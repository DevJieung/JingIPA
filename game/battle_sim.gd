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
## ★ **깔려 있는 장판들.** 탄과 달리 **좌표만** 들고 있다 — 몬스터 번호를 담으면
##   `_reap()` 이 배열을 당길 때 조용히 딴 놈을 가리키게 된다(탄만 번호를 고쳐 준다).
##   화면은 이 배열을 그대로 읽어서 땅에 원을 그린다(사건이 아니라 상태다 — 깔린 동안
##   내내 보여야 하는데 사건은 한 프레임짜리다).
var zones: Array = []
var heroes: Array = []

var kills: int = 0
var gold: int = 0            ## 이번 판에 번 골드
var done: bool = false
var wiped: bool = false      ## 크리스탈을 하나도 안 깨뜨렸는가
var leaked: int = 0          ## 깨진 크리스탈 수 (보스 하나가 셋을 부순다 — MKIND 의 crush)
var leak_n: int = 0          ## 크리스탈에 닿아 버린 마릿수

## ★ **이 탄에 들어오는 몬스터 체력의 합.** 오른쪽 정보판이 「준 피해」 막대의 **자**로
## 쓴다 (사용자가 정한 것: 「최대값을 해당탄 전체 몬스터 HP합으로해서 누적치를
## Normalize」). setup 에서 한 번만 세면 되는 값이다 — 큐에 든 것이 그 탄의 전부이고
## 도중에 몬스터가 늘어나는 길이 없다(분열도 소환도 회복도 없다).
## ★ 늘어나는 길을 새로 만들면 **여기도 같이 고쳐라.** 안 고치면 막대가 자를 넘는다.
var total_hp: float = 0.0

## 지금 때리고 있는 놈과 그때의 상성 배수. **화상 도트를 누구 몫으로 셀지**가 여기서
## 정해진다 — `_burn()` 이 붙는 순간에 읽어 몬스터에게 적어 둔다.
## ★ 갈아 끼우는 곳은 `_hurt()` 한 곳(과 들불 하나)뿐이다. 여러 곳에서 만지면
##   「누가 붙인 불인지」가 조용히 어긋난다.
var _atk_src: int = -1
var _atk_em: float = 1.0

var curse_t: float = 0.0     ## 주술사의 저주가 남은 시간
var elapsed: float = 0.0
## 패시브 「과열」 — 한 마리 잡을 때마다 오르고 가만두면 식는다.
var surge: float = 0.0
var surge_t: float = 0.0

## ★ 몬스터 좌표와 피격 반지름을 한 걸음에 한 번만 계산해 캐시한다.
##   **사거리를 없앤 뒤에도 이 캐시는 그대로 남는다** — 겨냥은 더 이상 거리를 안 재지만,
##   탄의 명중 판정 · 광역 · 연쇄 · 장판 · 들불은 전부 좌표를 거리로 잰다. 거기서 매번
##   cos/sin 을 다시 돌리면 탄 이백 개 × 몬스터 예순 마리가 한 프레임에 쌓여,
##   100탄을 자동으로 도는 검사기가 몇 분씩 걸린다.
var _mp := PackedVector2Array()
var _mr := PackedFloat32Array()

var _rng := RandomNumberGenerator.new()
## 팔을 뻗는 중인 발. **쏘기로 정한 것과 탄이 떠나는 것은 다른 순간이다** —
## 사이에 그 캐릭터가 팔을 뻗는 시간(Balance.windup)이 있다.
var _pending: Array = []
var _queue: Array = []       ## 아직 안 나온 몬스터
var _spawn_gap: float = 0.4
var _spawn_t: float = 0.0
var _path_len: float = 1.0
var _rank: int = 1           ## 이 탄이 걸린 테마의 험한 정도(1~5)
## Run 오토로드 대신 아무 상태 덩어리나 받을 수 있게 해 둔다(검사기가 가짜 Run 을 넣는다).
var run = null


func setup(run_state, wave_no: int, seed_value: int = 0) -> void:
	run = run_state
	wave = wave_no
	if seed_value != 0:
		_rng.seed = seed_value
	elif run != null and run.has_method("wave_seed"):
		_rng.seed = run.wave_seed(wave)
	else:
		_rng.randomize()
	monsters.clear()
	bullets.clear()
	zones.clear()
	heroes.clear()
	events.clear()
	_pending.clear()
	# ★ 안 비우면 같은 인스턴스로 setup 을 두 번 부를 때 몬스터가 두 배로 나온다.
	_queue.clear()
	kills = 0
	gold = 0
	done = false
	wiped = false
	leaked = 0
	leak_n = 0
	curse_t = 0.0
	surge = 0.0
	surge_t = 0.0
	elapsed = 0.0
	_path_len = Balance.path_len()
	# 이 탄이 걸린 테마가 얼마나 험한가. 체력에 곱해진다(Balance.wave_hp).
	# ★ 한 번만 물어서 들고 있는다 — 몬스터 하나 나올 때마다 물으면 테마 표를 매번 뒤진다.
	_rank = 1
	if run != null and run.has_method("theme_rank"):
		_rank = int(run.theme_rank(wave))

	run.ensure_posts()
	_spawn_route = 0
	var n: int = run.heroes.size()
	var hsc: float = Balance.hero_scale(n)
	for i in range(n):
		var h: Dictionary = run.heroes[i]
		var st: Dictionary = run.hero_stats(h)
		var u: Dictionary = h["unit"]
		heroes.append({
			"h": h, "st": st,
			"pos": Balance.post_position(int(h["post"])),
			"cool": _rng.randf() * 0.4, "acc": 0.0,
			# 바라보는 쪽. **시뮬레이터가 들고 있는다** — 총구 자리가 여기에 달려 있고,
			# 화면이 따로 굴리면 그림은 왼쪽을 보는데 탄은 오른쪽에서 나가게 된다.
			"face": 1.0,
			# 총구 — 발밑에서 잰 상대 좌표(오른쪽을 볼 때). 쏠 때 face 로 좌우만 뒤집는다.
			"muz": Balance.muzzle_off(u, hsc, 1.0),
			# 매 프레임 String()·Dictionary 조회를 하지 않으려고 미리 꺼내 둔다.
			"kind": String(st["bullet"]), "atk": float(st["atk"]),
			# 역할(일격·도탄·특효·광역). 상태이상 세기와 밀어내기가 여기에 달렸다.
			"role": String(st.get("role", "single")),
			"rate": float(st["rate"]),
			"range": float(st["range"]),
			# ★ 겹친 만큼 **한 번에 여러 발**이 나간다(x4 면 넷). 한 발의 세기는 이미
			#   atk 에 나뉘어 있으므로 단일 대상 피해는 정확히 n배 그대로다.
			"shots": int(st.get("shots", 1)),
			# 라운드 끝에 보여 줄 전과. **화면이 아니라 여기서** 센다 — 헤드리스 검사도
			# 같은 값을 봐야 "누가 일했나"를 숫자로 잴 수 있다.
			"dmg": 0.0, "kills": 0,
			# ★ 같은 피해를 **상성별로** 한 번 더 쌓는다 (2배 · 1배 · 0.5배).
			#   전투 정보판이 이 셋을 세 막대로 그린다 — 「이 영웅이 이번 탄에 약점을
			#   찌르고 있나, 저항에 막히고 있나」가 클리어율보다 먼저 보여야 할 것이고,
			#   그건 합계 하나로는 절대 안 보인다. dmg == dw + dn + dr 이다.
			#   (면역 0배는 피해가 0 이라 어디에도 안 쌓인다 — 「무효」는 화면이 따로 말한다)
			"dw": 0.0, "dn": 0.0, "dr": 0.0,
			"crit": float(st["crit"]), "critx": float(st["critx"]),
			# 공격 속성. 매 명중마다 Dictionary 를 뒤지지 않으려고 여기 꺼내 둔다.
			"elem": String(st.get("elem", "none")),
			"col": Color(String(u.get("color", "#ffffff"))),
			"wind": float(u.get("wind", Balance.WIND_FALLBACK)),
		})

	_build_queue()
	# 이 탄의 총 체력. 큐에 든 것이 그 탄의 전부다(보스는 _build_queue 가 맨 앞에 넣는다).
	var hp1: float = Balance.wave_hp(wave, _rank)
	total_hp = 0.0
	for q in _queue:
		total_hp += hp1 * float(Balance.MKIND[String(q["kind"])]["hp"])
	# ★ 몬스터가 찔끔찔끔 나오면 한 번에 두어 마리씩만 상대하게 되어 광역·장판이
	#   통째로 무의미해진다. 정해진 시간 안에 전부 내보낸다.
	_spawn_gap = Balance.SPAWN_WINDOW / float(maxi(1, _queue.size()))
	_spawn_t = 0.0


func _build_queue() -> void:
	# ★ 편성은 **Run 이 씨앗으로 정해 둔 것**을 그대로 쓴다. 여기서 다시 굴리면
	#   상점이 "다음 탄에 이 놈들이 온다"고 보여 준 것과 실제가 달라진다 —
	#   그 순간 상성은 플레이어가 쓸 수 없는 규칙이 된다.
	#   (검사기가 넣는 가짜 Run 처럼 kinds_for 가 없으면 예전처럼 굴린다)
	if run != null and run.has_method("spawns_for"):
		_queue.append_array(run.spawns_for(wave))
	else:
		var kinds: Array = []
		if run != null and run.has_method("kinds_for"):
			kinds = run.kinds_for(wave)
		if kinds.is_empty():
			kinds = Roster.wave_kinds(wave, _rng)
		for i in range(Balance.wave_count(wave)):
			_queue.append(kinds[i % kinds.size()])
	# 순서를 섞어야 같은 종류가 줄줄이 나오지 않는다.
	for i in range(_queue.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = _queue[i]
		_queue[i] = _queue[j]
		_queue[j] = t
	if Balance.is_boss_wave(wave):
		# ★ 보스도 **테마가 정한다** — 화산이면 불 보스, 설산이면 얼음 보스다.
		#   (검사기가 넣는 가짜 Run 처럼 boss_for 가 없으면 불 보스로 받는다)
		var b: Dictionary = {}
		if run != null and run.has_method("boss_for"):
			b = run.boss_for(wave)
		if b.is_empty():
			b = Roster.boss_of_body("flame")
		if not b.is_empty():
			_queue.push_front(b)


## Reposition in place: cooldowns, in-flight attacks and damage counters survive.
func move_hero(index: int, post: int) -> bool:
	if done or index < 0 or index >= heroes.size():
		return false
	if not run.move_hero(index, post):
		return false
	for hero in heroes:
		hero["pos"] = Balance.post_position(int(hero["h"]["post"]))
	return true

var _spawn_route: int = 0

func _spawn(m: Dictionary) -> void:
	var kind := String(m["kind"])
	var k: Dictionary = Balance.MKIND[kind]
	var hp: float = Balance.wave_hp(wave, _rank) * float(k["hp"])
	# 보스는 길 한가운데로 걷는다 — 덩치가 커서 옆으로 밀면 벽을 뚫고 나간다.
	var jit: float = 0.0 if kind == "boss" else _rng.randf_range(-1.0, 1.0) * Balance.LANE_JITTER
	monsters.append({
		"m": m, "kind": kind, "hp": hp, "max": hp,
		"s": 0.0, "off": jit, "route": _spawn_route % 2,
		"motion_t": 0.0, "motion_phase": fposmod(float(_spawn_route) * 0.618034, 1.0),
		"spd": float(k["spd"]),
		"slow": 0.0, "slow_t": 0.0, "burn": 0.0, "burn_t": 0.0,
		# 지금 붙은 화상을 **누가** 붙였고 그때 배수가 얼마였나. 화상 도트를 그 영웅의
		# 몫으로 세는 데 쓴다 (_burn · _move_monsters).
		"burn_src": -1, "burn_em": 1.0,
		# 마비 — stun_t 동안 완전히 멎고, 풀린 뒤 stun_cd 동안은 다시 안 걸린다.
		# ★ 재우는 시간(cd)이 없으면 연사 영웅 하나가 16% 를 초당 열 번 굴려서
		#   사실상 **영구 정지**를 건다. 그러면 길이 몬스터 벽이 되고 전투가 멎는다.
		"stun_t": 0.0, "stun_cd": 0.0,
		# 물 「특효」에 밀려서 되돌아간 거리의 **총합**. 뚜껑(RIDER_PUSH_MAX)이 없으면
		# 물 특효 여섯이 한 놈을 영원히 제자리에 붙들어 전투가 멎는다.
		"push": 0.0, "push_left": 0.0, "push_t": 0.0,
		"flash": 0.0, "cast_t": Balance.CURSE_EVERY * _rng.randf_range(0.5, 1.0),
		"h": float(m["h"]),
		# 몸 속성 — 무엇에 약하고 무엇을 튕겨 내는가 (Balance.MBODY).
		"body": String(m.get("body", "")),
		"gold": Balance.kill_gold(wave, kind),
		"crush": int(k.get("crush", 1)),
	})
	events.append({"t": "spawn", "p": mpos(monsters[-1])})
	_spawn_route += 1


static func mpos(mo: Dictionary) -> Vector2:
	return Balance.path_at(float(mo["s"]), float(mo["off"]), int(mo.get("route", 0)))


## 길을 얼마나 왔는가 (0~1). 화면이 "다 와 간다"를 보여 줄 때 쓴다.

func progress(mo: Dictionary) -> float:
	return clampf(float(mo["s"]) / max(1.0, _path_len), 0.0, 1.0)


## 아직 살아 있거나 아직 안 나온 마릿수.
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
	if curse_t > 0.0:
		curse_t = max(0.0, curse_t - dt)
	# 「과열」은 마지막 처치로부터 PASSIVE_SURGE_SEC 가 지나면 통째로 식는다.
	if surge_t > 0.0:
		surge_t = max(0.0, surge_t - dt)
		if surge_t <= 0.0:
			surge = 0.0

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
	# ★ 장판은 **탄 뒤·수확 앞**에 굴린다. 좌표 캐시(_mp)가 이번 걸음 것이라야 하고,
	#   이미 쓰러진 놈을 때리면 안 되기 때문이다(_reap 이 걸음 끝에 치운다).
	_step_zones(dt)
	_reap()

	if monsters.is_empty() and _queue.is_empty():
		done = true
		wiped = leak_n == 0
	elif not run.running:
		# 크리스탈이 다 깨졌다. 더 굴려 봐야 의미가 없다.
		done = true
		wiped = false


func _move_monsters(dt: float) -> void:
	var mire: float = Balance.mire_mult(run.lv("mire"))
	for mo in monsters:
		# ★ **마비가 둔화보다 먼저다.** 마비 중에는 걸음이 0 이라 둔화는 뜻이 없다 —
		#   둘을 곱하면 "얼리고 마비시켰더니 더 느려졌다"는 없는 규칙이 생긴다.
		#   재우는 시간(stun_cd)은 마비가 풀린 뒤부터 흐른다.
		if float(mo["stun_cd"]) > 0.0:
			mo["stun_cd"] = float(mo["stun_cd"]) - dt
		var slow_mul := 1.0
		if float(mo["slow_t"]) > 0.0:
			mo["slow_t"] = float(mo["slow_t"]) - dt
			slow_mul = 1.0 - float(mo["slow"])
		if float(mo["stun_t"]) > 0.0:
			mo["stun_t"] = float(mo["stun_t"]) - dt
			slow_mul = 0.0
			if float(mo["stun_t"]) <= 0.0:
				mo["stun_cd"] = Balance.STUN_IMMUNE_SEC
		var sp: float = Balance.PATH_SPEED * float(mo["spd"]) * slow_mul * mire
		# 순방향 보행 시계: 둔화·마비·배속을 따른다. 밀쳐내기에도 역재생하지 않는다.
		mo["motion_t"] = float(mo.get("motion_t", 0.0)) + dt * float(mo["spd"]) * slow_mul * mire
		# 실제 경로 좌표를 조금씩 되돌려 표시·피격·겨냥이 같은 위치를 사용한다.
		# 전진은 계속 합산하므로 밀림 시간이 추가 마비 시간으로 바뀌지 않는다.
		var pushed := _advance_push(mo, dt)
		mo["s"] = clampf(float(mo["s"]) + sp * dt - pushed, 0.0, _path_len)
		if float(mo["flash"]) > 0.0:
			mo["flash"] = max(0.0, float(mo["flash"]) - dt * 5.0)
		# 화상. **`_hurt()` 를 안 거치는 유일한 자리다**(CLAUDE.md 5-1).
		# ★ 그래서 「누가 얼마나 때렸는가」도 여기서 따로 쌓는다. 예전에는 화상이
		#   **아무에게도** 안 세어졌다 — 불 영웅이 실제로 깎은 체력의 3분의 1쯤이
		#   전과판 밖에 있었고, 「이번 탄 전체 체력」을 자로 쓰는 막대에서는 그 구멍이
		#   그대로 「불 영웅은 일을 덜 한다」로 보인다.
		# ★ 남은 체력까지만 깎는다 — _hurt 와 같은 규칙이다.
		if float(mo["burn_t"]) > 0.0:
			mo["burn_t"] = float(mo["burn_t"]) - dt
			var bd: float = minf(float(mo["burn"]) * dt, maxf(0.0, float(mo["hp"])))
			if bd > 0.0:
				mo["hp"] = float(mo["hp"]) - bd
				_credit(int(mo.get("burn_src", -1)), bd, float(mo.get("burn_em", 1.0)))
		# 주술사의 저주. ★ 마비 중에는 못 던진다 — 멎은 놈이 주문을 외면
		#   "마비가 걸렸다"가 화면에서 안 읽힌다.
		if String(mo["kind"]) == "caster" and float(mo["stun_t"]) <= 0.0:
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
		_mp[i] = mpos(monsters[i])
		_mr[i] = hit_radius(monsters[i])


## i 번 몬스터의 자리. 이번 걸음의 캐시(_mp)가 있으면 그것을, 없으면(걸음 사이에 밖에서
## 부르는 검사기처럼) 길에서 다시 잰다 — 둘은 같은 식이라 값이 같다.
func _pos_of(i: int) -> Vector2:
	return _mp[i] if i < _mp.size() else mpos(monsters[i])


func _rate_mult() -> float:
	var m := 1.0
	if curse_t > 0.0:
		m *= 1.0 - Balance.CURSE_RATE
	if run.has("rage") and elapsed >= Balance.PASSIVE_RAGE_AFTER:
		m *= 1.0 + Balance.PASSIVE_RAGE
	# 패시브 「과열」 — 한 마리 잡을 때마다 쌓이고 3초 안에 또 못 잡으면 식는다.
	if surge > 0.0:
		m *= 1.0 + surge
	return m


func _atk_mult() -> float:
	if run.has("first") and elapsed <= Balance.PASSIVE_FIRST_SEC:
		return Balance.PASSIVE_FIRST
	return 1.0


func _heroes_fire(dt: float) -> void:
	var rm := _rate_mult()
	var am := _atk_mult()
	_release(dt)
	for hi in range(heroes.size()):
		var he: Dictionary = heroes[hi]
		var kind: String = he["kind"]

		var shots: int = int(he.get("shots", 1))
		# ★ 예전에 여기 있던 「장판(aura)」 갈래를 통째로 없앴다. 그것은 쿨다운도
		#   총구도 팔 뻗기도 없이 **판 위의 전부**를 매 프레임 때리는, 이 파일에서
		#   혼자만 다른 길이었다. 지금의 장판(zone)은 다른 방식과 똑같이
		#   쿨다운 → 겨눔 → 팔 들기 → 시전을 거친다 — 다른 것은 탄이 아니라
		#   **땅에 원이 깔린다**는 것뿐이고, 그 갈래는 `_shoot()` 안에 있다.

		he["cool"] = float(he["cool"]) - dt * rm
		if float(he["cool"]) > 0.0:
			continue
		var tgt := _nearest_target(Vector2(he["pos"]), float(he["range"]))
		if tgt < 0:
			he["cool"] = 0.0
			continue
		var cool: float = 1.0 / max(0.05, float(he["rate"]))
		he["cool"] = cool

		var crit: bool = _rng.randf() < float(he["crit"])
		var dmg: float = float(he["atk"]) * am * (float(he["critx"]) if crit else 1.0)
		_aim(hi, tgt, dmg, kind, crit, cool / max(0.05, rm), shots)


## 쏘기로 정했다. **아직 탄은 안 나간다** — 그 캐릭터가 팔을 뻗는 만큼 기다린다.
##
## ★ 왜 나누었나: 예전에는 정하는 순간 탄이 나갔다. 그런데 화면의 공격 클립은 팔을
##   뻗는 데 0.195~0.265초를 쓰므로, **탄이 먼저 날아가고 팔이 뒤따라 뻗었다.**
##   무엇을 보고 쏜 것인지가 화면에서 안 읽히는 자리였다.
## ★ 쿨다운은 **정하는 순간에** 건다. 그래야 연사 속도가 예전과 한 톨도 안 달라진다 —
##   달라지는 것은 한 발의 "출발이 조금 늦다"뿐이다.
func _aim(hi: int, tgt: int, dmg: float, kind: String, crit: bool, cool: float,
		shots: int = 1) -> void:
	var he: Dictionary = heroes[hi]
	var pos: Vector2 = he["pos"]
	var d: Vector2 = (_mp[tgt] - pos).normalized()
	# ★ 좌우 뒤집기에 죽은 구간을 둔다. 목표가 정면 위아래에 있으면 d.x 가 0 근처에서
	#   흔들리는데, 그대로 받으면 매 발마다 좌우로 뒤집혀 발작처럼 보인다.
	if absf(d.x) > 0.22:
		he["face"] = -1.0 if d.x < 0.0 else 1.0
	var wind: float = Balance.windup(he["h"]["unit"], cool)
	# ★ **장판은 팔을 드는 데 더 오래 걸린다.** 사용자가 정한 연출이 「두 팔을 들어올림과
	#   동시에 발밑에서 머리 위로 이펙트가 지나간다」라, 그 이펙트가 몸을 훑고 지나갈
	#   시간이 있어야 한다. 그 몫이 BULLET["zone"]["cast"] 다.
	#   ☆ 쿨다운은 여전히 **정하는 순간**에 걸었으므로 연사 속도는 한 톨도 안 달라진다
	#     (CLAUDE.md 18-9). 달라지는 것은 한 번의 출발이 조금 더 늦다는 것뿐이다.
	#   ☆ 쿨다운보다 길어지면 시전이 겹치므로 거기서 자른다.
	if kind == "zone":
		# ★ **더하지 말고 바닥값으로 쓴다.** 뻗는 시간은 원래 그 캐릭터의 클립이 정한다
		#   (놓는 칸까지 걸린 시간 = anim.json 의 hit_ms, CLAUDE.md 18-8). 장판 클립은
		#   팔을 다 드는 데 그만큼 걸리므로 그 값이 이미 길다 — 거기에 cast 를 **더하면**
		#   두 번 세는 셈이라 팔은 다 들었는데 한참 더 서 있게 된다.
		#   클립이 아직 없는 캐릭터(fallback wind 0.24)를 위한 바닥값으로만 쓴다.
		wind = minf(cool * 0.86, maxf(wind, float(Balance.BULLET["zone"]["cast"])))
	events.append({"t": "aim", "p": _muzzle(hi), "d": d, "src": hi,
		"face": float(he["face"]), "w": wind, "kind": kind})
	if wind <= 0.0:
		_shoot(hi, tgt, dmg, kind, crit, shots)
		return
	_pending.append({"hi": hi, "t": wind, "dmg": dmg, "kind": kind, "crit": crit,
		"shots": shots})


## 팔을 다 뻗은 발을 내보낸다.
##
## ★ 목표는 **놓는 순간에 다시 고른다.** 뻗는 0.2초 사이에 겨눈 놈이 죽을 수 있고,
##   그때 죽은 번호를 그대로 쓰면 탄이 엉뚱한 놈에게 날아간다(_reap 이 배열을 당긴다).
##   사거리 안에 살아 있는 적이 없으면 발사를 취소하고 쿨다운을 풀어 준다.
func _release(dt: float) -> void:
	if _pending.is_empty():
		return
	var keep: Array = []
	for s in _pending:
		s["t"] = float(s["t"]) - dt
		if float(s["t"]) > 0.0:
			keep.append(s)
			continue
		var hi: int = int(s["hi"])
		if hi < 0 or hi >= heroes.size():
			continue
		var he: Dictionary = heroes[hi]
		var tgt := _nearest_target(Vector2(he["pos"]), float(he["range"]))
		if tgt < 0:
			he["cool"] = 0.0
			continue
		_shoot(hi, tgt, float(s["dmg"]), String(s["kind"]), bool(s["crit"]),
				int(s.get("shots", 1)))
	_pending = keep


## 그 영웅의 **총구 자리**. 발밑이 아니라 손끝(또는 총구)이다.
func _muzzle(hi: int) -> Vector2:
	var he: Dictionary = heroes[hi]
	var m: Vector2 = he["muz"]
	return Vector2(he["pos"]) + Vector2(m.x * float(he["face"]), m.y)


## 실제로 쏜다. **겹친 수(shots)만큼 한 번에 나간다** — x4 면 넷이 나가고, 넷이
## 저마다 터지고 저마다 상태이상을 굴린다(사용자가 정한 규칙).
##
## ★ 한 발의 세기는 이미 Run.hero_stats 에서 나뉘어 있으므로(stack_atk), 단일 대상
##   피해는 예전의 「공격력 n배」와 정확히 같다. 달라지는 것은 **광역·연쇄·마비가
##   그 수만큼 겹친다**는 것뿐이다.
## ★ 발끼리 아주 조금 벌려 쏜다. 완전히 같은 자리에서 같은 방향으로 내면 화면에서
##   한 발로 보여서, 겹친 것이 눈에 하나도 안 나타난다.
const SPREAD := 0.085


func _shoot(hi: int, tgt: int, dmg: float, kind: String, crit: bool,
		shots: int = 1) -> void:
	var he: Dictionary = heroes[hi]
	# 발사/시전 순간의 위치로 다시 확인한다. 준비 중 이동한 영웅도 예외가 없다.
	if not _target_in_range(tgt, Vector2(he["pos"]), float(he["range"])):
		return
	var col: Color = he["col"]
	var spec: Dictionary = Balance.BULLET.get(kind, Balance.BULLET["shot"])
	var elem: String = he["elem"]
	# ★ 탄은 **총구**에서 나간다. 예전에는 영웅이 선 자리(=발밑)에서 나가서, 화면에서는
	#   팔을 치켜드는데 탄이 신발 밑에서 튀어나왔다.
	var pos: Vector2 = _muzzle(hi)
	var n: int = maxi(1, shots)
	# ★ 누가 쐈는지(src)를 같이 흘린다. 화면이 총구 불꽃을 그 자리에 붙이는 데 쓴다 —
	#   시뮬레이터는 여전히 그리기를 모르고, 그냥 "몇 번 영웅이 이 방향으로 쐈다"만 적는다.
	events.append({"t": "fire", "p": pos, "d": (_mp[tgt] - pos).normalized(), "c": col,
		"src": hi, "el": elem, "kind": kind, "n": n})

	if kind == "beam":
		# 앞선 적들에게 나누어 쏘고, 적보다 발 수가 많으면 남은 발도 다시 배분한다.
		# 보스 하나만 남아도 x4의 네 발을 모두 맞혀야 겹침의 가치가 사라지지 않는다.
		var tl := _nearest_targets(Vector2(he["pos"]), n, float(he["range"]))
		if tl.is_empty():
			return
		for shot in range(n):
			var mi: int = int(tl[shot % tl.size()])
			if float(monsters[mi]["hp"]) <= 0.0:
				mi = _nearest_target(Vector2(he["pos"]), float(he["range"]))
			if mi < 0:
				break
			events.append({"t": "beam", "a": pos, "b": _mp[mi], "c": col, "big": true,
				"el": elem, "src": hi})
			var em: float = _hurt(mi, dmg, crit, hi, elem)
			events.append({"t": "hit", "p": _mp[mi], "c": col, "kind": kind,
				"crit": crit, "em": em, "el": elem, "n": dmg * em, "src": hi})
			_on_hit_extras(mi, dmg, hi)
		return

	if kind == "zone":
		# ★ **장판** — 탄이 안 나간다. 땅에 원이 깔리고 **그 안에 든 것만** 맞는다
		#   (사용자가 정한 것). 자리는 사거리 안에서 겨눈 놈이 선 곳이다.
		var zr: float = float(spec["radius"]) * run.pas_mult("radius")
		var ticks: int = Balance.zone_ticks()
		var at := Vector2(_mp[tgt])
		zones.append({
			"at": at, "r": zr, "src": hi, "el": elem, "c": col,
			# 한 번 시전한 몫(dmg)을 틱 수로 나눈다 — 그래서 **단일 대상 초당 피해는
			# BULLET.dmg 배수 그대로**이고 Run.total_dps() 가 거짓말을 하지 않는다.
			"dmg": dmg / float(ticks),
			"crit": crit,
			"t": 0.0, "n": 0, "max": ticks,
			"delay": float(spec["delay"]), "tick": float(spec["tick"]),
		})
		events.append({"t": "zone", "p": at, "r": zr, "c": col, "el": elem,
			"src": hi, "delay": float(spec["delay"])})
		return

	var pierce: int = int(spec.get("pierce", 1))
	if run.has("pierce"):
		pierce += 1
	var base: Vector2 = (_mp[tgt] - pos).normalized()
	var side := Vector2(-base.y, base.x)
	for i in range(n):
		# 가운데를 기준으로 좌우로 벌린다 (한 발이면 0).
		var k: float = float(i) - float(n - 1) * 0.5
		var d: Vector2 = base.rotated(k * SPREAD)
		bullets.append({
			"p": pos + side * (k * 5.0), "v": d * float(spec["speed"]),
			"tgt": tgt, "dmg": dmg, "kind": kind, "spd": float(spec["speed"]),
			"life": 2.6, "pierce": pierce, "hit": [], "c": col, "crit": crit, "src": hi,
			"el": elem,
			# ★ **도탄**만 갖는 셋. 맞고 나서 몇 번 더 튈 수 있는가, 튈 때마다 세기가
			#   얼마로 주는가, 얼마나 멀리까지 튈 수 있는가.
			#   ☆ 겹쳐도 튀는 횟수는 **안 늘린다**. 늘리면 x5 도탄 여섯이 한 발에
			#     서른 번씩 튀어 폰이 먼저 무너진다(STACK_SHOT_MAX 와 같은 까닭).
			"bounce": int(spec.get("bounce", 0)),
			"decay": float(spec.get("decay", 1.0)),
			"hop": float(spec.get("hop", 0.0)),
		})


## 유도가 목표 쪽으로 도는 빠르기. 클수록 곧게 꽂힌다.
const HOMING := 9.0
## 뚫고 나간 탄이 다음 목표를 고를 때 보는 앞쪽 각도(코사인). 0.94 면 약 20도다.
##
## ★ **좁게 잡아라.** 넓게 잡으면 관통탄이 뚫자마자 옆으로 꺾여 다음 놈을 찾아가는데,
##   그건 「뚫고 지나간다」가 아니라 유도탄 세 발이고 화면에서도 물리가 어긋나 보인다.
##   숫자로도 컸다 — 75도로 두었더니 짚신궁수 **하나**가 12탄을 한 마리도 안 놓치고
##   막았다(tests/play_check 의 「뚫림」 검사가 뜻을 잃었다). 20도면 사실상 **가던 길에
##   있는 놈**만 이어서 맞힌다.
const RETARGET_CONE := 0.94
## 그리고 그 거리 안에서만 고른다. 이보다 멀면 그냥 곧게 날아가 사라진다.
const RETARGET_R := 200.0


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
			var to: Vector2 = _mp[ti] - p
			# ★ **지나친 목표는 더 쫓지 않는다.** 이 한 줄이 없으면 탄이 목표를 지나칠
			#   때마다 되돌아서 그 둘레를 뱅뱅 돈다 — 관통탄과 「관통」 패시브가 붙은
			#   탄에서 눈에 띄게 나빴다. 이미 때린 놈은 다시 못 때리는데(hit 목록)
			#   유도는 그대로 그놈을 향해 있어서, 처음 맞힌 몬스터 둘레에서
			#   **어물쩡거리다가 엉뚱한 쪽으로 튕겨 나가는** 것처럼 보였다.
			if to.dot(v) > 0.0:
				v = v.lerp(to.normalized() * float(b["spd"]), clampf(dt * HOMING, 0.0, 1.0))
			else:
				b["tgt"] = -1
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
				# ★ **도탄은 여기서 안 죽는다 — 아무 데로나 꺾인다.**
				#   연쇄(chain)와 갈라지는 자리다: 연쇄는 순간이동해서 **가장 가까운**
				#   놈으로 가고, 도탄은 **실제로 날아가서** 닿는 거리 안의 놈 중
				#   **무작위**로 고른 놈에게 간다. 그래서 화면에서 「어디로 튈지
				#   모른다」가 읽히고, 번개가 아니므로 속성도 안 가린다(CLAUDE.md 5-4).
				var bounce: int = int(b.get("bounce", 0))
				var nb := -1
				if bounce > 0:
					nb = _ric_target(p, hitlist, float(b.get("hop", 0.0)))
				if nb >= 0:
					b["bounce"] = bounce - 1
					b["pierce"] = 1
					b["dmg"] = float(b["dmg"]) * float(b.get("decay", 1.0))
					b["tgt"] = nb
					var nv: Vector2 = (_mp[nb] - p).normalized() * float(b["spd"])
					b["v"] = nv
					v = nv
					# 꺾이고 나서도 닿을 만큼은 살려 둔다(끝물에 꺾이면 그냥 사라진다).
					b["life"] = maxf(float(b["life"]), 0.9)
					events.append({"t": "ric", "a": p, "b": _mp[nb], "c": b["c"],
						"el": String(b.get("el", "none"))})
				else:
					spent = true
			else:
				# ★ 뚫고 나갔으면 **다음 목표를 새로 고른다.** 안 고르면 방금 때린
				#   놈을 계속 겨눈 채로 도는데, 그놈은 hit 목록에 있어 다시는 못 때린다.
				b["tgt"] = _next_target(p, v, hitlist)
			break
		if not spent:
			keep.append(b)
	bullets = keep


## 뚫고 나간 탄이 이어서 노릴 놈. **앞쪽**에 있고 아직 안 때린 놈 중 가장 가까운 것.
##
## ★ 뒤쪽까지 보면 탄이 유턴한다 — 그러면 고친 뜻이 없다. 앞쪽 원뿔 안만 본다.
func _next_target(p: Vector2, v: Vector2, hitlist: Array) -> int:
	var dir: Vector2 = v.normalized()
	if dir == Vector2.ZERO:
		return -1
	var best := -1
	var bd: float = RETARGET_R * RETARGET_R
	for j in range(_mp.size()):
		if hitlist.has(j):
			continue
		var to: Vector2 = _mp[j] - p
		var d2: float = to.length_squared()
		if d2 >= bd or d2 <= 0.0001:
			continue
		if dir.dot(to / sqrt(d2)) < RETARGET_CONE:
			continue
		bd = d2
		best = j
	return best


## **도탄이 다음에 꺾여 갈 놈.** 닿는 거리 안에서 **무작위**다.
##
## ★ `_next_target()` 을 쓰면 안 된다. 그것은 관통탄이 「가던 길에 있는 놈」을 이어
##   맞히라고 앞쪽 20도로 좁혀 놓은 것이고(RETARGET_CONE), 그 좁힘에는 까닭이 있다 —
##   넓히면 관통이 유도탄 세 발이 되어 검사가 통째로 뜻을 잃는다. 도탄은 반대로
##   **아무 데로나 튀어야** 뜻이 사므로, 원뿔이 아예 없는 제 함수를 따로 둔다.
## ★ 이 함수는 `_rng` 를 쓴다. 그래서 도탄을 넣은 뒤로는 **씨앗을 박은 검사들의 값이
##   통째로 밀린다**(치명타·마비와 같은 난수를 나눠 쓰기 때문). 회귀로 읽지 말고
##   기준값을 다시 재라(CLAUDE.md 16).
func _ric_target(p: Vector2, hitlist: Array, hop: float) -> int:
	if hop <= 0.0:
		return -1
	var h2: float = hop * hop
	var cand: Array = []
	for j in range(_mp.size()):
		if hitlist.has(j):
			continue
		if p.distance_squared_to(_mp[j]) <= h2:
			cand.append(j)
	if cand.is_empty():
		return -1
	return int(cand[_rng.randi_range(0, cand.size() - 1)])


## 깔려 있는 장판을 굴린다. **한 걸음에 한 번**, 탄이 다 움직이고 수확하기 전에.
##
## ★ 왜 사건이 아니라 배열인가: 장판은 깔린 동안 **내내** 화면에 있어야 하는데
##   사건은 한 프레임짜리다. 화면은 `sim.zones` 를 몬스터·탄과 똑같이 읽어서 그린다.
## ★ 좌표만 들고 있다 — 몬스터 번호를 담으면 `_reap()` 이 배열을 당길 때 딴 놈을
##   가리키게 된다(번호를 고쳐 주는 것은 탄뿐이다).
func _step_zones(dt: float) -> void:
	if zones.is_empty():
		return
	var keep: Array = []
	for z in zones:
		z["t"] = float(z["t"]) + dt
		var el: float = float(z["t"]) - float(z["delay"])
		if el < 0.0:
			# 아직 안 깔렸다. 이 틈이 「어디에 깔릴지」를 보여 주는 시간이다.
			keep.append(z)
			continue
		# 깔린 순간에 한 번, 그 뒤로는 tick 마다 한 번.
		var due: int = mini(int(z["max"]),
				int(floor(el / maxf(0.01, float(z["tick"])))) + 1)
		var n: int = int(z["n"])
		while n < due:
			_zone_hit(z)
			n += 1
		z["n"] = n
		if n < int(z["max"]):
			keep.append(z)
	zones = keep


## 장판 한 틱. **원 안에 든 것만** 때린다 — 이것이 옛 장판(aura)과 갈라지는 전부다.
func _zone_hit(z: Dictionary) -> void:
	var at: Vector2 = z["at"]
	var r2: float = float(z["r"]) * float(z["r"])
	var src: int = int(z["src"])
	var elem := String(z["el"])
	var dmg: float = float(z["dmg"])
	var first := -1
	var fem := 1.0
	var cnt := 0
	for j in range(_mp.size()):
		if at.distance_squared_to(_mp[j]) > r2:
			continue
		var em: float = _hurt(j, dmg, false, src, elem)
		cnt += 1
		if first < 0:
			first = j
			fem = em
		# 패시브는 "모든 공격"에 붙는다. 장판은 틱마다 한 번이다(매 프레임이 아니다).
		_field_extras(j, dmg)
	if cnt <= 0:
		return
	# ★ 숫자·소리를 위한 사건. `n` 은 **상성을 이미 곱한** 값이다(「hit」과 같은 규약).
	#   `cnt` 가 「이 틱이 몇 마리를 덮었나」다 — 원을 그리는 지금도 이 수가 있어야
	#   가장자리에 걸친 놈까지 셌는지가 눈에 보인다.
	events.append({"t": "zone_tick", "p": at, "r": float(z["r"]), "c": z["c"],
		"el": elem, "src": src, "n": dmg * fem, "em": fem,
		"mp": _mp[first], "cnt": cnt})
	# 연쇄 낙뢰는 대상마다 굴리면 초당 수십 번이 된다. 틱마다 한 번만 굴린다.
	if run.has("bolt") and _rng.randf() < Balance.PASSIVE_BOLT_P:
		_chain(first, dmg * 0.5, 2, 0.7, 150.0, [first], Look.BLUE, src, "elec")


## 물 「특효」가 맞은 놈을 **뒤로 민다.** 걸은 거리를 되돌리는 것이다.
##
## ★ 물에는 상태이상이 없다(CLAUDE.md 5-2 옆줄의 규칙 — 물은 그 몫을 화력 1.12배로
##   받는다). 그래서 「특효」가 물에게는 걸 것이 없는데, 그 자리를 이것이 채운다.
##   디펜스에서 「뒤로 민다」보다 값진 효과가 없고 물살이라는 결과도 맞는다.
## ★ **뚜껑이 반드시 있어야 한다**(RIDER_PUSH_MAX). 없으면 물 특효 여섯이 한 놈을
##   영원히 제자리에 붙들어 전투가 멎는다 — 마비에 재우는 시간을 둔 것과 정확히
##   같은 까닭이다(CLAUDE.md 5-4-2).
func _push(mi: int) -> void:
	if mi < 0 or mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	var used: float = float(mo.get("push", 0.0))
	if used >= Balance.RIDER_PUSH_MAX:
		return
	var d: float = minf(Balance.RIDER_PUSH, Balance.RIDER_PUSH_MAX - used)
	var remaining: float = float(mo.get("push_left", 0.0))
	# 아직 되돌리지 않은 거리도 빼야 입구 바깥으로 밀 힘을 쌓지 않는다.
	d = minf(d, maxf(0.0, float(mo["s"]) - remaining))
	if d <= 0.0:
		return
	mo["push"] = used + d
	mo["push_left"] = remaining + d
	# 동시 명중은 거리를 합치되 시간을 늘려 한 번의 밀림보다 빨라지지 않게 한다.
	mo["push_t"] = Balance.RIDER_PUSH_SEC * maxf(1.0, (remaining + d) / Balance.RIDER_PUSH)
	events.append({"t": "push", "p": _mp[mi] if mi < _mp.size() else mpos(mo),
		"h": float(mo["h"])})


## 남은 거리의 제곱 감쇠를 적분한다. 프레임 크기와 관계없이 같은 거리로 끝난다.
func _advance_push(mo: Dictionary, dt: float) -> float:
	var remaining: float = float(mo.get("push_left", 0.0))
	var duration: float = float(mo.get("push_t", 0.0))
	if remaining <= 0.0 or duration <= 0.0 or dt <= 0.0:
		return 0.0
	var next_t := maxf(0.0, duration - dt)
	var ratio := next_t / duration
	var next_distance := remaining * ratio * ratio
	mo["push_t"] = next_t
	mo["push_left"] = next_distance
	return remaining - next_distance


func _impact(b: Dictionary, mi: int) -> void:
	var kind := String(b["kind"])
	var dmg: float = float(b["dmg"])
	var spec: Dictionary = Balance.BULLET.get(kind, Balance.BULLET["shot"])
	var src: int = int(b["src"])
	var rad_mul: float = run.pas_mult("radius")
	var elem := String(b.get("el", "none"))
	var em: float = _hurt(mi, dmg, bool(b["crit"]), src, elem)
	# ★ **한 대의 세기**를 그대로 흘린다(상성까지 곱한 값). 화면이 그 숫자를 띄우는데,
	#   화면이 제 나름대로 다시 곱하면 표시와 전투가 언젠가 어긋난다.
	# ★ 남은 체력보다 큰 한 방이면 실제로 깎이는 것은 남은 만큼뿐이지만(_hurt), 숫자는
	#   **깎인 몫이 아니라 때린 세기**를 적는다 — 마지막 한 대만 「5」로 뜨면 제일 센
	#   한 방이 화면에서 제일 약해 보인다. 「이 탄의 몇 할을 깎았나」는 정보판이 따로 센다.
	events.append({"t": "hit", "p": b["p"], "c": b["c"], "kind": kind,
		"crit": bool(b["crit"]), "em": em, "el": elem, "n": dmg * em, "src": src})

	match kind:
		"splash":
			var at: Vector2 = _mp[mi] if mi < _mp.size() else Vector2(b["p"])
			var rad: float = float(spec["radius"]) * rad_mul
			_splash(mi, at, rad, dmg * float(spec["falloff"]), src, elem)
			# ★ 상성 배수를 같이 흘린다. 화면이 「약점이면 폭발도 크게」를 그리는 데 쓴다 —
			#   여기서 안 보내면 화면이 제 나름대로 다시 곱하게 되고 언젠가 어긋난다.
			# ★ **들어온 방향(d)** 도 같이 흘린다. 화면이 폭발을 그 쪽으로 쏠리게 그린다 —
			#   사방으로 고르게 터지면 어느 쪽에서 맞았는지가 화면에서 통째로 사라진다.
			events.append({"t": "splash", "p": at, "r": rad, "c": b["c"],
				"em": em, "el": elem, "d": Vector2(b["v"]).normalized(), "src": src})
		"chain":
			# 패시브 「뇌격 증폭」이 있으면 두 번 더 튄다.
			var jumps: int = int(spec["jumps"]) - 1
			if run.has("chainmaster"):
				jumps += Balance.PASSIVE_CHAIN_JUMPS
			_chain(mi, dmg * float(spec["decay"]), jumps,
					float(spec["decay"]), float(spec["hop"]), [mi], b["c"], src, elem, src)
	# ★ 예전에 여기 있던 "slow" · "burn" 갈래를 없앴다. 둔화·화상·마비는 이제 **방식이
	#   아니라 속성**이 붙이고, 붙이는 곳은 _hurt() 한 군데뿐이다 (CLAUDE.md 5-1 과 같은 뜻).

	# 패시브 「분열 탄두」 — 방식과 상관없이 모든 탄이 작게 터진다.
	var split: float = run.pas_best("split")
	if split > 0.0 and kind != "splash":
		var sat: Vector2 = _mp[mi] if mi < _mp.size() else Vector2(b["p"])
		var srad: float = split * rad_mul
		# 분열 조각은 **쏜 놈의 속성 그대로** 터진다. 패시브가 속성을 바꾸지는 않는다.
		_splash(mi, sat, srad, dmg * 0.35, src, elem)
		# ★ **분열 조각이라고 적어 둔다(split).** 이것은 방식과 상관없이 **모든 명중**마다
		#   터지므로 초당 수십 번이고, 반경 44 는 화면 흔들림의 문턱을 넘는다 — 적어 두지
		#   않으면 화면이 전투 내내 흔들린다. 여기서는 **적기만** 한다. 무엇을 덜 할지는
		#   화면이 정한다(시뮬레이터는 그리기를 모른다).
		events.append({"t": "splash", "p": sat, "r": srad, "c": b["c"],
			"em": em, "el": elem, "d": Vector2(b["v"]).normalized(), "split": true})
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
## ★ 속성을 안 받는다. 여기서 붙는 것은 패시브뿐이고 그것들은 **자기 속성이
##   정해져 있다** — 「연쇄 낙뢰」는 언제나 전기, 「화염 부적」은 언제나 불이다.
##   쏜 영웅의 속성을 받아 두면 언젠가 그것을 잘못 연결하게 된다.
func _on_hit_extras(mi: int, dmg: float, src: int) -> void:
	_field_extras(mi, dmg)
	# ★ 「연쇄 낙뢰」는 이름 그대로 **번개**다. 쏜 영웅의 속성이 아니라 늘 전기로 친다 —
	#   불 마법사가 지른 낙뢰가 불이 되면 상점 설명과 화면이 어긋난다.
	if run.has("bolt") and _rng.randf() < Balance.PASSIVE_BOLT_P:
		var bj: int = 2 + (Balance.PASSIVE_CHAIN_JUMPS if run.has("chainmaster") else 0)
		_chain(mi, dmg * 0.5, bj, 0.7, 150.0, [mi], Look.BLUE, src, "elec")


## 화상·서리처럼 **대상에게 남는** 효과만. 장판은 이쪽만 쓴다(연쇄는 따로 굴린다).
## ★ 패시브가 붙이는 것은 **자기 속성이 정해져 있다.** 「화염 부적」은 언제나 불이고
##   「서리 부적」·「서리 심」은 피해가 없어 속성을 안 탄다.
func _field_extras(mi: int, dmg: float) -> void:
	if run.has("flame"):
		_burn(mi, dmg * Balance.PASSIVE_FLAME_BURN, Balance.PASSIVE_FLAME_SEC, "fire")
	# 패시브 「서리 부적」 — 세기와 시간이 표(Balance.PASSIVES)에 적혀 있다.
	var ws: float = run.pas_best("slow")
	if ws > 0.0:
		_slow(mi, ws, maxf(0.5, run.pas_best("slow_sec")))


func _chain(from_i: int, dmg: float, jumps: int, decay: float, hop: float,
		seen: Array, col: Color, src: int, elem: String = "none", shot_src: int = -1) -> void:
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
	var cem: float = _hurt(best, dmg, false, src, elem)
	# Only native chain attacks carry their character's Shot artwork. Passive
	# lightning keeps the common effect without changing damage attribution.
	events.append({"t": "bolt", "a": at, "b": _mp[best], "c": col, "p": _mp[best],
		"em": cem, "n": dmg * cem, "el": elem, "shot_src": shot_src})
	seen.append(best)
	_chain(best, dmg * decay, jumps - 1, decay, hop, seen, col, src, elem, shot_src)


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
	var bem: float = Balance.elem_mult(elem, String(mo.get("body", "")))
	dps *= bem
	# ★ 0 피해짜리 화상을 붙이지 마라. 시간(burn_t)만 차서 **불꽃은 타는데 피는 안 깎이는**
	#   몬스터가 생긴다 — 화면이 거짓말을 하는 자리다.
	if dps <= 0.0:
		return
	# ★ **누가 붙인 불인가**를 같이 적는다. 화상 도트는 `_hurt` 를 안 거치므로, 이것이
	#   없으면 그 피해가 아무에게도 안 세어진다 — 불 영웅만 막대가 짧아진다.
	# ★ 배수는 「무엇 때문에 이만큼인가」다. 부른 쪽이 상성을 이미 곱해 넘겼으면
	#   (elem == "none" — `_apply_rider` 가 그렇다) 그때의 배수를 물려받고, 제 속성으로
	#   붙는 것이면(패시브 「화염 부적」) 그 속성의 배수를 쓴다.
	# ★ **센 쪽으로 덮어쓰므로**(CLAUDE.md 15번) 임자도 이긴 쪽을 따라간다.
	if float(mo["burn_t"]) <= 0.0 or dps >= float(mo["burn"]):
		mo["burn_src"] = _atk_src
		mo["burn_em"] = _atk_em if elem == "none" else bem
	mo["burn"] = dps if float(mo["burn_t"]) <= 0.0 else max(float(mo["burn"]), dps)
	mo["burn_t"] = max(float(mo["burn_t"]), sec)


## 몬스터 하나를 때린다. **피가 깎이는 곳은 여기 한 군데뿐이다** — 상성 배수도
## 그래서 여기서만 곱한다. 광역·연쇄·장판·분열이 저마다 곱하기 시작하면
## "광역은 상성을 타는데 연쇄는 안 타는" 식으로 조용히 갈라진다.
##
## 돌려주는 것: **실제로 적용된 상성 배수.** 화면이 「약점!」을 띄우는 데 쓴다 —
## 화면이 같은 계산을 다시 하면 전투와 표시가 언젠가 어긋난다.
## ★ `rider_dmg` — 상태이상의 **밑값**을 피해와 따로 줄 수 있게 해 둔다. 기본은 피해 그대로다.
##   장판만 이것이 필요하다: 장판은 매 프레임 `dps * dt` 만큼 때리지만 상태이상은
##   **0.25초 틱에만** 붙이므로, 붙일 때의 밑값은 `dps * 0.25`(=한 틱 몫)여야 한다.
##   안 그러면 불 장판의 화상이 프레임 간격에 비례해 달라진다 — 실측으로 잡힌 결함이다:
##   dt=1/30 에서 0.385, dt=1/60 에서 0.193, dt=0.02 에서 0.231 로 **정확히 dt 에 비례**했고
##   의도한 값(1.445)의 12분의 1이었다. 바로 옆줄의 패시브 화상(`_field_extras(mi, dps*0.25)`)은
##   틱 몫을 쓰고 있어서, **같은 틱에 패시브 화상만 제대로 붙는** 어긋남이었다.
##   ★ 이것 때문에 `tests/balance_check`(DT=1/30)가 재는 불 장판 화력이 실기(0.02)와
##     달랐다 — 「화면보다 굵게 돌려도 결과는 같아야 한다」가 깨져 있었다.
## ★ `flash` — **붉게 번쩍이게 할 것인가.** 장판만 이것이 필요하다: 장판은 살아 있는
##   모두를 **매 프레임** 때리므로 flash 가 1.0 에 못 박히고, 그러면 장판에 든 몬스터는
##   내내 벌겋게 눌린 채로 서 있는다. 「방금 맞았다」가 늘 켜져 있으면 그 신호는 뜻을
##   잃고, **다른 영웅이 때린 것도 안 보이게 된다.** 그래서 장판은 0.25초 틱에만
##   번쩍이게 하고 나머지 프레임은 조용히 깎기만 한다.
##   (면역이면 그 위에서 이미 돌아가므로 여기까지 안 온다 — CLAUDE.md 5-6)
func _hurt(mi: int, dmg: float, _crit: bool, _src: int, elem: String = "none",
		rider: bool = true, rider_dmg: float = -1.0, rider_n: int = 1,
		flash: bool = true) -> float:
	if mi < 0 or mi >= monsters.size():
		return 1.0
	var mo: Dictionary = monsters[mi]
	var body := String(mo.get("body", ""))
	var em: float = Balance.elem_mult(elem, body)
	# 패시브 「상극 파훼」 — **저항만** 무디게 한다. 면역(0배)은 건드리지 않는다:
	# 나무의 전기 저항은 완화하지만 바위의 면역은 그대로 유지한다.
	if em > 0.0 and em < 1.0 and run.has("antibody"):
		em = maxf(em, Balance.PASSIVE_ANTIBODY)
	# 지금 때리고 있는 놈. **화상 도트를 누구 몫으로 셀지**가 여기서 정해진다
	# (_burn 이 붙는 순간에 읽는다). 면역으로 돌아 나가더라도 갈아 끼워 둔다 —
	# 아무 일도 안 일어나므로 화상도 안 붙기 때문이다.
	_atk_src = _src
	_atk_em = em
	# ★ 속성마다의 기본 화력(ELEM 의 dmg)은 여기서 곱하지 **않는다** — Run.hero_stats 가
	#   이미 공격력에 곱해 뒀다. 여기서 또 곱하면 물이 두 번 세진다.
	dmg *= em
	# ★ **면역이면 아무 일도 일어나지 않아야 한다.** 예전 코드는 배수가 0 이어도 붉게
	#   번쩍이고 치명타 숫자를 띄웠다 — 한 톨도 안 들어갔는데 화면은 "잘 때리고 있다"고
	#   말하는 셈이다. 그러면 플레이어는 왜 안 죽는지 영영 모른다.
	if em <= 0.0:
		return em
	# 패시브 둘 — 상성 배수와 **따로** 곱한다. em 은 화면이 「약점/저항」을 그리는 데
	# 쓰는 값이라, 여기에 섞으면 약점도 아닌데 약점처럼 그려진다.
	if run.has("giantslay") and String(mo["kind"]) == "boss":
		dmg *= Balance.PASSIVE_GIANT
	if run.has("overkill") \
			and float(mo["hp"]) <= float(mo["max"]) * Balance.PASSIVE_OVERKILL_AT:
		dmg *= Balance.PASSIVE_OVERKILL
	# ★ **남은 체력까지만 깎는다.** 예전에는 hp 가 음수로 내려가고 넘겨 죽인 몫이 그대로
	#   「준 피해」에 쌓였다. 두 가지가 그래서 부풀었다:
	#     1. 한 방에 열 배로 넘겨 죽인 영웅이 열 배로 일한 것처럼 보였다.
	#     2. `_reap()` 은 걸음 **끝에** 한 번 도는데, 그 사이에 이미 쓰러진 놈을 때린
	#        탄·광역·장판이 전부 셈에 들어갔다(장판은 매 프레임 판 위의 전부를 때린다).
	#   오른쪽 정보판이 「이번 탄 전체 체력」을 자로 쓰게 된 지금은 그 부풀림이 곧
	#   **자를 넘는 막대**다. 지금은 셋이 정확히 같다:
	#     깎인 체력 == 영웅에게 쌓인 피해 == 화면이 그리는 막대.
	var got: float = minf(dmg, maxf(0.0, float(mo["hp"])))
	if got <= 0.0:
		# 이미 쓰러진 놈이다(같은 걸음에 앞엣 것이 눕혔다). 아무 일도 일어나면 안 된다 —
		# 번쩍이지도, 얼지도, 처치를 가져가지도 않는다. 면역과 같은 규칙이다(CLAUDE.md 5-6).
		return em
	mo["hp"] = float(mo["hp"]) - got
	if flash:
		mo["flash"] = 1.0
	# ★ 누가 얼마나 때렸는가. 라운드 끝의 전과 판이 이 값으로 그려진다.
	#   마지막으로 때린 놈이 처치를 가져간다 — 「막타」가 가장 눈에 보이는 셈이다.
	_credit(_src, got, em)
	if _src >= 0 and _src < heroes.size():
		mo["src"] = _src
	# ★ 예전에 있던 「crit」 사건을 없앴다. 「hit」 사건이 이미 crit 를 들고 다니므로,
	#   둘 다 두면 치명타 한 대에 숫자가 **두 개** 뜬다.
	# ★ **상태이상도 여기서만 붙인다.** 상성 배수와 같은 이유다 — 광역·연쇄·분열이
	#   저마다 붙이기 시작하면 "광역은 얼리는데 연쇄는 안 어는" 식으로 조용히 갈라진다.
	# ★ 면역(0배)이면 아무것도 안 붙는다. 아예 안 통하는 공격이 몬스터를 마비시키면
	#   플레이어는 "전기가 나무·바위에 안 통한다"를 영영 못 배운다.
	if rider:
		# 상태이상 밑값도 상성을 탄 뒤의 값이어야 한다 — 약점 화상이 두 배로 타는 것이 맞다.
		var rd: float = dmg if rider_dmg < 0.0 else rider_dmg * em
		# ★ **「특효」 역할은 상태이상의 세기를 키운다.** 무엇을 거는가는 그대로 속성이
		#   정한다(CLAUDE.md 5-4-1) — 얼음이면 여전히 둔화이고 불이면 여전히 화상이다.
		#   바뀌는 것은 세기와 시간뿐이라, 「화면을 보고 규칙을 배운다」가 안 깨진다.
		var rmul: float = 1.0
		if _src >= 0 and _src < heroes.size():
			rmul = Balance.rider_mult(String(heroes[_src].get("role", "single")))
		# ★ 겹친 장판은 그 수만큼 **따로 굴린다.** 탄이 있는 방식은 발마다 한 번씩
		#   부르므로 여기 rider_n 은 언제나 1 이다.
		for _i in range(maxi(1, rider_n)):
			_apply_rider(mi, elem, rd, rmul)
		# ★ 물 특효만의 효과 — **뒤로 민다.** 물에는 상태이상이 없어서 위의 고리가
		#   아무 일도 안 하기 때문이다(무상성 특효는 몬스터에게 아무것도 안 붙이고
		#   대신 쏘는 쪽의 치명타가 오른다 — Run.hero_stats).
		if rmul > 1.0 and elem == "water":
			_push(mi)
	return em


## **누가 얼마나 깎았는가**를 그 영웅에게 쌓는다. 합계와 상성별 세 통을 **같은 한 줄**에서
## 올리므로 `dmg == dw + dn + dr` 이 저절로 성립한다 (tests/ns_check._check_dmg_split).
##
## ★ 부르는 곳은 **둘뿐**이다 — `_hurt()` 와, `_hurt` 를 안 거치는 유일한 예외인
##   화상 도트(`_move_monsters`). 셋째 자리를 만들지 마라: 세 통과 합계가 서로 다른
##   이야기를 하기 시작하면 그 어긋남은 아무도 못 잡는다(CLAUDE.md 10-8-1).
## ★ 면역(0배)은 여기까지 안 온다 — `_hurt` 가 그 위에서 돌아 나간다.
func _credit(src: int, dmg: float, em: float) -> void:
	if src < 0 or src >= heroes.size() or dmg <= 0.0:
		return
	var sh: Dictionary = heroes[src]
	sh["dmg"] = float(sh["dmg"]) + dmg
	if run != null and run.has_method("record_hero_damage"):
		run.record_hero_damage(sh["h"], dmg)
	# ★ 여기 dmg 는 em 을 **이미 곱한** 값이라, 세 통에 담기는 것은 「실제로 몬스터가
	#   받은 피해」다 — 정보판의 세 막대가 그대로 이것이다.
	if em > 1.001:
		sh["dw"] = float(sh["dw"]) + dmg
	elif em < 0.999:
		sh["dr"] = float(sh["dr"]) + dmg
	else:
		sh["dn"] = float(sh["dn"]) + dmg


## 그 속성이 늘 붙이는 것. 얼음=둔화 · 불=화상 · 전기=확률 마비 · 물/무=없음.
##
## ★ 표를 Balance.STATUS 한 곳에만 두는 이유: 상점 설명("얼음은 느리게 만든다")과
##   실제 전투가 같은 숫자를 봐야 한다. 여기에 값을 적으면 반드시 어긋난다.
## ★ `mult` — 「특효」 역할이 키우는 세기 배수(Balance.RIDER_MULT). 1.0 이면 보통이다.
func _apply_rider(mi: int, elem: String, dmg: float, mult: float = 1.0) -> void:
	match Balance.elem_rider(elem):
		"slow":
			var sp: Dictionary = Balance.STATUS["slow"]
			# ★ 세기에 뚜껑을 씌운다. 1.0 이 되면 그것은 둔화가 아니라 **완전 정지**이고,
			#   마비와 달리 재우는 시간이 없어서 얼음 특효 여섯이 길을 통째로 막는다
			#   (CLAUDE.md 5-4-2 와 같은 까닭). 시간은 그대로 곱한다.
			_slow(mi, minf(0.80, float(sp["amount"]) * mult), float(sp["sec"]) * mult)
		"burn":
			var bp: Dictionary = Balance.STATUS["burn"]
			# ★ 상성은 이미 dmg 에 곱해져 있다. _burn() 이 또 곱하지 않게 "none" 으로 넘긴다 —
			#   두 번 곱하면 약점 화상이 네 배가 된다.
			_burn(mi, dmg * float(bp["amount"]) * mult, float(bp["sec"]) * mult, "none")
		"stun":
			_stun(mi, mult)


## 전기가 굴리는 마비. **확률**이고, 보스에게는 확률이 깎인다.
##
## ★ 왜 확률인가 (사용자의 규칙: 「특정확률로 마비」): 마비는 완전 정지라 늘 걸리면
##   연사 영웅 하나가 길을 통째로 막아 전투가 멎는다. 확률이면 **떼거리를 흩뜨리는**
##   효과가 되어 앞뒤가 벌어지고, 그게 눈으로도 재미있다.
## ★ 보스를 깎는 까닭: 보스는 혼자라 광역·장판의 몫을 못 받는다. 그런 보스가 계속
##   서 있으면 보스탄이 제일 쉬운 탄이 되어 버린다(CLAUDE.md 17번과 같은 함정).
func _stun(mi: int, mult: float = 1.0) -> void:
	if mi >= monsters.size():
		return
	var mo: Dictionary = monsters[mi]
	# 이미 마비 중이거나, 막 풀려 재우는 중이면 안 건다.
	if float(mo["stun_t"]) > 0.0 or float(mo["stun_cd"]) > 0.0:
		return
	var sp: Dictionary = Balance.STATUS["stun"]
	# ★ 「특효」가 확률을 키운다. 뚜껑을 씌우는 까닭은 위(둔화)와 같다 — 확률이 1.0 이
	#   되면 재우는 시간이 있어도 전기 특효 여섯이 길을 사실상 멈춰 세운다.
	var p: float = minf(0.55, float(sp["chance"]) * mult)
	if String(mo["kind"]) == "boss":
		p *= Balance.BOSS_STUN_MUL
	if _rng.randf() >= p:
		return
	mo["stun_t"] = float(sp["sec"])
	events.append({"t": "stun", "p": _mp[mi] if mi < _mp.size() else mpos(mo),
		"h": float(mo["h"])})


## 영웅 발판과 몬스터 중심으로 사거리를 판정한다. 가장 가까운 유효 대상만 고른다.
## 발사된 탄·도탄·연쇄·광역의 후속 피해는 각 공격의 고유 반경과 수명을 따른다.
## ★ 자리는 캐시(_pos_of)에서 읽는다. 겨냥은 영웅 열둘이 걸음마다 부르는데, 매번 길
##   위의 좌표를 다시 재면 몬스터 일흔 마리 × 열둘이 한 걸음에 쌓인다(CLAUDE.md 12).
func _target_in_range(index: int, origin: Vector2, radius: float) -> bool:
	return index >= 0 and index < monsters.size() and float(monsters[index]["hp"]) > 0.0 \
			and origin.distance_squared_to(_pos_of(index)) <= radius * radius


func _nearest_target(origin: Vector2, radius: float = INF) -> int:
	var best := -1
	var distance := INF
	for i in range(monsters.size()):
		if not _target_in_range(i, origin, radius):
			continue
		var candidate := origin.distance_squared_to(_pos_of(i))
		if candidate < distance:
			distance = candidate
			best = i
	return best


func _nearest_targets(origin: Vector2, count: int, radius: float = INF) -> Array:
	var targets: Array = []
	for i in range(monsters.size()):
		if _target_in_range(i, origin, radius):
			targets.append(i)
	targets.sort_custom(func(a, b):
		return origin.distance_squared_to(_pos_of(a)) < origin.distance_squared_to(_pos_of(b)))
	return targets.slice(0, count)


func _front_target() -> int:
	var best := -1
	var best_s := -1.0
	for i in range(monsters.size()):
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
		var g: int = int(round(float(mo["gold"]) * Balance.gold_mult(run.lv("gold"))
				* run.pas_mult("gold")))
		gold += g
		kills += 1
		# 막타를 넣은 영웅이 처치를 가져간다. 라운드 끝의 전과 판이 이 값을 쓴다.
		# ★ 막타가 없으면 **붙은 불의 임자**가 가져간다. 들불(패시브)이 옮겨 붙인 불로만
		#   죽은 놈은 `_hurt` 를 한 번도 안 거쳐서 `src` 가 비어 있다 — 그대로 두면 그
		#   처치가 아무에게도 안 세어져서 전과판의 「몇 마리」가 조용히 모자란다.
		var ks: int = int(mo.get("src", -1))
		if ks < 0:
			ks = int(mo.get("burn_src", -1))
		if ks >= 0 and ks < heroes.size():
			heroes[ks]["kills"] = int(heroes[ks]["kills"]) + 1
		# 패시브 「과열」 — 잡을 때마다 공격속도가 쌓이고, 3초 안에 또 못 잡으면 식는다.
		if run.has("surge"):
			surge = minf(Balance.PASSIVE_SURGE_MAX, surge + Balance.PASSIVE_SURGE_STEP)
			surge_t = Balance.PASSIVE_SURGE_SEC
		# 패시브 「들불」 — 타는 채로 죽으면 둘레에 불이 옮아 붙는다.
		# ★ 새 화상을 **곱하지 않고 옮긴다.** 죽을 때마다 세기가 불어나면 떼거리 한가운데에서
		#   불이 스스로 커져서, 한 번 붙은 불이 그 탄을 통째로 태운다.
		if run.has("wildfire") and float(mo["burn_t"]) > 0.0:
			# 옮아 붙는 불의 임자는 **그 불을 붙인 영웅**이다(막타가 아니다 — 옮아 가는
			# 것은 불이지 마지막 한 대가 아니다). 안 적어 두면 들불이 깎는 체력이
			# 아무에게도 안 세어진다(_burn 이 _atk_src 를 읽는다).
			# ★ 들불이 들불로 옮은 자리에서 특히 중요하다 — 그 놈은 `_hurt` 를 한 번도
			#   안 거쳐서 `src` 가 비어 있고, `src` 만 보면 사슬 두 번째부터 임자가 없다.
			_atk_src = int(mo.get("burn_src", -1))
			if _atk_src < 0:
				_atk_src = int(mo.get("src", -1))
			_atk_em = 1.0
			var spread: float = float(mo["burn"]) * Balance.PASSIVE_WILDFIRE
			var r2: float = Balance.PASSIVE_WILDFIRE_R * Balance.PASSIVE_WILDFIRE_R
			for j in range(_mp.size()):
				if j == i or float(monsters[j]["hp"]) <= 0.0:
					continue
				if dp.distance_squared_to(_mp[j]) <= r2:
					_burn(j, spread, Balance.PASSIVE_FLAME_SEC, "none")
			events.append({"t": "wildfire", "p": dp, "r": Balance.PASSIVE_WILDFIRE_R})
		# ★ 여기서 바로 올린다. 화면이 전투가 끝난 뒤에 한꺼번에 더하게 두면,
		#   크리스탈이 0 이 되어 판이 **전투 도중** 끝날 때 그 판의 처치 수가
		#   저장 기록에 영영 안 들어간다(end_run 이 그 전에 불린다).
		run.kills += 1
		run.add_gold(g)
		events.append({"t": "die", "p": dp, "c": Color(String(mo["m"]["color"])),
			"h": float(mo["h"]), "gold": g})

	for i in arrived:
		var mo2: Dictionary = monsters[i]
		var ap: Vector2 = _mp[i] if i < _mp.size() else mpos(mo2)
		# ★ **남아 있는 크리스탈까지만** 깨진 것으로 센다. 예전에는 최소 1 로 잘랐는데,
		#   같은 걸음에 앞엣놈이 이미 0 으로 만들어 놓으면 없는 크리스탈이 깨진 것으로
		#   집계되어 결과창이 "크리스탈이 6개인데 9개가 깨졌다"고 적었다.
		var crush: int = mini(int(mo2["crush"]), maxi(0, run.lives))
		# 패시브 「수정 방벽」 — 닿아도 이 확률로 하나도 안 깨진다.
		# ★ 개수를 깎지 않고 **통째로 막는다.** 다섯을 부수는 보스에게 「하나만 덜 깨진다」는
		#   보이지도 않는 효과다 — 막느냐 못 막느냐로 두어야 손에 잡힌다.
		if crush > 0 and run.has("bulwark") and _rng.randf() < Balance.PASSIVE_BULWARK_P:
			leak_n += 1
			events.append({"t": "block", "p": ap, "h": float(mo2["h"])})
			continue
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
