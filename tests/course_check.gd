extends Harness

## Run the actual movement/arrival loop through both entrances in every theme.
## No heroes: enemies must traverse the whole inner detour before losing crystals.

func _ready() -> void:
	if not require_no_save():
		return
	var regular: Dictionary = Roster.MONSTERS.filter(func(m): return m["kind"] == "swarm")[0]
	var boss: Dictionary = Roster.MONSTERS.filter(func(m): return m["kind"] == "boss")[0]
	for theme in range(Roster.THEMES.size()):
		Fixture.fresh(20260920 + theme)
		Run.themes.fill(theme)
		Run.wave = 10
		var sim := BattleSim.new()
		sim.setup(Run, Run.wave, 20260920)
		sim._queue.clear()
		sim._spawn(regular)
		sim._spawn(boss)
		var previous: Array[Vector2] = []
		var continuous := [true, true]
		var within_road := [true, true]
		var seen_turns := [{}, {}]
		for mo in sim.monsters:
			mo["spd"] = 1.0
			previous.append(BattleSim.mpos(mo))
		var dt := 1.0 / 60.0
		var travel := Balance.path_len() / Balance.PATH_SPEED
		while sim.elapsed + dt < travel:
			sim.step(dt)
			if sim.monsters.size() != 2:
				break
			for index in range(2):
				var mo: Dictionary = sim.monsters[index]
				var p := BattleSim.mpos(mo)
				continuous[index] = continuous[index] and p.distance_to(previous[index]) < 2.0
				var pts := Balance.route_points(int(mo["route"]))
				var distance := INF
				for segment in range(pts.size() - 1):
					distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[segment], pts[segment + 1])))
					if p.distance_to(pts[segment]) < 2.0:
						seen_turns[index][segment] = true
				within_road[index] = within_road[index] and distance <= Balance.LANE_JITTER + 0.001
				previous[index] = p
		var label := String(Roster.THEMES[theme]["id"])
		check(sim.monsters.size() == 2 and sim.leaked == 0 and Run.lives == Balance.MAX_LIVES,
			label + ": neither route arrives before completing the extra turn")
		for route in range(2):
			check(continuous[route], label + ": movement stays continuous around every corner")
			check(within_road[route], label + ": movement stays on the rendered road")
			check(seen_turns[route].size() == Balance.route_points(route).size() - 1,
				label + ": movement visits every turn including the inner detour")
		# One final frame reaches the altar and removes both monsters exactly once.
		sim.step(dt * 2.0)
		check(sim.done and sim.monsters.is_empty() and sim.leak_n == 2,
			label + ": both routes finish at the altar")
		check(sim.leaked == 4 and Run.lives == Balance.MAX_LIVES - 4,
			label + ": ordinary enemy costs one crystal, boss costs three")
	finish("50개 테마 양쪽 진입·코어 우회 이동 검사")
