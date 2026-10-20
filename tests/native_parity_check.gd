extends Harness

## The C++ kernels of addons/stellar_native answer exactly like the GDScript they stand
## in for (docs/PERF_NATIVE.md): the road tests of ArenaGeometry, the simulator's
## navigation (segment tests, paths, the road mask) and the monster pose sampler. Each
## GDScript path stays in the game as the reference and the fallback, so this check runs
## both on the same inputs and expects the same bits.
##
##   godot --headless --path . res://tests/native_parity_check.tscn
##
## The library must be present: tools/native/build.sh builds it (CI does before the checks).

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	check(ClassDB.class_exists("StellarRoads") and Native.enabled(), "stellar_native 라이브러리가 실려 있음 (tools/native/build.sh)")
	if not Native.enabled():
		finish("네이티브 커널 일치")
		return
	_check_roads()
	_check_navigation()
	_check_battle()
	await _check_poses()
	Arena.running = false
	finish("네이티브 커널 일치")

const LAYOUTS := ["spiral:0:0", "pinwheel:3:1", "blades:5:0", "coil:1:1", "fork:6:0"]

func _check_roads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261017
	for layout in LAYOUTS:
		ArenaGeometry.use_layout(layout)
		var native = ArenaGeometry.native()
		check(native != null, layout + ": 네이티브 도로 객체")
		var mismatches := 0
		var on := 0
		var nearest := 0
		var direction := 0
		var segments := 0
		var points: Array[Vector2] = []
		for n in range(3000):
			points.append(Balance.ARENA_CENTER + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (ArenaGeometry.RADIUS + 30.0))
		# The kerb and the joints, where a broad phase or a rounding slips first.
		for road in ArenaGeometry.road_polylines():
			for i in range(0, road.size() - 1, 2):
				var normal := (road[i + 1] - road[i]).normalized().orthogonal()
				for side in [-1.0, 1.0]:
					for offset in [ArenaGeometry.ROAD_WIDTH * 0.5 - 0.01, ArenaGeometry.ROAD_WIDTH * 0.5, ArenaGeometry.ROAD_WIDTH * 0.5 + 0.01, ArenaGeometry.ROAD_WIDTH * 0.5 - Balance.ARENA_MONSTER_RADIUS]:
						points.append(road[i] + normal * side * offset)
		for point in points:
			for margin in [-60.0, 0.0, Balance.ARENA_MONSTER_RADIUS, Balance.ARENA_MONSTER_RADIUS + 1.0, Balance.ARENA_MONSTER_RADIUS + 3.0, 14.0, 17.0, 20.0]:
				var fast: bool = native.on_road(point, margin)
				if fast: on += 1
				if fast != ArenaGeometry.on_road_script(point, margin) or fast != ArenaGeometry.on_road_exhaustive(point, margin): mismatches += 1
			if native.contains(point, 10.0) != ArenaGeometry.contains(point, 10.0) or native.clamp_point(point, 18.0) != ArenaGeometry.clamp_point(point, 18.0): mismatches += 1
			if native.nearest_road_point(point) != ArenaGeometry.nearest_road_point_script(point): nearest += 1
			if native.road_direction(point) != ArenaGeometry.road_direction_script(point): direction += 1
		for n in range(points.size() - 1):
			var a: Vector2 = points[n]
			var b: Vector2 = points[n + 1]
			var to := a.lerp(b, rng.randf() * 0.2)
			for margin in [Balance.ARENA_MONSTER_RADIUS, Balance.ARENA_MONSTER_RADIUS + 3.0]:
				var expected := true
				var samples := maxi(1, ceili(a.distance_to(to) / 6.0))
				for i in range(samples + 1):
					if not ArenaGeometry.on_road_script(a.lerp(to, float(i) / samples), margin):
						expected = false
						break
				if native.segment_on_road(a, to, margin, 6.0) != expected: segments += 1
		check(mismatches == 0 and on > 1000, "%s: 도로 판정 %d점 x 8여유가 GDScript·전수 판정과 일치 (불일치 %d·도로 위 %d)" % [layout, points.size(), mismatches, on])
		check(nearest == 0 and direction == 0, "%s: 가장 가까운 도로 점·도로 방향 일치 (불일치 %d·%d)" % [layout, nearest, direction])
		check(segments == 0, "%s: 도로 구간 표본 판정 일치 (불일치 %d)" % [layout, segments])

## A battle with six guardians on the roads: every navigation question both ways.
func _battle(seed_value: int) -> ArenaSim:
	Arena.start_run(seed_value)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	for unit in Roster.UNITS:
		if Arena.heroes.size() >= Balance.ARENA_HERO_LIMIT: break
		if String(unit["id"]) != String(Arena.heroes[0]["unit"]["id"]): Arena.gain_hero(unit, 1)
	var lanes := ArenaGeometry.route_count()
	for i in range(Arena.heroes.size()):
		var route := ArenaGeometry.route_points(i % lanes)
		var index := route.size() - 1 - 14 - 12 * (i / lanes)
		Arena.heroes[i]["position"] = route[clampi(index, 0, route.size() - 1)]
	Arena.sim.refresh_heroes()
	Arena.sim._rebuild_navigation()
	return Arena.sim

func _check_navigation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	for theme in [0, 7, 19, 31, 44]:
		var sim := _battle(800 + theme)
		Arena.choose_theme(theme)
		sim = Arena.sim
		for i in range(Arena.heroes.size()):
			var route := ArenaGeometry.route_points(i % ArenaGeometry.route_count())
			Arena.heroes[i]["position"] = route[clampi(route.size() - 1 - 14 - 12 * (i / ArenaGeometry.route_count()), 0, route.size() - 1)]
		sim.refresh_heroes()
		sim._rebuild_navigation()
		var layout := ArenaGeometry.layout()
		check(sim._native_nav != null, layout + ": 네이티브 길찾기 객체")
		if sim._native_nav == null: continue
		var guardians := PackedVector2Array()
		for hero in sim.heroes: guardians.append(hero["pos"])
		sim._native_nav.set_heroes(guardians)
		check(sim._native_nav.road_mask(Balance.ARENA_MONSTER_RADIUS) == sim._road_mask_script(), layout + ": 도로 마스크 일치")
		var starts: Array[Vector2] = []
		for road in ArenaGeometry.road_polylines():
			for i in range(0, road.size(), 4):
				var tangent := (road[mini(i + 1, road.size() - 1)] - road[maxi(i - 1, 0)]).normalized()
				starts.append(road[i] + tangent.orthogonal() * rng.randf_range(-50.0, 50.0) + tangent * rng.randf_range(-6.0, 6.0))
		for hero in sim.heroes:
			for n in range(12):
				starts.append(Vector2(hero["pos"]) + Vector2.from_angle(n * TAU / 12.0) * (Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS + rng.randf_range(-3.0, 30.0)))
		var paths := 0
		var segments := 0
		var cells := 0
		var planned := 0
		for from in starts:
			for fly in [false, true]:
				var native_path: PackedVector2Array = sim._native_nav.path_from(from, Balance.ARENA_CENTER, fly)
				var script_path := sim._path_from_script(from, Balance.ARENA_CENTER, fly)
				if not native_path.is_empty(): planned += 1
				if native_path != script_path: paths += 1
			if sim._native_nav.cell(from) != sim._cell(from): cells += 1
			var to := from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 40.0)
			for margin in [Balance.ARENA_MONSTER_RADIUS, Balance.ARENA_MONSTER_RADIUS + 3.0]:
				if sim._native_nav.segment_clear(from, to, margin) != sim._segment_clear_script(from, to, margin): segments += 1
				if sim._native_nav.road_segment_clear(from, to, margin) != sim._road_segment_clear_script(from, to, margin): segments += 1
		check(paths == 0 and planned > starts.size() / 2, "%s: %d 출발점 x 지상·공중 경로 일치 (불일치 %d·경로 있음 %d)" % [layout, starts.size(), paths, planned])
		check(segments == 0 and cells == 0, "%s: 구간 통과 판정·격자 칸 일치 (불일치 %d·%d)" % [layout, segments, cells])

## The same seeded battle, 20 seconds, a guardian walking circles so the crowd replans
## all the time: the library's run and the GDScript run end in the same state.
func _check_battle() -> void:
	var states: Array[Dictionary] = []
	for use_native in [true, false]:
		Native.override(use_native)
		var sim := _battle(901)
		check((sim._native_nav != null) == use_native, "길찾기 경로 선택: %s" % ["네이티브" if use_native else "GDScript"])
		# A late wave: a fuller crowd that the guardians block, so replanning, the deadlock break
		# (ARENA_BLOCK_BREAK) and the bosses' road-only paths all run both ways.
		sim.begin_wave(Balance.ARENA_WAVES - 1)
		Arena.selected = 0
		for n in range(20 * 60):
			if Arena.modal == "talent" and not Arena.talent_offer.is_empty(): Arena.pick_talent(String(Arena.talent_offer[0]))
			if not Arena.modal.is_empty() or sim.done: break
			sim.move_selected(Vector2.from_angle(float(n) / 60.0 * 0.9), 1.0 / 60.0)
			sim.step(1.0 / 60.0)
		var positions: Array = []
		var paths: Array = []
		for mo in sim.monsters:
			positions.append(mo["pos"])
			paths.append(mo["path"])
		states.append({"elapsed": sim.elapsed, "monsters": sim.monsters.size(), "positions": positions, "paths": paths,
			"crystal": sim.crystal_hp, "kills": sim.kills, "hero": sim.heroes[0]["pos"], "rng": sim._rng.state})
	Native.override(true)
	var a := states[0]
	var b := states[1]
	check(a["monsters"] == b["monsters"] and a["positions"] == b["positions"] and a["paths"] == b["paths"], "20초 전투 뒤 몬스터 수·위치·경로 일치 (%d마리)" % int(a["monsters"]))
	check(a["elapsed"] == b["elapsed"] and a["crystal"] == b["crystal"] and a["kills"] == b["kills"] and a["hero"] == b["hero"] and a["rng"] == b["rng"], "수정 체력·처치·난수 상태 일치")

## Every shipped monster through walking, standing, besieging, a hit flash and the authored
## death: the library poses the skeleton exactly as the GDScript sampler does.
func _check_poses() -> void:
	var manifest: Dictionary = NativeMonsterModel.manifest()
	var bodies := 0
	for id in manifest.get("ready_ids", []):
		var data := {}
		for row in Roster.MONSTERS:
			if String(row["id"]) == String(id): data = row
		if data.is_empty() or not NativeMonsterModel.has_model(String(id)): continue
		var node := StellarModels.monster(data) as NativeMonsterModel
		if node == null:
			check(false, String(id) + ": 네이티브 어댑터")
			continue
		add_child(node)
		await frames(1)
		var skeleton := _skeleton(node)
		check(node._pose_native != null and skeleton != null, String(id) + ": 네이티브 자세 객체 결합")
		var mismatches := 0
		var steps := 0
		# A walk, a pause into the idle blend, a siege strike, a hit, a death.
		var script: Array[Array] = [
			[0.0, true, -1.0, 0.0], [0.37, true, -1.0, 0.0], [0.95, true, -1.0, 0.0],
			[1.10, false, -1.0, 0.0], [1.21, false, -1.0, 0.0], [1.40, false, -1.0, 0.0],
			[1.40, false, 0.15, 0.0], [1.40, false, 0.42, 0.0], [1.40, false, 0.80, 0.0],
			[1.60, true, -1.0, 1.0], [1.70, true, -1.0, 0.6], [1.90, true, -1.0, 0.0]]
		for step in script:
			node.face_toward(Vector2(1, 0.3), 1.0 / 60.0)
			node.set_hit_flash(float(step[3]))
			node.set_siege(float(step[2]))
			node.animate_visual(float(step[0]), bool(step[1]))
			if not _same_pose(node, skeleton): mismatches += 1
			steps += 1
		node.visual_event("die", {"p": Vector2.ZERO})
		for n in range(6):
			node.advance_death(0.12)
			if not _same_pose(node, skeleton): mismatches += 1
			steps += 1
		check(mismatches == 0, "%s: %d 단계의 자세가 GDScript 샘플러와 일치 (불일치 %d)" % [id, steps, mismatches])
		node.free()
		bodies += 1
	check(bodies == 25, "출고된 몬스터 25종 비교 (%d)" % bodies)

## The skeleton as the library composed it against the GDScript recomposition of the
## same state. Every bone, every channel, the same bits.
func _same_pose(node: NativeMonsterModel, skeleton: Skeleton3D) -> bool:
	var native_pose := _poses(skeleton)
	node.use_native_pose(false)
	node._compose(node._last_motion)
	node._apply_skeleton()
	var script_pose := _poses(skeleton)
	node.use_native_pose(true)
	node._compose(node._last_motion)
	node._apply_skeleton()
	return native_pose == script_pose and _poses(skeleton) == native_pose

func _poses(skeleton: Skeleton3D) -> Array:
	var out: Array = []
	for i in skeleton.get_bone_count():
		out.append([skeleton.get_bone_pose_position(i), skeleton.get_bone_pose_rotation(i), skeleton.get_bone_pose_scale(i)])
	return out

func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null: return found
	return null
