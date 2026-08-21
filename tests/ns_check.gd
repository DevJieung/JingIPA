extends Node

## 표와 표가 서로 어긋나지 않는지 본다. 사람이 눈으로는 절대 못 잡는 것들이다.
##
##   godot --headless --path . res://tests/ns_check.tscn
##   ... -- --strict     그림이 하나라도 없으면 실패로 친다 (갈무리 전 검사)

var fail := 0


func _ready() -> void:
	var strict := "--strict" in OS.get_cmdline_user_args()
	_check_scripts()
	_check_roster()
	_check_balance()
	_check_geometry()
	_check_shop()
	_check_art(strict)
	if fail == 0:
		print("판정: 정상")
	else:
		printerr("!! 실패 %d건" % fail)
	get_tree().quit(0 if fail == 0 else 1)


func _bad(msg: String) -> void:
	printerr("!! " + msg)
	fail += 1


## 모든 .gd 가 파스되는가. ★ `--import` 는 이미 임포트된 스크립트를 다시 안 볼 때가 있어서
## "화면을 찍으려니 그제서야 파스 에러가 튀어나오는" 일이 실제로 있었다. 여기서 통째로 읽는다.
func _check_scripts() -> void:
	var n := 0
	for dir in ["res://core", "res://game", "res://tests"]:
		for f in _gd_files(dir):
			n += 1
			# ⚠ CACHE_MODE_IGNORE 로 읽으면 **지금 돌고 있는 이 스크립트 자신**을 다시
			#   읽다가 엔진이 죽는다(실제로 코어 덤프가 났다). 기본(REUSE)으로 읽는다 —
			#   새 프로세스라 대부분 아직 안 읽힌 상태이므로 파스 오류는 그대로 잡힌다.
			var r := ResourceLoader.load(f)
			if r == null:
				_bad("스크립트가 파스되지 않는다: %s" % f)
	print("  스크립트 %d개 모두 파스됨" % n)


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_gd_files(dir + "/" + sub))
	return out


func _check_roster() -> void:
	var ids := {}
	var kos := {}
	var per_tier := {}
	for u in Roster.UNITS:
		var id := String(u["id"])
		if ids.has(id):
			_bad("캐릭터 id 중복: %s — 그림 파일이 덮어써진다" % id)
		ids[id] = true
		var ko := String(u["ko"])
		if kos.has(ko):
			_bad("캐릭터 이름 중복: %s" % ko)
		kos[ko] = true
		if not Balance.PROFILE.has(String(u["profile"])):
			_bad("%s 의 profile 이 표에 없다: %s" % [id, u["profile"]])
		if not Balance.BULLET.has(String(u["bullet"])):
			_bad("%s 의 bullet 이 표에 없다: %s" % [id, u["bullet"]])
		var t := int(u["tier"])
		if t < 0 or t > 9:
			_bad("%s 의 등급이 0~9 밖이다: %d" % [id, t])
		per_tier[t] = int(per_tier.get(t, 0)) + 1
		if not Color.html_is_valid(String(u["color"])):
			_bad("%s 의 색이 이상하다: %s" % [id, u["color"]])
	for t in range(10):
		if int(per_tier.get(t, 0)) < 2:
			# 등급마다 최소 둘은 있어야 "같은 족보인데 다른 얼굴"이 성립한다.
			_bad("%s 등급의 캐릭터가 %d명뿐이다 (둘 이상)"
					% [Poker.HAND_KO[t], int(per_tier.get(t, 0))])

	for m in Roster.MONSTERS:
		var mid := String(m["id"])
		if ids.has(mid):
			_bad("몬스터 id 가 캐릭터와 겹친다: %s" % mid)
		ids[mid] = true
		if not Balance.MKIND.has(String(m["kind"])):
			_bad("%s 의 kind 가 표에 없다: %s" % [mid, m["kind"]])
	for st in ["early", "mid", "late", "boss"]:
		if Roster.monsters_of_stage(st).is_empty():
			_bad("%s 구간에 몬스터가 하나도 없다" % st)
	if Roster.TIER_KO.size() != 10:
		_bad("등급 이름이 10개가 아니다")


func _check_balance() -> void:
	for arr in [Balance.TIER_ATK, Balance.TIER_RATE, Balance.TIER_RNG]:
		if arr.size() != 10:
			_bad("등급별 표의 길이가 10이 아니다")
	# 등급이 오르면 초당 피해가 반드시 올라야 한다. 하나라도 뒤집히면 족보를 맞출 이유가 없다.
	var prev := 0.0
	for t in range(10):
		var dps: float = float(Balance.TIER_ATK[t]) * float(Balance.TIER_RATE[t])
		if dps <= prev:
			_bad("%s 등급의 초당 피해가 아래 등급보다 크지 않다 (%.1f -> %.1f)"
					% [Poker.HAND_KO[t], prev, dps])
		prev = dps
	# 사거리도 등급을 따라 올라야 한다.
	for t in range(1, 10):
		if float(Balance.TIER_RNG[t]) <= float(Balance.TIER_RNG[t - 1]):
			_bad("%s 등급의 사거리가 아래 등급보다 크지 않다" % Poker.HAND_KO[t])
	# 같은 등급 안의 결(프로필)은 초당 피해가 비슷해야 한다 — 하나만 정답이면 나머지는 꽝이다.
	var lo := 9.9
	var hi := 0.0
	for k in Balance.PROFILE:
		var p: Dictionary = Balance.PROFILE[k]
		var v: float = float(p["atk"]) * float(p["rate"])
		lo = min(lo, v)
		hi = max(hi, v)
	if hi / lo > 1.25:
		_bad("프로필끼리 초당 피해 차이가 너무 크다 (%.2f배)" % (hi / lo))


func _check_geometry() -> void:
	# ★ 가장 짧은 사거리가 몬스터의 안쪽 한계보다 짧으면, 가운데 선 영웅이 아무도 못 때린다.
	var min_rng := 99999.0
	var worst := ""
	for t in range(10):
		for k in Balance.PROFILE:
			var p: Dictionary = Balance.PROFILE[k]
			var v: float = float(Balance.TIER_RNG[t]) * float(p["rng"])
			if v < min_rng:
				min_rng = v
				worst = "%s %s" % [Poker.HAND_KO[t], p["ko"]]
	if min_rng < Balance.INNER_R:
		_bad("가장 짧은 사거리(%s, %.0f)가 몬스터 안쪽 한계(%.0f)보다 짧다 — 그 영웅은 아무도 못 때린다"
				% [worst, min_rng, Balance.INNER_R])
	else:
		print("  가장 짧은 사거리 %.0f (%s) ≥ 안쪽 한계 %.0f" % [min_rng, worst, Balance.INNER_R])
	if Balance.HERO_MAX_R >= Balance.INNER_R:
		_bad("영웅이 퍼지는 반지름(%.0f)이 몬스터 안쪽 한계(%.0f) 이상이다 — 겹친다"
				% [Balance.HERO_MAX_R, Balance.INNER_R])
	# 영웅이 마흔 명이어도 자리가 원 안에 들어와야 한다.
	for n in [1, 8, 20, 40, 60]:
		for i in range(n):
			var v := Balance.hero_slot(i, n)
			if v.length() > Balance.HERO_MAX_R + 0.5:
				_bad("영웅 %d명 중 %d번 자리가 원 밖이다 (%.0f)" % [n, i, v.length()])
				break
	# 투기장이 화면 안에 들어오는가 (오른쪽 정보판을 침범하지 않는가)
	var c := Balance.ARENA_CENTER
	var r := Balance.SPAWN_R
	if c.x + r > 830.0 or c.x - r < 0.0 or c.y - r < 68.0 or c.y + r > 800.0:
		_bad("투기장이 화면/정보판을 벗어난다 (중심 %s 반지름 %.0f)" % [c, r])


func _check_shop() -> void:
	var seen := {}
	for u in Balance.UPGRADES:
		var id := String(u["id"])
		if seen.has(id):
			_bad("업그레이드 id 중복: %s" % id)
		seen[id] = true
		if Balance.upgrade_cost(id, 0) <= 0:
			_bad("%s 의 값이 0 이다" % id)
	for p in Balance.PASSIVES:
		var id := String(p["id"])
		if seen.has(id):
			_bad("패시브 id 가 업그레이드와 겹친다: %s" % id)
		seen[id] = true
	# 리롤 값은 반드시 올라야 한다 — 안 오르면 "한 번만 공짜"라는 규칙이 무너진다.
	var prev := -1
	for n in range(5):
		var c := Balance.reroll_cost(n)
		if c <= prev:
			_bad("유료 리롤 값이 오르지 않는다: %d번째 %d" % [n, c])
		prev = c


func _check_art(strict: bool) -> void:
	var miss: Array[String] = []
	for u in Roster.UNITS:
		if not ResourceLoader.exists(String(u["art"])):
			miss.append(String(u["id"]))
	for m in Roster.MONSTERS:
		if not ResourceLoader.exists(String(m["art"])):
			miss.append(String(m["id"]))
	for k in Roster.ART:
		if not ResourceLoader.exists(String(Roster.ART[k])):
			miss.append(String(k))
	if miss.is_empty():
		print("  그림 %d장 모두 있음" % (Roster.UNITS.size() + Roster.MONSTERS.size() + Roster.ART.size()))
	elif strict:
		_bad("그림 %d장이 없다: %s" % [miss.size(), ", ".join(miss.slice(0, 12))])
	else:
		print("  (그림 %d장 아직 없음 — python3 tools/gen_art.py)" % miss.size())
