extends Node2D

## 소개 영상의 자막·여닫는 판·컷 사이의 검은 막을 그린다. `tests/demo.gd` 전용이다.
##
## ★ 게임과 **같은 폰트·같은 색**으로 그린다(`Look`). 영상 편집기로 따로 얹으면 자막만
##   다른 게임처럼 보이고, 무엇보다 이 머신에는 화면이 없어서 편집기를 못 띄운다.
## ★ 자막 띠는 **왼쪽에 붙는 알약**이다. 화면 폭을 다 쓰면 전투 화면 오른쪽 정보판
##   (막대 여섯 줄)을 덮는데, 그 판이 이 게임에서 제일 보여 주고 싶은 것 중 하나다.

var demo = null

const PAD := 22.0
const BAND_Y := 700.0
const BAND_H := 78.0


func _draw() -> void:
	if demo == null:
		return
	# ★ 검은 막이 **먼저**다. 여는 판과 닫는 판은 그 검은 막 위에 뜨는 글자라서,
	#   막을 나중에 그리면 큰 글자가 통째로 덮인다(실제로 앞 300프레임이 새까맸다).
	#   자막 띠는 컷 전에 언제나 `_hush()` 로 내리므로 막보다 위에 있어도 안전하다.
	var v: float = float(demo.veil)
	if v > 0.002:
		draw_rect(Rect2(0, 0, demo.W, demo.H), Color(0, 0, 0, v))
	_draw_band()
	_draw_card()


## 아래쪽 자막 띠.
func _draw_band() -> void:
	var a: float = float(demo.cap_a)
	if a <= 0.004:
		return
	var title: String = String(demo.cap_title)
	var sub: String = String(demo.cap_sub)
	var num: String = "%d / %d" % [int(demo.cap_no), int(demo.cap_all)]

	var w := maxf(Look.text_width(title, 30), Look.text_width(sub, 20))
	w = maxf(w, 240.0) + PAD * 2.0 + 96.0
	w = minf(w, 1120.0)
	# 올라오면서 나타난다 — 그냥 켜지면 자막이 화면에 "붙어 있는" 것으로 보인다.
	var rise := (1.0 - a) * 16.0
	var r := Rect2(56.0, BAND_Y + rise, w, BAND_H)

	Look.fill_round(self, Rect2(r.position + Vector2(0, 5), r.size), 12.0,
			Color(0, 0, 0, 0.42 * a))
	Look.fill_round(self, r, 12.0, Color(Look.BG_DEEP, 0.90 * a))
	Look.outline_round(self, r, 12.0, Color(Look.PANEL_EDGE, 0.85 * a), 2.0)
	# 금색 세로 막대 — 「지금 몇 번째 장면인가」를 세는 눈금이다.
	draw_rect(Rect2(r.position.x + 14.0, r.position.y + 14.0, 5.0, r.size.y - 28.0),
			Color(Look.GOLD, 0.95 * a))

	var x := r.position.x + 34.0
	Look.text_left(self, Vector2(x, r.position.y + 32.0), title, 30, Color(Look.INK, a))
	Look.text_left(self, Vector2(x, r.position.y + 60.0), sub, 20,
			Color(Look.INK_DIM, 0.95 * a))
	Look.text_right(self, Vector2(r.position.x + r.size.x - 18.0, r.position.y + 26.0),
			num, 17, Color(Look.GOLD_DEEP, a))


## 여는 판 · 닫는 판 — 화면 한가운데 큰 글자.
func _draw_card() -> void:
	var a: float = float(demo.card_a)
	if a <= 0.004:
		return
	var cx: float = demo.W * 0.5
	var cy: float = demo.H * 0.5
	# 글자가 읽히게 화면을 한 겹 눌러 준다.
	draw_rect(Rect2(0, 0, demo.W, demo.H), Color(Look.BG_DEEP, 0.80 * a))

	var t: String = String(demo.card_t)
	var s: String = String(demo.card_s)
	# 조금 커지면서 나타난다.
	var k := 0.965 + 0.035 * a
	draw_set_transform(Vector2(cx, cy), 0.0, Vector2(k, k))
	# ★ 금색 줄은 68px 글자의 **아래 상자 밖**에 둔다. 14px 에 그었더니 「올인 디펜스」의
	#   받침을 가로질러서 밑줄 그은 것처럼 보였다.
	Look.text_center(self, Vector2(0, -26), t, 68, Color(Look.GOLD, a))
	draw_rect(Rect2(-150.0, 32.0, 300.0, 2.0), Color(Look.GOLD_DEEP, 0.9 * a))
	Look.text_center(self, Vector2(0, 80), s, 23, Color(Look.INK_DIM, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
