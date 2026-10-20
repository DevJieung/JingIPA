extends Node
class_name ArenaFrameBench

## Frame cost of the live arena, split by part, against the number of monsters on the
## field (docs/PERF_NATIVE.md). No judgement: a table for optimisation work.
##
##   tools/perf/frame_bench.sh [stage] [frames]        (a GPU display; see the script)
##
## Opens the real ArenaScreen on a seeded run with six guardians on the roads at the given
## stage, at 3x battle speed, and times: the simulator step, the whole _draw, the 3D
## field (draw_arena: world sync split into heroes / monster poses / facing / status
## marks / spawns / the rest, VFX, effects), the HUD parts (the screen's ArenaHud view) and,
## inside the shipped monster adapter, the pose composition, the skeleton write and the
## reaction pivot.
## Wall time is the whole frame (script + engine + render on this GPU); the phone's GPU
## cost is not in it, only its draw calls and triangles.
const KEYS := ["sim", "draw", "draw_arena", "w_total", "w_heroes", "w_anim", "w_face", "w_status", "w_spawn", "w_loop_other", "w_cleanup", "w_vfx_sync", "w_effects", "hud_bars", "hud_minimap", "hud_controls", "hud_topbar", "m_compose", "m_skeleton", "m_pivot"]
static var us := {}
var state := 0
var main: Node = null
var screen = null
var wait := 0
var frames := 0
var frames_total := 2400
var stage := 10
var seed_value := 20261017
var last_wall := 0
var buckets := {}
var worst_wall := 0.0
var worst_frame := -1
var worst_monsters := 0
var spikes := 0

static func lap(key: String, t0: int) -> void:
	us[key] = int(us.get(key, 0)) + Time.get_ticks_usec() - t0

static func add(key: String, value: int) -> void:
	us[key] = int(us.get(key, 0)) + value

class BenchMonster extends NativeMonsterModel:
	func _compose(motion_time: float) -> void:
		var t0 := Time.get_ticks_usec()
		super._compose(motion_time)
		ArenaFrameBench.lap("m_compose", t0)
	func _apply_skeleton() -> void:
		var t0 := Time.get_ticks_usec()
		super._apply_skeleton()
		ArenaFrameBench.lap("m_skeleton", t0)
	func _apply_pivot() -> void:
		var t0 := Time.get_ticks_usec()
		super._apply_pivot()
		ArenaFrameBench.lap("m_pivot", t0)

## StellarWorld.sync_battle + ArenaWorld.sync_battle with timers (the loop is a copy:
## keep it in step with game/3d/stellar_world.gd when that changes).
class BenchWorld extends ArenaWorld:
	func sync_battle(sim, time: float, lives: int, dt: float = 0.016) -> void:
		var t_all := Time.get_ticks_usec()
		var t0 := Time.get_ticks_usec()
		sync_heroes(sim.heroes, time, true)
		ArenaFrameBench.lap("w_heroes", t0)
		weather_update(time)
		var keep: Dictionary = {}
		var anim_us := 0
		var face_us := 0
		var status_us := 0
		var spawn_us := 0
		var t_loop := Time.get_ticks_usec()
		for mo in sim.monsters:
			var key: int = int(mo.get("spawn_id", 0))
			if key == 0:
				key = int(float(mo.get("motion_phase", 0.0)) * 1000000) + int(mo.get("route", 0)) * 1000001
			keep[key] = true
			if not monster_nodes.has(key):
				var ts := Time.get_ticks_usec()
				var model := StellarModels.monster(mo["m"])
				if model is NativeMonsterModel: model.set_script(BenchMonster)
				if bool(mo.get("elite", false)): StellarModels.elite(model)
				actors.add_child(model)
				monster_nodes[key] = model
				_monster_status[key] = [model.get_node("StellarBurn"), model.get_node("StellarFrost"), model.get_node("StellarStun")]
				if model.has_method("visual_event"): model.call("visual_event", "spawn", {"p": BattleSim.mpos(mo), "sid": key})
				spawn_us += Time.get_ticks_usec() - ts
			var node: Node3D = monster_nodes[key]
			var p := BattleSim.mpos(mo)
			var native_monster := bool(node.get_meta("_stellar_native_monster", false))
			var heading := _monster_heading(mo, p, _monster_ahead(mo, p))
			var adapter := node as NativeMonsterModel
			if adapter != null:
				var tf := Time.get_ticks_usec()
				if heading.length_squared() > 0.001: adapter.face_toward(heading, dt)
				face_us += Time.get_ticks_usec() - tf
				node.position = world(p,monster_ground)
				if node.rotation.z != 0.0: node.rotation.z = 0.0
				adapter.set_hit_flash(float(mo.get("flash", 0.0)))
				adapter.set_siege(_monster_siege(mo, p))
				var ta := Time.get_ticks_usec()
				adapter.animate_visual(float(mo.get("motion_t",0.0))+float(mo.get("motion_phase",0.0)), _monster_moving(mo))
				anim_us += Time.get_ticks_usec() - ta
			elif native_monster:
				_face(node, heading, true, dt)
				node.position = world(p,monster_ground)
				node.rotation.z = 0.0
				if node.has_method("set_hit_flash"): node.call("set_hit_flash", float(mo.get("flash", 0.0)))
				if node.has_method("set_siege"): node.call("set_siege", _monster_siege(mo, p))
				node.call("animate_visual", float(mo.get("motion_t",0.0))+float(mo.get("motion_phase",0.0)), _monster_moving(mo))
			else:
				_face(node, heading, true, dt)
				node.position = world(p,monster_ground+sin(time*10+key)*0.035)
				node.rotation.z = sin(time*10+key)*0.035
			var tst := Time.get_ticks_usec()
			var status: Array = _monster_status.get(key, [])
			if status.is_empty():
				status = [node.get_node("StellarBurn"), node.get_node("StellarFrost"), node.get_node("StellarStun")]
				_monster_status[key] = status
			var burn: Node3D = status[0]
			var frost: Node3D = status[1]
			var stun: Node3D = status[2]
			burn.visible=float(mo.get("burn_t",0))>0
			frost.visible=float(mo.get("slow_t",0))>0
			stun.visible=float(mo.get("stun_t",0))>0
			if burn.visible: burn.scale=Vector3.ONE*(0.9+sin(time*18+key)*0.13)
			if stun.visible: stun.rotation.y=time*5
			if not native_monster and float(mo.get("stun_t",0))>0: node.rotation.z = sin(time*35+key)*0.025
			status_us += Time.get_ticks_usec() - tst
		var loop_us := Time.get_ticks_usec() - t_loop
		ArenaFrameBench.add("w_anim", anim_us)
		ArenaFrameBench.add("w_face", face_us)
		ArenaFrameBench.add("w_status", status_us)
		ArenaFrameBench.add("w_spawn", spawn_us)
		ArenaFrameBench.add("w_loop_other", loop_us - anim_us - face_us - status_us - spawn_us)
		t0 = Time.get_ticks_usec()
		for key in monster_nodes.keys():
			if keep.has(key): continue
			var node: Node3D = monster_nodes[key]
			if _dying.has(key) and node.has_method("advance_death"):
				var age := float(_dying[key]) + dt
				_dying[key] = age
				if age < 1.6 and not bool(node.call("advance_death", dt)): continue
			node.free()
			monster_nodes.erase(key)
			_monster_status.erase(key)
			_dying.erase(key)
		ArenaFrameBench.lap("w_cleanup", t0)
		t0 = Time.get_ticks_usec()
		vfx.sync(sim, time)
		ArenaFrameBench.lap("w_vfx_sync", t0)
		for i in range(crystals.size()): crystals[i].visible = i<lives
		t0 = Time.get_ticks_usec()
		update_effects(dt)
		ArenaFrameBench.lap("w_effects", t0)
		for crystal in crystals: crystal.visible = sim.crystal_hp > 0
		if is_instance_valid(_ward): _ward.visible = sim.shield > 0
		if is_instance_valid(_crystal_light):
			_crystal_light.light_energy = 0.35 + 0.75 * clampf(sim.crystal_hp / maxf(1, sim.crystal_max), 0, 1)
		ArenaFrameBench.lap("w_total", t_all)

class BenchView extends ArenaView:
	func attach(parent: CanvasItem, rect: Rect2) -> void:
		box = rect
		if viewport == null or not is_instance_valid(viewport):
			viewport = SubViewport.new()
			viewport.name = "Arena3DViewport"
			viewport.own_world_3d = true
			viewport.transparent_bg = false
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			viewport.msaa_3d = Viewport.MSAA_2X
			parent.add_child(viewport)
			world = BenchWorld.new()
			viewport.add_child(world)
		var wanted := Vector2i(maxi(64, int(rect.size.x)), maxi(64, int(rect.size.y)))
		if viewport.size != wanted:
			viewport.size = wanted
		_apply_camera(_follow_offset)
	func draw_arena(ci: CanvasItem, rect: Rect2, theme: Dictionary, sim, selected: int, dt: float) -> void:
		var t0 := Time.get_ticks_usec()
		super.draw_arena(ci, rect, theme, sim, selected, dt)
		ArenaFrameBench.lap("draw_arena", t0)

## ArenaScreen with a timer around the battle's step (ArenaScreen._step_battle: the selected
## hero's move and the simulator) and around the whole picture. The screen's own _process runs
## unchanged, so the bench never drifts from it.
class BenchScreen extends ArenaScreen:
	func _step_battle(sdt: float) -> void:
		var t0 := Time.get_ticks_usec()
		super._step_battle(sdt)
		ArenaFrameBench.lap("sim", t0)
	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		super._draw()
		ArenaFrameBench.lap("draw", t0)

## The screen's HUD view (ArenaHud, drawn from ArenaScreen._draw) with timers around the
## parts the table splits out: the monsters' bars, the minimap, the command rail and the
## top strip.
class BenchHud extends ArenaHud:
	func _draw_monster_bars() -> void:
		var t0 := Time.get_ticks_usec()
		super._draw_monster_bars()
		ArenaFrameBench.lap("hud_bars", t0)
	func _draw_minimap() -> void:
		var t0 := Time.get_ticks_usec()
		super._draw_minimap()
		ArenaFrameBench.lap("hud_minimap", t0)
	func _draw_controls() -> void:
		var t0 := Time.get_ticks_usec()
		super._draw_controls()
		ArenaFrameBench.lap("hud_controls", t0)
	func _draw_topbar(theme: Dictionary) -> void:
		var t0 := Time.get_ticks_usec()
		super._draw_topbar(theme)
		ArenaFrameBench.lap("hud_topbar", t0)

func _ready() -> void:
	if OS.get_environment("STELLARDEFENSE_NO_SAVE") != "1":
		printerr("STELLARDEFENSE_NO_SAVE=1로 실행하세요. 실제 기록을 보호합니다.")
		get_tree().quit(1)
		return
	stage = Harness.arg_int("--stage", 10)
	frames_total = Harness.arg_int("--frames", 2400)
	seed_value = Harness.arg_int("--seed", 20261017)
	Run.running = false
	Arena.running = false
	main = load("res://game/main.gd").new()
	add_child(main)

func _process(_dt: float) -> void:
	match state:
		0:
			if main.screen is TitleScreen and main._fade_dir == 0.0: state = 1
		1:
			Arena.start_run(seed_value)
			screen = BenchScreen.new()
			screen.view_3d = BenchView.new()
			screen.hud = BenchHud.new(screen)
			main._swap(screen)
			wait = 3
			state = 2
		2:
			wait -= 1
			if wait > 0: return
			Arena.confirm_stage()
			Arena.confirm_summon()
			Arena.close_modal()
			for unit in Roster.UNITS:
				if Arena.heroes.size() >= Balance.ARENA_HERO_LIMIT: break
				if String(unit["id"]) != String(Arena.heroes[0]["unit"]["id"]): Arena.gain_hero(unit, 1)
			if stage > 1:
				Arena.stage = stage
				Arena.wave = stage
				Arena.theme_index = Arena.stage_themes[stage - 1]
				ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(Arena.theme_index))
				Arena.sim.begin_stage(stage)
			var lanes := ArenaGeometry.route_count()
			for i in range(Arena.heroes.size()):
				var route := ArenaGeometry.route_points(i % lanes)
				var index := route.size() - 1 - 14 - 12 * (i / lanes)
				Arena.heroes[i]["position"] = route[clampi(index, 0, route.size() - 1)]
			Arena.sim.refresh_heroes()
			screen._load_stage_monsters()
			screen.speed = 3.0
			Arena.modal = ""
			Arena.phase = Arena.Phase.BATTLE
			us.clear()
			last_wall = Time.get_ticks_usec()
			frames = 0
			state = 3
		3:
			var now := Time.get_ticks_usec()
			var wall := (now - last_wall) / 1000.0
			last_wall = now
			var count: int = Arena.sim.monsters.size() if Arena.sim != null else 0
			if frames > 2:
				var bucket := (count / 8) * 8
				if not buckets.has(bucket): buckets[bucket] = {"n": 0, "wall": 0.0, "worst": 0.0, "draws": 0.0, "prims": 0.0, "bullets": 0.0}
				var row: Dictionary = buckets[bucket]
				row["n"] += 1
				row["wall"] += wall
				row["worst"] = maxf(float(row["worst"]), wall)
				row["draws"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				row["prims"] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				row["bullets"] += Arena.sim.bullets.size()
				for key in KEYS: row[key] = float(row.get(key, 0.0)) + float(us.get(key, 0)) / 1000.0
				if wall > worst_wall:
					worst_wall = wall
					worst_frame = frames
					worst_monsters = count
				if wall > 16.7: spikes += 1
			us.clear()
			frames += 1
			if Arena.modal == "talent" and not Arena.talent_offer.is_empty():
				Arena.pick_talent(String(Arena.talent_offer[0]))
			if Arena.modal == "result" or frames >= frames_total:
				state = 4
		4:
			_report()
			state = 5
			Arena.running = false
			get_tree().quit(0)

func _report() -> void:
	print("BENCH stage %d · %d frames · worst frame %.1f ms (frame %d, %d monsters) · frames over 16.7 ms: %d" % [stage, frames, worst_wall, worst_frame, worst_monsters, spikes])
	var header := "monsters frames   wall  worst  draws  ktris bullets"
	for key in KEYS: header += " %7s" % key.substr(0, 7)
	print(header)
	var keys := buckets.keys()
	keys.sort()
	for bucket in keys:
		var row: Dictionary = buckets[bucket]
		var n := maxf(1.0, float(row["n"]))
		var line := "%3d-%3d %6d %6.2f %6.1f %6.0f %6.0f %6.1f" % [bucket, bucket + 7, row["n"], row["wall"] / n, row["worst"], row["draws"] / n, row["prims"] / n / 1000.0, row["bullets"] / n]
		for key in KEYS: line += " %7.2f" % (float(row.get(key, 0.0)) / n)
		print(line)
