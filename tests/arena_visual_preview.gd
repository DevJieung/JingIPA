extends Harness

var out_dir := "build/arena-visual/1280x800"
var screen: ArenaScreen
var main: Node2D
var _audit_count := 0

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if has_arg("--road-only"):
		await _road_only()
		return
	if has_arg("--hud-only"):
		await _hud_only()
		return
	if has_arg("--circle-only"):
		await _circle_only()
		return
	if has_arg("--look-only"):
		await _look_only()
		return
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
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = false
		await _capture(locale + "_field_six")
		check(screen.view_3d.world is ArenaWorld, "arena uses its own native 3D world adapter")
		check(screen.view_3d.world.hero_nodes.size() == Balance.ARENA_HERO_LIMIT, "all six real hero models are present")
		check(screen.view_3d.minimap_footprint(ArenaScreen.MINIMAP.grow(-11)).size() >= 3, "minimap exposes the camera area")
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
		finger.position = Vector2(123, 676)
		finger.pressed = true
		screen._input(finger)
		_drag(Vector2(169, 676), 0)
		for n in range(12):
			screen._process(1.0 / 30)
			await _capture(locale + "_move_%02d" % n)
		check(Vector2(Arena.sim.heroes[1]["pos"]).distance_to(before) > 1, "joystick actually moves selected native hero")
		check(Vector2(Arena.sim.heroes[0]["pos"]).is_equal_approx(untouched), "other heroes hold their assigned positions")
		check(is_equal_approx(screen.view_3d.world.camera.size, 26.0), "following preserves object scale")
		finger.pressed = false
		screen._input(finger)
		check(screen.joystick == Vector2.ZERO, "touch release stops joystick")
		check(tap(screen, "hero:0"), "approved Limne remains selectable")
		finger.pressed = true
		screen._input(finger)
		_drag(Vector2(169, 676), 0)
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

func _road_only() -> void:
	var trajectories: Array = []
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261010)
		main = load("res://game/main.gd").new()
		add_child(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		Arena.choose_theme(0)
		Arena.confirm_summon()
		Arena.close_modal()
		_prepare_field()
		await _capture(locale + "_road_field_six")
		Arena.heroes.clear()
		Arena.bench.clear()
		var ids := ["echo", "brasa", "limne", "dummy"]
		for lane in range(ArenaGeometry.ROUTE_COUNT):
			Arena.gain_hero(Roster.unit_by_id(ids[lane]), 3)
			Arena.heroes[lane]["position"] = ArenaGeometry.route_points(lane)[18]
		Arena.sim.refresh_heroes()
		Arena.sim.monsters.clear()
		Arena.selected = -1
		var pool := Roster.theme_pool(Arena.theme_for(1))
		for lane in range(ArenaGeometry.ROUTE_COUNT):
			Arena.sim._spawn(pool[0])
			var monster: Dictionary = Arena.sim.monsters[-1]
			monster["pos"] = ArenaGeometry.route_points(lane)[14]
			monster["route"] = lane
			monster["hp"] = 1000000.0
			monster["max"] = 1000000.0
		Arena.sim._rebuild_navigation()
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = true
		screen.view_3d._apply_camera(Vector3.ZERO)
		await _capture(locale + "_road_center_guardians")
		var closest := [INF, INF, INF, INF]
		var blocked := [0, 0, 0, 0]
		for n in range(32):
			for tick in range(18):
				Arena.sim._move_monsters(1.0 / 60)
				Arena.sim.elapsed += 1.0 / 60
				for lane in range(ArenaGeometry.ROUTE_COUNT):
					var monster: Dictionary = Arena.sim.monsters[lane]
					closest[lane] = minf(closest[lane], Vector2(monster["pos"]).distance_to(Arena.sim.heroes[lane]["pos"]))
					if monster["blocked"]: blocked[lane] += 1
			await _capture(locale + "_road_pass_%02d" % n)
			var frame := {"locale": locale, "frame": n, "monsters": []}
			for lane in range(ArenaGeometry.ROUTE_COUNT):
				var at: Vector2 = Arena.sim.monsters[lane]["pos"]
				check(ArenaGeometry.on_road(at, Balance.ARENA_MONSTER_RADIUS), "bypassing monster stays on visible road lane " + str(lane))
				frame["monsters"].append({"lane": lane, "x": at.x, "y": at.y})
			trajectories.append(frame)
		for lane in range(ArenaGeometry.ROUTE_COUNT):
			var path := ArenaGeometry.route_points(lane)
			var progress := _road_progress(Arena.sim.monsters[lane]["pos"], path)
			var hero_progress := _road_progress(Arena.sim.heroes[lane]["pos"], path)
			check(progress > hero_progress + 45.0, "monster visibly passes central guardian lane " + str(lane))
			check(closest[lane] >= Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS - 0.01, "bypass respects the active collision circles lane " + str(lane))
			check(blocked[lane] == 0, "central guardian never stops the monster lane " + str(lane))
		# Real hero-follow views include the road entrances, boundary stones and lamps.
		Arena.selected = 0
		for lane in range(ArenaGeometry.ROUTE_COUNT):
			Arena.sim.heroes[0]["pos"] = ArenaGeometry.route_points(lane)[1]
			screen.view_3d._camera_initialized = false
			await _capture(locale + "_road_entry_%02d" % lane)
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	I18n.set_locale("ko")
	var file := FileAccess.open(out_dir + "/road-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "text_boxes": _audit_count,
		"road_width": ArenaGeometry.ROAD_WIDTH, "simulation_seconds": 9.6,
		"trajectories": trajectories, "device_fps_measured": false}, "  ") + "\n")
	file = null
	finish("Wider roads and central guardian bypass")

func _road_progress(at: Vector2, path: PackedVector2Array) -> float:
	var nearest := INF
	var progress := 0.0
	var along := 0.0
	for i in range(path.size() - 1):
		var point := Geometry2D.get_closest_point_to_segment(at, path[i], path[i + 1])
		var distance := point.distance_squared_to(at)
		if distance < nearest:
			nearest = distance
			progress = along + point.distance_to(path[i])
		along += path[i].distance_to(path[i + 1])
	return progress

func _hud_only() -> void:
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
		Arena.heroes.clear()
		Arena.gain_hero(Roster.unit_by_id("echo"), 3)
		Arena.heroes[0]["position"] = Balance.ARENA_CENTER + Vector2(80, 110)
		Arena.sim.refresh_heroes()
		Arena.sim.monsters.clear()
		Arena.gold = 69
		Arena.selected = 0
		await _capture(locale + "_reference")
		# Thirty seconds of continuous real native gait, not twelve isolated poses.
		for n in range(12):
			for tick in range(150):
				var phase := (n * 150 + tick) * 0.01
				Arena.sim.heroes[0]["pos"] = Balance.ARENA_CENTER + Vector2(100, 100) + Vector2.from_angle(phase) * 70
				Arena.sim.elapsed += 1.0 / 60
				screen.view_3d.world.sync_heroes(Arena.sim.heroes, Arena.sim.elapsed, true)
			await _capture(locale + "_long_walk_%02d" % n)
		Arena.sim.elapsed += 0.1
		await _capture(locale + "_walk_stopped")
		var pool := Roster.theme_pool(Arena.theme_for(1))
		Arena.sim._spawn(pool[0])
		Arena.sim.monsters[0]["pos"] = ArenaGeometry.nearest_road_point(Arena.sim.heroes[0]["pos"] + Vector2(40, 0))
		Arena.sim.monsters[0]["hp"] = 1000000.0
		Arena.sim.monsters[0]["max"] = 1000000.0
		Arena.sim._cache_positions()
		for n in range(6):
			screen._process(1.0 / 15)
			await _capture(locale + "_echo_attack_%02d" % n)
		_prepare_field()
		Arena.gold = 99999
		await _capture(locale + "_field_six")
		for zone in screen.ui.zones:
			check(ArenaScreen.SIDEBAR.encloses(Rect2(zone["rect"])), "all battle commands remain in the right HUD")
		var last := zone_of(screen, "hero:5")
		_window_touch(Rect2(last["rect"]).get_center(), true)
		_window_touch(Rect2(last["rect"]).get_center(), false)
		check(Arena.selected == 5, "window pixel touch selects sixth right-side card")
		await _capture(locale + "_selected_last")
		for point in [Vector2(105, 692), Vector2(935, 442)]:
			screen._pointer(0, point, true)
			_drag(point + Vector2(40, -15))
			check(screen._joy_pointer == 0 and screen.joystick.length() > 0, "open lower field starts movement")
			await _capture(locale + "_joystick_" + str(int(point.x)))
			screen._pointer(0, point, false)
		for point in [Vector2(997, 430), Vector2(1136, 224), ArenaScreen.MINIMAP.get_center()]:
			screen._pointer(1, point, true)
			check(screen._joy_pointer == -99, "right HUD gaps do not start movement")
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var at: Vector2 = Balance.ARENA_CENTER + direction * (ArenaGeometry.RADIUS - Balance.ARENA_HERO_RADIUS)
			Arena.sim.heroes[Arena.selected]["pos"] = at
			for frame in range(60): screen.view_3d.follow_selected(at, 1.0 / 30)
			await _capture(locale + "_edge_%d_%d" % [int(direction.x), int(direction.y)])
			for height in [0.08, 1.95]:
				check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(Balance.ARENA_CENTER, height)), "crystal remains clear of right HUD")
			check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(at, 0.5)), "selected native hero remains clear of right HUD")
		for skill in ["blast", "freeze", "ward"]:
			Arena.sim.skill_cooldowns[skill] = 0.0
			await paint(screen)
			check(tap(screen, "skill:" + skill), "right skill action remains active")
			await _capture(locale + "_skill_" + skill)
		Arena.open_modal("shop")
		await _capture(locale + "_upgrades")
		Arena.close_modal()
		Arena.gain_hero(Roster.unit_by_id("saeta"), 9)
		Arena.open_modal("bench")
		await _capture(locale + "_reserves_selected")
		Arena.close_modal()
		Arena.begin_summon()
		screen._rite_age = 9
		await _capture(locale + "_rite_free")
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/hud-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "text_boxes": _audit_count}, "  ") + "\n")
	file = null
	finish("Right command HUD and prolonged native locomotion")

func _circle_only() -> void:
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
		Arena.heroes.clear()
		Arena.gain_hero(Roster.unit_by_id("echo"), 3)
		Arena.heroes[0]["position"] = Balance.ARENA_CENTER + Vector2(0, -175)
		Arena.sim.refresh_heroes()
		Arena.selected = 0
		Arena.gold = 99999
		Arena.sim.monsters.clear()
		var pool := Roster.theme_pool(Arena.theme_for(1))
		for lane in range(ArenaGeometry.ROUTE_COUNT):
			for sample in [4, 14, 24]:
				Arena.sim._spawn(pool[(lane + sample) % pool.size()])
				var monster: Dictionary = Arena.sim.monsters[-1]
				monster["pos"] = ArenaGeometry.route_points(lane)[sample]
				monster["route"] = lane
				monster["hp"] = float(monster["max"]) * 0.8
		Arena.sim._rebuild_navigation()
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = false
		await _capture(locale + "_circle")
		check(screen._joy_pointer == -99 and screen.joystick == Vector2.ZERO, "joystick hidden until a finger is down")
		var traveled := 0.0
		for n in range(16):
			var before: Vector2 = Arena.sim.monsters[0]["pos"]
			for tick in range(5):
				Arena.sim._move_monsters(0.15)
				Arena.sim.elapsed += 0.15
			traveled += before.distance_to(Vector2(Arena.sim.monsters[0]["pos"]))
			screen._draw_dt = 0.15
			await _capture(locale + "_lane_%02d" % n)
			for monster in Arena.sim.monsters:
				check(ArenaGeometry.on_road(monster["pos"], Balance.ARENA_MONSTER_RADIUS), "moving enemy remains on the rendered curved road")
		check(traveled > 20, "curved lane footage contains actual simulation movement")
		var origins := [Vector2(105, 692), Vector2(352, 407), Vector2(38, 250), Vector2(942, 440)]
		for i in range(origins.size()):
			var origin: Vector2 = origins[i]
			screen._pointer(0, origin, true)
			check(screen.joy_origin == origin and screen.joystick == Vector2.ZERO, "touch becomes the exact stationary origin")
			await _capture(locale + "_joystick_start_%02d" % i)
			_drag(origin + Vector2(47, -18))
			check(screen.joystick.length() > 0, "drag activates floating joystick")
			await _capture(locale + "_joystick_drag_%02d" % i)
			screen._pointer(0, origin, false)
			check(screen._joy_pointer == -99 and screen.joystick == Vector2.ZERO, "release hides the joystick")
		await _capture(locale + "_joystick_released")
		for n in range(8):
			var at := Balance.ARENA_CENTER + Vector2.from_angle(n * TAU / 8) * (ArenaGeometry.RADIUS - Balance.ARENA_HERO_RADIUS)
			Arena.sim.heroes[Arena.selected]["pos"] = at
			for tick in range(30): screen.view_3d.follow_selected(at, 1.0 / 30)
			await _capture(locale + "_circle_edge_%02d" % n)
			check(ArenaGeometry.contains(at, Balance.ARENA_HERO_RADIUS - 0.01), "hero stands inside the circular rim")
			check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(at, 0.5)), "hero visible at the circular rim")
			check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(Balance.ARENA_CENTER, 1.95)), "crystal tip remains visible at circle edge")
			check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(Balance.ARENA_CENTER, 0.08)), "crystal base remains visible at circle edge")
		_prepare_field()
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = false
		await _capture(locale + "_field_six")
		screen._pointer(0, Vector2(105, 692), true)
		_drag(Vector2(152, 680))
		main.menu.open()
		main.menu.page = "rules"
		await _capture_canvas(main.menu, locale + "_help")
		check(screen._joy_pointer == -99, "menu opening cancels movement while screen processing is disabled")
		main.menu.close()
		Arena.open_modal("shop")
		await _capture(locale + "_upgrades")
		Arena.close_modal()
		for id in ["saeta", "glaukos", "jokull"]: Arena.gain_hero(Roster.unit_by_id(id), 9)
		Arena.open_modal("bench")
		await _capture(locale + "_reserves_selected")
		Arena.close_modal()
		screen._pointer(0, Vector2(100, 690), true)
		_drag(Vector2(150, 690))
		screen._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(screen._joy_pointer == -99 and screen.joystick == Vector2.ZERO, "focus loss cancels floating control")
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/circle-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "text_boxes": _audit_count}, "  ") + "\n")
	file = null
	finish("Circular arena, curved lanes and floating joystick")

func _look_only() -> void:
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261009)
		main = load("res://game/main.gd").new()
		add_child(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		var lake := 0
		for i in range(Roster.THEMES.size()):
			if Roster.THEMES[i]["id"] == "calm_lake": lake = i
		Arena.choose_theme(lake)
		Arena.confirm_summon()
		Arena.close_modal()
		Arena.heroes.clear()
		Arena.gain_hero(Roster.unit_by_id("echo"), 3)
		Arena.heroes[0]["position"] = Balance.ARENA_CENTER + Vector2(100, 100)
		Arena.sim.refresh_heroes()
		Arena.selected = 0
		Arena.gold = 69
		Arena.sim.elapsed = 143
		Arena.sim.crystal_hp = 1160
		Arena.sim.monsters.clear()
		var pool := Roster.theme_pool(Arena.theme_for(1))
		Arena.sim._spawn(pool[0])
		Arena.sim.monsters[0]["pos"] = ArenaGeometry.nearest_road_point(Balance.ARENA_CENTER + Vector2(180, 110))
		Arena.sim.monsters[0]["hp"] *= 0.45
		await _capture(locale + "_reference")
		if has_arg("--reference-only"):
			main.queue_free()
			await frames(4)
			finish("Arena reference quick review")
			return
		for n in range(8):
			screen._process(1.0 / 15)
			await _capture(locale + "_echo_attack_%02d" % n)
		var size_before: float = screen.view_3d.world.camera.size
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
			var at: Vector2 = Balance.ARENA_CENTER + direction * ArenaGeometry.MAP_RECT.size * 0.5
			at = ArenaGeometry.clamp_point(at, 24)
			Arena.sim.heroes[0]["pos"] = at
			for n in range(30): screen.view_3d.follow_selected(at, 1.0 / 30)
			var name := "edge_%s_%s" % [int(direction.x), int(direction.y)]
			await _capture(locale + "_" + name)
			check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(Balance.ARENA_CENTER, 0.1)), "crystal base visible at " + name)
			check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(Balance.ARENA_CENTER, 1.95)), "crystal tip visible at " + name)
			check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(at, 0.5)), "selected hero visible at " + name)
			check(is_equal_approx(size_before, screen.view_3d.world.camera.size), "follow preserves object scale")
			check(screen.view_3d.minimap_footprint(ArenaScreen.MINIMAP.grow(-11)).size() >= 3, "minimap view footprint exists")
		Arena.sim.heroes[0]["pos"] = Balance.ARENA_CENTER
		for n in range(30): screen.view_3d.follow_selected(Balance.ARENA_CENTER, 1.0 / 30)
		Arena.sim.monsters.clear()
		for n in range(12):
			Arena.sim.heroes[0]["pos"] = ArenaGeometry.clamp_point(Balance.ARENA_CENTER + Vector2(220 + n * 22, 85), 24)
			screen._draw_dt = 1.0 / 15
			Arena.sim.elapsed += 1.0 / 15
			await _capture(locale + "_follow_%02d" % n)
		_prepare_field()
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = false
		await _capture(locale + "_field_six")
		Arena.open_modal("shop")
		await _capture(locale + "_upgrades")
		screen._shop_tab = "passives"
		await _capture(locale + "_passives")
		Arena.close_modal()
		for id in ["saeta", "glaukos", "jokull"]: Arena.gain_hero(Roster.unit_by_id(id), 9)
		Arena.open_modal("bench")
		await _capture(locale + "_reserves_selected")
		Arena.close_modal()
		for skill in ["blast", "freeze", "ward"]:
			Arena.sim.skill_cooldowns[skill] = 0.0
			await paint(screen)
			check(tap(screen, "skill:" + skill), "restyled skill button remains active")
			await _capture(locale + "_skill_" + skill)
		main.menu.open()
		main.menu.page = "rules"
		await _capture_canvas(main.menu, locale + "_help")
		main.menu.close()
		Arena.gold = 99999
		Arena.begin_summon()
		screen._rite_age = 9
		await _capture(locale + "_rite_free")
		Arena.close_modal()
		Arena.modal = ""
		Arena.phase = Arena.Phase.BATTLE
		for theme in [0, 20, 30, 40]:
			Arena.theme_index = theme
			await _capture(locale + "_biome_%02d" % theme)
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/look-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "text_boxes": _audit_count}, "  ") + "\n")
	file = null
	finish("Arena reference look and following camera")

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
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = false
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
			finger.position = Vector2(123, 676)
			finger.pressed = true
			screen._input(finger)
			_drag(Vector2(169, 676), 0)
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
		_window_touch(Vector2(123, 676), true)
		var drag := InputEventScreenDrag.new()
		drag.index = 7
		drag.position = get_viewport().get_final_transform() * Vector2(169, 676)
		get_viewport().push_input(drag, false)
		screen._process(1.0 / 30)
		_window_touch(Vector2(123, 676), false)
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

func _drag(logical: Vector2, pointer: int = 0) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = pointer
	drag.position = logical
	screen._input(drag)

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
		mo["pos"] = ArenaGeometry.route_points(n % ArenaGeometry.ROUTE_COUNT)[6 + (n / ArenaGeometry.ROUTE_COUNT) * 5]
		mo["hp"] *= 0.7
		mo["vel"] = ArenaGeometry.road_direction(mo["pos"])
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
