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
	check(Arena.modal == "stage" and Arena.stage == 1 and Arena.theme_index >= 0, "새 판은 무작위 전장 카드로 시작 (전장 선택 없음)")
	var has_choice := false
	for zone in screen.ui.zones:
		if String(zone["id"]).begins_with("theme:"): has_choice = true
	check(not has_choice and tap(screen, "stage:start"), "전장 카드 확인 버튼")
	screen._rite_age = 9.0
	await paint(screen)
	check(tap(screen, "rite:confirm"), "의식 확정 버튼")
	await paint(screen)
	check(Arena.heroes.size() == 1 and tap(screen, "close"), "첫 캐릭터 지급·전투 진입 버튼")
	await paint(screen)
	var hero_at: Vector2 = Arena.sim.heroes[Arena.selected]["pos"]
	var joy_origin := Vector2(120, 675)
	var joy_at := joy_origin + Vector2.RIGHT * 50
	screen._pointer(0, joy_origin, true)
	check(screen.joystick == Vector2.ZERO and screen.joy_origin == joy_origin, "터치 위치에서 정지 상태로 가변 스틱 생성")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = joy_at
	screen._input(drag)
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
	check(tap(screen, "speed:2") and is_equal_approx(screen.speed, 2.0), "상단 배속 버튼 2배속")
	var before_speed: float = Arena.sim.elapsed
	screen._process(0.1)
	check(Arena.sim.elapsed > before_speed + 0.15, "2배속이 실제 시뮬 시간을 두 배로 돌림")
	check(tap(screen, "speed:1") and is_equal_approx(screen.speed, 1.0), "상단 배속 버튼 1배속 복귀")
	# Stage boss down: the next random battlefield opens with its card, on screen.
	var first_field: String = screen.view_3d.world.theme_id
	var first_layout := ArenaGeometry.layout()
	Arena.sim.elapsed = Balance.ARENA_BOSS_AT - 0.02
	screen._process(0.05)
	for mo in Arena.sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	Arena.sim._cache_positions()
	Arena.sim._reap()
	check(Arena.sim.clear_t > 0.0, "탄 보스 처치 뒤 돌파 연출")
	for i in range(roundi((Balance.ARENA_CLEAR_DELAY + 0.3) * 30)): screen._process(1.0 / 30.0)
	await paint(screen)
	check(Arena.stage == 2 and Arena.modal == "stage" and screen.view_3d.world.theme_id == String(Arena.theme_for(1)["id"]) and screen.view_3d.world.theme_id != first_field,
		"2탄 전장 카드와 새 전장의 3D 월드")
	check(ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index) and (ArenaGeometry.layout() != first_layout or Arena.theme_index >= 0), "새 전장의 길 배치")
	check(tap(screen, "stage:start") and Arena.modal == "", "2탄 전장 카드 확인 뒤 바로 전투")
	await paint(screen)
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
