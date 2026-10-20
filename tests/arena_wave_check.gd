extends Harness

## The stage ladder fought in waves (2026-10-19, docs/STAGE_LADDER_2026-10-19.md):
##   - a wave spawns its list and ends when all of it is down; a preparation phase follows in which
##     nothing spawns, summons and level-up picks open only then, and 「바로 시작」 ends it;
##   - wave 5 brings an elite, the last wave the boss (announced in the last preparation) and its escort;
##   - bosses and elites walk through guardians, a walker sealed for ARENA_BLOCK_BREAK seconds too (F4);
##   - saves made in a preparation or mid-wave continue exactly;
##   - the ladder's order, the unlock on a clear, retry and next stage;
##   - endless waves (Hellbound) have no last wave.
## Guardians hold their fire and kills are staged by hand, so the whole check takes seconds.
##
##   godot --headless --path . res://tests/arena_wave_check.tscn
const DT := 1.0 / 60.0

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_wave_flow()
	_check_elite_and_boss()
	_check_prep_gates()
	_check_passage()
	_check_wave_saves()
	_check_ladder()
	_check_endless()
	_check_pace()
	_reset_ladder()
	Arena.running = false
	finish("웨이브·정비·정예·사다리")

func _reset_ladder() -> void:
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	Save.last_clear = {}

## A stage at its first preparation, past the card and the free first summon, its guardian holding fire.
func _stage(seed_value: int, stage: int = 1) -> ArenaSim:
	Arena.start_run(seed_value, stage)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	var sim: ArenaSim = Arena.sim
	_hold_fire(sim)
	return sim

func _hold_fire(sim: ArenaSim) -> void:
	for hero in sim.heroes: hero["cool"] = 1.0e9

func _advance(sim: ArenaSim, seconds: float, auto_pick: bool = true) -> void:
	for i in range(roundi(seconds * 60)):
		if auto_pick and Arena.modal == "talent" and not Arena.talent_offer.is_empty():
			Arena.pick_talent(String(Arena.talent_offer[0]))
		sim.step(DT)

func _events(sim: ArenaSim, type: String) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool: return String(e.get("t", "")) == type)

## Everything on the field goes down through the simulator's own reaping (gold, experience, the wave's end).
func _kill_all(sim: ArenaSim) -> void:
	for mo in sim.monsters: mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()

## The rest of the current wave's list spawns; the bodies are held at their gates.
func _spawn_rest(sim: ArenaSim, auto_pick: bool = true) -> void:
	var guard := 0
	while (sim.in_prep() or sim._wave_spawned < sim.wave_size()) and guard < 6000:
		guard += 1
		if auto_pick and Arena.modal == "talent" and not Arena.talent_offer.is_empty():
			Arena.pick_talent(String(Arena.talent_offer[0]))
		sim.step(DT)
		for mo in sim.monsters: mo["spd"] = 0.0

func _check_wave_flow() -> void:
	var sim := _stage(31001)
	check(sim.wave_no == 1 and sim.in_prep() and is_equal_approx(sim.prep_left(), Balance.ARENA_PREP_FIRST) and is_equal_approx(sim.prep_total(), Balance.ARENA_PREP_FIRST) and sim.waves_total() == Balance.ARENA_WAVES,
		"스테이지는 1웨이브 앞의 첫 정비(%.0f초)부터" % Balance.ARENA_PREP_FIRST)
	check(sim.wave_size() == Balance.arena_wave_count(1, 1) and sim.wave_size() == Arena.wave_spawns(1, 1).size() and sim.wave_left() == sim.wave_size(), "정비 중에도 다음 웨이브의 목록과 수를 앎")
	sim.events.clear()
	var serial: int = sim._serial
	_advance(sim, Balance.ARENA_PREP_FIRST - 0.1)
	check(sim.in_prep() and sim._serial == serial and _events(sim, "spawn").is_empty(), "정비 시간에는 아무것도 나오지 않음")
	_advance(sim, 0.2)
	var opened := _events(sim, "arena_wave")
	check(not sim.in_prep() and opened.size() == 1 and int(opened[0]["wave"]) == 1 and int(opened[0]["total"]) == Balance.ARENA_WAVES and not bool(opened[0]["elite"]) and not bool(opened[0]["boss"]),
		"정비가 끝나면 1웨이브 시작 이벤트")
	var times: Array[float] = []
	var guard := 0
	while sim._wave_spawned < sim.wave_size() and guard < 2400:
		guard += 1
		var before: int = sim._serial
		sim.step(DT)
		if sim._serial != before: times.append(sim.wave_t)
		for mo in sim.monsters: mo["spd"] = 0.0
	var same := sim.monsters.size() == sim.wave_size()
	for i in range(mini(sim.monsters.size(), sim.wave_size())):
		if String(sim.monsters[i]["m"]["id"]) != String(sim._wave_list[i]["m"]["id"]): same = false
	check(same, "1웨이브는 목록 그대로, 그 차례로 %d마리" % sim.wave_size())
	var even := times.size() == sim.wave_size() - 1
	for i in range(1, times.size()):
		if absf(times[i] - times[i - 1] - Balance.arena_wave_gap(1, 1)) > 1.5 / 60.0: even = false
	check(even, "한 마리씩 %.2f초 간격" % Balance.arena_wave_gap(1, 1))
	var spawned: int = sim._serial
	_advance(sim, 3.0)
	check(sim._serial == spawned and not sim.in_prep() and sim.wave_left() == sim.monsters.size(), "목록이 끝나면 더 나오지 않고 남은 수는 살아 있는 몸")
	sim.crystal_hp = sim.crystal_max * 0.5
	var gold: int = Arena.gold
	var bounty := 0
	for mo in sim.monsters: bounty += roundi(float(mo["gold"]) * Balance.gold_mult(Arena.lv("gold")) * Arena.pas_mult("gold"))
	sim.events.clear()
	_kill_all(sim)
	var held := _events(sim, "arena_wave_clear")
	check(held.size() == 1 and int(held[0]["wave"]) == 1 and int(held[0]["gold"]) == Balance.arena_wave_bonus(1, 1) and is_equal_approx(float(held[0]["prep"]), Balance.ARENA_PREP_SEC),
		"방어 성공 이벤트 (웨이브 · 골드 · 정비 시간)")
	check(Arena.gold == gold + bounty + Balance.arena_wave_bonus(1, 1), "처치 골드와 방어 성공 골드 지급")
	check(is_equal_approx(sim.crystal_hp, sim.crystal_max * (0.5 + Balance.ARENA_WAVE_HEAL)) and held.size() == 1 and is_equal_approx(float(held[0]["heal"]), sim.crystal_max * Balance.ARENA_WAVE_HEAL),
		"방어 성공 때 수정 %.0f%% 회복" % (Balance.ARENA_WAVE_HEAL * 100.0))
	check(sim.wave_no == 2 and sim.in_prep() and is_equal_approx(sim.prep_left(), Balance.ARENA_PREP_SEC) and is_equal_approx(sim.prep_total(), Balance.ARENA_PREP_SEC), "다음 웨이브의 정비(%.0f초)" % Balance.ARENA_PREP_SEC)
	var autosaved: Dictionary = Save.cur_run.get("sim", {})
	check(int(autosaved.get("wave_no", 0)) == 2 and bool(autosaved.get("in_prep", false)) and int(Save.cur_run.get("gold", -1)) == Arena.gold, "웨이브 끝에 바로 자동 저장 (정비 상태)")

func _check_elite_and_boss() -> void:
	var sim := _stage(31002)
	var w := Balance.ARENA_ELITE_EVERY
	sim.begin_wave(w)
	var marked := sim._wave_list.filter(func(e: Dictionary) -> bool: return bool(e["elite"]))
	check(marked.size() == 1 and sim.wave_size() == Balance.arena_wave_count(1, w) and sim.is_elite_wave(w) and not sim.is_elite_wave(w - 1) and not sim.is_boss_wave(w), "%d웨이브에 정예 하나" % w)
	var row: Dictionary = marked[0]["m"] if not marked.is_empty() else {}
	check(String(row.get("kind", "")) == "tank" and String(row.get("body", "")) == String(Arena.theme_for(1)["main_body"]) and not Balance.flies(row), "정예는 그 전장 주 속성의 육중형 (땅 위)")
	sim.events.clear()
	_spawn_rest(sim)
	var elite: Dictionary = {}
	for mo in sim.monsters:
		if bool(mo["elite"]): elite = mo
	var shown := _events(sim, "arena_elite")
	check(not elite.is_empty() and shown.size() == 1 and int(shown[0]["sid"]) == int(elite["spawn_id"]), "정예 등장 이벤트가 그 몸을 가리킴")
	var rank: int = Arena.theme_rank(1)
	check(not elite.is_empty() and is_equal_approx(float(elite["max"]), Balance.arena_elite_hp(1, rank, w, "tank")) and int(elite["gold"]) == roundi(Balance.arena_ladder_gold(1, "tank") * Balance.ARENA_ELITE_GOLD),
		"정예 체력 x%.1f · 골드 x%.0f" % [Balance.ARENA_ELITE_HP, Balance.ARENA_ELITE_GOLD])
	Arena.level = 1000
	Arena.xp = 0.0
	if not elite.is_empty(): elite["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	check(is_equal_approx(Arena.xp, Balance.arena_ladder_xp(1, "tank") * Balance.ARENA_ELITE_XP * Arena.mod("xp")), "정예 처치 경험치 x%.0f" % Balance.ARENA_ELITE_XP)
	# The boss wave: announced in its preparation, the boss first at the named gate, then the escort.
	sim = _stage(31003)
	sim.begin_wave(Balance.ARENA_WAVES - 1)
	sim._wave_spawned = sim.wave_size()
	sim.monsters.clear()
	_advance(sim, DT * 2.0)
	check(sim.in_prep() and sim.wave_no == Balance.ARENA_WAVES and sim.is_boss_wave(sim.wave_no) and not sim.boss_warned, "9웨이브를 막으면 보스 웨이브의 정비")
	check(is_equal_approx(sim.prep_total(), Balance.ARENA_PREP_BOSS) and sim.prep_left() > Balance.ARENA_BOSS_WARNING and Balance.ARENA_PREP_BOSS > Balance.ARENA_BOSS_WARNING,
		"보스 앞 정비는 %.0f초(예고 %.0f초보다 김)" % [Balance.ARENA_PREP_BOSS, Balance.ARENA_BOSS_WARNING])
	sim.events.clear()
	_advance(sim, sim.prep_left() - Balance.ARENA_BOSS_WARNING + 0.05)
	var warned := _events(sim, "arena_boss_warning")
	check(warned.size() == 1 and float(warned[0]["sec"]) <= Balance.ARENA_BOSS_WARNING + 0.001 and bool(warned[0]["final"]) == Arena.chapter_stage(1) and sim.boss_lane >= 0 and sim.in_prep(),
		"마지막 정비에 보스 예고 1회 (최종 표시 = 챕터 보스)")
	var lane: int = sim.boss_lane
	var mid := Arena.snapshot()
	check(ArenaValidation.valid(mid) and Arena.restore(mid) and Arena.sim.boss_lane == lane and Arena.sim.boss_warned and Arena.sim.in_prep(), "예고 중 저장·복구에도 입구 유지")
	sim = Arena.sim
	sim.events.clear()
	_spawn_rest(sim)
	var boss: Dictionary = {}
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": boss = mo
	var arrived := _events(sim, "arena_boss")
	var wave_events := _events(sim, "arena_wave")
	check(wave_events.size() == 1 and bool(wave_events[0]["boss"]) and arrived.size() == 1 and not boss.is_empty() and int(boss["route"]) == lane and String(sim._wave_list[0]["m"]["kind"]) == "boss",
		"보스 웨이브: 보스가 맨 앞, 예고한 입구로")
	check(sim.monsters.size() == 1 + Balance.ARENA_BOSS_ESCORT and not boss.is_empty() and is_equal_approx(float(boss["max"]), Balance.arena_ladder_boss_hp(1, Arena.theme_rank(1), Balance.ARENA_WAVES, false)),
		"보스 + 호위 %d · 보스 체력" % Balance.ARENA_BOSS_ESCORT)
	var unlocked: int = Save.stage_unlocked
	sim.events.clear()
	if not boss.is_empty(): boss["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	var beat := _events(sim, "arena_stage_clear")
	check(beat.size() == 1 and bool(beat[0]["final"]) and sim.clear_t > 0.0 and sim.monsters.is_empty() and _events(sim, "arena_wave_clear").is_empty(), "보스 처치: 승리 연출(final) · 호위는 흩어짐 · 방어 성공은 아님")
	_advance(sim, Balance.ARENA_CLEAR_DELAY + 0.2)
	check(sim.won and not Arena.running and Arena.modal == "result" and Save.stage_unlocked == maxi(unlocked, 2), "연출 뒤 스테이지 승리 · 다음 스테이지 해금")
	_reset_ladder()

func _check_prep_gates() -> void:
	var sim := _stage(31004)
	Arena.gold = 1000
	check(sim.in_prep() and Arena.summon_block() == "" and Arena.can_summon(), "정비 중에는 상자를 열 수 있음")
	var cost: int = Arena.summon_cost()
	check(Arena.begin_summon() and Arena.modal == "box" and Arena.gold == 1000 - cost, "정비 중 유료 상자")
	Arena.confirm_summon()
	Arena.close_modal()
	_hold_fire(sim)
	check(sim.skip_prep(), "「바로 시작」")
	_advance(sim, 0.1)
	check(not sim.in_prep() and Arena.summon_block() == "wave" and not Arena.can_summon(), "웨이브 중에는 상자가 막힘 (이유: wave)")
	var gold: int = Arena.gold
	check(not Arena.begin_summon() and Arena.gold == gold and Arena.modal == "", "웨이브 중 상자 시도는 골드를 쓰지 않음")
	Arena.begin_draw()
	check(Arena.modal == "", "웨이브 중에는 의식 창도 열리지 않음")
	var gained: int = Arena.gain_xp(float(Arena.xp_needed()) + 0.5)
	check(gained == 1 and Arena.pending_levels == 1 and not Arena.offer_levelup() and Arena.modal == "", "웨이브 중 오른 레벨은 쌓이고 팝업은 열리지 않음")
	_advance(sim, 0.5, false)
	check(Arena.modal == "" and Arena.pending_levels == 1, "웨이브 중에는 몇 걸음 뒤에도 팝업이 열리지 않음")
	_spawn_rest(sim, false)
	_kill_all(sim)
	check(sim.in_prep() and Arena.modal == "talent" and not Arena.talent_offer.is_empty(), "방어 성공으로 정비가 시작되자 쌓인 레벨업 팝업이 열림")
	var left := sim.prep_left()
	_advance(sim, 2.0, false)
	check(sim.prep_left() == left, "팝업을 고르는 동안 정비 시계는 멈춤")
	Arena.pick_talent(String(Arena.talent_offer[0]))
	while Arena.modal == "talent" and not Arena.talent_offer.is_empty(): Arena.pick_talent(String(Arena.talent_offer[0]))
	check(Arena.modal == "" and Arena.pending_levels == 0 and sim.in_prep(), "고르면 정비로 돌아옴")
	check(Arena.open_modal("talent") and Arena.close_modal(), "별자리 열람은 언제든 열고 닫힘")
	# Before the boss wave 「바로 시작」 keeps the warning.
	sim.begin_wave(Balance.ARENA_WAVES - 1)
	sim._wave_spawned = sim.wave_size()
	sim.monsters.clear()
	_advance(sim, DT * 2.0)
	check(sim.in_prep() and sim.is_boss_wave(sim.wave_no) and sim.skip_prep() and is_equal_approx(sim.prep_left(), Balance.ARENA_BOSS_WARNING) and not sim.boss_warned, "보스 앞의 「바로 시작」은 예고 시간만 남김")
	sim.events.clear()
	_advance(sim, 0.1)
	check(_events(sim, "arena_boss_warning").size() == 1 and sim.in_prep(), "그 뒤 예고가 나옴")
	check(sim.skip_prep() and sim.prep_left() == 0.0, "예고 뒤의 「바로 시작」은 곧바로")
	_advance(sim, DT * 2.0)
	check(sim.boss_spawned and not sim.in_prep() and not sim.skip_prep(), "보스 등장 · 웨이브 중에는 「바로 시작」 없음")
	Arena.running = false

## Walk one body from `from` toward the crystal through the current guardians, measuring how it went.
func _walk(sim: ArenaSim, row: Dictionary, from: Vector2, elite: bool) -> Dictionary:
	sim.monsters.clear()
	sim._forced_lane = 0
	sim._spawn(row)
	sim._forced_lane = -1
	var mo: Dictionary = sim.monsters[-1]
	if elite: sim._make_elite(mo)
	mo["pos"] = from
	mo["hp"] = 1.0e9
	mo["max"] = 1.0e9
	sim._cache_positions()
	var budget := int(ArenaGeometry.route_length(0) / (Balance.PATH_SPEED * float(mo["spd"])) * 60.0 * 1.5) + 600
	var blocked := 0
	var strayed := 0
	var arrived := false
	for i in range(budget):
		sim._move_monsters(DT)
		if bool(mo["blocked"]): blocked += 1
		if not ArenaGeometry.on_road(mo["pos"], Balance.ARENA_MONSTER_RADIUS): strayed += 1
		if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 2.0:
			arrived = true
			break
	return {"arrived": arrived, "blocked": blocked, "strayed": strayed, "mo": mo}

func _guard_at(points: Array) -> void:
	for i in range(Arena.heroes.size()):
		Arena.heroes[i]["position"] = points[i] if i < points.size() else Balance.ARENA_CENTER + Vector2.from_angle(i) * (Balance.ALTAR_R + 60.0)
	Arena.sim.refresh_heroes()
	Arena.sim._rebuild_navigation()

## F4 · M5: bosses and elites pass a sealed road like flyers over it and still keep to the road; a walker
## waits at the seal and, past ARENA_BLOCK_BREAK seconds of standing blocked, passes too.
func _check_passage() -> void:
	var sim := _stage(31005)
	for unit in Roster.UNITS:
		if Arena.heroes.size() >= Balance.ARENA_HERO_LIMIT: break
		if String(unit["id"]) != String(Arena.heroes[0]["unit"]["id"]): Arena.gain_hero(unit, 1)
	_hold_fire(sim)
	var road := ArenaGeometry.route_points(0)
	var trap: Vector2 = road[12]
	var ring: Array = []
	for i in range(Balance.ARENA_HERO_LIMIT):
		ring.append(trap + Vector2.from_angle(i * TAU / 6.0) * (Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS) * 1.5)
	_guard_at(ring)
	var boss := _walk(sim, Arena.boss_for(1), road[0], false)
	check(boss["arrived"] and int(boss["blocked"]) == 0 and int(boss["strayed"]) == 0, "보스는 6인 봉쇄를 지나 도로만 따라 수정에 닿음 (막힘 %d · 이탈 %d)" % [boss["blocked"], boss["strayed"]])
	var tank := _walk(sim, _main_tank(), road[0], true)
	check(tank["arrived"] and int(tank["blocked"]) == 0 and int(tank["strayed"]) == 0 and bool(tank["mo"]["elite"]) and not bool(tank["mo"]["fly"]), "정예도 6인 봉쇄를 지나 수정에 닿음 (땅 위 목표 그대로)")
	# Two guardians abreast seal the road: the walker waits, the boss walks on.
	var at: int = mini(30, road.size() - 2)
	var normal := (road[at + 1] - road[at]).normalized().orthogonal()
	_guard_at([road[at] + normal * 28.0, road[at] - normal * 28.0])
	var walker := _walk_for(sim, Arena.spawns_for(1)[0], road[0], Balance.ARENA_BLOCK_BREAK - 1.0)
	check(bool(walker["blocked"]) and float(walker["block_t"]) > 0.0 and float(walker["block_t"]) < Balance.ARENA_BLOCK_BREAK, "둘이 나란히 막은 길에서 떼거리는 기다림")
	var through := _walk(sim, Arena.boss_for(1), road[0], false)
	check(through["arrived"] and int(through["blocked"]) == 0, "같은 봉쇄를 보스는 지나감")
	# The deadlock break: a walker sealed inside the ring passes after ARENA_BLOCK_BREAK seconds.
	_guard_at(ring)
	sim.monsters.clear()
	sim._spawn(Arena.spawns_for(1)[0])
	var mo: Dictionary = sim.monsters[-1]
	mo["pos"] = trap
	mo["hp"] = 1.0e9
	mo["max"] = 1.0e9
	sim._cache_positions()
	for i in range(roundi(Balance.ARENA_BLOCK_BREAK * 0.5 * 60.0)): sim._move_monsters(DT)
	check(bool(mo["blocked"]) and Vector2(mo["pos"]).distance_to(trap) < 24.0 and float(mo["block_t"]) > Balance.ARENA_BLOCK_BREAK * 0.4, "떼거리는 6인 봉쇄 안에서 기다림 (%.1f초)" % float(mo["block_t"]))
	var saved := Arena.snapshot()
	check(ArenaValidation.valid(saved) and Arena.restore(saved), "막힌 채 저장·복구")
	sim = Arena.sim
	mo = sim.monsters[-1]
	check(absf(float(mo["block_t"]) - float(saved["sim"]["monsters"][-1]["block_t"])) < 0.0001, "막힌 시간이 저장에 남음")
	var held := Vector2(mo["pos"])
	for i in range(roundi(Balance.ARENA_BLOCK_BREAK * 0.4 * 60.0)): sim._move_monsters(DT)
	check(Vector2(mo["pos"]) == held and float(mo["block_t"]) < Balance.ARENA_BLOCK_BREAK, "%.0f초 전에는 여전히 기다림" % Balance.ARENA_BLOCK_BREAK)
	var broke := false
	var strayed := 0
	var arrived := false
	for i in range(roundi(Balance.ARENA_BLOCK_BREAK * 60.0) + 3600):
		sim._move_monsters(DT)
		if float(mo["block_t"]) >= Balance.ARENA_BLOCK_BREAK: broke = true
		if not ArenaGeometry.on_road(mo["pos"], Balance.ARENA_MONSTER_RADIUS): strayed += 1
		if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 2.0:
			arrived = true
			break
	check(broke and arrived and strayed == 0, "%.0f초 넘게 막힌 몸은 넘어가 도로를 따라 수정에 닿음 (교착 방지)" % Balance.ARENA_BLOCK_BREAK)
	var bad := Arena.snapshot()
	bad["sim"]["monsters"][-1]["block_t"] = -1.0
	check(not ArenaValidation.valid(bad), "음수 막힘 시간 저장 거부")
	bad = Arena.snapshot()
	bad["sim"]["monsters"][-1]["elite"] = 1
	check(not ArenaValidation.valid(bad), "정예 표식이 참/거짓이 아닌 저장 거부")
	Arena.running = false

func _walk_for(sim: ArenaSim, row: Dictionary, from: Vector2, seconds: float) -> Dictionary:
	sim.monsters.clear()
	sim._forced_lane = 0
	sim._spawn(row)
	sim._forced_lane = -1
	var mo: Dictionary = sim.monsters[-1]
	mo["pos"] = from
	mo["hp"] = 1.0e9
	mo["max"] = 1.0e9
	sim._cache_positions()
	for i in range(roundi(seconds * 60.0)): sim._move_monsters(DT)
	return mo

func _main_tank() -> Dictionary:
	for monster in Roster.monsters_of_body(String(Arena.theme_for(1)["main_body"])):
		if String(monster["kind"]) == "tank": return monster
	return Roster.monster_by_id("wave_giant")

func _branch(state: Dictionary, seconds: float) -> Dictionary:
	Arena.restore(state)
	_advance(Arena.sim, seconds)
	return Arena.snapshot()

func _check_wave_saves() -> void:
	var sim := _stage(31006)
	_advance(sim, 3.0)
	var prep := Arena.snapshot()
	check(ArenaValidation.valid(prep) and bool(prep["sim"]["in_prep"]) and int(prep["sim"]["wave_spawned"]) == 0, "정비 중 저장")
	check(Arena.restore(prep) and Arena.sim.in_prep() and Arena.sim.wave_no == 1 and is_equal_approx(Arena.sim.prep_t, float(prep["sim"]["prep_t"])) and Arena.sim._wave_list == sim._wave_list,
		"정비 중 복구: 웨이브 · 정비 시계 · 다음 목록이 같음")
	check(_branch(prep, 6.0) == _branch(prep, 6.0), "정비 중 저장에서 두 번 이어 해도 같은 결과")
	Arena.restore(prep)
	sim = Arena.sim
	sim.skip_prep()
	# Into the wave, a gap and a half: part of its list is out (the spawn gap is a tuning value).
	_advance(sim, Balance.arena_wave_gap(Arena.stage, 1) * 1.5 + DT * 3.0)
	var mid := Arena.snapshot()
	var spawned := int(mid["sim"]["wave_spawned"])
	check(not bool(mid["sim"]["in_prep"]) and spawned > 0 and spawned < sim.wave_size(), "웨이브 중 저장 (%d/%d 출현)" % [spawned, sim.wave_size()])
	check(Arena.restore(mid) and Arena.sim._wave_spawned == spawned and Arena.sim._wave_list.slice(spawned) == sim._wave_list.slice(spawned) and Arena.sim.monsters == mid["sim"]["monsters"],
		"웨이브 중 복구: 남은 목록 · 몬스터가 같음")
	check(_branch(mid, 4.0) == _branch(mid, 4.0), "웨이브 중 저장에서 두 번 이어 해도 같은 결과")
	var listed := Balance.arena_wave_count(1, 1)
	for case in [["wave_no", 0], ["wave_spawned", -1], ["prep_t", -1.0], ["prep_t", ArenaValidation.PREP_CAP + 1.0], ["in_prep", 1], ["wave_t", -1.0]]:
		var bad := mid.duplicate(true)
		bad["sim"][case[0]] = case[1]
		check(not ArenaValidation.valid(bad), "잘못된 웨이브 저장 거부: %s = %s" % [case[0], str(case[1])])
	# Past limits that tuning values set (the last wave, the wave's list): valid, and fitted on restore.
	var later := mid.duplicate(true)
	later["sim"]["wave_no"] = Balance.ARENA_WAVES + 1
	later["sim"]["wave_spawned"] = listed + 5
	check(ArenaValidation.valid(later) and Arena.restore(later) and Arena.sim.wave_no == Balance.ARENA_WAVES and Arena.sim._wave_spawned <= Arena.sim.wave_size(),
		"마지막 웨이브 · 목록을 넘는 저장은 받아 지금의 상한으로 맞춤")
	check(Arena.restore(mid), "웨이브 중 저장으로 되돌림")
	var missing := mid.duplicate(true)
	missing["sim"].erase("wave_no")
	check(not ArenaValidation.valid(missing), "웨이브 번호가 빠진 저장 거부")
	var early := prep.duplicate(true)
	early["sim"]["wave_spawned"] = 1
	check(not ArenaValidation.valid(early), "정비 중인데 이미 나온 몸이 있는 저장 거부")
	var old := mid.duplicate(true)
	old["v"] = 4
	check(ArenaValidation.outdated(old) and not ArenaValidation.valid(old) and not Arena.restore(old), "판 4 저장은 이어 하지 않음")
	Arena.running = false

func _win_stage() -> void:
	if Arena.modal == "stage": Arena.confirm_stage()
	if Arena.modal == "box":
		Arena.confirm_summon()
		Arena.close_modal()
	var sim: ArenaSim = Arena.sim
	sim.jump_to_boss()
	_advance(sim, 0.1)
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	_advance(sim, Balance.ARENA_CLEAR_DELAY + 0.2)

func _lose_stage() -> void:
	if Arena.modal == "stage": Arena.confirm_stage()
	if Arena.modal == "box":
		Arena.confirm_summon()
		Arena.close_modal()
	Arena.sim.revives = Balance.ARENA_REVIVE_USES
	Arena.sim._damage_crystal(1.0e6, Balance.ARENA_CENTER)

func _check_ladder() -> void:
	_reset_ladder()
	var ladder: Array[int] = []
	for n in range(1, Balance.ARENA_LADDER + 1): ladder.append(Arena.ladder_theme(n))
	check(ladder.size() == Balance.ARENA_LADDER and ladder == Arena.build_ladder(), "사다리 순서는 고정 씨앗으로 언제나 같음")
	var chapters_ok := true
	var ranks_ok := true
	for c in range(ceili(float(Balance.ARENA_LADDER) / Arena.CHAPTER)):
		var rank: int = Arena.chapter_rank(c * Arena.CHAPTER + 1)
		var want := {}
		for index in range(Roster.THEMES.size()):
			if int(Roster.THEMES[index].get("rank", 1)) == rank: want[index] = true
		var seen := {}
		for n in range(c * Arena.CHAPTER, mini((c + 1) * Arena.CHAPTER, Balance.ARENA_LADDER)):
			seen[ladder[n]] = true
			if int(Roster.THEMES[ladder[n]].get("rank", 1)) != rank: ranks_ok = false
		if seen.size() != want.size() or seen.size() != Arena.CHAPTER: chapters_ok = false
		for index in want:
			if not seen.has(index): chapters_ok = false
	check(chapters_ok and ranks_ok, "챕터마다 그 험지 등급의 전장 %d곳을 한 번씩" % Arena.CHAPTER)
	var repeats := 0
	var climbing := true
	for n in range(1, ladder.size()):
		if String(Roster.THEMES[ladder[n]]["main_body"]) == String(Roster.THEMES[ladder[n - 1]]["main_body"]): repeats += 1
		if int(Roster.THEMES[ladder[n]].get("rank", 1)) < int(Roster.THEMES[ladder[n - 1]].get("rank", 1)): climbing = false
	check(repeats == 0, "같은 생태가 연달아 나오지 않음 (챕터 경계 포함)")
	check(climbing and Arena.chapter_rank(1) == 1 and Arena.chapter_rank(21) == 2 and Arena.chapter_rank(Balance.ARENA_LADDER) == 5 and Arena.chapter_of(10) == 1 and Arena.chapter_of(11) == 2, "험지 등급은 두 챕터마다 하나씩 오름")
	var early_immune := 0
	for n in range(Balance.ARENA_IMMUNE_STAGE - 1):
		if not Balance.body_immune(String(Roster.THEMES[ladder[n]]["main_body"])).is_empty(): early_immune += 1
	check(early_immune == 0, "STAGE 1~%d 에는 면역 생태의 전장이 없음" % (Balance.ARENA_IMMUNE_STAGE - 1))
	# The unlock, retry and the next stage.
	Arena.start_run(32001)
	check(Arena.stage == 1 and Arena.theme_index == ladder[0] and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(ladder[0]), "다음 해금 스테이지(STAGE 1)부터 그 전장의 길로 시작")
	check(Arena.can_play(1) and not Arena.can_play(2) and not Arena.can_play(0) and Arena.ladder_size() == Balance.ARENA_LADDER, "열린 스테이지까지만 고를 수 있음")
	_win_stage()
	var theme_id := String(Roster.THEMES[ladder[0]]["id"])
	check(not Arena.running and Save.stage_unlocked == 2 and Save.stage_cleared == 1 and Save.last_clear == {"stage": 1, "theme": theme_id}, "승리 → 다음 스테이지 해금 · 직전 클리어")
	Arena.retry()
	check(Arena.running and Arena.stage == 1 and Arena.modal == "stage" and Arena.summon_count == 0 and Arena.heroes.is_empty() and Arena.theme_index == ladder[0], "재도전은 같은 스테이지를 처음부터")
	check(not Arena.next_stage(), "판이 도는 동안에는 다음 스테이지로 못 감")
	_win_stage()
	check(Save.stage_unlocked == 2 and Save.stage_cleared == 1, "같은 스테이지를 다시 깨도 해금은 한 칸")
	check(Arena.next_stage() and Arena.stage == 2 and Arena.theme_index == ladder[1] and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(ladder[1]), "다음 스테이지: STAGE 2 와 그 전장의 길")
	check(Arena.gold == Balance.START_GOLD and Arena.level == 0 and Arena.heroes.is_empty() and Arena.sim.wave_no == 1 and Arena.sim.in_prep() and Arena.sim.elapsed == 0.0, "다음 스테이지는 새 파티로 처음부터")
	_lose_stage()
	check(not Arena.running and Save.stage_unlocked == 2 and int(Save.last_clear.get("stage", 0)) == 1, "패배는 기록을 바꾸지 않음")
	Arena.retry()
	check(Arena.running and Arena.stage == 2, "패배 뒤 재도전도 같은 스테이지")
	Save.stage_unlocked = 37
	Arena.start_run(32002)
	check(Arena.stage == 37 and Arena.theme_index == ladder[36] and int(Roster.THEMES[Arena.theme_index].get("rank", 1)) == Arena.chapter_rank(37), "start_run(seed) 는 다음 해금 스테이지(STAGE 37)를 엶")
	Arena.start_run(32003, 99)
	check(Arena.stage == 99 and Arena.theme_index == ladder[98] and not Arena.can_play(99), "잠긴 스테이지도 도구로는 열림 (화면은 can_play 로 거름)")
	Arena.start_run(32004, 37)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.sim.skip_prep()
	_advance(Arena.sim, 2.0)
	var mid := Arena.snapshot()
	ArenaGeometry.use_layout("coil:0:0")
	check(ArenaValidation.valid(mid) and Arena.restore(mid) and Arena.stage == 37 and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(ladder[36]) and not Arena.sim.monsters.is_empty(),
		"STAGE 37 웨이브 중 저장 · 복구가 그 전장의 길까지 되돌림")
	var bad := mid.duplicate(true)
	bad["stage"] = Balance.ARENA_LADDER + 1
	bad["wave"] = bad["stage"]
	check(not ArenaValidation.valid(bad), "판과 sim 의 스테이지가 다른 저장 거부")
	bad = mid.duplicate(true)
	bad["theme_index"] = Roster.THEMES.size()
	check(not ArenaValidation.valid(bad), "없는 전장 저장 거부")
	Arena.running = false
	_reset_ladder()

## Long battlefields walk faster (Balance.ARENA_ROAD_PACE): the pace is the longest road over the constant,
## at least 1, and a body covers ground that much faster (2026-10-19 O4).
func _check_pace() -> void:
	var seen := {}
	var ok := true
	for n in range(1, 60):
		Arena.start_run(31200 + n, n)
		var key := ArenaGeometry.layout_for_theme(Arena.theme_index).get_slice(":", 0)
		var longest := 0.0
		for lane in range(ArenaGeometry.route_count()): longest = maxf(longest, ArenaGeometry.route_length(lane))
		if not is_equal_approx(Arena.sim.pace(), maxf(1.0, longest / Balance.ARENA_ROAD_PACE)): ok = false
		seen[key] = Arena.sim.pace()
	check(ok and seen.has("coil") and float(seen["coil"]) > 1.5 and seen.has("blades") and is_equal_approx(float(seen["blades"]), 1.0),
		"전장의 걸음 = 가장 긴 길 / %.0f (최소 1): %s" % [Balance.ARENA_ROAD_PACE, str(seen)])
	# The same body on the same coil, at the normal pace and at the coil's: the ground covered scales.
	var covered: Array[float] = []
	for forced in [1.0, -1.0]:
		var sim := _stage(31300, 10)
		check(ArenaGeometry.layout_for_theme(Arena.theme_index).begins_with("coil"), "STAGE 10 은 코일")
		if forced > 0.0: sim._pace = forced
		sim.begin_wave(1)
		sim._spawn_t = 1.0e9
		sim._spawn(Arena.wave_spawns(10, 1)[0]["m"])
		var mo: Dictionary = sim.monsters[sim.monsters.size() - 1]
		# Past the gate's first steps (the walk out of the gate is not at full speed), on the open road.
		var start := 0.0
		for i in range(150):
			if i == 90: start = float(mo["motion_t"])
			sim._rebuild_navigation()
			sim._move_monsters(DT)
		covered.append(float(mo["motion_t"]) - start)
	# (A step ends at each road point, so the slow walk loses a little more on the coil's dense points.)
	var coil_pace: float = float(seen.get("coil", 1.0))
	var ratio := covered[1] / maxf(0.001, covered[0])
	check(covered[0] > 0.0 and ratio >= coil_pace * 0.95 and ratio <= coil_pace * 1.15, "코일에서는 같은 몸이 약 %.2f배 멀리 걸음 (%.2f)" % [coil_pace, ratio])

func _check_endless() -> void:
	var sim := _stage(31007)
	Arena.hell = true
	check(sim.waves_total() == 0 and Arena.waves_total() == 0 and not sim.final_stage() and not sim.chapter_boss(), "끝없는 모드: 마지막 웨이브가 없음")
	check(sim.is_boss_wave(10) and sim.is_boss_wave(20) and sim.is_elite_wave(5) and sim.is_elite_wave(15) and not sim.is_elite_wave(10) and not sim.is_boss_wave(5), "10마다 보스 · 그 밖의 5마다 정예")
	sim.begin_wave(10)
	_spawn_rest(sim)
	check(sim.boss_spawned and sim.monsters.size() == 1 + Balance.ARENA_BOSS_ESCORT, "10웨이브의 보스와 호위")
	sim.events.clear()
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	check(not sim.won and sim.clear_t == 0.0 and Arena.running and not sim.in_prep() and not sim.boss_alive and _events(sim, "arena_stage_clear").is_empty(), "끝없는 모드의 보스는 판을 끝내지 않음")
	_kill_all(sim)
	check(sim.in_prep() and sim.wave_no == 11 and _events(sim, "arena_wave_clear").size() == 1, "호위까지 잡으면 방어 성공 → 11웨이브의 정비")
	check(Balance.arena_hp(1, 1, 25) > Balance.arena_hp(1, 1, 15) and Balance.arena_wave_size(1, 25) > Balance.arena_wave_size(1, 15)
		and Balance.arena_wave_size(1, 500) <= Balance.ARENA_POPULATION_MAX - 2 and Balance.arena_kind_wave(1, 15) == Balance.LAST_WAVE,
		"웨이브 번호로 체력 · 수 · 종 혼합이 오르고 개체 상한은 지킴")
	sim.jump_to_boss()
	check(sim.wave_no == 20 and sim.in_prep(), "끝없는 모드에서 다음 보스 웨이브로 건너뛰기")
	Arena.hell = false
	Arena.running = false
