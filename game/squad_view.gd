extends RefCounted
class_name SquadView

## Hellbound squad picker (2026-10-19, PLAN U4 / M10 · DLC D3): up to a squad of heroes from
## the collection — the heroes met, each at the best grade ever reached — then the endless
## waves. It stands over the title like the collection (CollectionView): element tabs, a
## 5 x 2 grid of hero cards, the squad strip with its count, Cancel and Start.
##
## Zones: hell:pick:<id> (a card or a strip slot; toggles), hell:start, hell:close,
## hell:element:<el>, hell:page:-1 / hell:page:1 (only when one element holds more than a
## page). The host (the title, LB2b) routes input(event, ui) and draw(ci, ui), and passes
## Main to open(); Start calls main.start_hellbound(ids) once main.hellbound_ready().
##
## Data: pool() asks Arena.hellbound_pool() when the run offers it (LA3) and otherwise reads
## the codex itself (Save.seen_units + Save.best_of). Swapping the source is that one function.
##
## Look: the collection's sheet with the mode's own ember (StoreView.HELL_EMBER) on the rim
## and in the gate mark, so the screen reads as the mode the shop row named.

const ELEMENTS := ["water", "fire", "ice", "elec", "none"]
const PAGE_SIZE := 10
const SHEET := Rect2(76, 76, 1128, 672)
const CARD := Vector2(208, 176)
const SLOT := 74.0
## How long the count glows after a pick past the limit was refused (seconds).
const REFUSE_SECONDS := 0.9

var opened := false
var main: Node = null
var element := "water"
var page := 0
## The chosen ids, in the order they were picked (the order the squad takes the field).
var picks: Array[String] = []
var started := false
var _refused_at := -10.0


## Open over the host. The last squad (Save.hell_squad, LA3) comes back already picked,
## as far as the pool still has those heroes.
func open(host_main: Node = null) -> void:
	if host_main != null:
		main = host_main
	opened = true
	started = false
	page = 0
	_refused_at = -10.0
	picks.clear()
	var ids := {}
	for entry in pool():
		ids[String(entry["unit"]["id"])] = String(entry["unit"].get("elem", "none"))
	var last: Variant = Save.get("hell_squad")
	if last is Array:
		for id in last:
			if ids.has(String(id)) and not picks.has(String(id)) and picks.size() < squad_max():
				picks.append(String(id))
	element = String(ids.get(picks[0], "water")) if not picks.is_empty() else "water"
	if picks.is_empty():
		for el in ELEMENTS:
			if ids.values().has(el):
				element = el
				break


func close() -> void:
	opened = false


## The heroes Hellbound may take, [{unit: Dictionary, tier: int}], each at the best grade
## the collection remembers (a hero met before grades were kept counts as 1-star).
func pool() -> Array:
	var out: Array = []
	if Arena.has_method("hellbound_pool"):
		for entry in Arena.call("hellbound_pool"):
			if not entry is Dictionary:
				continue
			var unit: Variant = entry.get("unit")
			if unit is String or unit is StringName:
				unit = Roster.unit_by_id(String(unit))
			if unit is Dictionary and not (unit as Dictionary).is_empty():
				out.append({"unit": unit, "tier": clampi(int(entry.get("tier", 1)), 0, Balance.TIER_MAX)})
		return out
	for unit in Roster.UNITS:
		var id := String(unit["id"])
		if Save.seen_units.has(id):
			var best := Save.best_of(id)
			out.append({"unit": unit, "tier": clampi(best if best >= 0 else Rite.tier_of(1), 0, Balance.TIER_MAX)})
	return out


## The most heroes one squad takes (Balance.ARENA_HELL_SQUAD once LA3 adds it; the field's
## limit until then).
static func squad_max() -> int:
	var table: Script = Balance
	var value: Variant = table.get("ARENA_HELL_SQUAD")
	return maxi(1, int(value) if value != null else Balance.ARENA_HERO_LIMIT)


## Start answers only when the run can begin a Hellbound run (Main.hellbound_ready(), LB2b /
## LA3) — never a lit button that leaves the picker stuck.
func can_start() -> bool:
	return not picks.is_empty() and not started and main != null and main.has_method("hellbound_ready") \
		and bool(main.hellbound_ready()) and main.has_method("start_hellbound")


func input(event: InputEvent, ui: Ui) -> bool:
	if not opened:
		return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := ui.hit(event.position)
		if id.begins_with("hell:"):
			action(id)
			Sfx.play("button")
	return true


func action(id: String) -> bool:
	if not id.begins_with("hell:"):
		return false
	var parts := id.split(":")
	match parts[1]:
		"close":
			close()
		"start":
			if can_start():
				started = true
				main.start_hellbound(picks.duplicate())
		"pick":
			if parts.size() > 2:
				toggle(parts[2])
		"element":
			if parts.size() > 2 and parts[2] in ELEMENTS:
				element = parts[2]
				page = 0
		"page":
			if parts.size() > 2:
				page = maxi(0, page + int(parts[2]))
	return true


## Pick or drop one hero. Past the limit the pick is refused and the count says why.
func toggle(id: String) -> void:
	if picks.has(id):
		picks.erase(id)
	elif picks.size() < squad_max():
		picks.append(id)
	else:
		_refused_at = Time.get_ticks_msec() * 0.001


func _element_entries(entries: Array, el: String) -> Array:
	var out: Array = []
	for entry in entries:
		if String(entry["unit"].get("elem", "none")) == el:
			out.append(entry)
	# By name inside a tab, as in the collection: a grade belongs to one card, not a hero.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_name := Look.unit_name(a["unit"])
		var b_name := Look.unit_name(b["unit"])
		return a_name < b_name if a_name != b_name else String(a["unit"]["id"]) < String(b["unit"]["id"]))
	return out


func draw(ci: CanvasItem, ui: Ui) -> void:
	if not opened:
		return
	var ember := StoreView.HELL_EMBER
	var limit := squad_max()
	var entries := pool()
	var by_id := {}
	for entry in entries:
		by_id[String(entry["unit"]["id"])] = entry
	for i in range(picks.size() - 1, -1, -1):
		if not by_id.has(picks[i]):
			picks.remove_at(i)
	ci.draw_rect(Look.SCREEN, Look.SHADE)
	ui.zone(Look.SCREEN, "hell:none")
	Look.sheet(ci, SHEET, ember.lerp(Look.STEEL, 0.35))
	Look.gradient_rect(ci, Rect2(SHEET.position + Vector2(6, 4), Vector2(SHEET.size.x - 12, 132)), Color(ember, 0.11), Color(ember, 0.0), true)
	# Head: the gate mark, the mode's name and what it is (hell.*), the best so far.
	var x0 := SHEET.position.x + 28.0
	StoreView.draw_fact_glyph(ci, Vector2(x0 + 22, SHEET.position.y + 44), "hell", ember.lerp(Look.GOLD, 0.45), 2.1)
	var title_x := x0 + 58.0
	var best: Variant = Save.get("hell_best_wave")
	var best_w := 0.0
	if best != null and int(best) > 0:
		var record := Arena.label("hell.best") % int(best)
		best_w = Look.text_width(record, 20) + 24.0
		Look.text_right(ci, Vector2(SHEET.end.x - 28, SHEET.position.y + 44), record, 20, Look.INK_DIM)
	Look.text_box(ci, Rect2(title_x, SHEET.position.y + 22, SHEET.end.x - 28 - best_w - title_x, 44), Arena.label("hell.title"), Look.TYPE_TITLE, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(ci, Rect2(x0, SHEET.position.y + 72, SHEET.size.x - 56, 28), Arena.label("hell.desc"), 19, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	# Element tabs, each with the number already picked from it.
	for index in range(ELEMENTS.size()):
		var el: String = ELEMENTS[index]
		var rect := Rect2(x0 + index * 216.0, SHEET.position.y + 112, 208, 46)
		ui.tab(ci, rect, Balance.elem_ko(el), "hell:element:" + el, el == element, 22)
		Look.draw_elem(ci, rect.position + Vector2(24, 23), 12, el)
		var chosen := 0
		for id in picks:
			if String(by_id[id]["unit"].get("elem", "none")) == el:
				chosen += 1
		if chosen > 0:
			var badge := rect.position + Vector2(rect.size.x - 22, 23)
			ci.draw_circle(badge, 11.0, Look.GOLD, true, -1, true)
			Look.text_center(ci, badge, str(chosen), 15, Look.BG_DEEP)
	# The grid.
	var grid_top := SHEET.position.y + 172.0
	var list := _element_entries(entries, element)
	page = clampi(page, 0, maxi(0, (list.size() - 1) / PAGE_SIZE))
	var full := picks.size() >= limit
	for cell in range(PAGE_SIZE):
		var index := page * PAGE_SIZE + cell
		if index >= list.size():
			break
		var entry: Dictionary = list[index]
		var id := String(entry["unit"]["id"])
		var rect := Rect2(x0 + (cell % 5) * 216.0, grid_top + (cell / 5) * (CARD.y + 8.0), CARD.x, CARD.y)
		var chosen := picks.has(id)
		ui.zone(rect, "hell:pick:" + id)
		HeroCard.draw(ci, rect, {"unit": entry["unit"], "tier": int(entry["tier"])}, chosen)
		if full and not chosen:
			Look.fill_round(ci, rect, 5.6, Color(Look.BG_DEEP, 0.50))
	var grid_mid := Vector2(SHEET.get_center().x, grid_top + CARD.y + 4.0)
	if entries.is_empty():
		Look.wrap_text(ci, Arena.label("hell.empty"), Rect2(grid_mid.x - 420, grid_mid.y - 36, 840, 72), 23, Look.INK_DIM)
	elif list.is_empty():
		Look.text_center(ci, grid_mid, "이 속성의 영웅을 아직 만나지 못했습니다.", 22, Look.INK_DIM)
	if list.size() > PAGE_SIZE:
		var pages := ceili(list.size() / float(PAGE_SIZE))
		ui.button(ci, Rect2(SHEET.end.x - 252, SHEET.position.y + 72, 64, 30), "<", "hell:page:-1", page > 0, Look.PANEL_EDGE, 18)
		Look.text_center(ci, Vector2(SHEET.end.x - 152, SHEET.position.y + 87), "%d / %d" % [page + 1, pages], 17, Look.INK_DIM)
		ui.button(ci, Rect2(SHEET.end.x - 92, SHEET.position.y + 72, 64, 30), ">", "hell:page:1", page + 1 < pages, Look.PANEL_EDGE, 18)
	# The squad strip: the picks in order, then the open slots; a picked slot drops its hero.
	var strip_y := SHEET.end.y - 26.0 - SLOT
	var label_y := strip_y - 20.0
	var refused := Time.get_ticks_msec() * 0.001 - _refused_at < REFUSE_SECONDS
	var count := Arena.label("hell.pick") % [picks.size(), limit]
	Look.text_left(ci, Vector2(x0, label_y), count, 20, Look.WARN if refused else Look.GOLD)
	if refused:
		Look.text_left(ci, Vector2(x0 + Look.text_width(count, 20) + 16.0, label_y), "최대 %d명까지 고를 수 있습니다." % limit, 16, Look.WARN)
	for slot in range(limit):
		var rect := Rect2(x0 + slot * (SLOT + 10.0), strip_y, SLOT, SLOT)
		if slot < picks.size():
			var entry: Dictionary = by_id[picks[slot]]
			var unit: Dictionary = entry["unit"]
			var tier := int(entry["tier"])
			ui.zone(rect, "hell:pick:" + picks[slot])
			Look.fill_round(ci, rect, 5, Look.hero_card_edge(String(unit.get("elem", "none"))))
			Look.fill_round(ci, rect.grow(-1.5), 4, Look.hero_card_face(String(unit.get("elem", "none"))))
			Art.draw_unit_fit(ci, unit, Rect2(rect.position + Vector2(6, 4), Vector2(SLOT - 12, SLOT - 22)), Color.WHITE, tier)
			Look.draw_rarity_fit(ci, Rect2(rect.position.x + 4, rect.end.y - 18, SLOT - 8, 14), tier, 4.2)
			Look.draw_elem(ci, rect.position + Vector2(10, 10), 6, String(unit.get("elem", "none")))
		else:
			Look.fill_round(ci, rect, 5, Color(Look.BG_DEEP, 0.55))
			_dashed(ci, rect.grow(-2), Color(Look.STEEL_DIM, 0.85))
			Look.text_center(ci, rect.get_center(), str(slot + 1), 18, Look.STEEL_DIM)
	# Cancel · Start.
	var start := Rect2(SHEET.end.x - 28 - 228, strip_y + 8, 228, 58)
	var cancel := Rect2(start.position.x - 12 - 196, start.position.y, 196, 58)
	ui.button(ci, cancel, "취소", "hell:close", true, Look.PANEL_EDGE, Look.TYPE_BUTTON_2)
	ui.button(ci, start, Arena.label("hell.start"), "hell:start", can_start(), Look.GOLD, Look.TYPE_BUTTON)
	# Without the DLC the mode stays shut, and the sheet says what opens it.
	if Arena.has_method("dlc") and not bool(Arena.call("dlc")):
		Look.text_box(ci, Rect2(cancel.position.x, label_y - 13, start.end.x - cancel.position.x, 26), Arena.label("hell.locked"), 16, Look.WARN, HORIZONTAL_ALIGNMENT_RIGHT)


static func _dashed(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	for side in [[rect.position, Vector2(rect.end.x, rect.position.y)], [Vector2(rect.position.x, rect.end.y), rect.end],
			[rect.position, Vector2(rect.position.x, rect.end.y)], [Vector2(rect.end.x, rect.position.y), rect.end]]:
		ci.draw_dashed_line(side[0], side[1], color, 1.2, 5.0, true, true)
