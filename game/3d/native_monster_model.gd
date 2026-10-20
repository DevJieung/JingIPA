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
##
## Three ways to leave the field (visual_event): "die" (the authored Die clip, a topple
## or sink by body shape, then the dissolve), "leak" (reached the crystal: shrinks away in
## 0.4 s) and "die" with `scatter` (an escort whose stage boss fell: it is not killed, it
## flees; see FLEE_SEC).
const MANIFEST := "res://art/models/native_monsters.json"
const FADE := 0.18          # idle/move/attack crossfade seconds
const DEATH_FADE := 0.08
const SPAWN_SEC := 0.45
const ATTACK_SHIFT := 0.3   # Attack clip time = (siege phase - 0.3) mod 1 → strike at the wrap
const EPS := 0.0005
## Motion beats (2026-10-18, casual overhaul WP-D) — all on the pivot, never in the
## samplers (parity with the C++ kernel stays bit-equal):
##   M1 hit     a pure function of the simulator flash: the squash sits on a plateau
##              (smoothstep 0.20..0.50 of the flash: full through frame 6 at 60 Hz, so six
##              coloured squashed frames follow the material flash's 0-1 white frames)
##              with a recoil away from the hit and a hop, then a stretch as the flash
##              dies; crits x1.35
##   M3 spawn   rise: burst out of the ground, over-rise, settle squash; drop: stretch on
##              the way down, a bigger landing squash; rest exactly by SPAWN_SEC
##   M4 death   a pop and a flatten before the sink; topples rebound and bounce once
##   M5 lean    forward while the walk fades in, back while it fades out (FADE 0.18)
##   M6 rock    torso pitch at the footfall cadence and roll at the cycle while walking;
##              about the feet, no vertical bob
##   M7 bank    the turn bank goes through a second-order spring (one swing back)
##   S18 crowd  per spawn id: a walk-phase offset (added to the sampler clock, so both
##              samplers see it), +-4 % size and, for symmetric shapes, a mirror
## BEAT_SHAPE multiplies every squash by body shape: blobs and jellies more, stone less.
const BEAT_SHAPE := {"blob": 1.4, "jelly": 1.4, "idol": 0.6, "tree": 0.6}
const BEAT_KIND := {"tank": 0.6, "boss": 0.7}
const MIRROR_SHAPES := ["blob", "mushroom", "jelly", "idol"]
const HIT_PLATEAU := Vector2(0.20, 0.50)   # full squash while flash >= 0.50 (frames 0-6 at 60 Hz), stretch below 0.20
const HIT_SQUASH := Vector2(0.22, 0.26)   # x/z widen, y squash at full plateau (x shape)
const HIT_RECOIL := 0.12                  # of the height, away from the hit
const HIT_HOP := 0.06                     # of the height
const HIT_STRETCH := Vector2(0.06, 0.08)  # as the flash dies below the plateau
const HIT_CRIT_MAX := 1.5                 # cap of shape x crit so a slime crit keeps 61 % of its height
const LEAN_START := 0.12
const LEAN_STOP := 0.10
const ROCK_PITCH := 0.07
const ROCK_ROLL := 0.045
const BANK_F := 2.9               # Hz (omega 18 rad/s)
const BANK_ZETA := 0.5
const VARIETY_SCALE := 0.04
## An elite (2026-10-19, StellarModels.elite): the crowd's size variety is off (it already
## stands 1.35x) and its hit, spawn and death beats are a little heavier.
const ELITE_BEAT := 0.8
## Scatter: an escort removed when its stage boss falls. Seconds after the event:
##   0 .. wait        halt: the simulator no longer moves the body, so the walk eases to
##                    the idle pose; a small crouch as the victory wave comes close
##   wait             the wave arrives (StellarVfx.scatter_delay: 0 at the crystal, 0.6 at
##                    the rim) and the haze StellarVfx draws for this body is born
##   wait .. +FLEE_SEC  flee: the body turns from the crystal (FLEE_TURN) and bolts
##                    FLEE_DIST along StellarVfx.scatter_heading, most of it in the first
##                    half while it is still solid (its MoveLoop driven by the ground it
##                    covers), leaning in and lifting a little; it thins into that haze
##                    over the second half
## No Die clip, no topple, no sink. Longest case 0.6 + 0.54 s: inside the world's 1.6 s
## retention and well before the next battlefield is built (Balance.ARENA_CLEAR_DELAY).
const FLEE_SEC := 0.50
const FLEE_DIST := 1.50     # world units covered while leaving
const FLEE_EASE := 1.8      # travel = 1 - (1 - u)^FLEE_EASE: a bolt that runs out as it thins
const FLEE_TURN := 0.14     # seconds to face the way out
const FLEE_BRACE := 0.16    # seconds of crouch before the wave arrives
const FLEE_LIFT := 0.28     # of the body height (capped at 1.2 u), reached as it is gone
const FLEE_BLEND := 0.08    # idle -> run crossfade
## Flyers (roster `fly`; StellarModels.monster sets meta `_stellar_fly` and adds the
## contact shadow): the body rides `altitude` world units above the normal monster ground
## on the rig pivot, so the root stays on BattleSim's ground point and every world lookup
## is unchanged. A slow bob (`bob` amplitude, `period` seconds) runs on the standing
## clock, so it goes on while the body besieges or is blocked, holds under a pause and
## starts at a phase set by the spawn id. `bank_max` widens the turn-banking limit
## (walkers: 0.28) and `shadow` is the disc on the ground (× the body height), the
## strongest airborne cue. The idol is a hovering stone: lower, heavier, slower. Any
## other flying shape gets FLIGHT_DEFAULT. The current altitude is published every frame
## as the node meta FLY_META (0 for walkers) for effects that must land on the body.
## Meta `_stellar_grounded` (portrait tools) keeps a flyer on the ground.
const FLIGHT := {
	"ray": {"altitude": 1.35, "bob": 0.10, "period": 1.9, "bank_max": 0.45, "shadow": Vector2(1.15, 0.85)},
	"jelly": {"altitude": 1.25, "bob": 0.13, "period": 2.5, "bank_max": 0.28, "shadow": Vector2(0.95, 0.80)},
	"idol": {"altitude": 0.95, "bob": 0.07, "period": 2.4, "bank_max": 0.20, "shadow": Vector2(0.72, 0.62)},
}
const FLIGHT_DEFAULT := {"altitude": 1.2, "bob": 0.10, "period": 2.0, "bank_max": 0.28, "shadow": Vector2(0.9, 0.75)}
const FLY_META := "_stellar_fly_height"
const FALL_SEC := 0.42      # a killed flyer drops out of its hover in this time, accelerating
const FALL_BOUNCE := 0.06   # of the ride height: the rebound after the impact
const SIEGE_LIFT := 0.10    # of the ride height: the lift through the wind-up of a strike
const SIEGE_DIVE := 0.22    # of the ride height: the dive at the strike
static var _manifest: Dictionary = {}
## Loaded creature scenes by id. A type stays loaded after its last instance dies:
## until 2026-10-15 it was read back from storage on its next spawn, a 30-70 ms frame
## on a phone-class core. keep_only() limits the set to the coming stage's creatures.
static var _scenes: Dictionary = {}
## Ids whose shared skin materials StellarShading.style() has tuned. The tuning lives
## on the cached scene's own materials, so it runs once per load instead of once per
## spawn (style() reads every surface's vertex arrays back to find vertex colours).
static var _styled: Dictionary = {}

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
## The C++ sampler (StellarMonsterPose, docs/PERF_NATIVE.md) over the same clips, or
## null: then _compose samples here. use_native_pose() switches for the checks.
var _pose = null
var _pose_native = null

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
# Motion beats (see the BEAT_* constants).
var _kind := ""
var _beat_shape := 1.0
var _rock_mult := 1.0
var _rock_cadence := 2.0
var _moving_target := true
var _bank_spring := Vector3.ZERO
var _variety_phase := 0.0        # seconds of clip time added while walking (S18)
var _variety_scale := 1.0
var _mirror := false
var _elite := false
var _dying := false
var _death_kind := ""
var _death_t := 0.0
var _dissolve := -1.0
# Scatter (see FLEE_SEC): when the wave arrives, how long and how far this body runs,
# which way (root-local unit vector and the turn that faces it) and the MoveLoop seconds
# its run has added to the simulator's last clock.
var _flee_wait := 0.0
var _flee_len := FLEE_SEC
var _flee_reach := FLEE_DIST
var _flee_dir := Vector3(0,0,1)
var _flee_yaw := 0.0
var _flee_run := 0.0
# Flight (see FLIGHT): the shape row, the bob clock and phase, the altitude published
# this frame and the contact shadow on the ground.
var _fly := false
var _flight: Dictionary = {}
var _air_t := 0.0
var _bob_phase := 0.0
var _hover := 0.0
var _shadow: Node3D

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary: _manifest = parsed
	return _manifest

static func has_model(id: String) -> bool:
	var data := manifest()
	return id in data.get("ready_ids",[]) and data.get("monsters",{}).has(id) and ResourceLoader.exists(String(data["monsters"][id]["path"]))

## Flight row of a body shape (see FLIGHT).
static func flight(shape: String) -> Dictionary:
	return FLIGHT.get(shape, FLIGHT_DEFAULT)

## Loads the given creature types and releases every other cached type. The arena
## calls it while a stage's battlefield card is up, so that stage's monsters and boss
## are in memory before the first one spawns. Bodies still on the field keep their own
## resources alive; a released type simply loads again if it is ever spawned.
static func keep_only(ids: Array) -> void:
	for id in _scenes.keys():
		if not ids.has(id):
			_scenes.erase(id)
			_styled.erase(id)
	for id in ids:
		if has_model(String(id)): _scene(String(id))

static func _scene(id: String) -> PackedScene:
	if _scenes.has(id): return _scenes[id]
	var row: Dictionary = manifest().get("monsters",{}).get(id,{})
	if row.is_empty(): return null
	var packed := load(String(row["path"])) as PackedScene
	if packed != null: _scenes[id] = packed
	return packed

static func create(id: String) -> Node3D:
	var row: Dictionary = manifest().get("monsters",{}).get(id,{})
	if row.is_empty(): return null
	var packed := _scene(id)
	if packed == null: return null
	var root := packed.instantiate() as Node3D
	root.set_script(load("res://game/3d/native_monster_model.gd"))
	root.set_meta("_stellar_native_monster",true)
	root.set_meta("_stellar_monster_id",id)
	root.set_meta("_stellar_height",float(row.get("height",1.0)))
	root.set_meta("_stellar_shape",String(row.get("shape","biped")))
	root.set_meta("_stellar_motion",row.get("motion",{}))
	root.set_meta("model_source",String(row["path"]))
	if not _styled.has(id):
		StellarShading.style(root,float(row.get("metallic",0.0)))
		_styled[id] = true
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
	_fly = bool(get_meta("_stellar_fly",false)) and not bool(get_meta("_stellar_grounded",false))
	if _fly:
		_flight = flight(_shape)
		_shadow = get_node_or_null("StellarContact") as Node3D
	var roster_row = Roster.monster_by_id(String(get_meta("_stellar_monster_id","")))
	_kind = String(roster_row.get("kind","")) if roster_row is Dictionary else ""
	_beat_shape = float(BEAT_KIND.get(_kind, BEAT_SHAPE.get(_shape, 1.0)))
	if _elite: _beat_shape = minf(_beat_shape, ELITE_BEAT)
	# Heavy bodies rock half as much; the gallop (one bounce per cycle) rocks once, the
	# trot and every two-legged walk twice; flyers hover instead.
	_rock_mult = 0.0 if _fly else 0.5 if _beat_shape < 1.0 else 1.0
	_rock_cadence = 1.0 if (_shape in ["quadruped", "blob", "serpent"] and float(_motion.get("cycle",0.5)) < 0.7) else 2.0
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
	_pose_native = Native.make("StellarMonsterPose")
	if _pose_native != null:
		_pose_native.bind(_skeleton)
		for key in _clips:
			var clip: Dictionary = _clips[key]
			clip["native"] = _pose_native.add_clip(clip["anim"], clip["pos"], clip["rot"], clip["scl"])
	_pose = _pose_native
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
	if _fly: _air_t = fposmod(_air_t+_pending_dt, _bob_period())
	_pending_dt = 0.0
	_last_motion = motion_time
	var attack := not moving and _siege >= 0.0 and _clips.has("Attack")
	_moving_target = moving
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
	_compose(_clip_time(motion_time))
	_apply_skeleton()
	_apply_pivot()

## The sampler clock: the simulator clock plus this body's crowd-variety phase while it
## walks (S18). One number for both samplers, so parity holds; the phase fades with the
## walk weight, so a standing body samples the plain clock (first sample = pure
## function of the simulator clock).
func _clip_time(motion_time: float) -> float:
	return motion_time+_variety_phase*_w_move

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
	var limit_bank := float(_flight.get("bank_max",0.28)) if _fly else 0.28
	var lean := clampf(_yaw_rate*float(_motion.get("bank",0.05)),-limit_bank,limit_bank)
	# M7: the bank follows a second-order spring (one swing back as the turn ends).
	_bank_spring = HeroLocomotion.sod_step(_bank_spring,lean,dt,BANK_F,BANK_ZETA,0.0)
	_bank = clampf(_bank_spring.x,-limit_bank*1.3,limit_bank*1.3)
	if absf(_bank) < 0.0005 and absf(lean) < 0.0005 and absf(_bank_spring.y) < 0.002:
		_bank = 0.0
		_bank_spring = Vector3(0.0,0.0,lean)

## Elite look hook (StellarModels.elite calls it before the body joins the world).
func set_elite(on: bool) -> void:
	_elite = on
	if _skeleton != null: _beat_shape = minf(float(BEAT_KIND.get(_kind, BEAT_SHAPE.get(_shape, 1.0))), ELITE_BEAT) if on else float(BEAT_KIND.get(_kind, BEAT_SHAPE.get(_shape, 1.0)))

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
			if not _dying:
				_spawn_t = 0.0
				# Flyers of one wave must not bob as one machine: the phase comes from the
				# spawn id (golden-ratio hash, no random numbers).
				var sid := int(e.get("sid",0))
				var h := fposmod(float(sid)*0.6180339,1.0) if sid != 0 else 0.0
				_bob_phase = TAU*h
				# S18 crowd variety from the same hash: walk phase, size, mirror. Spawn id 0
				# (checks, previews) stays neutral by construction.
				_variety_phase = h*float(_motion.get("cycle",0.5))
				_variety_scale = 1.0 if _elite else 1.0+VARIETY_SCALE*sin(TAU*h)
				_mirror = sid != 0 and _shape in MIRROR_SHAPES and h > 0.5
		"hit":
			_hit_scale = 1.35 if bool(e.get("crit",false)) else 1.0
			_recoil = _away_from(e.get("p"))
		"push":
			_stumble = 1.0
		"stun":
			_daze = maxf(_daze,0.6)
		"die":
			if bool(e.get("scatter",false)): _begin_scatter(e)
			else: _begin_death("die")
		"leak":
			_begin_death("leak")
		_:
			pass

## Called by the world each frame after die/leak. True once the body is done.
func advance_death(dt: float) -> bool:
	if not _bind() or not _dying: return true
	if dt > 0.0:
		_death_t += dt
		if _death_kind == "scatter":
			_advance_scatter(dt)
		else:
			_w_die = minf(1.0,_w_die+dt/DEATH_FADE)
			_compose(_clip_time(_last_motion))
		_apply_skeleton()
		_apply_pivot()
		var q := _dissolve_amount()
		if not is_equal_approx(q,_dissolve):
			_dissolve = q
			StellarShading.set_dissolve(self,q)
	return _death_t >= _death_total()

## Inspection hook for checks and previews (read only). `death` is "", "die", "leak" or
## "scatter"; `flee` is the run's progress 0..1 once the wave has arrived (-1 otherwise).
func motion_state() -> Dictionary:
	return {"idle": _w_idle, "move": _w_move, "attack": _w_attack, "die": _w_die, "spawn": _spawn_t,
		"yaw": _yaw, "bank": _bank, "stand": _stand_t, "hover": _hover, "dying": _dying, "dissolve": _dissolve,
		"flash": _flash, "daze": _daze, "stumble": _stumble, "pivot": _pivot.transform if _pivot != null else Transform3D.IDENTITY,
		"death": _death_kind, "death_t": _death_t, "death_total": _death_total() if _dying else 0.0,
		"flee_wait": _flee_wait, "flee": _flee_progress() if _death_kind == "scatter" else -1.0}

# --------------------------------------------------------------------------- #
# Pose composition
# --------------------------------------------------------------------------- #
func _compose(motion_time: float) -> void:
	if _pose != null:
		_compose_native(motion_time)
		return
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

## Tools and checks only: pose with the library (true) or with the GDScript sampler.
func use_native_pose(on: bool) -> void:
	_pose = _pose_native if on else null

## The same blend as _compose below, sampled and written by StellarMonsterPose.
func _compose_native(motion_time: float) -> void:
	_pose.begin()
	var alive := 1.0-_w_die
	if _w_move*alive > EPS: _pose.sample(int(_clips["MoveLoop"]["native"]),motion_time,_w_move*alive,true)
	if _w_idle*alive > EPS: _pose.sample(int(_clips["IdleLoop"]["native"]),motion_time+_stand_t,_w_idle*alive,true)
	if _w_attack*alive > EPS and _clips.has("Attack"):
		_pose.sample(int(_clips["Attack"]["native"]),fposmod(_siege_phase-ATTACK_SHIFT,1.0)*float(_clips["Attack"]["len"]),_w_attack*alive,true)
	if _w_die > EPS and _death_kind == "die" and _clips.has("Die"): _pose.sample(int(_clips["Die"]["native"]),_death_t,_w_die,false)
	_pose.finish(0.0 if _dying else _hit_amount(),_height)

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
	if _pose != null:
		_pose.apply(_skeleton)
		return
	for i in _bone_count:
		_skeleton.set_bone_pose_position(i,_acc_pos[i])
		_skeleton.set_bone_pose_rotation(i,_acc_rot[i])
		_skeleton.set_bone_pose_scale(i,_acc_scale[i])

func _hit_amount() -> float:
	return pow(_flash,1.5)*_hit_scale if _flash > 0.0 else 0.0

## Reaction layers on the rig pivot (child of this node): the world keeps
## writing position/rotation.z on the root, so offsets live one level down.
## Every term is a function of this frame's inputs and the clocks the world advances;
## nothing accumulates, so a paused redraw gives the same pivot.
func _apply_pivot() -> void:
	var origin := Vector3.ZERO
	var scl := Vector3.ONE
	var pitch := 0.0
	var yaw := 0.0
	var roll := _bank
	var m := _beat_shape
	if _spawn_t >= 0.0:
		var u := clampf(_spawn_t/SPAWN_SEC,0.0,1.0)
		match String(_motion.get("spawn","rise")):
			"drop":
				# Falls with a stretch, lands at 0.62 into a squash (26/32 % x shape), rests by 1.
				var fall := clampf(u/0.62,0.0,1.0)
				origin.y += 0.65*_height*(1.0-fall*fall)
				var tall := sin(PI*fall)
				scl *= Vector3(1.0-0.06*m*tall,1.0+0.10*m*tall,1.0-0.06*m*tall)
				var land := clampf((u-0.62)/0.38,0.0,1.0)
				var b := sin(PI*land)*(1.0-land*0.5)
				scl *= Vector3(1.0+0.26*m*b,1.0-0.32*m*b,1.0+0.26*m*b)
			"descend":
				var e := 1.0-pow(1.0-u,3.0)
				# A flyer comes down from well above its ride height.
				origin.y += (0.5*_height+(0.6 if _fly else 0.0))*(1.0-e)
				var pop := _back_out(u)
				scl *= Vector3(0.55+0.45*pop,0.55+0.45*pop,0.55+0.45*pop)
			_:
				# Rise: bursts out of the ground over the first 0.55 (ease-out, stretched
				# tall), over-rises 8 % of its height, lands at 0.75 into a settle squash.
				var up := clampf(u/0.55,0.0,1.0)
				var e := 1.0-pow(1.0-up,2.4)
				origin.y -= 0.95*_height*(1.0-e)
				var tall := sin(PI*up)
				scl *= Vector3(1.0-0.05*m*tall,1.0+0.10*m*tall,1.0-0.05*m*tall)
				origin.y += 0.08*_height*_bump(u,0.45,0.75)
				var settle := _bump(u,0.72,1.0)
				scl *= Vector3(1.0+0.18*m*settle,1.0-0.22*m*settle,1.0+0.18*m*settle)
	if _flash > 0.0 and not _dying:
		# M1 hit: squash + recoil + hop on the flash plateau, a stretch as it dies.
		var k := minf(m*_hit_scale,HIT_CRIT_MAX)
		var a := smoothstep(HIT_PLATEAU.x,HIT_PLATEAU.y,_flash)*k
		if a > 0.0:
			scl *= Vector3(1.0+HIT_SQUASH.x*a,1.0-HIT_SQUASH.y*a,1.0+HIT_SQUASH.x*a)
			origin += _recoil*(HIT_RECOIL*_height*a)
			origin.y += HIT_HOP*_height*a
		if _flash < HIT_PLATEAU.x:
			var b := sin(PI*(HIT_PLATEAU.x-_flash)/HIT_PLATEAU.x)*m
			scl *= Vector3(1.0-HIT_STRETCH.x*b,1.0+HIT_STRETCH.y*b,1.0-HIT_STRETCH.x*b)
	if _stumble > 0.0: pitch += 0.14*sin(PI*pow(1.0-_stumble,0.7))
	if _daze > 0.0:
		roll += 0.07*_daze*sin(_stand_t*6.3)
		pitch += 0.05*_daze*sin(_stand_t*4.7+1.0)
	if _started and not _dying:
		# M5: leans into the walk as it fades in, back as it fades out (a snap that
		# FADE 0.18 then settles). M6: the walk rock about the feet.
		if _moving_target: pitch -= LEAN_START*(1.0-_w_move)*_rock_mult
		else: pitch += LEAN_STOP*_w_move*_rock_mult
		if _w_move > EPS and _rock_mult > 0.0:
			var cycle := maxf(float(_motion.get("cycle",0.5)),0.05)
			var tau := _clip_time(_last_motion)/cycle
			pitch -= ROCK_PITCH*_rock_mult*_w_move*cos(TAU*_rock_cadence*tau-0.3)
			roll += ROCK_ROLL*_rock_mult*_w_move*sin(TAU*tau)
	if _dying:
		var t := _death_t
		if _death_kind == "leak":
			var u := clampf(t/0.4,0.0,1.0)
			scl *= Vector3.ONE*(1.0-0.8*u)
			origin.y -= 0.6*_height*u*u
		elif _death_kind == "scatter":
			var since := t-_flee_wait
			# Anticipation: a crouch and a lean back over the last FLEE_BRACE seconds
			# before the wave arrives (none for a body the wave reaches at once),
			# released as it bolts.
			var brace := clampf(_flee_wait/FLEE_BRACE,0.0,1.0)*smoothstep(-FLEE_BRACE,0.0,since)*(1.0-smoothstep(0.0,0.07,since))
			scl *= Vector3(1.0+0.09*brace,1.0-0.14*brace,1.0+0.09*brace)
			pitch += 0.10*brace
			if since > 0.0:
				var u := _flee_progress()
				# Snap: it springs up out of the crouch, turns and is off; then it thins.
				var spring := sin(PI*clampf(since/0.22,0.0,1.0))
				scl *= Vector3(1.0-0.06*spring,1.0+0.11*spring,1.0-0.06*spring)*(1.0-0.14*u*u)
				yaw = _flee_yaw*(1.0-pow(1.0-clampf(since/FLEE_TURN,0.0,1.0),3.0))
				pitch -= 0.24*smoothstep(0.0,0.25,u)
				origin += _flee_dir*(_flee_travel(u)/maxf(absf(scale.x),0.01))
				origin.y += FLEE_LIFT*minf(_height,1.2)*u*u
		else:
			# M4: a pop (0.08-0.20 s) and a flatten before the sink; a killed flyer pops
			# once it has hit the ground. Topples rebound 0.22 rad and bounce 0.08 H.
			var td := t-(FALL_SEC if _fly else 0.0)
			var pop := _bump(td,0.08,0.20)*m
			match String(_motion.get("death","sink")):
				"topple":
					pitch -= 1.40*pow(_seg(t,0.10,0.62),2.2)-0.22*sin(PI*_seg(t,0.62,0.95))
					origin.y += 0.08*_height*sin(PI*_seg(t,0.62,0.85))
					origin.y -= 1.0*_height*pow(_seg(t,0.85,1.45),2.0)
				"topple_back":
					pitch += 1.35*pow(_seg(t,0.15,0.70),2.2)-0.22*sin(PI*_seg(t,0.70,1.0))
					origin.y += 0.08*_height*sin(PI*_seg(t,0.70,0.90))
					origin.y -= 1.0*_height*pow(_seg(t,0.90,1.50),2.0)
				"topple_side":
					roll += 1.35*pow(_seg(t,0.12,0.65),2.2)-0.22*sin(PI*_seg(t,0.65,0.95))
					origin.y += 0.08*_height*sin(PI*_seg(t,0.65,0.85))
					origin.y -= 1.0*_height*pow(_seg(t,0.85,1.45),2.0)
				"splat":
					var flat := smoothstep(0.20,0.55,td)*m
					scl *= Vector3(1.0+0.15*pop+0.25*flat,1.0+0.15*pop-0.20*flat,1.0+0.15*pop+0.25*flat)
					origin.y -= 1.1*_height*pow(_seg(t,0.55,1.10),2.0)
				_:
					var flat := smoothstep(0.20,0.45,td)*m
					scl *= Vector3(1.0+0.15*pop+0.25*flat,1.0+0.15*pop-0.20*flat,1.0+0.15*pop+0.25*flat)
					origin.y -= 1.1*_height*pow(_seg(t,0.45,1.15),2.0)
	if _fly:
		_hover = _fly_altitude()
		origin.y += _hover
	# S18: size and mirror. A mirrored frame shows its roll and yaw reversed, so both
	# are negated first and the authored lean still reads into the turn.
	scl *= _variety_scale
	if _mirror:
		scl.x = -scl.x
		roll = -roll
		yaw = -yaw
	var basis := Basis.from_scale(scl)*Basis.from_euler(Vector3(pitch,yaw,roll))
	_pivot.transform = _pivot_base*Transform3D(basis,origin)
	if _fly: _apply_flight(origin.y)

## Sine bump 0 -> 1 -> 0 over [a, b], zero outside.
static func _bump(t: float, a: float, b: float) -> float:
	if t <= a or t >= b: return 0.0
	return sin(PI*(t-a)/(b-a))

## Seconds of one hover bob (see FLIGHT).
func _bob_period() -> float:
	return maxf(0.2,float(_flight.get("period",2.0)))

## Altitude of a flyer's body above the ground this frame: the shape's ride height with
## its slow bob on the standing clock (a paused game holds it; the phase is the spawn
## id's), a lift and dive through the siege strike (the dive lands with the damage at the
## phase wrap), a buffet upward while a hit flashes and, once killed, the fall: an
## accelerating drop to the ground, a small rebound, then the authored sink or topple
## takes the body under. A fleeing or leaking body keeps its height.
func _fly_altitude() -> float:
	var base := float(_flight.get("altitude",1.2))
	var h := base+float(_flight.get("bob",0.1))*sin(TAU*_air_t/_bob_period()+_bob_phase)
	if _w_attack > EPS: h += _w_attack*_siege_dip(_siege_phase)*base
	var s := _hit_amount()
	if s > 0.0 and not _dying: h += 0.05*_height*s
	if _dying and _death_kind == "die":
		var u := clampf(_death_t/FALL_SEC,0.0,1.0)
		h *= 1.0-u*u
		h += FALL_BOUNCE*base*sin(PI*clampf((_death_t-FALL_SEC)/0.22,0.0,1.0))
	return h

## Siege phase → altitude change as a fraction of the ride height, on the Attack clip's
## own timing (clip time = (phase - ATTACK_SHIFT) mod 1): hold, a lift through the
## wind-up, the dive at the strike, the climb back over the recovery.
static func _siege_dip(phase: float) -> float:
	var t := fposmod(phase-ATTACK_SHIFT,1.0)
	if t < 0.30: return 0.0
	if t < 0.62: return SIEGE_LIFT*smoothstep(0.30,0.62,t)
	if t < 0.70:
		var u := (t-0.62)/0.08
		return lerpf(SIEGE_LIFT,-SIEGE_DIVE,u*u)
	return -SIEGE_DIVE*(1.0-smoothstep(0.70,1.0,t))

## Publish how high the body is this frame (FLY_META: the whole pivot lift, so the
## entrance from above counts too, never below the ground) and keep the ground-level
## parts in step: status marks ride with the body (the world drives only their
## visibility, scale and spin); the contact shadow stays on the ground, smaller the
## higher the body is and larger as it comes down, and it goes with the dissolve.
func _apply_flight(y: float) -> void:
	var lift := maxf(y,0.0)
	set_meta(FLY_META,lift)
	for status in ["StellarBurn","StellarFrost","StellarStun"]:
		var group := get_node_or_null(status) as Node3D
		if group != null: group.position.y = lift
	if _shadow == null: return
	var base := maxf(float(_flight.get("altitude",1.2)),0.1)
	var k := clampf(1.0-0.28*(lift-base)/base,0.5,1.35)
	if _dying: k *= 1.0-_dissolve_amount()
	_shadow.visible = k > 0.03
	_shadow.scale = Vector3(k,1.0,k)

func _death_total() -> float:
	if _death_kind == "leak": return 0.4
	if _death_kind == "scatter": return _flee_wait+_flee_len
	match String(_motion.get("death","sink")):
		"topple", "topple_side": return 1.45
		"topple_back": return 1.5
		"splat": return 1.1
		_: return 1.15

func _dissolve_amount() -> float:
	var t := _death_t
	if _death_kind == "leak": return clampf(t/0.4,0.0,1.0)
	if _death_kind == "scatter":
		# Whole until the wave arrives. From there the material layer's cold glow starts
		# at once (it begins at 0.6 of its hold) and the body thins late in the run, so
		# the run itself is seen: still 85% there half way, 40% at 0.7, gone by 0.95.
		if t <= _flee_wait: return 0.0
		var glow := StellarShading.DISSOLVE_HOLD*0.6
		return glow+(1.0-glow)*pow(_flee_progress(),1.6)
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

## An escort whose stage boss fell: it flees instead of dying (see FLEE_SEC). `e.p` is
## where the simulator last had it, `e.sid` its spawn id (the same two values give
## StellarVfx the haze's place, moment and heading, so body and haze leave together).
func _begin_scatter(e: Dictionary) -> void:
	if _dying: return
	_begin_death("scatter")
	var sid := int(e.get("sid",0))
	var at: Vector2 = Balance.ARENA_CENTER
	if e.get("p") is Vector2: at = e["p"]
	elif is_inside_tree(): at = StellarWorld.logical(global_position)
	_flee_wait = StellarVfx.scatter_delay(at)
	var heading := StellarVfx.scatter_heading(at,sid)
	# A crowd must not leave as one machine: length and reach vary a little by spawn id
	# (no random numbers: a redraw or a second instance gives the same run).
	_flee_len = FLEE_SEC*(0.92+0.16*fposmod(float(sid)*0.6180339+0.31,1.0))
	_flee_reach = FLEE_DIST*(0.85+0.30*fposmod(float(sid)*0.7548777+0.63,1.0))
	var away := Vector3(heading.x,0.0,heading.y)
	if is_inside_tree(): away = global_transform.basis.inverse()*away
	away.y = 0.0
	_flee_dir = away.normalized() if away.length_squared() > 0.000001 else Vector3(0,0,1)
	# The body faces -Z; this is the turn that points it along the way out.
	_flee_yaw = atan2(-_flee_dir.x,-_flee_dir.z)
	_flee_run = 0.0
	# The last hit's flash and recoil belong to a fight that is over.
	_hit_scale = 1.0
	_recoil = Vector3.ZERO
	if _flash > 0.0:
		_flash = 0.0
		StellarShading.set_hit_flash(self,0.0)

## Fraction 0..1 of the run (0 until the wave arrives).
func _flee_progress() -> float:
	return clampf((_death_t-_flee_wait)/maxf(_flee_len,0.001),0.0,1.0)

## World units covered at run fraction u: a bolt. Most of the ground is covered while
## the body is still solid (71% by half way), and it runs out as the body thins, so the
## haze it turns into is left where it was last seen.
func _flee_travel(u: float) -> float:
	return _flee_reach*(1.0-pow(1.0-clampf(u,0.0,1.0),FLEE_EASE))

## One step of the scatter: blend weights and reaction layers move by dt, the pose is
## the idle while it waits and the MoveLoop at the distance it has run once it flees.
func _advance_scatter(dt: float) -> void:
	var fleeing := _death_t >= _flee_wait
	var k := dt/(FLEE_BLEND if fleeing else FADE)
	_w_move = move_toward(_w_move,1.0 if fleeing else 0.0,k)
	_w_idle = move_toward(_w_idle,0.0 if fleeing else 1.0,k)
	_w_attack = move_toward(_w_attack,0.0,k)
	_stand_t = fposmod(_stand_t+dt,float(_clips["IdleLoop"]["len"]))
	if _fly: _air_t = fposmod(_air_t+dt,_bob_period())
	_stumble = maxf(0.0,_stumble-dt/0.4)
	_daze = move_toward(_daze,0.0,dt/0.25)
	_bank = move_toward(_bank,0.0,dt*1.5)
	_bank_spring = Vector3(_bank,0.0,0.0)
	# The simulator's walk clock is seconds at Balance.PATH_SPEED: the same ratio keeps
	# the feet on the ground the pivot covers.
	if fleeing: _flee_run = _flee_travel(_flee_progress())*StellarWorld.UNIT/Balance.PATH_SPEED
	_compose(_clip_time(_last_motion)+_flee_run)

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
