extends Harness

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_summons()
	_check_movement()
	_check_navigation()
	_check_crystal_and_skills()
	_check_skill_limits()
	_check_pause_and_save()
	_check_boss()
	_check_duration()
	_check_shop()
	_check_stage_chain()
	_check_stage_strength()
	Arena.running = false
	finish("연속 수호전 규칙·저장")

func _battle(seed_value: int = 701) -> ArenaSim:
	Arena.start_run(seed_value)
	check(Arena.choose_theme(0), "테마 선택")
	Arena.confirm_summon()
	Arena.close_modal()
	return Arena.sim

func _advance(sim: ArenaSim, seconds: float) -> void:
	for i in range(roundi(seconds * 60)):
		sim.step(1.0 / 60.0)

func _monster(sim: ArenaSim, at: Vector2) -> Dictionary:
	sim._spawn(Arena.spawns_for(1)[0])
	var mo: Dictionary = sim.monsters[-1]
	mo["pos"] = at if ArenaGeometry.on_road(at, Balance.ARENA_MONSTER_RADIUS) else ArenaGeometry.nearest_road_point(at)
	mo["hp"] = 100000.0
	mo["max"] = mo["hp"]
	sim._cache_positions()
	return mo

func _check_summons() -> void:
	Arena.start_run(700)
	check(Arena.modal == "stage" and Arena.stage == 1 and Arena.theme_index >= 0 and Arena.sim != null, "새 판은 무작위 전장의 1탄 카드에서 시작")
	check(ArenaValidation.valid(Arena.snapshot()), "전장 카드 중 저장")
	var initial_gold: int = Arena.gold
	Arena.choose_theme(0)
	check(Arena.gold == initial_gold and Arena.heroes.is_empty(), "첫 의식 무료·확정 전 지급 없음")
	check(Arena.sim.elapsed == 0.0 and Arena.modal == "rite", "첫 의식 전투 정지")
	var result: Dictionary = Arena.confirm_summon()
	check(not result.is_empty() and Arena.heroes.size() == 1, "1명으로 시작")
	var confirmed := Arena.snapshot()
	var count: int = Arena.summon_count
	check(Arena.restore(confirmed), "소환 결과 복구")
	Arena.confirm_summon()
	check(Arena.summon_count == count and Arena.heroes.size() == 1, "확정 결과 재지급 방지")
	Arena.close_modal()
	var unit: Dictionary = Arena.heroes[0]["unit"]
	Arena.heroes[0]["tier"] = 1
	Arena.heroes[0]["growth_points"] = 0
	Arena.gain_hero(unit, 1)
	check(Arena.heroes.size() == 1 and Arena.heroes[0]["tier"] == 1 and Arena.heroes[0]["growth_points"] == 4, "중복은 성장 포인트·등급 즉시 교체 없음")
	Arena.gain_hero(unit, 3)
	check(Arena.heroes[0]["tier"] == 2 and Arena.heroes[0]["growth_points"] == 2, "포인트 임계 승급·잔여 보존")
	Arena.heroes[0]["tier"] = Balance.TIER_MAX - 1
	Arena.heroes[0]["growth_points"] = Arena.growth_needed(Arena.heroes[0]) - 2
	Arena.gain_hero(unit, 1)
	check(Arena.heroes[0]["tier"] == Balance.TIER_MAX and Arena.heroes[0]["growth_points"] == 0, "최종 강화 도달")
	check(not _contains_unit(Arena.eligible_units(), String(unit["id"])), "최종 강화 캐릭터 후보 제외")
	for candidate in Roster.UNITS:
		if String(candidate["id"]) != String(unit["id"]):
			Arena.gain_hero(candidate, 1)
	check(Arena.heroes.size() == 6 and Arena.bench.size() == Roster.UNITS.size() - 6, "전장 6명·나머지 대기")
	Arena.open_modal("bench")
	var outgoing: Dictionary = Arena.heroes[0]
	var at: Vector2 = outgoing["position"]
	check(Arena.swap_hero(0, 0) and Arena.heroes[0]["position"] == at, "전장·대기 교체 위치 보존")
	check(not _contains_unit(Arena.eligible_units(), String(unit["id"])), "최종 강화 대기 캐릭터도 후보 제외")
	var incoming: Dictionary = Arena.heroes[0]["unit"]
	var bench_count: int = Arena.bench.size()
	Arena.gain_hero(incoming, 1)
	check(Arena.bench.size() == bench_count and Arena.heroes.size() == 6, "전장 중복을 대기 새 개체로 만들지 않음")
	var reserve: Dictionary = Arena.bench[1]
	var reserve_points := int(reserve["growth_points"])
	Arena.gain_hero(reserve["unit"], 1)
	check(Arena.bench.size() == bench_count and reserve["growth_points"] == reserve_points + 4, "대기 중복도 같은 캐릭터에 포인트 누적")
	for hero in Arena.heroes + Arena.bench:
		hero["tier"] = Balance.TIER_MAX
		hero["growth_points"] = 0
	Arena.close_modal()
	Arena.gold = 1000
	check(not Arena.begin_summon() and Arena.gold == 1000, "후보 소진 시 소환·골드 차감 차단")

func _contains_unit(pool: Array, id: String) -> bool:
	for unit in pool:
		if unit["id"] == id: return true
	return false

func _check_movement() -> void:
	var sim := _battle()
	var id := String(Arena.heroes[0]["unit"]["id"])
	for unit in Roster.UNITS:
		if String(unit["id"]) != id:
			Arena.gain_hero(unit, 1)
			break
	var other: Vector2 = sim.heroes[1]["pos"]
	var start: Vector2 = sim.heroes[0]["pos"]
	check(sim.move_selected(Vector2.RIGHT, 0.1), "선택 캐릭터 실제 이동")
	check(sim.heroes[0]["pos"].distance_to(start) > 10 and sim.heroes[1]["pos"] == other, "선택 캐릭터만 이동·다른 영웅 유지")
	check(Arena.heroes[0]["position"] == sim.heroes[0]["pos"], "실제 위치와 저장 위치 일치")
	Arena.heroes[0]["position"] = Balance.ARENA_CENTER + Vector2(0, -100)
	sim.refresh_heroes()
	for i in range(20): sim.move_selected(Vector2.DOWN, 0.1)
	check(Vector2(sim.heroes[0]["pos"]).distance_to(Balance.ARENA_CENTER) >= Balance.ALTAR_R + Balance.ARENA_HERO_RADIUS, "크리스탈 관통 금지")
	for i in range(100): sim.move_selected(Vector2.LEFT, 0.1)
	check(ArenaGeometry.contains(sim.heroes[0]["pos"], Balance.ARENA_HERO_RADIUS), "원형 경계 이탈 금지")
	sim.monsters.clear()
	var p: Vector2 = sim.heroes[0]["pos"]
	_monster(sim, p + Vector2(40, 0))["pos"] = p + Vector2(40, 0)
	_monster(sim, p + Vector2(120, 0))["pos"] = p + Vector2(120, 0)
	sim._cache_positions()
	check(sim._nearest_target(p, 200) == 0 and sim._nearest_target(p, 20) == -1, "각 영웅 위치 기준 최근접·사거리")

func _park_heroes(sim: ArenaSim) -> void:
	var occupied: Array[Vector2] = []
	for hero in Arena.heroes:
		var found := false
		for y in range(-360, 361, 60):
			for x in range(-360, 361, 60):
				var p := Balance.ARENA_CENTER + Vector2(x, y)
				if not ArenaGeometry.contains(p, Balance.ARENA_HERO_RADIUS) or ArenaGeometry.on_road(p, -60): continue
				var clear := true
				for other in occupied:
					if p.distance_to(other) < Balance.ARENA_HERO_RADIUS * 2: clear = false
				if clear:
					hero["position"] = p
					occupied.append(p)
					found = true
					break
			if found: break
	sim.refresh_heroes()
	sim._rebuild_navigation()

func _check_navigation() -> void:
	var sim := _battle(703)
	var road := ArenaGeometry.route_points(0)
	var tangent := (road[19] - road[18]).normalized()
	Arena.heroes[0]["position"] = road[18] + Vector2(-tangent.y, tangent.x) * 55
	sim.refresh_heroes()
	sim._rebuild_navigation()
	var mo := _monster(sim, road[0])
	mo["spd"] = 1.0
	var passed_guardian := false
	var safe := true
	for i in range(2400):
		sim._move_monsters(1.0 / 60.0)
		var distance: float = Vector2(mo["pos"]).distance_to(sim.heroes[0]["pos"])
		passed_guardian = passed_guardian or distance < 90
		safe = safe and distance >= Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS - 0.01
	check(passed_guardian and safe, "길 가장자리 영웅을 충돌 없이 지나감")
	check(Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 2, "도로 우회 후 크리스탈 도착")
	sim = _battle(704)
	for unit in Roster.UNITS:
		if Arena.heroes.size() == 6: break
		if not _contains_unit([Arena.heroes[0]["unit"]], String(unit["id"])): Arena.gain_hero(unit, 1)
	_park_heroes(sim)
	var parked: Vector2 = Arena.heroes[0]["position"]
	Arena.heroes[0]["position"] = road[6]
	sim.refresh_heroes()
	sim._rebuild_navigation()
	mo = _monster(sim, road[6])
	var position: Vector2 = mo["pos"]
	var hp: float = sim.crystal_hp
	for i in range(120): sim._move_monsters(1.0 / 60.0)
	check(mo["pos"] == position and mo["blocked"] and mo["motion_t"] == 0.0 and sim.crystal_hp == hp, "경로 없으면 대기·밀어내기 없음")
	Arena.heroes[0]["position"] = parked
	sim.refresh_heroes()
	sim._rebuild_navigation()
	for i in range(60): sim._move_monsters(1.0 / 60.0)
	check(mo["pos"] != position, "길막 해제 후 이동 재개")
	var trap := road[12]
	for i in range(6):
		Arena.heroes[i]["position"] = trap + Vector2.from_angle(i * TAU / 6.0) * (Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS) * 1.5
	sim.refresh_heroes()
	sim._rebuild_navigation()
	sim.monsters.clear()
	mo = _monster(sim, trap)
	safe = true
	for i in range(120):
		sim._move_monsters(1.0 / 60.0)
		for hero in sim.heroes:
			safe = safe and Vector2(mo["pos"]).distance_to(hero["pos"]) >= Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS - 0.01
	var waiting: Vector2 = mo["pos"]
	for i in range(60): sim._move_monsters(1.0 / 60.0)
	check(safe and Vector2(mo["pos"]).distance_to(trap) < 24 and mo["pos"] == waiting and mo["blocked"], "6인 완전 봉쇄는 실제 접촉 지점까지 접근한 뒤 관통·밀어내기 없이 대기")
	_park_heroes(sim)
	for i in range(60): sim._move_monsters(1.0 / 60.0)
	check(mo["pos"] != trap, "봉쇄를 풀면 도로 이동 재개")

func _check_crystal_and_skills() -> void:
	var sim := _battle(705)
	var mo := _monster(sim, Balance.ARENA_CENTER + Vector2(74, 0))
	var hp: float = sim.crystal_hp
	for i in range(180): sim._move_monsters(1.0 / 60.0)
	check(sim.crystal_hp < hp and sim.monsters.size() == 1, "도착 몬스터가 사라지지 않고 지속 공격")
	check(sim.cast_skill("ward") and sim.shield > 0 and not sim.cast_skill("ward"), "방어 스킬·쿨타임")
	hp = sim.crystal_hp
	for i in range(60): sim._move_monsters(1.0 / 60.0)
	check(sim.crystal_hp == hp and sim.shield < Balance.ARENA_WARD_SHIELD, "방벽 피해 흡수")
	check(sim.cast_skill("freeze") and mo["slow_t"] > 0, "제어 스킬 자동 대상")
	hp = mo["hp"]
	check(sim.cast_skill("blast") and mo["hp"] < hp, "공격 스킬 자동 대상·피해")
	sim._push(0)
	check(mo["push_left"] > 0, "기존 물 특효 실제 좌표 밀림")
	# Guardian's blessing would revive the crystal (tests/store_check); spend it here.
	sim.revives = Balance.ARENA_REVIVE_USES
	sim._damage_crystal(100000.0, Balance.ARENA_CENTER)
	check(sim.done and not sim.won and Arena.modal == "result", "크리스탈 파괴 패배")

func _check_skill_limits() -> void:
	var sim := _battle(709)
	_monster(sim, Balance.ARENA_CENTER + Vector2(74, 0))
	for id in ["blast", "freeze", "ward"]:
		var limit: int = sim.skill_max_uses(id)
		check(limit > 0 and sim.skill_uses_left(id) == limit, id + " 한 판 사용 횟수 제한 존재")
		for n in range(limit):
			sim.skill_cooldowns[id] = 0.0
			check(sim.cast_skill(id) and sim.skill_uses_left(id) == limit - n - 1, "%s %d번째 사용·남은 횟수 감소" % [id, n + 1])
		sim.skill_cooldowns[id] = 0.0
		check(sim.skill_uses_left(id) == 0 and not sim.cast_skill(id), id + " 횟수 소진 뒤에는 쿨타임이 끝나도 사용 불가")
	var saved := Arena.snapshot()
	check(ArenaValidation.valid(saved) and Arena.restore(saved) and Arena.sim.skill_uses_left("blast") == 0 and Arena.sim.skill_uses_left("ward") == 0, "횟수 소진 상태 저장·복구")
	var bare := saved.duplicate(true)
	bare["sim"].erase("uses")
	check(not ArenaValidation.valid(bare), "횟수 정보가 빠진 저장 거부")
	saved["sim"]["uses"] = {"blast": -1, "freeze": 0, "ward": 0}
	check(not ArenaValidation.valid(saved), "음수 사용 횟수 저장 거부")
	Arena.start_run(710)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	check(Arena.sim.skill_uses_left("ward") == Balance.ARENA_WARD_USES, "새 판은 횟수가 다시 채워짐")

func _check_pause_and_save() -> void:
	var sim := _battle(706)
	Arena.gold = 1000
	_monster(sim, Balance.ARENA_CENTER + Vector2(210, 80))
	sim.cast_skill("ward")
	_advance(sim, 1.0)
	for modal in ["shop", "bench", "rite"]:
		if modal == "rite": check(Arena.begin_summon(), "골드 소환 진입")
		else: check(Arena.open_modal(modal), modal + " 진입")
		var before := sim.snapshot_arena()
		_advance(sim, 3.0)
		sim.move_selected(Vector2.RIGHT, 0.1)
		check(sim.elapsed == before["elapsed"] and sim.monsters == before["monsters"] and sim.skill_cooldowns == before["cooldowns"] and sim._spawn_t == before["spawn_t"], modal + " 시간·몹·이동·쿨타임 완전 정지")
		check(not sim.cast_skill("blast"), modal + " 전투 조작 차단")
		var state := Arena.snapshot()
		check(ArenaValidation.valid(state) and Arena.restore(state), modal + " 저장 복구")
		sim = Arena.sim
		if modal == "rite": Arena.confirm_summon()
		Arena.close_modal()
	Arena.open_modal("shop")
	check(Arena.buy_upgrade("atk"), "공격력 골드 강화 구매")
	var attack: float = sim.heroes[0]["atk"]
	check(Arena.restore(Save.cur_run) and Arena.sim.heroes[0]["atk"] == attack and Arena.lv("atk") == 1, "구매 즉시 저장·능력치 복구")
	Arena.close_modal()
	sim = Arena.sim
	_advance(sim, 0.7)
	var saved := Arena.snapshot()
	var rng: int = sim._rng.state
	var elapsed_time: float = sim.elapsed
	check(Arena.restore(saved) and Arena.sim.elapsed == elapsed_time and Arena.sim._rng.state == rng and Arena.sim.monsters == saved["sim"]["monsters"], "전투 진행·몬스터·난수 정확 복구")
	_check_serialized_save(saved)
	Arena.restore(saved)
	_advance(Arena.sim, 2.0)
	var first_branch := Arena.snapshot()
	Arena.restore(saved)
	_advance(Arena.sim, 2.0)
	var second_branch := Arena.snapshot()
	if first_branch != second_branch:
		for key in first_branch:
			if first_branch[key] != second_branch[key]: print("복구 분기 차이: ", key)
	check(first_branch == second_branch, "복구 후 전투 진행도 동일한 결정론적 결과")
	Arena.restore(saved)
	var broken := saved.duplicate(true)
	broken["sim"]["monsters"][0].erase("cast_t")
	check(not Arena.restore(broken) and Arena.sim.elapsed == elapsed_time, "손상 몬스터 저장 거부·현재 판 보존")
	broken = saved.duplicate(true)
	broken["bench"].append(broken["heroes"][0].duplicate())
	check(not Arena.restore(broken), "전장·대기 중복 ID 저장 거부")
	broken = saved.duplicate(true)
	broken["sim"]["pending"] = [{"hi":0}]
	check(not Arena.restore(broken), "손상 발사 대기 저장 거부")
	broken = saved.duplicate(true)
	broken["phase"] = 3
	check(not Arena.restore(broken), "메뉴·진행 단계 불일치 저장 거부")

func _check_serialized_save(state: Dictionary) -> void:
	var store = load("res://core/save.gd").new()
	var path := "user://arena-check-%d.cfg" % Time.get_ticks_usec()
	store.storage_path = path
	store.cur_run = state.duplicate(true)
	check(store.save_file(), "새 저장 형식 실제 파일 기록")
	var reopened = load("res://core/save.gd").new()
	reopened.storage_path = path
	reopened.load_file()
	check(not reopened.cur_run.is_empty() and Arena.restore(reopened.cur_run), "Vector2·PackedVector2Array 포함 저장 파일 복구")
	check(Arena.gold == state["gold"] and Arena.sim.crystal_hp == state["sim"]["crystal_hp"] and is_equal_approx(Arena.sim.elapsed, state["sim"]["elapsed"]), "디스크 복구 후 골드·수정체력·시간 유지")
	store.cur_run = state.duplicate(true)
	store.cur_run["gold"] += 1
	store.save_file()
	var broken := ConfigFile.new()
	broken.set_value("cur", "state", {"mode":"arena", "v":ArenaValidation.SAVE_V})
	broken.save(path)
	reopened.load_file()
	check(reopened.recovered_backup and not reopened.cur_run.is_empty() and Arena.restore(reopened.cur_run), "손상 새 모드 저장은 정상 백업으로 복구")
	# A run saved under the pre-stage rules is dropped; lifetime records survive.
	var outdated := ConfigFile.new()
	for key in ["best_wave", "runs", "clears", "total_kills"]: outdated.set_value("run", key, 7)
	outdated.set_value("run", "best_hand", 5)
	outdated.set_value("cur", "state", {"mode":"arena", "v":2, "wave":1})
	outdated.save(path)
	if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
	reopened.load_file()
	check(reopened.cur_run.is_empty() and reopened.runs == 7 and reopened.best_tier == 5 and not reopened.recovered_backup, "탄 사슬 이전 판만 버리고 평생 기록 보존")
	store.free()
	reopened.free()
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _check_boss() -> void:
	var sim := _battle(707)
	var initial_limit := sim.population_limit()
	var initial_gap := sim.spawn_interval()
	_monster(sim, ArenaGeometry.MAP_RECT.position + Vector2(30, 30))
	sim.elapsed = Balance.ARENA_BOSS_AT - Balance.ARENA_BOSS_WARNING - 0.02
	check(sim.population_limit() > initial_limit and sim.spawn_interval() < initial_gap, "시간에 따라 개체 수·스폰 빈도 증가")
	sim.events.clear()
	_advance(sim, 0.1)
	var warnings := 0
	var warned_at := Vector2.INF
	for e in sim.events:
		if String(e.get("t", "")) == "arena_boss_warning":
			warnings += 1
			warned_at = e.get("p", Vector2.INF)
	check(sim.boss_warned and not sim.boss_spawned and sim.boss_lane >= 0 and sim.boss_lane < ArenaGeometry.route_count(), "보스 출현 %.0f초 전 예고·입구 확정" % Balance.ARENA_BOSS_WARNING)
	check(warnings == 1 and warned_at.is_finite() and warned_at == sim.boss_gate() and ArenaGeometry.on_road(warned_at, Balance.ARENA_MONSTER_RADIUS), "예고 이벤트 1회·예고 지점은 입구 도로 위")
	var gate := sim.boss_gate()
	var lane: int = sim.boss_lane
	var mid := Arena.snapshot()
	check(ArenaValidation.valid(mid) and Arena.restore(mid) and Arena.sim.boss_warned and Arena.sim.boss_lane == lane, "예고 중 저장·복구에도 입구 유지")
	sim = Arena.sim
	sim.events.clear()
	# Jump to the last tick before the boss so no regular enemy spawns in between.
	sim.elapsed = Balance.ARENA_BOSS_AT - 0.02
	_advance(sim, 0.1)
	check(sim.boss_spawned and sim.boss_alive and sim.monsters.size() == 2, "탄 보스 1회 등장·기존 적 유지")
	var boss_at := Vector2.INF
	for e in sim.events:
		if String(e.get("t", "")) == "arena_boss": boss_at = e.get("p", Vector2.INF)
	check(boss_at.is_finite() and (boss_at - Balance.ARENA_CENTER).normalized().dot((gate - Balance.ARENA_CENTER).normalized()) > 0.99, "보스가 예고한 입구에서 등장")
	warnings = 0
	for e in sim.events:
		if String(e.get("t", "")) == "arena_boss_warning": warnings += 1
	check(warnings == 0, "예고는 한 번만")
	var serial: int = sim._serial
	_advance(sim, 3.0)
	check(sim._serial == serial, "보스 이후 신규 스폰 중단")
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	check(not sim.done and not sim.won and Arena.running and sim.clear_t > 0.0 and sim.monsters.is_empty(), "탄 보스 처치: 판은 이어지고 남은 적은 흩어짐")

func _check_duration() -> void:
	var sim := _battle(708)
	# Keep enemies alive at the perimeter to exercise a whole stage timer
	# and population curve without conflating this check with player strategy.
	sim.heroes[0]["cool"] = 100000.0
	var cap_observed := 0
	var sides := {}
	var safe_population := true
	var paused := false
	while sim.elapsed < Balance.ARENA_BOSS_AT - 0.5:
		if not paused and sim.elapsed >= Balance.ARENA_BOSS_AT * 0.5:
			Arena.open_modal("shop")
			var elapsed_time: float = sim.elapsed
			_advance(sim, 10.0)
			check(sim.elapsed == elapsed_time and not sim.boss_spawned, "탄 진행 중 메뉴의 10초를 전투 시간에서 제외")
			Arena.close_modal()
			sim.heroes[0]["cool"] = 100000.0
			paused = true
		sim.step(0.25)
		safe_population = safe_population and sim.monsters.size() <= sim.population_limit()
		cap_observed = maxi(cap_observed, sim.monsters.size())
		for mo in sim.monsters:
			if float(mo["spd"]) > 0.0:
				var at: Vector2 = mo["pos"]
				var rect := ArenaGeometry.MAP_RECT.grow(-Balance.ARENA_MONSTER_RADIUS)
				var distances := [absf(at.x - rect.position.x), absf(at.x - rect.end.x), absf(at.y - rect.position.y), absf(at.y - rect.end.y)]
				sides[distances.find(distances.min())] = true
			mo["spd"] = 0.0
	check(not sim.boss_spawned and sim.elapsed >= Balance.ARENA_BOSS_AT - 1, "탄 시간 누적 진행에서도 보스 조기 등장 없음")
	check(safe_population and cap_observed == sim.population_limit() and cap_observed > Balance.ARENA_POPULATION_START, "1탄의 실제 개체 수가 8명에서 그 탄의 한도까지 증가 (%d)" % cap_observed)
	check(sides.size() == 4, "네 방향 모두 실제 랜덤 스폰")
	_advance(sim, 1.0)
	check(sim.boss_spawned and sim.boss_alive and not sim.done, "탄 시간 누적 직후 보스 등장")
	var serial: int = sim._serial
	_advance(sim, 2.0)
	check(sim._serial == serial and sim.monsters.size() <= Balance.ARENA_POPULATION_MAX + 1, "긴 실행 후에도 보스 이후 스폰·개체 한도 유지")

func _check_shop() -> void:
	var sim := _battle(709)
	Arena.gold = 1000000
	Arena.open_modal("shop")
	var first_offer := Arena.shop_offer.duplicate()
	for id in first_offer:
		check(Arena.buy_passive(id), "첫 진열 패시브 골드 구매: " + id)
	check(not Arena.shop_offer.is_empty() and not Arena.shop_offer.has("echo"), "진열 모두 구매 후 다음 후보 보충·합성 전용 패시브 제외")
	var active := Arena.passives.duplicate()
	var extra_id := String(Arena.shop_offer[0])
	check(Arena.buy_passive(extra_id) and Arena.owned_passives.size() > Arena.passives.size(), "활성 3칸이 찼어도 패시브 보유 가능")
	check(Arena.toggle_passive(active[0]) and Arena.toggle_passive(extra_id) and Arena.passives.has(extra_id), "보유 패시브 해제·활성 교체")
	check(not Arena.buy_upgrade("removed_upgrade") and not Arena.levels.has("removed_upgrade"), "없는 강화 항목 구매 차단")
	for passive in Balance.PASSIVES:
		if int(passive.get("rank", 1)) < 3 and not Arena.owned_passives.has(passive["id"]):
			Arena.owned_passives.append(passive["id"])
	Arena.close_modal()
	# Late in the run: the last stage, most of the way to its boss.
	sim.stage = Balance.ARENA_STAGES
	sim.elapsed = Balance.ARENA_BOSS_AT * 0.9
	Arena.open_modal("shop")
	check(not Arena.shop_offer.is_empty(), "후반부 상위 패시브 해금")
	for id in Arena.shop_offer:
		check(int(Balance.passive_by_id(id)["rank"]) == 3 and id != "echo", "후반부 실제 상위 패시브 진열: " + id)


func _kill_boss(sim: ArenaSim) -> void:
	sim.elapsed = Balance.ARENA_BOSS_AT - 0.02
	_advance(sim, 0.1)
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()

## The run is a chain of battlefields: a boss per stage, a bounty and a mended crystal
## between them, a new random field with its own roads each time, the last boss wins.
func _check_stage_chain() -> void:
	Arena.start_run(811)
	var themes: Array = Arena.stage_themes.duplicate()
	check(themes.size() == Balance.ARENA_STAGES, "판을 시작할 때 열 탄의 전장이 정해짐")
	var visits := {}
	var order_ok := true
	var rank_ok := true
	var early_ok := true
	for n in range(themes.size()):
		var theme: Dictionary = Roster.THEMES[themes[n]]
		var body := String(theme["main_body"])
		visits[body] = int(visits.get(body, 0)) + 1
		if n > 0 and String(Roster.THEMES[themes[n - 1]]["main_body"]) == body: order_ok = false
		if int(theme["rank"]) != clampi(ceili(float(n + 1) * 5.0 / float(Balance.ARENA_STAGES)), 1, 5): rank_ok = false
		if n < 3 and not Balance.body_immune(body).is_empty(): early_ok = false
	check(visits.size() == 5 and order_ok, "다섯 지형을 고루 돌고 같은 지형이 연달아 나오지 않음")
	check(rank_ok, "뒤 탄일수록 험한 전장 (험지 등급 1에서 5까지)")
	check(early_ok, "앞 세 탄에는 면역 몸의 지형이 걸리지 않음")
	Arena.start_run(811)
	check(Arena.stage_themes == themes, "같은 씨앗은 같은 전장 차례")
	var opened := 0
	for e in Arena.sim.events:
		if String(e.get("t", "")) == "arena_stage" and int(e.get("stage", 0)) == 1: opened += 1
	check(opened == 1, "판의 첫 전장도 새 전장 이벤트로 열림")
	var different := 0
	for seed_value in range(900, 920):
		Arena.start_run(seed_value)
		if Arena.stage_themes != themes: different += 1
	check(different >= 19, "씨앗이 다르면 전장 차례도 달라짐")
	Arena.start_run(812)
	check(Arena.confirm_stage() and Arena.modal == "rite" and Arena.summon_count == 0, "1탄 카드 다음은 첫 무료 의식")
	Arena.confirm_summon()
	Arena.close_modal()
	var sim: ArenaSim = Arena.sim
	check(sim.stage == 1 and Arena.wave == 1 and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index), "전장마다 정해진 길 배치 사용")
	sim.crystal_hp = sim.crystal_max * 0.5
	sim.cast_skill("ward")
	var uses_left := sim.skill_uses_left("ward")
	var gold: int = Arena.gold
	var kills: int = Arena.kills
	var first_theme: int = Arena.theme_index
	_monster(sim, ArenaGeometry.route_points(0)[8])
	sim.events.clear()
	_kill_boss(sim)
	var cleared := false
	var scattered := 0
	for e in sim.events:
		if String(e.get("t", "")) == "arena_stage_clear" and int(e.get("stage", 0)) == 1: cleared = true
		if String(e.get("t", "")) == "die" and bool(e.get("scatter", false)): scattered += 1
	check(cleared and scattered == 1 and sim.clear_t > 0.0, "탄 돌파 이벤트·남은 적 흩어짐")
	check(Arena.gold >= gold + Balance.arena_stage_bonus(1), "탄 돌파 골드 지급")
	check(is_equal_approx(sim.crystal_hp, sim.crystal_max * (0.5 + Balance.ARENA_STAGE_HEAL)), "탄 돌파 때 수정 일부 회복")
	check(not sim.cast_skill("blast"), "돌파 연출 중 기술 사용 차단")
	var during := Arena.snapshot()
	check(ArenaValidation.valid(during) and Arena.restore(during) and Arena.sim.clear_t > 0.0 and Arena.stage == 1, "돌파 연출 중 저장·복구")
	sim = Arena.sim
	var hp_after: float = sim.crystal_hp
	sim._damage_crystal(50.0, Balance.ARENA_CENTER)
	check(sim.crystal_hp == hp_after, "돌파 연출 중에는 수정이 피해를 받지 않음")
	_advance(sim, Balance.ARENA_CLEAR_DELAY + 0.2)
	check(Arena.stage == 2 and Arena.modal == "stage" and Arena.running and sim.stage == 2, "연출 뒤 2탄의 전장 카드")
	check(Arena.theme_index == Arena.stage_themes[1] and Arena.theme_index != first_theme and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index), "다음 탄은 다른 전장과 그 전장의 길")
	check(sim.elapsed == 0.0 and sim.monsters.is_empty() and not sim.boss_spawned and not sim.boss_warned, "새 탄은 시간·적·보스가 처음부터")
	check(sim.crystal_hp == hp_after and sim.skill_uses_left("ward") == uses_left and Arena.kills >= kills and Arena.heroes.size() == 1, "수정·기술 횟수·처치·영웅은 다음 탄으로 이어짐")
	var staged := false
	for e in sim.events:
		if String(e.get("t", "")) == "arena_stage" and int(e.get("stage", 0)) == 2: staged = true
	check(staged, "새 전장 이벤트")
	var card := Arena.snapshot()
	var elapsed_time: float = sim.elapsed
	_advance(sim, 3.0)
	check(sim.elapsed == elapsed_time, "전장 카드가 열려 있는 동안 전투 정지")
	check(ArenaValidation.valid(card) and Arena.restore(card) and Arena.modal == "stage" and Arena.stage == 2, "전장 카드 중 저장·복구")
	check(Arena.sim.events.is_empty(), "이어 한 판은 전장을 다시 공개하지 않음")
	check(Arena.confirm_stage() and Arena.modal == "" and Arena.summon_count == 1, "2탄부터는 카드 뒤 바로 전투 (무료 의식은 첫 한 번)")
	sim = Arena.sim
	_advance(sim, 12.0)
	check(sim.elapsed > 11.0 and not sim.monsters.is_empty(), "2탄 전투 진행·몬스터 출현")
	for mo in sim.monsters:
		if not ArenaGeometry.on_road(mo["pos"]): check(false, "2탄 몬스터가 새 길 위에 있음")
	var mid := Arena.snapshot()
	ArenaGeometry.use_layout("coil:0:0")
	check(ArenaValidation.valid(mid) and ArenaGeometry.layout() == "coil:0:0", "저장 검사는 그 전장의 길로 보고 지금 배치를 건드리지 않음")
	check(Arena.restore(mid) and Arena.stage == 2 and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index) and Arena.sim.monsters == mid["sim"]["monsters"], "2탄 전투 중 저장·복구가 길 배치까지 되돌림")
	var wrong := mid.duplicate(true)
	wrong["theme_index"] = (int(mid["theme_index"]) + 1) % Roster.THEMES.size()
	check(not ArenaValidation.valid(wrong), "탄과 맞지 않는 전장 저장 거부")
	wrong = mid.duplicate(true)
	wrong["stage"] = Balance.ARENA_STAGES + 1
	wrong["wave"] = wrong["stage"]
	check(not ArenaValidation.valid(wrong), "없는 탄 저장 거부")
	# Walk the rest of the chain: every boss opens the next stage, the last one wins.
	var best_before: int = Save.best_stage
	var clears: int = Save.clears
	var guard := 0
	while Arena.running and guard < 40:
		guard += 1
		if Arena.modal == "stage": Arena.confirm_stage()
		sim = Arena.sim
		if sim.final_stage(): break
		_kill_boss(sim)
		_advance(sim, Balance.ARENA_CLEAR_DELAY + 0.2)
	# The last boss falls with the same beat as every other, and only then is the run won.
	sim.events.clear()
	sim.elapsed = Balance.ARENA_BOSS_AT - Balance.ARENA_BOSS_WARNING - 0.02
	_advance(sim, 0.1)
	var final_warning := false
	for e in sim.events:
		if String(e.get("t", "")) == "arena_boss_warning" and bool(e.get("final", false)): final_warning = true
	check(final_warning, "마지막 보스 예고는 최종 표시를 실음")
	_kill_boss(sim)
	var final_clear := false
	for e in sim.events:
		if String(e.get("t", "")) == "arena_stage_clear" and bool(e.get("final", false)): final_clear = true
	check(Arena.running and not sim.done and not sim.won and sim.clear_t > 0.0 and final_clear and sim.monsters.is_empty(), "마지막 보스도 쓰러지는 연출을 거친 뒤 승리")
	var closing := Arena.snapshot()
	check(ArenaValidation.valid(closing) and Arena.restore(closing) and Arena.running and Arena.sim.clear_t > 0.0, "마지막 돌파 연출 중 저장·복구")
	_advance(Arena.sim, Balance.ARENA_CLEAR_DELAY + 0.2)
	check(not Arena.running and Arena.stage == Balance.ARENA_STAGES and Arena.sim.won and Arena.modal == "result", "마지막 탄의 보스를 잡으면 승리")
	check(Save.best_stage == Balance.ARENA_STAGES and Save.best_stage >= best_before and Save.clears == clears + 1, "최고 도달 탄·완료 횟수 기록")

## Monsters grow with the stage: thicker, a richer bounty, more kinds and a denser crowd.
func _check_stage_strength() -> void:
	var hp_ok := true
	var gold_ok := true
	for stage in range(2, Balance.ARENA_STAGES + 1):
		if Balance.arena_hp(stage, 1) <= Balance.arena_hp(stage - 1, 1) * 1.05: hp_ok = false
		if Balance.arena_kill_gold(stage, "swarm") < Balance.arena_kill_gold(stage - 1, "swarm"): gold_ok = false
	check(hp_ok and is_equal_approx(Balance.arena_hp(1, 1), Balance.wave_hp(1, 1) * Balance.ARENA_HP_SCALE), "몬스터 체력은 1탄이 예전 값이고 탄마다 오름")
	check(gold_ok and Balance.arena_kill_gold(Balance.ARENA_STAGES, "swarm") > Balance.arena_kill_gold(1, "swarm"), "처치 골드도 탄을 따라 오름")
	var sim := _battle(813)
	sim.monsters.clear()
	sim._spawn(Arena.stage_spawns(1, 0)[0])
	var first: Dictionary = sim.monsters[0].duplicate(true)
	var early_limit := sim.population_limit()
	var early_gap := sim.spawn_interval()
	var kinds_first := {}
	for monster in Arena.stage_spawns(1, 0) + Arena.stage_spawns(1, 1): kinds_first[String(monster["kind"])] = true
	check(kinds_first.keys() == ["swarm"], "1탄은 떼거리만 나옴")
	# The same run, last stage.
	Arena.stage = Balance.ARENA_STAGES
	Arena.theme_index = Arena.stage_themes[Balance.ARENA_STAGES - 1]
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(Arena.theme_index))
	sim.begin_stage(Balance.ARENA_STAGES)
	sim._spawn(Arena.stage_spawns(Balance.ARENA_STAGES, 0)[0])
	var last: Dictionary = sim.monsters[0]
	var ratio := (float(last["max"]) / float(Balance.MKIND[String(last["kind"])]["hp"])) / (float(first["max"]) / float(Balance.MKIND[String(first["kind"])]["hp"]))
	check(ratio > pow(Balance.ARENA_STAGE_HP_GROW, Balance.ARENA_STAGES - 1) * 0.99, "마지막 탄 몬스터는 1탄보다 훨씬 두꺼움 (x%.1f)" % ratio)
	check(int(last["gold"]) >= int(first["gold"]) and sim.population_limit() > early_limit and sim.spawn_interval() < early_gap, "마지막 탄은 더 붐비고 더 자주 나옴")
	sim.elapsed = Balance.ARENA_BOSS_AT
	check(sim.population_limit() == Balance.ARENA_POPULATION_MAX and is_equal_approx(sim.spawn_interval(), Balance.ARENA_SPAWN_MIN), "판의 끝에서 개체 수·출현 간격이 한계값")
	var kinds_last := {}
	for monster in Arena.stage_spawns(Balance.ARENA_STAGES, 0) + Arena.stage_spawns(Balance.ARENA_STAGES, 1): kinds_last[String(monster["id"])] = true
	check(kinds_last.size() >= 4, "마지막 탄은 여러 종이 섞임 (%d종)" % kinds_last.size())
	sim.monsters.clear()
	sim.elapsed = Balance.ARENA_BOSS_AT - 0.02
	_advance(sim, 0.1)
	var boss: Dictionary = {}
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": boss = mo
	check(not boss.is_empty() and is_equal_approx(float(boss["max"]), Balance.arena_boss_hp(Balance.ARENA_STAGES, Arena.theme_rank(1))) and Balance.arena_boss_hp(Balance.ARENA_STAGES, 5) > Balance.arena_boss_hp(Balance.ARENA_STAGES - 1, 5) * Balance.ARENA_STAGE_HP_GROW, "최종 보스는 탄 보스보다 두꺼움")
	check(Balance.arena_boss_hp(1, 1) < Balance.arena_hp(1, 1) * float(Balance.MKIND["boss"]["hp"]) * 0.5, "1탄 보스는 영웅 두셋으로 잡을 수 있게 가벼움")
	Arena.running = false
