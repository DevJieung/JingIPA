extends Harness

## 성장 회귀 검사 — 별이 영웅 한 장의 세기가 되는가 · 합성 보장 · 각성 · 전투 중간 지원.
##
##   godot --headless --path . res://tests/progression_check.tscn
##
## ★ 포커 시절에는 여기서 7,462가지 문장 값과 키커 비교를 재서 「같은 족보라도 높은 숫자가
##   더 세다」를 지켰다. 그 값(value · value_mult · variant)은 규칙에서 통째로 없어졌다 —
##   지금 영웅의 세기를 정하는 것은 **등급(별) 하나와 각성 위력**뿐이다. 그래서 같은 자리에
##   「별이 실제 화력으로 이어지는가」 · 「옛 문장 값이 되살아나지 않는가」를 둔다.
## ★ 등급 표 · 각성 위력의 숫자는 Balance 에서 읽는다.


func _ready() -> void:
	if not require_no_save():
		return
	check_tier_ladder()
	check_draw_and_save()
	check_fusion_growth()
	check_repeated_awakening()
	check_support("promote")
	check_support("summon")
	check_support("summon", ["joker", "eye"])
	check_support_rite()
	check_top_promotion()
	finish("별 등급·합성 보장·중간 지원 회귀 검사")


## 반 별 한 칸이 언제나 값을 한다 — 누구에게든, 어느 칸에서든.
##
## ★ 의식은 온 별(홀수 칸)만 주고, 그 사이의 반 별은 승급과 합성으로만 오른다. 그러니
##   열 칸이 **전부** 아래 칸보다 세야 승급 한 번 · 합성 한 번이 헛일이 되지 않는다.
func check_tier_ladder() -> void:
	Fixture.fresh(6100)
	for unit in Roster.UNITS:
		var last := 0.0
		for tier in range(Balance.TIER_MAX + 1):
			var dps := Run.hero_dps({"unit": unit, "tier": tier, "wave": 1, "n": 1})
			check(dps > last, "every half star raises %s's real DPS (tier %d)" % [unit["id"], tier])
			last = dps
	# 각성 위력은 등급 위에 그대로 곱해진다.
	var plain := {"unit": Roster.UNITS[0], "tier": Balance.TIER_MAX, "wave": 1, "n": 1}
	var awakened := plain.duplicate(true)
	awakened["awakened"] = true
	awakened["awakening_mult"] = Balance.AWAKEN_BASE
	check(is_equal_approx(Run.hero_dps(awakened), Run.hero_dps(plain) * Balance.AWAKEN_BASE),
			"awakening power multiplies the hero's real DPS")
	check(Balance.AWAKEN_BASE > 1.0 and Balance.awaken_step(Balance.AWAKEN_BASE) > Balance.AWAKEN_BASE,
			"awakening starts above 1.0 and every step raises it")
	check(absf(Balance.awaken_step(Balance.AWAKEN_BASE) - (Balance.AWAKEN_BASE + Balance.AWAKEN_STEP)) < 0.0051,
			"one awakening step adds the step (to two decimals)")
	# 0.15 를 수십 번 더해도 소수 둘째 자리에서 흔들리지 않아야 저장한 값과 계산한 값이 같다.
	var power := Balance.AWAKEN_BASE
	for i in range(40):
		power = Balance.awaken_step(power)
		check(is_equal_approx(power * 100.0, roundf(power * 100.0)), "awakening power stays on two decimals (%d)" % i)


func check_draw_and_save() -> void:
	var last_dps := 0.0
	var drawn := ""
	for stars in range(Rite.MIN_STARS, Rite.MAX_STARS + 1):
		Fixture.fresh(6106)
		Fixture.stack(stars)
		var result := Run.confirm_summon()
		var h: Dictionary = Run.heroes[0]
		# 같은 씨앗이라 같은 캐릭터가 뽑힌다 — 별 수는 「누구인가」를 바꾸지 않는다.
		if drawn == "":
			drawn = String(h["unit"]["id"])
		check(String(h["unit"]["id"]) == drawn, "the star count decides how strong, never who (%d)" % stars)
		check(int(h["tier"]) == Rite.tier_of(stars) and int(result["tier"]) == int(h["tier"]) and h["unit"] == result["unit"],
				"the stars inside the gate reach the awarded hero (%d)" % stars)
		check(not h.has("value") and not h.has("variant") and not result.has("value") and not result.has("hand")
				and not result.has("cards"), "no poker value rides on the hero or the result")
		var dps := Run.hero_dps(h)
		check(dps > last_dps, "one more star in the gate increases the deployed hero's real DPS (%d)" % stars)
		last_dps = dps
		# 옛 문장 값이 붙어 있어도 화력은 한 톨도 안 달라진다(읽는 곳이 없어야 한다).
		var haunted: Dictionary = h.duplicate(true)
		haunted["value"] = {"hand": 9, "ranks": [14, 13, 12, 11, 10], "key": "9:14-13-12-11-10", "value_mult": 9.0}
		haunted["variant"] = "9:14-13-12-11-10"
		check(Run.hero_stats(haunted) == Run.hero_stats(h), "a leftover poker value cannot change combat power")
		var snapshot := Run.snapshot()
		check(Run.restore(snapshot) and Run.snapshot() == snapshot, "the hero's tier and the rite result survive save and resume")
		check(Run.last_tier == int(result["tier"]) and Run.last_result["orbit"] == result["orbit"]
				and int(Run.last_result["stars"]) == stars, "the confirmed rite is restored as it was")
		# 저장에 섞여 들어온 옛 값은 되돌릴 때 버려진다.
		var tainted := snapshot.duplicate(true)
		tainted["heroes"][0]["value"] = haunted["value"]
		tainted["heroes"][0]["variant"] = haunted["variant"]
		if Run.restore(tainted):
			check(not Run.heroes[0].has("value") and not Run.heroes[0].has("variant")
					and is_equal_approx(Run.hero_dps(Run.heroes[0]), dps), "a poker value smuggled into a save is dropped on restore")
		check(Run.restore(snapshot), "clean save restores again")
		# 손상된 등급 · 각성 위력은 전투에 들어오지 못하고, 돌고 있는 판도 건드리지 못한다.
		for damage in [["t", Balance.TIER_MAX + 1], ["t", -1], ["t", 1.5], ["t", "5"],
				["awakening_mult", NAN], ["awakening_mult", INF], ["awakening_mult", 0.5], ["awakening_mult", "2"],
				["awakened", "yes"], ["n", 0], ["w", 0]]:
			var bad := snapshot.duplicate(true)
			bad["heroes"][0][damage[0]] = damage[1]
			check(not Run.restore(bad) and Run.snapshot() == snapshot,
					"corrupt hero power cannot poison combat or overwrite the running save: " + str(damage))


func check_fusion_growth() -> void:
	for top in range(Balance.TIER_MAX + 1):
		Fixture.fresh(6160 + top, 1)
		# 재료 다섯 장 — 한 장만 등급 `top`, 나머지는 가장 낮은 칸. 캐릭터는 서로 달라도 된다.
		for i in range(5):
			Run.gain_hero(Roster.UNITS[10 + i], top if i == 0 else 0, false, false)
		Run.phase = Run.Phase.SHOP
		var codes: Array = []
		for i in range(5):
			codes.append(Run.FUSION_BENCH + i)
		var floor_tier := mini(Balance.TIER_MAX, top + 1)
		check(Run.fusion_min_tier(Run.fusion_materials(codes)) == floor_tier, "the floor is one step above the best material")
		var odds := Run.fusion_probabilities(codes)
		var total := 0.0
		for tier in range(odds.size()):
			total += odds[tier]
			if tier < floor_tier:
				check(odds[tier] == 0.0, "mixed materials never downgrade the highest material")
		check(odds.size() == Balance.TIER_MAX + 1 and is_equal_approx(total, 1.0), "fusion odds cover every tier and total 100 percent")
		var before := Run.snapshot()
		var result := Run.fuse_heroes(codes)
		check(result["tier"] >= floor_tier and not result["failed"], "fusion guarantees at least half a star of promotion")
		check(Roster.unit_by_id(result["unit"]).get("fusion_only", false), "fusion awards its exclusive roster")
		check(float(result["awakening_mult"]) >= Balance.AWAKEN_BASE and bool(result["awakened"]),
				"a fused guardian starts with awakening power")
		var fused: Dictionary = {}
		for h in Run.heroes + Run.bench:
			if String(h["unit"]["id"]) == String(result["unit"]):
				fused = h
		check(not fused.is_empty() and int(fused["tier"]) == int(result["tier"])
				and is_equal_approx(float(fused["awakening_mult"]), float(result["awakening_mult"])),
				"the fused hero card carries the announced tier and power")
		check(not fused.has("value") and not result.has("value") and not result.has("variant"), "fusion inherits no poker value")
		check(Save.best_of(String(result["unit"])) >= int(result["tier"]), "the codex remembers the fused guardian's tier")
		check(Run.restore(Run.snapshot()), "exclusive hero and pending result survive restart")
		Run.accept_fusion()
		check(Run.hero_total() == before["heroes"].size() + before["bench"].size() - 4, "accepted fusion consumes exactly five materials for one guardian")
	# 의식(과 지원 소환)이 뽑는 쪽에는 합성 전용 수호자가 절대 안 섞인다.
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	for i in range(300):
		check(not Roster.pick_unit(rng).get("fusion_only", false), "normal draws never award exclusive awakened heroes")


func check_repeated_awakening() -> void:
	Fixture.fresh(6280, 1)
	Run.best_tier = Balance.TIER_MAX
	# 이미 한 걸음 각성한 5성 재료 다섯 장.
	var held := Balance.awaken_step(Balance.AWAKEN_BASE)
	for i in range(5):
		Run.gain_hero(Roster.fusion_units(Balance.TIER_MAX)[0], Balance.TIER_MAX, false, false,
			{"awakened": true, "awakening_mult": held})
	Run.phase = Run.Phase.SHOP
	var codes: Array = []
	for i in range(5):
		codes.append(Run.FUSION_BENCH + i)
	var result := Run.fuse_heroes(codes)
	check(result["tier"] == Balance.TIER_MAX and is_equal_approx(float(result["awakening_mult"]), Balance.awaken_step(held)),
			"highest-star awakened materials still guarantee growth")
	var snapshot := Run.snapshot()
	var encoded := ConfigFile.new()
	encoded.set_value("cur", "state", snapshot)
	var decoded := ConfigFile.new()
	var parsed := decoded.parse(encoded.encode_to_text()) == OK
	var restored := Run.restore(decoded.get_value("cur", "state")) if parsed else false
	var after := Run.snapshot()
	check(parsed and restored and after == snapshot, "repeated awakening survives disk serialization exactly")

	Run.accept_fusion()
	check(Run.fusion_pending.is_empty() and Run.hero_total() == 2, "awakened result remains after accepting fusion")


## 전투 한가운데의 지원 — 승급(반 별) 또는 소환(의식 한 번). 어느 쪽이든 한 탄에 한 번이다.
func check_support(choice: String, passives: Array = []) -> void:
	Fixture.fresh(6210, 1)
	Fixture.stack(1)
	Run.owned_passives.assign(passives)
	Run.passives.assign(passives)
	Run.phase = Run.Phase.SWAP
	Run.prepare_battle()
	Run.lives = 1000 # Isolate support transaction from the combat balance.
	var sim := BattleSim.new()
	sim.setup(Run, Run.wave)
	sim.support_enabled = true
	while not sim.support_pending and not sim.done and sim.elapsed < 40.0:
		sim.step(0.02)
		sim.events.clear()
	check(sim.support_pending and sim.elapsed >= 30.0 and not sim._queue.is_empty(), "midpoint opens before the second assault")
	var elapsed := sim.elapsed
	var population := sim.monsters.duplicate(true)
	sim.step(3.0)
	check(sim.elapsed == elapsed and sim.monsters == population, "support freezes combat, projectiles and spawn time")
	check(sim.resolve_support("invalid").is_empty() and sim.support_pending, "invalid choices do not consume support")
	var old_tier: int = Run.heroes[0]["tier"]
	var old_count := Run.hero_total()
	var rite_before: Dictionary = Run.snapshot()["rite"]
	Run.gold += 200
	Run.kills += 5
	var gold_before := Run.gold
	var support := sim.resolve_support(choice, 0)
	check(not support.is_empty() and sim.support_used and not sim.support_pending, "valid choice resumes the same assault")
	check(Run.gold == gold_before, "support is free")
	if choice == "promote":
		check(Run.heroes[0]["tier"] == old_tier + 1 and sim.heroes[0]["atk"] == Run.hero_stats(Run.heroes[0])["atk"],
			"half-star promotion updates live attacks without recreating combat")
		check(int(support["before_tier"]) == old_tier and int(support["tier"]) == old_tier + 1 and Run.hero_total() == old_count,
			"promotion reports the step and grants no extra hero")
	else:
		# 지원 소환은 **한 번 돌린 그대로** 받는다 — 다시 돌리기도, 조커도, 눈도, 광고도 없다.
		var orbit: Array = support["orbit"]
		var stars := int(support["stars"])
		check(Run.hero_total() == old_count + 1 and orbit.size() == Rite.RINGS and Rite.valid(orbit),
				"support summons one free hero through a single rite")
		check(stars == Rite.stars(orbit) and int(support["tier"]) == Rite.tier_of(stars) and int(support["tier"]) % 2 == 1,
				"the support rite grants exactly the stars that stopped inside the gate")
		var group: Array = Run.heroes if String(support["where"]) == "field" else Run.bench
		var hero: Dictionary = group[int(support["slot"])]
		check(hero["unit"] == support["unit"] and int(hero["tier"]) == int(support["tier"])
				and not hero.has("value") and not bool(support["unit"].get("fusion_only", false)),
				"the supported hero card carries that tier and nothing else")
		check(Save.best_of(String(support["unit"]["id"])) >= int(support["tier"]), "the codex remembers the supported hero")
	# 이 탄의 의식(이미 확정한 별 자리와 횟수)은 지원이 건드리지 않는다.
	check(Run.snapshot()["rite"] == rite_before, "support leaves the wave's own rite and its re-spin counts untouched")
	check(Run.claim_midpoint_support(choice, 0).is_empty(), "support cannot be claimed twice")
	var saved := Save.cur_run.duplicate(true)
	check(saved["gold"] == Balance.START_GOLD and saved["kills"] == 0, "support save does not duplicate battle gold or kills")
	check(Run.restore(saved) and Run.support_wave == Run.wave, "claimed growth survives restart")
	check(Run.hero_total() == (old_count + 1 if choice == "summon" else old_count)
			and (choice != "promote" or int(Run.heroes[0]["tier"]) == old_tier + 1), "the restart keeps exactly the one claimed reward")
	var resumed := BattleSim.new()
	resumed.setup(Run, Run.wave)
	resumed.support_enabled = true
	check(resumed.support_used and Run.claim_midpoint_support(choice, 0).is_empty(), "restarting the stage cannot duplicate support")


## 지원 소환은 **한 번 돌린 그대로**다 — 조커와 눈을 다 들고 수백 번을 받아도 반 별이 한 번도
## 없고, 별 수의 분포가 「한 번 돌렸을 때」의 표(Rite.odds(1))와 맞는다.
##
## ★ 포커 시절의 지원 소환은 「카드 다섯 장을 한 번 받아 그대로 판정」이었다. 그 뜻이 이것이다.
##   누가 여기에 다시 돌리기나 조커를 얹으면 1성이 사라지거나 분포가 위로 쏠려서 걸린다.
func check_support_rite() -> void:
	Fixture.fresh(6212, 1)
	Run.owned_passives.assign(["joker", "eye"])
	Run.passives.assign(["joker", "eye"])
	Fixture.stack(1)
	Run.phase = Run.Phase.SWAP
	Run.prepare_battle()
	var rite_before: Dictionary = Run.snapshot()["rite"]
	var rounds := 400
	var counts := [0, 0, 0, 0, 0, 0]
	for i in range(rounds):
		Run.support_available = true
		Run.support_wave = -1
		var total := Run.hero_total()
		var support := Run.claim_midpoint_support("summon")
		var orbit: Array = support.get("orbit", [])
		var stars := int(support.get("stars", 0))
		check(Rite.valid(orbit) and stars == Rite.stars(orbit) and int(support.get("tier", -1)) == Rite.tier_of(stars)
				and Run.hero_total() == total + 1, "each support rite grants one hero at exactly its whole stars")
		counts[clampi(stars, 0, Rite.MAX_STARS)] += 1
	var odds := Rite.odds(1)
	for stars in range(Rite.MIN_STARS, Rite.MAX_STARS + 1):
		var want: float = odds[stars] * rounds
		var slack := 5.0 * sqrt(rounds * odds[stars] * (1.0 - odds[stars])) + 1.0
		check(absf(float(counts[stars]) - want) <= slack,
				"support summons follow the single-spin odds: %d stars %d times (expected %.1f)" % [stars, counts[stars], want])
	check(Run.snapshot()["rite"] == rite_before, "hundreds of support rites never touch the wave's own rite")


## 5성에서의 승급은 등급을 올리지 못한다 — 대신 각성 위력이 한 걸음 오른다.
func check_top_promotion() -> void:
	Fixture.fresh(6211, 0)
	Run.gain_hero(Roster.UNITS[0], Balance.TIER_MAX, false)
	Run.phase = Run.Phase.SWAP
	Run.prepare_battle()
	var before_dps := Run.hero_dps(Run.heroes[0])
	var power := 1.0
	for step in range(2):
		Run.support_available = true
		Run.support_wave = -1
		var result := Run.claim_midpoint_support("promote", 0)
		power = Balance.awaken_step(power)
		check(not result.is_empty() and int(Run.heroes[0]["tier"]) == Balance.TIER_MAX
				and is_equal_approx(float(Run.heroes[0]["awakening_mult"]), power),
				"promotion at five stars raises awakening power instead of the tier (%d)" % step)
		check(is_equal_approx(Run.hero_dps(Run.heroes[0]), before_dps * power), "that power reaches the hero's real DPS")
	var saved := Save.cur_run.duplicate(true)
	check(RunValidation.valid(saved, Run.SAVE_VERSION) and Run.restore(saved)
			and is_equal_approx(float(Run.heroes[0]["awakening_mult"]), power), "promoted power survives restart")
