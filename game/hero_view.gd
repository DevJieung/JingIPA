extends RefCounted
class_name HeroView

## 영웅 편성 판 — **전장** 여섯 자리와 **영웅 전당**(대기)을 한 판에 그리고 눌러서 바꾼다.
##
## ★ 왜 화면이 아니라 도우미인가: 이 판은 탄마다 뽑기 화면에서 뜬다. 나중에 다른 곳에서
##   또 띄우게 되더라도 그리기와 누르는 규칙이 여기 한 곳에만 있어야 한다 —
##   두 곳에 두면 "여기서는 바꿔지는데 저기서는 안 바꿔지는" 버그가 반드시 생긴다.
##
## 누르는 법:
##   아무것도 안 고른 상태에서 한 명을 누르면 **설명 팝업**이 뜬다.
##   팝업의 「옮기기」를 누르면 그 영웅이 골라지고, 그다음 누르는 자리와 맞바꾼다.
##
## ★ 전당은 **스크롤한다.** 예전에는 칸 크기를 줄여서 다 밀어 넣었는데, 후반에 캐릭터가
##   스물 넘게 쌓이면 칸이 세로로 찌부러져서 얼굴도 이름도 안 보였다(사용자가 본 그대로다).
##   지금은 칸 크기를 고정하고 넘치는 만큼 굴린다.
##
## ★ 전당은 전장과 **다른 격자**를 쓴다(BCOLS 여덟 칸). 예전에는 전장의 칸 폭 하나를
##   같이 써서 창이 딱 한 줄이었고, 그 한 줄이 판 밖으로 넘쳐서 「전투 시작」 위에
##   안 보이는 칸이 깔려 있었다 — 전투를 시작하려다 못 보는 영웅이 골라졌다.
##   지금 창은 **줄 높이의 정수배**이고, 굴림도 한 줄 눈금에 맞춰 선다(_snap_scroll).

## 전당 자리를 전장 자리와 한 숫자로 섞어 쓰기 위한 시작값.
const BENCH := 100000

## 지금 고른 자리. -1 이면 아무것도 안 골랐다.
var sel: int = -1
## 방금 온 영웅의 id. 그 칸에 「새로 왔다」 테두리를 두른다.
var new_id: String = ""
## 설명 팝업을 띄운 자리. -1 이면 안 떠 있다.
var info: int = -1
## 전당을 얼마나 굴렸는가(px). 0 이 맨 위다.
var scroll: float = 0.0

## 테두리가 숨 쉬듯 빛나게 하는 데만 쓰는 시계.
var _t: float = 0.0
## 마지막으로 그린 전당 창과 한 줄 높이 — 굴리는 한계를 재는 데 쓴다.
var _view := Rect2()
var _row_h: float = 1.0
var _rows: int = 1
## 창에 **온전히** 들어가는 줄 수. 창 높이가 언제나 이 수의 정수배다.
var _vis_rows: int = 1
## 새로 온 영웅을 한 번 찾아갔는가. draw() 는 매 프레임 도므로 이 빗장이 없으면
## 손가락으로 끌어 놓은 자리를 매 프레임 도로 끌어당긴다.
var _sought_new: bool = false
## 손가락을 끌고 있는가. 눌러서 고르는 것과 굴리는 것을 가르는 값이다.
var _drag: bool = false
var _drag_from: Vector2 = Vector2.ZERO
var _drag_scroll: float = 0.0
var _moved: float = 0.0

## 손가락이 이만큼 움직이면 「고르기」가 아니라 「굴리기」다.
const TAP_SLOP := 10.0


func update(dt: float) -> void:
	_t += dt


# --------------------------------------------------------------------------- #
# 손가락 — 눌러서 고르기와 끌어서 굴리기를 가른다
# --------------------------------------------------------------------------- #
## 눌렀다. 참을 주면 부르는 화면은 **이 프레임에 아무것도 하지 않는다** —
## 손을 뗄 때(release) 그때까지 움직인 거리를 보고 고르기인지 굴리기인지 정한다.
##
## ★ 왜 누르는 순간에 안 고르는가: 폰에서 목록을 굴리려고 손을 대면 그 자리에 있던
##   영웅이 골라져 버린다. 굴릴 때마다 엉뚱한 영웅이 골라지는 목록은 못 쓴다.
func press(pos: Vector2) -> bool:
	if info >= 0:
		return false          # 팝업이 떠 있으면 버튼이 먼저다
	if not _view.has_point(pos):
		return false
	_drag = true
	_drag_from = pos
	_drag_scroll = scroll
	_moved = 0.0
	return true


## ★ **끄는 동안에도 줄 눈금에 붙인다.** 1:1 로 따라가게 두면 두 가지가 같이 깨진다:
##   1. 줄이 창 아래로 최대 한 줄(96px) 삐져나오는데, 덮어 자를 바탕은 판 안쪽 10px 뿐이라
##      영웅 칸이 「전투 시작」 단추 위에 그려진다(CLAUDE.md 14-7 — 덮어 자르기는 판 안에
##      들어오는 것만 자를 수 있다).
##   2. 반쯤 걸친 줄은 누를 자리를 등록하지 않는데(hot), 손가락이 0.5px 만 밀려도 그 줄이
##      반쯤 걸친 것이 되고 release() 는 10px(TAP_SLOP) 까지를 여전히 「눌렀다」로 친다 —
##      95% 가 보이는 칸을 눌렀는데 아무 일도 안 일어난다.
##   눈금에 붙여 두면 반쯤 걸친 줄이 **아예 생기지 않아서** 둘 다 사라진다. 네 줄짜리
##   격자라 한 줄씩 넘어가는 손맛이 오히려 목록답다.
func motion(pos: Vector2) -> void:
	if not _drag:
		return
	_moved = max(_moved, _drag_from.distance_to(pos))
	scroll = _clamp_scroll(round((_drag_scroll - (pos.y - _drag_from.y)) / _row_h) * _row_h)


## 손을 뗐다. 굴린 것이 아니면 그 자리를 눌린 것으로 친다.
##
## ★ 눈금 맞추기(_snap_scroll)는 **누른 자리를 정한 뒤**에 온다. ui.hit() 이 재는 자리는
##   지난 프레임의 _draw() 가 등록해 둔 것이라, 먼저 굴려 버리면 목록은 이미 움직였는데
##   손가락은 옛 자리를 누른 셈이 되어 **엉뚱한 영웅**이 골라진다. 그래서 돌려줄 값을
##   먼저 셈해 두고, 나가는 길 넷이 모두 같은 자리에서 눈금을 맞춘다.
func release(pos: Vector2, ui: Ui) -> bool:
	if not _drag:
		_snap_scroll()
		return false
	_drag = false
	var out: bool = true
	if _moved <= TAP_SLOP:    # 굴린 것이면 누른 것으로 치지 않는다
		var id := ui.hit(pos)
		if id != "":
			out = tap(id)
	_snap_scroll()
	return out


## 휠 한 칸에 **한 줄**을 굴린다.
##
## ★ 반 줄씩 굴리면 한 칸만 굴려도 창이 줄 중간에 멈춰 서서, 마지막 줄이 판 밖으로
##   나간 채로 쉰다. 눈금이 한 줄이면 쉬는 자리가 언제나 줄 머리다.
func wheel(dir: float) -> void:
	if info >= 0:
		return                # 팝업이 떠 있으면 뒤의 목록은 굴러가면 안 된다
	scroll = _clamp_scroll(scroll + dir * _row_h)


func _clamp_scroll(v: float) -> float:
	var maxs: float = maxf(0.0, float(_rows) * _row_h - _view.size.y)
	return clampf(v, 0.0, maxs)


## 굴림 자리를 **한 줄 눈금**에 맞춘다.
##
## ★ 왜 필요한가: Godot 의 _draw 에는 자르기가 없어서, 창 밖으로 걸친 칸은 바탕색으로
##   덮어 자를 수밖에 없다(CLAUDE.md 14-7). 그런데 덮을 수 있는 것은 **판 안쪽**뿐이라,
##   줄 중간에 멈춰 서면 마지막 줄이 판 아래 — 「전투 시작」 위 — 에 그대로 남는다.
## ★ 굴림 한계(maxs)는 언제나 줄 높이의 정수배다(창 높이 = _vis_rows x _row_h).
##   그래서 눈금에 맞춘 뒤에 다시 잘라도 눈금이 안 어긋난다.
func _snap_scroll() -> void:
	if _row_h <= 0.0:
		return
	scroll = _clamp_scroll(round(scroll / _row_h) * _row_h)


# --------------------------------------------------------------------------- #
# 누르기
# --------------------------------------------------------------------------- #
## 이 판이 등록한 버튼인가. 처리했으면 참.
func tap(id: String) -> bool:
	if not id.begins_with("hv:"):
		return false
	var body := id.substr(3)
	if body == "sort":
		sort_bench()
		return true
	if body == "close" or body == "dismiss":
		info = -1
		return true
	# ★ 팝업의 판 안쪽. 눌러도 아무 일이 없어야 한다 — 이 갈래가 없으면 아래의
	#   int(body.substr(1)) 이 0 을 돌려줘서 **전장 0번의 팝업이 다시 뜬다.**
	if body == "none":
		return true
	if body == "move":
		# 팝업에서 「옮기기」 — 이제 이 영웅이 골라졌다. 다음에 누르는 자리와 맞바꾼다.
		sel = info
		info = -1
		return true
	var code: int = int(body.substr(1))
	if body.begins_with("b"):
		code += BENCH
	if sel < 0:
		# 아무것도 안 골랐다 — 설명 팝업을 띄운다. 빈 칸은 보여 줄 것이 없다.
		if _at(code).is_empty():
			return true
		info = code
		return true
	if sel == code:
		sel = -1
		return true
	_move(sel, code)
	sel = -1
	return true


## 전당을 **등급 높은 순**으로 세운다 (사용자가 정한 것: 「랭킹 높은 카드순」).
## 등급이 같으면 겹이 많은 쪽, 그것도 같으면 이름 차례.
##
## ★ 전장(싸우는 여섯)은 건드리지 않는다. 거기 서는 차례는 상성과 탄 방식을 보고 사람이
##   고른 것이라, 정렬 한 번에 뒤섞이면 방금 짜 놓은 편성이 통째로 날아간다.
## ★ 줄 세우는 일 자체는 Run 이 한다(CLAUDE.md 14-3). 화면이 Run.bench 를 직접 자르면
##   그 판만 자동 저장 밖에 있게 되어, 정렬해 놓고 앱을 껐다 켜면 도로 흐트러진다.
func sort_bench() -> void:
	Run.sort_bench()
	scroll = 0.0
	# ★ 고른 것을 반드시 푼다. 「옮기기」는 sel 에 **자리 번호**를 담아 두는데 정렬이
	#   전당의 번호를 통째로 다시 매기므로, 안 풀면 다음에 누르는 순간 플레이어가 고른
	#   영웅이 아니라 그 자리에 새로 온 **다른 영웅**이 딸려 간다.
	sel = -1


## a 자리의 영웅을 b 자리로 옮긴다(또는 맞바꾼다). 실제로 바뀌었으면 참.
##
## ★ 배열을 건드리는 것은 Run 쪽 함수들뿐이다. 여기서 heroes/bench 를 직접 자르면
##   "겹친 수(n)가 딸려 오지 않는" 종류의 버그가 난다.
func _move(a: int, b: int) -> bool:
	var a_bench: bool = a >= BENCH
	var b_bench: bool = b >= BENCH
	var ai: int = a - BENCH if a_bench else a
	var bi: int = b - BENCH if b_bench else b
	if not a_bench and not b_bench:
		# 전장 안에서 자리를 바꾼다. 빈 칸으로 보내는 것은 뜻이 없다(이미 전장에 있다).
		return Run.swap_field(ai, bi)
	if a_bench and b_bench:
		# ★ 전당의 **빈 칸**에 떨구는 것도 뜻이 있다 — 칸이 금색으로 「여기로」라고
		#   말해 놓고 아무 일도 안 하면 화면이 거짓말을 하는 것이다. Run.move_bench 가
		#   그 경우를 맨 뒤로 보내는 것으로 받아 준다.
		return Run.move_bench(ai, bi)
	# 한쪽은 전장, 한쪽은 전당
	var f: int = bi if a_bench else ai
	var v: int = ai if a_bench else bi
	if f >= Run.heroes.size():
		# 전장의 빈 칸에 전당에서 올린다
		return Run.bench_to_field(v)
	if v >= Run.bench.size():
		# 전당의 빈 칸으로 전장에서 내린다
		return Run.swap_field_bench(f, -1)
	return Run.swap_field_bench(f, v)


func _at(code: int) -> Dictionary:
	if code >= BENCH:
		var i: int = code - BENCH
		return Run.bench[i] if i < Run.bench.size() else {}
	return Run.heroes[code] if code < Run.heroes.size() else {}


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #
## 칸 하나의 최대 폭. 없으면 자리가 남는 화면에서 칸이 200px 로 부풀어
## 대여섯 개가 화면을 통째로 차지하고, 그 사이가 텅 비어 보인다.
const MAX_CW := 208.0
## 전당 칸의 **최소** 폭. 여기 아래로는 안 줄인다 — 대신 스크롤한다.
## ★ draw() 가 이 값을 **실제로 읽는다**: bcw 가 여기 못 미치면 칸 수(bcols)를 하나씩
##   줄인다. 예전에는 적어만 두고 아무도 안 읽어서, 좁은 판에서는 칸이 얼마든지
##   찌부러질 수 있었다(CLAUDE.md 14-7 이 금한 바로 그것이다).
const MIN_CW := 104.0
## 전당의 칸 수. **전장(여섯)과 다른 수다** — 스물다섯을 담는 목록이라 한 줄에 더 세운다.
const BCOLS := 6

## 머리글 높이. 전장 칸을 낮춘 만큼 여기도 같이 줄여 전당에 넘겼다 —
## 전당 창이 한 줄밖에 안 서던 것이 이 몇십 px 때문이었다.
const HEAD1 := 24.0
const GAP := 10.0
const HEAD2 := 30.0
## 머리글과 카드 테두리 사이의 숨 쉴 여백. 전장·전당에 같은 간격을 준다.
const HEADER_CARD_GAP := 12.0

## 판의 바탕색. 넘치는 칸을 덮어 자르는 데에도 쓰므로 **반드시 불투명**이어야 한다.
const BACK := Color("#182629")

## 창 경계를 잴 때 눈감아 주는 한 톨. Rect2 속은 float32 인데 여기 셈은 float64 라
## 「딱 맞는 자리」가 소수점 끝자리에서 어긋난다 — 그 한 톨이 줄 하나를 판 밖으로 내보낸다.
const EDGE_EPS := 0.5


func draw(ci: CanvasItem, ui: Ui, area: Rect2, cols: int = 6, show_info: bool = true) -> void:
	# 판 전체에 바탕을 깐다. ★ 이 한 겹이 있어야 전당을 굴릴 때 칸이 판 밖으로
	#   삐져나오는 것을 같은 색으로 덮어 자를 수 있다(Godot 의 _draw 에는 자르기가 없다).
	Look.px_panel(ci, area, BACK, Look.PANEL_EDGE, 0.06)

	var pad := 6.0
	var inner := area.grow(-14.0)

	# --- 전장: 여섯 자리. 칸 폭은 예전 그대로다 ---
	var cw: float = min(inner.size.x / float(cols), MAX_CW)
	# ★ 세로를 1.26 → 1.02 로 낮췄다. 남은 몫은 통째로 전당의 창이 된다 —
	#   얼굴은 칸 높이에서 art_box 를 다시 재므로(_cell) 낮춰도 아무것도 안 깨진다.
	var fh: float = 94.0 if cols <= 6 else 148.0
	var x0: float = inner.position.x + (inner.size.x - cw * float(cols)) * 0.5

	var fy: float = inner.position.y + HEAD1 + HEADER_CARD_GAP
	var field_rows := ceili(float(Balance.HERO_SLOTS) / float(cols))
	var by_head: float = fy + (fh + 6.0) * field_rows + GAP
	var by: float = by_head + HEAD2 + HEADER_CARD_GAP

	# --- 전당: **제 칸 수와 제 칸 크기**를 갖는다 ---
	# ★ 예전에는 전장의 cw 하나를 전당까지 같이 썼다. 여섯 칸짜리 폭으로 스물다섯을
	#   담으려니 창이 딱 한 줄이었고, 그 한 줄마저 판 밖으로 넘쳐 있었다.
	var bcols: int = BCOLS
	while bcols > 1 and inner.size.x / float(bcols) < MIN_CW:
		bcols -= 1
	var bcw: float = inner.size.x / float(bcols)
	var bx0: float = inner.position.x + (inner.size.x - bcw * float(bcols)) * 0.5

	# 창 높이는 **줄 높이의 정수배**다.
	# ★ 왜 그래야 하는가: 자르기가 없는 _draw 에서 넘친 칸을 지우는 길은 바탕색으로
	#   덮는 것뿐인데(CLAUDE.md 14-7), 덮을 수 있는 것은 **판 안쪽**뿐이다. 창이 제
	#   자리보다 조금이라도 크면 마지막 줄이 판 밖 — 「전투 시작」 위 — 으로 나가고,
	#   덮개는 그 몫에 닿지도 못한다. 그래서 창은 언제나 「들어가는 만큼」이다.
	var avail: float = maxf(1.0, inner.position.y + inner.size.y - by)
	var vis: int = clampi(int(floor(avail / (bcw * 0.68))), 1, 4)
	_vis_rows = vis
	_row_h = avail / float(vis)
	_view = Rect2(inner.position.x, by, inner.size.x, float(vis) * _row_h)

	# ★ 창은 언제나 꽉 채운다(bcols x _vis_rows). 반쯤 빈 창은 「여기가 목록이다」가 아니라
	#   「판이 잘못 그려졌다」로 읽히고, 남는 빈 칸은 그대로 떨굴 자리가 되어 준다.
	var shown: int = maxi(bcols * _vis_rows,
			int(ceil(float(Run.bench.size() + 1) / float(bcols))) * bcols)
	shown = mini(Balance.BENCH_SLOTS, shown)
	_rows = int(ceil(float(shown) / float(bcols)))
	# ★ 새로 온 영웅이 선 줄로 창을 데려간다. 이 판은 탄마다 **새로 만들어지므로**
	#   (DrawScreen 이 HeroView 를 들고 있다) 열릴 때 scroll 이 언제나 0 인데,
	#   gain_hero 는 새 영웅을 전당 **맨 뒤**에 붙인다 — 전당이 한 창을 넘어서는
	#   순간부터, 이 판이 뜬 이유인 바로 그 영웅이 화면 밖에서 「새로 왔다」 테두리를
	#   혼자 깜빡이고 있었다. 머리글은 "전당에서 기다린다"고 적어 놓고서.
	if not _sought_new and new_id != "":
		_sought_new = true       # 한 번만. 다시 켜면 매 프레임 손가락과 싸운다
		var found: Array = Run.latest_draw_location()
		if String(found[0]) == "bench":
			scroll = float(int(found[1]) / bcols) * _row_h
	scroll = _clamp_scroll(scroll)

	# --- 전당(스크롤하는 쪽)을 먼저 그리고, 넘친 것을 바탕색으로 덮어 자른다 ---
	# ★ Ui.hit 은 **나중에 등록한 것이 이긴다**(core/ui.gd 43~48). 전당을 제일 먼저
	#   등록하는 데에는 뜻이 있다 — 전장·팝업·「전투 시작」이 모두 뒤에 와서
	#   전당 칸을 덮는다. 이 차례를 바꾸면 전당이 남의 단추를 조용히 먹는다.
	var vy: float = _view.position.y
	var vb: float = vy + _view.size.y
	for i in range(shown):
		var c: int = i % bcols
		var r: int = i / bcols
		var cy: float = vy + float(r) * _row_h - scroll
		# ★ 경계는 >= · <= 로, 그것도 **한 톨(EDGE_EPS)을 두고** 잰다. 예전 > · < 는
		#   창에 딱 붙은 줄을 한 줄 더 그렸고, 그런데도 안 새고 있던 것은 순전히 우연이다 —
		#   Rect2 속은 float32 라, 여기서 float64 로 다시 잰 값과 소수점 끝자리가 어긋난다.
		#   그 한 톨 때문에 「창 바로 아래 줄」이 통째로 판 밖에 그려질 수 있다.
		if cy >= vb - EDGE_EPS or cy + _row_h <= vy + EDGE_EPS:
			continue          # 창 밖 — 그릴 것도 없고 누를 자리도 없다
		# ★ 창에 **반쯤 걸친** 줄(끄는 중에만 생긴다)은 그리되 누르지는 못하게 한다.
		#   바탕색이 덮어 자르는 것은 그림뿐이라, 자리를 그대로 등록하면 「전투 시작」
		#   위에 안 보이는 칸이 깔려서 — 전투를 시작하려다 못 보는 영웅이 골라진다.
		# ★ 자(EDGE_EPS)가 위의 잘라내기와 **같아야** 한다. 다르면 「그려졌는데 안 눌리는
		#   줄」과 「안 그려졌는데 눌리는 줄」 중 하나가 반드시 생긴다.
		var hot: bool = cy >= vy - EDGE_EPS and cy + _row_h <= vb + EDGE_EPS
		_cell(ci, ui, Rect2(bx0 + float(c) * bcw + pad, cy,
				bcw - pad * 2.0, _row_h - pad * 2.0), BENCH + i, false, hot)
	# 위아래로 삐져나온 몫을 덮는다.
	ci.draw_rect(Rect2(area.position.x + 4.0, area.position.y + 4.0,
			area.size.x - 8.0, _view.position.y - area.position.y - 4.0), BACK)
	ci.draw_rect(Rect2(area.position.x + 4.0, _view.position.y + _view.size.y,
			area.size.x - 8.0, maxf(0.0, area.position.y + area.size.y
			- (_view.position.y + _view.size.y) - 4.0)), BACK)

	# --- 전장 ---
	Look.text_left(ci, Vector2(inner.position.x, fy - 14.0 - HEADER_CARD_GAP),
			"전장에 배치된 영웅", 22, Look.INK)
	for i in range(Balance.HERO_SLOTS):
		_cell(ci, ui, Rect2(x0 + float(i % cols) * cw + pad, fy + float(i / cols) * (fh + 6.0), cw - pad * 2.0, fh), i, true)

	# --- 전당 머리글: 보관 순서를 유지하고 별도 정렬 조작은 두지 않는다 ---
	Look.text_left(ci, Vector2(inner.position.x, by_head + 16.0),
			"전당에 대기중인 영웅", 22, Look.INK)
	# 막대는 **마지막 칸 바로 오른쪽**, 창 안쪽에 붙인다.
	_scrollbar(ci, minf(bx0 + bcw * float(bcols) - SBAR_W,
			_view.position.x + _view.size.x - SBAR_W))
	if show_info:
		draw_info(ci, ui)


## 굴림 막대의 폭. 판 테두리에 붙은 4px 짜리 실선은 손잡이가 아니라 장식으로 읽혔다.
const SBAR_W := 6.0


## 굴림 막대. **얼마나 남았는지**가 보여야 손가락이 더 끌 생각을 한다.
##
## ★ 자리를 부르는 쪽에서 받는다 — 예전에는 판 오른쪽 끝(마지막 칸에서 63px 떨어진
##   자리)에 그려서 목록과 아무 상관 없는 테두리 무늬처럼 보였다. 지금은 마지막 칸에
##   바로 붙는다.
## ★ 홈(track)을 먼저 깐다. 손잡이만 있으면 「전체 중 어디」가 아니라 그냥 밝은 조각이다.
func _scrollbar(ci: CanvasItem, x: float) -> void:
	var total: float = float(_rows) * _row_h
	if total <= _view.size.y + 1.0:
		return
	ci.draw_rect(Rect2(x, _view.position.y, SBAR_W, _view.size.y), Look.BG_DEEP)
	ci.draw_rect(Rect2(x, _view.position.y, 1.0, _view.size.y), Look.PANEL_EDGE)
	var k: float = _view.size.y / total
	var h: float = maxf(24.0, _view.size.y * k)
	var y: float = _view.position.y + (_view.size.y - h) * (scroll / maxf(1.0, total - _view.size.y))
	ci.draw_rect(Rect2(x, y, SBAR_W, h), Look.INK_DIM)


## 자리 한 칸. 비어 있으면 빈 상자로 그린다.
##
## ★ hot 이 거짓이면 **그리기만 하고 누를 자리는 등록하지 않는다.** 전당 창에 반쯤
##   걸친 줄이 그것이다 — 그림은 바탕색이 덮어 자르지만 누를 자리는 아무도 못 자른다.
func _cell(ci: CanvasItem, ui: Ui, rect: Rect2, code: int, _big: bool,
		hot: bool = true) -> void:
	var hero := _at(code)
	var id := "hv:%s%d" % ["b" if code >= BENCH else "f", code - BENCH if code >= BENCH else code]
	if hot:
		ui.zone(rect, id)
	if hero.is_empty():
		Look.fill_round(ci, rect, 4, Look.BG_DEEP)
		var label := I18n.t("여기로" if sel >= 0 else "빈 칸")
		if code < BENCH and sel < 0 and I18n.locale == "en":
			label = label.replace(" ", "\n")
		var lines := Look.wrapped_lines(label, rect.size.x - 14, 18)
		var height := lines.size() * Look.line_height(18)
		Look.wrap_text(ci, label, Rect2(rect.get_center() - Vector2((rect.size.x - 14) * 0.5, height * 0.5), Vector2(rect.size.x - 14, height)), 18, Look.INK_DIM)
		return
	HeroCard.draw(ci, rect, hero, sel == code)
	if new_id != "" and String(hero["unit"]["id"]) == new_id:
		Look.draw_brackets(ci, rect, 6, Look.INK, 2)


# --------------------------------------------------------------------------- #
# 설명 팝업 — 캐릭터를 누르면 뜬다
# --------------------------------------------------------------------------- #
## ★ 왜 팝업인가: 캐릭터가 서른 명인데 칸에는 얼굴·등급·속성밖에 안 들어간다.
##   「이 애가 무엇을 하는 애인가」(탄 방식·상태이상·치명타·초당 피해)를 볼 데가
##   게임 어디에도 없었다. 고를 근거가 없으면 편성은 그냥 그림 고르기다.
static func attack_target(u: Dictionary) -> String:
	var kind := String(u.get("bullet", "shot"))
	var spec: Dictionary = Balance.BULLET.get(kind, Balance.BULLET["shot"])
	match kind:
		"chain":
			var targets := int(spec["jumps"]) + (Balance.PASSIVE_CHAIN_JUMPS if Run.has("chainmaster") else 0)
			return "다중 · 가까운 적 최대 %d명에게 연쇄" % targets
		"ricochet":
			return "다중 · 무작위 적에게 최대 %d회 도탄" % int(spec["bounce"])
		"splash":
			return "광역 · 명중 지점 주변의 적을 함께 공격"
		"zone":
			return "광역 · 가까운 적의 위치에 장판으로 지속 피해"
		"beam":
			return "단일 · 목표에 광선이 즉시 명중"
	var count := int(spec.get("pierce", 1)) + (1 if Run.has("pierce") else 0)
	return "다중 · 최대 %d명 관통" % count if count > 1 else "단일 · 적 1명에게 발사"


static func innate_passive(u: Dictionary) -> String:
	var el := String(u.get("elem", "none"))
	var role := String(u.get("role", "single"))
	var mult := Balance.rider_mult(role)
	match Balance.elem_rider(el):
		"stun":
			var sp: Dictionary = Balance.STATUS["stun"]
			return "명중 시 %s%% 확률로 %.1f초 마비" % [
				String.num(minf(0.55, float(sp["chance"]) * mult) * 100, 1), float(sp["sec"])]
		"slow":
			var sp: Dictionary = Balance.STATUS["slow"]
			return "명중 시 %.1f초 동안 이동속도 %s%% 감소" % [
				float(sp["sec"]) * mult, String.num(minf(0.80, float(sp["amount"]) * mult) * 100, 1)]
		"burn":
			var sp: Dictionary = Balance.STATUS["burn"]
			return "명중 시 %.1f초 화상 · 초당 타격 피해의 %s%%" % [
				float(sp["sec"]) * mult, String.num(float(sp["amount"]) * mult * 100, 1)]
	if Balance.role_rider(role):
		if el == "water":
			return "명중할 때마다 적을 뒤로 밀어냄"
		return "치명타 확률 +%d%%" % int(round(Balance.RIDER_CRIT * 100))
	return "없음 · 기본 공격에 집중"


static func attack_note(unit: Dictionary) -> String:
	return "사거리 %d · 범위 안의 가까운 적 우선" % int(Balance.attack_range(unit))


func draw_info(ci: CanvasItem, ui: Ui) -> void:
	if info >= 0:
		_info_panel(ci, ui, Look.SCREEN)


## Route modal and scroll input before screen tabs and navigation.
func input(event: InputEvent, ui: Ui) -> bool:
	if info >= 0:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			info = -1
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			tap(ui.hit(event.position))
		return true
	if event is InputEventMouseMotion:
		motion(event.position)
		return _drag
	if not event is InputEventMouseButton:
		return false
	if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		wheel(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return true
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if event.pressed:
		return press(event.position) or tap(ui.hit(event.position))
	return release(event.position, ui)


func _info_panel(ci: CanvasItem, ui: Ui, area: Rect2) -> void:
	var hero := _at(info)
	if hero.is_empty():
		info = -1
		return
	var unit: Dictionary = hero["unit"]
	var tier := int(hero["tier"])
	var element := String(unit.get("elem", "none"))
	var tint := Balance.elem_color(element)
	ci.draw_rect(area, Color(0, 0, 0, 0.86))
	ui.zone(area, "hv:dismiss")
	var box := Rect2(174, 154, 932, 508)
	Look.material_panel(ci, box, Look.hero_card_face(element), Look.hero_card_edge(element))
	ui.zone(box, "hv:none")
	var portrait := Rect2(201, 194, 320, 330)
	SummonArt.seal(ci, portrait.get_center() + Vector2(0, 8), 132, _t * 0.2, tint, 0.23)
	Art.draw_unit_fit(ci, unit, portrait)
	Look.draw_rarity_fit(ci, Rect2(233, 535, 256, 28), tier, 10)
	SummonArt.hero_info(ci, unit, tier, Rect2(555, 180, 514, 370), true, hero)
	ui.button(ci, Rect2(556, 589, 243, 48), "이 영웅 이동", "hv:move", true, Look.GOLD, 22)
	ui.button(ci, Rect2(814, 589, 254, 48), "닫기", "hv:close", true, Look.PANEL_EDGE, 22)
