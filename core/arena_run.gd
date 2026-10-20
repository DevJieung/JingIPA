extends "res://core/run.gd"

## One resumable stage of the ladder (2026-10-19, docs/STAGE_LADDER_2026-10-19.md): a battlefield fixed
## by the stage number, ten waves with a preparation phase between them, an elite on the fifth wave and
## the boss on the tenth. Every stage starts from nothing (heroes, gold, growth, crystal) and clearing it
## unlocks the next one (Save.stage_unlocked). Existing hero/passive math is reused.
const SAVE_V := ArenaValidation.SAVE_V
## The ladder order comes from a fixed seed in code, not from a DB column (PLAN M11).
const LADDER_SEED := 20261019
## One chapter is the ten battlefields of one rank (five biomes x two). The rank rises every two chapters.
const CHAPTER := 10
const CHAPTERS_PER_RANK := 2
## "stage" is the battlefield card shown when a stage opens (the run starts on it).
var modal := "stage"
var theme_index := -1
var selected := 0
var sim: ArenaSim
var summon_result: Dictionary = {}
var summon_count := 0
## The open jewel box (modal "box"): its grade (1~5 stars) and its cards {unit, stars, guaranteed}. Both are
## rolled when the box opens or is rerolled (JewelBox) and cleared when it closes. Saved as "box".
var box_tier := 0
var box_cards: Array = []
## 1..Balance.ARENA_LADDER. `wave` mirrors it so records and the title read the stage.
var stage := 1
## This run's copy of the ladder (theme index per stage). Tools may override one entry (choose_theme);
## it is not saved — the snapshot keeps theme_index. ★ The old name stays for the previews.
var stage_themes: Array[int] = []
## Hellbound (endless waves, start_hellbound): the waves never end and the run is not a ladder stage. The
## wave machine reads it through waves_total(). `squad` holds the ids the player took in.
var hell := false
var squad: Array[String] = []
## The last revival's hero {unit, tier, where, slot} (the screen's banner); {} before any revival.
var revive_gift: Dictionary = {}
## The ladder, built once from LADDER_SEED (ladder_theme).
static var _ladder: Array[int] = []
## 성장(2026-10-17): 골드는 영웅 뽑기(2026-10-19 부터 보석상자)에 쓴다. 능력치·패시브는 몬스터 처치
## 경험치가 차면 오르는 레벨마다 「별자리」 노드 셋 중 하나를 골라 얻는다(core/talents.gd).
## xp 는 지금 레벨에서 모은 경험치, level 은 오른 횟수, talents 는 고른 노드(id → 횟수).
var xp := 0.0
var level := 0
var talents: Dictionary = {}
## 지금 내놓은 노드 셋. 비어 있지 않으면 모달 "talent" 는 하나를 고르기 전에는 닫히지 않는다.
var talent_offer: Array[String] = []
## 아직 고르지 않은 레벨업 수(보스 한 마리가 두 레벨을 올릴 수 있다).
var pending_levels := 0
## 고른 노드들의 지속 효과를 모은 것(Talents.effects). 전투와 능력치 계산이 읽는다.
var mods: Dictionary = {}

func label(key: String) -> String:
	return I18n.t(key)

## Start a stage of the ladder: stage_no, or the next unlocked stage (Save.stage_unlocked) when it is 0.
## A locked stage still opens — tools, the auto-play and the benches use that; screens offer only
## stages for which can_play(n) holds. Opening the stage selects its battlefield's road layout
## (_open_stage), whatever layout the title left behind.
func start_run(seed_value: int = 0, stage_no: int = 0) -> void:
	var number := clampi(stage_no if stage_no > 0 else Save.stage_unlocked, 1, Balance.ARENA_LADDER)
	# A stage not yet finished (cleared or lost) starts again from its kept seed, so starting over gives the
	# same free first box (Save.seed_for_stage, 2026-10-19). Tools and checks pass their own seed.
	if seed_value == 0:
		seed_value = Save.seed_for_stage(number)
	super.start_run(seed_value)
	selected = 0
	summon_count = 0
	sim = null
	summon_result.clear()
	box_tier = 0
	box_cards.clear()
	xp = 0.0
	level = 0
	talents.clear()
	talent_offer.clear()
	pending_levels = 0
	mods = {}
	hell = false
	squad.clear()
	revive_gift = {}
	stage = number
	stage_themes.clear()
	for ladder_n in range(1, Balance.ARENA_LADDER + 1):
		stage_themes.append(ladder_theme(ladder_n))
	_open_stage(stage)
	autosave()

## The same stage again, from the start (Hellbound: the same squad again).
func retry() -> void:
	if hell:
		start_hellbound(_squad_out())
		return
	start_run(0, stage)

## After a cleared stage, open the next one when it is unlocked. False while a stage is still running.
func next_stage() -> bool:
	if running or hell or not can_play(stage + 1):
		return false
	start_run(0, stage + 1)
	return true

## Whether the player may start that stage: everything up to the highest unlocked one.
func can_play(number: int) -> bool:
	return number >= 1 and number <= ladder_size() and number <= Save.stage_unlocked

func ladder_size() -> int:
	return Balance.ARENA_LADDER

## Waves in this run: Balance.ARENA_WAVES, or 0 for Hellbound's endless waves.
func waves_total() -> int:
	return 0 if hell else Balance.ARENA_WAVES

static func chapter_of(number: int) -> int:
	return ceili(float(maxi(1, number)) / float(CHAPTER))

## The rank (how harsh the place is, 1~5) of a stage's chapter: chapters 1~2 rank 1 … 9~10 rank 5.
static func chapter_rank(number: int) -> int:
	return clampi(ceili(float(chapter_of(number)) / float(CHAPTERS_PER_RANK)), 1, 5)

## The last stage of every chapter: its boss is a chapter boss (the final boss look and
## Balance.ARENA_FINAL_BOSS_HP).
static func chapter_stage(number: int) -> bool:
	return number > 0 and number % CHAPTER == 0

## The battlefield (theme index) of a ladder stage. The same answer every time, on every device.
static func ladder_theme(number: int) -> int:
	if _ladder.size() != Balance.ARENA_LADDER:
		_ladder = build_ladder()
	return _ladder[clampi(number, 1, _ladder.size()) - 1]

## The ladder (PLAN M11), from LADDER_SEED: chapter c uses the ten battlefields of rank ceil(c/2) once
## each, as two laps of the five biomes in a shuffled order. The same biome never comes twice in a row,
## across laps and chapters too. Stages before Balance.ARENA_IMMUNE_STAGE avoid biomes whose monsters are
## immune to an element — the kind table keeps immune bodies out that early, so such a battlefield would
## not be itself. ★ Balance.MBODY_ORDER seeds the laps; do not reorder it.
static func build_ladder() -> Array[int]:
	var r := RandomNumberGenerator.new()
	r.seed = LADDER_SEED
	var out: Array[int] = []
	var last_body := ""
	var chapter := 0
	while out.size() < Balance.ARENA_LADDER:
		chapter += 1
		var rank := clampi(ceili(float(chapter) / float(CHAPTERS_PER_RANK)), 1, 5)
		var by_body := {}
		for body in Balance.MBODY_ORDER:
			by_body[body] = []
		for index in range(Roster.THEMES.size()):
			var theme: Dictionary = Roster.THEMES[index]
			var main := String(theme.get("main_body", ""))
			if by_body.has(main) and int(theme.get("rank", 1)) == rank:
				by_body[main].append(index)
		for body in by_body:
			_seeded_shuffle(by_body[body], r)
		var end := mini(out.size() + CHAPTER, Balance.ARENA_LADDER)
		while out.size() < end:
			var lap: Array = Balance.MBODY_ORDER.duplicate()
			for attempt in range(200):
				_seeded_shuffle(lap, r)
				var fits: bool = String(lap[0]) != last_body
				for i in range(lap.size()):
					if out.size() + i + 1 < Balance.ARENA_IMMUNE_STAGE and not Balance.body_immune(String(lap[i])).is_empty():
						fits = false
				if fits:
					break
			for body in lap:
				if out.size() >= end:
					break
				var pool: Array = by_body[body]
				out.append(int(pool.pop_front()) if not pool.is_empty() else _nearest_theme(String(body), rank, out.size()))
				last_body = String(body)
	return out

## A table that lost a (biome, rank) battlefield: the same biome at the nearest rank.
static func _nearest_theme(body: String, rank: int, salt: int) -> int:
	var best := -1
	for index in range(Roster.THEMES.size()):
		var theme: Dictionary = Roster.THEMES[index]
		if String(theme.get("main_body", "")) != body:
			continue
		if best < 0 or absi(int(theme.get("rank", 1)) - rank) < absi(int(Roster.THEMES[best].get("rank", 1)) - rank):
			best = index
	return best if best >= 0 else salt % maxi(1, Roster.THEMES.size())

static func _seeded_shuffle(list: Array, r: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var held = list[i]
		list[i] = list[j]
		list[j] = held

## Build the stage's battlefield. Selecting its road layout here is what every entry point relies on
## (start_run, retry, next_stage, choose_theme): the title puts the default layout back.
func _open_stage(number: int) -> void:
	stage = clampi(number, 1, Balance.ARENA_LADDER)
	wave = stage
	theme_index = stage_themes[stage - 1] if stage <= stage_themes.size() else ladder_theme(stage)
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(theme_index))
	if sim == null:
		sim = ArenaSim.new()
		sim.setup(self, stage, run_seed)
		# The stage's battlefield is revealed under its card.
		sim.announce_stage()
	else:
		sim.begin_stage(stage)
	modal = "stage"
	phase = Phase.DRAW

## Leave the battlefield card. Every stage starts with nobody, so its first box is free and follows the card.
func confirm_stage() -> bool:
	if not running or modal != "stage":
		return false
	if summon_count == 0:
		begin_draw()
		return modal != "stage"
	modal = ""
	phase = Phase.BATTLE
	autosave()
	return true

## A wave was held (the simulator calls this once per wave): pay the defence bonus and save at once.
## The end of a wave is an autosave point (PLAN M13), next to the real-time interval of ArenaSim.step.
func wave_cleared(number: int, w: int) -> void:
	# Hellbound's waves never end: its bonus follows the wave's place in its block of ARENA_WAVES (as its
	# health ramp does), not the raw number, so the endless gold does not snowball. Its record (the best wave)
	# is written at every held wave, not only when the Soul Stone breaks — a run left for another is not lost.
	add_gold(Balance.arena_wave_bonus(number, Balance.arena_hell_ramp_wave(w) if hell else w))
	if hell:
		Save.record_hell(w)
	autosave()

## ★ Old name kept for the previews and benches — do not use in new code. The ten-stage chain is gone:
## this opens the next ladder stage after a cleared one (next_stage).
func advance_stage() -> void:
	next_stage()

## Tools and tests only: play the current stage on a chosen battlefield. The game
## itself never offers a choice; battlefields come from the ladder (ladder_theme).
func choose_theme(index: int) -> bool:
	if not running or modal != "stage" or index < 0 or index >= Roster.THEMES.size():
		return false
	if stage_themes.size() >= stage:
		stage_themes[stage - 1] = index
	theme_index = index
	if summon_count == 0: sim = null
	_open_stage(stage)
	return confirm_stage()

func theme_for(_w: int) -> Dictionary:
	return Roster.THEMES[clampi(theme_index, 0, Roster.THEMES.size() - 1)]

func theme_rank(_w: int) -> int:
	return int(theme_for(1).get("rank", 1))

## The battlefield of a ladder stage: this run's (overridable) copy for the stage in play, the ladder
## for any other (the stage select previews them).
func _stage_theme(number: int) -> Dictionary:
	var index := stage_themes[number - 1] if number >= 1 and number <= stage_themes.size() else ladder_theme(number)
	if number == stage and theme_index >= 0:
		index = theme_index
	return Roster.THEMES[clampi(index, 0, Roster.THEMES.size() - 1)]

## The spawn list of one wave, in order: entries {"m": a monster row, "elite": bool}. The same stage and
## wave always give the same list (a seed of its own, never the run's rng or the simulator's), so a save
## restores the rest of a wave exactly and the card can show it. The boss wave is the boss followed by
## Balance.ARENA_BOSS_ESCORT; an elite wave has one elite in the middle. Its length is always
## Balance.arena_wave_count(number, w, waves_total()).
func wave_spawns(number: int, w: int) -> Array:
	var theme := _stage_theme(number)
	var total := waves_total()
	var r := RandomNumberGenerator.new()
	r.seed = _wave_seed(number, w)
	var out: Array = []
	if Balance.arena_boss_wave(w, total):
		out.append({"m": Roster.boss_of_body(String(theme.get("main_body", "flame"))), "elite": false})
		for row in _wave_rows(number, w, theme, Balance.ARENA_BOSS_ESCORT, r):
			out.append({"m": row, "elite": false})
		return out
	for row in _wave_rows(number, w, theme, Balance.arena_wave_size(number, w), r):
		out.append({"m": row, "elite": false})
	if Balance.arena_elite_wave(w, total):
		out.insert(out.size() / 2, {"m": _elite_row(theme, number), "elite": true})
	return out

## The seed of a wave's list: the ladder's stage and wave only, so a retry meets the same waves (the gates,
## crits and the rest still differ); Hellbound mixes in the run seed.
func _wave_seed(number: int, w: int) -> int:
	return (run_seed if hell else LADDER_SEED) * 1000003 + number * 7919 + w * 104729 + 11

## count regular monsters of the battlefield for one wave. The body shares come from the theme
## (Roster.theme_spawns); a kind the wave does not allow yet, or a flyer before Balance.ARENA_FLY_STAGE,
## becomes the swarm of the same body, so the battlefield keeps its bodies (and their matchups).
func _wave_rows(number: int, w: int, theme: Dictionary, count: int, r: RandomNumberGenerator) -> Array:
	var pool: Array = Roster.theme_spawns(Balance.arena_kind_wave(number, w), theme, r.randi())
	var kinds := Balance.arena_wave_kinds(number, w)
	for i in range(pool.size()):
		var row: Dictionary = pool[i]
		if not kinds.has(String(row["kind"])) or (number < Balance.ARENA_FLY_STAGE and Balance.flies(row)):
			var swarm := _body_row(String(row["body"]), "swarm")
			if not swarm.is_empty():
				pool[i] = swarm
	_seeded_shuffle(pool, r)
	var out: Array = []
	if pool.is_empty():
		return out
	for i in range(count):
		out.append(pool[i % pool.size()])
	return out

func _body_row(body: String, kind: String) -> Dictionary:
	for monster in Roster.monsters_of_body(body):
		if String(monster["kind"]) == kind:
			return monster
	return {}

## The elite (PLAN M6): the tank of the battlefield's main body, a ground body. A tool that puts an
## immune-bodied battlefield before Balance.ARENA_IMMUNE_STAGE gets the strongest other body's tank.
func _elite_row(theme: Dictionary, number: int) -> Dictionary:
	var body := String(theme.get("main_body", "flame"))
	if number < Balance.ARENA_IMMUNE_STAGE and not Balance.body_immune(body).is_empty():
		var weights: Dictionary = theme.get("weights", {})
		var best := -1.0
		for other in Balance.MBODY_ORDER:
			if Balance.body_immune(String(other)).is_empty() and float(weights.get(other, 0.0)) > best:
				best = float(weights.get(other, 0.0))
				body = String(other)
	var tank := _body_row(body, "tank")
	if not tank.is_empty():
		return tank
	for monster in Roster.monsters_of_body(body):
		if not Balance.flies(monster):
			return monster
	return Roster.monsters_of_body(body)[0] if not Roster.monsters_of_body(body).is_empty() else Roster.MONSTERS[0]

## ★ Old name kept for the previews — do not use in new code: the regular monsters of one wave
## (period 0 → wave 1).
func stage_spawns(number: int, period: int) -> Array:
	var out: Array = []
	for entry in wave_spawns(number, clampi(period + 1, 1, Balance.ARENA_WAVES)):
		if String(entry["m"]["kind"]) != "boss":
			out.append(entry["m"])
	return out

## What the battlefield card lists: body shares and monsters over all the waves (elite and escort included,
## the boss apart), the elite, one line per wave and the chapter. ArenaScreen preloads the models of the
## rows and the boss while the card is up (commit a04a5a2), so every monster of the stage must be here.
## In Hellbound `hell` is true and `final` false: its waves never end, the lines show the first ARENA_WAVES.
func stage_preview(number: int) -> Dictionary:
	var theme := _stage_theme(number)
	var total_waves := waves_total()
	var groups := {}
	var total := 0
	var waves: Array = []
	var elite: Dictionary = {}
	for w in range(1, Balance.ARENA_WAVES + 1):
		var entries := wave_spawns(number, w)
		waves.append({"wave": w, "size": entries.size(), "elite": Balance.arena_elite_wave(w, total_waves),
			"boss": Balance.arena_boss_wave(w, total_waves)})
		for entry in entries:
			var monster: Dictionary = entry["m"]
			if String(monster["kind"]) == "boss":
				continue
			if bool(entry["elite"]):
				elite = monster
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
	return {"stage": number, "theme": theme, "rows": rows,
		"boss": Roster.boss_of_body(String(theme.get("main_body", "flame"))), "elite": elite, "waves": waves,
		"final": chapter_stage(number) and not hell, "chapter": chapter_of(number), "rank": int(theme.get("rank", 1)),
		"hell": hell}

## Revival tickets (the DLC, 2026-10-19 D2): the crystal revives up to Balance.ARENA_REVIVE_USES times a
## stage and each revival brings a 5-star hero — never gold (grant_revive_hero).
func revive_ready() -> bool:
	return sim != null and sim.revives_left() > 0 and dlc()

## Revivals left in this stage for a DLC owner (0 without it).
func revives_left() -> int:
	return sim.revives_left() if sim != null and dlc() else 0

## The DLC was bought on the defeat screen: the stage that just ended resumes with its crystal revived (and
## its 5-star hero). Only the defeat that is still on screen can be taken back.
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

## The 5-star hero a revival would bring if it happened now: decided by the run seed and the stage, so the
## screen can load its model while the stage card is up (no hitch when it arrives). Granting takes another
## absent hero if this one has joined in the meantime.
func revive_candidate() -> Dictionary:
	if Roster.UNITS.is_empty():
		return {}
	return Roster.UNITS[posmod(run_seed * 7919 + stage * 104729 + 17, Roster.UNITS.size())]

## A revival's hero (D2): a 5-star (TIER_MAX) character not on the field or the bench — the candidate when it
## is free, else one chosen with the run's rng (saved, so a restore gives the same). It joins the field while
## there is room, else the bench. When everyone is already here the lowest hero below the top grade reaches
## it; when all are at the top, nobody comes. The codex and the best grade count it. Returns revive_gift.
func grant_revive_hero() -> Dictionary:
	revive_gift = {}
	var unit := revive_candidate()
	if unit.is_empty() or int(find_hero(String(unit["id"]))[1]) >= 0:
		var absent: Array = Roster.UNITS.filter(func(candidate: Dictionary) -> bool:
			return int(find_hero(String(candidate["id"]))[1]) < 0)
		unit = absent[rng.randi_range(0, absent.size() - 1)] if not absent.is_empty() else {}
	if not unit.is_empty():
		var joined := gain_hero(unit, Balance.TIER_MAX)
		revive_gift = {"unit": unit, "tier": Balance.TIER_MAX, "where": joined["where"], "slot": joined["slot"]}
	else:
		var low: Array = []
		for where in ["field", "bench"]:
			var list: Array = heroes if where == "field" else bench
			for slot in range(list.size()):
				if int(list[slot]["tier"]) < Balance.TIER_MAX and (low.is_empty() or int(list[slot]["tier"]) < int(low[0]["tier"])):
					low = [list[slot], where, slot]
		if low.is_empty():
			return revive_gift
		low[0]["tier"] = Balance.TIER_MAX
		low[0]["growth_points"] = 0
		revive_gift = {"unit": low[0]["unit"], "tier": Balance.TIER_MAX, "where": low[1], "slot": low[2]}
		if sim != null: sim.refresh_heroes()
	best_tier = maxi(best_tier, Balance.TIER_MAX)
	Save.record_summon(Balance.TIER_MAX, String(revive_gift["unit"]["id"]), false)
	autosave()
	return revive_gift

# --------------------------------------------------------------------------- #
# Hellbound (DLC, 2026-10-19 D3 · U4 · M10)
# --------------------------------------------------------------------------- #
## The heroes Hellbound may take: every character met (the codex, Save.seen_units) at its best grade
## (Save.best_of; never graded = 1 star), in roster order. Entries {unit, tier}.
static func hellbound_pool() -> Array:
	var out: Array = []
	for unit in Roster.UNITS:
		var id := String(unit["id"])
		if Save.seen_units.has(id):
			var best: int = Save.best_of(id)
			out.append({"unit": unit, "tier": best if best >= 0 else JewelBox.tier_of(1)})
	return out

func can_hellbound() -> bool:
	return dlc() and not hellbound_pool().is_empty()

## Start Hellbound with these heroes (ids from hellbound_pool, distinct, 1..ARENA_HELL_SQUAD): endless waves on
## one battlefield of rank 4~5 chosen by the seed, each hero at its best grade on the field. There is no free
## box (the squad is already there); boxes, constellation nodes, skills and revival tickets work as in a stage.
## Its record is the best wave reached (Save.hell_best_wave), apart from the ladder.
func start_hellbound(ids: Array, seed_value: int = 0) -> bool:
	if not can_hellbound():
		return false
	var pool := {}
	for entry in hellbound_pool():
		pool[String(entry["unit"]["id"])] = int(entry["tier"])
	var picked: Array[String] = []
	for id in ids:
		if not id is String or not pool.has(id) or picked.has(id):
			return false
		picked.append(id)
	if picked.is_empty() or picked.size() > Balance.ARENA_HELL_SQUAD:
		return false
	super.start_run(seed_value)
	selected = 0
	sim = null
	summon_result.clear()
	box_tier = 0
	box_cards.clear()
	revive_gift = {}
	xp = 0.0
	level = 0
	talents.clear()
	talent_offer.clear()
	pending_levels = 0
	mods = {}
	hell = true
	squad.assign(picked)
	Save.hell_squad = _squad_out()
	stage = clampi(Balance.ARENA_HELL_BASE_STAGE, 1, Balance.ARENA_LADDER)
	stage_themes.clear()
	for number in range(1, Balance.ARENA_LADDER + 1):
		stage_themes.append(ladder_theme(number))
	stage_themes[stage - 1] = _hell_theme()
	# The battlefield (and its road layout) first, so the squad stands off its roads.
	_open_stage(stage)
	for id in picked:
		gain_hero(Roster.unit_by_id(id), pool[id])
	# The squad stands in for the stage's first box.
	summon_count = 1
	autosave()
	return true

## Hellbound's battlefield: one of rank 4~5, chosen by the run seed.
func _hell_theme() -> int:
	var harsh: Array[int] = []
	for index in range(Roster.THEMES.size()):
		if int(Roster.THEMES[index].get("rank", 1)) >= 4: harsh.append(index)
	if harsh.is_empty():
		return ladder_theme(Balance.ARENA_LADDER)
	var r := RandomNumberGenerator.new()
	r.seed = run_seed * 31 + 7
	return harsh[r.randi_range(0, harsh.size() - 1)]

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

## 다음 보석상자의 값. 스테이지의 첫 상자는 무료고(summon_count 0), 그 뒤는 열 때마다
## ARENA_SUMMON_COST_STEP 씩 오른다. 별자리 「인연」이 배수로 깎는다.
func summon_cost() -> int:
	var paid := maxi(0, summon_count - 1)
	return maxi(1, roundi((Balance.ARENA_SUMMON_COST + Balance.ARENA_SUMMON_COST_STEP * paid) * mod("summon")))

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

## Why a summon cannot open now, or "" when it can (PLAN M4: summons only in the preparation phase).
##   "modal" — not running, or a window is open · "wave" — a wave is on (the button waits for the
##   preparation phase) · "pool" — every character is at the top grade · "gold" — not enough gold.
func summon_block() -> String:
	if not running or sim == null or not modal.is_empty():
		return "modal"
	if not sim.in_prep():
		return "wave"
	if eligible_units().is_empty():
		return "pool"
	if gold < summon_price():
		return "gold"
	return ""

## What the next box really costs: the stage's first box is free (M2), every later one is
## summon_cost(). The first box normally opens by itself after the stage card; this keeps
## the rail button honest if it is ever the one that opens it (D6, 2026-10-19).
func summon_price() -> int:
	return 0 if summon_count == 0 else summon_cost()

func can_summon() -> bool:
	return summon_block().is_empty()

func begin_summon() -> bool:
	if not can_summon():
		return false
	add_gold(-summon_price())
	begin_draw()
	return true

# --------------------------------------------------------------------------- #
# 보석상자 (2026-10-19 피드백 F10 · U1 · U2 · M1 · M2 · M3 · D1, docs/JEWEL_BOX.md — 규칙은 core/jewel_box.gd)
# --------------------------------------------------------------------------- #
## Open the box window (modal "box", phase DRAW): its grade and cards are rolled now, from the run's rng —
## a save holds the very same box. Only in the preparation phase (the stage's free first box comes right
## after its card, still in the first preparation); otherwise nothing happens (the parent's signature
## returns nothing, so callers read `modal`).
func begin_draw() -> void:
	if sim != null and not sim.in_prep():
		return
	phase = Phase.DRAW
	modal = "box"
	last_result = {}
	summon_result = {}
	orbit.clear()
	spins = 0
	paid_spins = 0
	box_tier = 0
	_deal_box()
	autosave()

## Roll the box: a new box rolls its grade (the stage's first at least ARENA_BOX_FIRST_TIER); a reroll rolls
## it again but never lower (PLAN M1). Then the cards, all new, and the fairness rules (anti-air, immune).
func _deal_box() -> void:
	var floor_stars := Balance.ARENA_BOX_FIRST_TIER if summon_count == 0 else 1
	box_tier = maxi(box_tier, JewelBox.roll(rng, Balance.arena_box_weights(), floor_stars))
	var pool := _box_pool()
	box_cards = JewelBox.deal(rng, pool, box_tier, Balance.ARENA_BOX_CARDS, Balance.arena_card_weights())
	_ensure_fair(pool)

## Characters a box may deal: everyone not yet at the top grade. The stage's first box (the party is
## empty) deals only elements that no body of waves 1~3 resists (PLAN M2's first-summon fairness, widened
## 2026-10-19 O5 from the main body alone), so the first hero is not stuck at half damage or nothing; when no
## character passes, elements none of them is immune to and the main body does not resist, then the main
## body alone.
func _box_pool() -> Array:
	var pool := eligible_units()
	if summon_count == 0:
		var early := _bodies_in(1, mini(3, waves_total() if waves_total() > 0 else 3))
		var main := String(theme_for(1).get("main_body", ""))
		for level in range(3):
			var fair := pool.filter(func(candidate: Dictionary) -> bool:
				return _first_box_fair(level, String(candidate.get("elem", "none")), early, main))
			if not fair.is_empty(): return fair
	return pool

## The first box's element tests, strictest first: 0 — no body of the early waves resists it; 1 — none is
## immune to it and the main body does not resist it; 2 — the main body does not resist it.
static func _first_box_fair(level: int, element: String, early: Dictionary, main: String) -> bool:
	if level < 2:
		for body in early:
			var mult := Balance.elem_mult(element, String(body))
			if (level == 0 and mult < 1.0) or (level == 1 and mult <= 0.0): return false
		if level == 0: return true
	return Balance.elem_mult(element, main) >= 1.0

## The bodies of waves first..last of this stage, each {fly, ground}: whether any of its monsters there flies,
## whether any walks.
func _bodies_in(first: int, last: int) -> Dictionary:
	var out := {}
	for w in range(maxi(1, first), last + 1):
		for entry in wave_spawns(stage, w):
			var monster: Dictionary = entry["m"]
			var body := String(monster["body"])
			if not out.has(body): out[body] = {"fly": false, "ground": false}
			out[body]["fly" if Balance.flies(monster) else "ground"] = true
	return out

## The bodies still ahead: from the current wave (the next one in a preparation) to the stage's last
## (endless waves: the next ARENA_WAVES).
func _bodies_ahead() -> Dictionary:
	var first: int = sim.wave_no if sim != null else 1
	return _bodies_in(first, waves_total() if waves_total() > 0 else first + Balance.ARENA_WAVES - 1)

## Whether this character can hurt that body: its element is not immune, and a flyer needs a gun or a bow.
static func hurts(unit: Dictionary, body: String, flying: bool) -> bool:
	return (not flying or Balance.anti_air(unit)) and Balance.elem_mult(String(unit.get("elem", "none")), body) > 0.0

## 공정 규칙(2026-10-19 대공 · 교차 점검 O5 면역): 남은 웨이브의 몸 중 출전 · 대기 영웅 누구도 때리지 못하는
## 것. 웨이브는 모두 쓰러져야 끝나므로 그런 몸이 있으면 수정이 깨질 때까지 갇힌다. 공중 몸은 대공(총 · 활)이면서
## 면역이 아닌 속성이라야 때리고, 땅 위의 몸은 면역이 아닌 속성이면 된다. 빈 파티(스테이지 첫 상자)는 공중 몸만
## 센다 — 속성은 첫 상자의 거르기(_box_pool)가 맡는다. 원소 [{body, fly}].
func uncovered_bodies() -> Array:
	var party: Array = heroes + bench
	var out: Array = []
	var ahead := _bodies_ahead()
	for body in ahead:
		for flying in [true, false]:
			if not bool(ahead[body]["fly" if flying else "ground"]): continue
			if not flying and party.is_empty(): continue
			var covered := false
			for hero in party:
				if hurts(hero["unit"], String(body), flying):
					covered = true
					break
			if not covered: out.append({"body": String(body), "fly": flying})
	return out

## 대공 공정 규칙: 남은 웨이브의 공중 몸을 실제로 때릴 대공 영웅(그 몸에 면역이 아닌 속성)이 파티에 없다.
func anti_air_needed() -> bool:
	return uncovered_bodies().any(func(need: Dictionary) -> bool: return bool(need["fly"]))

## 면역 공정 규칙: 남은 웨이브에 파티 모든 영웅의 속성에 면역인 땅 위의 몸이 있다.
func immune_needed() -> bool:
	return uncovered_bodies().any(func(need: Dictionary) -> bool: return not bool(need["fly"]))

## 이 스테이지의 지금 웨이브(정비 중이면 다음 웨이브)부터 마지막 웨이브까지에 공중 몬스터가 있는가.
## 끝없는 모드는 앞으로 ARENA_WAVES 웨이브를 본다.
func flyers_ahead() -> bool:
	var ahead := _bodies_ahead()
	for body in ahead:
		if bool(ahead[body]["fly"]): return true
	return false

## The fairness rules on a dealt box: for each body nobody can hurt (uncovered_bodies), a card that can — a
## flying one up to ARENA_BOX_AIR_CARDS anti-air cards, a walking one one card. A card that serves no rule
## yet (the guaranteed one last) takes a fitting character from the pool and keeps its stars.
func _ensure_fair(pool: Array) -> void:
	if box_cards.is_empty():
		return
	var served: Array[int] = []
	for need in uncovered_bodies():
		var flying := bool(need["fly"])
		var body := String(need["body"])
		var want := Balance.ARENA_BOX_AIR_CARDS if flying else 1
		if want <= 0: continue
		var fits := func(unit: Dictionary) -> bool: return hurts(unit, body, flying)
		var have := 0
		for i in range(box_cards.size()):
			if fits.call(box_cards[i]["unit"]):
				have += 1
				if not served.has(i): served.append(i)
		var dealt := {}
		for card in box_cards: dealt[String(card["unit"]["id"])] = true
		var candidates := pool.filter(func(unit: Dictionary) -> bool: return fits.call(unit) and not dealt.has(String(unit["id"])))
		while have < want and not candidates.is_empty():
			var slots: Array[int] = []
			for pass_no in range(2):
				for i in range(box_cards.size()):
					if served.has(i) or fits.call(box_cards[i]["unit"]): continue
					if pass_no == 0 and bool(box_cards[i]["guaranteed"]): continue
					slots.append(i)
				if not slots.is_empty(): break
			if slots.is_empty():
				break
			var slot: int = slots[rng.randi_range(0, slots.size() - 1)]
			box_cards[slot]["unit"] = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
			served.append(slot)
			have += 1

## The paid product (Store.GUARDIAN, shown as the DLC bundle) — the one place that asks.
func dlc() -> bool:
	return Store.owns(Store.GUARDIAN)

## Free rerolls per box: FREE_REROLL (plus 「한 번 더」 · 「큰손」 as before), and with the DLC up to
## ARENA_DLC_FREE_REROLL before those bonuses (D1).
func free_rerolls_at(level: int) -> int:
	return super.free_rerolls_at(level) + (maxi(0, Balance.ARENA_DLC_FREE_REROLL - Balance.FREE_REROLL) if dlc() else 0)

## The arena has no paid reroll (PLAN M1): a reroll is free or it is not there.
func respin_cost() -> int:
	return 0

func can_respin() -> bool:
	return running and modal == "box" and phase == Phase.DRAW and not box_cards.is_empty() and respins_left() > 0

## Reroll the box: its grade is rolled again but never drops, and all its cards are dealt anew. Returns the
## dealt card indices, or nothing when no reroll was possible. Saved at once (no reroll by restarting the app).
func respin() -> Array[int]:
	var dealt: Array[int] = []
	if not can_respin():
		return dealt
	spins += 1
	_deal_box()
	for i in range(box_cards.size()):
		dealt.append(i)
	autosave()
	return dealt

func growth_needed(hero: Dictionary) -> int:
	return _growth_need(int(hero["tier"]))

func _growth_need(tier: int) -> int:
	if tier >= Balance.TIER_MAX:
		return 0
	return Balance.ARENA_GROWTH_BASE + tier * Balance.ARENA_GROWTH_STEP

## What gaining `unit` at `tier` would do, without changing anything (gain_hero applies it; card_preview
## shows it): a new hero on the field or the bench, or growth points for the one already owned.
func _gain_plan(unit: Dictionary, tier: int, auto_deploy: bool = true) -> Dictionary:
	var found := find_hero(String(unit["id"]))
	var where := String(found[0])
	var slot := int(found[1])
	if slot < 0:
		where = "field" if auto_deploy and not field_full() else "bench"
		var list: Array = heroes if where == "field" else bench
		return {"kind": "new", "before_tier": -1, "after_tier": tier, "added_points": 0, "points": 0,
			"maxed": tier >= Balance.TIER_MAX, "where": where, "slot": list.size(), "blocked": false}
	var hero: Dictionary = (heroes if where == "field" else bench)[slot]
	var before := int(hero["tier"])
	if before >= Balance.TIER_MAX:
		return {"kind": "growth", "before_tier": before, "after_tier": before, "added_points": 0, "points": 0,
			"maxed": true, "where": where, "slot": slot, "blocked": true}
	var added := (tier + 1) * Balance.ARENA_GROWTH_POINT_SCALE + int(mod_add("growth"))
	var points := int(hero.get("growth_points", 0)) + added
	var after := before
	while after < Balance.TIER_MAX and points >= _growth_need(after):
		points -= _growth_need(after)
		after += 1
	if after == Balance.TIER_MAX:
		points = 0
	return {"kind": "growth", "before_tier": before, "after_tier": after, "added_points": added, "points": points,
		"maxed": after >= Balance.TIER_MAX, "where": where, "slot": slot, "blocked": false}

func gain_hero(unit: Dictionary, tier: int, _allow_echo: bool = true, auto_deploy: bool = true, _metadata: Dictionary = {}) -> Dictionary:
	var plan := _gain_plan(unit, tier, auto_deploy)
	if bool(plan["blocked"]):
		return {}
	var where := String(plan["where"])
	var list: Array = heroes if where == "field" else bench
	var hero: Dictionary
	if String(plan["kind"]) == "growth":
		hero = list[int(plan["slot"])]
		hero["growth_points"] = int(plan["points"])
		hero["tier"] = int(plan["after_tier"])
	else:
		hero = {"unit": unit, "tier": tier, "n": 1, "wave": 1, "growth_points": 0}
		list.append(hero)
		ensure_posts()
	best_tier = maxi(best_tier, int(hero["tier"]))
	Save.note_unit(String(unit["id"]), int(hero["tier"]))
	if sim != null:
		sim.refresh_heroes()
	return {"kind": plan["kind"], "unit": unit, "tier": tier, "before_tier": plan["before_tier"],
		"after_tier": int(hero["tier"]), "added_points": plan["added_points"],
		"growth_points": int(hero["growth_points"]), "maxed": int(hero["tier"]) >= Balance.TIER_MAX,
		"where": where, "slot": plan["slot"], "stacked": plan["kind"] == "growth", "n": 1}

## The stars a card would really give when picked: 「조커」 adds one (up to 5). 「도박꾼의 눈」 is a hidden roll at
## the pick and is not counted.
func _picked_stars(card: Dictionary) -> int:
	var stars := int(card["stars"])
	return mini(JewelBox.MAX_STARS, stars + 1) if has("joker") else stars

## What picking card `index` would do (for the card's badge: NEW on the field or the bench, or growth from
## before_tier to after_tier, MAX when maxed). Nothing changes. Shaped {kind, before_tier, after_tier,
## added_points, maxed, where, stars, joker}.
func card_preview(index: int) -> Dictionary:
	if index < 0 or index >= box_cards.size():
		return {}
	var card: Dictionary = box_cards[index]
	var stars := _picked_stars(card)
	var plan := _gain_plan(card["unit"], JewelBox.tier_of(stars))
	return {"kind": plan["kind"], "before_tier": plan["before_tier"], "after_tier": plan["after_tier"],
		"added_points": plan["added_points"], "maxed": plan["maxed"], "where": plan["where"],
		"stars": stars, "joker": stars > int(card["stars"])}

## Pick card `index` of the open box. 「조커」 makes it one star more (up to 5); 「도박꾼의 눈」 gives an
## PASSIVE_EYE_P chance of half a star more (rolled now, shown as `bumped`). The hero joins (or grows), the box
## stays on screen with the result (phase SWAP) and the run saves. Picking again returns the same result.
func pick_card(index: int) -> Dictionary:
	if modal == "box" and phase == Phase.SWAP:
		return summon_result
	if not running or modal != "box" or phase != Phase.DRAW or index < 0 or index >= box_cards.size():
		return {}
	var card: Dictionary = box_cards[index]
	var unit: Dictionary = card["unit"]
	var stars := _picked_stars(card)
	var tier := JewelBox.tier_of(stars)
	last_bumped = has("eye") and tier < Balance.TIER_MAX and rng.randf() < Balance.PASSIVE_EYE_P
	if last_bumped:
		tier += 1
	var result := gain_hero(unit, tier)
	if result.is_empty():
		return {}
	last_joker = index if stars > int(card["stars"]) else -1
	last_unit = unit
	last_tier = tier
	summon_result = result
	summon_result.merge({"stars": stars, "box": box_tier, "card": index, "guaranteed": bool(card["guaranteed"]),
		"bumped": last_bumped, "joker": stars > int(card["stars"]), "growth_needed": _growth_need(int(result["after_tier"]))})
	last_result = summon_result
	summon_count += 1
	phase = Phase.SWAP
	Save.record_summon(tier, String(unit["id"]), false)
	autosave()
	return summon_result

## Pick a card — the best one when `index` is negative (JewelBox.best). Kept for the auto-play and the checks.
func confirm_summon(index: int = -1) -> Dictionary:
	if modal == "box" and phase == Phase.SWAP:
		return summon_result
	return pick_card(index if index >= 0 else JewelBox.best(box_cards))

## "bench" 는 출전 교체, "talent" 는 별자리 보기(고를 것이 없을 때의 열람). 레벨업으로 열리는
## 별자리 팝업은 offer_levelup() 이 연다 — 상점("shop")은 없어졌다(골드는 뽑기에만 쓴다).
func open_modal(name: String) -> bool:
	if not running or not modal.is_empty() or name not in ["talent", "bench"]:
		return false
	modal = name
	phase = Phase.SHOP if name == "talent" else Phase.SWAP
	autosave()
	return true

## 별자리 팝업에 고를 노드가 남아 있으면 닫히지 않는다 — 하나를 골라야 전투가 이어진다.
func close_modal() -> bool:
	if not running or modal in ["theme", "result"] or (modal == "box" and phase == Phase.DRAW):
		return false
	if modal == "talent" and not talent_offer.is_empty():
		return false
	# A box closes once its card is picked; it is gone then (the next box rolls anew).
	if modal == "box":
		box_tier = 0
		box_cards.clear()
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

## 골드로 사는 능력치·패시브는 없다(2026-10-17). 옛 입력이 들어와도 아무것도 팔지 않는다.
func buy_upgrade(_id: String) -> bool:
	return false

func buy_passive(_id: String) -> bool:
	return false

## 별자리로 얻은 패시브는 칸 제한 없이 전부 켜져 있다 — 끄고 켤 것이 없다.
func toggle_passive(_id: String) -> bool:
	return false

func roll_shop() -> void:
	shop_offer.clear()

# --------------------------------------------------------------------------- #
# 경험치 · 레벨 · 별자리
# --------------------------------------------------------------------------- #
## 다음 레벨까지 필요한 경험치.
func xp_needed() -> int:
	return Balance.arena_xp_needed(level)

## 처치 경험치를 올린다. 오른 레벨 수를 돌려준다(시뮬레이터가 이벤트를 적는다). 팝업은
## 여기서 열지 않는다 — 걸음 끝에 offer_levelup() 이 연다.
func gain_xp(amount: float) -> int:
	if not running or amount <= 0.0:
		return 0
	xp += amount * mod("xp")
	var gained := 0
	while xp >= float(xp_needed()):
		xp -= float(xp_needed())
		level += 1
		pending_levels += 1
		gained += 1
	return gained

## 고르지 않은 레벨업이 있으면 별자리 셋을 내놓고 팝업을 연다. 열린 노드가 하나도 없으면
## 그 레벨은 골드로 바꿔 준다(끝까지 간 판).
## ★ 정비 시간에만 연다(PLAN M4) — 웨이브 중에 오른 레벨은 쌓여 있다가 다음 정비가 시작될 때 뜬다.
func offer_levelup() -> bool:
	if not running or not modal.is_empty() or pending_levels <= 0:
		return false
	if sim != null and not sim.in_prep():
		return false
	_roll_offer()
	if talent_offer.is_empty():
		add_gold(Balance.ARENA_LEVELUP_GOLD * pending_levels)
		pending_levels = 0
		autosave()
		return false
	modal = "talent"
	phase = Phase.SHOP
	autosave()
	return true

func _roll_offer() -> void:
	talent_offer = Talents.roll_offer(rng, talents, owned_passives, levels)

## 몇 번 골랐나.
func talent_count(id: String) -> int:
	return int(talents.get(id, 0))

## 내놓은 셋 중 하나를 고른다. 효과는 바로 걸리고, 고를 레벨이 더 남았으면 새 셋을 내놓는다.
func pick_talent(id: String) -> bool:
	if not running or modal != "talent" or not talent_offer.has(id):
		return false
	var node := Talents.by_id(id)
	if node.is_empty():
		return false
	talents[id] = talent_count(id) + 1
	for raw in Talents.effect_keys(node):
		var key := String(raw)
		var value: float = float(node[key])
		if key.begins_with("lv_"):
			var up: String = key.trim_prefix("lv_")
			var cap := int(Balance.upgrade_by_id(up).get("cap", 0))
			var next := lv(up) + int(value)
			levels[up] = next if cap <= 0 else mini(next, cap)
		elif key.begins_with("grant_"):
			var pid := key.trim_prefix("grant_")
			if not owned_passives.has(pid):
				owned_passives.append(pid)
			if not passives.has(pid):
				passives.append(pid)
		elif key == "now_heal" and sim != null:
			sim.heal_crystal(value)
		elif key == "now_gold":
			add_gold(int(value))
		elif key == "now_tier":
			promote_lowest(int(value))
	_refresh_mods()
	pending_levels = maxi(0, pending_levels - 1)
	talent_offer.clear()
	if pending_levels > 0:
		_roll_offer()
	if talent_offer.is_empty():
		if pending_levels > 0:
			add_gold(Balance.ARENA_LEVELUP_GOLD * pending_levels)
			pending_levels = 0
		modal = ""
		phase = Phase.BATTLE
	if sim != null:
		sim.refresh_heroes()
	autosave()
	return true

## 별자리 「승급」 — 출전 영웅 중 가장 낮은 등급 한 명을 `steps` 성급 올린다(최대 등급 미만만).
func promote_lowest(steps: int = 1) -> bool:
	var low := -1
	for i in range(heroes.size()):
		if int(heroes[i]["tier"]) >= Balance.TIER_MAX:
			continue
		if low < 0 or int(heroes[i]["tier"]) < int(heroes[low]["tier"]):
			low = i
	if low < 0:
		return false
	var hero: Dictionary = heroes[low]
	hero["tier"] = mini(Balance.TIER_MAX, int(hero["tier"]) + maxi(1, steps))
	if int(hero["tier"]) >= Balance.TIER_MAX:
		hero["growth_points"] = 0
	else:
		hero["growth_points"] = mini(int(hero.get("growth_points", 0)), growth_needed(hero) - 1)
	best_tier = maxi(best_tier, int(hero["tier"]))
	Save.note_unit(String(hero["unit"]["id"]), int(hero["tier"]))
	return true

func _refresh_mods() -> void:
	mods = Talents.effects(talents)

## 별자리의 곱하는 효과(없으면 1.0) · 더하는 효과(없으면 0.0). 전투(BattleSim._mod)가 읽는다.
func mod(key: String) -> float:
	return Talents.mult(mods, key)

func mod_add(key: String) -> float:
	return Talents.add(mods, key)

## 패시브 배수에 별자리의 같은 열쇠를 함께 곱한다(radius · gold …). 전투와 정보가 같은 값을 본다.
func pas_mult(key: String) -> float:
	return super.pas_mult(key) * mod(key)

func pas_add(key: String) -> float:
	return super.pas_add(key) + mod_add(key)

func hero_stats(h: Dictionary) -> Dictionary:
	return CombatStats.hero(h, levels, passives, heroes, mods)

## The stage is over: a clear unlocks the next stage and becomes the last clear (Save.record_stage), then
## the lifetime totals and the file (Save.record_run).
func end_run(won: bool) -> void:
	if not running:
		return
	running = false
	phase = Phase.WIN if won else Phase.OVER
	modal = "result"
	# Hellbound keeps its own record (the best wave) and never touches the ladder's unlock, last clear or
	# best stage; its kills still count.
	if hell:
		Save.record_hell(sim.wave_reached() if sim != null else 0)
	else:
		Save.record_stage(stage, String(theme_for(1).get("id", "")), won)
		# The attempt is over: the next one at this stage rolls a new seed.
		Save.end_stage_seed(stage)
	Save.record_run(0 if hell else stage, kills, won)

func _arena_heroes_out(list: Array) -> Array:
	var out: Array = []
	for hero in list:
		out.append({"u": String(hero["unit"]["id"]), "t": int(hero["tier"]), "p": hero_position(hero), "points": int(hero.get("growth_points", 0))})
	return out

func snapshot(_include_checkpoint: bool = true) -> Dictionary:
	return {"mode": "arena", "v": SAVE_V, "wave": stage, "stage": stage,
		"seed": run_seed, "rng": rng.state,
		"phase": phase, "modal": modal, "theme_index": theme_index, "selected": selected,
		"gold": gold, "lives": lives, "kills": kills, "best_tier": best_tier,
		"heroes": _arena_heroes_out(heroes), "bench": _arena_heroes_out(bench),
		"levels": levels.duplicate(), "passives": Array(passives), "owned_passives": Array(owned_passives),
		"hero_damage": hero_damage.duplicate(true),
		"xp": xp, "level": level, "talents": talents.duplicate(), "talent_offer": Array(talent_offer),
		"pending_levels": pending_levels, "summon_count": summon_count,
		"box": {"tier": box_tier, "cards": _box_out(), "spins": spins, "paid": paid_spins},
		"hell": hell, "squad": _squad_out(), "revive_gift": _gift_out(),
		"summon_result": summon_result.duplicate(true), "sim": sim.snapshot_arena() if sim != null else {}}

## A plain copy of the squad's ids (`Array(squad)` would hand out the live list itself).
func _squad_out() -> Array:
	var out: Array = []
	out.append_array(squad)
	return out

func _gift_out() -> Dictionary:
	if revive_gift.is_empty():
		return {}
	return {"u": String(revive_gift["unit"]["id"]), "t": int(revive_gift["tier"]), "where": String(revive_gift["where"]), "slot": int(revive_gift["slot"])}

func _box_out() -> Array:
	var out: Array = []
	for card in box_cards:
		out.append({"u": String(card["unit"]["id"]), "s": int(card["stars"]), "g": bool(card["guaranteed"])})
	return out

func restore(data: Dictionary) -> bool:
	if not ArenaValidation.valid(data):
		return false
	run_seed = int(data["seed"])
	rng.seed = run_seed
	rng.state = int(data["rng"])
	# Numbers held to tuning values come back inside today's limits (ArenaValidation only holds them to
	# fixed caps, so a moved value never voids a run in progress).
	stage = clampi(int(data["stage"]), 1, Balance.ARENA_LADDER)
	wave = stage
	hell = data.get("hell", false) == true
	squad.assign(data.get("squad", []))
	var gift: Dictionary = data.get("revive_gift", {})
	revive_gift = {} if gift.is_empty() else {"unit": Roster.unit_by_id(String(gift["u"])), "tier": int(gift["t"]),
		"where": String(gift["where"]), "slot": int(gift["slot"])}
	running = true
	phase = int(data["phase"])
	modal = String(data["modal"])
	theme_index = int(data["theme_index"])
	# The ladder copy, with the saved battlefield in its place (a tool may have chosen another).
	stage_themes.clear()
	for number in range(1, Balance.ARENA_LADDER + 1):
		stage_themes.append(ladder_theme(number))
	stage_themes[stage - 1] = theme_index
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(theme_index))
	selected = int(data["selected"])
	gold = int(data["gold"])
	lives = clampi(int(data["lives"]), 1, Balance.MAX_LIVES)
	kills = int(data["kills"])
	best_tier = int(data["best_tier"])
	heroes.clear()
	bench.clear()
	for group in ["heroes", "bench"]:
		var list: Array = heroes if group == "heroes" else bench
		for saved in data[group]:
			list.append({"unit": Roster.unit_by_id(String(saved["u"])), "tier": int(saved["t"]), "position": Vector2(saved["p"]), "growth_points": int(saved["points"]), "n": 1, "wave": 1})
	levels = data["levels"].duplicate()
	for id in levels:
		var cap := int(Balance.upgrade_by_id(String(id)).get("cap", 0))
		if cap > 0: levels[id] = mini(int(levels[id]), cap)
	passives.assign(data["passives"])
	owned_passives.assign(data["owned_passives"])
	hero_damage = data["hero_damage"].duplicate(true)
	shop_offer.clear()
	xp = float(data["xp"])
	level = int(data["level"])
	talents = {}
	for id in data["talents"]:
		talents[String(id)] = mini(int(data["talents"][id]), maxi(1, int(Balance.talent_by_id(String(id)).get("max", 1))))
	talent_offer.assign(data["talent_offer"])
	pending_levels = int(data["pending_levels"])
	_refresh_mods()
	summon_count = int(data["summon_count"])
	orbit.clear()
	var box: Dictionary = data["box"]
	box_tier = int(box["tier"])
	box_cards.clear()
	for card in box["cards"]:
		box_cards.append({"unit": Roster.unit_by_id(String(card["u"])), "stars": int(card["s"]), "guaranteed": bool(card["g"])})
	spins = int(box["spins"])
	paid_spins = int(box["paid"])
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
