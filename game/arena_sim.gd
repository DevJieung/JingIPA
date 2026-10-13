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
## Casts spent this run; each skill has Balance.ARENA_*_USES per run on top of its cooldown.
var skill_uses := {"blast": 0, "freeze": 0, "ward": 0}
## The boss gate is drawn ARENA_BOSS_WARNING seconds early so the arena can announce it.
var boss_warned := false
var boss_lane := -1
var _forced_lane := -1
## The run is a chain of stages; each is one battlefield with its own boss.
var stage := 1
## Counts down after a stage boss falls; the next battlefield opens when it reaches 0.
var clear_t := 0.0
## Guardian's blessing: one crystal revival per run, then a short untouchable window.
## Revivals of the Guardian's blessing used in this run (of Balance.ARENA_REVIVE_USES).
var revives := 0
var invuln_t := 0.0
var _nav := AStarGrid2D.new()
var _road_nav := AStarGrid2D.new()
var _road_cells: Array[Vector2i] = []
## Road cells currently closed by a guardian; only these are reopened on a rebuild.
var _guarded_cells: Array[Vector2i] = []
var _nav_key := ""
var _nav_version := 0
var _serial := 0
var _accumulator := 0.0
var _save_t := 0.0
var _spawn_pool: Array = []
var _pool_period := -1
## Static road mask per layout (1 = open cell), shared by every simulator: the roads of
## a layout never change, and building the mask is the costly part of opening a stage.
static var _mask_cache: Dictionary = {}

func setup(run_state, wave_no: int = 1, seed_value: int = 0) -> void:
	super.setup(run_state, wave_no, seed_value)
	crystal_max = Balance.ARENA_CRYSTAL_HP
	crystal_hp = crystal_max
	won = false
	revives = 0
	invuln_t = 0.0
	_serial = 0
	_accumulator = 0.0
	_save_t = 0.0
	for id in skill_cooldowns:
		skill_cooldowns[id] = 0.0
		skill_uses[id] = 0
	_enter_stage(wave_no)

## Open the next battlefield of the same run. The crystal, the skill casts already
## spent, kills and the guardians carry over; everything on the road is cleared.
## ArenaGeometry must already hold the new battlefield's layout.
func begin_stage(number: int) -> void:
	monsters.clear()
	bullets.clear()
	zones.clear()
	_pending.clear()
	events.clear()
	curse_t = 0.0
	surge = 0.0
	surge_t = 0.0
	elapsed = 0.0
	done = false
	_enter_stage(number)
	refresh_heroes()
	announce_stage()

## Tell the view that this stage's battlefield has just been built: it stages the reveal,
## which waits under the battlefield card and runs when the battle starts.
func announce_stage() -> void:
	events.append({"t": "arena_stage", "stage": stage, "p": Balance.ARENA_CENTER})

func _enter_stage(number: int) -> void:
	stage = clampi(number, 1, Balance.ARENA_STAGES)
	wave = stage
	_rank = int(run.theme_rank(stage)) if run != null and run.has_method("theme_rank") else 1
	boss_spawned = false
	boss_alive = false
	boss_warned = false
	boss_lane = -1
	_forced_lane = -1
	clear_t = 0.0
	shield = 0.0
	shield_t = 0.0
	_pool_period = -1
	_spawn_pool.clear()
	_spawn_t = Balance.ARENA_SPAWN_INITIAL
	_build_navigation()

func _build_navigation() -> void:
	_nav = AStarGrid2D.new()
	_road_nav = AStarGrid2D.new()
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
	var mask := _road_mask()
	_road_cells.clear()
	for y in range(_nav.region.size.y):
		for x in range(_nav.region.size.x):
			var cell := Vector2i(x, y)
			var road := mask[y * _nav.region.size.x + x] == 1
			_nav.set_point_solid(cell, not road)
			_road_nav.set_point_solid(cell, not road)
			if road: _road_cells.append(cell)
	_guarded_cells.clear()
	_nav_key = ""
	_nav_version += 1
	_rebuild_navigation()

## Open cells of the current layout's roads.
func _road_mask() -> PackedByteArray:
	var key := "%s|%d" % [ArenaGeometry.layout(), ArenaGeometry.ROAD_REVISION]
	if _mask_cache.has(key): return _mask_cache[key]
	var size := _nav.region.size
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	# A cell is open when its centre is inside the road with a little clearance to
	# spare, so grid edges cannot cut across the inside of a curved road (a 14 unit
	# diagonal on the tightest 75 unit bend dips 0.33). Together with the guardian
	# radius this leaves a 15 unit lane beside a hero standing on the centreline; one
	# cell wide lanes pinch shut on diagonal roads.
	var shallow := {}
	var reach := Balance.ARENA_MONSTER_RADIUS + _nav.cell_size.length() + 0.1
	for y in range(size.y):
		for x in range(size.x):
			var at := _nav.get_point_position(Vector2i(x, y))
			if not ArenaGeometry.on_road(at, Balance.ARENA_MONSTER_RADIUS + 1): continue
			mask[y * size.x + x] = 1
			# Deep cells keep every step to a neighbour inside the road; only cells near
			# a kerb can be part of a notch (below).
			if ArenaGeometry.on_road(at, reach): continue
			var depth := 0
			for margin in [14.0, 17.0, 20.0]:
				if ArenaGeometry.on_road(at, margin): depth += 1
			shallow[Vector2i(x, y)] = depth
	# Where two road shapes meet at an angle (an arm running into the plaza, a feeder
	# into an arm) the kerbs leave a notch thinner than a cell: both neighbours are
	# open, yet the straight step between their centres leaves the road, and a monster
	# sent across it would turn back at the notch for ever. Close the shallower cell
	# of every such pair so that each grid step is a walk the movement rules accept.
	for cell in shallow:
		if mask[cell.y * size.x + cell.x] == 0: continue
		for step in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var other: Vector2i = cell + step
			if not shallow.has(other) or mask[other.y * size.x + other.x] == 0: continue
			var from := _nav.get_point_position(cell)
			var to := _nav.get_point_position(other)
			var samples := ceili(from.distance_to(to) / 1.5)
			var inside := true
			for i in range(1, samples):
				if not ArenaGeometry.on_road(from.lerp(to, float(i) / samples), Balance.ARENA_MONSTER_RADIUS):
					inside = false
					break
			if inside: continue
			var shut: Vector2i = cell if int(shallow[cell]) <= int(shallow[other]) else other
			mask[shut.y * size.x + shut.x] = 0
			if shut == cell: break
	_mask_cache[key] = mask
	return mask

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

## How far the whole run has come (0 at the first spawn, 1 at the last boss). The
## crowd and the spawn pace climb along it, stage after stage.
func run_progress() -> float:
	return clampf((float(stage - 1) + clampf(elapsed / Balance.ARENA_BOSS_AT, 0.0, 1.0)) / float(Balance.ARENA_STAGES), 0.0, 1.0)

func population_limit() -> int:
	return roundi(lerpf(Balance.ARENA_POPULATION_START, Balance.ARENA_POPULATION_MAX, run_progress()))

func spawn_interval() -> float:
	return lerpf(Balance.ARENA_SPAWN_INITIAL, Balance.ARENA_SPAWN_MIN, run_progress())

func final_stage() -> bool:
	return stage >= Balance.ARENA_STAGES

func _spawn(monster: Dictionary) -> void:
	super._spawn(monster)
	var mo: Dictionary = monsters[-1]
	var lane := _forced_lane if _forced_lane >= 0 else _rng.randi_range(0, ArenaGeometry.route_count() - 1)
	var entrance := ArenaGeometry.gate_point(lane, Balance.ARENA_MONSTER_RADIUS)
	var radial := (entrance - Balance.ARENA_CENTER).normalized()
	var point := ArenaGeometry.clamp_point(entrance + Vector2(-radial.y, radial.x) * float(mo["off"]), Balance.ARENA_MONSTER_RADIUS)
	_serial += 1
	mo.merge({"pos": point, "vel": Vector2.ZERO, "blocked": false, "spawn_id": _serial,
		"path": PackedVector2Array(), "nav_v": -1, "siege_t": 0.0})
	mo["route"] = lane
	# Strength and bounty follow the stage, not the legacy wave table.
	var kind := String(mo["kind"])
	mo["hp"] = Balance.arena_hp(stage, _rank) * float(Balance.MKIND[kind]["hp"])
	mo["gold"] = Balance.arena_kill_gold(stage, kind)
	if kind == "boss":
		boss_alive = true
		mo["hp"] = Balance.arena_boss_hp(stage, _rank)
	mo["max"] = mo["hp"]
	events[-1]["p"] = point
	events[-1]["sid"] = _serial

func step(dt: float) -> void:
	if done or not run.running or not String(run.modal).is_empty() or dt <= 0.0:
		return
	_accumulator += minf(dt, 0.25)
	# A stage change opens the next battlefield's card: stop ticking under it.
	while _accumulator >= 1.0 / 60.0 and not done and String(run.modal).is_empty():
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
	invuln_t = maxf(0.0, invuln_t - dt)
	if clear_t > 0.0:
		# The stage boss is down: let the last shots and effects play, then move on.
		clear_t = maxf(0.0, clear_t - dt)
		_cache_positions()
		_move_bullets(dt)
		_step_zones(dt)
		_reap()
		_save_t += dt
		if clear_t == 0.0 and run.running:
			if final_stage():
				won = true
				done = true
				run.end_run(true)
			else:
				run.advance_stage()
		return
	if not boss_spawned and not boss_warned and elapsed >= Balance.ARENA_BOSS_AT - Balance.ARENA_BOSS_WARNING:
		# The gate is decided now so the warning can point at it; the boss then uses it.
		boss_warned = true
		boss_lane = _rng.randi_range(0, ArenaGeometry.route_count() - 1)
		events.append({"t": "arena_boss_warning", "p": boss_gate(), "sec": Balance.ARENA_BOSS_WARNING, "lane": boss_lane, "final": final_stage()})
	if not boss_spawned and elapsed >= Balance.ARENA_BOSS_AT:
		boss_spawned = true
		boss_warned = true
		if boss_lane < 0: boss_lane = _rng.randi_range(0, ArenaGeometry.route_count() - 1)
		_forced_lane = boss_lane
		_spawn(run.boss_for(stage))
		_forced_lane = -1
		events.append({"t": "arena_boss", "p": mpos(monsters[-1]), "sid": int(monsters[-1]["spawn_id"]), "lane": boss_lane, "final": final_stage()})
	elif not boss_spawned:
		_spawn_t -= dt
		if _spawn_t <= 0.0:
			if monsters.size() < population_limit():
				# Two assaults per stage, each with its own mix of the battlefield's monsters.
				var period := int(elapsed / (Balance.ARENA_BOSS_AT * 0.5))
				if period != _pool_period or _spawn_pool.is_empty():
					_pool_period = period
					_spawn_pool = run.stage_spawns(stage, period)
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
	# Cells are solid when their centre is closer than the touching distance plus the
	# 4 unit position rounding (2.83) and the dip of a diagonal chord between two
	# centres at that distance (0.9): every grid path then clears the real radius.
	var radius := Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS + 4.0
	# Only the cells around a guardian can change: reopen the ones closed last time,
	# then close the road cells inside each guardian's footprint. (Scanning every road
	# cell for every hero cost 3 ms per rebuild, and a walking hero rebuilds on most ticks.)
	for cell in _guarded_cells: _nav.set_point_solid(cell, false)
	_guarded_cells.clear()
	var reach := ceili(radius / minf(_nav.cell_size.x, _nav.cell_size.y)) + 1
	for hero in heroes:
		var at: Vector2 = hero["pos"]
		at = (at / 4.0).round() * 4.0
		var centre := _cell(at)
		for y in range(maxi(0, centre.y - reach), mini(_nav.region.size.y, centre.y + reach + 1)):
			for x in range(maxi(0, centre.x - reach), mini(_nav.region.size.x, centre.x + reach + 1)):
				var cell := Vector2i(x, y)
				# The road-only grid is the static mask; anything already closed is either
				# off the road or inside another guardian's footprint.
				if _nav.is_point_solid(cell) or _road_nav.is_point_solid(cell): continue
				if _nav.get_point_position(cell).distance_squared_to(at) < radius * radius:
					_nav.set_point_solid(cell, true)
					_guarded_cells.append(cell)

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
	# Presentation-only facing intent: a hero pushed against a wall or another
	# hero still turns toward where the player pushes.
	hero["fx_d"] = direction.normalized()
	var speed := float(hero.get("speed", Balance.ARENA_HERO_SPEED))
	var requested := current + direction.limit_length() * speed * minf(maxf(dt, 0.0), 0.25)
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
				events.append({"t": "curse", "p": current, "sid": int(mo.get("spawn_id", 0))})
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
	events.append({"t": "push", "p": mpos(mo), "h": float(mo["h"]), "sid": int(mo.get("spawn_id", 0))})

func _damage_crystal(damage: float, at: Vector2) -> void:
	if invuln_t > 0.0 or clear_t > 0.0:
		return
	if run.has("bulwark") and _rng.randf() < Balance.PASSIVE_BULWARK_P:
		events.append({"t": "block", "p": at, "h": 35.0})
		return
	var absorbed := minf(shield, damage)
	shield -= absorbed
	crystal_hp = maxf(0.0, crystal_hp - damage + absorbed)
	run.lives = ceili(crystal_hp / crystal_max * Balance.MAX_LIVES)
	events.append({"t": "arena_crystal_hit", "p": Balance.ARENA_CENTER, "n": damage - absorbed})
	if crystal_hp <= 0.0:
		if run.has_method("revive_ready") and run.revive_ready():
			revive()
			return
		done = true
		run.end_run(false)

## Revivals the Guardian's blessing can still give in this run.
func revives_left() -> int:
	return maxi(0, Balance.ARENA_REVIVE_USES - revives)

## Guardian's blessing: the broken crystal reforms, up to ARENA_REVIVE_USES times per
## run. It comes back at ARENA_REVIVE_HP of its maximum, cannot be hurt for
## ARENA_REVIVE_INVULN seconds, its shockwave stops every monster on the field for
## ARENA_REVIVE_STUN seconds, and the run is handed arena_revive_gold() to rebuild with.
func revive() -> void:
	revives += 1
	done = false
	crystal_hp = crystal_max * Balance.ARENA_REVIVE_HP
	run.lives = ceili(crystal_hp / crystal_max * Balance.MAX_LIVES)
	invuln_t = Balance.ARENA_REVIVE_INVULN
	for mo in monsters:
		if float(mo["hp"]) <= 0.0: continue
		mo["stun_t"] = maxf(float(mo["stun_t"]), Balance.ARENA_REVIVE_STUN)
		mo["siege_t"] = 0.0
	var purse := Balance.arena_revive_gold(stage)
	run.add_gold(purse)
	events.append({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS,
		"sec": Balance.ARENA_REVIVE_INVULN, "stun": Balance.ARENA_REVIVE_STUN,
		"gold": purse, "left": revives_left()})

func _reap() -> void:
	var boss_dead := false
	for mo in monsters:
		if String(mo["kind"]) == "boss" and float(mo["hp"]) <= 0.0:
			boss_dead = true
	super._reap()
	if not boss_dead or not run.running or clear_t > 0.0:
		return
	boss_alive = false
	# The stage is won: its escort scatters without bounty and the crystal mends a little.
	# The last boss gets the same beat, so its fall is seen before the run ends in victory.
	for mo in monsters:
		events.append({"t": "die", "p": mpos(mo), "c": Color(String(mo["m"]["color"])),
			"h": float(mo["h"]), "gold": 0, "sid": int(mo.get("spawn_id", 0)), "scatter": true})
	monsters.clear()
	_pending.clear()
	for bullet in bullets:
		bullet["tgt"] = -1
		bullet["hit"] = []
	_cache_positions()
	var mended := minf(crystal_max - crystal_hp, crystal_max * Balance.ARENA_STAGE_HEAL)
	crystal_hp += mended
	run.lives = ceili(crystal_hp / crystal_max * Balance.MAX_LIVES)
	clear_t = Balance.ARENA_CLEAR_DELAY
	events.append({"t": "arena_stage_clear", "p": Balance.ARENA_CENTER, "stage": stage,
		"heal": mended, "sec": Balance.ARENA_CLEAR_DELAY, "final": final_stage()})
	run.stage_cleared(stage)

## Logical point where the boss will step onto the field (the chosen gate), or INF before it is known.
func boss_gate() -> Vector2:
	if boss_lane < 0: return Vector2.INF
	return ArenaGeometry.gate_point(boss_lane, Balance.ARENA_MONSTER_RADIUS)

func skill_max_uses(id: String) -> int:
	match id:
		"blast": return Balance.ARENA_BLAST_USES
		"freeze": return Balance.ARENA_FREEZE_USES
		"ward": return Balance.ARENA_WARD_USES
	return 0

func skill_uses_left(id: String) -> int:
	return maxi(0, skill_max_uses(id) - int(skill_uses.get(id, 0)))

func skill_max_cooldown(id: String) -> float:
	match id:
		"blast": return Balance.ARENA_BLAST_COOLDOWN
		"freeze": return Balance.ARENA_FREEZE_COOLDOWN
		"ward": return Balance.ARENA_WARD_COOLDOWN
	return 0.0

func cast_skill(id: String) -> bool:
	if done or not run.running or not String(run.modal).is_empty() or not skill_cooldowns.has(id) or float(skill_cooldowns[id]) > 0.0:
		return false
	if clear_t > 0.0 or skill_uses_left(id) <= 0:
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
	skill_uses[id] = int(skill_uses.get(id, 0)) + 1
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
	return {"road_revision": ArenaGeometry.ROAD_REVISION, "layout": ArenaGeometry.layout(),
		"stage": stage, "clear_t": clear_t, "revives": revives, "invuln_t": invuln_t,
		"elapsed": elapsed, "boss_spawned": boss_spawned, "boss_alive": boss_alive, "crystal_hp": crystal_hp,
		"shield": shield, "shield_t": shield_t, "cooldowns": skill_cooldowns.duplicate(), "uses": skill_uses.duplicate(),
		"boss_warned": boss_warned, "boss_lane": boss_lane, "spawn_t": _spawn_t,
		"serial": _serial, "rng": _rng.state, "curse_t": curse_t, "surge": surge, "surge_t": surge_t,
		"accumulator": _accumulator, "kills": kills, "gold": gold,
		"nav_version": _nav_version,
		"monsters": monsters.duplicate(true), "bullets": bullets.duplicate(true), "zones": zones.duplicate(true),
		"pending": _pending.duplicate(true), "heroes": runtime}

func restore_arena(data: Dictionary, migrate_roads: bool = false) -> void:
	clear_t = float(data.get("clear_t", 0.0))
	# Saves made while the blessing was a single revival carry a flag instead of a count.
	revives = clampi(int(data.get("revives", 1 if bool(data.get("revived", false)) else 0)), 0, Balance.ARENA_REVIVE_USES)
	invuln_t = float(data.get("invuln_t", 0.0))
	elapsed = float(data["elapsed"])
	boss_spawned = bool(data["boss_spawned"])
	boss_alive = bool(data["boss_alive"])
	crystal_hp = float(data["crystal_hp"])
	shield = float(data["shield"])
	shield_t = float(data["shield_t"])
	skill_cooldowns = data["cooldowns"].duplicate()
	# Runs saved before the per-run limit (2026-10-12) start it fresh.
	for id in skill_uses:
		skill_uses[id] = int(data.get("uses", {}).get(id, 0))
	boss_warned = bool(data.get("boss_warned", boss_spawned))
	boss_lane = int(data.get("boss_lane", -1))
	_forced_lane = -1
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
