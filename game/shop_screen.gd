extends Node2D
class_name ShopScreen

## 탄과 탄 사이의 상점. 잡은 몬스터로 번 골드를 여기서 쓴다.
##
## 네 갈래이고, 위쪽 탭으로 갈아 낀다:
##  - **능력치** 살수록 값이 오른다. 이 게임의 진짜 성장 곡선이 여기다.
##    (족보는 운이라 믿을 수 없다. 매 판 확실히 세지는 길이 하나는 있어야 한다.)
##  - **무기**   장착 칸이 셋뿐이라 무엇을 빼는가가 곧 선택이다. 절반 값에 되판다.
##  - **아이템** 사 두었다가 **전투 중에 눌러서** 쓴다.
##  - **패시브** 한 번만 사는 것. 매 판 셋만 내놓아서 판마다 다른 길이 열린다.
##  - **영웅**   안뜰 여섯 자리와 캐릭터 인벤토리. 여기가 「중간 정비」다 —
##    전투와 전투 사이에 누구를 세우고 누구를 물릴지 느긋하게 고른다.
##
## ★ 왜 탭인가: 다섯을 한 화면에 늘어놓으면 1280x800 에 글자가 18px 밑으로 내려간다.
##   폰에서 안 읽히는 상점은 없는 것과 같다.

const TABS := [
	{"id": "u", "ko": "능력치"},
	{"id": "w", "ko": "무기"},
	{"id": "i", "ko": "아이템"},
	{"id": "p", "ko": "패시브"},
	{"id": "h", "ko": "영웅"},
]
const LIST_X := 40.0
const LIST_W := 700.0
const SIDE_X := 790.0
const SIDE_W := 450.0
const TOP_Y := 136.0
## 「영웅」 탭에서 "다음 탄에 오는 몬스터" 줄이 놓이는 높이. 탭(78~124) 바로 아래다.
const MON_Y := 130.0

var main = null
var ui := Ui.new()
var fx := Fx.new()
## 영웅 탭의 편성 판. 뽑기 화면의 교체 창과 **같은 것**이다.
var hv := HeroView.new()
var t: float = 0.0
var tab: String = "u"
var offer: Array = []
var flash_id: String = ""
var flash_t: float = 0.0


func _ready() -> void:
	offer = Run.offer_passives(3)
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	fx.update(dt)
	hv.update(dt)
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
	if id.begins_with("tab:"):
		tab = id.substr(4)
		hv.sel = -1
		return
	if hv.tap(id):
		return
	# ★ "ws:" 를 "w:" 보다 **먼저** 본다. 순서를 바꾸면 무기를 빼려던 손가락이
	#   같은 무기를 다시 사려고 든다.
	if id.begins_with("ws:"):
		if Run.sell_weapon(id.substr(3)):
			_bought(id.substr(3), e.position)
	elif id.begins_with("u:"):
		var uid := id.substr(2)
		if Run.buy_upgrade(uid):
			_bought(uid, e.position)
	elif id.begins_with("w:"):
		var wid := id.substr(2)
		if Run.buy_weapon(wid):
			_bought(wid, e.position)
			fx.do_flash(Color(1, 0.9, 0.5, 0.3), 0.28)
	elif id.begins_with("i:"):
		var iid := id.substr(2)
		if Run.buy_item(iid):
			_bought(iid, e.position)
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


func _lit(id: String) -> float:
	return (flash_t / 0.45) if flash_id == id else 0.0


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #
func _draw() -> void:
	ui.begin()
	if not Art.draw_fill(self, Roster.ART.get("shop_bg", ""), Rect2(0, 0, 1280, 800),
			Color(0.42, 0.40, 0.5)):
		draw_rect(Rect2(0, 0, 1280, 800), Look.BG)
	draw_rect(Rect2(0, 0, 1280, 800), Color(Look.BG_DEEP.r, Look.BG_DEEP.g, Look.BG_DEEP.b, 0.62))
	_draw_topbar()
	_draw_tabs()

	match tab:
		"u":
			_draw_upgrades()
		"w":
			_draw_weapons()
		"i":
			_draw_items()
		"h":
			_draw_heroes()
		_:
			_draw_passives()
	# ★ 영웅 탭은 화면 폭을 전부 쓴다. 오른쪽의 「지금 가진 것」을 같이 그리면
	#   편성 칸이 그 위로 겹쳐 그려지고, 겹친 자리를 누르면 엉뚱한 것이 눌린다.
	if tab != "h":
		_draw_owned()

	var last: bool = Run.wave >= Balance.LAST_WAVE
	ui.button(self, Rect2(SIDE_X, 700, SIDE_W, 74),
			"결과 보기" if last else "%d탄으로" % (Run.wave + 1), "next", true, Look.GOLD, 32)
	fx.draw(self)
	fx.draw_flash(self, Rect2(0, 0, 1280, 800))


func _draw_topbar() -> void:
	draw_rect(Rect2(0, 0, 1280, 68), Look.PANEL)
	draw_rect(Rect2(0, 66, 1280, 2), Look.PANEL_EDGE)
	Look.text_left(self, Vector2(28, 34), "상점", 34, Look.INK)
	Look.draw_crystal(self, Vector2(224, 34), 11.0, true)
	Look.text_left(self, Vector2(244, 34), "%d / %d" % [Run.lives, Run.max_lives()], 28, Look.INK)
	var gx := 420.0
	if not Art.draw_at(self, Roster.ART.get("coin", ""), gx, 47.0):
		draw_circle(Vector2(gx, 34), 12.0, Look.GOLD)
	Look.text_left(self, Vector2(gx + 22, 34), "%d G" % Run.gold, 30, Look.GOLD)
	var nxt := "마지막 탄까지 끝났다" if Run.wave >= Balance.LAST_WAVE \
			else "다음은 %d탄" % (Run.wave + 1)
	Look.text_right(self, Vector2(1252, 34), nxt, 24, Look.INK_DIM)


func _draw_tabs() -> void:
	# ★ 탭 다섯 개가 SIDE_X(790) 를 넘어가면 안 된다. 넘어가면 각 탭이 오른쪽에 적는
	#   한 줄 설명("장착 3칸 …")이 탭 **뒤에** 깔려 통째로 안 보인다. 실제로 그랬다.
	var w := 140.0
	for i in range(TABS.size()):
		var d: Dictionary = TABS[i]
		var id := String(d["id"])
		var r := Rect2(LIST_X + float(i) * (w + 8.0), 78, w, 46)
		var on: bool = tab == id
		ui.button(self, r, String(d["ko"]), "tab:" + id, true,
				Look.GOLD if on else Look.PANEL_EDGE, 24)


func _draw_upgrades() -> void:
	Look.text_left(self, Vector2(SIDE_X, 100), "살수록 값이 오른다", 20, Look.INK_DIM)
	var y := TOP_Y
	for u in Balance.UPGRADES:
		_draw_upgrade(u, Rect2(LIST_X, y, LIST_W, 56))
		y += 61.0


func _draw_upgrade(u: Dictionary, r: Rect2) -> void:
	var id := String(u["id"])
	var l := Run.lv(id)
	var maxed := Balance.upgrade_maxed(id, l)
	var cost := Balance.upgrade_cost(id, l)
	var can := (not maxed) and Run.gold >= cost
	Look.fill_round(self, r, 10.0, Look.PANEL.lerp(Look.GOLD, _lit(id) * 0.35))
	draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Look.GOLD if can else Look.PANEL_EDGE)
	Look.text_left(self, Vector2(r.position.x + 18, r.position.y + 20),
			String(u["ko"]), 25, Look.INK)
	Look.text_left(self, Vector2(r.position.x + 18, r.position.y + 43),
			String(u["desc"]), 18, Look.INK_DIM)
	var cap := int(u["cap"])
	var lvtxt := "Lv %d" % l if cap == 0 else "Lv %d / %d" % [l, cap]
	Look.text_right(self, Vector2(r.position.x + 470, r.position.y + 30), lvtxt, 21, Look.INK_DIM)
	if maxed:
		ui.button(self, Rect2(r.position.x + 500, r.position.y + 6, 180, 44),
				"끝", "u:" + id, false, Look.PANEL_EDGE, 22)
	else:
		ui.button(self, Rect2(r.position.x + 500, r.position.y + 6, 180, 44),
				"%d G" % cost, "u:" + id, can, Look.GOLD, 24)


func _draw_weapons() -> void:
	Look.text_left(self, Vector2(SIDE_X, 100),
			"장착 %d칸 · 모든 영웅에게 걸린다" % Balance.WEAPON_SLOTS, 20, Look.INK_DIM)
	var y := TOP_Y
	for wp in Balance.WEAPONS:
		_draw_weapon(wp, Rect2(LIST_X, y, LIST_W, 56))
		y += 61.0


func _draw_weapon(wp: Dictionary, r: Rect2) -> void:
	var id := String(wp["id"])
	var cost := int(wp["cost"])
	var owned := Run.has_weapon(id)
	var can := (not owned) and (not Run.weapon_full()) and Run.gold >= cost
	Look.fill_round(self, r, 10.0, Look.PANEL.lerp(Look.GOLD, _lit(id) * 0.35))
	draw_rect(Rect2(r.position, Vector2(5, r.size.y)),
			Look.CRYSTAL if owned else (Look.GOLD if can else Look.PANEL_EDGE))
	Look.text_left(self, Vector2(r.position.x + 18, r.position.y + 20),
			String(wp["ko"]), 25, Look.CRYSTAL if owned else Look.INK)
	Look.text_left(self, Vector2(r.position.x + 18, r.position.y + 43),
			String(wp["desc"]), 18, Look.INK_DIM)
	if owned:
		ui.button(self, Rect2(r.position.x + 500, r.position.y + 6, 180, 44),
				"빼기 +%dG" % Balance.weapon_refund(id), "ws:" + id, true, Look.PANEL_EDGE, 20)
	elif Run.weapon_full():
		# ★ 값 버튼(x+500~x+680) **왼쪽**에 적는다. 버튼 위에 적으면 버튼이 나중에 그려져
		#   글자를 통째로 덮는다 — "왜 못 사는지"를 알려 주는 유일한 문구가 안 보였다.
		Look.text_right(self, Vector2(r.position.x + 486, r.position.y + 30),
				"칸이 찼다", 20, Look.INK_DIM)
		ui.button(self, Rect2(r.position.x + 500, r.position.y + 6, 180, 44),
				"%d G" % cost, "w:" + id, false, Look.GOLD, 22)
	else:
		ui.button(self, Rect2(r.position.x + 500, r.position.y + 6, 180, 44),
				"%d G" % cost, "w:" + id, can, Look.GOLD, 24)


func _draw_items() -> void:
	Look.text_left(self, Vector2(SIDE_X, 100), "전투 중에 눌러서 쓴다", 20, Look.INK_DIM)
	var y := TOP_Y
	for it in Balance.ITEMS:
		_draw_item(it, Rect2(LIST_X, y, LIST_W, 72))
		y += 82.0


func _draw_item(it: Dictionary, r: Rect2) -> void:
	var id := String(it["id"])
	var cost := int(it["cost"])
	var have := Run.item_count(id)
	var full := have >= Balance.ITEM_MAX
	var can := (not full) and Run.gold >= cost
	Look.fill_round(self, r, 12.0, Look.PANEL.lerp(Look.GOLD, _lit(id) * 0.35))
	draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Look.CRYSTAL if have > 0 else Look.PANEL_EDGE)
	Look.text_left(self, Vector2(r.position.x + 18, r.position.y + 24),
			String(it["ko"]), 27, Look.INK)
	Look.text_left(self, Vector2(r.position.x + 18, r.position.y + 50),
			String(it["desc"]), 19, Look.INK_DIM)
	Look.text_right(self, Vector2(r.position.x + 470, r.position.y + 36),
			"%d / %d" % [have, Balance.ITEM_MAX], 22,
			Look.CRYSTAL if have > 0 else Look.INK_DIM)
	ui.button(self, Rect2(r.position.x + 500, r.position.y + 14, 180, 44),
			"다 찼다" if full else "%d G" % cost, "i:" + id, can, Look.GOLD, 22)


## 「중간 정비」 — 안뜰 여섯 자리와 캐릭터 인벤토리.
func _draw_heroes() -> void:
	Look.text_left(self, Vector2(SIDE_X, 100),
			"같은 캐릭터가 또 나오면 겹쳐서 공격력이 배가 된다", 20, Look.INK_DIM)
	# ★ 몬스터 줄은 **탭 아래**에 깐다. 탭과 같은 높이(y 78~124)에 두었더니 탭 넷을
	#   통째로 덮어서 다른 탭으로 갈 수가 없었다(사진으로 확인). 그만큼 편성 판을 내린다.
	_draw_next_monsters()
	hv.draw(self, ui, Rect2(LIST_X, MON_Y + 34.0, 1240.0 - LIST_X, 680.0 - MON_Y - 34.0))


## 다음 탄에 **실제로 오는** 몬스터와 그놈이 무엇에 약한가.
##
## ★ 이 줄이 없으면 상성은 그냥 운이다. 안뜰 여섯을 다시 짜는 자리가 여기인데,
##   "다음에 무엇이 오는가"를 못 보면 누구를 세울지 고를 근거가 하나도 없다.
## ★ Run.wave_lineup() 은 씨앗으로 정해진 답이라 전투가 뽑는 것과 **정확히 같다.**
##   난수를 여기서 굴리면 화면이 거짓말을 한다.
func _draw_next_monsters() -> void:
	var w: int = mini(Run.wave + 1, Balance.LAST_WAVE)
	var pool: Array = Run.wave_lineup(w)
	var head: String = "%d탄에 오는 몬스터" % w
	var cy: float = MON_Y + 13.0
	Look.text_left(self, Vector2(LIST_X, cy), head, 19, Look.INK_DIM)
	var x: float = LIST_X + Look.text_width(head, 19) + 14.0
	for m in pool:
		var nm := String(m["ko"])
		var wk := Balance.body_weak(String(m.get("body", "null")))
		var cw: float = Look.text_width(nm, 18) + (32.0 if wk != "" else 14.0)
		# 자리가 모자라면 조용히 자른다. 넘쳐 그리면 화면 밖으로 흘러나간다.
		if x + cw > 1240.0 - 16.0:
			break
		Look.fill_round(self, Rect2(x, MON_Y, cw, 26), 8.0, Look.BG_DEEP)
		Look.text_left(self, Vector2(x + 7, cy), nm, 18, Look.INK)
		if wk != "":
			Look.draw_elem(self, Vector2(x + cw - 13.0, cy), 9.0, wk)
		x += cw + 7.0


func _draw_passives() -> void:
	Look.text_left(self, Vector2(SIDE_X, 100), "한 번만 산다", 20, Look.INK_DIM)
	var y := TOP_Y
	for p in offer:
		_draw_passive(p, Rect2(LIST_X, y, 560, 128))
		y += 140.0
	if offer.is_empty():
		Look.text_left(self, Vector2(LIST_X, TOP_Y + 40), "더 살 패시브가 없다", 24, Look.INK_DIM)


func _draw_passive(p: Dictionary, r: Rect2) -> void:
	var id := String(p["id"])
	var cost := int(p["cost"])
	var can := Run.gold >= cost
	Look.fill_round(self, r.grow(3.0), 14.0, Look.GOLD if can else Look.PANEL_EDGE)
	Look.fill_round(self, r, 12.0, Look.PANEL.lerp(Look.GOLD, _lit(id) * 0.35))
	Look.text_left(self, Vector2(r.position.x + 20, r.position.y + 30),
			String(p["ko"]), 30, Look.GOLD if can else Look.INK_DIM)
	Look.text_left(self, Vector2(r.position.x + 20, r.position.y + 66),
			String(p["desc"]), 20, Look.INK)
	ui.button(self, Rect2(r.position.x + r.size.x - 170, r.position.y + 74, 150, 44),
			"%d G" % cost, "p:" + id, can, Look.GOLD, 24)


## 오른쪽 — 지금 가진 것. 어느 탭에서든 늘 보인다.
func _draw_owned() -> void:
	var y := TOP_Y
	Look.text_left(self, Vector2(SIDE_X, y), "장착한 무기", 24, Look.INK)
	y += 26.0
	for i in range(Balance.WEAPON_SLOTS):
		var r := Rect2(SIDE_X, y, SIDE_W, 52)
		Look.fill_round(self, r, 10.0, Look.BG_DEEP)
		if i < Run.weapons.size():
			var wp := Balance.weapon_by_id(String(Run.weapons[i]))
			draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Look.CRYSTAL)
			Look.text_left(self, Vector2(SIDE_X + 16, y + 18), String(wp.get("ko", "?")),
					23, Look.CRYSTAL)
			Look.text_left(self, Vector2(SIDE_X + 16, y + 38), String(wp.get("desc", "")),
					17, Look.INK_DIM)
		else:
			Look.text_left(self, Vector2(SIDE_X + 16, y + 26), "빈 칸", 20, Look.INK_DIM)
		y += 58.0

	y += 12.0
	Look.text_left(self, Vector2(SIDE_X, y), "가진 아이템", 24, Look.INK)
	y += 30.0
	var owned := Run.item_list()
	if owned.is_empty():
		Look.text_left(self, Vector2(SIDE_X, y), "없다", 20, Look.INK_DIM)
		y += 26.0
	else:
		for it in owned:
			Look.text_left(self, Vector2(SIDE_X, y),
					"%s %d개" % [String(it["ko"]), Run.item_count(String(it["id"]))],
					20, Look.CRYSTAL)
			y += 26.0

	y += 14.0
	Look.text_left(self, Vector2(SIDE_X, y), "가진 패시브", 24, Look.INK)
	y += 30.0
	if Run.passives.is_empty():
		Look.text_left(self, Vector2(SIDE_X, y), "없다", 20, Look.INK_DIM)
		return
	var names: Array = []
	for p in Balance.PASSIVES:
		if Run.passives.has(p["id"]):
			names.append(String(p["ko"]))
	# 오른쪽 칸이 좁으니 세 개씩 끊어서 줄을 바꾼다.
	var line: Array = []
	for nm in names:
		line.append(nm)
		if line.size() == 3:
			Look.text_left(self, Vector2(SIDE_X, y), ", ".join(line), 19, Look.GOLD)
			y += 24.0
			line = []
	if not line.is_empty():
		Look.text_left(self, Vector2(SIDE_X, y), ", ".join(line), 19, Look.GOLD)
