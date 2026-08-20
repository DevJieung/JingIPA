## 화면 전환 담당. 오토로드 이름: Router
##
## 씬 사이에 값을 넘길 때 전역 변수를 쓰지 않도록 여기 한 곳에 모은다.
## 전환은 항상 짧은 페이드로 감싼다 — 화면이 갑자기 바뀌면 어린 아이는
## 무슨 일이 일어났는지 놓친다.
##
## ★ 뷰포트 전환(Shell.enter_game/enter_shell)은 페이드가 화면을 완전히 덮은
##   순간에만 부른다. 그래야 기준 해상도가 1280x800 <-> 1280x720 으로 바뀌는 것이
##   아이 눈에 안 보인다.
##
## 갚아야 할 빚: pending_tier / goto_battle / goto_endless 는 개구리 용사 전용이다.
## 게임 #3 이 올 때 games/math/math_route.gd 로 내리고 여기에는
## goto_hub / goto_game / goto_scene 만 남긴다.
extends CanvasLayer

const HUB := "res://shell/hub.tscn"
const TITLE := "res://games/math/ui/title.tscn"
const TIERS := "res://games/math/ui/tiers.tscn"
const BATTLE := "res://games/math/game/battle.tscn"
const PARENT := "res://games/math/ui/parent.tscn"

const FADE_TIME := 0.22

## 쉬러 갈 때 두리가 하는 말. 놀이 밖의 화폐도, 평가도, 재촉도 아니다 —
## 방금 있었던 **사건**만 말한다.
const REST_LINE := "많이 놀았다!"

## 전투 화면이 읽어 가는 값.
var pending_tier := 0
var pending_endless := false
## 「섬 한 바퀴」로 들어왔는가 (0 이면 아니다). 게임은 이 값만 보고 여행인지 안다.
var journey_stage := 0
## 여행 개구리 구간의 문항 수 (0 이면 그 탄의 정규 문항 수)
var pending_journey_count := 0
## 여행 개구리 구간에서 별을 기록할 것인가
var pending_journey_record := false
## 전투가 끝나고 지도로 돌아올 때, 방금 깬 탄을 알려 준다 (연출용).
var last_result := {}

var _fade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.06, 0.10, 0.08, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	add_child(_fade)


# --------------------------------------------------------------------------- #
# 셸
# --------------------------------------------------------------------------- #

func goto_hub() -> void:
	_change(HUB, "")


## 놀이 단위 상한에 닿아 쉬러 간다. 허브로 가는 길에 두리가 한 번 인사한다.
##
## ★ 예전에는 아무 말 없이 화면만 바뀌었다. 아이는 방을 다 찾아 축하 배너를 보고
##   기뻐한 직후에 갑자기 게임 목록에 서 있게 되는데, 이 나이대는 그것을
##   "내가 뭘 잘못 눌러서 놀이가 끊겼다"로 읽는다. 무슨 일이 일어났는지는
##   글을 못 읽는 아이에게도 **그림으로** 와야 한다.
##
## ★ 문구는 사람이 아니라 사건을 말한다 (규칙 7). "잘했어요"도 "그만해"도 아니다.
func goto_rest() -> void:
	_change(HUB, "", REST_LINE, true)


## 등록된 게임으로 들어간다. 셸은 게임 이름을 모른다 — 등록표만 본다.
func goto_game(id: String) -> void:
	var g := GameRegistry.get_game(id)
	if g.is_empty():
		push_error("등록되지 않은 게임: %s" % id)
		return
	journey_stage = 0
	_change(String(g["scene"]), id)


## 「섬 한 바퀴」의 다음 장소. 화면이 덮인 동안 어디로 가는지 한 번 보여 준다 —
## 아이가 "다음에 뭐가 나오지?"를 기대하게 만드는 것이 이 모드의 전부다.
func goto_journey(id: String, stage: int) -> void:
	var g := GameRegistry.get_game(id)
	if g.is_empty():
		push_error("등록되지 않은 게임: %s" % id)
		return
	journey_stage = stage
	pending_endless = false
	if id == "math":
		_pick_journey_tier()
	_change(String(g.get("journey_scene", g["scene"])), id,
			"%d번째 · %s" % [stage, String(g.get("journey_caption", g["title"]))])


## 여행에서 개구리 구간이 나왔을 때 어느 탄을 할지.
##
## 대부분은 **이미 깬 탄**을 짧게 다시 지나간다 (여행이니까 아는 곳도 지나간다).
## 가끔 아직 안 깬 다음 탄이 나오고, 그때는 정규 문항 수로 별까지 기록한다 —
## 그래야 여행만 해도 지도가 앞으로 나아간다.
func _pick_journey_tier() -> void:
	var cleared: Array[int] = []
	for i in Curriculum.tier_count():
		if MathGame.is_cleared(i):
			cleared.append(i)
	if cleared.is_empty() or randf() < 0.3:
		pending_tier = MathGame.next_tier()
		pending_journey_count = 0        # 0 = 그 탄의 정규 문항 수
		pending_journey_record = true
	else:
		pending_tier = cleared[randi() % cleared.size()]
		pending_journey_count = 4        # 짧게 지나간다
		pending_journey_record = false


# --------------------------------------------------------------------------- #
# 개구리 용사 안쪽 (같은 게임 안의 화면 이동이라 뷰포트를 안 건드린다)
# --------------------------------------------------------------------------- #

func goto_title() -> void:
	_change(TITLE, "math")


func goto_tiers() -> void:
	_change(TIERS, "math")


func goto_parent() -> void:
	_change(PARENT, "math")


func goto_battle(tier: int) -> void:
	pending_tier = clampi(tier, 0, Curriculum.tier_count() - 1)
	pending_endless = false
	_change(BATTLE, "math")


func goto_endless() -> void:
	pending_tier = maxi(0, MathGame.highest_cleared())
	pending_endless = true
	_change(BATTLE, "math")


# --------------------------------------------------------------------------- #

func _change(path: String, game_id: String, caption: String = "", duri := false) -> void:
	if OS.has_environment("ROGAME_DEBUG"):
		print("[router] _change(%s, %s) busy=%s" % [path.get_file(), game_id, _busy])
	if _busy:
		return
	_busy = true
	await _fade_to(1.0)
	if caption != "":
		await _show_caption(caption, duri)
	# ★ 화면이 완전히 덮인 지금 뷰포트를 갈아 끼운다.
	if game_id.is_empty():
		if Shell.current_game != "":
			Shell.enter_shell()
	elif Shell.current_game != game_id:
		Shell.enter_game(game_id)
	var err := get_tree().change_scene_to_file(path)
	if OS.has_environment("ROGAME_DEBUG"):
		print("[router] change_scene -> %s err=%d" % [path.get_file(), err])
	if err != OK:
		push_error("씬을 열 수 없습니다: %s (%s)" % [path, error_string(err)])
	# 새 씬이 준비될 때까지 한 프레임 기다린다.
	await get_tree().process_frame
	# ★ 여기서 이미 새 화면이 떠 있다. 남은 것은 연출(밝아지기)뿐이므로
	#   "전환 중" 잠금은 여기서 푼다.
	#   예전에는 마지막 페이드 트윈이 끝나야 풀었는데, 그 트윈이 한 번이라도
	#   finished 를 안 내면(씬 전환 타이밍에 실제로 그런다) 잠금이 영영 안 풀리고
	#   그 뒤의 모든 화면 전환이 **아무 오류 없이 조용히 무시된다**.
	#   「섬 한 바퀴」가 몇 판 만에 그 자리에 서 버린 원인이 정확히 이것이었다.
	_busy = false
	if OS.has_environment("ROGAME_DEBUG"):
		print("[router] 잠금 해제 (%s)" % path.get_file())
	await _fade_to(0.0)
	_fade.visible = false


## 화면이 덮인 동안 "몇 번째 · 어디로" 를 한 번 띄운다.
## 글을 못 읽는 아이에게도 "장면이 바뀐다"는 신호가 되고, 읽는 아이에겐 기대가 된다.
## ★ duri 가 참이면 글자 위에 두리가 같이 뜬다. 글을 못 읽는 아이에게는
##   그림이 문장이다 — 쉬러 가는 순간에는 이쪽이 본문이고 글자가 각주다.
func _show_caption(text: String, duri := false) -> void:
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate = Color(1, 1, 1, 0.0)
	add_child(box)

	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 54)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	if duri:
		l.offset_top = 150.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)

	if duri:
		# 새 그림은 안 만든다 — 인사 포즈 한 장을 그대로 쓴다 (규칙 27).
		var img := TextureRect.new()
		img.texture = Look.duri("")
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 화면 한가운데를 기준으로 잡는다 — 게임(1280x720)과 허브(1280x800) 사이에서
		# 이 캡션이 뜨므로 절대 좌표로 두면 한쪽에서 어긋난다.
		img.anchor_left = 0.5
		img.anchor_right = 0.5
		img.anchor_top = 0.5
		img.anchor_bottom = 0.5
		img.offset_left = -105.0
		img.offset_right = 105.0
		img.offset_top = -250.0
		img.offset_bottom = 50.0
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(img)

	var hold := 1.15 if duri else 0.55
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.18)
	tw.tween_interval(hold)
	tw.tween_property(box, "modulate:a", 0.0, 0.18)
	# ★ 규칙 16. 여기가 Router 에 마지막으로 남아 있던 맨 `await tw.finished` 였다 —
	#   하필 화면이 100% 덮인 순간이라, 트윈이 한 번이라도 finished 를 안 내면
	#   **까만 화면 그대로 영영 멈춘다**(_busy 도 true 로 남아 그 뒤 모든 전환이 무시된다).
	#   _fade_to 와 똑같이 트윈·타이머 중 먼저 오는 쪽을 받는다.
	var guard := get_tree().create_timer(hold + 0.36 + 0.35, true, false, true)
	await _first_of(tw.finished, guard.timeout)
	box.queue_free()


func _fade_to(alpha: float) -> void:
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, FADE_TIME)
	# ★ 트윈이 죽으면 finished 가 안 온다 (이 저장소가 이미 한 번 물린 함정).
	#   타이머를 같이 걸어 두고 먼저 오는 쪽을 받는다 — 어느 쪽이든 잠기지 않는다.
	var guard := get_tree().create_timer(FADE_TIME + 0.35, true, false, true)
	await _first_of(tw.finished, guard.timeout)
	_fade.color.a = alpha


## 두 신호 중 먼저 오는 것을 기다린다.
func _first_of(a: Signal, b: Signal) -> void:
	var done := [false]
	var f := func():
		if not done[0]:
			done[0] = true
	a.connect(f, CONNECT_ONE_SHOT)
	b.connect(f, CONNECT_ONE_SHOT)
	while not done[0]:
		await get_tree().process_frame
