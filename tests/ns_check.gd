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
	_check_roster_slots()
	_check_battle()
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
	var bad := 0
	for dir in ["res://core", "res://game", "res://tests"]:
		for f in _gd_files(dir):
			n += 1
			# ⚠ CACHE_MODE_IGNORE 로 읽으면 **지금 돌고 있는 이 스크립트 자신**을 다시
			#   읽다가 엔진이 죽는다(실제로 코어 덤프가 났다). 기본(REUSE)으로 읽는다 —
			#   새 프로세스라 대부분 아직 안 읽힌 상태이므로 파스 오류는 그대로 잡힌다.
			var r := ResourceLoader.load(f)
			# ★ 파스가 깨진 스크립트도 load() 는 **null 이 아닌** GDScript 를 돌려준다.
			#   (예전에는 null 검사만 해서, 문법이 깨진 파일을 이 검사가 그냥 통과시켰다.)
			#   실제로 인스턴스를 만들 수 있는지까지 물어야 잡힌다.
			if r == null or (r is GDScript and not (r as GDScript).can_instantiate()):
				_bad("스크립트가 파스되지 않는다: %s" % f)
				bad += 1
	print("  스크립트 %d개 중 %d개 파스됨" % [n, n - bad])


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
		# 그림 크기 보정. 0 이나 음수면 캐릭터가 안 보이고, 너무 크면 안뜰을 통째로 덮는다.
		var sc: float = float(u.get("sc", 1.0))
		if sc < 0.6 or sc > 1.5:
			_bad("%s 의 그림 보정(sc %.2f)이 0.6~1.5 밖이다" % [id, sc])
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
	# 벽은 바깥에서 안쪽으로 줄어들어야 하고, 길은 벽과 벽 **사이**에 있어야 한다.
	for i in range(1, Balance.WALL_R.size()):
		if float(Balance.WALL_R[i]) >= float(Balance.WALL_R[i - 1]):
			_bad("벽 반지름이 안쪽으로 갈수록 줄지 않는다: %s" % str(Balance.WALL_R))
	if Balance.LANE_R.size() != Balance.WALL_R.size() - 1:
		_bad("길이 %d개인데 벽이 %d겹이다 — 길은 벽 사이에 하나씩이어야 한다"
				% [Balance.LANE_R.size(), Balance.WALL_R.size()])
	for i in range(Balance.LANE_R.size()):
		var lr: float = Balance.LANE_R[i]
		if lr >= float(Balance.WALL_R[i]) or lr <= float(Balance.WALL_R[i + 1]):
			_bad("%d번째 길(%.0f)이 벽 사이(%.0f~%.0f) 밖이다"
					% [i, lr, float(Balance.WALL_R[i + 1]), float(Balance.WALL_R[i])])
	if Balance.SPAWN_R <= float(Balance.WALL_R[0]):
		_bad("몬스터가 나타나는 자리(%.0f)가 바깥벽(%.0f) 안쪽이다 — 벽을 뚫고 나온다"
				% [Balance.SPAWN_R, float(Balance.WALL_R[0])])

	# ★ 문에서 문까지 정확히 LANE_SWEEP 만큼 돌아야 한다. 어긋나면 몬스터가 벽을 통과한다.
	for i in range(Balance.LANE_R.size()):
		var want: float = fposmod(float(Balance.GATE_A[i]) + Balance.LANE_SWEEP, TAU)
		var got: float = fposmod(float(Balance.GATE_A[i + 1]), TAU)
		var diff: float = absf(want - got)
		diff = min(diff, TAU - diff)
		if diff > 0.001:
			_bad("%d번째 길이 다음 문에 안 닿는다 (%.3f rad 어긋남) — 벽을 뚫고 지나간다"
					% [i, diff])

	# 길의 처음과 끝
	var p0 := Balance.path_at(0.0)
	var p1 := Balance.path_at(Balance.path_len())
	if p0.distance_to(Balance.ARENA_CENTER) < float(Balance.WALL_R[0]):
		_bad("길이 바깥벽 안에서 시작한다")
	# ★ path_at 은 마지막 토막을 ALTAR_R 에서 끝내므로 "끝점이 ALTAR_R 인가"는 늘 참이다
	#   (그건 아무것도 검사하지 않는다). 뜻이 있는 것은 **그 끝이 크리스탈 고리와 영웅
	#   고리 사이에 있는가** — 몬스터가 크리스탈까지 오되 영웅 자리를 밟지는 않는가다.
	var end_r: float = p1.distance_to(Balance.ARENA_CENTER)
	var cr_top := 0.0
	for r0 in Balance.CRYSTAL_R:
		cr_top = max(cr_top, float(r0))
	if end_r <= cr_top + 6.0 or end_r >= Balance.HERO_MIN_R:
		_bad("길 끝(%.0f)이 크리스탈 고리(%.0f)와 영웅 고리(%.0f) 사이에 없다"
				% [end_r, cr_top, Balance.HERO_MIN_R])
	# 걷는 시간이 상식적인가 — 너무 짧으면 손도 못 쓰고, 너무 길면 한 탄이 하염없다.
	var walk: float = Balance.path_len() / Balance.PATH_SPEED
	if walk < 15.0 or walk > 60.0:
		_bad("길을 걷는 데 %.0f초 걸린다 (15~60초여야 한다)" % walk)
	else:
		print("  길 %.0fpx · 기본 속도로 %.0f초" % [Balance.path_len(), walk])
	# 길 위의 모든 점이 (1) 화면 안이고 (2) **벽을 문으로만 지나가는가**.
	# ★ (2)가 이 개편의 전제다. 예전에는 화면 경계만 봤는데, 그러면 LANE_JITTER 를
	#   22 → 45 로 키워도 검사가 통과한다 — 몬스터가 벽 한가운데를 걸어 다니는데도.
	var steps := 1200
	var out_screen := false
	var thru_wall := false
	for i in range(steps + 1):
		var s_at: float = Balance.path_len() * float(i) / float(steps)
		for jit in [Balance.LANE_JITTER, -Balance.LANE_JITTER, 0.0]:
			var q := Balance.path_at(s_at, float(jit))
			if not out_screen and (q.x < 10.0 or q.x > 826.0 or q.y < 74.0 or q.y > 794.0):
				_bad("길이 화면 밖으로 나간다: %s (s=%.0f)" % [q, s_at])
				out_screen = true
			if thru_wall:
				continue
			var rel := q - Balance.ARENA_CENTER
			for wi in range(Balance.WALL_R.size()):
				# 벽 두께(그리기 14px)의 절반 + 여유
				if absf(rel.length() - float(Balance.WALL_R[wi])) > 10.0:
					continue
				var da2: float = absf(fposmod(rel.angle() - float(Balance.GATE_A[wi]) + PI,
						TAU) - PI)
				if da2 > Balance.GATE_HALF:
					_bad("길이 %d번 벽을 문이 아닌 곳(각도 %.2f, 문은 %.2f±%.2f)에서 지난다"
							% [wi, rel.angle(), float(Balance.GATE_A[wi]), Balance.GATE_HALF])
					thru_wall = true
					break
		if out_screen and thru_wall:
			break

	# ★ 가장 짧은 사거리로도 **안쪽 길의 절반 이상**은 덮어야 한다.
	#   안 그러면 그 영웅은 벽만 보고 서 있게 된다 (예전 「수호」가 그랬다).
	var min_rng := 99999.0
	var worst := ""
	for t in range(10):
		for k in Balance.PROFILE:
			var pf: Dictionary = Balance.PROFILE[k]
			var v: float = float(Balance.TIER_RNG[t]) * float(pf["rng"])
			if v < min_rng:
				min_rng = v
				worst = "%s %s" % [Poker.HAND_KO[t], pf["ko"]]
	var inner: float = float(Balance.LANE_R[Balance.LANE_R.size() - 1])
	# ★ **실제로 서는 자리 중 가장 나쁜 쪽**으로 잰다. 여섯 명이 서면 고리가 바깥으로
	#   밀리는데(hero_ring_r), 안쪽 고리만 재면 그 사실이 검사를 통과해 버린다.
	var stand: float = max(Balance.HERO_MIN_R, Balance.hero_ring_r(Balance.HERO_SLOTS))
	var cov := _coverage(stand, inner, min_rng)
	if cov < 0.5:
		_bad("가장 짧은 사거리(%s, %.0f)로 %.0f 에 서면 안쪽 길의 %.0f%% 밖에 못 덮는다 (절반은 덮어야 한다)"
				% [worst, min_rng, stand, cov * 100.0])
	else:
		print("  가장 짧은 사거리 %.0f (%s) — %.0f 에 서서 안쪽 길의 %.0f%% 를 덮는다"
				% [min_rng, worst, stand, cov * 100.0])

	# 안뜰: 제단 → 영웅 고리 → 안뜰벽 순서로 겹치지 않아야 한다
	var cr_max := 0.0
	for r in Balance.CRYSTAL_R:
		cr_max = max(cr_max, float(r))
	if cr_max + 14.0 > Balance.HERO_MIN_R:
		_bad("크리스탈 고리(%.0f)가 영웅이 서는 안쪽 고리(%.0f)에 닿는다"
				% [cr_max, Balance.HERO_MIN_R])
	if Balance.ALTAR_R <= cr_max:
		_bad("길 끝(%.0f)이 크리스탈(%.0f)보다 안쪽이다" % [Balance.ALTAR_R, cr_max])
	var core: float = float(Balance.WALL_R[Balance.WALL_R.size() - 1])
	if Balance.HERO_MAX_R >= core - 12.0:
		_bad("영웅이 퍼지는 반지름(%.0f)이 안뜰벽(%.0f)에 닿는다"
				% [Balance.HERO_MAX_R, core])

	# 영웅이 몇이든 자리가 안뜰 안이고, 진입로를 비우는가
	# ★ 실제로는 HERO_SLOTS(6)명뿐이지만, 자리 계산이 그 위에서 무너지지 않는지도 본다 —
	#   나중에 자리를 늘릴 때 여기가 먼저 알려 준다.
	var gate: float = float(Balance.GATE_A[Balance.GATE_A.size() - 1])
	for n in [1, 2, Balance.HERO_SLOTS, 8, 20, 40, 60]:
		for i in range(n):
			var v := Balance.hero_slot(i, n)
			var d := v.length()
			if d > Balance.HERO_MAX_R + 0.5 or d < Balance.HERO_MIN_R - 0.5:
				_bad("영웅 %d명 중 %d번 자리가 고리 밖이다 (%.0f)" % [n, i, d])
				break
			var da: float = absf(fposmod(v.angle() - gate + PI, TAU) - PI)
			if da < Balance.HERO_GAP - 0.001:
				_bad("영웅 %d명 중 %d번이 안뜰문 진입로 위에 서 있다" % [n, i])
				break
	# 크리스탈 자리가 서로 안 겹치는가 (마흔 개까지)
	for i in range(Balance.MAX_LIVES):
		var a := Balance.crystal_slot(i)
		for j in range(i + 1, Balance.MAX_LIVES):
			if a.distance_to(Balance.crystal_slot(j)) < 11.0:
				_bad("크리스탈 %d번과 %d번이 겹친다" % [i, j])
				break


## 반지름 h 에 선 영웅이 사거리 rng 로 반지름 lane 인 길의 몇 %를 덮는가.
static func _coverage(h: float, lane: float, rng: float) -> float:
	var x: float = (h * h + lane * lane - rng * rng) / (2.0 * h * lane)
	if x <= -1.0:
		return 1.0
	if x >= 1.0:
		return 0.0
	return acos(x) / PI


## 영웅 편성 — 안뜰 여섯 자리 · 겹치기 · 캐릭터 인벤토리.
##
## ★ 여기서 실제로 영웅을 마흔 번 받아 본다. 화면 없이 규칙만 돌려 보는 것이라
##   "겹쳤는데 인벤토리에도 남아 있는" 종류의 어긋남이 여기서 잡힌다.
func _check_roster_slots() -> void:
	if Balance.HERO_SLOTS < 1 or Balance.HERO_SLOTS > Balance.hero_ring_cap():
		_bad("안뜰 자리(%d)가 한 겹에 안 들어간다 (한 겹 정원 %d)"
				% [Balance.HERO_SLOTS, Balance.hero_ring_cap()])
	# ★ 캐릭터 전부가 안뜰+인벤토리에 들어가야 한다. 안 그러면 넘칠 때 영웅이 사라진다.
	if Balance.HERO_SLOTS + Balance.BENCH_SLOTS < Roster.UNITS.size():
		_bad("자리가 모자란다: 안뜰 %d + 인벤토리 %d < 캐릭터 %d명"
				% [Balance.HERO_SLOTS, Balance.BENCH_SLOTS, Roster.UNITS.size()])
	if Balance.stack_atk(1) != 1.0 or Balance.stack_atk(3) != 3.0:
		_bad("겹치기 배수가 이상하다: 1겹 %.2f · 3겹 %.2f"
				% [Balance.stack_atk(1), Balance.stack_atk(3)])

	Run.start_run(5150)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var given := 0
	for i in range(40):
		Run.wave = i + 1
		var tier: int = i % 10
		Run.gain_hero(Roster.pick_unit(tier, rng), tier)
		given += 1
		if Run.heroes.size() > Balance.HERO_SLOTS:
			_bad("안뜰에 %d명이 섰다 (%d명까지다)" % [Run.heroes.size(), Balance.HERO_SLOTS])
			break
	# 같은 캐릭터가 두 자리에 있으면 안 된다 — 겹치기가 새는 것이다.
	var seen := {}
	for h in (Run.heroes + Run.bench):
		var id := String(h["unit"]["id"])
		if seen.has(id):
			_bad("%s 가 두 자리에 있다 — 겹치지 않고 하나 더 생겼다" % id)
		seen[id] = true
	# 받은 수와 겹친 수의 합이 같아야 한다. 하나라도 사라지면 여기서 잡힌다.
	if Run.hero_total() != given:
		_bad("영웅 %d명을 받았는데 겹친 수까지 세면 %d명이다 — 어디선가 사라졌다"
				% [given, Run.hero_total()])

	# 겹치면 공격력이 딱 그만큼 오르는가
	if Run.heroes.is_empty():
		_bad("영웅을 마흔 번 받았는데 안뜰이 비었다")
		return
	var one: Dictionary = {"unit": Run.heroes[0]["unit"], "tier": int(Run.heroes[0]["tier"]),
			"wave": 1, "n": 1}
	var three: Dictionary = one.duplicate()
	three["n"] = 3
	var a1: float = float(Run.hero_stats(one)["atk"])
	var a3: float = float(Run.hero_stats(three)["atk"])
	if absf(a3 - a1 * 3.0) > 0.01:
		_bad("3겹인데 공격력이 3배가 아니다 (%.2f -> %.2f)" % [a1, a3])
	# 자리바꿈: 안뜰 0번과 인벤토리 0번을 맞바꿔도 둘 다 그대로 있어야 한다
	if not Run.bench.is_empty():
		var f0 := String(Run.heroes[0]["unit"]["id"])
		var b0 := String(Run.bench[0]["unit"]["id"])
		if not Run.swap_field_bench(0, 0):
			_bad("안뜰과 인벤토리를 맞바꾸지 못했다")
		elif String(Run.heroes[0]["unit"]["id"]) != b0 \
				or String(Run.bench[0]["unit"]["id"]) != f0:
			_bad("맞바꿨는데 자리가 안 바뀌었다")
		if Run.hero_total() != given:
			_bad("자리를 바꿨더니 영웅 수가 %d 로 바뀌었다 (%d 이어야 한다)"
					% [Run.hero_total(), given])
	print("  영웅 편성 정상 (마흔 번 받아 안뜰 %d · 인벤토리 %d · 겹친 수까지 %d)"
			% [Run.heroes.size(), Run.bench.size(), Run.hero_total()])


## 크리스탈 셈이 맞는가. **실제로 전투를 돌려서** 본다.
##
## ★ play_check 로는 이걸 못 잡는다 — 앞 네 탄은 한 마리도 안 놓쳐서 "크리스탈이 두 번
##   깎이는가"를 물어볼 상황 자체가 안 만들어진다. 여기서는 **영웅을 한 명도 안 세워**
##   전부 통과시킨 다음, 깎인 수와 센 수가 같은지 본다.
func _check_battle() -> void:
	# 1) end_run 은 두 번 불려도 기록을 두 번 쌓지 않아야 한다
	Run.start_run(4242)
	Run.kills = 7
	var before: int = Save.total_kills
	Run.end_run(false)
	Run.end_run(false)
	if Save.total_kills != before + 7:
		_bad("end_run 을 두 번 불렀더니 누적 처치 수가 %d 늘었다 (7 이어야 한다)"
				% (Save.total_kills - before))

	# 2) 영웅 없이 한 탄을 돌린다 — 전부 크리스탈까지 온다
	Run.start_run(4243)
	Run.begin_draw()          # 영웅은 안 세운다(confirm_hand 를 안 부른다)
	var sim := BattleSim.new()
	sim.setup(Run, 1, 99)
	var guard := 0
	while not sim.done and guard < 20000:
		sim.step(1.0 / 30.0)
		sim.events.clear()
		guard += 1
	if not sim.done:
		_bad("영웅 없는 전투가 안 끝난다")
	if sim.leak_n != Balance.wave_count(1):
		_bad("1탄 몬스터 %d마리 중 %d마리만 크리스탈에 닿았다"
				% [Balance.wave_count(1), sim.leak_n])
	if Run.lives != Balance.START_LIVES - sim.leaked:
		_bad("크리스탈 셈이 안 맞는다: 깨졌다고 센 것 %d, 실제로 준 것 %d"
				% [sim.leaked, Balance.START_LIVES - Run.lives])
	if sim.wiped:
		_bad("한 마리도 못 잡았는데 전멸(wiped)로 나온다")

	# 3) 크리스탈이 모자랄 때 — 없는 것까지 깨졌다고 세면 안 된다
	Run.start_run(4244)
	Run.begin_draw()
	Run.lives = 3
	var sim2 := BattleSim.new()
	sim2.setup(Run, 5, 77)     # 보스탄 — 보스 하나가 다섯을 부순다
	guard = 0
	while not sim2.done and guard < 20000:
		sim2.step(1.0 / 30.0)
		sim2.events.clear()
		guard += 1
	if sim2.leaked > 3:
		_bad("크리스탈이 3개뿐인데 %d개가 깨진 것으로 셌다" % sim2.leaked)
	if Run.lives != 0 or Run.running:
		_bad("크리스탈이 0 이 됐는데 판이 안 끝났다 (크리스탈 %d, running %s)"
				% [Run.lives, Run.running])
	print("  크리스탈 셈 정상 (1탄 %d마리 통과 · 보스탄에서 %d개까지만 깨짐)"
			% [sim.leak_n, sim2.leaked])


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
			_bad("패시브 id 가 다른 상품과 겹친다: %s" % id)
		seen[id] = true
	# ★ 무기·아이템 id 가 겹치면 상점 버튼 id 가 같아져서 **엉뚱한 것이 팔린다.**
	for wp in Balance.WEAPONS:
		var wid := String(wp["id"])
		if seen.has(wid):
			_bad("무기 id 가 다른 상품과 겹친다: %s" % wid)
		seen[wid] = true
		if int(wp["cost"]) <= 0:
			_bad("무기 %s 의 값이 0 이다" % wid)
		if Balance.weapon_by_id(wid).is_empty():
			_bad("무기 %s 를 id 로 못 찾는다" % wid)
	for it in Balance.ITEMS:
		var iid := String(it["id"])
		if seen.has(iid):
			_bad("아이템 id 가 다른 상품과 겹친다: %s" % iid)
		seen[iid] = true
		if int(it["cost"]) <= 0:
			_bad("아이템 %s 의 값이 0 이다" % iid)
		if Balance.item_by_id(iid).is_empty():
			_bad("아이템 %s 를 id 로 못 찾는다" % iid)
	if Balance.WEAPON_SLOTS < 1 or Balance.WEAPON_SLOTS >= Balance.WEAPONS.size():
		_bad("무기 장착 칸(%d)이 이상하다 — 1 이상, 무기 종류보다 적어야 고르는 재미가 있다"
				% Balance.WEAPON_SLOTS)
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
