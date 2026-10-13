extends Node2D
class_name ArenaScreen

## The run's current battlefield, with the stage card, the ritual, growth, reserves
## and the purchase sheet over its paused world.
const FIELD := Rect2(0, 0, 1280, 800)
const BATTLEFIELD := Rect2(0, 70, 992, 730)
const SIDEBAR := Rect2(992, 70, 288, 730)
const MINIMAP := Rect2(1006, 84, 130, 132)
const JOY_RADIUS := 67.0
const HERO_X := 1006.0
const HERO_Y := 228.0
const HERO_W := 124.0
const HERO_H := 119.0
const HERO_GAP := 12.0
const MODAL := Rect2(72, 86, 1136, 676)
## Transient HUD under the top strip: the ward countdown at the left, the boss warning
## banner / boss health centred over the open battle box (x 496). Touches here never
## start the joystick (see _pointer). Battle speed chips sit in the strip left of the menu.
const SHIELD_BOX := Rect2(68, 78, 214, 46)
const BOSS_BOX := Rect2(286, 78, 420, 46)
const SPEED_BOX := Rect2(784, 16, 162, 38)
## The battlefield briefing that opens every stage (and the run). The field itself is the
## reveal, so nothing sits on the arena: the name plate hangs under the top strip (every
## gate of every layout stays clear of it), and the briefing sheet takes the command
## rail, which is idle while the card is up. docs/UI_STAGE_STORE.md has the measurements.
const STAGE_BAND := Rect2(166, 78, 660, 70)
const STAGE_PANEL := Rect2(968, 70, 312, 730)
## Stage clear / revival banners: centred over the open battle box, on the boss strip's
## row when it is free and one row lower while a boss is announced or alive.
const BANNER_SIZE := Vector2(404, 70)
## Seconds the "Guardian's blessing" banner stays after a revival.
const REVIVE_BANNER := 3.0
## The result panel's entrance, in seconds of the screen's own clock: the shade comes in,
## the last boss's banner dissolves under it, then the card rises out of the shade. Until
## the card has arrived its buttons do not answer (a thumb still on the field must not
## leave the result the moment it appears).
const RESULT_SHADE_IN := 0.18
const RESULT_BANNER_OUT := 0.14
const RESULT_CARD_AT := 0.12
const RESULT_CARD_IN := 0.26

var main = null
var ui := Ui.new()
var view_3d := ArenaView.new()
## Battle speed 1/2/3. Persists in settings like the legacy battle screen (Save.speed);
## the simulator, the 3D world and its effects all run on the scaled dt, so nothing
## presentation-side keeps real time while the battle runs faster.
var speed := 1.0
var t := 0.0
var joystick := Vector2.ZERO
var joy_origin := Vector2.ZERO
var _joy_selection := -1
var _joy_pointer := -99
var _draw_dt := 0.0
var _modal_seen := ""
var _phase_seen := -1
var store := StoreView.new()
var _revives_seen := 0
var _revive_age := 99.0
var _shop_tab := "upgrades"
var _passive_page := 0
var _bench_page := 0
var _bench_choice := -1
var _field_choice := -1
var _rite_age := 9.0
var _spin_rings: Array = []
var _card_crops: Dictionary = {}
var _boss_tops: Dictionary = {}
## Drawing-side memory of the battlefield card: when it opened (its entrance runs on
## `t`), what it lists, and the road diagram of the layout it shows.
var _card_key := ""
var _card_t0 := 0.0
var _card_draws := 0
## The crystal's health in the last picture before a stage was cleared, and how much the
## clear mended (the stage-clear banner shows it).
var _hp_seen := -1.0
var _clear_seen := false
var _clear_heal := 0.0
## The result panel's entrance: whether this screen has drawn the battle (a screen that
## opens straight onto a result shows it settled), which result it is, and when it opened.
var _field_seen := false
var _result_key := ""
var _result_t0 := -100.0
var _preview_key := ""
var _preview: Dictionary = {}
var _layout_key := ""
var _layout_shape: Dictionary = {}
func _ready() -> void:
	get_tree().process_frame.connect(_guard_joystick)
	view_3d.battle_box = BATTLEFIELD
	view_3d.minimap_box = MINIMAP
	speed = float(clampi(roundi(Save.speed), 1, 3))
	_revives_seen = Arena.sim.revives if Arena.sim != null else 0
	Store.purchase_finished.connect(_on_purchase)
	_track_modal()

func _exit_tree() -> void:
	if Store.purchase_finished.is_connected(_on_purchase):
		Store.purchase_finished.disconnect(_on_purchase)

## The blessing bought on the defeat screen revives the run that just ended.
func _on_purchase(id: String, result: String) -> void:
	if id == Store.GUARDIAN and result == "ok" and Arena.revive_from_defeat():
		store.close()
		_track_modal()
	queue_redraw()

func _process(dt: float) -> void:
	t += dt
	_rite_age += dt
	_revive_age += dt
	_track_modal()
	_draw_dt = 0.0
	if Arena.sim != null and Arena.modal.is_empty() and not _menu_open() and not store.opened:
		var sdt := dt * speed
		Arena.sim.move_selected(_ground_direction(_push()), sdt)
		Arena.sim.step(sdt)
		_draw_dt = sdt
	# The blessing revives up to Balance.ARENA_REVIVE_USES times a run; a new run starts
	# the count again, so only a count that went up is a revival to announce.
	var used: int = Arena.sim.revives if Arena.sim != null else 0
	if used != _revives_seen:
		if used > _revives_seen:
			_revive_age = 0.0
			Sfx.play("summon_burst")
		_revives_seen = used
	queue_redraw()

## Movement push in screen space: the touch stick, or the keyboard / gamepad on desktop
## (arrow keys, WASD, D-pad and left stick) while no stick is held.
func _push() -> Vector2:
	if _joy_pointer != -99: return joystick
	var keys := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_A): keys.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): keys.x += 1.0
	if Input.is_physical_key_pressed(KEY_W): keys.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): keys.y += 1.0
	return keys.limit_length(1.0)

func _menu_open() -> bool:
	return main != null and main.get("menu") != null and main.menu.opened

func _ground_direction(direction: Vector2) -> Vector2:
	if direction.length_squared() < 0.001 or view_3d.world == null: return Vector2.ZERO
	var center := BATTLEFIELD.get_center()
	var a := view_3d.ground_at(center)
	var b := view_3d.ground_at(center + direction.normalized() * 40)
	return (b - a).normalized() * minf(1.0, direction.length()) if a.is_finite() and b.is_finite() else Vector2.ZERO

func _track_modal() -> void:
	if _modal_seen == Arena.modal and _phase_seen == Arena.phase: return
	var previous := _modal_seen
	_modal_seen = Arena.modal
	_phase_seen = Arena.phase
	cancel_joystick()
	ui.pressed = ""
	if Arena.modal == "rite" and previous != "rite":
		_start_spin(range(Rite.RINGS))
		Sfx.play("flip")
		Sfx.play_music("ritual")
	elif Arena.modal != previous:
		Sfx.play_music("camp" if Arena.theme_index < 0 else "theme_" + String(Arena.theme_for(1)["id"]))
		if Arena.modal == "stage": Sfx.play("theme")
	if Arena.modal == "bench" and previous != "bench":
		_field_choice = clampi(Arena.selected, 0, maxi(0, Arena.heroes.size() - 1))
		_bench_choice = -1
		_bench_page = 0

func _start_spin(rings: Array) -> void:
	_spin_rings = rings.duplicate()
	_rite_age = 0.0

func _input(e: InputEvent) -> void:
	if _menu_open():
		cancel_joystick()
		return
	if e is InputEventMouseButton and e.device < 0: return
	if e is InputEventScreenTouch:
		_pointer(e.index, e.position, e.pressed and not e.canceled)
		return
	if e is InputEventScreenDrag:
		if e.index == _joy_pointer:
			_set_joystick(e.position)
			get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_pointer(-1, e.position, e.pressed)
		return
	if e is InputEventMouseMotion and _joy_pointer == -1:
		_set_joystick(e.position)
		get_viewport().set_input_as_handled()
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		if store.opened:
			store.close()
			get_viewport().set_input_as_handled()
		elif Arena.modal in ["shop", "bench"]:
			Arena.close_modal()
			get_viewport().set_input_as_handled()

func cancel_joystick() -> void:
	joystick = Vector2.ZERO
	_joy_pointer = -99
	_joy_selection = -1
	queue_redraw()

func _guard_joystick() -> void:
	if _joy_pointer == -99: return
	if not Arena.modal.is_empty() or store.opened or _menu_open() or Arena.sim == null or Arena.sim.done or Arena.selected != _joy_selection or not is_visible_in_tree():
		cancel_joystick()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel_joystick()

func _pointer(pointer: int, at: Vector2, pressed: bool) -> void:
	if not pressed:
		if pointer == _joy_pointer: cancel_joystick()
		ui.pressed = ""
		return
	# Buttons retain multi-touch while an existing movement finger owns its origin.
	for n in range(ui.zones.size() - 1, -1, -1):
		var zone: Dictionary = ui.zones[n]
		if not Rect2(zone["rect"]).has_point(at): continue
		if bool(zone.get("on", false)):
			ui.pressed = String(zone["id"])
			_action(ui.pressed)
		get_viewport().set_input_as_handled()
		return
	if Rect2(0, 0, 1280, 70).has_point(at) or SIDEBAR.has_point(at): return
	if Arena.sim != null and (Arena.sim.boss_spawned or Arena.sim.boss_warned) and BOSS_BOX.has_point(at): return
	if Arena.sim != null and Arena.sim.shield > 0 and SHIELD_BOX.has_point(at): return
	if not FIELD.has_point(at) or not Arena.modal.is_empty() or store.opened or Arena.sim == null or Arena.sim.done or _menu_open(): return
	if _joy_pointer != -99:
		get_viewport().set_input_as_handled()
		return
	if BATTLEFIELD.has_point(at):
		var index := view_3d.hero_at(at)
		if index >= 0:
			Arena.selected = index
			Sfx.play("button")
	joy_origin = at
	_joy_pointer = pointer
	_joy_selection = Arena.selected
	joystick = Vector2.ZERO
	queue_redraw()
	get_viewport().set_input_as_handled()

func _set_joystick(at: Vector2) -> void:
	if _joy_pointer == -99: return
	_guard_joystick()
	if _joy_pointer == -99: return
	joystick = ((at - joy_origin) / JOY_RADIUS).limit_length(1.0)
	if joystick.length() < 0.12: joystick = Vector2.ZERO
	queue_redraw()

func _action(id: String) -> void:
	if id == "modal:block": return
	if store.action(id):
		pass
	elif id.begins_with("hero:"):
		Arena.selected = int(id.get_slice(":", 1))
		cancel_joystick()
	elif id == "summon": Arena.begin_summon()
	elif id == "shop": Arena.open_modal("shop")
	elif id == "bench": Arena.open_modal("bench")
	elif id == "close": Arena.close_modal()
	elif id.begins_with("skill:"):
		Arena.sim.cast_skill(id.get_slice(":", 1))
	elif id.begins_with("speed:") and id.get_slice(":", 1).is_valid_int():
		set_speed(float(int(id.get_slice(":", 1))))
	elif id == "stage:start": Arena.confirm_stage()
	elif id == "result:guardian": store.open(Store.GUARDIAN)
	elif id == "rite:respin":
		var rings := Arena.respin()
		if not rings.is_empty():
			_start_spin(rings)
			Sfx.play("flip")
	elif id == "rite:confirm":
		Arena.confirm_summon()
		_rite_age = 9
		Sfx.play("summon_burst")
	elif id.begins_with("shop:tab:"):
		_shop_tab = id.get_slice(":", 2)
	elif id.begins_with("upgrade:"): Arena.buy_upgrade(id.get_slice(":", 1))
	elif id.begins_with("passive:") and id.get_slice(":", 1) not in ["prev", "next"]:
		var pid := id.get_slice(":", 1)
		if Arena.owns_passive(pid): Arena.toggle_passive(pid)
		else: Arena.buy_passive(pid)
	elif id == "passive:prev": _passive_page = maxi(0, _passive_page - 1)
	elif id == "passive:next": _passive_page += 1
	elif id.begins_with("bench:field:"): _field_choice = int(id.get_slice(":", 2))
	elif id.begins_with("bench:reserve:"): _bench_choice = int(id.get_slice(":", 2))
	elif id == "bench:prev": _bench_page = maxi(0, _bench_page - 1)
	elif id == "bench:next": _bench_page += 1
	elif id == "bench:swap":
		if Arena.swap_hero(_field_choice, _bench_choice): _bench_choice = -1
	elif id == "result:retry":
		Arena.start_run()
	elif id == "result:home" and main != null:
		main.go(main.show_title)
	Sfx.play("button")
	_track_modal()
	queue_redraw()

func set_speed(value: float) -> void:
	speed = float(clampi(roundi(value), 1, 3))
	Save.set_speed(speed)

func _tr(key: String) -> String:
	return Arena.label("arena." + key)

func _draw() -> void:
	ui.begin()
	draw_rect(Look.SCREEN, Look.BG_DEEP)
	var theme: Dictionary = Arena.theme_for(1)
	view_3d.draw_arena(self, FIELD, theme, Arena.sim, Arena.selected, _draw_dt)
	_draw_dt = 0.0
	_draw_monster_bars()
	_draw_topbar(theme)
	_draw_controls()
	_draw_minimap()
	_draw_joystick()
	_draw_banners()
	match Arena.modal:
		"stage": _draw_stage_card()
		"rite": _draw_rite()
		"shop": _draw_shop()
		"bench": _draw_bench()
		"result": _draw_result()
	store.draw(self, ui, t)

func _draw_topbar(theme: Dictionary) -> void:
	draw_rect(Rect2(0, 0, 1280, 69), Color(0.025, 0.065, 0.095, 0.88))
	draw_line(Vector2(0, 69), Vector2(1280, 69), Color("#84b5c5"), 1, true)
	draw_line(Vector2(0, 71), Vector2(1280, 71), Color(0.02, 0.04, 0.07, 0.55), 2)
	_draw_hud_crystal(Vector2(43, 34))
	# Left to right: crystal block, battlefield name, boss clock, gold, battle speed, then
	# the shared menu / language buttons that MenuOverlay draws from x 958.
	Look.text_box(self, Rect2(76, 8, 200, 30), _tr("title"), 25, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	for x in [337, 515, 641, 775]:
		draw_line(Vector2(x, 16), Vector2(x, 54), Color("#406072"), 1, true)
		_draw_diamond(Vector2(x, 35), 3.5, Color("#688e9f"))
	_draw_stage_cell(Rect2(346, 4, 160, 62), theme)
	_draw_speed()
	if Arena.sim == null: return
	var sim = Arena.sim
	_draw_blessing(Vector2(301, 23), sim)
	var fraction := clampf(sim.crystal_hp / maxf(1.0, sim.crystal_max), 0, 1)
	_bar(Rect2(79, 49, 152, 9), fraction, Color("#6af4ef"))
	Look.text_box(self, Rect2(236, 40, 94, 23), "%d / %d" % [ceili(sim.crystal_hp), int(sim.crystal_max)], 16, Look.INK)
	var warning: bool = sim.boss_warned and not sim.boss_spawned
	Look.text_box(self, Rect2(518, 6, 120, 23), _boss_label(sim) if sim.boss_spawned else _tr("boss_in"), 15, Color("#ff9a8c") if warning else Look.INK_DIM)
	# The countdown rounds up (4, 3, 2, 1, boss) so it always agrees with the warning
	# banner; the elapsed clock after the boss counts up normally.
	var clock := ceilf(maxf(0, Balance.ARENA_BOSS_AT - sim.elapsed) - 0.0001)
	Look.text_box(self, Rect2(524, 27, 108, 34), _clock(sim.elapsed) if sim.boss_spawned else _clock(clock), 27, Look.GOLD if sim.boss_spawned else Color("#ff6b5c") if warning else Look.INK)
	_draw_coin(Vector2(663, 35), 11)
	Look.text_box(self, Rect2(678, 16, 90, 37), "%d G" % Arena.gold, 23, Look.GOLD)
	_draw_shield_panel(sim)
	_draw_boss_panel(sim)

func _boss_label(sim) -> String:
	return _tr("boss_final") if sim.final_stage() else _tr("boss_stage")

## "3탄" / "Stage 3": the stage's name everywhere on this screen.
func _stage_label(number: int) -> String:
	return _tr("stage_n") % number

## Presentation motion runs on `t`, which only advances while the screen itself is
## processing. A screen that is held still (a transition, a capture) shows everything
## settled, so nothing is ever photographed or left half-way through its entrance.
func _settled() -> bool:
	return not is_processing()

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

## Stage cell of the top strip: the stage number, the run's ten steps, the field's name.
func _draw_stage_cell(cell: Rect2, theme: Dictionary) -> void:
	var total := Balance.ARENA_STAGES
	var sim = Arena.sim
	var won: bool = sim != null and sim.won
	var clearing: bool = sim != null and sim.clear_t > 0.0
	var cleared := total if won else Arena.stage - 1 + (1 if clearing else 0)
	var final := Arena.stage >= total
	var label := _stage_label(Arena.stage)
	var count := " / %d" % total
	var label_w := Look.text_width(label, 20)
	var x := cell.get_center().x - (label_w + Look.text_width(count, 15)) * 0.5
	# The last stage is written in the warning colour until its boss falls; from that
	# beat on the number is gold like the ten lit steps under it.
	Look.text_left(self, Vector2(x, cell.position.y + 13), label, 20, Color("#ffb09c") if final and not won and not clearing else Look.GOLD)
	Look.text_left(self, Vector2(x + label_w, cell.position.y + 14), count, 15, Look.INK_DIM)
	var glow := 0.0 if _settled() else 0.5 + 0.5 * sin(t * 3.2)
	Look.draw_stage_track(self, Rect2(cell.position.x + 11, cell.position.y + 27, cell.size.x - 22, 5), Arena.stage, total, cleared, glow)
	Look.text_box(self, Rect2(cell.position.x, cell.position.y + 34, cell.size.x, 28), String(theme.get("ko", "")), 19, Look.INK)

## Guardian's blessing in the crystal block: the product's own crest and, beside it, the
## number of revivals left in this run (Arena.revives_left(): 3, 2, 1, 0). It reads like
## the gold counter next to its coin, and the number does not depend on colour.
##   ready    lit gold, breathing slowly, the number in gold
##   active   crystal blue inside a ring that drains: the reformed crystal cannot be hurt.
##            This wins over "ready": two blessings may still be in hand while it runs.
##   spent    a hollow steel outline and a steel 0: the next break ends the run
## Each revival lets the number land from a little larger, so the change is seen.
## Nothing is drawn for a run without the blessing. The crest follows the rule itself
## (Arena.revive_ready / sim.revives), so it also shows on a build without a shop, where
## every product counts as owned and the crystal does revive.
func _draw_blessing(at: Vector2, sim) -> void:
	if not (Arena.revive_ready() or sim.revives > 0): return
	var left := Arena.revives_left()
	var radius := 11.5
	var ink := Look.GOLD
	if sim.invuln_t > 0.0:
		var guard := clampf(sim.invuln_t / maxf(0.001, Balance.ARENA_REVIVE_INVULN), 0.0, 1.0)
		StoreView.draw_icon(self, at, Store.GUARDIAN, radius - 2.5, Look.CRYSTAL)
		draw_arc(at, radius + 1.5, 0, TAU, 32, Color(Look.CRYSTAL, 0.20), 2.6, true)
		draw_arc(at, radius + 1.5, -PI / 2, -PI / 2 + TAU * guard, 32, Color("#eafcff"), 2.6, true)
		ink = Color("#eafcff")
	elif left > 0:
		var breath := 0.5 if _settled() else 0.5 + 0.5 * sin(t * 2.4)
		draw_circle(at, radius + 3.5, Color(Look.GOLD, 0.10 + 0.10 * breath), true, -1, true)
		StoreView.draw_icon(self, at, Store.GUARDIAN, radius, Look.GOLD)
	else:
		var steel := Color("#6f8794")
		draw_circle(at, radius, Color(0.02, 0.05, 0.08, 0.55), true, -1, true)
		draw_arc(at, radius, 0, TAU, 32, Color(steel, 0.85), 1.3, true)
		var top := at + Vector2(0, -radius * 0.60)
		var bottom := at + Vector2(0, radius * 0.60)
		var left_p := at + Vector2(-radius * 0.34, -radius * 0.04)
		var right_p := at + Vector2(radius * 0.34, -radius * 0.04)
		draw_polyline(PackedVector2Array([top, right_p, bottom, left_p, top]), steel, 1.3, true)
		ink = Color("#8aa0ad")
	# The number, right of the crest.
	var number := str(left)
	var number_at := Vector2(at.x + radius + 5.5, at.y)
	var land := 1.0 if _settled() else 1.0 + 0.55 * (1.0 - _ease_out(_revive_age / 0.40))
	if land > 1.001:
		var number_mid := number_at + Vector2(Look.text_width(number, 18) * 0.5, 0)
		draw_set_transform(number_mid * (1.0 - land), 0, Vector2(land, land))
		Look.text_left(self, number_at, number, 18, Color.WHITE.lerp(ink, _ease_out(_revive_age / 0.40)))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		Look.text_left(self, number_at, number, 18, ink)

## The boss strip (warning banner or health bar) holds the first row under the top bar.
func _boss_strip_shown(sim) -> bool:
	if not sim.boss_spawned: return sim.boss_warned
	for mo in sim.monsters:
		if String(mo.get("kind", "")) == "boss": return true
	return false

func _banner_box(sim) -> Rect2:
	var top := BOSS_BOX.end.y + 8.0 if _boss_strip_shown(sim) else BOSS_BOX.position.y
	return Rect2(BATTLEFIELD.get_center().x - BANNER_SIZE.x * 0.5, top, BANNER_SIZE.x, BANNER_SIZE.y)

## Short field banners: a stage boss falling and the crystal's revival.
func _draw_banners() -> void:
	if Arena.modal != "result": _field_seen = true
	var sim = Arena.sim
	if sim == null: return
	# A cleared stage mends the crystal a little. The picture before the boss fell knows
	# what it held, so the banner can say how much came back.
	var clearing: bool = sim.clear_t > 0.0
	if clearing and not _clear_seen:
		_clear_heal = maxf(0.0, sim.crystal_hp - _hp_seen) if _hp_seen >= 0.0 else 0.0
	_clear_seen = clearing
	if not clearing: _hp_seen = sim.crystal_hp
	# The battlefield card's name plate takes this row while it is up.
	if Arena.modal == "stage": return
	if Arena.modal == "result":
		# Nothing of a banner is left under the result panel. The last boss's banner hands
		# over to the victory panel: it fades while the panel's shade comes in over it.
		var out := 1.0 - _result_age() / RESULT_BANNER_OUT
		if sim.won and out > 0.0: _draw_final_banner(sim, out)
		return
	if clearing and sim.final_stage():
		_draw_final_banner(sim)
	elif clearing:
		_draw_clear_banner(sim)
	elif _revive_age < REVIVE_BANNER and sim.revives > 0:
		_draw_revive_banner(sim)

## "N탄 돌파!" with the bounty, for as long as the simulator holds the cleared stage.
## (The last stage has its own banner: _draw_final_banner.)
func _draw_clear_banner(sim) -> void:
	var box := _banner_box(sim)
	var age: float = Balance.ARENA_CLEAR_DELAY - sim.clear_t
	var k := 1.0 if _settled() else _ease_out(age / 0.16)
	draw_set_transform(Vector2(0, -(1.0 - k) * 14.0), 0, Vector2.ONE)
	Look.fill_round(self, Rect2(box.position + Vector2(0, 5), box.size), 6, Color(0, 0, 0, 0.32))
	Look.glass_panel(self, box, Look.GOLD, Color(0.105, 0.085, 0.025, 0.90), true)
	var title := _stage_label(sim.stage) + " " + _tr("stage_clear")
	var title_box := Rect2(box.position.x + 70, box.position.y + 1, box.size.x - 140, 42)
	var size := Look.text_box(self, title_box, title, 28, Color("#fff0c7"))
	# Brass rules run out from the words to a diamond at each end.
	var half := Look.text_width(title, size) * 0.5 + 14.0
	var mid := Vector2(box.get_center().x, title_box.get_center().y)
	for side in [-1.0, 1.0]:
		var from := mid + Vector2(side * half, 0)
		var to := Vector2(box.get_center().x + side * (box.size.x * 0.5 - 22.0), mid.y)
		if (to.x - from.x) * side > 8.0:
			draw_line(from, to, Color(Look.GOLD, 0.55), 1.4, true)
			_draw_diamond(to, 5, Look.GOLD)
	# The bounty, said with the coin the gold counter uses, and what the crystal mended.
	var bonus := "+%d G" % Balance.arena_stage_bonus(sim.stage)
	var label := _tr("stage_bonus")
	var mended := "+%d" % roundi(_clear_heal) if _clear_heal >= 1.0 else ""
	var row_y := box.position.y + 52.0
	var label_w := Look.text_width(label, 16)
	var bonus_w := Look.text_width(bonus, 19)
	var mended_w := 30.0 + 18.0 + Look.text_width(mended, 19) if not mended.is_empty() else 0.0
	var left := box.get_center().x - (label_w + 14.0 + 22.0 + bonus_w + mended_w) * 0.5
	Look.text_left(self, Vector2(left, row_y), label, 16, Look.INK_DIM)
	_draw_coin(Vector2(left + label_w + 14.0 + 8.0, row_y), 8)
	Look.text_left(self, Vector2(left + label_w + 14.0 + 22.0, row_y), bonus, 19, Look.GOLD)
	if not mended.is_empty():
		var at := left + label_w + 14.0 + 22.0 + bonus_w + 30.0
		Look.draw_crystal(self, Vector2(at + 5.0, row_y + 1.0), 6.5, true)
		Look.text_left(self, Vector2(at + 18.0, row_y), mended, 19, Look.CRYSTAL)
	if not _settled() and age < 0.5:
		# One pass of light as it lands.
		var sweep := box.position.x + box.size.x * clampf(age / 0.42, 0.0, 1.0)
		Look.gradient_rect(self, Rect2(sweep - 60, box.position.y + 2, 60, box.size.y - 4), Color(1, 0.95, 0.75, 0.0), Color(1, 0.95, 0.75, 0.16 * (1.0 - age / 0.5)))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## The last boss fell: the run is won, and for the clear delay the banner says so before
## the result panel opens. It is the stage-clear banner's plaque in its brightest gold,
## framed twice, with stars where the others carry diamonds. There is no bounty row (no
## gold can be spent any more, and the crystal's mend no longer matters): under the words
## stand the run's ten steps, all lit, which the result panel repeats under its headline.
## `fade` below 1 is the hand-over: the settled banner dissolving under the result's shade.
func _draw_final_banner(sim, fade: float = 1.0) -> void:
	var box := _banner_box(sim)
	var age: float = Balance.ARENA_CLEAR_DELAY - sim.clear_t
	var settled := _settled() or fade < 1.0
	var k := 1.0 if settled else _ease_out(age / 0.18)
	draw_set_transform(Vector2(0, -(1.0 - k) * 14.0), 0, Vector2.ONE)
	var ivory := Color("#fff0c7")
	# Plain rectangles where the alpha moves (Look.fill_round caches a surface per colour).
	draw_rect(Rect2(box.position + Vector2(3, 6), box.size - Vector2(6, 0)), Color(0, 0, 0, 0.36 * fade))
	Look.glass_panel(self, box, ivory, Color(0.155, 0.112, 0.03, 0.94), true, fade)
	# A warm light falls into the plaque from its top edge.
	Look.gradient_rect(self, Rect2(box.position + Vector2(6, 3), Vector2(box.size.x - 12, 36)), Color(Look.GOLD, 0.26 * fade), Color(Look.GOLD, 0.0), true)
	draw_rect(box.grow(-4.0), Color(Look.GOLD, 0.42 * fade), false, 1.0)
	var title := _tr("final_clear")
	var title_box := Rect2(box.position.x + 44, box.position.y + 1, box.size.x - 88, 44)
	var size := Look.text_box(self, title_box, title, 30, Color("#fffaf0", fade))
	# A star at each end; a brass rule joins it to the words where there is room.
	var mid := Vector2(box.get_center().x, title_box.get_center().y)
	var half := Look.text_width(title, size) * 0.5 + 14.0
	for side in [-1.0, 1.0]:
		var star := Vector2(box.get_center().x + side * (box.size.x * 0.5 - 25.0), mid.y)
		var from := mid + Vector2(side * half, 0)
		var to := star - Vector2(side * 13.0, 0)
		if (to.x - from.x) * side > 10.0:
			draw_line(from, to, Color(Look.GOLD, 0.60 * fade), 1.4, true)
		var pop := 1.0 if settled else _ease_out((age - 0.10) / 0.20)
		if pop > 0.0:
			draw_colored_polygon(Look.star_points(star, 10.5 * pop), Color(Look.BG_DEEP, 0.85 * fade))
			draw_colored_polygon(Look.star_points(star, 8.0 * pop), Color(ivory, fade))
	# The run's ten steps, all lit, and what that means in the stage banners' own word.
	var words := _tr("final_clear_sub") % Balance.ARENA_STAGES
	var words_w := Look.text_width(words, 17)
	var track_w := 140.0
	var row_y := box.position.y + 54.0
	var left := box.get_center().x - (track_w + 12.0 + words_w) * 0.5
	var track := Rect2(left, row_y - 4.0, track_w, 8.0)
	# As the banner lands a glint runs the ten steps: the run is complete.
	var glint := -1.0 if settled else (age - 0.22) / 0.46
	Look.draw_stage_track(self, track, Balance.ARENA_STAGES, Balance.ARENA_STAGES, Balance.ARENA_STAGES, 0.0, false, fade, glint)
	Look.text_left(self, Vector2(left + track_w + 12.0, row_y), words, 17, Color(Look.GOLD.lightened(0.22), fade))
	if not settled and age < 0.5:
		# One pass of light over the whole plaque.
		var sweep := box.position.x + box.size.x * clampf(age / 0.42, 0.0, 1.0)
		Look.gradient_rect(self, Rect2(sweep - 70, box.position.y + 2, 70, box.size.y - 4), Color(1, 0.96, 0.78, 0.0), Color(1, 0.96, 0.78, 0.20 * (1.0 - age / 0.5)))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## The blessing's moment, for each of the run's revivals: what happened, the gold it
## handed over (said like the stage-clear banner says its bounty: the coin and "+N G"),
## how many blessings are left (a label and one pip each; after the last one the label
## says so in the warning colour), and how long the reformed crystal cannot be hurt.
func _draw_revive_banner(sim) -> void:
	var box := _banner_box(sim)
	var fade := clampf((REVIVE_BANNER - _revive_age) * 2.0, 0.0, 1.0)
	var settled := _settled()
	var k := 1.0 if settled else _ease_out(_revive_age / 0.18)
	draw_set_transform(Vector2(0, -(1.0 - k) * 14.0), 0, Vector2.ONE)
	# Fading parts are plain rectangles (Look.fill_round caches one surface per colour).
	draw_rect(Rect2(box.position + Vector2(3, 5), box.size - Vector2(6, 0)), Color(0, 0, 0, 0.32 * fade))
	Look.glass_panel(self, box, Look.CRYSTAL, Color(0.02, 0.095, 0.135, 0.90), true, fade)
	var crest := box.position + Vector2(38, box.size.y * 0.5 - 2.0)
	draw_circle(crest, 27, Color(Look.CRYSTAL, 0.10 * fade), true, -1, true)
	StoreView.draw_icon(self, crest, Store.GUARDIAN, 22, Color(Look.CRYSTAL, fade))
	var text_x := box.position.x + 74.0
	var right := box.end.x - 16.0
	# Seconds the reformed crystal cannot be hurt: the ward's glyph beside the title and
	# a draining bar along the bottom, so the number needs no word in either language.
	var guard := clampf(sim.invuln_t / maxf(0.001, Balance.ARENA_REVIVE_INVULN), 0.0, 1.0)
	var title_w := right - text_x
	if guard > 0.0:
		var seconds := "%.1f" % sim.invuln_t
		var seconds_w := Look.text_width(seconds, 18)
		Look.text_right(self, Vector2(right, box.position.y + 21), seconds, 18, Color("#eafcff", fade))
		_draw_skill_icon(Vector2(right - seconds_w - 14, box.position.y + 21), "ward", 8, Color(Look.CRYSTAL, fade))
		title_w -= seconds_w + 32.0
		var track := Rect2(box.position.x + 12, box.end.y - 8, box.size.x - 24, 3)
		draw_rect(track, Color(0.19, 0.26, 0.29, fade))
		draw_rect(Rect2(track.position, Vector2(track.size.x * guard, track.size.y)), Color(Look.CRYSTAL, fade))
	Look.text_box(self, Rect2(text_x, box.position.y + 2, title_w, 38), _tr("revived"), 25, Color("#eafcff", fade), HORIZONTAL_ALIGNMENT_LEFT)
	# The gold of this revival, then what is left.
	var row_y := box.position.y + 49.0
	var purse := "+%d G" % Balance.arena_revive_gold(sim.stage)
	_draw_coin(Vector2(text_x + 8, row_y), 8, fade)
	Look.text_left(self, Vector2(text_x + 22, row_y), purse, 19, Color(Look.GOLD, fade))
	var left: int = sim.revives_left()
	var last := left <= 0
	var label := _tr("revives_none") if last else _tr("revives_left")
	var tone := Color("#ff9a8c") if last else Look.CRYSTAL
	var pips := float(Balance.ARENA_REVIVE_USES) * 13.0
	var label_x := right - pips - 6.0 - Look.text_width(label, 16)
	Look.text_left(self, Vector2(label_x, row_y), label, 16, Color(tone, fade))
	for n in range(Balance.ARENA_REVIVE_USES):
		var pip := Vector2(right - pips + 6.5 + float(n) * 13.0, row_y)
		if n < left:
			_draw_diamond(pip, 6.5, Color(Look.CRYSTAL, fade))
		else:
			draw_polyline(PackedVector2Array([pip + Vector2(0, -6), pip + Vector2(4.1, 0), pip + Vector2(0, 6), pip + Vector2(-4.1, 0), pip + Vector2(0, -6)]), Color(tone, 0.75 * fade), 1.3, true)
	if not settled and _revive_age > 0.10 and _revive_age < 0.60:
		# The pip that was just spent goes out as the banner lands.
		var spent := Vector2(right - pips + 6.5 + float(left) * 13.0, row_y)
		if left < Balance.ARENA_REVIVE_USES:
			_draw_diamond(spent, 6.5 + 5.0 * _ease_out((_revive_age - 0.10) / 0.50), Color(1, 1, 1, 0.75 * (1.0 - (_revive_age - 0.10) / 0.50)))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## Battle speed x1 / x2 / x3 as one segmented chip in the top strip, left of the menu
## (user: "배속설정은 상단으로"). The chosen chip is solid gold; the others stay glass.
func _draw_speed() -> void:
	var active := Arena.sim != null and not Arena.sim.done
	Look.glass_panel(self, SPEED_BOX, Color("#7598aa"), Color(0.02, 0.06, 0.09, 0.80))
	var inner := SPEED_BOX.grow(-3)
	var width := inner.size.x / 3.0
	var chosen := clampi(roundi(speed), 1, 3)
	for i in range(3):
		var value := i + 1
		var id := "speed:%d" % value
		var rect := Rect2(inner.position + Vector2(i * width, 0), Vector2(width, inner.size.y))
		# The touch zone spans the whole strip height; the drawn chip stays compact.
		ui.zone(Rect2(rect.position.x, 4, rect.size.x, 62), id, active)
		var down := active and ui.pressed == id
		if i > 0:
			draw_line(Vector2(rect.position.x, rect.position.y + 6), Vector2(rect.position.x, rect.end.y - 6), Color("#406072"), 1, true)
		if value == chosen:
			Look.fill_round(self, rect, 4, Look.GOLD.darkened(0.10) if down else Look.GOLD)
			draw_line(rect.position + Vector2(5, 2), Vector2(rect.end.x - 5, rect.position.y + 2), Look.GOLD.lightened(0.35), 1)
		elif down:
			Look.fill_round(self, rect.grow(-1), 4, Color(0.42, 0.60, 0.70, 0.28))
		var ink := Look.BG_DEEP if value == chosen else (Look.INK_DIM if active else Color("#6e8390"))
		Look.text_box(self, rect, "x%d" % value, 19, ink)

## Crystal ward: the remaining seconds dominate (large tenths, a draining ring and a
## bar); absorb left is the secondary line. Pulses gold in the final two seconds.
func _draw_shield_panel(sim) -> void:
	if sim.shield <= 0: return
	var box := SHIELD_BOX
	var left := clampf(sim.shield_t / maxf(0.001, Balance.ARENA_WARD_DURATION), 0, 1)
	var urgent: bool = sim.shield_t <= 2.0
	var tint: Color = Look.CRYSTAL.lerp(Color("#ffd27a"), 0.5 + 0.5 * sin(t * 18)) if urgent else Look.CRYSTAL
	Look.glass_panel(self, box, tint, Color(0.015, 0.08, 0.14, 0.84))
	var ring := box.position + Vector2(25, 23)
	draw_arc(ring, 15, 0, TAU, 40, Color(Look.CRYSTAL, 0.18), 3, true)
	if left > 0: draw_arc(ring, 15, -PI / 2, -PI / 2 + TAU * left, 40, tint, 3, true)
	_draw_skill_icon(ring, "ward", 7, tint)
	Look.text_box(self, Rect2(box.position + Vector2(48, 1), Vector2(72, 44)), "%.1f" % sim.shield_t, 30, Look.INK)
	# The absorb number sits clear of the time bar under it (its feet were under the bar).
	Look.text_box(self, Rect2(box.position + Vector2(124, 0), Vector2(82, 22)), _tr("shield"), 15, Look.INK_DIM)
	Look.text_box(self, Rect2(box.position + Vector2(124, 16), Vector2(82, 24)), str(ceili(sim.shield)), 16, tint)
	_bar(Rect2(box.position.x + 10, box.end.y - 7, box.size.x - 20, 3), left, tint)

## Boss strip over the open battle box: the four-second warning banner (whole-second
## countdown, boss name, chevron toward its gate on screen), then its health bar.
func _draw_boss_panel(sim) -> void:
	var box := BOSS_BOX
	if sim.boss_spawned:
		for mo in sim.monsters:
			if String(mo.get("kind", "")) != "boss": continue
			Look.glass_panel(self, box, Color("#be797e"), Color(0.09, 0.02, 0.06, 0.86))
			var fraction := clampf(float(mo["hp"]) / maxf(1, float(mo["max"])), 0, 1)
			Look.text_box(self, Rect2(box.position + Vector2(16, 2), Vector2(box.size.x - 32, 28)), I18n.t(String(mo["m"].get("ko", _boss_label(sim)))), 19, Look.INK)
			_bar(Rect2(box.position.x + 16, box.end.y - 13, box.size.x - 32, 5), fraction, Look.RED)
			break
		return
	if not sim.boss_warned: return
	var left := maxf(0.0, Balance.ARENA_BOSS_AT - sim.elapsed)
	var pulse := 0.5 + 0.5 * sin(t * 9.0)
	var edge := Color("#ff6b5c").lerp(Color("#ffd27a"), pulse * 0.45)
	Look.glass_panel(self, box, edge, Color(0.17, 0.03, 0.05, 0.88), true)
	var sign_at := box.position + Vector2(25, 24)
	draw_colored_polygon(PackedVector2Array([sign_at + Vector2(0, -14), sign_at + Vector2(14, 10), sign_at + Vector2(-14, 10)]), Color(edge, 0.92))
	draw_line(sign_at + Vector2(0, -5), sign_at + Vector2(0, 3), Look.BG_DEEP, 2.5)
	draw_circle(sign_at + Vector2(0, 7), 1.6, Look.BG_DEEP)
	var boss: Dictionary = Arena.boss_for(1)
	Look.text_box(self, Rect2(box.position + Vector2(50, 0), Vector2(226, 21)), _boss_label(sim), 14, edge, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(self, Rect2(box.position + Vector2(50, 18), Vector2(226, 28)), I18n.t(String(boss.get("ko", ""))), 19, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	# Whole seconds, rounded up like the top clock during the warning: 4, 3, 2, 1, boss.
	var count := maxi(1, ceili(left - 0.0001))
	Look.text_box(self, Rect2(box.end.x - 112, box.position.y, 54, 46), str(count), 30, Look.INK)
	var gate: Vector2 = sim.boss_gate()
	if gate.is_finite():
		var origin := Vector2(box.end.x - 34, box.get_center().y)
		var direction := (view_3d.project(gate, 0.3) - origin).normalized()
		_draw_chevron(origin, direction, 11 + pulse * 2, edge)

func _draw_chevron(at: Vector2, direction: Vector2, size: float, color: Color) -> void:
	var normal := Vector2(-direction.y, direction.x)
	for n in range(2):
		var tip := at + direction * (size * 0.55 - n * size * 0.5)
		var back := tip - direction * size * 0.5
		draw_polyline(PackedVector2Array([back + normal * size * 0.5, tip, back - normal * size * 0.5]), Color(color, 1.0 - n * 0.4), 3, true)

func _draw_controls() -> void:
	# All commands live in one right rail; the lower field stays open for movement.
	draw_rect(SIDEBAR, Color(0.012, 0.037, 0.06, 0.88))
	draw_line(SIDEBAR.position, Vector2(SIDEBAR.position.x, SIDEBAR.end.y), Color("#84a8b5"), 1, true)
	for n in range(7):
		draw_rect(Rect2(SIDEBAR.position.x - 14 + n * 2, 70, 2, 730), Color(0.01, 0.03, 0.05, n * 0.025))
	var active := Arena.modal.is_empty() and Arena.sim != null and not Arena.sim.done
	var summoning := active and Arena.gold >= Arena.summon_cost() and not Arena.eligible_units().is_empty()
	_draw_command_button(Rect2(1148, 84, 118, 40), _tr("summon"), "%d G" % Arena.summon_cost(), "summon", summoning)
	ui.glass_button(self, Rect2(1148, 130, 118, 40), _tr("shop"), "shop", active, Look.PANEL_EDGE, 19)
	_draw_command_button(Rect2(1148, 176, 118, 40), _tr("bench"), str(Arena.bench.size()), "bench", active)
	for i in range(Balance.ARENA_HERO_LIMIT):
		var rect := Rect2(HERO_X + (i % 2) * (HERO_W + HERO_GAP), HERO_Y + (i / 2) * (HERO_H + 9), HERO_W, HERO_H)
		if i < Arena.heroes.size():
			_draw_hero_card(rect, Arena.heroes[i], i == Arena.selected)
			ui.zone(rect.grow(3), "hero:%d" % i, active)
		else:
			ui.zone(rect.grow(3), "hero:empty", false)
			Look.glass_panel(self, rect, Color("#587787"), Color(0.06, 0.12, 0.16, 0.73))
			_draw_skill_icon(Vector2(rect.get_center().x, rect.position.y + 31), "freeze", 13, Color(0.28, 0.46, 0.56, 0.25))
			Look.text_box(self, Rect2(rect.position + Vector2(8, 44), Vector2(rect.size.x - 16, 36)), str(i + 1), 27, Color("#698390"))
			Look.text_box(self, Rect2(rect.position.x + 8, rect.end.y - 33, rect.size.x - 16, 24), "빈 자리", 17, Color("#829ba7"))
	var sim = Arena.sim
	for i in range(3):
		var id: String = ["blast", "freeze", "ward"][i]
		var rect := Rect2(1006, 615 + i * 61, 260, 54)
		var remaining := float(sim.skill_cooldowns.get(id, 0.0)) if sim != null else 0.0
		var uses := int(sim.skill_uses_left(id)) if sim != null else 0
		var limit := int(sim.skill_max_uses(id)) if sim != null else 0
		# Out of casts for this run: disabled for good, shown apart from a mere cooldown.
		var spent: bool = sim != null and uses <= 0
		var enabled := active and remaining <= 0 and not spent
		var color: Color = [Look.GOLD, Color("#aeeaff"), Color("#6ce8fa")][i]
		var ink := color if enabled else Look.INK_DIM
		var warding: bool = id == "ward" and sim != null and sim.shield > 0
		ui.glass_button(self, rect, "", "skill:" + id, enabled, color, 18)
		var icon_at := Vector2(rect.position.x + 30, rect.get_center().y)
		for layer in range(3): draw_circle(icon_at, 21 - layer * 4, Color(color, 0.035 if enabled else 0.009))
		if warding:
			# The ward's active seconds drain as a ring around its glyph; the bar along the
			# bottom stays the cooldown, so the two timers never share one display.
			var left := clampf(sim.shield_t / maxf(0.001, Balance.ARENA_WARD_DURATION), 0, 1)
			draw_arc(icon_at, 22.5, 0, TAU, 48, Color(color, 0.22), 3, true)
			draw_arc(icon_at, 22.5, -PI / 2, -PI / 2 + TAU * left, 48, Look.CRYSTAL, 3, true)
		_draw_skill_icon(icon_at, id, 17, Color("#587080") if spent else ink)
		Look.text_box(self, Rect2(rect.position + Vector2(59, 3), Vector2(136, 26)), _tr("skill." + id), 20, ink)
		var status := "%.1f" % remaining if remaining > 0 else _tr("ready")
		var status_color := ink
		if warding:
			status = "%.1f" % sim.shield_t
			status_color = Look.CRYSTAL
		elif spent:
			status = ""
		if not status.is_empty():
			Look.text_box(self, Rect2(rect.position + Vector2(59, 28), Vector2(136, 20)), status, 15, status_color)
		_draw_uses(Rect2(rect.end.x - 68, rect.position.y + 5, 60, 44), uses, limit, color, spent)
		if remaining > 0 and sim != null:
			var maximum := sim.skill_max_cooldown(id)
			_bar(Rect2(rect.position.x + 8, rect.end.y - 6, rect.size.x - 16, 2), 1 - remaining / maxf(0.001, maximum), color)

## Casts left this run as a fraction plus one pip per cast, so "2/6" reads at a glance.
func _draw_uses(rect: Rect2, uses: int, limit: int, color: Color, spent: bool) -> void:
	if limit <= 0: return
	var ink: Color = Color("#e2415a").lerp(Look.INK_DIM, 0.35) if spent else color
	Look.text_box(self, Rect2(rect.position, Vector2(rect.size.x, 27)), "%d/%d" % [uses, limit], 18, ink)
	var pitch := minf(10.0, rect.size.x / limit)
	var start := rect.get_center().x - pitch * (limit - 1) * 0.5
	for n in range(limit):
		var at := Vector2(start + n * pitch, rect.end.y - 8)
		if n < uses: _draw_diamond(at, 4, color)
		else: draw_polyline(PackedVector2Array([at + Vector2(0, -4), at + Vector2(2.7, 0), at + Vector2(0, 4), at + Vector2(-2.7, 0), at + Vector2(0, -4)]), Color(ink, 0.6), 1, true)

func _draw_command_button(rect: Rect2, title: String, value: String, id: String, active: bool) -> void:
	ui.glass_button(self, rect, "", id, active)
	var color := Look.INK if active else Color("#8499a5")
	Look.text_box(self, Rect2(rect.position + Vector2(4, 1), Vector2(rect.size.x - 8, 21)), title, 17, color)
	Look.text_box(self, Rect2(rect.position + Vector2(4, 20), Vector2(rect.size.x - 8, 20)), value, 13, Look.GOLD if active else color)

func _draw_joystick() -> void:
	if _joy_pointer == -99 or not Arena.modal.is_empty() or _menu_open(): return
	draw_circle(joy_origin + Vector2(0, 3), JOY_RADIUS + 6, Color(0, 0, 0, 0.38))
	draw_circle(joy_origin, JOY_RADIUS + 4, Color(0.3, 0.54, 0.65, 0.45))
	draw_circle(joy_origin, JOY_RADIUS + 1, Color(0.02, 0.07, 0.11, 0.24))
	draw_circle(joy_origin, JOY_RADIUS - 3, Color(0.11, 0.24, 0.31, 0.18))
	draw_circle(joy_origin, JOY_RADIUS - 9, Color(0.025, 0.095, 0.15, 0.12))
	draw_arc(joy_origin, JOY_RADIUS + 2, PI * 1.05, TAU * 0.99, 48, Color("#91c7d9"), 1.4, true)
	draw_arc(joy_origin, JOY_RADIUS - 7, 0, TAU, 64, Color(0.41, 0.64, 0.73, 0.35), 1, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var at: Vector2 = joy_origin + d * 48
		var normal := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([at + d * 6, at - d * 3 + normal * 4, at - d * 3 - normal * 4]), Color("#b8ddea"))
	var stick := joy_origin + joystick * 36
	draw_circle(stick + Vector2(0, 3), 28, Color(0, 0, 0, 0.30))
	draw_circle(stick, 28, Look.GOLD if _joy_pointer != -99 else Color("#8db5c3"))
	draw_circle(stick, 26, Color("#284d60"))
	draw_circle(stick + Vector2(-3, -4), 21, Color(0.25, 0.48, 0.58, 0.42))
	draw_line(stick + Vector2(-15, -15), stick + Vector2(15, 15), Color(0.62, 0.85, 0.9, 0.13), 1, true)
	draw_line(stick + Vector2(15, -15), stick + Vector2(-15, 15), Color(0.62, 0.85, 0.9, 0.13), 1, true)

func _draw_hero_card(rect: Rect2, hero: Dictionary, selected: bool) -> void:
	var unit: Dictionary = hero["unit"]
	var tier := int(hero["tier"])
	var element := String(unit.get("elem", "none"))
	var edge := Look.GOLD if selected else Balance.elem_color(element).lerp(Color("#7394a6"), 0.60)
	Look.glass_panel(self, rect, edge, Color(0.018, 0.04, 0.065, 0.93), selected)
	var preview := Art.unit_preview(unit, tier)
	if not preview.is_empty():
		var key := String(unit["id"]) + ":" + str(tier)
		if not _card_crops.has(key):
			var texture: Texture2D = preview["tex"]
			var picture: Image = texture.diffuse_texture.get_image() if texture is CanvasTexture else texture.get_image()
			if picture.is_compressed(): picture.decompress()
			var visible := Rect2(picture.get_used_rect())
			var crop_height := visible.size.y * 0.53
			var crop_width := minf(visible.size.x, crop_height * 0.86)
			_card_crops[key] = Rect2(visible.get_center().x - crop_width * 0.5, visible.position.y - 3, crop_width, crop_height)
		# Alpha bounds remove empty studio margins before a native upper-body crop.
		var crop: Rect2 = _card_crops[key]
		var target := Rect2(rect.position + Vector2(5, 20), Vector2(rect.size.x - 10, rect.size.y - 29))
		draw_texture_rect_region(preview["tex"], Art.fit_rect(crop.size, target), crop)
	for n in range(9):
		draw_rect(Rect2(rect.position.x + 4, rect.end.y - 38 + n * 4, rect.size.x - 8, 4), Color(0.018, 0.035, 0.055, 0.18 + n * 0.088))
	Look.text_box(self, Rect2(rect.position.x + 5, rect.end.y - 30, rect.size.x - 10, 27), Look.unit_name(unit), 20, Look.INK)
	Look.fill_round(self, Rect2(rect.position + Vector2(4, 4), Vector2(rect.size.x - 8, 20)), 2, Color(0.008, 0.017, 0.03, 0.90))
	Look.draw_elem(self, rect.position + Vector2(14, 14), 8, element)
	Look.draw_rarity_fit(self, Rect2(rect.position + Vector2(27, 4), Vector2(rect.size.x - 34, 20)), tier, 5.2)
	if selected:
		Look.draw_brackets(self, rect.grow(2), 13, Look.GOLD.lightened(0.25), 2)
		var badge := rect.position + Vector2(rect.size.x - 24, 29)
		Look.fill_round(self, Rect2(badge, Vector2(18, 18)), 2, Look.GOLD)
		draw_line(badge + Vector2(4, 9), badge + Vector2(8, 13), Look.BG_DEEP, 2)
		draw_line(badge + Vector2(8, 13), badge + Vector2(15, 5), Look.BG_DEEP, 2)

func _draw_minimap() -> void:
	if Arena.sim == null: return
	Look.glass_panel(self, MINIMAP, Color("#85adbc"), Color(0.015, 0.055, 0.085, 0.79))
	var map := Rect2(MINIMAP.get_center() - Vector2.ONE * 54, Vector2.ONE * 108)
	var perimeter := PackedVector2Array()
	for point in ArenaGeometry.outline(): perimeter.append(view_3d.minimap_point(point, map))
	draw_colored_polygon(perimeter, Color(0.08, 0.20, 0.25, 0.30))
	draw_polyline(perimeter + PackedVector2Array([perimeter[0]]), Color(0.55, 0.77, 0.84, 0.59), 1.1, true)
	# Every road of the current layout, each drawn once at its true width.
	var width := ArenaGeometry.ROAD_WIDTH / (ArenaGeometry.RADIUS * 2) * map.size.x
	for polyline in ArenaGeometry.road_polylines():
		var road := PackedVector2Array()
		for point in polyline: road.append(view_3d.minimap_point(point, map))
		draw_polyline(road, Color(0.56, 0.68, 0.68, 0.27), width, true)
		draw_polyline(road, Color(0.78, 0.86, 0.82, 0.19), 1, true)
	# Every entrance of this battlefield, so a new layout reads before the first monster:
	# a dart on the rim pointing in, rimmed dark so it holds on the road's pale stone.
	for lane in range(ArenaGeometry.route_count()):
		var gate := view_3d.minimap_point(ArenaGeometry.gate_point(lane, 4.0), map)
		_draw_gate_dart(gate + (map.get_center() - gate).normalized() * 7.0, (map.get_center() - gate).normalized(), 10.5, 5.0)
	# The camera footprint only matters while it is smaller than the whole field.
	var footprint := view_3d.minimap_footprint(map)
	if footprint.size() >= 3 and _polygon_area(footprint) < _polygon_area(perimeter) * 0.985:
		draw_colored_polygon(footprint, Color(0.27, 0.69, 0.82, 0.07))
		draw_polyline(footprint + PackedVector2Array([footprint[0]]), Color(0.60, 0.84, 0.90, 0.57), 1, true)
	for mo in Arena.sim.monsters:
		if float(mo.get("hp", 0)) <= 0: continue
		var at := view_3d.minimap_point(mo["pos"], map)
		var boss := String(mo.get("kind", "")) == "boss"
		if boss:
			draw_circle(at, 5.5, Color(0.98, 0.3, 0.24, 0.15))
			_draw_diamond(at, 4, Color("#ffad68"))
		else: draw_circle(at, 2.0, Color("#f58c83"))
	for i in range(Arena.sim.heroes.size()):
		var at := view_3d.minimap_point(Arena.sim.heroes[i]["pos"], map)
		if i == Arena.selected:
			draw_arc(at, 4.2, 0, TAU, 18, Color("#ffe3a0"), 1, true)
			draw_circle(at, 2.4, Look.GOLD)
		else: draw_circle(at, 2, Color("#91cfda"))
	var crystal := view_3d.minimap_point(Balance.ARENA_CENTER, map)
	_draw_diamond(crystal, 4, Color("#77edff"))
	draw_circle(crystal, 1, Color.WHITE)
	# Warned boss gate: a pulsing ring marks the entrance until the boss diamond takes over.
	if Arena.sim.boss_warned and not Arena.sim.boss_spawned:
		var gate: Vector2 = Arena.sim.boss_gate()
		if gate.is_finite():
			var at := view_3d.minimap_point(gate, map)
			var pulse := 0.5 + 0.5 * sin(t * 9.0)
			draw_circle(at, 7, Color(1.0, 0.42, 0.36, 0.10 + pulse * 0.12))
			draw_arc(at, 5 + pulse * 3, 0, TAU, 20, Color("#ff8c7a"), 1.5, true)
			_draw_diamond(at, 3.5, Color("#ffd27a"))
	# Compass tick uses a shape, avoiding another language-dependent HUD label.
	draw_colored_polygon(PackedVector2Array([Vector2(MINIMAP.get_center().x, MINIMAP.position.y + 2), Vector2(MINIMAP.get_center().x - 3, MINIMAP.position.y + 7), Vector2(MINIMAP.get_center().x + 3, MINIMAP.position.y + 7)]), Color("#9dbdcc"))

func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5

func _draw_diamond(at: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.67, 0), at + Vector2(0, radius), at + Vector2(-radius * 0.67, 0)]), color)

func _draw_hud_crystal(at: Vector2) -> void:
	var top := at + Vector2(0, -24)
	var left := at + Vector2(-13, -3)
	var right := at + Vector2(13, -3)
	var bottom := at + Vector2(0, 24)
	var core := at + Vector2(-1, 3)
	var high := at + Vector2(3, -8)
	for n in range(3): draw_circle(at, 20 - n * 3, Color(0.19, 0.74, 0.93, 0.032))
	draw_colored_polygon(PackedVector2Array([top, left, high]), Color("#c8faff"))
	draw_colored_polygon(PackedVector2Array([top, high, right]), Color("#31b9e1"))
	draw_colored_polygon(PackedVector2Array([left, core, high]), Color("#278ab8"))
	draw_colored_polygon(PackedVector2Array([right, high, core]), Color("#83f0ff"))
	draw_colored_polygon(PackedVector2Array([left, bottom, core]), Color("#1769a7"))
	draw_colored_polygon(PackedVector2Array([right, core, bottom]), Color("#51cdec"))
	draw_polyline(PackedVector2Array([top, left, bottom, right, top]), Color("#9aeeff"), 1, true)
	draw_line(top, core, Color("#b9f5ff"), 1, true)
	draw_line(core, bottom, Color("#a6f1ff"), 1, true)

func _draw_coin(at: Vector2, radius: float, alpha: float = 1.0) -> void:
	draw_circle(at, radius + 1, Color("#7e653b", alpha))
	draw_circle(at, radius, Color("#dcad51", alpha))
	draw_arc(at, radius - 3, 0, TAU, 28, Color("#fff0b8", alpha), 1.2, true)
	draw_line(at + Vector2(-2, -7), at + Vector2(-5, 6), Color("#ffedb0", alpha), 2, true)
	draw_line(at + Vector2(3, -7), at + Vector2(0, 6), Color("#805d2d", alpha), 2, true)

func _draw_skill_icon(center: Vector2, id: String, radius: float, color: Color) -> void:
	if id == "blast":
		draw_colored_polygon(Look.star_points(center, radius, 0.4), color)
		for n in range(6):
			var d := Vector2.from_angle(n * TAU / 6)
			draw_line(center + d * (radius + 3), center + d * (radius + 7), color, 2)
	elif id == "freeze":
		for n in range(6):
			var d := Vector2.from_angle(n * TAU / 6)
			var normal := Vector2(-d.y, d.x)
			draw_line(center, center + d * radius, color, 2)
			draw_line(center + d * radius * 0.52, center + d * radius * 0.82 + normal * radius * 0.25, color, 2)
			draw_line(center + d * radius * 0.52, center + d * radius * 0.82 - normal * radius * 0.25, color, 2)
	else:
		var points := PackedVector2Array([center + Vector2(-radius, -radius * 0.75), center + Vector2(0, -radius), center + Vector2(radius, -radius * 0.75), center + Vector2(radius * 0.82, radius * 0.4), center + Vector2(0, radius), center + Vector2(-radius * 0.82, radius * 0.4)])
		draw_polyline(points + PackedVector2Array([points[0]]), color, 2, true)
		draw_line(center + Vector2(-5, 0), center + Vector2(5, 0), color, 2)
		draw_line(center + Vector2(0, -5), center + Vector2(0, 5), color, 2)

func _draw_monster_bars() -> void:
	if Arena.sim == null: return
	var occupied: Dictionary = {}
	for mo in Arena.sim.monsters:
		var kind := String(mo.get("kind", ""))
		var boss := kind == "boss"
		if mo["hp"] >= mo["max"] and not bool(mo.get("blocked", false)) and not boss: continue
		var at := view_3d.project(mo["pos"], _monster_top(mo))
		var field := BATTLEFIELD.grow(-14)
		if boss: at = at.clamp(field.position + Vector2(44, 16), field.end - Vector2(44, 0))
		if not field.has_point(at) or MINIMAP.has_point(at): continue
		var cell := Vector2i(int(at.x / 30), int(at.y / 12))
		if occupied.has(cell) and not boss: continue
		occupied[cell] = true
		var fraction := clampf(float(mo["hp"]) / maxf(1, float(mo["max"])), 0, 1)
		if boss:
			# The 2.8x boss carries a wide framed bar that reads over its own bulk.
			Look.fill_round(self, Rect2(at.x - 44, at.y - 13, 88, 13), 4, Color(0.02, 0.04, 0.06, 0.72))
			_bar(Rect2(at.x - 40, at.y - 10, 80, 7), fraction, Look.hp_color(fraction))
		else:
			var width := 40.0 if kind == "tank" else 32.0
			_bar(Rect2(at.x - width * 0.5, at.y - 7, width, 4), fraction, Look.hp_color(fraction))
		if bool(mo.get("blocked", false)) and not boss:
			draw_line(at + Vector2(-4, -14), at + Vector2(-4, -9), Look.GOLD, 2)
			draw_line(at + Vector2(4, -14), at + Vector2(4, -9), Look.GOLD, 2)

## World height of a monster's visual top so its bar floats just over a 2.8x boss body
## or a small swarm body alike. Boss tops come from the actual mesh bounds (cached 0.5s).
func _monster_top(mo: Dictionary) -> float:
	var kind := String(mo.get("kind", ""))
	if kind != "boss": return 1.2 if kind == "tank" else 0.84
	var sid := int(mo.get("spawn_id", 0))
	var cached: Dictionary = _boss_tops.get(sid, {})
	if not cached.is_empty() and t - float(cached["t"]) < 0.5: return float(cached["h"])
	var height := 3.6
	var node: Node3D = view_3d.world.monster_node(sid) if view_3d.world != null else null
	if node != null and node.is_inside_tree():
		var top := -INF
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var aabb: AABB = mesh.get_aabb()
			for corner in range(8):
				top = maxf(top, (mesh.global_transform * aabb.get_endpoint(corner)).y)
		if top > 0.5: height = top + 0.22
	_boss_tops[sid] = {"h": height, "t": t}
	return height

func _shade() -> void:
	draw_rect(Look.SCREEN, Color(0.025, 0.05, 0.075, 0.80))
	ui.zone(Look.SCREEN, "modal:block")
	Look.glass_panel(self, MODAL, Color("#81a5b6"), Color(0.035, 0.085, 0.13, 0.96))
	Look.fill_round(self, Rect2(1002, 100, 174, 31), 4, Color("#2d4246"))
	Look.text_box(self, Rect2(1008, 102, 162, 25), _tr("pause"), 17, Look.GOLD)

## The battlefield briefing: which stage this is, where it is fought, what comes down
## which roads and who waits at the end. It opens the run and every stage after a boss
## falls, and stays until its one button is pressed.
##
## The new field is the reveal, so the card keeps off it: a light veil, the name plate
## under the top strip, the briefing sheet over the idle command rail, and a mark on the
## real ground at every gate. The sheet's diagram sits where the minimap lives, so the
## roads read there first and are found there again once the battle runs.
func _draw_stage_card() -> void:
	ui.zone(Look.SCREEN, "modal:block")
	var preview := _stage_preview()
	var theme: Dictionary = preview["theme"]
	var body := String(theme.get("main_body", "wood"))
	var accent := Balance.body_color(body)
	var final: bool = preview["final"]
	var age := _card_age()
	var settled := _settled()
	var veil := 1.0 if settled else _ease_out(age / 0.30)
	draw_rect(BATTLEFIELD, Color(0.012, 0.03, 0.055, 0.27 * veil))
	# A shadow under the top strip seats the name plate on bright fields too.
	Look.gradient_rect(self, Rect2(0, 71, BATTLEFIELD.size.x, 104), Color(0.008, 0.024, 0.04, 0.62 * veil), Color(0.008, 0.024, 0.04, 0.0), true)
	if final:
		# The last field closes in: a red dusk from the bottom edge.
		Look.gradient_rect(self, Rect2(0, 560, BATTLEFIELD.size.x, 240), Color(0.42, 0.05, 0.08, 0.0), Color(0.42, 0.05, 0.08, 0.34 * veil), true)
	_draw_gate_beacons(age, settled)
	_draw_stage_band(preview, accent, age, settled)
	_draw_stage_panel(preview, accent, age, settled)

## Seconds since this stage's card opened. The frame that opens a stage also builds its
## 3D field, so the clock starts on the card's third picture: the entrance is never
## swallowed by that one long frame.
func _card_age() -> float:
	var key := "%d:%d:%d" % [Arena.run_seed, Arena.stage, Arena.theme_index]
	if key != _card_key:
		_card_key = key
		_card_draws = 0
	_card_draws += 1
	if _card_draws <= 2:
		_card_t0 = t
	return t - _card_t0

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
	if view_3d.world == null: return
	var rim := Color(Look.BG_DEEP, 0.78)
	for lane in range(ArenaGeometry.route_count()):
		var k := 1.0 if settled else _ease_out((age - 0.28 - lane * 0.08) / 0.32)
		if k <= 0.0: continue
		var route := ArenaGeometry.route_points(lane)
		var gate := route[0]
		if not BATTLEFIELD.grow(-4).has_point(view_3d.project(gate, 0.05)): continue
		var ring := PackedVector2Array()
		var radius := 30.0 * (0.55 + 0.45 * k)
		for n in range(25):
			ring.append(view_3d.project(gate + Vector2.from_angle(n * TAU / 24.0) * radius, 0.05))
		draw_polyline(ring, Color(rim, rim.a * k), 6.0, true)
		draw_polyline(ring, Color(Look.GATE_MARK, k), 2.6, true)
		if not settled:
			# A slow second ring breathes outward: this is where they come from.
			var beat := fposmod(t * 0.7 + lane * 0.23, 1.0)
			var wave := PackedVector2Array()
			for n in range(25):
				wave.append(view_3d.project(gate + Vector2.from_angle(n * TAU / 24.0) * radius * (1.0 + beat * 0.9), 0.05))
			draw_polyline(wave, Color(Look.GATE_MARK, 0.55 * (1.0 - beat) * k), 2.0, true)
		for step in range(3):
			var index := mini(route.size() - 2, roundi((62.0 + step * 44.0) / ArenaGeometry.SAMPLE))
			var along := (route[index + 1] - route[index]).normalized()
			var across := Vector2(-along.y, along.x)
			var tip := view_3d.project(route[index] + along * 15.0, 0.05)
			var a := view_3d.project(route[index] - along * 9.0 + across * 21.0, 0.05)
			var b := view_3d.project(route[index] - along * 9.0 - across * 21.0, 0.05)
			var lit := 1.0 if settled else 0.45 + 0.55 * maxf(0.0, sin(t * 4.6 - step * 1.05))
			var mark := PackedVector2Array([a, tip, b])
			draw_polyline(mark, Color(rim, rim.a * k), 7.0, true)
			draw_polyline(mark, Color(Look.GATE_MARK, lit * k), 3.4, true)

## The name plate: biome emblem, stage and the run's ten steps, the battlefield's name,
## and its hazard rank counted in pips (never told by colour alone).
func _draw_stage_band(preview: Dictionary, accent: Color, age: float, settled: bool) -> void:
	var band := STAGE_BAND
	var theme: Dictionary = preview["theme"]
	var final: bool = preview["final"]
	# It settles from just under the top strip's line; it never rides over the strip.
	var k := 1.0 if settled else _ease_out(age / 0.24)
	draw_set_transform(Vector2(0, -(1.0 - k) * 8.0), 0, Vector2.ONE)
	var edge := Look.GOLD if final else accent.lerp(Look.STEEL, 0.30)
	var face := Color(0.115, 0.035, 0.05, 0.93) if final else Color(0.026, 0.066, 0.098, 0.92)
	Look.fill_round(self, Rect2(band.position + Vector2(0, 6), band.size), 6, Color(0, 0, 0, 0.36))
	Look.glass_panel(self, band, edge, face, true)
	# The biome's wash runs in from the emblem's side.
	Look.gradient_rect(self, Rect2(band.position + Vector2(6, 4), Vector2(250, band.size.y - 8)), Color(accent, 0.15), Color(accent, 0.0))
	Look.draw_body(self, band.position + Vector2(40, band.size.y * 0.5), 20, String(theme.get("main_body", "")))
	var x := band.position.x + 74.0
	# Stage chip and the ten steps of the run.
	var label := _stage_label(int(preview["stage"]))
	var chip := Rect2(x, band.position.y + 7, Look.text_width(label, 17) + 20.0, 24)
	Look.fill_round(self, chip, 3, Color("#f08d7c") if final else Look.GOLD)
	Look.text_center(self, chip.get_center(), label, 17, Look.BG_DEEP)
	var track := Rect2(chip.end.x + 12, band.position.y + 15, 206, 8)
	var glow := 0.0 if settled else 0.5 + 0.5 * sin(t * 3.2)
	Look.draw_stage_track(self, track, int(preview["stage"]), Balance.ARENA_STAGES, -1, glow)
	if final:
		Look.text_left(self, Vector2(track.end.x + 14, band.position.y + 19), _tr("final_stage"), 17, Color("#ffb09c"))
	# Hazard rank at the right end: a word and five pips.
	var right := band.end.x - 18.0
	Look.text_right(self, Vector2(right, band.position.y + 19), _tr("field_rank"), 15, Look.INK_DIM)
	var rank := clampi(int(preview["rank"]), 0, 5)
	for n in range(5):
		var pip := Vector2(right - 8.0 - (4 - n) * 21.0, band.position.y + 48)
		if n < rank:
			_draw_diamond(pip, 9, accent.lightened(0.22))
			draw_line(pip + Vector2(0, -9), pip + Vector2(0, 9), Color(1, 1, 1, 0.30), 1, true)
		else:
			draw_polyline(PackedVector2Array([pip + Vector2(0, -8), pip + Vector2(5.6, 0), pip + Vector2(0, 8), pip + Vector2(-5.6, 0), pip + Vector2(0, -8)]), Color("#6f8794"), 1.3, true)
	# The name: the largest words on the screen while the card is up.
	Look.text_box(self, Rect2(x, band.position.y + 24, right - 118.0 - x, 50), String(theme.get("ko", "")), 34, Color("#fff0c7") if final else Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## The briefing sheet over the command rail: roads and gates, the monsters by body, the
## boss, and the card's one action.
func _draw_stage_panel(preview: Dictionary, accent: Color, age: float, settled: bool) -> void:
	var panel := STAGE_PANEL
	var final: bool = preview["final"]
	var k := 1.0 if settled else _ease_out(age / 0.28)
	draw_set_transform(Vector2((1.0 - k) * 48.0, 0), 0, Vector2.ONE)
	for n in range(8):
		draw_rect(Rect2(panel.position.x - 16 + n * 2, panel.position.y, 2, panel.size.y), Color(0.004, 0.016, 0.03, n * 0.034))
	# Opaque: the rail's cards must not show through the sheet that replaces them.
	draw_rect(panel, Color("#07131c"))
	Look.gradient_rect(self, Rect2(panel.position, Vector2(panel.size.x, 300)), Color(accent, 0.11), Color(accent, 0.0), true)
	draw_line(panel.position, Vector2(panel.position.x, panel.end.y), Look.STEEL, 1, true)
	draw_rect(Rect2(panel.position.x + 1, panel.position.y, 2, panel.size.y), Color(accent, 0.40))
	var x := panel.position.x + 14.0
	var w := panel.size.x - 28.0
	# Roads and gates first: this is what differs from field to field.
	var gates_label := _tr("gates")
	var gates_size := Look.text_box(self, Rect2(x + 22, panel.position.y + 9, w - 70, 26), gates_label, 17, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_draw_gate_dart(Vector2(x + 16, panel.position.y + 22), Vector2.RIGHT, 13.0, 7.0)
	Look.text_left(self, Vector2(x + 22 + Look.text_width(gates_label, gates_size) + 12, panel.position.y + 21), str(ArenaGeometry.route_count()), 24, Look.GATE_MARK)
	_draw_layout(Rect2(panel.position.x + panel.size.x * 0.5 - 104, panel.position.y + 52, 208, 208), accent, age, settled)
	var y := panel.position.y + 282.0
	draw_line(Vector2(x, y), Vector2(x + w, y), Color(Look.STEEL, 0.28), 1, true)
	# Who comes: the field's own body first, the rest as chips.
	Look.text_box(self, Rect2(x + 2, y + 6, w - 4, 26), _tr("monsters"), 17, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	y += 36.0
	var rows: Array = preview["rows"]
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
	ui.button(self, button, _tr("stage_start"), "stage:start", true, Look.GOLD, 25)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## The field's main body in three rows: badge, name and share / its monsters / what it
## is weak to and immune to (attack elements are circles, bodies are squares, as
## everywhere in the game). The last row is read from the rule table, not written here.
const BODY_BLOCK_H := 112.0

func _draw_body_block(rect: Rect2, row: Dictionary) -> void:
	var body := String(row["body"])
	var color := Balance.body_color(body)
	Look.fill_round(self, rect, 5, Color("#0d1f29"))
	# The share again as a bar behind the first row: a length, not only a number.
	Look.fill_round(self, Rect2(rect.position, Vector2(maxf(10.0, rect.size.x * clampf(float(row["percent"]) / 100.0, 0.0, 1.0)), 42)), 5, Color(color, 0.17))
	draw_rect(Rect2(rect.position.x, rect.position.y + 6, 3, 30), color)
	Look.draw_body(self, rect.position + Vector2(25, 21), 13, body)
	Look.text_box(self, Rect2(rect.position.x + 48, rect.position.y + 4, rect.size.x - 48 - 92, 34), Balance.body_ko(body), 21, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(self, Rect2(rect.end.x - 92, rect.position.y + 1, 84, 40), "%d%%" % int(row["percent"]), 26, Look.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	var monsters: Array = row["monsters"]
	var shown := mini(4, monsters.size())
	for n in range(shown):
		_draw_monster_thumb(Rect2(rect.position.x + 10 + n * 44.0, rect.position.y + 44, 40, 38), monsters[n])
	draw_line(Vector2(rect.position.x + 10, rect.position.y + 85), Vector2(rect.end.x - 10, rect.position.y + 85), Color(Look.STEEL, 0.16), 1, true)
	var at := rect.position.x + 12.0
	var mid := rect.position.y + 98.0
	var weak: Array = Balance.body_weak(body)
	var immune: Array = Balance.body_immune(body)
	if not weak.is_empty():
		Look.text_left(self, Vector2(at, mid), _tr("weak"), 15, Look.INK_DIM)
		at += Look.text_width(_tr("weak"), 15) + 8.0
		for element in weak:
			Look.draw_elem(self, Vector2(at + 10, mid), 9, String(element))
			at += 25.0
		at += 10.0
	if not immune.is_empty():
		Look.text_left(self, Vector2(at, mid), _tr("immune"), 15, Look.INK_DIM)
		at += Look.text_width(_tr("immune"), 15) + 8.0
		for element in immune:
			Look.draw_elem_x(self, Vector2(at + 10, mid), 9, String(element))
			at += 25.0

## A lesser body of the stage: badge, share, and up to two of its monsters.
func _draw_body_chip(rect: Rect2, row: Dictionary) -> void:
	var body := String(row["body"])
	Look.fill_round(self, rect, 5, Color("#0d1f29"))
	Look.draw_body(self, rect.position + Vector2(19, rect.size.y * 0.5), 10, body)
	Look.text_box(self, Rect2(rect.position.x + 35, rect.position.y + 4, 50, 32), "%d%%" % int(row["percent"]), 19, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	var monsters: Array = row["monsters"]
	var shown := mini(2, monsters.size())
	for n in range(shown):
		_draw_monster_thumb(Rect2(rect.end.x - 5 - (shown - n) * 27.0, rect.position.y + 6, 26, 28), monsters[n])

func _draw_monster_thumb(box: Rect2, monster: Dictionary) -> void:
	if not Look.draw_monster_portrait(self, String(monster.get("id", "")), box):
		Look.draw_body(self, box.get_center(), minf(box.size.x, box.size.y) * 0.32, String(monster.get("body", "")))

## The stage's boss: its render, its name, and on the last stage what beating it means
## (a footer of its own, clear of the render).
func _draw_boss_plate(rect: Rect2, preview: Dictionary, accent: Color, final: bool) -> void:
	var boss: Dictionary = preview["boss"]
	var theme: Dictionary = preview["theme"]
	var edge := Look.GOLD if final else Color("#be797e")
	Look.glass_panel(self, rect, edge, Color(0.10, 0.03, 0.055, 0.96), final)
	var foot_h := 28.0 if final else 0.0
	var inner := Rect2(rect.position, Vector2(rect.size.x, rect.size.y - foot_h))
	# Its render stands on the right, lit from behind in its body's colour.
	var art_w := minf(132.0, inner.size.y + 8.0)
	var art := Rect2(inner.end.x - art_w - 6.0, inner.position.y + 6, art_w, inner.size.y - 10)
	var glow_at := Vector2(art.get_center().x, art.end.y - art.size.y * 0.44)
	for layer in range(12):
		draw_circle(glow_at, minf(art.size.y, art.size.x) * (0.60 - layer * 0.042), Color(accent, 0.022), true, -1, true)
	if not Look.draw_monster_portrait(self, String(boss.get("id", "")), art):
		Look.draw_body(self, art.get_center(), 24, String(boss.get("body", "")))
	var x := rect.position.x + 14.0
	var w := art.position.x - x - 4.0
	Look.text_box(self, Rect2(x, inner.position.y + 7, w, 26), _tr("boss_final") if final else _tr("boss_stage"), 16, Color("#ff9a8c"), HORIZONTAL_ALIGNMENT_LEFT)
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
	Look.wrap_text(self, title, Rect2(x, name_top, w, clampf(room, 36.0, 72.0)), 22, Look.INK, true)
	if body_line:
		Look.draw_body(self, Vector2(x + 11, foot), 10, body)
		Look.text_box(self, Rect2(x + 28, foot - 14, w - 28, 28), Balance.body_ko(body), 17, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	if final:
		var strip := Rect2(rect.position.x + 4, rect.end.y - foot_h - 2, rect.size.x - 8, foot_h - 2)
		draw_rect(strip, Color(Look.GOLD, 0.13))
		draw_line(strip.position, Vector2(strip.end.x, strip.position.y), Color(Look.GOLD, 0.45), 1, true)
		Look.text_box(self, Rect2(strip.position.x + 8, strip.position.y - 1, strip.size.x - 16, 28), _tr("final_note"), 16, Color("#fff0c7"))

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
	draw_circle(centre + Vector2(0, 4), radius + 3, Color(0, 0, 0, 0.34), true, -1, true)
	draw_circle(centre, radius, Color("#0a1a24").lerp(accent, 0.07), true, -1, true)
	draw_arc(centre, radius - 6, 0, TAU, 96, Color(0.55, 0.77, 0.84, 0.10), 1, true)
	var reveal := 1.0 if settled else _ease_out((age - 0.16) / 0.80)
	var width := ArenaGeometry.ROAD_WIDTH / ArenaGeometry.RADIUS * radius
	var stone := Color("#9db2b8").lerp(accent, 0.20)
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
		if line.size() >= 2: draw_polyline(line, Color("#051019"), width + 4.5, true)
	for line in drawn:
		if line.size() >= 2: draw_polyline(line, stone, width, true)
	var plaza := ArenaGeometry.PLAZA_RADIUS / ArenaGeometry.RADIUS * radius
	draw_circle(centre, plaza + 2.2, Color("#051019"), true, -1, true)
	draw_circle(centre, plaza, stone.lightened(0.08), true, -1, true)
	# Chevrons walk each road toward the crystal.
	var spacing := 0.34
	var drift := 0.0 if settled else fposmod(t * 0.13, spacing)
	for road in shape["roads"]:
		var points: PackedVector2Array = road["points"]
		var lengths: PackedFloat32Array = road["lengths"]
		var limit: float = float(road["total"]) * reveal - 0.04
		var s := 0.16 + drift
		while s < limit:
			var i := clampi(lengths.bsearch(s), 1, points.size() - 1)
			var along := (points[i] - points[i - 1]).normalized()
			var span := lengths[i] - lengths[i - 1]
			var at := centre + points[i - 1].lerp(points[i], (s - lengths[i - 1]) / maxf(0.0001, span)) * radius
			var across := Vector2(-along.y, along.x)
			draw_polyline(PackedVector2Array([at - along * 2.8 + across * 4.8, at + along * 2.8, at - along * 2.8 - across * 4.8]), Color(0.03, 0.10, 0.14, 0.50), 2.0, true)
			s += spacing
	draw_arc(centre, radius, 0, TAU, 96, Color(0.60, 0.80, 0.86, 0.80), 1.6, true)
	# The crystal the roads lead to.
	for layer in range(3):
		draw_circle(centre, plaza * (0.95 - layer * 0.2), Color(Look.CRYSTAL, 0.10), true, -1, true)
	_draw_diamond(centre, plaza * 0.62, Color("#1f7fa8"))
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -plaza * 0.62), centre + Vector2(0, plaza * 0.62), centre + Vector2(-plaza * 0.415, 0)]), Color("#77edff"))
	# Gates: a dart outside the rim, pointing in. A plain triangle is nearly equilateral
	# and reads the same at every third of a turn; the notched tail keeps its heading.
	var gates: Array = shape["gates"]
	for lane in range(gates.size()):
		var out: Vector2 = gates[lane]
		var pop := 1.0 if settled else _ease_out((age - 0.10 - lane * 0.07) / 0.22)
		if pop <= 0.0: continue
		if not settled:
			var beat := fposmod(t * 0.7 + lane * 0.23, 1.0)
			draw_arc(centre + out * (radius + 5.0), 9.0 + beat * 9.0, 0, TAU, 20, Color(Look.GATE_MARK, 0.45 * (1.0 - beat)), 1.5, true)
		_draw_gate_dart(centre + out * (radius - 4.0), -out, 18.0 * pop, 9.5 * pop)

## A gate mark: a dart whose tip is at `tip` and which flies along `heading`.
func _draw_gate_dart(tip: Vector2, heading: Vector2, length: float, half: float) -> void:
	if length <= 0.5: return
	var side := Vector2(-heading.y, heading.x)
	var tail := tip - heading * length
	var shape := PackedVector2Array([tip, tail + side * half, tail + heading * length * 0.30, tail - side * half])
	draw_polyline(shape + PackedVector2Array([tip]), Color("#051019"), 4.0, true)
	draw_colored_polygon(shape, Look.GATE_MARK)

func _draw_rite() -> void:
	_shade()
	Look.text_box(self, Rect2(194, 106, 760, 50), _tr("rite_title"), 36, Look.GOLD)
	if Arena.phase == Arena.Phase.SWAP:
		_draw_summon_result()
		return
	Look.text_box(self, Rect2(180, 162, 920, 39), _tr("rite_hint"), 21, Look.INK_DIM)
	var center := Vector2(434, 446)
	var scale_value := 0.82
	RiteBoard.draw_base(self, center, scale_value, t)
	RiteBoard.draw_gate(self, center, scale_value, t)
	RiteBoard.draw_core(self, center, scale_value, t)
	for ring in range(mini(Rite.RINGS, Arena.orbit.size())):
		var final_angle := Rite.angle(ring, int(Arena.orbit[ring]))
		var duration := 0.72 + ring * 0.20
		var q := clampf(_rite_age / duration, 0, 1)
		var spinning := ring in _spin_rings and q < 1
		var angle := final_angle + (1.0 if ring % 2 == 0 else -1.0) * TAU * pow(1 - q, 3) * 2.2 if spinning else final_angle
		var at := RiteBoard.point(center, ring, angle, scale_value)
		if spinning: RiteBoard.draw_trail(self, center, ring, angle, 0.34, scale_value)
		RiteBoard.draw_star(self, at, RiteBoard.SPIN if spinning else RiteBoard.look_of(ring, int(Arena.orbit[ring])), scale_value, t)
	var preview: Dictionary = Arena.rite_preview()
	Look.material_panel(self, Rect2(736, 244, 384, 374), Look.BG_DEEP.lerp(Look.PANEL, 0.45), Look.PANEL_EDGE)
	Look.text_box(self, Rect2(782, 271, 292, 38), _tr("free_summon") if Arena.heroes.is_empty() else _tr("heroes"), 23, Look.INK_DIM)
	Look.draw_rarity(self, Vector2(928, 345), int(preview.get("tier", 1)), 15)
	Look.text_box(self, Rect2(782, 368, 292, 57), Look.star_label(int(preview.get("tier", 1))), 45, Look.GOLD)
	Look.text_box(self, Rect2(782, 452, 292, 29), "문 안의 별 %d개" % int(preview.get("stars", 1)), 20, Look.INK_DIM)
	Look.text_box(self, Rect2(782, 494, 292, 42), _tr("summons_cost") + "  %d G" % (0 if Arena.summon_count == 0 else Arena.summon_cost()), 20, Look.INK_DIM)
	var cost := Arena.respin_cost()
	var suffix := "무료 %d" % Arena.respins_left() if cost == 0 else "%d G" % cost
	ui.button(self, Rect2(168, 678, 416, 62), I18n.t("다시 돌리기") + "  " + I18n.t(suffix), "rite:respin", Arena.can_respin(), Look.GREEN, 22)
	ui.button(self, Rect2(616, 678, 488, 62), _tr("summon_confirm"), "rite:confirm", not Arena.eligible_units().is_empty(), Look.GOLD, 25)

func _draw_summon_result() -> void:
	var result: Dictionary = Arena.summon_result
	var unit: Dictionary = result.get("unit", Arena.last_unit)
	if unit.is_empty():
		Look.text_box(self, Rect2(210, 340, 860, 60), _tr("pool_done"), 28, Look.GOLD)
		ui.button(self, Rect2(344, 682, 592, 56), _tr("result_continue"), "close", true, Look.GOLD, 24)
		return
	var grown := String(result.get("kind", "new")) == "growth"
	var after := int(result.get("after_tier", result.get("tier", Arena.last_tier)))
	var before := int(result.get("before_tier", after))
	var hero := {"unit": unit, "tier": after}
	var portrait := Rect2(216, 215, 374, 390)
	var glow := 0.5 + sin(t * 3) * 0.1
	draw_circle(portrait.get_center(), 158, Color(Look.GOLD, 0.035 + glow * 0.025))
	Art.draw_unit_fit(self, unit, portrait, Color.WHITE, after)
	Look.draw_rarity(self, Vector2(403, 628), after, 10)
	Look.text_box(self, Rect2(655, 237, 448, 45), _tr("hero_grown") if grown else _tr("new_hero"), 30, Look.GOLD)
	Look.text_box(self, Rect2(655, 300, 448, 62), Look.unit_name(unit), 36, Look.INK)
	Look.text_box(self, Rect2(655, 374, 448, 45), Look.star_label(before) + "  >  " + Look.star_label(after) if grown else Look.star_label(after), 32, Look.GOLD)
	var maximum := bool(result.get("maxed", false))
	if maximum:
		Look.fill_round(self, Rect2(731, 445, 294, 58), 6, Color("#3a3929"))
		Look.text_box(self, Rect2(743, 454, 270, 39), _tr("maxed"), 28, Look.GOLD)
	else:
		var points := int(result.get("growth_points", 0))
		hero["growth_points"] = points
		var needed := Arena.growth_needed(hero)
		Look.text_box(self, Rect2(655, 444, 448, 32), _tr("growth_points") + ("  +%d" % int(result.get("added_points", 0)) if grown else ""), 23, Look.CRYSTAL)
		_bar(Rect2(710, 504, 338, 12), float(points) / maxf(1, needed), Look.CRYSTAL)
		Look.text_box(self, Rect2(710, 528, 338, 32), "%d / %d" % [points, needed], 23, Look.INK)
	Look.text_box(self, Rect2(655, 590, 448, 35), _tr("bench") if String(result.get("where", "field")) == "bench" else _tr("heroes"), 21, Look.INK_DIM)
	ui.button(self, Rect2(344, 682, 592, 56), _tr("result_continue"), "close", true, Look.GOLD, 24)

func _draw_shop() -> void:
	_shade()
	Look.text_box(self, Rect2(152, 103, 680, 50), _tr("shop") + "  %d G" % Arena.gold, 33, Look.GOLD)
	ui.tab(self, Rect2(176, 173, 448, 45), _tr("upgrades"), "shop:tab:upgrades", _shop_tab == "upgrades", 24)
	ui.tab(self, Rect2(656, 173, 448, 45), _tr("passives"), "shop:tab:passives", _shop_tab == "passives", 24)
	if _shop_tab == "upgrades": _draw_upgrades()
	else: _draw_passives()
	ui.button(self, Rect2(410, 697, 460, 50), _tr("resume"), "close", true, Look.GOLD, 23)

func _draw_upgrades() -> void:
	for i in range(Balance.UPGRADES.size()):
		var data: Dictionary = Balance.UPGRADES[i]
		var id := String(data["id"])
		var level := Arena.lv(id)
		var maximum := Balance.upgrade_maxed(id, level)
		var price := Balance.upgrade_cost(id, level)
		var rect := Rect2(112, 234 + i * 64, 1056, 54)
		Look.fill_round(self, rect, 4, Color("#23363d") if i % 2 == 0 else Color("#1b2e35"))
		Look.text_box(self, Rect2(rect.position + Vector2(17, 5), Vector2(230, 42)), String(data["ko"]), 22, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
		Look.text_box(self, Rect2(rect.position + Vector2(267, 5), Vector2(200, 42)), Balance.upgrade_show(id, Arena.stat_now(id)), 22, Look.CRYSTAL)
		Look.text_box(self, Rect2(rect.position + Vector2(470, 5), Vector2(35, 42)), ">", 21, Look.INK_DIM)
		Look.text_box(self, Rect2(rect.position + Vector2(512, 5), Vector2(216, 42)), _tr("maxed") if maximum else Balance.upgrade_show(id, Arena.up_at(id, level + 1)), 21, Look.INK_DIM)
		ui.button(self, Rect2(rect.position + Vector2(807, 6), Vector2(234, 44)), _tr("maxed") if maximum else "%d G" % price, "upgrade:" + id, not maximum and Arena.gold >= price, Look.GOLD, 22)

func _passives() -> Array:
	var items: Array = []
	var seen: Dictionary = {}
	for id in Arena.owned_passives:
		items.append(Balance.passive_by_id(id))
		seen[id] = true
	for item in Arena.offer_passives(3):
		if not seen.has(item["id"]): items.append(item)
	return items

func _draw_passives() -> void:
	var items := _passives()
	_passive_page = clampi(_passive_page, 0, maxi(0, (items.size() - 1) / 8))
	for n in range(8):
		var index := _passive_page * 8 + n
		if index >= items.size(): break
		var passive: Dictionary = items[index]
		var id := String(passive["id"])
		var owned := Arena.owns_passive(id)
		var selected := Arena.has(id)
		var can := Arena.gold >= int(passive["cost"]) if not owned else selected or not Arena.passive_full()
		var rect := Rect2(113 + (n % 4) * 269, 239 + (n / 4) * 217, 242, 152)
		Look.draw_passive_card(self, rect, passive, selected, can)
		var label := I18n.t("해제") if selected else I18n.t("활성화") if owned else "%d G" % int(passive["cost"])
		ui.button(self, Rect2(rect.position.x, rect.end.y + 5, rect.size.x, 42), label, "passive:" + id, can, Look.CRYSTAL if owned else Look.GOLD, 19)
	ui.button(self, Rect2(116, 689, 70, 52), "<", "passive:prev", _passive_page > 0, Look.PANEL_EDGE, 25)
	ui.button(self, Rect2(1094, 689, 70, 52), ">", "passive:next", (_passive_page + 1) * 8 < items.size(), Look.PANEL_EDGE, 25)

func _draw_bench() -> void:
	_shade()
	Look.text_box(self, Rect2(145, 103, 760, 50), _tr("bench"), 33, Look.GOLD)
	Look.text_box(self, Rect2(176, 159, 928, 30), _tr("field_select"), 21, Look.INK_DIM)
	for i in range(Arena.heroes.size()):
		var rect := Rect2(138 + i * 171, 202, 151, 151)
		HeroCard.draw(self, rect, Arena.heroes[i], i == _field_choice)
		ui.zone(rect.grow(4), "bench:field:%d" % i)
	Look.text_box(self, Rect2(176, 374, 928, 30), _tr("bench_select"), 21, Look.INK_DIM)
	if Arena.bench.is_empty():
		Look.text_box(self, Rect2(254, 461, 772, 90), _tr("bench_empty"), 29, Look.INK_DIM)
	else:
		_bench_page = clampi(_bench_page, 0, maxi(0, (Arena.bench.size() - 1) / 6))
		for n in range(6):
			var index := _bench_page * 6 + n
			if index >= Arena.bench.size(): break
			var rect := Rect2(138 + n * 171, 429, 151, 174)
			var hero: Dictionary = Arena.bench[index]
			HeroCard.draw(self, rect, hero, index == _bench_choice)
			ui.zone(rect.grow(4), "bench:reserve:%d" % index)
			var maximum := int(hero["tier"]) >= Balance.TIER_ATK.size() - 1
			var needed := Arena.growth_needed(hero)
			Look.text_box(self, Rect2(rect.position.x - 1, 615, rect.size.x + 2, 24), _tr("maxed") if maximum else "%d / %d" % [int(hero.get("growth_points", 0)), needed], 17, Look.GOLD if maximum else Look.CRYSTAL)
	ui.button(self, Rect2(98, 648, 66, 45), "<", "bench:prev", _bench_page > 0, Look.PANEL_EDGE, 25)
	ui.button(self, Rect2(1116, 648, 66, 45), ">", "bench:next", (_bench_page + 1) * 6 < Arena.bench.size(), Look.PANEL_EDGE, 25)
	ui.button(self, Rect2(220, 677, 392, 65), _tr("resume"), "close", true, Look.PANEL_EDGE, 22)
	ui.button(self, Rect2(668, 677, 392, 65), _tr("swap"), "bench:swap", _bench_choice >= 0 and _field_choice >= 0, Look.GOLD, 25)

## The run's result. How far the stage chain was walked is the headline: one large
## number over the run's ten steps; the line above it says how the run ended.
##
## A defeat without the blessing adds one quiet strip *under* the two buttons. It is
## never the primary action: the gold button stays "try again", the strip's own button
## is a secondary one and only opens the purchase sheet, where the price is.
##
## Entrance (only for a result this screen saw arrive, and only while it runs): the shade
## comes in first, then the card rises out of it, the headline number settles from a
## little larger, and after a win a glint crosses the ten lit steps as it did on the last
## boss's banner. Until the card has arrived its buttons do not answer.
func _draw_result() -> void:
	var age := _result_age()
	draw_rect(Look.SCREEN, Color(0.018, 0.04, 0.065, 0.84 * _ease_out(age / RESULT_SHADE_IN)))
	ui.zone(Look.SCREEN, "modal:block")
	var arrive := _ease_out((age - RESULT_CARD_AT) / RESULT_CARD_IN)
	if arrive <= 0.0: return
	var rise := Vector2(0, (1.0 - arrive) * 14.0)
	draw_set_transform(rise, 0, Vector2.ONE)
	var sim = Arena.sim
	var won: bool = sim != null and sim.won
	var offer: bool = not won and sim != null and sim.revives_left() > 0 and Store.has_shop() and not Store.owns(Store.GUARDIAN)
	var total := Balance.ARENA_STAGES
	var height := 574.0 if offer else 444.0
	var card := Rect2(260, 70 + (730 - height) * 0.5, 760, height)
	var mid := card.get_center().x
	var y := card.position.y
	Look.fill_round(self, Rect2(card.position + Vector2(0, 7), card.size), 8, Color(0, 0, 0, 0.40))
	Look.glass_panel(self, card, Look.GOLD if won else Color("#81a5b6"), Color(0.028, 0.07, 0.105, 0.97), won)
	# How it ended.
	var state_color := Look.GOLD if won else Color("#ff9488")
	var state := _tr("victory") if won else _tr("defeat")
	var state_box := Rect2(card.position.x + 76, y + 20, card.size.x - 152, 46)
	var state_size := Look.text_box(self, Rect2(state_box.position.x + 16, state_box.position.y, state_box.size.x - 16, state_box.size.y), state, 30, state_color)
	_draw_result_crystal(Vector2(mid + 8.0 - Look.text_width(state, state_size) * 0.5 - 22.0, state_box.get_center().y + 3.0), 9.0, won)
	# The headline: the stage reached, as large as the card allows.
	var caption := _tr("completed") if won else _tr("reached")
	var caption_y := y + 92.0
	Look.text_center(self, Vector2(mid, caption_y), caption, 20, Look.INK_DIM)
	var caption_half := Look.text_width(caption, 20) * 0.5 + 16.0
	for side in [-1.0, 1.0]:
		draw_line(Vector2(mid + side * caption_half, caption_y), Vector2(mid + side * (caption_half + 96.0), caption_y), Color(Look.GOLD_DEEP, 0.75), 1.4, true)
		_draw_diamond(Vector2(mid + side * (caption_half + 96.0), caption_y), 4.5, Look.GOLD_DEEP)
	# "7탄" and "Stage 7" put the number on different sides of the word: split the
	# catalog's own template and set the number large between its two halves.
	var template := _tr("stage_n")
	var lead := template.get_slice("%d", 0)
	var tail := template.get_slice("%d", 1) if template.contains("%d") else ""
	var number := str(Arena.stage)
	var of_total := " / %d" % total
	var number_w := Look.text_width(number, 104)
	var lead_w := Look.text_width(lead, 40) + (10.0 if not lead.strip_edges().is_empty() else 0.0)
	var tail_w := Look.text_width(tail, 40)
	var of_w := Look.text_width(of_total, 30)
	var row_y := y + 166.0
	var x := mid - (lead_w + number_w + tail_w + of_w) * 0.5
	if won:
		# A warm light behind the number; many thin layers so no ring shows.
		for layer in range(18):
			draw_circle(Vector2(x + lead_w + number_w * 0.5, row_y + 2.0), 132.0 - layer * 6.5, Color(Look.GOLD, 0.0075), true, -1, true)
	var figure := Color("#fff0c7") if won else Look.GOLD
	if not lead.is_empty(): Look.text_left(self, Vector2(x, row_y + 20.0), lead, 40, figure)
	# The number settles from a little larger, about its own middle.
	var land := 1.0 + 0.14 * (1.0 - _ease_out((age - RESULT_CARD_AT) / 0.34))
	var number_mid := Vector2(x + lead_w + number_w * 0.5, row_y)
	draw_set_transform(rise + number_mid * (1.0 - land), 0, Vector2(land, land))
	Look.text_left(self, Vector2(x + lead_w, row_y), number, 104, figure)
	draw_set_transform(rise, 0, Vector2.ONE)
	if not tail.is_empty(): Look.text_left(self, Vector2(x + lead_w + number_w + 2.0, row_y + 20.0), tail, 40, figure)
	Look.text_left(self, Vector2(x + lead_w + number_w + tail_w + 2.0, row_y + 24.0), of_total, 30, Look.INK_DIM)
	# After a win the glint of the last boss's banner crosses the ten steps once more.
	var glint := (age - RESULT_CARD_AT - RESULT_CARD_IN) / 0.50 if won else -1.0
	Look.draw_stage_track(self, Rect2(mid - 220, y + 236, 440, 12), Arena.stage, total, total if won else Arena.stage - 1, 0.0, not won, 1.0, glint)
	# Where it ended, and what the run did.
	if sim != null:
		var theme: Dictionary = Arena.theme_for(1)
		var field := String(theme.get("ko", ""))
		var field_size := Look.fit_size(field, 22, Vector2(card.size.x - 200, 34))
		var field_w := Look.text_width(field, field_size)
		Look.draw_body(self, Vector2(mid - field_w * 0.5 - 6.0, y + 278), 11, String(theme.get("main_body", "")))
		Look.text_left(self, Vector2(mid - field_w * 0.5 + 14.0, y + 278), field, field_size, Look.INK)
		# What the run did, as one centred row: kills, the best rank, and the blessings it
		# used. An owner who is defeated has used them all, and the row says so: that is
		# why the crystal did not reform this time.
		var stats: Array = [[_tr("kills") + "  %d" % Arena.kills, Look.INK_DIM, false]]
		if Arena.best_tier >= 0:
			stats.append([I18n.t("최고 등급") + "  " + I18n.t(Look.star_label(Arena.best_tier)), Look.INK_DIM, false])
		if sim.revives >= Balance.ARENA_REVIVE_USES and not won:
			stats.append([_tr("revives_spent") % sim.revives, Color("#ff9a8c").lerp(Look.INK_DIM, 0.35), true])
		elif sim.revives > 0:
			stats.append([_tr("revives_used") % sim.revives, Look.INK_DIM, true])
		_draw_stat_row(Vector2(mid, y + 320), card.size.x - 80.0, stats)
	var buttons := y + 356.0
	# The offer registers first so the two run buttons always win a shared edge.
	if offer:
		var strip := Rect2(card.position.x + 40, buttons + 62 + 28, card.size.x - 80, 100)
		draw_line(Vector2(strip.position.x, strip.position.y - 14), Vector2(strip.end.x, strip.position.y - 14), Color(Look.PANEL_EDGE, 0.40), 1, true)
		Look.fill_round(self, strip, 6, Color(0.01, 0.03, 0.05, 0.72))
		var quiet := Look.GOLD.lerp(Look.INK_DIM, 0.30)
		StoreView.draw_icon(self, strip.position + Vector2(48, 50), Store.GUARDIAN, 26, quiet)
		var text_x := strip.position.x + 92.0
		var text_w := strip.size.x - 92.0 - 232.0
		var product := Arena.label("store.guardian.name")
		var name_size := Look.text_box(self, Rect2(text_x, strip.position.y + 8, text_w, 30), product, 19, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
		# The price is on the strip itself: nothing about the offer waits behind a tap.
		var price := Look.price_text(Store.price(Store.GUARDIAN))
		var name_w := Look.text_width(product, name_size)
		if not price.is_empty() and text_w - name_w > 60.0:
			Look.price_box(self, Rect2(text_x + name_w + 12.0, strip.position.y + 8, text_w - name_w - 12.0, 30), price, 17, quiet, HORIZONTAL_ALIGNMENT_LEFT)
		Look.wrap_text(self, _tr("revive_offer") % Balance.ARENA_REVIVE_USES, Rect2(text_x, strip.position.y + 38, text_w, 56), 16, Look.INK_DIM, true)
		ui.button(self, Rect2(strip.end.x - 216, strip.position.y + 22, 200, 56), _tr("revive_now"), "result:guardian", true, Look.GOLD_DEEP, 20)
	ui.button(self, Rect2(card.position.x + 40, buttons, 328, 62), _tr("home"), "result:home", main != null, Look.PANEL_EDGE, 25)
	ui.button(self, Rect2(card.end.x - 368, buttons, 328, 62), _tr("retry"), "result:retry", true, Look.GOLD, 25)
	if arrive < 1.0:
		# Still rising: the shade's own colour lies over the card and thins out, and one
		# more blocking zone on top swallows taps until the card has arrived.
		draw_rect(card.grow(12.0), Color(0.018, 0.04, 0.065, 1.0 - arrive))
		ui.zone(Look.SCREEN, "modal:block")
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

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
			_draw_diamond(Vector2(x - gap * 0.5, at.y), 4, Color("#587080"))
		if bool(entry[2]):
			StoreView.draw_icon(self, Vector2(x + 9, at.y), Store.GUARDIAN, 9, tone)
			x += 24.0
		var words := String(entry[0])
		var words_w := Look.text_width(words, size)
		Look.text_box(self, Rect2(x - 1, at.y - 16, words_w + 2, 32), words, size, tone, HORIZONTAL_ALIGNMENT_LEFT)
		x += words_w + gap

## Seconds since the result opened on this screen; its entrance runs on `t`. A screen
## that opens straight onto a result (a restored run, a tool) or is held still shows the
## panel settled: the entrance only plays for a result this screen saw arrive.
func _result_age() -> float:
	var sim = Arena.sim
	var key := "%d:%d:%s:%d" % [Arena.run_seed, Arena.stage, sim != null and sim.won, sim.revives if sim != null else 0]
	if key != _result_key:
		_result_key = key
		_result_t0 = t if _field_seen else -100.0
	return 99.0 if _settled() else t - _result_t0

## The life crystal on the result line: whole and lit after a win, split in two after a
## defeat (Look.draw_crystal's broken stub is too dark to read at this size on a dark card).
func _draw_result_crystal(at: Vector2, r: float, won: bool) -> void:
	if won:
		draw_circle(at, r * 2.3, Color(Look.CRYSTAL, 0.13), true, -1, true)
		Look.draw_crystal(self, at, r, true, 0.0)
		return
	var edge := Color("#ff9488")
	var face := Color("#4a2d38")
	var left := PackedVector2Array([at + Vector2(-0.10, -1.50) * r, at + Vector2(-0.86, -0.20) * r, at + Vector2(-0.50, 1.00) * r,
		at + Vector2(-0.08, 0.30) * r, at + Vector2(-0.36, -0.30) * r])
	var right := PackedVector2Array([at + Vector2(0.24, -1.20) * r, at + Vector2(0.98, 0.00) * r, at + Vector2(0.60, 1.18) * r,
		at + Vector2(0.20, 0.52) * r, at + Vector2(0.04, -0.34) * r])
	for shard in [left, right]:
		draw_colored_polygon(shard, face)
		draw_polyline(shard + PackedVector2Array([shard[0]]), edge, 1.3, true)

func draw_help(ci: CanvasItem) -> void:
	var keys := ["control", "defense", "growth", "boss"]
	var colors := [Look.GOLD, Look.CRYSTAL, Look.GREEN, Look.RED]
	for i in range(keys.size()):
		var rect := Rect2(270, 241 + i * 83, 740, 74)
		Look.fill_round(ci, rect, 4, Color("#162830"))
		ci.draw_rect(Rect2(rect.position.x, rect.position.y, 4, rect.size.y), colors[i])
		Look.wrap_text(ci, Arena.label("arena.rules." + keys[i]), Rect2(rect.position + Vector2(14, 6), rect.size - Vector2(28, 12)), 21, Look.INK)
	Look.text_box(ci, Rect2(281, 592, 718, 47), _tr("save_hint"), 19, Look.INK_DIM)

func _bar(rect: Rect2, value: float, color: Color) -> void:
	Look.fill_round(self, rect.grow(2), 3, Color("#08141b"))
	Look.fill_round(self, rect, 2, Color("#30434a"))
	var width := clampf(value, 0, 1) * rect.size.x
	if width > 0: Look.fill_round(self, Rect2(rect.position, Vector2(width, rect.size.y)), 2, color)

func _clock(value: float) -> String:
	var seconds := maxi(0, int(value))
	return "%02d:%02d" % [seconds / 60, seconds % 60]
