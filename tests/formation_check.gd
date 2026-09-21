extends Harness

## 두 입구 · 12자리 · 실시간 재배치 회귀 검사.
##
##   godot --headless --path . res://tests/formation_check.tscn

var main: Node2D


func fresh(count: int = 6) -> void:
	Fixture.fresh(9090912, count)
	Run.phase = Run.Phase.SHOP
	Run.autosave()


func _ready() -> void:
	if not require_no_save():
		return
	fresh(13)
	check(Run.heroes.size() == 12 and Run.bench.size() == 1, "12명 참전, 나머지는 전당")
	check(Balance.POST_POINTS.size() == 12, "이동 가능한 발판 12곳")
	check(not Run.bench_to_field(0), "가득 찬 전장에서 열세 번째 영웅 출전 거절")
	for post in range(Balance.POST_SLOTS):
		check(Run.move_hero(0, post) or Run.heroes[0]["post"] == post, "12인 편성으로 모든 발판 사용 가능")
	var id0: String = Run.heroes[0]["unit"]["id"]
	var from: int = Run.heroes[0]["post"]
	var to: int = Run.heroes[1]["post"]
	check(Run.move_hero(0, to), "찬 자리 교환")
	check(Run.heroes[1]["post"] == from and Run.heroes[0]["post"] == to, "양쪽 위치 교환")
	check(Run.heroes[0]["unit"]["id"] == id0, "목록/전투 ID 불변")
	check(not Run.move_hero(0, 12) and not Run.move_hero(-1, 0), "범위 밖 이동 거부")
	var saved := Run.snapshot().duplicate(true)
	check(Run.restore(saved) and Run.heroes[0]["post"] == to, "저장 복원시 위치 보존")
	var legacy := saved.duplicate(true)
	legacy.erase("formation_v")
	# Legacy stacks become separate cards; all 12 deployed heroes retain their posts.
	legacy["heroes"][6]["n"] = 3
	legacy["last"] = {"unit": legacy["heroes"][6]["u"], "hand": legacy["heroes"][6]["t"],
		"cards": legacy["cards"].duplicate(), "key": [], "where": "field", "slot": 6, "n": 3}
	check(Run.restore(legacy) and Run.heroes.size() == 12 and Run.bench.size() == 3, "기존 12인 저장 유지 및 중첩 카드를 전당에 분리")
	check(Run.last_result["where"] == "field" and Run.heroes[Run.last_result["slot"]]["unit"]["id"] == legacy["last"]["unit"], "중첩 분리 후 기존 출전 영웅의 상세 위치 유지")
	var all_before := {}
	for h in legacy["heroes"] + legacy["bench"]:
		all_before[h["u"]] = int(all_before.get(h["u"], 0)) + int(h["n"])
	var all_after := {}
	for h in Run.heroes + Run.bench:
		var id: String = h["unit"]["id"]
		all_after[id] = int(all_after.get(id, 0)) + int(h["n"])
	check(all_after == all_before, "12인 저장의 모든 영웅 카드 수 보존")
	check(Run.restore(Run.snapshot()), "변환된 12인 저장 재복원")
	var oversized := saved.duplicate(true)
	var extra: Dictionary = oversized["bench"].pop_back()
	extra["post"] = -1
	oversized["heroes"].append(extra)
	check(not Run.restore(oversized), "새 저장의 12명 초과 편성 거절")
	var old := saved.duplicate(true)
	old["heroes"] = old["heroes"].slice(0, 6)
	for h in old["heroes"] + old["bench"]:
		h.erase("post")
	check(Run.restore(old) and Run.heroes.size() == 6, "기존 6인 저장 마이그레이션")
	var positions := {}
	for h in Run.heroes:
		positions[h["post"]] = true
	check(positions.size() == 6, "기존 저장 위치 중복 없음")
	var invalid := saved.duplicate(true)
	invalid["heroes"][0]["post"] = invalid["heroes"][1]["post"]
	var before := Run.snapshot().duplicate(true)
	check(not Run.restore(invalid) and before == Run.snapshot(), "중복 위치 거절, 기존 판 보존")
	invalid = saved.duplicate(true)
	invalid["heroes"][0]["post"] = "2"
	check(not Run.restore(invalid), "문자열 배치 거절")
	fresh(4)
	Run.phase = Run.Phase.BATTLE
	Run.autosave()
	var baseline := Save.cur_run.duplicate(true)
	var sim := BattleSim.new()
	sim.setup(Run, 1)
	sim._spawn(Roster.MONSTERS[0])
	sim._spawn(Roster.MONSTERS[0])
	check(sim.monsters[0]["route"] != sim.monsters[1]["route"], "양쪽 입구 번갈아 등장")
	check(BattleSim.mpos(sim.monsters[0]).distance_to(Vector2(24, 150)) < 0.1, "좌상단 등장 위치")
	check(BattleSim.mpos(sim.monsters[1]).distance_to(Vector2(808, 690)) < 0.1, "우하단 등장 위치")
	# Actively move during an ongoing windup with projectiles already in flight.
	sim.heroes[0]["cool"] = 0.47
	sim.heroes[0]["dmg"] = 123.0
	sim.heroes[0]["kills"] = 3
	sim.heroes[0]["acc"] = 2.0
	sim._pending.append({"src": 0, "wait": 0.2})
	sim.bullets.append({"owner": 0, "p": Vector2(500, 300)})
	Run.gold += 123
	Run.kills += 3
	Run.lives -= 2
	var pre: Dictionary = sim.heroes[0].duplicate(true)
	check(sim.move_hero(0, 11), "전투 중 빈자리 이동")
	for key in ["cool", "dmg", "kills", "acc", "st", "muz", "face"]:
		check(sim.heroes[0][key] == pre[key], "이동 중 전투 상태 유지: " + key)
	check(sim.heroes[0]["pos"] == Balance.post_position(11), "시뮬레이터/총구 원점 동기화")
	check(sim._pending.size() == 1 and sim.bullets.size() == 1, "진행 중 공격/탄 유지")
	for key in ["gold", "kills", "lives", "rng", "cards", "phase"]:
		check(Save.cur_run[key] == baseline[key], "이동 저장이 탄 시작 스냅샷을 훼손하지 않음: " + key)
	check(Save.cur_run["heroes"][0]["post"] == 11, "전투 배치만 자동 저장")
	check(Run.restore(Save.cur_run) and Run.heroes[0]["post"] == 11, "전투 이어하기 위치 유지")
	check(Run.gold == baseline["gold"] and Run.lives == baseline["lives"], "재접속 보상/손실 중복 없음")
	sim.done = true
	check(not sim.move_hero(0, 2), "전투 종료 후 이동 거부")
	main = load("res://game/main.gd").new()
	add_child(main)
	await check_field_first_exchange()
	fresh(13)
	main.go_shop()
	main.screen.set_process(false)
	await paint(main.screen)
	check(tap(main.screen, "tab:f"), "정비 배치 탭 클릭")
	await paint(main.screen)
	check(main.screen.formation.post_rects.size() == 12, "정비 탭 발판 12개")
	check(tap(main.screen, "reserve:0"), "전당 영웅 선택")
	var replacement_id: String = Run.bench[0]["unit"]["id"]
	check(tap(main.screen, "post:11"), "가득 찬 전장에서 영웅 교체")
	check(Run.heroes[Run.hero_at_post(11)]["unit"]["id"] == replacement_id and main.screen.formation.bench_selected == -1, "지정한 발판의 영웅을 교체한 뒤 선택 해제")
	check(Run.heroes.size() == 12 and Run.bench.size() == 1, "전당 교체 시 12명 제한과 영웅 수 보존")
	await paint(main.screen)
	check(tap(main.screen, "post:0"), "전장 영웅 선택")
	var form: FormationView = main.screen.formation
	var origin := form.post_rects[0].get_center()
	var destination := form.post_rects[11].get_center()
	var moving := Run.hero_at_post(0)
	mouse(main.screen, origin, true)
	mouse(main.screen, destination, false)
	check(Run.heroes[moving]["post"] == 11, "정비 화면 실제 드래그")
	fresh(3)
	Run.phase = Run.Phase.DRAW
	Run.confirm_hand()
	main.show_draw()
	main.screen.set_process(false)
	await paint(main.screen)
	check(main.screen.state == DrawScreen.SWAP and main.screen.formation_tab, "포커 확정/복원 후 배치 팝업")
	check(tap(main.screen, "post:4"), "포커 후 영웅 선택")
	check(tap(main.screen, "post:11"), "포커 후 위치 변경")
	check(main.screen.state == DrawScreen.SWAP, "배치 중 자동 전투 진입 없음")
	check(tap(main.screen, "formation:roster"), "영웅 정보 탭 유지")
	await paint(main.screen)
	for i in range(Balance.HERO_SLOTS):
		var found := false
		for z in main.screen.ui.zones:
			if z["id"] == "hv:f%d" % i:
				found = Look.SCREEN.encloses(z["rect"])
		check(found, "영웅 정보의 출전 12자리 화면 안에 존재")
	main.go_battle()
	main.screen.set_process(false)
	await paint(main.screen)
	var battle: BattleScreen = main.screen
	moving = 0
	from = int(Run.heroes[moving]["post"])
	# Click followed by click, then drag, then dropping outside the map.
	var at := Balance.post_position(from) - Vector2(0, 24)
	mouse(battle, at, true)
	mouse(battle, at, false)
	var target := Balance.post_position(2) - Vector2(0, 24)
	mouse(battle, target, true)
	mouse(battle, target, false)
	check(Run.heroes[moving]["post"] == 2, "실전 클릭-클릭 이동")
	mouse(battle, target, true)
	mouse(battle, Balance.post_position(10), false)
	check(Run.heroes[moving]["post"] == 10, "실전 드래그 이동")
	mouse(battle, Balance.post_position(10), true)
	mouse(battle, Vector2(1200, 600), false)
	check(Run.heroes[moving]["post"] == 10, "맵 밖 드롭 취소")
	main.menu.open()
	check(not battle.is_processing() and not battle.is_processing_input(), "메뉴에서 전투와 재배치 일시정지")
	main.menu.close()
	finish("배치 회귀 검사")


func check_field_first_exchange() -> void:
	for in_shop in [true, false]:
		fresh(13)
		if in_shop:
			main.go_shop()
			main.screen.tab = "f"
		else:
			Run.phase = Run.Phase.DRAW
			Run.confirm_hand()
			main.show_draw()
		main.screen.set_process(false)
		var view: FormationView = main.screen.formation
		view.element = String(Run.bench[0]["unit"]["elem"])
		await paint(main.screen)
		if in_shop:
			check(tap(main.screen, "tab:f"), "open camp formation for field-first exchange")
			await paint(main.screen)
		var outgoing: Dictionary = Run.heroes[0].duplicate(true)
		var incoming: Dictionary = Run.bench[0].duplicate(true)
		var post := int(outgoing["post"])
		var total := Run.hero_total()
		check(tap(main.screen, "post:%d" % post), "select deployed hero first")
		await paint(main.screen)
		check(tap(main.screen, "reserve:0"), "tap reserve to exchange with selected field hero")
		check(Run.heroes[0]["unit"]["id"] == incoming["unit"]["id"] and Run.heroes[0]["post"] == post,
				"reserve hero takes precisely the selected field post")
		check(Run.bench[0]["unit"]["id"] == outgoing["unit"]["id"] and not Run.bench[0].has("post"),
				"outgoing field hero takes the clicked reserve slot")
		check(Run.hero_total() == total and view.selected == -1 and view.bench_selected == -1,
				"field-first exchange preserves cards and clears both selections")
		var swapped := Run.snapshot()
		check(Run.restore(swapped) and Run.snapshot()["heroes"] == swapped["heroes"] \
				and Run.snapshot()["bench"] == swapped["bench"], "field-first exchange survives save and resume")
		# A reserve copy of another deployed hero must never create duplicate deployment.
		var duplicate := Run.gain_hero(Run.heroes[1]["unit"], int(Run.heroes[1]["tier"]), false)
		var index := int(duplicate["slot"])
		view.element = String(Run.bench[index]["unit"]["elem"])
		view.page = view.visible_indices().find(index) / FormationView.PAGE_SIZE
		await paint(main.screen)
		check(tap(main.screen, "post:%d" % post), "select field hero before blocked duplicate exchange")
		var before := Run.snapshot()
		await paint(main.screen)
		check(tap(main.screen, "reserve:%d" % index), "click duplicate reserve card")
		check(Run.snapshot() == before and view.selected == 0 and not view.note.is_empty(),
				"duplicate exchange preserves both rosters and explains rejection")
