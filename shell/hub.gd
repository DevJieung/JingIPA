## 게임 고르는 화면.
##
## ★ 세계관이 없다. 예전에는 "집 안 / 집 밖"이라는 이야기로 두 게임을 묶었는데,
##   숨은그림찾기와 사칙연산은 결이 너무 달라서 이야기가 오히려 이질감을 키웠다.
##   지금은 그냥 **게임 목록**이다 — 카드를 고르거나, 아무거나 누르면 랜덤으로 돈다.
##
## 게임이 늘어도 이 파일은 안 고친다. shell/game_registry.gd 의 배열만 늘리면
## 카드가 저절로 한 장 는다 (2~6개까지 배치가 맞춰진다).
extends Control

const W := 1280.0
const H := 800.0

const BG := Color("f4f2ec")
const BG2 := Color("eae7df")
const INK := Color("2f2a2c")
const INK_SOFT := Color("7d7570")
const CARD := Color("ffffff")
const SHADOW := Color(0, 0, 0, 0.10)
const RANDOM_COL := Color("f2a03d")

## 손가락이 큰 아이 기준. 카드는 이보다 작아지지 않는다.
## ★ 게임이 다섯이 되면 240 을 지킬 수 없다 (240x5 + 여백이 화면을 넘는다).
##   그래서 다섯부터는 여백과 사이를 먼저 줄이고 하한도 200 으로 내린다 — 200 이면
##   여섯 장까지 들어간다. 일곱 번째 게임이 오면 그때는 두 줄로 바꿔야 한다.
const CARD_MIN_W := 240.0
const CARD_MIN_W_MANY := 200.0

var _t := 0.0
var _panel_open := false
var _gear_held := 0.0
var _pressed := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Shell.journey_end()
	Shell.profile_changed.connect(queue_redraw)
	get_viewport().size_changed.connect(queue_redraw)


func _process(delta: float) -> void:
	_t += delta
	if _gear_held > 0.0:
		_gear_held += delta
		if _gear_held >= 1.2:
			_gear_held = 0.0
			Router.goto_parent()
			return
	queue_redraw()


# --------------------------------------------------------------------------- #
# 좌표 — 1280x800 기준으로 그리고 화면에 맞춰 통째로 옮긴다
# --------------------------------------------------------------------------- #

func _scale() -> float:
	return minf(size.x / W, size.y / H)


func _origin() -> Vector2:
	var s := _scale()
	return Vector2((size.x - W * s) * 0.5, (size.y - H * s) * 0.5)


func _to_local(p: Vector2) -> Vector2:
	var s := _scale()
	return Vector2.ZERO if s <= 0.0 else (p - _origin()) / s


## 게임 카드 자리. 개수에 따라 폭이 줄되 CARD_MIN_W 아래로는 안 간다.
func _card_rect(i: int, n: int) -> Rect2:
	var many := n >= 5
	var gap := 16.0 if many else 28.0
	var margin := 34.0 if many else 70.0
	var avail := W - margin * 2.0 - gap * float(maxi(0, n - 1))
	var w := maxf(CARD_MIN_W_MANY if many else CARD_MIN_W, avail / float(maxi(1, n)))
	var total := w * float(n) + gap * float(maxi(0, n - 1))
	var x0 := (W - total) * 0.5
	return Rect2(x0 + float(i) * (w + gap), 190.0, w, 360.0)


func _random_rect() -> Rect2:
	return Rect2(W * 0.5 - 220.0, 600.0, 440.0, 120.0)


func _badge_rect() -> Rect2:
	return Rect2(W - 152.0, 26.0, 118.0, 76.0)


func _gear_rect() -> Rect2:
	return Rect2(30.0, 34.0, 68.0, 60.0)


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #

func _draw() -> void:
	var s := _scale()
	var o := _origin()
	draw_set_transform(o, 0.0, Vector2(s, s))

	draw_rect(Rect2(0, 0, W, H), BG)
	# 아주 옅은 가로 띠 — 배경이 밋밋하지 않게, 그러나 눈에 걸리지 않게
	for i in 9:
		draw_rect(Rect2(0, float(i) * 96.0, W, 48.0), BG2)

	_paint_title()
	var n := GameRegistry.LIST.size()
	for i in n:
		_paint_card(i, n)
	_paint_random()
	_paint_badge()
	_paint_gear()
	if _panel_open:
		_paint_profile_panel()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 기준 화면 바깥 여백을 바탕색으로 (레터박스가 검게 보이지 않게)
	if o.x > 0.5:
		draw_rect(Rect2(0, 0, o.x, size.y), BG)
		draw_rect(Rect2(size.x - o.x, 0, o.x, size.y), BG)
	if o.y > 0.5:
		draw_rect(Rect2(0, 0, size.x, o.y), BG)
		draw_rect(Rect2(0, size.y - o.y, size.x, o.y), BG)


func _paint_title() -> void:
	_text_centered("무엇 하고 놀까?", Vector2(W * 0.5, 118.0), 54, INK)


func _paint_card(i: int, n: int) -> void:
	var g: Dictionary = GameRegistry.LIST[i]
	var r := _card_rect(i, n)
	var col := Color(g.get("color", Color("9ec6f0")))
	var press := 6.0 if _pressed == i else 0.0
	var last := String(Shell.profile().get("last_game", "")) == String(g["id"])

	# 그림자 -> 몸통 -> 위쪽 색띠
	_round_rect(Rect2(r.position + Vector2(0, 8.0 - press), r.size), 26.0, SHADOW)
	_round_rect(Rect2(r.position + Vector2(0, -press), r.size), 26.0, CARD)
	_round_rect(Rect2(r.position.x, r.position.y - press, r.size.x, 96.0), 26.0, col)
	draw_rect(Rect2(r.position.x, r.position.y + 60.0 - press, r.size.x, 36.0), col)

	# 마지막에 놀던 카드는 테두리가 살짝 숨 쉰다 (글자를 못 읽어도 알아본다)
	if last:
		var pulse := 0.5 + 0.5 * sin(_t * 2.2)
		_round_rect_outline(Rect2(r.position + Vector2(-6, -6 - press), r.size + Vector2(12, 12)),
				30.0, Color(col.r, col.g, col.b, 0.35 + 0.35 * pulse), 5.0)

	var cx := r.position.x + r.size.x * 0.5
	var top := r.position.y - press
	_paint_icon(String(g["id"]), Vector2(cx, top + 230.0), r.size.x)
	_text_centered(String(g["title"]), Vector2(cx, top + 62.0), 38, Color("ffffff"))
	_text_centered(String(g.get("subtitle", "")), Vector2(cx, top + 316.0), 21, INK_SOFT)


## 카드 그림 — 전부 코드로 그린다. 공룡만 이미 있는 PNG 를 쓴다.
func _paint_icon(id: String, c: Vector2, w: float) -> void:
	match id:
		"dino":
			var idx := DinoSpecies.index_of("trex")
			var tex := DinoSpecies.texture(idx)
			if tex != null:
				var dr := DinoSpecies.draw_rect_for(idx)
				var sc := minf((w - 70.0) / maxf(dr.size.x, 1.0), 150.0 / maxf(dr.size.y, 1.0))
				draw_texture_rect(tex, Rect2(c + dr.position * sc + Vector2(0, dr.size.y * sc * 0.5),
						dr.size * sc), false)
			else:
				_ellipse(c, Vector2(60, 46), Color("6fbf5a"))
		"math":
			# 십틀 두 줄 — 이 게임의 알맹이가 그대로 그림이 된다
			var cw := 26.0
			for row in 2:
				for col2 in 5:
					var p := Vector2(c.x - cw * 2.5 + float(col2) * cw, c.y - 34.0 + float(row) * (cw + 6.0))
					var on := row * 5 + col2 < 7
					draw_rect(Rect2(p, Vector2(cw - 5.0, cw - 5.0)),
							Color("f2a03d") if on else Color("e2ded6"))
			_text_centered("7", Vector2(c.x, c.y + 58.0), 44, INK)
		"torch":
			# 깜깜한 방 + 손전등 빛 웅덩이 + 그 안에 든 공룡.
			# 이 카드 하나로 "어두운데 비추면 보인다"가 글자 없이 읽혀야 한다.
			# ★ 상자 아래끝은 c.y + 54 까지만. 부제 글자가 c.y + 86 부근에서 시작하므로
			#   더 내려오면 글자를 덮는다 (실제로 한 번 덮었다).
			var bw := minf(184.0, w - 34.0)
			_round_rect(Rect2(c.x - bw * 0.5, c.y - 78.0, bw, 132.0), 16.0, Color("241f3d"))
			var lc := Vector2(c.x + 16.0, c.y + 4.0)
			# 왼쪽 위에서 뻗어 나오는 빛줄기.
			# ★ 네 점을 눈대중으로 찍으면 안 된다 — 축과 거의 나란해져서 폭 4px 짜리
			#   실오라기가 나온다(실제로 그랬다). 축의 **수직** 방향으로 벌려서 만든다.
			var tip := Vector2(c.x - 58.0, c.y - 62.0)
			var ax := (lc - tip).normalized()
			var pp := Vector2(-ax.y, ax.x)
			draw_colored_polygon(PackedVector2Array([
					tip + pp * 7.0, lc + pp * 38.0, lc - pp * 38.0, tip - pp * 7.0]),
					Color(1.0, 0.94, 0.74, 0.11))
			for i in 4:
				draw_circle(lc, 46.0 - 9.0 * float(i), Color(1.0, 0.94, 0.74, 0.085))
			var ti := DinoSpecies.index_of("stegosaurus")
			var ttex := DinoSpecies.texture(ti)
			if ttex != null:
				var tdr := DinoSpecies.draw_rect_for(ti)
				var tsc := minf(76.0 / maxf(tdr.size.x, 1.0), 54.0 / maxf(tdr.size.y, 1.0))
				draw_texture_rect(ttex, Rect2(lc + tdr.position * tsc
						+ Vector2(0, tdr.size.y * tsc * 0.5), tdr.size * tsc), false)
			else:
				_ellipse(lc, Vector2(30, 22), Color("8cc76a"))
			# 손전등 몸통
			_round_rect(Rect2(c.x - 88.0, c.y - 74.0, 32.0, 19.0), 7.0, Color("ffd166"))
		"cham":
			# 가운데 친구, 좌우에서 "이쪽!" 하고 가리키는 손 두 개.
			# ★ 카드 폭 w 에 맞춰 줄인다. 게임이 늘면 카드가 좁아지는데(다섯 장 229px,
			#   여섯 장 200px) 고정 픽셀로 그리면 그림이 카드 밖으로 삐져나간다.
			var k := minf(1.0, (w - 26.0) / 236.0)
			var ci := DinoSpecies.index_of("parasaurolophus")
			var ctex := DinoSpecies.texture(ci)
			if ctex != null:
				var cdr := DinoSpecies.draw_rect_for(ci)
				var csc := minf(104.0 * k / maxf(cdr.size.x, 1.0), 112.0 * k / maxf(cdr.size.y, 1.0))
				draw_texture_rect(ctex, Rect2(c + cdr.position * csc
						+ Vector2(0, cdr.size.y * csc * 0.5), cdr.size * csc), false)
			else:
				_ellipse(c, Vector2(40.0 * k, 34.0 * k), Color("f292b4"))
			for sgn in [-1.0, 1.0]:
				var hc := c + Vector2(sgn * 92.0 * k, 22.0)
				var hd := Vector2(-sgn, 0.0)          # 가운데 친구를 가리킨다
				_round_rect(Rect2(hc.x - 26.0 * k, hc.y - 23.0 * k, 52.0 * k, 46.0 * k),
						16.0 * k, Color("ffd7b0"))
				draw_line(hc + hd * 12.0 * k, hc + hd * 50.0 * k, Color("ffd7b0"), 18.0 * k)
				draw_circle(hc + hd * 50.0 * k, 9.0 * k, Color("ffd7b0"))
		"kanoodle":
			# 격자 위에 조각 두 개
			var g := 22.0
			for gy in 4:
				for gx in 4:
					draw_rect(Rect2(c.x - g * 2.0 + float(gx) * g, c.y - 44.0 + float(gy) * g,
							g - 3.0, g - 3.0), Color("e2ded6"))
			for cell in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]:
				draw_rect(Rect2(c.x - g * 2.0 + cell.x * g, c.y - 44.0 + cell.y * g,
						g - 3.0, g - 3.0), Color("58d168"))
			for cell in [Vector2(2, 2), Vector2(3, 2), Vector2(3, 1)]:
				draw_rect(Rect2(c.x - g * 2.0 + cell.x * g, c.y - 44.0 + cell.y * g,
						g - 3.0, g - 3.0), Color("b83e7f"))
		_:
			_ellipse(c, Vector2(52, 52), Color("bfb8ad"))


## "아무거나!" — 게임을 랜덤으로 이어서 돈다.
func _paint_random() -> void:
	var r := _random_rect()
	var press := 6.0 if _pressed == -2 else 0.0
	_round_rect(Rect2(r.position + Vector2(0, 8.0 - press), r.size), 30.0, SHADOW)
	_round_rect(Rect2(r.position + Vector2(0, -press), r.size), 30.0, RANDOM_COL)
	_text_centered("아무거나!", Vector2(r.position.x + r.size.x * 0.5, r.position.y + 42.0 - press),
			44, Color("ffffff"))
	var best := Shell.journey_best()
	var sub := "%d번째부터 이어서" % best if best > 1 else "게임이 번갈아 나와요"
	_text_centered(sub, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 86.0 - press),
			21, Color(1, 1, 1, 0.85))


func _paint_badge() -> void:
	var r := _badge_rect()
	if Shell.profiles.size() <= 1:
		return
	_round_rect(r, 18.0, Shell.profile_color())
	var i := DinoSpecies.index_of(String(Shell.profile().get("badge_species", "trex")))
	var tex := DinoSpecies.texture(i)
	if tex != null:
		var dr := DinoSpecies.draw_rect_for(i)
		var sc := minf((r.size.x - 14.0) / maxf(dr.size.x, 1.0), (r.size.y - 12.0) / maxf(dr.size.y, 1.0))
		draw_texture_rect(tex, Rect2(r.position + r.size * 0.5
				+ (dr.position + Vector2(0, dr.size.y * 0.5)) * sc, dr.size * sc), false)


func _paint_gear() -> void:
	var r := _gear_rect()
	var c := r.position + r.size * 0.5
	draw_circle(c, 16.0, Color(INK_SOFT, 0.30))
	draw_circle(c, 7.0, BG)
	if _gear_held > 0.0:
		draw_arc(c, 21.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(_gear_held / 1.2, 0.0, 1.0),
				24, INK, 4.0)


func _paint_profile_panel() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.1, 0.09, 0.08, 0.55))
	var n := Shell.profiles.size()
	var cw := 260.0
	var total := float(n) * cw + float(maxi(0, n - 1)) * 60.0
	var x0 := (W - total) * 0.5
	for i in n:
		var p: Dictionary = Shell.profiles[i]
		var r := Rect2(x0 + float(i) * (cw + 60.0), H * 0.5 - 170.0, cw, 340.0)
		var idx := DinoSpecies.index_of(String(p.get("badge_species", "trex")))
		_round_rect(r, 26.0, DinoSpecies.data(idx)["col"])
		if i == Shell.active:
			_round_rect_outline(r, 26.0, INK, 5.0)
		var tex := DinoSpecies.texture(idx)
		if tex != null:
			var dr := DinoSpecies.draw_rect_for(idx)
			var sc := minf((r.size.x - 30.0) / maxf(dr.size.x, 1.0),
					(r.size.y - 40.0) / maxf(dr.size.y, 1.0)) * 1.6
			draw_texture_rect(tex, Rect2(r.position + Vector2(r.size.x * 0.5, r.size.y - 24.0)
					+ dr.position * sc, dr.size * sc), false)


# --------------------------------------------------------------------------- #
# 입력 — 전부 탭 한 번
# --------------------------------------------------------------------------- #

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var p := _to_local(mb.position)
	if mb.pressed:
		_on_press(p)
	else:
		_gear_held = 0.0
		_pressed = -1
		queue_redraw()


func _on_press(p: Vector2) -> void:
	if _panel_open:
		_pick_profile(p)
		_panel_open = false
		queue_redraw()
		return
	if _gear_rect().grow(18.0).has_point(p):
		# 부모 화면은 길게 눌러야 열린다 — 아이의 탭은 짧다.
		_gear_held = 0.001
		return
	if Shell.profiles.size() > 1 and _badge_rect().grow(18.0).has_point(p):
		_panel_open = true
		queue_redraw()
		return
	if _random_rect().grow(14.0).has_point(p):
		_pressed = -2
		queue_redraw()
		Shell.journey_begin()
		return
	var n := GameRegistry.LIST.size()
	for i in n:
		if _card_rect(i, n).grow(10.0).has_point(p):
			_pressed = i
			queue_redraw()
			var id := String(GameRegistry.LIST[i]["id"])
			Shell.profile()["last_game"] = id
			Shell.mark_dirty()
			Router.goto_game(id)
			return


func _pick_profile(p: Vector2) -> void:
	var n := Shell.profiles.size()
	var cw := 260.0
	var total := float(n) * cw + float(maxi(0, n - 1)) * 60.0
	var x0 := (W - total) * 0.5
	for i in n:
		if Rect2(x0 + float(i) * (cw + 60.0), H * 0.5 - 170.0, cw, 340.0).has_point(p):
			Shell.switch_profile(i)
			return


# --------------------------------------------------------------------------- #
# 그리기 도우미 (셸은 게임의 팔레트·도우미를 쓰지 않는다)
# --------------------------------------------------------------------------- #

func _round_rect(r: Rect2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2.0, r.size.y), col)
	draw_rect(Rect2(r.position.x, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	draw_rect(Rect2(r.position.x + r.size.x - rad, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	for corner in [Vector2(rad, rad), Vector2(r.size.x - rad, rad),
			Vector2(rad, r.size.y - rad), Vector2(r.size.x - rad, r.size.y - rad)]:
		draw_circle(r.position + corner, rad, col)


func _round_rect_outline(r: Rect2, rad: float, col: Color, w: float) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [Vector2(rad, rad), Vector2(r.size.x - rad, rad),
			Vector2(r.size.x - rad, r.size.y - rad), Vector2(rad, r.size.y - rad)]
	for i in 4:
		var c: Vector2 = r.position + (corners[i] as Vector2)
		for k in 9:
			var a := -PI + PI * 0.5 * float(i) + PI * 0.5 * float(k) / 8.0
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
	pts.append(pts[0])
	draw_polyline(pts, col, w)


func _text_centered(s: String, at: Vector2, px: int, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(f, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
