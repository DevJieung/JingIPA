extends "res://core/run.gd"

## One resumable run: a chain of stages, each a battlefield drawn at random with its
## own roads and boss. Heroes, gold, growth and the crystal carry from stage to stage.
## Existing hero/passive math is reused.
const SAVE_V := ArenaValidation.SAVE_V
## "stage" is the battlefield card shown when a stage opens (the run starts on it).
var modal := "stage"
var theme_index := -1
var selected := 0
var sim: ArenaSim
var summon_result: Dictionary = {}
var summon_count := 0
## 1..Balance.ARENA_STAGES. `wave` mirrors it so records and the title read the stage.
var stage := 1
## Theme index of every stage of this run, fixed by the run seed when the run starts.
var stage_themes: Array[int] = []

func label(key: String) -> String:
	return I18n.t(key)

func start_run(seed_value: int = 0) -> void:
	super.start_run(seed_value)
	selected = 0
	summon_count = 0
	sim = null
	summon_result.clear()
	roll_stage_themes()
	_open_stage(1)
	autosave()

## Draw the run's battlefields. Every lap of five stages visits each of the five
## biomes once in a shuffled order, the same biome never comes twice in a row, and the
## rank (how harsh the place is) climbs from 1 to 5 across the run. The first three
## stages avoid biomes whose monsters are immune to an element: the kind table keeps
## those monsters out that early, so such a battlefield would not be itself.
func roll_stage_themes() -> void:
	stage_themes.clear()
	var r := RandomNumberGenerator.new()
	r.seed = run_seed * 31 + 7
	var bodies: Array = []
	while bodies.size() < Balance.ARENA_STAGES:
		var lap: Array = Balance.MBODY_ORDER.duplicate()
		for attempt in range(200):
			for i in range(lap.size() - 1, 0, -1):
				var j := r.randi_range(0, i)
				var held = lap[i]
				lap[i] = lap[j]
				lap[j] = held
			var fits: bool = bodies.is_empty() or lap[0] != bodies[-1]
			for i in range(lap.size()):
				if bodies.size() + i < 3 and not Balance.body_immune(String(lap[i])).is_empty(): fits = false
			if fits: break
		bodies.append_array(lap)
	for n in range(Balance.ARENA_STAGES):
		var rank := clampi(ceili(float(n + 1) * 5.0 / float(Balance.ARENA_STAGES)), 1, 5)
		var pool: Array[int] = []
		var fallback: Array[int] = []
		for index in range(Roster.THEMES.size()):
			if String(Roster.THEMES[index]["main_body"]) != String(bodies[n]): continue
			fallback.append(index)
			if int(Roster.THEMES[index].get("rank", 1)) == rank: pool.append(index)
		if pool.is_empty(): pool = fallback
		if pool.is_empty(): pool.append(n % Roster.THEMES.size())
		stage_themes.append(pool[r.randi_range(0, pool.size() - 1)])

func _open_stage(number: int) -> void:
	stage = clampi(number, 1, Balance.ARENA_STAGES)
	wave = stage
	theme_index = stage_themes[stage - 1]
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(theme_index))
	if sim == null:
		sim = ArenaSim.new()
		sim.setup(self, stage, run_seed)
		# The run's first battlefield is revealed like every later one.
		sim.announce_stage()
	else:
		sim.begin_stage(stage)
	modal = "stage"
	phase = Phase.DRAW
	Save.note_stage(stage)

## Leave the battlefield card. The run's first rite is free and follows the first card.
func confirm_stage() -> bool:
	if not running or modal != "stage":
		return false
	if summon_count == 0:
		begin_draw()
		return true
	modal = ""
	phase = Phase.BATTLE
	autosave()
	return true

## A stage boss fell (the simulator calls this once): pay the stage bounty.
func stage_cleared(number: int) -> void:
	add_gold(Balance.arena_stage_bonus(number))
	autosave()

func advance_stage() -> void:
	if not running or stage >= Balance.ARENA_STAGES:
		return
	_open_stage(stage + 1)
	autosave()

## Tools and tests only: play the current stage on a chosen battlefield. The game
## itself never offers a choice; battlefields come from roll_stage_themes().
func choose_theme(index: int) -> bool:
	if not running or modal != "stage" or index < 0 or index >= Roster.THEMES.size():
		return false
	stage_themes[stage - 1] = index
	if stage == 1 and summon_count == 0: sim = null
	_open_stage(stage)
	return confirm_stage()

func theme_for(_w: int) -> Dictionary:
	return Roster.THEMES[clampi(theme_index, 0, Roster.THEMES.size() - 1)]

func theme_rank(_w: int) -> int:
	return int(theme_for(1).get("rank", 1))

## The battlefield of a later stage of this run (the card previews the next one).
func stage_theme(number: int) -> Dictionary:
	if stage_themes.is_empty(): return theme_for(1)
	return Roster.THEMES[stage_themes[clampi(number, 1, stage_themes.size()) - 1]]

## Monsters of one assault of a stage (two assaults per stage). Fixed by the run seed.
func stage_spawns(number: int, period: int) -> Array:
	return Roster.theme_spawns(Balance.arena_kind_wave(number), stage_theme(number), wave_seed(number * 2 + period))

## What the battlefield card lists: body shares and monsters over both assaults.
func stage_preview(number: int) -> Dictionary:
	var groups := {}
	var total := 0
	for period in range(2):
		for monster in stage_spawns(number, period):
			var body := String(monster["body"])
			if not groups.has(body): groups[body] = {"body": body, "count": 0, "monsters": []}
			groups[body]["count"] += 1
			if not groups[body]["monsters"].has(monster): groups[body]["monsters"].append(monster)
			total += 1
	var rows: Array = []
	for body in Balance.MBODY_ORDER:
		if not groups.has(body): continue
		var row: Dictionary = groups[body]
		row["percent"] = roundi(float(row["count"]) * 100.0 / float(maxi(1, total)))
		rows.append(row)
	var theme := stage_theme(number)
	return {"stage": number, "theme": theme, "rows": rows,
		"boss": Roster.boss_of_body(String(theme.get("main_body", "flame"))),
		"final": number >= Balance.ARENA_STAGES, "rank": int(theme.get("rank", 1))}

## Guardian's blessing (Store product "guardian"): the crystal revives up to
## Balance.ARENA_REVIVE_USES times per run, with a purse of gold each time.
func revive_ready() -> bool:
	return sim != null and sim.revives_left() > 0 and Store.owns("guardian")

## Revivals left in this run for a player who owns the blessing (0 without it).
func revives_left() -> int:
	return sim.revives_left() if sim != null and Store.owns("guardian") else 0

## The blessing was bought on the defeat screen: the run that just ended resumes with
## its crystal revived. Only the defeat that is still on screen can be taken back.
func revive_from_defeat() -> bool:
	if running or modal != "result" or sim == null or sim.won or not revive_ready():
		return false
	Save.reopen_run(kills)
	running = true
	phase = Phase.BATTLE
	modal = ""
	sim.revive()
	autosave()
	return true

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
	# The battlefield is no longer the player's choice, so the run's first hero is never
	# one whose element the first battlefield's monsters shrug off.
	if summon_count == 0:
		var body := String(theme_for(1).get("main_body", ""))
		var fair := pool.filter(func(candidate: Dictionary) -> bool:
			return Balance.elem_mult(String(candidate.get("elem", "none")), body) >= 1.0)
		if not fair.is_empty(): pool = fair
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
	var progress := sim.run_progress() if sim != null else 0.0
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
	Save.record_run(stage, kills, won)

func _arena_heroes_out(list: Array) -> Array:
	var out: Array = []
	for hero in list:
		out.append({"u": String(hero["unit"]["id"]), "t": int(hero["tier"]), "p": hero_position(hero), "points": int(hero.get("growth_points", 0))})
	return out

func snapshot(_include_checkpoint: bool = true) -> Dictionary:
	return {"mode": "arena", "v": SAVE_V, "wave": stage, "stage": stage, "themes": Array(stage_themes),
		"seed": run_seed, "rng": rng.state,
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
	stage = int(data["stage"])
	wave = stage
	stage_themes.assign(_ints(data["themes"]))
	running = true
	phase = int(data["phase"])
	modal = String(data["modal"])
	theme_index = int(data["theme_index"])
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(theme_index))
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
	sim = ArenaSim.new()
	sim.setup(self, stage, run_seed)
	sim.restore_arena(data["sim"])
	return true

func autosave() -> void:
	if running:
		Save.store_run(snapshot())
