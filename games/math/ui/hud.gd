## 전투 화면 상단 바 (뒤로가기 · 스테이지 제목 · 진행 칩 · 하트).
##
## 1280x800(가로 태블릿) 디자인 좌표 기준으로 화면 폭 전체에 걸리며, 높이는 약 88px 이다.
## 세로 화면에서도 폭만 달라질 뿐 그대로 쓴다.
## 이미지 에셋을 전혀 쓰지 않고 _draw() 안에서 전부 코드로 그린다.
##
## 진행도는 이어진 막대가 아니라 "문제 수만큼의 둥근 칩"으로 그린다.
## 아이가 남은 뱀이 몇 마리인지 세어서 확인할 수 있어야 하기 때문이다.
## 시간 제한/카운트다운은 어디에도 없다.
class_name Hud
extends Control

## 뒤로가기 버튼을 눌렀을 때.
signal back_pressed

# --- 레이아웃 상수 (디자인 픽셀) ------------------------------------------- #
## size 를 아직 못 받았을 때만 쓰는 대체값 (Layout.BASE 와 같아야 한다).
const BASE_W := 1280.0
const BASE_H := 800.0
## 바 본체 높이.
const BAR_H := 88.0
## 좌우 여백.
const SIDE_PAD := 12.0
## 노치 아래 여백.
const TOP_GAP := 6.0
## 바 아래 여백 (아래 콘텐츠와 겹치지 않게).
const BOTTOM_GAP := 6.0
## 안전 영역 보정의 상한 — 잘못 읽어도 화면이 무너지지 않게.
const MAX_SAFE_TOP := 120.0

const TITLE_SIZE := 30
const TITLE_MIN_SIZE := 19
const HEART_SIZE := 30.0
const HEART_GAP := 8.0
const BACK_TOUCH_W := 104.0

# --- 상태 ------------------------------------------------------------------- #
var _title: String = ""
var _done: int = 0
var _total: int = 0
## 목숨 개념을 쓰지 않는 모드에서는 하트 줄을 통째로 감춘다.
var show_hearts := true:
	set(v):
		show_hearts = v
		queue_redraw()

var _hearts: int = 3
var _max_hearts: int = 3

## 노치 보정으로 내려야 하는 양 (디자인 픽셀). 데스크톱에서는 0.
var _safe_top: float = 0.0
## 가로 화면에서 노치가 옆에 올 때 좌우로 밀어야 하는 양 (디자인 픽셀).
var _safe_side: float = 0.0

## 대기 애니메이션용 위상 누적기.
var _t: float = 0.0

# 애니메이션 값 (전부 setter 에서 queue_redraw 를 호출한다).
var _back_press: float = 0.0
var _title_in: float = 1.0
var _flash: float = 0.0
var _heart_scale: Array[float] = []
var _heart_alpha: Array[float] = []
var _pip_fill: Array[float] = []
var _pip_boost: Array[float] = []

# 트윈 핸들 (다시 시작할 때 kill 한다 — 어느 것도 await 하지 않는다).
var _back_tw: Tween
var _title_tw: Tween
var _flash_tw: Tween
var _heart_tw: Array[Tween] = []
## 칩의 '차오름'과 '통통 튐'은 **서로 다른 트윈**이다.
##
## ★예전에는 하나로 묶여 있었다. 그래서 마지막 문제를 맞히면
##   `set_progress()` 가 마지막 칩을 채우기 시작한 직후 `pulse_progress()` 가
##   같은 칩을 강조하려고 그 트윈을 죽여서, **마지막 칸이 영영 안 찬 채로**
##   탄이 끝났다 (`pulse_progress` 는 다 풀었을 때 마지막 칩을 가리킨다).
##   이제 강조는 튐 트윈만 건드리므로 차오름은 끝까지 간다.
var _pip_tw: Array[Tween] = []
var _pip_boost_tw: Array[Tween] = []

var _back_held: bool = false
var _first_hearts: bool = true
var _first_progress: bool = true

# 제목 글자 크기 캐시 (매 프레임 재측정하지 않도록).
var _title_fs: int = TITLE_SIZE
var _title_fs_key: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	_compute_safe_insets()
	_ensure_heart_arrays()
	_ensure_pip_arrays()
	_apply_anchors()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)
	set_process(true)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_title_fs_key = ""
		queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	# 현재 문제 칩이 천천히 숨쉬는 것 말고는 상시 애니메이션이 없다.
	if _total > 0 and _done < _total:
		queue_redraw()


# --------------------------------------------------------------------------- #
# 공개 API
# --------------------------------------------------------------------------- #

## 가운데 제목을 바꾼다 (예: "개굴 늪지 · 3탄"). 살짝 떠오르며 나타난다.
func set_title(text: String) -> void:
	if _title == text:
		return
	_title = text
	_title_fs_key = ""
	if _title_tw != null and _title_tw.is_valid():
		_title_tw.kill()
	if not is_inside_tree():
		_title_in = 1.0
		queue_redraw()
		return
	_title_in = 0.0
	_title_tw = create_tween()
	_title_tw.tween_method(_set_title_in, 0.0, 1.0, 0.30 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()


## 이 스테이지의 문제 진행도. total 만큼 칩을 그리고 done 개를 채운다.
func set_progress(done: int, total: int) -> void:
	var new_total := maxi(0, total)
	var new_done := clampi(done, 0, new_total)
	var total_changed := new_total != _total
	var prev_done := _done
	_total = new_total
	_done = new_done
	_ensure_pip_arrays()
	if total_changed or _first_progress:
		# 새 스테이지 — 애니메이션 없이 바로 맞춘다.
		_first_progress = false
		for i in _total:
			_kill_pip_tweens(i)
			_pip_fill[i] = 1.0 if i < _done else 0.0
			_pip_boost[i] = 0.0
		queue_redraw()
		return
	for i in range(prev_done, _done):
		_animate_pip_fill(i)
	for i in range(_done, prev_done):
		_kill_pip_tweens(i)
		_pip_fill[i] = 0.0
		_pip_boost[i] = 0.0
	queue_redraw()


## 남은 하트. 현재 값과의 차이만 애니메이션한다 (줄면 오그라들며 사라짐).
func set_hearts(n: int, max_hearts: int = 3) -> void:
	var mx := clampi(max_hearts, 1, 6)
	var max_changed := mx != _max_hearts
	_max_hearts = mx
	_ensure_heart_arrays()
	var prev := _hearts
	_hearts = clampi(n, 0, _max_hearts)
	if _first_hearts or max_changed or not is_inside_tree():
		_first_hearts = false
		for i in _max_hearts:
			_kill_heart_tween(i)
			_heart_alpha[i] = 1.0 if i < _hearts else 0.0
			_heart_scale[i] = 1.0
		queue_redraw()
		return
	for i in range(_hearts, prev):
		_animate_heart_lose(i)
	for i in range(prev, _hearts):
		_animate_heart_gain(i)
	queue_redraw()


## 하트를 잃은 순간의 강조 — 붉은 잔광과 짧은 흔들림.
func flash_heart_loss() -> void:
	Audio.play("heart_lost")
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	if not is_inside_tree():
		_flash = 0.0
		queue_redraw()
		return
	_flash = 1.0
	_flash_tw = create_tween()
	_flash_tw.tween_method(_set_flash, 1.0, 0.0, 0.55 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 진행 칩에 시선을 끈다 (지금 풀고 있는 칩, 다 풀었으면 마지막 칩).
##
## 다 풀었을 때는 방금 채우기 시작한 그 칩을 가리키게 된다. 그래서 이 강조는
## 차오름 트윈을 건드리지 않고 **튐 트윈만** 바꿔 단다 (`_pip_boost_tw` 주석 참고).
func pulse_progress() -> void:
	if _total <= 0:
		return
	var idx := _done if _done < _total else _total - 1
	_animate_pip_boost(clampi(idx, 0, _total - 1))


## 진행 칩이 전부 다 찼는가 (애니메이션까지 끝났는가).
## 탄을 마무리하기 전에 마지막 칸이 실제로 찼는지 확인하는 데 쓴다.
func progress_settled() -> bool:
	if _total <= 0:
		return true
	for i in mini(_total, _pip_fill.size()):
		var want := 1.0 if i < _done else 0.0
		if absf(_pip_fill[i] - want) > 0.01:
			return false
	return true


## 이 HUD 가 실제로 차지하는 높이 (안전 영역 포함) — 아래 레이아웃 계산용.
func content_height() -> float:
	return _safe_top + TOP_GAP + BAR_H + BOTTOM_GAP


# --------------------------------------------------------------------------- #
# 안전 영역 / 레이아웃
# --------------------------------------------------------------------------- #

## 노치 인셋을 디자인 픽셀로 환산해 `_safe_top` / `_safe_side` 에 넣는다.
## 데스크톱에서는 항상 0.
##
## ★ 가로 화면에서는 노치가 **위가 아니라 옆**에 온다. 세로만 보던 코드를 그대로 두면
##   가로로 든 폰에서 뒤로가기 버튼이 노치 밑으로 들어가 눌리지 않는다.
##   좌우는 어느 쪽에 노치가 올지 (기기를 어느 방향으로 돌렸는지) 알 수 없으므로
##   큰 쪽 값으로 양쪽을 똑같이 밀어 바가 가운데를 유지하게 한다.
func _compute_safe_insets() -> void:
	_safe_top = 0.0
	_safe_side = 0.0
	if not OS.has_feature("mobile"):
		return
	var canvas := get_viewport_rect().size
	if canvas.x <= 1.0 or canvas.y <= 1.0:
		return
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 1.0 or win.y <= 1.0:
		return
	# stretch 배율: 실제 픽셀 / 디자인 픽셀.
	# aspect=expand 에서는 두 축의 배율이 정확히 같으므로 어느 쪽으로 재도 된다.
	var stretch := win.x / canvas.x
	if stretch <= 0.001:
		stretch = win.y / maxf(canvas.y, 1.0)
	if stretch <= 0.001:
		return
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return
	var screen := DisplayServer.screen_get_size()
	# 안전 영역이 화면 전체와 같으면 노치가 없는 기기다.
	var no_top: bool = screen.y > 0 and safe.size.y >= screen.y and safe.position.y <= 0
	var no_side: bool = screen.x > 0 and safe.size.x >= screen.x and safe.position.x <= 0
	if not no_top:
		_safe_top = clampf(float(maxi(safe.position.y, 0)) / stretch, 0.0, MAX_SAFE_TOP)
	if not no_side:
		var left := float(maxi(safe.position.x, 0))
		var right := float(maxi(screen.x - (safe.position.x + safe.size.x), 0))
		_safe_side = clampf(maxf(left, right) / stretch, 0.0, MAX_SAFE_TOP)


func _apply_anchors() -> void:
	# 컨테이너 안에 들어 있으면 부모가 배치하도록 두고 최소 높이만 알린다.
	custom_minimum_size = Vector2(custom_minimum_size.x, content_height())
	if get_parent() is Container:
		return
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = content_height()


func _on_viewport_resized() -> void:
	_compute_safe_insets()
	_apply_anchors()
	_title_fs_key = ""
	queue_redraw()


func _bar_width() -> float:
	return size.x if size.x > 1.0 else BASE_W


func _panel_rect() -> Rect2:
	var w := _bar_width()
	var pad := SIDE_PAD + _safe_side
	return Rect2(pad, _safe_top + TOP_GAP, maxf(w - pad * 2.0, 120.0), BAR_H)


## 뒤로가기 버튼의 터치 영역 — 그려진 아이콘보다 훨씬 크게 잡는다 (>= 88x88).
## 노치가 옆에 있으면 그만큼 안쪽에서 시작한다 (노치 밑은 눌러도 안 먹는다).
func _back_touch_rect() -> Rect2:
	var panel := _panel_rect()
	var h := maxf(BAR_H + TOP_GAP + 12.0, 88.0)
	return Rect2(_safe_side, maxf(panel.position.y - TOP_GAP, 0.0), BACK_TOUCH_W, h)


# --------------------------------------------------------------------------- #
# 입력
# --------------------------------------------------------------------------- #

func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		pos = mb.position
		pressed = mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pos = st.position
		pressed = st.pressed
	else:
		return

	var r := _back_touch_rect()
	if pressed:
		# 터치 → 마우스 에뮬레이션으로 같은 누름이 두 번 오는 것을 막는다.
		if _back_held:
			return
		if r.has_point(pos):
			_back_held = true
			_animate_back_press(true)
			accept_event()
		return

	if not _back_held:
		return
	_back_held = false
	_animate_back_press(false)
	accept_event()
	if r.has_point(pos):
		Audio.play("ui_tap")
		back_pressed.emit()


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #

func _draw() -> void:
	var panel := _panel_rect()
	_draw_panel(panel)
	_draw_back_button(panel)

	var hearts_left := _draw_hearts(panel)
	var content_left := panel.position.x + BACK_TOUCH_W - SIDE_PAD
	var cx := (content_left + hearts_left) * 0.5
	var avail := maxf(hearts_left - content_left - 12.0, 60.0)

	_draw_title(cx, panel.position.y + 30.0, avail)
	_draw_progress(cx, panel.position.y + 64.0, avail)


## 아레나 위에서도 글씨가 읽히도록 깔아주는 반투명 둥근 패널.
func _draw_panel(panel: Rect2) -> void:
	var fill := Palette.with_alpha(Palette.PANEL, 0.80)
	var edge := Palette.with_alpha(Palette.CARD_EDGE, 0.55)
	var shadow := Color(0.0, 0.0, 0.0, 0.10)
	DrawUtil.draw_card(self, panel, 26.0, fill, edge, shadow, 5.0)
	# 위쪽 하이라이트 — 장난감 블록 느낌의 광택.
	var hl := Rect2(panel.position + Vector2(18.0, 6.0),
			Vector2(panel.size.x - 36.0, 12.0))
	DrawUtil.fill_aa(self, DrawUtil.round_rect(hl, 6.0), Color(1.0, 1.0, 1.0, 0.35))


func _draw_back_button(panel: Rect2) -> void:
	var s := 62.0
	var c := Vector2(panel.position.x + 46.0, panel.position.y + BAR_H * 0.5)
	var press_off := 4.0 * _back_press
	var depth := 6.0 - 4.0 * _back_press
	var rect := Rect2(c.x - s * 0.5, c.y - s * 0.5 + press_off, s, s)
	var radius := 20.0

	# 아래쪽 두께(옆면)로 입체감을 만든다.
	var under := Rect2(rect.position + Vector2(0.0, depth), rect.size)
	DrawUtil.fill_aa(self, DrawUtil.round_rect(under, radius), Palette.CARD_EDGE)

	var face := Palette.CARD.lerp(Palette.CARD_EDGE, _back_press * 0.55)
	DrawUtil.fill_stroke(self, DrawUtil.round_rect(rect, radius), face,
			Palette.with_alpha(Palette.INK_SOFT, 0.20), 2.0)

	var hl := Rect2(rect.position + Vector2(s * 0.18, s * 0.13),
			Vector2(s * 0.64, s * 0.15))
	DrawUtil.fill_aa(self, DrawUtil.round_rect(hl, hl.size.y * 0.5),
			Color(1.0, 1.0, 1.0, 0.55 * (1.0 - _back_press * 0.6)))

	Glyphs.draw_back_arrow(self, rect.get_center() + Vector2(-2.0, 0.0), 34.0,
			Palette.INK_SOFT)


func _draw_title(cx: float, cy: float, max_w: float) -> void:
	if _title.is_empty():
		return
	_ensure_title_fs(max_w)
	var a := clampf(_title_in, 0.0, 1.0)
	var y := cy - (1.0 - a) * 6.0
	var ink := Palette.with_alpha(Palette.INK, a)
	var halo := Color(1.0, 1.0, 1.0, 0.85 * a)
	Fonts.draw_centered_outlined(self, _title, Vector2(cx, y), _title_fs, ink, halo, 5)


## 문제 수만큼의 둥근 칩. 푼 것은 초록으로 차고, 지금 푸는 것은 천천히 숨쉰다.
func _draw_progress(cx: float, cy: float, max_w: float) -> void:
	if _total <= 0:
		return
	var gap := 5.0
	var n := float(_total)
	var pw := clampf((max_w - gap * (n - 1.0)) / n, 6.0, 26.0)
	var ph := 9.0
	var span := pw * n + gap * (n - 1.0)
	var x0 := cx - span * 0.5
	var track := Palette.with_alpha(Palette.INK_SOFT, 0.22)

	for i in _total:
		var px := x0 + pw * 0.5 + float(i) * (pw + gap)
		var fill_t: float = _pip_fill[i] if i < _pip_fill.size() else 0.0
		var boost: float = _pip_boost[i] if i < _pip_boost.size() else 0.0
		var breathe := 0.0
		if i == _done and _done < _total:
			breathe = 0.5 + 0.5 * sin(_t * 3.0)

		var sx := 1.0 + boost * 0.30 + breathe * 0.05
		var sy := 1.0 + boost * 0.85 + breathe * 0.20
		var rect := Rect2(px - pw * 0.5 * sx, cy - ph * 0.5 * sy, pw * sx, ph * sy)
		var rr := minf(rect.size.x, rect.size.y) * 0.5

		DrawUtil.fill_aa(self, DrawUtil.round_rect(rect, rr, 4), track)

		if fill_t > 0.01:
			var fr := rect
			fr.size.x = rect.size.x * fill_t
			fr.position.x = px - fr.size.x * 0.5
			var fr_r := minf(fr.size.x, fr.size.y) * 0.5
			DrawUtil.fill_aa(self, DrawUtil.round_rect(fr, fr_r, 4), Palette.CORRECT)
			if fr.size.x > 6.0:
				var top := Rect2(fr.position + Vector2(fr.size.x * 0.18, fr.size.y * 0.16),
						Vector2(fr.size.x * 0.64, fr.size.y * 0.24))
				DrawUtil.fill_aa(self, DrawUtil.round_rect(top, top.size.y * 0.5, 3),
						Palette.with_alpha(Palette.CORRECT_LIGHT, 0.85))
		elif i == _done:
			# 지금 풀고 있는 문제 — 테두리만 은은하게 밝아진다.
			var glow := Palette.with_alpha(Palette.CORRECT, 0.30 + 0.40 * breathe)
			DrawUtil.draw_outline(self, DrawUtil.round_rect(rect, rr, 4), glow, 2.2)


## 하트를 그리고, 하트 영역의 왼쪽 x 좌표를 돌려준다 (가운데 폭 계산용).
func _draw_hearts(panel: Rect2) -> float:
	var step := HEART_SIZE + HEART_GAP
	var right := panel.position.x + panel.size.x - 16.0
	if not show_hearts:
		# 자리도 차지하지 않게 해서 제목이 가운데를 넓게 쓰도록 한다.
		return right
	var first_cx := right - HEART_SIZE * 0.5 - float(_max_hearts - 1) * step
	var cy := panel.position.y + BAR_H * 0.5
	var shake := sin(_t * 46.0) * 4.0 * _flash

	if _flash > 0.003:
		var mid := (first_cx + right - HEART_SIZE * 0.5) * 0.5 + shake
		var rx := float(_max_hearts - 1) * step * 0.5 + HEART_SIZE * 0.5 + 14.0
		DrawUtil.ellipse_aa(self, Vector2(mid, cy), Vector2(rx, 26.0),
				Palette.with_alpha(Palette.HEART, 0.30 * _flash), 26)

	for i in _max_hearts:
		var c := Vector2(first_cx + float(i) * step + shake, cy)
		# 빈 하트는 항상 자리에 남아 있어서 "몇 칸이 있었는지" 가 보인다.
		Glyphs.draw_heart(self, c, HEART_SIZE, Palette.with_alpha(Palette.HEART_EMPTY, 0.55),
				Palette.with_alpha(Palette.INK_SOFT, 0.28), 2.0)
		var a: float = _heart_alpha[i] if i < _heart_alpha.size() else 0.0
		if a <= 0.004:
			continue
		var sc: float = _heart_scale[i] if i < _heart_scale.size() else 1.0
		var hs := HEART_SIZE * maxf(sc, 0.02)
		Glyphs.draw_heart(self, c, hs, Palette.with_alpha(Palette.HEART, a),
				Palette.with_alpha(Palette.shade(Palette.HEART, -0.32), a), 2.4)
		DrawUtil.circle_aa(self, c + Vector2(-hs * 0.20, -hs * 0.16), hs * 0.09,
				Color(1.0, 1.0, 1.0, 0.70 * a))

	return first_cx - HEART_SIZE * 0.5 - 10.0


func _ensure_title_fs(max_w: float) -> void:
	var key := "%s|%d" % [_title, int(max_w)]
	if key == _title_fs_key:
		return
	_title_fs_key = key
	var fs := TITLE_SIZE
	while fs > TITLE_MIN_SIZE and Fonts.text_width(_title, fs) > max_w:
		fs -= 1
	_title_fs = fs


# --------------------------------------------------------------------------- #
# 애니메이션
# --------------------------------------------------------------------------- #

func _animate_back_press(down: bool) -> void:
	if _back_tw != null and _back_tw.is_valid():
		_back_tw.kill()
	var target := 1.0 if down else 0.0
	if not is_inside_tree():
		_set_back_press(target)
		return
	var dur := (0.07 if down else 0.18) * MathGame.anim_scale()
	_back_tw = create_tween()
	_back_tw.tween_method(_set_back_press, _back_press, target, dur) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate_pip_fill(index: int) -> void:
	if index < 0 or index >= _pip_fill.size():
		return
	_kill_pip_tweens(index)
	if not is_inside_tree():
		_pip_fill[index] = 1.0
		_pip_boost[index] = 0.0
		queue_redraw()
		return
	var sc := MathGame.anim_scale()
	var fill_tw := create_tween()
	_pip_tw[index] = fill_tw
	fill_tw.tween_method(_set_pip_fill.bind(index), 0.0, 1.0, 0.26 * sc) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var boost_tw := create_tween()
	_pip_boost_tw[index] = boost_tw
	boost_tw.tween_method(_set_pip_boost.bind(index), 1.0, 0.0, 0.46 * sc) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## 튐만 다시 준다. 차오르는 중인 칩이라도 차오름은 그대로 끝까지 간다.
func _animate_pip_boost(index: int) -> void:
	if index < 0 or index >= _pip_boost.size():
		return
	_kill_pip_boost_tween(index)
	if not is_inside_tree():
		return
	var tw := create_tween()
	_pip_boost_tw[index] = tw
	tw.tween_method(_set_pip_boost.bind(index), 1.0, 0.0, 0.50 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _animate_heart_lose(index: int) -> void:
	if index < 0 or index >= _heart_scale.size():
		return
	_kill_heart_tween(index)
	if not is_inside_tree():
		_heart_alpha[index] = 0.0
		_heart_scale[index] = 1.0
		queue_redraw()
		return
	var tw := create_tween()
	_heart_tw[index] = tw
	# 한 개의 0~1 구동값으로 "부풀었다가 쪼그라들며 사라진다" 를 전부 표현한다.
	tw.tween_method(_set_heart_lose.bind(index), 0.0, 1.0, 0.48 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_LINEAR)


func _animate_heart_gain(index: int) -> void:
	if index < 0 or index >= _heart_scale.size():
		return
	_kill_heart_tween(index)
	if not is_inside_tree():
		_heart_alpha[index] = 1.0
		_heart_scale[index] = 1.0
		queue_redraw()
		return
	_heart_alpha[index] = 1.0
	_heart_scale[index] = 0.0
	var tw := create_tween()
	_heart_tw[index] = tw
	tw.tween_method(_set_heart_scale.bind(index), 0.0, 1.0, 0.52 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# --- 애니메이션 setter (전부 queue_redraw) ---------------------------------- #

func _set_back_press(v: float) -> void:
	_back_press = clampf(v, 0.0, 1.0)
	queue_redraw()


func _set_title_in(v: float) -> void:
	_title_in = clampf(v, 0.0, 1.0)
	queue_redraw()


func _set_flash(v: float) -> void:
	_flash = clampf(v, 0.0, 1.0)
	queue_redraw()


func _set_pip_fill(v: float, index: int) -> void:
	if index < 0 or index >= _pip_fill.size():
		return
	_pip_fill[index] = clampf(v, 0.0, 1.0)
	queue_redraw()


func _set_pip_boost(v: float, index: int) -> void:
	if index < 0 or index >= _pip_boost.size():
		return
	_pip_boost[index] = clampf(v, 0.0, 1.6)
	queue_redraw()


func _set_heart_scale(v: float, index: int) -> void:
	if index < 0 or index >= _heart_scale.size():
		return
	_heart_scale[index] = maxf(v, 0.0)
	queue_redraw()


func _set_heart_lose(t: float, index: int) -> void:
	if index < 0 or index >= _heart_scale.size():
		return
	var u := clampf(t, 0.0, 1.0)
	if u < 0.25:
		# 먼저 살짝 부푼다 (아이가 "아, 하나 잃었구나" 를 알아채도록).
		var k := DrawUtil.ease_out_cubic(u / 0.25)
		_heart_scale[index] = lerpf(1.0, 1.45, k)
		_heart_alpha[index] = 1.0
	else:
		var k2 := (u - 0.25) / 0.75
		_heart_scale[index] = lerpf(1.45, 0.10, DrawUtil.ease_in_out_cubic(k2))
		_heart_alpha[index] = 1.0 - DrawUtil.ease_out_cubic(k2)
	queue_redraw()


# --------------------------------------------------------------------------- #
# 배열 / 트윈 관리
# --------------------------------------------------------------------------- #

func _ensure_heart_arrays() -> void:
	var n := maxi(_max_hearts, 1)
	if _heart_scale.size() == n and _heart_alpha.size() == n and _heart_tw.size() == n:
		return
	for i in range(n, _heart_tw.size()):
		_kill_heart_tween(i)
	var old := _heart_scale.size()
	_heart_scale.resize(n)
	_heart_alpha.resize(n)
	_heart_tw.resize(n)
	for i in range(old, n):
		_heart_scale[i] = 1.0
		_heart_alpha[i] = 1.0 if i < _hearts else 0.0


func _ensure_pip_arrays() -> void:
	var n := maxi(_total, 0)
	if _pip_fill.size() == n and _pip_boost.size() == n and _pip_tw.size() == n \
			and _pip_boost_tw.size() == n:
		return
	for i in range(n, maxi(_pip_tw.size(), _pip_boost_tw.size())):
		_kill_pip_tweens(i)
	var old := _pip_fill.size()
	_pip_fill.resize(n)
	_pip_boost.resize(n)
	_pip_tw.resize(n)
	_pip_boost_tw.resize(n)
	for i in range(old, n):
		_pip_fill[i] = 0.0
		_pip_boost[i] = 0.0


func _kill_heart_tween(index: int) -> void:
	if index < 0 or index >= _heart_tw.size():
		return
	var tw := _heart_tw[index]
	if tw != null and tw.is_valid():
		tw.kill()
	_heart_tw[index] = null


func _kill_pip_tweens(index: int) -> void:
	_kill_pip_fill_tween(index)
	_kill_pip_boost_tween(index)


func _kill_pip_fill_tween(index: int) -> void:
	if index < 0 or index >= _pip_tw.size():
		return
	var tw := _pip_tw[index]
	if tw != null and tw.is_valid():
		tw.kill()
	_pip_tw[index] = null


func _kill_pip_boost_tween(index: int) -> void:
	if index < 0 or index >= _pip_boost_tw.size():
		return
	var tw := _pip_boost_tw[index]
	if tw != null and tw.is_valid():
		tw.kill()
	_pip_boost_tw[index] = null
