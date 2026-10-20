extends Harness

## D3 (feedback 2026-10-19) battlefield visual preview: the real ArenaView / ArenaWorld /
## StellarVfx on a real battlefield, driven by a small stand-in simulator so the new pieces
## can be staged before the wave logic lands, and events thrown straight at the world.
##
##   godot --path . --resolution 1280x800 res://tests/3d/d3_visual_preview.tscn -- --out DIR
##   --scene ring|aim|wave|clear|elite|revive|blast|trample|all   --field calm_lake|polar_night|
##   spring_grove|volcano_crater|all   --film WxH (off-screen picture behind a tiny window)
##
## Scenes (each on every requested field):
##   ring     the selected hero's reach: a bow (long) and a sword (short) hero, plus the draw-in
##            of a new selection (ring_<field>_<bow|sword>.png, ring_<field>_in_NN.png)
##   aim      the starlight-burst aim moving over the field (valid gold, then off the rim:
##            red-grey), then the cast: the aim locks on and hands over to the sigil
##   wave     a wave starts: ordinary, elite (violet), boss (crimson runners + boss arrival)
##   clear    a wave is beaten: the sweep of light
##   elite    an elite steps in (arena_elite + an `elite` monster walking in)
##   revive   the crystal revives and grants a five-star guardian: on the field, then bench
##   blast    the starlight burst at radius 110 and at 160 (the radius awaiting approval)
##   trample  a boss walks through a guardian
##   game     (only with --scene game) the real ArenaScreen and simulator on a real stage: an
##            ordinary wave start, the elite wave until its elite steps in, the starlight burst
##            aimed by hand onto the elite (LB1: the screen's aim calls set_aim, the cast locks
##            on), the defence success with its heal, two revivals (LA3: the crystal breaks in a
##            tick; a five-star guardian lands on a free post, then one is crowned over the
##            crystal for the bench), then the boss warning and the boss walking through a guardian
##   hell     (only with --scene hell) Hellbound, the DLC's endless waves, on its own battlefield
##            through the real screen: waves 9 (ordinary), 10 (boss), 15 (elite, until it steps in)
##            and 21 — the same pictures as the ladder
## Every capture is a 3D frame through the battle frame's post pass (vignette), without the
## HUD (game/hell: the real screen, HUD included). Writes d3-report.json with the sequence list
## for tests/3d/d3_review.py.

const FIELDS := {"calm_lake": 0, "polar_night": 49, "spring_grove": 20, "volcano_crater": 18}
const SQUAD := [["echo", 6], ["jokull", 4], ["kari", 5], ["brasa", 6], ["limne", 4], ["pip", 5]]
const DT := 1.0 / 30.0
const RECT := Rect2(0, 0, 1280, 800)

## The parts of ArenaSim the world and the view read.
class StandIn extends RefCounted:
	var heroes: Array = []
	var monsters: Array = []
	var bullets: Array = []
	var zones: Array = []
	var events: Array = []
	var elapsed := 0.0
	var crystal_hp := 1000.0
	var crystal_max := 1200.0
	var shield := 0.0
	var invuln_t := 0.0
	var won := false
	var gate := Vector2.INF
	func final_stage() -> bool:
		return false
	func boss_gate() -> Vector2:
		return gate

## The canvas the view draws on (ArenaScreen's role).
class Stage extends Node2D:
	var view: ArenaView
	var sim
	var theme: Dictionary = {}
	var selected := -1
	var dt := 0.0
	func _draw() -> void:
		if view != null: view.draw_arena(self, Rect2(0, 0, 1280, 800), theme, sim, selected, dt)
		dt = 0.0

var out_dir := "build/feedback-2026-10-19/D3/1280x800"
var film: SubViewport
var stage: Stage
var sim: StandIn
var _report: Dictionary = {"sequences": []}
var _next_sid := 1

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if arg("--film", "") != "": _open_film(arg("--film", ""))
	var scene := arg("--scene", "all")
	var wanted := arg("--field", "all")
	var fields: Array = FIELDS.keys() if wanted == "all" else [wanted]
	if scene == "hell": fields = ["hell"]
	for field in fields:
		if scene == "game":
			await _game(String(field))
			continue
		if scene == "hell":
			await _hellbound()
			continue
		await _open(String(field))
		for name in ["ring", "aim", "wave", "clear", "elite", "revive", "blast", "trample", "calib"]:
			if scene != name and (scene != "all" or name == "calib"): continue
			await call("_scene_" + name, String(field))
		await _close()
	var file := FileAccess.open(out_dir + "/d3-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "  ") + "\n")
	file = null
	finish("D3 visual preview")

# --------------------------------------------------------------------------- #
# Set-up
# --------------------------------------------------------------------------- #
func _host() -> Node:
	return film if film != null else self

func _open_film(spec: String) -> void:
	var parts := spec.split("x")
	var design := Vector2i(1280, 800)
	film = SubViewport.new()
	film.name = "Film"
	film.size = Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else design
	film.size_2d_override = design
	film.size_2d_override_stretch = true
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.transparent_bg = false
	film.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	film.gui_disable_input = true
	add_child(film)
	get_window().size = Vector2i(96, 60)

func snap(path: String) -> Image:
	# A headless dry run (logic and checks only) has no picture to keep.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		return null
	await RenderingServer.frame_post_draw
	var img := (film if film != null else get_viewport()).get_texture().get_image()
	img.save_png(path)
	return img

func _open(field: String) -> void:
	var index := int(FIELDS[field])
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(index))
	sim = StandIn.new()
	sim.gate = ArenaGeometry.gate_point(0, 28.0)
	stage = Stage.new()
	stage.view = ArenaView.new()
	stage.sim = sim
	stage.theme = Roster.THEMES[index]
	_host().add_child(stage)
	_squad()
	await _tick(0.0)
	await _tick(0.0)
	var world: ArenaWorld = stage.view.world
	world.vfx._clear_field()
	# The warm frames hide the buried bodies after the first rendered frames.
	for n in range(6): await _tick(DT)
	check(int(world.get("_warm_left")) <= 0, field + ": warm frames are over after six rendered frames")
	for node in world.get("_warm_nodes"):
		check(not (node as Node3D).visible, field + ": warm body hidden after the warm frames")

func _close() -> void:
	stage.queue_free()
	stage = null
	await frames(4)

func _squad() -> void:
	sim.heroes.clear()
	for i in range(SQUAD.size()):
		var unit := Roster.unit_by_id(String(SQUAD[i][0]))
		var tier := int(SQUAD[i][1])
		var at: Vector2 = Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + i * TAU / 6.0 + 0.35) * 190.0
		sim.heroes.append({"h": {"unit": unit, "tier": tier}, "pos": at, "range": Balance.attack_range(unit, tier),
			"fx_t": 9.0, "fx_w": 0.35, "fx_d": Vector2.DOWN})

func _monster(id: String, at: Vector2, vel: Vector2 = Vector2.ZERO, extra: Dictionary = {}) -> Dictionary:
	var mo := {"spawn_id": _next_sid, "m": Roster.monster_by_id(id), "pos": at, "vel": vel, "hp": 100.0, "max": 100.0,
		"flash": 0.0, "motion_t": 0.0, "motion_phase": 0.0, "stun_t": 0.0, "burn_t": 0.0, "slow_t": 0.0}
	for key in extra: mo[key] = extra[key]
	_next_sid += 1
	sim.monsters.append(mo)
	return mo

## One simulated tick drawn once: the view drains the events into the world and the effect
## clock moves by dt. Monsters walk by their velocity.
func _tick(dt: float = DT) -> void:
	sim.elapsed += dt
	for mo in sim.monsters:
		var vel: Vector2 = mo.get("vel", Vector2.ZERO)
		if vel.length_squared() > 0.0:
			mo["pos"] = Vector2(mo["pos"]) + vel * dt
			mo["motion_t"] = float(mo["motion_t"]) + dt
		mo["flash"] = maxf(0.0, float(mo["flash"]) - 5.0 * dt)
	stage.dt = dt
	stage.queue_redraw()
	await frames(1)

func _shot(name: String) -> void:
	stage.queue_redraw()
	await frames(1)
	await snap(out_dir + "/" + name + ".png")

func _seq(prefix: String, count: int, ticks: int, focus: Rect2 = Rect2()) -> void:
	var row := {"prefix": prefix, "frames": count, "ticks_per_frame": ticks, "tick": DT}
	if focus.size != Vector2.ZERO: row["focus"] = [focus.position.x, focus.position.y, focus.size.x, focus.size.y]
	_report["sequences"].append(row)

## Film `count` frames, `ticks` simulated ticks apart; `each` runs before every tick.
func _film(prefix: String, count: int, ticks: int, each: Callable = Callable(), focus: Rect2 = Rect2()) -> void:
	for n in range(count):
		for k in range(ticks):
			if each.is_valid(): each.call(n * ticks + k)
			await _tick(DT)
		await snap(out_dir + "/%s_%02d.png" % [prefix, n])
	_seq(prefix, count, ticks, focus)

func _project(p: Vector2, h: float = 0.0) -> Vector2:
	return stage.view.project(p, h)

func _focus(p: Vector2, w: float = 420.0, h: float = 300.0) -> Rect2:
	var px := _project(p)
	return Rect2(px.x - w * 0.5, px.y - h * 0.5, w, h)

# --------------------------------------------------------------------------- #
# Scenes
# --------------------------------------------------------------------------- #
func _scene_ring(field: String) -> void:
	var world: ArenaWorld = stage.view.world
	sim.monsters.clear()
	# A few bodies inside the reach so the ring reads against them too.
	for n in range(5):
		_monster(["ember_imp", "frost_imp", "drop_slime"][n % 3], Vector2(sim.heroes[0]["pos"]) + Vector2.from_angle(n * 1.3) * (60.0 + 45.0 * n))
	for pick in [["bow", 0], ["sword", 1]]:
		stage.selected = int(pick[1])
		for n in range(12): await _tick(DT)
		if has_arg("--old-ring"):
			# The ring as it was before 2026-10-19, rebuilt here for a same-frame comparison
			# (the view is told nothing is selected, so the new ring stays hidden for that shot).
			var picked := stage.selected
			var old := _old_ring(world, sim.heroes[picked]["pos"], float(sim.heroes[picked]["range"]))
			stage.selected = -1
			await _shot("ringold_%s_%s" % [field, String(pick[0])])
			check(not (world.get("_ring") as MeshInstance3D).visible, field + ": the comparison shot has only the old ring")
			old.queue_free()
			stage.selected = picked
			for n in range(8): await _tick(DT)
		await _shot("ring_%s_%s" % [field, String(pick[0])])
		var ring: MeshInstance3D = world.get("_ring")
		check(ring.visible, field + ": the range ring shows for the selected " + String(pick[0]))
		var material: ShaderMaterial = ring.material_override
		check(is_equal_approx(float(material.get_shader_parameter("radius")), float(sim.heroes[stage.selected]["range"]) / StellarWorld.UNIT), field + ": ring radius = the hero's range")
	# The draw-in of a new selection (real-time animation: frames 30 ms apart).
	stage.selected = 2
	for n in range(8):
		await _tick(DT)
		await snap(out_dir + "/ring_%s_in_%02d.png" % [field, n])
		OS.delay_msec(25)
	_seq("ring_%s_in" % field, 8, 1, _focus(sim.heroes[2]["pos"], 520, 360))
	stage.selected = -1
	await _tick(DT)
	check(not (world.get("_ring") as MeshInstance3D).visible, field + ": no selection hides the ring")
	sim.monsters.clear()

func _scene_aim(field: String) -> void:
	var world: ArenaWorld = stage.view.world
	stage.selected = 0
	sim.monsters.clear()
	for n in range(6): _monster("ember_imp", Balance.ARENA_CENTER + Vector2(-230 + n * 22, 120 - n * 30))
	var start: Vector2 = Balance.ARENA_CENTER + Vector2(-260, 60)
	var radius := 160.0
	var path := func(k: int) -> Vector2:
		var t := float(k) / 23.0
		return start.lerp(Balance.ARENA_CENTER + Vector2(-80, 170), t)
	await _film("aim_%s_valid" % field, 8, 3, func(k: int) -> void:
		world.set_aim(path.call(k), radius, true, true), _focus(start + Vector2(90, 60), 640, 420))
	# Off the rim: the star cannot fall there.
	var outside: Vector2 = Balance.ARENA_CENTER + Vector2(ArenaGeometry.RADIUS + 70.0, -40.0)
	world.set_aim(outside, radius, false, true)
	for n in range(4): await _tick(DT)
	await _shot("aim_%s_invalid" % field)
	# Back on the field and cast: the aim locks on, the sigil takes over.
	var spot: Vector2 = Balance.ARENA_CENTER + Vector2(-150, 120)
	world.set_aim(spot, radius, true, true)
	for n in range(6):
		world.set_aim(spot, radius, true, true)
		await _tick(DT)
	world.set_aim(spot, radius, true, false)
	sim.events.append({"t": "arena_blast", "p": spot, "r": radius})
	for n in range(14):
		await _tick(DT)
		await snap(out_dir + "/aim_%s_cast_%02d.png" % [field, n])
		OS.delay_msec(20)
	_seq("aim_%s_cast" % field, 14, 1, _focus(spot, 640, 420))
	for n in range(30): await _tick(DT)
	check(not (world.get("_aim") as MeshInstance3D).visible, field + ": the aim ring is gone after the cast")
	stage.selected = -1
	sim.monsters.clear()

func _scene_wave(field: String) -> void:
	stage.selected = -1
	sim.monsters.clear()
	var world: ArenaWorld = stage.view.world
	for variant in [["normal", false, false], ["elite", true, false], ["boss", false, true]]:
		world.vfx._clear_field()
		sim.events.append({"t": "arena_wave", "wave": 5 if bool(variant[1]) else 10 if bool(variant[2]) else 3, "total": 10,
			"elite": bool(variant[1]), "boss": bool(variant[2])})
		if bool(variant[2]):
			sim.events.append({"t": "arena_boss", "p": sim.gate, "final": false})
		await _tick(DT)
		check((world.vfx.get_node("Roads") as MeshInstance3D).visible, field + ": a wave start sends runners down the roads (" + String(variant[0]) + ")")
		await _film("wave_%s_%s" % [field, String(variant[0])], 16, 3)
		for n in range(40): await _tick(DT)

func _scene_clear(field: String) -> void:
	stage.selected = -1
	var world: ArenaWorld = stage.view.world
	world.vfx._clear_field()
	sim.monsters.clear()
	sim.crystal_max = 1200.0
	sim.events.append({"t": "arena_heal", "p": Balance.ARENA_CENTER, "n": 96.0})
	sim.events.append({"t": "arena_wave_clear", "wave": 3, "gold": 40, "prep": 8.0, "heal": 96.0})
	await _film("clear_%s" % field, 16, 2)
	for n in range(30): await _tick(DT)
	# A heal on its own (a constellation node): the mend without the sweep.
	world.vfx._clear_field()
	sim.events.append({"t": "arena_heal", "p": Balance.ARENA_CENTER, "n": 120.0})
	await _film("mend_%s" % field, 14, 2, Callable(), _focus(Balance.ARENA_CENTER, 420, 320))
	for n in range(20): await _tick(DT)

func _scene_elite(field: String) -> void:
	stage.selected = -1
	var world: ArenaWorld = stage.view.world
	world.vfx._clear_field()
	sim.monsters.clear()
	var lane := 0
	var path := ArenaGeometry.route_points(lane)
	var at: Vector2 = path[mini(8, path.size() - 1)]
	var heading := (Vector2(path[mini(14, path.size() - 1)]) - at).normalized()
	var ids := ["ember_imp", "frost_imp", "drop_slime", "blaze_fox"]
	var elite_id := String(ids[FIELDS.keys().find(field) % ids.size()])
	var elite := _monster(elite_id, at, heading * 22.0, {"elite": true})
	_monster(elite_id, at - heading * 70.0, heading * 22.0)
	sim.events.append({"t": "arena_elite", "p": at, "sid": int(elite["spawn_id"])})
	await _film("elite_%s" % field, 16, 2, Callable(), _focus(at, 520, 360))
	var node: Node3D = world.monster_nodes.get(int(elite["spawn_id"]))
	check(node != null and is_equal_approx(node.scale.x, StellarModels.ELITE_SCALE), field + ": the elite stands 1.35x")
	check(node != null and node.has_meta(StellarShading.META_AURA), field + ": the elite wears its aura")
	# Its death: the aura and the violet line crumble with the body.
	sim.monsters.erase(elite)
	world.event({"t": "die", "p": elite["pos"], "sid": int(elite["spawn_id"]), "h": 60.0, "c": Color("#c79cff")})
	await _film("elite_%s_die" % field, 10, 3, Callable(), _focus(elite["pos"], 420, 300))
	sim.monsters.clear()
	for n in range(20): await _tick(DT)

func _scene_revive(field: String) -> void:
	stage.selected = -1
	var world: ArenaWorld = stage.view.world
	world.vfx._clear_field()
	sim.monsters.clear()
	for n in range(10):
		var path := ArenaGeometry.route_points(n % ArenaGeometry.route_count())
		_monster(["ember_imp", "frost_imp"][n % 2], path[clampi(int(path.size() * (0.2 + 0.07 * n)), 0, path.size() - 2)], Vector2.ZERO, {"stun_t": 2.5})
	# Field: the guardian joins in the same tick (the simulator adds it at the end of it).
	var gift := Roster.unit_by_id("solana")
	sim.events.append({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS, "sec": 5.0, "stun": 2.5,
		"left": 0, "unit": "solana", "tier": 9, "where": "field"})
	var spot: Vector2 = Balance.ARENA_CENTER + Vector2(150, 95)
	sim.heroes.append({"h": {"unit": gift, "tier": 9}, "pos": spot, "range": Balance.attack_range(gift, 9), "fx_t": 9.0, "fx_w": 0.35, "fx_d": Vector2.DOWN})
	await _film("revive_%s_field" % field, 30, 2)
	var node: Node3D = world.hero_node(sim.heroes.size() - 1)
	check(node != null and node.visible, field + ": the granted guardian is shown after its arrival")
	sim.heroes.pop_back()
	for n in range(60): await _tick(DT)
	# Bench: no body on the field; the star rises over the crystal.
	world.vfx._clear_field()
	sim.events.append({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS, "sec": 5.0, "stun": 2.5,
		"left": 0, "unit": "solana", "tier": 9, "where": "bench"})
	await _film("revive_%s_bench" % field, 30, 2)
	for n in range(60): await _tick(DT)
	sim.monsters.clear()

func _scene_blast(field: String) -> void:
	stage.selected = -1
	var world: ArenaWorld = stage.view.world
	for r in [110.0, 160.0]:
		world.vfx._clear_field()
		sim.monsters.clear()
		var spot: Vector2 = Balance.ARENA_CENTER + Vector2(-170, 110)
		for n in range(7): _monster(["ember_imp", "frost_imp", "drop_slime"][n % 3], spot + Vector2.from_angle(n * 0.9) * (25.0 + 18.0 * n))
		for n in range(3): await _tick(DT)
		sim.events.append({"t": "arena_blast", "p": spot, "r": r})
		await _film("blast_%s_r%d" % [field, int(r)], 18, 2, Callable(), _focus(spot, 680, 460))
		for n in range(40): await _tick(DT)
	sim.monsters.clear()

func _scene_trample(field: String) -> void:
	stage.selected = -1
	var world: ArenaWorld = stage.view.world
	world.vfx._clear_field()
	sim.monsters.clear()
	var hero_at: Vector2 = sim.heroes[3]["pos"]
	var boss_id := String({"calm_lake": "abyss_leviathan", "polar_night": "glacier_dragon", "spring_grove": "titan_bloom",
		"volcano_crater": "flame_dragon"}.get(field, "flame_dragon"))
	var from: Vector2 = hero_at + Vector2(-150, -40)
	var vel := (hero_at - from).normalized() * 70.0
	_monster(boss_id, from, vel, {"kind": "boss"})
	await _film("trample_%s" % field, 20, 3, Callable(), _focus(hero_at, 520, 380))
	sim.monsters.clear()
	for n in range(20): await _tick(DT)

## Colour calibration (development only, --scene calib): wide solid rings of candidate
## colours through the field's real tonemap and grade; the report lists where each core is.
const CALIB := [Color(1.0, 0.80, 0.25), Color(1.0, 0.70, 0.12), Color(1.0, 0.62, 0.08), Color(1.0, 0.55, 0.04),
	Color(1.0, 0.48, 0.02), Color(1.0, 0.66, 0.0), Color(0.95, 0.58, 0.0), Color(1.0, 0.72, 0.20),
	Color(0.80, 0.42, 0.40), Color(0.72, 0.36, 0.36), Color(0.80, 0.52, 1.0), Color(0.62, 0.30, 1.0)]

func _scene_calib(field: String) -> void:
	stage.selected = -1
	sim.monsters.clear()
	var world: ArenaWorld = stage.view.world
	var nodes: Array = []
	var rows: Array = []
	for i in range(CALIB.size()):
		var at: Vector2 = Balance.ARENA_CENTER + Vector2(-330 + (i % 4) * 220, -170 + (i / 4) * 170)
		var node := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2, 2)
		node.mesh = plane
		var m := ShaderMaterial.new()
		m.shader = ArenaWorld.RING_SHADER
		m.render_priority = 10
		m.set_shader_parameter("mode", 0)
		m.set_shader_parameter("radius", 1.2)
		m.set_shader_parameter("stroke_px", 26.0)
		m.set_shader_parameter("halo_px", 0.0)
		m.set_shader_parameter("fill", 0.0)
		m.set_shader_parameter("dashes", 0.0)
		m.set_shader_parameter("color", CALIB[i])
		node.material_override = m
		node.position = StellarWorld.world(at, 0.1)
		node.scale = Vector3(1.8, 1.0, 1.8)
		world.add_child(node)
		nodes.append(node)
		var top := _project(at + Vector2(0, -1.2 * StellarWorld.UNIT), 0.1)
		rows.append({"color": CALIB[i].to_html(false), "px": [top.x, top.y]})
	for n in range(3): await _tick(0.0)
	await _shot("calib_%s" % field)
	_report["calib_" + field] = rows
	for node in nodes: node.queue_free()
	await _tick(0.0)

# --------------------------------------------------------------------------- #
# The real game (--scene game): ArenaScreen, ArenaSim and its wave events (LA1, 2026-10-19)
# --------------------------------------------------------------------------- #
var main: Node2D
var screen
var _gseen: Dictionary = {}
var _grevive_event: Dictionary = {}
## Five-star arrivals seen while the real game ran: birth -> {at (world), mode (1 field, 2 bench)}.
var _garrive: Dictionary = {}

func _game(field: String) -> void:
	var index := int(FIELDS[field])
	Arena.start_run(20261019, 3)
	main = load("res://game/main.gd").new()
	_host().add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	Arena.choose_theme(index)
	Arena.confirm_summon()
	Arena.close_modal()
	await paint(screen)
	var world: ArenaWorld = screen.view_3d.world
	var sim = Arena.sim
	# The next revival's guardian is loaded under the battlefield card (ArenaWorld._keep_revival).
	var candidate: Dictionary = Arena.revive_candidate()
	print("  revival candidate: ", String(candidate.get("id", "")), " revives_left ", Arena.revives_left())
	check(Arena.revives_left() <= 0 or StellarModels.has_hero(candidate, Balance.TIER_MAX),
		field + ": the next revival's guardian (%s) was loaded under the card" % String(candidate.get("id", "")))
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(SQUAD.size()):
		Arena.gain_hero(Roster.unit_by_id(String(SQUAD[i][0])), int(SQUAD[i][1]))
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + i * TAU / 6.0 + 0.35) * 178.0
	sim.refresh_heroes()
	for i in range(sim.heroes.size()): sim.heroes[i]["pos"] = Arena.heroes[i]["position"]
	sim._rebuild_navigation()
	Arena.selected = 0
	_quiet_levels()
	world.vfx._clear_field()
	_gseen.clear()
	for n in range(4): await _gtick()
	# 1) An ordinary wave starts.
	sim.begin_wave(3)
	await _gfilm("game_%s_wave" % field, 14, 3)
	# 2) The elite wave: run until its elite steps in (guardians hold fire meanwhile).
	sim.monsters.clear()
	sim.begin_wave(5)
	var guard := 0
	var elite_seen := false
	_gseen.clear()
	while guard < 900 and not elite_seen:
		guard += 1
		for hero in sim.heroes: hero["cool"] = 1.0e9
		await _gtick()
		elite_seen = _gseen.has("arena_elite")
	check(elite_seen, field + ": the elite wave brings its elite (arena_elite)")
	await _gfilm("game_%s_elite" % field, 16, 2)
	var elite_node: Node3D = null
	for mo in sim.monsters:
		if bool(mo.get("elite", false)): elite_node = world.monster_nodes.get(int(mo["spawn_id"]))
	check(elite_node != null and is_equal_approx(elite_node.scale.x, StellarModels.ELITE_SCALE), field + ": the real elite stands 1.35x")
	screen.queue_redraw()
	await frames(1)
	await snap(out_dir + "/game_%s_elite_still.png" % field)
	# 2b) The starlight burst aimed by hand (LB1): the reticle follows the finger onto the elite,
	#     the finger lifts, the aim locks on and hands over to the falling star.
	await _gaim(field, world)
	# 3) The defence holds: everything falls, the crystal mends a little.
	sim.crystal_hp = sim.crystal_max * 0.55
	sim._wave_spawned = sim.wave_size()
	for mo in sim.monsters: mo["hp"] = 0.0
	sim._cache_positions()
	sim._reap()
	_quiet_levels()
	await _gfilm("game_%s_clear" % field, 18, 2)
	# 3b) Revivals (LA3): a free post on the field, then a full field (the bench).
	for hero in sim.heroes: hero["cool"] = 0.0
	await _grevive(field, "field")
	await _grevive(field, "bench")
	# 4) The boss: the warning at its gate, then it walks through a guardian on its road.
	for hero in sim.heroes: hero["cool"] = 0.0
	sim.monsters.clear()
	sim.jump_to_boss()
	await _gtick()
	await _gtick()
	var lane: int = int(sim.boss_lane)
	if lane >= 0:
		var road := ArenaGeometry.route_points(lane)
		var post: Vector2 = road[mini(9, road.size() - 1)]
		Arena.heroes[3]["position"] = post
		sim.heroes[3]["pos"] = post
		sim._rebuild_navigation()
	await _gfilm("game_%s_boss_warn" % field, 8, 15)
	await _gfilm("game_%s_boss" % field, 30, 3)
	check(_gseen.has("arena_wave") and _gseen.has("arena_wave_clear") and _gseen.has("arena_boss_warning") and _gseen.has("arena_boss"),
		field + ": the real flow sent the wave, clear and boss events " + str(_gseen))
	main.queue_free()
	main = null
	screen = null
	await frames(4)

## Hellbound through the real screen (see the header). The codex is set in memory and put back.
func _hellbound() -> void:
	var kept := {"seen": Save.seen_units.duplicate(), "best": Save.unit_best.duplicate(), "hell_best": Save.hell_best_wave,
		"hell_squad": Save.hell_squad.duplicate()}
	Save.seen_units = {}
	for entry in SQUAD: Save.seen_units[String(entry[0])] = true
	var ids: Array = []
	for i in range(4): ids.append(String(SQUAD[i][0]))
	check(Arena.start_hellbound(ids, 53004), "hell: Hellbound opens with a codex squad")
	main = load("res://game/main.gd").new()
	_host().add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	Arena.confirm_stage()
	await paint(screen)
	var world: ArenaWorld = screen.view_3d.world
	var sim = Arena.sim
	check(bool(Arena.hell) and sim != null, "hell: the endless battle runs")
	Arena.selected = 0
	_quiet_levels()
	_gseen.clear()
	for n in range(4): await _gtick()
	for w in [9, 10, 15, 21]:
		sim.monsters.clear()
		world.vfx._clear_field()
		var waves := int(_gseen.get("arena_wave", 0))
		var moments_before := _pool_count(world.vfx, "moment")
		sim.begin_wave(w)
		await _gtick()
		check(int(_gseen.get("arena_wave", 0)) == waves + 1, "hell: wave %d is announced (arena_wave)" % w)
		var expect_gates: bool = not sim.is_boss_wave(w)
		check(not expect_gates or _pool_count(world.vfx, "moment") > moments_before, "hell: wave %d flares its gates" % w)
		if sim.is_elite_wave(w):
			var guard := 0
			while guard < 900 and not _gseen.has("arena_elite"):
				guard += 1
				for hero in sim.heroes: hero["cool"] = 1.0e9
				await _gtick()
			check(_gseen.has("arena_elite"), "hell: the elite of wave %d steps in" % w)
			var dressed := false
			for mo in sim.monsters:
				var node: Node3D = world.monster_nodes.get(int(mo.get("spawn_id", -1)))
				if bool(mo.get("elite", false)) and node != null: dressed = is_equal_approx(node.scale.x, StellarModels.ELITE_SCALE)
			check(dressed, "hell: its elite wears the elite look")
		await _gfilm("hell_w%02d" % w, 12, 3)
	main.queue_free()
	main = null
	screen = null
	await frames(4)
	Arena.running = false
	Arena.hell = false
	Save.seen_units = kept["seen"]
	Save.unit_best = kept["best"]
	Save.hell_best_wave = kept["hell_best"]
	Save.hell_squad = kept["hell_squad"]

func _pool_count(vfx: StellarVfx, pool: String) -> int:
	var n := 0
	for fx in vfx.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == pool: n += 1
	return n

func _quiet_levels() -> void:
	Arena.xp = -1.0e9
	if "pending_levels" in Arena: Arena.pending_levels = 0
	if Arena.modal == "talent": Arena.close_modal()

## One real tick: the screen steps the simulator and draws it once (level-ups are taken at once).
func _gtick(dt: float = DT) -> void:
	if Arena.modal == "talent" and not Arena.talent_offer.is_empty():
		Arena.pick_talent(String(Arena.talent_offer[0]))
	screen._process(dt)
	# What the simulator said this tick (the draw below hands it to the world and clears it).
	if Arena.sim != null:
		for e in Arena.sim.events:
			var type := String(e.get("t", ""))
			if type.begins_with("arena_"): _gseen[type] = int(_gseen.get(type, 0)) + 1
			if type == "arena_revive": _grevive_event = e
	screen.queue_redraw()
	await frames(1)
	screen._draw_dt = 0.0
	var world = screen.view_3d.world if screen != null else null
	if world != null and is_instance_valid(world):
		for fx in world.vfx.effects:
			if typeof(fx) != TYPE_DICTIONARY or String(fx.get("vfx", "")) != "skill": continue
			var custom: Color = fx["custom"]
			if int(round(custom.a)) == StellarVfx.SkillKind.HERO_ARRIVE and not _garrive.has(str(fx["birth"])):
				_garrive[str(fx["birth"])] = {"at": fx.get("at", Vector3.INF), "mode": custom.b}

## The starlight burst through the screen's own aim (LB1, 2026-10-19): _begin_aim, a finger on
## the field that slides onto the elite (ArenaScreen._show_aim -> ArenaWorld.set_aim every
## picture), then the finger lifts (_drop_aim -> cast_skill('blast', aim_point())).
func _gaim(field: String, world: ArenaWorld) -> void:
	var sim = Arena.sim
	var elite: Dictionary = {}
	for mo in sim.monsters:
		if bool(mo.get("elite", false)) and float(mo["hp"]) > 0.0: elite = mo
	Arena.gold = 999999
	check(not elite.is_empty() and screen._skill_ready("blast"), field + ": the burst can be aimed at the elite " + str(sim.skill_state("blast")))
	if elite.is_empty() or not screen._skill_ready("blast"): return
	var prefix := "game_%s_aim" % field
	var start: Vector2 = BattleSim.mpos(elite) + Vector2(-200, 120)
	screen._begin_aim()
	screen._take_aim(0, screen.view_3d.project(start, 0.0))
	var shown := 0
	for n in range(12):
		var target: Vector2 = BattleSim.mpos(elite)
		screen.aim_pixel = screen.view_3d.project(start.lerp(target, minf(1.0, (n + 1) / 9.0)), 0.0)
		await _gtick()
		if (world.get("_aim") as Node3D).visible and bool(world.get("_aim_state")["shown"]): shown += 1
		await snap(out_dir + "/%s_%02d.png" % [prefix, n])
	check(shown >= 10 and bool(world.get("_aim_state")["valid"]), field + ": the screen's aim draws the gold reticle on the ground (%d pictures)" % shown)
	var blasts := int(_gseen.get("arena_blast", 0))
	screen._drop_aim(screen.aim_pixel)
	await _gtick()
	var locked := float(world.get("_aim_state")["locked"]) > 0.0 and (world.get("_aim") as Node3D).visible
	await snap(out_dir + "/%s_%02d.png" % [prefix, 12])
	check(int(_gseen.get("arena_blast", 0)) == blasts + 1 and locked, field + ": the cast locks the reticle on and the star falls there")
	for n in range(13, 26):
		await _gtick()
		await snap(out_dir + "/%s_%02d.png" % [prefix, n])
	check(not (world.get("_aim") as Node3D).visible, field + ": the reticle is gone once the star has it")
	_seq(prefix, 26, 1)

## A revival in the real flow (LA3): a monster at the altar strikes while the crystal is nearly
## gone, inside a tick; the crystal reforms and the run grants a five-star guardian, on the field
## while there is a free post (`where` "field"), else on the bench.
func _grevive(field: String, where: String) -> void:
	var sim = Arena.sim
	var world: ArenaWorld = screen.view_3d.world
	sim.monsters.clear()
	if where == "field" and Arena.heroes.size() >= Balance.ARENA_HERO_LIMIT:
		Arena.heroes.remove_at(Arena.heroes.size() - 1)
		sim.refresh_heroes()
		await _gtick()
	check(Arena.field_full() == (where == "bench"), field + ": the field is %s before the revival" % ("full" if where == "bench" else "open"))
	sim._spawn(Arena.wave_spawns(Arena.stage, 1)[0]["m"])
	var mo: Dictionary = sim.monsters[sim.monsters.size() - 1]
	mo["pos"] = Balance.ARENA_CENTER + Vector2(Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS - 2, 0)
	mo["hp"] = 1.0e9
	mo["max"] = 1.0e9
	mo["siege_t"] = 0.99
	sim.invuln_t = 0.0
	sim.shield = 0.0
	sim.crystal_hp = 0.01
	var before: int = sim.revives
	_grevive_event = {}
	_garrive.clear()
	var guard := 0
	var spent := 0
	while sim.revives == before and guard < 150:
		guard += 1
		var t0 := Time.get_ticks_usec()
		await _gtick()
		spent = Time.get_ticks_usec() - t0
	check(sim.revives == before + 1, field + ": the crystal broke inside a tick and reformed (%s)" % where)
	# The breaker falls to the guardians' next shots (an unkillable body at the altar would bury
	# the crystal under hit sparks for the whole arrival).
	for body in sim.monsters:
		body["hp"] = minf(float(body["hp"]), 1.0)
		body["max"] = minf(float(body["max"]), 40.0)
	var e := _grevive_event
	var unit := String(e.get("unit", ""))
	print("  revival (%s): %s, tick with the new guardian %.1f ms" % [where, str(e), spent / 1000.0])
	check(unit != "" and int(e.get("tier", -1)) == Balance.TIER_MAX and String(e.get("where", "")) == where and not e.has("gold"),
		field + ": arena_revive names its guardian, grade and place " + str(e))
	if where == "field":
		var held: Node3D = world.held_hero(unit)
		check(held != null and not held.visible, field + ": the granted guardian waits out of sight until its star lands")
	await _gfilm("game_%s_revive_%s" % [field, where], 32 if where == "field" else 28, 3)
	var arrivals: Array = _garrive.values()
	if where == "field":
		var node: Node3D = world.held_hero(unit)
		check(node != null and node.visible, field + ": it stands on the field after its arrival")
		var ok := node != null and arrivals.size() == 1 and is_equal_approx(float(arrivals[0]["mode"]), 1.0) \
			and Vector2(arrivals[0]["at"].x - node.global_position.x, arrivals[0]["at"].z - node.global_position.z).length() < 0.4
		check(ok, field + ": its star landed where it stands " + str(arrivals))
	else:
		var crystal := StellarWorld.world(Balance.ARENA_CENTER, 0.0)
		var ok := arrivals.size() == 1 and is_equal_approx(float(arrivals[0]["mode"]), 2.0) \
			and Vector2(arrivals[0]["at"].x - crystal.x, arrivals[0]["at"].z - crystal.z).length() < 0.05
		check(ok, field + ": the bench guardian was crowned over the crystal " + str(arrivals))
	sim.monsters.clear()
	await _gtick()

func _gfilm(prefix: String, count: int, ticks: int) -> void:
	for n in range(count):
		for k in range(ticks): await _gtick()
		screen.queue_redraw()
		await frames(1)
		await snap(out_dir + "/%s_%02d.png" % [prefix, n])
	_seq(prefix, count, ticks)

## The selection ring of 2026-10-18 (arena_world.gd set_selection before D3), for --old-ring.
func _old_ring(world: ArenaWorld, at: Vector2, radius: float) -> Node3D:
	var root := Node3D.new()
	world.add_child(root)
	root.position = StellarWorld.world(at, 0.10)
	StellarModels.part(root, "ring", Vector3.ZERO, Vector3(1.0, 0.038, 1.0), Color("#ffe0a1"), 0.25, 0.35)
	for side in [-1, 1]:
		StellarModels.part(root, "cone", Vector3(side * 0.54, 0.09, 0), Vector3(0.10, 0.16, 0.10), Color("#ffe0a1"), 0, 0.3)
	for n in range(56):
		var a := Vector3(cos(TAU * n / 56.0), 0.035, sin(TAU * n / 56.0)) * (radius / StellarWorld.UNIT)
		var b := Vector3(cos(TAU * (n + 0.55) / 56.0), 0.035, sin(TAU * (n + 0.55) / 56.0)) * (radius / StellarWorld.UNIT)
		StellarModels.link(root, a, b, 0.019, Color("#ebc77f"), 0.1, 0.15)
	StellarModels.compact(root)
	return root
