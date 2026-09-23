extends RefCounted
class_name ReviveRewardView

## Rewards are already granted and saved by Run. This view only celebrates them.
var age := 0.0
var result: Dictionary = {}
var fx := Fx.new()
var _burst := false

func begin(reward: Dictionary) -> void:
	result = reward
	age = 0.0
	_burst = false
	fx.clear()
	Sfx.play("summon_charge")

func update(dt: float) -> void:
	age += dt
	fx.update(dt)
	if age >= 0.32 and not _burst:
		_burst = true
		var at := Vector2(378, 408)
		Sfx.play("summon_burst")
		Sfx.force("reveal9")
		fx.rays(at, Look.GOLD, 32, 760, 1.6)
		fx.burst(at, Look.GOLD.lightened(0.3), 150, 410, 1.5, 5, 100)
		for i in range(4):
			fx.ring(at, Look.GOLD.lightened(i * 0.15), 24, 150 + i * 65, 0.8 + i * 0.12, 5)
		fx.do_flash(Color(1.0, 0.95, 0.74, 0.48), 0.3)

func ready() -> bool:
	return age >= 1.1

func draw(ci: CanvasItem, ui: Ui) -> void:
	var unit: Dictionary = result.get("unit", {})
	var tier := int(result.get("hand", Poker.Hand.ROYAL))
	var element := String(unit.get("elem", "none"))
	var gold_only := bool(result.get("gold_only", false))
	var gold := int(result.get("gold", 0))
	ci.draw_rect(Look.SCREEN, Color(0.01, 0.02, 0.025, 0.84))
	ui.zone(Look.SCREEN, "revive:none")
	# Long gold rays and pixel stars sit behind the portrait, leaving the name clear.
	var at := Vector2(378, 408)
	for i in range(20):
		var angle := i * TAU / 20.0 + age * 0.06
		var direction := Vector2.from_angle(angle)
		var side := direction.orthogonal()
		ci.draw_colored_polygon(PackedVector2Array([
			at + direction * 88,
			at + direction * 370 - side * 9,
			at + direction * 370 + side * 9]), Color(Look.GOLD, 0.075))
	fx.draw_back(ci)
	Look.material_panel(ci, Rect2(142, 202, 996, 446), Look.PANEL, Look.GOLD_DEEP, "stone")
	Look.hero_card_panel(ci, Rect2(168, 224, 420, 324), element)
	SummonArt.seal(ci, at, 162, age * 0.30, Look.GOLD, 0.65)
	SummonArt.seal(ci, at, 136, -age * 0.23, Balance.elem_color(element), 0.42)
	for i in range(12):
		var angle := i * TAU / 12.0 + age * 0.12
		var p := at + Vector2.from_angle(angle) * Vector2(178, 163)
		var twinkle := 0.55 + 0.45 * sin(age * 2.2 + i * 1.7)
		ci.draw_colored_polygon(Look.star_points(p, 3 + twinkle * 3, 0.35), Color(Look.GOLD.lightened(0.45), 0.5 + twinkle * 0.5))
	var pop := 1.0 - pow(1.0 - clampf(age / 0.55, 0, 1), 3)
	if gold_only:
		_draw_gold(ci, at + Vector2(0, (1 - pop) * 40), pop)
	else:
		Art.draw_unit_fit(ci, unit, Rect2(212, 239 + (1 - pop) * 40, 332, 250), Color(1, 1, 1, pop))
	if not gold_only:
		Look.draw_rarity_fit(ci, Rect2(225, 501, 306, 32), tier, 14)
	fx.draw(ci)
	fx.draw_flash(ci, Look.SCREEN)
	# All reward copy is painted after particles so the grant stays unmistakable.
	Look.text_center(ci, Vector2(640, 109), "재도전 보상", 22, Look.INK_DIM)
	Look.text_box(ci, Rect2(190, 133, 900, 54), "부활 + Gold 획득!" if gold_only else "최고 등급 영웅 획득!", 42, Look.GOLD)
	if gold_only:
		Look.text_box(ci, Rect2(215, 499, 326, 38), "부활 보상 골드", 26, Look.GOLD)
		Look.text_box(ci, Rect2(622, 248, 476, 65), "+%s G" % _gold_text(gold), 43, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
		Look.text_box(ci, Rect2(624, 323, 472, 42), "부활 추가 보상", 26, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
		Look.fill_round(ci, Rect2(620, 397, 482, 125), 5, Look.BG_DEEP)
		Look.wrap_text(ci, "대기실에서 능력치를 강화하고\n같은 탄에 다시 도전하세요.", Rect2(638, 421, 444, 80), 24, Look.CRYSTAL, true)
		Look.text_box(ci, Rect2(182, 562, 392, 62), "골드가 즉시 지급되었습니다.", 22, Look.INK_DIM)
	else:
		Look.text_box(ci, Rect2(622, 240, 476, 65), Look.unit_name(unit), 43, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
		Look.text_box(ci, Rect2(624, 311, 472, 37), "최고 등급 · 로열 플러시", 25, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
		Look.draw_elem(ci, Vector2(638, 379), 13, element)
		Look.text_left(ci, Vector2(662, 379), Balance.elem_ko(element), 23, Balance.elem_color(element))
		Look.fill_round(ci, Rect2(620, 416, 482, 100), 5, Look.BG_DEEP)
		Look.text_box(ci, Rect2(637, 429, 446, 34), "영웅 전당에 보관되었습니다", 26, Look.CRYSTAL, HORIZONTAL_ALIGNMENT_LEFT)
		Look.wrap_text(ci, "대기실의 전장 배치에서 배치하세요.", Rect2(637, 472, 446, 32), 21, Look.INK_DIM, true)
		var explanation := "이미 보유한 영웅입니다.\n추가 카드는 전당에 보관됩니다." if bool(result.get("duplicate", false)) \
				else "같은 영웅을 다시 얻으면\n추가 카드는 전당에 보관됩니다."
		Look.wrap_text(ci, explanation, Rect2(182, 562, 392, 62), 21, Look.INK_DIM, true)
		if gold > 0:
			Look.text_box(ci, Rect2(624, 527, 472, 36), "+%s G" % _gold_text(gold), 28, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	var crystal_y := 596.0 if gold > 0 and not gold_only else 577.0
	Look.draw_crystal(ci, Vector2(638, crystal_y), 11, true)
	Look.text_box(ci, Rect2(664, crystal_y - 22, 427, 44), "크리스탈 전체 회복", 26, Look.CRYSTAL, HORIZONTAL_ALIGNMENT_LEFT)
	ui.button(ci, Rect2(420, 688, 440, 64), "대기실로", "revive:confirm", ready(), Look.GOLD, 29)


static func _gold_text(value: int) -> String:
	var digits := str(value)
	var output := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			output += ","
		output += digits[i]
	return output


static func _draw_gold(ci: CanvasItem, at: Vector2, opacity: float) -> void:
	for offset in [Vector2(-66, 16), Vector2(61, 3), Vector2(0, -43)]:
		var center: Vector2 = at + offset
		for level in range(3):
			var face := center + Vector2(0, 14 - level * 8)
			ci.draw_circle(face + Vector2(0, 6), 46, Color(Look.GOLD_DEEP, opacity))
			ci.draw_circle(face, 46, Color(Look.GOLD, opacity))
			ci.draw_arc(face, 37, 0, TAU, 16, Color(Look.GOLD_DEEP, opacity), 3)
		ci.draw_colored_polygon(Look.star_points(center - Vector2(0, 2), 22, 0.44), Color(Look.GOLD.lightened(0.65), opacity))
