extends RefCounted
class_name ArenaValidation

## Reject malformed saves before touching a running battlefield.
## Version of the arena run snapshot (ArenaRun.snapshot writes it). 3 = stage chain,
## 4 = growth by experience and constellation nodes instead of the gold shop (2026-10-17),
## 5 = the stage ladder fought in waves with preparation phases (2026-10-19). Later keys of the
## 2026-10-19 plan join v5 as optional keys; the version is raised once.
const SAVE_V := 5
## Fixed caps for numbers whose real limit is a tuning value (2026-10-19): a value moved in the DB (a shorter
## preparation, fewer revivals, fewer cards …) must not turn a run in progress into a rejected save. Restore
## brings such a number back inside the current limit (ArenaRun.restore, ArenaSim.restore_arena).
const STAGE_CAP := 1000
const COUNT_CAP := 1000
const OFFER_CAP := 12
const PREP_CAP := 600.0
const CRYSTAL_CAP := 10000000.0
static func number(value: Variant, low: float = 0.0, high: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func point(value: Variant) -> bool:
	return vector(value) and ArenaGeometry.contains(value, -2)

static func vector(value: Variant) -> bool:
	return value is Vector2 and is_finite(value.x) and is_finite(value.y)

static func numbers(data: Dictionary, keys: Array, low: float = 0.0) -> bool:
	for key in keys:
		if not number(data.get(key), low):
			return false
	return true

static func source(value: Variant, count: int) -> bool:
	return value is int and value >= -1 and value < count

## Runs saved under older rules cannot be continued: the single battlefield of v1-2, the gold shop
## of v3, and the ten-stage chain without waves of v4 (2026-10-19) have no counterpart in the
## current rules. Save keeps the lifetime records and drops only such a run (Save._load_checked).
## A v5 run without a jewel box (saved for a few hours of 2026-10-19 with the star rite) goes the same way.
static func outdated(data: Dictionary) -> bool:
	if data.get("mode") != "arena" or not data.get("v") is int:
		return false
	return int(data["v"]) < SAVE_V or (int(data["v"]) == SAVE_V and not data.has("box"))

## Monster positions are checked against the saved battlefield's roads, so the layout
## is switched for the check and put back afterwards.
static func valid(data: Dictionary) -> bool:
	var layout := ArenaGeometry.layout()
	var result := _valid(data)
	ArenaGeometry.use_layout(layout)
	return result

static func _valid(data: Dictionary) -> bool:
	if data.get("mode") != "arena" or data.get("v") != SAVE_V:
		return false
	for key in ["seed", "rng", "phase", "theme_index", "selected", "gold", "lives", "kills", "best_tier", "summon_count", "stage", "wave"]:
		if not data.get(key) is int:
			return false
	# A ladder stage. Its battlefield is any valid theme: tools may choose one (choose_theme), so it is
	# not held to the ladder's order.
	if data["stage"] < 1 or data["stage"] > STAGE_CAP or data["wave"] != data["stage"]:
		return false
	if data["theme_index"] < 0 or data["theme_index"] >= Roster.THEMES.size():
		return false
	if data["phase"] not in [1, 2, 3, 6] or data.get("modal") not in ["stage", "box", "talent", "bench", ""]:
		return false
	if data["modal"] != "box" and data["phase"] != {"stage":1, "talent":3, "bench":6, "":2}[data["modal"]]:
		return false
	if data["gold"] < 0 or data["kills"] < 0 or data["summon_count"] < 0 or data["lives"] < 1 or data["lives"] > COUNT_CAP:
		return false
	if data["best_tier"] < -1 or data["best_tier"] > Balance.TIER_MAX:
		return false
	ArenaGeometry.use_layout(ArenaGeometry.layout_for_theme(data["theme_index"]))
	var ids := {}
	for group in ["heroes", "bench"]:
		if not data.get(group) is Array or data[group].size() > Roster.UNITS.size():
			return false
		for hero in data[group]:
			if not hero is Dictionary or not hero.get("u") is String or Roster.unit_by_id(hero["u"]).is_empty() or ids.has(hero["u"]):
				return false
			ids[hero["u"]] = true
			if not hero.get("t") is int or not hero.get("points") is int or not point(hero.get("p")):
				return false
			var tier := int(hero["t"])
			if tier < 0 or tier > Balance.TIER_MAX or hero["points"] < 0:
				return false
			if tier == Balance.TIER_MAX and hero["points"] != 0:
				return false
	if data["selected"] < 0 or data["selected"] >= maxi(1, data["heroes"].size()):
		return false
	if not data.get("hero_damage") is Dictionary:
		return false
	for id in data["hero_damage"]:
		var entry: Variant = data["hero_damage"][id]
		if not ids.has(id) or not entry is Dictionary or not number(entry.get("damage")) or not number(entry.get("tier"), 0, Balance.TIER_MAX):
			return false
	if not data.get("levels") is Dictionary:
		return false
	for id in data["levels"]:
		var upgrade := Balance.upgrade_by_id(id)
		if upgrade.is_empty() or not data["levels"][id] is int or data["levels"][id] < 0:
			return false
		if data["levels"][id] > COUNT_CAP:
			return false
	for key in ["passives", "owned_passives"]:
		if not data.get(key) is Array:
			return false
		var seen := {}
		for id in data[key]:
			if not id is String or Balance.passive_by_id(id).is_empty() or seen.has(id):
				return false
			seen[id] = true
	# Passives come from constellation nodes, every one of them active: no slot cap.
	if data["passives"].size() > Balance.PASSIVES.size():
		return false
	for id in data["passives"]:
		if not data["owned_passives"].has(id):
			return false
	# Experience, level and the constellation nodes taken (id -> times), plus the pending offer.
	if not number(data.get("xp")) or not data.get("level") is int or data["level"] < 0:
		return false
	if not data.get("pending_levels") is int or data["pending_levels"] < 0 or data["pending_levels"] > data["level"]:
		return false
	if not data.get("talents") is Dictionary or not data.get("talent_offer") is Array:
		return false
	var picks := 0
	for id in data["talents"]:
		var node := Balance.talent_by_id(String(id))
		if node.is_empty() or not data["talents"][id] is int or data["talents"][id] < 1 or data["talents"][id] > COUNT_CAP:
			return false
		picks += int(data["talents"][id])
	# Levels without a node are still pending or were paid out in gold; never more picks than levels.
	if picks > data["level"]:
		return false
	if data["talent_offer"].size() > OFFER_CAP:
		return false
	var offered := {}
	for id in data["talent_offer"]:
		if not id is String or Balance.talent_by_id(id).is_empty() or offered.has(id):
			return false
		offered[id] = true
	# A pending offer is only shown by the talent modal, and only while a level is unspent.
	if not data["talent_offer"].is_empty() and (data["modal"] != "talent" or data["pending_levels"] < 1):
		return false
	# The jewel box (2026-10-19): open while choosing (phase 1) and while its pick is shown (phase 6).
	if not data.get("summon_result") is Dictionary:
		return false
	var maxed := {}
	for group in ["heroes", "bench"]:
		for hero in data[group]:
			if int(hero["t"]) >= Balance.TIER_MAX: maxed[hero["u"]] = true
	var choosing: bool = data["modal"] == "box" and data["phase"] == 1
	if not JewelBox.valid(data.get("box"), maxed, choosing):
		return false
	if data["modal"] == "box":
		if data["phase"] not in [1, 6] or data["box"]["cards"].is_empty():
			return false
		if data["phase"] == 6 and data["summon_result"].is_empty():
			return false
	var result: Dictionary = data["summon_result"]
	if not result.is_empty():
		if result.get("kind") not in ["new", "growth"] or not result.get("unit") is Dictionary or not result["unit"].get("id") is String:
			return false
		if not ids.has(result["unit"]["id"]):
			return false
		for key in ["tier", "after_tier", "added_points", "growth_points", "slot", "stars"]:
			if not result.get(key) is int or result[key] < 0:
				return false
		if result["tier"] > Balance.TIER_MAX or result["after_tier"] > Balance.TIER_MAX or result["stars"] > JewelBox.MAX_STARS or not result.get("maxed") is bool:
			return false
		# What the box adds to a pick: its grade, the card, the guarantee and the two fortune nodes.
		for key in ["box", "card", "growth_needed"]:
			if result.has(key) and (not result[key] is int or result[key] < 0):
				return false
		for key in ["guaranteed", "bumped", "joker"]:
			if result.has(key) and not result[key] is bool:
				return false
	# Hellbound (2026-10-19): an optional flag and the squad taken in — known ids, each once, at most
	# ARENA_HELL_SQUAD, never empty in Hellbound. Saves made before it have neither.
	if data.has("hell") and not data["hell"] is bool:
		return false
	if data.has("squad"):
		if not data["squad"] is Array or data["squad"].size() > Roster.UNITS.size():
			return false
		var taken := {}
		for id in data["squad"]:
			if not id is String or Roster.unit_by_id(id).is_empty() or taken.has(id):
				return false
			taken[id] = true
	if data.get("hell", false) == true and (not data.get("squad") is Array or data["squad"].is_empty()):
		return false
	# The last revival's hero (the DLC's revival tickets): a hero of this run at a valid grade. Its place may
	# have changed since (the player moves heroes), so only its shape is held.
	if data.has("revive_gift"):
		if not data["revive_gift"] is Dictionary:
			return false
		var gift: Dictionary = data["revive_gift"]
		if not gift.is_empty():
			if not gift.get("u") is String or not ids.has(gift["u"]) or not gift.get("t") is int or gift["t"] < 0 or gift["t"] > Balance.TIER_MAX:
				return false
			if gift.get("where") not in ["field", "bench"] or not gift.get("slot") is int or gift["slot"] < 0:
				return false
	if not data.get("sim") is Dictionary:
		return false
	# The battlefield card comes before the stage's first box: nobody has been summoned yet.
	if data["summon_count"] == 0 and not (data["heroes"].is_empty() and data["bench"].is_empty()):
		return false
	if data["modal"] == "" and data["heroes"].is_empty():
		return false
	var sim: Dictionary = data["sim"]
	if not sim.get("road_revision") is int or sim["road_revision"] < 1:
		return false
	if sim.get("stage") != data["stage"]:
		return false
	# Revivals used: a count, or the flag of saves made while the blessing revived once.
	if sim.has("revives"):
		if not sim["revives"] is int or sim["revives"] < 0 or sim["revives"] > COUNT_CAP:
			return false
	elif not sim.get("revived") is bool:
		return false
	var current_roads: bool = sim["road_revision"] == ArenaGeometry.ROAD_REVISION and sim.get("layout") == ArenaGeometry.layout()
	for key in ["clear_t", "invuln_t"]:
		if not number(sim.get(key), 0.0, 60.0):
			return false
	for key in ["elapsed", "crystal_hp", "shield", "shield_t", "curse_t", "surge", "surge_t"]:
		if not number(sim.get(key)):
			return false
	# The spawn countdown: saves made before the LA4 fix may hold it below zero once a wave's list was out.
	if not number(sim.get("spawn_t"), -1000000.0):
		return false
	if not numbers(sim, ["accumulator", "kills", "gold", "nav_version"]):
		return false
	if not sim.get("boss_spawned") is bool or not sim.get("boss_alive") is bool or not sim.get("rng") is int or not sim.get("serial") is int:
		return false
	if sim.has("crystal_max") and not number(sim["crystal_max"], 1.0, CRYSTAL_CAP):
		return false
	var crystal_cap: float = float(sim.get("crystal_max", CRYSTAL_CAP))
	if sim["crystal_hp"] <= 0.0 or sim["crystal_hp"] > crystal_cap + 0.001 or not sim.get("cooldowns") is Dictionary:
		return false
	for id in ["blast", "freeze", "ward"]:
		if not number(sim["cooldowns"].get(id)):
			return false
	if not sim.get("uses") is Dictionary: return false
	for id in ["blast", "freeze", "ward"]:
		if not sim["uses"].get(id) is int or sim["uses"][id] < 0: return false
	if not sim.get("boss_warned") is bool: return false
	if not sim.get("boss_lane") is int or sim["boss_lane"] < -1 or sim["boss_lane"] >= ArenaGeometry.route_count(): return false
	# The wave and its place in it (2026-10-19). The counts are held to fixed caps only: restore fits the wave
	# to the stage's last wave (endless waves have none) and the spawned count to the wave's list.
	if not sim.get("wave_no") is int or sim["wave_no"] < 1 or sim["wave_no"] > COUNT_CAP:
		return false
	if not sim.get("in_prep") is bool or not number(sim.get("wave_t")):
		return false
	if not number(sim.get("prep_t"), 0.0, PREP_CAP):
		return false
	if not sim.get("wave_spawned") is int or sim["wave_spawned"] < 0 or sim["wave_spawned"] > COUNT_CAP:
		return false
	# Nothing of a wave spawns before its preparation ends.
	if sim["in_prep"] and sim["wave_spawned"] != 0:
		return false
	for key in ["monsters", "bullets", "zones", "pending", "heroes"]:
		if not sim.get(key) is Array or sim[key].size() > 10000:
			return false
		for entry in sim[key]:
			if not entry is Dictionary:
				return false
	if sim["heroes"].size() != data["heroes"].size():
		return false
	var hero_count: int = sim["heroes"].size()
	for hero in sim["heroes"]:
		if not numbers(hero, ["cool", "acc", "face", "dmg", "kills", "dw", "dn", "dr"], -1000000.0):
			return false
		for key in ["fx_t", "fx_w"]:
			if hero.has(key) and not number(hero[key]):
				return false
		if hero.has("fx_d") and not vector(hero["fx_d"]):
			return false
	for mo in sim["monsters"]:
		if not point(mo.get("pos")) or not mo.get("m") is Dictionary or not mo.get("path") is PackedVector2Array:
			return false
		if current_roads and not ArenaGeometry.on_road(mo["pos"]): return false
		for key in ["hp", "max", "spd", "motion_t", "slow", "slow_t", "stun_t", "stun_cd", "push", "push_left", "push_t", "flash", "burn", "burn_t", "burn_em", "siege_t", "s", "off", "h"]:
			if not number(mo.get(key), -1000000.0):
				return false
		if mo.get("kind") not in Balance.MKIND or mo.get("body") not in Balance.MBODY or not vector(mo.get("vel")):
			return false
		if mo.has("fly") and not mo["fly"] is bool:
			return false
		# The elite mark and the seconds stood blocked (the deadlock break, ARENA_BLOCK_BREAK).
		if mo.has("elite") and not mo["elite"] is bool:
			return false
		if mo.has("block_t") and not number(mo["block_t"]):
			return false
		if not mo["m"].get("id") is String or Roster.monster_by_id(mo["m"]["id"]).is_empty():
			return false
		if not numbers(mo, ["cast_t", "gold", "crush"]) or not source(mo.get("burn_src"), hero_count):
			return false
		if not mo.get("spawn_id") is int or not mo.get("nav_v") is int or not mo.get("blocked") is bool:
			return false
		for at in mo["path"]:
			if not point(at) or (current_roads and not ArenaGeometry.on_road(at)):
				return false
	for bullet in sim["bullets"]:
		if not vector(bullet.get("p")) or not vector(bullet.get("v")) or not bullet.get("c") is Color or not bullet.get("crit") is bool:
			return false
		if not numbers(bullet, ["dmg", "spd", "life", "pierce", "bounce", "decay", "hop"]) or not source(bullet.get("src"), hero_count):
			return false
		if bullet.get("kind") not in Balance.BULLET or not bullet.get("el") is String or not bullet.get("tgt") is int or not bullet.get("hit") is Array:
			return false
		for hit in bullet["hit"]:
			if not hit is int or hit < 0 or hit >= sim["monsters"].size():
				return false
	for zone in sim["zones"]:
		if not vector(zone.get("at")) or not zone.get("c") is Color or not zone.get("crit") is bool or not zone.get("el") is String:
			return false
		if not numbers(zone, ["r", "dmg", "t", "n", "max", "delay", "tick"]) or not source(zone.get("src"), hero_count):
			return false
	for pending in sim["pending"]:
		if not pending.get("crit") is bool or pending.get("kind") not in Balance.BULLET or not source(pending.get("hi"), hero_count) or pending["hi"] < 0:
			return false
		if not numbers(pending, ["t", "dmg", "shots"]):
			return false
	return true
