## 답 보기 4개를 2x2 로 놓는 판.
##
## 세로 화면에서는 2x2 가 가장 안전한 배치다 — 손가락이 큰 아이도 옆 버튼을
## 잘못 누르지 않고, 네 개가 한눈에 다 들어온다.
## 각 버튼은 최소 200x200 디자인 px, 버튼 사이 간격은 최소 36 px 를 지킨다.
##
## 보기 순서는 절대 여기서 정렬하지 않는다. 오름차순으로 놓으면 아이가
## "제일 큰 게 답"이라는 잘못된 규칙을 배운다 — 섞는 일은 호출한 쪽이 한다.
class_name AnswerPad
extends Control

## 아이가 보기 하나를 탭했다.
signal answered(value: int)

## 버튼 한 변의 최소/최대 길이 (디자인 px).
const MIN_CELL := 200.0
const MAX_CELL := 288.0
## 버튼 사이 간격 (디자인 px).
const GAP := 36.0
## 2x2 고정.
const COLS := 2
## 보기 등장 시 버튼마다 밀리는 시간.
const STAGGER := 0.06

var _buttons: Array[AnswerButton] = []
var _locked: bool = false


func _init() -> void:
	# 판 자체는 입력을 먹지 않는다 — 버튼만 받는다.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MIN_CELL * 2.0 + GAP, MIN_CELL * 2.0 + GAP)


func _ready() -> void:
	resized.connect(_relayout)
	_relayout()


# --------------------------------------------------------------------------- #
# 공개 API
# --------------------------------------------------------------------------- #

## 보기를 보여준다. values 는 이미 섞여서 오며, 여기서 다시 정렬하지 않는다.
func show_choices(values: Array[int]) -> void:
	_ensure_buttons(values.size())
	_locked = false
	for i in _buttons.size():
		var b := _buttons[i]
		if i < values.size():
			b.reset_state()
			b.set_value(values[i])
			b.set_interactive(true)
			b.visible = true
		else:
			b.visible = false
	_relayout()
	for i in mini(_buttons.size(), values.size()):
		_buttons[i].pop_in(STAGGER * float(i))


## 모든 보기의 입력을 막는다. 겉모습은 그대로 남는다(사라지거나 흐려지지 않는다).
func lock() -> void:
	_locked = true
	for b in _buttons:
		b.set_interactive(false)


## 다시 답을 받을 수 있게 한다.
func unlock() -> void:
	_locked = false
	for b in _buttons:
		b.set_interactive(true)


## 해당 값을 가진 버튼을 정답/오답으로 표시한다.
## 오답이어도 다른 보기는 절대 지우거나 비활성으로 만들지 않는다(찍기 방지).
func mark(value: int, correct: bool) -> void:
	var b := button_for(value)
	if b == null:
		return
	b.set_state(AnswerButton.State.CORRECT if correct else AnswerButton.State.WRONG)


## 블록 시연 중 보기를 살짝 가라앉힌다. 여전히 또렷하게 보인다.
func dim_all(on: bool) -> void:
	for b in _buttons:
		if not b.visible:
			continue
		if on:
			if b.state() == AnswerButton.State.NORMAL:
				b.set_state(AnswerButton.State.DIMMED)
		elif b.state() == AnswerButton.State.DIMMED:
			b.set_state(AnswerButton.State.NORMAL)


## 무오류 완성: 답을 다 보여준 뒤 "이걸 눌러 보자"라고 금빛으로 알려준다.
## 나머지 보기는 그대로 둔다 — 눌러도 되는 상태여야 한다.
func glow(value: int) -> void:
	var b := button_for(value)
	if b == null:
		return
	if b.state() == AnswerButton.State.DIMMED:
		b.set_state(AnswerButton.State.NORMAL)
	b.set_state(AnswerButton.State.GLOWING)


## 모든 보기를 평소 모습으로 되돌린다.
func reset_states() -> void:
	for b in _buttons:
		b.reset_state()


## 보기를 전부 없앤다 (문제가 끝났을 때).
func clear() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_locked = false


## 해당 값을 가진 버튼. 없으면 null.
func button_for(value: int) -> AnswerButton:
	for b in _buttons:
		if b.visible and b.value() == value:
			return b
	return null


## 지금 화면에 있는 보기 개수.
func choice_count() -> int:
	var n := 0
	for b in _buttons:
		if b.visible:
			n += 1
	return n


# --------------------------------------------------------------------------- #
# 내부
# --------------------------------------------------------------------------- #

func _ensure_buttons(n: int) -> void:
	while _buttons.size() < n:
		var b := AnswerButton.new()
		b.pressed_value.connect(_on_button_pressed)
		add_child(b)
		_buttons.append(b)


func _on_button_pressed(v: int) -> void:
	if _locked:
		return
	answered.emit(v)


## 판 크기에 맞춰 2x2 격자를 다시 잡는다. 최소 크기와 간격은 절대 줄이지 않는다.
func _relayout() -> void:
	if _buttons.is_empty():
		return
	var cell := _cell_size()
	var total := Vector2(cell * 2.0 + GAP, cell * 2.0 + GAP)
	var origin := (size - total) * 0.5
	origin.x = maxf(origin.x, 0.0)
	origin.y = maxf(origin.y, 0.0)
	for i in _buttons.size():
		var b := _buttons[i]
		if not b.visible:
			continue
		var col := i % COLS
		var row := int(floor(float(i) / float(COLS)))
		b.size = Vector2(cell, cell)
		b.position = origin + Vector2(float(col) * (cell + GAP),
				float(row) * (cell + GAP))


## 버튼 한 변의 길이. 판이 좁아도 아동용 최소 터치 크기 아래로는 내려가지 않는다.
func _cell_size() -> float:
	var by_w := (size.x - GAP) * 0.5
	var by_h := (size.y - GAP) * 0.5
	return clampf(minf(by_w, by_h), MIN_CELL, MAX_CELL)
