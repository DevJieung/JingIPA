extends RefCounted
class_name FormationView

## Filtering preserves the actual card indices used for deployment and saving.
const ELEMENTS := ["fire", "ice", "water", "elec", "none"]
const PAGE_SIZE := 4
var selected: int = -1
var bench_selected: int = -1
var page: int = 0
var element: String = "fire"
var note: String = ""
var post_rects: Array[Rect2] = []
var _pressed_post: int = -1
var _press_at := Vector2.ZERO
var _new_hero: Dictionary = {}
var _focused := false
var _side := Rect2()

func focus_latest() -> void:
	_focused = true
	var found := Run.latest_draw_location()
	selected = -1
	bench_selected = -1
	_new_hero = {}
	if found[0] == "field" and int(found[1]) >= 0:
		_new_hero = Run.heroes[int(found[1])]
	elif found[0] == "bench" and int(found[1]) >= 0:
		_new_hero = Run.bench[int(found[1])]
	if not _new_hero.is_empty():
		element = String(_new_hero["unit"].get("elem", "none"))
	elif not Run.bench.is_empty():
		element = String(Run.bench[0]["unit"].get("elem", "none"))
	page = 0

func is_new(hero: Dictionary) -> bool:
	return not _new_hero.is_empty() and is_same(hero, _new_hero)

func visible_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(Run.bench.size()):
		if String(Run.bench[i]["unit"].get("elem", "none")) == element:
			indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		var ha: Dictionary = Run.bench[a]
		var hb: Dictionary = Run.bench[b]
		if is_new(ha) != is_new(hb):
			return is_new(ha)
		if int(ha["tier"]) != int(hb["tier"]):
			return int(ha["tier"]) > int(hb["tier"])
		if int(ha.get("wave", 1)) != int(hb.get("wave", 1)):
			return int(ha.get("wave", 1)) > int(hb.get("wave", 1))
		return a < b)
	return indices

func draw(ci: CanvasItem, ui: Ui, box: Rect2, time: float) -> void:
	Run.ensure_posts()
	if not _focused:
		focus_latest()
	if selected >= Run.heroes.size():
		selected = -1
	if bench_selected >= Run.bench.size():
		bench_selected = -1
	var map_box := Rect2(box.position, Vector2(box.size.x - 342, box.size.y - 16))
	var scale := Vector2(map_box.size.x / 832.0, map_box.size.y / 644.0)
	var origin := map_box.position - Vector2(0, 100) * scale
	ci.draw_set_transform(origin, 0, scale)
	Battlefield.draw_map(ci, time)
	if selected >= 0:
		var hero: Dictionary = Run.heroes[selected]
		Battlefield.draw_range(ci, Balance.post_position(int(hero["post"])), float(Run.hero_stats(hero)["range"]), Look.GOLD)
	Look.px_panel(ci, Rect2(Balance.ARENA_CENTER - Vector2(48, 32), Vector2(96, 64)), Color("#253e48"), Look.CRYSTAL_DEEP, 0.2)
	for i in range(Run.lives):
		Look.draw_crystal(ci, Balance.ARENA_CENTER + Balance.crystal_slot(i), 9, true)
	for post in range(Balance.POST_SLOTS):
		var index := Run.hero_at_post(post)
		Battlefield.draw_post(ci, post, index >= 0 and index == selected, selected >= 0 or bench_selected >= 0)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	post_rects.clear()
	for post in range(Balance.POST_SLOTS):
		var p := origin + Balance.post_position(post) * scale
		# The central pair keeps separate name plates; smaller portraits free vertical room.
		if post in [4, 6]:
			p.x -= 7
		elif post in [5, 7]:
			p.x += 7
		var index := Run.hero_at_post(post)
		var hit := Rect2(p - Vector2(42, 65), Vector2(84, 84))
		post_rects.append(hit)
		ui.zone(hit, "post:%d" % post)
		if index >= 0:
			var hero: Dictionary = Run.heroes[index]
			Look.fill_round(ci, Rect2(p - Vector2(30, 49), Vector2(60, 46)), 4, Color(0.035, 0.075, 0.085, 0.76))
			Art.draw_deployed_fit(ci, hero["unit"], Rect2(p - Vector2(26, 46), Vector2(52, 42)))
			Look.draw_rarity_fit(ci, Rect2(p - Vector2(34, 65), Vector2(68, 16)), int(hero["tier"]), 4.0)
			Look.draw_elem(ci, p + Vector2(-29, -39), 7, String(hero["unit"].get("elem", "none")))
			Look.fill_round(ci, Rect2(p + Vector2(-42, -2), Vector2(84, 23)), 3, Color(0.03, 0.07, 0.09, 0.94))
			Look.text_center_fit(ci, p + Vector2(0, 9), Look.unit_name(hero["unit"]), 17, Look.INK, 80, 14)
			if is_new(hero):
				Look.fill_round(ci, Rect2(p + Vector2(9, -22), Vector2(34, 17)), 3, Look.GOLD)
				Look.text_center(ci, p + Vector2(26, -14), "NEW", 11, Look.BG_DEEP)
			if index == selected:
				var border := hit.grow(5)
				ci.draw_rect(border.grow(3), Look.BG_DEEP, false, 7)
				ci.draw_rect(border, Look.INK, false, 3)
				Look.draw_brackets(ci, border.grow(3), 17, Look.GOLD, 5)
				var badge := Rect2(border.end.x - 21, border.position.y + 17, 21, 21)
				Look.fill_round(ci, badge, 3, Look.GOLD)
				ci.draw_line(badge.position + Vector2(4, 10), badge.position + Vector2(9, 15), Look.BG_DEEP, 3)
				ci.draw_line(badge.position + Vector2(9, 15), badge.position + Vector2(17, 5), Look.BG_DEEP, 3)


	_side = Rect2(box.end.x - 326, box.position.y, 326, box.size.y)
	Look.material_panel(ci, _side, Look.PANEL, Look.PANEL_EDGE)
	var x := _side.position.x + 12
	var y := _side.position.y
	Look.text_left(ci, Vector2(x + 4, y + 23), "영웅 전당", 27, Look.GOLD)
	ui.button(ci, Rect2(x + 188, y + 7, 114, 32), "전당으로", "post:bench", selected >= 0 and Run.heroes.size() > 1, Look.PANEL_EDGE, 18)
	for i in range(ELEMENTS.size()):
		var el: String = ELEMENTS[i]
		var tab := Rect2(x + i * 61, y + 45, 58, 58)
		Look.fill_round(ci, tab, 3, Color("#34464b") if element == el else Color("#17272c"))
		Look.draw_elem(ci, tab.position + Vector2(29, 18), 8, el)
		var count := 0
		for h in Run.bench:
			if String(h["unit"].get("elem", "none")) == el:
				count += 1
		Look.text_center(ci, tab.position + Vector2(29, 42), str(count), 13, Look.INK_DIM)
		if element == el:
			ci.draw_line(tab.position + Vector2(3, 57), tab.end - Vector2(3, 1), Look.GOLD, 3)
		ui.zone(tab, "element:" + el)
	var indices := visible_indices()
	page = clampi(page, 0, maxi(0, (indices.size() - 1) / PAGE_SIZE))
	var card_h := (_side.size.y - 155) * 0.5
	for cell in range(PAGE_SIZE):
		var position := page * PAGE_SIZE + cell
		if position >= indices.size():
			break
		var index := indices[position]
		var reserve: Dictionary = Run.bench[index]
		var rect := Rect2(x + (cell % 2) * 155, y + 112 + (cell / 2) * (card_h + 7), 147, card_h)
		HeroCard.draw(ci, rect, reserve, bench_selected == index, "방금 뽑은 카드" if is_new(reserve) else "")
		ui.zone(rect, "reserve:%d" % index)
	if indices.is_empty():
		Look.text_center(ci, Vector2(x + 151, y + 218), "대기 중인 영웅이 없습니다", 19, Look.INK_DIM)
	if indices.size() > PAGE_SIZE:
		ui.button(ci, Rect2(x, _side.end.y - 32, 76, 28), "이전", "posts:prev", page > 0, Look.PANEL_EDGE, 18)
		Look.text_center(ci, Vector2(x + 151, _side.end.y - 18), "%d / %d" % [page + 1, ceili(float(indices.size()) / PAGE_SIZE)], 18, Look.INK_DIM)
		ui.button(ci, Rect2(x + 226, _side.end.y - 32, 76, 28), "다음", "posts:next", (page + 1) * PAGE_SIZE < indices.size(), Look.PANEL_EDGE, 18)
	if note != "":
		Look.fill_round(ci, Rect2(box.position.x, box.end.y - 26, map_box.size.x, 28), 3, Look.BG_DEEP)
		Look.text_center_fit(ci, Vector2(map_box.get_center().x, box.end.y - 12), note, 18, Look.CRYSTAL, map_box.size.x - 20, 14)

func post_at(p: Vector2) -> int:
	for i in range(post_rects.size()):
		if post_rects[i].has_point(p):
			return i
	return -1

func input(e: InputEvent, ui: Ui) -> bool:
	if not e is InputEventMouseButton:
		return false
	if e.pressed and _side.has_point(e.position) and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return tap("posts:prev" if e.button_index == MOUSE_BUTTON_WHEEL_UP else "posts:next")
	if e.button_index != MOUSE_BUTTON_LEFT:
		return false
	if e.pressed:
		_pressed_post = post_at(e.position)
		_press_at = e.position
		if _pressed_post >= 0:
			return true
		return tap(ui.hit(e.position))
	if _pressed_post >= 0:
		var target := post_at(e.position)
		var start := _pressed_post
		_pressed_post = -1
		if target < 0:
			return true
		if start != target and _press_at.distance_to(e.position) > 8.0:
			selected = Run.hero_at_post(start)
			bench_selected = -1
			if selected >= 0:
				_place(target)
		else:
			tap("post:%d" % target)
		return true
	return false

func _place(post: int) -> void:
	var changed := false
	if bench_selected >= 0 and bench_selected < Run.bench.size():
		var occupant := Run.hero_at_post(post)
		if not Run.can_deploy(Run.bench[bench_selected]["unit"], occupant):
			note = "같은 캐릭터가 이미 출전 중입니다."
			return
		if occupant >= 0:
			changed = Run.swap_field_bench(occupant, bench_selected)
		else:
			if Run.field_full():
				note = "교체할 전장 영웅을 누르세요."
				return
			changed = Run.bench_to_field(bench_selected)
			if changed:
				Run.move_hero(Run.heroes.size() - 1, post)
	elif selected >= 0:
		changed = Run.move_hero(selected, post)
	if changed:
		note = ""
		Sfx.play("button")
	selected = -1
	bench_selected = -1

func tap(id: String) -> bool:
	if id.begins_with("element:"):
		var el := id.get_slice(":", 1)
		if not ELEMENTS.has(el):
			return false
		element = el
		page = 0
		bench_selected = -1
		note = ""
		return true
	if id == "posts:prev" or id == "posts:next":
		page = clampi(page + (-1 if id == "posts:prev" else 1), 0, maxi(0, (visible_indices().size() - 1) / PAGE_SIZE))
		return true
	if id == "post:bench":
		if selected >= 0 and selected < Run.heroes.size() and Run.heroes.size() > 1:
			var hero: Dictionary = Run.heroes[selected]
			if Run.swap_field_bench(selected, -1):
				selected = -1
				bench_selected = -1
				element = String(hero["unit"].get("elem", "none"))
				page = maxi(0, visible_indices().find(Run.bench.size() - 1)) / PAGE_SIZE
				note = ""
		return true
	if id.begins_with("reserve:"):
		var index := int(id.get_slice(":", 1))
		if not visible_indices().has(index):
			return false
		if selected >= 0 and selected < Run.heroes.size():
			if Run.swap_field_bench(selected, index):
				selected = -1
				bench_selected = -1
				note = ""
				Sfx.play("button")
			else:
				note = "같은 캐릭터가 이미 출전 중입니다."
			return true
		bench_selected = index
		selected = -1
		note = ""
		return true
	if id.begins_with("post:"):
		var post := int(id.get_slice(":", 1))
		if post < 0 or post >= Balance.POST_SLOTS:
			return false
		var occupant := Run.hero_at_post(post)
		if selected == occupant and selected >= 0:
			selected = -1
		elif selected >= 0 or bench_selected >= 0:
			_place(post)
		else:
			selected = occupant
			note = ""
		return true
	return false
