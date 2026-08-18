## 게임 전체에서 쓰는 커다란 블록 버튼.
##
## 아이용이라 터치 영역을 크게 잡는다 (최소 높이 96, 아이콘 전용도 96x96).
## 눌리면 윗면이 아랫면 두께 위로 내려앉는 장난감 버튼 느낌.
class_name BigButton
extends Control

signal pressed

enum Icon { NONE, BACK, GEAR, REPLAY, SPEAKER_ON, SPEAKER_OFF, STAR, LOCK, PLAY }

const MIN_H := 96.0
const DEPTH := 9.0
## 글자를 줄일 수 있는 하한. 이보다 작으면 7~8세가 읽기 힘들다.
const MIN_FONT := 22

var text := "":
	set(v):
		text = v
		queue_redraw()

var icon: Icon = Icon.NONE:
	set(v):
		icon = v
		queue_redraw()

var face_color := Palette.BTN:
	set(v):
		face_color = v
		queue_redraw()

var text_color := Palette.BTN_TEXT:
	set(v):
		text_color = v
		queue_redraw()

var font_size := 38:
	set(v):
		font_size = v
		queue_redraw()

var round_shape := false:
	set(v):
		round_shape = v
		queue_redraw()

var enabled := true:
	set(v):
		enabled = v
		queue_redraw()

var _press := 0.0:
	set(v):
		_press = v
		queue_redraw()

var _pop := 1.0:
	set(v):
		_pop = v
		queue_redraw()

var _held := false


static func make(label: String, tint: Color = Palette.BTN,
		ic: Icon = Icon.NONE) -> BigButton:
	var b := BigButton.new()
	b.text = label
	b.face_color = tint
	b.icon = ic
	b.custom_minimum_size = Vector2(120, MIN_H)
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(120, MIN_H)
	pivot_offset = size * 0.5
	resized.connect(func(): pivot_offset = size * 0.5)


func pop_in(delay: float = 0.0) -> void:
	_pop = 0.0
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(self, "_pop", 1.0, 0.34 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_held = true
			_tween_press(1.0, 0.06)
		elif _held:
			_held = false
			_tween_press(0.0, 0.12)
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				Audio.play("ui_tap")
				pressed.emit()
		accept_event()
	elif event is InputEventMouseMotion and _held:
		if not Rect2(Vector2.ZERO, size).has_point(event.position):
			_held = false
			_tween_press(0.0, 0.12)


func _tween_press(v: float, t: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_press", v, t * MathGame.anim_scale())


func _draw() -> void:
	var s := clampf(_pop, 0.001, 2.0)
	var full := Rect2(Vector2.ZERO, size)
	if s < 0.999:
		var inset := size * (1.0 - s) * 0.5
		full = Rect2(inset, size * s)
	var depth := DEPTH * s
	var face := Rect2(full.position, Vector2(full.size.x, full.size.y - depth))
	face.position.y += depth * _press

	var radius := (face.size.y * 0.5) if round_shape else minf(28.0, face.size.y * 0.36)
	var fc := face_color if enabled else Palette.BTN_GREY
	var side := Palette.shade(fc, -0.30)
	var tc := text_color if enabled else Palette.shade(Palette.INK_SOFT, 0.15)

	# 아랫면(두께)
	DrawUtil.fill_aa(self, DrawUtil.round_rect(
			Rect2(full.position + Vector2(0, depth * 0.4),
					Vector2(full.size.x, full.size.y - depth * 0.4)), radius), side)
	# 윗면
	DrawUtil.fill_aa(self, DrawUtil.round_rect(face, radius), fc)
	# 하이라이트
	var hl := Rect2(face.position + Vector2(face.size.x * 0.10, face.size.y * 0.12),
			Vector2(face.size.x * 0.80, face.size.y * 0.20))
	DrawUtil.fill_aa(self, DrawUtil.round_rect(hl, hl.size.y * 0.5),
			Palette.with_alpha(Palette.shade(fc, 0.55), 0.75))

	var cx := face.position.x + face.size.x * 0.5
	var cy := face.position.y + face.size.y * 0.5
	var icon_size := minf(face.size.y * 0.56, 56.0)

	if icon != Icon.NONE and text == "":
		_draw_icon(Vector2(cx, cy), icon_size, tc)
		return
	if icon != Icon.NONE:
		var fs := _fit_font(face.size.x - icon_size - 40.0)
		var tw := Fonts.text_width(text, fs)
		var total := icon_size + 16.0 + tw
		_draw_icon(Vector2(cx - total * 0.5 + icon_size * 0.5, cy), icon_size, tc)
		Fonts.draw_centered(self, text,
				Vector2(cx - total * 0.5 + icon_size + 16.0 + tw * 0.5, cy),
				fs, tc)
		return
	Fonts.draw_centered(self, text, Vector2(cx, cy), _fit_font(face.size.x - 24.0), tc)


## 버튼 폭을 넘지 않는 글자 크기.
##
## 버튼은 폭이 화면 배치마다 달라지는데(가로에서는 세로보다 좁다) 글자는 고정이라,
## 줄이지 않으면 "설명 건너뛰기: 켬" 같은 긴 라벨이 버튼 밖으로 삐져나와
## 옆 버튼의 글자와 겹친다. 잘라내지 않고 줄이는 이유는, 이 나이대에는
## 말줄임표(…)가 글자보다 먼저 눈에 들어와서 무슨 버튼인지 못 읽기 때문이다.
func _fit_font(avail: float) -> int:
	if text == "" or avail <= 8.0:
		return font_size
	var fs := font_size
	while fs > MIN_FONT and Fonts.text_width(text, fs) > avail:
		fs -= 2
	return fs


func _draw_icon(c: Vector2, s: float, col: Color) -> void:
	match icon:
		Icon.BACK:
			Glyphs.draw_back_arrow(self, c, s, col)
		Icon.GEAR:
			Glyphs.draw_gear(self, c, s * 0.5, col)
		Icon.REPLAY:
			Glyphs.draw_replay(self, c, s, col)
		Icon.SPEAKER_ON:
			Glyphs.draw_speaker(self, c, s, col, false)
		Icon.SPEAKER_OFF:
			Glyphs.draw_speaker(self, c, s, col, true)
		Icon.STAR:
			Glyphs.draw_star(self, c, s * 0.5, Palette.STAR, Palette.shade(Palette.STAR, -0.35), 3.0)
		Icon.LOCK:
			Glyphs.draw_lock(self, c, s, col)
		Icon.PLAY:
			var pts := PackedVector2Array([
				c + Vector2(-s * 0.24, -s * 0.32),
				c + Vector2(s * 0.34, 0.0),
				c + Vector2(-s * 0.24, s * 0.32),
			])
			DrawUtil.fill_aa(self, pts, col)
		_:
			pass
