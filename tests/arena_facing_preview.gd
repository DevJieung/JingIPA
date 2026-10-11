extends Harness

## Real-GL capture of hero facing in the arena: kill an enemy to the north, walk
## east, stop, push into a neighbour, release. The hero must keep facing east
## from the moment it walks until the end — no turning back toward the old target.
##
##   python3 tests/arena_facing_review.py        (Xvfb + both review sizes)
##
## The loop drives the simulation exactly like ArenaScreen/ArenaView (joystick →
## move_selected → step → event replay → sync_battle) and paints every fifth tick.

const DT := 1.0 / 60.0
var out_dir := "build/facing/1280x800"
var screen: ArenaScreen
var main: Node2D
var _shot := 0
var _yaws: Array = []

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	I18n.set_locale("ko")
	Arena.start_run(20261011)
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
	Arena.bench.clear()
	Arena.gain_hero(Roster.unit_by_id("echo"), 5)
	Arena.gain_hero(Roster.unit_by_id("kari"), 4)
	# The neighbour stands where 1.2 s of walking east ends: the walk is blocked there.
	var start := Balance.ARENA_CENTER + Vector2(-150, 140)
	Arena.heroes[0]["position"] = start
	Arena.heroes[1]["position"] = start + Vector2(1.2 * Balance.ARENA_HERO_SPEED + Balance.ARENA_HERO_RADIUS * 2.0 - 6.0, 0)
	Arena.sim.refresh_heroes()
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	Arena.selected = 0
	var sim: ArenaSim = Arena.sim
	var pool := Roster.theme_pool(Arena.theme_for(1))
	sim._spawn(pool[0])
	var mo: Dictionary = sim.monsters[-1]
	mo["pos"] = start + Vector2(0, -130)
	mo["hp"] = 1.0
	mo["max"] = 1.0
	sim._cache_positions()
	# The 3D world is created by the first draw.
	screen._draw_dt = 0.0
	await paint(screen)
	await _run(Vector2.ZERO, 1.6, "kill")        # turn north, shoot, kill
	check(sim.monsters.is_empty(), "the enemy north of the hero is killed")
	await _run(Vector2.RIGHT, 1.2, "walk")       # walk east
	await _run(Vector2.ZERO, 1.4, "stop")        # stand: must keep facing east
	await _run(Vector2.RIGHT, 1.0, "push")       # pushed into the neighbour: blocked, faces east
	await _run(Vector2.ZERO, 1.0, "release")
	var east := HeroLocomotion.yaw_of(Vector2.RIGHT)
	var worst := 0.0
	for entry in _yaws:
		if String(entry[0]) in ["stop", "push", "release"]:
			worst = maxf(worst, absf(wrapf(float(entry[1]) - east, -PI, PI)))
	check(worst < deg_to_rad(8), "after walking east the hero never turns away (max %.1f°)" % rad_to_deg(worst))
	var report := {"frames": _shot, "checks": checks, "failures": failures, "max_off_east_deg": rad_to_deg(worst),
		"window_resolution": DisplayServer.window_get_size()}
	var file := FileAccess.open(out_dir + "/facing-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	finish("정지·막힘 뒤 바라보는 방향 (실제 GL 촬영)")

func _run(joystick: Vector2, seconds: float, phase: String) -> void:
	var sim: ArenaSim = Arena.sim
	var world: ArenaWorld = screen.view_3d.world
	for n in range(int(round(seconds / DT))):
		sim.move_selected(joystick, DT)
		sim.step(DT)
		for hero in sim.heroes: hero["fx_t"] = float(hero.get("fx_t", 9.0)) + DT
		for e in sim.events:
			if String(e.get("t", "")) == "aim":
				var source := int(e.get("src", -1))
				if source >= 0 and source < sim.heroes.size():
					sim.heroes[source]["fx_t"] = 0.0
					sim.heroes[source]["fx_w"] = float(e.get("w", 0.0))
					sim.heroes[source]["fx_d"] = e.get("d", Vector2.DOWN)
			world.event(e)
		sim.events.clear()
		world.sync_battle(sim, sim.elapsed, 1, DT)
		var node: Node3D = world.hero_node(0)
		if node != null: _yaws.append([phase, node.rotation.y])
		if n % 5 == 0:
			screen._draw_dt = 0.0
			await paint(screen)
			await snap(out_dir + "/ko_facing_%03d.png" % _shot)
			_shot += 1
