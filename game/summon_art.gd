extends RefCounted
class_name SummonArt

## Dealer art is a portrait-only filtered texture; combat sprites keep Nearest.
static var _dealer: CanvasTexture
static var _source := Rect2()

static func dealer(ci: CanvasItem, box: Rect2, time: float, message: String = "", casting: float = 0.0) -> void:
	if _dealer == null:
		var texture := Art.tex("res://art/ui/dealer/witch.png")
		if texture == null:
			return
		var img := texture.get_image()
		if img.is_compressed():
			img.decompress()
		_source = Rect2(img.get_used_rect())
		_dealer = CanvasTexture.new()
		_dealer.diffuse_texture = texture
		_dealer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var motion := Vector2(sin(time * 2.6) * casting * 5, sin(time * 2) * 2)
	var target := Art.fit_rect(_source.size, Rect2(box.position + motion, box.size))
	ci.draw_texture_rect_region(_dealer, target, _source)
	if casting > 0:
		var hand := target.position + target.size * Vector2(0.85, 0.59)
		seal(ci, hand, 25 + casting * 15, time * 2.2, Look.CRYSTAL, casting)
	if not message.is_empty():
		var bubble := Rect2(box.end.x + 16, box.position.y + 36, 350, 110)
		Look.fill_round(ci, Rect2(bubble.position + Vector2(0, 4), bubble.size), 5, Color(0, 0, 0, 0.28))
		Look.fill_round(ci, bubble, 5, Color("#958569"))
		Look.fill_round(ci, bubble.grow(-1), 4, Color("#1d2c31"))
		var tail := bubble.position + Vector2(0, 46)
		ci.draw_colored_polygon(PackedVector2Array([tail + Vector2(1, -8), tail + Vector2(-13, 8), tail + Vector2(1, 7)]), Color("#958569"))
		ci.draw_colored_polygon(PackedVector2Array([tail + Vector2(2, -5), tail + Vector2(-9, 6), tail + Vector2(2, 5)]), Color("#1d2c31"))
		ci.draw_line(bubble.position + Vector2(19, 15), bubble.position + Vector2(53, 15), Look.GOLD_DEEP, 1)
		ci.draw_colored_polygon(Look.star_points(bubble.position + Vector2(62, 15), 3, 0.4), Look.GOLD)
		Look.wrap_text(ci, message, Rect2(bubble.position + Vector2(20, 23), bubble.size - Vector2(40, 28)), 20, Look.INK, true)


static func seal(ci: CanvasItem, at: Vector2, radius: float, time: float, color: Color, alpha: float = 1) -> void:
	for band in range(3):
		var r := radius * (0.56 + band * 0.22)
		ci.draw_arc(at, r, time * (1 if band % 2 else -1), time * (1 if band % 2 else -1) + TAU * 0.91, 64, Color(color, alpha * (0.65 - band * 0.14)), 2, true)
	for i in range(8):
		var p := at + Vector2.from_angle(time * 0.65 + TAU * i / 8.0) * radius * 0.83
		ci.draw_colored_polygon(Look.star_points(p, 3 + radius * 0.03, 0.35), Color(color.lightened(0.35), alpha))


## A single identity layout is shared by summon, fusion and the camp hero modal.
static func hero_info(ci: CanvasItem, unit: Dictionary, tier: int, box: Rect2,
		stats: bool = false, hero: Dictionary = {}) -> void:
	var x := box.position.x
	var y := box.position.y
	var element := String(unit.get("elem", "none"))
	var element_label := Balance.elem_ko(element)
	var element_w := Look.text_width(element_label, 22) + 42
	var name_w := box.size.x - element_w - 20
	var name_size := Look.text_box(ci, Rect2(x, y + 3, name_w, 48), Look.unit_name(unit), 40, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	var element_x := x + minf(name_w, Look.text_width(Look.unit_name(unit), name_size)) + 22
	Look.draw_elem(ci, Vector2(element_x + 10, y + 28), 12, element)
	Look.text_left(ci, Vector2(element_x + 30, y + 28), element_label, 22, Balance.elem_color(element))
	Look.wrap_text(ci, I18n.hero_concept(String(unit.get("id", ""))), Rect2(x, y + 69, box.size.x, 82), 22, Look.INK_DIM, true)
	var chips := trait_labels(unit)
	var chip_x := x
	var chip_y := y + 166
	for i in range(chips.size()):
		var width := Look.text_width(chips[i], 19) + 26
		if chip_x + width > box.end.x:
			chip_x = x
			chip_y += 43
		var rect := Rect2(chip_x, chip_y, width, 34)
		var tint := Look.CRYSTAL if i == 0 else Look.GOLD
		Look.fill_round(ci, rect, 4, tint.darkened(0.55))
		Look.fill_round(ci, rect.grow(-1), 3, Look.BG_DEEP.lerp(tint, 0.09))
		Look.text_center(ci, rect.get_center(), chips[i], 19, tint)
		chip_x += width + 9
	if not stats:
		return
	var st := Run.hero_stats(hero if not hero.is_empty() else {"unit": unit, "tier": tier, "n": 1})
	var rows := [["공격력", "%.0f" % float(st["atk"])], ["공격속도", "%.2f회/초" % float(st["rate"])], ["사거리", "%d" % int(st["range"])], ["치명타", "%s%%" % String.num(float(st["crit"]) * 100, 1)]]
	var width := (box.size.x - 12) * 0.5
	for i in range(rows.size()):
		var r := Rect2(x + (i % 2) * (width + 12), y + 253 + (i / 2) * 58, width, 50)
		Look.fill_round(ci, r, 5, Look.BG_DEEP)
		Look.text_left(ci, r.position + Vector2(12, 15), rows[i][0], 16, Look.INK_DIM)
		Look.text_box(ci, Rect2(r.position.x + 12, r.position.y + 23, r.size.x - 24, 25), rows[i][1], 22, Look.INK, HORIZONTAL_ALIGNMENT_RIGHT)


static func attack_type(unit: Dictionary) -> String:
	var kind := String(unit.get("bullet", "shot"))
	if kind == "beam":
		return "단일"
	if kind in ["splash", "zone"]:
		return "광역"
	if kind in ["chain", "ricochet"]:
		return "연쇄"
	var spec: Dictionary = Balance.BULLET.get(kind, Balance.BULLET["shot"])
	if int(spec.get("pierce", 1)) + (1 if Run.has("pierce") else 0) > 1:
		return "관통"
	return "단일"


static func trait_labels(unit: Dictionary) -> Array[String]:
	var labels: Array[String] = [attack_type(unit)]
	var element := String(unit.get("elem", "none"))
	match Balance.elem_rider(element):
		"burn": labels.append("화상")
		"slow": labels.append("둔화")
		"stun": labels.append("감전")
	if Balance.role_rider(String(unit.get("role", "single"))):
		if element == "water":
			labels.append("밀쳐내기")
		elif element == "none":
			labels.append("치명타 강화")
	if String(unit.get("bullet", "")) == "zone":
		labels.append("지속 피해")
	return labels
