extends Node3D
class_name NativeMonsterModel

## Native creature presentation. BattleSim/ArenaSim own every position, timer
## and damage value; this node turns the simulator's forward-only clock plus a
## few visual events into body motion.
##
## Pose = blend(IdleLoop, MoveLoop, Attack, Die) sampled straight from the
## authored GLB clips, plus reaction layers on the rig pivot (spawn, hit
## squash/recoil, stumble, daze, turn banking, death topple/sink). Nothing
## accumulates per frame: blends, standing time and reactions advance only by
## the dt the world passes to face_toward/advance_death or by motion_time
## differences, so a paused simulator (dt 0, unchanged clock) redraws the same
## pose and two instances fed the same inputs pose identically.
const MANIFEST := "res://art/models/native_monsters.json"
const FADE := 0.18          # idle/move/attack crossfade seconds
const DEATH_FADE := 0.08
const SPAWN_SEC := 0.45
const ATTACK_SHIFT := 0.3   # Attack clip time = (siege phase - 0.3) mod 1 → strike at the wrap
const EPS := 0.0005
static var _manifest: Dictionary = {}

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _pivot: Node3D
var _pivot_base := Transform3D.IDENTITY
var _height := 1.0
var _shape := "biped"
var _motion: Dictionary = {}
var _bone_count := 0
var _rest_pos := PackedVector3Array()
var _rest_rot: Array[Quaternion] = []
var _rest_scale := PackedVector3Array()
var _clips: Dictionary = {}
var _head := -1
var _body := -1
var _acc_pos := PackedVector3Array()
var _acc_rot: Array[Quaternion] = []
var _acc_scale := PackedVector3Array()
var _acc_w := 0.0
var _bind_failed := false

# Presentation state (see class comment for the clocks that may advance it).
var _started := false
var _last_motion := 0.0
var _stand_t := 0.0
var _pending_dt := 0.0
var _w_idle := 0.0
var _w_move := 1.0
var _w_attack := 0.0
var _w_die := 0.0
var _siege := -1.0
var _siege_phase := 0.0
var _flash := 0.0
var _hit_scale := 1.0
var _recoil := Vector3.ZERO
var _yaw_ready := false
var _yaw := 0.0
var _yaw_rate := 0.0
var _bank := 0.0
var _spawn_t := -1.0
var _stumble := 0.0
var _daze := 0.0
var _dying := false
var _death_kind := ""
var _death_t := 0.0
var _dissolve := -1.0

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary: _manifest = parsed
	return _manifest

static func has_model(id: String) -> bool:
	var data := manifest()
	return id in data.get("ready_ids",[]) and data.get("monsters",{}).has(id) and ResourceLoader.exists(String(data["monsters"][id]["path"]))

static func create(id: String) -> Node3D:
	var row: Dictionary = manifest().get("monsters",{}).get(id,{})
	if row.is_empty(): return null
	var packed := load(String(row["path"])) as PackedScene
	if packed == null: return null
	var root := packed.instantiate() as Node3D
	root.set_script(load("res://game/3d/native_monster_model.gd"))
	root.set_meta("_stellar_native_monster",true)
	root.set_meta("_stellar_monster_id",id)
	root.set_meta("_stellar_height",float(row.get("height",1.0)))
	root.set_meta("_stellar_shape",String(row.get("shape","biped")))
	root.set_meta("_stellar_motion",row.get("motion",{}))
	root.set_meta("model_source",String(row["path"]))
	StellarShading.style(root,float(row.get("metallic",0.0)))
	StellarShading.prepare_instance(root)
	_setup_status(root,float(row.get("height",1.0)))
	var player := _find_type(root,"AnimationPlayer") as AnimationPlayer
	if player != null:
		for clip in player.get_animation_list():
			if String(clip).ends_with("IdleLoop") or String(clip).ends_with("MoveLoop") or String(clip).ends_with("Attack"):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return root

## Status marks are the shared StellarVfx implementation (same node names, shared
## mesh and material, battle-clock synced). The world drives their visibility,
## scale and rotation.y as direct children; they start hidden.
static func _setup_status(root: Node3D, height: float) -> void:
	for status in ["Burn","Frost","Stun"]:
		var group := StellarVfx.status_group(status,height)
		group.name = "Stellar"+status
		group.visible = false
		root.add_child(group)

func _ready() -> void:
	if not _bind():
		push_error("Native monster requires actual skin and authored motion clips")
		return
	# Formation/preview screens show the first walking frame until the world drives the clock.
	_compose(0.0)
	_apply_skeleton()
	_apply_pivot()

## Resolve skeleton, clips and rest poses once. Never creates nodes or resources.
func _bind() -> bool:
	if _skeleton != null: return true
	if _bind_failed: return false
	_skeleton = _find_type(self,"Skeleton3D") as Skeleton3D
	_player = _find_type(self,"AnimationPlayer") as AnimationPlayer
	if _skeleton == null or _player == null:
		_bind_failed = true
		return false
	_pivot = _skeleton.get_parent() as Node3D
	if _pivot == null or _pivot == self: _pivot = _skeleton
	_pivot_base = _pivot.transform
	_height = float(get_meta("_stellar_height",1.0))
	_shape = String(get_meta("_stellar_shape","biped"))
	var motion = get_meta("_stellar_motion",{})
	_motion = motion if motion is Dictionary else {}
	_bone_count = _skeleton.get_bone_count()
	_rest_pos.resize(_bone_count)
	_rest_scale.resize(_bone_count)
	_rest_rot.resize(_bone_count)
	_acc_pos.resize(_bone_count)
	_acc_scale.resize(_bone_count)
	_acc_rot.resize(_bone_count)
	for i in _bone_count:
		var rest := _skeleton.get_bone_rest(i)
		_rest_pos[i] = rest.origin
		_rest_rot[i] = rest.basis.get_rotation_quaternion()
		_rest_scale[i] = rest.basis.get_scale()
	_head = _skeleton.find_bone("Head")
	_body = _skeleton.find_bone("Body")
	for name in _player.get_animation_list():
		for key in ["IdleLoop","MoveLoop","Attack","Die"]:
			if String(name).ends_with(key):
				var animation := _player.get_animation(name)
				# glTF stores keyframes but no loop flag; authored endpoint-matched loops.
				if key != "Die": animation.loop_mode = Animation.LOOP_LINEAR
				_clips[key] = _bind_clip(animation)
	return _clips.has("IdleLoop") and _clips.has("MoveLoop")

func _bind_clip(animation: Animation) -> Dictionary:
	var pos := PackedInt32Array()
	var rot := PackedInt32Array()
	var scl := PackedInt32Array()
	pos.resize(_bone_count); pos.fill(-1)
	rot.resize(_bone_count); rot.fill(-1)
	scl.resize(_bone_count); scl.fill(-1)
	for t in animation.get_track_count():
		var path := animation.track_get_path(t)
		if path.get_subname_count() == 0: continue
		var bone := _skeleton.find_bone(String(path.get_subname(0)))
		if bone < 0: continue
		match animation.track_get_type(t):
			Animation.TYPE_POSITION_3D: pos[bone] = t
			Animation.TYPE_ROTATION_3D: rot[bone] = t
			Animation.TYPE_SCALE_3D: scl[bone] = t
	return {"anim": animation, "len": maxf(animation.length,0.001), "pos": pos, "rot": rot, "scl": scl}

# --------------------------------------------------------------------------- #
# World contract
# --------------------------------------------------------------------------- #
## motion_time: simulator clock (+phase) that already includes pause, slow, stun
## and battle speed. moving=false while stunned, blocked or sieging.
func animate_visual(motion_time: float, moving: bool = true) -> void:
	if not _bind() or _dying: return
	if not _started:
		# The first sample is a pure function of the simulator clock.
		_pending_dt = 0.0
		_stand_t = 0.0
	var step := maxf(_pending_dt, absf(motion_time-_last_motion)) if _started else 0.0
	_stand_t += _pending_dt
	if _clips.has("IdleLoop"): _stand_t = fposmod(_stand_t, float(_clips["IdleLoop"]["len"]))
	_pending_dt = 0.0
	_last_motion = motion_time
	var attack := not moving and _siege >= 0.0 and _clips.has("Attack")
	var target_move := 1.0 if moving else 0.0
	var target_attack := 1.0 if attack else 0.0
	var target_idle := 0.0 if (moving or attack) else 1.0
	if not _started:
		_started = true
		_w_move = target_move
		_w_attack = target_attack
		_w_idle = target_idle
	elif step > 0.0:
		var k := step/FADE
		_w_move = move_toward(_w_move,target_move,k)
		_w_attack = move_toward(_w_attack,target_attack,k)
		_w_idle = move_toward(_w_idle,target_idle,k)
		if _spawn_t >= 0.0:
			_spawn_t += step
			if _spawn_t >= SPAWN_SEC: _spawn_t = -1.0
		_stumble = maxf(0.0,_stumble-step/0.4)
		var dazed := is_instance_valid(_stun_group()) and _stun_group().visible
		_daze = move_toward(_daze,1.0 if dazed else 0.0,step/0.25)
	_compose(motion_time)
	_apply_skeleton()
	_apply_pivot()

## Smooth turning toward a logical direction (+y south). dt 0 holds the body;
## the first call snaps so a fresh spawn never starts mid-turn.
func face_toward(direction: Vector2, dt: float) -> void:
	if direction.length_squared() <= 0.000001: return
	if dt > 0.0: _pending_dt = maxf(_pending_dt,dt)
	var target := atan2(-direction.x,-direction.y)
	if not _yaw_ready:
		_yaw_ready = true
		_yaw = target
		rotation.y = target
		return
	if dt <= 0.0 or _dying: return
	var diff := angle_difference(_yaw,target)
	var rate := float(_motion.get("turn_rate",8.0))
	var limit := float(_motion.get("turn_max",6.0))*dt
	var turn := clampf(diff*(1.0-exp(-rate*dt)),-limit,limit)
	_yaw = wrapf(_yaw+turn,-PI,PI)
	rotation.y = _yaw
	_yaw_rate = lerpf(_yaw_rate,turn/dt,1.0-exp(-12.0*dt))
	var lean := clampf(_yaw_rate*float(_motion.get("bank",0.05)),-0.28,0.28)
	_bank = lerpf(_bank,lean,1.0-exp(-8.0*dt))
	if absf(_bank) < 0.0005 and absf(lean) < 0.0005: _bank = 0.0

## Simulator flash 0..1 (1 on hit, -5/s). Drives body squash and the material flash.
func set_hit_flash(amount: float) -> void:
	amount = clampf(amount,0.0,1.0)
	if amount <= 0.0:
		_hit_scale = 1.0
		_recoil = Vector3.ZERO
	if not is_equal_approx(amount,_flash):
		_flash = amount
		StellarShading.set_hit_flash(self,amount)

## -1 away from the crystal, else the siege phase in [0,1); damage lands at the wrap.
func set_siege(phase: float) -> void:
	_siege = phase
	if phase >= 0.0: _siege_phase = phase

func visual_event(type: String, e: Dictionary) -> void:
	match type:
		"spawn":
			if not _dying: _spawn_t = 0.0
		"hit":
			_hit_scale = 1.35 if bool(e.get("crit",false)) else 1.0
			_recoil = _away_from(e.get("p"))
		"push":
			_stumble = 1.0
		"stun":
			_daze = maxf(_daze,0.6)
		"die":
			_begin_death("die")
		"leak":
			_begin_death("leak")
		_:
			pass

## Called by the world each frame after die/leak. True once the body is done.
func advance_death(dt: float) -> bool:
	if not _bind() or not _dying: return true
	if dt > 0.0:
		_death_t += dt
		_w_die = minf(1.0,_w_die+dt/DEATH_FADE)
		_compose(_last_motion)
		_apply_skeleton()
		_apply_pivot()
		var q := _dissolve_amount()
		if not is_equal_approx(q,_dissolve):
			_dissolve = q
			StellarShading.set_dissolve(self,q)
	return _death_t >= _death_total()

## Inspection hook for checks and previews (read only).
func motion_state() -> Dictionary:
	return {"idle": _w_idle, "move": _w_move, "attack": _w_attack, "die": _w_die, "spawn": _spawn_t,
		"yaw": _yaw, "bank": _bank, "stand": _stand_t, "dying": _dying, "dissolve": _dissolve,
		"flash": _flash, "daze": _daze, "stumble": _stumble, "pivot": _pivot.transform if _pivot != null else Transform3D.IDENTITY}

# --------------------------------------------------------------------------- #
# Pose composition
# --------------------------------------------------------------------------- #
func _compose(motion_time: float) -> void:
	_acc_w = 0.0
	var alive := 1.0-_w_die
	if _w_move*alive > EPS: _sample(_clips["MoveLoop"],motion_time,_w_move*alive,true)
	if _w_idle*alive > EPS: _sample(_clips["IdleLoop"],motion_time+_stand_t,_w_idle*alive,true)
	if _w_attack*alive > EPS and _clips.has("Attack"):
		_sample(_clips["Attack"],fposmod(_siege_phase-ATTACK_SHIFT,1.0)*float(_clips["Attack"]["len"]),_w_attack*alive,true)
	if _w_die > EPS and _death_kind == "die" and _clips.has("Die"): _sample(_clips["Die"],_death_t,_w_die,false)
	if _acc_w <= 0.0:
		for i in _bone_count:
			_acc_pos[i] = _rest_pos[i]
			_acc_rot[i] = _rest_rot[i]
			_acc_scale[i] = _rest_scale[i]
	var s := _hit_amount()
	if s > 0.0 and not _dying:
		# Flinch: head and torso snap up/back for the few frames the flash lasts.
		if _head >= 0: _acc_rot[_head] = Quaternion(Vector3.RIGHT,0.22*s)*_acc_rot[_head]
		if _body >= 0:
			_acc_rot[_body] = Quaternion(Vector3.RIGHT,0.06*s)*_acc_rot[_body]
			_acc_pos[_body] += Vector3(0,0,0.02*_height*s)

func _sample(clip: Dictionary, time: float, weight: float, loop: bool) -> void:
	var animation: Animation = clip["anim"]
	var length := float(clip["len"])
	time = fposmod(time,length) if loop else clampf(time,0.0,length)
	var pos: PackedInt32Array = clip["pos"]
	var rot: PackedInt32Array = clip["rot"]
	var scl: PackedInt32Array = clip["scl"]
	var first := _acc_w <= 0.0
	var f := weight/(_acc_w+weight)
	for i in _bone_count:
		var p := animation.position_track_interpolate(pos[i],time) if pos[i] >= 0 else _rest_pos[i]
		var q := animation.rotation_track_interpolate(rot[i],time) if rot[i] >= 0 else _rest_rot[i]
		var sc := animation.scale_track_interpolate(scl[i],time) if scl[i] >= 0 else _rest_scale[i]
		if first:
			_acc_pos[i] = p
			_acc_rot[i] = q
			_acc_scale[i] = sc
		else:
			_acc_pos[i] = _acc_pos[i].lerp(p,f)
			_acc_rot[i] = _acc_rot[i].slerp(q,f)
			_acc_scale[i] = _acc_scale[i].lerp(sc,f)
	_acc_w += weight

func _apply_skeleton() -> void:
	for i in _bone_count:
		_skeleton.set_bone_pose_position(i,_acc_pos[i])
		_skeleton.set_bone_pose_rotation(i,_acc_rot[i])
		_skeleton.set_bone_pose_scale(i,_acc_scale[i])

func _hit_amount() -> float:
	return pow(_flash,1.5)*_hit_scale if _flash > 0.0 else 0.0

## Reaction layers on the rig pivot (child of this node): the world keeps
## writing position/rotation.z on the root, so offsets live one level down.
func _apply_pivot() -> void:
	var origin := Vector3.ZERO
	var scl := Vector3.ONE
	var pitch := 0.0
	var roll := _bank
	if _spawn_t >= 0.0:
		var u := clampf(_spawn_t/SPAWN_SEC,0.0,1.0)
		match String(_motion.get("spawn","rise")):
			"drop":
				var fall := clampf(u/0.62,0.0,1.0)
				origin.y += 0.65*_height*(1.0-fall*fall)
				var land := clampf((u-0.62)/0.38,0.0,1.0)
				var b := sin(PI*land)*(1.0-land*0.5)
				scl *= Vector3(1.0+0.20*b,1.0-0.24*b,1.0+0.20*b)
			"descend":
				var e := 1.0-pow(1.0-u,3.0)
				origin.y += 0.5*_height*(1.0-e)
				var pop := _back_out(u)
				scl *= Vector3(0.55+0.45*pop,0.55+0.45*pop,0.55+0.45*pop)
			_:
				var e := 1.0-pow(1.0-u,3.0)
				origin.y -= 0.95*_height*(1.0-e)
				var settle := clampf((u-0.72)/0.28,0.0,1.0)
				var b := sin(PI*settle)
				scl *= Vector3(1.0+0.10*b,1.0-0.12*b+0.10*sin(PI*u)*(1.0-settle),1.0+0.10*b)
	var s := _hit_amount()
	if s > 0.0:
		scl *= Vector3(1.0+0.10*s,1.0-0.12*s,1.0+0.10*s)
		origin += _recoil*(0.05*_height*s)
	if _stumble > 0.0: pitch += 0.14*sin(PI*pow(1.0-_stumble,0.7))
	if _daze > 0.0:
		roll += 0.07*_daze*sin(_stand_t*6.3)
		pitch += 0.05*_daze*sin(_stand_t*4.7+1.0)
	if _dying:
		var t := _death_t
		if _death_kind == "leak":
			var u := clampf(t/0.4,0.0,1.0)
			scl *= Vector3.ONE*(1.0-0.8*u)
			origin.y -= 0.6*_height*u*u
		else:
			match String(_motion.get("death","sink")):
				"topple":
					pitch -= 1.40*pow(_seg(t,0.10,0.62),2.2)-0.10*sin(PI*_seg(t,0.62,0.95))
					origin.y -= 1.0*_height*pow(_seg(t,0.85,1.45),2.0)
				"topple_back":
					pitch += 1.35*pow(_seg(t,0.15,0.70),2.2)-0.08*sin(PI*_seg(t,0.70,1.0))
					origin.y -= 1.0*_height*pow(_seg(t,0.90,1.50),2.0)
				"topple_side":
					roll += 1.35*pow(_seg(t,0.12,0.65),2.2)-0.08*sin(PI*_seg(t,0.65,0.95))
					origin.y -= 1.0*_height*pow(_seg(t,0.85,1.45),2.0)
				"splat":
					origin.y -= 1.1*_height*pow(_seg(t,0.55,1.10),2.0)
				_:
					origin.y -= 1.1*_height*pow(_seg(t,0.45,1.15),2.0)
	var basis := Basis.from_scale(scl)*Basis.from_euler(Vector3(pitch,0.0,roll))
	_pivot.transform = _pivot_base*Transform3D(basis,origin)

func _death_total() -> float:
	if _death_kind == "leak": return 0.4
	match String(_motion.get("death","sink")):
		"topple", "topple_side": return 1.45
		"topple_back": return 1.5
		"splat": return 1.1
		_: return 1.15

func _dissolve_amount() -> float:
	var t := _death_t
	if _death_kind == "leak": return clampf(t/0.4,0.0,1.0)
	match String(_motion.get("death","sink")):
		"topple", "topple_side": return _seg(t,0.75,1.4)
		"topple_back": return _seg(t,0.8,1.45)
		"splat": return _seg(t,0.5,1.05)
		_: return _seg(t,0.4,1.05)

func _begin_death(kind: String) -> void:
	if _dying: return
	_dying = true
	_death_kind = kind
	_death_t = 0.0
	_w_die = 0.0
	_spawn_t = -1.0
	_siege = -1.0
	for status in ["StellarBurn","StellarFrost","StellarStun"]:
		var group := get_node_or_null(status)
		if group != null: group.visible = false
	_dissolve = 0.0
	StellarShading.set_dissolve(self,0.0)

## Unit direction (local space) pointing from a logical hit position to this body.
func _away_from(p) -> Vector3:
	var local := Vector3(0,0,1)
	if p is Vector2 and is_inside_tree():
		var here := StellarWorld.logical(global_position)
		var away := Vector3(here.x-p.x,0.0,here.y-p.y)
		if away.length_squared() > 0.25:
			local = (global_transform.basis.inverse()*away).normalized()
			local.y = 0.0
	return local

func _stun_group() -> Node3D:
	return get_node_or_null("StellarStun") as Node3D

static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t-a)/(b-a),0.0,1.0)

static func _back_out(x: float, s: float = 1.5) -> float:
	x = clampf(x,0.0,1.0)-1.0
	return 1.0+x*x*((s+1.0)*x+s)

static func _find_type(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find_type(child,type)
		if found != null: return found
	return null
