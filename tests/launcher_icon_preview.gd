extends Node2D

const SHADER := """
shader_type canvas_item;
uniform int mask_shape = 0;
void fragment() {
	vec2 uv = UV;
	vec4 col = texture(TEXTURE, mask_shape == 0 ? uv : uv * 0.6666667 + vec2(0.1666667));
	if (mask_shape == 1) {
		vec2 q = abs(uv - vec2(0.5)) - vec2(0.32);
		if (length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) > 0.18) { col.a = 0.0; }
	} else if (mask_shape == 2 && distance(uv, vec2(0.5)) > 0.5) { col.a = 0.0; }
	COLOR = col;
}
"""

func _ready() -> void:
	Save._readonly = true
	var shader := Shader.new()
	shader.code = SHADER
	for mode in range(4):
		var top := 147.0
		for pixels in [192, 96, 72, 48]:
			var texture := Sprite2D.new()
			texture.texture = Art.tex("res://art/ui/launcher_main.png" if mode == 0 else "res://art/ui/launcher_monochrome.svg" if mode == 3 else "res://art/ui/launcher_adaptive.png")
			texture.centered = false
			texture.position = Vector2(168 + mode * 312 - pixels * 0.5, top)
			texture.scale = Vector2.ONE * float(pixels) / texture.texture.get_width()
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var material_ := ShaderMaterial.new()
			material_.shader = shader
			material_.set_shader_parameter("mask_shape", mini(mode, 2))
			texture.material = material_
			add_child(texture)
			top += pixels + 42
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/feedback-design/launcher_review.png")
	get_tree().quit()

func _draw() -> void:
	draw_rect(Look.SCREEN, Color("#17242b"))
	Look.text_center(self, Vector2(640, 48), "ALL-IN DEFENSE · LAUNCHER ICON", 30, Look.INK)
	var labels := ["Legacy", "Adaptive · rounded", "Adaptive · circle", "Themed · circle"]
	for mode in range(4):
		Look.text_center(self, Vector2(168 + mode * 312, 109), labels[mode], 22, Look.GOLD)
		var top := 147.0
		for pixels in [192, 96, 72, 48]:
			Look.text_center(self, Vector2(168 + mode * 312, top + pixels + 20), "%d px" % pixels, 16, Look.INK_DIM)
			top += pixels + 42
