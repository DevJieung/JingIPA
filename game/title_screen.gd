extends Node2D
class_name TitleScreen

## 타이틀. 누를 것은 「시작」 하나뿐이다.

var main = null
var ui := Ui.new()
var t: float = 0.0
## 부채꼴로 펼쳐진 카드 다섯 장 — 이 게임이 무슨 게임인지 한눈에 보이게.
var fan: Array[int] = []


func _ready() -> void:
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
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var id := ui.hit(e.position)
		if id == "start" and main != null:
			main.start_run()


func _draw() -> void:
	var W := 1280.0
	var H := 800.0
	ui.begin()

	if not Art.draw_at(self, Roster.ART.get("title_art", ""), W * 0.5, H * 0.86, 1.0,
			Color(0.72, 0.72, 0.8)):
		draw_rect(Rect2(0, 0, W, H), Look.BG)
	draw_rect(Rect2(0, 0, W, H), Color(Look.BG_DEEP.r, Look.BG_DEEP.g, Look.BG_DEEP.b, 0.55))

	# 부채꼴 카드
	var cx := W * 0.5
	var cy := 372.0
	for i in range(fan.size()):
		var k := float(i) - 2.0
		var ang := k * 0.16
		var pos := Vector2(cx + k * 96.0, cy + abs(k) * 15.0 + sin(t * 1.6 + k) * 5.0)
		draw_set_transform(pos, ang, Vector2.ONE)
		Look.draw_card(self, Vector2(-Look.CARD_W * 0.5, -Look.CARD_H * 0.5), fan[i], 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 제목
	var glow := 0.5 + 0.5 * sin(t * 2.0)
	Look.text_center(self, Vector2(cx, 150.0), "포커 디펜스", 92,
			Look.GOLD.lerp(Color.WHITE, glow * 0.35))
	Look.text_center(self, Vector2(cx, 216.0),
			"트럼프 다섯 장으로 영웅을 뽑아 몬스터를 막아라", 26, Look.INK_DIM)

	# 기록
	var rec := "최고 %d탄" % Save.best_wave if Save.best_wave > 0 else "첫 판"
	if Save.best_hand >= 0:
		rec += "   ·   최고 족보 %s" % Poker.HAND_KO[Save.best_hand]
	Look.text_center(self, Vector2(cx, 700.0), rec, 24, Look.INK_DIM)

	ui.button(self, Rect2(cx - 150.0, 588.0, 300.0, 82.0), "시작", "start", true, Look.GOLD, 38)
