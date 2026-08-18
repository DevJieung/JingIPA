class_name Dino
extends Node2D

## 숨어 있는 공룡 한 마리.
## 그림(assets/dinos/*.png)이 있으면 그걸 쓰고, 없으면 dino_art.gd 손그림으로 그린다.

var species := 0
var pal: Dictionary = {}
var face := 1.0
var found := false

var base_pos := Vector2.ZERO
var t := 0.0
var speed := 1.0
var wiggle := 0.0
var joy := 0.0

var _tex: Texture2D = null
var _rect := Rect2()
var _art := 0
var _blink := false
var _blink_timer := 2.0
var _pop := 0.0


func setup(p_species: int, p_pos: Vector2, p_face: float) -> void:
	species = p_species
	base_pos = p_pos
	face = p_face
	position = p_pos
	_tex = DinoSpecies.texture(species)
	_rect = DinoSpecies.draw_rect_for(species)
	_art = int(DinoSpecies.data(species)["art"])
	pal = DinoArt.palette(species)
	speed = randf_range(0.8, 1.25)
	t = randf() * TAU
	_blink_timer = randf_range(1.5, 5.0)
	z_index = 10


func full_name() -> String:
	return DinoSpecies.full_name(species)


func texture() -> Texture2D:
	return _tex


func hit_rect() -> Rect2:
	if _tex != null and _rect.size.x > 0.0:
		return Rect2(base_pos + _rect.position - Vector2(12, 14), _rect.size + Vector2(24, 26))
	return Rect2(base_pos + Vector2(-80, -160), Vector2(160, 176))


func _process(delta: float) -> void:
	t += delta * speed
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink = not _blink
		_blink_timer = 0.12 if _blink else randf_range(2.0, 6.0)
		if _tex == null:
			queue_redraw()

	if wiggle > 0.0:
		wiggle = maxf(0.0, wiggle - delta * 0.9)

	var bob := sin(t * 2.2) * 3.0
	var sq := 1.0 + sin(t * 2.2) * 0.02
	var rot := sin(t * 9.0) * 0.12 * wiggle

	if found:
		joy = minf(1.0, joy + delta * 2.0)
		bob = -absf(sin(t * 5.0)) * 14.0 * joy
		rot = sin(t * 5.0) * 0.10 * joy
		sq = 1.0 + sin(t * 5.0) * 0.05

	var punch := 0.0
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta * 2.6)
		punch = sin(_pop * PI) * 0.3

	position = base_pos + Vector2(0, bob)
	rotation = rot
	scale = Vector2((1.0 / sq) * (1.0 + punch), sq * (1.0 + punch))


func hint() -> void:
	if not found:
		wiggle = 1.0


func celebrate() -> void:
	found = true
	wiggle = 0.0
	z_index = 30
	_pop = 1.0


func _draw() -> void:
	_paint(self)


func _paint(ci: Object) -> void:
	if _tex != null and _rect.size.x > 0.0:
		DinoArt.blob(ci, DinoArt.ellipse(Vector2(0, -6), _rect.size.x * 0.42, 12, 18), Color(0, 0, 0, 0.14))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(face, 1.0))
		ci.draw_texture_rect(_tex, _rect, false)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		DinoArt.draw_shadow(ci, 1.0, 0.14)
		DinoArt.draw_dino(ci, _art, pal, 1.0, face, _blink)
