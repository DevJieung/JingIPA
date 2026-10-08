extends RefCounted
class_name HeroPlacement

## Footprints use the same logical ground coordinates as paths and combat.
static func position(hero: Dictionary) -> Vector2:
	return hero.get("position", Balance.post_position(int(hero.get("post", 0))))

static func ground_error(point: Vector2) -> String:
	var footprint := Balance.ROAD_WIDTH * 0.5
	if not point.is_finite() or not Balance.MAP_RECT.grow(-footprint).has_point(point):
		return "outside"
	if point.distance_to(Balance.ARENA_CENTER) < Balance.ALTAR_R + footprint:
		return "crystal"
	for route in range(2):
		var points := Balance.route_points(route)
		for i in range(points.size() - 1):
			var nearest := Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1])
			if point.distance_to(nearest) < Balance.ROAD_WIDTH * 0.5 + footprint:
				return "road"
	return ""

static func error(point: Vector2, occupied: Array[Vector2]) -> String:
	var reason := ground_error(point)
	if not reason.is_empty():
		return reason
	for other in occupied:
		if point.distance_to(other) < Balance.ROAD_WIDTH * 1.5:
			return "occupied"
	return ""

static func first_free(origin: Vector2, occupied: Array[Vector2]) -> Vector2:
	if error(origin, occupied).is_empty():
		return origin
	for post in Balance.POST_ORDER:
		var candidate := Balance.post_position(post)
		if error(candidate, occupied).is_empty():
			return candidate
	var step := Balance.ROAD_WIDTH * 1.5
	var area := Balance.MAP_RECT.grow(-Balance.ROAD_WIDTH)
	for y in range(int(area.position.y), int(area.end.y), int(step)):
		for x in range(int(area.position.x), int(area.end.x), int(step)):
			var candidate := Vector2(x, y)
			if error(candidate, occupied).is_empty():
				return candidate
	return Vector2.INF
