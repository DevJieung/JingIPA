extends BattleSim
class_name ArenaSim

## Continuous battle on the ground plane of the real 3D world.
## Position, navigation, timers and damage belong here; renderers only read them.
## 2026-10-19 (docs/STAGE_LADDER_2026-10-19.md): a stage is fought in waves. Each wave spawns a fixed
## list (ArenaRun.wave_spawns) and ends when all of it is down; a preparation phase follows, in which
## nothing spawns and only then summons and level-up picks open. Wave 5 brings an elite, the last wave
## the boss with its escort. Hellbound runs the same machine with no last wave (waves_total() == 0).
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
## The ladder stage (1..Balance.ARENA_LADDER); one battlefield with its own boss.
var stage := 1
## Counts down after the stage boss falls; the stage is won when it reaches 0.
var clear_t := 0.0
## True while the tick is inside the clear beat (including its last tick, when clear_t has
## just reached 0): no level-up popup may open there, the result is about to.
var _clearing := false
## The wave being fought, or the one the current preparation leads to (1-based).
var wave_no := 1
## Preparation phase (between waves): nothing spawns, prep_t counts down while no window is open
## (step() stops under modals) and skip_prep() ends it. The public question is in_prep().
var preparing := true
var prep_t := 0.0
## Seconds since the current wave started (0 in preparation).
var wave_t := 0.0
## The current wave's spawn list ({"m", "elite"} entries) and how much of it has spawned. The list is
## not saved: ArenaRun.wave_spawns gives the same list again on restore.
var _wave_list: Array = []
var _wave_spawned := 0
## True while a tick runs (a revival's hero then waits for its end, _flush_revive).
var _ticking := false
var _revive_pending := false
## The battlefield's walking pace (pace(), Balance.ARENA_ROAD_PACE), set when a stage opens.
var _pace := 1.0
## Guardian's blessing: one crystal revival per run, then a short untouchable window.
## Revivals of the Guardian's blessing used in this run (of Balance.ARENA_REVIVE_USES).
var revives := 0
var invuln_t := 0.0
var _nav := AStarGrid2D.new()
var _road_nav := AStarGrid2D.new()
## The C++ navigation kernels (StellarArenaNav, docs/PERF_NATIVE.md) over the same two
## grids, or null without the library: then the *_script functions below answer.
var _native_nav = null
var _road_cells: Array[Vector2i] = []
## Road cells currently closed by a guardian; only these are reopened on a rebuild.
var _guarded_cells: Array[Vector2i] = []
var _nav_key := ""
var _nav_version := 0
var _serial := 0
var _accumulator := 0.0
## Simulated seconds since the last periodic autosave. The save itself is due on the real
## clock (O8d, 2026-10-19): every AUTOSAVE_REAL seconds of play at any battle speed, so the
## threshold is that many seconds times the speed (Save.speed is the 1-3x the screen runs).
## At 3x the old 5 sim-second cadence wrote the whole run every 1.67 s. Skill casts still
## save at once (cast_skill) and Save flushes on pause/background (core/save.gd).
var _save_t := 0.0
const AUTOSAVE_REAL := 12.0
## jump_to_boss() leaves this much of the boss wave's preparation: two ticks (warning, then the boss).
const JUMP_LEAD := 2.0 / 60.0
## Static road mask per layout (1 = open cell), shared by every simulator: the roads of
## a layout never change, and building the mask is the costly part of opening a stage.
static var _mask_cache: Dictionary = {}

func setup(run_state, stage_no: int = 1, seed_value: int = 0) -> void:
	# 공중 몬스터·대공 규칙은 연속 수호전의 것이다(BattleSim.air_rules).
	air_rules = true
	super.setup(run_state, stage_no, seed_value)
	crystal_max = Balance.ARENA_CRYSTAL_HP
	crystal_hp = crystal_max
	won = false
	revives = 0
	invuln_t = 0.0
	_serial = 0
	_accumulator = 0.0
	_save_t = 0.0
	_ticking = false
	_revive_pending = false
	for id in skill_cooldowns:
		skill_cooldowns[id] = 0.0
		skill_uses[id] = 0
	_enter_stage(stage_no)

## Rebuild the field for a stage on this simulator (benches and tools; a ladder stage is a fresh run).
## The crystal, the skill casts already spent, kills and the guardians stay; everything on the road is
## cleared and the stage starts at its first preparation. ArenaGeometry must already hold the layout.
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
## How much faster monsters walk on this battlefield than PATH_SPEED x their kind's speed: its longest road
## over Balance.ARENA_ROAD_PACE, at least 1 (short roads keep the normal pace). The walk clock (motion_t)
## counts distance, so the feet stay planted.
func pace() -> float:
	return _pace

func _update_pace() -> void:
	var longest := 0.0
	for lane in range(ArenaGeometry.route_count()):
		longest = maxf(longest, ArenaGeometry.route_length(lane))
	_pace = maxf(1.0, longest / Balance.ARENA_ROAD_PACE) if Balance.ARENA_ROAD_PACE > 0.0 else 1.0

func announce_stage() -> void:
	events.append({"t": "arena_stage", "stage": stage, "p": Balance.ARENA_CENTER})

func _enter_stage(number: int) -> void:
	stage = clampi(number, 1, Balance.ARENA_LADDER)
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
	wave_no = 1
	_enter_prep(Balance.ARENA_PREP_FIRST)
	_build_navigation()
	_update_pace()

## A preparation phase before wave_no. ★ _spawn_t is set here and nowhere at the wave's start: a check
## that freezes spawns with `_spawn_t = 1e9` keeps them frozen, and its wave never completes.
func _enter_prep(seconds: float) -> void:
	preparing = true
	prep_t = maxf(0.0, seconds)
	wave_t = 0.0
	_wave_spawned = 0
	_spawn_t = 0.0
	_wave_list = run.wave_spawns(stage, wave_no) if run != null and run.has_method("wave_spawns") else []
	if is_boss_wave(wave_no):
		boss_spawned = false
		boss_alive = false
		boss_warned = false
		boss_lane = -1

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
	_native_nav = Native.make("StellarArenaNav")
	if _native_nav != null and ArenaGeometry.native() != null:
		_native_nav.setup(ArenaGeometry.native(), _nav, _road_nav, ArenaGeometry.MAP_RECT, Balance.ARENA_HERO_RADIUS, Balance.ARENA_MONSTER_RADIUS, 6.0)
	else:
		_native_nav = null
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
	var mask: PackedByteArray = _native_nav.road_mask(Balance.ARENA_MONSTER_RADIUS) if _native_nav != null else _road_mask_script()
	_mask_cache[key] = mask
	return mask

## The mask as the GDScript computes it: the reference the native kernel must match.
func _road_mask_script() -> PackedByteArray:
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
	_apply_crystal_mods()
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

## 별자리 「단단한 수정」·「성벽의 별」: 수정의 최대 체력이 배수로 는다. 늘어난 만큼은 그 자리에서
## 채워 주고(막 고른 노드가 바로 보이게), 줄어드는 일은 없다(노드는 되돌리지 않는다).
func _apply_crystal_mods() -> void:
	var wanted := Balance.ARENA_CRYSTAL_HP * _mod("crystal")
	if is_equal_approx(wanted, crystal_max):
		return
	if wanted > crystal_max and crystal_hp > 0.0:
		crystal_hp += wanted - crystal_max
	crystal_max = wanted
	crystal_hp = minf(crystal_hp, crystal_max)
	run.lives = ceili(crystal_hp / crystal_max * Balance.MAX_LIVES)

## 수정을 최대치의 `fraction` 만큼 채운다(별자리 「응급 처치」 등). 돌려주는 값은 실제로 찬 양.
func heal_crystal(fraction: float) -> float:
	if crystal_hp <= 0.0:
		return 0.0
	var mended := minf(crystal_max - crystal_hp, crystal_max * maxf(0.0, fraction))
	crystal_hp += mended
	run.lives = ceili(crystal_hp / crystal_max * Balance.MAX_LIVES)
	if mended > 0.0:
		events.append({"t": "arena_heal", "p": Balance.ARENA_CENTER, "n": mended})
	return mended

# --------------------------------------------------------------------------- #
# Waves (2026-10-19): the screens read these (PLAN §4)
# --------------------------------------------------------------------------- #
## Waves in this stage: Balance.ARENA_WAVES, or 0 for endless waves (Hellbound: run.hell).
func waves_total() -> int:
	return 0 if run != null and bool(run.get("hell")) else Balance.ARENA_WAVES

func in_prep() -> bool:
	return preparing

func prep_left() -> float:
	return prep_t if preparing else 0.0

## The full length of the current preparation (the HUD draws prep_left against it): Balance.arena_prep.
func prep_total() -> float:
	return Balance.arena_prep(wave_no, waves_total())

## Monsters of this wave not yet down: waiting to spawn plus alive.
func wave_left() -> int:
	var alive := 0
	for mo in monsters:
		if float(mo["hp"]) > 0.0: alive += 1
	return maxi(0, _wave_list.size() - _wave_spawned) + alive

func wave_size() -> int:
	return _wave_list.size()

## The last wave that started (for Hellbound's record): the one being fought, or the one just held while
## its next preparation runs.
func wave_reached() -> int:
	return maxi(0, wave_no - 1) if preparing else wave_no

## Hellbound's difficulty: wave w stands for a ladder stage (Balance.arena_hell_stage), its ramp inside a
## wave block repeats every ARENA_WAVES waves, and the health is Balance.arena_hell_hp(w) thicker
## (ARENA_HELL_HP, growing ARENA_HELL_HP_GROW a wave). The ladder uses its own stage and wave.
func _hp_stage() -> int:
	return Balance.arena_hell_stage(wave_no) if waves_total() == 0 else stage

func _hp_wave() -> int:
	return Balance.arena_hell_ramp_wave(wave_no) if waves_total() == 0 else wave_no

func _hp_mult() -> float:
	return Balance.arena_hell_hp(wave_no) if waves_total() == 0 else 1.0

func is_elite_wave(w: int) -> bool:
	return Balance.arena_elite_wave(w, waves_total())

func is_boss_wave(w: int) -> bool:
	return Balance.arena_boss_wave(w, waves_total())

## Whether this stage's boss ends the run when it falls — every ladder stage's boss does (the stage
## is won); endless waves have none. (Until 2026-10-19 this meant the tenth stage of a ten-stage run.)
func final_stage() -> bool:
	return waves_total() > 0

## The last stage of a ladder chapter: its boss is a chapter boss (the final boss look in the events'
## `final`, and Balance.ARENA_FINAL_BOSS_HP).
func chapter_boss() -> bool:
	return waves_total() > 0 and run != null and run.has_method("chapter_stage") and bool(run.chapter_stage(stage))

## 「바로 시작」 (and the auto-play, tests): end the preparation now. Before the boss wave the boss is still
## announced: the countdown drops only to Balance.ARENA_BOSS_WARNING while the warning is to come.
func skip_prep() -> bool:
	if not preparing or done or clear_t > 0.0:
		return false
	var floor_t := 0.0
	if is_boss_wave(wave_no) and not boss_warned:
		floor_t = minf(prep_t, Balance.ARENA_BOSS_WARNING)
	prep_t = floor_t
	return true

## Tests and tools: open wave n now, skipping the preparation before it. Monsters already on the field
## stay. The first of its list spawns on the next tick.
func begin_wave(n: int) -> void:
	wave_no = maxi(1, n) if waves_total() == 0 else clampi(n, 1, waves_total())
	_enter_prep(0.0)
	if is_boss_wave(wave_no):
		boss_lane = _rng.randi_range(0, ArenaGeometry.route_count() - 1)
		boss_warned = true
	_start_wave()

## Tests and previews: the end of the boss wave's preparation, where `elapsed = ARENA_BOSS_AT - 0.02`
## used to jump — the next tick announces the boss and the one after brings it. Monsters stay.
func jump_to_boss() -> void:
	var total := waves_total()
	wave_no = total if total > 0 else (wave_no / Balance.ARENA_WAVES + 1) * Balance.ARENA_WAVES
	_enter_prep(JUMP_LEAD)

func _tick_prep(dt: float) -> void:
	prep_t = maxf(0.0, prep_t - dt)
	if is_boss_wave(wave_no) and not boss_warned and prep_t <= Balance.ARENA_BOSS_WARNING:
		# The gate is decided now so the warning can point at it; the boss then uses it.
		boss_warned = true
		boss_lane = _rng.randi_range(0, ArenaGeometry.route_count() - 1)
		events.append({"t": "arena_boss_warning", "p": boss_gate(), "sec": prep_t, "lane": boss_lane, "final": chapter_boss()})
	if prep_t <= 0.0:
		_start_wave()

func _start_wave() -> void:
	preparing = false
	prep_t = 0.0
	wave_t = 0.0
	if is_boss_wave(wave_no) and boss_lane < 0:
		boss_lane = _rng.randi_range(0, ArenaGeometry.route_count() - 1)
		boss_warned = true
	events.append({"t": "arena_wave", "p": Balance.ARENA_CENTER, "wave": wave_no, "total": waves_total(),
		"elite": is_elite_wave(wave_no), "boss": is_boss_wave(wave_no)})

## The next monster of the wave's list. The boss steps in at the gate the warning named.
func _spawn_next() -> void:
	var entry: Dictionary = _wave_list[_wave_spawned]
	_wave_spawned += 1
	var row: Dictionary = entry["m"]
	if String(row["kind"]) == "boss":
		boss_spawned = true
		boss_warned = true
		if boss_lane < 0: boss_lane = _rng.randi_range(0, ArenaGeometry.route_count() - 1)
		_forced_lane = boss_lane
		_spawn(row)
		_forced_lane = -1
		events.append({"t": "arena_boss", "p": mpos(monsters[-1]), "sid": int(monsters[-1]["spawn_id"]), "lane": boss_lane, "final": chapter_boss()})
		return
	_spawn(row)
	if bool(entry.get("elite", false)):
		_make_elite(monsters[-1])
		events.append({"t": "arena_elite", "p": mpos(monsters[-1]), "sid": int(monsters[-1]["spawn_id"])})

## An elite (PLAN M6): the same monster with the elite mark, its health, bounty and (in _reap) experience
## multiplied. The look is StellarModels.elite.
func _make_elite(mo: Dictionary) -> void:
	mo["elite"] = true
	mo["hp"] = Balance.arena_elite_hp(_hp_stage(), _rank, _hp_wave(), String(mo["kind"])) * _hp_mult()
	mo["max"] = mo["hp"]
	mo["gold"] = roundi(float(mo["gold"]) * Balance.ARENA_ELITE_GOLD)

func _spawn(monster: Dictionary) -> void:
	super._spawn(monster)
	var mo: Dictionary = monsters[-1]
	var lane := _forced_lane if _forced_lane >= 0 else _rng.randi_range(0, ArenaGeometry.route_count() - 1)
	var entrance := ArenaGeometry.gate_point(lane, Balance.ARENA_MONSTER_RADIUS)
	var radial := (entrance - Balance.ARENA_CENTER).normalized()
	var point := ArenaGeometry.clamp_point(entrance + Vector2(-radial.y, radial.x) * float(mo["off"]), Balance.ARENA_MONSTER_RADIUS)
	_serial += 1
	mo.merge({"pos": point, "vel": Vector2.ZERO, "blocked": false, "spawn_id": _serial,
		"path": PackedVector2Array(), "nav_v": -1, "siege_t": 0.0, "elite": false, "block_t": 0.0})
	mo["route"] = lane
	# Strength and bounty follow the ladder stage and the wave, not the legacy wave table.
	var kind := String(mo["kind"])
	mo["hp"] = Balance.arena_hp(_hp_stage(), _rank, _hp_wave()) * float(Balance.MKIND[kind]["hp"]) * _hp_mult()
	mo["gold"] = Balance.arena_ladder_gold(stage, kind)
	if kind == "boss":
		boss_alive = true
		mo["hp"] = Balance.arena_ladder_boss_hp(_hp_stage(), _rank, _hp_wave(), chapter_boss()) * _hp_mult()
	mo["max"] = mo["hp"]
	events[-1]["p"] = point
	events[-1]["sid"] = _serial

func step(dt: float) -> void:
	if done or not run.running or not String(run.modal).is_empty() or dt <= 0.0:
		return
	_accumulator += minf(dt, 0.25)
	# A window opened by a tick (a level-up at the start of a preparation, the result) stops the
	# ticks under it at once — the preparation countdown included.
	while _accumulator >= 1.0 / 60.0 and not done and String(run.modal).is_empty():
		_tick(1.0 / 60.0)
		_accumulator -= 1.0 / 60.0
	if _save_t >= AUTOSAVE_REAL * clampf(Save.speed, 1.0, 3.0) and run.running:
		_save_t = 0.0
		run.autosave()

func _tick(dt: float) -> void:
	_ticking = true
	_tick_body(dt)
	_ticking = false
	# A revival during the tick (the crystal broke in _move_monsters): its hero joins now, between ticks.
	_flush_revive()

func _tick_body(dt: float) -> void:
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
		# The stage boss is down: let the last shots and effects play, then the stage is won.
		clear_t = maxf(0.0, clear_t - dt)
		_clearing = true
		_cache_positions()
		_move_bullets(dt)
		_step_zones(dt)
		_reap()
		_clearing = false
		_save_t += dt
		if clear_t == 0.0 and run.running and final_stage():
			won = true
			done = true
			run.end_run(true)
		return
	# Levels earned during a wave wait for the preparation phase (_offer_levelup refuses before).
	if int(run.get("pending_levels")) > 0 and _offer_levelup():
		return
	if preparing:
		_tick_prep(dt)
	if not preparing:
		wave_t += dt
		# The countdown runs only while the list has bodies left: once all are out it rests at the last gap
		# (it used to run on below zero, and a save made then failed ArenaValidation — LA4 fix).
		if _wave_spawned < _wave_list.size():
			_spawn_t -= dt
			if _spawn_t <= 0.0:
				_spawn_next()
				_spawn_t = Balance.arena_wave_gap(stage, wave_no)
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
	if _native_nav != null: return _native_nav.road_segment_clear(from, to, margin)
	return _road_segment_clear_script(from, to, margin)

func _road_segment_clear_script(from: Vector2, to: Vector2, margin: float = Balance.ARENA_MONSTER_RADIUS) -> bool:
	var samples := maxi(1, ceili(from.distance_to(to) / 6.0))
	for i in range(samples + 1):
		if not ArenaGeometry.on_road(from.lerp(to, float(i) / samples), margin):
			return false
	return true

func _segment_clear(from: Vector2, to: Vector2, road_margin: float = Balance.ARENA_MONSTER_RADIUS) -> bool:
	if _native_nav != null: return _native_nav.segment_clear(from, to, road_margin)
	return _segment_clear_script(from, to, road_margin)

func _segment_clear_script(from: Vector2, to: Vector2, road_margin: float = Balance.ARENA_MONSTER_RADIUS) -> bool:
	if not _road_segment_clear_script(from, to, road_margin):
		return false
	var radius := Balance.ARENA_HERO_RADIUS + Balance.ARENA_MONSTER_RADIUS
	for hero in heroes:
		var p: Vector2 = hero["pos"]
		var near := Geometry2D.get_closest_point_to_segment(p, from, to)
		if near.distance_squared_to(p) < radius * radius:
			return false
	return true

## ★ `fly` — 공중 몬스터의 길. 도로만 따르고 수호자의 몸은 보지 않는다(_road_nav 격자):
##   그 위를 날아 넘어가므로 길막이 안 된다. 2026-10-17 사용자 규칙의 짝이다 — 총·활만
##   맞힐 수 있는 대신 몸으로 세울 수도 없다.
## ★ 2026-10-19 피드백 F4 · PLAN M5: 보스와 정예도 이 길로 걷는다 — 공중 몬스터가 날아 넘듯 수호자의
##   몸을 지나간다(_move_monsters 의 ghost). 몸으로는 막을 수 없지만 땅 위 목표라 모든 영웅이 때리고
##   장판도 맞는다(mo.fly 는 건드리지 않는다). 일반 몬스터도 ARENA_BLOCK_BREAK 초 넘게 막히면 지나간다.
func _path_from(from: Vector2, target: Vector2, fly: bool = false) -> PackedVector2Array:
	if _native_nav != null: return _native_nav.path_from(from, target, fly)
	return _path_from_script(from, target, fly)

## The path as the GDScript plans it: the reference the native kernel must match.
func _path_from_script(from: Vector2, target: Vector2, fly: bool = false) -> PackedVector2Array:
	if fly:
		if not _road_segment_clear_script(from, from):
			return PackedVector2Array()
		var fstart := _cell(from)
		var fend := _cell(target)
		var fcandidates: Array[Vector2i] = []
		for y in range(fstart.y - 1, fstart.y + 2):
			for x in range(fstart.x - 1, fstart.x + 2):
				var cell := Vector2i(x, y)
				if _road_nav.region.has_point(cell) and not _road_nav.is_point_solid(cell) and _road_segment_clear_script(from, _road_nav.get_point_position(cell)):
					fcandidates.append(cell)
		fcandidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return from.distance_squared_to(_road_nav.get_point_position(a)) < from.distance_squared_to(_road_nav.get_point_position(b)))
		for cell in fcandidates:
			var fpath := _road_nav.get_point_path(cell, fend)
			if not fpath.is_empty():
				return _join_path(from, fpath, false)
		return PackedVector2Array()
	# A coarse blocked cell can contain a collision-free starting point.
	# Enter a visible free neighbour rather than trapping the enemy forever.
	if not _segment_clear_script(from, from):
		return PackedVector2Array()
	var start := _cell(from)
	var end := _cell(target)
	var candidates: Array[Vector2i] = []
	for y in range(start.y - 1, start.y + 2):
		for x in range(start.x - 1, start.x + 2):
			var cell := Vector2i(x, y)
			if _nav.region.has_point(cell) and not _nav.is_point_solid(cell) and _segment_clear_script(from, _nav.get_point_position(cell)):
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
		if not (_segment_clear_script(from, path[1], margin) if avoid_heroes else _road_segment_clear_script(from, path[1], margin)):
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
	if _native_nav != null:
		# The guardians the native segment tests must see: their positions this tick.
		var guardians := PackedVector2Array()
		for hero in heroes: guardians.append(hero["pos"])
		_native_nav.set_heroes(guardians)
	for mo in monsters:
		if float(mo["hp"]) <= 0.0:
			continue
		var current: Vector2 = mo["pos"]
		mo["vel"] = Vector2.ZERO
		mo["blocked"] = false
		mo["flash"] = maxf(0.0, float(mo["flash"]) - dt * 5.0)
		mo["stun_cd"] = maxf(0.0, float(mo["stun_cd"]) - dt)
		var speed := Balance.PATH_SPEED * float(mo["spd"]) * mire * _pace
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
		var fly: bool = bool(mo.get("fly", false))
		# F4 · M5: bosses and elites are not stopped by guardians' bodies, and neither is a body that has
		# stood blocked for ARENA_BLOCK_BREAK seconds (a sealed road must not hold a wave for ever). They
		# take the flyers' road-only path and step checks; mo.fly stays as it is (anti-air, ground zones).
		var ghost: bool = fly or String(mo["kind"]) == "boss" or bool(mo.get("elite", false)) \
				or float(mo.get("block_t", 0.0)) >= Balance.ARENA_BLOCK_BREAK
		if String(mo["kind"]) == "caster" and float(mo["stun_t"]) <= 0.0:
			mo["cast_t"] = float(mo["cast_t"]) - dt
			if float(mo["cast_t"]) <= 0.0:
				mo["cast_t"] = Balance.CURSE_EVERY
				# 별자리 「주술 저항」이 저주 시간을 깎는다.
				curse_t = Balance.CURSE_SEC * _mod("curse")
				events.append({"t": "curse", "p": current, "sid": int(mo.get("spawn_id", 0))})
		var pushed := _advance_push(mo, dt)
		if pushed > 0.0:
			var push_to := current - ArenaGeometry.road_direction(current) * pushed
			if (_road_segment_clear(current, push_to) if ghost else _segment_clear(current, push_to)):
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
		var ahead := current.move_toward(path[0], speed * dt) if not path.is_empty() else current
		# 공중 몬스터(와 보스 · 정예 · 오래 막힌 몸)는 도로만 본다 — 수호자가 앞을 막아도 지난다.
		var obstructed := not path.is_empty() and not (_road_segment_clear(current, ahead) if ghost else _segment_clear(current, ahead))
		var needs_path := obstructed or (path.is_empty() and (navigation_changed or had_path))
		if needs_path:
			path = _path_from(current, Balance.ARENA_CENTER, ghost)
			while not path.is_empty() and current.distance_to(path[0]) <= 0.1:
				path.remove_at(0)
		# Keep the next valid waypoint through unrelated hero movement. Resetting
		# every path on every navigation revision causes visible stalls/backsteps.
		mo["nav_v"] = _nav_version
		mo["path"] = path
		if path.is_empty():
			mo["blocked"] = true
			_note_blocked(mo, dt)
			continue
		var target := path[0]
		var next := current.move_toward(target, speed * dt)
		if needs_path and not (_road_segment_clear(current, next) if ghost else _segment_clear(current, next)):
			mo["blocked"] = true
			mo["path"] = PackedVector2Array()
			_note_blocked(mo, dt)
			continue
		mo["pos"] = next
		mo["vel"] = (next - current) / dt
		mo["motion_t"] = float(mo["motion_t"]) + next.distance_to(current) / Balance.PATH_SPEED
		# A step ends the run of blocked time — unless the body already broke through: it stays a ghost,
		# or it would walk one step and stand ARENA_BLOCK_BREAK seconds again at the same guardian.
		if float(mo.get("block_t", 0.0)) < Balance.ARENA_BLOCK_BREAK:
			mo["block_t"] = 0.0

## One more tick standing blocked. The tick it reaches ARENA_BLOCK_BREAK the body plans again, on the
## road-only grid (it is a ghost from the next tick on).
func _note_blocked(mo: Dictionary, dt: float) -> void:
	var before := float(mo.get("block_t", 0.0))
	mo["block_t"] = before + dt
	if before < Balance.ARENA_BLOCK_BREAK and float(mo["block_t"]) >= Balance.ARENA_BLOCK_BREAK:
		mo["nav_v"] = -1

func _push(mi: int) -> void:
	if mi < 0 or mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	var used := float(mo["push"])
	var distance := minf(Balance.RIDER_PUSH * _mod("push_mult"), Balance.RIDER_PUSH_MAX - used)
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

## Revivals the DLC's revival tickets can still give in this stage.
func revives_left() -> int:
	return maxi(0, Balance.ARENA_REVIVE_USES - revives)

## A revival ticket (DLC, 2026-10-19 D2): the broken crystal reforms, up to ARENA_REVIVE_USES times a
## stage. It comes back at ARENA_REVIVE_HP of its maximum, cannot be hurt for ARENA_REVIVE_INVULN seconds,
## its shockwave stops every monster on the field for ARENA_REVIVE_STUN seconds — and instead of gold
## (never any more) a 5-star hero joins (ArenaRun.grant_revive_hero). Inside a tick the crystal breaks in
## the middle of _move_monsters, where a new hero must not join (refresh_heroes clears in-flight shots and
## remaps sources): the hero then comes at the end of the tick. Outside a tick (the defeat screen, a check)
## it comes at once. arena_revive {p, r, sec, stun, left, unit, tier, where} is emitted with the hero.
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
	_revive_pending = true
	if not _ticking:
		_flush_revive()

## The revival's hero joins and the revival is announced.
func _flush_revive() -> void:
	if not _revive_pending:
		return
	_revive_pending = false
	var gift: Dictionary = run.grant_revive_hero() if run.has_method("grant_revive_hero") else {}
	var unit: Dictionary = gift.get("unit", {})
	events.append({"t": "arena_revive", "p": Balance.ARENA_CENTER, "r": ArenaGeometry.RADIUS,
		"sec": Balance.ARENA_REVIVE_INVULN, "stun": Balance.ARENA_REVIVE_STUN, "left": revives_left(),
		"unit": String(unit.get("id", "")), "tier": int(gift.get("tier", -1)), "where": String(gift.get("where", ""))})

func _reap() -> void:
	var boss_dead := false
	# 처치 경험치(2026-10-17): 쓰러진 놈마다 형(kind)의 xp 를 모아 판에 올린다. 골드와 달리
	# 경험치는 영웅 뽑기가 아니라 별자리 노드(레벨업 팝업)로 간다.
	var xp := 0.0
	for mo in monsters:
		if float(mo["hp"]) <= 0.0:
			# 사다리의 처치 경험치(2026-10-19). 정예는 ARENA_ELITE_XP 배.
			var gain := Balance.arena_ladder_xp(stage, String(mo["kind"]))
			if bool(mo.get("elite", false)):
				gain *= Balance.ARENA_ELITE_XP
			xp += gain
			if String(mo["kind"]) == "boss":
				boss_dead = true
	super._reap()
	if xp > 0.0 and run.running and run.has_method("gain_xp"):
		var gained: int = run.gain_xp(xp)
		for n in range(gained):
			events.append({"t": "arena_levelup", "p": Balance.ARENA_CENTER, "level": int(run.level) - gained + n + 1})
	if boss_dead:
		boss_alive = false
	# Endless waves: the boss is one more monster of its wave, the wave ends when all of it is down.
	if not boss_dead or not run.running or clear_t > 0.0 or not final_stage():
		_check_wave_clear()
		_offer_levelup()
		return
	# The stage is won: its escort scatters without bounty and the crystal mends a little.
	# The boss's fall is seen through the same beat before the stage ends in victory.
	for mo in monsters:
		events.append({"t": "die", "p": mpos(mo), "c": Color(String(mo["m"]["color"])),
			"h": float(mo["h"]), "gold": 0, "sid": int(mo.get("spawn_id", 0)), "scatter": true})
	monsters.clear()
	_pending.clear()
	for bullet in bullets:
		bullet["tgt"] = -1
		bullet["hit"] = []
	_cache_positions()
	# 별자리 「되살아나는 수정」이 돌파 회복을 더한다.
	var mended := minf(crystal_max - crystal_hp, crystal_max * (Balance.ARENA_STAGE_HEAL + _mod_add("heal_stage")))
	crystal_hp += mended
	run.lives = ceili(crystal_hp / crystal_max * Balance.MAX_LIVES)
	clear_t = Balance.ARENA_CLEAR_DELAY
	events.append({"t": "arena_stage_clear", "p": Balance.ARENA_CENTER, "stage": stage,
		"heal": mended, "sec": Balance.ARENA_CLEAR_DELAY, "final": final_stage()})
	_offer_levelup()

## The wave is held when all of its list has spawned and nothing is left alive. The ladder's boss wave
## ends with its boss instead (the clear beat, then victory).
func _check_wave_clear() -> void:
	if preparing or clear_t > 0.0 or done or not run.running:
		return
	if _wave_spawned < _wave_list.size() or not monsters.is_empty():
		return
	if waves_total() > 0 and wave_no >= waves_total():
		return
	_clear_wave()

## 방어 성공: the crystal mends a little (ARENA_WAVE_HEAL, plus the 「되살아나는 수정」 node), the defence
## bonus is paid and the run saves (ArenaRun.wave_cleared), and the preparation for the next wave begins —
## where the levels earned during the wave are offered (_reap calls _offer_levelup right after).
func _clear_wave() -> void:
	var cleared := wave_no
	var mended := heal_crystal(Balance.ARENA_WAVE_HEAL + _mod_add("heal_stage"))
	wave_no += 1
	var prep := Balance.arena_prep(wave_no, waves_total())
	_enter_prep(prep)
	# Hellbound (2026-10-19): the common skills' uses fill again after every block of ARENA_WAVES waves (the
	# boss's), or an endless run would spend them in its first block and never see them again.
	if waves_total() == 0 and cleared % Balance.ARENA_WAVES == 0:
		for id in skill_uses: skill_uses[id] = 0
		events.append({"t": "arena_skill_refill", "p": Balance.ARENA_CENTER, "wave": cleared})
	# The bonus the run pays (ArenaRun.wave_cleared): Hellbound counts the wave's place in its block.
	var bonus_wave := Balance.arena_hell_ramp_wave(cleared) if waves_total() == 0 else cleared
	events.append({"t": "arena_wave_clear", "p": Balance.ARENA_CENTER, "wave": cleared,
		"gold": Balance.arena_wave_bonus(stage, bonus_wave), "prep": prep, "heal": mended})
	if run.has_method("wave_cleared"):
		run.wave_cleared(stage, cleared)

## 레벨이 올랐으면 별자리 팝업을 연다(판이 돌고 있고 다른 창이 없을 때). 열리는 순간부터
## step() 이 멎으므로 전투는 고르는 동안 서 있다. ★ 정비 시간에만 연다(2026-10-19 PLAN M4 — 웨이브
## 중에 팝업이 떠 손가락이 그것을 누르던 F1 의 뿌리를 없앤다): 웨이브 중에 오른 레벨은 쌓였다가 정비가
## 시작될 때 뜬다. 돌파 연출(clear_t) 중에도 열지 않는다 — 보스가 쓰러지는 그림이 먼저다.
func _offer_levelup() -> bool:
	if not preparing or clear_t > 0.0 or _clearing or not run.running or not run.has_method("offer_levelup") or not String(run.modal).is_empty():
		return false
	return run.offer_levelup()

## 패시브 「첫 격돌」은 웨이브마다 그 첫 PASSIVE_FIRST_SEC 초다(2026-10-19 — 스테이지의 첫 몇 초는 정비
## 시간이라 그대로 두면 효과가 사라진다). 다른 배수는 BattleSim 과 같다.
func _atk_mult() -> float:
	if run.has("first") and not preparing and wave_t <= Balance.PASSIVE_FIRST_SEC:
		return Balance.PASSIVE_FIRST
	return 1.0

## Logical point where the boss will step onto the field (the chosen gate), or INF before it is known.
func boss_gate() -> Vector2:
	if boss_lane < 0: return Vector2.INF
	return ArenaGeometry.gate_point(boss_lane, Balance.ARENA_MONSTER_RADIUS)

## 스테이지당 사용 횟수. 별자리 「유성 하나 더」 등이 더한다.
func skill_max_uses(id: String) -> int:
	var base := 0
	match id:
		"blast": base = Balance.ARENA_BLAST_USES
		"freeze": base = Balance.ARENA_FREEZE_USES
		"ward": base = Balance.ARENA_WARD_USES
	return base + (int(_mod_add("uses_" + id)) if base > 0 else 0)

func skill_uses_left(id: String) -> int:
	return maxi(0, skill_max_uses(id) - int(skill_uses.get(id, 0)))

## 쿨타임. 별자리 「빠른 별빛」이 줄인다.
func skill_max_cooldown(id: String) -> float:
	var base := 0.0
	match id:
		"blast": base = Balance.ARENA_BLAST_COOLDOWN
		"freeze": base = Balance.ARENA_FREEZE_COOLDOWN
		"ward": base = Balance.ARENA_WARD_COOLDOWN
	return base * _mod("cooldown")

## 공통 스킬의 골드(2026-10-19 F5 · PLAN M7): 쓸 때마다 고정 값. 별자리 효과 'skill_gold'(곱, 없으면 1)가 깎는다.
func skill_cost(id: String) -> int:
	var base := 0
	match id:
		"blast": base = Balance.ARENA_BLAST_GOLD
		"freeze": base = Balance.ARENA_FREEZE_GOLD
		"ward": base = Balance.ARENA_WARD_GOLD
	return maxi(0, roundi(float(base) * _mod("skill_gold")))

## 별빛 폭발의 반경(별자리 「넓은 유성」이 넓힌다). 맞는 판정은 몬스터의 몸 반경까지 센다.
func blast_radius() -> float:
	return Balance.ARENA_BLAST_RADIUS * _mod("blast_r")

func _alive() -> int:
	var n := 0
	for mo in monsters:
		if float(mo["hp"]) > 0.0: n += 1
	return n

## ★ 스킬을 지금 쓸 수 있는가 — 한 곳에서만 정한다(PLAN M8). cast_skill 은 이것으로만 판정하고, HUD 는
## 이것으로 「준비 완료」 · 비용 · 막힌 까닭을 그린다 — 둘이 어긋나지 않는다. block 의 차례:
##   "inactive" 판이 끝났거나 안 돌거나 창이 열림 · "prep" 정비 중(대상도 피해도 없다 — 골드를 아낀다) ·
##   "clearing" 돌파 연출 · "cooldown" · "spent" 스테이지당 횟수를 다 씀 · "no_target" 폭발 · 서리인데
##   판 위에 몬스터가 없음 · "gold" 골드가 모자람. "" 이면 쓸 수 있다(ready).
func skill_state(id: String) -> Dictionary:
	var cost := skill_cost(id)
	var cooling := float(skill_cooldowns.get(id, 0.0))
	var block := ""
	if done or run == null or not run.running or not String(run.modal).is_empty() or not skill_cooldowns.has(id):
		block = "inactive"
	elif preparing:
		block = "prep"
	elif clear_t > 0.0:
		block = "clearing"
	elif cooling > 0.0:
		block = "cooldown"
	elif skill_uses_left(id) <= 0:
		block = "spent"
	elif id != "ward" and _alive() == 0:
		block = "no_target"
	elif int(run.gold) < cost:
		block = "gold"
	return {"block": block, "cooldown": cooling, "max_cooldown": skill_max_cooldown(id), "uses_left": skill_uses_left(id),
		"uses_max": skill_max_uses(id), "cost": cost, "ready": block.is_empty()}

## Cast a common skill when skill_state says it is ready. The blast falls on `at` (the player's pick; a point
## outside the arena is refused and nothing is spent) or, with `at` = INF, on the monster nearest the crystal
## (the auto-play and the checks). It hits every monster whose body reaches into its radius. Freeze and ward
## ignore `at`. The gold is paid once, after the effect, and the run saves.
func cast_skill(id: String, at: Vector2 = Vector2.INF) -> bool:
	if not bool(skill_state(id)["ready"]):
		return false
	if id == "blast" and at.is_finite() and not ArenaGeometry.contains(at):
		return false
	var cost := skill_cost(id)
	_cache_positions()
	var centre := Balance.ARENA_CENTER
	# 공용 기술은 하늘에서 떨어지는 별빛이라 땅 위든 공중이든 가리지 않는다.
	if id == "blast":
		centre = at if at.is_finite() else _pos_of(_nearest_target(Balance.ARENA_CENTER))
		var radius := blast_radius()
		var damage := Balance.ARENA_BLAST_DAMAGE * _mod("blast")
		for i in range(monsters.size()):
			if centre.distance_to(_pos_of(i)) <= radius + _mr[i]:
				_hurt(i, damage, false, -1, "none", false)
		events.append({"t": "arena_blast", "p": centre, "r": radius, "cost": cost})
	elif id == "freeze":
		for i in range(monsters.size()):
			_slow(i, Balance.ARENA_FREEZE_SLOW, Balance.ARENA_FREEZE_DURATION * _mod("freeze"))
		events.append({"t": "arena_freeze", "p": centre, "r": ArenaGeometry.MAP_RECT.size.length(), "cost": cost})
	else:
		shield = Balance.ARENA_WARD_SHIELD * _mod("ward")
		shield_t = Balance.ARENA_WARD_DURATION
		events.append({"t": "arena_ward", "p": centre, "r": Balance.ALTAR_R, "cost": cost})
	skill_cooldowns[id] = skill_max_cooldown(id)
	skill_uses[id] = int(skill_uses.get(id, 0)) + 1
	run.add_gold(-cost)
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
		"elapsed": elapsed, "boss_spawned": boss_spawned, "boss_alive": boss_alive, "crystal_hp": crystal_hp, "crystal_max": crystal_max,
		"shield": shield, "shield_t": shield_t, "cooldowns": skill_cooldowns.duplicate(), "uses": skill_uses.duplicate(),
		"boss_warned": boss_warned, "boss_lane": boss_lane, "spawn_t": _spawn_t,
		"wave_no": wave_no, "in_prep": preparing, "prep_t": prep_t, "wave_t": wave_t, "wave_spawned": _wave_spawned,
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
	crystal_max = float(data.get("crystal_max", Balance.ARENA_CRYSTAL_HP * _mod("crystal")))
	crystal_hp = minf(float(data["crystal_hp"]), crystal_max)
	shield = float(data["shield"])
	shield_t = float(data["shield_t"])
	skill_cooldowns = data["cooldowns"].duplicate()
	# Runs saved before the per-run limit (2026-10-12) start it fresh.
	for id in skill_uses:
		skill_uses[id] = int(data.get("uses", {}).get(id, 0))
	boss_warned = bool(data.get("boss_warned", boss_spawned))
	boss_lane = int(data.get("boss_lane", -1))
	_forced_lane = -1
	# The wave and its place: the rest of its list comes again from ArenaRun.wave_spawns.
	wave_no = maxi(1, int(data["wave_no"]))
	if waves_total() > 0: wave_no = mini(wave_no, waves_total())
	preparing = bool(data["in_prep"])
	# A preparation saved longer than today's (a tuning value moved) runs today's length.
	prep_t = minf(float(data["prep_t"]), Balance.arena_prep(wave_no, waves_total()))
	wave_t = float(data["wave_t"])
	_wave_list = run.wave_spawns(stage, wave_no) if run != null and run.has_method("wave_spawns") else []
	_wave_spawned = clampi(int(data["wave_spawned"]), 0, _wave_list.size())
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
		if not mo.has("elite"): mo["elite"] = false
		if not mo.has("block_t"): mo["block_t"] = 0.0
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
