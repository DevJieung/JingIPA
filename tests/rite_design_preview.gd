extends Harness

## 별맞춤 의식 디자인 미리보기 — 실제 Godot 렌더로 화면을 찍고, 그리면서 계약도 같이 잰다.
##
##     python3 tools/rite_design_review.py            # 1280x800 · 1000x625, 한국어 · 영어
##
## 찍는 것: 타이틀 / 의식판(도는 중 · 1성 · 3성 · 5성 · 문턱에 걸린 별 · 무료 · 유료 · 골드 부족 ·
## 조커 · 도박꾼의 눈) / 다시 돌리기 · 광고 끌어오기의 연속 프레임 / 확정 연출(보통 · 4성 · 5성 ·
## +0.5성 · 조커) / 편성 / 중간 지원 / 메뉴 도움말 / 도감 / 합성 결과 / 옛 부활 보상 / 상점의 무료 횟수.
## 끝으로 **실제 흐름**을 눌러서 지나간다: 타이틀 → 시작 → 테마 판 → 의식 → 다시 돌리기 → 소환 →
## 확정 연출 → 편성 → 전투.
##
## ★ 「보이는 문과 판정이 같은가」는 여기서 **그린 자리로** 잰다: 별이 선 각이 문의 두 끝 선
##   사이에 있는가 ⇔ Rite.in_gate. Balance.RITE_GATE 를 바꿔 돌려도 그대로 통과해야 한다.

var main: Node2D
var output := "build/rite-design/1280x800"
var report: Array = []
const STEP := 1.0 / 60.0


func capture(stem: String, image_: bool = true) -> void:
	Look.text_audit.clear()
	Look.raw_text_audit.clear()
	I18n.observed.clear()
	I18n._cache.clear()
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	if image_:
		await snap(output + "/" + stem + ".png")
	var found := {}
	for row in Look.text_audit:
		if found.has(str(row)):
			continue
		found[str(row)] = true
		var box: Rect2 = row["box"]
		check(float(row["width"]) <= box.size.x + 0.5 and float(row["height"]) <= box.size.y + 0.5,
				stem + ": 글자가 칸 안에 다 들어온다 — " + String(row["text"]))
		var saved: Dictionary = row.duplicate()
		saved["screen"] = stem
		saved["box"] = str(box)
		report.append(saved)


func swap(screen: Node2D) -> void:
	main._swap(screen)
	screen.set_process(false)


## 의식 화면을 세운다. 별 자리를 손으로 깔고, 도는 연출은 넘긴 채로 돌려준다.
func rite(orbit: Array, passives: Array = [], gold: int = 1000, spins: int = 0, paid: int = 0) -> DrawScreen:
	Fixture.fresh(20261007)
	Run.orbit.assign(orbit)
	Run.spins = spins
	Run.paid_spins = paid
	Run.pulls = 0
	Run.gold = gold
	Run.owned_passives.assign(passives)
	Run.passives.assign(passives)
	var draw := DrawScreen.new()
	swap(draw)
	draw.skip_spin()
	roll(draw, 0.8)         # 별이 잠기는 번쩍임이 가신 뒤의 평소 모습을 찍는다
	await paint(draw)       # 단추 자리는 한 번 그려야 등록된다
	return draw


## 화면의 시계를 `seconds` 만큼 굴린다(set_process(false) 인 화면을 손으로 굴린다).
func roll(screen: Node, seconds: float) -> void:
	var left := seconds
	while left > 0.0001:
		screen._process(minf(STEP, left))
		left -= STEP


## 단추 셋의 켜짐이 규칙과 같은가 — 검사기와의 약속을 화면에서 다시 잰다.
func check_actions(draw: DrawScreen, stem: String) -> void:
	check(bool(zone_of(draw, "go").get("on", false)), stem + ": 소환은 의식 내내 켜져 있다")
	check(bool(zone_of(draw, "rite:respin").get("on", false)) == Run.can_respin(), stem + ": 다시 돌리기는 can_respin 일 때만 켜진다")
	check(bool(zone_of(draw, "rite:pull").get("on", false)) == (Run.pull_target() >= 0 and not Ads.busy), stem + ": 끌어오기는 끌어올 별이 있을 때만 켜진다")
	var rects: Array[Rect2] = []
	for id in ["rite:respin", "go", "rite:pull"]:
		var rect: Rect2 = zone_of(draw, id).get("rect", Rect2())
		check(Look.SCREEN.encloses(rect) and rect.size.y >= 64.0, stem + ": 단추가 화면 안이고 손가락이 닿는 크기다 — " + id)
		for other in rects:
			check(not other.intersects(rect), stem + ": 단추끼리 안 겹친다")
		rects.append(rect)


## 보이는 문과 판정이 같은가. 별을 그리는 각이 그 궤도의 문 두 끝 사이에 있는가 ⇔ Rite.in_gate.
func check_gate(stem: String) -> void:
	for ring in range(Rite.RINGS):
		for pos in [0, Rite.gate(ring) - 1, Rite.gate(ring), Rite.slots() - 1, Rite.gate(ring) / 2]:
			if pos < 0 or pos >= Rite.slots():
				continue
			var off := absf(wrapf(Rite.angle(ring, pos) - Rite.GATE_ANGLE, -PI, PI))
			check((off < Rite.gate_half(ring)) == Rite.in_gate(ring, pos),
					"%s: %d번 궤도 %d번 칸 — 그린 자리와 판정이 같다" % [stem, ring, pos])
	check(Rite.valid(RiteBoard.sample_orbit(1)) and Rite.stars(RiteBoard.sample_orbit(3)) == 3
			and Rite.stars(RiteBoard.sample_orbit(5)) == 5, stem + ": 설명용 별 자리가 규칙에 맞는다")


## 문턱에 걸린 별 — 바깥 두 별은 문 바로 밖, 안쪽 두 별은 문 바로 안. 모양으로 갈려야 한다.
func edge_orbit() -> Array:
	return [Rite.gate(0) / 2, Rite.gate(1) - 1, 0, Rite.slots() - 1, Rite.gate(4)]


func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly = true
	Save.cur_run = {}
	output = arg("--out", output)
	DirAccess.make_dir_recursive_absolute(output)
	Ads.set_process(false)
	main = load("res://game/main.gd").new()
	add_child(main)
	Look.text_audit_enabled = true
	I18n.audit_enabled = true
	check_gate("문")
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		await title_and_book(language)
		await pick_states(language)
		await motion(language)
		await reveals(language)
		await support_and_menu(language)
		await legacy(language)
		await real_flow(language)
	check(I18n.missing.is_empty(), "영어 화면에 남은 한글이 없다: " + str(I18n.missing))
	var file := FileAccess.open(output + "/text-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	Look.text_audit_enabled = false
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("별맞춤 의식 디자인 실제 렌더 검수")


func title_and_book(language: String) -> void:
	Run.running = false
	Save.cur_run = {}
	Save.best_wave = 37
	Save.best_tier = 8
	Save.seen_units.clear()
	Save.unit_best.clear()
	swap(TitleScreen.new())
	await capture(language + "_title")
	# 도감 — 같은 캐릭터가 얻은 만큼의 별로 선다. 기록이 없는 캐릭터는 별 없이 「발견」만.
	var grades := [1, 3, 5, 7, 9, 2, 4, 6, 8, 0]
	for i in range(Roster.UNITS.size()):
		var unit: Dictionary = Roster.UNITS[i]
		if i % 7 == 6:
			continue
		Save.seen_units[String(unit["id"])] = true
		if i % 9 != 8:
			Save.unit_best[String(unit["id"])] = grades[i % grades.size()]
	Save.seen_units["awakened_fire_7"] = true
	Save.unit_best["awakened_fire_7"] = 8
	var title: TitleScreen = main.screen
	check(tap(title, "collection"), "타이틀에서 도감이 열린다")
	for element in CollectionView.ELEMENTS:
		title.collection.element = element
		await capture(language + "_book_" + element)
		for unit in title.collection.heroes():
			check(CollectionView.best_tier(unit) == Save.best_of(String(unit["id"])), "도감의 별은 얻은 최고 등급이다")
	title.collection.fusion_only = true
	title.collection.element = "fire"
	await capture(language + "_book_fusion_found")
	check(CollectionView.best_tier(title.collection.heroes()[0]) == 8, "수호자는 승급한 최고 등급으로 선다")
	title.collection.element = "water"
	await capture(language + "_book_fusion_locked")
	title.collection.close()
	title.collection.fusion_only = false
	Fixture.prepare(6, 20261007)
	Run.begin_draw()
	Save.store_run(Run.snapshot())
	swap(TitleScreen.new())
	await capture(language + "_title_continue")
	Save.cur_run = {}


func pick_states(language: String) -> void:
	var free := Run.free_rerolls()
	var states := [
		["rite_1star", RiteBoard.sample_orbit(1), [], 1000, 0, 0],
		["rite_2star", RiteBoard.sample_orbit(2), [], 1000, 0, 0],
		["rite_3star", RiteBoard.sample_orbit(3), [], 1000, 0, 0],
		["rite_4star", RiteBoard.sample_orbit(4), [], 1000, 0, 0],
		["rite_5star", RiteBoard.sample_orbit(5), [], 1000, 0, 0],
		["rite_edges", edge_orbit(), [], 1000, 0, 0],
		["rite_paid", RiteBoard.sample_orbit(2), [], 1000, 1, 0],
		["rite_paid_again", RiteBoard.sample_orbit(2), [], 123456, 3, 2],
		["rite_no_gold", RiteBoard.sample_orbit(2), [], 0, 1, 0],
		["rite_joker", RiteBoard.sample_orbit(3), ["joker"], 1000, 0, 0],
		["rite_eye", RiteBoard.sample_orbit(3), ["eye"], 1000, 0, 0],
		["rite_all_passives", RiteBoard.sample_orbit(2), ["joker", "eye", "deal"], 1000, 0, 0],
	]
	for state in states:
		var stem := language + "_" + String(state[0])
		var draw: DrawScreen = await rite(state[1], state[2], int(state[3]), int(state[4]), int(state[5]))
		await capture(stem)
		check_actions(draw, stem)
		check(draw._shown_stars() == Rite.stars(Run.orbit), stem + ": 화면이 센 별과 규칙이 센 별이 같다")
	# 숫자가 규칙과 같은가 — 무료 횟수 · 유료 값 · 조커 미리보기.
	var free_draw: DrawScreen = await rite(RiteBoard.sample_orbit(2))
	await capture(language + "_rite_free", false)
	check(I18n.observed.has("무료 %d" % free), "단추에서 남은 무료 횟수를 읽는다")
	await rite(RiteBoard.sample_orbit(2), [], 1000, free, 0)
	await capture(language + "_rite_cost", false)
	check(I18n.observed.has("%d G" % Balance.reroll_cost(0)), "무료를 다 쓰면 단추에서 골드 값을 읽는다")
	var joker_draw: DrawScreen = await rite(RiteBoard.sample_orbit(3), ["joker"])
	await capture(language + "_rite_joker_label", false)
	check(int(Run.rite_preview()["stars"]) == 4 and I18n.observed.has("%s 소환" % Look.star_label(Rite.tier_of(4))),
			"조커가 끌어올 별까지 센 등급을 소환 단추가 말한다")
	check(free_draw != joker_draw, "화면은 상태마다 새로 선다")


func motion(language: String) -> void:
	# 1) 들어올 때 — 별이 돌다가 안쪽부터 멈춘다. 멈춘 별만 센다.
	Fixture.fresh(20261007)
	Run.orbit.assign(RiteBoard.sample_orbit(3))
	var draw := DrawScreen.new()
	swap(draw)
	await paint(draw)
	check(draw._spinning() and draw._shown_stars() == 0, "들어오면 별 다섯이 돈다")
	check_actions(draw, language + "_spin")
	var last := 0
	for frame in range(10):
		roll(draw, 0.19)
		await capture("%s_spin_%02d" % [language, frame])
		check(draw._shown_stars() >= last, "도는 동안 문 안의 별 수는 줄지 않는다")
		last = draw._shown_stars()
	check(not draw._spinning() and last == 3, "다 멈추면 문 안의 별이 규칙과 같다")
	# 2) 다시 돌리기 — 문 밖의 별만 돈다. 문 안의 별은 제자리에 잠겨 있다.
	var before: Array = Run.orbit.duplicate()
	var misses := Rite.misses(Run.orbit)
	check(tap(draw, "rite:respin"), "다시 돌리기가 눌린다")
	for ring in range(Rite.RINGS):
		check((not draw._move[ring].is_empty()) == misses.has(ring), "%d번 궤도 — 문 밖의 별만 돈다" % ring)
		if not misses.has(ring):
			check(int(Run.orbit[ring]) == int(before[ring]), "문 안의 별은 자리를 지킨다")
	for frame in range(7):
		roll(draw, 0.19)
		await capture("%s_respin_%02d" % [language, frame])
	check(not draw._spinning(), "다시 돈 별도 1.5초 안에 다 선다")
	# 3) 도는 중에 누르면 — 연출을 넘기고 바로 처리한다.
	draw = await rite(RiteBoard.sample_orbit(2))
	draw._spin(draw._all_rings(), [])
	mouse(draw, Vector2(640, 400), true)
	check(not draw._spinning(), "빈 자리를 누르면 도는 별이 선다")
	draw._spin(draw._all_rings(), [])
	await paint(draw)
	check(tap(draw, "go") and draw.state == DrawScreen.REVEAL, "도는 중에도 소환이 바로 듣는다")
	# 4) 광고로 끌어오기 — 보상은 Run 이 적용하고, 화면은 그 별이 끌려오는 모습을 보여 준다.
	draw = await rite(RiteBoard.sample_orbit(2))
	var ring := Run.pull_target()
	draw._pull_ring = ring
	draw._pull_from = int(Run.orbit[ring])
	check(Run.apply_ad_reward("card", {"slot": ring}), "광고 보상이 별을 문 안으로 옮긴다")
	draw._ad_completed("card", true)
	check(draw._shown_stars() == 2, "끌려오기 전에는 아직 문 밖으로 그린다")
	for frame in range(6):
		roll(draw, 0.15)
		await capture("%s_pull_%02d" % [language, frame])
	check(draw._shown_stars() == 3 and not draw._spinning(), "끌려온 별이 문 안에 잠긴다")
	check_actions(draw, language + "_pull")


func reveals(language: String) -> void:
	var cases := [
		["reveal_2star", 2, [], "pip", false],
		["reveal_3star", 3, [], "thalassa", false],
		["reveal_4star", 4, [], "morrigan", false],
		["reveal_5star", 5, [], "sigrid", false],
		["reveal_bumped", 3, ["eye"], "rhiannon", true],
		["reveal_joker", 3, ["joker"], "brasa", false],
	]
	for case in cases:
		var stem := language + "_" + String(case[0])
		var draw: DrawScreen = await rite(RiteBoard.sample_orbit(int(case[1])), case[2])
		var heroes := Run.hero_total()
		check(tap(draw, "go") and draw.state == DrawScreen.REVEAL, stem + ": 소환을 누르면 확정 연출이 열린다")
		check(Run.hero_total() == heroes + 1, stem + ": 영웅은 한 명만 온다")
		draw.result = draw.result.duplicate(true)
		draw.result["unit"] = Roster.unit_by_id(String(case[3]))
		if bool(case[4]) and not bool(draw.result.get("bumped", false)):
			# 도박꾼의 눈은 확률이라, 화면이 그리는 모습을 보려고 결과만 손으로 얹는다.
			draw.result["bumped"] = true
			draw.result["tier"] = int(draw.result["tier"]) + 1
		elif not bool(case[4]) and bool(draw.result.get("bumped", false)):
			draw.result["bumped"] = false
			draw.result["tier"] = int(draw.result["tier"]) - 1
		draw.showy = int(draw.result["tier"]) >= Balance.SHOWY_TIER
		var at := draw._burst_at()
		for moment in [0.2, 0.55, at - 0.2]:
			roll(draw, float(moment) - draw.rt)
			await capture("%s_gather_%03d" % [stem, int(float(moment) * 100.0)])
		for moment in [at + 0.06, at + 0.3, at + 0.75, at + 1.6]:
			roll(draw, float(moment) - draw.rt)
			await capture("%s_burst_%03d" % [stem, int((float(moment) - at) * 100.0)])
		check(I18n.observed.has(Look.star_label(int(draw.result["tier"]))), stem + ": 마지막에 최종 등급을 적는다")
		mouse(draw, Vector2(640, 760), true)
		check(draw.state == DrawScreen.SWAP and Run.hero_total() == heroes + 1, stem + ": 터치하면 편성 판으로 간다")
		if String(case[0]) == "reveal_3star":
			await capture(language + "_formation")
			check(bool(zone_of(draw, "tobattle").get("on", false)), "편성 판에서 전투를 시작할 수 있다")
	# 4성과 5성은 터지는 양으로도 갈린다.
	var four := DrawScreen.new()
	four.result = {"tier": 7}
	four.showy = true
	four.rt = 2.6
	four._reveal_beats()
	var five := DrawScreen.new()
	five.result = {"tier": 9}
	five.showy = true
	five.rt = 2.6
	five._reveal_beats()
	check(five.fx.items.size() > four.fx.items.size() + 100, "5성은 4성보다 한 겹 더 터진다")
	four.free()
	five.free()


func support_and_menu(language: String) -> void:
	Fixture.fresh(20261007, 12)
	Run.wave = 12
	Run.phase = Run.Phase.BATTLE
	var battle := BattleScreen.new()
	swap(battle)
	battle.sim.support_pending = true
	Run.support_available = true
	battle.support_age = 3
	await capture(language + "_support_choices")
	check(tap(battle, "support:summon"), "중간 지원의 무료 소환이 눌린다")
	battle.support_age = 1
	await capture(language + "_support_summoned")
	var got: Dictionary = battle.support_result
	check(Rite.valid(got.get("orbit", [])) and Rite.stars(got["orbit"]) == int(got["stars"]),
			"지원 소환은 별이 선 자리와 별 수를 함께 준다")
	check(tap(battle, "support:continue"), "지원 결과를 확인하고 이어 간다")
	Fixture.fresh(20261008, 12)
	Run.wave = 12
	Run.phase = Run.Phase.BATTLE
	battle = BattleScreen.new()
	swap(battle)
	battle.sim.support_pending = true
	Run.support_available = true
	battle.support_age = 3
	await paint(battle)
	check(tap(battle, "support:hero:3") and tap(battle, "support:promote"), "중간 지원의 승급이 눌린다")
	battle.support_age = 1
	await capture(language + "_support_promoted")
	check(tap(battle, "support:continue"), "승급 결과를 확인하고 이어 간다")
	# 메뉴 — 별맞춤 도움말의 숫자는 전부 규칙에서 온다.
	var draw: DrawScreen = await rite(RiteBoard.sample_orbit(3))
	main.menu.open()
	for page in ["menu", "rules", "rite", "elements"]:
		main.menu.page = page
		await capture(language + "_menu_" + page)
	main.menu.page = "rite"
	await capture(language + "_menu_rite_values", false)
	var chances: PackedStringArray = []
	for ring in range(Rite.RINGS):
		chances.append("항상" if Rite.anchored(ring) else RiteBoard.percent(Rite.chance(ring)))
	check(I18n.observed.has("별이 문에 들 확률(안쪽 별부터)  %s" % " · ".join(chances)), "도움말의 문 확률은 규칙의 값이다")
	check(I18n.observed.has(RiteBoard.percent(Rite.odds(1)[2])), "도움말의 등급 분포는 Rite.odds 의 값이다")
	check(zone_of(main.menu, "cards:poker").is_empty() and zone_of(main.menu, "cards:sigil").is_empty(), "카드 표현 전환은 없어졌다")
	check(tap(main.menu, "page:rite") and main.menu.page == "rite", "별맞춤 도움말 탭이 눌린다")
	main.menu.close()
	check(draw.state == DrawScreen.PICK, "메뉴를 닫으면 의식으로 돌아온다")


func legacy(language: String) -> void:
	# 합성 결과 — 숫자 문장은 없고, 각성 수호자의 금색 표식만 남는다.
	Fixture.fresh(20261007)
	Run.phase = Run.Phase.SWAP
	Run.heroes.clear()
	Run.bench.clear()
	for tier in [1, 3, 3, 5, 7]:
		Run.bench.append({"unit": Roster.UNITS[tier * 3], "tier": tier, "wave": 1, "n": 1})
	Run.last_result = {"unit": Roster.UNITS[3], "tier": 1, "stars": 1, "orbit": RiteBoard.sample_orbit(1), "where": "bench", "slot": 0}
	var draw := DrawScreen.new()
	swap(draw)
	draw.fusion.opened = true
	draw.fusion.selected.assign(Run.fusion_candidates())
	await capture(language + "_fusion_materials")
	check(tap(draw, "fusion:go"), "합성이 실제 화면에서 시작된다")
	draw.fusion.reveal_age = 3
	await capture(language + "_fusion_result")
	check(tap(draw, "fusion:accept"), "합성 결과를 받는다")
	draw.fusion.opened = false
	# 옛 저장의 영웅 부활 보상 — 등급은 별로 적는다(족보 이름이 아니다).
	var unit := Roster.unit_by_id("sigrid")
	Run.bench.append({"unit": unit, "tier": Balance.TIER_MAX, "wave": Run.wave, "n": 1})
	Run.last_result = {"unit": unit, "tier": Balance.TIER_MAX, "orbit": [], "where": "bench",
		"slot": Run.bench.size() - 1, "revived": true, "reward_pending": true}
	draw = DrawScreen.new()
	swap(draw)
	draw.revive_reward.age = 3
	await capture(language + "_revive_hero")
	check(draw.state == DrawScreen.REVIVE_REWARD and I18n.observed.has("최고 등급 · %s" % Look.star_label(Balance.TIER_MAX)),
			"옛 부활 보상도 등급을 별로 적는다")


## 실제 흐름 — 화면을 손으로 세우지 않고, 타이틀에서부터 **눌러서** 전투까지 간다.
## 화면은 제 시계로 돈다(set_process 를 끄지 않는다) — 별이 정말 제시간에 서는지도 여기서 잰다.
func real_flow(language: String) -> void:
	Run.running = false
	Save.cur_run = {}
	main.show_title()
	await paint(main.screen)
	check(tap(main.screen, "start"), "흐름: 타이틀의 시작이 눌린다")
	check(await wait_screen(main, "theme_screen", 900), "흐름: 첫 탄 앞에 테마 판이 뜬다")
	await get_tree().create_timer(0.8).timeout
	mouse(main.screen, Vector2(640, 400), true)
	check(await wait_screen(main, "draw_screen", 900), "흐름: 테마 판 뒤에 의식 화면이 뜬다")
	var draw: DrawScreen = main.screen
	await paint(draw)
	check(draw.state == DrawScreen.PICK and Rite.valid(Run.orbit) and draw._spinning(), "흐름: 의식이 열리고 별이 돈다")
	check(Run.rite_stars() >= Balance.RITE_FIRST_STARS, "흐름: 첫 의식은 별 %d개 이상으로 열린다" % Balance.RITE_FIRST_STARS)
	var started := Time.get_ticks_msec()
	while draw._spinning() and Time.get_ticks_msec() - started < 4000:
		await get_tree().process_frame
	check(not draw._spinning() and draw.t < 2.2, "흐름: 별 다섯이 2초 안에 다 선다 (%.2f초)" % draw.t)
	check(draw._shown_stars() == Run.rite_stars(), "흐름: 화면이 센 별이 규칙과 같다")
	await paint(draw)
	await snap(output + "/" + language + "_flow_rite.png")
	var free := Run.respins_left()
	var gold := Run.gold
	var locked := Rite.stars(Run.orbit)
	if Run.can_respin():
		check(press(draw, "rite:respin"), "흐름: 다시 돌리기가 눌린다")
		check(Run.respins_left() == free - 1 and Run.gold == gold, "흐름: 무료 횟수 하나를 쓰고 골드는 그대로다")
		check(Rite.stars(Run.orbit) >= locked, "흐름: 다시 돌려서 별이 줄지 않는다")
		started = Time.get_ticks_msec()
		while draw._spinning() and Time.get_ticks_msec() - started < 4000:
			await get_tree().process_frame
		check(not draw._spinning(), "흐름: 다시 돈 별도 선다")
		await paint(draw)
	var heroes := Run.hero_total()
	var stars := int(Run.rite_preview()["stars"])
	check(press(draw, "go"), "흐름: 소환이 눌린다")
	check(draw.state == DrawScreen.REVEAL and Run.hero_total() == heroes + 1, "흐름: 영웅 한 명이 오고 확정 연출이 열린다")
	check(int(draw.result.get("stars", 0)) == stars, "흐름: 미리 본 별 수 그대로 소환된다")
	press(draw, "go")
	press(draw, "rite:respin")
	check(draw.state == DrawScreen.REVEAL and Run.hero_total() == heroes + 1, "흐름: 연출 중에 또 눌러도 영웅은 늘지 않는다")
	started = Time.get_ticks_msec()
	while draw.rt < draw._burst_at() + 0.9 and Time.get_ticks_msec() - started < 6000:
		await get_tree().process_frame
	await snap(output + "/" + language + "_flow_reveal.png")
	mouse(draw, Vector2(640, 760), true)
	check(draw.state == DrawScreen.SWAP, "흐름: 터치하면 편성 판이 뜬다")
	await paint(draw)
	check(press(draw, "tobattle"), "흐름: 전투 시작이 눌린다")
	check(await wait_screen(main, "battle_screen", 900), "흐름: 전투로 들어간다")
	await get_tree().create_timer(0.6).timeout
	check(main.screen is BattleScreen and main.screen.sim.heroes.size() == heroes + 1, "흐름: 뽑은 영웅이 전장에 선다")
	await snap(output + "/" + language + "_flow_battle.png")
	# 상점 — 무료 다시 돌리기 횟수는 활성 패시브(큰손)까지 더한 실제 값이다.
	Fixture.fresh(20261007)
	Run.owned_passives.assign(["deal"])
	Run.passives.assign(["deal"])
	Run.gold = 5000
	Run.phase = Run.Phase.SHOP
	Run.roll_shop()
	var shop := ShopScreen.new()
	swap(shop)
	await capture(language + "_shop_free_respins")
	check(I18n.observed.has("무료 다시 돌리기") and I18n.observed.has("%d번" % Run.free_rerolls()),
			"상점이 무료 다시 돌리기 횟수를 실제 값으로 적는다")
