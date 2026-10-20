extends Harness

## Headless cost of one simulator tick by phase, against the number of monsters on the
## field. No judgement: a table for optimisation work (docs/PERF_NATIVE.md).
##
##   godot --headless --path . res://tests/perf/arena_sim_bench.tscn -- --stage 10 --wave 9 --seconds 60 [--walk]
##
## The run is seeded, six guardians stand on the roads near the crystal (so monsters
## path around them), and the stage's waves arrive at their pace from --wave on (the
## preparation phases between them pass on their own).
class BenchSim extends ArenaSim:
	var us := {}
	func _lap(key: String, t0: int) -> void:
		us[key] = int(us.get(key, 0)) + (Time.get_ticks_usec() - t0)
	func _rebuild_navigation() -> void:
		var t0 := Time.get_ticks_usec()
		super._rebuild_navigation()
		_lap("nav", t0)
	func _move_monsters(dt: float) -> void:
		var t0 := Time.get_ticks_usec()
		super._move_monsters(dt)
		_lap("move", t0)
	func _cache_positions() -> void:
		var t0 := Time.get_ticks_usec()
		super._cache_positions()
		_lap("cache", t0)
	func _heroes_fire(dt: float) -> void:
		var t0 := Time.get_ticks_usec()
		super._heroes_fire(dt)
		_lap("fire", t0)
	func _move_bullets(dt: float) -> void:
		var t0 := Time.get_ticks_usec()
		super._move_bullets(dt)
		_lap("bullets", t0)
	func _step_zones(dt: float) -> void:
		var t0 := Time.get_ticks_usec()
		super._step_zones(dt)
		_lap("zones", t0)
	func _reap() -> void:
		var t0 := Time.get_ticks_usec()
		super._reap()
		_lap("reap", t0)

const KEYS := ["nav", "move", "cache", "fire", "bullets", "zones", "reap"]

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	var stage := arg_int("--stage", 10)
	var first_wave := arg_int("--wave", Balance.ARENA_WAVES - 1)
	var seconds := arg_float("--seconds", 60.0)
	var seed_value := arg_int("--seed", 20261017)
	Arena.start_run(seed_value, stage)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	for unit in Roster.UNITS:
		if Arena.heroes.size() >= Balance.ARENA_HERO_LIMIT: break
		if String(unit["id"]) != String(Arena.heroes[0]["unit"]["id"]): Arena.gain_hero(unit, 1)
	var sim := BenchSim.new()
	sim.setup(Arena, stage, seed_value)
	Arena.sim = sim
	sim.begin_wave(first_wave)
	# Guardians on the roads a little out from the plaza: every lane has a body to go round.
	var lanes := ArenaGeometry.route_count()
	for i in range(Arena.heroes.size()):
		var route := ArenaGeometry.route_points(i % lanes)
		var index := route.size() - 1 - 14 - 12 * (i / lanes)
		Arena.heroes[i]["position"] = route[clampi(index, 0, route.size() - 1)]
	sim.refresh_heroes()
	Arena.modal = ""
	Arena.phase = Arena.Phase.BATTLE
	var buckets := {}
	var total_us := 0
	var ticks := 0
	var worst := 0
	var ticks_total := roundi(seconds * 60.0)
	var walk := has_arg("--walk")
	Arena.selected = 0
	for n in range(ticks_total):
		if walk:
			# The selected guardian keeps walking in a slow circle: every tick moves the
			# navigation grid and sends the monsters near it looking for a new path.
			sim.move_selected(Vector2.from_angle(float(n) / 60.0 * 0.9), 1.0 / 60.0)
		if Arena.modal == "talent" and not Arena.talent_offer.is_empty():
			Arena.pick_talent(String(Arena.talent_offer[0]))
		if not Arena.modal.is_empty() or sim.done: break
		for key in sim.us: sim.us[key] = 0
		var t0 := Time.get_ticks_usec()
		sim.step(1.0 / 60.0)
		var cost := Time.get_ticks_usec() - t0
		var count := sim.monsters.size()
		var bucket := (count / 8) * 8
		if not buckets.has(bucket): buckets[bucket] = {"n": 0, "us": 0, "worst": 0, "bullets": 0}
		var row: Dictionary = buckets[bucket]
		row["n"] += 1
		row["us"] += cost
		row["bullets"] += sim.bullets.size()
		row["worst"] = maxi(int(row["worst"]), cost)
		for key in KEYS: row[key] = int(row.get(key, 0)) + int(sim.us.get(key, 0))
		total_us += cost
		worst = maxi(worst, cost)
		ticks += 1
	print("stage %d · %d ticks · %.2f ms/tick avg · worst %.2f ms · monsters now %d · crystal %.0f" % [stage, ticks, total_us / 1000.0 / maxf(1, ticks), worst / 1000.0, sim.monsters.size(), sim.crystal_hp])
	print("monsters  ticks   ms/tick  worst   bullets   nav   move  cache  fire  bullets zones  reap   (ms, per tick)")
	var keys := buckets.keys()
	keys.sort()
	for bucket in keys:
		var row: Dictionary = buckets[bucket]
		var n := maxf(1.0, float(row["n"]))
		var line := "%3d-%3d  %5d   %6.2f  %6.2f  %6.1f" % [bucket, bucket + 7, row["n"], row["us"] / 1000.0 / n, row["worst"] / 1000.0, row["bullets"] / n]
		for key in KEYS: line += "  %5.2f" % (int(row.get(key, 0)) / 1000.0 / n)
		print(line)
	Arena.running = false
	get_tree().quit(0)
