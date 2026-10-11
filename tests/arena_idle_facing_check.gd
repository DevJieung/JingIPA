extends Harness

## Idle facing. A hero that walks and then stops with no enemy in range must
## settle facing its direction of travel and hold that facing — no turning
## toward stale targets, no frame-to-frame flips. The loop below mirrors the
## arena screen: joystick → move_selected → step → event replay → sync_battle.

const DT := 1.0 / 60.0
var trace := has_arg("--trace")

func _ready() -> void:
	if not require_no_save(): return
	Save._readonly = true
	await _walk_then_stop()
	await _stop_after_shooting()
	finish("정지 후 바라보는 방향 유지")

func _arena(seed_value: int, ids: Array) -> ArenaWorld:
	Fixture.fresh(seed_value)
	Arena.start_run(seed_value)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(ids.size()):
		Arena.gain_hero(Roster.unit_by_id(ids[i]), 4)
		# Far apart so a short walk never collides with a neighbour.
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2(-220 + i * 220, 150)
	Arena.sim.refresh_heroes()
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	Arena.selected = 0
	var world := ArenaWorld.new()
	add_child(world)
	await frames(1)
	# Hero nodes are created by the first synchronised frame.
	_frame(world, Vector2.ZERO)
	return world

## One rendered frame exactly as ArenaScreen/ArenaView drive the simulation.
func _frame(world: ArenaWorld, joystick: Vector2) -> void:
	var sim: ArenaSim = Arena.sim
	sim.move_selected(joystick, DT)
	sim.step(DT)
	for hero in sim.heroes: hero["fx_t"] = float(hero.get("fx_t", 9.0)) + DT
	for e in sim.events:
		if String(e.get("t", "")) == "aim":
			var source := int(e.get("src", -1))
			if source >= 0 and source < sim.heroes.size():
				sim.heroes[source]["fx_t"] = 0.0
				sim.heroes[source]["fx_w"] = float(e.get("w", 0.0))
				sim.heroes[source]["fx_d"] = e.get("d", Vector2.DOWN)
		world.event(e)
	sim.events.clear()
	world.sync_battle(sim, sim.elapsed, 1, DT)

static func _deg(a: float) -> float:
	return rad_to_deg(wrapf(a, -PI, PI))

func _yaw_trace(world: ArenaWorld, joystick: Vector2, seconds: float, label: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var node: Node3D = world.hero_node(0)
	for n in range(int(round(seconds / DT))):
		_frame(world, joystick)
		out.append(node.rotation.y)
		if trace and n % 6 == 0:
			var loco = node.get("_loco")
			print("%s %3d yaw %7.1f speed %.2f aim %.2f face %s" % [label, n, _deg(node.rotation.y),
				float(loco.speed) if loco != null else -1.0, float(loco.aim_delta) if loco != null else 0.0,
				str(loco.face_target) if loco != null else "-"])
	return out

func _max_step(yaws: PackedFloat64Array, from: int) -> float:
	var worst := 0.0
	for i in range(maxi(1, from), yaws.size()):
		worst = maxf(worst, absf(wrapf(yaws[i] - yaws[i - 1], -PI, PI)))
	return worst

func _walk_then_stop() -> void:
	var world := await _arena(10112026, ["echo", "jokull", "limne"])
	var node: Node3D = world.hero_node(0)
	check(node != null and node.has_method("face_toward"), "selected hero is a smooth-turning adapter")
	var walking := _yaw_trace(world, Vector2.RIGHT, 1.0, "walk")
	var travel := HeroLocomotion.yaw_of(Vector2.RIGHT)
	check(absf(wrapf(walking[-1] - travel, -PI, PI)) < deg_to_rad(8), "hero faces east while walking east (%.1f°)" % _deg(walking[-1]))
	var stopped := _yaw_trace(world, Vector2.ZERO, 3.0, "stop")
	var settle := int(0.5 / DT)
	var drift := 0.0
	for i in range(settle, stopped.size()):
		drift = maxf(drift, absf(wrapf(stopped[i] - travel, -PI, PI)))
	check(drift < deg_to_rad(8), "stopped hero keeps facing its travel direction without enemies (max %.1f° off)" % rad_to_deg(drift))
	check(_max_step(stopped, settle) < deg_to_rad(1.0), "no frame-to-frame turning while standing (max %.2f°/frame)" % rad_to_deg(_max_step(stopped, settle)))
	# Diagonal travel and a second hero share the rule.
	Arena.selected = 1
	var node2: Node3D = world.hero_node(1)
	var walk2 := _yaw_trace(world, Vector2(-1, 1).normalized(), 0.8, "walk2")
	var travel2 := HeroLocomotion.yaw_of(Vector2(-1, 1))
	check(absf(wrapf(node2.rotation.y - travel2, -PI, PI)) < deg_to_rad(8), "second hero faces its diagonal travel")
	var stop2 := _yaw_trace(world, Vector2.ZERO, 2.0, "stop2")
	var drift2 := 0.0
	for i in range(settle, stop2.size()):
		drift2 = maxf(drift2, absf(wrapf(node2.rotation.y - travel2, -PI, PI)))
	check(absf(wrapf(node2.rotation.y - travel2, -PI, PI)) < deg_to_rad(8), "second hero holds its diagonal facing after stopping (%.1f°)" % _deg(wrapf(node2.rotation.y - travel2, -PI, PI)))
	check(absf(wrapf(node.rotation.y - travel, -PI, PI)) < deg_to_rad(8), "an unselected standing hero never turns (%.1f°)" % _deg(wrapf(node.rotation.y - travel, -PI, PI)))
	# Pushing into another hero: blocked, but still facing where the player pushes.
	Arena.selected = 0
	_yaw_trace(world, Vector2.UP, 0.6, "north")
	Arena.sim.heroes[0]["pos"] = Vector2(Arena.sim.heroes[1]["pos"]) + Vector2(-Balance.ARENA_HERO_RADIUS * 2.0 - 1.0, 0)
	Arena.sim.heroes[0]["h"]["position"] = Arena.sim.heroes[0]["pos"]
	_frame(world, Vector2.ZERO)
	var before: Vector2 = Arena.sim.heroes[0]["pos"]
	var pushed := _yaw_trace(world, Vector2.RIGHT, 1.2, "push")
	check(Vector2(Arena.sim.heroes[0]["pos"]).distance_to(before) < 2.0, "pushing into a neighbour does not move the hero")
	check(absf(wrapf(pushed[-1] - travel, -PI, PI)) < deg_to_rad(8), "a blocked hero faces the direction it is pushed (%.1f°)" % _deg(pushed[-1]))
	check(_max_step(pushed, settle) < deg_to_rad(1.0), "no flipping while blocked (max %.2f°/frame)" % rad_to_deg(_max_step(pushed, settle)))
	world.free()
	await frames(1)

## After killing an enemy, walking away and stopping, the hero faces where it
## walked — not the position of the old target.
func _stop_after_shooting() -> void:
	var world := await _arena(10112027, ["echo", "kari"])
	var sim: ArenaSim = Arena.sim
	var node: Node3D = world.hero_node(0)
	var pool := Roster.theme_pool(Arena.theme_for(1))
	sim._spawn(pool[0])
	var mo: Dictionary = sim.monsters[-1]
	mo["pos"] = Vector2(sim.heroes[0]["pos"]) + Vector2(0, -120)
	mo["hp"] = 1.0
	mo["max"] = 1.0
	sim._cache_positions()
	var fired := false
	for n in range(240):
		_frame(world, Vector2.ZERO)
		if sim.monsters.is_empty():
			fired = true
			break
	check(fired, "hero shoots and kills the enemy standing north of it")
	for n in range(30): _frame(world, Vector2.ZERO)
	var north := HeroLocomotion.yaw_of(Vector2(0, -1))
	check(absf(wrapf(node.rotation.y - north, -PI, PI)) < deg_to_rad(10), "after the kill the hero still faces its last target (%.1f°)" % _deg(wrapf(node.rotation.y - north, -PI, PI)))
	_yaw_trace(world, Vector2.RIGHT, 1.0, "walk3")
	var stopped := _yaw_trace(world, Vector2.ZERO, 2.5, "stop3")
	var travel := HeroLocomotion.yaw_of(Vector2.RIGHT)
	var settle := int(0.5 / DT)
	var drift := 0.0
	for i in range(settle, stopped.size()):
		drift = maxf(drift, absf(wrapf(stopped[i] - travel, -PI, PI)))
	check(drift < deg_to_rad(8), "after walking away from an old target the hero faces where it walked (max %.1f° off)" % rad_to_deg(drift))
	check(_max_step(stopped, settle) < deg_to_rad(1.0), "no flipping after stopping near an old target (max %.2f°/frame)" % rad_to_deg(_max_step(stopped, settle)))
	# Walking past a durable enemy: the hero keeps walking east while its attack
	# faces the enemy; once the enemy is gone it faces east again.
	sim._spawn(pool[0])
	var tank: Dictionary = sim.monsters[-1]
	tank["pos"] = Vector2(sim.heroes[0]["pos"]) + Vector2(60, -90)
	tank["hp"] = 1.0e9
	tank["max"] = 1.0e9
	sim._cache_positions()
	var aimed := false
	var yaw_toward_target := false
	for n in range(90):
		_frame(world, Vector2.RIGHT)
		var e_aim: bool = float(sim.heroes[0].get("fx_t", 9.0)) <= float(sim.heroes[0].get("fx_w", 0.0))
		if e_aim:
			aimed = true
			var to_target := (Vector2(tank["pos"]) - Vector2(sim.heroes[0]["pos"])).normalized()
			var loco = node.get("_loco")
			var body_aim := wrapf(node.rotation.y + float(loco.aim_delta) - HeroLocomotion.yaw_of(to_target), -PI, PI)
			yaw_toward_target = yaw_toward_target or absf(body_aim) < deg_to_rad(25)
	check(aimed, "the hero attacks the durable enemy while walking")
	check(yaw_toward_target, "while walking and attacking the upper body aims at the enemy")
	sim.monsters.clear()
	_yaw_trace(world, Vector2.RIGHT, 0.6, "walk4")
	var stop4 := _yaw_trace(world, Vector2.ZERO, 1.5, "stop4")
	check(absf(wrapf(stop4[-1] - travel, -PI, PI)) < deg_to_rad(8), "after the enemy is gone a walking hero faces east and keeps it when stopping (%.1f°)" % _deg(stop4[-1]))
	world.free()
	await frames(1)
