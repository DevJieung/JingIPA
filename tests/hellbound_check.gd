extends Harness

## Hellbound, the DLC's endless mode (2026-10-19 D3 · U4 · M10):
##   - open with the DLC (Store.owns; a build without a shop has it) and a codex that has met someone;
##   - the squad comes from the codex (Save.seen_units) at each hero's best grade (Save.best_of; never
##     graded = 1 star), 1..ARENA_HELL_SQUAD distinct ids; a bad pick changes nothing;
##   - a rank 4~5 battlefield, no free box (the squad stands in for it), endless waves: a boss every
##     ARENA_WAVES, an elite on the other multiples of ARENA_ELITE_EVERY, health from
##     Balance.arena_hell_stage · arena_hell_ramp_wave · arena_hell_hp (ARENA_HELL_HP x ARENA_HELL_HP_GROW^(w-1)),
##     and the defence bonus of a wave follows its place in the block (no endless snowball);
##   - saves carry hell and squad (the mode stays "arena"); retry brings the same squad;
##   - its record is the best wave reached (Save.hell_best_wave) and the last squad (Save.hell_squad); the
##     ladder's unlock, last clear and best stage stay as they were.
## The codex and the records are set in memory and put back (STELLARDEFENSE_NO_SAVE).
##
##   godot --headless --path . res://tests/hellbound_check.tscn
const DT := 1.0 / 60.0
## Characters met in the check's codex: the first MET of the roster.
const MET := 8

## A shop that sells nothing and owns what it is told (the DLC bought or not).
class Owner extends RefCounted:
	const NAME := "test"
	var store: Node
	var owned: Array = []
	func start() -> void: store.set_owned(owned)
	func sells(_id: String) -> bool: return false
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void: store.finish_restore(true)
	func buy(product: Dictionary) -> void: store.finish_purchase(String(product["id"]), "unavailable")

var _kept := {}

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_kept = {"seen": Save.seen_units.duplicate(), "best": Save.unit_best.duplicate(), "hell_best": Save.hell_best_wave,
		"hell_squad": Save.hell_squad.duplicate(), "best_wave": Save.best_wave, "kills": Save.total_kills}
	_codex()
	_check_gate()
	_check_pool_and_picks()
	_check_start()
	_check_endless()
	_check_saves()
	_check_records_and_retry()
	_check_blocks()
	_use_shop(null)
	Save.seen_units = _kept["seen"]
	Save.unit_best = _kept["best"]
	Save.hell_best_wave = _kept["hell_best"]
	Save.hell_squad = _kept["hell_squad"]
	Save.best_wave = _kept["best_wave"]
	Save.total_kills = _kept["kills"]
	_reset_ladder()
	Arena.running = false
	Arena.hell = false
	finish("Hellbound: DLC·도감 스쿼드·끝없는 웨이브·저장·기록")

func _reset_ladder() -> void:
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	Save.last_clear = {}

func _use_shop(owned: Variant) -> void:
	Save.iap_owned = []
	Save.iap_sandbox = []
	Store._owned.clear()
	if owned == null:
		Store.use_backend(null)
		return
	var shop := Owner.new()
	shop.owned = owned
	Store.use_backend(shop)

func _id(index: int) -> String:
	return String(Roster.UNITS[index]["id"])

## The check's codex: the first MET characters met — one at 5 stars, one at 3, one at half a star, the rest
## never graded — and an id the roster no longer has.
func _codex() -> void:
	Save.seen_units = {}
	Save.unit_best = {}
	for i in range(MET):
		Save.seen_units[_id(i)] = true
	Save.seen_units["gone_hero"] = true
	Save.unit_best[_id(0)] = Balance.TIER_MAX
	Save.unit_best[_id(1)] = JewelBox.tier_of(3)
	Save.unit_best[_id(2)] = 0

func _squad() -> Array:
	return [_id(0), _id(1), _id(2), _id(5)]

func _tier_in_pool(id: String) -> int:
	for entry in Arena.hellbound_pool():
		if String(entry["unit"]["id"]) == id: return int(entry["tier"])
	return -1

## Hellbound with the check's squad, past its card, guardians holding fire.
func _hell(seed_value: int) -> ArenaSim:
	Arena.start_hellbound(_squad(), seed_value)
	Arena.confirm_stage()
	var sim: ArenaSim = Arena.sim
	for hero in sim.heroes: hero["cool"] = 1.0e9
	return sim

func _events(sim: ArenaSim, type: String) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool: return String(e.get("t", "")) == type)

func _kill_all(sim: ArenaSim) -> void:
	for mo in sim.monsters: mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()

## The rest of the current wave's list spawns; the bodies are held at their gates.
func _spawn_rest(sim: ArenaSim) -> void:
	var guard := 0
	while (sim.in_prep() or sim._wave_spawned < sim.wave_size()) and guard < 6000:
		guard += 1
		if Arena.modal == "talent" and not Arena.talent_offer.is_empty():
			Arena.pick_talent(String(Arena.talent_offer[0]))
		sim.step(DT)
		for mo in sim.monsters: mo["spd"] = 0.0

## The crystal breaks with no revival left: the run ends in defeat.
func _break(sim: ArenaSim) -> void:
	sim.revives = Balance.ARENA_REVIVE_USES
	sim.invuln_t = 0.0
	sim._damage_crystal(1.0e9, Balance.ARENA_CENTER)

func _check_gate() -> void:
	_use_shop(null)
	check(Store.owns(Store.GUARDIAN) and Arena.dlc() and Arena.can_hellbound(), "상점이 없는 빌드는 DLC 를 가진 셈: Hellbound 열림")
	_use_shop([])
	check(not Arena.dlc() and not Arena.can_hellbound(), "DLC 가 없으면 Hellbound 닫힘")
	Arena.start_run(53001, 1)
	var before := Arena.snapshot()
	check(not Arena.start_hellbound(_squad()) and not Arena.hell and Arena.snapshot() == before, "DLC 없이 시작 요청은 거절·판은 그대로")
	_use_shop([Store.GUARDIAN])
	check(Arena.dlc() and Arena.can_hellbound(), "DLC 를 사면 열림")
	var seen: Dictionary = Save.seen_units
	Save.seen_units = {}
	check(Arena.hellbound_pool().is_empty() and not Arena.can_hellbound() and not Arena.start_hellbound(_squad()), "도감이 비면 데려갈 영웅이 없어 닫힘")
	Save.seen_units = seen
	_use_shop(null)

func _check_pool_and_picks() -> void:
	var ids: Array = []
	for entry in Arena.hellbound_pool(): ids.append(String(entry["unit"]["id"]))
	var met: Array = []
	for i in range(MET): met.append(_id(i))
	check(ids == met, "만난 영웅만 표 차례로·표에 없는 id 는 빠짐")
	check(_tier_in_pool(_id(0)) == Balance.TIER_MAX and _tier_in_pool(_id(1)) == JewelBox.tier_of(3) and _tier_in_pool(_id(2)) == 0
		and _tier_in_pool(_id(5)) == JewelBox.tier_of(1), "등급은 그 영웅의 최고 등급(기록이 없으면 1성)")
	Arena.start_run(53002, 1)
	var before := Arena.snapshot()
	var too_many: Array = met.slice(0, Balance.ARENA_HELL_SQUAD + 1)
	for bad in [[], too_many, [_id(0), _id(0)], ["gone_hero"], [_id(MET)], [7], [_id(0), null]]:
		check(not Arena.start_hellbound(bad) and not Arena.hell and Arena.snapshot() == before, "잘못 고른 스쿼드는 거절·판은 그대로: " + str(bad))
	check(Arena.start_hellbound(met.slice(0, Balance.ARENA_HELL_SQUAD), 53010) and Arena.heroes.size() + Arena.bench.size() == Balance.ARENA_HELL_SQUAD, "%d명까지 데려감" % Balance.ARENA_HELL_SQUAD)
	check(Arena.start_hellbound([_id(3)], 53011) and Arena.heroes.size() == 1, "한 명만 데려가도 됨")

func _check_start() -> void:
	var squad := _squad()
	check(Arena.start_hellbound(squad, 53003), "Hellbound 시작")
	check(Arena.running and Arena.hell and Array(Arena.squad) == squad and Save.hell_squad == squad, "스쿼드를 판과 기록(마지막 스쿼드)에 둠")
	var theme := Arena.theme_for(1)
	check(Arena.stage == Balance.ARENA_HELL_BASE_STAGE and int(theme.get("rank", 0)) >= 4
		and ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index), "4~5등급 전장 하나와 그 도로 배치")
	var graded := Arena.heroes.size() == squad.size() and Arena.bench.is_empty()
	for i in range(mini(squad.size(), Arena.heroes.size())):
		graded = graded and String(Arena.heroes[i]["unit"]["id"]) == squad[i] and int(Arena.heroes[i]["tier"]) == _tier_in_pool(squad[i])
	check(Arena.modal == "stage" and graded, "전장 카드 아래 스쿼드가 모두 판에·영웅마다 도감의 최고 등급")
	check(Arena.sim.heroes.size() == squad.size(), "스쿼드가 전투에도 섬")
	var preview := Arena.stage_preview(Arena.stage)
	check(bool(preview["hell"]) and not bool(preview["final"]) and String(preview["theme"].get("id", "")) == String(theme.get("id", "")), "전장 카드: Hellbound·마지막 스테이지 아님·그 전장")
	check(Arena.confirm_stage() and Arena.modal == "" and Arena.summon_count == 1 and Arena.box_cards.is_empty(), "무료 첫 상자 없이 바로 정비 시간")
	var sim: ArenaSim = Arena.sim
	check(sim.waves_total() == 0 and Arena.waves_total() == 0 and sim.in_prep() and sim.wave_no == 1 and not sim.final_stage(), "끝없는 웨이브의 첫 정비")
	Arena.gold = 10000
	check(Arena.can_summon() and Arena.begin_summon() and Arena.modal == "box", "정비 시간의 보석상자는 그대로(유료)")
	Arena.confirm_summon()
	Arena.close_modal()
	check(Arena.modal == "" and Arena.running, "상자를 고르고 전투로")

func _check_endless() -> void:
	var sim := _hell(53004)
	check(sim.is_elite_wave(5) and sim.is_boss_wave(10) and sim.is_elite_wave(15) and sim.is_boss_wave(20) and not sim.is_boss_wave(5)
		and not sim.is_elite_wave(10), "보스는 10웨이브마다·정예는 그 밖의 5웨이브마다")
	var bosses: Array = Arena.wave_spawns(Arena.stage, 10).filter(func(e: Dictionary) -> bool: return String(e["m"]["kind"]) == "boss")
	var elites: Array = Arena.wave_spawns(Arena.stage, 5).filter(func(e: Dictionary) -> bool: return bool(e["elite"]))
	check(bosses.size() == 1 and elites.size() == 1 and Arena.wave_spawns(Arena.stage, 30).size() == Balance.arena_wave_count(Arena.stage, 30, 0), "출현 목록: 보스·정예·먼 웨이브까지")
	# Health: wave w stands for ladder stage arena_hell_stage(w), its ramp repeats every ARENA_WAVES, and
	# everything is arena_hell_hp(w) thicker (ARENA_HELL_HP, growing ARENA_HELL_HP_GROW a wave).
	for w in [1, 7, 11, 23]:
		sim.begin_wave(w)
		sim._spawn_t = 1.0e9
		sim._spawn(Arena.wave_spawns(Arena.stage, w)[0]["m"])
		var mo: Dictionary = sim.monsters[sim.monsters.size() - 1]
		var want := Balance.arena_hp(Balance.arena_hell_stage(w), sim._rank, Balance.arena_hell_ramp_wave(w)) * float(Balance.MKIND[String(mo["kind"])]["hp"]) * Balance.arena_hell_hp(w)
		check(is_equal_approx(float(mo["max"]), want), "%d웨이브 체력 = 사다리 %d탄 %d웨이브의 %.1f배" % [w, Balance.arena_hell_stage(w), Balance.arena_hell_ramp_wave(w), Balance.arena_hell_hp(w)])
	check(Balance.arena_hell_stage(1) == Balance.ARENA_HELL_BASE_STAGE and Balance.arena_hell_stage(11) > Balance.arena_hell_stage(1)
		and Balance.arena_hell_ramp_wave(10) == Balance.ARENA_WAVES and Balance.arena_hell_ramp_wave(11) == 1, "웨이브 → 사다리 스테이지·묶음 안에서만 오르는 웨이브")
	check(Balance.arena_hp(Balance.arena_hell_stage(11), 4, 1) > Balance.arena_hp(Balance.arena_hell_stage(1), 4, 1), "다음 묶음은 더 단단함")
	check(is_equal_approx(Balance.arena_hell_hp(1), Balance.ARENA_HELL_HP) and is_equal_approx(Balance.arena_hell_hp(11) / Balance.arena_hell_hp(1), pow(Balance.ARENA_HELL_HP_GROW, 10.0))
		and Balance.ARENA_HELL_HP_GROW > 1.0, "Hellbound 체력 배수는 웨이브마다 ARENA_HELL_HP_GROW 배")
	# The ladder keeps its own health (no Hellbound factor).
	Arena.start_run(53012, Balance.ARENA_HELL_BASE_STAGE)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	var ladder: ArenaSim = Arena.sim
	ladder.begin_wave(1)
	ladder._spawn_t = 1.0e9
	ladder._spawn(Arena.wave_spawns(Arena.stage, 1)[0]["m"])
	var body: Dictionary = ladder.monsters[ladder.monsters.size() - 1]
	check(is_equal_approx(float(body["max"]), Balance.arena_hp(Arena.stage, ladder._rank, 1) * float(Balance.MKIND[String(body["kind"])]["hp"])), "사다리 스테이지의 체력은 그대로")
	# The elite of wave 5 and the boss of wave 10: neither ends the run.
	sim = _hell(53013)
	sim.begin_wave(5)
	_spawn_rest(sim)
	var marked := sim.monsters.filter(func(mo: Dictionary) -> bool: return bool(mo.get("elite", false)))
	check(marked.size() == 1, "5웨이브에 정예 하나")
	_kill_all(sim)
	check(sim.in_prep() and sim.wave_no == 6, "정예 웨이브를 막으면 6웨이브의 정비")
	# The defence bonus follows the wave's place in its block: wave 15 pays what wave 5 does.
	sim.begin_wave(15)
	_spawn_rest(sim)
	for mo in sim.monsters: mo["gold"] = 0
	var gold_before: int = Arena.gold
	sim.events.clear()
	_kill_all(sim)
	var held := _events(sim, "arena_wave_clear")
	var bonus := Balance.arena_wave_bonus(Arena.stage, 5)
	check(held.size() == 1 and int(held[0]["gold"]) == bonus and Arena.gold - gold_before == bonus and bonus < Balance.arena_wave_bonus(Arena.stage, 15),
		"Hellbound 방어 성공 골드는 묶음 안 자리(15웨이브 = 5웨이브 %d G)" % bonus)
	sim.begin_wave(10)
	_spawn_rest(sim)
	check(sim.boss_spawned, "10웨이브의 보스")
	sim.events.clear()
	_kill_all(sim)
	check(not sim.won and sim.clear_t == 0.0 and Arena.running and sim.in_prep() and sim.wave_no == 11 and _events(sim, "arena_stage_clear").is_empty(),
		"보스를 쓰러뜨려도 판은 이어짐 → 11웨이브의 정비")

func _check_saves() -> void:
	var sim := _hell(53005)
	sim.begin_wave(13)
	for i in range(90):
		sim.step(DT)
		for mo in sim.monsters: mo["spd"] = 0.0
	var saved := Arena.snapshot()
	check(saved["mode"] == "arena" and saved["hell"] == true and saved["squad"] == _squad() and int(saved["sim"]["wave_no"]) == 13 and not sim.monsters.is_empty(),
		"저장: mode 는 arena · hell · squad · 13웨이브")
	check(ArenaValidation.valid(saved), "13웨이브의 Hellbound 저장 유효")
	Arena.start_run(53006, 1)
	check(not Arena.hell and Arena.squad.is_empty(), "사다리 판을 열면 Hellbound 표시가 지워짐")
	check(Arena.restore(saved) and Arena.hell and Array(Arena.squad) == _squad() and Arena.sim.wave_no == 13 and Arena.sim.waves_total() == 0
		and Arena.stage == Balance.ARENA_HELL_BASE_STAGE and Arena.theme_index == int(saved["theme_index"]), "복구: Hellbound · 스쿼드 · 웨이브 · 전장 그대로")
	var again := Arena.snapshot()
	check(again["hell"] == true and again["squad"] == saved["squad"] and again["sim"]["monsters"].size() == saved["sim"]["monsters"].size(), "복구한 판을 다시 저장해도 같음")
	var ladder := saved.duplicate(true)
	ladder.erase("hell")
	ladder.erase("squad")
	check(ArenaValidation.valid(ladder) and Arena.restore(ladder) and not Arena.hell and Arena.sim.wave_no == Balance.ARENA_WAVES,
		"Hellbound 표시가 없는 저장은 사다리 판으로, 웨이브는 마지막 웨이브에 맞춤")
	var met: Array = []
	for i in range(MET): met.append(_id(i))
	for broken in [["hell", "yes"], ["squad", [_id(0), _id(0)]], ["squad", ["gone_hero"]], ["squad", []], ["squad", "abc"], ["squad", [3]]]:
		var bad := saved.duplicate(true)
		bad[broken[0]] = broken[1]
		check(not ArenaValidation.valid(bad), "잘못된 Hellbound 저장 거부: %s = %s" % [broken[0], str(broken[1])])
	# A squad larger than today's ARENA_HELL_SQUAD (the value was lowered) is only a record: still valid.
	var wide := saved.duplicate(true)
	wide["squad"] = met.slice(0, Balance.ARENA_HELL_SQUAD + 1)
	check(ArenaValidation.valid(wide), "지금 상한보다 큰 스쿼드 기록도 받음")
	# Saves from before Hellbound (no hell, no squad, no revival record) still load as ladder stages.
	Arena.start_run(53007, 1)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	var old := Arena.snapshot()
	for key in ["hell", "squad", "revive_gift"]: old.erase(key)
	check(ArenaValidation.valid(old) and Arena.restore(old) and not Arena.hell and Arena.squad.is_empty() and Arena.waves_total() == Balance.ARENA_WAVES,
		"Hellbound 전의 저장도 사다리 판으로 이어 함")

## Every block of ARENA_WAVES waves fills the common skills' uses again, and every held wave writes the
## record (2026-10-19): an endless run neither runs dry of skills nor loses its best wave when left.
func _check_blocks() -> void:
	Save.hell_best_wave = 0
	var sim := _hell(53020)
	check(Save.hell_best_wave == 0, "시작에는 기록 0")
	sim.begin_wave(4)
	_spawn_rest(sim)
	_kill_all(sim)
	check(sim.in_prep() and sim.wave_no == 5 and Save.hell_best_wave == 4 and Arena.running, "웨이브를 막을 때마다 최고 기록을 씀 (판이 끝나기 전에도)")
	for id in ["blast", "freeze", "ward"]: sim.skill_uses[id] = sim.skill_max_uses(id)
	sim.begin_wave(5)
	_spawn_rest(sim)
	_kill_all(sim)
	check(sim.skill_uses_left("blast") == 0 and sim.skill_uses_left("ward") == 0, "묶음 한가운데의 방어 성공은 기술 횟수를 채우지 않음")
	sim.begin_wave(10)
	_spawn_rest(sim)
	sim.events.clear()
	_kill_all(sim)
	var full := true
	for id in ["blast", "freeze", "ward"]: full = full and sim.skill_uses_left(id) == sim.skill_max_uses(id)
	check(full and _events(sim, "arena_skill_refill").size() == 1 and sim.wave_no == 11 and Save.hell_best_wave == 10, "10웨이브 묶음을 막으면 공용 기술 횟수가 다시 참 · 기록 10")
	Arena.start_run(53021, 1)
	check(Save.hell_best_wave == 10, "다른 판을 시작해도 기록이 남음")
	_reset_ladder()

func _check_records_and_retry() -> void:
	Save.stage_unlocked = 7
	Save.stage_cleared = 6
	Save.last_clear = {"stage": 6, "theme": "kept"}
	Save.hell_best_wave = 0
	var best_stage: int = Save.best_wave
	var kills: int = Save.total_kills
	var sim := _hell(53008)
	check(Arena.revive_ready() and Arena.revives_left() == Balance.ARENA_REVIVE_USES, "Hellbound 에서도 부활권")
	sim.begin_wave(9)
	sim._spawn_t = 1.0e9
	Arena.kills = 12
	_break(sim)
	check(sim.done and not sim.won and not Arena.running and Arena.modal == "result", "소울 스톤이 부서지면 끝(패배)")
	check(Save.hell_best_wave == 9 and Save.hell_squad == _squad(), "기록: 닿은 최고 웨이브 9 · 마지막 스쿼드")
	check(Save.stage_unlocked == 7 and Save.stage_cleared == 6 and Save.last_clear == {"stage": 6, "theme": "kept"} and Save.best_wave == best_stage,
		"사다리 해금 · 직전 클리어 · 최고 스테이지는 그대로")
	check(Save.total_kills == kills + 12, "처치 수는 평생 기록에 더함")
	check(not Arena.next_stage(), "Hellbound 에는 다음 스테이지가 없음")
	# Retry: the same squad, from wave 1.
	Arena.retry()
	check(Arena.running and Arena.hell and Array(Arena.squad) == _squad() and Arena.modal == "stage" and Arena.heroes.size() == _squad().size()
		and Arena.sim.wave_no == 1 and Arena.sim.in_prep(), "다시 하기: 같은 스쿼드로 1웨이브부터")
	# The wave held is what counts: in the preparation after wave 6 the reached wave is 6. A lower wave
	# never lowers the record.
	Arena.confirm_stage()
	sim = Arena.sim
	for hero in sim.heroes: hero["cool"] = 1.0e9
	sim.begin_wave(6)
	_spawn_rest(sim)
	_kill_all(sim)
	check(sim.in_prep() and sim.wave_no == 7 and sim.wave_reached() == 6, "6웨이브를 막은 뒤의 정비: 닿은 웨이브 6")
	_break(sim)
	check(Save.hell_best_wave == 9, "더 낮은 웨이브는 기록을 내리지 않음")
	Arena.retry()
	Arena.confirm_stage()
	sim = Arena.sim
	sim.begin_wave(12)
	sim._spawn_t = 1.0e9
	_break(sim)
	check(Save.hell_best_wave == 12, "더 높은 웨이브는 기록을 올림")
	# A ladder run afterwards is an ordinary ladder run.
	Arena.start_run(53009)
	check(not Arena.hell and Arena.squad.is_empty() and Arena.stage == Save.stage_unlocked and Arena.waves_total() == Balance.ARENA_WAVES, "그 뒤의 사다리 판은 평소대로")
