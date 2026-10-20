extends Harness
## The jewel box in the real game flow (F10/F11, D1): title → 「시작」 → STAGE 1's battlefield card →
## the free first box of the first preparation → reroll → pick → result → close → the wave → (the wave
## held at once, rewards untouched) → the next preparation → the rail's paid box → a 4-star and a
## 5-star box (forced for the capture: their grade and cards are set right after the box opens, before
## its first picture). Every frame of the boxes and every third of the rest is kept, per segment.
##
##   godot --path . --fixed-fps 30 --disable-vsync res://tests/box_flow_capture.tscn -- \
##       --out DIR --lang ko|en [--film 1280x800]
##
## tests/box_flow_review.py runs it on the GPU display at both sizes and languages and makes the movies.

var main: Node2D
var film: SubViewport
var out := "build/feedback-2026-10-19/D1/flow"
var _segment := ""
var _saved := 0
var _frame := 0
var _log: Array = []
var _t := 0.0


func _ready() -> void:
	if not require_no_save(): return
	out = arg("--out", out)
	DirAccess.make_dir_recursive_absolute(out)
	I18n.set_locale(arg("--lang", "ko"))
	_open_film()
	main = load("res://game/main.gd").new()
	_mount(main)
	await frames(3)
	main.show_title()
	await frames(3)
	await _rec("title", 1.0, 3)
	check(tap(main.screen, "start"), "the title's start opens STAGE 1")
	await _until("to_stage", func(): return main.screen is ArenaScreen and Arena.modal == "stage", 6.0, 3)
	await _rec("to_stage", 1.2, 3)
	var screen: ArenaScreen = main.screen
	check(Arena.stage == 1, "STAGE 1")
	check(tap(screen, "stage:start"), "the battlefield card starts the stage")
	check(Arena.modal == "box", "the first preparation opens the free first box")
	check(Arena.box_tier >= Balance.ARENA_BOX_FIRST_TIER, "the first box is at least %d-star" % Balance.ARENA_BOX_FIRST_TIER)
	await _box("first_box", screen)
	check(tap(screen, "box:reroll"), "the settled box rerolls")
	await _box("reroll", screen)
	await _pick("pick", screen)
	check(tap(screen, "close"), "the result closes")
	check(Arena.modal.is_empty(), "back to the battle")
	if not tap(screen, "wave:start") and Arena.sim != null:
		Arena.sim.skip_prep()
	await _rec("battle", 2.0, 3)
	# Hold the wave now (no rewards: the list is spent and the field cleared) — the box is the subject.
	Arena.sim._wave_spawned = Arena.sim._wave_list.size()
	Arena.sim.monsters.clear()
	await _until("prep", func(): return Arena.sim.in_prep(), 3.0, 3)
	await _rec("prep", 1.2, 3)
	await _settle_talents(screen)
	Arena.gold = maxi(Arena.gold, 900)
	await frames(2)
	check(tap(screen, "summon"), "the rail's jewel box button opens a paid box in the preparation")
	await _box("paid_box", screen)
	await _pick("paid_pick", screen)
	check(tap(screen, "close"), "the paid box's result closes")
	for grade in [4, 5]:
		await frames(2)
		check(tap(screen, "summon"), "another paid box opens")
		_force(grade)
		await _box("box%d" % grade, screen)
		await _pick("box%d_pick" % grade, screen)
		check(tap(screen, "close"), "the %d-star box's result closes" % grade)
	var f := FileAccess.open(out + "/flow.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed": Arena.run_seed, "frames": _log}, " "))
	f.close()
	finish("보석상자 실제 흐름")


## A box from its first picture until its buttons answer, then half a second of the settled cards.
func _box(name: String, screen: ArenaScreen) -> void:
	await _until(name, func(): return screen.box_ready(), 12.0, 1)
	check(screen.box_ready(), name + ": the cards settle and answer")
	await _rec(name, 0.5, 1)


## Pick the best card (on release, like a finger) and keep the pick until the result answers.
func _pick(name: String, screen: ArenaScreen) -> void:
	var best := JewelBox.best(Arena.box_cards)
	check(tap(screen, "box:pick:%d" % best), name + ": a card is picked")
	check(Arena.phase == Arena.Phase.SWAP, name + ": the pick lands")
	await _until(name, func(): return screen.box_ready(), 4.0, 1)
	await _rec(name, 0.5, 1)


## A level-up popup may open with the preparation: take its first star so the rail answers.
func _settle_talents(screen: ArenaScreen) -> void:
	var guard := 0
	while Arena.modal == "talent" and not Arena.talent_offer.is_empty() and guard < 6:
		Arena.pick_talent(String(Arena.talent_offer[0]))
		await _rec("prep", 0.4, 3)
		guard += 1


## The capture's 4- and 5-star boxes: the box that just opened takes this grade and a fresh deal (one
## more card at 4 stars for the 5-star box), before the screen draws it.
func _force(grade: int) -> void:
	Arena.box_tier = grade
	Arena.box_cards = JewelBox.deal(Arena.rng, Arena._box_pool(), grade, Balance.ARENA_BOX_CARDS, Balance.arena_card_weights())
	for card in Arena.box_cards:
		if not bool(card["guaranteed"]) and grade == 5:
			card["stars"] = 4
			break


## Keep frames for `seconds` of game time (30 per second under --fixed-fps 30), every `every`-th.
func _rec(name: String, seconds: float, every: int) -> void:
	var n := int(round(seconds * 30.0))
	for k in range(n):
		await _step(name, every)


func _until(name: String, done: Callable, limit: float, every: int) -> void:
	var n := int(round(limit * 30.0))
	for k in range(n):
		if bool(done.call()):
			return
		await _step(name, every)


func _step(name: String, every: int) -> void:
	await RenderingServer.frame_post_draw
	if name != _segment:
		_segment = name
		_saved = 0
		DirAccess.make_dir_recursive_absolute(out + "/" + name)
	if _frame % every == 0:
		var path := "%s/%s/%04d.png" % [out, name, _saved]
		_picture().get_texture().get_image().save_png(path)
		var screen = main.screen
		var row := {"segment": name, "frame": _saved, "t": snappedf(_t, 0.001), "modal": Arena.modal}
		if screen is ArenaScreen and Arena.modal == "box":
			row["deal"] = snappedf(screen.box_view.deal_age(), 0.001)
			row["pick"] = snappedf(screen.box_view.pick_age(), 0.001)
			row["ready"] = screen.box_ready()
			row["tier"] = Arena.box_tier
		_log.append(row)
		_saved += 1
	_frame += 1
	_t += 1.0 / 30.0


# --------------------------------------------------------------------------- #
# Picture: an off-screen viewport of the review size (the window only lends its GL context on the
# GPU display), or the window itself (Xvfb). The same as tests/arena_visual_preview.gd.
# --------------------------------------------------------------------------- #
func _open_film() -> void:
	var spec := arg("--film", "")
	if spec.is_empty(): return
	var size := Vector2i(int(spec.get_slice("x", 0)), int(spec.get_slice("x", 1)))
	get_window().size = Vector2i(96, 60)
	film = SubViewport.new()
	film.name = "Film"
	film.size = size
	film.size_2d_override = Vector2i(1280, 800)
	film.size_2d_override_stretch = true
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.transparent_bg = false
	film.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	film.set("oversampling_override", float(size.x) / 1280.0)
	add_child(film)


func _picture() -> Viewport:
	return film if film != null else get_viewport()


func _mount(node: Node) -> void:
	if film != null: film.add_child(node)
	else: add_child(node)
