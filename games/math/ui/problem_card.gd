## 문제 카드 — 화면에서 가장 큰 글씨.
##
## 규칙: 문제에는 한글이 한 어절도 들어가지 않는다. 숫자와 기호뿐이다.
## 초1 아이의 읽기 자동성은 분당 60어절 남짓이라, 문장을 넣으면 그 시간이
## 전부 수학이 아니라 해독에 쓰인다.
##
## 연산 기호는 폰트가 아니라 Glyphs 로 직접 그린다 (Jua 에 ×, − 글리프가 없다).
class_name ProblemCard
extends Control

const BASE_FONT := 108
const MIN_FONT := 44
const OP_RATIO := 0.52     # 기호 크기 / 숫자 크기
const GAP_RATIO := 0.30    # 토큰 사이 간격 / 숫자 크기

var _problem: Problem
var _reveal := false
var _blank_pop := 0.0:
	set(v):
		_blank_pop = v
		queue_redraw()

var _shake := 0.0:
	set(v):
		_shake = v
		queue_redraw()

var _tint := 0.0:
	set(v):
		_tint = v
		queue_redraw()

var _tint_color := Palette.CORRECT
var _font_size := BASE_FONT

## 지금 설명 중인 항. 블록 무대가 그 항의 블록을 쌓는 동안 이 숫자를 키워 강조한다.
## 화면의 숫자와 무대의 블록이 같은 것이라는 걸 아이가 눈으로 잇게 하는 장치.
var _focus_term := -1
var _focus_pulse := 0.0:
	set(v):
		_focus_pulse = v
		queue_redraw()
var _focus_tw: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func(): _fit(); queue_redraw())


func set_problem(p: Problem) -> void:
	_problem = p
	_reveal = false
	_blank_pop = 0.0
	_tint = 0.0
	highlight_term(-1)
	_fit()
	queue_redraw()


## index 번째 항을 강조한다. -1 이면 해제.
func highlight_term(index: int) -> void:
	if _focus_tw != null and _focus_tw.is_valid():
		_focus_tw.kill()
	_focus_term = index
	if index < 0:
		_focus_pulse = 0.0
		queue_redraw()
		return
	_focus_pulse = 0.0
	_focus_tw = create_tween()
	_focus_tw.tween_property(self, "_focus_pulse", 1.0, 0.22 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 시연이 끝난 뒤 물음표 자리에 답을 채운다.
func reveal_answer() -> void:
	if _problem == null or _reveal:
		return
	_reveal = true
	_fit()
	var tw := create_tween()
	_blank_pop = 0.0
	tw.tween_property(self, "_blank_pop", 1.0, 0.32 * MathGame.anim_scale()) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_answer() -> void:
	_reveal = false
	_blank_pop = 0.0
	_fit()
	queue_redraw()


func flash(correct: bool) -> void:
	_tint_color = Palette.CORRECT if correct else Palette.WRONG
	var tw := create_tween()
	tw.tween_property(self, "_tint", 1.0, 0.10)
	tw.tween_property(self, "_tint", 0.0, 0.45)
	if not correct:
		var sh := create_tween()
		sh.tween_property(self, "_shake", 1.0, 0.05)
		sh.tween_property(self, "_shake", 0.0, 0.35) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# --------------------------------------------------------------------------- #

func _tokens() -> Array[Dictionary]:
	if _problem == null:
		return []
	return _problem.parts(_reveal)


## 카드 폭에 맞게 글씨 크기를 줄인다 (세 항 식이나 두 자리 수에서 필요).
func _fit() -> void:
	_font_size = BASE_FONT
	var avail := maxf(80.0, size.x - 48.0)
	while _font_size > MIN_FONT and _measure(_font_size) > avail:
		_font_size -= 4
	# 카드 높이에도 맞춘다.
	var max_by_h := int(clampf(size.y * 0.62, MIN_FONT, BASE_FONT))
	_font_size = mini(_font_size, max_by_h)


## 식을 이루는 토큰들의 가로 배치를 계산한다.
## 블록 무대가 이 값을 받아 같은 x 에 연산 기호를 놓는다 —
## 문제의 '+' 와 설명의 '+' 가 세로로 딱 맞아야 둘이 같은 식이라는 게 보인다.
func token_layout() -> Array[Dictionary]:
	var toks := _tokens()
	if toks.is_empty():
		return []
	var fs := _font_size
	var gap := float(fs) * GAP_RATIO
	var x := (size.x - _measure(fs)) * 0.5
	var out: Array[Dictionary] = []
	for t in toks:
		var w := _token_width(t, fs)
		out.append({"kind": String(t["kind"]), "cx": x + w * 0.5, "w": w})
		x += w + gap
	return out


## 등호 왼쪽에 있는 연산 기호들의 x 중심 (왼쪽부터).
func op_centers() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for t in token_layout():
		if String(t["kind"]) == "eq":
			break
		if String(t["kind"]) == "op":
			out.append(float(t["cx"]))
	return out


func _measure(fs: int) -> float:
	var gap := float(fs) * GAP_RATIO
	var w := 0.0
	var toks := _tokens()
	for i in toks.size():
		if i > 0:
			w += gap
		w += _token_width(toks[i], fs)
	return w


func _token_width(t: Dictionary, fs: int) -> float:
	match String(t["kind"]):
		"num", "answer":
			return Fonts.text_width(str(int(t["value"])), fs)
		"blank":
			return float(fs) * 0.62
		"op", "eq":
			return float(fs) * OP_RATIO
	return 0.0


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var shake_x := sin(_shake * 34.0) * 12.0 * _shake
	rect.position.x += shake_x

	DrawUtil.draw_card(self, rect.grow(-6.0), 30.0, Palette.CARD,
			Palette.CARD_EDGE, Palette.SHADOW, 7.0)
	if _tint > 0.01:
		DrawUtil.fill_aa(self, DrawUtil.round_rect(rect.grow(-6.0), 30.0),
				Palette.with_alpha(_tint_color, 0.22 * _tint))

	if _problem == null:
		return

	var toks := _tokens()
	if toks.is_empty():
		return
	var fs := _font_size
	var gap := float(fs) * GAP_RATIO
	var total := _measure(fs)
	var x := rect.position.x + (rect.size.x - total) * 0.5
	var cy := rect.position.y + rect.size.y * 0.5

	var term_i := 0
	var seen_eq := false
	for i in toks.size():
		var t := toks[i]
		var kind := String(t["kind"])
		var w := _token_width(t, fs)
		var c := Vector2(x + w * 0.5, cy)
		# 등호 왼쪽의 num/blank 만 '항'으로 센다.
		var my_term := -1
		if not seen_eq and (kind == "num" or kind == "blank" or kind == "answer"):
			my_term = term_i
			term_i += 1
		if kind == "eq":
			seen_eq = true
		var focused := my_term >= 0 and my_term == _focus_term
		match kind:
			"num":
				if focused:
					# 강조 색은 그 항의 블록 색과 똑같다 — 위의 숫자와 아래 블록이
					# 같은 것이라는 걸 색으로 잇는다 (왼쪽 주황 / 오른쪽 파랑·빨강).
					var tc := _problem.term_color(my_term)
					var k := 1.0 + 0.30 * DrawUtil.ease_out_back(clampf(_focus_pulse, 0.0, 1.0))
					var r := Vector2(w, float(fs)) * 0.72 * k
					DrawUtil.fill_aa(self, DrawUtil.round_rect(
							Rect2(c - r, r * 2.0), float(fs) * 0.24),
							Palette.with_alpha(tc, 0.26 * _focus_pulse))
					Fonts.draw_centered_outlined(self, str(int(t["value"])), c,
							int(float(fs) * k), Palette.shade(tc, -0.42), Palette.CARD, 8)
				else:
					Fonts.draw_centered(self, str(int(t["value"])), c, fs, Palette.INK)
			"answer":
				var s := 0.6 + 0.4 * DrawUtil.ease_out_back(clampf(_blank_pop, 0.0, 1.0))
				Fonts.draw_centered_outlined(self, str(int(t["value"])), c,
						int(float(fs) * s), Palette.CHOICE_DARK, Palette.CARD, 8)
			"blank":
				_draw_blank(c, fs)
			"op":
				Glyphs.draw_op(self, t["op"], c, float(fs) * OP_RATIO,
						Palette.INK_SOFT, Color(0, 0, 0, 0.10))
			"eq":
				Glyphs.draw_equals(self, c, float(fs) * OP_RATIO, Palette.INK_SOFT,
						Color(0, 0, 0, 0.10))
		x += w + gap


## 아직 모르는 수 — 물음표 대신 '빈 블록'으로 그린다. 블록 무대와 같은 언어를 쓴다.
##
## 색은 보기 버튼과 같은 초록이다. 항(주황/파랑/빨강)과 확실히 갈라 두어야
## "초록 = 내가 골라서 채울 자리"가 한눈에 읽힌다.
func _draw_blank(center: Vector2, fs: int) -> void:
	var s := float(fs) * 0.62
	var r := Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s))
	var pts := DrawUtil.round_rect(r, s * 0.24)
	DrawUtil.fill_aa(self, pts, Palette.with_alpha(Palette.CHOICE, 0.30))
	DrawUtil.draw_outline(self, pts, Palette.CHOICE_DARK, maxf(3.0, s * 0.09))
	Fonts.draw_centered(self, "?", center, int(s * 0.95), Palette.CHOICE_DARK)
