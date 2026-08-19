## 타이틀 화면.
##
## 아이가 혼자서도 바로 시작할 수 있어야 하므로 가장 큰 버튼 하나가 곧 '시작'이다.
## 부모 메뉴는 작은 톱니 아이콘 뒤에 두고, 들어갈 때 간단한 관문을 둔다.
extends Control

var _start: BigButton
var _map: BigButton
var _endless: BigButton
var _gear: BigButton
var _sound: BigButton
var _home: BigButton
var _gate: ResultPanel
var _gate_problem: Problem
var _gate_pad: AnswerPad
var _title_bob := 0.0
## 가로(태블릿) 배치를 쓰는 중인가.
var _wide := false
## 제목·별을 그릴 가로 중심. 가로 배치에서는 화면 가운데가 아니라 왼쪽 절반의 가운데다.
var _hero_cx := 0.0
var _duri: TextureRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# ★ 여기서 begin_session() 을 부르지 않는다. 통합 앱에서는 허브 <-> 개구리
	#   왕복 한 번이 세션 카운터를 0 으로 리셋해 상한이 사실상 사라진다.
	#   세션은 Shell 이 앱 부팅에서 한 번만 시작한다.

	# ★ 배경 그림과 개구리 기사는 없앴다 — 서사를 걷어내고 알맹이만 남겼다.
	#   빈자리에는 앱의 주인공 두리가 선다 (core/look.gd — 이야기가 아니라 안내자다).
	# ★ 배경을 **자식 ColorRect 로 두지 않는다.** Control 의 _draw 는 자식보다 먼저
	#   그려지므로, 배경 노드를 자식으로 붙이면 이 화면의 제목("셈놀이")과 별 개수가
	#   통째로 덮여 안 보인다 — 실제로 그렇게 가려져 있었다. 배경은 _draw 첫 줄에서 칠한다.
	_duri = TextureRect.new()
	_duri.texture = Look.duri()
	_duri.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_duri.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_duri.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_duri)

	_start = BigButton.make(Loc.t("start"), Palette.BTN_GREEN, BigButton.Icon.PLAY)
	_start.font_size = 46
	_start.pressed.connect(_on_start)
	add_child(_start)

	_map = BigButton.make(Loc.t("map"), Palette.BTN_BLUE)
	_map.pressed.connect(Router.goto_tiers)
	add_child(_map)

	_endless = BigButton.make(Loc.t("endless"), Palette.BTN)
	_endless.pressed.connect(Router.goto_endless)
	add_child(_endless)

	# ★ "설명 건너뛰기"와 "언어" 버튼은 아이 화면에서 뺐다.
	#   설명 건너뛰기는 형이 눌러 두면 동생이 게임을 못 하게 되는 사고였고
	#   (프로필별 값이라 부모 화면에서만 켠다), 언어는 공룡 찾기 쪽 문자열이
	#   전부 한글 하드코딩이라 켜면 앱이 반쪽 영어가 된다.
	#   대신 그 자리에 집(허브)으로 가는 문을 둔다.
	_home = BigButton.make("집으로", Palette.BTN_BLUE)
	_home.font_size = 30
	_home.pressed.connect(Router.goto_hub)
	add_child(_home)

	_gear = BigButton.make("", Palette.BTN_GREY, BigButton.Icon.GEAR)
	_gear.round_shape = true
	_gear.pressed.connect(_open_gate)
	add_child(_gear)

	_sound = BigButton.make("", Palette.BTN_GREY,
			BigButton.Icon.SPEAKER_ON if MathGame.sfx_enabled else BigButton.Icon.SPEAKER_OFF)
	_sound.round_shape = true
	_sound.pressed.connect(_toggle_sound)
	add_child(_sound)

	_gate_pad = AnswerPad.new()
	_gate_pad.visible = false
	_gate_pad.answered.connect(_on_gate_answer)
	add_child(_gate_pad)

	_gate = ResultPanel.new()
	_gate.action.connect(_on_gate_action)
	add_child(_gate)

	_layout()
	get_viewport().size_changed.connect(_layout)
	Audio.play_bgm("bgm_menu")
	set_process(true)

	_start.pop_in(0.05)
	_map.pop_in(0.13)
	_endless.pop_in(0.21)


func _process(delta: float) -> void:
	_title_bob += delta
	queue_redraw()


func _layout() -> void:
	var w := size.x
	var h := size.y
	_wide = Layout.is_wide(size)

	_endless.visible = MathGame.all_cleared()
	if _wide:
		_layout_wide(w, h)
	else:
		_layout_tall(w, h)
	_refresh_options()

	# BigButton 은 custom_minimum_size(120x96) 아래로 줄지 않는다. 88 을 넣어도 120 이
	# 되므로, 오른쪽에 붙이는 버튼은 **대입한 뒤의 실제 size** 로 자리를 잡아야 한다.
	# (숫자를 미리 박아 두면 최소 크기가 바뀔 때 조용히 화면 밖으로 나간다.)
	_gear.size = Vector2(88, 88)
	_gear.position = Vector2(w - _gear.size.x - 20.0, 40.0)
	_sound.size = Vector2(88, 88)
	_sound.position = Vector2(20.0, 40.0)

	# 두리는 제목 아래에 선다 (가로 배치는 왼쪽 절반, 세로 배치는 가운데)
	var dh := clampf(h * 0.42, 180.0, 340.0)
	_duri.size = Vector2(dh * 0.7, dh)
	# 제목과 별 아래에 선다 (별 줄이 제목 바로 밑이라 그보다 더 내려가야 한다)
	_duri.position = Vector2(_hero_cx - _duri.size.x * 0.5,
			h * (0.40 if _wide else 0.34))

	_gate.set_anchors_preset(Control.PRESET_FULL_RECT)

	_start.text = Loc.t("start") if MathGame.highest_cleared() < 0 else Loc.t("continue")
	_map.text = Loc.t("map")
	_endless.text = Loc.t("endless")
	_map.visible = MathGame.highest_cleared() >= 0


## 세로(폰) 배치 — 개구리 아래로 버튼이 한 줄씩 쌓인다.
func _layout_tall(w: float, h: float) -> void:
	_hero_cx = w * 0.5

	var bw := minf(w - 120.0, 460.0)
	var bx := (w - bw) * 0.5
	var by := h * 0.60
	_start.size = Vector2(bw, 120.0)
	_start.position = Vector2(bx, by)
	_map.size = Vector2(bw, 100.0)
	_map.position = Vector2(bx, by + 140.0)
	_endless.size = Vector2(bw, 100.0)
	_endless.position = Vector2(bx, by + 256.0)

	var hw := (bw - 16.0) * 0.5
	_home.size = Vector2(hw * 2.0 + 16.0, 88.0)
	_home.position = Vector2(bx, by + (372.0 if _endless.visible else 256.0))

	_layout_gate_pad(w, h)


## 가로(태블릿) 배치 — 왼쪽에 제목과 개구리, 오른쪽에 버튼 기둥.
## 시작 버튼이 오른손 엄지 근처(오른쪽 가운데)에 오도록 둔다.
func _layout_wide(w: float, h: float) -> void:
	_hero_cx = w * 0.30

	var bw := clampf(w * 0.34, 320.0, 460.0)
	var bx := w * 0.72 - bw * 0.5
	var by := h * 0.20
	_start.size = Vector2(bw, 120.0)
	_start.position = Vector2(bx, by)
	_map.size = Vector2(bw, 100.0)
	_map.position = Vector2(bx, by + 140.0)
	_endless.size = Vector2(bw, 100.0)
	_endless.position = Vector2(bx, by + 256.0)

	var hw := (bw - 16.0) * 0.5
	_home.size = Vector2(hw * 2.0 + 16.0, 88.0)
	_home.position = Vector2(bx, by + (372.0 if _endless.visible else 256.0))

	_layout_gate_pad(w, h)


## 부모 관문에서만 쓰는 답 판. 화면 아래에 붙이고 위는 문제 패널 자리로 비워 둔다.
## 2x2 최소 크기(200x2 + 간격 36)가 실제로 들어갈 높이를 먼저 확보한다 —
## 가로 화면에서 비율로만 잡으면 판이 화면 아래로 삐져나간다.
func _layout_gate_pad(w: float, h: float) -> void:
	var gh := maxf(AnswerPad.MIN_CELL * 2.0 + AnswerPad.GAP, h * 0.34)
	_gate_pad.size = Vector2(w, gh)
	_gate_pad.position = Vector2(0.0, maxf(0.0, h - gh - 16.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.PANEL)
	# 가로 배치에서는 오른쪽이 버튼 기둥이므로 제목과 별을 왼쪽 절반 안에만 그린다.
	var cx := _hero_cx if _hero_cx > 1.0 else size.x * 0.5
	var avail := (size.x * 0.55 if _wide else size.x) - 60.0
	var bob := sin(_title_bob * 1.6) * 8.0
	var top := size.y * (0.22 if _wide else 0.20)
	var y := top + bob
	# 게임 제목 — 개구리 바로 위에 크게.
	var title := Loc.t("game_title")
	var fs := 78
	while fs > 34 and Fonts.text_width(title, fs) > avail:
		fs -= 3
	Fonts.draw_centered_outlined(self, title, Vector2(cx, y), fs,
			Palette.FROG_BODY, Palette.CARD, 14)

	# 모은 별
	var total := MathGame.total_stars()
	if total > 0:
		var bx := cx - 66.0
		var by := top + 92.0 + bob * 0.5
		Glyphs.draw_star(self, Vector2(bx, by), 24.0, Palette.STAR,
				Palette.shade(Palette.STAR, -0.35), 3.0)
		Fonts.draw_centered_outlined(self, "%d / %d" % [total, MathGame.max_stars()],
				Vector2(bx + 78.0, by), 34, Palette.INK, Palette.CARD, 7)


## 설정이 바뀌면 화면을 다시 그린다.
## (예전에는 여기서 "설명 건너뛰기" / "언어" 버튼의 글자도 갈아 끼웠는데,
##  그 둘은 아이 화면에서 빠지고 부모 화면으로 옮겼다.)
func _refresh_options() -> void:
	_layout()
	queue_redraw()


func _on_start() -> void:
	Router.goto_battle(MathGame.next_tier())


func _toggle_sound() -> void:
	var on := not MathGame.sfx_enabled
	MathGame.set_sfx(on)
	MathGame.set_bgm(on)
	_sound.icon = BigButton.Icon.SPEAKER_ON if on else BigButton.Icon.SPEAKER_OFF
	if on:
		Audio.play("ui_tap")


# --------------------------------------------------------------------------- #
# 부모 관문 — 아이가 실수로 설정을 바꾸지 못하게 하는 최소한의 장치.
# 게임에서 다루지 않는 두 자리 곱셈을 낸다.
# --------------------------------------------------------------------------- #

func _open_gate() -> void:
	# 관문 패널과 답 판의 자리는 화면 크기에 딸려 있다. 앵커가 반영되는 다음 프레임을
	# 기다리면 한 프레임 동안 엉뚱한 자리에 뜨므로 여기서 지금 크기로 맞춰 둔다.
	_layout()
	_gate.size = size
	# 관문은 패널 아래에 답 판이 같이 뜬다. 가운데에 두면 답 버튼이 '닫기' 를 덮어
	# 관문에서 빠져나올 수가 없다 — 답 판 위까지만 쓰게 한다.
	_gate.max_bottom = _gate_pad.position.y - 12.0
	_gate_problem = Problem.new()
	_gate_problem.op = Problem.Op.MUL
	_gate_problem.terms = [MathGame.rng.randi_range(11, 19), MathGame.rng.randi_range(6, 9)]
	_gate_problem.recompute()
	ProblemGen.build_choices(_gate_problem, MathGame.rng)
	_gate.show_panel(Loc.t("parent_check"), PackedStringArray([
		"%d x %d = ?" % [_gate_problem.a, _gate_problem.b],
	]), -1, [{"id": "cancel", "label": Loc.t("close"), "color": Palette.BTN_GREY}])
	_gate_pad.visible = true
	_gate_pad.reset_states()
	_gate_pad.show_choices(_gate_problem.choices)
	_gate_pad.unlock()
	move_child(_gate_pad, get_child_count() - 1)


func _on_gate_answer(value: int) -> void:
	if _gate_problem == null:
		return
	if value == _gate_problem.answer:
		_gate_pad.visible = false
		_gate.hide_panel()
		Router.goto_parent()
	else:
		_gate_pad.mark(value, false)
		Audio.play("wrong", 1.0, -6.0)


func _on_gate_action(id: String) -> void:
	if id == "cancel":
		_gate_pad.visible = false
		_gate.hide_panel()
