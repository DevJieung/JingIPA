extends RefCounted
class_name ArenaTalentView

## The constellation views of ArenaScreen (2026-10-19 rebuild for the feedback F1/F2/F3):
##
## * The level-up popup, entering from the top: the shade, then the header (the rising
##   star, the title, the level, the experience) dropping in under the top strip, then the
##   three cards falling in one after another and settling, then the constellation column
##   in the command rail's place and the levels still waiting, and the gold pick buttons
##   last. Until the screen arms the popup a button is a dark bronze plate whose rim fills
##   with gold; armed, it is the gold button and flashes once. A following offer (another
##   level waiting) drops only the cards again.
## * The constellation map (Constellation.draw_chart): over the popup from its map button,
##   with a way back to the same offer, or as the viewer from the rail.
## * The pick: while the screen holds the battle after a pick, the chosen star flies into
##   its constellation on its card and the other cards sink (Constellation.draw_pick_flourish).
## * The joined-star banner on the field, in the same seal.
##
## Draws on the screen's canvas (`s`) from ArenaScreen._draw and registers its touch zones
## in `s.ui` as it goes; the screen owns the input, the clocks and the arming. From the
## screen (PLAN §4): talent_entrance_age(), talent_armed(), talent_arm_progress(),
## talent_map, map_focus, map_node, talent_pressed, pick_hold_age(), pick_hold_id,
## pick_hold_offer, _settled(), t, ui; from the HUD view: hud._banner_box(). They are read
## through the small helpers below so this view also draws before the screen has them.
## Zones: talent:pick:<id>, talent:map, talent:back, close, talent:group:<g> (a column row
## or the map), talent:group: (the map's overview), talent:node:<id>, modal:block.

var s: ArenaScreen
## Staged answers for the screen's popup state, used by the preview tools instead of the
## screen (keys: settled, entrance_age, armed, arm_progress, map, focus, node, pressed,
## hold_age, hold_id, hold_offer, followup). Empty in the game.
var preview: Dictionary = {}

## The faint stars behind the popup, and the star joined last: the run keeps the count,
## this view remembers what it has shown (the field shows a new star for a moment).
var _sky: Array = []
var _talents_seen: Dictionary = {}
var _pick_node := ""
var _pick_t0 := -100.0
var _pick_waiting := false
## The popup's own memory: which offer it drew last (a new offer while the popup stayed
## open is a following offer: only the cards replay), when the buttons first showed and
## from what arming they fill, and when the map opened.
var _offer_key := ""
var _followup := false
var _drawn_frame := -10
var _fill_from := 0.0
var _last_progress := -1.0
var _buttons_seen := false
var _map_seen := false
var _map_t0 := 0.0
var _map_frame := -10
## When the buttons armed (they flash once), and whether they were armed last picture.
var _armed_at := -100.0
var _was_armed := false

## Where the popup stands. It sits over the battle box (centre x 496) so no button lands on
## the command rail (the fifth hero card and the starburst button stay out of reach); the
## rail's column holds the constellation column instead.
const CENTER_X := 496.0
const CARD := Vector2(296, 470)
const CARD_Y := 196.0
const CARD_GAP := 20.0
const COLUMN := Rect2(998, 78, 274, 714)
const MAP_BUTTON := Rect2(806, 92, 160, 44)
const CHART := Rect2(16, 72, 1248, 718)
## The entrance, in seconds of ArenaScreen.talent_entrance_age() (first offer): the shade,
## the header from under the top strip, the cards one after another (each falls CARD_DROP
## px and settles), the column, the buttons last. ArenaScreen.TALENT_ARM_AT should end
## the buttons' fill: 0.90 s for a first offer, 0.45 s for a following one.
const SHADE_IN := 0.15
const HEAD_AT := 0.04
const HEAD_IN := 0.30
const CARD_AT := 0.18
const CARD_STEP := 0.08
const CARD_IN := 0.32
const CARD_DROP := 64.0
const COLUMN_AT := 0.36
const LEFT_AT := 0.62
const BUTTON_AT := 0.66
const BUTTON_IN := 0.14
## A following offer: the cards only, quicker.
const FOLLOW_CARD_STEP := 0.05
const FOLLOW_CARD_IN := 0.24
const FOLLOW_BUTTON_AT := 0.33
## The map fades in over this long.
const MAP_IN := 0.16

func _init(screen: ArenaScreen) -> void:
	s = screen

func _tr(key: String) -> String:
	return Arena.label("arena." + key)

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

func _back_out(x: float) -> float:
	var k := clampf(x, 0.0, 1.0)
	var c := 1.4
	return 1.0 + (c + 1.0) * pow(k - 1.0, 3.0) + c * pow(k - 1.0, 2.0)

# --------------------------------------------------------------------------- #
# The screen's popup state (PLAN §4), read so the view draws with or without it
# --------------------------------------------------------------------------- #
func _settled() -> bool:
	return bool(preview.get("settled", s._settled()))

func _entrance_age() -> float:
	if preview.has("entrance_age"): return float(preview["entrance_age"])
	if s.has_method("talent_entrance_age"): return float(s.call("talent_entrance_age"))
	if s.has_method("_talent_age"): return float(s.call("_talent_age", Arena.talent_offer))
	return 9.0

func _armed() -> bool:
	if _settled(): return true
	if preview.has("armed"): return bool(preview["armed"])
	if s.has_method("talent_armed"): return bool(s.call("talent_armed"))
	return true

func _arm_progress() -> float:
	if _armed(): return 1.0
	if preview.has("arm_progress"): return clampf(float(preview["arm_progress"]), 0.0, 1.0)
	if s.has_method("talent_arm_progress"): return clampf(float(s.call("talent_arm_progress")), 0.0, 1.0)
	return 1.0

func _screen_value(key: String, name: String, fallback: Variant) -> Variant:
	if preview.has(key): return preview[key]
	var value: Variant = s.get(name)
	return fallback if value == null else value

func _map_open() -> bool:
	return bool(_screen_value("map", "talent_map", false))

## How long the screen takes to arm this offer (ArenaScreen.TALENT_ARM_AT when it has one).
func _arm_time() -> float:
	var constants: Dictionary = {}
	var script: Script = s.get_script()
	while script != null:
		constants.merge(script.get_script_constant_map())
		script = script.get_base_script()
	if _followup: return float(constants.get("TALENT_REARM_AT", 0.45))
	return float(constants.get("TALENT_ARM_AT", 0.90))

func _hold_age() -> float:
	if preview.has("hold_age"): return float(preview["hold_age"])
	if s.has_method("pick_hold_age"): return float(s.call("pick_hold_age"))
	return -1.0

func _pressed_id() -> String:
	return String(_screen_value("pressed", "talent_pressed", ""))

# --------------------------------------------------------------------------- #
# The field banner
# --------------------------------------------------------------------------- #
## Notice a star joined since the last picture (the run keeps the count; the screen only
## remembers what it has shown). A new run starts the memory over. While the screen holds
## the battle for the pick, the banner waits for the hold to end.
func _watch_picks() -> void:
	_warm_glyphs()
	var now: Dictionary = Arena.talents
	var key := "%d" % Arena.run_seed
	if String(_talents_seen.get("_run", "")) != key:
		_talents_seen = now.duplicate()
		_talents_seen["_run"] = key
		return
	for id in now:
		if int(now[id]) > int(_talents_seen.get(id, 0)):
			_pick_node = String(id)
			_pick_t0 = s.t
			_pick_waiting = true
	for id in now: _talents_seen[id] = now[id]
	# The banner waits for its row: while a window is open, the pick's flourish holds or the HUD
	# shows a banner of its own (the wave just held comes first), its clock does not start, so it
	# keeps its whole time once the row is free.
	if _pick_waiting:
		if _banner_row_busy():
			_pick_t0 = s.t
		else:
			_pick_waiting = false

## Load the seal art and two node glyphs a picture from the battle's first frames on, so the
## first popup and the first map do not read seventy-odd pictures inside one frame.
var _warmed := 0
func _warm_glyphs() -> void:
	var nodes: Array = Balance.TALENTS
	if _warmed >= nodes.size(): return
	if _warmed == 0: Constellation.has_art()
	for k in range(2):
		if _warmed >= nodes.size(): return
		Constellation.icon_texture(String(nodes[_warmed]["id"]))
		_warmed += 1

func _banner_row_busy() -> bool:
	if not Arena.modal.is_empty() or _hold_age() >= 0.0: return true
	var sim = Arena.sim
	if sim == null: return false
	if sim.clear_t > 0.0 or (s._revive_age < ArenaScreen.REVIVE_BANNER and sim.revives > 0): return true
	if s.hud.has_method("_banner_age") and s.hud.has_method("_banner_life"):
		return float(s.hud.call("_banner_age")) < float(s.hud.call("_banner_life"))
	return false

## "별을 이었습니다 · 분노 / 날선 손끝": the joined star's seal on the banner row, landing like
## the other banners and fading at the end.
func _draw_pick_banner(sim) -> void:
	var node := Constellation.node_of(_pick_node)
	if node.is_empty(): return
	var age := s.t - _pick_t0
	var settled := _settled()
	if age < 0.0 and not settled: return
	var group := String(node.get("group", ""))
	var color := Constellation.group_color(group)
	var box := s.hud._banner_box(sim)
	var fade := clampf((ArenaScreen.PICK_BANNER - age) * 2.5, 0.0, 1.0) if not settled else 1.0
	var k := 1.0 if settled else _ease_out(age / 0.18)
	s.draw_set_transform(Vector2(0, -(1.0 - k) * 14.0), 0, Vector2.ONE)
	s.draw_rect(Rect2(box.position + Vector2(3, 5), box.size - Vector2(6, 0)), Color(0, 0, 0, 0.32 * fade))
	Look.glass_panel(s, box, color.lerp(Look.STEEL, 0.15), Look.GLASS_FACE, true, fade)
	Look.gradient_rect(s, Rect2(box.position + Vector2(4, 3), Vector2(box.size.x * 0.5, box.size.y - 6)), Color(color, 0.30 * fade), Color(color, 0.0), false)
	var times := Arena.talent_count(_pick_node)
	var pop := 1.0 if settled else clampf((age - 0.04) / 0.30, 0.0, 1.0)
	Constellation.draw_seal(s, box.position + Vector2(40, box.size.y * 0.5), 21.0, _pick_node,
		"full" if times >= int(node.get("max", 1)) else "joined", times, s.t, {"settled": settled, "pop": pop, "alpha": fade})
	var text_x := box.position.x + 80.0
	var text_w := box.size.x - 94.0
	Look.text_box(s, Rect2(text_x, box.position.y + 8, text_w, 22), _tr("talent_joined") + "  ·  " + Constellation.group_name(group), Look.TYPE_CAPTION, Color(color.lightened(0.35), fade), HORIZONTAL_ALIGNMENT_LEFT)
	var name := I18n.t(String(node.get("ko", _pick_node))) + (" x%d" % times if times > 1 else "")
	Look.text_box(s, Rect2(text_x, box.position.y + 30, text_w, 32), name, 24, Color(Look.INK, fade), HORIZONTAL_ALIGNMENT_LEFT)
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# --------------------------------------------------------------------------- #
# The popup
# --------------------------------------------------------------------------- #
## The talent modal: the pick in progress (the screen's hold), the map, the viewer, or the
## level-up popup.
func _draw_talent() -> void:
	if _hold_age() >= 0.0:
		_draw_pick_hold()
		return
	var offer: Array = Arena.talent_offer
	if _map_open() or offer.is_empty():
		_draw_map(offer)
		return
	_map_seen = false
	_draw_offer(offer)

## The pick as the screen holds it (also called by the screen while it holds the battle
## with no talent modal left open): the chosen star flies into its constellation.
func _draw_pick_hold() -> void:
	var age := _hold_age()
	if age < 0.0: return
	_drawn_frame = Engine.get_process_frames()
	var picked := String(_screen_value("hold_id", "pick_hold_id", ""))
	var offer: Array = _screen_value("hold_offer", "pick_hold_offer", [])
	var next_waits := Arena.modal == "talent" and not Arena.talent_offer.is_empty()
	# With no other level waiting, the popup leaves with the star: the shade lifts at the end.
	var out := 1.0 if next_waits else 1.0 - clampf((age - (Constellation.PICK_TIME - 0.14)) / 0.14, 0.0, 1.0)
	s.draw_rect(Look.SCREEN, Color(Look.SHADE, Look.SHADE.a * out))
	s.ui.zone(Look.SCREEN, "modal:block")
	_draw_night_sky(out)
	_draw_header(1.0, out)
	var before: Dictionary = Arena.talents.duplicate()
	if before.has(picked):
		before[picked] = maxi(0, int(before[picked]) - 1)
	var node_states := Constellation.states(before, Arena.owned_passives, Arena.levels)
	var rects: Array = []
	for n in range(offer.size()):
		rects.append(_card_rect(n, offer.size()))
	Constellation.draw_pick_flourish(s, rects, offer, picked, before, node_states, age, s.t)
	Constellation.draw_column(s, s.ui, COLUMN, before, node_states, [], s.t, false, {"settled": true, "alpha": out})

## The level-up popup itself.
func _draw_offer(offer: Array) -> void:
	var key := ",".join(PackedStringArray(offer))
	var frame := Engine.get_process_frames()
	var fresh := frame - _drawn_frame > 2
	if key != _offer_key or fresh:
		# A new offer while the popup stayed up (another level waiting, after the pick's
		# hold) is a following offer: only the cards replay.
		_followup = not fresh and not _offer_key.is_empty()
		_offer_key = key
		_buttons_seen = false
		_last_progress = -1.0
		_was_armed = false
	_drawn_frame = frame
	# The screen knows best whether this offer follows a pick (ArenaScreen.talent_followup).
	var told: Variant = _screen_value("followup", "talent_followup", null)
	if told != null: _followup = bool(told)
	var settled := _settled()
	var age := 9.0 if settled else _entrance_age()
	var taken: Dictionary = Arena.talents
	var node_states := Constellation.states(taken, Arena.owned_passives, Arena.levels)
	var shade := 1.0 if settled or _followup else _ease_out(age / SHADE_IN)
	s.draw_rect(Look.SCREEN, Color(Look.SHADE, Look.SHADE.a * shade))
	s.ui.zone(Look.SCREEN, "modal:block")
	_draw_night_sky(shade)
	var head := 1.0 if settled or _followup else _ease_out((age - HEAD_AT) / HEAD_IN)
	_draw_header(head, 1.0)
	var armed := _armed()
	# The map button rides with the header; it answers once the popup is armed.
	_draw_map_button(head, armed)
	# The cards, one after another from above.
	var count := offer.size()
	var step := FOLLOW_CARD_STEP if _followup else CARD_STEP
	var span := FOLLOW_CARD_IN if _followup else CARD_IN
	var first := 0.0 if _followup else CARD_AT
	for n in range(count):
		var id := String(offer[n])
		var start := first + float(n) * step
		var k := 1.0 if settled else clampf((age - start) / span, 0.0, 1.0)
		if k <= 0.0:
			s.ui.zone(Rect2(), "talent:pick:" + id, false)
			continue
		var home := _card_rect(n, count)
		var rect := Rect2(home.position - Vector2(0, (1.0 - _back_out(k)) * CARD_DROP), home.size)
		Constellation.draw_offer_card(s, rect, id, taken, node_states, s.t,
			{"settled": settled, "age": age - start, "alpha": clampf(k * 2.2, 0.0, 1.0)})
	# The column of constellations, then the levels still waiting.
	Constellation.draw_column(s, s.ui, COLUMN, taken, node_states, offer, s.t, armed,
		{"settled": settled or _followup, "age": age, "at": COLUMN_AT})
	_draw_levels_left(1.0 if settled or _followup else _ease_out((age - LEFT_AT) / 0.20))
	# The buttons come last and show the arming on their rims.
	var appear_at := FOLLOW_BUTTON_AT if _followup else BUTTON_AT
	var appear := 1.0 if settled else clampf((age - appear_at) / BUTTON_IN, 0.0, 1.0)
	var progress := _arm_progress()
	if not _buttons_seen:
		# The rim starts filling when the buttons appear: the arming the screen will have
		# reached by then (its clock and this entrance start together).
		_buttons_seen = true
		_fill_from = clampf(appear_at / _arm_time(), 0.0, 0.95)
	if _last_progress >= 0.0 and progress < _last_progress - 0.02:
		# The screen armed again (back from the map): the rim fills again from here.
		_fill_from = progress
	_last_progress = progress
	var fill := 1.0 if armed else clampf((progress - _fill_from) / maxf(0.001, 1.0 - _fill_from), 0.0, 1.0)
	if armed and not _was_armed:
		_armed_at = s.t
	_was_armed = armed
	var armed_age := 9.0 if settled else s.t - _armed_at
	var pressed := _pressed_id()
	for n in range(count):
		var id := String(offer[n])
		var rect := _card_rect(n, count)
		var started := settled or age >= first + float(n) * step
		if not started:
			continue
		Constellation.draw_pick_button(s, s.ui, Rect2(rect.position.x + 20, rect.end.y - 66, rect.size.x - 40, 52), id,
			_tr("pick"), fill, armed, s.t, {"appear": appear, "armed_age": armed_age,
				"pressed": pressed == "talent:pick:" + id or pressed == id})

## The header: the rising star, the title and the level, the hint, the experience bar. It
## drops in from just under the top strip (the menu buttons hold y < 70).
func _draw_header(k: float, alpha: float) -> void:
	if k <= 0.0 or alpha <= 0.0: return
	var a := k * alpha
	# A night band under the header covers the field banners' row beneath the shade.
	var night := Color(0.012, 0.026, 0.045)
	s.draw_rect(Rect2(0, 70, ArenaScreen.BATTLEFIELD.end.x, 84), Color(night, 0.86 * a))
	Look.gradient_rect(s, Rect2(0, 154, ArenaScreen.BATTLEFIELD.end.x, 44), Color(night, 0.86 * a), Color(night, 0.0), true)
	var title := _tr("levelup")
	var level := _tr("level_n") % Arena.level
	var title_w := Look.text_width(title, Look.TYPE_TITLE)
	var chip_w := Look.text_width(level, 17) + 20.0
	var row_w := 30.0 + 14.0 + title_w + 16.0 + chip_w
	var x := CENTER_X - row_w * 0.5
	var drop := (1.0 - k) * 22.0
	var row_y := 108.0 - drop
	var star := Vector2(x + 15.0, row_y - (1.0 - k) * 18.0)
	Constellation.draw_emblem_row_star(s, star, 13.0 * (0.6 + 0.4 * k), s.t, _settled())
	Look.text_left(s, Vector2(x + 44.0, row_y), title, Look.TYPE_TITLE, Color(Look.GOLD, a))
	Look.chip(s, Vector2(x + 44.0 + title_w + 16.0, row_y), level, 17, Color(Look.STARLIGHT, a), Color(Look.BG_DEEP, a))
	Look.text_box(s, Rect2(CENTER_X - 400, 140 - drop * 0.8, 800, 28), _tr("talent_hint"), Look.TYPE_BODY, Color(Look.INK_DIM, a))
	var xp_words := "%s  %d / %d" % [_tr("xp"), floori(Arena.xp), Arena.xp_needed()]
	var words_w := Look.text_width(xp_words, 14)
	var xp_w := words_w + 12.0 + 200.0
	_draw_xp_bar(Rect2(CENTER_X - xp_w * 0.5 + words_w + 12.0, 172 - drop * 0.6, 200, 6), Color(Look.INK_DIM, a), a)

## The map button at the header's right: three joined stars and the word.
func _draw_map_button(k: float, armed: bool) -> void:
	if k <= 0.0:
		s.ui.zone(MAP_BUTTON, "talent:map", false)
		return
	var rect := Rect2(MAP_BUTTON.position - Vector2(0, (1.0 - k) * 18.0), MAP_BUTTON.size)
	var down := armed and _pressed_id() == "talent:map"
	Look.glass_panel(s, rect, Look.STARLIGHT.lerp(Look.STEEL, 0.35), Color(0.05, 0.09, 0.13, (0.92 if down else 0.82) * k), true, k)
	var stars := [Vector2(20, 28), Vector2(32, 15), Vector2(46, 24)]
	for n in range(stars.size() - 1):
		s.draw_line(rect.position + stars[n], rect.position + stars[n + 1], Color(Look.STARLIGHT, 0.7 * k), 1.6, true)
	for p in stars:
		s.draw_colored_polygon(Look.star_points(rect.position + p, 5.5, 0.46), Color(Look.STARLIGHT, k))
	Look.text_box(s, Rect2(rect.position + Vector2(58, 4), rect.size - Vector2(66, 8)), _tr("map_button"), 21, Color(Look.INK, k), HORIZONTAL_ALIGNMENT_LEFT)
	s.ui.zone(MAP_BUTTON, "talent:map", armed and k >= 1.0)

## Levels still waiting: words and one starlight pip each (nothing that hurries the player).
func _draw_levels_left(k: float) -> void:
	if Arena.pending_levels <= 1 or k <= 0.0: return
	var words := _tr("levels_left") % (Arena.pending_levels - 1)
	var pips := float(Arena.pending_levels - 1) * 16.0
	var words_w := Look.text_width(words, 18)
	var left := CENTER_X - (words_w + 12.0 + pips) * 0.5
	var y := CARD_Y + CARD.y + 30.0
	Look.text_left(s, Vector2(left, y), words, 18, Color(Look.CRYSTAL, k))
	for n in range(Arena.pending_levels - 1):
		s.draw_colored_polygon(Look.star_points(Vector2(left + words_w + 12.0 + 8.0 + n * 16.0, y), 6.0, 0.46), Color(Look.STARLIGHT, k))

func _card_rect(n: int, count: int) -> Rect2:
	var x0 := CENTER_X - (CARD.x * count + CARD_GAP * (count - 1)) * 0.5
	return Rect2(x0 + n * (CARD.x + CARD_GAP), CARD_Y, CARD.x, CARD.y)

## The map: from the popup's map button (the offer ringed, a way back to it) or as the
## viewer (no offer, back to battle). A night almost opaque lies under it, so the battle
## and the command rail do not show through the chart.
func _draw_map(offer: Array) -> void:
	var settled := _settled()
	var frame := Engine.get_process_frames()
	if not _map_seen or frame - _map_frame > 2:
		_map_seen = true
		_map_t0 = s.t
	_map_frame = frame
	if not offer.is_empty():
		# The offer waits under the map: coming back is not a new popup (its buttons arm again).
		_drawn_frame = frame
	var k := 1.0 if settled else _ease_out((s.t - _map_t0) / MAP_IN)
	s.draw_rect(Look.SCREEN, Color(Look.SHADE, Look.SHADE.a))
	s.draw_rect(Look.SCREEN, Color(0.012, 0.026, 0.045, 0.86 * k))
	s.ui.zone(Look.SCREEN, "modal:block")
	_draw_night_sky(1.0)
	var taken: Dictionary = Arena.talents
	var node_states := Constellation.states(taken, Arena.owned_passives, Arena.levels)
	var focus := String(_screen_value("focus", "map_focus", ""))
	var selected := String(_screen_value("node", "map_node", ""))
	Constellation.draw_chart(s, s.ui, CHART, taken, node_states, offer, focus, selected, s.t,
		{"settled": settled, "level": Arena.level})
	var button := Constellation.chart_button_rect(CHART)
	if offer.is_empty():
		s.ui.button(s, button, _tr("resume"), "close", true, Look.GOLD, Look.TYPE_BUTTON_2)
	else:
		s.ui.button(s, button, _tr("map_back"), "talent:back", true, Look.GOLD, Look.TYPE_BUTTON_2)

## A few faint stars over the shade: the night the constellations hang in.
func _draw_night_sky(alpha: float) -> void:
	if alpha <= 0.0: return
	if _sky.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261017
		for n in range(48):
			_sky.append(Vector3(rng.randf_range(20, 1260), rng.randf_range(80, 790), rng.randf_range(0.8, 2.0)))
	for star in _sky:
		Constellation.draw_dot(s, Vector2(star.x, star.y), star.z * 2.2, Color(Look.STARLIGHT, 0.30 * alpha))

## Experience toward the next level: a starlight bar with the numbers beside it.
func _draw_xp_bar(bar: Rect2, ink: Color, alpha: float = 1.0) -> void:
	var needed := maxf(1.0, float(Arena.xp_needed()))
	var fraction := clampf(Arena.xp / needed, 0.0, 1.0)
	var words := "%s  %d / %d" % [_tr("xp"), floori(Arena.xp), int(needed)]
	Look.text_right(s, Vector2(bar.position.x - 12.0, bar.get_center().y), words, 14, ink)
	s.draw_rect(bar, Color(0.19, 0.26, 0.29, 0.9 * alpha))
	if fraction > 0.0: s.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), Color(Look.STARLIGHT, alpha))
