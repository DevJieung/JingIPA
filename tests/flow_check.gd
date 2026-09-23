extends Harness

## 저장 · 보상 · 메뉴 · 거래 회귀 검사.
##
##   godot --headless --path . res://tests/flow_check.tscn


func _ready() -> void:
	if not require_no_save():
		return
	_test_restore()
	_test_transactions()
	_test_upgrade_limits()
	_test_storage()
	_test_ui_layers()
	_test_matchups()
	_test_restart_determinism()
	await _test_menu_and_rewards()
	finish("게임 흐름 회귀 검사")


func _fresh() -> void:
	Fixture.fresh(9092026)


func _reject(d: Dictionary, label: String) -> void:
	var before := Run.snapshot().duplicate(true)
	check(not Run.restore(d), "손상된 저장 거절: " + label)
	check(Run.snapshot() == before, "복구 실패가 현재 판을 바꿈: " + label)


func _test_restore() -> void:
	Run.start_run(9092026)
	Save._flush()
	check(Save.cur_run.is_empty(), "첫 테마 소개 중 종료해도 잘못된 0탄을 저장하지 않음")
	Run.begin_draw()
	Run.reroll(0)
	var good := Run.snapshot().duplicate(true)
	check(Run.restore(good), "유효한 DRAW 저장 복구")
	for key in ["cards", "rerolled", "paid", "piles", "at", "themes", "heroes", "bench", "passives", "owned_passives", "hero_damage", "offer", "levels", "last", "rng"]:
		var bad := good.duplicate(true)
		bad[key] = "손상"
		_reject(bad, key + " 형")
	for pair in [["wave", 101], ["wave", 0], ["phase", 99], ["phase", 5], ["lives", 21], ["best_hand", 10]]:
		var bad := good.duplicate(true)
		bad[pair[0]] = pair[1]
		_reject(bad, str(pair))
	var bad := good.duplicate(true)
	bad["rerolled"] = []
	_reject(bad, "교체 횟수 누락")
	bad = good.duplicate(true)
	bad["cards"][1] = bad["cards"][0]
	_reject(bad, "손패 카드 중복")
	bad = good.duplicate(true)
	bad["cards"][0] = 99
	_reject(bad, "범위 밖 카드")
	bad = good.duplicate(true)
	bad["themes"][0] = Roster.THEMES.size()
	_reject(bad, "테마 범위")
	bad = good.duplicate(true)
	bad["levels"]["crit"] = 999
	_reject(bad, "강화 상한")
	bad = good.duplicate(true)
	bad["passives"] = ["deal", "deal"]
	_reject(bad, "패시브 중복")
	var result := Run.confirm_hand().duplicate(true)
	good = Run.snapshot().duplicate(true)
	Run.start_run(55)
	check(Run.restore(good), "편성 저장 복구")
	check(Run.last_hand == result["hand"] and Run.last_cards == result["cards"], "확정 결과 복구")
	var count := Run.hero_total()
	check(not Run.reroll(0), "확정 후 리롤 금지")
	Run.confirm_hand()
	check(Run.hero_total() == count, "편성 중 중복 확정 금지")
	Run.phase = Run.Phase.BATTLE
	check(Run.confirm_hand().is_empty(), "전투 중 영웅 추가 금지")
	Run.phase = Run.Phase.SHOP
	check(Run.confirm_hand().is_empty(), "상점 중 영웅 추가 금지")
	check(Run.best_hand == result["hand"], "이번 판 최고 족보 복구")


func _test_transactions() -> void:
	_fresh()
	Run.confirm_hand()
	Run.phase = Run.Phase.SHOP
	Run.gold = 10000
	for id in ["deal", "keenedge", "repeater"]:
		check(Run.buy_passive(id), "빈 활성 칸의 패시브 구매")
	check(Run.passives.size() == 3 and Run.owned_passives.size() == 3, "첫 세 구매 자동 활성")
	var balance := Run.gold
	check(Run.buy_passive("joker"), "활성 세 칸이 차도 네 번째 보유 구매")
	check(Run.gold == balance - int(Balance.passive_by_id("joker")["cost"]), "네 번째 구매는 전체 가격")
	check(Run.owned_passives.size() == 4 and Run.passives.size() == 3 and not Run.has("joker"), "보유와 활성 효과 분리")
	var before := Run.snapshot().duplicate(true)
	check(not Run.toggle_passive("joker"), "네 번째 동시 활성 거절")
	check(not Run.sell_passive("deal") and not Run.replace_passive(0, "joker"), "판매와 차액 거래 거절")
	check(not Run.buy_passive("joker") and not Run.buy_passive("missing"), "보유 중복과 잘못된 구매 거절")
	check(Run.snapshot() == before, "실패 거래에 부작용 없음")
	check(Run.toggle_passive("deal") and Run.toggle_passive("joker"), "보유 중 무료 활성 교체")
	check(Run.owns_passive("deal") and not Run.has("deal") and Run.has("joker"), "비활성 패시브도 보유 유지")
	check(Run.free_rerolls() == Balance.FREE_REROLL, "비활성 큰손은 무료교체 효과 없음")
	check(Save.cur_run == Run.snapshot(), "활성 변경 즉시 저장")
	var saved := Save.cur_run.duplicate(true)
	check(Run.restore(saved) and Run.owned_passives.size() == 4 and Run.has("joker"), "네 장 이상 보유와 활성 저장 복구")
	var legacy := saved.duplicate(true)
	legacy.erase("owned_passives")
	legacy.erase("hero_damage")
	check(Run.restore(legacy) and Run.owned_passives == Run.passives, "이전 저장 활성 패시브 보유 이관")
	check(Run.restore(saved), "신규 저장 재복구")
	Run.passives.clear()
	check(Save.cur_run == saved, "저장 데이터와 실행 배열 분리")
	Run.phase = Run.Phase.BATTLE
	check(not Run.toggle_passive("deal"), "전투 도중 활성 변경 금지")


func _test_upgrade_limits() -> void:
	# 구매 경로, 표시값, 전투값 모두 같은 상한을 적용해야 한다.
	var limits := {"crit": [15, 0.60, 0.04], "critx": [20, 6.0, 2.20], "rate": [23, 3.0, 1.05]}
	for id in limits:
		_fresh()
		Run.gold = 1000000
		var cap := int(limits[id][0])
		var top := float(limits[id][1])
		check(is_equal_approx(Run.up_at(id, 1), float(limits[id][2])), id + " 단계당 증가량")
		for level in range(cap):
			check(not Balance.upgrade_maxed(id, level) and Run.up_at(id, level) < top,
					id + " 상한 전 강화 가능")
			check(Run.buy_upgrade(id), id + " 상한까지 구매 성공")
		check(Balance.upgrade_maxed(id, Run.lv(id)), id + " 최대 단계 도달")
		check(is_equal_approx(Run.up_at(id, cap), top), id + " 최대 표시값")
		check(is_equal_approx(Run.up_at(id, cap + 1), top) and is_equal_approx(Run.up_at(id, 999), top),
				id + " 초과 단계도 수치 상한 유지")
		var before := Run.snapshot().duplicate(true)
		check(not Run.buy_upgrade(id) and Run.snapshot() == before, id + " 최대 단계 구매 시 골드·상태 보존")

	_fresh()
	Run.confirm_hand()
	Run.levels = {"crit": 15, "critx": 20, "rate": 23}
	for with_passives in [false, true]:
		Run.passives.assign(["scope", "headsman", "repeater"] if with_passives else [])
		var chance := 0.70 if with_passives else 0.60
		var critx := 7.0 if with_passives else 6.0
		var rate := 3.6 if with_passives else 3.0
		check(is_equal_approx(Run.stat_now("crit"), chance), "치명타 확률: 강화 상한 후 패시브 별도 적용")
		check(is_equal_approx(Run.stat_now("critx"), critx), "치명타 배율: 강화 상한 후 패시브 별도 적용")
		check(is_equal_approx(Run.stat_now("rate"), rate), "공격속도: 강화 상한 후 패시브 별도 적용")
		for unit in Roster.UNITS:
			var tier := int(unit["tier"])
			var stats := Run.hero_stats({"unit": unit, "tier": tier, "n": 1})
			var bonus := Balance.RIDER_CRIT if unit["role"] == "rider" and unit["elem"] == "none" else 0.0
			var base_rate: float = Balance.TIER_RATE[tier] * float(Balance.PROFILE[unit["profile"]]["rate"])
			check(is_equal_approx(float(stats["crit"]), minf(0.85, chance + bonus)), "전투 치명타 확률과 영웅 고유 효과")
			check(is_equal_approx(float(stats["critx"]), critx), "전투 치명타 배율 상한")
			check(is_equal_approx(float(stats["rate"]), base_rate * rate), "전투 공격속도 강화 배수 상한")

	Run.passives.clear()
	var legacy := Run.snapshot().duplicate(true)
	legacy["levels"] = {"crit": 11, "critx": 40, "rate": 40}
	var original := legacy.duplicate(true)
	check(Run.restore(legacy), "기존 무제한 강화 저장 이어하기")
	check(Run.lv("critx") == 20 and Run.lv("rate") == 23 and Run.lv("crit") == 11,
			"기존 저장의 초과 단계만 새 상한으로 보정")
	check(legacy == original, "저장 보정 시 원본 데이터 보존")
	check(Run.restore(Run.snapshot()) and Run.lv("critx") == 20 and Run.lv("rate") == 23,
			"보정된 저장 재복구")


func _test_storage() -> void:
	_fresh()
	var store = load("res://core/save.gd").new()
	var path := "user://flow-check-%d.cfg" % Time.get_ticks_usec()
	store.storage_path = path
	store.cur_run = Run.snapshot().duplicate(true)
	store.runs = 1
	store.music = false
	check(store.save_file(), "첫 원자 저장")
	store.runs = 2
	check(store.save_file(), "두 번째 원자 저장")
	var readback := ConfigFile.new()
	check(readback.load(path) == OK and readback.get_value("run", "runs") == 2, "최신 저장 읽기")
	check(readback.get_value("opt", "music", true) == false, "배경음악 설정 저장")
	store.music = true
	store.load_file()
	check(not store.music, "배경음악 설정 복원")
	check(readback.load(path + ".bak") == OK and readback.get_value("run", "runs") == 1, "이전 정상 저장 보존")
	# 파싱 가능한 파일도 의미적으로 손상될 수 있다.
	var corrupt := ConfigFile.new()
	corrupt.set_value("cur", "state", "잘못된 형")
	corrupt.save(path)
	store.load_file()
	check(store.recovered_backup and store.runs == 1, "손상된 본 파일에서 백업 복구")
	check(store.save_file(), "백업 복구 뒤 본 파일 재작성")
	store.storage_path = "user://missing-%d/save.cfg" % Time.get_ticks_usec()
	store.runs = 3
	check(not store.save_file() and store.last_error != OK, "쓰기 실패 감지")
	store.storage_path = path
	check(store.save_file() and store.last_error == OK, "쓰기 실패 후 동일 내용 재시도")
	check(readback.load(path) == OK and readback.get_value("run", "runs") == 3, "재시도 내용 확인")
	# 옛 규칙의 진행 중 판만 제외하고 평생 기록은 보존한다.
	readback.set_value("cur", "state", {"v": Run.SAVE_VERSION - 1, "wave": 40})
	readback.save(path)
	store.load_file()
	check(store.runs == 3 and store.cur_run.is_empty(), "이전 버전의 평생 기록 보존")
	var empty := ConfigFile.new()
	empty.save(path)
	store.load_file()
	check(store.recovered_backup, "빈 저장 파일은 정상 기록으로 취급하지 않음")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	store.free()


func _test_ui_layers() -> void:
	var ui := Ui.new()
	ui.zone(Rect2(0, 0, 100, 100), "under")
	ui.zone(Rect2(10, 10, 80, 80), "disabled", false)
	check(ui.hit(Vector2(50, 50)) == "", "비활성 버튼을 뚫고 아래 버튼이 눌림")
	check(ui.hit(Vector2(5, 5)) == "under", "겹치지 않는 버튼은 동작")


func _test_matchups() -> void:
	_fresh()
	Run.heroes = [{"unit": Roster.unit_by_id("pip"), "tier": 0, "n": 4, "wave": 1}]
	for row in Run.formation_matchups():
		check(is_equal_approx(row["mult"], 1.0), "무상성 편성은 항상 100%")
	Run.heroes[0]["unit"] = Roster.unit_by_id("brigid")
	for row in Run.formation_matchups():
		check(is_equal_approx(row["mult"], Balance.elem_mult("elec", row["body"])), "편성 조언이 실제 상성표와 일치")


func _test_restart_determinism() -> void:
	_fresh()
	Run.confirm_hand()
	Run.phase = Run.Phase.BATTLE
	var checkpoint := Run.snapshot().duplicate(true)
	var first := BattleSim.new()
	first.setup(Run, Run.wave)
	for i in range(180):
		first.step(1.0 / 60.0)
	var gold := Run.gold
	Run.restore(checkpoint)
	var second := BattleSim.new()
	second.setup(Run, Run.wave)
	for i in range(180):
		second.step(1.0 / 60.0)
	check(first.monsters == second.monsters and first.bullets == second.bullets,
			"전투 재시작의 이동과 공격이 동일")
	check(first.kills == second.kills and Run.gold == gold, "전투 재시작의 처치와 골드가 동일")


func _test_menu_and_rewards() -> void:
	var main = load("res://game/main.gd").new()
	add_child(main)
	_fresh()
	Run.confirm_hand()
	main.go_battle()
	await frames(3)
	for what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		main._notification(what)
		check(not main.menu.opened and main.screen.is_processing(), "앱 상태 변경으로 메뉴를 자동 표시하지 않음")
	# 전환 중 받은 알림도 다음 화면에서 메뉴를 열지 않아야 한다.
	main.go(main.go_battle)
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	main._process(1.0)
	main._process(1.0)
	await frames(3)
	check(not main.menu.opened and main.screen.is_processing(), "화면 전환 뒤 예약된 팝업 없음")
	var b: BattleScreen = main.screen
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	get_viewport().push_input(key)
	var elapsed := b.sim.elapsed
	await frames(10)
	check(main.menu.opened and b.sim.elapsed == elapsed, "메뉴에서 실제 전투 정지")
	check(not b.is_processing_input(), "모달 아래 입력 차단")
	var sfx_before := Save.sfx
	for zone in main.menu.ui.zones:
		if zone["id"] == "sound":
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = Rect2(zone["rect"]).get_center()
			get_viewport().push_input(click, true)
			break
	check(Save.sfx != sfx_before, "실제 메뉴 터치가 효과음 설정에 도달")
	Save.set_sfx(sfx_before)
	for page in ["rules", "hands", "elements", "menu"]:
		main.menu.page = page
		await frames(2)
	main.menu.close()
	await frames(3)
	check(b.sim.elapsed > elapsed and b.is_processing_input(), "메뉴 닫은 뒤 전투 재개")
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	elapsed = b.sim.elapsed
	await frames(3)
	check(not main.menu.opened and b.sim.elapsed > elapsed, "포커스 상실 뒤 팝업 없이 전투 진행")
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(main.menu.opened and not b.is_processing(), "뒤로 가기로 메뉴 열기")
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not main.menu.opened and b.is_processing(), "뒤로 가기로 메뉴 닫기")
	key.keycode = KEY_SPACE
	get_viewport().push_input(key)
	check(main.menu.opened and not b.is_processing(), "Space로 직접 일시정지")
	main.menu.close()
	# 완료 직후 저장과 보상 중복 방어.
	b.sim.done = true
	b.sim.wiped = true
	var gold := Run.gold
	b._settle()
	check(Run.gold == gold + Balance.clear_bonus(Run.wave, true), "완료 보상 지급")
	check(Save.cur_run["phase"] == Run.Phase.SHOP, "결과 화면 진입 즉시 상점 체크포인트 저장")
	gold = Run.gold
	b._settle()
	check(Run.gold == gold and Run.settle_wave(true) == 0, "보상 중복 지급 방어")
	b.end_t = 20.0
	b._process(0.1)
	check(not b._leaving, "결과 화면은 직접 넘길 때까지 유지")
	var checkpoint := Save.cur_run.duplicate(true)
	Run.gold = 0
	check(Run.restore(checkpoint) and Run.gold == gold and Run.phase == Run.Phase.SHOP, "완료 전투를 다시 하지 않고 보상부터 이어하기")
	# 패배는 클리어 보너스를 주지 않는다.
	_fresh()
	Run.confirm_hand()
	Run.phase = Run.Phase.BATTLE
	Run.end_run(false)
	gold = Run.gold
	check(Run.settle_wave(false) == 0 and Run.gold == gold, "패배 보너스 금지")
	# 마지막 탄은 결과를 읽기 전에 승리를 기록한다.
	_fresh()
	Run.confirm_hand()
	Run.wave = Balance.LAST_WAVE
	Run.phase = Run.Phase.BATTLE
	var clears := Save.clears
	Run.settle_wave(true)
	check(Run.phase == Run.Phase.WIN and Save.clears == clears + 1 and not Save.has_run(), "마지막 탄 승리 즉시 확정")
	main.queue_free()
	await frames(2)
