extends Harness

## 사거리 — 발판에서 몬스터 중심까지, 화면과 전투가 같은 값을 쓰는가.
##
##   godot --headless --path . res://tests/range_check.tscn


func setup_unit(unit: Dictionary) -> BattleSim:
	Run.start_run(12092026)
	Run.begin_draw()
	Run.gain_hero(unit, int(unit["tier"]))
	Run.phase = Run.Phase.BATTLE
	var sim := BattleSim.new()
	sim.setup(Run, 1, 99)
	sim.monsters.clear()
	sim._spawn(Roster.MONSTERS[0])
	sim.monsters[0]["hp"] = 100000.0
	sim.monsters[0]["max"] = 100000.0
	sim._cache_positions()
	sim.events.clear()
	return sim

func _ready() -> void:
	Save._readonly = true
	var ranges := {}
	for unit in Roster.UNITS:
		var sim := setup_unit(unit)
		var hero: Dictionary = sim.heroes[0]
		var radius := float(hero["range"])
		ranges[radius] = true
		check(radius >= 160 and radius <= 400, "%s has a bounded range" % unit["id"])
		check(is_equal_approx(radius, float(Run.hero_stats(Run.heroes[0])["range"])), "simulation and UI share range")
		var at := BattleSim.mpos(sim.monsters[0])
		var origin := at - Vector2(radius, 0)
		hero["pos"] = origin
		check(sim._nearest_target(origin, radius) == 0, "target exactly at range is eligible")
		check(sim._nearest_target(origin - Vector2(0.1, 0), radius) == -1, "target beyond range is excluded")
		check(sim._nearest_targets(origin - Vector2(0.1, 0), 4, radius).is_empty(), "beam multi-target list excludes out-of-range enemies")
		hero["pos"] = origin - Vector2(1, 0)
		hero["cool"] = 0.0
		sim._heroes_fire(0)
		check(sim._pending.is_empty() and sim.events.is_empty(), "out-of-range enemies do not start an attack")
		for kind in Balance.BULLET:
			sim._shoot(0, 0, 1, kind, false)
		check(sim.bullets.is_empty() and sim.zones.is_empty() and float(hero["dmg"]) == 0.0, "all attack types reject an out-of-range cast")
		hero["pos"] = origin + Vector2(2, 0)
		sim._heroes_fire(0)
		check(sim.events.any(func(e): return e["t"] == "aim"), "entering range starts attack immediately")
		sim.events.clear()
		hero["pos"] = origin - Vector2(1, 0)
		sim._release(10)
		check(sim._pending.is_empty() and sim.bullets.is_empty() and sim.zones.is_empty(), "range is rechecked at attack release")
		check(float(hero["cool"]) == 0, "cancelled release restores readiness")
		hero["pos"] = origin + Vector2(2, 0)
		sim._heroes_fire(0)
		sim._release(10)
		check(sim.events.any(func(e): return e["t"] == "fire"), "hero resumes attacks when target reenters range")
	check(ranges.size() >= 15, "characters have a meaningful spread of ranges")
	check(Balance.attack_range({"weapon": "sword", "profile": "balance", "tier": 0}) < Balance.attack_range({"weapon": "bow", "profile": "balance", "tier": 0}), "bows outrange swords")
	check(Balance.attack_range({"weapon": "gun", "profile": "sniper", "tier": 9}) > Balance.attack_range({"weapon": "gun", "profile": "rapid", "tier": 0}), "rarity and attack style affect range")

	var bow := {}
	for unit in Roster.UNITS:
		if unit["weapon"] == "bow":
			bow = unit
			break
	var sim := setup_unit(bow)
	sim.monsters[0]["s"] = 500.0
	sim._cache_positions()
	var hero: Dictionary = sim.heroes[0]
	check(sim._target_in_range(0, hero["pos"], hero["range"]), "nearby lane is covered before moving")
	sim._aim(0, 0, 5.0, "zone", false, 1.0)
	check(sim.move_hero(0, 11), "hero can move while preparing an attack")
	check(not sim._target_in_range(0, hero["pos"], hero["range"]), "moving post changes the range origin")
	sim.events.clear()
	sim._release(10)
	check(sim.zones.is_empty() and not sim.events.any(func(e): return e["t"] == "fire"), "moving away cancels the pending spell")
	check(sim.move_hero(0, 4), "hero returns to covered lane")
	hero["cool"] = 0
	sim._heroes_fire(0)
	sim._release(10)
	check(sim.events.any(func(e): return e["t"] == "fire"), "returned hero attacks again")

	for wave in [1, 10, 11, 50, 100]:
		for rank in [1, 5]:
			var last_apk := Balance.HP_BASE * pow(Balance.HP_GROW, wave - 1) * Balance.mid_ramp(wave) * Balance.early_tough(wave) * Balance.theme_hp(rank) * 1.20
			check(is_equal_approx(Balance.wave_hp(wave, rank), last_apk * 1.5), "all waves are 50 percent tougher than the previous APK")
	finish("사거리 회귀 검사")
