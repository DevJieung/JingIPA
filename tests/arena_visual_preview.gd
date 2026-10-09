extends Harness

var out_dir := "build/arena-visual/1280x800"
var screen: ArenaScreen
var main: Node2D
var _audit_count := 0

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if has_arg("--style-only"):
		await _style_only()
		return
	if has_arg("--help-only"):
		await _help_only()
		return
	if has_arg("--polish-only"):
		await _polish_only()
		return
	if has_arg("--rite-only"):
		await _rite_only()
		return
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261009)
		main = load("res://game/main.gd").new()
		add_child(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		await _capture(locale + "_themes")
		check(tap(screen, "theme:next"), "theme paging responds to touch")
		await _capture(locale + "_themes_next")
		screen._action("theme:0")
		check(tap(screen, "theme:start"), "selected theme starts free ritual")
		screen._rite_age = 9
		await _capture(locale + "_rite_free")
		check(tap(screen, "rite:confirm"), "ritual accepts first hero")
		await _capture(locale + "_summon_new")
		check(tap(screen, "close"), "new hero result resumes battle")
		_prepare_field()
		await _capture(locale + "_field_six")
		check(screen.view_3d.world is ArenaWorld, "arena uses its own native 3D world adapter")
		check(screen.view_3d.world.hero_nodes.size() == Balance.ARENA_HERO_LIMIT, "all six real hero models are present")
		for corner in [Balance.MAP_RECT.position, Balance.MAP_RECT.end,
			Vector2(Balance.MAP_RECT.end.x, Balance.MAP_RECT.position.y), Vector2(Balance.MAP_RECT.position.x, Balance.MAP_RECT.end.y)]:
			check(ArenaScreen.FIELD.has_point(screen.view_3d.project(corner, 0.15)), "whole spawn edge stays in fixed overview")
			check(ArenaScreen.FIELD.has_point(screen.view_3d.project(corner, 1.75)), "tall model at spawn edge stays in fixed overview")
		var camera_before := screen.view_3d.world.camera.transform
		main.menu.open()
		main.menu.page = "rules"
		await frames(3)
		await snap(out_dir + "/" + locale + "_help.png")
		check(main.menu.opened, "actual menu displays arena help")
		main.menu.close()
		check(tap(screen, "hero:1"), "second hero card selects second hero")
		check(Arena.selected == 1, "selection follows the touched hero")
		var before: Vector2 = Arena.sim.heroes[1]["pos"]
		var untouched: Vector2 = Arena.sim.heroes[0]["pos"]
		var finger := InputEventScreenTouch.new()
		finger.index = 0
		finger.position = ArenaScreen.JOY_CENTER + Vector2(46, 0)
		finger.pressed = true
		screen._input(finger)
		for n in range(12):
			screen._process(1.0 / 30)
			await _capture(locale + "_move_%02d" % n)
		check(Vector2(Arena.sim.heroes[1]["pos"]).distance_to(before) > 1, "joystick actually moves selected native hero")
		check(Vector2(Arena.sim.heroes[0]["pos"]).is_equal_approx(untouched), "other heroes hold their assigned positions")
		check(screen.view_3d.world.camera.transform.is_equal_approx(camera_before), "moving heroes never moves the fixed camera")
		finger.pressed = false
		screen._input(finger)
		check(screen.joystick == Vector2.ZERO, "touch release stops joystick")
		check(tap(screen, "hero:0"), "approved Limne remains selectable")
		finger.pressed = true
		screen._input(finger)
		for n in range(6):
			screen._process(1.0 / 30)
			await _capture(locale + "_limne_move_%02d" % n)
		finger.pressed = false
		screen._input(finger)
		for skill in ["blast", "freeze", "ward"]:
			Arena.sim.skill_cooldowns[skill] = 0.0
			await paint(screen)
			check(tap(screen, "skill:" + skill), "manual common skill button " + skill)
			await _capture(locale + "_skill_" + skill)
			for n in range(4):
				screen._process(1.0 / 30)
				await _capture(locale + "_skill_" + skill + "_%02d" % n)
		Arena.gold = 99999
		check(Arena.begin_summon(), "paid ritual opens")
		var hero: Dictionary = Arena.heroes[0]
		var old_tier := int(hero["tier"])
		var result := Arena.gain_hero(hero["unit"], 5)
		Arena.summon_result = result
		Arena.phase = Arena.Phase.SWAP
		screen._track_modal()
		await _capture(locale + "_growth_result")
		check(int(result["after_tier"]) >= old_tier, "growth result carries resulting grade")
		hero["tier"] = Balance.TIER_MAX - 1
		hero["growth_points"] = maxi(0, Arena.growth_needed(hero) - (Balance.TIER_MAX + 1) * Balance.ARENA_GROWTH_POINT_SCALE)
		Arena.summon_result = Arena.gain_hero(hero["unit"], Balance.TIER_MAX)
		await _capture(locale + "_growth_maxed")
		check(bool(Arena.summon_result["maxed"]), "maximum growth is shown as complete")
		check(not Arena.eligible_units().any(func(u): return u["id"] == hero["unit"]["id"]), "fully grown identity leaves the summon candidates")
		Arena.close_modal()
		Arena.open_modal("shop")
		await _capture(locale + "_upgrades")
		var clock_before := Arena.sim.elapsed
		var positions := _positions()
		screen._process(0.2)
		Arena.sim.step(0.2)
		check(is_equal_approx(Arena.sim.elapsed, clock_before), "growth modal pauses battle clock")
		check(_positions() == positions, "growth modal pauses all actor positions")
		check(tap(screen, "shop:tab:passives"), "passive tab is touch accessible")
		await _capture(locale + "_passives")
		Arena.close_modal()
		for id in ["saeta", "glaukos", "jokull"]:
			Arena.gain_hero(Roster.unit_by_id(id), 9)
		Arena.open_modal("bench")
		await _capture(locale + "_reserves")
		check(tap(screen, "bench:field:2"), "reserve screen selects outgoing hero")
		check(tap(screen, "bench:reserve:0"), "reserve screen selects incoming hero")
		await _capture(locale + "_reserves_selected")
		var outgoing := String(Arena.heroes[2]["unit"]["id"])
		var incoming := String(Arena.bench[0]["unit"]["id"])
		check(tap(screen, "bench:swap"), "reserve swap confirms")
		check(String(Arena.heroes[2]["unit"]["id"]) == incoming and String(Arena.bench[0]["unit"]["id"]) == outgoing, "reserve swap preserves both identities")
		Arena.close_modal()
		Arena.sim._spawn(Arena.boss_for(1))
		Arena.sim.monsters[-1]["pos"] = Vector2(630, 530)
		Arena.sim.boss_spawned = true
		await _capture(locale + "_boss")
		Arena.sim.done = true
		Arena.sim.won = true
		Arena.end_run(true)
		await _capture(locale + "_victory")
		Arena.sim.won = false
		await _capture(locale + "_defeat")
		Save.cur_run = {}
		main.show_title()
		await paint(main.screen)
		await snap(out_dir + "/" + locale + "_title.png")
		Save.cur_run = {"mode": "arena", "wave": 1, "sim": {"elapsed": 187.0}}
		await paint(main.screen)
		check(zone_of(main.screen, "resume").size() > 0, "title has arena continue button")
		await snap(out_dir + "/" + locale + "_title_resume.png")
		for unit in Roster.UNITS:
			Save.seen_units[String(unit["id"])] = true
		main.screen.collection.opened = true
		for element in ["water", "fire", "ice", "elec", "none"]:
			main.screen.collection.element = element
			await _capture_canvas(main.screen, locale + "_collection_" + element)
		main.screen.collection.close()
		await paint(main.screen)
		main.menu.open()
		for menu_page in ["menu", "rite", "elements"]:
			main.menu.page = menu_page
			await _capture_canvas(main.menu, locale + "_menu_" + menu_page)
		main.menu.close()
		Save.cur_run = {}
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	I18n.set_locale("ko")
	var report := {"checks": checks, "failures": failures, "text_boxes": _audit_count,
		"native_assets_replaced": false, "device_fps_measured": false,
		"layout_resolution": get_viewport().get_visible_rect().size, "window_resolution": DisplayServer.window_get_size()}
	var file := FileAccess.open(out_dir + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file = null
	print("Arena visual review: " + out_dir)
	finish("Arena native 3D and mobile UI")

func _style_only() -> void:
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261009)
		main = load("res://game/main.gd").new()
		add_child(main)
		await frames(3)
		Save.cur_run = {}
		await _capture_canvas(main.screen, locale + "_title")
		Save.cur_run = {"mode": "arena", "wave": 1, "sim": {"elapsed": 187.0}}
		await _capture_canvas(main.screen, locale + "_title_resume")
		for unit in Roster.UNITS:
			Save.seen_units[String(unit["id"])] = true
		main.screen.collection.opened = true
		for element in ["water", "fire", "ice", "elec", "none"]:
			main.screen.collection.element = element
			await _capture_canvas(main.screen, locale + "_collection_" + element)
		main.screen.collection.close()
		await paint(main.screen)
		main.menu.open()
		for menu_page in ["menu", "rite", "elements"]:
			main.menu.page = menu_page
			await _capture_canvas(main.menu, locale + "_menu_" + menu_page)
		main.menu.close()
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		await _capture(locale + "_themes")
		Arena.choose_theme(0)
		screen._track_modal()
		screen._rite_age = 9
		await _capture(locale + "_rite_free")
		check(zone_of(screen, "rite:pull").is_empty(), "no advertising action on the ritual")
		Arena.confirm_summon()
		await _capture(locale + "_summon_new")
		Arena.close_modal()
		_prepare_field()
		await _capture(locale + "_field_six")
		Arena.gold = 99999
		Arena.open_modal("shop")
		await _capture(locale + "_upgrades")
		screen._shop_tab = "passives"
		await _capture(locale + "_passives")
		Arena.close_modal()
		for id in ["saeta", "glaukos", "jokull"]:
			Arena.gain_hero(Roster.unit_by_id(id), 9)
		Arena.open_modal("bench")
		screen._track_modal()
		screen._bench_choice = 0
		await _capture(locale + "_reserves_selected")
		Arena.close_modal()
		Arena.sim.done = true
		Arena.sim.won = true
		Arena.end_run(true)
		await _capture(locale + "_victory")
		Arena.sim.won = false
		await _capture(locale + "_defeat")
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/style-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "text_boxes": _audit_count}, "  ") + "\n")
	file = null
	finish("Native 3D design consistency")

func _help_only() -> void:
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261009)
		main = load("res://game/main.gd").new()
		add_child(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		Arena.choose_theme(0)
		Arena.confirm_summon()
		Arena.close_modal()
		await paint(screen)
		main.menu.open()
		main.menu.page = "rules"
		Look.text_audit.clear()
		Look.text_audit_enabled = true
		await paint(main.menu)
		for item in Look.text_audit:
			check(int(item["size"]) >= 16, "help remains readable: " + String(item["text"]))
		Look.text_audit_enabled = false
		await snap(out_dir + "/" + locale + "_help.png")
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/help-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  ") + "\n")
	file = null
	finish("Arena readable help")

func _polish_only() -> void:
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261009)
		main = load("res://game/main.gd").new()
		add_child(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		Arena.choose_theme(0)
		screen._track_modal()
		screen._rite_age = 9
		await _capture(locale + "_rite_free")
		var respin_box: Rect2 = zone_of(screen, "rite:respin")["rect"]
		var spins_before := Arena.spins
		_window_touch(respin_box.get_center(), true)
		_window_touch(respin_box.get_center(), false)
		check(Arena.spins > spins_before, "window pixel touch reaches the stretched ritual button")
		screen._rite_age = 9
		Arena.confirm_summon()
		Arena.close_modal()
		_prepare_field()
		for i in range(Balance.ARENA_HERO_LIMIT):
			await paint(screen)
			check(tap(screen, "hero:%d" % i), "each of six hero cards accepts selection")
			check(Arena.selected == i, "selected index matches each native hero")
			var old_positions := _positions()
			var finger := InputEventScreenTouch.new()
			finger.index = 0
			finger.position = ArenaScreen.JOY_CENTER + Vector2(46, 0)
			finger.pressed = true
			screen._input(finger)
			screen._process(1.0 / 30)
			check(Vector2(Arena.sim.heroes[i]["pos"]).distance_to(old_positions[i]) > 0.1, "each selected hero actually moves")
			for j in range(Balance.ARENA_HERO_LIMIT):
				if j != i:
					check(Vector2(Arena.sim.heroes[j]["pos"]).is_equal_approx(old_positions[j]), "unselected heroes stay for each selection")
			finger.pressed = false
			screen._input(finger)
		for skill in ["blast", "freeze", "ward"]:
			Arena.sim.skill_cooldowns[skill] = 0.0
			await paint(screen)
			check(tap(screen, "skill:" + skill), "manual common skill button " + skill)
			await _capture(locale + "_skill_" + skill)
			for n in range(4):
				screen._process(1.0 / 30)
				await _capture(locale + "_skill_" + skill + "_%02d" % n)
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/polish-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  ") + "\n")
	file = null
	finish("Arena ritual and skill clarity")

func _rite_only() -> void:
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261009)
		main = load("res://game/main.gd").new()
		add_child(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		Arena.choose_theme(0)
		screen._track_modal()
		screen._rite_age = 9
		await _capture(locale + "_rite_free")
		var spins_before := Arena.spins
		var respin_box: Rect2 = zone_of(screen, "rite:respin")["rect"]
		_window_touch(respin_box.get_center(), true)
		_window_touch(respin_box.get_center(), false)
		check(Arena.spins > spins_before, "window pixel touch reaches the stretched ritual button")
		screen._rite_age = 9
		check(zone_of(screen, "rite:pull").is_empty(), "ritual exposes no rewarded pull action")
		var clock: float = Arena.sim.elapsed
		for n in range(4):
			screen._process(0.15)
			await _capture(locale + "_rite_spin_%02d" % n)
		check(is_equal_approx(clock, Arena.sim.elapsed), "ritual animation preserves paused battle time")
		Arena.orbit = RiteBoard.sample_orbit(Rite.MAX_STARS)
		await _capture(locale + "_rite_full")
		check(not bool(zone_of(screen, "rite:respin").get("on", true)), "respin disables when all stars are in the gate")
		Arena.confirm_summon()
		Arena.close_modal()
		_prepare_field()
		await paint(screen)
		Arena.selected = 0
		var card: Rect2 = zone_of(screen, "hero:5")["rect"]
		_window_touch(card.get_center(), true)
		_window_touch(card.get_center(), false)
		check(Arena.selected == 5, "window pixel touch selects the sixth hero after stretch")
		var old_position: Vector2 = Arena.sim.heroes[5]["pos"]
		_window_touch(ArenaScreen.JOY_CENTER + Vector2(46, 0), true)
		screen._process(1.0 / 30)
		_window_touch(ArenaScreen.JOY_CENTER + Vector2(46, 0), false)
		check(Vector2(Arena.sim.heroes[5]["pos"]).distance_to(old_position) > 0.1, "window pixel joystick touch moves the selected hero")
		check(screen.joystick == Vector2.ZERO, "window pixel release stops the joystick")
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/rite-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  ") + "\n")
	file = null
	finish("Arena ritual presentation")

func _window_touch(logical: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 7
	event.position = get_viewport().get_final_transform() * logical
	event.pressed = pressed
	get_viewport().push_input(event, false)

func _prepare_field() -> void:
	Arena.heroes.clear()
	Arena.bench.clear()
	var ids := ["limne", "brasa", "echo", "pip", "morrigan", "dummy"]
	for i in range(Balance.ARENA_HERO_LIMIT):
		Arena.gain_hero(Roster.unit_by_id(ids[i]), (i + 1) % 10)
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + i * TAU / 6) * 150
	Arena.sim.refresh_heroes()
	Arena.selected = 1
	Arena.sim.monsters.clear()
	var pool := Roster.theme_pool(Arena.theme_for(1))
	for n in range(22):
		Arena.sim._spawn(pool[n % pool.size()])
		var mo: Dictionary = Arena.sim.monsters[-1]
		mo["pos"] = Balance.ARENA_CENTER + Vector2.from_angle(n * TAU / 22) * (210 + (n % 3) * 32)
		mo["hp"] *= 0.7
		mo["vel"] = (Balance.ARENA_CENTER - Vector2(mo["pos"])).normalized()
	Arena.sim.monsters[0]["blocked"] = true
	Arena.sim.monsters[0]["vel"] = Vector2.ZERO
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.65

func _positions() -> Array:
	var out: Array = []
	for item in Arena.sim.heroes: out.append(item["pos"])
	for item in Arena.sim.monsters: out.append(item["pos"])
	return out

func _capture(name: String) -> void:
	screen._track_modal()
	await _capture_canvas(screen, name)

func _capture_canvas(canvas: CanvasItem, name: String) -> void:
	Look.text_audit_enabled = true
	Look.text_audit.clear()
	Look.raw_text_audit.clear()
	await paint(canvas)
	for item in Look.text_audit:
		_audit_count += 1
		var box: Rect2 = item["box"]
		check(box.size.x > 0 and box.size.y > 0, "visible text box " + name)
		check(int(item["size"]) >= 12, "readable text size " + name + ": " + String(item["text"]))
	if canvas is ArenaScreen:
		var shown: Array[String] = []
		for item in Look.text_audit:
			shown.append(String(item["text"]))
		if Arena.modal == "theme":
			for index in range(canvas._theme_page * 12, mini(Roster.THEMES.size(), canvas._theme_page * 12 + 12)):
				check(I18n.t(String(Roster.THEMES[index]["ko"])) in shown, "localized theme name is actually rendered: " + String(Roster.THEMES[index]["id"]))
		else:
			var theme: Dictionary = Roster.THEMES[clampi(Arena.theme_index, 0, Roster.THEMES.size() - 1)]
			check(I18n.t(String(theme["ko"])) in shown, "current battlefield name is rendered in the HUD")
	Look.text_audit_enabled = false
	await snap(out_dir + "/" + name + ".png")
