extends RefCounted
class_name Talents

## 별자리 — 레벨업 노드의 규칙(2026-10-17). 표는 Balance.TALENTS 가 들고 있고 여기는
## 「무엇이 열려 있나 · 셋을 어떻게 내놓나 · 고른 것들이 합쳐서 얼마가 되나」만 센다.
## 상태를 갖지 않는다. ArenaRun 이 고른 노드(id → 횟수)를 들고 다니며 이 함수들을 부른다.

## **더하는** 효과 열쇠. 나머지 숫자 열쇠는 전부 곱한다(1.0 이 기준).
## lv_* · grant_* · now_* 는 고르는 순간 ArenaRun 이 처리하므로 effects() 에 들지 않는다.
const ADD_KEYS := ["crit", "critx", "bounce", "pierce", "growth", "heal_stage",
	"uses_blast", "uses_freeze", "uses_ward", "air_slow"]
const META_KEYS := ["ko", "desc", "group", "tier", "req", "max", "icon", "tint"]
## 깊이별로 내놓을 확률의 무게. 뿌리가 가장 자주, 세 번째 깊이는 드물게 나온다.
const TIER_WEIGHT := [3.0, 2.0, 1.0]
## 한 번 쓰는 노드(now_*)는 그만큼 덜 내놓는다 — 지속 효과보다 값어치가 작기 때문이다.
const INSTANT_WEIGHT := 0.6


static func by_id(id: String) -> Dictionary:
	return Balance.talent_by_id(id)


static func group_of(id: String) -> Dictionary:
	return Balance.TALENT_GROUPS.get(String(by_id(id).get("group", "")), {})


## 고르는 순간 처리되는 열쇠인가(능력치 단계 · 패시브 · 즉시 효과).
static func is_pick_key(key: String) -> bool:
	return key.begins_with("lv_") or key.begins_with("grant_") or key.begins_with("now_")


static func is_instant(node: Dictionary) -> bool:
	for key in node:
		if String(key).begins_with("now_"):
			return true
	return false


## 노드의 효과 열쇠만(표 열은 뺀다).
static func effect_keys(node: Dictionary) -> Array:
	var out: Array = []
	for key in node:
		if String(key) == "id" or String(key) in META_KEYS:
			continue
		out.append(String(key))
	return out


## 그 노드의 선행 조건이 맞는가. `req` 는 쉼표로 「전부」, `|` 로 「그중 하나」를 적는다.
static func requirements_met(node: Dictionary, taken: Dictionary) -> bool:
	var req := String(node.get("req", "")).strip_edges()
	if req.is_empty():
		return true
	for clause in req.split(","):
		var any := false
		for option in String(clause).split("|"):
			if int(taken.get(String(option).strip_edges(), 0)) > 0:
				any = true
				break
		if not any:
			return false
	return true


## 지금 고를 수 있는 노드들. 선행 조건이 맞고, 횟수가 남았고, 주는 패시브를 아직 안 가졌고,
## 올리는 능력치가 상한에 닿지 않은 것만.
static func available(taken: Dictionary, owned_passives: Array, levels: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for node in Balance.TALENTS:
		var id := String(node["id"])
		if int(taken.get(id, 0)) >= int(node.get("max", 1)):
			continue
		if not requirements_met(node, taken):
			continue
		var fits := true
		for raw in effect_keys(node):
			var key := String(raw)
			if key.begins_with("grant_") and owned_passives.has(key.trim_prefix("grant_")):
				fits = false
			elif key.begins_with("lv_"):
				var up: String = key.trim_prefix("lv_")
				var cap := int(Balance.upgrade_by_id(up).get("cap", 0))
				if Balance.upgrade_by_id(up).is_empty() or (cap > 0 and int(levels.get(up, 0)) + int(node[key]) > cap):
					fits = false
		if fits:
			out.append(id)
	return out


static func weight_of(node: Dictionary) -> float:
	var tier := clampi(int(node.get("tier", 1)), 1, TIER_WEIGHT.size())
	var w: float = TIER_WEIGHT[tier - 1]
	if is_instant(node):
		w *= INSTANT_WEIGHT
	return w


## 레벨업 때 내놓을 노드 `count` 개. 서로 다른 별자리를 우선하고(셋이 한 별자리에서 나오지
## 않게), 깊은 노드는 덜 나온다. `rng` 는 판의 난수라 저장·복구 뒤에도 같은 셋이 나온다.
static func roll_offer(rng: RandomNumberGenerator, taken: Dictionary, owned_passives: Array,
		levels: Dictionary, count: int = Balance.ARENA_TALENT_CHOICES) -> Array[String]:
	var pool := available(taken, owned_passives, levels)
	var out: Array[String] = []
	var groups_used := {}
	while out.size() < count and not pool.is_empty():
		# 아직 안 나온 별자리의 노드만 후보로 삼되, 그런 것이 없으면 전부에서 고른다.
		var candidates: Array[String] = []
		for id in pool:
			if not groups_used.has(String(by_id(id).get("group", ""))):
				candidates.append(id)
		if candidates.is_empty():
			candidates = pool.duplicate()
		var total := 0.0
		for id in candidates:
			total += weight_of(by_id(id))
		var pick := rng.randf() * total
		var chosen := candidates[-1]
		for id in candidates:
			pick -= weight_of(by_id(id))
			if pick <= 0.0:
				chosen = id
				break
		out.append(chosen)
		groups_used[String(by_id(chosen).get("group", ""))] = true
		pool.erase(chosen)
	return out


## 고른 노드들의 지속 효과를 하나로 모은다 — 곱하는 열쇠는 곱, 더하는 열쇠는 합.
## 되풀이 노드는 횟수만큼 겹친다. 고르는 순간의 열쇠(lv_·grant_·now_)는 들지 않는다.
static func effects(taken: Dictionary) -> Dictionary:
	var out := {}
	for id in taken:
		var node := by_id(String(id))
		var times := int(taken[id])
		if node.is_empty() or times <= 0:
			continue
		for raw in effect_keys(node):
			var key := String(raw)
			if is_pick_key(key):
				continue
			var value := float(node[key])
			if key in ADD_KEYS:
				out[key] = float(out.get(key, 0.0)) + value * float(times)
			else:
				out[key] = float(out.get(key, 1.0)) * pow(value, float(times))
	return out


## 모은 효과에서 곱하는 열쇠 하나를 읽는다(없으면 1.0).
static func mult(mods: Dictionary, key: String) -> float:
	return float(mods.get(key, 1.0))


## 모은 효과에서 더하는 열쇠 하나를 읽는다(없으면 0.0).
static func add(mods: Dictionary, key: String) -> float:
	return float(mods.get(key, 0.0))


## --- 별자리 지도용 읽기 도우미 (2026-10-19, F2) ---
## 지도는 규칙을 다시 세지 않고 이 함수들만 읽는다. 상태를 갖지 않는다.

## 선행 조건을 「묶음(전부) 안의 선택지(그중 하나)」 목록으로 푼다. 예: "a|b,c" → [["a","b"],["c"]].
static func clauses(node: Dictionary) -> Array:
	var out: Array = []
	for clause in String(node.get("req", "")).split(",", false):
		var options: Array = []
		for option in String(clause).split("|", false):
			var id := String(option).strip_edges()
			if not id.is_empty():
				options.append(id)
		if not options.is_empty():
			out.append(options)
	return out


## 그 노드를 선행 조건으로 적은 노드들(표 순서).
static func children(id: String) -> Array[String]:
	var out: Array[String] = []
	for node in Balance.TALENTS:
		for options in clauses(node):
			if id in options:
				out.append(String(node["id"]))
				break
	return out


static var _depth_cache: Dictionary = {}

## 선행 사슬의 가장 긴 길이(뿌리 = 0). 표의 tier 와 달리 같은 줄의 형제끼리 잇는 선이 생기지 않는다.
static func graph_depth(id: String) -> int:
	if _depth_cache.has(id):
		return int(_depth_cache[id])
	_depth_cache[id] = 0  # 순환이 있어도 멈추게 먼저 적어 둔다(lint 가 따로 잡는다).
	var depth := 0
	for options in clauses(by_id(id)):
		for option in options:
			depth = maxi(depth, graph_depth(String(option)) + 1)
	_depth_cache[id] = depth
	return depth


## 지도에 칠할 노드 상태. "full" 횟수를 다 채움 · "joined" 이었지만 더 고를 수 있음 ·
## "open" 지금 고를 수 있음 · "closed" 선행은 맞지만 가진 패시브나 능력치 상한 때문에 막힘 ·
## "locked" 선행 조건이 아직 안 맞음. 판단은 available() 그대로다.
static func state(id: String, taken: Dictionary, owned_passives: Array, levels: Dictionary) -> String:
	var node := by_id(id)
	if node.is_empty():
		return "locked"
	var count := int(taken.get(id, 0))
	if count >= int(node.get("max", 1)):
		return "full"
	if not requirements_met(node, taken):
		return "joined" if count > 0 else "locked"
	if id in available(taken, owned_passives, levels):
		return "joined" if count > 0 else "open"
	return "closed"


## 표가 맞게 적혔는가 — 검사기(tests/ns_check)가 부른다. 어긋난 줄의 설명을 돌려준다.
static func lint() -> Array[String]:
	var bad: Array[String] = []
	var ids := {}
	for node in Balance.TALENTS:
		var id := String(node.get("id", ""))
		if id.is_empty() or ids.has(id):
			bad.append("talent id empty or duplicated: " + id)
		ids[id] = true
	for node in Balance.TALENTS:
		var id := String(node["id"])
		if not Balance.TALENT_GROUPS.has(String(node.get("group", ""))):
			bad.append("%s: unknown constellation %s" % [id, String(node.get("group", ""))])
		if int(node.get("max", 1)) < 1 or int(node.get("tier", 1)) < 1 or int(node.get("tier", 1)) > TIER_WEIGHT.size():
			bad.append("%s: max or tier out of range" % id)
		for clause in String(node.get("req", "")).split(",", false):
			for option in String(clause).split("|", false):
				if not ids.has(String(option).strip_edges()):
					bad.append("%s: unknown prerequisite %s" % [id, String(option)])
		var keys := effect_keys(node)
		if keys.is_empty():
			bad.append("%s: no effect at all" % id)
		for raw in keys:
			var key := String(raw)
			if key.begins_with("grant_") and Balance.passive_by_id(key.trim_prefix("grant_")).is_empty():
				bad.append("%s: unknown passive %s" % [id, key])
			elif key.begins_with("lv_") and Balance.upgrade_by_id(key.trim_prefix("lv_")).is_empty():
				bad.append("%s: unknown upgrade %s" % [id, key])
			elif not (node[key] is int or node[key] is float):
				bad.append("%s: %s is not a number" % [id, key])
	for group in Balance.TALENT_GROUPS:
		if not Balance.TALENT_GROUP_ORDER.has(group):
			bad.append("TALENT_GROUP_ORDER lacks %s" % String(group))
	return bad
