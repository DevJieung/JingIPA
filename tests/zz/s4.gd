extends Node
var main: Node2D = null
func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
func _save(name_: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("build/shots/%s.png" % name_)
	print("  saved %s" % name_)

func _ready() -> void:
	main = load("res://game/main.gd").new()
	main.name = "Main"
	add_child(main)
	await get_tree().process_frame
	Run.start_run(20260822)
	for i in range(5):
		Run.begin_draw(); Run.confirm_hand()
	Run.begin_draw()
	var d := DrawScreen.new()
	main._swap(d)
	await _frames(2)
	d._confirm()
	for i in range(400):
		await get_tree().process_frame
		if d.state == DrawScreen.PICK:
			break
	print("A: rt=%.2f state=%d(PICK=%d) fade=%.2f screen_is_DrawScreen=%s"
		% [d.rt, d.state, DrawScreen.PICK, main._fade, str(main.screen == d)])
	await _save("A_after_leave")
	var before: int = Run.heroes.size()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(640, 738)
	d._input(ev)
	print("A2: heroes %d -> %d  state=%d rt=%.2f" % [before, Run.heroes.size(), d.state, d.rt])
	get_tree().quit(0)
