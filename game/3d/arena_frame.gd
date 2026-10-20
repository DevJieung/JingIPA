extends Node2D
class_name ArenaFrame

## The battle picture's blit (2026-10-18, casual overhaul WP-E). ArenaView draws the 3D
## viewport through this one child of the battle screen instead of on the screen itself:
## it is the only canvas item on that screen filtered LINEAR (the project default stays
## Nearest for the 2D sprite screens and for every HUD texture, so nothing else softens);
## it paints the deep night under the picture (the screen skips its own clear while this
## node exists); and its material is the post pass art/models/arena_post.gdshader — a cool
## vignette about the open battle box, a light sharpen, a 1/255 dither; no tilt-shift and
## no grading. It draws behind its parent, so every HUD draw of the screen (bars, damage
## numbers, strips, the rail) lands on top of it, after it. The legacy screens
## (StellarView.draw, StellarBackdrop) keep their plain blit and never create one.
const POST_SHADER := "res://art/models/arena_post.gdshader"

var picture: Texture2D = null
var rect := Rect2()

func _init() -> void:
	name = "ArenaFrame"
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var post := ShaderMaterial.new()
	post.shader = load(POST_SHADER)
	material = post

## One uniform of the post pass.
func set_post(uniform: StringName, value: Variant) -> void:
	if material is ShaderMaterial: material.set_shader_parameter(uniform, value)

## Show `source` (the arena viewport's texture, or null for the plain night) over `area`.
func present(source: Texture2D, area: Rect2) -> void:
	picture = source
	rect = area
	queue_redraw()

func _draw() -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0: return
	draw_rect(rect, Look.BG_DEEP)
	if picture != null: draw_texture_rect(picture, rect, false)
