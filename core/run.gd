extends Node

## 한 판(런)의 상태 전부. 화면들은 이 노드만 보고 자기를 그린다.
##
## 왜 오토로드인가: 카드 뽑기 → 전투 → 상점 이 셋이 서로 다른 씬인데 목숨·골드·영웅은
## 셋 사이를 계속 넘어다닌다. 씬끼리 값을 들고 다니게 하면 어느 한 곳에서만 갱신을
## 빠뜨려도 조용히 어긋난다.

signal gold_changed(gold: int)
signal lives_changed(lives: int)

## 지금 어느 단계인가. 화면 전환을 이 값으로 결정한다.
enum Phase { TITLE, DRAW, BATTLE, SHOP, OVER, WIN }

var phase: int = Phase.TITLE
var wave: int = 0
var lives: int = 0
var gold: int = 0
var kills: int = 0
var running: bool = false

## 안뜰에 세워 둔 영웅들. **최대 Balance.HERO_SLOTS 명**이고, 여기 있는 영웅만 싸운다.
## 각 원소는
##   {"unit": <Roster 의 표 한 줄>, "tier": int, "wave": int, "n": int}
## n 은 같은 캐릭터가 몇 겹으로 쌓였는가 — 그만큼 공격력이 배가 된다.
var heroes: Array = []
## 캐릭터 인벤토리. 자리가 없어 물러나 있는 영웅들. 모양은 heroes 와 같다.
## ★ 벤치에 있는 영웅은 **싸우지 않는다.** 겹치기(n)만 그대로 쌓인다 —
##   나중에 안뜰로 올리면 쌓인 만큼 그대로 세진다.
var bench: Array = []

## 상점에서 산 능력치 단계. id -> lv
var levels: Dictionary = {}
## 산 패시브 id 들.
var passives: Dictionary = {}
## 장착한 무기 id 들. **최대 Balance.WEAPON_SLOTS 개**라 무엇을 빼는가가 곧 선택이다.
var weapons: Array[String] = []
## 가진 아이템. id -> 개수. 전투 화면에서 눌러 쓴다.
var items: Dictionary = {}

## 이번 판에 받은 카드 다섯 장.
var cards: Array[int] = []
## 카드별 리롤 횟수 (공짜 포함).
var rerolled: Array[int] = []
## 카드별 **유료** 리롤 횟수. 값을 매기는 데 쓴다.
var paid: Array[int] = []
## 이번 뽑기에서 아직 안 쓴 덱(중복 방지).
var _deck: Array[int] = []

var rng := RandomNumberGenerator.new()

## 마지막으로 확정한 결과 — 전투 화면과 연출이 읽는다.
var last_hand: int = -1
var last_cards: Array[int] = []
var last_key: Array[int] = []
var last_unit: Dictionary = {}
var last_bumped: bool = false     ## 도박꾼의 눈으로 한 단계 올라갔는가
var last_joker: int = -1          ## 조커가 바꿔 준 카드 자리(없으면 -1)


func _ready() -> void:
	rng.randomize()


# --------------------------------------------------------------------------- #
# 판 시작 / 끝
# --------------------------------------------------------------------------- #
func start_run(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	wave = 0
	lives = Balance.START_LIVES
	gold = Balance.START_GOLD
	kills = 0
	heroes.clear()
	bench.clear()
	levels.clear()
	passives.clear()
	weapons.clear()
	items.clear()
	cards.clear()
	rerolled.clear()
	paid.clear()
	last_hand = -1
	last_unit = {}
	running = true
	phase = Phase.DRAW
	Save.runs += 1
	Save.save_file()
	gold_changed.emit(gold)
	lives_changed.emit(lives)


## ★ 두 번 부르면 안 된다. add_lives() 가 목숨 0 을 볼 때마다 여기로 오는데, 한 걸음에
##   몬스터 여럿이 크리스탈에 닿으면 그 수만큼 불린다. 막지 않으면 Save.record_run 이
##   여러 번 돌아 **평생 누적 처치 수가 두 배·세 배로 부풀고** 저장 파일이 한 프레임에
##   여러 번 쓰인다. (실제로 자동 플레이 14판 중 1판에서 재현됐다)
func end_run(won: bool) -> void:
	if not running:
		return
	running = false
	phase = Phase.WIN if won else Phase.OVER
	Save.record_run(wave, kills, won)


func lv(id: String) -> int:
	return int(levels.get(id, 0))


func has(passive_id: String) -> bool:
	return passives.has(passive_id)


func max_lives() -> int:
	return Balance.START_LIVES + lv("life")


func add_gold(n: int) -> void:
	gold = maxi(0, gold + n)
	gold_changed.emit(gold)


func add_lives(n: int) -> void:
	lives = clampi(lives + n, 0, max_lives())
	lives_changed.emit(lives)
	if lives <= 0:
		end_run(false)


# --------------------------------------------------------------------------- #
# 카드 다섯 장 — 뽑기와 리롤
# --------------------------------------------------------------------------- #
## 새 판의 카드를 뽑는다. 덱은 판마다 새로 섞으므로 한 판 안에서는 같은 카드가 안 나온다.
func begin_draw() -> void:
	wave += 1
	phase = Phase.DRAW
	_deck = Poker.full_deck()
	_shuffle(_deck)
	cards = []
	rerolled = []
	paid = []
	for i in range(5):
		cards.append(_deck.pop_back())
		rerolled.append(0)
		paid.append(0)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## 카드 한 장당 공짜 리롤 횟수.
func free_rerolls() -> int:
	return Balance.FREE_REROLL + lv("reroll")


## i 번 카드를 지금 다시 뽑는 데 드는 값. 0 이면 공짜다.
##
## ★ 규칙: 공짜 횟수를 다 쓴 카드는 **골드를 내지 않으면 더 리롤할 수 없다.**
##   값은 그 카드를 유료로 리롤한 횟수에 따라 두 배씩 오른다(15 → 30 → 60 …).
func reroll_cost_of(i: int) -> int:
	if i < 0 or i >= cards.size():
		return 0
	if rerolled[i] < free_rerolls():
		return 0
	return Balance.reroll_cost(paid[i])


func can_reroll(i: int) -> bool:
	if i < 0 or i >= cards.size() or _deck.is_empty():
		return false
	return gold >= reroll_cost_of(i)


## 실제로 다시 뽑는다. 성공하면 참.
func reroll(i: int) -> bool:
	if not can_reroll(i):
		return false
	var cost := reroll_cost_of(i)
	if cost > 0:
		add_gold(-cost)
		paid[i] += 1
	rerolled[i] += 1
	# 버린 카드는 덱으로 안 돌아간다 — 돌아가면 방금 버린 카드가 바로 다시 나와서
	# 플레이어가 리롤이 고장 났다고 느낀다.
	cards[i] = _deck.pop_back()
	return true


# --------------------------------------------------------------------------- #
# 족보 확정 → 영웅 등장
# --------------------------------------------------------------------------- #
## 지금 카드로 족보를 판정하고 그 등급의 캐릭터 중 하나를 무작위로 세운다.
## 화면은 반환값(딕셔너리)만 보고 연출한다.
func confirm_hand() -> Dictionary:
	var use: Array[int] = cards.duplicate()
	last_joker = -1
	var hand := Poker.evaluate(use)

	# 조커: 다섯 장 중 한 장을 **가장 좋은 패가 되는 카드**로 친다.
	if has("joker"):
		var best := hand
		var best_i := -1
		var best_c := -1
		for i in range(5):
			for c in range(52):
				if use.has(c):
					continue
				var trial: Array[int] = use.duplicate()
				trial[i] = c
				var h := Poker.evaluate(trial)
				if h > best:
					best = h
					best_i = i
					best_c = c
		if best_i >= 0:
			use[best_i] = best_c
			hand = best
			last_joker = best_i

	last_bumped = false
	if has("eye") and hand < Poker.Hand.ROYAL and rng.randf() < Balance.PASSIVE_EYE_P:
		hand += 1
		last_bumped = true

	var unit := Roster.pick_unit(hand, rng)
	last_hand = hand
	last_cards = use.duplicate()
	last_key = Poker.key_cards(use, hand) if not last_bumped else use.duplicate()
	last_unit = unit
	var got := gain_hero(unit, hand)
	Save.record_hand(hand, String(unit.get("id", "")))
	return {"hand": hand, "cards": last_cards, "key": last_key, "unit": unit,
			"bumped": last_bumped, "joker": last_joker,
			"showy": hand >= Poker.SHOWY,
			"stacked": bool(got["stacked"]), "where": String(got["where"]),
			"slot": int(got["slot"]), "n": int(got["n"])}


# --------------------------------------------------------------------------- #
# 영웅 편성 — 안뜰 여섯 자리와 캐릭터 인벤토리
# --------------------------------------------------------------------------- #
## 그 캐릭터가 지금 어디에 있는가. ["field"|"bench", 자리] 를 돌려준다. 없으면 ["", -1].
##
## ★ 배열 자체를 돌려주지 않는다. GDScript 의 `==` 는 배열을 **값으로** 비교해서,
##   돌려받은 배열이 heroes 인지 bench 인지를 `arr == heroes` 로 물으면 내용이 우연히
##   같을 때 엉뚱한 답이 나온다. 어디에 있었는지는 찾은 쪽이 말해 주는 것이 맞다.
func find_hero(unit_id: String) -> Array:
	for i in range(heroes.size()):
		if String(heroes[i]["unit"]["id"]) == unit_id:
			return ["field", i]
	for i in range(bench.size()):
		if String(bench[i]["unit"]["id"]) == unit_id:
			return ["bench", i]
	return ["", -1]


func field_full() -> bool:
	return heroes.size() >= Balance.HERO_SLOTS


## 새로 뽑은 영웅 하나를 받는다.
##
## 규칙(사용자가 정한 것):
##  - **같은 캐릭터가 또 나오면 옆에 세우지 않는다.** 이미 있는 그 캐릭터에 겹쳐서
##    공격력을 배로 올린다. 안뜰에 있든 인벤토리에 있든 그 자리에서 겹친다.
##  - 처음 보는 캐릭터인데 안뜰이 비어 있으면 바로 세운다.
##  - 안뜰이 꽉 찼으면 **인벤토리로 들어간다.** 누구를 물리고 이 애를 세울지는
##    플레이어가 고른다(뽑기 화면의 교체 창 · 상점의 영웅 탭).
##
## 돌려주는 것: {"stacked": 겹쳤는가, "where": "field"|"bench", "slot": 자리, "n": 겹친 수}
func gain_hero(unit: Dictionary, tier: int) -> Dictionary:
	var found := find_hero(String(unit.get("id", "")))
	if found[1] >= 0:
		var where := String(found[0])
		var i: int = found[1]
		var arr: Array = heroes if where == "field" else bench
		arr[i]["n"] = int(arr[i].get("n", 1)) + 1
		return {"stacked": true, "where": where, "slot": i, "n": int(arr[i]["n"])}
	var h := {"unit": unit, "tier": tier, "wave": wave, "n": 1}
	if not field_full():
		heroes.append(h)
		return {"stacked": false, "where": "field", "slot": heroes.size() - 1, "n": 1}
	# ★ 인벤토리가 넘칠 일은 없다 — 캐릭터가 31명이고 벤치가 25칸이다(Balance 참고).
	#   그래도 셈이 틀렸을 때 영웅이 조용히 사라지지는 않게, 가장 오래된 것을 밀어낸다.
	if bench.size() >= Balance.BENCH_SLOTS:
		bench.remove_at(0)
	bench.append(h)
	return {"stacked": false, "where": "bench", "slot": bench.size() - 1, "n": 1}


## 안뜰의 f 번과 인벤토리의 b 번을 맞바꾼다. b 가 -1 이면 안뜰에서 인벤토리로 물린다.
## ★ 여기 한 곳에서만 두 배열을 건드린다. 화면 두 곳(뽑기·상점)이 같은 규칙을 봐야
##   "상점에서는 바뀌는데 뽑기 화면에서는 안 바뀌는" 종류의 어긋남이 안 생긴다.
func swap_field_bench(f: int, b: int) -> bool:
	if f < 0 or f >= heroes.size():
		return false
	if b < 0:
		if bench.size() >= Balance.BENCH_SLOTS:
			return false
		bench.append(heroes[f])
		heroes.remove_at(f)
		return true
	if b >= bench.size():
		return false
	var t = heroes[f]
	heroes[f] = bench[b]
	bench[b] = t
	return true


## 인벤토리의 b 번을 안뜰의 빈 자리에 세운다. 자리가 없으면 거짓.
func bench_to_field(b: int) -> bool:
	if b < 0 or b >= bench.size() or field_full():
		return false
	heroes.append(bench[b])
	bench.remove_at(b)
	return true


## 안뜰 안에서 자리를 바꾼다. 서는 자리가 곧 사거리라 순서에도 뜻이 있다.
func swap_field(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= heroes.size() or b >= heroes.size():
		return false
	var t = heroes[a]
	heroes[a] = heroes[b]
	heroes[b] = t
	return true


## 안뜰 + 인벤토리를 통틀어 겹친 것까지 센 영웅 수. "여태 몇 명 뽑았나"가 이 값이다.
func hero_total() -> int:
	var n := 0
	for h in heroes:
		n += int(h.get("n", 1))
	for h in bench:
		n += int(h.get("n", 1))
	return n


# --------------------------------------------------------------------------- #
# 무기 — 장착한 것들이 **모든 영웅에게 함께** 걸린다
# --------------------------------------------------------------------------- #
## 장착한 무기들의 곱셈 효과를 모은다(공격력·공격속도·사거리·골드·광역 반경).
## ★ 전투(BattleSim)와 상점 표시가 반드시 이 함수를 함께 써야 "상점에는 +18% 라고
##   적혀 있는데 실제로는 안 오르는" 종류의 어긋남이 안 생긴다.
func wpn_mult(key: String) -> float:
	var m := 1.0
	for id in weapons:
		var w := Balance.weapon_by_id(String(id))
		m *= float(w.get(key, 1.0))
	return m


## 장착한 무기들의 덧셈 효과(치명타 확률처럼 확률로 더하는 것).
func wpn_add(key: String) -> float:
	var s := 0.0
	for id in weapons:
		var w := Balance.weapon_by_id(String(id))
		s += float(w.get(key, 0.0))
	return s


## 그 효과를 가진 무기 중 가장 센 값. 둔화처럼 **겹치지 않고 센 쪽만** 쓰는 것에.
func wpn_best(key: String) -> float:
	var best := 0.0
	for id in weapons:
		var w := Balance.weapon_by_id(String(id))
		best = max(best, float(w.get(key, 0.0)))
	return best


func has_weapon(id: String) -> bool:
	return weapons.has(id)


func weapon_full() -> bool:
	return weapons.size() >= Balance.WEAPON_SLOTS


## 무기를 산다. 칸이 다 찼거나 이미 있으면 못 산다(먼저 하나 빼야 한다).
func buy_weapon(id: String) -> bool:
	if has_weapon(id) or weapon_full():
		return false
	var w := Balance.weapon_by_id(id)
	if w.is_empty() or gold < int(w["cost"]):
		return false
	add_gold(-int(w["cost"]))
	weapons.append(id)
	return true


## 무기를 빼고 절반을 돌려받는다.
func sell_weapon(id: String) -> bool:
	if not has_weapon(id):
		return false
	weapons.erase(id)
	add_gold(Balance.weapon_refund(id))
	return true


# --------------------------------------------------------------------------- #
# 아이템 — 사 두었다가 전투 중에 쓴다
# --------------------------------------------------------------------------- #
func item_count(id: String) -> int:
	return int(items.get(id, 0))


func buy_item(id: String) -> bool:
	var it := Balance.item_by_id(id)
	if it.is_empty() or item_count(id) >= Balance.ITEM_MAX or gold < int(it["cost"]):
		return false
	add_gold(-int(it["cost"]))
	items[id] = item_count(id) + 1
	return true


## 하나 쓴다. 실제 효과는 전투 쪽(BattleSim.use_item)이 낸다 —
## 여기서는 **개수만** 줄인다. 화면이 없는 검사기에서도 같은 셈이 돌아야 한다.
func spend_item(id: String) -> bool:
	if item_count(id) <= 0:
		return false
	items[id] = item_count(id) - 1
	if int(items[id]) <= 0:
		items.erase(id)
	return true


## 지금 가진 아이템 목록 (표에 적힌 순서대로).
func item_list() -> Array:
	var out: Array = []
	for it in Balance.ITEMS:
		if item_count(String(it["id"])) > 0:
			out.append(it)
	return out


# --------------------------------------------------------------------------- #
# 영웅의 실제 능력치 — 전투와 검사기가 **이 함수 하나만** 쓴다
# --------------------------------------------------------------------------- #
func hero_stats(h: Dictionary) -> Dictionary:
	var u: Dictionary = h["unit"]
	var t: int = int(h["tier"])
	var prof: Dictionary = Balance.PROFILE[String(u.get("profile", "balance"))]
	var bul: Dictionary = Balance.BULLET[String(u.get("bullet", "shot"))]
	# ★ 같은 캐릭터가 겹친 만큼 **공격력만** 배가 된다(공격속도·사거리는 그대로).
	#   같은 영웅 n명을 나란히 세웠던 예전과 단일 대상 피해가 정확히 같아지는 값이다.
	var atk: float = Balance.TIER_ATK[t] * float(prof["atk"]) * float(bul["dmg"]) \
			* Balance.stack_atk(int(h.get("n", 1))) \
			* Balance.atk_mult(lv("atk")) * wpn_mult("atk")
	var rate: float = Balance.TIER_RATE[t] * float(prof["rate"]) \
			* Balance.rate_mult(lv("rate")) * wpn_mult("rate")
	var rng_px: float = Balance.TIER_RNG[t] * float(prof["rng"]) \
			* Balance.rng_mult(lv("rng")) * wpn_mult("rng")
	return {
		"atk": atk, "rate": rate, "rng": rng_px,
		"bullet": String(u.get("bullet", "shot")),
		"crit": min(0.85, Balance.crit_chance(lv("crit")) + wpn_add("crit")),
		"critx": Balance.crit_mult(lv("critx")),
	}


## 지금 세워 둔 영웅 전부의 **단일 대상** 초당 데미지 합(치명타 기대값 포함).
## ⚠ 광역·연쇄·장판이 여럿을 동시에 때리는 몫은 여기 안 들어간다. 어림수로만 써라.
func total_dps() -> float:
	var s := 0.0
	for h in heroes:
		var st := hero_stats(h)
		var mult: float = 1.0 + float(st["crit"]) * (float(st["critx"]) - 1.0)
		s += float(st["atk"]) * float(st["rate"]) * mult
	return s


# --------------------------------------------------------------------------- #
# 상점
# --------------------------------------------------------------------------- #
func buy_upgrade(id: String) -> bool:
	var l := lv(id)
	if Balance.upgrade_maxed(id, l):
		return false
	var cost := Balance.upgrade_cost(id, l)
	if gold < cost:
		return false
	add_gold(-cost)
	levels[id] = l + 1
	if id == "life":
		add_lives(1)     # 최대치가 같이 오르므로 실제로 한 칸 는다
	return true


func buy_passive(id: String) -> bool:
	if passives.has(id):
		return false
	for p in Balance.PASSIVES:
		if p["id"] == id:
			if gold < int(p["cost"]):
				return false
			add_gold(-int(p["cost"]))
			passives[id] = true
			return true
	return false


## 상점이 이번에 내놓을 패시브 셋. 이미 산 것은 빼고 고른다.
func offer_passives(n: int = 3) -> Array:
	var pool: Array = []
	for p in Balance.PASSIVES:
		if not passives.has(p["id"]):
			pool.append(p)
	_shuffle(pool)
	return pool.slice(0, mini(n, pool.size()))
