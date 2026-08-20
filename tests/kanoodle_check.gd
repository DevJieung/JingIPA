## 블록 채우기 — 퍼즐 생성기가 **항상 풀 수 있는 판**을 내는지, 그리고 **모양만 맞으면
## 어디든 들어가는지**를 무더기로 검사한다.
##
## ★ 생성이 역방향(먼저 덮고 일부를 뺀다)이라 해답을 이미 들고 있다.
##   그래도 "정말 덮였는가"를 격자로 다시 세어 확인한다 — 생성기가 조용히 실패하면
##   아이 화면에 빈 판이 뜬다.
##
## ★ 덮였다고 풀리는 게 아니다. 조각이 **떨어져서 쌓이므로**, 해답이 멀쩡해도
##   위에 뭔가 얹힌 조각을 문제로 내면 아이는 그 조각을 제자리에 못 보낸다.
##   그래서 실제로 한 조각씩 떨어뜨려 보는 검사(NoodGen.drop_check)를 같이 돌린다.
##
## ★ 그리고 여기서만 잡히는 것: **아무 데나 넣어도 판이 끝나는가.**
##   자리 판정이 "해답에 적힌 그 자리"에서 "끝까지 채울 수 있는가"로 바뀌었다.
##   아이는 안내대로 놓지 않는다 — 되는 자리를 찾아 아무 데나 넣어 본다.
##   그래서 계획을 아예 안 보고 **무작위로 되는 자리**만 골라 끝까지 가 보는 검사가 있다.
##   여기가 깨지면 아이가 판 한가운데서 갇힌다.
##
##   ~/.local/bin/godot --headless --path . res://tests/kanoodle_check.tscn
##   ~/.local/bin/godot --headless --path . res://tests/kanoodle_check.tscn -- --pre
extends Node

const ROUNDS := 40      # 유효탄마다 몇 판씩
const STAGES := [1, 3, 5, 8, 10, 14, 18, 22, 30, 50, 100]
## 진짜 씬을 띄워 끝까지 플레이해 볼 탄 (격자·조각수·안내·회전이 다 바뀌는 지점들)
const PLAY_STAGES := [1, 5, 10, 16, 24, 40]
## 아무 데나 넣어 보는 판을 탄마다 몇 번씩
const FREE_RUNS := 3

## "놓을 자리가 있는데 트레이는 차례가 아니라고 한다"가 몇 번 났는가 (0 이어야 한다)
var _ready_bad := 0
## 자유도 통계 — [들어가는 자리 수, 그중 계획과 다른 자리 수]
var _free_slots := 0
var _free_extra := 0
var _refresh_us := 0
var _refresh_n := 0
var _refresh_nodes := 0


func _ready() -> void:
	Shell.save_disabled = true
	Engine.max_fps = 0
	NoodGen.stat_capped = 0
	if "--pre" in OS.get_cmdline_user_args():
		Shell.profile()["age_band"] = "pre"
		Shell.profile()["tuning"] = Shell.default_tuning("pre")
	var t := Shell.tuning()
	print("   프로필: %s" % String(Shell.profile()["age_band"]))
	print("   %6s %5s %6s %6s %7s %8s %8s %10s" %
			["E", "격자", "놓기", "안내", "회전", "생성실패", "낙하실패", "평균시도"])

	var rng := RandomNumberGenerator.new()
	var fail := 0
	var bad_cover := 0
	var bad_drop := 0
	var total := 0
	for e in STAGES:
		var ax := NoodGen.axes(e, t)
		var f := 0
		var d := 0
		var ms := 0
		for r in ROUNDS:
			rng.seed = hash("k_%d_%d" % [e, r])
			var t0 := Time.get_ticks_usec()
			var pz := NoodGen.make(ax, rng)
			ms += Time.get_ticks_usec() - t0
			total += 1
			if pz.is_empty():
				f += 1
				fail += 1
				continue
			if not _covers(pz):
				bad_cover += 1
			# 진짜로 떨어뜨려 본다 — 여기서 걸리면 아이가 못 푸는 판이다
			if not NoodGen.drop_check(pz):
				d += 1
				bad_drop += 1
		print("   %6d %5s %6d %6d %7s %8d %8d %9.1fms" %
				[e, "%dx%d" % [int(ax["n"]), int(ax["n"])], int(ax["place"]),
				 int(ax["guide"]), "예" if bool(ax["rotate"]) else "아니오",
				 f, d, float(ms) / float(ROUNDS) / 1000.0])

	# 조각 회전 표가 온전한지 (같은 모양이 중복되면 돌리기 버튼이 헛돈다)
	var rot_bad := 0
	for pi in NoodPieces.count():
		var rots := NoodPieces.rotations(pi)
		if rots.is_empty() or rots.size() > 4:
			rot_bad += 1
		for r in rots:
			if (r as Array).size() != NoodPieces.size_of(pi):
				rot_bad += 1

	# 중력 규칙이 뒤집히지 않았는지 (묻힌 구멍은 영영 못 채운다)
	var bury_bad := _bury_check()
	# 빠른 탐색이 딛고 선 두 전제가 아직 참인지
	var contig_bad := _contig_check()
	var equiv_bad := _equiv_check()

	# 생성기가 아니라 **게임 코드**로 실제로 떨어뜨려 끝까지 풀어 본다.
	var play_bad := await _play_stages()
	# 되들다가 갇혔을 때 스스로 빠져나올 수 있는가
	var stuck_bad := await _stuck_check()
	# 판을 못 채우게 만드는 자리는 정말로 안 받는가
	var reject_bad := await _reject_check()
	# 어린 프로필: 판만 두드려도 놀이가 굴러가는가
	var auto_bad := await _auto_check()
	# "대강 맞으면 들어간다" 가 정말 그런가, 그리고 더 헐거워지지는 않았는가
	var snap_bad := await _snap_check()

	var ok := fail == 0 and bad_cover == 0 and bad_drop == 0 and rot_bad == 0 \
			and play_bad == 0 and bury_bad == 0 and _ready_bad == 0 \
			and contig_bad == 0 and equiv_bad == 0 and stuck_bad == 0 and auto_bad == 0 \
			and reject_bad == 0 and snap_bad == 0 and NoodGen.stat_capped == 0
	print("%s 판 %d개: 생성실패 %d건, 덮기이상 %d건, 낙하불가 %d건, 회전표이상 %d건, 플레이실패 %d건"
			% ["  " if ok else "!!", total, fail, bad_cover, bad_drop, rot_bad, play_bad])
	print("%s 묻힌구멍 판정이상 %d건, 트레이 거짓말 %d건, 기둥 끊긴 조각 %d개, 빠른길 어긋남 %d건" %
			["  " if (bury_bad == 0 and _ready_bad == 0 and contig_bad == 0
					and equiv_bad == 0) else "!!",
			 bury_bad, _ready_bad, contig_bad, equiv_bad])
	# 자유도 — 옛 규칙에서는 조각마다 들어가는 자리가 **딱 하나**(해답 자리)였다.
	print("%s 갇힘 탈출 실패 %d건, 자동집기 실패 %d건, 나쁜자리 통과 %d건, 탐색포기 %d건, 대강맞추기 이상 %d건" %
			["  " if (stuck_bad == 0 and auto_bad == 0 and reject_bad == 0
					and snap_bad == 0 and NoodGen.stat_capped == 0) else "!!",
			 stuck_bad, auto_bad, reject_bad, NoodGen.stat_capped, snap_bad])
	print("   자유도: 첫 판에서 들어가는 자리 %d곳 (그중 계획과 다른 자리 %d곳)"
			% [_free_slots, _free_extra])
	print("   계획 다시 세우기: 평균 %.1fms · 판 %d개씩 (%d회)"
			% [float(_refresh_us) / float(maxi(1, _refresh_n)) / 1000.0,
			   _refresh_nodes / maxi(1, _refresh_n), _refresh_n])
	if _free_extra <= 0:
		print("!! 계획과 다른 자리가 한 곳도 없습니다 — 자유 배치가 안 걸렸습니다")
		ok = false
	print("   판정: %s" % ("정상" if ok else "이상"))
	get_tree().quit(0 if ok else 1)


## 묻힌 구멍(위가 막힌 빈 칸) 판정이 살아 있는가.
## ★ 이 판정이 뒤집히면 "여기 놓아도 된다"가 거짓이 되고, 아이가 판 한가운데서 갇힌다.
func _bury_check() -> int:
	var bad := 0
	var g := PackedInt32Array()
	g.resize(9)
	g.fill(-1)
	if NoodGen.buried(g, 3):
		bad += 1                        # 텅 빈 판에는 묻힌 구멍이 없다
	g[0 * 3 + 1] = 1                    # 가운데 기둥 맨 위만 찼다
	if not NoodGen.buried(g, 3):
		bad += 1                        # 그 아래 두 칸은 영영 못 채운다
	g.fill(-1)
	g[2 * 3 + 1] = 1                    # 가운데 기둥 맨 아래만 찼다
	if NoodGen.buried(g, 3):
		bad += 1                        # 위가 뚫려 있으므로 멀쩡하다
	return bad


## ★ 생성기가 멀쩡해도 게임의 조작·판정이 어긋나면 아이는 못 푼다. 그래서 진짜 씬을
##   띄워서 두 가지로 끝까지 가 본다:
##     계획대로 — 안내를 따라가는 아이
##     아무 데나 — 되는 자리를 찾아 넣어 보는 아이 (이쪽이 진짜 아이에 가깝다)
##   여기서 misses 가 나오면 **놓을 수 있다고 해 놓고 안 받았다**는 뜻이다.
func _play_stages() -> int:
	var bad := 0
	var rng := RandomNumberGenerator.new()
	print("   %6s %8s %8s %8s %8s %10s" % ["탄", "계획드롭", "빗나감", "자유드롭", "자유빗나감", "결과"])
	for st in PLAY_STAGES:
		var g: Node = load("res://games/kanoodle/kanoodle.tscn").instantiate()
		add_child(g)
		# 크기는 안 건드린다 — 배치 함수가 전부 W/H 상수를 쓰고, _on_tap 은 이미
		# 그 좌표계를 받는다. 여기서 size 를 넣으면 앵커 경고만 나온다.
		g.set("dev_mode", true)
		# ★ 숨은 손잡이(skill)를 탄마다 0 으로 되돌린다. 한 판 깰 때마다 오르기 때문에,
		#   안 되돌리면 뒤쪽 탄들이 전부 상한(+10)에 붙어 **이름과 다른 판**을 검사하게 된다.
		_reset_skill(st)
		g.set("stage", st)
		g.call("_build")
		if not bool(g.get("_plan_ok")):
			print("!! %d탄: 첫 계획이 안 섰습니다" % st)
			bad += 1
		_tally_freedom(g)
		NoodGen.stat_nodes = 0
		var t0 := Time.get_ticks_usec()
		g.call("_refresh")
		_refresh_us += Time.get_ticks_usec() - t0
		_refresh_nodes += NoodGen.stat_nodes
		_refresh_n += 1

		var drops := await _play_one(g)
		var done := bool(g.get("_done"))
		var misses := int(g.get("_misses"))
		if not done or misses != 0 or drops < 0:
			bad += 1

		# 이번엔 계획을 아예 안 보고 아무 데나
		var fdrops := 0
		var fmiss := 0
		var free_bad := false
		for k in FREE_RUNS:
			rng.seed = hash("free_%d_%d" % [st, k])
			_reset_skill(st)
			g.call("_build")
			# 판마다 자유도를 센다 — 한 판만 보면 "계획과 다른 자리 0곳"이 우연히 나온다
			_tally_freedom(g)
			var d2 := await _play_free(g, rng)
			fdrops += maxi(0, d2)
			fmiss += int(g.get("_misses"))
			if d2 < 0 or not bool(g.get("_done")):
				print("!! %d탄 자유 배치 %d번째: 끝까지 못 갔습니다 (%d수)" % [st, k, d2])
				bad += 1
				free_bad = true
		if fmiss != 0:
			bad += 1
		print("   %6d %8d %8d %8d %8d %10s"
				% [st, drops, misses, fdrops, fmiss,
				   "정상" if (done and misses == 0 and fmiss == 0 and drops >= 0
						and not free_bad) else "이상"])
		g.queue_free()
		await get_tree().process_frame
	return bad


## 이 프로필의 숨은 손잡이를 0 으로. (검사기가 이름 그대로의 탄을 보게 한다)
func _reset_skill(st: int) -> void:
	Shell.profile()["kanoodle"] = {"best_stage": maxi(1, st), "skill": 0, "cleared": 0}


func _tally_freedom(g: Node) -> void:
	var fr := _freedom(g)
	_free_slots += fr.x
	_free_extra += fr.y


## 갓 만든 판에서 "지금 들어가는 자리"가 몇 곳인가.
## 반환: Vector2i(들어가는 자리 수, 그중 계획과 다른 자리 수)
##
## ★ 옛 규칙에서는 조각마다 자리가 **딱 하나**였다 (해답에 적힌 그 자리). 그래서
##   모양이 맞는 빈 자리에 제대로 넣어도 튕겼다. 두 번째 숫자가 0 이면 그 시절로
##   되돌아간 것이다.
func _freedom(g: Node) -> Vector2i:
	var n := int(g.get("_n"))
	var grid: PackedInt32Array = g.get("_grid")
	var shapes: Array = g.call("_shapes")
	var plan: Array = g.get("_plan")
	var bag: Dictionary = g.get("_bag")
	var slots := 0
	var extra := 0
	for i in shapes.size():
		for sh: Array in (shapes[i] as Array):
			for col in n:
				var lz := _land_col(g, sh, col)
				if lz.is_empty() or not NoodGen.fits(grid, n, shapes, i, lz["cells"], bag):
					continue
				slots += 1
				if not _same(lz["cells"], plan[i]):
					extra += 1
	return Vector2i(slots, extra)


## 한 판을 끝까지 — **계획대로**. 반환: 떨어뜨린 횟수 (막히면 -1)
func _play_one(g: Node) -> int:
	var drops := 0
	for guard in 400:
		if bool(g.get("_done")):
			return drops
		if not (g.get("_falling") as Dictionary).is_empty():
			await get_tree().process_frame
			continue
		var tray: Array = g.get("_tray")
		if tray.is_empty():
			await get_tree().process_frame
			continue
		# 힌트가 가리키는 조각을 그대로 따라간다 = **안내를 믿는 아이**.
		# ★ 검사기가 정답 순서를 미리 알고 있으면 안 된다. 게임에게 그때그때 묻는다.
		var plan: Array = g.get("_plan")
		var pick := int(g.get("_plan_next"))
		if pick < 0 or pick >= tray.size() or (plan[pick] as Array).is_empty():
			return -1                       # 놓을 수 있는 조각이 없다 = 아이가 갇혔다
		if not bool(g.call("_ready_now", pick)):
			return -1                       # 힌트와 트레이가 서로 다른 말을 한다
		if not await _drop_at(g, pick, plan[pick]):
			return -1
		drops += 1
	return -1


## 한 판을 끝까지 — **아무 데나**. 매 수마다 "지금 들어가는 모든 자리"를 모아
## 무작위로 하나를 고른다. 계획도 해답도 안 본다.
func _play_free(g: Node, rng: RandomNumberGenerator) -> int:
	var drops := 0
	for guard in 400:
		if bool(g.get("_done")):
			return drops
		if not (g.get("_falling") as Dictionary).is_empty():
			await get_tree().process_frame
			continue
		var tray: Array = g.get("_tray")
		if tray.is_empty():
			await get_tree().process_frame
			continue
		var n := int(g.get("_n"))
		var grid: PackedInt32Array = g.get("_grid")
		var shapes: Array = g.call("_shapes")
		var bag: Dictionary = g.get("_bag")
		var moves: Array = []
		for i in tray.size():
			var any := false
			for sh: Array in (shapes[i] as Array):
				for col in n:
					var lz := _land_col(g, sh, col)
					if lz.is_empty():
						continue
					if not NoodGen.fits(grid, n, shapes, i, lz["cells"], bag):
						continue
					moves.append({"i": i, "cells": lz["cells"]})
					any = true
			# 놓을 자리가 있는데 트레이가 "아직 차례가 아니야"라고 흔들면 거짓말이다.
			# (반대로 차례라고 해 놓고 자리가 없어도 거짓말이다.)
			if any != bool(g.call("_ready_now", i)):
				_ready_bad += 1
		if moves.is_empty():
			return -1
		var m: Dictionary = moves[rng.randi_range(0, moves.size() - 1)]
		if not await _drop_at(g, int(m["i"]), m["cells"]):
			return -1
		drops += 1
	return -1


## 조각 i 를 cells 자리로 보낸다 (들기 -> 모양 맞추기 -> 그 기둥 두드리기).
func _drop_at(g: Node, i: int, cells: Array) -> bool:
	var slot: Rect2 = g.call("_tray_slot", i)
	g.call("_on_tap", slot.position + slot.size * 0.5)
	if (g.get("_held") as Dictionary).is_empty():
		return false                        # 안 들렸다 = 차례 안내와 실제가 어긋났다
	var want_key := NoodPieces.key(g.call("_shape_of", cells))
	for r in 4:
		var t2: Array = g.get("_tray")
		if i >= t2.size():
			return false
		if NoodPieces.key(NoodPieces.normalize((t2[i] as Dictionary)["rot"])) == want_key:
			break
		g.call("_rotate_held")
	# 누를 **기둥** = 조각의 기준칸이 놓일 기둥 (왼쪽 위에서 처음 채워진 칸)
	var at: Vector2i = cells[0]
	for c in cells:
		var v: Vector2i = c
		if v.y < at.y or (v.y == at.y and v.x < at.x):
			at = v
	var br: Rect2 = g.call("_board_rect")
	var cell: float = g.call("_cell")
	g.call("_on_tap", br.position
			+ Vector2((float(at.x) + 0.5) * cell, (float(at.y) + 0.5) * cell))
	await get_tree().process_frame
	return true


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var have := {}
	for cc in a:
		have[cc] = true
	for cc in b:
		if not have.has(cc):
			return false
	return true


## 해답이 정말 격자를 빈틈없이, 겹치지 않게 덮는가.
func _covers(pz: Dictionary) -> bool:
	var n := int(pz["n"])
	var seen := PackedInt32Array()
	seen.resize(n * n)
	seen.fill(0)
	for e in (pz["solution"] as Array):
		for c in ((e as Dictionary)["cells"] as Array):
			var v: Vector2i = c
			if v.x < 0 or v.y < 0 or v.x >= n or v.y >= n:
				return false
			seen[v.y * n + v.x] += 1
	for i in n * n:
		if seen[i] != 1:
			return false
	# 트레이 + 미리놓기 = 해답 전체여야 한다
	return (pz["tray"] as Array).size() + (pz["fixed"] as Array).size() \
			== (pz["solution"] as Array).size()


## 조각의 기둥이 끊기지 않는가 (ㄷ 자처럼 가운데가 빈 기둥이 없는가).
##
## ★ 빠른 탐색은 조각을 "기둥마다 [맨 윗칸, 맨 아랫칸]" 두 숫자로만 본다 (_prof_of).
##   기둥이 끊긴 조각을 조각 세트에 넣는 순간 그 표가 거짓말이 되고, 놓을 수 있는
##   자리를 잘못 계산하기 시작한다. 그래서 여기서 전제를 못 박아 둔다.
func _contig_check() -> int:
	var bad := 0
	for pi in NoodPieces.count():
		for sh: Array in NoodPieces.rotations(pi):
			var col := {}
			for cc: Vector2i in sh:
				if not col.has(cc.x):
					col[cc.x] = []
				(col[cc.x] as Array).append(cc.y)
			for x in col:
				var ys: Array = col[x]
				ys.sort()
				for k in range(1, ys.size()):
					if int(ys[k]) != int(ys[k - 1]) + 1:
						bad += 1
						break
	return bad


## 빠른 길(기둥 높이)과 느린 길(격자)이 같은 답을 내는가.
##
## ★ 탐색은 격자를 안 훑고 기둥 높이만 본다. 그 지름길이 원래 규칙과 어긋나면
##   "화면에서는 들어가는데 판정은 안 된다"(또는 그 반대)가 되는데, 눈으로는
##   절대 안 잡힌다. 그래서 무작위 판마다 두 길을 직접 맞대어 본다:
##     낙하 자리      drop_dy(격자)            vs 기둥 높이로 잰 값
##     묻힌 구멍      buried(격자)             vs "틈 없이 앉았는가"
##     빈 덩어리 크기 _regions_ok(격자)        vs _runs_ok(기둥 높이)
func _equiv_check() -> int:
	var bad := 0
	var rng := RandomNumberGenerator.new()
	for t in 400:
		rng.seed = hash("eq_%d" % t)
		var n := rng.randi_range(4, 6)
		# 아무렇게나 쌓인 판 하나 (기둥마다 아래부터 찬 모양 — 탐색이 보는 판이다)
		var grid := PackedInt32Array()
		grid.resize(n * n)
		grid.fill(-1)
		for x in n:
			var fill := rng.randi_range(0, n)
			for y in range(n - fill, n):
				grid[y * n + x] = 1
		var h := NoodGen.heights(grid, n)
		if h.is_empty():
			bad += 1                        # 아래부터 채웠으니 묻힌 구멍이 있을 리 없다
			continue
		for x in n:
			if h[x] < n and grid[h[x] * n + x] < 0:
				bad += 1                    # 높이가 가리키는 칸은 차 있어야 한다
		var pi := rng.randi_range(0, NoodPieces.count() - 1)
		var rots: Array = NoodPieces.rotations(pi)
		var sh: Array = rots[rng.randi_range(0, rots.size() - 1)]
		var prof: PackedInt32Array = NoodGen.prof_of(sh)
		var sums := 1 << (sh.size())        # 남은 조각이 이 조각 하나뿐이라고 치고
		for dx in n:
			# 느린 길 — 격자를 그대로 훑는다
			var dy := NoodGen.drop_dy(grid, n, sh, dx)
			var slow_ok := dy != NoodGen.NO_DROP
			var g2 := grid.duplicate()
			if slow_ok:
				for cc: Vector2i in sh:
					g2[(cc.y + dy) * n + cc.x + dx] = 1
				slow_ok = not NoodGen.buried(g2, n)
			# 빠른 길 — **탐색이 실제로 부르는 그 함수** (여기 베껴 쓰면 검사가 헛돈다)
			var fdy := NoodGen.land_at(h, n, prof, dx)
			var fast_ok := fdy != NoodGen.NO_DROP
			if slow_ok != fast_ok or (slow_ok and fdy != dy):
				bad += 1
				continue
			if not slow_ok:
				continue
			# 빈 덩어리 크기 판정도 두 길이 같아야 한다
			var h2 := h.duplicate()
			for k in range(0, prof.size(), 3):
				h2[prof[k] + dx] = fdy + prof[k + 1]
			if NoodGen._regions_ok(g2, n, sums) != NoodGen.runs_ok(h2, n, sums):
				bad += 1

	# 묻힌 구멍이 **있는** 판에서도 두 길이 같은 말을 하는가
	for t in 200:
		rng.seed = hash("eqb_%d" % t)
		var n := rng.randi_range(4, 6)
		var grid := PackedInt32Array()
		grid.resize(n * n)
		grid.fill(-1)
		for i in n * n:
			if rng.randf() < 0.45:
				grid[i] = 1
		if NoodGen.buried(grid, n) != NoodGen.heights(grid, n).is_empty():
			bad += 1
	return bad


## 되들다가 구멍이 묻혔을 때, 아이가 **스스로 빠져나올 수 있는가**.
##
## ★ 자유 배치가 막다른 판을 안 만든다고 해도, 판 위의 조각을 도로 드는 길은 그대로
##   열려 있다 — 그리고 그 길로는 갇힐 수 있다. 위에 다른 조각이 얹힌 조각을 들어내면
##   그 자리는 묻힌 구멍이 되어 아무 조각도 못 들어간다. 그때 힌트가 **들어낼 조각**을
##   가리켜야 하고, 그 말을 따라가면 반드시 풀려야 한다. 안 그러면 아이는 판만 본다.
func _stuck_check() -> int:
	var bad := 0
	var made := 0
	for st in [10, 18, 30]:
		var g: Node = load("res://games/kanoodle/kanoodle.tscn").instantiate()
		add_child(g)
		g.set("dev_mode", true)
		g.set("stage", st)
		g.call("_build")
		# 계획대로 끝까지 놓아서 판을 꽉 채운다
		await _play_one(g)
		if not bool(g.get("_done")):
			g.queue_free()
			await get_tree().process_frame
			continue
		# 이제 **위에 뭔가 얹힌** 조각을 도로 든다 -> 그 자리가 묻힌 구멍이 된다
		var board: Array = g.get("_board")
		var n := int(g.get("_n"))
		var pick := -1
		for i in board.size():
			var b: Dictionary = board[i]
			if bool(b["fixed"]):
				continue
			var covered := false
			for cc: Vector2i in (b["cells"] as Array):
				if cc.y > 0 and int((g.get("_grid") as PackedInt32Array)[(cc.y - 1) * n + cc.x]) >= 0 \
						and not _has(b["cells"], Vector2i(cc.x, cc.y - 1)):
					covered = true
			if covered:
				pick = i
				break
		if pick < 0:
			g.queue_free()
			await get_tree().process_frame
			continue
		g.call("_pick_up", pick)
		g.set("_held", {})
		if bool(g.get("_plan_ok")):
			# 묻히지 않았다면 이 판은 검사 대상이 아니다 (들어낸 자리가 위에서 뚫려 있었다)
			g.queue_free()
			await get_tree().process_frame
			continue
		made += 1
		# ★ 기다림(idle) 없이 **바로** 떠 있어야 한다. 답답해서 자꾸 두드리는 아이는
		#   기다림이 매번 0으로 돌아가서 힌트를 영영 못 본다.
		if (g.get("_hint_cells") as Array).is_empty():
			print("!! %d탄: 갇혔는데 탈출 안내가 바로 안 떴습니다" % st)
			bad += 1
		# 힌트를 따라 걷어내면 반드시 풀려야 한다
		var freed := false
		for step in 12:
			g.call("_show_hint")
			var hint: Array = g.get("_hint_cells")
			if hint.is_empty():
				break
			var at := -1
			var bd: Array = g.get("_board")
			for i in bd.size():
				if _same((bd[i] as Dictionary)["cells"], hint):
					at = i
					break
			if at < 0:
				break                       # 힌트가 판 위의 조각을 안 가리켰다
			g.call("_pick_up", at)
			g.set("_held", {})
			if bool(g.get("_plan_ok")):
				freed = true
				break
		if not freed:
			print("!! %d탄: 되들다 갇힌 판에서 못 빠져나왔습니다" % st)
			bad += 1
		g.queue_free()
		await get_tree().process_frame
	print("   갇힌 판 %d개를 만들어 힌트만 보고 빠져나와 봤습니다" % made)
	if made == 0:
		print("!! 갇힌 판을 한 번도 못 만들어 봤습니다 — 검사가 헛돌고 있습니다")
		bad += 1
	return bad


## 어린 프로필(nood_autopick): 손이 비어도 **판만 두드리면** 조각이 들려 떨어지는가.
func _auto_check() -> int:
	if not bool(Shell.tune("nood_autopick", false)):
		print("   자동집기: 이 프로필에는 없음 (--pre 로 검사한다)")
		return 0
	var bad := 0
	for st in [1, 8]:
		var g: Node = load("res://games/kanoodle/kanoodle.tscn").instantiate()
		add_child(g)
		g.set("dev_mode", true)
		g.set("stage", st)
		g.call("_build")
		var before := (g.get("_tray") as Array).size()
		var br: Rect2 = g.call("_board_rect")
		var cell: float = g.call("_cell")
		var n := int(g.get("_n"))
		# 기둥을 하나씩 두드려 본다 — 어딘가는 반드시 들어가야 한다
		var moved := false
		for col in n:
			g.set("_held", {})
			g.call("_on_tap", br.position + Vector2((float(col) + 0.5) * cell, cell * 0.5))
			for f in 30:
				if (g.get("_falling") as Dictionary).is_empty():
					break
				await get_tree().process_frame
			if (g.get("_tray") as Array).size() < before:
				moved = true
				break
		if not moved:
			print("!! %d탄: 판을 두드려도 조각이 안 들어갔습니다" % st)
			bad += 1
		g.queue_free()
		await get_tree().process_frame
	return bad


## 이 모양의 **기준칸을 col 기둥에 맞춰** 떨어뜨리면 앉는 자리 — 물리만 본다.
##
## ★ 게임이 실제로 쓰는 것은 `_snap` 이다 (누른 기둥을 **덮는** 자리 중에서 고른다).
##   여기서는 "예전 규칙이라면 어디에 앉았을까"를 알아야 해서 낮은 층을 직접 부른다.
func _land_col(g: Node, sh: Array, col: int) -> Dictionary:
	var a: Vector2i = g.call("_anchor_of", sh)
	return g.call("_land_at", sh, col - a.x)


func _has(cells: Array, v: Vector2i) -> bool:
	for cc in cells:
		if (cc as Vector2i) == v:
			return true
	return false


## 판을 못 채우게 만드는 자리는 **정말로 안 받는가.**
##
## ★ 이 문(`kanoodle.gd` 의 `_falling["ok"]`)을 통째로 지워도 나머지 검사는 전부
##   통과한다 — 플레이 검사기들이 하나같이 "되는 자리"만 골라 넣기 때문이다.
##   그래서 여기서만 일부러 **안 되는 데**에 떨어뜨려 보고, 판이 안 바뀌는지 본다.
##   이게 없으면 자유 배치의 유일한 안전장치가 아무도 안 보는 코드가 된다.
##
## ★ 묻는 것이 "나쁜 **자리**"에서 "나쁜 **기둥**"으로 바뀌었다. `_snap` 이 생긴 뒤로는
##   물리적으로만 앉는 나쁜 자리를 눌러도 옆으로 밀어 살려 주므로, 그 조건으로는
##   튕김을 영영 못 본다 (검사가 조용히 헛돌게 된다). 실제로 물어야 하는 것은
##   **"이 기둥을 눌렀을 때 나쁜 자리가 들어가 버리는가"** 다.
func _reject_check() -> int:
	var bad := 0
	var tried := 0
	for st in [5, 10, 18, 24, 40]:
		_reset_skill(st)
		var g: Node = load("res://games/kanoodle/kanoodle.tscn").instantiate()
		add_child(g)
		g.set("dev_mode", true)
		g.set("stage", st)
		g.call("_build")
		var n := int(g.get("_n"))
		var grid: PackedInt32Array = g.get("_grid")
		var shapes: Array = g.call("_shapes")
		var bag: Dictionary = g.get("_bag")
		# 아무리 옆으로 밀어도 판을 못 채우게 되는 **기둥**을 찾는다
		var pick := -1
		var pick_sh: Array = []
		var pick_col := -1
		for i in shapes.size():
			if not bool(g.call("_ready_now", i)):
				continue                    # 못 드는 조각으로는 시험할 수 없다
			for sh: Array in (shapes[i] as Array):
				for col in n:
					var lz: Dictionary = g.call("_snap", i, sh, col)
					if lz.is_empty() or bool(lz["ok"]):
						continue
					pick = i
					pick_sh = sh
					pick_col = col
					break
				if pick >= 0:
					break
			if pick >= 0:
				break
		if pick < 0:
			g.queue_free()
			await get_tree().process_frame
			continue                        # 이 판에는 나쁜 기둥이 없다 (드물다)
		tried += 1
		var before_tray := (g.get("_tray") as Array).size()
		var before_grid := (g.get("_grid") as PackedInt32Array).duplicate()
		g.set("_misses", 0)
		await _drop_into(g, pick, pick_sh, pick_col)
		for f in 60:
			if (g.get("_falling") as Dictionary).is_empty():
				break
			await get_tree().process_frame
		if (g.get("_tray") as Array).size() != before_tray:
			print("!! %d탄: 판을 못 채우게 되는 자리가 그냥 들어갔습니다" % st)
			bad += 1
		if (g.get("_grid") as PackedInt32Array) != before_grid:
			print("!! %d탄: 튕겼는데 판이 바뀌었습니다" % st)
			bad += 1
		if int(g.get("_misses")) == 0:
			print("!! %d탄: 안 받았는데 아무 반응(흔들림)도 없었습니다" % st)
			bad += 1
		g.queue_free()
		await get_tree().process_frame
	print("   나쁜 기둥을 %d판에서 실제로 두드려 봤습니다" % tried)
	if tried == 0:
		print("!! 나쁜 기둥을 한 번도 못 찾았습니다 — 검사가 헛돌고 있습니다")
		bad += 1
	return bad


## 조각 i 를 sh 모양으로 만들어 **col 기둥**을 두드린다 (자리는 게임이 정한다).
func _drop_into(g: Node, i: int, sh: Array, col: int) -> bool:
	var slot: Rect2 = g.call("_tray_slot", i)
	g.call("_on_tap", slot.position + slot.size * 0.5)
	if (g.get("_held") as Dictionary).is_empty():
		return false
	var want := NoodPieces.key(NoodPieces.normalize(sh))
	for r in 4:
		var t2: Array = g.get("_tray")
		if i >= t2.size():
			return false
		if NoodPieces.key(NoodPieces.normalize((t2[i] as Dictionary)["rot"])) == want:
			break
		g.call("_rotate_held")
	var br: Rect2 = g.call("_board_rect")
	var cell: float = g.call("_cell")
	g.call("_on_tap", br.position + Vector2((float(col) + 0.5) * cell, cell * 0.5))
	await get_tree().process_frame
	return true


# --------------------------------------------------------------------------- #
# "대강 맞으면 들어간다" (kanoodle.gd 의 _snap)
# --------------------------------------------------------------------------- #

## ★ 예전에는 누른 칸에 조각의 **기준칸**(왼쪽 위)이 그대로 왔다. 그래서 아이는
##   조각이 놓일 자리의 맨 왼쪽 칸을 정확히 눌러야 했고, 빈틈 한가운데를 누르면
##   조각이 오른쪽으로 밀려 나가 튕겼다 — "보이는 자리에 넣었는데 안 되는" 것이다.
##   지금은 누른 기둥을 **덮는** 자리 중에서 고른다.
##
## ★ 넷을 잰다. 앞의 셋은 "봐주다가 남의 판을 두지는 않는가", 넷째는 "봐주기가
##   실제로 일어나기는 하는가" 다 — 넷째가 0 이면 이 기능이 죽은 것이다.
##   1. 예전에 되던 자리는 **전부 그대로** 된다 (익힌 아이가 헷갈리면 안 된다)
##   2. 고른 자리는 반드시 **누른 기둥을 덮는다** (안 누른 데로 날아가면 안 된다)
##   3. ok 로 돌려준 자리는 정말 판을 끝까지 채울 수 있다 (NoodGen.fits)
##   4. 예전에는 튕겼는데 이제 들어가는 자리가 실제로 있다
func _snap_check() -> int:
	var bad := 0
	var rescued := 0
	var checked := 0
	for st in [3, 8, 14, 22, 30, 40]:
		_reset_skill(st)
		var g: Node = load("res://games/kanoodle/kanoodle.tscn").instantiate()
		add_child(g)
		g.set("dev_mode", true)
		g.set("stage", st)
		g.call("_build")
		var n := int(g.get("_n"))
		var grid: PackedInt32Array = g.get("_grid")
		var shapes: Array = g.call("_shapes")
		var bag: Dictionary = g.get("_bag")
		for i in shapes.size():
			for sh: Array in (shapes[i] as Array):
				for col in n:
					checked += 1
					var was := _land_col(g, sh, col)
					var was_ok := not was.is_empty() \
							and NoodGen.fits(grid, n, shapes, i, was["cells"], bag)
					var now: Dictionary = g.call("_snap", i, sh, col)
					if was_ok:
						# 1. 예전에 되던 자리는 그대로
						if now.is_empty() or not bool(now["ok"]) \
								or not _same(now["cells"], was["cells"]):
							bad += 1
							if bad <= 3:
								print("!! %d탄: 예전에 되던 자리가 바뀌었다 (조각 %d, 기둥 %d)"
										% [st, i, col])
						continue
					if now.is_empty():
						continue
					# 2. 반드시 누른 기둥을 덮는다
					var covers := false
					for cc in (now["cells"] as Array):
						if (cc as Vector2i).x == col:
							covers = true
							break
					if not covers:
						bad += 1
						if bad <= 3:
							print("!! %d탄: 고른 자리가 누른 기둥 %d 을 안 덮는다 (조각 %d)"
									% [st, col, i])
					if not bool(now["ok"]):
						continue
					# 3. ok 라면 정말 끝까지 채울 수 있어야 한다
					if not NoodGen.fits(grid, n, shapes, i, now["cells"], bag):
						bad += 1
						if bad <= 3:
							print("!! %d탄: 못 채우는 자리를 ok 로 내줬다 (조각 %d, 기둥 %d)"
									% [st, i, col])
						continue
					rescued += 1        # 4. 예전에는 튕겼는데 이제 들어간다
		g.queue_free()
		await get_tree().process_frame
	print("   대강맞추기: %d번 물어봐서 예전이면 튕겼을 %d번을 살렸습니다" % [checked, rescued])
	if rescued == 0:
		print("!! 살린 자리가 하나도 없습니다 — 대강맞추기가 아무 일도 안 하고 있습니다")
		bad += 1
	return bad
