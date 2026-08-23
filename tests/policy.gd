extends RefCounted
class_name PlayPolicy

## "웬만큼 하는 사람"을 흉내 내는 자동 플레이어.
##
## 밸런스를 손으로 계산해서 맞추는 건 불가능하다(영웅이 매 판 무작위로 붙고, 상점에서
## 무엇을 사느냐로 세기가 통째로 달라진다). 그래서 **실제 게임 코드를 그대로 돌려**
## 40탄까지 몇 번이나 살아남는지 숫자로 뽑는다. 여기 정책이 곧 "기준 실력"이다.
##
## ★ 정책을 세게 만들면 게임이 쉬워 보이고, 약하게 만들면 어려워 보인다.
##   그래서 정책은 **평범하게** 둔다 — 사람이 쉽게 떠올릴 만한 수준으로만.


## 버릴 카드를 고른다. 되도록 큰 짝을 남기고 나머지를 바꾼다.
static func discard_plan(cards: Array) -> Array:
	var rank_n := {}
	var suit_n := {}
	for c in cards:
		var r := Poker.rank_of(int(c))
		var s := Poker.suit_of(int(c))
		rank_n[r] = int(rank_n.get(r, 0)) + 1
		suit_n[s] = int(suit_n.get(s, 0)) + 1

	# 플러시가 눈앞이면(같은 무늬 4장) 그쪽으로 간다 — 기대값이 짝보다 훨씬 크다.
	var best_suit := -1
	var best_sn := 0
	for s in suit_n:
		if int(suit_n[s]) > best_sn:
			best_sn = int(suit_n[s])
			best_suit = int(s)
	if best_sn >= 4:
		var keep_s: Array = []
		for i in range(cards.size()):
			keep_s.append(Poker.suit_of(int(cards[i])) != best_suit)
		return keep_s

	# 짝이 하나라도 있으면 짝을 전부 남긴다.
	var has_pair := false
	for r in rank_n:
		if int(rank_n[r]) >= 2:
			has_pair = true
	var out: Array = []
	if has_pair:
		for i in range(cards.size()):
			out.append(int(rank_n[Poker.rank_of(int(cards[i]))]) < 2)
		return out

	# 아무것도 없으면 제일 높은 한 장만 남기고 넷을 다 바꾼다.
	var top := -1
	var top_r := -1
	for i in range(cards.size()):
		var r := Poker.rank_of(int(cards[i]))
		if r > top_r:
			top_r = r
			top = i
	for i in range(cards.size()):
		out.append(i != top)
	return out


## 영웅 하나가 안뜰에서 내는 초당 피해(단일 대상). 자리 다툼을 이 값으로 매긴다.
##
## ★ 광역·연쇄·장판이 여럿을 동시에 때리는 몫은 여기 안 들어간다(Run.total_dps 와 같은
##   한계다). 그래서 장판 영웅을 살짝 얕본다 — 정책은 **평범한 사람**이면 된다.
static func hero_power(run, h: Dictionary) -> float:
	var st: Dictionary = run.hero_stats(h)
	var cmul: float = 1.0 + float(st["crit"]) * (float(st["critx"]) - 1.0)
	return float(st["atk"]) * float(st["rate"]) * cmul


## 이번 탄에 오는 몬스터들에게 이 영웅의 속성이 평균 몇 배로 들어가는가.
##
## ★ 왜 정책이 상성까지 보는가: 상점의 「영웅」 탭이 **다음 탄에 나올 몬스터와 그 약점**을
##   그대로 그려 준다(Run.wave_lineup). 그걸 보고도 안 쓰는 것은 "웬만큼 하는 사람"이
##   아니다. 편성이 씨앗으로 정해져 있으므로 화면이 보여 주는 것과 여기서 보는 것이 같다.
static func elem_factor(run, h: Dictionary) -> float:
	var e := String(h["unit"].get("elem", "none"))
	if e == "none":
		return 1.0
	var pool: Array = run.wave_lineup(run.wave) if run.has_method("wave_lineup") \
			else Roster.stage_pool(run.wave)
	if pool.is_empty():
		return 1.0
	var s := 0.0
	for m in pool:
		s += Balance.elem_mult(e, String(m.get("body", "null")))
	return s / float(pool.size())


## 안뜰 여섯 자리를 정리한다. 센 놈 여섯을 세우고 나머지는 인벤토리로 내린다.
##
## ★ 이 함수가 곧 "기준 실력"이다. 여기를 세게 만들면 게임이 쉬워 보이고 약하게 만들면
##   어려워 보인다. 그래서 판단은 둘뿐이다 — **초당 피해**와 **이번 탄 상성**.
##   (겹친 수가 공격력에 이미 곱해져 있으므로 "1겹 로열" 과 "8겹 원페어" 가 같은 저울에 선다)
static func arrange(run) -> void:
	var all: Array = []
	for h in run.heroes:
		all.append(h)
	for h in run.bench:
		all.append(h)
	var score := func(h): return hero_power(run, h) * elem_factor(run, h)
	all.sort_custom(func(a, b): return score.call(a) > score.call(b))
	var keep: int = mini(Balance.HERO_SLOTS, all.size())
	# ★ 배열을 통째로 갈아 끼운다. 한 칸씩 맞바꾸면 자리 번호가 밀려서 같은 영웅이
	#   두 배열에 다 들어가거나 조용히 사라진다(실제로 흔한 실수다).
	run.heroes = all.slice(0, keep)
	run.bench = all.slice(keep, all.size())


## 카드를 다시 뽑는다. 공짜는 다 쓰고, 골드가 넉넉할 때만 돈을 낸다.
static func do_rerolls(run) -> void:
	for _pass in range(3):
		var plan := discard_plan(run.cards)
		var did := false
		for i in range(run.cards.size()):
			if not bool(plan[i]):
				continue
			var cost: int = run.reroll_cost_of(i)
			# 유료 리롤은 지갑의 8% 를 넘지 않을 때만. 상점 살 돈을 다 태우면 안 된다.
			if cost > 0 and (run.gold < 300 or cost > int(run.gold * 0.08)):
				continue
			if run.reroll(i):
				did = true
		if not did:
			break


## 무기 하나가 "골드 하나당" 얼마나 이득인가.
## ★ 사거리·둔화·광역처럼 total_dps() 에 안 잡히는 것은 어림값을 더해 준다.
##   안 그러면 정책이 장궁을 영영 안 사고, 그 결과 밸런스가 실제보다 어렵게 나온다.
static func weapon_value(run, w: Dictionary) -> float:
	var id := String(w["id"])
	var before: float = max(1.0, run.total_dps())
	run.weapons.append(id)
	var after: float = run.total_dps()
	run.weapons.erase(id)
	var gain: float = (after - before) / before
	if w.has("rng"):
		gain += (float(w["rng"]) - 1.0) * 0.8
	if w.has("split"):
		gain += 0.30
	if w.has("slow"):
		gain += 0.18
	if w.has("gold"):
		gain += 0.15
	if w.has("radius"):
		gain += 0.10
	return gain / float(w["cost"])


## 아이템은 "여유가 있을 때" 조금만 쟁여 둔다.
## ★ 능력치 사는 줄에 같이 세우면 골드를 다 태워서 하나도 못 산다. 먼저 사고 시작한다.
static func stock_items(run) -> void:
	while run.lives <= 8 and run.item_count("repair") < 2 and run.gold > 420:
		if not run.buy_item("repair"):
			break
	while run.wave >= 8 and run.item_count("bomb") < 2 and run.gold > 600:
		if not run.buy_item("bomb"):
			break
	while run.wave >= 12 and run.item_count("freeze") < 1 and run.gold > 700:
		if not run.buy_item("freeze"):
			break


## 전투 중에 아이템을 쓴다. 화면이 없어도 같은 판단을 하도록 여기 둔다
## (전투 화면은 사람이 누르고, 검사기는 이 함수가 누른다).
static func use_items(run, sim) -> void:
	if sim.done or sim.monsters.is_empty():
		return
	if run.item_count("repair") > 0 and run.lives <= 3:
		sim.use_item("repair")
		return
	var lead := 0.0
	for mo in sim.monsters:
		lead = max(lead, sim.progress(mo))
	if lead < 0.82:
		return
	var cnt: int = sim.monsters.size()
	if cnt >= 4 and run.item_count("bomb") > 0:
		sim.use_item("bomb")
	elif cnt >= 3 and run.item_count("freeze") > 0:
		sim.use_item("freeze")
	elif run.item_count("rally") > 0:
		sim.use_item("rally")


## 상점. "골드 하나당 얼마나 세지는가"로 줄을 세워 살 수 있을 때까지 산다.
static func shop(run) -> void:
	arrange(run)          # 「중간 정비」 — 사기 전에 안뜰부터 정리한다
	stock_items(run)
	var guard := 0
	while guard < 120:
		guard += 1
		var best := ""
		var best_v := 0.0
		var dps: float = max(1.0, run.total_dps())
		for u in Balance.UPGRADES:
			var id := String(u["id"])
			var l: int = run.lv(id)
			if Balance.upgrade_maxed(id, l):
				continue
			var cost: int = Balance.upgrade_cost(id, l)
			if cost > run.gold:
				continue
			var v := 0.0
			match id:
				"atk", "rate", "crit", "critx":
					# 한 단계 올려 보고 초당 피해가 몇 % 오르는지 실제로 잰다.
					run.levels[id] = l + 1
					var after: float = run.total_dps()
					run.levels[id] = l
					v = ((after - dps) / dps) / float(cost)
				"rng":
					v = (0.060 if l < 6 else 0.020) / float(cost)
				"gold":
					v = (0.100 if run.wave <= 15 else 0.030) / float(cost)
				"life":
					if run.lives <= 6:
						v = 1.500 / float(cost)
					elif run.lives <= 12:
						v = 0.250 / float(cost)
					else:
						v = 0.040 / float(cost)
				"reroll":
					v = (0.120 if l < 2 else 0.040) / float(cost)
				"mire":
					# 몬스터가 6% 느려지면 그만큼 더 오래 때린다 — 대략 그만큼의 이득.
					v = 0.050 / float(cost)
			if v > best_v:
				best_v = v
				best = id
		# 무기도 같은 저울에 올린다. 칸이 비어 있을 때만.
		var wbest := ""
		var wbest_v := 0.0
		if not run.weapon_full():
			for w in Balance.WEAPONS:
				var wid := String(w["id"])
				if run.has_weapon(wid) or int(w["cost"]) > run.gold:
					continue
				var wv: float = weapon_value(run, w)
				if wv > wbest_v:
					wbest_v = wv
					wbest = wid
		if wbest != "" and wbest_v > best_v:
			if run.buy_weapon(wbest):
				continue
		# 패시브도 같은 저울에 올린다. 값이 커서 여유가 있을 때만 산다.
		var pbest := ""
		var pbest_v := 0.0
		for p in run.offer_passives(3):
			var cost: int = int(p["cost"])
			if run.gold < int(cost * 1.5):
				continue
			var v: float = 0.35 / float(cost)
			if v > pbest_v:
				pbest_v = v
				pbest = String(p["id"])
		if pbest != "" and pbest_v > best_v:
			if run.buy_passive(pbest):
				continue
		if best == "":
			break
		if not run.buy_upgrade(best):
			break
