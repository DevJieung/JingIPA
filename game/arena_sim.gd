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
var _road_nav := AStarGrid2D.new()
var _road_cells: Array[Vector2i] = []
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
	_nav.region = Rect2i(Vector2i.ZERO, Vector2i(ceili(ArenaGeometry.MAP_RECT.size.x / Balance.ARENA_NAV_CELL), ceili(ArenaGeometry.MAP_RECT.size.y / Balance.ARENA_NAV_CELL)))
	_nav.cell_size = ArenaGeometry.MAP_RECT.size / Vector2(_nav.region.size)
	_nav.offset = ArenaGeometry.MAP_RECT.position + _nav.cell_size * 0.5
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.update()
	_road_nav.region = _nav.region
	_road_nav.cell_size = _nav.cell_size
	_road_nav.offset = _nav.offset
	_road_nav.diagonal_mode = _nav.diagonal_mode
	_road_nav.update()
	_road_cells.clear()
	for y in range(_nav.region.size.y):
		for x in range(_nav.region.size.x):
			var cell := Vector2i(x, y)
			# Reserve a little clearance so grid edges cannot cut across the inside
			# of a curved road. The static mask is computed once, not every frame.
			var road := ArenaGeometry.on_road(_nav.get_point_position(cell), Balance.ARENA_MONSTER_RADIUS + 3)
			_nav.set_point_solid(cell, not road)
			_road_nav.set_point_solid(cell, not road)
			if road: _road_cells.append(cell)
	_nav_key = ""
	_rebuild_navigation()

func projectile_bounds() -> Rect2:
	return ArenaGeometry.MAP_RECT.grow(80)

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
	var lane := _rng.randi_range(0, ArenaGeometry.ROUTE_COUNT - 1)
	var path := ArenaGeometry.route_points(lane)
	var radial := (path[0] - Balance.ARENA_CENTER).normalized()
	var entrance := Balance.ARENA_CENTER + radial * (ArenaGeometry.RADIUS - Balance.ARENA_MONSTER_RADIUS)
	var point := ArenaGeometry.clamp_point(entrance + Vector2(-radial.y, radial.x) * float(mo["off"]), Balance.ARENA_MONSTER_RADIUS)
	_serial += 1
	mo.merge({"pos": point, "vel": Vector2.ZERO, "blocked": false, "spawn_id": _serial,
		"path": PackedVector2Array(), "nav_v": -1, "siege_t": 0.0})
	mo["route"] = lane
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
	var local := (point - ArenaGeometry.MAP_RECT.position) / _nav.cell_size
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
	for cell in _road_cells:
		var p := _nav.get_point_position(cell)
		var solid := false
		for hero in heroes:
			var at: Vector2 = hero["pos"]
			at = (at / 4.0).round() * 4.0
			if p.distance_squared_to(at) < radius * radius:
				solid = true
				break
		_nav.set_point_solid(cell, solid)

func _road_segment_clear(from: Vector2, to: Vector2, margin: float = Balance.ARENA_MONSTER_RADIUS) -> bool:
	var samples := maxi(1, ceili(from.distance_to(to) / 6.0))
	for i in range(samples + 1):
		if not ArenaGeometry.on_road(from.lerp(to, float(i) / samples), margin):
			return false
	return true

func _segment_clear(from: Vector2, to: Vector2, road_margin: float = Balance.ARENA_MONSTER_RADIUS) -> bool:
	if not _road_segment_clear(from, to, road_margin):
		return false
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
	var fallback := PackedVector2Array()
	for cell in candidates:
		var path := _nav.get_point_path(cell, end)
		if not path.is_empty():
			return _join_path(from, path)
		if fallback.is_empty():
			fallback = _road_nav.get_point_path(cell, end)
	# A distant guardian can seal a lane. Follow the road up to that guardian;
	# every movement segment still checks the real collision radius. A partial
	# AStar path instead stops at the point closest to the crystal, which can be
	# hundreds of units before an obstruction on the far side of an S bend.
	return _join_path(from, fallback, false)

func _join_path(from: Vector2, path: PackedVector2Array, avoid_heroes: bool = true) -> PackedVector2Array:
	# Join ahead of the nearest grid centre when visible. Replanning must not
	# pull a moving enemy back to a cell it has already passed.
	# Half the road-sampling interval covers the gaps between samples. Without
	# this clearance a shortcut can graze a bend and fail during actual movement.
	var margin := Balance.ARENA_MONSTER_RADIUS + 3.0
	while path.size() > 1:
		if not (_segment_clear(from, path[1], margin) if avoid_heroes else _road_segment_clear(from, path[1], margin)):
			break
		path.remove_at(0)
	return path

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
	requested = ArenaGeometry.clamp_point(requested, Balance.ARENA_HERO_RADIUS)
	var accepted := current
	for point in [requested, Vector2(requested.x, current.y), Vector2(current.x, requested.y)]:
		if not ArenaGeometry.contains(point, Balance.ARENA_HERO_RADIUS): continue
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
			var push_to := current - ArenaGeometry.road_direction(current) * pushed
			if _segment_clear(current, push_to):
				current = push_to
				mo["pos"] = current
				mo["nav_v"] = -1
		var stop := Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS
		if current.distance_to(Balance.ARENA_CENTER) <= stop:
			mo["siege_t"] = float(mo["siege_t"]) + dt
			if float(mo["siege_t"]) >= 1.0:
				mo["siege_t"] = float(mo["siege_t"]) - 1.0
				_damage_crystal(Balance.ARENA_CRYSTAL_DPS * float(mo["crush"]), current)
			if not run.running:
				return
			continue
		var path: PackedVector2Array = mo["path"]
		var had_path := not path.is_empty()
		while not path.is_empty() and current.distance_to(path[0]) <= 0.1:
			path.remove_at(0)
		var navigation_changed := int(mo["nav_v"]) != _nav_version
		var obstructed := not path.is_empty() and not _segment_clear(current, current.move_toward(path[0], speed * dt))
		var needs_path := obstructed or (path.is_empty() and (navigation_changed or had_path))
		if needs_path:
			path = _path_from(current, Balance.ARENA_CENTER)
			while not path.is_empty() and current.distance_to(path[0]) <= 0.1:
				path.remove_at(0)
		# Keep the next valid waypoint through unrelated hero movement. Resetting
		# every path on every navigation revision causes visible stalls/backsteps.
		mo["nav_v"] = _nav_version
		mo["path"] = path
		if path.is_empty():
			mo["blocked"] = true
			continue
		var target := path[0]
		var next := current.move_toward(target, speed * dt)
		if needs_path and not _segment_clear(current, next):
			mo["blocked"] = true
			mo["path"] = PackedVector2Array()
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
		events.append({"t": "arena_freeze", "p": at, "r": ArenaGeometry.MAP_RECT.size.length()})
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
	return {"road_revision": ArenaGeometry.ROAD_REVISION,
		"elapsed": elapsed, "boss_spawned": boss_spawned, "boss_alive": boss_alive, "crystal_hp": crystal_hp,
		"shield": shield, "shield_t": shield_t, "cooldowns": skill_cooldowns.duplicate(), "spawn_t": _spawn_t,
		"serial": _serial, "rng": _rng.state, "curse_t": curse_t, "surge": surge, "surge_t": surge_t,
		"accumulator": _accumulator, "kills": kills, "gold": gold,
		"nav_version": _nav_version,
		"monsters": monsters.duplicate(true), "bullets": bullets.duplicate(true), "zones": zones.duplicate(true),
		"pending": _pending.duplicate(true), "heroes": runtime}

func restore_arena(data: Dictionary, migrate_roads: bool = false) -> void:
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
	# Previous builds could save an empty path after grazing a road edge, with
	# the current navigation version. Retry it once without waiting for a hero.
	for mo in monsters:
		if mo["path"].is_empty():
			mo["nav_v"] = -1
	if migrate_roads or int(data.get("road_revision", 1)) != ArenaGeometry.ROAD_REVISION:
		for mo in monsters:
			if not ArenaGeometry.on_road(mo["pos"], Balance.ARENA_MONSTER_RADIUS):
				mo["pos"] = ArenaGeometry.nearest_road_point(mo["pos"])
			mo["path"] = PackedVector2Array()
			mo["nav_v"] = -1
			mo["vel"] = Vector2.ZERO
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
