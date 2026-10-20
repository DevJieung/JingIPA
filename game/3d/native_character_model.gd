extends Node3D
class_name NativeCharacterModel

## Native skinned character presentation. Battle events are read-only inputs.
##
## Pose composition per rendered sample (never accumulated between frames):
##   base   = IdleLoop(time) blended toward WalkLoop(distance phase) by speed
##   upper  = Attack(anticipation q = age / wind, release at 1.0 s, recovery) riding
##            on the base body delta while aiming, firing or recovering
##   gait   = planted legs and hip height re-solved by HeroLocomotion every sample
##            (heel -> toe rolling stance that never slides, swing clearance, flight
##            arc and strike settle by ground speed) on top of the clip's arms, torso
##            rhythm and timing; arm pump and lean at a run, hip roll at a heavy walk
##   lunge  = melee only: a visual step toward the cut on the release (root offset
##            re-added over the world's simulated position, never accumulated)
##   lean   = turn / acceleration / gait lean about the hips, plus the walk rock
##            (torso pitch at twice the cadence, roll at the cadence)
##   chunky = hands x1.20 / hand weapons x1.12 about the bone origin (bow, sword,
##            cast, tool heroes; never rifles or artillery)
##   fade   = cross-fade from the pose captured at the last state change
##   twist  = immediate upper-body yaw toward the aim direction (HeroLocomotion)
##   beats  = on the skeleton NODE, never on bones: the release pop (a volume-
##            preserving squash about the feet, zero on the release frame itself) and
##            the spawn pop-in (drop, grow, landing squash); identity outside battle
## Legs always come from the locomotion layer, so walking and attacking combine.
## Motion beats (2026-10-18, casual overhaul WP-D): the anticipation is a two-segment
## time warp into the clip's hold pose (HOLD_T per weapon kind) so every shot shows a
## held draw, then a 2-3 frame snap to the release; the release pops; walks rock the
## head and pump the arms; a placed hero drops in and lands. Numbers in docs/HERO_MOTION.md.
const MANIFEST := "res://art/models/native_heroes.json"
const ATTACK_RELEASE := 1.0      # seconds into the Attack clip where the release pose sits
const RECOVERY := 0.5            # seconds of release action after fire
const CANCEL_FADE := 0.25
const FIRE_FLASH := 0.13
const UPPER_FADE_OUT := 0.22
## Planted gait (2026-10-12): the authored WalkLoop keeps its arms, torso rhythm and
## timing, but the legs and the hip height come from HeroLocomotion so the planted
## sole rolls heel -> toe without sliding (hero_locomotion.gd). The sole reach ahead
## and behind the hip pivot follows the finisher's rig convention in height units;
## `motion.sole {toe, heel}` and `motion.leg_swing` in the manifest override it.
## At a run (5.1 u/s, spd 1.50) the arms pump 55 % more with 0.32 rad extra elbow
## flexion; a heavy walk (2.0 u/s, spd 0.60) adds hip roll.
const SOLE_TOE := 0.17
const SOLE_HEEL := 0.05
const SOLE_BAND := 0.012          # sole = skin within this fraction of the height above the floor
const RUN_ARM := 0.9
const RUN_ELBOW := 0.32
const WALK_ARM := 0.6            # share of the pump at a plain walk (walk_weight * WALK_ARM + run)
const PUMP_MAX := 1.2            # cap of walk + run so a sprint stays a swing, not a windmill
## Hold -> snap (H1): the aim progress q = age / wind is warped so the clip reaches its
## hold pose (HOLD_T, the clip time where the authored draw/wind-up is complete) at
## q = 0.65 with an ease-in, holds there, and runs the last clip stretch to the release
## pose over q 0.65 -> 1. `at == ATTACK_RELEASE` exactly at q == 1 (release contract).
const HOLD_T := {"bow": 0.86, "sword": 0.85, "tool": 0.85, "cast": 0.90, "artillery": 0.90, "rifle": 0.25, "gun": 0.25}
const HOLD_AT := 0.65
## Release pop (H2): a = POP_AMP on frames 1-2 after the release (plateau, in by 12 ms,
## out between 25 and 75 ms), then a -2 % rebound; zero at t = 0 so the release frame is
## the authored one and ~1 % at 65 ms where the socket checks sample.
const POP_AMP := 0.10
const POP_END := 0.22
## Spawn pop-in (H5): SPAWN_DROP world units above the ground falling with an ease-in,
## landing at SPAWN_LAND of SPAWN_SEC into a squash; the body grows 0.6 -> 1 with a
## back-out overshoot over the whole SPAWN_SEC.
const SPAWN_SEC := 0.35
const SPAWN_DROP := 0.6
const SPAWN_LAND := 0.8
## Walk rock (H3): torso pitch at twice the cadence, roll at the cadence, about the hip.
const ROCK_PITCH := 0.14
const ROCK_ROLL := 0.08
const ROCK_ROLL_SLOW := 0.025
## Chunky hands / weapons (H0), uniform about the bone origin (no shear on a flat rig).
const CHUNKY_HAND := 1.20
const CHUNKY_WEAPON := 1.12
const CHUNKY_KINDS := ["bow", "sword", "cast", "tool"]
static var _sole_cache: Dictionary = {}   # native id -> {"toe": u, "heel": u}, measured once
## Melee lunge (presentation only; the simulator's position and the damage moment do
## not move): the sword hero steps LUNGE_REACH toward the cut over the 3-frame strike
## (LUNGE_IN), holds through the follow-through and is back on its post by LUNGE_OUT,
## inside the 0.5 s recovery. Standing heroes plant the weapon-side leg forward.
const LUNGE_REACH := 0.17
const LUNGE_HOP := 0.045
const LUNGE_IN := 0.09
const LUNGE_HOLD := 0.20
const LUNGE_OUT := 0.46
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
var _height_scale := 1.0
var _lead := "R"                         # weapon hand (first release socket side)
var _melee := false
var _legs: Dictionary = {}               # side -> leg bone index
var _arm_chains: Dictionary = {}         # side -> [Arm, Forearm, Hand, Weapon] bone indices
var _arm_pump: Dictionary = {"L": 1.0, "R": 1.0}
var _lunge_applied := Vector3.ZERO
var _lunge_position := Vector3.INF
var _hold_t := 0.86
var _chunky: Dictionary = {}             # bone index -> uniform scale (H0)
## Arm chains (B1, 2026-10-19): the bones are parentless absolute controls, so sampling
## between clip keys, the idle/walk weight blend and the state cross-fade moved each bone on
## its own and pulled shoulders, elbows and wrists apart for a frame. _chain_order lists the
## arm bones parents first (Body -> Arm -> Forearm -> Hand -> Weapon); every sample
## re-seats each joint on its parent and the cross-fade runs in parent-relative space.
var _chain_order: Array[int] = []
var _chain_parent: Dictionary = {}       # bone -> parent bone (arm chains only)
var _chain_joint: Dictionary = {}        # bone -> its head in the parent's rest-local frame
var _hinge: Dictionary = {}              # side -> rest elbow hinge axis (skeleton space), as authored
var _skeleton_base := Transform3D.IDENTITY
var _spawn_clock := -INF                 # battle clock of the spawn event (H5), -INF when none

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
	_height_scale = float(_spec.get("height",1.65))/1.65
	var release_sockets: Array = _spec.get("sockets",[])
	_lead = "L" if not release_sockets.is_empty() and String(release_sockets[0].get("bone","")).ends_with("L") else "R"
	_melee = Balance.is_melee(Roster.unit_by_id(String(get_meta("native_id",""))))
	_arm_pump = _pump_multipliers()
	var kind := String(_spec.get("attack",""))
	_hold_t = float(HOLD_T.get(kind, 0.86))
	_skeleton_base = _skeleton.transform
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
	for side in ["L","R"]:
		var leg := _skeleton.find_bone("SkinLeg"+side)
		if leg >= 0: _legs[side] = leg
		var chain: Array[int] = []
		for part in ["Arm","Forearm","Hand","Weapon"]:
			var index := _skeleton.find_bone("Skin"+part+side)
			if index >= 0: chain.append(index)
		_arm_chains[side] = chain
		if kind in CHUNKY_KINDS:
			var hand := _skeleton.find_bone("SkinHand"+side)
			if hand >= 0: _chunky[hand] = CHUNKY_HAND
			var weapon := _skeleton.find_bone("SkinWeapon"+side)
			if weapon >= 0: _chunky[weapon] = CHUNKY_WEAPON
	_bind_chains()
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
	_bind_gait()
	_setup_flash()
	_collect_reactors(self)
	_composed = _rest.duplicate()
	animate_visual(0)
	# Stand-alone previews (portraits, review scenes) get the same per-instance
	# hit-flash/rim materials as world actors; already prepared instances are skipped.
	StellarShading.prepare_instance(self)

## Arm chains and elbow hinges from the rest skeleton (tools/3d/author_native_motion.py
## Rig._arm_geometry: anatomical hinge, flexion toward the front; a rest elbow bent more
## than 20 degrees keeps its modelled plane).
func _bind_chains() -> void:
	for side in ["L", "R"]:
		var chain: Array = _arm_chains.get(side, [])
		if chain.is_empty(): continue
		var parent := _body_bone
		for bone in chain:
			if parent >= 0:
				_chain_parent[bone] = parent
				_chain_joint[bone] = _rest[parent].affine_inverse()*_rest[bone].origin
			_chain_order.append(bone)
			parent = bone
		var arm := _skeleton.find_bone("SkinArm"+side)
		var fore := _skeleton.find_bone("SkinForearm"+side)
		var hand := _skeleton.find_bone("SkinHand"+side)
		if arm < 0 or fore < 0 or hand < 0: continue
		var a0 := (_rest[fore].origin-_rest[arm].origin).normalized()
		var f0 := (_rest[hand].origin-_rest[fore].origin).normalized()
		var m := (a0+f0).normalized()
		var p := Vector3.FORWARD-m*Vector3.FORWARD.dot(m)
		var n := m.cross(p.normalized()).normalized() if p.length() > 1e-6 else Vector3.RIGHT
		n = (n-f0*n.dot(f0)).normalized()
		if a0.angle_to(f0) > deg_to_rad(20.0): n = a0.cross(f0).normalized()
		_hinge[side] = n

## Re-seat each arm joint on its parent (positions only; rotations are untouched).
func _rechain(pose: Array[Transform3D]) -> void:
	for bone in _chain_order:
		if _chain_parent.has(bone):
			pose[bone].origin = pose[_chain_parent[bone]]*(_chain_joint[bone] as Vector3)

## Rig geometry for the planted gait: hip pivot height, sole reach and the authored
## leg swing amplitude (measured once from the WalkLoop unless the manifest states it).
func _bind_gait() -> void:
	var motion: Dictionary = _spec.get("motion", {})
	var h := float(_spec.get("height", 1.65))
	var sole: Dictionary = motion.get("sole", _measure_sole(h))
	# The heel reach is honoured as measured (HeroLocomotion shortens the front swing so a
	# rear-heavy sole lands under the body instead of rocking the hip up); the toe reach is
	# bounded because robe hems and flippers register as the front of the sole.
	var toe := clampf(float(sole.get("toe", SOLE_TOE * h)), 0.10 * h, 0.22 * h)
	var heel := clampf(float(sole.get("heel", SOLE_HEEL * h)), 0.0, 0.30 * h)
	var amplitude := float(motion.get("leg_swing", 0.0))
	if amplitude <= 0.0 and _clips[1] != null and _legs.has("L"):
		var i: int = _legs["L"]
		for n in range(16):
			var sampled := _sample(1, _length(1) * float(n) / 16.0)
			var q := (sampled[i].basis * _rest[i].basis.inverse()).get_rotation_quaternion()
			if q.w < 0.0: q = -q
			amplitude = maxf(amplitude, q.get_angle())
	if amplitude <= 0.0: amplitude = 0.62
	_loco.set_gait_geometry(_hip, toe, heel, amplitude)

## Sole reach ahead (toe) and behind (heel) the hip pivot, in model units, from the
## lowest leg-weighted skin vertices. Gear shifts the finisher's bounding-box centre,
## so the feet sit anywhere from 0.14 h to 0.26 h ahead of the pivot. Measured once per
## hero id: every vertex fails the cheap height test first, only the sole band looks
## up its bones, and the result is cached for every later instance.
func _measure_sole(h: float) -> Dictionary:
	var id := String(get_meta("native_id", ""))
	if _sole_cache.has(id): return _sole_cache[id]
	var result := {"toe": SOLE_TOE * h, "heel": SOLE_HEEL * h}
	var legs: Array = _legs.values()
	if legs.is_empty() or _skeleton == null:
		_sole_cache[id] = result
		return result
	var pivot_z := _rest[legs[0]].origin.z
	var band := SOLE_BAND * h
	var toe := 0.0
	var heel := 0.0
	var found := false
	for child in _skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null: continue
		var skin: Skin = mi.skin
		if skin == null: continue
		var leg_bind := PackedByteArray()
		leg_bind.resize(skin.get_bind_count())
		for b in skin.get_bind_count():
			var bone := skin.get_bind_bone(b)
			if bone < 0: bone = _skeleton.find_bone(skin.get_bind_name(b))
			leg_bind[b] = 1 if bone in legs else 0
		var local: Transform3D = mi.transform
		var identity: bool = local.is_equal_approx(Transform3D.IDENTITY)
		var mesh: Mesh = mi.mesh
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null: continue
			var per := 8 if (mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
			for k in verts.size():
				var v := verts[k]
				if v.y > band: continue
				if not identity:
					v = local * v
					if v.y > band: continue
				var best := 0.0
				var best_bind := -1
				for j in per:
					var w := float(weights[k * per + j])
					if w > best:
						best = w
						best_bind = int(bones[k * per + j])
				if best_bind < 0 or best_bind >= leg_bind.size() or leg_bind[best_bind] == 0: continue
				found = true
				toe = maxf(toe, pivot_z - v.z)
				heel = maxf(heel, v.z - pivot_z)
	if found: result = {"toe": toe, "heel": heel}
	_sole_cache[id] = result
	return result

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
	elif type == "spawn":
		# Placed on the field: the pop-in is a stateless function of time - _spawn_clock,
		# so the world must send it after the clock is set (it routes the event through
		# its pending queue, replayed right after animate_visual).
		_spawn_clock = _clock

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
		_spawn_clock = -INF
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
	var lunge := _lunge_curve(elapsed) if battle and _melee and _mode == 2 else 0.0
	_apply_lunge(lunge, elapsed, battle)
	var count := _skeleton.get_bone_count()
	var pose := _sample(0, fposmod(time, _length(0)))
	var weight := _loco.walk_weight()
	var phi := fposmod(_loco.walk_phase, 1.0)
	var run := 0.0
	var slow := 0.0
	if weight > 0.001 and _clips[1] != null:
		var walk := _sample(1, phi*_length(1))
		var idle_legs: Dictionary = {}
		for side in _legs: idle_legs[side] = pose[_legs[side]]
		for i in count: pose[i] = pose[i].interpolate_with(walk[i], weight)
		run = _loco.run_factor()*weight
		slow = _loco.slow_factor()*weight
		_plant_gait(pose, walk, idle_legs, weight)
		# Arms pump at a walk too (H4), more at a run; the attack layer below overrides
		# the upper body afterwards, so the release sockets stay exact.
		_pump_arms(pose, phi, minf(weight*WALK_ARM+run, PUMP_MAX))
	if lunge > 0.0 and weight < 0.5:
		# A standing cut steps into the target: weapon-side leg forward, the other braced.
		var stance := lunge*(1.0-weight*2.0)
		for side in _legs:
			var i: int = _legs[side]
			var angle := (0.42 if side == _lead else -0.22)*stance
			pose[i] = Transform3D(Basis(Vector3.RIGHT,angle)*pose[i].basis, pose[i].origin)
	if _mode == 1 or _mode == 2:
		var at := 0.0
		if _mode == 1:
			_aim_progress = clampf(age/raw_wind,0,1) if raw_wind>0 else 1.0
			at = ATTACK_RELEASE*warp_aim(_aim_progress, _hold_t)
		else:
			at = ATTACK_RELEASE+minf(elapsed,RECOVERY)
		var attack := _sample(2, minf(at, _length(2)))
		var body_delta := Transform3D.IDENTITY
		if _body_bone >= 0: body_delta = pose[_body_bone]*_rest[_body_bone].affine_inverse()
		for i in count:
			if _upper[i]: pose[i] = body_delta*attack[i]
	# Walk rock (H3): the torso nods twice per cycle (forward on each strike) and rolls
	# once; start/stop lag lean and the turn bank come from HeroLocomotion's springs.
	var lean_roll := _loco.lean_roll+(ROCK_ROLL+ROCK_ROLL_SLOW*slow)*weight*cos(TAU*(phi-0.1))
	var lean_pitch := _loco.lean_pitch+(_loco.gait_lean()+_loco.strike_nod())*weight+ROCK_PITCH*weight*cos(TAU*2.0*phi+0.3)
	if absf(lean_roll) > 0.0005 or absf(lean_pitch) > 0.0005:
		var hip := Vector3(0,_hip,0)
		var lean := Transform3D(Basis.from_euler(Vector3(lean_pitch,0,lean_roll)), Vector3.ZERO)
		lean = Transform3D(lean.basis, hip-lean.basis*hip)
		for i in count:
			if _upper[i]: pose[i] = lean*pose[i]
	_rechain(pose)
	# Chunky hands and weapons (H0): a uniform scale about the bone origin; the bones are
	# absolute controls, so nothing inherits it and nothing shears.
	for i in _chunky:
		pose[i] = Transform3D(pose[i].basis.scaled(Vector3.ONE*float(_chunky[i])), pose[i].origin)
	var blend := clampf((time-_blend_clock)/_blend_time,0,1) if _blend_time > 0.0 else 1.0
	if blend < 1.0 and _blend_from.size() == count:
		var eased := blend*blend*(3.0-2.0*blend)
		var target: Array[Transform3D] = pose.duplicate()
		for i in count:
			if not _chain_parent.has(i): pose[i] = _blend_from[i].interpolate_with(target[i], eased)
		# Arm chains blend parent-relative (an elbow hinge stays a hinge, joints stay seated).
		for i in _chain_order:
			if not _chain_parent.has(i): continue
			var p: int = _chain_parent[i]
			var from_local: Transform3D = _blend_from[p].affine_inverse()*_blend_from[i]
			var to_local: Transform3D = target[p].affine_inverse()*target[i]
			pose[i] = pose[p]*from_local.interpolate_with(to_local, eased)
	_composed = pose
	var twist := _loco.aim_delta
	if absf(twist) > 0.0005:
		var turn := Transform3D(Basis(Vector3.UP, twist), Vector3.ZERO)
		for i in count:
			_skeleton.set_bone_pose(i, turn*pose[i] if _upper[i] else pose[i])
	else:
		for i in count: _skeleton.set_bone_pose(i, pose[i])
	_apply_beats(time, elapsed, battle)
	_sync_controls_from_skin()
	_update_flash()

## Whole-body beats on the skeleton node (H2 release pop, H5 spawn pop-in), written
## every sample so the node is exactly its authored transform whenever no beat is on
## (previews, portraits, paused redraws). Both scale about the feet (the skeleton
## origin sits on the soles) and carry the five controls and the rank equipment along.
func _apply_beats(time: float, elapsed: float, battle: bool) -> void:
	var beat := Transform3D.IDENTITY
	if battle:
		if _mode == 2:
			var a := release_pop(elapsed)
			if a != 0.0: beat = Transform3D(Basis.from_scale(Vector3(1.0+a, 1.0-a, 1.0+a)), Vector3.ZERO)
		if _spawn_clock > -INF:
			var u := (time-_spawn_clock)/SPAWN_SEC
			if u >= 1.0 or u < 0.0: _spawn_clock = -INF
			else: beat = spawn_pop(u, SPAWN_DROP*_height_scale)*beat
	var target := _skeleton_base if beat == Transform3D.IDENTITY else _skeleton_base*beat
	if _skeleton.transform != target: _skeleton.transform = target

## Anticipation time warp (H1): clip time fraction for aim progress q in [0, 1].
static func warp_aim(q: float, hold_t: float) -> float:
	if q >= 1.0: return 1.0
	if q <= 0.0: return 0.0
	if q < HOLD_AT: return hold_t*pow(q/HOLD_AT, 1.8)
	return hold_t+(1.0-hold_t)*(q-HOLD_AT)/(1.0-HOLD_AT)

## Release pop amplitude (H2) at t seconds after the release: 0 on the release frame,
## POP_AMP on frames 1-2, out by 75 ms, a small rebound stretch until POP_END.
static func release_pop(t: float) -> float:
	if t <= 0.0 or t >= POP_END: return 0.0
	var squash := smoothstep(0.0, 0.012, t)*(1.0-smoothstep(0.025, 0.075, t))
	var rebound := 0.0
	if t > 0.075:
		var x := (t-0.075)/(POP_END-0.075)
		rebound = sin(PI*x)*sin(PI*x)
	return POP_AMP*squash-0.02*rebound

## Spawn pop-in (H5) at progress u in [0, 1): the body falls `drop` units with an
## ease-in and lands at SPAWN_LAND into a squash while it grows 0.6 -> 1 with one
## back-out overshoot (1.04 at u 0.58). Scale about the feet; identity at u = 1.
static func spawn_pop(u: float, drop: float) -> Transform3D:
	u = clampf(u, 0.0, 1.0)
	var fall := clampf(u/SPAWN_LAND, 0.0, 1.0)
	var lift := drop*(1.0-fall*fall)
	var grow := 0.6+0.4*_back_out(u, 1.7)
	var land := 0.0
	if u > 0.72:
		var x := (u-0.72)/0.28
		land = sin(PI*x)*sin(PI*x)
	var scale := Vector3(grow*(1.0+0.12*land), grow*(1.0-0.15*land), grow*(1.0+0.12*land))
	return Transform3D(Basis.from_scale(scale), Vector3(0.0, lift, 0.0))

static func _back_out(x: float, s: float = 1.5) -> float:
	x = clampf(x, 0.0, 1.0)-1.0
	return 1.0+x*x*((s+1.0)*x+s)

func _length(c: int) -> float:
	return _clips[c].length if _clips[c] != null else 1.0

## 0..1 step toward the cut from the release: snap in over the strike, hold through
## the follow-through, ease back before the recovery ends.
static func _lunge_curve(t: float) -> float:
	if t < LUNGE_IN:
		var x := t/LUNGE_IN
		return 1.0-(1.0-x)*(1.0-x)
	if t < LUNGE_HOLD: return 1.0
	var y := clampf((t-LUNGE_HOLD)/(LUNGE_OUT-LUNGE_HOLD),0.0,1.0)
	return 1.0-y*y*(3.0-2.0*y)

## The world writes `position` from the simulation before every animate_visual; the
## lunge is added on top of that value and taken off again first when the world has
## not reset it (event replays call animate_visual twice), so nothing accumulates.
func _apply_lunge(lunge: float, elapsed: float, battle: bool) -> void:
	var offset := Vector3.ZERO
	if lunge > 0.0 and battle:
		var heading := Basis(Vector3.UP, rotation.y+_loco.aim_delta)
		var hop := LUNGE_HOP*sin(PI*clampf(elapsed/(LUNGE_IN+0.07),0.0,1.0))
		offset = heading*Vector3(0.0, hop*_height_scale, -LUNGE_REACH*_height_scale*lunge)
	if _lunge_applied != Vector3.ZERO and position.is_equal_approx(_lunge_position): position -= _lunge_applied
	if offset != Vector3.ZERO: position += offset
	_lunge_applied = offset
	_lunge_position = position

## How much each arm swings in the authored walk (tools/3d/author_native_motion.py,
## walk_pose multipliers), so the run pump scales the same arms by the same ratio and
## never pulls a two-handed rifle grip apart.
func _pump_multipliers() -> Dictionary:
	var kind := String(_spec.get("attack",""))
	var grip := String(_spec.get("motion",{}).get("grip","none"))
	var mult := {"L":1.0,"R":1.0}
	match kind:
		"bow": mult[_lead] = 0.45
		"sword": mult[_lead] = 0.7
		"rifle":
			if grip == "two_hand": mult = {"L":0.0,"R":0.0}
			elif grip == "dual": mult = {"L":0.7,"R":0.7}
			else: mult[_lead] = 0.5
		"cast": mult = {"L":0.9,"R":0.9}
		"artillery": mult = {"L":0.75,"R":0.75}
		"tool": mult = {"L":0.8,"R":0.8}
	return mult

## Planted legs (presentation only, recomputed every sample): the sampled walk keeps
## its arms, torso rhythm and timing; each leg takes the hip angle and swing lift that
## HeroLocomotion solved for this phase (heel strike ahead, heel -> toe roll with the
## sole fixed on the ground, push-off behind, clearance in the swing), blended from
## the idle leg by the walk weight, and the whole upper body moves to the hip height
## that keeps the planted sole on the ground in place of the clip's vault.
func _plant_gait(pose: Array[Transform3D], walk: Array[Transform3D], idle_legs: Dictionary, weight: float) -> void:
	var vault := 0.0
	if _body_bone >= 0: vault = walk[_body_bone].origin.y-_rest[_body_bone].origin.y
	var hip := _loco.body_height()
	var shift := weight*(hip-vault)
	var legs: Array = _legs.values()
	for i in pose.size():
		if not (i in legs): pose[i].origin.y += shift
	# The bones are absolute controls (no parent chain): the hip pivots must ride the
	# same height as the body, so the leg origins carry the hip offset plus the swing lift.
	for side in _legs:
		var i: int = _legs[side]
		var st := _loco.leg_state(side)
		var rest := _rest[i]
		var planted := Transform3D(Basis(Vector3.RIGHT, float(st["angle"]))*rest.basis, rest.origin+Vector3(0, hip+float(st["lift"]), 0))
		pose[i] = (idle_legs[side] as Transform3D).interpolate_with(planted, weight)

func _pump_arms(pose: Array[Transform3D], phi: float, run: float) -> void:
	var axis := Vector3.RIGHT
	if _body_bone >= 0: axis = (pose[_body_bone].basis*Vector3.RIGHT).normalized()
	for side in _arm_chains:
		var chain: Array = _arm_chains[side]
		var mult := float(_arm_pump.get(side,1.0))
		if chain.is_empty() or mult <= 0.0: continue
		var swing := -0.48*cos(TAU*phi)*(1.0 if side == "L" else -1.0)*mult*RUN_ARM*run
		var shoulder: Vector3 = pose[chain[0]].origin
		var turn := Basis(axis, swing)
		var about_shoulder := Transform3D(turn, shoulder-turn*shoulder)
		for i in chain: pose[i] = about_shoulder*pose[i]
		if chain.size() > 1:
			var elbow: Vector3 = pose[chain[1]].origin
			# The elbow flexes about its own hinge carried by the upper arm (B1: the body's X
			# axis spun the forearm about itself by up to 0.4 rad of pump).
			var hinge := axis
			if _hinge.has(side):
				hinge = ((pose[chain[0]].basis.orthonormalized()*_rest[chain[0]].basis.orthonormalized().inverse())*(_hinge[side] as Vector3)).normalized()
			var flex := Basis(hinge, RUN_ELBOW*run*mult)
			var about_elbow := Transform3D(flex, elbow-flex*elbow)
			for n in range(1, chain.size()): pose[chain[n]] = about_elbow*pose[chain[n]]

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
