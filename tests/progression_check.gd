extends Harness


func hand(ranks: Array, suits: Array = [0, 1, 2, 3, 0]) -> Array:
	var out: Array = []
	for i in range(5):
		out.append(Poker.code(int(ranks[i]), int(suits[i])))
	return out


func _ready() -> void:
	if not require_no_save():
		return
	for pair in [
		[[14, 14, 9, 6, 3], [13, 13, 14, 12, 10]], # primary pair
		[[9, 9, 14, 8, 2], [9, 9, 14, 7, 6]], # second kicker
		[[13, 13, 5, 5, 2], [12, 12, 11, 11, 14]],
		[[9, 9, 9, 8, 2], [9, 9, 9, 7, 6]],
		[[6, 5, 4, 3, 2], [14, 2, 3, 4, 5]], # wheel
		[[12, 12, 12, 8, 8], [12, 12, 12, 7, 7]],
		[[9, 9, 9, 9, 14], [9, 9, 9, 9, 13]],
		[[14, 10, 8, 5, 3], [14, 10, 8, 5, 2]]]:
		var stronger := hand(pair[0])
		var weaker := hand(pair[1])
		check(Poker.compare(stronger, weaker) == 1 and Poker.compare(weaker, stronger) == -1,
			"rank and all kicker positions order correctly")
		check(float(Poker.detail(stronger)["value_mult"]) > float(Poker.detail(weaker)["value_mult"]),
			"card value contributes to actual combat power")
	for rank in range(2, 15):
		var cards := hand([rank, rank, 7 if rank != 7 else 8, 5 if rank != 5 else 6, 3 if rank != 3 else 4])
		var tie := cards.duplicate()
		tie.reverse()
		check(Poker.compare(cards, tie) == 0 and Poker.detail(cards)["key"] == Poker.detail(tie)["key"],
			"card order does not change the hero variant")
	check(Poker.compare(hand([14, 11, 8, 5, 2], [0, 0, 0, 0, 0]),
		hand([14, 11, 8, 5, 2], [1, 1, 1, 1, 1])) == 0, "suits never break a flush tie")
	check(Poker.detail([0, 0, 1, 2, 3]).is_empty(), "invalid hands cannot gain a value variant")
	check_draw_and_save()
	check_all_variants()
	check_fusion_growth()
	check_repeated_awakening()
	check_support("promote")
	check_support("summon")
	finish("상세 카드 가치·합성 보장·중간 지원 회귀 검사")


func check_all_variants() -> void:
	var keys := {}
	# Every legal rank multiset, plus same-suit variants for all distinct ranks.
	# This covers all 7,462 distinct five-card poker values, not just a sample.
	for a in range(2, 15):
		for b in range(a, 15):
			for c in range(b, 15):
				for d in range(c, 15):
					for e in range(d, 15):
						if a == e:
							continue
						var cards := hand([a, b, c, d, e], [0, 1, 2, 3, 0])
						var value := Poker.detail(cards)
						keys[value["key"]] = true
						if a < b and b < c and c < d and d < e:
							value = Poker.detail(hand([a, b, c, d, e], [0, 0, 0, 0, 0]))
							keys[value["key"]] = true
	check(keys.size() == 7462, "all 7,462 exact poker values have distinct character variants")


func check_draw_and_save() -> void:
	Fixture.fresh(6106)
	Run.cards.assign(hand([14, 14, 9, 6, 3]))
	var result := Run.confirm_hand()
	var h: Dictionary = Run.heroes[0]
	check(h["variant"] == "1:14-9-6-3" and h["value"] == result["value"], "all hand ranks reach the awarded hero")
	var plain: Dictionary = h.duplicate(true)
	plain.erase("value")
	check(Run.hero_dps(h) > Run.hero_dps(plain), "value increases the deployed hero's real DPS")
	var snapshot := Run.snapshot()
	check(Run.restore(snapshot) and Run.snapshot() == snapshot, "hero variant survives save and resume")
	var bad := snapshot.duplicate(true)
	bad["heroes"][0]["value"]["value_mult"] = NAN
	check(not Run.restore(bad), "corrupt value cannot poison combat or overwrite the running save")


func check_fusion_growth() -> void:
	for top in range(10):
		Fixture.fresh(6160 + top, 1)
		for i in range(5):
			Run.gain_hero(Roster.units_of_tier(top if i == 0 else 0)[0], top if i == 0 else 0, false, false)
		Run.phase = Run.Phase.SHOP
		var codes: Array = []
		for i in range(5):
			codes.append(Run.FUSION_BENCH + i)
		var odds := Run.fusion_probabilities(codes)
		for tier in range(mini(9, top + 1)):
			check(odds[tier] == 0.0, "mixed materials never downgrade the highest material")
		var before := Run.snapshot()
		var result := Run.fuse_heroes(codes)
		check(result["tier"] >= mini(9, top + 1) and not result["failed"], "fusion guarantees at least half a star of promotion")
		check(Roster.unit_by_id(result["unit"]).get("fusion_only", false), "fusion awards its exclusive roster")
		check(Run.restore(Run.snapshot()), "exclusive hero and undo window survive restart")
		check(Run.undo_fusion() and Run.snapshot()["heroes"] == before["heroes"] and Run.snapshot()["bench"] == before["bench"],
			"undo restores exact rank variants and protected deployed heroes")
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	for tier in range(10):
		for i in range(30):
			check(not Roster.pick_unit(tier, rng).get("fusion_only", false), "normal draws never award exclusive awakened heroes")


func check_repeated_awakening() -> void:
	Fixture.fresh(6280, 1)
	Run.best_hand = 9
	var value := Poker.detail(hand([14, 14, 9, 6, 3]))
	for i in range(5):
		Run.gain_hero(Roster.fusion_units(9)[0], 9, false, false,
			{"awakened": true, "awakening_mult": 1.50, "value": value, "variant": value["key"]})
	Run.phase = Run.Phase.SHOP
	var result := Run.fuse_heroes([100000, 100001, 100002, 100003, 100004])
	check(result["tier"] == 9 and result["awakening_mult"] == 1.65, "highest-star awakened materials still guarantee growth")
	var snapshot := Run.snapshot()
	var encoded := ConfigFile.new()
	encoded.set_value("cur", "state", snapshot)
	var decoded := ConfigFile.new()
	var parsed := decoded.parse(encoded.encode_to_text()) == OK
	var restored := Run.restore(decoded.get_value("cur", "state")) if parsed else false
	var after := Run.snapshot()
	check(parsed and restored and after == snapshot, "repeated awakening and exact kickers survive disk serialization")
	check(Run.undo_fusion(), "awakened materials can still be restored before acceptance")
	check(Run.bench[0]["value"] == value and Run.bench[0]["awakening_mult"] == 1.50,
		"undo preserves previous awakened power and the highest material's full value")


func check_support(choice: String) -> void:
	Fixture.fresh(6210, 1)
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
	Run.gold += 200
	Run.kills += 5
	var support := sim.resolve_support(choice, 0)
	check(not support.is_empty() and sim.support_used and not sim.support_pending, "valid choice resumes the same assault")
	if choice == "promote":
		check(Run.heroes[0]["tier"] == old_tier + 1 and sim.heroes[0]["atk"] == Run.hero_stats(Run.heroes[0])["atk"],
			"half-star promotion updates live attacks without recreating combat")
	else:
		check(Run.hero_total() == old_count + 1 and support["cards"].size() == 5, "support summons one free evaluated hero")
	check(Run.claim_midpoint_support(choice, 0).is_empty(), "support cannot be claimed twice")
	var saved := Save.cur_run.duplicate(true)
	check(saved["gold"] == Balance.START_GOLD and saved["kills"] == 0, "support save does not duplicate battle gold or kills")
	check(Run.restore(saved) and Run.support_wave == Run.wave, "claimed growth survives restart")
	var resumed := BattleSim.new()
	resumed.setup(Run, Run.wave)
	resumed.support_enabled = true
	check(resumed.support_used and Run.claim_midpoint_support(choice, 0).is_empty(), "restarting the stage cannot duplicate support")
