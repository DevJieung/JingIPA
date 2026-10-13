extends Harness

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_check_expanded_battle()
	await _check_camera()
	Arena.running = false
	finish("확장 전장·추적 카메라·미니맵")

func _check_expanded_battle() -> void:
	check(PI * ArenaGeometry.RADIUS * ArenaGeometry.RADIUS > Balance.MAP_RECT.get_area() * 1.5, "실제 이동 면적 확대")
	Arena.start_run(912)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	var sim: ArenaSim = Arena.sim
	var limits := ArenaGeometry.MAP_RECT.grow(-Balance.ARENA_HERO_RADIUS)
	for corner in ArenaGeometry.outline(8, Balance.ARENA_HERO_RADIUS):
		Arena.heroes[0]["position"] = corner
		sim.refresh_heroes()
		sim.move_selected((corner - Balance.ARENA_CENTER).normalized(), 0.25)
		check(Vector2(sim.heroes[0]["pos"]).is_equal_approx(corner), "새 맵 끝을 넘어 이동하지 않음")
		check(ArenaValidation.valid(Arena.snapshot()), "새 맵 모서리 저장 유효")
		# Pushing outward re-clamps the point onto the rim; the result differs from the
		# corner only by float noise (< 1e-4) that depends on the hero's own speed.
		check(Arena.restore(Arena.snapshot()) and Vector2(Arena.heroes[0]["position"]).is_equal_approx(corner), "모서리 위치 이어하기 보존")
		sim = Arena.sim
	for i in range(80): sim._spawn(Arena.spawns_for(1)[0])
	var spawn_radius := ArenaGeometry.RADIUS - Balance.ARENA_MONSTER_RADIUS
	for mo in sim.monsters:
		var p: Vector2 = mo["pos"]
		check(ArenaGeometry.contains(p, Balance.ARENA_MONSTER_RADIUS), "원형 경계 안 적 출현")
		check(absf(p.distance_to(Balance.ARENA_CENTER) - spawn_radius) < 0.1 and ArenaGeometry.on_road(p, Balance.ARENA_MONSTER_RADIUS), "외곽 도로 입구에서 적 출현")
	for y in range(sim._nav.region.size.y):
		for x in range(sim._nav.region.size.x):
			var cell := Vector2i(x, y)
			if not ArenaGeometry.on_road(sim._nav.get_point_position(cell), Balance.ARENA_MONSTER_RADIUS):
				check(sim._nav.is_point_solid(cell), "원 밖과 길 밖 셀은 적 통행 금지")
	# Exercise real firing and damage along the outer entrance.
	sim.monsters.clear()
	var left := Vector2(limits.position.x + 2, Balance.ARENA_CENTER.y)
	# This is about a projectile at the rim. The run's first hero may be a sword hero,
	# whose strike has no projectile, so a bow joins and fires instead.
	var archer := 0
	if Balance.is_melee(Arena.heroes[0]["unit"]):
		Arena.gain_hero(Roster.unit_by_id("echo"), 1)
		archer = Arena.heroes.size() - 1
	Arena.heroes[archer]["position"] = left
	sim.refresh_heroes()
	sim._spawn(Arena.spawns_for(1)[0])
	var enemy: Dictionary = sim.monsters[0]
	enemy["pos"] = left + Vector2(75, 0)
	enemy["hp"] = 10000.0
	enemy["max"] = 10000.0
	sim._cache_positions()
	sim.heroes[archer]["fx_d"] = (enemy["pos"] - left).normalized()
	sim._shoot(archer, 0, 100, "shot", false)
	check(not sim.bullets.is_empty(), "확장 왼쪽 경계에서 발사")
	for i in range(90): sim._move_bullets(1.0 / 60.0)
	check(float(enemy["hp"]) < 10000.0, "확장 경계의 탄환이 조기 소멸 없이 명중")
	sim._rebuild_navigation()
	sim._move_monsters(1.0 / 60.0)
	check(ArenaValidation.valid(Arena.snapshot()), "확장 맵 적 경로와 투사체 저장 유효")

func _check_camera() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var view := ArenaView.new()
	view.attach(holder, Rect2(0, 0, 1280, 800))
	await frames(2)
	view.follow_selected(Balance.ARENA_CENTER, 0.0)
	var original := view.world.camera.transform
	var magnification: float = view.world.camera.size
	var actor_height := view.project(Balance.ARENA_CENTER, 2.0).distance_to(view.project(Balance.ARENA_CENTER, 0.0))
	check(is_equal_approx(magnification, ArenaWorld.CAMERA_SIZE), "전장 전체 프레이밍 배율 34")
	check(view.project(Balance.ARENA_CENTER).distance_to(view.battle_box.get_center()) < 22,
		"수정이 상하 HUD 사이 전장 중앙에 위치")
	# 2026-10-12 spiral field: the whole 1200-logical circle, every gate included, sits
	# inside the open battle box at rest, so the roads read without any camera travel.
	for point in ArenaGeometry.outline(24):
		check(view.battle_box.grow(-20).has_point(view.project(point, 0.0)), "정지 시점에서 원 테두리 전체가 전장 안에 보임")
	for lane in range(ArenaGeometry.route_count()):
		check(view.battle_box.grow(-20).has_point(view.project(ArenaGeometry.route_points(lane)[0], 0.0)), "네 입구가 모두 보임")
	var hero_px := actor_height
	check(hero_px > 50 and hero_px < 70, "2u 영웅 화면 높이 50~70px (실측 %.1f)" % hero_px)
	var destinations := ArenaGeometry.outline(8, Balance.ARENA_HERO_RADIUS)
	for point in destinations:
		for frame in range(150): view.follow_selected(point, 1.0 / 60.0)
		# Full-field framing: the rim hero pulls the view at most a hair (edge guard), never
		# a tracking pan; the magnification and object sizes never change.
		check(view.world.camera.position.distance_to(original.origin) < 1.0, "가장자리에서도 카메라가 거의 고정(1u 미만 보정)")
		check(is_equal_approx(view.world.camera.size, magnification), "가장자리에서도 카메라 배율 유지")
		check(is_equal_approx(view.project(point, 2.0).distance_to(view.project(point)), actor_height), "오브젝트 화면 크기 유지")
		for height in [0.08, 1.95]:
			check(view.battle_box.grow(-24).has_point(view.project(Balance.ARENA_CENTER, height)), "끝까지 가도 수정 전체가 보임")
		check(not view.minimap_box.grow(20).has_point(view.project(Balance.ARENA_CENTER, 1.0)), "미니맵이 중앙 수정을 가리지 않음")
		check(view.battle_box.grow(-12).has_point(view.project(point, 1.0)), "가장자리 영웅이 HUD에 가려지지 않음")
		check(view.battle_box.grow(-ArenaView.EDGE_GUARD.x + 2).has_point(Vector2(view.project(point, 0.5).x, view.battle_box.get_center().y)), "가장자리 영웅이 명령 레일에서 64px 이상 떨어짐")
		var pixel := view.project(point)
		check(view.ground_at(pixel).distance_to(point) < 0.02, "이동한 카메라 지면 역투영 일치")
		view._hero_hits.assign([{"index":0, "post":0, "at":point}])
		check(view.hero_at(view.project(point, 0.9)) == 0, "추적 이후 실제 영웅 터치 선택")
		var footprint := view.minimap_footprint(Rect2(1086, 90, 160, 118))
		check(footprint.size() >= 3, "미니맵 카메라 시야 다각형 존재")
		for vertex in footprint:
			check(Rect2(1086, 90, 160, 118).grow(0.1).has_point(vertex), "미니맵 시야를 맵 경계로 자름")
	var paused := view.world.camera.transform
	view.follow_selected(destinations[0], 0.0)
	check(view.world.camera.transform.is_equal_approx(paused), "모달·일시정지 중 추적도 정지")
	view.follow_selected(destinations[0], 1.0 / 60.0)
	check(view.world.camera.position.distance_to(paused.origin) < 4.0, "다른 영웅 선택 시 한 프레임 순간이동 없음")
	await _check_boss_camera(view, original)
	var mini := Rect2(20, 20, 180, 126)
	check(view.minimap_point(Balance.ARENA_CENTER, mini).is_equal_approx(mini.get_center()), "미니맵 중앙 수정 위치")
	check(view.minimap_point(ArenaGeometry.MAP_RECT.position, mini).is_equal_approx(mini.position), "미니맵 좌상단 위치")
	check(view.minimap_point(ArenaGeometry.MAP_RECT.end, mini).is_equal_approx(mini.end), "미니맵 우하단 위치")
	holder.queue_free()
	await frames(2)

## Boss entrance: anticipation lean during the warning, an 8% punch with a short shake
## at the spawn, then a settle back to the identical full-field framing. Simulated time
## drives it, so paused frames never advance it, and the crystal never leaves the box.
func _check_boss_camera(view: ArenaView, original: Transform3D) -> void:
	for frame in range(120): view.follow_selected(Balance.ARENA_CENTER, 1.0 / 60.0)
	var rest := view.world.camera.transform
	check(rest.origin.distance_to(original.origin) < 0.05, "중앙 복귀 후 기준 프레이밍")
	var gate := ArenaGeometry.route_points(0)[0]
	var gate_before := view.project(gate, 0.0)
	view.boss_event("warn", gate)
	# draw_arena advances the entrance clock with the simulated dt; mirror that here.
	for frame in range(240):
		view.boss_advance(1.0 / 60.0)
		view.follow_selected(Balance.ARENA_CENTER, 1.0 / 60.0)
	# Measured on screen: the crystal (the camera target) slides away from the box
	# centre by the lean, 0.35u ≈ 13px during the warning, 0.95u ≈ 38px at the entrance.
	var centre := view.battle_box.get_center()
	var lean := view.project(Balance.ARENA_CENTER, 0.0).distance_to(centre)
	check(lean > 8 and lean < 20, "예고 4초 동안 입구 쪽으로 0.35u(약 13px) 기울기 (실측 %.1fpx)" % lean)
	check(view.project(gate, 0.0).distance_to(view.battle_box.get_center()) < gate_before.distance_to(view.battle_box.get_center()), "예고 기울기가 입구를 중앙 쪽으로 당김")
	check(is_equal_approx(view.world.camera.size, ArenaWorld.CAMERA_SIZE), "예고 중에는 배율 유지")
	view.boss_event("spawn", gate)
	view.follow_selected(Balance.ARENA_CENTER, 0.0)
	var frozen := view.world.camera.transform
	for frame in range(5):
		view.boss_advance(0.0)
		view.follow_selected(Balance.ARENA_CENTER, 0.0)
	check(view.world.camera.transform.is_equal_approx(frozen), "일시정지 프레임은 보스 연출을 진행하지 않음")
	var smallest := INF
	var farthest := 0.0
	for frame in range(60):
		view.boss_advance(1.0 / 60.0)
		view.follow_selected(Balance.ARENA_CENTER, 1.0 / 60.0)
		smallest = minf(smallest, view.world.camera.size)
		farthest = maxf(farthest, view.project(Balance.ARENA_CENTER, 0.0).distance_to(centre))
		for height in [0.08, 1.95]:
			check(view.battle_box.grow(-24).has_point(view.project(Balance.ARENA_CENTER, height)), "보스 연출 중에도 수정 전체가 보임")
		check(view.battle_box.grow(-6).has_point(view.project(gate, 0.0)), "보스 연출 중 입구가 화면 안")
	check(smallest < ArenaWorld.CAMERA_SIZE / 1.06, "출현 순간 8%% 줌 펀치 (최소 배율 %.2f)" % smallest)
	check(farthest > 30 and farthest < 60, "출현 순간 입구 쪽 0.95u(약 38px) 기울기+흔들림 (최대 %.1fpx)" % farthest)
	for frame in range(120):
		view.boss_advance(1.0 / 60.0)
		view.follow_selected(Balance.ARENA_CENTER, 1.0 / 60.0)
	check(String(view.boss_emphasis()["phase"]).is_empty(), "1.7초 뒤 연출 종료")
	check(is_equal_approx(view.world.camera.size, ArenaWorld.CAMERA_SIZE), "연출 뒤 배율 복귀")
	check(view.world.camera.position.distance_to(rest.origin) < 0.05, "연출 뒤 기준 프레이밍 복귀")
