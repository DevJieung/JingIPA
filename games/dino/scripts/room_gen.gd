class_name RoomGen
extends RefCounted

## 7탄부터는 방을 그때그때 만들어 낸다. 그래서 끝이 없다.
##   테마(이름 + 색) -> 가구 배치 -> 숨을 자리 고르기 -> 가려지는 정도 검사
## 나오는 값의 모양은 rooms.gd 의 손으로 만든 방과 똑같다.

const W := 1280.0
const LEFT := 60.0
const RIGHT := 1220.0

## 방 이름. 한 바퀴 돌면 색이 달라진 채로 다시 나온다.
static var THEMES := [
	{"n": "서재", "dark": false}, {"n": "지하실", "dark": true},
	{"n": "창고", "dark": false}, {"n": "아기방", "dark": false},
	{"n": "식당", "dark": false}, {"n": "세탁실", "dark": false},
	{"n": "현관", "dark": false}, {"n": "옷방", "dark": false},
	{"n": "공부방", "dark": false}, {"n": "손님방", "dark": false},
	{"n": "음악방", "dark": false}, {"n": "그림방", "dark": false},
	{"n": "별빛방", "dark": true}, {"n": "숲속방", "dark": false},
	{"n": "바다방", "dark": false}, {"n": "사탕방", "dark": false},
	{"n": "눈꽃방", "dark": false}, {"n": "무지개방", "dark": false},
	{"n": "구름방", "dark": false}, {"n": "딸기방", "dark": false},
	{"n": "레몬방", "dark": false}, {"n": "초코방", "dark": false},
	{"n": "우주방", "dark": true}, {"n": "공룡방", "dark": false},
	{"n": "장난감방", "dark": false}, {"n": "비밀방", "dark": true},
]

## 가구 목록.  hide: side=옆으로 빼꼼, low=뒤에서 머리만, none=숨는 자리 없음
static var CATALOG := [
	{"k": "sofa", "w": [380, 460], "h": [190, 230], "hide": "side"},
	{"k": "bed", "w": [370, 460], "h": [190, 220], "hide": "side"},
	{"k": "counter", "w": [350, 430], "h": [180, 210], "hide": "side"},
	{"k": "bathtub", "w": [370, 440], "h": [170, 200], "hide": "side"},
	{"k": "wardrobe", "w": [210, 260], "h": [320, 360], "hide": "side"},
	{"k": "fridge", "w": [190, 220], "h": [310, 350], "hide": "side"},
	{"k": "tv", "w": [240, 290], "h": [210, 240], "hide": "side"},
	{"k": "boxes", "w": [210, 260], "h": [230, 280], "hide": "side"},
	{"k": "toybox", "w": [240, 290], "h": [150, 180], "hide": "side"},
	{"k": "horse", "w": [230, 270], "h": [180, 210], "hide": "side"},
	{"k": "chair", "w": [190, 230], "h": [200, 240], "hide": "side"},
	{"k": "toilet", "w": [160, 190], "h": [200, 230], "hide": "side"},
	{"k": "sink", "w": [190, 220], "h": [160, 190], "hide": "side"},
	{"k": "nightstand", "w": [140, 175], "h": [155, 185], "hide": "side"},
	{"k": "plant", "w": [140, 175], "h": [250, 290], "hide": "side"},
	{"k": "bin", "w": [105, 130], "h": [140, 170], "hide": "side"},
	{"k": "table", "w": [210, 255], "h": [100, 125], "hide": "low"},
	{"k": "basket", "w": [150, 185], "h": [105, 132], "hide": "low"},
	{"k": "balls", "w": [180, 220], "h": [108, 130], "hide": "low"},
	{"k": "trunk", "w": [255, 300], "h": [115, 140], "hide": "low"},
	{"k": "blocks", "w": [130, 155], "h": [200, 240], "hide": "none"},
	{"k": "lamp", "w": [100, 130], "h": [255, 300], "hide": "none"},
]

static var FURN_COLORS := [
	"c98a55", "d8a86b", "b98d5e", "9ec6f0", "7fb5d9", "8fd6ff", "bcd9e8",
	"ffb3c1", "f2a2b0", "a3d9a5", "8fc98f", "c9a8e8", "e3c48f", "ffd166",
	"d6a86e", "e8a87c", "9fd8cf", "cbb7e8",
]

static var WOOD := ["c98a55", "d2a46c", "e6c08a", "a97b4f", "bb8a52", "d9b177"]


# ---------------------------------------------------------------- 테마(색)

static func theme_name(stage: int) -> String:
	return String(THEMES[(stage - 7) % THEMES.size()]["n"])


static func _theme(stage: int, rng: RandomNumberGenerator) -> Dictionary:
	var t: Dictionary = THEMES[(stage - 7) % THEMES.size()]
	# 황금비로 색상환을 돌아서 연달아 나오는 방이 서로 다른 색이 되게 한다.
	var hue := fposmod(float(stage) * 0.6180339887, 1.0)
	var wall := Color.from_hsv(hue, 0.15, 0.98)
	var wall2 := Color.from_hsv(hue, 0.27, 0.93)
	var trim := Color.from_hsv(hue, 0.05, 1.0)
	var wall_pat: String = ["stripes", "dots", "tiles", "planks"][rng.randi() % 4]

	var floor_col: Color
	var floor2: Color
	var floor_pat := "wood"
	if rng.randf() < 0.55:
		floor_col = Color(WOOD[rng.randi() % WOOD.size()])
		floor2 = floor_col.darkened(0.12)
	else:
		floor_pat = "checker"
		floor_col = Color.from_hsv(hue, 0.07, 0.97)
		floor2 = Color.from_hsv(hue, 0.16, 0.90)

	return {
		"name": String(t["n"]),
		"wall": wall, "wall2": wall2, "wall_pat": wall_pat,
		"floor": floor_col, "floor2": floor2, "floor_pat": floor_pat,
		"trim": trim, "dim": 0.16 if bool(t["dark"]) else 0.0,
	}


## 방 하나에 쓸 가구 색 4가지 (제각각이면 어수선해 보인다)
static func _palette(rng: RandomNumberGenerator) -> Array:
	var c: Array = FURN_COLORS.duplicate()
	c.shuffle()
	return c.slice(0, 4)


static func _prop(kind: String, x: float, y: float, w: float, h: float, rng: RandomNumberGenerator, pal: Array) -> Dictionary:
	return {
		"kind": kind, "x": x, "y": y, "w": w, "h": h,
		"col": Color(pal[rng.randi() % pal.size()]),
		"col2": Color("fff6e8"),
	}


# ---------------------------------------------------------------- 가구 배치

static func _layout(rng: RandomNumberGenerator, n: int, pal: Array) -> Array:
	var pool: Array = CATALOG.duplicate()
	pool.shuffle()
	var picks: Array = []
	var total := 0.0
	# 가구가 많아지면 사이 여백을 줄인다. 46px 고정이면 n=6 을 요청해도
	# 예산이 모자라 실제로는 3.7개밖에 안 놓인다 (요청보다 오히려 줄어든다).
	var pad := 46.0 if n <= 4 else 30.0
	var budget := RIGHT - LEFT - float(n + 1) * pad
	for c in pool:
		if picks.size() >= n:
			break
		var wr: Array = c["w"]
		var w: float = rng.randf_range(float(wr[0]), float(wr[1]))
		if total + w > budget:
			continue
		# 남은 자리 수를 보고 지나치게 큰 가구는 건너뛴다 (폭 인식 그리디).
		# 이게 없으면 큰 가구 하나가 예산을 먹어 뒤 자리들이 통째로 빈다.
		var left := n - picks.size()
		if left > 1 and w > (budget - total) / float(left) * 1.45:
			continue
		picks.append({"c": c, "w": w})
		total += w
	if picks.size() < 2:
		return []

	# 남는 공간을 앞뒤와 사이사이에 나눠 준다
	var gaps_n := picks.size() + 1
	var space := (RIGHT - LEFT) - total
	var gaps: Array = []
	var acc := 0.0
	for i in gaps_n:
		var g := rng.randf_range(0.7, 1.4)
		gaps.append(g)
		acc += g
	for i in gaps_n:
		gaps[i] = float(gaps[i]) / acc * space

	var out: Array = []
	var x := LEFT
	for i in picks.size():
		x += float(gaps[i])
		var c: Dictionary = picks[i]["c"]
		var w: float = picks[i]["w"]
		var hr: Array = c["h"]
		var h: float = rng.randf_range(float(hr[0]), float(hr[1]))
		var base := rng.randf_range(620.0, 700.0)
		out.append(_prop(String(c["k"]), x + w * 0.5, base, w, h, rng, pal))
		out[out.size() - 1]["hide"] = String(c["hide"])
		x += w
	return out


static func _wall_items(rng: RandomNumberGenerator, pal: Array, front: Array) -> Array:
	var back: Array = []
	# 벽 장식은 서로 겹치지 않고, 키 큰 가구(옷장·냉장고)에 가리지도 않는 자리에서만 고른다
	var slots: Array = []
	for s in [230.0, 480.0, 730.0, 980.0, 1140.0]:
		var ok := true
		for p in front:
			if float(p["h"]) > 250.0:
				var half: float = float(p["w"]) * 0.5 + 70.0
				if absf(float(p["x"]) - s) < half:
					ok = false
					break
		if ok:
			slots.append(s)
	slots.shuffle()
	var si := 0
	if rng.randf() < 0.85 and si < slots.size():
		var w := rng.randf_range(200.0, 250.0)
		back.append(_prop("window", clampf(float(slots[si]), 130.0, W - 130.0), rng.randf_range(300.0, 350.0), w, rng.randf_range(170.0, 200.0), rng, pal))
		back[back.size() - 1]["col"] = Color("fff6e8")
		si += 1
	if rng.randf() < 0.7 and si < slots.size():
		back.append(_prop("picture", float(slots[si]), rng.randf_range(270.0, 320.0), rng.randf_range(130.0, 180.0), rng.randf_range(100.0, 140.0), rng, pal))
		si += 1
	if rng.randf() < 0.45 and si < slots.size():
		back.append(_prop("shelf", clampf(float(slots[si]), 200.0, W - 200.0), rng.randf_range(310.0, 350.0), rng.randf_range(260.0, 330.0), 95.0, rng, pal))
		si += 1
	if rng.randf() < 0.5:
		var r := _prop("rug", rng.randf_range(500.0, 780.0), rng.randf_range(700.0, 716.0), rng.randf_range(480.0, 620.0), rng.randf_range(110.0, 140.0), rng, pal)
		r["col2"] = Color(r["col"]).lightened(0.55)
		back.append(r)
	if rng.randf() < 0.25:
		back.append(_prop("cobweb", 120.0, 200.0, 170.0, 170.0, rng, pal))
		back[back.size() - 1]["col"] = Color(1, 1, 1, 0.75)
	return back


# ---------------------------------------------------------------- 숨을 자리

## 후보 자리 전부 (가림% 상관없이). 실제로 쓸 자리는 _place() 가 u 로 맞춰서 고른다.
static func _candidates(front: Array) -> Array:
	var out: Array = []
	for i in front.size():
		var p: Dictionary = front[i]
		var hide := String(p.get("hide", "side"))
		var sides: Array = []
		if hide == "side":
			sides = [-1, 1, 0]      # 옆 둘 + 뒤 하나 (뒤는 u 로 살릴 수 있다)
		elif hide == "low":
			sides = [0, -1, 1]
		for s in sides:
			out.append({"p": i, "side": s})
	return out


## 이 자리가 u 를 끝까지 움직였을 때 닿을 수 있는 가림% 범위. 3번만 재고 만다.
##
## ★ 이걸 따로 두는 이유는 순전히 속도다. 예전에는 후보마다 목표마다 이분탐색(12회)을
##   돌렸는데, 가림% 한 번이 16x16 격자 x 가구 수라 방 하나에 수백만 번의 점 검사가 됐다.
##   폰에서 방 전환마다 프리즈가 나고 셀프테스트가 17탄에서 시간 초과로 멈췄다.
##   먼저 싸게 범위를 재서 후보를 거르고, 살아남은 후보에만 이분탐색을 돌린다.
static func u_span(front: Array, spot: Dictionary) -> Vector2i:
	var lo := 127
	var hi := -1
	for u in [Rooms.U_MIN, 0.0, Rooms.U_MAX]:
		var st := Rooms.spot_transform(front, {"p": spot["p"], "side": spot["side"], "u": u})
		var cov := Rooms.coverage(st["pos"], front)
		if cov < 0:
			continue
		lo = mini(lo, cov)
		hi = maxi(hi, cov)
	return Vector2i(lo, hi)


## 이 자리를 목표 가림%에 맞추는 u 를 이분탐색으로 찾는다.
## 가림%는 u 에 대해 거의 단조증가라 12회면 ±3%p 안에 든다.
## 못 맞추면(화면 밖으로 나가거나 절대 한계를 못 지키면) null.
static func solve_u(front: Array, spot: Dictionary, target: int) -> Variant:
	var lo := Rooms.U_MIN
	var hi := Rooms.U_MAX
	var best_u := 0.0
	var best_cov := -1
	var best_err := 9999
	for _i in 12:
		var mid := (lo + hi) * 0.5
		var probe := {"p": spot["p"], "side": spot["side"], "u": mid}
		var st := Rooms.spot_transform(front, probe)
		var cov := Rooms.coverage(st["pos"], front)
		if cov < 0:
			# 화면 밖 — 덜 파고들게 되돌린다
			hi = mid
			continue
		var err := absi(cov - target)
		if err < best_err:
			best_err = err
			best_u = mid
			best_cov = cov
		if cov < target:
			lo = mid
		else:
			hi = mid
	if best_cov < Rooms.COV_HARD_LO or best_cov > Rooms.COV_HARD_HI:
		return null
	return {"p": spot["p"], "side": spot["side"], "u": best_u, "cov": best_cov}


## 목표 가림%를 밴드 전체에 퍼뜨려 want 마리 자리를 고른다.
##
## ★ 완충 장치 B1: 제일 어려운 자리는 한 마리에만 준다. 6마리라면
##   51 / 57 / 62 / 67 / 72 / 77% 처럼 퍼지고, 80%짜리는 6마리 중 하나뿐이다.
##   전부 최고 난이도로 주면 "확 어려워졌다"가 된다.
static func _place(front: Array, want: int, band: Vector2i, rng: RandomNumberGenerator) -> Array:
	var cands := _candidates(front)
	cands.shuffle()
	var n := maxi(1, want)
	var targets: Array = []
	for k in n:
		targets.append(int(round(float(band.x) + float(band.y - band.x) * (float(k) + 0.5) / float(n))))
	# 후보마다 "닿을 수 있는 가림% 범위"와 대략의 x 를 한 번만 재 둔다 (후보당 4번).
	var info: Array = []
	for c in cands:
		var span := u_span(front, c)
		if span.y < Rooms.COV_HARD_LO or span.x > Rooms.COV_HARD_HI:
			continue
		var st := Rooms.spot_transform(front, {"p": c["p"], "side": c["side"], "u": 0.0})
		info.append({"c": c, "lo": span.x, "hi": span.y, "x": (st["pos"] as Vector2).x})

	# 쉬운 것부터 채운다 — 어려운 자리는 남는 후보 중 가장 잘 맞는 곳에 준다.
	# 자리가 모자라면 간격 조건만 조금씩 풀어 다시 훑는다 (가림 한계는 절대 안 푼다).
	var picked: Array = []
	var xs: Array = []
	var used := {}
	for gap in [130.0, 118.0, 108.0]:
		for ti in targets.size():
			if picked.size() > ti:
				continue     # 이 목표는 앞 바퀴에서 이미 채웠다
			var t := int(targets[ti])
			# 목표에 가장 잘 닿는 후보부터 차례로 시도한다.
			var ranked: Array = []
			for e in info:
				if used.has("%d_%d" % [int(e["c"]["p"]), int(e["c"]["side"])]):
					continue
				# 목표가 범위 안이면 0, 밖이면 벗어난 만큼
				ranked.append([maxi(0, maxi(int(e["lo"]) - t, t - int(e["hi"]))), e])
			ranked.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
			for r in ranked:
				var e: Dictionary = r[1]
				var sol: Variant = solve_u(front, e["c"], t)
				if sol == null:
					continue
				# ★ 간격은 **파고든 뒤의 최종 좌표**로 재야 한다.
				#   u 가 자리를 옮기므로 u=0 좌표로 재면 공룡이 12px 간격으로 겹친다(실제로 그랬다).
				var st2 := Rooms.spot_transform(front, sol)
				var fx: float = (st2["pos"] as Vector2).x
				var too_close := false
				for ox in xs:
					if absf(float(ox) - fx) < gap:
						too_close = true
						break
				if too_close:
					continue
				picked.append(sol)
				xs.append(fx)
				used["%d_%d" % [int(sol["p"]), int(sol["side"])]] = true
				break
		if picked.size() >= n:
			break
	return picked


# ---------------------------------------------------------------- 난이도 축

## 유효탄 e 에서의 모든 난이도 손잡이. **단일 진실 소스**다.
##
## t 는 프로필의 tuning (아이마다 다르다). 없으면 초등 기본값.
##
## 올리는 축은 셋뿐이다 — 볼 것이 늘거나(A), 잘 안 보이거나(B), 고를 것이 는다(C).
## 기다림(E)·평가(F)·시간압박(G)은 절대 올리지 않는다. 기다림은 내려가기만 한다.
static func axes(e: int, t: Dictionary = {}) -> Dictionary:
	var dmin := int(t.get("dino_min", 3))
	var dmax := int(t.get("dino_max", 6))
	var step := maxf(1.0, float(t.get("dino_step", 4.5)))
	var lo0 := int(t.get("dino_cov_lo", 30))
	var hi0 := int(t.get("dino_cov_hi", 58))
	var hint0 := float(t.get("dino_hint_sec", 13.0))
	var ceil_hi := int(t.get("dino_cov_ceil", 80))
	var b := Rooms.band(e, lo0, hi0, ceil_hi)
	return {
		# A. 볼 것이 는다
		"dinos": clampi(dmin + int(floor(float(e) / step)), dmin, dmax),
		# 가구 상한 6. 7 은 예산 대비 수익이 없다 (배치가 오히려 준다).
		"props": clampi(3 + int(floor(float(e) / 7.0)), 3, 6),
		# B. 잘 안 보인다
		"band": b,
		# 작은 종이 뽑힐 확률. 그림 면적이 종끼리 2배 넘게 차이난다.
		"small_bias": clampf(float(e - 10) / 30.0, 0.0, 1.0),
		# C. 고를 것이 는다
		"decoys": 0 if e < 28 else mini(2, int((e - 28) / 10) + 1),
		"targets_only": e >= 24,
		# 조명은 가림% 계산과 완전히 직교한다 (기하량이라 영향 0). 하드캡 0.22.
		"dim_add": 0.0 if e < 32 else clampf(0.06 * float(e - 32) / 8.0, 0.0, 0.06),
		# E. 기다림 — 내려가기만 한다
		"hint_sec": clampf(hint0 - 0.15 * float(e), 8.0, hint0),
	}


# ---------------------------------------------------------------- 만들기

## 이 탄에 공룡을 몇 마리 숨길지 (옛 이름 유지 — 바깥에서 부르는 곳이 있다)
static func dino_count(stage: int) -> int:
	return int(axes(stage)["dinos"])


## e = 난이도용 유효탄 (아이 실력에 따라 조용히 조정된다)
## stage = 아이가 보는 탄 번호 (방 이름·색은 이걸로 정한다)
static func stage_room(e: int, rng: RandomNumberGenerator, stage: int = -1, t: Dictionary = {}) -> Dictionary:
	if stage < 0:
		stage = e
	var ax := axes(e, t)
	var want := int(ax["dinos"])
	var n_props := int(ax["props"])
	var band: Vector2i = ax["band"]
	var best_front: Array = []
	var best_spots: Array = []
	var pal := _palette(rng)

	# ★ 14회는 want=6 에서 거의 항상 다 돌아 방 생성이 느려진다(폰에서 프리즈).
	#   u 로 자리를 살릴 수 있게 된 뒤로는 8회면 충분하다.
	for attempt in 8:
		var front := _layout(rng, n_props, pal)
		if front.is_empty():
			continue
		var spots := _place(front, want, band, rng)
		if spots.size() > best_spots.size():
			best_front = front
			best_spots = spots
		if spots.size() >= want:
			break

	var room := _theme(stage, rng)
	room["count"] = mini(want, maxi(2, best_spots.size()))
	room["want"] = want
	room["front"] = best_front
	room["back"] = _wall_items(rng, pal, best_front)
	room["spots"] = best_spots
	room["dim_add"] = float(ax["dim_add"])
	return room
