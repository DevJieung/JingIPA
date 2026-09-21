extends Harness

## 새 규칙 회귀 검사 — 발판 열둘 · 중복 출전 금지 · 옛 저장 이주 · 리롤 · 합성 · 보상.
##
##   godot --headless --path . res://tests/rules_check.tscn


func fresh(seed_value: int = 12345, count: int = 12) -> void:
	Fixture.fresh(seed_value, count)


func unique_field() -> bool:
	var ids := {}
	var posts := {}
	for hero in Run.heroes:
		if ids.has(hero["unit"]["id"]) or posts.has(hero["post"]) or int(hero["n"]) != 1:
			return false
		ids[hero["unit"]["id"]] = true
		posts[hero["post"]] = true
	return true


func _ready() -> void:
	if not require_no_save(2):
		return
	fresh()
	check(Run.heroes.size() == 12 and unique_field(), "all 12 posts can deploy unique heroes")
	var hero: Dictionary = Run.heroes[0].duplicate(true)
	var original_stats := Run.hero_stats(hero)
	Run.gain_hero(hero["unit"], int(hero["tier"]))
	check(Run.heroes.size() == 12 and Run.bench.size() == 1, "duplicate goes to reserve")
	check(not Run.swap_field_bench(1, 0), "cannot swap a duplicate onto another field slot")
	check(Run.swap_field_bench(0, 0) and unique_field(), "replace same character without duplicate deployment")
	check(Run.swap_field_bench(1, -1), "remove one hero")
	check(not Run.bench_to_field(0), "duplicate cannot deploy even when a post is empty")
	hero["n"] = 99
	check(Run.hero_stats(hero) == original_stats, "legacy stack count has no combat multiplier")
	Run.phase = Run.Phase.SHOP
	var state := Run.snapshot()
	check(RunValidation.valid(state, Run.SAVE_VERSION) and Run.restore(state), "new rules snapshot restores")
	var legacy := state.duplicate(true)
	legacy["heroes"][0]["n"] = 4
	legacy["bench"] = []
	legacy.erase("rules_v")
	legacy["cards"] = [0, 1, 2, 3, 4]
	legacy["rerolled"] = [0, 0, 0, 0, 0]
	legacy["paid"] = [0, 0, 0, 0, 0]
	legacy["at"] = [0, 0, 0, 0, 0]
	legacy["piles"] = []
	for slot in range(5):
		var pile: Array[int] = []
		for card in range(slot, 52, 5):
			pile.append(card)
		legacy["piles"].append(pile)
	var legacy_restored := Run.restore(legacy)
	check(legacy_restored and Run.hero_total() == legacy["heroes"].size() + 3 and unique_field(),
			"legacy stacks migrate to separate cards: restored=%s total=%d expected=%d unique=%s" % [legacy_restored, Run.hero_total(), legacy["heroes"].size() + 3, unique_field()])
	for reserved in Run.bench:
		check(int(reserved["n"]) == 1, "migrated copies remain single cards")
	Run.phase = Run.Phase.DRAW
	check(Run.cards.size() == 5 and Run.reroll(0), "v7 pile save migrates into unrestricted reroll")

	fresh(2394, 1)
	var seen := {}
	for iteration in range(512):
		var previous := Run.cards.duplicate()
		Run.gold = 100000
		Run.paid[0] = 0
		check(Run.reroll(0), "reroll available")
		check(not previous.has(Run.cards[0]) and Poker.evaluate(Run.cards) >= 0, "reroll excludes all visible cards")
		seen[Run.cards[0]] = true
	check(seen.size() == 48, "a slot reaches all cards outside the other four slots")
	Run.rerolled[0] = 0
	Run.gold = 0
	check(Run.can_reroll(0), "free card replacement remains available without gold")
	Run.rerolled[0] = Run.free_rerolls()
	var cost := Run.reroll_cost_of(0)
	var unchanged := Run.cards.duplicate()
	for balance in [0, cost - 1, cost]:
		Run.gold = balance
		check(Run.can_reroll(0) == (balance >= cost), "paid replacement requires enough gold")
		check(Run.can_choose_card(0), "direct card choice remains available independently of paid rerolls")
	check(Run.reroll(0) and Run.gold == 0, "paid replacement can spend the last gold")
	unchanged = Run.cards.duplicate()
	check(not Run.reroll(0) and Run.cards == unchanged, "exhausted funds block further paid replacement")
	var exhausted := Run.snapshot()
	check(Run.restore(exhausted) and not Run.can_reroll(0), "resumed exhausted draw preserves replacement limits")
	check(Run.can_choose_card(0), "resuming a draw preserves direct card choice")
	check_card_choices()
	check_fusion_duplicates()
	check_fusion_deployed_guard()
	check_repeated_fusion_undo()
	check(is_equal_approx(Balance.elem_mult("elec", "wood"), 0.5), "electric attacks deal half damage to wood")
	check(is_zero_approx(Balance.elem_mult("elec", "rock")), "rock electric immunity preserved")

	var previous_odds := Balance.fusion_probabilities(5)
	for score in range(6, 51):
		var odds := Balance.fusion_probabilities(score)
		var total := 0.0
		for value in odds:
			total += value
		check(is_equal_approx(total, 1), "fusion odds total 100 percent")
		for threshold in range(1, 10):
			var old_tail := 0.0
			var new_tail := 0.0
			for tier in range(threshold, 10):
				old_tail += previous_odds[tier]
				new_tail += odds[tier]
			check(new_tail >= old_tail - 0.000001, "rarer materials raise upper-tier probability")
		previous_odds = odds
	var found_failure := false
	for attempt in range(32):
		fresh(708 + attempt, 1)
		var rare: Dictionary = Roster.units_of_tier(9)[0]
		for i in range(7):
			Run.gain_hero(rare, 9, false)
		Run.phase = Run.Phase.SHOP
		var codes: Array[int] = []
		for i in range(5):
			codes.append(Run.FUSION_BENCH + i)
		var before := Run.snapshot()
		var count_before := Run.hero_total()
		var result := Run.fuse_heroes(codes)
		check(not result.is_empty() and Run.hero_total() == count_before - 4, "five cards consumed for exactly one hero")
		check(Run.fuse_heroes(codes).is_empty(), "pending fusion cannot run twice")
		check(unique_field(), "fusion respects one character per battlefield")
		var pending := Run.snapshot()
		check(RunValidation.valid(pending, Run.SAVE_VERSION) and Run.restore(pending), "pending fusion survives restart")
		if bool(result["failed"]):
			found_failure = true
			var undo := {"fusion_id": result["id"], "seed": Run.run_seed, "wave": Run.wave}
			check(Run.apply_ad_reward("fusion_undo", undo), "failed fusion can be undone by reward")
			var restored := Run.snapshot()
			check(restored["heroes"] == before["heroes"] and restored["bench"] == before["bench"], "undo removes result and restores exact materials and posts")
			check(not Run.apply_ad_reward("fusion_undo", undo), "fusion refund cannot be claimed twice")
			break
		Run.accept_fusion()
	check(found_failure, "failure path exercised")

	fresh(816, 12)
	Run.phase = Run.Phase.SWAP
	Run.kills = 17
	Run.prepare_battle()
	var checkpoint := Run.snapshot()
	Run.gold += 200
	Run.kills += 20
	Run.add_lives(-Run.max_lives())
	check(Run.phase == Run.Phase.OVER and not Run.running, "defeat remains eligible for a continue")
	var defeat := Run.snapshot()
	check(RunValidation.valid(defeat, Run.SAVE_VERSION) and Run.restore(defeat), "defeat and checkpoint survive restart")
	check(Run.apply_ad_reward("continue", {}), "reward revives the failed wave")
	check(Run.wave == checkpoint["wave"] and Run.lives == Run.max_lives() and Run.running, "same wave returns with full crystals")
	check(Run.kills == 17 and Run.gold == checkpoint["gold"], "failed-wave gold and kills are rolled back")
	check(Run.continue_used and Run.phase == Run.Phase.SWAP and int(Run.last_result["hand"]) == 9 and unique_field(), "max-tier reward preserves a valid formation")
	check(Run.snapshot()["heroes"] == checkpoint["heroes"] and Run.bench.size() == checkpoint["bench"].size() + 1,
			"revive reserves the reward without replacing any deployed hero")
	check(Run.last_result["where"] == "bench" and Run.last_result["reward_pending"], "reward identity and unconfirmed reveal are saved")
	check(RunValidation.valid(Run.snapshot(), Run.SAVE_VERSION), "revived formation is persistable")
	check(Run.acknowledge_revive_reward(), "reward can be acknowledged before deploying")
	Run.prepare_battle()
	Run.add_lives(-Run.max_lives())
	check(not Run.reward_allowed("continue"), "continue limited to once per run")
	var kills_before := Save.total_kills
	Run.finish_defeat()
	Run.finish_defeat()
	check(Save.total_kills == kills_before + Run.kills, "run statistics settle only once")
	check_revive_reserve()

	fresh(715, 2)
	Run.phase = Run.Phase.SHOP
	Run.lives = 3
	check(Run.apply_ad_reward("crystal", {}) and Run.lives == Run.max_lives(), "crystal reward fully restores health")
	check(not Run.apply_ad_reward("crystal", {}), "full health cannot claim another heal")
	Run.phase = Run.Phase.BATTLE
	var sim := BattleSim.new()
	sim.setup(Run, Run.wave)
	sim.monsters.clear()
	sim._spawn(Roster.MONSTERS[0])
	sim._spawn(Roster.MONSTERS[0])
	sim.monsters[0]["s"] = 140.0
	sim.monsters[1]["s"] = 1500.0
	sim._cache_positions()
	var origin := BattleSim.mpos(sim.monsters[0]) + Vector2(10, 0)
	sim.heroes[0]["pos"] = origin
	check(sim._nearest_target(origin) == 0 and sim._front_target() == 1, "hero distance takes priority over crystal progress")
	sim._shoot(0, 0, 10, "zone", false)
	check(sim.zones[0]["at"] == BattleSim.mpos(sim.monsters[0]), "zone centered on nearest enemy")
	sim.monsters[0]["hp"] = 0
	check(sim._nearest_target(origin) == 1, "dead enemy is excluded from targeting")
	check(not Ads.request_reward("crystal"), "unsupported/invalid ad requests grant nothing")
	finish("규칙 회귀 검사")


func check_repeated_fusion_undo() -> void:
	var outcomes := {}
	for phase in [Run.Phase.SWAP, Run.Phase.SHOP]:
		for material_tier in [0, 9]:
			fresh(91208 + material_tier, 0)
			Run.confirm_hand()
			var material: Dictionary = Roster.units_of_tier(material_tier)[0]
			for i in range(7):
				Run.gain_hero(material, material_tier, false, false)
			Run.phase = phase
			var before := Run.snapshot()
			var previous_request := {}
			var codes := [Run.FUSION_BENCH, Run.FUSION_BENCH + 1, Run.FUSION_BENCH + 2,
					Run.FUSION_BENCH + 3, Run.FUSION_BENCH + 4]
			for attempt in range(12):
				var result := Run.fuse_heroes(codes).duplicate(true)
				check(not result.is_empty(), "refunded materials can be fused again in the same wave")
				if result.is_empty():
					break
				outcomes["upgrade" if int(result["tier"]) > material_tier else (
						"equal" if int(result["tier"]) == material_tier else "downgrade")] = true
				outcomes["royal"] = outcomes.get("royal", false) or int(result["tier"]) == 9
				check(int(result["id"]) == attempt + 1, "each repeated fusion receives a new reward identity")
				var pending := Run.snapshot()
				var saved := ConfigFile.new()
				saved.set_value("cur", "state", pending)
				var decoded := ConfigFile.new()
				check(decoded.parse(saved.encode_to_text()) == OK and Run.restore(decoded.get_value("cur", "state")),
						"every pending fusion survives save and resume")
				var request := {"fusion_id": result["id"], "seed": Run.run_seed, "wave": Run.wave}
				check(Run.reward_allowed("fusion_undo", request), "every result offers a fresh rewarded undo")
				check(not Run.apply_ad_reward("fusion_undo", previous_request), "earlier fusion reward cannot undo the current result")
				check(Run.snapshot() == pending, "stale reward leaves the pending result untouched")
				var rng_after_fusion := Run.rng.state
				check(Run.apply_ad_reward("fusion_undo", request), "new earned reward undoes every repeated fusion")
				var restored := Run.snapshot()
				check(restored["heroes"] == before["heroes"] and restored["bench"] == before["bench"],
						"repeated refunds restore all copies and deployed posts exactly")
				check(Run.fusion_pending.is_empty() and Run.rng.state == rng_after_fusion,
						"undo clears the result without rewinding the next random draw")
				check(not Run.apply_ad_reward("fusion_undo", request) and not Run.undo_fusion(),
						"one completed ad cannot refund the same result twice")
				check(Run.restore(restored), "refunded collection survives save and resume before retrying")
				previous_request = request
			var accepted := Run.fuse_heroes(codes).duplicate(true)
			Run.accept_fusion()
			check(not Run.apply_ad_reward("fusion_undo", {"fusion_id": accepted.get("id", -1)}),
					"accepting a hero closes that fusion's undo window")
	check(outcomes.has("upgrade") and outcomes.has("equal") and outcomes.has("downgrade")
			and bool(outcomes.get("royal", false)), "repeated refunds cover higher, equal, lower, and highest-tier results")


func check_fusion_duplicates() -> void:
	fresh(5927, 12)
	var first: Dictionary = Run.heroes[0]["unit"]
	var second: Dictionary = Run.heroes[1]["unit"]
	# Interleave copies in reserve so grouping cannot rely on acquisition order.
	for i in range(14):
		Run.wave = 30 + i
		var unit := first if i % 2 == 0 else second
		Run.gain_hero(unit, int(unit["tier"]), false)
	Run.phase = Run.Phase.SHOP
	var before := Run.snapshot()
	var candidates := Run.fusion_candidates()
	check(candidates.size() == Run.bench.size(), "fusion lists only reserve copies across pages")
	var last_tier := -1
	var last_element := -1
	var seen_codes := {}
	var finished_ids := {}
	var previous_id := ""
	for code in candidates:
		check(not seen_codes.has(code), "each fusion entry identifies a separate owned card")
		seen_codes[code] = true
		var material := Run.fusion_materials([code])
		var on_bench := code >= Run.FUSION_BENCH
		check(Run.fusion_material_allowed(code) == on_bench, "only reserve cards are eligible fusion materials")
		check(material.size() == (1 if on_bench else 0), "all listed cards resolve as reserve materials")
		var card: Dictionary = Run.bench[code - Run.FUSION_BENCH] if on_bench else Run.heroes[code]
		var tier := int(card["tier"])
		var element := Run.ELEMENT_ORDER.find(String(card["unit"]["elem"]))
		check(tier > last_tier or (tier == last_tier and element >= last_element), "fusion order is ascending tier then element")
		last_tier = tier
		last_element = element
		var unit_id := String(card["unit"]["id"])
		if unit_id != previous_id:
			check(not finished_ids.has(unit_id), "duplicate character copies are consecutive")
			finished_ids[previous_id] = true
			previous_id = unit_id
	for i in range(Run.heroes.size()):
		check(not seen_codes.has(i), "fusion excludes every deployed card")
	for i in range(Run.bench.size()):
		check(seen_codes.has(Run.FUSION_BENCH + i), "fusion retains each duplicate reserve card")
	var after_listing := Run.snapshot()
	check(after_listing["heroes"] == before["heroes"] and after_listing["bench"] == before["bench"],
			"listing fusion copies does not reorder formation or reserve")
	var codes: Array[int] = [Run.FUSION_BENCH, Run.FUSION_BENCH + 4,
			Run.FUSION_BENCH + 8, Run.FUSION_BENCH + 10, Run.FUSION_BENCH + 12]
	var materials := Run.fusion_materials(codes)
	check(materials.size() == 5, "five reserve copies of a deployed character can be selected")
	check(Run.fusion_materials([Run.FUSION_BENCH, Run.FUSION_BENCH]).is_empty(), "one physical card cannot be selected twice")
	var remaining_field := Run.heroes.duplicate(true)
	var remaining_bench := Run.bench.duplicate(true)
	for i in [12, 10, 8, 4, 0]:
		remaining_bench.remove_at(i)
	var result := Run.fuse_heroes(codes)
	check(not result.is_empty() and Run.hero_total() == 22, "five identical copies fuse into exactly one result")
	check(Run.heroes == remaining_field, "fusion preserves every deployed hero and post exactly")
	for h in remaining_bench:
		check(Run.bench.has(h), "fusion preserves unselected copies of the same character")
	Run.accept_fusion()
	check(Run.restore(Run.snapshot()) and Run.fusion_candidates().size() == Run.bench.size(),
			"remaining individual fusion copies survive save and restore")
	fresh(5928, 0)
	check(Run.fusion_candidates().is_empty(), "empty collection has no fusion candidates")


func check_fusion_deployed_guard() -> void:
	for phase in [Run.Phase.SWAP, Run.Phase.SHOP]:
		fresh(5930 + phase, 12)
		Run.confirm_hand()
		var deployed: Dictionary = Run.heroes[0]["unit"]
		for i in range(5):
			Run.gain_hero(deployed, int(deployed["tier"]), false)
		Run.phase = phase
		var reserve: Array[int] = []
		for i in range(5):
			reserve.append(Run.FUSION_BENCH + i)
		var before := Run.snapshot()
		for field_index in range(Run.heroes.size()):
			var mixed := reserve.duplicate()
			mixed[field_index % 5] = field_index
			check(not Run.fusion_material_allowed(field_index), "every deployed slot is protected")
			check(Run.fusion_materials(mixed).is_empty(), "one deployed card invalidates all fusion materials")
			check(Run.fusion_probabilities(mixed).is_empty(), "protected cards cannot contribute to fusion odds")
			check(Run.fuse_heroes(mixed).is_empty(), "direct fusion with a deployed slot is rejected")
			check(Run.snapshot() == before, "rejected fusion preserves cards, posts, random state, and pending result")
		check(Run.fuse_heroes([0, 1, 2, 3, 4]).is_empty(), "five deployed cards cannot be fused")
		for invalid_code in [-1, Run.FUSION_BENCH - 1, Run.FUSION_BENCH + Run.bench.size()]:
			var invalid := reserve.duplicate()
			invalid[0] = invalid_code
			check(Run.fuse_heroes(invalid).is_empty(), "invalid material indices are rejected")
		var duplicate := reserve.duplicate()
		duplicate[4] = duplicate[0]
		check(Run.fuse_heroes(duplicate).is_empty(), "duplicate material codes cannot consume a card twice")
		check(Run.fuse_heroes(reserve.slice(0, 4)).is_empty(), "four reserve cards cannot fuse")
		check(Run.snapshot() == before, "invalid material requests have no side effects")
		check(Run.restore(before) and not Run.fusion_material_allowed(0), "deployed lock survives save and resume")
		check(Run.swap_field_bench(0, -1), "player can explicitly return a deployed hero to reserve")
		var returned := Run.FUSION_BENCH + Run.bench.size() - 1
		check(Run.fusion_material_allowed(returned), "a hero becomes eligible only after leaving the battlefield")
		check(Run.bench_to_field(Run.bench.size() - 1), "returned hero can be deployed again")
		check(not Run.fusion_material_allowed(Run.heroes.size() - 1), "redeploying restores fusion protection")
		check(not Run.fusion_material_allowed(returned), "old reserve index cannot consume the redeployed hero")
		var field_before := Run.heroes.duplicate(true)
		check(not Run.fuse_heroes(reserve).is_empty(), "reserve copies remain fusible after formation changes")
		check(Run.heroes == field_before, "successful reserve fusion leaves the formation intact")
		Run.accept_fusion()


func check_card_choices() -> void:
	fresh(8472, 1)
	var before := Run.cards.duplicate()
	for slot in range(5):
		var allowed := 0
		for desired in range(52):
			var available := Run.card_choice_allowed(slot, desired, Run.cards[slot])
			check(available == not Run.cards.has(desired), "direct choice excludes precisely the five visible cards")
			if available:
				allowed += 1
		check(allowed == 47, "each slot offers 47 distinct replacements")
	var desired := 0
	while Run.cards.has(desired):
		desired += 1
	var request := {"slot": 2, "card": desired, "expected": Run.cards[2], "seed": Run.run_seed, "wave": Run.wave}
	for balance in [0, 100]:
		Run.gold = balance
		for count in [0, Run.free_rerolls(), Run.free_rerolls() + 2]:
			Run.rerolled[2] = count
			check(Run.reward_allowed("card", request), "direct choice ignores free rerolls and gold balance")
	Run.gold = 0
	var changed_before := Run.rerolled[2]
	var paid_before := Run.paid.duplicate()
	for slot in [-1, 5, 99]:
		check(not Run.can_choose_card(slot), "invalid replacement slot rejected")
		var invalid := request.duplicate()
		invalid["slot"] = slot
		check(not Run.apply_ad_reward("card", invalid), "invalid slot cannot receive reward")
	for card in [-1, 52, Run.cards[0], Run.cards[2]]:
		var invalid := request.duplicate()
		invalid["card"] = card
		check(not Run.apply_ad_reward("card", invalid), "invalid or already held card is rejected")
	for key in ["slot", "card", "expected"]:
		var invalid := request.duplicate()
		invalid.erase(key)
		check(not Run.apply_ad_reward("card", invalid), "incomplete card choice is rejected")
	for key in ["seed", "wave", "expected"]:
		var invalid := request.duplicate()
		invalid[key] = int(invalid[key]) + 1
		check(not Run.apply_ad_reward("card", invalid), "outdated choice data rejected: " + key)
	for phase in [Run.Phase.SHOP, Run.Phase.SWAP, Run.Phase.BATTLE, Run.Phase.OVER]:
		Run.phase = phase
		check(not Run.apply_ad_reward("card", request), "card cannot change after draw phase")
	Run.phase = Run.Phase.DRAW
	Run.running = false
	check(not Run.apply_ad_reward("card", request), "ended run cannot choose a card")
	Run.running = true
	check(Run.cards == before and Run.gold == 0, "invalid choices preserve the hand and gold")
	request["revision"] = changed_before
	check(Run.apply_ad_reward("card", request), "earned reward replaces the selected slot")
	check(Run.cards[2] == desired, "replacement is exactly the selected card")
	for slot in [0, 1, 3, 4]:
		check(Run.cards[slot] == before[slot], "other slots stay unchanged")
	check(Run.gold == 0 and Run.paid == paid_before and Run.rerolled[2] == changed_before + 1,
			"choice costs no gold, preserves paid cost, and counts one replacement")
	check(not Run.apply_ad_reward("card", request), "same choice cannot be rewarded twice")
	var saved := Run.snapshot()
	check(RunValidation.valid(saved, Run.SAVE_VERSION) and Run.restore(saved) and Run.cards[2] == desired,
			"directly selected card survives save and restore")
	Run.cards[2] = before[2]
	check(not Run.apply_ad_reward("card", request), "old callback cannot replay if the former card returns")
	Run.cards[2] = desired


func check_revive_reserve() -> void:
	for count in [1, 12, 50, -1]:
		fresh(9212026 + count, maxi(count, 0))
		if count == -1:
			# All highest-tier heroes are already deployed, plus same-wave duplicates.
			for unit in Roster.units_of_tier(Poker.Hand.ROYAL):
				Run.gain_hero(unit, Poker.Hand.ROYAL, false)
				Run.gain_hero(unit, Poker.Hand.ROYAL, false)
		Run.phase = Run.Phase.SWAP
		Run.prepare_battle()
		var before := Run.snapshot()
		Run.add_lives(-Run.max_lives())
		check(Run.revive_wave(), "revive supports empty posts, full field and duplicate royals")
		var reward: Dictionary = Run.last_result["unit"]
		var slot := int(Run.last_result["slot"])
		check(Run.snapshot()["heroes"] == before["heroes"], "every original field hero keeps its post")
		check(Run.bench.size() == before["bench"].size() + 1 and slot == before["bench"].size(), "exactly one reward is appended to reserve")
		check(Run.bench[slot]["unit"]["id"] == reward["id"] and int(Run.bench[slot]["tier"]) == Poker.Hand.ROYAL,
				"revealed hero exactly matches the granted highest-tier card")
		var pending := Run.snapshot()
		check(Run.restore(pending) and bool(Run.last_result["reward_pending"]), "restart preserves an unseen reward reveal")
		check(Run.latest_draw_location() == ["bench", slot], "same-wave duplicate heroes do not steal reward focus")
		check(not Run.apply_ad_reward("continue", {}) and Run.snapshot() == pending, "a repeated reward callback cannot duplicate the hero")
		check(Run.acknowledge_revive_reward(), "explicit reward acknowledgement succeeds once")
		check(Run.latest_draw_location() == ["bench", slot], "confirmed reward keeps focus on its exact reserve card")
		check(not Run.acknowledge_revive_reward() and not Run.last_result["reward_pending"], "repeated confirmation is inert")
		var accepted := Run.snapshot()
		check(Run.restore(accepted) and not Run.last_result["reward_pending"], "accepted reward does not replay on restart")
		check(Run.hero_total() == before["heroes"].size() + before["bench"].size() + 1, "acknowledgement never grants another hero")
