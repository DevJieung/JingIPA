extends RefCounted
class_name SummonArt

## 의식의 안내자(마녀) 원화는 초상화 전용 필터 텍스처다. 전투 스프라이트는 Nearest 를 지킨다.
static var _dealer: CanvasTexture

## 마녀 원화(art/ui/dealer/witch.png, 1254x1254)에서 얼굴과 모자의 달 장식이 들어오는 원.
## ★ 원화의 왼손에는 포커 시절의 트럼프 카드가 들려 있다. 원화를 고치지 않고 **얼굴 둘레만**
##   둥글게 잘라 쓴다 — 카드를 든 손(x < 340)과 치켜든 손(x > 1000)은 원 밖이다.
## ★ 이 원은 **두 구도에 다 맞춘 값**이다 — 2026-09-14 의 원화(얼굴이 위쪽 · 작다)와 2026-10-07 에
##   작업 트리에 들어온 큰 머리 판(얼굴이 아래쪽 · 크다). 두 그림 모두 눈 · 입 · 모자의 달 장식이
##   들어오고 카드는 안 들어온다(두 그림에 직접 대어 확인했다). 한쪽 그림에만 맞추면
##   (예: 큰 머리 판의 얼굴에 맞춘 (628, 625) · 260) 다른 그림에서는 이마가 잘리고 가슴께가 들어온다.
##   원화를 다시 그리면 이 두 줄을 그 그림에 맞춰 다시 잡는다. tests/arena_visual_review.py 의
##   의식판 촬영으로 공통 색상·배치를 확인하고, 이 안내자 메달을 쓰는 화면도 별도 확인한다.
const GUIDE_CENTER := Vector2(628, 512)
const GUIDE_RADIUS := 300.0


## 의식의 안내자 — 황동 테를 두른 둥근 초상. 그림이 없으면 별 하나짜리 빈 메달이다.
static func guide(ci: CanvasItem, center: Vector2, radius: float, time: float = 0.0) -> void:
	if _dealer == null:
		var texture := Art.tex("res://art/ui/dealer/witch.png")
		if texture != null:
			_dealer = CanvasTexture.new()
			_dealer.diffuse_texture = texture
			_dealer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ci.draw_circle(center + Vector2(0, 3), radius + 5, Color(0, 0, 0, 0.35))
	ci.draw_circle(center, radius + 5, Look.GOLD_DEEP)
	ci.draw_circle(center, radius + 2, Look.BG_DEEP)
	ci.draw_circle(center, radius, Color("#1b2a3a"))
	if _dealer == null:
		ci.draw_colored_polygon(Look.star_points(center, radius * 0.5), Look.GOLD)
		return
	var size := Vector2(_dealer.get_width(), _dealer.get_height())
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in range(40):
		var direction := Vector2.from_angle(TAU * float(i) / 40.0)
		points.append(center + direction * radius)
		uvs.append((GUIDE_CENTER + direction * GUIDE_RADIUS) / size)
	ci.draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, _dealer)
	# 테 위의 작은 별 하나가 느리게 돈다 — 살아 있는 메달로 보이게 하는 한 점.
	var orbit := center + Vector2.from_angle(time * 0.6 - PI * 0.5) * (radius + 3.5)
	ci.draw_colored_polygon(Look.star_points(orbit, 5.5, 0.42), Look.BG_DEEP)
	ci.draw_colored_polygon(Look.star_points(orbit, 4.0, 0.42), Look.GOLD)


## 안내자의 말풍선. 꼬리는 아래(안내자 쪽)를 향한다. 글은 상자 안에서 줄을 바꾼다.
static func bubble(ci: CanvasItem, box: Rect2, message: String, tail_x: float) -> void:
	Look.fill_round(ci, Rect2(box.position + Vector2(0, 4), box.size), 5, Color(0, 0, 0, 0.28))
	Look.fill_round(ci, box, 5, Color("#958569"))
	Look.fill_round(ci, box.grow(-1), 4, Color("#1d2c31"))
	var tail := Vector2(clampf(tail_x, box.position.x + 20, box.end.x - 20), box.end.y)
	ci.draw_colored_polygon(PackedVector2Array([tail + Vector2(-9, -1), tail + Vector2(9, -1), tail + Vector2(0, 12)]), Color("#958569"))
	ci.draw_colored_polygon(PackedVector2Array([tail + Vector2(-7, -2), tail + Vector2(7, -2), tail + Vector2(0, 9)]), Color("#1d2c31"))
	ci.draw_line(box.position + Vector2(14, 12), box.position + Vector2(44, 12), Look.GOLD_DEEP, 1)
	ci.draw_colored_polygon(Look.star_points(box.position + Vector2(53, 12), 3, 0.4), Look.GOLD)
	Look.wrap_text(ci, message, Rect2(box.position + Vector2(14, 20), box.size - Vector2(28, 26)), 19, Look.INK, true)


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
	var concept := I18n.hero_concept(String(unit.get("base_id", unit.get("id", ""))))
	Look.wrap_text(ci, concept, Rect2(x, y + 69, box.size.x, 68), 22, Look.INK_DIM, true)
	if bool(unit.get("fusion_only", false)):
		Look.text_box(ci, Rect2(x, y + 210, box.size.x, 30), "합성 전용 · 각성 수호자", 20, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
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
