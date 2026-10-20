extends Harness

## Stages and photographs the surfaces of docs/UI_STAGE_STORE.md: the battlefield card,
## the stage HUD, the purchase sheet, the result screen and the title's shop entry.
## It changes no rule: every state is reached through the run, the simulator and a
## stand-in shop, then drawn by the real screens.
##
##   godot --disable-vsync --path . --resolution 96x60 res://tests/stage_store_preview.tscn -- \
##       --film 1280x800 --out build/ui-stage-store/1280x800 [--locales ko,en] [--only card,hud]
##
## Sets: card hud wave banner result shop title help (the default), motion, probe.
## Since 2026-10-19 every ladder stage is a run of its own (docs/STAGE_LADDER_2026-10-19.md):
## a stage's card opens directly (Arena.start_run(seed, n)), the first box is taken through the
## run's API, staged scenes sit in the middle of a wave (_mid_wave) and the boss comes through
## the wave machine (jump_to_boss). `--watchdog SEC` (default 1800) fails a run that stalls.
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
## What the preview is doing now (the set and the last picture), for the watchdog's report.
var _doing := "start"
var _set_name := ""

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_watchdog()
	_open_film()
	_sets = arg("--only", "card,hud,wave,shop,result,banner,title,help").split(",", false)
	_keep_save()
	Run.running = false
	Arena.running = false
	main = load("res://game/main.gd").new()
	_mount(main)
	await frames(3)
	for code in arg("--locales", "ko,en").split(",", false):
		locale = code
		I18n.set_locale(code)
		if "card" in _sets: await _run_set("card", _cards)
		if "hud" in _sets: await _run_set("hud", _hud)
		if "wave" in _sets: await _run_set("wave", _waves)
		if "banner" in _sets: await _run_set("banner", _banners)
		if "result" in _sets: await _run_set("result", _results)
		if "shop" in _sets: await _run_set("shop", _shop)
		if "title" in _sets: await _run_set("title", _title)
		if "help" in _sets: await _run_set("help", _help)
		if "motion" in _sets: await _run_set("motion", _motion)
	if "probe" in _sets: await _run_set("probe", _probe)
	_no_shop()
	_restore_save()
	Arena.running = false
	var file := FileAccess.open(out_dir + "/index.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_index, "  ") + "\n")
	file = null
	finish("Stage card · stage HUD · waves · purchase sheet · result · title previews")

# --------------------------------------------------------------------------- #
# Running the sets: a progress line per set, the save fields they touch, a watchdog
# --------------------------------------------------------------------------- #
## One set, announced on stdout (a stalled run then shows where it stopped).
func _run_set(name: String, body: Callable) -> void:
	_set_name = "%s (%s)" % [name, locale]
	_doing = _set_name
	print("set %s · %s" % [name, locale])
	await body.call()

## A preview that stops making progress (an awaited set that died on a script error, a loop
## that never meets its condition) would otherwise hang until the driver's timeout. After
## `--watchdog` seconds of real time (default 1800) it reports where it was and fails.
func _watchdog() -> void:
	var limit := arg_float("--watchdog", 1800.0)
	if limit <= 0.0: return
	var timer := get_tree().create_timer(limit, true, false, true)
	timer.timeout.connect(func() -> void:
		printerr("!! watchdog: no end after %.0f s; last: %s" % [limit, _doing])
		print("판정: 실패")
		get_tree().quit(2))

## The save fields the sets change in memory (STELLARDEFENSE_NO_SAVE: nothing is written).
func _keep_save() -> void:
	_saved = {"runs": Save.runs, "best_stage": Save.best_stage, "clears": Save.clears, "best_tier": Save.best_tier,
		"speed": Save.speed, "cur_run": Save.cur_run.duplicate(true), "language": I18n.locale,
		"iap_owned": Save.iap_owned.duplicate(), "iap_sandbox": Save.iap_sandbox.duplicate(),
		"stage_unlocked": Save.stage_unlocked, "stage_cleared": Save.stage_cleared, "last_clear": Save.last_clear.duplicate(true),
		"seen_units": Save.seen_units.duplicate(), "unit_best": Save.unit_best.duplicate(),
		"hell_best_wave": Save.hell_best_wave, "hell_squad": Save.hell_squad.duplicate()}

func _restore_save() -> void:
	Save.runs = int(_saved["runs"])
	Save.best_stage = int(_saved["best_stage"])
	Save.clears = int(_saved["clears"])
	Save.best_tier = int(_saved["best_tier"])
	Save.speed = float(_saved["speed"])
	Save.cur_run = _saved["cur_run"]
	Save.iap_owned = _saved["iap_owned"]
	Save.iap_sandbox = _saved["iap_sandbox"]
	Save.stage_unlocked = int(_saved["stage_unlocked"])
	Save.stage_cleared = int(_saved["stage_cleared"])
	Save.last_clear = _saved["last_clear"]
	Save.seen_units = _saved["seen_units"]
	Save.unit_best = _saved["unit_best"]
	Save.hell_best_wave = int(_saved["hell_best_wave"])
	Save.hell_squad = _saved["hell_squad"]
	I18n.set_locale(String(_saved["language"]))

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

## The stage's own monsters (every regular row of its ten waves) spread along every road.
func _crowd(per_lane: int = 5) -> void:
	var sim := Arena.sim
	var spawns := _stage_rows()
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

## Every regular monster row of this stage's waves (no boss, no elite mark), in wave order.
func _stage_rows() -> Array:
	var rows: Array = []
	for w in range(1, Balance.ARENA_WAVES):
		for entry in Arena.wave_spawns(Arena.stage, w):
			if String(entry["m"]["kind"]) != "boss": rows.append(entry["m"])
	return rows if not rows.is_empty() else Roster.theme_pool(Arena.theme_for(1))

## A fresh ladder stage `number` whose battlefield is `theme_id` ("" keeps the ladder's own),
## left on its battlefield card. Every stage is a run of its own since 2026-10-19
## (docs/STAGE_LADDER_2026-10-19.md): no chain of earlier stages is played to reach it.
func _run_on(theme_id: String, number: int = 1) -> void:
	Arena.start_run(SEED, number)
	if not theme_id.is_empty():
		Arena.stage_themes[Arena.stage - 1] = _theme_index(theme_id)
		Arena.sim = null
		Arena._open_stage(Arena.stage)
	_settle_levels()

## The card of stage `number` on `theme_id` (the stage opens directly; see _run_on).
func _card_of(number: int, theme_id: String) -> void:
	_run_on(theme_id, number)
	Arena.sim.events.clear()

## Leave the card: the stage's free first box opens (modal "box", its cards dealt).
func _open_first_box() -> void:
	if Arena.modal == "stage": Arena.confirm_stage()

## Take the box that is open (its best card) and close it.
func _take_box() -> void:
	if Arena.modal != "box": return
	Arena.confirm_summon()
	Arena.close_modal()

## From the card through the free first box into wave `wave` with the review squad. The wave
## has been running a while, its own list is held and the scene stages its monsters
## (_mid_wave). `wave` 0 stays in the stage's first preparation (its countdown held).
func _into_battle(wave: int = 1) -> void:
	_open_first_box()
	_take_box()
	_squad()
	_settle_levels()
	if wave > 0: _mid_wave(wave)
	Arena.sim._spawn_t = 1.0e9

## Wave `n` in progress: opened (ArenaSim.begin_wave) as if long ago, so no banner is due, and
## its list held (_spawn_t) so the staged monsters are the only ones. Common skills can be cast
## (they are refused in a preparation) and the wave never ends on its own.
func _mid_wave(n: int) -> void:
	var sim := Arena.sim
	sim.begin_wave(n)
	sim._spawn_t = 1.0e9
	sim.wave_t = 30.0
	_drop_events(["arena_wave"])

## Remove pending simulator events of these kinds (a staged state is not a fresh moment).
func _drop_events(kinds: Array) -> void:
	var events: Array = Arena.sim.events
	for i in range(events.size() - 1, -1, -1):
		if String(events[i].get("t", "")) in kinds: events.remove_at(i)

## No level-up waits, and none can open the popup in the middle of a staged chain: experience
## is cleared (`sink`: pushed far below zero, so kills while the chain runs never level) and
## an open constellation popup is closed. Callers that show the growth cell set xp after.
func _settle_levels(sink: bool = false) -> void:
	Arena.pending_levels = 0
	Arena.xp = -1.0e9 if sink else 0.0
	if Arena.modal == "talent":
		Arena.talent_offer.clear()
		Arena.close_modal()

## Hold the current wave the real way: the rest of its list steps in at the gates and everything
## on the field falls (bounty, experience) — ArenaSim then pays the defence bonus, emits
## arena_wave_clear and opens the next preparation, where waiting levels are offered.
## Not for the boss wave (its boss's fall wins the stage: _fell_boss).
func _clear_wave_now() -> void:
	var sim := Arena.sim
	if sim.in_prep() or sim.is_boss_wave(sim.wave_no): return
	while sim._wave_spawned < sim._wave_list.size(): sim._spawn_next()
	for mo in sim.monsters: mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	check(sim.in_prep(), "wave held: the next preparation opened")

## The boss wave's preparation with `left` seconds to go and its warning up (the gate named),
## the boss not out yet. Replaces the old `elapsed = ARENA_BOSS_AT - left`.
func _boss_warning(left: float = 2.2) -> void:
	var sim := Arena.sim
	_settle_levels(true)
	sim.jump_to_boss()
	sim.prep_t = minf(left, Balance.ARENA_BOSS_WARNING)
	for i in range(3):
		if sim.boss_warned: break
		sim.step(1.0 / 60.0)
	check(sim.boss_warned and not sim.boss_spawned, "boss warning staged %.1f s before the boss" % left)
	_settle_levels()

## The stage boss steps in at its gate: the end of the boss wave's preparation (jump_to_boss),
## then the ticks that announce it and bring it.
func _boss_arrive() -> void:
	var sim := Arena.sim
	_settle_levels(true)
	if not sim.boss_spawned:
		if not (sim.in_prep() and sim.is_boss_wave(sim.wave_no)): sim.jump_to_boss()
		sim.prep_t = minf(sim.prep_t, 2.0 / 60.0)
		for i in range(10):
			if sim.boss_spawned: break
			sim.step(1.0 / 60.0)
	check(sim.boss_spawned, "the stage boss stepped in")
	_settle_levels()

## The crystal breaks (any untouchable seconds are waived first). An owner with a
## revival ticket left is revived by the simulator (a 5-star hero joins); otherwise the run ends.
func _break_crystal() -> void:
	Arena.sim.invuln_t = 0.0
	Arena.sim._damage_crystal(1.0e9, Balance.ARENA_CENTER)

## A revival ticket gives no gold since 2026-10-19 (DLC D2): a 5-star hero joins, on the field while
## there is room, else on the bench (ArenaRun.revive_gift).
func _check_revive_hero() -> void:
	var gift: Dictionary = Arena.revive_gift
	check(not gift.is_empty() and int(gift.get("tier", -1)) == Balance.TIER_MAX and String(gift.get("where", "")) in ["field", "bench"],
		"the revival brings a 5-star hero (%s)" % JSON.stringify({"unit": String(gift.get("unit", {}).get("id", "")), "tier": gift.get("tier", -1), "where": gift.get("where", "")}))

## The screen's own step: it notices a revival here and starts its banner.
func _notice() -> void:
	screen._process(1.0 / 30.0)

## The stage boss walks in and falls. Leaves the simulator inside its clear beat (clear_t > 0);
## every ladder stage is won when that beat has run (ARENA_CLEAR_DELAY).
func _fell_boss() -> void:
	var sim := Arena.sim
	_boss_arrive()
	_settle_levels(true)
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	check(sim.clear_t > 0.0, "the boss fell: the clear beat runs")

## Run the simulator through the clear beat to the stage's result (bounded).
func _run_clear() -> void:
	for i in range(roundi((Balance.ARENA_CLEAR_DELAY + 0.3) * 30.0)):
		if Arena.modal == "result": break
		Arena.sim.step(1.0 / 30.0)

## Let the field play `seconds` (the screen's own step and draw, 30 a second) so bodies that just
## fell finish dying before a still is taken; a held screen would keep them standing. The
## simulator runs too (a preparation counts down, a wave goes on).
func _let_fall(seconds: float = 1.7) -> void:
	for i in range(roundi(seconds * 30.0)):
		screen._process(1.0 / 30.0)
		screen.queue_redraw()
		await frames(1)

## Tap the screen's own zone `id` when it is drawn and on; otherwise (a surface that is not
## wired yet) do what the zone stands for. True when the real zone answered.
func _act(id: String, fallback: Callable) -> bool:
	# A running screen notices a window change every frame; a held one only when asked.
	screen._track_modal()
	await paint(screen)
	if tap(screen, id): return true
	fallback.call()
	return false

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
## Battlefield cards (one per ladder stage since 2026-10-19): STAGE 1 as the ladder deals it,
## the first stages, a chapter's end (its boss is a chapter boss), a stage past the four-kind mix
## and the last stage; one, three and four gates; dark and bright fields. "" keeps the
## ladder's own battlefield.
const CARDS := [
	[1, ""],                   # the ladder's first stage, as a new player meets it
	[1, "mushroom_hollow"],    # coil, one gate, dark forest
	[2, "first_snow_hills"],   # fork, four gates, bright snow (flyers from STAGE 2)
	[3, "calm_lake"],          # spiral, four gates
	[5, "misty_cedar"],        # pinwheel, three gates
	[5, "drift_ice_sea"],      # coil, one gate, bright ice
	[7, "desert_mesa"],        # rock biome: immune element on the card (immune bodies from STAGE 4)
	[9, "worldtree_roots"],    # four bodies: three chips under the main block
	[10, "volcano_crater"],    # fork, chapter boss, dark
	[10, "ice_spire_field"],   # blades, chapter boss, bright
	[57, ""],                  # mid-ladder: four-kind mix, rank 3
	[100, ""],                 # the last stage: three digits, rank 5, chapter boss
]

func _card_name(number: int, id: String) -> String:
	return "card_s%02d_%s" % [number, id if not id.is_empty() else "ladder"]

func _cards() -> void:
	_no_shop()
	var wanted := arg("--cards", "")
	for entry in CARDS:
		var number := int(entry[0])
		var id := String(entry[1])
		if not wanted.is_empty() and not (id in wanted.split(",")) and not (str(number) in wanted.split(",")): continue
		_card_of(number, id)
		await _fresh_screen()
		var shown := String(Arena.theme_for(1)["id"])
		check(Arena.modal == "stage" and Arena.stage == number and (id.is_empty() or shown == id), "card staged: %d %s" % [number, shown])
		await _capture(_card_name(number, id))
		check(not zone_of(screen, "stage:start").is_empty() and bool(zone_of(screen, "stage:start")["on"]), "card keeps its one action: %d %s" % [number, shown])

## Top strip: the three plain speed chips (free for everyone), and the DLC crest with the
## revival tickets left: none without the DLC, all of them, one less after every break, and
## the ring while the reformed crystal cannot be hurt. Then what shares the row under the strip.
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
	# A build without a shop counts as owning the DLC.
	_no_shop()
	_run_on("misty_cedar")
	_into_battle()
	_crowd()
	await _fresh_screen()
	check(Arena.revives_left() == Balance.ARENA_REVIVE_USES, "no shop: the revival tickets are there")
	await _capture("hud_blessing_noshop")
	# An owner: every ticket, and one less after every break (a 5-star hero joins each time).
	var uses: int = Balance.ARENA_REVIVE_USES
	for field in ["misty_cedar", "first_snow_hills"]:
		_use_shop([Store.GUARDIAN])
		_run_on(field)
		_into_battle()
		_crowd()
		await _fresh_screen()
		if field == "misty_cedar": await _capture("hud_blessing_%d" % uses)
		for left in range(uses - 1, -1, -1):
			_break_crystal()
			check(Arena.running and Arena.revives_left() == left, "revival leaves %d" % left)
			if left == uses - 1 and field == "misty_cedar":
				Arena.sim.invuln_t = Balance.ARENA_REVIVE_INVULN * 0.62
				await _capture("hud_blessing_%d_untouchable" % left)
			Arena.sim.invuln_t = 0.0
			if field == "misty_cedar" or left == 0:
				await _capture("hud_blessing_%d%s" % [left, "" if field == "misty_cedar" else "_bright"])
	# Everything that can share the area under the strip at once: the ward's countdown, the
	# boss warning of the last preparation, then the boss's bar.
	_use_shop([Store.GUARDIAN])
	_run_on("calm_lake")
	_into_battle()
	_crowd()
	Arena.gold = 999
	check(Arena.sim.cast_skill("ward"), "the ward casts mid-wave")
	_boss_warning(2.2)
	await _fresh_screen()
	screen.set_speed(3.0)
	await _capture("hud_ward_boss_warning")
	_boss_arrive()
	await _capture("hud_ward_boss_bar")
	screen.set_speed(1.0)

## The wave machine on the HUD (docs/STAGE_LADDER_2026-10-19.md): the stage's first preparation
## (its countdown, the box open), a preparation between waves, a wave starting, a wave under way
## (the box waits for the preparation), the elite wave with its elite out, a held wave (방어
## 성공), the last preparation with the boss warning, the boss wave with its escort, and the end
## of a late wave with two left. The HUD's pictures are ArenaHud's (D6); this stages the states.
func _waves() -> void:
	_use_shop([Store.GUARDIAN])
	# The first preparation, right after the free first box.
	_run_on("misty_cedar", 3)
	_into_battle(0)
	check(Arena.sim.in_prep() and Arena.sim.wave_no == 1 and Arena.summon_block() in ["", "gold"], "the stage starts in its first preparation, the box open")
	await _fresh_screen()
	await _capture("wave_prep_first")
	# Wave 1 opens ("바로 시작" when the HUD has it, else the simulator's own skip).
	await _act("wave:start", func() -> void: Arena.sim.skip_prep())
	_notice()
	check(not Arena.sim.in_prep() and Arena.sim.wave_no == 1, "the first wave opened")
	await _capture("wave_start_w01")
	# A wave under way: monsters on the roads, the box waits for the next preparation. The HUD's
	# banners age on the screen's clock: play past the wave's banner (ArenaHud.WAVE_BANNER).
	_crowd()
	await _let_fall(1.9)
	check(Arena.summon_block() == "wave", "the box waits for the preparation during a wave")
	await _capture("wave_battle_w01")
	# Held: 방어 성공 and the preparation for wave 2 (the fallen finish dying first).
	_settle_levels(true)
	_clear_wave_now()
	await _let_fall(1.2)
	_settle_levels()
	await _capture("wave_clear_w01")
	# The elite wave: its elite (the stage's heavy, marked) on the road among the wave.
	_mid_wave(5)
	var sim := Arena.sim
	sim._spawn_t = 0.0
	var elite: Dictionary = {}
	while sim._wave_spawned < sim._wave_list.size() and elite.is_empty():
		var entry: Dictionary = sim._wave_list[sim._wave_spawned]
		sim._spawn_next()
		if bool(entry.get("elite", false)): elite = sim.monsters[-1]
	sim._spawn_t = 1.0e9
	check(not elite.is_empty() and bool(elite.get("elite", false)), "wave 5 brings its elite")
	_spread_on_roads(0.18, 0.62)
	_notice()
	await _capture("wave_elite_w05")
	# Held: the elite falls with its wave.
	_settle_levels(true)
	_clear_wave_now()
	await _let_fall(1.2)
	_settle_levels()
	await _capture("wave_clear_w05")
	# A late wave with two of it left (sturdy, so they are still there when the rest has gone).
	_mid_wave(9)
	while sim._wave_spawned < sim._wave_list.size(): sim._spawn_next()
	_spread_on_roads(0.30, 0.80)
	for i in range(sim.monsters.size()):
		if i < sim.monsters.size() - 2: sim.monsters[i]["hp"] = 0.0
		else:
			sim.monsters[i]["max"] = float(sim.monsters[i]["max"]) * 40.0
			sim.monsters[i]["hp"] = float(sim.monsters[i]["max"]) * 0.6
	sim._cache_positions()
	_settle_levels(true)
	sim._reap()
	await _let_fall(1.9)
	_settle_levels()
	check(sim.wave_left() == 2 and not sim.in_prep(), "a late wave with two left (%d)" % sim.wave_left())
	await _capture("wave_left_w09")
	# The last preparation: the boss warning names the gate. The boss wave's preparation is long
	# (ARENA_PREP_BOSS): by its warning the 방어 성공 banner has gone — a fresh screen has no banner.
	_boss_warning(2.6)
	await _fresh_screen()
	await _capture("wave_boss_warning")
	# The boss wave: the boss and the first of its escort.
	_boss_arrive()
	for i in range(int(1.6 * 60.0)): sim.step(1.0 / 60.0)
	_settle_levels()
	sim._spawn_t = 1.0e9
	await _capture("wave_boss_w10")

## Spread the monsters that just stepped in at the gates along their roads, between
## fractions `from` and `to` of each road, so a still shows them on the field.
func _spread_on_roads(from: float, to: float) -> void:
	var sim := Arena.sim
	var count := sim.monsters.size()
	for i in range(count):
		var mo: Dictionary = sim.monsters[i]
		var lane := int(mo.get("route", i % ArenaGeometry.route_count()))
		var path := ArenaGeometry.route_points(lane)
		var along := lerpf(from, to, float(i) / float(maxi(1, count - 1)))
		var at := clampi(int(path.size() * along), 0, path.size() - 3)
		mo["pos"] = path[at]
		mo["vel"] = (path[at + 1] - path[at]).normalized()
	sim._rebuild_navigation()
	sim._cache_positions()

## The stage boss's fall (every ladder boss ends its stage: the clear banner with `final`, then
## the result), alone and with the ward and the boss strip; a chapter boss on a dark and a bright
## field; the revival banner (the 5-star hero who joins) first and last of a stage.
func _banners() -> void:
	_use_shop([Store.GUARDIAN])
	_run_on("spring_grove")
	_into_battle()
	_crowd()
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.42
	await _fresh_screen()
	Arena.gold = 999
	Arena.sim.cast_skill("ward")
	_fell_boss()
	check(Arena.sim.clear_t > 0.0, "stage clear banner state")
	_notice()
	await _capture("banner_clear_s01")
	# A later stage of the first chapter.
	_card_of(9, "peak_cliffs")
	_into_battle()
	await _fresh_screen()
	_fell_boss()
	_notice()
	await _capture("banner_clear_s09")
	# A chapter boss falls (STAGE 10): the final banner, on a dark and on a bright field. The
	# ward is still up beside it on the first one.
	for id in ["volcano_crater", "ice_spire_field"]:
		_card_of(10, id)
		_into_battle()
		_crowd()
		Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.42
		await _fresh_screen()
		if id == "volcano_crater":
			Arena.gold = 999
			Arena.sim.cast_skill("ward")
		_fell_boss()
		check(Arena.sim.clear_t > 0.0 and Arena.sim.final_stage() and Arena.running and Arena.modal == "", "chapter boss: clear beat before the result")
		_notice()
		await _capture("banner_final_" + id)
	# Revival banners: the stage's first ticket on STAGE 1, under a boss bar with the ward up.
	_use_shop([Store.GUARDIAN])
	_run_on("first_snow_hills")
	_into_battle()
	_crowd()
	await _fresh_screen()
	Arena.gold = 999
	Arena.sim.cast_skill("ward")
	_boss_arrive()
	Arena.sim.shield = 0.0
	_break_crystal()
	check(Arena.sim.revives == 1 and Arena.running, "first revival")
	_check_revive_hero()
	_notice()
	await _capture("banner_revive_first_s01")
	# The stage's last ticket on a chapter's end (none left), on a dark and on a bright field.
	if Balance.ARENA_REVIVE_USES > 1:
		for id in ["volcano_crater", "ice_spire_field"]:
			_card_of(10, id)
			_into_battle()
			_crowd()
			await _fresh_screen()
			for n in range(Balance.ARENA_REVIVE_USES):
				_break_crystal()
				_check_revive_hero()
				_notice()
			check(Arena.sim.revives == Balance.ARENA_REVIVE_USES and Arena.revives_left() == 0 and Arena.running, "last revival: none left")
			await _capture("banner_revive_last_s10_" + id)
	# The banner has gone and the seconds still run: the crest alone carries them.
	screen.set("_revive_age", 99.0)
	Arena.sim.invuln_t = Balance.ARENA_REVIVE_INVULN * 0.3
	await _capture("banner_revive_after")

func _results() -> void:
	# A build without a shop counts as owning the DLC: a defeat there has used every ticket,
	# there is nothing to offer, and the panel says why the crystal stayed broken.
	_no_shop()
	_card_of(4, "quarry_pit")
	_into_battle()
	_crowd()
	Arena.kills = 318
	for n in range(Balance.ARENA_REVIVE_USES + 1): _break_crystal()
	await _fresh_screen()
	check(Arena.modal == "result" and Arena.sim.revives == Balance.ARENA_REVIVE_USES and zone_of(screen, "result:guardian").is_empty(), "no shop: every ticket used, no offer")
	await _capture("result_defeat_noshop")
	# Defeat with a shop and no DLC: one quiet offer.
	_use_shop()
	_card_of(4, "quarry_pit")
	_into_battle()
	_crowd()
	Arena.kills = 318
	_break_crystal()
	await _fresh_screen()
	check(Arena.modal == "result" and not zone_of(screen, "result:guardian").is_empty(), "defeat without the DLC: the offer")
	await _capture("result_defeat_offer")
	screen.ui.pressed = "result:guardian"
	await _capture("result_defeat_offer_pressed")
	screen.ui.pressed = ""
	check(tap(screen, "result:guardian") and screen.store.opened and screen.store.focus == Store.GUARDIAN, "offer opens the sheet on the DLC")
	await _capture("result_offer_sheet")
	if screen.has_method("_action"): screen._action("store:close")
	else: screen.store.close()
	# An owner who used every ticket, on a late stage: no offer, and the row says so.
	_use_shop([Store.GUARDIAN])
	_card_of(8, "blizzard_plateau")
	_into_battle()
	_crowd()
	Arena.kills = 1204
	for n in range(Balance.ARENA_REVIVE_USES + 1): _break_crystal()
	await _fresh_screen()
	check(Arena.modal == "result" and zone_of(screen, "result:guardian").is_empty(), "every ticket used: no offer")
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
	# Victory without a revival and one that needed two (a chapter's end), then the last stage
	# of the ladder (no next stage after it).
	for entry in [[10, "polar_night", 0], [10, "polar_night", 2], [100, "", 0]]:
		var used := mini(int(entry[2]), Balance.ARENA_REVIVE_USES)
		_use_shop([Store.GUARDIAN])
		_card_of(int(entry[0]), String(entry[1]))
		_into_battle()
		Arena.kills = 2480
		for n in range(used): _break_crystal()
		Arena.sim.invuln_t = 0.0
		_fell_boss()
		# The boss falls with the clear beat; the result follows it.
		_run_clear()
		check(Arena.sim.won and Arena.modal == "result" and Arena.sim.revives == used, "victory staged: STAGE %d" % int(entry[0]))
		await _fresh_screen()
		var name := "result_victory"
		if int(entry[0]) == 100: name = "result_victory_s100"
		elif used > 0: name = "result_victory_blessed"
		await _capture(name)

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

## The title over the ladder's records (Save.stage_unlocked · stage_cleared · last_clear): a new
## player, one who cleared STAGE 7 (the last clear named, STAGE 8 next) and one who cleared all.
func _ladder_record(state: String) -> void:
	var cleared: int = {"first": 0, "stage7": 7, "cleared": Balance.ARENA_LADDER}[state]
	Save.stage_cleared = cleared
	Save.stage_unlocked = mini(cleared + 1, Balance.ARENA_LADDER)
	Save.last_clear = {} if cleared == 0 else {"stage": cleared, "theme": String(Roster.THEMES[Arena.ladder_theme(cleared)]["id"])}
	Save.best_stage = mini(cleared, 10)
	Save.clears = cleared

func _title() -> void:
	Save.cur_run = {}
	Save.best_tier = 6
	for state in ["first", "stage7", "cleared"]:
		_ladder_record(state)
		_use_shop()
		main.show_title()
		await frames(6)
		await _capture_canvas(main.screen, "title_" + state)
	_ladder_record("stage7")
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
	screen.set("_card_key", "")
	await frames(3)
	await _frame("motion_card_00")
	for n in range(1, 18):
		_advance(0.07)
		await _frame("motion_card_%02d" % n)
	# A wave is held: 방어 성공 lands, the preparation counts down, the next wave opens.
	_into_battle(2)
	_crowd(2)
	_settle_levels(true)
	_advance(0.1)
	await frames(2)
	_clear_wave_now()
	var shot := 0
	for n in range(16):
		_advance(0.1)
		await _frame("motion_wave_%02d" % shot)
		shot += 1
	var guard := 0
	while Arena.sim.in_prep() and guard < 40:
		_advance(0.25)
		await _frame("motion_wave_%02d" % shot)
		shot += 1
		guard += 1
	for n in range(12):
		_advance(0.1)
		await _frame("motion_wave_%02d" % shot)
		shot += 1
	check(not Arena.sim.in_prep() and Arena.sim.wave_no == 3, "wave: the preparation ran out into the next wave")
	# A stage boss falls: the clear banner lands, holds, and the victory panel takes over.
	_settle_levels(true)
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.5
	_fell_boss()
	for n in range(26):
		_advance(0.1)
		await _frame("motion_clear_%02d" % n)
	check(Arena.modal == "result" and Arena.sim.won, "clear: the stage boss's beat ends in the victory panel")
	# Revival: the banner lands with the 5-star hero who joins, the spent pip goes out and the
	# crest's number drops; then the banner fades and the crest alone carries the seconds.
	_card_of(3, "forge_canyon")
	_into_battle()
	_crowd()
	_settle_levels(true)
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
	# The second ticket of the stage, right after: the count goes on down.
	if Balance.ARENA_REVIVE_USES > 1:
		_break_crystal()
		for n in range(25, 33):
			_advance(0.1)
			await _frame("motion_revive_%02d" % n)
	# A chapter boss (STAGE 10): the banner lands, holds for the clear delay, and the victory
	# panel takes over. Frames every 0.05 s, every one around the landing and the handover.
	_card_of(10, "volcano_crater")
	_into_battle()
	_crowd()
	_settle_levels(true)
	Arena.kills = 2480
	_advance(0.1)
	await frames(2)
	_fell_boss()
	shot = 0
	for n in range(34):
		_advance(0.05)
		var age: float = Balance.ARENA_CLEAR_DELAY - Arena.sim.clear_t if Arena.sim.clear_t > 0.0 else 99.0
		if age < 0.5 or age > Balance.ARENA_CLEAR_DELAY - 0.2 or n % 2 == 0:
			await _frame("motion_final_%02d" % shot)
			shot += 1
	# The hand-over: the shade comes in, the banner dissolves, the card rises, the number
	# settles. One second in 0.05 s frames.
	for n in range(20):
		_advance(0.05)
		await _frame("motion_final_%02d" % shot)
		shot += 1
	check(Arena.modal == "result" and Arena.sim.won, "chapter boss: the beat ends in the victory panel")
	# A defeat arrives through the same entrance, without a banner.
	_use_shop()
	_run_on("kiln_yard")
	_into_battle()
	_crowd()
	_settle_levels(true)
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
	# How many bodies and monsters a card can have to list: every battlefield on the first
	# and the last stage of the two chapters its rank is drawn for (ArenaRun.chapter_rank).
	var rows := {}
	for index in range(Roster.THEMES.size()):
		var rank := int(Roster.THEMES[index].get("rank", 1))
		for number in [(rank - 1) * 20 + 1, rank * 20]:
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
	_doing = "%s, last picture %s" % [_set_name, file_name]
	await frames(2)
	await snap(out_dir + "/" + file_name + ".png")
	var entry := {"name": file_name, "locale": locale, "raw": raw, "boxes": boxes, "zones": zones}
	var file := FileAccess.open(out_dir + "/" + file_name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(entry) + "\n")
	file = null
	_index.append(file_name)
