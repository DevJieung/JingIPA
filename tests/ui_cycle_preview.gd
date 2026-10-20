extends "res://tests/stage_store_preview.gd"

## The whole play cycle as still pictures, for the UI consistency audits (first
## docs/UI_CYCLE_AUDIT_2026-10-17.md; the stage ladder and the jewel box of 2026-10-19):
## title with its collection, stage select, Hellbound squad, shop sheet and menu pages; the
## battlefield card; the free first jewel box, a paid one, a reroll and its results; the battle
## HUD with anti-air heroes and flying monsters; the wave machine (preparation, elite, boss);
## the level-up constellation popup (opened in a preparation) and the constellation viewer and
## map; the reserve swap; the shop over the battle; the menu over the battle; the result
## panels; and the popup's entrance as consecutive frames.
##
##   godot --disable-vsync --path . --resolution 96x60 res://tests/ui_cycle_preview.tscn -- \
##       --film 1280x800 --out build/ui-cycle-2026-10-17/after/1280x800 \
##       [--locales ko,en] [--only title,card,box,hud,wave,talent,bench,shop,menu,result,hell,motion]
##
## Every state is reached through the run and the simulator and drawn by the real screens
## (the staging helpers are the stage/store preview's: a stage opens directly, staged
## scenes sit in the middle of a wave, the boss comes through the wave machine). Each
## picture leaves <name>.json with the drawn text and every touch zone, like the parent
## preview. `--watchdog SEC` (default 1800) fails a run that stalls instead of hanging.

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", "build/ui-cycle-2026-10-17/after/1280x800")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_watchdog()
	_open_film()
	_sets = arg("--only", "title,card,box,hud,wave,talent,bench,shop,menu,result,hell").split(",", false)
	# The set was called "rite" until the jewel box replaced the star rite (2026-10-19).
	if "rite" in _sets: _sets.append("box")
	_keep_save()
	Run.running = false
	Arena.running = false
	main = load("res://game/main.gd").new()
	_mount(main)
	await frames(3)
	for code in arg("--locales", "ko,en").split(",", false):
		locale = code
		I18n.set_locale(code)
		if "title" in _sets: await _run_set("title", _cycle_title)
		if "card" in _sets: await _run_set("card", _cycle_cards)
		if "box" in _sets: await _run_set("box", _cycle_box)
		if "hud" in _sets: await _run_set("hud", _cycle_hud)
		if "wave" in _sets: await _run_set("wave", _waves)
		if "talent" in _sets: await _run_set("talent", _cycle_talent)
		if "bench" in _sets: await _run_set("bench", _cycle_bench)
		if "shop" in _sets: await _run_set("shop", _cycle_shop)
		if "menu" in _sets: await _run_set("menu", _cycle_menu)
		if "result" in _sets: await _run_set("result", _cycle_results)
		if "hell" in _sets: await _run_set("hell", _cycle_hell)
		if "motion" in _sets: await _run_set("motion", _cycle_motion)
	_no_shop()
	_restore_save()
	Arena.running = false
	var file := FileAccess.open(out_dir + "/index.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_index, "  ") + "\n")
	file = null
	finish("Play-cycle UI previews")

## The guide's tabs (MenuOverlay: "box" is the jewel box page on the title and the battlefield).
const MENU_PAGES := ["menu", "rules", "box", "elements"]

# --------------------------------------------------------------------------- #
# Staging
# --------------------------------------------------------------------------- #
## Six guardians with every weapon: two guns and a bow (anti-air), a sword, a whip, a deck.
func _squad_mixed() -> void:
	Arena.heroes.clear()
	Arena.bench.clear()
	var ids := ["limne", "chispa", "brigid", "pip", "morrigan", "dummy"]
	for i in range(Balance.ARENA_HERO_LIMIT):
		Arena.gain_hero(Roster.unit_by_id(ids[i]), (i * 2 + 1) % 10)
		Arena.heroes[i]["position"] = _open_ground(-PI * 0.5 + i * TAU / 6, 150.0 if i % 2 == 0 else 345.0)
	Arena.sim.refresh_heroes()
	Arena.selected = 1
	Arena.gold = 480

## Flying and walking monsters of the water body down the first road, all hurt so their
## health bars show (the bars must ride the raised bodies).
func _crowd_air() -> void:
	var sim := Arena.sim
	var rows := [Roster.monster_by_id("rapid_ray"), Roster.monster_by_id("jelly_seer"), Roster.monster_by_id("drop_slime")]
	for lane in range(ArenaGeometry.route_count()):
		var path := ArenaGeometry.route_points(lane)
		for k in range(5):
			sim._spawn(rows[(k + lane) % rows.size()])
			var mo: Dictionary = sim.monsters[-1]
			var at := clampi(int(path.size() * (0.06 + 0.17 * k)), 0, path.size() - 3)
			mo["pos"] = path[at]
			mo["route"] = lane
			mo["max"] = float(mo["max"]) * 40.0
			mo["hp"] = float(mo["max"]) * (0.35 + 0.5 * fposmod(k * 0.37 + lane * 0.21, 1.0))
			mo["vel"] = (path[at + 1] - path[at]).normalized()
	sim.events.clear()
	sim._rebuild_navigation()
	sim._cache_positions()
	sim._spawn_t = 1.0e9

## Nodes already joined, by id → times.
func _take(nodes: Dictionary) -> void:
	for id in nodes:
		Arena.talents[String(id)] = int(nodes[id])
	Arena._refresh_mods()

## A level-up with `pending` levels to spend. The popup opens only in a preparation
## (PLAN M4): a wave in progress is held first, the real way, and the levels earned during it
## are offered as the next preparation begins. `offer` replaces the rolled three.
func _level_up(level: int, pending: int, offer: Array = []) -> void:
	Arena.level = level
	if not Arena.sim.in_prep():
		Arena.xp = -1.0e9
		_clear_wave_now()
		await _let_fall(1.2)
	Arena.pending_levels = pending
	Arena.xp = 0.0
	if Arena.modal.is_empty(): Arena.offer_levelup()
	check(Arena.modal == "talent" and not Arena.talent_offer.is_empty(), "level-up opens the constellation popup in the preparation")
	if not offer.is_empty():
		Arena.talent_offer.assign(offer)

## A battle with the mixed squad on a water field, part way to the next level: in the middle
## of wave `wave` (0 = the stage's first preparation, the box open).
func _air_battle(number: int = 5, wave: int = 3) -> void:
	_card_of(number, "calm_lake")
	_into_battle(wave)
	_squad_mixed()
	_crowd_air()
	Arena.level = 4
	Arena.xp = 0.62 * Arena.xp_needed()

## A card of the open box holding `unit`: the card that already deals it, else the first card
## that is not the guaranteed one (its stars kept). Returns the card's index.
func _card_with(unit: Dictionary) -> int:
	for i in range(Arena.box_cards.size()):
		if String(Arena.box_cards[i]["unit"]["id"]) == String(unit["id"]): return i
	for i in range(Arena.box_cards.size()):
		if not bool(Arena.box_cards[i]["guaranteed"]):
			Arena.box_cards[i]["unit"] = unit
			return i
	Arena.box_cards[0]["unit"] = unit
	return 0

## An anti-air (gun or bow) hero nobody in the party has yet.
func _new_anti_air() -> Dictionary:
	for id in ["chispa", "saeta", "brian", "conor", "echo", "kari"]:
		var unit := Roster.unit_by_id(id)
		if not unit.is_empty() and Balance.anti_air(unit) and int(Arena.find_hero(id)[1]) < 0: return unit
	for unit in Roster.UNITS:
		if Balance.anti_air(unit) and int(Arena.find_hero(String(unit["id"]))[1]) < 0: return unit
	return Roster.UNITS[0]

## Pick card `index` of the open box through its own zone when the box view draws one.
func _pick(index: int) -> void:
	await _act("box:pick:%d" % index, func() -> void: Arena.pick_card(index))

## Close the box after its result (the box view's "close"), or through the run.
func _close_box() -> void:
	await _act("close", func() -> void: Arena.close_modal())

# --------------------------------------------------------------------------- #
# Sets
# --------------------------------------------------------------------------- #
func _cycle_title() -> void:
	_use_shop()
	Save.cur_run = {}
	Save.best_tier = 6
	_ladder_record("stage7")
	main.show_title()
	await frames(6)
	await _capture_canvas(main.screen, "title_first")
	main.screen.collection.opened = true
	await _capture_canvas(main.screen, "title_collection")
	main.screen.collection.fusion_only = true
	await _capture_canvas(main.screen, "title_collection_fusion")
	main.screen.collection.fusion_only = false
	main.screen.collection.close()
	# The zones on record are the open collection's; draw once so the shop button is on top.
	await paint(main.screen)
	check(tap(main.screen, "store:open") and main.screen.store.opened, "title shop button opens the sheet")
	await _capture_canvas(main.screen, "title_shop")
	main.screen.store.close()
	# The ladder's stage select (the title's "stages").
	await paint(main.screen)
	if tap(main.screen, "stages"):
		await _capture_canvas(main.screen, "title_stages")
		main.screen.stage_select.close()
	else:
		print("   (no stages zone on the title: stage select not captured)")
	# Hellbound: the squad picker for a DLC owner (the codex's heroes), the shop sheet otherwise.
	for unit in Roster.UNITS: Save.seen_units[String(unit["id"])] = true
	_use_shop([Store.GUARDIAN])
	main.show_title()
	await frames(4)
	if tap(main.screen, "hell"):
		await _capture_canvas(main.screen, "title_hell")
		if main.screen.squad.opened: main.screen.squad.close()
		if main.screen.store.opened: main.screen.store.close()
	else:
		print("   (no hell zone on the title: Hellbound squad not captured)")
	_use_shop()
	main.show_title()
	await frames(4)
	main.menu.open()
	for page in MENU_PAGES:
		main.menu.page = page
		await frames(2)
		await _capture_canvas(main.menu, "title_menu_" + page)
	main.menu.close()
	await frames(2)
	# A run to resume.
	Arena.start_run(SEED, 8)
	_open_first_box()
	_take_box()
	Arena.autosave()
	Save.cur_run = Arena.snapshot()
	Arena.running = false
	main.show_title()
	await frames(4)
	await _capture_canvas(main.screen, "title_resume")
	Save.cur_run = {}

## Battlefield cards: the ladder's first stage, a water field with flyers, a rock field with
## the hovering idol, a chapter's end and the last stage.
func _cycle_cards() -> void:
	_no_shop()
	for entry in [[1, "spring_grove"], [2, "calm_lake"], [7, "desert_mesa"], [10, "ice_spire_field"], [100, ""]]:
		_card_of(int(entry[0]), String(entry[1]))
		await _fresh_screen()
		await _capture(_card_name(int(entry[0]), String(entry[1])))

## The jewel box (F10, modal "box", docs/JEWEL_BOX.md). The pictures are ArenaBoxView's
## (D1's ceremony); a held screen draws the box settled. States: the stage's free first box
## as it opens, a card pressed, its result; a paid box in the preparation; the same box after
## a free reroll; a box with a card that grows a hero already in the party and its result; a
## box with a new anti-air hero and its result; a box without the DLC (one free reroll) before
## and after the reroll.
func _cycle_box() -> void:
	_use_shop([Store.GUARDIAN])
	_run_on("spring_grove")
	_open_first_box()
	check(Arena.modal == "box" and not Arena.box_cards.is_empty() and Arena.box_tier >= 1, "the card opens the stage's free first box")
	await _fresh_screen()
	await _capture("box_first")
	screen.ui.pressed = "box:pick:0"
	await _capture("box_first_pressed")
	screen.ui.pressed = ""
	var best := JewelBox.best(Arena.box_cards)
	await _pick(best)
	check(not Arena.summon_result.is_empty() and Arena.modal == "box", "the first box gives the picked card")
	await _capture("box_result_new")
	await _close_box()
	check(Arena.modal.is_empty() and Arena.sim.in_prep(), "the result closes into the first preparation")
	# A paid box in the preparation (DLC: three free rerolls).
	Arena.gold = 999
	await _act("summon", func() -> void: Arena.begin_summon())
	check(Arena.modal == "box", "a paid box opens in the preparation")
	await _capture("box_paid")
	var tier := Arena.box_tier
	await _act("box:reroll", func() -> void: Arena.respin())
	check(Arena.spins >= 1 and Arena.box_tier >= tier, "a free reroll deals new cards, the grade never lower")
	await _capture("box_rerolled")
	# A card that grows the hero already on the field: its preview says growth.
	var grow := _card_with(Arena.heroes[0]["unit"])
	check(String(Arena.card_preview(grow).get("kind", "")) == "growth", "a card of an owned hero previews growth")
	await _capture("box_growth_card")
	await _pick(grow)
	check(String(Arena.summon_result.get("kind", "")) == "growth", "picking it grows the hero")
	await _capture("box_result_grown")
	await _close_box()
	# A new anti-air hero: the anti-air chip among its traits.
	Arena.gold = 999
	await _act("summon", func() -> void: Arena.begin_summon())
	var air := _card_with(_new_anti_air())
	await _pick(air)
	check(String(Arena.summon_result.get("kind", "")) == "new", "a new anti-air hero joins")
	await _capture("box_result_air")
	await _close_box()
	# Without the DLC: one free reroll, then none.
	_use_shop()
	_run_on("spring_grove")
	_open_first_box()
	await _fresh_screen()
	await _capture("box_nodlc")
	await _act("box:reroll", func() -> void: Arena.respin())
	check(Arena.respins_left() == maxi(0, Arena.free_rerolls() - 1), "the reroll spends the one free reroll")
	await _capture("box_nodlc_spent")
	Arena.confirm_summon()
	Arena.close_modal()

## The battle HUD with anti-air heroes, flyers and the growth cell of the top strip, then the
## last preparation with the boss warning.
func _cycle_hud() -> void:
	_use_shop([Store.GUARDIAN])
	_air_battle()
	await _fresh_screen()
	await _capture("hud_air_battle")
	Arena.selected = 2
	screen.ui.pressed = "hero:2"
	await _capture("hud_hero_pressed")
	screen.ui.pressed = ""
	Arena.level = 12
	Arena.xp = 0.96 * Arena.xp_needed()
	Arena.gold = 12480
	await _capture("hud_growth_full")
	check(Arena.sim.cast_skill("ward"), "the ward casts mid-wave")
	_boss_warning(2.2)
	# By the warning (late in the long boss preparation) no wave banner is left: a fresh screen.
	await _fresh_screen()
	await _capture("hud_air_boss_warning")
	# The stage's first preparation with the same squad: the countdown and the open box.
	_air_battle(5, 0)
	await _fresh_screen()
	await _capture("hud_prep_first")

## The level-up popup, the constellation viewer and its map.
func _cycle_talent() -> void:
	_use_shop([Store.GUARDIAN])
	_air_battle()
	await _fresh_screen()
	# Nothing joined yet: the viewer from the rail.
	check(tap(screen, "talents") and Arena.modal == "talent" and Arena.talent_offer.is_empty(), "the rail opens the viewer")
	await _capture("talent_view_empty")
	check(tap(screen, "close") and Arena.modal == "", "the viewer closes")
	# The first level: the wave is held and three rolled roots are offered in the preparation.
	await _level_up(1, 1)
	await _capture("talent_offer_first")
	screen.ui.pressed = "talent:pick:" + String(Arena.talent_offer[0])
	await _capture("talent_offer_pressed")
	screen.ui.pressed = ""
	var first := String(Arena.talent_offer[0])
	check(tap(screen, "talent:pick:" + first) and Arena.talent_count(first) == 1 and Arena.modal == "", "picking returns to the battle")
	# Back on the field, the star just joined stands on the banner row for a moment.
	await _capture("hud_pick_banner")
	check(not zone_of(screen, "skill:ward").is_empty(), "the field is live again under the banner")
	# Deep into a run: repeats, a third-depth node, three levels waiting.
	_take({"fury_edge": 1, "fury_blaze": 1, "fury_over": 1, "elem_elec": 1, "st_bolt": 1, "tempo_quick": 2, "guard_hp": 1})
	await _level_up(9, 3, ["fury_edge", "st_chain", "fate_ascend"])
	await _capture("talent_offer_pending3")
	# The longest effect lines of the table, in both languages.
	Arena.talent_offer.assign(["tempo_surge", "arms_down", "st_reson"])
	await _capture("talent_offer_long")
	# The map from the popup (F2, when the popup offers it).
	await paint(screen)
	if tap(screen, "talent:map"):
		await _capture("talent_offer_map")
		tap(screen, "talent:back")
		await paint(screen)
	Arena.pick_talent("st_reson")
	var guard := 0
	while Arena.modal == "talent" and not Arena.talent_offer.is_empty() and guard < 12:
		Arena.pick_talent(String(Arena.talent_offer[0]))
		guard += 1
	# The viewer with a run's worth of stars joined, across six constellations.
	_take({"prec_aim": 2, "prec_deadly": 1, "arms_gun": 1, "arms_air": 2, "star_meteor": 1, "fate_gold": 1, "fate_insight": 1})
	await paint(screen)
	check(tap(screen, "talents") and Arena.modal == "talent", "the viewer opens with stars joined")
	await _capture("talent_view_many")
	if not zone_of(screen, "talent:next").is_empty() and bool(zone_of(screen, "talent:next")["on"]):
		tap(screen, "talent:next")
		await _capture("talent_view_page2")
	# The constellation map (F2): its overview, then one constellation up close.
	await paint(screen)
	if tap(screen, "talent:map"):
		await _capture("talent_map")
		await paint(screen)
		for zone in screen.ui.zones:
			if String(zone["id"]).begins_with("talent:group:") and bool(zone["on"]):
				tap(screen, String(zone["id"]))
				await _capture("talent_map_group")
				break
	else:
		print("   (no talent:map zone yet: the constellation map is not captured)")
	await paint(screen)
	tap(screen, "close")
	if Arena.modal == "talent": Arena.close_modal()

func _cycle_bench() -> void:
	_use_shop([Store.GUARDIAN])
	_air_battle()
	Arena.gain_hero(Roster.unit_by_id("echo"), 4)
	Arena.gain_hero(Roster.unit_by_id("saeta"), 9)
	await _fresh_screen()
	check(tap(screen, "bench") and Arena.modal == "bench", "the rail opens the reserve")
	await _capture("bench_open")
	screen.set("_field_choice", 1)
	screen.set("_bench_choice", 0)
	await _capture("bench_selected")
	tap(screen, "close")

func _cycle_shop() -> void:
	_use_shop()
	_air_battle()
	await _fresh_screen()
	screen.store.open()
	await _capture("shop_battle")
	screen.store.close()

## The shared menu over the battle: its four pages.
func _cycle_menu() -> void:
	_no_shop()
	_air_battle()
	await _fresh_screen()
	main.menu.open()
	check(main.menu.opened, "menu opens over the battle")
	for page in MENU_PAGES:
		main.menu.page = page
		await frames(2)
		await _capture_canvas(main.menu, "menu_" + page)
	main.menu.close()
	await frames(2)

func _cycle_results() -> void:
	_use_shop()
	_card_of(4, "quarry_pit")
	_into_battle()
	_crowd()
	Arena.kills = 318
	Arena.level = 6
	_break_crystal()
	await _fresh_screen()
	check(Arena.modal == "result" and not zone_of(screen, "result:guardian").is_empty(), "defeat without the DLC: the offer")
	await _capture("result_defeat_offer")
	_use_shop([Store.GUARDIAN])
	_card_of(10, "polar_night")
	_into_battle()
	Arena.kills = 2480
	Arena.level = 21
	Arena.sim.invuln_t = 0.0
	_fell_boss()
	_run_clear()
	check(Arena.sim.won and Arena.modal == "result", "victory staged")
	await _fresh_screen()
	await _capture("result_victory")

## Hellbound (DLC, endless waves; PLAN U4 · M10): six heroes from the codex at their best grades
## (the codex is filled in memory: Hellbound only takes heroes met before), its card, the first
## preparation, a late wave with no total (WAVE 23) and its crowd, the elite of the twenty-fifth,
## the warning before the thirtieth (a boss every tenth wave), and the defeat that keeps the best wave.
func _cycle_hell() -> void:
	_use_shop([Store.GUARDIAN])
	var ids := ["limne", "chispa", "brigid", "pip", "morrigan", "saeta"]
	for unit in Roster.UNITS: Save.seen_units[String(unit["id"])] = true
	for i in range(ids.size()): Save.unit_best[ids[i]] = [9, 7, 8, 5, 6, 9][i]
	Save.hell_best_wave = 31
	check(Arena.start_hellbound(ids, SEED) and Arena.hell and Arena.modal == "stage", "Hellbound starts on its card with the codex squad")
	if not Arena.hell:
		return
	await _fresh_screen()
	await _capture("hell_card")
	Arena.confirm_stage()
	_settle_levels()
	check(Arena.modal.is_empty() and Arena.sim.in_prep() and Arena.sim.waves_total() == 0, "Hellbound: no box, the first preparation, endless waves")
	await _capture("hell_prep")
	_mid_wave(23)
	_crowd()
	# Past the wave's banner (the HUD's banners age on the screen's clock).
	await _let_fall(1.9)
	await _capture("hell_wave23")
	_settle_levels(true)
	_clear_wave_now()
	await _let_fall(1.2)
	_mid_wave(25)
	var sim := Arena.sim
	sim._spawn_t = 0.0
	var guard := 0
	while sim._wave_spawned < sim._wave_list.size() and guard < 40:
		var entry: Dictionary = sim._wave_list[sim._wave_spawned]
		sim._spawn_next()
		guard += 1
		if bool(entry.get("elite", false)): break
	sim._spawn_t = 1.0e9
	_spread_on_roads(0.2, 0.7)
	_notice()
	_settle_levels()
	await _capture("hell_elite_w25")
	_boss_warning(2.4)
	check(sim.wave_no == 30, "Hellbound: the warning before the thirtieth wave (%d)" % sim.wave_no)
	await _fresh_screen()
	await _capture("hell_boss_warning_w30")
	for n in range(Balance.ARENA_REVIVE_USES + 1): _break_crystal()
	await _fresh_screen()
	check(Arena.modal == "result" and Arena.hell, "Hellbound: the defeat result")
	await _capture("hell_result")

## The popup's entrance, frame by frame (the screen runs; the engine clock is held). The
## level-up arrives as a wave is held and its preparation begins.
func _cycle_motion() -> void:
	Engine.time_scale = 0.0
	_use_shop([Store.GUARDIAN])
	_air_battle()
	await _fresh_screen()
	screen.set_process(true)
	await frames(2)
	await _frame("motion_levelup_00")
	await _level_up(5, 2)
	screen._track_modal()
	for n in range(1, 14):
		_advance(0.05)
		await _frame("motion_levelup_%02d" % n)
	screen.set_process(false)
	Engine.time_scale = 1.0
