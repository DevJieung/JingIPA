extends Harness

## Auto-play of the stage ladder and of Hellbound for the balance pass (2026-10-19 LA4, the 「실측」 part of
## docs/STAGE_LADDER_2026-10-19.md). The player is meant to be an ordinary person, a little below a real one:
##   - preparation: opens the boxes its gold buys (from wave 4 on it keeps one skill's gold), spends the free
##     rerolls hoping the box grade rises by one, takes an anti-air card while nobody shoots the sky and
##     flyers are coming, otherwise the most stars; fields its six best, posts them where the roads reach the
##     plaza and starts the wave at once (the time tables add the full preparation back);
##   - level-ups: a fixed list of plain nodes (attack, speed, crit …);
##   - during a wave: walks an idle hero to what comes close; the starburst on the best cluster
##     (cast_skill("blast", point) — a body no fielded hero can hurt, an immune one or a flyer nobody shoots,
##     weighs more, an elite or the boss most) and at once on a striker of the crystal nobody can hurt or
##     while the crystal is under half; the frost when the crystal is threatened, the ward when the boss
##     strikes it; half a box of gold is kept unless it is an emergency;
##   - never counters elements.
## Everything follows the run seed: the same code gives the same sample.
##
##   godot --headless --path . res://tests/arena_balance_check.tscn -- --runs 4 --stages 1,5,10
##   --from K        first seed 1000 + K (Hellbound 2000 + K)
##   --dlc           with the DLC (three free rerolls, revival tickets); --blessing is the old name
##   --uses N        with the DLC, play as if ARENA_REVIVE_USES were N (to measure a DB proposal)
##   --speed F       monsters walk F times as fast (to measure a DB proposal on PATH_SPEED / road length)
##   --blast-r R     the starburst's radius as if ARENA_BLAST_RADIUS were R (to measure a DB proposal)
##   --hell 3|4      Hellbound with six heroes centred on 3 or 4 stars; --max-wave W stops a run (default 60)
##   --rows          also print one `ROW {json}` line per run (scratch tools merge parallel samples)
##   --report        print the tables only, no verdict
##   --min-win P     verdict: every sampled stage wins at least this share of its runs (default 0.75)
##   --time A,B      verdict: the median stage time (battle + the full preparation, 1x) lies in A..B seconds
##   --wall A,B      verdict: the median time with the windows (card, boxes, nodes) lies in A..B seconds
##   --no-skills     never cast the common skills · --think S  look at the field every S seconds (default 0.5)
##   --detail        print each wave's length · --trace  print the field every ten seconds
class Owner extends RefCounted:
	const NAME := "test"
	var store: Node
	var owned: Array = []
	func start() -> void: store.set_owned(owned)
	func sells(_id: String) -> bool: return false
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void: store.finish_restore(true)
	func buy(product: Dictionary) -> void: store.finish_purchase(String(product["id"]), "unavailable")

## Just outside the altar, so a sword reaches whatever is hitting the crystal.
const POST := 104.0
const STEP := 1.0 / 30.0
## How often the player looks at the field during a wave (seconds of battle).
const THINK := 0.5
## Monsters this close to the crystal are a threat.
const NEAR := 220.0
## A stage that has not ended after this much battle time counts as stalled (a bug, not balance).
const STALL_SECONDS := 900.0
## Assumed seconds of the windows a person sits through: the stage card, a level-up node, and a box — its
## ceremony measured 2.7 s plain up to 7.5 s with rerolls (D1), so 2.7 s plus BOX_REROLL_SECONDS a reroll.
const CARD_SECONDS := 3.0
const NODE_SECONDS := 3.0
const BOX_SECONDS := 2.7
const BOX_REROLL_SECONDS := 1.6
const BOX_SECONDS_MAX := 7.5
## Hellbound's squad: two that shoot the sky, every element, five weapons.
const HELL_SQUAD := ["limne", "chispa", "lind", "brigid", "pip", "phorkys"]
var _turn := 0

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	var owner := Owner.new()
	var dlc := has_arg("--dlc") or has_arg("--blessing") or has_arg("--hell")
	if dlc: owner.owned = [Store.GUARDIAN]
	Store.use_backend(owner)
	var ok := true
	if has_arg("--hell"):
		_hell_sample()
	else:
		ok = _ladder_sample(dlc)
	Store.use_backend(null)
	Arena.running = false
	Arena.hell = false
	if has_arg("--report") or has_arg("--hell"):
		get_tree().quit(0)
		return
	check(ok, "사다리 표본 판정")
	finish("수호전 사다리 자동 플레이")

func _ladder_sample(dlc: bool) -> bool:
	var runs := arg_int("--runs", 4)
	var first := arg_int("--from", 0)
	var stages: Array[int] = []
	for part in arg("--stages", "1,5,10").split(","):
		if part.strip_edges().is_valid_int(): stages.append(clampi(int(part), 1, Balance.ARENA_LADDER))
	var results: Array = []
	for stage in stages:
		for n in range(runs):
			var result := _play(1000 + first + n, stage, [])
			results.append(result)
			_print_run(result)
	print("")
	_print_table(results)
	var wins := 0
	var stalled := 0
	var times: Array = []
	var walls: Array = []
	var battles: Array = []
	var boxes := 0
	var casts := 0
	for result in results:
		if bool(result["won"]): wins += 1
		if bool(result["stalled"]): stalled += 1
		times.append(float(result["stage_time"]))
		walls.append(float(result["wall"]))
		battles.append(float(result["battle"]))
		boxes += int(result["boxes"])
		casts += int(result["blast"]) + int(result["freeze"]) + int(result["ward"])
	var played := maxi(1, results.size())
	var median := _median(times)
	print("")
	print("사다리 표본: STAGE %s · 승리 %d/%d판 · 스테이지 시간 중앙값 %s(전투 %s + 정비) · 창 포함 %s · 상자 %.1f · 스킬 %.1f회%s" % [
		",".join(PackedStringArray(stages.map(func(s: int) -> String: return str(s)))), wins, results.size(), _clock(median),
		_clock(_median(battles)), _clock(_median(walls)), float(boxes) / played, float(casts) / played, "  (DLC)" if dlc else ""])
	# The verdict: nothing stalls, every sampled stage wins often enough, the stage takes a sensible time.
	var ok := stalled == 0 and not results.is_empty()
	if stalled > 0: printerr("!! 멈춘 판 %d/%d" % [stalled, results.size()])
	var floor_share := arg_float("--min-win", 0.75)
	for stage in stages:
		var plays := 0
		var won := 0
		for result in results:
			if int(result["stage"]) != stage: continue
			plays += 1
			if bool(result["won"]): won += 1
		if plays > 0 and float(won) / float(plays) < floor_share - 0.0001:
			ok = false
			printerr("!! STAGE %d 승률 %d/%d — 하한 %.0f%%" % [stage, won, plays, floor_share * 100.0])
	for check_spec in [["--time", median, "스테이지 시간"], ["--wall", _median(walls), "창 포함 시간"]]:
		var span := arg(String(check_spec[0]), "")
		if not span.contains(","): continue
		var low := float(span.get_slice(",", 0))
		var high := float(span.get_slice(",", 1))
		var value := float(check_spec[1])
		if value < low or value > high:
			ok = false
			printerr("!! %s 중앙값 %s — 범위 %s~%s" % [check_spec[2], _clock(value), _clock(low), _clock(high)])
	return ok

## Hellbound with six heroes centred on 3 or 4 stars (four at it, one a star lower, one a star higher).
func _hell_sample() -> void:
	var stars := clampi(arg_int("--hell", 4), 2, 4)
	var grades: Array = [stars, stars, stars, stars, stars - 1, mini(JewelBox.MAX_STARS, stars + 1)]
	var kept := {"seen": Save.seen_units.duplicate(), "best": Save.unit_best.duplicate(), "hell": Save.hell_best_wave,
		"squad": Save.hell_squad.duplicate()}
	Save.seen_units = {}
	Save.unit_best = {}
	for i in range(HELL_SQUAD.size()):
		Save.seen_units[HELL_SQUAD[i]] = true
		Save.unit_best[HELL_SQUAD[i]] = JewelBox.tier_of(int(grades[i]))
	var runs := arg_int("--runs", 4)
	var first := arg_int("--from", 0)
	var reached: Array = []
	for n in range(runs):
		var result := _play(2000 + first + n, 0, HELL_SQUAD)
		reached.append(int(result["waves"]))
		_print_run(result)
	reached.sort()
	print("")
	print("Hellbound 표본: %d성 위주 6명 · 도달 웨이브 중앙값 %.0f (%d~%d) · %d판" % [stars, _median(reached),
		int(reached[0]) if not reached.is_empty() else 0, int(reached[-1]) if not reached.is_empty() else 0, runs])
	Save.seen_units = kept["seen"]
	Save.unit_best = kept["best"]
	Save.hell_best_wave = kept["hell"]
	Save.hell_squad = kept["squad"]

## One stage (or one Hellbound run when `squad` is given), played to its end.
func _play(seed_value: int, stage: int, squad: Array) -> Dictionary:
	var hell := not squad.is_empty()
	if hell:
		Arena.start_hellbound(squad, seed_value)
	else:
		Arena.start_run(seed_value, stage)
	var uses := arg_int("--uses", -1)
	if uses >= 0 and Arena.sim != null:
		Arena.sim.revives = clampi(Balance.ARENA_REVIVE_USES - uses, 0, Balance.ARENA_REVIVE_USES)
	_turn = 0
	var r := {"stage": Arena.stage, "seed": seed_value, "hell": hell, "dlc": Arena.dlc(), "boxes": 0, "box_best": 0, "rerolls": 0, "box_time": 0.0,
		"nodes": 0, "gold_box": 0, "gold_skill": 0, "blast": 0, "freeze": 0, "ward": 0,
		"field": String(Roster.THEMES[Arena.theme_index]["main_body"]).substr(0, 2) + String(ArenaGeometry.layout_for_theme(Arena.theme_index)).substr(0, 2)}
	var gold_start: int = Arena.gold
	var max_wave := arg_int("--max-wave", 60)
	var limit := STALL_SECONDS if not hell else 240.0 * float(max_wave)
	var think := 0.0
	var damage := 0.0
	var prep_time := 0.0
	var revives_seen: int = Arena.sim.revives if Arena.sim != null else 0
	var placed_for := -1
	var stalled := false
	var capped := false
	var wave_from := 0.0
	var wave_times: Array = []
	var speed := arg_float("--speed", 1.0)
	var hastened := 0
	while Arena.running:
		match Arena.modal:
			"stage":
				Arena.confirm_stage()
				continue
			"box":
				_box(r)
				continue
			"talent":
				if _pick_talent(): r["nodes"] = int(r["nodes"]) + 1
				continue
			"bench":
				Arena.close_modal()
				continue
		var sim: ArenaSim = Arena.sim
		if hell and sim.wave_no > max_wave:
			capped = true
			break
		if sim.elapsed > limit:
			stalled = true
			break
		if sim.in_prep() and sim.clear_t == 0.0:
			# Preparation: field the best, buy what the gold allows, post everyone, then start at once.
			if placed_for != sim.wave_no:
				placed_for = sim.wave_no
				_field_best()
				_place()
			var keep := 0 if sim.wave_no < 4 else mini(Balance.ARENA_BLAST_GOLD, Balance.ARENA_FREEZE_GOLD)
			var cost: int = Arena.summon_cost()
			if Arena.can_summon() and Arena.gold - cost >= keep:
				if Arena.begin_summon(): r["gold_box"] = int(r["gold_box"]) + cost
				continue
			sim.skip_prep()
		var hp_before: float = sim.crystal_hp
		var prepping := sim.in_prep()
		sim.step(STEP)
		if prepping: prep_time += STEP
		# --speed: every newcomer walks faster (spawn ids only grow).
		if speed != 1.0:
			for mo in sim.monsters:
				if int(mo["spawn_id"]) > hastened:
					mo["spd"] = float(mo["spd"]) * speed
			for mo in sim.monsters: hastened = maxi(hastened, int(mo["spawn_id"]))
		# Each wave's length (nothing reads the events here, so they are dropped as they come).
		for e in sim.events:
			match String(e.get("t", "")):
				"arena_wave": wave_from = sim.elapsed
				"arena_wave_clear": wave_times.append(snappedf(sim.elapsed - wave_from, 0.1))
		sim.events.clear()
		# Damage taken (a revival counts as losing it all). A revival's hero may be on the bench.
		if sim.clear_t == 0.0:
			if sim.revives > revives_seen:
				revives_seen = sim.revives
				damage += hp_before
				if Arena.running and Arena.modal.is_empty():
					_field_best()
					_place()
			elif sim.crystal_hp < hp_before:
				damage += hp_before - sim.crystal_hp
		think += STEP
		if think >= arg_float("--think", THINK) and Arena.running and Arena.modal.is_empty() and sim.clear_t == 0.0 and not sim.in_prep():
			think = 0.0
			_think(sim, r)
			if has_arg("--trace") and int(sim.elapsed * 2.0) % 20 == 0: _trace(sim)
	var end: ArenaSim = Arena.sim
	var won: bool = end.won
	var fought: int = Balance.ARENA_WAVES if won else end.wave_no
	var battle := end.elapsed - prep_time
	# The preparations a person would sit through had they never pressed 「바로 시작」.
	var stage_time := battle
	for w in range(1, fought + 1): stage_time += Balance.arena_prep(w, 0 if hell else Balance.ARENA_WAVES)
	r.merge({"won": won, "stalled": stalled, "capped": capped,
		"waves": end.wave_reached() if hell else fought, "damage": damage, "battle": battle, "prep": prep_time,
		"stage_time": stage_time, "wall": stage_time + CARD_SECONDS + float(r["box_time"]) + NODE_SECONDS * float(r["nodes"]), "pace": end.pace(),
		"level": Arena.level, "hero_best": Arena.best_tier, "kills": Arena.kills, "revives": end.revives, "wave_times": wave_times,
		"gold_in": Arena.gold - gold_start + int(r["gold_box"]) + int(r["gold_skill"])}, true)
	if hell: Arena.running = false
	return r

func _print_run(r: Dictionary) -> void:
	var head := ("HELL %d성" % arg_int("--hell", 4)) if bool(r["hell"]) else "STAGE %3d" % int(r["stage"])
	var verdict := ("도달 WAVE %d%s" % [int(r["waves"]), " (상한)" if bool(r["capped"]) else ""]) if bool(r["hell"]) \
		else "%s  WAVE %2d/%d" % ["승리" if bool(r["won"]) else "패배", int(r["waves"]), Balance.ARENA_WAVES]
	print("%s  seed %d  %s  수정 피해 %4.0f  전투 %5.1f초  정비 포함 %s  창 포함 %s  상자 %d(최고 %d성)  레벨 %d  골드 +%d / 상자 %d / 스킬 %d  폭발 %d 서리 %d 방벽 %d  부활 %d  %s%s" % [
		head, int(r["seed"]), verdict, float(r["damage"]), float(r["battle"]), _clock(float(r["stage_time"])), _clock(float(r["wall"])),
		int(r["boxes"]), int(r["box_best"]), int(r["level"]), int(r["gold_in"]), int(r["gold_box"]), int(r["gold_skill"]),
		int(r["blast"]), int(r["freeze"]), int(r["ward"]), int(r["revives"]), String(r["field"]), "  (멈춤)" if bool(r["stalled"]) else ""])
	if has_arg("--rows"):
		print("ROW " + JSON.stringify(r))
	if has_arg("--detail"):
		print("    웨이브 길이(초): " + ", ".join(PackedStringArray(Array(r["wave_times"]).map(func(t: float) -> String: return "%.0f" % t))))

func _print_table(results: Array) -> void:
	print("STAGE  판  승  전투(중앙)  정비 포함  창 포함  수정 피해  진 웨이브  레벨  상자(최고)  골드 수입/상자/스킬  폭발/서리/방벽  부활")
	var stages: Array = []
	for result in results:
		if not stages.has(int(result["stage"])): stages.append(int(result["stage"]))
	for stage in stages:
		var rows: Array = results.filter(func(result: Dictionary) -> bool: return int(result["stage"]) == stage)
		var n := float(rows.size())
		var won := 0
		var lost_waves: Array = []
		var sums := {}
		var best := 0
		for key in ["damage", "level", "boxes", "gold_in", "gold_box", "gold_skill", "blast", "freeze", "ward", "revives"]: sums[key] = 0.0
		for result in rows:
			if bool(result["won"]): won += 1
			else: lost_waves.append(int(result["waves"]))
			for key in sums: sums[key] = float(sums[key]) + float(result[key])
			best = maxi(best, int(result["box_best"]))
		print("%5d  %2d  %2d  %9s  %9s  %7s  %9.0f  %9s  %4.1f  %4.1f(%d성)  %6.0f/%4.0f/%4.0f  %4.1f/%4.1f/%4.1f  %4.1f" % [stage, rows.size(), won,
			_clock(_median(rows.map(func(x: Dictionary) -> float: return float(x["battle"])))),
			_clock(_median(rows.map(func(x: Dictionary) -> float: return float(x["stage_time"])))),
			_clock(_median(rows.map(func(x: Dictionary) -> float: return float(x["wall"])))),
			float(sums["damage"]) / n, ("%.1f" % _median(lost_waves)) if not lost_waves.is_empty() else "-", float(sums["level"]) / n,
			float(sums["boxes"]) / n, best, float(sums["gold_in"]) / n, float(sums["gold_box"]) / n, float(sums["gold_skill"]) / n,
			float(sums["blast"]) / n, float(sums["freeze"]) / n, float(sums["ward"]) / n, float(sums["revives"]) / n])

static func _median(values: Array) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	return float(sorted[mid]) if sorted.size() % 2 == 1 else (float(sorted[mid - 1]) + float(sorted[mid])) * 0.5

static func _clock(seconds: float) -> String:
	var whole := roundi(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]

## A jewel box: the free rerolls are spent while the box grade has not risen by one (a reroll never lowers
## it), then the pick.
func _box(r: Dictionary) -> void:
	if Arena.phase == Arena.Phase.DRAW:
		var opened: int = Arena.box_tier
		var spun := 0
		while Arena.can_respin() and Arena.box_tier < mini(opened + 1, JewelBox.MAX_STARS):
			Arena.respin()
			spun += 1
		r["rerolls"] = int(r["rerolls"]) + spun
		r["box_time"] = float(r["box_time"]) + minf(BOX_SECONDS_MAX, BOX_SECONDS + BOX_REROLL_SECONDS * float(spun))
		r["boxes"] = int(r["boxes"]) + 1
		r["box_best"] = maxi(int(r["box_best"]), Arena.box_tier)
		Arena.confirm_summon(_choice())
	Arena.close_modal()
	_field_best()
	_place()

## Without an anti-air hero on a stage whose waves bring flyers, an anti-air card first (the box guarantees
## one); otherwise the most stars, a new hero while the field has room, else growth for a fielded hero.
func _choice() -> int:
	var wants_air := Arena.anti_air_needed()
	var best := -1
	var best_score := -1.0
	for i in range(Arena.box_cards.size()):
		var card: Dictionary = Arena.box_cards[i]
		var preview: Dictionary = Arena.card_preview(i)
		var score := float(card["stars"]) * 10.0
		if wants_air and Balance.anti_air(card["unit"]): score += 100.0
		if String(preview.get("kind", "")) == "new" and String(preview.get("where", "")) == "field": score += 2.0
		elif String(preview.get("kind", "")) == "growth" and String(preview.get("where", "")) == "field": score += 1.0
		if score > best_score:
			best_score = score
			best = i
	return best

## Field the six highest grades.
func _field_best() -> void:
	if Arena.bench.is_empty() or Arena.heroes.size() < Balance.ARENA_HERO_LIMIT: return
	for attempt in range(8):
		var low := 0
		for i in range(Arena.heroes.size()):
			if int(Arena.heroes[i]["tier"]) < int(Arena.heroes[low]["tier"]): low = i
		var high := 0
		for i in range(Arena.bench.size()):
			if int(Arena.bench[i]["tier"]) > int(Arena.bench[high]["tier"]): high = i
		if int(Arena.bench[high]["tier"]) <= int(Arena.heroes[low]["tier"]): return
		if not Arena.open_modal("bench"): return
		Arena.swap_hero(low, high)
		Arena.close_modal()

## Posts beside the points where this battlefield's roads reach the plaza.
func _place() -> void:
	var arrivals: Array[float] = []
	for lane in range(ArenaGeometry.route_count()):
		var path := ArenaGeometry.route_points(lane)
		var angle := (path[path.size() - 2] - Balance.ARENA_CENTER).angle()
		var fresh := true
		for other in arrivals:
			if absf(angle_difference(angle, other)) < 0.35: fresh = false
		if fresh: arrivals.append(angle)
	for i in range(Arena.heroes.size()):
		var lap := i / arrivals.size()
		var spread := float((lap + 1) / 2) * 0.58 * (1.0 if lap % 2 == 1 else -1.0)
		Arena.heroes[i]["position"] = Balance.ARENA_CENTER + Vector2.from_angle(arrivals[i % arrivals.size()] + spread) * POST
	if Arena.sim != null: Arena.sim.refresh_heroes()

## A hero with nothing in reach walks to the monster nearest the crystal (what a player
## does with the joystick); a hero that is fighting stays where it is.
func _cover(sim: ArenaSim) -> void:
	if sim.monsters.is_empty(): return
	var target: Dictionary = sim.monsters[0]
	for mo in sim.monsters:
		if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) < Vector2(target["pos"]).distance_to(Balance.ARENA_CENTER): target = mo
	var at: Vector2 = target["pos"]
	# Only what has come close matters; the rest is still walking the road.
	if at.distance_to(Balance.ARENA_CENTER) > 260.0: return
	var moved := false
	for i in range(sim.heroes.size()):
		var from: Vector2 = sim.heroes[i]["pos"]
		var busy := false
		for mo in sim.monsters:
			if from.distance_to(mo["pos"]) <= float(sim.heroes[i]["range"]):
				busy = true
				break
		if busy: continue
		var angle := (at - Balance.ARENA_CENTER).angle()
		for turn in [0.0, 0.36, -0.36, 0.72, -0.72, 1.08, -1.08]:
			var post := Balance.ARENA_CENTER + Vector2.from_angle(angle + turn) * POST
			var free := true
			for j in range(sim.heroes.size()):
				if j != i and Vector2(Arena.heroes[j]["position"]).distance_to(post) < Balance.ARENA_HERO_RADIUS * 2.0: free = false
			if free:
				Arena.heroes[i]["position"] = post
				moved = true
				break
	if moved: sim.refresh_heroes()

func _think(sim: ArenaSim, r: Dictionary) -> void:
	if not has_arg("--no-skills"): _skills(sim, r)
	_cover(sim)
	_turn += 1

## The three common skills during a wave, each within a gold budget: half a box is kept for the next
## preparation unless it is an emergency (the boss near, the crystal under half).
func _skills(sim: ArenaSim, r: Dictionary) -> void:
	if has_arg("--blast-r"):
		Arena.mods["blast_r"] = Talents.mult(Talents.effects(Arena.talents), "blast_r") * arg_float("--blast-r", Balance.ARENA_BLAST_RADIUS) / Balance.ARENA_BLAST_RADIUS
	var siege_r := Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 12.0
	var near := 0
	var siege := 0
	var boss_near := false
	var boss_siege := false
	for mo in sim.monsters:
		if float(mo["hp"]) <= 0.0: continue
		var d := Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER)
		var boss := String(mo["kind"]) == "boss"
		if d < NEAR:
			near += 1
			if boss: boss_near = true
		if d <= siege_r:
			siege += 1
			if boss: boss_siege = true
	var crystal := sim.crystal_hp / maxf(1.0, sim.crystal_max)
	var keep := roundi(float(Arena.summon_cost()) * 0.5)
	# A body striking the crystal that no fielded hero can hurt (an immune body, a flyer nobody shoots), or
	# any striker once the crystal is under half: the starburst falls on it at once.
	for mo in sim.monsters:
		if float(mo["hp"]) <= 0.0 or Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) > siege_r: continue
		if crystal < 0.5 or not _hurtable(mo):
			_cast(sim, r, "blast", Vector2(mo["pos"]), 0)
			break
	# The ward when the boss strikes the crystal, or three bodies do while it is under half.
	if sim.shield <= 0.0 and (boss_siege or (siege >= 3 and crystal < 0.5)):
		_cast(sim, r, "ward", Vector2.INF, 0)
	# The frost when the crystal is threatened.
	if near >= 6 or boss_near or (siege >= 2 and crystal < 0.6):
		_cast(sim, r, "freeze", Vector2.INF, 0 if boss_near or crystal < 0.5 else keep)
	# The starburst on the best cluster, or on a boss, an elite or an unanswered flyer.
	var aim := _blast_aim(sim)
	if float(aim["score"]) >= 6.0 or (bool(aim["vip"]) and float(aim["score"]) >= 3.0):
		_cast(sim, r, "blast", aim["at"], 0 if bool(aim["urgent"]) else keep)

func _cast(sim: ArenaSim, r: Dictionary, id: String, at: Vector2, keep: int) -> bool:
	var state := sim.skill_state(id)
	if not bool(state["ready"]) or Arena.gold - int(state["cost"]) < keep:
		return false
	if not sim.cast_skill(id, at):
		return false
	r["gold_skill"] = int(r["gold_skill"]) + int(state["cost"])
	r[id] = int(r[id]) + 1
	return true

## Whether some fielded hero can hurt this monster (its element is not immune; a flyer needs a gun or a bow).
func _hurtable(mo: Dictionary) -> bool:
	var flying := bool(mo.get("fly", false))
	for hero in Arena.heroes:
		if flying and not Balance.anti_air(hero["unit"]): continue
		if Balance.elem_mult(String(hero["unit"].get("elem", "none")), String(mo["body"])) > 0.0: return true
	return false

## Where the starburst does most: every live monster is a candidate centre; a body counts 1, one no fielded
## hero can hurt 4 (an immune body, an unanswered flyer), an elite 4, the boss 5, and anything near the
## crystal half again as much.
func _blast_aim(sim: ArenaSim) -> Dictionary:
	var radius := sim.blast_radius()
	var alive: Array = sim.monsters.filter(func(mo: Dictionary) -> bool: return float(mo["hp"]) > 0.0)
	var best := {"at": Vector2.INF, "score": 0.0, "vip": false, "urgent": false}
	for centre in alive:
		var at: Vector2 = centre["pos"]
		var score := 0.0
		var vip := false
		var urgent := false
		for mo in alive:
			if at.distance_to(mo["pos"]) > radius + BattleSim.hit_radius(mo): continue
			var weight := 1.0
			var close := Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) < NEAR
			var special := false
			if not _hurtable(mo):
				weight += 3.0
				special = true
			if bool(mo.get("elite", false)):
				weight += 3.0
				special = true
			if String(mo["kind"]) == "boss":
				weight += 4.0
				special = true
			if special:
				vip = true
				if close: urgent = true
			score += weight * (1.5 if close else 1.0)
		if score > float(best["score"]):
			best = {"at": at, "score": score, "vip": vip, "urgent": urgent}
	return best

## A plain player's pick: raw attack and attack speed first, then crit, then whatever
## the first card is. Never reads the deeper tree.
const WANTS := ["fury_edge", "fury_blaze", "tempo_quick", "tempo_rush", "fury_wrath", "tempo_storm", "prec_aim", "prec_deadly",
	"tempo_repeat", "fury_heavy", "guard_hp", "arms_air", "fate_insight"]

func _pick_talent() -> bool:
	if Arena.talent_offer.is_empty():
		Arena.close_modal()
		return false
	for want in WANTS:
		if Arena.talent_offer.has(want):
			return Arena.pick_talent(want)
	return Arena.pick_talent(String(Arena.talent_offer[0]))


func _trace(sim: ArenaSim) -> void:
	var siege := 0
	var blocked := 0
	for mo in sim.monsters:
		if Vector2(mo["pos"]).distance_to(Balance.ARENA_CENTER) <= Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS + 1.0: siege += 1
		if bool(mo["blocked"]): blocked += 1
	var party := PackedStringArray()
	for hero in sim.heroes:
		var unit: Dictionary = hero["h"]["unit"]
		var reach := 0
		for mo in sim.monsters:
			if Vector2(hero["pos"]).distance_to(mo["pos"]) <= float(hero["range"]): reach += 1
		party.append("%s/%s/%s r%.0f t%d in%d dmg%.0f" % [unit["id"], unit.get("elem", "?"), unit.get("weapon", "?"), float(hero["range"]), int(hero["h"]["tier"]), reach, float(hero["dmg"])])
	print("  STAGE %d WAVE %d t=%3.0f 수정 %4.0f 골드 %3d 몹 %2d (공성 %d·막힘 %d) | %s" % [sim.stage, sim.wave_no, sim.elapsed, sim.crystal_hp, Arena.gold, sim.monsters.size(), siege, blocked, "  ".join(PackedStringArray(party))])
