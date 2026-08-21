extends Node2D
class_name OverScreen

## 판이 끝났을 때. 이겼든 졌든 같은 화면이고 문구와 색만 다르다.

var main = null
var ui := Ui.new()
var fx := Fx.new()
var t: float = 0.0
var won: bool = false


func _ready() -> void:
	won = Run.phase == Run.Phase.WIN
	var mid := Vector2(640, 300)
	if won:
		fx.rays(mid, Look.GOLD, 22, 700.0, 2.4)
		fx.burst(mid, Look.GOLD, 140, 520.0, 1.5, 5.0, 260.0)
		fx.do_flash(Color(1, 1, 1, 0.8), 0.6)
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	fx.update(dt)
	queue_redraw()


func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if ui.hit(e.position) == "again" and main != null:
		main.go(main.show_title)


func _draw() -> void:
	ui.begin()
	draw_rect(Rect2(0, 0, 1280, 800), Look.BG)
	fx.draw_back(self)
	var col := Look.GOLD if won else Look.RED
	Look.text_center(self, Vector2(640, 200), "이겼다!" if won else "여기까지", 84, col)
	Look.text_center(self, Vector2(640, 296),
			"40탄을 모두 막아 냈다" if won else "%d탄에서 무너졌다" % Run.wave, 32, Look.INK)

	var lines := [
		"영웅 %d명" % Run.heroes.size(),
		"잡은 몬스터 %d마리" % Run.kills,
		"가장 좋았던 족보 %s" % (Poker.HAND_KO[Save.best_hand] if Save.best_hand >= 0 else "-"),
		"최고 기록 %d탄" % Save.best_wave,
	]
	var y := 390.0
	for s in lines:
		Look.text_center(self, Vector2(640, y), s, 26, Look.INK_DIM)
		y += 40.0

	ui.button(self, Rect2(490, 640, 300, 78), "다시", "again", true, Look.GOLD, 34)
	fx.draw(self)
	fx.draw_flash(self, Rect2(0, 0, 1280, 800))
