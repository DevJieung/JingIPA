## 세션 상한(「많이 놀았다」) 검사 — 진짜 앱 흐름 그대로.
##
## ★ 이 길은 여태 **어떤 검사도 안 지나갔다.** tests/journey_runner.gd 는
##   `session_limit = 0` 으로 상한을 꺼 버리고, 게임별 검사기는 전부 `dev_mode = true`
##   라 상한 분기(`Shell.round_done`)를 통째로 건너뛴다. 그 사이에 이런 상태였다:
##
##     session_units 를 0 으로 되돌리는 곳이 앱 부팅 하나뿐이라, 상한에 한 번 닿은 뒤에는
##     **방을 깰 때마다** 예외 없이 허브로 튕겼다. 다시 들어가서 한 방, 또 허브, 또 한 방.
##     아이 눈에는 "다 찾았는데 다음 방이 안 나온다"로만 보이고, 안드로이드는 홈 버튼으로
##     나가도 프로세스가 살아 있어서 그 상태가 며칠씩 이어졌다. 부모가 이 증상으로 신고했다.
##
## 그래서 여기서 보는 것은 딱 둘이다:
##   1. 상한에 닿으면 허브로 나간다 (쉼표가 있다)
##   2. **그 다음 구간이 다시 온전하다** — 나갔다 들어와서 한 방 만에 또 튕기지 않는다
##
##   ~/.local/bin/godot --headless --path . res://tests/session_check.tscn
##   ~/.local/bin/godot --headless --path . res://tests/session_check.tscn -- --pre
extends Node

## 검사할 게임. 셸이 아니라 등록표가 놀이 단위를 알고 있으므로 여기서도 등록표를 본다.
const GAMES := ["torch", "dino"]

var _band := "elem"
var _game := ""
var _gi := 0
var _rooms := 0                 ## 이번 게임에서 깬 방 수 (통째로)
var _since_break := 0           ## 마지막 쉼표 이후 깬 방 수
var _breaks: Array[int] = []    ## 쉼표마다 "그 구간에서 몇 방 만에 나갔는가"
var _bad := 0
var _t0 := 0
var _seen_units_after_break := -1
var _log: FileAccess


func _say(s: String) -> void:
	print(s)
	if _log != null:
		_log.store_line(s)
		_log.flush()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log = FileAccess.open("user://session_check.txt", FileAccess.WRITE)
	_t0 = Time.get_ticks_msec()
	Shell.save_disabled = true
	Shell.sfx_enabled = false
	Engine.max_fps = 0
	if "--pre" in OS.get_cmdline_user_args():
		_band = "pre"
	Shell.profile()["age_band"] = _band
	Shell.profile()["tuning"] = Shell.default_tuning(_band)
	_say("   프로필: %s · 상한 %d단위" % [_band, _limit()])
	_say("   %8s %6s %8s %28s %s"
			% ["게임", "한방", "예상쉼표", "실제 (구간마다 몇 방)", "결과"])
	_start_game()


func _limit() -> int:
	return int(Shell.tune("session_limit", Shell.DEFAULT_SESSION_LIMIT))


## 이 게임은 몇 방 만에 상한에 닿는가.
func _expect() -> int:
	var u := int(GameRegistry.get_game(_game).get("journey_units", Shell.DINO_ROOM_UNITS))
	return int(ceil(float(_limit()) / float(maxi(1, u))))


func _start_game() -> void:
	_game = GAMES[_gi]
	_rooms = 0
	_since_break = 0
	_breaks.clear()
	_seen_units_after_break = -1
	# 앱을 막 켠 상태로 맞춘다 (shell/boot.gd 가 하는 일).
	Shell.begin_session()
	Shell.profile()["torch"] = {"best_stage": 1, "lifetime_found": 0,
			"skill": 0, "ease_streak": 0, "cushion": 0}
	Shell.profile()["dino"]["best_stage"] = 1
	Router.goto_game(_game)


func _process(_d: float) -> void:
	if Time.get_ticks_msec() - _t0 > 300000:
		_say("!! 시간 초과 — %s 에서 멈췄다" % _game)
		_bad += 1
		_finish()
		return
	var cur := get_tree().current_scene
	if cur == null or cur.get_script() == null:
		return
	var path := String(cur.get_script().resource_path)

	if path.ends_with("hub.gd"):
		if bool(Router.get("_busy")):
			return
		# 쉼표. 여기서 세션이 새로 열렸는지가 이 검사의 전부다.
		_breaks.append(_since_break)
		if _seen_units_after_break < 0:
			_seen_units_after_break = Shell.session_units
		_since_break = 0
		# 두 구간만 보면 "쉼표인가 자물쇠인가"가 갈린다.
		if _breaks.size() >= 2:
			_grade()
			return
		Router.goto_game(_game)
		return

	if not (path.ends_with("torch_game.gd") or path.ends_with("game.gd")):
		return
	# 연출은 검사 대상이 아니다 — 짧게 줄인다 (dev_mode 는 켜지 않는다.
	# 켜는 순간 상한 분기가 통째로 건너뛰어져서 이 검사가 아무것도 안 보게 된다).
	if float(cur.get("_slow")) > 0.5:
		cur.set("_slow", 0.05)
	if String(cur.get("state")) == "intro":
		cur.call("skip_intro")
		return
	if String(cur.get("state")) != "play" or bool(cur.get("busy")):
		return

	var beam: Object = cur.get("beam")
	var targets: Array = cur.get("target_ids") if cur.get("target_ids") != null else []
	for d in (cur.get("dinos") as Array):
		if bool(d.get("found")):
			continue
		if not targets.is_empty() and not targets.has(int(d.get("species"))):
			continue
		var c: Vector2 = (d.call("hit_rect") as Rect2).get_center()
		if beam != null:
			beam.call("aim", c)
		cur.call("_tap", c)
	_rooms += 1
	_since_break += 1
	if _rooms > _expect() * 3 + 4:
		_say("!! %s: 상한에 닿아도 허브로 안 나간다 (%d방)" % [_game, _rooms])
		_bad += 1
		_grade()


func _grade() -> void:
	var want := _expect()
	var ok := _breaks.size() >= 2 and _breaks[0] == want and _breaks[1] == want \
			and _seen_units_after_break == 0
	if not ok:
		_bad += 1
		if _breaks.size() >= 2 and _breaks[1] < want:
			_say("!! %s: 쉼표 뒤에 놀이가 %d방 만에 또 끊긴다 (%d방이어야 한다) — "
					% [_game, _breaks[1], want]
					+ "세션이 안 열렸다. Shell.take_session_break() 를 보라.")
		if _seen_units_after_break > 0:
			_say("!! %s: 허브로 나온 뒤에도 session_units 가 %d 다 (0 이어야 한다)"
					% [_game, _seen_units_after_break])
	_say("   %8s %6d %8d %28s %s"
			% [_game,
			   int(GameRegistry.get_game(_game).get("journey_units", 3)),
			   want, str(_breaks), "정상" if ok else "이상"])
	_gi += 1
	if _gi < GAMES.size():
		_start_game()
		return
	_finish()


func _finish() -> void:
	_say("   판정: %s" % ("정상" if _bad == 0 else "이상 — 위 !! 줄을 보세요"))
	get_tree().quit(0 if _bad == 0 else 1)
