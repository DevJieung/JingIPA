extends "res://core/run.gd"

## One continuous, resumable battlefield. Existing hero/passive math is reused.
var modal := "theme"
var theme_index := -1
var selected := 0
var sim: ArenaSim
var summon_result: Dictionary = {}
var summon_count := 0

func label(key: String) -> String:
	return I18n.t(key)

func start_run(seed_value: int = 0) -> void:
	super.start_run(seed_value)
	wave = 1
	modal = "theme"
	theme_index = -1
	selected = 0
	summon_count = 0
	sim = null
	summon_result.clear()
	autosave()

func choose_theme(index: int) -> bool:
	if not running or modal != "theme" or index < 0 or index >= Roster.THEMES.size():
		return false
	theme_index = index
	sim = ArenaSim.new()
	sim.setup(self, 1, run_seed)
	begin_draw()
	return true

func theme_for(_w: int) -> Dictionary:
	return Roster.THEMES[clampi(theme_index, 0, Roster.THEMES.size() - 1)]

func theme_rank(_w: int) -> int:
	return int(theme_for(1).get("rank", 1))

func field_full() -> bool:
	return heroes.size() >= Balance.ARENA_HERO_LIMIT

func ensure_posts() -> void:
	for i in range(heroes.size()):
		heroes[i]["post"] = i
		if not heroes[i].has("position"):
			heroes[i]["position"] = _spawn_position(i)

func _spawn_position(index: int) -> Vector2:
	var preferred := Balance.ARENA_CENTER + Vector2.from_angle(-PI * 0.5 + float(index) * TAU / float(maxi(1, Balance.ARENA_HERO_LIMIT))) * (Balance.ALTAR_R + Balance.ARENA_HERO_RADIUS * 3.0)
	if _position_free(preferred):
		return preferred
	var rect := ArenaGeometry.MAP_RECT.grow(-Balance.ARENA_HERO_RADIUS)
	var step_size := maxi(1, ceili(Balance.ARENA_HERO_RADIUS * 2.0))
	for y in range(ceili(rect.position.y), floori(rect.end.y), step_size):
		for x in range(ceili(rect.position.x), floori(rect.end.x), step_size):
			var candidate := Vector2(x, y)
			if _position_free(candidate):
				return candidate
	return preferred

func _position_free(point: Vector2) -> bool:
	if not ArenaGeometry.contains(point, Balance.ARENA_HERO_RADIUS): return false
	if point.distance_to(Balance.ARENA_CENTER) < Balance.ALTAR_R + Balance.ARENA_HERO_RADIUS:
		return false
	for hero in heroes:
		if hero.has("position") and point.distance_to(hero["position"]) < Balance.ARENA_HERO_RADIUS * 2.0:
			return false
	return true

func summon_cost() -> int:
	return Balance.ARENA_SUMMON_COST

func eligible_units() -> Array:
	var out: Array = []
	for unit in Roster.UNITS:
		var found := find_hero(String(unit["id"]))
		if int(found[1]) >= 0:
			var list: Array = heroes if found[0] == "field" else bench
			if int(list[int(found[1])]["tier"]) >= Balance.TIER_MAX:
				continue
		out.append(unit)
	return out

func begin_summon() -> bool:
	if not running or not modal.is_empty() or sim == null or gold < summon_cost() or eligible_units().is_empty():
		return false
	add_gold(-summon_cost())
	begin_draw()
	return true

func begin_draw() -> void:
	phase = Phase.DRAW
	modal = "rite"
	last_result = {}
	summon_result = {}
	orbit.assign(Rite.roll(rng))
	if summon_count == 0:
		Rite.ensure_stars(orbit, Balance.RITE_FIRST_STARS, rng)
	spins = 0
	paid_spins = 0
	autosave()

func growth_needed(hero: Dictionary) -> int:
	if int(hero["tier"]) >= Balance.TIER_MAX:
		return 0
	return Balance.ARENA_GROWTH_BASE + int(hero["tier"]) * Balance.ARENA_GROWTH_STEP

func gain_hero(unit: Dictionary, tier: int, _allow_echo: bool = true, auto_deploy: bool = true, _metadata: Dictionary = {}) -> Dictionary:
	var found := find_hero(String(unit["id"]))
	var where := String(found[0])
	var slot := int(found[1])
	var before := -1
	var added := 0
	var hero: Dictionary
	var kind := "new"
	if slot >= 0:
		kind = "growth"
		var list: Array = heroes if where == "field" else bench
		hero = list[slot]
		before = int(hero["tier"])
		if before >= Balance.TIER_MAX:
			return {}
		added = (tier + 1) * Balance.ARENA_GROWTH_POINT_SCALE
		hero["growth_points"] = int(hero.get("growth_points", 0)) + added
		while int(hero["tier"]) < Balance.TIER_MAX and int(hero["growth_points"]) >= growth_needed(hero):
			hero["growth_points"] = int(hero["growth_points"]) - growth_needed(hero)
			hero["tier"] = int(hero["tier"]) + 1
		if int(hero["tier"]) == Balance.TIER_MAX:
			hero["growth_points"] = 0
	else:
		hero = {"unit": unit, "tier": tier, "n": 1, "wave": 1, "growth_points": 0}
		where = "field" if auto_deploy and not field_full() else "bench"
		var list: Array = heroes if where == "field" else bench
		slot = list.size()
		list.append(hero)
		ensure_posts()
	best_tier = maxi(best_tier, int(hero["tier"]))
	Save.note_unit(String(unit["id"]), int(hero["tier"]))
	if sim != null:
		sim.refresh_heroes()
	return {"kind": kind, "unit": unit, "tier": tier, "before_tier": before,
		"after_tier": int(hero["tier"]), "added_points": added,
		"growth_points": int(hero["growth_points"]), "maxed": int(hero["tier"]) >= Balance.TIER_MAX,
		"where": where, "slot": slot, "stacked": kind == "growth", "n": 1}

func confirm_summon() -> Dictionary:
	if modal == "rite" and phase == Phase.SWAP:
		return summon_result
	if not running or modal != "rite" or phase != Phase.DRAW or not Rite.valid(orbit):
		return {}
	var pool := eligible_units()
	if pool.is_empty():
		return {}
	var final: Array[int] = orbit.duplicate()
	last_joker = -1
	if has("joker"):
		last_joker = Rite.pull_target(final)
		if last_joker >= 0:
			Rite.pull(final, last_joker, rng)
	var tier := Rite.tier_of(Rite.stars(final))
	last_bumped = has("eye") and tier < Balance.TIER_MAX and rng.randf() < Balance.PASSIVE_EYE_P
	if last_bumped:
		tier += 1
	var unit: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	last_unit = unit
	last_tier = tier
	orbit.assign(final)
	summon_result = gain_hero(unit, tier)
	summon_result.merge({"stars": Rite.stars(final), "orbit": Array(final), "bumped": last_bumped, "joker": last_joker})
	last_result = summon_result
	summon_count += 1
	phase = Phase.SWAP
	Save.record_summon(tier, String(unit["id"]), false)
	autosave()
	return summon_result

func open_modal(name: String) -> bool:
	if not running or not modal.is_empty() or name not in ["shop", "bench"]:
		return false
	modal = name
	phase = Phase.SHOP if name == "shop" else Phase.SWAP
	if name == "shop":
		roll_shop()
	autosave()
	return true

func close_modal() -> bool:
	if not running or modal in ["theme", "result"] or (modal == "rite" and phase == Phase.DRAW):
		return false
	modal = ""
	phase = Phase.BATTLE
	if sim != null:
		sim.refresh_heroes()
	autosave()
	return true

func swap_hero(field_index: int, bench_index: int) -> bool:
	if not running or modal != "bench" or bench_index < 0 or bench_index >= bench.size():
		return false
	if field_index == heroes.size() and not field_full():
		heroes.append(bench.pop_at(bench_index))
	elif field_index >= 0 and field_index < heroes.size():
		var outgoing: Dictionary = heroes[field_index]
		var incoming: Dictionary = bench[bench_index]
		incoming["position"] = hero_position(outgoing)
		heroes[field_index] = incoming
		bench[bench_index] = outgoing
	else:
		return false
	ensure_posts()
	selected = clampi(field_index, 0, heroes.size() - 1)
	sim.refresh_heroes()
	autosave()
	return true

func buy_upgrade(id: String) -> bool:
	if not running or modal != "shop" or Balance.upgrade_by_id(id).is_empty():
		return false
	var bought := super.buy_upgrade(id)
	if bought and sim != null:
		sim.refresh_heroes()
		autosave()
	return bought

func buy_passive(id: String) -> bool:
	if not running or modal != "shop" or id == "echo":
		return false
	var bought := super.buy_passive(id)
	if bought and sim != null:
		shop_offer.erase(id)
		if shop_offer.is_empty():
			roll_shop()
		sim.refresh_heroes()
		autosave()
	return bought

func toggle_passive(id: String) -> bool:
	if modal != "shop":
		return false
	var changed := super.toggle_passive(id)
	if changed and sim != null:
		sim.refresh_heroes()
		autosave()
	return changed

func roll_shop() -> void:
	var pool: Array[String] = []
	# Spread the existing passive rank gates over this single battle's duration.
	var progress := clampf((sim.elapsed if sim != null else 0.0) / Balance.ARENA_BOSS_AT, 0.0, 1.0)
	var progress_wave := 1 + floori(progress * (Balance.LAST_WAVE - 1))
	for passive in Balance.PASSIVES:
		# The old extra fusion-material passive has no counterpart in unique ownership.
		if passive["id"] != "echo" and not owns_passive(String(passive["id"])) and int(passive.get("rank", 1)) <= Balance.passive_rank_cap(progress_wave):
			pool.append(String(passive["id"]))
	_shuffle(pool)
	shop_offer = pool.slice(0, mini(3, pool.size()))

func end_run(won: bool) -> void:
	if not running:
		return
	running = false
	phase = Phase.WIN if won else Phase.OVER
	modal = "result"
	Save.record_run(1, kills, won)

func _arena_heroes_out(list: Array) -> Array:
	var out: Array = []
	for hero in list:
		out.append({"u": String(hero["unit"]["id"]), "t": int(hero["tier"]), "p": hero_position(hero), "points": int(hero.get("growth_points", 0))})
	return out

func snapshot(_include_checkpoint: bool = true) -> Dictionary:
	return {"mode": "arena", "v": 2, "wave": 1, "seed": run_seed, "rng": rng.state,
		"phase": phase, "modal": modal, "theme_index": theme_index, "selected": selected,
		"gold": gold, "lives": lives, "kills": kills, "best_tier": best_tier,
		"heroes": _arena_heroes_out(heroes), "bench": _arena_heroes_out(bench),
		"levels": levels.duplicate(), "passives": Array(passives), "owned_passives": Array(owned_passives),
		"hero_damage": hero_damage.duplicate(true),
		"offer": Array(shop_offer), "summon_count": summon_count,
		"rite": {"orbit": Array(orbit), "spins": spins, "paid": paid_spins},
		"summon_result": summon_result.duplicate(true), "sim": sim.snapshot_arena() if sim != null else {}}

func restore(data: Dictionary) -> bool:
	if not ArenaValidation.valid(data):
		return false
	run_seed = int(data["seed"])
	rng.seed = run_seed
	rng.state = int(data["rng"])
	wave = 1
	running = true
	phase = int(data["phase"])
	modal = String(data["modal"])
	theme_index = int(data["theme_index"])
	selected = int(data["selected"])
	gold = int(data["gold"])
	lives = int(data["lives"])
	kills = int(data["kills"])
	best_tier = int(data["best_tier"])
	heroes.clear()
	bench.clear()
	for group in ["heroes", "bench"]:
		var list: Array = heroes if group == "heroes" else bench
		for saved in data[group]:
			list.append({"unit": Roster.unit_by_id(String(saved["u"])), "tier": int(saved["t"]), "position": Vector2(saved["p"]), "growth_points": int(saved["points"]), "n": 1, "wave": 1})
	if int(data["v"]) == 1:
		_migrate_circle_positions()
	levels = data["levels"].duplicate()
	passives.assign(data["passives"])
	owned_passives.assign(data["owned_passives"])
	hero_damage = data["hero_damage"].duplicate(true)
	shop_offer.assign(data["offer"])
	summon_count = int(data["summon_count"])
	orbit.assign(_ints(data["rite"]["orbit"]))
	spins = int(data["rite"]["spins"])
	paid_spins = int(data["rite"]["paid"])
	summon_result = data["summon_result"].duplicate(true)
	last_result = summon_result
	last_unit = summon_result.get("unit", {})
	last_tier = int(summon_result.get("tier", -1))
	sim = null
	if theme_index >= 0:
		sim = ArenaSim.new()
		sim.setup(self, 1, run_seed)
		sim.restore_arena(data["sim"], int(data["v"]) == 1)
	return true

func _migrate_circle_positions() -> void:
	# Existing rectangular saves retain their progress. Only positions that no
	# longer fit are relocated, and neighbouring heroes must not collapse together.
	var occupied: Array[Vector2] = []
	for hero in heroes:
		var preferred := ArenaGeometry.clamp_point(hero["position"], Balance.ARENA_HERO_RADIUS)
		var candidate := preferred
		for ring in range(20):
			var found := false
			for step_index in range(1 if ring == 0 else 24):
				candidate = ArenaGeometry.clamp_point(preferred + Vector2.from_angle(TAU * step_index / 24.0) * ring * Balance.ARENA_HERO_RADIUS * 2.0, Balance.ARENA_HERO_RADIUS)
				if candidate.distance_to(Balance.ARENA_CENTER) < Balance.ALTAR_R + Balance.ARENA_HERO_RADIUS: continue
				var clear := true
				for other in occupied:
					if other.distance_to(candidate) < Balance.ARENA_HERO_RADIUS * 2.0: clear = false
				if clear:
					found = true
					break
			if found: break
		hero["position"] = candidate
		occupied.append(candidate)
	for hero in bench:
		hero["position"] = ArenaGeometry.clamp_point(hero["position"], Balance.ARENA_HERO_RADIUS)

func autosave() -> void:
	if running:
		Save.store_run(snapshot())
