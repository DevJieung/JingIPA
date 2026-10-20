extends RefCounted
class_name JewelBox

## 보석상자 — 투기장의 소환 규칙(2026-10-19 피드백 F10 · U1 · U2 · M1, docs/JEWEL_BOX.md).
##
## 상자를 열면 등급(1~5성)이 정해지고 영웅 카드가 나온다. 한 장(보장 카드)은 상자 등급 이상이고, 나머지는
## 저마다 굴려 상자보다 높을 수도 있다. 같은 영웅은 두 번 나오지 않는다. 플레이어는 하나를 고른다.
## 다시 뽑기는 상자 등급을 다시 굴리되 내려가지 않고(새 등급 = max(지금, 굴림)) 카드를 모두 새로 낸다.
##
## ★ 순수 함수만 둔다 — 화면도 저장도 모른다. 굴림은 부르는 쪽이 넘긴 난수(판의 rng)로 하므로, 같은 판
##   상태에서는 언제나 같은 상자가 나온다(저장했다 이어 해도 같은 카드, 껐다 켜서 다시 굴릴 수 없다).
## ★ 등급은 정수 별(1~5)이고 영웅의 등급 칸은 별 x 2 - 1 이다(반 별은 성장 · 도박꾼의 눈 · 승급에서만).
##   옛 100탄 모드의 의식(core/rite.gd)과는 따로다.
const MAX_STARS := 5

## 무게를 합이 1 이 되게 나눈다(1~5성 차례). 합이 0 이면 1성만.
static func odds(weights: Array) -> Array[float]:
	var total := 0.0
	for w in weights: total += maxf(0.0, float(w))
	var out: Array[float] = []
	for i in range(MAX_STARS):
		var w := maxf(0.0, float(weights[i])) if i < weights.size() else 0.0
		out.append(w / total if total > 0.0 else (1.0 if i == 0 else 0.0))
	return out

## 무게대로 별 수(1~5)를 굴린다. floor_stars 보다 낮게 나오면 floor_stars 다.
static func roll(rng: RandomNumberGenerator, weights: Array, floor_stars: int = 1) -> int:
	var chances := odds(weights)
	var r := rng.randf()
	var stars := MAX_STARS
	var acc := 0.0
	for i in range(MAX_STARS):
		acc += chances[i]
		if r < acc:
			stars = i + 1
			break
	return clampi(maxi(stars, floor_stars), 1, MAX_STARS)

## 상자의 카드: 후보(pool)에서 겹치지 않게 min(count, 후보 수) 명을 뽑는다. 무작위로 한 장이 보장 카드이고
## 그 별은 max(상자 등급, 굴림), 나머지는 card_weights 로 저마다 굴린다. 항목 {unit, stars, guaranteed}.
static func deal(rng: RandomNumberGenerator, pool: Array, grade: int, count: int, card_weights: Array) -> Array:
	var units := pool.duplicate()
	var n := mini(count, units.size())
	# 부분 피셔-예이츠: 앞의 n 자리만 섞어 뽑는다.
	for i in range(n):
		var j := rng.randi_range(i, units.size() - 1)
		var held = units[i]
		units[i] = units[j]
		units[j] = held
	var cards: Array = []
	if n == 0:
		return cards
	var guaranteed := rng.randi_range(0, n - 1)
	for i in range(n):
		var stars := roll(rng, card_weights)
		if i == guaranteed:
			stars = maxi(clampi(grade, 1, MAX_STARS), stars)
		cards.append({"unit": units[i], "stars": stars, "guaranteed": i == guaranteed})
	return cards

## 별 수의 영웅 등급 칸(반 별 칸 0~9).
static func tier_of(stars: int) -> int:
	return clampi(stars, 1, MAX_STARS) * 2 - 1

## 가장 좋은 카드: 별이 가장 많은 것, 같으면 보장 카드, 그다음 앞의 것. 카드가 없으면 -1.
static func best(cards: Array) -> int:
	var at := -1
	for i in range(cards.size()):
		if at < 0:
			at = i
			continue
		var stars := int(cards[i]["stars"])
		var top := int(cards[at]["stars"])
		if stars > top or (stars == top and bool(cards[i]["guaranteed"]) and not bool(cards[at]["guaranteed"])):
			at = i
	return at

## 저장된 상자({tier, cards:[{u, s, g}], spins, paid})가 규칙에 맞는가. choosing 이면(상자를 고르는 중)
## 카드가 있어야 하고, 최종 강화에 닿은 영웅(maxed: id → true)의 카드는 없어야 한다. 상자가 닫힌 뒤에는
## 비어 있어도 된다.
## 저장 검사가 받아 주는 카드 수의 고정 상한 — ARENA_BOX_CARDS 가 줄어도 하던 판의 상자는 그대로 받는다.
const SAVE_CARDS_MAX := 12

static func valid(box: Variant, maxed: Dictionary, choosing: bool) -> bool:
	if not box is Dictionary:
		return false
	for key in ["tier", "spins", "paid"]:
		if not box.get(key) is int or box[key] < 0:
			return false
	if box["paid"] > box["spins"] or not box.get("cards") is Array:
		return false
	var cards: Array = box["cards"]
	if cards.is_empty():
		return not choosing
	if box["tier"] < 1 or box["tier"] > MAX_STARS or cards.size() > SAVE_CARDS_MAX:
		return false
	var seen := {}
	var top := 0
	var guaranteed := 0
	for card in cards:
		if not card is Dictionary or not card.get("u") is String or not card.get("s") is int or not card.get("g") is bool:
			return false
		var id: String = card["u"]
		if Roster.unit_by_id(id).is_empty() or seen.has(id) or (choosing and maxed.has(id)):
			return false
		seen[id] = true
		if card["s"] < 1 or card["s"] > MAX_STARS:
			return false
		top = maxi(top, int(card["s"]))
		if card["g"]:
			guaranteed += 1
			if card["s"] < box["tier"]:
				return false
	return guaranteed == 1 and top >= box["tier"]

## 안내용: 상자 등급의 확률(1~5성).
static func grade_odds() -> Array[float]:
	return odds(Balance.arena_box_weights())

## 안내용: 카드 count 장 상자에서 가장 좋은 카드가 k성 이상일 확률(k = 1~5). 보장 카드가 하나, 나머지는
## 저마다 굴린다.
static func best_at_least(count: int = Balance.ARENA_BOX_CARDS) -> Array[float]:
	var grade := grade_odds()
	var card := odds(Balance.arena_card_weights())
	var out: Array[float] = []
	for k in range(1, MAX_STARS + 1):
		# P(카드 하나가 k 미만), P(보장 카드가 k 미만) = P(상자 < k) x P(굴림 < k).
		var card_below := 0.0
		var grade_below := 0.0
		for s in range(1, k):
			card_below += card[s - 1]
			grade_below += grade[s - 1]
		var all_below := grade_below * card_below * pow(card_below, maxi(0, count - 1))
		out.append(1.0 - all_below)
	return out
