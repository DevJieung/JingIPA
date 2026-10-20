extends RefCounted
class_name ArenaHelp

## The rules of the run, as the shared menu shows them (on the title too: the run is the
## game now). Five rules, each with the colour of what it is about; the last one is the
## air rule (guns and bows against flyers). MenuOverlay calls ArenaScreen.draw_help, which
## forwards here; `ci` is the menu's own canvas.
##
## O11 (2026-10-19): the rules are full sentences, longer than the old fragments, so the
## page gives them the whole sheet width and height (under the tabs to the bottom line) and
## keeps every rule at one size of at least 16 px (tests/arena_visual_preview.gd
## --help-only): the largest size at which all five fit, never smaller words in one row
## than in its neighbours. When even 16 px does not fit, the rules go onto pages (whole rules
## per page, turned with help:page:±1) instead of shrinking. The bottom line holds the save
## note and the length of the stage ladder (「총 100 STAGE」, Arena.ladder_size()).
const AREA := Rect2(250, 232, 780, 372)
const FLOOR := 16
const LARGEST := 20
const INSET := 16.0
const PAD := 10.0
const GAP := 5.0
const KEYS := ["control", "defense", "growth", "boss", "air"]
const PAGER := Vector2(48, 40)

## The page shown when the rules need more than one. MenuOverlay sets it back to 0 when the
## menu opens and turns it with the zones help:page:-1 / help:page:1.
static var page := 0


static func draw(ci: CanvasItem) -> void:
	var colors := [Look.GOLD, Look.CRYSTAL, Look.STARLIGHT, Look.RED, Look.AIR]
	var width := AREA.size.x - INSET * 2.0
	var texts: Array = []
	for key in KEYS:
		texts.append(Arena.label("arena.rules." + key))
	var total_stages := ladder_size()
	var chip_label := "총 %d STAGE" % total_stages
	var chip_w := Look.text_width(chip_label, 17) + 20.0 if total_stages > 0 else 0.0
	# Lay out once without pages; if the rules overflow at the floor, again with the pager
	# beside the save note.
	var layout := _layout(texts, width, chip_w, false)
	if layout["overflow"]:
		layout = _layout(texts, width, chip_w, true)
	var size: int = layout["size"]
	var pages: Array = layout["pages"]
	page = clampi(page, 0, pages.size() - 1)
	var y := AREA.position.y
	for i in pages[page]:
		var height := float(layout["counts"][i]) * Look.line_height(size) + PAD
		var rect := Rect2(AREA.position.x, y, AREA.size.x, height)
		Look.fill_round(ci, rect, 4, Color(Look.BG_DEEP, 0.55))
		ci.draw_rect(Rect2(rect.position.x, rect.position.y, 4, rect.size.y), colors[i])
		Look.wrap_text(ci, String(texts[i]), Rect2(rect.position.x + INSET, rect.position.y + PAD * 0.5, width, height - PAD), size, Look.INK, true)
		y += height + GAP
	# Bottom line: what is saved, (pages,) and how long the ladder is.
	var bottom_h: float = layout["bottom_h"]
	var line := Rect2(AREA.position.x + 4.0, AREA.position.y + float(layout["area_h"]) + 2.0, AREA.size.x - 8.0, bottom_h)
	var right := line.end.x
	if total_stages > 0:
		Look.chip(ci, Vector2(right, line.get_center().y), chip_label, 17, Look.GOLD, Look.BG_DEEP, HORIZONTAL_ALIGNMENT_RIGHT)
		right -= chip_w + 12.0
	if pages.size() > 1:
		right -= _pager(ci, Vector2(right, line.get_center().y), pages.size()) + 12.0
	var hint := Arena.label("arena.save_hint")
	var hint_h := float(Look.wrapped_lines(hint, right - line.position.x, Look.TYPE_CAPTION).size()) * Look.line_height(Look.TYPE_CAPTION)
	Look.wrap_text(ci, hint, Rect2(line.position.x, line.get_center().y - hint_h * 0.5, right - line.position.x, hint_h), Look.TYPE_CAPTION, Look.INK_DIM, true)


## The size, the line count of each rule, the pages (lists of rule indices), the height left
## for the rules and the bottom line's height. `paged` reserves the pager on the bottom line.
static func _layout(texts: Array, width: float, chip_w: float, paged: bool) -> Dictionary:
	var hint_w := AREA.size.x - 8.0 - (chip_w + 12.0 if chip_w > 0.0 else 0.0) - (PAGER.x * 2.0 + 64.0 + 12.0 if paged else 0.0)
	var hint_lines := Look.wrapped_lines(Arena.label("arena.save_hint"), hint_w, Look.TYPE_CAPTION).size()
	var bottom_h := maxf(PAGER.y if paged else 28.0, float(hint_lines) * Look.line_height(Look.TYPE_CAPTION))
	var area_h := AREA.size.y - (bottom_h - 28.0)
	var size := LARGEST
	var counts: Array = []
	var total := 0.0
	while true:
		counts.clear()
		total = GAP * float(texts.size() - 1)
		for text in texts:
			var lines := Look.wrapped_lines(String(text), width, size).size()
			counts.append(lines)
			total += float(lines) * Look.line_height(size) + PAD
		if total <= area_h or size <= FLOOR:
			break
		size -= 1
	var pages: Array = []
	var current: Array = []
	var used := 0.0
	for i in range(counts.size()):
		var height := float(counts[i]) * Look.line_height(size) + PAD
		if not current.is_empty() and used + GAP + height > area_h:
			pages.append(current)
			current = []
			used = 0.0
		used += height + (GAP if not current.is_empty() else 0.0)
		current.append(i)
	if not current.is_empty():
		pages.append(current)
	return {"size": size, "counts": counts.duplicate(), "pages": pages if paged else [range(texts.size())],
		"overflow": total > area_h, "area_h": area_h, "bottom_h": bottom_h}


## ◀ n / m ▶ ending at `right` (vertically centred on `mid_y`); returns its width. The zones
## go into the canvas's own Ui (the menu's), so its input turns the page.
static func _pager(ci: CanvasItem, right_mid: Vector2, count: int) -> float:
	var label := "%d / %d" % [page + 1, count]
	var label_w := maxf(52.0, Look.text_width(label, 17) + 12.0)
	var w := PAGER.x * 2.0 + label_w
	var x := right_mid.x - w
	var ui: Variant = ci.get("ui")
	var prev := Rect2(x, right_mid.y - PAGER.y * 0.5, PAGER.x, PAGER.y)
	var next := Rect2(x + PAGER.x + label_w, prev.position.y, PAGER.x, PAGER.y)
	if ui is Ui:
		(ui as Ui).button(ci, prev, "<", "help:page:-1", page > 0, Look.PANEL_EDGE, 18)
		(ui as Ui).button(ci, next, ">", "help:page:1", page + 1 < count, Look.PANEL_EDGE, 18)
	Look.text_center(ci, Vector2(x + PAGER.x + label_w * 0.5, right_mid.y), label, 17, Look.INK_DIM)
	return w


## How many stages the ladder has (Arena.ladder_size(), LA1).
static func ladder_size() -> int:
	return Arena.ladder_size()
