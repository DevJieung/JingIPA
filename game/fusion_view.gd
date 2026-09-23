extends RefCounted
class_name FusionView

const PAGE_SIZE := 12
var opened := false
var selected: Array[int] = []
var page := 0
var note := "대기 중인 영웅 카드 5장을 선택하세요. 출전 중인 영웅은 합성할 수 없습니다."
var _result_seen := false
var reveal_age := -1.0
var _burst := false
var _fx := Fx.new()
var _materials: Array = []
var restore_age := -1.0
var _undo_requested := false
var _cached_id := -1
var _restored_cards := 0

func update(dt: float) -> void:
	if _undo_requested and not Ads.busy:
		_undo_requested = false
		if Run.fusion_pending.is_empty():
			_begin_restore()
	_fx.update(dt)
	if restore_age >= 0:
		restore_age += dt
		for i in range(_restored_cards, _materials.size()):
			if restore_age < 0.30 + i * 0.16:
				break
			_restored_cards += 1
			var at := Vector2(240 + i * 200, 428)
			_fx.burst(at, Look.CRYSTAL, 24, 110, 0.65, 3, 25)
			_fx.ring(at, Look.GOLD, 15, 112, 0.65, 3)
		return
	if reveal_age < 0 or Run.fusion_pending.is_empty():
		return
	reveal_age += dt
	if reveal_age >= 1.35 and not _burst:
		_burst = true
		var col := Look.tier_color(int(Run.fusion_pending["tier"]))
		var at := Vector2(350, 418)
		Sfx.play("fusion_burst")
		_fx.rays(at, col, 30, 580, 0.9)
		_fx.burst(at, Look.GOLD, 90, 420, 1.0, 5, 120)
		_fx.shards(Rect2(at - Vector2(45, 60), Vector2(90, 120)), Look.CARD_BG, 30)
		for i in range(4):
			_fx.ring(at, col.lightened(0.15 * i), 20, 160 + i * 60, 0.8, 6)
		_fx.do_flash(Color(1, 0.95, 0.78, 0.48), 0.26)



func active() -> bool:
	return opened or not Run.fusion_pending.is_empty()


func input(event: InputEvent, ui: Ui) -> bool:
	if not active():
		return false
	if Ads.busy:
		return true
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return true
	var id := ui.hit(event.position)
	if restore_age >= 0:
		if id == "fusion:restored" and restore_age >= 1.35:
			restore_age = -1.0
			_fx.clear()
		return true
	if not Run.fusion_pending.is_empty():
		if id == "fusion:accept":
			Run.accept_fusion()
			selected.clear()
			_result_seen = false
		elif id == "fusion:undo":
			_cache_materials()
			_undo_requested = true
			Ads.request_reward("fusion_undo", {"fusion_id": int(Run.fusion_pending["id"])})
		return true
	_clean_selection()
	if id == "fusion:close":
		opened = false
		selected.clear()
	elif id == "fusion:prev":
		page = maxi(0, page - 1)
	elif id == "fusion:next":
		page += 1
	elif id == "fusion:clear":
		selected.clear()
	elif id == "fusion:go":
		_materials = Run.fusion_materials(selected).duplicate(true)
		if not Run.fuse_heroes(selected).is_empty():
			_cached_id = int(Run.fusion_pending["id"])
			reveal_age = 0
			_burst = false
			_fx.clear()
			Sfx.play("fusion_charge")
	elif id.begins_with("material:"):
		var code := int(id.get_slice(":", 1))
		if not Run.fusion_material_allowed(code):
			return true
		if selected.has(code):
			selected.erase(code)
		elif selected.size() < 5:
			selected.append(code)
		else:
			note = "5장이 선택되어 있습니다. 선택한 카드를 다시 누르면 제외됩니다."
	return true


func _clean_selection() -> void:
	for index in range(selected.size() - 1, -1, -1):
		if not Run.fusion_material_allowed(selected[index]):
			selected.remove_at(index)


func draw(ci: CanvasItem, ui: Ui) -> void:
	if not active():
		return
	opened = true
	ci.draw_rect(Look.SCREEN, Color(0, 0, 0, 0.88))
	ui.zone(Look.SCREEN, "fusion:none")
	Look.material_panel(ci, Rect2(38, 78, 1204, 674), Look.PANEL, Look.GOLD_DEEP)
	Look.text_left(ci, Vector2(64, 116), "영웅 합성", 32, Look.GOLD)
	if restore_age >= 0:
		_draw_restored(ci, ui)
		return
	if not Run.fusion_pending.is_empty():
		_cache_materials()
		_result_seen = true
		_draw_result(ci, ui)
		return
	if _result_seen:
		selected.clear()
		_result_seen = false
		note = "합성을 되돌렸습니다. 결과 영웅을 회수하고 재료 5장을 복구했습니다."
	_clean_selection()
	ui.button(ci, Rect2(1122, 98, 94, 42), "닫기", "fusion:close", true, Look.PANEL_EDGE, 20)
	Look.text_left(ci, Vector2(66, 152), "대기 중인 영웅카드 5장을 합성해서 새로운 영웅을 만들어 보세요", 18, Look.INK_DIM)
	var materials := Run.fusion_materials(selected)
	for i in range(5):
		var rect := Rect2(66 + i * 170, 176, 158, 128)
		if i < materials.size():
			HeroCard.draw(ci, rect, materials[i], true)
			ui.zone(rect, "material:%d" % selected[i])
		else:
			Look.fill_round(ci, rect, 4, Look.BG_DEEP)
			Look.text_center(ci, rect.get_center(), "%d" % (i + 1), 32, Look.PANEL_EDGE)
	Look.text_left(ci, Vector2(66, 333), "전당에서 대기중인 카드만 합성 가능합니다", 20, Look.INK)
	# 같은 캐릭터의 모든 보유 슬롯을 보여 주되 출전 중인 카드는 선택할 수 없다.
	var all := Run.fusion_candidates()
	page = clampi(page, 0, maxi(0, (all.size() - 1) / PAGE_SIZE))
	for cell in range(PAGE_SIZE):
		var index := page * PAGE_SIZE + cell
		if index >= all.size():
			break
		var code := all[index]
		var hero: Dictionary = Run.heroes[code] if code < Run.FUSION_BENCH else Run.bench[code - Run.FUSION_BENCH]
		var rect := Rect2(66 + (cell % 6) * 193, 354 + (cell / 6) * 154, 183, 146)
		var allowed := Run.fusion_material_allowed(code)
		HeroCard.draw(ci, rect, hero, selected.has(code), "출전 중" if not allowed else "", not allowed)
		ui.zone(rect, "material:%d" % code, allowed)
	ui.button(ci, Rect2(66, 678, 116, 44), "이전", "fusion:prev", page > 0, Look.PANEL_EDGE, 20)
	Look.text_center(ci, Vector2(640, 700), "%d / %d 페이지" % [page + 1, maxi(1, ceili(float(all.size()) / PAGE_SIZE))], 20, Look.INK_DIM)
	ui.button(ci, Rect2(1100, 678, 116, 44), "다음", "fusion:next", (page + 1) * PAGE_SIZE < all.size(), Look.PANEL_EDGE, 20)
	_draw_average(ci, materials)
	ui.button(ci, Rect2(928, 212, 288, 44), "%d / 5장 · 합성" % selected.size(), "fusion:go", selected.size() == 5 and materials.size() == 5, Look.GOLD, 24)
	ui.button(ci, Rect2(928, 260, 288, 44), "선택 초기화", "fusion:clear", not selected.is_empty(), Look.PANEL_EDGE, 20)


func _draw_average(ci: CanvasItem, materials: Array) -> void:
	Look.fill_round(ci, Rect2(928, 174, 288, 34), 4, Look.BG_DEEP)
	Look.text_box(ci, Rect2(938, 177, 96, 28), "평균 희귀도", 18, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	var average := float(Run.fusion_score(materials)) / 10.0 if materials.size() == 5 else 0.0
	for index in range(5):
		var center := Vector2(1048 + index * 22, 191)
		var star := Look.star_points(center, 9)
		ci.draw_colored_polygon(star, Color("#39454f"))
		var fill := clampf(average - index, 0, 1)
		if fill > 0:
			var clip := PackedVector2Array([center + Vector2(-10, -10), center + Vector2(-10 + 20 * fill, -10),
				center + Vector2(-10 + 20 * fill, 10), center + Vector2(-10, 10)])
			for polygon in Geometry2D.intersect_polygons(star, clip):
				ci.draw_colored_polygon(polygon, Look.GOLD)
		star.append(star[0])
		ci.draw_polyline(star, Look.GOLD if fill > 0 else Color("#8b9aa5"), 1, true)
	Look.text_box(ci, Rect2(1156, 177, 52, 28), "%.1f" % average if materials.size() == 5 else "-", 23, Look.GOLD)


func _cache_materials() -> void:
	var pending := Run.fusion_pending
	if pending.is_empty() or _cached_id == int(pending.get("id", -1)):
		return
	_cached_id = int(pending.get("id", -1))
	_materials.clear()
	var before: Array = pending.get("before_b", [])
	for code in pending.get("material_codes", []):
		var index := int(code) - Run.FUSION_BENCH
		if index >= 0 and index < before.size():
			_materials.append(Run._hero_in(before[index]))
	if _materials.size() == 5:
		return
	# Older pending saves predate material_codes. Remove the result from today's
	# hall, then compare counts so even identical material cards return individually.
	_materials.clear()
	var remaining: Array = Run.snapshot()["bench"].duplicate(true)
	# Materials are hall-only. A larger battlefield means the result was deployed
	# there; in that case every current hall card must remain in the comparison.
	if Run.heroes.size() == (pending.get("before_h", []) as Array).size():
		for i in range(remaining.size() - 1, -1, -1):
			if String(remaining[i].get("u", "")) == String(pending.get("unit", "")):
				remaining.remove_at(i)
				break
	for hero in before:
		var match_index := remaining.find(hero)
		if match_index >= 0:
			remaining.remove_at(match_index)
		elif _materials.size() < 5:
			_materials.append(Run._hero_in(hero))


func _begin_restore() -> void:
	restore_age = 0.0
	reveal_age = -1.0
	_restored_cards = 0
	_result_seen = false
	selected.clear()
	_fx.clear()
	Sfx.play("summon_charge")


func _draw_restored(ci: CanvasItem, ui: Ui) -> void:
	_fx.draw_back(ci)
	SummonArt.seal(ci, Vector2(640, 425), 140, -restore_age * 0.6, Look.CRYSTAL, 0.34)
	for i in range(_materials.size()):
		var progress := clampf((restore_age - 0.12 - i * 0.16) / 0.5, 0, 1)
		if progress <= 0:
			continue
		var ease := 1.0 - pow(1.0 - progress, 3)
		var at := Vector2(640, 425).lerp(Vector2(240 + i * 200, 428), ease)
		at.y -= sin(progress * PI) * 50
		var size := Vector2(180, 226) * lerpf(0.24, 1.0, ease)
		HeroCard.draw(ci, Rect2(at - size * 0.5, size), _materials[i])
	_fx.draw(ci)
	Look.text_box(ci, Rect2(178, 174, 924, 56), "재료 카드 5장 복구!", 38, Look.GOLD)
	Look.text_box(ci, Rect2(178, 239, 924, 34), "합성 전의 영웅들이 전당으로 돌아왔습니다", 24, Look.CRYSTAL)
	Look.text_box(ci, Rect2(178, 574, 924, 40), "결과 영웅을 회수하고 재료 5장을 되살렸습니다.", 23, Look.INK_DIM)
	ui.button(ci, Rect2(420, 652, 440, 58), "복구한 카드 확인", "fusion:restored", restore_age >= 1.35, Look.GOLD, 26)


func _draw_result(ci: CanvasItem, ui: Ui) -> void:
	var result := Run.fusion_pending
	var unit := Roster.unit_by_id(String(result["unit"]))
	var tier := int(result["tier"])
	if reveal_age >= 0 and reveal_age < 1.35:
		var k := clampf(reveal_age / 1.1, 0, 1)
		var at := Vector2(640, 406).lerp(Vector2(350, 418), clampf((reveal_age - 0.95) / 0.4, 0, 1))
		SummonArt.seal(ci, at, 175 - 58 * k, reveal_age * 3, Look.GOLD)
		for i in range(_materials.size()):
			var angle := -PI * 0.5 + i * TAU / 5.0 + k * 2.3
			var p := at + Vector2.from_angle(angle) * lerpf(190, 10, k * k)
			var size := Vector2(112, 142) * (1 - k * 0.35)
			HeroCard.draw(ci, Rect2(p - size * 0.5, size), _materials[i])
		Look.text_center(ci, Vector2(640, 708), "다섯 영웅의 힘을 모으는 중", 26, Look.GOLD)
		return
	_fx.draw_back(ci)
	var element := String(unit.get("elem", "none"))
	Look.hero_card_panel(ci, Rect2(174, 188, 352, 424), element)
	SummonArt.seal(ci, Vector2(350, 418), 168, maxf(0, reveal_age) * 0.5, Balance.elem_color(element), 0.40)
	var pop := clampf((reveal_age - 1.35) / 0.3, 0, 1) if reveal_age >= 0 else 1.0
	Art.draw_unit_fit(ci, unit, Rect2(180, 208 + (1 - pop) * 45, 340, 342), Color(1, 1, 1, pop))
	Look.draw_rarity(ci, Vector2(350, 586), tier, 15)
	SummonArt.hero_info(ci, unit, tier, Rect2(606, 200, 530, 370), false)
	_fx.draw(ci)
	_fx.draw_flash(ci, Look.SCREEN)
	var ready := reveal_age < 0 or reveal_age > 1.7
	ui.button(ci, Rect2(606, 580, 530, 58), "영웅 받기", "fusion:accept", ready and not Ads.busy, Look.GOLD, 26)
	ui.reward_button(ci, Rect2(606, 654, 530, 52), "재료 되돌리기", "fusion:undo", ready and not Ads.busy, Look.PANEL_EDGE, 23)
