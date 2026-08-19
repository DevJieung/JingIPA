## 참참참 — 친구의 버릇이 **읽을 수 있는 것**인지, 그리고 어떤 아이도 막히지 않는지 본다.
##
## ★ 이 게임이 조용히 망가지는 방식은 하나뿐이다: 친구가 뛰는 방향이 사실상 무작위가 되는 것.
##   그러면 화면은 똑같은데 놀이가 동전 던지기로 바뀌고, 아이는 아무리 잘 봐도 못 이긴다.
##   눈으로는 절대 안 보인다. 그래서 여기서 **두 아이를 흉내 내서 직접 플레이해 본다**:
##     (가) 몸이 기우는 것(tell)을 읽는 아이   -> 딱 필요한 횟수만에 끝나야 한다
##     (나) tell 은 아예 안 보고 **발자국만** 읽는 아이 -> 그래도 반드시 끝나야 한다
##   (나)가 끝난다는 것이 "막다른 길이 없다"의 증명이다.
##
##   ~/.local/bin/godot --headless --path . res://tests/cham_check.tscn
##   ~/.local/bin/godot --headless --path . res://tests/cham_check.tscn -- --pre
extends Node

const STAGES := [1, 3, 6, 9, 12, 15, 18, 21, 24, 30, 40, 60, 100, 200]
const ROUNDS := 200          ## 유효탄마다 만들어 볼 버릇 수
## 축이 하나씩 새로 켜지는 지점들 (e=8 버릇3 · 12 읽기2 · 16 방향3 · 20 버릇4 · 24 읽기3)
const PLAY_STAGES := [1, 2, 9, 13, 17, 21, 25, 40]

## 버릇 길이가 3 이상인데 고를 수 있는 버릇이 이보다 적으면, 아이는 버릇을 읽는 대신
## 규칙 하나를 외워 버린다 (왼·오 둘뿐인 길이 4 는 회전을 빼면 「둘씩 번갈아」 하나뿐이다).
const VARIETY_MIN := 6



func _ready() -> void:
	Shell.save_disabled = true
	Engine.max_fps = 0
	# 소리는 검사 대상이 아니고, 재생 중인 소리가 남으면 종료할 때 누수 경고가 뜬다.
	Shell.sfx_enabled = false
	if "--pre" in OS.get_cmdline_user_args():
		Shell.profile()["age_band"] = "pre"
		Shell.profile()["tuning"] = Shell.default_tuning("pre")
	var t := Shell.tuning()
	print("   프로필: %s" % String(Shell.profile()["age_band"]))
	print("   %5s %6s %6s %6s %6s %6s %7s %8s %8s"
			% ["E", "버릇", "읽기", "잡기", "tell", "방향", "가짓수", "최악탭", "버릇실패"])

	var bad_axes := 0
	var bad_pat := 0
	var made := 0
	var rng := RandomNumberGenerator.new()
	for ei in STAGES:
		var e := int(ei)
		var ax := ChamGen.axes(e, t)
		var plen := int(ax["pattern_len"])
		var need := int(ax["catches"])
		var dirs := int(ax["dirs"])
		var tell := float(ax["tell"])
		# 발자국만 읽는 아이의 최악: 한 바퀴는 찍고, 그 뒤로는 전부 맞힌다
		var worst := plen + need
		var variety := _variety(plen, dirs)
		# ★ 잡을 횟수가 버릇 길이보다 **반드시 길어야** 한다. 아니면 판이 무료 tell 창
		#   안에서 끝나서, 발자국도 버릇도 tell 이 옅어지는 축도 전부 장식이 된다.
		var ax_ok := worst <= ChamGen.TAPS_MAX and plen >= 2 and plen <= ChamGen.LEN_MAX \
				and need > plen and dirs >= 2 and dirs <= 3 and tell >= 0.0 and tell <= 1.0 \
				and (plen < 3 or variety >= VARIETY_MIN)
		if not ax_ok:
			bad_axes += 1
			print("!! E=%d 축이 한계를 넘었다: 버릇 %d, 잡기 %d(버릇보다 길어야 한다), 방향 %d, 가짓수 %d, 최악 %d탭"
					% [e, plen, need, dirs, variety, worst])
		var fail := 0
		for r in ROUNDS:
			rng.seed = hash("c_%d_%d" % [e, r])
			var p := ChamGen.pattern(plen, dirs, rng)
			made += 1
			if p.size() != plen or not ChamGen.readable(p):
				fail += 1
				bad_pat += 1
				if bad_pat <= 3:
					print("!! E=%d 읽을 수 없는 버릇: %s" % [e, str(p)])
		print("   %5d %6d %6d %6d %6.2f %6d %7d %8d %8d"
				% [e, plen, int(ax["read_turns"]), need, tell, dirs, variety, worst, fail])

	# 예비 버릇(무작위 60번이 다 실패했을 때 쓰는 것)도 스스로 조건을 지키는가
	var fb_bad := 0
	for n in range(2, ChamGen.LEN_MAX + 1):
		if not ChamGen.readable(ChamGen.fallback(n)):
			fb_bad += 1
			print("!! 예비 버릇이 읽을 수 없다 (길이 %d): %s" % [n, str(ChamGen.fallback(n))])

	var play_bad := await _play_stages()

	var ok := bad_axes == 0 and bad_pat == 0 and play_bad == 0 and fb_bad == 0
	print("%s 버릇 %d개: 축한계이탈 %d건, 못읽을버릇 %d건, 예비버릇이상 %d건, 플레이실패 %d건"
			% ["  " if ok else "!!", made, bad_axes, bad_pat, fb_bad, play_bad])
	print("   판정: %s" % ("정상" if ok else "이상 — 위 !! 줄을 보세요"))
	get_tree().quit(0 if ok else 1)


## 진짜 씬을 띄워서 두 아이로 각각 끝까지 놀아 본다.
func _play_stages() -> int:
	var bad := 0
	print("   %5s %6s %6s %8s %10s %8s %8s"
			% ["판", "버릇", "잡기", "읽는아이", "발자국아이", "tell", "결과"])
	for si in PLAY_STAGES:
		var st := int(si)
		var g1 := _make(st)
		await get_tree().process_frame
		var ax: Dictionary = g1.get("axes")
		var plen := (g1.get("_pat") as Array).size()
		var need := int(ax.get("catches", 3))
		# (가) tell 을 읽는 아이 — 딱 need 번에 끝나야 한다
		var taps_a := _run(g1, true)
		_drop(g1)
		await get_tree().process_frame

		# (나) 발자국만 읽는 아이 — 한 바퀴는 찍더라도 반드시 끝나야 한다
		var g2 := _make(st)
		await get_tree().process_frame
		var tell_bad := [0]
		var taps_b := _run(g2, false, tell_bad)
		_drop(g2)
		await get_tree().process_frame

		var row_ok: bool = taps_a == need and taps_b > 0 and taps_b <= plen + need + 2 \
				and int(tell_bad[0]) == 0
		if not row_ok:
			bad += 1
			print("!! %d판: 읽는아이 %d탭(기대 %d), 발자국아이 %d탭(상한 %d), tell이상 %d건"
					% [st, taps_a, need, taps_b, plen + need + 2, int(tell_bad[0])])
		print("   %5d %6d %6d %8d %10d %8s %8s"
				% [st, plen, need, taps_a, taps_b,
				   "정상" if int(tell_bad[0]) == 0 else "이상",
				   "정상" if row_ok else "이상"])
	return bad


func _make(st: int) -> Node:
	# 탄과 연출 배속을 _ready 가 돌기 전에 정해 둔다.
	Shell.profile()["cham"] = {
		"best_stage": st, "caught": 0, "skill": 0, "ease_streak": 0, "cushion": 0,
	}
	var g: Node = load("res://games/cham/cham.tscn").instantiate()
	g.set("dev_mode", true)
	g.set("_slow", 0.02)
	add_child(g)
	return g


func _drop(g: Node) -> void:
	(g.get("sfx") as Object).call("stop_all")
	g.queue_free()


## 한 판을 끝까지. 반환: 누른 횟수 (막히면 -1)
func _run(g: Node, use_tell: bool, tell_bad: Array = []) -> int:
	var taps := 0
	for guard in 300:
		_settle(g)
		var stt := String(g.get("_state"))
		if stt == "clear":
			return taps
		if stt != "wait":
			continue
		# 첫 한 바퀴 동안에는 tell 이 반드시 최대여야 한다 (이게 "읽을 수 있다"의 근거다)
		if not tell_bad.is_empty() and int(g.get("_turn")) < (g.get("_pat") as Array).size():
			if float(g.call("tell_now")) < 0.99:
				tell_bad[0] = int(tell_bad[0]) + 1
		var z: Rect2 = g.call("hand_zone", _pick_dir(g, use_tell))
		g.call("_on_tap", z.position + z.size * 0.5)
		taps += 1
	return -1


## 연출을 끝까지 돌려서 다시 누를 수 있는 상태로 만든다.
func _settle(g: Node) -> void:
	for i in 40:
		var stt := String(g.get("_state"))
		if stt == "wait" or stt == "clear":
			return
		g.call("_process", 0.5)


## 이 (길이, 방향수)에서 읽을 수 있는 버릇이 몇 가지인가 (전수)
func _variety(plen: int, dirs: int) -> int:
	var n := 0
	var total := int(pow(dirs, plen))
	for code in total:
		var p: Array[int] = []
		var x := code
		for i in plen:
			var d := x % dirs
			x /= dirs
			# 0 = 왼쪽, 1 = 오른쪽, 2 = 하늘 (ChamGen 의 상수와 맞춘다)
			p.append([ChamGen.LEFT, ChamGen.RIGHT, ChamGen.UP][d])
		if ChamGen.readable(p):
			n += 1
	return n


## 아이 흉내.
##   use_tell 이면 **화면에 실제로 그려지는 기울기**를 보고 고른다.
##   ★ 여기서 게임의 정답 함수(next_dir)를 부르면 안 된다 — 게임도 같은 함수로 방향을
##     정하므로 "무엇을 그리든 통과하는" 항등식이 되고, 기울기를 반대로 그려도 검사가
##     초록불이 된다. 실제로 그랬고 적대적 리뷰가 잡았다.
##   아니면 **발자국만** 보고 주기를 찾아 다음을 예측한다. 못 찾겠으면 그냥 왼쪽.
func _pick_dir(g: Node, use_tell: bool) -> int:
	if use_tell:
		var tp: Dictionary = g.call("tell_pose_now")
		if float(tp["dx"]) < -6.0:
			return ChamGen.LEFT
		if float(tp["dx"]) > 6.0:
			return ChamGen.RIGHT
		if float(tp["squash"]) < 0.97:
			return ChamGen.UP
	var h: Array = g.get("_hist")
	var n := h.size()
	for k in range(1, n):
		var ok := true
		for i in range(k, n):
			if int(h[i]) != int(h[i - k]):
				ok = false
				break
		if ok:
			return int(h[n - k])
	return ChamGen.LEFT
