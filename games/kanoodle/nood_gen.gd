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
##
## ★ 다만 이 해답은 **아이가 맞춰야 할 정답이 아니다.** 첫 계획일 뿐이다.
##   아이는 모양만 맞으면 아무 데나 넣을 수 있고(아래 "자유 배치" 절), 그때마다
##   계획을 다시 세운다. 여기서 만든 해답은 (1) 처음 판을 채워 두는 데,
##   (2) 첫 계획의 밑그림으로 쓰인다.

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

	# 가둠 표 — 해답 순서가 정말 떨어뜨려서 나오는지 보는 데만 쓴다.
	# ★ 게임은 이제 이 표를 안 쓴다 (자유 배치라 순서가 해답에 매이지 않는다).
	#   여기서는 **생성기가 낸 해답 자체가 낙하로 도달 가능한가**를 보는 것이라 여전히 필요하다.
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
# 자유 배치 — "모양이 맞으면 들어간다"
# --------------------------------------------------------------------------- #
#
# ★ 예전에는 조각이 **해답에 적힌 그 자리**에 앉아야만 들어갔다. 그래서 모양이 딱 맞는
#   빈 자리에 제대로 넣어도 튕겨 나오는 일이 생겼다 — 아이 눈에는 "맞는데 안 되는" 것이고
#   그게 이 놀이에서 제일 나쁜 경험이다. (같은 모양 조각이 둘일 때 특히 자주 났다:
#   왼쪽 i2 를 오른쪽 i2 자리에 넣으면 그림은 똑같은데 튕겼다.)
#
# ★ 그래서 판정을 **자리**에서 **가능성**으로 옮겼다. 어디에 떨어뜨렸든,
#   **남은 조각으로 판을 끝까지 채울 수 있으면** 들어간다. 해답은 이제 계약이 아니라
#   "지금 세워 둔 계획" 하나일 뿐이고, 아이가 다른 길로 가면 계획을 다시 세운다.
#
# ★ 그래도 막다른 판은 안 만든다 — **채울 수 없게 되는 수만** 막는다. 그 판정이
#   plan() 이다. 되돌리기(판 위의 조각 도로 들기)는 그대로라, 되들다가 구멍이
#   묻혀 버린 경우까지 아이가 스스로 빠져나올 수 있다 (kanoodle.gd 의 _lift_hint).

## 계획 하나를 찾는 데 볼 수 있는 상태 수. 넘으면 "모르겠다"가 되는데, 그때는
## **너그러운 쪽**(놓게 해 준다)으로 답한다 — 되는 걸 막는 것이 제일 나쁘다.
## (실제로는 근처도 안 간다. 아래 두 가지치기가 갈래를 거의 다 쳐 낸다.)
const PLAN_CAP := 60000

static var _sig_cache: Dictionary = {}

## 모양 묶음 번호표에 담을 수 있는 가짓수. 넘으면 기억(memo)만 끈다 (답은 그대로다).
const MAX_LOC := 8


## 탐색 여러 번이 **함께 쓰는 주머니** — 막힌 판 기억(memo)과 모양 묶음 번호표(ids).
##
## ★ 번호표를 반드시 같이 써야 한다. 부르는 쪽마다 번호를 새로 매기면 같은 열쇠가
##   서로 다른 판을 가리키게 되어, 되는 자리를 "안 된다"고 하기 시작한다.
##   (실제로 물렸다 — 자리마다 남은 조각이 달라서 번호가 밀린다.)
static func new_bag() -> Dictionary:
	return {"memo": {}, "ids": {}}


## 주머니를 쓸 수 있는 모양으로 만들어 준다 (빈 것이 오면 새로 판다).
static func _bag_of(bag: Dictionary) -> Dictionary:
	if bag.has("memo") and bag.has("ids"):
		# ★ 한 판 내내 쌓이므로 너무 커지면 비운다. 답은 안 변하고 다시 세기만 한다.
		if (bag["memo"] as Dictionary).size() > 150000:
			bag["memo"] = {}
		return bag
	return new_bag()

## 진단용 — 탐색이 들여다본 판의 수. 검사기가 이걸 찍어서 "느려지지 않았는가"를 본다.
static var stat_nodes := 0
## 진단용 — 탐색이 한도(PLAN_CAP)에 걸려 "모르겠다"로 끝난 횟수.
## ★ 0 이 아니면 너그러운 쪽으로 답한 것이라 **막다른 판이 새어 나갈 수 있다.**
##   검사기가 이걸 0으로 강제한다.
static var stat_capped := 0


static func _full(g: PackedInt32Array, n: int) -> bool:
	for i in n * n:
		if g[i] < 0:
			return false
	return true


## 위가 막힌 빈 칸이 있는가.
##
## ★ 조각은 위에서 **내려와서** 앉는다. 그래서 위쪽 어딘가가 이미 찬 기둥의 빈 칸은
##   어떤 조각도 지나갈 수 없어 **영영 못 채운다.** 계획 탐색에서 갈래를 가장 크게
##   쳐 내는 가지치기이자, "여기 놓으면 망한다"의 거의 전부다.
static func buried(g: PackedInt32Array, n: int) -> bool:
	for x in n:
		var lid := false
		for y in n:
			if g[y * n + x] >= 0:
				lid = true
			elif lid:
				return true
	return false


## 빈 칸 덩어리마다 "남은 조각들로 딱 떨어지는 크기"인가.
## (조각이 1칸짜리가 없으므로 홀로 남은 한 칸은 여기서 바로 걸린다.)
static func _regions_ok(g: PackedInt32Array, n: int, sums: int) -> bool:
	var seen := PackedInt32Array()
	seen.resize(n * n)
	seen.fill(0)
	for i in n * n:
		if g[i] >= 0 or seen[i] == 1:
			continue
		var stack: Array = [i]
		seen[i] = 1
		var cnt := 0
		while not stack.is_empty():
			var at := int(stack.pop_back())
			cnt += 1
			var ax := at % n
			var ay := at / n
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var bx := ax + d.x
				var by := ay + d.y
				if bx < 0 or by < 0 or bx >= n or by >= n:
					continue
				var bi := by * n + bx
				if g[bi] >= 0 or seen[bi] == 1:
					continue
				seen[bi] = 1
				stack.append(bi)
		if cnt > 62 or ((sums >> cnt) & 1) == 0:
			return false
	return true


## 모양 묶음 하나에 작은 번호를 붙인다 (탐색 중 상태 열쇠를 짧게 만들려고).
static func _sig_id(shs: Array) -> int:
	var parts: Array = []
	for sh in shs:
		parts.append(NoodPieces.key(NoodPieces.normalize(sh)))
	parts.sort()
	var k := ""
	for p in parts:
		k += String(p) + "|"
	if not _sig_cache.has(k):
		_sig_cache[k] = _sig_cache.size()
	return int(_sig_cache[k])


static func _sids_of(shapes: Array) -> Array:
	var out: Array = []
	for sh in shapes:
		out.append(_sig_id(sh))
	return out


static func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var have := {}
	for cc in a:
		have[cc] = true
	for cc in b:
		if not have.has(cc):
			return false
	return true


## 지금 판(grid)에 남은 조각들(shapes)을 떨어뜨려 **끝까지 채울 수 있는가**, 그 계획은.
##
## shapes[i] = i 번 조각이 쓸 수 있는 모양들. **돌리기 버튼이 없는 판이면 한 가지뿐**이다 —
##   여기서 모든 회전을 허용하면 "계획은 있는데 아이는 그 모양을 못 만드는" 판이 나온다.
## prefer[i] 가 있으면 그 자리를 먼저 시도한다. 계획이 이유 없이 춤추지 않게 하는
##   장치다 (안내 점 색이 매번 바뀌면 아이가 헷갈린다).
##
## 반환: {"ok", "at": [조각별 자리], "order": [놓는 차례], "capped": 탐색 한도에 걸림}
## bag 을 넘기면 **한 판 내내 기억이 이어진다.** 같은 판을 자리마다 수십 번 물어보므로
## 이게 없으면 어려운 판에서 같은 계산을 계속 다시 한다.
static func plan(grid: PackedInt32Array, n: int, shapes: Array,
		prefer: Array = [], bag: Dictionary = {}) -> Dictionary:
	return _solve(grid, n, shapes, _sids_of(shapes), prefer, _bag_of(bag))


## i 번 조각을 cells 에 앉혀도 남은 조각으로 판을 끝까지 채울 수 있는가.
## ★ 이 한 줄이 "모양이 맞으면 들어간다"의 전부다.
static func fits(grid: PackedInt32Array, n: int, shapes: Array, i: int,
		cells: Array, bag: Dictionary = {}) -> bool:
	return _fits_at(grid, n, shapes, _sids_of(shapes), [], i, cells, _bag_of(bag))


## 계획 하나 + "지금 놓을 수 있는 조각"을 한 번에 센다. **판이 바뀔 때만** 부른다
## (매 프레임 부르면 안 된다 — 판 전체를 뒤지는 탐색이다).
##
## 반환: plan() 의 결과 + {"ready": [조각별 bool]}
static func survey(grid: PackedInt32Array, n: int, shapes: Array,
		prefer: Array = [], shared: Dictionary = {}) -> Dictionary:
	var sids := _sids_of(shapes)
	var bag := _bag_of(shared)
	var res := _solve(grid, n, shapes, sids, prefer, bag)
	var ready: Array = []
	ready.resize(shapes.size())
	for i in shapes.size():
		ready[i] = false
	if not bool(res["ok"]):
		# 계획 자체가 없다 (되들다가 구멍이 묻힌 판). 아무 조각도 차례가 아니다 —
		# 다만 "모르겠다"로 끝났으면 막지 않는다.
		if bool(res["capped"]):
			for i in shapes.size():
				ready[i] = true
		res["ready"] = ready
		return res
	var order: Array = res["order"]
	if not order.is_empty():
		ready[int(order[0])] = true     # 계획의 첫 수는 당연히 지금 놓을 수 있다
	# ★ **모양 묶음이 같은 조각은 답도 같다.** 쌍둥이가 둘이면 한 번만 센다 —
	#   여기가 계획 다시 세우기 시간의 대부분이었다.
	var done := {}
	for i in shapes.size():
		if bool(ready[i]):
			done[int(sids[i])] = true
	for i in shapes.size():
		if bool(ready[i]):
			continue
		var sid := int(sids[i])
		if done.has(sid):
			ready[i] = bool(done[sid])
			continue
		var r := _can_lead(grid, n, shapes, sids, prefer, i, bag)
		done[sid] = r
		ready[i] = r
	res["ready"] = ready
	return res


# --------------------------------------------------------------------------- #
# 탐색 속살
# --------------------------------------------------------------------------- #
#
# ★ 탐색은 격자가 아니라 **기둥 높이**만 본다. 조각이 위에서 내려와 앉으므로,
#   탐색이 지나갈 수 있는 판은 전부 "기둥마다 아래부터 빈틈없이 찬" 모양이다
#   (묻힌 구멍이 생기는 수는 그 자리에서 잘라 낸다). 그러면 판 하나가 정수 n개로
#   줄어들어서, 낙하 자리 계산도 상태 열쇠도 칸을 훑지 않고 끝난다.
#   격자를 그대로 훑던 판보다 열 배쯤 빠르다 — 조각을 놓을 때마다 아이가 기다리면
#   안 되니까 이게 중요하다.

## 기둥별 "맨 위 찬 칸의 줄 번호" (다 비었으면 n).
## 묻힌 구멍이 있으면 [] 를 돌려준다 — 그런 판은 어차피 못 채운다.
static func heights(grid: PackedInt32Array, n: int) -> PackedInt32Array:
	var h := PackedInt32Array()
	h.resize(n)
	for x in n:
		var y := 0
		while y < n and grid[y * n + x] < 0:
			y += 1
		h[x] = y
		for z in range(y, n):
			if grid[z * n + x] < 0:
				return PackedInt32Array()
	return h


## 모양 하나를 기둥 표로 바꾼다: [기둥 x, 그 기둥의 맨 윗칸 y, 맨 아랫칸 y] 의 나열.
##
## ★ 전제: 조각의 각 기둥이 **끊기지 않는다**. 우리 9조각과 그 회전은 전부 그렇고,
##   tests/kanoodle_check.gd 가 그것을 강제한다. ㄷ 자처럼 기둥이 끊긴 조각을
##   나중에 넣으면 이 표가 거짓말을 하게 된다.
static func prof_of(shape: Array) -> PackedInt32Array:
	var top := {}
	var bot := {}
	for cc: Vector2i in shape:
		if not top.has(cc.x) or cc.y < int(top[cc.x]):
			top[cc.x] = cc.y
		if not bot.has(cc.x) or cc.y > int(bot[cc.x]):
			bot[cc.x] = cc.y
	var xs: Array = top.keys()
	xs.sort()
	var out := PackedInt32Array()
	for x in xs:
		out.append(int(x))
		out.append(int(top[x]))
		out.append(int(bot[x]))
	return out


## 기둥 표 prof 의 조각을 dx 만큼 밀어 떨어뜨렸을 때 앉는 세로 오프셋. 못 들어가면 NO_DROP.
##
## ★ **탐색과 검사기가 이 함수 하나만 본다.** drop_dy() 가 격자에 대해 하는 일을 기둥
##   높이에 대해 하는 것이고, 둘이 어긋나면 "화면에서는 들어가는데 판정은 안 되는" 자리가
##   생긴다 — 눈으로는 절대 안 잡힌다. tests/kanoodle_check.gd 가 둘을 맞대어 본다.
## ★ **밑에 틈이 남으면 못 놓는 것으로 친다.** 조각은 위에서만 내려오므로 그 틈은
##   영영 못 채운다 (= buried()).
static func land_at(h: PackedInt32Array, n: int, prof: PackedInt32Array, dx: int) -> int:
	if prof.is_empty():
		return NO_DROP
	var dy := 9999
	for t in range(0, prof.size(), 3):
		var x := prof[t] + dx
		if x < 0 or x >= n:
			return NO_DROP              # 판 옆으로 삐져나간다
		dy = mini(dy, h[x] - 1 - prof[t + 2])
	if dy < 0:
		return NO_DROP                  # 다 쌓여서 조각이 판 안으로 못 들어온다
	for t in range(0, prof.size(), 3):
		if h[prof[t] + dx] - 1 - prof[t + 2] != dy:
			return NO_DROP              # 어느 기둥 밑에 틈이 남는다
	return dy


## 빈 칸 덩어리마다 "남은 조각으로 딱 떨어지는 크기"인가.
## 기둥 높이로 보면 덩어리는 **안 찬 기둥이 이어지는 구간**이다 (꽉 찬 기둥이 벽).
static func runs_ok(h: PackedInt32Array, n: int, sums: int) -> bool:
	var run := 0
	for x in n:
		if h[x] <= 0:
			if run > 0 and ((sums >> run) & 1) == 0:
				return false
			run = 0
		else:
			run += h[x]
	return run == 0 or ((sums >> run) & 1) == 1


## 상태 열쇠 = 기둥 높이 + 남은 조각들의 **모양 묶음별 개수**.
## ★ 조각 번호가 아니라 모양 묶음으로 센다. 그래야 쌍둥이를 바꿔 넣은 두 판이
##   같은 것으로 합쳐진다 (갈래가 반으로 준다).
static func _key_of(h: PackedInt32Array, n: int, counts: PackedInt32Array) -> int:
	var hc := 0
	for x in n:
		hc = hc * (n + 1) + h[x]
	var mc := 0
	for j in counts.size():
		mc = mc * 16 + counts[j]
	return hc * 4294967296 + mc


static func _solve(grid: PackedInt32Array, n: int, shapes: Array, sids: Array,
		prefer: Array, bag: Dictionary) -> Dictionary:
	var out: Array = []
	out.resize(shapes.size())
	for i in shapes.size():
		out[i] = []
	var order: Array = []
	var bad := {"ok": false, "at": out, "order": order, "capped": false}

	# 빈 칸 수와 남은 조각 칸 수가 안 맞으면 애초에 못 채운다.
	var empty := 0
	for i in n * n:
		if grid[i] < 0:
			empty += 1
	var total := 0
	for sh in shapes:
		if (sh as Array).is_empty():
			return bad
		total += (((sh as Array)[0]) as Array).size()
	if empty != total:
		return bad
	var h := heights(grid, n)
	if h.is_empty():
		return bad                      # 묻힌 구멍이 이미 있다

	var ids: Dictionary = bag["ids"]
	var prof: Array = []
	var size: Array = []
	var loc: Array = []
	var pref: Array = []                # pref[i] = [회전번호, dx, dy] 또는 []
	for i in shapes.size():
		var rots: Array = shapes[i]
		var ps: Array = []
		for sh: Array in rots:
			ps.append(prof_of(sh))
		prof.append(ps)
		size.append((rots[0] as Array).size())
		var sid := int(sids[i])
		if not ids.has(sid):
			ids[sid] = ids.size()
		loc.append(int(ids[sid]))
		pref.append(_pref_of(rots, prefer[i] if i < prefer.size() else []))

	# ★ 개수표는 **늘 같은 길이**로 만든다. 부르는 쪽마다 길이가 달라지면 같은 판이
	#   다른 열쇠가 되어 기억이 헛돈다.
	#   번호표가 MAX_LOC 을 넘으면 길이를 늘려 두고(넘겨쓰기 방지) 기억만 끈다.
	var counts := PackedInt32Array()
	counts.resize(maxi(MAX_LOC, ids.size()))
	counts.fill(0)
	var left: Array = []
	for i in shapes.size():
		left.append(i)
		counts[int(loc[i])] += 1

	var budget := [PLAN_CAP, 0]
	var ctx := {
		"n": n, "shapes": shapes, "prof": prof, "size": size, "loc": loc,
		"pref": pref, "memo": bag["memo"], "out": out, "order": order, "budget": budget,
		# 열쇠를 정수 하나로 담을 수 있는가 (모양 묶음 MAX_LOC 가지 · 조각 15개까지)
		"memo_on": ids.size() <= MAX_LOC and shapes.size() <= 15,
	}
	var ok := _dfs(h, left, counts, ctx)
	return {"ok": ok, "at": out, "order": order, "capped": int(budget[1]) == 1}


## 먼저 시도할 자리(칸 배열)를 [회전번호, dx, dy] 로 바꾼다. 없으면 [].
static func _pref_of(rots: Array, cells: Array) -> Array:
	if (cells as Array).is_empty():
		return []
	var mx := 9999
	var my := 9999
	for cc: Vector2i in cells:
		mx = mini(mx, cc.x)
		my = mini(my, cc.y)
	var key := NoodPieces.key(NoodPieces.normalize(cells))
	for r in rots.size():
		if NoodPieces.key(rots[r]) == key:
			return [r, mx, my]
	return []


static func _dfs(h: PackedInt32Array, left: Array, counts: PackedInt32Array,
		ctx: Dictionary) -> bool:
	var n := int(ctx["n"])
	if left.is_empty():
		for x in n:
			if h[x] != 0:
				return false            # 조각은 다 놨는데 빈 칸이 남았다
		return true
	var budget: Array = ctx["budget"]
	if budget[0] <= 0:
		if budget[1] == 0:
			stat_capped += 1
		budget[1] = 1
		return false
	budget[0] -= 1
	stat_nodes += 1

	var memo: Dictionary = ctx["memo"]
	var memo_on := bool(ctx["memo_on"])
	var key := 0
	if memo_on:
		key = _key_of(h, n, counts)
		if memo.has(key):
			return false                # 이미 막힌 것으로 판명된 판

	var prof: Array = ctx["prof"]
	var size: Array = ctx["size"]
	var loc: Array = ctx["loc"]
	var pref: Array = ctx["pref"]

	# 후보 모으기 — [조각번호, 회전번호, dx, dy].
	# **모양 묶음이 같은 조각은 한 번만** 본다 (쌍둥이가 갈래를 두 배로 늘리지 않게).
	var pref_c: Array = []
	var rest_c: Array = []
	var scratch := PackedInt32Array()
	scratch.resize(n)
	var seen := {}
	for k in left.size():
		var i := int(left[k])
		var lo := int(loc[i])
		if seen.has(lo):
			continue
		seen[lo] = true
		# 이 조각을 뺀 나머지로 만들 수 있는 칸 수 (빈 덩어리 크기 가지치기)
		var sums := 1
		for k2 in left:
			if int(k2) != i:
				sums |= sums << int(size[int(k2)])
		var want: Array = pref[i]
		var rots: Array = prof[i]
		for r in rots.size():
			var p: PackedInt32Array = rots[r]
			for dx in n:
				var dy := land_at(h, n, p, dx)
				if dy == NO_DROP:
					continue
				for x in n:
					scratch[x] = h[x]
				for t in range(0, p.size(), 3):
					scratch[p[t] + dx] = dy + p[t + 1]
				if not runs_ok(scratch, n, sums):
					continue
				if not want.is_empty() and int(want[0]) == r and int(want[1]) == dx \
						and int(want[2]) == dy:
					pref_c.append([i, r, dx, dy])
				else:
					rest_c.append([i, r, dx, dy])
	pref_c.append_array(rest_c)

	var shapes: Array = ctx["shapes"]
	var out: Array = ctx["out"]
	var order: Array = ctx["order"]
	for cand: Array in pref_c:
		var i := int(cand[0])
		var r := int(cand[1])
		var dx := int(cand[2])
		var dy := int(cand[3])
		var p: PackedInt32Array = (prof[i] as Array)[r]
		var back := PackedInt32Array()
		back.resize(p.size() / 3)
		var t2 := 0
		for t in range(0, p.size(), 3):
			back[t2] = h[p[t] + dx]
			h[p[t] + dx] = dy + p[t + 1]
			t2 += 1
		var pos := left.find(i)
		left.remove_at(pos)
		counts[int(loc[i])] -= 1
		var good := _dfs(h, left, counts, ctx)
		counts[int(loc[i])] += 1
		left.insert(pos, i)
		t2 = 0
		for t in range(0, p.size(), 3):
			h[p[t] + dx] = back[t2]
			t2 += 1
		if good:
			# ★ 자리(칸 배열)는 **성공한 갈래에서만** 만든다. 실패하는 갈래가 훨씬
			#   많아서, 여기서 미리 만들면 그게 곧 탐색 비용이 된다.
			var cells: Array = []
			for cc: Vector2i in ((shapes[i] as Array)[r] as Array):
				cells.append(Vector2i(cc.x + dx, cc.y + dy))
			out[i] = cells
			order.push_front(i)
			return true
		if budget[0] <= 0:
			if budget[1] == 0:
				stat_capped += 1
			budget[1] = 1
			return false
	if memo_on:
		memo[key] = true
	return false


## i 번 조각을 **지금 첫 수로** 놓을 자리가 하나라도 있는가.
static func _can_lead(grid: PackedInt32Array, n: int, shapes: Array, sids: Array,
		prefer: Array, i: int, bag: Dictionary) -> bool:
	for sh: Array in (shapes[i] as Array):
		for col in n:
			var dy := drop_dy(grid, n, sh, col)
			if dy == NO_DROP:
				continue
			var cells: Array = []
			for cc: Vector2i in sh:
				cells.append(Vector2i(cc.x + col, cc.y + dy))
			if _fits_at(grid, n, shapes, sids, prefer, i, cells, bag):
				return true
	return false


static func _fits_at(grid: PackedInt32Array, n: int, shapes: Array, sids: Array,
		prefer: Array, i: int, cells: Array, bag: Dictionary) -> bool:
	var g := grid.duplicate()
	for cc: Vector2i in cells:
		if cc.x < 0 or cc.y < 0 or cc.x >= n or cc.y >= n or g[cc.y * n + cc.x] >= 0:
			return false
		g[cc.y * n + cc.x] = 1
	# ★ 값싼 가지치기를 먼저. 안 되는 자리는 거의 다 여기서 걸려서 탐색까지 안 간다 —
	#   조각 하나 놓을 때마다 자리를 수십 곳 물어보므로 이 순서가 곧 반응 속도다.
	if buried(g, n):
		return false
	var rest: Array = []
	var rest_sids: Array = []
	var rest_pref: Array = []
	var sums := 1
	for k in shapes.size():
		if k != i:
			rest.append(shapes[k])
			rest_sids.append(sids[k])
			rest_pref.append(prefer[k] if k < prefer.size() else [])
			sums |= sums << ((((shapes[k] as Array)[0]) as Array).size())
	if not _regions_ok(g, n, sums):
		return false
	var r := _solve(g, n, rest, rest_sids, rest_pref, bag)
	# "모르겠다"(한도 초과)로 끝났으면 **막지 않는다** — 아이 화면에서는 되는 걸 막는 것이
	# 제일 나쁘다. 이때 아주 드물게 못 채우는 자리가 들어갈 수 있는데, 그러면 바로 다음
	# _refresh 가 "계획 없음"을 깨끗하게 판정해서 힌트가 들어낼 조각을 가리킨다
	# (kanoodle.gd 의 _stuck). 즉 막다른 판이 아니라 되돌리기 한 번으로 끝난다.
	return bool(r["ok"]) or bool(r["capped"])


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
