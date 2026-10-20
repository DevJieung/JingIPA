extends Node

## D4 brand study — cold start: MindMorph logo -> Stellar Defense key art + loading bar.
## Mirrors the real flow (game/startup_splash.gd + game/startup_loading.gd, LB2a 2026-10-19):
## the same timings and the same state the cover's _draw_cover() reads — phase, shown, art,
## intro, outro, veil — with simulated loading steps. `draw_cover()` below is written to move
## into StartupLoading._draw_cover() once the main agent hands that function over.
##
##   godot --path . --resolution 1280x800 --fixed-fps 60 res://tests/brand/loading_preview.tscn \
##       -- --out <dir> --locale ko --art <png> [--lockup <png>] [--times 0.5,1.0,...]

const LOGO := preload("res://art/ui/mindmorph_logo.png")
const GREEN := Color8(35, 93, 72)
const NIGHT := Color("#060c14")

# StartupSplash timings.
const FADE_IN := 0.60
const HOLD := 0.70
const FADE_OUT := 0.60
const END_HOLD := 0.10
# StartupLoading timings and steps.
const INTRO_SECONDS := 0.35
const OUTRO_SECONDS := 0.25
const VEIL_SECONDS := 0.35
const MIN_SECONDS := 0.6
const EASE_RATE := 7.0
const EASE_MIN := 0.6
## Simulated work: [phase, seconds, progress at the end]. "load" moves smoothly (threaded
## loads report progress); the others land in one step after a stall, like the real ones.
const WORK := [["load", 1.30, 0.40], ["main", 0.45, 0.50], ["backdrop", 0.30, 0.64],
	["title", 0.40, 0.80], ["warm", 0.14, 1.0]]

var out_dir := "res://build/feedback-2026-10-19/D4/loading/preview"
var art_path := ""
var lockup_path := ""
var times: Array[float] = []
var clock := 0.0

# Cover state (names as in StartupLoading).
var phase := "logo"
var progress := 0.0
var shown := 0.0
var art: Texture2D = null
var lockup: Texture2D = null
var intro := 0.0
var outro := 0.0
var veil := 0.0
var logo_alpha := 0.0

var _cover_age := 0.0
var _phase_age := 0.0
var _work_index := 0
var _canvas: Control
var _cover_start := 0.0
var _saved := 0
var _capturing := false
var _records: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--out": out_dir = args[i + 1]
			"--locale": I18n.set_locale(args[i + 1])
			"--art": art_path = args[i + 1]
			"--lockup": lockup_path = args[i + 1]
			"--times":
				for part in args[i + 1].split(","):
					times.append(float(part))
	if times.is_empty():
		times = [0.05, 0.35, 0.95, 1.75, 2.06, 2.20, 2.45, 3.0, 3.6, 4.4, 4.75, 4.95, 5.2, 5.6]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	RenderingServer.set_default_clear_color(GREEN)
	if not art_path.is_empty():
		art = _texture(art_path)
	lockup = _texture(lockup_path) if not lockup_path.is_empty() else StartupLoading.lockup_texture()
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	_canvas = Control.new()
	layer.add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_canvas.draw.connect(_draw)
	set_process(true)


func _texture(path: String) -> Texture2D:
	var image := Image.load_from_file(path)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _process(_dt: float) -> void:
	var dt := 1.0 / 60.0
	clock += dt
	_phase_age += dt
	if phase == "logo":
		logo_alpha = StartupSplash.alpha_at(clock)
		if clock >= FADE_IN + HOLD + FADE_OUT + END_HOLD:
			phase = WORK[0][0]
			_phase_age = 0.0
			_cover_start = clock
	else:
		_cover_age += dt
		intro = minf(1.0, intro + dt / INTRO_SECONDS)
		_step(dt)
		_ease(dt)
	_canvas.queue_redraw()
	if not _capturing and _saved < times.size() and clock >= times[_saved]:
		_capture()


func _step(dt: float) -> void:
	if _work_index < WORK.size():
		var row: Array = WORK[_work_index]
		var start: float = 0.0 if _work_index == 0 else float(WORK[_work_index - 1][2])
		if row[0] == "load":
			progress = maxf(progress, lerpf(start, row[2], clampf(_phase_age / row[1], 0.0, 1.0)))
		if _phase_age >= row[1]:
			progress = maxf(progress, row[2])
			_work_index += 1
			phase = WORK[_work_index][0] if _work_index < WORK.size() else "settle"
			_phase_age = 0.0
		return
	match phase:
		"settle":
			if shown >= 1.0 and _cover_age >= MIN_SECONDS:
				phase = "reveal"
				_phase_age = 0.0
		"reveal":
			outro = minf(1.0, outro + dt / OUTRO_SECONDS)
			if outro >= 1.0:
				veil = 1.0
				phase = "lift"
		"lift":
			veil = maxf(0.0, veil - dt / VEIL_SECONDS)
			if veil <= 0.0:
				phase = "done"


func _ease(dt: float) -> void:
	var gap := progress - shown
	if gap <= 0.0005:
		shown = maxf(shown, progress)
		return
	shown = minf(progress, shown + maxf(gap * minf(1.0, dt * EASE_RATE), dt * EASE_MIN))


func _capture() -> void:
	_capturing = true
	var record := {"t": clock, "phase": phase, "view": [_canvas.size.x, _canvas.size.y], "logo_alpha": logo_alpha,
		"shown": shown, "intro": intro, "outro": outro, "veil": veil,
		"bar": _rect_array(StartupLoading.bar_rect(Rect2(Vector2.ZERO, _canvas.size))),
		"mark": _rect_array(StartupLoading.lockup_rect(Rect2(Vector2.ZERO, _canvas.size), lockup))}
	await RenderingServer.frame_post_draw
	var file := "t%05.2f.png" % float(record["t"])
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	record["file"] = file
	_records.append(record)
	_saved += 1
	_capturing = false
	if _saved >= times.size():
		var f := FileAccess.open(out_dir.path_join("frames.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"frames": _records, "locale": I18n.locale}, "\t"))
		f.close()
		get_tree().quit()


static func _rect_array(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, _canvas.size)
	if phase == "logo":
		_canvas.draw_rect(area, GREEN)
		var side := floorf(minf(area.size.x, area.size.y) * 0.64)
		var at := ((area.size - Vector2.ONE * side) * 0.5).floor()
		_canvas.draw_texture_rect(LOGO, Rect2(at, Vector2.ONE * side), false, Color(1, 1, 1, logo_alpha))
		return
	if phase == "done":
		_canvas.draw_rect(area, Look.BG)   # stands in for the revealed title in this study
		return
	if phase == "lift":
		_canvas.draw_rect(area, Look.BG)
	var art_k := clampf((clock - _cover_start) / StartupLoading.ART_FADE, 0.0, 1.0) if art != null else 0.0
	StartupLoading.draw_layers(_canvas, area, phase, shown, art, lockup, art_k, intro, outro, veil, clock)
