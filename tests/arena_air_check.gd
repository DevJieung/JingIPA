extends Harness

## Flying monsters (2026-10-17): the roster marks three monsters `fly` (rapid_ray,
## jelly_seer, runestone_idol). Only heroes with a gun or a bow can hit them; swords,
## whips and deck fields never touch them. Flyers follow the roads like everyone else but
## pass over the guardians' bodies, so they cannot be body-blocked.
const DT := 1.0 / 60.0

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_table()
	_check_targeting()
	_check_bullets_and_fields()
	_check_movement()
	_check_skills_and_mods()
	Arena.running = false
	finish("공중 몬스터 · 대공 규칙")

func _flyer() -> Dictionary:
	return Roster.monster_by_id("rapid_ray")

func _walker() -> Dictionary:
	return Roster.monster_by_id("drop_slime")

func _arena(seed_value: int, units: Array) -> ArenaSim:
	Fixture.fresh(seed_value)
	Arena.start_run(seed_value)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(units.size()):
		Arena.gain_hero(units[i], 4)
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2(-200 + i * 200, 160)
	Arena.sim.refresh_heroes()
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	Arena.selected = 0
	return Arena.sim

## Pin a body at `at` (hp huge so nothing dies while geometry is measured).
func _pin(sim: ArenaSim, monster: Dictionary, at: Vector2) -> Dictionary:
	sim._spawn(monster)
	var mo: Dictionary = sim.monsters[-1]
	mo["pos"] = at
	mo["hp"] = 1.0e6
	mo["max"] = 1.0e6
	sim._cache_positions()
	return mo

func _fire_once(sim: ArenaSim, limit: int = 240) -> Array:
	var hits: Array = []
	var fires: Array = []
	var pins: Array = []
	for mo in sim.monsters: pins.append(Vector2(mo["pos"]))
	for n in range(limit):
		for i in range(sim.monsters.size()): sim.monsters[i]["pos"] = pins[i]
		sim._cache_positions()
		sim._heroes_fire(DT)
		sim._move_bullets(DT)
		for e in sim.events:
			if String(e.get("t", "")) == "hit": hits.append(e)
			if String(e.get("t", "")) == "fire": fires.append(e)
		sim.events.clear()
		if not hits.is_empty() and sim._pending.is_empty() and sim.bullets.is_empty():
			break
	return [fires, hits]

func _check_table() -> void:
	var flyers: Array = []
	for m in Roster.MONSTERS:
		if Balance.flies(m): flyers.append(String(m["id"]))
	check(flyers == ["rapid_ray", "jelly_seer", "runestone_idol"], "공중 몬스터는 격류가오리·해파리술사·석상술사 셋 (%s)" % ",".join(PackedStringArray(flyers)))
	for id in flyers:
		check(String(Roster.monster_by_id(id)["kind"]) != "boss" and String(Roster.monster_by_id(id)["kind"]) != "swarm", "공중 몬스터는 떼거리·보스가 아님: " + id)
	check(Balance.ANTI_AIR_WEAPONS == ["gun", "bow"], "대공 무기는 총·활")
	var air := 0
	for u in Roster.UNITS:
		if Balance.anti_air(u): air += 1
		check(Balance.anti_air(u) == (String(u["weapon"]) in ["gun", "bow"]), "대공 판정은 무기에서만: " + String(u["id"]))
	check(air == 20, "쉰 명 중 스무 명이 대공 (%d)" % air)
	for kind in Balance.MKIND:
		check(Balance.arena_kill_xp(String(kind)) > 0.0, "형마다 처치 경험치가 있음: " + String(kind))
	Arena.start_run(4242)
	var early_flyers := 0
	for w in range(1, Balance.ARENA_WAVES + 1):
		for entry in Arena.wave_spawns(1, w):
			if Balance.flies(entry["m"]): early_flyers += 1
	check(early_flyers == 0, "STAGE 1 에는 공중 몬스터가 나오지 않음 (Balance.ARENA_FLY_STAGE)")
	check(Talents.lint().is_empty(), "별자리 표가 맞게 적힘: " + ",".join(PackedStringArray(Talents.lint())))

func _check_targeting() -> void:
	# A sword (pip), a whip (lind), a deck (limne), a gun (chispa) and a bow (brigid).
	var sim := _arena(10171, [Roster.unit_by_id("pip"), Roster.unit_by_id("lind"), Roster.unit_by_id("limne"), Roster.unit_by_id("chispa"), Roster.unit_by_id("brigid")])
	for i in range(sim.heroes.size()):
		var weapon := String(sim.heroes[i]["h"]["unit"]["weapon"])
		check(bool(sim.heroes[i]["air"]) == (weapon in ["gun", "bow"]), "전투 영웅의 대공 표식: " + weapon)
	# Only a flyer in reach of everyone: the ground weapons stay idle, gun and bow fire.
	var fly_at := Balance.ARENA_CENTER + Vector2(0, 160) + Vector2(0, -40)
	var flyer := _pin(sim, _flyer(), fly_at)
	for i in range(sim.heroes.size()):
		Arena.heroes[i]["position"] = fly_at + Vector2(-80 + i * 40, 30)
	sim.refresh_heroes()
	sim.monsters[0]["pos"] = fly_at
	sim._cache_positions()
	for hi in range(sim.heroes.size()):
		var expected: bool = bool(sim.heroes[hi]["air"])
		check(sim._can_hit(hi, 0) == expected, "_can_hit: %s → %s" % [String(sim.heroes[hi]["h"]["unit"]["weapon"]), "맞힘" if expected else "못 맞힘"])
		var target := sim._nearest_target(Vector2(sim.heroes[hi]["pos"]), float(sim.heroes[hi]["range"]), expected)
		check((target == 0) == expected, "겨냥: 땅 무기는 공중 몬스터를 고르지 않음 (%s)" % String(sim.heroes[hi]["h"]["unit"]["weapon"]))
	var result := _fire_once(sim)
	var shooters := {}
	for e in result[0]: shooters[int(e["src"])] = true
	check(shooters.has(3) and shooters.has(4), "총·활은 공중 몬스터에게 쏨")
	check(not shooters.has(0) and not shooters.has(1) and not shooters.has(2), "검·채찍·덱은 공중 몬스터에게 공격을 시작하지 않음")
	var hit_air := false
	for e in result[1]:
		if bool(e.get("air", false)): hit_air = true
		check(int(e["src"]) in [3, 4], "공중 몬스터를 맞힌 것은 총·활뿐")
	check(hit_air and float(flyer["hp"]) < 1.0e6, "명중 이벤트가 air 표식을 실고 체력이 깎임")
	# A walker next to the flyer: the ground weapons pick the walker even when the flyer is nearer.
	var walker := _pin(sim, _walker(), fly_at + Vector2(0, 26))
	sim._cache_positions()
	for hi in range(3):
		var target := sim._nearest_target(Vector2(sim.heroes[hi]["pos"]), float(sim.heroes[hi]["range"]), false)
		# The sword's short reach may leave both out of range; it must never pick the flyer.
		check(target == 1 if hi > 0 else target != 0, "땅 무기는 더 가까운 공중 몬스터를 건너뛰고 뚜벅이를 고름 (%s)" % String(sim.heroes[hi]["h"]["unit"]["weapon"]))
	var any_target := sim._nearest_target(Vector2(sim.heroes[3]["pos"]), float(sim.heroes[3]["range"]), true)
	check(any_target == 0 or any_target == 1, "대공 무기는 둘 다 겨눌 수 있음")
	check(float(walker["hp"]) == 1.0e6, "뚜벅이는 아직 멀쩡함 (공격 전)")

func _check_bullets_and_fields() -> void:
	# A whip splash bullet aimed at a walker passes a flyer sitting on its path and its
	# burst does not cover the flyer; the same for a deck field laid under both.
	var sim := _arena(10172, [Roster.unit_by_id("marea"), Roster.unit_by_id("limne")])
	var hero_at: Vector2 = sim.heroes[0]["pos"]
	var walker := _pin(sim, _walker(), hero_at + Vector2(0, -150))
	var flyer := _pin(sim, _flyer(), hero_at + Vector2(0, -80))
	var result := _fire_once(sim, 300)
	var struck := {}
	for e in result[1]: struck[int(e["sid"])] = true
	check(struck.has(int(walker["spawn_id"])), "채찍 탄은 뚜벅이를 맞힘")
	check(not struck.has(int(flyer["spawn_id"])) and float(flyer["hp"]) == 1.0e6, "탄의 길목에 떠 있는 공중 몬스터는 스쳐 지나가고 폭발도 덮지 않음")
	for b in sim.bullets: check(not bool(b.get("air", true)), "채찍 탄은 대공 표식이 없음")
	# Deck field: lay a zone under both and tick it.
	sim.zones.clear()
	sim.monsters.clear()
	var w2 := _pin(sim, _walker(), hero_at + Vector2(0, -120))
	var f2 := _pin(sim, _flyer(), hero_at + Vector2(10, -120))
	sim.zones.append({"at": Vector2(w2["pos"]), "r": 128.0, "src": 1, "el": "water", "c": Color.WHITE,
		"dmg": 10.0, "crit": false, "t": 0.0, "n": 0, "max": 3, "delay": 0.0, "tick": 0.25})
	for n in range(60): sim._step_zones(DT)
	check(float(w2["hp"]) < 1.0e6 and float(f2["hp"]) == 1.0e6, "장판은 땅 위의 것만 때리고 공중 몬스터는 그 위를 지남")
	# A gun's bullets do carry the anti-air mark and a gun splash covers a flyer.
	var sim2 := _arena(10173, [Roster.unit_by_id("kari")])
	var at2: Vector2 = sim2.heroes[0]["pos"]
	var f3 := _pin(sim2, _flyer(), at2 + Vector2(0, -120))
	var w3 := _pin(sim2, _walker(), at2 + Vector2(0, -150))
	var r2 := _fire_once(sim2, 300)
	var struck2 := {}
	for e in r2[1]: struck2[int(e["sid"])] = true
	check(struck2.has(int(f3["spawn_id"])) and float(f3["hp"]) < 1.0e6, "총 산탄은 공중 몬스터를 맞힘")
	check(float(w3["hp"]) < 1.0e6, "그 폭발은 옆의 뚜벅이도 덮음")
	# Common skills ignore altitude. They wait for a wave and cost gold: open wave 1, spawns held.
	sim2.begin_wave(1)
	sim2._spawn_t = 1.0e9
	Arena.gold = 1000
	var hp_before: float = f3["hp"]
	sim2.cast_skill("blast")
	check(float(f3["hp"]) < hp_before, "별빛 폭발은 공중 몬스터도 때림")

func _check_movement() -> void:
	# A flyer follows the road but is not stopped by a guardian standing across it;
	# a walker in the same spot is blocked.
	Fixture.fresh(10174)
	Arena.start_run(10174)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	var sim: ArenaSim = Arena.sim
	sim.monsters.clear()
	sim._spawn_t = 1.0e9
	# Bodies, not pace, are compared here: the long-road pace (ARENA_ROAD_PACE) would bring both to the
	# crystal inside the window, so this battlefield walks at the normal pace.
	sim._pace = 1.0
	var path := ArenaGeometry.route_points(0)
	# Stand the (single) hero on the road centreline about 320 units in from the gate, so the
	# spawn (gate, lateral jitter) never overlaps it and both bodies have to come to it.
	var block_at: Vector2 = path[-1]
	var walked := 0.0
	for i in range(1, path.size()):
		var seg: float = path[i - 1].distance_to(path[i])
		if walked + seg >= 320.0:
			block_at = path[i - 1].lerp(path[i], (320.0 - walked) / maxf(0.001, seg))
			break
		walked += seg
	Arena.heroes[0]["position"] = block_at
	sim.refresh_heroes()
	sim._forced_lane = 0
	sim._spawn(_walker())
	var walker: Dictionary = sim.monsters[-1]
	sim._spawn(_flyer())
	var flyer: Dictionary = sim.monsters[-1]
	sim._forced_lane = -1
	flyer["spd"] = 1.0  # same pace as the walker so the comparison is fair
	check(bool(flyer.get("fly", false)) and not bool(walker.get("fly", false)), "출현한 몬스터가 fly 표식을 실음")
	var start_walker: Vector2 = walker["pos"]
	var start_flyer: Vector2 = flyer["pos"]
	var blocked_ticks := 0
	var left_road := false
	var passed := false
	var distance_before := Vector2(flyer["pos"]).distance_to(Balance.ARENA_CENTER)
	for n in range(900):
		# Walkers never pass a guardian's body before the deadlock break (ARENA_BLOCK_BREAK, checked in
		# tests/arena_wave_check): hold its blocked time at zero so this compares bodies only.
		walker["block_t"] = 0.0
		sim._rebuild_navigation()
		sim._move_monsters(DT)
		sim._cache_positions()
		if bool(walker["blocked"]): blocked_ticks += 1
		if not ArenaGeometry.on_road(flyer["pos"], Balance.ARENA_MONSTER_RADIUS): left_road = true
		# Passed the guardian: closer to the crystal than the guardian, measured along the radial.
		if Vector2(flyer["pos"]).distance_to(Balance.ARENA_CENTER) < block_at.distance_to(Balance.ARENA_CENTER) - Balance.ARENA_HERO_RADIUS - Balance.ARENA_MONSTER_RADIUS:
			passed = true
	check(not left_road, "공중 몬스터도 도로를 따라감")
	check(passed and Vector2(flyer["pos"]).distance_to(Balance.ARENA_CENTER) < distance_before - 100.0, "공중 몬스터는 길을 막은 수호자를 넘어 안쪽으로 나아감")
	check(blocked_ticks > 0 or Vector2(walker["pos"]).distance_to(Balance.ARENA_CENTER) > Vector2(flyer["pos"]).distance_to(Balance.ARENA_CENTER), "같은 길의 뚜벅이는 수호자에게 막혀 뒤에 남음")
	# Walkers still never pass through a guardian's body.
	var min_gap := INF
	for n in range(300):
		walker["block_t"] = 0.0
		sim._rebuild_navigation()
		sim._move_monsters(DT)
		sim._cache_positions()
		min_gap = minf(min_gap, Vector2(walker["pos"]).distance_to(block_at))
	check(min_gap >= Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS - 0.5, "뚜벅이는 수호자의 몸을 뚫지 않음 (최소 간격 %.1f)" % min_gap)
	# Saved and restored, the flag survives.
	var saved := Arena.snapshot()
	check(ArenaValidation.valid(saved) and Arena.restore(saved), "공중 몬스터가 든 저장 복구")
	var kept := false
	for mo in Arena.sim.monsters:
		if bool(mo.get("fly", false)): kept = true
	check(kept, "복구된 몬스터도 fly 표식을 지님")

func _check_skills_and_mods() -> void:
	# "대공 사격" multiplies gun/bow damage against flyers only; "격추" slows them on hit.
	var sim := _arena(10175, [Roster.unit_by_id("chispa")])
	var at: Vector2 = sim.heroes[0]["pos"]
	var flyer := _pin(sim, _flyer(), at + Vector2(0, -120))
	var walker := _pin(sim, _walker(), at + Vector2(60, -120))
	var r := _fire_once(sim, 300)
	var plain_air := 0.0
	var plain_ground := 0.0
	for e in r[1]:
		if int(e["sid"]) == int(flyer["spawn_id"]): plain_air = maxf(plain_air, float(e["n"]))
		if int(e["sid"]) == int(walker["spawn_id"]): plain_ground = maxf(plain_ground, float(e["n"]))
	Arena.talents["arms_gun"] = 1
	Arena.talents["arms_air"] = 1
	Arena.talents["arms_down"] = 1
	Arena._refresh_mods()
	sim.refresh_heroes()
	check(is_equal_approx(float(sim.heroes[0]["atk"]), float(Arena.hero_stats(Arena.heroes[0])["atk"])) and Arena.mod("weapon_gun") == 1.15, "「사격술」이 총 영웅의 공격력에 곱해짐")
	flyer["hp"] = 1.0e6
	flyer["slow_t"] = 0.0
	sim.heroes[0]["cool"] = 0.0
	var before := float(flyer["hp"])
	var hits := 0
	for n in range(400):
		sim.monsters[0]["pos"] = at + Vector2(0, -120)
		sim.monsters[1]["pos"] = at + Vector2(400, -120)
		sim._cache_positions()
		sim._heroes_fire(DT)
		sim._move_bullets(DT)
		for e in sim.events:
			if String(e.get("t", "")) == "hit" and int(e["sid"]) == int(flyer["spawn_id"]): hits += 1
		sim.events.clear()
		if hits > 0 and sim.bullets.is_empty() and sim._pending.is_empty(): break
	var dealt := before - float(flyer["hp"])
	check(hits > 0 and dealt > 0.0, "노드를 단 뒤에도 공중 몬스터를 맞힘")
	check(float(flyer["slow_t"]) > 0.0 and is_equal_approx(float(flyer["slow"]), 0.3), "「격추」가 공중 몬스터를 1.5초 둔화 x0.70")
	# Damage per hit is at least 1.15 (gun) x 1.35 (air) of the plain hit (crit aside: compare to the floor).
	check(dealt >= plain_air * 1.15 * 1.35 * 0.999, "「대공 사격」이 공중 몬스터 피해에 곱해짐 (%.1f ≥ %.1f)" % [dealt, plain_air * 1.15 * 1.35])
	var effects := Talents.effects(Arena.talents)
	check(is_equal_approx(float(effects["air"]), 1.35) and is_equal_approx(float(effects["air_slow"]), 0.3) and is_equal_approx(float(effects["weapon_gun"]), 1.15), "효과 모음: 곱은 곱, 더함은 더함")
	Arena.talents["arms_air"] = 2
	check(is_equal_approx(float(Talents.effects(Arena.talents)["air"]), 1.35 * 1.35), "되풀이 노드는 횟수만큼 겹침")
