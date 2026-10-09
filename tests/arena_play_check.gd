extends Harness

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	Arena.running = false
	Save.cur_run.clear()
	var main = load("res://game/main.gd").new()
	add_child(main)
	await paint(main.screen)
	check(tap(main.screen, "start"), "실제 타이틀 시작 버튼")
	check(await wait_screen(main, "arena_screen", 1200), "타이틀에서 새 수호전 화면")
	var screen: ArenaScreen = main.screen
	screen.set_process(false)
	await paint(screen)
	check(Arena.modal == "theme" and tap(screen, "theme:0") and tap(screen, "theme:start"), "테마 선택 버튼")
	screen._rite_age = 9.0
	await paint(screen)
	var first_rite: Dictionary = Arena.snapshot()["rite"].duplicate(true)
	check(tap(screen, "rite:pull") and Arena.snapshot()["rite"] == first_rite,
			"비 Android 광고 버튼은 별을 지급하지 않고 안내")
	check(tap(screen, "rite:confirm"), "의식 확정 버튼")
	await paint(screen)
	check(Arena.heroes.size() == 1 and tap(screen, "close"), "첫 캐릭터 지급·전투 진입 버튼")
	await paint(screen)
	var hero_at: Vector2 = Arena.sim.heroes[Arena.selected]["pos"]
	var joy_at := ArenaScreen.JOY_CENTER + Vector2.RIGHT * 50
	screen._pointer(0, joy_at, true)
	screen._process(0.1)
	check(Vector2(Arena.sim.heroes[Arena.selected]["pos"]).distance_to(hero_at) > 1,
			"실제 가상 조이스틱 입력으로 3D 영웅 이동")
	screen._pointer(1, Vector2.ZERO, false)
	check(screen.joystick.length() > 0 and screen._joy_pointer == 0,
			"두 번째 손가락을 떼어도 이동 입력 유지")
	screen._pointer(0, joy_at, false)
	check(screen.joystick == Vector2.ZERO and screen._joy_pointer == -99,
			"이동 손가락을 떼면 조이스틱 정지")
	Arena.gold = 1000
	check(tap(screen, "shop"), "상점 진입 버튼")
	await paint(screen)
	check(tap(screen, "upgrade:atk") and Arena.lv("atk") == 1, "상점 강화 구매 버튼")
	check(tap(screen, "close"), "상점 닫기 버튼")
	await paint(screen)
	check(tap(screen, "skill:ward") and Arena.sim.shield > 0, "공통 스킬 버튼")
	check(tap(screen, "bench"), "대기 편성 버튼")
	await paint(screen)
	check(tap(screen, "close"), "대기 편성 닫기 버튼")
	await paint(screen)
	var old_gold: int = Arena.gold
	check(tap(screen, "summon") and Arena.gold == old_gold - Arena.summon_cost(), "유료 소환 버튼")
	screen._rite_age = 9.0
	await paint(screen)
	check(tap(screen, "rite:confirm"), "추가 의식 확정 버튼")
	await paint(screen)
	check(tap(screen, "close"), "추가 소환 결과 확인 버튼")
	await paint(screen)
	# Let the transition finish before opening the common pause menu.
	await frames(90)
	main.menu.open()
	check(main.menu.opened, "공통 일시정지 메뉴")
	var elapsed_time: float = Arena.sim.elapsed
	screen._process(0.1)
	check(Arena.sim.elapsed == elapsed_time, "공통 메뉴도 전투 시간 정지")
	main.menu.close()
	Arena.autosave()
	var saved := Save.cur_run.duplicate(true)
	Arena.running = false
	main.show_title()
	await paint(main.screen)
	check(tap(main.screen, "resume"), "타이틀 새 모드 이어하기 버튼")
	check(await wait_screen(main, "arena_screen", 1200), "새 모드 이어하기 화면")
	check(Arena.modal == saved["modal"] and Arena.sim.elapsed >= elapsed_time and Arena.sim.elapsed < elapsed_time + 0.1, "이어하기 전투 상태 복구")
	main.screen.set_process(false)
	Arena.running = false
	finish("연속 수호전 실제 UI 흐름")
