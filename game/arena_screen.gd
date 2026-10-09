extends Node2D
class_name ArenaScreen

## One battlefield, with the ritual, growth and reserves over its paused world.
const FIELD := Rect2(16, 82, 1248, 480)
const JOY_CENTER := Vector2(132, 683)
const JOY_RADIUS := 65.0
const HERO_X := 255.0
const HERO_Y := 640.0
const HERO_W := 115.0
const HERO_GAP := 14.0
const MODAL := Rect2(72, 86, 1136, 676)

var main = null
var ui := Ui.new()
var view_3d := ArenaView.new()
var t := 0.0
var joystick := Vector2.ZERO
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
var _pull_ring := -1
var _pull_from := 0.0
var _pull_draw_ring := -1
var _pull_age := 9.0

func _ready() -> void:
	Ads.completed.connect(_ad_completed)
	_theme_choice = clampi(Arena.theme_index, 0, maxi(0, Roster.THEMES.size() - 1))
	_theme_page = _theme_choice / 12
	_track_modal()

func _exit_tree() -> void:
	if Ads.completed.is_connected(_ad_completed):
		Ads.completed.disconnect(_ad_completed)

func _process(dt: float) -> void:
	t += dt
	_rite_age += dt
	_pull_age += dt
	_track_modal()
	_draw_dt = 0.0
	if Arena.sim != null and Arena.modal.is_empty() and not _menu_open() and not Ads.busy:
		Arena.sim.move_selected(_ground_direction(joystick), dt)
		Arena.sim.step(dt)
		_draw_dt = dt
	queue_redraw()

func _menu_open() -> bool:
	return main != null and main.get("menu") != null and main.menu.opened

func _ground_direction(direction: Vector2) -> Vector2:
	if direction.length_squared() < 0.001 or view_3d.world == null: return Vector2.ZERO
	var center := FIELD.get_center()
	var a := view_3d.ground_at(center)
	var b := view_3d.ground_at(center + direction.normalized() * 40)
	return (b - a).normalized() * minf(1.0, direction.length()) if a.is_finite() and b.is_finite() else Vector2.ZERO

func _track_modal() -> void:
	if _modal_seen == Arena.modal and _phase_seen == Arena.phase: return
	var previous := _modal_seen
	_modal_seen = Arena.modal
	_phase_seen = Arena.phase
	joystick = Vector2.ZERO
	_joy_pointer = -99
	ui.pressed = ""
	if Arena.modal == "rite" and previous != "rite":
		_pull_ring = -1
		_pull_draw_ring = -1
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
	if _menu_open() or Ads.busy: return
	if e is InputEventMouseButton and e.device < 0: return
	if e is InputEventScreenTouch:
		_pointer(e.index, e.position, e.pressed)
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

func _pointer(pointer: int, at: Vector2, pressed: bool) -> void:
	if not pressed:
		if pointer == _joy_pointer:
			joystick = Vector2.ZERO
			_joy_pointer = -99
		ui.pressed = ""
		return
	if Arena.modal.is_empty() and Arena.sim != null and not Arena.sim.done and at.distance_to(JOY_CENTER) <= JOY_RADIUS + 20:
		_joy_pointer = pointer
		_set_joystick(at)
		get_viewport().set_input_as_handled()
		return
	var id := ui.hit(at)
	if not id.is_empty():
		ui.pressed = id
		_action(id)
		get_viewport().set_input_as_handled()
		return
	if Arena.modal.is_empty() and FIELD.has_point(at):
		var index := view_3d.hero_at(at)
		if index >= 0:
			Arena.selected = index
			joystick = Vector2.ZERO
			Sfx.play("button")
		get_viewport().set_input_as_handled()

func _set_joystick(at: Vector2) -> void:
	joystick = ((at - JOY_CENTER) / JOY_RADIUS).limit_length(1.0)
	if joystick.length() < 0.12: joystick = Vector2.ZERO

func _action(id: String) -> void:
	if id == "modal:block": return
	if id.begins_with("hero:"):
		Arena.selected = int(id.get_slice(":", 1))
		joystick = Vector2.ZERO
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
	elif id == "rite:pull": _request_pull()
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

func _request_pull() -> void:
	if Arena.modal != "rite" or Arena.phase != Arena.Phase.DRAW or Ads.busy: return
	var ring := Arena.pull_target()
	if ring < 0: return
	_rite_age = 9
	_pull_ring = ring
	_pull_from = Rite.angle(ring, int(Arena.orbit[ring]))
	if not Ads.request_reward("card", {"slot": ring}): _pull_ring = -1

func _ad_completed(kind: String, rewarded: bool) -> void:
	if kind != "card" or not is_inside_tree() or Arena.modal != "rite" \
			or Arena.phase != Arena.Phase.DRAW or (main != null and main.screen != self): return
	var ring := _pull_ring
	_pull_ring = -1
	if rewarded and ring >= 0 and Rite.valid(Arena.orbit) and Rite.in_gate(ring, int(Arena.orbit[ring])):
		_pull_draw_ring = ring
		_pull_age = 0
		_rite_age = 9
		Sfx.play("block", -6.0, 1.1)
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
	match Arena.modal:
		"theme": _draw_themes()
		"rite": _draw_rite()
		"shop": _draw_shop()
		"bench": _draw_bench()
		"result": _draw_result()

func _draw_topbar(theme: Dictionary) -> void:
	Look.fill_round(self, Rect2(0, 0, 1280, 75), 0, Look.PANEL)
	draw_line(Vector2(0, 74), Vector2(1280, 74), Look.PANEL_EDGE, 2)
	Look.text_box(self, Rect2(24, 10, 250, 30), _tr("title"), 25, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(self, Rect2(350, 12, 210, 32), String(theme.get("en" if I18n.locale == "en" else "ko", "")), 23, Look.INK_DIM)
	if Arena.sim == null: return
	var sim = Arena.sim
	Look.draw_crystal(self, Vector2(36, 55), 9, sim.crystal_hp > 0)
	var fraction := clampf(sim.crystal_hp / maxf(1.0, sim.crystal_max), 0, 1)
	_bar(Rect2(58, 48, 218, 12), fraction, Look.hp_color(fraction))
	Look.text_box(self, Rect2(282, 40, 145, 24), "%d / %d" % [ceili(sim.crystal_hp), int(sim.crystal_max)], 17, Look.INK)
	if sim.shield > 0:
		Look.text_box(self, Rect2(430, 43, 125, 21), _tr("shield") + " " + str(ceili(sim.shield)), 16, Look.CRYSTAL)
	Look.text_box(self, Rect2(586, 8, 206, 22), _tr("boss_final") if sim.boss_spawned else _tr("boss_in"), 17, Look.INK_DIM)
	var clock := maxf(0, Balance.ARENA_BOSS_AT - sim.elapsed)
	Look.text_box(self, Rect2(586, 30, 206, 32), _clock(sim.elapsed) if sim.boss_spawned else _clock(clock), 29, Look.GOLD if sim.boss_spawned else Look.INK)
	Look.text_box(self, Rect2(808, 18, 136, 36), "%d G" % Arena.gold, 25, Look.GOLD)
	if sim.boss_spawned:
		for mo in sim.monsters:
			if String(mo.get("kind", "")) != "boss": continue
			var box := Rect2(368, 91, 544, 34)
			Look.fill_round(self, box, 5, Color("#15242a"))
			_bar(Rect2(380, 114, 520, 5), float(mo["hp"]) / maxf(1, float(mo["max"])), Look.RED)
			Look.text_box(self, Rect2(385, 91, 510, 23), I18n.t(String(mo["m"].get("ko", _tr("boss_final")))), 19, Look.INK)
			break

func _draw_controls() -> void:
	Look.fill_round(self, Rect2(0, 572, 1280, 228), 0, Look.BG_DEEP)
	draw_line(Vector2(24, 572), Vector2(1256, 572), Look.PANEL_EDGE, 1)
	var active := Arena.modal.is_empty() and Arena.sim != null and not Arena.sim.done
	draw_circle(JOY_CENTER + Vector2(0, 3), JOY_RADIUS + 7, Color(0, 0, 0, 0.45))
	draw_circle(JOY_CENTER, JOY_RADIUS + 3, Color("#758c91"))
	draw_circle(JOY_CENTER, JOY_RADIUS, Color("#162a32"))
	draw_arc(JOY_CENTER, JOY_RADIUS - 12, 0, TAU, 48, Color("#35515d"), 2, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var at: Vector2 = JOY_CENTER + d * 44
		var normal := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([at + d * 7, at - d * 2 + normal * 4, at - d * 2 - normal * 4]), Color("#9eb4ba") if active else Color("#47616b"))
	var stick := JOY_CENTER + joystick * 37
	draw_circle(stick + Vector2(0, 3), 26, Color(0, 0, 0, 0.45))
	draw_circle(stick, 26, Look.GOLD if _joy_pointer != -99 else Color("#8ba3a8"))
	draw_circle(stick, 23, Color("#344e58") if active else Color("#263a43"))
	Look.text_box(self, Rect2(50, 766, 164, 22), _tr("joystick"), 18, Look.INK_DIM)
	Look.text_box(self, Rect2(50, 592, 164, 25), _tr("pause") if not active else _tr("select_hero"), 17, Look.GOLD if not active else Look.INK_DIM)
	var summoning := active and Arena.gold >= Arena.summon_cost() and not Arena.eligible_units().is_empty()
	ui.button(self, Rect2(255, 584, 225, 44), _tr("summon") + "  %d G" % Arena.summon_cost(), "summon", summoning, Look.GOLD, 20)
	ui.button(self, Rect2(491, 584, 225, 44), _tr("shop"), "shop", active, Look.PANEL_EDGE, 21)
	ui.button(self, Rect2(727, 584, 225, 44), _tr("bench") + "  %d" % Arena.bench.size(), "bench", active, Look.PANEL_EDGE, 21)
	for i in range(Balance.ARENA_HERO_LIMIT):
		var rect := Rect2(HERO_X + i * (HERO_W + HERO_GAP), HERO_Y, HERO_W, 143)
		if i < Arena.heroes.size():
			HeroCard.draw(self, rect, Arena.heroes[i], i == Arena.selected)
			ui.zone(rect.grow(4), "hero:%d" % i, active)
		else:
			Look.outline_round(self, rect, 4, Color("#3d5156"), 1)
			Look.fill_round(self, rect, 4, Color("#17282e"))
			Look.text_box(self, Rect2(rect.position + Vector2(8, 43), Vector2(rect.size.x - 16, 40)), str(i + 1), 27, Color("#617a80"))
			Look.text_box(self, Rect2(rect.position.x + 8, rect.end.y - 37, rect.size.x - 16, 24), "빈 자리", 16, Look.INK_DIM)
	for i in range(3):
		var id: String = ["blast", "freeze", "ward"][i]
		var rect := Rect2(1058, 584 + i * 68, 196, 61)
		var remaining := float(Arena.sim.skill_cooldowns.get(id, 0.0)) if Arena.sim != null else 0.0
		var enabled := active and remaining <= 0
		var color: Color = [Look.GOLD, Look.ICE, Look.CRYSTAL][i]
		ui.button(self, rect, "", "skill:" + id, enabled, color if enabled else Look.PANEL_EDGE, 18)
		_draw_skill_icon(Vector2(rect.position.x + 27, rect.get_center().y - 4), id, 13, Look.BG_DEEP if enabled and id == "blast" else color if enabled else Look.INK_DIM)
		Look.text_box(self, Rect2(rect.position + Vector2(52, 6), Vector2(134, 26)), _tr("skill." + id), 20, Look.BG_DEEP if enabled and id == "blast" else Look.INK)
		Look.text_box(self, Rect2(rect.position + Vector2(52, 31), Vector2(134, 20)), _tr("ready") if remaining <= 0 else "%.1f" % remaining, 15, Look.BG_DEEP if enabled and id == "blast" else Look.INK_DIM)
		if remaining > 0 and Arena.sim != null:
			var maximum := Arena.sim.skill_max_cooldown(id)
			_bar(Rect2(rect.position.x + 8, rect.end.y - 7, rect.size.x - 16, 3), 1 - remaining / maxf(0.001, maximum), color)

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
		if not FIELD.grow(-14).has_point(at): continue
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
	Look.material_panel(self, MODAL, Color("#182b32"), Look.PANEL_EDGE)
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
		Look.outline_round(self, rect, 5, Look.GOLD if selected else Look.PANEL_EDGE, 2 if selected else 1)
		Look.fill_round(self, rect, 5, Color("#31464e") if selected else Color("#17282e"))
		var body := String(theme.get("main_body", "wood"))
		Look.draw_body(self, rect.position + Vector2(28, 31), 16, body)
		Look.text_box(self, Rect2(rect.position + Vector2(52, 10), Vector2(210, 45)), String(theme.get("en" if I18n.locale == "en" else "ko", "")), 24, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
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
		if ring == _pull_draw_ring and _pull_age < DrawScreen.PULL_SEC:
			var pull_q := clampf(_pull_age / DrawScreen.PULL_SEC, 0, 1)
			angle = lerp_angle(_pull_from, final_angle, 1 - pow(1 - pull_q, 3))
		var at := RiteBoard.point(center, ring, angle, scale_value)
		if spinning: RiteBoard.draw_trail(self, center, ring, angle, 0.34, scale_value)
		RiteBoard.draw_star(self, at, RiteBoard.SPIN if spinning else RiteBoard.look_of(ring, int(Arena.orbit[ring])), scale_value, t)
	var preview: Dictionary = Arena.rite_preview()
	Look.fill_round(self, Rect2(752, 242, 352, 337), 7, Color("#112229"))
	Look.text_box(self, Rect2(782, 271, 292, 38), _tr("free_summon") if Arena.heroes.is_empty() else _tr("heroes"), 23, Look.INK_DIM)
	Look.draw_rarity(self, Vector2(928, 345), int(preview.get("tier", 1)), 15)
	Look.text_box(self, Rect2(782, 368, 292, 57), Look.star_label(int(preview.get("tier", 1))), 45, Look.GOLD)
	Look.text_box(self, Rect2(782, 452, 292, 29), _tr("growth_points"), 20, Look.INK_DIM)
	Look.text_box(self, Rect2(782, 494, 292, 42), _tr("summons_cost") + "  %d G" % (0 if Arena.summon_count == 0 else Arena.summon_cost()), 20, Look.INK_DIM)
	ui.reward_button(self, Rect2(766, 603, 330, 54), "별 끌어오기", "rite:pull", Arena.pull_target() >= 0 and not Ads.busy, Look.CRYSTAL, 22)
	var cost := Arena.respin_cost()
	var suffix := "무료 %d" % Arena.respins_left() if cost == 0 else "%d G" % cost
	ui.button(self, Rect2(168, 686, 362, 55), I18n.t("다시 돌리기") + "  " + I18n.t(suffix), "rite:respin", Arena.can_respin(), Look.GREEN, 22)
	ui.button(self, Rect2(662, 686, 442, 55), _tr("summon_confirm"), "rite:confirm", not Arena.eligible_units().is_empty(), Look.GOLD, 25)

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
