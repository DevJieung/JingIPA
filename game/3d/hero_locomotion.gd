extends RefCounted
class_name HeroLocomotion

## Presentation-only locomotion, turning and upper-body aim state shared by the
## hero adapters. The world feeds simulation-derived velocity and facing; nothing
## here is read back by the simulation.
##
## Walk phase advances by travelled distance / cycle stride (no foot sliding), speed
## is smoothed so stopping blends into idle over ~0.2 s, the root turns toward
## its target with an ease-out profile that completes 180 degrees in under
## 0.25 s, and the upper body immediately twists toward the aim direction within
## AIM_LIMIT so release sockets agree with the real fire direction.
##
## Planted gait (2026-10-12): the rigs have rigid legs hinged at the hip with a long
## flat sole (toe `toe` ahead of the pivot, `heel` behind it). This class turns the
## phase into a stance/swing schedule per foot and solves the leg angle so that the
## planted foot rolls heel -> toe without moving on the ground: during the heel part
## of the stance the hip rides an arc about the heel, during the toe part an arc
## about the toe, and the body height follows the lowest sole point (the toe rocker
## rise is only partly honoured, TOE_ROCKER, so the push-off lifts the body a little
## instead of sinking the toe a lot). The stance fraction (duty) is 0.58 of the cycle
## at a heavy walk (double support), 0.50 at RUN_START and 0.32 at a full run (both
## feet off between steps, a short flight arc). The cycle stride is whatever makes the
## planted foot cover exactly its contact travel: stride = travel / duty. Short-legged
## heroes would need an absurd cadence for that, so the cadence is capped and the
## duty drops toward DUTY_MIN (they bound rather than blur).
##
## Gait by ground speed: characters travel at 2.0~5.1 world units/s
## (Balance.hero_speed, spd 0.60~1.50). run_factor() / slow_factor() still shape the
## look (lean, arm pump, lift) in the adapters.

const AIM_LIMIT := 1.2          # radians of torso twist before the root must turn
const TURN_GAIN := 18.0         # rad/s per radian remaining (ease-out)
const TURN_MIN := 3.5           # rad/s floor so turns finish
const TURN_MAX := 26.0          # rad/s cap
const WALK_FULL_SPEED := 0.9    # world units/s at which the walk clip plays fully
const ACCEL_TAU := 0.06
const DECEL_TAU := 0.10
const RUN_START := 2.6          # world units/s where the walk starts turning into a run
const RUN_FULL := 5.1           # spd 1.50: the full run look
const SLOW_FULL := 2.0          # spd 0.60: the full heavy-walk look
## Stance schedule.
const DUTY_WALK := 0.58         # planted fraction of the cycle per foot at the heavy walk
const DUTY_RUN := 0.32          # at the full run
const DUTY_MIN := 0.25          # never less planted than this (cadence cap takes over)
const CADENCE_MAX := 2.7        # cycles/s
const STRIKE_WINDOW := 0.10     # cycle fraction before the other foot lands: body pre-descends
## Leg swing relative to the authored clip amplitude: the heel strikes modestly ahead,
## the push-off extends well behind (how a straight-legged stride reads from the side).
const FRONT_WALK := 0.72
const FRONT_RUN := 0.92
const BACK_WALK := 1.15
const BACK_RUN := 1.45
const SLOW_SWING := 0.25        # heavy walkers take longer, planted strides
const SWING_MIN := 0.52         # the legs are procedural: short-legged clips (0.40) still step this wide
## A long sole behind the pivot lifts the hip at heel strike (the foot rocks onto its
## rear edge): the front swing is shortened until that rise stays within RISE_MAX_LEG *
## leg and the lost amplitude goes to the back swing (the lead foot lands under the
## body, the trailing leg extends further). A long sole ahead lifts the hip at push-off
## by sqrt(leg^2 + (share*toe)^2) - leg whatever the swing, so the honoured toe share is
## capped to keep that rise within the same limit (the rest of the toe sinks a little).
const RISE_MAX_LEG := 0.11
const DROP_MAX_LEG := 0.14      # push-off on a near-point front edge may not drop the hip more than this
const FRONT_MIN := 0.08
const BACK_MAX := 0.95
## Vertical shaping in units of the leg (hip pivot height).
const TOE_ROCKER := 0.8         # share of the toe-pivot rise honoured by the body (rest sinks the toe)
const LIFT_LEG := 0.20          # swing foot clearance at a walk
const LIFT_RUN := 0.6           # extra clearance at the full run (knee lift)
const FLIGHT_LEG := 0.10        # flight apex at a full-length flight (both feet off 17 % of the cycle)
const SETTLE_LEG := 0.025       # weight settle right after the heel strike
const NOD := 0.03               # torso nod (rad) at the strike
## Start/stop lean (2026-10-18, motion beats): a second-order spring trails the smoothed
## ground speed and the torso leans by the LAG between the two (forward while gaining
## speed, back while braking, nothing at a steady pace — the steady run lean is
## gait_lean()). r is 0 on purpose: an initial response > 0 makes the spring lead the
## speed during the 0.06 s ramp, so the lag flips sign and the body jerks back while it
## is still accelerating. At 3.5 Hz / zeta 0.45 the brake leans back 0.17 rad within
## 0.15 s and swings once past upright before it settles (< 0.4 s).
const LEAN_GAIN := 0.9
const LEAN_F := 3.5
const LEAN_ZETA := 0.45
const LEAN_PITCH_MIN := -0.20
const LEAN_PITCH_MAX := 0.25
## Turn bank: the roll target follows the yaw rate (0.02 s of yaw per radian of roll,
## clamped) and goes through the same spring so a turn banks in and swings back once.
const BANK_GAIN := 0.02
const BANK_MAX := 0.18
const BANK_F := 3.0
const BANK_ZETA := 0.5

var stride := 1.5               # authored clip stride (manifest); kept for stride_scale()
var leg := 0.48                 # hip pivot height above the sole (model units)
var toe := 0.28                 # sole reach ahead of the pivot
var heel := 0.08                # sole reach behind the pivot
var swing := 0.62               # authored leg swing amplitude (rad)
var speed := 0.0                # smoothed ground speed (world units/s)
var raw_speed := 0.0
var walk_phase := 0.0           # cycles, fractional part is the gait phase (L strike 0, R strike 0.5)
var move_dir := Vector2(0, 1)   # logical direction of travel
var yaw := 0.0                  # root rotation.y driven by face_toward
var yaw_rate := 0.0             # rad/s, for lean
var aim_delta := 0.0            # upper body twist (radians) relative to the root
var lean_roll := 0.0
var lean_pitch := 0.0
var face_target := Vector2.INF
var _face_hint := 0.0
var _faced := false
var _accel := 0.0
var _yaw_started := false
var _front := 0.45
var _back := 0.71
var _duty := 0.5
var _cycle := 1.3
var _toe_share := TOE_ROCKER
var _lean_spring := Vector3.ZERO    # sod_step state for the speed spring (y, y', last x)
var _bank_spring := Vector3.ZERO    # sod_step state for the roll spring

func _init() -> void:
	_update_gait()

## Rig geometry in model units: hip pivot height, sole reach ahead/behind the pivot
## and the authored leg swing amplitude (radians).
func set_gait_geometry(leg_length: float, toe_reach: float, heel_reach: float, swing_amplitude: float) -> void:
	leg = maxf(leg_length, 0.05)
	toe = maxf(toe_reach, 0.0)
	heel = maxf(heel_reach, 0.0)
	swing = clampf(maxf(swing_amplitude, SWING_MIN), 0.15, 1.2)
	_update_gait()

func walk_weight() -> float:
	return clampf(speed / WALK_FULL_SPEED, 0.0, 1.0)

## 0 at a walk (<= RUN_START), 1 at a full run (>= RUN_FULL).
func run_factor() -> float:
	return smoothstep(RUN_START, RUN_FULL, speed)

## Linear version of run_factor for the stance schedule.
func run_lin() -> float:
	return clampf((speed - RUN_START) / (RUN_FULL - RUN_START), 0.0, 1.0)

## 1 at a heavy walk (<= SLOW_FULL), 0 from RUN_START up.
func slow_factor() -> float:
	return clampf((RUN_START - speed) / (RUN_START - SLOW_FULL), 0.0, 1.0)

## Cycle stride over the authored clip stride (review aid).
func stride_scale() -> float:
	return _cycle / maxf(stride, 0.2)

## Distance travelled per gait cycle at the current speed (no foot sliding).
func cycle_stride() -> float:
	return _cycle

## Planted fraction of the cycle per foot.
func duty() -> float:
	return _duty

func front_swing() -> float:
	return _front

func back_swing() -> float:
	return _back

## Ground the planted sole covers from heel strike to toe-off (model units).
func contact_travel() -> float:
	return leg * sin(_front) + heel * (1.0 - cos(_front)) + leg * sin(_back) + toe * (1.0 - cos(_back))

## Extra torso lean from the gait (radians about the hips, + forward): runners lean
## in, heavy walkers stand up straighter than the authored brisk walk.
func gait_lean() -> float:
	return 0.10 * run_factor() - 0.05 * slow_factor()

func is_moving() -> bool:
	return speed > 0.05

## Velocity in world units per second; dt is the simulated interval (0 on paused redraws).
func set_locomotion(velocity: Vector3, dt: float) -> void:
	var ground := Vector2(velocity.x, velocity.z)
	raw_speed = ground.length()
	if raw_speed > 0.05: move_dir = ground.normalized()
	if dt <= 0.0: return
	var previous := speed
	var tau := ACCEL_TAU if raw_speed > speed else DECEL_TAU
	speed += (raw_speed - speed) * (1.0 - exp(-dt / tau))
	if raw_speed <= 0.001 and speed < 0.02: speed = 0.0
	_accel = (speed - previous) / dt
	_update_gait()
	if speed > 0.0: walk_phase = fposmod(walk_phase + speed * dt / maxf(_cycle, 0.2), 1.0)

func _update_gait() -> void:
	var r := run_lin()
	var s := slow_factor()
	var front := swing * lerpf(FRONT_WALK, FRONT_RUN, r) * (1.0 + SLOW_SWING * s)
	var back := swing * lerpf(BACK_WALK, BACK_RUN, r) * (1.0 + SLOW_SWING * s)
	var limit := RISE_MAX_LEG * leg
	var reach_max := sqrt(pow(leg + limit, 2.0) - leg * leg)
	_toe_share = minf(TOE_ROCKER, reach_max / maxf(toe, 0.001))
	_front = maxf(_limited_swing(front, heel, 1.0, limit), FRONT_MIN)
	_back = _limited_drop(minf(back + (front - _front), BACK_MAX), toe, _toe_share, DROP_MAX_LEG * leg)
	var travel := maxf(contact_travel(), 0.05)
	var d := 0.5 + (DUTY_WALK - 0.5) * s - (0.5 - DUTY_RUN) * r
	var cycle := travel / d
	if speed > 0.0 and speed / cycle > CADENCE_MAX:
		cycle = speed / CADENCE_MAX
		d = maxf(DUTY_MIN, travel / cycle)
	_duty = d
	_cycle = cycle

## Largest swing <= `nominal` whose rocker rise (reach * share * sin A - leg * (1 - cos A))
## stays under `limit`; the rise grows with A over the range used here, so bisect.
func _limited_swing(nominal: float, reach: float, share: float, limit: float) -> float:
	if reach * share * sin(nominal) - leg * (1.0 - cos(nominal)) <= limit: return nominal
	var lo := 0.0
	var hi := nominal
	for n in range(12):
		var mid := 0.5 * (lo + hi)
		if reach * share * sin(mid) - leg * (1.0 - cos(mid)) <= limit: lo = mid
		else: hi = mid
	return lo

## Largest swing <= `nominal` whose hip drop (leg * (1 - cos A) - reach * share * sin A)
## stays under `limit`; the drop has a minimum at tan A = reach * share / leg and grows
## past it, so bisect on that rising side.
func _limited_drop(nominal: float, reach: float, share: float, limit: float) -> float:
	var drop := func(a: float) -> float: return leg * (1.0 - cos(a)) - reach * share * sin(a)
	if drop.call(nominal) <= limit: return nominal
	var lo := minf(atan2(reach * share, leg), nominal)
	var hi := nominal
	for n in range(12):
		var mid := 0.5 * (lo + hi)
		if drop.call(mid) <= limit: lo = mid
		else: hi = mid
	return lo

## --- planted gait ------------------------------------------------------------
## Per-foot schedule at the current phase: {"angle": hip rotation (rad, + = foot ahead),
## "lift": swing clearance (model units), "stance": bool, "u": local phase, "p": progress
## through the stance or the swing}. Left strikes at phase 0, right at 0.5.
func leg_state(side: String) -> Dictionary:
	var u := fposmod(walk_phase - (0.0 if side == "L" else 0.5), 1.0)
	if u < _duty:
		var p := u / _duty
		return {"angle": _stance_angle(p), "lift": 0.0, "stance": true, "u": u, "p": p}
	var w := (u - _duty) / (1.0 - _duty)
	var angle := -_back + (_front + _back) * (0.5 - 0.5 * cos(PI * w))
	var lift := _lift() * sin(PI * pow(w, 0.55))
	return {"angle": angle, "lift": lift, "stance": false, "u": u, "p": w}

## Hip rotation while the planted sole rolls heel -> toe with the body advancing
## p * contact_travel() since the strike (the foot never moves on the ground).
func _stance_angle(p: float) -> float:
	var d_heel := leg * sin(_front) + heel * (1.0 - cos(_front))
	var d_toe := leg * sin(_back) + toe * (1.0 - cos(_back))
	var s := clampf(p, 0.0, 1.0) * (d_heel + d_toe)
	if s <= d_heel:
		var rh := sqrt(leg * leg + heel * heel)
		var beta := atan2(heel, leg)
		var c := leg * sin(_front) - heel * cos(_front) - s
		return asin(clampf(c / rh, -1.0, 1.0)) + beta
	var rt := sqrt(leg * leg + toe * toe)
	var alpha := atan2(toe, leg)
	return asin(clampf((d_heel + toe - s) / rt, -1.0, 1.0)) - alpha

## Body (hip) vertical offset that keeps the sole of a leg at `angle` on the ground.
func _body_for(angle: float) -> float:
	if angle >= 0.0: return -(leg * (1.0 - cos(angle)) - heel * sin(angle))
	return -(leg * (1.0 - cos(angle)) - _toe_share * toe * sin(-angle))

func _lift() -> float:
	return LIFT_LEG * leg * (1.0 + LIFT_RUN * run_lin())

## Hip vertical offset (model units, relative to the standing height) at the current
## phase: follows the planted sole, pre-descends before the next strike, settles a
## little after it and arcs through the air when both feet are off the ground.
func body_height() -> float:
	var h := INF
	for side in ["L", "R"]:
		var st := leg_state(side)
		if not st["stance"]: continue
		var req := _body_for(float(st["angle"]))
		var u := float(st["u"])
		if _duty > 0.5 and u > 0.5 - STRIKE_WINDOW and u < 0.5:
			req = lerpf(req, _body_for(_front), smoothstep(0.5 - STRIKE_WINDOW, 0.5, u))
		var p := float(st["p"])
		if p < 0.15: req -= SETTLE_LEG * leg * (1.0 + run_lin()) * sin(PI * p / 0.15)
		h = minf(h, req)
	if h != INF: return h
	# Flight: the last foot left at u = duty, the next lands at 0.5.
	var u := fposmod(walk_phase, 0.5)
	var w := clampf((u - _duty) / maxf(0.5 - _duty, 0.001), 0.0, 1.0)
	var apex := FLIGHT_LEG * leg * clampf((0.5 - _duty) / 0.17, 0.0, 1.0)
	return lerpf(_body_for(-_back), _body_for(_front), w) + apex * 4.0 * w * (1.0 - w)

## Short torso nod (rad, + forward) as the weight lands on the new foot.
func strike_nod() -> float:
	var u := fposmod(walk_phase, 0.5)
	if u >= 0.12 * _duty * 2.0: return 0.0
	return NOD * (1.0 + run_lin()) * sin(PI * u / (0.12 * _duty * 2.0))

## Logical target direction (+y south). dt is the simulated interval, 0 when unknown.
func face_toward(direction: Vector2, dt: float) -> void:
	if direction.length_squared() <= 0.000001: return
	face_target = direction.normalized()
	_face_hint = maxf(dt, 0.0)
	_faced = true

static func yaw_of(direction: Vector2) -> float:
	return atan2(-direction.x, -direction.y)

## Integrate turning for this rendered sample. clock_dt is the clock advance since
## the previous sample (0 on paused redraws). Returns true when the root yaw is owned.
func update(clock_dt: float) -> bool:
	# A facing sample's dt is consumed once; redraws without new input hold still.
	var step := _face_hint if _face_hint > 0.0 else clampf(clock_dt, 0.0, 0.1)
	_face_hint = 0.0
	if not _faced:
		_relax(step)
		return false
	var aim_yaw := yaw_of(face_target)
	var root_target := aim_yaw
	# While travelling, the legs keep the direction of travel as long as the aim
	# stays within the torso's reach; beyond that the whole body turns.
	if is_moving():
		var travel_yaw := yaw_of(move_dir)
		if absf(wrapf(aim_yaw - travel_yaw, -PI, PI)) <= AIM_LIMIT: root_target = travel_yaw
	if not _yaw_started:
		yaw = root_target
		_yaw_started = true
		yaw_rate = 0.0
	else:
		var remaining := wrapf(root_target - yaw, -PI, PI)
		var rate := clampf(TURN_GAIN * absf(remaining), TURN_MIN, TURN_MAX)
		var move := minf(absf(remaining), rate * step)
		if absf(remaining) - move < 0.003: move = absf(remaining)
		yaw = wrapf(yaw + signf(remaining) * move, -PI, PI)
		if step > 0.0: yaw_rate = lerpf(yaw_rate, signf(remaining) * move / step, 1.0 - exp(-step / 0.05))
	aim_delta = clampf(wrapf(aim_yaw - yaw, -PI, PI), -AIM_LIMIT, AIM_LIMIT)
	_relax(step)
	return true

## The world may set rotation.y directly outside battle; keep turning continuous.
func sync_yaw(value: float) -> void:
	if _yaw_started: yaw = wrapf(value, -PI, PI)

func _relax(step: float) -> void:
	if step <= 0.0: return
	var k := 1.0 - exp(-step / 0.08)
	# Lag lean: the spring follows the speed; the torso leans by what the spring still
	# owes (see LEAN_*). Advanced only by a positive step, so paused redraws hold.
	_lean_spring = sod_step(_lean_spring, speed, step, LEAN_F, LEAN_ZETA, 0.0)
	var pitch_target := clampf(LEAN_GAIN * (speed - _lean_spring.x) / WALK_FULL_SPEED, LEAN_PITCH_MIN, LEAN_PITCH_MAX)
	lean_pitch = lerpf(lean_pitch, pitch_target, k)
	# Turn bank through the spring: banks into the turn, swings back once as it ends.
	var roll_target := clampf(-yaw_rate * BANK_GAIN, -BANK_MAX, BANK_MAX) * clampf(speed / WALK_FULL_SPEED, 0.35, 1.0)
	_bank_spring = sod_step(_bank_spring, roll_target, step, BANK_F, BANK_ZETA, 0.0)
	lean_roll = clampf(_bank_spring.x, -BANK_MAX * 1.25, BANK_MAX * 1.25)
	if absf(lean_roll) < 0.0005 and absf(roll_target) < 0.0005 and absf(_bank_spring.y) < 0.002:
		lean_roll = 0.0
		_bank_spring = Vector3(0.0, 0.0, roll_target)
	_accel = lerpf(_accel, 0.0, k)

## One semi-implicit Euler step of a second-order system (t3ssel8r's "second order
## dynamics"): `state` is (y, y', previous target), f the natural frequency in Hz, zeta
## the damping ratio (< 1 overshoots once, 1 none), r the initial response (0 = none,
## > 0 leads the input, < 0 anticipates against it). dt-stable: the stiffness term is
## raised to the semi-implicit bound for this dt, so a large simulated step never
## explodes. Returns the new state; a zero or negative dt returns the state unchanged.
static func sod_step(state: Vector3, target: float, dt: float, f: float = 4.0, zeta: float = 0.5, r: float = 1.5) -> Vector3:
	if dt <= 0.0: return state
	var hz := maxf(f, 0.01)
	var w := TAU * hz
	var k1 := zeta / (PI * hz)
	var k2 := 1.0 / (w * w)
	var k3 := r * zeta / w
	var xd := (target - state.z) / dt
	var k2_stable := maxf(k2, 1.1 * (dt * dt / 4.0 + dt * k1 / 2.0))
	var y := state.x + dt * state.y
	var yd := state.y + dt * (target + k3 * xd - y - k1 * state.y) / k2_stable
	return Vector3(y, yd, target)

## Previews and formation screens show a calm, untwisted body.
func clear_battle() -> void:
	speed = 0.0
	raw_speed = 0.0
	aim_delta = 0.0
	yaw_rate = 0.0
	lean_roll = 0.0
	lean_pitch = 0.0
	_accel = 0.0
	_lean_spring = Vector3.ZERO
	_bank_spring = Vector3.ZERO
	_update_gait()
