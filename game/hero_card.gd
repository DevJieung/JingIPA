extends RefCounted
class_name HeroCard


static func draw(ci: CanvasItem, rect: Rect2, hero: Dictionary, selected: bool = false,
		caption: String = "", locked: bool = false) -> void:
	var unit: Dictionary = hero["unit"]
	var tier := int(hero["tier"])
	var element := String(unit.get("elem", "none"))
	var color := Balance.elem_color(element)
	Look.hero_card_panel(ci, rect, element)
	var portrait_tint := Color(0.60, 0.60, 0.60, 1.0) if locked else Color.WHITE
	# Cards carry identity only. Combat values live in the Hero Info detail panel.
	if rect.size.x > rect.size.y * 1.7:
		Art.draw_unit_fit(ci, unit, Rect2(rect.position + Vector2(8, 8), Vector2(46, rect.size.y - 16)), portrait_tint)
		var x := rect.position.x + 64
		_text_left_fit(ci, Vector2(x, rect.position.y + 23), Look.unit_name(unit), 20, Look.INK, rect.end.x - x - 8)
		Look.draw_elem(ci, Vector2(x + 9, rect.end.y - 22), 9, element)
		Look.draw_rarity_fit(ci, Rect2(x + 25, rect.end.y - 32, minf(76, rect.end.x - x - 35), 20), tier, 5.2)
		if caption != "":
			_text_left_fit(ci, Vector2(x + 110, rect.end.y - 22), caption, 15, color, rect.end.x - x - 120)
	else:
		var narrow := rect.size.x < 110
		Look.draw_elem(ci, rect.position + Vector2(13, 14), 8 if narrow else 9, element)
		Look.draw_rarity_fit(ci, Rect2(rect.position + Vector2(25, 4), Vector2(rect.size.x - 31, 20)), tier, 5.0)
		var caption_h := 23.0 if caption != "" or locked else 0.0
		var name_h := 44.0 if narrow else 32.0
		var name_box := Rect2(rect.position.x + 6, rect.end.y - name_h - caption_h - 5, rect.size.x - 12, name_h)
		var portrait := Rect2(rect.position + Vector2(12, 29), Vector2(rect.size.x - 24, maxf(18, name_box.position.y - rect.position.y - 35)))
		Art.draw_unit_fit(ci, unit, portrait, portrait_tint)
		if narrow:
			var lines := Look.wrapped_lines(Look.unit_name(unit), name_box.size.x, 18)
			var height := lines.size() * Look.line_height(18)
			Look.wrap_text(ci, Look.unit_name(unit), Rect2(name_box.position + Vector2(0, maxf(0, (name_h - height) * 0.5)), name_box.size), 18, Look.INK)
		else:
			Look.text_box(ci, name_box, Look.unit_name(unit), 22, Look.INK)
		if locked:
			_draw_locked(ci, Rect2(rect.position.x + 6, rect.end.y - 24, rect.size.x - 12, 20), caption)
		elif caption != "":
			Look.text_box(ci, Rect2(rect.position.x + 6, rect.end.y - 26, rect.size.x - 12, 22), caption, 15, Look.INK_DIM)
	if selected and not locked:
		# 꺾쇠는 속성·등급 줄을 안 가리면서 「골랐다」를 모양으로 말한다.
		ci.draw_rect(rect.grow(3), Look.BG_DEEP, false, 7)
		Look.draw_brackets(ci, rect.grow(3), 18.0, Look.INK, 5.0)
		var badge := Rect2(rect.end.x - 28, rect.position.y + 26, 23, 23)
		if rect.size.x > rect.size.y * 1.7:
			badge = Rect2(rect.position.x + 7, rect.end.y - 28, 23, 23)
		Look.fill_round(ci, badge, 3, Look.GOLD)
		ci.draw_line(badge.position + Vector2(5, 11), badge.position + Vector2(10, 16), Look.BG_DEEP, 3)
		ci.draw_line(badge.position + Vector2(10, 16), badge.position + Vector2(19, 6), Look.BG_DEEP, 3)


static func _draw_locked(ci: CanvasItem, rect: Rect2, caption: String) -> void:
	Look.fill_round(ci, rect, 3, Look.BG_DEEP)
	var size := Look.fit_size(caption, 14, rect.size - Vector2(26, 2))
	var left := rect.get_center().x - (Look.text_width(caption, size) + 19) * 0.5
	var center := Vector2(left + 6, rect.get_center().y)
	ci.draw_arc(center - Vector2(0, 3), 4, PI, TAU, 8, Look.INK_DIM, 2)
	Look.fill_round(ci, Rect2(center - Vector2(6, 1), Vector2(12, 8)), 2, Look.INK_DIM)
	ci.draw_rect(Rect2(center + Vector2(-1, 1), Vector2(2, 3)), Look.BG_DEEP)
	Look.text_left(ci, Vector2(left + 19, rect.get_center().y), caption, size, Look.INK_DIM)


static func _text_left_fit(ci: CanvasItem, at: Vector2, label: String, size: int,
		color: Color, width: float) -> void:
	Look.text_box(ci, Rect2(at - Vector2(0, Look.font(size).get_height(size) * 0.5),
		Vector2(width, Look.font(size).get_height(size))), label, size, color, HORIZONTAL_ALIGNMENT_LEFT)
