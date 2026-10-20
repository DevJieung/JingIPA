class_name StartupLoading
extends CanvasLayer

## Cold-start loading screen (F8, 2026-10-19 「MindMorph 로고 뜨고 Fadeout 한 다음에 Stellar
## Defense 그림과 Loading 바를 그 밑에 추가」). It follows the logo (StartupSplash) and covers
## the real work, one step per frame at most so the bar keeps moving:
##   load      the threaded loads requested when the logo began (request()): the title's
##             portraits, the title music and the GLB bodies the arena world warms with
##   main      the screen scripts compiled one per frame (SCRIPTS: the single longest stall,
##             ~0.7 s headless on this box), then game/main.gd (no longer preloaded by
##             game/startup.gd) and Main built under this cover with `interactive = false`
##   backdrop  Main's persistent title backdrop: its 3D world and render target (F7)
##   title     the title screen; its first draw builds the battlefield map in that world
##   warm      WARM_FRAMES frames rendered under the cover (first-use GL shader compiles)
##   settle    the bar finishes easing to 100 % (the cover stays at least MIN_SECONDS)
##   reveal    the picture dips to black, the window aspect is restored (unseen: the
##             letterbox bars are black too) and the title music starts (Main.uncover)
##   lift      the black veil fades off the title
##   done      Main.reveal(): input, back button and frame budget are Main's; `finished`
## `progress` (0..1, never goes back) moves only when a threaded load reports progress or a
## step finishes. The bar draws `shown`, which eases after it and reaches 1.0 only after it.
## Input: game/startup.gd puts Main before this layer, so this layer's _input runs before
## every node of Main and swallows each event until `done`. (The Android back button is a
## notification, not an event: Main ignores it while it is not interactive.)
## Frames are counted on process_frame: RenderingServer.frame_post_draw never fires headless.
## Headless runs (verify.sh step 3, tests) skip the easing and the minimum time.
##
## ★ Drawing is _draw_cover() only — that function is the design's (D4). It reads `progress`,
##   `shown`, `phase`, `art` (key art; null = placeholder), `intro` (0..1 fade-in from the
##   logo green), `outro` (0..1 dip to black) and `veil` (1..0, black over the title).
signal finished

## The logo screen's green (StartupSplash.BACKGROUND): the first loading frame matches it.
const GREEN := Color8(35, 93, 72)
## Key art (texture path). Empty = placeholder until D4 delivers the art.
const ART_PATH := "res://art/ui/stellar_keyart.png"
const MAIN_SCRIPT := "res://game/main.gd"
## What game/main.gd pulls in that the autoloads have not compiled yet, heaviest first; one
## per frame so the bar moves through the compile instead of freezing on it.
const SCRIPTS := ["res://game/title_screen.gd", "res://game/arena_screen.gd", "res://game/menu_overlay.gd",
	"res://game/draw_screen.gd", "res://game/shop_screen.gd"]
## The title's two portraits (game/title_screen.gd draws brasa and thalassa at grade 9).
const TITLE_UNITS := [["brasa", 9], ["thalassa", 9]]
const MUSIC := "res://art/bgm/camp.ogg"
## The bodies ArenaWorld._warm_bodies() buries under every field (its GLB loads here).
const WARM_HERO := "echo"
const WARM_MONSTER := "ember_imp"
## Where each step leaves the bar.
const STEP := {"load": 0.40, "main": 0.50, "backdrop": 0.64, "title": 0.80, "warm": 1.0}
const WARM_FRAMES := 8
const WARM_FRAMES_FAST := 2
const INTRO_SECONDS := 0.35
const MIN_SECONDS := 1.5  # 2026-10-19: long enough for the key art to register (D4: at 0.6 s the finished picture showed ~0.3 s)
const OUTRO_SECONDS := 0.25
const VEIL_SECONDS := 0.35
## Give-ups that keep a broken asset from holding the cover forever.
const LOAD_TIMEOUT := 12.0
const BUILD_TIMEOUT := 6.0
## Bar easing: exponential rate, plus a floor speed so it always arrives.
const EASE_RATE := 7.0
const EASE_MIN := 0.6

var progress := 0.0
var shown := 0.0
var phase := "wait"
var art: Texture2D = null
var intro := 0.0
var outro := 0.0
var veil := 0.0
## Where Main is added (game/startup.gd); the parent when unset.
var host: Node = null
var main: Node2D = null
## The window aspect to restore at reveal (the game's own; the logo set EXPAND before this).
var restore_aspect: int = -1

var _fast := false
var _window: Window
var _canvas: Control
var _requests: PackedStringArray = []
var _requested := false
var _taken: Dictionary = {}
var _held: Array = []
var _age := 0.0
var _phase_age := 0.0
var _warm_left := 0
var _script_index := 0
var _built := false
var _aspect_restored := false


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fast = DisplayServer.get_name() == "headless"
	_window = get_tree().root
	if restore_aspect < 0:
		restore_aspect = _window.content_scale_aspect
	# Fill the whole device like the logo did; reveal() gives the game its aspect back.
	_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_canvas = Control.new()
	_canvas.name = "LoadingCover"
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_canvas.draw.connect(_draw_cover)
	request()
	_next("load")


## Start the threaded loads. game/startup.gd calls this when the logo begins; _ready calls
## it again (a no-op then). Paths this build does not have are skipped quietly.
func request() -> void:
	if _requested:
		return
	_requested = true
	for path in wanted_paths():
		if path.is_empty() or _requests.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_requests.append(path)


## What the loading screen loads in the background, in order of need.
static func wanted_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	if not ART_PATH.is_empty():
		paths.append(ART_PATH)
	for row in TITLE_UNITS:
		var unit := Roster.unit_by_id(String(row[0]))
		if not unit.is_empty():
			paths.append(StellarPortraits.path(unit, int(row[1])))
	paths.append(MUSIC)
	var hero: Dictionary = NativeCharacterModel.manifest().get("heroes", {}).get(WARM_HERO, {})
	paths.append(String(hero.get("path", "")))
	var monster: Dictionary = NativeMonsterModel.manifest().get("monsters", {}).get(WARM_MONSTER, {})
	paths.append(String(monster.get("path", "")))
	return paths


## Whether the cover is still up (Main must not take input).
func covering() -> bool:
	return phase != "done"


func _input(_event: InputEvent) -> void:
	if covering():
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	_age += dt
	_phase_age += dt
	intro = 1.0 if _fast else minf(1.0, intro + dt / INTRO_SECONDS)
	match phase:
		"load":
			_step_load()
		"main":
			_step_main()
		"backdrop":
			main.backdrop_view()
			_advance(STEP["backdrop"])
			_next("title")
		"title":
			main.show_title()
			_advance(STEP["title"])
			_warm_left = WARM_FRAMES_FAST if _fast else WARM_FRAMES
			_next("warm")
		"warm":
			_step_warm()
		"settle":
			if shown >= 1.0 and (_fast or _age >= MIN_SECONDS):
				_next("reveal")
		"reveal":
			outro = 1.0 if _fast else minf(1.0, outro + dt / OUTRO_SECONDS)
			if outro >= 1.0:
				_restore_aspect()
				veil = 1.0
				if is_instance_valid(main):
					main.uncover()
				_next("lift")
		"lift":
			veil = 0.0 if _fast else maxf(0.0, veil - dt / VEIL_SECONDS)
			if veil <= 0.0:
				_next("done")
				if is_instance_valid(main):
					main.reveal()
				finished.emit()
	_ease(dt)
	if _canvas != null:
		_canvas.queue_redraw()


func _step_load() -> void:
	var total := 0.0
	var pending := false
	for path in _requests:
		if _taken.has(path):
			total += 1.0
			continue
		var report := []
		var status := ResourceLoader.load_threaded_get_status(path, report)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and _phase_age < LOAD_TIMEOUT:
			pending = true
			total += clampf(float(report[0]) if not report.is_empty() else 0.0, 0.0, 1.0)
			continue
		_take(path)
		total += 1.0
	if not _requests.is_empty():
		_advance(STEP["load"] * total / float(_requests.size()))
	if not pending:
		_advance(STEP["load"])
		_next("main")


## Collect one finished load. The resource stays held until this cover is freed, so the
## title's first draw and its music find it in the cache instead of reading storage.
func _take(path: String) -> void:
	var resource := ResourceLoader.load_threaded_get(path)
	_taken[path] = resource
	if resource != null:
		_held.append(resource)
	if path == ART_PATH and resource is Texture2D:
		art = resource


func _step_main() -> void:
	if _script_index < SCRIPTS.size():
		var path: String = SCRIPTS[_script_index]
		_script_index += 1
		if ResourceLoader.exists(path):
			load(path)
		_advance(lerpf(STEP["load"], STEP["main"], float(_script_index) / float(SCRIPTS.size() + 1)))
		return
	var script := load(MAIN_SCRIPT) as Script
	if script == null:
		# A build without its main script cannot start; do not hold the cover over nothing.
		_next("done")
		finished.emit()
		return
	main = script.new()
	main.name = "Main"
	main.interactive = false
	var parent := host if host != null else get_parent()
	parent.add_child(main)
	# Before this cover in the tree: _input runs from the last node back, so this layer
	# sees (and swallows) every event before any node of Main.
	parent.move_child(main, 0)
	_advance(STEP["main"])
	_next("backdrop")


func _step_warm() -> void:
	if not _built:
		var view: ArenaView = main.backdrop
		if (view != null and view.is_built()) or _phase_age >= BUILD_TIMEOUT:
			_built = true
		else:
			return
	_warm_left -= 1
	var frames := WARM_FRAMES_FAST if _fast else WARM_FRAMES
	_advance(lerpf(STEP["title"], STEP["warm"], 1.0 - float(maxi(0, _warm_left)) / float(frames)))
	if _warm_left <= 0:
		_advance(1.0)
		_next("settle")


func _next(name: String) -> void:
	phase = name
	_phase_age = 0.0


func _advance(value: float) -> void:
	progress = clampf(maxf(progress, value), 0.0, 1.0)


func _ease(dt: float) -> void:
	var gap := progress - shown
	if _fast or gap <= 0.0005:
		shown = maxf(shown, progress)
		return
	shown = minf(progress, shown + maxf(gap * minf(1.0, dt * EASE_RATE), dt * EASE_MIN))


func _restore_aspect() -> void:
	if _aspect_restored:
		return
	_aspect_restored = true
	if is_instance_valid(_window):
		_window.content_scale_aspect = restore_aspect as Window.ContentScaleAspect


func _exit_tree() -> void:
	_restore_aspect()
	collect()


## Collect every threaded load still out (a cover removed early: tests, quitting).
func collect() -> void:
	for path in _requests:
		if not _taken.has(path):
			_take(path)


# --------------------------------------------------------------------------- #
# 그리기 — 디자인 담당(D4) 구간. 위의 상태 변수만 읽는다.
# --------------------------------------------------------------------------- #
## D4 (2026-10-19): the Stellar Defense key art — the four guardians around the Soul Stone on
## its altar (art/ui/stellar_keyart.png, ART_PATH) — under the wordmark lockup, with the bar on
## the ground in front of them. Everything fades in with `intro` out of the logo's green; the dip
## (`outro`) and the veil over the title stay black. The art never pops in: when it arrives after
## the cover appeared it fades over ART_FADE. One static drawer (draw_layers) serves this cover
## and the brand study tests/brand/loading_preview.tscn, so both show the same picture.
## The lockup (soul-stone crest + metal title + subtitle) is baked per locale — the one recorded
## exception to "no text in images" (tests/brand/lockup_bake.tscn, tools/brand/lockup.py).
## Loaded by the cover itself (not preloaded: this script stays loaded for the app's life, the
## texture should leave with the cover).
const LOCKUP_PATH := {"ko": "res://art/ui/brand_lockup_ko.png", "en": "res://art/ui/brand_lockup_en.png"}
const NIGHT := Color("#060c14")
## Where the key art sits when the screen is taller than it (cover fit; 0 top .. 1 bottom).
const ART_FOCUS := Vector2(0.5, 0.55)
## The Soul Stone in the key art (UV) and its glow radius (share of the drawn art height).
const ART_STONE := Vector2(0.5, 0.465)
const ART_STONE_RADIUS := 0.21
const ART_FADE := 0.35
## Lockup band at the top of the cover (logical px; EXPAND keeps it at the top edge).
const LOCKUP_TOP := 18.0
const LOCKUP_HEIGHT := 200.0
## Bar: 42 % of the width within these bounds, its top this far above the bottom edge.
const BAR_WIDTH := Vector2(440.0, 620.0)
const BAR_HEIGHT := 12.0
const BAR_LIFT := 66.0
const SPARKS := 22
var _art_since := -1.0
var _lockup: Texture2D = null


func _draw_cover() -> void:
	if _canvas.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		# The art and the lockup are drawn smaller than their textures on most screens.
		_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if art != null and _art_since < 0.0:
		_art_since = _age
	if _lockup == null:
		_lockup = lockup_texture()
	var art_k := 0.0 if art == null else clampf((_age - _art_since) / ART_FADE, 0.0, 1.0)
	draw_layers(_canvas, Rect2(Vector2.ZERO, _canvas.size), phase, shown, art, _lockup, art_k, intro, outro, veil, _age)


## The wordmark lockup of the current language.
static func lockup_texture() -> Texture2D:
	return load(String(LOCKUP_PATH.get(I18n.locale, LOCKUP_PATH["ko"]))) as Texture2D


## The whole cover for one frame. `art_k` 0..1 is the art's own fade-in, `t` drives the stone's
## breathing and the drifting sparks.
static func draw_layers(ci: CanvasItem, area: Rect2, at_phase: String, bar_value: float, key_art: Texture2D,
		lockup: Texture2D, art_k: float, intro_k: float, outro_k: float, veil_k: float, t: float) -> void:
	if at_phase == "lift" or at_phase == "done":
		ci.draw_rect(area, Color(0, 0, 0, veil_k))
		return
	var k := 1.0 - pow(1.0 - clampf(intro_k, 0.0, 1.0), 3.0)
	ci.draw_rect(area, GREEN)
	ci.draw_rect(area, Color(NIGHT, k))
	if key_art != null and art_k > 0.0:
		var ts := Vector2(key_art.get_size())
		var a := k * (1.0 - pow(1.0 - art_k, 2.0))
		var zoom := 1.0 + 0.03 * (1.0 - a)
		var ds := ts * maxf(area.size.x / ts.x, area.size.y / ts.y) * zoom
		var rect := Rect2(area.position + (area.size - ds) * ART_FOCUS, ds)
		ci.draw_texture_rect(key_art, rect, false, Color(1, 1, 1, a))
		_draw_stone_glow(ci, rect.position + ART_STONE * ds, ds.y * ART_STONE_RADIUS, a, t)
	_draw_sparks(ci, area, k, t)
	_vgrad(ci, Rect2(area.position.x, area.position.y, area.size.x, 270.0), Color(NIGHT, 0.55 * k), Color(NIGHT, 0.0))
	_vgrad(ci, Rect2(area.position.x, area.end.y - 210.0, area.size.x, 210.0), Color(NIGHT, 0.0), Color(NIGHT, 0.86 * k))
	_draw_lockup(ci, area, lockup, k)
	_draw_bar(ci, bar_rect(area), bar_value, k, t)
	if outro_k > 0.0:
		ci.draw_rect(area, Color(0, 0, 0, outro_k))


static func lockup_rect(area: Rect2, tex: Texture2D) -> Rect2:
	var size := Vector2(tex.get_size()) * (LOCKUP_HEIGHT / float(tex.get_height()))
	return Rect2(area.position.x + (area.size.x - size.x) * 0.5, area.position.y + LOCKUP_TOP, size.x, size.y)


static func bar_rect(area: Rect2) -> Rect2:
	var w := clampf(area.size.x * 0.42, BAR_WIDTH.x, BAR_WIDTH.y)
	return Rect2(area.position.x + (area.size.x - w) * 0.5, area.end.y - BAR_LIFT, w, BAR_HEIGHT)


static func _draw_lockup(ci: CanvasItem, area: Rect2, tex: Texture2D, k: float) -> void:
	if k <= 0.003 or tex == null:
		return
	var r := lockup_rect(area, tex)
	# Lands with the art: a 4 % settle around its centre.
	var grow := 1.0 + 0.04 * (1.0 - k)
	ci.draw_texture_rect(tex, Rect2(r.get_center() - r.size * grow * 0.5, r.size * grow), false, Color(1, 1, 1, k))


## The stone's light breathing over the painting: a soft cyan pool, never brighter than the art.
static func _draw_stone_glow(ci: CanvasItem, c: Vector2, radius: float, a: float, t: float) -> void:
	var breath := 0.5 + 0.5 * sin(t * 2.4)
	var core := Color(Look.CRYSTAL, (0.10 + 0.08 * breath) * a)
	var rim := Color(Look.CRYSTAL, 0.0)
	var r := radius * (0.92 + 0.08 * breath)
	var cols := PackedColorArray([core, rim, rim])
	# A fan of triangles (one outline polygon cannot hold its own centre).
	for i in range(40):
		ci.draw_polygon(PackedVector2Array([c, c + Vector2.from_angle(TAU * float(i) / 40.0) * r,
			c + Vector2.from_angle(TAU * float(i + 1) / 40.0) * r]), cols)


## Fireflies and soul sparks rising through the scene (seeded by index, so every run is the same).
static func _draw_sparks(ci: CanvasItem, area: Rect2, k: float, t: float) -> void:
	if k <= 0.003:
		return
	for i in range(SPARKS):
		var h1 := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var h2 := fposmod(sin(float(i) * 78.233) * 12345.678, 1.0)
		var h3 := fposmod(sin(float(i) * 39.425) * 24634.6345, 1.0)
		var rise := 10.0 + 18.0 * h2
		var span := area.size.y * 0.62
		var y := area.end.y - 40.0 - fposmod(h1 * span + t * rise, span)
		var x := area.position.x + area.size.x * (0.06 + 0.88 * h3) + sin(t * (0.6 + h1) + h2 * TAU) * 9.0
		var twinkle := maxf(0.0, sin(t * (1.6 + 2.2 * h2) + h1 * TAU))
		var warm := i % 3 != 0
		var col := Look.STARLIGHT if warm else Look.CRYSTAL
		var size := 1.4 + 1.8 * h3
		var fade := clampf((area.end.y - 40.0 - y) / 60.0, 0.0, 1.0) * clampf((y - (area.end.y - 40.0 - span)) / 80.0, 0.0, 1.0)
		var alpha := k * fade * (0.25 + 0.6 * twinkle)
		ci.draw_circle(Vector2(x, y), size * 3.2, Color(col, alpha * 0.22), true, -1, true)
		ci.draw_circle(Vector2(x, y), size, Color(col, alpha), true, -1, true)


## Dark glass track with a gold rim and gold end diamonds (the wordmark's rules), soul-stone
## cyan fill with a lit head, the percentage above — digits only, nothing to translate.
static func _draw_bar(ci: CanvasItem, r: Rect2, value: float, a: float, t: float) -> void:
	if a <= 0.003:
		return
	var radius := r.size.y * 0.5
	# Gold rim (outline_round fills under), a dark gap, then the track.
	Look.outline_round(ci, r.grow(3.0), radius + 3.0, Color(Look.GOLD_DEEP, 0.95 * a), 1.5)
	Look.fill_round(ci, r.grow(3.0), radius + 3.0, Color(NIGHT, 0.92 * a))
	Look.fill_round(ci, r, radius, Color(0.02, 0.05, 0.08, 0.96 * a))
	var fw := r.size.x * clampf(value, 0.0, 1.0)
	if fw > 0.5:
		var fill := Rect2(r.position, Vector2(maxf(fw, r.size.y), r.size.y))
		_hgrad_round(ci, fill, radius, Color(Look.CRYSTAL_DEEP, a), Color(Look.CRYSTAL, a), r.size.x)
		ci.draw_line(fill.position + Vector2(radius, 2.5), Vector2(fill.end.x - radius, fill.position.y + 2.5),
			Color(1, 1, 1, 0.35 * a), 1.5, true)
		var head := Vector2(fill.end.x - radius, r.get_center().y)
		var pulse := 0.85 + 0.15 * sin(t * 6.0)
		for i in range(4):
			ci.draw_circle(head, radius + 2.0 + float(i) * 3.5, Color(Look.CRYSTAL, (0.22 - float(i) * 0.05) * a * pulse), true, -1, true)
		ci.draw_circle(head, radius * 0.7, Color(Look.CRYSTAL_INK, a), true, -1, true)
	for side in [-1.0, 1.0]:
		var p := Vector2(r.get_center().x + side * (r.size.x * 0.5 + 16.0), r.get_center().y)
		Look.draw_diamond(ci, p, 7.0, Color(Look.BG_DEEP, 0.9 * a))
		Look.draw_diamond(ci, p, 4.5, Color(Look.GOLD, a))
	Look.text_center(ci, Vector2(r.get_center().x, r.position.y - 20.0), "%d%%" % int(round(value * 100.0)), 18,
		Color(Look.INK_DIM, 0.95 * a))


static func _vgrad(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## A pill filled left to right from `from` to the colour `full` reaches at the bar's whole width.
static func _hgrad_round(ci: CanvasItem, r: Rect2, radius: float, from: Color, full: Color, whole: float) -> void:
	var to := from.lerp(full, clampf(r.size.x / maxf(whole, 1.0), 0.0, 1.0))
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in range(11):
		var ang := PI * 0.5 + PI * float(i) / 10.0
		pts.append(Vector2(r.position.x + radius, r.get_center().y) + Vector2.from_angle(ang) * radius)
		cols.append(from)
	for i in range(11):
		var ang := -PI * 0.5 + PI * float(i) / 10.0
		pts.append(Vector2(r.end.x - radius, r.get_center().y) + Vector2.from_angle(ang) * radius)
		cols.append(to)
	ci.draw_polygon(pts, cols)
