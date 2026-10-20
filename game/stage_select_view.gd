extends RefCounted
class_name StageSelectView

## Stage select over the title (2026-10-19, PLAN U3 · O10 · LB2b): the ladder's stages, one
## chapter (ten stages) to a page. Only stages the player may play start (Arena.can_play: up to
## Save.stage_unlocked); a pick starts that stage through main.start_run(0, n).
##
## Zones: stage:pick:<n> (a cell; registered off while locked), stage:page:-1 / stage:page:1,
## stage:close, stage:none (the shade: swallows taps outside the sheet). The host (TitleScreen)
## routes input(event, ui) and draw(ci, ui) and passes Main to open().
##
## Data the drawing reads (D4 replaces draw() only):
##   page, pages(), chapter(), cells() -> [cell(n) ...] with
##   {stage, label ("STAGE n"), theme_index, theme (Roster.THEMES row), name (translated field
##    name), body (main body id), rank, open (can_play), cleared (<= Save.stage_cleared),
##    next (== Save.stage_unlocked: the stage up next), last (== Save.last_clear.stage),
##    chapter_boss (every tenth stage: the chapter's final boss)}

## One chapter per page (core/arena_run.gd CHAPTER): the tenth cell is the chapter boss.
const PAGE_SIZE := 10
const SHEET := Rect2(76, 76, 1128, 672)

var opened := false
var main: Node = null
var page := 0
## The stage chosen (0 = none yet): a second tap during the fade starts nothing twice.
var picked := 0


## Open on the chapter of the stage that is up next.
func open(host_main: Node = null) -> void:
	if host_main != null:
		main = host_main
	opened = true
	picked = 0
	page = clampi((Save.stage_unlocked - 1) / PAGE_SIZE, 0, pages() - 1)


func close() -> void:
	opened = false


func pages() -> int:
	return maxi(1, ceili(float(Arena.ladder_size()) / float(PAGE_SIZE)))


## The chapter (1..) this page shows.
func chapter() -> int:
	return page + 1


static func stage_label(number: int) -> String:
	return Arena.label("arena.stage_label") % number


## Everything a cell shows about one stage.
static func cell(number: int) -> Dictionary:
	var index: int = Arena.ladder_theme(number)
	var theme: Dictionary = Roster.THEMES[index] if index >= 0 and index < Roster.THEMES.size() else {}
	return {"stage": number, "label": stage_label(number), "theme_index": index, "theme": theme,
		"name": I18n.t(String(theme.get("ko", ""))), "body": String(theme.get("main_body", "")),
		"rank": int(theme.get("rank", 1)), "open": Arena.can_play(number),
		"cleared": number <= Save.stage_cleared, "next": number == Save.stage_unlocked,
		"last": int(Save.last_clear.get("stage", 0)) == number, "chapter_boss": Arena.chapter_stage(number)}


## The cells of the page shown now.
func cells() -> Array:
	var out: Array = []
	var first := page * PAGE_SIZE + 1
	for number in range(first, mini(first + PAGE_SIZE, Arena.ladder_size() + 1)):
		out.append(cell(number))
	return out


## Mouse / touch through the host's Ui. True while open, so nothing underneath reacts.
func input(event: InputEvent, ui: Ui) -> bool:
	if not opened:
		return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := ui.hit(event.position)
		if id.begins_with("stage:") and id != "stage:none":
			action(id)
			Sfx.play("button")
	return true


func action(id: String) -> bool:
	if not id.begins_with("stage:"):
		return false
	var parts := id.split(":")
	match parts[1]:
		"close":
			close()
		"page":
			if parts.size() > 2:
				page = clampi(page + int(parts[2]), 0, pages() - 1)
		"pick":
			if parts.size() > 2:
				return pick(int(parts[2]))
	return true


## Start a stage the player may play. False for a locked one, or when a pick is already on its way.
func pick(number: int) -> bool:
	if picked > 0 or not Arena.can_play(number) or main == null or not main.has_method("start_run"):
		return false
	picked = number
	main.start_run(0, number)
	return true


# --------------------------------------------------------------------------- #
# 그리기 — 디자인 담당(D4) 구간. 위의 데이터만 읽는다. D4 2026-10-19.
# --------------------------------------------------------------------------- #
## One chapter as a route of ten stage cards: each card carries its battlefield's body element
## (a tinted band, the element medallion and its name — never colour alone), the stage up next
## glows gold with 「도전」, cleared ones carry a check, locked ones a padlock, and the tenth card is
## the chapter boss in ember. Chevrons between cards turn gold as the route is walked; pips under
## the chapter chip show the whole chapter at a glance.
const CARD := Vector2(196, 232)
const CARD_GAP := 20.0
const GRID_TOP := 176.0
const LOCKED_INK := Color("#8b9aa5")
const BOSS := Color("#ff6b3d")


func draw(ci: CanvasItem, ui: Ui) -> void:
	if not opened:
		return
	ci.draw_rect(Look.SCREEN, Look.SHADE)
	ui.zone(Look.SCREEN, "stage:none")
	Look.sheet(ci, SHEET, Look.STEEL)
	Look.text_box(ci, Rect2(SHEET.position + Vector2(28, 20), Vector2(380, 48)), Arena.label("arena.stage_select"), Look.TYPE_TITLE,
		Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	var shown := cells()
	_draw_chapter_head(ci, Vector2(SHEET.get_center().x, SHEET.position.y + 40), shown)
	ui.button(ci, Rect2(SHEET.end.x - 132, SHEET.position.y + 22, 104, 44), "닫기", "stage:close", true, Look.PANEL_EDGE, 20)
	var origin := Vector2(SHEET.get_center().x - (CARD.x * 5 + CARD_GAP * 4) * 0.5, GRID_TOP)
	var t := float(Time.get_ticks_msec()) * 0.001
	for i in range(shown.size()):
		var data: Dictionary = shown[i]
		var rect := Rect2(origin + Vector2(float(i % 5) * (CARD.x + CARD_GAP), float(i / 5) * (CARD.y + CARD_GAP)), CARD)
		if i % 5 != 4 and i + 1 < shown.size():
			_chevron(ci, Vector2(rect.end.x + CARD_GAP * 0.5, rect.get_center().y), Look.GOLD if bool(data["cleared"]) else Look.STEEL_DIM)
		_draw_card(ci, ui, rect, data, t)
	var nav_y := SHEET.end.y - 62
	ui.button(ci, Rect2(SHEET.position.x + 28, nav_y, 124, 44), "이전", "stage:page:-1", page > 0, Look.PANEL_EDGE, 20)
	Look.text_center(ci, Vector2(SHEET.get_center().x, nav_y + 22), "%d / %d" % [page + 1, pages()], 21, Look.INK_DIM)
	ui.button(ci, Rect2(SHEET.end.x - 152, nav_y, 124, 44), "다음", "stage:page:1", page < pages() - 1, Look.PANEL_EDGE, 20)


## 「챕터 n」 in a chip, and ten pips: cleared (gold), next (ivory ring), locked (hollow), boss (ember).
func _draw_chapter_head(ci: CanvasItem, at: Vector2, shown: Array) -> void:
	var label := Arena.label("arena.chapter_n") % chapter()
	var tw := Look.text_width(label, 22)
	var chip := Rect2(at.x - tw * 0.5 - 18.0, at.y - 18.0, tw + 36.0, 34.0)
	Look.outline_round(ci, chip, 17, Color(Look.GOLD_DEEP, 0.9), 1.5)
	Look.fill_round(ci, chip, 17, Look.BG_DEEP)
	Look.text_center(ci, chip.get_center(), label, 22, Look.IVORY)
	var step := 18.0
	var x0 := at.x - step * float(shown.size() - 1) * 0.5
	for i in range(shown.size()):
		var data: Dictionary = shown[i]
		var p := Vector2(x0 + step * float(i), at.y + 34.0)
		var boss := bool(data["chapter_boss"])
		var r := 6.5 if boss else 5.0
		if bool(data["cleared"]):
			Look.draw_diamond(ci, p, r, Look.GOLD)
		elif bool(data["next"]):
			Look.draw_diamond(ci, p, r + 1.5, Color(Look.IVORY, 0.35))
			Look.draw_diamond(ci, p, r, Look.IVORY, true, 1.6)
		else:
			Look.draw_diamond(ci, p, r, BOSS if boss else Look.STEEL_DIM, true, 1.3)


func _draw_card(ci: CanvasItem, ui: Ui, rect: Rect2, data: Dictionary, t: float) -> void:
	var open: bool = data["open"]
	var cleared: bool = data["cleared"]
	var next: bool = data["next"]
	var boss: bool = data["chapter_boss"]
	var body := String(data["body"])
	var tone := Balance.body_color(body)
	var id := "stage:pick:%d" % int(data["stage"])
	ui.zone(rect, id, open)
	var down := open and ui.pressed == id
	var r := Rect2(rect.position + Vector2(0, 2 if down else 0), rect.size)
	var edge := Look.GOLD if next else (BOSS if boss and not cleared else (Look.CRYSTAL if cleared else Look.PANEL_EDGE))
	if not open:
		edge = Color("#34434d") if not boss else BOSS.darkened(0.55)
	# The stage up next breathes a gold halo.
	if next:
		var glow := 0.5 + 0.5 * sin(t * 3.0)
		for k in range(3):
			Look.outline_round(ci, r.grow(3.0 + float(k) * 3.0), 12.0 + float(k) * 3.0, Color(Look.GOLD, (0.30 - float(k) * 0.09) * (0.6 + 0.4 * glow)), 2.0)
	Look.fill_round(ci, Rect2(r.position + Vector2(0, 4), r.size), 11, Color(0, 0, 0, 0.35))
	Look.fill_round(ci, r, 11, edge)
	var face := Color("#10222e") if open else Color("#0a141b")
	if down:
		face = face.darkened(0.2)
	Look.fill_round(ci, r.grow(-2.0), 9, face)
	# Body band: the battlefield's element tints the head of the card.
	var band := Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 104))
	var top := Color(tone, 0.34 if open else 0.10)
	ci.draw_polygon(PackedVector2Array([band.position + Vector2(9, 0), band.position + Vector2(band.size.x - 9, 0),
		band.end, band.position + Vector2(0, band.size.y)]), PackedColorArray([top, top, Color(tone, 0.0), Color(tone, 0.0)]))
	var cx := r.get_center().x
	var medal := Vector2(cx, r.position.y + 58)
	ci.draw_circle(medal, 32, Color(Look.BG_DEEP, 0.85), true, -1, true)
	ci.draw_arc(medal, 32, 0, TAU, 40, Color(tone, 0.9 if open else 0.35), 2.0, true)
	if open:
		Look.draw_body(ci, medal, 19, body)
	else:
		Look.draw_body(ci, medal, 19, body)
		ci.draw_circle(medal, 31, Color(Look.BG_DEEP, 0.55), true, -1, true)
		_padlock(ci, medal + Vector2(0, 2), LOCKED_INK)
	if boss:
		_boss_tab(ci, Vector2(r.get_center().x, r.position.y), open)
	var label_col := Look.GOLD if next else (Look.CRYSTAL if cleared else (Look.INK if open else LOCKED_INK))
	Look.text_center_fit(ci, Vector2(cx, r.position.y + 118), String(data["label"]), 25, label_col, r.size.x - 20, 18)
	Look.text_center_fit(ci, Vector2(cx, r.position.y + 148), String(data["name"]), 19, Look.INK if open else LOCKED_INK, r.size.x - 18, 14)
	Look.text_center_fit(ci, Vector2(cx, r.position.y + 172), Balance.body_ko(body), 16, Color(tone.lightened(0.25), 0.95) if open else LOCKED_INK, r.size.x - 18, 12)
	_draw_state(ci, Rect2(r.position.x + 14, r.end.y - 34, r.size.x - 28, 26), data)


## The card's foot: cleared (check), next (gold 「도전」 pill with a play mark), locked (padlock).
func _draw_state(ci: CanvasItem, box: Rect2, data: Dictionary) -> void:
	var c := box.get_center()
	if bool(data["cleared"]):
		var label := Arena.label("arena.stage_cleared")
		var w := Look.text_width(label, 19)
		Look.draw_check(ci, c + Vector2(-w * 0.5 - 12.0, 0), 13.0, Look.CRYSTAL, 2.6)
		Look.text_center(ci, c + Vector2(8.0, 0), label, 19, Look.CRYSTAL)
	elif bool(data["next"]):
		var label := Arena.label("arena.stage_next")
		var w := Look.text_width(label, 19)
		var pill := Rect2(c.x - w * 0.5 - 26.0, box.position.y - 2.0, w + 52.0, box.size.y + 4.0)
		Look.fill_round(ci, pill, pill.size.y * 0.5, Look.GOLD)
		var tri := c + Vector2(-w * 0.5 - 10.0, 0)
		ci.draw_colored_polygon(PackedVector2Array([tri + Vector2(-5, -7), tri + Vector2(7, 0), tri + Vector2(-5, 7)]), Look.BG_DEEP)
		Look.text_center(ci, c + Vector2(8.0, 0), label, 19, Look.BG_DEEP)
	elif not bool(data["open"]):
		var label := Arena.label("arena.stage_locked")
		Look.text_center(ci, c, label, 18, LOCKED_INK)


## 「챕터 보스」: an ember tab with a crown on the tenth card's top edge.
func _boss_tab(ci: CanvasItem, top_center: Vector2, open: bool) -> void:
	var col := BOSS if open else BOSS.darkened(0.45)
	var label := Arena.label("arena.chapter_boss")
	var w := Look.text_width(label, 16)
	var tab := Rect2(top_center.x - w * 0.5 - 30.0, top_center.y - 13.0, w + 50.0, 26.0)
	Look.outline_round(ci, tab, 13, col, 1.6)
	Look.fill_round(ci, tab, 13, Look.BG_DEEP)
	var c := Vector2(tab.position.x + 17.0, tab.get_center().y + 1.0)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 5), c + Vector2(-8, -3), c + Vector2(-4, 1), c + Vector2(0, -6),
		c + Vector2(4, 1), c + Vector2(8, -3), c + Vector2(8, 5)]), col)
	Look.text_center(ci, Vector2(tab.position.x + 30.0 + w * 0.5, tab.get_center().y), label, 16, col.lerp(Look.INK, 0.25) if open else LOCKED_INK)


func _chevron(ci: CanvasItem, at: Vector2, color: Color) -> void:
	ci.draw_polyline(PackedVector2Array([at + Vector2(-4, -7), at + Vector2(3, 0), at + Vector2(-4, 7)]), color, 2.6, true)


func _padlock(ci: CanvasItem, at: Vector2, color: Color) -> void:
	ci.draw_arc(at + Vector2(0, -5), 6.0, PI, TAU, 14, color, 2.6, true)
	ci.draw_line(at + Vector2(-6, -5), at + Vector2(-6, 0), color, 2.6, true)
	ci.draw_line(at + Vector2(6, -5), at + Vector2(6, 0), color, 2.6, true)
	Look.fill_round(ci, Rect2(at + Vector2(-9, -1), Vector2(18, 14)), 3, color)
	ci.draw_circle(at + Vector2(0, 5), 2.2, Look.BG_DEEP, true, -1, true)
