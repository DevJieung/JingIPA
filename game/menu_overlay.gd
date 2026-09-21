extends Node2D
class_name MenuOverlay

const ELEMENT_ROWS := ["water", "fire", "ice", "elec", "none"]

## 모든 화면에서 같은 메뉴를 쓴다. 화면의 처리와 입력을 함께 멈춘다.
var main: Node2D
var ui := Ui.new()
var opened := false
var page := "menu"
var _screen: Node2D
var _was_processing := false
var _was_input := false


func _process(_dt: float) -> void:
	queue_redraw()


func open() -> void:
	if Ads.busy or opened or main._fade_dir != 0.0 or main.screen == null or main.screen_modal_open():
		return
	opened = true
	page = "menu"
	_screen = main.screen
	_was_processing = _screen.is_processing()
	_was_input = _screen.is_processing_input()
	_screen.set_process(false)
	_screen.set_process_input(false)
	ui.begin()
	queue_redraw()


func close() -> void:
	if not opened:
		return
	opened = false
	if is_instance_valid(_screen) and _screen == main.screen:
		_screen.set_process(_was_processing)
		_screen.set_process_input(_was_input)
	ui.begin()
	queue_redraw()


func _input(e: InputEvent) -> void:
	if Ads.dismiss_notice_input(e):
		return
	if Ads.busy:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and ui.hit(e.position).begins_with("language:"):
		I18n.set_locale(ui.hit(e.position).get_slice(":", 1))
		main.screen.queue_redraw()
		queue_redraw()
		Sfx.play("button")
		get_viewport().set_input_as_handled()
		return
	if not opened and main.screen_modal_open():
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE or (e.keycode == KEY_SPACE and main.screen is BattleScreen and not Dbg.on):
			if opened:
				close()
			else:
				open()
			get_viewport().set_input_as_handled()
			return
	if opened:
		get_viewport().set_input_as_handled()
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var id := ui.hit(e.position)
	if id == "menu":
		open()
		get_viewport().set_input_as_handled()
	elif not opened:
		return
	elif id == "resume":
		close()
	elif id == "sound":
		Save.set_sfx(not Save.sfx)
	elif id == "music":
		Save.set_music(not Save.music)
	elif id.begins_with("page:"):
		page = id.substr(5)
	elif id == "title":
		# 전투 중에는 시작 체크포인트를 보존하고, 완료 보상은 이미 상점으로 저장돼 있다.
		Save._flush()
		if Save.last_error != OK:
			return
		close()
		Run.running = false
		main.go(main.show_title)
	Sfx.play("button")


func _draw() -> void:
	ui.begin()
	if main == null or main.screen == null or main._fade_dir != 0.0:
		return
	var language_rect := Hud.LANGUAGE_RECT
	if main.screen is TitleScreen or main.screen is OverScreen:
		language_rect.position.y = 24
	_draw_languages(language_rect)
	if not opened:
		var rect := Hud.MENU_RECT
		if main.screen is TitleScreen or main.screen is OverScreen:
			rect.position.y = 24
		ui.button(self, rect, "메뉴 / 도움말", "menu", not main.screen_modal_open(), Look.PANEL_EDGE, 20)
		return
	draw_rect(Look.SCREEN, Color(0.01, 0.02, 0.04, 0.85))
	Look.material_panel(self, Rect2(220, 86, 840, 638), Look.PANEL, Look.CRYSTAL)
	Look.text_center(self, Vector2(640, 136), "일시정지" if Run.running else "게임 안내", 38, Look.INK)
	var tabs := [["menu", "메뉴"], ["rules", "플레이 방법"], ["hands", "족보"], ["elements", "속성 상성표"]]
	for i in range(tabs.size()):
		ui.tab(self, Rect2(250 + i * 196, 176, 188, 44), tabs[i][1], "page:" + tabs[i][0], page == tabs[i][0], 21)
	match page:
		"rules":
			_draw_rules()
		"hands":
			_draw_hands()
		"elements":
			_draw_elements()
		_:
			_draw_menu()
	ui.button(self, Rect2(480, 644, 320, 54), "계속하기" if Run.running else "닫기", "resume", true, Look.GOLD, 26)
	_draw_languages(language_rect)


func _draw_menu() -> void:
	ui.button(self, Rect2(400, 262, 480, 56), "효과음  " + ("켜짐" if Save.sfx else "꺼짐"), "sound", true, Look.PANEL_EDGE, 25)
	ui.button(self, Rect2(400, 334, 480, 56), "배경음악  " + ("켜짐" if Save.music else "꺼짐"), "music", true, Look.PANEL_EDGE, 25)
	if Run.running:
		ui.button(self, Rect2(400, 410, 480, 56), "저장하고 타이틀로", "title", true, Look.CRYSTAL, 25)
		var hint := "전투 중 종료 시 이번 탄부터 다시 시작합니다." if Run.phase == Run.Phase.BATTLE else "카드와 구매 내역이 저장됩니다."
		Look.text_center(self, Vector2(640, 486), hint, 23, Look.INK_DIM)
	Look.text_center(self, Vector2(640, 538), "Esc  메뉴 열기 / 닫기   ·   Space  전투 일시정지", 21, Look.INK_DIM)
	if Save.last_error != OK:
		Look.text_center(self, Vector2(640, 588), "저장하지 못했습니다. 저장 공간을 확인하고 다시 눌러 주세요.", 20, Look.RED)
	elif Save.recovered_backup:
		Look.text_center(self, Vector2(640, 588), "이전 자동 저장에서 기록을 복구했습니다.", 20, Look.CRYSTAL)


func _draw_rules() -> void:
	var rows := [
		["01  카드 선택", "카드별 무료 교체 가능 · 금색 테두리: 족보에 포함된 카드"],
		["02  족보 확정", "영웅 1장 획득 · 같은 캐릭터는 전장에 1명만 출전"],
		["03  편성과 합성", "발판 12곳 모두 출전 · 영웅 카드 5장을 합쳐 새 영웅 획득"],
		["04  방어와 성장", "사거리 안의 가까운 적부터 공격 · 상점에서 강화와 패시브 구매"],
	]
	for i in range(rows.size()):
		var y := 263.0 + i * 76.0
		Look.text_left(self, Vector2(260, y), rows[i][0], 24, Look.GOLD)
		Look.text_box(self, Rect2(260, y + 16, 758, 34), rows[i][1], 19, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_center(self, Vector2(640, 593), "유료 교체 %d > %d > %dG…  ·  크리스탈 %d개  ·  총 %d탄"
			% [Balance.reroll_cost(0), Balance.reroll_cost(1), Balance.reroll_cost(2), Balance.MAX_LIVES, Balance.LAST_WAVE], 20, Look.CRYSTAL)


func _draw_hands() -> void:
	var examples := ["다른 족보가 없는 패", "같은 숫자 2장", "같은 숫자 2장씩 두 쌍", "같은 숫자 3장", "연속 5장 · A는 1 또는 14", "같은 무늬 5장", "같은 숫자 3장 + 2장", "같은 숫자 4장", "연속 숫자 + 같은 무늬", "10 · J · Q · K · A + 같은 무늬"]
	for i in range(10):
		var tier := 9 - i
		var x := 264.0 + (i / 5) * 388.0
		var y := 265.0 + (i % 5) * 69.0
		Look.draw_rarity(self, Vector2(x + 30, y), tier, 4.5)
		Look.text_box(self, Rect2(x + 72, y - 16, 300, 32), Poker.HAND_KO[tier], 22, Look.tier_color(tier), HORIZONTAL_ALIGNMENT_LEFT)
		Look.text_box(self, Rect2(x, y + 13, 372, 30), examples[tier], 18, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_elements() -> void:
	Look.text_center_fit(self, Vector2(339, 248), "캐릭터 속성 ↓", 21, Look.GOLD, 164, 19)
	Look.text_center(self, Vector2(724, 248), "몬스터 속성 →", 21, Look.GOLD)
	draw_rect(Rect2(256, 270, 166, 64), Look.BG_DEEP)
	Look.text_center(self, Vector2(339, 302), "피해 배율", 20, Look.INK_DIM)
	for column in range(Balance.MBODY_ORDER.size()):
		var x := 424.0 + column * 120.0
		var body := String(Balance.MBODY_ORDER[column])
		var color := Balance.body_color(body)
		draw_rect(Rect2(x, 270, 118, 64), Look.BG_DEEP.lerp(color, 0.14))
		Look.draw_body(self, Vector2(x + 59, 289), 14, body)
		Look.text_center(self, Vector2(x + 59, 316), Balance.body_ko(body), 20, Look.INK)
	for row in range(ELEMENT_ROWS.size()):
		var y := 338.0 + row * 49.0
		var element := String(ELEMENT_ROWS[row])
		draw_rect(Rect2(256, y, 166, 47), Look.hero_card_face(element))
		Look.draw_elem(self, Vector2(281, y + 23.5), 16, element)
		Look.text_center_fit(self, Vector2(357, y + 23.5), Balance.elem_ko(element), 22, Look.INK, 114, 20)
		for column in range(Balance.MBODY_ORDER.size()):
			var mult := Balance.elem_mult(element, String(Balance.MBODY_ORDER[column]))
			var color := _element_mult_color(mult)
			var rect := Rect2(424.0 + column * 120.0, y, 118, 47)
			draw_rect(rect, Look.BG_DEEP.lerp(color, 0.13 if mult != 1.0 else 0.025))
			Look.text_center(self, rect.get_center(), _element_mult_label(mult), 26, color)
	var legend := [[Balance.ELEM_WEAK, "약점"], [1.0, "보통"], [Balance.ELEM_RESIST, "반감"], [Balance.ELEM_IMMUNE, "무효"]]
	for i in range(legend.size()):
		var x := 256.0 + i * 194.0
		var mult := float(legend[i][0])
		Look.text_left(self, Vector2(x + 8, 610), _element_mult_label(mult), 21, _element_mult_color(mult))
		Look.text_left(self, Vector2(x + 84, 610), String(legend[i][1]), 19, Look.INK_DIM)


func _element_mult_label(mult: float) -> String:
	return "%s배" % ("%.1f" % mult if not is_equal_approx(mult, roundf(mult)) else "%d" % int(mult))


func _element_mult_color(mult: float) -> Color:
	if is_zero_approx(mult):
		return Look.RED.lerp(Look.INK, 0.42)
	if mult < 1.0:
		return Look.DMG_RESIST.lerp(Look.INK, 0.38)
	return Look.DMG_WEAK if mult > 1.0 else Look.DMG_NORMAL


func _draw_languages(rect: Rect2) -> void:
	for index in range(2):
		var code := "ko" if index == 0 else "en"
		var button_rect := Rect2(rect.position + Vector2(index * 76, 0), Vector2(68, rect.size.y))
		var selected := I18n.locale == code
		ui.button(self, button_rect, "KOR" if code == "ko" else "ENG", "language:" + code,
				not Ads.busy, Look.GOLD if selected else Look.PANEL_EDGE, 20)
		if selected:
			draw_rect(Rect2(button_rect.position + Vector2(19, button_rect.size.y - 9), Vector2(30, 3)), Look.BG_DEEP)
