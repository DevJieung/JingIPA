extends Harness

## 물 「특효」의 밀어내기 — 프레임 크기와 무관하게 같은 거리로 끝나는가.
##
##   godot --headless --path . res://tests/push_check.tscn


func fresh(route: int = 0, distance: float = 500.0) -> BattleSim:
	Run.start_run(14092026)
	Run.begin_draw()
	var sim := BattleSim.new()
	sim.setup(Run, 1, 99)
	sim._queue.clear()
	sim._spawn(Roster.MONSTERS[0])
	sim.monsters[0]["s"] = distance
	sim.monsters[0]["route"] = route
	sim._cache_positions()
	sim.events.clear()
	return sim

func _ready() -> void:
	Save._readonly = true
	for route in [0, 1]:
		for fps in [30, 60, 120]:
			var sim := fresh(route)
			var mo: Dictionary = sim.monsters[0]
			var start := BattleSim.mpos(mo)
			sim._push(0)
			check(BattleSim.mpos(mo) == start and mo["s"] == 500.0,
					"hit queues movement without teleporting")
			check(sim.events.size() == 1 and sim.events[0]["p"] == start,
					"push effect starts at the current hit position")
			var speed := Balance.PATH_SPEED * float(mo["spd"])
			var dt: float = 1.0 / fps
			var first_step := 0.0
			for i in range(fps):
				var previous := float(mo["s"])
				sim._move_monsters(dt)
				sim._cache_positions()
				if i == 0:
					first_step = previous - float(mo["s"])
				check(absf(float(mo["s"]) - previous) < 8.5,
						"each movement step is short at %d fps" % fps)
				check(sim._mp[0] == BattleSim.mpos(mo),
						"rendered position and hit cache agree through the path")
			check(first_step > 0.0 and first_step < Balance.RIDER_PUSH / 4.0,
					"first frame visibly moves backward by only part of the push")
			check(absf(float(mo["s"]) - (500.0 + speed - Balance.RIDER_PUSH)) < 0.001,
					"total displacement is unchanged across frame rates and routes")
			check(mo["push_left"] == 0.0 and mo["push_t"] == 0.0,
					"push completes without residual movement")
			check(float(mo["motion_t"]) > 0.0, "walking animation never rewinds")

	var sim := fresh()
	var mo: Dictionary = sim.monsters[0]
	mo["stun_t"] = 5.0
	for i in range(20):
		sim._push(0)
	check(mo["s"] == 500.0, "simultaneous hits do not teleport")
	check(mo["push"] == Balance.RIDER_PUSH_MAX, "simultaneous hits retain lifetime cap")
	var previous_step := INF
	for i in range(120):
		var previous := float(mo["s"])
		sim._move_monsters(1.0 / 60.0)
		var movement := previous - float(mo["s"])
		check(movement <= 2.0 * Balance.RIDER_PUSH / Balance.RIDER_PUSH_SEC / 60.0 + 0.001,
				"stacked hits retain the single-hit speed limit")
		check(movement <= previous_step + 0.001, "push decelerates smoothly")
		previous_step = movement
	check(absf(float(mo["s"]) - (500.0 - Balance.RIDER_PUSH_MAX)) < 0.001,
			"stun permits external displacement with exact capped distance")
	check(mo["motion_t"] == 0.0, "stunned monster does not walk while being pushed")
	sim._push(0)
	check(mo["push_left"] == 0.0, "spent lifetime cap prevents further knockback")

	sim = fresh(1, 6.0)
	mo = sim.monsters[0]
	mo["stun_t"] = 5.0
	for i in range(10):
		sim._push(0)
	sim._move_monsters(1.0)
	check(is_zero_approx(float(mo["s"])), "entrance clamps displacement without leaving the path")
	check(mo["push"] == 6.0 and mo["push_left"] == 0.0, "entrance cannot accumulate hidden extra push")

	sim = fresh()
	mo = sim.monsters[0]
	mo["stun_t"] = 5.0
	sim._push(0)
	sim._move_monsters(0.12)
	var before := float(mo["s"])
	sim._push(0)
	check(mo["s"] == before, "hit during knockback preserves continuous position")
	sim._move_monsters(2.0)
	check(absf(float(mo["s"]) - (500.0 - 2.0 * Balance.RIDER_PUSH)) < 0.001,
			"overlapping hits preserve both displacements on a long frame")

	# Exercise the real water rider damage path, not just the movement helper.
	Run.gain_hero(Roster.UNITS.filter(func(unit): return unit["elem"] == "water" and unit["role"] == "rider")[0], 1)
	sim = BattleSim.new()
	sim.setup(Run, 1, 99)
	sim._queue.clear()
	sim._spawn(Roster.MONSTERS[0])
	mo = sim.monsters[0]
	mo["s"] = 500.0
	sim._cache_positions()
	sim._hurt(0, 0.01, false, 0, "water")
	check(mo["s"] == 500.0 and float(mo["push_left"]) > 0.0,
			"water rider damage schedules smooth knockback")
	finish("밀어내기 회귀 검사")
