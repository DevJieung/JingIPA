extends Node2D

var output := "build/chibi-review/1280x800"
var mode := "heroes"
var phase := 0.0
var attack := false
var main: Node2D


func _ready() -> void:
	if OS.get_environment("STELLARDEFENSE_NO_SAVE") != "1":
		get_tree().quit(1)
		return
	Save._readonly = true
	var arguments := OS.get_cmdline_user_args()
	var output_index := arguments.find("--out")
	if output_index >= 0 and output_index + 1 < arguments.size():
		output = arguments[output_index + 1]
	DirAccess.make_dir_recursive_absolute(output)
	for current_mode in ["heroes", "monsters"]:
		mode = current_mode
		for frame_index in range(16):
			phase = float(frame_index) / 16.0
			attack = frame_index >= 8
			queue_redraw()
			await snap("%s/%s_%02d.png" % [output, mode, frame_index])
	mode = ""
	queue_redraw()
	main = load("res://game/main.gd").new()
	add_child(main)
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		Run.start_run(7102026)
		Run.begin_draw()
		var guide_screen := DrawScreen.new()
		main._swap(guide_screen)
		guide_screen.set_process(false)
		guide_screen.skip_spin()
		for step in range(60):
			guide_screen._process(1.0 / 60.0)
		await capture(language + "_guide")
		Run.heroes.clear()
		Run.bench.clear()
		var ids := ["brasa", "sigrid", "marea", "glaukos", "caden", "dummy", "finn", "snorri", "jokull", "helga", "lugh", "grey"]
		for index in range(ids.size()):
			var unit := Roster.unit_by_id(ids[index])
			Run.heroes.append({"unit": unit, "tier": int(unit["tier"]), "wave": 1, "n": 1, "post": index})
		Run.last_result = {}
		Run.phase = Run.Phase.SWAP
		var formation := DrawScreen.new()
		main._swap(formation)
		formation.set_process(false)
		formation.state = DrawScreen.SWAP
		await capture(language + "_formation_full")
		formation.formation_tab = false
		await capture(language + "_cards")
		for selected in [0, 1, 2, 4, 7]:
			formation.hv.info = selected
			await capture(language + "_detail_" + ids[selected])
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	print("Chibi visual preview complete: ", output)
	get_tree().quit()


func frames(count: int) -> void:
	for frame_index in range(count):
		await get_tree().process_frame


func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func capture(stem: String) -> void:
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	await snap(output + "/" + stem + ".png")
	print(stem + ": rendered current game screen")


func _draw() -> void:
	if mode == "":
		return
	draw_rect(Look.SCREEN, Look.BG_DEEP)
	Look.text_center(self, Vector2(640, 28), "캐릭터 비례 검수 · " + mode, 24, Look.INK)
	if mode == "heroes":
		for index in range(Roster.UNITS.size()):
			var unit: Dictionary = Roster.UNITS[index]
			var origin := Vector2((index % 10) * 128, 48 + (index / 10) * 148)
			draw_rect(Rect2(origin + Vector2(4, 2), Vector2(120, 143)), Look.PANEL)
			Look.text_center(self, origin + Vector2(64, 17), Look.unit_name(unit), 15, Look.GOLD)
			var clip := Anim.clip(unit, "attack" if attack else "idle")
			var current_time := (phase * 2.0 - 1.0 if attack else phase * 2.0) * float(clip["total"]) / 1000.0
			Anim.draw_frame(self, clip, Anim.frame_at(clip, current_time), origin.x + 60, origin.y + 129, 0.64)
	else:
		for index in range(Roster.MONSTERS.size()):
			var monster: Dictionary = Roster.MONSTERS[index]
			var origin := Vector2(12 + (index % 5) * 253, 48 + (index / 5) * 148)
			draw_rect(Rect2(origin, Vector2(244, 143)), Look.PANEL)
			Look.text_center(self, origin + Vector2(122, 18), String(monster["ko"]), 17, Look.GOLD)
			var clip := Anim.clip(monster, "move")
			var current_time := phase * float(clip["total"]) / 1000.0
			Anim.draw_frame(self, clip, Anim.frame_at(clip, current_time), origin.x + 122, origin.y + 136,
					0.70 if monster["kind"] == "boss" else 1.35)
