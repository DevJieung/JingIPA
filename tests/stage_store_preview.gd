extends Harness

## Stages and photographs the surfaces of docs/UI_STAGE_STORE.md: the battlefield card,
## the stage HUD, the purchase sheet, the result screen and the title's shop entry.
## It changes no rule: every state is reached through the run, the simulator and a
## stand-in shop, then drawn by the real screens.
##
##   godot --disable-vsync --path . --resolution 96x60 res://tests/stage_store_preview.tscn -- \
##       --film 1280x800 --out build/ui-stage-store/1280x800 [--locales ko,en] [--only card,hud]
##
## Sets: card hud banner result shop title help (the default), motion, probe.
## Every picture comes with <name>.json: the text that was drawn (fitted sizes and
## boxes) and every touch zone, so clipping, overlap and touch sizes can be checked
## over the whole set instead of by eye alone.
## `--film WxH` draws into an off-screen picture of that size (the window only lends its
## GL context); without it the scene draws into the window (Xvfb).

## A shop that answers at once. `answer` is the outcome of the next purchase
## ("ok" | "cancelled" | "pending" | "failed" | "hang"), `selling` whether the shop can
## sell at all, `prices` what its price strings say.
class ShopBase extends RefCounted:
	var store: Node
	var selling := true
	var answer := "ok"
	var restore_answer := "ok"
	var owned: Array = []
	var prices := {"guardian": "₩2,200"}
	func start() -> void:
		for id in prices: store.set_price(String(id), String(prices[id]))
		store.set_owned(owned)
	func sells(_id: String) -> bool: return selling
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void:
		if restore_answer == "hang": return
		store.set_owned(owned)
		store.finish_restore(restore_answer == "ok")
	func buy(product: Dictionary) -> void:
		var id := String(product["id"])
		if answer == "ok":
			owned.append(id)
			store.grant(id)
		elif answer != "hang":
			store.finish_purchase(id, answer)

class MobileShop extends ShopBase:
	const NAME := "test"

## A store build whose shop cannot sell reads "not connected". This binary is a test
## build and offers the test unlock instead, so that one state is staged in the view.
class OfflineView extends StoreView:
	func state_of(id: String) -> String:
		return "owned" if Store.owns(id) else "offline"

class SteamShop extends ShopBase:
	const NAME := "steam"

const SEED := 20261013
var out_dir := "build/ui-stage-store/1280x800"
var main: Node2D
var screen: ArenaScreen
var film: SubViewport
var locale := "ko"
var _sets: PackedStringArray = []
var _index: Array = []
var _saved := {}

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_open_film()
	_sets = arg("--only", "card,hud,shop,result,banner,title,help").split(",", false)
	_saved = {"runs": Save.runs, "best_stage": Save.best_stage, "clears": Save.clears, "best_tier": Save.best_tier,
		"speed": Save.speed, "cur_run": Save.cur_run.duplicate(true), "language": I18n.locale,
		"iap_owned": Save.iap_owned.duplicate(), "iap_sandbox": Save.iap_sandbox.duplicate()}
	Run.running = false
	Arena.running = false
	main = load("res://game/main.gd").new()
	_mount(main)
	await frames(3)
	for code in arg("--locales", "ko,en").split(",", false):
		locale = code
		I18n.set_locale(code)
		if "card" in _sets: await _cards()
		if "hud" in _sets: await _hud()
		if "banner" in _sets: await _banners()
		if "result" in _sets: await _results()
		if "shop" in _sets: await _shop()
		if "title" in _sets: await _title()
		if "help" in _sets: await _help()
		if "motion" in _sets: await _motion()
	if "probe" in _sets: await _probe()
	_no_shop()
	Save.runs = int(_saved["runs"])
	Save.best_stage = int(_saved["best_stage"])
	Save.clears = int(_saved["clears"])
	Save.best_tier = int(_saved["best_tier"])
	Save.speed = float(_saved["speed"])
	Save.cur_run = _saved["cur_run"]
	Save.iap_owned = _saved["iap_owned"]
	Save.iap_sandbox = _saved["iap_sandbox"]
	I18n.set_locale(String(_saved["language"]))
	Arena.running = false
	var file := FileAccess.open(out_dir + "/index.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_index, "  ") + "\n")
	file = null
	finish("Stage card · stage HUD · purchase sheet · result · title previews")

# --------------------------------------------------------------------------- #
# Shop stand-ins
# --------------------------------------------------------------------------- #
func _no_shop() -> void:
	Save.iap_owned = []
	Save.iap_sandbox = []
	Store._owned.clear()
	Store.use_backend(null)

func _use_shop(owned: Array = [], prices: Dictionary = {}, steam: bool = false) -> ShopBase:
	var shop: ShopBase = SteamShop.new() if steam else MobileShop.new()
	shop.owned = owned.duplicate()
	if not prices.is_empty(): shop.prices = prices.duplicate()
	Save.iap_owned = []
	Save.iap_sandbox = []
	Store._owned.clear()
	Store.use_backend(shop)
	return shop

# --------------------------------------------------------------------------- #
# Run staging
# --------------------------------------------------------------------------- #
func _theme_index(id: String) -> int:
	for i in range(Roster.THEMES.size()):
		if String(Roster.THEMES[i]["id"]) == id: return i
	printerr("!! unknown theme " + id)
	return 0

func _open_ground(angle: float, radius: float) -> Vector2:
	for step in range(24):
		var at := Balance.ARENA_CENTER + Vector2.from_angle(angle + step * 0.13) * radius
		if not ArenaGeometry.on_road(at, -Balance.ARENA_HERO_RADIUS): return at
	return Balance.ARENA_CENTER + Vector2.from_angle(angle) * radius

## Six mixed guardians around the altar and out on the open ground.
func _squad() -> void:
	Arena.heroes.clear()
	Arena.bench.clear()
	var ids := ["limne", "brasa", "echo", "pip", "morrigan", "dummy"]
	for i in range(Balance.ARENA_HERO_LIMIT):
		Arena.gain_hero(Roster.unit_by_id(ids[i]), (i + 3) % 10)
		Arena.heroes[i]["position"] = _open_ground(-PI * 0.5 + i * TAU / 6, 150.0 if i % 2 == 0 else 345.0)
	Arena.sim.refresh_heroes()
	Arena.selected = 1
	Arena.gold = 480

## The stage's own monsters spread along every road.
func _crowd(per_lane: int = 5) -> void:
	var sim := Arena.sim
	var spawns: Array = Arena.stage_spawns(Arena.stage, 0)
	var n := 0
	for lane in range(ArenaGeometry.route_count()):
		var path := ArenaGeometry.route_points(lane)
		for k in range(per_lane):
			sim._spawn(spawns[(n * 7) % spawns.size()])
			var mo: Dictionary = sim.monsters[-1]
			var at := clampi(int(path.size() * (0.03 + 0.8 * float(k) / per_lane)), 0, path.size() - 3)
			mo["pos"] = path[at]
			mo["route"] = lane
			mo["max"] = float(mo["max"]) * 40.0
			mo["hp"] = float(mo["max"]) * (0.4 + 0.55 * fposmod(n * 0.37, 1.0))
			mo["vel"] = (path[at + 1] - path[at]).normalized()
			n += 1
	sim.events.clear()
	sim._rebuild_navigation()
	sim._cache_positions()
	sim._spawn_t = 1.0e9

## A fresh run whose first battlefield is `theme_id`, left on the stage 1 card.
func _run_on(theme_id: String) -> void:
	Arena.start_run(SEED)
	Arena.stage_themes[0] = _theme_index(theme_id)
	Arena.sim = null
	Arena._open_stage(1)

## From the stage 1 card into the battle with the review squad.
func _into_battle() -> void:
	if Arena.modal == "stage": Arena.confirm_stage()
	if Arena.modal == "rite":
		Arena.confirm_summon()
		Arena.close_modal()
	_squad()
	Arena.sim._spawn_t = 1.0e9

## The crystal breaks (any untouchable seconds are waived first). An owner with a
## blessing left is revived by the simulator; otherwise the run ends.
func _break_crystal() -> void:
	Arena.sim.invuln_t = 0.0
	Arena.sim._damage_crystal(1.0e9, Balance.ARENA_CENTER)

## The screen's own step: it notices a revival here and starts its banner.
func _notice() -> void:
	screen._process(1.0 / 30.0)

## The stage boss walks in and falls. Leaves the simulator inside its clear delay.
func _fell_boss() -> void:
	var sim := Arena.sim
	sim.elapsed = Balance.ARENA_BOSS_AT - 0.02
	for i in range(4): sim.step(1.0 / 30.0)
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()

## Play the real chain up to the card of `number` on `theme_id`.
func _card_of(number: int, theme_id: String, first: String = "spring_grove") -> void:
	_run_on(theme_id if number == 1 else first)
	if number == 1: return
	_into_battle()
	while Arena.stage < number and Arena.running:
		if Arena.modal == "stage": Arena.confirm_stage()
		if Arena.stage + 1 == number: Arena.stage_themes[number - 1] = _theme_index(theme_id)
		_fell_boss()
		for i in range(roundi((Balance.ARENA_CLEAR_DELAY + 0.3) * 30.0)):
			if Arena.modal == "stage" and Arena.stage > 1 and Arena.sim.clear_t == 0.0 and Arena.sim.elapsed == 0.0: break
			Arena.sim.step(1.0 / 30.0)
	Arena.sim.events.clear()

func _fresh_screen() -> void:
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	screen.speed = float(clampi(roundi(Save.speed), 1, 3))
	screen._track_modal()
	await frames(4)

# --------------------------------------------------------------------------- #
# Sets
# --------------------------------------------------------------------------- #
## The battlefield card on stage 1, a middle stage and the final stage; one, three and
## four gates; dark and bright fields.
const CARDS := [
	[1, "mushroom_hollow"],    # coil, one gate, dark forest
	[1, "first_snow_hills"],   # fork, four gates, bright snow
	[1, "calm_lake"],          # spiral, four gates
	[5, "misty_cedar"],        # pinwheel, three gates
	[5, "drift_ice_sea"],      # coil, one gate, bright ice
	[7, "desert_mesa"],        # rock biome: immune element on the card
	[9, "worldtree_roots"],    # four bodies: three chips under the main block
	[10, "volcano_crater"],    # fork, final, dark
	[10, "ice_spire_field"],   # blades, final, bright
]

func _cards() -> void:
	_no_shop()
	var wanted := arg("--cards", "")
	for entry in CARDS:
		var number := int(entry[0])
		var id := String(entry[1])
		if not wanted.is_empty() and not (id in wanted.split(",")): continue
		_card_of(number, id)
		await _fresh_screen()
		check(Arena.modal == "stage" and Arena.stage == number and String(Arena.theme_for(1)["id"]) == id, "card staged: %d %s" % [number, id])
		await _capture("card_s%02d_%s" % [number, id])
		check(not zone_of(screen, "stage:start").is_empty() and bool(zone_of(screen, "stage:start")["on"]), "card keeps its one action: " + id)

## Top strip: the three plain speed chips (free for everyone), and the blessing's crest
## with the number of revivals left: none without the blessing, 3, 2, 1, 0, and the ring
## while the reformed crystal cannot be hurt. Then what shares the row under the strip.
func _hud() -> void:
	# Nothing bought: no crest, and every speed is there to choose.
	_use_shop()
	Save.runs = 50
	_run_on("misty_cedar")
	_into_battle()
	_crowd()
	await _fresh_screen()
	for value in [1, 2, 3]:
		check(tap(screen, "speed:%d" % value) and is_equal_approx(screen.speed, float(value)) and not screen.store.opened, "speed x%d is free" % value)
		await _capture("hud_speed_x%d" % value)
	screen.ui.pressed = "speed:1"
	await _capture("hud_speed_pressed")
	screen.ui.pressed = ""
	screen.set_speed(1.0)
	# A build without a shop counts as owning the blessing.
	_no_shop()
	_run_on("misty_cedar")
	_into_battle()
	_crowd()
	await _fresh_screen()
	check(Arena.revives_left() == Balance.ARENA_REVIVE_USES, "no shop: the blessing is there")
	await _capture("hud_blessing_noshop")
	# An owner: three, and one less after every break.
	for field in ["misty_cedar", "first_snow_hills"]:
		_use_shop([Store.GUARDIAN])
		_run_on(field)
		_into_battle()
		_crowd()
		await _fresh_screen()
		if field == "misty_cedar": await _capture("hud_blessing_3")
		for left in [2, 1, 0]:
			_break_crystal()
			check(Arena.running and Arena.revives_left() == left, "revival leaves %d" % left)
			if left == 2 and field == "misty_cedar":
				Arena.sim.invuln_t = Balance.ARENA_REVIVE_INVULN * 0.62
				await _capture("hud_blessing_2_untouchable")
			Arena.sim.invuln_t = 0.0
			if field == "misty_cedar" or left == 0:
				await _capture("hud_blessing_%d%s" % [left, "" if field == "misty_cedar" else "_bright"])
	# Everything that can share the area under the strip at once.
	_use_shop([Store.GUARDIAN])
	_run_on("calm_lake")
	_into_battle()
	_crowd()
	Arena.sim.cast_skill("ward")
	Arena.sim.elapsed = Balance.ARENA_BOSS_AT - 2.2
	for i in range(3): Arena.sim.step(1.0 / 30.0)
	await _fresh_screen()
	screen.set_speed(3.0)
	await _capture("hud_ward_boss_warning")
	Arena.sim.elapsed = Balance.ARENA_BOSS_AT - 0.02
	for i in range(4): Arena.sim.step(1.0 / 30.0)
	await _capture("hud_ward_boss_bar")

## Stage clear and revival banners, alone and with the ward and the boss strip.
func _banners() -> void:
	_use_shop([Store.GUARDIAN])
	_run_on("spring_grove")
	_into_battle()
	_crowd()
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.42
	await _fresh_screen()
	Arena.sim.cast_skill("ward")
	_fell_boss()
	check(Arena.sim.clear_t > 0.0, "stage clear banner state")
	screen._process(1.0 / 30.0)
	await _capture("banner_clear_s01")
	# A later stage: the bounty is larger and the number has two digits less often.
	_card_of(9, "peak_cliffs")
	Arena.confirm_stage()
	await _fresh_screen()
	_fell_boss()
	screen._process(1.0 / 30.0)
	await _capture("banner_clear_s09")
	# The last boss falls: its own banner, on a dark and on a bright field. The ward is
	# still up beside it on the first one.
	for id in ["volcano_crater", "ice_spire_field"]:
		_card_of(10, id)
		Arena.confirm_stage()
		_crowd()
		Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.42
		await _fresh_screen()
		if id == "volcano_crater": Arena.sim.cast_skill("ward")
		_fell_boss()
		check(Arena.sim.clear_t > 0.0 and Arena.sim.final_stage() and Arena.running and Arena.modal == "", "last boss: clear beat before the result")
		screen._process(1.0 / 30.0)
		await _capture("banner_final_" + id)
	# Revival banners: every one of a run's three fires its own, with that stage's gold.
	# The first, on stage 1 (+110 G, two left), under a boss bar with the ward up.
	_use_shop([Store.GUARDIAN])
	_run_on("first_snow_hills")
	_into_battle()
	_crowd()
	await _fresh_screen()
	Arena.sim.cast_skill("ward")
	Arena.sim.elapsed = Balance.ARENA_BOSS_AT - 0.02
	for i in range(4): Arena.sim.step(1.0 / 30.0)
	Arena.sim.shield = 0.0
	var gold: int = Arena.gold
	_break_crystal()
	check(Arena.sim.revives == 1 and Arena.running and Arena.gold == gold + Balance.arena_revive_gold(1), "first revival: gold of stage 1")
	_notice()
	await _capture("banner_revive_first_s01")
	# The second, on a middle stage (one left).
	_card_of(5, "misty_cedar")
	Arena.confirm_stage()
	_crowd()
	await _fresh_screen()
	_break_crystal()
	_notice()
	_break_crystal()
	check(Arena.sim.revives == 2 and Arena.revives_left() == 1, "second revival: one left")
	_notice()
	await _capture("banner_revive_second_s05")
	# The last, on the final stage (+200 G, none left), on a dark and on a bright field.
	for id in ["volcano_crater", "ice_spire_field"]:
		_card_of(10, id)
		Arena.confirm_stage()
		_crowd()
		await _fresh_screen()
		for n in range(Balance.ARENA_REVIVE_USES):
			gold = Arena.gold
			_break_crystal()
			_notice()
		check(Arena.sim.revives == Balance.ARENA_REVIVE_USES and Arena.revives_left() == 0 and Arena.running and Arena.gold >= gold + Balance.arena_revive_gold(10), "last revival: gold of stage 10, none left")
		await _capture("banner_revive_last_s10_" + id)
	# The banner has gone and the seconds still run: the crest alone carries them.
	screen._revive_age = 99.0
	Arena.sim.invuln_t = Balance.ARENA_REVIVE_INVULN * 0.3
	await _capture("banner_revive_after")

func _results() -> void:
	# A build without a shop counts as owning the blessing: a defeat there has used all
	# three, there is nothing to offer, and the panel says why the crystal stayed broken.
	_no_shop()
	_card_of(4, "quarry_pit")
	Arena.confirm_stage()
	_crowd()
	Arena.kills = 318
	for n in range(Balance.ARENA_REVIVE_USES + 1): _break_crystal()
	await _fresh_screen()
	check(Arena.modal == "result" and Arena.sim.revives == Balance.ARENA_REVIVE_USES and zone_of(screen, "result:guardian").is_empty(), "no shop: all three used, no offer")
	await _capture("result_defeat_noshop")
	# Defeat with a shop and no blessing: one quiet offer.
	_use_shop()
	_card_of(4, "quarry_pit")
	Arena.confirm_stage()
	_crowd()
	Arena.kills = 318
	_break_crystal()
	await _fresh_screen()
	check(Arena.modal == "result" and not zone_of(screen, "result:guardian").is_empty(), "defeat without the blessing: the offer")
	await _capture("result_defeat_offer")
	screen.ui.pressed = "result:guardian"
	await _capture("result_defeat_offer_pressed")
	screen.ui.pressed = ""
	check(tap(screen, "result:guardian") and screen.store.opened and screen.store.focus == Store.GUARDIAN, "offer opens the sheet on the blessing")
	await _capture("result_offer_sheet")
	screen._action("store:close")
	# An owner who used all three, on a late stage: no offer, and the row says so.
	_use_shop([Store.GUARDIAN])
	_card_of(8, "blizzard_plateau")
	Arena.confirm_stage()
	_crowd()
	Arena.kills = 1204
	for n in range(Balance.ARENA_REVIVE_USES + 1): _break_crystal()
	await _fresh_screen()
	check(Arena.modal == "result" and zone_of(screen, "result:guardian").is_empty(), "all three used: no offer")
	await _capture("result_defeat_spent")
	# First-stage defeat: the smallest headline.
	_use_shop()
	_run_on("kiln_yard")
	_into_battle()
	_crowd()
	Arena.kills = 12
	_break_crystal()
	await _fresh_screen()
	await _capture("result_defeat_s01")
	# Victory without a revival, and one that needed two.
	for used in [0, 2]:
		_use_shop([Store.GUARDIAN])
		_card_of(10, "polar_night")
		Arena.confirm_stage()
		Arena.kills = 2480
		for n in range(used): _break_crystal()
		Arena.sim.invuln_t = 0.0
		_fell_boss()
		# The last boss falls with the same beat as every other; the result follows it.
		for i in range(roundi((Balance.ARENA_CLEAR_DELAY + 0.3) * 30.0)): Arena.sim.step(1.0 / 30.0)
		check(Arena.sim.won and Arena.modal == "result" and Arena.sim.revives == used, "victory staged")
		await _fresh_screen()
		await _capture("result_victory" if used == 0 else "result_victory_blessed")

func _sheet(name: String) -> void:
	await _capture("shop_" + name)

func _shop() -> void:
	# The sheet over the battle; the title uses the same view (see _title) and the defeat
	# panel opens it with the product named (see _results: result_offer_sheet).
	var shop := _use_shop()
	_run_on("misty_cedar")
	_into_battle()
	_crowd()
	await _fresh_screen()
	screen.store.open()
	await _sheet("buyable")
	check(not zone_of(screen, "store:buy:" + Store.GUARDIAN).is_empty() and bool(zone_of(screen, "store:buy:" + Store.GUARDIAN)["on"]), "the sheet's one buy button")
	screen.ui.pressed = "store:buy:" + Store.GUARDIAN
	await _sheet("buyable_pressed")
	screen.ui.pressed = ""
	# Price strings: long ones, one the shop has not answered yet, and currency signs the
	# bundled font does not carry.
	for entry in [["price_krw_code", "KRW 2,200"], ["price_usd", "US$1.99"], ["price_brl", "R$ 10,90"],
			["price_empty", ""], ["price_inr", "₹179.00"], ["price_try", "69,99 ₺"]]:
		shop = _use_shop([], {"guardian": String(entry[1])})
		screen.store.open()
		await _sheet(String(entry[0]))
	# Purchasing: the sheet waits on the shop.
	shop = _use_shop()
	shop.answer = "hang"
	screen.store.open()
	Store.buy(Store.GUARDIAN)
	await _sheet("purchasing")
	Store.finish_purchase(Store.GUARDIAN, "cancelled")
	await _sheet("notice_cancelled")
	for outcome in ["pending", "failed"]:
		shop.answer = outcome
		Store.buy(Store.GUARDIAN)
		await _sheet("notice_" + outcome)
	shop.answer = "ok"
	Store.buy(Store.GUARDIAN)
	await _sheet("notice_ok_owned")
	screen.store.open()
	await _sheet("owned")
	# Restore: running (the price rests), then both answers.
	shop = _use_shop()
	screen.store.open()
	shop.restore_answer = "hang"
	Store.restore()
	await _sheet("restoring")
	Store.finish_restore(true)
	await _sheet("restore_ok")
	shop.restore_answer = "failed"
	Store.restore()
	await _sheet("restore_failed")
	shop = _use_shop()
	shop.owned = [Store.GUARDIAN]
	shop.restore_answer = "ok"
	screen.store.open()
	Store.restore()
	await _sheet("restore_found")
	# The shop cannot sell: a test build unlocks without paying.
	shop = _use_shop()
	shop.selling = false
	screen.store.open()
	await _sheet("test_unlock")
	Store.buy(Store.GUARDIAN)
	await _sheet("test_unlocked_reset")
	# The same on a store build reads "not connected" (staged through the view).
	shop = _use_shop()
	shop.selling = false
	screen.store.close()
	screen.store = OfflineView.new()
	screen.store.open()
	await _sheet("offline")
	screen.store.close()
	screen.store = StoreView.new()
	# Steam, free release: the product is a DLC page without a price string.
	shop = _use_shop([], {"guardian": ""}, true)
	screen.store.open()
	await _sheet("steam")
	screen.store.close()

func _title() -> void:
	Save.cur_run = {}
	Save.best_tier = 6
	for state in ["first", "stage7", "cleared"]:
		Save.best_stage = {"first": 0, "stage7": 7, "cleared": 10}[state]
		Save.clears = 3 if state == "cleared" else 0
		_use_shop()
		main.show_title()
		await frames(6)
		await _capture_canvas(main.screen, "title_" + state)
	_no_shop()
	main.show_title()
	await frames(4)
	await _capture_canvas(main.screen, "title_noshop")
	check(zone_of(main.screen, "store:open").is_empty(), "no shop: no shop button")
	# Owned on a phone shop: the button stays, restore must remain findable.
	_use_shop([Store.GUARDIAN])
	main.show_title()
	await frames(4)
	await _capture_canvas(main.screen, "title_owned")
	check(not zone_of(main.screen, "store:open").is_empty(), "phone shop, owned: the shop button stays")
	check(tap(main.screen, "store:open") and main.screen.store.opened, "owner opens the sheet")
	await _capture_canvas(main.screen, "title_sheet_owned")
	main.screen.store.close()
	# A paid Steam copy owns it from the start: nothing to sell, no button.
	_use_shop([Store.GUARDIAN], {}, true)
	main.show_title()
	await frames(4)
	await _capture_canvas(main.screen, "title_steam_included")
	check(zone_of(main.screen, "store:open").is_empty(), "Steam, owned: the shop button steps aside")
	var shop := _use_shop()
	main.show_title()
	await frames(4)
	main.screen.ui.pressed = "store:open"
	await _capture_canvas(main.screen, "title_shop_pressed")
	main.screen.ui.pressed = ""
	check(tap(main.screen, "store:open") and main.screen.store.opened, "title shop button opens the sheet")
	await _capture_canvas(main.screen, "title_sheet")
	shop.answer = "ok"
	Store.buy(Store.GUARDIAN)
	await _capture_canvas(main.screen, "title_sheet_bought")
	main.screen.store.close()
	# A run to resume: the shop button must not crowd the two main buttons.
	Arena.start_run(SEED)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.autosave()
	Save.cur_run = Arena.snapshot()
	Arena.running = false
	main.show_title()
	await frames(4)
	await _capture_canvas(main.screen, "title_resume")
	Save.cur_run = {}

## The arena's page of the shared menu: the rule about stages has to fit its row.
func _help() -> void:
	_no_shop()
	_run_on("spring_grove")
	_into_battle()
	await _fresh_screen()
	main.menu.open()
	main.menu.page = "rules"
	check(main.menu.opened, "menu opens over the battle")
	await frames(3)
	await _capture_canvas(main.menu, "help_rules")
	main.menu.close()
	await frames(2)

## Consecutive frames of the moving parts. The screen runs here (a held screen draws
## everything settled). The engine's own clock is stopped so that every step of the
## screen's time is the one given by hand, however slowly the pictures are taken.
func _motion() -> void:
	Engine.time_scale = 0.0
	# The card's entrance: veil, plate, sheet, then the roads draw in from the gates.
	_use_shop([Store.GUARDIAN])
	_card_of(3, "forge_canyon")
	await _fresh_screen()
	screen.set_process(true)
	screen._card_key = ""
	await frames(3)
	await _frame("motion_card_00")
	for n in range(1, 18):
		_advance(0.07)
		await _frame("motion_card_%02d" % n)
	# Stage clear: the banner lands, holds, and the next card takes over.
	Arena.confirm_stage()
	_crowd()
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.5
	_advance(0.1)
	await frames(2)
	_fell_boss()
	for n in range(26):
		_advance(0.1)
		await _frame("motion_clear_%02d" % n)
	# Revival: the banner lands with its gold, the spent pip goes out and the crest's
	# number drops; then the banner fades and the crest alone carries the seconds.
	Arena.confirm_stage()
	_crowd()
	_advance(0.1)
	await frames(2)
	await _frame("motion_revive_00")
	_break_crystal()
	for n in range(1, 13):
		_advance(0.05)
		await _frame("motion_revive_%02d" % n)
	for n in range(13, 25):
		_advance(0.25)
		await _frame("motion_revive_%02d" % n)
	# The second of the run, right after: the count goes on down.
	_break_crystal()
	for n in range(25, 33):
		_advance(0.1)
		await _frame("motion_revive_%02d" % n)
	# The last boss: the banner lands, holds for the clear delay, and the victory panel
	# takes over. Frames every 0.1 s, closer around the handover.
	_card_of(10, "volcano_crater")
	Arena.confirm_stage()
	_crowd()
	Arena.kills = 2480
	_advance(0.1)
	await frames(2)
	_fell_boss()
	var shot := 0
	for n in range(34):
		_advance(0.05)
		var age: float = Balance.ARENA_CLEAR_DELAY - Arena.sim.clear_t if Arena.sim.clear_t > 0.0 else 99.0
		# Every frame of the landing and of the handover, every other one in between.
		if age < 0.5 or age > Balance.ARENA_CLEAR_DELAY - 0.2 or n % 2 == 0:
			await _frame("motion_final_%02d" % shot)
			shot += 1
	# The hand-over: the shade comes in, the banner dissolves, the card rises, the number
	# settles and a glint crosses the ten steps. One second in 0.05 s frames.
	for n in range(20):
		_advance(0.05)
		await _frame("motion_final_%02d" % shot)
		shot += 1
	check(Arena.modal == "result" and Arena.sim.won, "last boss: the beat ends in the victory panel")
	# A defeat arrives through the same entrance, without a banner.
	_use_shop()
	_run_on("kiln_yard")
	_into_battle()
	_crowd()
	Arena.kills = 12
	_advance(0.1)
	await frames(2)
	await _frame("motion_defeat_00")
	Arena.sim._damage_crystal(1.0e9, Balance.ARENA_CENTER)
	for n in range(1, 13):
		_advance(0.05)
		await _frame("motion_defeat_%02d" % n)
	check(Arena.modal == "result" and not Arena.sim.won, "defeat: the result panel")
	screen.set_process(false)
	Engine.time_scale = 1.0

## Run the screen for `seconds` of its own time in steady 1/60 steps.
func _advance(seconds: float) -> void:
	for i in range(maxi(1, roundi(seconds * 60.0))): screen._process(1.0 / 60.0)

func _frame(name: String) -> void:
	screen.set_process(true)
	screen.queue_redraw()
	await RenderingServer.frame_post_draw
	var image := _picture().get_texture().get_image()
	image.save_png(out_dir + "/%s_%s.png" % [locale, name])

## Where the rim and every gate of every layout land on screen (design pixels), so the
## card's plates can be checked against all eighty layouts without eighty pictures.
func _probe() -> void:
	_no_shop()
	_run_on("spring_grove")
	await _fresh_screen()
	await paint(screen)
	var rim: Array = []
	for point in ArenaGeometry.outline(72):
		var at := screen.view_3d.project(point, 0.0)
		rim.append([snappedf(at.x, 0.1), snappedf(at.y, 0.1)])
	var layouts := {}
	for shape in ArenaGeometry.SHAPE_ORDER:
		for turn in range(ArenaGeometry.TURN_STEPS):
			for mirror in range(2):
				var key := "%s:%d:%d" % [shape, turn, mirror]
				ArenaGeometry.use_layout(key)
				var gates: Array = []
				for lane in range(ArenaGeometry.route_count()):
					var at := screen.view_3d.project(ArenaGeometry.gate_point(lane), 0.0)
					# The beacon as the card draws it: the ring around the road's first
					# point and the three chevrons down the road, as one bounding box.
					var route := ArenaGeometry.route_points(lane)
					var low := Vector2.INF
					var high := -Vector2.INF
					for n in range(24):
						var ring := screen.view_3d.project(route[0] + Vector2.from_angle(n * TAU / 24.0) * 30.0, 0.05)
						low = low.min(ring)
						high = high.max(ring)
					for step in range(3):
						var index := mini(route.size() - 2, roundi((62.0 + step * 44.0) / ArenaGeometry.SAMPLE))
						var along := (route[index + 1] - route[index]).normalized()
						var across := Vector2(-along.y, along.x)
						for corner in [route[index] + along * 15.0, route[index] - along * 9.0 + across * 21.0, route[index] - along * 9.0 - across * 21.0]:
							var mark := screen.view_3d.project(corner, 0.05)
							low = low.min(mark)
							high = high.max(mark)
					gates.append([snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(low.x, 0.1), snappedf(low.y, 0.1), snappedf(high.x, 0.1), snappedf(high.y, 0.1)])
				layouts[key] = gates
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(Arena.theme_index))
	var centre := screen.view_3d.project(Balance.ARENA_CENTER, 0.0)
	# How many bodies and monsters a card can have to list: every battlefield on the
	# stages its rank is drawn for, with this preview's run seed.
	var rows := {}
	for index in range(Roster.THEMES.size()):
		var rank := int(Roster.THEMES[index].get("rank", 1))
		for number in [rank * 2 - 1, rank * 2]:
			Arena.stage_themes[number - 1] = index
			var preview: Dictionary = Arena.stage_preview(number)
			var most := 0
			for row in preview["rows"]: most = maxi(most, (row["monsters"] as Array).size())
			rows["%s:%d" % [String(Roster.THEMES[index]["id"]), number]] = [(preview["rows"] as Array).size(), most]
	var file := FileAccess.open(out_dir + "/probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"rim": rim, "centre": [centre.x, centre.y], "layouts": layouts, "rows": rows}) + "\n")
	file = null

# --------------------------------------------------------------------------- #
# Picture: the window, or an off-screen viewport of the review size
# --------------------------------------------------------------------------- #
func _open_film() -> void:
	var spec := arg("--film", "")
	if spec.is_empty(): return
	var size := Vector2i(int(spec.get_slice("x", 0)), int(spec.get_slice("x", 1)))
	get_window().size = Vector2i(96, 60)
	film = SubViewport.new()
	film.name = "Film"
	film.size = size
	# The game lays out on the 1280x800 design canvas; a smaller picture scales it the
	# way the window's canvas_items stretch does.
	film.size_2d_override = Vector2i(1280, 800)
	film.size_2d_override_stretch = true
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.transparent_bg = false
	film.msaa_2d = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d", 0)) as Viewport.MSAA
	film.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	film.set("oversampling_override", float(size.x) / 1280.0)
	add_child(film)

func _picture() -> Viewport:
	return film if film != null else get_viewport()

func _mount(node: Node) -> void:
	if film != null: film.add_child(node)
	else: add_child(node)

func snap(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := _picture().get_texture().get_image()
	image.save_png(path)
	return image

func _capture(name: String) -> void:
	screen._track_modal()
	await _capture_canvas(screen, name)

func _rect(r: Rect2) -> Array:
	return [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]

func _capture_canvas(canvas: CanvasItem, name: String) -> void:
	Look.text_audit_enabled = true
	Look.text_audit.clear()
	Look.raw_text_audit.clear()
	await paint(canvas)
	var raw: Array = []
	for item in Look.raw_text_audit:
		raw.append({"text": String(item["text"]), "rect": _rect(item["rect"]), "size": int(item["size"]), "canvas": String(item["canvas"]).get_file()})
	var boxes: Array = []
	for item in Look.text_audit:
		boxes.append({"text": String(item["text"]), "box": _rect(item["box"]), "size": int(item["size"]), "lines": int(item["lines"]),
			"width": snappedf(float(item["width"]), 0.1), "height": snappedf(float(item["height"]), 0.1)})
	Look.text_audit_enabled = false
	var zones: Array = []
	var ui: Ui = canvas.get("ui")
	if ui != null:
		for zone in ui.zones: zones.append({"id": String(zone["id"]), "rect": _rect(zone["rect"]), "on": bool(zone["on"])})
	var file_name := "%s_%s" % [locale, name]
	await frames(2)
	await snap(out_dir + "/" + file_name + ".png")
	var entry := {"name": file_name, "locale": locale, "raw": raw, "boxes": boxes, "zones": zones}
	var file := FileAccess.open(out_dir + "/" + file_name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(entry) + "\n")
	file = null
	_index.append(file_name)
