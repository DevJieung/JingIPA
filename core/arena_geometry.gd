extends RefCounted
class_name ArenaGeometry

## Shared geometry for rendering, navigation, free hero movement and the minimap.
const RADIUS := 600.0
const ROAD_WIDTH := 116.0
## Most lanes any layout uses. The live number is route_count().
const MAX_ROUTES := 4
const ROAD_REVISION := 5
const PLAZA_RADIUS := 103.0
## Enemy roads. Every gate first heads straight for the crystal, then bends onto the
## tangent and spirals inward (2026-10-12). Since 2026-10-13 each battlefield owns one of
## several layouts built from the same two pieces, so the entrances differ per map:
##   arm     gate -> straight -> smooth bend -> Archimedean spiral down to the plaza
##   feeder  a straight road from its own gate that T-joins an arm part way along
## A layout key is "shape:turn:mirror": turn rotates the whole layout in 45 degree steps
## and mirror flips its handedness, so the same shape meets the player from new sides.
const GATE_RADIUS := RADIUS - 16.0
## The straight approach ends here; over BEND_LENGTH of road the heading eases from
## "toward the crystal" onto the spiral's tangent (no corner, no kerb fold).
const TURN_RADIUS := 560.0
const BEND_LENGTH := 150.0
## Centreline sample spacing (logical units).
const SAMPLE := 12.0
## shape -> arms (count, pitch = radial distance between one arm's successive turns)
## and feeders ([arm, sweep]: joins that arm after it has swept `sweep` turns).
## Arms of one shape are rotations of each other, so neighbouring roads stay
## pitch / count apart: never closer than the 116 road plus 44 of soil.
const SHAPES := {
	# Two interleaved spiral arms and two feeders (the 2026-10-12 field).
	"spiral": {"arms": 2, "pitch": 320.0, "feeders": [[0, 0.25], [1, 0.25]]},
	# Three arms, each a little under one turn.
	"pinwheel": {"arms": 3, "pitch": 480.0, "feeders": []},
	# Four short sweeping blades: every side is an entrance and the walk is short.
	"blades": {"arms": 4, "pitch": 960.0, "feeders": []},
	# One long road that winds almost twice around the crystal from a single gate.
	"coil": {"arms": 1, "pitch": 240.0, "feeders": []},
	# One spiral arm with three side gates joining it ever closer to the crystal.
	"fork": {"arms": 1, "pitch": 320.0, "feeders": [[0, 0.25], [0, 0.5], [0, 0.75]]},
}
const SHAPE_ORDER := ["spiral", "pinwheel", "blades", "coil", "fork"]
const DEFAULT_LAYOUT := "spiral:0:0"
const TURN_STEPS := 8
const MAP_RECT := Rect2(Balance.ARENA_CENTER - Vector2.ONE * RADIUS, Vector2.ONE * RADIUS * 2)
const LEGACY_RECT := Rect2(Balance.ARENA_CENTER - Vector2(552, 408), Vector2(1104, 816))
static var _layout := DEFAULT_LAYOUT
## Per lane: the navigation polyline from the gate to the crystal. Feeder lanes
## continue along the arm they join, so a lane is a complete walk to the centre.
static var _routes: Array[PackedVector2Array] = []
## Unique road centrelines for drawing and road tests: arms first, then feeders.
## A feeder stops just inside its arm so neither surface is drawn twice.
static var _roads: Array[PackedVector2Array] = []
static var _arm_roads := 0
## Broad phase for road tests: every centreline segment is listed in the GRID cells its
## bounding box touches, so a query only measures the handful of segments around it
## instead of all of them. The narrow test is unchanged (closest point on the segment).
const GRID := 60.0
static var _grid_w := 0
static var _grid: Array[PackedInt32Array] = []
static var _seg_a := PackedVector2Array()
static var _seg_b := PackedVector2Array()
## The C++ road tests (StellarRoads of addons/stellar_native, docs/PERF_NATIVE.md) built
## from the same roads, or null without the library: then the GDScript below answers.
static var _native = null

static func contains(point: Vector2, margin: float = 0.0) -> bool:
	return point.is_finite() and point.distance_squared_to(Balance.ARENA_CENTER) <= pow(maxf(0.0, RADIUS - margin) + 0.001, 2)

static func clamp_point(point: Vector2, margin: float = 0.0) -> Vector2:
	return Balance.ARENA_CENTER + (point - Balance.ARENA_CENTER).limit_length(maxf(0.0, RADIUS - margin))

static func outline(segments: int = 96, margin: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		points.append(Balance.ARENA_CENTER + Vector2.from_angle(TAU * i / segments) * (RADIUS - margin))
	return points

## Layout of a battlefield, fixed per theme so a map keeps its roads between runs.
static func layout_for_theme(index: int) -> String:
	var count := SHAPE_ORDER.size()
	var i := maxi(0, index)
	# Themes are listed by biome (ten each) and rank pair; stepping the shape by both
	# gives every biome all five shapes and neighbouring ranks different ones.
	var shape: String = SHAPE_ORDER[(i + i / 10) % count]
	return "%s:%d:%d" % [shape, (i * 3 + i / 10) % TURN_STEPS, (i / 5) % 2]

static func valid_layout(key: String) -> bool:
	var parts := key.split(":")
	return parts.size() == 3 and SHAPES.has(parts[0]) and parts[1].is_valid_int() and parts[2] in ["0", "1"] \
		and int(parts[1]) >= 0 and int(parts[1]) < TURN_STEPS

## Select the road layout every caller of this class sees. Returns true when it changed.
static func use_layout(key: String) -> bool:
	if not valid_layout(key): key = DEFAULT_LAYOUT
	if key == _layout and not _routes.is_empty(): return false
	_layout = key
	_routes.clear()
	_build()
	return true

static func layout() -> String:
	return _layout

static func shape() -> String:
	return _layout.get_slice(":", 0)

static func route_count() -> int:
	_build()
	return _routes.size()

## 0 for an arm, 1 for a feeder: feeders are drawn a hair higher so their mouths cover
## the arm's kerb instead of fighting it for the same depth.
static func road_layer(road: int) -> int:
	_build()
	return 0 if road < _arm_roads else 1

## Logical point on the rim where a lane's monsters step onto the field.
static func gate_point(lane: int, inset: float = 0.0) -> Vector2:
	var radial := (route_points(lane)[0] - Balance.ARENA_CENTER).normalized()
	return Balance.ARENA_CENTER + radial * (RADIUS - inset)

## Walking length of a lane from its gate to the crystal.
static func route_length(lane: int) -> float:
	var path := route_points(lane)
	var total := 0.0
	for i in range(path.size() - 1): total += path[i].distance_to(path[i + 1])
	return total

## Exact spiral heading at a point: tangential, tilted inward so that dr/dtheta = -k.
static func _spiral_heading(rel: Vector2, k: float) -> Vector2:
	var r := rel.length()
	var out := rel / r
	return (Vector2(-out.y, out.x) * r - out * k).normalized()

## One arm: straight in from the gate, a smooth bend, then an Archimedean spiral down
## to the plaza. Returns {"points", "marks"}: marks[i] is the index of the sample where
## the arm has swept sweeps[i] turns, which is where a feeder road joins.
static func _arm(base: float, pitch: float, sweeps: Array = []) -> Dictionary:
	var k := pitch / TAU
	var radial := Vector2.from_angle(base)
	var points := PackedVector2Array()
	var straight := GATE_RADIUS - TURN_RADIUS
	var count := maxi(1, ceili(straight / SAMPLE))
	for i in range(count + 1):
		points.append(Balance.ARENA_CENTER + radial * (GATE_RADIUS - straight * i / count))
	var p := points[-1]
	var travelled := 0.0
	var theta := 0.0
	var since := 0.0
	var marks: Array[int] = []
	for sweep in sweeps: marks.append(-1)
	var ds := 1.0
	while true:
		var rel := p - Balance.ARENA_CENTER
		if rel.length() <= PLAZA_RADIUS + 4.0: break
		# Midpoint step keeps the integrated pitch within a unit over a full turn.
		var head := _heading(rel, k, travelled)
		var mid := p + head * ds * 0.5
		head = _heading(mid - Balance.ARENA_CENTER, k, travelled + ds * 0.5)
		var next := p + head * ds
		theta += rel.angle_to(next - Balance.ARENA_CENTER)
		p = next
		travelled += ds
		since += ds
		if since >= SAMPLE - 0.001:
			points.append(p)
			since = 0.0
			for i in range(marks.size()):
				if marks[i] < 0 and theta >= TAU * float(sweeps[i]): marks[i] = points.size() - 1
	if since > 0.001: points.append(p)
	return {"points": points, "marks": marks}

static func _heading(rel: Vector2, k: float, travelled: float) -> Vector2:
	var inward := -rel.normalized()
	var blend := smoothstep(0.0, BEND_LENGTH, travelled)
	return inward.slerp(_spiral_heading(rel, k), blend).normalized()

static func _build() -> void:
	if not _routes.is_empty(): return
	var spec: Dictionary = SHAPES[_layout.get_slice(":", 0)]
	var arm_count := int(spec["arms"])
	var feeders: Array = spec["feeders"]
	var arms: Array[Dictionary] = []
	for arm in range(arm_count):
		var sweeps: Array = []
		for feeder in feeders:
			if int(feeder[0]) == arm: sweeps.append(float(feeder[1]))
		arms.append(_arm(arm * TAU / arm_count, float(spec["pitch"]), sweeps))
	_roads.clear()
	_routes.clear()
	for arm in range(arm_count):
		var path: PackedVector2Array = arms[arm]["points"]
		_roads.append(path)
		var route := path.duplicate()
		route.append(Balance.ARENA_CENTER)
		_routes.append(route)
	_arm_roads = arm_count
	# Feeders: a straight road from its own gate to a point part way along an arm.
	# The lane then continues along that arm.
	var used: Array[int] = []
	for arm in range(arm_count): used.append(0)
	for feeder in feeders:
		var arm := int(feeder[0])
		var path: PackedVector2Array = arms[arm]["points"]
		var join := int(arms[arm]["marks"][used[arm]])
		used[arm] += 1
		var junction := path[join]
		var angle := (junction - Balance.ARENA_CENTER).angle()
		var gate := Balance.ARENA_CENTER + Vector2.from_angle(angle) * GATE_RADIUS
		var count := maxi(1, ceili(gate.distance_to(junction) / SAMPLE))
		var stub := PackedVector2Array()
		for i in range(count + 1): stub.append(gate.lerp(junction, float(i) / count))
		var route := stub.duplicate()
		for i in range(join + 1, path.size()): route.append(path[i])
		route.append(Balance.ARENA_CENTER)
		_routes.append(route)
		# Drawn and tested up to the arm's edge; the arm's own surface covers the rest.
		var cut := ROAD_WIDTH * 0.5 - 10.0
		var road := PackedVector2Array()
		for p in stub:
			if p.distance_to(junction) <= cut: break
			road.append(p)
		road.append(junction + (gate - junction).normalized() * cut)
		_roads.append(road)
	# Turn and mirror the finished layout around the crystal.
	var turn := float(int(_layout.get_slice(":", 1))) * TAU / TURN_STEPS
	var mirror := _layout.get_slice(":", 2) == "1"
	if turn != 0.0 or mirror:
		for list in [_routes, _roads]:
			for n in range(list.size()):
				var moved := PackedVector2Array()
				for p in list[n]:
					var rel: Vector2 = p - Balance.ARENA_CENTER
					if mirror: rel.x = -rel.x
					moved.append(Balance.ARENA_CENTER + rel.rotated(turn))
				list[n] = moved
	_grid_w = ceili(MAP_RECT.size.x / GRID)
	_grid.clear()
	for i in range(_grid_w * _grid_w): _grid.append(PackedInt32Array())
	_seg_a.clear()
	_seg_b.clear()
	for road in _roads:
		for i in range(road.size() - 1):
			var index := _seg_a.size()
			_seg_a.append(road[i])
			_seg_b.append(road[i + 1])
			var lo := (road[i].min(road[i + 1]) - MAP_RECT.position) / GRID
			var hi := (road[i].max(road[i + 1]) - MAP_RECT.position) / GRID
			for gy in range(clampi(floori(lo.y), 0, _grid_w - 1), clampi(floori(hi.y), 0, _grid_w - 1) + 1):
				for gx in range(clampi(floori(lo.x), 0, _grid_w - 1), clampi(floori(hi.x), 0, _grid_w - 1) + 1):
					_grid[gy * _grid_w + gx].append(index)
	_native = Native.make("StellarRoads")
	if _native != null:
		_native.configure(Balance.ARENA_CENTER, RADIUS, PLAZA_RADIUS, ROAD_WIDTH, MAP_RECT, GRID, _roads)

## The native road tests of the current layout, or null without the library.
static func native():
	_build()
	return _native

static func route_points(lane: int) -> PackedVector2Array:
	_build()
	return _routes[posmod(lane, _routes.size())]

## Centrelines to draw: arms in full, feeders up to the arm they join.
static func road_polylines() -> Array[PackedVector2Array]:
	_build()
	return _roads

static func on_road(point: Vector2, margin: float = 0.0) -> bool:
	_build()
	if _native != null: return _native.on_road(point, margin)
	return on_road_script(point, margin)

## The grid-indexed GDScript test: what on_road answers without the library, and the
## reference the native kernel must match (on_road_exhaustive checks both).
static func on_road_script(point: Vector2, margin: float = 0.0) -> bool:
	if not contains(point, margin): return false
	if point.distance_squared_to(Balance.ARENA_CENTER) <= pow(maxf(0, PLAZA_RADIUS - margin), 2): return true
	_build()
	var half := maxf(0.0, ROAD_WIDTH * 0.5 - margin)
	var half_sq := half * half
	# A segment within `half` of the point has a point inside this square, and that
	# point's cell lists the segment.
	var local := point - MAP_RECT.position
	var x0 := clampi(floori((local.x - half) / GRID), 0, _grid_w - 1)
	var x1 := clampi(floori((local.x + half) / GRID), 0, _grid_w - 1)
	var y0 := clampi(floori((local.y - half) / GRID), 0, _grid_w - 1)
	var y1 := clampi(floori((local.y + half) / GRID), 0, _grid_w - 1)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			for index in _grid[gy * _grid_w + gx]:
				if Geometry2D.get_closest_point_to_segment(point, _seg_a[index], _seg_b[index]).distance_squared_to(point) <= half_sq:
					return true
	return false

## Reference implementation of on_road without the broad phase (checks only).
static func on_road_exhaustive(point: Vector2, margin: float = 0.0) -> bool:
	if not contains(point, margin): return false
	if point.distance_squared_to(Balance.ARENA_CENTER) <= pow(maxf(0, PLAZA_RADIUS - margin), 2): return true
	_build()
	var half_sq := pow(maxf(0.0, ROAD_WIDTH * 0.5 - margin), 2)
	for path in _roads:
		for i in range(path.size() - 1):
			if Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1]).distance_squared_to(point) <= half_sq:
				return true
	return false

static func nearest_road_point(point: Vector2) -> Vector2:
	_build()
	if _native != null: return _native.nearest_road_point(point)
	return nearest_road_point_script(point)

static func nearest_road_point_script(point: Vector2) -> Vector2:
	_build()
	var nearest := Balance.ARENA_CENTER
	var distance := point.distance_squared_to(nearest)
	for path in _roads:
		for i in range(path.size() - 1):
			var candidate := Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])
			if candidate.distance_squared_to(point) < distance:
				nearest = candidate
				distance = candidate.distance_squared_to(point)
	return nearest

static func road_direction(point: Vector2) -> Vector2:
	_build()
	if _native != null: return _native.road_direction(point)
	return road_direction_script(point)

static func road_direction_script(point: Vector2) -> Vector2:
	_build()
	var distance := INF
	var direction := (Balance.ARENA_CENTER - point).normalized()
	for path in _roads:
		for i in range(path.size() - 1):
			var candidate := Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])
			if candidate.distance_squared_to(point) < distance:
				distance = candidate.distance_squared_to(point)
				direction = (path[i + 1] - path[i]).normalized()
	return direction

static func corners(rect: Rect2 = MAP_RECT) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])
