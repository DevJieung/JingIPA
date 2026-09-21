extends Harness

var main: Node2D
var output := "build/element-matrix/1280x800"


func capture_chart(language: String, state: String) -> void:
	await paint(main.menu)
	check(tap(main.menu, "menu") and main.menu.opened, "menu opens from " + state)
	await paint(main.menu)
	check(tap(main.menu, "page:elements"), "element chart tab is reachable")
	await paint(main.menu)
	check(main.menu.page == "elements", "element chart is selected")
	check(not main.screen.is_processing() and not main.screen.is_processing_input(), "chart pauses background gameplay and input")
	await snap(output + "/" + language + "_" + state + ".png")
	for source in ["캐릭터 속성 ↓", "몬스터 속성 →", "피해 배율", "2배", "1배", "0.5배", "0배"]:
		check(I18n.observed.has(source), "rendered chart includes " + source)
	for body in Balance.MBODY_ORDER:
		check(Look.text_width(Balance.body_ko(body), 20) <= 108.0, "translated monster heading fits")
	for element in MenuOverlay.ELEMENT_ROWS:
		check(Look.text_width(Balance.elem_ko(element), 22) <= 114.0, "translated character heading fits")
	check(tap(main.menu, "resume") and not main.menu.opened, "chart closes through its actual button")
	check(main.screen.is_processing() and main.screen.is_processing_input(), "closing chart restores gameplay and input")


func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly = true
	output = arg("--out", output)
	DirAccess.make_dir_recursive_absolute(output)
	main = load("res://game/main.gd").new()
	add_child(main)
	I18n.audit_enabled = true
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		Run.running = false
		main.show_title()
		await capture_chart(language, "title")
		Fixture.prepare(20, 16092026)
		Run.begin_draw()
		Run.confirm_hand()
		Run.prepare_battle()
		main._swap(BattleScreen.new())
		await capture_chart(language, "battle")
		check(I18n.missing.is_empty(), "all rendered chart labels are translated in " + language)
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Element matrix preview")
