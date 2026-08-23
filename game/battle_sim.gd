extends RefCounted
class_name BattleSim

## 전투 그 자체. **그리기를 전혀 모른다.**
##
## 왜 화면과 갈라놓았나: 이 머신에는 화면이 없어서 "40탄이 깨지는가"를 눈으로 확인할 수가
## 없다. 시뮬레이터가 따로 있으면 헤드리스로 수백 판을 돌려 클리어율을 숫자로 뽑을 수 있다
## (tests/balance_check.gd). 화면은 이 안의 배열을 그리기만 한다.
##
## 규칙(사용자가 정한 것):
##  - 몬스터는 **벽으로 나뉜 길**을 따라 걸어 들어온다. 길은 Balance.path_at() 하나가 정한다.
##  - 길 끝에는 **크리스탈**이 있다. 한 마리가 닿을 때마다 크리스탈이 하나 깨진다(목숨 -1).
##  - **제한 시간은 없다.** 그 탄의 몬스터가 전부 죽거나 닿으면 끝난다.

## 화면이 이펙트를 붙일 수 있게 남기는 사건들. 화면이 매 프레임 비운다.
var events: Array = []

var wave: int = 1
var monsters: Array = []
var bullets: Array = []
var heroes: Array = []

var kills: int = 0
var gold: int = 0            ## 이번 판에 번 골드
var done: bool = false
var wiped: bool = false      ## 크리스탈을 하나도 안 깨뜨렸는가
var leaked: int = 0          ## 깨진 크리스탈 수 (보스 하나가 다섯을 부순다)
var leak_n: int = 0          ## 크리스탈에 닿아 버린 마릿수

var curse_t: float = 0.0     ## 주술사의 저주가 남은 시간
var freeze_t: float = 0.0    ## 「시간 정지」가 남은 시간
var rally_t: float = 0.0     ## 「진군 나팔」이 남은 시간
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
var _path_len: float = 1.0
## Run 오토로드 대신 아무 상태 덩어리나 받을 수 있게 해 둔다(검사기가 가짜 Run 을 넣는다).
var run = null


func setup(run_state, wave_no: int, seed_value: int = 0) -> void:
	run = run_state
	wave = wave_no
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
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
	leak_n = 0
	curse_t = 0.0
	freeze_t = 0.0
	rally_t = 0.0
	elapsed = 0.0
	_path_len = Balance.path_len()

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
			# 공격 속성. 매 명중마다 Dictionary 를 뒤지지 않으려고 여기 꺼내 둔다.
			"elem": String(st.get("elem", "none")),
			"col": Color(String(h["unit"].get("color", "#ffffff"))),
		})

	_build_queue()
	# ★ 몬스터가 찔끔찔끔 나오면 한 번에 두어 마리씩만 상대하게 되어 광역·장판이
	#   통째로 무의미해진다. 정해진 시간 안에 전부 내보낸다.
	_spawn_gap = Balance.SPAWN_WINDOW / float(maxi(1, _queue.size()))
	_spawn_t = 0.0


func _build_queue() -> void:
	# ★ 편성은 **Run 이 씨앗으로 정해 둔 것**을 그대로 쓴다. 여기서 다시 굴리면
	#   상점이 "다음 탄에 이 놈들이 온다"고 보여 준 것과 실제가 달라진다 —
	#   그 순간 상성은 플레이어가 쓸 수 없는 규칙이 된다.
	#   (검사기가 넣는 가짜 Run 처럼 kinds_for 가 없으면 예전처럼 굴린다)
	var kinds: Array = []
	if run != null and run.has_method("kinds_for"):
		kinds = run.kinds_for(wave)
	if kinds.is_empty():
		kinds = Roster.wave_kinds(wave, _rng)
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
	# 보스는 길 한가운데로 걷는다 — 덩치가 커서 옆으로 밀면 벽을 뚫고 나간다.
	var jit: float = 0.0 if kind == "boss" else _rng.randf_range(-1.0, 1.0) * Balance.LANE_JITTER
	monsters.append({
		"m": m, "kind": kind, "hp": hp, "max": hp,
		"s": 0.0, "off": jit,
		"spd": float(k["spd"]),
		"slow": 0.0, "slow_t": 0.0, "burn": 0.0, "burn_t": 0.0,
		"flash": 0.0, "cast_t": Balance.CURSE_EVERY * _rng.randf_range(0.5, 1.0),
		"h": float(m["h"]),
		# 몸 속성 — 무엇에 약하고 무엇을 튕겨 내는가 (Balance.MBODY).
		"body": String(m.get("body", "null")),
		"gold": Balance.kill_gold(wave, kind),
		"crush": int(k.get("crush", 1)),
	})
	events.append({"t": "spawn", "p": mpos(monsters[-1])})


static func mpos(mo: Dictionary) -> Vector2:
	return Balance.path_at(float(mo["s"]), float(mo["off"]))


## 길을 얼마나 왔는가 (0~1). 화면이 "다 와 간다"를 보여 줄 때 쓴다.
func progress(mo: Dictionary) -> float:
	return clampf(float(mo["s"]) / max(1.0, _path_len), 0.0, 1.0)


## 아직 살아 있거나 아직 안 나온 마릿수.
func remaining() -> int:
	return monsters.size() + _queue.size()


static func hit_radius(mo: Dictionary) -> float:
	return float(mo["h"]) * 0.32 + 6.0


# --------------------------------------------------------------------------- #
# 아이템 — 화면(또는 자동 플레이 정책)이 불러 준다
# --------------------------------------------------------------------------- #
## 지금 쓰면 실제로 무슨 일이 일어나는가.
## ★ 크리스탈이 꽉 찼는데 「크리스탈 수리」를 쓰면 140G 짜리가 아무 일도 없이 사라진다.
##   화면은 이 값으로 버튼을 꺼 두고, 눌려도 여기서 한 번 더 막는다.
func can_use_item(id: String) -> bool:
	if done or run.item_count(id) <= 0:
		return false
	if id == "repair":
		return run.lives < run.max_lives()
	return true


## 아이템 하나를 쓴다. 개수는 Run 이 줄이고(spend_item), 효과는 여기서 낸다.
func use_item(id: String) -> bool:
	if done or not can_use_item(id):
		return false
	if not run.spend_item(id):
		return false
	match id:
		"bomb":
			var dmg: float = Balance.bomb_damage(wave)
			# ★ 뒤에서부터 도는 이유는 없다 — _hurt 는 배열을 안 건드리고 hp 만 깎는다.
			#   실제로 치우는 것은 이번 걸음 끝의 _reap 이다.
			for i in range(monsters.size()):
				# ★ 폭탄은 **무상성**이다. 이름은 「벼락」이지만 상성을 안 탄다.
				#   왜냐하면 이것은 후반 방어의 안전망이기 때문이다 — 전기로 두면
				#   돌골렘(뒷 구간 체력의 3분의 1을 차지한다)에게 반밖에 안 들어가서,
				#   **안전망이 정확히 제일 필요한 곳에서만 사라진다.**
				_hurt(i, dmg, false, -1, "none")
			events.append({"t": "bomb", "p": Balance.ARENA_CENTER})
		"freeze":
			freeze_t = Balance.ITEM_FREEZE_SEC
			events.append({"t": "freeze", "p": Balance.ARENA_CENTER})
		"rally":
			rally_t = Balance.ITEM_RALLY_SEC
			events.append({"t": "rally", "p": Balance.ARENA_CENTER})
		"repair":
			run.add_lives(Balance.ITEM_REPAIR)
			events.append({"t": "repair", "p": Balance.ARENA_CENTER})
	return true


# --------------------------------------------------------------------------- #
# 한 걸음
# --------------------------------------------------------------------------- #
func step(dt: float) -> void:
	if done:
		return
	elapsed += dt
	if curse_t > 0.0:
		curse_t = max(0.0, curse_t - dt)
	if freeze_t > 0.0:
		freeze_t = max(0.0, freeze_t - dt)
	if rally_t > 0.0:
		rally_t = max(0.0, rally_t - dt)

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
		wiped = leak_n == 0
	elif not run.running:
		# 크리스탈이 다 깨졌다. 더 굴려 봐야 의미가 없다.
		done = true
		wiped = false


func _move_monsters(dt: float) -> void:
	if freeze_t > 0.0:
		return          # 「시간 정지」 — 걷지도, 타지도, 저주하지도 않는다
	var mire: float = Balance.mire_mult(run.lv("mire"))
	for mo in monsters:
		var slow_mul := 1.0
		if float(mo["slow_t"]) > 0.0:
			mo["slow_t"] = float(mo["slow_t"]) - dt
			slow_mul = 1.0 - float(mo["slow"])
		var sp: float = Balance.PATH_SPEED * float(mo["spd"]) * slow_mul * mire
		mo["s"] = min(_path_len, float(mo["s"]) + sp * dt)
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
		_mp[i] = Balance.path_at(float(mo["s"]), float(mo["off"]))
		_mr[i] = float(mo["h"]) * 0.32 + 6.0


func _rate_mult() -> float:
	var m := 1.0
	if curse_t > 0.0:
		m *= 1.0 - Balance.CURSE_RATE
	if run.has("rage") and elapsed >= Balance.PASSIVE_RAGE_AFTER:
		m *= 1.0 + Balance.PASSIVE_RAGE
	if rally_t > 0.0:
		m *= 1.0 + Balance.ITEM_RALLY_RATE
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
					_hurt(mi, dps * dt * rm, false, hi, String(he["elem"]))
					any = true
					if first < 0:
						first = mi
					# ★ 패시브는 "모든 공격"에 붙는다고 적어 놨는데 장판만 빠져 있었다.
					#   매 프레임 붙이면 60번씩 굴리게 되므로 0.25초마다 한 번만 붙인다.
					if tick:
						_field_extras(mi, dps * 0.25)
			if any and tick:
				events.append({"t": "aura", "p": pos, "r": rng_px, "src": hi,
					"c": he["col"]})
				# 연쇄 낙뢰만은 대상마다 굴리면 초당 수십 번이 된다. 한 번만 굴린다.
				if first >= 0 and run.has("bolt") and _rng.randf() < Balance.PASSIVE_BOLT_P:
					_chain(first, dps * 0.25 * 0.5, 2, 0.7, 150.0, [first], Look.BLUE, hi, "elec")
			continue

		he["cool"] = float(he["cool"]) - dt * rm
		if float(he["cool"]) > 0.0:
			continue
		var tgt := _front_target(pos, rng2)
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
	var elem: String = he["elem"]
	events.append({"t": "fire", "p": pos, "d": (_mp[tgt] - pos).normalized(), "c": col})

	if kind == "beam":
		events.append({"t": "beam", "a": pos, "b": _mp[tgt], "c": col, "big": true})
		var em: float = _hurt(tgt, dmg, crit, hi, elem)
		events.append({"t": "hit", "p": _mp[tgt], "c": col, "kind": kind,
			"crit": crit, "em": em, "el": elem})
		_on_hit_extras(tgt, dmg, hi)
		return

	var pierce: int = int(spec.get("pierce", 1))
	if run.has("pierce"):
		pierce += 1
	bullets.append({
		"p": pos, "v": (_mp[tgt] - pos).normalized() * float(spec["speed"]),
		"tgt": tgt, "dmg": dmg, "kind": kind, "spd": float(spec["speed"]),
		"life": 2.6, "pierce": pierce, "hit": [], "c": col, "crit": crit, "src": hi,
		"el": elem,
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
		# ★ 지나온 자리를 남긴다 — 화면이 꼬리를 그린다. 탄이 점 하나였을 때는
		#   무엇이 날아가는지가 안 보였다.
		b["prev"] = p
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
	var rad_mul: float = run.wpn_mult("radius")
	var elem := String(b.get("el", "none"))
	var em: float = _hurt(mi, dmg, bool(b["crit"]), src, elem)
	events.append({"t": "hit", "p": b["p"], "c": b["c"], "kind": kind,
		"crit": bool(b["crit"]), "em": em, "el": elem})

	match kind:
		"splash":
			var at: Vector2 = _mp[mi] if mi < _mp.size() else Vector2(b["p"])
			var rad: float = float(spec["radius"]) * rad_mul
			_splash(mi, at, rad, dmg * float(spec["falloff"]), src, elem)
			events.append({"t": "splash", "p": at, "r": rad, "c": b["c"]})
		"chain":
			_chain(mi, dmg * float(spec["decay"]), int(spec["jumps"]) - 1,
					float(spec["decay"]), float(spec["hop"]), [mi], b["c"], src, elem)
		"slow":
			_slow(mi, float(spec["slow"]), float(spec["slow_sec"]))
		"burn":
			_burn(mi, dmg * float(spec["burn"]), float(spec["burn_sec"]), elem)

	# 무기 「분열 탄두」 — 방식과 상관없이 모든 탄이 작게 터진다.
	var split: float = run.wpn_best("split")
	if split > 0.0 and kind != "splash":
		var sat: Vector2 = _mp[mi] if mi < _mp.size() else Vector2(b["p"])
		var srad: float = split * rad_mul
		# 분열 조각은 **쏜 놈의 속성 그대로** 터진다. 무기가 속성을 바꾸지는 않는다.
		_splash(mi, sat, srad, dmg * 0.35, src, elem)
		events.append({"t": "splash", "p": sat, "r": srad, "c": b["c"]})
	_on_hit_extras(mi, dmg, src)


## 한 점 둘레를 함께 때린다. 광역탄과 분열 탄두가 같은 함수를 쓴다.
func _splash(skip: int, at: Vector2, radius: float, dmg: float, src: int,
		elem: String = "none") -> void:
	var r2: float = radius * radius
	for j in range(_mp.size()):
		if j == skip:
			continue
		if at.distance_squared_to(_mp[j]) <= r2:
			_hurt(j, dmg, false, src, elem)


## 패시브가 붙여 주는 추가 효과. 공격 방식과 상관없이 **모든 명중**에 붙는다.
## ★ 속성을 안 받는다. 여기서 붙는 것은 패시브·무기뿐이고 그것들은 **자기 속성이
##   정해져 있다** — 「연쇄 낙뢰」는 언제나 전기, 「화염 부적」은 언제나 불이다.
##   쏜 영웅의 속성을 받아 두면 언젠가 그것을 잘못 연결하게 된다.
func _on_hit_extras(mi: int, dmg: float, src: int) -> void:
	_field_extras(mi, dmg)
	# ★ 「연쇄 낙뢰」는 이름 그대로 **번개**다. 쏜 영웅의 속성이 아니라 늘 전기로 친다 —
	#   불 마법사가 지른 낙뢰가 불이 되면 상점 설명과 화면이 어긋난다.
	if run.has("bolt") and _rng.randf() < Balance.PASSIVE_BOLT_P:
		_chain(mi, dmg * 0.5, 2, 0.7, 150.0, [mi], Look.BLUE, src, "elec")


## 화상·서리처럼 **대상에게 남는** 효과만. 장판은 이쪽만 쓴다(연쇄는 따로 굴린다).
## ★ 패시브·무기가 붙이는 것은 **자기 속성이 정해져 있다.** 「화염 부적」은 언제나 불이고
##   「서리 부적」·「서리 심」은 피해가 없어 속성을 안 탄다.
func _field_extras(mi: int, dmg: float) -> void:
	if run.has("flame"):
		_burn(mi, dmg * Balance.PASSIVE_FLAME_BURN, Balance.PASSIVE_FLAME_SEC, "fire")
	if run.has("frost"):
		_slow(mi, Balance.PASSIVE_FROST_SLOW, Balance.PASSIVE_FROST_SEC)
	# 무기 「서리 심」
	var ws: float = run.wpn_best("slow")
	if ws > 0.0:
		_slow(mi, ws, run.wpn_best("slow_sec"))


func _chain(from_i: int, dmg: float, jumps: int, decay: float, hop: float,
		seen: Array, col: Color, src: int, elem: String = "none") -> void:
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
	events.append({"t": "bolt", "a": at, "b": _mp[best], "c": col})
	_hurt(best, dmg, false, src, elem)
	seen.append(best)
	_chain(best, dmg * decay, jumps - 1, decay, hop, seen, col, src, elem)


## 겹치지 않고 **센 쪽으로 덮어쓴다.** 곱해 버리면 둔화 둘만 겹쳐도 몬스터가 멈춘다.
##
## ★ 다만 **이미 풀린 뒤에는 세기를 물려주지 않는다.** 예전에는 늘 max 라서, 센 둔화가
##   끝난 뒤에 약한 둔화를 걸어도 옛 세기가 그대로 살아났다. 화상 쪽이 특히 나빴다 —
##   보스에게 한 번 박힌 강한 화상이 라운드 내내 약한 화상의 탈을 쓰고 계속 탔다.
func _slow(mi: int, amount: float, sec: float) -> void:
	if mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	# ★ **처음 얼어붙는 순간에만** 알린다. 둔화는 명중마다 다시 걸린다 —
	#   서리 부적·「서리 심」은 모든 명중에, 장판은 0.25초마다 붙이므로 매번 알리면
	#   초당 수백 개가 쌓여 이펙트가 화면을 덮는다. 이미 얼어 있는 동안에는 몸에 얼음이
	#   남아 있으니 다시 터뜨릴 까닭도 없다.
	var fresh: bool = float(mo["slow_t"]) <= 0.0
	mo["slow"] = amount if fresh else max(float(mo["slow"]), amount)
	mo["slow_t"] = max(float(mo["slow_t"]), sec)
	if fresh:
		events.append({"t": "frost", "p": _mp[mi] if mi < _mp.size() else mpos(mo),
			"h": float(mo["h"])})


## ★ 상성 배수를 **붙이는 순간에 미리 곱해** 둔다. 화상 도트는 매 걸음 _move_monsters()
##   에서 hp 를 직접 깎으므로 _hurt() 를 안 거친다 — 거기서 다시 곱하려면 몬스터마다
##   "이 화상은 무슨 속성이었나"를 들고 다녀야 하고, 겹쳐 걸릴 때 어느 쪽 속성을 남길지가
##   또 문제가 된다. 미리 곱해 두면 max() 로 센 쪽을 남기는 규칙이 그대로 맞는다.
func _burn(mi: int, dps: float, sec: float, elem: String = "none") -> void:
	if mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	dps *= Balance.elem_mult(elem, String(mo.get("body", "null")))
	mo["burn"] = dps if float(mo["burn_t"]) <= 0.0 else max(float(mo["burn"]), dps)
	mo["burn_t"] = max(float(mo["burn_t"]), sec)


## 몬스터 하나를 때린다. **피가 깎이는 곳은 여기 한 군데뿐이다** — 상성 배수도
## 그래서 여기서만 곱한다. 광역·연쇄·장판·분열이 저마다 곱하기 시작하면
## "광역은 상성을 타는데 연쇄는 안 타는" 식으로 조용히 갈라진다.
##
## 돌려주는 것: **실제로 적용된 상성 배수.** 화면이 「약점!」을 띄우는 데 쓴다 —
## 화면이 같은 계산을 다시 하면 전투와 표시가 언젠가 어긋난다.
func _hurt(mi: int, dmg: float, crit: bool, _src: int, elem: String = "none") -> float:
	if mi < 0 or mi >= monsters.size():
		return 1.0
	var mo: Dictionary = monsters[mi]
	var em: float = Balance.elem_mult(elem, String(mo.get("body", "null")))
	dmg *= em
	mo["hp"] = float(mo["hp"]) - dmg
	mo["flash"] = 1.0
	if crit:
		events.append({"t": "crit", "p": _mp[mi] if mi < _mp.size() else Vector2.ZERO,
			"n": int(dmg)})
	return em


## 사거리(제곱) 안에서 **가장 앞선**(크리스탈에 가장 가까운) 몬스터.
##
## ★ 예전에는 가장 가까운 놈을 쐈다. 길이 생긴 뒤로는 그게 나쁜 선택이다 —
##   코앞에서 갓 들어온 놈을 때리는 동안 다 온 놈이 크리스탈을 깬다.
##   디펜스 게임에서 먼저 막아야 하는 것은 늘 **제일 앞선 놈**이다.
func _front_target(from: Vector2, rng2: float) -> int:
	var best := -1
	var best_s := -1.0
	for i in range(_mp.size()):
		if from.distance_squared_to(_mp[i]) > rng2:
			continue
		var s: float = float(monsters[i]["s"])
		if s > best_s:
			best_s = s
			best = i
	return best


## 죽은 것과 **크리스탈까지 간 것**을 치운다.
## ★ 인덱스가 앞으로 당겨지므로 탄이 들고 있는 목표 번호도 같이 고쳐야 한다.
##   이걸 빼먹으면 탄이 엉뚱한 몬스터를 쫓아가고, 마지막 한 마리가 안 잡히는 버그가 된다.
func _reap() -> void:
	var dead: Array[int] = []
	var arrived: Array[int] = []
	for i in range(monsters.size()):
		# 다 왔더라도 그 순간 죽었으면 죽은 쪽이 먼저다 — 마지막 한 대로 막아 낸 것이다.
		if float(monsters[i]["hp"]) <= 0.0:
			dead.append(i)
		elif float(monsters[i]["s"]) >= _path_len:
			arrived.append(i)
	if dead.is_empty() and arrived.is_empty():
		return

	for i in dead:
		var mo: Dictionary = monsters[i]
		var dp: Vector2 = _mp[i] if i < _mp.size() else mpos(mo)
		var midas: float = (1.0 + Balance.PASSIVE_MIDAS) if run.has("midas") else 1.0
		var g: int = int(round(float(mo["gold"]) * Balance.gold_mult(run.lv("gold"))
				* midas * run.wpn_mult("gold")))
		gold += g
		kills += 1
		# ★ 여기서 바로 올린다. 화면이 전투가 끝난 뒤에 한꺼번에 더하게 두면,
		#   크리스탈이 0 이 되어 판이 **전투 도중** 끝날 때 그 판의 처치 수가
		#   저장 기록에 영영 안 들어간다(end_run 이 그 전에 불린다).
		run.kills += 1
		run.add_gold(g)
		events.append({"t": "die", "p": dp, "c": Color(String(mo["m"]["color"])),
			"h": float(mo["h"]), "gold": g})
		if run.has("vamp") and _rng.randf() < Balance.PASSIVE_VAMP_P:
			run.add_lives(1)
			events.append({"t": "life", "p": dp})

	for i in arrived:
		var mo2: Dictionary = monsters[i]
		var ap: Vector2 = _mp[i] if i < _mp.size() else mpos(mo2)
		# ★ **남아 있는 크리스탈까지만** 깨진 것으로 센다. 예전에는 최소 1 로 잘랐는데,
		#   같은 걸음에 앞엣놈이 이미 0 으로 만들어 놓으면 없는 크리스탈이 깨진 것으로
		#   집계되어 결과창이 "크리스탈이 6개인데 9개가 깨졌다"고 적었다.
		var crush: int = mini(int(mo2["crush"]), maxi(0, run.lives))
		leak_n += 1
		if crush > 0:
			leaked += crush
			# ★ 목숨이 깎이는 곳은 **여기 한 군데뿐**이다. 화면에서 또 깎으면 두 배가 된다.
			var idx: int = maxi(0, run.lives - 1)
			run.add_lives(-crush)
			events.append({"t": "leak", "p": ap, "i": idx, "n": crush,
				"c": Color(String(mo2["m"]["color"])), "h": float(mo2["h"])})

	var alive: Array = []
	var remap := {}
	for i in range(monsters.size()):
		var mo3: Dictionary = monsters[i]
		if float(mo3["hp"]) > 0.0 and float(mo3["s"]) < _path_len:
			remap[i] = alive.size()
			alive.append(mo3)
	monsters = alive
	for b in bullets:
		b["tgt"] = int(remap.get(int(b["tgt"]), -1))
		var nh: Array = []
		for x in (b["hit"] as Array):
			if remap.has(int(x)):
				nh.append(int(remap[int(x)]))
		b["hit"] = nh
