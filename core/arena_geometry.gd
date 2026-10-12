extends RefCounted
class_name ArenaGeometry

## Shared geometry for rendering, navigation, free hero movement and the minimap.
const RADIUS := 600.0
const ROAD_WIDTH := 116.0
const ROUTE_COUNT := 4
const ROAD_REVISION := 4
const PLAZA_RADIUS := 103.0
## Enemy roads (2026-10-12): every gate first heads straight for the crystal, then
## bends onto the tangent and spirals slowly inward. Two opposite gates own a full
## spiral arm each (one turn and a bit around the crystal); the other two gates are
## straight feeder roads that join the nearest arm a quarter turn in. Four arms of
## this width would not fit a usable spiral, so the feeders keep four entrances.
const ARM_COUNT := 2
const GATE_RADIUS := RADIUS - 16.0
## The straight approach ends here; over BEND_LENGTH of road the heading eases from
## "toward the crystal" onto the spiral's tangent (no corner, no kerb fold).
const TURN_RADIUS := 560.0
const BEND_LENGTH := 150.0
## Radial distance between one arm's successive turns. The two arms interleave, so
## neighbouring roads are ARM_PITCH / 2 = 160 apart: a 116 road and 44 of soil.
const ARM_PITCH := 320.0
## Centreline sample spacing (logical units).
const SAMPLE := 12.0
const MAP_RECT := Rect2(Balance.ARENA_CENTER - Vector2.ONE * RADIUS, Vector2.ONE * RADIUS * 2)
const LEGACY_RECT := Rect2(Balance.ARENA_CENTER - Vector2(552, 408), Vector2(1104, 816))
## Per lane: the navigation polyline from the gate to the crystal. Feeder lanes
## continue along the arm they join, so a lane is a complete walk to the centre.
static var _routes: Array[PackedVector2Array] = []
## Unique road centrelines for drawing and road tests: two arms and two feeders.
## A feeder stops just inside its arm so neither surface is drawn twice.
static var _roads: Array[PackedVector2Array] = []
## Broad phase for road tests: every centreline segment is listed in the GRID cells its
## bounding box touches, so a query only measures the handful of segments around it
## instead of all ~420. The narrow test is unchanged (closest point on the segment).
const GRID := 60.0
static var _grid_w := 0
static var _grid: Array[PackedInt32Array] = []
static var _seg_a := PackedVector2Array()
static var _seg_b := PackedVector2Array()

static func contains(point: Vector2, margin: float = 0.0) -> bool:
	return point.is_finite() and point.distance_squared_to(Balance.ARENA_CENTER) <= pow(maxf(0.0, RADIUS - margin) + 0.001, 2)

static func clamp_point(point: Vector2, margin: float = 0.0) -> Vector2:
	return Balance.ARENA_CENTER + (point - Balance.ARENA_CENTER).limit_length(maxf(0.0, RADIUS - margin))

static func outline(segments: int = 96, margin: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		points.append(Balance.ARENA_CENTER + Vector2.from_angle(TAU * i / segments) * (RADIUS - margin))
	return points

static func _arm_base(arm: int) -> float:
	return arm * TAU / ARM_COUNT

## Exact spiral heading at a point: tangential, tilted inward so that dr/dtheta = -k.
static func _spiral_heading(rel: Vector2, k: float) -> Vector2:
	var r := rel.length()
	var out := rel / r
	return (Vector2(-out.y, out.x) * r - out * k).normalized()

## One arm: straight in from the gate, a smooth bend, then an Archimedean spiral down
## to the plaza. Returns {"points", "quarter"}: quarter is the index of the sample
## where the arm has swept a quarter turn, which is where its feeder road joins.
static func _arm(base: float) -> Dictionary:
	var k := ARM_PITCH / TAU
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
	var quarter := -1
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
			if quarter < 0 and theta >= PI * 0.5: quarter = points.size() - 1
	if since > 0.001: points.append(p)
	return {"points": points, "quarter": quarter}

static func _heading(rel: Vector2, k: float, travelled: float) -> Vector2:
	var inward := -rel.normalized()
	var blend := smoothstep(0.0, BEND_LENGTH, travelled)
	return inward.slerp(_spiral_heading(rel, k), blend).normalized()

static func _build() -> void:
	if not _routes.is_empty(): return
	var arms: Array[Dictionary] = []
	for arm in range(ARM_COUNT): arms.append(_arm(_arm_base(arm)))
	_roads.clear()
	_routes.clear()
	for arm in range(ARM_COUNT):
		var path: PackedVector2Array = arms[arm]["points"]
		_roads.append(path)
		var route := path.duplicate()
		route.append(Balance.ARENA_CENTER)
		_routes.append(route)
	# Feeders: from the gate between two arms, a straight road to the point a quarter
	# turn along the nearest arm. The lane then continues along that arm.
	for feeder in range(ROUTE_COUNT - ARM_COUNT):
		var arm := feeder % ARM_COUNT
		var path: PackedVector2Array = arms[arm]["points"]
		var join := int(arms[arm]["quarter"])
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

static func route_points(lane: int) -> PackedVector2Array:
	_build()
	return _routes[posmod(lane, ROUTE_COUNT)]

## Centrelines to draw: arms in full, feeders up to the arm they join.
static func road_polylines() -> Array[PackedVector2Array]:
	_build()
	return _roads

static func on_road(point: Vector2, margin: float = 0.0) -> bool:
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
