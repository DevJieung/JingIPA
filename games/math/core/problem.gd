## 문제 하나.
##
## 초1~2 교육과정을 담으려면 두 항짜리 식만으로는 부족해서 두 가지를 더 지원한다:
##   - 세 항의 덧셈/뺄셈      : 2 + 1 + 5 = ?   /   9 - 2 - 3 = ?      (1-2 4단원)
##   - 빈칸(미지수) 형태      : 4 + □ = 10                              (10 모으기)
##
## 화면에는 항상 숫자와 기호만 나온다(한글 0어절). 초1 아이의 읽기 속도가
## 분당 60어절 수준이라, 문장이 들어가면 그 시간이 전부 수학이 아니라 해독에 쓰인다.
class_name Problem
extends RefCounted

enum Op { ADD, SUB, MUL }
## RESULT: 3 + 2 = ?    (답 = 계산 결과)
## MISSING: 4 + □ = 10  (답 = 빈칸에 들어갈 수)
enum Form { RESULT, MISSING }

## 식에 등장하는 수들. 길이 2 또는 3.
var terms: Array[int] = [0, 0]
var op: Op = Op.ADD
var form: Form = Form.RESULT

## 아이가 맞혀야 하는 수.
var answer: int = 0
## MISSING 형태에서 등호 오른쪽에 이미 적혀 있는 수 (예: 4 + □ = 10 의 10).
var total: int = 0
## MISSING 형태에서 빈칸인 항의 인덱스. RESULT 면 -1.
var blank_index: int = -1

## 4지선다 보기 (섞인 상태, 정답 포함).
var choices: Array[int] = []
## 보기 값 -> 오류 유형 태그. 정답에는 "answer".
## 아이가 어떤 오류로 틀렸는지 부모 리포트에 남기기 위한 것.
var choice_tags: Dictionary = {}

## 블록 시연 연출 분기용 플래그.
var carry := false        # 합산판의 앞 십틀이 차고 뒤 틀로 넘어간다 (받아올림)
var borrow := false       # 뒤 틀만으로 모자라 앞 십틀에서 덜어낸다 (받아내림)
## 8탄 "10을 만들어 더하기"에서 10을 이루는 두 항의 인덱스. 없으면 (-1, -1).
var make_ten_pair := Vector2i(-1, -1)
## 이 문제가 나온 탄 번호 (1~18). 연출 강도와 리포트 분류에 쓴다.
var tier := 1


# --------------------------------------------------------------------------- #
# 편의 접근자
# --------------------------------------------------------------------------- #

var a: int:
	get:
		return terms[0] if terms.size() > 0 else 0

var b: int:
	get:
		return terms[1] if terms.size() > 1 else 0

var c: int:
	get:
		return terms[2] if terms.size() > 2 else 0


func term_count() -> int:
	return terms.size()


func is_three_term() -> bool:
	return terms.size() >= 3


static func op_symbol(o: Op) -> String:
	match o:
		Op.ADD:
			return "+"
		Op.SUB:
			return "-"
		Op.MUL:
			return "x"
	return "?"



## 로그/부모 리포트용 한 줄 표기. 화면에는 이 문자열을 쓰지 않는다
## (화면은 parts() 를 받아 숫자와 벡터 기호로 직접 그린다).
func text() -> String:
	var sep := " %s " % op_symbol(op)
	var pieces := PackedStringArray()
	if form == Form.MISSING:
		for i in terms.size():
			pieces.append(str(answer) if i == blank_index else str(terms[i]))
		return "%s = %d" % [sep.join(pieces), total]
	for t in terms:
		pieces.append(str(t))
	return "%s = %d" % [sep.join(pieces), answer]


## 정답을 채워 넣은 완성식 — 시연이 끝난 뒤 문제 카드에 보여준다.
func solved_text() -> String:
	return text()


# --------------------------------------------------------------------------- #
# 화면 렌더링용 토큰
# --------------------------------------------------------------------------- #

## 문제 카드가 그릴 토큰 목록.
##   {"kind": "num", "value": 7}
##   {"kind": "op",  "op": Op.ADD}
##   {"kind": "eq"}
##   {"kind": "blank"}            <- 아직 모르는 수(물음표 자리)
##   {"kind": "answer", "value": 12}  <- reveal 이 true 면 blank 대신 이게 나온다
func parts(reveal: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if form == Form.MISSING:
		for i in terms.size():
			if i > 0:
				out.append({"kind": "op", "op": op})
			if i == blank_index:
				out.append(_blank_or_answer(reveal))
			else:
				out.append({"kind": "num", "value": terms[i]})
		out.append({"kind": "eq"})
		out.append({"kind": "num", "value": total})
		return out

	for i in terms.size():
		if i > 0:
			out.append({"kind": "op", "op": op})
		out.append({"kind": "num", "value": terms[i]})
	out.append({"kind": "eq"})
	out.append(_blank_or_answer(reveal))
	return out


## i 번째 항을 나타내는 색.
##
## ★문제 카드의 숫자 강조와 블록 무대의 블록이 **반드시 같은 색**이어야 해서
##   판정을 여기 한 곳에 둔다. 예전에는 카드가 항을 전부 주황으로 강조해서,
##   오른쪽 숫자를 강조하는 동안 화면 아래 블록은 파란데 위 숫자만 주황이었다.
##   아이에게는 그 둘이 같은 수라는 게 보이지 않는다.
##
##   왼쪽 = 주황, 오른쪽 = 파랑. 단 뺄셈의 오른쪽은 '없앨 것'이라 빨강이다.
func term_color(i: int) -> Color:
	if op == Op.SUB and i > 0:
		return Palette.BLOCK_REMOVE
	# 10을 만들어 더하기: 짝이 되는 두 항을 같은 주황 계열로 묶어 보인다.
	if make_ten_pair.x >= 0:
		if i == make_ten_pair.x:
			return Palette.BLOCK_A
		if i == make_ten_pair.y:
			return Palette.shade(Palette.BLOCK_A, 0.25)
		return Palette.BLOCK_B
	match i:
		0:
			return Palette.BLOCK_A
		1:
			return Palette.BLOCK_B
		_:
			return Palette.BLOCK_C


## 빈칸(찾아야 할 수)의 색. 보기 버튼·물음표 상자와 같은 초록이다.
func blank_color() -> Color:
	return Palette.CHOICE


func _blank_or_answer(reveal: bool) -> Dictionary:
	if reveal:
		return {"kind": "answer", "value": answer}
	return {"kind": "blank"}


# --------------------------------------------------------------------------- #
# 저장/복원용 키
# --------------------------------------------------------------------------- #

## 통계 저장과 스테이지 내 중복 방지에 쓰는 고유 키.
## 형식: "op,form,blank,total,t0-t1[-t2]"
func key() -> String:
	var ts := PackedStringArray()
	for t in terms:
		ts.append(str(t))
	return "%d,%d,%d,%d,%s" % [int(op), int(form), blank_index, total, "-".join(ts)]


## key() 로 만든 문자열에서 문제를 되살린다. 실패하면 null.
static func from_key(k: String) -> Problem:
	var head := k.split(",")
	if head.size() != 5:
		return null
	var p := Problem.new()
	p.op = clampi(head[0].to_int(), 0, 2) as Op
	p.form = clampi(head[1].to_int(), 0, 1) as Form
	p.blank_index = head[2].to_int()
	p.total = head[3].to_int()
	p.terms = []
	for s in head[4].split("-"):
		if s == "":
			continue
		p.terms.append(s.to_int())
	if p.terms.size() < 2:
		return null
	if not p.recompute():
		return null
	return p


## terms/op/form 으로부터 answer, carry, borrow 를 다시 계산한다.
## 값이 유효하지 않으면(음수 결과 등) false.
func recompute() -> bool:
	if form == Form.MISSING:
		if blank_index < 0 or blank_index >= terms.size():
			return false
		# 현재는 "a + □ = total" 형태만 쓴다.
		if op != Op.ADD or terms.size() != 2:
			return false
		var known := terms[1 - blank_index]
		answer = total - known
		if answer < 0:
			return false
		carry = false
		borrow = false
		return true

	match op:
		Op.ADD:
			answer = 0
			for t in terms:
				answer += t
			carry = _add_has_carry()
			borrow = false
		Op.SUB:
			answer = terms[0]
			for i in range(1, terms.size()):
				answer -= terms[i]
			if answer < 0:
				return false
			borrow = _sub_has_borrow()
			carry = false
		Op.MUL:
			answer = 1
			for t in terms:
				answer *= t
			carry = false
			borrow = false
	return true


func _add_has_carry() -> bool:
	var ones := 0
	for t in terms:
		ones += t % 10
	return ones >= 10


func _sub_has_borrow() -> bool:
	var cur := terms[0]
	for i in range(1, terms.size()):
		if terms[i] % 10 > cur % 10:
			return true
		cur -= terms[i]
	return false


## 블록 시연에서 화면에 동시에 놓일 수 있는 낱개의 최대 개수.
## 무대 크기를 미리 잡는 데 쓴다.
func peak_units() -> int:
	match op:
		Problem.Op.ADD:
			if form == Form.MISSING:
				return maxi(total, 10)
			var s := 0
			for t in terms:
				s += t
			return s
		Problem.Op.SUB:
			# 받아내림이 일어나면 앞 십틀까지 손대므로 낱개가 최대 19개까지 간다.
			var ones := terms[0] % 10
			return (ones + 10) if borrow else maxi(ones, terms[0])
		Problem.Op.MUL:
			return answer
	return answer


func duplicate_problem() -> Problem:
	var p := Problem.new()
	p.terms = terms.duplicate()
	p.op = op
	p.form = form
	p.answer = answer
	p.total = total
	p.blank_index = blank_index
	p.choices = choices.duplicate()
	p.choice_tags = choice_tags.duplicate()
	p.carry = carry
	p.borrow = borrow
	p.make_ten_pair = make_ten_pair
	p.tier = tier
	return p
