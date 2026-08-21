extends RefCounted
class_name BattleSim

## 전투 그 자체. **그리기를 전혀 모른다.**
##
## 왜 화면과 갈라놓았나: 이 머신에는 화면이 없어서 "40탄이 깨지는가"를 눈으로 확인할 수가
## 없다. 시뮬레이터가 따로 있으면 헤드리스로 수백 판을 돌려 클리어율을 숫자로 뽑을 수 있다
## (tests/balance_check.gd). 화면은 이 안의 배열을 그리기만 한다.

## 화면이 이펙트를 붙일 수 있게 남기는 사건들. 화면이 매 프레임 비운다.
var events: Array = []

var wave: int = 1
var time_left: float = 30.0
var total_time: float = 30.0
var monsters: Array = []
var bullets: Array = []
var heroes: Array = []

var kills: int = 0
var gold: int = 0            ## 이번 판에 번 골드
var done: bool = false
var wiped: bool = false      ## 시간 안에 전멸시켰는가
var leaked: int = 0          ## 시간이 끝났을 때 남아 있던 마릿수

var curse_t: float = 0.0
var elapsed: float = 0.0

## ★ 몬스터 좌표를 한 걸음에 한 번만 계산해 캐시한다.
##   예전에는 사거리를 잴 때마다 cos/sin 을 다시 돌렸다. 영웅 40 × 몬스터 60 이면
##   한 프레임에 2,400번이고, 40탄을 자동으로 도는 검사기가 몇 분씩 걸렸다.
var _mp := PackedVector2Array()
var _mr := PackedFloat32Array()

var _rng := RandomNumberGenerator.new()
var _queue: Array = []       ## 아직 안 나온 몬스터
var _spawn_gap: float = 0.4
var _spawn_t: float = 0.0
## Run 오토로드 대신 아무 상태 덩어리나 받을 수 있게 해 둔다(검사기가 가짜 Run 을 넣는다).
var run = null


func setup(run_state, wave_no: int, seed_value: int = 0) -> void:
	run = run_state
	wave = wave_no
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	total_time = run.round_seconds()
	time_left = total_time
	monsters.clear()
	bullets.clear()
	heroes.clear()
	events.clear()
	# ★ 안 비우면 같은 인스턴스로 setup 을 두 번 부를 때 몬스터가 두 배로 나온다.
	_queue.clear()
	kills = 0
	gold = 0
	done = false
	wiped = false
	leaked = 0
	curse_t = 0.0
	elapsed = 0.0

	var n: int = run.heroes.size()
	for i in range(n):
		var h: Dictionary = run.heroes[i]
		var st: Dictionary = run.hero_stats(h)
		heroes.append({
			"h": h, "st": st,
			"pos": Balance.ARENA_CENTER + Balance.hero_slot(i, n),
			"cool": _rng.randf() * 0.4, "acc": 0.0,
			# 매 프레임 String()·Dictionary 조회를 하지 않으려고 미리 꺼내 둔다.
			"kind": String(st["bullet"]), "atk": float(st["atk"]),
			"rate": float(st["rate"]), "rng": float(st["rng"]),
			"crit": float(st["crit"]), "critx": float(st["critx"]),
			"col": Color(String(h["unit"].get("color", "#ffffff"))),
		})

	_build_queue()
	# ★ 몬스터가 늦게 나오면 잡을 시간이 없어 목숨이 그냥 깎인다. 제한 시간의 앞쪽
	#   24% 안에 전부 나오게 한다. (나오는 데 7초 + 안으로 조여드는 데 8초 = 15초,
	#   그래야 마지막에 나온 놈도 12초 넘게 얻어맞는다.)
	_spawn_gap = (total_time * 0.24) / float(maxi(1, _queue.size()))
	_spawn_t = 0.0


func _build_queue() -> void:
	var kinds := Roster.wave_kinds(wave, _rng)
	var cnt := Balance.wave_count(wave)
	for i in range(cnt):
		_queue.append(kinds[i % kinds.size()])
	# 순서를 섞어야 같은 종류가 줄줄이 나오지 않는다.
	for i in range(_queue.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = _queue[i]
		_queue[i] = _queue[j]
		_queue[j] = t
	if Balance.is_boss_wave(wave):
		var b := Roster.boss_for_wave(wave)
		if not b.is_empty():
			_queue.push_front(b)


func _spawn(m: Dictionary) -> void:
	var kind := String(m["kind"])
	var k: Dictionary = Balance.MKIND[kind]
	var hp: float = Balance.wave_hp(wave) * float(k["hp"])
	monsters.append({
		"m": m, "kind": kind, "hp": hp, "max": hp,
		"r": Balance.SPAWN_R, "ang": _rng.randf() * TAU,
		"dir": 1.0 if _rng.randf() < 0.5 else -1.0,
		"spd": float(k["spd"]),
		"slow": 0.0, "slow_t": 0.0, "burn": 0.0, "burn_t": 0.0,
		"flash": 0.0, "cast_t": Balance.CURSE_EVERY * _rng.randf_range(0.5, 1.0),
		"h": float(m["h"]),
		"gold": Balance.kill_gold(wave, kind),
	})
	events.append({"t": "spawn", "p": mpos(monsters[-1])})


static func mpos(mo: Dictionary) -> Vector2:
	var a: float = float(mo["ang"])
	return Balance.ARENA_CENTER + Vector2(cos(a), sin(a)) * float(mo["r"])


## 아직 살아 있거나 아직 안 나온 마릿수 = 지금 시간이 끝나면 깎일 목숨.
func remaining() -> int:
	return monsters.size() + _queue.size()


static func hit_radius(mo: Dictionary) -> float:
	return float(mo["h"]) * 0.32 + 6.0


# --------------------------------------------------------------------------- #
# 한 걸음
# --------------------------------------------------------------------------- #
func step(dt: float) -> void:
	if done:
		return
	elapsed += dt
	time_left = max(0.0, time_left - dt)
	if curse_t > 0.0:
		curse_t = max(0.0, curse_t - dt)

	# 1) 나오기
	if not _queue.is_empty():
		_spawn_t -= dt
		while _spawn_t <= 0.0 and not _queue.is_empty():
			_spawn(_queue.pop_front())
			_spawn_t += _spawn_gap

	_move_monsters(dt)
	_cache_positions()
	_heroes_fire(dt)
	_move_bullets(dt)
	_reap()

	if monsters.is_empty() and _queue.is_empty():
		done = true
		wiped = true
		leaked = 0
	elif time_left <= 0.0:
		done = true
		wiped = false
		leaked = monsters.size() + _queue.size()


func _move_monsters(dt: float) -> void:
	var inward: float = (Balance.SPAWN_R - Balance.INNER_R) / Balance.CLOSE_IN_SEC
	for mo in monsters:
		var slow_mul := 1.0
		if float(mo["slow_t"]) > 0.0:
			mo["slow_t"] = float(mo["slow_t"]) - dt
			slow_mul = 1.0 - float(mo["slow"])
		var sp: float = float(mo["spd"]) * slow_mul
		mo["r"] = max(Balance.INNER_R, float(mo["r"]) - inward * sp * dt)
		var ang_spd: float = min(Balance.MAX_ANGULAR,
				Balance.TANGENT_SPEED * sp / max(20.0, float(mo["r"])))
		mo["ang"] = float(mo["ang"]) + float(mo["dir"]) * ang_spd * dt
		if float(mo["flash"]) > 0.0:
			mo["flash"] = max(0.0, float(mo["flash"]) - dt * 5.0)
		# 화상
		if float(mo["burn_t"]) > 0.0:
			mo["burn_t"] = float(mo["burn_t"]) - dt
			mo["hp"] = float(mo["hp"]) - float(mo["burn"]) * dt
		# 주술사의 저주
		if String(mo["kind"]) == "caster":
			mo["cast_t"] = float(mo["cast_t"]) - dt
			if float(mo["cast_t"]) <= 0.0:
				mo["cast_t"] = Balance.CURSE_EVERY
				curse_t = Balance.CURSE_SEC
				events.append({"t": "curse", "p": mpos(mo)})


## 몬스터 좌표와 피격 반지름을 한 걸음에 한 번만 계산해 둔다.
func _cache_positions() -> void:
	var n := monsters.size()
	_mp.resize(n)
	_mr.resize(n)
	for i in range(n):
		var mo: Dictionary = monsters[i]
		var a: float = mo["ang"]
		var r: float = mo["r"]
		_mp[i] = Vector2(Balance.ARENA_CENTER.x + cos(a) * r,
				Balance.ARENA_CENTER.y + sin(a) * r)
		_mr[i] = float(mo["h"]) * 0.32 + 6.0


func _rate_mult() -> float:
	var m := 1.0
	if curse_t > 0.0:
		m *= 1.0 - Balance.CURSE_RATE
	if run.has("rage") and time_left <= Balance.PASSIVE_RAGE_LEFT:
		m *= 1.0 + Balance.PASSIVE_RAGE
	return m


func _atk_mult() -> float:
	if run.has("first") and elapsed <= Balance.PASSIVE_FIRST_SEC:
		return Balance.PASSIVE_FIRST
	return 1.0


func _heroes_fire(dt: float) -> void:
	var rm := _rate_mult()
	var am := _atk_mult()
	for hi in range(heroes.size()):
		var he: Dictionary = heroes[hi]
		var rng_px: float = he["rng"]
		var kind: String = he["kind"]
		var pos: Vector2 = he["pos"]
		var rng2: float = rng_px * rng_px

		if kind == "aura":
			# 장판은 쿨다운이 없다. 사거리 안 모두에게 초당 꾸준히 준다.
			# ★ 장판은 "한 대"가 없어서 치명타를 굴릴 자리가 없다. 그런데 Run.total_dps()
			#   는 모든 영웅에 치명타 기대값을 곱해 세므로, 안 넣으면 상점 표시와 실제
			#   피해가 어긋나고 자동 플레이 정책도 장판 영웅을 과대평가한다.
			#   그래서 **기대값을 그대로 곱해** 둔다 — 계산과 현실이 같아진다.
			var cmul: float = 1.0 + float(he["crit"]) * (float(he["critx"]) - 1.0)
			var dps: float = float(he["atk"]) * float(he["rate"]) * cmul * am
			var tick: bool = false
			he["acc"] = float(he["acc"]) + dt
			if float(he["acc"]) > 0.25:
				he["acc"] = 0.0
				tick = true
			var any := false
			var first := -1
			for mi in range(_mp.size()):
				if pos.distance_squared_to(_mp[mi]) <= rng2:
					_hurt(mi, dps * dt * rm, false, hi)
					any = true
					if first < 0:
						first = mi
					# ★ 패시브는 "모든 공격"에 붙는다고 적어 놨는데 장판만 빠져 있었다.
					#   매 프레임 붙이면 60번씩 굴리게 되므로 0.25초마다 한 번만 붙인다.
					if tick:
						_field_extras(mi, dps * 0.25)
			if any and tick:
				events.append({"t": "aura", "p": pos, "r": rng_px, "src": hi})
				# 연쇄 낙뢰만은 대상마다 굴리면 초당 수십 번이 된다. 한 번만 굴린다.
				if first >= 0 and run.has("bolt") and _rng.randf() < Balance.PASSIVE_BOLT_P:
					_chain(first, dps * 0.25 * 0.5, 2, 0.7, 150.0, [first], Look.BLUE, hi)
			continue

		he["cool"] = float(he["cool"]) - dt * rm
		if float(he["cool"]) > 0.0:
			continue
		var tgt := _nearest(pos, rng2)
		if tgt < 0:
			he["cool"] = 0.0
			continue
		he["cool"] = 1.0 / max(0.05, float(he["rate"]))

		var crit: bool = _rng.randf() < float(he["crit"])
		var dmg: float = float(he["atk"]) * am * (float(he["critx"]) if crit else 1.0)
		_shoot(hi, tgt, dmg, kind, crit)


func _shoot(hi: int, tgt: int, dmg: float, kind: String, crit: bool) -> void:
	var he: Dictionary = heroes[hi]
	var pos: Vector2 = he["pos"]
	var col: Color = he["col"]
	var spec: Dictionary = Balance.BULLET[kind]

	if kind == "beam":
		events.append({"t": "beam", "a": pos, "b": _mp[tgt], "c": col})
		_hurt(tgt, dmg, crit, hi)
		_on_hit_extras(tgt, dmg, hi)
		return

	var pierce: int = int(spec.get("pierce", 1))
	if run.has("pierce"):
		pierce += 1
	bullets.append({
		"p": pos, "v": (_mp[tgt] - pos).normalized() * float(spec["speed"]),
		"tgt": tgt, "dmg": dmg, "kind": kind, "spd": float(spec["speed"]),
		"life": 2.2, "pierce": pierce, "hit": [], "c": col, "crit": crit, "src": hi,
	})


func _move_bullets(dt: float) -> void:
	var keep: Array = []
	for b in bullets:
		b["life"] = float(b["life"]) - dt
		if float(b["life"]) <= 0.0:
			continue
		var p: Vector2 = b["p"]
		var v: Vector2 = b["v"]
		# 목표를 따라간다. 빗나가면 DPS 계산이 통째로 거짓말이 되므로 유도탄으로 만든다.
		var ti: int = int(b["tgt"])
		if ti >= 0 and ti < _mp.size():
			var want: Vector2 = (_mp[ti] - p).normalized() * float(b["spd"])
			v = v.lerp(want, clampf(dt * 9.0, 0.0, 1.0))
		p += v * dt
		b["p"] = p
		b["v"] = v
		if not Rect2(-80, -80, 1440, 960).has_point(p):
			continue

		# ★ Array(b["hit"]) 로 감싸 쓰지 마라 — 변환본에 append 하면 원본이 안 바뀌어
		#   관통탄이 같은 몬스터를 매 프레임 다시 때린다. 배열은 참조라 그냥 받아 쓴다.
		var hitlist: Array = b["hit"]
		var spent := false
		for mi in range(_mp.size()):
			if hitlist.has(mi):
				continue
			var hr: float = _mr[mi]
			if p.distance_squared_to(_mp[mi]) > hr * hr:
				continue
			hitlist.append(mi)
			_impact(b, mi)
			b["pierce"] = int(b["pierce"]) - 1
			if int(b["pierce"]) <= 0:
				spent = true
			break
		if not spent:
			keep.append(b)
	bullets = keep


func _impact(b: Dictionary, mi: int) -> void:
	var kind := String(b["kind"])
	var dmg: float = float(b["dmg"])
	var spec: Dictionary = Balance.BULLET[kind]
	var src: int = int(b["src"])
	_hurt(mi, dmg, bool(b["crit"]), src)
	events.append({"t": "hit", "p": b["p"], "c": b["c"], "kind": kind})

	match kind:
		"splash":
			var at: Vector2 = _mp[mi] if mi < _mp.size() else Vector2(b["p"])
			var rad2: float = float(spec["radius"]) * float(spec["radius"])
			for j in range(_mp.size()):
				if j == mi:
					continue
				if at.distance_squared_to(_mp[j]) <= rad2:
					_hurt(j, dmg * float(spec["falloff"]), false, src)
			events.append({"t": "splash", "p": at, "r": float(spec["radius"]), "c": b["c"]})
		"chain":
			_chain(mi, dmg * float(spec["decay"]), int(spec["jumps"]) - 1,
					float(spec["decay"]), float(spec["hop"]), [mi], b["c"], src)
		"slow":
			_slow(mi, float(spec["slow"]), float(spec["slow_sec"]))
		"burn":
			_burn(mi, dmg * float(spec["burn"]), float(spec["burn_sec"]))
	_on_hit_extras(mi, dmg, src)


## 패시브가 붙여 주는 추가 효과. 공격 방식과 상관없이 **모든 명중**에 붙는다.
func _on_hit_extras(mi: int, dmg: float, src: int) -> void:
	_field_extras(mi, dmg)
	if run.has("bolt") and _rng.randf() < Balance.PASSIVE_BOLT_P:
		_chain(mi, dmg * 0.5, 2, 0.7, 150.0, [mi], Look.BLUE, src)


## 화상·서리처럼 **대상에게 남는** 효과만. 장판은 이쪽만 쓴다(연쇄는 따로 굴린다).
func _field_extras(mi: int, dmg: float) -> void:
	if run.has("flame"):
		_burn(mi, dmg * Balance.PASSIVE_FLAME_BURN, Balance.PASSIVE_FLAME_SEC)
	if run.has("frost"):
		_slow(mi, Balance.PASSIVE_FROST_SLOW, Balance.PASSIVE_FROST_SEC)


func _chain(from_i: int, dmg: float, jumps: int, decay: float, hop: float,
		seen: Array, col: Color, src: int) -> void:
	if jumps <= 0 or from_i >= _mp.size():
		return
	var at: Vector2 = _mp[from_i]
	var best := -1
	var bd := hop * hop
	for j in range(_mp.size()):
		if seen.has(j):
			continue
		var d := at.distance_squared_to(_mp[j])
		if d < bd:
			bd = d
			best = j
	if best < 0:
		return
	events.append({"t": "beam", "a": at, "b": _mp[best], "c": col})
	_hurt(best, dmg, false, src)
	seen.append(best)
	_chain(best, dmg * decay, jumps - 1, decay, hop, seen, col, src)


## 겹치지 않고 **센 쪽으로 덮어쓴다.** 곱해 버리면 둔화 둘만 겹쳐도 몬스터가 멈춘다.
##
## ★ 다만 **이미 풀린 뒤에는 세기를 물려주지 않는다.** 예전에는 늘 max 라서, 센 둔화가
##   끝난 뒤에 약한 둔화를 걸어도 옛 세기가 그대로 살아났다. 화상 쪽이 특히 나빴다 —
##   보스에게 한 번 박힌 강한 화상이 라운드 내내 약한 화상의 탈을 쓰고 계속 탔다.
func _slow(mi: int, amount: float, sec: float) -> void:
	if mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	mo["slow"] = amount if float(mo["slow_t"]) <= 0.0 else max(float(mo["slow"]), amount)
	mo["slow_t"] = max(float(mo["slow_t"]), sec)


func _burn(mi: int, dps: float, sec: float) -> void:
	if mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	mo["burn"] = dps if float(mo["burn_t"]) <= 0.0 else max(float(mo["burn"]), dps)
	mo["burn_t"] = max(float(mo["burn_t"]), sec)


func _hurt(mi: int, dmg: float, crit: bool, _src: int) -> void:
	if mi < 0 or mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	mo["hp"] = float(mo["hp"]) - dmg
	mo["flash"] = 1.0
	if crit:
		events.append({"t": "crit", "p": _mp[mi] if mi < _mp.size() else Vector2.ZERO,
			"n": int(dmg)})


## 사거리(제곱) 안에서 가장 가까운 몬스터. 제곱끼리 비교해 sqrt 를 안 쓴다.
func _nearest(from: Vector2, rng2: float) -> int:
	var best := -1
	var bd := rng2
	for i in range(_mp.size()):
		var d := from.distance_squared_to(_mp[i])
		if d < bd:
			bd = d
			best = i
	return best


## 죽은 것을 치운다. ★ 인덱스가 앞으로 당겨지므로 탄이 들고 있는 목표 번호도 같이 고쳐야 한다.
##   이걸 빼먹으면 탄이 엉뚱한 몬스터를 쫓아가고, 마지막 한 마리가 안 잡히는 버그가 된다.
func _reap() -> void:
	var dead: Array[int] = []
	for i in range(monsters.size()):
		if float(monsters[i]["hp"]) <= 0.0:
			dead.append(i)
	if dead.is_empty():
		return
	for i in dead:
		var mo: Dictionary = monsters[i]
		var dp: Vector2 = _mp[i] if i < _mp.size() else mpos(mo)
		var midas: float = (1.0 + Balance.PASSIVE_MIDAS) if run.has("midas") else 1.0
		var g: int = int(round(float(mo["gold"]) * Balance.gold_mult(run.lv("gold")) * midas))
		gold += g
		kills += 1
		run.add_gold(g)
		events.append({"t": "die", "p": dp, "c": Color(String(mo["m"]["color"])),
			"h": float(mo["h"]), "gold": g})
		if run.has("vamp") and _rng.randf() < Balance.PASSIVE_VAMP_P:
			run.add_lives(1)
			events.append({"t": "life", "p": dp})

	var alive: Array = []
	var remap := {}
	for i in range(monsters.size()):
		if float(monsters[i]["hp"]) > 0.0:
			remap[i] = alive.size()
			alive.append(monsters[i])
	monsters = alive
	for b in bullets:
		b["tgt"] = int(remap.get(int(b["tgt"]), -1))
		var nh: Array = []
		for x in (b["hit"] as Array):
			if remap.has(int(x)):
				nh.append(int(remap[int(x)]))
		b["hit"] = nh
