extends Node2D
class_name ShopScreen

## 탄과 탄 사이의 상점. 잡은 몬스터로 번 골드를 여기서 쓴다.
##
## 두 줄기다:
##  - 왼쪽 **능력치** — 살수록 값이 오른다. 이 게임의 진짜 성장 곡선이 여기다.
##    (족보는 운이라 믿을 수 없다. 매 판 확실히 세지는 길이 하나는 있어야 한다.)
##  - 오른쪽 **패시브** — 한 번만 사는 것. 매 판 셋만 내놓아서 판마다 다른 길이 열린다.

var main = null
var ui := Ui.new()
var fx := Fx.new()
var t: float = 0.0
var offer: Array = []
var flash_id: String = ""
var flash_t: float = 0.0


func _ready() -> void:
	offer = Run.offer_passives(3)
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	fx.update(dt)
	if flash_t > 0.0:
		flash_t = max(0.0, flash_t - dt)
	queue_redraw()


func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var id := ui.hit(e.position)
	if id == "":
		return
	if id == "next":
		if main != null:
			main.go(main.go_draw)
		return
	if id.begins_with("u:"):
		var uid := id.substr(2)
		if Run.buy_upgrade(uid):
			_bought(uid, e.position)
	elif id.begins_with("p:"):
		var pid := id.substr(2)
		if Run.buy_passive(pid):
			offer = offer.filter(func(p): return p["id"] != pid)
			_bought(pid, e.position)
			fx.do_flash(Color(1, 0.9, 0.5, 0.35), 0.3)


func _bought(id: String, at: Vector2) -> void:
	flash_id = id
	flash_t = 0.45
	fx.burst(at, Look.GOLD, 22, 260.0)
	fx.ring(at, Look.GOLD, 10.0, 90.0, 0.4, 4.0)


func _draw() -> void:
	ui.begin()
	if not Art.draw_at(self, Roster.ART.get("shop_bg", ""), 640.0, 800.0, 1.0,
			Color(0.42, 0.40, 0.5)):
		draw_rect(Rect2(0, 0, 1280, 800), Look.BG)
	draw_rect(Rect2(0, 0, 1280, 800), Color(Look.BG_DEEP.r, Look.BG_DEEP.g, Look.BG_DEEP.b, 0.62))
	_draw_topbar()

	Look.text_left(self, Vector2(40, 108), "능력치", 32, Look.INK)
	Look.text_left(self, Vector2(150, 112), "살수록 값이 오른다", 20, Look.INK_DIM)
	var y := 140.0
	for u in Balance.UPGRADES:
		_draw_upgrade(u, Rect2(40, y, 700, 62))
		y += 68.0

	Look.text_left(self, Vector2(790, 108), "패시브", 32, Look.INK)
	Look.text_left(self, Vector2(900, 112), "한 번만 산다", 20, Look.INK_DIM)
	var py := 140.0
	for p in offer:
		_draw_passive(p, Rect2(790, py, 450, 128))
		py += 140.0
	if offer.is_empty():
		Look.text_left(self, Vector2(790, 180), "더 살 패시브가 없다", 24, Look.INK_DIM)

	# 이미 산 패시브
	if Run.passives.size() > 0:
		var names: Array = []
		for p in Balance.PASSIVES:
			if Run.passives.has(p["id"]):
				names.append(String(p["ko"]))
		Look.text_left(self, Vector2(790, 600), "가진 패시브", 22, Look.INK_DIM)
		Look.text_left(self, Vector2(790, 634), ", ".join(names), 20, Look.GOLD)

	ui.button(self, Rect2(790, 700, 450, 74), "%d탄으로" % (Run.wave + 1), "next",
			true, Look.GOLD, 32)
	fx.draw(self)
	fx.draw_flash(self, Rect2(0, 0, 1280, 800))


func _draw_topbar() -> void:
	draw_rect(Rect2(0, 0, 1280, 68), Look.PANEL)
	draw_rect(Rect2(0, 66, 1280, 2), Look.PANEL_EDGE)
	Look.text_left(self, Vector2(28, 34), "상점", 34, Look.INK)
	var hx := 220.0
	if not Art.draw_at(self, Roster.ART.get("heart", ""), hx, 46.0):
		draw_circle(Vector2(hx, 34), 12.0, Look.RED)
	Look.text_left(self, Vector2(hx + 22, 34), "%d / %d" % [Run.lives, Run.max_lives()], 28, Look.INK)
	var gx := 420.0
	if not Art.draw_at(self, Roster.ART.get("coin", ""), gx, 47.0):
		draw_circle(Vector2(gx, 34), 12.0, Look.GOLD)
	Look.text_left(self, Vector2(gx + 22, 34), "%d G" % Run.gold, 30, Look.GOLD)
	Look.text_right(self, Vector2(1252, 34), "다음은 %d탄" % (Run.wave + 1), 24, Look.INK_DIM)


func _draw_upgrade(u: Dictionary, r: Rect2) -> void:
	var id := String(u["id"])
	var l := Run.lv(id)
	var maxed := Balance.upgrade_maxed(id, l)
	var cost := Balance.upgrade_cost(id, l)
	var can := (not maxed) and Run.gold >= cost
	var lit: float = (flash_t / 0.45) if flash_id == id else 0.0
	Look.fill_round(self, r, 10.0, Look.PANEL.lerp(Look.GOLD, lit * 0.35))
	draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Look.GOLD if can else Look.PANEL_EDGE)
	Look.text_left(self, Vector2(r.position.x + 18, r.position.y + 22),
			String(u["ko"]), 26, Look.INK)
	Look.text_left(self, Vector2(r.position.x + 18, r.position.y + 48),
			String(u["desc"]), 19, Look.INK_DIM)
	var cap := int(u["cap"])
	var lvtxt := "Lv %d" % l if cap == 0 else "Lv %d / %d" % [l, cap]
	Look.text_right(self, Vector2(r.position.x + 470, r.position.y + 34), lvtxt, 22, Look.INK_DIM)
	if maxed:
		ui.button(self, Rect2(r.position.x + 500, r.position.y + 8, 180, 46),
				"끝", "u:" + id, false, Look.PANEL_EDGE, 22)
	else:
		ui.button(self, Rect2(r.position.x + 500, r.position.y + 8, 180, 46),
				"%d G" % cost, "u:" + id, can, Look.GOLD, 24)


func _draw_passive(p: Dictionary, r: Rect2) -> void:
	var id := String(p["id"])
	var cost := int(p["cost"])
	var can := Run.gold >= cost
	var lit: float = (flash_t / 0.45) if flash_id == id else 0.0
	Look.fill_round(self, r.grow(3.0), 14.0, Look.GOLD if can else Look.PANEL_EDGE)
	Look.fill_round(self, r, 12.0, Look.PANEL.lerp(Look.GOLD, lit * 0.35))
	Look.text_left(self, Vector2(r.position.x + 20, r.position.y + 30),
			String(p["ko"]), 30, Look.GOLD if can else Look.INK_DIM)
	Look.text_left(self, Vector2(r.position.x + 20, r.position.y + 66),
			String(p["desc"]), 20, Look.INK)
	ui.button(self, Rect2(r.position.x + r.size.x - 170, r.position.y + 74, 150, 44),
			"%d G" % cost, "p:" + id, can, Look.GOLD, 24)
