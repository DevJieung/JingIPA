extends RefCounted
class_name HeroLocomotion

## Presentation-only locomotion, turning and upper-body aim state shared by the
## hero adapters. The world feeds simulation-derived velocity and facing; nothing
## here is read back by the simulation.
##
## Walk phase advances by travelled distance / stride (no foot sliding), speed
## is smoothed so stopping blends into idle over ~0.2 s, the root turns toward
## its target with an ease-out profile that completes 180 degrees in under
## 0.25 s, and the upper body immediately twists toward the aim direction within
## AIM_LIMIT so release sockets agree with the real fire direction.

const AIM_LIMIT := 1.2          # radians of torso twist before the root must turn
const TURN_GAIN := 18.0         # rad/s per radian remaining (ease-out)
const TURN_MIN := 3.5           # rad/s floor so turns finish
const TURN_MAX := 26.0          # rad/s cap
const WALK_FULL_SPEED := 0.9    # world units/s at which the walk clip plays fully
const ACCEL_TAU := 0.06
const DECEL_TAU := 0.10

var stride := 1.5
var speed := 0.0                # smoothed ground speed (world units/s)
var raw_speed := 0.0
var walk_phase := 0.0           # cycles, fractional part is the clip phase
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

func walk_weight() -> float:
	return clampf(speed / WALK_FULL_SPEED, 0.0, 1.0)

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
	if speed > 0.0: walk_phase = fposmod(walk_phase + speed * dt / maxf(stride, 0.2), 1.0)

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
	lean_roll = lerpf(lean_roll, clampf(-yaw_rate * 0.012, -0.12, 0.12) * clampf(speed / WALK_FULL_SPEED, 0.35, 1.0), k)
	lean_pitch = lerpf(lean_pitch, clampf(_accel * 0.012, -0.08, 0.10), k)
	_accel = lerpf(_accel, 0.0, k)

## Previews and formation screens show a calm, untwisted body.
func clear_battle() -> void:
	speed = 0.0
	raw_speed = 0.0
	aim_delta = 0.0
	yaw_rate = 0.0
	lean_roll = 0.0
	lean_pitch = 0.0
	_accel = 0.0
