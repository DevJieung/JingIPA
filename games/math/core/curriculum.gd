## 진행 데이터 — 18개의 "탄"(스테이지)과 이를 묶은 6개 월드.
##
## ★덧셈과 뺄셈은 전부 20 이내다 (최대 10 + 10 = 20).
## 그래서 블록 무대의 합산판이 20칸 하나로 모든 문제를 표현할 수 있다.
##
## 순서는 2022 개정 교육과정 초1~2 '수와 연산'의 실제 지도 순서를 따른다:
##   합 5 이하 → 합 6~9 → 한 자리 뺄셈 → 10 모으기·가르기
##   → 십몇 ± 몇 (받아올림/내림 없음) → 세 수의 계산 → 10을 만들어 더하기
##   → 받아올림 (몇)+(몇) → 받아내림 (십몇)-(몇)
##   → 20까지 더하기/빼기 → 곱셈의 뜻
##   → 곱셈구구 2·5단 → 3·6단 → 4·8단 → 7·9단 → 1단·0의 곱·총력전
##
## 곱셈구구 순서(2·5 → 3·6 → 4·8 → 7·9 → 1)는 한국 교과서 지도 순서 그대로다.
## 8탄(10을 만들어 더하기)을 건너뛰면 9탄 받아올림에서 실패율이 급증하기 때문에
## 반드시 그 앞에 둔다.
class_name Curriculum
extends RefCounted

## 블록 무대의 표현 방식.
enum Display {
	TEN_FRAME,    # 십틀(가로5 x 세로2)만. 낱개를 직산으로 읽는 구간.
	PLACE_VALUE,  # 자릿값 판: 왼쪽 십 막대 칸 / 오른쪽 낱개 칸.
	ARRAY,        # 곱셈 배열: a씩 b묶음의 직사각형.
}

const NORMAL_COUNT := 5
const BOSS_COUNT := 8

static var _tiers: Array[Dictionary] = []
static var _worlds: Array[Dictionary] = []


# --------------------------------------------------------------------------- #
# 조회
# --------------------------------------------------------------------------- #

static func tiers() -> Array[Dictionary]:
	if _tiers.is_empty():
		_build()
	return _tiers


static func worlds() -> Array[Dictionary]:
	if _worlds.is_empty():
		_build()
	return _worlds


static func tier_count() -> int:
	return tiers().size()


static func tier(index: int) -> Dictionary:
	var t := tiers()
	return t[clampi(index, 0, t.size() - 1)]


static func world_count() -> int:
	return worlds().size()


static func world(index: int) -> Dictionary:
	var w := worlds()
	return w[clampi(index, 0, w.size() - 1)]


## 이 탄이 속한 월드 번호(0-based).
static func world_of_tier(index: int) -> int:
	for w in world_count():
		if index in (world(w)["tiers"] as Array):
			return w
	return 0


static func is_boss(index: int) -> bool:
	return bool(tier(index).get("boss", false))


## 현재 언어로 된 탄 이름 / 목표 / 월드 이름.
static func tier_name(index: int) -> String:
	return Loc.t(String(tier(index).get("key", "t1")))


static func tier_goal(index: int) -> String:
	return Loc.t(String(tier(index).get("key", "t1")) + "g")


static func world_name(w: int) -> String:
	return Loc.t(String(world(w).get("key", "w1")))


static func world_subtitle(w: int) -> String:
	return Loc.t(String(world(w).get("key", "w1")) + "s")


## "3탄" — 아이 화면에 쓰는 짧은 이름.
static func tier_label(index: int) -> String:
	return Loc.f("stage_n", [index + 1])


## "개굴 늪지 · 3탄" — HUD 제목.
static func tier_title(index: int) -> String:
	return "%s %s" % [world_name(world_of_tier(index)), tier_label(index)]


static func question_count(index: int) -> int:
	return int(tier(index).get("count", NORMAL_COUNT))


## 클리어 후 열리는 무한 복습 모드의 규칙. 지금까지 배운 전 범위에서 뽑는다.
static func endless_params(highest_cleared_tier: int) -> Dictionary:
	var rules: Array = []
	for i in mini(highest_cleared_tier + 1, tier_count()):
		var t := tier(i)
		# 개념 도입용 탄(4탄 빈칸 등)도 복습에 포함한다.
		rules.append([t["rule"], t["params"], float(t.get("review_weight", 1.0))])
	if rules.is_empty():
		rules = [["add_small", {"max_sum": 5}, 1.0]]
	return {"rules": rules}


# --------------------------------------------------------------------------- #
# 데이터
# --------------------------------------------------------------------------- #

static func _t(key: String, rule: String, params: Dictionary,
		op: Problem.Op, display: Display, ten_frame: bool, boss: bool = false,
		count: int = -1, review_weight: float = 1.0) -> Dictionary:
	return {
		"key": key,
		"rule": rule,
		"params": params,
		"op": op,
		"display": display,
		"ten_frame": ten_frame,
		"boss": boss,
		"count": count if count > 0 else (BOSS_COUNT if boss else NORMAL_COUNT),
		"review_weight": review_weight,
	}


static func _build() -> void:
	_tiers = [
		# --- 월드 1: 개굴 늪지 ------------------------------------------------ #
		_t("t1", "add_small", {"max_sum": 5, "min_sum": 2},
				Problem.Op.ADD, Display.TEN_FRAME, true, false, 5, 0.5),
		_t("t2", "add_small", {"max_sum": 9, "min_sum": 6},
				Problem.Op.ADD, Display.TEN_FRAME, true),
		_t("t3", "sub_small", {"max_m": 9, "min_m": 2},
				Problem.Op.SUB, Display.TEN_FRAME, true, true),

		# --- 월드 2: 연꽃 호수 ------------------------------------------------ #
		_t("t4", "make_ten", {},
				Problem.Op.ADD, Display.TEN_FRAME, true, false, 6, 1.6),
		_t("t5", "add_teen_no_carry", {},
				Problem.Op.ADD, Display.PLACE_VALUE, true),
		_t("t6", "sub_teen_no_borrow", {},
				Problem.Op.SUB, Display.PLACE_VALUE, true, true),

		# --- 월드 3: 버섯 숲 -------------------------------------------------- #
		_t("t7", "three_term", {},
				Problem.Op.ADD, Display.TEN_FRAME, true),
		_t("t8", "make_ten_then_add", {},
				Problem.Op.ADD, Display.TEN_FRAME, true, false, 6, 1.2),
		_t("t9", "add_carry_1d", {},
				Problem.Op.ADD, Display.PLACE_VALUE, true, true),

		# --- 월드 4: 안개 동굴 ------------------------------------------------ #
		_t("t10", "sub_borrow_1d", {},
				Problem.Op.SUB, Display.PLACE_VALUE, true, false, 6, 1.5),
		_t("t11", "add_to_twenty", {},
				Problem.Op.ADD, Display.PLACE_VALUE, true),
		_t("t12", "sub_to_twenty", {},
				Problem.Op.SUB, Display.PLACE_VALUE, true, true),

		# --- 월드 5: 곱셈 신전 ------------------------------------------------ #
		_t("t13", "mul_concept", {"max_a": 5, "max_b": 5},
				Problem.Op.MUL, Display.ARRAY, false),
		_t("t14", "mul_table", {"tables": [2, 5]},
				Problem.Op.MUL, Display.ARRAY, false),
		_t("t15", "mul_table", {"tables": [3, 6]},
				Problem.Op.MUL, Display.ARRAY, false, true),

		# --- 월드 6: 뱀왕의 성 ------------------------------------------------ #
		_t("t16", "mul_table", {"tables": [4, 8]},
				Problem.Op.MUL, Display.ARRAY, false),
		_t("t17", "mul_table", {"tables": [7, 9]},
				Problem.Op.MUL, Display.ARRAY, false, false, 7, 1.8),
		_t("t18", "mul_mixed", {"include_zero": true},
				Problem.Op.MUL, Display.ARRAY, false, true, 10, 1.2),
	]

	_worlds = [
		{"key": "w1", "tint": 0, "tiers": [0, 1, 2]},
		{"key": "w2", "tint": 1, "tiers": [3, 4, 5]},
		{"key": "w3", "tint": 2, "tiers": [6, 7, 8]},
		{"key": "w4", "tint": 4, "tiers": [9, 10, 11]},
		{"key": "w5", "tint": 6, "tiers": [12, 13, 14]},
		{"key": "w6", "tint": 9, "tiers": [15, 16, 17]},
	]


# --------------------------------------------------------------------------- #
# 적응형 변형 (다축 난이도)
# --------------------------------------------------------------------------- #

## 이 탄에서 오프셋 d 일 때 문제 생성기에 넘길 변형.
##
## ★ 탄의 순서와 규칙은 절대 건드리지 않는다 — 교육과정 순서가 이 게임의 뼈대다.
##   변형은 "같은 규칙 안에서 모양을 바꾸는 것"뿐이다.
##
## | 축          | d=-1        | d=0 (기본) | d=+1     | d=+2               |
## |-------------|-------------|-----------|----------|--------------------|
## | 빈칸        | 없음        | 없음       | 25%      | 45%                |
## | 보기 근접도 | 먼 오답     | 오류모델   | 가까운 쪽 | 가까운 것만        |
## | 복습 간격   | +2문제      | +3문제     | +5문제    | +7문제             |
static func mods_for(tier: int, d: int, choices: int = 4) -> Dictionary:
	d = clampi(d, -1, 2)
	var m := {
		"choices": clampi(choices, 2, 4),
		"distractor": 1,
		"blank": 0.0,
		"review_gap": 3,
	}
	match d:
		-1:
			m["distractor"] = 0
			m["review_gap"] = 2
		1:
			m["distractor"] = 2
			m["blank"] = 0.25
			m["review_gap"] = 5
		2:
			m["distractor"] = 2
			m["blank"] = 0.45
			m["review_gap"] = 7
	return m
