extends RefCounted
class_name Poker

## 트럼프 카드와 족보 판정. **순수 함수만 있다** — 화면도 저장도 모른다.
##
## 이 파일이 게임 전체의 심장이다. 여기가 틀리면 "풀하우스인데 원페어 캐릭이 나오는"
## 종류의 버그가 나고, 그건 플레이어가 게임을 못 믿게 만든다.
## 그래서 tests/poker_check.gd 가 **7,462,080가지 5장 조합을 전수로** 돌려
## 각 족보의 개수가 수학적으로 알려진 값과 정확히 같은지 확인한다.

## 무늬. 순서는 화면 표시 순서일 뿐 세기와 무관하다(포커에는 무늬 우열이 없다).
enum Suit { SPADE, HEART, DIAMOND, CLUB }

## 족보. **값이 곧 등급**이고 캐릭터 등급 인덱스와 1:1 이다. ★값을 바꾸지 마라 —
## 저장 파일과 core/roster.gd 의 티어 인덱스가 이 숫자를 쓴다.
enum Hand {
	HIGH = 0,        ## 하이카드
	PAIR = 1,        ## 원페어
	TWO_PAIR = 2,    ## 투페어
	TRIPS = 3,       ## 트리플
	STRAIGHT = 4,    ## 스트레이트
	FLUSH = 5,       ## 플러시
	FULL_HOUSE = 6,  ## 풀하우스   ★여기부터 화려한 연출
	QUADS = 7,       ## 포카드     ★
	STRAIGHT_FLUSH = 8, ## 스트레이트 플러시 ★
	ROYAL = 9,       ## 로열 스트레이트 플러시 ★
}

## 화려한 연출을 켜는 경계. "풀하우스 이상급으로 걸리면 좀 이펙트 화려하게".
const SHOWY := Hand.FULL_HOUSE

const HAND_KO := {
	Hand.HIGH: "하이카드",
	Hand.PAIR: "원페어",
	Hand.TWO_PAIR: "투페어",
	Hand.TRIPS: "트리플",
	Hand.STRAIGHT: "스트레이트",
	Hand.FLUSH: "플러시",
	Hand.FULL_HOUSE: "풀하우스",
	Hand.QUADS: "포카드",
	Hand.STRAIGHT_FLUSH: "스트레이트 플러시",
	Hand.ROYAL: "로열 스트레이트 플러시",
}

## ★ 무늬는 **글자로 그리지 않는다.** 번들 폰트(DinoKR = Noto Sans CJK KR)에
##   ♠(U+2660) · ♦(U+2666) · ♣(U+2663) 가 아예 없어서 화면에서 두부(□)로 깨진다.
##   ♥ 하나만 있다. 카드 게임에서 무늬가 깨지면 게임이 통째로 못 읽게 되므로
##   무늬는 Look.draw_suit() 이 도형으로 그린다. 여기 이름은 **말로 할 때만** 쓴다.
##   (tools/check_font.py 가 이걸 지킨다 — 무늬 글자를 다시 넣으면 검사가 막는다)
const SUIT_KO := ["스페이드", "하트", "다이아", "클럽"]
## 2~10 은 숫자, 그 위는 글자. 인덱스가 곧 rank(2..14) - 2 다.
const RANK_CHAR := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

const RANK_MIN := 2
const RANK_MAX := 14   ## 에이스


## 카드 한 장. 정수 하나로 표현한다 — 저장·비교·중복검사가 전부 공짜가 된다.
## code = (rank - 2) * 4 + suit,  0..51
static func code(rank: int, suit: int) -> int:
	return (rank - RANK_MIN) * 4 + suit


static func rank_of(c: int) -> int:
	return c / 4 + RANK_MIN


static func suit_of(c: int) -> int:
	return c % 4


## 말로 하는 카드 이름. 화면의 카드 그림은 Look.draw_card 가 따로 그린다.
static func card_text(c: int) -> String:
	return "%s %s" % [SUIT_KO[suit_of(c)], RANK_CHAR[rank_of(c) - RANK_MIN]]


## 52장 한 벌. 셔플은 부르는 쪽이 한다(시드를 쥔 쪽이 결정해야 재현이 된다).
static func full_deck() -> Array[int]:
	var d: Array[int] = []
	for c in range(52):
		d.append(c)
	return d


## 5장의 족보를 판정한다. 5장이 아니거나 같은 카드가 섞여 있으면 -1.
##
## ⚠ 스트레이트에서 **A는 양쪽 끝에 다 선다**: A-2-3-4-5(휠, 가장 낮은 스트레이트)와
##   10-J-Q-K-A(가장 높은 것) 둘 다 스트레이트다. 이걸 빼먹는 것이 이 판정에서
##   제일 흔한 실수라, 전수 검사가 이 경우만 따로 센다.
static func evaluate(cards: Array) -> int:
	if cards.size() != 5:
		return -1
	var seen := {}
	var counts := {}          # rank -> 몇 장
	var suits := {}           # suit -> 몇 장
	for c in cards:
		var ci := int(c)
		if ci < 0 or ci > 51 or seen.has(ci):
			return -1
		seen[ci] = true
		var r := rank_of(ci)
		var s := suit_of(ci)
		counts[r] = int(counts.get(r, 0)) + 1
		suits[s] = int(suits.get(s, 0)) + 1

	var flush := suits.size() == 1

	# 같은 숫자가 몇 장씩인지를 내림차순으로 — [4,1]=포카드, [3,2]=풀하우스 ...
	var shape: Array[int] = []
	for r in counts:
		shape.append(int(counts[r]))
	shape.sort()
	shape.reverse()

	var straight_high := _straight_high(counts)
	var straight := straight_high > 0

	if straight and flush:
		# 10-J-Q-K-A 만 로열. 휠(A-2-3-4-5)은 straight_high 가 5 라 여기 안 걸린다.
		return Hand.ROYAL if straight_high == RANK_MAX else Hand.STRAIGHT_FLUSH
	if shape[0] == 4:
		return Hand.QUADS
	if shape[0] == 3 and shape[1] == 2:
		return Hand.FULL_HOUSE
	if flush:
		return Hand.FLUSH
	if straight:
		return Hand.STRAIGHT
	if shape[0] == 3:
		return Hand.TRIPS
	if shape[0] == 2 and shape[1] == 2:
		return Hand.TWO_PAIR
	if shape[0] == 2:
		return Hand.PAIR
	return Hand.HIGH


## 스트레이트면 가장 높은 숫자를, 아니면 0 을 준다. 휠은 5 를 준다(가장 약한 스트레이트).
static func _straight_high(counts: Dictionary) -> int:
	if counts.size() != 5:
		return 0
	var rs: Array[int] = []
	for r in counts:
		rs.append(int(r))
	rs.sort()
	if rs[4] - rs[0] == 4:
		return rs[4]
	# 휠: A(14)-2-3-4-5
	if rs == [2, 3, 4, 5, RANK_MAX]:
		return 5
	return 0


## 족보를 이룬 카드만 골라 준다. 화면에서 "이 세 장이 트리플이었다"를 밝게 비추는 데 쓴다.
## 하이카드는 제일 높은 한 장, 플러시·스트레이트는 다섯 장 전부.
static func key_cards(cards: Array, hand: int) -> Array[int]:
	var out: Array[int] = []
	if cards.size() != 5:
		return out
	match hand:
		Hand.STRAIGHT, Hand.FLUSH, Hand.STRAIGHT_FLUSH, Hand.ROYAL:
			for c in cards:
				out.append(int(c))
			return out
		Hand.HIGH:
			var best := -1
			var best_r := -1
			for c in cards:
				var r := rank_of(int(c))
				# A 가 있으면 A. 없으면 제일 큰 숫자.
				if r > best_r:
					best_r = r
					best = int(c)
			out.append(best)
			return out
	var counts := {}
	for c in cards:
		var r := rank_of(int(c))
		counts[r] = int(counts.get(r, 0)) + 1
	for c in cards:
		if int(counts[rank_of(int(c))]) >= 2:
			out.append(int(c))
	return out
