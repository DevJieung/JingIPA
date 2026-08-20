## 가위바위보 — 규칙이 맞는지, 그리고 **어떤 아이도 막히지 않는지** 본다.
##
## ★ 이 게임이 조용히 망가지는 방식은 둘이다:
##   (1) 화면에 그린 손·목표와 판정이 어긋난다 — 아이는 맞게 냈는데 틀렸다고 나온다.
##       눈으로는 안 보인다 (그림은 멀쩡하니까).
##   (2) 축이 헐거워져서 **아무렇게나 찍어도 "잘한다"로 읽힌다** — 그러면 적응형이
##       운을 숙련으로 오독하고(규칙 9) 판이 아이보다 먼저 어려워진다.
##
##   그래서 여기서는 **두 아이를 흉내 내서 직접 플레이해 본다**:
##     (가) 규칙을 아는 아이 -> 딱 라운드 수만큼만 눌러서 끝나야 한다 (틀림 0)
##     (나) 규칙을 하나도 모르는 아이 -> 카드를 하나씩 눌러 보더라도 **반드시** 끝나야 한다
##   그리고 축마다 "찍는 아이가 통과할 확률"을 숫자로 재서 상한을 강제한다.
##
## ★ (가)가 게임의 정답 함수(RpsGen.answer)를 부르면 **무엇을 그리든 통과하는 항등식**이
##   된다 — 참참참이 같은 함정에 한 번 빠졌다. 그래서 (가)는 화면에 그려지는 것
##   (friend_hand · goal_now · cards_now)만 읽고, 이기고 지는 표는 **이 파일이 따로 들고 있다.**
##
##   ~/.local/bin/godot --headless --path . res://tests/rps_check.tscn
##   ~/.local/bin/godot --headless --path . res://tests/rps_check.tscn -- --pre
extends Node

const STAGES := [1, 3, 6, 8, 10, 12, 16, 20, 22, 30, 50, 100, 200]
const ROUNDS := 200          ## 유효탄마다 만들어 볼 판 수
## 축이 하나씩 새로 켜지는 지점들 (e=6 카드3 · 8 비겨라 · 12 라운드6 · 16 져라 · 22 라운드7)
const PLAY_STAGES := [1, 4, 7, 9, 13, 17, 23, 40]

## 찍는 아이가 "읽었다"로 읽힐 확률의 상한 (두 판 연속이어야 한 칸 어려워지므로 제곱으로 본다).
## 규칙 9 가 못 박은 문턱(4지선다 2연속 = 1/16 = 6.25%)보다 촘촘해야 한다.
const GUESS_MAX := 0.04

## 손 이름 (검사기가 직접 들고 있는 표 — 게임 코드를 안 본다)
const NAMES := ["가위", "바위", "보"]

## "모르는 아이"가 통틀어 몇 번 틀렸는가. 0 이면 그 아이 흉내가 헛돈 것이다.
var _free_miss := 0


func _ready() -> void:
	Shell.save_disabled = true
	Engine.max_fps = 0
	Shell.sfx_enabled = false
	if "--pre" in OS.get_cmdline_user_args():
		Shell.profile()["age_band"] = "pre"
		Shell.profile()["tuning"] = Shell.default_tuning("pre")
	var t := Shell.tuning()
	print("   프로필: %s" % String(Shell.profile()["age_band"]))

	# 0. 규칙표가 진짜 가위바위보인가 (검사기가 제 표로 확인한다)
	var rule_bad := _rule_check()

	print("   %5s %7s %6s %6s %7s %9s %8s %8s"
			% ["E", "라운드", "카드", "목표", "고리", "찍기통과", "최악탭", "판이상"])
	var bad_axes := 0
	var bad_make := 0
	var made := 0
	var rng := RandomNumberGenerator.new()
	for ei in STAGES:
		var e := int(ei)
		var ax := RpsGen.axes(e, t)
		var rounds := int(ax["rounds"])
		var cards := int(ax["cards"])
		var goals := int(ax["goals"])
		var help := float(ax["help"])
		# 규칙을 모르는 아이의 최악: 라운드마다 카드를 하나씩 눌러 본다
		var worst := rounds * cards
		# ★ 찍는 아이가 "한 판에 한 번만 틀림"으로 보일 확률. 두 판 연속이 한 칸 어려워지는
		#   조건이므로 제곱으로 본다.
		var guess: float = RpsGen.guess_pass(cards, rounds)
		var ax_ok := rounds >= RpsGen.ROUNDS_MIN and rounds <= RpsGen.ROUNDS_MAX \
				and cards >= 2 and cards <= 3 and goals >= 1 and goals <= 3 \
				and help >= 0.0 and help <= 1.0 \
				and worst <= RpsGen.TAPS_MAX and guess * guess <= GUESS_MAX
		if not ax_ok:
			bad_axes += 1
			print("!! E=%d 축이 한계를 넘었다: 라운드 %d, 카드 %d, 목표 %d, 최악 %d탭, 찍기 %.3f"
					% [e, rounds, cards, goals, worst, guess * guess])
		var fail := 0
		for r in ROUNDS:
			rng.seed = hash("r_%d_%d" % [e, r])
			var rs := RpsGen.make_rounds(cards, goals, rounds, rng)
			made += 1
			var why := _check_rounds(rs, cards, goals, rounds)
			if not why.is_empty():
				fail += 1
				bad_make += 1
				if bad_make <= 3:
					print("!! E=%d 판이 이상하다: %s" % [e, why])
		print("   %5d %7d %6d %6d %7.2f %9.4f %8d %8d"
				% [e, rounds, cards, goals, help, guess * guess, worst, fail])

	var play_bad := await _play_stages()
	var help_bad := await _help_check()
	var limit_bad := await _limit_check()
	var art_bad := _art_check()

	var ok := rule_bad == 0 and bad_axes == 0 and bad_make == 0 and play_bad == 0 \
			and help_bad == 0 and limit_bad == 0 and art_bad == 0 and _free_miss > 0
	print("%s 판 %d개: 규칙표이상 %d건, 축한계이탈 %d건, 판생성이상 %d건, 플레이실패 %d건, 안내이상 %d건, 상한탈출이상 %d건, 손그림이상 %d건"
			% ["  " if ok else "!!", made, rule_bad, bad_axes, bad_make, play_bad, help_bad,
				limit_bad, art_bad])
	print("   모르는 아이가 통틀어 %d번 틀렸다 (0 이면 그 아이 흉내가 헛돈 것이다)" % _free_miss)
	print("   판정: %s" % ("정상" if ok else "이상 — 위 !! 줄을 보세요"))
	get_tree().quit(0 if ok else 1)


# --------------------------------------------------------------------------- #
# 검사기가 **직접 들고 있는** 가위바위보 표
#
# ★ 여기서 RpsGen 을 부르면 안 된다. 게임도 같은 함수로 판정하므로 "무엇이든 통과하는"
#   항등식이 되고, 규칙을 뒤집어도 초록불이 된다 (참참참이 같은 함정에 빠진 적이 있다).
# --------------------------------------------------------------------------- #

## mine 이 other 를 상대로: 1 = 이김, 0 = 비김, -1 = 짐
func _win(mine: int, other: int) -> int:
	if mine == other:
		return 0
	# 가위(0)는 보(2)를, 바위(1)는 가위(0)를, 보(2)는 바위(1)를 이긴다
	var table := {0: 2, 1: 0, 2: 1}
	return 1 if int(table[mine]) == other else -1


## 이 목표를 이루려면 내야 하는 손 (표를 훑어서 **직접** 찾는다)
func _answer(friend: int, goal: int) -> int:
	var want := 1 if goal == 0 else (-1 if goal == 2 else 0)
	for h in 3:
		if _win(h, friend) == want:
			return h
	return -1


## 게임의 규칙 함수들이 이 표와 같은 말을 하는가 + 정답이 언제나 딱 하나인가
func _rule_check() -> int:
	var bad := 0
	for f in 3:
		for m in 3:
			if RpsGen.outcome(m, f) != _win(m, f):
				bad += 1
				print("!! %s vs %s: 게임은 %d, 표는 %d"
						% [NAMES[m], NAMES[f], RpsGen.outcome(m, f), _win(m, f)])
	for g in 3:
		# ★ **목표 팻말이 그리는 별의 방향**을 표에 못 박는다. 이 값은 판정에 안 쓰이고
		#   그림에만 쓰여서, 아래 개수 세기(n==1)만으로는 세 값을 아무렇게나 뒤바꿔도
		#   통과한다 — 이겨라 팻말이 지는 그림을 보여도 검사가 초록불이 된다.
		var want := 1 if g == RpsGen.WIN else (-1 if g == RpsGen.LOSE else 0)
		if RpsGen.goal_outcome(g) != want:
			bad += 1
			print("!! 목표 %d 의 별 방향이 %d 다 (표는 %d)" % [g, RpsGen.goal_outcome(g), want])
		var seen := {}
		for f in 3:
			var a := _answer(f, g)
			# 목표마다 정답이 **정확히 하나** 있어야 한다 (막다른 판이 없다는 근거)
			var n := 0
			for h in 3:
				if _win(h, f) == RpsGen.goal_outcome(g):
					n += 1
			if n != 1 or a < 0:
				bad += 1
				print("!! 목표 %d, 친구 %s: 정답이 %d개다" % [g, NAMES[f], n])
			if RpsGen.answer(f, g) != a:
				bad += 1
				print("!! 목표 %d, 친구 %s: 게임은 %s, 표는 %s"
						% [g, NAMES[f], NAMES[RpsGen.answer(f, g)], NAMES[a]])
			seen[a] = true
		# 목표 하나에서 친구 손 셋이 서로 다른 정답으로 가야 한다 (한 손만 계속 내면 안 된다)
		if seen.size() != 3:
			bad += 1
			print("!! 목표 %d: 정답이 %d가지뿐이다 (3가지여야 한다)" % [g, seen.size()])
	return bad


## 만들어진 한 판이 조건을 지키는가. 이상하면 이유를, 멀쩡하면 "" 를 돌려준다.
func _check_rounds(rs: Array, cards: int, goals: int, rounds: int) -> String:
	if rs.size() != rounds:
		return "라운드가 %d개다 (%d개여야 한다)" % [rs.size(), rounds]
	for i in rs.size():
		var r: Dictionary = rs[i]
		var f := int(r["friend"])
		var g := int(r["goal"])
		var a := int(r["answer"])
		var cs: Array = r["cards"]
		if f < 0 or f > 2 or g < 0 or g >= goals:
			return "%d번째: 손 %d 목표 %d 가 범위 밖" % [i, f, g]
		if a != _answer(f, g):
			return "%d번째: 정답이 %s 인데 %s 로 적혀 있다" % [i, NAMES[_answer(f, g)], NAMES[a]]
		if i == 0 and g != RpsGen.WIN:
			return "첫 라운드가 '이겨라'가 아니다"      # 새 목표로 판을 시작하면 안 된다
		if cs.size() != cards:
			return "%d번째: 카드가 %d장이다 (%d장이어야 한다)" % [i, cs.size(), cards]
		if not (a in cs):
			return "%d번째: 정답 카드가 화면에 없다"    # 이게 깨지면 아이가 갇힌다
		var sorted := (cs as Array).duplicate()
		sorted.sort()
		if sorted != cs:
			return "%d번째: 카드 순서가 가위·바위·보가 아니다" % i
		if i >= 2:
			if a == int((rs[i - 1] as Dictionary)["answer"]) \
					and a == int((rs[i - 2] as Dictionary)["answer"]):
				return "%d번째: 같은 정답이 세 번 연속" % i
			if f == int((rs[i - 1] as Dictionary)["friend"]) \
					and f == int((rs[i - 2] as Dictionary)["friend"]):
				return "%d번째: 친구가 같은 손을 세 번 연속" % i
	return ""


# --------------------------------------------------------------------------- #
# 진짜 씬으로 끝까지 놀아 보기
# --------------------------------------------------------------------------- #

func _play_stages() -> int:
	var bad := 0
	print("   %5s %7s %6s %10s %12s %8s"
			% ["판", "라운드", "카드", "아는아이", "모르는아이", "결과"])
	for si in PLAY_STAGES:
		var st := int(si)
		var g1 := _make(st)
		await get_tree().process_frame
		var ax: Dictionary = g1.get("axes")
		var rounds := int(ax.get("rounds", 5))
		var cards := int(ax.get("cards", 3))
		# (가) 규칙을 아는 아이 — 화면만 보고 고른다. 딱 rounds 번이어야 한다.
		var taps_a := _run(g1, true)
		var miss_a := int(g1.get("misses"))
		_drop(g1)
		await get_tree().process_frame

		# (나) 규칙을 모르는 아이 — 왼쪽부터 하나씩 눌러 본다. 그래도 끝나야 한다.
		var g2 := _make(st)
		await get_tree().process_frame
		var taps_b := _run(g2, false)
		# ★ 탭 수 상한만 보면 안 된다. **판을 끝냈는지**를 안 보면, 틀린 순간 판이
		#   끝나 버리는 게임(규칙 2 위반)이 "적은 탭 수"로 오히려 더 잘 통과한다.
		#   실제로 _judge 를 그렇게 바꿔 보니 검사가 통째로 초록불이었다.
		var done_b := int(g2.get("hit")) == rounds and String(g2.get("_state")) == "clear"
		_free_miss += int(g2.get("misses"))
		_drop(g2)
		await get_tree().process_frame

		var row_ok: bool = taps_a == rounds and miss_a == 0 and done_b \
				and taps_b > 0 and taps_b <= rounds * cards and taps_b <= RpsGen.TAPS_MAX
		if not row_ok:
			bad += 1
			print("!! %d판: 아는아이 %d탭(기대 %d, 틀림 %d), 모르는아이 %d탭(상한 %d, 판끝냄 %s)"
					% [st, taps_a, rounds, miss_a, taps_b, rounds * cards, str(done_b)])
		print("   %5d %7d %6d %10d %12d %8s"
				% [st, rounds, cards, taps_a, taps_b, "정상" if row_ok else "이상"])
	return bad


## 설명이 정말 **다시 친절해지는가** (규칙 11).
## 두 번 틀리면 관계 고리가 또렷해지고, 세 번이면 정답 카드가 숨을 쉬어야 한다.
func _help_check() -> int:
	var bad := 0
	var g := _make(40)              # 관계 고리가 가장 옅어져 있는 탄
	await get_tree().process_frame
	# ★ 반드시 먼저 연출을 끝내 놓는다. 판이 시작되는 "enter" 동안에는 탭이 안 먹는데,
	#   그걸 모르고 바로 누르면 **검사기 혼자 헛돌면서** 게임을 탓하게 된다 (한 번 그랬다).
	_settle(g)
	# ★ 높은 탄이면 고리는 **그 프로필의 하한까지** 내려와 있어야 한다.
	#   0.5 같은 숫자를 박아 두면 미취학 하한(0.55)과 부딪힌다 — 미취학은 일부러
	#   고리를 끝까지 안 지운다. 그래서 손잡이와 맞대어 본다.
	var floor_help := float(Shell.tune("rps_help_min", 0.0))
	if absf(float(g.call("help_now")) - floor_help) > 0.02:
		bad += 1
		print("!! 높은 탄인데 관계 고리가 하한(%.2f)까지 안 내려왔다 (%.2f) — B축이 죽었다"
				% [floor_help, float(g.call("help_now"))])
	var wrong := _wrong_card(g)
	if wrong < 0:
		print("!! 틀릴 카드가 없다 — 검사가 헛돌고 있다")
		return 1
	var f0 := int(g.call("friend_hand"))
	var g0 := int(g.call("goal_now"))
	for k in 3:
		_settle(g)
		# ★ 틀려도 **같은 라운드가 이어져야** 한다. 오답이 라운드를 넘겨 버리면 판이
		#   줄어들고, 그건 곧 "틀리면 손해"라 벌이 된다 (규칙 2).
		if int(g.call("friend_hand")) != f0 or int(g.call("goal_now")) != g0 \
				or int(g.get("hit")) != 0:
			bad += 1
			print("!! %d번 틀린 뒤 라운드가 넘어갔다" % k)
		var i := int(g.call("card_index", wrong))
		var r: Rect2 = g.call("card_rect", i)
		g.call("_on_tap", r.position + r.size * 0.5)
		_settle(g)
		var ms := int(g.get("_miss_streak"))
		if ms != k + 1:
			bad += 1
			print("!! %d번째로 틀렸는데 연속 틀림이 %d 이다" % [k + 1, ms])
		if k >= 1 and float(g.call("help_now")) < 0.99:
			bad += 1
			print("!! 두 번 틀렸는데 관계 고리가 다시 안 진해졌다 (%.2f)" % float(g.call("help_now")))
		if k >= 2 and int(g.call("hint_hand")) != _answer(int(g.call("friend_hand")),
				int(g.call("goal_now"))):
			bad += 1
			print("!! 세 번 틀렸는데 정답 카드를 안 가리킨다")
	# 맞히면 안내가 도로 옅어져야 한다 (계속 켜 두면 축이 죽는다)
	_settle(g)
	var ans := _answer(int(g.call("friend_hand")), int(g.call("goal_now")))
	var ri: Rect2 = g.call("card_rect", int(g.call("card_index", ans)))
	g.call("_on_tap", ri.position + ri.size * 0.5)
	_settle(g)
	if int(g.call("hint_hand")) >= 0:
		bad += 1
		print("!! 맞혔는데 정답 카드가 계속 켜져 있다")
	_drop(g)
	await get_tree().process_frame
	return bad


## 지금 라운드에서 **틀리는** 카드 하나 (없으면 -1)
func _wrong_card(g: Node) -> int:
	var ans := _answer(int(g.call("friend_hand")), int(g.call("goal_now")))
	for h in (g.call("cards_now") as Array):
		if int(h) != ans:
			return int(h)
	return -1


func _make(st: int) -> Node:
	Shell.profile()["rps"] = {
		"best_stage": st, "hits": 0, "skill": 0, "ease_streak": 0, "cushion": 0,
	}
	var g: Node = load("res://games/rps/rps.tscn").instantiate()
	g.set("dev_mode", true)
	g.set("_slow", 0.02)
	add_child(g)
	return g


func _drop(g: Node) -> void:
	(g.get("sfx") as Object).call("stop_all")
	g.queue_free()


## 한 판을 끝까지. 반환: 누른 횟수 (막히면 -1)
##
## know 가 참이면 **화면에 그려지는 것만** 보고 규칙대로 고른다.
## 아니면 카드를 왼쪽부터 하나씩 눌러 본다 (규칙을 모르는 아이).
func _run(g: Node, know: bool) -> int:
	var taps := 0
	var probe := 0
	for guard in 200:
		_settle(g)
		var st := String(g.get("_state"))
		if st == "clear":
			return taps
		if st == "gone":
			return -1               # 판이 끝난 게 아니라 화면이 갈리는 중이다
		if st != "wait":
			continue
		var cs: Array = g.call("cards_now")
		var want := -1
		if know:
			# ★ 게임의 정답 함수를 부르지 않는다. 친구 손과 목표만 읽고 제 표로 푼다.
			want = _answer(int(g.call("friend_hand")), int(g.call("goal_now")))
			probe = 0
		else:
			want = int(cs[probe % cs.size()])
			probe += 1
		var i := int(g.call("card_index", want))
		if i < 0:
			return -1               # 정답 카드가 화면에 없다 = 아이가 갇혔다
		var r: Rect2 = g.call("card_rect", i)
		g.call("_on_tap", r.position + r.size * 0.5)
		taps += 1
	return -1


## 연출을 끝까지 돌려서 다시 누를 수 있는 상태로 만든다.
func _settle(g: Node) -> void:
	for i in 60:
		var st := String(g.get("_state"))
		if st == "wait" or st == "clear" or st == "gone":
			return
		g.call("_process", 0.5)


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
	Shell.profile()["rps"] = {
		"best_stage": 1, "hits": 0, "skill": 0, "ease_streak": 0, "cushion": 0,
	}
	var g: Node = load("res://games/rps/rps.tscn").instantiate()
	g.set("_slow", 0.02)
	add_child(g)
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
# 손 그림 한 벌
# --------------------------------------------------------------------------- #

## 손 셋이 **한 벌인가**, 그리고 core/look.gd 가 말하는 자리에 손목이 있는가.
##
## ★ 손 셋은 따로 있는 그림이 아니라 한 벌이다 — tools/theme/gen_theme.py 의 fit_hand 가
##   손목 밴드를 자로 삼아 세 장을 같은 틀에 앉힌다. 한 장만 다시 뽑아 끼우면 손목
##   굵기와 높이가 어긋나서 카드 세 장이 서로 다른 사람 손처럼 보이는데,
##   **화면이 없는 이 머신에서는 눈으로 절대 안 잡힌다.** 그래서 여기서 잰다.
## ★ 그림이 아예 없으면 통과다. 없으면 도형 손으로 도는 것이 정상이기 때문이다
##   (Look.draw_hand 의 되돌아갈 자리). 다만 **셋 중 일부만** 있으면 실패다 —
##   카드 한 장만 그림이면 그게 제일 이상해 보인다.
func _art_check() -> int:
	var kinds := [Look.HAND_SCISSORS, Look.HAND_ROCK, Look.HAND_PAPER]
	var names := ["가위", "바위", "보"]
	var have := 0
	for k in kinds:
		if Look.hand_tex(int(k)) != null:
			have += 1
	if have == 0:
		print("   손 그림 없음 — 도형 손으로 돈다 (그것도 정상이다)")
		return 0
	if have < kinds.size():
		print("!! 손 그림이 %d/3 장뿐이다 — 카드 일부만 그림이면 제일 이상해 보인다" % have)
		return 1
	var bad := 0
	var size0 := Vector2i.ZERO
	for i in kinds.size():
		var img: Image = Look.hand_tex(int(kinds[i])).get_image()
		var sz := Vector2i(img.get_width(), img.get_height())
		if i == 0:
			size0 = sz
		elif sz != size0:
			bad += 1
			print("!! %s 손 크기가 %s — 다른 손은 %s 다. 한 벌이 아니다" % [names[i], sz, size0])
		var box := _cuff_box(img)
		if box.size.x <= 0:
			bad += 1
			print("!! %s 손에서 손목 밴드(파랑)를 못 찾았다 — fit_hand 를 안 탄 그림이다" % names[i])
			continue
		var cw := float(box.size.x) / float(sz.x)
		var cv := (float(box.position.y) + float(box.size.y) * 0.5) / float(sz.y)
		var cx := (float(box.position.x) + float(box.size.x) * 0.5) / float(sz.x)
		var why := ""
		if absf(cw - Look.HAND_CUFF_W) > 0.03:
			why += " 폭 %.3f(≠%.2f)" % [cw, Look.HAND_CUFF_W]
		if absf(cv - Look.HAND_CUFF_V) > 0.03:
			why += " 높이 %.3f(≠%.2f)" % [cv, Look.HAND_CUFF_V]
		if absf(cx - 0.5) > 0.03:
			why += " 가로한가운데 %.3f(≠0.50)" % cx
		if why.is_empty():
			print("   %s 손: %dx%d, 밴드 폭 %.3f · 높이 %.3f · 가운데 %.3f" % [names[i], sz.x, sz.y, cw, cv, cx])
		else:
			bad += 1
			print("!! %s 손의 손목 밴드가 look.gd 의 자와 어긋난다:%s" % [names[i], why])
	return bad


## 손목 밴드(데님 파랑)의 네모. **tools/theme/gen_theme.py 의 cuff_box 와 같은 잣대**다
## (파랑이 빨강보다 18/255 이상 진하고, 파랑이 70/255 이상, 불투명한 곳).
## 두 칸씩 건너뛰며 본다 — 밴드는 그림의 5분의 1을 덮는 큰 덩어리라 이걸로 충분하다.
func _cuff_box(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	var n := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			if c.a > 0.392 and c.b > c.r + 0.070 and c.b > 0.275:
				n += 1
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
			x += 2
		y += 2
	if n < 200:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0, y1 - y0)
