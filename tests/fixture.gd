extends RefCounted
class_name Fixture

## 검사·촬영이 세우는 **판**. 「n탄까지 간 판」 · 「원하는 족보가 나오는 손패」 —
## shot.gd 와 demo.gd 가 같은 손으로 베껴 쓰던 것을 한 곳에 둔다.
##
## ★ 배열을 직접 만지는 것은 tests/ 라서 괜찮다. 화면에서 그러면 안 된다(CLAUDE.md 14-3).

## 원하는 족보가 나오는 손패. 인덱스는 Poker.Hand 값이다.
## ★ `const` 로 못 둔다 — Poker.code() 호출은 상수식이 아니라서 파스가 깨진다.
##   (`var c := Poker.code` 처럼 static 함수를 변수에 담아 c(...) 로 부르는 것도 같은
##   이유로 깨진다. 그냥 풀어 쓴다.)
static func hands() -> Dictionary:
	return {
		0: [Poker.code(14, 0), Poker.code(10, 1), Poker.code(7, 2), Poker.code(5, 3), Poker.code(3, 0)],
		1: [Poker.code(11, 0), Poker.code(11, 1), Poker.code(7, 2), Poker.code(5, 3), Poker.code(3, 0)],
		2: [Poker.code(11, 0), Poker.code(11, 1), Poker.code(7, 2), Poker.code(7, 3), Poker.code(3, 0)],
		3: [Poker.code(9, 0), Poker.code(9, 1), Poker.code(9, 2), Poker.code(5, 3), Poker.code(3, 0)],
		4: [Poker.code(9, 0), Poker.code(8, 1), Poker.code(7, 2), Poker.code(6, 3), Poker.code(5, 0)],
		5: [Poker.code(14, 2), Poker.code(10, 2), Poker.code(8, 2), Poker.code(5, 2), Poker.code(3, 2)],
		6: [Poker.code(12, 0), Poker.code(12, 1), Poker.code(12, 2), Poker.code(6, 3), Poker.code(6, 0)],
		7: [Poker.code(8, 0), Poker.code(8, 1), Poker.code(8, 2), Poker.code(8, 3), Poker.code(13, 0)],
		8: [Poker.code(9, 1), Poker.code(8, 1), Poker.code(7, 1), Poker.code(6, 1), Poker.code(5, 1)],
		9: [Poker.code(14, 0), Poker.code(13, 0), Poker.code(12, 0), Poker.code(11, 0), Poker.code(10, 0)],
	}


## 새 판을 열고 첫 탄의 카드를 돌린다. `count` 명이면 표의 앞에서부터 그만큼 영웅을 준다.
static func fresh(seed_value: int, count: int = 0) -> void:
	Run.start_run(seed_value)
	Run.begin_draw()
	for i in range(count):
		var u: Dictionary = Roster.UNITS[i]
		Run.gain_hero(u, int(u["tier"]))


## 원하는 탄까지 상태를 만든다(영웅 n명 · 골드 넉넉히). `wave` 탄을 **뽑기 직전**(wave = w-1)
## 까지 만들어 두므로, 부르는 쪽이 `Run.begin_draw()` 로 그 탄을 연다.
static func prepare(wave: int, seed_value: int) -> void:
	Run.start_run(seed_value)
	Run.gold = 400 + wave * 90
	for i in range(maxi(0, wave - 1)):
		Run.begin_draw()
		Run.confirm_hand()
	# ★ 성역은 자리가 정해져 있다. 사람이라면 센 쪽을 세워 두므로 검사 정책과 같은 손으로
	#   정리해 둔다 — 안 그러면 사진 속 성역이 "먼저 뽑은 것들"이라 실제 화면과 다르다.
	PlayPolicy.arrange(Run)
	# 상점을 몇 번 거친 것처럼 능력치도 조금 올려 둔다 — 빈 상점은 실제 화면이 아니다.
	Run.levels["atk"] = int(wave / 3)
	Run.levels["rate"] = int(wave / 5)
	# ★ **상한(cap)이 있는 능력치는 그 위로 못 올린다.** 공격속도 등 상한이 있는 줄은
	#   현재 강화 표를 따라 검사·촬영용 단계도 제한한다.
	#   여기에 그런 줄을 하나라도 더하는 날, 이 고리가 없으면 사진이 **상점에서 살 수도
	#   없는 판**을 보여 주게 된다 — 없앤 사거리 줄이 실제로 그랬다(42탄이면 7단계로
	#   박히는데 상점은 6단계까지만 팔았다).
	for k in Run.levels.keys():
		var cap: int = int(Balance.upgrade_by_id(String(k)).get("cap", 0))
		if cap > 0:
			Run.levels[k] = mini(int(Run.levels[k]), cap)
	# 패시브도 몇 장 쥐여 준다. 빈 칸만 찍으면 새 화면이 제대로 도는지 안 보인다.
	Run.passives.clear()
	if wave >= 4:
		Run.passives.append("keenedge")
	if wave >= 8:
		Run.passives.append("repeater")
	if wave >= 12:
		Run.passives.append("pierce")
	Run.owned_passives.assign(Run.passives)
	# 상점 진열도 채워 둔다 — 화면을 안 타므로(main.go_shop) 여기서 굴려 준다.
	Run.shop_offer.clear()
	Run.roll_shop()


## 원하는 족보가 나오도록 카드를 손으로 깔아 준다.
static func stack(hand: int) -> void:
	var cards: Array[int] = []
	for x in hands()[hand]:
		cards.append(int(x))
	Run.cards = cards
	Run.rerolled = [0, 0, 0, 0, 0]
	Run.paid = [0, 0, 0, 0, 0]
