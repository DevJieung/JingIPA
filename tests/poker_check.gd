extends Node

## 족보 판정을 **전수로** 검사한다. 52장에서 5장을 고르는 2,598,960가지를 전부 돌려
## 족보별 개수가 수학적으로 알려진 값과 한 개도 틀리지 않는지 본다.
##
## 왜 전수인가: 표본으로 돌리면 "A-2-3-4-5(휠)를 스트레이트로 안 세는" 같은 좁은 버그가
## 그냥 지나간다. 실제로 이 판정에서 제일 흔한 실수가 그것이다.
## 전수로 세면 스트레이트 개수가 10200 이 아니라 10176 으로 나와서 **반드시** 걸린다.
##
##   godot --headless --path . res://tests/poker_check.tscn
##   godot --headless --path . res://tests/poker_check.tscn -- --quick   (표본 20만)

## 5장 포커의 족보별 가짓수. 어느 포커 책에나 있는 값이다.
const EXPECT := {
	Poker.Hand.ROYAL: 4,
	Poker.Hand.STRAIGHT_FLUSH: 36,
	Poker.Hand.QUADS: 624,
	Poker.Hand.FULL_HOUSE: 3744,
	Poker.Hand.FLUSH: 5108,
	Poker.Hand.STRAIGHT: 10200,
	Poker.Hand.TRIPS: 54912,
	Poker.Hand.TWO_PAIR: 123552,
	Poker.Hand.PAIR: 1098240,
	Poker.Hand.HIGH: 1302540,
}
const TOTAL := 2598960


func _ready() -> void:
	var quick := Harness.has_arg("--quick")
	var fail := 0
	fail += _check_basics()
	if quick:
		fail += _check_sample()
	else:
		fail += _check_all()
	fail += _check_key_cards()
	if fail == 0:
		print("판정: 정상")
	else:
		printerr("!! 실패 %d건" % fail)
	get_tree().quit(0 if fail == 0 else 1)


func _bad(msg: String) -> int:
	printerr("!! " + msg)
	return 1


func _check_basics() -> int:
	var fail := 0
	# 카드 번호 ↔ (숫자, 무늬) 왕복
	for c in range(52):
		var r := Poker.rank_of(c)
		var s := Poker.suit_of(c)
		if Poker.code(r, s) != c:
			fail += _bad("카드 번호 왕복 실패: %d" % c)
			break
	# 손으로 확인하는 대표 다섯 판
	var cases := [
		[[Poker.code(14, 0), Poker.code(13, 0), Poker.code(12, 0), Poker.code(11, 0),
		  Poker.code(10, 0)], Poker.Hand.ROYAL, "로열"],
		[[Poker.code(5, 1), Poker.code(4, 1), Poker.code(3, 1), Poker.code(2, 1),
		  Poker.code(14, 1)], Poker.Hand.STRAIGHT_FLUSH, "휠 스트레이트 플러시"],
		[[Poker.code(14, 0), Poker.code(2, 1), Poker.code(3, 2), Poker.code(4, 3),
		  Poker.code(5, 0)], Poker.Hand.STRAIGHT, "휠(A-2-3-4-5)"],
		[[Poker.code(10, 0), Poker.code(11, 1), Poker.code(12, 2), Poker.code(13, 3),
		  Poker.code(14, 0)], Poker.Hand.STRAIGHT, "10-J-Q-K-A"],
		[[Poker.code(13, 0), Poker.code(14, 1), Poker.code(2, 2), Poker.code(3, 3),
		  Poker.code(4, 0)], Poker.Hand.HIGH, "K-A-2-3-4 는 스트레이트가 아니다"],
	]
	for cs in cases:
		var got: int = Poker.evaluate(cs[0])
		if got != cs[1]:
			fail += _bad("%s: %s 가 나왔다 (%s 여야 한다)"
					% [cs[2], Poker.HAND_KO.get(got, got), Poker.HAND_KO[cs[1]]])
	# 잘못된 입력은 -1
	if Poker.evaluate([0, 1, 2]) != -1:
		fail += _bad("5장이 아닌데 -1 이 아니다")
	if Poker.evaluate([0, 0, 1, 2, 3]) != -1:
		fail += _bad("같은 카드가 둘인데 -1 이 아니다")
	return fail


func _check_all() -> int:
	var count := {}
	for h in EXPECT:
		count[h] = 0
	var n := 0
	var t0 := Time.get_ticks_msec()
	for a in range(52):
		for b in range(a + 1, 52):
			for c in range(b + 1, 52):
				for d in range(c + 1, 52):
					for e in range(d + 1, 52):
						var h := Poker.evaluate([a, b, c, d, e])
						count[h] = int(count[h]) + 1
						n += 1
		if a % 10 == 0:
			print("  … %d/52 (%d판)" % [a, n])
	var fail := 0
	if n != TOTAL:
		fail += _bad("전체 가짓수가 %d 다 (%d 여야 한다)" % [n, TOTAL])
	for h in EXPECT:
		var got := int(count[h])
		var want := int(EXPECT[h])
		var mark := "ok" if got == want else "!!"
		print("  %s %-20s %8d (기대 %8d)" % [mark, Poker.HAND_KO[h], got, want])
		if got != want:
			fail += 1
	print("  전수 검사 %d판, %.1f초" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	return fail


## 빠른 검사: 무작위 20만 판을 돌려 **비율**이 이론값 근처인지만 본다.
func _check_sample() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260822
	var count := {}
	for h in EXPECT:
		count[h] = 0
	var n := 200000
	var deck := Poker.full_deck()
	for i in range(n):
		for k in range(5):
			var j := rng.randi_range(k, 51)
			var t = deck[k]
			deck[k] = deck[j]
			deck[j] = t
		var h := Poker.evaluate(deck.slice(0, 5))
		count[h] = int(count[h]) + 1
	var fail := 0
	for h in EXPECT:
		var want: float = float(EXPECT[h]) / float(TOTAL)
		var got: float = float(count[h]) / float(n)
		# 드문 족보는 표본으로 못 잡으므로 흔한 것만 본다.
		if want > 0.001 and abs(got - want) > want * 0.12:
			fail += _bad("%s 비율 %.4f%% (기대 %.4f%%)"
					% [Poker.HAND_KO[h], got * 100.0, want * 100.0])
	print("  표본 %d판" % n)
	return fail


## 족보를 이룬 카드를 제대로 골라 주는가 (화면에서 그 카드만 금색으로 비춘다).
func _check_key_cards() -> int:
	var fail := 0
	var pair := [Poker.code(7, 0), Poker.code(7, 1), Poker.code(2, 2), Poker.code(9, 3),
			Poker.code(11, 0)]
	var k := Poker.key_cards(pair, Poker.Hand.PAIR)
	if k.size() != 2:
		fail += _bad("원페어의 핵심 카드가 %d장이다 (2장이어야 한다)" % k.size())
	var fh := [Poker.code(7, 0), Poker.code(7, 1), Poker.code(7, 2), Poker.code(9, 3),
			Poker.code(9, 0)]
	if Poker.key_cards(fh, Poker.Hand.FULL_HOUSE).size() != 5:
		fail += _bad("풀하우스의 핵심 카드가 5장이 아니다")
	var hi := [Poker.code(14, 0), Poker.code(7, 1), Poker.code(3, 2), Poker.code(9, 3),
			Poker.code(11, 0)]
	var kh := Poker.key_cards(hi, Poker.Hand.HIGH)
	if kh.size() != 1 or Poker.rank_of(kh[0]) != 14:
		fail += _bad("하이카드의 핵심 카드가 A 가 아니다")
	return fail
