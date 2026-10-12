extends Harness

## Real GL capture of the five bosses at StellarModels.BOSS_SCALE in the actual arena
## (real ArenaScreen, simulator positions, events and timers): each boss spawns at a
## gate, walks its lane to the altar, besieges the crystal for a full siege phase (the
## strike lands at the wrap) while three heroes shoot it, then dies (hp set to 0 so the
## simulator emits its own die event). Nothing here changes balance or roster files.
##
##   godot --path . --resolution 1280x800 res://tests/3d/boss_scale_preview.tscn -- --out DIR
##   options: --ids a,b   --walk-every N (default 6 ticks)   --scale (print only)

const BOSSES := ["abyss_leviathan", "flame_dragon", "titan_bloom", "crystal_golem_king", "glacier_dragon"]
const TICK := 1.0 / 30.0

var out_dir := "build/walk-grounding/boss/1280x800"
var screen: ArenaScreen
var main: Node2D
var _report: Dictionary = {"bosses": {}, "window": [0, 0], "scale": StellarModels.BOSS_SCALE}

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	I18n.set_locale("ko")
	_report["window"] = [get_window().size.x, get_window().size.y]
	var ids: Array = BOSSES
	if arg("--ids", "") != "": ids = arg("--ids", "").split(",")
	var walk_every := int(arg("--walk-every", "6"))
	for id in ids:
		await _boss(String(id), walk_every)
	var file := FileAccess.open(out_dir + "/boss-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "  ") + "\n")
	file = null
	finish("Boss scale arena capture")

func _open(seed_value: int) -> void:
	Arena.start_run(seed_value)
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

func _close() -> void:
	main.queue_free()
	main = null
	screen = null
	await frames(4)

func _camera_at(p: Vector2) -> void:
	screen.view_3d._follow_offset = StellarWorld.world(p)
	screen.view_3d._camera_initialized = true
	screen.view_3d._apply_camera(screen.view_3d._follow_offset)

func _tick() -> void:
	screen._process(TICK)
	screen.queue_redraw()
	await frames(1)
	screen._draw_dt = 0.0

func _capture(name: String) -> void:
	screen.queue_redraw()
	await frames(2)
	await snap(out_dir + "/" + name + ".png")

## Hero spots around the altar that are not on any road (so monsters are never blocked).
func _off_road_spots(count: int) -> Array:
	var spots: Array = []
	var margin := Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS + 6.0
	for n in range(72):
		var angle := TAU * float(n) / 72.0
		for radius: float in [150.0, 185.0, 220.0]:
			var p: Vector2 = Balance.ARENA_CENTER + Vector2.from_angle(angle) * radius
			if ArenaGeometry.on_road(p, margin): continue
			var clear := true
			for other in spots:
				if Vector2(other).distance_to(p) < 60.0: clear = false
			if clear:
				spots.append(p)
				break
		if spots.size() >= count: break
	while spots.size() < count: spots.append(Balance.ARENA_CENTER + Vector2(0, -1) * 200.0)
	return spots

func _row(id: String) -> Dictionary:
	for m in Roster.MONSTERS:
		if String(m["id"]) == id: return m
	return {}

func _find(sid: int) -> Dictionary:
	for mo in Arena.sim.monsters:
		if int(mo.get("spawn_id", 0)) == sid: return mo
	return {}

func _boss(id: String, walk_every: int) -> void:
	var row := _row(id)
	check(not row.is_empty() and String(row.get("kind", "")) == "boss", id + " is a boss in the roster")
	if row.is_empty(): return
	await _open(20261012 + id.hash() % 1000)
	Arena.heroes.clear()
	Arena.bench.clear()
	# Three shooters near the altar, off the roads so they never block the boss's lane,
	# so the siege shows real hits on the big body.
	var shooters := ["echo", "kari", "brasa"]
	var spots := _off_road_spots(shooters.size())
	for i in range(shooters.size()):
		Arena.gain_hero(Roster.unit_by_id(String(shooters[i])), 6)
		Arena.heroes[i]["position"] = spots[i]
	Arena.sim.refresh_heroes()
	Arena.selected = -1
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	Arena.sim.boss_spawned = true
	Arena.sim.boss_warned = true
	Arena.sim._forced_lane = 0
	Arena.sim._spawn(row)
	var mo: Dictionary = Arena.sim.monsters[-1]
	var sid := int(mo["spawn_id"])
	mo["hp"] = 1.0e9
	mo["max"] = mo["hp"]
	Arena.sim._rebuild_navigation()
	Arena.sim._cache_positions()
	await paint(screen)
	var world: StellarWorld = screen.view_3d.world
	var node: Node3D = world.monster_node(sid)
	await _tick()
	node = world.monster_node(sid)
	check(node != null, id + " has a live world node")
	var record := {"sid": sid, "scale": node.scale.x if node != null else 0.0, "frames": {}, "screen": {}}
	if node != null:
		check(is_equal_approx(node.scale.x, StellarModels.BOSS_SCALE), "%s body scaled x%.2f" % [id, StellarModels.BOSS_SCALE])
	# Spawn: 0.45 s rise/drop at the gate, camera on the boss.
	var count := 0
	for n in range(14):
		mo = _find(sid)
		if mo.is_empty(): break
		_camera_at(mo["pos"])
		await _capture("%s_spawn_%02d" % [id, count])
		count += 1
		await _tick()
	record["frames"]["spawn"] = count
	# Walk: follow the lane for 24 captures, then the boss is set down on its lane just
	# outside the altar stop (the lanes spiral for a long way) and walks the last stretch.
	count = 0
	var stop := Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS
	var ticks := 0
	var placed := false
	while ticks < 900:
		mo = _find(sid)
		if mo.is_empty(): break
		var p: Vector2 = mo["pos"]
		if p.distance_to(Balance.ARENA_CENTER) <= stop + 2.0: break
		if ticks == 24 * walk_every and not placed:
			placed = true
			var toward := (Vector2(mo["pos"]) - Balance.ARENA_CENTER).normalized()
			var near := Balance.ARENA_CENTER + toward * (stop + 36.0)
			if not ArenaGeometry.on_road(near, Balance.ARENA_MONSTER_RADIUS):
				near = ArenaGeometry.route_points(int(mo.get("route", 0)))[-1]
				near = Balance.ARENA_CENTER + (near - Balance.ARENA_CENTER).normalized() * (stop + 36.0)
			mo["pos"] = near
			mo["vel"] = Vector2.ZERO
			mo["path"] = PackedVector2Array()
			mo["nav_v"] = -1
			Arena.sim._cache_positions()
		if ticks % walk_every == 0:
			_camera_at(p)
			await _capture("%s_walk_%02d" % [id, count])
			count += 1
		await _tick()
		ticks += 1
	record["frames"]["walk"] = count
	record["walk_ticks"] = ticks
	check(ticks < 900, id + " reached the altar")
	# Siege: camera on the crystal; 36 consecutive ticks cover the strike at the wrap.
	_camera_at(Balance.ARENA_CENTER)
	count = 0
	for n in range(36):
		mo = _find(sid)
		if mo.is_empty(): break
		await _capture("%s_siege_%02d" % [id, count])
		count += 1
		await _tick()
	record["frames"]["siege"] = count
	mo = _find(sid)
	if not mo.is_empty():
		var p: Vector2 = mo["pos"]
		var foot := screen.view_3d.project(p, 0.0)
		record["screen"]["siege_foot"] = [foot.x, foot.y]
		record["siege_distance"] = p.distance_to(Balance.ARENA_CENTER)
		record["siege_t"] = float(mo.get("siege_t", -1.0))
		check(float(mo.get("siege_t", -1.0)) >= 0.0, id + " besieges the crystal")
		# Die: the simulator emits its own die event; the body plays topple/sink + dissolve.
		# A boss death ends the run with the victory overlay (ArenaSim._reap), which would
		# hide the body, so this simulator entry is reclassified first (the 2x model and
		# its death kind were fixed at spawn; roster data is untouched).
		mo["kind"] = "tank"
		mo["hp"] = 0.0
	count = 0
	for n in range(50):
		await _tick()
		await _capture("%s_die_%02d" % [id, count])
		count += 1
		if world.monster_node(sid) == null: break
	record["frames"]["die"] = count
	check(world.monster_node(sid) == null, id + " body released after its death presentation")
	_report["bosses"][id] = record
	await _close()
