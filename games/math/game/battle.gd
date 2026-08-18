## 전투 화면 — 한 탄을 푸는 곳. 게임의 학습 루프 전체가 여기에 있다.
##
## 한 문제 = 뱀 한 마리. 흐름:
##   문제 제시 → 아이가 보기 선택 → ★블록 시연★ → 판정
##     정답  : 개구리가 혀로 공격 → 뱀 처치 → 다음 문제
##     오답  : 뱀이 막아냄 → 같은 문제 다시 (블록은 화면에 남겨 세어볼 수 있게)
##
## 보상(공격·처치)은 반드시 블록 시연 뒤에 온다. 탭 직후에 보상이 나오면
## 보상이 '탭'에 연합되고 시연은 건너뛰고 싶은 방해물이 된다.
##
## 오답 사다리 (벌주지 않고 계단을 놓는다):
##   1차 오답 — 하트 차감 없음. 과정만 시연하고 마지막 수는 가린다. 블록을 세면 답이 나온다.
##   2차 오답 — 다시 과정만 시연 (숙달 단축 모드 해제, 천천히).
##   3차 오답 — 답까지 포함한 완전 시연 후 정답 보기를 반짝여 '눌러보기'만 시킨다.
##              보상은 정상 정답과 똑같이 준다. 이후 3문항은 한 단계 쉬운 문제로 낮춘다.
##
## ★목숨(하트)이 없다. 시도 횟수에 제한이 없고 게임 오버도 없다.
## 아이가 마음 놓고 여러 번 눌러볼 수 있어야 계산을 다시 해 보게 된다.
extends Control

const HUD_H := 92.0
const CARD_H := 158.0
const PAD_H := 452.0
const BOTTOM_MARGIN := 56.0
## 전투 띠가 본문에서 차지하는 비율 (세로 배치).
##
## 세로 배치에서 넓은 화면(브라우저 등)일 때 가운데 이 폭까지만 쓴다.
const MAX_COL_W := 780.0

# --- 가로(태블릿) 배치 상수 ------------------------------------------------- #
## 답 열의 폭. 2x2 가 최소 칸(200) + 간격(36) 으로도 들어가려면 472 는 있어야 하고,
## 여기에 판 안쪽 여백 28 을 더한 490 이 하한이다. 이 값을 내리면 규칙 7이 깨진다.
const WIDE_PAD_MIN_W := 490.0
const WIDE_PAD_MAX_W := 640.0
## 답 열이 가져가는 화면 폭 비율.
const WIDE_PAD_RATIO := 0.38
## 답 판 안쪽 여백 (판 테두리와 버튼 사이).
const WIDE_PAD_INSET := 14.0

# 화면 구성
var _panel: Control
var _panel_top := 0.0
var _card: ProblemCard
var _stage: BlockStage
var _pad: AnswerPad
var _hud: Hud
var _next_btn: BigButton
var _skip_catcher: Control
var _result: ResultPanel
var _col_x := 0.0
var _col_w := 720.0
## 가로(태블릿) 배치를 쓰는 중인가. 판정은 Layout 한 곳에서만 한다.
var _wide := false

# 진행 상태
var _tier := 0
var _endless := false
## 「섬 한 바퀴」의 한 구간으로 들어왔는가.
var _journey := false
var _total := 5
var _index := 0
var _problem: Problem
var _problem_tier := 0
var _attempts := 0
var _wrong_total := 0
var _streak := 0
var _ease_remaining := 0
var _busy := false
var _errorless := false
var _finished := false
var _session_break_pending := false

var _used_keys := {}
var _recent_slots: Array[int] = []
var _review_queue: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_tier = Router.pending_tier
	_endless = Router.pending_endless
	# ★ 「섬 한 바퀴」로 들어왔는가. 여행에서는 보스도 없고, 대개 짧게 지나간다.
	_journey = Router.journey_stage > 0 and not _endless
	_total = 999 if _endless else Curriculum.question_count(_tier)
	if _journey and Router.pending_journey_count > 0:
		_total = Router.pending_journey_count

	_build_ui()
	_layout()
	# _ready() 시점에는 자기 size 가 아직 0이라 첫 배치가 어긋난다.
	# 앵커가 적용되며 크기가 잡히는 순간 다시 계산한다.
	resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	MathGame.session_limit_reached.connect(_on_session_limit)

	# BGM 은 Shell.enter_game() 이 문을 지날 때 한 번만 건다.
	# 씬마다 부르면 게임 경계를 넘어 전투 BGM 이 공룡 찾기 내내 루프로 깔린다.
	Audio.play_bgm("bgm_battle")
	if _journey:
		_hud.set_title("섬 %d번째" % Router.journey_stage)
	else:
		_hud.set_title(Loc.t("endless") if _endless else Curriculum.tier_title(_tier))
	_hud.show_hearts = false      # 목숨 없음 — 무한 시도
	await get_tree().process_frame
	_next_question()


# --------------------------------------------------------------------------- #
# 화면 구성
# --------------------------------------------------------------------------- #

func _build_ui() -> void:
	# ★ 개구리 기사·뱀·월드 배경은 없앴다. 이 게임의 알맹이는 문제 카드와 블록 시연이고,
	#   서사 장치는 다른 게임들과 결이 너무 달라서 앱 전체를 이질적으로 만들었다.
	#   그 자리는 전부 블록 무대에 준다 — 설명이 커질수록 좋은 게임이다.
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_panel)
	add_child(_panel)

	_card = ProblemCard.new()
	add_child(_card)

	_stage = BlockStage.new()
	_stage.count_changed.connect(_on_count_changed)
	# 무대가 "지금 이 항을 쌓는 중" 이라고 알려주면 문제 카드의 그 숫자를 키운다.
	_stage.term_focus.connect(func(i: int): _card.highlight_term(i))
	add_child(_stage)

	_pad = AnswerPad.new()
	_pad.answered.connect(_on_answered)
	add_child(_pad)

	# 맞히고 나면 바로 넘어가지 않는다. 아이가 방금 본 걸 음미할 시간을 주고,
	# 스스로 '다음' 을 눌러 넘어가게 한다.
	_next_btn = BigButton.make(Loc.t("next"), Palette.BTN_GREEN, BigButton.Icon.PLAY)
	_next_btn.font_size = 52
	_next_btn.visible = false
	_next_btn.pressed.connect(_on_next_pressed)
	add_child(_next_btn)

	_skip_catcher = Control.new()
	_skip_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_catcher.gui_input.connect(_on_skip_input)
	add_child(_skip_catcher)

	_hud = Hud.new()
	_hud.back_pressed.connect(_on_back)
	add_child(_hud)

	_result = ResultPanel.new()
	_result.action.connect(_on_result_action)
	add_child(_result)


func _layout() -> void:
	_wide = Layout.is_wide(size)
	if _wide:
		_layout_wide()
	else:
		_layout_tall()

	_skip_catcher.position = Vector2.ZERO
	_skip_catcher.size = size

	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sync_op_anchors()


## 세로(폰) 배치 — 위에서 아래로 HUD / 전투 / 문제 / 블록 / 답.
func _layout_tall() -> void:
	var w := size.x
	var h := size.y
	# HUD 는 스스로 상단에 앵커되고 노치 인셋만큼 키가 늘어난다. 여기서 크기를 만지면 안 된다.
	var hud_h := maxf(HUD_H, _hud.content_height())
	var remaining := h - hud_h - CARD_H - PAD_H - BOTTOM_MARGIN
	# ★ 전투 띠가 없어졌다. 남은 세로 공간은 전부 블록 무대가 가져간다.
	var block_h := maxf(220.0, remaining)
	_panel_top = hud_h
	_col_w = minf(w, MAX_COL_W)
	_col_x = (w - _col_w) * 0.5

	_panel.position = Vector2.ZERO
	_panel.size = size
	_panel.queue_redraw()

	var pad_x := _col_x + 16.0
	var inner := _col_w - 32.0
	_card.position = Vector2(pad_x, _panel_top + 12.0)
	_card.size = Vector2(inner, CARD_H - 16.0)

	_stage.position = Vector2(pad_x, _panel_top + CARD_H)
	_stage.size = Vector2(inner, block_h)

	_pad.position = Vector2(_col_x, h - BOTTOM_MARGIN - PAD_H)
	_pad.size = Vector2(_col_w, PAD_H)

	var nb_w := minf(_col_w - 96.0, 460.0)
	_next_btn.size = Vector2(nb_w, 132.0)
	_next_btn.position = Vector2(_col_x + (_col_w - nb_w) * 0.5,
			_pad.position.y + (PAD_H - 132.0) * 0.5)
	_next_btn.pivot_offset = _next_btn.size * 0.5


## 가로(태블릿) 배치.
##
##   ┌──────────────────────────────────────────────┐
##   │ HUD                                          │
##   ├──────────────────────────────────────────────┤
##   │ 전투 띠 — 개구리 ←────→ 뱀 (화면 폭 전체)     │
##   ├───────────────────────────┬──────────────────┤
##   │ 문제 카드   6 + 1 = ?     │   ┌────┬────┐    │
##   │                           │   ├────┼────┤    │
##   │ 블록 무대                 │   └────┴────┘    │
##   └───────────────────────────┴──────────────────┘
##
## 왼쪽이 '보는 곳', 오른쪽이 '고르는 곳'이다. 한국어 읽는 방향과 같게 두어야
## 아이가 "설명을 보고 → 답을 고른다" 는 순서를 따로 배우지 않아도 된다.
## 세로 배치에서 위/아래였던 것을 그대로 왼쪽/오른쪽으로 옮긴 것이라
## 블록 무대의 크기(폭 약 760, 높이 약 330)는 세로 때와 거의 같게 유지된다.
func _layout_wide() -> void:
	var w := size.x
	var h := size.y
	var hud_h := maxf(HUD_H, _hud.content_height())
	# ★ 전투 띠가 없어졌다. HUD 바로 아래부터 본문이다.
	_panel_top = hud_h
	_col_x = 0.0
	_col_w = w

	_panel.position = Vector2.ZERO
	_panel.size = size
	_panel.queue_redraw()

	# 답 열은 2x2 최소 크기가 반드시 들어가야 하므로 폭을 먼저 확보하고 남은 걸 왼쪽에 준다.
	var pad_w := clampf(w * WIDE_PAD_RATIO, WIDE_PAD_MIN_W, WIDE_PAD_MAX_W)
	pad_w = minf(pad_w, w * 0.5)
	var left_w := w - pad_w
	var panel_h := h - _panel_top - 6.0

	var inner := left_w - 32.0
	_card.position = Vector2(16.0, _panel_top + 12.0)
	_card.size = Vector2(inner, CARD_H - 16.0)

	_stage.position = Vector2(16.0, _panel_top + CARD_H)
	_stage.size = Vector2(inner, maxf(220.0, panel_h - CARD_H - 12.0))

	# 답 판 안쪽에 여백을 두어 버튼이 판 테두리를 넘지 않게 한다.
	var pad_h := maxf(AnswerPad.MIN_CELL * 2.0 + AnswerPad.GAP,
			panel_h - WIDE_PAD_INSET * 2.0)
	_pad.position = Vector2(left_w + WIDE_PAD_INSET, _panel_top + WIDE_PAD_INSET)
	_pad.size = Vector2(pad_w - WIDE_PAD_INSET * 2.0, pad_h)

	var nb_w := minf(_pad.size.x - 48.0, 420.0)
	_next_btn.size = Vector2(nb_w, 132.0)
	_next_btn.position = Vector2(_pad.position.x + (_pad.size.x - nb_w) * 0.5,
			_pad.position.y + (_pad.size.y - 132.0) * 0.5)
	_next_btn.pivot_offset = _next_btn.size * 0.5


## 문제 카드의 '+' x 를 블록 무대에 알려준다. 카드와 무대는 x/폭이 같아서 좌표가 그대로 통한다.
func _sync_op_anchors() -> void:
	if _card == null or _stage == null or _problem == null:
		return
	_stage.set_op_anchors(_card.op_centers())


func _draw_panel() -> void:
	var bottom := size.y - _panel_top - 6.0
	if _wide:
		var split := _pad.position.x - WIDE_PAD_INSET
		_fill_panel(Rect2(6.0, _panel_top, split - 12.0, bottom))
		_fill_panel(Rect2(split + 6.0, _panel_top, size.x - split - 12.0, bottom))
		return
	_fill_panel(Rect2(_col_x + 6.0, _panel_top, _col_w - 12.0, bottom))


func _fill_panel(r: Rect2) -> void:
	if r.size.x < 8.0 or r.size.y < 8.0:
		return
	DrawUtil.fill_aa(_panel, DrawUtil.round_rect(r, 34.0),
			Palette.with_alpha(Palette.PANEL, 0.96))
	DrawUtil.draw_outline(_panel, DrawUtil.round_rect(r, 34.0),
			Palette.with_alpha(Palette.CARD_EDGE, 0.9), 2.0)


# --------------------------------------------------------------------------- #
# 문제 진행
# --------------------------------------------------------------------------- #

func _next_question() -> void:
	if _finished:
		return
	if not _endless and _index >= _total:
		_finish()
		return
	if _endless and MathGame.session_over_limit():
		_finish()
		return

	_attempts = 0
	_errorless = false
	_next_btn.visible = false
	_pad.visible = true
	_problem = _pick_problem()
	if _problem == null:
		_finish()
		return

	_apply_slot_rule(_problem)
	_card.set_problem(_problem)
	var td := Curriculum.tier(_problem_tier)
	if MathGame.skip_demo:
		_stage.clear_stage()
	else:
		_stage.setup(_problem, _display_for(_problem, td), bool(td.get("ten_frame", true)))
		_sync_op_anchors()
	_stage.set_flash_mode(false)
	_pad.reset_states()
	_pad.show_choices(_problem.choices)
	_update_progress()
	# ★ 미취학 프로필: 블록 시연을 **답을 받기 전에** 먼저 돌린다.
	#   이게 없으면 5세는 "2 + 3 = ?" 라는 기호식만 보고 넷 중 하나를 골라야 하는데,
	#   5세는 + 기호를 모른다. play_demo(reveal=false) 는 이미 있었고,
	#   부르는 **순서만** 바뀐 것이다. 답은 안 알려 주고 블록만 놓아 보인다.
	if MathGame.demo_first and not MathGame.skip_demo:
		_pad.dim_all(true)
		await _stage.play_demo(false)
		if not is_inside_tree():
			return
		_pad.dim_all(false)
	_pad.unlock()


func _pick_problem() -> Problem:
	# 두 번 틀린 문제는 잠시 뒤 다시 물어본다 (간격 반복).
	for i in _review_queue.size():
		var r: Dictionary = _review_queue[i]
		if int(r["due"]) <= _index:
			_review_queue.remove_at(i)
			var rp: Problem = r["problem"]
			ProblemGen.build_choices(rp, MathGame.rng)
			_problem_tier = int(r["tier"])
			return rp

	var t := _tier
	if _ease_remaining > 0:
		t = maxi(0, _tier - 1)
		_ease_remaining -= 1
	_problem_tier = t

	var rule := ""
	var params := {}
	if _endless:
		rule = "review"
		params = Curriculum.endless_params(maxi(0, MathGame.highest_cleared()))
	else:
		var td := Curriculum.tier(t)
		rule = String(td["rule"])
		params = td["params"]

	for _try in 40:
		var p := ProblemGen.make_one(rule, params, MathGame.rng, t + 1, _mods_now())
		if p == null:
			continue
		if _used_keys.has(p.key()):
			continue
		_used_keys[p.key()] = true
		return p
	return ProblemGen.make_one(rule, params, MathGame.rng, t + 1, _mods_now())


## 정답이 세 번 연속 같은 자리에 오면 한 칸 돌린다.
## 7~8세는 '항상 두 번째' 같은 위치 전략을 아주 빨리 만든다.
func _apply_slot_rule(p: Problem) -> void:
	var idx := p.choices.find(p.answer)
	if _recent_slots.size() >= 2 \
			and _recent_slots[_recent_slots.size() - 1] == idx \
			and _recent_slots[_recent_slots.size() - 2] == idx:
		p.choices.push_front(p.choices.pop_back())
		idx = p.choices.find(p.answer)
	_recent_slots.append(idx)
	if _recent_slots.size() > 4:
		_recent_slots.pop_front()


func _display_for(p: Problem, td: Dictionary) -> int:
	if _endless:
		if p.op == Problem.Op.MUL:
			return Curriculum.Display.ARRAY
		if p.answer >= 10 or p.terms[0] >= 10:
			return Curriculum.Display.PLACE_VALUE
		return Curriculum.Display.TEN_FRAME
	return int(td.get("display", Curriculum.Display.TEN_FRAME))


# --------------------------------------------------------------------------- #
# 답 처리
# --------------------------------------------------------------------------- #

func _on_answered(value: int) -> void:
	if _busy or _problem == null:
		return
	var correct := value == _problem.answer

	if _errorless and not correct:
		# 완전 시연까지 본 뒤라 정답만 누르면 된다. 다른 걸 눌러도 혼내지 않고 다시 안내.
		_pad.glow(_problem.answer)
		Audio.play("ui_tap", 0.85)
		return

	_busy = true
	_pad.lock()
	_pad.mark(value, correct)
	MathGame.record_answer(_problem, correct, value)

	await _wait(0.28)
	if not is_inside_tree():
		return

	# ★블록 시연★ — 판정보다 먼저. 이게 이 게임의 존재 이유다.
	# 3차 오답이 될 차례면 이번 시연에서 바로 답까지 보여준다 (시연을 두 번 돌리지 않도록).
	var third_miss := (not correct) and _attempts >= 2
	var reveal := correct or _errorless or third_miss
	if MathGame.skip_demo:
		# 설명 건너뛰기 — 이미 아는 아이가 빠르게 풀 때.
		if reveal:
			_card.reveal_answer()
		await _wait(0.15)
	else:
		_stage.set_demo_level(MathGame.tier_m(_problem_tier))
		_pad.dim_all(true)
		_skip_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		_stage.setup(_problem, _stage_display(), _stage_ten_frame())
		await _stage.play_demo(reveal)
		_skip_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pad.dim_all(false)
		if not is_inside_tree():
			return
		if reveal:
			_card.reveal_answer()

	_update_adapt(correct)

	if correct:
		await _resolve_correct()
	else:
		await _resolve_wrong(value)
	_busy = false


## 적응형 조정 — 아이 눈에 아무 표시도 나가지 않는다.
##
## ★ 신호로 응답 시간을 쓰지 않는다. 초시계는 (a) 화면에 안 보이는 타이머이고,
##   (b) 아이가 잠깐 자리를 비우면 무너지고, (c) 4지선다 찍기를 숙련으로 오독한다
##   (순수 추측으로 2연속 정답 확률 1/16 -> 20문제 세션에 기대 1.2회 승급).
##   대신 **이미 저장 중인 누적 첫시도 정답 횟수**만 본다 — 같은 문제를 여러 번
##   맞혀야만 올라가므로 찍어서는 절대 못 올라간다.
##
##   m: 시연 단계 0~4 (올라가면 설명이 짧아진다 = 보상)
##   d: 문제 변형 -1~+2 (올라가면 빈칸·3항 같은 "새 모양"이 나온다 = 콘텐츠)
func _update_adapt(correct: bool) -> void:
	var t := _problem_tier
	var m := MathGame.tier_m(t)
	var d := MathGame.tier_d(t)
	if correct and _attempts == 0:
		# 이 문제를 여러 번 맞혀 봤는가?
		# ★ record_answer() 가 위(_on_answered 초입)에서 **이미** 불렸으므로
		#   이번 정답이 mastery 에 포함돼 있다. 3 이면 "세 번째로 맞힘"이다.
		if MathGame.mastery(_problem.key()) >= 3:
			MathGame.set_tier_m(t, m + 1)
		_good_streak += 1
		if _good_streak >= 4:
			MathGame.set_tier_d(t, d + 1)
			_good_streak = 0
			_cushion_q = 2      # 올린 직후 두 문제는 유예 (B6)
	elif not correct:
		_good_streak = 0
		# 틀리면 설명이 다시 자세해진다. 벌이 아니라 도움이다.
		MathGame.set_tier_m(t, m - 2)
		if _attempts >= 2:
			MathGame.set_tier_d(t, d - 1)


var _good_streak := 0
var _cushion_q := 0


## 지금 문제에 적용할 변형. 탄의 첫 문제와 d 를 올린 직후 두 문제는 유예한다 (B6/B7).
func _mods_now() -> Dictionary:
	var d := MathGame.tier_d(_problem_tier)
	if _index == 0 or _cushion_q > 0:
		_cushion_q = maxi(0, _cushion_q - 1)
		d = mini(d, 0)
	return Curriculum.mods_for(_problem_tier, d, MathGame.choice_count)


func _stage_display() -> int:
	return _display_for(_problem, Curriculum.tier(_problem_tier))


func _stage_ten_frame() -> bool:
	if _endless:
		return _problem.answer < 20
	return bool(Curriculum.tier(_problem_tier).get("ten_frame", true))


func _resolve_correct() -> void:
	_card.flash(true)
	Audio.play("correct")
	Fx.ring_pulse(self, _card.position + _card.size * 0.5, Palette.CORRECT, 180.0)

	if _attempts == 0:
		_streak += 1
	else:
		_streak = 0

	_index += 1
	MathGame.add_snake_defeated()   # 푼 문제 수 (부모 화면 통계)

	# ★ 보상은 반드시 **블록 시연 뒤에** 온다 (규칙 4). 시연 앞에 두면 보상이
	#   '탭' 에 연합되고 시연은 건너뛰고 싶은 방해물이 된다.
	#   예전에는 개구리가 뱀을 먹는 장면이 그 자리였다. 지금은 방금 센 블록들이
	#   그대로 터진다 — 보상이 **계산의 결과에서** 나오므로 연결이 더 곧다.
	await _celebrate_answer()
	if not is_inside_tree():
		return

	MathGame.count_session_question(true)
	_update_progress()
	_hud.pulse_progress()
	# 마지막 문제였다면 결과 판이 덮기 전에 **다 찬 진행 칩과 텅 빈 벌판**을 볼 시간을 준다.
	# 칩 채우기 애니메이션만 0.26 + 0.46초라, 0.35초 뒤에 덮으면 마지막 칸이
	# 안 찬 채로 다음 탄으로 넘어가는 것처럼 보인다.
	await _wait(1.0 if _index >= _total else 0.35)
	if not is_inside_tree():
		return
	# 그래도 마지막 칸이 덜 찼으면 찰 때까지 기다린다. 아이 눈에 진행 바는
	# "몇 마리 남았나" 를 세는 곳이라, 덜 찬 채로 결과 판이 덮으면
	# 다 잡았는데도 하나 남은 것처럼 보인다.
	await _await_progress_filled()
	if not is_inside_tree():
		return
	_show_next_button()


## 정답 축하 — 블록 무대에서 터진다.
##
## 캐릭터가 없어진 자리를 메우는 것이 아니라, 원래 있어야 할 자리로 옮긴 것이다.
## 아이가 방금 센 블록이 그대로 반짝이고 터지므로 "내가 센 것 -> 좋은 일" 이 곧게 이어진다.
func _celebrate_answer() -> void:
	var c := _stage.position + _stage.size * 0.5
	Fx.confetti(self, c, 18 if MathGame.reduce_motion else 30)
	Fx.ring_pulse(self, c, Palette.CORRECT, 220.0)
	await _wait(0.34)


## 진행 칩의 차오름이 끝날 때까지 기다린다.
## 트윈이 어떤 이유로 멈춰도 화면이 잠기지 않도록 프레임 상한을 둔다.
func _await_progress_filled() -> void:
	var frames := 0
	while not _hud.progress_settled() and frames < 180:
		await get_tree().process_frame
		frames += 1
		if not is_inside_tree():
			return


## 다음 문제로 넘어가는 버튼을 띄운다. 마지막 문제였으면 바로 마무리한다.
func _show_next_button() -> void:
	if _finished:
		return
	if not _endless and _index >= _total:
		_finish()
		return
	if _endless and MathGame.session_over_limit():
		_finish()
		return
	if MathGame.skip_demo:
		# 빠른 모드에서는 멈추지 않고 바로 다음 문제로.
		_next_question()
		return
	_pad.visible = false
	_next_btn.visible = true
	_next_btn.pop_in(0.0)


func _on_next_pressed() -> void:
	_next_btn.visible = false
	_pad.visible = true
	_next_question()


func _resolve_wrong(value: int) -> void:
	_attempts += 1
	_wrong_total += 1
	_streak = 0
	_stage.set_flash_mode(false)
	_card.flash(false)

	# ★ 중립 연출. **벌이 아니다** — 예전에는 뱀이 막아내는 그림이었고, 개구리가
	#   다치는 그림은 1차 오답에서 쓰지 않았다. 그 원칙을 그대로 옮겨,
	#   문제 카드가 한 번 흔들리기만 한다. 블록은 화면에 그대로 남는다(세어 볼 수 있게).
	Audio.play("wrong")
	await _wait(0.30)
	if not is_inside_tree():
		return

	if _attempts == 2:
		_queue_review(_problem)

	if _attempts >= 3:
		# 세 번이나 어려웠다면 다음 몇 문항은 한 단계 낮춘다 (벌이 아니라 발판).
		_ease_remaining = maxi(_ease_remaining, 3)
		# 답까지 포함한 완전 시연을 방금 봤다 (_on_answered 에서 reveal=true 로 재생).
		# 이제 정답 보기만 반짝이게 해서 '눌러보기'만 시킨다 — errorless completion.
		# 여기서 정답을 누르면 보상은 정상 정답과 똑같이 준다.
		_errorless = true
		_pad.reset_states()
		_pad.unlock()
		_pad.glow(_problem.answer)
		return

	# 같은 문제 다시. 보기 배치는 그대로 두어 '위치 찾기'가 아니라 '계산 다시 하기'를 시킨다.
	_card.hide_answer()
	_pad.reset_states()
	_pad.unlock()


func _queue_review(p: Problem) -> void:
	if _endless:
		return
	_review_queue.append({
		"problem": p.duplicate_problem(),
		"due": _index + 3,
		"tier": _problem_tier,
	})


## 무한 도전은 문제 수가 정해져 있지 않으므로 10문제 단위 구간으로 보여준다.
## (한 문제당 칩 하나를 그리는데, 50개가 되면 화면에 들어가지 않는다.)
func _update_progress() -> void:
	if _endless:
		_hud.set_progress(_index % 10, 10)
	else:
		_hud.set_progress(_index, _total)


func _on_count_changed(_v: int) -> void:
	pass


# --------------------------------------------------------------------------- #
# 마무리
# --------------------------------------------------------------------------- #

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_pad.lock()
	_next_btn.visible = false
	_pad.visible = true

	if _endless:
		var best := MathGame.record_endless(_index)
		Audio.play("stage_clear")
		_result.show_panel(Loc.t("endless_done"), PackedStringArray([
			Loc.f("solved_count", [_index]),
			(Loc.t("is_new_record") if best else Loc.f("best_count", [MathGame.endless_best])),
		]), -1, [
			{"id": "map", "label": Loc.t("go_map"), "color": Palette.BTN_BLUE},
			{"id": "again", "label": Loc.t("one_more"), "color": Palette.BTN_GREEN},
		])
		return

	# ★ 여행 구간이다 — 버튼을 누르게 하지 않는다. "쭈욱 넘어가는" 것이 이 모드의 전부다.
	if _journey:
		Audio.play("stage_clear")
		Fx.confetti(self, Vector2(size.x * 0.5, size.y * 0.34), 24)
		# 아직 안 깬 탄을 정규 문항 수로 다 풀었으면 별까지 남긴다 —
		# 그래야 여행만 해도 지도가 앞으로 나아간다.
		if Router.pending_journey_record:
			var js := 1
			if _wrong_total <= int(floor(float(_total) / 8.0)):
				js = 3
			elif _wrong_total <= int(ceil(float(_total) / 2.0)):
				js = 2
			MathGame.record_tier(_tier, js)
		await _wait(1.6)
		if not is_inside_tree():
			return
		Shell.journey_advance()
		return

	# ★ 별 판정은 문항 수에 비례한다.
	#   예전에는 문항 수와 무관하게 "오답 3개 이상이면 1별"이라, 5문제짜리 탄에서
	#   3번 틀리면 남은 문제의 긴장이 사라졌다. 그리고 그 1별은 지도에 영구히 남는데,
	#   하트·게임오버·타이머를 전부 없앤 설계와 정면으로 모순된다.
	#   더 엄격해진 항목은 하나도 없다.
	var stars := 1
	if _wrong_total <= int(floor(float(_total) / 8.0)):
		stars = 3
	elif _wrong_total <= int(ceil(float(_total) / 2.0)):
		stars = 2
	var improved := MathGame.record_tier(_tier, stars)
	Audio.play("stage_clear")
	Fx.confetti(self, Vector2(size.x * 0.5, size.y * 0.34), 34)

	var lines := PackedStringArray()
	if _wrong_total == 0:
		lines.append(Loc.t("all_correct"))
	elif improved:
		lines.append(Loc.t("new_record"))
	else:
		lines.append(Loc.f("snakes_beaten", [_total]))

	var buttons: Array = []
	if _session_break_pending or MathGame.session_over_limit():
		lines.append(Loc.t("rest_today"))
		buttons.append({"id": "map", "label": Loc.t("go_map"), "color": Palette.BTN_BLUE})
	else:
		var nxt := _tier + 1
		if nxt < Curriculum.tier_count():
			buttons.append({"id": "next", "label": Loc.t("next_tier"), "color": Palette.BTN_GREEN})
		else:
			buttons.append({"id": "endless", "label": Loc.t("endless"), "color": Palette.BTN_GREEN})
		buttons.append({"id": "map", "label": Loc.t("go_map"), "color": Palette.BTN_BLUE})

	_result.show_panel(Loc.t("tier_clear"), lines, stars, buttons)


func _on_session_limit() -> void:
	_session_break_pending = true


func _on_result_action(id: String) -> void:
	match id:
		"next":
			Router.goto_battle(_tier + 1)
		"map":
			Router.goto_tiers()
		"again":
			Router.goto_endless()
		"endless":
			Router.goto_endless()


# --------------------------------------------------------------------------- #
# 입력
# --------------------------------------------------------------------------- #

func _on_skip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if _stage.is_running():
			_stage.skip()
			accept_event()


func _on_back() -> void:
	# 여행 중이면 지도가 아니라 집으로 — 여행은 여기서 끝난다.
	if _journey:
		Shell.journey_end()
		Router.goto_hub()
		return
	Router.goto_tiers()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()


func _wait(sec: float) -> void:
	await get_tree().create_timer(maxf(0.01, sec * MathGame.anim_scale())).timeout
