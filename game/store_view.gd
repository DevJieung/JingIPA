extends RefCounted
class_name StoreView

## The purchase sheet shared by the title and the battlefield. One thing is for sale: the
## DLC (Store.GUARDIAN, a permanent purchase; the id, the locale keys and the SKU stay
## "guardian"), a bundle of three benefits (2026-10-19, PLAN M9): more free jewel-box
## rerolls, revival tickets (the Soul Stone rises again and a 5-star hero joins, never
## gold) and the Hellbound mode. The sheet shows that product with the shop's own price,
## the restore button and the answer to the last request. It never opens by itself: the
## title's shop button and the defeat panel's offer open it.
##
## Tone (user, 2026-10-13: "부담없이"): the sheet says once that this is the only thing
## for sale and that it is bought once, states what is bought in three plain rows (two
## lines each at most), shows the price before anything is tapped, and leaves as easily as
## it buys (close button, a tap outside, Esc / back). No timers, no badges, no discounts,
## nothing that moves except the spinner of a running request. Layout and states:
## docs/UI_STAGE_STORE.md.
##
## The sheet is laid out for this single product. Battle speed was a second product for a
## few hours of 2026-10-13 and is free again; a second row would need its own layout.
const PANEL := Rect2(232, 143, 816, 514)
const BLOCK_H := 260.0
## One benefit row's slot: two lines of the largest size at which all three rows fit
## (FACT_TEXT_H), with air between the rows.
const FACT_ROW_H := 64.0
const FACT_TEXT_H := 56.0
const NOTICE_SECONDS := 6.0
## The Hellbound mode's own colour: the embers inside its gate (sheet row, squad picker).
const HELL_EMBER := Color("#ff6b3d")

var opened := false
## The product the sheet was opened for (the defeat panel's offer passes the blessing);
## empty when it was opened from the title. The sheet then adds what buying means now.
var focus := ""
var notice := ""
var notice_good := false
## "good" | "info" | "quiet" | "bad": how the last answer is coloured.
var notice_tone := "info"
var _notice_at := -100.0
var _clock := 0.0
var _bound := false
## Whether the sheet was last drawn over the battlefield (see resumes_run).
var _on_arena := false


func open(product: String = "") -> void:
	opened = true
	focus = product
	notice = ""
	_bind()


func close() -> void:
	opened = false


func _bind() -> void:
	if _bound: return
	_bound = true
	Store.purchase_finished.connect(_on_purchase)
	Store.restore_finished.connect(_on_restore)


func _say(key: String, good: bool, tone: String = "") -> void:
	notice = Arena.label(key)
	notice_good = good
	notice_tone = tone if not tone.is_empty() else ("good" if good else "info")
	_notice_at = _clock


func _on_purchase(_id: String, result: String) -> void:
	# Cancelling is not an error and a pending approval is not a failure.
	var tone: String = {"ok": "good", "cancelled": "quiet", "pending": "info"}.get(result, "bad")
	_say("store.result." + result, result == "ok", tone)


func _on_restore(result: String) -> void:
	_say("store.restore." + result, result == "ok", "good" if result == "ok" else "bad")


## Mouse / touch for screens that hit-test through Ui (the title). Returns true while
## the sheet is open so nothing underneath reacts.
func input(event: InputEvent, ui: Ui) -> bool:
	if not opened: return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := ui.hit(event.position)
		if id.begins_with("store:"):
			action(id)
			Sfx.play("button")
	return true


func action(id: String) -> bool:
	if not id.begins_with("store:"): return false
	var parts := id.split(":")
	match parts[1]:
		"close": close()
		"restore": Store.restore()
		"reset": Store.sandbox_reset()
		"buy":
			if parts.size() > 2: Store.buy(parts[2])
	return true


## Whether buying now continues the run that was just lost — the sheet was opened from the
## defeat panel's offer: over the battlefield, the run over and lost, its result up (the
## state Arena.revive_from_defeat accepts). The title opens the same product (its shop button
## and the locked Hellbound button) with no run to continue, so the sheet does not say so there.
func resumes_run() -> bool:
	return focus == Store.GUARDIAN and _on_arena and not Arena.running and Arena.modal == "result" \
		and Arena.sim != null and not Arena.sim.won


## What the product shows on its right side:
##   "owned"    bought: a tick, no button
##   "busy"     this purchase is with the shop right now
##   "wait"     another request is running: the price stays, the button rests
##   "offline"  the shop cannot sell it at the moment
##   "test"     a test build unlocks it without paying
##   "buy"      for sale
func state_of(id: String) -> String:
	if Store.owns(id): return "owned"
	if Store.buying() == id: return "busy"
	if not Store.buying().is_empty() or Store.restoring(): return "wait"
	if not Store.can_buy(id): return "offline"
	return "test" if Store.sandbox(id) else "buy"


## The words on a product's button. The price is the shop's own string; "" means the
## shop has not answered yet, and the button then names the action instead.
func button_label(id: String) -> String:
	match state_of(id):
		"owned": return Arena.label("store.owned")
		"busy": return Arena.label("store.busy")
		"offline": return Arena.label("store.offline")
		"test": return Arena.label("store.test_unlock")
	var price := Look.price_text(Store.price(id))
	if not price.is_empty(): return price
	return Arena.label("store.view_steam") if Store.shop_name() == "steam" else Arena.label("store.buy")


func draw(ci: CanvasItem, ui: Ui, time: float) -> void:
	_clock = time
	_on_arena = ci is ArenaScreen
	if not opened: return
	# Deep enough that a result panel under the sheet (the defeat offer opens it, and
	# that panel is taller than the sheet) does not read as part of it.
	ci.draw_rect(Look.SCREEN, Color(Look.SHADE, 0.87))
	# Leaving is as easy as buying: anywhere outside the sheet closes it. The sheet
	# itself swallows taps, so nothing underneath ever reacts.
	ui.zone(Look.SCREEN, "store:close")
	ui.zone(PANEL, "modal:block")
	Look.sheet(ci, PANEL, Look.STEEL)
	var x := PANEL.position.x
	var y := PANEL.position.y
	Look.text_box(ci, Rect2(x + 40, y + 16, PANEL.size.x - 80, 50), Arena.label("store.title"), Look.TYPE_TITLE, Look.GOLD)
	Look.text_box(ci, Rect2(x + 40, y + 64, PANEL.size.x - 80, 30), Arena.label("store.all"), Look.TYPE_BODY, Look.INK_DIM)
	var rule_y := y + 104.0
	ci.draw_line(Vector2(x + 44, rule_y), Vector2(PANEL.end.x - 44, rule_y), Color(Look.PANEL_EDGE, 0.45), 1, true)
	_diamond(ci, Vector2(PANEL.get_center().x, rule_y), 4.0, Look.GOLD_DEEP)
	var id := Store.GUARDIAN
	var state := state_of(id)
	var block := Rect2(x + 32, y + 118, PANEL.size.x - 64, BLOCK_H)
	_draw_product(ci, ui, block, id, state, time)
	# One line under the product: the answer to the last request, else what is true now.
	var line := Rect2(x + 40, block.end.y + 12, PANEL.size.x - 80, 30)
	if time - _notice_at < NOTICE_SECONDS and not notice.is_empty():
		var tone: Color = {"good": Look.GREEN, "quiet": Look.INK_DIM, "bad": Look.WARN}.get(notice_tone, Look.GOLD)
		var width := minf(line.size.x - 34.0, Look.text_width(notice, 18))
		var mark := Vector2(line.get_center().x - width * 0.5 - 16.0, line.get_center().y)
		if notice_tone == "good":
			Look.draw_check(ci, mark, 12.0, tone)
		else:
			_diamond(ci, mark, 4.5, tone)
		Look.text_box(ci, Rect2(line.position.x + 24, line.position.y, line.size.x - 24, line.size.y), notice, 18, tone)
	elif Store.restoring():
		_spinner(ci, Vector2(line.get_center().x - Look.text_width(Arena.label("store.restoring"), 18) * 0.5 - 18.0, line.get_center().y), 7.0, Look.INK_DIM, time)
		Look.text_box(ci, line, Arena.label("store.restoring"), 18, Look.INK_DIM)
	elif state == "offline":
		Look.text_box(ci, line, Arena.label("store.result.unavailable"), 18, Look.INK_DIM)
	elif resumes_run() and state in ["buy", "test", "busy"]:
		# Opened from a defeat: buying now is not only for later runs.
		Look.text_box(ci, line, Arena.label("store.resume_note"), 18, Look.INK_DIM)
	var busy := not Store.buying().is_empty() or Store.restoring()
	var foot := PANEL.end.y - 78.0
	_restore_button(ci, ui, Rect2(x + 32, foot, 252, 54), Store.has_shop() and not busy)
	ui.button(ci, Rect2(PANEL.end.x - 284, foot, 252, 54), I18n.t("닫기"), "store:close", true, Look.PANEL_EDGE, Look.TYPE_BUTTON_2)
	# Test builds only (never a store build): forget the purchases made without paying.
	if Store.test_build() and not Save.iap_sandbox.is_empty():
		var reset := Rect2(PANEL.get_center().x - 104, foot + 6, 208, 42)
		ui.zone(reset, "store:reset", not busy)
		var down := not busy and ui.pressed == "store:reset"
		Look.fill_round(ci, reset, 5, Color(0.02, 0.05, 0.08, 0.90 if down else 0.55))
		_dashed_rect(ci, reset.grow(-1), Color(Look.PANEL_EDGE, 0.75 if not busy else 0.35))
		Look.text_box(ci, reset.grow(-8), Arena.label("store.test_reset"), 15, Look.INK_DIM if not busy else Color("#6e8390"))


## The three plain statements of what is bought, one per benefit of the DLC: the jewel
## box's free rerolls, the revival ticket and the Hellbound mode. Every number is read
## from the balance table, so the sheet cannot disagree with the rule.
static func facts() -> Array:
	# The revival's hero is a 5-star (PLAN M9); ARENA_REVIVE_HERO_STARS if the run names it.
	var table: Script = Balance
	var hero_stars: Variant = table.get("ARENA_REVIVE_HERO_STARS")
	var hero_tier := JewelBox.tier_of(int(hero_stars)) if hero_stars != null else Balance.TIER_MAX
	return [
		["reroll", Arena.label("store.guardian.reroll") % [Balance.FREE_REROLL, Balance.ARENA_DLC_FREE_REROLL]],
		["revive", Arena.label("store.guardian.revive") % [Balance.ARENA_REVIVE_USES, I18n.t(Look.star_label(hero_tier))]],
		["hell", Arena.label("store.guardian.hell")],
	]


## The product: its crest over the DLC chip, its name, the three benefits, and on the
## right the price button (or what stands in its place) with the kind of payment under it.
func _draw_product(ci: CanvasItem, ui: Ui, block: Rect2, id: String, state: String, time: float) -> void:
	var owned := state == "owned"
	var tint := Look.CRYSTAL if owned else Look.GOLD
	Look.glass_panel(ci, block, Look.CRYSTAL.darkened(0.15) if owned else Look.GOLD_DEEP.lightened(0.15), Look.GLASS_DEEP, owned)
	# Crest column: the crest the battle HUD lights for a revival, over the bundle's chip.
	var crest := block.position + Vector2(76, 106)
	ci.draw_circle(crest, 58, Color(tint, 0.05), true, -1, true)
	draw_icon(ci, crest, id, 44, tint)
	Look.chip(ci, Vector2(crest.x, block.position.y + 194), "DLC", 17, tint, Look.BG_DEEP, HORIZONTAL_ALIGNMENT_CENTER)
	# Name and benefits. The rows share one size: the largest at which each fits two lines.
	var text_x := block.position.x + 150.0
	var text_w := block.size.x - 150.0 - 228.0
	Look.text_box(ci, Rect2(text_x, block.position.y + 12, text_w, 42), Arena.label("store.%s.name" % id), 28, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	var rows := facts()
	var body_w := text_w - 34.0
	var fact_size := 18
	while fact_size > 13:
		var fits := true
		for row in rows:
			if float(Look.wrapped_lines(String(row[1]), body_w, fact_size).size()) * Look.line_height(fact_size) > FACT_TEXT_H:
				fits = false
				break
		if fits:
			break
		fact_size -= 1
	for n in range(rows.size()):
		var text := String(rows[n][1])
		var height := float(Look.wrapped_lines(text, body_w, fact_size).size()) * Look.line_height(fact_size)
		var mid := block.position.y + 58.0 + (float(n) + 0.5) * FACT_ROW_H
		draw_fact_glyph(ci, Vector2(text_x + 12, mid), String(rows[n][0]), tint)
		Look.wrap_text(ci, text, Rect2(text_x + 34, mid - height * 0.5, body_w, height), fact_size, Look.INK.lerp(Look.INK_DIM, 0.30), true)
	# Price column.
	var button := Rect2(block.end.x - 216, block.position.y + 86, 196, 58)
	var caption := Rect2(button.position.x - 8, button.end.y + 6, button.size.x + 16, 24)
	if owned:
		# Bought: a quiet tick where the price was. The zone stays, switched off.
		ui.zone(button, "store:buy:" + id, false)
		var mark := Vector2(button.position.x + 34, button.get_center().y + 14)
		ci.draw_circle(mark, 17, Color(Look.CRYSTAL, 0.14), true, -1, true)
		ci.draw_arc(mark, 17, 0, TAU, 40, Color(Look.CRYSTAL, 0.85), 1.6, true)
		Look.draw_check(ci, mark, 15, Look.CRYSTAL)
		Look.text_box(ci, Rect2(mark.x + 26, mark.y - 20, button.end.x - mark.x - 26, 40), Arena.label("store.owned"), 23, Look.CRYSTAL, HORIZONTAL_ALIGNMENT_LEFT)
		return
	var on := state in ["buy", "test"]
	var zone_id := "store:buy:" + id
	var down := on and ui.pressed == zone_id
	# The shared button draws the surface; the label is drawn here because a price is
	# foreign text (Look.price_box) and a running request carries a spinner.
	ui.button(ci, button, "", zone_id, on, Look.GREEN if state == "test" else Look.GOLD, 24)
	var label_box := Rect2(button.position + Vector2(12, 4 if down else 2), button.size - Vector2(24, 7))
	var ink := Look.BG_DEEP if state == "buy" else Look.INK if state == "test" else Look.INK_MUTE
	match state:
		"busy":
			var label := Arena.label("store.busy")
			var size := Look.fit_size(label, 20, Vector2(label_box.size.x - 30, label_box.size.y))
			var width := Look.text_width(label, size)
			_spinner(ci, Vector2(label_box.get_center().x - width * 0.5 - 6.0, label_box.get_center().y), 8.0, Look.GOLD, time)
			Look.text_box(ci, Rect2(label_box.position.x + 24, label_box.position.y, label_box.size.x - 24, label_box.size.y), label, 20, Look.INK_DIM)
		"offline":
			Look.text_box(ci, label_box, Arena.label("store.offline"), 21, ink)
		"test":
			Look.text_box(ci, label_box, Arena.label("store.test_unlock"), 22, ink)
		_:
			var price := Look.price_text(Store.price(id))
			if not price.is_empty():
				Look.price_box(ci, label_box, price, 26, ink)
			else:
				Look.text_box(ci, label_box, Arena.label("store.view_steam") if Store.shop_name() == "steam" else Arena.label("store.buy"), 23, ink)
	# Under the price: what kind of payment this is, in plain words.
	if state == "test":
		Look.text_box(ci, caption, Arena.label("store.test_note"), 15, Look.GREEN.lerp(Look.INK_DIM, 0.35))
	elif state != "offline":
		Look.text_box(ci, caption, Arena.label("store.once"), 15, Look.INK_DIM)


## Marks of the benefit rows, drawn (not baked) so they keep their weight at every size:
##   reroll  a jewel inside a turning arrow: the box is rolled again
##   revive  a ticket holding a star: the revival that brings a 5-star hero
##   hell    a spiked gate with embers inside: the Hellbound mode
##   coin · ward · crystal  marks of the earlier rows, kept for callers
## `scale` 1.0 is the 20 px row mark; the guide and the squad picker draw them larger.
static func draw_fact_glyph(ci: CanvasItem, at: Vector2, kind: String, color: Color, scale: float = 1.0) -> void:
	match kind:
		"reroll":
			var r := 10.0 * scale
			var end := PI * 1.30
			ci.draw_arc(at, r, -PI * 0.22, end, 28, color, maxf(1.4, 1.8 * scale), true)
			var tip := at + Vector2.from_angle(end) * r
			var along := Vector2.from_angle(end + PI * 0.5)
			var out := Vector2.from_angle(end)
			ci.draw_colored_polygon(PackedVector2Array([tip + along * 4.6 * scale, tip - along * 1.4 * scale + out * 4.2 * scale,
				tip - along * 1.4 * scale - out * 4.2 * scale]), color)
			draw_gem(ci, at + Vector2(0, 0.6 * scale), 5.4 * scale, color)
		"revive":
			_ticket(ci, at, scale, color)
		"hell":
			_hell_gate(ci, at, scale, color)
		"coin":
			ci.draw_circle(at, 9.0 * scale, color.darkened(0.45), true, -1, true)
			ci.draw_circle(at, 8.0 * scale, color.darkened(0.08), true, -1, true)
			ci.draw_arc(at, 5.2 * scale, 0, TAU, 20, color.lightened(0.45), 1.2, true)
		"ward":
			var r := 9.0 * scale
			var points := PackedVector2Array([at + Vector2(-r, -r * 0.75), at + Vector2(0, -r), at + Vector2(r, -r * 0.75),
				at + Vector2(r * 0.82, r * 0.4), at + Vector2(0, r), at + Vector2(-r * 0.82, r * 0.4)])
			ci.draw_polyline(points + PackedVector2Array([points[0]]), color, 1.8, true)
			ci.draw_line(at + Vector2(-3.5, 0) * scale, at + Vector2(3.5, 0) * scale, color, 1.8, true)
			ci.draw_line(at + Vector2(0, -3.5) * scale, at + Vector2(0, 3.5) * scale, color, 1.8, true)
		_:
			var top := at + Vector2(0, -10.0) * scale
			var bottom := at + Vector2(0, 10.0) * scale
			var left := at + Vector2(-6.0, -0.6) * scale
			var right := at + Vector2(6.0, -0.6) * scale
			ci.draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), color.darkened(0.22))
			ci.draw_colored_polygon(PackedVector2Array([top, at + Vector2(0, -0.6) * scale, bottom, left]), color.lightened(0.18))


## A cut jewel: a lit crown over a two-tone pavilion (not the life crystal's tall rhombus).
static func draw_gem(ci: CanvasItem, at: Vector2, w: float, color: Color) -> void:
	var girdle_l := at + Vector2(-w, -w * 0.12)
	var girdle_r := at + Vector2(w, -w * 0.12)
	var culet := at + Vector2(0, w * 0.86)
	ci.draw_colored_polygon(PackedVector2Array([girdle_l, girdle_r, culet]), color.darkened(0.30))
	ci.draw_colored_polygon(PackedVector2Array([girdle_l, at + Vector2(0, -w * 0.12), culet]), color.darkened(0.04))
	ci.draw_colored_polygon(PackedVector2Array([girdle_l, at + Vector2(-w * 0.55, -w * 0.64), at + Vector2(w * 0.55, -w * 0.64), girdle_r]), color.lightened(0.22))
	ci.draw_line(at + Vector2(-w * 0.50, -w * 0.58), at + Vector2(-w * 0.18, -w * 0.16), Color(1, 1, 1, 0.50), maxf(1.0, w * 0.13), true)


## A ticket with notched sides and a star on it.
static func _ticket(ci: CanvasItem, at: Vector2, scale: float, color: Color) -> void:
	var w := 11.0 * scale
	var h := 7.6 * scale
	var notch := 2.7 * scale
	var points := PackedVector2Array([at + Vector2(-w, -h), at + Vector2(w, -h)])
	for i in range(9):
		points.append(at + Vector2(w, 0) + Vector2.from_angle(-PI * 0.5 - PI * float(i) / 8.0) * notch)
	points.append(at + Vector2(w, h))
	points.append(at + Vector2(-w, h))
	for i in range(9):
		points.append(at + Vector2(-w, 0) + Vector2.from_angle(PI * 0.5 - PI * float(i) / 8.0) * notch)
	ci.draw_colored_polygon(points, Color(color, 0.22))
	points.append(points[0])
	ci.draw_polyline(points, color, maxf(1.3, 1.6 * scale), true)
	ci.draw_colored_polygon(Look.star_points(at, 5.4 * scale), color.lightened(0.18))


## A gate: an arch with spikes along its crown and embers rising in its dark opening.
static func _hell_gate(ci: CanvasItem, at: Vector2, scale: float, color: Color) -> void:
	var spring := at + Vector2(0, -1.0 * scale)
	var base := at.y + 9.5 * scale
	var outer := 8.6 * scale
	var inner := 5.0 * scale
	for angle in [PI * 1.25, PI * 1.5, PI * 1.75]:
		ci.draw_colored_polygon(PackedVector2Array([spring + Vector2.from_angle(angle - 0.20) * (outer - 0.5 * scale),
			spring + Vector2.from_angle(angle) * (outer + 3.6 * scale), spring + Vector2.from_angle(angle + 0.20) * (outer - 0.5 * scale)]), color)
	var frame := PackedVector2Array()
	var hole := PackedVector2Array()
	for i in range(13):
		frame.append(spring + Vector2.from_angle(PI + PI * float(i) / 12.0) * outer)
		hole.append(spring + Vector2.from_angle(PI + PI * float(i) / 12.0) * inner)
	frame.append_array(PackedVector2Array([Vector2(at.x + outer, base), Vector2(at.x - outer, base)]))
	hole.append_array(PackedVector2Array([Vector2(at.x + inner, base), Vector2(at.x - inner, base)]))
	ci.draw_colored_polygon(frame, color.darkened(0.28))
	ci.draw_colored_polygon(hole, Look.BG_DEEP)
	for flame in [[0.0, 7.6, 2.9], [-2.7, 4.6, 1.8], [2.7, 4.6, 1.8]]:
		var x: float = at.x + float(flame[0]) * scale
		var fh: float = float(flame[1]) * scale
		var fw: float = float(flame[2]) * scale
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - fw, base), Vector2(x - fw * 0.85, base - fh * 0.45),
			Vector2(x - fw * 0.25, base - fh * 0.82), Vector2(x, base - fh), Vector2(x + fw * 0.40, base - fh * 0.66),
			Vector2(x + fw * 0.90, base - fh * 0.36), Vector2(x + fw, base)]), HELL_EMBER if flame[0] == 0.0 else HELL_EMBER.lightened(0.25))
	frame.append(frame[0])
	ci.draw_polyline(frame, color, maxf(1.2, 1.5 * scale), true)


## Restore purchases: a real button with its own glyph, always on the sheet
## (the App Store requires that it can be found).
func _restore_button(ci: CanvasItem, ui: Ui, rect: Rect2, on: bool) -> void:
	ui.button(ci, rect, "", "store:restore", on, Look.PANEL_EDGE, 21)
	var down := on and ui.pressed == "store:restore"
	var ink := Look.INK if on else Color("#8b9aa5")
	var label := Arena.label("store.restore")
	var box := Rect2(rect.position + Vector2(48, 3 if down else 1), rect.size - Vector2(60, 6))
	var size := Look.fit_size(label, 21, box.size)
	var width := Look.text_width(label, size)
	var at := Vector2(box.get_center().x - width * 0.5 - 20.0, box.get_center().y)
	ci.draw_arc(at, 8.5, -PI * 0.42, PI * 1.25, 20, ink, 2.0, true)
	var tip := at + Vector2.from_angle(-PI * 0.42) * 8.5
	ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-6.5, -3.0), tip + Vector2(2.5, -5.5), tip + Vector2(0.5, 3.5)]), ink)
	Look.text_box(ci, box, label, 21, ink)


func _spinner(ci: CanvasItem, at: Vector2, radius: float, color: Color, time: float) -> void:
	ci.draw_arc(at, radius, 0, TAU, 24, Color(color, 0.22), 2.2, true)
	var turn := fposmod(time * 4.2, TAU)
	ci.draw_arc(at, radius, turn, turn + PI * 0.9, 14, color, 2.2, true)


func _dashed_rect(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	for side in [[rect.position, Vector2(rect.end.x, rect.position.y)], [Vector2(rect.position.x, rect.end.y), rect.end]]:
		ci.draw_dashed_line(side[0], side[1], color, 1.0, 5.0, true, true)
	for side in [[rect.position, Vector2(rect.position.x, rect.end.y)], [Vector2(rect.end.x, rect.position.y), rect.end]]:
		ci.draw_dashed_line(side[0], side[1], color, 1.0, 5.0, true, true)


static func _diamond(ci: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.72, 0),
		at + Vector2(0, radius), at + Vector2(-radius * 0.72, 0)]), color)


## The blessing's glyph, drawn, not baked: the life crystal between two wards that close
## around it. It is the same crest the battle HUD lights next to the life crystal, so what
## was bought is recognised where it works. Below 16 px it drops its fine parts. The
## colour's own alpha fades the whole glyph (the revival banner fades it out). `_id` is
## kept for callers; there is one product.
static func draw_icon(ci: CanvasItem, at: Vector2, _id: String, size: float, color: Color) -> void:
	var fine := size >= 16.0
	var a := color.a
	var tone := Color(color, 1.0)
	if fine:
		ci.draw_circle(at + Vector2(0, size * 0.06), size * 1.04, Color(Look.BG_DEEP, 0.55 * a), true, -1, true)
	ci.draw_circle(at, size, Color(Look.BG_DEEP.lerp(tone, 0.09), a), true, -1, true)
	ci.draw_arc(at, size, 0, TAU, 56 if fine else 28, Color(tone, 0.80 * a), maxf(1.3, size * 0.06), true)
	if fine:
		ci.draw_arc(at, size * 0.86, PI * 1.08, PI * 1.92, 24, Color(tone.lightened(0.4), 0.22 * a), 1.0, true)
	# The life crystal between two wards that close around it.
	var top := at + Vector2(0, -size * 0.60)
	var bottom := at + Vector2(0, size * 0.60)
	var left := at + Vector2(-size * 0.34, -size * 0.04)
	var right := at + Vector2(size * 0.34, -size * 0.04)
	ci.draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), Color(tone.darkened(0.22), a))
	ci.draw_colored_polygon(PackedVector2Array([top, at + Vector2(0, -size * 0.04), bottom, left]), Color(tone.lightened(0.18), a))
	if fine:
		ci.draw_line(top, bottom, Color(1, 1, 1, 0.55 * a), maxf(1.0, size * 0.04), true)
		for side in [-1.0, 1.0]:
			var mid: float = 0.0 if side > 0.0 else PI
			ci.draw_arc(at, size * 0.74, mid - PI * 0.30, mid + PI * 0.30, 18, Color(tone, 0.90 * a), maxf(1.6, size * 0.075), true)
			for end in [-1.0, 1.0]:
				ci.draw_circle(at + Vector2.from_angle(mid + end * PI * 0.30) * size * 0.74, maxf(1.2, size * 0.055), Color(tone, a), true, -1, true)
