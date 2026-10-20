extends RefCounted
class_name Constellation

## The eight constellations of Balance.TALENTS: their star maps, the seal that stands for
## one node, and the surfaces that show nodes (2026-10-17 maps; 2026-10-19 rebuild for the
## feedback F2 "a map to check every node at a glance" and F3 "a striking node design").
##
## Nothing here changes a rule. The table and the picks are read through Balance and
## Talents; a node's state comes from states() (= Talents.state for every node at once).
## Art lives in art/ui/talents/ (tools/talent_art.py): one atlas of seal frames, glows and
## the eight emblems, and one glyph per node (<id>.png). Without the art every surface
## still draws, with plain shapes and the vector glyphs of Look.draw_passive_icon.

# =========================================================================== #
# 2026-10-17 drawing, still called by the level-up popup and the viewer inside
# ArenaScreen until that popup moves to game/arena_talent_view.gd. It is kept exactly
# as it was (the screen split compares its pictures pixel by pixel) and it keeps the
# old rows by table tier in _tier_map(). New drawing uses map(), rows by graph depth.
# =========================================================================== #
const DEPTH_Y := [0.84, 0.50, 0.16]
## Layouts per constellation, built on first use: {"nodes": {id: Vector2(0..1)}, "edges": [[from, to, any]]}.
static var _maps: Dictionary = {}


static func _tier_map(group: String) -> Dictionary:
	if _maps.has(group):
		return _maps[group]
	var rows := {1: [], 2: [], 3: []}
	for node in Balance.TALENTS:
		if String(node["group"]) != group:
			continue
		rows[clampi(int(node.get("tier", 1)), 1, 3)].append(node)
	var at := {}
	var edges: Array = []
	for tier in [1, 2, 3]:
		var row: Array = rows[tier]
		if tier > 1:
			# Children sit over their parents: order the row by the mean x of what it needs.
			row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _parent_x(a, at) < _parent_x(b, at))
		var xs: Array = []
		for i in range(row.size()):
			var even := (float(i) + 1.0) / (float(row.size()) + 1.0)
			xs.append(even if tier == 1 else lerpf(even, _parent_x(row[i], at), 0.45))
		xs = _spread(xs, 1.0 / (float(row.size()) + 1.0) * 0.72)
		for i in range(row.size()):
			at[String(row[i]["id"])] = Vector2(float(xs[i]), DEPTH_Y[tier - 1])
	for node in Balance.TALENTS:
		if String(node["group"]) != group:
			continue
		for clause in String(node.get("req", "")).split(",", false):
			var options: PackedStringArray = String(clause).split("|", false)
			for option in options:
				var parent := String(option).strip_edges()
				if at.has(parent):
					edges.append([parent, String(node["id"]), options.size() > 1])
	_maps[group] = {"nodes": at, "edges": edges}
	return _maps[group]


static func _parent_x(node: Dictionary, at: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for clause in String(node.get("req", "")).split(",", false):
		for option in String(clause).split("|", false):
			var parent := String(option).strip_edges()
			if at.has(parent):
				total += (at[parent] as Vector2).x
				count += 1
	return total / float(count) if count > 0 else 0.5


## Keep a row's points at least `gap` apart (in order) and inside 0.08..0.92.
static func _spread(xs: Array, gap: float) -> Array:
	var out: Array = xs.duplicate()
	for i in range(1, out.size()):
		out[i] = maxf(float(out[i]), float(out[i - 1]) + gap)
	if out.is_empty():
		return out
	var low := float(out[0])
	var high := float(out[-1])
	var span := high - low
	if span > 0.84:
		for i in range(out.size()):
			out[i] = 0.08 + (float(out[i]) - low) / span * 0.84
	else:
		var shift := 0.5 - (low + high) * 0.5
		for i in range(out.size()):
			out[i] = float(out[i]) + shift
	return out


## State of one node for drawing: 3 lit (joined), 2 open (could be joined), 1 far.
static func state_of(id: String, taken: Dictionary) -> int:
	if int(taken.get(id, 0)) > 0:
		return 3
	return 2 if Talents.requirements_met(Talents.by_id(id), taken) else 1


## The map inside `rect`. `highlight` is the node on offer (drawn bright and ringed),
## `time` breathes the ring and `settled` stops it. Returns the screen position of the
## highlighted node (or the rect's centre).
static func draw_map(ci: CanvasItem, rect: Rect2, group: String, taken: Dictionary,
		highlight: String = "", time: float = 0.0, settled: bool = true, alpha: float = 1.0) -> Vector2:
	var info: Dictionary = Balance.TALENT_GROUPS.get(group, {})
	var color := Color(String(info.get("color", "#b9cad3")))
	var layout := _tier_map(group)
	var nodes: Dictionary = layout["nodes"]
	var inset := Vector2(14, 10)
	var span := rect.size - inset * 2.0
	var found := rect.get_center()
	var pos := {}
	for id in nodes:
		pos[id] = rect.position + inset + (nodes[id] as Vector2) * span
	for edge in layout["edges"]:
		var a: Vector2 = pos[edge[0]]
		var b: Vector2 = pos[edge[1]]
		var lit := int(taken.get(String(edge[0]), 0)) > 0
		var both := lit and int(taken.get(String(edge[1]), 0)) > 0
		var tone := Color(color, (0.70 if both else 0.38 if lit else 0.14) * alpha)
		if bool(edge[2]) and not both:
			ci.draw_dashed_line(a, b, tone, 1.2, 4.0, true, true)
		else:
			ci.draw_line(a, b, tone, 1.6 if both else 1.2, true)
	for id in nodes:
		var at: Vector2 = pos[id]
		var sid := String(id)
		var state := state_of(sid, taken)
		if sid == highlight:
			found = at
			var breath := 1.0 if settled else 0.5 + 0.5 * sin(time * 3.4)
			ci.draw_circle(at, 13.0 + breath * 3.0, Color(Look.STARLIGHT, 0.10 * alpha), true, -1, true)
			ci.draw_arc(at, 11.0 + breath * 2.5, 0, TAU, 32, Color(Look.STARLIGHT, (0.55 + 0.35 * breath) * alpha), 1.4, true)
			ci.draw_colored_polygon(Look.star_points(at, 8.5, 0.46), Color(Look.BG_DEEP, 0.9 * alpha))
			ci.draw_colored_polygon(Look.star_points(at, 7.0, 0.46), Color(Look.STARLIGHT, alpha))
		elif state == 3:
			ci.draw_circle(at, 8.0, Color(color, 0.16 * alpha), true, -1, true)
			ci.draw_colored_polygon(Look.star_points(at, 6.4, 0.46), Color(Look.BG_DEEP, 0.9 * alpha))
			ci.draw_colored_polygon(Look.star_points(at, 5.2, 0.46), Color(color, alpha))
			ci.draw_circle(at, 1.4, Color(Color.WHITE, 0.8 * alpha), true, -1, true)
		elif state == 2:
			var ring := Look.star_points(at, 4.6, 0.46)
			ci.draw_colored_polygon(ring, Color(Look.BG_DEEP, 0.9 * alpha))
			ring.append(ring[0])
			ci.draw_polyline(ring, Color(color, 0.80 * alpha), 1.2, true)
		else:
			ci.draw_circle(at, 2.6, Color(Look.BG_DEEP, 0.9 * alpha), true, -1, true)
			ci.draw_circle(at, 1.8, Color(Look.STEEL_DIM, 0.75 * alpha), true, -1, true)
	return found


## Depth as stars: one, two or three small lit stars in a row (never a number).
static func draw_depth(ci: CanvasItem, c: Vector2, tier: int, color: Color, radius: float = 5.0) -> void:
	var pitch := radius * 2.6
	for n in range(3):
		var at := c + Vector2((float(n) - 1.0) * pitch, 0)
		var points := Look.star_points(at, radius, 0.46)
		if n < tier:
			ci.draw_colored_polygon(points, color)
		else:
			ci.draw_colored_polygon(points, Color(Look.STEEL_DIM, 0.35))
			points.append(points[0])
			ci.draw_polyline(points, Color(Look.STEEL_DIM, 0.8), 1.0, true)


## How many of a constellation's nodes are joined, and how many there are.
static func progress(group: String, taken: Dictionary) -> Vector2i:
	var ids := ids_of(group)
	var joined := 0
	for id in ids:
		if int(taken.get(id, 0)) > 0:
			joined += 1
	return Vector2i(joined, ids.size())


## One cell of the strip: the constellation's name in its colour, joined / total, and
## one point per node, lit when joined. `active` names the constellation of the offer.
static func draw_cell(ci: CanvasItem, rect: Rect2, group: String, taken: Dictionary, active: bool = false) -> void:
	var info: Dictionary = Balance.TALENT_GROUPS.get(group, {})
	var color := Color(String(info.get("color", "#b9cad3")))
	if active:
		Look.fill_round(ci, rect, 4, Color(color, 0.10))
	var count := progress(group, taken)
	var name_size := Look.text_box(ci, Rect2(rect.position + Vector2(8, 2), Vector2(rect.size.x - 54, 20)), I18n.t(String(info.get("ko", group))), 14, color, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(ci, Rect2(rect.end.x - 50, rect.position.y + 2, 44, 20), "%d / %d" % [count.x, count.y], 13, Look.INK_DIM if count.x > 0 else Look.INK_MUTE, HORIZONTAL_ALIGNMENT_RIGHT)
	# The nodes as a row of points, by depth and table order.
	var ids: Array = []
	for node in Balance.TALENTS:
		if String(node["group"]) == group:
			ids.append(String(node["id"]))
	var pitch := minf(9.0, (rect.size.x - 16.0) / maxf(1.0, float(ids.size())))
	var x := rect.position.x + 8.0 + pitch * 0.5
	var y := rect.end.y - 10.0
	for id in ids:
		var at := Vector2(x, y)
		if int(taken.get(id, 0)) > 0:
			ci.draw_colored_polygon(Look.star_points(at, 3.6, 0.46), color)
		else:
			ci.draw_circle(at, 1.5, Color(Look.STEEL_DIM, 0.6), true, -1, true)
		x += pitch
	if name_size < 0:
		return


# =========================================================================== #
# 2026-10-19 — the node seal (F3), the constellation map (F2), the node cards
# =========================================================================== #
## Art. The node glyph is found in this order: art/ui/talents/<id>.png, then the painted
## icon of the passive the node grants (Roster.ART["pi_<passive>"]), then the vector glyph
## named by the node's `icon` column. (Paths are code, not data: no DB row is involved.)
const ATLAS := "res://art/ui/talents/seal_atlas.png"
const ICON_PATH := "res://art/ui/talents/%s.png"
## Cells of the atlas, in the order tools/talent_art.py draws them (keep the two in step).
enum Cell { FACE, GLOSS, RING, RING_GOLD, HEX, HEX_GOLD, STAR, HALO, RAYS, SPARKLE, CROWN, LOCK,
	SHADOW, RING_SOFT, DOT, PIP, EMBLEM, THIN_RING = 24, BRACKETS = 25 }
const CELL_PX := 192.0
const CELL_COLS := 4
## The radius each kind of cell was drawn for, in atlas pixels.
const R_FACE := 52.0
const R_SOFT := 40.0
const R_RING := 64.0
const R_EMBLEM := 74.0
const R_THIN := 80.0
## How far each tier's frame reaches, in face radii: ring, hexagon, eight-point star.
const FRAME_REACH := [1.17, 1.42, 1.86]
## Map chrome (design pixels).
const HEADER_H := 54.0
const TAB_H := 50.0
const FOOT_H := 62.0
const BAND_H := 34.0
## The offer card's parts (relative to the card): the colour field's height, the seal's
## radius (it hangs on the field's lower edge) and the constellation map inside the field.
const CARD_FIELD_H := 168.0
const CARD_SEAL_R := 44.0
const CARD_MAP := Rect2(18, 58, -36, 62)
## The pick flourish (draw_pick_flourish) lasts this long.
const PICK_TIME := 0.45

static var _atlas_tex: Texture2D = null
static var _atlas_size := Vector2.ONE
static var _atlas_tried := false
static var _icons: Dictionary = {}
static var _icon_kind: Dictionary = {}
static var _layouts: Dictionary = {}
static var _state_key := ""
static var _state_cache: Dictionary = {}
static var _pack_key := ""
static var _pack: Dictionary = {}
static var _dust: Array = []
static var _node_cache: Dictionary = {}
static var _group_cache: Dictionary = {}
static var _fit_cache: Dictionary = {}
static var _wrap_cache: Dictionary = {}
static var _seal_cache: Dictionary = {}
static var _beams: Array = []


static func group_color(group: String) -> Color:
	return Color(String(Balance.TALENT_GROUPS.get(group, {}).get("color", "#b9cad3")))


static func group_name(group: String) -> String:
	return I18n.t(String(Balance.TALENT_GROUPS.get(group, {}).get("ko", group)))


## The tier a node's seal shows: the table's tier, except that a tier-3 node with no
## prerequisite (it stands on the root row, e.g. 승급) is not drawn as a capstone — the
## capstone star means the end of a chain. (A data fix for such rows is a DB proposal.)
static func frame_tier(id: String) -> int:
	var node := node_of(id)
	var tier := clampi(int(node.get("tier", 1)), 1, 3)
	if tier == 3 and Talents.clauses(node).is_empty():
		return 2
	return tier


## Whether a node is its constellation's capstone (the gold eight-point star, 「으뜸별」).
static func is_capstone(id: String) -> bool:
	return frame_tier(id) == 3


## A node's table row by id (Balance.talent_by_id walks the table; the map asks often).
static func node_of(id: String) -> Dictionary:
	if _node_cache.is_empty():
		for node in Balance.TALENTS:
			_node_cache[String(node["id"])] = node
	return _node_cache.get(id, {})


## A constellation's node ids in table order.
static func ids_of(group: String) -> Array:
	if _group_cache.is_empty():
		for node in Balance.TALENTS:
			var g := String(node["group"])
			if not _group_cache.has(g):
				_group_cache[g] = []
			(_group_cache[g] as Array).append(String(node["id"]))
	return _group_cache.get(group, [])


## Look.glass_panel's look in five draws instead of fourteen (the map draws many panels every
## frame): the chamfered face, the rim, the top light, the bottom line and the inner top glow.
static func _glass(ci: CanvasItem, rect: Rect2, edge: Color, face: Color, selected: bool = false, alpha: float = 1.0) -> void:
	var p := rect.position
	var e := rect.end
	var cut := 5.0
	var shape := PackedVector2Array([p + Vector2(cut, 0), Vector2(e.x - cut, p.y), Vector2(e.x - cut, p.y + 3), Vector2(e.x, p.y + cut),
		Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y - 3), e - Vector2(cut, 0), Vector2(p.x + cut, e.y),
		Vector2(p.x + cut, e.y - 3), Vector2(p.x, e.y - cut), p + Vector2(0, cut), p + Vector2(cut, 3), p + Vector2(cut, 0)])
	ci.draw_colored_polygon(shape, Color(face, face.a * alpha))
	ci.draw_polyline(shape, Color(edge, (0.95 if selected else 0.70) * alpha), 1.6 if selected else 1.0, false)
	ci.draw_line(p + Vector2(9, 2), Vector2(e.x - 9, p.y + 2), Color(edge.lightened(0.35), 0.62 * alpha), 1, false)
	ci.draw_line(Vector2(p.x + 9, e.y - 2), e - Vector2(9, 2), Color(edge, 0.26 * alpha), 1, false)
	Look.gradient_rect(ci, Rect2(p + Vector2(7, 4), Vector2(rect.size.x - 14, 9)), Color(edge, (0.045 if selected else 0.020) * alpha), Color(edge, 0.0), true)


## Look.text_box with the fitted size remembered (the map redraws the same words every
## frame). During a text audit it is Look.text_box itself, so captures record every box.
static func _box(ci: CanvasItem, box: Rect2, s: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	if Look.text_audit_enabled:
		Look.text_box(ci, box, s, size, col, align)
		return
	var text := I18n.t(s)
	var key := "%s|%d|%d|%d" % [text, size, int(box.size.x), int(box.size.y)]
	var fitted := int(_fit_cache.get(key, -1))
	if fitted < 0:
		fitted = Look.fit_size(text, size, box.size)
		if _fit_cache.size() > 2048:
			_fit_cache.clear()
		_fit_cache[key] = fitted
	match align:
		HORIZONTAL_ALIGNMENT_LEFT:
			Look.text_left(ci, Vector2(box.position.x, box.get_center().y), text, fitted, col)
		HORIZONTAL_ALIGNMENT_RIGHT:
			Look.text_right(ci, Vector2(box.end.x, box.get_center().y), text, fitted, col)
		_:
			Look.text_center(ci, box.get_center(), text, fitted, col)


## Look.wrap_text with the lines remembered (same shrinking rule, same placement).
static func _wrap(ci: CanvasItem, s: String, box: Rect2, size: int, col: Color, left: bool = false) -> void:
	if Look.text_audit_enabled:
		Look.wrap_text(ci, s, box, size, col, left)
		return
	var key := "%s|%d|%d|%d" % [s, size, int(box.size.x), int(box.size.y)]
	var entry: Array = _wrap_cache.get(key, [])
	if entry.is_empty():
		var fitted := size
		var lines := Look.wrapped_lines(s, box.size.x, fitted)
		while fitted > 1 and float(lines.size()) * Look.line_height(fitted) > box.size.y:
			fitted -= 1
			lines = Look.wrapped_lines(s, box.size.x, fitted)
		entry = [fitted, lines]
		if _wrap_cache.size() > 1024:
			_wrap_cache.clear()
		_wrap_cache[key] = entry
	var step := Look.line_height(int(entry[0]))
	var lines: Array = entry[1]
	for i in range(lines.size()):
		var y := box.position.y + step * (float(i) + 0.5)
		if left:
			Look.text_left(ci, Vector2(box.position.x, y), String(lines[i]), int(entry[0]), col)
		else:
			Look.text_center(ci, Vector2(box.get_center().x, y), String(lines[i]), int(entry[0]), col)


## Every node's state at once, for one set of picks: "full" / "joined" / "open" /
## "closed" / "locked" — the same answer as Talents.state, but available() runs once.
## Cached on the picks, so a screen may call it every frame.
static func states(taken: Dictionary, passives: Array = [], levels: Dictionary = {}) -> Dictionary:
	var key := "%s|%s|%s" % [str(taken), str(passives), str(levels)]
	if key == _state_key:
		return _state_cache
	var open := {}
	for id in Talents.available(taken, passives, levels):
		open[id] = true
	var out := {}
	for node in Balance.TALENTS:
		var id := String(node["id"])
		var count := int(taken.get(id, 0))
		if count >= int(node.get("max", 1)):
			out[id] = "full"
		elif not Talents.requirements_met(node, taken):
			out[id] = "joined" if count > 0 else "locked"
		elif open.has(id):
			out[id] = "joined" if count > 0 else "open"
		else:
			out[id] = "closed"
	_state_key = key
	_state_cache = out
	return out


# --------------------------------------------------------------------------- #
# Art access
# --------------------------------------------------------------------------- #
## The atlas, sampled linearly through mipmaps (seals are drawn at many sizes; the
## project's Nearest default stays for everything else).
static func _atlas() -> Texture2D:
	if not _atlas_tried:
		_atlas_tried = true
		var raw := Art.tex(ATLAS)
		if raw != null:
			var filtered := CanvasTexture.new()
			filtered.diffuse_texture = raw
			filtered.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			_atlas_tex = filtered
			_atlas_size = Vector2(raw.get_width(), raw.get_height())
	return _atlas_tex


static func has_art() -> bool:
	return _atlas() != null


static func _src(cell: int) -> Rect2:
	return Rect2(float(cell % CELL_COLS) * CELL_PX, float(cell / CELL_COLS) * CELL_PX, CELL_PX, CELL_PX)


## One atlas cell centred on `c`, scaled so its drawn unit becomes `scale` x its atlas size.
static func _sprite(ci: CanvasItem, cell: int, c: Vector2, scale: float, mod: Color) -> void:
	var tex := _atlas()
	if tex == null or scale <= 0.0 or mod.a <= 0.003:
		return
	var side := CELL_PX * scale
	ci.draw_texture_rect_region(tex, Rect2(c.x - side * 0.5, c.y - side * 0.5, side, side), _src(cell), mod)


## The same, turned by `angle` (drawn as a textured quad; the caller's transform is kept).
static func _sprite_turned(ci: CanvasItem, cell: int, c: Vector2, scale: float, angle: float, mod: Color) -> void:
	var tex := _atlas()
	if tex == null or scale <= 0.0 or mod.a <= 0.003:
		return
	var h := CELL_PX * scale * 0.5
	var src := _src(cell)
	var u0 := src.position / _atlas_size
	var u1 := src.end / _atlas_size
	var cs := cos(angle)
	var sn := sin(angle)
	var pts := PackedVector2Array()
	for k in [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]:
		pts.append(c + Vector2(k.x * cs - k.y * sn, k.x * sn + k.y * cs))
	ci.draw_polygon(pts, PackedColorArray([mod, mod, mod, mod]),
		PackedVector2Array([u0, Vector2(u1.x, u0.y), u1, Vector2(u0.x, u1.y)]), tex)


## The passive a node grants ("" when it grants none).
static func grant_of(id: String) -> String:
	for key in node_of(id):
		if String(key).begins_with("grant_"):
			return String(key).trim_prefix("grant_")
	return ""


## The node's glyph picture, or null for the vector glyph. `_icon_kind[id]` says which:
## "talent" (a neutral glyph the seal tints) or "passive" (a coloured painted icon).
static func icon_texture(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var tex: Texture2D = Art.tex(ICON_PATH % id)
	var kind := "talent"
	if tex == null:
		var passive := grant_of(id)
		if not passive.is_empty():
			tex = Art.tex(String(Roster.ART.get("pi_" + passive, "")))
			kind = "passive"
	if tex != null:
		var filtered := CanvasTexture.new()
		filtered.diffuse_texture = tex
		filtered.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if kind == "talent" else CanvasItem.TEXTURE_FILTER_LINEAR
		tex = filtered
	else:
		kind = ""
	_icons[id] = tex
	_icon_kind[id] = kind
	return tex


## The glyph of a node on a face of radius `r`. `ink` tints a neutral glyph (ivory on a lit
## face, the constellation colour on an open one, grey when locked); a painted icon keeps
## its own colours and only takes the ink's brightness and alpha.
static func draw_icon(ci: CanvasItem, c: Vector2, r: float, id: String, ink: Color) -> void:
	var tex := icon_texture(id)
	var kind := String(_icon_kind.get(id, ""))
	if tex != null:
		var side := r * (1.72 if kind == "talent" else 1.30)
		var mod := ink
		if kind == "passive":
			var v := clampf(maxf(ink.r, maxf(ink.g, ink.b)) * 1.15, 0.0, 1.0)
			mod = Color(v, v, v, ink.a)
		ci.draw_texture_rect(tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false, mod)
		return
	var glyph := {"icon": String(node_of(id).get("icon", ""))}
	Look.draw_passive_icon(ci, c + Vector2(0, r * 0.06), r * 0.54, glyph, Color(0, 0, 0, 0.50 * ink.a))
	Look.draw_passive_icon(ci, c, r * 0.54, glyph, ink)


## A soft round point of light of radius `r` (a sky's star, a mote).
static func draw_dot(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	if _atlas() == null:
		ci.draw_circle(c, r * 0.45, color)
		return
	_sprite(ci, Cell.DOT, c, r / R_SOFT, color)


## A constellation's emblem (sword, gust, reticle, prism, crossed arms, shield, meteor,
## star coin) of radius `r`, tinted `mod`.
static func draw_emblem(ci: CanvasItem, group: String, c: Vector2, r: float, mod: Color) -> void:
	var index := Balance.TALENT_GROUP_ORDER.find(group)
	if index < 0:
		return
	if _atlas() == null:
		ci.draw_colored_polygon(Look.star_points(c, r * 0.9, 0.46), mod)
		return
	_sprite(ci, Cell.EMBLEM + index, c, r / R_EMBLEM, mod)


# --------------------------------------------------------------------------- #
# The seal: one node, everywhere it appears
# --------------------------------------------------------------------------- #
## One node drawn as a seal of face radius `r`.
##   frame by tier — 1 a silver ring · 2 a faceted hexagon · 3 (the capstone) a gold
##   eight-point star with turning rays
##   state — joined: the face lit in the constellation's colour with a halo · full: gold
##   frame and a crown · open: a dark face with the glyph in colour and a breathing glow ·
##   locked / closed: dark, grey, a small lock (closed: a warning-coloured lock)
##   pips — a repeatable node carries one socket per pick on the bottom of its bezel
## `opts`: offered (a starlight ring with two sparkles), selected (four turning brackets),
## settled (no motion), alpha, pop (0..1 entrance: grows and overshoots), flash (0..1 a
## white flare over the face).
static func draw_seal(ci: CanvasItem, c: Vector2, r: float, id: String, state: String, count: int,
		t: float, opts: Dictionary = {}) -> void:
	if r < 2.0:
		return
	var info: Array = _seal_cache.get(id, [])
	if info.is_empty():
		var node := node_of(id)
		if node.is_empty():
			return
		info = [group_color(String(node.get("group", ""))), frame_tier(id),
			maxi(1, int(node.get("max", 1))), float(absi(id.hash()) % 628) * 0.01]
		_seal_cache[id] = info
	var color: Color = info[0]
	var tier: int = info[1]
	var maximum: int = info[2]
	var phase: float = info[3]
	var a := float(opts.get("alpha", 1.0))
	var settled := bool(opts.get("settled", false))
	var offered := bool(opts.get("offered", false))
	var selected := bool(opts.get("selected", false))
	if opts.has("pop"):
		var p := clampf(float(opts["pop"]), 0.0, 1.0)
		r *= _back_out(p)
		a *= clampf(p * 2.5, 0.0, 1.0)
		if r < 1.0:
			return
	var detail := r >= 19.0
	var lit := state == "joined" or state == "full"
	var full := state == "full"
	var dark := state == "locked" or state == "closed"
	var breath := 0.6 if settled else 0.5 + 0.5 * sin(t * 2.6 + phase)
	var reach: float = FRAME_REACH[tier - 1]
	if _atlas() == null:
		_seal_plain(ci, c, r, id, state, color, tier, offered, selected, breath, a)
		return
	if detail:
		_sprite(ci, Cell.SHADOW, c + Vector2(0, r * 0.16), r / R_FACE, Color(1, 1, 1, 0.55 * a))
	if offered:
		_sprite(ci, Cell.HALO, c, r * 1.10 / R_SOFT, Color(Look.STARLIGHT, (0.26 + 0.20 * breath) * a))
	if lit:
		_sprite(ci, Cell.HALO, c, r * 0.95 / R_SOFT, Color(Look.GOLD if full else color, (0.55 if full else 0.46) * a))
	elif state == "open":
		_sprite(ci, Cell.HALO, c, r * 0.88 / R_SOFT, Color(color, (0.08 + 0.24 * breath) * a))
	if tier == 3 and not dark:
		var spin := phase if settled else t * 0.30 + phase
		_sprite_turned(ci, Cell.RAYS, c, r * 1.02 / R_SOFT, spin, Color(Look.STARLIGHT if lit or offered else color, (0.62 if lit else 0.34) * a))
	var frame: int = [Cell.RING, Cell.HEX, Cell.STAR][tier - 1]
	if full and tier < 3:
		frame = [Cell.RING_GOLD, Cell.HEX_GOLD][tier - 1]
	var frame_mod := Color(1, 1, 1, a)
	if dark:
		frame_mod = Color(0.36, 0.41, 0.46, a)
	elif state == "open":
		frame_mod = Color(0.90, 0.94, 0.97, a)
	_sprite(ci, frame, c, r / R_FACE, frame_mod)
	var face := color
	if state == "open":
		face = Look.BG_DEEP.lerp(color, 0.30)
	elif dark:
		face = Color(0.085, 0.115, 0.145)
	_sprite(ci, Cell.FACE, c, r / R_FACE, Color(face, a))
	if state == "open":
		_sprite(ci, Cell.THIN_RING, c, r * 0.93 / R_THIN, Color(color.lightened(0.25), (0.70 + 0.30 * breath) * a))
	_sprite(ci, Cell.GLOSS, c, r / R_FACE, Color(1, 1, 1, (0.80 if lit else 0.42 if state == "open" else 0.20) * a))
	var ink := Color(1, 1, 1, a)
	if state == "open":
		ink = Color(color.lightened(0.38), a)
	elif dark:
		ink = Color(0.50, 0.56, 0.62, 0.78 * a)
	draw_icon(ci, c, r, id, ink)
	if tier == 3 and detail and not dark:
		# A capstone keeps three motes of starlight circling it, each twinkling on its own beat.
		var clock := 0.0 if settled else t
		for k in range(3):
			var ang := phase * 2.0 + float(k) * TAU / 3.0 + clock * 0.8
			var rad := r * (1.52 + 0.12 * sin(clock * 1.7 + float(k)))
			var twinkle := 0.55 + 0.45 * sin(clock * 3.1 + float(k) * 2.1)
			_sprite(ci, Cell.SPARKLE, c + Vector2(cos(ang), sin(ang) * 0.86) * rad, r * 0.11 / R_SOFT,
				Color(Look.STARLIGHT, twinkle * a * (1.0 if lit or offered else 0.55)))
	if opts.has("flash"):
		var f := clampf(float(opts["flash"]), 0.0, 1.0)
		_sprite(ci, Cell.HALO, c, r * 0.80 / R_SOFT, Color(1, 1, 1, f * 0.9 * a))
	if maximum > 1:
		_pips(ci, c, r, maximum, count, full, color, a)
	if full:
		_sprite(ci, Cell.CROWN, c + Vector2(0, -r * 1.12), r * 0.64 / R_FACE, Color(1, 1, 1, a))
	elif dark and detail:
		_sprite(ci, Cell.LOCK, c + Vector2(r * 0.70, r * 0.64), r * 0.42 / R_FACE, Color(1, 1, 1, 0.95 * a) if state == "locked" else Color(Look.WARN, a))
	if offered:
		var ring := r * (reach + 0.22)
		_sprite(ci, Cell.RING_SOFT, c, ring / R_RING, Color(Look.STARLIGHT, (0.50 + 0.35 * breath) * a))
		_sprite(ci, Cell.THIN_RING, c, ring / R_THIN, Color(Look.STARLIGHT, 0.95 * a))
		if detail:
			for k in range(2):
				var ang := phase + float(k) * PI + (0.0 if settled else t * 1.1)
				_sprite(ci, Cell.SPARKLE, c + Vector2(cos(ang), sin(ang)) * ring, r * 0.15 / R_SOFT, Color(1, 1, 1, 0.95 * a))
	if selected:
		var sel := r * (reach + (0.46 if offered else 0.26))
		_sprite_turned(ci, Cell.BRACKETS, c, sel / R_THIN, 0.0 if settled else t * 0.5, Color(Look.IVORY, 0.95 * a))


## The picks of a repeatable node: sockets along the bottom of the bezel, lit per pick
## (a star in the constellation's colour, gold when full; an empty socket is a dark pit).
static func _pips(ci: CanvasItem, c: Vector2, r: float, maximum: int, count: int, full: bool, color: Color, a: float) -> void:
	var step := clampf(0.36 * 4.0 / float(maxi(4, maximum)), 0.22, 0.36)
	var radius := r * 1.085
	var size := maxf(1.7, r * 0.12)
	var fill := Look.GOLD if full else color.lightened(0.5)
	for n in range(maximum):
		var ang := PI * 0.5 + (float(n) - float(maximum - 1) * 0.5) * step
		var at := c + Vector2(cos(ang), sin(ang)) * radius
		if n < count:
			_sprite(ci, Cell.PIP, at, size * 1.55 / R_SOFT, Color(fill, a))
		else:
			_sprite(ci, Cell.FACE, at, size / R_FACE, Color(0.05, 0.08, 0.10, 0.95 * a))


## Without the atlas: the same states in plain shapes.
static func _seal_plain(ci: CanvasItem, c: Vector2, r: float, id: String, state: String, color: Color, tier: int,
		offered: bool, selected: bool, breath: float, a: float) -> void:
	var lit := state == "joined" or state == "full"
	var dark := state == "locked" or state == "closed"
	if offered:
		ci.draw_arc(c, r * 1.45, 0, TAU, 32, Color(Look.STARLIGHT, (0.6 + 0.3 * breath) * a), 2.0, true)
	if tier == 3:
		ci.draw_colored_polygon(Look.star_points(c, r * 1.6, 0.55), Color(Look.GOLD if not dark else Look.STEEL_DIM, a))
	elif tier == 2:
		var hexagon := PackedVector2Array()
		for k in range(6):
			hexagon.append(c + Vector2.from_angle(-PI * 0.5 + TAU * k / 6.0) * r * 1.35)
		ci.draw_colored_polygon(hexagon, Color(Look.STEEL if not dark else Look.STEEL_DIM, a))
	ci.draw_circle(c, r * 1.12, Color(Look.GOLD if state == "full" else (Look.STEEL if not dark else Look.STEEL_DIM), a), true, -1, true)
	ci.draw_circle(c, r, Color(color if lit else Look.BG_DEEP.lerp(color, 0.3 if state == "open" else 0.05), a), true, -1, true)
	draw_icon(ci, c, r, id, Color(1, 1, 1, a) if lit else (Color(color.lightened(0.35), a) if not dark else Color(Look.STEEL_DIM, 0.8 * a)))
	if selected:
		ci.draw_arc(c, r * 1.7, 0, TAU, 32, Color(Look.IVORY, a), 2.0, true)


static func _back_out(x: float) -> float:
	var s := 1.70158
	var p := x - 1.0
	return 1.0 + (s + 1.0) * p * p * p + s * p * p


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


# --------------------------------------------------------------------------- #
# Layout by graph depth
# --------------------------------------------------------------------------- #
## One constellation laid out as a tree: roots on the bottom row, each row one graph depth
## (Talents.graph_depth), so no line ever joins two stars of the same row. Positions are
## in slots: {"nodes": {id: Vector2(x, depth)}, "edges": [[from, to, any_of]],
## "width": slots wide, "rows": number of rows}. Rows are ordered by a few barycentre
## sweeps (fewer crossings) and children sit over the mean of their parents.
static func map(group: String) -> Dictionary:
	if _layouts.has(group):
		return _layouts[group]
	var ids: Array[String] = []
	for node in Balance.TALENTS:
		if String(node["group"]) == group:
			ids.append(String(node["id"]))
	var rows := {}
	var deepest := 0
	for id in ids:
		var depth := Talents.graph_depth(id)
		deepest = maxi(deepest, depth)
		if not rows.has(depth):
			rows[depth] = []
		(rows[depth] as Array).append(id)
	for depth in range(deepest + 1):
		if not rows.has(depth):
			rows[depth] = []
	var parents := {}
	var kids := {}
	var edges: Array = []
	for id in ids:
		parents[id] = []
		kids[id] = []
	for id in ids:
		for options in Talents.clauses(node_of(id)):
			for option in options:
				if ids.has(String(option)):
					(parents[id] as Array).append(String(option))
					(kids[String(option)] as Array).append(id)
					edges.append([String(option), id, (options as Array).size() > 1])
	var order := {}
	for depth in rows:
		_index_row(rows[depth], order)
	for sweep in range(4):
		for depth in range(1, deepest + 1):
			_sort_row(rows[depth], parents, order)
		for depth in range(deepest - 1, -1, -1):
			_sort_row(rows[depth], kids, order)
	# Coordinates: roots side by side, then every row over the mean x of its parents,
	# pushed apart to one slot and re-centred on where it wanted to be.
	var x := {}
	var root_row: Array = rows[0]
	for i in range(root_row.size()):
		x[root_row[i]] = float(i) - float(root_row.size() - 1) * 0.5
	for depth in range(1, deepest + 1):
		var row: Array = rows[depth]
		var want: Array = []
		for id in row:
			var total := 0.0
			for parent in parents[id]:
				total += float(x[parent])
			want.append(total / maxf(1.0, float((parents[id] as Array).size())))
		var placed: Array = want.duplicate()
		for i in range(1, placed.size()):
			placed[i] = maxf(float(placed[i]), float(placed[i - 1]) + 1.0)
		var shift := 0.0
		for i in range(placed.size()):
			shift += float(want[i]) - float(placed[i])
		shift /= maxf(1.0, float(placed.size()))
		for i in range(row.size()):
			x[row[i]] = float(placed[i]) + shift
	var low := INF
	var high := -INF
	for id in ids:
		low = minf(low, float(x[id]))
		high = maxf(high, float(x[id]))
	var nodes := {}
	for id in ids:
		nodes[id] = Vector2(float(x[id]) - low, float(Talents.graph_depth(id)))
	var out := {"nodes": nodes, "edges": edges, "width": (high - low) + 1.0 if not ids.is_empty() else 1.0, "rows": deepest + 1}
	_layouts[group] = out
	return out


static func _index_row(row: Array, order: Dictionary) -> void:
	for i in range(row.size()):
		order[row[i]] = float(i) - float(row.size() - 1) * 0.5


static func _sort_row(row: Array, links: Dictionary, order: Dictionary) -> void:
	var keyed: Array = []
	for i in range(row.size()):
		var id := String(row[i])
		var near: Array = links.get(id, [])
		var key := float(order[id])
		if not near.is_empty():
			var total := 0.0
			for other in near:
				total += float(order[other])
			key = total / float(near.size())
		keyed.append([key, float(order[id]), id])
	keyed.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0] or (p[0] == q[0] and p[1] < q[1]))
	for i in range(keyed.size()):
		row[i] = keyed[i][2]
	_index_row(row, order)


## Pixel positions of a constellation's nodes in `area`: `px` / `py` the slot and row
## pitch, roots on the bottom of the area, the tree centred across it.
static func _place(group: String, area: Rect2, px: float, py: float) -> Dictionary:
	var layout := map(group)
	var nodes: Dictionary = layout["nodes"]
	var width := float(layout["width"])
	var out := {}
	for id in nodes:
		var slot: Vector2 = nodes[id]
		out[id] = Vector2(area.get_center().x + (slot.x - (width - 1.0) * 0.5) * px, area.end.y - (slot.y + 0.5) * py)
	return out


# --------------------------------------------------------------------------- #
# The constellation map (F2)
# --------------------------------------------------------------------------- #
## The whole map inside `rect`, for any screen that hosts it (the arena's level-up popup
## and viewer, a menu page, a codex). Registers its touch zones in `ui`:
##   talent:group:<g>  a constellation — an overview cluster or a tab ("talent:group:" = the overview)
##   talent:node:<id>  one node (on the overview it also means "show its constellation")
## `focus` "" draws the overview (all eight constellations, every node with its state);
## a constellation id draws that one large with names, tabs to switch, and the detail
## card of `selected` (or of the most interesting node of it when `selected` is elsewhere).
## `states` comes from states(); `offer` are the ids on offer (starlight rings).
## `opts`: settled, level (0 hides the chip). The host draws its own back / close button
## in chart_button_rect(rect).
static func draw_chart(ci: CanvasItem, ui: Ui, rect: Rect2, taken: Dictionary, node_states: Dictionary,
		offer: Array, focus: String, selected: String, t: float, opts: Dictionary = {}) -> void:
	var settled := bool(opts.get("settled", false))
	_chart_header(ci, Rect2(rect.position, Vector2(rect.size.x, HEADER_H)), taken, offer, int(opts.get("level", 0)), node_states, t, settled)
	var top := rect.position.y + HEADER_H + 4.0
	var bottom := rect.end.y - FOOT_H
	var hint_box := Rect2(rect.position.x + 8.0, rect.end.y - FOOT_H + 12.0, chart_button_rect(rect).position.x - rect.position.x - 24.0, FOOT_H - 18.0)
	if focus.is_empty() or not Balance.TALENT_GROUPS.has(focus):
		_overview(ci, ui, Rect2(rect.position.x, top, rect.size.x, bottom - top), taken, node_states, offer, selected, t, settled)
		_box(ci, hint_box, I18n.t("arena.map_hint"), Look.TYPE_CAPTION, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		return
	_tabs(ci, ui, Rect2(rect.position.x, top, rect.size.x, TAB_H), focus, taken, offer)
	var body_top := top + TAB_H + 8.0
	var detail_w := clampf(rect.size.x * 0.34, 360.0, 430.0)
	var panel := Rect2(rect.position.x, body_top, rect.size.x - detail_w - 12.0, bottom - body_top)
	var card := Rect2(panel.end.x + 12.0, body_top, detail_w, panel.size.y)
	var shown := selected
	if node_of(shown).is_empty() or String(node_of(shown).get("group", "")) != focus:
		shown = default_node(focus, node_states, offer)
	_focus(ci, ui, panel, focus, taken, node_states, offer, shown, t, settled)
	draw_detail(ci, card, shown, taken, node_states, offer, t, settled, ui)
	_box(ci, hint_box, I18n.t("arena.map_pick_hint"), Look.TYPE_CAPTION, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)


## Where the host's own button (back to the offer / back to battle) goes under the map.
static func chart_button_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.get_center().x - 220.0, rect.end.y - FOOT_H + 8.0, 440.0, 50.0)


## The node a constellation shows first: one on offer, else one that can be picked, else
## a joined one, else its first root.
static func default_node(group: String, node_states: Dictionary, offer: Array) -> String:
	var ids := ids_of(group)
	for id in ids:
		if offer.has(id):
			return id
	for wanted in ["open", "joined", "full"]:
		for id in ids:
			if String(node_states.get(id, "")) == wanted:
				return id
	return String(ids[0]) if not ids.is_empty() else ""


static func _chart_header(ci: CanvasItem, rect: Rect2, taken: Dictionary, offer: Array, level: int,
		_node_states: Dictionary, t: float, settled: bool) -> void:
	var title := I18n.t("arena.map_title")
	var y := rect.get_center().y
	var x := rect.position.x + 8.0
	draw_emblem_row_star(ci, Vector2(x + 14.0, y), 13.0, t, settled)
	x += 36.0
	Look.text_left(ci, Vector2(x, y), title, Look.TYPE_TITLE, Look.GOLD)
	x += Look.text_width(title, Look.TYPE_TITLE) + 14.0
	if level > 0:
		var chip := Look.chip(ci, Vector2(x, y), I18n.t("arena.level_n") % level, 17, Look.STARLIGHT, Look.BG_DEEP)
		x = chip.end.x + 12.0
	var joined := 0
	var total := 0
	for node in Balance.TALENTS:
		total += 1
		if int(taken.get(String(node["id"]), 0)) > 0:
			joined += 1
	Look.text_left(ci, Vector2(x, y + 1), I18n.t("arena.map_joined_total") % [joined, total], 18, Look.INK_DIM)
	_legend(ci, Rect2(rect.end.x - 600.0, rect.position.y + 6.0, 592.0, rect.size.y - 12.0), not offer.is_empty(), t, settled)


## A small starlight star with a soft glow: the map's title mark.
static func draw_emblem_row_star(ci: CanvasItem, c: Vector2, r: float, t: float, settled: bool) -> void:
	var glow := 0.5 if settled else 0.5 + 0.5 * sin(t * 2.0)
	_sprite(ci, Cell.HALO, c, r * 1.0 / R_SOFT, Color(Look.STARLIGHT, 0.25 + 0.15 * glow))
	ci.draw_colored_polygon(Look.star_points(c, r + 2.5, 0.46), Color(Look.BG_DEEP, 0.9))
	ci.draw_colored_polygon(Look.star_points(c, r, 0.46), Look.STARLIGHT)


## The legend: what the four states and the offer ring look like, right-aligned in `rect`.
static func _legend(ci: CanvasItem, rect: Rect2, with_offer: bool, t: float, _settled: bool) -> void:
	var items := [["joined", "arena.map_joined", false], ["full", "arena.map_full", false],
		["open", "arena.map_open", false], ["locked", "arena.map_locked", false]]
	if with_offer:
		items.append(["open", "arena.map_offered", true])
	var size := 15
	var r := 9.0
	var widths: Array = []
	var total := 0.0
	for item in items:
		var w := 2.0 * r * 1.5 + 6.0 + Look.text_width(I18n.t(String(item[1])), size)
		widths.append(w)
		total += w + 14.0
	var x := rect.end.x - total + 14.0
	var y := rect.get_center().y
	# Samples are round (tier 1) stars of different constellations, so only the state differs.
	var sample := {"joined": "fury_edge", "full": "tempo_repeat", "open": "prec_scope", "locked": "st_frost"}
	for n in range(items.size()):
		var item: Array = items[n]
		var state := String(item[0])
		var id := "prec_edge" if bool(item[2]) else String(sample.get(state, "prec_scope"))
		if node_of(id).is_empty():
			id = String(Balance.TALENTS[n % Balance.TALENTS.size()]["id"])
		draw_seal(ci, Vector2(x + r * 1.5, y), r, id, state, 1, t, {"settled": true, "offered": bool(item[2])})
		Look.text_left(ci, Vector2(x + r * 3.0 + 6.0, y), I18n.t(String(item[1])), size, Look.INK_DIM)
		x += float(widths[n]) + 14.0


## The overview: every constellation as a cluster, packed in two rows by width.
static func _overview(ci: CanvasItem, ui: Ui, body: Rect2, taken: Dictionary, node_states: Dictionary,
		offer: Array, selected: String, t: float, settled: bool) -> void:
	var pack := _overview_pack(body)
	var rows: Array = pack["rows"]
	var px := float(pack["px"])
	var py := float(pack["py"])
	var y := body.position.y
	for row in rows:
		var row_rows := 1
		var row_width := 0.0
		for group in row:
			row_rows = maxi(row_rows, int(map(String(group))["rows"]))
			row_width += _cluster_width(String(group), px)
		var gap := 10.0
		row_width += gap * float((row as Array).size() - 1)
		var height := BAND_H + 14.0 + float(row_rows) * py
		# Spread the spare width over the clusters so the row fills the body.
		var spare := (body.size.x - row_width) / float((row as Array).size())
		var x := body.position.x
		for group in row:
			var w := _cluster_width(String(group), px) + spare
			_cluster(ci, ui, Rect2(x, y, w, height), String(group), px, py, taken, node_states, offer, selected, t, settled)
			x += w + gap
		y += height + 10.0


static func _cluster_width(group: String, px: float) -> float:
	return (float(map(group)["width"]) + 0.9) * px


## Which constellations share a row, and the pitch that makes them fit: the split of
## TALENT_GROUP_ORDER into two rows (each row keeps the table order) that gives the
## largest stars, rows on the vertical limited to 1.4 x the slot pitch.
static func _overview_pack(body: Rect2) -> Dictionary:
	var key := "%s" % body
	if key == _pack_key:
		return _pack
	var groups: Array = Balance.TALENT_GROUP_ORDER
	var best := {}
	var best_score := -1.0
	for mask in range(1, (1 << groups.size()) - 1):
		var row_a: Array = []
		var row_b: Array = []
		for i in range(groups.size()):
			if mask & (1 << i):
				row_a.append(groups[i])
			else:
				row_b.append(groups[i])
		if not row_a.has(groups[0]):
			continue
		var px := INF
		var height_rows := 0
		for row in [row_a, row_b]:
			var units := 0.0
			var deepest := 1
			for group in row:
				units += float(map(String(group))["width"]) + 0.9
				deepest = maxi(deepest, int(map(String(group))["rows"]))
			px = minf(px, (body.size.x - 10.0 * float(row.size() - 1)) / units)
			height_rows += deepest
		var py := minf((body.size.y - 2.0 * (BAND_H + 14.0) - 10.0) / float(height_rows), px * 1.4)
		# The stars' size follows the tighter pitch, but reading the clusters row by row
		# should keep the table's order: every constellation read out of turn costs a little.
		var reading: Array = row_a + row_b
		var turns := 0
		for i in range(reading.size()):
			for j in range(i + 1, reading.size()):
				if groups.find(reading[i]) > groups.find(reading[j]):
					turns += 1
		var score := minf(px, py / 1.15) - float(turns) * 2.5 - float(mask) * 1e-6
		if score > best_score:
			best_score = score
			best = {"rows": [row_a, row_b], "px": px, "py": py}
	_pack_key = key
	_pack = best
	return best


## One overview cluster: its band (emblem, name, joined / total, an offer mark), its links
## and its seals. The whole cluster is a touch zone; every seal is one on top of it.
static func _cluster(ci: CanvasItem, ui: Ui, rect: Rect2, group: String, px: float, py: float, taken: Dictionary,
		node_states: Dictionary, offer: Array, selected: String, t: float, settled: bool) -> void:
	var color := group_color(group)
	var count := progress(group, taken)
	var lit := count.x > 0
	var offered := false
	for id in offer:
		if String(node_of(String(id)).get("group", "")) == group:
			offered = true
	_glass(ci, rect, color.lerp(Look.STEEL, 0.15 if lit or offered else 0.55), Look.GLASS_FACE, lit or offered)
	Look.gradient_rect(ci, Rect2(rect.position + Vector2(4, 3), Vector2(rect.size.x - 8, BAND_H)), Color(color, 0.42 if lit else 0.22), Color(color, 0.0), false)
	ci.draw_rect(Rect2(rect.position.x + 4, rect.position.y + 3, rect.size.x - 8, 2), Color(color, 0.9 if lit else 0.5))
	draw_emblem(ci, group, rect.position + Vector2(20, 3 + BAND_H * 0.5), 12.5, Color(color.lightened(0.15), 1.0))
	var count_w := Look.text_width("%d / %d" % [count.x, count.y], 15) + 8.0
	_box(ci, Rect2(rect.position.x + 36, rect.position.y + 4, rect.size.x - 44 - count_w - (16.0 if offered else 0.0), BAND_H - 2), group_name(group), 18, color.lightened(0.2) if lit else color, HORIZONTAL_ALIGNMENT_LEFT)
	_box(ci, Rect2(rect.end.x - count_w - 8, rect.position.y + 4, count_w, BAND_H - 2), "%d / %d" % [count.x, count.y], 15, Look.INK if lit else Look.INK_MUTE, HORIZONTAL_ALIGNMENT_RIGHT)
	if offered:
		var star := Vector2(rect.end.x - count_w - 18, rect.position.y + 3 + BAND_H * 0.5)
		ci.draw_colored_polygon(Look.star_points(star, 7.5, 0.46), Look.STARLIGHT)
	ui.zone(rect, "talent:group:" + group)
	draw_emblem(ci, group, Vector2(rect.end.x - minf(rect.size.x, rect.size.y) * 0.30, rect.position.y + rect.size.y * 0.56), minf(rect.size.x, rect.size.y) * 0.30, Color(color, 0.06))
	var area := Rect2(rect.position.x, rect.position.y + BAND_H + 10, rect.size.x, rect.size.y - BAND_H - 14)
	# A tree shorter than its row sits in the middle of its panel, not on the floor.
	var spare_rows := area.size.y / py - float(map(group)["rows"])
	if spare_rows > 0.25:
		area.size.y -= spare_rows * py * 0.5
	var pos := _place(group, area, px, py)
	var r := minf(px * 0.34, py * 0.27)
	_links(ci, group, pos, taken, t, settled, r / 17.0, false)
	for id in pos:
		var sid := String(id)
		var at: Vector2 = pos[id]
		draw_seal(ci, at, r, sid, String(node_states.get(sid, "locked")), int(taken.get(sid, 0)), t,
			{"settled": settled, "offered": offer.has(sid), "selected": sid == selected})
		ui.zone(Rect2(at - Vector2(px, py) * 0.5, Vector2(px, py)), "talent:node:" + sid)


## The links of one constellation: solid for a single prerequisite, dashed for "any one
## of"; bright with a glow when both ends are joined, half-lit from a joined parent, faint
## otherwise. `flow` sends a mote of light along every lit link.
static func _links(ci: CanvasItem, group: String, pos: Dictionary, taken: Dictionary, t: float, settled: bool,
		scale: float, flow: bool) -> void:
	var color := group_color(group)
	var layout := map(group)
	for edge in layout["edges"]:
		var a: Vector2 = pos[edge[0]]
		var b: Vector2 = pos[edge[1]]
		var from_lit := int(taken.get(String(edge[0]), 0)) > 0
		var both := from_lit and int(taken.get(String(edge[1]), 0)) > 0
		var dashed := bool(edge[2])
		if both:
			_line(ci, a, b, Color(color, 0.22), 6.0 * scale, dashed)
			_line(ci, a, b, Color(color.lightened(0.35), 0.95), 2.2 * scale, dashed)
			if flow and not settled:
				var k := fposmod(t * 0.45 + float(String(edge[1]).hash() % 97) * 0.01, 1.0)
				_sprite(ci, Cell.DOT, a.lerp(b, k), 7.0 * scale / R_SOFT, Color(color.lightened(0.6), 0.9))
		elif from_lit:
			_line(ci, a, b, Color(color, 0.55), 1.8 * scale, dashed)
		else:
			_line(ci, a, b, Color(Look.STEEL_DIM, 0.40), 1.3 * scale, dashed)


static func _line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float, dashed: bool) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.5 or color.a <= 0.003:
		return
	var beams := _beam_textures()
	# The beam's texture is soft across its height with a solid core of half of it, so the
	# quad is twice the line's width; a dashed beam repeats one dash per period along it.
	var n := Vector2(-d.y, d.x) / length * maxf(1.0, width)
	var u := length / maxf(8.0, width * 5.2) if dashed else 1.0
	ci.draw_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), PackedColorArray([color, color, color, color]),
		PackedVector2Array([Vector2(0, 0), Vector2(u, 0), Vector2(u, 1), Vector2(0, 1)]), beams[1] if dashed else beams[0])


## Two small textures made once: a solid beam and a dashed one (repeating), soft across.
static func _beam_textures() -> Array:
	if not _beams.is_empty():
		return _beams
	for kind in range(2):
		var dashed: bool = kind == 1
		var w: int = 32 if dashed else 4
		var image := Image.create(w, 16, false, Image.FORMAT_RGBA8)
		for y in range(16):
			var v := (float(y) + 0.5) / 16.0
			var edge := clampf(1.0 - absf(v - 0.5) * 2.0, 0.0, 1.0)
			var alpha := clampf(edge * 2.2, 0.0, 1.0)
			for x in range(w):
				var on: bool = not dashed or x < 17
				image.set_pixel(x, y, Color(1, 1, 1, alpha if on else 0.0))
		var tex := CanvasTexture.new()
		tex.diffuse_texture = ImageTexture.create_from_image(image)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tex.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_beams.append(tex)
	return _beams


## The tabs over a focused constellation: "all" (back to the overview) and the eight.
static func _tabs(ci: CanvasItem, ui: Ui, rect: Rect2, focus: String, taken: Dictionary, offer: Array) -> void:
	var groups: Array = Balance.TALENT_GROUP_ORDER
	var gap := 6.0
	var all_w := 104.0
	var w := (rect.size.x - all_w - gap * float(groups.size())) / float(groups.size())
	var all_rect := Rect2(rect.position, Vector2(all_w, rect.size.y))
	_glass(ci, all_rect, Look.STEEL, Color(0.03, 0.08, 0.12, 0.80))
	for k in range(4):
		var at := all_rect.position + Vector2(24 + (k % 2) * 11, rect.size.y * 0.5 - 5.5 + (k / 2) * 11)
		Look.draw_diamond(ci, at, 4.2, Look.INK_DIM)
	_box(ci, Rect2(all_rect.position + Vector2(44, 4), Vector2(all_w - 50, rect.size.y - 8)), I18n.t("arena.map_all"), 18, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	ui.zone(all_rect, "talent:group:")
	for n in range(groups.size()):
		var group := String(groups[n])
		var color := group_color(group)
		var cell := Rect2(rect.position.x + all_w + gap + float(n) * (w + gap), rect.position.y, w, rect.size.y)
		var on := group == focus
		var count := progress(group, taken)
		_glass(ci, cell, color if on else color.lerp(Look.STEEL, 0.55), Color(color.darkened(0.55), 0.85) if on else Color(0.03, 0.08, 0.12, 0.80), on)
		if on:
			ci.draw_rect(Rect2(cell.position.x + 4, cell.end.y - 4, cell.size.x - 8, 3), color)
		draw_emblem(ci, group, cell.position + Vector2(19, cell.size.y * 0.5), 13.0, color.lightened(0.2) if on or count.x > 0 else Color(color, 0.75))
		var count_text := "%d/%d" % [count.x, count.y]
		var count_w := Look.text_width(count_text, 13) + 4.0
		_box(ci, Rect2(cell.position.x + 36, cell.position.y + 4, cell.size.x - 42 - count_w, cell.size.y - 8), group_name(group), 17, Look.INK if on else color.lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT)
		_box(ci, Rect2(cell.end.x - count_w - 6, cell.position.y + 4, count_w, cell.size.y - 8), count_text, 13, Look.INK_DIM if count.x > 0 else Look.INK_MUTE, HORIZONTAL_ALIGNMENT_RIGHT)
		for id in offer:
			if String(node_of(String(id)).get("group", "")) == group:
				ci.draw_colored_polygon(Look.star_points(cell.position + Vector2(cell.size.x - 9, 9), 6.0, 0.46), Look.STARLIGHT)
				break
		ui.zone(cell, "talent:group:" + group)


## One constellation large: a night panel with its glow and emblem, its band, the links
## with motes of light, every seal with its name.
static func _focus(ci: CanvasItem, ui: Ui, panel: Rect2, group: String, taken: Dictionary, node_states: Dictionary,
		offer: Array, selected: String, t: float, settled: bool) -> void:
	var color := group_color(group)
	var info: Dictionary = Balance.TALENT_GROUPS.get(group, {})
	var count := progress(group, taken)
	Look.sheet(ci, panel, color.lerp(Look.STEEL, 0.15), Color(0.02, 0.05, 0.08, 0.95))
	# The sky of this constellation: a wide glow in its colour, faint dust, the emblem.
	_sprite(ci, Cell.HALO, panel.get_center() + Vector2(0, 20), panel.size.y * 0.42 / R_SOFT, Color(color, 0.16))
	_draw_dust(ci, panel, color)
	draw_emblem(ci, group, Vector2(panel.end.x - panel.size.y * 0.30, panel.get_center().y + 24), panel.size.y * 0.36, Color(color, 0.07))
	var band := Rect2(panel.position + Vector2(5, 4), Vector2(panel.size.x - 10, 56))
	Look.gradient_rect(ci, band, Color(color, 0.40), Color(color, 0.0), false)
	ci.draw_rect(Rect2(band.position.x, band.position.y, band.size.x, 2), color)
	draw_emblem(ci, group, band.position + Vector2(30, 28), 21.0, color.lightened(0.2))
	var name := group_name(group)
	Look.text_left(ci, Vector2(band.position.x + 60, band.position.y + 20), name, 28, color.lightened(0.25))
	Look.text_left(ci, Vector2(band.position.x + 60 + Look.text_width(name, 28) + 14, band.position.y + 22), I18n.t(String(info.get("desc", ""))), 16, Look.INK_DIM)
	var count_text := "%d / %d" % [count.x, count.y]
	Look.text_right(ci, Vector2(band.end.x - 14, band.position.y + 20), count_text, 22, Look.INK)
	var bar := Rect2(band.position.x + 60, band.position.y + 42, band.size.x - 74, 5)
	ci.draw_rect(bar, Color(0.12, 0.17, 0.21, 0.95))
	if count.y > 0 and count.x > 0:
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(count.x) / float(count.y), bar.size.y)), color)
	var layout := map(group)
	var area := Rect2(panel.position.x + 10, band.end.y + 8, panel.size.x - 20, panel.end.y - band.end.y - 14)
	var rows := int(layout["rows"])
	var px := minf(area.size.x / (float(layout["width"]) + 0.6), 150.0)
	var r := minf(minf(px * 0.27, area.size.y / float(rows) * 0.21), 32.0)
	# Rows from the roots (above their two-line names) up to the deepest (under its points).
	var low := area.end.y - 44.0 - r * 1.3
	var high := area.position.y + r * 1.9
	var py := minf((low - high) / float(maxi(1, rows - 1)), 132.0) if rows > 1 else 0.0
	var lift := ((low - high) - py * float(rows - 1)) * 0.5 if rows > 1 else (low - high) * 0.5
	var pos := {}
	var nodes: Dictionary = layout["nodes"]
	for id in nodes:
		var slot: Vector2 = nodes[id]
		pos[id] = Vector2(area.get_center().x + (slot.x - (float(layout["width"]) - 1.0) * 0.5) * px, low - lift - slot.y * py)
	py = maxf(py, r * 3.2)
	_links(ci, group, pos, taken, t, settled, r / 17.0, true)
	for id in pos:
		var sid := String(id)
		var at: Vector2 = pos[id]
		var state := String(node_states.get(sid, "locked"))
		draw_seal(ci, at, r, sid, state, int(taken.get(sid, 0)), t,
			{"settled": settled, "offered": offer.has(sid), "selected": sid == selected})
		var label := I18n.t(String(node_of(sid).get("ko", sid)))
		var ink := Look.INK if state == "joined" or state == "full" else (Look.INK_DIM if state == "open" else Look.INK_MUTE)
		var label_box := Rect2(at.x - px * 0.5 + 3, at.y + r * 1.30, px - 6, 40)
		var lines := Look.wrapped_lines(label, label_box.size.x, 14)
		var size := 14 if lines.size() <= 2 else 12
		var box_h := float(mini(lines.size(), 2)) * Look.line_height(size)
		Look.fill_round(ci, Rect2(label_box.position.x + 4, label_box.position.y - 1, label_box.size.x - 8, box_h + 2), 4, Color(0.02, 0.04, 0.07, 0.55))
		_wrap(ci, label, Rect2(label_box.position, Vector2(label_box.size.x, box_h)), size, ink)
		ui.zone(Rect2(at.x - px * 0.5, at.y - py * 0.5, px, py), "talent:node:" + sid)


static func _draw_dust(ci: CanvasItem, panel: Rect2, color: Color) -> void:
	if _dust.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261019
		for n in range(26):
			_dust.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.7, 1.8)))
	var tone := Color(Look.STARLIGHT.lerp(color, 0.3), 0.55)
	for d in _dust:
		_sprite(ci, Cell.DOT, panel.position + Vector2(d.x * panel.size.x, d.y * panel.size.y), d.z * 1.6 / R_SOFT, tone)


# --------------------------------------------------------------------------- #
# The constellation column: every constellation's progress beside the level-up cards
# --------------------------------------------------------------------------- #
## The eight constellations as rows inside `rect` (the popup puts it in the command rail's
## column): emblem, name, joined / total, and one mark per node in the seal language
## (a lit star in the constellation's colour, a gold star when full, a ring when it can be
## picked, a faint point when locked, a starlight star with a ring when it is on offer).
## A constellation with a star on offer is lit. Each row is a touch zone
## `talent:group:<g>` (live when `zones_on`), the way into the map at that constellation.
## `opts`: settled, age (seconds; rows slide in from the right one after another from
## `at`), at, alpha.
static func draw_column(ci: CanvasItem, ui: Ui, rect: Rect2, taken: Dictionary, node_states: Dictionary,
		offer: Array, t: float, zones_on: bool, opts: Dictionary = {}) -> void:
	var settled := bool(opts.get("settled", false))
	var age := 9.0 if settled else float(opts.get("age", 9.0))
	var start := float(opts.get("at", 0.0))
	var a := float(opts.get("alpha", 1.0))
	var k_panel := _ease_out((age - start) / 0.18)
	if k_panel <= 0.0:
		for group in Balance.TALENT_GROUP_ORDER:
			ui.zone(Rect2(), "talent:group:" + String(group), false)
		return
	_glass(ci, rect, Look.STEEL, Color(0.016, 0.034, 0.055, 0.94), false, a * k_panel)
	var joined := 0
	var total := 0
	for node in Balance.TALENTS:
		total += 1
		if int(taken.get(String(node["id"]), 0)) > 0:
			joined += 1
	var head := Rect2(rect.position + Vector2(14, 8), Vector2(rect.size.x - 28, 34))
	_box(ci, Rect2(head.position, Vector2(head.size.x * 0.52, head.size.y)), I18n.t("arena.talents"), 21, Color(Look.GOLD, a * k_panel), HORIZONTAL_ALIGNMENT_LEFT)
	_box(ci, Rect2(head.position.x + head.size.x * 0.52, head.position.y, head.size.x * 0.48, head.size.y), "%d / %d" % [joined, total], 15, Color(Look.INK_DIM, a * k_panel), HORIZONTAL_ALIGNMENT_RIGHT)
	var groups: Array = Balance.TALENT_GROUP_ORDER
	var top := head.end.y + 6.0
	var row_h := (rect.end.y - 8.0 - top) / float(groups.size())
	for n in range(groups.size()):
		var group := String(groups[n])
		var row := Rect2(rect.position.x + 6, top + float(n) * row_h, rect.size.x - 12, row_h - 4)
		var k := _ease_out((age - start - 0.06 - float(n) * 0.03) / 0.20)
		ui.zone(row, "talent:group:" + group, zones_on and k >= 1.0)
		if k <= 0.0:
			continue
		var shift := (1.0 - k) * 36.0
		var r2 := Rect2(row.position + Vector2(shift, 0), row.size)
		var ra := a * k
		var color := group_color(group)
		var count := progress(group, taken)
		var offered_here := false
		for id in offer:
			if String(node_of(String(id)).get("group", "")) == group:
				offered_here = true
		if offered_here:
			var breath := 0.6 if settled else 0.5 + 0.5 * sin(t * 2.4)
			Look.fill_round(ci, r2, 5, Color(Look.STARLIGHT, (0.07 + 0.05 * breath) * ra))
			ci.draw_rect(Rect2(r2.position.x, r2.position.y + 4, 3, r2.size.y - 8), Color(Look.STARLIGHT, 0.9 * ra))
		else:
			Look.fill_round(ci, r2, 5, Color(color, (0.10 if count.x > 0 else 0.04) * ra))
			ci.draw_rect(Rect2(r2.position.x, r2.position.y + 4, 3, r2.size.y - 8), Color(color, (0.85 if count.x > 0 else 0.35) * ra))
		var line_y := r2.position.y + minf(22.0, r2.size.y * 0.32)
		draw_emblem(ci, group, Vector2(r2.position.x + 22, line_y), 13.0, Color(color.lightened(0.15), ra))
		var count_text := "%d / %d" % [count.x, count.y]
		var count_w := Look.text_width(count_text, 14) + 6.0
		_box(ci, Rect2(r2.position.x + 42, line_y - 12, r2.size.x - 50 - count_w, 24), group_name(group), 17, Color(color.lightened(0.25) if count.x > 0 or offered_here else color, ra), HORIZONTAL_ALIGNMENT_LEFT)
		_box(ci, Rect2(r2.end.x - count_w - 6, line_y - 11, count_w, 22), count_text, 14, Color(Look.INK if count.x > 0 else Look.INK_MUTE, ra), HORIZONTAL_ALIGNMENT_RIGHT)
		# One mark per node, in the table's order.
		var ids := ids_of(group)
		var pitch := minf(18.0, (r2.size.x - 24.0) / maxf(1.0, float(ids.size())))
		var size := clampf(pitch * 0.62, 5.0, 9.0)
		var mark_y := r2.end.y - minf(17.0, r2.size.y * 0.30)
		var x := r2.position.x + 13.0 + pitch * 0.5
		for id in ids:
			var at := Vector2(x, mark_y)
			var state := String(node_states.get(id, "locked"))
			if offer.has(id):
				_sprite(ci, Cell.HALO, at, size * 0.9 / R_SOFT, Color(Look.STARLIGHT, 0.45 * ra))
				_sprite(ci, Cell.THIN_RING, at, size * 1.25 / R_THIN, Color(Look.STARLIGHT, ra))
				_sprite(ci, Cell.PIP, at, size * 1.05 / R_SOFT, Color(Look.STARLIGHT, ra))
			elif state == "full":
				_sprite(ci, Cell.PIP, at, size * 1.05 / R_SOFT, Color(Look.GOLD, ra))
			elif state == "joined":
				_sprite(ci, Cell.PIP, at, size / R_SOFT, Color(color.lightened(0.25), ra))
			elif state == "open":
				_sprite(ci, Cell.THIN_RING, at, size * 0.62 / R_THIN, Color(color.lightened(0.25), 0.95 * ra))
			else:
				_sprite(ci, Cell.DOT, at, size * 0.42 / R_SOFT, Color(Look.STEEL_DIM, 0.9 * ra))
			x += pitch


# --------------------------------------------------------------------------- #
# The detail card of one node
# --------------------------------------------------------------------------- #
## Everything about one node: its seal, name, constellation and depth; whether it can be
## picked (and why not); its effect; what it needs; what it opens.
static func draw_detail(ci: CanvasItem, rect: Rect2, id: String, taken: Dictionary, node_states: Dictionary,
		offer: Array, t: float, settled: bool, ui: Ui = null) -> void:
	var node := node_of(id)
	if node.is_empty():
		Look.sheet(ci, rect, Look.STEEL, Look.GLASS_FACE)
		return
	var group := String(node.get("group", ""))
	var color := group_color(group)
	var state := String(node_states.get(id, "locked"))
	var count := int(taken.get(id, 0))
	var maximum := int(node.get("max", 1))
	var tier := frame_tier(id)
	var offered := offer.has(id)
	Look.sheet(ci, rect, color.lerp(Look.STEEL, 0.2), Look.GLASS_FACE, offered)
	Look.gradient_rect(ci, Rect2(rect.position + Vector2(5, 3), Vector2(rect.size.x - 10, 150)), Color(color, 0.30), Color(color, 0.0), true)
	ci.draw_rect(Rect2(rect.position.x + 5, rect.position.y + 3, rect.size.x - 10, 2), color)
	var seal := rect.position + Vector2(72, 78)
	draw_seal(ci, seal, 34.0, id, state, count, t, {"settled": settled})
	var x := rect.position.x + 146.0
	var w := rect.end.x - x - 14.0
	if offered:
		Look.chip(ci, Vector2(x, rect.position.y + 24), I18n.t("arena.map_offered_tag"), 14, Look.STARLIGHT, Look.BG_DEEP)
	var name_y := rect.position.y + (56.0 if offered else 44.0)
	_box(ci, Rect2(x, name_y - 16, w, 34), I18n.t(String(node.get("ko", id))), 26, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	draw_emblem(ci, group, Vector2(x + 9, name_y + 30), 9.0, color.lightened(0.2))
	var tier_word := I18n.t("arena.map_capstone") if tier == 3 else I18n.t("arena.talent_depth")
	var group_line := "%s · %s" % [group_name(group), tier_word]
	Look.text_left(ci, Vector2(x + 24, name_y + 30), group_line, 16, color.lightened(0.25))
	draw_depth(ci, Vector2(x + 24 + Look.text_width(group_line, 16) + 30, name_y + 30), tier, Look.STARLIGHT if tier == 3 else color, 5.5)
	# State: what the player can do with this node now.
	var state_y := rect.position.y + 172.0
	var state_text := ""
	var state_ink := Look.INK_DIM
	match state:
		"full":
			state_text = I18n.t("arena.map_state_full")
			state_ink = Look.GOLD
		"joined":
			state_text = I18n.t("arena.talent_taken") % [count, maximum]
			state_ink = color.lightened(0.35)
		"open":
			# From a level-up's map only the three on offer can be picked now.
			if offer.is_empty() or offered:
				state_text = I18n.t("arena.map_state_open")
				state_ink = color.lightened(0.35)
			else:
				state_text = I18n.t("arena.map_state_open_offer")
				state_ink = Look.INK_DIM
		"closed":
			state_text = I18n.t("arena.map_state_closed")
			state_ink = Look.WARN
		_:
			state_text = I18n.t("arena.map_state_locked")
			state_ink = Look.INK_MUTE
	Look.fill_round(ci, Rect2(rect.position.x + 14, state_y - 16, rect.size.x - 28, 32), 5, Color(state_ink, 0.12))
	_box(ci, Rect2(rect.position.x + 26, state_y - 14, rect.size.x - 52, 28), state_text, 18, state_ink, HORIZONTAL_ALIGNMENT_LEFT)
	if maximum > 1 and state != "locked":
		var pip_x := rect.end.x - 24.0
		for n in range(maximum - 1, -1, -1):
			var at := Vector2(pip_x, state_y)
			if n < count:
				ci.draw_colored_polygon(Look.star_points(at, 6.0, 0.46), Look.GOLD if state == "full" else color.lightened(0.3))
			else:
				var hollow := Look.star_points(at, 5.4, 0.46)
				hollow.append(hollow[0])
				ci.draw_polyline(hollow, Color(Look.STEEL_DIM, 0.9), 1.0, true)
			pip_x -= 15.0
	# Effect.
	var effect := I18n.t(String(node.get("desc", "")))
	if Talents.is_instant(node):
		effect += "\n" + I18n.t("arena.talent_instant")
	_wrap(ci, effect, Rect2(rect.position.x + 22, state_y + 26, rect.size.x - 44, 86), 20, Look.INK, true)
	# Needs and opens.
	var y := state_y + 124.0
	ci.draw_line(Vector2(rect.position.x + 18, y - 8), Vector2(rect.end.x - 18, y - 8), Color(color, 0.30), 1.0)
	y = _relations(ci, rect, y, I18n.t("arena.map_needs"), Talents.clauses(node), taken, node_states, t, settled, true, ui)
	var children: Array = []
	for child in Talents.children(id):
		children.append([child])
	y = _relations(ci, rect, y + 6.0, I18n.t("arena.map_unlocks"), children, taken, node_states, t, settled, false, ui)


## One relation list in the detail card: a caption and the nodes as small seals with names.
## For prerequisites each clause is one row and "any one of" is said once per row.
static func _relations(ci: CanvasItem, rect: Rect2, y: float, caption: String, groups: Array, taken: Dictionary,
		node_states: Dictionary, t: float, settled: bool, needs: bool, ui: Ui = null) -> float:
	Look.text_left(ci, Vector2(rect.position.x + 22, y + 9), caption, Look.TYPE_CAPTION, Look.INK_DIM)
	y += 24.0
	if groups.is_empty():
		Look.text_left(ci, Vector2(rect.position.x + 30, y + 10), I18n.t("arena.map_root") if needs else I18n.t("arena.map_leaf"), 16, Look.INK_MUTE)
		return y + 26.0
	var col_w := (rect.size.x - 44.0) * 0.5
	for options in groups:
		var list: Array = options
		if needs and list.size() > 1:
			Look.text_left(ci, Vector2(rect.position.x + 30, y + 9), I18n.t("arena.map_any_of"), 14, Look.INK_DIM)
			y += 22.0
		var n := 0
		for option in list:
			var oid := String(option)
			var at := Vector2(rect.position.x + 22.0 + float(n % 2) * col_w, y + float(n / 2) * 30.0)
			if at.y > rect.end.y - 22.0:
				break
			draw_seal(ci, at + Vector2(12, 10), 10.0, oid, String(node_states.get(oid, "locked")), int(taken.get(oid, 0)), t, {"settled": true})
			var joined := int(taken.get(oid, 0)) > 0
			_box(ci, Rect2(at.x + 30, at.y - 2, col_w - 36, 24), I18n.t(String(node_of(oid).get("ko", oid))), 16, Look.INK if joined else Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
			if ui != null:
				# A related star is a way to it: tapping it selects it on the map.
				ui.zone(Rect2(at.x, at.y - 6, col_w - 4, 32), "talent:node:" + oid)
			n += 1
		y += ceilf(float(n) / 2.0) * 30.0 + 2.0
	return y


# --------------------------------------------------------------------------- #
# The offer card (the level-up popup's cards)
# --------------------------------------------------------------------------- #
## One offered node as a card: its constellation's colour field with the emblem and the
## constellation's own map (this node ringed), the seal hanging over the field's edge,
## the name, the effect, the picks so far. The pick button is draw_pick_button().
## `opts`: settled, age (seconds since this card began to arrive; drives the reveal from
## top to bottom: field, map, seal pop and shine, name, effect, pips), alpha.
static func draw_offer_card(ci: CanvasItem, rect: Rect2, id: String, taken: Dictionary, node_states: Dictionary,
		t: float, opts: Dictionary = {}) -> void:
	var node := node_of(id)
	if node.is_empty():
		return
	var settled := bool(opts.get("settled", false))
	var age := 9.0 if settled else float(opts.get("age", 9.0))
	var a := float(opts.get("alpha", 1.0))
	var group := String(node.get("group", ""))
	var color := group_color(group)
	var info: Dictionary = Balance.TALENT_GROUPS.get(group, {})
	var tier := frame_tier(id)
	var count := int(taken.get(id, 0))
	var maximum := int(node.get("max", 1))
	var reveal := func(start: float, span: float) -> float: return _ease_out((age - start) / span)
	Look.sheet(ci, rect, color.lerp(Look.STEEL, 0.10), Look.GLASS_FACE, tier == 3, a)
	# The colour field: the constellation at full strength, darkening downwards.
	var field := Rect2(rect.position + Vector2(4, 3), Vector2(rect.size.x - 8, CARD_FIELD_H))
	var k_field: float = reveal.call(0.0, 0.16)
	Look.gradient_rect(ci, field, Color(color.lerp(Color.WHITE, 0.08), 0.92 * a * k_field), Color(color.darkened(0.45), 0.85 * a * k_field), true)
	Look.gradient_rect(ci, Rect2(field.position, Vector2(field.size.x, 60)), Color(0, 0, 0, 0.32 * a * k_field), Color(0, 0, 0, 0.0), true)
	draw_emblem(ci, group, field.position + Vector2(field.size.x - 58, 92), 62.0, Color(1, 1, 1, 0.12 * a * k_field))
	ci.draw_rect(Rect2(field.position.x, field.end.y - 2, field.size.x, 2), Color(color.lightened(0.45), a * k_field))
	# The constellation's name, and what it is about on its own line under it (a long English
	# line keeps its size instead of shrinking beside the name).
	draw_emblem(ci, group, rect.position + Vector2(24, 24), 12.0, Color(1, 1, 1, a * k_field))
	_box(ci, Rect2(rect.position + Vector2(42, 10), Vector2(rect.size.x - 56, 28)), group_name(group), 19, Color(Look.IVORY, a * k_field), HORIZONTAL_ALIGNMENT_LEFT)
	_box(ci, Rect2(rect.position + Vector2(42, 36), Vector2(rect.size.x - 56, 20)), I18n.t(String(info.get("desc", ""))), 14, Color(Look.IVORY, 0.82 * a * k_field), HORIZONTAL_ALIGNMENT_LEFT)
	# The constellation's map in the field, this node ringed: where the star will stand.
	var k_map: float = reveal.call(0.06, 0.18)
	var map_rect := Rect2(rect.position + CARD_MAP.position, Vector2(rect.size.x + CARD_MAP.size.x, CARD_MAP.size.y))
	_mini_map(ci, map_rect, group, taken, node_states, id if bool(opts.get("ring", true)) else "", t, settled, a * k_map)
	# The seal hangs over the field's lower edge.
	var seal := card_seal_point(rect)
	var pop: float = clampf((age - 0.14) / 0.30, 0.0, 1.0)
	var r := CARD_SEAL_R
	var flash := clampf(1.0 - absf(age - 0.34) / 0.16, 0.0, 1.0) if not settled else 0.0
	# On a card the seal is shown lit: the star this pick would light (the pips say how many
	# times it has been joined already).
	if bool(opts.get("seal", true)):
		draw_seal(ci, seal, r, id, "joined", count, t,
			{"settled": settled, "pop": pop if not settled else 1.0, "alpha": a, "flash": flash})
	if not settled and age > 0.30 and age < 0.80:
		_shine(ci, rect, (age - 0.30) / 0.50, a)
	# Name and effect, then the picks.
	var k_name: float = reveal.call(0.22, 0.16)
	# One baseline for every tier: just under the capstone star's lowest point.
	var name_y := seal.y + r * FRAME_REACH[2] + 14.0
	_box(ci, Rect2(rect.position.x + 14, name_y - 17 + (1.0 - k_name) * 8.0, rect.size.x - 28, 36), I18n.t(String(node.get("ko", id))), 27, Color(Look.INK, a * k_name))
	var k_effect: float = reveal.call(0.28, 0.16)
	var effect := I18n.t(String(node.get("desc", "")))
	_wrap(ci, effect, Rect2(rect.position.x + 18, name_y + 22 + (1.0 - k_effect) * 8.0, rect.size.x - 36, 66), 19, Color(Look.INK_DIM.lerp(Look.INK, 0.35), a * k_effect))
	var k_pips: float = reveal.call(0.34, 0.16)
	var row_y := name_y + 106.0
	if maximum > 1:
		var words := I18n.t("arena.talent_taken") % [count, maximum]
		var pips := float(maximum) * 15.0
		var left := rect.get_center().x - (pips + 10.0 + Look.text_width(words, 15)) * 0.5
		for n in range(maximum):
			var at := Vector2(left + 7.5 + float(n) * 15.0, row_y)
			if n < count:
				ci.draw_colored_polygon(Look.star_points(at, 6.0, 0.46), Color(color.lightened(0.3), a * k_pips))
			elif n == count:
				ci.draw_colored_polygon(Look.star_points(at, 6.0, 0.46), Color(Look.STARLIGHT, (0.55 + 0.35 * (0.5 + 0.5 * sin(t * 4.0))) * a * k_pips if not settled else 0.8 * a * k_pips))
			else:
				var hollow := Look.star_points(at, 5.2, 0.46)
				hollow.append(hollow[0])
				ci.draw_polyline(hollow, Color(Look.STEEL_DIM, 0.9 * a * k_pips), 1.0, true)
		Look.text_left(ci, Vector2(left + pips + 10.0, row_y), words, 15, Color(Look.INK_DIM, a * k_pips))
	elif Talents.is_instant(node):
		_box(ci, Rect2(rect.position.x + 14, row_y - 11, rect.size.x - 28, 22), I18n.t("arena.talent_instant"), 15, Color(Look.INK_DIM, a * k_pips))
	elif tier == 3:
		_box(ci, Rect2(rect.position.x + 14, row_y - 11, rect.size.x - 28, 22), I18n.t("arena.map_capstone"), 15, Color(Look.STARLIGHT, a * k_pips))


## Where an offer card's seal hangs (the centre of its face).
static func card_seal_point(rect: Rect2) -> Vector2:
	return Vector2(rect.get_center().x, rect.position.y + 3.0 + CARD_FIELD_H - 2.0)


## Where an offer card's constellation map puts a node.
static func card_map_point(rect: Rect2, id: String) -> Vector2:
	var group := String(node_of(id).get("group", ""))
	var area := Rect2(rect.position + CARD_MAP.position, Vector2(rect.size.x + CARD_MAP.size.x, CARD_MAP.size.y))
	var layout := map(group)
	var px := minf(area.size.x / (float(layout["width"]) + 0.4), 46.0)
	var py := area.size.y / float(maxi(2, int(layout["rows"])))
	return _place(group, area, px, py).get(id, area.get_center())


## The pick, played over PICK_TIME (0.45 s) while the battle still waits: the chosen card
## flares, its seal lifts and flies along an arc into its own place in the card's
## constellation map, which lights with a ring burst; the other cards sink and fade.
## `rects[n]` is the card of `offer[n]`; `age` is the time since the pick.
static func draw_pick_flourish(ci: CanvasItem, rects: Array, offer: Array, picked: String, taken: Dictionary,
		node_states: Dictionary, age: float, t: float) -> void:
	var landed := age >= 0.34
	for n in range(mini(offer.size(), rects.size())):
		var id := String(offer[n])
		var rect: Rect2 = rects[n]
		if id != picked:
			var k := clampf(age / 0.30, 0.0, 1.0)
			draw_offer_card(ci, Rect2(rect.position + Vector2(0, k * k * 46.0), rect.size), id, taken, node_states, t,
				{"settled": true, "alpha": 1.0 - k})
			continue
		var after := taken.duplicate()
		var lit_states := node_states.duplicate()
		if landed:
			after[id] = int(after.get(id, 0)) + 1
			lit_states[id] = "joined"
		var fade := 1.0 - clampf((age - 0.36) / 0.09, 0.0, 1.0)
		draw_offer_card(ci, rect, id, after, lit_states, t, {"settled": true, "alpha": fade, "seal": false, "ring": not landed})
		var flare := clampf(1.0 - age / 0.12, 0.0, 1.0)
		if flare > 0.0:
			Look.fill_round(ci, rect, 6, Color(1, 1, 1, 0.26 * flare))
		var from := card_seal_point(rect)
		var to := card_map_point(rect, id)
		var ctrl := from.lerp(to, 0.5) + Vector2((rect.size.x * 0.30) * (1.0 if to.x <= from.x else -1.0), -36.0)
		var k := clampf((age - 0.05) / 0.29, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		if age < 0.36:
			for j in range(5, 0, -1):
				var back := clampf(e - float(j) * 0.055, 0.0, 1.0)
				var at := _bezier(from, ctrl, to, back)
				_sprite(ci, Cell.SPARKLE, at, (5.0 - float(j) * 0.6) / R_SOFT, Color(Look.STARLIGHT, (0.85 - float(j) * 0.14) * fade))
			var pop := 1.0 + 0.14 * clampf(1.0 - absf(age - 0.06) / 0.06, 0.0, 1.0)
			var r := lerpf(CARD_SEAL_R * pop, 7.0, e)
			draw_seal(ci, _bezier(from, ctrl, to, e), r, id, "joined", int(taken.get(id, 0)), t, {"settled": true})
		if landed:
			var b := clampf((age - 0.34) / 0.11, 0.0, 1.0)
			_sprite(ci, Cell.HALO, to, lerpf(10.0, 22.0, b) / R_SOFT, Color(Look.STARLIGHT, 0.8 * (1.0 - b)))
			_sprite(ci, Cell.THIN_RING, to, lerpf(8.0, 36.0, b) / R_THIN, Color(Look.STARLIGHT, 1.0 - b))
			_sprite(ci, Cell.SPARKLE, to, lerpf(14.0, 4.0, b) / R_SOFT, Color(1, 1, 1, 1.0 - b * 0.6))


static func _bezier(a: Vector2, c: Vector2, b: Vector2, k: float) -> Vector2:
	return a.lerp(c, k).lerp(c.lerp(b, k), k)


## A constellation's map at card size: links and small stars, this node ringed.
static func _mini_map(ci: CanvasItem, rect: Rect2, group: String, taken: Dictionary, node_states: Dictionary,
		ring: String, t: float, settled: bool, a: float) -> void:
	if a <= 0.01:
		return
	var layout := map(group)
	var px := minf(rect.size.x / (float(layout["width"]) + 0.4), 46.0)
	var py := rect.size.y / float(maxi(2, int(layout["rows"])))
	var pos := _place(group, rect, px, py)
	for edge in layout["edges"]:
		var a2: Vector2 = pos[edge[0]]
		var b2: Vector2 = pos[edge[1]]
		var lit := int(taken.get(String(edge[0]), 0)) > 0 and int(taken.get(String(edge[1]), 0)) > 0
		_line(ci, a2, b2, Color(1, 1, 1, (0.85 if lit else 0.30) * a), 2.0 if lit else 1.2, bool(edge[2]))
	for id in pos:
		var sid := String(id)
		var at: Vector2 = pos[id]
		var state := String(node_states.get(sid, "locked"))
		if sid == ring:
			var breath := 1.0 if settled else 0.5 + 0.5 * sin(t * 3.4)
			_sprite(ci, Cell.HALO, at, 6.0 / R_SOFT, Color(Look.STARLIGHT, (0.55 + 0.3 * breath) * a))
			_sprite(ci, Cell.THIN_RING, at, (9.0 + breath * 2.0) / R_THIN * 1.15, Color(Look.STARLIGHT, a))
			_sprite(ci, Cell.PIP, at, 8.5 / R_SOFT, Color(Look.STARLIGHT, a))
		elif state == "joined" or state == "full":
			_sprite(ci, Cell.PIP, at, 6.6 / R_SOFT, Color(1, 1, 1, a))
		elif state == "open":
			_sprite(ci, Cell.PIP, at, 6.0 / R_SOFT, Color(0.55, 0.62, 0.68, 0.95 * a))
		else:
			_sprite(ci, Cell.DOT, at, 3.0 / R_SOFT, Color(1, 1, 1, 0.45 * a))


## A diagonal sheen crossing `rect` (progress 0..1), clipped to the rect.
static func _shine(ci: CanvasItem, rect: Rect2, progress: float, a: float) -> void:
	var p := clampf(progress, 0.0, 1.0)
	var span := rect.size.x + rect.size.y
	var cx := rect.position.x - rect.size.y * 0.5 + p * span
	var w := 34.0
	var band := PackedVector2Array([Vector2(cx - w, rect.position.y - 4), Vector2(cx + w, rect.position.y - 4),
		Vector2(cx + w - rect.size.y * 0.55, rect.end.y + 4), Vector2(cx - w - rect.size.y * 0.55, rect.end.y + 4)])
	var box := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var strength := sin(p * PI) * 0.16 * a
	for piece in Geometry2D.intersect_polygons(band, box):
		var poly: PackedVector2Array = piece
		var colors := PackedColorArray()
		for v in poly:
			var along := v.x + (v.y - rect.position.y) * 0.55 - cx
			colors.append(Color(1, 1, 1, strength * clampf(1.0 - absf(along) / w, 0.0, 1.0)))
		ci.draw_polygon(poly, colors)


## The gold pick button under a card, with the popup's arming shown on it. Before it is
## armed the button is a dark glass plate whose gold rim fills clockwise from the top as
## `arm` goes 0..1 (the label waits in dim gold); armed, it is the primary gold button
## and flashes once (`armed_age` seconds since it armed). Registers `talent:pick:<id>`
## live only when armed. `appear` 0..1 slides it in; `pressed` draws it pushed.
static func draw_pick_button(ci: CanvasItem, ui: Ui, rect: Rect2, id: String, label: String, arm: float,
		armed: bool, _t: float, opts: Dictionary = {}) -> void:
	var appear := clampf(float(opts.get("appear", 1.0)), 0.0, 1.0)
	if appear <= 0.0:
		ui.zone(rect, "talent:pick:" + id, false)
		return
	var pressed := bool(opts.get("pressed", false))
	var armed_age := float(opts.get("armed_age", 9.0))
	var a := appear
	var box := Rect2(rect.position + Vector2(0, (1.0 - _ease_out(appear)) * 10.0), rect.size)
	if armed:
		ui.zone(rect, "talent:pick:" + id, true)
		var was := ui.pressed
		if pressed:
			ui.pressed = "talent:pick:" + id
		ui.button(ci, box, label, "talent:pick:" + id, true, Look.GOLD, 22)
		ui.pressed = was
		ui.zones.pop_back()
		if armed_age < 0.35:
			var f := 1.0 - armed_age / 0.35
			Look.fill_round(ci, box.grow(2.0 + 6.0 * (1.0 - f)), 8, Color(Look.IVORY, 0.35 * f))
		return
	ui.zone(rect, "talent:pick:" + id, false)
	var p := clampf(arm, 0.0, 1.0)
	Look.fill_round(ci, box, 7, Color(0.02, 0.05, 0.08, 0.92 * a))
	Look.fill_round(ci, box.grow(-2.0), 6, Color(Look.GOLD_DEEP.darkened(0.55), 0.85 * a))
	var outline := _rounded_outline(box.grow(-1.0), 7.0)
	ci.draw_polyline(outline, Color(Look.GOLD_DEEP, 0.55 * a), 1.4, true)
	if p > 0.0:
		var part := _partial(outline, p)
		ci.draw_polyline(part, Color(Look.GOLD, a), 3.0, true)
		if p < 1.0 and part.size() > 0:
			_sprite(ci, Cell.SPARKLE, part[part.size() - 1], 0.22, Color(1, 1, 1, 0.95 * a))
	_box(ci, Rect2(box.position + Vector2(12, 2), box.size - Vector2(24, 4)), label, 22, Color(Look.GOLD, (0.38 + 0.30 * p) * a))


## A rounded rectangle's outline as a closed polyline starting at the top centre, clockwise.
static func _rounded_outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array([Vector2(rect.get_center().x, rect.position.y)])
	var corners := [[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5], [Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5], [Vector2(rect.position.x + r, rect.position.y + r), PI]]
	for corner in corners:
		var centre: Vector2 = corner[0]
		var start: float = corner[1]
		for s in range(7):
			pts.append(centre + Vector2.from_angle(start + PI * 0.5 * float(s) / 6.0) * r)
	pts.append(Vector2(rect.get_center().x, rect.position.y))
	return pts


## The first `fraction` of a polyline, by length.
static func _partial(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var want := total * clampf(fraction, 0.0, 1.0)
	var out := PackedVector2Array([points[0]])
	var run := 0.0
	for i in range(1, points.size()):
		var step := points[i - 1].distance_to(points[i])
		if run + step >= want:
			out.append(points[i - 1].lerp(points[i], (want - run) / maxf(step, 0.0001)))
			return out
		run += step
		out.append(points[i])
	return out
