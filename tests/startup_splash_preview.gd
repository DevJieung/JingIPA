extends Node

var output := "res://build/startup-splash/1280x800"
var metadata: Array[Dictionary] = []
var failures: Array[String] = []


func _ready() -> void:
	if OS.get_environment("POCKER_NO_SAVE") != "1":
		push_error("Run startup preview with POCKER_NO_SAVE=1")
		get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			output = args[i + 1]
	DirAccess.make_dir_recursive_absolute(output)
	var original_aspect := get_tree().root.content_scale_aspect
	var boot: Node = load("res://game/boot.tscn").instantiate()
	add_child(boot)
	var captured_title := false
	for frame in range(160):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var splash: StartupSplash = null
		for child in boot.get_children():
			if child is StartupSplash:
				splash = child
		var main := boot.get_node_or_null("Main")
		if splash != null and main != null:
			failures.append("Main entered the scene before the splash was removed")
		if frame % 4 == 0 and splash != null:
			var record := {"frame": frame, "alpha": splash._logo.modulate.a,
				"viewport_size": [splash._root.size.x, splash._root.size.y],
				"logo_rect": [splash._logo.position.x, splash._logo.position.y,
					splash._logo.size.x, splash._logo.size.y]}
			var path := "frame_%03d.png" % frame
			get_viewport().get_texture().get_image().save_png(output.path_join(path))
			record["file"] = path
			metadata.append(record)
		if splash == null:
			if main == null or not main.screen is TitleScreen:
				failures.append("The actual boot scene did not continue to TitleScreen")
			if get_tree().root.content_scale_aspect != original_aspect:
				failures.append("The game window aspect was not restored")
			get_viewport().get_texture().get_image().save_png(output.path_join("title.png"))
			captured_title = true
			break
	if not captured_title:
		failures.append("Startup did not finish within the capture window")
	var file := FileAccess.open(output.path_join("frames.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": metadata, "failures": failures}, "\t"))
	file.close()
	boot.queue_free()
	await get_tree().process_frame
	print("Startup splash preview: %d frames, %d failures" % [metadata.size(), failures.size()])
	for failure in failures:
		push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
