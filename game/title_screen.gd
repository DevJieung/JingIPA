extends Node2D
class_name TitleScreen

## 시작 / 이어하기와 평생 기록. 만난 영웅 기록은 속성별 도감으로 열린다.

var main = null
var ui := Ui.new()
var collection := CollectionView.new()
var t: float = 0.0
## 부채꼴로 펼쳐진 카드 다섯 장 — 이 게임이 무슨 게임인지 한눈에 보이게.
var fan: Array[int] = []
## 시작을 두 번 눌러 판이 두 번 시작되지 않게.
var _started: bool = false
var _wordmark := Wordmark.new()


func _ready() -> void:
	# 글자 자체는 번들 글꼴로 유지하고 금속색·입체 테두리만 별도 캔버스에 그린다.
	add_child(_wordmark)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# 로열 스트레이트 플러시를 보여 준다. 타이틀에서까지 하이카드를 보여 줄 이유가 없다.
	var suit := rng.randi_range(0, 3)
	for r in [10, 11, 12, 13, 14]:
		fan.append(Poker.code(r, suit))
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	queue_redraw()


func _input(e: InputEvent) -> void:
	if collection.input(e, ui):
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if main == null or _started:
		return
	var id := ui.hit(e.position)
	if id == "collection":
		collection.opened = true
		Sfx.play("button")
	elif id == "resume":
		# 하다 만 판을 이어 한다. 되돌릴 수 없으면(옛 저장·깨진 저장) 조용히 새 판이다.
		_started = true
		Sfx.play("button")
		if not main.resume_run():
			main.start_run()
	elif id == "start":
		_started = true
		Sfx.play("button")
		# ★ 새로 시작하면 하다 만 판은 사라진다. 그 전에 한 번 물어보고 싶어지겠지만,
		#   이어하기 단추가 바로 위에 있으므로 여기서 또 묻는 것은 성가시기만 하다.
		main.start_run()


func _draw() -> void:
	var W := 1280.0
	var H := 800.0
	ui.begin()

	# ★ draw_at 은 원래 크기 그대로 놓기 때문에 위아래에 검은 띠가 남았다. 꽉 채운다.
	if not Art.draw_fill(self, Roster.ART.get("title_art", ""), Rect2(0, 0, W, H),
			Color.WHITE):
		draw_rect(Rect2(0, 0, W, H), Look.BG)
	draw_rect(Rect2(0, 0, W, H), Color(Look.BG_DEEP.r, Look.BG_DEEP.g, Look.BG_DEEP.b, 0.10))

	# 실제 영웅 원화를 배경 양쪽에 배치해 카드와 방어의 두 축을 함께 보여 준다.
	Art.draw_unit_fit(self, Roster.unit_by_id("brasa"), Rect2(32, 248, 218, 328))
	draw_set_transform(Vector2(1280, 0), 0, Vector2(-1, 1))
	Art.draw_unit_fit(self, Roster.unit_by_id("thalassa"), Rect2(34, 248, 214, 328))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# 부채꼴 카드
	var cx := W * 0.5
	var cy := 353.0
	for i in range(fan.size()):
		var k := float(i) - 2.0
		var ang := k * 0.16
		var pos := Vector2(cx + k * 96.0, cy + abs(k) * 15.0 + sin(t * 1.6 + k) * 5.0)
		draw_set_transform(pos, ang, Vector2.ONE)
		Look.draw_card(self, Vector2(-Look.CARD_W * 0.5, -Look.CARD_H * 0.5), fan[i], 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 도감이 열렸을 때 제목 장식이 모달 위로 나오지 않게 한다.
	_wordmark.visible = not collection.opened
	_wordmark.queue_redraw()

	var records := [
		["최고 탄수", "%d" % Save.best_wave, Look.CRYSTAL],
		["최고 족보", Poker.HAND_KO[Save.best_hand] if Save.best_hand >= 0 else "-", Look.GOLD],
		["만난 영웅", "%d / %d" % [Save.seen_count(), Roster.UNITS.size()], Look.GREEN],
	]
	for index in range(records.size()):
		var record: Array = records[index]
		var rect := Rect2(220 + index * 286, 482, 270, 100)
		Look.material_panel(self, rect, Look.PANEL, record[2])
		Look.text_center(self, rect.position + Vector2(135, 26), record[0], 20, Look.INK_DIM)
		Look.text_center_fit(self, rect.position + Vector2(135, 67), record[1], 31, record[2], 238, 20)
		if index == 2:
			Look.text_right(self, rect.position + Vector2(254, 26), "›", 24, Look.GREEN)
			ui.zone(rect, "collection")

	# ★ 하다 만 판이 있으면 **이어하기가 위**에 온다. 자동 저장을 넣은 뜻이 여기 있다 —
	#   앱을 껐다 켠 사람이 제일 먼저 누르고 싶은 단추가 그것이다.
	if Save.has_run():
		ui.button(self, Rect2(cx - 170.0, 608.0, 340.0, 64.0),
				"이어하기 — %d탄" % Save.run_wave(), "resume", true, Look.CRYSTAL, 34)
		ui.button(self, Rect2(cx - 120.0, 688.0, 240.0, 48.0), "새로 시작", "start", true,
				Look.PANEL_EDGE, 26)
	else:
		ui.button(self, Rect2(cx - 150.0, 626.0, 300.0, 76.0), "시작", "start", true,
				Look.GOLD, 38)

	collection.draw(self, ui)


## 배경과 카드의 색은 건드리지 않는 별도 워드아트 캔버스.
## 실제 글리프 위 금색 램프와 청동 입체면, 포커 문장으로 타이틀을 구성한다.
class Wordmark extends Node2D:
	const METAL_SHADER := preload("res://art/ui/title_wordmark.gdshader")

	func _ready() -> void:
		var metal := ShaderMaterial.new()
		metal.shader = METAL_SHADER
		material = metal

	func _diamond(center: Vector2, radius: Vector2, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -radius.y), center + Vector2(radius.x, 0),
			center + Vector2(0, radius.y), center - Vector2(radius.x, 0)]), color)

	func _draw() -> void:
		var dark := Color("#101b20")
		var bronze := Color("#75431d")
		var edge := Color("#e0ae4e")
		var light := Color("#fff0b0")
		var center := Vector2(640, 144)
		var title := I18n.t("올인 디펜스")
		var size := 94 if I18n.locale == "ko" else 80
		var font := Look.font(size)
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := Look._baseline(font, center - Vector2(width * 0.5, 0), size)

		# 세 장의 카드와 스페이드 방패. 작은 문장만으로 포커와 방어를 함께 표현한다.
		for index in [-1, 1]:
			draw_set_transform(Vector2(640 + index * 14, 62), index * 0.23)
			Look.px_panel(self, Rect2(-17, -25, 34, 50), dark, edge)
			draw_set_transform(Vector2.ZERO)
		var shield := PackedVector2Array([Vector2(620, 37), Vector2(660, 37),
			Vector2(660, 63), Vector2(654, 77), Vector2(640, 89),
			Vector2(626, 77), Vector2(620, 63)])
		draw_colored_polygon(shield, dark)
		var border := shield.duplicate()
		border.append(shield[0])
		draw_polyline(border, edge, 3.0)
		Look.draw_suit(self, Vector2(640, 57), 13, 0, light)
		_diamond(Vector2(640, 76), Vector2(3, 4), Look.CRYSTAL)

		# 그림자 → 청동 측면 → 얇은 금 테두리 → 밝은 안쪽 베벨 → 금속 전면.
		draw_string_outline(font, at + Vector2(0, 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 13, Color(dark, 0.8))
		for depth in range(8, 0, -1):
			draw_string_outline(font, at + Vector2(0, depth), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, bronze)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, dark)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, edge)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, dark)
		draw_string(font, at + Vector2(0, 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, bronze)
		draw_string(font, at + Vector2(0, -1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, light)
		draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
		Look._audit_raw(self, title, center - Vector2(width * 0.5, font.get_height(size) * 0.5), size)

		# 얇은 양쪽 장식은 글자보다 뒤로 물러나고, 부제는 두 언어의 브랜드를 함께 보여 준다.
		var subtitle := "ALL-IN DEFENSE" if I18n.locale == "ko" else "올인 디펜스"
		var sub_size := 23
		var sub_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
		var subtitle_pos := Vector2(640 - sub_width * 0.5, 212)
		var subtitle_at := Look._baseline(font, subtitle_pos, sub_size)
		draw_string_outline(font, subtitle_at, subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, 5, dark)
		draw_string(font, subtitle_at, subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, light)
		for direction in [-1, 1]:
			var start: float = 640 + direction * (sub_width * 0.5 + 24)
			var end: float = 640 + direction * (width * 0.5 + 24)
			draw_line(Vector2(start, 213), Vector2(end, 213), dark, 5)
			draw_line(Vector2(start, 211), Vector2(end, 211), edge, 2)
			_diamond(Vector2(end, 211), Vector2(5, 5), edge)
			var side := Vector2(640 + direction * (width * 0.5 + 38), 145)
			_diamond(side, Vector2(7, 12), dark)
			_diamond(side, Vector2(4, 8), edge)
