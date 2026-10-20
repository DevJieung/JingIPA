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
	_check_wave_timing()
	_check_shop()
	_check_stage_run()
	_check_ladder_strength()
	_check_stage_seed()
	Arena.running = false
	finish("연속 수호전 규칙·저장")

## Starting a stage over before it is finished gives the same seed — the same free first box — so the box
## cannot be rerolled by starting again (2026-10-19). A clear or a defeat ends the attempt.
func _check_stage_seed() -> void:
	_reset_ladder()
	Save.stage_seeds = {}
	Save.stage_unlocked = 3
	Arena.start_run(0, 2)
	var first: int = Arena.run_seed
	Arena.confirm_stage()
	var cards: Array = Arena.box_cards.map(func(card: Dictionary) -> String: return "%s/%d" % [card["unit"]["id"], card["stars"]])
	var tier: int = Arena.box_tier
	check(first != 0 and Save.stage_seeds.get(2, 0) == first, "끝나지 않은 스테이지의 시드를 적어 둠")
	Arena.start_run(0, 2)
	Arena.confirm_stage()
	check(Arena.run_seed == first and Arena.box_tier == tier and Arena.box_cards.map(func(card: Dictionary) -> String: return "%s/%d" % [card["unit"]["id"], card["stars"]]) == cards,
		"새로 시작해도 같은 시드 · 같은 무료 첫 상자")
	Arena.start_run(0, 3)
	check(Arena.run_seed != first and Save.stage_seeds.has(3) and Save.stage_seeds.get(2, 0) == first, "다른 스테이지는 저마다의 시드")
	Arena.start_run(0, 2)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.sim.revives = Balance.ARENA_REVIVE_USES
	Arena.sim._damage_crystal(1.0e9, Balance.ARENA_CENTER)
	check(not Arena.running and not Save.stage_seeds.has(2), "지면 그 도전이 끝나 시드를 지움")
	Arena.retry()
	check(Arena.run_seed != first and Save.stage_seeds.get(2, 0) == Arena.run_seed, "다음 도전은 새 시드")
	var store = load("res://core/save.gd").new()
	var path := "user://arena-seed-%d.cfg" % Time.get_ticks_usec()
	store.storage_path = path
	store.stage_seeds = {2: 12345, 3: -7, 999: 5, 4: 0}
	check(store.save_file(), "시드 표 저장")
	var reopened = load("res://core/save.gd").new()
	reopened.storage_path = path
	reopened.load_file()
	check(reopened.stage_seeds == {2: 12345, 3: -7}, "시드 표는 파일에 남고 사다리 밖 · 0 은 버림")
	store.free()
	reopened.free()
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	Arena.running = false
	Save.stage_seeds = {}
	_reset_ladder()

## Checks that win a stage move Save's ladder records (memory only: STELLARDEFENSE_NO_SAVE). Put them
## back so `Arena.start_run(seed)` keeps opening STAGE 1 for the checks after.
func _reset_ladder() -> void:
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	Save.last_clear = {}

func _battle(seed_value: int = 701) -> ArenaSim:
	Arena.start_run(seed_value)
	check(Arena.choose_theme(0), "테마 선택")
	Arena.confirm_summon()
	Arena.close_modal()
	return Arena.sim

## Steps the battle; a level-up popup that opens on the way is answered like a player
## would (first star), so time keeps flowing in checks that are not about the popup.
func _advance(sim: ArenaSim, seconds: float, auto_pick: bool = true) -> void:
	for i in range(roundi(seconds * 60)):
		if auto_pick and Arena.modal == "talent" and not Arena.talent_offer.is_empty():
			Arena.pick_talent(String(Arena.talent_offer[0]))
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
	check(Arena.modal == "stage" and Arena.stage == 1 and Arena.theme_index == Arena.ladder_theme(1) and Arena.sim != null, "새 판은 사다리 STAGE 1 의 전장 카드에서 시작")
	check(ArenaValidation.valid(Arena.snapshot()), "전장 카드 중 저장")
	var initial_gold: int = Arena.gold
	Arena.choose_theme(0)
	check(Arena.gold == initial_gold and Arena.heroes.is_empty(), "첫 의식 무료·확정 전 지급 없음")
	check(Arena.sim.elapsed == 0.0 and Arena.modal == "box", "첫 상자 동안 전투 정지")
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
	check(Arena.summon_block() == "pool" and not Arena.begin_summon() and Arena.gold == 1000, "후보 소진 시 소환·골드 차감 차단 (이유: pool)")

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
	# Skills wait for a wave and cost gold (2026-10-19 F5 · M7): open wave 1 now, spawns held.
	check(not sim.cast_skill("ward") and String(sim.skill_state("ward")["block"]) == "prep", "정비 시간에는 스킬 대기")
	sim.begin_wave(1)
	sim._spawn_t = 1.0e9
	Arena.gold = 1000
	check(sim.cast_skill("ward") and sim.shield > 0 and not sim.cast_skill("ward"), "방어 스킬·쿨타임")
	check(Arena.gold == 1000 - sim.skill_cost("ward") and sim.skill_cost("ward") == Balance.ARENA_WARD_GOLD, "스킬을 쓰면 골드 차감")
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
	sim.begin_wave(1)
	sim._spawn_t = 1.0e9
	Arena.gold = 100000
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
	for modal in ["talent", "bench", "box"]:
		if modal == "box": check(Arena.begin_summon(), "골드 소환 진입")
		else: check(Arena.open_modal(modal), modal + " 진입")
		var before := sim.snapshot_arena()
		_advance(sim, 3.0, false)
		sim.move_selected(Vector2.RIGHT, 0.1)
		check(sim.elapsed == before["elapsed"] and sim.monsters == before["monsters"] and sim.skill_cooldowns == before["cooldowns"] and sim._spawn_t == before["spawn_t"] and sim.prep_t == before["prep_t"], modal + " 시간·몹·이동·쿨타임·정비 시계 완전 정지")
		check(not sim.cast_skill("blast"), modal + " 전투 조작 차단")
		var state := Arena.snapshot()
		check(ArenaValidation.valid(state) and Arena.restore(state), modal + " 저장 복구")
		sim = Arena.sim
		if modal == "box": Arena.confirm_summon()
		Arena.close_modal()
	# Growth is no longer bought: a level-up offers three constellation nodes and the pick
	# applies at once. Force one level and take the attack node when it is on offer.
	check(not Arena.buy_upgrade("atk") and Arena.lv("atk") == 0, "골드 강화 구매 없음 (골드는 별맞춤에만)")
	Arena.pending_levels = 1
	Arena.level = 1
	check(Arena.offer_levelup() and Arena.modal == "talent" and Arena.talent_offer.size() == Balance.ARENA_TALENT_CHOICES, "레벨업 별자리 셋 제시")
	check(not Arena.close_modal(), "고르기 전에는 별자리 팝업이 닫히지 않음")
	var pick := String(Arena.talent_offer[0])
	for id in Arena.talent_offer:
		if id == "fury_edge": pick = id
	var before_atk: float = sim.heroes[0]["atk"]
	check(Arena.pick_talent(pick) and Arena.talent_count(pick) == 1 and Arena.modal == "", "별자리 노드 선택·전투 복귀")
	var attack: float = Arena.sim.heroes[0]["atk"]
	if pick == "fury_edge": check(Arena.lv("atk") == 1 and attack > before_atk, "공격력 노드가 능력치 단계와 전투 수치를 바로 올림")
	check(Arena.restore(Save.cur_run) and Arena.sim.heroes[0]["atk"] == attack and Arena.talent_count(pick) == 1, "선택 즉시 저장·능력치 복구")
	sim = Arena.sim
	# The rest runs inside the first wave, so restoring covers spawns and the place in the wave's list.
	check(sim.skip_prep() and sim.in_prep(), "「바로 시작」은 다음 걸음에 웨이브를 연다")
	_advance(sim, 1.5)
	var saved := Arena.snapshot()
	var rng: int = sim._rng.state
	var elapsed_time: float = sim.elapsed
	var spawned: int = sim._wave_spawned
	check(not sim.in_prep() and spawned > 0 and spawned < sim.wave_size(), "첫 웨이브 진행 중 (%d/%d 출현)" % [spawned, sim.wave_size()])
	check(Arena.restore(saved) and Arena.sim.elapsed == elapsed_time and Arena.sim._rng.state == rng and Arena.sim.monsters == saved["sim"]["monsters"]
			and Arena.sim._wave_spawned == spawned and Arena.sim._wave_list == sim._wave_list and not Arena.sim.in_prep(), "전투 진행·몬스터·난수·웨이브 자리 정확 복구")
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
	# A v4 run (the ten-stage chain without waves) is dropped too; the ladder records stay.
	var chain := ConfigFile.new()
	for key in ["best_wave", "runs", "clears", "total_kills"]: chain.set_value("run", key, 3)
	chain.set_value("run", "best_hand", 4)
	chain.set_value("run", "stage_unlocked", 6)
	chain.set_value("run", "stage_cleared", 5)
	chain.set_value("cur", "state", {"mode":"arena", "v":4, "wave":2, "stage":2})
	chain.save(path)
	if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
	reopened.load_file()
	check(reopened.cur_run.is_empty() and reopened.stage_unlocked == 6 and reopened.stage_cleared == 5 and reopened.runs == 3 and not reopened.recovered_backup, "판 4(웨이브 이전) 저장은 판만 버리고 사다리 기록 보존")
	# 2026-10-19: a v5 run past limits that tuning moved (a longer preparation, more revivals, a later wave,
	# more cards) still loads and restores inside today's limits; a v5 run that fails its check for any
	# other reason is dropped alone — the unlocks, the codex, Hellbound's record and the settings stay.
	var moved := state.duplicate(true)
	moved["sim"]["prep_t"] = 8.0
	moved["sim"]["in_prep"] = true
	moved["sim"]["wave_spawned"] = 0
	moved["sim"]["revives"] = Balance.ARENA_REVIVE_USES + 2
	moved["sim"]["wave_no"] = Balance.ARENA_WAVES + 3
	var kept := ConfigFile.new()
	for key in ["best_wave", "runs", "clears", "total_kills"]: kept.set_value("run", key, 9)
	kept.set_value("run", "best_hand", 6)
	kept.set_value("run", "stage_unlocked", 7)
	kept.set_value("run", "stage_cleared", 6)
	kept.set_value("book", "units", {String(Roster.UNITS[0]["id"]): true, String(Roster.UNITS[1]["id"]): true})
	kept.set_value("book", "best", {String(Roster.UNITS[0]["id"]): 5})
	kept.set_value("hell", "best_wave", 23)
	kept.set_value("opt", "music", false)
	kept.set_value("cur", "state", moved)
	kept.save(path)
	if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
	reopened.load_file()
	check(not reopened.cur_run.is_empty() and reopened.stage_unlocked == 7 and reopened.hell_best_wave == 23 and not reopened.recovered_backup, "옛 상한을 넘는 판 5 도 그대로 읽힘(정비 8초 · 부활 횟수 · 웨이브)")
	check(Arena.restore(reopened.cur_run) and Arena.sim.prep_t <= Balance.arena_prep(Arena.sim.wave_no, Arena.sim.waves_total()) + 0.001
		and Arena.sim.revives == Balance.ARENA_REVIVE_USES and Arena.sim.wave_no == Balance.ARENA_WAVES, "복구는 지금의 상한으로 맞춤(정비 · 부활 · 웨이브)")
	var damaged := state.duplicate(true)
	damaged["heroes"][0]["u"] = "no_such_hero"
	kept.set_value("cur", "state", damaged)
	kept.save(path)
	if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
	reopened.load_file()
	check(reopened.cur_run.is_empty() and not reopened.recovered_backup and reopened.stage_unlocked == 7 and reopened.stage_cleared == 6 and reopened.runs == 9
		and reopened.seen_units.size() == 2 and reopened.best_of(String(Roster.UNITS[0]["id"])) == 5 and reopened.hell_best_wave == 23 and not reopened.music,
		"검사에 걸린 판 5 는 판만 버리고 해금 · 도감 · Hellbound 기록 · 설정 보존")
	check(reopened.save_file() and FileAccess.file_exists(path), "그 뒤의 저장도 기록을 그대로 씀")
	var after := ConfigFile.new()
	check(after.load(path) == OK and int(after.get_value("run", "stage_unlocked", 0)) == 7 and int(after.get_value("hell", "best_wave", 0)) == 23, "다시 쓴 파일에 해금 · Hellbound 기록이 남음")
	store.free()
	reopened.free()
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

## The boss comes with the last wave: announced during the last preparation phase, at the gate the
## warning names, followed by its escort, and nothing spawns after the wave's list. Its fall is the
## clear beat that ends the stage.
func _check_boss() -> void:
	var sim := _battle(707)
	sim.heroes[0]["cool"] = 100000.0
	# The ninth wave is held: the boss wave's preparation follows.
	sim.begin_wave(Balance.ARENA_WAVES - 1)
	sim._wave_spawned = sim._wave_list.size()
	sim.monsters.clear()
	_advance(sim, 0.05)
	check(sim.in_prep() and sim.wave_no == Balance.ARENA_WAVES and sim.is_boss_wave(sim.wave_no) and not sim.boss_warned and not sim.boss_spawned, "9웨이브를 막으면 보스 웨이브의 정비")
	_monster(sim, ArenaGeometry.MAP_RECT.position + Vector2(30, 30))
	_advance(sim, sim.prep_left() - Balance.ARENA_BOSS_WARNING - 0.05, false)
	check(not sim.boss_warned and sim.boss_lane < 0, "예고 전에는 입구가 정해지지 않음")
	sim.events.clear()
	_advance(sim, 0.1)
	var warnings := 0
	var warned_at := Vector2.INF
	for e in sim.events:
		if String(e.get("t", "")) == "arena_boss_warning":
			warnings += 1
			warned_at = e.get("p", Vector2.INF)
	check(sim.boss_warned and not sim.boss_spawned and sim.in_prep() and sim.boss_lane >= 0 and sim.boss_lane < ArenaGeometry.route_count(), "보스 출현 %.0f초 전(마지막 정비 중) 예고·입구 확정" % Balance.ARENA_BOSS_WARNING)
	check(warnings == 1 and warned_at.is_finite() and warned_at == sim.boss_gate() and ArenaGeometry.on_road(warned_at, Balance.ARENA_MONSTER_RADIUS), "예고 이벤트 1회·예고 지점은 입구 도로 위")
	var gate := sim.boss_gate()
	var lane: int = sim.boss_lane
	var mid := Arena.snapshot()
	check(ArenaValidation.valid(mid) and Arena.restore(mid) and Arena.sim.boss_warned and Arena.sim.boss_lane == lane and Arena.sim.in_prep(), "예고 중 저장·복구에도 입구 유지")
	sim = Arena.sim
	sim.heroes[0]["cool"] = 100000.0
	sim.events.clear()
	_advance(sim, sim.prep_left() + 0.03)
	check(sim.boss_spawned and sim.boss_alive and sim.monsters.size() == 2 and not sim.in_prep(), "보스 웨이브가 열리자 보스 1회 등장·기존 적 유지")
	var boss_at := Vector2.INF
	var opened := false
	warnings = 0
	for e in sim.events:
		if String(e.get("t", "")) == "arena_boss": boss_at = e.get("p", Vector2.INF)
		if String(e.get("t", "")) == "arena_wave" and bool(e.get("boss", false)) and int(e.get("wave", 0)) == Balance.ARENA_WAVES: opened = true
		if String(e.get("t", "")) == "arena_boss_warning": warnings += 1
	check(opened and boss_at.is_finite() and (boss_at - Balance.ARENA_CENTER).normalized().dot((gate - Balance.ARENA_CENTER).normalized()) > 0.99, "보스 웨이브 이벤트·보스가 예고한 입구에서 등장")
	check(warnings == 0, "예고는 한 번만")
	_advance(sim, float(Balance.ARENA_BOSS_ESCORT) * Balance.arena_wave_gap(sim.stage, sim.wave_no) + 0.5)
	check(sim._wave_list.size() == 1 + Balance.ARENA_BOSS_ESCORT and sim._wave_spawned == sim._wave_list.size(), "보스 뒤로 호위 %d 마리" % Balance.ARENA_BOSS_ESCORT)
	var serial: int = sim._serial
	_advance(sim, 2.0)
	check(sim._serial == serial, "보스 웨이브의 목록이 끝나면 새 출현 없음")
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	check(not sim.done and not sim.won and Arena.running and sim.clear_t > 0.0 and sim.monsters.is_empty(), "보스 처치: 돌파 연출, 남은 적은 흩어짐")

## Waves keep their own clock: nothing spawns in a preparation phase, a window stops the preparation and
## the wave alike, and every wave spawns exactly its list, one at a time at its pace, from random gates.
func _check_wave_timing() -> void:
	var sim := _battle(708)
	sim.heroes[0]["cool"] = 100000.0
	var serial: int = sim._serial
	_advance(sim, 2.0, false)
	check(sim.in_prep() and sim._serial == serial and sim.elapsed > 1.9, "정비 시간에는 아무것도 나오지 않음")
	var left := sim.prep_left()
	var elapsed_time: float = sim.elapsed
	Arena.open_modal("talent")
	_advance(sim, 10.0, false)
	check(sim.prep_left() == left and sim.elapsed == elapsed_time, "창이 열린 10초는 정비 시계에서도 빠짐")
	Arena.close_modal()
	var lanes := {}
	for w in range(1, 4):
		check(sim.skip_prep(), "%d웨이브 바로 시작" % w)
		var times: Array[float] = []
		var guard := 0
		while (sim.in_prep() or sim._wave_spawned < sim.wave_size()) and guard < 2400:
			guard += 1
			var before: int = sim._serial
			sim.step(1.0 / 60.0)
			if sim._serial != before: times.append(sim.wave_t)
			for mo in sim.monsters: mo["spd"] = 0.0
		check(times.size() == Balance.arena_wave_count(sim.stage, w) and sim.wave_size() == times.size(), "%d웨이브는 목록 %d마리를 모두 냄 (%d)" % [w, Balance.arena_wave_count(sim.stage, w), times.size()])
		var even := true
		for i in range(1, times.size()):
			if absf(times[i] - times[i - 1] - Balance.arena_wave_gap(sim.stage, w)) > 1.5 / 60.0: even = false
		check(even, "%d웨이브는 한 마리씩 %.2f초 간격" % [w, Balance.arena_wave_gap(sim.stage, w)])
		for mo in sim.monsters: lanes[int(mo["route"])] = true
		var spawned: int = sim._serial
		_advance(sim, 2.0, false)
		check(sim._serial == spawned and not sim.in_prep(), "%d웨이브 목록이 끝나면 더 나오지 않고 웨이브는 이어짐" % w)
		if w == 1:
			Arena.open_modal("bench")
			var wave_clock: float = sim.wave_t
			_advance(sim, 5.0, false)
			check(sim.wave_t == wave_clock and sim.elapsed > elapsed_time, "창이 열린 동안 웨이브 시계도 멈춤")
			Arena.close_modal()
		for mo in sim.monsters: mo["hp"] = 0.0
		sim._cache_positions()
		sim._reap()
		check(sim.in_prep() and sim.wave_no == w + 1 and sim._serial == spawned, "%d웨이브를 다 잡으면 다음 웨이브의 정비" % w)
		while Arena.modal == "talent" and not Arena.talent_offer.is_empty():
			Arena.pick_talent(String(Arena.talent_offer[0]))
	check(lanes.size() >= mini(2, ArenaGeometry.route_count()), "여러 입구에서 실제 무작위 출현 (%d곳)" % lanes.size())

## Constellations replace the gold shop (2026-10-17): experience from kills levels the run
## up, every level offers three open nodes, a pick is permanent. Gold only summons.
func _check_shop() -> void:
	var sim := _battle(709)
	Arena.gold = 1000000
	check(not Arena.open_modal("shop") and Arena.modal == "", "상점 모달 없음")
	check(not Arena.buy_passive("repeater") and not Arena.buy_upgrade("rate") and Arena.owned_passives.is_empty() and Arena.lv("rate") == 0, "골드로 능력치·패시브를 살 수 없음")
	check(Arena.open_modal("talent") and Arena.talent_offer.is_empty() and Arena.close_modal(), "고를 것이 없을 때의 별자리 열람은 열고 닫힘")
	# Experience: kills fill the bar; the first level needs Balance.arena_xp_needed(0).
	var need := Arena.xp_needed()
	check(need == Balance.ARENA_XP_BASE and Arena.level == 0 and Arena.xp == 0.0, "첫 레벨까지의 경험치는 표의 밑값")
	var kills := 0
	var levelups := 0
	while Arena.level == 0 and kills < 40:
		var mo := _monster(sim, Balance.ARENA_CENTER + Vector2(220, 60))
		mo["hp"] = 0.0
		sim._cache_positions()
		sim._reap()
		for e in sim.events:
			if String(e.get("t", "")) == "arena_levelup": levelups += 1
		sim.events.clear()
		kills += 1
	check(Arena.level == 1 and levelups == 1 and kills == ceili(float(need) / Balance.arena_ladder_xp(Arena.stage, String(Arena.spawns_for(1)[0]["kind"]))), "처치 경험치가 차면 레벨 1·레벨업 이벤트 1회 (%d처치)" % kills)
	check(Arena.modal == "talent" and Arena.pending_levels == 1 and Arena.talent_offer.size() == Balance.ARENA_TALENT_CHOICES, "레벨업 즉시 별자리 팝업이 열림")
	var seen := {}
	var groups := {}
	for id in Arena.talent_offer:
		var node := Talents.by_id(id)
		check(not node.is_empty() and Talents.requirements_met(node, Arena.talents), "제시된 노드는 표에 있고 선행 조건을 갖춤: " + id)
		seen[id] = true
		groups[String(node.get("group", ""))] = true
	check(seen.size() == Arena.talent_offer.size() and groups.size() == Arena.talent_offer.size(), "제시된 셋은 서로 다른 노드·서로 다른 별자리")
	var saved := Arena.snapshot()
	check(ArenaValidation.valid(saved) and Arena.restore(saved) and Arena.talent_offer == saved["talent_offer"] and Arena.modal == "talent", "별자리 팝업 중 저장·복구에 같은 셋이 남음")
	sim = Arena.sim
	check(not sim.cast_skill("blast") and not Arena.close_modal(), "팝업 중 전투 조작과 닫기 차단")
	check(not Arena.pick_talent("fury_wrath") and not Arena.pick_talent("nothing"), "제시되지 않은 노드는 고를 수 없음")
	var first := String(Arena.talent_offer[0])
	check(Arena.pick_talent(first) and Arena.talent_count(first) == 1 and Arena.pending_levels == 0 and Arena.modal == "" and Arena.talent_offer.is_empty(), "노드를 고르면 팝업이 닫히고 전투로")
	# Several levels at once: a boss worth of experience.
	var gained: int = Arena.gain_xp(float(Arena.xp_needed()) + float(Balance.arena_xp_needed(Arena.level + 1)) + 0.5)
	check(gained == 2 and Arena.pending_levels == 2, "큰 경험치는 레벨을 둘 올리고 둘을 고르게 함")
	check(Arena.offer_levelup() and Arena.modal == "talent", "남은 레벨의 팝업")
	var second := String(Arena.talent_offer[0])
	# (The node just taken may come again only when it has ranks left.)
	check(Arena.pick_talent(second) and Arena.pending_levels == 1 and Arena.modal == "talent" and not Arena.talent_offer.is_empty()
		and (not Arena.talent_offer.has(second) or int(Talents.by_id(second).get("max", 1)) > 1), "하나를 고르면 남은 레벨의 새 셋이 바로 뜸")
	check(Arena.pick_talent(String(Arena.talent_offer[0])) and Arena.pending_levels == 0 and Arena.modal == "", "마지막 레벨을 고르면 닫힘")
	# Node effects: upgrade levels, passives and instants land where the rules read them.
	Arena.talent_offer.assign(["fury_edge", "tempo_repeat", "guard_now"])
	Arena.modal = "talent"
	Arena.pending_levels = 3
	var atk_before: float = Arena.sim.heroes[0]["atk"]
	check(Arena.pick_talent("fury_edge") and Arena.lv("atk") == 1 and Arena.sim.heroes[0]["atk"] > atk_before, "능력치 노드는 상점 단계를 올림")
	Arena.talent_offer.assign(["tempo_repeat", "guard_now", "fate_treasure"])
	check(Arena.pick_talent("tempo_repeat") and Arena.has("repeater") and Arena.owned_passives.has("repeater"), "패시브 노드는 그 패시브를 바로 켬")
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.5
	Arena.talent_offer.assign(["guard_now", "fate_treasure", "fate_bond"])
	check(Arena.pick_talent("guard_now") and is_equal_approx(Arena.sim.crystal_hp, Arena.sim.crystal_max * 0.8), "즉시 회복 노드는 수정을 바로 채움")
	check(Arena.modal == "" and Arena.pending_levels == 0, "셋을 다 고르면 전투로")
	# Repeatable nodes stop at their max, passives already owned are not offered again.
	Arena.talents["fury_edge"] = int(Talents.by_id("fury_edge")["max"])
	var open := Talents.available(Arena.talents, Arena.owned_passives, Arena.levels)
	check(not open.has("fury_edge") and not open.has("tempo_repeat") and open.has("fury_blaze") and open.has("fury_heavy"), "횟수를 다 쓴 노드·가진 패시브는 빠지고 뒷 노드가 열림")
	# Multipliers: constellation effects reach the simulator through the run's mods.
	Arena.talents["guard_hp"] = 1
	Arena.talents["star_quick"] = 1
	Arena.talents["star_more_blast"] = 1
	Arena._refresh_mods()
	Arena.sim.refresh_heroes()
	check(is_equal_approx(Arena.sim.crystal_max, Balance.ARENA_CRYSTAL_HP * 1.15), "수정 체력 노드가 최대치를 늘림")
	check(is_equal_approx(Arena.sim.skill_max_cooldown("blast"), Balance.ARENA_BLAST_COOLDOWN * 0.8) and Arena.sim.skill_max_uses("blast") == Balance.ARENA_BLAST_USES + 1, "별빛 노드가 쿨타임·횟수에 닿음")
	# Gold: summons only, and the price climbs with every paid ritual.
	Arena.talents.erase("fate_bond")
	Arena._refresh_mods()
	var cost0 := Arena.summon_cost()
	check(cost0 == Balance.ARENA_SUMMON_COST and Arena.summon_count == 1, "두 번째 의식(첫 유료)의 값은 밑값")
	Arena.summon_count = 4
	check(Arena.summon_cost() == Balance.ARENA_SUMMON_COST + Balance.ARENA_SUMMON_COST_STEP * 3, "유료 의식마다 값이 오름")
	Arena.talents["fate_bond"] = 1
	Arena._refresh_mods()
	check(Arena.summon_cost() == roundi((Balance.ARENA_SUMMON_COST + Balance.ARENA_SUMMON_COST_STEP * 3) * 0.85), "「인연」이 의식 값을 깎음")
	# Nothing left to pick: the level pays gold instead of blocking the battle.
	for node in Balance.TALENTS: Arena.talents[String(node["id"])] = int(node["max"])
	for passive in Balance.PASSIVES: Arena.owned_passives.append(String(passive["id"]))
	Arena.pending_levels = 1
	var gold := Arena.gold
	check(not Arena.offer_levelup() and Arena.pending_levels == 0 and Arena.gold == gold + Balance.ARENA_LEVELUP_GOLD and Arena.modal == "", "열린 노드가 없으면 레벨이 골드로 바뀜")


func _kill_boss(sim: ArenaSim) -> void:
	sim.jump_to_boss()
	_advance(sim, 0.1)
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()

## One stage of the ladder from its card to its result: the battlefield the ladder names, with its own
## roads, the free first box, the waves, the boss, the clear beat and the victory that unlocks the next
## stage — which starts again from nothing. A defeat changes no record and a retry replays the stage.
func _check_stage_run() -> void:
	_reset_ladder()
	Arena.start_run(811)
	check(Arena.stage == 1 and Arena.theme_index == Arena.ladder_theme(1) and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index), "STAGE 1 은 사다리의 전장과 그 전장의 길")
	var opened := 0
	for e in Arena.sim.events:
		if String(e.get("t", "")) == "arena_stage" and int(e.get("stage", 0)) == 1: opened += 1
	check(opened == 1, "스테이지의 전장도 새 전장 이벤트로 열림")
	check(Arena.sim.in_prep() and Arena.sim.wave_no == 1 and Arena.sim.waves_total() == Balance.ARENA_WAVES and is_equal_approx(Arena.sim.prep_left(), Balance.ARENA_PREP_FIRST), "카드 뒤의 판은 1웨이브의 첫 정비부터")
	Arena.start_run(812)
	check(Arena.confirm_stage() and Arena.modal == "box" and Arena.summon_count == 0, "카드 다음은 무료 첫 상자")
	Arena.confirm_summon()
	Arena.close_modal()
	var sim: ArenaSim = Arena.sim
	check(sim.stage == 1 and Arena.wave == 1 and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index), "전장마다 정해진 길 배치 사용")
	sim.crystal_hp = sim.crystal_max * 0.5
	var first_theme: int = Arena.theme_index
	var theme_id := String(Arena.theme_for(1)["id"])
	var clears: int = Save.clears
	_monster(sim, ArenaGeometry.route_points(0)[8])
	sim.events.clear()
	_kill_boss(sim)
	var cleared := false
	var scattered := 0
	for e in sim.events:
		if String(e.get("t", "")) == "arena_stage_clear" and int(e.get("stage", 0)) == 1 and bool(e.get("final", false)): cleared = true
		if String(e.get("t", "")) == "die" and bool(e.get("scatter", false)): scattered += 1
	check(cleared and scattered == 1 and sim.clear_t > 0.0, "보스 처치: 승리 연출(final)·남은 적 흩어짐")
	check(is_equal_approx(sim.crystal_hp, sim.crystal_max * (0.5 + Balance.ARENA_STAGE_HEAL)), "돌파 연출에 수정 일부 회복")
	check(not sim.cast_skill("blast") and String(sim.skill_state("blast")["block"]) == "clearing", "돌파 연출 중 기술 사용 차단")
	var during := Arena.snapshot()
	check(ArenaValidation.valid(during) and Arena.restore(during) and Arena.sim.clear_t > 0.0 and Arena.stage == 1, "돌파 연출 중 저장·복구")
	sim = Arena.sim
	var hp_after: float = sim.crystal_hp
	sim._damage_crystal(50.0, Balance.ARENA_CENTER)
	check(sim.crystal_hp == hp_after, "돌파 연출 중에는 수정이 피해를 받지 않음")
	_advance(sim, Balance.ARENA_CLEAR_DELAY + 0.2)
	check(not Arena.running and sim.won and Arena.modal == "result" and Arena.stage == 1, "연출 뒤 스테이지 승리")
	check(Save.stage_unlocked == 2 and Save.stage_cleared == 1 and Save.last_clear == {"stage": 1, "theme": theme_id} and Save.clears == clears + 1, "승리로 다음 스테이지 해금·직전 클리어·완료 횟수 기록")
	check(Arena.can_play(2) and not Arena.can_play(3), "열린 스테이지까지만 고를 수 있음")
	check(Arena.next_stage() and Arena.stage == 2 and Arena.modal == "stage" and Arena.running, "다음 스테이지 카드")
	check(Arena.theme_index == Arena.ladder_theme(2) and Arena.theme_index != first_theme and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index), "다음 스테이지는 사다리의 다른 전장과 그 전장의 길")
	check(Arena.heroes.is_empty() and Arena.summon_count == 0 and Arena.gold == Balance.START_GOLD and Arena.level == 0 and Arena.sim.wave_no == 1 and Arena.sim.in_prep() and Arena.sim.elapsed == 0.0, "스테이지마다 새로 시작 (영웅·골드·레벨·웨이브)")
	var staged := false
	for e in Arena.sim.events:
		if String(e.get("t", "")) == "arena_stage" and int(e.get("stage", 0)) == 2: staged = true
	check(staged, "새 전장 이벤트")
	var card := Arena.snapshot()
	var elapsed_time: float = Arena.sim.elapsed
	_advance(Arena.sim, 3.0)
	check(Arena.sim.elapsed == elapsed_time, "전장 카드가 열려 있는 동안 전투 정지")
	check(ArenaValidation.valid(card) and Arena.restore(card) and Arena.modal == "stage" and Arena.stage == 2, "전장 카드 중 저장·복구")
	check(Arena.sim.events.is_empty(), "이어 한 판은 전장을 다시 공개하지 않음")
	var chosen := card.duplicate(true)
	chosen["theme_index"] = (int(card["theme_index"]) + 1) % Roster.THEMES.size()
	check(ArenaValidation.valid(chosen), "도구가 고른 다른 전장도 유효한 저장")
	check(Arena.confirm_stage() and Arena.modal == "box" and Arena.summon_count == 0, "STAGE 2 도 무료 첫 상자부터")
	Arena.confirm_summon()
	Arena.close_modal()
	sim = Arena.sim
	sim.skip_prep()
	_advance(sim, 3.0)
	check(not sim.in_prep() and not sim.monsters.is_empty(), "STAGE 2 웨이브 진행·몬스터 출현")
	for mo in sim.monsters:
		if not ArenaGeometry.on_road(mo["pos"]): check(false, "STAGE 2 몬스터가 그 전장의 길 위에 있음")
	var mid := Arena.snapshot()
	ArenaGeometry.use_layout("coil:0:0")
	check(ArenaValidation.valid(mid) and ArenaGeometry.layout() == "coil:0:0", "저장 검사는 그 전장의 길로 보고 지금 배치를 건드리지 않음")
	check(Arena.restore(mid) and Arena.stage == 2 and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index) and Arena.sim.monsters == mid["sim"]["monsters"], "STAGE 2 웨이브 중 저장·복구가 길 배치까지 되돌림")
	var wrong := mid.duplicate(true)
	wrong["theme_index"] = Roster.THEMES.size()
	check(not ArenaValidation.valid(wrong), "없는 전장 저장 거부")
	wrong = mid.duplicate(true)
	wrong["stage"] = Balance.ARENA_LADDER + 1
	wrong["wave"] = wrong["stage"]
	check(not ArenaValidation.valid(wrong), "판과 sim 의 스테이지가 다른 저장 거부")
	# A ladder made shorter (a tuning value) leaves the run valid; restore puts it on the last stage.
	wrong["sim"]["stage"] = wrong["stage"]
	check(ArenaValidation.valid(wrong) and Arena.restore(wrong) and Arena.stage == Balance.ARENA_LADDER and Arena.sim.stage == Balance.ARENA_LADDER,
		"사다리 밖이 된 스테이지 저장은 받아 마지막 스테이지로 맞춤")
	check(Arena.restore(mid) and Arena.stage == 2, "판 되돌림")
	wrong = mid.duplicate(true)
	wrong["themes"] = []
	check(ArenaValidation.valid(mid) and ArenaValidation.valid(wrong), "전장 목록(themes)은 더는 저장의 일부가 아님")
	# A defeat changes no record; a retry replays the same stage from nothing.
	sim = Arena.sim
	sim.revives = Balance.ARENA_REVIVE_USES
	sim._damage_crystal(100000.0, Balance.ARENA_CENTER)
	check(not Arena.running and not sim.won and Save.stage_unlocked == 2 and Save.stage_cleared == 1, "패배는 해금·기록을 바꾸지 않음")
	check(not Arena.next_stage(), "깨지 않은 스테이지 다음은 열리지 않음")
	Arena.retry()
	check(Arena.running and Arena.stage == 2 and Arena.modal == "stage" and Arena.heroes.is_empty() and Arena.theme_index == Arena.ladder_theme(2), "재도전은 같은 스테이지를 처음부터")
	_reset_ladder()

## The ladder's curve: a gentle climb in health from stage to stage plus the climb inside a stage, the
## same economy at every stage (each starts from nothing), the kinds a wave may bring, and the values the
## spawned bodies really get.
func _check_ladder_strength() -> void:
	check(is_equal_approx(Balance.arena_hp(1, 1, 1), Balance.wave_hp(1, 1) * Balance.ARENA_HP_SCALE), "STAGE 1 의 1웨이브 체력은 예전 1탄 값")
	# The ladder's slope (2026-10-19 LA4): 1 up to STAGE ARENA_LADDER_HP_FROM, then (stage / FROM)^POW —
	# quick at first, gentler later.
	var top := pow(float(Balance.ARENA_LADDER) / Balance.ARENA_LADDER_HP_FROM, Balance.ARENA_LADDER_HP_POW)
	check(is_equal_approx(Balance.arena_hp(Balance.ARENA_LADDER, 1, 1) / Balance.arena_hp(1, 1, 1), top) and is_equal_approx(Balance.arena_ladder_hp(1), 1.0)
		and is_equal_approx(Balance.arena_ladder_hp(floori(Balance.ARENA_LADDER_HP_FROM)), 1.0), "사다리 경사 = (STAGE / %.0f)^%.2f, 그 앞은 1 (100 → %.2f배)" % [Balance.ARENA_LADDER_HP_FROM, Balance.ARENA_LADDER_HP_POW, top])
	check(Balance.arena_ladder_hp(50) > Balance.arena_ladder_hp(25) and Balance.arena_ladder_hp(50) - Balance.arena_ladder_hp(25) > Balance.arena_ladder_hp(100) - Balance.arena_ladder_hp(75),
		"사다리 경사는 오르되 뒤로 갈수록 완만")
	check(Balance.arena_hp(1, 1, 10) > Balance.arena_hp(1, 1, 9) and is_equal_approx(Balance.arena_hp(1, 1, 10) / Balance.arena_hp(1, 1, 1), 1.0 + 9.0 * Balance.ARENA_WAVE_HP_STEP), "웨이브마다 체력이 오름")
	Arena.start_run(813, 1)
	var first := _stage_economy(1)
	var last := _stage_economy(Balance.ARENA_LADDER)
	check(absf(last.x / first.x - 1.0) <= 0.2 and absf(last.y / first.y - 1.0) <= 0.2, "한 스테이지의 골드·경험치는 사다리 끝까지 비슷 (골드 %.0f→%.0f · 경험치 %.0f→%.0f)" % [first.x, last.x, first.y, last.y])
	var kinds_first := {}
	for entry in Arena.wave_spawns(1, 1): kinds_first[String(entry["m"]["kind"])] = true
	check(kinds_first.keys() == ["swarm"], "STAGE 1 의 1웨이브는 떼거리만")
	var flyers := 0
	var immune := 0
	var heavy_early := 0
	for stage in [1, 2, 3]:
		for w in range(1, Balance.ARENA_WAVES + 1):
			for entry in Arena.wave_spawns(stage, w):
				var monster: Dictionary = entry["m"]
				if stage == 1 and Balance.flies(monster): flyers += 1
				if not Balance.body_immune(String(monster["body"])).is_empty(): immune += 1
				if w < Balance.ARENA_HEAVY_WAVE and String(monster["kind"]) in ["tank", "caster"]: heavy_early += 1
	check(flyers == 0, "STAGE 1 에는 공중 몬스터가 없음")
	check(immune == 0, "STAGE 1~3 에는 면역 몸이 없음")
	check(heavy_early == 0, "육중·주술은 %d웨이브부터" % Balance.ARENA_HEAVY_WAVE)
	var late := {}
	for entry in Arena.wave_spawns(60, Balance.ARENA_WAVES - 1): late[String(entry["m"]["id"])] = true
	check(late.size() >= 3, "늦은 스테이지의 늦은 웨이브는 여러 종이 섞임 (%d종)" % late.size())
	# The bodies the simulator spawns carry those values.
	var sim := _battle(814)
	sim.heroes[0]["cool"] = 100000.0
	sim.monsters.clear()
	sim.begin_wave(Balance.ARENA_ELITE_EVERY)
	var guard := 0
	while sim._wave_spawned < sim.wave_size() and guard < 2400:
		guard += 1
		sim.step(1.0 / 60.0)
	var rank: int = Arena.theme_rank(1)
	var elites := 0
	var plain := true
	for mo in sim.monsters:
		var kind := String(mo["kind"])
		if bool(mo["elite"]):
			elites += 1
			check(is_equal_approx(float(mo["max"]), Balance.arena_elite_hp(1, rank, Balance.ARENA_ELITE_EVERY, kind)) and int(mo["gold"]) == roundi(Balance.arena_ladder_gold(1, kind) * Balance.ARENA_ELITE_GOLD) and kind == "tank" and not bool(mo["fly"]), "정예는 땅 위 육중형이고 체력·골드 배수를 지님")
		elif not is_equal_approx(float(mo["max"]), Balance.arena_hp(1, rank, Balance.ARENA_ELITE_EVERY) * float(Balance.MKIND[kind]["hp"])) or int(mo["gold"]) != Balance.arena_ladder_gold(1, kind):
			plain = false
	check(elites == 1 and plain, "%d웨이브: 정예 1 · 일반 몸은 그 웨이브의 체력과 사다리 골드" % Balance.ARENA_ELITE_EVERY)
	sim.monsters.clear()
	sim.jump_to_boss()
	_advance(sim, 0.1)
	var boss: Dictionary = {}
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": boss = mo
	check(not boss.is_empty() and is_equal_approx(float(boss["max"]), Balance.arena_ladder_boss_hp(1, rank, Balance.ARENA_WAVES, false)), "보스 체력은 10웨이브 체력 x 보스 배수 x ARENA_LADDER_BOSS_HP")
	check(Arena.chapter_stage(10) and not Arena.chapter_stage(9) and is_equal_approx(Balance.arena_ladder_boss_hp(10, 1, 10, true), Balance.arena_ladder_boss_hp(10, 1, 10) * Balance.ARENA_FINAL_BOSS_HP), "챕터 보스(10의 배수)는 최종 보스 배수")
	Arena.running = false

## Gold and experience one stage hands out before its boss wave: the kills of waves 1~9 (elite included)
## and the defence bonuses.
func _stage_economy(stage: int) -> Vector2:
	var gold := 0.0
	var xp := 0.0
	for w in range(1, Balance.ARENA_WAVES):
		gold += Balance.arena_wave_bonus(stage, w)
		for entry in Arena.wave_spawns(stage, w):
			var kind := String(entry["m"]["kind"])
			var elite := bool(entry["elite"])
			gold += Balance.arena_ladder_gold(stage, kind) * (Balance.ARENA_ELITE_GOLD if elite else 1.0)
			xp += Balance.arena_ladder_xp(stage, kind) * (Balance.ARENA_ELITE_XP if elite else 1.0)
	return Vector2(gold, xp)
