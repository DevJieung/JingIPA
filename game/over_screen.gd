extends Node2D
class_name OverScreen

## 판이 끝났을 때. 이겼든 졌든 같은 화면이고 문구와 색만 다르다.

var main = null
var ui := Ui.new()
var fx := Fx.new()
var t: float = 0.0
var won: bool = false
var _leaving := false


func _ready() -> void:
	won = Run.phase == Run.Phase.WIN
	var mid := Vector2(640, 300)
	if won:
		fx.rays(mid, Look.GOLD, 22, 700.0, 2.4)
		fx.burst(mid, Look.GOLD, 140, 520.0, 1.5, 5.0, 260.0)
		fx.do_flash(Color(1, 1, 1, 0.8), 0.6)
		Sfx.force("victory")
	else:
		Sfx.force("defeat")
	set_process(true)


func _process(dt: float) -> void:
	if not Ads.busy and Run.running and Run.phase == Run.Phase.SWAP and not _leaving and main != null:
		_leaving = true
		main.go(main.show_draw)
		return
	t += dt
	fx.update(dt)
	queue_redraw()


func _input(e: InputEvent) -> void:
	if Ads.busy or _leaving:
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var id := ui.hit(e.position)
	if id == "continue":
		Ads.request_reward("continue")
	elif id == "again" and main != null:
		Sfx.play("button")
		Run.finish_defeat()
		_leaving = true
		main.go(main.show_title)


func _draw() -> void:
	ui.begin()
	Look.camp_backdrop(self)
	draw_rect(Look.SCREEN, Color(0.01, 0.03, 0.035, 0.35))
	Look.text_center(self, Vector2(640, 82), "승리!" if won else "게임 종료", 35, Look.GOLD if won else Look.INK)
	var best := Run.best_player()
	Look.material_panel(self, Rect2(408, 130, 464, 420), Look.PANEL, Look.GOLD_DEEP, "stone")
	Look.text_center(self, Vector2(640, 166), "Best Player", 36, Look.GOLD)
	if not best.is_empty():
		var unit: Dictionary = best["unit"]
		var element := String(unit.get("elem", "none"))
		SummonArt.seal(self, Vector2(640, 339), 126, t * 0.22, Balance.elem_color(element), 0.33)
		Look.fill_round(self, Rect2(484, 449, 312, 20), 4, Look.GOLD_DEEP)
		Art.draw_unit_fit(self, unit, Rect2(488, 208, 304, 258))
		Look.draw_rarity(self, Vector2(640, 485), int(best["tier"]), 9)
		Look.text_center_fit(self, Vector2(640, 521), Look.unit_name(unit), 30, Look.INK, 410, 23)
		Look.text_center(self, Vector2(640, 575), "누적 피해 %s" % _damage_text(float(best["damage"])), 23, Look.INK_DIM)
	else:
		Look.text_center(self, Vector2(640, 340), "-", 42, Look.INK_DIM)
	if not won:
		Look.text_center_fit(self, Vector2(640, 613), "크리스탈 전체 회복 + 1,000,000 G", 27, Look.CRYSTAL, 1100, 23)
		ui.reward_button(self, Rect2(340, 641, 600, 64), "광고 보고 부활 + Gold", "continue",
				Run.reward_allowed("continue"), Look.GOLD, 30)
		Look.text_box(self, Rect2(280, 712, 720, 34), "대기실에서 준비 후 같은 탄에 다시 도전합니다.", 20, Look.INK_DIM)
	ui.button(self, Rect2(1090, 740, 150, 36), "타이틀로", "again", true, Look.PANEL_EDGE, 18)
	fx.draw_back(self)
	fx.draw(self)
	fx.draw_flash(self, Look.SCREEN)


func _damage_text(value: float) -> String:
	if value >= 1000000:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return "%d" % int(value)
