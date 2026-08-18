## 탄 고르는 화면.
##
## ★ 예전에는 월드 지도(늪지·호수·숲…)였다. 그 서사가 다른 게임들과 결이 너무 달라서
##   걷어내고, 남은 것만 남겼다 — **어디까지 왔는지**와 **다음에 무엇을 하는지**.
##   지도가 알려 주던 정보는 그대로 있다: 깬 탄, 별, 지금 갈 곳.
extends Control

const COLS := 6
const TILE := 148.0
const GAP := 18.0

var _back: BigButton
var _grid: Control
var _pressed := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Palette.PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_grid = Control.new()
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_on_grid_input)
	add_child(_grid)

	_back = BigButton.make("", Palette.BTN_GREY, BigButton.Icon.BACK)
	_back.round_shape = true
	_back.pressed.connect(Router.goto_hub)
	add_child(_back)

	resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	_back.size = Vector2(88, 88)
	_back.position = Vector2(24, 24)
	_grid.position = Vector2.ZERO
	_grid.size = size
	_grid.queue_redraw()


func _rows() -> int:
	return int(ceil(float(Curriculum.tier_count()) / float(COLS)))


func _tile_rect(i: int) -> Rect2:
	var total_w := float(COLS) * TILE + float(COLS - 1) * GAP
	var total_h := float(_rows()) * TILE + float(_rows() - 1) * GAP
	var x0 := (size.x - total_w) * 0.5
	var y0 := maxf(128.0, (size.y - total_h) * 0.5 + 26.0)
	return Rect2(x0 + float(i % COLS) * (TILE + GAP),
			y0 + float(i / COLS) * (TILE + GAP), TILE, TILE)


func _draw_grid() -> void:
	Fonts.draw_centered(_grid, "어디까지 왔나",
			Vector2(size.x * 0.5, 74.0), 46, Palette.INK)

	for i in Curriculum.tier_count():
		var r := _tile_rect(i)
		var unlocked := MathGame.is_unlocked(i)
		var stars := MathGame.tier_stars(i)
		var press := 5.0 if _pressed == i else 0.0
		var face := Palette.CARD if unlocked else Palette.shade(Palette.CARD, -0.10)
		DrawUtil.draw_card(_grid, Rect2(r.position + Vector2(0, -press), r.size), 22.0,
				face, Palette.CARD_EDGE, Palette.SHADOW, 5.0)

		var c := r.position + r.size * 0.5 + Vector2(0, -press)
		if unlocked:
			Fonts.draw_centered(_grid, "%d" % (i + 1), c + Vector2(0, -8.0), 52, Palette.INK)
			# 이 탄이 무엇을 배우는 곳인지 한 줄 (읽는 아이에게만 쓸모 있고, 못 읽어도 손해 없다)
			# 무엇을 배우는 탄인지 한 줄 (읽는 아이에게만 쓸모 있고, 못 읽어도 손해 없다)
			Fonts.draw_centered(_grid, Curriculum.tier_goal(i), c + Vector2(0, 28.0), 15,
					Palette.INK_SOFT)
			for s in 3:
				var sc := c + Vector2((float(s) - 1.0) * 26.0, 52.0)
				Glyphs.draw_star(_grid, sc, 11.0,
						Palette.STAR if s < stars else Palette.shade(Palette.CARD, -0.16),
						Palette.shade(Palette.STAR if s < stars else Palette.CARD, -0.30), 2.0)
		else:
			# 잠긴 탄 — 자물쇠 대신 흐린 점 세 개. "못 한다"가 아니라 "아직 안 왔다".
			for d in 3:
				_grid.draw_circle(c + Vector2((float(d) - 1.0) * 18.0, 0.0), 6.0,
						Palette.shade(Palette.CARD, -0.20))

	# 다음에 갈 곳을 한 번 짚어 준다
	var nxt := MathGame.next_tier()
	if nxt >= 0 and nxt < Curriculum.tier_count():
		var nr := _tile_rect(nxt)
		DrawUtil.draw_card(_grid, nr.grow(7.0), 26.0, Color(0, 0, 0, 0),
				Palette.CORRECT, Color(0, 0, 0, 0), 4.0)


func _on_grid_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not mb.pressed:
		_pressed = -1
		_grid.queue_redraw()
		return
	for i in Curriculum.tier_count():
		if _tile_rect(i).has_point(mb.position) and MathGame.is_unlocked(i):
			_pressed = i
			_grid.queue_redraw()
			Router.goto_battle(i)
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Router.goto_hub()
