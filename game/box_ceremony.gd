extends RefCounted
## 보석상자 의식 (F10/F11) — 상자가 떨어져 제 등급까지 한 단씩 오르고, 이음새로 빛이 새다
## 뚜껑이 터지고, 카드 다섯 장이 아치로 날아가 앉고, 낮은 카드부터 뒤집혀 가장 좋은 카드가
## 마지막에 모아 둔 빛과 함께 열리고, 고른 영웅이 떠올라 결과가 된다.
##
## ★ 그리기만 한다. 상자 등급·카드는 받은 그대로(Arena.box_tier · box_cards · card_preview)이고
##   시계도 받은 그대로다(화면의 box_deal_age · box_pick_age). 같은 시각이면 같은 그림이다 —
##   촬영·건너뛰기·저장 복원이 같은 함수를 지난다. 상태를 갖는 것은 작은 입자뿐이고(풀 CAP 개,
##   프레임마다 노드·텍스처를 새로 만들지 않는다), 큰 연출(빛기둥·빛살·고리·섬광·흔들림)은
##   시각의 함수다.
## ★ 화면의 캔버스 하나에 그린다(새 노드 · 캔버스 아이템 없음 — 화면 규칙). draw_all() 의 순서:
##   무대(그늘 · 상자 · 카드) → 빛(빛살 · 고리 · 입자 — 어두운 그늘 위라 보통 섞기로 빛처럼 보이게
##   색과 알파를 골랐다) → 단추 · 안내 · 결과 → 화면 섬광.
## ★ 등급은 별의 수가 먼저다(카드 별 줄 · 상자 아래 별 줄 · 「3성 상자」). 색은 그다음이다.
## 기록·결정: build/feedback-2026-10-19/D1/RECORD.md

const Layout := preload("res://art/ui/box/box_layout.gd")

const SCREEN := Rect2(0, 0, 1280, 800)
## 상자 밑동(앵커)의 자리와 배율 — 무대 가운데 / 카드가 펼쳐진 뒤의 머리 자리.
const STAGE := Vector2(640, 548)
const STAGE_SCALE := 0.76
const HEAD := Vector2(640, 214)
const HEAD_SCALE := 0.25
const CARD := Vector2(196, 320)
const CARD_GAP := 22.0
const CARD_Y := 404.0
const PICK_H := 44.0
const REROLL := Rect2(440, 650, 400, 60)
## 4성부터 카드를 붙들고 빛을 모은 뒤에 뒤집는다(Balance.SHOWY_TIER = 7 = 4성).
const SHOWY := 4
## 한 장면의 입자 상한. 넘치면 가장 오래된 것부터 덮어쓴다(5성 개봉 + 5성 카드가 최대 ~300).
const CAP := 420
const FLIP := 0.26
## 카드가 정착한 뒤 고르기 · 다시 뽑기가 듣기까지(무장). 건너뛰기로 연타하던 손가락이 그대로 카드를
## 고르지 않게(F1 과 같은 실패) — 정착(건너뛰기 착지) 뒤 이만큼, 단추 테두리가 채워지는 동안은 꺼져 있다.
const ARM := 0.7
## 고른 뒤: 결과가 다 들어와 「확인」을 받는 시각.
const RESULT_READY := 1.15
const RESULT_CARD := Vector2(376, 410)
const RESULT_SCALE := 1.32
const PINK := Color("#ff7ac0")

# --------------------------------------------------------------------------- #
# 받은 것
# --------------------------------------------------------------------------- #
var tier := 1
## [{unit: Dictionary, stars: int, guaranteed: bool, preview: Dictionary}] — preview 는
## Arena.card_preview(i) 의 모양 {kind, before_tier, after_tier, added_points, maxed, where}.
var cards: Array = []
## 반복 상자는 같은 박자를 짧게 친다(첫 상자만 온전한 의식).
var fast := false
## 다시 뽑기 단추: 남은 무료 횟수(Arena.respins_left)와 누를 수 있는지(Arena.can_respin).
var free_rerolls := 0
var can_reroll := false
## 스테이지의 첫 상자(무료)인가 — 무대의 등급판 밑에 「첫 상자 무료」.
var free_box := false
## 대공 공정 규칙이 이 상자에 걸렸는가 — 머리의 「대공 보장」.
var anti_air := false
## 면역 공정 규칙이 걸린 몸(파티 누구도 못 때리는 땅 위의 몸, 카드 중 하나가 때린다) — 머리의 「면역 대응 보장」.
var immune_body := ""
## 고른 뒤의 결과(Arena.summon_result 모양 + growth_needed). picked < 0 이면 아직.
var picked := -1
var result: Dictionary = {}

var start_tier := 1
var rerolled := false
var old_cards: Array = []
var old_tier := 1
var plan: Dictionary = {}
var cues: Array = []
var _last_age := 0.0
var _last_pick := -1.0
var _flourish := false
var _skip_at := -9.0
var _sig := ""
var _serial := 0
## 미리 읽어 둘 그림(상자 층 · 초상화). 처음 쓰이는 프레임에 디스크를 읽으면 그 프레임이 100ms 넘게
## 끊긴다(1280×800 실측 127ms) — 카드가 뒤집히는 순간이 바로 그 프레임이다. 상자가 떨어지는 동안
## 프레임마다 두 장씩 읽는다.
var _warm: Array = []

# 입자 풀 — 위치·속도·수명·크기·회전·색·종류를 고정 길이 배열에 둔다.
enum P { SPARK, STAR, EMBER, SHARD, COIN, SPLINTER, DUST, STREAK }
const P_LIGHT := [true, true, true, false, false, false, false, true]
var _pp := PackedVector2Array()
var _pv := PackedVector2Array()
var _pl := PackedFloat32Array()
var _pm := PackedFloat32Array()
var _ps := PackedFloat32Array()
var _pr := PackedFloat32Array()
var _pw := PackedFloat32Array()
var _pg := PackedFloat32Array()
var _pd := PackedFloat32Array()
var _pc := PackedColorArray()
var _pk := PackedInt32Array()
var _pn := 0
var _rng := RandomNumberGenerator.new()

static var _tex: Dictionary = {}
static var _glow: Texture2D = null
static var _card_outer := PackedVector2Array()
static var _card_inner: Dictionary = {}


func _init() -> void:
	_pp.resize(CAP)
	_pv.resize(CAP)
	_pl.resize(CAP)
	_pm.resize(CAP)
	_ps.resize(CAP)
	_pr.resize(CAP)
	_pw.resize(CAP)
	_pg.resize(CAP)
	_pd.resize(CAP)
	_pc.resize(CAP)
	_pk.resize(CAP)
	_pl.fill(0.0)
	_rng.seed = 20261019


# --------------------------------------------------------------------------- #
# 화면이 부르는 것
# --------------------------------------------------------------------------- #
## 새 상자. 등급은 1성 상자로 들어와 제 등급까지 오른다.
func begin(box_tier: int, box_cards: Array, quick: bool) -> void:
	tier = clampi(box_tier, 1, 5)
	cards = box_cards.duplicate()
	# 4성 이상 상자는 반복 상자라도 온전한 의식을 받는다(드물고, 그 순간이 보상이다).
	fast = quick and tier < SHOWY
	start_tier = 1
	rerolled = false
	old_cards.clear()
	picked = -1
	result = {}
	_flourish = false
	_skip_at = -9.0
	_last_age = 0.0
	_last_pick = -1.0
	_sig = _signature(tier, cards)
	_pl.fill(0.0)
	_make_plan()
	_queue_warm()


## 다시 뽑기. 지금 카드는 상자로 접혀 돌아가고, 상자는 무대로 내려와 새 등급까지 오른다
## (내려가지 않는다), 다시 열려 새 다섯 장을 짧게 나눈다.
func begin_reroll(box_tier: int, box_cards: Array) -> void:
	old_cards = cards.duplicate()
	old_tier = tier
	tier = clampi(maxi(box_tier, old_tier), 1, 5)
	cards = box_cards.duplicate()
	start_tier = old_tier
	rerolled = true
	fast = true
	picked = -1
	result = {}
	_flourish = false
	_skip_at = -9.0
	_last_age = 0.0
	_sig = _signature(tier, cards)
	_make_plan()
	_queue_warm()


## 첫 프레임에 쓸 층은 바로, 나머지는 쓰일 차례대로 줄을 세운다.
func _queue_warm() -> void:
	_warm.clear()
	box_tex(start_tier, "body")
	box_tex(start_tier, _lid_layer(0.0))
	if rerolled:
		box_tex(start_tier, "lid_100")
	for g in range(start_tier + 1, tier + 1):
		_warm.append(["box", g, "body"])
		_warm.append(["box", g, "lid_000"])
	for layer in ["seam", "lid_006", "lid_018", "lid_040", "lid_070", "lid_100", "lid_118"]:
		_warm.append(["box", tier, layer])
	for card in cards:
		var unit: Dictionary = (card as Dictionary).get("unit", {})
		_warm.append(["unit", unit, clampi(int((card as Dictionary).get("stars", 1)), 1, 5) * 2 - 1])
	# 글자도 처음 그리는 프레임에 글리프를 만든다(정착 순간 96ms 실측) — 미리 재어 둔다.
	var words: Array = [I18n.t("arena.box_tier") % tier, I18n.t("arena.box_guarantee") % tier, I18n.t("arena.box_hint"),
		I18n.t("arena.box_pick"), I18n.t("arena.box_reroll"), I18n.t("arena.box_free_n") % free_rerolls, I18n.t("arena.box_new"),
		I18n.t("arena.box_maxed"), I18n.t("arena.box_air"), I18n.t("arena.box_free"),
		"상자 등급은 내려가지 않지만 카드 %d장은 새로 뽑습니다." % cards.size(), "보장", "화면을 누르면 건너뜁니다.", "강화", "MAX",
		"면역 대응 보장"]
	for card in cards:
		var unit: Dictionary = (card as Dictionary).get("unit", {})
		words.append(Look.unit_name(unit))
		for label in SummonArt.trait_labels(unit):
			words.append(String(label))
		var pv: Dictionary = (card as Dictionary).get("preview", {})
		words.append(I18n.t("arena.box_growth") % int(pv.get("added_points", 0)))
	for w in words:
		_warm.append(["text", String(w)])


func _warm_step(n: int) -> void:
	while n > 0 and not _warm.is_empty():
		var item: Array = _warm.pop_front()
		match String(item[0]):
			"box":
				box_tex(int(item[1]), String(item[2]))
			"unit":
				Art.unit_preview(item[1], int(item[2]))
			_:
				Look.text_width(String(item[1]), 22)
		n -= 1


## 고르기. result 는 Arena.summon_result 모양(+ growth_needed) — 없으면 카드의 미리보기로 채운다.
func begin_pick(index: int, picked_result: Dictionary) -> void:
	picked = clampi(index, 0, maxi(0, cards.size() - 1))
	result = picked_result.duplicate()
	_last_pick = -1.0


## 화면이 매 프레임 넘겨도 되는 한 줄 — 상자가 바뀌었으면(새로 열림 · 다시 뽑기) 알아서 시작한다.
## `serial` 은 다시 뽑기 횟수(Arena.spins) — 같은 카드가 다시 나와도 다시 뽑기로 읽는다.
func sync(box_tier: int, box_cards: Array, quick: bool, serial: int = 0) -> void:
	var sig := "%d|%s" % [serial, _signature(box_tier, box_cards)]
	if sig == _sig:
		return
	var reroll := not cards.is_empty() and not box_cards.is_empty() and serial > _serial
	_serial = serial
	if reroll:
		begin_reroll(box_tier, box_cards)
	else:
		begin(box_tier, box_cards, quick)
	_sig = sig


## 입력이 열리는 시각(나눔 시계). 그 전에는 화면 전체가 「건너뛰기」 자리다.
func settle_time() -> float:
	return float(plan.get("ready", 0.0))


func is_ready(age: float, pick_age: float) -> bool:
	if pick_age >= 0.0:
		return pick_age >= RESULT_READY
	return age >= settle_time()


## 건너뛰기: 화면은 나눔 시계를 이 값으로 옮긴다. 남은 카드는 한 번에 열리고, 그중 4성 이상은
## 짧게라도 제 등급의 터짐을 보여 준다(드문 순간을 건너뛰기가 지우지 않게).
func skip_target(age: float) -> float:
	var settle := float(plan.get("settle", 0.0))
	if age >= settle:
		return age
	_flourish = true
	_skip_at = settle - 0.02
	return settle - 0.02


# --------------------------------------------------------------------------- #
# 박자표 — 시각이 정해지면 모든 그림이 그 시각에서 읽힌다
# --------------------------------------------------------------------------- #
func _k(full: float, quick: float) -> float:
	return quick if fast else full


func _stars(i: int) -> int:
	if i < 0 or i >= cards.size():
		return 1
	return clampi(int((cards[i] as Dictionary).get("stars", 1)), 1, 5)


static func _deal_order(n: int) -> Array:
	var order: Array = []
	var mid := (n - 1) / 2
	order.append(mid)
	for step in range(1, n):
		var left := mid - step
		var right := mid + step
		if left >= 0:
			order.append(left)
		if right < n:
			order.append(right)
		if order.size() >= n:
			break
	return order.slice(0, n)


func _make_plan() -> void:
	var p: Dictionary = {}
	var c: Array = []
	var t := 0.0
	if rerolled:
		var n_old := old_cards.size()
		var fold: Dictionary = {}
		var outside: Array = _deal_order(n_old)
		outside.reverse()
		for k in range(outside.size()):
			fold[outside[k]] = 0.045 * k
		p["fold"] = fold
		var fold_end := 0.045 * maxi(0, n_old - 1) + 0.44
		c.append([0.0, "sfx", "card_collect", -3.0])
		p["slam"] = fold_end
		c.append([fold_end + 0.07, "slam", 0, 0])
		p["ret0"] = fold_end + 0.11
		p["ret1"] = float(p["ret0"]) + 0.34
		c.append([float(p["ret1"]), "land", 1, 0])
		t = float(p["ret1"]) + 0.12
	else:
		p["land"] = _k(0.30, 0.24)
		c.append([float(p["land"]), "land", 0, 0])
		t = _k(0.64, 0.46)
	# 등급 오르기: 상자가 한 단씩 제 등급을 보여 준다. 흰 빛이 가득한 순간에 그림을 바꾼다.
	# 단이 거듭될수록 빨라진다(북소리가 몰아치듯) — 5성 상자의 네 단도 1.2초 안에.
	var step := _k(0.36, 0.28)
	var steps := maxi(0, tier - start_tier)
	var steps_t: Array = []
	var steps_d: Array = []
	p["climb0"] = t
	p["step"] = step
	p["steps"] = steps
	for j in range(steps):
		var dj := step * maxf(0.62, 1.0 - 0.1 * j)
		steps_t.append(t)
		steps_d.append(dj)
		c.append([t + dj * 0.43, "grade", start_tier + j + 1, 0])
		t += dj
	p["steps_t"] = steps_t
	p["steps_d"] = steps_d
	if steps == 0 and rerolled:
		p["same"] = t
		c.append([t + 0.06, "same", 0, 0])
		t += 0.30
	if steps > 0 and tier >= SHOWY:
		p["grand"] = t
		c.append([t, "grand", tier, 0])
		t += _k(0.30, 0.20) if tier == 4 else _k(0.46, 0.32)
	p["climb1"] = t
	# 예비 동작: 세 번 들썩이며 이음새로 빛이 새고, 웅크렸다 터진다. 충전음의 꼭대기(0.70초)가
	# 터지는 순간에 오도록 먼저 튼다.
	t += _k(0.10, 0.06)
	var antic := 0.42 if rerolled else _k(0.68, 0.44)
	p["antic0"] = t
	p["antic"] = antic
	c.append([t + antic - 0.70, "sfx", "summon_charge", -1.0])
	for r in range(3):
		c.append([t + antic * [0.0, 0.32, 0.58][r], "rattle", r, 0])
	t += antic
	p["burst"] = t
	c.append([t, "burst", tier, 0])
	# 나눔: 가운데부터 바깥으로. 카드는 상자 입에서 아치를 그려 제자리에 앉는다.
	var n := cards.size()
	var order := _deal_order(n)
	var gap := _k(0.06, 0.045)
	var flight := _k(0.40, 0.32)
	var deal0 := t + _k(0.14, 0.09)
	p["deal0"] = deal0
	p["move0"] = t + 0.10
	p["move1"] = float(p["move0"]) + _k(0.52, 0.40)
	var launch: Dictionary = {}
	var landed: Dictionary = {}
	var last_land := deal0
	for k in range(order.size()):
		var i: int = order[k]
		var lt := deal0 + k * gap
		launch[i] = lt
		landed[i] = lt + flight
		c.append([lt + flight - 0.20, "sfx", "deal", -7.0])
		c.append([lt + flight, "card_land", i, 0])
		last_land = maxf(last_land, lt + flight)
	p["launch"] = launch
	p["landed"] = landed
	p["flight"] = flight
	# 뒤집기: 낮은 카드부터 — 가장 좋은 카드가 마지막이다. 4성 이상은 붙들고 빛을 모은다.
	var seq: Array = range(n)
	seq.sort_custom(func(a, b): return _stars(a) < _stars(b) or (_stars(a) == _stars(b) and a < b))
	var flip: Dictionary = {}
	var charge: Dictionary = {}
	# 낮은 카드는 내려앉는 대로 뒤집기 시작한다(나눔과 겹친다) — 자기 카드가 앉은 뒤에만.
	t = deal0 + flight + _k(0.16, 0.10)
	var gap_f := _k(0.13, 0.09)
	var any_regular := false
	for i in seq:
		var s := _stars(i)
		if s >= SHOWY:
			continue
		t = maxf(t, float(landed[i]) + 0.12)
		flip[i] = t
		c.append([t, "sfx", "flip", -5.0])
		c.append([t + FLIP * 0.5, "sfx", "reveal%d" % (s * 2 - 1), [-14.0, -10.0, -6.0][s - 1]])
		c.append([t + FLIP * 0.5, "reveal", i, 0])
		t += gap_f
		any_regular = true
	if any_regular:
		t += FLIP - gap_f
	t = maxf(t, last_land + 0.1)
	var showy_left := 0
	for i in seq:
		if _stars(i) >= SHOWY:
			showy_left += 1
	for i in seq:
		var s := _stars(i)
		if s < SHOWY:
			continue
		showy_left -= 1
		# 붙들 카드가 둘이면 앞의 것은 짧게 — 박자는 마지막 카드의 것이다.
		var brief := 0.65 if showy_left > 0 else 1.0
		t = maxf(t + _k(0.16, 0.10), last_land + 0.2)
		var hold := (_k(0.50, 0.34) if s == 4 else _k(0.84, 0.56)) * brief
		charge[i] = t
		c.append([t, "charge", i, 0])
		t += hold
		flip[i] = t
		c.append([t, "sfx", "flip", 0.0])
		var rv := t + FLIP * 0.5
		# reveal9 는 두 번 친다(0.20 · 0.45초) — 첫 번째가 앞면이 보이는 순간에 오게.
		c.append([rv - (0.20 if s == 5 else 0.0), "sfx", "reveal%d" % (s * 2 - 1), 0.0])
		c.append([rv, "reveal", i, 0])
		t += FLIP + (_k(0.32, 0.22) if s == 4 else _k(0.56, 0.40)) * brief
	p["flip"] = flip
	p["charge"] = charge
	p["settle"] = t + 0.10
	p["ready"] = t + 0.10 + ARM
	c.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	plan = p
	cues = c


static func _signature(box_tier: int, box_cards: Array) -> String:
	var parts := PackedStringArray([str(box_tier)])
	for card in box_cards:
		var unit: Dictionary = (card as Dictionary).get("unit", {})
		parts.append("%s:%d" % [String(unit.get("id", "?")), int((card as Dictionary).get("stars", 0))])
	return ",".join(parts)


# --------------------------------------------------------------------------- #
# 시간을 흘리기 — 지난 박자의 입자와 소리를 낸다
# --------------------------------------------------------------------------- #
## `sound` 가 거짓이면 소리를 내지 않는다(촬영 · 시험).
func advance(age: float, pick_age: float, dt: float, sound: bool = true) -> void:
	_warm_step(2)
	var from := _last_age
	if age < from - 0.0001:
		from = -1.0
	# 크게 건너뛴 시계(건너뛰기 · 복원)는 지난 박자를 한꺼번에 쏟지 않는다.
	if age - from > 0.5:
		from = age - 0.3
	if _flourish:
		_flourish = false
		_skip_burst(sound)
	for cue in cues:
		var at := float(cue[0])
		if at <= from:
			continue
		if at > age:
			break
		_fire(cue, sound)
	_last_age = age
	if pick_age >= 0.0:
		if _last_pick < 0.0:
			_fire_pick(sound)
		if _last_pick < 0.9 and pick_age >= 0.9:
			if bool(result.get("joker", false)) or bool(result.get("bumped", false)):
				if sound:
					Sfx.play("gain")
				var at := RESULT_CARD + Vector2(0, 222)
				_burst(P.STAR, at, PINK.lightened(0.3), 12, 160.0, 0.6, 7.0, 60.0)
		_last_pick = pick_age
	_step_particles(dt)


func _fire(cue: Array, sound: bool) -> void:
	var kind := String(cue[1])
	match kind:
		"sfx":
			if sound:
				Sfx.force(String(cue[2]), float(cue[3]))
		"land":
			var st := _box(float(cue[0]), -1.0)
			var base: Vector2 = st["pos"]
			for side in [-1.0, 1.0]:
				for n in range(7):
					_spawn(P.DUST, base + Vector2(side * _rng.randf_range(40, 130), -4),
							Vector2(side * _rng.randf_range(60, 190), _rng.randf_range(-50, -10)),
							_rng.randf_range(0.5, 0.8), _rng.randf_range(22, 40), Color(0.62, 0.7, 0.8, 0.5), -20.0, 2.6)
			if sound:
				Sfx.force("block", -4.0, 0.72)
		"grade":
			var g := int(cue[2])
			var st := _box(float(cue[0]) + 0.01, -1.0)
			var mid := _box_mid(st)
			var col := tier_light(g)
			_burst(P.SPARK, mid, col.lightened(0.3), 16 + g * 4, 300.0, 0.55, 6.0, 120.0)
			_burst(P.STAR, mid, col.lightened(0.5), 4 + g, 220.0, 0.7, 9.0, 40.0)
			var star_at := _plate_star(g - 1, 5)
			_burst(P.SPARK, star_at, Look.GOLD.lightened(0.3), 8, 120.0, 0.35, 4.0, 80.0)
			if sound:
				Sfx.force("block", -3.0, 0.92 + 0.11 * g)
				if g >= SHOWY:
					Sfx.play("gain", -4.0)
		"same":
			var st := _box(float(cue[0]), -1.0)
			_burst(P.DUST, _box_mid(st), Color(0.7, 0.75, 0.85, 0.4), 10, 120.0, 0.6, 30.0, -30.0)
		"grand":
			var st := _box(float(cue[0]), -1.0)
			var col := tier_light(int(cue[2]))
			_burst(P.STAR, _box_mid(st), col.lightened(0.4), 18, 340.0, 0.9, 10.0, 30.0)
			_burst(P.STREAK, _box_mid(st), col.lightened(0.5), 14, 520.0, 0.5, 3.0, 0.0)
		"rattle":
			var r := int(cue[2])
			var st := _box(float(cue[0]) + 0.04, -1.0)
			var seam := _box_mouth(st)
			var col := tier_light(tier)
			for n in range(4 + r * 4):
				var x := _rng.randf_range(-120, 120) * float(st["scale"]) / STAGE_SCALE
				_spawn(P.SPARK, seam + Vector2(x, 0), Vector2(x * 0.6, _rng.randf_range(-180, -60)),
						_rng.randf_range(0.3, 0.6), _rng.randf_range(4, 8), col.lightened(0.4), 160.0, 1.0)
			_burst(P.DUST, seam, Color(0.7, 0.72, 0.8, 0.30), 3 + r * 2, 90.0, 0.5, 26.0, -30.0)
			if sound:
				Sfx.force("block", -10.0 + r * 2.0, 0.55 + r * 0.12)
		"burst":
			_open_burst(int(cue[2]), float(cue[0]))
		"card_land":
			var i := int(cue[2])
			var slot := _slot(i, cards.size())
			for side in [-1.0, 1.0]:
				_spawn(P.DUST, slot + Vector2(side * 80, CARD.y * 0.5 - 6), Vector2(side * 70, -20), 0.45, 20.0,
						Color(0.6, 0.68, 0.8, 0.35), -10.0, 3.0)
			_burst(P.SPARK, slot + Vector2(0, CARD.y * 0.5), Color(0.75, 0.85, 1.0), 6, 140.0, 0.3, 3.0, 200.0)
		"slam":
			var st := _box(float(cue[0]), -1.0)
			_burst(P.DUST, _box_mouth(st), Color(0.7, 0.72, 0.8, 0.35), 8, 110.0, 0.5, 22.0, -20.0)
			if sound:
				Sfx.force("block", -2.0, 0.66)
		"charge":
			pass
		"reveal":
			_reveal_burst(int(cue[2]), sound)


## 뚜껑이 터지는 순간의 파편: 상자의 재질을 따른다(나무 → 쇠 → 자수정 → 금화 → 프리즘).
func _open_burst(t: int, at: float) -> void:
	var st := _box(at, -1.0)
	var mouth := _box_mouth(st)
	var col := tier_light(t)
	_burst(P.SPARK, mouth, col.lightened(0.35), 26 + t * 10, 520.0, 0.8, 7.0, 260.0, -PI * 0.5, 2.2)
	_burst(P.STREAK, mouth, col.lightened(0.5), 10 + t * 4, 760.0, 0.42, 3.0, 0.0, -PI * 0.5, 2.6)
	match t:
		1:
			_burst(P.SPLINTER, mouth, Color("#a8713e"), 18, 560.0, 1.1, 9.0, 900.0, -PI * 0.5, 2.4)
			_burst(P.SPLINTER, mouth, Color("#7a4e2b"), 10, 480.0, 1.0, 7.0, 900.0, -PI * 0.5, 2.4)
		2:
			_burst(P.SHARD, mouth, Color("#c4ced9"), 16, 560.0, 1.1, 8.0, 900.0, -PI * 0.5, 2.3)
			_burst(P.STAR, mouth, Color("#9cc4ff"), 10, 380.0, 0.8, 9.0, 60.0)
		3:
			_burst(P.SHARD, mouth, Color("#d27cff"), 22, 600.0, 1.2, 10.0, 900.0, -PI * 0.5, 2.4)
			_burst(P.STAR, mouth, Color("#f0b8ff"), 16, 420.0, 0.9, 10.0, 40.0)
		4:
			_burst(P.COIN, mouth, Color("#ffc34f"), 26, 680.0, 1.4, 10.0, 1000.0, -PI * 0.5, 2.0)
			_burst(P.EMBER, mouth, Color("#ffb24a"), 26, 300.0, 1.4, 6.0, -80.0, -PI * 0.5, 2.6)
			_burst(P.STAR, mouth, Color("#ffe08a"), 14, 460.0, 1.0, 11.0, 30.0)
		_:
			for n in range(30):
				var hue := float(n) / 30.0
				var a := -PI * 0.5 + _rng.randf_range(-1.3, 1.3)
				var sp := _rng.randf_range(260, 760)
				_spawn(P.SHARD, mouth, Vector2(cos(a), sin(a)) * sp, _rng.randf_range(0.9, 1.5), _rng.randf_range(7, 13),
						Color.from_hsv(hue, 0.45, 1.0), 900.0, 0.6, _rng.randf() * TAU, _rng.randf_range(-12, 12))
			_burst(P.STAR, mouth, Color("#fff6dc"), 24, 520.0, 1.2, 13.0, 20.0)
			_burst(P.EMBER, mouth, Color("#ffe9b8"), 20, 240.0, 1.6, 6.0, -60.0, -PI * 0.5, 2.8)


## 한 장의 앞면이 보이는 순간. 1성 작은 반짝임 … 4성 주황금 빛살 … 5성 백금 프리즘 폭발.
func _reveal_burst(i: int, _sound: bool) -> void:
	var s := _stars(i)
	var at := _slot(i, cards.size()) + Vector2(0, -30)
	var col := tier_light(s)
	match s:
		1:
			_burst(P.SPARK, at, col.lightened(0.35), 10, 200.0, 0.45, 5.0, 60.0)
			_burst(P.STAR, at, col.lightened(0.5), 3, 120.0, 0.5, 7.0, 0.0)
		2:
			_burst(P.SPARK, at, col.lightened(0.4), 16, 260.0, 0.55, 5.5, 60.0)
			_burst(P.STAR, at, Color("#bcd6ff"), 6, 170.0, 0.6, 8.0, 0.0)
		3:
			_burst(P.SPARK, at, col.lightened(0.35), 24, 320.0, 0.65, 6.0, 40.0)
			_burst(P.STAR, at, Color("#f0b8ff"), 10, 220.0, 0.8, 9.0, -20.0)
			_burst(P.EMBER, at + Vector2(0, 80), col.lightened(0.3), 10, 90.0, 1.1, 5.0, -90.0, -PI * 0.5, 1.4)
		4:
			_burst(P.SPARK, at, Color("#ffd27a"), 40, 460.0, 0.8, 7.0, 60.0)
			_burst(P.STAR, at, Color("#ffe8a8"), 14, 300.0, 0.9, 11.0, -10.0)
			_burst(P.EMBER, at + Vector2(0, 100), Color("#ffb24a"), 20, 120.0, 1.5, 6.0, -110.0, -PI * 0.5, 1.6)
			_burst(P.STREAK, at, Color("#ffd27a"), 12, 620.0, 0.4, 3.0, 0.0)
		_:
			for n in range(48):
				var a := _rng.randf() * TAU
				var sp := _rng.randf_range(180, 640)
				_spawn(P.SPARK, at, Vector2(cos(a), sin(a)) * sp, _rng.randf_range(0.7, 1.2), _rng.randf_range(5, 9),
						Color.from_hsv(float(n) / 48.0, 0.35, 1.0), 40.0, 1.2)
			_burst(P.STAR, at, Color("#fff6dc"), 22, 380.0, 1.1, 13.0, -10.0)
			_burst(P.STREAK, at, Color("#fff0b8"), 18, 780.0, 0.45, 3.5, 0.0)
			_burst(P.EMBER, at + Vector2(0, 100), Color("#ffe9b8"), 24, 140.0, 1.8, 6.0, -120.0, -PI * 0.5, 1.8)


## 건너뛰기를 누른 순간 아직 열리지 않은 카드를 한꺼번에 연다.
func _skip_burst(sound: bool) -> void:
	var best := 1
	for i in range(cards.size()):
		var flip_t := float((plan.get("flip", {}) as Dictionary).get(i, 0.0))
		if flip_t + FLIP * 0.5 > _last_age:
			_reveal_burst(i, false)
			best = maxi(best, _stars(i))
	if sound:
		Sfx.force("flip", -3.0)
		Sfx.force("reveal%d" % (best * 2 - 1), -2.0 if best >= SHOWY else -6.0)


func _fire_pick(sound: bool) -> void:
	if picked < 0:
		return
	var at := _slot(picked, cards.size())
	var s := _stars(picked)
	_burst(P.SPARK, at, tier_light(s).lightened(0.4), 28 + s * 6, 380.0, 0.7, 6.0, 80.0)
	_burst(P.STAR, at, Look.STARLIGHT, 8 + s * 2, 260.0, 0.8, 10.0, 0.0)
	for i in range(cards.size()):
		if i == picked:
			continue
		var slot := _slot(i, cards.size())
		for n in range(10):
			_spawn(P.EMBER, slot + Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-130, 130)),
					Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-140, -60)), _rng.randf_range(0.6, 1.1),
					_rng.randf_range(4, 7), tier_light(_stars(i)).lightened(0.3), -40.0, 0.8)
	if sound:
		Sfx.force("summon_burst")


# --------------------------------------------------------------------------- #
# 입자 풀
# --------------------------------------------------------------------------- #
func _spawn(kind: int, pos: Vector2, vel: Vector2, life: float, size: float, col: Color,
		grav: float = 0.0, drag: float = 0.0, rot: float = 0.0, spin: float = 0.0) -> void:
	var i := _pn
	_pn = (_pn + 1) % CAP
	_pp[i] = pos
	_pv[i] = vel
	_pl[i] = life
	_pm[i] = life
	_ps[i] = size
	_pc[i] = col
	_pk[i] = kind
	_pg[i] = grav
	_pd[i] = drag
	_pr[i] = rot
	_pw[i] = spin


## 한 점에서 퍼지는 한 무더기. `aim` 을 주면 그쪽으로 `spread` 만큼 퍼진다.
func _burst(kind: int, pos: Vector2, col: Color, n: int, speed: float, life: float, size: float,
		grav: float = 0.0, aim: float = INF, spread: float = TAU) -> void:
	for k in range(n):
		var a := _rng.randf() * TAU if aim == INF else aim + _rng.randf_range(-spread * 0.5, spread * 0.5)
		var sp := speed * _rng.randf_range(0.35, 1.0)
		_spawn(kind, pos, Vector2(cos(a), sin(a)) * sp, life * _rng.randf_range(0.65, 1.2), size * _rng.randf_range(0.7, 1.3),
				col, grav, 1.4 if kind in [P.SPARK, P.STAR, P.STREAK] else 0.4, _rng.randf() * TAU, _rng.randf_range(-10, 10))


func _step_particles(dt: float) -> void:
	if dt <= 0.0:
		return
	for i in range(CAP):
		if _pl[i] <= 0.0:
			continue
		_pl[i] -= dt
		var v := _pv[i]
		v.y += _pg[i] * dt
		v *= maxf(0.0, 1.0 - _pd[i] * dt)
		_pv[i] = v
		_pp[i] += v * dt
		_pr[i] += _pw[i] * dt


func alive() -> int:
	var n := 0
	for i in range(CAP):
		if _pl[i] > 0.0:
			n += 1
	return n


func _draw_particles(ci: CanvasItem, light: bool) -> void:
	var glow := glow_tex()
	for i in range(CAP):
		if _pl[i] <= 0.0:
			continue
		var kind := _pk[i]
		if bool(P_LIGHT[kind]) != light:
			continue
		var k := clampf(_pl[i] / maxf(0.001, _pm[i]), 0.0, 1.0)
		var p := _pp[i]
		var s := _ps[i]
		var col := _pc[i]
		match kind:
			P.SPARK:
				var r := s * (0.6 + 0.6 * k)
				ci.draw_texture_rect(glow, Rect2(p - Vector2(r, r) * 2.0, Vector2(r, r) * 4.0), false, Color(col, k * 0.55))
				ci.draw_circle(p, r * 0.42, Color(col.lightened(0.5), k))
			P.EMBER:
				var flick := 0.75 + 0.25 * sin(_pl[i] * 23.0 + float(i))
				var r := s * (0.5 + 0.5 * k)
				ci.draw_texture_rect(glow, Rect2(p - Vector2(r, r) * 2.2, Vector2(r, r) * 4.4), false, Color(col, k * 0.5 * flick))
				ci.draw_circle(p, r * 0.35, Color(col.lightened(0.6), k * flick))
			P.STAR:
				_sparkle(ci, p, s * (0.4 + 0.8 * sin(PI * k)), _pr[i] * 0.3, Color(col, minf(1.0, k * 1.6)))
			P.STREAK:
				var v := _pv[i]
				var tail := p - v * 0.045
				ci.draw_line(tail, p, Color(col, k * 0.8), s * k + 0.6, true)
			P.SHARD:
				var r := s * (0.55 + 0.45 * k)
				if r < 0.8:
					continue
				var a := _pr[i]
				var pts := PackedVector2Array([p + Vector2(cos(a), sin(a)) * r * 1.4, p + Vector2(cos(a + 2.2), sin(a + 2.2)) * r * 0.8,
					p + Vector2(cos(a + 3.3), sin(a + 3.3)) * r * 1.1, p + Vector2(cos(a + 4.6), sin(a + 4.6)) * r * 0.7])
				ci.draw_colored_polygon(pts, Color(col, minf(1.0, k * 1.5)))
				ci.draw_line(pts[0], pts[1], Color(col.lightened(0.6), minf(1.0, k * 1.5)), 1.2, true)
			P.COIN:
				var r := s * (0.6 + 0.4 * k)
				var w := absf(cos(_pr[i] * 1.6)) * r + 0.8
				var face := Color(col, minf(1.0, k * 1.6))
				ci.draw_set_transform(p, _pr[i] * 0.2, Vector2(w / r, 1.0))
				ci.draw_circle(Vector2.ZERO, r, face.darkened(0.25))
				ci.draw_circle(Vector2(-r * 0.12, -r * 0.12), r * 0.78, face)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			P.SPLINTER:
				var a := _pr[i]
				var d := Vector2(cos(a), sin(a))
				var nrm := d.orthogonal()
				var l := s * 1.8
				var w := s * 0.35
				var pts := PackedVector2Array([p - d * l + nrm * w, p + d * l + nrm * w * 0.4, p + d * l - nrm * w * 0.4, p - d * l - nrm * w])
				ci.draw_colored_polygon(pts, Color(col, minf(1.0, k * 1.5)))
			P.DUST:
				var r := s * (1.6 - 0.6 * k)
				ci.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col, col.a * k))


static func _sparkle(ci: CanvasItem, p: Vector2, r: float, rot: float, col: Color) -> void:
	if r < 0.8 or col.a <= 0.01:
		return
	var glow := glow_tex()
	ci.draw_texture_rect(glow, Rect2(p - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), false, Color(col, col.a * 0.55))
	for axis in range(2):
		var a := rot + axis * PI * 0.5
		var d := Vector2(cos(a), sin(a))
		var n := d.orthogonal()
		var len := r * (1.0 if axis == 0 else 0.75)
		ci.draw_colored_polygon(PackedVector2Array([p - d * len, p + n * r * 0.13, p + d * len, p - n * r * 0.13]), col)


# --------------------------------------------------------------------------- #
# 그림 재료
# --------------------------------------------------------------------------- #
## 등급의 빛 색 — Look.TIER_COLOR 의 온 별 칸.
static func tier_light(stars: int) -> Color:
	return Look.tier_color(clampi(stars, 1, 5) * 2 - 1)


## 부드러운 빛 한 점(가운데 1 → 가장자리 0). 한 번만 만들어 둔다.
static func glow_tex() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.22, Color(1, 1, 1, 0.62))
		g.add_point(0.55, Color(1, 1, 1, 0.16))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		var c := CanvasTexture.new()
		c.diffuse_texture = t
		c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_glow = c
	return _glow


## 상자 그림 한 층. 렌더는 Nearest 기본값을 따르지 않고 밉맵 선형으로 읽는다(작은 머리 자리).
static func box_tex(t: int, layer: String) -> Texture2D:
	var key := "%d/%s" % [t, layer]
	if _tex.has(key):
		return _tex[key]
	var raw := Art.tex("res://art/ui/box/tier%d/%s.png" % [t, layer])
	var out: Texture2D = null
	if raw != null:
		var c := CanvasTexture.new()
		c.diffuse_texture = raw
		c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		out = c
	_tex[key] = out
	return out


## 상자를 닫을 때 그림을 놓아 준다(Art 캐시는 영원히 들고 있으므로).
static func release_art() -> void:
	_tex.clear()
	Art.forget("res://art/ui/box/")


static func _layout(t: int) -> Dictionary:
	return Layout.TIERS[clampi(t, 1, 5)]


## 그림 한 층을 앵커(밑동 가운데) 기준으로 놓는다 — 웅크림·늘어남의 축이 밑동이다.
static func _blit(ci: CanvasItem, t: int, layer: String, anchor: Vector2, scale: Vector2, rot: float, mod: Color) -> void:
	var tex := box_tex(t, layer)
	if tex == null:
		return
	var lay := _layout(t)
	var r: Rect2 = (lay["layers"] as Dictionary)[layer]
	var a: Vector2 = lay["anchor"]
	ci.draw_set_transform(anchor, rot, scale)
	ci.draw_texture_rect(tex, Rect2(r.position - a, r.size), false, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _lid_layer(angle: float) -> String:
	var best := 0
	var gap := 1e9
	for a in Layout.ANGLES:
		var d := absf(float(a) - angle)
		if d < gap:
			gap = d
			best = int(a)
	return "lid_%03d" % best


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


static func _ease_in(x: float) -> float:
	return pow(clampf(x, 0.0, 1.0), 2.4)


static func _ease_in_out(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _back(x: float, over: float = 1.7) -> float:
	var t := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + t * t * ((over + 1.0) * t + over)


## 줄었다 늘었다 잦아드는 용수철(웅크림·안착).
static func _spring(d: float, amp: float, freq: float = 21.0, damp: float = 7.5) -> float:
	if d < 0.0:
		return 0.0
	return amp * exp(-damp * d) * cos(freq * d)


# --------------------------------------------------------------------------- #
# 상자의 자세 — 나눔 시계 `age` 와 고르기 시계 `pick_age` 의 함수
# --------------------------------------------------------------------------- #
func _box(age: float, pick_age: float) -> Dictionary:
	var p := plan
	var st := {"pos": STAGE, "scale": STAGE_SCALE, "sx": 1.0, "sy": 1.0, "rot": 0.0, "lid": 0.0,
		"tier": start_tier, "white": 0.0, "seam": 0.0, "alpha": 1.0, "lift": 0.0, "jit": Vector2.ZERO, "glow": 0.0}
	if p.is_empty():
		return st
	var steps_t: Array = p["steps_t"]
	var steps_d: Array = p["steps_d"]
	var passed := 0
	for j in range(steps_t.size()):
		if age >= float(steps_t[j]) + 0.43 * float(steps_d[j]):
			passed += 1
	st["tier"] = start_tier + passed
	var sx := 1.0
	var sy := 1.0
	var lift := 0.0
	var white := 0.0
	if rerolled:
		var slam := float(p["slam"])
		var r0 := float(p["ret0"])
		var r1 := float(p["ret1"])
		if age < r0:
			st["pos"] = HEAD
			st["scale"] = HEAD_SCALE
			st["lid"] = 100.0 if age < slam else lerpf(100.0, 0.0, clampf((age - slam) / 0.07, 0.0, 1.0))
			# 카드가 하나 들어올 때마다 작게 움찔한다.
			var fold: Dictionary = p["fold"]
			for i in fold:
				var arrive := float(fold[i]) + 0.42
				sy -= _spring(age - arrive, 0.06, 26.0, 10.0)
			var s := _spring(age - slam - 0.07, 0.14)
			sy -= s
			sx += s * 0.7
		elif age < r1:
			var k := _ease_in_out((age - r0) / (r1 - r0))
			st["pos"] = HEAD.lerp(STAGE, k) + Vector2(0, -70.0 * sin(PI * k))
			st["scale"] = lerpf(HEAD_SCALE, STAGE_SCALE, k)
			sy += 0.06 * sin(PI * k)
		else:
			var s := _spring(age - r1, 0.15)
			sy -= s
			sx += s * 0.75
	else:
		var land := float(p["land"])
		if age < land:
			var u := clampf(age / land, 0.0, 1.0)
			lift = -470.0 * (1.0 - u * u)
			sy = 1.0 + 0.10 * u
			sx = 1.0 - 0.06 * u
			st["rot"] = 0.07 * (1.0 - u)
		else:
			var s := _spring(age - land, 0.18)
			sy -= s
			sx += s * 0.75
	# 숨쉬기 — 내려앉은 뒤부터.
	var breathe := 0.012 * sin(5.4 * age)
	sy *= 1.0 + breathe
	sx *= 1.0 - breathe * 0.6
	# 등급 오르기의 한 단: 웅크림 → 흰 빛 속에서 뛰어 그림이 바뀜 → 안착.
	var active := -1
	for j in range(steps_t.size()):
		if age >= float(steps_t[j]) and age < float(steps_t[j]) + float(steps_d[j]):
			active = j
	if active >= 0:
		var step := float(steps_d[active])
		var u := (age - float(steps_t[active])) / step
		if u < 0.25:
			var k := _ease_out(u / 0.25)
			sy *= 1.0 - 0.10 * k
			sx *= 1.0 + 0.07 * k
			white = 0.45 * k
		elif u < 0.62:
			var v := (u - 0.25) / 0.37
			lift += -36.0 * sin(PI * v)
			sy *= 1.0 + 0.09 * sin(PI * v)
			sx *= 1.0 - 0.05 * sin(PI * v)
			white = 0.45 + 0.55 * clampf((u - 0.25) / 0.18, 0.0, 1.0) if u < 0.43 else 1.0 - clampf((u - 0.43) / 0.32, 0.0, 1.0)
		else:
			var s := _spring((u - 0.62) * step, 0.10)
			sy -= s
			sx += s * 0.7
			white = maxf(0.0, 1.0 - (u - 0.43) / 0.32)
	# 높은 등급에 닿은 박자: 한 번 더 부풀며 빛난다.
	if p.has("grand"):
		var d := age - float(p["grand"])
		if d >= 0.0 and d < 0.8:
			var s := _spring(d, -0.10, 16.0, 5.0)
			sy -= s
			sx += s * 0.6
			white = maxf(white, 0.5 * exp(-5.0 * d))
			st["glow"] = exp(-2.5 * d)
	# 예비 동작: 세 번 들썩이며 이음새가 빛나고, 웅크렸다 터진다.
	var a0 := float(p["antic0"])
	var antic := float(p["antic"])
	var burst := float(p["burst"])
	if age >= a0 and age < burst:
		var t := age - a0
		var seam := 0.0
		var jit := Vector2.ZERO
		var rot := 0.0
		var peaks := [6.0, 6.0, 18.0]
		var amps := [3.0, 5.0, 8.0]
		for r in range(3):
			var at: float = antic * float([0.0, 0.32, 0.58][r])
			var d: float = t - at
			if d >= 0.0:
				seam = [0.35, 0.6, 0.85][r] + 0.4 * exp(-9.0 * d)
				if d < 0.11:
					st["lid"] = maxf(float(st["lid"]), float(peaks[r]) * sin(PI * d / 0.11))
				var shake := float(amps[r]) * exp(-14.0 * d)
				jit += Vector2(sin(d * 61.0) * shake, -absf(sin(d * 43.0)) * shake * 0.6)
				rot += sin(d * 53.0) * 0.012 * shake
		# 두 번째 들썩임 뒤로 뚜껑은 살짝 들린 채(6도) 빛을 못 이긴다 — 이음새의 빛이 실제 틈에서 샌다.
		if t >= antic * 0.32 + 0.11:
			st["lid"] = maxf(float(st["lid"]), 6.0)
		var w := clampf((t - antic * 0.74) / (antic * 0.26), 0.0, 1.0)
		if w > 0.0:
			var k := _ease_in(w)
			sy *= 1.0 - 0.12 * k
			sx *= 1.0 + 0.08 * k
			seam = maxf(seam, 0.9 + 0.1 * k)
			white = maxf(white, 0.28 * k)
			jit += Vector2(sin(age * 90.0) * 2.0 * k, 0)
		st["seam"] = seam
		st["jit"] = jit
		st["rot"] = float(st["rot"]) + rot
	# 터짐: 뚜껑이 0 → 118 → 100 도로 젖혀지고 몸통이 늘었다 잦아든다.
	if age >= burst:
		var d := age - burst
		var lid := 100.0
		if d < 0.035:
			lid = lerpf(0.0, 40.0, d / 0.035)
		elif d < 0.07:
			lid = lerpf(40.0, 100.0, (d - 0.035) / 0.035)
		elif d < 0.11:
			lid = lerpf(100.0, 118.0, (d - 0.07) / 0.04)
		elif d < 0.22:
			lid = lerpf(118.0, 100.0, (d - 0.11) / 0.11)
		st["lid"] = lid
		var s := _spring(d, 0.16, 17.0, 6.0)
		sy *= 1.0 + s
		sx *= 1.0 - s * 0.6
		white = maxf(white, 0.5 * exp(-14.0 * d))
		st["seam"] = exp(-10.0 * d)
		st["glow"] = maxf(float(st["glow"]), exp(-1.8 * d))
		# 머리 자리로 물러난다 — 카드가 무대를 쓴다.
		var m0 := float(p["move0"])
		var m1 := float(p["move1"])
		if age >= m0:
			var k := _ease_in_out((age - m0) / (m1 - m0))
			st["pos"] = STAGE.lerp(HEAD, k) + Vector2(0, -36.0 * sin(PI * k))
			st["scale"] = lerpf(STAGE_SCALE, HEAD_SCALE, k)
			st["rot"] = float(st["rot"]) + 0.05 * sin(PI * k)
	# 고른 뒤: 머리의 상자는 닫히며 작아져 사라진다.
	if pick_age >= 0.0:
		st["lid"] = lerpf(100.0, 0.0, clampf(pick_age / 0.12, 0.0, 1.0))
		var k := _ease_in(clampf((pick_age - 0.12) / 0.26, 0.0, 1.0))
		st["scale"] = float(st["scale"]) * (1.0 - k)
		st["alpha"] = 1.0 - k
	st["sx"] = sx
	st["sy"] = sy
	st["lift"] = lift
	st["white"] = white
	return st


## 상자의 화면 앵커(밑동 가운데) — 들썩임·흔들림·뜀까지 넣은 실제 자리.
func _box_anchor(st: Dictionary, shake: Vector2 = Vector2.ZERO) -> Vector2:
	return Vector2(st["pos"]) + Vector2(0, float(st["lift"])) * float(st["scale"]) / STAGE_SCALE + Vector2(st["jit"]) + shake


func _box_mouth(st: Dictionary) -> Vector2:
	var lay := _layout(int(st["tier"]))
	var off: Vector2 = Vector2(lay["mouth"]) - Vector2(lay["anchor"])
	return _box_anchor(st) + Vector2(off.x * float(st["sx"]), off.y * float(st["sy"])) * float(st["scale"])


func _box_mid(st: Dictionary) -> Vector2:
	var lay := _layout(int(st["tier"]))
	var b: Rect2 = lay["bounds"]
	var off: Vector2 = b.get_center() - Vector2(lay["anchor"])
	return _box_anchor(st) + off * float(st["scale"])


func _shake(age: float) -> Vector2:
	var p := plan
	if p.is_empty():
		return Vector2.ZERO
	var out := Vector2.ZERO
	var events: Array = []
	if p.has("land"):
		events.append([float(p["land"]), 4.0])
	events.append([float(p["burst"]), 4.0 + 2.0 * tier])
	if p.has("grand"):
		events.append([float(p["grand"]), 3.0 if tier == 4 else 6.0])
	var flip: Dictionary = p["flip"]
	for i in flip:
		var s := _stars(int(i))
		if s >= SHOWY:
			events.append([float(flip[i]) + FLIP * 0.5, 5.0 if s == 4 else 9.0])
	for e in events:
		var d := age - float(e[0])
		if d < 0.0 or d > 0.6:
			continue
		var a := float(e[1]) * exp(-9.0 * d)
		out += Vector2(sin(d * 71.0 + float(e[0])), cos(d * 59.0 + float(e[0]) * 2.0)) * a
	return out


# --------------------------------------------------------------------------- #
# 카드의 자세
# --------------------------------------------------------------------------- #
static func _slot(i: int, n: int) -> Vector2:
	var count := maxi(1, n)
	var width := CARD.x * count + CARD_GAP * (count - 1)
	return Vector2(640.0 - width * 0.5 + CARD.x * 0.5 + i * (CARD.x + CARD_GAP), CARD_Y)


func _card(i: int, age: float, pick_age: float) -> Dictionary:
	var slot := _slot(i, cards.size())
	var st := {"show": false, "pos": slot, "rot": 0.0, "scale": 1.0, "sx": 1.0, "sy": 1.0, "skew": 0.0,
		"face": false, "alpha": 1.0, "reveal": -1.0, "charge": 0.0, "white": 0.0, "fly": false, "u": 1.0}
	var launch: Dictionary = plan.get("launch", {})
	if not launch.has(i):
		return st
	var lt := float(launch[i])
	if age < lt:
		return st
	st["show"] = true
	var flight := float(plan["flight"])
	var u := (age - lt) / flight
	if u < 1.0:
		var from := _box_mouth(_box(lt, -1.0))
		var ctrl := (from + slot) * 0.5 + Vector2(0, -250)
		var e := 1.0 - pow(1.0 - u, 1.6)
		st["pos"] = from.lerp(ctrl, e).lerp(ctrl.lerp(slot, e), e)
		st["scale"] = lerpf(0.16, 1.0, _ease_out(u))
		var side := signf(slot.x - 640.0) if absf(slot.x - 640.0) > 1.0 else 1.0
		st["rot"] = side * 0.95 * (1.0 - _ease_out(u))
		st["fly"] = true
		st["u"] = u
		return st
	var d := age - lt - flight
	var s := _spring(d, 0.08, 24.0, 9.0)
	var sy := 1.0 - s
	var sx := 1.0 + s * 0.6
	var bob := 2.0 * sin(2.1 * age + i * 1.3)
	var lift := 0.0
	var flip: Dictionary = plan.get("flip", {})
	var charge: Dictionary = plan.get("charge", {})
	var ft := float(flip.get(i, INF))
	var ct := float(charge.get(i, INF))
	var pos := slot
	if age >= ct and age < ft:
		var c := (age - ct) / (ft - ct)
		st["charge"] = c
		lift -= 20.0 * _ease_out(c)
		pos.x += sin(age * 70.0 + i) * 3.2 * c
		st["white"] = 0.25 * c
	if age >= ft:
		var f := clampf((age - ft) / FLIP, 0.0, 1.0)
		var th := PI * _ease_in_out(f)
		sx *= maxf(0.02, absf(cos(th)))
		st["face"] = th > PI * 0.5
		st["skew"] = 0.10 * sin(2.0 * th)
		lift -= 16.0 * sin(th)
		var r := ft + FLIP * 0.5
		st["reveal"] = age - r
		if ct < INF:
			lift -= 20.0 * (1.0 - _ease_out((age - ft) / 0.55))
			st["charge"] = maxf(0.0, 1.0 - (age - ft) / 0.25)
		if age >= r:
			var pop := _spring(age - r, 0.12 if _stars(i) >= SHOWY else 0.05, 15.0, 6.0)
			st["scale"] = 1.0 + pop
			st["white"] = maxf(float(st["white"]), [0.0, 0.42, 0.52, 0.64, 0.82, 0.92][_stars(i)] * exp(-9.0 * (age - r)))
	if pick_age >= 0.0:
		if i == picked:
			var k := _back(clampf((pick_age - 0.12) / 0.5, 0.0, 1.0), 1.2)
			var rise := -24.0 * _ease_out(pick_age / 0.12)
			pos = slot.lerp(RESULT_CARD, k) + Vector2(0, rise * (1.0 - k))
			st["scale"] = lerpf(1.0 + 0.10 * _ease_out(pick_age / 0.12), RESULT_SCALE, k)
			st["white"] = 0.9 * exp(-7.0 * pick_age)
			bob = 0.0
		else:
			var k := clampf((pick_age - 0.04 - absf(i - picked) * 0.05) / 0.36, 0.0, 1.0)
			st["alpha"] = 1.0 - _ease_in(k)
			st["scale"] = float(st["scale"]) * (1.0 - 0.12 * k)
			lift -= 30.0 * k
			if k >= 1.0:
				st["show"] = false
	st["pos"] = pos + Vector2(0, lift + bob)
	st["sx"] = sx
	st["sy"] = sy
	return st


## 다시 뽑기 때 접혀 상자로 돌아가는 옛 카드.
func _old_card(i: int, age: float) -> Dictionary:
	var slot := _slot(i, old_cards.size())
	var st := {"show": true, "pos": slot, "rot": 0.0, "scale": 1.0, "sx": 1.0, "sy": 1.0, "skew": 0.0,
		"face": true, "alpha": 1.0, "reveal": 9.0, "charge": 0.0, "white": 0.0, "fly": false, "u": 1.0}
	var fold: Dictionary = plan.get("fold", {})
	var t0 := float(fold.get(i, 0.0))
	if age < t0:
		return st
	var u1 := (age - t0) / 0.12
	if u1 < 1.0:
		var th := PI * _ease_in_out(u1)
		st["sx"] = maxf(0.02, absf(cos(th)))
		st["face"] = th < PI * 0.5
		st["pos"] = slot + Vector2(0, -10.0 * sin(th))
		return st
	st["face"] = false
	var u2 := (age - t0 - 0.12) / 0.30
	if u2 >= 1.0:
		st["show"] = false
		return st
	var to := _box_mouth(_box(age, -1.0))
	var e := _ease_in(u2)
	var ctrl := (slot + to) * 0.5 + Vector2(0, -120)
	st["pos"] = slot.lerp(ctrl, e).lerp(ctrl.lerp(to, e), e)
	st["scale"] = lerpf(1.0, 0.12, e)
	st["rot"] = signf(slot.x - 640.0 + 0.01) * 2.2 * e
	st["fly"] = true
	st["u"] = u2
	return st


# --------------------------------------------------------------------------- #
# 그리기 — 보통 섞기 층
# --------------------------------------------------------------------------- #
## 한 캔버스에 전부: 무대 → 빛 → 단추·결과 → 섬광.
func draw_all(ci: CanvasItem, ui: Ui, age: float, pick_age: float) -> void:
	draw_scene(ci, age, pick_age)
	draw_light(ci, age, pick_age)
	_draw_ui(ci, ui, age, pick_age)
	if pick_age >= 0.0:
		_draw_result(ci, ui, pick_age)
	_draw_flash(ci, age, pick_age)


func draw_scene(ci: CanvasItem, age: float, pick_age: float) -> void:
	var fade := 1.0 if rerolled else _ease_out(age / 0.2)
	ci.draw_rect(SCREEN, Color(Look.SHADE, Look.SHADE.a * fade))
	_draw_sky(ci, fade, age)
	var shake := _shake(age)
	var box := _box(age, pick_age)
	_draw_spot(ci, box, age, pick_age)
	_draw_box_back(ci, box, age, shake)
	_draw_box(ci, box, shake)
	_draw_plate(ci, box, age, pick_age)
	_draw_particles(ci, false)
	if rerolled:
		for i in range(old_cards.size()):
			var st := _old_card(i, age)
			if bool(st["show"]):
				_draw_card(ci, old_cards[i], st, shake, age)
	# 그리는 순서: 먼저 날아간 카드부터, 빛을 모으거나 막 열리는 카드는 맨 위에.
	var order: Array = range(cards.size())
	var launch: Dictionary = plan.get("launch", {})
	order.sort_custom(func(a, b): return float(launch.get(a, 0.0)) < float(launch.get(b, 0.0)))
	var top: Array = []
	for i in order:
		var st := _card(i, age, pick_age)
		if not bool(st["show"]):
			continue
		if float(st["charge"]) > 0.0 or (float(st["reveal"]) >= -FLIP and float(st["reveal"]) < 0.4) or i == picked:
			top.append([i, st])
			continue
		_draw_card_aura(ci, cards[i], st, shake, age)
		_draw_card(ci, cards[i], st, shake, age)
	for entry in top:
		var idx := int(entry[0])
		_face_tier = -1
		if idx == picked and pick_age >= 0.9 and (bool(result.get("joker", false)) or bool(result.get("bumped", false))):
			_face_tier = int(result.get("after_tier", -1))
			_face_pop = pick_age - 0.9
		_draw_card_aura(ci, cards[idx], entry[1], shake, age)
		_draw_card(ci, cards[idx], entry[1], shake, age)
		_face_tier = -1


## 그늘 위의 흐린 별 — 별자리 팝업과 같은 밤(상태 없이 번호로 자리를 셈한다).
static func _draw_sky(ci: CanvasItem, alpha: float, age: float) -> void:
	for n in range(64):
		var p := Vector2(10.0 + fposmod(n * 0.7548776, 1.0) * 1260.0, 76.0 + fposmod(n * 0.5698403 + 0.31, 1.0) * 714.0)
		var r := 0.7 + 1.2 * fposmod(n * 0.381966, 1.0)
		var tw := 0.6 + 0.4 * sin(age * 1.3 + n * 1.7)
		ci.draw_circle(p, r, Color(Look.STARLIGHT, 0.15 * alpha * tw), true, -1, true)


## 무대 조명: 상자 뒤의 등급 빛과, 카드가 펼쳐진 뒤 카드 줄을 비추는 넓은 빛.
func _draw_spot(ci: CanvasItem, box: Dictionary, age: float, pick_age: float) -> void:
	var glow := glow_tex()
	var col := tier_light(int(box["tier"]))
	var at := _box_mid(box)
	var big := float(box["scale"]) / STAGE_SCALE
	var a := float(box["alpha"])
	var r := Vector2(560, 470) * big
	ci.draw_texture_rect(glow, Rect2(at - r, r * 2.0), false, Color(col, 0.16 * a))
	r = Vector2(300, 250) * big
	ci.draw_texture_rect(glow, Rect2(at - r, r * 2.0), false, Color(col.lightened(0.3), 0.10 * a + 0.12 * float(box["glow"])))
	var deal0 := float(plan.get("deal0", 99.0))
	var row := clampf((age - deal0) / 0.6, 0.0, 1.0) * (1.0 - clampf(pick_age / 0.4, 0.0, 1.0) if pick_age >= 0.0 else 1.0)
	if row > 0.0:
		ci.draw_texture_rect(glow, Rect2(Vector2(40, CARD_Y - 300), Vector2(1200, 600)), false, Color(0.55, 0.7, 0.95, 0.07 * row))


## 상자 뒤의 빛살(보통 섞기 층, 상자 밑): 높은 등급에 닿은 박자와 터지는 순간.
func _draw_box_back(ci: CanvasItem, st: Dictionary, age: float, shake: Vector2) -> void:
	var t := int(st["tier"])
	var big := float(st["scale"]) / STAGE_SCALE
	var light := tier_light(t).lightened(0.35)
	var grand := float(st["glow"])
	if grand > 0.01 and plan.has("grand") and age < float(plan["burst"]):
		_rays(ci, _box_mid(st) + shake, 14 if t == 4 else 20, 440.0 * big, age * 0.4, light, 0.42 * grand, t == 5)
	var d := age - float(plan.get("burst", 99.0))
	if d >= 0.0 and d < 1.4:
		_rays(ci, _box_mouth(st) + shake, 10 + 3 * t, (460.0 + 60.0 * t) * big, -age * 0.3, light, 0.38 * exp(-2.0 * d), t == 5)


func _draw_box(ci: CanvasItem, st: Dictionary, shake: Vector2) -> void:
	var t := int(st["tier"])
	var sc := float(st["scale"])
	var a := float(st["alpha"])
	if sc <= 0.01 or a <= 0.01:
		return
	var anchor := _box_anchor(st, shake)
	var scale := Vector2(float(st["sx"]), float(st["sy"])) * sc
	# 접지 그림자: 뛰어오르면 작고 옅어진다.
	var lift := clampf(-float(st["lift"]) / 200.0, 0.0, 1.0)
	var lay := _layout(t)
	var b: Rect2 = lay["bounds"]
	var w := b.size.x * sc * (0.62 - 0.25 * lift)
	ci.draw_texture_rect(glow_tex(), Rect2(Vector2(st["pos"]) + shake + Vector2(-w, -w * 0.16), Vector2(w * 2.0, w * 0.32)), false,
			Color(0.0, 0.0, 0.02, 0.62 * a * (1.0 - 0.6 * lift)))
	# 흰 빛(등급이 바뀌는 순간)은 색을 1 위로 곱해 그림을 하얗게 태운다.
	var white := float(st["white"])
	var mod := Color(1.0 + white * 2.6, 1.0 + white * 2.6, 1.0 + white * 2.6, a)
	var rot := float(st["rot"])
	_blit(ci, t, "body", anchor, scale, rot, mod)
	_blit(ci, t, _lid_layer(float(st["lid"])), anchor, scale, rot, mod)


## 상자 등급판: 무대에서는 상자 밑에 별 줄과 「N성 상자」, 머리 자리에서는 상자 양옆에.
func _draw_plate(ci: CanvasItem, box: Dictionary, age: float, pick_age: float) -> void:
	var shown := int(box["tier"])
	var p := plan
	var steps_t: Array = p.get("steps_t", [])
	var steps_d: Array = p.get("steps_d", [])
	var stage_k := 0.0
	var head_k := 0.0
	if rerolled:
		var r1 := float(p.get("ret1", 0.0))
		stage_k = clampf((age - r1) / 0.2, 0.0, 1.0)
	else:
		stage_k = clampf((age - float(p.get("land", 0.3))) / 0.25, 0.0, 1.0)
	var m0 := float(p.get("move0", 99.0))
	var m1 := float(p.get("move1", 99.0))
	stage_k *= 1.0 - clampf((age - m0) / 0.18, 0.0, 1.0)
	head_k = clampf((age - m1 + 0.1) / 0.3, 0.0, 1.0)
	if pick_age >= 0.0:
		head_k *= 1.0 - clampf(pick_age / 0.25, 0.0, 1.0)
	var col := tier_light(shown)
	var ink := col.lightened(0.35) if shown != 2 else col.lightened(0.45)
	if stage_k > 0.0:
		for j in range(5):
			var at := _plate_star(j, 5)
			var on := j < shown
			var pop := 1.0
			if on and j >= start_tier and j - start_tier < steps_t.size():
				var swap := float(steps_t[j - start_tier]) + 0.43 * float(steps_d[j - start_tier])
				pop = 1.0 + 0.8 * maxf(0.0, 1.0 - (age - swap) / 0.22) if age >= swap else 1.0
			_star(ci, at, 17.0 * pop, on, Color(1, 1, 1, stage_k))
		Look.text_center(ci, Vector2(640, STAGE.y + 101), I18n.t("arena.box_tier") % shown, 28, Color(ink, stage_k))
		if free_box and not rerolled:
			Look.chip(ci, Vector2(640, STAGE.y + 136), I18n.t("arena.box_free"), 16, Color(Look.GOLD, stage_k), Color(Look.BG_DEEP, stage_k), HORIZONTAL_ALIGNMENT_CENTER)
	if head_k > 0.0:
		var y := HEAD.y - 64.0
		Look.text_right(ci, Vector2(560, y), I18n.t("arena.box_tier") % shown, 26, Color(ink, head_k))
		Look.text_right(ci, Vector2(560, y + 32), I18n.t("arena.box_guarantee") % shown, Look.TYPE_CAPTION, Color(Look.INK_DIM, head_k))
		var row_y := y + 58
		if anti_air:
			var air := I18n.t("arena.box_air")
			var aw := Look.text_width(air, Look.TYPE_CAPTION)
			Look.text_right(ci, Vector2(560, row_y), air, Look.TYPE_CAPTION, Color(Look.AIR, head_k))
			Look.draw_anti_air(ci, Vector2(560 - aw - 14, row_y), 8.0, Color(Look.AIR, head_k))
			row_y += 22
		if not immune_body.is_empty():
			var imm := "면역 대응 보장"
			var iw := Look.text_width(imm, Look.TYPE_CAPTION)
			Look.text_right(ci, Vector2(560, row_y), imm, Look.TYPE_CAPTION, Color(Look.GOLD, head_k))
			Look.draw_body(ci, Vector2(560 - iw - 14, row_y), 7.0, immune_body)
		for j in range(5):
			_star(ci, Vector2(736 + j * 30, y), 12.0, j < shown, Color(1, 1, 1, head_k))
		Look.text_box(ci, Rect2(722, y + 18, 470, 28), I18n.t("arena.box_hint"), Look.TYPE_CAPTION, Color(Look.INK_DIM, head_k), HORIZONTAL_ALIGNMENT_LEFT)


static func _plate_star(j: int, n: int) -> Vector2:
	return Vector2(640.0 + (j - (n - 1) * 0.5) * 42.0, STAGE.y + 56.0)


## 별 하나 — 찬 별은 금빛, 빈 별은 등급 배지의 두 색(Look.draw_rarity 와 같은 말).
static func _star(ci: CanvasItem, at: Vector2, r: float, on: bool, tint: Color = Color.WHITE) -> void:
	var pts := Look.star_points(at, r, 0.47)
	ci.draw_colored_polygon(Look.star_points(at + Vector2(0, r * 0.12), r * 1.12, 0.47), Color(Look.BG_DEEP, 0.8 * tint.a))
	if on:
		ci.draw_colored_polygon(pts, Color(Look.GOLD, tint.a))
		ci.draw_colored_polygon(Look.star_points(at + Vector2(-r * 0.08, -r * 0.1), r * 0.55, 0.47), Color(Look.IVORY, 0.7 * tint.a))
	else:
		ci.draw_colored_polygon(pts, Color("#39454f", tint.a))
	var line := pts.duplicate()
	line.append(pts[0])
	ci.draw_polyline(line, Color(Look.GOLD if on else Color("#8b9aa5"), tint.a), maxf(1.0, r * 0.08), true)


# --------------------------------------------------------------------------- #
# 카드
# --------------------------------------------------------------------------- #
const RIM := {
	1: [Color("#a9bcc6"), Color("#4f616b"), 5.0],
	2: [Color("#9cc4ff"), Color("#2a4c8c"), 6.0],
	3: [Color("#e6c2ff"), Color("#5a2c90"), 7.0],
	4: [Color("#ffe39a"), Color("#a8601a"), 8.0],
	5: [Color("#fff8e4"), Color("#c9a463"), 9.0],
}


static func _rrect(r: Rect2, rad: float, seg: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for c in range(4):
		for k in range(seg + 1):
			var a := -PI * 0.5 + c * PI * 0.5 + PI * 0.5 * float(k) / seg
			pts.append(Vector2(corners[c]) + Vector2(cos(a), sin(a)) * rad)
	return pts


static func _card_shape() -> PackedVector2Array:
	if _card_outer.is_empty():
		_card_outer = _rrect(Rect2(-CARD * 0.5, CARD), 13.0)
	return _card_outer


static func _card_face_shape(inset: float) -> PackedVector2Array:
	var key := int(inset * 10.0)
	if not _card_inner.has(key):
		_card_inner[key] = _rrect(Rect2(-CARD * 0.5 + Vector2(inset, inset), CARD - Vector2(inset, inset) * 2.0), maxf(4.0, 13.0 - inset * 0.6))
	return _card_inner[key]


static func _vgrad(pts: PackedVector2Array, top: Color, bottom: Color, y0: float, y1: float) -> PackedColorArray:
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for k in range(pts.size()):
		cols[k] = top.lerp(bottom, clampf((pts[k].y - y0) / (y1 - y0), 0.0, 1.0))
	return cols


## 카드 한 장을 그 자세대로. 앞면이면 원화·별·이름·문양·딱지, 뒷면이면 별 문장.
var _face_tier := -1
var _face_pop := 0.0


func _draw_card(ci: CanvasItem, card: Dictionary, st: Dictionary, shake: Vector2, age: float) -> void:
	var sc := float(st["scale"])
	var a := float(st["alpha"])
	if sc <= 0.01 or a <= 0.01:
		return
	var pos: Vector2 = Vector2(st["pos"]) + shake * 0.6
	var xf := Transform2D(float(st["rot"]), pos) * Transform2D(Vector2(float(st["sx"]) * sc, float(st["skew"]) * sc), Vector2(0, float(st["sy"]) * sc), Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)
	# 날아가는 동안의 그림자는 아래로 떨어진다.
	ci.draw_colored_polygon(_shift(_card_shape(), Vector2(0, 8)), Color(0, 0, 0, 0.45 * a))
	if bool(st["face"]):
		_draw_face(ci, card, a, float(st["reveal"]), age)
	else:
		_draw_back(ci, a, float(st["charge"]), int(card.get("stars", 1)), age)
	var white := float(st["white"])
	if white > 0.01:
		ci.draw_colored_polygon(_card_shape(), Color(1, 1, 1, white * a * 0.8))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _shift(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for k in range(pts.size()):
		out[k] = pts[k] + d
	return out


## 뒷면: 깊은 밤빛 판, 금빛 이중 테, 가운데 소울 스톤을 품은 여덟 꼭지 별 문장.
func _draw_back(ci: CanvasItem, a: float, charge: float, stars: int, age: float) -> void:
	var outer := _card_shape()
	ci.draw_polygon(outer, _vgrad(outer, Color(0.27, 0.38, 0.5, a), Color(0.07, 0.12, 0.19, a), -160, 160))
	var face := _card_face_shape(6.0)
	ci.draw_polygon(face, _vgrad(face, Color(0.09, 0.19, 0.3, a), Color(0.035, 0.07, 0.12, a), -154, 154))
	var gold := Color(Look.GOLD, 0.75 * a)
	var inner := _card_face_shape(14.0)
	var line := inner.duplicate()
	line.append(inner[0])
	ci.draw_polyline(line, gold, 1.6, true)
	var inner2 := _card_face_shape(19.0)
	var line2 := inner2.duplicate()
	line2.append(inner2[0])
	ci.draw_polyline(line2, Color(Look.GOLD_DEEP, 0.7 * a), 1.0, true)
	for cx in [-1.0, 1.0]:
		for cy in [-1.0, 1.0]:
			Look.draw_diamond(ci, Vector2(cx * 72, cy * 134), 6.0, gold)
	# 문장: 둥근 테 · 여덟 꼭지 별 · 소울 스톤.
	ci.draw_arc(Vector2.ZERO, 50, 0, TAU, 48, Color(Look.GOLD, 0.6 * a), 2.0, true)
	ci.draw_arc(Vector2.ZERO, 58, 0, TAU, 48, Color(Look.GOLD_DEEP, 0.5 * a), 1.0, true)
	for sq in range(2):
		var pts := PackedVector2Array()
		for k in range(4):
			var ang := PI * 0.25 * sq + PI * 0.5 * k
			pts.append(Vector2(cos(ang), sin(ang)) * 40.0)
		ci.draw_colored_polygon(pts, Color(Look.GOLD_DEEP.darkened(0.2), 0.85 * a))
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(Look.GOLD, 0.8 * a), 1.4, true)
	var spin := age * 0.6
	for k in range(8):
		var ang := spin + TAU * k / 8.0
		ci.draw_circle(Vector2(cos(ang), sin(ang)) * 50.0, 2.2, Color(Look.STARLIGHT, 0.7 * a), true, -1, true)
	Look.draw_crystal(ci, Vector2(0, 4), 15.0, true, 0.4 + 0.6 * charge)
	for n in range(9):
		var p := Vector2(fposmod(n * 53.0, 150.0) - 75.0, fposmod(n * 97.0, 270.0) - 135.0)
		if p.length() > 66.0:
			ci.draw_circle(p, 1.2, Color(Look.STARLIGHT, 0.35 * a), true, -1, true)
	if charge > 0.0:
		# 빛을 모으는 카드: 테두리가 그 등급의 빛으로 달아오른다.
		var col := tier_light(stars)
		var rim := outer.duplicate()
		rim.append(outer[0])
		ci.draw_polyline(rim, Color(col.lightened(0.4), charge * a), 3.0 + 3.0 * charge, true)


## 앞면: 속성색 판(영웅 카드의 규칙) + 등급의 테(1성 강철 … 5성 백금 프리즘).
func _draw_face(ci: CanvasItem, card: Dictionary, a: float, reveal: float, age: float) -> void:
	var unit: Dictionary = card.get("unit", {})
	var s := clampi(int(card.get("stars", 1)), 1, 5)
	var elem := String(unit.get("elem", "none"))
	var rim: Array = RIM[s]
	var rim_top: Color = rim[0]
	var rim_bottom: Color = rim[1]
	var w: float = rim[2]
	var outer := _card_shape()
	ci.draw_polygon(outer, _vgrad(outer, Color(rim_top, a), Color(rim_bottom, a), -160, 160))
	if s == 5:
		# 백금 테 위로 무지개가 천천히 돈다.
		var cols := PackedColorArray()
		cols.resize(outer.size())
		for k in range(outer.size()):
			var h := fposmod(float(k) / outer.size() + age * 0.18, 1.0)
			cols[k] = Color.from_hsv(h, 0.32, 1.0, 0.55 * a)
		ci.draw_polygon(outer, cols)
	var face := _card_face_shape(w)
	var base := Look.hero_card_face(elem)
	ci.draw_polygon(face, _vgrad(face, Color(base.lightened(0.10), a), Color(base.darkened(0.35), a), -150, 150))
	# 원화 뒤의 속성 빛 웅덩이.
	ci.draw_texture_rect(glow_tex(), Rect2(Vector2(-110, -170), Vector2(220, 220)), false, Color(Balance.elem_color(elem), 0.30 * a))
	# 이미 가진 영웅의 카드는 고르면 될 그 등급의 모습(장비)으로 — 카드 별의 모습이 아니라.
	var pv: Dictionary = card.get("preview", {})
	var look := s * 2 - 1
	if String(pv.get("kind", "new")) == "growth":
		look = clampi(int(pv.get("after_tier", look)), 0, 9)
	Art.draw_unit_fit(ci, unit, Rect2(-86, -140, 172, 168), Color(1, 1, 1, a), look)
	# 아래 글자판.
	ci.draw_rect(Rect2(-CARD.x * 0.5 + w, 36, CARD.x - w * 2.0, 2), Color(rim_top, 0.5 * a))
	ci.draw_polygon(PackedVector2Array([Vector2(-CARD.x * 0.5 + w, 38), Vector2(CARD.x * 0.5 - w, 38),
		Vector2(CARD.x * 0.5 - w, 160 - w - 4), Vector2(-CARD.x * 0.5 + w, 160 - w - 4)]),
		PackedColorArray([Color(0, 0, 0, 0.35 * a), Color(0, 0, 0, 0.35 * a), Color(0, 0, 0, 0.55 * a), Color(0, 0, 0, 0.55 * a)]))
	Look.draw_elem(ci, Vector2(-CARD.x * 0.5 + w + 16, -160 + w + 16), 11.0, elem)
	if Balance.anti_air(unit):
		Look.draw_anti_air(ci, Vector2(CARD.x * 0.5 - w - 16, -160 + w + 16), 10.0)
	_draw_ornaments(ci, s, w, a, age)
	# 별: 앞면이 보인 뒤 하나씩 박힌다(4성부터 더 느리게 — 다시 센다).
	var gap := 0.05 if s < SHOWY else 0.09
	if _face_tier >= 0:
		# 조커 · 도박꾼의 눈: 고른 뒤에 별 줄이 최종 등급으로 오른다(반 별은 분홍).
		for j in range(5):
			var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - _face_pop / 0.25) if j >= s - 1 else 1.0
			_star_tier(ci, Vector2((j - 2) * 25.0, 58), 10.5 * pop, _face_tier, j, Color(1, 1, 1, a))
	for j in range(5):
		if _face_tier >= 0:
			break
		var on := j < s
		var at := Vector2((j - 2) * 25.0, 58)
		var pop := 1.0
		var vis := 1.0
		if on and reveal < 9.0:
			var t := reveal - 0.04 - j * gap
			vis = 1.0 if t >= 0.0 else 0.0
			pop = 1.0 + 0.9 * maxf(0.0, 1.0 - t / 0.18) if t >= 0.0 else 1.0
		_star(ci, at, 10.5 * pop, on and vis > 0.0, Color(1, 1, 1, a))
	Look.text_center_fit(ci, Vector2(0, 88), Look.unit_name(unit), 22, Color(Look.INK, a), CARD.x - w * 2.0 - 12.0, 14)
	_draw_mini_chips(ci, SummonArt.trait_labels(unit), Vector2(0, 118), CARD.x - w * 2.0 - 10.0, a)
	_draw_badge(ci, card, a, reveal)
	if bool(card.get("guaranteed", false)):
		_draw_seal(ci, s, w, a)


## 등급의 장식: 3성 모서리 보석, 4성 금 문장과 보석, 5성 별 보석과 모서리 별.
static func _draw_ornaments(ci: CanvasItem, s: int, w: float, a: float, age: float) -> void:
	var col := tier_light(s)
	var hx := CARD.x * 0.5 - w * 0.5
	var hy := CARD.y * 0.5 - w * 0.5
	if s >= 3:
		for cx in [-1.0, 1.0]:
			for cy in [-1.0, 1.0]:
				var p := Vector2(cx * (hx - 2), cy * (hy - 2))
				Look.draw_diamond(ci, p, w * 0.9, Color(Look.BG_DEEP, 0.8 * a))
				Look.draw_diamond(ci, p, w * 0.65, Color(col.lightened(0.25) if s < 5 else Color.from_hsv(fposmod(age * 0.2 + cx * 0.25 + cy * 0.1, 1.0), 0.3, 1.0), a))
	if s >= 4:
		var top := Vector2(0, -CARD.y * 0.5 + 2)
		var mount: Color = (RIM[s] as Array)[1]
		ci.draw_colored_polygon(PackedVector2Array([top + Vector2(-26, 0), top + Vector2(26, 0), top + Vector2(14, 12), top + Vector2(-14, 12)]), Color(mount, a))
		if s == 4:
			ci.draw_circle(top + Vector2(0, 4), 8.0, Color(Look.BG_DEEP, a), true, -1, true)
			ci.draw_circle(top + Vector2(0, 4), 6.5, Color("#ff9a3c", a), true, -1, true)
			ci.draw_circle(top + Vector2(-2, 2), 2.2, Color(1, 0.95, 0.8, a), true, -1, true)
		else:
			ci.draw_colored_polygon(Look.star_points(top + Vector2(0, 4), 11.0, 0.45), Color(Look.BG_DEEP, a))
			ci.draw_colored_polygon(Look.star_points(top + Vector2(0, 4), 9.0, 0.45), Color(Look.IVORY, a))
			ci.draw_colored_polygon(Look.star_points(top + Vector2(-1, 3), 4.0, 0.45), Color(1, 1, 1, a))


## 작은 성격 칩: 공격 방식(수정빛) · 대공(하늘빛) · 나머지(금빛). 넘치면 뒤를 덜어낸다.
static func _draw_mini_chips(ci: CanvasItem, labels: Array, center: Vector2, max_w: float, a: float) -> void:
	var size := 14
	var widths: Array = []
	var total := 0.0
	var shown: Array = []
	for label in labels:
		var text := I18n.t(String(label))
		var wd := Look.text_width(text, size) + 14.0
		if total + wd + (6.0 if not shown.is_empty() else 0.0) > max_w:
			break
		total += wd + (6.0 if not shown.is_empty() else 0.0)
		widths.append(wd)
		shown.append(String(label))
	var x := center.x - total * 0.5
	for k in range(shown.size()):
		var label := String(shown[k])
		var wd: float = widths[k]
		var air := label == "대공"
		var tint := Look.AIR if air else (Look.CRYSTAL if k == 0 else Look.GOLD)
		var r := Rect2(x, center.y - 11, wd, 22)
		Look.fill_round(ci, r, 3, Color(tint.darkened(0.55), a))
		Look.fill_round(ci, r.grow(-1), 2, Color(Look.BG_DEEP.lerp(tint, 0.10), a))
		Look.text_center(ci, r.get_center(), label, size, Color(tint, a))
		x += wd + 6.0


## NEW · 강화 +N · 최대 — 원화 발치에 걸친 딱지.
static func _draw_badge(ci: CanvasItem, card: Dictionary, a: float, reveal: float) -> void:
	var pv: Dictionary = card.get("preview", {})
	if pv.is_empty():
		return
	var k := 1.0 if reveal >= 9.0 else clampf((reveal - 0.12) / 0.16, 0.0, 1.0)
	if k <= 0.0:
		return
	var pop := 1.0 + 0.35 * (1.0 - _ease_out(k))
	if bool(pv.get("joker", false)):
		# 「조커」: 고르면 한 별 더 — 별 줄 오른쪽 위의 분홍 +1★.
		var jr := Rect2(57, 33, 34, 16)
		Look.fill_round(ci, jr.grow(1.5), 5, Color(Look.BG_DEEP, 0.85 * a * k))
		Look.fill_round(ci, jr, 4, Color(PINK, a * k))
		Look.text_center(ci, Vector2(jr.position.x + 11, jr.get_center().y), "+1", 12, Color(Look.BG_DEEP, a * k))
		ci.draw_colored_polygon(Look.star_points(Vector2(jr.end.x - 9, jr.get_center().y), 5.0, 0.46), Color(Look.BG_DEEP, a * k))
	# 새 영웅은 언제나 「새 영웅」(최고 등급으로 와도). 이미 가진 영웅의 카드는 그 영웅이 몇 별에서 몇 별이 되는지
	# (끝까지 오르면 MAX) — 카드의 별 줄만 보고 「5성 영웅」으로 읽지 않게.
	if String(pv.get("kind", "new")) != "growth":
		var label := I18n.t("arena.box_new")
		var wd := (Look.text_width(label, 15) + 20.0) * pop
		var r := Rect2(-wd * 0.5, 22 - 12 * pop, wd, 24 * pop)
		Look.fill_round(ci, r.grow(2), 6, Color(Look.BG_DEEP, 0.85 * a * k))
		Look.fill_round(ci, r, 5, Color(Look.GREEN, a * k))
		Look.text_center(ci, r.get_center(), label, int(15 * pop), Color(Look.BG_DEEP, a * k))
		return
	var word := I18n.t("강화")
	var before := _star_number(int(pv.get("before_tier", 0)))
	var after := "MAX" if bool(pv.get("maxed", false)) else _star_number(int(pv.get("after_tier", 0)))
	var fs := 15
	var w_word := Look.text_width(word, fs)
	var w_b := Look.text_width(before, fs)
	var w_a := Look.text_width(I18n.t(after), fs)
	var top := bool(pv.get("maxed", false))
	var wd := (10.0 + w_word + 10.0 + 12.0 + 2.0 + w_b + 16.0 + (0.0 if top else 14.0) + w_a + 10.0) * pop
	var r := Rect2(-wd * 0.5, 22 - 12 * pop, wd, 24 * pop)
	var face := Look.GOLD if bool(pv.get("maxed", false)) else Look.CRYSTAL
	Look.fill_round(ci, r.grow(2), 6, Color(Look.BG_DEEP, 0.85 * a * k))
	Look.fill_round(ci, r, 5, Color(face, a * k))
	var ink := Color(Look.BG_DEEP, a * k)
	var cy := r.get_center().y
	var x := r.position.x + 10.0 * pop
	var sz := int(fs * pop)
	Look.text_left(ci, Vector2(x, cy), word, sz, ink)
	x += (w_word + 10.0) * pop
	ci.draw_colored_polygon(Look.star_points(Vector2(x + 6.0 * pop, cy), 6.0 * pop, 0.46), ink)
	x += 14.0 * pop
	Look.text_left(ci, Vector2(x, cy), before, sz, ink)
	x += (w_b + 4.0) * pop
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x, cy - 5 * pop), Vector2(x + 7 * pop, cy), Vector2(x, cy + 5 * pop)]), ink)
	x += 12.0 * pop
	if not top:
		ci.draw_colored_polygon(Look.star_points(Vector2(x + 6.0 * pop, cy), 6.0 * pop, 0.46), ink)
		x += 14.0 * pop
	Look.text_left(ci, Vector2(x, cy), after, sz, ink)


## 반 별 단위 등급의 별 수를 숫자로: 칸 0 → 「0.5」, 1 → 「1」, 2 → 「1.5」 …
static func _star_number(t: int) -> String:
	var cells := clampi(t, 0, 9) + 1
	return str(cells / 2) if cells % 2 == 0 else ("%.1f" % (float(cells) * 0.5))


## 보장 카드의 인장: 오른쪽 위 모서리에 상자 별을 품은 작은 깃발.
static func _draw_seal(ci: CanvasItem, s: int, w: float, a: float) -> void:
	var x := -CARD.x * 0.5 + w + 2.0
	var y := -CARD.y * 0.5 + w + 44.0
	var label := "보장"
	var wd := Look.text_width(I18n.t(label), 13) + 26.0
	var r := Rect2(x, y - 11, wd, 22)
	# 왼쪽 테에 붙고 오른쪽 끝이 제비꼬리인 작은 깃발.
	var tail := r.end.x + 7.0
	ci.draw_colored_polygon(PackedVector2Array([r.position - Vector2(1, 1), Vector2(tail + 1, r.position.y - 1), Vector2(r.end.x + 1, y), Vector2(tail + 1, r.end.y + 1), Vector2(r.position.x - 1, r.end.y + 1)]), Color(Look.BG_DEEP, 0.85 * a))
	ci.draw_colored_polygon(PackedVector2Array([r.position, Vector2(tail, r.position.y), Vector2(r.end.x, y), Vector2(tail, r.end.y), Vector2(r.position.x, r.end.y)]), Color(Look.GOLD, a))
	ci.draw_colored_polygon(Look.star_points(r.position + Vector2(10, 11), 5.5, 0.45), Color(Look.BG_DEEP, a))
	Look.text_center(ci, r.get_center() + Vector2(6, 0), label, 13, Color(Look.BG_DEEP, a))


## 카드 뒤의 은은한 등급 빛(3성부터) — 보통 섞기 층, 카드 밑에.
func _draw_card_aura(ci: CanvasItem, card: Dictionary, st: Dictionary, shake: Vector2, age: float) -> void:
	var s := clampi(int(card.get("stars", 1)), 1, 5)
	var reveal := float(st["reveal"])
	var charge := float(st["charge"])
	var k := clampf(reveal / 0.3, 0.0, 1.0) if reveal >= 0.0 else 0.0
	var amount := 0.0
	if s >= 3:
		amount = k * [0.0, 0.0, 0.0, 0.20, 0.30, 0.36][s]
	amount = maxf(amount, charge * 0.5)
	if amount <= 0.01:
		return
	var a := float(st["alpha"])
	var col := tier_light(s)
	var light := col.lightened(0.3)
	var pos: Vector2 = Vector2(st["pos"]) + shake * 0.6
	var pulse := 0.85 + 0.15 * sin(age * 3.0 + pos.x * 0.01)
	# 빛살은 카드 뒤에서 나온다: 빛 모으기 · 열리는 순간 · 열린 뒤의 잔광(4성 느린 금빛, 5성 무지개).
	if charge > 0.01:
		_rays(ci, pos, 12 if s == 4 else 18, (210.0 + 170.0 * charge) * (1.0 if s == 4 else 1.3), age * 1.2, light, 0.42 * charge * a, s == 5)
	if s >= SHOWY and reveal >= 0.0 and reveal < 1.6:
		var f := exp(-1.3 * reveal)
		_rays(ci, pos, 14 if s == 4 else 22, (440.0 if s == 4 else 640.0) * (0.7 + 0.3 * _ease_out(reveal / 0.3)), age * 0.5, light, 0.55 * f * a, s == 5)
	if s >= SHOWY and reveal >= 0.3:
		_rays(ci, pos, 10 if s == 4 else 14, 250.0 if s == 4 else 300.0, age * 0.25, light, (0.16 if s == 4 else 0.2) * a * minf(1.0, (reveal - 0.3) / 0.5), s == 5)
	var r := CARD * Vector2(0.95, 0.75) * float(st["scale"])
	ci.draw_texture_rect(glow_tex(), Rect2(pos - r, r * 2.0), false, Color(col, amount * pulse * a))


# --------------------------------------------------------------------------- #
# 단추 · 안내 · 존
# --------------------------------------------------------------------------- #
func _draw_ui(ci: CanvasItem, ui: Ui, age: float, pick_age: float) -> void:
	if pick_age >= 0.0:
		ui.zone(SCREEN, "modal:block")
		return
	# Until the cards settle the whole screen skips; from then the buttons arm (their zones stay off
	# until `ready`), so a finger tapping through the ceremony lands on nothing.
	if age < float(plan.get("settle", 0.0)):
		ui.zone(SCREEN, "box:skip")
		var hint := clampf((age - 0.5) / 0.4, 0.0, 1.0)
		if hint > 0.0:
			Look.text_center(ci, Vector2(640, 764), "화면을 누르면 건너뜁니다.", Look.TYPE_CAPTION, Color(Look.INK_MUTE, hint))
		return
	ui.zone(SCREEN, "modal:block")
	var settle := float(plan.get("settle", 0.0))
	var ready_t := float(plan.get("ready", settle))
	var k := _ease_out((age - settle) / 0.3)
	var drop := (1.0 - k) * 24.0
	# 무장: 단추가 올라오는 동안 테두리가 금빛으로 채워지고, 다 차면 금빛 단추로 한 번 빛난다.
	var arm := clampf((age - settle) / maxf(0.001, ready_t - settle), 0.0, 1.0)
	var armed := age >= ready_t
	var armed_age := age - ready_t
	for i in range(cards.size()):
		var slot := _slot(i, cards.size())
		ui.zone(Rect2(slot - CARD * 0.5, CARD), "box:pick:%d" % i, armed)
		var b := Rect2(slot.x - CARD.x * 0.5, slot.y + CARD.y * 0.5 + 12 + drop, CARD.x, PICK_H)
		_arm_button(ci, ui, b, I18n.t("arena.box_pick"), "box:pick:%d" % i, arm, armed, armed_age, Look.GOLD, 22)
	# 다시 뽑기: 조작명 + 따로 난 칸(남은 무료 횟수). 누를 수 없으면 꺼진 단추, 무장 중엔 초록 테가 채워진다.
	var rb := Rect2(REROLL.position + Vector2(0, drop), REROLL.size)
	var on := can_reroll and free_rerolls > 0
	var live := on and armed
	if on and not armed:
		_arm_button(ci, ui, rb, "", "box:reroll", arm, false, armed_age, Look.GREEN, Look.TYPE_BUTTON_2)
	else:
		ui.button(ci, rb, "", "box:reroll", live, Look.GREEN if live else Look.PANEL_EDGE, Look.TYPE_BUTTON_2)
		if live and armed_age < 0.35:
			var f := 1.0 - armed_age / 0.35
			Look.fill_round(ci, rb.grow(2.0 + 6.0 * (1.0 - f)), 8, Color(Look.GREEN.lightened(0.4), 0.30 * f))
	var down := live and ui.pressed == "box:reroll"
	var cell := Rect2(rb.end.x - 118, rb.position.y + 11 + (2 if down else 0), 104, 36)
	Look.fill_round(ci, cell, 5, Color(Look.BG_DEEP, 0.55))
	var ink := Look.INK if live else (Color(Look.INK, 0.45 + 0.35 * arm) if on else Look.INK_MUTE)
	Look.text_box(ci, Rect2(rb.position.x + 16, rb.position.y + 4 + (2 if down else 0), rb.size.x - 146, 50), I18n.t("arena.box_reroll"), Look.TYPE_BUTTON_2, ink)
	Look.text_box(ci, cell.grow(-5), I18n.t("arena.box_free_n") % free_rerolls, 19, Look.GREEN if live else (Color(Look.GREEN, 0.5) if on else Look.INK_MUTE))
	Look.text_center(ci, Vector2(640, rb.end.y + 26), "상자 등급은 내려가지 않지만 카드 %d장은 새로 뽑습니다." % cards.size(), Look.TYPE_CAPTION, Color(Look.INK_DIM, k))


## A button that arms (the level-up popup's language): before it is armed a dark plate whose rim
## fills clockwise from the top with `accent` as `arm` goes 0..1, the label waiting dim, its zone off;
## armed, the ordinary button that flashes once.
static func _arm_button(ci: CanvasItem, ui: Ui, rect: Rect2, label: String, id: String, arm: float, armed: bool,
		armed_age: float, accent: Color, size: int) -> void:
	if armed:
		ui.button(ci, rect, label, id, true, accent, size)
		if armed_age < 0.35:
			var f := 1.0 - armed_age / 0.35
			Look.fill_round(ci, rect.grow(2.0 + 6.0 * (1.0 - f)), 8, Color(Look.IVORY if accent == Look.GOLD else accent.lightened(0.4), 0.32 * f))
		return
	ui.zone(rect, id, false)
	var p := clampf(arm, 0.0, 1.0)
	Look.fill_round(ci, rect, 7, Color(0.02, 0.05, 0.08, 0.92))
	Look.fill_round(ci, rect.grow(-2.0), 6, accent.darkened(0.72))
	var outline := _outline(rect.grow(-1.0), 7.0)
	ci.draw_polyline(outline, Color(accent.darkened(0.35), 0.55), 1.4, true)
	if p > 0.0:
		var part := _partial(outline, p)
		ci.draw_polyline(part, accent, 3.0, true)
		if p < 1.0 and part.size() > 0:
			_sparkle(ci, part[part.size() - 1], 7.0, 0.0, Color(1, 1, 1, 0.95))
	if not label.is_empty():
		Look.text_box(ci, Rect2(rect.position + Vector2(12, 2), rect.size - Vector2(24, 4)), label, size, Color(accent, 0.38 + 0.30 * p))


static func _outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array([Vector2(rect.get_center().x, rect.position.y)])
	var corners := [[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5], [Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5], [Vector2(rect.position.x + r, rect.position.y + r), PI]]
	for corner in corners:
		var centre: Vector2 = corner[0]
		var start: float = corner[1]
		for k in range(7):
			pts.append(centre + Vector2.from_angle(start + PI * 0.5 * float(k) / 6.0) * r)
	pts.append(Vector2(rect.get_center().x, rect.position.y))
	return pts


static func _partial(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var want := total * clampf(fraction, 0.0, 1.0)
	var out := PackedVector2Array([points[0]])
	var run := 0.0
	for i in range(1, points.size()):
		var step := points[i - 1].distance_to(points[i])
		if run + step >= want:
			out.append(points[i - 1].lerp(points[i], (want - run) / maxf(step, 0.0001)))
			return out
		run += step
		out.append(points[i])
	return out


# --------------------------------------------------------------------------- #
# 고른 뒤의 결과
# --------------------------------------------------------------------------- #
func _draw_result(ci: CanvasItem, ui: Ui, pick_age: float) -> void:
	if picked < 0:
		return
	var card: Dictionary = cards[picked]
	var unit: Dictionary = card.get("unit", {})
	var pv: Dictionary = card.get("preview", {})
	var res := result
	var grown := String(res.get("kind", pv.get("kind", "new"))) == "growth"
	var after := int(res.get("after_tier", pv.get("after_tier", int(card.get("stars", 1)) * 2 - 1)))
	var before := int(res.get("before_tier", pv.get("before_tier", after)))
	var x := 600.0
	var wd := 520.0
	var rows := [0.55, 0.62, 0.69, 0.76, 0.83, 0.90]
	var k := func(n: int) -> float: return _ease_out((pick_age - float(rows[n])) / 0.22)
	var a0: float = k.call(0)
	if a0 > 0.0:
		Look.text_box(ci, Rect2(x, 214 - (1.0 - a0) * 10, wd, 40), I18n.t("arena.hero_grown") if grown else I18n.t("arena.new_hero"), 30, Color(Look.GOLD, a0), HORIZONTAL_ALIGNMENT_LEFT)
	var a1: float = k.call(1)
	if a1 > 0.0:
		Look.text_box(ci, Rect2(x, 260 - (1.0 - a1) * 10, wd, 52), Look.unit_name(unit), 40, Color(Look.INK, a1), HORIZONTAL_ALIGNMENT_LEFT)
	var a2: float = k.call(2)
	if a2 > 0.0:
		var y := 340.0 - (1.0 - a2) * 10
		var sx := x + 14.0
		if grown:
			for j in range(5):
				_star_tier(ci, Vector2(sx + j * 26, y), 11.0, before, j, Color(1, 1, 1, a2 * 0.7))
			sx += 5 * 26 + 18
			ci.draw_colored_polygon(PackedVector2Array([Vector2(sx, y - 9), Vector2(sx + 12, y), Vector2(sx, y + 9)]), Color(Look.GOLD, a2))
			sx += 34
		for j in range(5):
			_star_tier(ci, Vector2(sx + j * 34, y), 15.0, after, j, Color(1, 1, 1, a2))
		Look.text_left(ci, Vector2(sx + 5 * 34 + 6, y), Look.star_label(after), 26, Color(tier_light((after + 1) / 2).lightened(0.3), a2))
	var a3: float = k.call(3)
	if a3 > 0.0:
		SummonArt.draw_chips(ci, SummonArt.trait_labels(unit), Rect2(x, 380 - (1.0 - a3) * 10, wd, 34))
	var a4: float = k.call(4)
	# A new hero that arrives at the top grade has nothing to grow: the row stays empty (its stars say it).
	if a4 > 0.0 and (grown or not bool(res.get("maxed", pv.get("maxed", false)))):
		var y := 448.0 - (1.0 - a4) * 10
		if bool(res.get("maxed", pv.get("maxed", false))):
			Look.fill_round(ci, Rect2(x, y, 300, 50), 6, Color(Look.GOLD, 0.16 * a4))
			Look.text_box(ci, Rect2(x + 12, y + 6, 276, 38), I18n.t("arena.maxed"), 26, Color(Look.GOLD, a4), HORIZONTAL_ALIGNMENT_LEFT)
		else:
			var pts := int(res.get("growth_points", 0))
			var need := maxi(1, int(res.get("growth_needed", 10)))
			var added := int(res.get("added_points", pv.get("added_points", 0)))
			var label := I18n.t("arena.growth_points") + ("  +%d" % added if grown else "")
			Look.text_box(ci, Rect2(x, y, wd, 30), label, Look.TYPE_HEADING, Color(Look.CRYSTAL, a4), HORIZONTAL_ALIGNMENT_LEFT)
			var fill := float(pts) / float(need)
			var from := float(maxi(0, pts - added)) / float(need) if grown else fill
			var f := lerpf(from, fill, _ease_out((pick_age - float(rows[4]) - 0.15) / 0.5))
			var bar := Rect2(x, y + 44, 360, 12)
			Look.fill_round(ci, bar.grow(2), 4, Color(Look.BG_DEEP, a4))
			Look.fill_round(ci, bar, 3, Color("#30434a", a4))
			if f > 0.0:
				Look.fill_round(ci, Rect2(bar.position, Vector2(bar.size.x * clampf(f, 0.0, 1.0), bar.size.y)), 3, Color(Look.CRYSTAL, a4))
			Look.text_left(ci, Vector2(bar.end.x + 16, bar.get_center().y), "%d / %d" % [pts, need], 20, Color(Look.INK, a4))
	var a5: float = k.call(5)
	if a5 > 0.0:
		var where := String(res.get("where", pv.get("where", "field")))
		Look.text_box(ci, Rect2(x, 528, wd, 30), I18n.t("arena.bench") if where == "bench" else I18n.t("arena.heroes"), Look.TYPE_BODY, Color(Look.INK_DIM, a5), HORIZONTAL_ALIGNMENT_LEFT)
		var tags: Array = []
		if bool(res.get("joker", false)):
			tags.append("조커 · 별 하나 더")
		if bool(res.get("bumped", false)):
			tags.append("도박꾼의 눈 · +0.5성")
		var tx := x
		var tk := _ease_out((pick_age - 0.9) / 0.25)
		for tag in tags:
			var tw := Look.text_width(I18n.t(tag), 18) + 26.0
			var tr := Rect2(tx, 572, tw, 34)
			Look.fill_round(ci, tr, 5, Color(PINK.darkened(0.55), tk))
			Look.fill_round(ci, tr.grow(-1), 4, Color(Look.BG_DEEP.lerp(PINK, 0.12), tk))
			Look.text_center(ci, tr.get_center(), tag, 18, Color(PINK.lightened(0.2), tk))
			tx += tw + 10.0
	var ready_k := _ease_out((pick_age - 0.95) / 0.2)
	if ready_k > 0.0:
		var b := Rect2(344, 680 + (1.0 - ready_k) * 20, 592, 58)
		if pick_age >= RESULT_READY:
			ui.button(ci, b, I18n.t("arena.result_continue"), "close", true, Look.GOLD, 24)
		else:
			ui.button(ci, b, I18n.t("arena.result_continue"), "modal:block", false, Look.GOLD, 24)


## 반 별 단위 등급의 j 번째 별(결과 화면 — 도박꾼의 눈으로 반 별이 붙을 수 있다).
static func _star_tier(ci: CanvasItem, at: Vector2, r: float, t: int, j: int, tint: Color) -> void:
	var cells := clampi(t, 0, 9) + 1
	if cells >= j * 2 + 2:
		_star(ci, at, r, true, tint)
	elif cells == j * 2 + 1:
		_star(ci, at, r, false, tint)
		var pts := Look.star_points(at, r, 0.47)
		ci.draw_colored_polygon(PackedVector2Array([pts[0], pts[5], pts[6], pts[7], pts[8], pts[9]]), Color(PINK, tint.a))
	else:
		_star(ci, at, r, false, tint)


# --------------------------------------------------------------------------- #
# 그리기 — 더하기 섞기(빛) 층
# --------------------------------------------------------------------------- #
func draw_light(ci: CanvasItem, age: float, pick_age: float) -> void:
	if plan.is_empty():
		return
	var shake := _shake(age)
	var box := _box(age, pick_age)
	_draw_motes(ci, age, pick_age)
	_draw_box_light(ci, box, age, shake)
	for i in range(cards.size()):
		var st := _card(i, age, pick_age)
		if bool(st["show"]):
			_draw_card_light(ci, i, st, age, shake)
	if rerolled:
		for i in range(old_cards.size()):
			var st := _old_card(i, age)
			if bool(st["show"]) and bool(st["fly"]):
				_trail(ci, st, Color(0.75, 0.85, 1.0))
	_draw_particles(ci, true)


## 화면 섬광: 터짐 · 4성 이상 카드 · 고르기 · 건너뛰기. 단추와 글 위에 한순간.
func _draw_flash(ci: CanvasItem, age: float, pick_age: float) -> void:
	if plan.is_empty():
		return
	var flash := 0.0
	var col := Color(1, 0.96, 0.85)
	var d := age - float(plan["burst"])
	if d >= 0.0:
		flash = maxf(flash, (0.16 + 0.05 * tier) * exp(-14.0 * d))
	var flip: Dictionary = plan["flip"]
	for i in flip:
		var s := _stars(int(i))
		if s >= SHOWY:
			var r := age - float(flip[i]) - FLIP * 0.5
			if r >= 0.0:
				flash = maxf(flash, (0.16 if s == 4 else 0.30) * exp(-10.0 * r))
	if pick_age >= 0.0:
		flash = maxf(flash, 0.18 * exp(-10.0 * pick_age))
	if age >= _skip_at and age - _skip_at < 0.5:
		flash = maxf(flash, 0.32 * exp(-11.0 * (age - _skip_at)))
	if flash > 0.004:
		ci.draw_rect(SCREEN, Color(col, flash))


## 떠도는 먼지 빛 — 상태 없이 시각과 번호로 자리를 셈한다.
func _draw_motes(ci: CanvasItem, age: float, pick_age: float) -> void:
	var glow := glow_tex()
	var a := 1.0 if pick_age < 0.0 else maxf(0.3, 1.0 - pick_age)
	for n in range(26):
		var h := fposmod(n * 0.6180339 + 0.13, 1.0)
		var sp := 14.0 + 22.0 * h
		var y := 800.0 - fposmod(age * sp + h * 900.0, 860.0)
		var x := 640.0 + (h - 0.5) * 1100.0 + sin(age * 0.6 + n) * 24.0
		var r := 2.0 + 3.0 * fposmod(n * 0.37, 1.0)
		var tw := 0.5 + 0.5 * sin(age * 1.7 + n * 2.1)
		ci.draw_texture_rect(glow, Rect2(Vector2(x, y) - Vector2(r, r) * 2.0, Vector2(r, r) * 4.0), false, Color(0.75, 0.85, 1.0, 0.10 * tw * a))


func _draw_box_light(ci: CanvasItem, st: Dictionary, age: float, shake: Vector2) -> void:
	var t := int(st["tier"])
	var sc := float(st["scale"])
	var a := float(st["alpha"])
	if sc <= 0.01 or a <= 0.01:
		return
	var glow := glow_tex()
	var col := tier_light(t)
	var light := col.lightened(0.35)
	var anchor := _box_anchor(st, shake)
	var scale := Vector2(float(st["sx"]), float(st["sy"])) * sc
	var mouth := _box_mouth(st) + shake
	var big := sc / STAGE_SCALE
	# 기다리는 상자의 금속·보석 위로 이따금 반짝임이 스친다(5성은 자주, 무지개빛).
	if age < float(plan["burst"]) and sc > 0.3:
		var lay := _layout(t)
		var b: Rect2 = lay["bounds"]
		var a0: Vector2 = lay["anchor"]
		var period := 0.75 if t < 5 else 0.42
		var n := int(floor(age / period))
		var u := fposmod(age, period) / period
		var h := fposmod(n * 0.618 + t * 0.13, 1.0)
		var h2 := fposmod(n * 0.381 + 0.5, 1.0)
		var local := Vector2(b.position.x + b.size.x * (0.22 + 0.56 * h), b.position.y + b.size.y * (0.2 + 0.42 * h2)) - a0
		var gp := anchor + Vector2(local.x * scale.x, local.y * scale.y)
		var gcol := Color(1, 1, 1) if t < 5 else Color.from_hsv(h, 0.3, 1.0)
		_sparkle(ci, gp, (12.0 + 4.0 * t) * big * sin(PI * u), age * 2.0, Color(gcol, 0.85 * sin(PI * u) * a))
	# 이음새의 빛: 들썩일 때마다 세지고, 그 위로 가는 빛줄기가 새어 오른다.
	var seam := float(st["seam"])
	if seam > 0.01:
		_blit(ci, t, "seam", anchor, scale, float(st["rot"]), Color(light.r, light.g, light.b, clampf(seam, 0.0, 1.0)))
		_blit(ci, t, "seam", anchor, scale * Vector2(0.98, 0.9), float(st["rot"]), Color(1, 1, 1, clampf(seam - 0.35, 0.0, 1.0) * 0.6))
		var shafts := int(4 + seam * 6)
		for n in range(shafts):
			var h := fposmod(n * 0.618 + 0.21, 1.0)
			var x := (h - 0.5) * 300.0 * big
			var flick := 0.6 + 0.4 * sin(age * 31.0 + n * 2.7)
			var len := (90.0 + 160.0 * h) * big * seam
			var base := mouth + Vector2(x, 6.0 * big)
			var tip := base + Vector2(x * 0.35, -len)
			var wv := (5.0 + 7.0 * h) * big
			ci.draw_polygon(PackedVector2Array([base - Vector2(wv, 0), base + Vector2(wv, 0), tip]),
					PackedColorArray([Color(light, 0.30 * seam * flick), Color(light, 0.30 * seam * flick), Color(light, 0.0)]))
		ci.draw_texture_rect(glow, Rect2(mouth - Vector2(220, 70) * big, Vector2(440, 140) * big), false, Color(light, 0.35 * seam))
	# 터짐: 빛기둥 · 빛살 · 충격 고리 · 입의 빛.
	var d := age - float(plan["burst"])
	if d >= 0.0 and d < 1.6:
		var fade := exp(-1.7 * d)
		var wpill := (54.0 + 20.0 * t) * (1.0 + 0.7 * exp(-9.0 * d)) * big
		_pillar(ci, mouth, wpill, mouth.y + 40.0, light, 0.85 * fade * a, t == 5, age)
		_rays(ci, mouth, 8 + 3 * t, (380.0 + 55.0 * t) * big * (0.6 + 0.4 * _ease_out(d / 0.3)), age * 0.5, light, 0.42 * exp(-2.2 * d), t == 5)
		var rings := 1 + (1 if t >= 3 else 0) + (1 if t == 5 else 0)
		for j in range(rings):
			var dj := d - 0.09 * j
			if dj <= 0.0 or dj > 0.8:
				continue
			var pr := _ease_out(dj / 0.8)
			var rr := (30.0 + (480.0 + 40.0 * t) * pr) * big
			ci.draw_arc(mouth, rr, 0, TAU, 72, Color(light if j != 1 else Look.GOLD, (1.0 - pr) * 0.8), (12.0 * (1.0 - pr) + 1.5) * big, true)
	# 열린 입의 빛 — 머리 자리에서도 잔잔히 남는다.
	if float(st["lid"]) > 30.0:
		var pulse := 0.8 + 0.2 * sin(age * 3.4)
		ci.draw_texture_rect(glow, Rect2(mouth - Vector2(200, 120) * big, Vector2(400, 240) * big), false, Color(light, 0.30 * pulse * a))
		ci.draw_texture_rect(glow, Rect2(mouth - Vector2(80, 50) * big, Vector2(160, 100) * big), false, Color(1, 1, 1, 0.25 * pulse * a))
	# 등급 단이 오르는 순간의 고리.
	var steps_t: Array = plan["steps_t"]
	var steps_d: Array = plan["steps_d"]
	for j in range(steps_t.size()):
		var at := float(steps_t[j]) + float(steps_d[j]) * 0.43
		var dj := age - at
		if dj < 0.0 or dj > 0.5:
			continue
		var g := start_tier + j + 1
		var pr := _ease_out(dj / 0.5)
		var gcol := tier_light(g).lightened(0.35)
		ci.draw_arc(_box_mid(st) + shake, (40.0 + 260.0 * pr) * big, 0, TAU, 64, Color(gcol, (1.0 - pr) * 0.9), (9.0 * (1.0 - pr) + 1.0) * big, true)
		ci.draw_texture_rect(glow, Rect2(_box_mid(st) + shake - Vector2(260, 220) * big, Vector2(520, 440) * big), false, Color(gcol, 0.5 * (1.0 - pr)))


func _draw_card_light(ci: CanvasItem, i: int, st: Dictionary, age: float, shake: Vector2) -> void:
	var s := _stars(i)
	var col := tier_light(s).lightened(0.3)
	var pos: Vector2 = Vector2(st["pos"]) + shake * 0.6
	var glow := glow_tex()
	if bool(st["fly"]):
		_trail(ci, st, Color(0.75, 0.85, 1.0))
	elif not bool(st["face"]) and float(st["charge"]) <= 0.0 and float(st["reveal"]) < 0.0:
		# 기다리는 뒷면 위로 느린 광택이 차례로 지나간다.
		var cycle := fposmod(age * 0.8 - i * 0.18, 1.6)
		if cycle < 0.55:
			_sheen(ci, pos, float(st["scale"]), cycle / 0.55, 0.16)
	# 빛 모으기: 카드 뒤로 빛살이 돌고 테두리가 달아오르며 빛 알갱이가 빨려 든다.
	var charge := float(st["charge"])
	if charge > 0.01:
		var r := CARD * (0.9 + 0.3 * charge)
		ci.draw_texture_rect(glow, Rect2(pos - r, r * 2.0), false, Color(col, 0.30 * charge))
		for n in range(10):
			var h := fposmod(n * 0.618 + age * 1.6, 1.0)
			var ang := n * 2.399
			var p := pos + Vector2(cos(ang), sin(ang)) * (240.0 * (1.0 - h) + 30.0)
			_sparkle(ci, p, 5.0 + 4.0 * h, ang, Color(col, charge * h))
	# 앞면이 보인 순간: 카드의 섬광 · 고리 · (4성부터) 빛살.
	var reveal := float(st["reveal"])
	if reveal >= 0.0 and reveal < 9.0:
		if reveal < 0.7:
			var pr := _ease_out(reveal / 0.7)
			var rings := 1 if s <= 2 else 2
			for j in range(rings):
				var dj := reveal - 0.12 * j
				if dj <= 0.0:
					continue
				var pj := _ease_out(dj / 0.7)
				var rr := 40.0 + (90.0 + 40.0 * s) * pj * (1.6 if s >= SHOWY else 1.0)
				ci.draw_arc(pos, rr, 0, TAU, 56, Color(col if j == 0 else Look.GOLD, (1.0 - pj) * 0.85), 7.0 * (1.0 - pj) + 1.0, true)
			var gr := CARD * (0.7 + 0.5 * pr)
			ci.draw_texture_rect(glow, Rect2(pos - gr, gr * 2.0), false, Color(col, 0.55 * (1.0 - pr)))
		if s >= SHOWY and reveal < 1.6:
			if s == 5 and reveal > 0.25 and reveal < 1.1:
				var pj := _ease_out((reveal - 0.25) / 0.85)
				ci.draw_arc(pos, 60.0 + 420.0 * pj, 0, TAU, 72, Color(Color.from_hsv(fposmod(age * 0.5, 1.0), 0.3, 1.0), (1.0 - pj) * 0.9), 10.0 * (1.0 - pj) + 1.0, true)
	# 열린 뒤에도 남는 빛: 4성 느린 빛살, 5성 무지개 빛살과 테를 도는 별.
	if reveal >= 0.3 or reveal >= 9.0:
		var a := float(st["alpha"])
		if s == 5:
			for n in range(3):
				var u := fposmod(age * 0.22 + n / 3.0, 1.0)
				var p := pos + _rim_point(u) * float(st["scale"])
				_sparkle(ci, p, 9.0, age * 2.0 + n, Color(1, 0.97, 0.9, 0.9 * a))
		if s >= 4:
			# 이따금 앞면을 가로지르는 광택(카드 모양으로 잘라 그린다).
			var cycle := fposmod(age + i * 0.37, 3.2)
			if cycle < 0.6:
				_sheen(ci, pos, float(st["scale"]), cycle / 0.6, 0.35 * a)


## 카드 테두리를 따라 도는 점(0..1).
static func _rim_point(u: float) -> Vector2:
	var hw := CARD.x * 0.5
	var hh := CARD.y * 0.5
	var per := 2.0 * (CARD.x + CARD.y)
	var d := u * per
	if d < CARD.x:
		return Vector2(-hw + d, -hh)
	d -= CARD.x
	if d < CARD.y:
		return Vector2(hw, -hh + d)
	d -= CARD.y
	if d < CARD.x:
		return Vector2(hw - d, hh)
	d -= CARD.x
	return Vector2(-hw, hh - d)


func _sheen(ci: CanvasItem, pos: Vector2, sc: float, u: float, a: float) -> void:
	var x := lerpf(-CARD.x * 0.9, CARD.x * 0.9, u)
	var band := PackedVector2Array([Vector2(x - 26, -CARD.y), Vector2(x + 6, -CARD.y), Vector2(x - 54, CARD.y), Vector2(x - 86, CARD.y)])
	var card := _card_shape()
	var clipped := Geometry2D.intersect_polygons(band, card)
	for poly in clipped:
		var pts := PackedVector2Array()
		for q in poly:
			pts.append(pos + q * sc)
		if pts.size() >= 3:
			ci.draw_colored_polygon(pts, Color(1, 1, 1, a * sin(PI * u)))


func _trail(ci: CanvasItem, st: Dictionary, col: Color) -> void:
	var u := float(st["u"])
	if u <= 0.02 or u >= 1.0:
		return
	var p: Vector2 = st["pos"]
	var glow := glow_tex()
	var r := 46.0 * float(st["scale"])
	ci.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col, 0.28 * (1.0 - u)))


## 빛살 — 가운데가 밝고 끝으로 사라지는 가는 삼각형들. prism 이면 한 줄마다 무지개 색.
static func _rays(ci: CanvasItem, at: Vector2, n: int, length: float, spin: float, col: Color, alpha: float, prism: bool) -> void:
	if alpha <= 0.005 or length < 4.0:
		return
	for k in range(n):
		var a := spin + TAU * float(k) / n
		var wd := 0.045 + 0.03 * fposmod(k * 0.618, 1.0)
		var ln := length * (0.7 + 0.3 * fposmod(k * 0.381 + 0.2, 1.0))
		var c := Color.from_hsv(fposmod(float(k) / n + spin * 0.1, 1.0), 0.45, 1.0) if prism else col
		ci.draw_polygon(PackedVector2Array([at, at + Vector2(cos(a - wd), sin(a - wd)) * ln, at + Vector2(cos(a + wd), sin(a + wd)) * ln]),
				PackedColorArray([Color(c, alpha), Color(c, 0.0), Color(c, 0.0)]))


## 빛기둥 — 입에서 화면 위까지. 가운데 흰 심과 바깥 등급 빛, prism 이면 가장자리에 무지개.
static func _pillar(ci: CanvasItem, base: Vector2, width: float, bottom: float, col: Color, alpha: float, prism: bool, age: float) -> void:
	if alpha <= 0.005:
		return
	var top := -40.0
	for layer in range(2):
		var w := width * (1.0 if layer == 0 else 0.34)
		var c := col if layer == 0 else Color(1, 1, 1)
		var a := alpha * (0.75 if layer == 0 else 1.0)
		var l := base.x - w * 0.5
		var r := base.x + w * 0.5
		var m := base.x
		ci.draw_polygon(PackedVector2Array([Vector2(l, top), Vector2(m, top), Vector2(m, bottom), Vector2(l, bottom)]),
				PackedColorArray([Color(c, 0.0), Color(c, a * 0.35), Color(c, a), Color(c, 0.0)]))
		ci.draw_polygon(PackedVector2Array([Vector2(m, top), Vector2(r, top), Vector2(r, bottom), Vector2(m, bottom)]),
				PackedColorArray([Color(c, a * 0.35), Color(c, 0.0), Color(c, 0.0), Color(c, a)]))
	if prism:
		for side in [-1.0, 1.0]:
			var x: float = base.x + float(side) * width * 0.42
			var h := fposmod(age * 0.6 + (0.5 if side > 0 else 0.0), 1.0)
			ci.draw_line(Vector2(x, bottom), Vector2(x, top), Color(Color.from_hsv(h, 0.5, 1.0), alpha * 0.5), 3.0, true)
