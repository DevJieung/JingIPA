extends Harness

var out_dir := "build/arena-visual/1280x800"
var screen: ArenaScreen
var main: Node2D
var _audit_count := 0
## Off-screen picture (`--film 1280x800`). With it the window only lends its GL context
## (the GPU display of the login session), the game draws into this viewport and every
## capture reads it. Without it the game draws into the window as before (Xvfb).
var film: SubViewport
## What the preview is doing (for the watchdog's report).
var _doing := "start"

## Since 2026-10-19 (docs/STAGE_LADDER_2026-10-19.md, docs/JEWEL_BOX.md) a stage opens on its card,
## the card opens the free first jewel box (modal "box"), and the stage starts in a preparation
## where common skills are refused: scenes that cast skills sit in the middle of a wave
## (_mid_wave), the boss comes through the wave machine (jump_to_boss). `--box-only` replaces the
## old `--rite-only` (still accepted). `--watchdog SEC` (default 1800) fails a stalled run.
func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_watchdog()
	_open_film()
	if has_arg("--biome-only"):
		await _biome_only()
		return
	if has_arg("--spiral-only"):
		await _spiral_only()
		return
	if has_arg("--road-only"):
		await _road_only()
		return
	if has_arg("--motion-only"):
		await _motion_only()
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
	if has_arg("--box-only") or has_arg("--rite-only"):
		await _box_only()
		return
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		_fresh_ladder()
		Arena.start_run(20261009, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		# A run opens on the battlefield card of its stage (no chooser since 2026-10-13).
		check(Arena.modal == "stage", "run opens on the stage 1 battlefield card")
		await _capture(locale + "_stage_card")
		check(tap(screen, "stage:start") and Arena.modal == "box", "battlefield card opens the free first box")
		await _capture(locale + "_box_free")
		await _act("box:pick:%d" % JewelBox.best(Arena.box_cards), func() -> void: Arena.pick_card(JewelBox.best(Arena.box_cards)))
		check(not Arena.summon_result.is_empty(), "the box gives the first hero")
		await _capture(locale + "_summon_new")
		await _act("close", func() -> void: Arena.close_modal())
		check(Arena.modal.is_empty(), "new hero result resumes the stage")
		_prepare_field()
		_no_levelups()
		_mid_wave(1)
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
		check(is_equal_approx(screen.view_3d.world.camera.size, ArenaWorld.CAMERA_SIZE), "following preserves object scale")
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
		Arena.gold = 99999
		for skill in ["blast", "freeze", "ward"]:
			Arena.sim.skill_cooldowns[skill] = 0.0
			await paint(screen)
			check(await _tap_skill(skill), "manual common skill button " + skill)
			await _capture(locale + "_skill_" + skill)
			for n in range(4):
				screen._process(1.0 / 30)
				await _capture(locale + "_skill_" + skill + "_%02d" % n)
		# Boxes open only in a preparation: hold the wave first.
		_back_to_prep()
		check(Arena.begin_summon(), "paid box opens in the preparation")
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
		# Growth is the constellation since 2026-10-17 (the gold shop is gone): its viewer pauses the field.
		check(Arena.open_modal("talent"), "the constellation viewer opens")
		await _capture(locale + "_talents")
		var clock_before := Arena.sim.elapsed
		var positions := _positions()
		screen._process(0.2)
		Arena.sim.step(0.2)
		check(is_equal_approx(Arena.sim.elapsed, clock_before), "growth modal pauses battle clock")
		check(_positions() == positions, "growth modal pauses all actor positions")
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
		Save.cur_run = {"mode": "arena", "wave": 7, "stage": 7, "sim": {"elapsed": 187.0}}
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
		for menu_page in MENU_PAGES:
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
		"layout_resolution": _picture().get_visible_rect().size, "window_resolution": film.size if film != null else DisplayServer.window_get_size()}
	var file := FileAccess.open(out_dir + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file = null
	print("Arena visual review: " + out_dir)
	finish("Arena native 3D and mobile UI")

## Battle motion overhaul proof: mixed weapon types walking while attacking,
## monsters spawning, being hit, dying and besieging the crystal, one skill.
## Positions and damage come from the real simulator; only capture timing is scripted.
func _motion_only() -> void:
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261010, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		Arena.choose_theme(0)
		Arena.confirm_summon()
		Arena.close_modal()
		Arena.heroes.clear()
		Arena.bench.clear()
		var ids := ["echo", "kari", "jokull", "brasa", "triton", "limne"]
		for i in range(ids.size()):
			Arena.gain_hero(Roster.unit_by_id(ids[i]), 3 + i)
			Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + i * TAU / 6) * 150
		Arena.sim.refresh_heroes()
		Arena.sim.monsters.clear()
		Arena.selected = 0
		Arena.gold = 69
		_no_levelups()
		var pool := Roster.theme_pool(Arena.theme_for(1))
		for n in range(14):
			Arena.sim._spawn(pool[n % pool.size()])
			var mo: Dictionary = Arena.sim.monsters[-1]
			var lane := n % ArenaGeometry.route_count()
			mo["pos"] = ArenaGeometry.route_points(lane)[22 + (n / ArenaGeometry.route_count()) * 4]
			mo["route"] = lane
			mo["hp"] = float(mo["max"]) * (0.08 if n < 6 else 0.6)
			mo["vel"] = ArenaGeometry.road_direction(mo["pos"])
		for n in range(2):
			Arena.sim._spawn(pool[(n + 2) % pool.size()])
			var mo: Dictionary = Arena.sim.monsters[-1]
			mo["pos"] = Balance.ARENA_CENTER + Vector2.from_angle(n * PI + 0.4) * (Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS - 1)
			mo["hp"] = 1000000.0
			mo["max"] = 1000000.0
		Arena.sim._rebuild_navigation()
		Arena.sim._cache_positions()
		# Mid-wave: the starburst at frame 30 is refused in a preparation.
		_mid_wave(1)
		await _capture(locale + "_motion_start")
		# The first draw creates the 3D view; pin the camera afterwards so the
		# whole field stays in frame while the selected archer walks.
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = true
		screen.view_3d._apply_camera(Vector3.ZERO)
		# Fifteen captures per second of real simulated battle, the selected
		# archer walking a circle while every guardian keeps attacking.
		for n in range(48):
			for tick in range(4):
				var phase := (n * 4 + tick) * (1.0 / 60) * 1.4
				Arena.sim.heroes[0]["pos"] = Balance.ARENA_CENTER + Vector2(0, -150) + Vector2.from_angle(phase) * 60
				Arena.sim.heroes[0]["h"]["position"] = Arena.sim.heroes[0]["pos"]
				screen._process(1.0 / 60)
			if n == 30:
				Arena.sim.skill_cooldowns["blast"] = 0.0
				await paint(screen)
				check(await _tap_skill("blast"), "starburst fires during the motion capture")
			await _capture(locale + "_motion_%02d" % n)
		check(Arena.sim.monsters.size() < 16, "weak monsters actually died on camera")
		check(screen.view_3d.world.hero_nodes.size() == 6, "six mixed-weapon heroes stayed live")
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/motion-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "text_boxes": _audit_count}, "  ") + "\n")
	file = null
	finish("Battle motion overhaul capture")

## 2026-10-12 spiral field: zoomed-out full-field framing, battle speed chips, the ward
## countdown, cast counts, the boss warning banner and the boss entrance camera.
func _spiral_only() -> void:
	var hero_px := 0.0
	var boss_tops: Array = []
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261012, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		Arena.choose_theme(0)
		Arena.confirm_summon()
		Arena.close_modal()
		_prepare_field()
		_no_levelups()
		_mid_wave(1)
		Arena.gold = 480
		screen.set_speed(1.0)
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = false
		await _capture(locale + "_spiral_field")
		for point in ArenaGeometry.outline(16):
			check(ArenaScreen.BATTLEFIELD.grow(-20).has_point(screen.view_3d.project(point, 0.0)), "whole spiral rim framed inside the open field")
		check(is_equal_approx(screen.view_3d.world.camera.size, ArenaWorld.CAMERA_SIZE), "zoomed-out framing")
		var hero_at: Vector2 = Arena.sim.heroes[Arena.selected]["pos"]
		hero_px = screen.view_3d.project(hero_at, 2.0).distance_to(screen.view_3d.project(hero_at, 0.0))
		# Battle speed chips: each tap selects, the chosen chip reads as the solid one.
		for value in [1, 2, 3]:
			check(tap(screen, "speed:%d" % value) and is_equal_approx(screen.speed, float(value)), "speed chip %d selects" % value)
			await _capture(locale + "_speed_%d" % value)
		screen.set_speed(1.0)
		var menu_rect: Rect2 = Hud.MENU_RECT
		for zone in screen.ui.zones:
			if String(zone["id"]).begins_with("speed:"):
				check(not Rect2(zone["rect"]).intersects(menu_rect), "speed chips never overlap the menu button")
		# Crystal ward: the countdown right after the cast and four seconds later.
		Arena.sim.skill_cooldowns["ward"] = 0.0
		await paint(screen)
		check(tap(screen, "skill:ward") and Arena.sim.shield > 0, "ward cast from the rail")
		await _capture(locale + "_ward_cast")
		for n in range(16): screen._process(0.25)
		check(Arena.sim.shield_t > 3.5 and Arena.sim.shield_t < 4.5, "four simulated seconds of ward elapsed")
		await _capture(locale + "_ward_4s")
		for n in range(8): screen._process(0.25)
		await _capture(locale + "_ward_6s")
		# Casts left 2 / 1 / 0: the exhausted ward is disabled apart from its cooldown.
		Arena.sim.shield = 0.0
		Arena.sim.shield_t = 0.0
		Arena.sim.skill_uses["blast"] = Balance.ARENA_BLAST_USES - 2
		Arena.sim.skill_uses["freeze"] = Balance.ARENA_FREEZE_USES - 1
		Arena.sim.skill_uses["ward"] = Balance.ARENA_WARD_USES
		for id in ["blast", "freeze", "ward"]: Arena.sim.skill_cooldowns[id] = 0.0
		await _capture(locale + "_uses_210")
		check(not tap(screen, "skill:ward"), "exhausted ward button is disabled")
		check(tap(screen, "skill:freeze") and Arena.sim.skill_uses_left("freeze") == 0, "last freeze cast spends the final use")
		await _capture(locale + "_uses_200")
		# Boss warning 4 → 1 (the boss wave's preparation), then the entrance: frames at 15 fps.
		Arena.sim.monsters.clear()
		_no_levelups()
		Arena.sim.jump_to_boss()
		Arena.sim.prep_t = Balance.ARENA_BOSS_WARNING + 0.02
		screen._process(0.05)
		check(Arena.sim.boss_warned and not Arena.sim.boss_spawned, "warning raised four seconds before the boss")
		await _capture(locale + "_boss_warn_04")
		check(Arena.sim.boss_gate().is_finite(), "warning names a gate")
		for second in [3, 2, 1]:
			for n in range(4): screen._process(0.25)
			await _capture(locale + "_boss_warn_%02d" % second)
		var rest_size: float = screen.view_3d.world.camera.size
		var smallest := INF
		for n in range(42):
			screen._process(1.0 / 15)
			await _capture(locale + "_boss_spawn_%02d" % n)
			smallest = minf(smallest, screen.view_3d.world.camera.size)
			for height in [0.08, 1.95]:
				check(ArenaScreen.BATTLEFIELD.has_point(screen.view_3d.project(Balance.ARENA_CENTER, height)), "crystal stays framed during the boss entrance")
		check(Arena.sim.boss_spawned, "boss actually spawned on camera")
		check(smallest < rest_size, "entrance punch zoomed the camera in")
		check(is_equal_approx(screen.view_3d.world.camera.size, rest_size), "camera settled back after the entrance")
		for n in range(12): screen._process(0.25)
		await _capture(locale + "_boss_bar")
		var boss_top := -1.0
		for mo in Arena.sim.monsters:
			if String(mo.get("kind", "")) == "boss": boss_top = screen._monster_top(mo)
		# The bar height is measured from the boss mesh bounds, so it follows whatever
		# body scale the model carries (1.4x today, 2.8x once the walker's change lands).
		check(boss_top > 1.5, "boss bar floats above the measured body (top %.2f)" % boss_top)
		boss_tops.append(boss_top)
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	I18n.set_locale("ko")
	var file := FileAccess.open(out_dir + "/spiral-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "text_boxes": _audit_count,
		"camera_size": ArenaWorld.CAMERA_SIZE, "hero_height_px": hero_px, "boss_bar_heights": boss_tops, "device_fps_measured": false}, "  ") + "\n")
	file = null
	finish("Spiral field framing, speed, ward, casts and boss entrance")

func _road_only() -> void:
	var trajectories: Array = []
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261010, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
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
		for lane in range(ArenaGeometry.route_count()):
			Arena.gain_hero(Roster.unit_by_id(ids[lane]), 3)
			Arena.heroes[lane]["position"] = ArenaGeometry.route_points(lane)[18]
		Arena.sim.refresh_heroes()
		Arena.sim.monsters.clear()
		Arena.selected = -1
		var pool := Roster.theme_pool(Arena.theme_for(1))
		for lane in range(ArenaGeometry.route_count()):
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
				for lane in range(ArenaGeometry.route_count()):
					var monster: Dictionary = Arena.sim.monsters[lane]
					closest[lane] = minf(closest[lane], Vector2(monster["pos"]).distance_to(Arena.sim.heroes[lane]["pos"]))
					if monster["blocked"]: blocked[lane] += 1
			await _capture(locale + "_road_pass_%02d" % n)
			var frame := {"locale": locale, "frame": n, "monsters": []}
			for lane in range(ArenaGeometry.route_count()):
				var at: Vector2 = Arena.sim.monsters[lane]["pos"]
				check(ArenaGeometry.on_road(at, Balance.ARENA_MONSTER_RADIUS), "bypassing monster stays on visible road lane " + str(lane))
				frame["monsters"].append({"lane": lane, "x": at.x, "y": at.y})
			trajectories.append(frame)
		for lane in range(ArenaGeometry.route_count()):
			var path := ArenaGeometry.route_points(lane)
			var progress := _road_progress(Arena.sim.monsters[lane]["pos"], path)
			var hero_progress := _road_progress(Arena.sim.heroes[lane]["pos"], path)
			check(progress > hero_progress + 45.0, "monster visibly passes central guardian lane " + str(lane))
			check(closest[lane] >= Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS - 0.01, "bypass respects the active collision circles lane " + str(lane))
			check(blocked[lane] == 0, "central guardian never stops the monster lane " + str(lane))
		# Real hero-follow views include the road entrances, boundary stones and lamps.
		Arena.selected = 0
		for lane in range(ArenaGeometry.route_count()):
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
		Arena.start_run(20261009, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
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
			# Battle speed chips live in the top strip (user: "배속설정은 상단으로"), and so does the
			# wave HUD's 「바로 시작」 (2026-10-19, PLAN M4: the preparation's countdown is drawn there);
			# every other command stays in the right rail.
			var strip := Rect2(0, 0, Hud.MENU_RECT.position.x, 70)
			var in_strip: bool = String(zone["id"]).begins_with("speed:") or String(zone["id"]) == "wave:start"
			var allowed: bool = ArenaScreen.SIDEBAR.encloses(Rect2(zone["rect"])) or (in_strip and strip.encloses(Rect2(zone["rect"])))
			check(allowed, "all battle commands remain in the right HUD or the top strip (%s at %s)" % [String(zone["id"]), str(Rect2(zone["rect"]))])
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
		_no_levelups()
		_mid_wave(1)
		for skill in ["blast", "freeze", "ward"]:
			Arena.sim.skill_cooldowns[skill] = 0.0
			await paint(screen)
			check(await _tap_skill(skill), "right skill action remains active")
			await _capture(locale + "_skill_" + skill)
		check(Arena.open_modal("talent"), "the constellation viewer opens")
		await _capture(locale + "_talents")
		Arena.close_modal()
		Arena.gain_hero(Roster.unit_by_id("saeta"), 9)
		Arena.open_modal("bench")
		await _capture(locale + "_reserves_selected")
		Arena.close_modal()
		_back_to_prep()
		check(Arena.begin_summon(), "a paid box opens in the preparation")
		await _capture(locale + "_box_paid")
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
		Arena.start_run(20261009, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
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
		for lane in range(ArenaGeometry.route_count()):
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
		check(Arena.open_modal("talent"), "the constellation viewer opens")
		await _capture(locale + "_talents")
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
		Arena.start_run(20261009, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
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
		check(Arena.open_modal("talent"), "the constellation viewer opens")
		await _capture(locale + "_talents")
		Arena.close_modal()
		for id in ["saeta", "glaukos", "jokull"]: Arena.gain_hero(Roster.unit_by_id(id), 9)
		Arena.open_modal("bench")
		await _capture(locale + "_reserves_selected")
		Arena.close_modal()
		_no_levelups()
		_mid_wave(1)
		Arena.gold = 99999
		for skill in ["blast", "freeze", "ward"]:
			Arena.sim.skill_cooldowns[skill] = 0.0
			await paint(screen)
			check(await _tap_skill(skill), "restyled skill button remains active")
			await _capture(locale + "_skill_" + skill)
		main.menu.open()
		main.menu.page = "rules"
		await _capture_canvas(main.menu, locale + "_help")
		main.menu.close()
		Arena.gold = 99999
		_back_to_prep()
		check(Arena.begin_summon(), "a paid box opens in the preparation")
		await _capture(locale + "_box_paid")
		Arena.confirm_summon()
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
		_fresh_ladder()
		Arena.start_run(20261009, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
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
		for menu_page in MENU_PAGES:
			main.menu.page = menu_page
			await _capture_canvas(main.menu, locale + "_menu_" + menu_page)
		main.menu.close()
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		await _capture(locale + "_stage_card")
		Arena.choose_theme(0)
		screen._track_modal()
		await _capture(locale + "_box_free")
		check(zone_of(screen, "box:pull").is_empty() and zone_of(screen, "rite:pull").is_empty(), "no advertising action on the box")
		Arena.confirm_summon()
		await _capture(locale + "_summon_new")
		Arena.close_modal()
		_prepare_field()
		screen.view_3d._follow_offset = Vector3.ZERO
		screen.view_3d._camera_initialized = false
		await _capture(locale + "_field_six")
		Arena.gold = 99999
		check(Arena.open_modal("talent"), "the constellation viewer opens")
		await _capture(locale + "_talents")
		Arena.close_modal()
		for id in ["saeta", "glaukos", "jokull"]:
			Arena.gain_hero(Roster.unit_by_id(id), 9)
		Arena.open_modal("bench")
		screen._track_modal()
		screen.set("_bench_choice", 0)
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
		Arena.start_run(20261009, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
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
		Arena.start_run(20261009, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		Arena.choose_theme(0)
		screen._track_modal()
		await _capture(locale + "_box_free")
		await _reroll_by_window_touch()
		Arena.confirm_summon()
		Arena.close_modal()
		_prepare_field()
		_no_levelups()
		_mid_wave(1)
		Arena.gold = 99999
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
			check(await _tap_skill(skill), "manual common skill button " + skill)
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

## The jewel box over the paused field (modal "box", D1's ceremony in ArenaBoxView): the free
## first box, a reroll through a window-pixel touch on the stretched button, the ceremony's
## frames (the battle clock must not move under it), the box once every free reroll is spent
## (its reroll button off), then a window-pixel touch selecting the sixth hero and moving it.
## The box's own zones (box:reroll, box:pick:<i>) arrive with LB1; until then the touches that
## need them are skipped and noted.
func _box_only() -> void:
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Arena.start_run(20261009, 1)
		main = load("res://game/main.gd").new()
		_mount(main)
		await frames(3)
		main.show_arena()
		screen = main.screen
		screen.set_process(false)
		Arena.choose_theme(0)
		screen._track_modal()
		check(Arena.modal == "box" and not Arena.box_cards.is_empty(), "the card opens the free first box")
		await _capture(locale + "_box_free")
		await _reroll_by_window_touch()
		check(zone_of(screen, "box:pull").is_empty() and zone_of(screen, "rite:pull").is_empty(), "the box exposes no rewarded pull action")
		var clock: float = Arena.sim.elapsed
		for n in range(4):
			screen._process(0.15)
			await _capture(locale + "_box_open_%02d" % n)
		check(is_equal_approx(clock, Arena.sim.elapsed), "the box ceremony preserves paused battle time")
		var guard := 0
		while Arena.can_respin() and guard < 12:
			Arena.respin()
			guard += 1
		await _capture(locale + "_box_spent")
		var reroll := zone_of(screen, "box:reroll")
		if not reroll.is_empty():
			check(not bool(reroll.get("on", true)), "the reroll button is off once every free reroll is spent")
		Arena.confirm_summon()
		await _capture(locale + "_box_result")
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
		drag.position = _picture().get_final_transform() * Vector2(169, 676)
		_picture().push_input(drag, false)
		screen._process(1.0 / 30)
		_window_touch(Vector2(123, 676), false)
		check(Vector2(Arena.sim.heroes[5]["pos"]).distance_to(old_position) > 0.1, "window pixel joystick touch moves the selected hero")
		check(screen.joystick == Vector2.ZERO, "window pixel release stops the joystick")
		main.queue_free()
		main = null
		screen = null
		await frames(4)
	var file := FileAccess.open(out_dir + "/box-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  ") + "\n")
	file = null
	finish("Arena jewel box presentation")

## The reroll of the open box through a touch on the window's pixels (the picture is stretched
## to the window size): it must reach the box view's button. Skipped (and said) while the box
## view registers no reroll zone yet.
func _reroll_by_window_touch() -> void:
	await paint(screen)
	var zone := zone_of(screen, "box:reroll")
	if zone.is_empty() or not bool(zone.get("on", false)):
		print("   (no box:reroll zone drawn yet: the window-pixel reroll touch is skipped)")
		return
	var spins_before := Arena.spins
	var at: Vector2 = Rect2(zone["rect"]).get_center()
	_window_touch(at, true)
	_window_touch(at, false)
	check(Arena.spins > spins_before, "window pixel touch reaches the stretched reroll button")

# --------------------------------------------------------------------------- #
# Battlefield biomes (2026-10-13): fields by biome and rank, the five road shapes,
# gate / junction close-ups, a stage switch and the cost of a rebuild
# --------------------------------------------------------------------------- #
## Five biomes at rank 1 / 3 / 5 (the default "fields" set of the review).
const BIOME_FIELDS := ["calm_lake", "tidal_flats", "maelstrom_sea",
	"kiln_yard", "sulfur_springs", "volcano_crater",
	"spring_grove", "misty_cedar", "worldtree_roots",
	"gravel_hills", "broken_wall", "rift_chasm",
	"first_snow_hills", "drift_ice_sea", "polar_night"]
const REVIEW_SEED := 20261013
## The ladder stage the battlefield reviews play: past Balance.ARENA_MIX_STAGE every kind of
## monster (swarm, runner, heavy, caster, flyer, immune bodies) is in a stage's waves, as the
## old ten-stage run's first stage had them. Its battlefield is the one under review.
const REVIEW_STAGE := 41

func _theme_index(id: String) -> int:
	for i in range(Roster.THEMES.size()):
		if String(Roster.THEMES[i]["id"]) == id: return i
	printerr("!! unknown theme " + id)
	return 0

func _biome_only() -> void:
	I18n.set_locale(arg("--locale", "ko"))
	# Pictures only: a music stream that is still fading when the tool quits is reported
	# as a leak at exit.
	Save.music = false
	Save.sfx = false
	var sets := arg("--sets", "fields,shapes,detail,switch,timing").split(",", false)
	var report := {"fields": {}, "shapes": {}, "detail": [], "switch": {}, "timing": {}}
	Arena.start_run(REVIEW_SEED, REVIEW_STAGE)
	main = load("res://game/main.gd").new()
	_mount(main)
	await frames(3)
	main.show_arena()
	if not (main.screen is ArenaScreen):
		# A game script failed to compile (someone is mid-edit): stop instead of hanging.
		printerr("!! the arena screen did not open; see the script errors above")
		get_tree().quit(1)
		return
	screen = main.screen
	screen.set_process(false)
	if "fields" in sets:
		var wanted := arg("--themes", "")
		var ids: Array = Array(wanted.split(",", false)) if not wanted.is_empty() and wanted != "all" else BIOME_FIELDS.duplicate()
		if wanted == "all":
			ids.clear()
			for theme in Roster.THEMES: ids.append(String(theme["id"]))
		for id in ids:
			var index := _theme_index(String(id))
			await _enter_field(index)
			report["fields"][id] = await _field_shots(String(id))
	if "shapes" in sets:
		# The five road shapes on one battlefield, each at a turn that shows a south gate.
		var index := _theme_index(arg("--shape-theme", "misty_cedar"))
		var id := String(Roster.THEMES[index]["id"])
		var home := ArenaGeometry.layout_for_theme(index)
		for shape in ArenaGeometry.SHAPE_ORDER:
			var key := "%s:%d:0" % [shape, 1 if shape == "blades" else 2]
			await _enter_field(index, key)
			report["shapes"][shape] = await _field_shots("shape_%s_%s" % [id, shape])
		ArenaGeometry.use_layout(home)
	if "detail" in sets:
		for id in arg("--detail-themes", "calm_lake,volcano_crater,misty_cedar,rift_chasm,polar_night").split(",", false):
			var index := _theme_index(id)
			for shape in ArenaGeometry.SHAPE_ORDER:
				await _enter_field(index, "%s:%d:%d" % [shape, (index + ArenaGeometry.SHAPE_ORDER.find(shape) * 3) % 8, index % 2], false)
				report["detail"].append_array(await _detail_shots("%s_%s" % [id, shape]))
			ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(index))
	if "switch" in sets:
		report["switch"] = await _stage_switch(arg("--switch-from", "spring_grove"), arg("--switch-to", "volcano_crater"))
	if "timing" in sets:
		report["timing"] = await _build_timing()
	if "vfx" in sets:
		# Battle effects over the ground of a field: a volley and the three common skills.
		for id in arg("--vfx-themes", "first_snow_hills,quarry_pit,kiln_yard,deep_trench").split(",", false):
			await _enter_field(_theme_index(id))
			_review_crowd()
			for n in range(24):
				screen._process(1.0 / 30)
				screen.queue_redraw()
				await frames(1)
			await _capture("vfx_%s_volley" % id)
			for skill in ["blast", "freeze", "ward"]:
				Arena.sim.skill_cooldowns[skill] = 0.0
				await paint(screen)
				check(await _tap_skill(skill), "skill %s cast on %s" % [skill, id])
				for n in range(4):
					for tick in range(9):
						screen._process(1.0 / 30)
						screen.queue_redraw()
						await frames(1)
					await _capture("vfx_%s_%s_%d" % [id, skill, n])
	if "props" in sets:
		await _props_sheet()
	if "probe" in sets:
		await _tint_probe()
	report["checks"] = checks
	report["failures"] = failures
	report["picture"] = [_picture().get_visible_rect().size.x, _picture().get_visible_rect().size.y]
	var file := FileAccess.open(out_dir + "/biome-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file = null
	finish("Battlefield biomes")

## Start a run on `index` (tool API: no chooser exists) and stand a review squad on it.
## `layout` previews another road shape on the same battlefield.
func _enter_field(index: int, layout: String = "", crowd: bool = true) -> void:
	Arena.start_run(REVIEW_SEED, REVIEW_STAGE)
	# A restarted run counts its monsters from one again; the world keys bodies by that
	# number, so bodies of the previous field must not be taken for the new ones.
	var live: ArenaWorld = screen.view_3d.world as ArenaWorld
	if live != null:
		for node in live.monster_nodes.values(): node.free()
		live.monster_nodes.clear()
		live._dying.clear()
		live._monster_status.clear()
	check(Arena.choose_theme(index), "tool API puts the battlefield on stage 1")
	Arena.confirm_summon()
	Arena.close_modal()
	if not layout.is_empty() and ArenaGeometry.use_layout(layout):
		Arena.sim._build_navigation()
	_review_squad()
	_no_levelups()
	# In the middle of wave 1 (skills are refused in a preparation; no countdown, no banner).
	_mid_wave(1)
	screen.speed = 1.0
	screen.view_3d._follow_offset = Vector3.ZERO
	screen.view_3d._camera_initialized = false
	screen._track_modal()
	if crowd: await paint(screen)

func _open_ground(angle: float, radius: float) -> Vector2:
	for step in range(24):
		var at := Balance.ARENA_CENTER + Vector2.from_angle(angle + step * 0.13) * radius
		if not ArenaGeometry.on_road(at, -Balance.ARENA_HERO_RADIUS): return at
	return Balance.ARENA_CENTER + Vector2.from_angle(angle) * radius

## Six mixed guardians: three by the altar, three out on the open ground.
func _review_squad() -> void:
	Arena.heroes.clear()
	Arena.bench.clear()
	var ids := ["limne", "brasa", "echo", "pip", "morrigan", "dummy"]
	for i in range(Balance.ARENA_HERO_LIMIT):
		Arena.gain_hero(Roster.unit_by_id(ids[i]), (i + 1) % 10)
		Arena.heroes[i]["position"] = _open_ground(-PI * 0.5 + i * TAU / 6, 150.0 if i % 2 == 0 else 345.0)
	Arena.sim.refresh_heroes()
	Arena.selected = 1
	Arena.gold = 480
	Arena.sim.monsters.clear()
	Arena.sim.bullets.clear()
	Arena.sim.events.clear()
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.8
	Arena.sim._spawn_t = 1.0e9

## The stage's own monster mix (the regular rows of all its waves: swarms, runners, heavies,
## casters, flyers) spread along every road from the gate to the plaza.
func _review_crowd() -> void:
	var spawns: Array = []
	for w in range(1, Balance.ARENA_WAVES):
		for entry in Arena.wave_spawns(Arena.stage, w):
			if String(entry["m"]["kind"]) != "boss": spawns.append(entry["m"])
	if spawns.is_empty(): spawns = Roster.theme_pool(Arena.theme_for(1))
	var lanes := ArenaGeometry.route_count()
	var per_lane := maxi(5, 24 / lanes)
	var n := 0
	for lane in range(lanes):
		var path := ArenaGeometry.route_points(lane)
		for k in range(per_lane):
			Arena.sim._spawn(spawns[(n * 7) % spawns.size()])
			var mo: Dictionary = Arena.sim.monsters[-1]
			var at := clampi(int(path.size() * (0.012 + 0.88 * pow(float(k) / per_lane, 1.2))), 0, path.size() - 3)
			mo["pos"] = path[at]
			mo["route"] = lane
			mo["max"] = float(mo["max"]) * 40.0
			mo["hp"] = float(mo["max"]) * (0.4 + 0.55 * fposmod(n * 0.37, 1.0))
			mo["vel"] = (path[at + 1] - path[at]).normalized()
			n += 1
	Arena.sim.events.clear()
	Arena.sim._rebuild_navigation()
	Arena.sim._cache_positions()

func _world_image() -> Image:
	await RenderingServer.frame_post_draw
	return screen.view_3d.viewport.get_texture().get_image()

## Three pictures of one field: the empty ground (gates before the first monster), the
## live battle as the player sees it, and the same moment without the HUD. Returns where
## every actor stands in the HUD-less picture so contrast can be measured on it.
func _field_shots(label: String) -> Dictionary:
	await paint(screen)
	(await _world_image()).save_png(out_dir + "/empty_" + label + ".png")
	# Where the bare floor and the bare road are in that picture (for lightness sampling):
	# points well away from any road edge and from the guardians standing on the field.
	var floor_points: Array = []
	var road_points: Array = []
	var view: ArenaWorld = screen.view_3d.world
	for n in range(160):
		var at := Balance.ARENA_CENTER + Vector2.from_angle(n * 2.399963) * (130.0 + sqrt((n + 0.5) / 160.0) * (ArenaGeometry.RADIUS - 200.0))
		if ArenaGeometry.on_road(at, -26.0): continue
		var clear := true
		for hero in Arena.sim.heroes:
			if Vector2(hero["pos"]).distance_to(at) < 70.0: clear = false
		if not clear: continue
		var pixel := view.screen(at, 0.0)
		floor_points.append([pixel.x, pixel.y])
	for polyline in ArenaGeometry.road_polylines():
		for i in range(6, polyline.size() - 6, 5):
			var clear := true
			for hero in Arena.sim.heroes:
				if Vector2(hero["pos"]).distance_to(polyline[i]) < 80.0: clear = false
			if not clear: continue
			var pixel := view.screen(polyline[i], 0.0)
			road_points.append([pixel.x, pixel.y])
	_review_crowd()
	# Nine tenths of a second of real battle, drawn every tick like the game does, so
	# bodies finish stepping in and the guardians are mid-volley.
	for n in range(27):
		screen._process(1.0 / 30)
		screen.queue_redraw()
		await frames(1)
	await _capture("screen_" + label)
	(await _world_image()).save_png(out_dir + "/world_" + label + ".png")
	var world: ArenaWorld = screen.view_3d.world
	var actors: Array = []
	for i in range(Arena.sim.heroes.size()):
		var at: Vector2 = Arena.sim.heroes[i]["pos"]
		var foot := world.screen(at, 0.05)
		var head := world.screen(at, 1.9)
		actors.append({"kind": "hero", "id": String(Arena.sim.heroes[i]["h"]["unit"]["id"]), "foot": [foot.x, foot.y], "head": [head.x, head.y]})
	for mo in Arena.sim.monsters:
		var at: Vector2 = mo["pos"]
		var foot := world.screen(at, 0.05)
		var head := world.screen(at, screen._monster_top(mo))
		actors.append({"kind": "monster", "id": String(mo["m"]["id"]), "body": String(mo["m"]["body"]), "foot": [foot.x, foot.y], "head": [head.x, head.y]})
	var theme: Dictionary = Arena.theme_for(1)
	var baked: Dictionary = load("res://game/3d/arena_biome.gd").FLOOR_L
	return {"theme": String(theme["id"]), "body": String(theme["main_body"]), "rank": int(theme["rank"]),
		"layout": ArenaGeometry.layout(), "gates": ArenaGeometry.route_count(), "actors": actors,
		"baked_floor_l": float(baked.get(String(theme["id"]), -1.0)), "wash": float(world.ground_wash),
		"floor_points": floor_points, "road_points": road_points}

func _closeup(focus: Vector2, size: float, name: String) -> void:
	var world: ArenaWorld = screen.view_3d.world
	var target := StellarWorld.world(focus)
	world.camera.size = size
	world.camera.position = target + Vector3(-3.0, 19.0, 23.0)
	world.camera.look_at(target + Vector3(0, 0.4, 0), Vector3.UP)
	await frames(2)
	(await _world_image()).save_png(out_dir + "/" + name + ".png")

## Close views of what a full-field picture cannot settle: the plaza junction, every
## gate and every feeder T-join of the current layout.
func _detail_shots(label: String) -> Array:
	var made: Array = []
	await paint(screen)
	await _closeup(Balance.ARENA_CENTER, 11.0, "detail_%s_plaza" % label)
	made.append("detail_%s_plaza" % label)
	for lane in range(ArenaGeometry.route_count()):
		await _closeup(ArenaGeometry.gate_point(lane, 70.0), 10.0, "detail_%s_gate%d" % [label, lane])
		made.append("detail_%s_gate%d" % [label, lane])
	var roads := ArenaGeometry.road_polylines()
	var joins := 0
	for i in range(roads.size()):
		if ArenaGeometry.road_layer(i) != 1: continue
		await _closeup(roads[i][-1], 9.0, "detail_%s_join%d" % [label, joins])
		made.append("detail_%s_join%d" % [label, joins])
		joins += 1
	return made

## The staged kills feed the run's experience; a level-up would open the talent offer (a
## modal that pauses the field until a pick, and opens whenever a preparation begins). Sink
## the experience so it never comes, and close an offer that is already open.
func _no_levelups() -> void:
	var run = Arena.sim.run if Arena.sim != null else null
	if run == null: return
	if "pending_levels" in run: run.pending_levels = 0
	if "xp" in run: run.xp = -1.0e9
	if "talent_offer" in run and not run.talent_offer.is_empty():
		run.talent_offer.clear()
		if String(run.modal) == "talent": run.close_modal()

## One real stage change on the same screen (2026-10-19 ladder): the boss of STAGE 1 falls, the
## clear beat runs, the victory panel stands, then the run's next stage opens on `to_id` under its
## card (what the result's 「다음 STAGE」 starts), the card is confirmed, the free first box is
## taken, the preparation is skipped (「바로 시작」) and the first monsters come through the new gates.
func _stage_switch(from_id: String, to_id: String) -> Dictionary:
	await _enter_field(_theme_index(from_id))
	_review_crowd()
	# The boss wave (its list held, so the HUD reads WAVE 10), its boss placed in the frame.
	_mid_wave(Balance.ARENA_WAVES)
	Arena.sim._spawn(Arena.boss_for(Arena.stage))
	var boss: Dictionary = Arena.sim.monsters[-1]
	var path := ArenaGeometry.route_points(0)
	boss["pos"] = path[int(path.size() * 0.42)]
	boss["route"] = 0
	boss["vel"] = Vector2.ZERO
	Arena.sim.boss_spawned = true
	Arena.sim.boss_warned = true
	Arena.sim._spawn_t = 1.0e9
	Arena.sim._rebuild_navigation()
	Arena.sim._cache_positions()
	var frame := 0
	var card_frames := 0
	var result_frames := 0
	var after := 0
	var marks := {}
	while frame < 170 and after < 46:
		if frame == 10:
			boss["hp"] = 0.0
			marks["boss_down"] = frame
		var before_stage := Arena.stage
		# Fifteen pictures a second up to the card, then two simulated ticks a picture
		# so the first assault of the new stage fits in the sequence.
		for tick in range(2 if Arena.stage > REVIEW_STAGE and Arena.modal.is_empty() else 1): screen._process(1.0 / 15)
		if Arena.modal == "result" and Arena.stage == REVIEW_STAGE:
			if result_frames == 0: marks["result"] = frame
			result_frames += 1
			if result_frames == 12:
				# The result's next stage, on the battlefield under review.
				check(Arena.next_stage(), "the cleared stage opens the next one")
				Arena.stage_themes[Arena.stage - 1] = _theme_index(to_id)
				Arena.sim = null
				Arena._open_stage(Arena.stage)
				_no_levelups()
				screen._track_modal()
		if Arena.stage != before_stage: marks["new_field"] = frame
		if Arena.modal == "stage" and Arena.stage > REVIEW_STAGE:
			card_frames += 1
			if card_frames == 18:
				await paint(screen)
				check(tap(screen, "stage:start"), "stage card confirms into the new battlefield")
				Arena.confirm_summon()
				Arena.close_modal()
				_no_levelups()
				Arena.sim.skip_prep()
				marks["card_closed"] = frame
		elif Arena.stage > REVIEW_STAGE and Arena.modal.is_empty(): after += 1
		await _capture("switch_%03d" % frame)
		frame += 1
	check(Arena.stage == REVIEW_STAGE + 1 and String(Arena.theme_for(1)["id"]) == to_id, "stage switch reached the next battlefield")
	check(screen.view_3d.world.theme_id == to_id, "world rebuilt for the next battlefield")
	return {"from": from_id, "to": to_id, "frames": frame, "marks": marks}

## Authoring aid: does an instance tint reach the scenery shader as it was passed?
func _tint_probe() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var holder := Node3D.new()
	viewport.add_child(holder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.position = Vector3(0, 10, 0)
	camera.rotation = Vector3(-PI / 2, 0, 0)
	holder.add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	holder.add_child(environment)
	var scn = load("res://game/3d/arena_scenery.gd").new()
	var tints := [Color("#3f8068"), Color("#808080"), Color("#ffffff"), Color("#ff0000")]
	for i in range(4):
		scn.part("box", Vector3(-1.5 + i, 0, -0.5), Vector3(0.8, 0.2, 0.8), tints[i])
		var plain := StellarModels.part(holder, "box", Vector3(-1.5 + i, 0, 0.5), Vector3(0.8, 0.2, 0.8), tints[i])
		plain.material_override = plain.material_override.duplicate()
		(plain.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# A plain mesh with a vertex colour (the kerbs), and a template part that shows the
	# instance's second tint (a tree trunk seen from above is too thin: use a mushroom stem).
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for corner in [Vector3(-0.4, 0, -0.1), Vector3(0.4, 0, -0.1), Vector3(0.4, 0, 0.1), Vector3(-0.4, 0, -0.1), Vector3(0.4, 0, 0.1), Vector3(-0.4, 0, 0.1)]:
		tool.set_normal(Vector3.UP)
		tool.set_color(Color("#808080"))
		tool.set_uv(Vector2(1, 0))
		tool.set_uv2(Vector2(0, 0))
		tool.add_vertex(corner + Vector3(-0.5, 0.3, 0.0))
	var strip := MeshInstance3D.new()
	strip.mesh = tool.commit()
	strip.material_override = scn.material
	holder.add_child(strip)
	scn.stand("mush0", Vector3(0.5, 0.2, 0.0), Vector3(0.1, 0.4, 0.1), 0.0, Color("#000000"), Color("#808080"))
	scn.stand("column", Vector3(0.5, 0.0, 0.0), Vector3(1.6, 0.2, 0.3), 0.0, Color("#000000"), Color("#808080"))
	scn.commit(holder)
	await frames(4)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var vertex_pixel := image.get_pixel(96, 64)
	print("vertex colour 808080 -> %d %d %d" % [vertex_pixel.r8, vertex_pixel.g8, vertex_pixel.b8])
	for x in range(150, 175, 4):
		var second_pixel := image.get_pixel(x, 64)
		print("second tint 808080 at x %d -> %d %d %d" % [x, second_pixel.r8, second_pixel.g8, second_pixel.b8])
	for i in range(4):
		var pixel := image.get_pixel(32 + i * 64, 32)
		var reference := image.get_pixel(32 + i * 64, 96)
		print("tint %s -> scenery %d %d %d   standard material %d %d %d" % [tints[i].to_html(false), pixel.r8, pixel.g8, pixel.b8, reference.r8, reference.g8, reference.b8])
	image.save_png(out_dir + "/tint_probe.png")
	viewport.queue_free()

## Every scenery template side by side under the arena lights (authoring aid).
func _props_sheet() -> void:
	var scenery_script: GDScript = load("res://game/3d/arena_scenery.gd")
	await paint(screen)
	var world: ArenaWorld = screen.view_3d.world
	for child in world.terrain.get_children():
		if child is Node3D and not child is Light3D: child.visible = false
	world.actors.visible = false
	if is_instance_valid(world.weather): world.weather.visible = false
	var stage := Node3D.new()
	world.add_child(stage)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor.mesh = plane
	floor.material_override = StellarModels.material(Color("#3d4a4c"))
	stage.add_child(floor)
	var scn = scenery_script.new()
	var kinds := ["rock0", "rock1", "rock2", "rock3", "spire0", "spire1", "spire2", "column", "hoodoo0", "hoodoo1",
		"fir0", "fir1", "fir2", "tree0", "tree1", "tree2", "dead0", "dead1", "mush0", "mush1",
		"tuft", "reed", "bamboo", "slab0", "slab1", "slab2", "pad", "crystal0", "crystal1", "dome",
		"arch", "pyramid", "box", "stone", "cylinder", "cone", "pentagon", "sphere", "ring"]
	var tints := {"fir": [Color("#3f8068"), Color("#6a5340")], "tree": [Color("#4f8a3f"), Color("#5a4636")],
		"mush": [Color("#c9584f"), Color("#e6dcc2")], "bamboo": [Color("#7fa35a"), Color("#4f8a3f")],
		"reed": [Color("#8a9a55"), Color("#6b4a2e")], "tuft": [Color("#5f9a4a"), Color("#5f9a4a")],
		"crystal": [Color("#9b7bea"), Color("#9b7bea")], "spire": [Color("#a8d8ee"), Color("#a8d8ee")],
		"dead": [Color("#3a3230"), Color("#3a3230")], "pad": [Color("#4f9a5a"), Color("#4f9a5a")]}
	for i in range(kinds.size()):
		var kind: String = kinds[i]
		var base := kind.rstrip("0123456789")
		var pair: Array = tints.get(base, [Color("#8a8f94"), Color("#8a8f94")])
		if kind in ["rock0", "rock1", "rock2", "rock3"]:
			var grey: Color = [Color("#404040"), Color("#808080"), Color("#b4b4b4"), Color("#ffffff")][int(kind.substr(4))]
			pair = [grey, grey]
		var at := Vector3((i % 10 - 4.5) * 2.5, 0.0, (i / 10 - 1.5) * 3.2)
		var size := Vector3(1.6, 1.6, 1.6)
		if base in ["fir", "tree", "dead", "bamboo", "spire", "hoodoo", "column"]: size = Vector3(1.6, 2.4, 1.6)
		if base in ["slab"]: size = Vector3(1.6, 0.25, 1.6)
		var lift := 0.8 if base in ["box", "stone", "cylinder", "cone", "pentagon", "sphere"] else 0.05 if base == "ring" else 0.0
		scn.stand(kind, at + Vector3(0, lift, 0), size, 0.4, pair[0], pair[1], 0.7 if base in ["crystal", "mush"] else 0.0, 0.05)
	scn.material.set_shader_parameter("wind", 1.0)
	scn.commit(stage)
	for row in range(2):
		await _closeup(Balance.ARENA_CENTER + Vector2(0, (row - 0.5) * 6.4) * StellarWorld.UNIT, 26.0, "props_%d" % row)
	scn.material.set_shader_parameter("cover_amount", 1.0)
	await _closeup(Balance.ARENA_CENTER + Vector2(0, -3.2) * StellarWorld.UNIT, 26.0, "props_snow")
	stage.queue_free()

func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() if indices != null and indices.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total

## How long a stage switch spends rebuilding the map on this machine, and what the
## built field costs to draw.
func _build_timing() -> Dictionary:
	await paint(screen)
	var world: ArenaWorld = screen.view_3d.world
	var rid := screen.view_3d.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var out := {}
	var home := ArenaGeometry.layout()
	# The default fifteen, the fields named by --themes, or every field with --themes all.
	var wanted := arg("--themes", "")
	var ids: Array = BIOME_FIELDS.duplicate()
	if wanted == "all":
		ids.clear()
		for theme in Roster.THEMES: ids.append(String(theme["id"]))
	elif not wanted.is_empty():
		ids = Array(wanted.split(",", false))
	for id in ids:
		var index := _theme_index(id)
		# The same battle on every field: six guardians and the review crowd.
		await _enter_field(index)
		_review_crowd()
		for n in range(6):
			screen._process(1.0 / 30)
			screen.queue_redraw()
			await frames(1)
		var samples: Array = []
		for n in range(4):
			world._map_key = ""
			var started := Time.get_ticks_usec()
			world.build_map(Roster.THEMES[index])
			samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
			await frames(3)
		await paint(screen)
		await frames(6)
		var gpu := 0.0
		var cpu := 0.0
		for n in range(12):
			await frames(1)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid) / 12.0
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) / 12.0
		var nodes := 0
		var triangles := 0
		for mesh in world.terrain.find_children("*", "MeshInstance3D", true, false):
			nodes += 1
			triangles += _mesh_triangles(mesh.mesh)
		# Instanced scenery: every instance draws its template.
		var instances := 0
		for group in world.terrain.find_children("*", "MultiMeshInstance3D", true, false):
			nodes += 1
			instances += group.multimesh.instance_count
			triangles += group.multimesh.instance_count * _mesh_triangles(group.multimesh.mesh)
		var frame_primitives := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		var frame_draws := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		# What the map alone costs a frame: the same counters with every actor hidden.
		world.actors.visible = false
		world.projectiles.visible = false
		await frames(4)
		var map_primitives := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		var map_draws := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var map_gpu := 0.0
		for n in range(12):
			await frames(1)
			map_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid) / 12.0
		world.actors.visible = true
		world.projectiles.visible = true
		samples.sort()
		out[id] = {"build_ms_first": samples[-1], "build_ms": samples[0], "build_ms_median": samples[1],
			"terrain_meshes": nodes, "terrain_triangles": triangles, "scenery_instances": instances,
			"map_primitives": map_primitives, "map_draw_calls": map_draws, "map_gpu_ms": map_gpu,
			"frame_primitives": frame_primitives, "frame_draw_calls": frame_draws,
			"shadow_draw_calls": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"gpu_ms": gpu, "cpu_ms": cpu, "lights": world.terrain.find_children("*", "OmniLight3D", true, false).size()}
		print("build %s: %.1f ms (first %.1f), %d triangles in %d meshes" % [id, samples[0], samples[-1], triangles, nodes])
	ArenaGeometry.use_layout(home)
	return out

func _drag(logical: Vector2, pointer: int = 0) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = pointer
	drag.position = logical
	screen._input(drag)

func _window_touch(logical: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 7
	event.position = _picture().get_final_transform() * logical
	event.pressed = pressed
	_picture().push_input(event, false)

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
		mo["pos"] = ArenaGeometry.route_points(n % ArenaGeometry.route_count())[6 + (n / ArenaGeometry.route_count()) * 5]
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
	_doing = name
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
		var theme: Dictionary = Roster.THEMES[clampi(Arena.theme_index, 0, Roster.THEMES.size() - 1)]
		check(I18n.t(String(theme["ko"])) in shown, "current battlefield name is rendered in the HUD")
	Look.text_audit_enabled = false
	await snap(out_dir + "/" + name + ".png")

# --------------------------------------------------------------------------- #
# The 2026-10-19 flow: waves, preparations, the box; the watchdog
# --------------------------------------------------------------------------- #
## The guide's tabs (MenuOverlay: "box" is the jewel box page on the title and the battlefield).
const MENU_PAGES := ["menu", "rules", "box", "elements"]

## Wave `n` in progress: opened (ArenaSim.begin_wave) as if long ago, so no banner is due, and
## its list held so the staged monsters are the only ones. Common skills can be cast (they are
## refused in a preparation) and the wave never ends on its own.
func _mid_wave(n: int) -> void:
	var sim := Arena.sim
	sim.begin_wave(n)
	sim._spawn_t = 1.0e9
	sim.wave_t = 30.0
	var events: Array = sim.events
	for i in range(events.size() - 1, -1, -1):
		if String(events[i].get("t", "")) == "arena_wave": events.remove_at(i)

## Hold the current wave the real way (the rest of its list steps in and everything on the field
## falls): the next preparation opens, where boxes and level-up picks are allowed.
func _back_to_prep() -> void:
	var sim := Arena.sim
	_no_levelups()
	if not sim.in_prep():
		if sim.is_boss_wave(sim.wave_no): sim.begin_wave(maxi(1, sim.wave_no - 1))
		while sim._wave_spawned < sim._wave_list.size(): sim._spawn_next()
		for mo in sim.monsters: mo["hp"] = 0.0
		sim._cache_positions()
		sim._reap()
	_no_levelups()
	check(sim.in_prep(), "the wave was held: a preparation is open")

## A common skill through its rail button, as a player casts it: the starburst's button arms
## the aim (F6) and a tap on the battlefield (Harness.tap_at) casts it at `at`, by default on the
## monster nearest the crystal; frost and ward cast at once. True when a cast was spent.
func _tap_skill(skill: String, at: Vector2 = Vector2.INF) -> bool:
	var used := int(Arena.sim.skill_uses.get(skill, 0))
	var state: Dictionary = Arena.sim.skill_state(skill) if Arena.sim.has_method("skill_state") else {}
	# A running screen notices a closed window every frame; a held one would only notice it after
	# the tap (and that notice ends the aim the tap just began).
	screen._track_modal()
	await paint(screen)
	var tapped := tap(screen, "skill:" + skill)
	var aimed := false
	if tapped and skill == "blast" and screen.has_method("aiming") and screen.aiming():
		aimed = true
		var point := at if at.is_finite() else _blast_point()
		tap_at(screen, screen.view_3d.project(point, 0.0))
	var cast := int(Arena.sim.skill_uses.get(skill, 0)) == used + 1
	if not cast:
		print("   skill %s not cast: zone %s, aimed %s, state %s" % [skill, "tapped" if tapped else "off/missing", aimed, JSON.stringify(state)])
	return cast

## Where a player would drop the starburst: on the live monster nearest the crystal (what the
## simulator's own target was before the aim), else open ground below the crystal.
func _blast_point() -> Vector2:
	var best := Vector2.INF
	for mo in Arena.sim.monsters:
		if float(mo["hp"]) <= 0.0: continue
		var point: Vector2 = mo["pos"]
		if not best.is_finite() or point.distance_to(Balance.ARENA_CENTER) < best.distance_to(Balance.ARENA_CENTER): best = point
	return best if best.is_finite() else Balance.ARENA_CENTER + Vector2(0, 160)

## A staged victory unlocks the next ladder stage in memory (nothing is written); the title of
## the next language pass would then read it. Every pass starts from STAGE 1.
func _fresh_ladder() -> void:
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	Save.last_clear = {}

## Tap the screen's own zone `id` when it is drawn and on; otherwise (a surface that is not
## wired yet) do what the zone stands for. True when the real zone answered.
func _act(id: String, fallback: Callable) -> bool:
	# A running screen notices a window change every frame; a held one only when asked.
	screen._track_modal()
	await paint(screen)
	if tap(screen, id): return true
	fallback.call()
	return false

## A preview that stops making progress (an awaited step that died on a script error) would hang
## until the driver's timeout. After `--watchdog` seconds of real time it reports and fails.
func _watchdog() -> void:
	var limit := arg_float("--watchdog", 1800.0)
	if limit <= 0.0: return
	var timer := get_tree().create_timer(limit, true, false, true)
	timer.timeout.connect(func() -> void:
		printerr("!! watchdog: no end after %.0f s; last capture: %s" % [limit, _doing])
		print("판정: 실패")
		get_tree().quit(2))

