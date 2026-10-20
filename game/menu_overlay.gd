extends Node2D
class_name MenuOverlay

const ELEMENT_ROWS := ["water", "fire", "ice", "elec", "none"]
## The chart's columns (monster bodies). The three bodies that share a name with an attack
## come first, in the rows' order, so same-named types meet on the diagonal the way a
## Pokémon type chart reads (water on water, fire on fire, ice on ice: all resisted). Then
## the two bodies no attack is named after: wood, and rock — the Ground body of the
## 2026-10-19 table (C, 「대지」 / "Ground") — whose one immunity (lightning) closes the
## lightning row. A local order on purpose: Balance.MBODY_ORDER seeds the stage shuffle
## and sorts the stage card, so it must not move. A body the table adds later follows.
const ELEMENT_COLUMNS := ["aqua", "flame", "frost", "wood", "rock"]
## The body each attack shares its name with (the chart's footnote checks these pairs).
const SAME_KIND := {"water": "aqua", "fire": "flame", "ice": "frost"}
## The guide's sheet.
const SHEET := Rect2(220, 86, 840, 638)
## The jewel-box art's closed box of each grade (D1, art/ui/box/tier<n>/closed.png). The box
## page shows grades 1, 3 and 5 climbing; without the art it draws a casket of its own.
const BOX_ART := "res://art/ui/box/tier%d/closed.png"
const BOX_ART_TIERS := [1, 3, 5]
## How long the quit button waits for its confirming second tap (seconds).
const QUIT_CONFIRM_SECONDS := 3.0

## 모든 화면에서 같은 메뉴를 쓴다. 화면의 처리와 입력을 함께 멈춘다.
var main: Node2D
var ui := Ui.new()
var opened := false
## The open tab. Setting it redraws: the overlay no longer redraws every frame.
var page: String = "menu":
	set(value):
		page = value
		queue_redraw()
var _screen: Node2D
var _was_processing := false
var _was_input := false
## What the overlay showed when it last drew (see _state_key).
var _drawn_key: Array = []
## When the quit button was first tapped; a second tap within QUIT_CONFIRM_SECONDS quits.
var _quit_at := -100.0
static var _box_art: Dictionary = {}


func _ready() -> void:
	I18n.language_changed.connect(_on_language)


## O8 (heat): the overlay used to queue a redraw on every frame of the game, open or not.
## Now it draws again only when what it shows has changed (_state_key), when the language
## changes, when its page changes, and on input.
func _process(_dt: float) -> void:
	var key := _state_key()
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _on_language(_code: String) -> void:
	queue_redraw()


## Everything the picture depends on besides the overlay's own input: the screen under it,
## a running transition, whether that screen has a modal up (the button greys out), the
## boot cover, the language, the page and the settings the menu page shows.
func _state_key() -> Array:
	if main == null or not is_instance_valid(main.screen):
		return [0]
	return [main.screen.get_instance_id(), main._fade_dir != 0.0, main.screen_modal_open(), main.get("interactive"),
		I18n.locale, opened, page, main.active_run().running, Save.sfx, Save.music, Save.fps,
		Save.last_error, Save.recovered_backup, _quit_armed()]


func open() -> void:
	if opened or main._fade_dir != 0.0 or main.screen == null or main.screen_modal_open():
		return
	opened = true
	page = "menu"
	ArenaHelp.page = 0
	_quit_at = -100.0
	_screen = main.screen
	_was_processing = _screen.is_processing()
	_was_input = _screen.is_processing_input()
	_screen.set_process(false)
	_screen.set_process_input(false)
	# O8: while the menu covers the battlefield, its 3D view keeps the last picture.
	_set_view_live(false)
	ui.begin()
	queue_redraw()


func close() -> void:
	if not opened:
		return
	opened = false
	if is_instance_valid(_screen) and _screen == main.screen:
		_screen.set_process(_was_processing)
		_screen.set_process_input(_was_input)
		# Back to rendering every frame only if nothing else still covers the battle.
		if _screen is ArenaScreen:
			_set_view_live(Arena.modal.is_empty() and not _screen.store.opened)
	ui.begin()
	queue_redraw()


## The battlefield's 3D view renders every frame only while live (ArenaView.set_live, LB2a).
func _set_view_live(on: bool) -> void:
	if not (_screen is ArenaScreen):
		return
	var view: Variant = _screen.get("view_3d")
	if view is Object and is_instance_valid(view) and (view as Object).has_method("set_live"):
		view.set_live(on)


func _input(e: InputEvent) -> void:
	# Under the boot loading cover nothing here answers (F8, main.interactive).
	if main == null or main.get("interactive") == false:
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
		if e.keycode == KEY_ESCAPE or (e.keycode == KEY_SPACE and (main.screen is BattleScreen or main.screen is ArenaScreen) and not Dbg.on):
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
	# Any other tap takes back a half-done quit.
	var quit_armed := _quit_armed()
	_quit_at = -100.0
	if id == "menu":
		open()
		get_viewport().set_input_as_handled()
	elif not opened:
		return
	elif id == "quit":
		# Android's back button no longer quits (quit_on_go_back = false), so the title's
		# menu offers it — the second tap confirms.
		if quit_armed and _can_quit():
			get_tree().quit()
			return
		_quit_at = Time.get_ticks_msec() * 0.001
	elif id == "resume":
		close()
	elif id == "sound":
		Save.set_sfx(not Save.sfx)
	elif id == "music":
		Save.set_music(not Save.music)
	elif id.begins_with("fps:"):
		# 30 / 60: Main stores Save.fps and applies the cap at once (LB2a).
		if main.has_method("set_fps"):
			main.set_fps(int(id.get_slice(":", 1)))
	elif id.begins_with("page:"):
		page = id.substr(5)
	elif id.begins_with("help:page:"):
		# The rules' own pages, when even 16 px does not fit them on one (ArenaHelp).
		ArenaHelp.page = maxi(0, ArenaHelp.page + int(id.get_slice(":", 2)))
	elif id == "title":
		# 전투 중에는 시작 체크포인트를 보존하고, 완료 보상은 이미 상점으로 저장돼 있다.
		Save._flush()
		if Save.last_error != OK:
			return
		close()
		main.active_run().running = false
		main.go(main.show_title)
	queue_redraw()
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
		if _glass():
			ui.glass_button(self, rect, "메뉴 / 도움말", "menu", not main.screen_modal_open(), Look.STEEL, 20)
		else:
			ui.button(self, rect, "메뉴 / 도움말", "menu", not main.screen_modal_open(), Look.PANEL_EDGE, 20)
		return
	draw_rect(Look.SCREEN, Look.SHADE)
	Look.sheet(self, SHEET, Look.STEEL)
	Look.text_center(self, Vector2(640, 136), "일시정지" if main.active_run().running else "게임 안내", Look.TYPE_TITLE, Look.GOLD)
	var shown := _page_shown()
	var tabs := _tabs()
	for i in range(tabs.size()):
		ui.tab(self, Rect2(250 + i * 196, 176, 188, 44), tabs[i][1], "page:" + tabs[i][0], shown == tabs[i][0], 21)
	match shown:
		"rules":
			_draw_rules()
		"box":
			_draw_box()
		"rite":
			_draw_rite()
		"elements":
			_draw_elements()
		_:
			_draw_menu()
	ui.button(self, Rect2(480, 644, 320, 54), "계속하기" if main.active_run().running else "닫기", "resume", true, Look.GOLD, Look.TYPE_BUTTON)
	_draw_languages(language_rect)


## The title and the battlefield share the chamfered glass of the HUD; the legacy
## screens keep their bevelled buttons.
func _glass() -> bool:
	return main.screen is ArenaScreen or main.screen is TitleScreen


## The guide's tabs. The title and the battlefield explain the jewel box (2026-10-19, F10);
## the legacy wave screens keep the star rite they still use.
func _tabs() -> Array:
	return [["menu", "메뉴"], ["rules", "플레이 방법"], ["box", "보석상자"] if _glass() else ["rite", "별맞춤"], ["elements", "속성 상성표"]]


## The page to draw. "box" and "rite" name the same third tab (older capture tools still
## ask for "rite"); the screen decides which of the two it is.
func _page_shown() -> String:
	if page in ["box", "rite"]:
		return "box" if _glass() else "rite"
	return page


func _draw_menu() -> void:
	ui.button(self, Rect2(400, 240, 480, 54), "효과음  " + ("켜짐" if Save.sfx else "꺼짐"), "sound", true, Look.PANEL_EDGE, 24)
	ui.button(self, Rect2(400, 302, 480, 54), "배경음악  " + ("켜짐" if Save.music else "꺼짐"), "music", true, Look.PANEL_EDGE, 24)
	_draw_fps(Rect2(400, 364, 480, 54))
	if main.active_run().running:
		ui.button(self, Rect2(400, 462, 480, 54), "저장하고 타이틀로", "title", true, Look.CRYSTAL, 24)
		var hint := "전투 중 종료 시 이번 탄부터 다시 시작합니다." if main.active_run().phase == Run.Phase.BATTLE else "별 자리와 구매 내역이 저장됩니다."
		if main.screen is ArenaScreen:
			hint = Arena.label("arena.save_hint")
		Look.text_box(self, Rect2(290, 522, 700, 28), hint, 19, Look.INK_DIM)
	elif _can_quit():
		var armed := _quit_armed()
		# "menu.quit" is a key: the Korean words 「게임 종료」 already translate as "Game Over".
		ui.button(self, Rect2(400, 462, 480, 54), "종료 확인" if armed else "menu.quit", "quit", true, Look.WARN if armed else Look.PANEL_EDGE, 24)
		if armed:
			Look.text_box(self, Rect2(290, 522, 700, 28), "한 번 더 누르면 게임을 종료합니다.", 19, Look.WARN)
	# Keys only where there is a keyboard; phones have the back button instead.
	if not OS.has_feature("mobile"):
		Look.text_box(self, Rect2(270, 591, 740, 26), "Esc 키로 메뉴를 열고 닫습니다. 전투 중에는 Space 키로도 일시정지할 수 있습니다.", Look.TYPE_CAPTION, Look.INK_DIM)
	if Save.last_error != OK:
		Look.text_center(self, Vector2(640, 570), "저장하지 못했습니다. 저장 공간을 확인하고 다시 눌러 주세요.", 20, Look.RED)
	elif Save.recovered_backup:
		Look.text_center(self, Vector2(640, 570), "이전 자동 저장에서 기록을 복구했습니다.", 20, Look.CRYSTAL)


## Quitting is offered on the title's menu only (a running battle saves and goes to the
## title instead), and never on iOS, where apps do not quit themselves.
func _can_quit() -> bool:
	return not main.active_run().running and OS.get_name() != "iOS"


func _quit_armed() -> bool:
	return Time.get_ticks_msec() * 0.001 - _quit_at < QUIT_CONFIRM_SECONDS


## Frame rate (O8): the choices side by side on one plate, the current one in gold like
## the battle's speed chips. The battle runs at this cap; every still screen runs at 30
## (Main.refresh_render_budget). Phones start at 30.
func _draw_fps(rect: Rect2) -> void:
	var on: bool = main.has_method("set_fps")
	var face := Rect2(rect.position, rect.size - Vector2(0, 3))
	Look.fill_round(self, rect, 7, Look.BG_DEEP)
	Look.fill_round(self, face, 7, Look.PANEL_EDGE)
	Look.fill_round(self, face.grow(-1.5), 6, Look.BG_DEEP.lerp(Look.PANEL, 0.62))
	var choices: Array = Save.FPS_CHOICES
	var chip_w := 112.0
	var gap := 8.0
	var chips_x := face.end.x - 7.0 - float(choices.size()) * chip_w - float(choices.size() - 1) * gap
	Look.text_box(self, Rect2(face.position.x + 20, face.position.y + 2, chips_x - face.position.x - 32, face.size.y - 4), "화면 프레임", 24, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	for i in range(choices.size()):
		var value := int(choices[i])
		var chip := Rect2(chips_x + float(i) * (chip_w + gap), face.position.y + 6, chip_w, face.size.y - 10)
		ui.button(self, chip, "%d FPS" % value, "fps:%d" % value, on, Look.GOLD if value == Save.fps else Look.PANEL_EDGE, 21)
	Look.text_box(self, Rect2(290, rect.end.y + 4, 700, 24), "%d프레임으로 두면 발열과 배터리 소모가 줄어듭니다." % int(choices.min()), Look.TYPE_CAPTION, Look.INK_DIM)


func _draw_rules() -> void:
	# The run's rules on the battlefield and on the title (the title starts that run).
	if _glass():
		ArenaScreen.draw_help(self)
		return
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


## 보석상자 — the summon's rules as full sentences (O11), a small box, and the grade odds.
## The words follow the box itself (D1): 「다시 뽑기」 / redraw.
##
## ★ No number is written by hand: the card count, the free redraws (base and DLC), the
##   first box's floor and the box price come from Balance, the odds from JewelBox (the
##   weights Balance.ARENA_BOX_P* / ARENA_CARD_P*), so a retune redraws this page too.
func _draw_box() -> void:
	var cards := Balance.ARENA_BOX_CARDS
	var rows := [
		["cards", "영웅 %d명 중 1명 선택" % cards,
			"상자를 열면 영웅 %d명이 나옵니다. 그중 1명은 상자 등급 이상이 보장되고, 나머지 %d명은 무작위라 더 높은 등급일 수도 있습니다." % [cards, cards - 1]],
		["grade", "상자 등급",
			"상자 등급은 열 때 무작위로 정해집니다. 다시 뽑으면 상자 등급을 다시 굴려 더 높은 등급을 노리며, 등급은 내려가지 않습니다."],
		["reroll", "무료 다시 뽑기",
			"무료 다시 뽑기는 상자마다 기본 %d번이고, DLC가 있으면 %d번입니다. 별자리 보너스는 그 위에 더해집니다." % [Balance.FREE_REROLL, Balance.ARENA_DLC_FREE_REROLL]],
		["free", "첫 상자는 무료",
			"스테이지의 첫 상자는 무료이며 최소 %s입니다. 그다음 상자는 %d G에서 시작해 열 때마다 %d G씩 오릅니다."
			% [Look.star_label(JewelBox.tier_of(Balance.ARENA_BOX_FIRST_TIER)), Balance.ARENA_SUMMON_COST, Balance.ARENA_SUMMON_COST_STEP]],
	]
	# The box and its grade range on the left; the first two rules beside it, the other two
	# across the page under it.
	var art := Rect2(252, 236, 180, 136)
	_draw_box_art(art)
	var range_label := I18n.t(Look.star_label(JewelBox.tier_of(1))) + " ~ " + I18n.t(Look.star_label(JewelBox.tier_of(JewelBox.MAX_STARS)))
	Look.text_box(self, Rect2(art.position.x, art.end.y + 2, art.size.x, 26), range_label, 18, Look.GOLD)
	var y := 234.0
	for i in range(rows.size()):
		var x := 452.0 if i < 2 else 252.0
		if i == 2:
			y = maxf(y, art.end.y + 36.0)
		y += _draw_box_rule(Rect2(x, y, 1030.0 - x, 0), rows[i]) + 10.0
	# Grade odds: the box's grade, then each of the other cards.
	var table := [["상자 등급", JewelBox.grade_odds()], ["나머지 %d명" % (cards - 1), JewelBox.odds(Balance.arena_card_weights())]]
	var row_h := 26.0
	var top := maxf(y + 2.0, 632.0 - 24.0 - row_h * float(table.size()))
	Look.text_box(self, Rect2(262, top, 200, 24), "등급 확률", 17, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	for star in range(1, JewelBox.MAX_STARS + 1):
		var tier := JewelBox.tier_of(star)
		Look.text_box(self, Rect2(478 + (star - 1) * 110, top, 106, 24), Look.star_label(tier), 18, Look.tier_color(tier).lightened(0.15))
	for row in range(table.size()):
		var ry := top + 24.0 + float(row) * row_h
		draw_rect(Rect2(252, ry + 1, 778, row_h - 2), Color(0, 0, 0, 0.22))
		Look.text_box(self, Rect2(262, ry + 1, 208, row_h - 2), String(table[row][0]), 16, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		var odds: Array = table[row][1]
		for star in range(1, JewelBox.MAX_STARS + 1):
			Look.text_box(self, Rect2(478 + (star - 1) * 110, ry + 1, 106, row_h - 2), RiteBoard.percent(float(odds[star - 1])), 18, Look.INK)


## One rule of the box page: its mark, a short heading, then the full sentence (16 px,
## wrapped). Returns the height it took. `area.size.y` is ignored.
func _draw_box_rule(area: Rect2, rule: Array) -> float:
	var body_x := area.position.x + 40.0
	var body_w := area.end.x - body_x
	var body := String(rule[2])
	var lines := Look.wrapped_lines(body, body_w, Look.TYPE_CAPTION).size()
	var body_h := float(lines) * Look.line_height(Look.TYPE_CAPTION)
	_box_mark(Vector2(area.position.x + 16, area.position.y + 14), String(rule[0]))
	Look.text_box(self, Rect2(body_x, area.position.y, body_w, 28), String(rule[1]), 20, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	Look.wrap_text(self, body, Rect2(body_x, area.position.y + 28, body_w, body_h), Look.TYPE_CAPTION, Look.INK_DIM, true)
	return 28.0 + body_h


## Marks of the box rules: a fan of cards with the guaranteed one lit, a star that climbs,
## the reroll (the store's mark), and a coin struck through (the free first box).
func _box_mark(at: Vector2, kind: String) -> void:
	match kind:
		"cards":
			for i in [0, 4, 1, 3, 2]:
				var offset := float(i - 2)
				draw_set_transform(at + Vector2(offset * 5.6, 3.0 + absf(offset) * 1.4), offset * 0.20, Vector2.ONE)
				var card := Rect2(-5.0, -10.0, 10.0, 15.0)
				Look.fill_round(self, card.grow(1.2), 2, Look.BG_DEEP)
				Look.fill_round(self, card, 2, Look.GOLD if i == 2 else Look.STEEL.darkened(0.25))
				if i == 2:
					draw_colored_polygon(Look.star_points(Vector2(0, -2.5), 3.6), Look.BG_DEEP)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"grade":
			draw_colored_polygon(Look.star_points(at + Vector2(-3, 2), 9.0), Look.STARLIGHT)
			draw_line(at + Vector2(9, 9), at + Vector2(9, -7), Look.GOLD, 2.0, true)
			draw_colored_polygon(PackedVector2Array([at + Vector2(9, -11), at + Vector2(4.5, -5), at + Vector2(13.5, -5)]), Look.GOLD)
		"reroll":
			StoreView.draw_fact_glyph(self, at, "reroll", Look.GOLD, 1.05)
		_:
			StoreView.draw_fact_glyph(self, at, "coin", Look.GOLD, 1.05)
			draw_line(at + Vector2(-9, 9), at + Vector2(9, -9), Look.BG_DEEP, 4.0, true)
			draw_line(at + Vector2(-9, 9), at + Vector2(9, -9), Look.GREEN, 2.0, true)


## The jewel box: the art's closed boxes of grades 1, 3 and 5, each larger and in front of
## the last (the grade climbs), over a warm light; without the art, a drawn casket of the
## game's night-and-gold with a cut jewel on its seam.
func _draw_box_art(rect: Rect2) -> void:
	var boxes: Array = []
	for tier in BOX_ART_TIERS:
		var texture := _box_texture(int(tier))
		if texture != null:
			boxes.append(texture)
	if boxes.size() == BOX_ART_TIERS.size():
		var glow := rect.get_center() + Vector2(14, 6)
		var fan := PackedVector2Array([glow])
		var tones := PackedColorArray([Color(Look.GOLD, 0.18)])
		for i in range(33):
			fan.append(glow + Vector2.from_angle(TAU * float(i) / 32.0) * Vector2(112, 78))
			tones.append(Color(Look.GOLD, 0.0))
		draw_polygon(fan, tones)
		var heights := [54.0, 74.0, 100.0]
		var centres := [rect.position.x + 30.0, rect.position.x + 82.0, rect.position.x + 140.0]
		for i in range(boxes.size()):
			var texture: Texture2D = boxes[i]
			var height: float = heights[i]
			var size := Vector2(height * texture.get_width() / float(texture.get_height()), height)
			var foot := Vector2(float(centres[i]), rect.end.y - 4.0 + float(i) * 2.0)
			draw_set_transform(foot + Vector2(0, -3), 0.0, Vector2(1.0, 0.22))
			draw_circle(Vector2.ZERO, size.x * 0.44, Color(0, 0, 0, 0.35), true, -1, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_texture_rect(texture, Rect2(foot - Vector2(size.x * 0.5, size.y), size), false)
		return
	var c := rect.get_center()
	var w := minf(rect.size.x * 0.36, 64.0)
	# A soft warm light behind the box (one fan: no rings).
	var glow_at := c + Vector2(0, -10)
	var fan := PackedVector2Array([glow_at])
	var tones := PackedColorArray([Color(Look.GOLD, 0.20)])
	for i in range(33):
		fan.append(glow_at + Vector2.from_angle(TAU * float(i) / 32.0) * Vector2(w * 1.55, w * 1.20))
		tones.append(Color(Look.GOLD, 0.0))
	draw_polygon(fan, tones)
	# Casket: a low lid over a deeper body, gold corners and bands, the jewel on the seam.
	var seam := c.y - w * 0.02
	var body := Rect2(c.x - w, seam, w * 2.0, w * 0.92)
	var lid := PackedVector2Array()
	for i in range(17):
		var a := PI + PI * float(i) / 16.0
		lid.append(Vector2(c.x + cos(a) * w * 1.04, seam - 2.0 + sin(a) * w * 0.44))
	lid.append(Vector2(c.x + w * 1.04, seam))
	lid.append(Vector2(c.x - w * 1.04, seam))
	var velvet := Look.NIGHT.lerp(Color("#3d2a5c"), 0.70)
	Look.fill_round(self, body.grow(2.5), 6, Look.GOLD_DEEP)
	Look.fill_round(self, body, 5, velvet)
	Look.gradient_rect(self, Rect2(body.position + Vector2(3, 3), Vector2(body.size.x - 6, body.size.y * 0.45)), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0), true)
	draw_colored_polygon(lid, velvet.lightened(0.10))
	lid.append(lid[0])
	draw_polyline(lid, Look.GOLD_DEEP, 3.4, true)
	draw_polyline(lid, Look.GOLD, 1.5, true)
	for side in [-1.0, 1.0]:
		var band_x: float = c.x + side * w * 0.60
		var lid_top: float = seam - 2.0 - sqrt(maxf(0.0, 1.0 - pow(side * 0.60 / 1.04, 2.0))) * w * 0.44
		draw_line(Vector2(band_x, lid_top + 1.0), Vector2(band_x, body.end.y), Look.GOLD_DEEP, 7.0, true)
		draw_line(Vector2(band_x, lid_top + 1.0), Vector2(band_x, body.end.y), Look.GOLD, 3.6, true)
		var corner := Vector2(c.x + side * w, body.end.y)
		draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(-side * 13.0, 0), corner + Vector2(0, -13.0)]), Look.GOLD)
	draw_line(Vector2(body.position.x - 2.0, seam), Vector2(body.end.x + 2.0, seam), Look.GOLD, 2.2, true)
	var jewel := Vector2(c.x, seam + 1.0)
	draw_circle(jewel, w * 0.33, Look.GOLD_DEEP, true, -1, true)
	draw_circle(jewel, w * 0.29, Look.BG_DEEP, true, -1, true)
	draw_arc(jewel, w * 0.29, 0, TAU, 28, Look.GOLD, 1.4, true)
	StoreView.draw_gem(self, jewel + Vector2(0, -1), w * 0.22, Look.STARLIGHT)
	for spark in [[Vector2(-1.22, -0.70), 5.5], [Vector2(1.10, -0.95), 7.0], [Vector2(1.34, -0.12), 4.0]]:
		_sparkle(c + Vector2(spark[0]) * w, float(spark[1]), Look.STARLIGHT)


func _sparkle(at: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.24, -r * 0.24), at + Vector2(r, 0),
		at + Vector2(r * 0.24, r * 0.24), at + Vector2(0, r), at + Vector2(-r * 0.24, r * 0.24), at + Vector2(-r, 0),
		at + Vector2(-r * 0.24, -r * 0.24)]), color)


## The closed box of `tier`, sampled through mipmaps: the 400 px render is shown at a sixth
## of its size (the same exception the monster and hero portraits make to the canvas's
## Nearest default). Null without the art.
static func _box_texture(tier: int) -> Texture2D:
	if not _box_art.has(tier):
		var texture: Texture2D = null
		var path := BOX_ART % tier
		if ResourceLoader.exists(path):
			var source: Texture2D = load(path)
			var image := source.get_image() if source != null else null
			if image != null and not image.is_empty():
				if image.is_compressed():
					image.decompress()
				image.generate_mipmaps()
				var filtered := CanvasTexture.new()
				filtered.diffuse_texture = ImageTexture.create_from_image(image)
				filtered.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				texture = filtered
		_box_art[tier] = texture
	return _box_art[tier]


## 별맞춤 의식의 규칙 한 장 — 그림 하나, 규칙 셋, 그리고 **실제 값에서 뽑은** 확률.
## (The legacy wave screens only; the title and the battlefield show the jewel box.)
##
## ★ 숫자를 손으로 적지 않는다. 문의 폭 · 등급 분포 · 무료 횟수 · 패시브 확률이 전부
##   Rite 와 Balance 에서 온다 — 밸런스가 문 너비를 다시 잡으면 이 표도 같이 바뀐다.
func _draw_rite() -> void:
	# 왼쪽 — 작은 의식판. 문 안에 별 셋이 선 3성의 예.
	var sample := 3
	RiteBoard.draw_still(self, Vector2(366, 364), 0.42, RiteBoard.sample_orbit(sample), float(Time.get_ticks_msec()) * 0.001, 0.62)
	Look.text_box(self, Rect2(250, 480, 232, 30), "문 안의 별 %d개 = %s" % [sample, Look.star_label(Rite.tier_of(sample))], 20, Look.GOLD)
	# 오른쪽 — 규칙 셋. 줄머리의 그림은 판 위의 바로 그 별들이다.
	var rows := [
		[RiteBoard.IN, "문 안의 별 = 등급", "빛의 문 안에 멈춘 별을 세면 됩니다 · 다섯이 다 들면 5성"],
		[RiteBoard.OUT, "문 밖의 별만 다시 돕니다", "문 안의 별은 잠깁니다 · 다시 돌려서 등급이 내려가지 않습니다"],
		[RiteBoard.HELD, "가장 안쪽 별은 수정이 붙듭니다", "언제나 문 안 · 최소 %s · 첫 의식은 별 %d개로 시작" % [Look.star_label(Rite.tier_of(Rite.MIN_STARS)), Balance.RITE_FIRST_STARS]],
	]
	for i in range(rows.size()):
		var y := 240.0 + i * 60.0
		var icon := Vector2(522, y + 26)
		RiteBoard.draw_star(self, icon, int(rows[i][0]), 0.86)
		Look.text_box(self, Rect2(552, y + 2, 478, 28), String(rows[i][1]), 21, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
		Look.text_box(self, Rect2(552, y + 30, 478, 24), String(rows[i][2]), 16, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	# 아래 — 등급이 나올 확률. 첫 줄은 한 번 돌린 그대로, 둘째 줄은 무료 다시 돌리기를 다 쓴 뒤.
	var chances: PackedStringArray = []
	for ring in range(Rite.RINGS):
		chances.append("항상" if Rite.anchored(ring) else RiteBoard.percent(Rite.chance(ring)))
	Look.text_box(self, Rect2(250, 516, 780, 26), "별이 문에 들 확률(안쪽 별부터)  %s" % " · ".join(chances), 17, Look.CRYSTAL)
	var free: int = main.active_run().free_rerolls()
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


## The element chart (O6/B2, 2026-10-19): rows attack, columns defend, read like a Pokémon
## type chart. No axis words (the tester found them in the way); the corner says what a
## cell is and draws the direction as the two marks the headers use — attack circle →
## body square. Same-named types meet on the diagonal (ELEMENT_COLUMNS). 2x, 0.5x and 0x
## stand out, 1x stays quiet. Every cell is Balance.elem_mult, so a new table (the C
## table: 「대지」 for rock, two cells back to 1x) shows itself, and the legend lists only
## the multipliers the chart actually holds.
func _draw_elements() -> void:
	var columns := _chart_columns()
	var count := columns.size()
	var left := 256.0
	var head_w := 166.0
	var gap := 2.0
	var cell_w := floorf((766.0 - head_w - gap * float(count)) / float(count))
	var top := 236.0
	var head_h := 60.0
	var row_h := 50.0
	var grid_x := left + head_w + gap
	var corner := Rect2(left, top, head_w, head_h)
	draw_rect(corner, Look.BG_DEEP)
	Look.text_center_fit(self, corner.position + Vector2(head_w * 0.5, 21), "피해 배율", 19, Look.INK_DIM, head_w - 16, 14)
	_draw_direction(corner.position + Vector2(head_w * 0.5, 44))
	for c in range(count):
		var body := String(columns[c])
		var x := grid_x + float(c) * (cell_w + gap)
		draw_rect(Rect2(x, top, cell_w, head_h), Look.BG_DEEP.lerp(Balance.body_color(body), 0.14))
		Look.draw_body(self, Vector2(x + cell_w * 0.5, top + 19), 13, body)
		Look.text_center_fit(self, Vector2(x + cell_w * 0.5, top + 45), _body_name(body), 20, Look.INK, cell_w - 10, 14)
	var present := {}
	for r in range(ELEMENT_ROWS.size()):
		var element := String(ELEMENT_ROWS[r])
		var y := top + head_h + 4.0 + float(r) * (row_h + gap)
		draw_rect(Rect2(left, y, head_w, row_h), Look.hero_card_face(element))
		Look.draw_elem(self, Vector2(left + 25, y + row_h * 0.5), 16, element)
		Look.text_center_fit(self, Vector2(left + 101, y + row_h * 0.5), Balance.elem_ko(element), 22, Look.INK, 114, 16)
		for c in range(count):
			var mult := _mult(element, String(columns[c]))
			present[mult] = true
			_draw_mult_cell(Rect2(grid_x + float(c) * (cell_w + gap), y, cell_w, row_h), mult, 26)
	var bottom := top + head_h + 4.0 + float(ELEMENT_ROWS.size()) * (row_h + gap) - gap
	if _same_kind_resisted(columns):
		Look.text_box(self, Rect2(left, bottom + 8, 766, 24), "같은 속성끼리는 반감됩니다.", Look.TYPE_CAPTION, Look.INK_DIM)
	_draw_legend(present, bottom + 50)


## The chart's columns: the local order first, then any body the table has that it lacks.
static func _chart_columns() -> Array:
	var out: Array = []
	for body in ELEMENT_COLUMNS:
		if Balance.MBODY.has(body):
			out.append(body)
	for body in Balance.MBODY_ORDER:
		if not out.has(body):
			out.append(body)
	return out


## True when every attack resists the body of its own name in the chart (the footnote).
func _same_kind_resisted(columns: Array) -> bool:
	var seen := false
	for element in SAME_KIND:
		if not ELEMENT_ROWS.has(element) or not columns.has(SAME_KIND[element]):
			continue
		seen = true
		if _mult(element, String(SAME_KIND[element])) >= 1.0:
			return false
	return seen


## The chart's numbers and column names: the balance table's own (a capture tool overrides
## these two to preview a table the balance has not adopted yet).
func _mult(element: String, body: String) -> float:
	return Balance.elem_mult(element, body)


func _body_name(body: String) -> String:
	return Balance.body_ko(body)


## The corner's direction: the attack circle → the body square, in the headers' marks.
func _draw_direction(at: Vector2) -> void:
	var ink := Look.INK_DIM
	draw_arc(at + Vector2(-27, 0), 6.0, 0, TAU, 20, ink, 1.6, true)
	draw_line(at + Vector2(-16, 0), at + Vector2(10, 0), ink, 1.6, true)
	draw_colored_polygon(PackedVector2Array([at + Vector2(15, 0), at + Vector2(8, -4.5), at + Vector2(8, 4.5)]), ink)
	draw_rect(Rect2(at + Vector2(21, -6), Vector2(12, 12)), ink, false, 1.6)


## One cell. 2x: hot fill and rim; 0.5x: ash rim; 0x: dark red, hatched; 1x: a quiet well
## with a muted figure. The figure is always there: the colour never carries it alone.
func _draw_mult_cell(rect: Rect2, mult: float, size: int) -> void:
	var tone := _element_mult_color(mult)
	if is_equal_approx(mult, 1.0):
		draw_rect(rect, Look.BG_DEEP.lerp(Look.STEEL, 0.07))
		Look.text_center(self, rect.get_center(), _element_mult_label(mult), maxi(16, size - 5), tone)
		return
	var strong := mult > 1.0 or is_zero_approx(mult)
	draw_rect(rect, Look.BG_DEEP.lerp(tone, 0.26 if mult > 1.0 else 0.20 if strong else 0.13))
	if is_zero_approx(mult):
		for k in range(-4, 9):
			var x0 := rect.position.x + float(k) * 16.0
			var a := Vector2(maxf(rect.position.x, x0), rect.position.y + maxf(0.0, rect.position.x - x0))
			var b := Vector2(minf(rect.end.x, x0 + rect.size.y), rect.position.y + minf(rect.size.y, rect.end.x - x0))
			if a.x < b.x and a.y < b.y:
				draw_line(a, b, Color(tone, 0.10), 2.0, true)
	draw_rect(rect.grow(-1.0), Color(tone, 0.80 if strong else 0.45), false, 1.6 if strong else 1.2)
	Look.text_center(self, rect.get_center(), _element_mult_label(mult), size + (1 if mult > 1.0 else -1), tone.lightened(0.10) if strong else tone)


## The legend: one swatch per multiplier the chart holds, strongest first, centred.
func _draw_legend(present: Dictionary, y: float) -> void:
	var entries: Array = []
	for mult in present:
		entries.append(float(mult))
	entries.sort_custom(func(a: float, b: float) -> bool:
		return _legend_rank(a) < _legend_rank(b))
	var swatch := Vector2(62, 30)
	var size := 18
	var widths: Array = []
	var total := 0.0
	for mult in entries:
		var width := swatch.x + 10.0 + Look.text_width(_legend_word(mult), size)
		widths.append(width)
		total += width
	total += 34.0 * float(maxi(0, entries.size() - 1))
	var x := 640.0 - total * 0.5
	for i in range(entries.size()):
		var mult: float = entries[i]
		_draw_mult_cell(Rect2(Vector2(x, y - swatch.y * 0.5), swatch), mult, 19)
		Look.text_left(self, Vector2(x + swatch.x + 10.0, y), _legend_word(mult), size, Look.INK_DIM)
		x += float(widths[i]) + 34.0


static func _legend_rank(mult: float) -> int:
	if mult > 1.0:
		return 0
	if is_equal_approx(mult, 1.0):
		return 1
	return 2 if mult > 0.0 else 3


static func _legend_word(mult: float) -> String:
	return ["약점", "보통", "반감", "무효"][_legend_rank(mult)]


func _element_mult_label(mult: float) -> String:
	return "%s배" % ("%.1f" % mult if not is_equal_approx(mult, roundf(mult)) else "%d" % int(mult))


func _element_mult_color(mult: float) -> Color:
	if is_zero_approx(mult):
		return Look.RED.lerp(Look.INK, 0.42)
	if is_equal_approx(mult, 1.0):
		return Look.INK_MUTE
	if mult < 1.0:
		return Look.DMG_RESIST.lerp(Look.INK, 0.38)
	return Look.DMG_WEAK


func _draw_languages(rect: Rect2) -> void:
	for index in range(2):
		var code := "ko" if index == 0 else "en"
		var button_rect := Rect2(rect.position + Vector2(index * 76, 0), Vector2(68, rect.size.y))
		var selected := I18n.locale == code
		if _glass():
			if selected:
				ui.zone(button_rect, "language:" + code)
				Look.glass_panel(self, button_rect, Look.GOLD.lightened(0.25), Look.GOLD.darkened(0.05), true)
				Look.text_box(self, button_rect.grow(-5), "KOR" if code == "ko" else "ENG", 20, Look.BG_DEEP)
			else:
				ui.glass_button(self, button_rect, "KOR" if code == "ko" else "ENG", "language:" + code, true, Look.STEEL, 20)
		else:
			ui.button(self, button_rect, "KOR" if code == "ko" else "ENG", "language:" + code,
					true, Look.GOLD if selected else Look.PANEL_EDGE, 20)
		if selected:
			draw_rect(Rect2(button_rect.position + Vector2(19, button_rect.size.y - 9), Vector2(30, 3)), Look.BG_DEEP)
