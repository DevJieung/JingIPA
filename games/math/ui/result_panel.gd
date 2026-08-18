## 결과/알림 오버레이. 탄 클리어, 오늘의 마무리, 확인 창에 모두 쓴다.
##
## 글자 수 규칙을 지킨다: 한 화면 12어절 이하, 한 문장 6어절 이하, 최대 2문장.
## 아이는 읽는 데 쓰는 1초마다 수학에서 멀어진다.
class_name ResultPanel
extends Control

signal action(id: String)

const STAR_R := 40.0

## 상자 아래가 넘어서면 안 되는 y. 0 이면 제한 없음(화면 가운데).
##
## 부모 관문처럼 **패널 아래에 답 판이 같이 뜨는 화면**에서 쓴다. 가운데에 두면
## 답 버튼이 패널의 '닫기' 를 덮어 관문에서 빠져나올 수가 없다.
## 비율(0~1)이 아니라 y 좌표를 받는 이유: 부르는 쪽은 답 판이 어디 있는지는 알아도
## 이 패널이 얼마나 높은지는 모른다. 높이를 아는 쪽이 계산해야 화면 비율이 바뀌어도
## 저절로 맞는다.
var max_bottom := 0.0:
	set(v):
		max_bottom = maxf(v, 0.0)
		_relayout()
		queue_redraw()

var _title := ""
var _lines: PackedStringArray = []
var _stars := -1              # -1 이면 별을 그리지 않는다
var _star_shown := 0
var _buttons: Array[BigButton] = []
var _box: Rect2 = Rect2()
var _appear := 0.0:
	set(v):
		_appear = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## buttons: [{"id": "next", "label": "다음 탄", "color": Color, "icon": BigButton.Icon}, ...]
func show_panel(title: String, lines: PackedStringArray, stars: int,
		buttons: Array) -> void:
	_title = title
	_lines = lines
	_stars = stars
	_star_shown = 0
	visible = true
	_clear_buttons()

	for b in buttons:
		var btn := BigButton.make(String(b.get("label", "")),
				b.get("color", Palette.BTN),
				b.get("icon", BigButton.Icon.NONE))
		var id := String(b.get("id", ""))
		btn.pressed.connect(func(): action.emit(id))
		add_child(btn)
		_buttons.append(btn)

	_relayout()
	_appear = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_appear", 1.0, 0.34 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in _buttons.size():
		_buttons[i].pop_in(0.20 + float(i) * 0.08)

	if _stars > 0:
		_reveal_stars()


func hide_panel() -> void:
	visible = false
	_clear_buttons()


func _clear_buttons() -> void:
	for b in _buttons:
		if is_instance_valid(b):
			b.queue_free()
	_buttons.clear()


func _reveal_stars() -> void:
	for i in _stars:
		await get_tree().create_timer(0.34 * MathGame.anim_scale() + float(i) * 0.30).timeout
		if not is_inside_tree() or not visible:
			return
		_star_shown = i + 1
		Audio.play("star", 1.0 + float(i) * 0.12)
		var c := _star_center(i)
		Fx.star_burst(self, c, 8)
		queue_redraw()


func _star_center(i: int) -> Vector2:
	var gap := STAR_R * 2.4
	var start := _box.position.x + _box.size.x * 0.5 - gap
	return Vector2(start + gap * float(i), _box.position.y + 172.0)


func _relayout() -> void:
	# v_align 이 트리에 들어가기 전에 대입될 수 있다 — 그때는 뷰포트를 볼 수 없다.
	if not is_inside_tree():
		return
	# _ready() 시점에는 부모 Control 의 size 가 아직 0이라 여기서 뷰포트를 직접 본다.
	# (이걸 안 하면 패널이 화면 왼쪽 밖으로 튀어나가 글자가 잘려 보인다.)
	var vp := get_viewport_rect().size
	if size.x < 8.0 or size.y < 8.0:
		size = vp
		position = Vector2.ZERO
	var w := minf(maxf(size.x, 320.0) - 72.0, 600.0)
	var has_stars := _stars >= 0
	var h := 190.0 + float(_lines.size()) * 46.0 + float(_buttons.size()) * 116.0
	if has_stars:
		h += 110.0
	h = clampf(h, 240.0, maxf(280.0, size.y - 120.0))
	var top := (size.y - h) * 0.5
	if max_bottom > 0.0:
		top = minf(top, max_bottom - h)
	_box = Rect2(maxf(0.0, (size.x - w) * 0.5), maxf(0.0, top), w, h)

	var y := _box.position.y + _box.size.y - 24.0 - float(_buttons.size()) * 116.0
	for b in _buttons:
		b.size = Vector2(_box.size.x - 96.0, 100.0)
		b.position = Vector2(_box.position.x + 48.0, y)
		b.pivot_offset = b.size * 0.5
		y += 116.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()


func _draw() -> void:
	var a := clampf(_appear, 0.0, 1.0)
	DrawUtil.fill_aa(self, DrawUtil.round_rect(Rect2(Vector2.ZERO, size), 0.0),
			Color(0.06, 0.12, 0.10, 0.55 * a))

	var box := _box
	var scale_t := 0.86 + 0.14 * DrawUtil.ease_out_back(a)
	box = Rect2(box.position + box.size * (1.0 - scale_t) * 0.5, box.size * scale_t)

	DrawUtil.draw_card(self, box, 36.0, Palette.PANEL, Palette.CARD_EDGE,
			Color(0, 0, 0, 0.28), 10.0)

	var cx := box.position.x + box.size.x * 0.5
	Fonts.draw_centered(self, _title, Vector2(cx, box.position.y + 62.0), 48,
			Palette.INK)

	if _stars >= 0:
		for i in 3:
			var c := _star_center(i)
			if i < _star_shown:
				Glyphs.draw_star(self, c, STAR_R, Palette.STAR,
						Palette.shade(Palette.STAR, -0.35), 4.0)
			else:
				Glyphs.draw_star(self, c, STAR_R * 0.86, Palette.STAR_EMPTY,
						Palette.shade(Palette.STAR_EMPTY, -0.2), 3.0)

	var ly := box.position.y + (250.0 if _stars >= 0 else 132.0)
	for line in _lines:
		Fonts.draw_centered(self, line, Vector2(cx, ly), 32, Palette.INK_SOFT)
		ly += 46.0
