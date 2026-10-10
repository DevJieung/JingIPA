extends Harness

## World-to-adapter motion plumbing. The world must pass simulation-derived
## locomotion, facing, hit flash, siege phase and life-cycle events to whatever
## adapter methods exist, keep dying bodies until their presentation ends, and
## never write back into the simulation.

class FakeHero extends Node3D:
	var calls: Array[String] = []
	var velocity := Vector3.ZERO
	var dt := -1.0
	var facing := Vector2.INF
	var facing_dt := -1.0
	func set_locomotion(v: Vector3, step: float) -> void:
		calls.append("loco")
		velocity = v
		dt = step
	func face_toward(direction: Vector2, step: float) -> void:
		calls.append("face")
		facing = direction
		facing_dt = step
	func animate_visual(_time: float, _age: float = 9.0, _wind: float = 0.0, _battle: bool = false) -> void:
		calls.append("anim")

class FakeMonster extends Node3D:
	var calls: Array[String] = []
	var events: Array[String] = []
	var flash := -1.0
	var siege := -9.0
	var moving := true
	var motion := -1.0
	var facing := Vector2.INF
	var death_age := 0.0
	var death_length := 0.5
	func _init() -> void:
		set_meta("_stellar_native_monster", true)
		for status in ["Burn", "Frost", "Stun"]:
			var group := Node3D.new()
			group.name = "Stellar" + status
			add_child(group)
	func face_toward(direction: Vector2, _step: float) -> void:
		calls.append("face")
		facing = direction
	func set_hit_flash(amount: float) -> void:
		calls.append("flash")
		flash = amount
	func set_siege(phase: float) -> void:
		calls.append("siege")
		siege = phase
	func animate_visual(motion_time: float, is_moving: bool = true) -> void:
		calls.append("anim")
		motion = motion_time
		moving = is_moving
	func visual_event(type: String, _e: Dictionary) -> void:
		events.append(type)
	func advance_death(step: float) -> bool:
		death_age += step
		return death_age >= death_length

func _ready() -> void:
	if not require_no_save(): return
	await _hero_plumbing()
	await _monster_plumbing()
	await _real_adapters_tolerate_hooks()
	finish("World motion plumbing (locomotion, facing, flash, siege, death retention)")

func _hero_plumbing() -> void:
	var world := ArenaWorld.new()
	add_child(world)
	await frames(1)
	var unit: Dictionary = Roster.unit_by_id("echo")
	var hero := {"unit": unit, "tier": 4}
	var fake := FakeHero.new()
	world.actors.add_child(fake)
	world.hero_nodes["0:echo:4"] = fake
	var data := {"h": hero, "pos": Balance.ARENA_CENTER, "fx_t": 9.0, "fx_w": 0.3, "fx_d": Vector2.RIGHT}
	world.sync_heroes([data], 10.0, true)
	check(fake.calls == ["loco", "face", "anim"], "hero receives locomotion, facing, then animation each frame")
	check(fake.velocity == Vector3.ZERO and fake.dt == 0.0, "first sample has no velocity")
	check(fake.facing == Vector2.RIGHT, "idle hero faces its aim direction")
	fake.calls.clear()
	data["pos"] = Balance.ARENA_CENTER + Vector2(0, 17)
	world.sync_heroes([data], 10.1, true)
	check(fake.velocity.is_equal_approx(Vector3(0, 0, 17.0 / (StellarWorld.UNIT * 0.1))) and is_equal_approx(fake.dt, 0.1),
		"velocity is world units per simulated second: " + str(fake.velocity))
	check(fake.facing == Vector2(0, 17) and is_equal_approx(fake.facing_dt, 0.1), "walking hero outside the attack window faces its travel direction")
	data["fx_t"] = 0.1
	data["pos"] = Balance.ARENA_CENTER + Vector2(0, 34)
	world.sync_heroes([data], 10.2, true)
	check(fake.facing == Vector2.RIGHT, "walking hero inside the attack window keeps the aim direction")
	var before := data.duplicate(true)
	world.sync_heroes([data], 10.2, true)
	check(fake.dt == 0.0 and fake.velocity.length() > 0.0, "paused redraw passes dt 0 and keeps the last velocity")
	check(data == before, "hero sync never writes into simulation dictionaries")
	world.sync_heroes([{"unit": unit, "tier": 4}], 11.0, false)
	check(fake.dt == 0.0 and fake.velocity == Vector3.ZERO, "formation screens pass zero locomotion")
	world.free()
	await frames(1)

func _monster_plumbing() -> void:
	Fixture.fresh(10102026)
	Arena.start_run(10102026)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	var sim: ArenaSim = Arena.sim
	sim.monsters.clear()
	var pool := Roster.theme_pool(Arena.theme_for(1))
	sim._spawn(pool[0])
	sim._spawn(pool[1 % pool.size()])
	var first: Dictionary = sim.monsters[0]
	var second: Dictionary = sim.monsters[1]
	var sid_first := int(first["spawn_id"])
	var sid_second := int(second["spawn_id"])
	check(sid_first > 0 and sid_second > sid_first, "arena monsters carry unique spawn ids")
	var spawn_events := sim.events.filter(func(e): return String(e.get("t", "")) == "spawn")
	check(spawn_events.size() == 2 and int(spawn_events[0].get("sid", 0)) == sid_first, "spawn events name their spawn id")
	first["flash"] = 0.6
	first["vel"] = Vector2(3, 4)
	second["vel"] = Vector2.ZERO
	second["pos"] = Balance.ARENA_CENTER + Vector2(Balance.ALTAR_R + 2, 0)
	second["siege_t"] = 0.42
	var world := ArenaWorld.new()
	add_child(world)
	await frames(1)
	var fake_first := FakeMonster.new()
	var fake_second := FakeMonster.new()
	world.actors.add_child(fake_first)
	world.actors.add_child(fake_second)
	world.monster_nodes[sid_first] = fake_first
	world.monster_nodes[sid_second] = fake_second
	var state := [sim.monsters.duplicate(true), sim.events.duplicate(true), sim._rng.state]
	world.sync_battle(sim, 5.0, 1, 1.0 / 30.0)
	check(fake_first.calls.slice(0, 4) == ["face", "flash", "siege", "anim"], "monster receives facing, flash, siege, then animation: " + str(fake_first.calls))
	check(is_equal_approx(fake_first.flash, 0.6), "hit flash forwards the simulator's decaying flash value")
	check(fake_first.moving and fake_first.facing == Vector2(3, 4), "moving monster walks and faces its velocity")
	check(fake_first.siege == -1.0, "a monster away from the altar is not sieging")
	check(not fake_second.moving and is_equal_approx(fake_second.siege, 0.42), "a body at the altar stands and reports its siege phase")
	check((fake_second.facing.normalized() + Vector2.RIGHT).length() < 0.001, "standing monster faces the crystal")
	check(is_equal_approx(fake_first.motion, float(first["motion_t"]) + float(first["motion_phase"])), "animation receives the simulator clock plus phase")
	world.event({"t": "hit", "p": first["pos"], "c": Color.WHITE, "sid": sid_first, "n": 3.0})
	check(fake_first.events == ["hit"] and fake_second.events.is_empty(), "hit events route to the named body only")
	world.event({"t": "stun", "p": first["pos"], "h": 1.0, "sid": sid_first})
	world.event({"t": "hit", "p": first["pos"], "c": Color.WHITE, "sid": 999999, "n": 3.0})
	check(fake_first.events == ["hit", "stun"], "unknown spawn ids are ignored")
	var dying_pos := fake_first.position
	world.event({"t": "die", "p": first["pos"], "c": Color.RED, "h": 1.0, "sid": sid_first})
	sim.monsters.remove_at(0)
	world.sync_battle(sim, 5.1, 1, 0.1)
	check(is_instance_valid(fake_first) and world.monster_nodes.has(sid_first), "a dying body stays until its presentation ends")
	check(fake_first.position == dying_pos, "a dying body is no longer moved")
	world.sync_battle(sim, 5.2, 1, 0.0)
	check(is_instance_valid(fake_first) and is_equal_approx(fake_first.death_age, 0.1), "paused frames do not advance death")
	for n in range(5): world.sync_battle(sim, 5.3 + n * 0.1, 1, 0.1)
	check(not world.monster_nodes.has(sid_first), "a finished death releases the body")
	fake_second.death_length = 99.0
	world.event({"t": "die", "p": second["pos"], "c": Color.RED, "h": 1.0, "sid": sid_second})
	sim.monsters.clear()
	for n in range(20): world.sync_battle(sim, 6.0 + n * 0.1, 1, 0.1)
	check(not world.monster_nodes.has(sid_second), "death retention is capped at 1.6 seconds")
	check(sim.events == state[1] and sim._rng.state == state[2], "monster presentation never touches events or RNG")
	world.free()
	await frames(1)

func _real_adapters_tolerate_hooks() -> void:
	# Whatever subset of the hooks the shipped adapters implement, the world must
	# drive a live mixed battle without errors and without touching the simulator.
	Fixture.fresh(10102027)
	Arena.start_run(10102027)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.heroes.clear()
	for id in ["echo", "kari", "jokull", "brasa", "triton", "limne"]:
		Arena.gain_hero(Roster.unit_by_id(id), 3)
	Arena.sim.refresh_heroes()
	var sim: ArenaSim = Arena.sim
	var pool := Roster.theme_pool(Arena.theme_for(1))
	for n in range(6): sim._spawn(pool[n % pool.size()])
	var world := ArenaWorld.new()
	add_child(world)
	await frames(1)
	for frame in range(90):
		sim.step(1.0 / 30.0)
		for hero in sim.heroes: hero["fx_t"] = float(hero.get("fx_t", 9.0)) + 1.0 / 30.0
		for e in sim.events: world.event(e)
		sim.events.clear()
		var snapshot := [sim.heroes.duplicate(true), sim.monsters.duplicate(true), sim.bullets.duplicate(true), sim._rng.state]
		world.sync_battle(sim, sim.elapsed, 1, 1.0 / 30.0)
		if frame % 30 == 0:
			check([sim.heroes, sim.monsters, sim.bullets, sim._rng.state] == snapshot, "live world sync preserves the simulator at frame %d" % frame)
	check(world.hero_nodes.size() == 6, "six live heroes remain after ninety frames")
	world.free()
	await frames(1)
