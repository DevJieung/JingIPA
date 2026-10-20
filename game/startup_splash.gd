class_name StartupSplash
extends CanvasLayer

## The cold-start MindMorph logo (F8, 2026-10-19): fade in, hold, fade out, plain green.
## game/startup.gd adds it first and starts the real loading (StartupLoading.request) at the
## same moment; when `finished` fires, the loading cover (key art + bar) takes over in the
## same frame on the same green. Keep the opaque background until then.
signal finished

const BACKGROUND := Color8(35, 93, 72)
## The company logo: art/ui/mindmorph_logo.png is the 1024 px render of the vector redraw
## art/ui/mindmorph_logo.svg (tools/brand/mindmorph_logo.py) of the user's docs/icon-business-v3-512.png
## — same shapes and colours, fitted to the original; docs/ itself is not exported.
## Loaded in _ready, not preloaded: game/startup.gd keeps this script for the app's life, and the
## 1024 px master (with mipmaps) should leave memory with the splash.
const LOGO_PATH := "res://art/ui/mindmorph_logo.png"
const FADE_IN_SECONDS := 0.60
const HOLD_SECONDS := 0.70
const FADE_OUT_SECONDS := 0.60
const END_HOLD_SECONDS := 0.10
## Headless runs (verify.sh boots for 200 frames, tests) play the same sequence this much faster.
const HEADLESS_SPEED := 10.0
## The timeline advances at most this much per frame. The first frames after the engine
## starts (and while the loading threads begin) can be long — 0.3 s measured headless — and
## a tween would jump over half of the fade-in; this way the logo is always seen arriving.
const MAX_STEP := 0.1
## True when a following cover keeps the full-screen aspect (game/startup.gd sets it right
## before removing this layer): then leaving the tree does not restore the game's aspect.
var hand_over := false

var _root: Control
var _logo: TextureRect
var _window: Window
var _previous_aspect: Window.ContentScaleAspect
## Seconds into the logo sequence; negative until the first plain green frame has shown.
var _t := -1.0
var _done := false


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_window = get_tree().root
	_previous_aspect = _window.content_scale_aspect
	# Fill the whole device, including the wide margins on 16:9 and wider phones.
	# The existing game aspect is restored when this layer leaves the tree.
	_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	RenderingServer.set_default_clear_color(BACKGROUND)
	_root = Control.new()
	_root.name = "StartupBackground"
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo = TextureRect.new()
	_logo.name = "BusinessLogo"
	_logo.texture = load(LOGO_PATH)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# D4: the 1024 px vector-redrawn master (art/ui/mindmorph_logo.svg) is drawn at about half size on
	# most screens; its mipmaps keep the M's diagonals and the cube's edges clean.
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	_root.add_child(_logo)
	_root.resized.connect(_layout_logo)
	_layout_logo()


func _layout_logo() -> void:
	var side := floorf(minf(_root.size.x, _root.size.y) * 0.64)
	_logo.size = Vector2.ONE * side
	_logo.position = ((_root.size - _logo.size) * 0.5).floor()


## Fade in, hold, fade out (sine in-out), then a short plain green hold before `finished`.
func _process(dt: float) -> void:
	if _done:
		return
	if _t < 0.0:
		# Render the same plain green as the native boot screen before fading in.
		_t = 0.0
		return
	var speed := HEADLESS_SPEED if DisplayServer.get_name() == "headless" else 1.0
	_t += minf(dt, MAX_STEP) * speed
	_logo.modulate.a = alpha_at(_t)
	if _t >= FADE_IN_SECONDS + HOLD_SECONDS + FADE_OUT_SECONDS + END_HOLD_SECONDS:
		_done = true
		finished.emit()


## The logo's opacity `t` seconds into the sequence.
static func alpha_at(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t < FADE_IN_SECONDS:
		return 0.5 - 0.5 * cos(PI * t / FADE_IN_SECONDS)
	t -= FADE_IN_SECONDS
	if t < HOLD_SECONDS:
		return 1.0
	t -= HOLD_SECONDS
	if t < FADE_OUT_SECONDS:
		return 0.5 + 0.5 * cos(PI * t / FADE_OUT_SECONDS)
	return 0.0


## The window aspect the game had before this logo (the loading cover restores it).
func original_aspect() -> int:
	return _previous_aspect


## How visible the logo is now (0..1), for the startup preview and checks.
func logo_alpha() -> float:
	return _logo.modulate.a if _logo != null else 0.0


## Where the logo sits on the cover (cover coordinates).
func logo_rect() -> Rect2:
	return Rect2(_logo.position, _logo.size) if _logo != null else Rect2()


## The cover's size (the whole device in EXPAND aspect).
func cover_size() -> Vector2:
	return _root.size if _root != null else Vector2.ZERO


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(_window) and not hand_over:
		_window.content_scale_aspect = _previous_aspect
