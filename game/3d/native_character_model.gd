extends Node3D
class_name NativeCharacterModel

## Native skinned character presentation. Battle events are read-only inputs.
##
## Pose composition per rendered sample (never accumulated between frames):
##   base   = IdleLoop(time) blended toward WalkLoop(distance phase) by speed
##   upper  = Attack(anticipation q = age / wind, release at 1.0 s, recovery) riding
##            on the base body delta while aiming, firing or recovering
##   lean   = turn / acceleration lean about the hips
##   fade   = cross-fade from the pose captured at the last state change
##   twist  = immediate upper-body yaw toward the aim direction (HeroLocomotion)
## Legs always come from the locomotion layer, so walking and attacking combine.
const MANIFEST := "res://art/models/native_heroes.json"
const ATTACK_RELEASE := 1.0      # seconds into the Attack clip where the release pose sits
const RECOVERY := 0.5            # seconds of release action after fire
const CANCEL_FADE := 0.25
const FIRE_FLASH := 0.13
const UPPER_FADE_OUT := 0.22
static var _manifest: Dictionary = {}
static var _flash_mesh: SphereMesh
var _spec: Dictionary = {}
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _clips: Array[Animation] = []        # 0 idle, 1 walk, 2 attack (null when absent)
var _tracks: Array = []                  # per clip: Array of [pos, rot, scale] track indices per bone
var _rest: Array[Transform3D] = []
var _upper: Array[bool] = []
var _body_bone := -1
var _bindings: Array[Dictionary] = []
var _socket_bones: Array[int] = []
var _socket_rest: Array[Transform3D] = []
var _flashes: Array[MeshInstance3D] = []
var _reactor_materials: Array[StandardMaterial3D] = []
var _loco := HeroLocomotion.new()
var _clock := 0.0
var _phase_clock := 0.0
var _mode := 0
var _wind := 0.0
var _fire_strength := 0.0
var _blend_clock := -9.0
var _blend_time := 0.1
var _blend_from: Array[Transform3D] = []
var _composed: Array[Transform3D] = []
var _hip := 0.48
var _artillery := false
var _aim_progress := 0.0

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary: _manifest = parsed
	return _manifest

static func has_model(id: String) -> bool:
	var m := manifest()
	return id in m.get("ready_ids",[]) and m.get("heroes",{}).has(id) and ResourceLoader.exists(String(m["heroes"][id]["path"]))

static func create(id: String) -> Node3D:
	# QA may instantiate a candidate before ready_ids publishes it. Production
	# dispatch must call has_model() first, so raw inference never ships as ready.
	var row: Dictionary = manifest().get("heroes",{}).get(id,{})
	if row.is_empty(): return null
	var scene := load(String(row["path"])) as PackedScene
	if scene == null: return null
	var root := scene.instantiate() as Node3D
	if root.get_node_or_null("Body") == null:
		var body := root.find_child("Body",true,false)
		if body == null:
			root.free()
			return null
		var inner := body.get_parent() as Node3D
		inner.get_parent().remove_child(inner)
		root.free()
		root = inner
	root.set_script(load("res://game/3d/native_character_model.gd"))
	root.set_meta("native_id",id)
	root.set_meta("model_source",String(row["path"]))
	_style(root,float(row.get("metallic",0.0)))
	return root

static func _style(node: Node, metal: float) -> void:
	StellarShading.style(node, metal)

func _ready() -> void:
	_spec = manifest().get("heroes",{}).get(String(get_meta("native_id","")),{})
	_skeleton = _find_type(self,"Skeleton3D") as Skeleton3D
	_player = _find_type(self,"AnimationPlayer") as AnimationPlayer
	if _skeleton == null or _player == null:
		push_error("Native character requires actual skin and motion clips")
		return
	_artillery = String(_spec.get("attack","")) == "artillery"
	_hip = float(_spec.get("height",1.65))*0.29
	_loco.stride = float(_spec.get("motion",{}).get("stride",1.5))
	var names := {"IdleLoop":"","WalkLoop":"","Attack":""}
	for name in _player.get_animation_list():
		for suffix in names.keys():
			if String(name).ends_with(suffix): names[suffix] = String(name)
	_clips.resize(3)
	_tracks.resize(3)
	var count := _skeleton.get_bone_count()
	for i in count:
		_rest.append(_skeleton.get_bone_rest(i))
		var bone := _skeleton.get_bone_name(i)
		_upper.append(not bone.begins_with("SkinLeg"))
		if bone == "SkinBody": _body_bone = i
	var order := ["IdleLoop","WalkLoop","Attack"]
	for c in 3:
		var clip: Animation = _player.get_animation(names[order[c]]) if names[order[c]] != "" else null
		_clips[c] = clip
		var map: Array = []
		for i in count: map.append([-1,-1,-1])
		if clip != null:
			for t in clip.get_track_count():
				var path := clip.track_get_path(t)
				if path.get_subname_count() < 1: continue
				var bone := _skeleton.find_bone(String(path.get_subname(0)))
				if bone < 0: continue
				match clip.track_get_type(t):
					Animation.TYPE_POSITION_3D: map[bone][0] = t
					Animation.TYPE_ROTATION_3D: map[bone][1] = t
					Animation.TYPE_SCALE_3D: map[bone][2] = t
		_tracks[c] = map
	var skeleton_to_root := global_transform.affine_inverse()*_skeleton.global_transform
	for name in ["Body","ArmL","ArmR","LegL","LegR"]:
		var index := _skeleton.find_bone("Skin"+name)
		if index < 0: continue
		var control: Node3D = get_node(name)
		_bindings.append({"index":index,"control":control,"bind":control.transform,
			"rest":skeleton_to_root*_skeleton.get_bone_global_rest(index)})
	for socket in _spec.get("sockets",[]):
		var index := _skeleton.find_bone(String(socket["bone"]))
		if index < 0: continue
		var xyz: Array = socket["point"]
		var rotation: Array = socket.get("rotation_xyz",[0.0,0.0,0.0])
		_socket_bones.append(index)
		# rotation_xyz is authored as Blender XYZ Euler, not Godot's YXZ default.
		var basis := Basis.from_euler(Vector3(float(rotation[0]),float(rotation[1]),float(rotation[2])),EULER_ORDER_XYZ)
		_socket_rest.append(Transform3D(basis,Vector3(float(xyz[0]),float(xyz[1]),float(xyz[2]))))
	_setup_flash()
	_collect_reactors(self)
	_composed = _rest.duplicate()
	animate_visual(0)
	# Stand-alone previews (portraits, review scenes) get the same per-instance
	# hit-flash/rim materials as world actors; already prepared instances are skipped.
	StellarShading.prepare_instance(self)

func _collect_reactors(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(i) as StandardMaterial3D
			if material == null or not String(material.resource_name).contains("NativeReactorAmber"): continue
			var instance := material.duplicate() as StandardMaterial3D
			instance.emission_enabled = true
			instance.emission = Color("#ff6509")
			instance.emission_energy_multiplier = 0.18
			node.set_surface_override_material(i,instance)
			_reactor_materials.append(instance)
	for child in node.get_children(): _collect_reactors(child)

## --- world inputs -----------------------------------------------------------
func set_locomotion(velocity: Vector3, dt: float) -> void:
	_loco.set_locomotion(velocity, dt)

func face_toward(direction: Vector2, dt: float) -> void:
	_loco.face_toward(direction, dt)

func visual_event(e: Dictionary) -> void:
	var type := String(e.get("t",""))
	if type == "retarget": return # Root bridge updates actual facing.
	if type == "aim":
		# The anticipation must be fully blended in before the actual release, so
		# the fade never outlasts the aim window; a zero-wind shot snaps at once.
		_wind = maxf(0.0,float(e.get("w",0.0)))
		_capture_transition(minf(0.16 if _mode == 0 else 0.08, _wind*0.6))
		_mode = 1
		_fire_strength = 0.0
		_phase_clock = _clock
		_aim_progress = 0.0
	elif type == "fire":
		# Continuous when the anticipation reached its hold pose and its fade has
		# finished; otherwise a short fade from whatever is on screen.
		var settled := _mode == 1 and _aim_progress >= 0.98 and _clock-_blend_clock >= _blend_time
		if not settled: _capture_transition(0.05)
		_mode = 2
		_phase_clock = _clock
		_fire_strength = 1.0
		_update_flash()
	elif type == "cancel":
		_capture_transition(CANCEL_FADE)
		_mode = 3
		_phase_clock = _clock

func _capture_transition(duration: float) -> void:
	_blend_clock = _clock
	_blend_time = duration
	_blend_from = _composed.duplicate()

## --- per-sample composition -------------------------------------------------
func animate_visual(time: float, age: float = 9.0, raw_wind: float = 0.0, battle: bool = false) -> void:
	var clock_dt := clampf(time-_clock, 0.0, 0.1)
	_clock = time
	if _player == null or _skeleton == null: return
	if not battle:
		_mode = 0
		_fire_strength = 0.0
		_loco.clear_battle()
		_loco.sync_yaw(rotation.y)
	var elapsed := maxf(0,time-_phase_clock)
	if _mode == 1 and age > maxf(raw_wind,0.0)+0.04:
		_capture_transition(CANCEL_FADE)
		_mode = 3
		_phase_clock = time
		elapsed = 0
	if _mode == 2 and elapsed >= RECOVERY:
		_capture_transition(UPPER_FADE_OUT)
		_mode = 0
	if _mode == 3 and elapsed >= 0.30: _mode = 0
	_fire_strength = maxf(0,1.0-elapsed/FIRE_FLASH) if _mode==2 else 0.0
	if battle and _loco.update(clock_dt): rotation.y = _loco.yaw
	var count := _skeleton.get_bone_count()
	var pose := _sample(0, fposmod(time, _length(0)))
	var weight := _loco.walk_weight()
	if weight > 0.001 and _clips[1] != null:
		var walk := _sample(1, fposmod(_loco.walk_phase, 1.0)*_length(1))
		for i in count: pose[i] = pose[i].interpolate_with(walk[i], weight)
	if _mode == 1 or _mode == 2:
		var at := 0.0
		if _mode == 1:
			_aim_progress = clampf(age/raw_wind,0,1) if raw_wind>0 else 1.0
			at = ATTACK_RELEASE*_aim_progress
		else:
			at = ATTACK_RELEASE+minf(elapsed,RECOVERY)
		var attack := _sample(2, minf(at, _length(2)))
		var body_delta := Transform3D.IDENTITY
		if _body_bone >= 0: body_delta = pose[_body_bone]*_rest[_body_bone].affine_inverse()
		for i in count:
			if _upper[i]: pose[i] = body_delta*attack[i]
	var lean_roll := _loco.lean_roll
	var lean_pitch := _loco.lean_pitch
	if absf(lean_roll) > 0.0005 or absf(lean_pitch) > 0.0005:
		var hip := Vector3(0,_hip,0)
		var lean := Transform3D(Basis.from_euler(Vector3(lean_pitch,0,lean_roll)), Vector3.ZERO)
		lean = Transform3D(lean.basis, hip-lean.basis*hip)
		for i in count:
			if _upper[i]: pose[i] = lean*pose[i]
	var blend := clampf((time-_blend_clock)/_blend_time,0,1) if _blend_time > 0.0 else 1.0
	if blend < 1.0 and _blend_from.size() == count:
		var eased := blend*blend*(3.0-2.0*blend)
		for i in count: pose[i] = _blend_from[i].interpolate_with(pose[i], eased)
	_composed = pose
	var twist := _loco.aim_delta
	if absf(twist) > 0.0005:
		var turn := Transform3D(Basis(Vector3.UP, twist), Vector3.ZERO)
		for i in count:
			_skeleton.set_bone_pose(i, turn*pose[i] if _upper[i] else pose[i])
	else:
		for i in count: _skeleton.set_bone_pose(i, pose[i])
	_sync_controls_from_skin()
	_update_flash()

func _length(c: int) -> float:
	return _clips[c].length if _clips[c] != null else 1.0

func _sample(c: int, at: float) -> Array[Transform3D]:
	var result: Array[Transform3D] = _rest.duplicate()
	var clip := _clips[c]
	if clip == null: return result
	var map: Array = _tracks[c]
	for i in result.size():
		var tracks: Array = map[i]
		if tracks[0] < 0 and tracks[1] < 0 and tracks[2] < 0: continue
		var origin: Vector3 = clip.position_track_interpolate(tracks[0], at) if tracks[0] >= 0 else _rest[i].origin
		var rotation: Quaternion = clip.rotation_track_interpolate(tracks[1], at) if tracks[1] >= 0 else _rest[i].basis.get_rotation_quaternion()
		var scale: Vector3 = clip.scale_track_interpolate(tracks[2], at) if tracks[2] >= 0 else _rest[i].basis.get_scale()
		result[i] = Transform3D(Basis(rotation).scaled(scale), origin)
	return result

func _sync_controls_from_skin() -> void:
	var skeleton_to_root := global_transform.affine_inverse()*_skeleton.global_transform
	for binding in _bindings:
		var delta: Transform3D = skeleton_to_root*_skeleton.get_bone_global_pose(int(binding["index"]))*binding["rest"].affine_inverse()
		var control: Node3D = binding["control"]
		control.transform = delta*binding["bind"]

func update_visuals() -> void:
	# Preserve the public five-control contract for manual preview/test poses.
	if _skeleton == null: return
	var root_to_skeleton := _skeleton.global_transform.affine_inverse()*global_transform
	for binding in _bindings:
		var control: Node3D = binding["control"]
		var target: Transform3D = root_to_skeleton*control.transform*binding["bind"].affine_inverse()*binding["rest"]
		_skeleton.set_bone_pose(int(binding["index"]),target)
	_update_flash()

func weapon_transform(side: int = -1) -> Transform3D:
	if _socket_bones.is_empty(): return global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1,-0.25))
	var n := 0 if side<0 else mini(1,_socket_bones.size()-1)
	return _socket_transform(n)

func _socket_transform(n: int) -> Transform3D:
	var index := _socket_bones[n]
	var skeleton_to_root := global_transform.affine_inverse()*_skeleton.global_transform
	var rest := skeleton_to_root*_skeleton.get_bone_global_rest(index)
	var delta := skeleton_to_root*_skeleton.get_bone_global_pose(index)*rest.affine_inverse()
	return global_transform*delta*_socket_rest[n]

func fire_strength() -> float: return _fire_strength
func visual_phase() -> int: return _mode
func walk_weight() -> float: return _loco.walk_weight()
func aim_twist() -> float: return _loco.aim_delta

func _setup_flash() -> void:
	# A small soft core at the release socket. The actual muzzle flash, projectile
	# and impact are drawn by the world VFX from weapon_transform()/fire_strength().
	if _flash_mesh == null:
		_flash_mesh = SphereMesh.new()
		_flash_mesh.radius = 0.055
		_flash_mesh.height = 0.11
		_flash_mesh.radial_segments = 8
		_flash_mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var color := Color(String(_spec.get("effect_color","#9de8ff")))
	color.a = 0.7
	mat.albedo_color = color
	for n in maxi(1,_socket_bones.size()):
		var mesh := MeshInstance3D.new()
		mesh.name = "NativeRelease"+str(n)
		mesh.mesh = _flash_mesh
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = false
		add_child(mesh)
		_flashes.append(mesh)

func _update_flash() -> void:
	for material in _reactor_materials:
		material.emission_energy_multiplier = 0.18+0.9*_fire_strength
	for n in _flashes.size():
		var mouth := global_transform.affine_inverse()*(_socket_transform(n) if n<_socket_bones.size() else weapon_transform())
		if _artillery: mouth.origin += mouth.basis*Vector3(0,0,-0.06)
		_flashes[n].transform = mouth
		_flashes[n].scale = (Vector3(0.45,0.45,1.6) if _artillery else Vector3(0.26,0.26,0.8))*maxf(_fire_strength,0.01)
		_flashes[n].visible = _fire_strength>0.01

static func _find_type(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find_type(child,type)
		if found != null: return found
	return null
