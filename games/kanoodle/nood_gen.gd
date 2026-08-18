class_name NoodGen
extends RefCounted

## 퍼즐 생성기.
##
## ★ 무작위로 늘어놓고 "풀리나?" 검사하면 못 푸는 판이 나온다.
##   그래서 **거꾸로 만든다** — 먼저 판을 조각으로 빈틈없이 덮은 뒤(=해답),
##   그중 몇 개를 빼서 문제로 준다. 이러면 **풀 수 있다는 것이 생성 방식 자체로 보장**되고,
##   해답을 이미 들고 있으므로 힌트와 검증이 공짜다.
##
## ★ 조각은 **떨어져서 쌓인다**(중력). 그래서 해답에서 아무 조각이나 빼면 안 된다.
##   위에 뭔가 얹혀 있는 조각을 빼서 문제로 주면, 아이가 그걸 떨어뜨렸을 때
##   위에 얹힌 조각에 걸려 제자리까지 못 내려간다 — **풀 수 없는 판**이 된다.
##   그래서 빼는 조각들은 반드시 "위쪽이 뚫린 덩어리"여야 한다 (pick_top 참고).
##
## 덮는 순서는 "빈 칸 중 맨 앞(위→아래, 왼→오른)"을 반드시 채우는 것으로 고정한다.
## 이게 없으면 백트래킹이 같은 배치를 순서만 바꿔 무한히 훑는다.

## 난이도 손잡이. game 이 axes() 로 만들어 넘긴다.
##   n        격자 한 변 (4~6)
##   place    아이가 놓아야 할 조각 수
##   guide    0 = 칸마다 목표색까지 보임 / 1 = 조각 경계만 / 2 = 바깥 테두리만
##   rotate   true 면 트레이 조각이 아무 방향으로 온다 (돌리기 버튼을 써야 한다)
##   twins    같은 모양을 여러 개 섞어 헷갈리게 (0~2)

## 이 기둥으로는 조각이 판 안에 못 들어온다. drop_dy() 가 돌려주는 값.
const NO_DROP := -9999


## 판을 조각으로 빈틈없이 덮는다. 성공하면 [{pi, cells}], 실패하면 [].
##
## cap 은 백트래킹 한도다 — 4x4~6x6 에서는 수백 번 안에 끝난다.
static func tile(n: int, rng: RandomNumberGenerator, allowed: Array[int],
		cap: int = 4000) -> Array:
	var grid := PackedInt32Array()
	grid.resize(n * n)
	grid.fill(-1)
	var placed: Array = []
	var budget := [cap]
	if _fill(grid, n, rng, allowed, placed, budget):
		return placed
	return []


static func _first_empty(grid: PackedInt32Array, n: int) -> int:
	for i in n * n:
		if grid[i] < 0:
			return i
	return -1


static func _fill(grid: PackedInt32Array, n: int, rng: RandomNumberGenerator,
		allowed: Array[int], placed: Array, budget: Array) -> bool:
	var slot := _first_empty(grid, n)
	if slot < 0:
		return true
	if budget[0] <= 0:
		return false
	budget[0] -= 1
	var sx := slot % n
	var sy := slot / n

	# 이 빈 칸을 덮는 모든 (조각, 회전, 오프셋) 후보를 모아 섞는다.
	var cands: Array = []
	for pi in allowed:
		for rot in NoodPieces.rotations(pi):
			for anchor in rot:
				var ax: int = sx - (anchor as Vector2i).x
				var ay: int = sy - (anchor as Vector2i).y
				var cells: Array = []
				var ok := true
				for c in rot:
					var x: int = ax + (c as Vector2i).x
					var y: int = ay + (c as Vector2i).y
					if x < 0 or y < 0 or x >= n or y >= n or grid[y * n + x] >= 0:
						ok = false
						break
					cells.append(Vector2i(x, y))
				if ok:
					cands.append({"pi": pi, "cells": cells})
	if cands.is_empty():
		return false
	_shuffle(cands, rng)

	for cand in cands:
		var idx := placed.size()
		for c in (cand["cells"] as Array):
			grid[(c as Vector2i).y * n + (c as Vector2i).x] = idx
		placed.append(cand)
		if _fill(grid, n, rng, allowed, placed, budget):
			return true
		placed.remove_at(idx)
		for c in (cand["cells"] as Array):
			grid[(c as Vector2i).y * n + (c as Vector2i).x] = -1
		if budget[0] <= 0:
			return false
	return false


# --------------------------------------------------------------------------- #
# 중력 — 게임·생성기·검사기가 모두 이 함수들만 본다
# --------------------------------------------------------------------------- #

## shape 를 (dx, dy) 만큼 옮긴 자리에 둘 수 있는가.
##
## y < 0 (아직 판 위) 은 빈 것으로 친다 — 조각은 판 바깥 위에서 내려온다.
static func can_sit(grid: PackedInt32Array, n: int, shape: Array, dx: int, dy: int) -> bool:
	for cc in shape:
		var v: Vector2i = cc
		var x := v.x + dx
		if x < 0 or x >= n:
			return false
		var y := v.y + dy
		if y >= n:
			return false
		if y >= 0 and grid[y * n + x] >= 0:
			return false
	return true


## shape 를 dx 만큼 옆으로 민 채 떨어뜨렸을 때 멈추는 세로 오프셋.
##
## ★ 낙하 규칙이 게임과 검사기에 따로 적히면 "검사는 통과하는데 아이 화면에서는
##   안 들어가는" 판이 나온다. 그래서 세 곳이 이 함수 하나만 본다.
##   (공룡 찾기의 rooms.gd `band()` 와 같은 이유다.)
static func drop_dy(grid: PackedInt32Array, n: int, shape: Array, dx: int) -> int:
	var top := 0
	for cc in shape:
		top = maxi(top, (cc as Vector2i).y)
	var dy := -top - 1                      # 판 바로 위에서 시작한다
	if not can_sit(grid, n, shape, dx, dy):
		return NO_DROP                      # 가로가 판 밖으로 나간다
	while can_sit(grid, n, shape, dx, dy + 1):
		dy += 1
	for cc in shape:
		if (cc as Vector2i).y + dy < 0:
			return NO_DROP                  # 다 쌓여서 조각이 판 안으로 못 들어온다
	return dy


## 조각 i 의 낙하 경로를 막는 조각들 — i 의 각 기둥에서 i 보다 위에 있는 칸의 주인.
##
## 반환: [{조각인덱스: true}, ...] (해답과 같은 길이)
static func blockers_of(sol: Array, n: int) -> Array:
	var owner := PackedInt32Array()
	owner.resize(n * n)
	owner.fill(-1)
	for i in sol.size():
		for cc in ((sol[i] as Dictionary)["cells"] as Array):
			var v: Vector2i = cc
			owner[v.y * n + v.x] = i

	var out: Array = []
	for i in sol.size():
		var top := {}                       # 기둥 x -> 이 조각의 가장 윗칸
		for cc in ((sol[i] as Dictionary)["cells"] as Array):
			var v: Vector2i = cc
			if not top.has(v.x) or v.y < int(top[v.x]):
				top[v.x] = v.y
		var s := {}
		for x in top:
			for y in int(top[x]):
				var o := owner[y * n + int(x)]
				if o >= 0 and o != i:
					s[o] = true
		out.append(s)
	return out


## 해답에서 아이 몫으로 뺄 조각 want 개를 고른다 — **위에서부터**.
##
## ★ 막는 것이 이미 다 빠진 조각만 뺀다. 이렇게 모으면 "아래에서부터 차례로
##   떨어뜨리면 전부 제자리에 앉는 순서"가 반드시 존재한다 (뺀 순서를 뒤집으면 된다).
## ★ 막는 것이 **아예 없는** 조각(맨 윗층)을 먼저 고른다. 맨 윗층끼리는 서로를 가리지
##   않아서 아이가 아무 순서로 떨어뜨려도 된다 — 순서를 못 맞춰 헤맬 일이 없다.
##   더 깊이 파고들 때만 순서가 생기고, 그때는 판 위의 조각을 도로 들어 되돌릴 수 있다.
##
## 반환: 뺀 순서(위 -> 아래)의 해답 인덱스 배열.
static func pick_top(sol: Array, n: int, want: int, rng: RandomNumberGenerator) -> Array:
	var block := blockers_of(sol, n)
	var taken := {}
	var out: Array = []
	while out.size() < want:
		var free_c: Array = []
		var dep_c: Array = []
		for i in sol.size():
			if taken.has(i):
				continue
			var ready := true
			for q in (block[i] as Dictionary):
				if not taken.has(q):
					ready = false
					break
			if not ready:
				continue
			if (block[i] as Dictionary).is_empty():
				free_c.append(i)
			else:
				dep_c.append(i)
		var pool: Array = free_c if not free_c.is_empty() else dep_c
		if pool.is_empty():
			break
		var pick := int(pool[rng.randi_range(0, pool.size() - 1)])
		taken[pick] = true
		out.append(pick)
	return out


## 이 판이 정말 "떨어뜨려서" 끝까지 풀리는가.
##
## ★ 미리 계산해 둔 order 를 그대로 따라가면 검사가 아니라 자기 확인이 된다.
##   그래서 **게임과 똑같이** 판다 — 매번 "지금 차례인 조각"을 트레이 앞에서부터
##   찾아 떨어뜨리고, 그때마다 정말 제자리에 앉는지 본다. 차례인 조각이 하나도
##   없으면 아이가 갇힌 것이므로 실패다.
##
## 이렇게 해야 "생성은 됐는데 아이가 순서를 골라 가며 놓다 보면 막히는 판"이 잡힌다.
static func drop_check(pz: Dictionary) -> bool:
	if pz.is_empty():
		return false
	var n := int(pz["n"])
	var sol: Array = pz["solution"]
	var tray: Array = pz["tray"]

	var grid := PackedInt32Array()
	grid.resize(n * n)
	grid.fill(-1)
	for i in (pz["fixed"] as Array):
		for cc in ((sol[int(i)] as Dictionary)["cells"] as Array):
			var v: Vector2i = cc
			grid[v.y * n + v.x] = 1

	# 가둠 표 — 게임의 _blocks 와 같은 것
	var bl := blockers_of(sol, n)
	var blocks := {}
	for k in tray.size():
		var r := int((tray[k] as Dictionary)["sol"])
		for s in (bl[r] as Dictionary):
			if not blocks.has(int(s)):
				blocks[int(s)] = []
			(blocks[int(s)] as Array).append(r)

	var left := {}                          # 아직 안 놓은 조각의 해답 인덱스
	for k in tray.size():
		left[int((tray[k] as Dictionary)["sol"])] = k

	while not left.is_empty():
		var pick := -1
		for k in tray.size():
			var s := int((tray[k] as Dictionary)["sol"])
			if not left.has(s):
				continue
			var ready := true
			for r in blocks.get(s, []):
				if left.has(int(r)):
					ready = false
					break
			if ready:
				pick = k
				break
		if pick < 0:
			return false                    # 차례인 조각이 없다 = 아이가 갇혔다

		var cells: Array = (tray[pick] as Dictionary)["cells"]
		var mx := 9999
		var my := 9999
		for cc in cells:
			mx = mini(mx, (cc as Vector2i).x)
			my = mini(my, (cc as Vector2i).y)
		var shape: Array = []
		for cc in cells:
			shape.append(Vector2i((cc as Vector2i).x - mx, (cc as Vector2i).y - my))
		# 차례인 조각은 **반드시** 제자리에 앉아야 한다. 안 앉으면 규칙이 틀린 것이다.
		if drop_dy(grid, n, shape, mx) != my:
			return false
		for cc in cells:
			var v: Vector2i = cc
			grid[v.y * n + v.x] = 1
		left.erase(int((tray[pick] as Dictionary)["sol"]))
	return true


# --------------------------------------------------------------------------- #
# 한 판 만들기
# --------------------------------------------------------------------------- #

## 반환: {
##   "n": 격자 한 변,
##   "solution": [{pi, cells}]  — 전체 해답 (덮기 결과)
##   "fixed": [i, ...]          — 미리 놓여 있는 조각의 solution 인덱스
##   "tray":  [{pi, cells, sol}]— 아이가 놓아야 할 조각 (cells 는 정답 자리,
##                                sol 은 해답 인덱스 — 게임이 가둠 표를 만들 때 쓴다)
##   "guide": 0~2
## }
## 실패하면 {} (호출부가 더 쉬운 설정으로 다시 부른다).
static func make(cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var n := int(cfg.get("n", 5))
	var want := int(cfg.get("place", 3))
	var allowed: Array[int] = []
	var pool: Array = cfg.get("pieces", [])
	if pool.is_empty():
		for i in NoodPieces.count():
			allowed.append(i)
	else:
		for id in pool:
			allowed.append(NoodPieces.index_of(String(id)))

	var sol: Array = []
	for attempt in 12:
		sol = tile(n, rng, allowed)
		if not sol.is_empty():
			break
	if sol.is_empty():
		return {}

	# 해답 중 want 개를 아이 몫으로 빼고 나머지는 미리 놓아 둔다.
	# ★ 아무거나 빼는 게 아니다 — 중력 때문에 "위쪽이 뚫린" 것만 뺄 수 있다.
	want = clampi(want, 1, sol.size())
	var take := pick_top(sol, n, want, rng)
	if take.is_empty():
		return {}
	var take_set := {}
	for t in take:
		take_set[int(t)] = true

	var fixed: Array = []
	var tray: Array = []
	for i in sol.size():
		if take_set.has(i):
			var e: Dictionary = sol[i]
			tray.append({"pi": int(e["pi"]), "cells": (e["cells"] as Array).duplicate(),
					"sol": i})
		else:
			fixed.append(i)

	# 트레이에 보일 순서는 섞는다 (해답 순서대로 주면 순서만 따라 놓으면 된다).
	# ★ 섞어도 안전하다 — 놓는 순서는 게임이 blockers_of() 로 그때그때 따진다.
	#   여기서 "정답 순서"를 같이 내보내면 진실이 두 군데가 되어 언젠가 어긋난다.
	_shuffle(tray, rng)

	return {
		"n": n,
		"solution": sol,
		"fixed": fixed,
		"tray": tray,
		"guide": int(cfg.get("guide", 0)),
		"rotate": bool(cfg.get("rotate", false)),
	}


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# --------------------------------------------------------------------------- #
# 난이도 축
# --------------------------------------------------------------------------- #

## 유효탄 e 에서의 손잡이. **단일 진실 소스**다.
##
## 올리는 축은 셋 — 볼 것이 늘고(격자·조각 수), 잘 안 보이고(안내 단계),
## 고를 것이 는다(회전·닮은 조각). 기다림·평가·시간 축은 없다.
static func axes(e: int, t: Dictionary = {}) -> Dictionary:
	var nmin := int(t.get("nood_n_min", 4))
	var nmax := int(t.get("nood_n_max", 6))
	var pmin := int(t.get("nood_place_min", 2))
	var pmax := int(t.get("nood_place_max", 6))
	var guide_at := int(t.get("nood_guide_at", 10))   # 안내를 한 단계 줄이기 시작하는 탄
	var rotate_at := int(t.get("nood_rotate_at", 22)) # 회전이 필요해지는 탄

	var n := clampi(nmin + int(floor(float(e) / 9.0)), nmin, nmax)
	var place := clampi(pmin + int(floor(float(e) / 4.0)), pmin, pmax)
	# 안내 0(칸마다 색) -> 1(조각 경계) -> 2(바깥 테두리만)
	var guide := 0
	if e >= guide_at:
		guide = 1
	if e >= guide_at * 2:
		guide = 2
	return {
		"n": n,
		"place": place,
		"guide": guide,
		"rotate": e >= rotate_at,
		# 쉬운 탄에서는 단순한 조각만 쓴다
		"pieces": NoodPieces.EASY_ORDER.slice(0, clampi(4 + int(floor(float(e) / 5.0)), 4,
				NoodPieces.EASY_ORDER.size())),
	}
