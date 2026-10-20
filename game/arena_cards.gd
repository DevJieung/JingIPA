extends RefCounted
class_name ArenaCards

## The cards of ArenaScreen: the battlefield briefing that opens every stage (name plate with
## the stage and its ten waves, gate beacons on the real ground, the briefing sheet with the road
## diagram, the bodies, the elite and the boss), the reserve swap and the stage's result panel
## (2026-10-19 ladder: 「STAGE n 클리어」 and 「다음 STAGE」, 「STAGE n 실패 · WAVE k」, Hellbound's
## wave and record — D6, build/feedback-2026-10-19/D6/RECORD.md).
##
## Draws on the screen's own canvas (`s`) from ArenaScreen._draw, in the order the screen
## calls it, and registers its touch zones in the screen's `ui` as it goes, so the drawing
## order and the zone order (a later zone wins) are the screen's. Input, the run's clocks
## (_card_age, _result_age, _talent_age, _settled) and the pages and choices that buttons
## change stay on the screen.
##
## Uses from the screen: s._bench_choice, s._bench_page, s._card_age(),
## s._field_choice, s.main, s._result_age(), s._settled(), s.t, s.ui, s.view_3d and, when the
## screen has it (LB1), s.can_next_stage(). Zones: stage:start, result:home, result:retry,
## result:next, result:guardian, bench:*, close.
## Uses from the other views: s.hud._draw_diamond(), s.hud._shade(),
## s.hud._stage_label(), s.hud._draw_elite_crest(), s.hud._split().

## The road diagram's materials and the briefing's wells. Everything else is a Look token.
const DIAGRAM_NIGHT := Color("#0a1a24")
const DIAGRAM_OUTLINE := Color("#051019")
const DIAGRAM_STONE := Color("#9db2b8")
const INSET := Color("#0d1f29")
## Height of the main body's block on the briefing sheet (badge row, monsters, matchups).
const BODY_BLOCK_H := 112.0
## Hellbound's ember on its result card (the HUD's tag shares it).
const HELL_EDGE := ArenaHud.HELL

var s: ArenaScreen

## What the battlefield card lists and the road diagram of the layout it shows, read once
## per stage and per layout.
var _preview_key := ""
var _preview: Dictionary = {}
var _layout_key := ""
var _layout_shape: Dictionary = {}

func _init(screen: ArenaScreen) -> void:
	s = screen

func _tr(key: String) -> String:
	return Arena.label("arena." + key)

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

## The battlefield briefing: which stage this is, where it is fought, what comes down
## which roads and who waits at the end. It opens the run and every stage after a boss
## falls, and stays until its one button is pressed.
##
## The new field is the reveal, so the card keeps off it: a light veil, the name plate
## under the top strip, the briefing sheet over the idle command rail, and a mark on the
## real ground at every gate. The sheet's diagram sits where the minimap lives, so the
## roads read there first and are found there again once the battle runs.
func _draw_stage_card() -> void:
	s.ui.zone(Look.SCREEN, "modal:block")
	var preview := _stage_preview()
	var theme: Dictionary = preview["theme"]
	var body := String(theme.get("main_body", "wood"))
	var accent := Balance.body_color(body)
	var final: bool = preview["final"]
	var age := s._card_age()
	var settled := s._settled()
	var veil := 1.0 if settled else _ease_out(age / 0.30)
	s.draw_rect(ArenaScreen.BATTLEFIELD, Color(0.012, 0.03, 0.055, 0.27 * veil))
	# A shadow under the top strip seats the name plate on bright fields too.
	Look.gradient_rect(s, Rect2(0, 71, ArenaScreen.BATTLEFIELD.size.x, 104), Color(0.008, 0.024, 0.04, 0.62 * veil), Color(0.008, 0.024, 0.04, 0.0), true)
	if final:
		# The last field closes in: a red dusk from the bottom edge.
		Look.gradient_rect(s, Rect2(0, 560, ArenaScreen.BATTLEFIELD.size.x, 240), Color(0.42, 0.05, 0.08, 0.0), Color(0.42, 0.05, 0.08, 0.34 * veil), true)
	_draw_gate_beacons(age, settled)
	_draw_stage_band(preview, accent, age, settled)
	_draw_stage_panel(preview, accent, age, settled)

## What the card lists, read once per stage. Bodies are ordered by their share so the
## field's own monsters lead; the run's table keeps its fixed body order.
func _stage_preview() -> Dictionary:
	var key := "%d:%d:%d" % [Arena.run_seed, Arena.stage, Arena.theme_index]
	if key != _preview_key or _preview.is_empty():
		_preview_key = key
		_preview = Arena.stage_preview(Arena.stage)
		var rows: Array = (_preview["rows"] as Array).duplicate()
		var main := String((_preview["theme"] as Dictionary).get("main_body", ""))
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["percent"]) != int(b["percent"]): return int(a["percent"]) > int(b["percent"])
			if (String(a["body"]) == main) != (String(b["body"]) == main): return String(a["body"]) == main
			return Balance.MBODY_ORDER.find(String(a["body"])) < Balance.MBODY_ORDER.find(String(b["body"])))
		_preview["rows"] = rows
	return _preview

## Every gate marked on the real ground: a ring where the monsters step in and three
## chevrons walking down the road, in the camera's own perspective. Pale fields get the
## same marks: each stroke is laid over a dark one.
func _draw_gate_beacons(age: float, settled: bool) -> void:
	if s.view_3d.world == null: return
	var rim := Color(Look.BG_DEEP, 0.78)
	for lane in range(ArenaGeometry.route_count()):
		var k := 1.0 if settled else _ease_out((age - 0.28 - lane * 0.08) / 0.32)
		if k <= 0.0: continue
		var route := ArenaGeometry.route_points(lane)
		var gate := route[0]
		if not ArenaScreen.BATTLEFIELD.grow(-4).has_point(s.view_3d.project(gate, 0.05)): continue
		var ring := PackedVector2Array()
		var radius := 30.0 * (0.55 + 0.45 * k)
		for n in range(25):
			ring.append(s.view_3d.project(gate + Vector2.from_angle(n * TAU / 24.0) * radius, 0.05))
		s.draw_polyline(ring, Color(rim, rim.a * k), 6.0, true)
		s.draw_polyline(ring, Color(Look.GATE_MARK, k), 2.6, true)
		if not settled:
			# A slow second ring breathes outward: this is where they come from.
			var beat := fposmod(s.t * 0.7 + lane * 0.23, 1.0)
			var wave := PackedVector2Array()
			for n in range(25):
				wave.append(s.view_3d.project(gate + Vector2.from_angle(n * TAU / 24.0) * radius * (1.0 + beat * 0.9), 0.05))
			s.draw_polyline(wave, Color(Look.GATE_MARK, 0.55 * (1.0 - beat) * k), 2.0, true)
		for step in range(3):
			var index := mini(route.size() - 2, roundi((62.0 + step * 44.0) / ArenaGeometry.SAMPLE))
			var along := (route[index + 1] - route[index]).normalized()
			var across := Vector2(-along.y, along.x)
			var tip := s.view_3d.project(route[index] + along * 15.0, 0.05)
			var a := s.view_3d.project(route[index] - along * 9.0 + across * 21.0, 0.05)
			var b := s.view_3d.project(route[index] - along * 9.0 - across * 21.0, 0.05)
			var lit := 1.0 if settled else 0.45 + 0.55 * maxf(0.0, sin(s.t * 4.6 - step * 1.05))
			var mark := PackedVector2Array([a, tip, b])
			s.draw_polyline(mark, Color(rim, rim.a * k), 7.0, true)
			s.draw_polyline(mark, Color(Look.GATE_MARK, lit * k), 3.4, true)

## The name plate: biome emblem, the stage and its ten waves (the elite's and the boss's
## marked, each wave as tall as it is large), on a chapter's last stage the chapter boss, the
## battlefield's name, and its hazard rank counted in pips (never told by colour alone).
func _draw_stage_band(preview: Dictionary, accent: Color, age: float, settled: bool) -> void:
	var band := ArenaScreen.STAGE_BAND
	var theme: Dictionary = preview["theme"]
	var final: bool = preview["final"]
	# It settles from just under the top strip's line; it never rides over the strip.
	var k := 1.0 if settled else _ease_out(age / 0.24)
	s.draw_set_transform(Vector2(0, -(1.0 - k) * 8.0), 0, Vector2.ONE)
	var edge := Look.GOLD if final else accent.lerp(Look.STEEL, 0.30)
	var face := Color(0.115, 0.035, 0.05, 0.93) if final else Color(0.026, 0.066, 0.098, 0.92)
	Look.fill_round(s, Rect2(band.position + Vector2(0, 6), band.size), 6, Color(0, 0, 0, 0.36))
	Look.glass_panel(s, band, edge, face, true)
	# The biome's wash runs in from the emblem's side.
	Look.gradient_rect(s, Rect2(band.position + Vector2(6, 4), Vector2(250, band.size.y - 8)), Color(accent, 0.15), Color(accent, 0.0))
	Look.draw_body(s, band.position + Vector2(40, band.size.y * 0.5), 20, String(theme.get("main_body", "")))
	var x := band.position.x + 74.0
	# Stage chip (Hellbound: its tag), the stage's waves, and on a chapter's last stage its boss
	# (Hellbound: the endless mark — its waves never end).
	var hell := bool(preview.get("hell", false))
	var label := _tr("hell_tag") if hell else s.hud._stage_label(int(preview["stage"]))
	var chip := Look.chip(s, Vector2(x, band.position.y + 19), label, 17, HELL_EDGE if hell else (Look.WARN if final else Look.GOLD))
	var strip := _draw_wave_preview(Rect2(chip.end.x + 12, band.position.y + 7, 200, 22), preview, age, settled)
	if hell:
		Look.draw_infinity(s, Vector2(strip.end.x + 22, band.position.y + 22), 9.0, HELL_EDGE, 2.2)
	elif final:
		Look.chip(s, Vector2(strip.end.x + 12, band.position.y + 19), _tr("chapter_boss"), 15, Color(Look.WARN, 0.22), Look.WARN)
	# Hazard rank at the right end: a word and five pips.
	var right := band.end.x - 18.0
	Look.text_right(s, Vector2(right, band.position.y + 19), _tr("field_rank"), 15, Look.INK_DIM)
	var rank := clampi(int(preview["rank"]), 0, 5)
	for n in range(5):
		var pip := Vector2(right - 8.0 - (4 - n) * 21.0, band.position.y + 48)
		if n < rank:
			s.hud._draw_diamond(pip, 9, accent.lightened(0.22))
			s.draw_line(pip + Vector2(0, -9), pip + Vector2(0, 9), Color(1, 1, 1, 0.30), 1, true)
		else:
			s.draw_polyline(PackedVector2Array([pip + Vector2(0, -8), pip + Vector2(5.6, 0), pip + Vector2(0, 8), pip + Vector2(-5.6, 0), pip + Vector2(0, -8)]), Look.STEEL_DIM, 1.3, true)
	# The name: the largest words on the screen while the card is up.
	Look.text_box(s, Rect2(x, band.position.y + 24, right - 118.0 - x, 50), String(theme.get("ko", "")), 34, Look.IVORY if final else Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## The stage's ten waves before it starts: one column per wave, as tall as the wave is large,
## in the wave track's language — the fifth wave's elite stands violet with its notch and a
## crest over it, the tenth is the boss's pointed crimson step. The columns rise in one after
## another as the card lands. Returns the strip's rect.
func _draw_wave_preview(rect: Rect2, preview: Dictionary, age: float, settled: bool) -> Rect2:
	var waves: Array = preview.get("waves", [])
	if waves.is_empty(): return Rect2(rect.position, Vector2.ZERO)
	var low := 1 << 30
	var high := 0
	for entry in waves:
		low = mini(low, int(entry["size"]))
		high = maxi(high, int(entry["size"]))
	var count := waves.size()
	var gap := 4.0
	var width := (rect.size.x - gap * float(count - 1)) / float(count)
	var floor_y := rect.end.y
	for i in range(count):
		var entry: Dictionary = waves[i]
		var k := 1.0 if settled else _ease_out((age - 0.18 - float(i) * 0.035) / 0.22)
		if k <= 0.0: continue
		var size := int(entry["size"])
		var boss := bool(entry.get("boss", false))
		var elite := bool(entry.get("elite", false))
		# The boss's wave is the stage's peak whatever its count: always the tallest.
		var tall := (rect.size.y if boss else lerpf(8.0, rect.size.y - 6.0, float(size - low) / float(maxi(1, high - low)))) * k
		var x := rect.position.x + float(i) * (width + gap)
		var column := Rect2(x, floor_y - tall, width, tall)
		var color := Color(0.42, 0.57, 0.64, 0.92)
		if boss: color = Color("#d9565f")
		elif elite: color = Look.ELITE
		if boss:
			var tip := minf(width * 0.5, 7.0)
			s.draw_colored_polygon(PackedVector2Array([column.position + Vector2(0, tip), Vector2(column.get_center().x, column.position.y), Vector2(column.end.x, column.position.y + tip),
				column.end, Vector2(column.position.x, column.end.y)]), color)
		else:
			s.draw_rect(column, color)
			s.draw_line(column.position + Vector2(0, 0.5), Vector2(column.end.x, column.position.y + 0.5), Color(1, 1, 1, 0.28), 1.0)
		if elite and k >= 1.0:
			Look.draw_diamond(s, Vector2(column.get_center().x, column.position.y + minf(7.0, tall * 0.5)), minf(width * 0.32, 4.0), Color(Look.BG_DEEP, 0.75))
			s.hud._draw_elite_crest(Vector2(column.get_center().x, column.position.y - 6.0), 4.2)
	s.draw_line(Vector2(rect.position.x, floor_y + 1.5), Vector2(rect.end.x, floor_y + 1.5), Color(Look.STEEL, 0.45), 1.0)
	return rect

## The briefing sheet over the command rail: roads and gates, the monsters by body, the
## boss, and the card's one action.
func _draw_stage_panel(preview: Dictionary, accent: Color, age: float, settled: bool) -> void:
	var panel := ArenaScreen.STAGE_PANEL
	var final: bool = preview["final"]
	var k := 1.0 if settled else _ease_out(age / 0.28)
	s.draw_set_transform(Vector2((1.0 - k) * 48.0, 0), 0, Vector2.ONE)
	for n in range(8):
		s.draw_rect(Rect2(panel.position.x - 16 + n * 2, panel.position.y, 2, panel.size.y), Color(0.004, 0.016, 0.03, n * 0.034))
	# Opaque: the rail's cards must not show through the sheet that replaces them.
	s.draw_rect(panel, Look.BG_DEEP)
	Look.gradient_rect(s, Rect2(panel.position, Vector2(panel.size.x, 300)), Color(accent, 0.11), Color(accent, 0.0), true)
	s.draw_line(panel.position, Vector2(panel.position.x, panel.end.y), Look.STEEL, 1, true)
	s.draw_rect(Rect2(panel.position.x + 1, panel.position.y, 2, panel.size.y), Color(accent, 0.40))
	var x := panel.position.x + 14.0
	var w := panel.size.x - 28.0
	# Roads and gates first: this is what differs from field to field.
	var gates_label := _tr("gates")
	var gates_size := Look.text_box(s, Rect2(x + 22, panel.position.y + 9, w - 70, 26), gates_label, 17, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_draw_gate_dart(Vector2(x + 16, panel.position.y + 22), Vector2.RIGHT, 13.0, 7.0)
	Look.text_left(s, Vector2(x + 22 + Look.text_width(gates_label, gates_size) + 12, panel.position.y + 21), str(ArenaGeometry.route_count()), 24, Look.GATE_MARK)
	_draw_layout(Rect2(panel.position.x + panel.size.x * 0.5 - 104, panel.position.y + 52, 208, 208), accent, age, settled)
	var y := panel.position.y + 282.0
	s.draw_line(Vector2(x, y), Vector2(x + w, y), Color(Look.STEEL, 0.28), 1, true)
	# Who comes: the field's own body first, the rest as chips. When some of them fly,
	# the header says so (only guns and bows reach them).
	Look.text_box(s, Rect2(x + 2, y + 6, w - 4, 26), _tr("monsters"), 17, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	var rows: Array = preview["rows"]
	if _any_flies(rows):
		var word := _tr("flying")
		var word_w := Look.text_width(word, 15)
		Look.text_right(s, Vector2(x + w - 2, y + 19), word, 15, Look.AIR)
		Look.draw_wing(s, Vector2(x + w - 2 - word_w - 14, y + 19), 7.0)
	y += 36.0
	if not rows.is_empty():
		_draw_body_block(Rect2(x, y, w, BODY_BLOCK_H), rows[0])
		y += BODY_BLOCK_H + 6.0
	var minors := mini(4, rows.size() - 1)
	for n in range(minors):
		_draw_body_chip(Rect2(x + (n % 2) * (w * 0.5 + 3.0), y + (n / 2) * 44.0, w * 0.5 - 3.0, 38), rows[n + 1])
	y += ceili(minors / 2.0) * 44.0
	# Who waits at the end. The plate takes what room is left above the button.
	var button := Rect2(x, panel.end.y - 70, w, 58)
	var plate_bottom := button.position.y - 10.0
	var plate_top := maxf(y + 4.0, plate_bottom - 150.0)
	_draw_boss_plate(Rect2(x, plate_top, w, plate_bottom - plate_top), preview, accent, final)
	s.ui.button(s, button, _tr("stage_start"), "stage:start", true, Look.GOLD, 25)
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## The field's main body in three rows: badge, name and share / its monsters / what it
## is weak to and immune to (attack elements are circles, bodies are squares, as
## everywhere in the game). The last row is read from the rule table, not written here.
func _draw_body_block(rect: Rect2, row: Dictionary) -> void:
	var body := String(row["body"])
	var color := Balance.body_color(body)
	Look.fill_round(s, rect, 5, INSET)
	# The share again as a bar behind the first row: a length, not only a number.
	Look.fill_round(s, Rect2(rect.position, Vector2(maxf(10.0, rect.size.x * clampf(float(row["percent"]) / 100.0, 0.0, 1.0)), 42)), 5, Color(color, 0.17))
	s.draw_rect(Rect2(rect.position.x, rect.position.y + 6, 3, 30), color)
	Look.draw_body(s, rect.position + Vector2(25, 21), 13, body)
	Look.text_box(s, Rect2(rect.position.x + 48, rect.position.y + 4, rect.size.x - 48 - 92, 34), Balance.body_ko(body), 21, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(s, Rect2(rect.end.x - 92, rect.position.y + 1, 84, 40), "%d%%" % int(row["percent"]), 26, Look.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	var monsters: Array = row["monsters"]
	var shown := mini(4, monsters.size())
	for n in range(shown):
		_draw_monster_thumb(Rect2(rect.position.x + 10 + n * 44.0, rect.position.y + 44, 40, 38), monsters[n])
	s.draw_line(Vector2(rect.position.x + 10, rect.position.y + 85), Vector2(rect.end.x - 10, rect.position.y + 85), Color(Look.STEEL, 0.16), 1, true)
	var at := rect.position.x + 12.0
	var mid := rect.position.y + 98.0
	var weak: Array = Balance.body_weak(body)
	var immune: Array = Balance.body_immune(body)
	if not weak.is_empty():
		Look.text_left(s, Vector2(at, mid), _tr("weak"), 15, Look.INK_DIM)
		at += Look.text_width(_tr("weak"), 15) + 8.0
		for element in weak:
			Look.draw_elem(s, Vector2(at + 10, mid), 9, String(element))
			at += 25.0
		at += 10.0
	if not immune.is_empty():
		Look.text_left(s, Vector2(at, mid), _tr("immune"), 15, Look.INK_DIM)
		at += Look.text_width(_tr("immune"), 15) + 8.0
		for element in immune:
			Look.draw_elem_x(s, Vector2(at + 10, mid), 9, String(element))
			at += 25.0

## A lesser body of the stage: badge, share, and up to two of its monsters.
func _draw_body_chip(rect: Rect2, row: Dictionary) -> void:
	var body := String(row["body"])
	Look.fill_round(s, rect, 5, INSET)
	Look.draw_body(s, rect.position + Vector2(19, rect.size.y * 0.5), 10, body)
	Look.text_box(s, Rect2(rect.position.x + 35, rect.position.y + 4, 50, 32), "%d%%" % int(row["percent"]), 19, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	var monsters: Array = row["monsters"]
	var shown := mini(2, monsters.size())
	for n in range(shown):
		_draw_monster_thumb(Rect2(rect.end.x - 5 - (shown - n) * 27.0, rect.position.y + 6, 26, 28), monsters[n])

func _draw_monster_thumb(box: Rect2, monster: Dictionary) -> void:
	if not Look.draw_monster_portrait(s, String(monster.get("id", "")), box):
		Look.draw_body(s, box.get_center(), minf(box.size.x, box.size.y) * 0.32, String(monster.get("body", "")))
	# A flyer carries wings on its corner; the stage's elite (the fifth wave's) its violet crest.
	if Balance.flies(monster): Look.draw_wing(s, Vector2(box.end.x - 6, box.position.y + 6), 5.5)
	var elite: Dictionary = _preview.get("elite", {})
	if not elite.is_empty() and String(elite.get("id", "")) == String(monster.get("id", "")):
		s.hud._draw_elite_crest(Vector2(box.position.x + 6, box.position.y + 7), 5.0)

## Whether any monster of these rows flies.
func _any_flies(rows: Array) -> bool:
	for row in rows:
		for monster in row["monsters"]:
			if Balance.flies(monster): return true
	return false

## The stage's boss: its render, its name, and on the last stage what beating it means
## (a footer of its own, clear of the render).
func _draw_boss_plate(rect: Rect2, preview: Dictionary, accent: Color, final: bool) -> void:
	var boss: Dictionary = preview["boss"]
	var theme: Dictionary = preview["theme"]
	var edge := Look.GOLD if final else Look.BOSS
	Look.glass_panel(s, rect, edge, Color(0.10, 0.03, 0.055, 0.96), final)
	var foot_h := 28.0 if final else 0.0
	var inner := Rect2(rect.position, Vector2(rect.size.x, rect.size.y - foot_h))
	# Its render stands on the right, lit from behind in its body's colour.
	var art_w := minf(132.0, inner.size.y + 8.0)
	var art := Rect2(inner.end.x - art_w - 6.0, inner.position.y + 6, art_w, inner.size.y - 10)
	var glow_at := Vector2(art.get_center().x, art.end.y - art.size.y * 0.44)
	for layer in range(12):
		s.draw_circle(glow_at, minf(art.size.y, art.size.x) * (0.60 - layer * 0.042), Color(accent, 0.022), true, -1, true)
	if not Look.draw_monster_portrait(s, String(boss.get("id", "")), art):
		Look.draw_body(s, art.get_center(), 24, String(boss.get("body", "")))
	var x := rect.position.x + 14.0
	var w := art.position.x - x - 4.0
	Look.text_box(s, Rect2(x, inner.position.y + 7, w, 26), _tr("chapter_boss") if final else _tr("boss_stage"), 16, Look.WARN, HORIZONTAL_ALIGNMENT_LEFT)
	var body := String(boss.get("body", theme.get("main_body", "")))
	var foot := inner.end.y - 20.0
	var title := String(boss.get("ko", ""))
	var name_top := inner.position.y + 34.0
	var room := foot - 18.0 - name_top
	# A long name takes two lines at full size. When the plate is too short to hold them
	# above the body line, the body line steps aside: the block above already names it.
	var two_lines := Look.wrapped_lines(title, w, 22).size() > 1
	var body_line := not two_lines or room >= Look.line_height(22) * 2.0
	if not body_line: room = inner.end.y - 6.0 - name_top
	Look.wrap_text(s, title, Rect2(x, name_top, w, clampf(room, 36.0, 72.0)), 22, Look.INK, true)
	if body_line:
		Look.draw_body(s, Vector2(x + 11, foot), 10, body)
		var body_w := Look.text_box(s, Rect2(x + 28, foot - 14, w - 28, 28), Balance.body_ko(body), 17, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		if Balance.flies(boss):
			var wing_x := x + 28 + Look.text_width(Balance.body_ko(body), body_w) + 18.0
			Look.draw_wing(s, Vector2(wing_x, foot), 7.0)
			Look.text_left(s, Vector2(wing_x + 12, foot), _tr("flying"), 15, Look.AIR)
	if final:
		var strip := Rect2(rect.position.x + 4, rect.end.y - foot_h - 2, rect.size.x - 8, foot_h - 2)
		s.draw_rect(strip, Color(Look.GOLD, 0.13))
		s.draw_line(strip.position, Vector2(strip.end.x, strip.position.y), Color(Look.GOLD, 0.45), 1, true)
		Look.text_box(s, Rect2(strip.position.x + 8, strip.position.y - 1, strip.size.x - 16, 28), _tr("final_note"), 16, Look.IVORY)

## The layout's roads as unit-radius polylines with their running lengths, built once
## per layout: arms first, then feeders, each starting at its own gate.
func _road_shape() -> Dictionary:
	var key := ArenaGeometry.layout()
	if key != _layout_key or _layout_shape.is_empty():
		_layout_key = key
		var roads: Array = []
		for polyline in ArenaGeometry.road_polylines():
			var points := PackedVector2Array()
			var lengths := PackedFloat32Array()
			var total := 0.0
			for i in range(polyline.size()):
				var p: Vector2 = (polyline[i] - Balance.ARENA_CENTER) / ArenaGeometry.RADIUS
				if i > 0: total += p.distance_to(points[i - 1])
				points.append(p)
				lengths.append(total)
			roads.append({"points": points, "lengths": lengths, "total": total})
		var gates: Array = []
		for lane in range(ArenaGeometry.route_count()):
			gates.append((ArenaGeometry.route_points(lane)[0] - Balance.ARENA_CENTER).normalized())
		_layout_shape = {"roads": roads, "gates": gates}
	return _layout_shape

## Road diagram of the current layout inside `rect`: field rim, roads at their true
## width, the plaza and crystal, a dart at every gate and chevrons that walk the
## roads toward the crystal. When the card opens the roads draw themselves in from the
## gates, which is the direction the monsters will take.
func _draw_layout(rect: Rect2, accent: Color, age: float = 99.0, settled: bool = true) -> void:
	var shape := _road_shape()
	var centre := rect.get_center()
	var radius := rect.size.x * 0.5
	s.draw_circle(centre + Vector2(0, 4), radius + 3, Color(0, 0, 0, 0.34), true, -1, true)
	s.draw_circle(centre, radius, DIAGRAM_NIGHT.lerp(accent, 0.07), true, -1, true)
	s.draw_arc(centre, radius - 6, 0, TAU, 96, Color(0.55, 0.77, 0.84, 0.10), 1, true)
	var reveal := 1.0 if settled else _ease_out((age - 0.16) / 0.80)
	var width := ArenaGeometry.ROAD_WIDTH / ArenaGeometry.RADIUS * radius
	var stone := DIAGRAM_STONE.lerp(accent, 0.20)
	var drawn: Array = []
	for road in shape["roads"]:
		var points: PackedVector2Array = road["points"]
		var lengths: PackedFloat32Array = road["lengths"]
		var shown: float = float(road["total"]) * reveal
		var line := PackedVector2Array()
		for i in range(points.size()):
			if lengths[i] > shown:
				if i > 0:
					var span := lengths[i] - lengths[i - 1]
					line.append(centre + points[i - 1].lerp(points[i], (shown - lengths[i - 1]) / maxf(0.0001, span)) * radius)
				break
			line.append(centre + points[i] * radius)
		drawn.append(line)
	for line in drawn:
		if line.size() >= 2: s.draw_polyline(line, DIAGRAM_OUTLINE, width + 4.5, true)
	for line in drawn:
		if line.size() >= 2: s.draw_polyline(line, stone, width, true)
	var plaza := ArenaGeometry.PLAZA_RADIUS / ArenaGeometry.RADIUS * radius
	s.draw_circle(centre, plaza + 2.2, DIAGRAM_OUTLINE, true, -1, true)
	s.draw_circle(centre, plaza, stone.lightened(0.08), true, -1, true)
	# Chevrons walk each road toward the crystal.
	var spacing := 0.34
	var drift := 0.0 if settled else fposmod(s.t * 0.13, spacing)
	for road in shape["roads"]:
		var points: PackedVector2Array = road["points"]
		var lengths: PackedFloat32Array = road["lengths"]
		var limit: float = float(road["total"]) * reveal - 0.04
		var dist := 0.16 + drift
		while dist < limit:
			var i := clampi(lengths.bsearch(dist), 1, points.size() - 1)
			var along := (points[i] - points[i - 1]).normalized()
			var span := lengths[i] - lengths[i - 1]
			var at := centre + points[i - 1].lerp(points[i], (dist - lengths[i - 1]) / maxf(0.0001, span)) * radius
			var across := Vector2(-along.y, along.x)
			s.draw_polyline(PackedVector2Array([at - along * 2.8 + across * 4.8, at + along * 2.8, at - along * 2.8 - across * 4.8]), Color(0.03, 0.10, 0.14, 0.50), 2.0, true)
			dist += spacing
	s.draw_arc(centre, radius, 0, TAU, 96, Color(0.60, 0.80, 0.86, 0.80), 1.6, true)
	# The crystal the roads lead to.
	for layer in range(3):
		s.draw_circle(centre, plaza * (0.95 - layer * 0.2), Color(Look.CRYSTAL, 0.10), true, -1, true)
	s.hud._draw_diamond(centre, plaza * 0.62, Look.CRYSTAL_DEEP)
	s.draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -plaza * 0.62), centre + Vector2(0, plaza * 0.62), centre + Vector2(-plaza * 0.415, 0)]), Look.CRYSTAL)
	# Gates: a dart outside the rim, pointing in. A plain triangle is nearly equilateral
	# and reads the same at every third of a turn; the notched tail keeps its heading.
	var gates: Array = shape["gates"]
	for lane in range(gates.size()):
		var out: Vector2 = gates[lane]
		var pop := 1.0 if settled else _ease_out((age - 0.10 - lane * 0.07) / 0.22)
		if pop <= 0.0: continue
		if not settled:
			var beat := fposmod(s.t * 0.7 + lane * 0.23, 1.0)
			s.draw_arc(centre + out * (radius + 5.0), 9.0 + beat * 9.0, 0, TAU, 20, Color(Look.GATE_MARK, 0.45 * (1.0 - beat)), 1.5, true)
		_draw_gate_dart(centre + out * (radius - 4.0), -out, 18.0 * pop, 9.5 * pop)

## A gate mark: a dart whose tip is at `tip` and which flies along `heading`.
func _draw_gate_dart(tip: Vector2, heading: Vector2, length: float, half: float) -> void:
	if length <= 0.5: return
	var side := Vector2(-heading.y, heading.x)
	var tail := tip - heading * length
	var shape := PackedVector2Array([tip, tail + side * half, tail + heading * length * 0.30, tail - side * half])
	s.draw_polyline(shape + PackedVector2Array([tip]), DIAGRAM_OUTLINE, 4.0, true)
	s.draw_colored_polygon(shape, Look.GATE_MARK)

func _draw_bench() -> void:
	s.hud._shade()
	Look.sheet_title(s, Rect2(194, 106, 892, 80), _tr("bench"), _tr("field_select"))
	for i in range(Arena.heroes.size()):
		var rect := Rect2(138 + i * 171, 202, 151, 151)
		HeroCard.draw(s, rect, Arena.heroes[i], i == s._field_choice)
		s.ui.zone(rect.grow(4), "bench:field:%d" % i)
	Look.text_box(s, Rect2(176, 374, 928, 30), _tr("bench_select"), Look.TYPE_BODY, Look.INK_DIM)
	if Arena.bench.is_empty():
		Look.text_box(s, Rect2(254, 461, 772, 90), _tr("bench_empty"), 29, Look.INK_DIM)
	else:
		s._bench_page = clampi(s._bench_page, 0, maxi(0, (Arena.bench.size() - 1) / 6))
		for n in range(6):
			var index := s._bench_page * 6 + n
			if index >= Arena.bench.size(): break
			var rect := Rect2(138 + n * 171, 429, 151, 174)
			var hero: Dictionary = Arena.bench[index]
			HeroCard.draw(s, rect, hero, index == s._bench_choice)
			s.ui.zone(rect.grow(4), "bench:reserve:%d" % index)
			var maximum := int(hero["tier"]) >= Balance.TIER_ATK.size() - 1
			var needed := Arena.growth_needed(hero)
			Look.text_box(s, Rect2(rect.position.x - 1, 615, rect.size.x + 2, 24), _tr("maxed") if maximum else "%d / %d" % [int(hero.get("growth_points", 0)), needed], 17, Look.GOLD if maximum else Look.CRYSTAL)
	s.ui.button(s, Rect2(98, 648, 66, 45), "<", "bench:prev", s._bench_page > 0, Look.PANEL_EDGE, 25)
	s.ui.button(s, Rect2(1116, 648, 66, 45), ">", "bench:next", (s._bench_page + 1) * 6 < Arena.bench.size(), Look.PANEL_EDGE, 25)
	s.ui.button(s, Rect2(220, 677, 392, 65), _tr("resume"), "close", true, Look.PANEL_EDGE, Look.TYPE_BUTTON_2)
	s.ui.button(s, Rect2(668, 677, 392, 65), _tr("swap"), "bench:swap", s._bench_choice >= 0 and s._field_choice >= 0, Look.GOLD, Look.TYPE_BUTTON)

## The stage's result. The headline says it in one line with the number large — 「STAGE 12
## 클리어」, 「STAGE 12 실패」, Hellbound's 「23웨이브 도달」 — over the stage's ten waves (all
## lit after a win, the fallen one marked after a defeat, Hellbound's block of ten) and the wave
## it ended on (Hellbound: its best record, and a chip when this run set it). Then where it was
## fought and what the stage did, and the buttons: after a win 「야영지로」 · 「다시 도전」 ·
## 「다음 STAGE」 (gold, only while the next stage is open), else home and the gold retry.
##
## A defeat without the DLC adds one quiet strip *under* the buttons. It is never the primary
## action: the gold button stays "try again", the strip's own button is a secondary one and
## only opens the purchase sheet, where the price is.
##
## Entrance (only for a result this screen saw arrive, and only while it runs): the shade
## comes in first, then the card rises out of it, the headline number settles from a little
## larger, and after a win a glint crosses the ten lit waves as it did on the boss's banner.
## Until the card has arrived its buttons do not answer.
func _draw_result() -> void:
	var age := s._result_age()
	s.draw_rect(Look.SCREEN, Color(Look.SHADE, Look.SHADE.a * _ease_out(age / ArenaScreen.RESULT_SHADE_IN)))
	s.ui.zone(Look.SCREEN, "modal:block")
	var arrive := _ease_out((age - ArenaScreen.RESULT_CARD_AT) / ArenaScreen.RESULT_CARD_IN)
	if arrive <= 0.0: return
	var rise := Vector2(0, (1.0 - arrive) * 14.0)
	s.draw_set_transform(rise, 0, Vector2.ONE)
	var sim = Arena.sim
	var won: bool = sim != null and sim.won
	var hell: bool = Arena.hell
	var offer: bool = not won and not hell and sim != null and sim.revives_left() > 0 and Store.has_shop() and not Store.owns(Store.GUARDIAN)
	var height := 598.0 if offer else 448.0
	var card := Rect2(260, 70 + (730 - height) * 0.5, 760, height)
	var mid := card.get_center().x
	var y := card.position.y
	Look.fill_round(s, Rect2(card.position + Vector2(0, 7), card.size), 8, Color(0, 0, 0, 0.40))
	Look.glass_panel(s, card, Look.GOLD if won else (HELL_EDGE if hell else Look.STEEL), Look.GLASS_FACE, won)
	# How it ended.
	var state_color := Look.GOLD if won else Look.WARN
	var state := _tr("victory") if won else _tr("defeat")
	var state_box := Rect2(card.position.x + 76, y + 20, card.size.x - 152, 46)
	var state_size := Look.text_box(s, Rect2(state_box.position.x + 16, state_box.position.y, state_box.size.x - 16, state_box.size.y), state, 30, state_color)
	_draw_result_crystal(Vector2(mid + 8.0 - Look.text_width(state, state_size) * 0.5 - 22.0, state_box.get_center().y + 3.0), 9.0, won)
	# Between the brass rules: the stage's chapter, or Hellbound's tag.
	var caption_y := y + 88.0
	var caption_half := 16.0
	if hell:
		var tag := _tr("hell_tag")
		var tag_w := Look.text_width(tag, 15) + 22.0
		var tag_rect := Rect2(mid - tag_w * 0.5, caption_y - 12.0, tag_w, 24.0)
		s.draw_rect(tag_rect, Color(HELL_EDGE, 0.22))
		s.draw_rect(tag_rect, Color(HELL_EDGE, 0.80), false, 1.0)
		Look.text_box(s, tag_rect, tag, 15, HELL_EDGE)
		caption_half = tag_w * 0.5 + 12.0
	else:
		var chapter := _tr("chapter_n") % ceili(float(maxi(1, Arena.stage)) / 10.0)
		Look.text_center(s, Vector2(mid, caption_y), chapter, 18, Look.INK_DIM)
		caption_half = Look.text_width(chapter, 18) * 0.5 + 16.0
	for side in [-1.0, 1.0]:
		s.draw_line(Vector2(mid + side * caption_half, caption_y), Vector2(mid + side * (caption_half + 110.0), caption_y), Color(Look.GOLD_DEEP, 0.75), 1.4, true)
		s.hud._draw_diamond(Vector2(mid + side * (caption_half + 110.0), caption_y), 4.5, Look.GOLD_DEEP)
	# The headline: one line, the number large between the template's words.
	var wave: int = maxi(1, int(sim.wave_reached())) if sim != null else 1
	var template := _tr("wave_reached") if hell else (_tr("stage_clear_n") if won else _tr("stage_fail_n"))
	var figure := Look.IVORY if won else Look.GOLD
	_draw_headline(Vector2(mid, y + 158.0), template, wave if hell else Arena.stage, figure, won, age, rise, card.size.x - 60.0)
	# The waves, and the wave it ended on (Hellbound: the record).
	var total := Balance.ARENA_WAVES
	var first := (wave - 1) / total * total + 1 if hell else 1
	var held := total if won else wave - first
	var track := Rect2(mid - 210, y + 232, 300, 12)
	var glint := (age - ArenaScreen.RESULT_CARD_AT - ArenaScreen.RESULT_CARD_IN) / 0.50 if won else -1.0
	Look.draw_wave_track(s, track, wave - first + 1, total, held, Look.wave_marks(first, total, hell), 0.0, not won, 1.0, glint)
	var side_x := track.end.x + 16.0
	if hell:
		var best := maxi(Save.hell_best_wave, wave)
		var record := _tr_fmt("hell.best", best)
		var record_size := Look.text_box(s, Rect2(side_x, track.get_center().y - 15.0, card.end.x - 40.0 - side_x, 30), record, 19, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
		if wave >= best and wave > s.hud.hell_best_before:
			var chip_x := side_x + Look.text_width(record, record_size) + 10.0
			var chip_w := Look.text_width(_tr("hell_new_best"), 13) + 20.0
			if chip_x + chip_w < card.end.x - 24.0:
				Look.chip(s, Vector2(chip_x, track.get_center().y), _tr("hell_new_best"), 13, Look.GOLD, Look.BG_DEEP)
			else:
				Look.chip(s, Vector2(side_x, track.get_center().y - 24.0), _tr("hell_new_best"), 13, Look.GOLD, Look.BG_DEEP)
	else:
		var label := _tr("wave_label") % (total if won else wave)
		Look.text_box(s, Rect2(side_x, track.get_center().y - 17.0, card.end.x - 40.0 - side_x, 34), label, 22, Look.GOLD if won else Look.WARN, HORIZONTAL_ALIGNMENT_LEFT)
	# Where it was fought, and what the stage did.
	if sim != null:
		var theme: Dictionary = Arena.theme_for(1)
		var field := String(theme.get("ko", ""))
		var field_size := Look.fit_size(field, 22, Vector2(card.size.x - 200, 34))
		var field_w := Look.text_width(field, field_size)
		Look.draw_body(s, Vector2(mid - field_w * 0.5 - 6.0, y + 280), 11, String(theme.get("main_body", "")))
		Look.text_left(s, Vector2(mid - field_w * 0.5 + 14.0, y + 280), field, field_size, Look.INK)
		# What the stage did, as one centred row: kills, the best rank, and the revival tickets
		# it used. An owner who is defeated has used them all, and the row says so: that is why
		# the crystal did not reform this time.
		var stats: Array = [[_tr("kills") + "  %d" % Arena.kills, Look.INK_DIM, false]]
		if Arena.best_tier >= 0:
			stats.append([_tr("best_tier") + "  " + I18n.t(Look.star_label(Arena.best_tier)), Look.INK_DIM, false])
		if sim.revives >= Balance.ARENA_REVIVE_USES and not won:
			stats.append([_tr("revives_spent") % sim.revives, Look.WARN.lerp(Look.INK_DIM, 0.35), true])
		elif sim.revives > 0:
			stats.append([_tr("revives_used") % sim.revives, Look.INK_DIM, true])
		_draw_stat_row(Vector2(mid, y + 322), card.size.x - 80.0, stats)
	var buttons := y + 358.0
	# The offer registers first so the run buttons always win a shared edge.
	if offer:
		var strip := Rect2(card.position.x + 40, buttons + 62 + 26, card.size.x - 80, 124)
		s.draw_line(Vector2(strip.position.x, strip.position.y - 13), Vector2(strip.end.x, strip.position.y - 13), Color(Look.PANEL_EDGE, 0.40), 1, true)
		Look.fill_round(s, strip, 6, Color(0.01, 0.03, 0.05, 0.72))
		var quiet := Look.GOLD.lerp(Look.INK_DIM, 0.30)
		StoreView.draw_icon(s, strip.position + Vector2(46, strip.size.y * 0.5), Store.GUARDIAN, 26, quiet)
		var text_x := strip.position.x + 88.0
		var button_w := 196.0
		var text_w := strip.size.x - 88.0 - button_w - 30.0
		var product := Arena.label("store.guardian.name")
		var name_size := Look.text_box(s, Rect2(text_x, strip.position.y + 8, text_w, 30), product, 19, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
		# The price is on the strip itself: nothing about the offer waits behind a tap.
		var price := Look.price_text(Store.price(Store.GUARDIAN))
		var name_w := Look.text_width(product, name_size)
		if not price.is_empty() and text_w - name_w > 60.0:
			Look.price_box(s, Rect2(text_x + name_w + 12.0, strip.position.y + 8, text_w - name_w - 12.0, 30), price, 17, quiet, HORIZONTAL_ALIGNMENT_LEFT)
		# Room for three lines: the revival ticket's copy names the 5-star hero (no gold).
		Look.wrap_text(s, _tr("revive_offer") % Balance.ARENA_REVIVE_USES, Rect2(text_x, strip.position.y + 40, text_w, 78), 15, Look.INK_DIM, true)
		s.ui.button(s, Rect2(strip.end.x - button_w - 16, strip.position.y + 34, button_w, 56), _tr("revive_now"), "result:guardian", true, Look.GOLD_DEEP, 20)
	if won:
		var width := (card.size.x - 80.0 - 32.0) / 3.0
		var next_on: bool = s.can_next_stage() if s.has_method("can_next_stage") else (not hell and Arena.can_play(Arena.stage + 1))
		s.ui.button(s, Rect2(card.position.x + 40, buttons, width, 62), _tr("home"), "result:home", s.main != null, Look.PANEL_EDGE, 25)
		s.ui.button(s, Rect2(card.position.x + 40 + width + 16.0, buttons, width, 62), _tr("retry"), "result:retry", true, Look.PANEL_EDGE, 25)
		s.ui.button(s, Rect2(card.end.x - 40 - width, buttons, width, 62), _tr("next_stage"), "result:next", next_on, Look.GOLD, 25)
	else:
		s.ui.button(s, Rect2(card.position.x + 40, buttons, 328, 62), _tr("home"), "result:home", s.main != null, Look.PANEL_EDGE, 25)
		s.ui.button(s, Rect2(card.end.x - 368, buttons, 328, 62), _tr("retry"), "result:retry", true, Look.GOLD, 25)
	if arrive < 1.0:
		# Still rising: the shade's own colour lies over the card and thins out, and one
		# more blocking zone on top swallows taps until the card has arrived.
		s.draw_rect(card.grow(12.0), Color(Look.SHADE, 1.0 - arrive))
		s.ui.zone(Look.SCREEN, "modal:block")
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## One line with its number large: the catalog template ("STAGE %d 클리어", "Reached wave
## %d", "%d웨이브 도달") split round its number, the words at 40 px and the number at 104 px,
## centred on `at` and shrunk together when the card is narrower. The number settles from a
## little larger, about its own middle; after a win a warm light sits behind it.
func _draw_headline(at: Vector2, template: String, number: int, figure: Color, won: bool, age: float, rise: Vector2, room: float) -> void:
	var parts := ArenaHud._split(template)
	var lead: String = parts[0]
	var tail: String = parts[1]
	var digits := str(number)
	var big := 104
	var small := 40
	var lead_w := Look.text_width(lead, small)
	var number_w := Look.text_width(digits, big)
	var tail_w := Look.text_width(tail, small)
	var scale := minf(1.0, room / maxf(1.0, lead_w + number_w + tail_w))
	if scale < 1.0:
		big = maxi(60, floori(big * scale))
		small = maxi(24, floori(small * scale))
		lead_w = Look.text_width(lead, small)
		number_w = Look.text_width(digits, big)
		tail_w = Look.text_width(tail, small)
	var x := at.x - (lead_w + number_w + tail_w) * 0.5
	var drop := (float(big) - float(small)) * 0.31
	if won:
		# A warm light behind the number; many thin layers so no ring shows.
		for layer in range(18):
			s.draw_circle(Vector2(x + lead_w + number_w * 0.5, at.y + 2.0), 132.0 - layer * 6.5, Color(Look.GOLD, 0.0075), true, -1, true)
	if not lead.is_empty(): Look.text_left(s, Vector2(x, at.y + drop), lead, small, figure)
	var land := 1.0 + 0.14 * (1.0 - _ease_out((age - ArenaScreen.RESULT_CARD_AT) / 0.34))
	var number_mid := Vector2(x + lead_w + number_w * 0.5, at.y)
	s.draw_set_transform(rise + number_mid * (1.0 - land), 0, Vector2(land, land))
	Look.text_left(s, Vector2(x + lead_w, at.y), digits, big, figure)
	s.draw_set_transform(rise, 0, Vector2.ONE)
	if not tail.is_empty(): Look.text_left(s, Vector2(x + lead_w + number_w + 2.0, at.y + drop), tail, small, figure)

## A catalog template outside the arena's own keys ("hell.best"), formatted.
func _tr_fmt(key: String, value: int) -> String:
	var template := Arena.label(key)
	return template % value if template.contains("%d") else template + " %d" % value

## A centred row of run facts with a small diamond between them. Each entry is
## [text, colour, with_crest]; the crest marks the blessing's line. The row shrinks its
## type when three long entries do not fit.
func _draw_stat_row(at: Vector2, width: float, stats: Array) -> void:
	var gap := 40.0
	var size := 21
	var total := INF
	while total > width and size > 15:
		size -= 1
		total = gap * float(stats.size() - 1)
		for entry in stats:
			total += Look.text_width(String(entry[0]), size) + (24.0 if bool(entry[2]) else 0.0)
	var x := at.x - total * 0.5
	for n in range(stats.size()):
		var entry: Array = stats[n]
		var tone: Color = entry[1]
		if n > 0:
			s.hud._draw_diamond(Vector2(x - gap * 0.5, at.y), 4, Look.STEEL_DIM)
		if bool(entry[2]):
			StoreView.draw_icon(s, Vector2(x + 9, at.y), Store.GUARDIAN, 9, tone)
			x += 24.0
		var words := String(entry[0])
		var words_w := Look.text_width(words, size)
		Look.text_box(s, Rect2(x - 1, at.y - 16, words_w + 2, 32), words, size, tone, HORIZONTAL_ALIGNMENT_LEFT)
		x += words_w + gap

## The life crystal on the result line: whole and lit after a win, split in two after a
## defeat (Look.draw_crystal's broken stub is too dark to read at this size on a dark card).
func _draw_result_crystal(at: Vector2, r: float, won: bool) -> void:
	if won:
		s.draw_circle(at, r * 2.3, Color(Look.CRYSTAL, 0.13), true, -1, true)
		Look.draw_crystal(s, at, r, true, 0.0)
		return
	var edge := Look.WARN
	var face := Color("#4a2d38")
	var left := PackedVector2Array([at + Vector2(-0.10, -1.50) * r, at + Vector2(-0.86, -0.20) * r, at + Vector2(-0.50, 1.00) * r,
		at + Vector2(-0.08, 0.30) * r, at + Vector2(-0.36, -0.30) * r])
	var right := PackedVector2Array([at + Vector2(0.24, -1.20) * r, at + Vector2(0.98, 0.00) * r, at + Vector2(0.60, 1.18) * r,
		at + Vector2(0.20, 0.52) * r, at + Vector2(0.04, -0.34) * r])
	for shard in [left, right]:
		s.draw_colored_polygon(shard, face)
		s.draw_polyline(shard + PackedVector2Array([shard[0]]), edge, 1.3, true)
