## 블록 채우기 — 조각을 기둥에 떨어뜨려 빈 칸을 메운다.
##
## ★ 조각은 테트리스처럼 **내려가다 걸리는 곳에 선다.** 손가락으로 집어 빈 칸에
##   박아 넣는 것이 아니다. 그래서 "어느 기둥으로 떨어뜨릴까 · 무엇을 먼저
##   떨어뜨릴까" 가 문제가 된다.
##
## ★ 조작 규칙은 **하나뿐**이다:
##     손이 비었을 때 탭  -> 그 조각을 손에 든다 (트레이든 판 위든)
##     손에 들었을 때 탭  -> 탭한 **기둥**으로 조각이 떨어진다
##   트레이와 판을 구분하지 않는다. 상태는 "지금 든 조각" 하나뿐이라
##   만 4세가 잃어버릴 것이 없다. 취소 버튼도, 드래그도, 길게 누르기도 없다.
##
## ★ **모양만 맞으면 어디든 들어간다.** 예전에는 생성기 해답에 적힌 그 자리에 앉아야만
##   들어갔다. 그래서 모양이 딱 맞는 빈 자리에 제대로 넣어도 튕겨 나왔고 — 아이 눈에는
##   "맞는데 안 되는" 것이라 이 놀이에서 제일 나쁜 경험이었다. 지금 판정은 자리가
##   아니라 **가능성**이다: 떨어뜨린 자리에 앉혀도 남은 조각으로 판을 끝까지 채울 수
##   있으면 들어간다 (`NoodGen.fits`). 해답은 계약이 아니라 "지금 계획"(`_plan`)일
##   뿐이고, 아이가 다른 길로 가면 계획을 다시 세운다 (`_refresh`).
##
## ★ 실패가 없다. 판을 못 채우게 만드는 수를 두면 그 칸들이 잠깐 흔들리고 조각은
##   손에 그대로 남는다. 시간 제한도, 점수도, 게임오버도 없다.
##   낙하도 재촉이 아니다 — 아이가 탭한 뒤에만 시작하고 FALL_SEC 안에 끝난다.
##
## ★ 판이 막다르게 끝나지 않는 이유: (1) 생성기가 "떨어뜨려서 풀리는 판"만 낸다
##   (NoodGen.pick_top), (2) 판을 못 채우게 되는 수는 애초에 안 들어간다
##   (NoodGen.fits), (3) 그래도 판 위의 조각을 도로 들 수 있고, 그러다 구멍이
##   묻히면 힌트가 **들어낼 조각**을 가리킨다 (_lift_hint). 셋 다 있어야 한다.
extends Control

const W := 1280.0
const H := 800.0

const BG := Look.BG
const INK := Look.INK
const INK_SOFT := Look.INK_SOFT
const CELL_EMPTY := Color("e2ded6")
const CELL_LINE := Color("cdc7bc")
const GHOST_OK := Color(1, 1, 1, 0.55)
## ★ "여기엔 못 놓아"를 말하는 색. 어떤 조각 색과도 같으면 안 된다 —
##   예전에는 조각 s4 와 똑같은 색이라, 아이 눈에 "안 된다"가 "조각이 하나 더 있다"로 보였다.
const GHOST_NO := Color("9a938c")
const TRAY_BG := Color("eae7df")
## 이미 채워져 있어 아이가 손댈 수 없는 칸 = **벽**.
## ★ 미리 놓인 조각을 제 색으로 그리면 "내가 넣은 조각"과 구분이 안 가서, 아직 남은
##   구멍이 어디인지가 한눈에 안 들어온다. 그래서 색을 통째로 뺀다.
##   빈 칸(밝은 베이지)과도, 가장 어두운 조각(t4 보라 · p5 자주)과도 확실히 갈리도록
##   **거의 검정**에 가깝게 잡는다. 색은 Look 에 있다 (게임이 색을 짓지 않는다).
const WALL := Look.WALL
const WALL_LINE := Look.WALL_LINE
## 힌트 강조. 갇힌 판에서는 이 강조가 **유일한 탈출 안내**라 반드시 보여야 한다.
## ★ 흰색도 금색도 쓰면 안 된다 — 빈 칸이 이미 밝은 베이지(e2ded6)라 대비가
##   1.1:1 밖에 안 나와서 사실상 안 보인다. 그래서 **테두리는 짙은 글자색**으로 긋고
##   (빈 칸에서도 조각 위에서도 보인다) 안쪽만 강조색으로 물들인다.
const HINT_LINE := Look.INK
const HINT_FILL := Look.ACCENT

## 손가락이 큰 아이 기준 칸 하한. 이 아래로는 격자를 안 키운다.
const CELL_MIN := 92.0

## 낙하 시간. **재촉 연출이 되면 안 된다** — "떨어졌다"가 보이기만 하면 되므로
## 짧게 잡는다. 길게 잡으면 조각을 여러 개 놓는 동안 기다림이 누적된다.
const FALL_SEC := 0.18

var stage := 1
var dev_mode := false

var _n := 5
var _puzzle: Dictionary = {}
## 격자: 각 칸에 놓인 조각의 배열 인덱스 (-1 = 빈 칸)
var _grid: PackedInt32Array = PackedInt32Array()
## 판 위의 조각들: {"pi", "cells", "fixed"}
var _board: Array = []
## 트레이(아직 안 놓은 조각): {"pi", "rot"(지금 보이는 모양)}
## ★ "정답 자리"를 들고 있지 않다. 자리는 정해져 있지 않다 — 계획은 _plan 에 있다.
var _tray: Array = []
## 손에 든 것: {"from": "tray"|"board", "idx": int}
var _held: Dictionary = {}
## 지금 떨어지고 있는 조각. 비어 있지 않으면 탭을 받지 않는다.
##   {"pi", "shape", "cells"(착지 자리), "dx", "dy", "idx"(트레이 자리), "t", "ok"}
var _falling: Dictionary = {}
var _hover := Vector2i(-1, -1)
var _shake: Array = []          # [{cells, t}]
var _t := 0.0
var _done := false
var _busy := false
var _misses := 0
var _hint_cells: Array = []
var _idle := 0.0
## 지금 계획 — _tray 와 같은 길이. _plan[i] = i 번 조각이 갈 자리(칸 배열), 없으면 [].
## ★ 정답이 아니라 **한 가지 답**이다. 아이가 다른 자리에 넣으면 _refresh() 가 다시 세운다.
##   안내 점·힌트가 이걸 그린다. 그래서 안내는 늘 지금 판에 대해 참이다.
var _plan: Array = []
## _tray 와 같은 길이. "지금 이 조각을 놓을 자리가 하나라도 있는가"를 미리 세어 둔 것.
var _can_place: Array = []
## 지금 판을 끝까지 채울 수 있는가 (되들다가 구멍이 묻히면 false 가 된다).
var _plan_ok := false
## **확실히** 갇혔는가 (계획이 없고, 탐색이 포기해서 모르는 것도 아니다).
## 이때만 "판 위의 조각을 들어내라"고 안내한다.
var _stuck := false
## 계획의 **첫 수** — 지금 떨어뜨리면 _plan 에 적힌 그 자리에 앉는 조각. 힌트가 이걸 쓴다.
var _plan_next := -1
## 아직 차례가 아닌 조각을 눌렀을 때의 흔들림 (트레이 자리 / 남은 세기)
var _wobble_i := -1
var _wobble_t := 0.0

var _axes: Dictionary = {}
## 계획 탐색이 **한 판 내내 같이 쓰는 주머니** (막힌 판 기억).
## ★ 같은 판을 자리마다 수십 번 물어보므로, 이게 없으면 어려운 판에서 같은 계산을
##   계속 다시 하다가 탐색 한도에 걸린다. 판이 바뀔 때 새로 판다.
var _bag: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	randomize()
	stage = maxi(1, int(_state().get("best_stage", 1)))
	_build()


func _process(delta: float) -> void:
	_t += delta
	if not _falling.is_empty():
		_falling["t"] = float(_falling["t"]) + delta / FALL_SEC
		if float(_falling["t"]) >= 1.0:
			_land()
	if not _done and not _busy and _falling.is_empty():
		_idle += delta
		var wait := float(_axes.get("hint_sec", 16.0))
		if _idle > wait:
			_idle = wait * 0.5
			_show_hint()
	_wobble_t = maxf(0.0, _wobble_t - delta * 3.0)
	for s in _shake:
		s["t"] = maxf(0.0, float(s["t"]) - delta * 3.0)
	_shake = _shake.filter(func(s): return float(s["t"]) > 0.0)
	queue_redraw()


# --------------------------------------------------------------------------- #
# 판 만들기
# --------------------------------------------------------------------------- #

## 이 프로필의 블록 채우기 기록. 없으면 만들어서 준다.
func _state() -> Dictionary:
	var p := Shell.profile()
	if not p.has("kanoodle"):
		p["kanoodle"] = {"best_stage": 1, "skill": 0, "cleared": 0}
	return p["kanoodle"]


func effective_stage() -> int:
	return clampi(stage + int(_state().get("skill", 0)), 1, 999)


func _build() -> void:
	var e := effective_stage()
	var t := Shell.tuning()
	_axes = NoodGen.axes(e, t)
	_axes["hint_sec"] = float(t.get("nood_hint_sec", 16.0))
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	_puzzle = {}
	# 못 만들거나 첫 계획이 안 서면 한 단계씩 쉽게 해서 다시 —
	# 아이 앞에 멈춘 판이 뜨는 일은 없어야 한다.
	var cfg := _axes.duplicate()
	for retry in 4:
		_puzzle = NoodGen.make(cfg, rng)
		if not _puzzle.is_empty():
			_setup()
			if _plan_ok:
				return
		cfg["place"] = maxi(1, int(cfg["place"]) - 1)
		cfg["n"] = maxi(4, int(cfg["n"]) - 1)
	# 최후의 보루: 4x4 를 가장 단순한 조각들로
	for retry in 4:
		_puzzle = NoodGen.make({"n": 4, "place": 2, "pieces": ["o4", "i2", "i3", "l3"]}, rng)
		if not _puzzle.is_empty():
			break
	_setup()


## 만들어진 _puzzle 을 판에 깐다.
func _setup() -> void:
	if _puzzle.is_empty():
		# 생성기가 4x4 최단순 설정에서도 실패했다는 뜻이다 — 있어서는 안 되는 일이라
		# 조용히 넘어가지 않는다 (판이 그대로 남아 아이 화면은 멈춘 것처럼 보인다).
		push_error("블록 채우기: 판을 하나도 못 만들었습니다")
		# ★ 잠금은 반드시 풀어 둔다. _next_stage() 가 _busy 를 켜 놓고 여기로 오는데,
		#   여기서 그냥 나가면 "집으로"까지 안 눌리는 화면이 남는다.
		_busy = false
		_done = false
		return
	_n = int(_puzzle["n"])
	_bag = NoodGen.new_bag()
	_grid = PackedInt32Array()
	_grid.resize(_n * _n)
	_grid.fill(-1)
	_board.clear()
	_tray.clear()
	_plan.clear()
	_can_place.clear()
	_plan_ok = false
	_stuck = false
	_held = {}
	_falling = {}
	_done = false
	_busy = false
	_misses = 0
	_idle = 0.0
	_wobble_i = -1
	_wobble_t = 0.0
	_hint_cells.clear()

	var sol: Array = _puzzle["solution"]
	for i in (_puzzle["fixed"] as Array):
		var e2: Dictionary = sol[int(i)]
		_put_on_board(int(e2["pi"]), e2["cells"], true)
	for item in (_puzzle["tray"] as Array):
		var cells: Array = (item["cells"] as Array)
		var shape := _shape_of(cells)
		if bool(_puzzle.get("rotate", false)):
			# 트레이에 아무 방향으로 내놓는다 — 아이가 돌려서 맞춰야 한다.
			var rots: Array = NoodPieces.rotations(int(item["pi"]))
			shape = rots[randi() % rots.size()]
		_tray.append({"pi": int(item["pi"]), "rot": shape})
		# 생성기의 해답을 **첫 계획**으로 깔아 둔다. 정답이 아니라 밑그림이다 —
		# 아이가 다른 자리에 넣는 순간 _refresh() 가 다시 세운다.
		_plan.append(cells.duplicate())

	_refresh()


func _put_on_board(pi: int, cells: Array, fixed: bool) -> void:
	var idx := _board.size()
	_board.append({"pi": pi, "cells": (cells as Array).duplicate(), "fixed": fixed})
	for c in cells:
		_grid[(c as Vector2i).y * _n + (c as Vector2i).x] = idx


## 절대 좌표 배열 -> (0,0) 기준 모양.
## ★ 정렬까지 해서 늘 같은 순서로 나온다 — 계획 탐색이 모양 자체를 열쇠로 쓰기 때문에
##   같은 모양이 두 가지 순서로 오면 쌍둥이를 못 알아본다.
func _shape_of(cells: Array) -> Array:
	return NoodPieces.normalize(cells)


# --------------------------------------------------------------------------- #
# 좌표
# --------------------------------------------------------------------------- #

func _scale() -> float:
	return minf(size.x / W, size.y / H)


func _origin() -> Vector2:
	var s := _scale()
	return Vector2((size.x - W * s) * 0.5, (size.y - H * s) * 0.5)


func _to_local(p: Vector2) -> Vector2:
	var s := _scale()
	return Vector2.ZERO if s <= 0.0 else (p - _origin()) / s


## 격자 칸 크기. 왼쪽 판 영역 안에서 최대한 크게, 단 CELL_MIN 아래로는 안 간다.
func _cell() -> float:
	return maxf(CELL_MIN, minf(600.0 / float(_n), 132.0))


func _board_rect() -> Rect2:
	var c := _cell()
	var side := c * float(_n)
	return Rect2(70.0, (H - side) * 0.5 + 18.0, side, side)


func _tray_rect() -> Rect2:
	var br := _board_rect()
	var x := br.position.x + br.size.x + 46.0
	# 트레이 높이는 조각 수에 맞춘다 — 텅 빈 상자는 "여기 뭐가 없어졌나" 로 읽힌다.
	var rows := int(ceil(float(maxi(1, _tray.size())) / 2.0))
	var h := clampf(float(rows) * 176.0, 200.0, 520.0)
	return Rect2(x, (H - h) * 0.5 - 30.0, W - x - 60.0, h)


## 트레이 조각 i 의 자리 (칸 크기는 판보다 작다)
func _tray_slot(i: int) -> Rect2:
	var r := _tray_rect()
	var n := maxi(1, _tray.size())
	var rows := int(ceil(float(n) / 2.0))
	var cw := r.size.x / 2.0
	var ch := r.size.y / float(maxi(1, rows))
	return Rect2(r.position.x + float(i % 2) * cw, r.position.y + float(i / 2) * ch, cw, ch)


func _tray_cell() -> float:
	var r := _tray_rect()
	var rows := int(ceil(float(maxi(1, _tray.size())) / 2.0))
	return clampf(minf(r.size.x / 2.0, r.size.y / float(maxi(1, rows))) / 3.4, 26.0, 66.0)


func _cell_at(p: Vector2) -> Vector2i:
	var br := _board_rect()
	var c := _cell()
	if not br.has_point(p):
		return Vector2i(-1, -1)
	return Vector2i(int((p.x - br.position.x) / c), int((p.y - br.position.y) / c))


func _rotate_rect() -> Rect2:
	var r := _tray_rect()
	return Rect2(r.position.x, r.position.y + r.size.y + 16.0, r.size.x * 0.48, 96.0)


func _home_rect() -> Rect2:
	var r := _tray_rect()
	return Rect2(r.position.x + r.size.x * 0.52, r.position.y + r.size.y + 16.0, r.size.x * 0.48, 96.0)


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #

func _draw() -> void:
	var s := _scale()
	var o := _origin()
	draw_set_transform(o, 0.0, Vector2(s, s))

	draw_rect(Rect2(0, 0, W, H), BG)
	_paint_header()
	_paint_board()
	_paint_tray()
	_paint_buttons()
	if _done:
		_paint_done()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if o.x > 0.5:
		draw_rect(Rect2(0, 0, o.x, size.y), BG)
		draw_rect(Rect2(size.x - o.x, 0, o.x, size.y), BG)
	if o.y > 0.5:
		draw_rect(Rect2(0, 0, size.x, o.y), BG)
		draw_rect(Rect2(0, size.y - o.y, size.x, o.y), BG)


func _paint_header() -> void:
	var left := 0 if _done else _tray.size()
	_text("%d번째 판" % stage, Vector2(70.0, 42.0), 30, INK)
	var msg := "다 채웠어요!" if _done else ("%d조각 남았어요" % left)
	_text(msg, Vector2(70.0, 78.0), 22, INK_SOFT)


func _paint_board() -> void:
	var br := _board_rect()
	var c := _cell()
	var guide := int(_puzzle.get("guide", 0))

	# 바탕 칸
	for y in _n:
		for x in _n:
			var r := Rect2(br.position + Vector2(float(x) * c, float(y) * c), Vector2(c, c))
			draw_rect(r.grow(-3.0), CELL_EMPTY)

	# 안내 — 단계가 오를수록 덜 알려 준다 (난이도 축 B)
	#
	# ★ 생성기 해답이 아니라 **지금 계획**(_plan)을 그린다. 모양만 맞으면 어디든
	#   들어가는 놀이라, 해답을 그리면 아이가 다른 자리에 넣은 순간 안내가 거짓말이 된다.
	if guide == 0:
		# ★ 칸을 통째로 칠하지 않는다. 옅게라도 칠하면 "이미 놓인 조각"과 헷갈려서
		#   아이 눈에 다 채워진 판으로 보인다. 가운데에 **작은 점**만 찍는다 —
		#   "여기에 이 색 조각이 온다"는 힌트이지 조각 자체가 아니다.
		for i in _plan.size():
			var pcol := Color(NoodPieces.color_of(int(_tray[i]["pi"])), 0.55)
			for cc: Vector2i in (_plan[i] as Array):
				if _grid[cc.y * _n + cc.x] >= 0:
					continue
				var mid := br.position + Vector2((float(cc.x) + 0.5) * c,
						(float(cc.y) + 0.5) * c)
				draw_circle(mid, c * 0.17, pcol)
	elif guide == 1:
		# 조각 경계선만.
		# ★ 격자선보다 **확실히 진하게** 그린다. 예전에는 격자선과 같은 색이라 눈에
		#   아예 안 보였고, 그래서 안내 1단계가 사실상 2단계(안내 없음)와 같았다 —
		#   난이도 축 하나가 조용히 사라져 있었다.
		for i in _plan.size():
			_outline_cells(br, c, _plan[i], Color(INK_SOFT, 0.75), 5.0)

	# 이미 채워져 있던 칸 = **벽**.
	# ★ 미리 놓인 조각을 제 색으로 그리면 "내가 넣은 조각"과 구분이 안 가서, 아직 남은
	#   구멍이 어디인지가 한눈에 안 들어온다. 그래서 색을 빼고 통째로 한 덩어리로
	#   그린다 — 조각 경계도 안 그린다. 벽에는 경계가 필요 없고, 경계가 있으면
	#   그것도 "채워야 할 모양"으로 읽힌다.
	var wall: Array = []
	for b: Dictionary in _board:
		if bool(b["fixed"]):
			wall.append_array(b["cells"] as Array)
	for cc: Vector2i in wall:
		draw_rect(Rect2(br.position + Vector2(float(cc.x) * c, float(cc.y) * c),
				Vector2(c, c)).grow(-3.0), WALL)
	_outline_cells(br, c, wall, WALL_LINE, 5.0)

	# 아이가 놓은 조각 — 색 그대로. 색이 남아 있다는 것이 "다시 들 수 있다"는 뜻이다.
	for b: Dictionary in _board:
		if bool(b["fixed"]):
			continue
		var col: Color = NoodPieces.color_of(int(b["pi"]))
		for cc: Vector2i in (b["cells"] as Array):
			draw_rect(Rect2(br.position + Vector2(float(cc.x) * c, float(cc.y) * c),
					Vector2(c, c)).grow(-3.0), col)
		_outline_cells(br, c, b["cells"], col.darkened(0.35), 5.0)

	# 격자선
	for i in _n + 1:
		var t := float(i) * c
		draw_line(br.position + Vector2(t, 0), br.position + Vector2(t, br.size.y), CELL_LINE, 2.0)
		draw_line(br.position + Vector2(0, t), br.position + Vector2(br.size.x, t), CELL_LINE, 2.0)
	_outline_rect(br, INK_SOFT, 4.0)

	# 힌트 — 자리 하나가 숨 쉰다.
	# ★ 그 위에 **누를 칸**(조각의 기준칸)을 따로 찍는다. 세로로는 아무 데나 눌러도 되지만
	#   가로 기둥은 정해져 있어서, 강조된 칸 아무 데나 누르면 조각이 옆으로 밀려 앉는다 —
	#   시킨 대로 했는데 튕기는 것이 되고, 그게 힌트가 거짓말하는 최악의 경우다.
	if not _hint_cells.is_empty():
		var pulse := 0.5 + 0.5 * absf(sin(_t * 2.4))
		for cc: Vector2i in _hint_cells:
			var r := Rect2(br.position + Vector2(float(cc.x) * c, float(cc.y) * c),
					Vector2(c, c))
			draw_rect(r.grow(-6.0), Color(HINT_FILL, 0.16 + 0.16 * pulse))
		_outline_cells(br, c, _hint_cells, Color(HINT_LINE, 0.45 + 0.45 * pulse), 8.0)
		var an := _anchor_of(_hint_cells)
		var mid := br.position + Vector2((float(an.x) + 0.5) * c, (float(an.y) + 0.5) * c)
		var rad := c * 0.19 * (0.92 + 0.08 * pulse)
		draw_circle(mid, rad, Color(HINT_LINE, 0.35 + 0.35 * pulse))
		draw_circle(mid, rad * 0.68, Color(HINT_FILL, 0.6 + 0.4 * pulse))

	# 안 맞는 자리에 놓으려 했을 때 — 벌이 아니라 흔들림
	for sh in _shake:
		var k := float(sh["t"])
		for cc in (sh["cells"] as Array):
			var off := Vector2(sin(_t * 40.0) * 5.0 * k, 0)
			var r := Rect2(br.position + Vector2(float((cc as Vector2i).x) * c,
					float((cc as Vector2i).y) * c) + off, Vector2(c, c))
			draw_rect(r.grow(-4.0), Color(GHOST_NO, 0.35 * k))

	# 손에 든 조각이 이 기둥에서 **어디에 앉는지** (테트리스의 그림자).
	# 맞는 자리인지 아닌지는 알려 주지 않는다 — 그걸 알려 주면 퍼즐이 사라진다.
	if not _held.is_empty() and _falling.is_empty() and _hover.x >= 0:
		var shape := _held_shape()
		var ga := _anchor_of(shape)
		var gdx := _hover.x - ga.x
		var gdy := NoodGen.drop_dy(_grid, _n, shape, gdx)
		if gdy != NoodGen.NO_DROP:
			for cc in shape:
				var gx: int = (cc as Vector2i).x + gdx
				var gy: int = (cc as Vector2i).y + gdy
				var r := Rect2(br.position + Vector2(float(gx) * c, float(gy) * c),
						Vector2(c, c))
				draw_rect(r.grow(-6.0), GHOST_OK)

	# 떨어지는 중인 조각. 판 위(y<0)에서 시작해 착지 자리까지 내려온다.
	if not _falling.is_empty():
		var fs: Array = _falling["shape"]
		var fdx := int(_falling["dx"])
		var ftop := 0
		for cc in fs:
			ftop = maxi(ftop, (cc as Vector2i).y)
		# 살짝 가속시킨다 — 등속으로 내리면 "끌려간다"로 보이고 툭 떨어지지 않는다
		var fk := clampf(float(_falling["t"]), 0.0, 1.0)
		var fy := lerpf(float(-ftop - 1), float(_falling["dy"]), fk * fk)
		var fcol: Color = NoodPieces.color_of(int(_falling["pi"]))
		for cc in fs:
			var cy := float((cc as Vector2i).y) + fy
			if cy + 1.0 <= 0.0:
				continue                    # 아직 판 위 — 안 보인다
			var r := Rect2(br.position + Vector2(float((cc as Vector2i).x + fdx) * c, cy * c),
					Vector2(c, c))
			if cy < 0.0:
				# 판 윗선에 걸쳐 있다 — 위로 삐져나온 만큼 잘라 낸다
				r.position.y = br.position.y
				r.size.y = (cy + 1.0) * c
			var rr := r.grow(-3.0)
			if rr.size.x > 1.0 and rr.size.y > 1.0:
				draw_rect(rr, fcol)


func _paint_tray() -> void:
	var r := _tray_rect()
	_round_rect(r.grow(14.0), 24.0, TRAY_BG)
	var tc := _tray_cell()
	for i in _tray.size():
		# 떨어지는 중인 조각은 트레이에 겹쳐 그리지 않는다 — 한 조각이 둘로 보인다.
		if not _falling.is_empty() and int(_falling["idx"]) == i:
			continue
		var slot := _tray_slot(i)
		var shape: Array = _tray[i]["rot"]
		var ext := NoodPieces.extent(shape)
		var lift := 0.0
		if not _held.is_empty() and String(_held.get("from", "")) == "tray" and int(_held["idx"]) == i:
			# 든 조각은 사라지지 않는다 — 떠오른다. 사라지면 아이는 "없어졌다"로 읽는다.
			lift = 10.0 + sin(_t * 6.0) * 2.0
		var o := slot.position + slot.size * 0.5 - Vector2(float(ext.x), float(ext.y)) * tc * 0.5
		o.y -= lift
		if i == _wobble_i and _wobble_t > 0.0:
			o.x += sin(_t * 40.0) * 6.0 * _wobble_t
		var col: Color = NoodPieces.color_of(int(_tray[i]["pi"]))
		# ★ 손에 든 조각은 흐리게 만들지 않는다. "떠 있다(들었다)"와 "쉬고 있다(아직 안 된다)"를
		#   한 조각에 동시에 그리면 아이에게는 그냥 뜻 모를 상태가 된다.
		if lift <= 0.0 and not _ready_now(i):
			# 아직 차례가 아닌 조각은 쉬고 있다. 지우지는 않는다 — 앞으로 뭐가 남았는지
			# 보이는 편이 낫고, 사라지면 아이는 "없어졌다"로 읽는다.
			col = Color(col, 0.34)
		for cc in shape:
			draw_rect(Rect2(o + Vector2(float((cc as Vector2i).x) * tc,
					float((cc as Vector2i).y) * tc), Vector2(tc, tc)).grow(-2.0), col)
		if lift > 0.0:
			_outline_cells_at(o, tc, shape, INK, 4.0)


func _paint_buttons() -> void:
	if bool(_puzzle.get("rotate", false)):
		var rr := _rotate_rect()
		_round_rect(rr, 22.0, Color("cfe0ee"))
		_text_centered("돌리기", rr.position + Vector2(rr.size.x * 0.5, 34.0), 30, INK)
	var hr := _home_rect()
	_round_rect(hr, 22.0, Color("ffe0e6"))
	_text_centered("집으로", hr.position + Vector2(hr.size.x * 0.5, 34.0), 30, INK)


func _paint_done() -> void:
	var box := Rect2(W * 0.5 - 250.0, 300.0, 500.0, 150.0)
	_round_rect(box, 34.0, Color("fdf8ee"))
	_outline_rect(box, Color("f2c74a"), 6.0)
	_text_centered("다 채웠어요!", Vector2(W * 0.5, box.position.y + 62.0), 52, INK)
	_text_centered("다음 판으로 가요", Vector2(W * 0.5, box.position.y + 112.0), 24, INK_SOFT)
	# 두리가 같이 만세한다 (다섯 게임이 같은 순간에 같은 표정을 짓는다)
	Look.draw_duri(self, "cheer", Vector2(box.position.x - 30.0, box.end.y + 190.0), 210.0)


# --------------------------------------------------------------------------- #
# 입력 — 규칙은 하나뿐이다
# --------------------------------------------------------------------------- #

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _held.is_empty():
		_hover = _cell_at(_to_local((event as InputEventMouseMotion).position))
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# 떨어지는 동안은 탭을 먹지 않는다 — 연타로 조각이 겹쳐 떨어지면 판이 어긋난다.
	if _busy or not _falling.is_empty():
		return
	_on_tap(_to_local(mb.position))


func _on_tap(p: Vector2) -> void:
	_idle = 0.0
	# ★ 갇힌 판에서는 안내를 지우지 않는다. 지우면 두드릴수록 탈출구가 사라진다.
	if not _stuck:
		_hint_cells.clear()

	if _done:
		_next_stage()
		return

	if _home_rect().grow(10.0).has_point(p):
		_go_home()
		return
	if bool(_puzzle.get("rotate", false)) and _rotate_rect().grow(10.0).has_point(p):
		_rotate_held()
		return

	# 트레이 조각을 눌렀나
	for i in _tray.size():
		if _tray_slot(i).has_point(p):
			if not _held.is_empty() and String(_held.get("from", "")) == "tray" \
					and int(_held["idx"]) == i:
				_held = {}          # 같은 걸 다시 누르면 내려놓는다
				return
			if not _ready_now(i):
				# ★ 지금은 이 조각이 들어갈 자리가 한 곳도 없다 (먼저 떨어뜨리면 판을
				#   못 채우게 된다). "안 돼" 대신 살짝 흔들어서 "조금 있다가"로 읽히게 한다.
				_wobble_i = i
				_wobble_t = 1.0
				return
			_held = {"from": "tray", "idx": i}
			return

	var cell := _cell_at(p)
	if cell.x < 0:
		_held = {}                  # 판 밖을 누르면 손을 비운다
		return

	if _held.is_empty():
		var at := _grid[cell.y * _n + cell.x]
		if at >= 0:
			# 놓인 조각을 눌렀다 -> 도로 든다 (미리 놓인 벽은 못 든다).
			# ★ 이 되돌리기는 판정과 별개로 늘 열려 있다. 아이는 "여기 말고 저기"를
			#   해 보고 싶어 하고, 그걸 막으면 놀이가 아니라 시험이 된다.
			#   ⚠ 이 길로는 갇힐 수 있다 — 위에 조각이 얹힌 것을 들어내면 그 자리가
			#   묻힌 구멍이 된다. 그때는 힌트가 들어낼 조각을 가리킨다 (_lift_hint).
			var b: Dictionary = _board[at]
			if bool(b["fixed"]):
				_shake.append({"cells": (b["cells"] as Array).duplicate(), "t": 1.0})
				return
			_pick_up(at)
			return
		# 손이 비었는데 빈 칸을 눌렀다. 어린 아이는 먼저 판을 두드린다 —
		# 지금 차례인 조각을 자동으로 들려 주면 "판만 두드려도" 놀이가 굴러간다.
		if bool(Shell.tune("nood_autopick", false)):
			# ★ 두드린 기둥에 **정말 들어가는** 조각을 고른다. 아무거나 집어서
			#   떨어뜨리면 판만 두드리는 아이에게는 흔들림만 돌아온다.
			for i in _tray.size():
				if not _ready_now(i):
					continue
				var lz := _landing(_tray[i]["rot"], cell.x)
				if lz.is_empty() or not _fits(i, lz["cells"]):
					continue
				_held = {"from": "tray", "idx": i}
				_hover = cell
				_start_drop(cell.x)
				return
			# 그 기둥에 맞는 게 없으면 지금 놓을 수 있는 조각을 **들어만** 준다.
			# 아이가 다른 기둥을 두드리면 된다 — 헛방을 만들어 주는 것보다 낫다.
			for i in _tray.size():
				if _ready_now(i):
					_held = {"from": "tray", "idx": i}
					return
		return

	# 손에 들었다 -> 이 **기둥**으로 떨어뜨린다.
	# 세로로 어디를 눌렀는지는 상관없다 — 어차피 중력이 자리를 정한다.
	_hover = cell
	_start_drop(cell.x)


func _held_shape() -> Array:
	if _held.is_empty():
		return []
	if String(_held["from"]) == "tray":
		return _tray[int(_held["idx"])]["rot"]
	return _shape_of(_board[int(_held["idx"])]["cells"])


## 조각의 **기준칸** — 왼쪽 위에서 처음 나오는 "실제로 채워진" 칸.
##
## ★ 조각의 네모난 테두리 좌상단이 아니다. ㄴ 자 조각처럼 좌상단이 비어 있는 모양에서
##   테두리를 기준으로 잡으면, 아이가 "조각이 없는 허공"을 눌러야 놓인다.
##   누른 칸에 조각의 첫 칸이 온다 — 그게 아이가 예상하는 것이다.
func _anchor_of(shape: Array) -> Vector2i:
	var a: Vector2i = shape[0]
	for cc in shape:
		var v: Vector2i = cc
		if v.y < a.y or (v.y == a.y and v.x < a.x):
			a = v
	return a


# --------------------------------------------------------------------------- #
# 계획 — "여기 놓아도 판을 끝까지 채울 수 있는가"
# --------------------------------------------------------------------------- #

## 각 트레이 조각이 **아이가 실제로 만들 수 있는** 모양들.
##
## ★ 돌리기 버튼이 없는 판에서는 지금 보이는 모양 하나뿐이다. 여기서 모든 회전을
##   허용해 버리면 "계획은 있는데 아이는 그 모양을 못 만드는" 판이 나온다 —
##   그러면 조각이 트레이에서 영영 안 빠진다.
func _shapes() -> Array:
	var rotate := bool(_puzzle.get("rotate", false))
	var out: Array = []
	for it: Dictionary in _tray:
		out.append(NoodPieces.rotations(int(it["pi"])) if rotate
				else [_shape_of(it["rot"])])
	return out


## 이 모양을 col 기둥으로 떨어뜨리면 앉을 자리. 못 들어가면 {}.
## 반환: {"cells", "dx", "dy"} — 누른 기둥에는 조각의 **기준칸**이 온다 (_anchor_of).
func _landing(shape: Array, col: int) -> Dictionary:
	if shape.is_empty():
		return {}
	var dx := col - _anchor_of(shape).x
	var dy := NoodGen.drop_dy(_grid, _n, shape, dx)
	if dy == NoodGen.NO_DROP:
		return {}
	var cells: Array = []
	for cc: Vector2i in shape:
		cells.append(Vector2i(cc.x + dx, cc.y + dy))
	return {"cells": cells, "dx": dx, "dy": dy}


## 트레이 조각 i 를 cells 에 앉혀도 남은 조각으로 판을 끝까지 채울 수 있는가.
func _fits(i: int, cells: Array) -> bool:
	return NoodGen.fits(_grid, _n, _shapes(), i, cells, _bag)


## 판이 바뀌었다 — 계획과 "지금 놓을 수 있는 조각"을 다시 센다.
##
## ★ 판이 바뀌는 순간(놓기 · 되들기 · 새 판)에만 부른다. 매 프레임 부르면 안 된다.
## ★ 지금 계획을 **먼저 시도할 자리**로 넘긴다. 그래야 아이가 계획대로 놓는 동안
##   나머지 안내 점이 가만히 있는다 — 이유 없이 색이 바뀌면 그게 헷갈림이 된다.
func _refresh() -> void:
	var res := NoodGen.survey(_grid, _n, _shapes(), _plan, _bag)
	_can_place = res["ready"]
	_plan_ok = bool(res["ok"])
	# ★ "못 채운다"와 "탐색이 포기했다(capped)"는 다르다. 포기한 것을 갇힌 것으로
	#   뭉개면 멀쩡한 판에서 아이에게 "조각을 들어내라"고 시키게 된다.
	_stuck = not _plan_ok and not bool(res["capped"])
	if _plan_ok:
		_plan = res["at"]
		var order: Array = res["order"]
		# ★ 계획의 **첫 수**를 따로 들고 있어야 한다. _plan[i] 는 "다 놓고 났을 때
		#   i 가 있을 자리"라, 차례가 뒤인 조각은 지금 떨어뜨리면 더 아래로 간다.
		#   힌트가 그걸 가리키면 시킨 대로 했는데 안 되는 최악의 경우가 된다.
		_plan_next = int(order[0]) if not order.is_empty() else -1
		return
	# 계획이 없다. 안내를 지운다 — 거짓말하느니 침묵이 낫다.
	_plan = []
	for i in _tray.size():
		_plan.append([])
	_plan_next = -1
	if not _stuck:
		_hint_cells.clear()
		return
	# ★ 확실히 갇혔다 (되들다가 구멍이 조각 밑에 묻혔다). 빠져나가는 길을
	#   **기다리지 말고 바로** 보여 준다. 이 상태에서 안내를 기다림(idle)에 걸어 두면,
	#   답답해서 자꾸 두드리는 아이에게는 영영 안 나온다 — 탭마다 기다림이 0으로
	#   돌아가기 때문이다. 그러면 유일한 탈출구가 닫힌 것과 같다.
	var lift := _lift_hint()
	_hint_cells = ((_board[lift]["cells"] as Array).duplicate() if lift >= 0 else [])


## 든 조각을 col 기둥으로 떨어뜨리기 시작한다. 실제 결과는 _land() 가 정한다.
##
## ★ 누른 기둥에는 조각의 **기준칸**이 온다 (_anchor_of). 조각을 감싸는 네모의
##   좌상단이 아니다 — ㄴ 자 조각에서 그러면 아이가 허공을 눌러야 한다.
func _start_drop(col: int) -> void:
	if not _falling.is_empty() or _held.is_empty():
		return
	var shape := _held_shape()
	if shape.is_empty():
		return
	var idx := int(_held["idx"])
	var lz := _landing(shape, col)
	if lz.is_empty():
		# 이 기둥으로는 아예 못 들어간다 (조각이 판 옆으로 삐져나가거나 이미 꽉 찼다).
		# 떨어뜨리는 흉내조차 안 낸다 — 기둥만 흔들어서 "여기는 아니야"를 말한다.
		_shake.append({"cells": _column_cells(col), "t": 1.0})
		_misses += 1
		return
	_falling = {
		"pi": int(_tray[idx]["pi"]),
		"shape": shape,
		"cells": lz["cells"],
		"dx": int(lz["dx"]),
		"dy": int(lz["dy"]),
		"idx": idx,
		"t": 0.0,
		# ★ 이 한 줄이 이 놀이의 판정 전부다. "해답에 적힌 자리인가"가 아니라
		#   **"여기 앉혀도 남은 조각으로 판을 끝까지 채울 수 있는가"** 를 본다.
		#   그래서 모양만 맞으면 어디든 들어가고, 그러면서도 막다른 판은 안 생긴다.
		"ok": _fits(idx, lz["cells"]),
	}
	_idle = 0.0


## 낙하가 끝났다. 판을 끝까지 채울 수 있는 자리면 붙고, 아니면 손에 그대로 돌아온다.
func _land() -> void:
	var f := _falling
	_falling = {}
	var cells: Array = f["cells"]
	if not bool(f["ok"]):
		# ★ 벌이 아니다. 앉았던 칸이 잠깐 흔들리고 조각은 손에 그대로 남는다.
		#   판은 손대지 않는다 — 그래서 아이가 어떻게 두드려도 판이 엉키지 않는다.
		_shake.append({"cells": (cells as Array).duplicate(), "t": 1.0})
		_misses += 1
		return
	var idx := int(f["idx"])
	var pi := int(_tray[idx]["pi"])
	_tray.remove_at(idx)
	_plan.remove_at(idx)
	_wobble_i = -1                  # 자리가 밀리므로 엉뚱한 조각이 흔들리지 않게
	_put_on_board(pi, cells, false)
	_held = {}
	_hover = Vector2i(-1, -1)
	_refresh()
	if _tray.is_empty():
		_finish()


func _column_cells(col: int) -> Array:
	var out: Array = []
	if col < 0 or col >= _n:
		return out
	for y in _n:
		out.append(Vector2i(col, y))
	return out


## 트레이 조각 i 를 지금 떨어뜨려도 되는가.
##
## ★ 기준은 **"이 조각을 지금 놓을 수 있는 자리가 하나라도 있는가"** 다.
##   자리가 정해져 있지 않으니 "제자리에 앉는가"로는 물을 수 없고, 예전의 가둠 표
##   (해답 기준으로 누가 누구를 가두는지)도 자유 배치에서는 의미가 없다.
##
##   ★ **"제자리에 앉는가"로 판단하면 안 된다**는 옛 교훈은 그대로 유효하다 —
##     앉기는 잘 앉는데 다른 조각을 가두는 경우가 있었다 (여행 검사 10번째에서 물렸다).
##     지금은 그것까지 포함해서 "끝까지 채울 수 있는가"로 본다 (NoodGen.survey).
##
##   세는 것은 판이 바뀔 때 _refresh() 가 미리 한다. 여기서는 읽기만 한다 —
##   매 프레임 다시 세면 안 된다. 판 전체를 뒤지는 탐색이다.
func _ready_now(i: int) -> bool:
	return i >= 0 and i < _can_place.size() and bool(_can_place[i])


func _pick_up(idx: int) -> void:
	var b: Dictionary = _board[idx]
	var shape := _shape_of(b["cells"])
	_remove_board(idx)
	_tray.append({"pi": int(b["pi"]), "rot": shape})
	_plan.append([])
	_wobble_i = -1
	_held = {"from": "tray", "idx": _tray.size() - 1}
	_refresh()


func _remove_board(idx: int) -> void:
	for cc in (_board[idx]["cells"] as Array):
		_grid[(cc as Vector2i).y * _n + (cc as Vector2i).x] = -1
	_board.remove_at(idx)
	# 인덱스가 밀리므로 격자를 다시 그린다
	_grid.fill(-1)
	for i in _board.size():
		for cc in (_board[i]["cells"] as Array):
			_grid[(cc as Vector2i).y * _n + (cc as Vector2i).x] = i


func _rotate_held() -> void:
	if _held.is_empty() or String(_held["from"]) != "tray":
		return
	if not bool(_puzzle.get("rotate", false)):
		# 돌리기 버튼이 없는 판이다. 여기서 몰래 돌리면 계획이 보는 모양과 아이가 든
		# 모양이 어긋난다 (계획은 "이 판에서 쓸 수 있는 모양"만 놓고 세운다).
		# 검사기가 이 함수를 직접 부를 수 있어서 여기서 막는다.
		return
	var i := int(_held["idx"])
	var pi := int(_tray[i]["pi"])
	var rots: Array = NoodPieces.rotations(pi)
	var cur := NoodPieces.key(NoodPieces.normalize(_tray[i]["rot"]))
	var at := 0
	for k in rots.size():
		if NoodPieces.key(rots[k]) == cur:
			at = k
			break
	_tray[i]["rot"] = rots[(at + 1) % rots.size()]


## 오래 막혀 있으면 지금 계획의 자리 하나를 숨 쉬게 한다. 벌도 재촉도 아니다.
##
## ★ **지금 놓을 수 있는** 조각만 가리킨다. 중력이 있어서 "자리는 비었지만 아직 놓으면
##   안 되는" 조각이 생기는데, 그런 걸 가리키면 아이는 시킨 대로 했는데도 조각이
##   안 들리는 걸 보게 된다 — 힌트가 거짓말이 되는 최악의 경우다.
func _show_hint() -> void:
	if _tray.is_empty():
		return
	# ★ 계획의 **첫 수**만 가리킨다. _plan[i] 는 "다 놓고 났을 때 있을 자리"라,
	#   차례가 뒤인 조각을 가리키면 아이는 시킨 대로 떨어뜨렸는데 더 아래로 가서
	#   튕기는 것을 보게 된다 — 힌트가 거짓말이 되는 최악의 경우다.
	if _plan_next >= 0 and _plan_next < _plan.size() \
			and not (_plan[_plan_next] as Array).is_empty():
		_hint_cells = (_plan[_plan_next] as Array).duplicate()
		return
	# 계획이 아예 없다 = 되들다가 구멍이 조각 밑에 묻혔다. 그러면 **들어낼 조각**을
	# 가리킨다. 이것이 막다른 판을 막는 마지막 방어선이고, 없으면 아이는 판만 보게 된다.
	var lift := _lift_hint()
	if lift >= 0:
		_hint_cells = (_board[lift]["cells"] as Array).duplicate()


## 계획이 사라졌을 때 도로 들어야 할 판 위의 조각. 없으면 -1.
##
## ★ 힌트를 누를 때만 부른다 (판마다 조각 수만큼 계획을 다시 세운다).
func _lift_hint() -> int:
	var shapes := _shapes()
	var rotate := bool(_puzzle.get("rotate", false))
	var best := -1
	var top := 9999
	for i in _board.size():
		var b: Dictionary = _board[i]
		if bool(b["fixed"]):
			continue
		var g := _grid.duplicate()
		for cc: Vector2i in (b["cells"] as Array):
			g[cc.y * _n + cc.x] = -1
		var sh := shapes.duplicate()
		sh.append(NoodPieces.rotations(int(b["pi"])) if rotate
				else [_shape_of(b["cells"])])
		if bool(NoodGen.plan(g, _n, sh, [], _bag)["ok"]):
			return i
		# 하나만 들어서는 안 풀리면 **맨 위** 조각부터 걷어낸다. 위에서부터 걷으면
		# 반드시 처음 상태로 돌아가므로 아이가 갇히지 않는다.
		var my := 9999
		for cc: Vector2i in (b["cells"] as Array):
			my = mini(my, cc.y)
		if my < top:
			top = my
			best = i
	return best


# --------------------------------------------------------------------------- #
# 진행
# --------------------------------------------------------------------------- #

func _finish() -> void:
	_done = true
	_busy = true
	_save(true)
	await get_tree().create_timer(0.9 if not dev_mode else 0.05).timeout
	_busy = false


func _next_stage() -> void:
	_busy = true
	stage += 1
	_save()
	if Shell.journey_active and not dev_mode:
		Shell.journey_advance()
		return
	# ★ 상한에 닿았으면 셸이 쉼표를 찍고 허브로 보낸다 (Shell.round_done) —
	#   세션을 새로 열지 않으면 그 뒤로는 한 판마다 튕겨 나간다.
	if Shell.round_done(dev_mode):
		return
	_build()


## 기록을 남긴다. score 가 참일 때만 **"한 판 깼다"를 센다.**
##
## ★ 예전에는 `_finish()` 와 `_next_stage()` 가 둘 다 이걸 불렀고, 그 사이에 `_done` 이
##   안 꺼져서 **한 판이 두 번 세어졌다.** 숨은 난이도 손잡이(skill)가 판마다 +2 씩 올라
##   **다섯 판 만에 상한(+10)에 붙었다** — 아이 눈에는 이유 없이 갑자기 어려워지는 것으로만
##   보인다(규칙 11 위반). 부모 화면의 "오늘 몇 판"도 두 배였다.
##   그래서 세는 일과 저장하는 일을 갈라 두었다. `_done` 으로 판단하지 마라.
func _save(score := false) -> void:
	var d := _state()
	d["best_stage"] = maxi(int(d.get("best_stage", 1)), stage)
	if score:
		d["cleared"] = int(d.get("cleared", 0)) + 1
		# 헤매지 않고 끝냈으면 조용히 한 칸 어렵게 (아이 눈에 아무 표시도 안 나간다)
		if _misses == 0:
			d["skill"] = clampi(int(d.get("skill", 0)) + 1, -6, 10)
		elif _misses >= 6:
			d["skill"] = clampi(int(d.get("skill", 0)) - 1, -6, 10)
		Shell.bump_today("nood")
	Shell.mark_dirty()


func _go_home() -> void:
	Shell.journey_end()
	Router.goto_hub()


# --------------------------------------------------------------------------- #
# 그리기 도우미
# --------------------------------------------------------------------------- #

func _outline_cells(br: Rect2, c: float, cells: Array, col: Color, w: float) -> void:
	_outline_cells_at(br.position, c, cells, col, w)


## 조각 바깥 테두리만 그린다 (칸 사이 선은 안 그린다).
func _outline_cells_at(o: Vector2, c: float, cells: Array, col: Color, w: float) -> void:
	var have := {}
	for cc in cells:
		have["%d,%d" % [(cc as Vector2i).x, (cc as Vector2i).y]] = true
	for cc in cells:
		var v: Vector2i = cc
		var p := o + Vector2(float(v.x) * c, float(v.y) * c)
		if not have.has("%d,%d" % [v.x, v.y - 1]):
			draw_line(p, p + Vector2(c, 0), col, w)
		if not have.has("%d,%d" % [v.x, v.y + 1]):
			draw_line(p + Vector2(0, c), p + Vector2(c, c), col, w)
		if not have.has("%d,%d" % [v.x - 1, v.y]):
			draw_line(p, p + Vector2(0, c), col, w)
		if not have.has("%d,%d" % [v.x + 1, v.y]):
			draw_line(p + Vector2(c, 0), p + Vector2(c, c), col, w)


func _outline_rect(r: Rect2, col: Color, w: float) -> void:
	draw_rect(r, col, false, w)


func _round_rect(r: Rect2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2.0, r.size.y), col)
	draw_rect(Rect2(r.position.x, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	draw_rect(Rect2(r.position.x + r.size.x - rad, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	for corner in [Vector2(rad, rad), Vector2(r.size.x - rad, rad),
			Vector2(rad, r.size.y - rad), Vector2(r.size.x - rad, r.size.y - rad)]:
		draw_circle(r.position + corner, rad, col)


func _text(s: String, at: Vector2, px: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at + Vector2(0, px), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_centered(s: String, at: Vector2, px: int, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(f, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
