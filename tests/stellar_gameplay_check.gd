extends Harness


func _ready() -> void:
	if not require_no_save():
		return
	Fixture.prepare(30, 8102026)
	Run.begin_draw()
	Run.ensure_posts()
	var sim := BattleSim.new()
	sim.setup(Run, Run.wave, 8102026)
	for i in range(120):
		sim.step(1.0 / 30.0)
	var before := Run.snapshot().duplicate(true)
	var stats: Array[Dictionary] = []
	for hero in Run.heroes:
		stats.append(Run.hero_stats(hero).duplicate(true))
	var actors_before := sim.monsters.duplicate(true)
	var heroes_before := sim.heroes.duplicate(true)
	var bullets_before := sim.bullets.duplicate(true)
	var events_before := sim.events.duplicate(true)
	var run_rng_before := Run.rng.state
	var sim_rng_before := sim._rng.state
	var host := Node2D.new()
	add_child(host)
	var view := StellarView.new()
	view.attach(host, Rect2(12, 100, 832, 644))
	await frames(2)
	view.world.build_map(Run.theme_for(Run.wave))
	view.world.sync_battle(sim, 4.0, Run.lives)
	check(view.world.hero_nodes.size() == sim.heroes.size(), "실제 편성 인원 그대로 3D 배치")
	check(view.world.monster_nodes.size() == sim.monsters.size(), "시뮬 몬스터 그대로 3D 배치")
	check(view.viewport.own_world_3d and view.world.camera.current, "독립된 실제 3D 월드·카메라")
	for hero in sim.heroes:
		var logical := Vector2(hero["pos"])
		check(StellarWorld.logical(StellarWorld.world(logical)).distance_to(logical) < 0.001, "전투 좌표 왕복 일치")
	for command in ["camera:left", "camera:right", "camera:in", "camera:out", "camera:reset"]:
		check(view.camera_button(command), "카메라 조작 " + command)
	for settings in [Vector2(0, 1), Vector2(0.35, 1.2), Vector2(-0.35, 0.8)]:
		view.world.yaw = settings.x
		view.world.zoom = settings.y
		view.world.camera_update()
		for hero in Run.heroes:
			var post := int(hero["post"])
			var at := Run.hero_position(hero)
			var pixel := view.world.screen(at)
			check(view.world.ground_at(pixel).distance_to(at) < 0.01, "카메라 변경 뒤 논리좌표 역투영 %d" % post)
			var hit := view.project(at, 0.3)
			if view.box.has_point(hit):
				check(view.post_at(hit) == post, "카메라 변경 뒤 실제 발판 선택 %d" % post)
	view.world.sync_battle(sim, 4.2, Run.lives, 0.0)
	check(Run.snapshot() == before and Run.rng.state == run_rng_before, "3D 렌더·카메라는 진행 상태·소환 난수를 변경하지 않음")
	check(sim._rng.state == sim_rng_before, "3D 렌더는 전투 난수를 변경하지 않음")
	check(sim.monsters == actors_before and sim.heroes == heroes_before and sim.bullets == bullets_before, "몬스터·영웅·탄의 판정 좌표와 타이머 보존")
	check(sim.events == events_before, "렌더 준비 중 전투 사건 보존")
	for i in range(Run.heroes.size()):
		check(Run.hero_stats(Run.heroes[i]) == stats[i], "3D 장비 표현이 실제 능력치를 변경하지 않음")
	host.queue_free()
	await frames(2)
	finish("Stellar Defense 3D 연동·게임성 보존 검사")
