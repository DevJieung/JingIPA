extends Harness

## F8 (2026-10-19) 첫 실행 검사 — 실제 boot.tscn 을 띄워 MindMorph 로고 → 로딩 덮개(그림 + 바)
## → 타이틀까지 지켜본다.
##   - 로고가 먼저, 로딩 덮개가 그 뒤에 온다. 그동안 창은 전체 화면 비율(EXPAND)이다.
##   - 진행률(progress)과 바(shown)는 뒤로 가지 않고 1.0 에 닿는다.
##   - Main 은 덮개 밑에서 만들어지고(타이틀·3D 배경까지) 덮개가 있는 동안 입력을 받지 않는다:
##     실제 입력 경로(Viewport.push_input)로 누른 타이틀 버튼이 안 눌리고, 뒤로 가기도
##     메뉴를 안 연다. 타이틀 음악은 덮개가 걷힐 때까지 기다린다.
##   - 덮개가 걷히면 창 비율이 돌아오고, 같은 입력이 이번에는 타이틀에 닿는다.
##   - 헤드리스에서는 FRAME_LIMIT 프레임 안에 타이틀이 열린다(verify.sh 3단계는 200프레임 부팅).
##   - 로그에 오류가 없다.
##
## 실행: godot --headless --path . res://tests/startup_loading_check.tscn

const FRAME_LIMIT_HEADLESS := 150
const FRAME_LIMIT_DISPLAY := 900

var _errors = preload("res://tests/log_errors.gd").new()


func _ready() -> void:
	if not require_no_save():
		return
	OS.add_logger(_errors)
	Run.running = false
	Arena.running = false
	var root := get_tree().root
	var original := root.content_scale_aspect
	var quit_on_back := get_tree().quit_on_go_back
	var back_blocked := true
	var boot: Node = load("res://game/boot.tscn").instantiate()
	add_child(boot)
	var limit := FRAME_LIMIT_HEADLESS if DisplayServer.get_name() == "headless" else FRAME_LIMIT_DISPLAY
	var saw_logo := false
	var saw_cover := false
	var order_ok := true
	var expand_ok := true
	var progress_ok := true
	var shown_ok := true
	var last_progress := 0.0
	var last_shown := 0.0
	var peak_progress := 0.0
	var peak_shown := 0.0
	var built_under_cover := false
	var never_interactive := true
	var main_before_cover := true
	var probed := false
	var title_frame := -1
	var logo_frames := 0
	var cover_frames := 0
	var phases: Array[String] = []
	var main: Node = null
	for frame in range(limit):
		await get_tree().process_frame
		var splash := _find(boot, "StartupSplash")
		var cover := _find(boot, "StartupLoading")
		main = boot.get_node_or_null("Main")
		if splash != null:
			saw_logo = true
			logo_frames += 1
			if saw_cover:
				order_ok = false
		if (splash != null or (cover != null and cover.phase not in ["lift", "done"])) \
				and root.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
			expand_ok = false
		if cover != null:
			saw_cover = true
			cover_frames += 1
			if phases.is_empty() or phases[-1] != String(cover.phase):
				phases.append(String(cover.phase))
			var p: float = cover.progress
			var s: float = cover.shown
			if p + 1e-6 < last_progress:
				progress_ok = false
			if s + 1e-6 < last_shown:
				shown_ok = false
			last_progress = p
			last_shown = s
			peak_progress = maxf(peak_progress, p)
			peak_shown = maxf(peak_shown, s)
			if main != null and cover.covering():
				if main.interactive:
					never_interactive = false
				if main.get_index() > cover.get_index():
					main_before_cover = false
				if main.screen is TitleScreen and main.backdrop != null and main.backdrop.is_built():
					built_under_cover = true
				if not probed and main.screen is TitleScreen and not zone_of(main.screen, "collection").is_empty():
					probed = true
					_probe_blocked(main)
		if (splash != null or cover != null) and get_tree().quit_on_go_back:
			back_blocked = false
		if splash == null and cover == null and main != null:
			title_frame = frame
			break
	print("로고 %d프레임 · 로딩 %d프레임 (%s) · 타이틀 %d프레임째" % [logo_frames, cover_frames, " → ".join(phases), title_frame])
	check(saw_logo, "MindMorph 로고 단계가 있음")
	check(saw_cover, "로딩 덮개 단계가 있음")
	check(order_ok, "로고 → 로딩 순서")
	check(expand_ok, "로고·로딩 동안 창은 전체 화면 비율(EXPAND)")
	check(progress_ok, "진행률이 뒤로 가지 않음")
	check(shown_ok, "바가 뒤로 가지 않음")
	check(is_equal_approx(peak_progress, 1.0), "진행률이 1.0 에 닿음 (%.3f)" % peak_progress)
	check(is_equal_approx(peak_shown, 1.0), "바가 1.0 에 닿음 (%.3f)" % peak_shown)
	check(main_before_cover, "Main 이 덮개보다 앞(입력은 덮개가 먼저 받음)")
	check(built_under_cover, "덮개 밑에서 타이틀과 3D 배경을 만듦")
	check(never_interactive, "덮개가 있는 동안 Main 은 입력을 받지 않음")
	check(probed, "덮개가 있는 동안 입력 차단을 시험함")
	check(back_blocked, "로고·로딩 동안 뒤로 가기로 앱이 꺼지지 않음 (quit_on_go_back 꺼짐)")
	check(get_tree().quit_on_go_back == quit_on_back, "덮개가 걷힌 뒤 quit_on_go_back 원래대로")
	check(title_frame >= 0, "타이틀까지 도착 (%d프레임)" % title_frame)
	if main != null and title_frame >= 0:
		check(main.screen is TitleScreen, "덮개가 걷힌 뒤 타이틀 화면")
		check(main.interactive, "덮개가 걷힌 뒤 Main 이 입력을 받음")
		check(root.content_scale_aspect == original, "창 비율 복구")
		check(String(main.get("_waiting_music")).is_empty(), "타이틀 음악이 덮개가 걷힐 때 시작")
		if Sfx.get("_on"):
			check(Sfx._music_id == "camp", "타이틀 음악 camp")
		await _probe_open(main)
	check(_errors.count() == 0, "로그 오류 없음 (%d)" % _errors.count())
	for line in _errors.lines:
		printerr("   로그 오류: " + line)
	OS.remove_logger(_errors)
	if main != null and is_instance_valid(main.screen):
		main.screen.set_process(false)
	boot.queue_free()
	await frames(2)
	finish("첫 실행 로고·로딩")


func _find(boot: Node, cls: String) -> Node:
	for child in boot.get_children():
		var script: Script = child.get_script()
		if script != null and script.get_global_name() == cls:
			return child
	return null


## A real click through the viewport (the path the player's finger takes) at the title's
## collection record, and the Android back button: both must die at the cover.
func _probe_blocked(main: Node) -> void:
	_click(Rect2(zone_of(main.screen, "collection")["rect"]).get_center())
	check(not main.screen.collection.opened, "덮개 밑 타이틀 버튼이 눌리지 않음")
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not main.menu.opened, "덮개가 있는 동안 뒤로 가기 무시")
	check(String(main.get("_waiting_music")) == "camp", "덮개가 있는 동안 타이틀 음악 대기")
	if Sfx.get("_on"):
		check(Sfx._music_id != "camp", "덮개 밑에서는 타이틀 음악이 아직 안 나옴")


## The same paths once the cover is gone: the back button opens the menu, the click opens
## the collection.
func _probe_open(main: Node) -> void:
	await paint(main.screen)
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(main.menu.opened, "덮개가 걷힌 뒤 뒤로 가기로 메뉴")
	main.menu.close()
	await paint(main.screen)
	var zone := zone_of(main.screen, "collection")
	check(not zone.is_empty(), "타이틀 도감 버튼 자리")
	if not zone.is_empty():
		_click(Rect2(zone["rect"]).get_center())
		check(main.screen.collection.opened, "덮개가 걷힌 뒤 같은 입력이 타이틀에 닿음")


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = pressed
		get_viewport().push_input(e, true)
