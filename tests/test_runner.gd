## 헤드리스 자동 검증.
##
## 실행:
##   ~/.local/bin/godot --headless --path . res://tests/test_runner.tscn
##
## 검사 항목:
##   1. 18개 탄 전부에서 문제를 대량 생성해 정답/보기/플래그가 맞는지
##   2. 문제 키 왕복 (저장 -> 복원)
##   3. 블록 무대가 모든 탄에서 배치 오류 없이 시연을 끝내는지
##   4. 전투 화면을 실제로 띄워 한 탄을 전부 자동으로 풀어보기
extends Node

const PER_TIER := 400

## 화면별로 "화면 밖으로 나가면 안 되는" 버튼 필드들.
const SCREEN_BUTTONS := {
	"res://games/math/ui/title.tscn": ["_start", "_map", "_endless", "_skip", "_lang",
			"_gear", "_sound"],
	"res://games/math/ui/map.tscn": ["_prev", "_next", "_back", "_endless"],
	"res://games/math/ui/parent.tscn": ["_back"],
}

var _fail := 0
var _checks := 0


func _ready() -> void:
	print("=== 개구리 용사 자동 검증 ===")
	await get_tree().process_frame
	_test_all_scripts_load()
	_test_generator()
	_test_key_roundtrip()
	_test_choice_quality()
	await _test_block_stage()
	await _test_missing_stage()
	await _test_sub_removal_order()
	await _test_battle_playthrough()
	await _test_progress_chips()
	await _test_screens()
	await _test_layout()
	await _test_op_alignment()
	_test_colors()
	_test_localization()
	_test_export_settings()
	print("\n--- 결과: 검사 %d개 / 실패 %d개 ---" % [_checks, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fail += 1
		printerr("  FAIL: ", msg)


# --------------------------------------------------------------------------- #

func _expected(p: Problem) -> int:
	if p.form == Problem.Form.MISSING:
		return p.total - p.terms[1 - p.blank_index]
	match p.op:
		Problem.Op.ADD:
			var s := 0
			for t in p.terms:
				s += t
			return s
		Problem.Op.SUB:
			var v: int = p.terms[0]
			for i in range(1, p.terms.size()):
				v -= p.terms[i]
			return v
		Problem.Op.MUL:
			var m := 1
			for t in p.terms:
				m *= t
			return m
	return -999


func _test_generator() -> void:
	print("\n[1] 문제 생성기 — 탄별 %d문제" % PER_TIER)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260809
	for ti in Curriculum.tier_count():
		var td := Curriculum.tier(ti)
		var rule := String(td["rule"])
		var params: Dictionary = td["params"]
		var made := 0
		var min_ans := 9999
		var max_ans := -9999
		for i in PER_TIER:
			var p := ProblemGen.make_one(rule, params, rng, ti + 1)
			if p == null:
				_ok(false, "%d탄(%s): 생성 실패" % [ti + 1, rule])
				continue
			made += 1
			min_ans = mini(min_ans, p.answer)
			max_ans = maxi(max_ans, p.answer)
			_ok(p.answer == _expected(p),
					"%d탄 %s: answer=%d, 계산=%d" % [ti + 1, p.text(), p.answer, _expected(p)])
			_ok(p.answer >= 0, "%d탄 %s: 음수 정답" % [ti + 1, p.text()])
			if p.op != Problem.Op.MUL:
				_ok(p.answer <= 20, "%d탄 %s: 덧셈/뺄셈 결과가 20 초과" % [ti + 1, p.text()])
				for t2 in p.terms:
					_ok(t2 <= 20, "%d탄 %s: 항이 20 초과" % [ti + 1, p.text()])
			_ok(p.terms.size() >= 2, "%d탄: 항이 부족" % (ti + 1))
			# 블록 무대가 실제로 그릴 수 있는 크기인지. 넘으면 격자에 다 안 놓여
			# "숫자는 15인데 블록은 10개" 가 된다.
			if int(td["display"]) != Curriculum.Display.ARRAY:
				var cap := BlockStage.FRAME_CAP if p.terms.size() >= 3 \
						else BlockStage.GROUP_CAP
				for t4 in p.terms:
					_ok(t4 <= cap, "%d탄 %s: 항 %d 이 항 격자(%d칸)를 넘음"
							% [ti + 1, p.text(), t4, cap])
				_ok(p.total <= BlockStage.MAT_CAP and p.answer <= BlockStage.MAT_CAP,
						"%d탄 %s: 결과가 합산판(%d칸)을 넘음"
						% [ti + 1, p.text(), BlockStage.MAT_CAP])
			for t in p.terms:
				_ok(t >= 0, "%d탄 %s: 음수 항" % [ti + 1, p.text()])
			_ok(p.choices.size() == ProblemGen.CHOICE_COUNT,
					"%d탄 %s: 보기 %d개" % [ti + 1, p.text(), p.choices.size()])
			_ok(p.choices.has(p.answer), "%d탄 %s: 보기에 정답 없음" % [ti + 1, p.text()])
			var uniq := {}
			for c in p.choices:
				_ok(not uniq.has(c), "%d탄 %s: 보기 중복 %d" % [ti + 1, p.text(), c])
				_ok(c >= 0, "%d탄 %s: 음수 보기 %d" % [ti + 1, p.text(), c])
				uniq[c] = true
			_ok(p.choice_tags.has(p.answer), "%d탄 %s: 정답 태그 없음" % [ti + 1, p.text()])
		print("  %2d탄 %-14s %-24s 생성 %d, 정답 범위 %d~%d"
				% [ti + 1, Curriculum.tier_name(ti), rule, made, min_ans, max_ans])
	_check_tier_specifics(rng)


## 탄별로 "반드시 그래야 하는" 조건 (교육과정 순서를 코드가 지키는지).
func _check_tier_specifics(rng: RandomNumberGenerator) -> void:
	print("  탄별 조건 검사")
	for i in 300:
		var p1 := ProblemGen.make_one("add_small", {"max_sum": 5, "min_sum": 2}, rng, 1)
		_ok(p1.answer <= 5 and p1.answer >= 2, "1탄: 합이 2~5 밖 (%s)" % p1.text())

		var p2 := ProblemGen.make_one("add_small", {"max_sum": 9, "min_sum": 6}, rng, 2)
		_ok(p2.answer >= 6 and p2.answer <= 9, "2탄: 합이 6~9 밖 (%s)" % p2.text())

		var p3 := ProblemGen.make_one("sub_small", {"max_m": 9, "min_m": 2}, rng, 3)
		_ok(p3.terms[0] <= 9 and p3.answer >= 0, "3탄: 범위 밖 (%s)" % p3.text())

		var p5 := ProblemGen.make_one("add_teen_no_carry", {}, rng, 5)
		_ok(not p5.carry, "5탄: 받아올림이 생김 (%s)" % p5.text())
		_ok(p5.answer <= 19 and p5.terms[0] >= 10, "5탄: 십몇+몇 범위 밖 (%s)" % p5.text())

		var p6 := ProblemGen.make_one("sub_teen_no_borrow", {}, rng, 6)
		_ok(not p6.borrow, "6탄: 받아내림이 생김 (%s)" % p6.text())
		_ok(p6.answer >= 10 and p6.terms[0] <= 19, "6탄: 십몇-몇 범위 밖 (%s)" % p6.text())

		var p7 := ProblemGen.make_one("three_term", {}, rng, 7)
		_ok(p7.terms.size() == 3, "7탄: 항이 3개가 아님 (%s)" % p7.text())
		_ok(p7.answer >= 0 and p7.answer <= 9, "7탄: 결과가 0~9 밖 (%s)" % p7.text())

		var p8 := ProblemGen.make_one("make_ten_then_add", {}, rng, 8)
		_ok(p8.terms.size() == 3, "8탄: 항이 3개가 아님")
		var pair := p8.make_ten_pair
		_ok(p8.terms[pair.x] + p8.terms[pair.y] == 10,
				"8탄: 짝의 합이 10이 아님 (%s)" % p8.text())
		_ok(p8.answer >= 11 and p8.answer <= 19, "8탄: 결과가 11~19 밖 (%s)" % p8.text())

		var p9 := ProblemGen.make_one("add_carry_1d", {}, rng, 9)
		_ok(p9.carry, "9탄: 받아올림이 없음 (%s)" % p9.text())
		_ok(p9.answer >= 11 and p9.answer <= 18, "9탄: 합이 11~18 밖 (%s)" % p9.text())

		var p10 := ProblemGen.make_one("sub_borrow_1d", {}, rng, 10)
		_ok(p10.borrow, "10탄: 받아내림이 없음 (%s)" % p10.text())
		_ok(p10.terms[1] > p10.terms[0] % 10, "10탄: 받아내림 조건 불만족 (%s)" % p10.text())
		_ok(p10.answer >= 1 and p10.answer <= 9, "10탄: 결과가 1~9 밖 (%s)" % p10.text())

		var p11 := ProblemGen.make_one("add_to_twenty", {}, rng, 11)
		_ok(p11.answer >= 11 and p11.answer <= 20, "11탄: 합이 11~20 밖 (%s)" % p11.text())
		_ok(p11.terms[0] <= 10 and p11.terms[1] <= 10, "11탄: 항이 10 초과 (%s)" % p11.text())

		var p12 := ProblemGen.make_one("sub_to_twenty", {}, rng, 12)
		_ok(p12.terms[0] <= 20, "12탄: 피감수가 20 초과 (%s)" % p12.text())
		_ok(p12.answer >= 1, "12탄: 결과가 1 미만 (%s)" % p12.text())

		var p13 := ProblemGen.make_one("mul_concept", {"max_a": 5, "max_b": 5}, rng, 13)
		_ok(p13.answer <= 25, "13탄: 곱이 25 초과 (%s)" % p13.text())

		var p14 := ProblemGen.make_one("mul_table", {"tables": [2, 5]}, rng, 14)
		_ok(p14.terms[0] == 2 or p14.terms[0] == 5,
				"14탄: 단이 2/5가 아님 (%s) — 한국 교과서 표기는 a=한 묶음의 크기" % p14.text())

	# 4탄은 두 형태가 모두 나와야 한다.
	var saw_missing := false
	var saw_sub := false
	for i in 200:
		var p := ProblemGen.make_one("make_ten", {}, rng, 4)
		if p.form == Problem.Form.MISSING:
			saw_missing = true
			_ok(p.total == 10, "4탄: 빈칸 형태의 합이 10이 아님")
			_ok(p.answer + p.terms[1 - p.blank_index] == 10, "4탄: 보수 관계 깨짐")
		else:
			saw_sub = true
			_ok(p.terms[0] == 10, "4탄: 가르기 형태가 10에서 시작하지 않음")
	_ok(saw_missing, "4탄: 빈칸(모으기) 형태가 한 번도 안 나옴")
	_ok(saw_sub, "4탄: 가르기 형태가 한 번도 안 나옴")


func _test_key_roundtrip() -> void:
	print("\n[2] 문제 키 왕복")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for ti in Curriculum.tier_count():
		var td := Curriculum.tier(ti)
		for i in 60:
			var p := ProblemGen.make_one(String(td["rule"]), td["params"], rng, ti + 1)
			if p == null:
				continue
			var back := Problem.from_key(p.key())
			_ok(back != null, "키 복원 실패: %s" % p.key())
			if back == null:
				continue
			_ok(back.answer == p.answer, "키 복원 후 정답 다름: %s" % p.key())
			_ok(back.terms == p.terms, "키 복원 후 항 다름: %s" % p.key())
			_ok(back.op == p.op and back.form == p.form, "키 복원 후 형태 다름")
	print("  ok")


## 오답이 '진짜 아이가 하는 실수'를 담고 있는지 대표 사례로 확인한다.
func _test_choice_quality() -> void:
	print("\n[3] 오답 설계")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	# 7 + 5 = 12 -> 받아올림을 버린 2 가 반드시 보기에 있어야 한다.
	var p := Problem.new()
	p.op = Problem.Op.ADD
	p.terms = [7, 5]
	p.recompute()
	ProblemGen.build_choices(p, rng)
	_ok(p.choices.has(2), "7+5: 받아올림 누락 오답(2)이 보기에 없음 -> %s" % str(p.choices))
	_ok(String(p.choice_tags.get(2, "")) == "carry_dropped", "7+5: 2의 태그가 틀림")

	# 12 - 3 = 9 -> 자리마다 큰 수에서 작은 수를 뺀 1 이 있어야 한다.
	var q := Problem.new()
	q.op = Problem.Op.SUB
	q.terms = [12, 3]
	q.recompute()
	ProblemGen.build_choices(q, rng)
	_ok(q.borrow, "12-3: borrow 플래그가 꺼짐")
	_ok(q.choices.has(1), "12-3: smaller_from_larger 오답(1)이 없음 -> %s" % str(q.choices))
	_ok(String(q.choice_tags.get(1, "")) == "smaller_from_larger", "12-3: 1의 태그가 틀림")

	# 7 x 8 = 56 -> 같은 단 이웃(49, 63)이 있어야 한다.
	var m := Problem.new()
	m.op = Problem.Op.MUL
	m.terms = [7, 8]
	m.recompute()
	ProblemGen.build_choices(m, rng)
	_ok(m.choices.has(49) or m.choices.has(63),
			"7x8: 같은 단 이웃 오답이 없음 -> %s" % str(m.choices))

	# 같은 문제는 항상 같은 자리에 정답이 오도록 (다시 풀 때 위치가 바뀌면 안 된다)
	var a1 := Problem.new()
	a1.op = Problem.Op.ADD
	a1.terms = [3, 4]
	a1.recompute()
	ProblemGen.build_choices(a1, rng)
	var a2 := Problem.new()
	a2.op = Problem.Op.ADD
	a2.terms = [3, 4]
	a2.recompute()
	ProblemGen.build_choices(a2, rng)
	_ok(a1.choices == a2.choices, "같은 문제인데 보기 배치가 달라짐")
	print("  ok")


# --------------------------------------------------------------------------- #

func _test_block_stage() -> void:
	print("\n[4] 블록 무대 — 모든 탄 시연 완주")
	# 기준 화면(가로 태블릿 1280x800)에서 배틀이 실제로 무대에 주는 크기.
	# 세로(폰)에서는 약 748x334 로 거의 같아서, 여기서 도는 시연은 양쪽 다 돈다.
	# (자리 계산 자체는 [7]/[8] 이 두 배치 모두에서 따로 확인한다.)
	const STAGE_SIZE := Vector2(758, 328)
	var host := Control.new()
	host.size = STAGE_SIZE
	add_child(host)
	var stage := BlockStage.new()
	stage.size = STAGE_SIZE
	host.add_child(stage)

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var old_fast := MathGame.fast_animation
	MathGame.fast_animation = true

	# 10칸이 찰 때 묶고(금색 테두리 + "10" 배지), 뺄 때 다시 푸는 장면은 **없어야** 한다.
	# 설명은 옳았지만 한 문제마다 2초 가까이 잡아먹어서 걷어냈다. 다시 들어오면 여기서 잡힌다.
	var segs: Array[String] = []
	stage.segment_started.connect(func(n: String): segs.append(n))

	for ti in Curriculum.tier_count():
		var td := Curriculum.tier(ti)
		for i in 3:
			var p := ProblemGen.make_one(String(td["rule"]), td["params"], rng, ti + 1)
			if p == null:
				continue
			stage.setup(p, int(td["display"]), bool(td["ten_frame"]))
			stage.set_flash_mode(true)
			# GDScript 람다는 지역 변수를 값으로 캡처한다. 배열로 감싸야 밖에서 보인다.
			var done := [false]
			stage.demo_finished.connect(func(): done[0] = true, CONNECT_ONE_SHOT)
			stage.play_demo(true)
			var frames := 0
			while not done[0] and frames < 4000:
				await get_tree().process_frame
				frames += 1
			_ok(done[0], "%d탄 %s: 시연이 끝나지 않음" % [ti + 1, p.text()])
			_ok(frames < 4000, "%d탄 %s: 시연이 너무 김 (%d프레임)" % [ti + 1, p.text(), frames])
		print("  %2d탄 ok" % (ti + 1))

	# 건너뛰기가 동작하는지
	var p2 := ProblemGen.make_one("sub_to_twenty", {}, rng, 12)
	stage.setup(p2, Curriculum.Display.PLACE_VALUE, false)
	var done2 := [false]
	stage.demo_finished.connect(func(): done2[0] = true, CONNECT_ONE_SHOT)
	stage.play_demo(true)
	await get_tree().process_frame
	stage.skip()
	var f2 := 0
	while not done2[0] and f2 < 4000:
		await get_tree().process_frame
		f2 += 1
	_ok(done2[0], "건너뛰기 후 시연이 끝나지 않음")

	_ok(not segs.has("bundle"), "10칸 묶기 장면이 되살아남 (시연이 느려진다)")
	_ok(not segs.has("borrow"), "10 풀기 장면이 되살아남 (시연이 느려진다)")

	MathGame.fast_animation = old_fast
	host.queue_free()
	print("  ok — 장면 %d개, 묶기/풀기 없음" % segs.size())


## 빈칸 문제(a + □ = b) — 격자를 셋 다 깔고, 답을 채울 때 □ 와 합산판이 같이 늘어나는지.
##
## 이게 깨지면 화면이 식과 다른 그림이 된다: 식에는 항이 둘인데 격자는 하나이거나,
## □ 에 블록이 쌓이는데 오른쪽(b)은 가만히 있어서 둘의 대응이 안 보인다.
func _test_missing_stage() -> void:
	print("\n[4b] 빈칸 문제 — 격자 셋 + 동시 증가")
	const STAGE_SIZE := Vector2(758, 328)
	var host := Control.new()
	host.size = STAGE_SIZE
	add_child(host)
	var stage := BlockStage.new()
	stage.size = STAGE_SIZE
	host.add_child(stage)
	var old_fast := MathGame.fast_animation
	MathGame.fast_animation = true

	for known in [1, 4, 9]:
		var p := Problem.new()
		p.op = Problem.Op.ADD
		p.form = Problem.Form.MISSING
		p.terms = [known, 0]
		p.blank_index = 1
		p.total = 10
		_ok(p.recompute(), "%d + □ = 10: recompute 실패" % known)
		ProblemGen.build_choices(p, MathGame.rng)
		var tag := "%d + □ = 10" % known

		stage.setup(p, Curriculum.Display.TEN_FRAME, true)
		await get_tree().process_frame
		var groups: Array = stage.get("_stage_groups")
		_ok(groups.size() == 2, "%s: 격자가 2개가 아님 (%d)" % [tag, groups.size()])
		if groups.size() < 2:
			continue
		var gk: Dictionary = groups[0]
		var gb: Dictionary = groups[1]
		_ok(not bool(gk["blank"]) and bool(gb["blank"]), "%s: □ 격자 표시가 틀림" % tag)
		_ok(gb["color"] == p.blank_color(), "%s: □ 격자가 정답색(초록)이 아님" % tag)
		# 초록은 화면에서 뜻이 하나여야 한다 — "내가 찾아야 할 것".
		# 빈칸 문제는 □ 격자가 답 자리이므로 합산판은 초록이 아니다.
		_ok(not stage.call("answer_on_mat"), "%s: 합산판까지 초록이면 초록이 두 뜻이 됨" % tag)
		_ok(int(gb["value"]) == p.answer, "%s: □ 격자 값이 답이 아님" % tag)
		# 답을 고르기 전 — 아는 수는 놓여 있고 □ 는 비어 있으며 숫자도 안 나온다.
		_ok((gk["ones_nodes"] as Array).size() == known,
				"%s: 아는 수 격자에 %d개가 안 놓임" % [tag, known])
		_ok((gb["ones_nodes"] as Array).is_empty(), "%s: 답 전에 □ 격자에 블록이 있음" % tag)
		_ok(not bool(gb["shown"]), "%s: 답 전에 □ 숫자가 보임" % tag)

		var done := [false]
		stage.demo_finished.connect(func(): done[0] = true, CONNECT_ONE_SHOT)
		stage.play_demo(true)
		var frames := 0
		while not done[0] and frames < 4000:
			await get_tree().process_frame
			frames += 1
		_ok(done[0], "%s: 시연이 끝나지 않음" % tag)

		# 시연 뒤 — □ 격자에는 답만큼, 합산판에는 총합만큼 (하나 넣을 때마다 하나 늘었다).
		var gb2: Dictionary = (stage.get("_stage_groups") as Array)[1]
		var filled: int = (gb2["ones_nodes"] as Array).size()
		_ok(filled == p.answer, "%s: □ 격자에 %d개가 아니라 %d개" % [tag, p.answer, filled])
		var mat: Array = stage.get("_ones")
		_ok(mat.size() == p.total,
				"%s: 합산판이 %d칸이 아니라 %d칸" % [tag, p.total, mat.size()])

	# 반대쪽: `a + b = ?` 는 답이 합산판에 나타나므로 판이 초록이어야 한다.
	# ("정답 격자가 하얀 탄이 있다" 는 지적이 여기였다 — 빈칸 탄만 초록이었다.)
	for pair in [[3, 2], [12, 3], [10, 10]]:
		var r := Problem.new()
		r.op = Problem.Op.ADD if int(pair[0]) < int(pair[1]) or pair[0] == 10 else Problem.Op.SUB
		r.terms = [int(pair[0]), int(pair[1])]
		r.recompute()
		stage.setup(r, Curriculum.Display.TEN_FRAME, true)
		await get_tree().process_frame
		_ok(stage.call("answer_on_mat"),
				"%s: 답이 합산판에 나오는데 판이 초록이 아님" % r.text())
		for g in (stage.get("_stage_groups") as Array):
			_ok(not bool(g["blank"]), "%s: 일반 문제에 □ 격자가 생김" % r.text())

	MathGame.fast_animation = old_fast
	host.queue_free()
	print("  ok")


## 뺄셈 — 빨간 블록과 판이 **뒤에서부터** 없어지는지.
##
## 앞에서부터 빼면 남은 빨간 블록 사이에 구멍이 생겨 "몇 개 남았지?" 를 세기 어렵고,
## 판은 마지막 칸부터 줄어드는데 격자만 앞에서부터 줄어 두 방향이 어긋난다.
##
## 검사 방법: 없애기 장면이 시작할 때 블록 목록을 찍어 두고, 매 프레임 살아있는지 본다.
## 뒤에서부터 없앤다면 살아있는 것은 **항상 앞쪽 연속 구간**이어야 한다
## (죽은 블록 뒤에 살아있는 블록이 있으면 앞에서부터 없앤 것이다).
func _test_sub_removal_order() -> void:
	print("\n[4c] 뺄셈 — 뒤에서부터 없애기")
	const STAGE_SIZE := Vector2(758, 328)
	var host := Control.new()
	host.size = STAGE_SIZE
	add_child(host)
	var stage := BlockStage.new()
	stage.size = STAGE_SIZE
	host.add_child(stage)
	var old_fast := MathGame.fast_animation
	MathGame.fast_animation = true

	# 람다는 지역 변수를 값으로 캡처하므로 배열에 담아 참조로 넘긴다.
	var snap := [[], []]      # [빨간 격자, 합산판]
	stage.segment_started.connect(func(n: String):
		if n.begins_with("smash_"):
			var groups: Array = stage.get("_stage_groups")
			snap[0] = (groups[1]["ones_nodes"] as Array).duplicate()
			snap[1] = (stage.get("_ones") as Array).duplicate())

	for spec in [[12, 3], [9, 4], [17, 8]]:
		var p := Problem.new()
		p.op = Problem.Op.SUB
		p.terms = [int(spec[0]), int(spec[1])]
		p.recompute()
		ProblemGen.build_choices(p, MathGame.rng)
		var tag := "%d - %d" % [p.a, p.b]

		snap[0] = []
		snap[1] = []
		stage.setup(p, Curriculum.Display.TEN_FRAME, true)
		var done := [false]
		stage.demo_finished.connect(func(): done[0] = true, CONNECT_ONE_SHOT)
		stage.play_demo(true)

		var bad := ""
		var samples := 0
		var frames := 0
		while not done[0] and frames < 4000:
			await get_tree().process_frame
			frames += 1
			for si in 2:
				var arr: Array = snap[si]
				if arr.is_empty():
					continue
				samples += 1
				var dead_seen := false
				for n in arr:
					if not is_instance_valid(n):
						dead_seen = true
					elif dead_seen:
						bad = "빨간 격자" if si == 0 else "합산판"
		_ok(done[0], "%s: 시연이 끝나지 않음" % tag)
		_ok(samples > 0, "%s: 없애기 장면을 한 번도 못 봄 (검사가 무의미)" % tag)
		_ok(bad == "", "%s: 뒤에서부터가 아니라 앞에서부터 없어짐 (%s)" % [tag, bad])
		# 다 빼고 나면 빨간 블록은 하나도 남지 않고 판에는 답만큼 남는다.
		_ok((stage.get("_ones") as Array).size() == p.answer,
				"%s: 판에 %d개가 아니라 %d개 남음"
				% [tag, p.answer, (stage.get("_ones") as Array).size()])

	MathGame.fast_animation = old_fast
	host.queue_free()
	print("  ok")


func _test_battle_playthrough() -> void:
	print("\n[5] 전투 화면 — 한 탄 자동 플레이")
	var old_fast := MathGame.fast_animation
	MathGame.fast_animation = true
	Router.pending_tier = 8      # 9탄: 받아올림 (십 막대가 만들어지는 탄)
	Router.pending_endless = false

	var packed: PackedScene = load("res://games/math/game/battle.tscn")
	_ok(packed != null, "battle.tscn 로드 실패")
	if packed == null:
		return
	var battle := packed.instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame

	var answered := 0
	var frames := 0
	var saw_errorless := [false]
	var saw_ease := [false]
	while frames < 20000:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(battle):
			break
		if battle.get("_finished"):
			break
		var busy: bool = battle.get("_busy")
		var p: Problem = battle.get("_problem")
		if busy or p == null:
			continue
		var pad = battle.get("_pad")
		if pad == null:
			continue
		# 첫 문제는 일부러 세 번 틀려서 오답 사다리 전체(하트 차감 -> 완전 시연 ->
		# 정답 반짝임 -> 눌러보기)를 끝까지 밟아 본다.
		var pick := p.answer
		if int(battle.get("_index")) == 0 \
				and int(battle.get("_attempts")) < 3 \
				and not bool(battle.get("_errorless")):
			for c in p.choices:
				if c != p.answer:
					pick = c
					break
		else:
			if bool(battle.get("_errorless")):
				saw_errorless[0] = true
		if int(battle.get("_ease_remaining")) > 0:
			saw_ease[0] = true
		battle.call("_on_answered", pick)
		answered += 1
		await get_tree().process_frame

	_ok(is_instance_valid(battle) and battle.get("_finished"),
			"전투가 끝나지 않음 (%d프레임, %d번 응답)" % [frames, answered])
	if is_instance_valid(battle):
		_ok(int(battle.get("_index")) >= int(battle.get("_total")),
				"모든 문제를 풀지 못함")
		_ok(int(battle.get("_wrong_total")) >= 3, "오답 3회가 기록되지 않음")
		_ok(saw_errorless[0], "3차 오답 뒤 errorless completion 단계에 들어가지 않음")
		# _ease_remaining 은 3문항이 지나면 0으로 돌아오므로 '켜진 적이 있는지' 로 본다.
		_ok(saw_ease[0], "3차 오답 뒤 난이도 완화가 한 번도 켜지지 않음")
		battle.queue_free()
	MathGame.fast_animation = old_fast
	print("  응답 %d회 / %d프레임" % [answered, frames])


func _test_progress_chips() -> void:
	print("\n[5c] 진행 칩 — 마지막 칸까지 차는가")
	var total := 5
	var hud := Hud.new()
	add_child(hud)
	await get_tree().process_frame
	hud.set_progress(0, total)
	await get_tree().process_frame
	for done in range(1, total + 1):
		# 배틀 화면과 같은 순서·같은 프레임.
		hud.set_progress(done, total)
		hud.pulse_progress()
		var frames := 0
		while not hud.progress_settled() and frames < 2000:
			await get_tree().process_frame
			frames += 1
		var fill: Array = hud.get("_pip_fill")
		_ok(fill.size() == total, "칩 배열이 %d개가 아님" % total)
		if fill.size() != total:
			break
		_ok(absf(float(fill[done - 1]) - 1.0) <= 0.01,
				"%d/%d: %d번째 칩이 %.2f 만 참 — 강조가 차오름을 죽였다"
				% [done, total, done, float(fill[done - 1])])
		for i in range(done, total):
			_ok(float(fill[i]) <= 0.01,
					"%d/%d: 아직 안 푼 %d번째 칩이 찼음" % [done, total, i + 1])
	hud.queue_free()
	await get_tree().process_frame
	print("  칩 %d개 전부 순서대로 채워짐" % total)


## 나머지 화면들이 열리고 닫히는지 (그리기 포함).
func _test_screens() -> void:
	print("\n[6] 화면 스모크 테스트")
	# 진행이 있는 상태와 없는 상태 양쪽에서, 가로와 세로 양쪽 크기로 열어 본다.
	MathGame.stars = {}
	for pass_i in 2:
		if pass_i == 1:
			MathGame.stars = {"0": 3, "1": 2, "2": 1}
		for vs in [Vector2(1280, 800), Vector2(720, 1280)]:
			var mode := "가로" if Layout.is_wide(vs) else "세로"
			for path in [Router.TITLE, Router.TIERS, Router.PARENT]:
				var packed: PackedScene = load(path)
				_ok(packed != null, "%s 로드 실패" % path)
				if packed == null:
					continue
				var inst := packed.instantiate()
				add_child(inst)
				await get_tree().process_frame
				if inst is Control:
					(inst as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
					(inst as Control).size = vs
					if inst.has_method("_layout"):
						inst.call("_layout")
					(inst as Control).queue_redraw()
				await get_tree().process_frame
				await get_tree().process_frame
				_ok(is_instance_valid(inst), "%s (%s) 인스턴스가 죽음" % [path, mode])
				if is_instance_valid(inst) and inst is Control:
					_check_on_screen(inst as Control, vs, mode, SCREEN_BUTTONS.get(path, []))
				if path == Router.TITLE and is_instance_valid(inst):
					await _check_title(inst as Control, vs, mode)
				inst.queue_free()
				await get_tree().process_frame
		print("  진행 %s 상태 ok" % ("있음" if pass_i == 1 else "없음"))
	MathGame.stars = {}


## 버튼이 화면 밖으로 나가지 않는지.
##
## ★ BigButton 은 custom_minimum_size(120x96) 아래로 줄지 않는다.
##   `size = Vector2(88, 88)` 을 대입해도 실제로는 120x96 이 되므로,
##   오른쪽/아래에 붙이는 버튼을 "화면폭 - 108" 같은 숫자로 놓으면 조용히 밖으로 나간다.
##   눈으로는 잘 안 보이고 탭이 안 먹는 것으로만 드러나서, 여기서 좌표로 잡는다.
func _check_on_screen(scr: Control, vs: Vector2, mode: String, fields: Array) -> void:
	for f in fields:
		var b: Control = scr.get(String(f))
		if b == null or not b.visible:
			continue
		_ok(b.position.x >= -1.0 and b.position.x + b.size.x <= vs.x + 1.0
				and b.position.y >= -1.0 and b.position.y + b.size.y <= vs.y + 1.0,
				"%s %s: %s 버튼이 화면 밖 (%.0f,%.0f %.0fx%.0f)"
				% [scr.name, mode, f, b.position.x, b.position.y, b.size.x, b.size.y])


## 타이틀 추가 확인: 부모 관문의 '닫기' 를 답 판이 덮지 않는지.
## 관문에서 못 빠져나오면 설정을 되돌릴 방법이 없다.
func _check_title(t: Control, vs: Vector2, mode: String) -> void:
	t.call("_open_gate")
	await get_tree().process_frame
	var gate: ResultPanel = t.get("_gate")
	var pad: AnswerPad = t.get("_gate_pad")
	_ok(gate != null and pad != null and pad.visible, "타이틀 %s: 관문이 안 열림" % mode)
	if gate == null or pad == null:
		return
	var first: Control = pad.get("_buttons")[0]
	var pad_top := pad.position.y + first.position.y
	for b in gate.get("_buttons"):
		var btn: Control = b
		var bottom := btn.position.y + btn.size.y
		_ok(bottom <= pad_top + 1.0,
				"타이틀 %s: 관문의 '%s' 버튼(아래 %.0f)을 답 판(위 %.0f)이 덮음"
				% [mode, btn.get("text"), bottom, pad_top])
		_ok(bottom <= vs.y + 1.0, "타이틀 %s: 관문 버튼이 화면 아래로 넘침" % mode)
	var last: Control = pad.get("_buttons")[3]
	_ok(pad.position.y + last.position.y + last.size.y <= vs.y + 1.0,
			"타이틀 %s: 관문 답 판이 화면 아래로 넘침" % mode)
	t.call("_on_gate_action", "cancel")
	await get_tree().process_frame


## 아이 기준 UI 제약이 실제 배치에서 지켜지는지.
## 화면 크기를 바꿔가며 영역이 겹치지 않고 화면을 벗어나지 않는지 확인한다.
func _test_layout() -> void:
	print("\n[7] 레이아웃 불변식")
	# 기준은 가로 태블릿 1280x800. stretch=expand 라 뷰포트는 절대 그보다 작아지지 않으므로
	# 1280x800 이 가로에서 가장 빡빡한 경우다.
	#   가로: 1280x800(기준·최악), 1280x960(4:3 아이패드), 1896x800(21:9), 1600x900
	#   세로: 1280x2844(20:9 폰), 1280x1707(4:3 세로), 720x1280(옛 기준)
	var sizes := [Vector2(1280, 800), Vector2(1280, 960), Vector2(1896, 800),
			Vector2(1600, 900),
			Vector2(1280, 2844), Vector2(1280, 1707), Vector2(720, 1280)]
	Router.pending_tier = 11      # 12탄: 두 자리 받아내림 = 블록이 가장 많이 필요한 탄
	Router.pending_endless = false
	var packed: PackedScene = load("res://games/math/game/battle.tscn")
	for vs in sizes:
		var b := packed.instantiate()
		add_child(b)
		await get_tree().process_frame
		# 뷰포트에 붙지 않은 상태로 크기를 강제해 배치만 계산시킨다.
		(b as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(b as Control).size = vs
		b.call("_layout")
		await get_tree().process_frame

		var hud: Control = b.get("_hud")
		var card: Control = b.get("_card")
		var stage: Control = b.get("_stage")
		var pad: Control = b.get("_pad")
		var wide: bool = b.get("_wide")
		var label := "%dx%d %s" % [int(vs.x), int(vs.y), "가로" if wide else "세로"]

		_ok(wide == Layout.is_wide(vs), "%s: 배치 모드 판정이 Layout 과 다름" % label)
		_ok(card.position.y >= hud.size.y - 1.0,
				"%s: 문제 카드가 HUD 를 침범" % label)
		_ok(stage.position.y >= card.position.y + card.size.y - 1.0,
				"%s: 블록 무대가 카드를 침범" % label)
		_ok(stage.size.y >= 220.0, "%s: 블록 무대가 220px 미만 (%.0f)" % [label, stage.size.y])
		_ok(card.size.x <= vs.x and card.position.x >= 0.0,
				"%s: 카드가 가로로 넘침" % label)
		_ok(stage.position.x + stage.size.x <= vs.x + 1.0,
				"%s: 블록 무대가 가로로 넘침" % label)
		_ok(pad.position.x + pad.size.x <= vs.x + 1.0,
				"%s: 답 패드가 가로로 넘침" % label)
		_ok(pad.position.y + pad.size.y <= vs.y + 1.0,
				"%s: 답 패드가 화면 아래로 넘침" % label)

		if wide:
			# 가로: 답 열이 블록 무대 오른쪽에 따로 선다 (세로로 겹쳐도 된다).
			_ok(pad.position.x >= stage.position.x + stage.size.x - 1.0,
					"%s: 답 패드가 블록 무대를 가로로 침범 (무대 %.0f, 패드 %.0f)"
					% [label, stage.position.x + stage.size.x, pad.position.x])
			_ok(pad.position.y >= hud.size.y - 1.0,
					"%s: 답 패드가 HUD 를 침범" % label)
		else:
			# 세로: 답 패드가 블록 무대 아래에 오고 하단 여백을 남긴다.
			_ok(pad.position.y >= stage.position.y + stage.size.y - 1.0,
					"%s: 답 패드가 블록 무대를 침범 (무대 %.0f, 패드 %.0f)"
					% [label, stage.position.y + stage.size.y, pad.position.y])
			_ok(vs.y - (pad.position.y + pad.size.y) >= 40.0,
					"%s: 화면 하단 여백이 40px 미만 (홈 인디케이터 영역)" % label)

		# 캐릭터가 HUD 뒤로 잘리지 않는지.
		#
		# ★보스는 지정 높이의 1.7배로 그려져서 여기가 자주 넘쳤다. 배경 띠 높이만 보고
		#   크기를 잡으면 그 띠 위를 HUD 가 덮고 있다는 걸 놓쳐서, 얼굴과 왕관이 통째로
		#   HUD 뒤나 화면 밖으로 나간다. 뱀은 원점이 발밑이고 그림이 위로 자라므로
		#   "발밑 y - 그림 높이" 가 머리 끝이다.
		var hud_bottom: float = float(hud.call("content_height"))
		var frog: Node2D = b.get("_frog")
		_ok(frog.position.y - float(frog.get("_height")) >= hud_bottom - 1.0,
				"%s: 개구리 머리가 HUD 뒤로 들어감 (머리 %.0f < HUD 아래 %.0f)"
				% [label, frog.position.y - float(frog.get("_height")), hud_bottom])
		var mobs: Array = (b.get("_snakes") as Array).duplicate()
		var boss = b.get("_boss_snake")
		if boss != null:
			mobs.append(boss)
		_ok(not mobs.is_empty(), "%s: 뱀이 한 마리도 없음" % label)
		for m in mobs:
			var top: float = m.position.y - float(m.get("_art_h"))
			_ok(top >= hud_bottom - 1.0,
					"%s: 뱀 머리가 HUD 뒤로 들어감 (머리 %.0f < HUD 아래 %.0f)"
					% [label, top, hud_bottom])
			_ok(top >= -1.0, "%s: 뱀 머리가 화면 위로 나감 (%.0f)" % [label, top])
			_ok(m.position.y <= stage.position.y + 1.0,
					"%s: 뱀 발밑이 블록 무대를 침범 (%.0f)" % [label, m.position.y])

		# 답 버튼이 아이용 최소 터치 타깃(200x200)과 간격(36)을 지키는지
		pad.call("show_choices", [12, 3, 21, 30] as Array[int])
		await get_tree().process_frame
		var btn: Control = pad.call("button_for", 12)
		var btn2: Control = pad.call("button_for", 3)
		_ok(btn != null and btn2 != null, "%s: 보기 버튼이 만들어지지 않음" % label)
		if btn != null and btn2 != null:
			_ok(btn.size.x >= 195.0 and btn.size.y >= 195.0,
					"%s: 답 버튼이 200x200 미만 (%.0f x %.0f)"
					% [label, btn.size.x, btn.size.y])
			_ok(btn2.position.x - (btn.position.x + btn.size.x) >= 35.0,
					"%s: 답 버튼 간격이 36px 미만" % label)
			# 버튼이 답 판을 벗어나면 화면 밖이나 옆 판 위에 그려진다.
			_ok(pad.position.x + btn.position.x >= -1.0
					and pad.position.x + btn2.position.x + btn2.size.x <= vs.x + 1.0,
					"%s: 답 버튼이 화면 밖으로 나감" % label)
		print("  %-16s HUD %.0f / 카드 %.0f / 무대 %.0fx%.0f / 패드 %.0fx%.0f / 버튼 %.0f / 뱀 %.0f(머리 %.0f)"
				% [label, hud.size.y, card.size.y, stage.size.x, stage.size.y,
					pad.size.x, pad.size.y, btn.size.x if btn != null else 0.0,
					float(mobs[0].get("_art_h")),
					mobs[0].position.y - float(mobs[0].get("_art_h"))])
		b.queue_free()
		await get_tree().process_frame


func _test_op_alignment() -> void:
	print("\n[8] 문제 ↔ 설명 기호 정렬")
	Router.pending_tier = 1
	Router.pending_endless = false
	# 가로와 세로 양쪽에서 확인한다. 카드와 무대는 배치가 달라져도
	# 늘 같은 x/폭을 써야 좌표를 그대로 넘길 수 있다.
	for vs in [Vector2(1280, 800), Vector2(720, 1280)]:
		var mode := "가로" if Layout.is_wide(vs) else "세로"
		var b := (load("res://games/math/game/battle.tscn") as PackedScene).instantiate()
		add_child(b)
		await get_tree().process_frame
		(b as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(b as Control).size = vs
		b.call("_layout")
		await get_tree().process_frame

		var card: Control = b.get("_card")
		var stage: Control = b.get("_stage")
		_ok(is_equal_approx(card.position.x, stage.position.x)
				and is_equal_approx(card.size.x, stage.size.x),
				"%s: 카드와 무대의 x/폭이 달라 좌표를 그대로 쓸 수 없음" % mode)

		for spec in [[6, 1], [7, 5], [3, 2], [10, 10], [9, 9], [2, 8]]:
			var p := Problem.new()
			p.op = Problem.Op.ADD
			p.terms = [int(spec[0]), int(spec[1])]
			p.recompute()
			ProblemGen.build_choices(p, MathGame.rng)
			b.set("_problem", p)
			b.set("_problem_tier", 1 if p.answer < 10 else 8)
			card.call("set_problem", p)
			stage.call("setup", p, Curriculum.Display.TEN_FRAME, true)
			b.call("_sync_op_anchors")
			await get_tree().process_frame

			var card_ops: PackedFloat32Array = card.call("op_centers")
			var demo_ops: PackedFloat32Array = stage.get("_op_positions")
			var groups: Array = stage.get("_stage_groups")
			_ok(card_ops.size() >= 1 and demo_ops.size() >= 1,
					"%s %d+%d: 기호 위치를 못 구함" % [mode, p.a, p.b])
			if card_ops.is_empty() or demo_ops.is_empty():
				continue
			var d: float = absf(card_ops[0] - demo_ops[0])
			_ok(d <= 2.0, "%s %d+%d: 기호가 %.1f px 어긋남" % [mode, p.a, p.b, d])

			# 등호도 답을 고르기 전부터 격자 쪽에 깔려 있어야 한다 (합산판 바로 왼쪽).
			# 위 줄이 식의 왼쪽, 아래 줄이 "= 결과" — 두 줄로 옮겨 적은 식이 된다.
			var u: float = stage.get("_u")
			var eq: Vector2 = stage.get("_eq_center")
			var mat: Vector2 = stage.get("_mat_origin")
			var mat_w := (float(BlockStage.MAT_FRAMES) * float(BlockStage.FRAME_COLS)
					* BlockStage.CELL
					+ float(BlockStage.MAT_FRAMES - 1) * BlockStage.FRAME_GAP) * u
			_ok(bool(stage.get("_eq_visible")),
					"%s %d+%d: 합산판 왼쪽에 등호가 없음" % [mode, p.a, p.b])
			_ok(eq.x < mat.x, "%s %d+%d: 등호가 합산판 왼쪽에 있지 않음" % [mode, p.a, p.b])
			# `= [합산판]` 이 한 덩어리로 가운데에 놓이는지. 판 폭을 잘못 재면
			# (예전에 십틀 폭 대신 항 격자 폭을 곱했다) 여기서 한쪽으로 치우친다.
			var eq_left := eq.x - BlockStage.EQ_GAP * 0.5 * u
			var mat_right := mat.x + mat_w
			_ok(eq_left >= -1.0 and mat_right <= stage.size.x + 1.0,
					"%s %d+%d: 등호+합산판이 무대 밖 (%.0f ~ %.0f / 폭 %.0f)"
					% [mode, p.a, p.b, eq_left, mat_right, stage.size.x])
			_ok(absf(eq_left - (stage.size.x - mat_right)) <= 2.0,
					"%s %d+%d: 등호+합산판이 가운데가 아님 (왼쪽 %.0f, 오른쪽 %.0f)"
					% [mode, p.a, p.b, eq_left, stage.size.x - mat_right])

			# 무리끼리 겹치지 않고 화면 안에 들어오는지
			_ok(groups.size() == 2, "%s %d+%d: 무리가 2개가 아님" % [mode, p.a, p.b])
			if groups.size() == 2:
				var g0: Dictionary = groups[0]
				var g1: Dictionary = groups[1]
				var o0: Vector2 = g0["origin"]
				var o1: Vector2 = g1["origin"]
				_ok(o0.x + float(g0["width"]) < o1.x,
						"%s %d+%d: 두 무리가 겹침" % [mode, p.a, p.b])
				_ok(o0.x >= -1.0 and o1.x + float(g1["width"]) <= stage.size.x + 1.0,
						"%s %d+%d: 무리가 무대 밖으로 나감" % [mode, p.a, p.b])

		# 빈칸 문제도 격자가 둘이므로 똑같이 기호를 맞춰야 한다.
		# (선행 배치로 블록이 이미 놓여 있어서, 무대를 다시 세우지 않으면 정렬이 안 먹는다.)
		var mp := Problem.new()
		mp.op = Problem.Op.ADD
		mp.form = Problem.Form.MISSING
		mp.terms = [4, 0]
		mp.blank_index = 1
		mp.total = 10
		mp.recompute()
		ProblemGen.build_choices(mp, MathGame.rng)
		b.set("_problem", mp)
		b.set("_problem_tier", 3)
		card.call("set_problem", mp)
		stage.call("setup", mp, Curriculum.Display.TEN_FRAME, true)
		b.call("_sync_op_anchors")
		await get_tree().process_frame
		var mcard: PackedFloat32Array = card.call("op_centers")
		var mdemo: PackedFloat32Array = stage.get("_op_positions")
		_ok(mcard.size() >= 1 and mdemo.size() >= 1, "%s 4+□=10: 기호 위치를 못 구함" % mode)
		if mcard.size() >= 1 and mdemo.size() >= 1:
			_ok(absf(mcard[0] - mdemo[0]) <= 2.0,
					"%s 4+□=10: 기호가 %.1f px 어긋남" % [mode, absf(mcard[0] - mdemo[0])])
		_ok((stage.get("_stage_groups") as Array).size() == 2,
				"%s 4+□=10: 격자가 2개가 아님" % mode)

		print("  %s — 6가지 식 + 빈칸 식 정렬 확인" % mode)
		b.queue_free()
		await get_tree().process_frame


## 색이 곧 "어느 수인가"라는 약속을 지키는지.
##
## 왼쪽 항 = 주황, 오른쪽 항 = 파랑(뺄셈은 빨강), 찾아야 할 것 = 초록.
## 이게 무너지면 아이가 "위의 숫자"와 "아래 블록"을 다른 것으로 읽는다.
## 문제 카드와 블록 무대가 같은 함수(Problem.term_color)를 쓰는지도 여기서 잡는다.
func _test_colors() -> void:
	print("\n[10] 색 구분")

	var add := Problem.new()
	add.op = Problem.Op.ADD
	add.terms = [3, 4]
	add.recompute()
	_ok(add.term_color(0) == Palette.BLOCK_A, "덧셈: 왼쪽 항이 주황이 아님")
	_ok(add.term_color(1) == Palette.BLOCK_B, "덧셈: 오른쪽 항이 파랑이 아님")

	var sub := Problem.new()
	sub.op = Problem.Op.SUB
	sub.terms = [9, 4]
	sub.recompute()
	_ok(sub.term_color(0) == Palette.BLOCK_A, "뺄셈: 왼쪽 항이 주황이 아님")
	_ok(sub.term_color(1) == Palette.BLOCK_REMOVE, "뺄셈: 오른쪽 항이 빨강이 아님")

	# 보기 버튼 · 물음표 상자 · 빈칸 블록은 전부 같은 초록이어야 한다.
	_ok(add.blank_color() == Palette.CHOICE, "빈칸 색이 보기 색과 다름")

	# 그 초록이 어떤 항 색과도 헷갈리면 안 된다.
	var terms := {
		"왼쪽(주황)": Palette.BLOCK_A,
		"오른쪽(파랑)": Palette.BLOCK_B,
		"셋째(보라)": Palette.BLOCK_C,
		"빼는(빨강)": Palette.BLOCK_REMOVE,
	}
	for name in terms:
		var d := _color_dist(Palette.CHOICE, terms[name])
		_ok(d >= 0.30, "보기 초록과 %s 이 너무 비슷함 (거리 %.2f)" % [name, d])

	# 기본 보기색과 '정답' 표시색도 갈려야 한다 (둘 다 초록 계열이라서).
	var dc := _color_dist(Palette.CHOICE, Palette.CORRECT)
	_ok(dc >= 0.25, "보기 초록과 정답 초록이 구분되지 않음 (거리 %.2f)" % dc)
	print("  항 색 4종 · 보기 초록 · 정답 초록 모두 구분됨")


func _color_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## 두 언어가 다 채워져 있는지, 커리큘럼이 쓰는 키가 다 있는지.
## 하나라도 비면 영어 모드에서 키 문자열이 그대로 화면에 나온다.
## 익스포트 설정 — 지워지면 **오류 없이** 기기에서만 깨지는 값들.
##
## 여기 있는 것들은 전부 익스포트가 조용히 성공한 뒤 실제 폰/태블릿에서만 드러난다.
## 그래서 사람 눈 대신 여기서 지킨다.
func _test_export_settings() -> void:
	print("\n[11] 익스포트 설정 (기기에서만 드러나는 값들)")

	# 안드로이드: 없으면 익스포트가 아예 막힌다.
	_ok(bool(ProjectSettings.get_setting(
			"rendering/textures/vram_compression/import_etc2_astc", false)),
			"import_etc2_astc 가 꺼져 있음 — 안드로이드 익스포트가 막힌다")

	# iOS 앱 이름: 애플은 App ID 이름에 영문·숫자만 받는다.
	# 한글이면 무료 서명(AltStore/Sideloadly)이 App ID 를 못 만든다.
	var ios_name := String(ProjectSettings.get_setting("application/config/name.ios", ""))
	_ok(not ios_name.is_empty(), "config/name.ios 가 없음 — 아이폰 앱 이름이 한글로 나간다")
	var ascii_ok := not ios_name.is_empty()
	for c in ios_name:
		if not ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			ascii_ok = false
	_ok(ascii_ok, "config/name.ios 에 영문·숫자가 아닌 글자가 있음 (%s)" % ios_name)

	# 익스포트 프리셋. 편집기 파일이라 익스포트된 빌드에는 없지만,
	# 이 테스트는 프로젝트 폴더에서 도므로 읽을 수 있다.
	var cf := ConfigFile.new()
	if cf.load("res://export_presets.cfg") != OK:
		_ok(false, "export_presets.cfg 를 읽지 못함")
		return
	var ios_section := ""
	for s in cf.get_sections():
		if s.ends_with(".options"):
			continue
		if String(cf.get_value(s, "platform", "")) == "iOS":
			ios_section = s + ".options"
	_ok(not ios_section.is_empty(), "iOS 익스포트 프리셋이 없음")
	if ios_section.is_empty():
		return

	# ★아이패드가 '아이폰 호환 모드'(폰 크기 창 + 통째 여백)로 뜨지 않게.
	#   0=아이폰 / 1=아이패드 / 2=둘 다. 기준 해상도가 가로 태블릿인 게임이라 2 여야 한다.
	_ok(int(cf.get_value(ios_section, "application/targeted_device_family", -1)) == 2,
			"iOS targeted_device_family 가 2(아이폰+아이패드)가 아님 — 아이패드가 여백투성이로 뜬다")
	# 비어 있으면 Godot 이 익스포트 자체를 거부한다 (자리표시자라도 있어야 한다).
	_ok(not String(cf.get_value(ios_section, "application/app_store_team_id", "")).is_empty(),
			"app_store_team_id 가 비어 있음 — iOS 익스포트가 거부된다")
	# 번들 ID 는 `A-Z a-z 0-9 - .` 만 된다. 밑줄이 들어가면 익스포트가 중단된다.
	var bid := String(cf.get_value(ios_section, "application/bundle_identifier", ""))
	_ok(not bid.is_empty(), "bundle_identifier 가 비어 있음")
	_ok(not bid.contains("_"), "bundle_identifier 에 밑줄이 있음 (%s)" % bid)
	print("  iOS: 이름 %s / 기기군 %s / 번들 %s" % [ios_name,
			cf.get_value(ios_section, "application/targeted_device_family", -1), bid])


func _test_localization() -> void:
	print("\n[9] 한국어 / English")
	for k in Loc.STRINGS:
		var d: Dictionary = Loc.STRINGS[k]
		_ok(d.has("ko") and String(d["ko"]) != "", "%s: 한국어 없음" % k)
		_ok(d.has("en") and String(d["en"]) != "", "%s: 영어 없음" % k)
		# 서식 문자열은 두 언어의 %기호 개수가 같아야 한다 (아니면 런타임 오류).
		var ko := String(d.get("ko", ""))
		var en := String(d.get("en", ""))
		_ok(ko.count("%") == en.count("%"),
				"%s: 서식 개수가 다름 (ko %d / en %d)" % [k, ko.count("%"), en.count("%")])

	# ★ 뱀 생김새·지도 테마 검사는 없앴다 — 그 서사 장치를 걷어냈기 때문이다.
	#   대신 탄 목록 화면이 모든 탄을 그릴 수 있는지만 본다.
	var tiers_inst := (load(Router.TIERS) as PackedScene).instantiate()
	add_child(tiers_inst)
	tiers_inst.size = Vector2(1280, 800)
	if tiers_inst.has_method("_layout"):
		tiers_inst.call("_layout")
	for i in Curriculum.tier_count():
		var r: Rect2 = tiers_inst.call("_tile_rect", i)
		_ok(r.position.x >= 0.0 and r.position.x + r.size.x <= 1280.0,
				"%d탄 칸이 화면 밖으로 나감 (x %.0f~%.0f)" % [i + 1, r.position.x, r.position.x + r.size.x])
		_ok(r.size.x >= 120.0 and r.size.y >= 120.0,
				"%d탄 칸이 너무 작음 (%.0fx%.0f)" % [i + 1, r.size.x, r.size.y])
	tiers_inst.queue_free()

	# 커리큘럼이 참조하는 키가 전부 있는지
	for i in Curriculum.tier_count():
		var key := String(Curriculum.tier(i).get("key", ""))
		_ok(Loc.STRINGS.has(key), "%d탄 이름 키 없음: %s" % [i + 1, key])
		_ok(Loc.STRINGS.has(key + "g"), "%d탄 목표 키 없음: %sg" % [i + 1, key])
	for w in Curriculum.world_count():
		var wk := String(Curriculum.world(w).get("key", ""))
		_ok(Loc.STRINGS.has(wk), "월드 이름 키 없음: %s" % wk)
		_ok(Loc.STRINGS.has(wk + "s"), "월드 부제 키 없음: %ss" % wk)

	# 실제로 언어를 바꿔 보고 이름이 달라지는지
	var before := Curriculum.tier_name(0)
	Loc.lang = "en"
	var after := Curriculum.tier_name(0)
	_ok(before != after, "언어를 바꿔도 탄 이름이 그대로임")
	_ok(Loc.t("start") == "Start!", "영어 문자열이 안 나옴")
	Loc.lang = "ko"
	_ok(Loc.t("start") == "시작!", "한국어로 되돌아오지 않음")
	print("  문자열 %d개, 두 언어 확인" % Loc.STRINGS.size())


## src/ 의 모든 스크립트가 실제로 컴파일되는지.
## `--import` 는 컴파일 오류를 알려주지 않아서, 깨진 스크립트가 조용히 섞여 들어갈 수 있다.
## (실제로 뱀 스크립트가 깨져 뱀이 안 나오는 걸 이 검사가 없어서 늦게 발견했다.)
func _test_all_scripts_load() -> void:
	print("\n[0] 스크립트 컴파일")
	var files: Array[String] = []
	_collect_gd("res://games", files)
	_collect_gd("res://shell", files)
	_collect_gd("res://core", files)
	for f in files:
		var sc: Script = load(f) as Script
		_ok(sc != null, "%s: 로드 실패" % f)
		if sc == null:
			continue
		_ok(sc.can_instantiate() or sc.get_instance_base_type() == "",
				"%s: 인스턴스를 만들 수 없음 (컴파일 오류)" % f)
	print("  %d개 스크립트 ok" % files.size())


func _collect_gd(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_collect_gd(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
