extends BattleSim
class_name ArenaSim

## Continuous battle on the ground plane of the real 3D world.
## Position, navigation, timers and damage belong here; renderers only read them.
var boss_spawned := false
var boss_alive := false
var won := false
var crystal_hp := 0.0
var crystal_max := 0.0
var shield := 0.0
var shield_t := 0.0
var skill_cooldowns := {"blast": 0.0, "freeze": 0.0, "ward": 0.0}
var _nav := AStarGrid2D.new()
var _nav_key := ""
var _nav_version := 0
var _serial := 0
var _accumulator := 0.0
var _save_t := 0.0
var _spawn_pool: Array = []
var _pool_period := -1

func setup(run_state, wave_no: int = 1, seed_value: int = 0) -> void:
	super.setup(run_state, wave_no, seed_value)
	crystal_max = Balance.ARENA_CRYSTAL_HP
	crystal_hp = crystal_max
	boss_spawned = false
	boss_alive = false
	won = false
	shield = 0.0
	shield_t = 0.0
	_serial = 0
	_accumulator = 0.0
	_save_t = 0.0
	_pool_period = -1
	_spawn_pool.clear()
	_spawn_t = Balance.ARENA_SPAWN_INITIAL
	for id in skill_cooldowns:
		skill_cooldowns[id] = 0.0
	_nav.region = Rect2i(Vector2i.ZERO, Vector2i(ceili(Balance.MAP_RECT.size.x / Balance.ARENA_NAV_CELL), ceili(Balance.MAP_RECT.size.y / Balance.ARENA_NAV_CELL)))
	_nav.cell_size = Vector2.ONE * Balance.ARENA_NAV_CELL
	_nav.offset = Balance.MAP_RECT.position + _nav.cell_size * 0.5
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.update()
	_nav_key = ""
	_rebuild_navigation()

func _build_queue() -> void:
	_queue.clear()

func refresh_heroes() -> void:
	var old_ids: Array[String] = []
	var old_runtime := {}
	for runtime in heroes:
		var id := String(runtime["h"]["unit"]["id"])
		old_ids.append(id)
		old_runtime[id] = runtime
	# Runtime counters and cooldowns follow the hero, including reserve swaps.
	var reordered: Array = []
	for hero in run.heroes:
		var id := String(hero["unit"]["id"])
		reordered.append(old_runtime.get(id, {"h": hero, "cool": 0.2, "acc": 0.0, "face": 1.0,
			"dmg": 0.0, "kills": 0, "dw": 0.0, "dn": 0.0, "dr": 0.0}))
	heroes.assign(reordered)
	super.refresh_heroes()
	heroes.resize(run.heroes.size())
	var changed := old_ids.size() != heroes.size()
	for i in range(mini(old_ids.size(), heroes.size())):
		changed = changed or old_ids[i] != String(heroes[i]["h"]["unit"]["id"])
	if changed:
		_pending.clear()
		for list in [bullets, zones, monsters]:
			for item in list:
				for key in ["src", "burn_src"]:
					if not item.has(key):
						continue
					var old := int(item[key])
					var index := -1
					if old >= 0 and old < old_ids.size():
						for j in range(heroes.size()):
							if String(heroes[j]["h"]["unit"]["id"]) == old_ids[old]:
								index = j
					item[key] = index
	_nav_key = ""

func population_limit() -> int:
	var progress_value := clampf(elapsed / Balance.ARENA_BOSS_AT, 0.0, 1.0)
	return roundi(lerpf(Balance.ARENA_POPULATION_START, Balance.ARENA_POPULATION_MAX, progress_value))

func spawn_interval() -> float:
	return lerpf(Balance.ARENA_SPAWN_INITIAL, Balance.ARENA_SPAWN_MIN, clampf(elapsed / Balance.ARENA_BOSS_AT, 0.0, 1.0))

func _spawn(monster: Dictionary) -> void:
	super._spawn(monster)
	var mo: Dictionary = monsters[-1]
	var rect := Balance.MAP_RECT.grow(-Balance.ARENA_MONSTER_RADIUS)
	var point: Vector2
	match _rng.randi_range(0, 3):
		0: point = Vector2(rect.position.x, _rng.randf_range(rect.position.y, rect.end.y))
		1: point = Vector2(rect.end.x, _rng.randf_range(rect.position.y, rect.end.y))
		2: point = Vector2(_rng.randf_range(rect.position.x, rect.end.x), rect.position.y)
		_: point = Vector2(_rng.randf_range(rect.position.x, rect.end.x), rect.end.y)
	_serial += 1
	mo.merge({"pos": point, "vel": Vector2.ZERO, "blocked": false, "spawn_id": _serial,
		"path": PackedVector2Array(), "nav_v": -1, "siege_t": 0.0})
	mo["hp"] = float(mo["hp"]) * Balance.ARENA_HP_SCALE
	mo["max"] = mo["hp"]
	if String(mo["kind"]) == "boss":
		boss_alive = true
	events[-1]["p"] = point

func step(dt: float) -> void:
	if done or not run.running or not String(run.modal).is_empty() or dt <= 0.0:
		return
	_accumulator += minf(dt, 0.25)
	while _accumulator >= 1.0 / 60.0 and not done:
		_tick(1.0 / 60.0)
		_accumulator -= 1.0 / 60.0
	if _save_t >= 5.0 and run.running:
		_save_t = 0.0
		run.autosave()

func _tick(dt: float) -> void:
	elapsed += dt
	curse_t = maxf(0.0, curse_t - dt)
	surge_t = maxf(0.0, surge_t - dt)
	if surge_t == 0.0:
		surge = 0.0
	for id in skill_cooldowns:
		skill_cooldowns[id] = maxf(0.0, float(skill_cooldowns[id]) - dt)
	shield_t = maxf(0.0, shield_t - dt)
	if shield_t == 0.0:
		shield = 0.0
	if not boss_spawned and elapsed >= Balance.ARENA_BOSS_AT:
		boss_spawned = true
		_spawn(run.boss_for(1))
		events.append({"t": "arena_boss", "p": mpos(monsters[-1])})
	elif not boss_spawned:
		_spawn_t -= dt
		if _spawn_t <= 0.0:
			if monsters.size() < population_limit():
				var period := int(elapsed / Balance.SPAWN_WINDOW)
				if period != _pool_period or _spawn_pool.is_empty():
					_pool_period = period
					_spawn_pool = run.spawns_for(period + 1)
				if not _spawn_pool.is_empty():
					_spawn(_spawn_pool[_rng.randi_range(0, _spawn_pool.size() - 1)])
			_spawn_t = spawn_interval()
	_rebuild_navigation()
	_move_monsters(dt)
	_cache_positions()
	_heroes_fire(dt)
	_move_bullets(dt)
	_step_zones(dt)
	_reap()
	if not run.running:
		done = true
	_save_t += dt

func _cell(point: Vector2) -> Vector2i:
	var local := (point - Balance.MAP_RECT.position) / Balance.ARENA_NAV_CELL
	return Vector2i(clampi(floori(local.x), 0, _nav.region.size.x - 1), clampi(floori(local.y), 0, _nav.region.size.y - 1))

func _rebuild_navigation() -> void:
	var key := ""
	for hero in heroes:
		var p: Vector2 = hero["pos"]
		key += "%d,%d;" % [roundi(p.x / 4.0), roundi(p.y / 4.0)]
	if key == _nav_key:
		return
	_nav_key = key
	_nav_version += 1
	var radius := Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS + Balance.ARENA_NAV_CELL * 0.5
	for y in range(_nav.region.size.y):
		for x in range(_nav.region.size.x):
			var cell := Vector2i(x, y)
			var p := _nav.get_point_position(cell)
			var solid := false
			for hero in heroes:
				var at: Vector2 = hero["pos"]
				at = (at / 4.0).round() * 4.0
				if p.distance_squared_to(at) < radius * radius:
					solid = true
					break
			_nav.set_point_solid(cell, solid)

func _segment_clear(from: Vector2, to: Vector2) -> bool:
	var radius := Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS
	for hero in heroes:
		var p: Vector2 = hero["pos"]
		var near := Geometry2D.get_closest_point_to_segment(p, from, to)
		if near.distance_squared_to(p) < radius * radius:
			return false
	return true

func _path_from(from: Vector2, target: Vector2) -> PackedVector2Array:
	# A coarse blocked cell can contain a collision-free starting point.
	# Enter a visible free neighbour rather than trapping the enemy forever.
	if not _segment_clear(from, from):
		return PackedVector2Array()
	var start := _cell(from)
	var end := _cell(target)
	var candidates: Array[Vector2i] = []
	for y in range(start.y - 1, start.y + 2):
		for x in range(start.x - 1, start.x + 2):
			var cell := Vector2i(x, y)
			if _nav.region.has_point(cell) and not _nav.is_point_solid(cell) and _segment_clear(from, _nav.get_point_position(cell)):
				candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return from.distance_squared_to(_nav.get_point_position(a)) < from.distance_squared_to(_nav.get_point_position(b)))
	for cell in candidates:
		var path := _nav.get_point_path(cell, end)
		if not path.is_empty():
			return path
	return PackedVector2Array()

func move_selected(direction: Vector2, dt: float) -> bool:
	for actor in heroes:
		actor["move_d"] = Vector2.ZERO
	if done or not run.running or not String(run.modal).is_empty() or run.selected < 0 or run.selected >= heroes.size():
		return false
	if direction.length_squared() < 0.001:
		if run.selected < heroes.size():
				heroes[run.selected]["move_d"] = Vector2.ZERO
		return false
	var hero: Dictionary = heroes[run.selected]
	var current: Vector2 = hero["pos"]
	var requested := current + direction.limit_length() * Balance.ARENA_HERO_SPEED * minf(maxf(dt, 0.0), 0.25)
	var rect := Balance.MAP_RECT.grow(-Balance.ARENA_HERO_RADIUS)
	requested = requested.clamp(rect.position, rect.end)
	var accepted := current
	for point in [requested, Vector2(requested.x, current.y), Vector2(current.x, requested.y)]:
		if point.distance_to(Balance.ARENA_CENTER) < Balance.ALTAR_R + Balance.ARENA_HERO_RADIUS:
			continue
		var free := true
		for i in range(heroes.size()):
			if i != run.selected and point.distance_to(Vector2(heroes[i]["pos"])) < Balance.ARENA_HERO_RADIUS * 2.0:
				free = false
		if free:
			accepted = point
			break
	hero["pos"] = accepted
	hero["h"]["position"] = accepted
	hero["move_d"] = (accepted - current).normalized()
	if accepted != current:
		hero["fx_d"] = hero["move_d"]
	return accepted != current

func _move_monsters(dt: float) -> void:
	var mire := Balance.mire_mult(run.lv("mire"))
	for mo in monsters:
		if float(mo["hp"]) <= 0.0:
			continue
		var current: Vector2 = mo["pos"]
		mo["vel"] = Vector2.ZERO
		mo["blocked"] = false
		mo["flash"] = maxf(0.0, float(mo["flash"]) - dt * 5.0)
		mo["stun_cd"] = maxf(0.0, float(mo["stun_cd"]) - dt)
		var speed := Balance.PATH_SPEED * float(mo["spd"]) * mire
		if float(mo["slow_t"]) > 0.0:
			mo["slow_t"] = maxf(0.0, float(mo["slow_t"]) - dt)
			speed *= 1.0 - float(mo["slow"])
		if float(mo["stun_t"]) > 0.0:
			mo["stun_t"] = maxf(0.0, float(mo["stun_t"]) - dt)
			speed = 0.0
			if float(mo["stun_t"]) == 0.0:
				mo["stun_cd"] = Balance.STUN_IMMUNE_SEC
		if float(mo["burn_t"]) > 0.0:
			mo["burn_t"] = maxf(0.0, float(mo["burn_t"]) - dt)
			var damage := minf(float(mo["hp"]), float(mo["burn"]) * dt)
			mo["hp"] = float(mo["hp"]) - damage
			_credit(int(mo["burn_src"]), damage, float(mo["burn_em"]))
		if float(mo["hp"]) <= 0.0 or speed == 0.0:
			continue
		if String(mo["kind"]) == "caster" and float(mo["stun_t"]) <= 0.0:
			mo["cast_t"] = float(mo["cast_t"]) - dt
			if float(mo["cast_t"]) <= 0.0:
				mo["cast_t"] = Balance.CURSE_EVERY
				curse_t = Balance.CURSE_SEC
				events.append({"t": "curse", "p": current})
		var pushed := _advance_push(mo, dt)
		if pushed > 0.0:
			var push_to := current + (current - Balance.ARENA_CENTER).normalized() * pushed
			if _segment_clear(current, push_to) and Balance.MAP_RECT.has_point(push_to):
				current = push_to
				mo["pos"] = current
		var stop := Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS
		if current.distance_to(Balance.ARENA_CENTER) <= stop:
			mo["siege_t"] = float(mo["siege_t"]) + dt
			if float(mo["siege_t"]) >= 1.0:
				mo["siege_t"] = float(mo["siege_t"]) - 1.0
				_damage_crystal(Balance.ARENA_CRYSTAL_DPS * float(mo["crush"]), current)
			if not run.running:
				return
			continue
		var target := Balance.ARENA_CENTER
		if not _segment_clear(current, target):
			if int(mo["nav_v"]) != _nav_version:
				mo["path"] = _path_from(current, target)
				mo["nav_v"] = _nav_version
			var path: PackedVector2Array = mo["path"]
			while path.size() > 1 and current.distance_to(path[0]) <= Balance.ARENA_NAV_CELL * 0.7:
				path.remove_at(0)
			mo["path"] = path
			if path.is_empty():
				mo["blocked"] = true
				continue
			target = path[0]
		var next := current.move_toward(target, speed * dt)
		if not _segment_clear(current, next):
			mo["blocked"] = true
			continue
		mo["pos"] = next
		mo["vel"] = (next - current) / dt
		mo["motion_t"] = float(mo["motion_t"]) + next.distance_to(current) / Balance.PATH_SPEED

func _push(mi: int) -> void:
	if mi < 0 or mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	var used := float(mo["push"])
	var distance := minf(Balance.RIDER_PUSH, Balance.RIDER_PUSH_MAX - used)
	if distance <= 0.0:
		return
	var remaining := float(mo["push_left"])
	mo["push"] = used + distance
	mo["push_left"] = remaining + distance
	mo["push_t"] = Balance.RIDER_PUSH_SEC * maxf(1.0, (remaining + distance) / Balance.RIDER_PUSH)
	events.append({"t": "push", "p": mpos(mo), "h": float(mo["h"])})

func _damage_crystal(damage: float, at: Vector2) -> void:
	if run.has("bulwark") and _rng.randf() < Balance.PASSIVE_BULWARK_P:
		events.append({"t": "block", "p": at, "h": 35.0})
		return
	var absorbed := minf(shield, damage)
	shield -= absorbed
	crystal_hp = maxf(0.0, crystal_hp - damage + absorbed)
	run.lives = ceili(crystal_hp / crystal_max * Balance.MAX_LIVES)
	events.append({"t": "arena_crystal_hit", "p": Balance.ARENA_CENTER, "n": damage - absorbed})
	if crystal_hp <= 0.0:
		done = true
		run.end_run(false)

func _reap() -> void:
	var boss_dead := false
	for mo in monsters:
		if String(mo["kind"]) == "boss" and float(mo["hp"]) <= 0.0:
			boss_dead = true
	super._reap()
	if boss_dead and run.running:
		boss_alive = false
		won = true
		done = true
		run.end_run(true)

func skill_max_cooldown(id: String) -> float:
	match id:
		"blast": return Balance.ARENA_BLAST_COOLDOWN
		"freeze": return Balance.ARENA_FREEZE_COOLDOWN
		"ward": return Balance.ARENA_WARD_COOLDOWN
	return 0.0

func cast_skill(id: String) -> bool:
	if done or not run.running or not String(run.modal).is_empty() or not skill_cooldowns.has(id) or float(skill_cooldowns[id]) > 0.0:
		return false
	_cache_positions()
	if id != "ward" and _mp.is_empty():
		return false
	var at := Balance.ARENA_CENTER
	if id == "blast":
		var target := _nearest_target(Balance.ARENA_CENTER)
		at = _pos_of(target)
		for i in range(monsters.size()):
			if at.distance_to(_pos_of(i)) <= Balance.ARENA_BLAST_RADIUS:
				_hurt(i, Balance.ARENA_BLAST_DAMAGE, false, -1, "none", false)
		events.append({"t": "arena_blast", "p": at, "r": Balance.ARENA_BLAST_RADIUS})
	elif id == "freeze":
		for i in range(monsters.size()):
			_slow(i, Balance.ARENA_FREEZE_SLOW, Balance.ARENA_FREEZE_DURATION)
		events.append({"t": "arena_freeze", "p": at, "r": Balance.MAP_RECT.size.length()})
	else:
		shield = Balance.ARENA_WARD_SHIELD
		shield_t = Balance.ARENA_WARD_DURATION
		events.append({"t": "arena_ward", "p": at, "r": Balance.ALTAR_R})
	skill_cooldowns[id] = skill_max_cooldown(id)
	_reap()
	run.autosave()
	return true

func snapshot_arena() -> Dictionary:
	var runtime: Array = []
	for hero in heroes:
		var state: Dictionary = hero.duplicate(true)
		state.erase("h")
		state.erase("st")
		runtime.append(state)
	return {"elapsed": elapsed, "boss_spawned": boss_spawned, "boss_alive": boss_alive, "crystal_hp": crystal_hp,
		"shield": shield, "shield_t": shield_t, "cooldowns": skill_cooldowns.duplicate(), "spawn_t": _spawn_t,
		"serial": _serial, "rng": _rng.state, "curse_t": curse_t, "surge": surge, "surge_t": surge_t,
		"accumulator": _accumulator, "kills": kills, "gold": gold,
		"nav_version": _nav_version,
		"monsters": monsters.duplicate(true), "bullets": bullets.duplicate(true), "zones": zones.duplicate(true),
		"pending": _pending.duplicate(true), "heroes": runtime}

func restore_arena(data: Dictionary) -> void:
	elapsed = float(data["elapsed"])
	boss_spawned = bool(data["boss_spawned"])
	boss_alive = bool(data["boss_alive"])
	crystal_hp = float(data["crystal_hp"])
	shield = float(data["shield"])
	shield_t = float(data["shield_t"])
	skill_cooldowns = data["cooldowns"].duplicate()
	_spawn_t = float(data["spawn_t"])
	_serial = int(data["serial"])
	_rng.state = int(data["rng"])
	curse_t = float(data["curse_t"])
	surge = float(data["surge"])
	surge_t = float(data["surge_t"])
	_accumulator = float(data["accumulator"])
	kills = int(data["kills"])
	gold = int(data["gold"])
	_nav_version = int(data["nav_version"])
	monsters.assign(data["monsters"].duplicate(true))
	bullets.assign(data["bullets"].duplicate(true))
	zones.assign(data["zones"].duplicate(true))
	_pending.assign(data["pending"].duplicate(true))
	for i in range(heroes.size()):
		# Saved runtime cannot override stats recomputed from the owned hero.
		for key in ["cool", "acc", "face", "dmg", "kills", "dw", "dn", "dr", "fx_t", "fx_w", "fx_d"]:
			if data["heroes"][i].has(key):
				heroes[i][key] = data["heroes"][i][key]
	_spawn_route = _serial
	_cache_positions()
	events.clear()
