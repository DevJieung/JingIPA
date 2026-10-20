extends Harness

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_spatial_indexes()
	_check_routes()
	_check_spawn_entries()
	_check_moving_guardian()
	_check_center_guardians()
	_check_migration()
	_check_layouts()
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

## The road test's grid broad phase and the incremental guardian footprint are pure
## optimisations: both must agree with their exhaustive definitions everywhere.
func _check_spatial_indexes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var mismatches := 0
	var on := 0
	for n in range(4000):
		var point := Balance.ARENA_CENTER + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (ArenaGeometry.RADIUS + 20.0)
		for margin in [-60.0, 0.0, Balance.ARENA_MONSTER_RADIUS, Balance.ARENA_MONSTER_RADIUS + 1.0, Balance.ARENA_MONSTER_RADIUS + 3.0]:
			var fast := ArenaGeometry.on_road(point, margin)
			if fast: on += 1
			if fast != ArenaGeometry.on_road_exhaustive(point, margin): mismatches += 1
	# Points exactly on the kerb and on segment joints, where a broad phase is most likely to slip.
	for road in ArenaGeometry.road_polylines():
		for i in range(0, road.size() - 1, 3):
			var normal := (road[i + 1] - road[i]).normalized().orthogonal()
			for side in [-1.0, 1.0]:
				for offset in [ArenaGeometry.ROAD_WIDTH * 0.5 - 0.01, ArenaGeometry.ROAD_WIDTH * 0.5 + 0.01, ArenaGeometry.ROAD_WIDTH * 0.5 - Balance.ARENA_MONSTER_RADIUS]:
					var point: Vector2 = road[i] + normal * side * offset
					for margin in [0.0, Balance.ARENA_MONSTER_RADIUS]:
						if ArenaGeometry.on_road(point, margin) != ArenaGeometry.on_road_exhaustive(point, margin): mismatches += 1
	check(mismatches == 0 and on > 2000, "도로 판정 격자 색인이 전수 판정과 일치 (불일치 %d·도로 위 %d)" % [mismatches, on])
	var sim := _battle()
	for unit in Roster.UNITS:
		if Arena.heroes.size() >= Balance.ARENA_HERO_LIMIT: break
		if String(unit["id"]) != String(Arena.heroes[0]["unit"]["id"]): Arena.gain_hero(unit, 1)
	sim.refresh_heroes()
	var radius := Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS + 4.0
	var wrong := 0
	var closed := 0
	for round_index in range(60):
		for i in range(Arena.heroes.size()):
			# Roads, kerbs, overlapping footprints, the rim and the plaza edge.
			var at := Balance.ARENA_CENTER + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(Balance.ALTAR_R + Balance.ARENA_HERO_RADIUS, ArenaGeometry.RADIUS - Balance.ARENA_HERO_RADIUS)
			if round_index % 3 == 0: at = ArenaGeometry.route_points(i % ArenaGeometry.route_count())[rng.randi_range(2, 90)] + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
			if round_index % 5 == 0 and i > 0: at = Vector2(Arena.heroes[0]["position"]) + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
			Arena.heroes[i]["position"] = ArenaGeometry.clamp_point(at, Balance.ARENA_HERO_RADIUS)
		sim.refresh_heroes()
		sim._rebuild_navigation()
		for cell in sim._road_cells:
			var p := sim._nav.get_point_position(cell)
			var solid := false
			for hero in sim.heroes:
				if p.distance_squared_to((Vector2(hero["pos"]) / 4.0).round() * 4.0) < radius * radius: solid = true
			if solid: closed += 1
			if sim._nav.is_point_solid(cell) != solid: wrong += 1
	check(wrong == 0 and closed > 1000, "수호자 발자국 증분 갱신이 전체 재계산과 일치 (불일치 %d·막힌 칸 누계 %d)" % [wrong, closed])

func _check_routes() -> void:
	var sim := _battle()
	check(not ArenaGeometry.on_road(sim.heroes[0]["pos"]), "아군의 길 밖 위치 허용")
	var before: Vector2 = sim.heroes[0]["pos"]
	sim.move_selected(Vector2.RIGHT, 0.1)
	check(Vector2(sim.heroes[0]["pos"]).distance_to(before) > 10 and not ArenaGeometry.on_road(sim.heroes[0]["pos"]), "길 밖 자유 이동")
	# A tick refreshes the guardian footprint before it moves the monsters. The walks
	# below call _move_monsters() directly, so do the same here: how far the hero just
	# walked depends on which hero the run rolled, and a stale footprint beside a road
	# sends the monster back and forth between the grid and the real collision radius.
	sim._rebuild_navigation()
	for lane in range(ArenaGeometry.route_count()):
		sim.monsters.clear()
		sim._spawn(Arena.spawns_for(1)[0])
		var mo: Dictionary = sim.monsters[0]
		var route := ArenaGeometry.route_points(lane)
		var road_length := 0.0
		for i in range(1, route.size()): road_length += route[i - 1].distance_to(route[i])
		# Spiral roads (2026-10-12): the two arms wind more than a full turn, the two
		# feeders join them a quarter turn in. Both are far longer than the old bends.
		check(road_length > (2100 if lane < 2 else 1600), "진입로 중심선 길이 %d" % lane)
		var sweep := 0.0
		for i in range(1, route.size() - 1):
			sweep += (route[i - 1] - Balance.ARENA_CENTER).angle_to(route[i] - Balance.ARENA_CENTER)
		check(sweep > (TAU if lane < 2 else TAU * 0.7), "수정 둘레를 나선으로 감아 내려감 %d (%.0f도)" % [lane, rad_to_deg(sweep)])
		var first_leg := route[0].distance_to(route[4])
		check(absf((route[4] - route[0]).normalized().dot((Balance.ARENA_CENTER - route[0]).normalized()) - 1.0) < 0.001 and first_leg > 40, "입구에서는 수정을 향해 곧게 들어옴 %d" % lane)
		mo["pos"] = route[0]
		mo["nav_v"] = -1
		mo["spd"] = 1.0
		var travelled := 0.0
		var road_only := true
		var radial_line := true
		for step_index in range(2400):
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
		check(not radial_line and travelled > direct_distance * 2.5, "직선의 2.5배 이상 긴 나선 도로 이동 %d (거리 %.1f)" % [lane, travelled])
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
		for frame in range(2400):
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
	check(lanes.size() == ArenaGeometry.route_count() and lanes.size() == 4, "실제 무작위 출현으로 네 입구 모두 검사")
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
	# A waypoint far around the first arm: the straight line to it leaves the road.
	saved["sim"]["monsters"][0]["path"] = PackedVector2Array([ArenaGeometry.route_points(0)[70]])
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
	for lane in range(ArenaGeometry.route_count()):
		var route := ArenaGeometry.route_points(lane)
		# Approach, bend and the spiral itself (samples are 12 units apart; feeder
		# lanes are shorter, so the deep samples only exist on the arms).
		for sample in [6, 12, 18, 24, 30, 36, 42, 48, 54, 72, 96, 120, 144]:
			if sample >= route.size() - 8: continue
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
				for frame in range(2400):
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
	# Runs saved before the stage chain (snapshot v1 and v2) are not continued.
	var old := Arena.snapshot()
	old["v"] = 2
	check(ArenaValidation.outdated(old) and not ArenaValidation.valid(old) and not Arena.restore(old), "탄 사슬 이전 저장은 이어 하지 않음")
	check(not ArenaValidation.outdated(Arena.snapshot()) and Arena.snapshot()["v"] == ArenaValidation.SAVE_V and ArenaValidation.valid(Arena.snapshot()), "지금 형식은 정상 저장")
	var broken := Arena.snapshot()
	broken["heroes"][0]["p"] = ArenaGeometry.MAP_RECT.position
	check(not Arena.restore(broken), "원 밖 좌표는 거부")
	# A previously blocked enemy must replan immediately after a road update
	# even when the guardian never moves and the old path was nonempty.
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
	for frame in range(2400):
		Arena.sim._move_monsters(1.0 / 60.0)
		if Vector2(Arena.sim.monsters[0]["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS: break
	check(not Arena.sim.monsters[0]["blocked"] and Vector2(Arena.sim.monsters[0]["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS,
		"이전 저장도 영웅을 움직이지 않고 우회하여 수정 도착")
	var old_road := Arena.snapshot()
	old_road["sim"]["monsters"][0]["pos"] = Balance.ARENA_CENTER + Vector2(230, -10)
	old_road["sim"]["monsters"][0]["path"] = PackedVector2Array([Balance.ARENA_CENTER + Vector2(330, 170), Balance.ARENA_CENTER])
	check(not Arena.restore(old_road), "현재 도로 저장의 길 밖 좌표는 거부")
	old_road["sim"]["road_revision"] = ArenaGeometry.ROAD_REVISION - 1
	check(Arena.restore(old_road), "이전 도로 판의 저장 이어하기 허용")
	check(ArenaGeometry.on_road(Arena.sim.monsters[0]["pos"], Balance.ARENA_MONSTER_RADIUS) and Arena.sim.monsters[0]["path"].is_empty(), "이전 도로 적 위치·캐시 경로를 새 길로 이전")
	for frame in range(60): Arena.sim._move_monsters(1.0 / 60.0)
	check(Arena.gold == old_road["gold"] and Arena.sim.elapsed == old_road["sim"]["elapsed"] and ArenaValidation.valid(Arena.snapshot()), "도로 이전 뒤 이동·골드·시간·저장 보존")

## Every battlefield layout (five shapes, eight turns, mirrored or not): the lanes it
## promises, sane lengths, and a monster and a boss that actually walk every lane to
## the crystal without leaving the road or stalling at a junction.
func _check_layouts() -> void:
	var lanes := {"spiral": 4, "pinwheel": 3, "blades": 4, "coil": 1, "fork": 4}
	var shortest := {"spiral": 1600.0, "pinwheel": 1500.0, "blades": 900.0, "coil": 2700.0, "fork": 800.0}
	var longest := {"spiral": 2500.0, "pinwheel": 1800.0, "blades": 1150.0, "coil": 3300.0, "fork": 2500.0}
	check(not ArenaGeometry.use_layout("nonsense") or ArenaGeometry.layout() == ArenaGeometry.DEFAULT_LAYOUT, "모르는 배치 이름은 기본 배치")
	check(not ArenaGeometry.valid_layout("spiral:8:0") and not ArenaGeometry.valid_layout("spiral:0:2") and ArenaGeometry.valid_layout("fork:7:1"), "배치 이름 검사")
	var per_shape := {}
	for index in range(Roster.THEMES.size()):
		var key := ArenaGeometry.layout_for_theme(index)
		per_shape[key.get_slice(":", 0)] = int(per_shape.get(key.get_slice(":", 0), 0)) + 1
		if not ArenaGeometry.valid_layout(key): check(false, "전장 %d 배치 이름" % index)
	check(per_shape.size() == ArenaGeometry.SHAPE_ORDER.size(), "쉰 전장이 다섯 배치를 모두 사용")
	for shape in per_shape: check(int(per_shape[shape]) == Roster.THEMES.size() / ArenaGeometry.SHAPE_ORDER.size(), "배치 %s 를 쓰는 전장 수 균등" % shape)
	var stalled := 0
	var strayed := 0
	var walked := 0
	var shape_errors := 0
	for shape in ArenaGeometry.SHAPE_ORDER:
		for turn in range(ArenaGeometry.TURN_STEPS):
			for mirror in range(2):
				var key := "%s:%d:%d" % [shape, turn, mirror]
				Arena.start_run(20261013)
				ArenaGeometry.use_layout(key)
				Arena.sim = ArenaSim.new()
				Arena.sim.setup(Arena, 1, 20261013)
				Arena.modal = ""
				Arena.phase = Arena.Phase.BATTLE
				var sim: ArenaSim = Arena.sim
				if ArenaGeometry.route_count() != int(lanes[shape]) or ArenaGeometry.shape() != shape: shape_errors += 1
				var gates: Array[Vector2] = []
				for lane in range(ArenaGeometry.route_count()):
					var length := ArenaGeometry.route_length(lane)
					if length < float(shortest[shape]) or length > float(longest[shape]): shape_errors += 1
					var gate := ArenaGeometry.gate_point(lane)
					if absf(gate.distance_to(Balance.ARENA_CENTER) - ArenaGeometry.RADIUS) > 0.01: shape_errors += 1
					for other in gates:
						if other.distance_to(gate) < ArenaGeometry.ROAD_WIDTH * 2.0: shape_errors += 1
					gates.append(gate)
					for monster in [Arena.wave_spawns(1, 1)[0]["m"], Roster.boss_of_body("flame")]:
						sim.monsters.clear()
						sim._forced_lane = lane
						sim._spawn(monster)
						sim._forced_lane = -1
						var mo: Dictionary = sim.monsters[0]
						mo["hp"] = 1.0e9
						var budget := int(length / (Balance.PATH_SPEED * float(mo["spd"])) * 60.0 * 1.35) + 240
						var arrived := false
						for frame in range(budget):
							sim._move_monsters(1.0 / 60.0)
							if not ArenaGeometry.on_road(mo["pos"]): strayed += 1
							if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 0.5:
								arrived = true
								break
						walked += 1
						if not arrived:
							stalled += 1
							printerr("   정체: %s 길 %d %s r=%.0f" % [key, lane, mo["kind"], Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER)])
	check(shape_errors == 0, "배치마다 입구 수·길이·입구 간격이 약속대로 (어긋남 %d)" % shape_errors)
	check(walked >= 400 and stalled == 0 and strayed == 0,
		"모든 배치·회전·좌우 반전의 모든 길에서 일반 몬스터와 보스가 수정에 도착 (%d회·정체 %d·이탈 %d)" % [walked, stalled, strayed])

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
	# Skills wait for a wave and cost gold (2026-10-19): open wave 1 now, spawns held.
	Arena.sim.begin_wave(1)
	Arena.sim._spawn_t = 1.0e9
	Arena.gold = 1000
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
	# Battle speed: the simulator, hero movement and the drawn dt all follow it.
	screen.set_speed(3.0)
	check(is_equal_approx(Save.speed, 3.0) and is_equal_approx(screen.speed, 3.0), "배속 3배 선택이 설정에 남음")
	var elapsed_before: float = Arena.sim.elapsed
	# One 30 fps frame: the simulator caps a single step at 0.25 s of battle time.
	screen._process(1.0 / 30.0)
	check(absf(Arena.sim.elapsed - elapsed_before - 0.1) < 1.0 / 60.0 + 0.001 and is_equal_approx(screen._draw_dt, 0.1), "3배속은 실제 1/30초에 전투 0.1초 진행")
	screen.set_speed(7.0)
	check(is_equal_approx(screen.speed, 3.0), "배속은 1~3배로 제한")
	screen.set_speed(1.0)
	elapsed_before = Arena.sim.elapsed
	screen._process(1.0 / 30.0)
	check(absf(Arena.sim.elapsed - elapsed_before - 1.0 / 30.0) < 1.0 / 60.0 + 0.001, "1배속 복귀")
	main.queue_free()
	await frames(3)
