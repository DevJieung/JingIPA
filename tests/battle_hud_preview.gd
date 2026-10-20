extends Harness

## Photographs the battle HUD of the 2026-10-19 feedback (D6 — build/feedback-2026-10-19/D6/RECORD.md):
## the skill buttons in every state and their ready pop, the starfall's aim (button latched, the hint,
## the 3D ring), the empty guardian slot, the wave cell and its banners, the elite's bar, the boss
## strip, the stage card (ladder, chapter), the results (win with 「다음 STAGE」, defeat with the DLC
## strip, Hellbound) and the revival banner with its 5-star hero. Every state is reached through the
## run and the simulator, then drawn by the real screen.
##
##   godot --disable-vsync --path . --resolution 96x60 res://tests/battle_hud_preview.tscn -- \
##       --film 1280x800 --out build/feedback-2026-10-19/D6/1280x800 [--locales ko,en] [--only a,b]
##
## Stills are taken with the screen held (its motion settled); `motion_*` sets advance the screen's
## clock by 1/30 s per picture (Engine.time_scale 0, so nothing moves between pictures but what the
## harness steps). Every still comes with <name>.json: the text drawn (fitted sizes and boxes) and
## the touch zones.

## A shop that never sells anything owned: the defeat strip's stand-in (tests/stage_store_preview.gd).
class Shop extends RefCounted:
	const NAME := "test"
	var store: Node
	var owned: Array = []
	var prices := {"guardian": "₩2,200"}
	func start() -> void:
		for id in prices: store.set_price(String(id), String(prices[id]))
		store.set_owned(owned)
	func sells(_id: String) -> bool: return true
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void:
		store.set_owned(owned)
		store.finish_restore(true)
	func buy(product: Dictionary) -> void:
		store.finish_purchase(String(product["id"]), "cancelled")

const SEED := 20261019
const BRIGHT := "first_snow_hills"
const DARK := "polar_night"
const SQUAD := ["brasa", "limne", "echo", "morrigan", "pip", "caden"]
var out_dir := "build/feedback-2026-10-19/D6/1280x800"
var film: SubViewport
var main: Node2D
var screen: ArenaScreen
var locale := "ko"
var _only: PackedStringArray = []
var _index: Array = []

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only := arg("--only", "")
	if not only.is_empty(): _only = only.split(",", false)
	_open_film()
	_watchdog()
	var locales := arg("--locales", "ko,en").split(",", false)
	for code in locales:
		locale = code
		I18n.set_locale(code)
		await _run_sets()
	var report := FileAccess.open(out_dir + "/index.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_index, "  "))
	finish("전투 HUD 미리보기")

func _wants(name: String) -> bool:
	return _only.is_empty() or name in _only

func _run_sets() -> void:
	if _wants("prep"): await _set_prep()
	if _wants("skills"): await _set_skills()
	if _wants("pop"): await _set_pop()
	if _wants("aim"): await _set_aim()
	if _wants("waves"): await _set_waves()
	if _wants("boss"): await _set_boss()
	if _wants("card"): await _set_card()
	if _wants("result"): await _set_result()
	if _wants("revive"): await _set_revive()
	if _wants("hell"): await _set_hell()
	if _wants("names"): await _set_names()

# --------------------------------------------------------------------------- #
# Staging
# --------------------------------------------------------------------------- #
func _theme_index(id: String) -> int:
	for i in range(Roster.THEMES.size()):
		if String(Roster.THEMES[i]["id"]) == id: return i
	return 0

## A fresh stage on its own screen. `field` picks the battlefield ("" keeps the ladder's); the
## first box is taken (its best card) and closed, so the stage stands in its first preparation.
func _open(stage: int, field: String = "", heroes: int = 6, card := false) -> void:
	Engine.time_scale = 1.0
	Store._owned.clear()
	Store.use_backend(null)
	Arena.start_run(SEED, stage)
	if main == null:
		main = load("res://game/main.gd").new()
		_mount(main)
		await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	await frames(3)
	if card: return
	if not field.is_empty():
		check(Arena.choose_theme(_theme_index(field)), "battlefield %s chosen" % field)
	else:
		check(Arena.confirm_stage(), "stage card confirmed")
	if Arena.modal == "box":
		Arena.confirm_summon()
		Arena.close_modal()
	check(Arena.modal.is_empty(), "the stage is in its first preparation")
	# The screen follows the windows the harness opened and closed (its _process is held).
	screen._track_modal()
	_heroes(heroes)
	Arena.xp = -1e9
	Arena.pending_levels = 0
	screen.view_3d._follow_offset = Vector3.ZERO
	screen.view_3d._camera_initialized = false
	await paint(screen)

func _heroes(count: int) -> void:
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(count):
		Arena.gain_hero(Roster.unit_by_id(SQUAD[i]), [9, 5, 7, 3, 6, 4][i])
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + i * TAU / 6) * 150
	Arena.sim.refresh_heroes()
	Arena.selected = 0

## Step the battle `seconds` (60 ticks a second), the 3D world following once at the end.
func _step(seconds: float) -> void:
	for n in range(roundi(seconds * 60.0)):
		Arena.sim.step(1.0 / 60.0)
		if not Arena.modal.is_empty(): break

## Open wave `n` and let its first monsters walk in (a few seconds of the real battle).
func _wave(n: int, seconds: float = 2.6) -> void:
	Arena.sim.begin_wave(n)
	await paint(screen)
	_step(seconds)
	await paint(screen)

## Move the wave's monsters to visible spots along the roads (bars over bodies, not at the rim).
func _spread() -> void:
	var lanes := ArenaGeometry.route_count()
	var n := 0
	for mo in Arena.sim.monsters:
		var route := ArenaGeometry.route_points(n % lanes)
		mo["pos"] = route[mini(route.size() - 1, 9 + (n / lanes) * 4)]
		mo["vel"] = ArenaGeometry.road_direction(mo["pos"])
		if String(mo["kind"]) != "boss": mo["hp"] = float(mo["max"]) * (0.45 + 0.1 * float(n % 4))
		n += 1

## The harness holds the screen's clock, so a banner would stay up for ever: let it end.
func _age_banners() -> void:
	screen.hud._bclock += 10.0

func _kill_all() -> void:
	Arena.sim._wave_spawned = Arena.sim._wave_list.size()
	for mo in Arena.sim.monsters: mo["hp"] = 0.0
	Arena.sim.step(1.0 / 60.0)

# --------------------------------------------------------------------------- #
# Sets
# --------------------------------------------------------------------------- #
## The first preparation: 「바로 시작」 with its countdown, the jewel box ready (and its first-box
## and gold-short and wave states), the skills waiting for the wave, three empty slots (B3).
func _set_prep() -> void:
	for field in [BRIGHT, DARK]:
		await _open(1, field, 3)
		Arena.gold = 130
		Arena.sim.prep_t = 5.4
		await _shot("prep_%s" % field)
	Arena.gold = 40
	await _shot("prep_box_gold")
	# The stage's first box (summon_count 0): 「첫 상자 무료」 in the value row, at 13 px.
	Arena.gold = 130
	Arena.summon_count = 0
	await _shot("prep_box_first")
	var first_size := 0
	for item in Look.text_audit:
		if String(item["text"]) == I18n.t("arena.box_free"): first_size = int(item["size"])
	check(first_size >= 12, "the first box's label is drawn at a readable size (%d)" % first_size)
	Arena.summon_count = 1
	Arena.sim.prep_t = 2.2
	screen.ui.pressed = "wave:start"
	await _shot("prep_start_pressed")
	screen.ui.pressed = ""
	check(tap(screen, "wave:start"), "「바로 시작」 answers")
	check(Arena.sim.prep_left() <= 0.001, "the preparation ends")

## A wave with each skill in another state: ready, cooling, short of gold; then no target, spent,
## the ward's shield, the stage's clear beat.
func _set_skills() -> void:
	for field in [BRIGHT, DARK]:
		await _open(2, field, 6)
		await _wave(3)
		_spread()
		Arena.gold = 45
		Arena.sim.skill_cooldowns["freeze"] = 12.4
		await _shot("skills_mixed_%s" % field)
	check(String(Arena.sim.skill_state("blast")["block"]) == "", "blast ready with 45 G")
	check(String(Arena.sim.skill_state("ward")["block"]) == "gold", "ward short of gold")
	check(not bool(zone_of(screen, "skill:ward").get("on", true)), "a skill short of gold does not answer")
	Arena.gold = 999
	Arena.sim.skill_cooldowns["freeze"] = 0.0
	await _shot("skills_all_ready")
	Arena.sim.skill_uses["ward"] = Arena.sim.skill_max_uses("ward")
	Arena.sim.skill_cooldowns["blast"] = 20.0
	await _shot("skills_cool_spent")
	Arena.sim.skill_uses["ward"] = 0
	Arena.sim.skill_cooldowns["blast"] = 0.0
	Arena.sim.skill_cooldowns["ward"] = 0.0
	await paint(screen)
	check(tap(screen, "skill:ward"), "ward casts")
	await _shot("skills_warding")
	var keep: Array = Arena.sim.monsters.duplicate()
	Arena.sim.monsters.clear()
	await _shot("skills_no_target")
	Arena.sim.monsters = keep

## The moment a skill turns ready: its pop, frame by frame (the screen's clock runs).
func _set_pop() -> void:
	await _open(2, DARK, 6)
	await _wave(3)
	_spread()
	Arena.gold = 999
	Arena.sim.skill_cooldowns["freeze"] = 30.0
	Arena.sim.skill_cooldowns["blast"] = 0.0
	Arena.sim.skill_cooldowns["ward"] = 0.0
	Engine.time_scale = 0.0
	screen.set_process(true)
	# Let the pops of the wave's start play out first (the held screen kept its clock still).
	for n in range(30):
		screen._process(1.0 / 30.0)
		await paint(screen)
	Arena.sim.skill_cooldowns["freeze"] = 0.2
	for n in range(30):
		screen._process(1.0 / 30.0)
		await _frame("motion_pop_%02d" % n)
	screen.set_process(false)
	Engine.time_scale = 1.0

## The starfall's aim: armed with no finger yet, a finger on the field, a spot the star cannot take,
## and a few frames of the hint and the ring.
func _set_aim() -> void:
	for field in [BRIGHT, DARK, "calm_lake"]:
		await _open(2, field, 6)
		await _wave(4)
		_spread()
		Arena.gold = 999
		screen._track_modal()
		await paint(screen)
		check(tap(screen, "skill:blast"), "starburst arms")
		check(screen.has_method("aiming") and screen.aiming(), "the screen is aiming")
		await _shot("aim_armed_%s" % field)
		# The hint keeps off the roads where the monsters step in (D3: the old top pill hid a gate).
		var cancel_zone := zone_of(screen, "aim:cancel")
		check(not cancel_zone.is_empty(), "the aim hint has its cancel button")
		check(zone_of(screen, "aim:hint").is_empty(), "the hint's body swallows no press")
		if has_arg("--debug-aim"):
			for lane in range(ArenaGeometry.route_count()):
				var gate := ArenaGeometry.gate_point(lane)
				print("gate %d logical %s screen %s out %s" % [lane, gate, screen.view_3d.project(gate, 0.0),
					screen.view_3d.project(gate + (gate - Balance.ARENA_CENTER).normalized() * 300.0, 0.0)])
			for x in [496.0 - 256.0, 16.0, 976.0 - 512.0]:
				var r := Rect2(x, 744, 512, 44)
				print("candidate x %d hits %d" % [x, screen.hud._road_hits(r.grow(40.0))])
		var pill_y := Rect2(cancel_zone["rect"]).position.y
		check(pill_y > ArenaScreen.BATTLEFIELD.end.y - 80.0, "the aim hint stands on the battle box's bottom edge (%d)" % pill_y)
		var target := screen.view_3d.project(Vector2(Arena.sim.monsters[0]["pos"]) if not Arena.sim.monsters.is_empty() else Balance.ARENA_CENTER, 0.0)
		_touch(0, target, true)
		await _real_wait(0.35)
		await _shot("aim_finger_%s" % field)
		var cooled := float(Arena.sim.skill_cooldowns["blast"])
		_touch(0, target, false)
		check(float(Arena.sim.skill_cooldowns["blast"]) > cooled, "lifting the finger on the field casts the star")
	_rearm()
	await paint(screen)
	check(tap(screen, "skill:blast"), "starburst arms again")
	_touch(1, Vector2(28, 780), true)
	await _real_wait(0.35)
	await _shot("aim_invalid")
	_touch(1, Vector2(28, 780), false)
	_rearm()
	await paint(screen)
	check(tap(screen, "skill:blast"), "armed for the motion")
	var spot := screen.view_3d.project(Balance.ARENA_CENTER + Vector2(120, -60), 0.0)
	_touch(2, spot, true)
	Engine.time_scale = 0.0
	screen.set_process(true)
	for n in range(16):
		screen._process(1.0 / 30.0)
		await _frame("motion_aim_%02d" % n)
	_touch(2, spot, false)
	for n in range(10):
		screen._process(1.0 / 30.0)
		await _frame("motion_cast_%02d" % n)
	screen.set_process(false)
	Engine.time_scale = 1.0

## The 3D aim ring draws itself in on the wall clock (ArenaWorld.AIM_DRAW_IN): let it, repainting
## so the screen keeps handing the world its aim.
func _real_wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await paint(screen)

## The starburst ready again (a cast spent its cooldown and a use).
func _rearm() -> void:
	Arena.sim.skill_cooldowns["blast"] = 0.0
	Arena.sim.skill_uses["blast"] = 0
	Arena.gold = 999

func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	screen._input(e)

## Waves: the wave running (monsters left), its banner, a wave held (「방어 성공!」), the elite wave's
## banner, the elite stepping in and its bar.
func _set_waves() -> void:
	await _open(3, BRIGHT, 6)
	Arena.gold = 210
	Arena.sim.skip_prep()
	_step(0.1)
	await _shot("wave_banner_1")
	_step(2.4)
	_spread()
	_age_banners()
	await _shot("wave_running")
	_kill_all()
	await _shot("wave_held")
	# A window over the field: the banner neither shows through it nor runs out behind it.
	check(Arena.open_modal("talent"), "the constellations open over the field")
	screen._track_modal()
	await _shot("wave_held_under_window")
	check(Arena.close_modal(), "the constellations close")
	screen._track_modal()
	await _shot("wave_held_after_window")
	Arena.sim.prep_t = 0.05
	_step(0.1)
	await _shot("wave_banner_next")
	# The elite wave: its banner, then the elite itself.
	Arena.sim.begin_wave(4)
	await paint(screen)
	_kill_all()
	await paint(screen)
	Arena.sim.prep_t = 0.05
	_step(0.1)
	await _shot("wave_banner_elite")
	var found := false
	for n in range(600):
		Arena.sim.step(1.0 / 60.0)
		for mo in Arena.sim.monsters:
			if bool(mo.get("elite", false)): found = true
		if found: break
	check(found, "the elite steps in")
	_spread()
	await _shot("wave_elite")
	Engine.time_scale = 0.0
	screen.set_process(true)
	for n in range(14):
		screen._process(1.0 / 30.0)
		await _frame("motion_elite_%02d" % n)
	screen.set_process(false)
	Engine.time_scale = 1.0

## The boss: its warning in the last preparation (and the start button's warm pill), its bar, its
## fall (the stage's banner) and a chapter's.
func _set_boss() -> void:
	for stage in [4, 10]:
		await _open(stage, DARK if stage == 10 else BRIGHT, 6)
		Arena.gold = 300
		Arena.sim.wave_no = Balance.ARENA_WAVES
		Arena.sim._enter_prep(3.6)
		_step(0.05)
		await _shot("boss_warning_s%02d" % stage)
		for n in range(600):
			Arena.sim.step(1.0 / 60.0)
			if Arena.sim.boss_spawned: break
		_step(0.5)
		_spread()
		await _shot("boss_bar_s%02d" % stage)
		for mo in Arena.sim.monsters:
			if String(mo["kind"]) == "boss": mo["hp"] = 0.0
		Arena.sim.step(1.0 / 60.0)
		await _shot("boss_down_s%02d" % stage)
		if stage == 10:
			Engine.time_scale = 0.0
			screen.set_process(true)
			for n in range(26):
				screen._process(1.0 / 30.0)
				await _frame("motion_final_%02d" % n)
			screen.set_process(false)
			Engine.time_scale = 1.0

## The stage card: STAGE 1, a mid stage, a chapter's last stage.
func _set_card() -> void:
	for stage in [1, 7, 10]:
		await _open(stage, "", 0, true)
		check(Arena.modal == "stage", "STAGE %d opens on its card" % stage)
		await _shot("card_s%02d" % stage)

## Results: a win (「다음 STAGE」 open), a win on a stage whose next is locked (a tool opened it), a
## defeat with the DLC strip, a defeat of an owner who spent every ticket.
func _set_result() -> void:
	await _open(5, BRIGHT, 6)
	Save.stage_unlocked = 5
	Arena.sim.wave_no = Balance.ARENA_WAVES
	Arena.sim._enter_prep(0.02)
	for n in range(600):
		Arena.sim.step(1.0 / 60.0)
		if Arena.sim.boss_spawned: break
	for mo in Arena.sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	_step(2.2)
	check(Arena.modal == "result" and Arena.sim.won, "the stage is won")
	await _shot("result_win")
	check(bool(zone_of(screen, "result:next").get("on", false)), "「다음 STAGE」 is open after a win")
	Save.stage_unlocked = 5
	await _shot("result_win_locked")
	# Defeat with a shop and no DLC: the quiet strip.
	await _open(6, DARK, 4)
	var shop := Shop.new()
	Store.use_backend(shop)
	await _wave(4)
	Arena.sim._damage_crystal(1e9, Balance.ARENA_CENTER)
	check(Arena.modal == "result" and not Arena.sim.won, "the stage is lost")
	await _shot("result_defeat_offer")
	# An owner with every ticket spent.
	Store._owned.clear()
	Store.use_backend(null)
	await _open(6, DARK, 4)
	await _wave(7)
	Arena.sim.revives = Balance.ARENA_REVIVE_USES
	Arena.sim._damage_crystal(1e9, Balance.ARENA_CENTER)
	await _shot("result_defeat_spent")

## A revival ticket (the DLC): the crystal reforms and a 5-star hero joins (the field, then the bench).
func _set_revive() -> void:
	for full in [false, true]:
		await _open(4, BRIGHT if not full else DARK, 6 if full else 4)
		await _wave(6)
		_spread()
		Arena.sim._damage_crystal(1e9, Balance.ARENA_CENTER)
		check(Arena.sim.revives == 1 and not Arena.revive_gift.is_empty(), "the revival brings a hero")
		screen._process(0.0)
		await _shot("revive_%s" % ("bench" if full else "field"))

## Hellbound: the HUD on its endless waves, and its result (an old record, a new one).
func _set_hell() -> void:
	for id in SQUAD: Save.seen_units[id] = true
	Save.hell_best_wave = 30
	Engine.time_scale = 1.0
	Store._owned.clear()
	Store.use_backend(null)
	check(Arena.start_hellbound(SQUAD, SEED), "Hellbound opens")
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	await frames(3)
	Arena.confirm_stage()
	Arena.xp = -1e9
	await paint(screen)
	await _wave(23)
	_spread()
	Arena.gold = 160
	await _shot("hell_wave")
	Arena.sim.revives = Balance.ARENA_REVIVE_USES
	Arena.sim._damage_crystal(1e9, Balance.ARENA_CENTER)
	await _shot("hell_result_old")
	Save.hell_best_wave = 12
	screen.hud.hell_best_before = 12
	check(Arena.start_hellbound(SQUAD, SEED + 1), "Hellbound again")
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	await frames(3)
	Arena.confirm_stage()
	Arena.xp = -1e9
	await paint(screen)
	await _wave(17)
	Arena.sim.revives = Balance.ARENA_REVIVE_USES
	Arena.sim._damage_crystal(1e9, Balance.ARENA_CENTER)
	await _shot("hell_result_new")

## The strings the D6 report proposes for the DB (none is applied: the catalog is changed in
## memory only, for these pictures), photographed where they are drawn: the Soul Stone names (O1),
## 「준비 완료」 (O2), the revival ticket words and the defeat strip without gold (D2), the ladder's
## boss and chapter words, WAVE in capitals (M12).
const PROPOSED := {
	"ko": {"arena.title": "소울 스톤", "arena.skill.ward": "소울 방벽", "arena.ready": "준비 완료",
		"arena.victory": "소울 스톤을 지켰습니다!", "arena.defeat": "소울 스톤이 파괴됐습니다",
		"arena.revived": "부활권 사용!", "arena.revive_hero": "5성 %s 합류", "arena.revives_left": "남은 부활권",
		"arena.revives_none": "남은 부활권 없음", "arena.revives_used": "부활권 %d장 사용", "arena.revives_spent": "부활권 %d장 모두 사용",
		"arena.revive_offer": "스테이지마다 %d번, 깨진 소울 스톤이 되살아나고 5성 영웅 1명이 합류합니다. 지금 받으면 이 스테이지를 이어서 합니다.",
		"arena.revive_now": "부활권 살펴보기", "arena.boss_stage": "이 스테이지의 보스", "arena.final_note": "쓰러뜨리면 챕터를 마칩니다",
		"arena.wave_reached": "WAVE %d 도달"},
	"en": {"arena.title": "Soul Stone", "arena.skill.ward": "Soul Ward", "arena.ready": "Ready!",
		"arena.victory": "The Soul Stone is safe!", "arena.defeat": "The Soul Stone was shattered",
		"arena.revived": "Revival ticket used!", "arena.revive_hero": "5-star %s joins", "arena.revives_left": "Tickets left",
		"arena.revives_none": "No tickets left", "arena.revives_used": "Tickets used: %d", "arena.revives_spent": "All %d tickets used",
		"arena.revive_offer": "%d times a stage, the broken Soul Stone revives and a 5-star hero joins. Get it now and this stage goes on.",
		"arena.revive_now": "See revival tickets", "arena.boss_stage": "Stage boss", "arena.final_note": "Defeat it to finish the chapter",
		"arena.wave_reached": "Reached WAVE %d", "arena.box_wave": "Between waves"},
}
var _kept_strings := {}

func _propose(on: bool) -> void:
	for code in PROPOSED:
		for key in PROPOSED[code]:
			var slot := String(code) + "|" + String(key)
			if on:
				if not _kept_strings.has(slot): _kept_strings[slot] = I18n._catalog[code].get(key, null)
				I18n._catalog[code][key] = PROPOSED[code][key]
			elif _kept_strings.has(slot):
				if _kept_strings[slot] == null: I18n._catalog[code].erase(key)
				else: I18n._catalog[code][key] = _kept_strings[slot]
	I18n._cache.clear()
	Look._fit_cache.clear()

func _set_names() -> void:
	_propose(true)
	await _open(2, DARK, 4)
	await _wave(3)
	_spread()
	Arena.gold = 999
	_age_banners()
	await _shot("names_hud")
	Arena.sim._damage_crystal(1e9, Balance.ARENA_CENTER)
	screen._process(0.0)
	await _shot("names_revive")
	await _open(3, "", 0, true)
	await _shot("names_card")
	# A defeat with the shop (the strip), then a win.
	await _open(6, BRIGHT, 4)
	Store.use_backend(Shop.new())
	await _wave(4)
	Arena.sim._damage_crystal(1e9, Balance.ARENA_CENTER)
	await _shot("names_defeat")
	Store._owned.clear()
	Store.use_backend(null)
	await _open(4, BRIGHT, 6)
	Arena.sim.wave_no = Balance.ARENA_WAVES
	Arena.sim._enter_prep(0.02)
	for n in range(600):
		Arena.sim.step(1.0 / 60.0)
		if Arena.sim.boss_spawned: break
	for mo in Arena.sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	_step(2.2)
	await _shot("names_win")
	_propose(false)

# --------------------------------------------------------------------------- #
# Pictures
# --------------------------------------------------------------------------- #
func _shot(name: String) -> void:
	var file := "%s_%s" % [locale, name]
	screen._track_modal()
	Look.text_audit_enabled = true
	Look.text_audit.clear()
	await paint(screen)
	await paint(screen)
	var texts: Array = []
	for item in Look.text_audit:
		var box: Rect2 = item["box"]
		check(int(item["size"]) >= 12, "readable text size %s: %s (%d)" % [file, String(item["text"]), int(item["size"])])
		texts.append({"text": String(item["text"]), "size": int(item["size"]), "box": [box.position.x, box.position.y, box.size.x, box.size.y],
			"width": float(item.get("width", 0.0)), "lines": int(item.get("lines", 1))})
	Look.text_audit_enabled = false
	var zones: Array = []
	for z in screen.ui.zones:
		var r: Rect2 = z["rect"]
		zones.append({"id": String(z["id"]), "on": bool(z["on"]), "rect": [r.position.x, r.position.y, r.size.x, r.size.y]})
	await snap(out_dir + "/" + file + ".png")
	var meta := FileAccess.open(out_dir + "/" + file + ".json", FileAccess.WRITE)
	meta.store_string(JSON.stringify({"texts": texts, "zones": zones}, "  "))
	_index.append(file)

func _frame(name: String) -> void:
	await paint(screen)
	await snap(out_dir + "/%s_%s.png" % [locale, name])

func _open_film() -> void:
	var spec := arg("--film", "")
	if spec.is_empty(): return
	var size := Vector2i(int(spec.get_slice("x", 0)), int(spec.get_slice("x", 1)))
	get_window().size = Vector2i(96, 60)
	film = SubViewport.new()
	film.name = "Film"
	film.size = size
	film.size_2d_override = Vector2i(1280, 800)
	film.size_2d_override_stretch = true
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.transparent_bg = false
	film.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	film.set("oversampling_override", float(size.x) / 1280.0)
	add_child(film)

func _mount(node: Node) -> void:
	if film != null: film.add_child(node)
	else: add_child(node)

func snap(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := (film if film != null else get_viewport()).get_texture().get_image()
	image.save_png(path)
	return image

## A stuck staging step must not hold the GPU display: give up after a few minutes.
func _watchdog() -> void:
	var timer := get_tree().create_timer(float(arg_int("--timeout", 900)), true, false, true)
	timer.timeout.connect(func():
		printerr("!! watchdog: preview took too long")
		get_tree().quit(2))
