extends StellarView
class_name ArenaView

## HUD overlays the full world texture; follow and picking use the open field.
## Since the 2026-10-12 spiral field the camera frames the whole arena: it only nudges
## when the selected hero reaches the rim so a hero never sits under the HUD edges, and
## it keeps the complete crystal in view at all times.
var battle_box := Rect2(0, 70, 992, 730)
var minimap_box := Rect2(1006, 84, 130, 132)
var _follow_offset := Vector3.ZERO
var _camera_initialized := false
var _camera_sim = null
## Pixels the selected hero may approach the open box edges before the view nudges.
const EDGE_GUARD := Vector2(64, 48)
## Boss entrance emphasis. Anticipation: during the warning the view leans slowly toward
## the gate. Snap: the moment the boss steps in the view punches 8% closer around the gate
## with a short decaying shake. Settle: it eases back to the full-field framing.
## Ages advance with simulated time only, so pauses and modals freeze the move.
const BOSS_WARN_LEAN := 0.35
const BOSS_SPAWN_LEAN := 0.95
const BOSS_PUNCH := 1.08
const BOSS_SNAP := 0.12
const BOSS_HOLD := 0.55
const BOSS_SPAWN_LENGTH := 1.7
var _boss_phase := ""
var _boss_age := 0.0
var _boss_gate := Vector2.INF
## Impact micro-shake (2026-10-17). A short decaying wobble of the 3D camera, never the 2D
## HUD, for the moments that should be felt: a critical hit (tiny), a tank or boss falling,
## the meteor landing, the frost pulse, a blow on the crystal. Amplitudes are world units
## (0.1 u is under 4 px at 1280x800), a kick is never larger than IMPACT_MAX and kicks are
## spaced by IMPACT_GAP so a busy fight does not shake continuously. Ages advance with the
## simulated dt only, so pauses and modals freeze it like the boss camera.
const IMPACT_GAP := 0.28
const IMPACT_MAX := 0.20
const IMPACT_DECAY := 9.5
const IMPACT_FREQ := 41.0
const IMPACT_CRIT := 0.035
const IMPACT_TANK := 0.09
const IMPACT_BOSS := 0.18
const IMPACT_METEOR := 0.15
const IMPACT_FREEZE := 0.07
const IMPACT_LEAK := 0.06
var _impact := {"age": 9.0, "amp": 0.0, "dir": Vector3.RIGHT, "zoom": 0.0}
var _impact_gap := 0.0
var _impact_queue: Array[Dictionary] = []
## The battle frame (2026-10-18, casual overhaul WP-E): the picture is blitted by one
## ArenaFrame child of the screen — LINEAR filtered, behind every HUD draw, through the
## post pass art/models/arena_post.gdshader — instead of by this view on the screen
## itself (the project default Nearest stair-stepped the kerb and joints on a 1000x625
## phone). Vignette strength about the open box, sharpen (0 = off) and dither amount are
## the three levers; colour grading stays in the Environment. draw_arena() creates it on
## the screen it draws for, so the legacy StellarView/StellarBackdrop blits never get one.
## 0.33 measured 0.70-0.73x at the open box's corners against the raw picture (0.24 gave
## 0.78-0.80x and barely read as a frame; A/B in build/casual-overhaul/after/wp-e/).
const VIGNETTE := 0.33
const SHARPEN := 0.30
const DITHER := 1.0
var frame: ArenaFrame = null
## Damage numbers: 24 px, popping to 1.4x over the first 0.13 s, rising 30 px/s. Only the
## big ones (critical and weakness hits) unless Look.SHOW_ALL_DAMAGE.
const NUMBER_PX := 24
const NUMBER_POP := 0.4
const NUMBER_POP_SEC := 0.13

## Battery saver (O8a / M13, 2026-10-19). A view is in one of three states:
##   always  live, pace 1: renders every frame (UPDATE_ALWAYS) — the battle.
##   paced   live, pace N > 1: renders one frame in N, on every N-th tick() (UPDATE_ONCE in
##           between rests) — the title backdrop at pace 3, about 10 fps under the title's
##           30 fps cap: water and wind still breathe at a third of the GPU work.
##   frozen  not live: keeps its last picture (cards, boxes, maps, results, the shop, the menu).
## Freezing renders one more, up-to-date picture first (an aim ring or a hover of the last live
## frame must not stay behind the window), and while frozen draw_arena leaves the world alone
## unless something asked for a new picture: a new battlefield map, a resize, a new world,
## refresh_once(). ★ After UPDATE_ONCE the SubViewport's own property keeps reading UPDATE_ONCE
## (the server switches itself off), so the state is kept here: render_state().
var live := true
var pace := 1
var _pace_left := 0
## The update mode last asked of the viewport (-1: none yet / a new viewport), and the frame
## of the last one-shot ask: from the next frame on the viewport rests (UPDATE_DISABLED).
var _mode := -1
var _once_frame := -1
## Frames asked of the viewport one at a time, and world syncs, so far (checks count the
## battery saver's work with these).
var refreshes := 0
var syncs := 0
## The world owes one synced picture before it rests (freezing, refresh_once, a new map).
var _sync_due := false
## A world that could not be created is tried again at most this often (ms): never every
## frame, and never left empty for the rest of the session (F7).
const WORLD_RETRY_MS := 1000
var _world_retry_at := 0

func attach(parent: CanvasItem, rect: Rect2) -> void:
	box = rect
	_settle_mode()
	var fresh := false
	if viewport == null or not is_instance_valid(viewport):
		viewport = SubViewport.new()
		viewport.name = "Arena3DViewport"
		viewport.own_world_3d = true
		viewport.transparent_bg = false
		viewport.msaa_3d = Viewport.MSAA_2X
		parent.add_child(viewport)
		world = null
		_mode = -1
		fresh = true
	# ★ F7: the viewport can outlive its world (a world that failed to build, or one freed
	#   underneath). Building only together with a new viewport left such a view an empty
	#   picture forever; now the world is made again, at most once per WORLD_RETRY_MS.
	if (world == null or not is_instance_valid(world)) and Time.get_ticks_msec() >= _world_retry_at:
		# The next try is booked first: a script that cannot build (it failed to compile)
		# is skipped without an error, and anything that still fails aborts only this try.
		_world_retry_at = Time.get_ticks_msec() + WORLD_RETRY_MS
		var script: Script = ArenaWorld
		world = script.new() if script != null and script.can_instantiate() else null
		if world != null:
			viewport.add_child(world)
			fresh = true
	var wanted := Vector2i(maxi(64, int(rect.size.x)), maxi(64, int(rect.size.y)))
	if viewport.size != wanted:
		viewport.size = wanted
		fresh = true
	if fresh:
		_apply_update_mode(true)
	if world == null or not is_instance_valid(world):
		world = null
		return
	_apply_camera(_follow_offset)

## Live (always or paced) or frozen. Cheap to call every frame: nothing happens without a change.
func set_live(on: bool) -> void:
	if on == live:
		return
	live = on
	if on:
		_pace_left = pace
		_set_mode(SubViewport.UPDATE_ALWAYS if pace <= 1 else SubViewport.UPDATE_ONCE)
	else:
		# One last picture of the present (and a world brought up to date), then rest.
		_sync_due = true
		_set_mode(SubViewport.UPDATE_ONCE)

## Render one frame in `frames` while live (1 = every frame).
func set_pace(frames: int) -> void:
	pace = maxi(1, frames)
	_pace_left = pace
	if live:
		_set_mode(SubViewport.UPDATE_ALWAYS if pace <= 1 else SubViewport.UPDATE_ONCE)

## A paced live view's clock: call once per drawn frame; every pace-th call renders a frame.
func tick() -> void:
	if not live or pace <= 1:
		return
	_pace_left -= 1
	if _pace_left <= 0:
		_pace_left = pace
		_set_mode(SubViewport.UPDATE_ONCE)

## Render one new, up-to-date frame now (a new battlefield behind its card, a resolution
## change, a camera move) on a frozen or paced view; the engine rests the viewport again after
## it. A view rendering every frame needs nothing.
func refresh_once() -> void:
	if live and pace <= 1:
		return
	_sync_due = true
	_set_mode(SubViewport.UPDATE_ONCE)

## "always", "paced" or "frozen" (the SubViewport's own property cannot tell: see above).
func render_state() -> String:
	return "always" if live and pace <= 1 else "paced" if live else "frozen"

## Whether the world exists and holds a built battlefield (the boot loading screen waits on
## it; tests/title_return_check asks it).
func is_built() -> bool:
	return world != null and is_instance_valid(world) and world.terrain.get_child_count() > 0

func _apply_update_mode(redraw: bool) -> void:
	if live and pace <= 1:
		_set_mode(SubViewport.UPDATE_ALWAYS)
	elif redraw:
		_pace_left = pace
		refresh_once()

func _set_mode(mode: int) -> void:
	if viewport == null or not is_instance_valid(viewport):
		return
	# UPDATE_ONCE is asked again each time: every ask renders one more frame.
	if mode == _mode and mode != SubViewport.UPDATE_ONCE:
		return
	_mode = mode
	viewport.render_target_update_mode = mode
	if mode == SubViewport.UPDATE_ONCE:
		_once_frame = Engine.get_process_frames()
		refreshes += 1

## The frame after a one-shot render the server has already switched the viewport off; say so
## on the node too, so whoever reads the property (ArenaWorld counts drawn frames by it) sees
## a resting viewport instead of a stale UPDATE_ONCE.
func _settle_mode() -> void:
	if _mode == SubViewport.UPDATE_ONCE and Engine.get_process_frames() > _once_frame:
		_set_mode(SubViewport.UPDATE_DISABLED)

## The frame node under `parent`, created once (ArenaScreen asks for it in _ready so the
## night is painted under the field from the first frame; draw_arena keeps it fed).
func frame_for(parent: CanvasItem) -> ArenaFrame:
	if frame == null or not is_instance_valid(frame):
		frame = ArenaFrame.new()
		frame.set_post(&"vignette", VIGNETTE)
		frame.set_post(&"vignette_color", Look.BG_DEEP)
		frame.set_post(&"sharpen", SHARPEN)
		frame.set_post(&"dither", DITHER)
		parent.add_child(frame)
	return frame

func _active_box() -> Rect2:
	return battle_box.intersection(box)

func _apply_camera(offset: Vector3) -> void:
	var emphasis := boss_camera()
	var kick := impact_camera()
	world.camera_punch = float(emphasis["punch"]) * float(kick["punch"])
	world.camera_target = offset + Vector3(emphasis["shift"]) + Vector3(kick["shift"])
	world.camera_update()
	# Center the fixed orthographic view in the open area left of the command rail.
	var center := box.get_center()
	var focus := _active_box().get_center()
	var a := world.ground_at(center - box.position)
	var b := world.ground_at(focus - box.position)
	world.camera.position += Vector3((a.x - b.x) / StellarWorld.UNIT, 0,
		(a.y - b.y) / StellarWorld.UNIT)

func _ground_shift(from: Vector2, to: Vector2) -> Vector3:
	var a := world.ground_at(from - box.position)
	var b := world.ground_at(to - box.position)
	return Vector3((a.x - b.x) / StellarWorld.UNIT, 0, (a.y - b.y) / StellarWorld.UNIT)

func _keep_crystal_visible(offset: Vector3) -> Vector3:
	_apply_camera(offset)
	var safe := _active_box().grow(-28)
	# Preserve the complete crystal, including its point and the altar's base.
	for height in [0.08, 1.95]:
		var pixel := project(Balance.ARENA_CENTER, height)
		var target := pixel.clamp(safe.position, safe.end)
		offset += _ground_shift(pixel, target)
		_apply_camera(offset)
	# A crystal at the upper right must not disappear underneath the minimap.
	var crystal := project(Balance.ARENA_CENTER, 1.0)
	var obstacle := minimap_box.grow(30)
	if obstacle.has_point(crystal):
		var left := Vector2(obstacle.position.x, crystal.y)
		var below := Vector2(crystal.x, obstacle.end.y)
		var target := left if crystal.distance_squared_to(left) < crystal.distance_squared_to(below) else below
		offset += _ground_shift(crystal, target)
	return offset

func follow_selected(at: Vector2, dt: float) -> void:
	if world == null or not at.is_finite(): return
	_apply_camera(_follow_offset)
	if _camera_initialized and dt <= 0.0: return
	# The whole field is framed, so the hero only pulls the view when it reaches the
	# rim next to a HUD edge; the nudge is measured from the centred framing, so the
	# view eases back to it as soon as the hero leaves the rim.
	var active := _active_box()
	var guard := Rect2(active.position + EDGE_GUARD, active.size - EDGE_GUARD * 2)
	_apply_camera(Vector3.ZERO)
	var pixel := project(at, 0.5)
	var desired := _ground_shift(pixel, pixel.clamp(guard.position, guard.end))
	desired = _keep_crystal_visible(desired)
	var weight := 1.0 if not _camera_initialized else 1.0 - exp(-8.0 * minf(dt, 0.25))
	_follow_offset = _keep_crystal_visible(_follow_offset.lerp(desired, weight))
	_camera_initialized = true
	_apply_camera(_follow_offset)

## Start the boss entrance camera: "warn" at the four-second warning, "spawn" when the
## boss steps onto the field. `gate` is the logical point where it appears.
func boss_event(phase: String, gate: Vector2) -> void:
	if phase not in ["warn", "spawn"]: return
	_boss_phase = phase
	_boss_age = 0.0
	if gate.is_finite(): _boss_gate = gate

func boss_advance(dt: float) -> void:
	if _boss_phase.is_empty() or dt <= 0.0: return
	_boss_age += dt
	if _boss_phase == "spawn" and _boss_age >= BOSS_SPAWN_LENGTH:
		_boss_phase = ""
		_boss_age = 0.0

func boss_emphasis() -> Dictionary:
	return {"phase": _boss_phase, "age": _boss_age, "gate": _boss_gate}

## Camera lean (world units) and zoom punch for the current boss entrance moment.
func boss_camera() -> Dictionary:
	if _boss_phase.is_empty() or not _boss_gate.is_finite():
		return {"shift": Vector3.ZERO, "punch": 1.0}
	var toward := StellarWorld.world(_boss_gate) - StellarWorld.world(Balance.ARENA_CENTER)
	toward.y = 0.0
	if toward.length_squared() < 0.0001: return {"shift": Vector3.ZERO, "punch": 1.0}
	toward = toward.normalized()
	if _boss_phase == "warn":
		var lean := BOSS_WARN_LEAN * smoothstep(0.0, Balance.ARENA_BOSS_WARNING, _boss_age)
		return {"shift": toward * lean, "punch": 1.0}
	var age := _boss_age
	var hit := 1.0 - pow(1.0 - clampf(age / BOSS_SNAP, 0.0, 1.0), 3.0)
	var settle := smoothstep(BOSS_HOLD, BOSS_SPAWN_LENGTH, age)
	var lean := lerpf(BOSS_WARN_LEAN, BOSS_SPAWN_LEAN, hit) * (1.0 - settle)
	var side := Vector3(-toward.z, 0, toward.x)
	var decay := exp(-age * 5.5)
	var shake := (side * sin(age * 47.0) * 0.6 + toward * sin(age * 31.0 + 0.9) * 0.4) * 0.13 * decay
	return {"shift": toward * lean + shake, "punch": 1.0 + (BOSS_PUNCH - 1.0) * hit * (1.0 - settle)}

## Kick the camera: `amount` world units, away from the logical point `from` (a random
## sideways direction without one), `zoom` a brief orthographic punch (0.02 = 2%).
## Rate-limited; a stronger kick during the gap replaces the running one.
func impact(amount: float, from: Vector2 = Vector2.INF, zoom: float = 0.0) -> void:
	amount = minf(amount, IMPACT_MAX)
	if amount <= 0.0: return
	if _impact_gap > 0.0 and amount <= float(_impact["amp"]) * exp(-float(_impact["age"]) * IMPACT_DECAY): return
	var dir := Vector3(1, 0, 0.6).normalized()
	if from.is_finite():
		var away := StellarWorld.world(from) - StellarWorld.world(Balance.ARENA_CENTER)
		away.y = 0.0
		if away.length_squared() > 0.01: dir = away.normalized()
	_impact = {"age": 0.0, "amp": amount, "dir": dir, "zoom": zoom}
	_impact_gap = IMPACT_GAP

## A kick that waits on the simulated clock (the meteor lands BLAST_FALL after its cast).
func impact_later(delay: float, amount: float, from: Vector2 = Vector2.INF, zoom: float = 0.0) -> void:
	_impact_queue.append({"t": delay, "amount": amount, "from": from, "zoom": zoom})

func impact_advance(dt: float) -> void:
	if dt <= 0.0: return
	_impact["age"] = float(_impact["age"]) + dt
	_impact_gap = maxf(0.0, _impact_gap - dt)
	for i in range(_impact_queue.size() - 1, -1, -1):
		var queued: Dictionary = _impact_queue[i]
		queued["t"] = float(queued["t"]) - dt
		if float(queued["t"]) <= 0.0:
			_impact_queue.remove_at(i)
			impact(float(queued["amount"]), queued["from"], float(queued["zoom"]))

## Camera shift (world units) and zoom punch of the running impact kick: a decaying
## wobble, mostly along the kick direction, a little across it.
func impact_camera() -> Dictionary:
	var age := float(_impact["age"])
	var amp := float(_impact["amp"])
	if amp <= 0.0 or age > 0.6: return {"shift": Vector3.ZERO, "punch": 1.0}
	var decay := exp(-age * IMPACT_DECAY)
	var dir: Vector3 = _impact["dir"]
	var side := Vector3(-dir.z, 0, dir.x)
	var shift := (dir * sin(age * IMPACT_FREQ) + side * sin(age * IMPACT_FREQ * 0.63 + 1.1) * 0.45) * amp * decay
	return {"shift": shift, "punch": 1.0 + float(_impact["zoom"]) * decay}

## Which events kick the camera, and how hard.
func impact_event(e: Dictionary) -> void:
	match String(e.get("t", "")):
		"hit":
			if bool(e.get("crit", false)) and float(e.get("em", 1.0)) > 0.0: impact(IMPACT_CRIT, e.get("p", Vector2.INF))
		"die":
			if bool(e.get("scatter", false)): return
			var h := float(e.get("h", 52.0))
			if h >= 120.0: impact(IMPACT_BOSS, e.get("p", Vector2.INF), 0.02)
			elif h >= 66.0: impact(IMPACT_TANK, e.get("p", Vector2.INF))
		"arena_blast":
			impact_later(StellarVfx.BLAST_FALL, IMPACT_METEOR, e.get("p", Vector2.INF), 0.02)
		"arena_freeze":
			impact(IMPACT_FREEZE, Vector2.INF)
		"arena_crystal_hit":
			if float(e.get("n", 0.0)) > 0.0: impact(IMPACT_LEAK, Vector2.INF)

func minimap_bounds() -> Rect2:
	return ArenaGeometry.MAP_RECT

func minimap_point(point: Vector2, rect: Rect2) -> Vector2:
	var bounds := minimap_bounds()
	return rect.position + ((point - bounds.position) / bounds.size).clamp(Vector2.ZERO, Vector2.ONE) * rect.size

func camera_ground_polygon() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if world == null: return polygon
	for point in ArenaGeometry.corners(_active_box()):
		polygon.append(world.ground_at(point - box.position))
	return polygon

func minimap_footprint(rect: Rect2) -> PackedVector2Array:
	if world == null: return PackedVector2Array()
	# Clip the actual oblique footprint before scaling, rather than clamping each
	# corner (which would distort the view area when it straddles the map edge).
	var clipped := Geometry2D.intersect_polygons(camera_ground_polygon(), ArenaGeometry.outline())
	var polygon := PackedVector2Array()
	if clipped.is_empty(): return polygon
	for point in clipped[0]: polygon.append(minimap_point(point, rect))
	return polygon

func draw_arena(ci: CanvasItem, rect: Rect2, theme: Dictionary, sim, selected: int, dt: float) -> void:
	attach(ci, rect)
	if world == null: return
	var map_before := String(world._map_key)
	world.build_map(theme)
	# A new battlefield, or a new run on the same one (a retry), behind its card while the view
	# is frozen: show it once, actors and all.
	if String(world._map_key) != map_before or sim != _camera_sim: refresh_once()
	# Frozen with no time passing (a window over the battle): the world keeps the picture it
	# was frozen with — no actor sync, no camera follow — until something asks for a new one.
	if live or dt > 0.0 or _sync_due:
		_sync_due = false
		_sync_battle(sim, selected, dt)
	_present(ci, rect, sim)

## Bring the world up to the simulator: events, actors, selection ring and camera follow.
func _sync_battle(sim, selected: int, dt: float) -> void:
	syncs += 1
	world.actors.visible = sim != null
	world.projectiles.visible = sim != null
	_hero_hits.clear()
	if sim != _camera_sim:
		_camera_sim = sim
		_camera_initialized = false
		_follow_offset = Vector3.ZERO
		_boss_phase = ""
		_boss_age = 0.0
		_impact = {"age": 9.0, "amp": 0.0, "dir": Vector3.RIGHT, "zoom": 0.0}
		_impact_queue.clear()
		_impact_gap = 0.0
	if sim != null:
		for hero in sim.heroes:
			hero["fx_t"] = float(hero.get("fx_t", 9.0)) + dt
		for e in sim.events:
			if String(e.get("t", "")) == "aim":
				var source := int(e.get("src", -1))
				if source >= 0 and source < sim.heroes.size():
					var hero: Dictionary = sim.heroes[source]
					hero["fx_t"] = 0.0
					hero["fx_w"] = float(e.get("w", 0.0))
					hero["fx_d"] = e.get("d", Vector2.DOWN)
			if String(e.get("t", "")) == "fire":
				Sfx.play(Sfx.shot_id(String(e.get("el", "none")), String(e.get("kind", "shot"))), -6.0, 1.0, 0.07)
			if String(e.get("t", "")) == "arena_boss_warning":
				boss_event("warn", Vector2(e.get("p", sim.boss_gate())))
			if String(e.get("t", "")) == "arena_boss":
				Sfx.play("boss")
				boss_event("spawn", Vector2(e.get("p", sim.boss_gate())))
			impact_event(e)
			world.event(e)
		sim.events.clear()
		boss_advance(dt)
		impact_advance(dt)
		world.sync_battle(sim, sim.elapsed, 1, dt)
		var at := Vector2.INF
		var radius := 0.0
		for i in range(sim.heroes.size()):
			var data: Dictionary = sim.heroes[i]
			_hero_hits.append({"index": i, "post": i, "at": data["pos"]})
			if i == selected:
				at = data["pos"]
				radius = float(data.get("range", 0.0))
		world.set_selection(at, false, radius)
		if at.is_finite(): follow_selected(at, dt)
		else: _apply_camera(_follow_offset)
	else:
		world.set_selection(Vector2.INF, false)
		_apply_camera(Vector3.ZERO)

## Blit the picture and draw the big damage numbers over it.
func _present(ci: CanvasItem, rect: Rect2, sim) -> void:
	# The picture goes through the frame node (behind this draw); the vignette is told
	# where the open battle box is, so the sidebar and the top strip stay untouched.
	var blit := frame_for(ci)
	var open := _active_box()
	blit.set_post(&"frame_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	blit.set_post(&"box_center", open.get_center())
	blit.set_post(&"box_size", open.size)
	blit.present(viewport.get_texture(), rect)
	if sim == null: return
	for item in world.texts:
		# Plain chip damage is read from the bar, the flash and the squash; a number is
		# for the hits that matter (`big`: critical or weakness, flagged by the world).
		if not (bool(item["big"]) or Look.SHOW_ALL_DAMAGE): continue
		var age := float(item["age"])
		var at := project(item["p"], 1.1) + Vector2(0, -age * 30)
		if not rect.grow(-12).has_point(at): continue
		var color: Color = item["color"]
		color.a = clampf(1.5 - age * 2, 0, 1)
		var size := int(NUMBER_PX * (1.0 + NUMBER_POP * (1.0 - smoothstep(0.0, NUMBER_POP_SEC, age))))
		Look.text_center_out(ci, at, Fx._short_num(float(item["n"])), size, color, Look.BG_DEEP, 2.0)

func camera_input(_e: InputEvent) -> bool:
	return false

func camera_button(_id: String) -> bool:
	return false
