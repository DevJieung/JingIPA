extends Harness

func _ready() -> void:
	if not require_no_save():
		return
	var original := I18n.locale
	_test_storage()
	_test_messages()
	await _test_controls()
	I18n.set_locale(original)
	finish("한영 언어·영웅정보 회귀 검사")


func _test_storage() -> void:
	var script := load("res://core/save.gd")
	var store = script.new()
	var path := "user://language-check-%d.cfg" % Time.get_ticks_usec()
	store.storage_path = path
	store.runs = 7
	store.set_language("en")
	var restored = script.new()
	restored.storage_path = path
	restored.load_file()
	check(restored.language == "en" and restored.runs == 7, "언어와 기존 기록 함께 저장/복구")
	restored.set_language("invalid")
	check(restored.language == "en", "지원하지 않는 언어 선택 거절")
	var file := ConfigFile.new()
	file.load(path)
	file.erase_section_key("opt", "language")
	file.save(path)
	restored.load_file()
	check(restored.language == "ko" and restored.runs == 7, "기존 저장은 한국어로 열고 기록 보존")
	file.set_value("opt", "language", "unknown")
	file.save(path)
	restored.load_file()
	check(restored.language == "ko", "알 수 없는 저장 언어는 한국어로 복구")
	store.free()
	restored.free()
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(path + suffix)


func _test_messages() -> void:
	I18n.set_locale("en")
	var examples := {
		"올인 디펜스": "All-in Defense",
		"이어하기 — 25탄": "Continue — Wave 25",
		"교체 (무료 3)": "Redraw (3 free)",
		"교체 123G": "Redraw 123G",
		"불 속성이 많이 등장합니다. 물 영웅을 준비하세요.": "Many Fire enemies ahead. Prepare Water heroes.",
		"명중 시 2.0초 동안 이동속도 22% 감소": "Hits slow by 22% for 2.0s",
		"명중 시 3.0초 화상 · 초당 타격 피해의 18%": "Burns for 3.0s · 18% of hit damage per second",
		"최고 25탄   ·   최고 족보 스트레이트 플러시   ·   만난 영웅 10 / 50": "Best: Wave 25   ·   Best hand: Straight Flush   ·   Heroes found: 10 / 50",
		"효과음  켜짐": "Sound  On",
		"배경음악  꺼짐": "Music  Off",
		"Lv 0 / 4 · 다음 2번": "Lv 0 / 4 · Next: 2 redraws",
		"능력치": "Upgrades",
		"선택됨": "Selected",
		"최종 획득 Gold": "Gold earned",
	}
	for source in examples:
		var result := I18n.t(source)
		check(result == examples[source], "영문 표시: %s -> %s" % [source, result])
		check(I18n.t(result) == result, "측정·그리기의 반복 번역 결과 유지")
	for unit in Roster.UNITS:
		check(I18n.hero_name(unit["id"]) == unit["en"], "영문 영웅 이름 " + unit["id"])
		check(not I18n.hero_concept(unit["id"]).is_empty(), "영문 컨셉 누락 " + unit["id"])
	for group in [Roster.MONSTERS, Roster.THEMES, Balance.UPGRADES, Balance.PASSIVES]:
		for entry in group:
			check(I18n._hangul.search(I18n.t(entry["ko"])) == null, "데이터 이름 번역 " + entry["ko"])
			if entry.has("desc"):
				check(I18n._hangul.search(I18n.t(entry["desc"])) == null, "데이터 설명 번역 " + entry["ko"])
	# Exercise every printf template with concrete numbers and a nested translated label.
	for source in I18n._catalog["en"]:
		var concrete := String(source)
		var tokens := I18n._placeholder.search_all(concrete)
		for index in range(tokens.size() - 1, -1, -1):
			var token: RegExMatch = tokens[index]
			var literal := token.get_string()
			var sample := "%" if literal == "%%" else "불" if literal.ends_with("s") else "12.5" if literal.ends_with("f") else "12"
			concrete = concrete.substr(0, token.get_start()) + sample + concrete.substr(token.get_end())
		var result := I18n.t(concrete)
		check(I18n._hangul.search(result) == null and not result.contains("{0}"), "문구 번역 누락: " + concrete + " -> " + result)
	I18n.set_locale("ko")
	check(I18n.t("THE LAST TABLE") == "최후의 테이블", "한국어 타이틀 부제")
	check(I18n.t("Next Stage") == "다음 전투", "한국어 다음 전투 표시")
	check(I18n.t("최종 획득 Gold") == "최종 획득 골드", "한국어 결과 골드 표시")
	check(I18n.t("Lv 0 / 4 · 다음 2번") == "0 / 4단계 · 다음 2번", "한국어 강화 단계 표기")
	for unit in Roster.UNITS:
		check(I18n.hero_name(unit["id"]) == unit["ko"], "한글 음차 이름 " + unit["id"])
		check(not I18n.hero_concept(unit["id"]).is_empty(), "한국어 컨셉 누락 " + unit["id"])


func _test_controls() -> void:
	var main: Node2D = load("res://game/main.gd").new()
	add_child(main)
	await paint(main.screen)
	await paint(main.menu)
	check(tap(main.menu, "language:en"), "공통 상단 Eng 선택")
	check(I18n.locale == "en" and Save.language == "en", "영어 선택 즉시 적용 및 설정 보존")
	check(get_window().title == "All-in Defense", "영문 창 이름 반영")
	await paint(main.menu)
	check(tap(main.menu, "language:en") and I18n.locale == "en", "선택된 영어를 다시 눌러도 영어 유지")
	await paint(main.screen)
	await paint(main.menu)
	check(tap(main.menu, "language:ko"), "공통 상단 Kor 선택")
	check(I18n.locale == "ko" and Save.language == "ko", "한국어 선택 즉시 적용")
	check(get_window().title == "올인 디펜스", "한국어 창 이름 반영")
	Fixture.prepare(12, 15092026)
	Run.phase = Run.Phase.SHOP
	main._swap(ShopScreen.new())
	var shop: ShopScreen = main.screen
	await paint(shop)
	check(tap(shop, "tab:f"), "대기실 배치 탭 진입")
	await paint(shop)
	check(tap(shop, "tab:i"), "대기실 영웅 정보 목록 진입")
	await paint(shop)
	check(tap(shop, "hv:f0"), "보유 영웅 상세 열기")
	await paint(shop)
	check(shop.hv.info == 0 and main.screen_modal_open(), "영웅 상세 모달 판정")
	var before := Run.snapshot().duplicate(true)
	main.menu.open()
	check(not main.menu.opened, "영웅 정보 위에 메뉴 중첩 금지")
	var next_zone := zone_of(shop, "next")
	if not next_zone.is_empty():
		mouse(shop, Rect2(next_zone["rect"]).get_center(), true)
	check(Run.snapshot() == before and main.screen == shop, "상세 모달 뒤 다음 전투 클릭 차단")
	# Click outside closes the modal; reopen and test the actual close control.
	shop.hv.info = 0
	await paint(shop)
	var close_at := Vector2.ZERO
	for zone in shop.ui.zones:
		if zone["id"] == "hv:close" and Rect2(zone["rect"]).size != Look.SCREEN.size:
			close_at = Rect2(zone["rect"]).get_center()
	check(close_at != Vector2.ZERO, "영웅 상세 닫기 버튼 존재")
	mouse(shop, close_at, true)
	mouse(shop, close_at, false)
	check(shop.hv.info == -1, "닫기 후 대기실 복귀")
	main.queue_free()
	await frames(2)
