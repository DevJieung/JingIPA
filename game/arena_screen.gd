extends Node2D
class_name ArenaScreen

## One battlefield, with the ritual, growth and reserves over its paused world.
const FIELD := Rect2(0, 0, 1280, 800)
const BATTLEFIELD := Rect2(0, 70, 1280, 490)
const MINIMAP := Rect2(1088, 88, 174, 130)
const JOY_RADIUS := 67.0
const HERO_X := 255.0
const HERO_Y := 631.0
const HERO_W := 115.0
const HERO_GAP := 10.0
const MODAL := Rect2(72, 86, 1136, 676)

var main = null
var ui := Ui.new()
var view_3d := ArenaView.new()
var t := 0.0
var joystick := Vector2.ZERO
var joy_origin := Vector2.ZERO
var _joy_selection := -1
var _joy_pointer := -99
var _draw_dt := 0.0
var _modal_seen := ""
var _phase_seen := -1
var _theme_choice := 0
var _theme_page := 0
var _shop_tab := "upgrades"
var _passive_page := 0
var _bench_page := 0
var _bench_choice := -1
var _field_choice := -1
var _rite_age := 9.0
var _spin_rings: Array = []
var _card_crops: Dictionary = {}
func _ready() -> void:
	get_tree().process_frame.connect(_guard_joystick)
	view_3d.battle_box = BATTLEFIELD
	view_3d.minimap_box = MINIMAP
	_theme_choice = clampi(Arena.theme_index, 0, maxi(0, Roster.THEMES.size() - 1))
	_theme_page = _theme_choice / 12
	_track_modal()

func _process(dt: float) -> void:
	t += dt
	_rite_age += dt
	_track_modal()
	_draw_dt = 0.0
	if Arena.sim != null and Arena.modal.is_empty() and not _menu_open():
		Arena.sim.move_selected(_ground_direction(joystick), dt)
		Arena.sim.step(dt)
		_draw_dt = dt
	queue_redraw()

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
		Sfx.play_music("camp" if Arena.modal == "theme" or Arena.theme_index < 0 else "theme_" + String(Arena.theme_for(1)["id"]))
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
		if Arena.modal in ["shop", "bench"]:
			Arena.close_modal()
			get_viewport().set_input_as_handled()

func cancel_joystick() -> void:
	joystick = Vector2.ZERO
	_joy_pointer = -99
	_joy_selection = -1
	queue_redraw()

func _guard_joystick() -> void:
	if _joy_pointer == -99: return
	if not Arena.modal.is_empty() or _menu_open() or Arena.sim == null or Arena.sim.done or Arena.selected != _joy_selection or not is_visible_in_tree():
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
	if Rect2(0, 0, 1280, 70).has_point(at) or MINIMAP.has_point(at): return
	if Arena.sim != null and Arena.sim.boss_spawned and Rect2(368, 83, 544, 39).has_point(at): return
	if Arena.sim != null and Arena.sim.shield > 0 and Rect2(76, 80, 184, 30).has_point(at): return
	if not FIELD.has_point(at) or not Arena.modal.is_empty() or Arena.sim == null or Arena.sim.done or _menu_open(): return
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
	if id.begins_with("hero:"):
		Arena.selected = int(id.get_slice(":", 1))
		cancel_joystick()
	elif id == "summon": Arena.begin_summon()
	elif id == "shop": Arena.open_modal("shop")
	elif id == "bench": Arena.open_modal("bench")
	elif id == "close": Arena.close_modal()
	elif id.begins_with("skill:"):
		Arena.sim.cast_skill(id.get_slice(":", 1))
	elif id.begins_with("theme:") and id.get_slice(":", 1).is_valid_int():
		_theme_choice = int(id.get_slice(":", 1))
	elif id == "theme:prev": _theme_page = maxi(0, _theme_page - 1)
	elif id == "theme:next": _theme_page = mini((Roster.THEMES.size() - 1) / 12, _theme_page + 1)
	elif id == "theme:start": Arena.choose_theme(_theme_choice)
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
		_theme_choice = maxi(0, Arena.theme_index)
		_theme_page = 0
	elif id == "result:home" and main != null:
		main.go(main.show_title)
	Sfx.play("button")
	_track_modal()
	queue_redraw()

func _tr(key: String) -> String:
	return Arena.label("arena." + key)

func _draw() -> void:
	ui.begin()
	draw_rect(Look.SCREEN, Look.BG_DEEP)
	var theme: Dictionary = Roster.THEMES[_theme_choice] if Arena.modal == "theme" else Roster.THEMES[clampi(Arena.theme_index, 0, Roster.THEMES.size() - 1)]
	view_3d.draw_arena(self, FIELD if Arena.modal != "theme" else Look.SCREEN, theme, Arena.sim if Arena.modal != "theme" else null, Arena.selected, _draw_dt)
	_draw_dt = 0.0
	if Arena.modal != "theme":
		_draw_monster_bars()
		_draw_topbar(theme)
		_draw_controls()
		_draw_minimap()
		_draw_joystick()
	match Arena.modal:
		"theme": _draw_themes()
		"rite": _draw_rite()
		"shop": _draw_shop()
		"bench": _draw_bench()
		"result": _draw_result()

func _draw_topbar(theme: Dictionary) -> void:
	draw_rect(Rect2(0, 0, 1280, 69), Color(0.025, 0.065, 0.095, 0.88))
	draw_line(Vector2(0, 69), Vector2(1280, 69), Color("#84b5c5"), 1, true)
	draw_line(Vector2(0, 71), Vector2(1280, 71), Color(0.02, 0.04, 0.07, 0.55), 2)
	_draw_hud_crystal(Vector2(43, 34))
	Look.text_box(self, Rect2(76, 8, 315, 30), _tr("title"), 25, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	for x in [442, 648, 800]:
		draw_line(Vector2(x, 16), Vector2(x, 54), Color("#406072"), 1, true)
		_draw_diamond(Vector2(x, 35), 3.5, Color("#688e9f"))
	Look.text_box(self, Rect2(458, 17, 176, 32), String(theme.get("ko", "")), 23, Look.INK)
	if Arena.sim == null: return
	var sim = Arena.sim
	var fraction := clampf(sim.crystal_hp / maxf(1.0, sim.crystal_max), 0, 1)
	_bar(Rect2(79, 49, 207, 9), fraction, Color("#6af4ef"))
	Look.text_box(self, Rect2(300, 40, 131, 23), "%d / %d" % [ceili(sim.crystal_hp), int(sim.crystal_max)], 17, Look.INK)
	if sim.shield > 0:
		Look.glass_panel(self, Rect2(76, 80, 184, 30), Look.CRYSTAL, Color(0.015, 0.08, 0.14, 0.78))
		_draw_skill_icon(Vector2(92, 95), "ward", 8, Look.CRYSTAL)
		Look.text_box(self, Rect2(106, 82, 146, 26), _tr("shield") + " " + str(ceili(sim.shield)), 16, Look.CRYSTAL)
	Look.text_box(self, Rect2(662, 7, 125, 22), _tr("boss_final") if sim.boss_spawned else _tr("boss_in"), 16, Look.INK_DIM)
	var clock := maxf(0, Balance.ARENA_BOSS_AT - sim.elapsed)
	Look.text_box(self, Rect2(662, 27, 125, 34), _clock(sim.elapsed) if sim.boss_spawned else _clock(clock), 28, Look.GOLD if sim.boss_spawned else Look.INK)
	_draw_coin(Vector2(832, 35), 12)
	Look.text_box(self, Rect2(851, 16, 100, 37), "%d G" % Arena.gold, 25, Look.GOLD)
	if sim.boss_spawned:
		for mo in sim.monsters:
			if String(mo.get("kind", "")) != "boss": continue
			var box := Rect2(368, 83, 544, 39)
			Look.glass_panel(self, box, Color("#be797e"), Color(0.09, 0.02, 0.06, 0.85))
			_bar(Rect2(380, 112, 520, 4), float(mo["hp"]) / maxf(1, float(mo["max"])), Look.RED)
			Look.text_box(self, Rect2(385, 86, 510, 23), I18n.t(String(mo["m"].get("ko", _tr("boss_final")))), 19, Look.INK)
			break

func _draw_controls() -> void:
	# The forest remains visible under the touch deck, making the world continuous.
	draw_rect(Rect2(0, 564, 1280, 236), Color(0.012, 0.037, 0.06, 0.81))
	for n in range(13):
		draw_rect(Rect2(0, 564 + n * 3, 1280, 3), Color(0.014, 0.052, 0.075, 0.10 * (1 - n / 13.0)))
	draw_line(Vector2(0, 564), Vector2(1280, 564), Color("#97b7bd"), 1, true)
	for x in [16, 1264]: _draw_diamond(Vector2(x, 564), 3, Look.GOLD)
	var active := Arena.modal.is_empty() and Arena.sim != null and not Arena.sim.done
	var summoning := active and Arena.gold >= Arena.summon_cost() and not Arena.eligible_units().is_empty()
	ui.glass_button(self, Rect2(294, 574, 206, 39), _tr("summon") + "  %d G" % Arena.summon_cost(), "summon", summoning, Look.PANEL_EDGE, 20)
	ui.glass_button(self, Rect2(510, 574, 206, 39), _tr("shop"), "shop", active, Look.PANEL_EDGE, 21)
	ui.glass_button(self, Rect2(726, 574, 242, 39), _tr("bench") + "  %d" % Arena.bench.size(), "bench", active, Look.PANEL_EDGE, 21)
	for i in range(Balance.ARENA_HERO_LIMIT):
		var rect := Rect2(HERO_X + i * (HERO_W + HERO_GAP), HERO_Y, HERO_W, 153)
		if i < Arena.heroes.size():
			_draw_hero_card(rect, Arena.heroes[i], i == Arena.selected)
			ui.zone(rect.grow(3), "hero:%d" % i, active)
		else:
			ui.zone(rect.grow(3), "hero:empty", false)
			Look.glass_panel(self, rect, Color("#587787"), Color(0.06, 0.12, 0.16, 0.73))
			_draw_skill_icon(Vector2(rect.get_center().x, rect.position.y + 31), "freeze", 13, Color(0.28, 0.46, 0.56, 0.25))
			Look.text_box(self, Rect2(rect.position + Vector2(8, 59), Vector2(rect.size.x - 16, 43)), str(i + 1), 31, Color("#698390"))
			Look.text_box(self, Rect2(rect.position.x + 8, rect.end.y - 33, rect.size.x - 16, 24), "빈 자리", 17, Color("#829ba7"))
	for i in range(3):
		var id: String = ["blast", "freeze", "ward"][i]
		var rect := Rect2(1056, 574 + i * 70, 206, 61)
		var remaining := float(Arena.sim.skill_cooldowns.get(id, 0.0)) if Arena.sim != null else 0.0
		var enabled := active and remaining <= 0
		var color: Color = [Look.GOLD, Color("#aeeaff"), Color("#6ce8fa")][i]
		ui.glass_button(self, rect, "", "skill:" + id, enabled, color, 18)
		for layer in range(3): draw_circle(Vector2(rect.position.x + 30, rect.get_center().y), 21 - layer * 4, Color(color, 0.035 if enabled else 0.009))
		_draw_skill_icon(Vector2(rect.position.x + 30, rect.get_center().y), id, 17, color if enabled else Look.INK_DIM)
		Look.text_box(self, Rect2(rect.position + Vector2(59, 6), Vector2(138, 26)), _tr("skill." + id), 20, color if enabled else Look.INK_DIM)
		Look.text_box(self, Rect2(rect.position + Vector2(59, 31), Vector2(138, 20)), _tr("ready") if remaining <= 0 else "%.1f" % remaining, 15, color if enabled else Look.INK_DIM)
		if remaining > 0 and Arena.sim != null:
			var maximum := Arena.sim.skill_max_cooldown(id)
			_bar(Rect2(rect.position.x + 8, rect.end.y - 6, rect.size.x - 16, 2), 1 - remaining / maxf(0.001, maximum), color)

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
	for lane in range(ArenaGeometry.ROUTE_COUNT):
		var road := PackedVector2Array()
		for point in ArenaGeometry.route_points(lane): road.append(view_3d.minimap_point(point, map))
		draw_polyline(road, Color(0.56, 0.68, 0.68, 0.27), ArenaGeometry.ROAD_WIDTH / (ArenaGeometry.RADIUS * 2) * map.size.x, true)
		draw_polyline(road, Color(0.78, 0.86, 0.82, 0.19), 1, true)
	var footprint := view_3d.minimap_footprint(map)
	if footprint.size() >= 3:
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
	# Compass tick uses a shape, avoiding another language-dependent HUD label.
	draw_colored_polygon(PackedVector2Array([Vector2(MINIMAP.get_center().x, MINIMAP.position.y + 2), Vector2(MINIMAP.get_center().x - 3, MINIMAP.position.y + 7), Vector2(MINIMAP.get_center().x + 3, MINIMAP.position.y + 7)]), Color("#9dbdcc"))

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

func _draw_coin(at: Vector2, radius: float) -> void:
	draw_circle(at, radius + 1, Color("#7e653b"))
	draw_circle(at, radius, Color("#dcad51"))
	draw_arc(at, radius - 3, 0, TAU, 28, Color("#fff0b8"), 1.2, true)
	draw_line(at + Vector2(-2, -7), at + Vector2(-5, 6), Color("#ffedb0"), 2, true)
	draw_line(at + Vector2(3, -7), at + Vector2(0, 6), Color("#805d2d"), 2, true)

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
		if mo["hp"] >= mo["max"] and not bool(mo.get("blocked", false)): continue
		var boss := String(mo.get("kind", "")) == "boss"
		var at := view_3d.project(mo["pos"], 1.75 if boss else 1.2 if String(mo.get("kind", "")) == "tank" else 0.84)
		if not BATTLEFIELD.grow(-14).has_point(at) or MINIMAP.has_point(at): continue
		var cell := Vector2i(int(at.x / 34), int(at.y / 13))
		if occupied.has(cell) and not boss: continue
		occupied[cell] = true
		var fraction := clampf(float(mo["hp"]) / maxf(1, float(mo["max"])), 0, 1)
		_bar(Rect2(at.x - 22, at.y - 8, 44, 5), fraction, Look.hp_color(fraction))
		if bool(mo.get("blocked", false)) and not boss:
			draw_line(at + Vector2(-4, -15), at + Vector2(-4, -10), Look.GOLD, 2)
			draw_line(at + Vector2(4, -15), at + Vector2(4, -10), Look.GOLD, 2)

func _shade() -> void:
	draw_rect(Look.SCREEN, Color(0.025, 0.05, 0.075, 0.80))
	ui.zone(Look.SCREEN, "modal:block")
	Look.glass_panel(self, MODAL, Color("#81a5b6"), Color(0.035, 0.085, 0.13, 0.96))
	Look.fill_round(self, Rect2(1002, 100, 174, 31), 4, Color("#2d4246"))
	Look.text_box(self, Rect2(1008, 102, 162, 25), _tr("pause"), 17, Look.GOLD)

func _draw_themes() -> void:
	draw_rect(Look.SCREEN, Color(0.02, 0.04, 0.06, 0.73))
	ui.zone(Look.SCREEN, "modal:block")
	Look.text_box(self, Rect2(144, 66, 992, 64), _tr("theme_title"), 42, Look.GOLD)
	Look.text_box(self, Rect2(120, 132, 1040, 45), _tr("theme_hint"), 24, Look.INK_DIM)
	var start := _theme_page * 12
	for n in range(12):
		var index := start + n
		if index >= Roster.THEMES.size(): break
		var theme: Dictionary = Roster.THEMES[index]
		var rect := Rect2(64 + (n % 4) * 292, 216 + (n / 4) * 124, 276, 108)
		var selected := index == _theme_choice
		Look.material_panel(self, rect, Look.PANEL.lightened(0.10) if selected else Look.PANEL.darkened(0.15), Look.GOLD if selected else Look.PANEL_EDGE)
		var body := String(theme.get("main_body", "wood"))
		Look.draw_body(self, rect.position + Vector2(28, 31), 16, body)
		Look.text_box(self, Rect2(rect.position + Vector2(52, 10), Vector2(210, 45)), String(theme.get("ko", "")), 24, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
		Look.text_box(self, Rect2(rect.position + Vector2(20, 65), Vector2(238, 27)), Balance.body_ko(body), 18, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		if selected: Look.draw_brackets(self, rect.grow(3), 15, Look.GOLD, 3)
		ui.zone(rect, "theme:%d" % index)
	ui.button(self, Rect2(72, 626, 92, 48), "<", "theme:prev", _theme_page > 0, Look.PANEL_EDGE, 26)
	ui.button(self, Rect2(1116, 626, 92, 48), ">", "theme:next", start + 12 < Roster.THEMES.size(), Look.PANEL_EDGE, 26)
	Look.text_box(self, Rect2(472, 633, 336, 32), "%d / %d" % [_theme_page + 1, ceili(Roster.THEMES.size() / 12.0)], 23, Look.INK_DIM)
	ui.button(self, Rect2(344, 701, 592, 61), _tr("start"), "theme:start", true, Look.GOLD, 27)

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

func _draw_result() -> void:
	_shade()
	var won := Arena.sim != null and Arena.sim.won
	var color := Look.GOLD if won else Look.RED
	_draw_skill_icon(Vector2(640, 255), "ward", 56, color)
	Look.text_box(self, Rect2(196, 344, 888, 70), _tr("victory") if won else _tr("defeat"), 42, color)
	if Arena.sim != null:
		Look.text_box(self, Rect2(280, 444, 720, 42), _tr("elapsed") + "  " + _clock(Arena.sim.elapsed), 28, Look.INK)
		Look.text_box(self, Rect2(280, 493, 720, 42), _tr("kills") + "  %d" % Arena.sim.kills, 28, Look.INK_DIM)
	ui.button(self, Rect2(220, 657, 392, 63), _tr("home"), "result:home", main != null, Look.PANEL_EDGE, 25)
	ui.button(self, Rect2(668, 657, 392, 63), _tr("retry"), "result:retry", true, Look.GOLD, 25)

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
