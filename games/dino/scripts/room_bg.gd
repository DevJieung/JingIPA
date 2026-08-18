class_name RoomBg
extends Node2D

## 방의 벽과 바닥.

var data: Dictionary = {}

const W := 1280.0
const H := 720.0
const FY := 470.0


func _draw() -> void:
	_paint(self)


func _paint(ci: Object) -> void:
	if data.is_empty():
		return
	var wall: Color = data["wall"]
	var wall2: Color = data["wall2"]
	var fl: Color = data["floor"]
	var fl2: Color = data["floor2"]
	var trim: Color = data["trim"]

	ci.draw_rect(Rect2(0, 0, W, FY), wall)
	match String(data["wall_pat"]):
		"stripes":
			var x := 0.0
			while x < W:
				ci.draw_rect(Rect2(x, 0, 56, FY), wall2)
				x += 118
		"dots":
			var row := 0
			var y := 46.0
			while y < FY:
				var x2 := 40.0 + (58.0 if row % 2 == 1 else 0.0)
				while x2 < W:
					DinoArt.blob(ci, DinoArt.ellipse(Vector2(x2, y), 11, 11, 12), wall2)
					x2 += 116
				y += 74
				row += 1
		"tiles":
			var x3 := 0.0
			while x3 <= W:
				ci.draw_line(Vector2(x3, 0), Vector2(x3, FY), wall2, 4.0)
				x3 += 92
			var y3 := 46.0
			while y3 < FY:
				ci.draw_line(Vector2(0, y3), Vector2(W, y3), wall2, 4.0)
				y3 += 92
		"planks":
			var y4 := 40.0
			while y4 < FY:
				ci.draw_line(Vector2(0, y4), Vector2(W, y4), wall2, 6.0)
				y4 += 78

	# 바닥
	ci.draw_rect(Rect2(0, FY, W, H - FY), fl)
	if String(data["floor_pat"]) == "wood":
		# 긴 마루널 (이음매는 아주 드물게)
		var line := fl.darkened(0.13)
		var y := FY + 46.0
		var row := 0
		while y < H:
			ci.draw_line(Vector2(0, y), Vector2(W, y), line, 3.0)
			var x := -160.0 + (row % 3) * 230.0
			while x < W:
				ci.draw_line(Vector2(x, y - 46), Vector2(x, y), line, 3.0)
				x += 690
			ci.draw_line(Vector2(120 + (row % 4) * 260, y - 24), Vector2(420 + (row % 4) * 260, y - 24), fl.darkened(0.05), 2.0)
			y += 46
			row += 1
	else:
		var s := 74.0
		var row2 := 0
		var y2 := FY
		while y2 < H:
			var x2 := 0.0 if row2 % 2 == 0 else -s
			while x2 < W:
				ci.draw_rect(Rect2(x2, y2, s, s), fl2)
				x2 += s * 2.0
			y2 += s
			row2 += 1

	# 걸레받이 + 벽/바닥 그림자
	ci.draw_rect(Rect2(0, FY - 22, W, 26), trim)
	ci.draw_rect(Rect2(0, FY + 4, W, 12), Color(0, 0, 0, 0.10))
	ci.draw_rect(Rect2(0, 0, W, 96), Color(0, 0, 0, 0.05))

	var dim: float = data.get("dim", 0.0)
	if dim > 0.0:
		ci.draw_rect(Rect2(0, 0, W, H), Color(0.18, 0.12, 0.22, dim))
