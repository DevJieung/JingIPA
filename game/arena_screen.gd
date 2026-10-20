extends Node2D
class_name ArenaScreen

## The run's current battlefield, with the stage card, the jewel box, the level-up popup and
## the constellation map, reserves and the purchase sheet over its world. This script owns the
## input, the run's clocks and the draw order; the pictures are its views (ArenaHud,
## ArenaCards, ArenaBoxView, ArenaTalentView) and ArenaHelp for the rules page. The state the
## views read is the contract of build/feedback-2026-10-19/PLAN.md §4:
##   popup  talent_entrance_age() · talent_armed() · talent_arm_progress() · talent_followup ·
##          talent_pressed · pick_hold_age() · pick_hold_id · pick_hold_offer
##   map    talent_map · map_focus · map_node
##   box    box_age() · box_deal_age() · box_pick_age() · box_ready() · box_skip()
##   aim    aiming() · aim_pixel · aim_point() · aim_valid()
##   skills skill_ready_age(id) · result can_next_stage()
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
## Seconds the field shows the star that was just joined, after the popup closes.
const PICK_BANNER := 1.8
## The level-up popup's input lock (F1): its pick buttons answer only once the popup has
## settled — TALENT_ARM_AT seconds into the offer's entrance (ArenaTalentView fills the
## buttons' rims to gold over that time), TALENT_REARM_AT for a following offer in the open
## popup or the way back from the map — and only after TALENT_ARM_DRAWS pictures, so one long
## frame cannot open them. A pick commits when the finger that pressed an armed button lifts
## on it; a touch that began before the popup armed never picks.
const TALENT_ARM_AT := 0.90
const TALENT_REARM_AT := 0.45
const TALENT_ARM_DRAWS := 3
## After a pick the battle waits this long while the chosen star flies into its
## constellation (Constellation.draw_pick_flourish).
const PICK_HOLD := Constellation.PICK_TIME
## The jewel box answers once its ceremony has settled — the view knows its beats
## (ArenaBoxView.is_ready(): 2.8 s for a repeat box up to 7.6 s for a 5-star jackpot) — and
## only after BOX_ARM_DRAWS pictures of the deal (or of the pick): the view learns a new
## deal or a pick when it draws it.
const BOX_ARM_DRAWS := 3
## Modals under which the battlefield's 3D view keeps rendering every frame. Under every
## other modal it keeps its last picture (battery saver O8a; ArenaView.set_live). None needs
## a moving field today.
const LIVE_MODALS: Array[String] = []
## No finger: the joystick, the aim and a held button all use this.
const NO_POINTER := -99

var main = null
var ui := Ui.new()
var view_3d := ArenaView.new()
## What the screen draws, one view per area, each drawing on this canvas from _draw:
## the HUD (top strip, command rail, minimap, bars, stick, field banners), the cards
## (battlefield card, reserve, result), the summon modal and the constellation views.
var hud := ArenaHud.new(self)
var cards := ArenaCards.new(self)
var box_view := ArenaBoxView.new(self)
var talent_view := ArenaTalentView.new(self)
## Battle speed 1/2/3. Persists in settings like the legacy battle screen (Save.speed);
## the simulator, the 3D world and its effects all run on the scaled dt, so nothing
## presentation-side keeps real time while the battle runs faster.
var speed := 1.0
var t := 0.0
var joystick := Vector2.ZERO
var joy_origin := Vector2.ZERO
var _joy_selection := -1
var _joy_pointer := NO_POINTER
var _draw_dt := 0.0
var _modal_seen := ""
var _phase_seen := -1
var store := StoreView.new()
var _revives_seen := 0
var _revive_age := 99.0
var _bench_page := 0
var _bench_choice := -1
var _field_choice := -1
## ★ Old summon clock: capture tools still set it; nothing reads it (the box runs on
## box_deal_age / box_pick_age).
var _rite_age := 9.0
## The battlefield card's clock: when it opened (its entrance runs on `t`). What it
## lists and the road diagram of its layout are ArenaCards' memory.
var _card_key := ""
var _card_t0 := 0.0
var _card_draws := 0
## The result panel's entrance: whether this screen has drawn the battle (a screen that
## opens straight onto a result shows it settled), which result it is, and when it opened.
var _field_seen := false
var _result_key := ""
var _result_t0 := -100.0

## The level-up popup (F1) and the constellation map (F2), screen side. The map is up from
## the popup's map button (the offer waits under it) or as the rail's viewer.
var talent_map := false
## The constellation the map zooms into ("" = the overview), and the node it details.
var map_focus := ""
var map_node := ""
## The pick button held down (its zone id) until the finger lifts: the pressed look.
var talent_pressed := ""
## The offer on screen follows a pick in the same popup: only its cards come in again.
var talent_followup := false
## The star just picked and the offer it came from, while the battle holds for its flourish
## (pick_hold_age() >= 0). The run has the pick already.
var pick_hold_id := ""
var pick_hold_offer: Array = []
var _pick_hold_t0 := -1.0
## Which offer the popup's clocks belong to, and how many offers this popup has shown. A
## pick bumps the serial, so a following offer restarts even when it repeats the last one.
var _talent_key := ""
var _talent_serial := 0
var _talent_offers := 0
var _talent_clock := Clock.new()
var _arm_clock := Clock.new()
var _arm_at := TALENT_ARM_AT
var _map_from_offer := false

## The jewel box's clocks (F11): its arrival, its deal (again at every reroll), its pick.
var _box_clock := Clock.new()
var _box_deal := Clock.new()
var _box_pick := Clock.new()

## The starburst's aim (F6): its button arms it, a press on the battlefield takes the spot
## (the finger may slide it) and the release casts there. Where the finger or cursor is.
var aim_pixel := Vector2.INF
var _aim := ""
var _aim_pointer := NO_POINTER
var _aim_shown := false

## A button that commits on release (the level-up picks, the box's cards): the finger that
## pressed it and its zone.
var _press_pointer := NO_POINTER
var _press_zone := ""

## When each common skill last became ready to cast (O2, skill_ready_age).
var _ready_seen: Dictionary = {}
var _ready_t0: Dictionary = {}

## A presentation clock on the screen's `t` that starts on its second picture after a
## restart: the frame that opens something also builds what it shows, and that one long
## frame must not swallow the entrance (the battlefield card's _card_age does the same).
class Clock:
	var t0 := 0.0
	## Pictures since the restart; below 0 while stopped.
	var draws := -1
	func restart() -> void:
		draws = 0
	func stop() -> void:
		draws = -1
	func running() -> bool:
		return draws >= 0
	func tick(now: float) -> void:
		if draws < 0: return
		draws += 1
		if draws <= 2: t0 = now
	## Seconds since it started (0 before its first picture), or -1 while stopped.
	func age(now: float) -> float:
		if draws < 0: return -1.0
		return now - t0 if draws > 0 else 0.0
	## Put the clock at `seconds` now; the next picture does not restart it.
	func set_age(now: float, seconds: float) -> void:
		t0 = now - seconds
		draws = maxi(draws, 2)

func _ready() -> void:
	get_tree().process_frame.connect(_guard_frame)
	view_3d.battle_box = BATTLEFIELD
	view_3d.minimap_box = MINIMAP
	# The battle frame (ArenaFrame, a LINEAR child drawn behind this screen) paints the
	# night under the whole field from the first frame; _draw never clears over it.
	view_3d.frame_for(self).present(null, FIELD)
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
	_refresh_live()
	queue_redraw()

func _process(dt: float) -> void:
	t += dt
	_revive_age += dt
	_track_modal()
	_draw_dt = 0.0
	if _pick_hold_t0 >= 0.0 and t - _pick_hold_t0 >= PICK_HOLD:
		_end_pick_hold()
	if _battle_runs():
		var sdt := dt * speed
		_step_battle(sdt)
		_draw_dt = sdt
		# A window the step opened (the level-up popup when a preparation begins, the
		# result) is taken in before its first picture: the stick lets go, no button stays
		# pressed, and the popup's clock starts with that picture.
		_track_modal()
	_guard_aim()
	# The blessing revives up to Balance.ARENA_REVIVE_USES times a run; a new run starts
	# the count again, so only a count that went up is a revival to announce.
	var used: int = Arena.sim.revives if Arena.sim != null else 0
	if used != _revives_seen:
		if used > _revives_seen:
			_revive_age = 0.0
			Sfx.play("summon_burst")
		_revives_seen = used
	queue_redraw()

## Whether the battle steps this frame: no window, menu or shop over it, and no pick
## flourish holding it.
func _battle_runs() -> bool:
	return Arena.sim != null and Arena.modal.is_empty() and not _menu_open() and not store.opened and _pick_hold_t0 < 0.0

## One frame of the battle: the selected hero's move, then the simulator (the frame bench
## times this).
func _step_battle(sdt: float) -> void:
	Arena.sim.move_selected(_ground_direction(_push()), sdt)
	Arena.sim.step(sdt)

## Movement push in screen space: the touch stick, or the keyboard / gamepad on desktop
## (arrow keys, WASD, D-pad and left stick) while no stick is held.
func _push() -> Vector2:
	if _joy_pointer != NO_POINTER: return joystick
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

## A window opened, closed or moved on (Arena.modal / phase): fingers let go, the aim ends,
## the music follows, and the window's own clocks and state start over.
func _track_modal() -> void:
	if _modal_seen == Arena.modal and _phase_seen == Arena.phase: return
	# A screen whose time and input are stopped (Main's fade taking it away — 「재도전」 and
	# 「다음 STAGE」 open the stage on a fresh screen — or the menu over it) takes the change in
	# when it is back, if ever: the next stage's music and sting are the new screen's.
	if not is_processing() and not is_processing_input(): return
	var previous := _modal_seen
	_modal_seen = Arena.modal
	_phase_seen = Arena.phase
	cancel_joystick()
	cancel_aim()
	_release_press()
	ui.pressed = ""
	if Arena.modal == "box" and previous != "box":
		_open_box()
		Sfx.play_music("ritual")
	elif Arena.modal != previous:
		Sfx.play_music("camp" if Arena.theme_index < 0 else "theme_" + String(Arena.theme_for(1)["id"]))
		if Arena.modal == "stage":
			Sfx.play("theme")
			_load_stage_monsters()
	if previous == "box" and Arena.modal != "box":
		box_view.release()
	if Arena.modal == "bench" and previous != "bench":
		_field_choice = clampi(Arena.selected, 0, maxi(0, Arena.heroes.size() - 1))
		_bench_choice = -1
		_bench_page = 0
	if Arena.modal == "talent" and previous != "talent":
		_reset_talent()
		# With nothing to pick the popup is the rail's viewer: the map.
		talent_map = Arena.talent_offer.is_empty()
		if not talent_map: Sfx.play("theme")
	elif previous == "talent" and Arena.modal != "talent":
		_reset_talent()
	_refresh_live()

## The battlefield's 3D view renders every frame only while the battle shows (O8a): under a
## window, the shop or the menu it keeps its last picture (a new battlefield behind its card
## still shows once: ArenaView.draw_arena).
func _refresh_live() -> void:
	view_3d.set_live((Arena.modal.is_empty() or LIVE_MODALS.has(Arena.modal)) and not store.opened and not _menu_open())

## While the battlefield card is up, load the stage's monsters (every wave) and its boss,
## and let the previous stage's types go. Without this the first spawn of a type, and the
## boss entrance, read the model from storage in the middle of the fight.
func _load_stage_monsters() -> void:
	var preview := Arena.stage_preview(Arena.stage)
	var ids: Array = []
	for row in preview["rows"]:
		for monster in row["monsters"]:
			if not ids.has(String(monster["id"])): ids.append(String(monster["id"]))
	var boss: Dictionary = preview.get("boss", {})
	if not boss.is_empty() and not ids.has(String(boss["id"])): ids.append(String(boss["id"]))
	NativeMonsterModel.keep_only(ids)

func _input(e: InputEvent) -> void:
	if _menu_open():
		cancel_joystick()
		cancel_aim()
		_release_press()
		return
	if e is InputEventMouseButton and e.device < 0: return
	if e is InputEventScreenTouch:
		if e.canceled: _cancel_pointer(e.index)
		else: _pointer(e.index, e.position, e.pressed)
		return
	if e is InputEventScreenDrag:
		if e.index == _aim_pointer:
			aim_pixel = e.position
			get_viewport().set_input_as_handled()
		elif e.index == _joy_pointer:
			_set_joystick(e.position)
			get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_pointer(-1, e.position, e.pressed)
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and aiming():
		cancel_aim()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseMotion and e.device >= 0 and aiming() and _aim_pointer in [NO_POINTER, -1]:
		# Desktop: the reticle follows the cursor before the press (a preview) and while held.
		aim_pixel = e.position
	if e is InputEventMouseMotion and _joy_pointer == -1:
		_set_joystick(e.position)
		get_viewport().set_input_as_handled()
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		if store.opened:
			store.close()
			_refresh_live()
			get_viewport().set_input_as_handled()
		elif back():
			get_viewport().set_input_as_handled()
		elif Arena.modal in ["talent", "bench"]:
			Arena.close_modal()
			get_viewport().set_input_as_handled()

## The back button (Main._notification) and Esc: the screen's own layers, top first — the
## aim, the pick's flourish, the map (zoomed → overview → closed: back to the offer it was
## opened from, or out of the rail's viewer), the box's ceremony (skipped) and its result
## (closed). False when nothing of the screen's was there to take back; the shop is closed by
## Main / _input themselves.
func back() -> bool:
	if store.opened:
		return false
	if aiming():
		cancel_aim()
		return true
	if _pick_hold_t0 >= 0.0:
		return true
	if Arena.modal == "talent" and talent_map:
		if not map_focus.is_empty():
			map_focus = ""
			map_node = ""
		else:
			_close_map()
		_track_modal()
		queue_redraw()
		return true
	if Arena.modal == "box":
		if not box_ready():
			box_skip()
			return true
		if Arena.phase == Arena.Phase.SWAP and Arena.close_modal():
			_track_modal()
			return true
	return false

## The screen's own layers over the running battle — the aim, the pick's flourish — keep the
## pause menu out (Main.screen_modal_open), so Esc and back reach them first.
func overlay_open() -> bool:
	return aiming() or _pick_hold_t0 >= 0.0

func cancel_joystick() -> void:
	joystick = Vector2.ZERO
	_joy_pointer = NO_POINTER
	_joy_selection = -1
	queue_redraw()

## Every frame, processing or not: let go of what lost its reason.
func _guard_frame() -> void:
	_guard_joystick()
	_guard_aim()

func _guard_joystick() -> void:
	if _joy_pointer == NO_POINTER: return
	if not Arena.modal.is_empty() or store.opened or _menu_open() or Arena.sim == null or Arena.sim.done or Arena.selected != _joy_selection or not is_visible_in_tree():
		cancel_joystick()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel_joystick()
		cancel_aim()
		_release_press()

func _pointer(pointer: int, at: Vector2, pressed: bool) -> void:
	if not pressed:
		_release(pointer, at)
		return
	# The pick's flourish holds everything for its moment.
	if _pick_hold_t0 >= 0.0:
		get_viewport().set_input_as_handled()
		return
	# Buttons retain multi-touch while an existing movement finger owns its origin.
	for n in range(ui.zones.size() - 1, -1, -1):
		var zone: Dictionary = ui.zones[n]
		if not Rect2(zone["rect"]).has_point(at): continue
		if bool(zone.get("on", false)):
			_press(pointer, String(zone["id"]))
		get_viewport().set_input_as_handled()
		return
	# Aiming, a press on the open field takes the aim — before the moving finger's claim
	# below, so a second finger aims while the first one moves the hero.
	if aiming():
		_take_aim(pointer, at)
		get_viewport().set_input_as_handled()
		return
	if Rect2(0, 0, 1280, 70).has_point(at) or SIDEBAR.has_point(at): return
	if Arena.sim != null and (Arena.sim.boss_spawned or Arena.sim.boss_warned) and BOSS_BOX.has_point(at): return
	if Arena.sim != null and Arena.sim.shield > 0 and SHIELD_BOX.has_point(at): return
	if not FIELD.has_point(at) or not Arena.modal.is_empty() or store.opened or Arena.sim == null or Arena.sim.done or _menu_open(): return
	if _joy_pointer != NO_POINTER:
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

## A press on a live zone. The level-up popup's buttons (its picks, its map button and the
## constellation column's rows that open the map) and the box's cards and reroll commit on
## release: the press only holds them, and only once they answer — a finger still tapping from
## the battle never acts. Every other button acts at once.
func _press(pointer: int, id: String) -> void:
	if id.begins_with("talent:pick:") or _popup_button(id):
		if talent_armed():
			_hold_button(pointer, id)
			talent_pressed = id
		return
	if id.begins_with("box:pick:") or id == "box:reroll":
		if box_ready():
			_hold_button(pointer, id)
		return
	ui.pressed = id
	_action(id)

## The popup's buttons besides its picks: the map button and the column's constellation rows
## while the offer shows (inside the map they act at once).
func _popup_button(id: String) -> bool:
	return Arena.modal == "talent" and not talent_map and not Arena.talent_offer.is_empty() \
		and (id == "talent:map" or id.begins_with("talent:group:"))

func _hold_button(pointer: int, id: String) -> void:
	_press_pointer = pointer
	_press_zone = id
	ui.pressed = id
	queue_redraw()

## A finger lifts: the stick stops, the aim casts (or ends), and a held button acts if the
## finger is still on it.
func _release(pointer: int, at: Vector2) -> void:
	if pointer == _joy_pointer: cancel_joystick()
	if pointer == _aim_pointer: _drop_aim(at)
	if pointer == _press_pointer:
		var id := _press_zone
		_release_press()
		if ui.hit(at) == id:
			_action(id)
	ui.pressed = ""

## A touch the system took back: whatever it held lets go, and nothing is cast or picked.
func _cancel_pointer(pointer: int) -> void:
	if pointer == _joy_pointer: cancel_joystick()
	if pointer == _aim_pointer: cancel_aim()
	if pointer == _press_pointer: _release_press()
	ui.pressed = ""

func _release_press() -> void:
	_press_pointer = NO_POINTER
	_press_zone = ""
	talent_pressed = ""

func _set_joystick(at: Vector2) -> void:
	if _joy_pointer == NO_POINTER: return
	_guard_joystick()
	if _joy_pointer == NO_POINTER: return
	joystick = ((at - joy_origin) / JOY_RADIUS).limit_length(1.0)
	if joystick.length() < 0.12: joystick = Vector2.ZERO
	queue_redraw()

func _action(id: String) -> void:
	if id == "modal:block": return
	# Any other command ends the aim (the starburst's own button toggles it).
	if id != "skill:blast": cancel_aim()
	if store.action(id):
		pass
	elif id.begins_with("hero:"):
		Arena.selected = int(id.get_slice(":", 1))
		cancel_joystick()
	elif id == "summon": Arena.begin_summon()
	elif id == "talents": Arena.open_modal("talent")
	elif id == "bench": Arena.open_modal("bench")
	elif id == "close":
		# The box's result closes once it is in; any other window as before.
		if Arena.modal != "box" or box_ready(): Arena.close_modal()
	elif id == "skill:blast":
		if aiming(): cancel_aim()
		elif _skill_ready("blast"): _begin_aim()
	elif id.begins_with("skill:"):
		Arena.sim.cast_skill(id.get_slice(":", 1))
	elif id == "aim:cancel": pass
	elif id == "wave:start":
		if Arena.sim != null: Arena.sim.skip_prep()
	elif id.begins_with("speed:") and id.get_slice(":", 1).is_valid_int():
		set_speed(float(int(id.get_slice(":", 1))))
	elif id == "stage:start": Arena.confirm_stage()
	elif id == "result:guardian": store.open(Store.GUARDIAN)
	elif id == "box:reroll": _reroll_box()
	elif id.begins_with("box:pick:"): _pick_box_card(int(id.get_slice(":", 2)))
	elif id == "box:skip": box_skip()
	elif id.begins_with("talent:pick:"): _pick_talent(id.get_slice(":", 2))
	elif id == "talent:map": _open_map("")
	elif id == "talent:back": _close_map()
	elif id.begins_with("talent:group:"): _open_map(id.trim_prefix("talent:group:"))
	elif id.begins_with("talent:node:"):
		var node := id.trim_prefix("talent:node:")
		_open_map(String(Talents.by_id(node).get("group", "")))
		if talent_map: map_node = node
	elif id.begins_with("bench:field:"): _field_choice = int(id.get_slice(":", 2))
	elif id.begins_with("bench:reserve:"): _bench_choice = int(id.get_slice(":", 2))
	elif id == "bench:prev": _bench_page = maxi(0, _bench_page - 1)
	elif id == "bench:next": _bench_page += 1
	elif id == "bench:swap":
		if Arena.swap_hero(_field_choice, _bench_choice): _bench_choice = -1
	elif id == "result:retry":
		# The same stage again (Hellbound: the same squad), on a fresh screen.
		if main != null: main.retry_stage()
		else: Arena.retry()
	elif id == "result:next":
		if can_next_stage():
			if main != null: main.next_stage()
			else: Arena.next_stage()
	elif id == "result:home" and main != null:
		main.go(main.show_title)
	# The jewel box plays its own cue at each of these moments (charge, flip, pick burst);
	# a click on top muddies them (D1, 2026-10-19). Closing the result keeps the click. A
	# level-up pick has its own burst too.
	if not (id == "box:skip" or id == "box:reroll" or id.begins_with("box:pick:") or id.begins_with("talent:pick:")):
		Sfx.play("button")
	_track_modal()
	_refresh_live()
	queue_redraw()

## The result card's 「다음 STAGE」: only after a won ladder stage whose next stage is open.
func can_next_stage() -> bool:
	return not Arena.running and Arena.modal == "result" and Arena.sim != null and Arena.sim.won \
		and not Arena.hell and Arena.can_play(Arena.stage + 1)

func set_speed(value: float) -> void:
	speed = float(clampi(roundi(value), 1, 3))
	Save.set_speed(speed)

func _tr(key: String) -> String:
	return Arena.label("arena." + key)

# --------------------------------------------------------------------------- #
# The level-up popup (F1) and the constellation map (F2)
# --------------------------------------------------------------------------- #
## Seconds into the popup's entrance (a following offer: its cards' entrance). The clock
## starts on the offer's second picture.
func talent_entrance_age() -> float:
	if _settled(): return 99.0
	return maxf(0.0, _talent_clock.age(t))

## Whether the offer's pick buttons answer. A held screen (captures, tests) is armed.
func talent_armed() -> bool:
	if _settled(): return true
	return Arena.modal == "talent" and not Arena.talent_offer.is_empty() and not talent_map \
		and _pick_hold_t0 < 0.0 and _arm_clock.draws >= TALENT_ARM_DRAWS and _arm_clock.age(t) >= _arm_at

## How far the buttons are towards arming, 0 to 1 (1 only once armed).
func talent_arm_progress() -> float:
	if talent_armed(): return 1.0
	if not _arm_clock.running(): return 0.0
	return clampf(_arm_clock.age(t) / _arm_at, 0.0, 0.99)

## Seconds since the pick whose flourish holds the battle, or -1.
func pick_hold_age() -> float:
	return t - _pick_hold_t0 if _pick_hold_t0 >= 0.0 else -1.0

## The popup's clocks, once per picture (from _draw). A new offer starts them: the first one
## of the popup with its whole entrance, a following one with its cards and the shorter arm.
func _tick_talent_clocks() -> void:
	if _pick_hold_t0 >= 0.0: return
	var offer: Array = Arena.talent_offer
	var key := "%d:%s" % [_talent_serial, ",".join(PackedStringArray(offer))] if not offer.is_empty() else "map"
	if key != _talent_key:
		_talent_key = key
		talent_followup = not offer.is_empty() and _talent_offers > 0
		if not offer.is_empty(): _talent_offers += 1
		_talent_clock.restart()
		_arm(TALENT_REARM_AT if talent_followup else TALENT_ARM_AT)
	_talent_clock.tick(t)
	_arm_clock.tick(t)

func _arm(seconds: float) -> void:
	_arm_at = seconds
	_arm_clock.restart()

func _reset_talent() -> void:
	_talent_key = ""
	_talent_offers = 0
	_talent_clock.stop()
	_arm_clock.stop()
	_arm_at = TALENT_ARM_AT
	talent_followup = false
	talent_map = false
	map_focus = ""
	map_node = ""
	_map_from_offer = false
	talent_pressed = ""

## The pick: the run takes the star at once (the next offer, if a level still waits, is
## rolled); the screen holds the battle for the star's flourish.
func _pick_talent(node: String) -> void:
	if not talent_armed() or not Arena.talent_offer.has(node): return
	var offer: Array = Arena.talent_offer.duplicate()
	if not Arena.pick_talent(node): return
	Sfx.play("summon_burst")
	_talent_serial += 1
	talent_pressed = ""
	if not _settled():
		pick_hold_id = node
		pick_hold_offer = offer
		_pick_hold_t0 = t

func _end_pick_hold() -> void:
	_pick_hold_t0 = -1.0
	pick_hold_id = ""
	pick_hold_offer = []

## Open the map (or move it) on `focus` ("" = the overview). From the offer only once the
## popup answers: the map button is one more thing to arm.
func _open_map(focus: String) -> void:
	if Arena.modal != "talent": return
	if not talent_map:
		if not Arena.talent_offer.is_empty() and not talent_armed(): return
		talent_map = true
		_map_from_offer = not Arena.talent_offer.is_empty()
	if focus != map_focus: map_node = ""
	map_focus = focus

## Leave the map: back to the offer it was opened from — whose buttons arm again, a tap on
## «back» can land on one — or, as the rail's viewer, out of the window.
func _close_map() -> void:
	if not talent_map: return
	map_focus = ""
	map_node = ""
	if _map_from_offer and not Arena.talent_offer.is_empty():
		talent_map = false
		_map_from_offer = false
		_arm(TALENT_REARM_AT)
	else:
		Arena.close_modal()

# --------------------------------------------------------------------------- #
# The jewel box (F10 / F11)
# --------------------------------------------------------------------------- #
func _open_box() -> void:
	_box_clock.restart()
	_box_deal.restart()
	_box_pick.stop()
	# A box the screen opens onto after its pick (a restored run) shows its result settled.
	if Arena.phase == Arena.Phase.SWAP: _box_pick.set_age(t, 99.0)

func _tick_box_clocks() -> void:
	_box_clock.tick(t)
	_box_deal.tick(t)
	_box_pick.tick(t)

## Seconds since the box opened.
func box_age() -> float:
	return 99.0 if _settled() else maxf(0.0, _box_clock.age(t))

## Seconds into the box's deal: from its opening, again from 0 at every reroll.
func box_deal_age() -> float:
	return 99.0 if _settled() else maxf(0.0, _box_deal.age(t))

## Seconds since the pick, or -1 before it.
func box_pick_age() -> float:
	if _settled(): return 99.0 if Arena.modal == "box" and Arena.phase == Arena.Phase.SWAP else -1.0
	return _box_pick.age(t)

## Whether the box takes a pick, a reroll or (after the pick) its close: once its ceremony
## has settled (ArenaBoxView.is_ready) and the view has drawn this deal / this pick. A held
## screen is ready.
func box_ready() -> bool:
	if Arena.modal != "box": return false
	if not _settled() and (_box_pick if Arena.phase == Arena.Phase.SWAP else _box_deal).draws < BOX_ARM_DRAWS: return false
	return box_view.is_ready()

## A tap during the ceremony: the cards turn over at once and it settles (the view moves its
## own beat; the screen's deal clock stays).
func box_skip() -> void:
	if Arena.modal == "box" and Arena.phase == Arena.Phase.DRAW and not box_ready():
		box_view.skip()
		queue_redraw()

func _reroll_box() -> void:
	if box_ready() and not Arena.respin().is_empty():
		_box_deal.restart()

func _pick_box_card(index: int) -> void:
	if box_ready() and Arena.phase == Arena.Phase.DRAW and not Arena.pick_card(index).is_empty():
		_box_pick.restart()

# --------------------------------------------------------------------------- #
# The starburst's aim (F6)
# --------------------------------------------------------------------------- #
func aiming() -> bool:
	return not _aim.is_empty()

## The logical ground point under the aim, or INF (no finger or cursor on the field yet).
func aim_point() -> Vector2:
	if not aiming() or not aim_pixel.is_finite() or not BATTLEFIELD.has_point(aim_pixel): return Vector2.INF
	return view_3d.ground_at(aim_pixel)

## Whether the star may fall there: on the arena, in the open battle box, not under the boss
## strip or the ward countdown while they show.
func aim_valid() -> bool:
	var point := aim_point()
	if not point.is_finite() or not ArenaGeometry.contains(point): return false
	if Arena.sim != null and (Arena.sim.boss_spawned or Arena.sim.boss_warned) and BOSS_BOX.has_point(aim_pixel): return false
	if Arena.sim != null and Arena.sim.shield > 0 and SHIELD_BOX.has_point(aim_pixel): return false
	return true

func cancel_aim() -> void:
	if _aim.is_empty() and _aim_pointer == NO_POINTER: return
	_aim = ""
	_aim_pointer = NO_POINTER
	aim_pixel = Vector2.INF
	queue_redraw()

func _begin_aim() -> void:
	_aim = "blast"
	_aim_pointer = NO_POINTER
	aim_pixel = Vector2.INF
	queue_redraw()

## A press while aiming: on the battle box it takes the aim (one finger at a time); anywhere
## else it lets the aim go.
func _take_aim(pointer: int, at: Vector2) -> void:
	if _aim_pointer != NO_POINTER: return
	if not BATTLEFIELD.has_point(at):
		cancel_aim()
		return
	_aim_pointer = pointer
	aim_pixel = at
	queue_redraw()

## The aiming finger lifts: the star falls there when the spot is valid; the aim ends either way.
func _drop_aim(at: Vector2) -> void:
	aim_pixel = at
	if Arena.sim != null and aim_valid() and Arena.sim.cast_skill("blast", aim_point()):
		# The star's fall: an area spell's descending sweep and thump, lower and forced (the
		# heroes' area shots share the cue and its gap must not swallow the player's cast).
		Sfx.force("shot_zone", -2.0, 0.82)
	cancel_aim()

## Every frame: the aim ends when the starburst could no longer be cast (a window, the shop
## or menu, the run over, cooling, no target, short of gold).
func _guard_aim() -> void:
	if not aiming(): return
	if not Arena.modal.is_empty() or store.opened or _menu_open() or Arena.sim == null or Arena.sim.done \
			or not is_visible_in_tree() or not _skill_ready("blast"):
		cancel_aim()

## The 3D reticle, every picture while aiming and once more when it ends (ArenaWorld.set_aim).
func _show_aim() -> void:
	var shown := aiming()
	if not shown and not _aim_shown: return
	_aim_shown = shown
	var world = view_3d.world
	if world == null or not is_instance_valid(world): return
	world.set_aim(aim_point(), Arena.sim.blast_radius() if shown and Arena.sim != null else 0.0, aim_valid(), shown)

# --------------------------------------------------------------------------- #
# Common skills (O2)
# --------------------------------------------------------------------------- #
func _skill_ready(id: String) -> bool:
	return Arena.sim != null and bool(Arena.sim.skill_state(id).get("ready", false))

## Seconds since the skill became ready to cast (its 「준비 완료」 moment), or -1 while it
## is not. A skill already ready when first asked has been ready all along, and a window
## over the battle (block "inactive") neither ends nor starts the moment. A held screen
## shows the steady look.
func skill_ready_age(id: String) -> float:
	if Arena.sim == null: return -1.0
	var block := String(Arena.sim.skill_state(id).get("block", ""))
	if block == "inactive": return -1.0
	var ready := block.is_empty()
	if not _ready_seen.has(id):
		_ready_t0[id] = -100.0
	elif ready and not bool(_ready_seen[id]):
		_ready_t0[id] = t
	_ready_seen[id] = ready
	if not ready: return -1.0
	return 99.0 if _settled() else t - float(_ready_t0[id])

# --------------------------------------------------------------------------- #
# The picture
# --------------------------------------------------------------------------- #
## The picture, back to front: the 3D field (behind this canvas, through ArenaFrame) with
## its damage numbers, then the views in a fixed order. Each view draws on this canvas and
## registers its touch zones in `ui` as it goes, so a later zone wins a shared edge exactly
## where the drawing overlaps (Ui.hit, _pointer).
func _draw() -> void:
	ui.begin()
	if view_3d.frame == null or not is_instance_valid(view_3d.frame):
		draw_rect(Look.SCREEN, Look.BG_DEEP)
	var theme: Dictionary = Arena.theme_for(1)
	view_3d.draw_arena(self, FIELD, theme, Arena.sim, Arena.selected, _draw_dt)
	_draw_dt = 0.0
	_show_aim()
	hud._draw_monster_bars()
	hud._draw_topbar(theme)
	hud._draw_controls()
	hud._draw_minimap()
	hud._draw_joystick()
	# A result this screen saw arrive plays its entrance; one it opened onto is settled.
	if Arena.modal != "result": _field_seen = true
	hud._draw_banners()
	match Arena.modal:
		"stage": cards._draw_stage_card()
		"box":
			_tick_box_clocks()
			box_view.draw_box()
		"talent":
			_tick_talent_clocks()
			talent_view._draw_talent()
		"bench": cards._draw_bench()
		"result": cards._draw_result()
	# The last level's pick: its flourish outlives the popup until the hold ends (under an
	# open popup _draw_talent draws it).
	if Arena.modal != "talent" and _pick_hold_t0 >= 0.0:
		talent_view._draw_pick_hold()
	store.draw(self, ui, t)

## World height of a monster's visual top (ArenaHud keeps the measured boss tops).
func _monster_top(mo: Dictionary) -> float:
	return hud._monster_top(mo)

## Presentation motion runs on `t`, which only advances while the screen itself is
## processing. A screen that is held still (a transition, a capture) shows everything
## settled, so nothing is ever photographed or left half-way through its entrance.
func _settled() -> bool:
	return not is_processing()

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

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

## The rules of the run, as the shared menu shows them (MenuOverlay calls this): ArenaHelp.
static func draw_help(ci: CanvasItem) -> void:
	ArenaHelp.draw(ci)
