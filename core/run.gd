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

## 지금까지 뽑아 놓은 영웅들. 각 원소는
##   {"unit": <Roster 의 표 한 줄>, "tier": int, "wave": int}
var heroes: Array = []

## 상점에서 산 능력치 단계. id -> lv
var levels: Dictionary = {}
## 산 패시브 id 들.
var passives: Dictionary = {}

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
	levels.clear()
	passives.clear()
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


func end_run(won: bool) -> void:
	running = false
	phase = Phase.WIN if won else Phase.OVER
	Save.record_run(wave, kills, won)


func lv(id: String) -> int:
	return int(levels.get(id, 0))


func has(passive_id: String) -> bool:
	return passives.has(passive_id)


func max_lives() -> int:
	return Balance.START_LIVES + lv("life")


func round_seconds() -> float:
	return Balance.round_sec(wave) + 2.0 * float(lv("time"))


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
	heroes.append({"unit": unit, "tier": hand, "wave": wave})
	Save.record_hand(hand, String(unit.get("id", "")))
	return {"hand": hand, "cards": last_cards, "key": last_key, "unit": unit,
			"bumped": last_bumped, "joker": last_joker,
			"showy": hand >= Poker.SHOWY}


# --------------------------------------------------------------------------- #
# 영웅의 실제 능력치 — 전투와 검사기가 **이 함수 하나만** 쓴다
# --------------------------------------------------------------------------- #
func hero_stats(h: Dictionary) -> Dictionary:
	var u: Dictionary = h["unit"]
	var t: int = int(h["tier"])
	var prof: Dictionary = Balance.PROFILE[String(u.get("profile", "balance"))]
	var bul: Dictionary = Balance.BULLET[String(u.get("bullet", "shot"))]
	var atk: float = Balance.TIER_ATK[t] * float(prof["atk"]) * float(bul["dmg"]) \
			* Balance.atk_mult(lv("atk"))
	var rate: float = Balance.TIER_RATE[t] * float(prof["rate"]) * Balance.rate_mult(lv("rate"))
	var rng_px: float = Balance.TIER_RNG[t] * float(prof["rng"]) * Balance.rng_mult(lv("rng"))
	return {
		"atk": atk, "rate": rate, "rng": rng_px,
		"bullet": String(u.get("bullet", "shot")),
		"crit": Balance.crit_chance(lv("crit")),
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
