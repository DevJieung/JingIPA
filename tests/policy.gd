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


## 영웅 하나가 성역에서 내는 초당 피해(단일 대상). 자리 다툼을 이 값으로 매긴다.
##
## ★ 광역·연쇄·장판이 여럿을 동시에 때리는 몫은 여기 안 들어간다(Run.total_dps 와 같은
##   한계다). 그래서 장판 영웅을 살짝 얕본다 — 정책은 **평범한 사람**이면 된다.
static func hero_power(run, h: Dictionary) -> float:
	var st: Dictionary = run.hero_stats(h)
	var cmul: float = 1.0 + float(st["crit"]) * (float(st["critx"]) - 1.0)
	# ★ 겹친 만큼 **발이 여러 개** 나간다. 안 곱하면 x5 영웅이 1겹으로 세어져서
	#   정책이 성역을 통째로 잘못 짠다(Run.total_dps 와 같은 셈이다).
	return float(st["atk"]) * float(st["rate"]) * cmul * float(st.get("shots", 1))


## 이번 탄에 오는 몬스터들에게 이 영웅의 속성이 평균 몇 배로 들어가는가.
##
## ★ 왜 정책이 상성까지 보는가: 상점의 「영웅」 탭이 **다음 탄에 나올 몬스터와 그 약점**을
##   그대로 그려 준다(Run.wave_lineup). 그걸 보고도 안 쓰는 것은 "웬만큼 하는 사람"이
##   아니다. 편성이 씨앗으로 정해져 있으므로 화면이 보여 주는 것과 여기서 보는 것이 같다.
static func elem_factor(run, h: Dictionary) -> float:
	var e := String(h["unit"].get("elem", "none"))
	if e == "none":
		return 1.0
	var pool: Array = run.wave_lineup(run.wave) if run.has_method("wave_lineup") else []
	if pool.is_empty():
		return 1.0
	var s := 0.0
	for m in pool:
		s += Balance.elem_mult(e, String(m.get("body", "")))
	var avg: float = s / float(pool.size())
	# ★ **면역이 섞이면 평균보다 더 크게 깎는다.** 평균만 보면 「셋 중 하나가 바위」인 탄에서
	#   전기가 0.83 으로 나와 그럭저럭 쓸 만해 보이는데, 실제로는 그 한 종이 안 죽어서
	#   길 끝까지 걸어간다. 디펜스 게임에서 못 잡는 놈 하나는 평균의 문제가 아니다.
	for m2 in pool:
		if Balance.elem_mult(e, String(m2.get("body", ""))) <= 0.001:
			avg *= 0.55
	# ★ **0 으로 떨어뜨리지 않는다.** 편성이 통째로 면역이면 그 속성 영웅 전부가 0 점
	#   동점이 되어 정렬이 무작위가 되고, 그러면 "제일 센 여섯"이 아니라 아무나 여섯이
	#   선다. 바닥을 두면 같은 속성 안에서는 여전히 센 놈이 먼저 선다.
	return maxf(0.08, avg)


## 성역 여섯 자리를 정리한다. 센 놈 여섯을 세우고 나머지는 전당으로 내린다.
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


## 패시브 하나가 "골드 하나당" 얼마나 이득인가.
##
## ★ 무기·아이템이 없어진 뒤로 **골드로 사는 빌드는 이것 하나뿐**이라, 정책이 여기서
##   엉터리로 고르면 밸런스 숫자가 통째로 거짓말이 된다.
## ★ 초당 피해에 잡히는 것(공격력·공격속도·치명타 확률과 배율·골드)은 실제로 껴 보고
##   몇 % 오르는지 **잰다**. total_dps() 에 안 잡히는 것(관통·분열·상태이상·안전망)만
##   어림값을 더한다 — 안 그러면 정책이 「연발 장치」만 사고 그 결과 게임이 실제보다
##   어렵게 나온다.
## ★ 사거리를 없애면서 「긴 활대」가 「예리한 촉」(치명타 배율)으로 갈렸다. 새 카드에는
##   어림값을 안 준다 — 치명타는 total_dps() 가 이미 세고 있어서, 치명타 확률이 0 인
##   판에서는 안 사는 것까지 **재어 준 대로** 맞다.
static func passive_value(run, p: Dictionary) -> float:
	var id := String(p["id"])
	var before: float = max(1.0, run.total_dps())
	run.passives.append(id)
	var after: float = run.total_dps()
	run.passives.erase(id)
	var gain: float = (after - before) / before
	match id:
		"pierce":
			gain += 0.26
		"split":
			gain += 0.30
		"mortar":
			gain += 0.14
		"flame":
			gain += 0.24
		"frost":
			gain += 0.16
		"bolt":
			gain += 0.24
		"chainmaster":
			gain += 0.16
		"wildfire":
			gain += 0.18
		"overkill":
			gain += 0.20
		"giantslay":
			gain += 0.12
		"surge":
			gain += 0.16
		"rage":
			gain += 0.18
		"first":
			gain += 0.10
		"bulwark":
			gain += 0.30          # 안전망 — 후반에 크리스탈을 지키는 값이 크다
		"antibody":
			gain += 0.22
		"resonance":
			gain += 0.10
		"echo":
			gain += 0.34
		"midas":
			gain += 0.10
		"deal":
			gain += 0.12
		"eye":
			gain += 0.30
		"joker":
			gain += 0.55
	return gain / float(p["cost"])


## 상점. "골드 하나당 얼마나 세지는가"로 줄을 세워 살 수 있을 때까지 산다.
static func shop(run) -> void:
	arrange(run)          # 「중간 정비」 — 사기 전에 성역부터 정리한다
	var guard := 0
	# ★ 100탄이면 한 번 상점에서 살 것이 훨씬 많다. 120 에서 멈추면 후반의 정책이
	#   "살 돈은 있는데 안 사는" 사람이 되어 클리어율이 실제보다 낮게 나온다.
	while guard < 260:
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
				"gold":
					v = (0.100 if run.wave <= Balance.LAST_WAVE * 0.38 else 0.030) / float(cost)
				"reroll":
					v = (0.120 if l < 2 else 0.040) / float(cost)
				"mire":
					# 몬스터가 5% 느려지면 그만큼 더 오래 때린다 — 대략 그만큼의 이득.
					v = 0.050 / float(cost)
				_:
					# ★ 표에 줄이 하나 늘었는데 여기 가지를 안 더하면 그 상품은 **영영 안
					#   팔린다**(v 가 0 이라 후보에도 못 든다). 사거리 줄을 지우면서 이 함정이
					#   보였다 — 조용히 안 사는 것은 클리어율만 조금 낮출 뿐이라 아무도 못
					#   알아챈다. 그래서 모르는 id 도 후보에는 들게 해 둔다.
					v = 0.010 / float(cost)
			if v > best_v:
				best_v = v
				best = id

		# 패시브도 같은 저울에 올린다. 칸이 셋뿐이라 **꽉 찼으면 제일 약한 것과 견준다.**
		var pbest := ""
		var pbest_v := 0.0
		for p in run.offer_passives(3):
			var pid := String(p["id"])
			var cost2: int = int(p["cost"])
			var worst_v := 1e9
			if run.passive_full():
				for held in run.passives:
					var hv: float = passive_value(run, Balance.passive_by_id(String(held)))
					if hv < worst_v:
						worst_v = hv
			if run.gold < cost2:
				continue
			var pv: float = passive_value(run, p)
			# 새 패시브는 전액 구매하므로 활성 중인 것보다 충분히 좋은 경우에 산다.
			if run.passive_full() and pv < worst_v * 1.45:
				continue
			if pv > pbest_v:
				pbest_v = pv
				pbest = pid
		if pbest != "" and pbest_v > best_v:
			if run.passive_full():
				var w2 := ""
				var wv := 1e9
				for held2 in run.passives:
					var hv2: float = passive_value(run, Balance.passive_by_id(String(held2)))
					if hv2 < wv:
						wv = hv2
						w2 = String(held2)
				run.toggle_passive(w2)
			if run.buy_passive(pbest):
				continue
		if best == "":
			break
		if not run.buy_upgrade(best):
			break
