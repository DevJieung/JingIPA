extends Harness

func fresh(count: int = 2) -> void:
	Fixture.fresh(8102026, count)
	Run.phase = Run.Phase.SHOP
	Run.autosave()

func _ready() -> void:
	if not require_no_save(): return
	fresh()
	var point := Vector2(110.25, 320.75)
	var internal_slot := int(Run.heroes[0]["post"])
	check(Run.move_hero_to(0, point), "fixed posts do not constrain placement")
	check(Run.heroes[0]["post"] == internal_slot, "free move preserves combat identity")
	var saved := Run.snapshot().duplicate(true)
	check(Run.restore(saved) and Run.hero_position(Run.heroes[0]) == point, "fractional coordinates survive resume")
	for bad in [Vector2.INF, Vector2(NAN, 0), Vector2(21, 113), Balance.ARENA_CENTER,
			Balance.route_points(0)[2], Run.hero_position(Run.heroes[1])]:
		var before := Run.snapshot()
		check(not Run.move_hero_to(0, bad) and Run.snapshot() == before, "invalid ground is rejected without mutation")
	for value in [["110", 320], [INF, 320], [NAN, 320], [110], [416, 420], [156, 300]]:
		var before := Run.snapshot()
		var malformed := saved.duplicate(true)
		malformed["heroes"][0]["pos"] = value
		check(not Run.restore(malformed) and Run.snapshot() == before, "invalid saved coordinates rejected atomically")
	var overlap := saved.duplicate(true)
	overlap["heroes"][1]["pos"] = overlap["heroes"][0]["pos"].duplicate()
	check(not Run.restore(overlap), "overlapping saved heroes rejected")
	var legacy := saved.duplicate(true)
	legacy["formation_v"] = 2
	for hero in legacy["heroes"]: hero.erase("pos")
	check(Run.restore(legacy), "previous post-only saves migrate")
	for hero in Run.heroes:
		check(Run.hero_position(hero) == Balance.post_position(int(hero["post"])), "legacy physical location retained")
	check(Run.move_hero_to(0, point), "migrated hero moves freely")
	Run.gain_hero(Roster.UNITS[13], 4, false, false)
	var incoming_id := String(Run.bench[0]["unit"]["id"])
	check(Run.swap_field_bench(0, 0), "reserve exchange at arbitrary position")
	check(Run.hero_position(Run.heroes[0]) == point and Run.heroes[0]["unit"]["id"] == incoming_id,
		"replacement inherits physical position")
	check(not Run.bench[0].has("position"), "reserve card has no stale physical position")
	check(Run.bench_to_position(0, Vector2(730, 430)), "reserve deploys directly on chosen ground")
	check(Run.restore(Run.snapshot()), "reserve exchange and deployment save remains valid")
	# Automatic summons must find space even when free placement covers a default spawn.
	fresh(1)
	check(Run.move_hero_to(0, Balance.post_position(0)), "move onto another default spawn")
	Run.gain_hero(Roster.UNITS[1], 3)
	check(Run.placement_error(Run.hero_position(Run.heroes[1]), 1).is_empty(), "auto deployment finds unoccupied ground")

	fresh()
	Run.phase = Run.Phase.BATTLE
	Run.battle_checkpoint = Run.snapshot(false)
	Run.autosave()
	var start := Save.cur_run.duplicate(true)
	var sim := BattleSim.new()
	sim.setup(Run, 1, 8102026)
	sim.heroes[0]["cool"] = 0.4
	sim.heroes[0]["dmg"] = 123.0
	sim._pending.append({"src": 0, "wait": 0.2})
	sim.bullets.append({"owner": 0, "p": Vector2(500, 300)})
	Run.gold += 200
	Run.lives -= 1
	check(sim.move_hero_to(0, point) and sim.heroes[0]["pos"] == point, "battle origin follows arbitrary placement")
	check(sim.heroes[0]["cool"] == 0.4 and sim.heroes[0]["dmg"] == 123.0 and sim._pending.size() == 1
		and sim.bullets.size() == 1, "cooldowns damage windups and flying projectiles survive movement")
	for key in ["gold", "lives", "rng", "kills"]:
		check(Save.cur_run[key] == start[key], "movement saves preserve wave-start state " + key)
	check(Save.cur_run["heroes"][0]["pos"] == [point.x, point.y], "free battle position autosaved")
	check(Run.battle_checkpoint["heroes"][0]["pos"] == [point.x, point.y], "revival checkpoint retains placement")
	check(Run.restore(Save.cur_run) and Run.hero_position(Run.heroes[0]) == point, "battle resume retains free placement")
	sim.refresh_heroes()
	check(sim.heroes[0]["pos"] == point, "support refresh retains placement")
	sim.done = true
	check(not sim.move_hero_to(0, Vector2(730, 430)), "finished battle rejects movement")
	await _test_screen_input()
	finish("자유 배치·좌표 저장·카메라 입력 회귀 검사")

func _test_screen_input() -> void:
	fresh()
	var main := load("res://game/main.gd").new() as Node2D
	add_child(main)
	main.go_shop()
	main.screen.tab = "f"
	main.screen.set_process(false)
	await paint(main.screen)
	var form: FormationView = main.screen.formation
	for settings in [Vector2(-0.12, 1), Vector2(0.35, 1.2), Vector2(-0.35, 0.8)]:
		form.view_3d.world.yaw = settings.x
		form.view_3d.world.zoom = settings.y
		form.view_3d.world.camera_update()
		await paint(main.screen)
		var origin := Run.hero_position(Run.heroes[0])
		var next := Vector2(110, 320) if origin.x > 200 else Vector2(730, 430)
		var down := form.view_3d.project(origin, 0.3)
		var target := form.view_3d.project(next)
		check(form.view_3d.ground_at(target).distance_to(next) < 0.02, "camera inverse projection matches ground")
		check(form.view_3d.hero_at(down) == 0, "camera projection selects freely placed hero")
		mouse(main.screen, down, true)
		mouse(main.screen, down, false)
		mouse(main.screen, target, true)
		mouse(main.screen, target, false)
		check(Run.hero_position(Run.heroes[0]).distance_to(next) < 0.1, "click-click moves after camera orbit and zoom")
	form.view_3d.camera_button("camera:reset")
	await paint(main.screen)
	var before := Run.hero_position(Run.heroes[0])
	mouse(main.screen, form.view_3d.project(before, 0.3), true)
	mouse(main.screen, form.view_3d.project(Vector2(156, 300)), false)
	check(Run.hero_position(Run.heroes[0]) == before and form.selected == 0, "invalid drop retains selection and location")
	mouse(main.screen, form.view_3d.project(before, 0.3), true)
	# Two-finger camera movement cancels an in-progress one-finger placement.
	for index in range(2):
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.pressed = true
		touch.position = form.view_3d.box.get_center() + Vector2(index * 80, 0)
		form.input(touch, main.screen.ui)
	mouse(main.screen, form.view_3d.project(Vector2(110, 580)), false)
	check(Run.hero_position(Run.heroes[0]) == before, "camera gesture cancels placement")
	main.queue_free()
	await frames(3)
