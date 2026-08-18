## 부모 화면 — 학습 리포트와 설정.
##
## 아이 화면에는 절대 나오지 않는 정보만 모은다. 정답률, 자주 틀리는 문제,
## 그리고 "어떤 종류의 실수인지"까지 보여준다. 실수 유형을 알면
## 무엇을 다시 봐야 하는지가 분명해진다.
extends Control

var _scroll: ScrollContainer
var _page: Control
var _back: BigButton
var _toggles: Dictionary = {}
var _reset: BigButton
var _confirm: ResultPanel
var _weak: Array = []
var _tags: Array = []
## 통계를 그릴 영역. _layout() 이 정하고 _draw_page() 가 그대로 쓴다.
## (두 곳에서 따로 계산하면 가로/세로를 바꿀 때 글씨와 카드가 어긋난다.)
var _stats_rect := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_weak = MathGame.weak_problems(8)
	_tags = MathGame.top_error_tags(5)

	var bgc := ColorRect.new()
	bgc.color = Palette.PANEL
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bgc)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_page = Control.new()
	_page.custom_minimum_size = Vector2(0, 100)
	_page.draw.connect(_draw_page)
	_scroll.add_child(_page)

	_back = BigButton.make("", Palette.BTN_GREY, BigButton.Icon.BACK)
	_back.round_shape = true
	_back.pressed.connect(Router.goto_hub)
	add_child(_back)

	_add_toggle("sfx", Loc.t("opt_sfx"), MathGame.sfx_enabled)
	_add_toggle("bgm", Loc.t("opt_bgm"), MathGame.bgm_enabled)
	_add_toggle("fast", Loc.t("opt_fast"), MathGame.fast_animation)
	_add_toggle("motion", Loc.t("opt_motion"), MathGame.reduce_motion)
	_add_toggle("skip", Loc.t("opt_skip"), MathGame.skip_demo)
	_add_toggle("session", Loc.t("opt_session"), MathGame.session_limit > 0)
	# ★ 언어 토글은 뺐다. 공룡 찾기 쪽 문자열(방 26종 + 공룡 50종 + UI)이 전부
	#   한글 하드코딩이라, 켜면 "개구리는 영어, 공룡은 한글"인 앱이 된다.
	#   문자열 표는 그대로 남아 있으므로 나중에 되살릴 수 있다.
	# 이 아이가 미취학 설정인가 — 시연을 먼저 보여 주고 보기를 2개로 줄인다.
	_add_toggle("young", "어린 아이 모드 (설명 먼저, 보기 2개)",
			String(Shell.profile()["age_band"]) == "pre")

	_reset = BigButton.make(Loc.t("reset"), Palette.WRONG)
	_reset.text_color = Palette.CARD
	_reset.font_size = 32
	_reset.pressed.connect(_ask_reset)
	_page.add_child(_reset)

	_confirm = ResultPanel.new()
	_confirm.action.connect(_on_confirm)
	add_child(_confirm)

	_layout()
	get_viewport().size_changed.connect(_layout)


func _add_toggle(id: String, label: String, on: bool) -> void:
	var b := BigButton.make(label, Palette.BTN_GREEN if on else Palette.BTN_GREY)
	b.font_size = 30
	b.text_color = Palette.INK if on else Palette.INK_SOFT
	b.pressed.connect(func(): _toggle(id))
	_page.add_child(b)
	_toggles[id] = b


func _toggle(id: String) -> void:
	match id:
		"sfx":
			MathGame.set_sfx(not MathGame.sfx_enabled)
		"bgm":
			MathGame.set_bgm(not MathGame.bgm_enabled)
		"fast":
			MathGame.set_fast_animation(not MathGame.fast_animation)
		"motion":
			MathGame.set_reduce_motion(not MathGame.reduce_motion)
		"session":
			MathGame.set_session_limit(0 if MathGame.session_limit > 0 else MathGame.DEFAULT_SESSION_LIMIT)
		"skip":
			MathGame.set_skip_demo(not MathGame.skip_demo)
		"young":
			_toggle_age_band()
	_refresh_toggles()


## 언어를 바꾸면 버튼 글자를 전부 다시 붙인다.
func _relabel() -> void:
	var labels := {
		"sfx": Loc.t("opt_sfx"), "bgm": Loc.t("opt_bgm"), "fast": Loc.t("opt_fast"),
		"motion": Loc.t("opt_motion"), "skip": Loc.t("opt_skip"),
		"session": Loc.t("opt_session"),
		"young": "어린 아이 모드 (설명 먼저, 보기 2개)",
	}
	for id in _toggles:
		(_toggles[id] as BigButton).text = String(labels.get(id, ""))
	_reset.text = Loc.t("reset")
	_page.queue_redraw()


func _refresh_toggles() -> void:
	var states := {
		"sfx": MathGame.sfx_enabled,
		"bgm": MathGame.bgm_enabled,
		"fast": MathGame.fast_animation,
		"motion": MathGame.reduce_motion,
		"session": MathGame.session_limit > 0,
		"skip": MathGame.skip_demo,
		"young": String(Shell.profile()["age_band"]) == "pre",
	}
	for id in _toggles:
		var b: BigButton = _toggles[id]
		var on: bool = bool(states.get(id, false))
		b.face_color = Palette.BTN_GREEN if on else Palette.BTN_GREY
		b.text_color = Palette.INK if on else Palette.INK_SOFT


# --------------------------------------------------------------------------- #

func _stats_height() -> float:
	return 300.0 + float(_weak.size()) * 44.0 + 70.0 + float(_tags.size()) * 40.0


func _layout() -> void:
	var w := size.x
	_back.size = Vector2(88, 88)
	_back.position = Vector2(16.0, 30.0)

	var inner: float
	var x: float
	var y: float
	if Layout.is_wide(size):
		# 가로(태블릿): 왼쪽에 리포트, 오른쪽에 설정. 세로로 길게 늘어놓으면
		# 화면 높이의 두 배 가까이 되어 부모가 계속 스크롤해야 한다.
		var half := w * 0.5
		var sw := minf(half - 48.0, 620.0)
		_stats_rect = Rect2(24.0 + (half - 48.0 - sw) * 0.5, 0.0, sw, _stats_height())
		inner = minf(half - 48.0, 560.0)
		x = half + (half - inner) * 0.5
		y = 100.0
	else:
		var sw2 := minf(w - 48.0, 620.0)
		_stats_rect = Rect2((w - sw2) * 0.5, 0.0, sw2, _stats_height())
		inner = sw2
		x = (w - inner) * 0.5
		y = _stats_height() + 30.0

	for id in ["sfx", "bgm", "fast", "motion", "skip", "session", "lang"]:
		var b: BigButton = _toggles[id]
		b.size = Vector2(inner, 88.0)
		b.position = Vector2(x, y)
		y += 100.0

	y += 30.0
	_reset.size = Vector2(inner, 88.0)
	_reset.position = Vector2(x, y)
	y += 140.0

	var page_h := maxf(y, _stats_rect.size.y + 60.0)
	_page.custom_minimum_size = Vector2(w, page_h)
	_page.size = Vector2(w, page_h)
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.queue_redraw()


func _draw_page() -> void:
	var inner := _stats_rect.size.x
	var x := _stats_rect.position.x
	var cx := x + inner * 0.5

	Fonts.draw_centered(_page, Loc.t("report"), Vector2(cx, 60.0), 46, Palette.INK)

	# --- 요약 카드 ---
	var card := Rect2(x, 100.0, inner, 172.0)
	DrawUtil.draw_card(_page, card, 26.0, Palette.CARD, Palette.CARD_EDGE,
			Palette.SHADOW, 5.0)
	var solved := int(MathGame.totals.get("correct", 0)) + int(MathGame.totals.get("wrong", 0))
	var mins := int(float(MathGame.totals.get("seconds", 0.0)) / 60.0)
	var cells := [
		[Loc.t("solved"), Loc.f("count_unit", [solved])],
		[Loc.t("accuracy"), "%d%%" % int(round(MathGame.accuracy() * 100.0))],
		[Loc.t("stages_done"), "%d / %d" % [maxi(0, MathGame.highest_cleared() + 1), Curriculum.tier_count()]],
		[Loc.t("stars"), "%d / %d" % [MathGame.total_stars(), MathGame.max_stars()]],
		[Loc.t("snakes"), Loc.f("snake_unit", [int(MathGame.totals.get("snakes", 0))])],
		[Loc.t("playtime"), Loc.f("minutes", [mins])],
	]
	for i in cells.size():
		var col := i % 3
		var row := i / 3
		var ccx := card.position.x + inner * (0.1667 + 0.3333 * float(col))
		var ccy := card.position.y + 52.0 + float(row) * 74.0
		Fonts.draw_centered(_page, String(cells[i][0]), Vector2(ccx, ccy), 24,
				Palette.INK_SOFT)
		Fonts.draw_centered(_page, String(cells[i][1]), Vector2(ccx, ccy + 34.0), 34,
				Palette.INK)

	# --- 자주 틀리는 문제 ---
	var y := card.position.y + card.size.y + 34.0
	Fonts.draw_centered(_page, Loc.t("weak_problems"), Vector2(cx, y), 32, Palette.INK)
	y += 40.0
	if _weak.is_empty():
		Fonts.draw_centered(_page, Loc.t("none_yet"), Vector2(cx, y + 12.0), 26,
				Palette.INK_SOFT)
		y += 44.0
	else:
		for item in _weak:
			var p: Problem = item["problem"]
			var line := Loc.f("wrong_times", [p.text(), int(item["wrong"])])
			Fonts.draw_centered(_page, line, Vector2(cx, y), 28, Palette.INK_SOFT)
			y += 44.0

	# --- 실수 유형 ---
	y += 26.0
	Fonts.draw_centered(_page, Loc.t("error_types"), Vector2(cx, y), 32, Palette.INK)
	y += 40.0
	if _tags.is_empty():
		Fonts.draw_centered(_page, Loc.t("none_yet"), Vector2(cx, y + 12.0), 26,
				Palette.INK_SOFT)
	else:
		for t in _tags:
			var label := Loc.t(String(t[0]))
			Fonts.draw_centered(_page, Loc.f("tag_times", [label, int(t[1])]),
					Vector2(cx, y), 26, Palette.INK_SOFT)
			y += 40.0


## 나이대를 바꾸면 그 프로필의 손잡이 묶음이 통째로 갈린다.
##
## ★ 별(stars)의 키는 탄 인덱스라 커리큘럼 시작점을 옮기면 어긋난다.
##   그래서 나이대는 **손잡이만** 바꾸고 커리큘럼 인덱스는 건드리지 않는다.
func _toggle_age_band() -> void:
	var p := Shell.profile()
	var band := "elem" if String(p["age_band"]) == "pre" else "pre"
	p["age_band"] = band
	p["tuning"] = Shell.default_tuning(band)
	Shell.mark_dirty()
	MathGame.pull_settings()


func _ask_reset() -> void:
	_confirm.show_panel(Loc.t("reset_ask"), PackedStringArray([
		Loc.t("reset_warn"),
	]), -1, [
		{"id": "cancel", "label": Loc.t("no"), "color": Palette.BTN_GREY},
		{"id": "reset", "label": Loc.t("yes_erase"), "color": Palette.WRONG},
	])


func _on_confirm(id: String) -> void:
	_confirm.hide_panel()
	if id == "reset":
		# ★ 지금 프로필만 지운다. 예전에는 저장 파일 전체를 지웠는데,
		#   형제가 한 기기를 쓰면 그건 형 기록을 날리는 지뢰다.
		MathGame.reset_progress()
		_weak = []
		_tags = []
		_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Router.goto_hub()
