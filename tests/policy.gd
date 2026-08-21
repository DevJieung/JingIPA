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


## 상점. "골드 하나당 얼마나 세지는가"로 줄을 세워 살 수 있을 때까지 산다.
static func shop(run) -> void:
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
				"time":
					v = 0.100 / float(cost)
			if v > best_v:
				best_v = v
				best = id
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
