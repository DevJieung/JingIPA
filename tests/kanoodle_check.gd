## 블록 채우기 — 퍼즐 생성기가 **항상 풀 수 있는 판**을 내는지 무더기로 검사한다.
##
## ★ 생성이 역방향(먼저 덮고 일부를 뺀다)이라 해답을 이미 들고 있다.
##   그래도 "정말 덮였는가"를 격자로 다시 세어 확인한다 — 생성기가 조용히 실패하면
##   아이 화면에 빈 판이 뜬다.
##
## ★ 덮였다고 풀리는 게 아니다. 조각이 **떨어져서 쌓이므로**, 해답이 멀쩡해도
##   위에 뭔가 얹힌 조각을 문제로 내면 아이는 그 조각을 제자리에 못 보낸다.
##   그래서 실제로 한 조각씩 떨어뜨려 보는 검사(NoodGen.drop_check)를 같이 돌린다.
##   이게 없으면 "덮기는 정상인데 아이가 못 푸는 판"이 조용히 나간다.
##
##   ~/.local/bin/godot --headless --path . res://tests/kanoodle_check.tscn
##   ~/.local/bin/godot --headless --path . res://tests/kanoodle_check.tscn -- --pre
extends Node

const ROUNDS := 40      # 유효탄마다 몇 판씩
const STAGES := [1, 3, 5, 8, 10, 14, 18, 22, 30, 50, 100]
## 진짜 씬을 띄워 끝까지 플레이해 볼 탄 (격자·조각수·안내·회전이 다 바뀌는 지점들)
const PLAY_STAGES := [1, 5, 10, 16, 24, 40]


func _ready() -> void:
	Shell.save_disabled = true
	Engine.max_fps = 0
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

	# 생성기가 아니라 **게임 코드**로 실제로 떨어뜨려 끝까지 풀어 본다.
	var play_bad := await _play_stages()

	var ok := fail == 0 and bad_cover == 0 and bad_drop == 0 and rot_bad == 0 \
			and play_bad == 0
	print("%s 판 %d개: 생성실패 %d건, 덮기이상 %d건, 낙하불가 %d건, 회전표이상 %d건, 플레이실패 %d건"
			% ["  " if ok else "!!", total, fail, bad_cover, bad_drop, rot_bad, play_bad])
	print("   판정: %s" % ("정상" if ok else "이상"))
	get_tree().quit(0 if ok else 1)


## ★ 생성기가 멀쩡해도 게임의 조작·판정이 어긋나면 아이는 못 푼다. 그래서 진짜 씬을
##   띄워서 "차례인 조각을 골라 제 기둥에 떨어뜨린다"만 반복해 끝까지 가 본다.
##   여기서 misses 가 나오면 **차례인 조각이 제자리에 안 앉았다**는 뜻이고,
##   그건 낙하 규칙과 차례 규칙이 서로 어긋났다는 신호다.
func _play_stages() -> int:
	var bad := 0
	print("   %6s %8s %8s %10s" % ["탄", "떨어뜨림", "빗나감", "결과"])
	for st in PLAY_STAGES:
		var g: Node = load("res://games/kanoodle/kanoodle.tscn").instantiate()
		add_child(g)
		# 크기는 안 건드린다 — 배치 함수가 전부 W/H 상수를 쓰고, _on_tap 은 이미
		# 그 좌표계를 받는다. 여기서 size 를 넣으면 앵커 경고만 나온다.
		g.set("dev_mode", true)
		g.set("stage", st)
		g.call("_build")
		var drops := await _play_one(g)
		var done := bool(g.get("_done"))
		var misses := int(g.get("_misses"))
		if not done or misses != 0:
			bad += 1
		print("   %6d %8d %8d %10s"
				% [st, drops, misses, "정상" if (done and misses == 0) else "이상"])
		g.queue_free()
		await get_tree().process_frame
	return bad


## 한 판을 끝까지. 반환: 떨어뜨린 횟수 (막히면 -1)
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
		# 차례인 조각을 트레이 앞에서부터 찾는다 (게임이 순서를 강제하는지 보는 것이므로
		# 검사기가 정답 순서를 미리 알고 있으면 안 된다)
		var pick := -1
		for i in tray.size():
			if bool(g.call("_ready_now", i)):
				pick = i
				break
		if pick < 0:
			return -1                       # 차례인 조각이 없다 = 아이가 갇혔다
		var slot: Rect2 = g.call("_tray_slot", pick)
		g.call("_on_tap", slot.position + slot.size * 0.5)
		var want: Array = (tray[pick] as Dictionary)["cells"]
		var want_key := NoodPieces.key(NoodPieces.normalize(g.call("_shape_of", want)))
		for r in 4:
			if NoodPieces.key(NoodPieces.normalize((tray[pick] as Dictionary)["rot"])) == want_key:
				break
			g.call("_rotate_held")
		var at: Vector2i = want[0]
		for c in want:
			var v: Vector2i = c
			if v.y < at.y or (v.y == at.y and v.x < at.x):
				at = v
		var br: Rect2 = g.call("_board_rect")
		var cell: float = g.call("_cell")
		g.call("_on_tap", br.position
				+ Vector2((float(at.x) + 0.5) * cell, (float(at.y) + 0.5) * cell))
		drops += 1
		await get_tree().process_frame
	return -1


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
