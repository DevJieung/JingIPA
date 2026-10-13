extends Harness

## Auto-play of the stage chain, to see how the difficulty curve actually plays:
## how far a plain strategy gets, where the crystal starts to crack and how long each
## stage boss stands. The player here is deliberately ordinary: it fills the field,
## alternates summons and upgrades, posts its heroes where the roads reach the crystal,
## walks an idle hero over when something hits the crystal out of everyone's reach,
## never counters elements and casts the three skills on simple cues. A person who
## walks heroes out to meet the crowd and builds against the battlefield does better.
##
##   godot --headless --path . res://tests/arena_balance_check.tscn -- --runs 12 --from 0
##   --blessing    play with the Guardian's blessing (three crystal revivals per run, with gold)
##   --report      print the per-stage table only, do not judge
class Owner extends RefCounted:
	const NAME := "test"
	var store: Node
	var owned: Array = []
	func start() -> void: store.set_owned(owned)
	func sells(_id: String) -> bool: return false
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void: store.finish_restore(true)
	func buy(product: Dictionary) -> void: store.finish_purchase(String(product["id"]), "unavailable")

## Just outside the altar, so a sword reaches whatever is hitting the crystal.
const POST := 104.0
const STEP := 1.0 / 30.0
var _turn := 0

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	var runs := arg_int("--runs", 8)
	var first := arg_int("--from", 0)
	var owner := Owner.new()
	if has_arg("--blessing"): owner.owned = [Store.GUARDIAN]
	Store.use_backend(owner)
	var reached: Array[int] = []
	var clears := 0
	var early_loss := 0.0
	var stage_damage: Array[float] = []
	var stage_boss: Array[float] = []
	var stage_seen: Array[int] = []
	for n in range(Balance.ARENA_STAGES):
		stage_damage.append(0.0)
		stage_boss.append(0.0)
		stage_seen.append(0)
	for n in range(runs):
		var result := _play(1000 + first + n)
		reached.append(int(result["stage"]))
		if bool(result["won"]): clears += 1
		var line := "run %2d  seed %d  %s %2d탄  %s" % [n + 1, 1000 + first + n, "승리" if result["won"] else "패배", result["stage"], result["fields"]]
		print(line)
		for record in result["stages"]:
			var index := int(record["stage"]) - 1
			stage_seen[index] += 1
			stage_damage[index] += float(record["damage"])
			stage_boss[index] += float(record["boss_seconds"])
			if index < 2: early_loss += float(record["damage"])
		print("        " + result["detail"])
	reached.sort()
	var median: int = reached[reached.size() / 2]
	print("")
	print("탄    도달   수정 피해(평균)   보스 처치(초, 평균)   몬스터 체력   처치 골드")
	for n in range(Balance.ARENA_STAGES):
		var seen := maxi(1, stage_seen[n])
		print("%2d   %3d판    %7.0f          %6.1f              %7.0f      %d" % [n + 1, stage_seen[n], stage_damage[n] / seen, stage_boss[n] / seen,
			Balance.arena_hp(n + 1, clampi(ceili(float(n + 1) * 5.0 / Balance.ARENA_STAGES), 1, 5)), Balance.arena_kill_gold(n + 1, "swarm")])
	print("")
	print("도달 탄: 중간값 %d · 최소 %d · 최대 %d · 완주 %d/%d판%s" % [median, reached[0], reached[-1], clears, runs, "  (수호자의 가호 사용)" if has_arg("--blessing") else ""])
	Store.use_backend(null)
	Arena.running = false
	if has_arg("--report"):
		get_tree().quit(0)
		return
	check(early_loss / runs < Balance.ARENA_CRYSTAL_HP * 0.05, "1~2탄은 수정이 거의 상하지 않음 (판당 평균 피해 %.0f)" % (early_loss / runs))
	check(median >= 5, "평범한 자동 플레이가 판의 절반은 넘김 (중간값 %d탄)" % median)
	check(clears < runs, "뒤 탄이 실제로 어려움: 모든 판을 완주하지는 못함 (%d/%d)" % [clears, runs])
	var early := (stage_boss[0] + stage_boss[1]) / maxf(1.0, float(stage_seen[0] + stage_seen[1]))
	var early_damage := (stage_damage[0] + stage_damage[1] + stage_damage[2]) / maxf(1.0, float(stage_seen[0] + stage_seen[1] + stage_seen[2]))
	var late_seen := 0
	var late := 0.0
	var late_damage := 0.0
	for n in range(6, Balance.ARENA_STAGES):
		late += stage_boss[n]
		late_damage += stage_damage[n]
		late_seen += stage_seen[n]
	check(late_seen > 0 and late / late_seen > early, "뒤 탄의 보스가 앞 탄의 보스보다 오래 버팀 (%.1f초 > %.1f초)" % [late / maxf(1.0, late_seen), early])
	check(late_seen > 0 and late_damage / late_seen > early_damage + 40.0, "탄을 거듭할수록 수정이 받는 압박이 커짐 (7~10탄 평균 %.0f > 1~3탄 평균 %.0f)" % [late_damage / maxf(1.0, late_seen), early_damage])
	finish("연속 수호전 탄별 난이도 (자동 플레이 %d판)" % runs)

func _play(seed_value: int) -> Dictionary:
	Arena.start_run(seed_value)
	_turn = 0
	var fields := PackedStringArray()
	for index in Arena.stage_themes: fields.append(String(Roster.THEMES[index]["main_body"]).substr(0, 2) + String(ArenaGeometry.layout_for_theme(index)).substr(0, 2))
	var stages: Array = []
	var record := {}
	var think := 0.0
	var guard := 0
	var hp_at_start := 0.0
	var boss_at := -1.0
	var revives_seen := 0
	while Arena.running and guard < 2000000:
		guard += 1
		match Arena.modal:
			"stage":
				Arena.confirm_stage()
				continue
			"rite":
				_rite()
				continue
			"shop", "bench":
				Arena.close_modal()
				continue
		var sim: ArenaSim = Arena.sim
		if record.is_empty() or int(record["stage"]) != Arena.stage:
			if not record.is_empty(): record["dps_end"] = Arena.total_dps()
			record = {"stage": Arena.stage, "damage": 0.0, "boss_seconds": 0.0, "dps_start": Arena.total_dps(), "heroes": Arena.heroes.size()}
			stages.append(record)
			hp_at_start = sim.crystal_hp
			boss_at = -1.0
			_place()
		var hp_before: float = sim.crystal_hp
		var stage_before: int = Arena.stage
		sim.step(STEP)
		# Damage taken (a stage clear mends the crystal; a revival counts as losing it all).
		if Arena.stage == stage_before and sim.clear_t == 0.0:
			if sim.revives > revives_seen:
				revives_seen = sim.revives
				record["damage"] = float(record["damage"]) + hp_before
			elif sim.crystal_hp < hp_before: record["damage"] = float(record["damage"]) + hp_before - sim.crystal_hp
		if sim.boss_spawned and boss_at < 0.0: boss_at = sim.elapsed
		if boss_at >= 0.0 and (sim.clear_t > 0.0 or not Arena.running) and float(record["boss_seconds"]) == 0.0:
			record["boss_seconds"] = sim.elapsed - boss_at
		think += STEP
		if think >= 1.0 and Arena.running and Arena.modal.is_empty() and sim.clear_t == 0.0:
			think = 0.0
			_think(sim)
			if has_arg("--trace") and int(sim.elapsed) % 10 == 0: _trace(sim)
	record["dps_end"] = Arena.total_dps()
	var growth := PackedStringArray()
	for item in stages: growth.append("%d:%.0f" % [item["stage"], float(item.get("dps_end", 0.0))])
	var tiers := PackedStringArray()
	for hero in Arena.heroes: tiers.append("%.1f" % ((int(hero["tier"]) + 1) * 0.5))
	var detail := "별 [%s] 대기 %d  강화 atk%d rate%d crit%d critx%d gold%d  패시브 %s  처치 %d" % [",".join(tiers), Arena.bench.size(),
		Arena.lv("atk"), Arena.lv("rate"), Arena.lv("crit"), Arena.lv("critx"), Arena.lv("gold"), ",".join(PackedStringArray(Arena.passives)), Arena.kills]
	detail += "\n        탄 끝 화력 " + " ".join(growth)
	return {"stage": Arena.stage, "won": Arena.sim.won, "stages": stages, "fields": " ".join(fields), "detail": detail}

## Every free re-spin, then take what the stars give.
func _rite() -> void:
	if Arena.phase == Arena.Phase.DRAW:
		while Arena.can_respin() and Arena.respin_cost() == 0: Arena.respin()
		Arena.confirm_summon()
	Arena.close_modal()
	_field_best()
	_place()

## Field the six highest grades.
func _field_best() -> void:
	if Arena.bench.is_empty() or Arena.heroes.size() < Balance.ARENA_HERO_LIMIT: return
	for attempt in range(8):
		var low := 0
		for i in range(Arena.heroes.size()):
			if int(Arena.heroes[i]["tier"]) < int(Arena.heroes[low]["tier"]): low = i
		var high := 0
		for i in range(Arena.bench.size()):
			if int(Arena.bench[i]["tier"]) > int(Arena.bench[high]["tier"]): high = i
		if int(Arena.bench[high]["tier"]) <= int(Arena.heroes[low]["tier"]): return
		if not Arena.open_modal("bench"): return
		Arena.swap_hero(low, high)
		Arena.close_modal()

## Posts beside the points where this battlefield's roads reach the plaza.
func _place() -> void:
	var arrivals: Array[float] = []
	for lane in range(ArenaGeometry.route_count()):
		var path := ArenaGeometry.route_points(lane)
		var angle := (path[path.size() - 2] - Balance.ARENA_CENTER).angle()
		var fresh := true
		for other in arrivals:
			if absf(angle_difference(angle, other)) < 0.35: fresh = false
		if fresh: arrivals.append(angle)
	for i in range(Arena.heroes.size()):
		var lap := i / arrivals.size()
		var spread := float((lap + 1) / 2) * 0.58 * (1.0 if lap % 2 == 1 else -1.0)
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(arrivals[i % arrivals.size()] + spread) * POST
	if Arena.sim != null: Arena.sim.refresh_heroes()

## A hero with nothing in reach walks to the monster nearest the crystal (what a player
## does with the joystick); a hero that is fighting stays where it is.
func _cover(sim: ArenaSim) -> void:
	if sim.monsters.is_empty(): return
	var target: Dictionary = sim.monsters[0]
	for mo in sim.monsters:
		if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) < Vector2(target["pos"]).distance_to(Balance.ARENA_CENTER): target = mo
	var at: Vector2 = target["pos"]
	# Only what has come close matters; the rest is still walking the road.
	if at.distance_to(Balance.ARENA_CENTER) > 260.0: return
	var moved := false
	for i in range(sim.heroes.size()):
		var from: Vector2 = sim.heroes[i]["pos"]
		var busy := false
		for mo in sim.monsters:
			if from.distance_to(mo["pos"]) <= float(sim.heroes[i]["range"]):
				busy = true
				break
		if busy: continue
		var angle := (at - Balance.ARENA_CENTER).angle()
		for turn in [0.0, 0.36, -0.36, 0.72, -0.72, 1.08, -1.08]:
			var post := Balance.ARENA_CENTER + Vector2.from_angle(angle + turn) * POST
			var free := true
			for j in range(sim.heroes.size()):
				if j != i and Vector2(Arena.heroes[j]["position"]).distance_to(post) < Balance.ARENA_HERO_RADIUS * 2.0: free = false
			if free:
				Arena.heroes[i]["position"] = post
				moved = true
				break
	if moved: sim.refresh_heroes()

func _think(sim: ArenaSim) -> void:
	# Skills on simple cues.
	var near := 0
	var boss := false
	for mo in sim.monsters:
		if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) < 220.0: near += 1
		if String(mo["kind"]) == "boss": boss = true
	if sim.crystal_hp < sim.crystal_max * 0.7 and near >= 3 and sim.shield <= 0.0: sim.cast_skill("ward")
	if near >= 8 or (boss and near >= 3): sim.cast_skill("freeze")
	if near >= 6 or boss: sim.cast_skill("blast")
	_cover(sim)
	# Spend: fill the field first, then alternate summons with upgrades and buy a
	# passive whenever one on offer is affordable with gold to spare.
	_turn += 1
	if Arena.heroes.size() < Balance.ARENA_HERO_LIMIT:
		if Arena.gold >= Arena.summon_cost() and not Arena.eligible_units().is_empty(): Arena.begin_summon()
		return
	if _turn % 6 == 0 and Arena.owned_passives.size() < Balance.PASSIVE_SLOTS and Arena.open_modal("shop"):
		for id in Arena.shop_offer.duplicate():
			var cost := int(Balance.passive_by_id(id)["cost"])
			if Arena.gold >= cost + 60 and Arena.owned_passives.size() < Balance.PASSIVE_SLOTS: Arena.buy_passive(id)
		Arena.close_modal()
		return
	var wants := ["atk", "summon", "rate", "summon", "crit", "atk", "summon", "critx", "gold"]
	var want: String = wants[_turn % wants.size()]
	if want == "summon":
		if Arena.gold >= Arena.summon_cost() and not Arena.eligible_units().is_empty(): Arena.begin_summon()
		return
	var cost := Balance.upgrade_cost(want, Arena.lv(want))
	if Balance.upgrade_maxed(want, Arena.lv(want)) or Arena.gold < cost: return
	if Arena.open_modal("shop"):
		Arena.buy_upgrade(want)
		Arena.close_modal()


func _trace(sim: ArenaSim) -> void:
	var siege := 0
	var blocked := 0
	for mo in sim.monsters:
		if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 1.0: siege += 1
		if bool(mo["blocked"]): blocked += 1
	var party := PackedStringArray()
	for hero in sim.heroes:
		var unit: Dictionary = hero["h"]["unit"]
		var reach := 0
		for mo in sim.monsters:
			if Vector2(hero["pos"]).distance_to(mo["pos"]) <= float(hero["range"]): reach += 1
		party.append("%s/%s/%s r%.0f t%d in%d dmg%.0f" % [unit["id"], unit.get("elem", "?"), unit.get("weapon", "?"), float(hero["range"]), int(hero["h"]["tier"]), reach, float(hero["dmg"])])
	print("  %d탄 t=%3.0f 수정 %4.0f 골드 %3d 몹 %2d (공성 %d·막힘 %d) | %s" % [sim.stage, sim.elapsed, sim.crystal_hp, Arena.gold, sim.monsters.size(), siege, blocked, "  ".join(party)])
