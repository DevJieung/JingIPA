## 코드 드로잉(_draw)에서 쓸 폰트 접근점.
##
## Control 계열은 project.godot 의 gui/theme/custom_font 로 자동 적용되지만,
## draw_string() 을 직접 호출할 때는 Font 객체가 필요해서 여기서 가져다 쓴다.
##
## 주의: Jua 폰트에는 U+00D7(×), U+2212(−) 글리프가 없다.
## 연산 기호는 Glyphs 로 직접 그린다.
class_name Fonts
extends RefCounted

const MAIN: FontFile = preload("res://core/fonts/Jua-Regular.ttf")


## 문자열을 중앙 정렬로 그린다 (center 는 글자 상자의 중심).
static func draw_centered(ci: CanvasItem, text: String, center: Vector2,
		font_size: int, color: Color, font: Font = MAIN) -> void:
	var s := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var pos := Vector2(center.x - s.x * 0.5, center.y + (ascent - descent) * 0.5)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## 외곽선(테두리) 있는 중앙 정렬 텍스트 — 배경 위에서도 잘 읽히게.
static func draw_centered_outlined(ci: CanvasItem, text: String, center: Vector2,
		font_size: int, color: Color, outline_color: Color, outline: int = 6,
		font: Font = MAIN) -> void:
	var s := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var pos := Vector2(center.x - s.x * 0.5, center.y + (ascent - descent) * 0.5)
	if outline > 0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, outline, outline_color)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func text_width(text: String, font_size: int, font: Font = MAIN) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
