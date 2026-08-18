## 로딩 화면 — 게임을 켜면 가장 먼저 나오는 화면.
##
## 로고가 부드럽게 떠올랐다가 타이틀로 넘어간다.
## 로고 그림(assets/art/logo.png)이 없으면 글자만으로도 성립하게 만들어 뒀다.
extends Control

const HOLD := 1.5      # 로고를 보여주는 시간(초)
const FADE := 0.45

var _t := 0.0
var _appear := 0.0:
	set(v):
		_appear = v
		queue_redraw()
var _fade_out := 0.0:
	set(v):
		_fade_out = v
		queue_redraw()
var _done := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(self, "_appear", 1.0, FADE) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD)
	tw.tween_callback(_leave)
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _leave() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "_fade_out", 1.0, FADE)
	tw.tween_callback(Router.goto_title)


## 아무 데나 누르면 바로 넘어간다 (매번 기다리게 하지 않는다).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_leave()
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# 하늘색 -> 연둣빛으로 은은한 세로 그라데이션 (띠로 근사).
	var bands := 22
	for i in bands:
		var t := float(i) / float(bands - 1)
		var c := Palette.SKY_TOP.lerp(Palette.SKY_BOTTOM, t)
		draw_rect(Rect2(0.0, size.y * float(i) / float(bands),
				size.x, size.y / float(bands) + 1.0), c)

	var a := clampf(_appear, 0.0, 1.0)
	var pop := DrawUtil.ease_out_back(a)
	var cx := size.x * 0.5
	var cy := size.y * 0.44
	var bob := sin(_t * 1.8) * 6.0

	var logo: Texture2D = null   # ★ 로고 그림은 없앴다 — 아래 코드 드로잉으로 대체된다
	if logo != null:
		var h := minf(size.y * 0.34, size.x * 0.62)
		Art.draw_fit(self, logo, Vector2(cx, cy + bob), h * (0.6 + 0.4 * pop),
				Color(1, 1, 1, a))
	else:
		# 그림이 아직 없을 때: 금색 원 안에 글자.
		var rad := minf(size.x * 0.24, size.y * 0.16) * (0.6 + 0.4 * pop)
		DrawUtil.circle_aa(self, Vector2(cx, cy + bob), rad,
				Palette.with_alpha(Palette.HELMET, a))
		DrawUtil.circle_aa(self, Vector2(cx, cy + bob), rad * 0.86,
				Palette.with_alpha(Palette.shade(Palette.HELMET, 0.35), a))
		Fonts.draw_centered(self, "10", Vector2(cx, cy + bob),
				int(rad * 0.55), Palette.with_alpha(Palette.INK, a))

	var title := Loc.t("game_title")
	var tfs := 46
	while tfs > 24 and Fonts.text_width(title, tfs) > size.x - 60.0:
		tfs -= 2
	Fonts.draw_centered_outlined(self, title,
			Vector2(cx, size.y * 0.72), tfs,
			Palette.with_alpha(Palette.FROG_BODY_DARK, a), Palette.with_alpha(Palette.CARD, a), 10)

	# 로딩 점 세 개
	for i in 3:
		var ph := fposmod(_t * 2.2 - float(i) * 0.35, 2.0)
		var s := 1.0 + 0.55 * maxf(0.0, sin(ph * PI))
		DrawUtil.circle_aa(self, Vector2(cx - 34.0 + float(i) * 34.0, size.y * 0.80),
				8.0 * s, Palette.with_alpha(Palette.INK_SOFT, 0.55 * a))

	if _fade_out > 0.001:
		draw_rect(r, Color(0.06, 0.10, 0.08, _fade_out))
