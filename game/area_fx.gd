extends RefCounted
class_name AreaFx

## Presentation only: damage, radius and ticks remain owned by BattleSim.
const ATLAS := "res://art/effects/area_attacks.png"
const ELEMENTS := ["fire", "ice", "water", "elec", "none"]
const MAX_FIELDS := 36
const TAIL := 0.42
var fields: Array[Dictionary] = []

func zone(at: Vector2, radius: float, element: String, color: Color,
		tier: int, delay: float, tick: float, ticks: int, shot: Dictionary = {}) -> void:
	_add(at, radius, element, color, tier, delay,
			maxf(0.0, float(ticks - 1) * tick), tick, false)
	# Character Shot art is presentation data. The simulation still owns the
	# target, radius, delay and damage ticks, including the warning phase.
	fields.back()["shot"] = shot

func impact(at: Vector2, radius: float, element: String, color: Color,
		tier: int, secondary: bool = false) -> void:
	_add(at, radius, element, color, tier, 0, 0.25, 0.18, secondary)

func _add(at: Vector2, radius: float, element: String, color: Color,
		tier: int, delay: float, active: float, tick: float, secondary: bool) -> void:
	if fields.size() >= MAX_FIELDS:
		fields.pop_front()
	fields.append({"at": at, "r": maxf(8, radius), "el": element, "c": color,
		"tier": clampi(tier, 0, 9), "age": -delay, "delay": maxf(0.01, delay),
		"active": active, "tick": maxf(0.05, tick), "strength": 0.65 if secondary else 1.0})

func update(dt: float) -> void:
	for i in range(fields.size() - 1, -1, -1):
		fields[i]["age"] = float(fields[i]["age"]) + dt
		if float(fields[i]["age"]) > float(fields[i]["active"]) + TAIL:
			fields.remove_at(i)

## A central burst sits fully inside the true circular damage range.
## Even its canvas corners are <= radius; no range-marker outline is drawn.
static func sprite_rect(at: Vector2, radius: float) -> Rect2:
	var size := Vector2.ONE * radius * 1.30
	return Rect2(at - Vector2(size.x * 0.5, size.y * 0.5 + radius * 0.10), size)

## 한 칸을 **땅(아래 28%)과 몸통(위 72%)** 두 겹으로 가른다. layer 0 은 땅, 1 은 몸통,
## 그 밖은 통째로다. 원본과 목적지 네모를 같은 비율로 잘라 돌려준다 [source, dest].
static func _layer_rects(source: Rect2, dest: Rect2, layer: int) -> Array:
	if layer == 0:
		source.position.y += source.size.y * 0.72
		source.size.y *= 0.28
		dest.position.y += dest.size.y * 0.72
		dest.size.y *= 0.28
	elif layer == 1:
		source.size.y *= 0.72
		dest.size.y *= 0.72
	return [source, dest]


## 한 칸(source)을 at 둘레의 폭발 자리에 그린다. 땅/몸통 갈래는 _layer_rects 가 정한다.
static func _blit(ci: CanvasItem, texture: Texture2D, source: Rect2, at: Vector2,
		radius: float, alpha: float, layer: int) -> void:
	var rects := _layer_rects(source, sprite_rect(at, radius), layer)
	ci.draw_texture_rect_region(texture, rects[1], rects[0], Color(1, 1, 1, clampf(alpha, 0, 1)))


## The atlas has five elements and four chronological frames per row.
## Split ground and raised pixels; both passes stay behind character bodies.
static func draw_sprite(ci: CanvasItem, at: Vector2, radius: float, element: String,
		frame: int, alpha: float = 1.0, layer: int = -1) -> bool:
	var texture := Art.tex(ATLAS)
	if texture == null:
		return false
	var row := ELEMENTS.find(element)
	if row < 0:
		row = 4
	var cell := Vector2(texture.get_width() / 4.0, texture.get_height() / 5.0)
	_blit(ci, texture, Rect2(Vector2(clampi(frame, 0, 3) * cell.x, row * cell.y), cell),
			at, radius, alpha, layer)
	return true

func _frame(field: Dictionary) -> int:
	var age := float(field["age"])
	if age < 0.06:
		return 0
	if age > float(field["active"]):
		return 3
	if age < 0.16:
		return 1
	return 1 + int(fposmod(age, maxf(0.16, float(field["tick"]))) / maxf(0.16, float(field["tick"])) * 2) % 2

func _alpha(field: Dictionary) -> float:
	var age := float(field["age"])
	var opacity := 1.0
	if age < 0:
		opacity = clampf(1 + age / float(field["delay"]), 0, 1) * 0.6
	elif age > float(field["active"]):
		opacity = 1 - (age - float(field["active"])) / TAIL
	return maxf(0, opacity) * float(field["strength"]) / sqrt(maxf(1, fields.size() / 10.0))

func _draw_field_sprite(ci: CanvasItem, field: Dictionary, alpha: float, layer: int) -> bool:
	var shot: Dictionary = field.get("shot", {})
	if shot.is_empty() or float(field["age"]) < 0.0:
		return draw_sprite(ci, field["at"], float(field["r"]), String(field["el"]),
				_frame(field), alpha, layer)
	# All four phases come from this hero's Shot strip: charge, expansion,
	# impact, fragments. Reuse the existing tick/decay phase and layer split.
	var frame: int = mini(_frame(field), int(shot["n"]) - 1)
	var cell := Vector2(float(shot["w"]), float(shot["h"]))
	_blit(ci, shot["tex"], Rect2(Vector2(frame * cell.x, 0), cell), field["at"],
			float(field["r"]), alpha, layer)
	return true

func draw_back(ci: CanvasItem) -> void:
	for field in fields:
		var alpha := _alpha(field)
		var at: Vector2 = field["at"]
		var col: Color = field["c"]
		if float(field["age"]) < 0:
			# A small central charge keeps the impact timing readable without
			# tracing the damage radius around surrounding monsters.
			_draw_field_sprite(ci, field, alpha * 0.72, -1)
			continue
		if not _draw_field_sprite(ci, field, alpha, 0):
			ci.draw_rect(Rect2(at - Vector2.ONE * 3, Vector2.ONE * 6), Color(col, alpha * 0.45))

func draw_front(ci: CanvasItem) -> void:
	for field in fields:
		var alpha := _alpha(field)
		var at: Vector2 = field["at"]
		var radius := float(field["r"])
		var age := float(field["age"])
		if age < 0:
			continue
		_draw_field_sprite(ci, field, alpha, 1)
		var col: Color = field["c"]
		var count := 4 + int(field["tier"])
		for i in range(count):
			var phase := fposmod(age * 1.5 + i * 0.618, 1.0)
			var angle := i * 2.39996
			var p := at + Vector2.from_angle(angle) * radius * (0.18 + phase * 0.55)
			p.y -= phase * radius * 0.16
			var size := 2.0 + int(field["tier"]) * 0.18
			ci.draw_rect(Rect2(p.round(), Vector2.ONE * size), Color(col.lightened(0.5), alpha * (1 - phase)))
