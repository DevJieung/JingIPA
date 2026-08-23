extends RefCounted
class_name HeroView

## 영웅 편성 판 — 안뜰 여섯 자리와 캐릭터 인벤토리를 한 판에 그리고 눌러서 바꾼다.
##
## ★ 왜 화면이 아니라 도우미인가: 이 판은 **두 곳**에 뜬다. 뽑기 화면에서 새 영웅이
##   왔는데 안뜰이 꽉 찼을 때, 그리고 상점(중간 정비)의 「영웅」 탭에서. 둘이 따로
##   그리면 규칙이 갈라진다 — "상점에서는 바꿔지는데 뽑기 화면에서는 안 바꿔지는"
##   버그가 반드시 생긴다. 그리기도 누르는 규칙도 여기 한 곳에만 둔다.
##
## 누르는 법: 하나를 눌러 고르고, 바꿀 자리를 한 번 더 누른다. 같은 것을 또 누르면 취소.
## 빈 칸은 **고를 수는 없고 놓을 수만** 있다.

## 인벤토리 자리를 안뜰 자리와 한 숫자로 섞어 쓰기 위한 시작값.
const BENCH := 1000

## 지금 고른 자리. -1 이면 아무것도 안 골랐다.
var sel: int = -1
## 방금 온 영웅의 id. 그 칸에 「새로 왔다」 테두리를 두른다.
var new_id: String = ""

## 테두리가 숨 쉬듯 빛나게 하는 데만 쓰는 시계.
var _t: float = 0.0


func update(dt: float) -> void:
	_t += dt


# --------------------------------------------------------------------------- #
# 누르기
# --------------------------------------------------------------------------- #
## 이 판이 등록한 버튼인가. 처리했으면 참.
func tap(id: String) -> bool:
	if not id.begins_with("hv:"):
		return false
	var body := id.substr(3)
	var code: int = int(body.substr(1))
	if body.begins_with("b"):
		code += BENCH
	if sel < 0:
		# 빈 칸을 먼저 고를 수는 없다 — 옮길 것이 없다.
		if _at(code).is_empty():
			return true
		sel = code
		return true
	if sel == code:
		sel = -1
		return true
	_move(sel, code)
	sel = -1
	return true


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
		# 안뜰 안에서 자리를 바꾼다. 빈 칸으로 보내는 것은 뜻이 없다(이미 안뜰에 있다).
		return Run.swap_field(ai, bi)
	if a_bench and b_bench:
		return _swap_bench(ai, bi)
	# 한쪽은 안뜰, 한쪽은 인벤토리
	var f: int = bi if a_bench else ai
	var v: int = ai if a_bench else bi
	if f >= Run.heroes.size():
		# 안뜰의 빈 칸에 인벤토리에서 올린다
		return Run.bench_to_field(v)
	if v >= Run.bench.size():
		# 인벤토리의 빈 칸으로 안뜰에서 내린다
		return Run.swap_field_bench(f, -1)
	return Run.swap_field_bench(f, v)


func _swap_bench(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= Run.bench.size() or b >= Run.bench.size():
		return false
	var t = Run.bench[a]
	Run.bench[a] = Run.bench[b]
	Run.bench[b] = t
	return true


func _at(code: int) -> Dictionary:
	if code >= BENCH:
		var i: int = code - BENCH
		return Run.bench[i] if i < Run.bench.size() else {}
	return Run.heroes[code] if code < Run.heroes.size() else {}


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #
## 인벤토리에 몇 칸을 보여 줄 것인가. 가진 것보다 **한 칸은 더** 보여 줘야
## "여기로 내려놓으면 되는구나"가 눈에 보인다. 빈 줄을 여럿 깔면 화면만 휑해진다.
func bench_shown(cols: int) -> int:
	var rows: int = maxi(1, int(ceil(float(Run.bench.size() + 1) / float(cols))))
	return mini(Balance.BENCH_SLOTS, rows * cols)


## area 안에 안뜰 여섯 자리와 인벤토리를 그린다. 칸 크기는 **주어진 네모에 맞춰** 정한다 —
## 뽑기 화면과 상점은 쓸 수 있는 자리가 다른데, 한쪽에 맞춰 고정하면 다른 쪽에서 넘친다.
func draw(ci: CanvasItem, ui: Ui, area: Rect2, cols: int = 6) -> void:
	const HEAD1 := 26.0
	const GAP := 14.0
	const HEAD2 := 30.0
	## 칸 하나의 최대 폭. ★ 없으면 자리가 남는 화면(상점)에서 칸이 200px 로 부풀어
	##   대여섯 개가 화면을 통째로 차지하고, 그 사이가 텅 비어 보인다.
	const MAX_CW := 168.0
	var shown := bench_shown(cols)
	var rows: int = shown / cols
	var room: float = area.size.y - HEAD1 - GAP - HEAD2 - 6.0
	# 안뜰 칸은 세로 1.30배, 인벤토리 칸은 0.86배. 둘을 합쳐 남은 높이에 맞춘다.
	var cw: float = min(area.size.x / float(cols), MAX_CW,
			room / (1.30 + 0.86 * float(rows)))
	var x0: float = area.position.x + (area.size.x - cw * float(cols)) * 0.5
	var pad := 5.0
	# 세로도 가운데로 모은다. 위로 붙여 놓으면 인벤토리가 비었을 때 아래가 통째로 빈다.
	var used: float = HEAD1 + cw * 1.30 + GAP + HEAD2 + cw * 0.86 * float(rows)
	var y: float = area.position.y + max(0.0, (area.size.y - used) * 0.5)

	Look.text_left(ci, Vector2(area.position.x, y + 10.0),
			"안뜰 — 여기 선 %d명만 싸운다" % Run.heroes.size(), 22, Look.INK)
	Look.text_right(ci, Vector2(area.position.x + area.size.x, y + 10.0),
			"%d / %d 자리" % [Run.heroes.size(), Balance.HERO_SLOTS], 20, Look.INK_DIM)
	y += HEAD1
	var fh: float = cw * 1.30
	for i in range(Balance.HERO_SLOTS):
		_cell(ci, ui, Rect2(x0 + float(i) * cw + pad, y, cw - pad * 2.0, fh), i, true)
	y += fh + GAP

	Look.text_left(ci, Vector2(area.position.x, y + 10.0),
			"캐릭터 인벤토리 %d명" % Run.bench.size(), 22, Look.INK)
	Look.text_right(ci, Vector2(area.position.x + area.size.x, y + 10.0),
			"눌러서 고르고, 바꿀 자리를 한 번 더 누른다", 18, Look.INK_DIM)
	y += HEAD2
	var bh: float = cw * 0.86
	for i in range(shown):
		var c: int = i % cols
		var r: int = i / cols
		_cell(ci, ui, Rect2(x0 + float(c) * cw + pad, y + float(r) * bh,
				cw - pad * 2.0, bh - pad * 2.0), BENCH + i, false)


## 자리 한 칸. 비어 있으면 빈 상자로 그린다.
func _cell(ci: CanvasItem, ui: Ui, r: Rect2, code: int, big: bool) -> void:
	var h := _at(code)
	var id: String = "hv:%s%d" % ["b" if code >= BENCH else "f",
			(code - BENCH) if code >= BENCH else code]
	ui.zone(r, id, true)
	var picked: bool = sel == code
	var is_new: bool = (not h.is_empty()) and new_id != "" \
			and String(h["unit"]["id"]) == new_id

	# ★ 테두리를 먼저, 안을 나중에. outline_round 는 넓힌 네모를 채우는 방식이라
	#   순서를 뒤집으면 테두리가 칸을 통째로 덮는다.
	if picked:
		Look.outline_round(ci, r, 10.0, Look.GOLD, 3.0)
	elif is_new:
		Look.outline_round(ci, r, 10.0, Color(Look.CRYSTAL.r, Look.CRYSTAL.g, Look.CRYSTAL.b,
				0.55 + 0.45 * sin(_t * 6.0)), 3.0)
	elif h.is_empty() and sel >= 0:
		# 무언가를 골라 둔 동안에는 "여기 놓을 수 있다"를 테두리로 알려 준다.
		Look.outline_round(ci, r, 10.0, Color(Look.GOLD.r, Look.GOLD.g, Look.GOLD.b,
				0.35 + 0.25 * sin(_t * 5.0)), 2.0)

	if h.is_empty():
		# ★ 빈 칸도 **칸으로 보여야** 한다. 글자만 띄워 놓으면 상점 배경 위에서
		#   자리가 있는 줄도 모른다 (사진에서 실제로 그렇게 보였다).
		Look.fill_round(ci, r, 10.0, Look.BG_DEEP)
		Look.fill_round(ci, r.grow(-3.0), 8.0,
				Color(Look.PANEL.r, Look.PANEL.g, Look.PANEL.b, 0.55))
		Look.text_center(ci, r.position + r.size * 0.5,
				"여기로" if sel >= 0 else "빈 칸", 18,
				Look.GOLD if sel >= 0 else Look.INK_DIM)
		return

	var u: Dictionary = h["unit"]
	var tier: int = int(h["tier"])
	var tc := Look.tier_color(tier)
	Look.fill_round(ci, r, 10.0, Look.PANEL)

	# 머리띠 — 등급 이름과 겹친 수가 **얼굴 위에 겹치지 않게** 제 자리를 갖는다.
	# ★ 글자 크기는 칸 폭을 따라간다. 고정으로 두면 인벤토리가 다섯 줄까지 차서 칸이
	#   좁아졌을 때 「스트레이트플러시」가 칸을 넘어 옆 칸까지 흘러넘친다.
	var top: float = 22.0 if big else 16.0
	Look.fill_round(ci, Rect2(r.position, Vector2(r.size.x, top)), 8.0, Look.BG_DEEP)
	Look.fill_round(ci, Rect2(r.position, Vector2(r.size.x, 4.0)), 2.0, tc)
	var n: int = int(h.get("n", 1))
	if big:
		Look.text_left(ci, Vector2(r.position.x + 7.0, r.position.y + top * 0.5 + 2.0),
				Roster.TIER_KO[tier], clampi(int(r.size.x * 0.092), 10, 14), tc)
	# 겹친 수 — 이 게임에서 제일 중요한 숫자다. ('×' 는 번들 폰트에 없다)
	if n > 1:
		Look.text_right(ci, Vector2(r.position.x + r.size.x - 7.0,
				r.position.y + top * 0.5 + 2.0), "%d겹" % n,
				clampi(int(r.size.x * 0.12), 12, 18 if big else 15), Look.GOLD)

	# 얼굴 — 머리띠와 이름 사이에 남는 만큼 줄여 그린다.
	var name_h: float = float(clampi(int(r.size.x * 0.145), 12, 20 if big else 17))
	var art_box: float = r.size.y - top - name_h - 6.0
	var nat: float = max(1.0, Art.unit_h(u))
	var sc: float = clampf(art_box / nat, 0.15, 1.6)
	Art.draw_unit(ci, u, r.position.x + r.size.x * 0.5, r.position.y + top + 3.0 + art_box, sc)

	Look.text_center(ci, Vector2(r.position.x + r.size.x * 0.5,
			r.position.y + r.size.y - name_h * 0.5 - 3.0),
			String(u.get("ko", "")), int(name_h), Look.INK)
