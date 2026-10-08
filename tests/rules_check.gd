extends Harness

## 새 규칙 회귀 검사 — 발판 열둘 · 중복 출전 금지 · 옛 저장 거절 · 다시 돌리기 ·
## 별 끌어오기 · 합성 · 보상.
##
##   godot --headless --path . res://tests/rules_check.tscn
##
## ★ 별맞춤 의식의 규칙 그 자체(문의 경계 · 확률표 · 조커와 눈)는 tests/rite_check 가,
##   무료 횟수와 상점 표시는 tests/reroll_check 가 잰다. 여기서는 **판(Run)이 그 규칙을
##   지키는가**를 본다 — 골드 · 저장 · 단계 · 광고 보상이 서로 얽히는 자리다.
## ★ 문 너비 · 다시 돌리기 값 · 등급 표의 숫자는 전부 Balance/Rite 에서 읽는다. 밸런스를
##   다시 잡아도 이 검사는 「규칙이 지켜지는가」만 묻는다.


func fresh(seed_value: int = 12345, count: int = 12) -> void:
	Fixture.fresh(seed_value, count)


## 문 밖에 별 넷을 다시 세운다(붙들린 0번만 문 안). 횟수(spins · paid_spins · pulls)는
## 건드리지 않는다 — 다시 돌리다 우연히 다 들어 버리면 그 뒤를 잴 수가 없기 때문이다.
func scatter() -> void:
	Run.orbit.assign(Fixture.orbit_for(1))


## 확정 결과가 가리키는 그 영웅 한 장.
func awarded(result: Dictionary) -> Dictionary:
	var group: Array = Run.heroes if String(result.get("where", "")) == "field" else Run.bench
	var slot := int(result.get("slot", -1))
	return group[slot] if slot >= 0 and slot < group.size() else {}


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
	# 별 자리를 알아볼 수 있는 꼴로 깔아 둔다 — 저장을 거쳐 그대로 돌아와야 한다.
	Fixture.stack(2)
	Run.phase = Run.Phase.SHOP
	var state := Run.snapshot()
	check(RunValidation.valid(state, Run.SAVE_VERSION) and Run.restore(state), "new rules snapshot restores")
	check(int(state["v"]) == Run.SAVE_VERSION and int(state["rules_v"]) == 3 and state.has("rite"),
			"snapshot carries the rite and the current rule markers")
	for gone in ["cards", "rerolled", "paid", "piles", "at", "best_hand"]:
		check(not state.has(gone), "poker-era key is no longer saved: " + gone)
	# 겹친 수(n)가 남아 있는 저장은 한 장씩 따로 보관하는 꼴로 풀린다.
	var stacked := state.duplicate(true)
	stacked["heroes"][0]["n"] = 4
	stacked["bench"] = []
	var stacked_restored := Run.restore(stacked)
	check(stacked_restored and Run.hero_total() == stacked["heroes"].size() + 3 and unique_field(),
			"stacked copies split into separate cards: restored=%s total=%d expected=%d unique=%s" % [stacked_restored, Run.hero_total(), stacked["heroes"].size() + 3, unique_field()])
	for reserved in Run.bench:
		check(int(reserved["n"]) == 1, "split copies remain single cards")
	Run.phase = Run.Phase.DRAW
	check(Run.orbit == Fixture.orbit_for(2), "the restored rite keeps every star where it stopped")
	check(Run.respin() == [2, 3, 4] and Run.orbit[0] == Fixture.orbit_for(2)[0] and Run.orbit[1] == Fixture.orbit_for(2)[1],
			"the restored rite continues: only the stars outside the gate re-spin")
	# ★ 포커 시절의 저장(판 번호 7 · rules_v 2 · 카드 다섯 장)은 **이어하지 않는다.** 옛 영웅의
	#   등급은 지금의 별과 세기가 달라서, 반쯤 맞는 값이 새 규칙에 섞여 들어오면 아무도 못 잡는다.
	var kept := Run.snapshot()
	var poker := state.duplicate(true)
	poker.erase("rite")
	poker["rules_v"] = 2
	poker["cards"] = [0, 1, 2, 3, 4]
	poker["rerolled"] = [0, 0, 0, 0, 0]
	poker["paid"] = [0, 0, 0, 0, 0]
	check(not RunValidation.valid(poker, Run.SAVE_VERSION) and not Run.restore(poker) and Run.snapshot() == kept,
			"a poker-era save shape is rejected without touching the running game")
	for marker in [["v", Run.SAVE_VERSION - 1], ["rules_v", 2], ["rules_v", 0], ["rules_v", "3"]]:
		var stale := state.duplicate(true)
		stale[marker[0]] = marker[1]
		check(not Run.restore(stale) and Run.snapshot() == kept, "stale save marker rejected: " + str(marker))
	var unmarked := state.duplicate(true)
	unmarked.erase("rules_v")
	check(not Run.restore(unmarked) and Run.snapshot() == kept, "a save without the rule marker is rejected")

	check_respins()
	check_star_pulls()
	check_rite_flow()
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
	var checked_maximum := false
	for attempt in range(1):
		fresh(708 + attempt, 1)
		# 5성 영웅 일곱 장. 등급은 캐릭터가 아니라 영웅 한 장의 것이라 누구든 5성일 수 있다.
		var rare: Dictionary = Roster.UNITS[Roster.UNITS.size() - 1]
		for i in range(7):
			Run.gain_hero(rare, Balance.TIER_MAX, false)
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
		if not bool(result["failed"]):
			checked_maximum = true
			check(int(result["tier"]) == Balance.TIER_MAX and float(result["awakening_mult"]) >= Balance.AWAKEN_BASE,
				"maximum rarity fusion guarantees an awakened exclusive hero")
			check(bool(Roster.unit_by_id(String(result["unit"])).get("fusion_only", false)),
				"the fused guardian comes from the fusion-only roster")
			var undo := {"fusion_id": result["id"], "seed": Run.run_seed, "wave": Run.wave}
			check(Run.apply_ad_reward("fusion_undo", undo), "guaranteed fusion can be undone by reward")
			var restored := Run.snapshot()
			check(restored["heroes"] == before["heroes"] and restored["bench"] == before["bench"], "undo removes result and restores exact materials and posts")
			check(not Run.apply_ad_reward("fusion_undo", undo), "fusion refund cannot be claimed twice")
			break
		Run.accept_fusion()
	check(checked_maximum, "maximum-rarity guaranteed fusion and undo exercised")

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
	check(Run.kills == 17 and Run.gold == checkpoint["gold"] + Balance.REVIVE_GOLD, "failed-wave gold and kills are rolled back before the revival gold reward")
	check(Run.continue_used and Run.phase == Run.Phase.SWAP and Run.last_result["gold_only"] and unique_field(), "gold reward preserves a valid formation")
	check(Run.snapshot()["heroes"] == checkpoint["heroes"] and Run.snapshot()["bench"] == checkpoint["bench"],
			"revive never changes any field or reserve hero")
	check(Run.last_result["unit"].is_empty() and Run.last_result["gold"] == Balance.REVIVE_GOLD and Run.last_result["reward_pending"], "reward identity and unconfirmed reveal are saved")
	# 부활 보상은 의식 없이 받는다 — 별 자리가 빈 채로도 저장할 수 있는 것은 이 결과뿐이다.
	check((Run.last_result["orbit"] as Array).is_empty() and int(Run.last_result["joker"]) == -1,
			"the gold reward carries no rite of its own")
	check(RunValidation.valid(Run.snapshot(), Run.SAVE_VERSION), "revived formation is persistable")
	check(Run.respin().is_empty() and Run.pull_target() == -1 and not Run.reward_allowed("card", {"slot": Rite.RINGS - 1}),
			"a revival never reopens the rite: no re-spin and no star pull")
	check(Run.acknowledge_revive_reward(), "reward can be acknowledged before deploying")
	Run.prepare_battle()
	Run.add_lives(-Run.max_lives())
	check(Run.reward_allowed("continue"), "another defeat offers a new continue in the same run")
	var kills_before := Save.total_kills
	Run.finish_defeat()
	Run.finish_defeat()
	check(Save.total_kills == kills_before + Run.kills, "run statistics settle only once")
	check(not Run.reward_allowed("continue"), "accepting defeat ends continue eligibility")
	check_revive_reserve()
	check_repeated_revives()

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
		# 같은 캐릭터를 0.5성 일곱 장으로도, 5성 일곱 장으로도 깔아 본다.
		for material_tier in [0, Balance.TIER_MAX]:
			fresh(91208 + material_tier, 0)
			Run.confirm_summon()
			var material: Dictionary = Roster.UNITS[0]
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
				outcomes["top"] = outcomes.get("top", false) or int(result["tier"]) == Balance.TIER_MAX
				check(int(result["tier"]) >= mini(Balance.TIER_MAX, material_tier + 1),
						"fusion never lands below one step above its best material")
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
	check(outcomes.has("upgrade") and outcomes.has("equal") and not outcomes.has("downgrade")
			and bool(outcomes.get("top", false)), "repeated refunds cover guaranteed upgrades and highest-tier awakening")


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
		Run.confirm_summon()
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


## 다시 돌리기 — 문 안에 든 별은 잠기고, 문 밖의 별은 전부 다시 돈다.
##
## ★ 포커 시절의 「카드 한 장 교체는 지금 보이는 다섯 장을 빼고 뽑는다」가 서 있던 자리다.
##   그때 지키던 것은 「바꿔서 손패가 망가지는 일은 없다」였고, 지금 그 뜻은
##   **「다시 돌려서 이미 든 별이 빠지는 일은 없다」**다.
func check_respins() -> void:
	fresh(2394, 1)
	var free := Run.free_rerolls()
	# 아직 의식이 열리지 않은 판(첫 탄 전)에서는 돌릴 것도 끌어올 것도 없다.
	Run.start_run(2394)
	check(Run.rite_stars() == 0 and int(Run.rite_preview()["tier"]) == -1, "no rite is open before the first wave")
	check(not Run.can_respin() and Run.respin().is_empty() and Run.pull_target() == -1
			and not Run.can_pull(Rite.RINGS - 1) and Run.confirm_summon().is_empty() and Run.hero_total() == 0,
			"nothing can be re-spun, pulled or summoned before a rite opens")
	fresh(2394, 1)
	var landed := {}      # 궤도 → 다시 돌아 문 안에 선 횟수
	var missed := {}      # 궤도 → 다시 돌았는데 문 밖에 선 횟수
	for iteration in range(512):
		# 문 안에 별이 1~4개 선 자리를 번갈아 깐다. 안 깔면 몇 번 뒤에는 다 들어 버려서 돌릴 것이 없다.
		var held := 1 + iteration % 4
		Run.orbit.assign(Fixture.orbit_for(held))
		# 한 번은 무료로, 한 번은 무료를 다 쓴 것으로 — 두 길이 같은 별을 돌려야 한다.
		var paying := iteration % 2 == 1
		Run.spins = free if paying else 0
		Run.paid_spins = 0
		Run.gold = 100000
		var before: Array[int] = Run.orbit.duplicate()
		var cost := Run.respin_cost()
		check(cost == (Balance.reroll_cost(0) if paying else 0), "the re-spin price follows the free allowance")
		var expected: Array[int] = []
		for ring in range(held, Rite.RINGS):
			expected.append(ring)
		var moved := Run.respin()
		check(moved == expected, "every star outside the gate re-spins, and only those")
		check(Run.gold == 100000 - cost and Run.paid_spins == (1 if paying else 0) and Run.spins == (free + 1 if paying else 1),
				"a re-spin charges exactly the shown price and is counted once")
		check(Rite.valid(Run.orbit) and Run.rite_stars() >= held, "re-spinning never lowers the star count")
		for ring in range(Rite.RINGS):
			if ring < held:
				check(Run.orbit[ring] == before[ring], "a star inside the gate never moves")
			elif Rite.in_gate(ring, Run.orbit[ring]):
				landed[ring] = int(landed.get(ring, 0)) + 1
			else:
				missed[ring] = int(missed.get(ring, 0)) + 1
		check(Save.cur_run.get("rite", {}) == Run.snapshot()["rite"], "every re-spin is saved at once")
	for ring in range(1, Rite.RINGS):
		check(landed.has(ring) and missed.has(ring),
				"over many re-spins ring %d both enters and misses the gate (%d in · %d out)"
				% [ring, int(landed.get(ring, 0)), int(missed.get(ring, 0))])
	check(not landed.has(0) and not missed.has(0), "the anchored star never re-spins")

	# 골드와 무료 횟수.
	Fixture.stack(1)
	Run.gold = 0
	check(Run.can_respin() and Run.respin_cost() == 0, "the free re-spin remains available without gold")
	Run.spins = free          # 무료를 다 쓴 것으로
	var paid_cost := Run.respin_cost()
	check(paid_cost == Balance.reroll_cost(0) and paid_cost > 0, "the first paid re-spin costs the base price")
	for balance in [0, paid_cost - 1, paid_cost]:
		Run.gold = balance
		check(Run.can_respin() == (balance >= paid_cost), "a paid re-spin requires enough gold")
		check(Run.can_pull(Run.pull_target()), "pulling a star by reward stays available independently of paid re-spins")
	check(not Run.respin().is_empty() and Run.gold == 0, "a paid re-spin can spend the last gold")
	scatter()
	var unchanged: Array[int] = Run.orbit.duplicate()
	check(Run.respin().is_empty() and Run.orbit == unchanged and Run.gold == 0 and Run.spins == free + 1,
			"exhausted funds block further paid re-spins")
	var exhausted := Run.snapshot()
	check(Run.restore(exhausted) and not Run.can_respin(), "a resumed exhausted rite preserves the re-spin limits")
	check(Run.spins == free + 1 and Run.paid_spins == 1 and Run.respins_left() == 0
			and Run.respin_cost() == Balance.reroll_cost(1), "resuming keeps the used count and the raised price")
	check(Run.pull_target() == Rite.RINGS - 1 and Run.can_pull(Run.pull_target()), "resuming a rite preserves the reward pull")
	# 다 든 5성에서는 돌릴 것이 없다 — 골드만 받고 아무 일도 안 일어나면 안 된다.
	Fixture.stack(Rite.MAX_STARS)
	Run.gold = 100000
	var full: Array[int] = Run.orbit.duplicate()
	check(not Run.can_respin() and Run.respin().is_empty() and Run.gold == 100000 and Run.spins == 0 and Run.orbit == full,
			"five stars in the gate: nothing to re-spin and no gold taken")
	check(Run.pull_target() == -1 and not Run.can_pull(Rite.RINGS - 1), "five stars in the gate leave nothing to pull")


## 보상형 광고 「별 끌어오기」 — 문 밖의 별에만, 그리고 **지금 이 의식**에만.
##
## ★ 포커 시절의 「원하는 카드 광고」가 서 있던 자리다. 그때 지키던 것 넷이 그대로 남는다:
##   무료 횟수·골드와 무관하다 / 이미 가진 것은 고를 수 없다 / 오래된 콜백은 거절한다 /
##   한 번의 광고는 한 번만 준다.
func check_star_pulls() -> void:
	fresh(8472, 1)
	# 궤도마다 문 안/밖을 따로 깔아 본다(붙들린 0번은 언제나 문 안) — 열여섯 가지.
	for mask in range(1 << (Rite.RINGS - 1)):
		var orbit := Fixture.orbit_for(Rite.RINGS)
		var outside: Array[int] = []
		for ring in range(1, Rite.RINGS):
			if mask & (1 << (ring - 1)):
				orbit[ring] = Fixture.orbit_for(1)[ring]
				outside.append(ring)
		Run.orbit.assign(orbit)
		check(Rite.valid(Run.orbit) and Run.rite_stars() == Rite.RINGS - outside.size(), "hand-laid rite counts its stars")
		check(Run.pull_target() == (outside[-1] if not outside.is_empty() else -1),
				"the reward targets the outermost star outside the gate")
		for ring in [-1, 0, 1, 2, 3, 4, Rite.RINGS, 99]:
			check(Run.can_pull(ring) == outside.has(ring), "only a star standing outside the gate can be pulled")
			check(Run.reward_allowed("card", {"slot": ring}) == outside.has(ring),
					"the reward is offered precisely for the stars outside the gate")

	Fixture.stack(2)            # 문 안 0 · 1번, 문 밖 2 · 3 · 4번
	var target := Run.pull_target()
	check(target == Rite.RINGS - 1, "the outermost star is the one to pull")
	var before: Array[int] = Run.orbit.duplicate()
	var request := {"slot": target, "seed": Run.run_seed, "wave": Run.wave}
	var free := Run.free_rerolls()
	for balance in [0, 100]:
		Run.gold = balance
		for used in [[0, 0], [free, 0], [free + 2, 2]]:
			Run.spins = int(used[0])
			Run.paid_spins = int(used[1])
			check(Run.reward_allowed("card", request), "a reward pull ignores the free allowance and the gold balance")
	Run.gold = 0
	var spins_before := Run.spins
	var paid_before := Run.paid_spins
	var cost_before := Run.respin_cost()
	var pulls_before := Run.pulls
	var revision := Run.rite_revision()
	for slot in [-1, Rite.RINGS, 99]:
		check(not Run.can_pull(slot), "a ring outside the rite is rejected")
		var invalid := request.duplicate()
		invalid["slot"] = slot
		check(not Run.apply_ad_reward("card", invalid), "a ring outside the rite cannot receive the reward")
	for slot in [0, 1]:
		var invalid := request.duplicate()
		invalid["slot"] = slot
		check(not Run.apply_ad_reward("card", invalid), "a star already inside the gate is rejected")
	var incomplete := request.duplicate()
	incomplete.erase("slot")
	check(not Run.apply_ad_reward("card", incomplete), "a pull without its ring is rejected")
	for key in ["seed", "wave"]:
		var invalid := request.duplicate()
		invalid[key] = int(invalid[key]) + 1
		check(not Run.apply_ad_reward("card", invalid), "outdated reward data rejected: " + key)
	for off in [-1, 1]:
		var invalid := request.duplicate()
		invalid["revision"] = revision + off
		check(not Run.apply_ad_reward("card", invalid), "a pull aimed at another state of the rite is rejected")
	for phase in [Run.Phase.SHOP, Run.Phase.SWAP, Run.Phase.BATTLE, Run.Phase.OVER]:
		Run.phase = phase
		check(not Run.apply_ad_reward("card", request), "a star cannot be pulled outside the rite phase")
	Run.phase = Run.Phase.DRAW
	Run.running = false
	check(not Run.apply_ad_reward("card", request), "an ended run cannot pull a star")
	Run.running = true
	check(Run.orbit == before and Run.gold == 0 and Run.pulls == pulls_before and Run.rite_revision() == revision,
			"rejected pulls preserve the stars, the gold and the rite revision")
	request["revision"] = revision
	check(Run.apply_ad_reward("card", request), "the earned reward pulls the star into the gate")
	check(Rite.in_gate(target, Run.orbit[target]) and Run.rite_stars() == 3 and Rite.valid(Run.orbit),
			"the pulled star stands inside the gate: exactly one more star")
	for other in range(Rite.RINGS):
		if other != target:
			check(Run.orbit[other] == before[other], "the other stars stay where they stopped")
	check(Run.gold == 0 and Run.spins == spins_before and Run.paid_spins == paid_before and Run.respin_cost() == cost_before,
			"a pull costs no gold and changes neither the re-spin count nor its price")
	check(Run.pulls == pulls_before + 1 and Run.rite_revision() == revision + 1,
			"a pull is counted once and advances the rite revision")
	check(Save.cur_run.get("rite", {}) == Run.snapshot()["rite"], "the pulled star is saved at once")
	check(not Run.apply_ad_reward("card", request) and Run.pulls == pulls_before + 1, "the same reward cannot be applied twice")
	var saved := Run.snapshot()
	var pulled_at := Run.orbit[target]
	check(RunValidation.valid(saved, Run.SAVE_VERSION) and Run.restore(saved) and Run.orbit[target] == pulled_at
			and Run.pulls == pulls_before + 1 and Run.rite_revision() == revision + 1,
			"the pulled star survives save and restore")
	# 같은 자리가 되돌아와도 옛 콜백은 다시 못 쓴다 — 별이 한 번이라도 바뀌면 판 번호가 오른다.
	Run.orbit[target] = before[target]
	check(Run.can_pull(target) and not Run.apply_ad_reward("card", request),
			"an old callback cannot replay when the same star stands outside again")
	var renewed := request.duplicate()
	renewed["revision"] = Run.rite_revision()
	check(Run.reward_allowed("card", renewed), "a request made in the current state of the rite is accepted")

	# 광고를 보는 사이에 다시 돌렸다면 그 보상은 옛 상태를 겨눈 것이다.
	Fixture.stack(1)
	Run.gold = 0
	var pending := {"slot": Run.pull_target(), "seed": Run.run_seed, "wave": Run.wave, "revision": Run.rite_revision()}
	check(Run.reward_allowed("card", pending), "a pull is pending for the current rite")
	check(not Run.respin().is_empty(), "the player re-spins while the ad is still open")
	scatter()                   # 그 별이 여전히 문 밖에 서 있어도
	check(Run.can_pull(int(pending["slot"])) and not Run.reward_allowed("card", pending)
			and not Run.apply_ad_reward("card", pending),
			"a re-spin makes the pending pull stale even while that star is still outside")
	check(Run.orbit == Fixture.orbit_for(1) and Run.pulls == 0, "a stale pull changes nothing")

	# 다음 탄의 의식은 판 번호가 다시 0 부터다. 그래도 지난 탄의 콜백은 탄 번호에서 걸린다.
	Fixture.stack(1)
	var last_wave := {"slot": Rite.RINGS - 1, "seed": Run.run_seed, "wave": Run.wave, "revision": Run.rite_revision()}
	check(not Run.confirm_summon().is_empty() and not Run.reward_allowed("card", last_wave), "a confirmed rite closes the pull")
	Run.phase = Run.Phase.SHOP
	Run.begin_draw()
	Fixture.stack(1)
	check(Run.rite_revision() == int(last_wave["revision"]) and Run.can_pull(int(last_wave["slot"])),
			"the next rite reaches the same revision with the same star outside")
	check(not Run.reward_allowed("card", last_wave) and not Run.apply_ad_reward("card", last_wave),
			"a callback from the previous wave is rejected")
	var other_run := last_wave.duplicate()
	other_run["wave"] = Run.wave
	check(Run.reward_allowed("card", other_run), "the same request for this wave would be accepted")
	other_run["seed"] = Run.run_seed + 1
	check(not Run.reward_allowed("card", other_run), "a callback from another run is rejected")


## 실제 굴림으로 한 판을 이어 본다 — 의식이 주는 것은 언제나 온 별(홀수 칸)이고,
## 반 별(짝수 칸)은 도박꾼의 눈으로만 온다.
##
## ★ 포커 시절에는 「족보 → 그 등급의 캐릭터」였다. 지금은 **문 안의 별 수 → 등급**이고
##   캐릭터는 쉰 명 중 아무나다. 그래서 여기서 재는 것은 「별 수와 영웅 한 장의 등급이
##   같은 말을 하는가」다 — 둘이 어긋나면 「문 안에 셋이 섰는데 2성이 나오는」 버그다.
func check_rite_flow() -> void:
	for with_eye in [false, true]:
		fresh(77001 + int(with_eye), 0)
		if with_eye:
			Run.owned_passives.assign(["eye"])
			Run.passives.assign(["eye"])
		var best := -1
		var bumped := 0
		var paid_rounds := 0
		var star_counts := {}
		var units := {}
		# 탄 번호가 판의 끝(Balance.LAST_WAVE)을 넘지 않는 만큼만 잇는다.
		for round in range(mini(90, Balance.LAST_WAVE)):
			if round > 0:
				Run.phase = Run.Phase.SHOP
				Run.begin_draw()
			check(Rite.valid(Run.orbit) and Run.spins == 0 and Run.paid_spins == 0 and Run.pulls == 0
					and Run.respins_left() == Run.free_rerolls() and Run.respin_cost() == 0,
					"every wave opens a fresh rite with its full free allowance")
			var purse := Balance.reroll_cost(0) + Balance.reroll_cost(1)
			Run.gold = purse
			var held := Rite.hits(Run.orbit)
			var stars_before := Run.rite_stars()
			# 무료를 다 쓰고, 한 탄 걸러 한 번은 값을 내고 한 번 더 돌린다.
			var guard := 0
			while Run.respins_left() > 0 and Run.can_respin() and guard < 32:
				guard += 1
				check(not Run.respin().is_empty() and Run.gold == purse, "a free re-spin turns stars and takes no gold")
			if round % 2 == 1 and Run.can_respin():
				check(not Run.respin().is_empty() and Run.paid_spins == 1 and Run.gold == purse - Balance.reroll_cost(0),
						"a paid re-spin takes exactly the shown price")
				paid_rounds += 1
			for ring in range(Rite.RINGS):
				if held[ring]:
					check(Rite.in_gate(ring, Run.orbit[ring]), "a star that entered the gate stays in through every re-spin")
			var hero_count := Run.hero_total()
			var result := Run.confirm_summon()
			var stars := int(result["stars"])
			var tier := int(result["tier"])
			star_counts[stars] = true
			units[String(result["unit"]["id"])] = true
			check(stars >= stars_before and stars == Rite.stars(result["orbit"]) and stars == Run.rite_stars(),
					"the summoned star count is the number of stars inside the gate")
			if bool(result["bumped"]):
				bumped += 1
				check(with_eye and tier == Rite.tier_of(stars) + 1 and tier % 2 == 0 and stars < Rite.MAX_STARS,
						"only the gambler's eye adds a half star, and never above five stars")
			else:
				check(tier == Rite.tier_of(stars) and tier % 2 == 1, "the rite alone always grants whole stars")
			check(int(result["joker"]) == -1, "no joker, no pulled star")
			check(bool(result["showy"]) == (tier >= Balance.SHOWY_TIER), "the showy reveal starts at its tier")
			var hero := awarded(result)
			check(Run.hero_total() == hero_count + 1 and not hero.is_empty() and hero["unit"] == result["unit"]
					and int(hero["tier"]) == tier, "exactly one hero is granted, carrying the tier of the rite")
			check(not hero.has("value") and not hero.has("variant"), "a summoned hero carries no poker value")
			check(not bool(result["unit"].get("fusion_only", false)), "the rite never grants a fusion-only guardian")
			best = maxi(best, tier)
			check(Run.best_tier == best and Run.last_tier == tier and Run.phase == Run.Phase.SWAP,
					"the run remembers its best and latest tier")
			check(Save.best_of(String(result["unit"]["id"])) >= tier and int(Save.cur_run.get("phase", -1)) == Run.Phase.SWAP,
					"the summon is recorded and saved at once")
		check(star_counts.size() >= 2 and units.size() >= 20, "real rolls spread over star counts and characters (%d · %d)"
				% [star_counts.size(), units.size()])
		check(paid_rounds > 0, "the flow exercised paid re-spins as well as free ones")
		check((bumped > 0) == with_eye, "half stars appear exactly when the gambler's eye is active (%d)" % bumped)


func check_repeated_revives() -> void:
	fresh(9222026, 12)
	Run.phase = Run.Phase.SWAP
	for attempt in range(12):
		Run.prepare_battle()
		var before := Run.snapshot()
		Run.gold += 200
		Run.kills += 20
		Run.add_lives(-Run.max_lives())
		var defeat := Run.snapshot()
		check(RunValidation.valid(defeat, Run.SAVE_VERSION) and Run.restore(defeat),
				"every repeated defeat remains resumable, including saves with continue_used=true")
		check(Run.reward_allowed("continue") and Run.apply_ad_reward("continue", {}),
				"each earned ad can revive the same wave again: " + str(attempt + 1))
		if Run.phase != Run.Phase.SWAP:
			break
		check(Run.wave == before["wave"] and Run.lives == Run.max_lives() and Run.running,
				"every revival returns to the failed wave with full crystals")
		check(Run.gold == before["gold"] + Balance.REVIVE_GOLD and Run.kills == before["kills"],
				"each revival rolls back only the current failed battle")
		check(Run.snapshot()["heroes"] == before["heroes"] and Run.bench.size() == before["bench"].size(),
				"repeated revival preserves all heroes and grants gold")
		var pending := Run.snapshot()
		check(RunValidation.valid(pending, Run.SAVE_VERSION) and Run.restore(pending),
				"each repeated revival reward survives restart")
		check(not Run.apply_ad_reward("continue", {}) and Run.snapshot() == pending,
				"each revival rejects duplicate rewards before another defeat")
		check(Run.acknowledge_revive_reward(), "each repeated reward can be confirmed")
		if attempt == 5:
			Run.prepare_battle()
			Run.settle_wave(false)
			Run.begin_draw()
			Run.confirm_summon()
	check(Run.hero_total() == 13 and Run.gold >= 12 * Balance.REVIVE_GOLD + Balance.START_GOLD,
			"all earlier revival rewards are retained")
	Run.phase = Run.Phase.OVER
	Run.battle_checkpoint = {}
	check(not Run.reward_allowed("continue") and not Run.revive_wave(), "defeat without a checkpoint cannot revive")


func check_revive_reserve() -> void:
	for count in [1, 12, 50, -1, -2]:
		fresh(9212026 + count, maxi(count, 0))
		if count < 0:
			# Five different heroes at the highest tier are already owned (deployed when
			# count is -1, all in reserve when -2), plus same-wave duplicates.
			if count == -2:
				Run.gain_hero(Roster.UNITS[0], 0, false)
			for unit in Roster.UNITS.slice(Roster.UNITS.size() - 5):
				Run.gain_hero(unit, Balance.TIER_MAX, false, count == -1)
				Run.gain_hero(unit, Balance.TIER_MAX, false, count == -1)
		Run.phase = Run.Phase.SWAP
		Run.prepare_battle()
		var before := Run.snapshot()
		Run.add_lives(-Run.max_lives())
		check(Run.revive_wave(), "revive supports every five-star ownership and formation state")
		check(Run.snapshot()["heroes"] == before["heroes"] and Run.snapshot()["bench"] == before["bench"], "revive never grants or moves heroes")
		check(Run.last_result["unit"].is_empty() and Run.last_result["slot"] == -1 and Run.last_result["gold_only"], "revive result contains gold without a hero")
		check(Run.gold == before["gold"] + Balance.REVIVE_GOLD and Run.last_result["gold"] == Balance.REVIVE_GOLD, "every revival gets exactly the revival gold")
		var location := ["", -1]
		var pending := Run.snapshot()
		check(Run.restore(pending) and bool(Run.last_result["reward_pending"]), "restart preserves an unseen reward reveal")
		check(Run.latest_draw_location() == location, "reward focus matches the granted card or gold")
		check(not Run.apply_ad_reward("continue", {}) and Run.snapshot() == pending, "a repeated reward callback cannot duplicate the hero")
		check(Run.acknowledge_revive_reward(), "explicit reward acknowledgement succeeds once")
		check(Run.latest_draw_location() == location and Run.phase == Run.Phase.SHOP and Run.retry_wave,
				"confirmation opens the main camp with same-wave retry")
		check(not Run.acknowledge_revive_reward() and not Run.last_result["reward_pending"], "repeated confirmation is inert")
		var accepted := Run.snapshot()
		check(Run.restore(accepted) and not Run.last_result["reward_pending"], "accepted reward does not replay on restart")
		check(Run.hero_total() == before["heroes"].size() + before["bench"].size(), "acknowledgement never grants another hero")
		check(Run.gold == before["gold"] + Balance.REVIVE_GOLD, "resume and confirmation never grant gold twice")
		var malformed := accepted.duplicate(true)
		malformed["last"]["gold"] = -1
		check(not Run.restore(malformed) and Run.snapshot() == accepted, "invalid gold reward save is rejected without changing the run")
		malformed = accepted.duplicate(true)
		malformed["retry_wave"] = "true"
		check(not Run.restore(malformed) and Run.snapshot() == accepted, "invalid retry flag is rejected without changing the run")
		# 결과에 적힌 등급 · 별 수 · 별 자리 · 조커 궤도가 범위를 벗어나면 손상된 저장이다.
		for field in [["tier", Balance.TIER_MAX + 1], ["stars", 0], ["stars", Rite.MAX_STARS + 1],
				["joker", Rite.RINGS], ["orbit", "none"], ["orbit", [0, 0, 0]]]:
			malformed = accepted.duplicate(true)
			malformed["last"][field[0]] = field[1]
			check(not Run.restore(malformed) and Run.snapshot() == accepted,
					"malformed reward result is rejected without changing the run: " + str(field))
	# A revival reward that carried a hero (not gold only) remains claimable, without
	# exchanging the hero or granting gold on top.
	fresh(230926, 12)
	var unit: Dictionary = Roster.UNITS[Roster.UNITS.size() - 1]
	var got := Run.gain_hero(unit, Balance.TIER_MAX, false, false)
	Run.phase = Run.Phase.SWAP
	Run.continue_used = true
	Run.last_result = {"tier": Balance.TIER_MAX, "stars": Rite.MAX_STARS,
			"orbit": Fixture.orbit_for(Rite.MAX_STARS), "bumped": false, "joker": -1,
			"unit": unit, "where": got["where"], "slot": got["slot"],
			"revived": true, "reward_pending": true}
	var hero_reward := Run.snapshot()
	hero_reward.erase("retry_wave")
	check(Run.restore(hero_reward) and Run.last_result["unit"] == unit, "an unconfirmed hero reward remains readable")
	check(Run.latest_draw_location() == ["bench", int(got["slot"])], "the reward still points at the granted reserve card")
	# 영웅을 받은 결과는 별 자리가 있어야 한다 — 비어 있어도 되는 것은 골드만 받은 부활뿐이다.
	var orbitless := hero_reward.duplicate(true)
	orbitless["last"]["orbit"] = []
	var held_run := Run.snapshot()
	check(not Run.restore(orbitless) and Run.snapshot() == held_run, "a hero result without its rite is rejected")
	# 포커 시절의 결과 꼴(hand · cards · key)은 지금 규칙에 없다 — 통째로 거절하고 판은 그대로 둔다.
	var poker_reward := hero_reward.duplicate(true)
	poker_reward["last"] = {"hand": Balance.TIER_MAX, "cards": [0, 1, 2, 3, 4], "key": [],
			"unit": String(unit["id"]), "where": got["where"], "slot": got["slot"],
			"revived": true, "reward_pending": true}
	check(not Run.restore(poker_reward) and Run.snapshot() == held_run, "a poker-era result cannot be resumed")
	check(Run.acknowledge_revive_reward() and Run.phase == Run.Phase.SHOP and Run.retry_wave,
			"a hero reward also returns to the main camp")
	check(Run.gold == hero_reward["gold"] and Run.snapshot()["bench"] == hero_reward["bench"],
			"acknowledging a hero reward neither exchanges heroes nor grants new gold")
