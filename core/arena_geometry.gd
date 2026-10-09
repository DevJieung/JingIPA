extends RefCounted
class_name ArenaGeometry

## Shared geometry for rendering, navigation, free hero movement and the minimap.
const RADIUS := 500.0
const ROAD_WIDTH := 90.0
const ROUTE_COUNT := 4
const ROAD_REVISION := 2
const PLAZA_RADIUS := 103.0
const MAP_RECT := Rect2(Balance.ARENA_CENTER - Vector2.ONE * RADIUS, Vector2.ONE * RADIUS * 2)
const LEGACY_RECT := Rect2(Balance.ARENA_CENTER - Vector2(552, 408), Vector2(1104, 816))
static var _routes: Array[PackedVector2Array] = []

static func contains(point: Vector2, margin: float = 0.0) -> bool:
	return point.is_finite() and point.distance_squared_to(Balance.ARENA_CENTER) <= pow(maxf(0.0, RADIUS - margin) + 0.001, 2)

static func clamp_point(point: Vector2, margin: float = 0.0) -> Vector2:
	return Balance.ARENA_CENTER + (point - Balance.ARENA_CENTER).limit_length(maxf(0.0, RADIUS - margin))

static func outline(segments: int = 96, margin: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		points.append(Balance.ARENA_CENTER + Vector2.from_angle(TAU * i / segments) * (RADIUS - margin))
	return points

static func route_points(lane: int) -> PackedVector2Array:
	if _routes.is_empty():
		# A winding double bend, rotated into four independent entrances. These exact
		# samples also draw the road; there is no separate visual-only route.
		var anchors := PackedVector2Array([Vector2(484, 0), Vector2(420, 15),
			Vector2(370, 125), Vector2(310, 270), Vector2(190, 330),
			Vector2(90, 300), Vector2(85, 225), Vector2(180, 210),
			Vector2(235, 130), Vector2(180, 75), Vector2(90, 70), Vector2.ZERO])
		for route in range(ROUTE_COUNT):
			var path := PackedVector2Array()
			for i in range(anchors.size() - 1):
				var a := anchors[maxi(0, i - 1)]
				var b := anchors[i]
				var c := anchors[i + 1]
				var d := anchors[mini(anchors.size() - 1, i + 2)]
				for sample in range(6):
					var t := sample / 6.0
					var p := 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t)
					path.append(Balance.ARENA_CENTER + p.rotated(route * TAU / ROUTE_COUNT))
			path.append(Balance.ARENA_CENTER)
			_routes.append(path)
	return _routes[posmod(lane, ROUTE_COUNT)]

static func on_road(point: Vector2, margin: float = 0.0) -> bool:
	if not contains(point, margin): return false
	if point.distance_squared_to(Balance.ARENA_CENTER) <= pow(maxf(0, PLAZA_RADIUS - margin), 2): return true
	var width_sq := pow(maxf(0, ROAD_WIDTH * 0.5 - margin), 2)
	for lane in range(ROUTE_COUNT):
		var path := route_points(lane)
		for i in range(path.size() - 1):
			if Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1]).distance_squared_to(point) <= width_sq:
				return true
	return false

static func nearest_road_point(point: Vector2) -> Vector2:
	var nearest := Balance.ARENA_CENTER
	var distance := point.distance_squared_to(nearest)
	for lane in range(ROUTE_COUNT):
		var path := route_points(lane)
		for i in range(path.size() - 1):
			var candidate := Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])
			if candidate.distance_squared_to(point) < distance:
				nearest = candidate
				distance = candidate.distance_squared_to(point)
	return nearest

static func road_direction(point: Vector2) -> Vector2:
	var distance := INF
	var direction := (Balance.ARENA_CENTER - point).normalized()
	for lane in range(ROUTE_COUNT):
		var path := route_points(lane)
		for i in range(path.size() - 1):
			var candidate := Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])
			if candidate.distance_squared_to(point) < distance:
				distance = candidate.distance_squared_to(point)
				direction = (path[i + 1] - path[i]).normalized()
	return direction

static func corners(rect: Rect2 = MAP_RECT) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])
