class_name Confetti
extends Node2D

## 색종이 / 반짝이 효과.

var _p: Array = []

const G := 900.0


func _ready() -> void:
	set_process(false)
	z_index = 100


func burst(at: Vector2, count := 16, tint := Color.WHITE) -> void:
	for i in count:
		var a := randf() * TAU
		var sp := randf_range(140.0, 340.0)
		_p.append({
			"pos": at + Vector2(randf_range(-8, 8), randf_range(-8, 8)),
			"vel": Vector2(cos(a), sin(a)) * sp - Vector2(0, 120),
			"rot": randf() * TAU,
			"spin": randf_range(-9.0, 9.0),
			"size": randf_range(7.0, 15.0),
			"col": tint.lerp([Color("fff275"), Color("ff8fa3"), Color("8fd6ff"), Color.WHITE][i % 4], randf_range(0.3, 0.9)),
			"life": randf_range(0.7, 1.2),
			"max": 1.2,
			"star": i % 3 == 0,
		})
	set_process(true)


func rain(count := 70) -> void:
	for i in count:
		_p.append({
			"pos": Vector2(randf_range(0, 1280), randf_range(-420, -20)),
			"vel": Vector2(randf_range(-70, 70), randf_range(160, 340)),
			"rot": randf() * TAU,
			"spin": randf_range(-7.0, 7.0),
			"size": randf_range(9.0, 18.0),
			"col": [Color("ff8fa3"), Color("ffd166"), Color("8fd6ff"), Color("9be36f"), Color("c9a8e8")][i % 5],
			"life": randf_range(2.2, 3.6),
			"max": 3.6,
			"star": i % 4 == 0,
		})
	set_process(true)


func clear_all() -> void:
	_p.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var alive := []
	for d in _p:
		d["life"] -= delta
		if d["life"] <= 0.0:
			continue
		var v: Vector2 = d["vel"]
		v.y += G * delta * 0.35
		v.x *= 1.0 - delta * 0.6
		d["vel"] = v
		d["pos"] = d["pos"] + v * delta
		d["rot"] = d["rot"] + d["spin"] * delta
		alive.append(d)
	_p = alive
	queue_redraw()
	if _p.is_empty():
		set_process(false)


func _draw() -> void:
	for d in _p:
		var a: float = clampf(d["life"] / 0.4, 0.0, 1.0)
		var c: Color = d["col"]
		c.a = a
		var s: float = d["size"]
		draw_set_transform(d["pos"], d["rot"], Vector2.ONE)
		if d["star"]:
			var pts := PackedVector2Array()
			for i in 10:
				var ang := TAU * float(i) / 10.0 - PI * 0.5
				var r: float = s * (0.95 if i % 2 == 0 else 0.42)
				pts.append(Vector2(cos(ang), sin(ang)) * r)
			draw_colored_polygon(pts, c)
		else:
			draw_rect(Rect2(-s * 0.5, -s * 0.35, s, s * 0.7), c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
