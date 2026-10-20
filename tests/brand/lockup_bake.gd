extends Node

## Bakes the Stellar Defense wordmark lockup (crest + metal title + subtitle) for the loading
## cover: the title screen's code wordmark (game/title_screen.gd Wordmark — same glyphs, layers,
## shader ramp) rendered at 2x into a transparent viewport, once per locale. Text baked into an
## image is the recorded exception for the logo lockup (D4 brief); the title keeps drawing live.
##
##   godot --path . --resolution 320x200 res://tests/brand/lockup_bake.tscn -- --crest <png> --out <dir>
## Writes <out>/brand_lockup_<locale>.png (premultiplied by the viewport; tools/brand/lockup.py
## un-premultiplies and trims).

const SCALE := 2.0
const SIZE := Vector2i(1700, 640)
## Native title coordinates (title_screen.gd): title line centre (640, 144), subtitle at y 212.
const NATIVE := Vector2(640, 144)
var out_dir := "res://build/feedback-2026-10-19/D4/lockup"
var crest_path := ""
var crest_height := 150.0     # native px
var crest_gap := 6.0          # native px between crest bottom and title cap height


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--out": out_dir = args[i + 1]
			"--crest": crest_path = args[i + 1]
			"--crest-height": crest_height = float(args[i + 1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var crest: Sprite2D = null
	if not crest_path.is_empty():
		var img := Image.load_from_file(crest_path)
		img.generate_mipmaps()
		crest = Sprite2D.new()
		crest.texture = ImageTexture.create_from_image(img)
		crest.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		vp.add_child(crest)
	var mark := Mark.new()
	vp.add_child(mark)
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		# Lockup origin: title line centre at x = SIZE.x/2, y leaves room for the crest above.
		var top := (crest_height + crest_gap + 50.0) if crest != null else 60.0
		var centre := Vector2(SIZE.x * 0.5, (top + 48.0) * SCALE)
		mark.scale = Vector2.ONE * SCALE
		mark.position = centre - NATIVE * SCALE
		mark.queue_redraw()
		if crest != null:
			var tex_h := float(crest.texture.get_height())
			crest.scale = Vector2.ONE * (crest_height * SCALE / tex_h)
			crest.position = Vector2(SIZE.x * 0.5, centre.y - (48.0 + crest_gap + crest_height * 0.5) * SCALE)
		for i in range(3):
			await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out_dir.path_join("brand_lockup_%s.png" % locale))
	print("lockups baked")
	get_tree().quit()


class Mark extends Node2D:
	const METAL_SHADER := preload("res://art/ui/title_wordmark.gdshader")

	func _ready() -> void:
		var metal := ShaderMaterial.new()
		metal.shader = METAL_SHADER
		material = metal

	func _diamond(center: Vector2, radius: Vector2, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -radius.y), center + Vector2(radius.x, 0),
			center + Vector2(0, radius.y), center - Vector2(radius.x, 0)]), color)

	func _draw() -> void:
		var dark := Color("#101b20")
		var bronze := Color("#715436")
		var edge := Look.GOLD
		var light := Color("#fff0c7")
		var center := Vector2(640, 144)
		var title := I18n.t("스텔라 디펜스")
		var size := 84 if I18n.locale == "ko" else 76
		var font := Look.font(size)
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := Look._baseline(font, center - Vector2(width * 0.5, 0), size)
		draw_string_outline(font, at + Vector2(0, 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 13, Color(dark, 0.8))
		for depth in range(4, 0, -1):
			draw_string_outline(font, at + Vector2(0, depth), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, bronze)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, dark)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, edge)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, dark)
		draw_string(font, at + Vector2(0, 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, bronze)
		draw_string(font, at + Vector2(0, -1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, light)
		draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
		var subtitle := "STELLAR DEFENSE" if I18n.locale == "ko" else "스텔라 디펜스"
		var sub_size := 23
		var sub_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
		var subtitle_at := Look._baseline(font, Vector2(640 - sub_width * 0.5, 212), sub_size)
		draw_string_outline(font, subtitle_at, subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, 5, dark)
		draw_string(font, subtitle_at, subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, light)
		for direction in [-1, 1]:
			var start: float = 640 + direction * (sub_width * 0.5 + 24)
			var end: float = 640 + direction * (width * 0.5 + 24)
			draw_line(Vector2(start, 213), Vector2(end, 213), dark, 5)
			draw_line(Vector2(start, 211), Vector2(end, 211), edge, 2)
			_diamond(Vector2(end, 211), Vector2(5, 5), edge)
			var side := Vector2(640 + direction * (width * 0.5 + 38), 145)
			_diamond(side, Vector2(7, 12), dark)
			_diamond(side, Vector2(4, 8), edge)
