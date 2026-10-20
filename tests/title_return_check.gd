extends Harness

## F7 (2026-10-19 피드백) 회귀 검사 — 「게임 끝나고 돌아오면 초기화면 배경이 사라져있음」.
##
## 실제 흐름 그대로: main.gd → 타이틀 → 시작 → ArenaScreen → 첫 소환 → 몇 초 전투 →
## 패배 / 승리 / 일시정지 메뉴의 「저장하고 타이틀로」 → 타이틀. 매번 같은 배경이어야 한다.
##   - 배경 뷰와 3D world 가 있고, 지형 자식이 있고, 지도 열쇠(_map_key)가 비어 있지 않다.
##   - 절전(M13): 맨 타이틀에서는 배경이 세 프레임에 한 번만 그려지고(약 10fps), 시트(상점·스테이지
##     선택·스쿼드·도감)나 메뉴가 열리면 완전히 멈추며, 전투 중에도 멈춰 있다(3D 두 벌을 안 그림).
##   - 배경은 Main 이 한 벌만 갖는다 — 돌아올 때마다 3D 세계를 새로 만들지 않는다.
##   - 타이틀의 길 모양은 늘 기본 레이아웃이다(마지막 전장의 길이 남지 않는다).
##   - 로그에 오류(SCRIPT ERROR 등)가 없다.
##   - 화면이 있으면(Xvfb·GPU) 실제 화면을 찍어, 배경 자리가 Look.BG 단색이 아님을 본다.
##
## 실행: godot --headless --path . res://tests/title_return_check.tscn
##       화면 확인: DISPLAY=:1 godot --path . --disable-vsync --resolution 1280x800 \
##                  res://tests/title_return_check.tscn -- --out build/feedback-2026-10-19/LB2a/title_return

var _tap = preload("res://tests/log_errors.gd").new()
var _out := ""
var _first_view: Object = null


func _ready() -> void:
	if not require_no_save():
		return
	OS.add_logger(_tap)
	_out = arg("--out", "")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	Run.running = false
	Arena.running = false
	Save.cur_run.clear()
	var main = load("res://game/main.gd").new()
	add_child(main)
	await frames(4)
	await _check_title(main, "first")
	for ending in ["defeat", "victory", "menu"]:
		await _play_and_return(main, ending)
		await _check_title(main, ending)
	await _check_rebuild(main)
	if is_instance_valid(main.screen):
		main.screen.set_process(false)
	Arena.running = false
	OS.remove_logger(_tap)
	for line in _tap.lines:
		printerr("   로그 오류: " + line)
	finish("타이틀 복귀 배경")


## The live backdrop the title is drawing: Main's persistent one, or (older code) the
## per-screen view kept in the CanvasItem meta.
func _view_of(main: Node) -> Object:
	var view: Object = main.get("backdrop")
	if view == null and is_instance_valid(main.screen) and main.screen.has_meta("stellar_backdrop"):
		view = main.screen.get_meta("stellar_backdrop")
	return view


func _check_title(main: Node, label: String) -> void:
	check(main.screen is TitleScreen, "%s: 타이틀 화면" % label)
	if not main.screen is TitleScreen:
		return
	await _settle(main)
	await paint(main.screen)
	await frames(3)
	var view: Object = _view_of(main)
	check(view != null, "%s: 배경 뷰가 있음" % label)
	if view == null:
		return
	var world: Node = view.get("world")
	var viewport: SubViewport = view.get("viewport")
	check(world != null and is_instance_valid(world), "%s: 배경 3D world 가 있음" % label)
	check(viewport != null and is_instance_valid(viewport) and viewport.is_inside_tree(), "%s: 배경 SubViewport 가 트리에 있음" % label)
	if world == null or not is_instance_valid(world) or viewport == null or not is_instance_valid(viewport):
		return
	var terrain: Node = world.get("terrain")
	check(terrain != null and terrain.get_child_count() > 0, "%s: 배경 지형 자식 > 0" % label)
	check(not String(world.get("_map_key")).is_empty(), "%s: 배경 지도 열쇠가 비어 있지 않음" % label)
	check(view.call("render_state") == "paced" and int(view.get("pace")) == int(main.BACKDROP_PACE), "%s: 맨 타이틀 배경은 %d프레임에 한 번 (%s)" % [label, int(main.BACKDROP_PACE), view.call("render_state")])
	if label == "first":
		await _check_pacing(main, view)
	check(ArenaGeometry.layout() == ArenaGeometry.DEFAULT_LAYOUT, "%s: 타이틀 길 모양은 기본 레이아웃 (%s)" % [label, ArenaGeometry.layout()])
	if _first_view == null:
		_first_view = view
	check(view == _first_view, "%s: 배경 3D 세계를 새로 만들지 않고 다시 씀" % label)
	check(not main.battle_live() and main.frame_cap(false) == main.IDLE_FPS, "%s: 타이틀은 전투 아님 → 30fps 예산" % label)
	check(_tap.lines.is_empty(), "%s: 로그 오류 없음 (%d)" % [label, _tap.lines.size()])
	if DisplayServer.get_name() != "headless":
		await _check_pixels(label)


## A backdrop whose world is lost (it failed to build, or was freed) is built again within
## about a second, drawing the plain fallback meanwhile, and logs no error doing so.
func _check_rebuild(main: Node) -> void:
	var view: Object = main.get("backdrop")
	if view == null or not main.screen is TitleScreen:
		check(false, "rebuild: 영속 배경이 있는 타이틀")
		return
	var lost: Node = view.get("world")
	lost.get_parent().remove_child(lost)
	lost.free()
	var rebuilt := false
	for i in range(150):
		await frames(1)
		if view.call("is_built"):
			rebuilt = true
			break
	check(rebuilt, "rebuild: 잃어버린 배경 world 를 다시 만들어 지형까지 그림")
	check(view.get("world") != lost, "rebuild: 새 world")
	check(_tap.lines.is_empty(), "rebuild: 다시 만드는 동안 로그 오류 없음 (%d)" % _tap.lines.size())


## The title backdrop's battery saver: a frame in BACKDROP_PACE on the bare title, nothing under
## a sheet (here the collection) or the pause menu, and paced again once they close.
func _check_pacing(main: Node, view: Object) -> void:
	var title: TitleScreen = main.screen
	var asked := int(view.get("refreshes"))
	await frames(9)
	var paced := int(view.get("refreshes")) - asked
	check(paced >= 2 and paced <= 4, "맨 타이틀: 9프레임에 3번 안팎만 그림 (%d)" % paced)
	title.collection.opened = true
	await paint(title)
	check(view.call("render_state") == "frozen", "시트가 열리면 배경이 멈춤")
	asked = int(view.get("refreshes"))
	await frames(9)
	check(int(view.get("refreshes")) == asked, "시트 아래에서는 한 프레임도 안 그림 (%d)" % (int(view.get("refreshes")) - asked))
	title.collection.close()
	await paint(title)
	check(view.call("render_state") == "paced", "시트를 닫으면 다시 세 프레임에 한 번")
	main.menu.open()
	await frames(2)
	asked = int(view.get("refreshes"))
	await frames(9)
	check(main.menu.opened and int(view.get("refreshes")) == asked, "메뉴 아래에서는 한 프레임도 안 그림")
	main.menu.close()
	await paint(title)
	asked = int(view.get("refreshes"))
	await frames(6)
	check(int(view.get("refreshes")) > asked, "메뉴를 닫으면 배경이 다시 움직임")


## Let a screen transition finish (Main fades in from black after the swap).
func _settle(main: Node) -> void:
	for i in range(180):
		if float(main.get("_fade_dir")) == 0.0:
			return
		await frames(1)


## A missing backdrop leaves the clear colour (Look.BG) behind the title UI; a live field
## (under the 0.46 camp shade) never produces that exact colour.
func _check_pixels(label: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		check(false, "%s: 화면을 읽지 못함" % label)
		return
	if not _out.is_empty():
		img.save_png(_out.path_join("title_%s.png" % label))
	var bg := Look.BG
	var flat := 0
	var total := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			total += 1
			if c.r8 == bg.r8 and c.g8 == bg.g8 and c.b8 == bg.b8:
				flat += 1
	var share := float(flat) / float(maxi(1, total))
	print("%s: Look.BG 단색 픽셀 %.2f%%" % [label, share * 100.0])
	check(share < 0.02, "%s: 화면 배경이 Look.BG 단색이 아님 (%.1f%%)" % [label, share * 100.0])


func _play_and_return(main: Node, ending: String) -> void:
	check(tap(main.screen, "start"), "%s: 타이틀 시작 버튼" % ending)
	check(await wait_screen(main, "arena_screen", 1200), "%s: 새 수호전 화면" % ending)
	var screen: Node = main.screen
	await paint(screen)
	var view: Object = main.get("backdrop")
	if view != null and view.get("viewport") != null:
		var asked := int(view.get("refreshes"))
		await frames(6)
		check(view.call("render_state") == "frozen" and int(view.get("refreshes")) == asked, "%s: 전투 중 타이틀 배경은 멈춤" % ending)
	await _enter_battle(ending)
	check(Arena.heroes.size() >= 1, "%s: 첫 소환으로 영웅 지급" % ending)
	await _settle(main)
	check(main.battle_live() and main.frame_cap(true) == Save.fps, "%s: 실제 전투 → Save.fps 예산 (%d)" % [ending, Save.fps])
	if ending == "defeat":
		# The menu toggle: stored and applied at once; tests never cap the engine.
		var before: int = Save.fps
		main.set_fps(30 if before == 60 else 60)
		check(Save.fps != before and main.frame_cap(true) == Save.fps, "set_fps: 저장값과 전투 예산이 함께 바뀜")
		main.set_fps(before)
		check(not main.budget_enabled(), "검사(STELLARDEFENSE_NO_SAVE=1)에서는 프레임 상한을 걸지 않음")
	# A few seconds of the real battle: screen frames, then simulated time.
	await frames(60)
	for i in range(120):
		screen._process(1.0 / 30.0)
	await frames(2)
	await _enter_battle(ending)
	check(Arena.sim != null and Arena.sim.elapsed > 2.0, "%s: 몇 초 전투 진행 (%.1fs)" % [ending, Arena.sim.elapsed if Arena.sim != null else 0.0])
	var v3: ArenaView = screen.view_3d
	check(v3.render_state() == "always", "%s: 전투 중 3D 는 매 프레임" % ending)
	var asked := v3.refreshes
	match ending:
		"defeat", "victory":
			Arena.sim.done = true
			Arena.sim.won = ending == "victory"
			Arena.end_run(ending == "victory")
			check(Arena.modal == "result", "%s: 결과 카드" % ending)
			await frames(2)
			# The result freezes the field, after one last up-to-date picture (O8a).
			check(v3.render_state() == "frozen" and v3.refreshes == asked + 1, "%s: 결과 카드 — 한 번 더 그린 뒤 멈춤 (%d)" % [ending, v3.refreshes - asked])
			var synced := v3.syncs
			await frames(6)
			check(v3.syncs == synced and v3.refreshes == asked + 1, "%s: 멈춘 동안 3D 동기화·그리기 없음" % ending)
			check(not main.battle_live(), "%s: 결과 카드는 전투 아님 → 30fps 예산" % ending)
			await frames(30)
			await paint(screen)
			check(tap(screen, "result:home"), "%s: 결과 카드의 타이틀 버튼" % ending)
		"menu":
			await frames(30)
			main.menu.open()
			check(main.menu.opened, "menu: 공통 일시정지 메뉴")
			var synced := v3.syncs
			await frames(6)
			check(v3.render_state() == "frozen" and v3.refreshes == asked + 1 and v3.syncs == synced, "menu: 메뉴 아래 3D 는 한 번 그린 뒤 멈춤")
			check(not main.battle_live(), "menu: 메뉴가 열리면 전투 아님 → 30fps 예산")
			await paint(main.menu)
			check(tap(main.menu, "title"), "menu: 저장하고 타이틀로")
	check(await wait_screen(main, "title_screen", 600), "%s: 타이틀로 복귀" % ending)


## Walk the run's opening modals with the run's own API: the battlefield card, the first
## summon (rite today, a jewel box later) and anything a level may open.
func _enter_battle(ending: String) -> void:
	for i in range(24):
		match String(Arena.modal):
			"":
				break
			"stage":
				Arena.confirm_stage()
			"rite", "box":
				if Arena.phase == Run.Phase.DRAW:
					Arena.confirm_summon()
				else:
					Arena.close_modal()
			"talent":
				if not Arena.talent_offer.is_empty():
					Arena.pick_talent(String(Arena.talent_offer[0]))
				else:
					Arena.close_modal()
			_:
				Arena.close_modal()
		await frames(1)
	check(Arena.modal == "", "%s: 전투 진입 (modal '%s')" % [ending, Arena.modal])


