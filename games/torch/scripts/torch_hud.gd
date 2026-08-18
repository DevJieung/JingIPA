class_name TorchHud
extends CanvasLayer

## 손전등 찾기의 화면 위 표시 — 방 이름, 이 방의 공룡 줄, 집으로, 배너, 카드, 페이드.
##
## ★ CanvasLayer 는 **이 한 겹뿐**이다. 안에 CanvasLayer 를 또 끼우면 프로젝트 폰트가
##   조용히 fallback 으로 돌아간다 (CLAUDE.md 규칙 18). 페이드도 여기 마지막 자식으로 둔다.
##
## ★ 화면이 깜깜하므로 위쪽 바는 일부러 밝고 따뜻하게 둔다. 아이가 "여기는 안전하다"고
##   붙잡을 자리가 하나는 있어야 한다. 어둠은 놀이지 위협이 아니다.

signal home_pressed

const W := 1280.0
const H := 720.0
const INK := Color("463a45")
const CREAM := Color(1.0, 0.976, 0.925, 0.88)

## 연출 길이 배수 (자동 테스트에서만 짧게 줄인다)
var slow := 1.0

var root: Control
var hud_name: Label
var hud_sub: Label
var row: DinoRow
var home_btn: Button
var banner: Panel
var banner_label: Label
var card: Panel
var card_img: TextureRect
var card_label: Label
var fade: ColorRect

var _card_tween: Tween


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_bar()
	_build_banner()
	_build_card()
	# ★ 페이드는 맨 마지막 자식이라 위쪽 바까지 덮는다 (예전 공룡 찾기의 layer 20 과 같다).
	fade = ColorRect.new()
	fade.color = Color(0.03, 0.03, 0.07, 0.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)


# ================================================================= 만들기

func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, fsize: int, base: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(int(fsize * 0.7))
	sb.content_margin_left = fsize * 0.9
	sb.content_margin_right = fsize * 0.9
	sb.content_margin_top = fsize * 0.35
	sb.content_margin_bottom = fsize * 0.45
	sb.border_width_bottom = 7
	sb.border_color = base.darkened(0.28)
	b.add_theme_stylebox_override("normal", sb)
	var sh: StyleBoxFlat = sb.duplicate()
	sh.bg_color = base.lightened(0.10)
	b.add_theme_stylebox_override("hover", sh)
	var sp: StyleBoxFlat = sb.duplicate()
	sp.bg_color = base.darkened(0.08)
	sp.border_width_bottom = 2
	sp.content_margin_top = fsize * 0.42
	sp.content_margin_bottom = fsize * 0.38
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _build_bar() -> void:
	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(30)
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.22)
	bar.add_theme_stylebox_override("panel", sb)
	bar.position = Vector2(22, 16)
	bar.size = Vector2(W - 44, 88)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	hb.position = Vector2(56, 34)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hb)
	hud_name = _label("방", 40, INK)
	hb.add_child(hud_name)
	hud_sub = _label("", 24, Color("8a7c8c"))
	hb.add_child(hud_sub)

	row = DinoRow.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(700, 20)
	root.add_child(row)

	home_btn = _button("집으로", 22, Color("ffe0e6"))
	home_btn.position = Vector2(W - 180, 32)
	home_btn.pressed.connect(func(): home_pressed.emit())
	root.add_child(home_btn)


func _build_banner() -> void:
	banner = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.98, 0.93, 0.94)
	sb.set_corner_radius_all(40)
	sb.border_width_bottom = 8
	sb.border_color = Color("ffd166")
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.25)
	banner.add_theme_stylebox_override("panel", sb)
	banner.size = Vector2(600, 150)
	banner.position = Vector2(W * 0.5 - 300, 190)
	banner.pivot_offset = Vector2(300, 75)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	root.add_child(banner)

	banner_label = _label("", 56, Color("e2743b"))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(banner_label)


## 공룡을 찾으면 잠깐 떠오르는 카드 — 큰 그림 + 이름 전부.
## (공룡 찾기와 같은 카드다. 두 게임에서 같은 공룡을 만나는 것이 도감으로 이어진다.)
func _build_card() -> void:
	card = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.99, 0.96, 0.96)
	sb.set_corner_radius_all(44)
	sb.border_width_bottom = 10
	sb.border_color = Color("ffd166")
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.28)
	card.add_theme_stylebox_override("panel", sb)
	card.size = Vector2(460, 330)
	card.position = Vector2(W * 0.5 - 230, 110)
	card.pivot_offset = Vector2(230, 165)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	root.add_child(card)

	card_img = TextureRect.new()
	card_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_img.position = Vector2(20, 18)
	card_img.size = Vector2(420, 208)
	card_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(card_img)

	card_label = _label("", 40, INK)
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.position = Vector2(0, 238)
	card_label.size = Vector2(460, 72)
	card.add_child(card_label)


# ================================================================= 쓰기

func set_room(name: String, sub: String, species: Array) -> void:
	hud_name.text = name
	hud_sub.text = sub
	row.set_room(species)
	row.position = Vector2(930.0 - row.size.x, 20)
	hide_card()
	hide_banner()


func set_sub(text: String) -> void:
	hud_sub.text = text


func set_found(n: int) -> void:
	row.found = n
	row.queue_redraw()


func show_card(d: Dino) -> void:
	var tex := d.texture()
	card_img.texture = tex
	card_img.visible = tex != null
	card_label.text = d.full_name()
	card_label.position.y = 238 if tex != null else 130
	card.visible = true
	card.modulate.a = 1.0
	card.scale = Vector2(0.5, 0.5)
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	_card_tween = create_tween()
	_card_tween.tween_property(card, "scale", Vector2(1.06, 1.06), 0.22 * slow) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(card, "scale", Vector2.ONE, 0.12 * slow)
	_card_tween.tween_interval(1.9 * slow)
	_card_tween.tween_property(card, "modulate:a", 0.0, 0.40 * slow)
	_card_tween.tween_callback(hide_card)


func hide_card() -> void:
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	card.visible = false


func show_banner(text: String) -> void:
	banner_label.text = text
	banner.visible = true
	banner.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(banner, "scale", Vector2(1.1, 1.1), 0.18 * slow) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.12 * slow)


func hide_banner() -> void:
	banner.visible = false


func fade_to(alpha: float, secs: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, maxf(0.02, secs))
	return tw
