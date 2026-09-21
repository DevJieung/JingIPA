extends RefCounted
class_name Battlefield

const MATERIALS := "res://art/terrain/biome_materials.png"
const BODIES := ["aqua", "flame", "wood", "rock", "frost"]
static var _materials: Dictionary = {}

static func material(theme: Dictionary, road: bool) -> Texture2D:
	var row := maxi(0, BODIES.find(String(theme.get("main_body", "rock"))))
	var key := row * 2 + int(road)
	if _materials.has(key):
		return _materials[key]
	var sheet := Art.tex(MATERIALS)
	if sheet == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = sheet
	var cell := Vector2(sheet.get_width() / 2.0, sheet.get_height() / 5.0)
	texture.region = Rect2(Vector2(cell.x * int(road), cell.y * row).round(), cell.round()).grow(-1)
	_materials[key] = texture
	return texture

static func _tile_rect(ci: CanvasItem, texture: Texture2D, rect: Rect2, color: Color) -> void:
	if texture == null or not rect.has_area():
		return
	var tile := Vector2(144, 72)
	var start := (rect.position / tile).floor() * tile
	for y in range(int(start.y), ceili(rect.end.y), int(tile.y)):
		for x in range(int(start.x), ceili(rect.end.x), int(tile.x)):
			var cell := Rect2(Vector2(x, y), tile)
			var part := cell.intersection(rect)
			var source := Rect2((part.position - cell.position) / tile * texture.get_size(), part.size / tile * texture.get_size())
			ci.draw_texture_rect_region(texture, part, source, color)

## Rendering and simulation use the very same route coordinates.
static func draw_map(ci: CanvasItem, time: float = 0.0, tint: Color = Color.WHITE) -> void:
	Look.material_panel(ci, Balance.MAP_RECT, Color("#202e31"), Look.PANEL_EDGE, "stone")
	var theme := Run.theme_for(Run.wave)
	var ground := material(theme, false)
	var road := material(theme, true)
	var floor_drawn := Art.draw_fill(ci, String(theme.get("art_floor", "")), Balance.MAP_RECT, tint)
	_tile_rect(ci, ground, Balance.MAP_RECT, Color(tint, 0.42 if floor_drawn else 1.0))
	# Quiet terrain under the road so all five biomes retain the same route contrast.
	ci.draw_rect(Balance.MAP_RECT, Color(0.025, 0.055, 0.065, 0.38))
	var edge := Color("#d1cdb7").lerp(Color(String(theme.get("floor", "#39464b"))), 0.18)
	var paving := Color(String(theme.get("floor", "#39464b"))).lerp(Color("#84918b"), 0.64)
	for route in range(2):
		var pts := Balance.route_points(route)
		var col := edge.lightened(0.3)
		ci.draw_polyline(pts, Color("#111a20"), Balance.ROAD_WIDTH + 12.0, false)
		ci.draw_polyline(pts, edge * tint, Balance.ROAD_WIDTH + 4.0, false)
		ci.draw_polyline(pts, paving * tint, Balance.ROAD_WIDTH - 4.0, false)
		# The material is clipped to the same axis-aligned segments used by BattleSim.
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var segment := Rect2(a.min(b), (b - a).abs()).grow((Balance.ROAD_WIDTH - 4.0) * 0.5)
			_tile_rect(ci, road, segment.intersection(Balance.MAP_RECT), Color(tint * edge.lerp(Color.WHITE, 0.82), 0.32))
		for i in range(16):
			var distance := fmod(float(i) * Balance.path_len() / 16.0 + time * 16.0, Balance.path_len())
			var p := Balance.path_at(distance, 0.0, route)
			var d := (Balance.path_at(distance + 5.0, 0.0, route) - p).normalized()
			if d.length_squared() > 0.1:
				ci.draw_polyline(PackedVector2Array([p - d * 5.0 + d.orthogonal() * 4.0,
					p, p - d * 5.0 - d.orthogonal() * 4.0]), Color(col.lightened(0.15), 0.80), 2.0)
		var gate: Vector2 = pts[0]
		Look.px_panel(ci, Rect2(gate - Vector2(12, 20), Vector2(24, 40)), Look.RED.darkened(0.4), Look.GOLD_DEEP, 0.2)

## Draw only the part inside the map so long ranges cannot cover hall controls.
static func draw_range(ci: CanvasItem, origin: Vector2, radius: float, color: Color) -> void:
	if radius <= 0:
		return
	var disk := PackedVector2Array()
	for i in range(97):
		disk.append(origin + Vector2.from_angle(float(i) * TAU / 96) * radius)
	var box := PackedVector2Array([Balance.MAP_RECT.position, Vector2(Balance.MAP_RECT.end.x, Balance.MAP_RECT.position.y),
		Balance.MAP_RECT.end, Vector2(Balance.MAP_RECT.position.x, Balance.MAP_RECT.end.y)])
	for polygon in Geometry2D.intersect_polygons(disk, box):
		if polygon.size() >= 3:
			ci.draw_colored_polygon(polygon, Color(color, 0.07))
	for i in range(96):
		if i % 4 < 2 and Balance.MAP_RECT.has_point(disk[i]) and Balance.MAP_RECT.has_point(disk[i + 1]):
			ci.draw_line(disk[i], disk[i + 1], Color(Look.BG_DEEP, 0.9), 5.0, false)
			ci.draw_line(disk[i], disk[i + 1], Color(color, 0.95), 2.0, false)


static func draw_post(ci: CanvasItem, post: int, selected: bool, available: bool = false) -> void:
	var p := Balance.post_position(post)
	var occupied := Run.hero_at_post(post) >= 0
	var col := Look.GOLD if selected else (Look.CRYSTAL if available else Color("#b5c6be"))
	var r := Rect2(p - Vector2(32, 16), Vector2(64, 32))
	Look.px_panel(ci, r.grow(3), Look.BG_DEEP, Look.BG_DEEP)
	Look.px_panel(ci, r, Color("#193740") if available else Color("#1a2b32"), col, 0.16)
	ci.draw_line(p + Vector2(-21, 6), p + Vector2(21, 6), col, 2)
	if not occupied:
		var center := p - Vector2(0, 30)
		ci.draw_circle(center, 13, Look.BG_DEEP)
		ci.draw_line(center - Vector2(7, 0), center + Vector2(7, 0), col, 3)
		ci.draw_line(center - Vector2(0, 7), center + Vector2(0, 7), col, 3)
	if selected or (available and not occupied):
		Look.draw_brackets(ci, Rect2(p - Vector2(33, 78), Vector2(66, 96)), 12.0, col)
