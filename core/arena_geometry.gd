extends RefCounted
class_name ArenaGeometry

## Continuous-arena layout in logical ground coordinates. Legacy route maps keep
## Balance.MAP_RECT; movement, navigation, saves and the minimap share this area.
const MAP_RECT := Rect2(Balance.ARENA_CENTER - Vector2(552, 408), Vector2(1104, 816))

static func corners(rect: Rect2 = MAP_RECT) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])
