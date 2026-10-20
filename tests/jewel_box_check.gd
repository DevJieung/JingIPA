extends Harness

## The jewel box (2026-10-19, docs/JEWEL_BOX.md): grade and card odds, the deal's guarantees, the stage's
## free first box (2-star floor, fair elements), rerolls (grade never drops, free ones only: 1, 3 with the
## DLC, plus the fortune nodes), the pick (idempotent, recorded, as previewed, 「조커」 and 「도박꾼의 눈」),
## saves mid-box and after the pick, the save checks, the anti-air fairness rule and a shrinking pool.
##
##   godot --headless --path . res://tests/jewel_box_check.tscn

## A shop that owns what it is told (owned [] = no DLC).
class Owner extends RefCounted:
	const NAME := "test"
	var store: Node
	var owned: Array = []
	func start() -> void: store.set_owned(owned)
	func sells(_id: String) -> bool: return false
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void: store.finish_restore(true)
	func buy(product: Dictionary) -> void: store.finish_purchase(String(product["id"]), "unavailable")

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_rules()
	_check_first_box()
	_check_rerolls()
	_check_pick()
	_check_saves()
	_check_anti_air()
	_check_immune()
	_check_first_box_elements()
	_check_pool()
	_use_shop(null)
	Arena.running = false
	finish("보석상자 규칙·다시 뽑기·고르기·저장")

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

## A stage's first box, open (modal "box"), the battle still in its first preparation.
func _box(seed_value: int, stage: int = 1) -> void:
	Arena.start_run(seed_value, stage)
	Arena.confirm_stage()

func _ids(cards: Array) -> Array:
	var out: Array = []
	for card in cards: out.append(String(card["unit"]["id"]))
	return out

func _check_rules() -> void:
	for weights in [Balance.arena_box_weights(), Balance.arena_card_weights()]:
		var chances := JewelBox.odds(weights)
		var total := 0.0
		for p in chances: total += p
		check(chances.size() == JewelBox.MAX_STARS and absf(total - 1.0) < 1e-9, "확률표는 1~5성 다섯 칸, 합 1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	for weights in [Balance.arena_box_weights(), Balance.arena_card_weights()]:
		var counts := [0, 0, 0, 0, 0]
		var n := 200000
		for i in range(n): counts[JewelBox.roll(rng, weights) - 1] += 1
		var chances := JewelBox.odds(weights)
		var close := true
		for s in range(JewelBox.MAX_STARS):
			var sigma := sqrt(chances[s] * (1.0 - chances[s]) / n)
			if absf(float(counts[s]) / n - chances[s]) > 5.0 * sigma + 1e-4: close = false
		check(close, "굴림 %d번이 확률표대로 (%s)" % [n, str(counts)])
	var floored := true
	for i in range(10000):
		if JewelBox.roll(rng, Balance.arena_box_weights(), 2) < 2: floored = false
	check(floored, "최저 등급(2성)이 지켜짐")
	var dealt_ok := true
	var at_least := [0, 0, 0, 0, 0]
	var deals := 20000
	for i in range(deals):
		var grade := JewelBox.roll(rng, Balance.arena_box_weights())
		var cards := JewelBox.deal(rng, Roster.UNITS, grade, Balance.ARENA_BOX_CARDS, Balance.arena_card_weights())
		var guaranteed := 0
		var top := 0
		var seen := {}
		for card in cards:
			var stars := int(card["stars"])
			if stars < 1 or stars > 5 or seen.has(String(card["unit"]["id"])): dealt_ok = false
			seen[String(card["unit"]["id"])] = true
			top = maxi(top, stars)
			if bool(card["guaranteed"]):
				guaranteed += 1
				if stars < grade: dealt_ok = false
		if cards.size() != Balance.ARENA_BOX_CARDS or guaranteed != 1 or top < grade: dealt_ok = false
		for k in range(top): at_least[k] += 1
	check(dealt_ok, "상자마다 %d장 · 보장 카드 한 장(상자 등급 이상) · 같은 영웅 없음" % Balance.ARENA_BOX_CARDS)
	var expected := JewelBox.best_at_least()
	var table_ok := true
	for k in range(JewelBox.MAX_STARS):
		var p: float = expected[k]
		if absf(float(at_least[k]) / deals - p) > 5.0 * sqrt(p * (1.0 - p) / deals) + 1e-3: table_ok = false
	check(table_ok and is_equal_approx(expected[0], 1.0), "안내표(가장 좋은 카드가 k성 이상)가 실제 굴림과 맞음")
	var small := JewelBox.deal(rng, Roster.UNITS.slice(0, 3), 3, Balance.ARENA_BOX_CARDS, Balance.arena_card_weights())
	check(small.size() == 3 and small.filter(func(c): return bool(c["guaranteed"])).size() == 1 and JewelBox.deal(rng, [], 3, 5, Balance.arena_card_weights()).is_empty(), "후보가 적으면 카드도 그만큼")
	check(JewelBox.tier_of(1) == 1 and JewelBox.tier_of(3) == 5 and JewelBox.tier_of(5) == 9 and JewelBox.tier_of(9) == 9 and JewelBox.tier_of(0) == 1, "별 수 → 등급 칸")
	var tie := [{"stars": 3, "guaranteed": false}, {"stars": 4, "guaranteed": false}, {"stars": 4, "guaranteed": true}, {"stars": 2, "guaranteed": false}]
	check(JewelBox.best(tie) == 2 and JewelBox.best([]) == -1 and JewelBox.best([{"stars": 2, "guaranteed": false}, {"stars": 2, "guaranteed": false}]) == 0, "가장 좋은 카드: 별, 같으면 보장 카드, 그다음 앞")

func _check_first_box() -> void:
	_use_shop(null)
	var floor_ok := true
	var fair_ok := true
	var free_ok := true
	for i in range(40):
		var stage := 1 + i % 6
		Arena.start_run(41000 + i, stage)
		var gold: int = Arena.gold
		if not Arena.confirm_stage(): free_ok = false
		if Arena.modal != "box" or Arena.phase != Arena.Phase.DRAW or Arena.box_cards.size() != Balance.ARENA_BOX_CARDS: free_ok = false
		if Arena.box_tier < Balance.ARENA_BOX_FIRST_TIER: floor_ok = false
		if Arena.gold != gold or Arena.summon_count != 0: free_ok = false
		var body := String(Arena.theme_for(1)["main_body"])
		for card in Arena.box_cards:
			if Balance.elem_mult(String(card["unit"].get("elem", "none")), body) < 1.0: fair_ok = false
	check(free_ok, "스테이지 첫 상자는 무료 · 정비 중 바로 열림 · 카드 %d장" % Balance.ARENA_BOX_CARDS)
	check(floor_ok, "첫 상자는 최소 %d성" % Balance.ARENA_BOX_FIRST_TIER)
	check(fair_ok, "첫 상자의 다섯 장 모두 그 스테이지 주 몸통이 반감하지 않는 속성")
	check(not Arena.close_modal() and Arena.modal == "box", "고르기 전에는 상자가 닫히지 않음")

func _check_rerolls() -> void:
	_use_shop(null)
	_box(42001)
	check(Arena.dlc() and Arena.free_rerolls() == Balance.ARENA_DLC_FREE_REROLL and Arena.respins_left() == Balance.ARENA_DLC_FREE_REROLL and Arena.respin_cost() == 0,
		"상점 연결이 없으면(=소유) 무료 다시 뽑기 %d번" % Balance.ARENA_DLC_FREE_REROLL)
	var gold: int = Arena.gold
	var never_lower := true
	var changed := false
	var saved_at_once := true
	for n in range(Balance.ARENA_DLC_FREE_REROLL):
		var tier: int = Arena.box_tier
		var before := _ids(Arena.box_cards)
		var dealt := Arena.respin()
		if dealt.size() != Arena.box_cards.size() or Arena.box_cards.size() != Balance.ARENA_BOX_CARDS: never_lower = false
		if Arena.box_tier < tier: never_lower = false
		if _ids(Arena.box_cards) != before: changed = true
		if Save.cur_run.get("box", {}) != Arena.snapshot()["box"] or int(Save.cur_run["box"]["spins"]) != n + 1: saved_at_once = false
	check(never_lower and changed, "다시 뽑기는 상자 등급을 내리지 않고 카드를 새로 냄")
	check(saved_at_once, "다시 뽑는 그 순간 저장")
	check(Arena.spins == Balance.ARENA_DLC_FREE_REROLL and Arena.respins_left() == 0 and not Arena.can_respin() and Arena.respin().is_empty() and Arena.gold == gold,
		"무료를 다 쓰면 더 못 뽑음 · 골드는 들지 않음(유료 다시 뽑기 없음)")
	_use_shop([])
	_box(42002)
	check(not Arena.dlc() and Arena.free_rerolls() == Balance.FREE_REROLL and Arena.respins_left() == Balance.FREE_REROLL, "DLC 가 없으면 무료 다시 뽑기 %d번" % Balance.FREE_REROLL)
	Arena.levels["reroll"] = 1
	Arena.passives.append("deal")
	check(Arena.free_rerolls() == Balance.FREE_REROLL + 1 + Balance.PASSIVE_DEAL, "「한 번 더」 · 「큰손」이 그 위에 더함 (DLC 없음)")
	_use_shop([Store.GUARDIAN])
	check(Arena.dlc() and Arena.free_rerolls() == Balance.ARENA_DLC_FREE_REROLL + 1 + Balance.PASSIVE_DEAL, "DLC 를 사면 %d번 + 별자리 보너스" % Balance.ARENA_DLC_FREE_REROLL)
	_use_shop(null)

func _check_pick() -> void:
	_use_shop(null)
	_box(43001)
	var index := 2
	var card: Dictionary = Arena.box_cards[index]
	var preview := Arena.card_preview(index)
	var count: int = Arena.summon_count
	var result := Arena.pick_card(index)
	var id := String(card["unit"]["id"])
	check(not result.is_empty() and Arena.phase == Arena.Phase.SWAP and Arena.summon_count == count + 1, "카드를 고르면 영웅 지급 · 고른 결과 화면")
	check(Arena.pick_card(index) == result and Arena.confirm_summon() == result and Arena.pick_card(0) == result and Arena.summon_count == count + 1, "다시 골라도 같은 결과 (한 번만 지급)")
	check(String(result["kind"]) == String(preview["kind"]) and int(result["after_tier"]) == int(preview["after_tier"]) and int(result["before_tier"]) == int(preview["before_tier"])
		and int(result["added_points"]) == int(preview["added_points"]) and String(result["where"]) == String(preview["where"]), "결과가 미리보기와 같음")
	check(int(result["stars"]) == int(card["stars"]) and int(result["box"]) == Arena.box_tier and int(result["card"]) == index and bool(result["guaranteed"]) == bool(card["guaranteed"])
		and not bool(result["joker"]) and not bool(result["bumped"]) and result.has("growth_needed"), "결과에 상자 · 카드 · 보장 표시")
	check(Save.seen_units.has(id) and Save.best_of(id) >= int(result["after_tier"]), "고른 영웅이 도감에 기록됨")
	check(Arena.close_modal() and Arena.modal == "" and Arena.box_cards.is_empty() and Arena.box_tier == 0, "고른 뒤 닫으면 상자가 사라짐")
	# 「조커」: one star more on the picked card, up to five.
	Arena.gold = 1000000
	Arena.passives.append("joker")
	check(Arena.begin_summon() and Arena.modal == "box", "정비 중 유료 상자")
	var low := 0
	for i in range(Arena.box_cards.size()):
		if int(Arena.box_cards[i]["stars"]) < int(Arena.box_cards[low]["stars"]): low = i
	var plain := int(Arena.box_cards[low]["stars"])
	var shown := Arena.card_preview(low)
	var picked := Arena.pick_card(low)
	check(int(picked["stars"]) == mini(5, plain + 1) and bool(picked["joker"]) == (plain < 5) and int(shown["stars"]) == int(picked["stars"]) and int(picked["tier"]) == JewelBox.tier_of(mini(5, plain + 1)),
		"「조커」는 고른 카드 +1성 (미리보기에도)")
	Arena.close_modal()
	Arena.begin_summon()
	Arena.box_cards[0]["stars"] = 5
	var five := Arena.pick_card(0)
	check(int(five["stars"]) == 5 and not bool(five["joker"]), "5성 카드에 「조커」는 아무것도 더하지 않음")
	Arena.close_modal()
	Arena.passives.erase("joker")
	# 「도박꾼의 눈」: an PASSIVE_EYE_P chance of half a star more, rolled at the pick.
	Arena.passives.append("eye")
	Arena.gold = 100000000
	var tries := 0
	var bumps := 0
	for n in range(600):
		if not Arena.begin_summon(): break
		var at := 0
		for i in range(Arena.box_cards.size()):
			if int(Arena.box_cards[i]["stars"]) < int(Arena.box_cards[at]["stars"]): at = i
		var before_tier := JewelBox.tier_of(int(Arena.box_cards[at]["stars"]))
		var got := Arena.pick_card(at)
		if before_tier < Balance.TIER_MAX:
			tries += 1
			if bool(got["bumped"]):
				bumps += 1
				if int(got["tier"]) != before_tier + 1: tries = -100000
		Arena.close_modal()
	var rate := float(bumps) / maxf(1.0, float(tries))
	check(tries > 400 and absf(rate - Balance.PASSIVE_EYE_P) < 0.06, "「도박꾼의 눈」은 약 %.0f%% 로 반 별 (실제 %.1f%% · %d번)" % [Balance.PASSIVE_EYE_P * 100.0, rate * 100.0, tries])
	Arena.passives.erase("eye")
	Arena.running = false

func _check_saves() -> void:
	_use_shop(null)
	_box(44001)
	Arena.respin()
	var open := Arena.snapshot()
	check(ArenaValidation.valid(open) and open["box"]["cards"].size() == Balance.ARENA_BOX_CARDS and int(open["box"]["spins"]) == 1, "상자를 고르는 중 저장")
	var a := Arena.pick_card(1)
	check(Arena.restore(open) and Arena.modal == "box" and Arena.phase == Arena.Phase.DRAW and Arena.box_tier == int(open["box"]["tier"]) and Arena.spins == 1 and _ids(Arena.box_cards) == open["box"]["cards"].map(func(c): return String(c["u"])),
		"상자 중 복구: 같은 등급 · 같은 카드 · 같은 다시 뽑기 수")
	var b := Arena.pick_card(1)
	check(a == b and not a.is_empty(), "복구한 상자에서 같은 카드를 고르면 같은 결과 (이어 하기로 다시 굴릴 수 없음)")
	var swap := Arena.snapshot()
	check(ArenaValidation.valid(swap) and Arena.restore(swap) and Arena.phase == Arena.Phase.SWAP and Arena.summon_result == b and Arena.close_modal(), "고른 뒤 저장 · 복구 · 닫기")
	var closed := Arena.snapshot()
	check(ArenaValidation.valid(closed) and closed["box"]["cards"].is_empty(), "닫힌 뒤의 저장에는 상자가 비어 있음")
	# More cards than today's ARENA_BOX_CARDS (the value was lowered) is still a box; past the fixed cap it is not.
	var six: Dictionary = open.duplicate(true)
	_break(six, "카드 하나 더")
	check(ArenaValidation.valid(six), "지금 장 수보다 한 장 많은 상자도 받음")
	for label in ["상자 등급 0", "모든 카드가 상자 등급 아래", "같은 영웅 두 장", "없는 영웅", "0성 카드", "6성 카드", "고정 상한을 넘는 카드",
			"유료 횟수 > 다시 뽑기", "보장 카드 없음", "보장 카드 두 장", "옛 의식 모달"]:
		var bad: Dictionary = open.duplicate(true)
		_break(bad, label)
		check(not ArenaValidation.valid(bad), "잘못된 상자 저장 거부: " + label)
	# A card for a character already at the top grade: valid one grade below, refused at the top.
	var owned: Dictionary = open.duplicate(true)
	var unit_id := String(owned["box"]["cards"][0]["u"])
	owned["heroes"].append({"u": unit_id, "t": Balance.TIER_MAX - 1, "p": Balance.ARENA_CENTER + Vector2(0, 160), "points": 0})
	owned["sim"]["heroes"].append({"cool": 0.2, "acc": 0.0, "face": 1.0, "dmg": 0.0, "kills": 0, "dw": 0.0, "dn": 0.0, "dr": 0.0})
	owned["summon_count"] = 1
	check(ArenaValidation.valid(owned), "가진 영웅의 카드가 든 상자는 유효")
	owned["heroes"][-1]["t"] = Balance.TIER_MAX
	check(not ArenaValidation.valid(owned), "최종 강화한 영웅의 카드가 든 상자 거부")
	var interim: Dictionary = open.duplicate(true)
	interim.erase("box")
	check(ArenaValidation.outdated(interim) and not ArenaValidation.valid(interim), "상자 없는 판 5 저장(별맞춤 시절)은 이어 하지 않음")
	var old: Dictionary = open.duplicate(true)
	old["v"] = 4
	check(ArenaValidation.outdated(old) and not Arena.restore(old), "판 4 저장은 이어 하지 않음")
	Arena.running = false

func _break(save: Dictionary, label: String) -> void:
	var box: Dictionary = save["box"]
	var cards: Array = box["cards"]
	match label:
		"상자 등급 0": box["tier"] = 0
		"모든 카드가 상자 등급 아래":
			box["tier"] = 5
			for card in cards: card["s"] = 1
		"같은 영웅 두 장": cards[1]["u"] = cards[0]["u"]
		"없는 영웅": cards[0]["u"] = "no_such_hero"
		"0성 카드": cards[0]["s"] = 0
		"6성 카드": cards[0]["s"] = 6
		"카드 하나 더", "고정 상한을 넘는 카드":
			var target := cards.size() + 1 if label == "카드 하나 더" else JewelBox.SAVE_CARDS_MAX + 1
			var have := {}
			for card in cards: have[String(card["u"])] = true
			for unit in Roster.UNITS:
				if cards.size() >= target: break
				var id := String(unit["id"])
				if have.has(id) or save["heroes"].any(func(h: Dictionary) -> bool: return String(h["u"]) == id): continue
				cards.append({"u": id, "s": 1, "g": false})
				have[id] = true
		"유료 횟수 > 다시 뽑기": box["paid"] = int(box["spins"]) + 1
		"보장 카드 없음":
			for card in cards: card["g"] = false
		"보장 카드 두 장":
			for card in cards: card["g"] = true
		"옛 의식 모달": save["modal"] = "rite"

## The stage of the ladder (from STAGE 2) whose waves bring flyers, for the anti-air rule.
func _flyer_stage() -> int:
	for n in range(2, 60):
		Arena.start_run(45000 + n, n)
		if Arena.flyers_ahead(): return n
	return -1

func _check_anti_air() -> void:
	_use_shop(null)
	Arena.start_run(45001, 1)
	check(not Arena.flyers_ahead() and not Arena.anti_air_needed(), "STAGE 1 에는 공중 몬스터가 없어 대공 규칙이 쉼")
	var stage := _flyer_stage()
	check(stage > 1, "공중 몬스터가 나오는 스테이지 (STAGE %d)" % stage)
	if stage < 2: return
	var always := true
	var fair := true
	for i in range(30):
		Arena.start_run(46000 + i, stage)
		Arena.confirm_stage()
		if not Arena.anti_air_needed(): always = false
		var air := 0
		var body := String(Arena.theme_for(1)["main_body"])
		for card in Arena.box_cards:
			if Balance.anti_air(card["unit"]): air += 1
			if Balance.elem_mult(String(card["unit"].get("elem", "none")), body) < 1.0: fair = false
		if air < Balance.ARENA_BOX_AIR_CARDS: always = false
		Arena.respin()
		air = 0
		for card in Arena.box_cards:
			if Balance.anti_air(card["unit"]): air += 1
		if air < Balance.ARENA_BOX_AIR_CARDS: always = false
	check(always, "대공 공정 규칙: 대공 영웅이 없고 공중 몬스터가 나오면 첫 상자부터 대공 카드 %d장 이상 (다시 뽑아도)" % Balance.ARENA_BOX_AIR_CARDS)
	check(fair, "대공 카드도 첫 상자의 속성 공정 규칙을 지킴")
	Arena.start_run(46100, stage)
	Arena.confirm_stage()
	var archer := -1
	for i in range(Arena.box_cards.size()):
		if Balance.anti_air(Arena.box_cards[i]["unit"]): archer = i
	Arena.pick_card(archer)
	Arena.close_modal()
	check(not Arena.anti_air_needed(), "대공 영웅이 생기면 규칙은 쉼")
	Arena.running = false

## Electric heroes: rock is immune to them (Balance.MBODY), so a party of only these cannot finish a wave
## with a rock body in it — the immune fairness rule (2026-10-19 O5). brigid · conor shoot the sky.
const ELEC := ["brigid", "conor", "finn", "rhiannon", "donn"]

## A stage (from STAGE 4, where immune bodies may appear) whose waves bring that body, walking or flying.
func _stage_with_body(body: String, flying: bool) -> int:
	for n in range(Balance.ARENA_IMMUNE_STAGE, Balance.ARENA_LADDER + 1):
		Arena.start_run(47000 + n, n)
		var ahead: Dictionary = Arena._bodies_in(1, Balance.ARENA_WAVES)
		if ahead.has(body) and bool(ahead[body]["fly" if flying else "ground"]): return n
	return -1

## That stage past its first box, the party replaced by `ids` (4 stars), plenty of gold, a box open.
func _party_box(seed_value: int, stage: int, ids: Array) -> void:
	Arena.start_run(seed_value, stage)
	Arena.confirm_stage()
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.heroes.clear()
	Arena.bench.clear()
	for id in ids: Arena.gain_hero(Roster.unit_by_id(id), JewelBox.tier_of(4))
	Arena.gold = 100000
	Arena.begin_summon()

func _check_immune() -> void:
	_use_shop(null)
	var stage := _stage_with_body("rock", false)
	check(stage > 0, "바위 몸이 걸어 나오는 스테이지 (STAGE %d)" % stage)
	if stage < 0: return
	_party_box(48000, stage, ELEC)
	check(not Arena.hurts(Roster.unit_by_id("finn"), "rock", false) and Arena.hurts(Roster.unit_by_id("pip"), "rock", false), "바위는 전기에 면역(전기 영웅은 못 때림)")
	check(Arena.modal == "box" and Arena.immune_needed(), "전기 영웅뿐이면 면역 공정 규칙이 걸림")
	var always := true
	for i in range(40):
		Arena.box_tier = 0
		Arena._deal_box()
		if not Arena.box_cards.any(func(card: Dictionary) -> bool: return Arena.hurts(card["unit"], "rock", false)): always = false
	check(always, "상자마다 바위를 때릴 수 있는 카드가 한 장 이상 (40번)")
	var pick := -1
	for i in range(Arena.box_cards.size()):
		if Arena.hurts(Arena.box_cards[i]["unit"], "rock", false): pick = i
	check(pick >= 0 and not Arena.pick_card(pick).is_empty() and Arena.close_modal() and not Arena.immune_needed(), "바위를 때릴 영웅이 생기면 규칙은 쉼")
	# A flying rock body: electric guns and bows shoot the sky but cannot hurt it, so the anti-air rule holds.
	var sky := _stage_with_body("rock", true)
	check(sky > 0, "바위 공중 몸이 나오는 스테이지 (STAGE %d)" % sky)
	if sky < 0: return
	_party_box(48100, sky, ["brigid", "conor"])
	check(Arena.anti_air_needed(), "전기 대공뿐이면 바위 공중 몸을 못 맞혀 대공 규칙이 그대로 걸림")
	var air := true
	for i in range(40):
		Arena.box_tier = 0
		Arena._deal_box()
		if Arena.box_cards.filter(func(card: Dictionary) -> bool: return Arena.hurts(card["unit"], "rock", true)).size() < Balance.ARENA_BOX_AIR_CARDS: air = false
	check(air, "상자마다 바위 공중 몸을 맞힐 대공 카드 (40번)")

## The stage's first box deals elements that no body of waves 1~3 resists (the strictest test any character
## passes, _first_box_fair), not only the main body (2026-10-19 O5).
func _check_first_box_elements() -> void:
	_use_shop(null)
	var checked := 0
	var ok := true
	var widened := 0
	for n in [4, 7, 12, 25, 41, 45, 60, 77, 90]:
		for k in range(4):
			Arena.start_run(49000 + n * 10 + k, n)
			Arena.confirm_stage()
			var early: Dictionary = Arena._bodies_in(1, 3)
			var main := String(Arena.theme_for(1)["main_body"])
			if early.size() > 1: widened += 1
			var level := -1
			for l in range(3):
				if Arena.eligible_units().any(func(unit: Dictionary) -> bool: return Arena._first_box_fair(l, String(unit.get("elem", "none")), early, main)):
					level = l
					break
			for card in Arena.box_cards:
				if level >= 0 and not Arena._first_box_fair(level, String(card["unit"].get("elem", "none")), early, main): ok = false
			checked += 1
	check(ok and checked > 0 and widened > 0, "첫 상자는 1~3웨이브의 몸 누구도 저항하지 않는 속성 (%d판, 몸이 여럿인 판 %d)" % [checked, widened])

func _check_pool() -> void:
	_use_shop(null)
	_box(47001)
	Arena.confirm_summon()
	Arena.close_modal()
	for unit in Roster.UNITS:
		if Arena.find_hero(String(unit["id"]))[1] < 0: Arena.gain_hero(unit, 1)
	var keep := 0
	for hero in Arena.heroes + Arena.bench:
		if keep < 2:
			keep += 1
			continue
		hero["tier"] = Balance.TIER_MAX
		hero["growth_points"] = 0
	Arena.gold = 1000000
	check(Arena.begin_summon() and Arena.box_cards.size() == 2, "최종 강화하지 않은 영웅이 둘뿐이면 카드도 두 장")
	Arena.confirm_summon()
	Arena.close_modal()
	for hero in Arena.heroes + Arena.bench:
		hero["tier"] = Balance.TIER_MAX
		hero["growth_points"] = 0
	check(Arena.summon_block() == "pool" and not Arena.begin_summon(), "모두 최종 강화하면 상자는 열리지 않음 (이유: pool)")
	Arena.running = false
