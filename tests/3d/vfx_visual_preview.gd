extends Harness

## Real GL capture of the battle VFX layer in the continuous arena: muzzle release,
## projectiles and trails, impacts, beams / chain / ricochet, zones, deaths, spawns,
## status bursts, guardian skills and crystal hits, as consecutive frames.
##
##   godot --path . --resolution 1280x800 res://tests/3d/vfx_visual_preview.tscn -- --out DIR
##   options: --squad a|b|all  --theme N  --frames N  --quick  --skills-only
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
	# Guardian skills, each through the actual simulator entry point.
	for skill in ["blast", "freeze", "ward"]:
		Arena.sim.skill_cooldowns[skill] = 0.0
		check(Arena.sim.cast_skill(skill), squad + ": skill casts " + skill)
		for n in range(10):
			await _tick()
			await _capture("%s_skill_%s_%02d" % [squad, skill, n])
		for k in range(12): await _tick()
	_note(squad + "_skill", 30, 1)
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
	main.queue_free()
	main = null
	screen = null
	await frames(4)

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

func _note(prefix: String, count: int, ticks: int) -> void:
	_report["sequences"].append({"prefix": prefix, "frames": count, "ticks_per_frame": ticks, "tick": 1.0 / 30.0})

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
