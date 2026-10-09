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


## 저장된 별 자리의 한 칸을 갈아 끼운다.
## ★ 형이 없는 배열로 옮겨서 넣는다 — 정수 배열에는 「정수가 아닌 칸」을 넣어 볼 수가 없고,
##   파일에서 돌아오는 손상된 값은 형을 지켜 주지 않는다.
func _with_star(d: Dictionary, ring: int, pos: Variant) -> Dictionary:
	var out := d.duplicate(true)
	var loose: Array = []
	loose.assign(out["rite"]["orbit"])
	loose[ring] = pos
	out["rite"]["orbit"] = loose
	return out


func _test_restore() -> void:
	Run.start_run(9092026)
	Save._flush()
	check(Save.cur_run.is_empty(), "첫 테마 소개 중 종료해도 잘못된 0탄을 저장하지 않음")
	Run.begin_draw()
	# 별 둘이 문 안에 선 의식에서 무료로 한 번, 골드를 내고 한 번 다시 돌린 판 —
	# 별 자리 · 돌린 횟수 · 유료 횟수가 다 담긴다.
	Fixture.stack(2)
	check(Run.respin() == [2, 3, 4], "의식에서 문 밖의 별만 다시 돌림")
	Run.orbit.assign(Fixture.orbit_for(2))
	Run.gold = Balance.reroll_cost(0) + 7
	check(Run.respins_left() == 0 and not Run.respin().is_empty() and Run.paid_spins == 1 and Run.gold == 7,
			"무료를 다 쓴 뒤의 유료 다시 돌리기")
	Run.orbit.assign(Fixture.orbit_for(2))
	var good := Run.snapshot().duplicate(true)
	Run.start_run(4)
	check(Run.restore(good), "유효한 DRAW 저장 복구")
	check(Run.snapshot() == good and Run.spins == 2 and Run.paid_spins == 1 and Run.respins_left() == 0
			and Run.respin_cost() == Balance.reroll_cost(1) and Run.gold == 7 and Run.orbit == Fixture.orbit_for(2),
			"별 자리 · 돌린 횟수 · 유료 횟수 · 오른 값이 저장을 거쳐 그대로 복구")
	for key in ["rite", "themes", "heroes", "bench", "passives", "owned_passives", "hero_damage", "offer", "levels", "last", "rng"]:
		var bad := good.duplicate(true)
		bad[key] = "손상"
		_reject(bad, key + " 형")
	for pair in [["wave", Balance.LAST_WAVE + 1], ["wave", 0], ["phase", 99], ["phase", 5], ["lives", Balance.MAX_LIVES + 1],
			["best_tier", Balance.TIER_MAX + 1], ["best_tier", -2], ["best_tier", "5"],
			["v", Run.SAVE_VERSION - 1], ["v", Run.SAVE_VERSION + 1], ["rules_v", 2], ["rules_v", 0]]:
		var bad := good.duplicate(true)
		bad[pair[0]] = pair[1]
		_reject(bad, str(pair))
	# --- 별맞춤 의식의 상태(rite) ---
	var bad := good.duplicate(true)
	bad.erase("rite")
	_reject(bad, "의식 상태 누락")
	bad = good.duplicate(true)
	bad.erase("rules_v")
	_reject(bad, "규칙 표식 누락")
	bad = good.duplicate(true)
	bad["rite"] = {}
	_reject(bad, "빈 의식 상태")
	for key in ["orbit", "spins", "paid"]:
		bad = good.duplicate(true)
		bad["rite"].erase(key)
		_reject(bad, "의식 %s 누락" % key)
		bad = good.duplicate(true)
		bad["rite"][key] = "손상"
		_reject(bad, "의식 %s 형" % key)
	for key in ["spins", "paid"]:
		bad = good.duplicate(true)
		bad["rite"][key] = -1
		_reject(bad, "의식 %s 음수" % key)
		bad = good.duplicate(true)
		bad["rite"][key] = 1.0
		_reject(bad, "의식 %s 실수" % key)
	bad = good.duplicate(true)
	bad["rite"]["paid"] = int(bad["rite"]["spins"]) + 1
	_reject(bad, "유료 횟수가 돌린 횟수보다 많음")
	# 별 자리: 다섯 개여야 하고, 칸 번호는 궤도 안이어야 하고, 붙들린 별은 문 밖에 설 수 없다.
	for stars in [[], [0, 0, 0, 0], [0, 0, 0, 0, 0, 0]]:
		bad = good.duplicate(true)
		bad["rite"]["orbit"] = stars
		_reject(bad, "별이 %d개" % (stars as Array).size())
	for ring in range(Rite.RINGS):
		for pos in [-1, Rite.slots(), 0.5, "0", null]:
			_reject(_with_star(good, ring, pos), "%d번 궤도의 칸 %s" % [ring, str(pos)])
	for ring in range(Rite.RINGS):
		if not Rite.anchored(ring) or Rite.gate(ring) >= Rite.slots():
			continue
		for pos in [Rite.gate(ring), Rite.slots() - 1]:
			_reject(_with_star(good, ring, pos), "붙들린 %d번 별이 문 밖(%d칸)" % [ring, pos])
	# 문의 두 끝 칸은 쓸 수 있는 자리다 — 거절이 너무 넓으면 멀쩡한 판을 못 잇는다.
	for ring in range(Rite.RINGS):
		var edges: Array = [0, Rite.gate(ring) - 1]
		if not Rite.anchored(ring):
			edges.append(Rite.gate(ring))
			edges.append(Rite.slots() - 1)
		for pos in edges:
			check(Run.restore(_with_star(good, ring, pos)) and Run.orbit[ring] == pos,
					"경계 칸 저장 복구: %d번 %d칸" % [ring, pos])
	check(Run.restore(good), "유효한 DRAW 저장 재복구")
	# 포커 시절의 열쇠가 섞여 있어도 의식 상태가 없으면 이어하지 않는다.
	bad = good.duplicate(true)
	bad.erase("rite")
	bad["cards"] = [0, 1, 2, 3, 4]
	bad["rerolled"] = [0, 0, 0, 0, 0]
	bad["paid"] = [0, 0, 0, 0, 0]
	_reject(bad, "포커 시절의 손패 저장")
	bad = good.duplicate(true)
	bad["themes"][0] = Roster.THEMES.size()
	_reject(bad, "테마 범위")
	bad = good.duplicate(true)
	bad["levels"]["crit"] = 999
	_reject(bad, "강화 상한")
	bad = good.duplicate(true)
	bad["passives"] = ["deal", "deal"]
	_reject(bad, "패시브 중복")
	var result := Run.confirm_summon().duplicate(true)
	good = Run.snapshot().duplicate(true)
	Run.start_run(55)
	check(Run.restore(good), "편성 저장 복구")
	check(Run.last_tier == result["tier"] and Run.last_result["stars"] == result["stars"]
			and Run.last_result["orbit"] == result["orbit"] and Run.last_unit == result["unit"]
			and Run.orbit == result["orbit"], "확정 결과 복구")
	var count := Run.hero_total()
	Run.gold = 100000
	check(not Run.can_respin() and Run.respin().is_empty() and Run.gold == 100000, "확정 후 다시 돌리기 금지")
	check(Run.confirm_summon() == Run.last_result and Run.hero_total() == count, "편성 중 중복 확정 금지")
	Run.phase = Run.Phase.BATTLE
	check(Run.confirm_summon().is_empty() and Run.respin().is_empty(), "전투 중 영웅 추가 금지")
	Run.phase = Run.Phase.SHOP
	check(Run.confirm_summon().is_empty() and Run.respin().is_empty(), "상점 중 영웅 추가 금지")
	check(Run.hero_total() == count, "단계 밖 확정은 영웅을 주지 않음")
	check(Run.best_tier == result["tier"], "이번 판 최고 등급 복구")
	# 확정 결과(last)의 꼴 — 등급 · 별 수 · 별 자리 · 조커가 끌어온 궤도.
	for pair in [["tier", Balance.TIER_MAX + 1], ["tier", -1], ["tier", "3"], ["stars", 0], ["stars", Rite.MAX_STARS + 1],
			["stars", 2.0], ["orbit", []], ["orbit", "손상"], ["joker", Rite.RINGS], ["joker", -2], ["joker", "1"],
			["unit", "없는_캐릭터"], ["unit", 7], ["slot", "0"]]:
		bad = good.duplicate(true)
		bad["last"][pair[0]] = pair[1]
		_reject(bad, "확정 결과 " + str(pair))
	for key in ["tier", "stars", "orbit", "unit"]:
		bad = good.duplicate(true)
		bad["last"].erase(key)
		_reject(bad, "확정 결과 %s 누락" % key)


func _test_transactions() -> void:
	_fresh()
	Run.confirm_summon()
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
	Run.confirm_summon()
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
	# 도감 — 등급별 뽑은 횟수와, 캐릭터마다 여태 얻은 가장 높은 등급.
	var first_unit := String(Roster.UNITS[0]["id"])
	var low := Rite.tier_of(Rite.MIN_STARS)
	var high := Rite.tier_of(Rite.MAX_STARS - 1)
	store.best_tier = -1
	store.seen_tiers = {}
	store.seen_units = {}
	store.unit_best = {}
	store.record_summon(high, first_unit, false)
	store.record_summon(low, first_unit, false)
	check(store.best_of(first_unit) == high and store.best_tier == high and int(store.seen_tiers[high]) == 1
			and int(store.seen_tiers[low]) == 1 and store.seen_units.has(first_unit), "도감은 캐릭터별 최고 등급을 낮추지 않음")
	store.note_unit(first_unit, Balance.TIER_MAX + 5)
	store.note_unit("", Balance.TIER_MAX)
	check(store.best_of(first_unit) == Balance.TIER_MAX and not store.unit_best.has("") and store.best_tier == high,
			"도감 등급은 등급 표 안으로 제한하고 뽑기 기록과 섞지 않음")
	check(store.best_of("없는_캐릭터") == -1, "기록 없는 캐릭터의 최고 등급은 -1")
	check(store.save_file(), "도감 저장")
	var reopened = load("res://core/save.gd").new()
	reopened.storage_path = path
	reopened.load_file()
	check(not reopened.recovered_backup and reopened.best_of(first_unit) == Balance.TIER_MAX and reopened.best_tier == high
			and reopened.seen_tiers == store.seen_tiers and reopened.seen_units.has(first_unit), "도감과 최고 등급 저장/복구")
	# 포커 시절에 쓴 파일(열쇠 best_hand · hands · card_mode, 등급 도감 없음)도 평생 기록은 그대로 읽는다.
	# 하던 판만 버린다 — 카드 다섯 장과 문장 값이 지금 규칙에 없다.
	var old := ConfigFile.new()
	old.set_value("run", "best_wave", 77)
	old.set_value("run", "runs", 9)
	old.set_value("run", "clears", 1)
	old.set_value("run", "total_kills", 1234)
	old.set_value("run", "best_hand", 6)
	old.set_value("book", "units", {first_unit: true})
	old.set_value("book", "hands", {0: 5, 6: 1})
	old.set_value("cur", "state", {"v": Run.SAVE_VERSION - 1, "rules_v": 2, "wave": 40, "phase": Run.Phase.DRAW,
			"cards": [0, 1, 2, 3, 4], "rerolled": [1, 0, 0, 0, 0], "paid": [0, 0, 0, 0, 0]})
	old.set_value("opt", "card_mode", "poker")
	old.set_value("opt", "language", "en")
	old.save(path)
	reopened.load_file()
	check(not reopened.recovered_backup and reopened.best_wave == 77 and reopened.runs == 9 and reopened.clears == 1
			and reopened.total_kills == 1234 and reopened.language == "en", "포커 시절 파일의 평생 기록과 설정 보존")
	check(reopened.best_tier == 6 and reopened.seen_tiers == {0: 5, 6: 1} and reopened.seen_units.has(first_unit),
			"옛 최고 족보 번호와 도감은 같은 0~9 칸으로 이어짐")
	check(reopened.cur_run.is_empty() and not reopened.has_run() and reopened.run_wave() == 0, "포커 시절에 하던 판은 이어하지 않음")
	check(reopened.best_of(first_unit) == -1, "포커 시절에 만난 캐릭터는 등급 기록이 없음")
	# 등급 도감이 딕셔너리가 아니면 손상된 파일이다 — 백업으로 물러난다.
	old.set_value("book", "best", "손상")
	old.save(path)
	reopened.load_file()
	check(reopened.recovered_backup, "손상된 등급 도감은 정상 기록으로 취급하지 않음")
	reopened.free()
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
	Run.confirm_summon()
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
	Run.confirm_summon()
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
	# 메뉴의 쪽을 전부 그려 본다. 쪽 이름을 못 박지 않는다 — 그려진 탭(page:*)을 그대로 따라간다.
	var pages: Array = []
	for zone in main.menu.ui.zones:
		if String(zone["id"]).begins_with("page:"):
			pages.append(String(zone["id"]).substr(5))
	check(pages.size() >= 3 and pages.has("menu"), "메뉴 탭 등록 (%s)" % str(pages))
	for page in pages + ["menu"]:
		main.menu.page = page
		await frames(2)
	# 카드가 없어졌으므로 「판타지 문장 / 포커 카드」 표현 전환도 없다.
	check(zone_of(main.menu, "cards:sigil").is_empty() and zone_of(main.menu, "cards:poker").is_empty(),
			"메뉴에 카드 표현 전환 단추 없음")
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
	Run.confirm_summon()
	Run.phase = Run.Phase.BATTLE
	Run.end_run(false)
	gold = Run.gold
	check(Run.settle_wave(false) == 0 and Run.gold == gold, "패배 보너스 금지")
	# 마지막 탄은 결과를 읽기 전에 승리를 기록한다.
	_fresh()
	Run.confirm_summon()
	Run.wave = Balance.LAST_WAVE
	Run.phase = Run.Phase.BATTLE
	var clears := Save.clears
	Run.settle_wave(true)
	check(Run.phase == Run.Phase.WIN and Save.clears == clears + 1 and not Save.has_run(), "마지막 탄 승리 즉시 확정")
	main.queue_free()
	await frames(2)
