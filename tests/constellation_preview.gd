extends Harness

## D2 (feedback 2026-10-19, F2/F3): the constellation node language drawn on its own,
## before it is wired into the level-up popup. Staged picks (no run, no simulator) over a
## battle picture under the popup's shade; every surface is drawn by game/constellation.gd.
##
##   godot --disable-vsync --path . --resolution 96x60 res://tests/constellation_preview.tscn -- \
##       --film 1280x800 --out build/feedback-2026-10-19/D2/1280x800 [--locales ko,en] \
##       [--only map,cards,seals,motion]
##
## Each picture leaves <name>.json with the drawn text and every touch zone. It also checks
## that Constellation.states() answers Talents.state for every node, that no two nodes of a
## map share a spot or a row with a line, and that the map's node zones are big enough
## (the detail card's relation rows are list rows and are counted apart).

class Board extends Node2D:
	var painter: Callable
	var ui := Ui.new()
	func _draw() -> void:
		ui.begin()
		if painter.is_valid():
			painter.call(self)

## The real popup drawn by the real ArenaTalentView on an ArenaScreen that does nothing
## else (no world, no input, no clock): its state comes from the view's `preview` hook.
class PreviewScreen extends ArenaScreen:
	var backdrop: Texture2D
	var paint_hold := false
	var banner_sim = null
	func _ready() -> void:
		set_process(false)
	func _process(_dt: float) -> void:
		pass
	func _input(_e: InputEvent) -> void:
		pass
	func _draw() -> void:
		ui.begin()
		if backdrop != null:
			draw_texture_rect(backdrop, Look.SCREEN, false)
		if banner_sim != null:
			talent_view._draw_pick_banner(banner_sim)
		elif paint_hold:
			talent_view._draw_pick_hold()
		else:
			talent_view._draw_talent()

## Enough of a simulator for the banner row's placement.
class BannerSim extends RefCounted:
	var boss_spawned := false
	var boss_warned := false
	var monsters: Array = []

const CHART := Rect2(16, 72, 1248, 718)
var film: SubViewport
var board: Board
var out_dir := ""
var locale := "ko"
var backdrop: Texture2D
var clock := 0.0
var settled := true
var _sets: PackedStringArray = []
var _index: Array = []

## A run in the middle: some constellations grown, a few stars full, three on offer.
const MID := {"fury_edge": 3, "fury_blaze": 1, "fury_over": 1, "tempo_quick": 2, "tempo_feet": 1,
	"prec_aim": 1, "elem_fire": 2, "st_flame": 1, "st_inferno": 1, "elem_elec": 1, "arms_bow": 1,
	"arms_air": 1, "guard_hp": 1, "guard_mire": 2, "star_meteor": 1, "star_quick": 1, "fate_gold": 1,
	"fate_reroll": 1}
const MID_OFFER := ["prec_scope", "guard_bul", "fury_wrath"]
## Late in a run: most roots and many second stars, two capstones.
const LATE := {"fury_edge": 3, "fury_blaze": 2, "fury_over": 1, "fury_giant": 1, "fury_wrath": 1, "fury_heavy": 1,
	"tempo_quick": 4, "tempo_rush": 2, "tempo_rage": 1, "tempo_feet": 2, "prec_aim": 4, "prec_deadly": 2,
	"prec_scope": 1, "elem_fire": 2, "elem_ice": 1, "st_flame": 1, "st_inferno": 1, "st_wild": 1, "st_frost": 1,
	"st_reson": 1, "elem_elec": 2, "st_shock": 1, "arms_bow": 2, "arms_air": 2, "arms_gun": 1, "arms_pierce": 1,
	"guard_hp": 3, "guard_bul": 1, "guard_mire": 3, "guard_now": 1, "star_meteor": 2, "star_quick": 1,
	"star_wide": 1, "star_more_blast": 1, "fate_gold": 3, "fate_midas": 1, "fate_reroll": 2, "fate_eye": 1,
	"fate_insight": 1}
const LATE_OFFER := ["st_chain", "tempo_storm", "fate_joker"]


func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", "build/feedback-2026-10-19/D2/1280x800")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_sets = arg("--only", "map,cards,seals,motion,popup,perf").split(",", false)
	_open_film()
	board = Board.new()
	if film != null: film.add_child(board)
	else: add_child(board)
	await frames(2)
	_check_states()
	_check_layout()
	var saved_locale := I18n.locale
	for code in arg("--locales", "ko,en").split(",", false):
		locale = code
		I18n.set_locale(code)
		backdrop = _picture("build/ui-cycle-2026-10-17/after/1280x800/%s_hud_air_battle.png" % code)
		if "map" in _sets: await _cycle_map()
		if "cards" in _sets: await _cycle_cards()
		if "seals" in _sets: await _cycle_seals()
		if "motion" in _sets: await _cycle_motion()
		if "popup" in _sets: await _cycle_popup()
	if "perf" in _sets: await _cycle_perf()
	I18n.set_locale(saved_locale)
	var file := FileAccess.open(out_dir + "/index.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_index, "  ") + "\n")
	file = null
	finish("Constellation preview")


# --------------------------------------------------------------------------- #
# Staging
# --------------------------------------------------------------------------- #
## Owned passives and stat levels that a set of picks implies (as ArenaRun.pick_talent).
func _implied(taken: Dictionary) -> Array:
	var passives: Array = []
	var levels := {}
	for id in taken:
		var node := Talents.by_id(String(id))
		for raw in Talents.effect_keys(node):
			var key := String(raw)
			if key.begins_with("grant_") and not passives.has(key.trim_prefix("grant_")):
				passives.append(key.trim_prefix("grant_"))
			elif key.begins_with("lv_"):
				var up := key.trim_prefix("lv_")
				var cap := int(Balance.upgrade_by_id(up).get("cap", 0))
				var next := int(levels.get(up, 0)) + int(node[key]) * int(taken[id])
				levels[up] = next if cap <= 0 else mini(next, cap)
	return [passives, levels]


func _states(taken: Dictionary) -> Dictionary:
	var implied := _implied(taken)
	return Constellation.states(taken, implied[0], implied[1])


func _picture(path: String) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://" + path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _shade(ci: CanvasItem) -> void:
	if backdrop != null:
		ci.draw_texture_rect(backdrop, Look.SCREEN, false)
	ci.draw_rect(Look.SCREEN, Look.SHADE)


# --------------------------------------------------------------------------- #
# Checks
# --------------------------------------------------------------------------- #
func _check_states() -> void:
	var probe = Constellation.states({}, [], {})
	check(probe is Dictionary and (probe as Dictionary).size() == Balance.TALENTS.size(), "Constellation did not load (states() gave no answer)")
	if not (probe is Dictionary):
		return
	for taken in [{}, MID, LATE]:
		var implied := _implied(taken)
		var all := Constellation.states(taken, implied[0], implied[1])
		var bad := 0
		for node in Balance.TALENTS:
			var id := String(node["id"])
			if String(all.get(id, "")) != Talents.state(id, taken, implied[0], implied[1]):
				bad += 1
		check(bad == 0, "states() differs from Talents.state on %d nodes" % bad)


func _check_layout() -> void:
	for group in Balance.TALENT_GROUP_ORDER:
		var layout := Constellation.map(String(group))
		var nodes: Dictionary = layout["nodes"]
		var spots := {}
		for id in nodes:
			var at: Vector2 = nodes[id]
			var key := "%.2f,%.0f" % [at.x, at.y]
			check(not spots.has(key), "%s: %s and %s share a spot" % [group, id, spots.get(key, "")])
			spots[key] = id
			check(int(at.y) == Talents.graph_depth(String(id)), "%s: %s is not on its depth row" % [group, id])
		for edge in layout["edges"]:
			var a: Vector2 = nodes[edge[0]]
			var b: Vector2 = nodes[edge[1]]
			check(b.y > a.y, "%s: link %s -> %s does not climb" % [group, edge[0], edge[1]])
		print("layout %s: width %.1f rows %d edges %d" % [group, float(layout["width"]), int(layout["rows"]), (layout["edges"] as Array).size()])


func _check_zones(name: String, min_side: float) -> void:
	var small := 0
	var nodes := 0
	var rows := 0
	for zone in board.ui.zones:
		if String(zone["id"]).begins_with("talent:node:"):
			var r: Rect2 = zone["rect"]
			if r.position.x >= CHART.end.x - 440.0 and r.size.y < 40.0:
				rows += 1
				continue
			nodes += 1
			if minf(r.size.x, r.size.y) < min_side:
				small += 1
	check(small == 0, "%s: %d map node zones under %.0f px" % [name, small, min_side])
	print("%s: %d node zones (+%d detail rows), %d under %.0f px" % [name, nodes, rows, small, min_side])


# --------------------------------------------------------------------------- #
# Sets
# --------------------------------------------------------------------------- #
func _chart(ci: Board, taken: Dictionary, offer: Array, focus: String, selected: String, button: String, level: int) -> void:
	_shade(ci)
	Constellation.draw_chart(ci, ci.ui, CHART, taken, _states(taken), offer, focus, selected, clock,
		{"settled": settled, "level": level})
	ci.ui.button(ci, Constellation.chart_button_rect(CHART), I18n.t(button), "close", true, Look.GOLD, Look.TYPE_BUTTON_2)


func _cycle_map() -> void:
	settled = true
	board.painter = func(ci: Board) -> void: _chart(ci, {}, [], "", "", "arena.resume", 1)
	await _capture("map_overview_empty")
	board.painter = func(ci: Board) -> void: _chart(ci, MID, MID_OFFER, "", "", "arena.map_back", 9)
	await _capture("map_overview_offer")
	_check_zones(locale + " overview", 44.0)
	board.painter = func(ci: Board) -> void: _chart(ci, LATE, [], "", "", "arena.resume", 24)
	await _capture("map_overview_late")
	board.painter = func(ci: Board) -> void: _chart(ci, MID, MID_OFFER, "fury", "", "arena.map_back", 9)
	await _capture("map_focus_fury_offer")
	_check_zones(locale + " focus fury", 60.0)
	board.painter = func(ci: Board) -> void: _chart(ci, MID, MID_OFFER, "element", "st_wild", "arena.map_back", 9)
	await _capture("map_focus_element_node")
	_check_zones(locale + " focus element", 60.0)
	board.painter = func(ci: Board) -> void: _chart(ci, LATE, LATE_OFFER, "arms", "arms_split", "arena.map_back", 24)
	await _capture("map_focus_arms_late")
	board.painter = func(ci: Board) -> void: _chart(ci, LATE, [], "fortune", "fate_joker", "arena.resume", 24)
	await _capture("map_focus_fortune_late")
	board.painter = func(ci: Board) -> void: _chart(ci, {}, [], "starlight", "star_bless", "arena.resume", 1)
	await _capture("map_focus_starlight_empty")


func _cards(ci: Board, taken: Dictionary, offer: Array, ages: Array, arm: float, armed: bool, armed_age: float, appear: float) -> void:
	_shade(ci)
	var title := I18n.t("arena.levelup")
	Look.text_center(ci, Vector2(640, 112), title, Look.TYPE_TITLE, Look.GOLD)
	var node_states := _states(taken)
	var size := ArenaTalentView.CARD
	var gap := ArenaTalentView.CARD_GAP
	var x0 := ArenaTalentView.CENTER_X - (size.x * offer.size() + gap * (offer.size() - 1)) * 0.5
	for n in range(offer.size()):
		var rect := Rect2(x0 + n * (size.x + gap), ArenaTalentView.CARD_Y, size.x, size.y)
		var age := float(ages[n]) if n < ages.size() else 9.0
		if age < 0.0:
			continue
		Constellation.draw_offer_card(ci, rect, String(offer[n]), taken, node_states, clock, {"settled": settled, "age": age})
		Constellation.draw_pick_button(ci, ci.ui, Rect2(rect.position.x + 20, rect.end.y - 66, rect.size.x - 40, 52), String(offer[n]),
			I18n.t("arena.pick"), arm, armed, clock, {"appear": appear, "armed_age": armed_age})


func _cycle_cards() -> void:
	settled = true
	board.painter = func(ci: Board) -> void: _cards(ci, MID, MID_OFFER, [9, 9, 9], 1.0, true, 9.0, 1.0)
	await _capture("cards_mid")
	board.painter = func(ci: Board) -> void: _cards(ci, LATE, LATE_OFFER, [9, 9, 9], 1.0, true, 9.0, 1.0)
	await _capture("cards_late")
	board.painter = func(ci: Board) -> void: _cards(ci, {}, ["fate_ascend", "elem_water", "arms_whip"], [9, 9, 9], 1.0, true, 9.0, 1.0)
	await _capture("cards_first")
	board.painter = func(ci: Board) -> void: _cards(ci, MID, MID_OFFER, [9, 9, 9], 0.45, false, 9.0, 1.0)
	await _capture("cards_arming")


func _seals(ci: Board) -> void:
	ci.draw_rect(Look.SCREEN, Color("#0a1520"))
	var states := ["open", "joined", "full", "locked", "closed"]
	var samples := ["fury_edge", "tempo_rush", "st_wild"]
	var y := 90.0
	Look.text_left(ci, Vector2(40, 40), "tier 1 / 2 / 3  x  open · joined · full · locked · closed · offered · selected", 18, Look.INK_DIM)
	for row in range(3):
		var id := String(samples[row])
		for n in range(7):
			var state := String(states[mini(n, 4)]) if n < 5 else ("open" if n == 5 else "joined")
			var c := Vector2(90 + n * 150, y + row * 150)
			Constellation.draw_seal(ci, c, 34.0, id, state, 1, clock, {"settled": settled, "offered": n == 5, "selected": n == 6})
	# Sizes: the overview (17), the focus map (30), the card (44).
	for n in range(3):
		var r: float = [17.0, 30.0, 44.0][n]
		var c := Vector2(1130, 120 + n * 150)
		Constellation.draw_seal(ci, c, r, "fury_wrath", "joined", 1, clock, {"settled": settled})
	# The emblems in their colours.
	for n in range(Balance.TALENT_GROUP_ORDER.size()):
		var group := String(Balance.TALENT_GROUP_ORDER[n])
		var c := Vector2(90 + n * 140, 600)
		Constellation.draw_emblem(ci, group, c, 40.0, Constellation.group_color(group))
		Constellation.draw_emblem(ci, group, c + Vector2(0, 100), 22.0, Color.WHITE)
		Look.text_center(ci, c + Vector2(0, 140), Constellation.group_name(group), 16, Constellation.group_color(group))


func _all_seals(ci: Board, lit: bool) -> void:
	ci.draw_rect(Look.SCREEN, Color("#0a1520"))
	var n := 0
	for group in Balance.TALENT_GROUP_ORDER:
		for node in Balance.TALENTS:
			if String(node["group"]) != String(group):
				continue
			var id := String(node["id"])
			var c := Vector2(60 + (n % 12) * 103, 64 + (n / 12) * 112)
			Constellation.draw_seal(ci, c, 27.0, id, "joined" if lit else "open", 1, clock, {"settled": true})
			Look.text_box(ci, Rect2(c.x - 50, c.y + 38, 100, 18), I18n.t(String(node["ko"])), 13, Look.INK_DIM)
			n += 1


## Before / after for every node: the medallion the level-up card draws today (vector glyph
## in the node's tint) beside the new seal (lit).
func _compare(ci: Board) -> void:
	ci.draw_rect(Look.SCREEN, Color("#0a1520"))
	var n := 0
	for group in Balance.TALENT_GROUP_ORDER:
		for node in Balance.TALENTS:
			if String(node["group"]) != String(group):
				continue
			var id := String(node["id"])
			var cell := Vector2(14 + (n % 12) * 105, 12 + (n / 12) * 112)
			var tint := Color(String(node.get("tint", "#edc879")))
			var old_c := cell + Vector2(26, 34)
			ci.draw_circle(old_c, 24, Color(Look.BG_DEEP, 0.60), true, -1, true)
			ci.draw_arc(old_c, 24, 0, TAU, 32, Color(tint, 0.55), 1.2, true)
			Look.draw_passive_icon(ci, old_c, 16, node, tint)
			Constellation.draw_seal(ci, cell + Vector2(76, 34), 19.0, id, "joined", 1, clock, {"settled": true})
			Look.text_box(ci, Rect2(cell.x, cell.y + 70, 102, 18), I18n.t(String(node["ko"])), 13, Look.INK_DIM)
			n += 1


func _cycle_seals() -> void:
	settled = true
	board.painter = func(ci: Board) -> void: _compare(ci)
	await _capture("seals_before_after")
	board.painter = func(ci: Board) -> void: _seals(ci)
	await _capture("seals_states")
	board.painter = func(ci: Board) -> void: _all_seals(ci, true)
	await _capture("seals_all_lit")
	board.painter = func(ci: Board) -> void: _all_seals(ci, false)
	await _capture("seals_all_open")


## The card entrance and the button's arming as consecutive frames (0.05 s apart).
func _cycle_motion() -> void:
	settled = false
	for f in range(18):
		var age := f * 0.05
		clock = 10.0 + age
		var ages := [age, age - 0.07, age - 0.14]
		var arm := clampf((age - 0.55) / 0.30, 0.0, 1.0)
		var appear := clampf((age - 0.45) / 0.15, 0.0, 1.0)
		board.painter = func(ci: Board) -> void: _cards(ci, MID, MID_OFFER, ages, arm, age >= 0.85, age - 0.85, appear)
		await _capture("motion_card_%02d" % f)
	# The pick: the right card's capstone flies into its constellation (0.45 s).
	for f in range(11):
		var age := f * 0.045
		clock = 15.0 + age
		board.painter = func(ci: Board) -> void:
			_shade(ci)
			var rects: Array = []
			for n in range(3):
				rects.append(Rect2(32 + n * 316, 196, 296, 470))
			Constellation.draw_pick_flourish(ci, rects, MID_OFFER, "fury_wrath", MID, _states(MID), age, clock)
		await _capture("motion_pick_%02d" % f)
	for f in range(8):
		clock = 20.0 + f * 0.1
		board.painter = func(ci: Board) -> void: _chart(ci, MID, MID_OFFER, "element", "st_wild", "arena.map_back", 9)
		await _capture("motion_map_%02d" % f)
	settled = true


## What one frame of the map costs to record (the GDScript side of drawing), averaged
## over animated frames: the overview with an offer, a focused constellation, the cards.
func _cycle_perf() -> void:
	settled = false
	var implied := _implied(LATE)
	var cases := {
		"overview": func(ci: Board) -> void: Constellation.draw_chart(ci, ci.ui, CHART, LATE, Constellation.states(LATE, implied[0], implied[1]), LATE_OFFER, "", "", clock, {"level": 24}),
		"focus": func(ci: Board) -> void: Constellation.draw_chart(ci, ci.ui, CHART, LATE, Constellation.states(LATE, implied[0], implied[1]), LATE_OFFER, "element", "st_chain", clock, {"level": 24}),
		"cards": func(ci: Board) -> void:
			var node_states := Constellation.states(MID, _implied(MID)[0], _implied(MID)[1])
			for n in range(3):
				var rect := Rect2(32 + n * 316, 196, 296, 470)
				Constellation.draw_offer_card(ci, rect, String(MID_OFFER[n]), MID, node_states, clock, {"age": 9.0})
				Constellation.draw_pick_button(ci, ci.ui, Rect2(rect.position.x + 20, rect.end.y - 66, rect.size.x - 40, 52), String(MID_OFFER[n]), "x", 1.0, true, clock),
	}
	for name in cases:
		var acc := {"total": 0, "count": 0}
		var draw: Callable = cases[name]
		board.painter = func(ci: Board) -> void:
			var t0 := Time.get_ticks_usec()
			draw.call(ci)
			acc["total"] = int(acc["total"]) + Time.get_ticks_usec() - t0
			acc["count"] = int(acc["count"]) + 1
		for f in range(52):
			if f == 12:
				acc["total"] = 0
				acc["count"] = 0

			clock = 30.0 + f / 30.0
			board.queue_redraw()
			await frames(1)
		print("perf %s: %.2f ms per frame (%d frames)" % [name, float(acc["total"]) / maxf(1.0, float(acc["count"])) / 1000.0, int(acc["count"])])

	settled = true


# --------------------------------------------------------------------------- #
# The popup, drawn by game/arena_talent_view.gd on a do-nothing ArenaScreen
# --------------------------------------------------------------------------- #
var _popup: PreviewScreen

func _stage_run(taken: Dictionary, offer: Array, level: int, pending: int, xp: float) -> void:
	var implied := _implied(taken)
	Arena.talents = taken.duplicate()
	Arena.owned_passives.assign(implied[0])
	Arena.levels = (implied[1] as Dictionary).duplicate()
	Arena.talent_offer.assign(offer)
	Arena.level = level
	Arena.xp = xp
	Arena.pending_levels = pending
	Arena.modal = "talent"

func _popup_shot(name: String, state: Dictionary) -> void:
	_popup.talent_view.preview = state
	_popup.paint_hold = bool(state.get("paint_hold", false))
	_popup.banner_sim = state.get("banner_sim", null)
	_popup.t = float(state.get("t", 30.0))
	_popup.queue_redraw()
	await _capture_on(_popup, name)

func _cycle_popup() -> void:
	var saved := {"talents": Arena.talents.duplicate(), "offer": Arena.talent_offer.duplicate(), "level": Arena.level,
		"xp": Arena.xp, "pending": Arena.pending_levels, "modal": Arena.modal, "owned": Arena.owned_passives.duplicate(),
		"levels": Arena.levels.duplicate()}
	_popup = PreviewScreen.new()
	_popup.backdrop = backdrop
	if film != null: film.add_child(_popup)
	else: add_child(_popup)
	board.visible = false
	_stage_run(MID, MID_OFFER, 9, 3, 6.0)
	await _popup_shot("popup_settled", {"settled": true})
	await _popup_shot("popup_pressed", {"settled": false, "entrance_age": 9.0, "armed": true, "arm_progress": 1.0, "pressed": "talent:pick:guard_bul"})
	await _popup_shot("popup_arming", {"settled": false, "entrance_age": 0.78, "armed": false, "arm_progress": 0.78 / 0.90})
	# The entrance, 0.05 s apart, to the armed frame.
	for f in range(21):
		var age := f * 0.05
		await _popup_shot("motion_popup_%02d" % f, {"settled": false, "entrance_age": age, "armed": age >= 0.90,
			"arm_progress": age / 0.90, "t": 40.0 + age})
	# A following offer: the cards only.
	_stage_run(MID, ["tempo_rush", "elem_ice", "fate_insight"], 10, 2, 0.0)
	for f in range(11):
		var age := f * 0.05
		await _popup_shot("motion_follow_%02d" % f, {"settled": false, "followup": true, "entrance_age": age,
			"armed": age >= 0.45, "arm_progress": age / 0.45, "t": 50.0 + age})
	# Capstones and long words.
	_stage_run(LATE, LATE_OFFER, 24, 1, 12.0)
	await _popup_shot("popup_late", {"settled": true})
	# The map over the popup, and back.
	_stage_run(MID, MID_OFFER, 9, 3, 6.0)
	await _popup_shot("popup_map_overview", {"settled": true, "map": true, "focus": "", "node": ""})
	await _popup_shot("popup_map_focus", {"settled": true, "map": true, "focus": "guardian", "node": "guard_bul"})
	# The viewer from the rail (no offer).
	_stage_run(LATE, [], 24, 0, 12.0)
	await _popup_shot("viewer_overview", {"settled": true, "map": false, "focus": "", "node": ""})
	await _popup_shot("viewer_focus", {"settled": true, "map": false, "focus": "precision", "node": "prec_hawk"})
	# The pick: Star of Fury flies into its constellation; one more level waits.
	var picked := MID.duplicate()
	picked["fury_wrath"] = 1
	_stage_run(picked, ["tempo_rush", "elem_ice", "fate_insight"], 10, 1, 0.0)
	for f in range(11):
		var age := f * 0.045
		await _popup_shot("motion_pick_hold_%02d" % f, {"settled": false, "hold_age": age, "hold_id": "fury_wrath",
			"hold_offer": MID_OFFER, "t": 60.0 + age})
	# The pick with nothing left: the popup leaves with the star, then the field banner.
	_stage_run(picked, [], 10, 0, 0.0)
	Arena.modal = ""
	for f in range(6):
		var age := f * 0.09
		await _popup_shot("motion_pick_last_%02d" % f, {"settled": false, "paint_hold": true, "hold_age": age,
			"hold_id": "fury_wrath", "hold_offer": MID_OFFER, "t": 70.0 + age})
	_popup.talent_view._pick_node = "fury_wrath"
	_popup.talent_view._pick_t0 = 79.6
	await _popup_shot("field_pick_banner", {"settled": false, "banner_sim": BannerSim.new(), "t": 80.0})
	_popup.queue_free()
	board.visible = true
	Arena.talents = saved["talents"]
	Arena.talent_offer.assign(saved["offer"])
	Arena.level = int(saved["level"])
	Arena.xp = float(saved["xp"])
	Arena.pending_levels = int(saved["pending"])
	Arena.modal = String(saved["modal"])
	Arena.owned_passives.assign(saved["owned"])
	Arena.levels = saved["levels"]


# --------------------------------------------------------------------------- #
# Film and capture
# --------------------------------------------------------------------------- #
func _open_film() -> void:
	var spec := arg("--film", "")
	if spec.is_empty(): return
	var size := Vector2i(int(spec.get_slice("x", 0)), int(spec.get_slice("x", 1)))
	get_window().size = Vector2i(96, 60)
	film = SubViewport.new()
	film.size = size
	film.size_2d_override = Vector2i(1280, 800)
	film.size_2d_override_stretch = true
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.transparent_bg = false
	film.msaa_2d = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d", 0)) as Viewport.MSAA
	film.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	film.set("oversampling_override", float(size.x) / 1280.0)
	add_child(film)


func _capture(name: String) -> void:
	await _capture_on(board, name)


func _capture_on(canvas: CanvasItem, name: String) -> void:
	Look.text_audit_enabled = true
	Look.text_audit.clear()
	canvas.queue_redraw()
	await frames(2)
	var boxes: Array = []
	for item in Look.text_audit:
		var r: Rect2 = item["box"]
		boxes.append({"text": String(item["text"]), "box": [r.position.x, r.position.y, r.size.x, r.size.y], "size": int(item["size"])})
	Look.text_audit_enabled = false
	var zones: Array = []
	var canvas_ui: Ui = canvas.get("ui")
	for zone in canvas_ui.zones:
		var r: Rect2 = zone["rect"]
		zones.append({"id": String(zone["id"]), "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "on": bool(zone["on"])})
	await RenderingServer.frame_post_draw
	var picture: Viewport = film if film != null else get_viewport()
	var file_name := "%s_%s" % [locale, name]
	picture.get_texture().get_image().save_png(out_dir + "/" + file_name + ".png")
	var file := FileAccess.open(out_dir + "/" + file_name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"name": file_name, "boxes": boxes, "zones": zones}) + "\n")
	file = null
	_index.append(file_name)
