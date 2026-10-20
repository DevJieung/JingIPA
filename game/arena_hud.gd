extends RefCounted
class_name ArenaHud

## The battle HUD of ArenaScreen: the top strip (crystal, the stage and its waves, the wave
## cell, growth, speed), the ward and boss strips under it, the command rail (jewel box /
## constellations / reserve, the six guardian cards, the three common skills), the minimap, the
## monsters' health bars, the movement stick, the short field banners (a wave begins, a wave is
## held, an elite steps in, the stage boss falls, a revival ticket and its 5-star hero; the
## joined-star banner is ArenaTalentView's) and the starfall's aim hint, plus the small shapes
## the other views borrow (diamond, coin, bar, modal shade, stage label).
##
## 2026-10-19 feedback (D6, build/feedback-2026-10-19/D6/RECORD.md): skills read as ready at a
## glance and pop when they become ready (O2), they cost gold (F5), the starfall is aimed on the
## field (F6), the empty guardian slot is a neutral socket (B3), the stage runs as waves with a
## preparation between them (O4 · O5), stages are a ladder (O10), a revival brings a 5-star hero
## instead of gold (D2).
##
## Draws on the screen's own canvas (`s`) from ArenaScreen._draw, in the order the screen
## calls it, and registers its touch zones in the screen's `ui` as it goes, so the drawing
## order and the zone order (a later zone wins) are the screen's. Input, the run's clocks
## (_card_age, _result_age, _talent_age, _settled) and the pages and choices that buttons
## change stay on the screen.
##
## Uses from the screen: s.joy_origin, s._joy_pointer, s.joystick, s._menu_open(),
## s._result_age(), s._revive_age, s._settled(), s.speed, s.t, s.ui, s.view_3d, and when the
## screen has them (LB1) s.aiming(), s.aim_valid(), s.aim_pixel and s.skill_ready_age(id) —
## without skill_ready_age the HUD keeps its own memory of when a skill became ready.
## Zones: summon, talents, bench, hero:<i>, hero:empty (never on), skill:<id> (on while the
## skill is ready, and the armed starfall's button to cancel it), speed:<n>, wave:start (the
## wave cell during a preparation), aim:cancel.
## Uses from the other views: s.cards._draw_gate_dart(),
## s.talent_view._draw_pick_banner(), s.talent_view._pick_node,
## s.talent_view._pick_t0, s.talent_view._watch_picks().

## The HUD's own tones: the three common skills, the minimap's actors, the bars' wells and
## Hellbound's ember. Everything else is a Look token.
const SKILL_TINT := {"blast": Look.GOLD, "freeze": Color("#aeeaff"), "ward": Color("#6ce8fa")}
const SKILLS := ["blast", "freeze", "ward"]
const MAP_ALLY := Color("#91cfda")
const MAP_BOSS := Color("#ffad68")
const BAR_WELL := Color("#08141b")
const BAR_TRACK := Color("#30434a")
const HELL := Color("#ff8f5e")
## The top strip's wave cell, where the boss clock was until the stage became waves.
const WAVE_CELL := Rect2(518, 4, 120, 62)
## The command rail: the jewel box's button and the three skills, one row each.
const BOX_BUTTON := Rect2(1148, 84, 118, 40)
const SKILL_ORIGIN := Vector2(1006, 615)
const SKILL_SIZE := Vector2(260, 54)
const SKILL_PITCH := 61.0
## A ready skill (O2) breathes slowly at its rim, each button a third of a breath behind the one
## above so the three never pulse together, and one button at a time a shimmer crosses it. The
## moment it becomes ready it pops once: a ring leaves the medallion, the glyph flashes and
## lands, a light runs over the button.
const READY_BREATH := 2.6
const READY_SWEEP_EVERY := 7.2
const READY_SWEEP := 0.7
const READY_POP := 0.65
## Seconds a field banner stays: a wave begins, a wave is held, an elite steps in.
const WAVE_BANNER := 1.7
const HELD_BANNER := 2.2
const ELITE_BANNER := 2.0
## The revival banner is taller than the others: it also carries the 5-star hero who joined.
const REVIVE_SIZE := Vector2(452, 106)
## The starfall's aim hint: a pill under the top strip.
const AIM_HINT_H := 44.0
## The jewel box on the rail is D1's own render of the box (art/ui/box), shown small.
const BOX_ICON_PATH := "res://art/ui/box/tier4/closed.png"

var s: ArenaScreen

## Drawing-side memory: the upper-body crop of each guardian card's portrait, and each
## boss's measured top (cached 0.5 s).
var _card_crops: Dictionary = {}
var _boss_tops: Dictionary = {}

## When each skill became ready, for a screen without skill_ready_age: ready in the last
## picture, and the screen time it turned ready.
var _ready_seen: Dictionary = {}
var _ready_t0: Dictionary = {}

## The waves as the last picture saw them, so a change of phase shows its banner. The banners
## run on their own clock, which stands still while a window covers the field: a wave held under
## a level-up popup still says so when the popup closes.
var _wave_key := ""
var _wave_seen := 0
var _prep_seen := true
var _hp_seen := -1.0
var _elites_seen: Dictionary = {}
var _bclock := 0.0
var _clock_t := -1.0
## The field banner of the waves now up: {kind: "wave" | "held" | "elite", t0 (on _bclock), and
## what it shows}. The newest event takes the row; the one it replaces simply ends.
var _banner: Dictionary = {}
## Where the banner of this picture stands (empty when none): the aim hint keeps below it.
var _banner_rect := Rect2()
## The screen time aiming began (the hint's entrance).
var _aim_t0 := -100.0
var _aiming_seen := false
## Hellbound's best wave as it stood before the result (Save.record_hell raises the record before
## the result card is drawn): ArenaCards tells a new record from an old one with it.
var hell_best_before := 0

static var _box_icon: Dictionary = {}

func _init(screen: ArenaScreen) -> void:
	s = screen

func _tr(key: String) -> String:
	return Arena.label("arena." + key)

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

## "STAGE %d" / "WAVE %d" around its number: [the words before, the words after]. The number is
## set larger between them (the two languages may put it on either side).
static func _split(template: String) -> Array:
	if not template.contains("%d"):
		return [template + " ", ""]
	return [template.get_slice("%d", 0), template.get_slice("%d", 1)]

func _draw_topbar(theme: Dictionary) -> void:
	s.draw_rect(Rect2(0, 0, 1280, 69), Color(0.025, 0.065, 0.095, 0.88))
	s.draw_line(Vector2(0, 69), Vector2(1280, 69), Look.STEEL, 1, true)
	s.draw_line(Vector2(0, 71), Vector2(1280, 71), Color(0.02, 0.04, 0.07, 0.55), 2)
	_draw_hud_crystal(Vector2(43, 34))
	# Left to right: crystal block, the stage and its waves, the wave cell, gold, battle speed,
	# then the shared menu / language buttons that MenuOverlay draws from x 958.
	Look.text_box(s, Rect2(76, 8, 200, 30), _tr("title"), 25, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	for x in [337, 515, 641, 775]:
		s.draw_line(Vector2(x, 16), Vector2(x, 54), Color(Look.STEEL, 0.45), 1, true)
		_draw_diamond(Vector2(x, 35), 3.5, Color(Look.STEEL, 0.75))
	_draw_stage_cell(Rect2(346, 4, 160, 62), theme)
	_draw_speed()
	if Arena.sim == null: return
	var sim = Arena.sim
	_draw_blessing(Vector2(301, 23), sim)
	var fraction := clampf(sim.crystal_hp / maxf(1.0, sim.crystal_max), 0, 1)
	_bar(Rect2(79, 49, 152, 9), fraction, Look.CRYSTAL)
	Look.text_box(s, Rect2(236, 40, 94, 23), "%d / %d" % [ceili(sim.crystal_hp), int(sim.crystal_max)], 16, Look.INK)
	_draw_wave_cell(WAVE_CELL, sim)
	_draw_growth_cell(Rect2(650, 4, 118, 62))
	_draw_shield_panel(sim)
	_draw_boss_panel(sim)

## Growth cell of the top strip: what kills bring. Gold on the first row (it pays for jewel
## boxes and the common skills), the level and the experience toward the next star on the
## second and third (they buy constellation nodes). The bar is starlight: not the coin's gold,
## not the crystal's blue.
func _draw_growth_cell(cell: Rect2) -> void:
	_draw_coin(Vector2(cell.position.x + 14, cell.position.y + 17), 9)
	Look.text_box(s, Rect2(cell.position.x + 29, cell.position.y + 5, cell.size.x - 33, 25), "%d G" % Arena.gold, 20, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	var needed := maxf(1.0, float(Arena.xp_needed()))
	var fraction := clampf(Arena.xp / needed, 0.0, 1.0)
	var full := Arena.pending_levels > 0 or fraction >= 1.0
	var level_label: String = _tr("level_n") % Arena.level
	Look.text_box(s, Rect2(cell.position.x + 5, cell.position.y + 31, 64, 18), level_label, 14, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	# The experience count is the smallest text of the HUD: 13 px (10 physical on a
	# 1000x625 phone) in a 20 px box — RefugeSans needs 18.8 px at 13 — starting right
	# after the level label, so it is never fitted under the 12 px readability floor.
	var xp_left := cell.position.x + 5.0 + ceilf(Look.text_width(level_label, 14)) + 6.0
	# Experience never reads negative (a harness parks it at -1e9 to hold level-ups off).
	Look.text_box(s, Rect2(xp_left, cell.position.y + 30, cell.end.x - 6.0 - xp_left, 20), "%d / %d" % [maxi(0, floori(Arena.xp)), int(needed)], 13, Look.INK_MUTE, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar := Rect2(cell.position.x + 6, cell.position.y + 51, cell.size.x - 12, 5)
	Look.fill_round(s, bar.grow(1.5), 2, BAR_WELL)
	Look.fill_round(s, bar, 2, BAR_TRACK)
	var glow := 1.0 if s._settled() else 0.5 + 0.5 * sin(s.t * 4.0)
	var lit := Look.STARLIGHT if not full else Look.STARLIGHT.lerp(Color.WHITE, glow)
	if fraction > 0.0: Look.fill_round(s, Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), 2, lit)

## The boss strip's word: the boss of every stage comes with its tenth wave; every tenth stage
## it is a chapter boss.
func _boss_label(sim) -> String:
	if sim != null and sim.has_method("chapter_boss") and sim.chapter_boss():
		return _tr("chapter_boss")
	return _tr("boss_wave")

## "STAGE 3": the stage's name everywhere on this screen (M12 — the same capitals in Korean).
func _stage_label(number: int) -> String:
	return _tr("stage_label") % number

## Stage cell of the top strip: the stage (or Hellbound's tag), its ten waves with the elite
## and the boss marked, the field's name.
func _draw_stage_cell(cell: Rect2, theme: Dictionary) -> void:
	var sim = Arena.sim
	var hell: bool = Arena.hell
	var won: bool = sim != null and sim.won
	var clearing: bool = sim != null and sim.clear_t > 0.0
	# A chapter's last stage is written in the warning colour until its boss falls.
	var chapter := not hell and Arena.stage % Arena.CHAPTER == 0
	var label := _tr("hell_tag") if hell else _stage_label(Arena.stage)
	var tone := HELL if hell else (Look.WARN if chapter and not won and not clearing else Look.GOLD)
	Look.text_box(s, Rect2(cell.position.x + 6, cell.position.y - 2, cell.size.x - 12, 30), label, 20, tone)
	_draw_waves_track(Rect2(cell.position.x + 11, cell.position.y + 27, cell.size.x - 22, 5), sim, s._settled())
	Look.text_box(s, Rect2(cell.position.x, cell.position.y + 34, cell.size.x, 28), String(theme.get("ko", "")), 19, Look.INK)

## The stage's ten waves on a track (Hellbound: the block of ten it is in): held ones gold, the
## one fought or prepared for lit, the elite step taller, the boss step pointed.
func _draw_waves_track(rect: Rect2, sim, settled: bool, alpha: float = 1.0, glint: float = -1.0) -> void:
	var total := Balance.ARENA_WAVES
	var endless: bool = sim != null and sim.waves_total() == 0
	var wave: int = int(sim.wave_no) if sim != null else 1
	var first := 1
	if endless:
		first = (wave - 1) / total * total + 1
	var held := wave - first
	if sim != null and not endless and (sim.won or sim.clear_t > 0.0):
		held = total
	var glow := 0.0 if settled else 0.5 + 0.5 * sin(s.t * 3.2)
	Look.draw_wave_track(s, rect, wave - first + 1, total, held, Look.wave_marks(first, total, endless), glow, false, alpha, glint)

## The wave cell: "WAVE 3 / 10" (Hellbound: "WAVE 23" and the endless mark), then the phase —
## a preparation is the 「바로 시작」 button with its countdown (the whole cell is the button),
## a wave is how many of its monsters are still to fall.
func _draw_wave_cell(cell: Rect2, sim) -> void:
	var total: int = sim.waves_total()
	var wave: int = sim.wave_no
	var endless := total == 0
	var tone := Look.INK
	if sim.is_boss_wave(wave): tone = Look.WARN
	elif sim.is_elite_wave(wave): tone = Look.ELITE_INK
	var parts := _split(_tr("wave_label"))
	var lead: String = parts[0]
	var tail: String = parts[1]
	var number := str(wave)
	var count := "" if endless else " / %d" % total
	var lead_w := Look.text_width(lead, 13)
	var number_w := Look.text_width(number, 22)
	var tail_w := Look.text_width(tail, 13)
	var count_w := 19.0 if endless else Look.text_width(count, 14)
	var x := cell.get_center().x - (lead_w + number_w + tail_w + count_w) * 0.5
	var y := cell.position.y + 15.0
	Look.text_left(s, Vector2(x, y + 3), lead, 13, Look.INK_DIM)
	Look.text_left(s, Vector2(x + lead_w, y), number, 22, tone)
	if not tail.is_empty(): Look.text_left(s, Vector2(x + lead_w + number_w, y + 3), tail, 13, Look.INK_DIM)
	if endless:
		Look.draw_infinity(s, Vector2(x + lead_w + number_w + tail_w + 11.0, y + 2), 6.5, Look.INK_DIM, 1.7)
	else:
		Look.text_left(s, Vector2(x + lead_w + number_w + tail_w, y + 3), count, 14, Look.INK_DIM)
	var row := Rect2(cell.position.x + 5, cell.position.y + 31, cell.size.x - 10, 27)
	if sim.clear_t > 0.0 or sim.won:
		Look.draw_check(s, row.get_center(), 15, Look.GOLD, 2.6)
	elif sim.in_prep():
		_draw_start_button(cell, row, sim)
	else:
		_draw_wave_left(row, sim)

## 「바로 시작」 during a preparation: a gold pill (warm red once the boss is announced) with the
## countdown in a dark disc at its end, a ring round the seconds draining as they run. The touch
## zone is the whole cell, the strip's full height like the speed chips.
func _draw_start_button(cell: Rect2, pill: Rect2, sim) -> void:
	var on: bool = Arena.modal.is_empty() and not sim.done and sim.clear_t <= 0.0
	s.ui.zone(cell, "wave:start", on)
	var down := on and s.ui.pressed == "wave:start"
	var warned: bool = sim.boss_warned and not sim.boss_spawned
	var base := Look.WARN if warned else Look.GOLD
	var face := base if on else base.darkened(0.55)
	if down: face = face.darkened(0.16)
	var r := Rect2(pill.position + Vector2(0, 1.5 if down else 0.0), pill.size)
	if on and not s._settled():
		var breath := 0.5 + 0.5 * sin(s.t * TAU / 2.2)
		_rim(r.grow(2.0), Color(base, 0.10 + 0.16 * breath), 2.0, 7.0)
	Look.fill_round(s, Rect2(r.position + Vector2(0, 2), r.size), 6, Look.GOLD_DEEP if on else Look.BG_DEEP)
	Look.fill_round(s, r, 6, face)
	if on and not down:
		s.draw_line(r.position + Vector2(7, 2.5), Vector2(r.end.x - 7, r.position.y + 2.5), face.lightened(0.28), 1)
	var left := maxf(0.0, float(sim.prep_left()))
	var fraction := clampf(left / maxf(0.001, float(sim.prep_total())), 0.0, 1.0)
	var disc := Vector2(r.end.x - 13.0, r.get_center().y)
	s.draw_circle(disc, 11.0, Look.BG_DEEP, true, -1, true)
	s.draw_arc(disc, 9.0, 0, TAU, 28, Color(base, 0.22), 2.0, true)
	if fraction > 0.0: s.draw_arc(disc, 9.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 28, Look.IVORY if on else Look.INK_MUTE, 2.0, true)
	Look.text_center(s, disc + Vector2(0, 0.5), str(ceili(left - 0.0001)), 13, Look.IVORY if on else Look.INK_MUTE)
	var ink := Look.BG_DEEP if on else Look.INK_MUTE
	var words := Rect2(r.position.x + 17, r.position.y + 1, r.size.x - 17 - 27, r.size.y - 2)
	var tip := Vector2(r.position.x + 10, r.get_center().y)
	s.draw_colored_polygon(PackedVector2Array([tip + Vector2(-3.5, -5), tip + Vector2(4.5, 0), tip + Vector2(-3.5, 5)]), ink)
	Look.text_box(s, words, _tr("wave_start"), 15, ink)

## During a wave: how many of its monsters are still to fall, out of the wave — three coral
## dots (the minimap's monsters) and a bar that empties as they fall.
func _draw_wave_left(row: Rect2, sim) -> void:
	var size := maxi(1, int(sim.wave_size()))
	var left := clampi(int(sim.wave_left()), 0, size)
	var number := str(left)
	var of := " / %d" % size
	var number_w := Look.text_width(number, 19)
	var of_w := Look.text_width(of, 13)
	var x := row.get_center().x - (17.0 + number_w + of_w) * 0.5
	var y := row.position.y + 10.0
	_draw_crowd(Vector2(x + 6, y + 1), 3.0, Look.GATE_MARK)
	Look.text_left(s, Vector2(x + 17, y), number, 19, Look.INK)
	Look.text_left(s, Vector2(x + 17 + number_w, y + 2), of, 13, Look.INK_DIM)
	var bar := Rect2(row.position.x + 8, row.end.y - 4, row.size.x - 16, 3)
	s.draw_rect(bar.grow(1), BAR_WELL)
	s.draw_rect(bar, BAR_TRACK)
	if left > 0: s.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(left) / float(size), bar.size.y)), Look.GATE_MARK)

## Three dots in a huddle: the monsters of a wave.
func _draw_crowd(c: Vector2, r: float, color: Color) -> void:
	for at in [c + Vector2(-r * 1.25, r * 0.55), c + Vector2(r * 1.25, r * 0.55), c + Vector2(0, -r * 0.75)]:
		s.draw_circle(at, r + 1.0, Color(Look.BG_DEEP, 0.85), true, -1, true)
		s.draw_circle(at, r, color, true, -1, true)

## Revival tickets in the crystal block (the DLC): the product's own crest and, beside it, the
## number of revivals left in this stage (Arena.revives_left()). It reads like the gold counter
## next to its coin, and the number does not depend on colour.
##   ready    lit gold, breathing slowly, the number in gold
##   active   crystal blue inside a ring that drains: the reformed crystal cannot be hurt.
##            This wins over "ready": tickets may still be in hand while it runs.
##   spent    a hollow steel outline and a steel 0: the next break ends the stage
## Each revival lets the number land from a little larger, so the change is seen.
## Nothing is drawn for a run without the DLC. The crest follows the rule itself
## (Arena.revive_ready / sim.revives), so it also shows on a build without a shop, where
## every product counts as owned and the crystal does revive.
func _draw_blessing(at: Vector2, sim) -> void:
	if not (Arena.revive_ready() or sim.revives > 0): return
	var left := Arena.revives_left()
	var radius := 11.5
	var ink := Look.GOLD
	if sim.invuln_t > 0.0:
		var guard := clampf(sim.invuln_t / maxf(0.001, Balance.ARENA_REVIVE_INVULN), 0.0, 1.0)
		StoreView.draw_icon(s, at, Store.GUARDIAN, radius - 2.5, Look.CRYSTAL)
		s.draw_arc(at, radius + 1.5, 0, TAU, 32, Color(Look.CRYSTAL, 0.20), 2.6, true)
		s.draw_arc(at, radius + 1.5, -PI / 2, -PI / 2 + TAU * guard, 32, Look.CRYSTAL_INK, 2.6, true)
		ink = Look.CRYSTAL_INK
	elif left > 0:
		var breath := 0.5 if s._settled() else 0.5 + 0.5 * sin(s.t * 2.4)
		s.draw_circle(at, radius + 3.5, Color(Look.GOLD, 0.10 + 0.10 * breath), true, -1, true)
		StoreView.draw_icon(s, at, Store.GUARDIAN, radius, Look.GOLD)
	else:
		var steel := Look.STEEL_DIM
		s.draw_circle(at, radius, Color(0.02, 0.05, 0.08, 0.55), true, -1, true)
		s.draw_arc(at, radius, 0, TAU, 32, Color(steel, 0.85), 1.3, true)
		var top := at + Vector2(0, -radius * 0.60)
		var bottom := at + Vector2(0, radius * 0.60)
		var left_p := at + Vector2(-radius * 0.34, -radius * 0.04)
		var right_p := at + Vector2(radius * 0.34, -radius * 0.04)
		s.draw_polyline(PackedVector2Array([top, right_p, bottom, left_p, top]), steel, 1.3, true)
		ink = Look.INK_MUTE
	# The number, right of the crest.
	var number := str(left)
	var number_at := Vector2(at.x + radius + 5.5, at.y)
	var land := 1.0 if s._settled() else 1.0 + 0.55 * (1.0 - _ease_out(s._revive_age / 0.40))
	if land > 1.001:
		var number_mid := number_at + Vector2(Look.text_width(number, 18) * 0.5, 0)
		s.draw_set_transform(number_mid * (1.0 - land), 0, Vector2(land, land))
		Look.text_left(s, number_at, number, 18, Color.WHITE.lerp(ink, _ease_out(s._revive_age / 0.40)))
		s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		Look.text_left(s, number_at, number, 18, ink)

## The boss strip (warning banner or health bar) holds the first row under the top bar.
func _boss_strip_shown(sim) -> bool:
	if not sim.boss_spawned: return sim.boss_warned
	for mo in sim.monsters:
		if String(mo.get("kind", "")) == "boss": return true
	return false

func _banner_box(sim) -> Rect2:
	var top := ArenaScreen.BOSS_BOX.end.y + 8.0 if _boss_strip_shown(sim) else ArenaScreen.BOSS_BOX.position.y
	return Rect2(ArenaScreen.BATTLEFIELD.get_center().x - ArenaScreen.BANNER_SIZE.x * 0.5, top, ArenaScreen.BANNER_SIZE.x, ArenaScreen.BANNER_SIZE.y)

## Short field banners, one at a time: the stage boss falling, then a revival, then the newest
## of the waves' moments (a wave begins, a wave is held, an elite steps in — a newer one takes
## the row), then the star just joined — and the starfall's aim hint under whichever is up.
func _draw_banners() -> void:
	var sim = Arena.sim
	_banner_rect = Rect2()
	if Arena.modal != "result": hell_best_before = Save.hell_best_wave
	if sim == null: return
	_watch_waves(sim)
	# The battlefield card's name plate takes this row while it is up.
	if Arena.modal == "stage": return
	if Arena.modal == "result":
		# Nothing of a banner is left under the result panel. The stage boss's banner hands
		# over to the victory panel: it fades while the panel's shade comes in over it.
		var out := 1.0 - s._result_age() / ArenaScreen.RESULT_BANNER_OUT
		if sim.won and out > 0.0: _draw_final_banner(sim, out)
		return
	s.talent_view._watch_picks()
	# A window over the field (the box, the level-up popup, the map, the reserve) hides the field's
	# banners: their clock waits (_bclock) and they carry on when it closes — nothing shows
	# through the window's head.
	if not Arena.modal.is_empty(): return
	if sim.clear_t > 0.0 and sim.final_stage():
		_draw_final_banner(sim)
	elif s._revive_age < ArenaScreen.REVIVE_BANNER and sim.revives > 0:
		_draw_revive_banner(sim)
	elif _banner_age() < _banner_life():
		match String(_banner["kind"]):
			"wave": _draw_wave_banner(sim)
			"held": _draw_held_banner(sim)
			"elite": _draw_elite_banner(sim)
	elif Arena.modal.is_empty() and not s.talent_view._pick_node.is_empty() and s.t - s.talent_view._pick_t0 < ArenaScreen.PICK_BANNER:
		_banner_rect = _banner_box(sim)
		s.talent_view._draw_pick_banner(sim)
	_draw_aim_hint(sim)

## The waves as this picture sees them, against the last: a preparation ending is a wave
## beginning, a preparation beginning after a wave is that wave held, an elite never seen before
## has stepped in. A new run or stage (or a restored one) starts the memory without a banner.
func _watch_waves(sim) -> void:
	var dt := 0.0 if _clock_t < 0.0 else clampf(s.t - _clock_t, 0.0, 0.25)
	_clock_t = s.t
	if Arena.modal.is_empty(): _bclock += dt
	var wave: int = sim.wave_no
	var prep: bool = sim.in_prep()
	var key := "%d:%d:%s:%d" % [Arena.run_seed, Arena.stage, Arena.hell, sim.get_instance_id()]
	if key != _wave_key:
		_wave_key = key
		_wave_seen = wave
		_prep_seen = prep
		_hp_seen = sim.crystal_hp
		_elites_seen.clear()
		for mo in sim.monsters:
			if bool(mo.get("elite", false)): _elites_seen[int(mo.get("spawn_id", 0))] = true
		_banner = {}
		return
	if _prep_seen and not prep:
		# The boss wave has no banner: its warning and its strip hold the row.
		if not sim.is_boss_wave(wave):
			_banner = {"kind": "wave", "t0": _bclock, "wave": wave}
	elif not _prep_seen and prep and wave > _wave_seen:
		_banner = {"kind": "held", "t0": _bclock, "wave": wave - 1, "gold": _wave_bonus(sim, wave - 1),
			"heal": maxf(0.0, sim.crystal_hp - _hp_seen)}
	for mo in sim.monsters:
		if not bool(mo.get("elite", false)): continue
		var sid := int(mo.get("spawn_id", 0))
		if _elites_seen.has(sid): continue
		_elites_seen[sid] = true
		_banner = {"kind": "elite", "t0": _bclock, "id": String(mo["m"].get("id", "")),
			"name": String(mo["m"].get("ko", "")), "body": String(mo["m"].get("body", ""))}
	_wave_seen = wave
	_prep_seen = prep
	_hp_seen = sim.crystal_hp

## The defence bonus of a held wave, as the simulator's arena_wave_clear event says it (the view
## consumes the events before the HUD draws): the simulator's own record when it keeps one, else
## the same reckoning as ArenaSim._clear_wave — Hellbound counts the wave's place in its block.
func _wave_bonus(sim, cleared: int) -> int:
	var kept = sim.get("last_wave_clear")
	if kept is Dictionary and int(kept.get("wave", -1)) == cleared:
		return int(kept.get("gold", 0))
	var place := Balance.arena_hell_ramp_wave(cleared) if sim.waves_total() == 0 else cleared
	return Balance.arena_wave_bonus(Arena.stage, place)

func _banner_age() -> float:
	return _bclock - float(_banner.get("t0", -100.0))

func _banner_life() -> float:
	match String(_banner.get("kind", "")):
		"wave": return WAVE_BANNER
		"held": return HELD_BANNER
		"elite": return ELITE_BANNER
	return 0.0

## A field banner's plaque: the cast shadow, the glass, the landing and the fade. Returns the
## fade; the caller resets the transform when it is done.
func _plaque(box: Rect2, edge: Color, face: Color, age: float, life: float, settled: bool) -> float:
	_banner_rect = box
	var fade := 1.0 if settled else clampf((life - age) * 3.0, 0.0, 1.0)
	var k := 1.0 if settled else _ease_out(age / 0.16)
	s.draw_set_transform(Vector2(0, -(1.0 - k) * 14.0), 0, Vector2.ONE)
	# Fading parts are plain rectangles (Look.fill_round caches one surface per colour).
	s.draw_rect(Rect2(box.position + Vector2(3, 5), box.size - Vector2(6, 0)), Color(0, 0, 0, 0.32 * fade))
	Look.glass_panel(s, box, edge, face, true, fade)
	return fade

## A title on a plaque's first row with a rule from the words to a diamond at each end.
func _plaque_title(box: Rect2, title: String, size: int, ink: Color, rule: Color, fade: float, inset: float = 70.0) -> void:
	var title_box := Rect2(box.position.x + inset, box.position.y + 1, box.size.x - inset * 2.0, 42)
	var fitted := Look.text_box(s, title_box, title, size, Color(ink, fade))
	var half := Look.text_width(title, fitted) * 0.5 + 14.0
	var mid := Vector2(box.get_center().x, title_box.get_center().y)
	for side in [-1.0, 1.0]:
		var from := mid + Vector2(side * half, 0)
		var to := Vector2(box.get_center().x + side * (box.size.x * 0.5 - 22.0), mid.y)
		if (to.x - from.x) * side > 8.0:
			s.draw_line(from, to, Color(rule, 0.55 * fade), 1.4, true)
			_draw_diamond(to, 5, Color(rule, fade))

## One pass of light over a plaque as it lands.
func _plaque_sweep(box: Rect2, age: float, strength: float) -> void:
	if s._settled() or age >= 0.5: return
	var sweep := box.position.x + box.size.x * clampf(age / 0.42, 0.0, 1.0)
	Look.gradient_rect(s, Rect2(sweep - 60, box.position.y + 2, 60, box.size.y - 4), Color(1, 0.95, 0.75, 0.0), Color(1, 0.95, 0.75, strength * (1.0 - age / 0.5)))

## A wave begins: "WAVE 3" with the number large, and the stage's waves under it with this one
## lit (Hellbound: its block of ten and the endless mark). An elite wave says so in violet.
func _draw_wave_banner(sim) -> void:
	var box := _banner_box(sim)
	var age := _banner_age()
	var settled := s._settled()
	var shown := int(_banner.get("wave", sim.wave_no))
	var elite: bool = sim.is_elite_wave(shown)
	var edge := Look.ELITE if elite else Look.GATE_MARK
	var fade := _plaque(box, edge, Color(0.03, 0.05, 0.075, 0.90), age, WAVE_BANNER, settled)
	var parts := _split(_tr("wave_label"))
	var lead: String = parts[0]
	var tail: String = parts[1]
	var number := str(shown)
	var lead_w := Look.text_width(lead, 22)
	var number_w := Look.text_width(number, 34)
	var tail_w := Look.text_width(tail, 22)
	var width := lead_w + number_w + tail_w
	var x := box.get_center().x - width * 0.5
	var y := box.position.y + 23.0
	Look.text_left(s, Vector2(x, y + 4), lead, 22, Color(Look.INK_DIM, fade))
	Look.text_left(s, Vector2(x + lead_w, y), number, 34, Color(Look.IVORY, fade))
	if not tail.is_empty(): Look.text_left(s, Vector2(x + lead_w + number_w, y + 4), tail, 22, Color(Look.INK_DIM, fade))
	var half := width * 0.5 + 16.0
	for side in [-1.0, 1.0]:
		var from := Vector2(box.get_center().x + side * half, y)
		var to := Vector2(box.get_center().x + side * (box.size.x * 0.5 - 22.0), y)
		if (to.x - from.x) * side > 8.0:
			s.draw_line(from, to, Color(edge, 0.55 * fade), 1.4, true)
			_draw_diamond(to, 5, Color(edge, fade))
	# The stage's waves (Hellbound: its block of ten and the endless mark); an elite wave's chip
	# beside them.
	var endless: bool = sim.waves_total() == 0
	var chip_w := Look.text_width(_tr("elite"), 14) + 20.0 if elite else 0.0
	var track_w := 196.0
	var extra := (chip_w + 12.0 if elite else 0.0) + (28.0 if endless else 0.0)
	var row_y := box.position.y + 54.0
	var start := box.get_center().x - (track_w + extra) * 0.5
	_draw_waves_track(Rect2(start, row_y - 3.5, track_w, 7), sim, true, fade)
	var after := start + track_w
	if endless:
		Look.draw_infinity(s, Vector2(after + 16.0, row_y), 8.0, Color(Look.INK_DIM, fade), 1.8)
		after += 28.0
	if elite:
		var chip := Rect2(after + 12.0, row_y - 10.0, chip_w, 20.0)
		s.draw_rect(chip, Color(Look.ELITE, 0.85 * fade))
		Look.text_box(s, chip, _tr("elite"), 14, Color(Look.IVORY, fade))
	_plaque_sweep(box, age, 0.14)
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## A wave held: 「방어 성공!」, the defence bonus said with the coin the gold counter uses, and
## what the crystal mended.
func _draw_held_banner(sim) -> void:
	var box := _banner_box(sim)
	var age := _banner_age()
	var fade := _plaque(box, Look.GOLD, Color(0.105, 0.085, 0.025, 0.90), age, HELD_BANNER, s._settled())
	_plaque_title(box, _tr("wave_held"), 28, Look.IVORY, Look.GOLD, fade)
	var bonus := "+%d G" % int(_banner.get("gold", 0))
	var heal := float(_banner.get("heal", 0.0))
	var mended := "+%d" % roundi(heal) if heal >= 1.0 else ""
	var row_y := box.position.y + 52.0
	var bonus_w := Look.text_width(bonus, 19)
	var mended_w := 30.0 + 18.0 + Look.text_width(mended, 19) if not mended.is_empty() else 0.0
	var left := box.get_center().x - (22.0 + bonus_w + mended_w) * 0.5
	_draw_coin(Vector2(left + 8.0, row_y), 8, fade)
	Look.text_left(s, Vector2(left + 22.0, row_y), bonus, 19, Color(Look.GOLD, fade))
	if not mended.is_empty():
		var at := left + 22.0 + bonus_w + 30.0
		Look.draw_crystal(s, Vector2(at + 5.0, row_y + 1.0), 6.5, true)
		Look.text_left(s, Vector2(at + 18.0, row_y), mended, 19, Color(Look.CRYSTAL, fade))
	_plaque_sweep(box, age, 0.16)
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## An elite steps in: its render on the left over a violet glow, 「정예 출현」 and its name.
func _draw_elite_banner(sim) -> void:
	var box := _banner_box(sim)
	var age := _banner_age()
	var settled := s._settled()
	var fade := _plaque(box, Look.ELITE, Color(0.07, 0.035, 0.115, 0.92), age, ELITE_BANNER, settled)
	var art := Rect2(box.position.x + 8, box.position.y + 5, 62, box.size.y - 10)
	for layer in range(5):
		s.draw_circle(Vector2(art.get_center().x, art.end.y - 18), 30.0 - layer * 5.0, Color(Look.ELITE, 0.07 * fade), true, -1, true)
	var pop := 1.0 if settled else 0.80 + 0.20 * _ease_out(age / 0.24)
	var drawn := Rect2(art.get_center() - art.size * pop * 0.5, art.size * pop)
	if not Look.draw_monster_portrait(s, String(_banner.get("id", "")), drawn, Color(1, 1, 1, fade)):
		Look.draw_body(s, art.get_center(), 16, String(_banner.get("body", "")))
	_draw_elite_crest(Vector2(art.end.x - 2, art.position.y + 9), 7.0, fade)
	var text_x := box.position.x + 82.0
	var text_w := box.size.x - 96.0
	Look.text_box(s, Rect2(text_x, box.position.y + 2, text_w, 38), _tr("elite_in"), 26, Color(Look.ELITE_INK, fade), HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(s, Rect2(text_x, box.position.y + 38, text_w, 26), I18n.t(String(_banner.get("name", ""))), 18, Color(Look.INK, fade), HORIZONTAL_ALIGNMENT_LEFT)
	_plaque_sweep(box, age, 0.12)
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## The elite's crest: a violet diamond with a light edge (its health bar and banner carry it).
func _draw_elite_crest(c: Vector2, r: float, alpha: float = 1.0) -> void:
	_draw_diamond(c, r + 1.6, Color(Look.BG_DEEP, 0.85 * alpha))
	_draw_diamond(c, r, Color(Look.ELITE, alpha))
	_draw_diamond(c + Vector2(0, -r * 0.18), r * 0.42, Color(Look.ELITE_INK, alpha))

## The stage boss fell and the stage is won: for the clear delay the banner says so before the
## result panel opens. A plain stage has the gold plaque; a chapter's last stage the brightest
## plaque, framed twice, with stars where the others carry diamonds. Under the words stand the
## stage's ten waves, all lit, and "STAGE n 클리어", which the result panel repeats.
## `fade` below 1 is the hand-over: the settled banner dissolving under the result's shade.
func _draw_final_banner(sim, fade: float = 1.0) -> void:
	var box := _banner_box(sim)
	_banner_rect = box
	var age: float = Balance.ARENA_CLEAR_DELAY - sim.clear_t
	var settled := s._settled() or fade < 1.0
	var chapter: bool = sim.has_method("chapter_boss") and sim.chapter_boss()
	var k := 1.0 if settled else _ease_out(age / 0.18)
	s.draw_set_transform(Vector2(0, -(1.0 - k) * 14.0), 0, Vector2.ONE)
	var ivory := Look.IVORY
	# Plain rectangles where the alpha moves (Look.fill_round caches a surface per colour).
	s.draw_rect(Rect2(box.position + Vector2(3, 6), box.size - Vector2(6, 0)), Color(0, 0, 0, 0.36 * fade))
	if chapter:
		Look.glass_panel(s, box, ivory, Color(0.155, 0.112, 0.03, 0.94), true, fade)
		# A warm light falls into the plaque from its top edge.
		Look.gradient_rect(s, Rect2(box.position + Vector2(6, 3), Vector2(box.size.x - 12, 36)), Color(Look.GOLD, 0.26 * fade), Color(Look.GOLD, 0.0), true)
		s.draw_rect(box.grow(-4.0), Color(Look.GOLD, 0.42 * fade), false, 1.0)
	else:
		Look.glass_panel(s, box, Look.GOLD, Color(0.105, 0.085, 0.025, 0.92), true, fade)
	var title := _tr("chapter_down") if chapter else _tr("boss_down")
	var title_box := Rect2(box.position.x + 44, box.position.y + 1, box.size.x - 88, 44)
	var size := Look.text_box(s, title_box, title, 30 if chapter else 28, Color(Look.IVORY, fade))
	# A star (chapter) or a diamond at each end; a brass rule joins it to the words.
	var mid := Vector2(box.get_center().x, title_box.get_center().y)
	var half := Look.text_width(title, size) * 0.5 + 14.0
	for side in [-1.0, 1.0]:
		var end := Vector2(box.get_center().x + side * (box.size.x * 0.5 - 25.0), mid.y)
		var from := mid + Vector2(side * half, 0)
		var to := end - Vector2(side * 13.0, 0)
		if (to.x - from.x) * side > 10.0:
			s.draw_line(from, to, Color(Look.GOLD, 0.60 * fade), 1.4, true)
		var pop := 1.0 if settled else _ease_out((age - 0.10) / 0.20)
		if pop <= 0.0: continue
		if chapter:
			s.draw_colored_polygon(Look.star_points(end, 10.5 * pop), Color(Look.BG_DEEP, 0.85 * fade))
			s.draw_colored_polygon(Look.star_points(end, 8.0 * pop), Color(ivory, fade))
		else:
			_draw_diamond(end, 6.0 * pop, Color(Look.GOLD, fade))
	# The stage's ten waves, all lit, and the stage it was.
	var words := _tr("stage_clear_n") % Arena.stage
	var words_w := Look.text_width(words, 17)
	var track_w := 140.0
	var row_y := box.position.y + 54.0
	var left := box.get_center().x - (track_w + 12.0 + words_w) * 0.5
	# As the banner lands a glint runs the ten steps: the stage is complete.
	var glint := -1.0 if settled else (age - 0.22) / 0.46
	_draw_waves_track(Rect2(left, row_y - 4.0, track_w, 8.0), sim, true, fade, glint)
	Look.text_left(s, Vector2(left + track_w + 12.0, row_y), words, 17, Color(Look.GOLD.lightened(0.22), fade))
	if not settled and age < 0.5:
		# One pass of light over the whole plaque.
		var sweep := box.position.x + box.size.x * clampf(age / 0.42, 0.0, 1.0)
		Look.gradient_rect(s, Rect2(sweep - 70, box.position.y + 2, 70, box.size.y - 4), Color(1, 0.96, 0.78, 0.0), Color(1, 0.96, 0.78, 0.20 * (1.0 - age / 0.5)))
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## A revival ticket's moment (the DLC, D2): what happened, the 5-star hero who joined — its
## portrait, five stars, its name and whether it stands on the field or waits on the bench —
## how many tickets are left (a label and one pip each; after the last one the label says so
## in the warning colour), and how long the reformed crystal cannot be hurt. Never gold.
func _draw_revive_banner(sim) -> void:
	var top := _banner_box(sim).position.y
	var box := Rect2(ArenaScreen.BATTLEFIELD.get_center().x - REVIVE_SIZE.x * 0.5, top, REVIVE_SIZE.x, REVIVE_SIZE.y)
	_banner_rect = box
	var fade := clampf((ArenaScreen.REVIVE_BANNER - s._revive_age) * 2.0, 0.0, 1.0)
	var settled := s._settled()
	var k := 1.0 if settled else _ease_out(s._revive_age / 0.18)
	s.draw_set_transform(Vector2(0, -(1.0 - k) * 14.0), 0, Vector2.ONE)
	# Fading parts are plain rectangles (Look.fill_round caches one surface per colour).
	s.draw_rect(Rect2(box.position + Vector2(3, 5), box.size - Vector2(6, 0)), Color(0, 0, 0, 0.32 * fade))
	Look.glass_panel(s, box, Look.CRYSTAL, Color(0.02, 0.095, 0.135, 0.90), true, fade)
	var crest := box.position + Vector2(40, 30)
	s.draw_circle(crest, 27, Color(Look.CRYSTAL, 0.10 * fade), true, -1, true)
	StoreView.draw_icon(s, crest, Store.GUARDIAN, 22, Color(Look.CRYSTAL, fade))
	var text_x := box.position.x + 78.0
	var right := box.end.x - 16.0
	# Seconds the reformed crystal cannot be hurt: the ward's glyph beside the title and a
	# draining bar along the bottom, so the number needs no word in either language.
	var guard := clampf(sim.invuln_t / maxf(0.001, Balance.ARENA_REVIVE_INVULN), 0.0, 1.0)
	var title_w := right - text_x
	if guard > 0.0:
		var seconds := "%.1f" % sim.invuln_t
		var seconds_w := Look.text_width(seconds, 18)
		Look.text_right(s, Vector2(right, box.position.y + 21), seconds, 18, Color(Look.CRYSTAL_INK, fade))
		_draw_skill_icon(Vector2(right - seconds_w - 14, box.position.y + 21), "ward", 8, Color(Look.CRYSTAL, fade))
		title_w -= seconds_w + 32.0
		var track := Rect2(box.position.x + 12, box.end.y - 6, box.size.x - 24, 3)
		s.draw_rect(track, Color(0.19, 0.26, 0.29, fade))
		s.draw_rect(Rect2(track.position, Vector2(track.size.x * guard, track.size.y)), Color(Look.CRYSTAL, fade))
	Look.text_box(s, Rect2(text_x, box.position.y + 2, title_w, 38), _tr("revived"), 25, Color(Look.CRYSTAL_INK, fade), HORIZONTAL_ALIGNMENT_LEFT)
	# The 5-star hero who joined (Arena.revive_gift): its face, 「%s 합류」 (arena.revive_hero),
	# its five stars and where it stands. Nobody joins when every hero is already at the top.
	var gift: Dictionary = Arena.revive_gift
	var unit: Dictionary = gift.get("unit", {}) if gift.get("unit") is Dictionary else {}
	if not unit.is_empty():
		var tier := int(gift.get("tier", Balance.TIER_MAX))
		var chip := Rect2(text_x, box.position.y + 44, 34, 34)
		_draw_portrait_chip(chip, unit, tier, fade)
		var line_x := chip.end.x + 10.0
		Look.text_box(s, Rect2(line_x, box.position.y + 39, right - line_x, 25), _tr("revive_hero") % Look.unit_name(unit), 17, Color(Look.INK, fade), HORIZONTAL_ALIGNMENT_LEFT)
		var stars := Rect2(line_x - 1, box.position.y + 64, 84, 14)
		Look.draw_rarity_fit(s, stars, tier, 5.2)
		var where := String(gift.get("where", ""))
		var tag := _tr("revive_bench") if where == "bench" else _tr("revive_field")
		var tag_rect := Rect2(stars.end.x + 10.0, box.position.y + 62, Look.text_width(tag, 13) + 16.0, 19)
		s.draw_rect(tag_rect, Color(Look.GOLD if where != "bench" else Look.STEEL, 0.88 * fade))
		Look.text_box(s, tag_rect.grow_individual(0, 1, 0, 1), tag, 13, Color(Look.BG_DEEP, fade))
	# The tickets left: a label and one pip each.
	var row_y := box.position.y + 90.0
	var left: int = sim.revives_left()
	var last := left <= 0
	var label := _tr("revives_none") if last else _tr("revives_left")
	var tone := Look.WARN if last else Look.CRYSTAL
	Look.text_left(s, Vector2(text_x, row_y), label, 14, Color(tone, fade))
	var pip_x := text_x + Look.text_width(label, 14) + 10.0
	for n in range(Balance.ARENA_REVIVE_USES):
		var pip := Vector2(pip_x + 6.5 + float(n) * 13.0, row_y)
		if n < left:
			_draw_diamond(pip, 6.0, Color(Look.CRYSTAL, fade))
		else:
			s.draw_polyline(PackedVector2Array([pip + Vector2(0, -5.5), pip + Vector2(3.8, 0), pip + Vector2(0, 5.5), pip + Vector2(-3.8, 0), pip + Vector2(0, -5.5)]), Color(tone, 0.75 * fade), 1.3, true)
	if not settled and s._revive_age > 0.10 and s._revive_age < 0.60 and left < Balance.ARENA_REVIVE_USES:
		# The pip that was just spent goes out as the banner lands.
		var spent := Vector2(pip_x + 6.5 + float(left) * 13.0, row_y)
		_draw_diamond(spent, 6.0 + 5.0 * _ease_out((s._revive_age - 0.10) / 0.50), Color(1, 1, 1, 0.75 * (1.0 - (s._revive_age - 0.10) / 0.50)))
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## A hero's face in a small gold frame (the revival banner's 5-star hero): a square crop of the
## head and shoulders from the guardian card's upper-body render.
func _draw_portrait_chip(rect: Rect2, unit: Dictionary, tier: int, alpha: float = 1.0) -> void:
	s.draw_rect(rect.grow(1.5), Color(Look.GOLD, 0.95 * alpha))
	s.draw_rect(rect, Color(0.02, 0.05, 0.08, alpha))
	var picture := _portrait(unit, tier)
	if not picture.is_empty():
		var crop: Rect2 = picture["crop"]
		# Centred a little under the upper body's middle: the face, below a halo or a tall crest.
		var side := minf(crop.size.x, crop.size.y * 0.62)
		var head := Rect2(crop.get_center().x - side * 0.5, crop.position.y + crop.size.y * 0.48 - side * 0.5, side, side)
		s.draw_texture_rect_region(picture["tex"], rect.grow(-1), head, Color(1, 1, 1, alpha))
	else:
		Look.draw_elem(s, rect.get_center(), 9, String(unit.get("elem", "none")))

## The upper-body crop of a hero's portrait (cards and chips), measured once per hero and grade.
func _portrait(unit: Dictionary, tier: int) -> Dictionary:
	var preview := Art.unit_preview(unit, tier)
	if preview.is_empty(): return {}
	var key := String(unit["id"]) + ":" + str(tier)
	if not _card_crops.has(key):
		var texture: Texture2D = preview["tex"]
		var picture: Image = texture.diffuse_texture.get_image() if texture is CanvasTexture else texture.get_image()
		if picture.is_compressed(): picture.decompress()
		var visible := Rect2(picture.get_used_rect())
		var crop_height := visible.size.y * 0.53
		var crop_width := minf(visible.size.x, crop_height * 0.86)
		_card_crops[key] = Rect2(visible.get_center().x - crop_width * 0.5, visible.position.y - 3, crop_width, crop_height)
	return {"tex": preview["tex"], "crop": _card_crops[key]}

## The starfall's aim (F6): while the blast is armed a pill on the open battle box's bottom edge
## says what to do — 「떨어질 곳을 누르세요」 — beside the aim's own mark (the ground ring's gold, its
## lock-on arrowheads and the star at its heart: ArenaWorld.set_aim draws the same on the ground)
## and a cancel button (aim:cancel, the pill's only zone: a press on its body still aims). It
## stands where no road comes in (the centre of the edge, else a corner — never over a gate),
## and a thin gold line breathes round the open battle box: the field is the target. A spot the
## star cannot take turns the mark and the words red-grey.
func _draw_aim_hint(_sim) -> void:
	var aiming := _aiming()
	if aiming and not _aiming_seen:
		_aim_t0 = s.t
	_aiming_seen = aiming
	if not aiming: return
	var settled := s._settled()
	var valid := _aim_valid()
	var tint := Look.AIM_GOLD if valid else Look.AIM_BAD
	var breath := 0.6 if settled else 0.5 + 0.5 * sin(s.t * 3.0)
	s.draw_rect(ArenaScreen.BATTLEFIELD.grow(-2.0), Color(tint, 0.18 + 0.16 * breath), false, 2.0)
	var text := _tr("skill_aim")
	var cancel := _tr("skill_cancel")
	var cancel_w := maxf(70.0, Look.text_width(cancel, 17) + 30.0)
	var chrome := 14.0 + 34.0 + 12.0 + 18.0 + cancel_w + 6.0
	# One line on the bottom edge where no road comes in; where every place on the edge has a road
	# (a gate at the bottom), the words take two lines and the pill fits a corner beside it.
	var lines: Array = [text]
	var size := 20
	var w := minf(chrome + Look.text_width(text, 20), ArenaScreen.BATTLEFIELD.size.x - 48.0)
	var place := _aim_hint_place(w, AIM_HINT_H)
	if int(place[1]) > 0:
		var wrapped := Look.wrapped_lines(text, ceilf(Look.text_width(text, 17) * 0.5) + 24.0, 17)
		if wrapped.size() == 2:
			var narrow := chrome + maxf(Look.text_width(wrapped[0], 17), Look.text_width(wrapped[1], 17))
			var second := _aim_hint_place(narrow, AIM_HINT_H + 14.0)
			if int(second[1]) < int(place[1]):
				place = second
				lines = wrapped
				size = 17
	var box: Rect2 = place[0]
	var age := s.t - _aim_t0
	var k := 1.0 if settled else _ease_out(age / 0.16)
	s.draw_set_transform(Vector2(0, (1.0 - k) * 10.0), 0, Vector2.ONE)
	s.draw_rect(Rect2(box.position + Vector2(3, 5), box.size - Vector2(6, 0)), Color(0, 0, 0, 0.30 * k))
	Look.glass_panel(s, box, tint, Color(0.10, 0.07, 0.025, 0.92), true, k)
	var mark := Vector2(box.position.x + 14.0 + 17.0, box.get_center().y)
	_draw_aim_mark(mark, 10.5, tint, valid, 0.0 if settled else s.t * 0.9, k)
	var button := Rect2(box.end.x - 6.0 - cancel_w, box.get_center().y - (AIM_HINT_H - 12.0) * 0.5, cancel_w, AIM_HINT_H - 12)
	var words_x := mark.x + 17.0 + 12.0
	var words_w := button.position.x - 12.0 - words_x
	var ink := Color(Look.IVORY if valid else tint, k)
	if lines.size() == 1:
		Look.text_box(s, Rect2(words_x, box.position.y + 4, words_w, box.size.y - 8), text, size, ink, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		Look.text_box(s, Rect2(words_x, box.position.y + 4, words_w, 25), String(lines[0]), size, ink, HORIZONTAL_ALIGNMENT_LEFT)
		Look.text_box(s, Rect2(words_x, box.position.y + 28, words_w, 25), String(lines[1]), size, ink, HORIZONTAL_ALIGNMENT_LEFT)
	s.ui.zone(button.grow(5), "aim:cancel", true)
	var down := s.ui.pressed == "aim:cancel"
	var face := Color(0.07, 0.12, 0.155, 0.92)
	if down: face = face.lightened(0.12)
	Look.glass_panel(s, Rect2(button.position + Vector2(0, 1.0 if down else 0.0), button.size), Look.STEEL, face, false, k)
	Look.text_box(s, button.grow(-4), cancel, 17, Color(Look.INK, k))
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## The aim hint's place on the battle box's bottom edge, `w` × `h`: the centre, else the left or the
## right corner — the first with no road under it (the first stretch of every road and its
## approach, where the monsters step in), else the one with the fewest. Returns [rect, hits].
func _aim_hint_place(w: float, h: float) -> Array:
	var field := ArenaScreen.BATTLEFIELD
	var y := field.end.y - h - 12.0
	var best := Rect2(field.get_center().x - w * 0.5, y, w, h)
	var best_hits := 1 << 30
	for x in [field.get_center().x - w * 0.5, field.position.x + 16.0, field.end.x - 16.0 - w]:
		var rect := Rect2(x, y, w, h)
		var hits := _road_hits(rect.grow(40.0))
		if hits < best_hits:
			best_hits = hits
			best = rect
		if hits == 0: break
	return [best, best_hits]

## Road samples under `rect`: each lane's first stretch inside the rim and its approach outside it
## (radial from the gate to past the screen's edge, as ArenaLand.road_line lays it).
func _road_hits(rect: Rect2) -> int:
	var hits := 0
	for lane in range(ArenaGeometry.route_count()):
		var route := ArenaGeometry.route_points(lane)
		for i in range(mini(route.size(), 12)):
			if rect.has_point(s.view_3d.project(route[i], 0.0)): hits += 1
		var gate := ArenaGeometry.gate_point(lane)
		var out := (gate - Balance.ARENA_CENTER).normalized()
		for n in range(24):
			if rect.has_point(s.view_3d.project(gate + out * (float(n) * 30.0), 0.0)): hits += 1
	return hits

## The aim's mark, the 3D aim ring in small (art/vfx/vfx_ring.gdshader mode 1): a translucent
## disc, the solid ring, eight arrowheads at 1.35 R pointing in and turning slowly, a four-point
## star at its heart; a spot the star cannot take gets a cross instead of the star.
func _draw_aim_mark(c: Vector2, r: float, color: Color, valid: bool, spin: float, alpha: float = 1.0) -> void:
	s.draw_circle(c, r * 1.35 + 6.0, Color(0, 0, 0, 0.30 * alpha), true, -1, true)
	s.draw_circle(c, r, Color(color, 0.16 * alpha), true, -1, true)
	s.draw_arc(c, r, 0, TAU, 32, Color(color, alpha), 2.0, true)
	_draw_arrowheads(c, r * 1.35 + 0.5, 4.6, 2.5, spin, Color(color, alpha))
	if valid:
		_draw_four_star(c, r * 0.62, Color(color.lightened(0.30), alpha))
	else:
		var a := r * 0.42
		s.draw_line(c + Vector2(-a, -a), c + Vector2(a, a), Color(color, alpha), 2.2, true)
		s.draw_line(c + Vector2(a, -a), c + Vector2(-a, a), Color(color, alpha), 2.2, true)

## Eight arrowheads round `c`: tips at `at` pointing in, `length` long and `half` wide at the base.
func _draw_arrowheads(c: Vector2, at: float, length: float, half: float, spin: float, color: Color) -> void:
	for n in range(8):
		var d := Vector2.from_angle(spin + n * TAU / 8.0)
		var side := Vector2(-d.y, d.x)
		var tip := c + d * at
		var base := c + d * (at + length)
		s.draw_colored_polygon(PackedVector2Array([tip, base + side * half, base - side * half]), color)

## A four-point star (the 3D ring's centre mark).
func _draw_four_star(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for n in range(8):
		points.append(c + Vector2.from_angle(-PI * 0.5 + n * PI / 4.0) * (r if n % 2 == 0 else r * 0.30))
	s.draw_colored_polygon(points, color)

func _aiming() -> bool:
	return s.has_method("aiming") and bool(s.aiming())

func _aim_valid() -> bool:
	if not s.has_method("aim_valid"): return true
	# Before the finger (or cursor) is on the field there is no spot yet: nothing is wrong.
	var pixel = s.get("aim_pixel")
	if pixel is Vector2 and not (pixel as Vector2).is_finite(): return true
	return bool(s.aim_valid())

## Battle speed x1 / x2 / x3 as one segmented chip in the top strip, left of the menu
## (user: "배속설정은 상단으로"). The chosen chip is solid gold; the others stay glass.
func _draw_speed() -> void:
	var active := Arena.sim != null and not Arena.sim.done
	Look.glass_panel(s, ArenaScreen.SPEED_BOX, Look.STEEL, Color(0.02, 0.06, 0.09, 0.80))
	var inner := ArenaScreen.SPEED_BOX.grow(-3)
	var width := inner.size.x / 3.0
	var chosen := clampi(roundi(s.speed), 1, 3)
	for i in range(3):
		var value := i + 1
		var id := "speed:%d" % value
		var rect := Rect2(inner.position + Vector2(i * width, 0), Vector2(width, inner.size.y))
		# The touch zone spans the whole strip height; the drawn chip stays compact.
		s.ui.zone(Rect2(rect.position.x, 4, rect.size.x, 62), id, active)
		var down := active and s.ui.pressed == id
		if i > 0:
			s.draw_line(Vector2(rect.position.x, rect.position.y + 6), Vector2(rect.position.x, rect.end.y - 6), Color(Look.STEEL, 0.45), 1, true)
		if value == chosen:
			Look.fill_round(s, rect, 4, Look.GOLD.darkened(0.10) if down else Look.GOLD)
			s.draw_line(rect.position + Vector2(5, 2), Vector2(rect.end.x - 5, rect.position.y + 2), Look.GOLD.lightened(0.35), 1)
		elif down:
			Look.fill_round(s, rect.grow(-1), 4, Color(0.42, 0.60, 0.70, 0.28))
		var ink := Look.BG_DEEP if value == chosen else (Look.INK_DIM if active else Look.INK_MUTE)
		Look.text_box(s, rect, "x%d" % value, 19, ink)

## Crystal ward: the remaining seconds dominate (large tenths, a draining ring and a
## bar); absorb left is the secondary line. Pulses gold in the final two seconds.
func _draw_shield_panel(sim) -> void:
	if sim.shield <= 0: return
	var box := ArenaScreen.SHIELD_BOX
	var left := clampf(sim.shield_t / maxf(0.001, Balance.ARENA_WARD_DURATION), 0, 1)
	var urgent: bool = sim.shield_t <= 2.0
	var tint: Color = Look.CRYSTAL.lerp(Look.GOLD.lightened(0.2), 0.5 + 0.5 * sin(s.t * 18)) if urgent else Look.CRYSTAL
	Look.glass_panel(s, box, tint, Color(0.015, 0.08, 0.14, 0.84))
	var ring := box.position + Vector2(25, 23)
	s.draw_arc(ring, 15, 0, TAU, 40, Color(Look.CRYSTAL, 0.18), 3, true)
	if left > 0: s.draw_arc(ring, 15, -PI / 2, -PI / 2 + TAU * left, 40, tint, 3, true)
	_draw_skill_icon(ring, "ward", 7, tint)
	Look.text_box(s, Rect2(box.position + Vector2(48, 1), Vector2(72, 44)), "%.1f" % sim.shield_t, 30, Look.INK)
	# The absorb number sits clear of the time bar under it (its feet were under the bar).
	Look.text_box(s, Rect2(box.position + Vector2(124, 0), Vector2(82, 22)), _tr("shield"), 15, Look.INK_DIM)
	Look.text_box(s, Rect2(box.position + Vector2(124, 16), Vector2(82, 24)), str(ceili(sim.shield)), 16, tint)
	_bar(Rect2(box.position.x + 10, box.end.y - 7, box.size.x - 20, 3), left, tint)

## Boss strip over the open battle box: the warning banner during the boss wave's preparation
## (whole-second countdown of that preparation, boss name, chevron toward its gate on screen),
## then its health bar.
func _draw_boss_panel(sim) -> void:
	var box := ArenaScreen.BOSS_BOX
	if sim.boss_spawned:
		for mo in sim.monsters:
			if String(mo.get("kind", "")) != "boss": continue
			Look.glass_panel(s, box, Look.BOSS, Color(0.09, 0.02, 0.06, 0.86))
			var fraction := clampf(float(mo["hp"]) / maxf(1, float(mo["max"])), 0, 1)
			Look.text_box(s, Rect2(box.position + Vector2(16, 2), Vector2(box.size.x - 32, 28)), I18n.t(String(mo["m"].get("ko", _boss_label(sim)))), 19, Look.INK)
			_bar(Rect2(box.position.x + 16, box.end.y - 13, box.size.x - 32, 5), fraction, Look.RED)
			break
		return
	if not sim.boss_warned: return
	var left := maxf(0.0, float(sim.prep_left()))
	var pulse := 0.5 + 0.5 * sin(s.t * 9.0)
	var edge := Look.WARN.lerp(Look.GOLD, pulse * 0.45)
	Look.glass_panel(s, box, edge, Color(0.17, 0.03, 0.05, 0.88), true)
	var sign_at := box.position + Vector2(25, 24)
	s.draw_colored_polygon(PackedVector2Array([sign_at + Vector2(0, -14), sign_at + Vector2(14, 10), sign_at + Vector2(-14, 10)]), Color(edge, 0.92))
	s.draw_line(sign_at + Vector2(0, -5), sign_at + Vector2(0, 3), Look.BG_DEEP, 2.5)
	s.draw_circle(sign_at + Vector2(0, 7), 1.6, Look.BG_DEEP)
	var boss: Dictionary = Arena.boss_for(1)
	Look.text_box(s, Rect2(box.position + Vector2(50, 0), Vector2(226, 21)), _boss_label(sim), 14, edge, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(s, Rect2(box.position + Vector2(50, 18), Vector2(226, 28)), I18n.t(String(boss.get("ko", ""))), 19, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	# Whole seconds, rounded up like the wave cell's countdown: 4, 3, 2, 1, boss.
	var count := maxi(1, ceili(left - 0.0001))
	Look.text_box(s, Rect2(box.end.x - 112, box.position.y, 54, 46), str(count), 30, Look.INK)
	var gate: Vector2 = sim.boss_gate()
	if gate.is_finite():
		var origin := Vector2(box.end.x - 34, box.get_center().y)
		var direction := (s.view_3d.project(gate, 0.3) - origin).normalized()
		_draw_chevron(origin, direction, 11 + pulse * 2, edge)

func _draw_chevron(at: Vector2, direction: Vector2, size: float, color: Color) -> void:
	var normal := Vector2(-direction.y, direction.x)
	for n in range(2):
		var tip := at + direction * (size * 0.55 - n * size * 0.5)
		var back := tip - direction * size * 0.5
		s.draw_polyline(PackedVector2Array([back + normal * size * 0.5, tip, back - normal * size * 0.5]), Color(color, 1.0 - n * 0.4), 3, true)

func _draw_controls() -> void:
	# All commands live in one right rail; the lower field stays open for movement.
	s.draw_rect(ArenaScreen.SIDEBAR, Color(0.012, 0.037, 0.06, 0.88))
	s.draw_line(ArenaScreen.SIDEBAR.position, Vector2(ArenaScreen.SIDEBAR.position.x, ArenaScreen.SIDEBAR.end.y), Look.STEEL, 1, true)
	for n in range(7):
		s.draw_rect(Rect2(ArenaScreen.SIDEBAR.position.x - 14 + n * 2, 70, 2, 730), Color(0.01, 0.03, 0.05, n * 0.025))
	var active := Arena.modal.is_empty() and Arena.sim != null and not Arena.sim.done
	_draw_box_button(BOX_BUTTON)
	_draw_command_button(Rect2(1148, 130, 118, 40), _tr("talents"), _tr("level_n") % Arena.level, "talents", active)
	_draw_command_button(Rect2(1148, 176, 118, 40), _tr("bench"), str(Arena.bench.size()), "bench", active)
	for i in range(Balance.ARENA_HERO_LIMIT):
		var rect := Rect2(ArenaScreen.HERO_X + (i % 2) * (ArenaScreen.HERO_W + ArenaScreen.HERO_GAP), ArenaScreen.HERO_Y + (i / 2) * (ArenaScreen.HERO_H + 9), ArenaScreen.HERO_W, ArenaScreen.HERO_H)
		if i < Arena.heroes.size():
			_draw_hero_card(rect, Arena.heroes[i], i == Arena.selected)
			s.ui.zone(rect.grow(3), "hero:%d" % i, active)
		else:
			_draw_empty_slot(rect, i)
	var sim = Arena.sim
	for i in range(SKILLS.size()):
		_draw_skill_button(Rect2(SKILL_ORIGIN + Vector2(0, i * SKILL_PITCH), SKILL_SIZE), String(SKILLS[i]), i, sim)

## An empty guardian slot (B3): a socket waiting for a hero — darker than the cards and sunk
## into the rail, a dashed frame, a plinth and the faint outline of who will stand on it, the
## slot's number and 「빈 자리」. Nothing on it says "press": no lit rim, no glass light, and its
## zone never answers. It shares no shape with a skill (star, snowflake, shield), an element
## (circle), a body (square) or a grade (stars). Its lines are built once per slot and drawn in
## a handful of calls (the rail is drawn every frame).
func _draw_empty_slot(rect: Rect2, index: int) -> void:
	s.ui.zone(rect.grow(3), "hero:empty", false)
	var shape := _slot_shape(rect)
	s.draw_rect(rect, Color(0.012, 0.032, 0.05, 0.80))
	Look.gradient_rect(s, Rect2(rect.position, Vector2(rect.size.x, 16)), Color(0, 0, 0, 0.40), Color(0, 0, 0, 0.0), true)
	s.draw_multiline(shape["dashes"], Color(Look.STEEL_DIM, 0.42), 1.2)
	var ghost := Color(Look.STEEL_DIM, 0.30)
	s.draw_polyline(shape["head"], ghost, 1.4, true)
	s.draw_polyline(shape["shoulders"], ghost, 1.4, true)
	s.draw_colored_polygon(shape["top"], Color(0.05, 0.10, 0.13, 0.85))
	s.draw_polyline(shape["top"], Color(Look.STEEL_DIM, 0.55), 1.3, true)
	s.draw_polyline(shape["front"], Color(Look.STEEL_DIM, 0.35), 1.3, true)
	Look.text_box(s, Rect2(rect.position + Vector2(8, 5), Vector2(24, 22)), str(index + 1), 15, Look.INK_MUTE, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(s, Rect2(rect.position.x + 8, rect.end.y - 31, rect.size.x - 16, 24), _tr("empty_slot"), 16, Look.INK_MUTE)

var _slot_shapes: Dictionary = {}

## The empty slot's lines for one rect: the dashed frame (segment pairs for draw_multiline), the
## head and shoulders, the plinth's top and its front (with its two sides).
func _slot_shape(rect: Rect2) -> Dictionary:
	var key := str(rect)
	if _slot_shapes.has(key): return _slot_shapes[key]
	var frame := rect.grow(-3.0)
	var dashes := PackedVector2Array()
	var corners := [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]
	for side in range(4):
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var along := (b - a) / maxf(0.001, length)
		var at := 0.0
		while at < length:
			dashes.append(a + along * at)
			dashes.append(a + along * minf(length, at + 5.0))
			at += 9.0
	var cx := rect.get_center().x
	var base := Vector2(cx, rect.position.y + 74.0)
	var head := PackedVector2Array()
	for n in range(25):
		head.append(Vector2(cx, base.y - 40.0) + Vector2.from_angle(TAU * float(n) / 24.0) * 8.5)
	var shoulders := PackedVector2Array()
	for n in range(13):
		var a := PI + PI * float(n) / 12.0
		shoulders.append(Vector2(cx, base.y - 6.0) + Vector2(cos(a) * 18.0, sin(a) * 19.0))
	var top := PackedVector2Array()
	for n in range(25):
		var a := TAU * float(n) / 24.0
		top.append(base + Vector2(cos(a) * 29.0, sin(a) * 7.5))
	var front := PackedVector2Array([base + Vector2(29, 0)])
	for n in range(13):
		var a := PI * float(n) / 12.0
		front.append(base + Vector2(cos(a) * 29.0, sin(a) * 7.5 + 7.0))
	front.append(base + Vector2(-29, 0))
	var shape := {"dashes": dashes, "head": head, "shoulders": shoulders, "top": top, "front": front}
	_slot_shapes[key] = shape
	return shape

## The jewel box on the rail (F10): the box itself small, its name, and what opening one costs
## now (the stage's first box is free) or why it cannot open — a wave is on (「정비 시간에」:
## boxes open in the preparation), the gold is short (the price turns warm), every hero is at
## the top grade. While it can open it breathes, slower than a ready skill.
func _draw_box_button(rect: Rect2) -> void:
	var block := Arena.summon_block()
	var on := block.is_empty()
	s.ui.zone(rect, "summon", on)
	var down := on and s.ui.pressed == "summon"
	if on:
		var face := Color("#142e3f").lerp(Look.GOLD, 0.14)
		face.a = 0.84 if down else 0.74
		if down: face = face.lightened(0.10)
		Look.glass_panel(s, rect, Look.GOLD, face, true)
		if not s._settled():
			var breath := 0.5 + 0.5 * sin(s.t * TAU / 3.4)
			_rim(rect.grow(2.0), Color(Look.GOLD, 0.08 + 0.14 * breath), 2.0)
	else:
		Look.glass_panel(s, rect, Color("#405461"), Color(0.05, 0.12, 0.17, 0.72), false)
	var shift := Vector2(0, 1.0) if down else Vector2.ZERO
	_draw_box_icon(Rect2(rect.position + Vector2(5, 3) + shift, Vector2(28, 20)), on)
	# The rail's command buttons share one type: the title in a 21 px row (14 px), the value
	# in a 20 px row (13 px — RefugeSans needs 18.8 px at 13).
	var title_box := Rect2(rect.position + Vector2(35, 1) + shift, Vector2(rect.size.x - 39, 21))
	var value_box := Rect2(rect.position + Vector2(4, 20) + shift, Vector2(rect.size.x - 8, 20))
	var label := ""
	var ink := Look.INK_MUTE
	match block:
		"wave": label = _tr("box_wave")
		"pool": label = _tr("box_maxed")
	if not label.is_empty():
		Look.text_box(s, title_box, _tr("box_title"), 16, Look.INK_MUTE, HORIZONTAL_ALIGNMENT_LEFT)
		if Look.fit_size(label, 13, value_box.size) >= 12:
			Look.text_box(s, value_box, label, 13, ink)
		else:
			# A label too long for one row at a readable size takes both rows beside the box,
			# set tighter than wrap_text's leading so two 12 px lines fit the 40 px button.
			var lines := Look.wrapped_lines(label, title_box.size.x, 12)
			if lines.size() == 2:
				s.draw_rect(Rect2(title_box.position.x - 1, rect.position.y + 2, title_box.size.x + 1, rect.size.y - 4), Color(0.05, 0.12, 0.17, 0.96))
				Look.text_box(s, Rect2(title_box.position.x, rect.position.y + 2, title_box.size.x, 18), lines[0], 12, ink, HORIZONTAL_ALIGNMENT_LEFT)
				Look.text_box(s, Rect2(title_box.position.x, rect.position.y + 19, title_box.size.x, 18), lines[1], 12, ink, HORIZONTAL_ALIGNMENT_LEFT)
			else:
				Look.text_box(s, value_box, label, 13, ink)
		return
	Look.text_box(s, title_box, _tr("box_title"), 16, Look.INK if on else Look.INK_MUTE, HORIZONTAL_ALIGNMENT_LEFT)
	if Arena.summon_count == 0 and block != "gold":
		Look.text_box(s, value_box, _tr("box_free"), 13, Look.GOLD if on else Look.INK_MUTE)
		return
	var price := "%d G" % Arena.summon_cost()
	var price_ink := Look.GOLD
	var coin_alpha := 1.0
	if block == "gold":
		price_ink = Look.WARN
		coin_alpha = 0.6
	elif not on:
		price_ink = Look.INK_MUTE
		coin_alpha = 0.45
	var price_w := Look.text_width(price, 13)
	var x := value_box.get_center().x - (price_w + 14.0) * 0.5
	_draw_coin(Vector2(x + 5.0, value_box.get_center().y), 5.5, coin_alpha)
	Look.text_left(s, Vector2(x + 14.0, value_box.get_center().y), price, 13, price_ink)

## The box's own render (D1, art/ui/box), cropped to its silhouette once and sampled smoothly
## through its mipmaps; a drawn chest when the render is missing.
func _draw_box_icon(rect: Rect2, lit: bool) -> void:
	if _box_icon.is_empty():
		_box_icon = {"tex": null}
		var source: Texture2D = ResourceLoader.load(BOX_ICON_PATH) if ResourceLoader.exists(BOX_ICON_PATH) else null
		if source != null:
			var image := source.get_image()
			if image != null and not image.is_empty():
				if image.is_compressed(): image.decompress()
				var smooth := CanvasTexture.new()
				smooth.diffuse_texture = source
				smooth.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				_box_icon = {"tex": smooth, "src": Rect2(image.get_used_rect())}
	var tint := Color.WHITE if lit else Color(0.55, 0.60, 0.64, 0.75)
	if _box_icon["tex"] != null:
		var src: Rect2 = _box_icon["src"]
		s.draw_texture_rect_region(_box_icon["tex"], Art.fit_rect(src.size, rect), src, tint)
		return
	# A chest: body, lid, a gem on the lock.
	var body := Rect2(rect.position.x + 3, rect.position.y + rect.size.y * 0.45, rect.size.x - 6, rect.size.y * 0.55)
	var lid := Rect2(body.position.x, rect.position.y + 2, body.size.x, rect.size.y * 0.43)
	s.draw_rect(body, Color(Look.GOLD_DEEP, tint.a))
	s.draw_rect(lid, Color(Look.GOLD, tint.a))
	s.draw_line(Vector2(body.position.x, body.position.y), Vector2(body.end.x, body.position.y), Color(Look.BG_DEEP, tint.a), 1.5)
	_draw_diamond(Vector2(body.get_center().x, body.position.y), 3.5, Color(Look.CRYSTAL, tint.a))

## A common skill on the rail (O2 · F5 · F6): the medallion with its glyph, the name, what the
## skill is doing now, its price (the coin and the number, like the jewel box's) and the casts
## left in this stage. ArenaSim.skill_state is the one judge: 「준비 완료」 and the ready look
## (a breathing rim, a lit glyph, now and then a shimmer, and one pop the moment it turns ready)
## only when a press really casts. Every other state has its own look: a dark sweep over the
## medallion and the seconds while it cools, the price warm and no press without the gold, a
## quiet word with no target or in a preparation, all pips hollow once spent; nothing at the
## stage's clear beat. The armed starfall's button stays down, latched, with the aim's ring
## round its medallion and 「다시 눌러 취소」.
func _draw_skill_button(rect: Rect2, id: String, index: int, sim) -> void:
	var state := _skill_state(sim, id)
	var block := String(state.get("block", "inactive"))
	var ready := block.is_empty()
	var aiming := id == "blast" and _aiming()
	var tint: Color = SKILL_TINT[id]
	var cooling := float(state.get("cooldown", 0.0))
	var warding: bool = id == "ward" and sim != null and sim.shield > 0
	var settled := s._settled()
	var on := ready or aiming
	var zone_id := "skill:" + id
	s.ui.zone(rect, zone_id, on)
	var down := on and s.ui.pressed == zone_id
	var age := _ready_age(id, ready)
	var popping := ready and not settled and age >= 0.0 and age < READY_POP
	if aiming:
		Look.glass_panel(s, rect, Look.AIM_GOLD, Color(0.15, 0.10, 0.025, 0.94), true)
		# Pressed in: a shadow under its top edge.
		Look.gradient_rect(s, Rect2(rect.position + Vector2(5, 2), Vector2(rect.size.x - 10, 11)), Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.0), true)
	elif ready:
		var face := Color("#142e3f").lerp(tint, 0.16)
		face.a = 0.86 if down else 0.78
		if down: face = face.lightened(0.10)
		Look.glass_panel(s, rect, tint, face, true)
		var breath := 0.6 if settled else 0.5 + 0.5 * sin((s.t / READY_BREATH + float(index) / 3.0) * TAU)
		_rim(rect.grow(2.0), Color(tint, 0.10 + 0.17 * breath), 2.0)
		if not settled and not popping:
			var cycle := fposmod(s.t + float(index) * READY_SWEEP_EVERY / 3.0, READY_SWEEP_EVERY)
			if cycle < READY_SWEEP: _sweep(rect, cycle / READY_SWEEP, Color(1, 1, 1, 0.12))
	else:
		Look.glass_panel(s, rect, Color("#405461"), Color(0.05, 0.12, 0.17, 0.72), false)
	if popping:
		var p := age / READY_POP
		_rim(rect.grow(2.0 + 4.0 * _ease_out(p)), Color(tint.lightened(0.35), 0.70 * (1.0 - p)), 2.0)
		if age < 0.45: _sweep(rect, age / 0.45, Color(1, 1, 1, 0.24))
	var shift := Vector2(0, 1.5) if aiming or down else Vector2.ZERO
	var center := Vector2(rect.position.x + 30, rect.get_center().y) + shift
	_draw_medallion(center, id, tint, block, aiming, cooling, float(state.get("max_cooldown", 0.0)), warding, sim, age, popping, settled)
	var text_x := rect.position.x + 60.0
	# Look.text_box fits both axes (RefugeSans is 1.45 x its size tall): a 25 px row holds the
	# name at 17 px, a 22 px row the state at 15 px — 「준비 완료」 reads at a glance.
	Look.text_box(s, Rect2(Vector2(text_x, rect.position.y + 3) + shift, Vector2(126, 25)), _tr("skill." + id), 17, Look.INK if on else Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	var status := ""
	var status_ink := Look.INK_MUTE
	if aiming:
		status = _tr("skill_cancel_hint")
		status_ink = Look.AIM_GOLD
	elif warding:
		status = "%.1f" % sim.shield_t
		status_ink = Look.CRYSTAL
	else:
		match block:
			"":
				status = _tr("ready")
				status_ink = tint.lightened(0.18)
			"cooldown":
				status = "%.1f" % maxf(0.1, cooling)
				status_ink = Look.INK
			"gold":
				status = _tr("need_gold")
				status_ink = Look.WARN
			"no_target": status = _tr("no_target")
			"prep": status = _tr("skill_prep")
			"spent":
				status = _tr("skill_spent")
				status_ink = Look.RED.lerp(Look.INK_DIM, 0.35)
	_draw_cost(Vector2(rect.end.x - 10, rect.position.y + 16) + shift, int(state.get("cost", 0)), block)
	# The casts left first: the state's words keep clear of their pips.
	var uses_left := _draw_uses(Rect2(Vector2(rect.end.x - 74, rect.position.y + 30) + shift, Vector2(64, 18)), int(state.get("uses_left", 0)), int(state.get("uses_max", 0)), tint, block == "spent")
	if not status.is_empty():
		var status_w := minf(126.0, uses_left - 7.0 - (text_x + shift.x))
		Look.text_box(s, Rect2(Vector2(text_x, rect.position.y + 28) + shift, Vector2(status_w, 22)), status, 15, status_ink, HORIZONTAL_ALIGNMENT_LEFT)

## The skill's medallion: a dark well, its glyph (lit when ready, quiet otherwise), and what
## runs on it — the cooldown as a dark sweep that uncovers the glyph clockwise with a lit rim
## behind it, the ward's shield time as a ring round it, the armed aim's ring and ticks, the
## ready pop (a ring leaving it, a flash, the glyph landing from larger).
func _draw_medallion(c: Vector2, id: String, tint: Color, block: String, aiming: bool, cooling: float,
		cool_max: float, warding: bool, sim, age: float, popping: bool, settled: bool) -> void:
	var r := 21.0
	var lit := block.is_empty() or aiming
	s.draw_circle(c, r + 1.5, Color(0.0, 0.015, 0.03, 0.66), true, -1, true)
	if lit:
		s.draw_circle(c, r, Color(tint, 0.14), true, -1, true)
		s.draw_circle(c, r * 0.6, Color(tint, 0.10), true, -1, true)
	var ink: Color = tint.lightened(0.20) if lit else Color(tint.lerp(Look.INK_MUTE, 0.55), 0.72)
	if block == "spent": ink = Look.STEEL_DIM
	elif block in ["gold", "no_target", "prep"]: ink = Color(tint.lerp(Look.INK_MUTE, 0.35), 0.82)
	var grow := 1.0
	if popping and age < 0.32: grow = 1.0 + 0.32 * (1.0 - _ease_out(age / 0.32))
	if grow > 1.001:
		s.draw_set_transform(c * (1.0 - grow), 0, Vector2(grow, grow))
		_draw_skill_icon(c, id, 15, ink)
		s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		_draw_skill_icon(c, id, 15, ink)
	s.draw_arc(c, r + 1.0, 0, TAU, 40, Color(tint, 0.85 if lit else 0.26), 1.4, true)
	if block == "cooldown" and not warding and cool_max > 0.0:
		var left := clampf(cooling / cool_max, 0.0, 1.0)
		var turned := -PI * 0.5 + TAU * (1.0 - left)
		_pie(c, r + 0.5, turned, PI * 1.5, Color(0.0, 0.02, 0.04, 0.60))
		if left < 1.0:
			s.draw_arc(c, r + 1.0, -PI * 0.5, turned, 40, Color(tint, 0.90), 2.4, true)
		s.draw_line(c, c + Vector2.from_angle(turned) * r, Color(tint, 0.50), 1.2, true)
	if warding:
		# The ward's active seconds drain as a ring round the medallion (its cooldown waits).
		var k := clampf(sim.shield_t / maxf(0.001, Balance.ARENA_WARD_DURATION), 0.0, 1.0)
		s.draw_arc(c, r + 3.5, 0, TAU, 48, Color(tint, 0.22), 3, true)
		s.draw_arc(c, r + 3.5, -PI / 2, -PI / 2 + TAU * k, 48, Look.CRYSTAL, 3, true)
	if aiming:
		# The aim's ring round the medallion: the ground ring's solid edge and its eight arrowheads.
		var spin := 0.0 if settled else s.t * 0.9
		s.draw_arc(c, r + 1.5, 0, TAU, 40, Look.AIM_GOLD, 2.2, true)
		_draw_arrowheads(c, r + 3.0, 4.2, 2.3, spin, Look.AIM_GOLD)
	if popping:
		var p := age / READY_POP
		s.draw_arc(c, r + 2.0 + 20.0 * _ease_out(p), 0, TAU, 48, Color(tint.lightened(0.35), 0.85 * (1.0 - p)), 1.0 + 2.6 * (1.0 - p), true)
		if age < 0.25: s.draw_circle(c, r, Color(1, 1, 1, 0.50 * (1.0 - age / 0.25)), true, -1, true)

## A sector of a disc from angle `from` to `to` (radians, clockwise on screen), drawn as convex
## slices so any sweep triangulates.
func _pie(c: Vector2, r: float, from: float, to: float, color: Color) -> void:
	var a := from
	while to - a > 0.01:
		var b := minf(to, a + PI * 0.5)
		var points := PackedVector2Array([c])
		var steps := maxi(2, ceili((b - a) / 0.2))
		for n in range(steps + 1):
			points.append(c + Vector2.from_angle(lerpf(a, b, float(n) / float(steps))) * r)
		s.draw_colored_polygon(points, color)
		a = b

## A skill's price, said like the jewel box's: the coin and the number. Warm when the gold is
## short now, quieter while the skill waits for something else, muted once it is spent.
func _draw_cost(at: Vector2, cost: int, block: String) -> void:
	var number := str(cost)
	var ink := Look.GOLD
	var coin_alpha := 1.0
	if block == "spent":
		ink = Look.INK_MUTE
		coin_alpha = 0.45
	elif Arena.gold < cost:
		ink = Look.WARN
		coin_alpha = 0.65
	elif not block.is_empty():
		ink = Look.GOLD.lerp(Look.INK_DIM, 0.40)
		coin_alpha = 0.75
	var width := Look.text_width(number, 17)
	Look.text_right(s, at, number, 17, ink)
	_draw_coin(Vector2(at.x - width - 10.0, at.y), 7.0, coin_alpha)

## Casts left in this stage: "2/6" and one pip per cast to its left (filled while left, hollow
## once used), so the count reads at a glance; more than eight casts keep only the numbers.
## Returns the left edge of what it drew.
func _draw_uses(rect: Rect2, uses: int, limit: int, color: Color, spent: bool) -> float:
	if limit <= 0: return rect.end.x
	var ink: Color = Look.RED.lerp(Look.INK_DIM, 0.35) if spent else Look.INK_DIM
	var text := "%d/%d" % [uses, limit]
	var text_w := Look.text_width(text, 13)
	var y := rect.get_center().y
	Look.text_right(s, Vector2(rect.end.x, y), text, 13, ink)
	if limit > 8: return rect.end.x - text_w
	var room := rect.size.x - text_w - 5.0
	var pitch := minf(7.0, room / float(limit))
	var start := rect.end.x - text_w - 5.0 - pitch * (float(limit) - 0.5)
	for n in range(limit):
		var at := Vector2(start + float(n) * pitch, y)
		if n < uses: _draw_diamond(at, 3.4, color)
		else: s.draw_polyline(PackedVector2Array([at + Vector2(0, -3.4), at + Vector2(2.3, 0), at + Vector2(0, 3.4), at + Vector2(-2.3, 0), at + Vector2(0, -3.4)]), Color(ink, 0.65), 1.0, true)
	return start - 3.0

## What the simulator says about a skill (ArenaSim.skill_state): one dictionary for the button.
func _skill_state(sim, id: String) -> Dictionary:
	if sim != null and sim.has_method("skill_state"):
		return sim.skill_state(id)
	return {"block": "inactive", "cooldown": 0.0, "max_cooldown": 0.0, "uses_left": 0, "uses_max": 0, "cost": 0, "ready": false}

## Seconds since the skill became ready (-1 while it is not): the screen's clock when it keeps
## one (skill_ready_age), else this view's memory. A skill already ready when first seen never
## pops.
func _ready_age(id: String, ready: bool) -> float:
	if s.has_method("skill_ready_age"):
		return float(s.skill_ready_age(id))
	var was := bool(_ready_seen.get(id, ready))
	if ready and not was: _ready_t0[id] = s.t
	_ready_seen[id] = ready
	return s.t - float(_ready_t0.get(id, -100.0)) if ready else -1.0

## The glass panel's chamfered outline grown by its rect: a ready button's breathing rim.
func _rim(rect: Rect2, color: Color, width: float, cut: float = 6.0) -> void:
	var p := rect.position
	var e := rect.end
	s.draw_polyline(PackedVector2Array([p + Vector2(cut, 0), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut),
		Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut),
		Vector2(p.x, p.y + cut), p + Vector2(cut, 0)]), color, width, true)

## A slanted band of light crossing a button left to right (`phase` 0..1), kept on its face.
func _sweep(rect: Rect2, phase: float, color: Color) -> void:
	var x := lerpf(rect.position.x - 34.0, rect.end.x + 34.0, phase)
	var top := rect.position.y + 3.0
	var bottom := rect.end.y - 3.0
	var lo := rect.position.x + 4.0
	var hi := rect.end.x - 4.0
	var lean := 12.0
	var half := 15.0
	var clear := Color(color, 0.0)
	var a := Vector2(clampf(x - half + lean, lo, hi), top)
	var b := Vector2(clampf(x + lean, lo, hi), top)
	var c := Vector2(clampf(x + half + lean, lo, hi), top)
	var d := Vector2(clampf(x + half - lean, lo, hi), bottom)
	var e := Vector2(clampf(x - lean, lo, hi), bottom)
	var f := Vector2(clampf(x - half - lean, lo, hi), bottom)
	if maxf(b.x, e.x) - minf(a.x, f.x) > 1.0 and absf(b.x - a.x) + absf(e.x - f.x) > 1.0:
		s.draw_polygon(PackedVector2Array([a, b, e, f]), PackedColorArray([clear, color, color, clear]))
	if maxf(c.x, d.x) - minf(b.x, e.x) > 1.0 and absf(c.x - b.x) + absf(d.x - e.x) > 1.0:
		s.draw_polygon(PackedVector2Array([b, c, d, e]), PackedColorArray([color, clear, clear, color]))

func _draw_command_button(rect: Rect2, title: String, value: String, id: String, active: bool) -> void:
	s.ui.glass_button(s, rect, "", id, active)
	var color := Look.INK if active else Look.INK_MUTE
	Look.text_box(s, Rect2(rect.position + Vector2(4, 1), Vector2(rect.size.x - 8, 21)), title, 17, color)
	Look.text_box(s, Rect2(rect.position + Vector2(4, 20), Vector2(rect.size.x - 8, 20)), value, 13, Look.GOLD if active else color)

func _draw_joystick() -> void:
	if s._joy_pointer == -99 or not Arena.modal.is_empty() or s._menu_open(): return
	s.draw_circle(s.joy_origin + Vector2(0, 3), ArenaScreen.JOY_RADIUS + 6, Color(0, 0, 0, 0.38))
	s.draw_circle(s.joy_origin, ArenaScreen.JOY_RADIUS + 4, Color(0.3, 0.54, 0.65, 0.45))
	s.draw_circle(s.joy_origin, ArenaScreen.JOY_RADIUS + 1, Color(0.02, 0.07, 0.11, 0.24))
	s.draw_circle(s.joy_origin, ArenaScreen.JOY_RADIUS - 3, Color(0.11, 0.24, 0.31, 0.18))
	s.draw_circle(s.joy_origin, ArenaScreen.JOY_RADIUS - 9, Color(0.025, 0.095, 0.15, 0.12))
	s.draw_arc(s.joy_origin, ArenaScreen.JOY_RADIUS + 2, PI * 1.05, TAU * 0.99, 48, Color("#91c7d9"), 1.4, true)
	s.draw_arc(s.joy_origin, ArenaScreen.JOY_RADIUS - 7, 0, TAU, 64, Color(0.41, 0.64, 0.73, 0.35), 1, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var at: Vector2 = s.joy_origin + d * 48
		var normal := Vector2(-d.y, d.x)
		s.draw_colored_polygon(PackedVector2Array([at + d * 6, at - d * 3 + normal * 4, at - d * 3 - normal * 4]), Color("#b8ddea"))
	var stick := s.joy_origin + s.joystick * 36
	s.draw_circle(stick + Vector2(0, 3), 28, Color(0, 0, 0, 0.30))
	s.draw_circle(stick, 28, Look.GOLD if s._joy_pointer != -99 else Look.STEEL)
	s.draw_circle(stick, 26, Color("#284d60"))
	s.draw_circle(stick + Vector2(-3, -4), 21, Color(0.25, 0.48, 0.58, 0.42))
	s.draw_line(stick + Vector2(-15, -15), stick + Vector2(15, 15), Color(0.62, 0.85, 0.9, 0.13), 1, true)
	s.draw_line(stick + Vector2(15, -15), stick + Vector2(-15, 15), Color(0.62, 0.85, 0.9, 0.13), 1, true)

func _draw_hero_card(rect: Rect2, hero: Dictionary, selected: bool) -> void:
	var unit: Dictionary = hero["unit"]
	var tier := int(hero["tier"])
	var element := String(unit.get("elem", "none"))
	var edge := Look.GOLD if selected else Balance.elem_color(element).lerp(Look.STEEL, 0.60)
	Look.glass_panel(s, rect, edge, Color(0.018, 0.04, 0.065, 0.93), selected)
	var picture := _portrait(unit, tier)
	if not picture.is_empty():
		# Alpha bounds remove empty studio margins before a native upper-body crop.
		var crop: Rect2 = picture["crop"]
		var target := Rect2(rect.position + Vector2(5, 20), Vector2(rect.size.x - 10, rect.size.y - 29))
		s.draw_texture_rect_region(picture["tex"], Art.fit_rect(crop.size, target), crop)
	for n in range(9):
		s.draw_rect(Rect2(rect.position.x + 4, rect.end.y - 38 + n * 4, rect.size.x - 8, 4), Color(0.018, 0.035, 0.055, 0.18 + n * 0.088))
	Look.text_box(s, Rect2(rect.position.x + 5, rect.end.y - 30, rect.size.x - 10, 27), Look.unit_name(unit), 20, Look.INK)
	Look.fill_round(s, Rect2(rect.position + Vector2(4, 4), Vector2(rect.size.x - 8, 20)), 2, Color(0.008, 0.017, 0.03, 0.90))
	Look.draw_elem(s, rect.position + Vector2(14, 14), 8, element)
	# Guns and bows reach flying monsters: the mark sits at the end of the rank row.
	var air := Balance.anti_air(unit)
	Look.draw_rarity_fit(s, Rect2(rect.position + Vector2(27, 4), Vector2(rect.size.x - 34 - (18.0 if air else 0.0), 20)), tier, 5.2)
	if air: Look.draw_anti_air(s, Vector2(rect.end.x - 14, rect.position.y + 14), 7.0)
	if selected:
		Look.draw_brackets(s, rect.grow(2), 13, Look.GOLD.lightened(0.25), 2)
		var badge := rect.position + Vector2(rect.size.x - 24, 29)
		Look.fill_round(s, Rect2(badge, Vector2(18, 18)), 2, Look.GOLD)
		s.draw_line(badge + Vector2(4, 9), badge + Vector2(8, 13), Look.BG_DEEP, 2)
		s.draw_line(badge + Vector2(8, 13), badge + Vector2(15, 5), Look.BG_DEEP, 2)

func _draw_minimap() -> void:
	if Arena.sim == null: return
	Look.glass_panel(s, ArenaScreen.MINIMAP, Look.STEEL, Color(0.015, 0.055, 0.085, 0.79))
	var map := Rect2(ArenaScreen.MINIMAP.get_center() - Vector2.ONE * 54, Vector2.ONE * 108)
	var perimeter := PackedVector2Array()
	for point in ArenaGeometry.outline(): perimeter.append(s.view_3d.minimap_point(point, map))
	s.draw_colored_polygon(perimeter, Color(0.08, 0.20, 0.25, 0.30))
	s.draw_polyline(perimeter + PackedVector2Array([perimeter[0]]), Color(0.55, 0.77, 0.84, 0.59), 1.1, true)
	# Every road of the current layout, each drawn once at its true width.
	var width := ArenaGeometry.ROAD_WIDTH / (ArenaGeometry.RADIUS * 2) * map.size.x
	for polyline in ArenaGeometry.road_polylines():
		var road := PackedVector2Array()
		for point in polyline: road.append(s.view_3d.minimap_point(point, map))
		s.draw_polyline(road, Color(0.56, 0.68, 0.68, 0.27), width, true)
		s.draw_polyline(road, Color(0.78, 0.86, 0.82, 0.19), 1, true)
	# Every entrance of this battlefield, so a new layout reads before the first monster:
	# a dart on the rim pointing in, rimmed dark so it holds on the road's pale stone.
	for lane in range(ArenaGeometry.route_count()):
		var gate := s.view_3d.minimap_point(ArenaGeometry.gate_point(lane, 4.0), map)
		s.cards._draw_gate_dart(gate + (map.get_center() - gate).normalized() * 7.0, (map.get_center() - gate).normalized(), 10.5, 5.0)
	# The camera footprint only matters while it is smaller than the whole field.
	var footprint := s.view_3d.minimap_footprint(map)
	if footprint.size() >= 3 and _polygon_area(footprint) < _polygon_area(perimeter) * 0.985:
		s.draw_colored_polygon(footprint, Color(0.27, 0.69, 0.82, 0.07))
		s.draw_polyline(footprint + PackedVector2Array([footprint[0]]), Color(0.60, 0.84, 0.90, 0.57), 1, true)
	for mo in Arena.sim.monsters:
		if float(mo.get("hp", 0)) <= 0: continue
		var at := s.view_3d.minimap_point(mo["pos"], map)
		var boss := String(mo.get("kind", "")) == "boss"
		if boss:
			s.draw_circle(at, 5.5, Color(0.98, 0.3, 0.24, 0.15))
			_draw_diamond(at, 4, MAP_BOSS)
		else: s.draw_circle(at, 2.0, Look.GATE_MARK)
	for i in range(Arena.sim.heroes.size()):
		var at := s.view_3d.minimap_point(Arena.sim.heroes[i]["pos"], map)
		if i == Arena.selected:
			s.draw_arc(at, 4.2, 0, TAU, 18, Look.IVORY, 1, true)
			s.draw_circle(at, 2.4, Look.GOLD)
		else: s.draw_circle(at, 2, MAP_ALLY)
	var crystal := s.view_3d.minimap_point(Balance.ARENA_CENTER, map)
	_draw_diamond(crystal, 4, Look.CRYSTAL)
	s.draw_circle(crystal, 1, Color.WHITE)
	# Warned boss gate: a pulsing ring marks the entrance until the boss diamond takes over.
	if Arena.sim.boss_warned and not Arena.sim.boss_spawned:
		var gate: Vector2 = Arena.sim.boss_gate()
		if gate.is_finite():
			var at := s.view_3d.minimap_point(gate, map)
			var pulse := 0.5 + 0.5 * sin(s.t * 9.0)
			s.draw_circle(at, 7, Color(1.0, 0.42, 0.36, 0.10 + pulse * 0.12))
			s.draw_arc(at, 5 + pulse * 3, 0, TAU, 20, Look.WARN, 1.5, true)
			_draw_diamond(at, 3.5, Look.GOLD.lightened(0.2))
	# Compass tick uses a shape, avoiding another language-dependent HUD label.
	s.draw_colored_polygon(PackedVector2Array([Vector2(ArenaScreen.MINIMAP.get_center().x, ArenaScreen.MINIMAP.position.y + 2), Vector2(ArenaScreen.MINIMAP.get_center().x - 3, ArenaScreen.MINIMAP.position.y + 7), Vector2(ArenaScreen.MINIMAP.get_center().x + 3, ArenaScreen.MINIMAP.position.y + 7)]), Look.STEEL)

func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5

func _draw_diamond(at: Vector2, radius: float, color: Color) -> void:
	s.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.67, 0), at + Vector2(0, radius), at + Vector2(-radius * 0.67, 0)]), color)

func _draw_hud_crystal(at: Vector2) -> void:
	var top := at + Vector2(0, -24)
	var left := at + Vector2(-13, -3)
	var right := at + Vector2(13, -3)
	var bottom := at + Vector2(0, 24)
	var core := at + Vector2(-1, 3)
	var high := at + Vector2(3, -8)
	for n in range(3): s.draw_circle(at, 20 - n * 3, Color(0.19, 0.74, 0.93, 0.032))
	s.draw_colored_polygon(PackedVector2Array([top, left, high]), Color("#c8faff"))
	s.draw_colored_polygon(PackedVector2Array([top, high, right]), Color("#31b9e1"))
	s.draw_colored_polygon(PackedVector2Array([left, core, high]), Color("#278ab8"))
	s.draw_colored_polygon(PackedVector2Array([right, high, core]), Color("#83f0ff"))
	s.draw_colored_polygon(PackedVector2Array([left, bottom, core]), Color("#1769a7"))
	s.draw_colored_polygon(PackedVector2Array([right, core, bottom]), Color("#51cdec"))
	s.draw_polyline(PackedVector2Array([top, left, bottom, right, top]), Color("#9aeeff"), 1, true)
	s.draw_line(top, core, Color("#b9f5ff"), 1, true)
	s.draw_line(core, bottom, Color("#a6f1ff"), 1, true)

## The gold coin (the gold counter, prices, bounties). Its strokes follow the radius, so a small
## coin beside a skill's price keeps its marks inside.
func _draw_coin(at: Vector2, radius: float, alpha: float = 1.0) -> void:
	var k := radius / 9.0
	s.draw_circle(at, radius + 1, Color("#7e653b", alpha))
	s.draw_circle(at, radius, Color("#dcad51", alpha))
	s.draw_arc(at, radius - 3.0 * k, 0, TAU, 28, Color(Look.STARLIGHT, alpha), maxf(1.0, 1.2 * k), true)
	s.draw_line(at + Vector2(-2, -7) * k, at + Vector2(-5, 6) * k, Color("#ffedb0", alpha), maxf(1.2, 2.0 * k), true)
	s.draw_line(at + Vector2(3, -7) * k, at + Vector2(0, 6) * k, Color("#805d2d", alpha), maxf(1.2, 2.0 * k), true)

func _draw_skill_icon(center: Vector2, id: String, radius: float, color: Color) -> void:
	if id == "blast":
		s.draw_colored_polygon(Look.star_points(center, radius, 0.4), color)
		for n in range(6):
			var d := Vector2.from_angle(n * TAU / 6)
			s.draw_line(center + d * (radius + 3), center + d * (radius + 7), color, 2)
	elif id == "freeze":
		for n in range(6):
			var d := Vector2.from_angle(n * TAU / 6)
			var normal := Vector2(-d.y, d.x)
			s.draw_line(center, center + d * radius, color, 2)
			s.draw_line(center + d * radius * 0.52, center + d * radius * 0.82 + normal * radius * 0.25, color, 2)
			s.draw_line(center + d * radius * 0.52, center + d * radius * 0.82 - normal * radius * 0.25, color, 2)
	else:
		var points := PackedVector2Array([center + Vector2(-radius, -radius * 0.75), center + Vector2(0, -radius), center + Vector2(radius, -radius * 0.75), center + Vector2(radius * 0.82, radius * 0.4), center + Vector2(0, radius), center + Vector2(-radius * 0.82, radius * 0.4)])
		s.draw_polyline(points + PackedVector2Array([points[0]]), color, 2, true)
		s.draw_line(center + Vector2(-5, 0), center + Vector2(5, 0), color, 2)
		s.draw_line(center + Vector2(0, -5), center + Vector2(0, 5), color, 2)

func _draw_monster_bars() -> void:
	if Arena.sim == null: return
	var occupied: Dictionary = {}
	for mo in Arena.sim.monsters:
		var kind := String(mo.get("kind", ""))
		var boss := kind == "boss"
		# An elite (2026-10-19, O5) is a boss in small: its bar is always up, framed and wide.
		var elite := bool(mo.get("elite", false)) and not boss
		if mo["hp"] >= mo["max"] and not bool(mo.get("blocked", false)) and not boss and not elite: continue
		var at := s.view_3d.project(mo["pos"], _monster_top(mo))
		var field := ArenaScreen.BATTLEFIELD.grow(-14)
		if boss: at = at.clamp(field.position + Vector2(44, 16), field.end - Vector2(44, 0))
		elif elite: at = at.clamp(field.position + Vector2(40, 14), field.end - Vector2(34, 0))
		if not field.has_point(at) or ArenaScreen.MINIMAP.has_point(at): continue
		var cell := Vector2i(int(at.x / 30), int(at.y / 12))
		if occupied.has(cell) and not boss and not elite: continue
		occupied[cell] = true
		var fraction := clampf(float(mo["hp"]) / maxf(1, float(mo["max"])), 0, 1)
		if boss:
			# The 2.8x boss carries a wide framed bar that reads over its own bulk.
			Look.fill_round(s, Rect2(at.x - 44, at.y - 13, 88, 13), 4, Color(0.02, 0.04, 0.06, 0.72))
			_bar(Rect2(at.x - 40, at.y - 10, 80, 7), fraction, Look.hp_color_enemy(fraction))
		elif elite:
			# The boss bar's family, smaller, framed in the elite's violet, with its crest at
			# the left end (the 3D body carries the same violet outline and aura).
			Look.fill_round(s, Rect2(at.x - 31, at.y - 12, 66, 12), 4, Color(0.035, 0.02, 0.06, 0.74))
			s.draw_rect(Rect2(at.x - 31, at.y - 12, 66, 12), Color(Look.ELITE, 0.70), false, 1.0)
			_bar(Rect2(at.x - 22, at.y - 9, 54, 6), fraction, Look.hp_color_enemy(fraction))
			_draw_elite_crest(Vector2(at.x - 30, at.y - 6), 6.0)
		else:
			# Never wider than the body it labels (26 px imp, 19 px slime): 28x4 on the
			# swarm, 36x5 on a tank, in the enemy's warm colour (2026-10-18).
			var width := 36.0 if kind == "tank" else 28.0
			var height := 5.0 if kind == "tank" else 4.0
			_bar(Rect2(at.x - width * 0.5, at.y - 7, width, height), fraction, Look.hp_color_enemy(fraction))
		if bool(mo.get("blocked", false)) and not boss and not elite:
			s.draw_line(at + Vector2(-4, -14), at + Vector2(-4, -9), Look.GOLD, 2)
			s.draw_line(at + Vector2(4, -14), at + Vector2(4, -9), Look.GOLD, 2)

## World height of a monster's visual top so its bar floats just over a 2.8x boss body
## or a small swarm body alike. Boss tops come from the actual mesh bounds (cached 0.5s).
func _monster_top(mo: Dictionary) -> float:
	var kind := String(mo.get("kind", ""))
	if kind != "boss":
		var top := 1.2 if kind == "tank" else 0.84
		var node: Node3D = s.view_3d.world.monster_node(int(mo.get("spawn_id", 0))) if s.view_3d.world != null else null
		# Any root scale on the body keeps the bar on the head (bosses measure their mesh).
		if node != null: top *= node.scale.y
		if bool(mo.get("fly", false)):
			# A flyer's body rides above the ground point; the model publishes how high.
			top += float(node.get_meta(NativeMonsterModel.FLY_META, 1.2)) if node != null else 1.2
		return top
	var sid := int(mo.get("spawn_id", 0))
	var cached: Dictionary = _boss_tops.get(sid, {})
	if not cached.is_empty() and s.t - float(cached["t"]) < 0.5: return float(cached["h"])
	var height := 3.6
	var node: Node3D = s.view_3d.world.monster_node(sid) if s.view_3d.world != null else null
	if node != null and node.is_inside_tree():
		var top := -INF
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var aabb: AABB = mesh.get_aabb()
			for corner in range(8):
				top = maxf(top, (mesh.global_transform * aabb.get_endpoint(corner)).y)
		if top > 0.5: height = top + 0.22
	_boss_tops[sid] = {"h": height, "t": s.t}
	return height

func _shade() -> void:
	s.draw_rect(Look.SCREEN, Look.SHADE)
	s.ui.zone(Look.SCREEN, "modal:block")
	Look.sheet(s, ArenaScreen.MODAL, Look.STEEL, Look.GLASS_FACE)
	Look.chip(s, Vector2(ArenaScreen.MODAL.end.x - 26, ArenaScreen.MODAL.position.y + 26), _tr("pause"), 15, Color(Look.STEEL, 0.22), Look.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)

## A 1 px light frame around a 1 px dark well around the track: the bar reads on the
## brightest road and on the night water alike without growing past the body it labels
## (the old 2 px well alone sank into dark ground and bulged over small bodies).
func _bar(rect: Rect2, value: float, color: Color) -> void:
	Look.fill_round(s, rect.grow(2), 3, Color(Look.STEEL_DIM, 0.55))
	Look.fill_round(s, rect.grow(1), 2, BAR_WELL)
	Look.fill_round(s, rect, 2, BAR_TRACK)
	var width := clampf(value, 0, 1) * rect.size.x
	if width > 0: Look.fill_round(s, Rect2(rect.position, Vector2(width, rect.size.y)), 2, color)

func _clock(value: float) -> String:
	var seconds := maxi(0, int(value))
	return "%02d:%02d" % [seconds / 60, seconds % 60]
