## 블록 채우기 — 조각을 기둥에 떨어뜨려 가이드 모양대로 쌓는다.
##
## ★ 조각은 테트리스처럼 **내려가다 걸리는 곳에 선다.** 빈 칸에 그냥 박아 넣는
##   자유 배치가 아니다. 그래서 "어디에 놓을까" 가 아니라 "어느 기둥으로
##   떨어뜨릴까 · 무엇을 먼저 떨어뜨릴까" 가 문제가 된다.
##
## ★ 조작 규칙은 **하나뿐**이다:
##     손이 비었을 때 탭  -> 그 조각을 손에 든다 (트레이든 판 위든)
##     손에 들었을 때 탭  -> 탭한 **기둥**으로 조각이 떨어진다
##   트레이와 판을 구분하지 않는다. 상태는 "지금 든 조각" 하나뿐이라
##   만 4세가 잃어버릴 것이 없다. 취소 버튼도, 드래그도, 길게 누르기도 없다.
##
## ★ 실패가 없다. 가이드 자리가 아닌 곳에 앉으면 그 칸들이 잠깐 흔들리고 조각은
##   손에 그대로 남는다. 시간 제한도, 점수도, 게임오버도 없다.
##   낙하도 재촉이 아니다 — 아이가 탭한 뒤에만 시작하고 FALL_SEC 안에 끝난다.
##
## ★ 판이 막다르게 끝나지 않는 이유: (1) 생성기가 "떨어뜨려서 풀리는 판"만 낸다
##   (NoodGen.pick_top), (2) 그래도 아이가 순서를 어긋나게 놓으면 판 위의 조각을
##   도로 들어 되돌릴 수 있다. 둘 다 있어야 한다 — (1)만으로는 부족하다.
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
## 트레이(아직 안 놓은 조각): {"pi", "cells"(정답 자리), "rot"(지금 보이는 모양)}
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
## 가둠 표: 해답 인덱스 s -> s 를 먼저 놓으면 갇히는 조각들의 해답 인덱스
var _blocks: Dictionary = {}
## 아직 차례가 아닌 조각을 눌렀을 때의 흔들림 (트레이 자리 / 남은 세기)
var _wobble_i := -1
var _wobble_t := 0.0

var _axes: Dictionary = {}


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
	# 못 만들면 한 단계씩 쉽게 해서 다시 — 아이 앞에 빈 화면이 뜨는 일은 없어야 한다.
	var cfg := _axes.duplicate()
	for retry in 4:
		_puzzle = NoodGen.make(cfg, rng)
		if not _puzzle.is_empty():
			break
		cfg["place"] = maxi(1, int(cfg["place"]) - 1)
		cfg["n"] = maxi(4, int(cfg["n"]) - 1)
	if _puzzle.is_empty():
		# 최후의 보루: 4x4 를 가장 단순한 조각들로
		_puzzle = NoodGen.make({"n": 4, "place": 2, "pieces": ["o4", "i2", "i3", "l3"]}, rng)

	_n = int(_puzzle["n"])
	_grid = PackedInt32Array()
	_grid.resize(_n * _n)
	_grid.fill(-1)
	_board.clear()
	_tray.clear()
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
		_put_on_board(int(e2["pi"]), e2["cells"], true, int(i))
	for item in (_puzzle["tray"] as Array):
		var cells: Array = (item["cells"] as Array)
		var shape := _shape_of(cells)
		if bool(_puzzle.get("rotate", false)):
			# 트레이에 아무 방향으로 내놓는다 — 아이가 돌려서 맞춰야 한다.
			var rots: Array = NoodPieces.rotations(int(item["pi"]))
			shape = rots[randi() % rots.size()]
		_tray.append({"pi": int(item["pi"]), "cells": cells, "rot": shape,
				"sol": int(item["sol"])})

	# 누가 누구를 가두는지 판마다 한 번 표로 만든다.
	#   _blocks[s] = s 를 먼저 떨어뜨리면 갇혀 버리는 조각들
	# 이 표가 조각 고르는 순서를 아래에서부터로 강제한다 (_ready_now 참고).
	_blocks = {}
	var bl := NoodGen.blockers_of(sol, _n)
	for it in _tray:
		var r := int((it as Dictionary)["sol"])
		for s in (bl[r] as Dictionary):
			if not _blocks.has(int(s)):
				_blocks[int(s)] = []
			(_blocks[int(s)] as Array).append(r)


func _put_on_board(pi: int, cells: Array, fixed: bool, sol: int) -> void:
	var idx := _board.size()
	_board.append({"pi": pi, "cells": (cells as Array).duplicate(), "fixed": fixed,
			"sol": sol})
	for c in cells:
		_grid[(c as Vector2i).y * _n + (c as Vector2i).x] = idx


## 절대 좌표 배열 -> (0,0) 기준 모양
func _shape_of(cells: Array) -> Array:
	var mx := 9999
	var my := 9999
	for c in cells:
		mx = mini(mx, (c as Vector2i).x)
		my = mini(my, (c as Vector2i).y)
	var out: Array = []
	for c in cells:
		out.append(Vector2i((c as Vector2i).x - mx, (c as Vector2i).y - my))
	return out


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
	var sol: Array = _puzzle.get("solution", [])

	# 바탕 칸
	for y in _n:
		for x in _n:
			var r := Rect2(br.position + Vector2(float(x) * c, float(y) * c), Vector2(c, c))
			draw_rect(r.grow(-3.0), CELL_EMPTY)

	# 안내 — 단계가 오를수록 덜 알려 준다 (난이도 축 B)
	if guide == 0:
		# ★ 칸을 통째로 칠하지 않는다. 옅게라도 칠하면 "이미 놓인 조각"과 헷갈려서
		#   아이 눈에 다 채워진 판으로 보인다. 가운데에 **작은 점**만 찍는다 —
		#   "여기에 이 색 조각이 온다"는 힌트이지 조각 자체가 아니다.
		for i in sol.size():
			var e: Dictionary = sol[i]
			for cc in (e["cells"] as Array):
				if _grid[(cc as Vector2i).y * _n + (cc as Vector2i).x] >= 0:
					continue
				var mid := br.position + Vector2((float((cc as Vector2i).x) + 0.5) * c,
						(float((cc as Vector2i).y) + 0.5) * c)
				draw_circle(mid, c * 0.17, Color(NoodPieces.color_of(int(e["pi"])), 0.55))
	elif guide == 1:
		# 조각 경계선만
		for i in sol.size():
			var e: Dictionary = sol[i]
			_outline_cells(br, c, e["cells"], Color(CELL_LINE, 0.9), 3.0)

	# 놓인 조각
	for i in _board.size():
		var b: Dictionary = _board[i]
		var col: Color = NoodPieces.color_of(int(b["pi"]))
		# 미리 놓여 있는 조각 — 색은 그대로 진하게 두고 **못 든다는 것만** 표시한다.
		# 회색으로 죽이면 안내 점과 구분이 안 간다.
		if bool(b["fixed"]):
			col = col.lerp(Color(0.55, 0.53, 0.50), 0.12)
		for cc in (b["cells"] as Array):
			var r := Rect2(br.position + Vector2(float((cc as Vector2i).x) * c,
					float((cc as Vector2i).y) * c), Vector2(c, c))
			draw_rect(r.grow(-3.0), col)
		_outline_cells(br, c, b["cells"], col.darkened(0.35), 5.0)
		if bool(b["fixed"]):
			# 못 드는 조각에는 옅은 빗금 — 눌러도 안 들리는 이유가 보인다
			for cc in (b["cells"] as Array):
				var p0 := br.position + Vector2(float((cc as Vector2i).x) * c,
						float((cc as Vector2i).y) * c)
				for k in 3:
					var o2 := float(k) * c * 0.33 + c * 0.16
					draw_line(p0 + Vector2(o2, 4.0), p0 + Vector2(4.0, o2),
							Color(1, 1, 1, 0.28), 3.0)

	# 격자선
	for i in _n + 1:
		var t := float(i) * c
		draw_line(br.position + Vector2(t, 0), br.position + Vector2(t, br.size.y), CELL_LINE, 2.0)
		draw_line(br.position + Vector2(0, t), br.position + Vector2(br.size.x, t), CELL_LINE, 2.0)
	_outline_rect(br, INK_SOFT, 4.0)

	# 힌트 — 시간이 지나면 정답 자리 하나가 숨 쉰다
	for cc in _hint_cells:
		var r := Rect2(br.position + Vector2(float((cc as Vector2i).x) * c,
				float((cc as Vector2i).y) * c), Vector2(c, c))
		draw_rect(r.grow(-6.0), Color(1, 1, 1, 0.20 + 0.25 * absf(sin(_t * 2.4))))

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
		if not _ready_now(i):
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
				# ★ 아직 이 조각의 차례가 아니다. 먼저 떨어뜨리면 아래로 내려와야 할
				#   조각이 갇힌다. "안 돼" 대신 살짝 흔들어서 "조금 있다가"로 읽히게 한다.
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
			# 놓인 조각을 눌렀다 -> 도로 든다 (미리 놓인 것은 못 든다).
			# ★ 이 되돌리기가 막다른 판을 막는 마지막 방어선이다. 가이드 자리에
			#   제대로 놓은 조각이라도, 아직 안 놓은 조각의 낙하 경로를 위에서
			#   막고 있을 수 있다. 그때 아이가 스스로 빠져나오는 유일한 길이다.
			var b: Dictionary = _board[at]
			if bool(b["fixed"]):
				_shake.append({"cells": (b["cells"] as Array).duplicate(), "t": 1.0})
				return
			_pick_up(at)
			return
		# 손이 비었는데 빈 칸을 눌렀다. 어린 아이는 먼저 판을 두드린다 —
		# 지금 차례인 조각을 자동으로 들려 주면 "판만 두드려도" 놀이가 굴러간다.
		if bool(Shell.tune("nood_autopick", false)):
			for i in _tray.size():
				if _ready_now(i):
					_held = {"from": "tray", "idx": i}
					_hover = cell
					_start_drop(cell.x)
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
	var an := _anchor_of(shape)
	var dx := col - an.x
	var dy := NoodGen.drop_dy(_grid, _n, shape, dx)
	if dy == NoodGen.NO_DROP:
		# 이 기둥으로는 아예 못 들어간다 (조각이 판 옆으로 삐져나가거나 이미 꽉 찼다).
		# 떨어뜨리는 흉내조차 안 낸다 — 기둥만 흔들어서 "여기는 아니야"를 말한다.
		_shake.append({"cells": _column_cells(col), "t": 1.0})
		_misses += 1
		return
	var cells: Array = []
	for cc in shape:
		cells.append(Vector2i((cc as Vector2i).x + dx, (cc as Vector2i).y + dy))
	_falling = {
		"pi": int(_tray[idx]["pi"]),
		"shape": shape,
		"cells": cells,
		"dx": dx,
		"dy": dy,
		"idx": idx,
		"t": 0.0,
		"ok": _same_cells(cells, _tray[idx]["cells"]),
	}
	_idle = 0.0


## 낙하가 끝났다. 가이드 자리면 붙고, 아니면 조각이 손에 그대로 돌아온다.
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
	var sol := int(_tray[idx]["sol"])
	_tray.remove_at(idx)
	_put_on_board(pi, cells, false, sol)
	_held = {}
	_hover = Vector2i(-1, -1)
	if _tray.is_empty():
		_finish()


## 두 칸 묶음이 같은 자리인가 (순서는 상관없다).
func _same_cells(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var have := {}
	for cc in a:
		have["%d,%d" % [(cc as Vector2i).x, (cc as Vector2i).y]] = true
	for cc in b:
		if not have.has("%d,%d" % [(cc as Vector2i).x, (cc as Vector2i).y]):
			return false
	return true


func _column_cells(col: int) -> Array:
	var out: Array = []
	if col < 0 or col >= _n:
		return out
	for y in _n:
		out.append(Vector2i(col, y))
	return out


## 트레이 조각 i 를 지금 떨어뜨려도 되는가.
##
## ★ "제자리에 앉는가"로 판단하면 안 된다 — **앉기는 잘 앉는데 다른 조각을 가두는**
##   경우가 있다. 옆 기둥의 고정 조각에 얹혀 제자리에 딱 앉았는데, 그 바람에
##   바로 아래 칸으로 내려와야 할 조각의 길을 막아 버리는 식이다. 그러면 그 조각은
##   영원히 못 들어가고 아이는 못 끝낸다 (실제로 여행 검사 10번째에서 물렸다).
##
##   그래서 기준은 **"이 조각이 가두는 조각이 이미 다 놓였는가"** 다. 이 규칙만 지키면
##   (1) 떨어뜨린 조각은 반드시 제자리에 앉고, (2) 남은 조각도 반드시 들어갈 수 있다.
##   증명: 이 조각을 받쳐 줄 조각과 위에서 막을 조각은 모두 "가두는" 관계로 묶여 있어서
##   순서가 강제된다. 그래서 아이가 어떤 순서로 골라도 판이 끝난다.
func _ready_now(i: int) -> bool:
	for s in _blocks.get(int(_tray[i]["sol"]), []):
		if _in_tray(int(s)):
			return false
	return true


## 해답 인덱스 s 의 조각이 아직 트레이에 있는가 (= 판에 안 놓였는가).
func _in_tray(s: int) -> bool:
	for it in _tray:
		if int((it as Dictionary)["sol"]) == s:
			return true
	return false


func _pick_up(idx: int) -> void:
	var b: Dictionary = _board[idx]
	var shape := _shape_of(b["cells"])
	_remove_board(idx)
	_tray.append({"pi": int(b["pi"]), "cells": (b["cells"] as Array), "rot": shape,
			"sol": int(b["sol"])})
	_held = {"from": "tray", "idx": _tray.size() - 1}


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


## 오래 막혀 있으면 정답 자리 하나를 숨 쉬게 한다. 벌도 재촉도 아니다.
##
## ★ **지금 차례인** 조각만 가리킨다. 중력이 있어서 "자리는 비었지만 아직 놓으면
##   안 되는" 조각이 생기는데, 그런 걸 가리키면 아이는 시킨 대로 했는데도 조각이
##   안 들리는 걸 보게 된다 — 힌트가 거짓말이 되는 최악의 경우다.
func _show_hint() -> void:
	if _tray.is_empty():
		return
	for i in _tray.size():
		if _ready_now(i):
			_hint_cells = (_tray[i]["cells"] as Array).duplicate()
			return


# --------------------------------------------------------------------------- #
# 진행
# --------------------------------------------------------------------------- #

func _finish() -> void:
	_done = true
	_busy = true
	_save()
	await get_tree().create_timer(0.9 if not dev_mode else 0.05).timeout
	_busy = false


func _next_stage() -> void:
	_busy = true
	stage += 1
	_save()
	if Shell.journey_active and not dev_mode:
		Shell.journey_advance()
		return
	Shell.add_round_units()
	if Shell.session_over_limit() and not dev_mode:
		_go_home()
		return
	_build()


func _save() -> void:
	var d := _state()
	d["best_stage"] = maxi(int(d.get("best_stage", 1)), stage)
	if _done:
		d["cleared"] = int(d.get("cleared", 0)) + 1
		# 헤매지 않고 끝냈으면 조용히 한 칸 어렵게 (아이 눈에 아무 표시도 안 나간다)
		if _misses == 0:
			d["skill"] = clampi(int(d.get("skill", 0)) + 1, -6, 10)
		elif _misses >= 6:
			d["skill"] = clampi(int(d.get("skill", 0)) - 1, -6, 10)
	Shell.mark_dirty()
	Shell.bump_today("nood")


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
