## 문제 생성기 — 규칙별 숫자 뽑기 + "진짜 아이가 하는 실수"로 오답 만들기.
##
## 오답은 무작위 숫자가 아니다. 각 후보에는 오류 유형 태그가 붙고, 아이가 어떤 오답을
## 골랐는지 저장해서 부모 리포트와 복습 큐에 쓴다.
## 예: 12 - 3 에서 1을 고르면 smaller_from_larger — 개념이 아니라 절차 버그라는 뜻이라
## 앞 십틀에서 하나씩 덜어내는 장면을 다시 보여줘야 한다.
class_name ProblemGen
extends RefCounted

const CHOICE_COUNT := 4

## 곱셈구구에서 아이들이 가장 많이 틀리는 조합. 18탄에서 가중치를 준다.
const HARD_FACTS: Array[Vector2i] = [
	Vector2i(6, 7), Vector2i(7, 6), Vector2i(6, 8), Vector2i(8, 6),
	Vector2i(7, 8), Vector2i(8, 7), Vector2i(7, 9), Vector2i(9, 7),
	Vector2i(8, 9), Vector2i(9, 8), Vector2i(6, 9), Vector2i(9, 6),
]


# --------------------------------------------------------------------------- #
# 공개 API
# --------------------------------------------------------------------------- #

## 한 탄(스테이지)에 쓸 문제 목록. 같은 문제가 중복되지 않도록 한다.
static func make_set(rule: String, params: Dictionary, count: int,
		rng: RandomNumberGenerator, tier: int = 1) -> Array[Problem]:
	var out: Array[Problem] = []
	var used := {}
	var guard := 0
	while out.size() < count and guard < count * 80:
		guard += 1
		var p := make_one(rule, params, rng, tier)
		if p == null or used.has(p.key()):
			continue
		used[p.key()] = true
		out.append(p)
	# 규칙이 만들 수 있는 문제 수가 적으면(예: 10 만들기 = 9쌍) 중복을 허용해 채운다.
	while out.size() < count:
		var p2 := make_one(rule, params, rng, tier)
		if p2 == null:
			break
		out.append(p2)
	return out


## mods 는 적응형 변형이다. 기본값 {} 이면 아무 일도 일어나지 않으므로
## 4인자로 부르던 기존 코드와 테스트가 그대로 통과한다.
static func make_one(rule: String, params: Dictionary, rng: RandomNumberGenerator,
		tier: int = 1, mods: Dictionary = {}) -> Problem:
	var p: Problem = null
	match rule:
		"add_small":
			p = _add_small(params, rng)
		"sub_small":
			p = _sub_small(params, rng)
		"make_ten":
			p = _make_ten(params, rng)
		"add_teen_no_carry":
			p = _add_teen_no_carry(params, rng)
		"sub_teen_no_borrow":
			p = _sub_teen_no_borrow(params, rng)
		"three_term":
			p = _three_term(params, rng)
		"make_ten_then_add":
			p = _make_ten_then_add(params, rng)
		"add_carry_1d":
			p = _add_carry_1d(params, rng)
		"sub_borrow_1d":
			p = _sub_borrow_1d(params, rng)
		"add_to_twenty":
			p = _add_to_twenty(params, rng)
		"sub_to_twenty":
			p = _sub_to_twenty(params, rng)
		"mul_concept":
			p = _mul_concept(params, rng)
		"mul_table":
			p = _mul_table(params, rng)
		"mul_mixed":
			p = _mul_mixed(params, rng)
		"review":
			p = _review(params, rng, tier)
		_:
			push_error("알 수 없는 문제 규칙: %s" % rule)
			return null
	if p == null:
		return null
	if p.tier <= 0:
		p.tier = tier
	# ★ 변형은 recompute() **앞**에 와야 한다. 뒤에 두면 answer 가 바뀐 뒤에
	#   보기가 옛 답 기준으로 이미 만들어져 있다.
	if not mods.is_empty():
		_apply_mods(p, mods, rng)
	if not p.recompute():
		return null
	build_choices(p, rng, int(mods.get("choices", CHOICE_COUNT)), int(mods.get("distractor", 1)))
	return p


## 적응형 변형. 아이 눈에는 난이도가 아니라 "새 모양"으로 읽힌다.
##
## 빈칸(MISSING)은 Problem 이 2항 덧셈만 허용한다 — 그 밖에서는 조용히 건너뛴다.
static func _apply_mods(p: Problem, mods: Dictionary, rng: RandomNumberGenerator) -> void:
	var blank: float = float(mods.get("blank", 0.0))
	if blank > 0.0 and p.form == Problem.Form.RESULT \
			and p.op == Problem.Op.ADD and p.terms.size() == 2 \
			and rng.randf() < blank:
		p.form = Problem.Form.MISSING
		p.blank_index = rng.randi() % 2


# --------------------------------------------------------------------------- #
# 규칙 (탄 번호는 Curriculum 참고)
# --------------------------------------------------------------------------- #

## 1탄(합 5 이하) / 2탄(합 6~9) — 받아올림 없는 한 자리 덧셈.
static func _add_small(params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var max_sum: int = params.get("max_sum", 9)
	var min_sum: int = params.get("min_sum", 2)
	# a 를 먼저 뽑고, b 의 유효 구간이 비지 않도록 a 의 범위를 제한한다.
	var a_hi := mini(max_sum - 1, 9)
	var a := rng.randi_range(1, maxi(1, a_hi))
	var b_lo := maxi(1, min_sum - a)
	var b_hi := mini(9, max_sum - a)
	if b_hi < b_lo:
		# a 가 너무 커서 구간이 비면 a 를 낮춘다.
		a = rng.randi_range(1, maxi(1, max_sum - min_sum + 1))
		b_lo = maxi(1, min_sum - a)
		b_hi = maxi(b_lo, mini(9, max_sum - a))
	var p := Problem.new()
	p.op = Problem.Op.ADD
	p.terms = [a, rng.randi_range(b_lo, b_hi)]
	return p


## 3탄 — 한 자리 뺄셈. 0을 더하고 빼는 경우도 교과 내용이라 섞는다.
static func _sub_small(params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var max_m: int = params.get("max_m", 9)
	var min_m: int = params.get("min_m", 2)
	var zero_forms: bool = params.get("zero_forms", true)
	var p := Problem.new()
	p.op = Problem.Op.SUB
	var roll := rng.randf()
	if zero_forms and roll < 0.15:
		var m := rng.randi_range(1, max_m)
		p.terms = [m, 0]                       # m - 0
	elif zero_forms and roll < 0.30:
		var m2 := rng.randi_range(1, max_m)
		p.terms = [m2, m2]                     # m - m = 0
	else:
		var m3 := rng.randi_range(maxi(2, min_m), max_m)
		p.terms = [m3, rng.randi_range(1, m3 - 1)]
	return p


## 4탄 — 10 모으기와 가르기. 받아올림/받아내림의 유일한 전제조건이라 별도 탄으로 둔다.
## 주의: "a + (10-a) = ?" 형태는 답이 항상 10이라 절대 쓰지 않는다.
static func _make_ten(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var a := rng.randi_range(1, 9)
	var p := Problem.new()
	if rng.randf() < 0.5:
		# 가르기: 10 - a = ?
		p.op = Problem.Op.SUB
		p.terms = [10, a]
	else:
		# 모으기(빈칸): a + □ = 10
		p.op = Problem.Op.ADD
		p.form = Problem.Form.MISSING
		p.terms = [a, 0]
		p.blank_index = 1
		p.total = 10
	return p


## 5탄 — 십몇 + 몇 (받아올림 없음). 자릿값을 처음 보는 탄이라 합은 19를 넘지 않는다.
static func _add_teen_no_carry(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var ones := rng.randi_range(1, 8)
	var a := 10 + ones
	var b := rng.randi_range(1, 9 - ones)
	var p := Problem.new()
	p.op = Problem.Op.ADD
	p.terms = [a, b]
	return p


## 6탄 — 십몇 - 몇 (받아내림 없음). 결과가 10 밑으로 내려가지 않는다.
static func _sub_teen_no_borrow(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var ones := rng.randi_range(1, 9)
	var a := 10 + ones
	var b := rng.randi_range(1, ones)
	var p := Problem.new()
	p.op = Problem.Op.SUB
	p.terms = [a, b]
	return p


## 7탄 — 세 수의 덧셈/뺄셈. 왼쪽부터 차례로 계산하는 절차를 익히는 탄.
static func _three_term(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var p := Problem.new()
	if rng.randf() < 0.5:
		p.op = Problem.Op.ADD
		var a := rng.randi_range(1, 7)
		var b := rng.randi_range(1, maxi(1, 8 - a))
		var c := rng.randi_range(1, maxi(1, 9 - a - b))
		p.terms = [a, b, c]
	else:
		p.op = Problem.Op.SUB
		for _i in 30:
			var b2 := rng.randi_range(1, 3)
			var c2 := rng.randi_range(1, 3)
			var ans := rng.randi_range(0, 6)
			var a2 := ans + b2 + c2
			if a2 <= 9:
				p.terms = [a2, b2, c2]
				break
		if p.terms.size() < 3:
			p.terms = [9, 2, 3]
	return p


## 8탄 — 10을 만들어 더하기. 9탄 받아올림의 정확한 리허설.
static func _make_ten_then_add(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var x := rng.randi_range(1, 9)
	var y := 10 - x
	var z := rng.randi_range(1, 9)
	var p := Problem.new()
	p.op = Problem.Op.ADD
	if rng.randf() < 0.5:
		p.terms = [x, y, z]
		p.make_ten_pair = Vector2i(0, 1)
	else:
		p.terms = [z, x, y]
		p.make_ten_pair = Vector2i(1, 2)
	return p


## 9탄 — 받아올림 있는 (몇)+(몇). 합 11~18.
static func _add_carry_1d(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var a := rng.randi_range(2, 9)
	var b := rng.randi_range(maxi(2, 11 - a), 9)
	var p := Problem.new()
	p.op = Problem.Op.ADD
	p.terms = [a, b]
	return p


## 10탄 — 받아내림 있는 (십몇)-(몇). 초1~2 전체에서 오답률이 가장 높은 지점.
static func _sub_borrow_1d(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var m := rng.randi_range(11, 18)
	var s := rng.randi_range((m % 10) + 1, 9)
	var p := Problem.new()
	p.op = Problem.Op.SUB
	p.terms = [m, s]
	return p


## 11탄 — 20까지 더하기. 10 + 10 = 20 이 이 게임 덧셈의 최대치다.
static func _add_to_twenty(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var total := rng.randi_range(11, 20)
	var lo := maxi(1, total - 10)
	var a := rng.randi_range(lo, mini(10, total - 1))
	var p := Problem.new()
	p.op = Problem.Op.ADD
	p.terms = [a, total - a]
	return p


## 12탄 — 20까지 빼기. 받아내림이 있는 경우를 더 자주 낸다.
static func _sub_to_twenty(_params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var a := rng.randi_range(11, 20)
	var b := 0
	for _i in 40:
		b = rng.randi_range(2, 9)
		if a - b >= 1 and b > a % 10:
			break
	if a - b < 1 or b <= 0:
		b = mini(9, a - 1)
	var p := Problem.new()
	p.op = Problem.Op.SUB
	p.terms = [a, b]
	return p


## 13탄 — 곱셈의 뜻. "a씩 b묶음" 이므로 a=한 묶음의 크기, b=묶음의 수.
static func _mul_concept(params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var max_a: int = params.get("max_a", 5)
	var max_b: int = params.get("max_b", 5)
	var p := Problem.new()
	p.op = Problem.Op.MUL
	p.terms = [rng.randi_range(2, max_a), rng.randi_range(2, max_b)]
	return p


## 14~17탄 — 곱셈구구. 한국 교과서 표기대로 a 가 '단'(한 묶음의 크기)이다.
static func _mul_table(params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var tables: Array = params.get("tables", [2, 5])
	var t: int = int(tables[rng.randi_range(0, tables.size() - 1)])
	# b=1 은 규칙이지 암기 대상이 아니라 5%로만 낸다.
	var b := 1 if rng.randf() < 0.05 else rng.randi_range(2, 9)
	var p := Problem.new()
	p.op = Problem.Op.MUL
	p.terms = [t, b]
	return p


## 18탄 — 1단, 0의 곱, 그리고 난문 가중 혼합.
static func _mul_mixed(params: Dictionary, rng: RandomNumberGenerator) -> Problem:
	var include_zero: bool = params.get("include_zero", true)
	var p := Problem.new()
	p.op = Problem.Op.MUL
	var roll := rng.randf()
	if roll < 0.15:
		p.terms = [1, rng.randi_range(1, 9)]
	elif include_zero and roll < 0.25:
		if rng.randf() < 0.5:
			p.terms = [0, rng.randi_range(1, 9)]
		else:
			p.terms = [rng.randi_range(1, 9), 0]
	elif rng.randf() < 0.4:
		var hf: Vector2i = HARD_FACTS[rng.randi_range(0, HARD_FACTS.size() - 1)]
		p.terms = [hf.x, hf.y]
	else:
		p.terms = [rng.randi_range(2, 9), rng.randi_range(2, 9)]
	return p


## 보너스/복습 — 여러 규칙 중 가중 추출. rules = [[rule, params, weight], ...]
static func _review(params: Dictionary, rng: RandomNumberGenerator, tier: int) -> Problem:
	var rules: Array = params.get("rules", [])
	if rules.is_empty():
		return null
	var total := 0.0
	for r in rules:
		total += float(r[2]) if r.size() > 2 else 1.0
	var pick := rng.randf() * total
	for r in rules:
		pick -= float(r[2]) if r.size() > 2 else 1.0
		if pick <= 0.0:
			return make_one(String(r[0]), r[1], rng, tier)
	var last: Array = rules[rules.size() - 1]
	return make_one(String(last[0]), last[1], rng, tier)


# --------------------------------------------------------------------------- #
# 보기(오답) 만들기
# --------------------------------------------------------------------------- #

## 정답 + 그럴듯한 오답 3개를 만들어 p.choices / p.choice_tags 를 채운다.
## n 은 보기 개수 (미취학 프로필은 2개). d 는 오답 고르는 방식:
##   0 = 정답에서 먼 오답 우선 (쉬움) / 1 = 오류모델 순서(기본) / 2 = 가까운 오답 우선
##
## ★ 이 축이 가장 조용하다. 9탄 8+5 의 오답 후보들은 정답과의 거리가
##   10 / 1 / 1 / 10 / 10 / 2 다. 먼 것만 고르면 평균 거리 10, 가까운 것만 고르면 1.3 —
##   같은 문제, 같은 수 범위인데 난이도가 확 다르고 화면은 하나도 안 바뀐다.
static func build_choices(p: Problem, rng: RandomNumberGenerator,
		n: int = CHOICE_COUNT, distractor: int = 1) -> void:
	n = clampi(n, 2, CHOICE_COUNT)
	var cands := _error_model(p)
	if distractor != 1:
		var ans := p.answer
		cands.sort_custom(func(a, b):
			var da: int = absi(int(a[0]) - ans)
			var db: int = absi(int(b[0]) - ans)
			return da > db if distractor == 0 else da < db)
	var cap := _cap(p)
	var picked: Array[int] = []
	var tags := {}
	var seen := {p.answer: true}

	for pair in cands:
		if picked.size() >= n - 1:
			break
		var v: int = pair[0]
		if v < 0 or v > cap or seen.has(v):
			continue
		seen[v] = true
		tags[v] = String(pair[1])
		picked.append(v)

	# 3개가 안 채워졌을 때만 정답 근처로 보충한다. cap > answer >= 0 이라 항상 채워진다.
	var delta := 1
	var guard := 0
	while picked.size() < n - 1 and guard < 400:
		guard += 1
		for v in [p.answer - delta, p.answer + delta]:
			if picked.size() >= n - 1:
				break
			if v < 0 or v > cap or seen.has(v):
				continue
			seen[v] = true
			tags[v] = "near"
			picked.append(v)
		delta += 1

	picked.append(p.answer)
	tags[p.answer] = "answer"

	# 같은 문제를 다시 풀 때 보기 위치가 바뀌지 않게 문제 키로 시드를 고정한다.
	# 위치를 다시 찾는 게 아니라 계산을 다시 하게 만들기 위함.
	var shuffler := RandomNumberGenerator.new()
	shuffler.seed = hash(p.key())
	_shuffle_seeded(picked, shuffler)

	p.choices = picked
	p.choice_tags = tags


## 보기의 상한. 말이 안 되게 큰 수만 걸러내는 용도이며,
## 정답과 자릿수를 맞추는 데 쓰면 안 된다 — 받아올림을 잊은 오답(7+5 -> 2)은
## 한 자리이고 정답은 두 자리인데, 그 불일치가 바로 그 오답의 진단 가치다.
static func _cap(p: Problem) -> int:
	if p.op == Problem.Op.MUL:
		return 99
	# 덧셈/뺄셈은 20 이내가 최대라 보기도 그 근처로 묶는다.
	return mini(30, maxi(20, p.answer + 12))


static func _shuffle_seeded(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 연산별 "흔한 실수" 후보 목록. [[값, 태그], ...] 를 그럴듯한 순서로 반환한다.
static func _error_model(p: Problem) -> Array:
	if p.form == Problem.Form.MISSING:
		return _errors_missing(p)
	match p.op:
		Problem.Op.ADD:
			return _errors_add(p)
		Problem.Op.SUB:
			return _errors_sub(p)
		Problem.Op.MUL:
			return _errors_mul(p)
	return []


## a + □ = 10 형태.
static func _errors_missing(p: Problem) -> Array:
	var known := p.terms[1 - p.blank_index]
	return [
		[p.answer + 1, "counting_on_high"],
		[p.answer - 1, "counting_on_low"],
		[known, "term_echo"],          # 보이는 수를 그대로 답함
		[p.total, "total_echo"],       # 오른쪽 수를 그대로 답함
		[p.answer + 2, "count_off2"],
		[p.answer - 2, "count_off2"],
	]


static func _errors_add(p: Problem) -> Array:
	var out: Array = []
	if p.is_three_term():
		var ab := p.terms[0] + p.terms[1]
		var bc := p.terms[1] + p.terms[2]
		if p.make_ten_pair.x >= 0:
			# 8탄: 10은 만들었는데 나머지 항을 얹지 않음 / 나머지만 답함
			var extra := p.terms[3 - p.make_ten_pair.x - p.make_ten_pair.y]
			out.append([10, "ten_only"])
			out.append([extra, "leftover_only"])
		out.append([p.answer - 1, "counting_on_low"])
		out.append([p.answer + 1, "counting_on_high"])
		out.append([ab, "dropped_last_term"])
		out.append([bc, "dropped_first_term"])
		out.append([p.answer - 2, "count_off2"])
		return out

	if p.carry:
		# 받아올림을 버린 답이 이 구간 최빈 오답이다. 7+5 -> 2, 15+6 -> 11
		out.append([p.answer - 10, "carry_dropped"])
		out.append([p.answer - 1, "decompose_slip"])
		out.append([p.answer + 1, "counting_on_high"])
		out.append([p.answer + 10, "carry_twice"])
		out.append([absi(p.a - p.b), "sign_confusion"])
		out.append([p.answer - 2, "count_off2"])
		return out

	out.append([p.answer - 1, "counting_on_low"])
	out.append([p.answer + 1, "counting_on_high"])
	if p.a >= 10 or p.b >= 10:
		# 십의 자리를 잊거나 잘못 얹음 (13 + 4 를 3 + 4 로 처리 등)
		out.append([p.answer - 10, "tens_slip_low"])
		out.append([p.answer + 10, "tens_slip_high"])
	out.append([absi(p.a - p.b), "sign_confusion"])
	out.append([p.answer - 2, "count_off2"])
	out.append([p.answer + 2, "count_off2"])
	return out


static func _errors_sub(p: Problem) -> Array:
	var out: Array = []
	if p.is_three_term():
		out.append([p.answer + 1, "count_back_low"])
		out.append([p.answer - 1, "count_back_high"])
		out.append([p.terms[0] - p.terms[1], "dropped_last_term"])
		out.append([p.terms[0] - p.terms[1] + p.terms[2], "added_last_term"])
		out.append([p.answer + 2, "count_off2"])
		return out

	var m := p.a
	var s := p.b
	if p.borrow:
		# Brown & Burton(1978)의 대표 버그: 자리마다 큰 숫자에서 작은 숫자를 뺀다.
		if m < 20:
			out.append([absi((m % 10) - s), "smaller_from_larger"])
			out.append([10 - s, "ten_only"])     # 십몇의 낱개를 잊고 10에서만 뺌
		else:
			out.append([10 + absi((m % 10) - s), "smaller_from_larger"])
			out.append([p.answer + 10, "borrow_forgot"])
		out.append([p.answer - 1, "count_back_high"])
		out.append([p.answer + 1, "count_back_low"])
		out.append([m + s, "sign_confusion"])
		return out

	if p.answer == 0:
		return [[1, "near"], [m, "term_echo_minuend"], [2, "near"]]
	if s == 0:
		return [[m - 1, "counting_on_low"], [m + 1, "counting_on_high"], [0, "zero_echo"]]

	out.append([p.answer + 1, "count_back_low"])
	out.append([p.answer - 1, "count_back_high"])
	out.append([m + s, "sign_confusion"])
	if m >= 10:
		out.append([p.answer + 10, "tens_slip_high"])
		out.append([p.answer - 10, "tens_slip_low"])
	out.append([s, "term_echo_subtrahend"])
	out.append([m, "term_echo_minuend"])
	return out


static func _errors_mul(p: Problem) -> Array:
	var a := p.a
	var b := p.b
	if a == 0 or b == 0:
		var nz := maxi(a, b)
		return [[nz, "zero_as_identity"], [1, "zero_as_one"], [nz + 1, "near"]]
	if a == 1:
		return [[1, "one_rule_overgeneralized"], [b + 1, "near"], [b - 1, "near"],
				[b + 2, "near"]]

	var out: Array = []
	# 아동의 한 자리 곱셈 오답 중 약 3/4이 operand error — 두 피연산자 중 한쪽의
	# '단' 안에 실제로 있는 이웃 곱을 답한다. 그래서 이웃 곱이 오답의 주력이어야 한다.
	if b > 1:
		out.append([p.answer - a, "operand_error_low"])
	out.append([p.answer + a, "operand_error_high"])
	if a > 1:
		out.append([p.answer - b, "operand_other_low"])
	out.append([p.answer + b, "operand_other_high"])
	out.append([a + b, "mul_as_add"])
	if p.answer >= 10 and p.answer % 10 != 0:
		out.append([(p.answer % 10) * 10 + p.answer / 10, "digit_swap"])
	out.append([p.answer + 1, "near"])
	out.append([p.answer - 1, "near"])
	return out
