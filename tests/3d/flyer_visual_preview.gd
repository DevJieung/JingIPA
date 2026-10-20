extends Harness

## Real GL capture of the flying monsters (`fly: true` in the roster) in the actual arena
## (real ArenaScreen, simulator positions, events and timers): each flyer descends at a
## gate beside a walking monster of its biome, follows the lane past a hero standing at
## the kerb (who shoots it as it passes), is set down on the last stretch, besieges the
## crystal under three shooters for more than one siege phase and dies (hp set to 0 so
## the simulator emits its own die event). Nothing here changes balance or roster files.
##
##   godot --path . --disable-vsync res://tests/3d/flyer_visual_preview.tscn -- --out DIR --film 1280x800
##   options: --ids a,b   --walk-every N (default 3 ticks)   --no-film (capture the window)
##
## --film WxH draws the game into an off-screen picture of that size while the window is
## 96x60, so the login session's GPU display can be used (tests/3d/flyer_review.py).
## The report (flyers-report.json) carries, per frame, where the flyer's ground point and
## its body are on the 1280x800 design canvas, the hit flash and the world's
## `_stellar_fly_height` meta, so the review tool can crop around the body.

const FLYERS := {
	"rapid_ray": {"theme": "calm_lake", "walker": "drop_slime"},
	"jelly_seer": {"theme": "tidal_flats", "walker": "wave_giant"},
	"runestone_idol": {"theme": "gravel_hills", "walker": "stone_golem"},
}
const SHOOTERS := ["kari", "echo", "chispa"]
const KERB_HERO := "brigid"
const TICK := 1.0 / 30.0
const SEED := 20261017

var out_dir := "build/flyers/after/1280x800"
var screen: ArenaScreen
var main: Node2D
var film: SubViewport
var _report: Dictionary = {"flyers": {}, "window": [0, 0], "picture": [1280, 800]}

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	I18n.set_locale("ko")
	Save.music = false
	Save.sfx = false
	_open_film()
	_report["window"] = [get_window().size.x, get_window().size.y]
	if film != null: _report["picture"] = [film.size.x, film.size.y]
	var ids: Array = FLYERS.keys()
	if arg("--ids", "") != "": ids = Array(arg("--ids", "").split(","))
	var walk_every := int(arg("--walk-every", "3"))
	for id in ids:
		await _flyer(String(id), walk_every)
	var file := FileAccess.open(out_dir + "/flyers-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "  ") + "\n")
	file = null
	finish("Flying monster arena capture")

# --------------------------------------------------------------------------- #
# Picture: the window, or an off-screen film of the requested size.
# --------------------------------------------------------------------------- #
func _open_film() -> void:
	var spec := arg("--film", "")
	if spec.is_empty() or has_arg("--no-film"): return
	var size := Vector2i(int(spec.get_slice("x", 0)), int(spec.get_slice("x", 1)))
	get_window().size = Vector2i(96, 60)
	film = SubViewport.new()
	film.name = "Film"
	film.size = size
	film.size_2d_override = Vector2i(1280, 800)
	film.size_2d_override_stretch = true
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.transparent_bg = false
	film.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	film.set("oversampling_override", float(size.x) / 1280.0)
	add_child(film)

func _picture() -> Viewport:
	return film if film != null else get_viewport()

func _mount(node: Node) -> void:
	if film != null: film.add_child(node)
	else: add_child(node)

func snap(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := _picture().get_texture().get_image()
	image.save_png(path)
	return image

# --------------------------------------------------------------------------- #
# Arena plumbing (the boss scale harness pattern)
# --------------------------------------------------------------------------- #
func _open(seed_value: int, theme: int) -> void:
	Arena.start_run(seed_value)
	main = load("res://game/main.gd").new()
	_mount(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	check(Arena.choose_theme(theme), "tool API puts the battlefield on stage 1")
	Arena.confirm_summon()
	Arena.close_modal()
	screen.speed = 1.0
	screen._track_modal()
	await paint(screen)

func _close() -> void:
	main.queue_free()
	main = null
	screen = null
	await frames(4)

func _camera_at(p: Vector2) -> void:
	screen.view_3d._follow_offset = StellarWorld.world(p)
	screen.view_3d._camera_initialized = true
	screen.view_3d._apply_camera(screen.view_3d._follow_offset)

func _tick() -> void:
	screen._process(TICK)
	screen.queue_redraw()
	await frames(1)
	screen._draw_dt = 0.0

func _capture(name: String) -> void:
	screen.queue_redraw()
	await frames(2)
	await snap(out_dir + "/" + name + ".png")

func _theme_index(id: String) -> int:
	for i in range(Roster.THEMES.size()):
		if String(Roster.THEMES[i]["id"]) == id: return i
	printerr("!! unknown theme " + id)
	return 0

func _row(id: String) -> Dictionary:
	for m in Roster.MONSTERS:
		if String(m["id"]) == id: return m
	return {}

func _find(sid: int) -> Dictionary:
	for mo in Arena.sim.monsters:
		if int(mo.get("spawn_id", 0)) == sid: return mo
	return {}

## Hero spots around the altar that are not on any road (so monsters are never blocked).
func _off_road_spots(count: int) -> Array:
	var spots: Array = []
	var margin := Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS + 6.0
	for n in range(72):
		var angle := TAU * float(n) / 72.0 + 0.3
		for radius: float in [150.0, 185.0, 220.0]:
			var p: Vector2 = Balance.ARENA_CENTER + Vector2.from_angle(angle) * radius
			if ArenaGeometry.on_road(p, margin): continue
			var clear := true
			for other in spots:
				if Vector2(other).distance_to(p) < 60.0: clear = false
			if clear:
				spots.append(p)
				break
		if spots.size() >= count: break
	while spots.size() < count: spots.append(Balance.ARENA_CENTER + Vector2(0, -1) * 200.0)
	return spots

## Point of a lane `distance` logical units of walking from its gate.
func _lane_point(lane: int, distance: float) -> Dictionary:
	var path := ArenaGeometry.route_points(lane)
	var left := distance
	for i in range(path.size() - 1):
		var step := path[i].distance_to(path[i + 1])
		if left <= step:
			var direction := (path[i + 1] - path[i]).normalized()
			return {"p": path[i] + direction * left, "dir": direction}
		left -= step
	return {"p": path[-1], "dir": (path[-1] - path[-2]).normalized()}

## A hero post at the kerb of the lane, clear of every road, next to where the flyer
## passes about `seconds` after its spawn.
func _kerb_spot(lane: int, seconds: float, speed: float) -> Vector2:
	var at := _lane_point(lane, Balance.PATH_SPEED * speed * seconds)
	var p: Vector2 = at["p"]
	var direction: Vector2 = at["dir"]
	for side in [1.0, -1.0]:
		var normal: Vector2 = Vector2(-direction.y, direction.x) * float(side)
		for distance in range(80, 150, 4):
			var candidate: Vector2 = p + normal * float(distance)
			if not ArenaGeometry.contains(candidate, Balance.ARENA_HERO_RADIUS + 4.0): break
			if ArenaGeometry.on_road(candidate, 0.0): continue
			if ArenaGeometry.nearest_road_point(candidate).distance_to(candidate) < 78.0: continue
			return candidate
	return p + Vector2(-direction.y, direction.x) * 100.0

func _place(mo: Dictionary, at: Vector2) -> void:
	mo["pos"] = ArenaGeometry.clamp_point(at, Balance.ARENA_MONSTER_RADIUS)
	mo["vel"] = Vector2.ZERO
	mo["path"] = PackedVector2Array()
	mo["nav_v"] = -1

func _frame(stage: String, index: int, sid: int, walker_sid: int, kerb: Vector2) -> Dictionary:
	var world: StellarWorld = screen.view_3d.world
	var mo := _find(sid)
	var row := {"stage": stage, "index": index, "name": "", "flyer": {}, "walker": {}, "kerb": _px(kerb, 0.0)}
	var node: Node3D = world.monster_node(sid)
	if not mo.is_empty():
		var p: Vector2 = mo["pos"]
		var h := float(node.get_meta("_stellar_fly_height", 0.0)) if node != null else 0.0
		row["flyer"] = {"pos": [p.x, p.y], "foot": _px(p, 0.0), "body": _px(p, h + 0.5),
			"fly_height": h, "flash": float(mo.get("flash", 0.0)), "blocked": bool(mo.get("blocked", false)),
			"siege_t": float(mo.get("siege_t", -1.0)), "stun": float(mo.get("stun_t", 0.0)),
			"distance": p.distance_to(Balance.ARENA_CENTER)}
	elif node != null and node.is_inside_tree():
		# Dying: the simulator entry is gone, the body still plays its death.
		var p := StellarWorld.logical(node.global_position)
		row["flyer"] = {"pos": [p.x, p.y], "foot": _px(p, 0.0), "body": _px(p, float(node.get_meta("_stellar_fly_height", 0.0)) + 0.5),
			"fly_height": float(node.get_meta("_stellar_fly_height", 0.0)), "dying": true}
	var walker := _find(walker_sid)
	if not walker.is_empty():
		var p: Vector2 = walker["pos"]
		row["walker"] = {"pos": [p.x, p.y], "foot": _px(p, 0.0), "flash": float(walker.get("flash", 0.0))}
	return row

func _px(p: Vector2, height: float) -> Array:
	var pixel := screen.view_3d.project(p, height)
	return [snappedf(pixel.x, 0.1), snappedf(pixel.y, 0.1)]

func _flyer(id: String, walk_every: int) -> void:
	var row := _row(id)
	var spec: Dictionary = FLYERS.get(id, {"theme": "calm_lake", "walker": "drop_slime"})
	check(not row.is_empty() and bool(row.get("fly", false)), id + " is a flyer in the roster")
	if row.is_empty(): return
	var walker_row := _row(String(spec["walker"]))
	await _open(SEED + id.hash() % 1000, _theme_index(String(spec["theme"])))
	Arena.heroes.clear()
	Arena.bench.clear()
	var lane := 0
	var speed := float(Balance.MKIND[String(row["kind"])]["spd"])
	# Three shooters near the altar (gun/bow), off the roads so they never block the lane,
	# so the siege shows real hits on the hovering body; one more bow at the kerb of the
	# lane, where the flyer passes about 1.4 s after its spawn.
	var spots := _off_road_spots(SHOOTERS.size())
	for i in range(SHOOTERS.size()):
		Arena.gain_hero(Roster.unit_by_id(String(SHOOTERS[i])), 6)
		Arena.heroes[i]["position"] = spots[i]
	var kerb := _kerb_spot(lane, 1.4, speed)
	Arena.gain_hero(Roster.unit_by_id(KERB_HERO), 6)
	Arena.heroes[SHOOTERS.size()]["position"] = kerb
	Arena.sim.refresh_heroes()
	Arena.selected = -1
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	Arena.sim.boss_spawned = true
	Arena.sim.boss_warned = true
	Arena.sim._forced_lane = lane
	# The walker first, then the flyer, side by side at the gate.
	Arena.sim._spawn(walker_row)
	var walker: Dictionary = Arena.sim.monsters[-1]
	var walker_sid := int(walker["spawn_id"])
	walker["hp"] = 1.0e9
	walker["max"] = walker["hp"]
	Arena.sim._spawn(row)
	var mo: Dictionary = Arena.sim.monsters[-1]
	var sid := int(mo["spawn_id"])
	mo["hp"] = 1.0e9
	mo["max"] = mo["hp"]
	var gate := ArenaGeometry.gate_point(lane, Balance.ARENA_MONSTER_RADIUS + 2.0)
	var radial := (gate - Balance.ARENA_CENTER).normalized()
	var across := Vector2(-radial.y, radial.x)
	_place(walker, gate - across * 15.0)
	_place(mo, gate + across * 15.0)
	Arena.sim._rebuild_navigation()
	Arena.sim._cache_positions()
	_camera_at(mo["pos"])
	await paint(screen)
	var world: StellarWorld = screen.view_3d.world
	var node: Node3D = world.monster_node(sid)
	check(node != null, id + " has a live world node")
	var record := {"sid": sid, "walker": String(spec["walker"]), "walker_sid": walker_sid, "theme": String(spec["theme"]),
		"kerb": [kerb.x, kerb.y], "frames": {}, "rows": [], "fly_height": {}}
	var rows: Array = record["rows"]
	var heights: Array = []
	# Spawn: 0.45 s descent at the gate, camera on the flyer.
	var count := 0
	for n in range(14):
		mo = _find(sid)
		if mo.is_empty(): break
		_camera_at(mo["pos"])
		await _capture("%s_spawn_%02d" % [id, count])
		rows.append(_frame("spawn", count, sid, walker_sid, kerb))
		count += 1
		await _tick()
	record["frames"]["spawn"] = count
	# Walk: follow the lane for 30 captures (the kerb hero fires as the flyer passes), then
	# both bodies are set down just outside the altar stop and walk the last stretch.
	count = 0
	var stop := Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS
	var ticks := 0
	var placed := false
	while ticks < 900:
		mo = _find(sid)
		if mo.is_empty(): break
		var p: Vector2 = mo["pos"]
		if p.distance_to(Balance.ARENA_CENTER) <= stop + 2.0: break
		if ticks == 30 * walk_every and not placed:
			placed = true
			# Both bodies are set down on the lane itself, 40 logical units of walking
			# before the altar stop (a radial point can miss a spiral lane, and the
			# route's last point is the crystal).
			var at := _lane_point(lane, ArenaGeometry.route_length(lane) - (stop + 40.0))
			var near: Vector2 = at["p"]
			var direction: Vector2 = at["dir"]
			var beside := Vector2(-direction.y, direction.x)
			_place(mo, near + beside * 13.0)
			var other := _find(walker_sid)
			if not other.is_empty(): _place(other, near - beside * 13.0 - direction * 10.0)
			Arena.sim._cache_positions()
		if ticks % walk_every == 0:
			_camera_at(p)
			await _capture("%s_walk_%02d" % [id, count])
			rows.append(_frame("walk", count, sid, walker_sid, kerb))
			if not rows[-1]["flyer"].is_empty(): heights.append(float(rows[-1]["flyer"]["fly_height"]))
			count += 1
		await _tick()
		ticks += 1
	record["frames"]["walk"] = count
	record["walk_ticks"] = ticks
	check(ticks < 900, id + " reached the altar")
	# Siege: camera on the crystal; 40 consecutive ticks cover the strike at the wrap.
	_camera_at(Balance.ARENA_CENTER)
	count = 0
	for n in range(40):
		mo = _find(sid)
		if mo.is_empty(): break
		await _capture("%s_siege_%02d" % [id, count])
		rows.append(_frame("siege", count, sid, walker_sid, kerb))
		count += 1
		await _tick()
	record["frames"]["siege"] = count
	mo = _find(sid)
	if not mo.is_empty():
		var p: Vector2 = mo["pos"]
		record["siege_distance"] = p.distance_to(Balance.ARENA_CENTER)
		record["siege_t"] = float(mo.get("siege_t", -1.0))
		check(float(mo.get("siege_t", -1.0)) >= 0.0, id + " besieges the crystal")
		# Die: the simulator emits its own die event; the body plays its fall and dissolve.
		mo["hp"] = 0.0
	count = 0
	for n in range(50):
		await _tick()
		await _capture("%s_die_%02d" % [id, count])
		rows.append(_frame("die", count, sid, walker_sid, kerb))
		count += 1
		if world.monster_node(sid) == null: break
	record["frames"]["die"] = count
	check(world.monster_node(sid) == null, id + " body released after its death presentation")
	if not heights.is_empty():
		var low: float = float(heights[0])
		var high: float = float(heights[0])
		for h in heights:
			low = minf(low, float(h))
			high = maxf(high, float(h))
		record["fly_height"] = {"min": low, "max": high}
	_report["flyers"][id] = record
	await _close()
