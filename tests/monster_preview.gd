extends Node2D

var main = null
var time := 0.0

func _process(dt: float) -> void:
	time += dt
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Look.BG_DEEP)
	Look.text_left(self, Vector2(24, 40), "몬스터 걷기 · 날개짓", 30, Look.GOLD)
	for i in range(Roster.MONSTERS.size()):
		var m: Dictionary = Roster.MONSTERS[i]
		var origin := Vector2(20 + (i % 5) * 250, 82 + (i / 5) * 140)
		Look.px_panel(self, Rect2(origin, Vector2(240, 132)), Look.PANEL, Look.PANEL_EDGE)
		Look.text_left(self, origin + Vector2(10, 20), m["ko"], 16, Look.INK)
		var clip := Anim.clip(m, "move")
		if not clip.is_empty():
			Anim.draw_frame(self, clip, Anim.frame_at(clip, time), origin.x + 120,
					origin.y + 124, 0.70 if m["kind"] == "boss" else 1.35)
		else:
			Look.text_center(self, origin + Vector2(120, 80), "생성 중", 18, Look.INK_DIM)
