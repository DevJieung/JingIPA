## 블록으로 연산을 시연하는 무대 — 이 게임의 핵심.
##
## 화면 구성 (덧셈):
##   ┌────────────────────────────────────────────────────┐
##   │ ┌─┬─┬─┬─┬─┐┌─┬─┬─┬─┬─┐  +  ┌─┬─┬─┬─┬─┐┌─┬─┬─┬─┬─┐ │ ← 항 격자 20칸
##   │ ├─┼─┼─┼─┼─┤├─┼─┼─┼─┼─┤     ├─┼─┼─┼─┼─┤├─┼─┼─┼─┼─┤ │
##   │            15                       3              │
##   ├────────────────────────────────────────────────────┤
##   │          =  ┌─┬─┬─┬─┬─┐  ┌─┬─┬─┬─┬─┐               │ ← 합산판 20칸
##   │             ├─┼─┼─┼─┼─┤  ├─┼─┼─┼─┼─┤               │
##   └────────────────────────────────────────────────────┘
##                     12                                   ← 세는 중인 수
##
## ★등호도 격자 쪽에 처음부터 깔려 있다. 위 줄이 식의 왼쪽, 아래 줄이 "= 결과" 다 —
##   식을 두 줄로 옮겨 적은 그림과 같다. 예전에는 `+` 만 있고 `=` 가 없어서,
##   위 격자와 아래 판이 왜 이어지는지가 화면에 적혀 있지 않았다.
##
## 격자 칸 수는 문제 내용에 따라 바뀌지 않는다.
##   - 항 격자 = 20칸  (항이 두 자리인 탄이 있다: 15 − 3)
##                     단 항이 셋 이상이면 10칸 — GROUP_FRAMES_MANY 주석 참고
##   - 합산판  = 20칸  (이 게임의 최대치가 20)
## 칸 수가 문제마다 바뀌면 아이가 매번 화면을 다시 읽어야 한다.
##
## 진행 순서가 곧 설명이다:
##   1. 문제 카드의 왼쪽 숫자가 강조된다  → 왼쪽 격자에 블록이 하나씩 '딱딱딱' 놓인다
##   2. 연산 기호가 나타난다 (문제 카드의 기호와 정확히 같은 x)
##   3. 오른쪽 숫자가 강조되고 오른쪽 격자가 채워진다
##   4. 왼쪽 격자를 합산판에 쏟는다 → 이어서 오른쪽 격자를 쏟는다
##   5. 결과를 강조한다 (다시 세지 않는다 — 쏟는 동안 이미 셌다)
##
## ★10칸이 찰 때 묶는 연출을 넣지 않는다.
##   예전에는 합산판의 첫 십틀이 차는 순간 금색 테두리로 잠그고 "10" 배지를 붙였다가,
##   뺄 때 다시 푸는 장면이 있었다(받아올림/받아내림). 설명 자체는 옳았지만
##   한 문제마다 2초 가까이 더 걸려서, 아이가 **기다리는 시간이 계산하는 시간보다 길어졌다.**
##   자릿값은 십틀 두 개(5칸씩 두 줄)의 모양만으로도 읽힌다 — 앞 틀이 꽉 차고
##   뒤 틀로 넘어가는 것이 곧 받아올림이다. 다시 넣지 말 것.
##
## 빈칸 문제(a + □ = b)는 격자를 **셋 다** 깐다 — a 격자, □ 격자, 그리고 합산판.
##   □ 자리 격자는 보기 버튼과 같은 초록이라 "여기가 내가 채울 곳" 이 먼저 읽힌다.
##   답을 고르면 그 초록 격자에 블록이 하나씩 놓이는데, **정확히 같은 순간에**
##   합산판도 한 칸씩 늘어난다(뺄셈 형태라면 줄어든다).
##   이 동시성이 이 문제 유형의 설명 전부다 — "□ 에 하나 넣으면 저쪽도 하나 늘어난다".
##
## 곱셈은 자릿값 판을 쓰지 않는다. 가르칠 대상이 '직사각형성'이라
## 십 막대로 압축하면 배열 구조가 깨진다. a씩 b묶음 = b행 x a열.
class_name BlockStage
extends Control

signal demo_finished
## 각 장면 시작 알림 (배틀 화면이 연출을 맞출 때).
signal segment_started(name: String)
## 지금 설명 중인 항의 인덱스. -1 이면 강조 해제. 문제 카드가 그 숫자를 키운다.
signal term_focus(index: int)
## 세는 중의 현재 수.
signal count_changed(value: int)

const FRAME_COLS := 5
const FRAME_ROWS := 2
const FRAME_CAP := FRAME_COLS * FRAME_ROWS   # 10
const MAT_FRAMES := 2                        # 합산판은 항상 20칸
const MAT_CAP := FRAME_CAP * MAT_FRAMES
## 항 격자는 합산판과 똑같이 십틀 2개 = 20칸이다.
##
## ★예전에는 10칸이었는데, 5·6·10·12탄은 항이 두 자리다(15 − 3 등).
##   그래서 "15" 라고 쓰인 격자에 블록이 10개만 놓이고, 합산판에서 세는 숫자도
##   10부터 시작해 마지막에 답으로 튀었다. 아이가 세어 보면 절대 맞지 않는다.
##   합산판과 같은 20칸을 쓰면 어떤 항이든 그대로 놓이고, 3탄에서 보던
##   '채우기 → 쏟기 → 부딪히기' 흐름이 모든 탄에서 똑같이 성립한다.
const GROUP_FRAMES := 2
const GROUP_CAP := FRAME_CAP * GROUP_FRAMES  # 20

## 단, **항이 셋 이상이면 십틀 하나(10칸)**로 돌아간다.
##
## 세 수의 계산(7·8탄)은 커리큘럼상 항이 전부 한 자리라 20칸이 쓰일 일이 없는데,
## 20칸짜리 격자 셋을 가로로 늘어놓으면 폭이 모자라 블록이 18px 까지 쪼그라든다
## (2항일 때는 29px). 쓰지도 않을 칸 때문에 블록이 절반이 되는 건 손해다.
## 문제마다 바뀌는 게 아니라 **항 개수마다** 정해지므로, 한 탄 안에서는 늘 같다.
## (tests 의 "3항 이상은 항이 10 이하" 검사가 이 전제를 지킨다.)
const GROUP_FRAMES_MANY := 1

# 단위 U 에 대한 비율들 (U = 낱개 블록 한 변)
const CELL := 1.18
const FRAME_GAP := 0.34   # 합산판의 두 십틀 사이
const ROW_GAP := 0.95     # 항 격자 줄과 합산판 사이
const OP_GAP := 1.60      # 항 격자 사이 (연산 기호 자리)
## 합산판 왼쪽의 등호 자리. 항 격자 사이의 기호 자리와 폭이 같아야
## 위 줄의 `+` 와 아래 줄의 `=` 가 같은 크기·같은 여백으로 읽힌다.
const EQ_GAP := OP_GAP
const LABEL_H := 46.0
const GROUP_LABEL := 1.85 # 격자 아래 숫자 라벨 자리
const U_MIN := 14.0
const U_MAX := 62.0

## 전체 재생 속도 배율. 크면 느리다.
const PACE := 1.55

## 블록 하나를 놓거나 옮기고 다음 것까지 쉬는 간격(초). **개수와 무관하게 항상 같다.**
##
## ★예전에는 "전체 0.8초를 개수로 나눠" 썼다. 그래서 3개짜리 탄은 한 개마다 0.13초,
##   15개짜리 탄은 0.05초 — 손놀림이 세 배 가까이 달랐다. 아이는 그 차이를
##   "블록이 많구나"가 아니라 "이 탄은 빠르다/느리다"로 읽는다. 같은 동작은 어느 탄에서나
##   같은 속도여야 화면을 다시 배우지 않는다. 오래 걸리는 건 개수가 많아서지 속도 때문이 아니다.
const FILL_GAP := 0.07
const POUR_GAP := 0.06

var _problem: Problem
var _display: int = Curriculum.Display.TEN_FRAME
var _ten_frame := true

# 배치 값 (로컬 픽셀)
var _u := 40.0
var _cell := 47.0
var _mat_origin := Vector2.ZERO      # 합산판 첫 십틀의 왼쪽 위
var _mat_bottom := 0.0
var _row_bottom := 0.0               # 항 격자들의 바닥선
var _stage_groups: Array[Dictionary] = []
var _grid_origin := Vector2.ZERO     # 곱셈 배열 왼쪽 위
var _count_center := Vector2.ZERO

# 살아있는 노드
var _ones: Array[BlockUnit] = []     # 합산판 (슬롯 순서)
var _mul: Array[BlockUnit] = []

# 라벨/상태
var _count_text := ""
var _hint_text := ""
var _reveal := true
var _empty_glow := 0.0
## 빈칸 문제(a + □ = b)에서 합산판에 미리 흐릿하게 깔아 둘 칸 수와,
## 그중 '이미 아는 수'가 차지하는 앞쪽 칸 수. 0이면 안 깐다.
var _ghost_total := 0
var _ghost_known := 0
## 이번 문제의 항 격자가 쓰는 십틀 개수 (_layout 이 정한다).
var _group_frames := GROUP_FRAMES
var _ops_visible := 0
var _op_anchors := PackedFloat32Array()
var _op_positions := PackedFloat32Array()
## 합산판 왼쪽 등호의 중심. 곱셈(배열 표시)에는 합산판이 없어서 그리지 않는다.
var _eq_center := Vector2.ZERO
var _eq_visible := false

## 결과 숫자가 한 번 커졌다 돌아오는 강조.
var _count_pop := 0.0:
	set(v):
		_count_pop = v
		queue_redraw()

# 재생 제어
var _running := false
var _flash := false
var _segment := 0
var _skip_segment := -1
var _cancelled := false
var _tweens: Array[Tween] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	resized.connect(_on_resized)


func _exit_tree() -> void:
	_cancelled = true


func is_running() -> bool:
	return _running


func set_flash_mode(on: bool) -> void:
	_flash = on
	_demo_level = 2 if on else 0


## 시연 단계 0~4. 올라갈수록 설명이 짧아진다.
##
## ★ 이 축은 **내려가기만 하는 난이도**다. 기다림을 늘리는 것은 아이에게 벌이지만,
##   줄여 주는 것은 보상이다. 그래서 숙련될수록 저절로 짧아지고, 틀리면
##   다시 자세해진다 — 아이 눈에는 "설명이 다시 친절해진 것"으로만 보인다.
##
##   10탄 15-8 기준: m0 26.8초 / m1 21.4 / m2 16.6 / m3 10.4 / m4 1.9초
const DEMO_SCALE := [1.00, 0.80, 0.62, 0.48, 0.0]
var _demo_level := 0


func set_demo_level(m: int) -> void:
	_demo_level = clampi(m, 0, 4)
	_flash = _demo_level >= 2


## 문제 카드의 연산 기호 x 를 받아 설명의 기호를 같은 자리에 맞춘다.
##
## ★`_layout()` 만 다시 돌리면 안 된다. `_stage_groups` 가 통째로 새로 만들어져서
##   이미 놓여 있는 블록 노드(빈칸 문제의 선행 배치)의 참조가 끊긴다.
##   무대를 다시 세우는 편이 안전하고, 같은 값이면 아무것도 하지 않는다.
func set_op_anchors(xs: PackedFloat32Array) -> void:
	if _op_anchors == xs:
		return
	_op_anchors = xs
	if _problem != null and not _running:
		setup(_problem, _display, _ten_frame)


# --------------------------------------------------------------------------- #
# 준비
# --------------------------------------------------------------------------- #

func setup(p: Problem, display: int = Curriculum.Display.TEN_FRAME,
		ten_frame: bool = true) -> void:
	_problem = p
	_display = display
	_ten_frame = ten_frame
	_cancelled = false
	_running = false
	_segment = 0
	_skip_segment = -1
	_reveal = true
	_count_text = ""
	_hint_text = ""
	_empty_glow = 0.0
	_count_pop = 0.0
	_ghost_total = 0
	_ghost_known = 0
	_clear_nodes()
	_layout()
	if p != null and p.form == Problem.Form.MISSING \
			and display != Curriculum.Display.ARRAY:
		_prestage_missing()
	queue_redraw()


## 빈칸 문제(a + □ = b)의 **시연 전** 화면을 만든다.
##
## 아이가 답을 고르기 전에 이미 이만큼은 보여 준다:
##   - 아는 수의 격자에 a 개가 놓여 있고 (숫자도 적혀 있다)
##   - □ 자리에도 **같은 크기의 격자가 비어 있다.** 초록이고 아래에 "?" 가 적혀 있다.
##   - 합산판에는 결과 b 칸이 흐릿하게 깔려 있다.
##     앞의 a 칸은 아는 수와 같은 색, 나머지가 찾아야 할 초록 칸이다.
##
## ★격자를 셋 다 깔아야 식과 화면이 같은 그림이 된다. 예전에는 □ 자리 격자가
##   아예 없어서 "a + □ = b" 인데 화면에는 격자가 하나뿐이었다.
## ★합산판을 미리 깔아야 "칸이 몇 개 비었지?"를 세어서 답을 찾을 수 있다.
##   예전에는 시연을 시작해야 빈 칸이 보여서, 답을 고르는 시점에는
##   화면에 단서가 하나도 없었다.
func _prestage_missing() -> void:
	if _problem == null or _stage_groups.size() < 2:
		return
	var g: Dictionary = _stage_groups[_known_index()]
	var n: int = mini(int(g["value"]), _group_cap())
	var onodes: Array = g["ones_nodes"]
	for i in n:
		onodes.append(_spawn_block(_group_slot(g, i), g["color"], false))
	g["shown"] = true
	_ghost_total = clampi(_problem.total, 0, MAT_CAP)
	_ghost_known = clampi(n, 0, _ghost_total)
	# 결과 수는 식에 이미 적혀 있으므로 판 아래에도 미리 적어 둔다.
	_count_text = str(_problem.total)


## 빈칸 문제에서 이미 아는 항(=□ 가 아닌 항)의 인덱스. 격자 인덱스와 항 인덱스는 같다.
func _known_index() -> int:
	if _problem == null or _problem.form != Problem.Form.MISSING:
		return 0
	return clampi(1 - _problem.blank_index, 0, maxi(0, _problem.terms.size() - 1))


func clear_stage() -> void:
	_problem = null
	_clear_nodes()
	queue_redraw()


func _clear_nodes() -> void:
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()
	for b in _ones:
		if is_instance_valid(b):
			b.queue_free()
	_ones.clear()
	for b in _mul:
		if is_instance_valid(b):
			b.queue_free()
	_mul.clear()
	for g in _stage_groups:
		for n in (g["ones_nodes"] as Array):
			if is_instance_valid(n):
				n.queue_free()
	_stage_groups.clear()


func _on_resized() -> void:
	if _problem == null or _running:
		return
	setup(_problem, _display, _ten_frame)


# --------------------------------------------------------------------------- #
# 배치
# --------------------------------------------------------------------------- #

## 위 줄에 늘어놓을 항들. 식에 적힌 항은 전부 자기 격자를 갖는다.
##
## 빈칸 문제의 □ 도 예외가 아니다 — 값은 답이지만 아이가 답을 고르기 전에는
## 격자만 비어 있고(shown=false) 색이 초록(보기 버튼과 같은 색)이라
## "여기가 내가 채울 자리" 로만 읽힌다. 숫자는 채운 뒤에야 나온다.
func _staging_spec() -> Array:
	var out: Array = []
	if _problem == null or _display == Curriculum.Display.ARRAY:
		return out
	for i in _problem.terms.size():
		var blank := _problem.form == Problem.Form.MISSING and i == _problem.blank_index
		out.append({
			"term": i,
			"value": _problem.answer if blank else _problem.terms[i],
			"color": _problem.blank_color() if blank else _term_color(i),
			"blank": blank,
		})
	return out


## 항별 색. 합쳐진 뒤에도 색을 유지해서 "전체 안에 부분이 남아 있다"를 보인다.
## 판정은 Problem 한 곳에서 한다 — 문제 카드의 숫자 강조도 같은 색을 써야 하기 때문이다.
func _term_color(i: int) -> Color:
	if _problem == null:
		return Palette.BLOCK_A
	return _problem.term_color(i)


func _layout() -> void:
	if _problem == null:
		return
	var pad := 8.0
	var avail_w := maxf(60.0, size.x - pad * 2.0)
	var avail_h := maxf(60.0, size.y - pad * 2.0 - LABEL_H)

	if _display == Curriculum.Display.ARRAY:
		_layout_array(pad, avail_w, avail_h)
		return

	var groups := _staging_spec()
	_group_frames = GROUP_FRAMES_MANY if groups.size() >= 3 else GROUP_FRAMES
	var group_w := float(_group_frames) * float(FRAME_COLS) * CELL \
			+ float(_group_frames - 1) * FRAME_GAP
	var group_h := float(FRAME_ROWS) * CELL
	# 합산판은 십틀 MAT_FRAMES 개다. ★`group_w` 를 곱하면 안 된다 — 그건 이미 십틀
	#   여러 개를 합친 폭이라 판 폭이 두 배로 잡히고, 가운데 정렬이 그만큼 왼쪽으로
	#   치우친다 (실제로 판이 화면 왼쪽에 붙어 그려지고 있었다).
	var mat_w := float(MAT_FRAMES) * float(FRAME_COLS) * CELL \
			+ float(MAT_FRAMES - 1) * FRAME_GAP
	var mat_h := group_h

	var row_w := 0.0
	if not groups.is_empty():
		row_w = float(groups.size()) * group_w + float(groups.size() - 1) * OP_GAP
	var row_h := (group_h + GROUP_LABEL) if not groups.is_empty() else 0.0

	# 아래 줄은 `= [합산판]` 이 한 덩어리다. 등호까지 넣어서 가운데를 잡아야
	# 판만 가운데로 가고 등호가 밖으로 밀려나지 않는다.
	var eq_gap := EQ_GAP if not groups.is_empty() else 0.0
	var bottom_w := mat_w + eq_gap

	var w_coeff := maxf(bottom_w, row_w)
	var h_coeff := mat_h + (0.0 if groups.is_empty() else ROW_GAP + row_h)

	var u_fit := minf(avail_w / maxf(w_coeff, 0.1), avail_h / maxf(h_coeff, 0.1))
	# 문제 카드의 기호에 맞추려면, 기호 좌우에 격자가 들어갈 만큼만 커야 한다.
	if groups.size() == 2 and _op_anchors.size() >= 1:
		var anchor := float(_op_anchors[0])
		var c := group_w + OP_GAP * 0.5
		var left_room := anchor - pad
		var right_room := (pad + avail_w) - anchor
		if left_room > 1.0:
			u_fit = minf(u_fit, left_room / c)
		if right_room > 1.0:
			u_fit = minf(u_fit, right_room / c)
	_u = clampf(u_fit, U_MIN, U_MAX)
	_cell = _u * CELL

	var total_h := h_coeff * _u
	var top := pad + maxf(0.0, (avail_h - total_h) * 0.5)

	_stage_groups.clear()
	_op_positions = PackedFloat32Array()
	if not groups.is_empty():
		_row_bottom = top + group_h * _u
		var gw := group_w * _u
		var gap := OP_GAP * _u
		var start := pad + (avail_w - (float(groups.size()) * gw
				+ float(groups.size() - 1) * gap)) * 0.5
		if groups.size() == 2 and _op_anchors.size() >= 1:
			start = float(_op_anchors[0]) - gap * 0.5 - gw
		# 화면 밖으로 나가면 통째로 밀어 넣는다 (정렬보다 안 잘리는 게 우선).
		var span := float(groups.size()) * gw + float(groups.size() - 1) * gap
		start = clampf(start, pad, pad + avail_w - span)
		for i in groups.size():
			var g: Dictionary = groups[i]
			var gx := start + float(i) * (gw + gap)
			_stage_groups.append({
				"origin": Vector2(gx, _row_bottom),
				"term": int(g["term"]),
				"value": int(g["value"]),
				"color": g["color"],
				"blank": bool(g.get("blank", false)),
				"width": gw,
				"ones_nodes": [] as Array,
				"shown": false,
			})
			if i > 0:
				_op_positions.append(gx - gap * 0.5)
		# ★기호는 **처음부터** 보인다. 문제 카드의 식과 아래 격자가 같은 그림이어야
		#   아이가 둘을 잇는다. 예전에는 시연 도중에 하나씩 나타나서, 답을 고르는
		#   시점의 화면에는 빈 격자 둘만 있고 그 사이가 비어 있었다 —
		#   무슨 계산인지가 정작 그림에는 없었던 셈이다.
		_ops_visible = _stage_groups.size() - 1
		_mat_bottom = top + (row_h + ROW_GAP + mat_h) * _u
	else:
		_row_bottom = top
		_mat_bottom = top + mat_h * _u

	_mat_origin = Vector2(pad + (avail_w - bottom_w * _u) * 0.5 + eq_gap * _u,
			_mat_bottom - mat_h * _u)
	# 등호는 판의 세로 한가운데에, 판 왼쪽의 기호 자리 한가운데에 놓인다.
	_eq_visible = not groups.is_empty()
	_eq_center = Vector2(_mat_origin.x - eq_gap * 0.5 * _u,
			_mat_bottom - mat_h * _u * 0.5)
	_count_center = Vector2(size.x * 0.5, size.y - LABEL_H * 0.5)


func _layout_array(pad: float, avail_w: float, avail_h: float) -> void:
	# 곱셈은 합산판을 쓰지 않으므로 등호도 놓을 자리가 없다.
	_eq_visible = false
	# a씩 b묶음 -> b행 x a열. 한 줄이 한 묶음이다.
	var cols := maxi(1, _problem.a)
	var rows := maxi(1, _problem.b)
	_u = clampf(minf(avail_w / (float(cols) * CELL), avail_h / (float(rows) * CELL)),
			U_MIN, U_MAX)
	_cell = _u * CELL
	_grid_origin = Vector2(pad + (avail_w - float(cols) * _cell) * 0.5,
			pad + (avail_h - float(rows) * _cell) * 0.5)
	_count_center = Vector2(size.x * 0.5, size.y - LABEL_H * 0.5)


# --------------------------------------------------------------------------- #
# 좌표
# --------------------------------------------------------------------------- #

## 합산판 slot 번째 칸의 중심. 십틀 두 개가 나란히 있고, 각각 위 줄부터 채운다.
func _mat_slot(slot: int) -> Vector2:
	var frame := clampi(slot, 0, MAT_CAP - 1) / FRAME_CAP
	var idx := slot % FRAME_CAP
	return _mat_origin + Vector2(
			float(frame) * (float(FRAME_COLS) * _cell + FRAME_GAP * _u)
					+ (float(idx % FRAME_COLS) + 0.5) * _cell,
			(float(idx / FRAME_COLS) + 0.5) * _cell)


## 이번 문제의 항 격자가 담을 수 있는 칸 수 (20 또는 10).
func _group_cap() -> int:
	return FRAME_CAP * _group_frames


## 항 격자 안 i번째 칸의 중심. 합산판(_mat_slot)과 채우는 순서가 완전히 같다 —
## 같은 순서로 차야 격자에서 판으로 '그대로 옮겨간다'가 읽힌다.
func _group_slot(g: Dictionary, i: int) -> Vector2:
	var o: Vector2 = g["origin"]
	var top := o.y - float(FRAME_ROWS) * _cell
	var frame := clampi(i, 0, _group_cap() - 1) / FRAME_CAP
	var idx := i % FRAME_CAP
	return Vector2(
			o.x + float(frame) * (float(FRAME_COLS) * _cell + FRAME_GAP * _u)
					+ (float(idx % FRAME_COLS) + 0.5) * _cell,
			top + (float(idx / FRAME_COLS) + 0.5) * _cell)


func _group_center_x(g: Dictionary) -> float:
	var o: Vector2 = g["origin"]
	return o.x + float(g["width"]) * 0.5


func _grid_slot(index: int) -> Vector2:
	var cols := maxi(1, _problem.a)
	return _grid_origin + Vector2((float(index % cols) + 0.5) * _cell,
			(float(index / cols) + 0.5) * _cell)


func _spawn_block(pos: Vector2, color: Color, hidden: bool = true) -> BlockUnit:
	var b := BlockUnit.new(_u, color)
	b.position = pos
	if hidden:
		b.scale = Vector2.ZERO
		b.modulate.a = 0.0
	add_child(b)
	return b


# --------------------------------------------------------------------------- #
# 재생 제어
# --------------------------------------------------------------------------- #

func _alive() -> bool:
	return not _cancelled and is_inside_tree()


func _speed() -> float:
	var k: float = DEMO_SCALE[clampi(_demo_level, 0, 3)]
	return MathGame.anim_scale() * PACE * maxf(0.30, k)


func _dur(sec: float) -> float:
	if _skip_segment == _segment:
		return 0.001
	return maxf(0.001, sec * _speed())


func _begin(name: String) -> void:
	_segment += 1
	segment_started.emit(name)


## 화면을 탭하면 '현재 장면의 끝으로 점프'한다.
func skip() -> void:
	if not _running:
		return
	_skip_segment = _segment
	for t in _tweens:
		if t != null and t.is_valid():
			t.set_speed_scale(80.0)


func _new_tween() -> Tween:
	var t := create_tween()
	t.set_parallel(true)
	_tweens.append(t)
	return t


func _run(t: Tween) -> void:
	if t == null:
		return
	# 트위너가 없는 트윈은 finished 를 내지 않고 엔진 오류만 찍는다 (4.7 신규 API).
	if not t.has_tweeners():
		_tweens.erase(t)
		t.kill()
		return
	await t.finished
	_tweens.erase(t)


func _wait(sec: float) -> void:
	var target := sec * _speed()
	var elapsed := 0.0
	while elapsed < target and _skip_segment != _segment and _alive():
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _beat() -> void:
	await _wait(0.40)


# --------------------------------------------------------------------------- #
# 시연
# --------------------------------------------------------------------------- #

func play_demo(reveal: bool = true) -> void:
	if _problem == null:
		demo_finished.emit()
		return
	_reveal = reveal
	_running = true
	_skip_segment = -1
	# m=4 는 결과만 — 이 문제를 여러 번 첫시도에 맞힌 아이에게 같은 시연을
	# 또 보여 주는 것은 숙련을 처벌하는 일이다.
	if _demo_level >= 4:
		await _demo_result_only()
		_running = false
		term_focus.emit(-1)
		if _alive():
			demo_finished.emit()
		return
	if _display == Curriculum.Display.ARRAY:
		await _demo_mul()
	elif _problem.form == Problem.Form.MISSING:
		await _demo_missing()
	elif _problem.op == Problem.Op.SUB:
		await _demo_sub()
	else:
		await _demo_add()
	_running = false
	term_focus.emit(-1)
	if _alive():
		demo_finished.emit()


# --- 덧셈 ------------------------------------------------------------------ #

func _demo_add() -> void:
	for gi in _stage_groups.size():
		if not _alive():
			return
		_begin("term_%d" % gi)
		term_focus.emit(int(_stage_groups[gi]["term"]))
		await _fill_group(gi)
		if not _alive():
			return
		await _beat()

	term_focus.emit(-1)
	await _beat()

	for gi in _stage_groups.size():
		if not _alive():
			return
		_begin("pour_%d" % gi)
		term_focus.emit(int(_stage_groups[gi]["term"]))
		await _pour_group(gi)
		if not _alive():
			return
		await _beat()

	term_focus.emit(-1)
	_begin("count")
	await _show_result()


## 항 격자에 블록을 하나씩 '딱딱딱' 놓는다.
func _fill_group(gi: int) -> void:
	if gi < 0 or gi >= _stage_groups.size():
		return
	var g: Dictionary = _stage_groups[gi]
	var color: Color = g["color"]
	var n: int = mini(int(g["value"]), _group_cap())
	var onodes: Array = g["ones_nodes"]

	for i in n:
		if not _alive():
			return
		var b := _spawn_block(_group_slot(g, i), color)
		onodes.append(b)
		var tw := _new_tween()
		tw.tween_property(b, "scale", Vector2.ONE, _dur(0.16)) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "modulate:a", 1.0, _dur(0.10))
		Audio.play_block(i, maxi(n, 1), _fill_sfx(gi))
		await _run(tw)
		await _wait(FILL_GAP)

	g["shown"] = true
	queue_redraw()


## 시연 단계 4 전용: 트윈 없이 블록을 놓인 상태로 바로 만든다.
func _fill_group_instant(gi: int) -> void:
	if gi < 0 or gi >= _stage_groups.size():
		return
	var g: Dictionary = _stage_groups[gi]
	var color: Color = g["color"]
	var n: int = mini(int(g["value"]), _group_cap())
	var onodes: Array = g["ones_nodes"]
	for i in n:
		var b := _spawn_block(_group_slot(g, i), color)
		b.scale = Vector2.ONE
		b.modulate.a = 1.0
		onodes.append(b)
	g["shown"] = true
	queue_redraw()


## 이 격자에 블록을 놓을 때 낼 소리.
##
## 뺄셈의 **빼는 수(붉은 블록)** 만 "챡!" 하는 딱딱한 소리를 쓴다.
## 얹을 블록은 둥근 마림바 톡 — 두 소리가 갈려야 아이가 화면을 안 보고도
## "이건 덜어낼 것"이라고 알아챈다. 음정이 올라가는 규칙은 둘 다 똑같다.
func _fill_sfx(gi: int) -> String:
	if _problem != null and _problem.op == Problem.Op.SUB and gi > 0:
		return "block_snap"
	return "block_pop"


## 항 격자를 합산판으로 쏟는다. 낱개는 반드시 하나씩 —
## 한꺼번에 날아가면 10이 채워지는 순간도, 세기 오류를 고칠 기회도 사라진다.
func _pour_group(gi: int) -> void:
	if gi < 0 or gi >= _stage_groups.size():
		return
	var g: Dictionary = _stage_groups[gi]
	var onodes: Array = g["ones_nodes"]
	var total := onodes.size()

	for i in total:
		if not _alive():
			return
		var b: BlockUnit = onodes[i]
		if not is_instance_valid(b):
			continue
		var slot := _ones.size()
		var tw := _new_tween()
		tw.tween_property(b, "position", _mat_slot(slot), _dur(0.20)) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_ones.append(b)
		Audio.play_block(i, maxi(total, 1))
		await _run(tw)
		if not _alive():
			return
		_set_count(_ones.size())
		await _wait(POUR_GAP)
	onodes.clear()
	g["shown"] = false
	queue_redraw()


# --- 뺄셈 ------------------------------------------------------------------ #

func _demo_sub() -> void:
	# 1) 왼쪽 수를 격자에 나열 (덧셈과 완전히 같은 흐름)
	_begin("term_0")
	term_focus.emit(0)
	await _fill_group(0)
	if not _alive():
		return
	await _beat()

	# 2) 빼기 기호가 나오고, 오른쪽 수도 똑같이 나열한다 (붉은 블록)
	for gi in range(1, _stage_groups.size()):
		if not _alive():
			return
		_begin("term_%d" % gi)
		term_focus.emit(int(_stage_groups[gi]["term"]))
		await _fill_group(gi)
		if not _alive():
			return
		await _beat()
	term_focus.emit(-1)
	await _beat()

	# 3) 왼쪽 수를 합산판에 쏟는다 (여기까지 덧셈과 동일)
	_begin("pour_0")
	term_focus.emit(0)
	await _pour_group(0)
	if not _alive():
		return
	term_focus.emit(-1)
	await _beat()

	# 4) 붉은 블록이 하나씩 날아가 판의 블록에 '박치기' 하고 둘 다 사라진다.
	for gi in range(1, _stage_groups.size()):
		if not _alive():
			return
		_begin("smash_%d" % gi)
		term_focus.emit(int(_stage_groups[gi]["term"]))
		await _collide_remove(gi)
		if not _alive():
			return
		term_focus.emit(-1)
		await _beat()

	_begin("count")
	await _show_result()


## 빼는 블록이 판의 블록에 부딪혀 둘 다 없어진다.
## "덜어낸다"를 1:1 로 보여주는 장면 — 몇 개가 사라졌는지 세지 않아도 눈에 남는다.
##
## ★**뒤에 놓은 빨간 블록부터** 날아간다. 앞에서부터 빼면 남은 빨간 블록 사이에 구멍이
##   생겨서(3개 중 첫 칸이 비고 2·3번 칸만 남는다) "몇 개 남았지?" 를 세려면 흩어진 걸
##   다시 읽어야 한다. 뒤에서부터 빼면 남은 것이 늘 앞쪽에 붙어 있어 3 → 2 → 1 이
##   그대로 보인다. 합산판도 마지막 칸부터 없어지므로 두 격자가 같은 방향으로 줄어든다.
func _collide_remove(gi: int) -> void:
	if gi < 0 or gi >= _stage_groups.size():
		return
	var g: Dictionary = _stage_groups[gi]
	var reds: Array = g["ones_nodes"]
	for i in range(reds.size() - 1, -1, -1):
		if not _alive():
			return
		var r: BlockUnit = reds[i]
		if not is_instance_valid(r):
			continue
		if _ones.is_empty():
			break
		var target: BlockUnit = _ones[_ones.size() - 1]

		# 어디를 칠지 먼저 보여준다.
		var tw0 := _new_tween()
		tw0.tween_property(target, "highlight", 0.75, _dur(0.10))
		await _run(tw0)
		if not _alive():
			return

		# 날아가서 부딪힌다.
		var tw := _new_tween()
		tw.tween_property(r, "position", target.position, _dur(0.20)) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await _run(tw)
		if not _alive():
			return
		Audio.play("snake_hit", 1.2, -5.0)
		Fx.ring_pulse(self, target.position, Palette.BLOCK_REMOVE, _u * 1.7)

		# 둘 다 팡 하고 사라진다.
		var tw2 := _new_tween()
		for n in [r, target]:
			tw2.tween_property(n, "scale", Vector2(1.38, 0.72), _dur(0.08))
			tw2.tween_property(n, "scale", Vector2.ZERO, _dur(0.20)).set_delay(_dur(0.08))
			tw2.tween_property(n, "modulate:a", 0.0, _dur(0.20)).set_delay(_dur(0.08))
			tw2.tween_property(n, "highlight", 0.0, _dur(0.10))
		await _run(tw2)
		if not _alive():
			return
		_ones.erase(target)
		if is_instance_valid(target):
			target.queue_free()
		if is_instance_valid(r):
			r.queue_free()
		_set_count(_ones.size())
		await _wait(POUR_GAP)
	reds.clear()
	g["shown"] = false
	queue_redraw()


# --- 빈칸 (a + □ = 10) ------------------------------------------------------ #

## 빈칸 문제(a + □ = b) 시연.
##
## 흐름을 보통 덧셈과 **똑같이** 맞춘다 — 쏟기 → 이어서 채우기 → 결과 강조.
## 다른 점은 두 번째 몫이 □ 격자와 합산판에서 **동시에** 자란다는 것뿐이다.
##
## ★답을 알기 전에는 이 함수가 돌지 않는다. 시연은 아이가 보기를 고른 뒤에만 재생된다.
func _demo_missing() -> void:
	var ki := _known_index()

	# 1) 이미 놓여 있는 아는 수를 합산판에 쏟는다 (덧셈의 '쏟기'와 완전히 같다).
	_begin("pour_%d" % ki)
	term_focus.emit(ki)
	await _pour_group(ki)
	if not _alive():
		return
	term_focus.emit(-1)
	await _beat()

	# 2) 남은 빈칸이 '찾던 자리'라는 걸 한 번 짚어 준다.
	#    (판이 줄어드는 형태에서는 채울 빈칸이 없으므로 건너뛴다.)
	if _problem.op != Problem.Op.SUB:
		_begin("empty_slots")
		var tw := _new_tween()
		tw.tween_property(self, "_empty_glow", 1.0, _dur(0.40))
		await _run(tw)
		if not _alive():
			return
		await _beat()

	# 3) □ 격자를 하나씩 채우면서 합산판을 같은 박자로 움직인다.
	_begin("fill")
	term_focus.emit(_problem.blank_index)
	await _fill_blank_coupled()
	if not _alive():
		return

	term_focus.emit(-1)
	var tw2 := _new_tween()
	tw2.tween_property(self, "_empty_glow", 0.0, _dur(0.28))
	await _run(tw2)
	if not _alive():
		return
	_begin("count")
	await _show_result()


## □ 격자에 블록을 하나씩 놓으면서, **같은 트윈으로** 합산판도 한 칸씩 움직인다.
##
## ★두 판이 정확히 같은 순간에 움직여야 한다. 하나 놓고 → 잠시 뒤 저쪽이 움직이면
##   아이는 그걸 '다음 단계'로 읽지 '같은 사건'으로 읽지 않는다. 이 문제 유형이
##   가르치는 건 값이 아니라 그 대응 관계다 — □ 에 하나 넣으면 저쪽도 하나 움직인다.
## ★뺄셈 형태(a − □ = b)라면 합산판에서 하나씩 빠진다. 지금 커리큘럼은
##   a + □ = b 만 만들지만(Problem.recompute 가 그렇게 막는다), 방향이 반대라는 것만
##   다르고 대응 관계는 똑같아서 여기서 같이 처리한다.
func _fill_blank_coupled() -> void:
	var bi: int = _problem.blank_index
	if bi < 0 or bi >= _stage_groups.size():
		return
	var g: Dictionary = _stage_groups[bi]
	var color: Color = g["color"]
	var onodes: Array = g["ones_nodes"]
	var n: int = mini(int(g["value"]), _group_cap())
	var shrink := _problem.op == Problem.Op.SUB

	for i in n:
		if not _alive():
			return
		var b := _spawn_block(_group_slot(g, i), color)
		onodes.append(b)
		var tw := _new_tween()
		tw.tween_property(b, "scale", Vector2.ONE, _dur(0.16)) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "modulate:a", 1.0, _dur(0.10))

		var victim: BlockUnit = null
		if shrink:
			# 판의 마지막 칸이 같은 순간에 사라진다.
			if not _ones.is_empty():
				victim = _ones[_ones.size() - 1]
				tw.tween_property(victim, "scale", Vector2.ZERO, _dur(0.16)) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_property(victim, "modulate:a", 0.0, _dur(0.15))
		else:
			# 판의 다음 칸이 같은 순간에 생긴다.
			var m := _spawn_block(_mat_slot(_ones.size()), color)
			_ones.append(m)
			tw.tween_property(m, "scale", Vector2.ONE, _dur(0.16)) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(m, "modulate:a", 1.0, _dur(0.10))

		Audio.play_block(i, maxi(n, 1))
		await _run(tw)
		if not _alive():
			return
		# 트윈이 끝난 뒤에 지운다. 먼저 빼 두면 중간에 무대가 정리될 때 노드가 남는다.
		if victim != null:
			_ones.erase(victim)
			if is_instance_valid(victim):
				victim.queue_free()
		_set_count(_ones.size())
		await _wait(FILL_GAP)

	# 숫자 라벨은 답을 밝힐 때만 붙인다. 1차 오답에서는 블록만 남아
	# "세어 보면 답이 나온다" 가 그대로 유지된다.
	g["shown"] = _reveal
	queue_redraw()


# --- 곱셈 ------------------------------------------------------------------ #

func _demo_mul() -> void:
	var per := maxi(1, _problem.a)     # 한 묶음의 크기
	var groups := maxi(1, _problem.b)  # 묶음의 수
	_hint_text = Loc.f("groups_of", [per, groups])
	queue_redraw()

	if _problem.answer == 0:
		_begin("count")
		_set_count(0, true)
		await _wait(0.8)
		return

	var running := 0
	for g in groups:
		if not _alive():
			return
		_begin("group_%d" % g)
		var color := Palette.BLOCK_A if g % 2 == 0 else Palette.BLOCK_B
		var tw := _new_tween()
		for i in per:
			var index := g * per + i
			var to := _grid_slot(index)
			var b := _spawn_block(to + Vector2(size.x * 0.6, 0.0), color, false)
			b.scale = Vector2(0.85, 0.85)
			b.modulate.a = 0.0
			_mul.append(b)
			var d := float(i) * 0.05
			tw.tween_property(b, "position", to, _dur(0.34)) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(_dur(d))
			tw.tween_property(b, "scale", Vector2.ONE, _dur(0.32)) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(_dur(d))
			tw.tween_property(b, "modulate:a", 1.0, _dur(0.16)).set_delay(_dur(d))
			tw.tween_callback(Audio.play_block.bind(i, per)).set_delay(_dur(d))
		await _run(tw)
		if not _alive():
			return
		running += per
		# 뛰어세기: a, 2a, 3a ... 곱셈구구의 뼈대다.
		_set_count(running)
		Audio.play("count_tick", 0.9 + float(g) / float(groups) * 0.6)
		await _wait(0.28)

	await _beat()
	_begin("count")
	await _show_result()


# --------------------------------------------------------------------------- #
# 결과
# --------------------------------------------------------------------------- #

func _set_count(v: int, final: bool = false) -> void:
	if final and not _reveal:
		_count_text = "?"
		queue_redraw()
		return
	_count_text = str(v)
	count_changed.emit(v)
	queue_redraw()


## 판 아래에 최종적으로 남길 수.
##
## ★빈칸 문제(a + □ = b)에서는 **답이 아니라 b** 다. 판에 놓인 블록이 b 개이기 때문이다.
##   여기에 답(□에 들어갈 수)을 적으면, 블록은 7개인데 숫자는 4라고 적혀 있게 된다.
##   답은 문제 카드의 물음표 자리에 나타나고, 판에서는 초록 블록의 개수가 곧 답이다.
func _result_value() -> int:
	if _problem.form == Problem.Form.MISSING:
		return _problem.total
	return _problem.answer


## 시연 단계 4: 블록을 한 칸씩 놓는 과정 없이 결과 상태만 한 번에 보인다.
## 격자와 기호는 그대로 깔려 있으므로 "무슨 계산인지"는 화면에서 사라지지 않는다.
func _demo_result_only() -> void:
	for gi in _stage_groups.size():
		if not _alive():
			return
		_fill_group_instant(gi)
	await _show_result()


## 쏟는 동안 이미 숫자가 하나씩 올라갔다. 여기서 처음부터 다시 세면
## "방금 센 걸 왜 또 세지?" 가 되어 오히려 헷갈린다.
## 그래서 다시 세지 않고, 결과 숫자만 한 번 크게 강조한다.
func _show_result() -> void:
	if not _reveal:
		_count_text = "?"
		queue_redraw()
		await _wait(0.7)
		return

	_set_count(_result_value(), true)
	Audio.play("count_tick", 1.3)

	var tw := _new_tween()
	var all: Array[BlockUnit] = []
	all.append_array(_ones)
	all.append_array(_mul)
	for b in all:
		tw.tween_property(b, "highlight", 0.85, _dur(0.16))
		tw.tween_property(b, "highlight", 0.0, _dur(0.34)).set_delay(_dur(0.16))
	_count_pop = 0.0
	tw.tween_property(self, "_count_pop", 1.0, _dur(0.30)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _run(tw)
	if not _alive():
		return
	await _wait(0.45)


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if _problem == null:
		return
	if _display == Curriculum.Display.ARRAY:
		_draw_array_guides()
	else:
		_draw_row()
		_draw_mat()
	_draw_labels()


## 십틀 하나를 그린다 (합산판·항 격자 공통 — 같은 언어를 써야 옮겨간다는 게 읽힌다).
func _draw_frame(rect: Rect2, tint: Color, fill_a: float, line_a: float) -> void:
	DrawUtil.fill_aa(self, DrawUtil.round_rect(rect, _u * 0.20),
			Palette.with_alpha(tint, fill_a))
	if _ten_frame:
		var line_c := Palette.with_alpha(Palette.INK_SOFT, line_a)
		for c in range(1, FRAME_COLS):
			var x := rect.position.x + float(c) * _cell
			var w := maxf(1.5, _u * 0.05) if c == 3 else maxf(1.0, _u * 0.03)
			draw_line(Vector2(x, rect.position.y),
					Vector2(x, rect.position.y + rect.size.y), line_c, w, true)
		var ym := rect.position.y + _cell
		draw_line(Vector2(rect.position.x, ym),
				Vector2(rect.position.x + rect.size.x, ym), line_c,
				maxf(1.0, _u * 0.03), true)
	DrawUtil.draw_outline(self, DrawUtil.round_rect(rect, _u * 0.20),
			Palette.with_alpha(Palette.INK_SOFT, 0.45), maxf(2.0, _u * 0.055))


## '?' 가 들어가는 자리의 십틀 — 보기 버튼·물음표 상자와 같은 초록.
##
## ★화면에서 초록은 뜻이 하나여야 한다: **내가 찾아야 할 것.**
##   그래서 답이 어디에 나타나든(합산판이든 □ 항 격자든) 그 격자만 초록이고,
##   이미 아는 수가 놓이는 격자는 절대 초록이 아니다.
func _draw_answer_frame(rect: Rect2) -> void:
	_draw_frame(rect, Palette.CHOICE, 0.26, 0.30)
	DrawUtil.draw_outline(self, DrawUtil.round_rect(rect, _u * 0.20),
			Palette.with_alpha(Palette.CHOICE_DARK, 0.85), maxf(2.5, _u * 0.075))


## 이번 문제에서 '?' 가 합산판에 나타나는가.
##
## `a + b = ?` 면 합산판이 답 자리다. `a + □ = b` 면 판에 놓일 수(b)는 이미 알고 있고
## 찾는 것은 □ 쪽이라 판은 흰 판으로 두고 초록은 □ 항 격자가 가져간다.
func answer_on_mat() -> bool:
	return _problem != null and _problem.form != Problem.Form.MISSING


func _draw_row() -> void:
	if _stage_groups.is_empty():
		return
	var num_size := int(clampf(_u * 1.20, 22.0, 42.0))
	var fw := float(FRAME_COLS) * _cell
	var fh := float(FRAME_ROWS) * _cell
	for gi in _stage_groups.size():
		var g: Dictionary = _stage_groups[gi]
		var o: Vector2 = g["origin"]
		var blank := bool(g.get("blank", false))
		# 십틀 2개 = 20칸. 합산판과 같은 모양이라 옮겨간다는 게 눈으로 이어진다.
		# □ 자리는 합산판이 답 자리일 때와 **똑같은** 초록 십틀로 깐다 (_draw_answer_frame).
		for f in _group_frames:
			var fo := Vector2(o.x + float(f) * (fw + FRAME_GAP * _u), _row_bottom - fh)
			var frect := Rect2(fo, Vector2(fw, fh))
			if blank:
				_draw_answer_frame(frect)
			else:
				_draw_frame(frect, g["color"], 0.10, 0.28)
		if gi > 0 and gi <= _ops_visible and gi - 1 < _op_positions.size():
			Glyphs.draw_op(self, _problem.op,
					Vector2(_op_positions[gi - 1], _row_bottom - _cell),
					_u * 1.05, Palette.INK_SOFT, Color(0, 0, 0, 0.10))
		var label_at := Vector2(_group_center_x(g), _row_bottom + _u * 1.15)
		if bool(g["shown"]):
			Fonts.draw_centered_outlined(self, str(int(g["value"])), label_at,
					num_size, Palette.shade(g["color"], -0.35), Palette.CARD, 6)
		elif blank:
			# 아직 모르는 수. 문제 카드의 물음표와 같은 글자·같은 색이어야
			# "카드의 저 □ 가 이 격자다" 가 이어진다.
			Fonts.draw_centered_outlined(self, "?", label_at,
					num_size, Palette.CHOICE_DARK, Palette.CARD, 6)


func _draw_mat() -> void:
	var fw := float(FRAME_COLS) * _cell
	var fh := float(FRAME_ROWS) * _cell
	var green := answer_on_mat()
	# 등호는 답을 고르기 전부터 깔려 있다 (항 격자 사이의 `+` 와 같은 크기·같은 색).
	# 위 줄이 식의 왼쪽, 아래 줄이 "= 결과" — 두 줄로 옮겨 적은 식과 같은 그림이다.
	if _eq_visible:
		Glyphs.draw_equals(self, _eq_center, _u * 1.05, Palette.INK_SOFT,
				Color(0, 0, 0, 0.10))
	for f in MAT_FRAMES:
		var origin := _mat_origin + Vector2(float(f) * (fw + FRAME_GAP * _u), 0.0)
		var rect := Rect2(origin, Vector2(fw, fh))
		if green:
			_draw_answer_frame(rect)
		else:
			_draw_frame(rect, Palette.CARD, 0.62, 0.30)

	# 빈칸 문제: 결과 b 를 미리 흐릿하게 깔아 둔다.
	# 앞쪽은 이미 아는 수와 같은 색, 뒤쪽은 찾아야 할 초록 —
	# 답을 고르기 전에 "초록 칸이 몇 개지?"를 세어 볼 수 있어야 한다.
	if _ghost_total > 0:
		for slot in range(_ones.size(), mini(_ghost_total, MAT_CAP)):
			var gc := _mat_slot(slot)
			var gr := Rect2(gc - Vector2(_u, _u) * 0.5, Vector2(_u, _u))
			var tint := _term_color(_known_index()) if slot < _ghost_known \
					else _problem.blank_color()
			var pts2 := DrawUtil.round_rect(gr, _u * 0.22)
			DrawUtil.fill_aa(self, pts2, Palette.with_alpha(tint, 0.26))
			DrawUtil.draw_outline(self, pts2,
					Palette.with_alpha(Palette.shade(tint, -0.30), 0.55),
					maxf(2.0, _u * 0.06))

	if _empty_glow > 0.01:
		for slot in range(_ones.size(), mini(maxi(_ghost_total, FRAME_CAP), MAT_CAP)):
			var c := _mat_slot(slot)
			var r2 := Rect2(c - Vector2(_u, _u) * 0.5, Vector2(_u, _u))
			DrawUtil.draw_outline(self, DrawUtil.round_rect(r2, _u * 0.22),
					Palette.with_alpha(Palette.ROD_GLOW, 0.85 * _empty_glow),
					maxf(2.5, _u * 0.09))


func _draw_array_guides() -> void:
	var cols := maxi(1, _problem.a)
	var rows := maxi(1, _problem.b)
	for r in rows:
		var rect := Rect2(_grid_origin.x - _cell * 0.10,
				_grid_origin.y + float(r) * _cell + _cell * 0.06,
				float(cols) * _cell + _cell * 0.20, _cell * 0.88)
		var tint := Palette.BLOCK_A if r % 2 == 0 else Palette.BLOCK_B
		DrawUtil.fill_aa(self, DrawUtil.round_rect(rect, _cell * 0.22),
				Palette.with_alpha(tint, 0.13))


func _draw_labels() -> void:
	var count_size := int(clampf(_u * 1.5, 30.0, 58.0))
	if _count_text != "":
		var k := 1.0 + 0.28 * DrawUtil.ease_out_back(clampf(_count_pop, 0.0, 1.0))
		Fonts.draw_centered_outlined(self, _count_text, _count_center,
				int(float(count_size) * k), Palette.INK, Palette.CARD, 8)
	if _hint_text != "":
		Fonts.draw_centered(self, _hint_text,
				Vector2(size.x * 0.5, LABEL_H * 0.42),
				int(clampf(_u * 0.72, 16.0, 26.0)), Palette.INK_SOFT)
