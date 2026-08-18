class_name DinoRow
extends Control

## 화면 위쪽의 "몇 마리 찾았나" 표시.
## 아직 못 찾은 공룡은 까만 그림자로, 찾은 공룡은 제 색으로 보여준다.

var species: Array = []
var found := 0

const GAP := 62.0
const ICON_H := 48.0
const SHADOW := Color(0.16, 0.13, 0.2, 0.32)


func set_room(p_species: Array) -> void:
	species = p_species
	found = 0
	custom_minimum_size = Vector2(GAP * species.size(), 60)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	_paint(self)


func _paint(ci: Object) -> void:
	for i in species.size():
		var at := Vector2(GAP * (i + 0.5), 58.0)
		var sp: int = species[i]
		var tex := DinoSpecies.texture(sp)
		var tint := Color.WHITE if i < found else SHADOW
		if tex != null:
			var r := DinoSpecies.draw_rect_for(sp)
			if r.size.y <= 0.0:
				continue
			var k := ICON_H / r.size.y
			if r.size.x * k > GAP - 6.0:
				k = (GAP - 6.0) / r.size.x
			ci.draw_texture_rect(tex, Rect2(at + r.position * k, r.size * k), false, tint)
		else:
			var art := int(DinoSpecies.data(sp)["art"])
			var pal := DinoArt.palette(sp) if i < found else DinoArt.grey_palette()
			DinoArt.draw_dino(ci, art, pal, 0.30, 1.0, false, at)
