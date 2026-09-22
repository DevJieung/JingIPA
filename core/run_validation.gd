extends RefCounted
class_name RunValidation

## 파일에서 온 값은 형 변환 전에 검사한다. 복구 실패 시 현재 판은 바꾸지 않는다.
static func valid(d: Dictionary, version: int) -> bool:
	for key in ["v", "wave", "phase", "lives", "gold", "kills", "seed", "repairs", "rng"]:
		if not d.get(key, 0) is int:
			return false
	if d.get("v", 0) != version or d.get("wave", 0) < 1 or d["wave"] > Balance.LAST_WAVE:
		return false
	# Phase의 저장 번호는 기존 v7과 호환한다: DRAW, BATTLE, SHOP, SWAP.
	if not d.get("phase", -1) in [1, 2, 3, 4, 6]:
		return false
	if d.get("lives", 0) < (0 if d["phase"] == 4 else 1) or d["lives"] > Balance.MAX_LIVES:
		return false
	if d.get("gold", 0) < 0 or d.get("kills", 0) < 0 or d.get("repairs", 0) < 0:
		return false
	if not d.get("best_hand", -1) is int or d.get("best_hand", -1) < -1 or d.get("best_hand", -1) > 9:
		return false
	for key in ["heroes", "bench", "themes", "cards", "rerolled", "paid", "piles", "at", "passives", "offer"]:
		if not d.get(key) is Array:
			return false
	if not d.get("levels") is Dictionary or not d.get("last", {}) is Dictionary:
		return false
	for t in d["themes"]:
		if not t is int or t < 0 or t >= Roster.THEMES.size():
			return false
	var blocks := ceili(float(Balance.LAST_WAVE) / Balance.THEME_BLOCK)
	if not d["themes"].is_empty() and d["themes"].size() != blocks:
		return false
	var seen := {}
	var posts := {}
	if d.has("formation_v") and (not d["formation_v"] is int or d["formation_v"] != 2):
		return false
	var field_limit := Balance.HERO_SLOTS if d.has("formation_v") else Balance.POST_SLOTS
	if d["bench"].size() + maxi(0, d["heroes"].size() - Balance.HERO_SLOTS) > Balance.BENCH_SLOTS:
		return false
	for group in ["heroes", "bench"]:
		if d[group].size() > (field_limit if group == "heroes" else Balance.BENCH_SLOTS):
			return false
		for h in d[group]:
			if not h is Dictionary or not h.get("u") is String:
				return false
			if (group == "heroes" and seen.has(h["u"])) or Roster.unit_by_id(h["u"]).is_empty():
				return false
			seen[h["u"]] = true
			if h.has("post"):
				if not h["post"] is int or h["post"] < -1 or h["post"] >= Balance.POST_SLOTS:
					return false
				if group == "heroes" and h["post"] >= 0:
					if posts.has(h["post"]):
						return false
					posts[h["post"]] = true
			for key in ["t", "w", "n"]:
				if not h.get(key) is int:
					return false
			if h["t"] < 0 or h["t"] > 9 or h["n"] < 1 or h["n"] > 10000 or h["w"] < 1:
				return false
	if d["phase"] in [2, 3, 4] and d["heroes"].is_empty():
		return false
	for id in d["levels"]:
		if not id is String or not d["levels"][id] is int:
			return false
		var u := Balance.upgrade_by_id(id)
		var lv: int = d["levels"][id]
		# 공격속도·치명타 배율은 이전 버전에 상한이 없었다. 초과 단계가 있는
		# 정상 저장도 이어 갈 수 있게 허용하고, Run.restore()에서 새 상한으로 맞춘다.
		var capped: bool = int(u.get("cap", 0)) > 0 and id not in ["rate", "critx"]
		if u.is_empty() or lv < 0 or (capped and lv > int(u["cap"])):
			return false
	for group in ["passives", "offer"]:
		seen.clear()
		if d[group].size() > Balance.PASSIVE_SLOTS:
			return false
		for id in d[group]:
			if not id is String or seen.has(id) or Balance.passive_by_id(id).is_empty():
				return false
			seen[id] = true
	# 이전 저장의 패시브는 보유·활성 양쪽으로 그대로 이관한다.
	var owned: Variant = d.get("owned_passives", d["passives"])
	if not owned is Array or owned.size() > Balance.PASSIVES.size():
		return false
	seen.clear()
	for id in owned:
		if not id is String or seen.has(id) or Balance.passive_by_id(id).is_empty():
			return false
		seen[id] = true
	for id in d["passives"]:
		if not seen.has(id):
			return false
	var damage: Variant = d.get("hero_damage", {})
	if not damage is Dictionary:
		return false
	for id in damage:
		if not id is String or Roster.unit_by_id(id).is_empty() or not damage[id] is Dictionary:
			return false
		var entry: Dictionary = damage[id]
		if not entry.get("tier") is int or entry["tier"] < 0 or entry["tier"] > 9:
			return false
		var amount: Variant = entry.get("damage")
		if not (amount is float or amount is int) or not is_finite(float(amount)) or amount < 0:
			return false
	if not rewards_valid(d, version):
		return false
	if not piles_valid(d):
		return false
	var last: Dictionary = d.get("last", {})
	if not last.is_empty():
		if not last.get("unit") is String or Roster.unit_by_id(last["unit"]).is_empty():
			return false
		if not last.get("hand") is int or last["hand"] < 0 or last["hand"] > 9:
			return false
		if not cards_valid(last.get("cards"), 5) or not cards_valid(last.get("key")):
			return false
		for key in ["joker", "slot", "n"]:
			if not last.get(key, 0) is int:
				return false
		for key in ["revived", "reward_pending"]:
			if not last.get(key, false) is bool:
				return false
	return true


static func cards_valid(value: Variant, count: int = -1) -> bool:
	if not value is Array or (count >= 0 and value.size() != count):
		return false
	var seen := {}
	for c in value:
		if not c is int or c < 0 or c >= 52 or seen.has(c):
			return false
		seen[c] = true
	return true


static func piles_valid(d: Dictionary) -> bool:
	if int(d.get("rules_v", 0)) == 2:
		if not cards_valid(d.get("cards"), 5):
			return false
		for key in ["rerolled", "paid"]:
			if not d.get(key) is Array or d[key].size() != 5:
				return false
			for value in d[key]:
				if not value is int or value < 0:
					return false
		for i in range(5):
			if d["paid"][i] > d["rerolled"][i]:
				return false
		return true
	for key in ["cards", "rerolled", "paid", "piles", "at"]:
		if not d.get(key) is Array or d[key].size() != 5:
			return false
	if not cards_valid(d["cards"], 5):
		return false
	var seen := {}
	for i in range(5):
		var pile: Variant = d["piles"][i]
		if not cards_valid(pile, 11 if i < 2 else 10):
			return false
		for c in pile:
			if seen.has(c):
				return false
			seen[c] = true
		for key in ["at", "rerolled", "paid"]:
			if not d[key][i] is int or d[key][i] < 0:
				return false
		if d["at"][i] >= pile.size() or pile[d["at"][i]] != d["cards"][i]:
			return false
		if d["paid"][i] > d["rerolled"][i] or d["at"][i] != d["rerolled"][i] % pile.size():
			return false
	return seen.size() == 52

static func rewards_valid(d: Dictionary, version: int) -> bool:
	if not d.get("rules_v", 0) is int or not d.get("rules_v", 0) in [0, 2]:
		return false
	if not d.get("continue_used", false) is bool or not d.get("fusion_serial", 0) is int:
		return false
	var checkpoint: Variant = d.get("checkpoint", {})
	if not checkpoint is Dictionary:
		return false
	if not checkpoint.is_empty():
		if checkpoint.get("checkpoint", {}) != {} or checkpoint.get("phase", -1) != 2:
			return false
		if checkpoint.get("wave", -1) != d["wave"] or checkpoint.get("seed", -1) != d["seed"]:
			return false
		if not valid(checkpoint, version):
			return false
	var fusion: Variant = d.get("fusion", {})
	if not fusion is Dictionary:
		return false
	if fusion.is_empty():
		return true
	if not d["phase"] in [3, 6] or not fusion.get("id") is int or not fusion.get("failed") is bool:
		return false
	if not fusion.get("unit") is String or Roster.unit_by_id(fusion["unit"]).is_empty():
		return false
	if not fusion.get("tier") is int or fusion["tier"] < 0 or fusion["tier"] > 9:
		return false
	var before := d.duplicate(true)
	before["heroes"] = fusion.get("before_h")
	before["bench"] = fusion.get("before_b")
	before["fusion"] = {}
	before["checkpoint"] = {}
	if not before["heroes"] is Array or not before["bench"] is Array:
		return false
	if before["heroes"].size() + before["bench"].size() != d["heroes"].size() + d["bench"].size() + 4:
		return false
	return valid(before, version)
