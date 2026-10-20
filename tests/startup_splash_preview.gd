extends Node

## Captures the real cold start (game/boot.tscn) frame by frame for tools/startup_splash_review.py:
## the MindMorph logo (StartupSplash), the loading cover (StartupLoading: key art + bar) and
## the title it lifts off. Writes frame PNGs and frames.json ({frames, failures}) into --out.
## Each record: frame, stage ("logo" | "loading" | "title"), the logo's alpha and rect (logo),
## the cover's phase / progress / shown / intro / outro / veil (loading), whether Main exists
## and takes input, and the window aspect.
## Failures: the logo must come first and the cover after it, the cover's progress and bar
## never go back and reach 1.0, Main is not interactive while covered, the title arrives,
## the aspect comes back, and no error is logged.

var output := "res://build/startup-splash/1280x800"
var every := 2
var metadata: Array[Dictionary] = []
var failures: Array[String] = []
var _errors = preload("res://tests/log_errors.gd").new()


func _ready() -> void:
	if OS.get_environment("STELLARDEFENSE_NO_SAVE") != "1":
		push_error("Run startup preview with STELLARDEFENSE_NO_SAVE=1")
		get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			output = args[i + 1]
		elif args[i] == "--every":
			every = maxi(1, int(args[i + 1]))
	DirAccess.make_dir_recursive_absolute(output)
	OS.add_logger(_errors)
	var shooting := DisplayServer.get_name() != "headless"
	var original_aspect := get_tree().root.content_scale_aspect
	var boot: Node = load("res://game/boot.tscn").instantiate()
	add_child(boot)
	var captured_title := false
	var saw_cover := false
	var last_progress := 0.0
	var last_shown := 0.0
	var peak_progress := 0.0
	for frame in range(1200):
		await get_tree().process_frame
		if shooting:
			await RenderingServer.frame_post_draw
		var splash := _find(boot, "StartupSplash")
		var cover := _find(boot, "StartupLoading")
		var main := boot.get_node_or_null("Main")
		var record := {"frame": frame, "aspect": get_tree().root.content_scale_aspect,
			"main": main != null, "interactive": main != null and bool(main.interactive)}
		if splash != null:
			record["stage"] = "logo"
			record["alpha"] = splash.logo_alpha()
			var rect: Rect2 = splash.logo_rect()
			record["logo_rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
			var size: Vector2 = splash.cover_size()
			record["viewport_size"] = [size.x, size.y]
			if saw_cover:
				failures.append("The logo came back after the loading cover")
		elif cover != null:
			saw_cover = true
			record["stage"] = "loading"
			for key in ["phase", "progress", "shown", "intro", "outro", "veil"]:
				record[key] = cover.get(key)
			if float(cover.progress) + 1e-6 < last_progress:
				failures.append("Loading progress went back at frame %d" % frame)
			if float(cover.shown) + 1e-6 < last_shown:
				failures.append("Loading bar went back at frame %d" % frame)
			last_progress = cover.progress
			last_shown = cover.shown
			peak_progress = maxf(peak_progress, cover.progress)
			if main != null and cover.covering() and main.interactive:
				failures.append("Main took input under the loading cover at frame %d" % frame)
		else:
			record["stage"] = "title"
		# Every frame of the hand-over (dip to black, lift) is kept: that is where a blink would hide.
		if shooting and (frame % every == 0 or record["stage"] == "title" or String(record.get("phase", "")) in ["reveal", "lift"]):
			var path := "frame_%03d.png" % frame
			get_viewport().get_texture().get_image().save_png(output.path_join(path))
			record["file"] = path
		metadata.append(record)
		if record["stage"] == "title":
			if not saw_cover:
				failures.append("The loading cover never appeared")
			if main == null or not main.screen is TitleScreen:
				failures.append("The actual boot scene did not continue to TitleScreen")
			elif not main.interactive:
				failures.append("Main does not take input after the cover lifted")
			if get_tree().root.content_scale_aspect != original_aspect:
				failures.append("The game window aspect was not restored")
			if shooting:
				# A few more title frames: the field and the music are up, nothing flickers.
				for extra in range(1, 13):
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
					if extra % 4 == 0:
						var later := "title_%02d.png" % extra
						get_viewport().get_texture().get_image().save_png(output.path_join(later))
				get_viewport().get_texture().get_image().save_png(output.path_join("title.png"))
			captured_title = true
			break
	if not captured_title:
		failures.append("Startup did not finish within the capture window")
	if not is_equal_approx(peak_progress, 1.0):
		failures.append("Loading progress never reached 1.0 (%.3f)" % peak_progress)
	if _errors.count() > 0:
		failures.append("Errors were logged: %s" % "; ".join(_errors.lines.slice(0, 3)))
	OS.remove_logger(_errors)
	var file := FileAccess.open(output.path_join("frames.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": metadata, "failures": failures}, "\t"))
	file.close()
	boot.queue_free()
	await get_tree().process_frame
	print("Startup splash preview: %d frames, %d failures" % [metadata.size(), failures.size()])
	for failure in failures:
		printerr("!! " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _find(boot: Node, cls: String) -> Node:
	for child in boot.get_children():
		var script: Script = child.get_script()
		if script != null and script.get_global_name() == cls:
			return child
	return null
