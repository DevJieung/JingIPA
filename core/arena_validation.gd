extends RefCounted
class_name ArenaValidation

## Reject malformed saves before touching a running battlefield.
static func number(value: Variant, low: float = 0.0, high: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func point(value: Variant, legacy: bool = false) -> bool:
	return vector(value) and (ArenaGeometry.LEGACY_RECT.grow(2).has_point(value) if legacy else ArenaGeometry.contains(value, -2))

static func vector(value: Variant) -> bool:
	return value is Vector2 and is_finite(value.x) and is_finite(value.y)

static func numbers(data: Dictionary, keys: Array, low: float = 0.0) -> bool:
	for key in keys:
		if not number(data.get(key), low):
			return false
	return true

static func source(value: Variant, count: int) -> bool:
	return value is int and value >= -1 and value < count

static func valid(data: Dictionary) -> bool:
	if data.get("mode") != "arena" or data.get("v") not in [1, 2] or data.get("wave") != 1:
		return false
	var legacy: bool = data["v"] == 1
	for key in ["seed", "rng", "phase", "theme_index", "selected", "gold", "lives", "kills", "best_tier", "summon_count"]:
		if not data.get(key) is int:
			return false
	if data["phase"] not in [1, 2, 3, 6] or data.get("modal") not in ["theme", "rite", "shop", "bench", ""]:
		return false
	if data["modal"] != "rite" and data["phase"] != {"theme":1, "shop":3, "bench":6, "":2}[data["modal"]]:
		return false
	if data["gold"] < 0 or data["kills"] < 0 or data["summon_count"] < 0 or data["lives"] < 1 or data["lives"] > Balance.MAX_LIVES:
		return false
	if data["best_tier"] < -1 or data["best_tier"] > Balance.TIER_MAX:
		return false
	if data["theme_index"] < -1 or data["theme_index"] >= Roster.THEMES.size():
		return false
	if (data["modal"] == "theme") != (data["theme_index"] == -1):
		return false
	var ids := {}
	for group in ["heroes", "bench"]:
		if not data.get(group) is Array or data[group].size() > (Balance.ARENA_HERO_LIMIT if group == "heroes" else Roster.UNITS.size()):
			return false
		for hero in data[group]:
			if not hero is Dictionary or not hero.get("u") is String or Roster.unit_by_id(hero["u"]).is_empty() or ids.has(hero["u"]):
				return false
			ids[hero["u"]] = true
			if not hero.get("t") is int or not hero.get("points") is int or not point(hero.get("p"), legacy):
				return false
			var tier := int(hero["t"])
			if tier < 0 or tier > Balance.TIER_MAX or hero["points"] < 0:
				return false
			if tier == Balance.TIER_MAX and hero["points"] != 0:
				return false
			if tier < Balance.TIER_MAX and hero["points"] >= Balance.ARENA_GROWTH_BASE + tier * Balance.ARENA_GROWTH_STEP:
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
		if int(upgrade["cap"]) > 0 and data["levels"][id] > int(upgrade["cap"]):
			return false
	for key in ["passives", "owned_passives", "offer"]:
		if not data.get(key) is Array:
			return false
		var seen := {}
		for id in data[key]:
			if not id is String or Balance.passive_by_id(id).is_empty() or seen.has(id):
				return false
			seen[id] = true
	if data["passives"].size() > Balance.PASSIVE_SLOTS:
		return false
	for id in data["passives"]:
		if not data["owned_passives"].has(id):
			return false
	if not data.get("rite") is Dictionary or not data["rite"].get("orbit") is Array or not data.get("summon_result") is Dictionary:
		return false
	for key in ["spins", "paid"]:
		if not data["rite"].get(key) is int or data["rite"][key] < 0:
			return false
	if data["modal"] == "rite":
		if data["phase"] not in [1, 6] or not Rite.valid(data["rite"]["orbit"]):
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
		if result["tier"] > Balance.TIER_MAX or result["after_tier"] > Balance.TIER_MAX or not result.get("maxed") is bool:
			return false
	if not data.get("sim") is Dictionary:
		return false
	if data["modal"] == "theme":
		return data["heroes"].is_empty() and data["bench"].is_empty() and data["sim"].is_empty()
	var sim: Dictionary = data["sim"]
	if sim.has("road_revision") and (not sim["road_revision"] is int or sim["road_revision"] < 1):
		return false
	var current_roads := not legacy and int(sim.get("road_revision", 1)) == ArenaGeometry.ROAD_REVISION
	for key in ["elapsed", "crystal_hp", "shield", "shield_t", "spawn_t", "curse_t", "surge", "surge_t"]:
		if not number(sim.get(key)):
			return false
	if not numbers(sim, ["accumulator", "kills", "gold", "nav_version"]):
		return false
	if not sim.get("boss_spawned") is bool or not sim.get("boss_alive") is bool or not sim.get("rng") is int or not sim.get("serial") is int:
		return false
	if sim["crystal_hp"] <= 0.0 or sim["crystal_hp"] > Balance.ARENA_CRYSTAL_HP or not sim.get("cooldowns") is Dictionary:
		return false
	for id in ["blast", "freeze", "ward"]:
		if not number(sim["cooldowns"].get(id)):
			return false
	for key in ["monsters", "bullets", "zones", "pending", "heroes"]:
		if not sim.get(key) is Array or sim[key].size() > 10000:
			return false
		for entry in sim[key]:
			if not entry is Dictionary:
				return false
	if sim["heroes"].size() != data["heroes"].size() or sim["monsters"].size() > Balance.ARENA_POPULATION_MAX + 1:
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
		if not point(mo.get("pos"), legacy) or not mo.get("m") is Dictionary or not mo.get("path") is PackedVector2Array:
			return false
		if current_roads and not ArenaGeometry.on_road(mo["pos"]): return false
		for key in ["hp", "max", "spd", "motion_t", "slow", "slow_t", "stun_t", "stun_cd", "push", "push_left", "push_t", "flash", "burn", "burn_t", "burn_em", "siege_t", "s", "off", "h"]:
			if not number(mo.get(key), -1000000.0):
				return false
		if mo.get("kind") not in Balance.MKIND or mo.get("body") not in Balance.MBODY or not vector(mo.get("vel")):
			return false
		if not mo["m"].get("id") is String or Roster.monster_by_id(mo["m"]["id"]).is_empty():
			return false
		if not numbers(mo, ["cast_t", "gold", "crush"]) or not source(mo.get("burn_src"), hero_count):
			return false
		if not mo.get("spawn_id") is int or not mo.get("nav_v") is int or not mo.get("blocked") is bool:
			return false
		for at in mo["path"]:
			if not point(at, legacy) or (current_roads and not ArenaGeometry.on_road(at)):
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
