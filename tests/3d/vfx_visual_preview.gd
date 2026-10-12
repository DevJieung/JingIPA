extends Harness

## Real GL capture of the battle VFX layer in the continuous arena: muzzle release,
## projectiles and trails, impacts, beams / chain / ricochet, zones, deaths, spawns,
## status bursts, guardian skills and crystal hits, as consecutive frames.
##
##   godot --path . --resolution 1280x800 res://tests/3d/vfx_visual_preview.tscn -- --out DIR
##   options: --squad a|b|all  --theme N  --frames N  --quick  --skills-only  --gate-only  --probe
##   special modes (each replaces the squad run; they can be combined):
##     --death-only      deaths on open ground at every tick: six bodies killed through the
##                       simulator (kill_*), then four killed by the Starlight Burst (blast_*),
##                       once in the theme's own colours (plain_*) and once with the
##                       environment clear colour set to magenta (marker_*). Every frame must
##                       leave the 3D viewport's alpha at 1 (an alpha below 1 lets the screen's
##                       2D backdrop through as a dark hole), and the marker pass must never
##                       show the clear colour through a dying body (a depth-only silhouette).
##     --dissolve-probe  one body and a static control box frozen at fixed material states
##                       over a magenta clear colour, with pixel statistics of the screen
##                       region and the alpha the 3D viewport stored there (probe_*.png).
##     --boss-melee      the theme boss (root scale 2) pinned between two sword guardians
##                       with a rifle, a bow, an artillery piece and a beam rifle further out,
##                       and burn / frost / stun marks: blade contacts, impacts and status
##                       marks on the doubled body, at the game camera (boss_melee_*) and at
##                       a review zoom (boss_zoom_*). --no-body-fit shows the same fight as
##                       it was before bursts and marks followed the body's scale.
## Skill sequences: <squad>_skill_<blast|freeze|ward> at 2 ticks per frame (66 ms, 1.5 s),
## <squad>_blast_slow at 1 tick per frame (the fall and impact), and the boss gate:
## <squad>_gate_warn (arena_boss_warning, 6 ticks per frame over 4 s) then <squad>_gate_burst
## (arena_boss, 1 tick per frame). The gate events go straight to vfx.arena_event with the
## same payload the arena world forwards.
## Squad a: echo(bow/none) kari(rifle/ice splash) brasa(cast/fire zone) jokull(sword/ice pierce)
##          triton(artillery/water) limne(water zone, own spray)
## Squad b: rhiannon(cast/elec chain) brian(rifle/elec beam) protea(bow/water ricochet)
##          conor(rifle/elec) pip(tool/none) finn(sword/elec)
## tools/3d/vfx_review.py runs both window sizes and assembles GIF / MP4 / contact sheets.

const SQUADS := {
	"a": ["echo", "kari", "brasa", "jokull", "triton", "limne"],
	"b": ["rhiannon", "brian", "protea", "conor", "pip", "finn"],
}
var out_dir := "build/motion-overhaul/vfx/1280x800"
var screen: ArenaScreen
var main: Node2D
var _frames := 36
var _report: Dictionary = {"sequences": [], "events": {}}
var _marker_seen := Color(1.0, 0.0, 1.0)
var _alpha_leaks: PackedStringArray = []
var _window_scale := Vector2.ZERO

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_frames = int(arg("--frames", "36"))
	if has_arg("--quick"): _frames = 12
	var wanted := arg("--squad", "all")
	var squads := SQUADS.keys() if wanted == "all" else [wanted]
	var theme := int(arg("--theme", "0"))
	I18n.set_locale("ko")
	var special := false
	if has_arg("--dissolve-probe"):
		special = true
		await _dissolve_probe(theme)
	if has_arg("--death-only"):
		special = true
		await _deaths(theme)
	if has_arg("--boss-melee"):
		special = true
		await _boss_melee(theme)
	if not special:
		for squad in squads:
			await _squad(String(squad), theme)
	var file := FileAccess.open(out_dir + "/vfx-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "  ") + "\n")
	file = null
	finish("VFX visual preview (%d frames per sequence)" % _frames)

func _squad(squad: String, theme: int) -> void:
	Arena.start_run(20261010 + squad.hash() % 1000)
	main = load("res://game/main.gd").new()
	add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	Arena.choose_theme(theme)
	Arena.confirm_summon()
	Arena.close_modal()
	# The 3D view attaches its world on the first paint.
	await paint(screen)
	_field(SQUADS[squad])
	var world: StellarWorld = screen.view_3d.world
	check(world.vfx != null and world.vfx.get_child_count() >= 6, squad + ": VFX pools are built once at start")
	var pools_before := world.vfx.get_child_count()
	var materials_before := _material_ids(world.vfx)
	# Warm up so the first volley is already in flight, then record consecutive frames.
	for n in range(24): await _tick()
	if not has_arg("--skills-only"):
		for n in range(_frames):
			await _tick()
			await _capture("%s_battle_%02d" % [squad, n])
		_note(squad + "_battle", _frames, 1)
		# Broader coverage: three ticks per frame for a few seconds of actual fighting.
		for n in range(_frames / 2):
			for k in range(3): await _tick()
			await _capture("%s_fight_%02d" % [squad, n])
		_note(squad + "_fight", _frames / 2, 3)
	check(world.vfx.get_node_or_null("Skills") != null, squad + ": the Skills sequence pool exists at start-up")
	if not has_arg("--gate-only"):
		# Guardian skills, each through the actual simulator entry point.
		for skill in ["blast", "freeze", "ward"]:
			Arena.sim.skill_cooldowns[skill] = 0.0
			check(Arena.sim.cast_skill(skill), squad + ": skill casts " + skill)
			for n in range(22):
				for k in range(2): await _tick()
				await _capture("%s_skill_%s_%02d" % [squad, skill, n])
			_note("%s_skill_%s" % [squad, skill], 22, 2)
			for k in range(12): await _tick()
		# The blast once more at every tick: the fall, the impact and the ring reaching R.
		Arena.sim.skill_cooldowns["blast"] = 0.0
		check(Arena.sim.cast_skill("blast"), squad + ": blast casts again for the slow capture")
		for n in range(18):
			await _tick()
			if n == 0: check(_live_skills(world) >= 1, squad + ": the blast occupies one Skills instance once drawn")
			await _capture("%s_blast_slow_%02d" % [squad, n])
		_note(squad + "_blast_slow", 18, 1)
		for k in range(30): await _tick()
	if has_arg("--probe"):
		# The blast alone on an empty patch of ground (no bodies, no deaths): isolates the
		# sequence's own layers from monster presentation.
		var spot: Vector2 = Balance.ARENA_CENTER + Vector2(0, 190)
		world.vfx.arena_event({"t": "arena_blast", "p": spot, "r": Balance.ARENA_BLAST_RADIUS})
		for n in range(22):
			for k in range(2): await _tick()
			await _capture("%s_blast_probe_%02d" % [squad, n])
		_note(squad + "_blast_probe", 22, 2)
		for k in range(12): await _tick()
	# The boss gate: a four-second warning at a gate, then the arrival at the same point.
	var gate := _visible_gate()
	world.vfx.arena_event({"t": "arena_boss_warning", "p": gate, "sec": 4.0})
	check(_live_skills(world) >= 1, squad + ": the gate warning occupies one Skills instance")
	for n in range(20):
		for k in range(6): await _tick()
		await _capture("%s_gate_warn_%02d" % [squad, n])
	_note(squad + "_gate_warn", 20, 6)
	world.vfx.arena_event({"t": "arena_boss", "p": gate})
	for n in range(24):
		await _tick()
		await _capture("%s_gate_burst_%02d" % [squad, n])
	_note(squad + "_gate_burst", 24, 1)
	for k in range(12): await _tick()
	# Crystal hit (more than the ward absorbs) and a passive block, plus fresh portal spawns.
	Arena.sim._damage_crystal(Balance.ARENA_WARD_SHIELD + 40.0, Balance.ARENA_CENTER)
	world.event({"t": "block", "p": Balance.ARENA_CENTER + Vector2(120, -40), "h": 35.0})
	var pool := Roster.theme_pool(Arena.theme_for(1))
	for n in range(3): Arena.sim._spawn(pool[(n * 5) % pool.size()])
	# Fresh spawns get their bodies on the next drawn tick.
	await _tick()
	# Review-only: the shared looping status markers offered to the body adapters,
	# attached to up to three live bodies (adapters decide whether to adopt them).
	var shown := 0
	for sid in world.monster_nodes:
		if shown >= 3: break
		var body: Node3D = world.monster_nodes[sid]
		var marker := StellarVfx.status_group(["Burn", "Frost", "Stun"][shown], _body_height(body))
		marker.name = "ReviewStatus"
		marker.visible = true
		body.add_child(marker)
		shown += 1
	check(shown >= 1, squad + ": status markers attach to live bodies")
	for n in range(10):
		await _tick()
		await _capture("%s_events_%02d" % [squad, n])
	_note(squad + "_events", 10, 1)
	var counts := _count_effects(world)
	for key in counts: _report["events"][squad + ":" + key] = counts[key]
	check(world.vfx.get_child_count() == pools_before, squad + ": no VFX node is created after start-up")
	check(_material_ids(world.vfx) == materials_before, squad + ": no VFX material is created during battle")
	check(world.effects.size() <= 72, squad + ": one-shot effects respect the shared 72 budget")
	var bullets: MultiMeshInstance3D = world.vfx.get_node("Bullets")
	check(bullets.multimesh.visible_instance_count == mini(120, Arena.sim.bullets.size()), squad + ": projectile instances mirror the simulator list")
	check(_pause_freezes(world), squad + ": a paused battle (dt 0) does not advance the effect clock")
	check(_alpha_leaks.is_empty(), "%s: the 3D viewport keeps alpha 1 in every captured frame (%d leak, first %s)" % [squad, _alpha_leaks.size(), ", ".join(_alpha_leaks.slice(0, 5))])
	_alpha_leaks.clear()
	main.queue_free()
	main = null
	screen = null
	await frames(4)

# --------------------------------------------------------------------------- #
# Special modes: death dissolve, material probe, boss scale
# --------------------------------------------------------------------------- #
const DEATH_IDS := ["jelly_seer", "drop_slime", "wave_giant", "frost_imp", "elder_treant", "runestone_idol"]
const BLAST_IDS := ["jelly_seer", "rapid_ray", "blaze_fox", "spore_cap"]
const MARKER := Color(1.0, 0.0, 1.0)

## The real arena screen on `theme` with no guardians and no enemies: bare ground.
func _open_arena(theme: int, seed_value: int) -> StellarWorld:
	Arena.start_run(seed_value)
	main = load("res://game/main.gd").new()
	add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	Arena.choose_theme(theme)
	Arena.confirm_summon()
	Arena.close_modal()
	await paint(screen)
	Arena.heroes.clear()
	Arena.bench.clear()
	Arena.sim.refresh_heroes()
	Arena.selected = -1
	Arena.sim.monsters.clear()
	Arena.sim._rebuild_navigation()
	screen.view_3d._follow_offset = Vector3.ZERO
	screen.view_3d._camera_initialized = true
	screen.view_3d._apply_camera(Vector3.ZERO)
	return screen.view_3d.world

func _close_arena() -> void:
	main.queue_free()
	main = null
	screen = null
	await frames(4)

func _put(id: String, at: Vector2) -> Dictionary:
	Arena.sim._spawn(Roster.monster_by_id(id))
	var mo: Dictionary = Arena.sim.monsters[-1]
	mo["pos"] = at
	mo["vel"] = Vector2.ZERO
	return mo

## Hold bodies on their spots: the simulator walks them a pixel per tick otherwise.
func _pin(bodies: Array, spots: Array) -> void:
	for i in range(bodies.size()):
		bodies[i]["pos"] = spots[i]
		bodies[i]["vel"] = Vector2.ZERO

func _environment(world: StellarWorld) -> Environment:
	for child in world.get_children():
		if child is WorldEnvironment: return child.environment
	return null

## Canvas (design-space) rectangle that contains a body of `height` world units standing
## on `at`. The 3D viewport is rendered at design size; screenshots are window pixels
## (see _to_window).
func _body_rect(at: Vector2, height: float, pad: float = 10.0) -> Rect2i:
	var view = screen.view_3d
	var half := maxf(height, 0.8) * 0.9 * StellarWorld.UNIT
	var points: Array = [view.project(at + Vector2(-half, 0), 0.0), view.project(at + Vector2(half, 0), 0.0),
		view.project(at + Vector2(0, -half), 0.0), view.project(at + Vector2(0, half), 0.0),
		view.project(at, height * 1.25 + 0.2)]
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points: rect = rect.expand(point)
	var window := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
	return Rect2i(rect.grow(pad).intersection(window))

## A canvas rectangle in the pixels of a window screenshot. The scale is measured from an
## actual screenshot against the project's design size (canvas_items stretch).
func _to_window(rect: Rect2i) -> Rect2i:
	if _window_scale == Vector2.ZERO:
		var design := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
			float(ProjectSettings.get_setting("display/window/size/viewport_height")))
		_window_scale = Vector2(get_viewport().get_texture().get_image().get_size()) / design
		print("window pixels per canvas unit: ", _window_scale)
	return Rect2i(Rect2(Vector2(rect.position) * _window_scale, Vector2(rect.size) * _window_scale).grow(1.0))

func _rect_row(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

## The marker clear colour as the window shows it (tonemapped), within a small tolerance.
func _is_marker(c: Color) -> bool:
	return absf(c.r - _marker_seen.r) < 0.03 and absf(c.g - _marker_seen.g) < 0.03 and absf(c.b - _marker_seen.b) < 0.03

func _marker_pixels(img: Image, rect: Rect2i) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if _is_marker(img.get_pixel(x, y)): n += 1
	return n

## What the marker clear colour looks like on screen: one paused frame with the terrain
## and the actors hidden, sampled where nothing else draws.
func _measure_marker(world: StellarWorld, at: Vector2) -> void:
	var hidden: Array = []
	for child in world.get_children():
		if child is Node3D and not (child is Camera3D) and not (child is Light3D) and child.visible:
			child.visible = false
			hidden.append(child)
	screen.queue_redraw()
	await frames(2)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var px := _to_window(Rect2i(Vector2i(screen.view_3d.project(at, 0.0)), Vector2i.ONE)).position
	_marker_seen = img.get_pixel(px.x, px.y)
	for child in hidden: child.visible = true
	_report["marker_seen"] = [_marker_seen.r, _marker_seen.g, _marker_seen.b]
	print("marker clear colour on screen: ", _marker_seen)

## Pixels of the 3D viewport itself whose alpha is below 1 inside the canvas rectangles,
## and whether any pixel of the whole viewport is. A non-transparent viewport must store
## alpha 1 everywhere: the arena blends its texture over the 2D backdrop.
func _alpha_holes(rects: Array) -> Dictionary:
	var view = screen.view_3d
	var img: Image = view.viewport.get_texture().get_image()
	var offset := Vector2i(view.box.position)
	var count := 0
	for rect in rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var px := Vector2i(x, y) - offset
				if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height(): continue
				if img.get_pixel(px.x, px.y).a < 0.999: count += 1
	return {"rects": count, "anywhere": img.detect_alpha() != Image.ALPHA_NONE}

## How a state differs from the reference (the same view without the body) inside `rect`:
## pixels that changed, how many of those show the marker clear colour, how many turned
## dark over a bright reference, and the mean colour of the changed pixels.
func _region_stats(img: Image, ref: Image, rect: Rect2i) -> Dictionary:
	var changed := 0
	var marker := 0
	var dark := 0
	var sum := Vector3.ZERO
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := img.get_pixel(x, y)
			var r := ref.get_pixel(x, y)
			if maxf(absf(c.r - r.r), maxf(absf(c.g - r.g), absf(c.b - r.b))) <= 0.09: continue
			changed += 1
			sum += Vector3(c.r, c.g, c.b)
			if _is_marker(c): marker += 1
			elif c.get_luminance() < 0.12 and r.get_luminance() > 0.25: dark += 1
	var mean := sum / float(maxi(changed, 1))
	return {"changed": changed, "marker": marker, "dark": dark,
		"mean": [snappedf(mean.x, 0.001), snappedf(mean.y, 0.001), snappedf(mean.z, 0.001)]}

## Lowest alpha the 3D viewport itself stored under the canvas rectangle `rect`.
func _viewport_alpha(rect: Rect2i) -> float:
	var view = screen.view_3d
	var img: Image = view.viewport.get_texture().get_image()
	var offset := Vector2i(view.box.position)
	var lowest := 1.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var px := Vector2i(x, y) - offset
			if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height(): continue
			lowest = minf(lowest, img.get_pixel(px.x, px.y).a)
	return lowest

func _shot(name: String) -> Image:
	screen.queue_redraw()
	await frames(2)
	return await snap(out_dir + "/" + name + ".png")

## Material cause probe. A standing body is frozen (paused redraws only) and its
## per-instance materials are forced through fixed states over a magenta clear colour,
## so a pixel that shows the clear colour (depth written, colour discarded) cannot be
## mistaken for ground or for the 2D backdrop behind the viewport texture.
func _dissolve_probe(theme: int) -> void:
	var world := await _open_arena(theme, 20261012)
	var env := _environment(world)
	var natural := env.background_color
	var spot: Vector2 = Balance.ARENA_CENTER + Vector2(-150, 150)
	var id := arg("--probe-id", "jelly_seer")
	var mo := _put(id, spot)
	mo["hp"] = 1.0e9
	mo["max"] = 1.0e9
	Arena.sim._rebuild_navigation()
	for n in range(30):
		_pin([mo], [spot])
		await _tick()
	_pin([mo], [spot])
	var sid := int(mo["spawn_id"])
	var node: Node3D = world.monster_nodes[sid]
	var height := _body_height(node) * node.scale.y
	var canvas_rect := _body_rect(spot, height)
	var rect := _to_window(canvas_rect)
	var materials: Array = node.get_meta("_stellar_materials", [])
	check(not materials.is_empty(), "probe: the body owns per-instance materials")
	# A static, unskinned control mesh with its own alpha-hash material next to the body.
	var box_spot: Vector2 = spot + Vector2(170, 0)
	var box := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.7, 0.7, 0.7)
	box.mesh = cube
	var box_material := StandardMaterial3D.new()
	box_material.albedo_color = Color(0.95, 0.75, 0.15, 1.0)
	box_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	box.material_override = box_material
	box.position = StellarWorld.world(box_spot, 0.36)
	world.add_child(box)
	var box_rect := _to_window(_body_rect(box_spot, 0.7))
	env.background_color = MARKER
	await _measure_marker(world, spot)
	node.visible = false
	box.visible = false
	var ref := await _shot("probe_reference")
	node.visible = true
	box.visible = true
	var rows: Array = []
	# Alpha-hash states step through the alpha range: where the stored alpha drops to 0
	# is where the body turns into a hole.
	var states: Array = [
		["hash_a100", "hash", 1.0], ["hash_a050", "hash", 0.5], ["hash_a040", "hash", 0.4],
		["hash_a030", "hash", 0.3], ["hash_a025", "hash", 0.25], ["hash_a020", "hash", 0.2],
		["hash_a018", "hash", 0.18], ["hash_a017", "hash", 0.17], ["hash_a016", "hash", 0.16],
		["hash_a015", "hash", 0.15], ["hash_a008", "hash", 0.08],
		["hash_a0001", "hash", 0.001], ["hash_a000", "hash", 0.0],
		["hash_nodepth_a000", "hash_nodepth", 0.0],
		["scissor_a060", "scissor", 0.6], ["scissor_a040", "scissor", 0.4],
		["dither_f075", "dither", 0.75], ["dither_f050", "dither", 0.5], ["dither_f025", "dither", 0.25],
		["dither_f000", "dither", 0.0],
		["opaque_a000", "opaque", 0.0], ["hidden", "hidden", 1.0]]
	for state in states:
		_probe_apply(node, materials, String(state[1]), float(state[2]))
		box_material.albedo_color.a = float(state[2]) if String(state[1]) == "hash" else 1.0
		var img := await _shot("probe_" + String(state[0]))
		var row := _region_stats(img, ref, rect)
		row["state"] = state[0]
		row["viewport_alpha_min"] = snappedf(_viewport_alpha(canvas_rect), 0.001)
		# The 3D viewport's own pixel at the body's chest and the window pixel over it.
		var chest: Vector2 = screen.view_3d.project(spot, height * 0.5)
		var raw: Color = screen.view_3d.viewport.get_texture().get_image().get_pixelv(Vector2i(chest - screen.view_3d.box.position))
		var shown: Color = img.get_pixelv(_to_window(Rect2i(Vector2i(chest), Vector2i.ONE)).position + Vector2i.ONE)
		row["viewport_pixel"] = [snappedf(raw.r, 0.001), snappedf(raw.g, 0.001), snappedf(raw.b, 0.001), snappedf(raw.a, 0.001)]
		row["window_pixel"] = [roundi(shown.r * 255.0), roundi(shown.g * 255.0), roundi(shown.b * 255.0)]
		if String(state[1]) == "hash":
			var box_row := _region_stats(img, ref, box_rect)
			row["box"] = {"changed": box_row["changed"], "marker": box_row["marker"], "mean": box_row["mean"]}
		rows.append(row)
		print("probe ", JSON.stringify(row))
	# The shipped path: StellarShading's own configuration and curve through the fade.
	_probe_apply(node, materials, "game", 1.0)
	box.visible = false
	var view_distance := world.camera.global_position.distance_to(node.global_position)
	var solid := 0
	for q in [0.0, 0.30, 0.46, 0.62, 0.80, 0.92, 1.0]:
		StellarShading.set_dissolve(node, q)
		var img := await _shot("probe_game_q%03d" % int(round(q * 100.0)))
		var row := _region_stats(img, ref, rect)
		row["state"] = "game_q%.2f" % q
		row["material_alpha"] = snappedf(float(materials[0].albedo_color.a), 0.001)
		row["viewport_alpha_min"] = snappedf(_viewport_alpha(canvas_rect), 0.001)
		# What the material's dither lets through at this body's distance from the camera.
		var mat: StandardMaterial3D = materials[0]
		var visible := smoothstep(mat.distance_fade_min_distance, mat.distance_fade_max_distance, view_distance)
		var wanted := 1.0 - smoothstep(StellarShading.DISSOLVE_HOLD, StellarShading.DISSOLVE_END, q)
		row["dither_visible"] = snappedf(visible, 0.001)
		if q == 0.0: solid = int(row["changed"])
		row["pixels_vs_solid"] = snappedf(float(row["changed"]) / float(maxi(solid, 1)), 0.001)
		rows.append(row)
		print("probe ", JSON.stringify(row))
		check(absf(visible - wanted) < 0.02, "probe: dissolve %.2f leaves %.3f of the body (curve asks %.3f)" % [q, visible, wanted])
		check(is_equal_approx(mat.albedo_color.a, 1.0) and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "probe: the dissolve never touches alpha (q %.2f)" % q)
		check(float(row["viewport_alpha_min"]) > 0.999, "probe: the 3D viewport keeps alpha 1 under the body at dissolve %.2f" % q)
		if q >= StellarShading.DISSOLVE_END:
			check(int(row["changed"]) == 0, "probe: a finished dissolve leaves no pixel of the body (%d changed)" % int(row["changed"]))
	check(solid > 200, "probe: the whole body is drawn before the fade (%d px)" % solid)
	# The same end state in the theme's own colours: what the player sees.
	env.background_color = natural
	node.visible = false
	var natural_ref := await _shot("probe_natural_reference")
	node.visible = true
	var seen := await _shot("probe_natural_q100")
	var natural_row := _region_stats(seen, natural_ref, rect)
	natural_row["state"] = "natural_q1.00"
	rows.append(natural_row)
	print("probe ", JSON.stringify(natural_row))
	StellarShading.set_dissolve(node, 0.0)
	_report["probe"] = {"id": id, "rect": _rect_row(rect), "box_rect": _rect_row(box_rect), "rows": rows}
	box.free()
	await _close_arena()

## Force the probe body's materials into one named configuration (probe only: the game
## never switches features at run time).
func _probe_apply(node: Node3D, materials: Array, mode: String, value: float) -> void:
	_set_meshes_visible(node, mode != "hidden")
	for mat in materials:
		mat.emission_energy_multiplier = 0.0
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
		var albedo: Color = mat.albedo_color
		albedo.a = 1.0
		match mode:
			"hash":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
				albedo.a = value
			"hash_nodepth":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
				mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				albedo.a = value
			"scissor":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.5
				albedo.a = value
			"dither":
				# The shipped mechanism: the distance-fade pixel dither with a window far
				# wider than the scene, so the visible fraction is `value` everywhere.
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
				StellarShading._set_visible(mat, value)
			"opaque":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				albedo.a = value
			"game":
				StellarShading._instance_features(mat)
				continue
			_:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color = albedo
	if mode == "game":
		# Force the next set_dissolve to write through, whatever the probe left behind.
		node.set_meta("dissolve", -1.0)
		StellarShading.set_dissolve(node, 0.0)

func _set_meshes_visible(node: Node, on: bool) -> void:
	if node is MeshInstance3D and not String(node.name).begins_with("Stellar"): node.visible = on
	for child in node.get_children(): _set_meshes_visible(child, on)

## Deaths at every tick, through the real simulator paths.
func _deaths(theme: int) -> void:
	var world := await _open_arena(theme, 20261012)
	var env := _environment(world)
	var natural := env.background_color
	var ring: Array = []
	for i in range(DEATH_IDS.size()):
		ring.append(Balance.ARENA_CENTER + Vector2.from_angle(0.35 + i * TAU / DEATH_IDS.size()) * 200.0)
	var hub: Vector2 = Balance.ARENA_CENTER + Vector2(150, 110)
	# Every body within the burst radius (110) of the one nearest the crystal, which it targets.
	var cluster: Array = [hub, hub + Vector2(48, -12), hub + Vector2(-36, 30), hub + Vector2(12, 50)]
	for marker in [false, true]:
		env.background_color = MARKER if marker else natural
		if marker: await _measure_marker(world, ring[0])
		var tag := "marker" if marker else "plain"
		await _death_sequence(world, DEATH_IDS, ring, tag + "_kill", false, marker)
		await _death_sequence(world, BLAST_IDS, cluster, tag + "_blast", true, marker)
	env.background_color = natural
	await _close_arena()

func _death_sequence(world: StellarWorld, ids: Array, spots: Array, prefix: String, blast: bool, marker: bool) -> void:
	Arena.sim.monsters.clear()
	var bodies: Array = []
	for i in range(ids.size()): bodies.append(_put(String(ids[i]), spots[i]))
	Arena.sim._rebuild_navigation()
	# The entrance (0.8 s) settles with the bodies held in place.
	for n in range(30):
		_pin(bodies, spots)
		await _tick()
	_pin(bodies, spots)
	var canvas_rects: Array = []
	var rects: Array = []
	var rect_rows: Array = []
	for i in range(bodies.size()):
		var node: Node3D = world.monster_nodes[int(bodies[i]["spawn_id"])]
		var canvas_rect := _body_rect(spots[i], _body_height(node) * node.scale.y, 14.0)
		canvas_rects.append(canvas_rect)
		rects.append(_to_window(canvas_rect))
		rect_rows.append(_rect_row(rects[-1]))
	Arena.sim._cache_positions()
	if blast:
		for mo in bodies: mo["hp"] = 1.0
		Arena.sim.skill_cooldowns["blast"] = 0.0
		check(Arena.sim.cast_skill("blast"), prefix + ": the Starlight Burst casts on the cluster")
	else:
		for i in range(Arena.sim.monsters.size()): Arena.sim._hurt(i, 1.0e9, false, -1, "none", false)
		Arena.sim._reap()
	var alive := 0
	for mo in bodies:
		if Arena.sim.monsters.has(mo): alive += 1
	check(alive == 0, "%s: every placed body died in the simulator (%d left)" % [prefix, alive])
	var count := 54
	var worst := 0
	var worst_frame := -1
	var leaks := 0
	var leak_worst := 0
	var leak_frame := -1
	var leaky_frames := 0
	var holes: Array = []
	var alpha_holes: Array = []
	for n in range(count):
		await _tick()
		var img := await _shot("%s_%02d" % [prefix, n])
		# The frame the screenshot shows is the one the 3D viewport still holds.
		var alpha := _alpha_holes(canvas_rects)
		alpha_holes.append(int(alpha["rects"]))
		if bool(alpha["anywhere"]): leaky_frames += 1
		leaks += int(alpha["rects"])
		if int(alpha["rects"]) > leak_worst:
			leak_worst = int(alpha["rects"])
			leak_frame = n
		if marker:
			var total := 0
			for rect in rects: total += _marker_pixels(img, rect)
			holes.append(total)
			if total > worst:
				worst = total
				worst_frame = n
	check(leaks == 0 and leaky_frames == 0, "%s: the 3D viewport keeps alpha 1 while bodies die (worst %d px under the bodies at frame %d, %d of %d frames leak somewhere)" % [prefix, leak_worst, leak_frame, leaky_frames, count])
	print("deaths %s viewport alpha<1 pixels under the bodies per frame: %s" % [prefix, JSON.stringify(alpha_holes)])
	if marker:
		check(worst == 0, "%s: no dying body shows the clear colour instead of the ground (worst %d px at frame %d)" % [prefix, worst, worst_frame])
		print("deaths %s clear-colour pixels under the bodies per frame: %s" % [prefix, JSON.stringify(holes)])
	_report["sequences"].append({"prefix": prefix, "frames": count, "ticks_per_frame": 1, "tick": 1.0 / 30.0,
		"rects": rect_rows, "labels": ids, "holes": holes, "alpha_holes": alpha_holes, "leaky_frames": leaky_frames})
	for n in range(30): await _tick()

## The theme boss at root scale 2 between two sword guardians: blade contacts must land on
## its body, and the burn / frost / stun marks must fit the doubled body.
func _boss_melee(theme: int) -> void:
	var world := await _open_arena(theme, 20261013)
	var spot: Vector2 = Balance.ARENA_CENTER + Vector2(30, 185)
	var blades: Array = ["jokull", "finn"]
	var sides: Array = [Vector2(-1.0, 0.08).normalized(), Vector2(1.0, -0.05).normalized()]
	# Ranged guardians further out: ice splash rifle, bow, water artillery, beam rifle.
	var shooters: Array = ["kari", "echo", "triton", "brian"]
	var posts: Array = [Vector2(175, 95), Vector2(-165, 105), Vector2(20, 185), Vector2(-185, -55)]
	for i in range(blades.size()):
		Arena.gain_hero(Roster.unit_by_id(String(blades[i])), 6)
		Arena.heroes[i]["position"] = spot + sides[i] * 80.0
	for i in range(shooters.size()):
		Arena.gain_hero(Roster.unit_by_id(String(shooters[i])), 6)
		Arena.heroes[blades.size() + i]["position"] = spot + posts[i]
	Arena.sim.refresh_heroes()
	# Stand each blade just inside its own reach of the boss.
	for i in range(blades.size()):
		var reach := float(Arena.sim.heroes[i].get("range", 60.0))
		var stand: Vector2 = spot + sides[i] * clampf(reach * 0.82, 44.0, 110.0)
		Arena.heroes[i]["position"] = stand
		Arena.sim.heroes[i]["pos"] = stand
		print("boss blade %s reach %.1f stands %.1f from the boss" % [blades[i], reach, stand.distance_to(spot)])
	Arena.sim.refresh_heroes()
	Arena.selected = -1
	Arena.sim._spawn(Arena.boss_for(1))
	var boss: Dictionary = Arena.sim.monsters[-1]
	boss["pos"] = spot
	boss["vel"] = Vector2.ZERO
	boss["hp"] = 1.0e9
	boss["max"] = 1.0e9
	Arena.sim._rebuild_navigation()
	for n in range(30):
		_pin([boss], [spot])
		await _tick()
	var sid := int(boss["spawn_id"])
	var node: Node3D = world.monster_nodes[sid]
	check(is_equal_approx(node.scale.y, StellarModels.BOSS_SCALE), "boss: the body stands at root scale %.1f" % StellarModels.BOSS_SCALE)
	var tall: float = world.vfx._monster_height(sid)
	check(tall > 2.0, "boss: effect code sees the scaled height (%.2f u)" % tall)
	var fitted := not has_arg("--no-body-fit")
	if not fitted:
		# The fight as it looked before bursts and status marks followed the body's scale.
		world.vfx._big_bodies.clear()
		for status in ["Burn", "Frost", "Stun"]:
			var mark := node.get_node("Stellar" + status) as MeshInstance3D
			var old := mark.material_override as ShaderMaterial
			mark.material_override = StellarVfx._status_material(status, float(old.get_shader_parameter("height")), 1.0)
	else:
		check(world.vfx._big_body_at(spot) == node, "boss: effect code finds the scaled body at its position")
		check(world.vfx._big_body_at(spot + Vector2(400, 0)) == null, "boss: open ground far from the boss is not inside a scaled body")
		print("boss girth %.2f u" % float(node.get_meta("_stellar_body_radius", 0.0)))
	var count := 48
	var contact_low := INF
	var contact_high := -INF
	var contacts := 0
	var lifted := 0
	var impacts := 0
	for n in range(count):
		_pin([boss], [spot])
		if n == 16:
			# Status marks and the stun burst on the doubled body.
			boss["stun_t"] = 1.2
			boss["slow"] = 0.3
			boss["slow_t"] = 2.0
			boss["burn"] = 1.0
			boss["burn_t"] = 2.0
			world.event({"t": "stun", "p": spot, "sid": sid})
		await _tick()
		for row in _fresh_bursts(world):
			if int(row["kind"]) == StellarVfx.Kind.SLASH_HIT:
				contacts += 1
				contact_low = minf(contact_low, float(row["y"]))
				contact_high = maxf(contact_high, float(row["y"]))
			if int(row["kind"]) in [StellarVfx.Kind.HIT, StellarVfx.Kind.SPLASH, StellarVfx.Kind.SLASH_HIT, StellarVfx.Kind.BEAM_CAP]:
				impacts += 1
				if float(row["body"]) > 1.5: lifted += 1
		await _shot("boss_melee_%02d" % n)
	check(contacts > 0, "boss: the blades made contact during the capture")
	var stun := node.get_node_or_null("StellarStun") as MeshInstance3D
	var stun_material := stun.material_override as ShaderMaterial if stun != null else null
	var mark_scale := float(stun_material.get_shader_parameter("body_scale")) if stun_material != null else 0.0
	var mark_height := float(stun_material.get_shader_parameter("height")) if stun_material != null else 0.0
	if fitted:
		check(contact_low >= tall * 0.4, "boss: blade contacts land on the body, %.2f..%.2f u of a %.2f u boss" % [contact_low, contact_high, tall])
		check(impacts > 0 and lifted == impacts, "boss: every impact on the boss carries its scale (%d of %d)" % [lifted, impacts])
		check(is_equal_approx(mark_scale, node.scale.y), "boss: status marks use the body's root scale (%.2f)" % mark_scale)
	print("boss height %.2f u, blade contacts %.2f..%.2f u (%d samples), impacts with the body's scale %d of %d, stun ring orbit %.2f u" % [tall, contact_low, contact_high, contacts, lifted, impacts, (mark_height + 0.12) * mark_scale])
	var rect := _to_window(_body_rect(spot, tall, 60.0))
	_report["sequences"].append({"prefix": "boss_melee", "frames": count, "ticks_per_frame": 1, "tick": 1.0 / 30.0,
		"rects": [_rect_row(rect)], "labels": ["boss"], "height": tall,
		"contact": [contact_low, contact_high], "stun_orbit": (mark_height + 0.12) * mark_scale})
	# Review zoom: the same fight with the camera pulled in on the boss just before each
	# frame renders. The 2D overlays (health bar, numbers) keep the game camera's positions.
	var focus := StellarWorld.world(spot, tall * 0.45)
	var pull_in := func() -> void:
		var camera: Camera3D = world.camera
		camera.size = 11.0
		camera.position = focus + Vector3(-3.0, 19.0, 23.0)
		camera.look_at(focus, Vector3.UP)
	RenderingServer.frame_pre_draw.connect(pull_in)
	for n in range(40):
		_pin([boss], [spot])
		if n == 12:
			boss["stun_t"] = 1.0
			boss["slow"] = 0.3
			boss["slow_t"] = 2.0
			boss["burn"] = 1.0
			boss["burn_t"] = 2.0
			world.event({"t": "stun", "p": spot, "sid": sid})
		await _tick()
		await _shot("boss_zoom_%02d" % n)
	RenderingServer.frame_pre_draw.disconnect(pull_in)
	_note("boss_zoom", 40, 1)
	await _close_arena()

## Bursts spawned by the tick that was just drawn: kind, origin height and the body scale
## their instance carries (the instance colour's alpha).
func _fresh_bursts(world: StellarWorld) -> Array:
	var rows: Array = []
	var bursts: MultiMeshInstance3D = world.vfx.get_node("Bursts")
	for fx in world.effects:
		if typeof(fx) != TYPE_DICTIONARY or String(fx.get("vfx", "")) != "burst": continue
		# A burst spawned by this tick's draw has aged exactly one tick: count each once.
		if float(fx["age"]) > 0.04: continue
		var custom: Color = fx["custom"]
		var slot := int(fx["slot"])
		rows.append({"kind": int(round(custom.a)), "y": bursts.multimesh.get_instance_transform(slot).origin.y,
			"body": bursts.multimesh.get_instance_color(slot).a})
	return rows

func _field(ids: Array) -> void:
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(ids.size()):
		Arena.gain_hero(Roster.unit_by_id(String(ids[i])), 4 + (i % 3) * 2)
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + i * TAU / 6.0) * 165.0
	Arena.sim.refresh_heroes()
	Arena.selected = -1
	Arena.sim.monsters.clear()
	var pool := Roster.theme_pool(Arena.theme_for(1))
	for n in range(26):
		Arena.sim._spawn(pool[n % pool.size()])
		var mo: Dictionary = Arena.sim.monsters[-1]
		var lane := n % ArenaGeometry.ROUTE_COUNT
		var path := ArenaGeometry.route_points(lane)
		mo["pos"] = path[clampi(10 + (n / ArenaGeometry.ROUTE_COUNT) * 6, 0, path.size() - 1)]
		mo["route"] = lane
		mo["hp"] = float(mo["hp"]) * 0.42
		mo["max"] = mo["hp"]
		mo["vel"] = ArenaGeometry.road_direction(mo["pos"])
	Arena.sim._rebuild_navigation()
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.8
	screen.view_3d._follow_offset = Vector3.ZERO
	screen.view_3d._camera_initialized = true
	screen.view_3d._apply_camera(Vector3.ZERO)

## One simulated tick rendered exactly once, like real play: the draw drains the
## simulator's events into the world and advances the effect clock by dt. Later
## redraws of the same tick (captures) are paused redraws (dt 0).
func _tick() -> void:
	screen._process(1.0 / 30.0)
	screen.queue_redraw()
	await frames(1)
	screen._draw_dt = 0.0

func _capture(name: String) -> void:
	screen.queue_redraw()
	await frames(2)
	await snap(out_dir + "/" + name + ".png")
	# The arena blends the 3D viewport over the 2D backdrop: any pixel whose alpha is not 1
	# is a hole onto that backdrop (the 2026-10-12 dissolve bug), whatever drew it.
	if screen.view_3d.viewport.get_texture().get_image().detect_alpha() != Image.ALPHA_NONE: _alpha_leaks.append(name)

func _note(prefix: String, count: int, ticks: int) -> void:
	_report["sequences"].append({"prefix": prefix, "frames": count, "ticks_per_frame": ticks, "tick": 1.0 / 30.0})

## The lane entrance that projects deepest inside the battlefield box (edge gates are cut
## off by the fixed framing, which would hide the sequence from the capture).
func _visible_gate() -> Vector2:
	var best := ArenaGeometry.route_points(0)[0]
	var best_margin := -INF
	var box: Rect2 = screen.view_3d._active_box()
	for lane in range(ArenaGeometry.ROUTE_COUNT):
		var gate: Vector2 = ArenaGeometry.route_points(lane)[0]
		var px: Vector2 = screen.view_3d.project(gate, 0.0)
		var margin := minf(minf(px.x - box.position.x, box.end.x - px.x), minf(px.y - box.position.y, box.end.y - px.y))
		if margin > best_margin:
			best_margin = margin
			best = gate
	return best

func _live_skills(world: StellarWorld) -> int:
	var n := 0
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == "skill": n += 1
	return n

func _count_effects(world: StellarWorld) -> Dictionary:
	var counts := {"bullets": Arena.sim.bullets.size(), "zones": Arena.sim.zones.size(), "effects": world.effects.size(), "monsters": Arena.sim.monsters.size()}
	return counts

func _body_height(body: Node3D) -> float:
	var id := String(body.get_meta("_stellar_monster_id", ""))
	return float(NativeMonsterModel.manifest().get("monsters", {}).get(id, {}).get("height", 0.9))

func _material_ids(node: Node) -> Array:
	var ids: Array = []
	if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		for i in node.multimesh.mesh.get_surface_count():
			ids.append(node.multimesh.mesh.surface_get_material(i).get_instance_id())
	elif node is MeshInstance3D and node.material_override != null:
		ids.append(node.material_override.get_instance_id())
	for child in node.get_children(): ids.append_array(_material_ids(child))
	return ids

## update(0) must not move the clock that every effect shader reads.
func _pause_freezes(world: StellarWorld) -> bool:
	var vfx: StellarVfx = world.vfx
	var before: float = vfx._clock
	vfx.update(0.0)
	return is_equal_approx(vfx._clock, before)
