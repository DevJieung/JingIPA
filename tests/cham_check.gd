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
		# ★ 이 탄의 tell 로 **세 방향이 전부** 읽히는가. 하나만 먼저 사라지면 그 방향은
		#   찍기가 되는데, 버릇에 그 방향이 들어간 판에서만 나타나서 검사가 "가끔"
		#   빨간불이 된다 — 실제로 그랬다 (하늘 웅크림이 e=40 에서 2.4%).
		var tell_read := _tell_readable(tell, dirs)
		var ax_ok := worst <= ChamGen.TAPS_MAX and plen >= 2 and plen <= ChamGen.LEN_MAX \
				and need > plen and dirs >= 2 and dirs <= 3 and tell >= 0.0 and tell <= 1.0 \
				and (plen < 3 or variety >= VARIETY_MIN) and tell_read
		if not ax_ok:
			bad_axes += 1
			print("!! E=%d 축이 한계를 넘었다: 버릇 %d, 잡기 %d(버릇보다 길어야 한다), 방향 %d, 가짓수 %d, 최악 %d탭, tell읽힘 %s"
					% [e, plen, need, dirs, variety, worst, str(tell_read)])
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
	# 세션 상한에 닿았을 때 정말 나가는가 (dev_mode 가 막고 있어 아무도 안 밟던 길)
	var limit_bad := await _limit_check()

	# 고개 돌리기가 **거짓말을 안 하는가** (방향 표 · 답 미리 알려 주지 않기)
	var face_bad := await _face_check()

	var ok := bad_axes == 0 and bad_pat == 0 and play_bad == 0 and fb_bad == 0 \
			and limit_bad == 0 and face_bad == 0
	print("%s 버릇 %d개: 축한계이탈 %d건, 못읽을버릇 %d건, 예비버릇이상 %d건, 플레이실패 %d건, 상한탈출이상 %d건, 고개돌리기이상 %d건"
			% ["  " if ok else "!!", made, bad_axes, bad_pat, fb_bad, play_bad, limit_bad,
				face_bad])
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


## 이 tell 세기로 방향 하나하나가 다 읽히는가 (그리기가 내놓는 값만 본다)
func _tell_readable(tell: float, dirs: int) -> bool:
	var cg := load("res://games/cham/scripts/cham_game.gd")
	for d in [ChamGen.LEFT, ChamGen.RIGHT] + ([ChamGen.UP] if dirs >= 3 else []):
		var tp: Dictionary = cg.tell_pose(int(d), tell)
		var ok := absf(float(tp["dx"])) > ChamGen.TELL_DX_MIN \
				or float(tp["squash"]) < ChamGen.TELL_SQUASH_MAX
		if not ok:
			return false
	return true


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
		if float(tp["dx"]) < -ChamGen.TELL_DX_MIN:
			return ChamGen.LEFT
		if float(tp["dx"]) > ChamGen.TELL_DX_MIN:
			return ChamGen.RIGHT
		if float(tp["squash"]) < ChamGen.TELL_SQUASH_MAX:
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


## 세션 상한에 닿았을 때 **정말 집으로 나가는가.**
##
## ★ 이 길은 아무도 안 밟는다: 검사기들이 dev_mode 를 켜고 놀기 때문에 상한 판정 자체가
##   건너뛰어진다. 그런데 여기가 막히면 화면이 축하 장면에서 **얼어붙고 「집으로」조차
##   안 눌린다** — 아이는 앱을 껐다 켜는 수밖에 없다. 판이 끝나면 _state 가 "gone" 이
##   되는데, _go_home() 이 바로 그 "gone" 을 보고 그냥 돌아가기 때문이다.
##
## ★ **여기서부터는 await 를 하지 마라.** Router.goto_hub() 는 첫 await 에서 멈춰 있고,
##   프레임을 한 번이라도 넘기면 그 코루틴이 이어져 **검사 씬을 진짜로 갈아 치운다**
##   (그러면 검사가 결과를 못 찍고 사라진다). 그래서 이 검사는 맨 마지막에 온다.
func _limit_check() -> int:
	var bad := 0
	var g := _make(1)
	await get_tree().process_frame
	Router.set("_busy", false)           # 잠겨 있으면 goto_hub 가 조용히 무시된다
	Shell.journey_active = false         # 여행 중이면 상한 길로 안 온다
	Shell.session_notified = true        # 알림 신호는 이 검사의 대상이 아니다
	Shell.session_units = 999999
	g.set("dev_mode", false)             # ★ dev_mode 가 상한 판정을 통째로 막는다
	g.call("_next_stage")
	if not bool(Router.get("_busy")):
		bad += 1
		print("!! 상한에 닿았는데 집으로 안 갔다 — 축하 장면에서 얼어붙는다")
	g.queue_free()
	return bad


# --------------------------------------------------------------------------- #
# 고개 돌리기 — 이 게임에서 그림을 뒤집는 유일한 곳
# --------------------------------------------------------------------------- #

## 친구가 **뛴 쪽으로 몸을 돌리는** 것이 거짓말이 아닌지 본다.
##
## ★ 규칙 26 은 "그림을 뒤집어 방향을 말하지 마라"이고, 예외를 허락하는 조건이
##   딱 하나 적혀 있다 — **50종의 방향 표를 먼저 만들어라.** 그 표가 낡으면
##   (그림을 다시 뽑았는데 표는 그대로면) 아이는 반대 방향을 보게 되고,
##   **화면 없는 이 머신에서는 아무도 못 본다.** 그래서 여기서 잰다.
##
## 넷을 본다:
##   1. 50종 전부가 FACE 표에 있는가 (모르는 종은 안 돌리지만, 빠진 것도 알아야 한다)
##   2. 그림의 지문이 표와 같은가 (다르면 눈으로 다시 보라는 뜻이다)
##   3. **뛰기 전(wait)에는 절대 안 돌린다** — 돌리면 그건 tell 이 아니라 답이다
##   4. 뛴 뒤에는 정말 그쪽을 본다 (표가 말하는 원래 방향까지 셈에 넣어서)
func _face_check() -> int:
	var bad := 0
	var ids: Array = []
	for i in DinoSpecies.count():
		ids.append(String(DinoSpecies.data(i)["id"]))
	# 1 · 2 — 표가 50종을 다 덮는가, 그리고 그림이 그때 그 그림인가
	var miss := 0
	var stale := 0
	for i in DinoSpecies.count():
		var id := String(DinoSpecies.data(i)["id"])
		if not DinoSpecies.FACE.has(id):
			miss += 1
			if miss <= 3:
				print("!! 방향 표에 %s 가 없다 — tools/dino/face_table.py --sheet 로 보고 적어라" % id)
			continue
		var want := String(DinoSpecies.ART_SHA.get(id, ""))
		var now := FileAccess.get_sha256(DinoSpecies.DIR + id + ".png").substr(0, 12)
		if want.is_empty() or now.is_empty():
			continue
		if want != now:
			stale += 1
			if stale <= 3:
				print("!! %s 그림이 바뀌었다 (%s -> %s) — 방향을 눈으로 다시 보고 FACE 를 고친 뒤"
						% [id, want, now])
				print("   python3 tools/dino/face_table.py --sha 로 지문을 갱신해라")
	bad += miss + stale

	# 3 · 4 — 실제로 게임을 돌려서 본다
	for st in [1, 9, 20]:
		Shell.profile()["cham"] = {
			"best_stage": st, "caught": 0, "skill": 0, "ease_streak": 0, "cushion": 0,
		}
		var g: Node = load("res://games/cham/cham.tscn").instantiate()
		g.set("dev_mode", true)
		g.set("_slow", 0.02)
		add_child(g)
		await get_tree().process_frame
		g.set("_state", "wait")
		# 3. 기다리는 동안은 늘 제 방향 그대로여야 한다 (답을 미리 주면 안 된다)
		if absf(float(g.call("friend_face")) - 1.0) > 0.001:
			bad += 1
			print("!! %d탄: 뛰기 전에 고개가 돌아 있다 — 답을 미리 알려 주는 것이다" % st)
		# 4. 뛴 뒤에는 뛴 쪽을 본다
		var sp := int(g.get("_sp"))
		var art := DinoSpecies.face_of(sp)
		for d in [ChamGen.LEFT, ChamGen.RIGHT]:
			g.set("_dir", d)
			g.set("_pick", d)
			g.set("_state", "jump")
			var got := float(g.call("friend_face"))
			var want2 := 1.0
			if art != 0:
				want2 = float((-1 if d == ChamGen.LEFT else 1) * art)
			if absf(got - want2) > 0.001:
				bad += 1
				print("!! %d탄: %s 로 뛰었는데 보는 쪽이 %.0f (기대 %.0f, 그림 방향 %d)"
						% [st, "왼쪽" if d == ChamGen.LEFT else "오른쪽", got, want2, art])
		g.queue_free()
		await get_tree().process_frame
	print("   방향 표: %d종 (빠짐 %d · 그림 바뀜 %d)" % [DinoSpecies.FACE.size(), miss, stale])
	return bad
