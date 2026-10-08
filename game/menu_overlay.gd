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
	var tabs := [["menu", "메뉴"], ["rules", "플레이 방법"], ["rite", "별맞춤"], ["elements", "속성 상성표"]]
	for i in range(tabs.size()):
		ui.tab(self, Rect2(250 + i * 196, 176, 188, 44), tabs[i][1], "page:" + tabs[i][0], page == tabs[i][0], 21)
	match page:
		"rules":
			_draw_rules()
		"rite":
			_draw_rite()
		"elements":
			_draw_elements()
		_:
			_draw_menu()
	ui.button(self, Rect2(480, 644, 320, 54), "계속하기" if Run.running else "닫기", "resume", true, Look.GOLD, 26)
	_draw_languages(language_rect)


func _draw_menu() -> void:
	ui.button(self, Rect2(400, 252, 480, 54), "효과음  " + ("켜짐" if Save.sfx else "꺼짐"), "sound", true, Look.PANEL_EDGE, 24)
	ui.button(self, Rect2(400, 320, 480, 54), "배경음악  " + ("켜짐" if Save.music else "꺼짐"), "music", true, Look.PANEL_EDGE, 24)
	if Run.running:
		ui.button(self, Rect2(400, 414, 480, 54), "저장하고 타이틀로", "title", true, Look.CRYSTAL, 24)
		var hint := "전투 중 종료 시 이번 탄부터 다시 시작합니다." if Run.phase == Run.Phase.BATTLE else "별 자리와 구매 내역이 저장됩니다."
		Look.text_box(self, Rect2(290, 478, 700, 28), hint, 19, Look.INK_DIM)
	Look.text_center(self, Vector2(640, 602), "Esc  메뉴 열기 / 닫기   ·   Space  전투 일시정지", 18, Look.INK_DIM)
	if Save.last_error != OK:
		Look.text_center(self, Vector2(640, 560), "저장하지 못했습니다. 저장 공간을 확인하고 다시 눌러 주세요.", 20, Look.RED)
	elif Save.recovered_backup:
		Look.text_center(self, Vector2(640, 560), "이전 자동 저장에서 기록을 복구했습니다.", 20, Look.CRYSTAL)


func _draw_rules() -> void:
	var rows := [
		["01  별맞춤 의식", "수정을 도는 별 다섯이 멈춥니다 · 빛의 문 안에 든 별의 수가 곧 등급입니다"],
		["02  확정과 소환", "문 밖의 별만 다시 돌릴 수 있습니다 · 소환하면 그 등급의 영웅이 무작위로 등장합니다"],
		["03  편성과 합성", "5장 합성: 최고 재료보다 +0.5성 보장 · 합성 전용 각성 수호자"],
		["04  방어와 성장", "생명 수정 방어 · 전투 중간에 무료 소환 또는 영웅 승급 선택"],
	]
	for i in range(rows.size()):
		var y := 263.0 + i * 76.0
		Look.text_left(self, Vector2(260, y), rows[i][0], 24, Look.GOLD)
		Look.text_box(self, Rect2(260, y + 16, 758, 34), rows[i][1], 19, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_center(self, Vector2(640, 593), "유료 다시 돌리기 %d > %d > %dG…  ·  크리스탈 %d개  ·  총 %d탄"
			% [Balance.reroll_cost(0), Balance.reroll_cost(1), Balance.reroll_cost(2), Balance.MAX_LIVES, Balance.LAST_WAVE], 20, Look.CRYSTAL)


## 별맞춤 의식의 규칙 한 장 — 그림 하나, 규칙 넷, 그리고 **실제 값에서 뽑은** 확률.
##
## ★ 숫자를 손으로 적지 않는다. 문의 폭 · 등급 분포 · 무료 횟수 · 패시브 확률이 전부
##   Rite 와 Balance 에서 온다 — 밸런스가 문 너비를 다시 잡으면 이 표도 같이 바뀐다.
func _draw_rite() -> void:
	# 왼쪽 — 작은 의식판. 문 안에 별 셋이 선 3성의 예.
	var sample := 3
	RiteBoard.draw_still(self, Vector2(366, 364), 0.42, RiteBoard.sample_orbit(sample), float(Time.get_ticks_msec()) * 0.001, 0.62)
	Look.text_box(self, Rect2(250, 480, 232, 30), "문 안의 별 %d개 = %s" % [sample, Look.star_label(Rite.tier_of(sample))], 20, Look.GOLD)
	# 오른쪽 — 규칙 넷. 줄머리의 그림은 판 위의 바로 그 별들이다.
	var eye := roundi(Balance.PASSIVE_EYE_P * 100.0)
	var rows := [
		[RiteBoard.IN, "문 안의 별 = 등급", "빛의 문 안에 멈춘 별을 세면 됩니다 · 다섯이 다 들면 5성"],
		[RiteBoard.OUT, "문 밖의 별만 다시 돕니다", "문 안의 별은 잠깁니다 · 다시 돌려서 등급이 내려가지 않습니다"],
		[RiteBoard.HELD, "가장 안쪽 별은 수정이 붙듭니다", "언제나 문 안 · 최소 %s · 첫 의식은 별 %d개로 시작" % [Look.star_label(Rite.tier_of(Rite.MIN_STARS)), Balance.RITE_FIRST_STARS]],
		[-1, "별을 문 안으로 끌어오는 방법", "광고 · 조커: 가장 바깥 별 하나 · 도박꾼의 눈: %d%% 확률로 +0.5성" % eye],
	]
	for i in range(rows.size()):
		var y := 240.0 + i * 60.0
		var icon := Vector2(522, y + 26)
		if int(rows[i][0]) >= 0:
			RiteBoard.draw_star(self, icon, int(rows[i][0]), 0.86)
		else:
			Look.draw_reward_icon(self, icon, 13, Look.CRYSTAL)
		Look.text_box(self, Rect2(552, y + 2, 478, 28), String(rows[i][1]), 21, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
		Look.text_box(self, Rect2(552, y + 30, 478, 24), String(rows[i][2]), 16, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	# 아래 — 등급이 나올 확률. 첫 줄은 한 번 돌린 그대로, 둘째 줄은 무료 다시 돌리기를 다 쓴 뒤.
	var chances: PackedStringArray = []
	for ring in range(Rite.RINGS):
		chances.append("항상" if Rite.anchored(ring) else RiteBoard.percent(Rite.chance(ring)))
	Look.text_box(self, Rect2(250, 516, 780, 26), "별이 문에 들 확률(안쪽 별부터)  %s" % " · ".join(chances), 17, Look.CRYSTAL)
	var free := Run.free_rerolls()
	var table := [["한 번 돌렸을 때", Rite.odds(1)], ["무료 %d번 다시 돌린 뒤" % free, Rite.odds(1 + free)]]
	for star in range(Rite.MIN_STARS, Rite.MAX_STARS + 1):
		var tier := Rite.tier_of(star)
		Look.text_box(self, Rect2(478 + (star - 1) * 110, 546, 106, 26), Look.star_label(tier), 19, Look.tier_color(tier).lightened(0.15))
	for row in range(table.size()):
		var y := 574.0 + row * 30.0
		draw_rect(Rect2(250, y, 780, 28), Color(0, 0, 0, 0.22))
		Look.text_box(self, Rect2(262, y + 1, 208, 26), String(table[row][0]), 17, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		var odds: Array = table[row][1]
		for star in range(Rite.MIN_STARS, Rite.MAX_STARS + 1):
			Look.text_box(self, Rect2(478 + (star - 1) * 110, y + 1, 106, 26), RiteBoard.percent(float(odds[star])), 19, Look.INK)


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
