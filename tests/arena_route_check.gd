extends Harness

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_routes()
	_check_spawn_entries()
	_check_moving_guardian()
	_check_center_guardians()
	_check_migration()
	await _check_floating_input()
	Arena.running = false
	finish("원형 전장·도로 이동·가변 조이스틱")

func _battle() -> ArenaSim:
	Arena.start_run(20261010)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.heroes[0]["position"] = Balance.ARENA_CENTER + Vector2(230, -10)
	Arena.sim.refresh_heroes()
	Arena.sim._rebuild_navigation()
	return Arena.sim

func _check_routes() -> void:
	var sim := _battle()
	check(not ArenaGeometry.on_road(sim.heroes[0]["pos"]), "아군의 길 밖 위치 허용")
	var before: Vector2 = sim.heroes[0]["pos"]
	sim.move_selected(Vector2.RIGHT, 0.1)
	check(Vector2(sim.heroes[0]["pos"]).distance_to(before) > 10 and not ArenaGeometry.on_road(sim.heroes[0]["pos"]), "길 밖 자유 이동")
	for lane in range(ArenaGeometry.ROUTE_COUNT):
		sim.monsters.clear()
		sim._spawn(Arena.spawns_for(1)[0])
		var mo: Dictionary = sim.monsters[0]
		var route := ArenaGeometry.route_points(lane)
		var road_length := 0.0
		for i in range(1, route.size()): road_length += route[i - 1].distance_to(route[i])
		check(road_length > 1100, "진입로 중심선 길이 1100 이상 %d" % lane)
		mo["pos"] = route[0]
		mo["nav_v"] = -1
		mo["spd"] = 1.0
		var travelled := 0.0
		var road_only := true
		var radial_line := true
		for step_index in range(1500):
			var at: Vector2 = mo["pos"]
			sim._move_monsters(1.0 / 60.0)
			var p: Vector2 = mo["pos"]
			travelled += p.distance_to(at)
			road_only = road_only and ArenaGeometry.on_road(p, Balance.ARENA_MONSTER_RADIUS)
			var closest := Geometry2D.get_closest_point_to_segment(p, route[0], Balance.ARENA_CENTER)
			radial_line = radial_line and p.distance_to(closest) < 30
			if p.distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS: break
		check(road_only, "모든 프레임에서 길 안에 머무름 %d" % lane)
		var direct_distance := route[0].distance_to(Balance.ARENA_CENTER) - Balance.ALTAR_R - Balance.ARENA_MONSTER_RADIUS
		check(not radial_line and travelled > direct_distance * 2.0, "직선의 두 배 이상 긴 굽은 도로 이동 %d (거리 %.1f)" % [lane, travelled])
		print("입구 %d 실제 이동 거리 %.1f / 도로 중심선 %.1f" % [lane, travelled, road_length])
		check(Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 1, "네 입구 모두 수정 도착 %d" % lane)
	# A single central guardian leaves room to pass throughout the road.
	sim.monsters.clear()
	var block_point := ArenaGeometry.route_points(0)[12]
	Arena.heroes[0]["position"] = block_point
	sim.refresh_heroes()
	sim._rebuild_navigation()
	sim._spawn(Arena.spawns_for(1)[0])
	var blocked: Dictionary = sim.monsters[0]
	blocked["pos"] = ArenaGeometry.route_points(0)[0]
	blocked["spd"] = 1.0
	var start: Vector2 = blocked["pos"]
	for i in range(90): sim._move_monsters(1.0 / 60.0)
	check(not blocked["blocked"] and Vector2(blocked["pos"]).distance_to(start) > 50, "중앙 영웅이 있어도 입구에서 계속 접근")
	for i in range(360): sim._move_monsters(1.0 / 60.0)
	check(not blocked["blocked"] and Vector2(blocked["pos"]).distance_to(block_point) > 80, "중앙 영웅을 지나 계속 전진")
	var waiting: Vector2 = blocked["pos"]
	Arena.heroes[0]["position"] = Balance.ARENA_CENTER + Vector2(230, -10)
	sim.refresh_heroes()
	sim._rebuild_navigation()
	for i in range(90): sim._move_monsters(1.0 / 60.0)
	check(Vector2(blocked["pos"]).distance_to(waiting) > 30 and ArenaGeometry.on_road(blocked["pos"], Balance.ARENA_MONSTER_RADIUS), "영웅 위치 변경 뒤에도 같은 도로 이동 유지")
	blocked["pos"] = ArenaGeometry.route_points(0)[20]
	blocked["nav_v"] = -1
	sim._push(0)
	for i in range(30):
		sim._move_monsters(1.0 / 60.0)
		check(ArenaGeometry.on_road(blocked["pos"], Balance.ARENA_MONSTER_RADIUS), "굽은 길의 밀쳐내기도 길 밖 이탈 없음")
	check(ArenaValidation.valid(Arena.snapshot()), "도로 이동 중 저장 정상")
	var saved := Arena.snapshot()
	Arena.restore(saved)
	for i in range(60): Arena.sim.step(1.0 / 60.0)
	var first := Arena.snapshot()
	Arena.restore(saved)
	for i in range(60): Arena.sim.step(1.0 / 60.0)
	check(Arena.snapshot() == first, "도로 경로·이동 결정론적 이어하기")

func _check_spawn_entries() -> void:
	var sim := _battle()
	var lanes := {}
	var waiting := 0
	var left_road := 0
	var arrived := 0
	# Keep the real random spawn positions: centre-only fixtures missed the
	# shortcut that grazed the first bend for negative entrance offsets.
	for sample in range(160):
		sim.monsters.clear()
		sim._spawn(Arena.spawns_for(1)[0])
		var mo: Dictionary = sim.monsters[0]
		lanes[mo["route"]] = true
		mo["spd"] = 1.0
		for frame in range(1500):
			sim._move_monsters(1.0 / 60.0)
			if mo["blocked"]:
				waiting += 1
				break
			if not ArenaGeometry.on_road(mo["pos"], Balance.ARENA_MONSTER_RADIUS):
				left_road += 1
				break
			if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS:
				arrived += 1
				break
	check(lanes.size() == ArenaGeometry.ROUTE_COUNT, "실제 무작위 출현으로 네 입구 모두 검사")
	check(waiting == 0 and left_road == 0 and arrived == 160,
		"출현 편차가 있는 160마리 모두 도로 안에서 정체 없이 수정 도착 (정체 %d·이탈 %d·도착 %d)" % [waiting, left_road, arrived])
	# Saved by the previous build after the right entrance shortcut hit the
	# road edge. Neither a hero move nor a road-layout migration should be needed.
	sim = _battle()
	sim._spawn(Arena.spawns_for(1)[0])
	var mo: Dictionary = sim.monsters[0]
	mo["pos"] = Balance.ARENA_CENTER + Vector2(442.1726, 34.446)
	mo["blocked"] = true
	mo["nav_v"] = sim._nav_version
	mo["path"] = PackedVector2Array()
	var saved := Arena.snapshot()
	check(Arena.restore(saved), "입구에서 멈춘 이전 저장 불러오기")
	sim = Arena.sim
	var before: Vector2 = sim.monsters[0]["pos"]
	var safe := true
	for frame in range(120):
		sim._move_monsters(1.0 / 60.0)
		safe = safe and ArenaGeometry.on_road(sim.monsters[0]["pos"], Balance.ARENA_MONSTER_RADIUS)
	check(safe and not sim.monsters[0]["blocked"] and before.distance_to(sim.monsters[0]["pos"]) > 60,
		"영웅 이동 없이도 이어하기 직후 입구 정체 해소")
	check(ArenaValidation.valid(Arena.snapshot()), "입구 정체 복구 뒤 저장 유효")
	# Also recover a still-cached shortcut before it becomes an empty path.
	saved["sim"]["monsters"][0]["path"] = PackedVector2Array([Balance.ARENA_CENTER + Vector2(350, 130)])
	check(Arena.restore(saved), "이전 빌드의 가장자리를 스치는 경로 불러오기")
	sim = Arena.sim
	before = sim.monsters[0]["pos"]
	for frame in range(120): sim._move_monsters(1.0 / 60.0)
	check(not sim.monsters[0]["blocked"] and before.distance_to(sim.monsters[0]["pos"]) > 60,
		"내비게이션 변경 없이도 막힌 기존 경로를 다시 탐색")

func _check_moving_guardian() -> void:
	var reference: Array[Vector2] = []
	for moving in [false, true]:
		var sim := _battle()
		sim._spawn(Arena.spawns_for(1)[0])
		var mo: Dictionary = sim.monsters[0]
		mo["pos"] = ArenaGeometry.route_points(0)[0]
		mo["spd"] = 1.0
		var same_progress := true
		var keeps_moving := true
		for frame in range(600):
			if moving:
				sim.move_selected(Vector2.RIGHT if (frame / 8) % 2 == 0 else Vector2.LEFT, 1.0 / 60.0)
				sim._rebuild_navigation()
			sim._move_monsters(1.0 / 60.0)
			if moving:
				same_progress = same_progress and Vector2(mo["pos"]).distance_to(reference[frame]) < 0.01
				keeps_moving = keeps_moving and not bool(mo["blocked"])
			else:
				reference.append(mo["pos"])
		if moving:
			check(same_progress and keeps_moving, "영웅을 10초 연속 이동해도 적은 정지·뒷걸음 없이 같은 속도로 전진")

func _check_center_guardians() -> void:
	var sim := _battle()
	# All four rotations, straight sections, inner/outer bends, and positions
	# between grid centres must leave a usable passage beside a single hero.
	for lane in range(ArenaGeometry.ROUTE_COUNT):
		var route := ArenaGeometry.route_points(lane)
		for sample in [6, 12, 18, 24, 30, 36, 42, 48, 54]:
			for offset in [Vector2.ZERO, Vector2(3, 3)]:
				var guardian: Vector2 = route[sample] + offset
				Arena.heroes[0]["position"] = guardian
				sim.refresh_heroes()
				sim._rebuild_navigation()
				sim.monsters.clear()
				sim._spawn(Arena.spawns_for(1)[0])
				var mo: Dictionary = sim.monsters[0]
				mo["pos"] = route[0]
				mo["spd"] = 1.0
				var safe := true
				var road_only := true
				var keeps_moving := true
				for frame in range(1500):
					sim._move_monsters(1.0 / 60.0)
					var at: Vector2 = mo["pos"]
					safe = safe and at.distance_to(guardian) >= Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS - 0.01
					road_only = road_only and ArenaGeometry.on_road(at, Balance.ARENA_MONSTER_RADIUS)
					keeps_moving = keeps_moving and not bool(mo["blocked"])
					if at.distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS: break
				var label := "입구%d·굽이%d·편차%s" % [lane, sample, offset]
				check(safe and road_only, "중앙 영웅 우회 중 관통·길 이탈 없음 " + label)
				check(keeps_moving and Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS,
					"중앙 영웅 한 명으로 길이 막히지 않고 수정 도착 " + label)

func _check_migration() -> void:
	var sim := _battle()
	sim._spawn(Arena.spawns_for(1)[0])
	var saved := Arena.snapshot()
	saved["v"] = 1
	saved["heroes"][0]["p"] = ArenaGeometry.LEGACY_RECT.position + Vector2(30, 30)
	saved["sim"]["monsters"][0]["pos"] = ArenaGeometry.LEGACY_RECT.end - Vector2(20, 20)
	saved["sim"]["monsters"][0]["path"] = PackedVector2Array([saved["sim"]["monsters"][0]["pos"], Balance.ARENA_CENTER])
	check(Arena.restore(saved), "구 직사각형 저장을 거부하지 않고 이전")
	check(ArenaGeometry.contains(Arena.heroes[0]["position"], Balance.ARENA_HERO_RADIUS), "구 모서리 영웅을 원 안으로 이전")
	check(ArenaGeometry.on_road(Arena.sim.monsters[0]["pos"], Balance.ARENA_MONSTER_RADIUS), "구 길 밖 적을 가까운 새 도로로 이전")
	check(Arena.sim.monsters[0]["path"].is_empty() and Arena.sim.monsters[0]["nav_v"] == -1, "구 직선 경로 폐기·새 도로 재탐색")
	check(Arena.gold == saved["gold"] and Arena.sim.crystal_hp == saved["sim"]["crystal_hp"] and Arena.sim.elapsed == saved["sim"]["elapsed"], "이전 중 골드·체력·시간 보존")
	check(Arena.snapshot()["v"] == 2 and ArenaValidation.valid(Arena.snapshot()), "이전 후 새 형식으로 정상 저장")
	var broken := Arena.snapshot()
	broken["heroes"][0]["p"] = ArenaGeometry.MAP_RECT.position
	check(not Arena.restore(broken), "새 형식의 원 밖 좌표는 거부")
	# A previously blocked enemy must replan immediately after the wider-road
	# update even when the guardian never moves and the old path was nonempty.
	var narrow_road := Arena.snapshot()
	var route := ArenaGeometry.route_points(0)
	narrow_road["heroes"][0]["p"] = route[18]
	narrow_road["sim"]["road_revision"] = 2
	narrow_road["sim"]["monsters"][0]["pos"] = route[12]
	narrow_road["sim"]["monsters"][0]["path"] = PackedVector2Array([route[18]])
	narrow_road["sim"]["monsters"][0]["blocked"] = true
	narrow_road["sim"]["monsters"][0]["spd"] = 1.0
	check(Arena.restore(narrow_road), "좁은 도로에서 영웅에게 막힌 기존 저장 불러오기")
	check(Arena.sim.monsters[0]["path"].is_empty() and Arena.sim.monsters[0]["nav_v"] == -1, "이전 충돌 반경·격자 경로를 폐기하고 재탐색")
	for frame in range(1500):
		Arena.sim._move_monsters(1.0 / 60.0)
		if Vector2(Arena.sim.monsters[0]["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS: break
	check(not Arena.sim.monsters[0]["blocked"] and Vector2(Arena.sim.monsters[0]["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS,
		"이전 저장도 영웅을 움직이지 않고 우회하여 수정 도착")
	var old_road := Arena.snapshot()
	old_road["sim"]["monsters"][0]["pos"] = Balance.ARENA_CENTER + Vector2(230, -10)
	old_road["sim"]["monsters"][0]["path"] = PackedVector2Array([Balance.ARENA_CENTER + Vector2(330, 170), Balance.ARENA_CENTER])
	check(not Arena.restore(old_road), "현재 도로 저장의 길 밖 좌표는 거부")
	old_road["sim"].erase("road_revision")
	check(Arena.restore(old_road), "이전 짧은 도로 저장 이어하기 허용")
	check(ArenaGeometry.on_road(Arena.sim.monsters[0]["pos"], Balance.ARENA_MONSTER_RADIUS) and Arena.sim.monsters[0]["path"].is_empty(), "이전 도로 적 위치·캐시 경로를 새 길로 이전")
	for frame in range(60): Arena.sim._move_monsters(1.0 / 60.0)
	check(Arena.gold == old_road["gold"] and Arena.sim.elapsed == old_road["sim"]["elapsed"] and ArenaValidation.valid(Arena.snapshot()), "도로 이전 뒤 이동·골드·시간·저장 보존")

func _drag(screen: ArenaScreen, pointer: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = pointer
	event.position = at
	screen._input(event)

func _check_floating_input() -> void:
	_battle()
	var main = load("res://game/main.gd").new()
	add_child(main)
	await frames(3)
	main.show_arena()
	var screen: ArenaScreen = main.screen
	screen.set_process(false)
	await paint(screen)
	for origin in [Vector2(220, 250), Vector2(980, 460), Vector2(120, 685)]:
		var p: Vector2 = Arena.sim.heroes[Arena.selected]["pos"]
		screen._pointer(2, origin, true)
		check(screen.joy_origin == origin and screen._joy_pointer == 2 and screen.joystick == Vector2.ZERO, "누른 위치를 기준으로 스틱 생성")
		screen._process(0.1)
		check(Arena.sim.heroes[Arena.selected]["pos"] == p, "드래그 전에는 이동 없음")
		_drag(screen, 2, origin + Vector2(55, 0))
		screen._process(0.1)
		check(Vector2(Arena.sim.heroes[Arena.selected]["pos"]).distance_to(p) > 1, "어느 시작점에서도 드래그 이동")
		screen._pointer(3, Vector2(850, 450), true)
		_drag(screen, 3, Vector2(900, 500))
		screen._pointer(3, Vector2(900, 500), false)
		check(screen._joy_pointer == 2 and screen.joy_origin == origin and screen.joystick.x > 0.5, "두 번째 손가락이 원점·소유권을 빼앗지 않음")
		screen._pointer(2, origin, false)
		check(screen._joy_pointer == -99 and screen.joystick == Vector2.ZERO, "손을 떼면 스틱 숨김·정지")
	# Skills remain usable with a second finger while the first one is moving.
	screen._pointer(4, Vector2(200, 350), true)
	_drag(screen, 4, Vector2(235, 350))
	Arena.sim.skill_cooldowns["ward"] = 0.0
	await paint(screen)
	var skill := zone_of(screen, "skill:ward")
	screen._pointer(5, Rect2(skill["rect"]).get_center(), true)
	screen._pointer(5, Rect2(skill["rect"]).get_center(), false)
	check(Arena.sim.shield > 0 and screen._joy_pointer == 4 and screen.joystick.x > 0, "이동 중 두 번째 손가락 스킬 사용")
	var canceled := InputEventScreenTouch.new()
	canceled.index = 5
	canceled.position = Vector2(235, 350)
	canceled.pressed = true
	canceled.canceled = true
	screen._input(canceled)
	check(screen._joy_pointer == 4 and screen.joystick.x > 0, "다른 손가락의 터치 취소는 이동에 영향 없음")
	canceled.index = 4
	screen._input(canceled)
	check(screen._joy_pointer == -99 and screen.joystick == Vector2.ZERO, "이동 손가락의 터치 취소는 즉시 정지")
	for point in [Vector2(1190, 25), ArenaScreen.MINIMAP.get_center(), Rect2(skill["rect"]).get_center(), Vector2(997, 430), Vector2(1136, 224)]:
		screen._pointer(5, point, true)
		check(screen._joy_pointer == -99, "HUD·미니맵·쿨다운 버튼은 스틱 시작 제외")
	screen._pointer(4, Vector2(200, 350), true)
	_drag(screen, 4, Vector2(250, 350))
	main.menu.open()
	await frames(2)
	check(screen._joy_pointer == -99 and screen.joystick == Vector2.ZERO, "메뉴가 화면 처리를 멈춰도 스틱 즉시 초기화")
	main.menu.close()
	screen._pointer(4, Vector2(200, 350), true)
	_drag(screen, 4, Vector2(250, 350))
	screen.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(screen._joy_pointer == -99 and screen.joystick == Vector2.ZERO, "앱 전환·포커스 상실 뒤 이동 잔류 없음")
	main.queue_free()
	await frames(3)
