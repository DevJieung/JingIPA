## 답 고르기용 커다란 숫자 블록 버튼 하나.
##
## 7~8세 아이의 손가락에 맞춰 최소 200x200 디자인 px 로 만든다(성인 가이드의 약 4배).
## 이미지 에셋 없이 _draw() 로만 그린다 — 아래쪽에 두께 슬래브, 그 위에 윗면,
## 윗면에 하이라이트를 얹어 장난감 블록 같은 입체감을 낸다. 누르면 윗면이
## 슬래브 쪽으로 내려앉아 "꾹 눌리는" 촉감을 준다.
##
## 상호작용은 '한 번 탭' 뿐이다. 드래그/스와이프/더블탭/길게누르기는 쓰지 않는다.
## 오답이라도 버튼을 지우거나 비활성으로 만들지 않는다(찍기를 가르치게 되므로).
## 정답/오답은 색만으로 알리지 않고 항상 체크/엑스 도형을 함께 붙인다.
class_name AnswerButton
extends Control

## 진짜 탭이 일어났을 때 이 버튼의 값을 알린다.
signal pressed_value(v: int)

## 버튼의 표시 상태.
enum State {
	NORMAL,   ## 평소
	PRESSED,  ## 눌린 모습(외부에서 강제로 지정할 때)
	CORRECT,  ## 정답 — 초록 + 체크 배지
	WRONG,    ## 오답 — 부드러운 주황 + 엑스 배지, 짧게 도리도리
	DIMMED,   ## 시연 중 — 살짝 채도만 낮춤(여전히 또렷하게 보인다)
	GLOWING,  ## 무오류 학습 — 금빛 후광이 숨쉬듯 반짝인다
}

## 아동용 최소 터치 타깃(디자인 px). 이보다 작아지지 않는다.
const MIN_TOUCH := 200.0

# --- 그리기에 쓰는 애니메이션 값 (setter 에서 queue_redraw) ------------------ #

## 0 = 떠 있음, 1 = 슬래브에 닿도록 눌림.
var press_amount: float = 0.0:
	set(v):
		press_amount = v
		queue_redraw()

## 전체 확대율 (등장/정답 팝).
var pop_scale: float = 1.0:
	set(v):
		pop_scale = v
		queue_redraw()

## 오답 때 좌우로 살짝 흔드는 양.
var shake_x: float = 0.0:
	set(v):
		shake_x = v
		queue_redraw()

## 체크/엑스 배지의 등장 확대율.
var badge_scale: float = 0.0:
	set(v):
		badge_scale = v
		queue_redraw()

var _value: int = 0
var _state: State = State.NORMAL
var _interactive: bool = true
var _pressing: bool = false
var _phase: float = 0.0
var _fx: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(MIN_TOUCH, MIN_TOUCH)


func _ready() -> void:
	set_process(false)


# --------------------------------------------------------------------------- #
# 공개 API
# --------------------------------------------------------------------------- #

## 버튼에 표시할 수를 정한다.
func set_value(v: int) -> void:
	_value = v
	queue_redraw()


## 현재 표시 중인 수.
func value() -> int:
	return _value


## 표시 상태를 바꾸고 그에 맞는 짧은 연출을 시작한다.
func set_state(s: State) -> void:
	if _state == s:
		return
	_state = s
	_kill_fx()
	shake_x = 0.0
	var d := MathGame.anim_scale()
	match s:
		State.CORRECT:
			badge_scale = 0.0
			_fx = create_tween()
			_fx.set_parallel(true)
			_fx.tween_property(self, "pop_scale", 1.0, 0.55 * d).from(1.22) \
					.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			_fx.tween_property(self, "badge_scale", 1.0, 0.34 * d).from(0.0) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		State.WRONG:
			# 혼내는 느낌이 아니라 "그건 아니야" 정도로 아주 짧게.
			pop_scale = 1.0
			badge_scale = 0.0
			_fx = create_tween()
			_fx.set_parallel(true)
			_fx.tween_property(self, "badge_scale", 1.0, 0.24 * d).from(0.0) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_fx.tween_method(_apply_shake, 0.0, 1.0, 0.42 * d)
		State.PRESSED:
			pop_scale = 1.0
			badge_scale = 0.0
		_:
			pop_scale = 1.0
			badge_scale = 0.0
	# 후광은 트윈이 아니라 _process 위상값으로 돌린다(일회성 트윈과 싸우지 않게).
	set_process(s == State.GLOWING)
	queue_redraw()


## 모든 연출과 상태를 처음으로 되돌린다.
func reset_state() -> void:
	_kill_fx()
	_state = State.NORMAL
	_pressing = false
	press_amount = 0.0
	pop_scale = 1.0
	badge_scale = 0.0
	shake_x = 0.0
	modulate.a = 1.0
	set_process(false)
	queue_redraw()


## 등장 애니메이션. delay 만큼 기다렸다가 통통 튀며 나타난다.
func pop_in(delay: float = 0.0) -> void:
	_kill_fx()
	var d := MathGame.anim_scale()
	pop_scale = 0.0
	modulate.a = 0.0
	_fx = create_tween()
	_fx.set_parallel(true)
	_fx.tween_property(self, "pop_scale", 1.0, 0.46 * d).from(0.0) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay * d)
	_fx.tween_property(self, "modulate:a", 1.0, 0.22 * d).from(0.0) \
			.set_delay(delay * d)


## 입력만 막는다. 겉모습은 거의 그대로라 "없어진/못 누르는 버튼"으로 보이지 않는다.
func set_interactive(on: bool) -> void:
	_interactive = on
	if not on and _pressing:
		_pressing = false
		_release_visual()


## 지금 탭을 받을 수 있는지.
func is_interactive() -> bool:
	return _interactive


## 현재 표시 상태.
func state() -> State:
	return _state


# --------------------------------------------------------------------------- #
# 입력 — 한 번 탭만 처리한다
# --------------------------------------------------------------------------- #

func _gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_begin_press()
		else:
			_end_press(Rect2(Vector2.ZERO, size).has_point(mb.position))
		accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		# 첫 손가락만 본다 — 멀티터치로 여러 답이 동시에 눌리는 사고 방지.
		if st.index != 0:
			return
		if st.pressed:
			_begin_press()
		else:
			_end_press(Rect2(Vector2.ZERO, size).has_point(st.position))
		accept_event()


func _begin_press() -> void:
	# 터치 → 마우스 에뮬레이션 때문에 같은 탭이 두 번 올 수 있어 한 번만 받는다.
	if _pressing:
		return
	_pressing = true
	press_amount = 1.0


func _end_press(inside: bool) -> void:
	if not _pressing:
		return
	_pressing = false
	_release_visual()
	if inside:
		Audio.play("answer_pick")
		pressed_value.emit(_value)


## 눌렸던 윗면이 통통 튀어 올라온다.
func _release_visual() -> void:
	var d := MathGame.anim_scale()
	var tw := create_tween()
	tw.tween_property(self, "press_amount", 0.0, 0.24 * d) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_shake(t: float) -> void:
	shake_x = sin(t * TAU * 2.5) * 11.0 * (1.0 - t)


func _kill_fx() -> void:
	if _fx != null and _fx.is_valid():
		_fx.kill()
	_fx = null


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return

	var depth := maxf(7.0, h * 0.105)          # 블록 두께
	var pad := maxf(2.0, h * 0.015)
	# 원점을 버튼 중앙에 두고 그리면 확대/흔들림을 캔버스 변환 한 번으로 끝낼 수 있다.
	var base := Rect2(-w * 0.5 + pad, -h * 0.5 + pad,
			w - pad * 2.0, h - pad * 2.0 - depth)
	var radius := base.size.y * 0.26

	var sc := pop_scale * _idle_scale()
	if sc <= 0.001:
		return
	draw_set_transform(Vector2(w, h) * 0.5 + Vector2(shake_x, 0.0), 0.0, Vector2(sc, sc))

	var face_col := _face_color()
	var side_col := _side_color()
	var ink_col := _ink_color()

	if _state == State.GLOWING:
		_draw_glow(base, radius)

	var t := _press_t()
	var slab := Rect2(base.position + Vector2(0.0, depth), base.size)
	var face := Rect2(base.position + Vector2(0.0, depth * t * 0.80), base.size)

	# 바닥 그림자 — 누를수록 좁아져서 실제로 내려앉는 느낌을 준다.
	DrawUtil.draw_soft_shadow(self, slab, radius, Palette.SHADOW, 4, 7.0 - 3.0 * t)
	# 두께 슬래브
	DrawUtil.fill_aa(self, DrawUtil.round_rect(slab, radius), side_col)
	# 윗면
	DrawUtil.fill_aa(self, DrawUtil.round_rect(face, radius), face_col)
	# 윗면 하이라이트
	var hl := Rect2(face.position + Vector2(face.size.x * 0.13, face.size.y * 0.10),
			Vector2(face.size.x * 0.74, face.size.y * 0.15))
	DrawUtil.fill_aa(self, DrawUtil.round_rect(hl, hl.size.y * 0.5),
			Palette.with_alpha(Palette.shade(face_col, 0.58), 0.55))

	# 숫자
	var txt := str(_value)
	var fs := _font_size_for(txt, face)
	Fonts.draw_centered_outlined(self, txt, face.get_center(), fs, ink_col,
			Palette.with_alpha(Palette.shade(face_col, 0.5), 0.75),
			maxi(3, int(fs * 0.06)))

	# 정답/오답 배지 — 색만으로 알리지 않기 위한 도형 신호
	if badge_scale > 0.01 and (_state == State.CORRECT or _state == State.WRONG):
		_draw_badge(face)


## 배지: 흰 원판 + 체크(정답) 또는 엑스(오답).
func _draw_badge(face: Rect2) -> void:
	var r := face.size.y * 0.185 * badge_scale
	if r < 1.0:
		return
	var c := Vector2(face.end.x - face.size.y * 0.205,
			face.position.y + face.size.y * 0.205)
	DrawUtil.circle_aa(self, c + Vector2(0.0, r * 0.13),
			r, Color(0, 0, 0, 0.14))
	DrawUtil.circle_aa(self, c, r, Palette.CARD)
	if _state == State.CORRECT:
		Glyphs.draw_check(self, c, r * 1.35, Palette.CORRECT, r * 0.30)
	else:
		Glyphs.draw_cross(self, c, r * 1.30, Palette.WRONG, r * 0.28)


## 무오류 학습용 금빛 후광 — 숨쉬듯 커졌다 작아진다.
func _draw_glow(base: Rect2, radius: float) -> void:
	var puls := 0.5 + 0.5 * sin(_phase * 3.2)
	var layers := 5
	for i in range(layers, 0, -1):
		var g := (7.0 + 15.0 * puls) * float(i) / float(layers)
		var r := Rect2(base.position - Vector2(g, g),
				base.size + Vector2(g, g) * 2.0)
		var a := 0.13 * (1.0 - float(i - 1) / float(layers))
		DrawUtil.fill_aa(self, DrawUtil.round_rect(r, radius + g),
				Palette.with_alpha(Palette.STAR, a))
	var ring := DrawUtil.round_rect(
			Rect2(base.position - Vector2(4.0, 4.0), base.size + Vector2(8.0, 8.0)),
			radius + 4.0)
	DrawUtil.draw_outline(self, ring,
			Palette.with_alpha(Palette.STAR, 0.45 + 0.35 * puls), 5.0)


## 문자열이 윗면 안에 넉넉히 들어가는 글자 크기. 세 자리 수면 자동으로 줄어든다.
func _font_size_for(txt: String, face: Rect2) -> int:
	var fs := int(round(minf(face.size.y * 0.56, face.size.x * 0.58)))
	fs = maxi(fs, 12)
	var max_w := face.size.x * 0.70
	var tw := Fonts.text_width(txt, fs)
	if tw > max_w and tw > 0.0:
		fs = maxi(12, int(round(float(fs) * max_w / tw)))
	return fs


## 눌림 정도 (PRESSED 상태는 항상 눌린 모습).
func _press_t() -> float:
	if _state == State.PRESSED:
		return maxf(press_amount, 1.0)
	return clampf(press_amount, 0.0, 1.0)


## GLOWING 일 때만 아주 살짝 숨쉬는 확대.
func _idle_scale() -> float:
	if _state == State.GLOWING:
		return 1.0 + sin(_phase * 3.2) * 0.022
	return 1.0


## 보기는 초록(Palette.CHOICE)이다. 블록의 항 색(주황/파랑/빨강)과 겹치지 않아야
## "이건 내가 고르는 것"과 "이건 식에 나온 수"가 갈린다.
##
## ★정답 표시는 더 진한 초록(Palette.CORRECT)을 쓴다. 기본 초록과 톤이 같으면
##   맞았는지가 색으로 안 보인다 — 명도 차이 + 체크 배지 둘 다로 구분한다.
func _face_color() -> Color:
	match _state:
		State.CORRECT:
			return Palette.CORRECT
		State.WRONG:
			return Palette.WRONG
		State.DIMMED:
			# 지워지는 게 아니라 살짝 물이 빠진 정도 — 여전히 누를 수 있어 보인다.
			return Palette.shade(Palette.saturate(Palette.CHOICE, 0.5), 0.12)
		State.PRESSED:
			return Palette.shade(Palette.CHOICE, -0.07)
		_:
			return Palette.CHOICE


func _side_color() -> Color:
	match _state:
		State.CORRECT:
			return Palette.shade(Palette.CORRECT, -0.30)
		State.WRONG:
			return Palette.shade(Palette.WRONG, -0.30)
		State.DIMMED:
			return Palette.shade(Palette.saturate(Palette.CHOICE_DARK, 0.5), 0.10)
		_:
			return Palette.CHOICE_DARK


func _ink_color() -> Color:
	match _state:
		State.CORRECT:
			return Palette.CARD
		State.WRONG:
			return Palette.shade(Palette.WRONG, -0.62)
		State.DIMMED:
			return Palette.shade(Palette.CHOICE_TEXT, 0.34)
		_:
			return Palette.CHOICE_TEXT
