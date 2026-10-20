extends Harness

## The arena through its real screen: taps on the zones the views register (CLAUDE.md 7). The
## first half runs held still (set_process(false): every entrance settled, every button armed);
## _check_live then runs the screen's own clock by hand (Engine.time_scale 0, _process(1/60)
## frames) for the input locks — the level-up popup (F1), the map (F2), the jewel box (F11),
## the preparation's 「바로 시작」 and the starburst's aim (F6) — and _check_results ends a stage
## both ways through its result card.

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
	check(Arena.modal == "stage" and Arena.stage == 1 and Arena.theme_index == Arena.ladder_theme(1), "새 판은 사다리 STAGE 1 의 전장 카드로 시작 (전장 선택 없음)")
	var has_choice := false
	for zone in screen.ui.zones:
		if String(zone["id"]).begins_with("theme:"): has_choice = true
	check(not has_choice and tap(screen, "stage:start") and Arena.modal == "box", "전장 카드 확인 버튼 → 무료 첫 보석상자")
	await _box_pick_and_close(screen, "첫 상자")
	check(Arena.heroes.size() == 1, "첫 상자에서 영웅 고르기·전투 진입")
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
	# The rail's constellations open the map (the viewer); its own button closes it.
	check(tap(screen, "talents") and Arena.modal == "talent" and Arena.talent_offer.is_empty() and screen.talent_map, "별자리 열람 버튼 → 지도")
	await paint(screen)
	check(tap(screen, "close") and Arena.modal == "" and not screen.talent_map, "별자리 열람 닫기 버튼")
	# Growth comes from experience: force a level and pick one of the three stars on screen.
	Arena.pending_levels = 1
	Arena.level = 1
	check(Arena.offer_levelup() and Arena.modal == "talent" and Arena.talent_offer.size() == Balance.ARENA_TALENT_CHOICES, "레벨업 팝업이 셋을 제시")
	screen._process(0.05)
	await paint(screen)
	var pick := String(Arena.talent_offer[0])
	var pick_zone := zone_of(screen, "talent:pick:" + pick)
	check(not pick_zone.is_empty(), "팝업의 선택 버튼이 화면에 있음")
	# Where the first card's button sits: _check_live taps there before the popup arms.
	var first_button: Rect2 = pick_zone.get("rect", Rect2())
	check(tap(screen, "talent:pick:" + pick) and Arena.talent_count(pick) == 1 and Arena.modal == "", "별자리 노드 선택 버튼으로 전투 복귀")
	# Skills wait for a wave and cost gold (2026-10-19): open wave 1 now, spawns held.
	Arena.sim.begin_wave(1)
	Arena.sim._spawn_t = 1.0e9
	await paint(screen)
	check(tap(screen, "skill:ward") and Arena.sim.shield > 0, "공통 스킬 버튼")
	check(tap(screen, "speed:2") and is_equal_approx(screen.speed, 2.0), "상단 배속 버튼 2배속")
	var before_speed: float = Arena.sim.elapsed
	screen._process(0.1)
	check(Arena.sim.elapsed > before_speed + 0.15, "2배속이 실제 시뮬 시간을 두 배로 돌림")
	check(tap(screen, "speed:1") and is_equal_approx(screen.speed, 1.0), "상단 배속 버튼 1배속 복귀")
	# The stage boss comes with the last wave; its fall wins the stage and unlocks the next one. The
	# result card's 「다음 STAGE」 opens it on a fresh screen with its own battlefield.
	var first_field: String = screen.view_3d.world.theme_id
	var first_layout := ArenaGeometry.layout()
	Arena.sim.jump_to_boss()
	screen._process(0.05)
	for mo in Arena.sim.monsters:
		if String(mo["kind"]) == "boss": mo["hp"] = 0.0
	Arena.sim._cache_positions()
	Arena.sim._reap()
	check(Arena.sim.clear_t > 0.0, "스테이지 보스 처치 뒤 돌파 연출")
	for i in range(roundi((Balance.ARENA_CLEAR_DELAY + 0.3) * 30)): screen._process(1.0 / 30.0)
	await paint(screen)
	check(not Arena.running and Arena.modal == "result" and Arena.sim.won and Save.stage_unlocked == 2, "연출 뒤 스테이지 승리·다음 스테이지 해금")
	check(screen.can_next_stage(), "승리 결과: 다음 STAGE 가 열려 있음")
	var won_screen := screen
	check(_press_or_act(screen, "result:next"), "결과의 「다음 STAGE」")
	screen = await _next_screen(main, won_screen)
	check(screen != null, "다음 STAGE 는 새 전장 화면에서")
	if screen == null:
		finish("연속 수호전 실제 UI 흐름")
		return
	screen.set_process(false)
	await paint(screen)
	check(Arena.stage == 2 and Arena.modal == "stage" and screen.view_3d.world.theme_id == String(Arena.theme_for(1)["id"]) and screen.view_3d.world.theme_id != first_field,
		"STAGE 2 전장 카드와 새 전장의 3D 월드")
	check(ArenaGeometry.layout() == ArenaGeometry.layout_for_theme(Arena.theme_index) and (ArenaGeometry.layout() != first_layout or Arena.theme_index >= 0), "새 전장의 길 배치")
	check(tap(screen, "stage:start") and Arena.modal == "box" and Arena.heroes.is_empty(), "STAGE 2 카드 확인 뒤 새 파티의 무료 첫 상자")
	await _box_pick_and_close(screen, "STAGE 2 첫 상자")
	check(Arena.heroes.size() == 1 and Arena.modal == "" and Arena.sim.in_prep(), "첫 영웅 지급·정비 시간으로")
	await paint(screen)
	check(tap(screen, "bench"), "대기 편성 버튼")
	await paint(screen)
	check(tap(screen, "close"), "대기 편성 닫기 버튼")
	await paint(screen)
	# A new stage starts from the starting gold; buy the paid summon in its preparation phase.
	Arena.gold = 1000
	await paint(screen)
	var old_gold: int = Arena.gold
	check(tap(screen, "summon") and Arena.modal == "box" and Arena.gold == old_gold - Arena.summon_cost(), "유료 소환 버튼 → 보석상자")
	await paint(screen)
	var spins: int = Arena.spins
	check(tap(screen, "box:reroll") and Arena.spins == spins + 1 and Arena.modal == "box", "상자의 다시 뽑기 버튼")
	await _box_pick_and_close(screen, "추가 상자")
	await paint(screen)
	# Let the transition finish before opening the common pause menu.
	await frames(90)
	main.menu.open()
	check(main.menu.opened, "공통 일시정지 메뉴")
	var elapsed_time: float = Arena.sim.elapsed
	screen._process(0.1)
	check(Arena.sim.elapsed == elapsed_time, "공통 메뉴도 전투 시간 정지")
	main.menu.close()
	# Levels earned on the way would open their popup on the first tick after resuming; answer them
	# first so the resumed state is the saved one.
	while Arena.pending_levels > 0 and Arena.offer_levelup():
		Arena.pick_talent(String(Arena.talent_offer[0]))
	check(Arena.modal == "" and Arena.pending_levels == 0, "이어하기 전 남은 레벨업 정리")
	Arena.autosave()
	var saved := Save.cur_run.duplicate(true)
	Arena.running = false
	main.show_title()
	await paint(main.screen)
	check(tap(main.screen, "resume"), "타이틀 새 모드 이어하기 버튼")
	check(await wait_screen(main, "arena_screen", 1200), "새 모드 이어하기 화면")
	check(Arena.modal == saved["modal"] and Arena.sim.elapsed >= elapsed_time and Arena.sim.elapsed < elapsed_time + 0.1, "이어하기 전투 상태 복구")
	check(Arena.stage == 2 and Arena.sim.wave_no == int(saved["sim"]["wave_no"]) and Arena.sim.in_prep() == bool(saved["sim"]["in_prep"]), "이어하기는 같은 스테이지·같은 웨이브 자리")
	var live: ArenaScreen = main.screen
	await _check_live(main, live, first_button)
	await _check_results(main, live)
	if is_instance_valid(main.screen): main.screen.set_process(false)
	Arena.running = false
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	Save.last_clear = {}
	finish("연속 수호전 실제 UI 흐름")

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
## The open box on a held screen (settled, so it answers): pick the best card by its button —
## a pick commits on release — then close the result by its button.
func _box_pick_and_close(screen: ArenaScreen, label: String) -> void:
	await paint(screen)
	var index := JewelBox.best(Arena.box_cards)
	check(screen.box_ready() and tap(screen, "box:pick:%d" % index) and Arena.phase == Arena.Phase.SWAP and int(Arena.summon_result.get("card", -1)) == index,
		label + ": 카드 버튼(뗄 때 확정)으로 고르기")
	await paint(screen)
	check(tap(screen, "close") and Arena.modal == "", label + ": 결과 닫기 버튼")
	await paint(screen)

## A button by its zone when the views draw it, else the screen's own action (the HUD's 「바로 시작」
## and the result's 「다음 STAGE」 come with the battle HUD package) — the note says which.
func _press_or_act(screen: ArenaScreen, id: String) -> bool:
	if not zone_of(screen, id).is_empty():
		return tap(screen, id)
	print("   (%s: 아직 그려진 존이 없어 화면 동작으로 누름)" % id)
	screen._action(id)
	return true

## Main swaps a fresh battlefield screen in behind its fade: wait for it.
func _next_screen(main: Node, old: Node, limit: int = 1200) -> ArenaScreen:
	for i in range(limit):
		await get_tree().process_frame
		if is_instance_valid(main.screen) and main.screen != old and main.screen is ArenaScreen:
			return main.screen
	return null

## The screen's clock by hand: 1/60 s frames, each one painted (the popup's and the box's clocks
## count pictures), until `done` holds or `limit` seconds pass. True when it held.
func _run_until(screen: ArenaScreen, done: Callable, limit: float) -> bool:
	for i in range(ceili(limit * 60.0)):
		if done.call(): return true
		screen._process(1.0 / 60.0)
		await frames(1)
	return done.call()

## Live zones whose id starts with `prefix`.
static func _live_zones(screen: ArenaScreen, prefix: String) -> int:
	var n := 0
	for zone in screen.ui.zones:
		if String(zone["id"]).begins_with(prefix) and bool(zone["on"]): n += 1
	return n

## The tail of the first live zone `prefix<tail>` with a tail.
static func _first_zone_tail(screen: ArenaScreen, prefix: String) -> String:
	for zone in screen.ui.zones:
		var id := String(zone["id"])
		if id.begins_with(prefix) and id.length() > prefix.length() and bool(zone["on"]):
			return id.trim_prefix(prefix)
	return ""

static func _counts(ids: Array) -> Array:
	var out: Array = []
	for id in ids: out.append(Arena.talent_count(String(id)))
	return out

static func _alive() -> int:
	var n := 0
	for mo in Arena.sim.monsters:
		if float(mo["hp"]) > 0.0: n += 1
	return n

## The screen point over a living monster in the open battle box (else the box's middle, by the crystal).
static func _target_pixel(screen: ArenaScreen) -> Vector2:
	for mo in Arena.sim.monsters:
		if float(mo["hp"]) <= 0.0: continue
		var pixel: Vector2 = screen.view_3d.project(Vector2(mo["pos"]))
		if ArenaScreen.BATTLEFIELD.grow(-24.0).has_point(pixel): return pixel
	return ArenaScreen.BATTLEFIELD.get_center()

static func _esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	return e

static func _right_click(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.position = at
	e.pressed = true
	return e

static func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	return e

# --------------------------------------------------------------------------- #
# The screen on its own clock
# --------------------------------------------------------------------------- #
func _check_live(main: Node, screen: ArenaScreen, button: Rect2) -> void:
	for i in range(600):
		if float(main.get("_fade_dir")) == 0.0: break
		await frames(1)
	Engine.time_scale = 0.0
	screen.set_process(true)
	# Room for the whole section in this preparation (a window or the hold stops its countdown anyway).
	Arena.sim.prep_t = maxf(Arena.sim.prep_t, 30.0)
	await paint(screen)
	check(Arena.modal == "" and Arena.sim.in_prep() and not screen._settled(), "살아 있는 화면: 정비 시간에서 시작")
	await _check_popup(screen, button)
	await _check_followup(screen, button)
	await _check_map(main, screen)
	await _check_box(main, screen)
	await _check_wave_start(screen)
	await _check_aim(main, screen)
	screen.set_process(false)
	Engine.time_scale = 1.0

## F1: the popup's first frame has let go of the stick; it opens disarmed and its picks commit on
## release only once armed; the pick holds the battle for its flourish.
func _check_popup(screen: ArenaScreen, button: Rect2) -> void:
	# A finger is moving the hero when the step opens the popup (a level waiting in a preparation).
	screen._pointer(3, Vector2(160, 640), true)
	check(screen._joy_pointer == 3, "팝업 전: 이동 손가락")
	Arena.pending_levels = 1
	screen._process(1.0 / 60.0)
	check(Arena.modal == "talent" and screen._joy_pointer == -99 and not screen.talent_armed() and screen.talent_entrance_age() == 0.0,
		"팝업이 열린 그 프레임에 스틱을 놓고 시계 0·무장 전 (시계 버그 회귀)")
	screen._pointer(3, Vector2(160, 640), false)
	var first := String(Arena.talent_offer[0])
	await frames(1)
	check(_live_zones(screen, "talent:pick:") == 0, "팝업 첫 그림에 켜진 고르기 존 없음")
	tap_at(screen, button.get_center())
	check(Arena.talent_count(first) == 0 and Arena.modal == "talent", "열자마자 탭은 고르지 않음")
	# The buttons show before they answer: a tap on one still picks nothing.
	check(await _run_until(screen, func() -> bool: return screen.talent_entrance_age() >= 0.70, 2.0), "팝업 입장 시계가 흐름")
	var zone := zone_of(screen, "talent:pick:" + first)
	check(not zone.is_empty() and not bool(zone["on"]) and not screen.talent_armed() and screen.talent_arm_progress() > 0.5,
		"무장 전: 버튼은 보이지만 꺼져 있음 (무장 %.2f)" % screen.talent_arm_progress())
	if not zone.is_empty(): tap_at(screen, Rect2(zone["rect"]).get_center())
	check(Arena.talent_count(first) == 0, "무장 전(%.2f s) 버튼 탭은 고르지 않음" % screen.talent_entrance_age())
	check(await _run_until(screen, func() -> bool: return screen.talent_armed(), 2.0) and screen.talent_entrance_age() >= ArenaScreen.TALENT_ARM_AT - 0.02,
		"TALENT_ARM_AT(%.2f s) 뒤에 무장" % ArenaScreen.TALENT_ARM_AT)
	await frames(1)
	check(press(screen, "talent:pick:" + first) and screen.talent_pressed == "talent:pick:" + first and Arena.talent_count(first) == 0,
		"누르기만으로는 고르지 않음 (눌린 모양만)")
	mouse(screen, Vector2(640, 760), false)
	check(Arena.talent_count(first) == 0 and screen.talent_pressed == "" and Arena.modal == "talent", "버튼 밖에서 떼면 고르지 않음")
	check(tap(screen, "talent:pick:" + first) and Arena.talent_count(first) == 1 and screen.pick_hold_age() >= 0.0 and screen.pick_hold_id == first
			and screen.pick_hold_offer.has(first), "무장 뒤 탭(뗄 때 확정)으로 고르기 · 마무리 시작")
	var elapsed: float = Arena.sim.elapsed
	screen._process(0.1)
	check(Arena.sim.elapsed == elapsed and screen.overlay_open(), "고르기 마무리 동안 전투 정지 · 메뉴가 끼지 않음")
	check(await _run_until(screen, func() -> bool: return screen.pick_hold_age() < 0.0, 1.0), "마무리(%.2f s)가 끝남" % ArenaScreen.PICK_HOLD)
	screen._process(0.1)
	check(Arena.sim.elapsed > elapsed and Arena.modal == "", "마무리 뒤 전투 재개")

## Two levels waiting: the next offer comes after the flourish, with its cards only and the shorter
## arming; taps right after the pick, and right as the next offer shows, pick nothing.
func _check_followup(screen: ArenaScreen, button: Rect2) -> void:
	Arena.pending_levels = 2
	screen._process(1.0 / 60.0)
	check(Arena.modal == "talent" and Arena.pending_levels == 2, "남은 레벨 둘: 팝업")
	check(await _run_until(screen, func() -> bool: return screen.talent_armed() and _live_zones(screen, "talent:pick:") > 0, 2.0), "첫 제안 무장")
	var first := String(Arena.talent_offer[0])
	check(tap(screen, "talent:pick:" + first) and Arena.pending_levels == 1 and Arena.modal == "talent" and screen.pick_hold_age() >= 0.0,
		"첫 제안 고르기 → 다음 제안은 마무리 뒤")
	var next: Array = Arena.talent_offer.duplicate()
	var counts := _counts(next)
	tap_at(screen, button.get_center())
	check(_counts(next) == counts and Arena.pending_levels == 1, "마무리 중 곧바로 두 번째 탭은 고르지 않음")
	check(await _run_until(screen, func() -> bool: return screen.pick_hold_age() < 0.0, 1.0), "마무리가 끝남")
	await frames(1)
	check(screen.talent_followup and not screen.talent_armed() and screen.talent_entrance_age() < 0.05, "이어지는 제안: 카드만 다시 · 무장은 처음부터")
	tap_at(screen, button.get_center())
	check(_counts(next) == counts and Arena.pending_levels == 1, "이어지는 제안이 뜨자마자의 탭은 고르지 않음")
	check(await _run_until(screen, func() -> bool: return screen.talent_armed(), 2.0) and screen.talent_entrance_age() >= ArenaScreen.TALENT_REARM_AT - 0.02
			and screen.talent_entrance_age() < ArenaScreen.TALENT_ARM_AT - 0.1, "이어지는 제안은 TALENT_REARM_AT(%.2f s)에 무장" % ArenaScreen.TALENT_REARM_AT)
	check(await _run_until(screen, func() -> bool: return _live_zones(screen, "talent:pick:") > 0, 1.0), "이어지는 제안의 버튼이 켜짐")
	var second := String(Arena.talent_offer[0])
	check(tap(screen, "talent:pick:" + second) and Arena.pending_levels == 0, "이어지는 제안 고르기")
	await _run_until(screen, func() -> bool: return screen.pick_hold_age() < 0.0, 1.0)
	check(Arena.modal == "" and not screen.talent_followup, "남은 레벨을 다 고르면 전투로")

## F2: the map opens over an armed offer and gives it back untouched, armed again; Esc and back
## step out (zoomed → overview → closed); the rail's viewer is the same map.
func _check_map(main: Node, screen: ArenaScreen) -> void:
	Arena.pending_levels = 1
	screen._process(1.0 / 60.0)
	await frames(1)
	check(Arena.modal == "talent" and not tap(screen, "talent:map") and not screen.talent_map, "무장 전 지도 버튼은 듣지 않음")
	# Like the picks, the map button acts on release, for a press begun once the popup armed.
	var map_at: Vector2 = Rect2(zone_of(screen, "talent:map").get("rect", Rect2())).get_center()
	mouse(screen, map_at, true)
	check(await _run_until(screen, func() -> bool: return screen.talent_armed() and _live_zones(screen, "talent:map") > 0, 2.0), "지도 버튼 무장")
	mouse(screen, map_at, false)
	check(not screen.talent_map, "무장 전에 시작된 누름은 무장 뒤에 떼도 지도를 열지 않음")
	check(press(screen, "talent:map") and not screen.talent_map and screen.talent_pressed == "talent:map", "지도 버튼도 누르기만으로는 열리지 않음")
	mouse(screen, Vector2(640, 760), false)
	check(not screen.talent_map and screen.talent_pressed == "", "지도 버튼 밖에서 떼면 열리지 않음")
	var offer: Array = Arena.talent_offer.duplicate()
	check(tap(screen, "talent:map") and screen.talent_map and Arena.modal == "talent" and Arena.talent_offer == offer and Arena.pending_levels == 1 and not screen.talent_armed(),
		"제안 중 지도 열기: 제안·남은 레벨·창 그대로")
	await frames(1)
	var group := _first_zone_tail(screen, "talent:group:")
	check(not group.is_empty() and tap(screen, "talent:group:" + group) and screen.map_focus == group, "지도: 별자리 확대 (%s)" % group)
	await frames(1)
	var node := _first_zone_tail(screen, "talent:node:")
	check(not node.is_empty() and tap(screen, "talent:node:" + node) and screen.map_node == node and screen.map_focus == String(Talents.by_id(node).get("group", "")),
		"지도: 별 고르기 → 상세 (%s)" % node)
	await frames(1)
	if not zone_of(screen, "talent:group:").is_empty():
		check(tap(screen, "talent:group:") and screen.talent_map and screen.map_focus == "", "지도: 「전체」 탭 → 개요")
		await frames(1)
		tap(screen, "talent:group:" + group)
	screen._input(_esc())
	check(screen.talent_map and screen.map_focus == "" and screen.map_node == "", "Esc: 확대 → 개요")
	screen._input(_esc())
	check(not screen.talent_map and Arena.modal == "talent" and Arena.talent_offer == offer and Arena.pending_levels == 1 and not screen.talent_armed(),
		"Esc: 개요 → 제안으로 돌아옴 (다시 무장)")
	check(await _run_until(screen, func() -> bool: return screen.talent_armed(), 2.0) and screen.talent_arm_progress() == 1.0, "돌아온 제안이 다시 무장")
	await frames(1)
	check(tap(screen, "talent:map") and screen.talent_map, "지도 다시 열기")
	await frames(1)
	check(tap(screen, "talent:back") and not screen.talent_map and Arena.talent_offer == offer and not screen.talent_armed(), "「고르기로 돌아가기」 버튼")
	check(await _run_until(screen, func() -> bool: return screen.talent_armed() and _live_zones(screen, "talent:map") > 0, 2.0), "다시 무장")
	check(tap(screen, "talent:map") and screen.talent_map, "지도 또 열기")
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not screen.talent_map and Arena.modal == "talent" and not main.menu.opened, "뒤로 가기: 지도를 닫고 제안으로 (메뉴는 안 열림)")
	# The constellation column beside the cards: a row opens the map on its constellation.
	check(await _run_until(screen, func() -> bool: return screen.talent_armed() and _live_zones(screen, "talent:group:") > 0, 2.0), "별자리 열 무장")
	var row := _first_zone_tail(screen, "talent:group:")
	check(not row.is_empty() and tap(screen, "talent:group:" + row) and screen.talent_map and screen.map_focus == row, "별자리 열의 줄 → 그 별자리의 지도 (%s)" % row)
	screen._input(_esc())
	screen._input(_esc())
	check(not screen.talent_map and Arena.talent_offer == offer, "Esc 두 번 → 제안으로")
	check(await _run_until(screen, func() -> bool: return screen.talent_armed() and _live_zones(screen, "talent:pick:") > 0, 2.0), "제안 무장")
	check(tap(screen, "talent:pick:" + String(offer[0])) and Arena.pending_levels == 0, "지도를 다녀온 제안에서 고르기")
	await _run_until(screen, func() -> bool: return screen.pick_hold_age() < 0.0, 1.0)
	await frames(1)
	check(tap(screen, "talents") and Arena.modal == "talent" and screen.talent_map and Arena.talent_offer.is_empty(), "레일의 별자리 = 지도 (열람)")
	await frames(1)
	check(tap(screen, "talent:group:" + group) and screen.map_focus == group, "열람 지도 확대")
	screen._input(_esc())
	check(Arena.modal == "talent" and screen.talent_map and screen.map_focus == "", "열람 Esc: 확대 → 개요")
	screen._input(_esc())
	check(Arena.modal == "" and not screen.talent_map, "열람 Esc: 개요 → 닫기")

## F11: the box answers only once its ceremony settles (a tap skips it), a reroll deals again and
## locks it again, a card picks on release, and the result closes once it is in.
func _check_box(main: Node, screen: ArenaScreen) -> void:
	Arena.gold = 1000
	await frames(1)
	check(screen.view_3d.live, "전투 중 3D 실시간")
	check(tap(screen, "summon") and Arena.modal == "box" and not screen.box_ready(), "유료 상자: 열리자마자는 입력 잠김")
	check(not screen.view_3d.live, "상자가 열리면 3D 는 마지막 그림 (절전)")
	var spins: int = Arena.spins
	screen._action("box:pick:0")
	screen._action("box:reroll")
	check(Arena.phase == Arena.Phase.DRAW and Arena.spins == spins, "준비 전 고르기·다시 뽑기는 무시")
	await frames(1)
	check(_live_zones(screen, "box:pick:") == 0 and _live_zones(screen, "box:skip") > 0, "정착 전에는 고르기 없이 화면 전체가 건너뛰기")
	check(tap(screen, "box:skip"), "탭으로 연출 건너뛰기")
	check(await _run_until(screen, func() -> bool: return screen.box_ready(), 3.0), "건너뛴 뒤 입력 열림 (나눔 %.2f s)" % screen.box_deal_age())
	await frames(1)
	check(_live_zones(screen, "box:pick:") > 0, "정착 뒤 카드 고르기 존")
	check(press(screen, "box:reroll") and Arena.spins == spins, "다시 뽑기도 누르기만으로는 안 뽑음")
	mouse(screen, Vector2(640, 40), false)
	check(Arena.spins == spins, "다시 뽑기 버튼 밖에서 떼면 안 뽑음")
	check(Arena.can_respin() and tap(screen, "box:reroll") and Arena.spins == spins + 1 and screen.box_deal_age() < 0.05 and not screen.box_ready(),
		"다시 뽑기를 눌렀다 떼면 → 새 나눔 · 다시 잠김")
	await frames(1)
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not main.menu.opened and Arena.modal == "box", "뒤로 가기는 상자 연출을 건너뜀 (메뉴는 안 열림)")
	check(await _run_until(screen, func() -> bool: return screen.box_ready(), 3.0), "건너뛴 다시 뽑기 → 입력")
	await frames(1)
	check(press(screen, "box:pick:0") and Arena.phase == Arena.Phase.DRAW, "카드를 누르기만으로는 고르지 않음")
	mouse(screen, Vector2(640, 40), false)
	check(Arena.phase == Arena.Phase.DRAW, "카드 밖에서 떼면 고르지 않음")
	check(tap(screen, "box:pick:0") and Arena.phase == Arena.Phase.SWAP and screen.box_pick_age() >= 0.0, "카드를 눌렀다 떼면 고르기")
	screen._action("close")
	check(Arena.modal == "box", "결과가 들어오기 전에는 닫히지 않음")
	check(await _run_until(screen, func() -> bool: return screen.box_ready(), 3.0), "결과가 들어오면 입력 열림 (%.2f s)" % screen.box_pick_age())
	screen._input(_esc())
	check(Arena.modal == "" and screen.view_3d.live, "Esc 로 결과 닫기 → 전투 (3D 다시 실시간)")

## The preparation's 「바로 시작」.
func _check_wave_start(screen: ArenaScreen) -> void:
	await frames(1)
	check(Arena.modal == "" and Arena.sim.in_prep(), "정비 시간")
	check(_press_or_act(screen, "wave:start"), "「바로 시작」")
	screen._process(1.0 / 60.0)
	check(not Arena.sim.in_prep() and Arena.sim.wave_size() > 0, "「바로 시작」으로 웨이브 시작")

## F6: the starburst's button arms the aim; a press-release on the field casts on that spot; the
## button again, Esc, back and the right button cancel; aiming never starts the stick; a second
## finger aims while the first moves; the battle runs on; a window ends the aim.
func _check_aim(main: Node, screen: ArenaScreen) -> void:
	check(await _run_until(screen, func() -> bool: return _alive() >= 1, 8.0), "조준 검사: 몬스터 등장")
	Arena.sim._spawn_t = 1.0e9
	# Sturdy targets: the starburst must find them again after every cast.
	for mo in Arena.sim.monsters:
		if float(mo["hp"]) > 0.0:
			mo["hp"] = 1.0e7
			mo["max"] = 1.0e7
	Arena.gold = 5000
	Arena.sim.skill_cooldowns["blast"] = 0.0
	await frames(1)
	var uses := int(Arena.sim.skill_uses["blast"])
	check(bool(Arena.sim.skill_state("blast")["ready"]) and tap(screen, "skill:blast") and screen.aiming() and int(Arena.sim.skill_uses["blast"]) == uses,
		"별빛 폭발 버튼은 조준만 (시전 안 함)")
	check(main.screen_modal_open(), "조준 중에는 메뉴가 끼어들지 않음")
	var target := _target_pixel(screen)
	var spot: Vector2 = screen.view_3d.ground_at(target)
	tap_at(screen, target)
	var blasts := Arena.sim.events.filter(func(e: Dictionary) -> bool: return String(e.get("t", "")) == "arena_blast")
	check(not screen.aiming() and int(Arena.sim.skill_uses["blast"]) == uses + 1 and not blasts.is_empty()
			and int(blasts[-1].get("cost", -1)) == Arena.sim.skill_cost("blast"), "전장을 눌렀다 떼면 시전 (골드 %d)" % Arena.sim.skill_cost("blast"))
	check(not blasts.is_empty() and Vector2(blasts[-1]["p"]).distance_to(spot) < 1.0, "누른 자리에 떨어짐")
	# O2: when the skill became ready again — from the moment its cooldown ends; a window over the
	# battle hides the state without restarting the moment.
	check(screen.skill_ready_age("blast") == -1.0, "쿨타임 중 skill_ready_age = -1")
	Arena.sim.skill_cooldowns["blast"] = 0.0
	check(screen.skill_ready_age("blast") == 0.0, "준비가 된 순간 skill_ready_age = 0")
	screen._process(0.1)
	check(absf(screen.skill_ready_age("blast") - 0.1) < 0.01, "준비 뒤 시간이 흐름 (%.3f)" % screen.skill_ready_age("blast"))
	check(Arena.open_modal("bench") and screen.skill_ready_age("blast") == -1.0, "창이 열린 동안은 준비 아님")
	Arena.close_modal()
	check(screen.skill_ready_age("blast") >= 0.099, "창을 닫아도 준비된 순간은 그대로 (새로 깜빡이지 않음)")
	screen._process(1.0 / 60.0)
	await frames(1)
	check(tap(screen, "skill:blast") and screen.aiming(), "다시 조준")
	check(tap(screen, "skill:blast") and not screen.aiming() and int(Arena.sim.skill_uses["blast"]) == uses + 1, "버튼을 다시 누르면 조준 취소")
	check(tap(screen, "skill:blast") and screen.aiming(), "조준 (Esc)")
	screen._input(_esc())
	check(not screen.aiming(), "Esc 로 조준 취소")
	check(tap(screen, "skill:blast") and screen.aiming(), "조준 (뒤로 가기)")
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not screen.aiming() and not main.menu.opened, "뒤로 가기로 조준 취소 (메뉴는 안 열림)")
	check(tap(screen, "skill:blast") and screen.aiming(), "조준 (오른쪽 단추)")
	screen._input(_right_click(Vector2(400, 400)))
	check(not screen.aiming(), "오른쪽 단추로 조준 취소")
	check(tap(screen, "skill:blast") and screen.aiming(), "조준 (끌기)")
	screen._pointer(7, Vector2(300, 420), true)
	check(screen._joy_pointer == -99 and screen._aim_pointer == 7 and screen.aim_pixel == Vector2(300, 420), "조준 중 전장 누름은 스틱 대신 조준을 잡음")
	screen._input(_drag(7, Vector2(330, 440)))
	check(screen.aim_pixel == Vector2(330, 440) and screen.aim_point().is_finite() and screen.aim_valid(), "끌면 조준점이 따라감")
	await frames(1)
	var state = screen.view_3d.world.get("_aim_state")
	check(state is Dictionary and bool(state.get("shown", false)) and Vector2(state.get("at", Vector2.INF)).is_finite(), "3D 조준 링 (set_aim)")
	screen._pointer(7, Vector2(1100, 330), false)
	check(not screen.aiming() and int(Arena.sim.skill_uses["blast"]) == uses + 1, "전장 밖에서 떼면 취소 (시전 없음)")
	await frames(1)
	state = screen.view_3d.world.get("_aim_state")
	check(state is Dictionary and not bool(state.get("shown", true)), "조준이 끝나면 3D 링을 내림")
	# A second finger aims while the first one moves the hero.
	Arena.sim.skill_cooldowns["blast"] = 0.0
	await frames(1)
	screen._pointer(2, Vector2(200, 600), true)
	screen._input(_drag(2, Vector2(245, 600)))
	var skill := zone_of(screen, "skill:blast")
	screen._pointer(3, Rect2(skill.get("rect", Rect2())).get_center(), true)
	screen._pointer(3, Rect2(skill.get("rect", Rect2())).get_center(), false)
	check(screen.aiming() and screen._joy_pointer == 2, "이동 중 두 번째 손가락으로 조준")
	var target2 := _target_pixel(screen)
	screen._pointer(4, target2, true)
	check(screen._aim_pointer == 4 and screen._joy_pointer == 2, "또 다른 손가락의 누름이 조준을 잡음 (스틱 그대로)")
	screen._pointer(4, target2, false)
	check(not screen.aiming() and int(Arena.sim.skill_uses["blast"]) == uses + 2 and screen._joy_pointer == 2 and screen.joystick.x > 0, "이동하며 시전")
	screen._pointer(2, Vector2(245, 600), false)
	# The battle runs on under the aim; a window ends it.
	Arena.sim.skill_cooldowns["blast"] = 0.0
	await frames(1)
	check(tap(screen, "skill:blast") and screen.aiming(), "조준 (전투 진행)")
	var elapsed: float = Arena.sim.elapsed
	screen._process(0.1)
	check(screen.aiming() and Arena.sim.elapsed > elapsed, "조준 중에도 전투는 흐름")
	check(Arena.open_modal("bench"), "조준 중 창 열기")
	screen._process(1.0 / 60.0)
	check(not screen.aiming(), "창이 열리면 조준 취소")
	Arena.close_modal()
	screen._process(1.0 / 60.0)
	await frames(1)

## The result card after a defeat: no 「다음 STAGE」, and 「재도전」 opens the same stage again from
## the start on a fresh screen.
func _check_results(main: Node, screen: ArenaScreen) -> void:
	screen.set_process(false)
	Arena.sim.revives = Balance.ARENA_REVIVE_USES
	for i in range(64):
		if not Arena.running: break
		Arena.sim.invuln_t = 0.0
		Arena.sim._damage_crystal(1.0e9, Balance.ARENA_CENTER)
	check(not Arena.running and Arena.modal == "result" and not Arena.sim.won, "수정이 깨지면 패배 결과")
	await paint(screen)
	check(not screen.can_next_stage(), "패배 뒤에는 「다음 STAGE」 없음")
	var stage: int = Arena.stage
	check(_press_or_act(screen, "result:retry"), "결과의 「재도전」")
	var fresh := await _next_screen(main, screen)
	check(fresh != null and Arena.stage == stage and Arena.modal == "stage" and Arena.running and Arena.heroes.is_empty(),
		"재도전은 같은 STAGE %d 를 처음부터, 새 화면에서" % stage)
	if fresh != null: fresh.set_process(false)
