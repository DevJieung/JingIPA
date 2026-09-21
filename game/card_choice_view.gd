extends RefCounted
class_name CardChoiceView

## Choosing only stages a replacement. Ads/Run apply it after an earned reward.
const PANEL := Rect2(56, 88, 1168, 692)
const CARD_SCALE := 0.51
const HAND_SCALE := 0.38
var opened := false
var slot := -1
var expected := -1
var desired := -1
var awaiting := false
var _seed := 0
var _wave := 0


func open(index: int) -> void:
	if Ads.busy or not Run.can_choose_card(index):
		return
	opened = true
	slot = index
	expected = Run.cards[index]
	desired = -1
	awaiting = false
	_seed = Run.run_seed
	_wave = Run.wave


func close() -> void:
	opened = false
	awaiting = false
	slot = -1
	expected = -1
	desired = -1


func current() -> bool:
	return opened and Run.run_seed == _seed and Run.wave == _wave \
		and Run.can_choose_card(slot) and Run.cards[slot] == expected


func update() -> void:
	# An earned reward changes the card before the full-screen ad is dismissed.
	if opened and not (awaiting and Ads.busy) and not current():
		close()


func input(event: InputEvent, ui: Ui) -> bool:
	if not opened:
		return false
	if Ads.busy:
		return true
	if not current():
		close()
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		return true
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return true
	var id := ui.hit(event.position)
	if id == "choice:close":
		close()
	elif id.begins_with("choice:card:"):
		var card := int(id.get_slice(":", 2))
		if Run.card_choice_allowed(slot, card, expected):
			desired = card
			Sfx.play("button", -14.0)
	elif id == "choice:watch" and Run.card_choice_allowed(slot, desired, expected):
		awaiting = true
		if not Ads.request_reward("card", {"slot": slot, "card": desired, "expected": expected}):
			awaiting = false
	return true


## Returns only the slot whose reward was actually applied, for screen feedback.
func completed(rewarded: bool) -> int:
	if not awaiting:
		return -1
	awaiting = false
	if rewarded and opened and Run.run_seed == _seed and Run.wave == _wave \
			and Run.can_choose_card(slot) and Run.cards[slot] == desired:
		var changed := slot
		close()
		return changed
	update()
	return -1


static func card_rect(index: int) -> Rect2:
	# Suit-major 4 x 13 grid: every rank and suit stays visible together.
	return Rect2(132 + (index % 13) * 82, 298 + (index / 13) * 92,
		Look.CARD_W * CARD_SCALE, Look.CARD_H * CARD_SCALE)


func preview_cards() -> Array[int]:
	var cards: Array[int] = Run.cards.duplicate()
	if desired >= 0:
		cards[slot] = desired
	return cards


func _hand_summary(ci: CanvasItem, box: Rect2, cards: Array[int], after: bool) -> void:
	Look.fill_round(ci, box, 5, Look.BG_DEEP)
	for index in range(cards.size()):
		var pos := box.position + Vector2(16 + index * 50, 18)
		if after and index == slot and desired < 0:
			Look.draw_card_back(ci, pos, HAND_SCALE)
			Look.text_center_out(ci, pos + Vector2(22, 32), "?", 25, Look.INK, Look.BG_DEEP, 2)
		else:
			Look.draw_card(ci, pos, cards[index], HAND_SCALE, index == slot)
	var text_at := box.position + Vector2(284, 24)
	Look.text_left(ci, text_at, "교체 후 족보" if after else "현재 족보", 19, Look.INK_DIM)
	var tier := Poker.evaluate(cards)
	var waiting := after and desired < 0
	Look.text_center_fit(ci, Vector2(box.end.x - 136, box.position.y + 55),
		"카드를 선택하세요" if waiting else Poker.HAND_KO.get(tier, "?"),
		25, Look.INK_DIM if waiting else Look.tier_color(tier).lightened(0.2), 248, 17)
	if not waiting:
		Look.draw_rarity_fit(ci, Rect2(box.end.x - 246, box.position.y + 79, 220, 15), tier, 4.2)


func draw(ci: CanvasItem, ui: Ui) -> void:
	if not opened:
		return
	# Rebuild targets so the table behind the modal has no live actions.
	ui.begin()
	ui.zone(Look.SCREEN, "choice:block")
	ci.draw_rect(Look.SCREEN, Color(0.015, 0.035, 0.04, 0.86))
	Look.material_panel(ci, PANEL, Look.PANEL, Look.GOLD_DEEP)
	# Leave room above the title for Ads' non-modal failure/cancellation notice.
	Look.text_left(ci, Vector2(88, 146), "%d번 카드 · 원하는 카드 선택" % (slot + 1), 30, Look.GOLD)
	_hand_summary(ci, Rect2(88, 174, 544, 100), Run.cards, false)
	_hand_summary(ci, Rect2(648, 174, 544, 100), preview_cards(), true)
	for rank in range(13):
		Look.text_center(ci, Vector2(card_rect(rank).get_center().x, 284), Poker.RANK_CHAR[rank], 18, Look.INK_DIM)
	for s in range(4):
		var col := Look.CARD_RED.lightened(0.35) if s in [1, 2] else Look.INK
		Look.draw_suit(ci, Vector2(105, card_rect(s * 13).get_center().y), 14, s, col)
	for index in range(52):
		var card := Poker.code(index % 13 + Poker.RANK_MIN, index / 13)
		var box := card_rect(index)
		var held := Run.cards.has(card)
		var selected := desired == card
		var replacing := card == expected
		if replacing:
			Look.draw_card_back(ci, box.position, CARD_SCALE)
		else:
			Look.draw_card(ci, box.position, card, CARD_SCALE, selected, held)
		ui.zone(box, "choice:card:%d" % card, not Ads.busy and not held)
		if not replacing and (held or selected):
			var ribbon := Rect2(box.position.x + 3, box.end.y - 25, box.size.x - 6, 20)
			Look.fill_round(ci, ribbon, 2, Look.BG_DEEP if held else Look.GOLD)
			Look.text_center_fit(ci, ribbon.get_center(), "보유 중" if held else "선택됨", 15,
				Look.INK_DIM if held else Look.BG_DEEP, ribbon.size.x - 4, 11)
	Look.text_center_fit(ci, Vector2(640, 683), "광고 시청을 완료하면 선택한 카드로 바뀝니다.", 20, Look.INK_DIM, 1080, 17)
	ui.button(ci, Rect2(88, 709, 248, 50), "취소", "choice:close", not Ads.busy, Look.PANEL_EDGE, 24)
	ui.reward_button(ci, Rect2(648, 703, 544, 60), "광고 보고 교체", "choice:watch",
		not Ads.busy and current() and Run.card_choice_allowed(slot, desired, expected), Look.GOLD, 28)
