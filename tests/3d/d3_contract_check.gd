extends Harness

## D3 (feedback 2026-10-19) headless contracts of the 3D battlefield pieces:
##   - the selection ring is one quad: a new range is two uniforms, never new nodes
##   - set_aim(at, radius, valid, shown) poses one quad; a cast hands over (lock) and it goes
##   - the warm bodies are hidden (not freed) after the warm frames
##   - build_map writes its key only after a whole build (F7)
##   - arena_wave / arena_wave_clear / arena_elite reach StellarVfx (a sequence is born)
##   - arena_blast raises the gust at the impact, not at the cast
##   - an `elite` monster is dressed (1.35x, aura, violet hull on the instance only)
##   - authored glow (ember_imp's crown) gets its own dithered override that fades with the
##     body and that a hit flash never writes (X1)
##   - a revival's guardian is held hidden until its arrival, then shown, and its star lands
##     on it; a bench guardian's crown plays over the crystal; a guardian already standing
##     (raised to the top grade) is never hidden (LA3)
##   - the next revival's candidate (ArenaRun.revive_candidate through sim.run) is loaded and
##     buried for the warm frames only while a revival can still come; one never granted is
##     let go when the stage changes; build_map alone (a frozen card skips the sync) loads it
##   - a guardian nobody could load ahead is read on a loader thread: no body (and no shots)
##     until it is ready, then held, then shown when its star lands
##   - a frozen view (UPDATE_ONCE left on its node) never counts as drawn for the warm frames
##   - on a window smaller than the picture the ring strokes are drawn wider (screen_k)
##   - a frozen window that skips the battle's sync (ArenaView, LB2) breaks nothing: events
##     still land, the sequences wait on the paused clock and finish after; the aim ring
##     fades on its own; a revival's guardian is held and arrives after the window
##   STELLARDEFENSE_NO_SAVE=1 godot --headless --path . res://tests/3d/d3_contract_check.tscn

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
	var run = null
	func final_stage() -> bool:
		return false

## The run as _keep_revival reads it through sim.run (ArenaRun's names).
class RunStandIn extends RefCounted:
	var run_seed := 20261019
	var stage := 1
	var unit: Dictionary = {}
	var left := 3
	var party: Array = []
	func revive_candidate() -> Dictionary:
		return unit
	func revives_left() -> int:
		return left
	func find_hero(id: String) -> Array:
		return ["field", 0] if party.has(id) else ["", -1]

var world: ArenaWorld
var sim: StandIn

func _ready() -> void:
	if not require_no_save(): return
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(0))
	world = ArenaWorld.new()
	add_child(world)
	world.build_map(Roster.THEMES[0])
	sim = StandIn.new()
	await frames(2)
	_check_warm()
	_check_map_key()
	_check_selection()
	await _check_aim()
	_check_events()
	_check_gust()
	_check_elite()
	_check_glow()
	await _check_arrival()
	_check_bench_arrival()
	_check_raised_guardian()
	_check_revival_warm()
	await _check_loading_guardian()
	await _check_frozen_and_scaled()
	await _check_skipped_sync()
	_check_card_preload()
	world.queue_free()
	await frames(2)
	finish("D3 battlefield contracts")

func _tick(dt: float = 1.0 / 30.0) -> void:
	sim.elapsed += dt
	world.sync_battle(sim, sim.elapsed, 1, dt)

func _check_warm() -> void:
	# Headless: the root window renders every frame, so the warm frames pass at once.
	for n in range(6): world._process(0.016)
	var nodes: Array = world.get("_warm_nodes")
	check(nodes.size() >= 2, "warm bodies exist (a hero and a monster)")
	var hidden := true
	for node in nodes: hidden = hidden and is_instance_valid(node) and not (node as Node3D).visible
	check(hidden, "warm bodies are hidden after the warm frames, not freed")

func _check_map_key() -> void:
	check(String(world.get("_map_key")) == "calm_lake|" + ArenaGeometry.layout(), "build_map records its key after the build")
	var children := world.terrain.get_child_count()
	world.build_map(Roster.THEMES[0])
	check(world.terrain.get_child_count() == children, "the same field is not built twice")

func _check_selection() -> void:
	var ring: MeshInstance3D = world.get("_ring")
	var count := world.selection.get_child_count()
	world.set_selection(Balance.ARENA_CENTER + Vector2(100, 0), false, 320.0)
	var material: ShaderMaterial = ring.material_override
	check(ring.visible and is_equal_approx(float(material.get_shader_parameter("radius")), 320.0 / StellarWorld.UNIT), "the ring takes the bow's reach")
	world.set_selection(Balance.ARENA_CENTER + Vector2(-120, 40), false, 60.0)
	check(is_equal_approx(float(material.get_shader_parameter("radius")), 60.0 / StellarWorld.UNIT), "the ring takes the sword's reach")
	check(world.selection.get_child_count() == count and ring.material_override == material, "a new reach rebuilds nothing (same node, same material)")
	check(int(material.get_shader_parameter("dashes")) % 2 == 0 and float(material.get_shader_parameter("dashes")) >= 12.0, "whole even dash count")
	world.set_selection(Vector2.INF, false)
	check(not ring.visible, "no selection hides the ring")

func _check_aim() -> void:
	var aim: MeshInstance3D = world.get("_aim")
	var spot: Vector2 = Balance.ARENA_CENTER + Vector2(-150, 90)
	world.set_aim(spot, 160.0, true, true)
	var material: ShaderMaterial = aim.material_override
	check(aim.visible and int(material.get_shader_parameter("mode")) == 1, "a valid aim is the gold mode")
	check(is_equal_approx(float(material.get_shader_parameter("radius")), 160.0 / StellarWorld.UNIT), "the aim ring is the damage radius")
	world.set_aim(spot + Vector2(900, 0), 160.0, false, true)
	check(int(material.get_shader_parameter("mode")) == 2, "an invalid aim is the red-grey mode")
	world.set_aim(spot, 160.0, true, true)
	world.set_aim(spot, 160.0, true, false)
	world.event({"t": "arena_blast", "p": spot, "r": 160.0})
	check(aim.visible and float(world.get("_aim_state")["locked"]) > 0.0, "the cast locks the aim on (hand-over to the sigil)")
	await get_tree().create_timer(0.4).timeout
	await frames(2)
	check(not aim.visible, "the aim ring is gone after the hand-over")

func _check_events() -> void:
	var vfx: StellarVfx = world.vfx
	vfx._clear_field()
	world.event({"t": "arena_wave", "wave": 3, "total": 10, "elite": false, "boss": false})
	check(_count(vfx, "moment") >= ArenaGeometry.route_count() and (vfx.get_node("Roads") as MeshInstance3D).visible, "arena_wave flares every gate and sends runners")
	vfx._clear_field()
	world.event({"t": "arena_wave_clear", "wave": 3, "gold": 40, "prep": 8.0})
	check(_count(vfx, "moment") == 1, "arena_wave_clear sweeps the field")
	vfx._clear_field()
	world.event({"t": "arena_elite", "p": Balance.ARENA_CENTER + Vector2(300, 0), "sid": 7})
	check(_count(vfx, "skill") == 1, "arena_elite plays the elite entrance")
	vfx._clear_field()
	# The defence's heal arrives as arena_heal just before arena_wave_clear: one sequence shows both.
	world.event({"t": "arena_heal", "p": Balance.ARENA_CENTER, "n": 120.0})
	world.event({"t": "arena_wave_clear", "wave": 4, "gold": 40, "prep": 8.0, "heal": 120.0})
	_tick(0.0)
	check(_count(vfx, "moment") == 1, "a wave clear shows its own heal (no second mend)")
	vfx._clear_field()
	world.event({"t": "arena_heal", "p": Balance.ARENA_CENTER, "n": 120.0})
	_tick(0.0)
	check(_count(vfx, "moment") == 1, "a heal on its own plays the mend")
	vfx._clear_field()

func _count(vfx: StellarVfx, pool: String) -> int:
	var n := 0
	for fx in vfx.effects:
		if typeof(fx) == TYPE_DICTIONARY and String(fx.get("vfx", "")) == pool: n += 1
	return n

func _check_gust() -> void:
	world.set("_wind_pulse", 0.0)
	(world.get("_wind_due") as Array).clear()
	world.event({"t": "arena_blast", "p": Balance.ARENA_CENTER, "r": 110.0})
	check(is_zero_approx(float(world.get("_wind_pulse"))), "no gust at the cast")
	for n in range(6): _tick(1.0 / 30.0)
	check(is_zero_approx(float(world.get("_wind_pulse"))), "no gust while the star falls")
	for n in range(6): _tick(1.0 / 30.0)
	check(float(world.get("_wind_pulse")) > 0.3, "the gust arrives with the impact (%.2f)" % float(world.get("_wind_pulse")))
	world.vfx._clear_field()

func _check_elite() -> void:
	var data := Roster.monster_by_id("frost_imp")
	sim.monsters = [{"spawn_id": 41, "m": data, "pos": Balance.ARENA_CENTER + Vector2(260, 0), "vel": Vector2.ZERO, "hp": 10.0,
		"max": 10.0, "flash": 0.0, "motion_t": 0.0, "motion_phase": 0.0, "elite": true},
		{"spawn_id": 42, "m": data, "pos": Balance.ARENA_CENTER + Vector2(300, 0), "vel": Vector2.ZERO, "hp": 10.0,
		"max": 10.0, "flash": 0.0, "motion_t": 0.0, "motion_phase": 0.0}]
	_tick(0.0)
	var elite: Node3D = world.monster_nodes.get(41)
	var plain: Node3D = world.monster_nodes.get(42)
	check(elite != null and is_equal_approx(elite.scale.x, StellarModels.ELITE_SCALE), "the elite stands 1.35x")
	check(plain != null and is_equal_approx(plain.scale.x, 1.0), "its ordinary kin keeps its size")
	check(elite != null and elite.has_meta(StellarShading.META_AURA) and is_instance_valid(elite.get_meta(StellarShading.META_AURA)), "the elite wears its aura")
	check(elite != null and not (elite.get_meta(StellarShading.META_OUTLINE_NODES, []) as Array).is_empty(), "the elite has its hull")
	check(plain != null and (plain.get_meta(StellarShading.META_OUTLINE_NODES, []) as Array).is_empty(), "the hull stays on the elite instance only")
	sim.monsters.clear()
	_tick(0.0)

func _check_glow() -> void:
	var imp := StellarModels.monster(Roster.monster_by_id("ember_imp"))
	add_child(imp)
	var glows: Array = imp.get_meta(StellarShading.META_GLOW, [])
	check(not glows.is_empty(), "ember_imp's authored glow has its own instance override")
	if not glows.is_empty():
		var glow: StandardMaterial3D = glows[0]
		var energy := glow.emission_energy_multiplier
		var colour := glow.emission
		StellarShading.set_hit_flash(imp, 1.0)
		check(is_equal_approx(glow.emission_energy_multiplier, energy) and glow.emission.is_equal_approx(colour), "a hit flash never writes the glow")
		StellarShading.set_hit_flash(imp, 0.0)
		check(glow.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER, "the glow dithers like the skin")
		StellarShading.set_dissolve(imp, 1.0)
		check(glow.distance_fade_min_distance > StellarShading.DITHER_CENTRE, "a finished dissolve takes the glow away")
		StellarShading.set_dissolve(imp, 0.0)
		check(glow.distance_fade_max_distance < StellarShading.DITHER_CENTRE, "a whole body keeps its glow whole")
	imp.queue_free()

func _check_arrival() -> void:
	var unit := Roster.unit_by_id("solana")
	# Its model is ready (the candidate kept under the card): the body is built at once and held.
	# An unread one goes through the loader thread first (_check_loading_guardian).
	StellarModels.hero(unit, 9).free()
	sim.heroes = [{"h": {"unit": unit, "tier": 9}, "pos": Balance.ARENA_CENTER + Vector2(140, 80), "range": 200.0,
		"fx_t": 9.0, "fx_w": 0.35, "fx_d": Vector2.DOWN}]
	world.event({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS, "sec": 5.0, "stun": 2.5,
		"left": 0, "unit": "solana", "tier": 9, "where": "field"})
	_tick(1.0 / 30.0)
	var node: Node3D = world.hero_node(0)
	check(node != null and not node.visible, "the granted guardian is held out of sight at first")
	var landed: Array = []
	for n in range(48):
		_tick(1.0 / 30.0)
		if landed.is_empty(): landed = _arrivals(world.vfx)
	node = world.hero_node(0)
	check(node != null and node.visible, "it is shown after its arrival")
	var spot := StellarWorld.world(sim.heroes[0]["pos"], 0.0)
	check(landed.size() == 1 and is_equal_approx(float(landed[0]["mode"]), 1.0) and Vector2(landed[0]["at"].x - spot.x, landed[0]["at"].z - spot.z).length() < 0.05,
		"its star lands on its own spot (%s)" % str(landed))
	sim.heroes.clear()
	_tick(0.0)
	world.vfx._clear_field()

## The five-star arrivals playing now: where (world) and mode (1 field, 2 bench).
func _arrivals(vfx: StellarVfx) -> Array:
	var out: Array = []
	for fx in vfx.effects:
		if typeof(fx) != TYPE_DICTIONARY or String(fx.get("vfx", "")) != "skill": continue
		var custom: Color = fx["custom"]
		if int(round(custom.a)) != StellarVfx.SkillKind.HERO_ARRIVE: continue
		out.append({"at": fx.get("at", Vector3.INF), "mode": custom.b})
	return out

func _check_bench_arrival() -> void:
	world.event({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS, "sec": 5.0, "stun": 2.5,
		"left": 1, "unit": "kari", "tier": 9, "where": "bench"})
	var landed: Array = []
	for n in range(36):
		_tick(1.0 / 30.0)
		if landed.is_empty(): landed = _arrivals(world.vfx)
	var crystal := StellarWorld.world(Balance.ARENA_CENTER, 0.0)
	check(landed.size() == 1 and is_equal_approx(float(landed[0]["mode"]), 2.0) and Vector2(landed[0]["at"].x - crystal.x, landed[0]["at"].z - crystal.z).length() < 0.05,
		"a bench guardian's crown plays over the crystal (%s)" % str(landed))
	check(world.held_slots().is_empty(), "nothing is held for the bench")
	world.event({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS, "sec": 5.0, "stun": 2.5,
		"left": 0, "unit": "", "tier": -1, "where": ""})
	world.vfx._clear_field()
	for n in range(36): _tick(1.0 / 30.0)
	check(_arrivals(world.vfx).is_empty(), "a revival that brings nobody plays no arrival")
	world.vfx._clear_field()

## Everyone was here: the revival raised a standing guardian to the top grade (ArenaRun
## grant_revive_hero). Its body stays; the star lands on it.
func _check_raised_guardian() -> void:
	var unit := Roster.unit_by_id("jokull")
	sim.heroes = [{"h": {"unit": unit, "tier": 4}, "pos": Balance.ARENA_CENTER + Vector2(-150, 60), "range": 200.0,
		"fx_t": 9.0, "fx_w": 0.35, "fx_d": Vector2.DOWN}]
	_tick(1.0 / 30.0)
	sim.heroes[0]["h"]["tier"] = 9
	world.event({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS, "sec": 5.0, "stun": 2.5,
		"left": 0, "unit": "jokull", "tier": 9, "where": "field"})
	var hidden := false
	var landed: Array = []
	for n in range(48):
		_tick(1.0 / 30.0)
		var node: Node3D = world.hero_node(0)
		if node == null or not node.visible: hidden = true
		if landed.is_empty(): landed = _arrivals(world.vfx)
	check(not hidden and world.held_slots().is_empty(), "a raised guardian is never hidden")
	check(landed.size() == 1 and is_equal_approx(float(landed[0]["mode"]), 1.0), "its star still lands on it")
	check(world.hero_node(0) != null and int(world.hero_node(0).get_meta("grade", -1)) == 9, "it wears the top grade")
	sim.heroes.clear()
	_tick(0.0)
	world.vfx._clear_field()

func _check_revival_warm() -> void:
	var first := Roster.unit_by_id("pip")
	var second := Roster.unit_by_id("brasa")
	StellarModels.forget_hero(first, Balance.TIER_MAX)
	StellarModels.forget_hero(second, Balance.TIER_MAX)
	var run := RunStandIn.new()
	run.unit = first
	run.left = 0
	sim.run = run
	_tick(0.0)
	check(not StellarModels.has_hero(first, Balance.TIER_MAX) and world.get("_revival_body") == null, "no revival to come: nothing is loaded")
	run.left = 3
	var t0 := Time.get_ticks_usec()
	_tick(0.0)
	var cold := (Time.get_ticks_usec() - t0) / 1000.0
	var body: Node3D = world.get("_revival_body")
	check(StellarModels.has_hero(first, Balance.TIER_MAX), "the next revival's guardian is loaded (card up)")
	check(body != null and body.visible and body.position.y < -10.0 and int(body.get_meta("grade", -1)) == Balance.TIER_MAX, "its top-grade body stands buried for the warm frames")
	_tick(0.0)
	check(world.get("_revival_body") == body, "the same stage loads nothing more")
	for n in range(6): world._process(0.016)
	check(is_instance_valid(body) and not body.visible, "then it is hidden, not freed")
	t0 = Time.get_ticks_usec()
	var again := StellarModels.hero(first, Balance.TIER_MAX)
	var warm := (Time.get_ticks_usec() - t0) / 1000.0
	again.free()
	print("  revival candidate %s: first sync %.1f ms (load, style, pack), afterwards hero() %.2f ms" % [String(first["id"]), cold, warm])
	check(warm < cold, "the arrival then only instantiates")
	run.stage = 2
	run.unit = second
	_tick(0.0)
	check(not StellarModels.has_hero(first, Balance.TIER_MAX) and StellarModels.has_hero(second, Balance.TIER_MAX), "a candidate never granted is let go; the next stage's is loaded")
	run.stage = 3
	run.party = [String(second["id"])]
	run.unit = first
	_tick(0.0)
	check(StellarModels.has_hero(second, Balance.TIER_MAX), "a candidate that joined stays loaded")
	sim.run = null

## A field guardian whose model nobody loaded ahead (the candidate was already in the party).
func _check_loading_guardian() -> void:
	var unit: Dictionary = {}
	for candidate in Roster.UNITS:
		var path := StellarModels.hero_source(candidate)
		if path != "" and not ResourceLoader.has_cached(path) and not StellarModels.has_hero(candidate, Balance.TIER_MAX):
			unit = candidate
			break
	check(not unit.is_empty(), "a hero with an unread model exists for the loading check")
	if unit.is_empty(): return
	var id := String(unit["id"])
	sim.heroes = [{"h": {"unit": unit, "tier": 9}, "pos": Balance.ARENA_CENTER + Vector2(-130, -90), "range": 200.0,
		"fx_t": 9.0, "fx_w": 0.35, "fx_d": Vector2.DOWN}]
	world.event({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS, "sec": 5.0, "stun": 2.5,
		"left": 0, "unit": id, "tier": 9, "where": "field"})
	var t0 := Time.get_ticks_usec()
	_tick(1.0 / 30.0)
	var grant_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(world.hero_node(0) == null and world.loading(id) and world.held_slots().has(0), "an unread guardian's model is read on a loader thread (no body yet, slot held)")
	var built := false
	var build_ms := 0.0
	for n in range(240):
		await get_tree().process_frame
		t0 = Time.get_ticks_usec()
		_tick(1.0 / 240.0)
		var spent := (Time.get_ticks_usec() - t0) / 1000.0
		if world.hero_node(0) != null:
			built = true
			build_ms = spent
			break
	var node: Node3D = world.hero_node(0)
	check(built and node != null and not node.visible and not world.loading(id), "when it is read the body is built, still out of sight")
	print("  unread guardian %s: grant frame %.1f ms, build frame %.1f ms" % [id, grant_ms, build_ms])
	var landed: Array = []
	for n in range(48):
		_tick(1.0 / 30.0)
		if landed.is_empty(): landed = _arrivals(world.vfx)
	node = world.hero_node(0)
	check(node != null and node.visible and landed.size() == 1 and is_equal_approx(float(landed[0]["mode"]), 1.0), "then its star lands and it is shown")
	sim.heroes.clear()
	_tick(0.0)
	world.vfx._clear_field()

## A world inside a frozen view, shown on a window smaller than its picture (a film viewport
## with a 2D override, like a 1000x625 window over the 1280x800 design).
func _check_frozen_and_scaled() -> void:
	var host := SubViewport.new()
	host.size = Vector2i(1000, 625)
	host.size_2d_override = Vector2i(1280, 800)
	host.size_2d_override_stretch = true
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(host)
	var holder := Node2D.new()
	host.add_child(holder)
	var view := SubViewport.new()
	view.size = Vector2i(1280, 800)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	holder.add_child(view)
	var other := ArenaWorld.new()
	view.add_child(other)
	await frames(2)
	for n in range(8): other._process(0.016)
	var nodes: Array = other.get("_warm_nodes")
	var shown := not nodes.is_empty()
	for body in nodes: shown = shown and (body as Node3D).visible
	check(shown, "a frozen view (UPDATE_ONCE left on the node) keeps its warm bodies drawn")
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for n in range(6): other._process(0.016)
	var hidden := true
	for body in nodes: hidden = hidden and not (body as Node3D).visible
	check(hidden, "a live view counts its warm frames")
	check(absf(other.screen_scale() - 0.78125) < 0.01, "the picture is shown at 0.78 on a 1000x625 window (%.3f)" % other.screen_scale())
	other.set_selection(Balance.ARENA_CENTER + Vector2(80, 0), false, 320.0)
	var ring: MeshInstance3D = other.get("_ring")
	var material: ShaderMaterial = ring.material_override
	check(absf(float(material.get_shader_parameter("screen_k")) - 1.28) < 0.01, "its ring strokes are drawn 1.28x wider in the picture (3.6 px on screen)")
	check(float(material.get_shader_parameter("dashes")) < ArenaWorld.ring_dashes(320.0 / StellarWorld.UNIT), "and keep their dash period on the screen (fewer dashes)")
	host.queue_free()
	await frames(2)

func _check_skipped_sync() -> void:
	var vfx: StellarVfx = world.vfx
	vfx._clear_field()
	var unit := Roster.unit_by_id("solana")
	StellarModels.hero(unit, 9).free()
	world.event({"t": "arena_wave", "wave": 6, "total": 10, "elite": true, "boss": false})
	sim.heroes = [{"h": {"unit": unit, "tier": 9}, "pos": Balance.ARENA_CENTER + Vector2(120, 100), "range": 200.0,
		"fx_t": 9.0, "fx_w": 0.35, "fx_d": Vector2.DOWN}]
	world.event({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS, "sec": 5.0, "stun": 2.5,
		"left": 0, "unit": "solana", "tier": 9, "where": "field"})
	var born := vfx.effects.size()
	world.set_aim(Balance.ARENA_CENTER + Vector2(-60, 40), 110.0, true, true)
	world.set_aim(Balance.ARENA_CENTER + Vector2(-60, 40), 110.0, true, false)
	# A frozen window: pictures go on (the world's own _process) but no sync_battle.
	for n in range(20):
		await get_tree().process_frame
		world.build_map(Roster.THEMES[0])
	check(vfx.effects.size() == born and born > 0, "under a frozen window the sequences wait (%d)" % born)
	check(not (world.get("_aim") as Node3D).visible, "the aim ring fades on its own without the battle's sync")
	check(world.hero_node(0) == null, "the granted guardian has no body until the battle syncs again")
	_tick(1.0 / 30.0)
	var node: Node3D = world.hero_node(0)
	check(node != null and not node.visible, "after the window it is built held")
	for n in range(120): _tick(1.0 / 30.0)
	node = world.hero_node(0)
	check(node != null and node.visible, "and arrives on the resumed clock")
	check(vfx.effects.size() <= 2, "the waiting sequences finish after the window (%d left)" % vfx.effects.size())
	sim.heroes.clear()
	_tick(0.0)
	vfx._clear_field()

## The battlefield card: ArenaView may skip the battle's sync under it, so build_map alone loads
## the next revival's guardian (the run autoload).
func _check_card_preload() -> void:
	Arena.start_run(20261019, 4)
	var unit: Dictionary = Arena.revive_candidate()
	if Arena.revives_left() <= 0 or unit.is_empty():
		check(true, "no revival can come on this build: nothing to preload")
		return
	StellarModels.forget_hero(unit, Balance.TIER_MAX)
	world.build_map(Roster.THEMES[0])
	check(StellarModels.has_hero(unit, Balance.TIER_MAX), "build_map alone loads the next revival's guardian (%s)" % String(unit["id"]))
	Arena.running = false
