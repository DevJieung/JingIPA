extends Harness

## D2 (feedback 2026-10-19, F1/F2/F3): the level-up flow photographed through the real game —
## main → title → the arena screen, a stage's first box, a wave in which levels are earned, the
## preparation that opens the popup (top-down entrance, the buttons arming last), the pick's
## flourish while the battle holds, the following offer (cards only), the map from the popup
## and back (the buttons arm again), the last pick, the field banner, and the rail's viewer.
##
##   godot --disable-vsync --path . --resolution 96x60 res://tests/constellation_flow.tscn -- \
##       --film 1280x800 --out build/feedback-2026-10-19/D2/flow/1280x800 [--locales ko,en]
##
## The screen runs on its own clock by hand (Engine.time_scale 0, _process(1/60) per frame, as
## tests/arena_play_check does); a picture is kept every third frame (0.05 s) through motion.
## The wave is shortened, not faked: everything left of it spawns and falls at once, the kills
## pay the level, the wave is held and the simulator's preparation opens the popup.

var out_dir := ""
var film: SubViewport
var main: Node
var screen: ArenaScreen
var locale := "ko"
var _index: Array = []
var _shot := 0


func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", "build/feedback-2026-10-19/D2/flow/1280x800")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_open_film()
	var saved_locale := I18n.locale
	for code in arg("--locales", "ko,en").split(",", false):
		locale = code
		I18n.set_locale(code)
		_shot = 0
		await _flow()
	I18n.set_locale(saved_locale)
	Engine.time_scale = 1.0
	var file := FileAccess.open(out_dir + "/index.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_index, "  ") + "\n")
	file = null
	finish("Constellation flow")


func _flow() -> void:
	Engine.time_scale = 1.0
	Run.running = false
	Arena.running = false
	Save.cur_run.clear()
	main = load("res://game/main.gd").new()
	if film != null: film.add_child(main)
	else: add_child(main)
	await paint(main.screen)
	check(tap(main.screen, "start"), "title start")
	check(await wait_screen(main, "arena_screen", 1200), "arena screen")
	screen = main.screen
	screen.set_process(false)
	await paint(screen)
	check(tap(screen, "stage:start") and Arena.modal == "box", "stage card -> first box")
	await paint(screen)
	var index := JewelBox.best(Arena.box_cards)
	check(screen.box_ready() and tap(screen, "box:pick:%d" % index), "box pick")
	await paint(screen)
	check(tap(screen, "close") and Arena.modal == "", "box closed, preparation")
	await paint(screen)
	for i in range(600):
		if float(main.get("_fade_dir")) == 0.0: break
		await frames(1)
	Engine.time_scale = 0.0
	screen.set_process(true)
	await _step(4)
	# Wave 1: monsters come, the heroes fight.
	check(Arena.sim.skip_prep(), "wave 1 starts")
	await _step(150)
	await _keep("wave")
	# A level earned in the wave waits: the popup does not open while monsters are out.
	Arena.gain_xp(float(Arena.xp_needed()) + 0.1)
	await _step(30)
	check(Arena.pending_levels == 1 and Arena.modal == "", "a level earned in the wave waits for the preparation")
	await _keep("wave_level_waits")
	# The last of the wave: everything left spawns and falls; its last kill pays one more level.
	Arena.xp = float(Arena.xp_needed()) - 0.01
	Arena.gain_xp(0.02)
	var sim = Arena.sim
	sim._wave_spawned = sim._wave_list.size()
	for mo in sim.monsters:
		mo["hp"] = 0.0
	# The popup: from its first picture to armed and a little past (every third frame).
	var opened := false
	for f in range(4):
		screen._process(1.0 / 60.0)
		await frames(1)
		if Arena.modal == "talent":
			opened = true
			break
	check(opened and Arena.sim.in_prep() and Arena.pending_levels == 2, "the preparation opens the popup with two levels waiting")
	check(Constellation._icons.size() >= Balance.TALENTS.size(), "every node glyph was loaded before the popup (%d)" % Constellation._icons.size())
	await _motion("popup", 1.08, 3)
	check(screen.talent_armed(), "the popup armed (%.2f s)" % screen.talent_entrance_age())
	await _keep("popup_armed")
	# Press and hold the middle card's button: the pressed look, then the release picks.
	var first := String(Arena.talent_offer[1])
	check(press(screen, "talent:pick:" + first), "press a pick")
	await _step(2)
	await _keep("popup_pressed")
	var zone := zone_of(screen, "talent:pick:" + first)
	mouse(screen, Rect2(zone["rect"]).get_center(), false)
	check(Arena.talent_count(first) == 1 and screen.pick_hold_age() >= 0.0, "release picks; the flourish holds the battle")
	await _motion("pick_hold", ArenaScreen.PICK_HOLD + 0.03, 3)
	# The following offer: its cards only, the shorter arming.
	check(screen.talent_followup and Arena.modal == "talent", "the following offer")
	await _motion("follow", 0.60, 3)
	# The map from the popup: overview, a constellation, a star, and back to the same offer.
	check(tap(screen, "talent:map") and screen.talent_map, "the map button")
	await _motion("map_open", 0.20, 3)
	await _keep("map_overview")
	var group := String(Talents.by_id(String(Arena.talent_offer[0])).get("group", ""))
	check(tap(screen, "talent:group:" + group) and screen.map_focus == group, "a constellation on the map")
	await _step(6)
	await _keep("map_focus")
	# A star that could be picked but is not on offer: its card says this level picks from the three.
	var node := ""
	var node_states := Constellation.states(Arena.talents, Arena.owned_passives, Arena.levels)
	for wanted in ["open", "locked", "joined", "full"]:
		for zone_entry in screen.ui.zones:
			var id := String(zone_entry["id"]).trim_prefix("talent:node:")
			if String(zone_entry["id"]).begins_with("talent:node:") and bool(zone_entry["on"]) and not Arena.talent_offer.has(id) \
					and String(node_states.get(id, "")) == wanted:
				node = id
				break
		if not node.is_empty():
			break
	check(not node.is_empty() and tap(screen, "talent:node:" + node) and screen.map_node == node, "a star on the map")
	await _step(6)
	await _keep("map_node")
	check(tap(screen, "talent:group:") and screen.map_focus == "", "back to the overview")
	await _step(4)
	check(tap(screen, "talent:back") and not screen.talent_map and Arena.modal == "talent", "back to the offer")
	await _motion("map_back", 0.55, 3)
	# The last pick: the popup leaves with the star, the battle resumes, the banner lands.
	var last := String(Arena.talent_offer[0])
	check(tap(screen, "talent:pick:" + last) and Arena.pending_levels == 0, "the last pick")
	await _motion("pick_last", ArenaScreen.PICK_HOLD + 0.03, 3)
	# The wave just held keeps the banner row first; the joined star's banner follows it.
	await _motion("held", 1.9, 30)
	await _motion("banner", 1.0, 6)
	# The rail's viewer: the map with nothing on offer.
	check(tap(screen, "talents") and screen.talent_map and Arena.talent_offer.is_empty(), "the rail's constellations")
	await _step(12)
	await _keep("viewer")
	check(tap(screen, "talent:group:" + group), "a constellation in the viewer")
	await _step(6)
	await _keep("viewer_focus")
	check(tap(screen, "close") and Arena.modal == "", "the viewer closes")
	await _step(4)
	screen.set_process(false)
	Engine.time_scale = 1.0
	Arena.running = false
	main.queue_free()
	await frames(3)


## `n` frames of the screen's clock (1/60 s each), each one drawn.
func _step(n: int) -> void:
	for i in range(n):
		screen._process(1.0 / 60.0)
		await frames(1)


## Keep a picture every `every` frames for `seconds`.
func _motion(name: String, seconds: float, every: int) -> void:
	var frames_total := ceili(seconds * 60.0)
	var n := 0
	for i in range(frames_total):
		if i % every == 0:
			await _keep("%s_%02d" % [name, n])
			n += 1
		screen._process(1.0 / 60.0)
		await frames(1)


func _keep(name: String) -> void:
	screen.queue_redraw()
	await RenderingServer.frame_post_draw
	var picture: Viewport = film if film != null else get_viewport()
	var file_name := "%s_%02d_%s" % [locale, _shot, name]
	_shot += 1
	picture.get_texture().get_image().save_png(out_dir + "/" + file_name + ".png")
	_index.append(file_name)


func _open_film() -> void:
	var spec := arg("--film", "")
	if spec.is_empty(): return
	var size := Vector2i(int(spec.get_slice("x", 0)), int(spec.get_slice("x", 1)))
	get_window().size = Vector2i(96, 60)
	film = SubViewport.new()
	film.size = size
	film.size_2d_override = Vector2i(1280, 800)
	film.size_2d_override_stretch = true
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.transparent_bg = false
	film.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	film.set("oversampling_override", float(size.x) / 1280.0)
	add_child(film)
