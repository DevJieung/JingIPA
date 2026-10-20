extends Harness

## Common skills (2026-10-19 F5 · PLAN M7 · M8):
##   - every cast costs a fixed gold (Balance.ARENA_BLAST_GOLD · ARENA_FREEZE_GOLD · ARENA_WARD_GOLD; the
##     constellation key skill_gold scales it), paid once after the effect; a refused cast spends nothing;
##   - ArenaSim.skill_state is the one judge — cast_skill asks it and the HUD draws it. Its block, in order:
##     inactive → prep → clearing → cooldown → spent → no_target → gold, or "" (ready);
##   - the starburst falls where the player taps (cast_skill(id, at)) and hits every body that reaches into
##     its radius; a point outside the arena is refused; without a point it aims at the monster nearest the
##     crystal (auto-play, checks). Frost and ward ignore the point;
##   - cooldowns and uses survive a save.
## Guardians hold their fire and spawns are held, so only the skills hurt.
##
##   godot --headless --path . res://tests/arena_skill_check.tscn
const DT := 1.0 / 60.0
const SKILLS := ["blast", "freeze", "ward"]

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_costs()
	_check_states()
	_check_aimed_blast()
	_check_saves()
	_reset_ladder()
	Arena.running = false
	finish("공통 스킬·골드·판정·조준 폭발")

func _reset_ladder() -> void:
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	Save.last_clear = {}

## STAGE 1 past its card and free box, guardians holding fire, no monster, plenty of gold. In wave 1 (its
## spawns held) unless `wave` is false: then still in the first preparation.
func _fight(seed_value: int, wave: bool = true) -> ArenaSim:
	Arena.start_run(seed_value, 1)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	var sim: ArenaSim = Arena.sim
	for hero in sim.heroes: hero["cool"] = 1.0e9
	if wave:
		sim.begin_wave(1)
	sim._spawn_t = 1.0e9
	sim.monsters.clear()
	Arena.gold = 1000
	return sim

## A body of the stage's first wave, standing still on the road nearest `at`, too tough to fall.
func _body(sim: ArenaSim, at: Vector2) -> Dictionary:
	sim._spawn(Arena.wave_spawns(Arena.stage, 1)[0]["m"])
	var mo: Dictionary = sim.monsters[sim.monsters.size() - 1]
	mo["pos"] = at if ArenaGeometry.on_road(at, Balance.ARENA_MONSTER_RADIUS) else ArenaGeometry.nearest_road_point(at)
	mo["hp"] = 1.0e6
	mo["max"] = 1.0e6
	mo["spd"] = 0.0
	sim._cache_positions()
	return mo

func _events(sim: ArenaSim, type: String) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool: return String(e.get("t", "")) == type)

func _block(sim: ArenaSim, id: String) -> String:
	return String(sim.skill_state(id)["block"])

## A refused cast changes nothing: gold, uses, cooldowns, the ward's shield, the monsters' health, events.
func _refused(sim: ArenaSim, id: String, at: Vector2, label: String) -> void:
	var gold: int = Arena.gold
	var uses: Dictionary = sim.skill_uses.duplicate()
	var cools: Dictionary = sim.skill_cooldowns.duplicate()
	var shield: float = sim.shield
	var hp: Array = []
	for mo in sim.monsters: hp.append(float(mo["hp"]))
	sim.events.clear()
	var cast := sim.cast_skill(id, at)
	var after: Array = []
	for mo in sim.monsters: after.append(float(mo["hp"]))
	check(not cast and Arena.gold == gold and sim.skill_uses == uses and sim.skill_cooldowns == cools and sim.shield == shield
		and hp == after and _events(sim, "arena_" + id).is_empty(), label)

## The last wave's boss falls: the stage's clear beat begins.
func _boss_down(sim: ArenaSim) -> void:
	sim.jump_to_boss()
	var guard := 0
	while not sim.boss_spawned and guard < 600:
		guard += 1
		sim.step(DT)
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()

func _check_costs() -> void:
	var sim := _fight(52001)
	check(sim.skill_cost("blast") == Balance.ARENA_BLAST_GOLD and sim.skill_cost("freeze") == Balance.ARENA_FREEZE_GOLD
		and sim.skill_cost("ward") == Balance.ARENA_WARD_GOLD and sim.skill_cost("nothing") == 0,
		"스킬마다 고정 골드 (폭발 %d · 서리 %d · 방벽 %d G)" % [Balance.ARENA_BLAST_GOLD, Balance.ARENA_FREEZE_GOLD, Balance.ARENA_WARD_GOLD])
	check(Balance.ARENA_BLAST_GOLD > 0 and Balance.ARENA_FREEZE_GOLD > 0 and Balance.ARENA_WARD_GOLD > 0, "비용은 0 G 보다 큼")
	_body(sim, Balance.ARENA_CENTER + Vector2(220, 0))
	for id in SKILLS:
		var before: int = Arena.gold
		var cost := int(sim.skill_state(id)["cost"])
		sim.events.clear()
		var cast := sim.cast_skill(id)
		var fired := _events(sim, "arena_" + id)
		check(cast and cost == sim.skill_cost(id) and Arena.gold == before - cost and fired.size() == 1 and int(fired[0].get("cost", -1)) == cost
			and int(sim.skill_uses[id]) == 1, "%s: 쓰면 골드를 한 번 차감·이벤트에 비용·횟수 하나" % id)
	# Exactly enough is enough; one short is not.
	sim = _fight(52002)
	_body(sim, Balance.ARENA_CENTER + Vector2(220, 0))
	Arena.gold = Balance.ARENA_WARD_GOLD
	check(bool(sim.skill_state("ward")["ready"]) and sim.cast_skill("ward") and Arena.gold == 0, "골드가 딱 맞으면 쓰고 0 G")
	Arena.gold = Balance.ARENA_BLAST_GOLD - 1
	check(_block(sim, "blast") == "gold", "1 G 모자라면 「gold」")
	_refused(sim, "blast", Vector2.INF, "골드가 모자란 폭발은 거절·아무것도 쓰지 않음")
	# The constellation key skill_gold scales the price, and the state shows the scaled price.
	Arena.mods["skill_gold"] = 0.5
	check(sim.skill_cost("blast") == roundi(Balance.ARENA_BLAST_GOLD * 0.5) and int(sim.skill_state("blast")["cost"]) == sim.skill_cost("blast"),
		"별자리 효과 skill_gold 가 비용을 곱해 깎고 판정도 그 값을 씀")
	Arena.gold = sim.skill_cost("blast")
	check(sim.cast_skill("blast") and Arena.gold == 0, "깎인 비용으로 사용")
	Arena.mods.erase("skill_gold")

func _check_states() -> void:
	# The preparation phase: nothing comes and nothing is hurt, so the gold is kept for the wave.
	var sim := _fight(52003, false)
	_body(sim, Balance.ARENA_CENTER + Vector2(220, 0))
	check(sim.in_prep(), "첫 정비 시간")
	for id in SKILLS:
		check(_block(sim, id) == "prep", id + ": 정비 시간에는 「prep」")
		_refused(sim, id, Vector2.INF, id + ": 정비 중 사용 거절·아무것도 쓰지 않음")
	Arena.gold = 0
	sim.skill_cooldowns["blast"] = 5.0
	check(_block(sim, "blast") == "prep" and _block(sim, "ward") == "prep", "정비가 쿨타임·골드 부족보다 먼저")
	sim.skill_cooldowns["blast"] = 0.0
	Arena.gold = 1000
	# The wave: all three ready, with every field the HUD draws.
	sim.begin_wave(1)
	sim._spawn_t = 1.0e9
	for id in SKILLS:
		var state := sim.skill_state(id)
		check(bool(state["ready"]) and String(state["block"]) == "" and float(state["cooldown"]) == 0.0
			and is_equal_approx(float(state["max_cooldown"]), sim.skill_max_cooldown(id)) and int(state["uses_left"]) == sim.skill_max_uses(id)
			and int(state["uses_max"]) == sim.skill_max_uses(id) and int(state["cost"]) == sim.skill_cost(id),
			id + ": 웨이브 중 준비 완료·HUD 칸(비용·쿨타임·횟수)")
	# Nobody on the field: the starburst and the frost have nothing to hit; the ward still guards.
	var keep: Array = sim.monsters.duplicate()
	sim.monsters.clear()
	check(_block(sim, "blast") == "no_target" and _block(sim, "freeze") == "no_target" and _block(sim, "ward") == "",
		"몬스터가 없으면 폭발·서리 「no_target」·방벽은 준비")
	_refused(sim, "blast", Vector2.INF, "대상 없는 폭발은 거절·아무것도 쓰지 않음")
	_refused(sim, "freeze", Vector2.INF, "대상 없는 서리는 거절·아무것도 쓰지 않음")
	Arena.gold = 0
	check(_block(sim, "freeze") == "no_target" and _block(sim, "ward") == "gold", "대상 없음이 골드 부족보다 먼저·방벽은 「gold」")
	_refused(sim, "ward", Vector2.INF, "골드가 모자란 방벽은 거절")
	Arena.gold = 1000
	for mo in keep: sim.monsters.append(mo)
	sim._cache_positions()
	# Cast: cooling down, then ready again; every use spent: spent.
	check(sim.cast_skill("freeze"), "서리 사용")
	var state := sim.skill_state("freeze")
	check(String(state["block"]) == "cooldown" and is_equal_approx(float(state["cooldown"]), float(state["max_cooldown"]))
		and int(state["uses_left"]) == sim.skill_max_uses("freeze") - 1, "쓴 뒤 「cooldown」·남은 초·횟수 하나 줄어듦")
	_refused(sim, "freeze", Vector2.INF, "쿨타임 중 사용 거절·아무것도 쓰지 않음")
	Arena.gold = 0
	check(_block(sim, "freeze") == "cooldown", "쿨타임이 골드 부족보다 먼저")
	Arena.gold = 1000
	var left := float(sim.skill_cooldowns["freeze"])
	for i in range(30): sim._tick(DT)
	check(absf(float(sim.skill_state("freeze")["cooldown"]) - (left - 0.5)) < 0.01, "쿨타임은 전투 시간으로 줄어듦")
	sim.skill_cooldowns["freeze"] = 0.0
	check(_block(sim, "freeze") == "", "쿨타임이 끝나면 다시 준비")
	sim.skill_uses["freeze"] = sim.skill_max_uses("freeze")
	check(_block(sim, "freeze") == "spent" and int(sim.skill_state("freeze")["uses_left"]) == 0, "횟수를 다 쓰면 「spent」")
	_refused(sim, "freeze", Vector2.INF, "다 쓴 스킬은 거절")
	Arena.gold = 0
	check(_block(sim, "freeze") == "spent", "다 쓴 것이 대상·골드보다 먼저")
	Arena.gold = 1000
	# A window over the battle.
	check(Arena.open_modal("bench") and _block(sim, "blast") == "inactive" and _block(sim, "ward") == "inactive", "창이 열려 있으면 「inactive」")
	_refused(sim, "ward", Vector2.INF, "창이 열린 동안 사용 거절")
	Arena.close_modal()
	check(_block(sim, "ward") == "", "창을 닫으면 다시 준비")
	# The boss down: the clear beat holds every skill; then the stage is over.
	_boss_down(sim)
	check(sim.clear_t > 0.0 and _block(sim, "blast") == "clearing" and _block(sim, "ward") == "clearing", "돌파 연출 중에는 「clearing」")
	_refused(sim, "ward", Vector2.INF, "돌파 연출 중 사용 거절")
	for i in range(ceili(sim.clear_t * 60.0) + 2): sim._tick(DT)
	check(sim.done and not Arena.running and _block(sim, "ward") == "inactive" and _block(sim, "blast") == "inactive", "판이 끝나면 「inactive」")
	_refused(sim, "ward", Vector2.INF, "끝난 판에서 사용 거절")
	_reset_ladder()

func _check_aimed_blast() -> void:
	var sim := _fight(52005)
	var radius := sim.blast_radius()
	check(is_equal_approx(radius, Balance.ARENA_BLAST_RADIUS), "폭발 반경은 표의 값(별자리 없이)")
	# Around a tapped point: a body inside, one whose edge just reaches in, one just out of reach; and one
	# right by the crystal, far from the point.
	var at := Balance.ARENA_CENTER + Vector2(-260, 150)
	var inside := _body(sim, at)
	var edge := _body(sim, at)
	var outside := _body(sim, at)
	var guard := _body(sim, Balance.ARENA_CENTER + Vector2(Balance.ALTAR_R + 40.0, 0))
	inside["pos"] = at + Vector2(12, 0)
	edge["pos"] = at + Vector2(0, radius + BattleSim.hit_radius(edge) - 1.0)
	outside["pos"] = at - Vector2(radius + BattleSim.hit_radius(outside) + 4.0, 0)
	sim._cache_positions()
	var gold: int = Arena.gold
	sim.events.clear()
	check(sim.cast_skill("blast", at), "누른 곳에 폭발")
	check(float(inside["hp"]) < 1.0e6 and float(edge["hp"]) < 1.0e6, "반경 안의 몬스터와 몸 가장자리가 닿는 몬스터는 맞음")
	check(float(outside["hp"]) == 1.0e6 and float(guard["hp"]) == 1.0e6, "닿지 않는 몬스터와 수정 앞의 먼 몬스터는 안 맞음")
	var fired := _events(sim, "arena_blast")
	check(fired.size() == 1 and Vector2(fired[0]["p"]) == at and is_equal_approx(float(fired[0]["r"]), radius)
		and int(fired[0]["cost"]) == Balance.ARENA_BLAST_GOLD and Arena.gold == gold - Balance.ARENA_BLAST_GOLD, "폭발 이벤트: 누른 곳·반경·비용")
	# Outside the arena: refused, nothing spent.
	sim.skill_cooldowns["blast"] = 0.0
	var beyond := Balance.ARENA_CENTER + Vector2(ArenaGeometry.RADIUS + 30.0, 0)
	check(not ArenaGeometry.contains(beyond), "판 밖의 점")
	_refused(sim, "blast", beyond, "판 밖을 누른 폭발은 거절·아무것도 쓰지 않음")
	# No point: the body nearest the crystal.
	var guard_hp := float(guard["hp"])
	sim.events.clear()
	check(sim.cast_skill("blast") and float(guard["hp"]) < guard_hp and Vector2(_events(sim, "arena_blast")[0]["p"]) == Vector2(guard["pos"]),
		"자리를 주지 않으면 수정에 가장 가까운 몬스터에 떨어짐")
	# Frost and ward take no point: a point outside the arena does not stop them.
	sim.events.clear()
	check(sim.cast_skill("freeze", beyond) and sim.cast_skill("ward", beyond) and Vector2(_events(sim, "arena_ward")[0]["p"]) == Balance.ARENA_CENTER,
		"서리·방벽은 누른 곳과 상관없음")
	# The constellation's 「넓은 유성」 widens it, and the hit test follows.
	Arena.mods = Talents.effects({"star_wide": 1})
	var wide := sim.blast_radius()
	check(wide > radius and is_equal_approx(wide, Balance.ARENA_BLAST_RADIUS * Talents.mult(Arena.mods, "blast_r")), "넓은 유성이 반경을 넓힘 (%.0f → %.0f)" % [radius, wide])
	var hp := float(outside["hp"])
	outside["pos"] = at - Vector2(wide + BattleSim.hit_radius(outside) - 1.0, 0)
	sim._cache_positions()
	sim.skill_cooldowns["blast"] = 0.0
	sim.events.clear()
	check(sim.cast_skill("blast", at) and float(outside["hp"]) < hp and is_equal_approx(float(_events(sim, "arena_blast")[0]["r"]), wide), "넓어진 반경으로 맞히고 이벤트도 그 반경")
	Arena.mods = {}

func _check_saves() -> void:
	var sim := _fight(52006)
	_body(sim, Balance.ARENA_CENTER + Vector2(220, 0))
	check(sim.cast_skill("blast") and sim.cast_skill("ward"), "두 스킬 사용")
	sim.skill_uses["freeze"] = sim.skill_max_uses("freeze")
	Arena.gold = Balance.ARENA_FREEZE_GOLD - 1
	var states := {}
	for id in SKILLS: states[id] = sim.skill_state(id)
	var saved := Arena.snapshot()
	check(ArenaValidation.valid(saved) and Arena.restore(saved), "스킬을 쓴 판 저장·복구")
	sim = Arena.sim
	var same := true
	for id in SKILLS: same = same and sim.skill_state(id) == states[id]
	check(same and Arena.gold == Balance.ARENA_FREEZE_GOLD - 1, "복구 뒤 스킬 판정(쿨타임·횟수·비용·막힌 까닭)이 같음")
	check(_block(sim, "blast") == "cooldown" and _block(sim, "freeze") == "spent" and _block(sim, "ward") == "cooldown", "복구한 판의 막힌 까닭")
