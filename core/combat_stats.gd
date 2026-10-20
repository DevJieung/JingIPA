extends RefCounted
class_name CombatStats

## Shared, side-effect-free combat calculations for both run modes and UI previews.
## Authoritative values remain in Balance; this module never owns game state.


static func upgrade(id: String, level: int) -> float:
	match id:
		"atk":
			return Balance.atk_mult(level)
		"rate":
			return Balance.rate_mult(level)
		"crit":
			return Balance.crit_chance(level)
		"critx":
			return Balance.crit_mult(level)
		"gold":
			return Balance.gold_mult(level)
		"mire":
			return Balance.mire_mult(level)
		"reroll":
			return float(Balance.FREE_REROLL + level)
	return 1.0


static func passive_mult(passives: Array, key: String) -> float:
	var m := 1.0
	for id in passives:
		m *= float(Balance.passive_by_id(String(id)).get(key, 1.0))
	return m


static func passive_add(passives: Array, key: String) -> float:
	var t := 0.0
	for id in passives:
		t += float(Balance.passive_by_id(String(id)).get(key, 0.0))
	return t


static func passive_best(passives: Array, key: String) -> float:
	var best := 0.0
	for id in passives:
		best = max(best, float(Balance.passive_by_id(String(id)).get(key, 0.0)))
	return best


static func resonance(heroes: Array, passives: Array, elem: String) -> float:
	if not passives.has("resonance") or elem == "":
		return 1.0
	var n := 0
	for h in heroes:
		if String(h["unit"].get("elem", "none")) == elem:
			n += 1
			if n >= 2:
				return Balance.PASSIVE_RESONANCE
	return 1.0


## `mods` 는 별자리(Talents.effects)가 모은 지속 효과다 — 없으면 빈 사전(옛 모드 · 검사기).
## 곱하는 열쇠(atk · rate · speed · elem_<속성> · weapon_<무기> · melee_range)와
## 더하는 열쇠(crit · critx)를 여기서 같이 읽어, 전투와 영웅 정보가 같은 값을 본다.
static func hero(h: Dictionary, levels: Dictionary, passives: Array, heroes: Array, mods: Dictionary = {}) -> Dictionary:
	var u: Dictionary = h["unit"]
	var t: int = int(h["tier"])
	var prof: Dictionary = Balance.PROFILE[String(u.get("profile", "balance"))]
	var bul: Dictionary = Balance.BULLET.get(String(u.get("bullet", "shot")), Balance.BULLET["shot"])
	var el := String(u.get("elem", "none"))
	var weapon := String(u.get("weapon", ""))
	var role := String(u.get("role", "single"))
	var rol: Dictionary = Balance.ROLE.get(role, Balance.ROLE["single"])
	var atk: float = Balance.TIER_ATK[t] * float(prof["atk"]) * float(bul["dmg"]) \
			* float(rol["atk"]) \
			* Balance.elem_dmg(el) * resonance(heroes, passives, el) \
			* Balance.atk_mult(int(levels.get("atk", 0))) * passive_mult(passives, "atk")
	atk *= float(h.get("awakening_mult", 1.0))
	atk *= float(mods.get("atk", 1.0)) * float(mods.get("elem_" + el, 1.0)) * float(mods.get("weapon_" + weapon, 1.0))
	var rate: float = Balance.TIER_RATE[t] * float(prof["rate"]) \
			* Balance.rate_mult(int(levels.get("rate", 0))) * passive_mult(passives, "rate") * float(mods.get("rate", 1.0))
	var crit: float = Balance.crit_chance(int(levels.get("crit", 0))) + passive_add(passives, "crit") + float(mods.get("crit", 0.0))
	if role == "rider" and el == "none":
		crit += Balance.RIDER_CRIT
	var reach := Balance.attack_range(u, t)
	if Balance.is_melee(u):
		# 「검기」 — 근접 무기만 사거리가 는다. 탄 무기의 사거리는 없앤 개념 그대로 고정이다.
		reach = clampf(roundf(reach * float(mods.get("melee_range", 1.0))), Balance.RANGE_MIN, Balance.RANGE_MAX)
	return {
		"atk": atk, "rate": rate,
		"range": reach,
		"speed": Balance.hero_speed(u) * float(mods.get("speed", 1.0)),
		"shots": 1,
		"bullet": String(u.get("bullet", "shot")),
		"role": role,
		"elem": el,
		# 대공 — 공중 몬스터를 맞힐 수 있는 무기인가(Balance.ANTI_AIR_WEAPONS). 전투가 겨눌 때 본다.
		"air": Balance.anti_air(u),
		"crit": min(0.85, crit),
		"critx": Balance.crit_mult(int(levels.get("critx", 0))) + passive_add(passives, "critx") + float(mods.get("critx", 0.0)),
	}


static func dps(st: Dictionary) -> float:
	var mult: float = 1.0 + float(st["crit"]) * (float(st["critx"]) - 1.0)
	return float(st["atk"]) * float(st["rate"]) * mult * float(st.get("shots", 1))
