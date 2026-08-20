## 「섬 한 바퀴」를 실제로 여러 판 돌려 보는 검사기.
##
## ★ 이 경로는 다른 어떤 검사도 안 본다 — 게임과 게임 **사이**가 검사 대상이기 때문이다.
##   여기서 잡히는 것: 뷰포트 전환이 매 판 일어나도 멈추지 않는가, 같은 게임이
##   세 번 연속 나오지 않는가, 개구리 구간이 버튼 없이 저절로 넘어가는가,
##   그리고 한쪽 게임이 "다음"을 안 불러서 여행이 그 자리에 서 버리지 않는가.
##
## 씬이 계속 갈리므로 이 노드는 루트에 붙어 산다 (current_scene 이 아니다).
extends Node

## 게임 id -> 그 게임 화면의 스크립트 경로.
## ★ 여기에 새 게임을 빠뜨리면 검사기가 그 화면을 "모르는 씬"으로 보고 조용히 넘어가
##   멈춤 감지에도 안 걸린다 — 검사가 영원히 안 끝난다. 실제로 물렸다.
##   그래서 _report() 가 GameRegistry 와 대조해 **빠진 게임이 있으면 실패**시킨다.
const SCRIPTS := {
	"dino": "res://games/dino/scripts/game.gd",
	"math": "res://games/math/game/battle.gd",
	"kanoodle": "res://games/kanoodle/kanoodle.gd",
	"torch": "res://games/torch/scripts/torch_game.gd",
	"cham": "res://games/cham/scripts/cham_game.gd",
	"rps": "res://games/rps/scripts/rps_game.gd",
}

var target_stages := 18
## 등록된 게임이 전부 한 번씩 나올 때까지는 더 돈다. 여기까지 가도 안 나오면 실패.
##
## ★ 왜 필요한가: 다음 게임은 가중치 랜덤이라, 게임이 늘수록 "18번째까지 한 번도
##   안 뽑힌 게임"이 확률적으로 생긴다 (게임 넷이면 초등 약 3%, 미취학 약 9%).
##   그러면 코드가 멀쩡한데도 검증이 가끔 빨간불이 되고, 그 빨간불이 진짜 회귀처럼
##   읽힌다 — 이 검사는 화면 전환 잠금 사고를 잡은 유일한 검사라 신뢰도가 곧 방어선이다.
##   전역 난수를 고정하는 방법은 못 쓴다: 게임들이 _ready 에서 randomize() 를 부른다.
var max_stages := 60
var _seen: Dictionary = {}
var _order: Array[String] = []
var _last_iid := 0
var _last_token := ""
var _stuck := 0.0
var _t0 := 0
## ★ 헤드리스에서 stdout 은 블록 버퍼링이라, 멈추면 여태 찍은 게 통째로 날아간다.
##   진행 상황은 파일에 바로 흘려 둔다 — 멈춰도 어디까지 갔는지는 남는다.
var _log: FileAccess


func _say(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log = FileAccess.open("user://journey_log.txt", FileAccess.WRITE)
	_t0 = Time.get_ticks_msec()
	_say("여행 검사 시작")
	Shell.save_disabled = true
	Engine.max_fps = 0
	# ★ 설정은 반드시 프로필 tuning 에 써야 한다.
	#   MathGame 의 변수에 직접 대입하면 pull_settings() 한 번에 되돌아간다 (거울이라서).
	var t := Shell.tuning()
	t["fast_animation"] = true          # 연출을 짧게 — 검사는 로직만 본다
	t["session_limit"] = 0              # 상한은 여기서 검사 대상이 아니다
	# ★ 여기서 보는 것은 게임과 게임 **사이**다. 시연 자체는 tests/battle_check 가 본다.
	#   시연을 켜 두면 한 판에 50초씩 걸려 이 검사가 10분짜리가 된다.
	t["skip_demo"] = true
	MathGame.pull_settings()
	Shell.journey_begin(1)


func _process(delta: float) -> void:
	var cur := get_tree().current_scene
	if cur == null:
		return
	var path := ""
	if cur.get_script() != null:
		path = String(cur.get_script().resource_path)

	# ★ 기록은 **씬이 바뀔 때** 한다. journey_stage 는 화면이 갈리기 전에 먼저 오르므로,
	#   그걸 기준으로 삼으면 "2번째 -> dino" 처럼 직전 게임이 찍힌다.
	var id := _id_of(path)
	if id == "":
		return
	# ★ "멈췄다"는 판정은 **게임 안의 진행**으로 재야 한다. 씬 전환만 보면
	#   정상적인 한 판(개구리 6문제 = 시연 포함 50초)을 멈춤으로 오인한다. 실제로 그랬다.
	var token := "%d:%s" % [cur.get_instance_id(), _progress_of(cur, path)]
	if token != _last_token:
		_last_token = token
		_stuck = 0.0
	else:
		_stuck += delta

	var iid := cur.get_instance_id()
	if iid != _last_iid:
		_last_iid = iid
		_order.append(id)
		_seen[id] = int(_seen.get(id, 0)) + 1
		_say("  %d번째 -> %s" % [Shell.journey_stage, id])

	if not Shell.journey_active:
		_report()
		return
	if Shell.journey_stage >= target_stages and _missing().is_empty():
		_report()
		return
	if Shell.journey_stage >= max_stages:
		_report()
		return
	if _stuck > 45.0 or Time.get_ticks_msec() - _t0 > 600000:
		_say("!! 여행이 %d번째에서 멈췄습니다 (%s)" % [Shell.journey_stage, path])
		if _id_of(path) == "math":
			var nb: Object = cur.get("_next_btn")
			_say("   busy=%s finished=%s index=%s/%s problem=%s next보임=%s pad잠김=%s"
					% [cur.get("_busy"), cur.get("_finished"), cur.get("_index"),
					   cur.get("_total"), cur.get("_problem") != null,
					   nb != null and bool(nb.get("visible")),
					   (cur.get("_pad") as Object).get("locked") if cur.get("_pad") != null else "?"])
			var pt := int(cur.get("_problem_tier"))
			var st: Object = cur.get("_stage")
			var pr: Object = cur.get("_problem")
			_say("   탄=%d m=%d d=%d / 문제 form=%s op=%s 항=%d / 무대 running=%s level=%s"
					% [pt, MathGame.tier_m(pt), MathGame.tier_d(pt),
					   pr.get("form") if pr != null else "?",
					   pr.get("op") if pr != null else "?",
					   (pr.get("terms") as Array).size() if pr != null else -1,
					   st.get("_running") if st != null else "?",
					   st.get("_demo_level") if st != null else "?"])
		elif _id_of(path) == "dino":
			_say("   state=%s busy=%s found=%s need=%s"
					% [cur.get("state"), cur.get("busy"), cur.get("found"),
					   cur.call("_need_count")])
		elif _id_of(path) == "kanoodle":
			_say("   판=%s 트레이=%s 손=%s done=%s busy=%s"
					% [cur.get("_n"), (cur.get("_tray") as Array).size(),
					   cur.get("_held"), cur.get("_done"), cur.get("_busy")])
		elif _id_of(path) == "cham":
			_say("   상태=%s 잡음=%s/%s 놓침=%s 버릇=%s 발자국=%s"
					% [cur.get("_state"), cur.get("caught"),
					   (cur.get("axes") as Dictionary).get("catches", "?"),
					   cur.get("misses"), str(cur.get("_pat")), str(cur.get("_hist"))])
		elif _id_of(path) == "rps":
			_say("   상태=%s 맞힘=%s/%s 틀림=%s 친구손=%s 목표=%s 카드=%s"
					% [cur.get("_state"), cur.get("hit"),
					   (cur.get("axes") as Dictionary).get("rounds", "?"),
					   cur.get("misses"), cur.call("friend_hand"), cur.call("goal_now"),
					   str(cur.call("cards_now"))])
		elif _id_of(path) == "torch":
			var bm: Object = cur.get("beam")
			_say("   state=%s busy=%s found=%s/%s 빛=%s r=%s 어둠=%s"
					% [cur.get("state"), cur.get("busy"), cur.get("found"),
					   (cur.get("dinos") as Array).size(),
					   bm.get("on") if bm != null else "?",
					   bm.get("radius") if bm != null else "?",
					   bm.get("dark") if bm != null else "?"])
		_say("   Router._busy=%s / Shell.journey_active=%s journey_stage=%d current_game=%s"
				% [Router.get("_busy"), Shell.journey_active, Shell.journey_stage, Shell.current_game])
		_say("   Router.journey_stage=%d / 최근=%s" % [Router.journey_stage, str(Shell.get("_journey_recent"))])
		_report()
		return

	match id:
		"dino": _drive_dino(cur)
		"math": _drive_battle(cur)
		"kanoodle": _drive_nood(cur)
		"torch": _drive_torch(cur)
		"cham": _drive_cham(cur)
		"rps": _drive_rps(cur)


## 등록됐는데 아직 한 번도 안 나온 게임
func _missing() -> PackedStringArray:
	var out := PackedStringArray()
	for g in GameRegistry.LIST:
		var gid := String(g["id"])
		if SCRIPTS.has(gid) and int(_seen.get(gid, 0)) <= 0:
			out.append(gid)
	return out


## 이 게임이 "앞으로 나아갔는가"를 한 문자열로. 안 바뀌면 멈춘 것이다.
func _id_of(path: String) -> String:
	for id in SCRIPTS:
		if String(SCRIPTS[id]) == path:
			return String(id)
	return ""


func _progress_of(cur: Node, path: String) -> String:
	match _id_of(path):
		"math":
			return "%s/%s/%s" % [cur.get("_index"), cur.get("_attempts"), cur.get("_finished")]
		"dino":
			return "%s/%s/%s" % [cur.get("found"), cur.get("stage"), cur.get("state")]
		"kanoodle":
			return "%s/%s/%s" % [(cur.get("_tray") as Array).size(), cur.get("stage"), cur.get("_done")]
		"torch":
			return "%s/%s/%s" % [cur.get("found"), cur.get("stage"), cur.get("state")]
		"cham":
			return "%s/%s/%s" % [cur.get("caught"), cur.get("stage"), cur.get("_state")]
		"rps":
			return "%s/%s/%s" % [cur.get("hit"), cur.get("stage"), cur.get("_state")]
	return ""


## 블록 채우기 자동 플레이 — **지금 떨어뜨릴 수 있는** 조각을 골라 계획한 기둥에 떨어뜨린다.
##
## ★ 자리는 정해져 있지 않다 (모양만 맞으면 어디든 들어간다). 그래서 "정답 자리"가
##   아니라 게임이 지금 세워 둔 계획(_plan)을 따라간다. 계획은 판이 바뀔 때마다
##   다시 서므로, 검사기는 그때그때 물어보기만 하면 된다.
##
## ★ 조각이 떨어져서 쌓이므로 "아무 조각이나 아무 때나"가 아니다. 위에 얹힐 조각을
##   먼저 떨어뜨리면 판을 못 채우게 되어 튕겨 나오는데, 그러면 판이 안 줄어들어서
##   검사기가 "멈췄다"로 읽는다. 그래서 순서를 여기서 지켜 준다.
func _drive_nood(g: Node) -> void:
	if bool(g.get("_busy")):
		return
	if not (g.get("_falling") as Dictionary).is_empty():
		return                          # 떨어지는 중 — 끝날 때까지 기다린다
	if bool(g.get("_done")):
		g.call("_on_tap", Vector2(640, 400))
		return
	var tray: Array = g.get("_tray")
	if tray.is_empty():
		return

	# 게임이 가리키는 **다음 수**를 그대로 따라간다 (힌트가 쓰는 것과 같은 값이다).
	# 없으면 손을 놓는다 — 진행이 멈추므로 검사기의 "막힘" 감시에 걸린다
	# (조용히 넘어가면 안 된다). 검사기가 정답 순서를 미리 알고 있으면 안 되므로
	# 그때그때 게임에게 묻는다.
	var plan: Array = g.get("_plan")
	var pick := int(g.get("_plan_next"))
	if pick < 0 or pick >= tray.size() or (plan[pick] as Array).is_empty():
		return

	var slot: Rect2 = g.call("_tray_slot", pick)
	g.call("_on_tap", slot.position + slot.size * 0.5)
	var want: Array = plan[pick]
	var want_key := NoodPieces.key(NoodPieces.normalize(g.call("_shape_of", want)))
	for r in 4:
		var t2: Array = g.get("_tray")
		if t2.size() <= pick:
			return
		if NoodPieces.key(NoodPieces.normalize((t2[pick] as Dictionary)["rot"])) == want_key:
			break
		g.call("_rotate_held")
	# 누를 **기둥** = 조각의 기준칸이 놓일 기둥 (왼쪽 위에서 처음 채워진 칸).
	# 세로로 어디를 누르든 중력이 자리를 정하지만, 정답 칸을 눌러 두면 사람이 읽기 쉽다.
	var at: Vector2i = want[0]
	for c in want:
		var v: Vector2i = c
		if v.y < at.y or (v.y == at.y and v.x < at.x):
			at = v
	var br: Rect2 = g.call("_board_rect")
	var cell: float = g.call("_cell")
	g.call("_on_tap", br.position + Vector2((float(at.x) + 0.5) * cell, (float(at.y) + 0.5) * cell))


func _drive_dino(g: Node) -> void:
	g.set("_slow", 0.08)
	if String(g.get("state")) != "play" or bool(g.get("busy")):
		return
	var targets: Array = g.get("target_ids")
	var dinos: Array = g.get("dinos")
	for d in dinos:
		if bool(d.get("found")):
			continue
		if not targets.is_empty() and not targets.has(int(d.get("species"))):
			continue
		g.call("_tap", (d.get("base_pos") as Vector2) + Vector2(0, -70))
		return


## 손전등 찾기 자동 플레이 — 아이가 하는 그대로 같은 자리를 두 번 두드린다.
##
## ★ 첫 탭은 빛만 옮기고 두 번째 탭이 찾는다. 검사기가 이 순서를 그대로 밟아야
##   "어두운 데를 찍어도 찾아지는" 회귀가 여기서도 걸린다 (한 번에 찾아지면
##   방이 절반의 탭으로 끝나므로 tests/torch_check.gd 가 그것까지 못 박는다).
func _drive_torch(g: Node) -> void:
	g.set("_slow", 0.08)
	if bool(g.get("busy")):
		return
	if String(g.get("state")) == "intro":
		g.call("skip_intro")     # 해질녘 연출은 여기서 볼 것이 아니다
		return
	if String(g.get("state")) != "play":
		return
	for d in (g.get("dinos") as Array):
		if bool(d.get("found")):
			continue
		g.call("_tap", (d.call("hit_rect") as Rect2).get_center())
		return


## 가위바위보 자동 플레이 — 친구 손과 목표를 보고 규칙대로 카드를 고른다.
## (여기는 흐름 검사라 규칙 자체는 tests/rps_check.gd 가 따로 본다.)
func _drive_rps(g: Node) -> void:
	g.set("_slow", 0.05)
	if String(g.get("_state")) != "wait":
		return
	var want := RpsGen.answer(int(g.call("friend_hand")), int(g.call("goal_now")))
	var i := int(g.call("card_index", want))
	if i < 0:
		return                      # 정답 카드가 없다 = 생성이 어긋났다 (멈춤으로 잡힌다)
	var r: Rect2 = g.call("card_rect", i)
	g.call("_on_tap", r.position + r.size * 0.5)


## 참참참 자동 플레이 — 친구의 버릇을 읽어(next_dir) 맞는 손을 누른다.
## (버릇을 못 읽는 아이까지 흉내 내는 것은 tests/cham_check.gd 가 한다.)
func _drive_cham(g: Node) -> void:
	g.set("_slow", 0.05)
	if String(g.get("_state")) != "wait":
		return
	var z: Rect2 = g.call("hand_zone", int(g.call("next_dir")))
	g.call("_on_tap", z.position + z.size * 0.5)


func _drive_battle(b: Node) -> void:
	if bool(b.get("_busy")) or bool(b.get("_finished")):
		return
	# 문제를 맞히면 "다음" 버튼이 뜬다 — 실제 아이가 누르는 그 버튼을 눌러 준다.
	# (skip_demo 로 건너뛰지 않는다. 여행에서도 이 흐름이 진짜 흐름이다.)
	var nb: Object = b.get("_next_btn")
	if nb != null and bool(nb.get("visible")):
		b.call("_on_next_pressed")
		return
	var p: Object = b.get("_problem")
	if p == null:
		return
	b.call("_on_answered", int(p.get("answer")))


func _report() -> void:
	set_process(false)
	var secs := float(Time.get_ticks_msec() - _t0) / 1000.0
	# 같은 게임이 세 번 연속 나왔는가 (섞는 의미가 사라지는 지점)
	var run := 1
	var worst := 1
	for i in range(1, _order.size()):
		run = run + 1 if _order[i] == _order[i - 1] else 1
		worst = maxi(worst, run)
	var missing := _missing()
	var unknown := PackedStringArray()
	for g in GameRegistry.LIST:
		if not SCRIPTS.has(String(g["id"])):
			unknown.append(String(g["id"]))
	if not unknown.is_empty():
		_say("!! 검사기가 모르는 게임: %s — tests/journey_runner.gd 의 SCRIPTS 에 넣어라"
				% ", ".join(unknown))

	var ok := Shell.journey_stage >= target_stages and worst <= 2 \
			and missing.is_empty() and unknown.is_empty()
	_say("%s 섬 한 바퀴: %d번째까지 %.1f초, 나온 순서 %s"
			% ["  " if ok else "!!", Shell.journey_stage, secs, " ".join(_order)])
	_say("   게임별 횟수 %s / 같은 게임 최대 연속 %d회 / 안 나온 게임 %s"
			% [str(_seen), worst, "없음" if missing.is_empty() else ", ".join(missing)])
	_say("   판정: %s" % ("정상" if ok else "이상"))
	if _log != null:
		_log.close()
	get_tree().quit(0 if ok else 1)
