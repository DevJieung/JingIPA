class_name RpsGen
extends RefCounted

## 가위바위보의 **규칙과 난이도 손잡이**. 단일 진실 소스.
##
## ★ 진짜 가위바위보에서 바꾼 것은 **동시에 내는 것 하나**다.
##   동시에 내면 아무리 잘 봐도 세 번에 두 번은 진다. 그 한 줄이 이 앱이 금지한 것 셋을
##   한꺼번에 건드린다 — **지는 것(규칙 2) · 평가받는 느낌(규칙 8의 F축) ·
##   운을 숙련으로 오독하는 적응형(규칙 9)**. (참참참이 박자를 뺀 것과 같은 자리다.)
##   그래서 여기서는 **친구가 먼저 손을 내고, 아이는 그걸 보고 낸다.**
##
## ★ 그러면 남는 것이 이 놀이의 진짜 알맹이다 — **세 손의 관계**(가위>보>바위>가위)와,
##   커서는 **일부러 지기**(억제 조절). 둘 다 운이 아니라 아는 것이고, 자랄 수 있다.
##
## ★ 목표가 무엇이든 **정답은 언제나 정확히 하나**다 (가위바위보의 성질).
##   그래서 막다른 판이 **구조 자체로** 없다 — 블록 채우기의 역방향 생성과 같은 자리다.
##
## 올리는 축은 셋뿐이고 전부 A/B/C 다. 기다림도 시간 압박도 없다 —
## 친구는 아이가 누를 때까지 영원히 손을 내밀고 서 있는다.
##   e=3   관계 고리가 옅어지기 시작한다        (B)
##   e=6   카드 2장 -> 3장 (미취학만)           (C)
##   e=9   목표가 는다 1 -> 2 (+비겨라)         (C)
##   e=12  한 판에 맞힐 횟수 5 -> 6             (A)
##   e=16  목표가 는다 2 -> 3 (+져라)           (C)
##   e=22  맞힐 횟수 6 -> 7                     (A)

## 손 — 이름 순서 그대로 (가위·바위·보). 카드도 이 순서로 놓인다.
## ★ 번호는 core/look.gd 가 쥐고 있다. 허브 카드 그림과 게임 화면이 **같은 손**을
##   그려야 아이가 글자 없이 "이 카드가 그 놀이"라는 것을 안다.
const SCISSORS := Look.HAND_SCISSORS
const ROCK := Look.HAND_ROCK
const PAPER := Look.HAND_PAPER

## 목표 — 이번 판에 아이가 만들어야 하는 결과
const WIN := 0                  ## 이겨라
const DRAW := 1                 ## 비겨라
const LOSE := 2                 ## 져라

## 한 판에 맞힐 횟수의 한계. 아래로는 **찍기가 통하지 않을 만큼**은 있어야 하고
## (guess_pass 참고), 위로는 한 판이 1분을 넘으면 안 된다 (편입 규칙 5).
const ROUNDS_MIN := 5
const ROUNDS_MAX := 7

## 한 판을 끝내는 데 드는 탭 수의 상한.
## ★ **규칙을 하나도 모르는 아이**가 기준이다: 라운드마다 카드를 하나씩 눌러 보다가
##   맞힌다 -> 맞힐 횟수 x 카드 수. 넘으면 놀이가 아니라 노동이다.
const TAPS_MAX := 21


# --------------------------------------------------------------------------- #
# 규칙 — 게임·검사기·화면이 모두 이 셋만 본다
# --------------------------------------------------------------------------- #

## a 가 **이기는** 손 (가위는 보를, 바위는 가위를, 보는 바위를)
static func beats(a: int) -> int:
	match a:
		SCISSORS: return PAPER
		ROCK: return SCISSORS
		_: return ROCK


## a 를 **이기는** 손
static func beaten_by(a: int) -> int:
	match a:
		SCISSORS: return ROCK
		ROCK: return PAPER
		_: return SCISSORS


## 두 손이 만났을 때: 1 = 내가 이김, 0 = 비김, -1 = 내가 짐
static func outcome(mine: int, other: int) -> int:
	if mine == other:
		return 0
	return 1 if beats(mine) == other else -1


## 친구가 그 손을 냈을 때, 이 목표를 이루려면 아이가 내야 할 손.
## ★ 언제나 정확히 하나다. 이 한 줄이 "막다른 판이 없다"의 전부다.
static func answer(friend: int, goal: int) -> int:
	match goal:
		WIN: return beaten_by(friend)
		LOSE: return beats(friend)
		_: return friend


## 목표가 바라는 결과 (outcome 과 같은 척도). 화면의 목표 팻말이 이걸 그린다.
static func goal_outcome(goal: int) -> int:
	match goal:
		WIN: return 1
		LOSE: return -1
		_: return 0


static func hand_name(h: int) -> String:
	match h:
		SCISSORS: return "가위"
		ROCK: return "바위"
		_: return "보"


static func goal_name(g: int) -> String:
	match g:
		WIN: return "이겨라!"
		LOSE: return "져라!"
		_: return "비겨라!"


# --------------------------------------------------------------------------- #
# 난이도 축
# --------------------------------------------------------------------------- #

static func axes(e: int, t: Dictionary = {}) -> Dictionary:
	var rmin := clampi(int(t.get("rps_rounds_min", ROUNDS_MIN)), ROUNDS_MIN, ROUNDS_MAX)
	var rmax := clampi(int(t.get("rps_rounds_max", ROUNDS_MAX)), rmin, ROUNDS_MAX)
	var cmin := clampi(int(t.get("rps_cards_min", 3)), 2, 3)
	var cards_at := int(t.get("rps_cards_at", 6))
	var gmax := clampi(int(t.get("rps_goals_max", 3)), 1, 3)
	var help0 := clampf(float(t.get("rps_help", 1.0)), 0.0, 1.0)
	var hmin := clampf(float(t.get("rps_help_min", 0.0)), 0.0, help0)
	return {
		# A. 볼 것이 는다 — 한 판에 맞힐 횟수
		"rounds": clampi(rmin + _steps(e, [12, 22]), rmin, rmax),
		# C. 고를 것이 는다 — 카드 수 · 목표 수
		"cards": 3 if (cmin >= 3 or e >= cards_at) else 2,
		# ★ 9 는 눈대중이 아니다. 미취학은 카드가 e=6 에서 늘므로 8 로 두면 새 축 둘이
		#   **두 판 간격**으로 켜진다 (규칙 10: 최소 3방). 9 면 3 · 6 · 9 · 12 로 고르다.
		"goals": clampi(1 + _steps(e, [9, 16]), 1, gmax),
		# B. 잘 안 보인다 — 세 손의 관계 고리(커닝페이퍼)가 옅어진다
		"help": clampf(help0 - (help0 - hmin) * float(maxi(0, e - 3)) / 17.0, hmin, help0),
	}


static func _steps(e: int, at: Array) -> int:
	var n := 0
	for x in at:
		if e >= int(x):
			n += 1
	return n


## 아무렇게나 찍는 아이가 한 판에서 "읽었다"(놓침 <= 1) 로 보일 확률.
##
## ★ 적응형이 이걸 숙련으로 오독하면 규칙 9 위반이다. 그래서 축을 정할 때 이 값을
##   **먼저** 본다. 기준은 **같은 카드를 두 번 안 누르는 아이** — 그쪽이 더 잘 통과한다.
##   그 아이는 라운드마다 틀리는 수가 0..(카드수-1) 중 하나로 고르게 나오므로
##   P(한 판 통틀어 <= 1번 틀림) = (1/카드수)^라운드 x (1 + 라운드) 다.
##   두 판 연속이어야 한 칸 어려워지므로 실제 문턱은 이 값의 제곱이다.
static func guess_pass(cards: int, rounds: int) -> float:
	var c := float(maxi(2, cards))
	return pow(1.0 / c, float(rounds)) * (1.0 + float(rounds))


# --------------------------------------------------------------------------- #
# 한 판 만들기
# --------------------------------------------------------------------------- #

## 이 판의 라운드들. 반환: [{friend, goal, answer, cards}]
##
## ★ 조건 둘 (검사기가 같은 함수를 본다):
##   - **첫 라운드는 언제나 "이겨라"** — 새 목표가 판의 첫 문제로 나오면 아이는
##     그게 뭔지 모르는 채로 시작한다. 익숙한 데서 출발해야 한다.
##   - **같은 정답 · 같은 친구 손이 세 번 연속 나오지 않는다** — "그냥 아까 그거"로
##     읽히는 순간 아이는 관계를 안 보고 손버릇으로 누른다.
static func make_rounds(cards_n: int, goals_n: int, rounds: int,
		rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in rounds:
		var pool: Array = []
		for f in 3:
			for g in clampi(goals_n, 1, 3):
				if i == 0 and g != WIN:
					continue
				var a := answer(f, g)
				if _twice(out, "answer", a) or _twice(out, "friend", f):
					continue
				pool.append({"friend": f, "goal": g, "answer": a})
		if pool.is_empty():
			# 여기 오는 일은 없다 (아래 증명). 그래도 조건을 **스스로 지키는** 것을 넣는다 —
			# 예비값이 제 조건을 어긴 적이 있다 (참참참의 fallback 이 그랬다).
			var f2 := 0
			if not out.is_empty():
				f2 = (int((out[out.size() - 1] as Dictionary)["friend"]) + 1) % 3
			pool.append({"friend": f2, "goal": WIN, "answer": answer(f2, WIN)})
		var pick: Dictionary = pool[rng.randi() % pool.size()]
		pick["cards"] = _cards_for(int(pick["answer"]), cards_n, rng)
		out.append(pick)
	return out


## 이 라운드에 내놓을 카드들. **정답은 반드시 들어간다.**
## 순서는 언제나 가위·바위·보 (자리가 판마다 바뀌면 아이가 자리로 못 외우는 게 아니라
## 매번 세 장을 처음부터 다시 봐야 한다 — 그건 난이도가 아니라 피로다).
static func _cards_for(ans: int, cards_n: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	if cards_n >= 3:
		out.assign([SCISSORS, ROCK, PAPER])
		return out
	var others: Array[int] = []
	for h in 3:
		if h != ans:
			others.append(h)
	var pair: Array[int] = [ans, int(others[rng.randi() % others.size()])]
	pair.sort()
	out.assign(pair)
	return out


## 마지막 둘이 이 값으로 같은가 (세 번 연속을 막는다)
static func _twice(out: Array, key: String, v: int) -> bool:
	var n := out.size()
	if n < 2:
		return false
	return int((out[n - 1] as Dictionary)[key]) == v \
			and int((out[n - 2] as Dictionary)[key]) == v
