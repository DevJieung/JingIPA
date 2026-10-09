extends Harness

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_summons()
	_check_movement()
	_check_navigation()
	_check_crystal_and_skills()
	_check_pause_and_save()
	_check_boss()
	_check_duration()
	_check_shop()
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
	mo["pos"] = at
	mo["hp"] = 100000.0
	mo["max"] = mo["hp"]
	sim._cache_positions()
	return mo

func _check_summons() -> void:
	Arena.start_run(700)
	check(ArenaValidation.valid(Arena.snapshot()), "테마 선택 중 저장")
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
	check(ArenaGeometry.MAP_RECT.has_point(sim.heroes[0]["pos"]), "맵 경계 이탈 금지")
	sim.monsters.clear()
	var p: Vector2 = sim.heroes[0]["pos"]
	_monster(sim, p + Vector2(40, 0))
	_monster(sim, p + Vector2(120, 0))
	sim._cache_positions()
	check(sim._nearest_target(p, 200) == 0 and sim._nearest_target(p, 20) == -1, "각 영웅 위치 기준 최근접·사거리")

func _check_navigation() -> void:
	var sim := _battle(703)
	Arena.heroes[0]["position"] = Balance.ARENA_CENTER + Vector2(-160, 0)
	sim.refresh_heroes()
	sim._rebuild_navigation()
	var mo := _monster(sim, Balance.ARENA_CENTER + Vector2(-310, 0))
	var detoured := false
	var safe := true
	for i in range(900):
		sim._move_monsters(1.0 / 60.0)
		detoured = detoured or absf(Vector2(mo["pos"]).y - Balance.ARENA_CENTER.y) > 15
		safe = safe and Vector2(mo["pos"]).distance_to(sim.heroes[0]["pos"]) >= Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS - 0.01
	check(detoured and safe, "영웅 길막 시 충돌 없이 우회")
	check(Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 2, "우회 후 크리스탈 도착")
	# Seal a spawned enemy against the edge with a legal 6-hero chain.
	sim = _battle(704)
	for unit in Roster.UNITS:
		if Arena.heroes.size() == 6: break
		if not _contains_unit([Arena.heroes[0]["unit"]], String(unit["id"])): Arena.gain_hero(unit, 1)
	for i in range(6):
		Arena.heroes[i]["position"] = Vector2(ArenaGeometry.MAP_RECT.position.x + 80, ArenaGeometry.MAP_RECT.position.y + 27 + i * 52)
	sim.refresh_heroes()
	sim._rebuild_navigation()
	# A trapped enemy's own start cell is closed when a hero approaches it.
	mo = _monster(sim, sim.heroes[0]["pos"])
	var position: Vector2 = mo["pos"]
	var hp: float = sim.crystal_hp
	for i in range(600): sim._move_monsters(1.0 / 60.0)
	check(mo["pos"] == position and mo["blocked"] and mo["motion_t"] == 0.0 and sim.crystal_hp == hp, "경로 없으면 무기한 대기·밀어내기 없음")
	Arena.heroes[0]["position"] += Vector2(200, 0)
	sim.refresh_heroes()
	sim._rebuild_navigation()
	for i in range(60): sim._move_monsters(1.0 / 60.0)
	check(mo["pos"] != position, "길막 해제 후 이동 재개")
	var trap := Balance.ARENA_CENTER + Vector2(-220, 0)
	for i in range(6):
		Arena.heroes[i]["position"] = trap + Vector2.from_angle(i * TAU / 6.0) * 60.0
	sim.refresh_heroes()
	sim._rebuild_navigation()
	sim.monsters.clear()
	mo = _monster(sim, trap)
	for i in range(600): sim._move_monsters(1.0 / 60.0)
	check(mo["pos"] == trap and mo["blocked"] and mo["motion_t"] == 0.0, "겹침 없는 6인 완전 봉쇄에서도 무기한 대기")
	Arena.heroes[0]["position"] += Vector2(0, -200)
	sim.refresh_heroes()
	sim._rebuild_navigation()
	for i in range(60): sim._move_monsters(1.0 / 60.0)
	check(mo["pos"] != trap, "봉쇄에 틈을 열면 이동 재개")

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
	sim._damage_crystal(100000.0, Balance.ARENA_CENTER)
	check(sim.done and not sim.won and Arena.modal == "result", "크리스탈 파괴 패배")

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
	broken.set_value("cur", "state", {"mode":"arena", "v":1})
	broken.save(path)
	reopened.load_file()
	check(reopened.recovered_backup and not reopened.cur_run.is_empty() and Arena.restore(reopened.cur_run), "손상 새 모드 저장은 정상 백업으로 복구")
	store.free()
	reopened.free()
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _check_boss() -> void:
	var sim := _battle(707)
	var initial_limit := sim.population_limit()
	var initial_gap := sim.spawn_interval()
	_monster(sim, ArenaGeometry.MAP_RECT.position + Vector2(30, 30))
	sim.elapsed = Balance.ARENA_BOSS_AT - 0.02
	check(sim.population_limit() > initial_limit and sim.spawn_interval() < initial_gap, "시간에 따라 개체 수·스폰 빈도 증가")
	_advance(sim, 0.1)
	check(sim.boss_spawned and sim.boss_alive and sim.monsters.size() == 2, "18분 최종 보스 1회 등장·기존 적 유지")
	var serial: int = sim._serial
	_advance(sim, 3.0)
	check(sim._serial == serial, "보스 이후 신규 스폰 중단")
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	check(sim.done and sim.won and Arena.modal == "result" and sim.monsters.size() == 1, "일반 몬스터 남아도 최종 보스 처치 즉시 승리")

func _check_duration() -> void:
	var sim := _battle(708)
	# Keep enemies alive at the perimeter to exercise a whole 18-minute timer
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
			check(sim.elapsed == elapsed_time and not sim.boss_spawned, "18분 실제 진행 중 메뉴의 10초를 전투 시간에서 제외")
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
	check(not sim.boss_spawned and sim.elapsed >= Balance.ARENA_BOSS_AT - 1, "18분 누적 진행에서도 보스 조기 등장 없음")
	check(safe_population and cap_observed == Balance.ARENA_POPULATION_MAX, "연속 진행의 실제 개체 수가 8명부터 최대 48명까지 증가")
	check(sides.size() == 4, "네 방향 모두 실제 랜덤 스폰")
	_advance(sim, 1.0)
	check(sim.boss_spawned and sim.boss_alive and not sim.done, "18분 누적 직후 최종 보스 등장")
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
	sim.elapsed = Balance.ARENA_BOSS_AT * 0.9
	Arena.open_modal("shop")
	check(not Arena.shop_offer.is_empty(), "후반부 상위 패시브 해금")
	for id in Arena.shop_offer:
		check(int(Balance.passive_by_id(id)["rank"]) == 3 and id != "echo", "후반부 실제 상위 패시브 진열: " + id)
