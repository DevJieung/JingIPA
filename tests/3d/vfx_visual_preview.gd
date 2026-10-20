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
##                       --probe-id a,b (default jelly_seer,ember_imp) probes each body in
##                       turn (probe_<id>_*.png when more than one).
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
##
## Run-level moments (2026-10-13, --moments; tests/3d/moments_review.py drives it):
##   first    a fresh run through the game's own flow: the first battlefield's card
##            (first_card: the reveal waits at age 0), the free first jewel box over it
##            (first_box) and the reveal running as the stage's first preparation starts
##            (first_NNN)
##   revive   the crystal breaks through the real _damage_crystal path with the Guardian's
##            blessing in hand: revive_<NNN> at one 60 Hz tick per frame for the first 1.5 s
##            (collapse, flash, shockwave, shards), then revive_tail at two ticks per frame
##            until the aegis has run out; revive_defeat is the same blessing taken on the
##            defeat screen (Arena.revive_from_defeat: the crystal is already gone), and
##            resume a run restored inside the untouchable window (no event, only invuln_t)
##   clear    the stage boss dies among its escort (real _hurt / _reap): the release, the
##            mend and the scattering escort over the 1.8 s before the world is rebuilt
##   stage    continues the same run: the paused first frame of the new battlefield under
##            its card (stage_card), the same frame without the 2D overlay (stage_field),
##            then the reveal after the card is confirmed. Leftovers are planted just
##            before the change (a boss arrival, a ward dome, a blast with its queued
##            light, hits): none of them may be in the paused picture
##   scatter  a stage boss falls among a crowd spread along every road: each escort is
##            followed through its halt, its run from the crystal and its end (scatter_NNN
##            at every 60 Hz tick; the report lists a rectangle per followed body for the
##            review strips). --scatter-as-kill strips the flag from the events, so the
##            same crowd dies the ordinary way (scatterkill_NNN): the comparison
##   final    STAGE 10 (a chapter boss): the four-second warning at the gate (the boss wave's
##            preparation, ArenaSim.jump_to_boss), the boss arriving, then its fall
##            (final_clear: the last clear, the gates sealed) and the still that the result
##            panel freezes (final_result, final_rest_field). final_settle is the same
##            victory after a hitch that leaves the effect clock behind
## Since 2026-10-19 every ladder stage is a run of its own and its boss ends it: "stage" opens the
## next stage from the victory panel (Arena.next_stage, what 「다음 STAGE」 starts), and staged scenes
## sit in the middle of a wave (_mid_wave: skills are refused in a preparation, nothing spawns
## on its own). `--watchdog SEC` (default 2400) fails a run that stalls.
## --moment revive|clear|stage|final|all, --next-theme N (the battlefield that opens after
## the clear), --speed 1|2|3 (battle speed the moment is played at).
## --film WxH draws the game into an off-screen viewport of that size (design canvas
## 1280x800) and keeps the window tiny: the way to capture on a GPU display without
## putting a full-size window on the desktop session. Without it the window is captured.
##
## Hit feel (2026-10-17, --hitfeel; tools/3d/vfx_review.py --hitfeel drives it): staged
## scenes at one 30 Hz tick per frame on the bare field of --theme, see _hitfeel below.
## --scene zone|blast|freeze|hit|kill|melee|fly|levelup|perf|all picks one.

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
## Off-screen picture (--film WxH): the game is a child of this viewport instead of the window.
var film: SubViewport

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
	_watchdog()
	if arg("--film", "") != "": _open_film(arg("--film", ""))
	var special := false
	if has_arg("--moments"):
		special = true
		await _moments(theme)
	if has_arg("--dissolve-probe"):
		special = true
		await _dissolve_probe(theme)
	if has_arg("--death-only"):
		special = true
		await _deaths(theme)
	if has_arg("--boss-melee"):
		special = true
		await _boss_melee(theme)
	if has_arg("--hitfeel"):
		special = true
		await _hitfeel(theme)
	if not special:
		for squad in squads:
			await _squad(String(squad), theme)
	var file := FileAccess.open(out_dir + "/vfx-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "  ") + "\n")
	file = null
	finish("VFX visual preview (%d frames per sequence)" % _frames)

func _squad(squad: String, theme: int) -> void:
	Arena.start_run(20261010 + squad.hash() % 1000, 1)
	main = load("res://game/main.gd").new()
	_host().add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	Arena.choose_theme(theme)
	Arena.confirm_summon()
	Arena.close_modal()
	# The 3D view attaches its world on the first paint.
	await paint(screen)
	_quiet()
	_field(SQUADS[squad])
	_no_levelups()
	_mid_wave(1)
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
			_ensure_targets(6)
			check(Arena.sim.cast_skill(skill), squad + ": skill casts " + skill)
			for n in range(22):
				for k in range(2): await _tick()
				await _capture("%s_skill_%s_%02d" % [squad, skill, n])
			_note("%s_skill_%s" % [squad, skill], 22, 2)
			for k in range(12): await _tick()
		# The blast once more at every tick: the fall, the impact and the ring reaching R.
		Arena.sim.skill_cooldowns["blast"] = 0.0
		_ensure_targets(6)
		check(Arena.sim.cast_skill("blast"), squad + ": blast casts again for the slow capture (%d monsters, %d casts left)" % [Arena.sim.monsters.size(), Arena.sim.skill_uses_left("blast")])
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
	Arena.start_run(seed_value, 1)
	main = load("res://game/main.gd").new()
	_host().add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	Arena.choose_theme(theme)
	Arena.confirm_summon()
	Arena.close_modal()
	await paint(screen)
	_quiet()
	Arena.heroes.clear()
	Arena.bench.clear()
	Arena.sim.refresh_heroes()
	Arena.selected = -1
	Arena.sim.monsters.clear()
	Arena.sim._rebuild_navigation()
	_no_levelups()
	_mid_wave(1)
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
	var window := Rect2(Vector2.ZERO, Vector2(1280, 800) if film != null else Vector2(get_viewport().get_visible_rect().size))
	return Rect2i(rect.grow(pad).intersection(window))

## A canvas rectangle in the pixels of a window screenshot. The scale is measured from an
## actual screenshot against the project's design size (canvas_items stretch).
func _to_window(rect: Rect2i) -> Rect2i:
	if _window_scale == Vector2.ZERO:
		var design := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
			float(ProjectSettings.get_setting("display/window/size/viewport_height")))
		_window_scale = Vector2(_frame_image().get_size()) / design
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
	var img := _frame_image()
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
	# Every body named (comma list). The default keeps both regressions in view: jelly_seer (the
	# 2026-10-12 depth-only hole) and ember_imp (its glowing crown that outlived the dissolve, X1,
	# fixed by D3 on 2026-10-19). With one id the files keep their plain probe_* names.
	var ids := arg("--probe-id", "jelly_seer,ember_imp").split(",", false)
	_report["probes"] = []
	for id in ids:
		await _dissolve_probe_one(theme, String(id), "probe" if ids.size() == 1 else "probe_" + String(id))

func _dissolve_probe_one(theme: int, id: String, prefix: String) -> void:
	var world := await _open_arena(theme, 20261012)
	var env := _environment(world)
	var natural := env.background_color
	var spot: Vector2 = Balance.ARENA_CENTER + Vector2(-150, 150)
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
	check(not materials.is_empty(), "probe %s: the body owns per-instance materials" % id)
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
	var ref := await _shot(prefix + "_reference")
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
		var img := await _shot(prefix + "_" + String(state[0]))
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
		var img := await _shot(prefix + "_game_q%03d" % int(round(q * 100.0)))
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
		check(absf(visible - wanted) < 0.02, "probe %s: dissolve %.2f leaves %.3f of the body (curve asks %.3f)" % [id, q, visible, wanted])
		check(is_equal_approx(mat.albedo_color.a, 1.0) and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "probe %s: the dissolve never touches alpha (q %.2f)" % [id, q])
		check(float(row["viewport_alpha_min"]) > 0.999, "probe %s: the 3D viewport keeps alpha 1 under the body at dissolve %.2f" % [id, q])
		if q >= StellarShading.DISSOLVE_END:
			check(int(row["changed"]) == 0, "probe %s: a finished dissolve (q %.2f) leaves no pixel of the body (%d changed)" % [id, q, int(row["changed"])])
	check(solid > 200, "probe %s: the whole body is drawn before the fade (%d px)" % [id, solid])
	# The same end state in the theme's own colours: what the player sees.
	env.background_color = natural
	node.visible = false
	var natural_ref := await _shot(prefix + "_natural_reference")
	node.visible = true
	var seen := await _shot(prefix + "_natural_q100")
	var natural_row := _region_stats(seen, natural_ref, rect)
	natural_row["state"] = "natural_q1.00"
	rows.append(natural_row)
	print("probe ", JSON.stringify(natural_row))
	StellarShading.set_dissolve(node, 0.0)
	var probe := {"id": id, "prefix": prefix, "rect": _rect_row(rect), "box_rect": _rect_row(box_rect), "rows": rows}
	_report["probes"].append(probe)
	if not _report.has("probe"): _report["probe"] = probe
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
	_no_levelups()
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
		var lane := n % ArenaGeometry.route_count()
		var path := ArenaGeometry.route_points(lane)
		mo["pos"] = path[clampi(10 + (n / ArenaGeometry.route_count()) * 6, 0, path.size() - 1)]
		mo["route"] = lane
		mo["hp"] = float(mo["hp"]) * 0.42
		mo["max"] = mo["hp"]
		mo["vel"] = ArenaGeometry.road_direction(mo["pos"])
	Arena.sim._rebuild_navigation()
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.8
	screen.view_3d._follow_offset = Vector3.ZERO
	screen.view_3d._camera_initialized = true
	screen.view_3d._apply_camera(Vector3.ZERO)

## A skill needs something to hit: when the squad has cleared the roads (stage 1 monsters
## are few and frail), stand a few sturdy ones on the lanes again.
func _ensure_targets(count: int) -> void:
	if Arena.sim.monsters.size() >= count: return
	var pool := Roster.theme_pool(Arena.theme_for(1))
	var lanes := ArenaGeometry.route_count()
	for n in range(count):
		Arena.sim._spawn(pool[n % pool.size()])
		if not Arena.sim.events.is_empty() and String(Arena.sim.events[-1].get("t", "")) == "spawn": Arena.sim.events.pop_back()
		var mo: Dictionary = Arena.sim.monsters[-1]
		var path := ArenaGeometry.route_points(n % lanes)
		mo["pos"] = path[clampi(int(path.size() * (0.55 + 0.06 * float(n / lanes))), 0, path.size() - 2)]
		mo["route"] = n % lanes
		mo["hp"] = float(mo["hp"]) * 6.0
		mo["max"] = mo["hp"]
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()

## One simulated tick rendered exactly once, like real play: the draw drains the
## simulator's events into the world and advances the effect clock by dt. Later
## redraws of the same tick (captures) are paused redraws (dt 0).
func _tick(dt: float = 1.0 / 30.0) -> void:
	screen._process(dt)
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
	for lane in range(ArenaGeometry.route_count()):
		var gate: Vector2 = ArenaGeometry.route_points(lane)[0]
		var px: Vector2 = screen.view_3d.project(gate, 0.0)
		var margin := minf(minf(px.x - box.position.x, box.end.x - px.x), minf(px.y - box.position.y, box.end.y - px.y))
		if margin > best_margin:
			best_margin = margin
			best = gate
	return best

func _live_moments(world: StellarWorld) -> int:
	var n := 0
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == "moment": n += 1
	return n

## A live Moments sequence of `kind` (the kind rides in the instance's custom data).
func _has_moment(world: StellarWorld, kind: int) -> bool:
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == "moment" and int(round((fx["custom"] as Color).a)) == kind: return true
	return false

## Uniform scale of the live Moments sequence of `kind` (its basis carries 1 + a distance).
func _moment_scale(world: StellarWorld, kind: int) -> float:
	var moments: MultiMeshInstance3D = world.vfx.get_node("Moments")
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == "moment" and int(round((fx["custom"] as Color).a)) == kind:
			return moments.multimesh.get_instance_transform(int(fx["slot"])).basis.get_scale().x
	return -1.0

func _count_bursts(world: StellarWorld, kind: int) -> int:
	var n := 0
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == "burst" and int(round((fx["custom"] as Color).a)) == kind: n += 1
	return n

func _count_moments(world: StellarWorld, kind: int) -> int:
	var n := 0
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == "moment" and int(round((fx["custom"] as Color).a)) == kind: n += 1
	return n

## Live one-shot records of one pool ("burst", "beam", "slash", "skill", "moment").
func _count_pool(world: StellarWorld, pool: String) -> int:
	var n := 0
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == pool: n += 1
	return n

func _visible_domes(world: StellarWorld) -> int:
	var n := 0
	for name in ["Dome0", "Dome1"]:
		if (world.vfx.get_node(name) as MeshInstance3D).visible: n += 1
	return n

func _lit_pulses(world: StellarWorld) -> int:
	var n := 0
	for i in range(StellarVfx.MAX_LIGHTS):
		if (world.vfx.get_node("Pulse" + str(i)) as OmniLight3D).visible: n += 1
	return n

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

# --------------------------------------------------------------------------- #
# Off-screen picture (--film) and the run-level moments (--moments)
# --------------------------------------------------------------------------- #
## The node the game is added to: the film when there is one, this harness otherwise.
func _host() -> Node:
	return film if film != null else self

## The picture a screenshot would show (the film's, or the window's).
func _frame_image() -> Image:
	return (film if film != null else get_viewport()).get_texture().get_image()

## Screenshots come from the film when there is one (Harness.snap reads the window).
func snap(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := _frame_image()
	img.save_png(path)
	return img

## Draw the game off-screen at `spec` (WxH) pixels on the 1280x800 design canvas, the
## same stretch a window of that size gets, and shrink the window to a GL context holder.
func _open_film(spec: String) -> void:
	var parts := spec.split("x")
	var design := Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	film = SubViewport.new()
	film.name = "Film"
	film.size = Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else design
	film.size_2d_override = design
	film.size_2d_override_stretch = true
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.transparent_bg = false
	# The root viewport takes these from project settings; a SubViewport does not.
	film.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	film.set("oversampling_override", float(film.size.x) / float(design.x))
	film.gui_disable_input = true
	add_child(film)
	get_window().size = Vector2i(96, 60)

const MOMENT_SQUAD := ["echo", "kari", "brasa", "jokull", "triton", "limne"]

## The real arena screen in battle on `theme` with six guardians around the crystal and
## `count` monsters spread along every road of the battlefield's layout.
func _open_battle(theme: int, seed_value: int, count: int = 22) -> StellarWorld:
	Arena.start_run(seed_value, 1)
	main = load("res://game/main.gd").new()
	_host().add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	Arena.choose_theme(theme)
	Arena.confirm_summon()
	Arena.close_modal()
	await paint(screen)
	_quiet()
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(MOMENT_SQUAD.size()):
		Arena.gain_hero(Roster.unit_by_id(String(MOMENT_SQUAD[i])), 4 + (i % 3) * 2)
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + i * TAU / 6.0) * 178.0
	Arena.sim.refresh_heroes()
	for i in range(Arena.sim.heroes.size()): Arena.sim.heroes[i]["pos"] = Arena.heroes[i]["position"]
	Arena.selected = -1
	Arena.sim.monsters.clear()
	_no_levelups()
	_mid_wave(1)
	_crowd(count)
	screen.speed = clampf(arg_float("--speed", 1.0), 1.0, 3.0)
	screen.view_3d._follow_offset = Vector3.ZERO
	screen.view_3d._camera_initialized = true
	screen.view_3d._apply_camera(Vector3.ZERO)
	return screen.view_3d.world

## A run's first battlefield is announced like every other (arena_stage), and that reveal
## plays through the first seconds of battle. The scenes staged here stand for the
## middle of a battle, long after it: release it. (--moment first films it.)
func _quiet() -> void:
	(screen.view_3d.world as StellarWorld).vfx._clear_field()

## Monsters of the current battlefield spread from the gates to the plaza along every lane.
func _crowd(count: int) -> void:
	var pool := Roster.theme_pool(Arena.theme_for(1))
	var lanes := ArenaGeometry.route_count()
	for n in range(count):
		Arena.sim._spawn(pool[n % pool.size()])
		if not Arena.sim.events.is_empty() and String(Arena.sim.events[-1].get("t", "")) == "spawn": Arena.sim.events.pop_back()
		var mo: Dictionary = Arena.sim.monsters[-1]
		var lane := n % lanes
		var path := ArenaGeometry.route_points(lane)
		var along := 0.04 + 0.93 * (float(n / lanes) + 0.5 * float(lane) / float(lanes)) / maxf(1.0, ceilf(float(count) / float(lanes)))
		mo["pos"] = path[clampi(int(along * float(path.size() - 1)), 0, path.size() - 2)]
		mo["route"] = lane
		mo["hp"] = float(mo["hp"]) * 30.0
		mo["max"] = mo["hp"]
		mo["vel"] = ArenaGeometry.road_direction(mo["pos"])
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()

## `count` frames of `ticks` steps of `dt` each, saved as <prefix>_NNN.png.
func _roll(prefix: String, count: int, ticks: int, dt: float, first: int = 0) -> void:
	for n in range(count):
		for k in range(ticks): await _tick(dt)
		screen.queue_redraw()
		await frames(2)
		await snap("%s/%s_%03d.png" % [out_dir, prefix, first + n])
		if screen.view_3d.viewport.get_texture().get_image().detect_alpha() != Image.ALPHA_NONE: _alpha_leaks.append("%s_%03d" % [prefix, first + n])

func _note_moment(prefix: String, count: int, ticks: int, dt: float, extra: Dictionary = {}) -> void:
	var row := {"prefix": prefix, "frames": count, "ticks_per_frame": ticks, "tick": dt, "digits": 3,
		"speed": screen.speed if screen != null else 1.0}
	row.merge(extra)
	_report["sequences"].append(row)

## Where the canvas shows a logical ground point (design pixels), for the review crops.
func _px(at: Vector2, height: float = 0.0) -> Array:
	var p: Vector2 = screen.view_3d.project(at, height)
	return [roundi(p.x), roundi(p.y)]

func _moments(theme: int) -> void:
	var only := arg("--moment", "all")
	if only in ["all", "first"]: await _moment_first(theme)
	if only in ["all", "revive"]:
		await _moment_revive(theme)
		await _moment_resume(theme)
	if only in ["all", "clear", "stage"]: await _moment_clear_and_stage(theme, only != "stage")
	if only in ["all", "scatter"]: await _moment_scatter(theme)
	if only in ["all", "final"]: await _moment_final(theme)
	check(_alpha_leaks.is_empty(), "moments: the 3D viewport keeps alpha 1 in every captured frame (%d leak, first %s)" % [_alpha_leaks.size(), ", ".join(_alpha_leaks.slice(0, 5))])
	_alpha_leaks.clear()

## A fresh run through the game's own flow. The first battlefield is announced like every
## later one: its reveal waits at age 0 under the card and under the first rite, and runs
## when the first battle starts.
func _moment_first(theme: int) -> void:
	Arena.start_run(20261019, 1)
	# The game draws the battlefield itself; put the field under test first and open it
	# again as the run does (the card stays up: no tool shortcut past it).
	Arena.stage_themes[0] = theme
	Arena.sim = null
	Arena._open_stage(1)
	main = load("res://game/main.gd").new()
	_host().add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	screen.speed = clampf(arg_float("--speed", 1.0), 1.0, 3.0)
	await paint(screen)
	await paint(screen)
	var world: StellarWorld = screen.view_3d.world
	var vfx: StellarVfx = world.vfx
	var gates := ArenaGeometry.route_count()
	check(Arena.modal == "stage" and Arena.stage == 1 and Arena.theme_index == theme, "first: the run opens on its first battlefield's card")
	check(_count_moments(world, StellarVfx.MomentKind.STAGE_SWEEP) == 1 and _count_moments(world, StellarVfx.MomentKind.GATE_BEACON) == gates and _live_moments(world) == 1 + gates,
		"first: the first battlefield is revealed like every other (%d sequences, %d gates)" % [_live_moments(world), gates])
	var oldest := 0.0
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and fx.has("vfx"): oldest = maxf(oldest, float(fx["age"]))
	check(is_zero_approx(oldest), "first: the picture behind the first card is the reveal at age 0 (%.3f s)" % oldest)
	await snap(out_dir + "/first_card.png")
	vfx.get_viewport().get_texture().get_image().save_png(out_dir + "/first_field.png")
	var clock: float = vfx._clock
	# The card is confirmed: the stage's free first jewel box opens over the same paused field.
	check(Arena.confirm_stage() and Arena.modal == "box", "first: the free first box follows the card")
	screen._track_modal()
	for n in range(4): await paint(screen)
	await snap(out_dir + "/first_box.png")
	check(not Arena.confirm_summon().is_empty(), "first: the box gives the first guardian")
	for n in range(3): await paint(screen)
	check(is_equal_approx(vfx._clock, clock) and _live_moments(world) == 1 + gates, "first: the reveal waits through the card and the box (%d sequences)" % _live_moments(world))
	check(Arena.close_modal() and Arena.modal.is_empty(), "first: the stage starts (its first preparation)")
	screen._track_modal()
	var gate_px: Array = []
	for lane in range(gates): gate_px.append(_px(ArenaGeometry.gate_point(lane, 20.0), 0.6))
	var reveal := int(round(3.6 * 30.0 / screen.speed))
	await _roll("first", reveal, 2, 1.0 / 60.0)
	_note_moment("first", reveal, 2, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9), "gates": gate_px,
		"stills": ["first_card", "first_field", "first_box"], "layout": ArenaGeometry.layout(), "theme": theme})
	# The first preparation is short (ARENA_PREP_FIRST): hold it past the film so wave 1's own gate
	# beacons and runners (arena_wave) cannot be taken for the reveal's leftovers below.
	Arena.sim.prep_t += 30.0
	for n in range(60): await _tick()
	check(_live_moments(world) == 0 and not (vfx.get_node("Roads") as MeshInstance3D).visible, "first: the reveal is released when it has played (%s, roads %s, %.1f s into the first preparation of %.1f)"
		% [_moment_kinds(world), (vfx.get_node("Roads") as MeshInstance3D).visible, Arena.sim.prep_total() - Arena.sim.prep_left(), Arena.sim.prep_total()])
	await _close_arena()

## The live Moments sequences by kind name and age, for a check's message.
func _moment_kinds(world: StellarWorld) -> String:
	var rows: PackedStringArray = []
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == "moment":
			var kind := int(round((fx["custom"] as Color).a))
			rows.append("%s %.2fs" % [StellarVfx.MomentKind.keys()[kind] if kind >= 0 and kind < StellarVfx.MomentKind.size() else str(kind), float(fx["age"])])
	return "live: " + (", ".join(rows) if not rows.is_empty() else "none")

## The crystal's revival through the simulator's own path: a siege blow takes the last
## health while the Guardian's blessing is still in hand. Then the same blessing bought on
## the defeat screen (the crystal is already gone when it is taken back).
func _moment_revive(theme: int) -> void:
	var world := await _open_battle(theme, 20261013, 24)
	var vfx: StellarVfx = world.vfx
	# A few besiegers already at the altar: the wave has to be read against bodies next to it.
	var pool := Roster.theme_pool(Arena.theme_for(1))
	for n in range(4):
		Arena.sim._spawn(pool[(n * 3) % pool.size()])
		if String(Arena.sim.events[-1].get("t", "")) == "spawn": Arena.sim.events.pop_back()
		var mo: Dictionary = Arena.sim.monsters[-1]
		mo["pos"] = Balance.ARENA_CENTER + Vector2.from_angle(0.6 + n * 1.45) * (Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS - 1.0)
		mo["hp"] = float(mo["hp"]) * 30.0
		mo["max"] = mo["hp"]
	for n in range(40): await _tick()
	var pools_before := vfx.get_child_count()
	var materials_before := _material_ids(vfx)
	var moments: MultiMeshInstance3D = vfx.get_node("Moments")
	var aegis: MeshInstance3D = vfx.get_node("Aegis")
	check(not moments.visible and not aegis.visible, "revive: the Moments pool and the aegis are hidden while idle")
	var crystal: Node3D = world.crystals[0]
	var whole := crystal.scale
	Arena.sim.crystal_hp = 40.0
	check(Arena.revive_ready(), "revive: the blessing is in hand before the blow")
	await _roll("revive", 4, 1, 1.0 / 60.0)
	Arena.sim._damage_crystal(400.0, Balance.ARENA_CENTER)
	check(Arena.sim.revives == 1 and Arena.sim.crystal_hp > 0.0, "revive: the simulator revived the crystal")
	var sec: float = Balance.ARENA_REVIVE_INVULN
	var step := 1.0 / 60.0 * screen.speed
	# 1.5 s at every 60 Hz tick, then two ticks a frame until the aegis is gone.
	var fine := int(round(1.5 / step))
	var gone := false
	var whole_again := -1.0
	var mismatch := 0
	for n in range(fine):
		await _roll("revive", 1, 1, 1.0 / 60.0, 4 + n)
		var age := float(n + 1) * step
		if crystal.scale.y < 0.01 * whole.y: gone = true
		if whole_again < 0.0 and gone and crystal.scale.is_equal_approx(whole): whole_again = age
		if n == 0: check(moments.visible and _live_moments(world) == 1, "revive: the sequence occupies one Moments instance")
		# The aegis is up exactly while the simulator keeps the crystal untouchable.
		if age > StellarVfx.REVIVE_FLASH + 0.05 and aegis.visible != (Arena.sim.invuln_t > 0.0): mismatch += 1
	check(gone, "revive: the crystal shatters before it reforms")
	check(whole_again > 0.0 and whole_again <= StellarVfx.REVIVE_WHOLE + 0.2, "revive: the crystal is whole again %.2f s after the blow" % whole_again)
	var rest := int(ceil((sec + 0.9 - 1.5) / (2.0 * step)))
	for n in range(rest):
		await _roll("revive_tail", 1, 2, 1.0 / 60.0, n)
		if aegis.visible != (Arena.sim.invuln_t > 0.0): mismatch += 1
	# The effect clock runs up to one tick ahead of the simulator's fixed steps.
	check(mismatch <= 2, "revive: the aegis is visible exactly while the crystal cannot be hurt (%d frames differ)" % mismatch)
	_note_moment("revive", 4 + fine, 1, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9), "event_frame": 4})
	_note_moment("revive_tail", rest, 2, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9), "starts_at": 1.5 / screen.speed})
	check(Arena.sim.invuln_t <= 0.0, "revive: the capture runs past the untouchable window")
	check(not moments.visible and not aegis.visible and _live_moments(world) == 0, "revive: nothing of the moment is left once the aegis has run out")
	check(crystal.scale.is_equal_approx(whole), "revive: the crystal keeps its own scale afterwards")
	check(vfx.get_child_count() == pools_before, "revive: no VFX node is created by the moment")
	check(_material_ids(vfx) == materials_before, "revive: no VFX material is created by the moment")
	check(world.effects.size() <= 72, "revive: one-shot effects respect the shared 72 budget")
	check(_pause_freezes(world), "revive: a paused battle (dt 0) does not advance the effect clock")
	# The same blessing bought on the defeat screen: the run has ended, the crystal is gone.
	# (All of the run's revivals spent stands in for a player who does not own it yet.)
	Arena.sim.revives = Balance.ARENA_REVIVE_USES
	Arena.sim.crystal_hp = 1.0
	Arena.sim._damage_crystal(50.0, Balance.ARENA_CENTER)
	check(not Arena.running and Arena.modal == "result", "revive: without the blessing the same blow ends the run")
	screen._track_modal()
	for n in range(3): await paint(screen)
	check(not crystal.visible, "revive: the broken crystal is hidden on the defeat screen")
	Arena.sim.revives = 0
	check(Arena.revive_from_defeat(), "revive: the blessing takes the defeat back")
	screen._track_modal()
	var late := int(round(1.3 / step))
	var seen_whole := false
	for n in range(late):
		await _roll("revive_defeat", 1, 1, 1.0 / 60.0, n)
		if n < int(0.4 / step) and crystal.visible and crystal.scale.y > 0.5 * whole.y: seen_whole = true
	check(not seen_whole, "revive: taken back from a defeat, the crystal does not pop in whole before it reforms")
	check(crystal.scale.is_equal_approx(whole), "revive: the crystal is whole after the defeat was taken back")
	_note_moment("revive_defeat", late, 1, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9)})
	await _close_arena()

## A run restored inside the revival's untouchable window: there is no arena_revive event,
## only the simulator's remaining invuln_t. The rest of the aegis must be shown, without
## the burst, and end with the window.
func _moment_resume(theme: int) -> void:
	var world := await _open_battle(theme, 20261016, 12)
	var vfx: StellarVfx = world.vfx
	for n in range(20): await _tick()
	var aegis: MeshInstance3D = vfx.get_node("Aegis")
	var crystal: Node3D = world.crystals[0]
	var whole := crystal.scale
	check(not aegis.visible, "resume: no aegis before the window")
	Arena.sim.revives = 1
	Arena.sim.invuln_t = 3.0
	var bursts_before := _count_bursts(world, StellarVfx.Kind.SEAL)
	await _roll("resume", 1, 1, 1.0 / 60.0)
	check(aegis.visible and _has_moment(world, StellarVfx.MomentKind.REVIVE) and _live_moments(world) == 1,
		"resume: the rest of the aegis is shown for a restored run (aegis %s, %d sequences)" % [aegis.visible, _live_moments(world)])
	check(crystal.scale.is_equal_approx(whole), "resume: the crystal is not shattered again")
	check(_count_bursts(world, StellarVfx.Kind.SEAL) == bursts_before and vfx._delayed.is_empty(), "resume: no burst, no seals")
	var step := 1.0 / 60.0 * screen.speed
	var count := int(ceil(3.4 / (4.0 * step)))
	var mismatch := 0
	for n in range(count):
		await _roll("resume", 1, 4, 1.0 / 60.0, 1 + n)
		if aegis.visible != (Arena.sim.invuln_t > 0.0): mismatch += 1
	check(mismatch <= 1, "resume: the aegis ends with the simulator's window (%d frames differ)" % mismatch)
	check(not aegis.visible and Arena.sim.invuln_t <= 0.0, "resume: the capture runs past the window")
	_note_moment("resume", 1 + count, 4, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9)})
	# Since 2026-10-19 every stage is a run of its own: the stage is won (its boss falls inside the
	# window), the victory panel stands, and the next stage (Arena.next_stage) starts with a whole
	# crystal and no window. Under its card there is the new field's reveal and no aegis.
	Arena.sim.invuln_t = 3.0
	for n in range(12): await _tick(1.0 / 60.0)
	check(aegis.visible and Arena.sim.invuln_t > 2.0, "resume: the aegis is up again before the stage is won")
	_fell_boss_now()
	var guard := 0
	while Arena.modal != "result" and guard < 240:
		await _tick(1.0 / 60.0)
		guard += 1
	check(Arena.modal == "result" and Arena.sim.won, "resume: the stage is won inside the window")
	check(Arena.next_stage() and Arena.modal == "stage", "resume: the next stage opens under its card")
	screen._track_modal()
	await _tick(1.0 / 60.0)
	await paint(screen)
	check(Arena.sim.invuln_t <= 0.0 and not aegis.visible, "resume: a new stage starts without the previous stage's aegis")
	check(_live_moments(world) == 1 + ArenaGeometry.route_count() and _count_bursts(world, StellarVfx.Kind.SEAL) == 0 and vfx._delayed.is_empty(),
		"resume: under the new card there is the reveal alone, no burst (%d sequences, %d gates)" % [_live_moments(world), ArenaGeometry.route_count()])
	await snap(out_dir + "/resume_stage_card.png")
	await _close_arena()

## The stage boss of the run in play steps in (the boss wave's preparation runs out) and is
## killed through the simulator's own damage path: the clear beat begins.
func _fell_boss_now() -> void:
	var sim := Arena.sim
	_no_levelups()
	if not sim.boss_spawned:
		sim.jump_to_boss()
		for i in range(10):
			if sim.boss_spawned: break
			sim.step(1.0 / 60.0)
	for i in range(sim.monsters.size()):
		if String(sim.monsters[i]["kind"]) == "boss":
			sim._cache_positions()
			sim._hurt(i, 1.0e12, false, -1, "none", false)
	sim._reap()
	check(sim.clear_t > 0.0, "the stage boss fell: the clear beat runs")

## A stage boss dies among its escort; the clear beat runs (1.8 s) and the stage is won. From the
## victory panel the next stage opens (Arena.next_stage, on --next-theme) under its card; then the
## card is confirmed, the free first box taken, and the reveal plays in the first preparation.
func _moment_clear_and_stage(theme: int, keep_clear: bool) -> void:
	var world := await _open_battle(theme, 20261014, 26)
	var next_theme := int(arg("--next-theme", str((theme + 29) % Roster.THEMES.size())))
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.55
	# The boss wave (its list held: the HUD reads the last wave), the boss half way down a road.
	_mid_wave(Balance.ARENA_WAVES)
	Arena.sim._spawn(Arena.boss_for(Arena.stage))
	if String(Arena.sim.events[-1].get("t", "")) == "spawn": Arena.sim.events.pop_back()
	var boss: Dictionary = Arena.sim.monsters[-1]
	var path := ArenaGeometry.route_points(0)
	boss["pos"] = path[int(path.size() * 0.72)]
	boss["route"] = 0
	# It must fall when the capture says so, not to the squad during the run-up
	# (at 3x the run-up is four seconds of fighting).
	boss["hp"] = 1.0e8
	boss["max"] = 1.0e8
	Arena.sim.boss_spawned = true
	Arena.sim.boss_warned = true
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()
	for n in range(40): await _tick()
	var boss_at: Vector2 = boss["pos"]
	if keep_clear: await _roll("clear", 4, 1, 1.0 / 60.0)
	Arena.sim._cache_positions()
	check(Arena.sim.monsters.has(boss) and Arena.sim.clear_t <= 0.0, "clear: the boss is still standing when the capture kills it")
	boss_at = boss["pos"]
	Arena.sim._hurt(Arena.sim.monsters.find(boss), 1.0e9, false, -1, "none", false)
	Arena.sim._reap()
	check(Arena.sim.clear_t > 0.0 and Arena.sim.monsters.is_empty(), "clear: the stage is cleared and the escort removed")
	var sec: float = Balance.ARENA_CLEAR_DELAY
	var count := int(round((sec - 0.05) * 60.0 / screen.speed))
	if keep_clear:
		await _roll("clear", count, 1, 1.0 / 60.0, 4)
		_note_moment("clear", 4 + count, 1, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9), "boss": _px(boss_at, 1.2), "event_frame": 4})
	else:
		await _tick(1.0 / 60.0)
	# The release knows where the boss fell: its instance carries 1 + that distance, and
	# what is left of the boss flows from there to the crystal.
	var link := _moment_scale(world, StellarVfx.MomentKind.STAGE_CLEAR)
	var boss_distance := StellarWorld.world(boss_at).distance_to(StellarWorld.world(Balance.ARENA_CENTER))
	check(absf(link - 1.0 - boss_distance) < 0.2, "clear: the release is linked to where the boss fell (%.2f u from the crystal, instance carries %.2f)" % [boss_distance, link - 1.0])
	# Leftovers that would outlive the change: a boss arrival (2.4 s), a ward dome, a
	# blast whose big light is still queued, a few hits. The world is paused under the
	# card, so anything still alive there would stay frozen on the new field.
	var planted: Vector2 = Balance.ARENA_CENTER + Vector2(-170, 120)
	world.vfx.arena_event({"t": "arena_boss", "p": planted})
	world.vfx.arena_event({"t": "arena_ward", "p": Balance.ARENA_CENTER, "r": Balance.ALTAR_R})
	world.vfx.arena_event({"t": "arena_blast", "p": Balance.ARENA_CENTER + Vector2(160, 130), "r": Balance.ARENA_BLAST_RADIUS})
	for n in range(4): world.vfx.event({"t": "hit", "p": Balance.ARENA_CENTER + Vector2(-120 + n * 70, -150), "c": Color("#ffcc66"), "em": 1.0})
	check(_live_skills(world) >= 2 and not world.vfx._delayed.is_empty() and _visible_domes(world) >= 1,
		"stage: leftovers are planted before the change (%d skills, %d queued, %d domes)" % [_live_skills(world), world.vfx._delayed.size(), _visible_domes(world)])
	# Run to the result, then open the next stage from it: the card opens over the freshly built field.
	var guard := 0
	while Arena.modal != "result" and guard < 240:
		await _tick(1.0 / 60.0)
		guard += 1
	check(Arena.modal == "result" and Arena.sim.won, "stage: the clear beat ends in victory")
	check(Arena.next_stage(), "stage: the victory opens the next stage")
	Arena.stage_themes[Arena.stage - 1] = next_theme
	Arena.sim = null
	Arena._open_stage(Arena.stage)
	_no_levelups()
	screen._track_modal()
	await _tick(1.0 / 60.0)
	check(Arena.modal == "stage" and Arena.theme_index == next_theme, "stage: the next battlefield opened under its card")
	# Everything born before the change is released in the frame the world is rebuilt in;
	# what is live now is the reveal alone: one sweep and one beacon per gate.
	check(_live_moments(world) == 1 + ArenaGeometry.route_count(), "stage: the clear is gone and the reveal is one sweep and a beacon per gate (%d sequences, %d gates)" % [_live_moments(world), ArenaGeometry.route_count()])
	check(_live_skills(world) == 0 and _count_pool(world, "burst") == 0 and world.vfx._delayed.is_empty() and _visible_domes(world) == 0,
		"stage: nothing of the previous field is left under the card (%d skills, %d bursts, %d queued, %d domes)" % [_live_skills(world), _count_pool(world, "burst"), world.vfx._delayed.size(), _visible_domes(world)])
	check(_lit_pulses(world) <= 1, "stage: the only pulse light under the card is the reveal's own (%d lit)" % _lit_pulses(world))
	check((world.vfx.get_node("Roads") as MeshInstance3D).visible, "stage: the road ribbons of the new layout are up")
	await paint(screen)
	await paint(screen)
	await snap(out_dir + "/stage_card.png")
	world.vfx.get_viewport().get_texture().get_image().save_png(out_dir + "/stage_field.png")
	var gates: Array = []
	for lane in range(ArenaGeometry.route_count()): gates.append(_px(ArenaGeometry.gate_point(lane, 20.0), 0.6))
	# A paused redraw must not move the reveal, and its first frame is exactly age 0.
	var clock: float = world.vfx._clock
	var youngest := INF
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == "moment": youngest = minf(youngest, float(fx["age"]))
	check(is_zero_approx(youngest), "stage: the picture behind the card is the reveal at age 0 (%.3f s)" % youngest)
	for n in range(6):
		screen.queue_redraw()
		await frames(1)
	check(is_equal_approx(world.vfx._clock, clock), "stage: the reveal waits while the card is open")
	check(Arena.confirm_stage() and Arena.modal == "box", "stage: the card is confirmed (the free first box)")
	Arena.confirm_summon()
	check(Arena.close_modal(), "stage: the box closes into the first preparation")
	_no_levelups()
	screen._track_modal()
	var reveal := int(round(3.6 * 30.0 / screen.speed))
	await _roll("stage", reveal, 2, 1.0 / 60.0)
	_note_moment("stage", reveal, 2, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9), "gates": gates,
		"stills": ["stage_card", "stage_field"], "layout": ArenaGeometry.layout(), "theme": next_theme})
	# Hold the first preparation past the film (see _moment_first): wave 1's beacons are not leftovers.
	Arena.sim.prep_t += 30.0
	for n in range(40): await _tick()
	check(_live_moments(world) == 0 and not (world.vfx.get_node("Moments") as MultiMeshInstance3D).visible
		and not (world.vfx.get_node("Roads") as MeshInstance3D).visible, "stage: the reveal is released when it has played")
	check(world.effects.size() <= 72, "stage: one-shot effects respect the shared 72 budget")
	await _close_arena()

## A stage boss falls among a crowd spread along every road. The escort must leave, not
## die: every body is followed through its halt, its run from the crystal and its end,
## against the haze StellarVfx draws for it.
func _moment_scatter(theme: int) -> void:
	var as_kill := has_arg("--scatter-as-kill")
	var prefix := "scatterkill" if as_kill else "scatter"
	var world := await _open_battle(theme, 20261018, 30)
	var vfx: StellarVfx = world.vfx
	_mid_wave(Balance.ARENA_WAVES)
	Arena.sim._spawn(Arena.boss_for(Arena.stage))
	if String(Arena.sim.events[-1].get("t", "")) == "spawn": Arena.sim.events.pop_back()
	var boss: Dictionary = Arena.sim.monsters[-1]
	var path := ArenaGeometry.route_points(0)
	boss["pos"] = path[int(path.size() * 0.5)]
	boss["route"] = 0
	boss["hp"] = 1.0e8
	boss["max"] = 1.0e8
	Arena.sim.boss_spawned = true
	Arena.sim.boss_warned = true
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()
	for n in range(40): await _tick()
	await _roll(prefix, 4, 1, 1.0 / 60.0)
	check(Arena.sim.monsters.has(boss) and Arena.sim.clear_t <= 0.0, "scatter: the boss is still standing when the capture kills it")
	# Everybody that is about to be sent away, where the simulator has it now.
	var tracked: Dictionary = {}
	for mo in Arena.sim.monsters:
		if mo == boss: continue
		var sid := int(mo.get("spawn_id", 0))
		var node: Node3D = world.monster_nodes.get(sid)
		if node == null or not node.has_method("motion_state"): continue
		var at: Vector2 = BattleSim.mpos(mo)
		tracked[sid] = {"at": at, "node": node, "id": String(mo["m"]["id"]), "wait": StellarVfx.scatter_delay(at),
			"heading": StellarVfx.scatter_heading(at, sid), "gone": -1.0, "run": 0.0, "moved_early": 0.0, "bad": "",
			"height": _body_height(node), "haze": -1.0}
	var boss_sid := int(boss["spawn_id"])
	var boss_node: Node3D = world.monster_nodes.get(boss_sid)
	Arena.sim._cache_positions()
	Arena.sim._hurt(Arena.sim.monsters.find(boss), 1.0e9, false, -1, "none", false)
	Arena.sim._reap()
	check(Arena.sim.clear_t > 0.0 and Arena.sim.monsters.is_empty(), "scatter: the stage is cleared and the escort removed")
	var flagged := 0
	for e in Arena.sim.events:
		if String(e.get("t", "")) == "die" and bool(e.get("scatter", false)):
			flagged += 1
			if as_kill: e.erase("scatter")
	check(flagged == tracked.size() and flagged >= 20, "scatter: every escort is sent away by a die event with scatter (%d events, %d bodies)" % [flagged, tracked.size()])
	var step := 1.0 / 60.0 * screen.speed
	var count := int(round(1.3 / step))
	var seen_bursts: Dictionary = {}
	var last_alive := 0.0
	for n in range(count):
		await _roll(prefix, 1, 1, 1.0 / 60.0, 4 + n)
		var age := float(n + 1) * step
		if n == 0:
			check(is_instance_valid(boss_node) and String(boss_node.motion_state()["death"]) == "die", "scatter: the boss itself dies the ordinary death")
		# The haze of each body, the first frame it exists.
		for fx in world.effects:
			if typeof(fx) != TYPE_DICTIONARY or String(fx.get("vfx", "")) != "burst": continue
			if int(round((fx["custom"] as Color).a)) != StellarVfx.Kind.SCATTER: continue
			var key := "%d:%d" % [int(fx["slot"]), int(fx["gen"])]
			if seen_bursts.has(key): continue
			var origin: Vector3 = (vfx.get_node("Bursts") as MultiMeshInstance3D).multimesh.get_instance_transform(int(fx["slot"])).origin
			seen_bursts[key] = true
			for sid in tracked:
				var row: Dictionary = tracked[sid]
				if float(row["haze"]) < 0.0 and StellarWorld.world(row["at"]).distance_to(origin) < 0.06:
					row["haze"] = age - float(fx["age"])
					break
		if as_kill: continue
		for sid in tracked:
			var row: Dictionary = tracked[sid]
			if float(row["gone"]) >= 0.0: continue
			# The world frees a body when its presentation is over: look before touching it.
			if not is_instance_valid(row["node"]) or not world.monster_nodes.has(sid):
				row["gone"] = age
				continue
			var node: Node3D = row["node"]
			last_alive = age
			var state: Dictionary = node.motion_state()
			var pivot: Transform3D = state["pivot"]
			# Where the pivot stands along the body's own way out, in world units.
			var away: Vector2 = row["heading"]
			var offset: Vector3 = node.global_transform.basis * pivot.origin
			var run := offset.dot(Vector3(away.x, 0.0, away.y))
			if String(state["death"]) != "scatter": row["bad"] = "death kind " + String(state["death"])
			if float(state["die"]) > 0.0: row["bad"] = "the Die clip is blended in"
			if absf(pivot.basis.get_euler().x) > 0.30: row["bad"] = "it topples (pitch %.2f)" % pivot.basis.get_euler().x
			if pivot.origin.y < -0.02: row["bad"] = "it sinks (%.2f)" % pivot.origin.y
			if age < float(row["wait"]) - step * 0.5:
				row["moved_early"] = maxf(float(row["moved_early"]), Vector2(offset.x, offset.z).length())
				if float(state["dissolve"]) > 0.0: row["bad"] = "it thins before the wave arrives"
			else:
				if run < float(row["run"]) - 0.001: row["bad"] = "it comes back (%.2f after %.2f)" % [run, float(row["run"])]
				row["run"] = maxf(float(row["run"]), run)
	if not as_kill:
		var bad := PackedStringArray()
		var slowest := 0.0
		var early := 0.0
		var shortest_run := INF
		var late := 0
		var no_haze := 0
		var haze_off := 0.0
		for sid in tracked:
			var row: Dictionary = tracked[sid]
			if String(row["bad"]) != "": bad.append("%s: %s" % [row["id"], row["bad"]])
			var gone := float(row["gone"])
			if gone < 0.0: late += 1
			slowest = maxf(slowest, gone)
			early = maxf(early, float(row["moved_early"]))
			shortest_run = minf(shortest_run, float(row["run"]))
			var length := gone - float(row["wait"])
			if gone >= 0.0 and (length < NativeMonsterModel.FLEE_SEC * 0.9 - step or length > NativeMonsterModel.FLEE_SEC * 1.1 + 2.0 * step):
				bad.append("%s: left %.2f s after the wave (run length %.2f)" % [row["id"], length, NativeMonsterModel.FLEE_SEC])
			if float(row["haze"]) < 0.0: no_haze += 1
			else: haze_off = maxf(haze_off, absf(float(row["haze"]) - float(row["wait"])))
		check(bad.is_empty(), "scatter: no body dies, topples, sinks, thins early or comes back (%d wrong, first: %s)" % [bad.size(), ", ".join(bad.slice(0, 4))])
		check(late == 0 and slowest <= 1.2, "scatter: every body has left %.2f s after the boss fell (%d still there at 1.3 s; the world keeps bodies 1.6 s, the next field is built at %.1f s)" % [slowest, late, Balance.ARENA_CLEAR_DELAY])
		check(early < 0.02, "scatter: a body stays where it is until the wave reaches it (largest early move %.3f u)" % early)
		check(shortest_run > NativeMonsterModel.FLEE_DIST * 0.5, "scatter: every body runs away from the crystal (shortest run seen %.2f u of %.2f)" % [shortest_run, NativeMonsterModel.FLEE_DIST])
		check(no_haze == 0 and haze_off <= step * 2.0 + 0.001, "scatter: each body's haze is born when its run starts (%d without haze, largest offset %.3f s)" % [no_haze, haze_off])
		# The boss itself may still be falling (a golem king topples for 1.45 s).
		var held := 0
		for sid in world._dying:
			if int(sid) != boss_sid: held += 1
		check(held == 0, "scatter: the world holds no escort back (%d retained)" % held)
	# A few bodies to look at closely: spread from the first the wave reaches to the last.
	var order: Array = tracked.keys()
	order.sort_custom(func(a, b) -> bool: return float(tracked[a]["wait"]) < float(tracked[b]["wait"]))
	var bodies: Array = []
	var box: Rect2 = screen.view_3d._active_box().grow(-30)
	var used: Array[Rect2] = []
	# Walk the list in strides so the picks cover near, middle and far bodies.
	var visit: Array = []
	for stride in [5, 3, 2, 1]:
		for pick in range(0, order.size(), stride):
			if not visit.has(order[pick]): visit.append(order[pick])
	for sid in visit:
		if bodies.size() >= 8: break
		var row: Dictionary = tracked[sid]
		var at: Vector2 = row["at"]
		var out: Vector2 = at + Vector2(row["heading"]) * NativeMonsterModel.FLEE_DIST * 1.25 * StellarWorld.UNIT
		var tall: float = row["height"]
		var rect := Rect2(screen.view_3d.project(at, 0.0), Vector2.ZERO)
		for point in [screen.view_3d.project(out, 0.0), screen.view_3d.project(at, tall * 1.3 + 0.5), screen.view_3d.project(out, tall + 0.7),
				screen.view_3d.project(at + Vector2(-40, 0), 0.0), screen.view_3d.project(at + Vector2(40, 0), 0.0), screen.view_3d.project(at + Vector2(0, 40), 0.0)]:
			rect = rect.expand(point)
		rect = rect.grow(12)
		if not box.encloses(rect): continue
		var crowded := false
		for other in used: crowded = crowded or other.grow(-10).intersects(rect)
		if crowded: continue
		used.append(rect)
		bodies.append({"label": row["id"], "rect": _rect_row(Rect2i(rect)), "wait": snappedf(float(row["wait"]), 0.001)})
	bodies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["wait"]) < float(b["wait"]))
	_note_moment(prefix, 4 + count, 1, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9), "event_frame": 4, "bodies": bodies,
		"crowd": tracked.size()})
	await _close_arena()

## Stage 10: the warning at a gate inside the frame, then the final boss.
func _moment_final(theme: int) -> void:
	var world := await _open_battle(theme, 20261015, 18)
	Arena.stage = CHAPTER_END
	Arena.wave = Arena.stage
	Arena.sim.stage = Arena.stage
	Arena.sim.wave = Arena.stage
	check(Arena.sim.final_stage(), "final: the simulator is on the last stage")
	for n in range(30): await _tick()
	var lane := 0
	var best := -INF
	var box: Rect2 = screen.view_3d._active_box()
	for i in range(ArenaGeometry.route_count()):
		var px: Vector2 = screen.view_3d.project(ArenaGeometry.gate_point(i, 10.0), 0.0)
		var margin := minf(minf(px.x - box.position.x, box.end.x - px.x), minf(px.y - box.position.y - 60.0, box.end.y - px.y))
		if margin > best:
			best = margin
			lane = i
	# The simulator's own warning, on the chosen gate; its boss then uses that gate. The boss wave's
	# preparation is left with the warning's seconds (ArenaSim.jump_to_boss replaces the old clock).
	var warning: float = Balance.ARENA_BOSS_WARNING
	_no_levelups()
	Arena.sim.jump_to_boss()
	Arena.sim.prep_t = warning
	Arena.sim.boss_warned = true
	Arena.sim.boss_lane = lane
	Arena.sim.events.append({"t": "arena_boss_warning", "p": Arena.sim.boss_gate(), "sec": warning, "lane": lane, "final": Arena.sim.chapter_boss()})
	var gate := _px(Arena.sim.boss_gate(), 1.2)
	var warn := int(round((warning - 0.05) * 30.0 / screen.speed))
	await _roll("final_warn", 1, 2, 1.0 / 60.0)
	# The warning is a chapter boss's (`final`, as the simulator sends it on STAGE 10).
	check(_has_moment(world, StellarVfx.MomentKind.FINAL_WARNING) and _live_skills(world) >= 1, "final: the warning adds the dark sun to the gate's own gather")
	await _roll("final_warn", warn - 1, 2, 1.0 / 60.0, 1)
	_note_moment("final_warn", warn, 2, 1.0 / 60.0, {"gate": gate})
	var guard := 0
	while not Arena.sim.boss_spawned and guard < 30:
		await _tick(1.0 / 60.0)
		guard += 1
	check(Arena.sim.boss_spawned and guard > 0, "final: the boss stepped in after the warning")
	check(_has_moment(world, StellarVfx.MomentKind.FINAL_BURST) and _live_skills(world) >= 1, "final: the arrival adds the dark sun's burst to the gate's own (%d + %d sequences)" % [_live_skills(world), _live_moments(world)])
	var fine := int(round(1.4 * 60.0 / screen.speed))
	await _roll("final_burst", fine, 1, 1.0 / 60.0)
	var rest := int(round(2.6 * 30.0 / screen.speed))
	await _roll("final_tail", rest, 2, 1.0 / 60.0)
	_note_moment("final_burst", fine, 1, 1.0 / 60.0, {"gate": gate})
	_note_moment("final_tail", rest, 2, 1.0 / 60.0, {"gate": gate, "starts_at": 1.4})
	# The last boss falls: the same clear beat with `final`, then the run ends in victory
	# and the result panel freezes the picture.
	var vfx: StellarVfx = world.vfx
	var boss: Dictionary = {}
	for mo in Arena.sim.monsters:
		if String(mo["kind"]) == "boss": boss = mo
	check(not boss.is_empty(), "final: the last boss is on the field")
	if boss.is_empty():
		await _close_arena()
		return
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.6
	var boss_px := _px(boss["pos"], 1.2)
	await _roll("final_clear", 4, 1, 1.0 / 60.0)
	Arena.sim._cache_positions()
	Arena.sim._hurt(Arena.sim.monsters.find(boss), 1.0e12, false, -1, "none", false)
	Arena.sim._reap()
	check(Arena.sim.clear_t > 0.0 and Arena.running, "final: the last boss gets the clear beat before the run ends")
	var sec: float = Balance.ARENA_CLEAR_DELAY
	var count := int(round((sec - 0.05) * 60.0 / screen.speed))
	await _roll("final_clear", 1, 1, 1.0 / 60.0, 4)
	var gates := ArenaGeometry.route_count()
	check(_has_moment(world, StellarVfx.MomentKind.STAGE_CLEAR) and _count_moments(world, StellarVfx.MomentKind.GATE_SEAL) == gates,
		"final: the last clear seals every gate (%d seals, %d gates)" % [_count_moments(world, StellarVfx.MomentKind.GATE_SEAL), gates])
	await _roll("final_clear", count - 1, 1, 1.0 / 60.0, 5)
	_note_moment("final_clear", 4 + count, 1, 1.0 / 60.0, {"crystal": _px(Balance.ARENA_CENTER, 0.9), "boss": boss_px, "event_frame": 4})
	var guard2 := 0
	while Arena.modal != "result" and guard2 < 60:
		await _tick(1.0 / 60.0)
		guard2 += 1
	check(Arena.modal == "result" and Arena.sim.won, "final: the run ends in victory when the beat is over")
	screen._track_modal()
	await paint(screen)
	await paint(screen)
	await snap(out_dir + "/final_result.png")
	vfx.get_viewport().get_texture().get_image().save_png(out_dir + "/final_rest_field.png")
	# The frozen picture is the last clear at rest and nothing else.
	var youngest := INF
	var held := 0
	for fx in world.effects:
		if typeof(fx) != TYPE_DICTIONARY or not fx.has("vfx"): continue
		if bool(fx.get("rest", false)):
			held += 1
			youngest = minf(youngest, float(fx["age"]))
	check(held == 1 + gates and _live_moments(world) == held, "final: the still is the last clear and its gate seals (%d held of %d live sequences)" % [held, _live_moments(world)])
	check(youngest >= StellarVfx.FINAL_REST, "final: every held sequence is at rest when the panel freezes it (youngest %.2f s, rest from %.2f)" % [youngest, StellarVfx.FINAL_REST])
	check(_live_skills(world) == 0 and _count_pool(world, "burst") == 0 and vfx._delayed.is_empty() and _visible_domes(world) == 0,
		"final: nothing else is left under the result panel (%d skills, %d bursts, %d queued)" % [_live_skills(world), _count_pool(world, "burst"), vfx._delayed.size()])
	var clock: float = vfx._clock
	for n in range(6):
		screen.queue_redraw()
		await frames(1)
	check(is_equal_approx(vfx._clock, clock), "final: the still does not move under the result panel")
	# "Try again" on the same screen: nothing of the won run is left, and the new run's
	# first battlefield waits under its card with its own reveal at age 0.
	Arena.start_run(20261099, 1)
	screen._track_modal()
	await paint(screen)
	await paint(screen)
	var retry_gates := ArenaGeometry.route_count()
	var oldest := 0.0
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and fx.has("vfx"): oldest = maxf(oldest, float(fx["age"]))
	check(Arena.modal == "stage" and _live_moments(world) == 1 + retry_gates and _count_moments(world, StellarVfx.MomentKind.STAGE_SWEEP) == 1
		and _count_moments(world, StellarVfx.MomentKind.GATE_BEACON) == retry_gates,
		"final: after a retry the first card shows the new field's reveal (%d sequences, %d gates)" % [_live_moments(world), retry_gates])
	check(is_zero_approx(oldest) and _live_skills(world) == 0 and _count_pool(world, "burst") == 0 and _lit_pulses(world) <= 1 and vfx._delayed.is_empty()
		and not (vfx.get_node("Aegis") as MeshInstance3D).visible,
		"final: nothing of the won run is left under it (oldest effect %.3f s, %d skills, %d bursts, %d lights)" % [oldest, _live_skills(world), _count_pool(world, "burst"), _lit_pulses(world)])
	await snap(out_dir + "/final_retry_card.png")
	await _close_arena()
	await _moment_final_hitch(theme)

## The same victory after a hitch: the simulator runs through the whole clear beat while
## nothing is drawn (the effect clock stands still), then one frame is drawn. The frozen
## picture must still be the last clear at rest.
func _moment_final_hitch(theme: int) -> void:
	var world := await _open_battle(theme, 20261017, 10)
	var vfx: StellarVfx = world.vfx
	Arena.stage = CHAPTER_END
	Arena.wave = Arena.stage
	Arena.sim.stage = Arena.stage
	Arena.sim.wave = Arena.stage
	_mid_wave(Balance.ARENA_WAVES)
	Arena.sim._spawn(Arena.boss_for(Arena.stage))
	if String(Arena.sim.events[-1].get("t", "")) == "spawn": Arena.sim.events.pop_back()
	var boss: Dictionary = Arena.sim.monsters[-1]
	var path := ArenaGeometry.route_points(0)
	boss["pos"] = path[int(path.size() * 0.6)]
	boss["hp"] = 1.0e8
	boss["max"] = 1.0e8
	Arena.sim.boss_spawned = true
	Arena.sim.boss_warned = true
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()
	for n in range(20): await _tick()
	# A boss arrival that is still burning when the run ends.
	vfx.arena_event({"t": "arena_boss", "p": boss["pos"], "final": true})
	Arena.sim._cache_positions()
	Arena.sim._hurt(Arena.sim.monsters.find(boss), 1.0e12, false, -1, "none", false)
	Arena.sim._reap()
	await _tick(1.0 / 60.0)
	check(_has_moment(world, StellarVfx.MomentKind.STAGE_CLEAR), "hitch: the last clear has begun")
	# Two seconds of simulation with no frame drawn.
	for n in range(12): Arena.sim.step(0.2)
	check(Arena.sim.won and Arena.modal == "result", "hitch: the run ended while nothing was drawn")
	screen._track_modal()
	await paint(screen)
	await paint(screen)
	var youngest := INF
	var held := 0
	for fx in world.effects:
		if typeof(fx) == TYPE_DICTIONARY and bool(fx.get("rest", false)):
			held += 1
			youngest = minf(youngest, float(fx["age"]))
	check(held == 1 + ArenaGeometry.route_count() and youngest >= StellarVfx.FINAL_REST and _live_moments(world) == held,
		"hitch: the frozen picture is still the last clear at rest (%d held, youngest %.2f s, %d live)" % [held, youngest, _live_moments(world)])
	check(_live_skills(world) == 0 and _count_pool(world, "burst") == 0 and vfx._delayed.is_empty(), "hitch: the boss arrival and every burst are gone under the result panel")
	check(_lit_pulses(world) == 1, "hitch: the still keeps its one light (%d lit)" % _lit_pulses(world))
	await snap(out_dir + "/final_settle.png")
	await _close_arena()

# --------------------------------------------------------------------------- #
# Hit feel and volumetric zones (2026-10-17, --hitfeel)
# --------------------------------------------------------------------------- #
## Staged scenes for the battle-feel overhaul, each at one 30 Hz tick per frame on the bare
## field: a ground zone of every element (the simulator's own zone list and tick damage,
## injected with the same fields _shoot writes), the Starlight Burst and the frost pulse
## through cast_skill, plain and critical rifle hits, a tank kill beside a swarm kill, a
## sword guardian's contacts, hits on a hovering body (meta _stellar_fly_height) and the
## level-up flare. A battle of six guardians against forty monsters closes the run and
## records the renderer's draw-call and primitive counts (perf). Every sequence carries a
## focus rectangle (design pixels) for the review crops.
const HITFEEL_SPOT := Vector2(-30, 205)          # relative to the crystal: open soil below it
const ZONE_CASTERS := {"fire": "brasa", "ice": "vidarr", "elec": "donn", "water": "limne", "none": "mimic"}
const HITFEEL_FLY := 1.5

func _hitfeel(theme: int) -> void:
	var world := await _open_arena(theme, 20261017)
	var spot: Vector2 = Balance.ARENA_CENTER + HITFEEL_SPOT
	var only := arg("--scene", "all")
	var wants := func(name: String) -> bool: return only == "all" or only == name
	_report["hitfeel"] = {"theme": theme, "spot": [spot.x, spot.y]}
	_no_levelups()
	if wants.call("zone"): await _hitfeel_zones(world, spot)
	if wants.call("blast"): await _hitfeel_blast(world, spot)
	if wants.call("freeze"): await _hitfeel_freeze(world)
	if wants.call("hit"): await _hitfeel_hits(world, spot)
	if wants.call("kill"): await _hitfeel_kills(world, spot)
	if wants.call("melee"): await _hitfeel_melee(world, spot)
	if wants.call("fly"): await _hitfeel_fly(world, spot)
	if wants.call("levelup"): await _hitfeel_levelup(world)
	if wants.call("perf"): await _hitfeel_perf(world)
	check(_alpha_leaks.is_empty(), "hitfeel: the 3D viewport keeps alpha 1 in every captured frame (%d leak, first %s)" % [_alpha_leaks.size(), ", ".join(_alpha_leaks.slice(0, 5))])
	_alpha_leaks.clear()
	await _close_arena()

## Guardians at explicit logical positions (grade 6), replacing whoever stood before.
func _stand(ids: Array, spots: Array) -> void:
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(ids.size()):
		Arena.gain_hero(Roster.unit_by_id(String(ids[i])), 6)
		Arena.heroes[i]["position"] = spots[i]
	Arena.sim.refresh_heroes()
	for i in range(Arena.sim.heroes.size()): Arena.sim.heroes[i]["pos"] = Arena.heroes[i]["position"]
	Arena.selected = -1
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()

## Sturdy bodies held on their spots (hp `hp`), spawned without the portal event.
func _bodies(ids: Array, spots: Array, hp: float = 1.0e5) -> Array:
	var out: Array = []
	for i in range(ids.size()):
		var mo := _put(String(ids[i]), spots[i])
		if not Arena.sim.events.is_empty() and String(Arena.sim.events[-1].get("t", "")) == "spawn": Arena.sim.events.pop_back()
		mo["hp"] = hp
		mo["max"] = hp
		out.append(mo)
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()
	return out

func _clear_bodies() -> void:
	Arena.sim.monsters.clear()
	Arena.sim._pending.clear()
	Arena.sim.bullets.clear()
	Arena.sim.zones.clear()
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()
	_no_levelups()
	for n in range(4): await _tick()

## The staged kills feed the run's experience; a level-up would open the talent offer (a
## modal that pauses the field until a pick, and opens whenever a preparation begins). Sink
## the experience so it never comes, and close an offer that is already open.
func _no_levelups() -> void:
	var run = Arena.sim.run if Arena.sim != null else null
	if run == null: return
	if "pending_levels" in run: run.pending_levels = 0
	if "xp" in run: run.xp = -1.0e9
	if "talent_offer" in run and not run.talent_offer.is_empty():
		run.talent_offer.clear()
		if String(run.modal) == "talent": run.close_modal()

## A chapter's last stage (STAGE 10): its boss is a chapter boss (ArenaRun.chapter_stage), which
## the final moments film.
const CHAPTER_END := 10

## Wave `n` in progress: opened (ArenaSim.begin_wave) as if long ago, so no banner is due, and its
## list held so the staged bodies are the only ones. Common skills can be cast (they are refused in
## a preparation), nothing spawns on its own and the wave never ends by itself. Gold for the skills.
func _mid_wave(n: int) -> void:
	var sim := Arena.sim
	sim.begin_wave(n)
	sim._spawn_t = 1.0e9
	sim.wave_t = 30.0
	Arena.gold = maxi(Arena.gold, 99999)
	var events: Array = sim.events
	for i in range(events.size() - 1, -1, -1):
		if String(events[i].get("t", "")) == "arena_wave": events.remove_at(i)

## A run that stops making progress (an awaited step that died on a script error) would hang until
## the driver's timeout. After `--watchdog` seconds of real time it reports and fails.
func _watchdog() -> void:
	var limit := arg_float("--watchdog", 2400.0)
	if limit <= 0.0: return
	var timer := get_tree().create_timer(limit, true, false, true)
	timer.timeout.connect(func() -> void:
		printerr("!! watchdog: no end after %.0f s" % limit)
		print("판정: 실패")
		get_tree().quit(2))

## `count` frames of one tick each, the bodies pinned before every tick.
func _film_pinned(prefix: String, count: int, bodies: Array, spots: Array, focus: Rect2, dt: float = 1.0 / 30.0) -> void:
	for n in range(count):
		_pin(bodies, spots)
		await _tick(dt)
		await _capture("%s_%02d" % [prefix, n])
	_note_focus(prefix, count, 1, focus, dt)

func _note_focus(prefix: String, count: int, ticks: int, focus: Rect2, dt: float = 1.0 / 30.0) -> void:
	_report["sequences"].append({"prefix": prefix, "frames": count, "ticks_per_frame": ticks, "tick": dt,
		"focus": [roundi(focus.position.x), roundi(focus.position.y), roundi(focus.size.x), roundi(focus.size.y)]})

## Design-pixel rectangle around a logical point: `radius` logical units wide, `tall`
## world units high above the ground, for the review crops.
func _focus(at: Vector2, radius: float, tall: float) -> Rect2:
	var view = screen.view_3d
	var rect := Rect2(view.project(at, 0.0), Vector2.ZERO)
	for corner in [Vector2(-radius, -radius), Vector2(radius, -radius), Vector2(radius, radius), Vector2(-radius, radius)]:
		rect = rect.expand(view.project(at + corner, 0.0))
		rect = rect.expand(view.project(at + corner, tall))
	return rect.grow(16).intersection(Rect2(0, 70, 992, 730))

## One ground zone per element on bodies standing inside it (one outside the radius), from
## the telegraph through the five ticks to the settle: zone_<el>_NN.
func _hitfeel_zones(world: StellarWorld, spot: Vector2) -> void:
	var spec: Dictionary = Balance.BULLET["zone"]
	var radius := float(spec["radius"])
	_stand(["echo"], [Balance.ARENA_CENTER + Vector2(-240, 40)])
	var offsets := [Vector2(-48, -22), Vector2(42, 30), Vector2(-8, 58), Vector2(radius + 34, -10)]
	for el in ["fire", "ice", "elec", "water", "none"]:
		var spots: Array = []
		for o in offsets: spots.append(spot + o)
		var bodies := _bodies(["bramble_imp", "vine_lynx", "stone_golem", "frost_imp"], spots)
		for n in range(6):
			_pin(bodies, spots)
			await _tick()
		var color := Color(String(Roster.unit_by_id(String(ZONE_CASTERS[el]))["color"]))
		Arena.sim.zones.append({"at": spot, "r": radius, "src": 0, "el": el, "c": color, "dmg": 10.0, "crit": false,
			"t": 0.0, "n": 0, "max": Balance.zone_ticks(), "delay": float(spec["delay"]), "tick": float(spec["tick"])})
		Arena.sim.events.append({"t": "zone", "p": spot, "r": radius, "c": color, "el": el, "src": 0, "delay": float(spec["delay"])})
		var zones_node: MultiMeshInstance3D = world.vfx.get_node("Zones")
		var seen_disc := false
		var prefix: String = "zone_" + String(el)
		for n in range(60):
			_pin(bodies, spots)
			await _tick()
			if n == 2:
				seen_disc = zones_node.multimesh.visible_instance_count >= 1
				var basis: Basis = zones_node.multimesh.get_instance_transform(0).basis
				check(is_equal_approx(basis.get_scale().x, radius / StellarWorld.UNIT), "zone %s: the disc is scaled to the damage radius (%.2f u)" % [el, basis.get_scale().x])
			await _capture("%s_%02d" % [prefix, n])
		check(seen_disc, "zone %s: the simulator's zone is drawn while it lives" % el)
		check(Arena.sim.zones.is_empty(), "zone %s: the zone has run its ticks within the capture" % el)
		_note_focus(prefix, 60, 1, _focus(spot, radius * 1.35, 3.2))
		await _clear_bodies()

## The Starlight Burst on five bodies (two frail enough to fall): blast_NN at every tick.
func _hitfeel_blast(world: StellarWorld, spot: Vector2) -> void:
	_stand(["echo"], [Balance.ARENA_CENTER + Vector2(-240, 40)])
	var spots := [spot, spot + Vector2(-70, 34), spot + Vector2(66, 26), spot + Vector2(-26, 84), spot + Vector2(44, 74)]
	var bodies := _bodies(["stone_golem", "bramble_imp", "vine_lynx", "pebble_imp", "crystal_skink"], spots)
	bodies[1]["hp"] = 40.0
	bodies[4]["hp"] = 40.0
	for n in range(6):
		_pin(bodies, spots)
		await _tick()
	Arena.sim.skill_cooldowns["blast"] = 0.0
	var rest: Vector3 = world.camera.position
	check(Arena.sim.cast_skill("blast"), "blast: the skill casts on the staged bodies")
	var alive: Array = []
	var alive_spots: Array = []
	for i in range(bodies.size()):
		if float(bodies[i]["hp"]) > 0.0:
			alive.append(bodies[i])
			alive_spots.append(spots[i])
	var focus := _focus(spot, Balance.ARENA_BLAST_RADIUS * 1.6, 7.5)
	var shake := 0.0
	var shake_at := -1
	for n in range(48):
		_pin(alive, alive_spots)
		await _tick()
		var moved := (world.camera.position - rest).length()
		if moved > shake:
			shake = moved
			shake_at = n
		await _capture("blast_%02d" % n)
	_note_focus("blast", 48, 1, focus)
	_report["hitfeel"]["blast_shake"] = {"max_u": snappedf(shake, 0.001), "frame": shake_at}
	check(shake > 0.03 and shake <= ArenaView.IMPACT_MAX + 0.01, "blast: the meteor's landing kicks the camera (%.3f u at frame %d, cap %.2f)" % [shake, shake_at, ArenaView.IMPACT_MAX])
	check(shake_at >= int(StellarVfx.BLAST_FALL * 30.0) - 1, "blast: the kick waits for the landing (frame %d, fall %d frames)" % [shake_at, int(StellarVfx.BLAST_FALL * 30.0)])
	await _clear_bodies()

## The frost pulse over a crowd on every road: freeze_NN at every tick.
func _hitfeel_freeze(world: StellarWorld) -> void:
	_stand(["echo"], [Balance.ARENA_CENTER + Vector2(-240, 40)])
	_crowd(24)
	for n in range(6): await _tick()
	Arena.sim.skill_cooldowns["freeze"] = 0.0
	check(Arena.sim.cast_skill("freeze"), "freeze: the skill casts on the crowd")
	for n in range(45):
		await _tick()
		await _capture("freeze_%02d" % n)
	_note_focus("freeze", 45, 1, Rect2(0, 70, 992, 730))
	await _clear_bodies()

## Rifle hits on two held bodies: hit_plain (no crits) then hit_crit (every shot critical).
func _hitfeel_hits(world: StellarWorld, spot: Vector2) -> void:
	_stand(["conor", "echo"], [spot + Vector2(-150, -36), spot + Vector2(150, -60)])
	var spots := [spot, spot + Vector2(54, 34)]
	var bodies := _bodies(["stone_golem", "vine_lynx"], spots)
	# Staged review only: a quicker trigger so a 36-frame capture holds several impacts.
	for i in range(Arena.sim.heroes.size()):
		Arena.sim.heroes[i]["crit"] = 0.0
		Arena.sim.heroes[i]["rate"] = float(Arena.sim.heroes[i].get("rate", 1.0)) * 3.0
	for n in range(10):
		_pin(bodies, spots)
		await _tick()
	await _film_pinned("hit_plain", 36, bodies, spots, _focus(spot, 110.0, 2.4))
	for i in range(Arena.sim.heroes.size()): Arena.sim.heroes[i]["crit"] = 1.0
	var crits := 0
	var plain := 0
	var kinds: Dictionary = {}
	var focus := _focus(spot, 110.0, 2.4)
	for n in range(36):
		_pin(bodies, spots)
		# Peek at this tick's events before the draw drains them.
		screen._process(1.0 / 30.0)
		for e in Arena.sim.events:
			if String(e.get("t", "")) == "hit":
				if bool(e.get("crit", false)): crits += 1
				else: plain += 1
		screen.queue_redraw()
		await frames(1)
		screen._draw_dt = 0.0
		for row in _fresh_bursts(world): kinds[int(row["kind"])] = int(kinds.get(int(row["kind"]), 0)) + 1
		await _capture("hit_crit_%02d" % n)
	_note_focus("hit_crit", 36, 1, focus)
	_report["hitfeel"]["crit_probe"] = {"crit_hits": crits, "plain_hits": plain, "burst_kinds": kinds}
	check(crits > 0, "hit_crit: the simulator reported critical hits (%d crit, %d plain)" % [crits, plain])
	check(int(kinds.get(StellarVfx.Kind.CRIT, 0)) > 0, "hit_crit: critical hits spawn CRIT bursts (%s)" % JSON.stringify(kinds))
	await _clear_bodies()

## A tank falls beside a swarm body that falls four ticks later: kill_NN.
func _hitfeel_kills(world: StellarWorld, spot: Vector2) -> void:
	_stand(["echo"], [Balance.ARENA_CENTER + Vector2(-240, 40)])
	var spots := [spot + Vector2(-40, 0), spot + Vector2(70, 26)]
	var bodies := _bodies(["wave_giant", "drop_slime"], spots)
	for n in range(8):
		_pin(bodies, spots)
		await _tick()
	var focus := _focus(spot, 120.0, 3.0)
	var rest: Vector3 = world.camera.position
	var shake := 0.0
	for n in range(40):
		_pin(bodies, spots)
		if n == 0: _slay(bodies[0])
		if n == 4: _slay(bodies[1])
		await _tick()
		shake = maxf(shake, (world.camera.position - rest).length())
		await _capture("kill_%02d" % n)
	_note_focus("kill", 40, 1, focus)
	_report["hitfeel"]["kill_shake_u"] = snappedf(shake, 0.001)
	check(shake > 0.02 and shake <= ArenaView.IMPACT_MAX + 0.01, "kill: a tank's fall kicks the camera a little (%.3f u, cap %.2f)" % [shake, ArenaView.IMPACT_MAX])
	await _clear_bodies()

## Kill a staged body through the simulator's own damage path.
func _slay(mo: Dictionary) -> void:
	var index := Arena.sim.monsters.find(mo)
	if index < 0: return
	Arena.sim._cache_positions()
	Arena.sim._hurt(index, 1.0e9, false, 0, "none")

## A sword guardian with three bodies inside his reach: melee_NN (the arc, the contacts).
func _hitfeel_melee(world: StellarWorld, spot: Vector2) -> void:
	var stand := spot + Vector2(0, -62)
	_stand(["jokull"], [stand])
	var reach := float(Arena.sim.heroes[0].get("range", 60.0))
	var spots := [stand + Vector2(0, reach * 0.78), stand + Vector2(-reach * 0.45, reach * 0.62), stand + Vector2(reach * 0.5, reach * 0.66)]
	var bodies := _bodies(["bramble_imp", "vine_lynx", "pebble_imp"], spots)
	for n in range(8):
		_pin(bodies, spots)
		await _tick()
	await _film_pinned("melee", 48, bodies, spots, _focus(spot, 95.0, 2.2))
	await _clear_bodies()

## Shots on a hovering body: the ray rides HITFEEL_FLY units up (the body adapter's own
## hover when it has one, else the harness lifts the pivot and sets the meta the effect
## layer reads), and every hit burst must be born at that height: fly_NN.
func _hitfeel_fly(world: StellarWorld, spot: Vector2) -> void:
	# Only guns and bows reach a flyer (Balance.ANTI_AIR_WEAPONS): a rifle and a bow, close.
	_stand(["conor", "echo"], [spot + Vector2(-105, -30), spot + Vector2(110, -48)])
	var spots := [spot + Vector2(10, 10)]
	var bodies := _bodies(["rapid_ray"], spots)
	for n in range(3):
		_pin(bodies, spots)
		await _tick()
	var sid := int(bodies[0]["spawn_id"])
	var node: Node3D = world.monster_nodes[sid]
	var fly := float(node.get_meta("_stellar_fly_height", 0.0))
	if fly <= 0.0:
		fly = HITFEEL_FLY
		node.set_meta("_stellar_fly_height", fly)
		if "_pivot_base" in node and node.get("_pivot") != null:
			node.set("_pivot_base", (node.get("_pivot_base") as Transform3D).translated(Vector3(0, fly, 0)))
	_report["hitfeel"]["fly_height"] = fly
	_report["hitfeel"]["fly_probe"] = {"vfx_reads": world.vfx._fly_height({"sid": sid}), "node_y": node.position.y,
		"sim_fly": bool(bodies[0].get("fly", false)), "rows": []}
	for i in range(Arena.sim.heroes.size()): Arena.sim.heroes[i]["crit"] = 0.0
	var lifted := 0
	var low := 0
	var focus := _focus(spot, 90.0, fly + 1.6)
	for n in range(54):
		_pin(bodies, spots)
		await _tick()
		# The body bobs: its hover meta moves every frame, so compare with this tick's value.
		var now := float(node.get_meta("_stellar_fly_height", fly)) if is_instance_valid(node) else fly
		for row in _fresh_bursts(world):
			if int(row["kind"]) != StellarVfx.Kind.HIT and int(row["kind"]) != StellarVfx.Kind.CRIT: continue
			if _report["hitfeel"]["fly_probe"]["rows"].size() < 6: _report["hitfeel"]["fly_probe"]["rows"].append([n, int(row["kind"]), snappedf(float(row["y"]), 0.01), snappedf(now, 0.01)])
			if float(row["y"]) >= minf(now, fly) - 0.45 and float(row["y"]) > 0.6: lifted += 1
			else: low += 1
		await _capture("fly_%02d" % n)
	_note_focus("fly", 54, 1, focus)
	_report["hitfeel"]["fly_hits"] = {"lifted": lifted, "low": low}
	check(lifted + low > 0, "fly: the rifle hit the hovering body during the capture (%d hits)" % (lifted + low))
	check(low == 0, "fly: every hit burst on the hovering body is born at its height (%d at the ground)" % low)
	await _clear_bodies()

## The level-up flare at the crystal (the HUD popup is the UI's): levelup_NN.
func _hitfeel_levelup(world: StellarWorld) -> void:
	_stand(["echo"], [Balance.ARENA_CENTER + Vector2(-240, 40)])
	for n in range(3): await _tick()
	world.vfx.arena_event({"t": "arena_levelup", "p": Balance.ARENA_CENTER, "level": 3})
	for n in range(40):
		await _tick()
		await _capture("levelup_%02d" % n)
	_note_focus("levelup", 40, 1, _focus(Balance.ARENA_CENTER, 130.0, 4.5))

## Six guardians against forty bodies for three seconds: the renderer's draw calls and
## primitives per frame (min / mean / max), the effect budget's high-water mark, and six
## frames of the fight for the record (perf_NN).
func _hitfeel_perf(world: StellarWorld) -> void:
	_field(SQUADS["a"])
	var pool := Roster.theme_pool(Arena.theme_for(1))
	var lanes := ArenaGeometry.route_count()
	var n := 0
	while Arena.sim.monsters.size() < 40:
		Arena.sim._spawn(pool[n % pool.size()])
		if not Arena.sim.events.is_empty() and String(Arena.sim.events[-1].get("t", "")) == "spawn": Arena.sim.events.pop_back()
		var mo: Dictionary = Arena.sim.monsters[-1]
		var path := ArenaGeometry.route_points(n % lanes)
		mo["pos"] = path[clampi(int(path.size() * (0.30 + 0.04 * float(n / lanes))), 0, path.size() - 2)]
		mo["route"] = n % lanes
		mo["hp"] = float(mo["hp"]) * 40.0
		mo["max"] = mo["hp"]
		mo["vel"] = ArenaGeometry.road_direction(mo["pos"])
		n += 1
	# Every body sturdy: the count must stay at forty for the whole measurement.
	for mo in Arena.sim.monsters:
		mo["hp"] = 1.0e6
		mo["max"] = 1.0e6
	Arena.sim._nav_key = ""
	Arena.sim._rebuild_navigation()
	for k in range(30): await _tick()
	var calls: Array = []
	var prims: Array = []
	var rs_calls: Array = []
	var rs_prims: Array = []
	var budget := 0
	var shot := 0
	for k in range(90):
		await _tick()
		calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		rs_calls.append(int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		rs_prims.append(int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
		budget = maxi(budget, world.effects.size())
		if k % 15 == 7:
			await _capture("perf_%02d" % shot)
			shot += 1
	_note_focus("perf", shot, 15, Rect2(0, 70, 992, 730))
	# The same fight with the effects layer hidden: the layer's own draw calls and primitives.
	var bare_calls: Array = []
	var bare_prims: Array = []
	world.vfx.visible = false
	for k in range(45):
		await _tick()
		bare_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		bare_prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	world.vfx.visible = true
	var stats := func(rows: Array) -> Dictionary:
		var total := 0
		var low: int = int(rows[0])
		var high: int = int(rows[0])
		for v in rows:
			total += int(v)
			low = mini(low, int(v))
			high = maxi(high, int(v))
		return {"min": low, "mean": total / rows.size(), "max": high}
	_report["hitfeel"]["perf"] = {"heroes": Arena.sim.heroes.size(), "monsters": Arena.sim.monsters.size(),
		"draw_calls": stats.call(calls), "primitives": stats.call(prims), "effects_peak": budget, "frames": calls.size(),
		"rs_draw_calls": stats.call(rs_calls), "rs_primitives": stats.call(rs_prims),
		"without_vfx": {"draw_calls": stats.call(bare_calls), "primitives": stats.call(bare_prims)}}
	print("perf: heroes %d monsters %d draw calls %s primitives %s effects peak %d" % [Arena.sim.heroes.size(), Arena.sim.monsters.size(),
		JSON.stringify(stats.call(calls)), JSON.stringify(stats.call(prims)), budget])
	check(budget <= 72, "perf: the shared effect budget holds (%d)" % budget)
	await _clear_bodies()
