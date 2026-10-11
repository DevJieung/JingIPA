extends Harness

## Real GL capture of sword melee strikes and per-character move speed in the
## continuous arena (actual ArenaScreen, simulator positions and events).
##
##   godot --path . --resolution 1280x800 res://tests/3d/melee_visual_preview.tscn -- --out DIR
##   options: --strike-only | --gait-only   --frames N (strike frames, default 72)
##            --planned-range   (preview the approved-pending sword reach, base 60 logical)
##            --fast F --slow S (gait spd multipliers, default 1.50 / 0.62)
##
## Strikes: jokull (ice pierce 3), pip (tool single), helga (ice splash), caden (elec chain),
## igni (fire pierce 3) and echo (bow, for contrast) stand on their posts while monsters are
## pinned 0.5~0.9 reach in front of each sword (one beyond reach, one outside the fan), so
## every strike geometry the simulator produces is on camera. Monsters are re-pinned after
## each simulated tick; the simulator still owns targeting, timing, damage and events.
##
## Gait: the same lane is run twice under the joystick, first by a spd `--fast` copy of pip,
## then by a spd `--slow` copy of brasa (unit copies live only in this process; roster and
## balance files are untouched). The report records screen positions for cropping.
## tools/3d/melee_review.py runs both window sizes and assembles GIF / contact sheets.

const STRIKE_IDS := ["jokull", "pip", "helga", "caden", "igni", "echo"]
const GAIT_FAST := "pip"
const GAIT_SLOW := "brasa"
const TICK := 1.0 / 30.0

var out_dir := "build/melee-speed/1280x800"
var screen: ArenaScreen
var main: Node2D
var _frames := 72
var _pins: Dictionary = {}          # monster index -> pinned logical position
var _planned: Dictionary = {}       # hero index -> planned reach (logical)
var _report: Dictionary = {"sequences": [], "heroes": {}, "gait": {}, "window": [0, 0], "events": {}}
var _event_counts: Dictionary = {}

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_frames = int(arg("--frames", "72"))
	I18n.set_locale("ko")
	_report["window"] = [get_window().size.x, get_window().size.y]
	_report["planned_range"] = has_arg("--planned-range")
	if has_arg("--probe"):
		await _probe()
		finish("Slash layer probe")
		return
	if not has_arg("--gait-only"):
		await _strikes()
	if not has_arg("--strike-only"):
		await _gait(GAIT_FAST, float(arg("--fast", "1.50")))
		await _gait(GAIT_SLOW, float(arg("--slow", "0.62")))
	var file := FileAccess.open(out_dir + "/melee-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "  ") + "\n")
	file = null
	finish("Melee strike and move speed visual preview")

# --------------------------------------------------------------------------- #
# Shared arena set-up (same path as the VFX preview: real main, real ArenaScreen)
# --------------------------------------------------------------------------- #
func _open(seed_value: int) -> void:
	Arena.start_run(seed_value)
	main = load("res://game/main.gd").new()
	add_child(main)
	await frames(3)
	main.show_arena()
	screen = main.screen
	screen.set_process(false)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	await paint(screen)

func _close() -> void:
	main.queue_free()
	main = null
	screen = null
	await frames(4)

func _pin_camera() -> void:
	screen.view_3d._follow_offset = Vector3.ZERO
	screen.view_3d._camera_initialized = true
	screen.view_3d._apply_camera(Vector3.ZERO)

## One simulated tick rendered once (dt advances the effect clock), then the
## monsters go back to their pins so the strike geometry stays on camera.
func _tick() -> void:
	screen._process(TICK)
	for i in _pins:
		if i < Arena.sim.monsters.size():
			Arena.sim.monsters[i]["pos"] = _pins[i]
			Arena.sim.monsters[i]["vel"] = Vector2.ZERO
	if not _pins.is_empty(): Arena.sim._cache_positions()
	for i in _planned:
		if i < Arena.sim.heroes.size(): Arena.sim.heroes[i]["range"] = _planned[i]
	for e in Arena.sim.events:
		var key := String(e.get("t", "")) + ("_melee" if bool(e.get("melee", false)) else "")
		_event_counts[key] = int(_event_counts.get(key, 0)) + 1
	screen.queue_redraw()
	await frames(1)
	screen._draw_dt = 0.0

func _capture(name: String) -> void:
	screen.queue_redraw()
	await frames(2)
	await snap(out_dir + "/" + name + ".png")

func _note(prefix: String, count: int) -> void:
	_report["sequences"].append({"prefix": prefix, "frames": count, "tick": TICK})

## The approved-pending sword reach (WEAPON_RANGE.sword 60) for a preview only.
static func _planned_reach(unit: Dictionary, tier: int) -> float:
	var rank := clampi(tier, 0, Balance.TIER_MAX)
	var multiplier: float = Balance.PROFILE_RANGE.get(String(unit.get("profile", "balance")), 1.0)
	return clampf(roundf((60.0 + rank * 6.0) * multiplier), Balance.RANGE_MIN, Balance.RANGE_MAX)

# --------------------------------------------------------------------------- #
# Probe: the Slashes layer alone, stepped by hand (review aid, not a game path)
# --------------------------------------------------------------------------- #
func _probe() -> void:
	await _open(20261013)
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	await paint(screen)
	_pin_camera()
	var world: StellarWorld = screen.view_3d.world
	var vfx: StellarVfx = world.vfx
	var c := Balance.ARENA_CENTER
	# sword left->right, sword right->left, wrench (upright), long reach
	vfx._slash(c + Vector2(-190, 150), Vector2(0, -1), 1.6, 1.0, false, Color("#7fd9ff"), 2.0)
	vfx._slash(c + Vector2(60, 150), Vector2(0, -1), 1.6, -1.0, false, Color("#f0451d"), 1.0)
	vfx._slash(c + Vector2(260, 150), Vector2(0, -1), 1.7, -1.0, true, Color("#ffe1a0"), 0.0)
	vfx._slash(c + Vector2(0, -120), Vector2(1, 0), 2.5, 1.0, false, Color("#c8ff2e"), 3.0)
	for n in range(10):
		await _capture("probe_%02d" % n)
		vfx.update(0.033)
	await _close()

# --------------------------------------------------------------------------- #
# Strikes
# --------------------------------------------------------------------------- #
func _strikes() -> void:
	await _open(20261011)
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(STRIKE_IDS.size()):
		Arena.gain_hero(Roster.unit_by_id(String(STRIKE_IDS[i])), 4 + (i % 3) * 2)
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + i * TAU / 6.0) * 165.0
	Arena.sim.refresh_heroes()
	Arena.selected = -1
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	_pins.clear()
	_planned.clear()
	var pool := Roster.theme_pool(Arena.theme_for(1))
	var spawned := 0
	for i in range(STRIKE_IDS.size()):
		var he: Dictionary = Arena.sim.heroes[i]
		var unit: Dictionary = he["h"]["unit"]
		var tier := int(he["h"]["tier"])
		var reach := float(he["range"])
		if has_arg("--planned-range") and Balance.is_melee(unit):
			reach = _planned_reach(unit, tier)
			_planned[i] = reach
		var at: Vector2 = he["pos"]
		var out: Vector2 = (at - Balance.ARENA_CENTER).normalized()
		var side := Vector2(-out.y, out.x)
		var offsets: Array = []
		match String(unit["id"]):
			"jokull", "igni":
				offsets = [out * reach * 0.55, out.rotated(deg_to_rad(32)) * reach * 0.85,
					out.rotated(deg_to_rad(-36)) * reach * 0.80, out * (reach + 45.0),
					out.rotated(deg_to_rad(96)) * reach * 0.7]
			"caden":
				offsets = [out * reach * 0.6, out.rotated(deg_to_rad(42)) * reach * 0.78,
					out.rotated(deg_to_rad(-44)) * reach * 0.82]
			"helga":
				offsets = [out * reach * 0.55, out * reach * 0.55 + side * 24.0, out * reach * 0.62 - side * 26.0]
			"pip":
				offsets = [out * reach * 0.62, out.rotated(deg_to_rad(28)) * reach * 0.85]
			_:
				offsets = [out * minf(reach * 0.55, 190.0)]
		for n in range(offsets.size()):
			Arena.sim._spawn(pool[(spawned * 3 + n) % pool.size()])
			var mo: Dictionary = Arena.sim.monsters[-1]
			var pin: Vector2 = ArenaGeometry.clamp_point(at + offsets[n], Balance.ARENA_MONSTER_RADIUS)
			mo["pos"] = pin
			mo["vel"] = Vector2.ZERO
			mo["hp"] = float(mo["max"]) * 40.0
			mo["max"] = mo["hp"]
			_pins[Arena.sim.monsters.size() - 1] = pin
			spawned += 1
		var pin_list: Array = []
		for n in range(offsets.size()):
			var pin: Vector2 = _pins[Arena.sim.monsters.size() - offsets.size() + n]
			pin_list.append([pin.x, pin.y])
		_report["heroes"][String(unit["id"])] = {"index": i, "tier": tier, "reach": reach,
			"reach_units": reach / StellarWorld.UNIT, "melee": Balance.is_melee(unit), "pos": [at.x, at.y],
			"pins": pin_list}
	Arena.sim._rebuild_navigation()
	Arena.sim._cache_positions()
	for i in _planned: Arena.sim.heroes[i]["range"] = _planned[i]
	Arena.sim.crystal_hp = Arena.sim.crystal_max * 0.85
	await paint(screen)
	_pin_camera()
	var world: StellarWorld = screen.view_3d.world
	var pools_before := world.vfx.get_child_count()
	for n in range(6): await _tick()
	for id in _report["heroes"]:
		var row: Dictionary = _report["heroes"][id]
		var at := Vector2(row["pos"][0], row["pos"][1])
		var pixel := screen.view_3d.project(at, 0.8)
		row["screen"] = [pixel.x, pixel.y]
		var foot := screen.view_3d.project(at, 0.0)
		row["screen_foot"] = [foot.x, foot.y]
		var pin_screens: Array = []
		for pin in row.get("pins", []):
			var ps := screen.view_3d.project(Vector2(pin[0], pin[1]), 0.0)
			pin_screens.append([ps.x, ps.y])
		row["pins_screen"] = pin_screens
	_event_counts.clear()
	for n in range(_frames):
		await _tick()
		await _capture("strike_%02d" % n)
	_note("strike", _frames)
	_report["events"]["strike"] = _event_counts.duplicate()
	check(int(_event_counts.get("fire_melee", 0)) >= 4, "sword heroes released melee strikes on camera (%d)" % int(_event_counts.get("fire_melee", 0)))
	check(int(_event_counts.get("hit_melee", 0)) >= 6, "melee hits landed on pinned bodies (%d)" % int(_event_counts.get("hit_melee", 0)))
	check(Arena.sim.bullets.filter(func(b): return Balance.is_melee(Arena.sim.heroes[int(b.get("src", 0))]["h"]["unit"])).is_empty(), "no sword projectile is ever simulated")
	check(world.vfx.get_child_count() == pools_before, "no VFX node is created during the strikes")
	check(world.effects.size() <= 72, "one-shot effects respect the shared 72 budget")
	_pins.clear()
	_planned.clear()
	await _close()

# --------------------------------------------------------------------------- #
# Gait: one runner at a time under the joystick, same lane, pinned camera
# --------------------------------------------------------------------------- #
func _gait(id: String, spd: float) -> void:
	await _open(20261012)
	Arena.heroes.clear()
	Arena.bench.clear()
	var runner: Dictionary = Roster.unit_by_id(id).duplicate(true)
	runner["spd"] = spd
	Arena.gain_hero(runner, 6)
	var start := Balance.ARENA_CENTER + Vector2(-250.0, 160.0)
	Arena.heroes[0]["position"] = start
	var bystanders := ["echo", "kari", "limne", "triton", "brian"]
	for i in range(bystanders.size()):
		Arena.gain_hero(Roster.unit_by_id(String(bystanders[i])), 4)
		Arena.heroes[i + 1]["position"] = Balance.ARENA_CENTER + Vector2(-220.0 + i * 110.0, -260.0)
	Arena.sim.refresh_heroes()
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	Arena.selected = 0
	check(is_equal_approx(float(Arena.sim.heroes[0]["speed"]), Balance.ARENA_HERO_SPEED * spd), "%s runs at spd %.2f in the simulator" % [id, spd])
	await paint(screen)
	_pin_camera()
	for n in range(4): await _tick()
	# Hold the joystick to the right (screen space maps to the ground plane).
	screen._joy_pointer = 1
	screen._joy_selection = 0
	screen.joystick = Vector2(1.0, 0.0)
	var from: Vector2 = Arena.sim.heroes[0]["pos"]
	var count := 0
	for n in range(42):
		await _tick()
		await _capture("gait_%s_%02d" % [id, count])
		count += 1
	var travelled := Vector2(Arena.sim.heroes[0]["pos"]).distance_to(from)
	screen.cancel_joystick()
	for n in range(18):
		await _tick()
		await _capture("gait_%s_%02d" % [id, count])
		count += 1
	_note("gait_" + id, count)
	var to: Vector2 = Arena.sim.heroes[0]["pos"]
	var a := screen.view_3d.project(from, 0.8)
	var b := screen.view_3d.project(to, 0.8)
	_report["gait"][id] = {"spd": spd, "speed": float(Arena.sim.heroes[0]["speed"]), "travelled": travelled,
		"units_per_s": float(Arena.sim.heroes[0]["speed"]) / StellarWorld.UNIT,
		"from": [a.x, a.y], "to": [b.x, b.y], "frames": count}
	check(absf(travelled - Balance.ARENA_HERO_SPEED * spd * 42.0 * TICK) < 12.0,
		"%s covered its own speed's distance in 1.4 s (%.0f logical)" % [id, travelled])
	await _close()
