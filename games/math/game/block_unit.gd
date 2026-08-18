## 낱개 블록 하나 (수 모형의 '1').
##
## 시연 중 위치/크기/투명도를 트윈으로 움직이므로 Node2D 의 내장 속성
## (position, scale, modulate) 만 사용한다.
class_name BlockUnit
extends Node2D

var unit: float = 24.0:
	set(v):
		unit = v
		queue_redraw()

var face: Color = Palette.BLOCK_A
var side: Color = Palette.BLOCK_A_DARK
var light: Color = Palette.BLOCK_A_LIGHT

## 블록 위에 찍히는 점(주사위 눈처럼) — 낱개임을 강조.
var show_pip: bool = true

## 없어지는 중 표시 (뺄셈).
var doomed: bool = false

## 세기 강조용 흰색 번쩍임. 0~1.
var highlight: float = 0.0:
	set(v):
		highlight = v
		queue_redraw()


func _init(size: float = 24.0, base: Color = Palette.BLOCK_A) -> void:
	unit = size
	set_base_color(base)


func set_base_color(base: Color) -> void:
	face = base
	side = Palette.shade(base, -0.28)
	light = Palette.shade(base, 0.45)
	queue_redraw()


## 뺄셈에서 사라질 블록을 붉게 물들인다.
func mark_doomed() -> void:
	doomed = true
	set_base_color(Palette.BLOCK_REMOVE)


func _draw() -> void:
	var s := unit
	var rect := Rect2(-s * 0.5, -s * 0.5, s, s)
	var depth := s * 0.16
	DrawUtil.draw_block(self, rect, s * 0.22, face, side, light, depth)
	if show_pip:
		DrawUtil.circle_aa(self, Vector2(0, s * 0.10), s * 0.085,
				Color(side.r, side.g, side.b, 0.55))
	if highlight > 0.01:
		DrawUtil.fill_aa(self, DrawUtil.round_rect(rect, s * 0.22),
				Color(1, 1, 1, 0.5 * highlight))
