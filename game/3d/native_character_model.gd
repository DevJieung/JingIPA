extends Node3D
class_name NativeCharacterModel

## Native skinned character presentation. Battle events are read-only inputs.
const MANIFEST := "res://art/models/native_heroes.json"
static var _manifest: Dictionary = {}
static var _flash_mesh: SphereMesh
var _spec: Dictionary = {}
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _idle := ""
var _attack := ""
var _bindings: Array[Dictionary] = []
var _socket_bones: Array[int] = []
var _socket_rest: Array[Transform3D] = []
var _flashes: Array[MeshInstance3D] = []
var _reactor_materials: Array[StandardMaterial3D] = []
var _clock := 0.0
var _phase_clock := 0.0
var _mode := 0
var _wind := 0.0
var _fire_strength := 0.0
var _blend_clock := -9.0
var _blend_from: Array[Transform3D] = []

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
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null: continue
			mat.metallic_specular = 0.16
			mat.clearcoat_enabled = false
			if mat.albedo_texture != null:
				mat.roughness_texture = null
				mat.metallic_texture = null
				mat.roughness = 0.84
				mat.metallic = metal
			var arrays: Array = node.mesh.surface_get_arrays(i)
			if arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty():
				mat.vertex_color_use_as_albedo = true
				mat.vertex_color_is_srgb = false
	for child in node.get_children(): _style(child,metal)

func _ready() -> void:
	_spec = manifest().get("heroes",{}).get(String(get_meta("native_id","")),{})
	_skeleton = _find_type(self,"Skeleton3D") as Skeleton3D
	_player = _find_type(self,"AnimationPlayer") as AnimationPlayer
	if _skeleton == null or _player == null:
		push_error("Native character requires actual skin and motion clips")
		return
	for name in _player.get_animation_list():
		if String(name).ends_with("IdleLoop"): _idle = name
		if String(name).ends_with("Attack"): _attack = name
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
	animate_visual(0)

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

func visual_event(e: Dictionary) -> void:
	var type := String(e.get("t",""))
	if type == "retarget": return # Root bridge updates actual facing.
	if type == "aim":
		_capture_transition()
		_mode = 1
		_wind = maxf(0.0,float(e.get("w",0.0)))
		_fire_strength = 0.0
		_phase_clock = _clock
	elif type == "fire":
		_capture_transition()
		_mode = 2
		_phase_clock = _clock
		_fire_strength = 1.0
		if _wind<=0.04: _blend_clock = _clock-0.045
		_update_flash()
	elif type == "cancel":
		_capture_transition()
		_mode = 3
		_phase_clock = _clock

func _capture_transition() -> void:
	_blend_clock = _clock
	_blend_from.clear()
	if _skeleton != null:
		for i in _skeleton.get_bone_count(): _blend_from.append(_skeleton.get_bone_pose(i))

func animate_visual(time: float, age: float = 9.0, raw_wind: float = 0.0, battle: bool = false) -> void:
	_clock = time
	if _player == null or _skeleton == null: return
	if not battle:
		_mode = 0
		_fire_strength = 0.0
	var elapsed := maxf(0,time-_phase_clock)
	if _mode == 1 and age > maxf(raw_wind,0.0)+0.04:
		_capture_transition()
		_mode = 3
		_phase_clock = time
		elapsed = 0
	if _mode in [2,3] and elapsed >= 0.30: _mode = 0
	if _mode == 0:
		_sample(_idle,fposmod(time,6.0))
	elif _mode == 1:
		var q := clampf(age/raw_wind,0,1) if raw_wind>0 else 1.0
		_sample(_attack,q)
	else:
		_sample(_attack,1.0+minf(elapsed,0.30))
	_fire_strength = maxf(0,1.0-elapsed/0.13) if _mode==2 else 0.0
	var blend := clampf((time-_blend_clock)/0.045,0,1)
	if blend<1 and _blend_from.size()==_skeleton.get_bone_count():
		for i in _skeleton.get_bone_count():
			_skeleton.set_bone_pose(i,_blend_from[i].interpolate_with(_skeleton.get_bone_pose(i),blend))
	_sync_controls_from_skin()
	_update_flash()

func _sample(clip: String, value: float) -> void:
	if clip == "": return
	if _player.current_animation != clip: _player.play(clip)
	_player.seek(value,true)
	_player.pause()

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

func _setup_flash() -> void:
	if _flash_mesh == null:
		_flash_mesh = SphereMesh.new()
		_flash_mesh.radius = 0.055
		_flash_mesh.height = 0.11
		_flash_mesh.radial_segments = 8
		_flash_mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(String(_spec.get("effect_color","#9de8ff")))
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
		var artillery := String(_spec.get("attack","")) == "artillery"
		if artillery: mouth.origin += mouth.basis*Vector3(0,0,-0.06)
		_flashes[n].transform = mouth
		_flashes[n].scale = (Vector3(0.9,0.9,3.2) if artillery else Vector3(0.5,0.5,1.5))*maxf(_fire_strength,0.01)
		_flashes[n].visible = _fire_strength>0.01

static func _find_type(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find_type(child,type)
		if found != null: return found
	return null
