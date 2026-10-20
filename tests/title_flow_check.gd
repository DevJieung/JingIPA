extends Harness

## 타이틀 흐름(2026-10-19 LB2b) — 사다리 시작 · 스테이지 선택 · 직전 클리어 · Hellbound 입구.
##   - 「시작」은 다음에 열린 스테이지(Save.stage_unlocked)를 연다.
##   - 「스테이지」: 열린 칸만 고를 수 있고(잠긴 칸은 눌리지 않음), 고르면 그 스테이지로 시작한다.
##     한 페이지가 한 챕터(10칸)이고 10번째 칸이 챕터 보스다. 칸 데이터(STAGE n · 전장 이름 · 생태 ·
##     클리어 · 다음 도전)가 맞다.
##   - 첫 기록 칸의 데이터: 직전 클리어 「STAGE n · 전장」(ko·en, 레거시 'Stage %d'→'{0}탄' 치환 없이),
##     클리어가 없으면 사다리의 「도전 · STAGE n」(옛 10탄 기록 아님). 챕터 트랙은 그 챕터의 실제 클리어 수.
##   - 이어하기 라벨: 사다리 판 「계속하기 · STAGE n」, Hellbound 판 「계속하기 · HELLBOUND · WAVE n」.
##   - 「Hellbound」: DLC 가 없으면 상점 시트(수호자 묶음), 있으면 스쿼드 화면. 뒤로 가기가 위의 창부터
##     닫고, 창이 열린 동안 screen_modal_open 이 참이다.
##   - Main.start_hellbound 는 런이 스쿼드를 거절하면(도감에 없는 영웅) 아무것도 하지 않고, 받으면
##     Hellbound 전장으로 간다(도감은 검사가 메모리에서 채운다).
##   - Main.next_stage / retry_stage 가 다음 스테이지·같은 스테이지를 연다.

var _errors = preload("res://tests/log_errors.gd").new()


## A shop that answers at once (as in tests/store_check.gd): owns exactly `owned`.
class TestShop extends RefCounted:
	const NAME := "test"
	var store: Node
	var owned: Array = []
	func start() -> void: store.set_owned(owned)
	func sells(_id: String) -> bool: return true
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void:
		store.set_owned(owned)
		store.finish_restore(true)
	func buy(_product: Dictionary) -> void: pass


func _ready() -> void:
	if not require_no_save():
		return
	OS.add_logger(_errors)
	var saved := {"unlocked": Save.stage_unlocked, "cleared": Save.stage_cleared, "last": Save.last_clear.duplicate(),
		"best": Save.best_stage, "locale": I18n.locale}
	Run.running = false
	Arena.running = false
	Save.cur_run.clear()
	Save.best_stage = 0
	var main = load("res://game/main.gd").new()
	add_child(main)
	await paint(main.screen)
	await _check_records(main)
	await _check_resume_label(main)
	await _check_start(main)
	await _check_stage_select(main)
	await _check_next_retry(main)
	await _check_hellbound(main)
	Store.use_backend(null)
	I18n.set_locale(String(saved["locale"]))
	Save.stage_unlocked = int(saved["unlocked"])
	Save.stage_cleared = int(saved["cleared"])
	Save.last_clear = saved["last"]
	Save.best_stage = int(saved["best"])
	if is_instance_valid(main.screen):
		main.screen.set_process(false)
	Arena.running = false
	check(_errors.count() == 0, "로그 오류 없음 (%d)" % _errors.count())
	for line in _errors.lines:
		printerr("   로그 오류: " + line)
	OS.remove_logger(_errors)
	finish("타이틀 흐름 (사다리·스테이지 선택·직전 클리어·Hellbound)")


func _title(main: Node) -> TitleScreen:
	return main.screen as TitleScreen


## Back to a fresh title (no saved run) and let its fade finish.
func _home(main: Node) -> void:
	Arena.running = false
	Save.cur_run.clear()
	main.show_title()
	for i in range(120):
		if float(main.get("_fade_dir")) == 0.0:
			break
		await frames(1)
	await paint(main.screen)


func _check_records(main: Node) -> void:
	var title := _title(main)
	# Before any ladder clear: the stage to take on, never the old ten-stage chain's best.
	Save.last_clear = {}
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	Save.best_stage = 7
	var none: Dictionary = title.first_record()
	check(none["kind"] == "next" and none["label"] == "도전" and none["value"] == "STAGE 1" and not String(none["value"]).contains("탄"),
		"클리어가 없으면 사다리의 「도전 · STAGE 1」 (옛 「7탄」 아님)")
	check(int(none["track_total"]) == 10 and int(none["track_cleared"]) == 0 and int(none["track_reached"]) == 1, "그 챕터 트랙: 클리어 0 · 다음 칸 1")
	Save.best_stage = 0
	# The chapter track counts the stages actually cleared in it (the ladder opens in order).
	Save.stage_unlocked = 16
	Save.stage_cleared = 15
	Save.last_clear = {"stage": 3, "theme": String(Roster.THEMES[Arena.ladder_theme(3)]["id"])}
	var replay: Dictionary = title.first_record()
	check(replay["kind"] == "last_clear" and int(replay["track_cleared"]) == 10 and int(replay["track_reached"]) == 11,
		"예전 스테이지를 다시 깨도 그 챕터 트랙은 실제 클리어 10/10")
	Save.last_clear = {"stage": 15, "theme": String(Roster.THEMES[Arena.ladder_theme(15)]["id"])}
	var current: Dictionary = title.first_record()
	check(int(current["track_cleared"]) == 5 and int(current["track_reached"]) == 6, "챕터 2: 클리어 5 · 다음 도전 6번째 칸")
	await paint(title)
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	var number := 2
	var theme: Dictionary = Roster.THEMES[Arena.ladder_theme(number)]
	Save.last_clear = {"stage": number, "theme": String(theme["id"])}
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		var record: Dictionary = title.first_record()
		var field := I18n.t(String(theme["ko"]))
		check(record["kind"] == "last_clear" and int(record["stage"]) == number, "%s: 첫 기록 칸은 직전 클리어" % locale)
		check(record["label"] == ("직전 클리어" if locale == "ko" else "Last cleared"), "%s: 라벨 arena.last_clear (%s)" % [locale, record["label"]])
		check(record["value"] == "STAGE %d · %s" % [number, field], "%s: 값 'STAGE n · 전장' (%s)" % [locale, record["value"]])
		check(I18n.t(String(record["value"])) == record["value"], "%s: 그릴 때 다시 번역해도 그대로 ('Stage %%d' 치환 없음)" % locale)
		check(locale == "ko" or not String(record["value"]).contains("탄"), "en: 한국어 탄 표기가 섞이지 않음")
		await paint(title)
	I18n.set_locale("ko")
	Save.last_clear = {}


## The 「이어하기」 label of a saved run: its ladder stage, or a Hellbound run's wave.
func _check_resume_label(main: Node) -> void:
	var title := _title(main)
	Save.cur_run = {"mode": "arena", "wave": 7, "stage": 7, "hell": false, "sim": {"wave_no": 4}}
	check(title.resume_label().ends_with("STAGE 7"), "사다리 판의 이어하기: 계속하기 · STAGE 7 (%s)" % title.resume_label())
	Save.cur_run = {"mode": "arena", "wave": 60, "stage": 60, "hell": true, "sim": {"wave_no": 23}}
	var label := title.resume_label()
	check(label.contains("HELLBOUND") and label.ends_with("WAVE 23") and not label.contains("STAGE"),
		"Hellbound 판의 이어하기: 계속하기 · HELLBOUND · WAVE 23 (%s)" % label)
	await paint(title)
	check(not zone_of(title, "resume").is_empty(), "저장된 Hellbound 판이면 이어하기 버튼")
	Save.cur_run.clear()
	await paint(title)


func _check_start(main: Node) -> void:
	Save.stage_unlocked = 3
	Save.stage_cleared = 2
	await _home(main)
	check(tap(main.screen, "start"), "타이틀 「시작」 버튼")
	check(await wait_screen(main, "arena_screen", 1200), "「시작」으로 수호전 화면")
	check(Arena.stage == 3 and not Arena.hell, "「시작」은 다음에 열린 STAGE 3 (%d)" % Arena.stage)
	check(Arena.theme_index == Arena.ladder_theme(3), "그 스테이지의 사다리 전장")


func _check_stage_select(main: Node) -> void:
	Save.stage_unlocked = 13
	Save.stage_cleared = 12
	await _home(main)
	var title := _title(main)
	check(tap(title, "stages"), "타이틀 「스테이지」 버튼")
	var view: StageSelectView = title.stage_select
	check(view.opened and main.screen_modal_open(), "스테이지 선택이 열리고 다른 버튼을 막음")
	check(view.page == 1 and view.chapter() == 2, "다음 도전(STAGE 13)이 있는 챕터 2 쪽에서 열림")
	await paint(title)
	var cells: Array = view.cells()
	check(cells.size() == 10 and int(cells[0]["stage"]) == 11 and int(cells[9]["stage"]) == 20, "한 쪽은 한 챕터 열 칸 (11~20)")
	var c12: Dictionary = view.cell(12)
	var c13: Dictionary = view.cell(13)
	var c14: Dictionary = view.cell(14)
	var theme: Dictionary = Roster.THEMES[Arena.ladder_theme(12)]
	check(c12["label"] == "STAGE 12" and c12["name"] == I18n.t(String(theme["ko"])) and c12["body"] == String(theme["main_body"]), "칸 데이터: STAGE n · 전장 이름 · 주 몸통")
	check(c12["open"] and c12["cleared"] and not c12["next"], "깬 칸: 열림 · 클리어")
	check(c13["open"] and not c13["cleared"] and c13["next"], "다음 도전 칸: 열림 · 다음")
	check(not c14["open"] and not c14["cleared"], "그 뒤 칸: 잠김")
	check(view.cell(20)["chapter_boss"] and not view.cell(19)["chapter_boss"], "10의 배수 칸은 챕터 보스")
	check(not zone_of(title, "stage:pick:13").is_empty() and not zone_of(title, "stage:pick:14").is_empty(), "칸마다 자리가 등록됨")
	check(not tap(title, "stage:pick:14") and not view.action("stage:pick:14") and view.picked == 0 and Arena.running == false,
		"잠긴 칸은 눌리지도 시작되지도 않음")
	check(tap(title, "stage:page:1") and view.page == 2 and int(view.cells()[0]["stage"]) == 21, "다음 쪽 (21~30)")
	await paint(title)
	check(not view.cell(21)["open"], "다음 챕터는 잠김")
	view.action("stage:page:-1")
	view.action("stage:page:-1")
	view.action("stage:page:-1")
	check(view.page == 0, "앞 쪽 끝에서 멈춤")
	view.action("stage:page:1")
	await paint(title)
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not view.opened and not main.menu.opened, "뒤로 가기는 스테이지 선택만 닫음")
	await paint(title)
	check(tap(title, "stages") and view.opened, "다시 열기")
	await paint(title)
	check(tap(title, "stage:pick:12"), "열린 칸 STAGE 12 누르기")
	check(not tap(title, "stage:pick:13") or view.picked == 12, "두 번째 누름은 다른 판을 열지 않음")
	check(await wait_screen(main, "arena_screen", 1200), "고른 스테이지로 수호전 화면")
	check(Arena.stage == 12 and Arena.theme_index == Arena.ladder_theme(12), "고른 STAGE 12 로 시작 (%d)" % Arena.stage)


func _check_next_retry(main: Node) -> void:
	# On the arena screen of STAGE 12 (unlocked up to 13): win it, then the next stage.
	check(not main.next_stage(), "판이 도는 중에는 다음 스테이지 없음")
	Arena.sim.done = true
	Arena.sim.won = true
	Arena.end_run(true)
	check(Save.stage_unlocked == 13, "STAGE 12 승리 뒤 해금은 13")
	check(main.next_stage(), "결과의 다음 스테이지 도우미")
	check(await wait_screen(main, "arena_screen", 1200) and Arena.stage == 13, "다음 스테이지 STAGE 13 (%d)" % Arena.stage)
	for i in range(60):
		if float(main.get("_fade_dir")) == 0.0:
			break
		await frames(1)
	Arena.sim.done = true
	Arena.end_run(false)
	check(main.retry_stage(), "결과의 재도전 도우미")
	for i in range(120):
		await frames(1)
		if float(main.get("_fade_dir")) == 0.0 and Arena.running:
			break
	check(Arena.running and Arena.stage == 13, "재도전은 같은 STAGE 13 (%d)" % Arena.stage)


func _check_hellbound(main: Node) -> void:
	await _home(main)
	var title := _title(main)
	# Not owned: the button opens the shop sheet on the DLC.
	var shop := TestShop.new()
	Store.use_backend(shop)
	check(not title.dlc(), "상점이 있고 사지 않았으면 DLC 없음")
	await paint(title)
	check(tap(title, "hell"), "타이틀 「Hellbound」 버튼 (비소유)")
	check(title.store.opened and title.store.focus == Store.GUARDIAN and not title.squad.opened, "비소유: 상점 시트(수호자 묶음)")
	check(main.screen_modal_open(), "상점 시트가 열린 동안 다른 버튼을 막음")
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not title.store.opened and not main.menu.opened, "뒤로 가기는 상점 시트만 닫음")
	await paint(title)
	# Owned: the squad picker.
	var owner := TestShop.new()
	owner.owned = [Store.GUARDIAN]
	Store.use_backend(owner)
	check(title.dlc(), "DLC 보유")
	await paint(title)
	check(tap(title, "hell"), "타이틀 「Hellbound」 버튼 (보유)")
	check(title.squad.opened and not title.store.opened and title.squad.main == main, "보유: 스쿼드 화면")
	check(main.screen_modal_open(), "스쿼드 화면이 열린 동안 다른 버튼을 막음")
	await paint(title)
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not title.squad.opened and not main.menu.opened, "뒤로 가기는 스쿼드 화면만 닫음")
	# The squad comes from the codex: whatever the developer's save holds, the check fills it in memory
	# (STELLARDEFENSE_NO_SAVE: nothing is written) with the hero it starts with, and puts it back after.
	var ids := ["brasa"]
	var codex: Dictionary = Save.seen_units.duplicate()
	Save.seen_units.erase("brasa")
	check(not main.start_hellbound(ids) and main.screen is TitleScreen and float(main.get("_fade_dir")) == 0.0,
		"도감에 없는 영웅으로는 Hellbound 를 시작하지 않음 (아무것도 안 함)")
	for id in ids: Save.seen_units[id] = true
	check(main.hellbound_ready(), "DLC 와 도감이 있으면 Hellbound 준비")
	check(main.start_hellbound(ids) and await wait_screen(main, "arena_screen", 1200) and Arena.hell, "Hellbound 시작")
	Arena.running = false
	Save.seen_units = codex
