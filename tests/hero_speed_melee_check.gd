extends Harness

## Per-hero move speed and sword melee strikes.
##
##   STELLARDEFENSE_NO_SAVE=1 godot --headless --path . res://tests/hero_speed_melee_check.tscn
##
## Speed: Balance.hero_speed scales the arena joystick speed by the character's
## spd multiplier, the simulator carries it per hero, and a fast hero really
## covers more ground than a slow one. Melee: sword heroes spawn no projectile;
## at release the blade hits the aimed enemy directly, pierce swords cut up to
## their pierce count inside the fan in front, nothing behind or beyond reach is
## touched, and every hit names its body (sid) and position.

const DT := 1.0 / 60.0

func _ready() -> void:
	if not require_no_save(): return
	Save._readonly = true
	_speed_rules()
	await _speed_in_arena()
	await _melee_pierce()
	await _melee_single_and_splash()
	finish("영웅별 이동 속도 · 검 근접 타격")

func _speed_rules() -> void:
	check(is_equal_approx(Balance.hero_speed({"spd": 1.0}), Balance.ARENA_HERO_SPEED), "spd 1.0 is the base arena speed")
	check(is_equal_approx(Balance.hero_speed({}), Balance.ARENA_HERO_SPEED), "a unit without spd walks at the base speed")
	check(is_equal_approx(Balance.hero_speed({"spd": 0.6}), Balance.ARENA_HERO_SPEED * 0.6), "spd 0.6 walks at 60%")
	check(is_equal_approx(Balance.hero_speed({"spd": 1.5}), Balance.ARENA_HERO_SPEED * 1.5), "spd 1.5 walks at 150%")
	for unit in Roster.UNITS:
		var spd := float(unit.get("spd", 1.0))
		if spd < 0.5 or spd > 1.6:
			check(false, "%s spd %.2f outside 0.5~1.6" % [unit["id"], spd])
	var slow: Dictionary = Roster.unit_by_id("brasa").duplicate(true)
	slow["spd"] = 0.6
	var st := CombatStats.hero({"unit": slow, "tier": 4, "n": 1}, {}, [], [])
	check(is_equal_approx(float(st["speed"]), Balance.ARENA_HERO_SPEED * 0.6), "hero stats carry the move speed")
	check(Balance.is_melee(Roster.unit_by_id("jokull")) and not Balance.is_melee(Roster.unit_by_id("echo")), "swords are melee, bows are not")
	check(Balance.MELEE_ARC > 60.0 and Balance.MELEE_ARC < 180.0, "the melee fan is a forward arc")
	check(Balance.RANGE_MIN < Balance.WEAPON_RANGE["sword"], "the range floor allows a short sword reach")

func _arena(seed_value: int, units: Array) -> ArenaSim:
	Fixture.fresh(seed_value)
	Arena.start_run(seed_value)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.heroes.clear()
	Arena.bench.clear()
	for i in range(units.size()):
		Arena.gain_hero(units[i], 4)
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2(-200 + i * 200, 160)
	Arena.sim.refresh_heroes()
	Arena.sim.monsters.clear()
	Arena.sim._spawn_t = 1.0e9
	Arena.selected = 0
	return Arena.sim

func _speed_in_arena() -> void:
	var slow: Dictionary = Roster.unit_by_id("brasa").duplicate(true)
	slow["spd"] = 0.6
	var fast: Dictionary = Roster.unit_by_id("pip").duplicate(true)
	fast["spd"] = 1.5
	var sim := _arena(10112028, [slow, fast])
	check(is_equal_approx(float(sim.heroes[0]["speed"]), Balance.ARENA_HERO_SPEED * 0.6), "arena hero carries its own speed")
	var start_slow: Vector2 = sim.heroes[0]["pos"]
	for n in range(60): sim.move_selected(Vector2.RIGHT, DT)
	var slow_distance := Vector2(sim.heroes[0]["pos"]).distance_to(start_slow)
	Arena.selected = 1
	var start_fast: Vector2 = sim.heroes[1]["pos"]
	for n in range(60): sim.move_selected(Vector2.RIGHT, DT)
	var fast_distance := Vector2(sim.heroes[1]["pos"]).distance_to(start_fast)
	check(absf(slow_distance - Balance.ARENA_HERO_SPEED * 0.6) < 3.0, "a spd 0.6 hero walks 60%% of the base distance in one second (%.1f)" % slow_distance)
	check(absf(fast_distance - Balance.ARENA_HERO_SPEED * 1.5) < 3.0, "a spd 1.5 hero walks 150%% of the base distance in one second (%.1f)" % fast_distance)
	check(fast_distance > slow_distance * 2.3, "the fast hero clearly outruns the slow one")
	await frames(1)

## Monsters are pinned in place each tick so only the strike geometry is measured.
func _fire_until_hits(sim: ArenaSim, pins: Dictionary, limit: int = 240) -> Array:
	var hits: Array = []
	var fires: Array = []
	for n in range(limit):
		for i in pins: sim.monsters[i]["pos"] = pins[i]
		sim._cache_positions()
		sim._heroes_fire(DT)
		for e in sim.events:
			if String(e.get("t", "")) == "hit": hits.append(e)
			if String(e.get("t", "")) == "fire": fires.append(e)
		sim.events.clear()
		check(sim.bullets.is_empty(), "a sword never spawns a projectile")
		if not hits.is_empty() and sim._pending.is_empty():
			break
	return [fires, hits]

func _place(sim: ArenaSim, hero_pos: Vector2, offsets: Array) -> Dictionary:
	var pool := Roster.theme_pool(Arena.theme_for(1))
	var pins := {}
	for i in range(offsets.size()):
		sim._spawn(pool[i % pool.size()])
		var mo: Dictionary = sim.monsters[-1]
		mo["hp"] = 1.0e6
		mo["max"] = 1.0e6
		mo["pos"] = hero_pos + offsets[i]
		pins[i] = mo["pos"]
	sim._cache_positions()
	sim.events.clear()
	return pins

func _melee_pierce() -> void:
	var sim := _arena(10112029, [Roster.unit_by_id("jokull")])
	var he: Dictionary = sim.heroes[0]
	var reach := float(he["range"])
	check(is_equal_approx(reach, Balance.attack_range(he["h"]["unit"], 4)), "sim range equals the balance range")
	var spec: Dictionary = Balance.BULLET[String(he["kind"])]
	var pierce := int(spec.get("pierce", 1))
	check(pierce >= 3, "jokull's blade pierces several bodies")
	var hero_pos: Vector2 = he["pos"]
	var front := Vector2(0, -1)
	# 0 nearest ahead, 1 and 2 inside the fan, 3 inside the fan but beyond reach,
	# 4 behind the hero, 5 inside reach but outside the fan.
	var offsets := [front * reach * 0.45,
		front.rotated(deg_to_rad(35)) * reach * 0.8,
		front.rotated(deg_to_rad(-40)) * reach * 0.85,
		front * (reach + 40.0),
		-front * reach * 0.6,
		front.rotated(deg_to_rad(95)) * reach * 0.7]
	var pins := _place(sim, hero_pos, offsets)
	var hp_before: Array = []
	for mo in sim.monsters: hp_before.append(float(mo["hp"]))
	var result := _fire_until_hits(sim, pins)
	var fires: Array = result[0]
	var hits: Array = result[1]
	check(fires.size() >= 1 and bool(fires[0].get("melee", false)), "the fire event is marked melee")
	check(not hits.is_empty(), "the blade lands hits at release")
	var struck := {}
	for e in hits:
		struck[int(e["sid"])] = true
		check(bool(e.get("melee", false)), "melee hits are marked")
	var sid := func(i: int) -> int: return int(sim.monsters[i]["spawn_id"])
	check(struck.has(sid.call(0)) and struck.has(sid.call(1)) and struck.has(sid.call(2)), "the nearest body and two more inside the fan are cut")
	check(not struck.has(sid.call(3)), "a body beyond reach is not cut")
	check(not struck.has(sid.call(4)), "a body behind the hero is not cut")
	check(not struck.has(sid.call(5)), "a body outside the fan is not cut")
	check(struck.size() == pierce, "pierce %d cuts exactly %d bodies (%d)" % [pierce, pierce, struck.size()])
	for i in range(sim.monsters.size()):
		var damaged: bool = float(sim.monsters[i]["hp"]) < float(hp_before[i])
		check(damaged == struck.has(sid.call(i)), "damage matches the hit events for body %d" % i)
	for e in hits:
		var body := -1
		for i in range(sim.monsters.size()):
			if int(sim.monsters[i]["spawn_id"]) == int(e["sid"]): body = i
		check(body >= 0 and Vector2(e["p"]).distance_to(pins[body]) < 0.01, "hit position is the struck body's position")
	check(float(he["dmg"]) > 0.0, "the hero is credited with melee damage")
	await frames(1)

func _melee_single_and_splash() -> void:
	# A single-strike sword cuts only the nearest body even with others in the fan.
	var sim := _arena(10112030, [Roster.unit_by_id("pip")])
	var he: Dictionary = sim.heroes[0]
	var reach := float(he["range"])
	var front := Vector2(0, -1)
	var pins := _place(sim, he["pos"], [front * reach * 0.5, front.rotated(deg_to_rad(30)) * reach * 0.7])
	var result := _fire_until_hits(sim, pins)
	var hits: Array = result[1]
	var bodies := {}
	for e in hits: bodies[int(e["sid"])] = true
	check(bodies.size() == 1 and bodies.has(int(sim.monsters[0]["spawn_id"])), "a single-strike sword cuts one body")
	await frames(1)
	# A splash sword still bursts around the struck body.
	sim = _arena(10112031, [Roster.unit_by_id("helga")])
	he = sim.heroes[0]
	reach = float(he["range"])
	pins = _place(sim, he["pos"], [front * reach * 0.5, front * reach * 0.5 + Vector2(20, 0)])
	var hp1 := float(sim.monsters[1]["hp"])
	var splashes := 0
	var hits2: Array = []
	for n in range(240):
		for i in pins: sim.monsters[i]["pos"] = pins[i]
		sim._cache_positions()
		sim._heroes_fire(DT)
		for e in sim.events:
			if String(e.get("t", "")) == "splash": splashes += 1
			if String(e.get("t", "")) == "hit": hits2.append(e)
		sim.events.clear()
		check(sim.bullets.is_empty(), "a splash sword never spawns a projectile")
		if not hits2.is_empty() and sim._pending.is_empty(): break
	check(splashes >= 1, "a splash sword bursts at the struck body")
	check(float(sim.monsters[1]["hp"]) < hp1, "the neighbour takes splash damage")
	await frames(1)
