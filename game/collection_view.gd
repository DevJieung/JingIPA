extends RefCounted
class_name CollectionView

const ELEMENTS := ["water", "fire", "ice", "elec", "none"]
const PAGE_SIZE := 10
var opened := false
var element := "water"
var page := 0
var fusion_only := false

func close() -> void:
	opened = false

func heroes() -> Array:
	var result: Array = []
	if fusion_only:
		var best: Dictionary = {}
		for tier in range(9, -1, -1):
			for unit in Roster.fusion_units(tier):
				if String(unit.get("elem", "none")) == element and Save.seen_units.has(String(unit["id"])):
					best = unit
					break
			if not best.is_empty():
				break
		if best.is_empty():
			for unit in Roster.fusion_units():
				if String(unit.get("elem", "none")) == element:
					best = unit
		result.append(best)
		return result
	for unit in Roster.UNITS:
		if Save.seen_units.has(String(unit["id"])) and String(unit.get("elem", "none")) == element:
			result.append(unit)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) > int(b["tier"])
		return String(a["id"]) < String(b["id"]))
	return result

func input(event: InputEvent, ui: Ui) -> bool:
	if not opened:
		return false
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return true
	var id := ui.hit(event.position)
	if id == "collection:close":
		close()
	elif id.begins_with("collection:element:"):
		element = id.get_slice(":", 2)
		page = 0
	elif id == "collection:prev":
		page = maxi(0, page - 1)
	elif id == "collection:next":
		page += 1
	elif id.begins_with("collection:source:"):
		fusion_only = id.ends_with("fusion")
		page = 0
	return true

func draw(ci: CanvasItem, ui: Ui) -> void:
	if not opened:
		return
	ci.draw_rect(Look.SCREEN, Color(0, 0, 0, 0.88))
	ui.zone(Look.SCREEN, "collection:none")
	Look.material_panel(ci, Rect2(76, 88, 1128, 660), Look.PANEL, Look.GOLD_DEEP)
	Look.text_left(ci, Vector2(104, 128), "만난 수호자" if fusion_only else "만난 영웅", 34, Look.GOLD)
	Look.text_left(ci, Vector2(320, 128), "%d / %d" % [_fusion_seen_count(), ELEMENTS.size()] if fusion_only else "%d / %d" % [Save.seen_count(), Roster.UNITS.size()], 25, Look.INK_DIM)
	ui.tab(ci, Rect2(544, 106, 226, 42), "일반 소환", "collection:source:normal", not fusion_only, 19)
	ui.tab(ci, Rect2(782, 106, 272, 42), "합성 전용 수호자", "collection:source:fusion", fusion_only, 19)
	ui.button(ci, Rect2(1080, 106, 96, 42), "닫기", "collection:close", true, Look.PANEL_EDGE, 20)
	for index in range(ELEMENTS.size()):
		var el: String = ELEMENTS[index]
		var rect := Rect2(104 + index * 216, 170, 208, 48)
		ui.tab(ci, rect, Balance.elem_ko(el), "collection:element:" + el, el == element, 22)
		Look.draw_elem(ci, rect.position + Vector2(24, 24), 12, el)
	var entries := heroes()
	page = clampi(page, 0, maxi(0, (entries.size() - 1) / PAGE_SIZE))
	for cell in range(PAGE_SIZE):
		var index := page * PAGE_SIZE + cell
		if index >= entries.size():
			break
		var unit: Dictionary = entries[index]
		var rect := Rect2(104 + (cell % 5) * 216, 238 + (cell / 5) * 213, 208, 202)
		var discovered := Save.seen_units.has(String(unit["id"]))
		var caption := ("합성 전용" if discovered else "합성으로 발견") if fusion_only else ""
		HeroCard.draw(ci, rect, {"unit": unit, "tier": int(unit["tier"]), "awakened": fusion_only}, false, caption, fusion_only and not discovered)
		if fusion_only and not discovered:
			ci.draw_rect(Rect2(rect.position + Vector2(25, 3), Vector2(rect.size.x - 31, 21)), Look.hero_card_face(String(unit["elem"])))
			Look.text_box(ci, Rect2(rect.position + Vector2(26, 4), Vector2(rect.size.x - 32, 20)), "미발견", 16, Look.INK_DIM)
	if fusion_only:
		Look.text_box(ci, Rect2(348, 441, 810, 30), "획득한 최고 등급의 수호자를 표시합니다", 19, Look.INK_DIM)
		Look.wrap_text(ci, "뽑기로 나오지 않는 각성 수호자\n높은 별의 재료 5장을 합성해 만나세요", Rect2(348, 478, 810, 86), 26, Look.GOLD)
	if entries.is_empty():
		Look.text_center(ci, Vector2(640, 445), "아직 만난 영웅이 없습니다", 25, Look.INK_DIM)
	ui.button(ci, Rect2(104, 687, 108, 40), "이전", "collection:prev", page > 0, Look.PANEL_EDGE, 20)
	Look.text_center(ci, Vector2(640, 707), "%d / %d 페이지" % [page + 1, maxi(1, ceili(entries.size() / float(PAGE_SIZE)))], 20, Look.INK_DIM)
	ui.button(ci, Rect2(1072, 687, 108, 40), "다음", "collection:next", (page + 1) * PAGE_SIZE < entries.size(), Look.PANEL_EDGE, 20)


func _fusion_seen_count() -> int:
	var kinds := {}
	for tier in range(10):
		for unit in Roster.fusion_units(tier):
			if Save.seen_units.has(String(unit["id"])):
				kinds[String(unit["elem"])] = true
	return kinds.size()
