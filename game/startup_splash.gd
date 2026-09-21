class_name StartupSplash
extends CanvasLayer

## The startup wrapper adds this before Main, then removes it after finished.
## Keep the opaque background in place until the wrapper has prepared the title.
signal finished

const BACKGROUND := Color8(35, 93, 72)
const LOGO := preload("res://art/ui/startup_logo.png")
const FADE_IN_SECONDS := 0.60
const HOLD_SECONDS := 0.70
const FADE_OUT_SECONDS := 0.60
const END_HOLD_SECONDS := 0.10

var _root: Control
var _logo: TextureRect
var _window: Window
var _previous_aspect: Window.ContentScaleAspect


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
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	_root.add_child(_logo)
	_root.resized.connect(_layout_logo)
	_layout_logo()
	_play.call_deferred()


func _layout_logo() -> void:
	var side := floorf(minf(_root.size.x, _root.size.y) * 0.64)
	_logo.size = Vector2.ONE * side
	_logo.position = ((_root.size - _logo.size) * 0.5).floor()


func _play() -> void:
	# Render the same plain green as the native boot screen before fading in.
	await get_tree().process_frame
	var tween := create_tween()
	tween.tween_property(_logo, "modulate:a", 1.0, FADE_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(_logo, "modulate:a", 0.0, FADE_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Several fully blank frames remain before Main can enter the tree.
	tween.tween_interval(END_HOLD_SECONDS)
	tween.tween_callback(finished.emit)


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(_window):
		_window.content_scale_aspect = _previous_aspect
