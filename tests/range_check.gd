extends Harness

## 사거리 — 발판에서 몬스터 중심까지, 화면과 전투가 같은 값을 쓰는가.
##
##   godot --headless --path . res://tests/range_check.tscn
##
## ★ **사거리는 캐릭터가 아니라 영웅 한 장의 등급으로 정해진다**(Balance.attack_range 의 ★).
##   캐릭터 표의 tier 는 원화의 격일 뿐이다 — 그래서 여기서는 캐릭터마다 표의 격과 **다른**
##   등급으로 세워 본다. 격과 같은 등급으로만 세우면, 전투가 영웅의 등급 대신 표의 격을
##   읽게 돼도 이 검사가 그대로 통과해 버린다.


## 그 캐릭터를 세울 등급 — 표의 원화 격에서 세 칸 밀린 등급(열 칸을 돈다).
func hero_tier(unit: Dictionary) -> int:
	return (int(unit["tier"]) + 3) % (Balance.TIER_MAX + 1)


func setup_unit(unit: Dictionary) -> BattleSim:
	Run.start_run(12092026)
	Run.begin_draw()
	Run.gain_hero(unit, hero_tier(unit))
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
		check(int(Run.heroes[0]["tier"]) == hero_tier(unit) and is_equal_approx(radius, Balance.attack_range(unit, hero_tier(unit))),
				"%s fights with the range of the hero's own tier, not the character's art grade" % unit["id"])
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
	check(Balance.attack_range({"weapon": "sword", "profile": "balance"}, 0) < Balance.attack_range({"weapon": "bow", "profile": "balance"}, 0), "bows outrange swords")
	check(Balance.attack_range({"weapon": "gun", "profile": "sniper"}, Balance.TIER_MAX) > Balance.attack_range({"weapon": "gun", "profile": "rapid"}, 0), "rarity and attack style affect range")
	# 등급(반 별 한 칸)이 오르면 같은 캐릭터의 사거리도 조금씩 는다 — 줄어드는 일은 없고,
	# 0.5성과 5성 사이에는 반드시 차이가 난다. 표의 원화 격은 한 톨도 영향이 없다.
	for unit in Roster.UNITS:
		var twin: Dictionary = unit.duplicate(true)
		twin["tier"] = Balance.TIER_MAX - int(unit["tier"])
		var last := 0.0
		for tier in range(Balance.TIER_MAX + 1):
			var reach := Balance.attack_range(unit, tier)
			check(reach >= last, "%s never loses range with a higher tier (%d)" % [unit["id"], tier])
			check(is_equal_approx(reach, Balance.attack_range(twin, tier)), "%s: the art grade has no effect on range (%d)" % [unit["id"], tier])
			last = reach
		check(Balance.attack_range(unit, Balance.TIER_MAX) > Balance.attack_range(unit, 0), "%s reaches farther at five stars" % unit["id"])
		# 등급 없이 물으면(도감처럼 캐릭터만 보여 주는 자리) 1성으로 친다.
		check(is_equal_approx(Balance.attack_range(unit), Balance.attack_range(unit, Rite.tier_of(Rite.MIN_STARS))),
				"%s: asking without a tier answers for one star" % unit["id"])

	var bow := {}
	for unit in Roster.UNITS:
		if unit["weapon"] == "bow":
			bow = unit
			break
	var sim := setup_unit(bow)
	var hero: Dictionary = sim.heroes[0]
	var home := int(Run.heroes[0]["post"])
	var away := 11
	# ★ 몬스터를 **길 위에서** 고른 자리에 세운다: 영웅의 발판에서는 넉넉히 닿고, 옮겨 갈
	#   발판에서는 넉넉히 안 닿는 곳. 길이나 발판을 다시 깔아도 이 검사가 따라간다
	#   (예전에는 길 위 500 지점을 못 박아 뒀는데, 길이 바뀐 뒤로 그 자리가 사거리 밖이었다).
	var spot := -1.0
	var step := 0.0
	while step <= Balance.path_len():
		sim.monsters[0]["s"] = step
		sim._cache_positions()
		var at := BattleSim.mpos(sim.monsters[0])
		if at.distance_to(Balance.post_position(home)) <= float(hero["range"]) - 24.0 \
				and at.distance_to(Balance.post_position(away)) >= float(hero["range"]) + 24.0:
			spot = step
			break
		step += 20.0
	check(home != away and spot >= 0.0, "the path offers a spot near the hero's post and far from the other post")
	check(sim._target_in_range(0, hero["pos"], hero["range"]), "nearby lane is covered before moving")
	sim._aim(0, 0, 5.0, "zone", false, 1.0)
	check(sim.move_hero(0, away), "hero can move while preparing an attack")
	check(not sim._target_in_range(0, hero["pos"], hero["range"]), "moving post changes the range origin")
	sim.events.clear()
	sim._release(10)
	check(sim.zones.is_empty() and not sim.events.any(func(e): return e["t"] == "fire"), "moving away cancels the pending spell")
	check(sim.move_hero(0, home), "hero returns to covered lane")
	hero["cool"] = 0
	sim._heroes_fire(0)
	sim._release(10)
	check(sim.events.any(func(e): return e["t"] == "fire"), "returned hero attacks again")

	for wave in [1, 10, 11, 50, 100]:
		for rank in [1, 5]:
			var last_apk := Balance.HP_BASE * pow(Balance.HP_GROW, wave - 1) * Balance.mid_ramp(wave) * Balance.early_tough(wave) * Balance.theme_hp(rank) * 1.20
			check(is_equal_approx(Balance.wave_hp(wave, rank), last_apk * 1.5), "all waves are 50 percent tougher than the previous APK")
	finish("사거리 회귀 검사")
