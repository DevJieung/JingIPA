extends Node2D
class_name ShopScreen

## 전투 사이의 능력치 강화, 패시브 관리와 영웅 편성.
## 패시브 보유 수에는 제한이 없으며 보유 목록에서 최대 세 개를 활성화한다.

const TABS := [
	{"id": "u", "ko": "능력치"},
	{"id": "p", "ko": "패시브"},
	{"id": "f", "ko": "전장 배치"},
	{"id": "i", "ko": "영웅 정보"},
	{"id": "h", "ko": "영웅 합성"},
]
const LIST_X := 40.0
const LIST_W := 700.0
const SIDE_X := 790.0
const SIDE_W := 450.0
const TOP_Y := 210.0
## 「다음 탄에 오는 몬스터」 줄. 탭(78~124) 바로 아래다.
## ★ TOP_Y 와 20px 는 벌려 둔다. 132/170 이었을 때 「내 패시브」 머리글이 이 줄을
##   반쯤 덮었다(사진으로 확인).
const MON_Y := 80.0

var main = null
var ui := Ui.new()
var formation := FormationView.new()
var hv := HeroView.new()
var hero_info_tab := false
var fusion := FusionView.new()
var fx := Fx.new()
var t: float = 0.0
var tab: String = "u"
var flash_id: String = ""
var flash_t: float = 0.0
## 보유 패시브는 여덟 장씩 페이지에 표시한다.
var passive_page: int = 0


func _ready() -> void:
	if Run.shop_offer.is_empty():
		Run.roll_shop()
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	fusion.update(dt)
	hv.update(dt)
	fx.update(dt)
	if flash_t > 0.0:
		flash_t = max(0.0, flash_t - dt)
	queue_redraw()


func _input(e: InputEvent) -> void:
	if hv.info >= 0:
		hv.input(e, ui)
		if hv.info < 0 and hv.sel >= 0:
			hero_info_tab = true
		return
	if Ads.busy or fusion.input(e, ui):
		return
	if tab == "f":
		if hero_info_tab and hv.input(e, ui):
			return
		if not hero_info_tab and formation.input(e, ui):
			return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var id := ui.hit(e.position)
	if id == "":
		return
	if id == "camp:map" or id == "camp:info":
		hero_info_tab = id == "camp:info"
		hv.sel = -1
		return
	if id == "next":
		Sfx.play("button")
		if main != null:
			main.go(main.go_draw)
		return
	if id.begins_with("tab:"):
		if id == "tab:h":
			fusion.opened = true
		else:
			var target := id.substr(4)
			if target in ["f", "i"]:
				tab = "f"
				hero_info_tab = target == "i"
				hv.sel = -1
			else:
				tab = target
		passive_page = 0
		Sfx.play("button")
		return
	if id.begins_with("u:"):
		var uid := id.substr(2)
		if Run.buy_upgrade(uid):
			_bought(uid, e.position)
	elif id.begins_with("p:"):
		_buy_passive(id.substr(2), e.position)
	elif id.begins_with("active:"):
		if Run.toggle_passive(id.substr(7)):
			Sfx.play("button")
	elif id == "passives:prev" or id == "passives:next":
		passive_page += -1 if id == "passives:prev" else 1


func _buy_passive(pid: String, at: Vector2) -> void:
	if Run.buy_passive(pid):
		_bought(pid, at)
		fx.do_flash(Color(1, 0.9, 0.5, 0.35), 0.3)


func _bought(id: String, at: Vector2) -> void:
	flash_id = id
	flash_t = 0.45
	Sfx.play("buy")
	fx.burst(at, Look.GOLD, 22, 260.0)
	fx.ring(at, Look.GOLD, 10.0, 90.0, 0.4, 4.0)


func _lit(id: String) -> float:
	return (flash_t / 0.45) if flash_id == id else 0.0


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #
func _draw() -> void:
	ui.begin()
	Look.camp_backdrop(self)
	# ★ **뒤 layer 를 여기서 한 번 그린다.** 고리(ring)는 Fx.BACK 이라 fx.draw() 로는
	#   절대 안 나온다 — 이 한 줄이 없어서 크리스탈을 되살 때 뜨는 고리가 수명만 살다
	#   조용히 사라졌다(CLAUDE.md 8: 빛살·고리는 draw_back).
	fx.draw_back(self)
	_draw_topbar()
	_draw_tabs()
	# ★ 어느 탭에서나 **다음 탄에 무엇이 오는지**를 보여 준다. 영웅 탭이 없어졌으니
	#   여기가 유일한 예고다 — 그것마저 없으면 상성은 다시 운이 된다.
	_draw_next_monsters()

	match tab:
		"f":
			if hero_info_tab:
				hv.draw(self, ui, Rect2(40, 184, 1200, 518), 6, false)
			else:
				formation.draw(self, ui, Rect2(40, 184, 1200, 518), t)
		"p":
			_draw_passives()
		_:
			_draw_upgrades()

	var last: bool = Run.wave >= Balance.LAST_WAVE and not Run.retry_wave
	var next_label := "결과 보기" if last else "%d탄으로" % Run.next_battle_wave()
	if Run.retry_wave:
		next_label = "%d탄 다시 도전" % Run.next_battle_wave()
	ui.button(self, Rect2(SIDE_X, 706, SIDE_W, 68),
			next_label, "next", not Run.retry_wave or not Run.heroes.is_empty(), Look.GOLD, 32)
	fx.draw(self)
	fx.draw_flash(self, Look.SCREEN)
	fusion.draw(self, ui)
	hv.draw_info(self, ui)


func _draw_topbar() -> void:
	Hud.topbar(self, "야영지", Look.INK if Run.lives > 5 else Look.RED)
	var nxt := "모든 탄 완료" if Run.wave >= Balance.LAST_WAVE \
			else "다음 %d탄" % Run.next_battle_wave()
	if Run.retry_wave:
		nxt = "%d탄 다시 도전" % Run.next_battle_wave()
	Look.text_box(self, Rect2(490, 12, Hud.MENU_RECT.position.x - 514, 44), nxt, Hud.INFO_SIZE, Look.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_tabs() -> void:
	var w := 142.0
	for i in range(TABS.size()):
		var d: Dictionary = TABS[i]
		var id := String(d["id"])
		var r := Rect2(LIST_X + float(i) * (w + 8.0), 128, w, 42)
		var on: bool = (id == "i" if hero_info_tab else id == "f") if tab == "f" else tab == id
		ui.tab(self, r, String(d["ko"]), "tab:" + id, on, 22)


## 다음 탄의 실제 몬스터와 각자의 속성.
func _draw_next_monsters() -> void:
	var w := Run.next_battle_wave()
	Hud.draw_lineup(self, Vector2(LIST_X, MON_Y + 17.0), "다음전투에 나올 몬스터",
			Run.wave_lineup(w))


# --------------------------------------------------------------------------- #
# 능력치
# --------------------------------------------------------------------------- #
func _draw_upgrades() -> void:
	var y := TOP_Y
	for u in Balance.UPGRADES:
		_draw_upgrade(u, Rect2(LIST_X, y, LIST_W, 56))
		y += 61.0
	_draw_owned(Rect2(SIDE_X, TOP_Y + 24.0, SIDE_W, 486.0), true)


func _draw_upgrade(u: Dictionary, r: Rect2) -> void:
	var id := String(u["id"])
	var level := Run.lv(id)
	var maxed := Balance.upgrade_maxed(id, level)
	var cost := Balance.upgrade_cost(id, level)
	var can := not maxed and Run.gold >= cost
	Look.material_panel(self, r, Look.PANEL.lerp(Look.GOLD, _lit(id) * 0.35), Look.PANEL_EDGE)
	draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Look.GOLD if can else Look.PANEL_EDGE)
	Look.text_center_fit(self, r.position + Vector2(128, 28), String(u["ko"]), 23, Look.INK, 226, 17)
	for column in range(2):
		var x := r.position.x + 251 + column * 116
		draw_rect(Rect2(x, r.position.y + 7, 110, 42), Look.BG_DEEP)
		Look.text_center(self, Vector2(x + 55, r.position.y + 16), "현재" if column == 0 else "다음", 13, Look.INK_DIM)
		var amount := float(Run.free_rerolls_at(level + column)) if id == "reroll" else Run.up_at(id, level + column)
		var value := Balance.upgrade_show(id, amount)
		if column == 1 and maxed:
			value = "최대"
		Look.text_center_fit(self, Vector2(x + 55, r.position.y + 36), value, 23,
				Look.INK_DIM if column == 1 and maxed else (Look.GOLD if column == 1 else Look.INK), 103, 17)
	ui.button(self, Rect2(r.position.x + 500, r.position.y + 6, 180, 44),
			"최대" if maxed else "%d G" % cost, "u:" + id, can,
			Look.PANEL_EDGE if maxed else Look.GOLD, 24)


# --------------------------------------------------------------------------- #
# 보유 패시브 / 활성 패시브 / 판매 목록
# --------------------------------------------------------------------------- #
func _draw_passives() -> void:
	Look.text_left(self, Vector2(LIST_X, 196), "보유 패시브", 25, Look.INK)
	Look.text_left(self, Vector2(SIDE_X, 196), "활성 패시브", 25, Look.CRYSTAL)
	Look.text_right(self, Vector2(1240, 196), "%d / %d" % [Run.passives.size(), Balance.PASSIVE_SLOTS], 21, Look.CRYSTAL)
	passive_page = clampi(passive_page, 0, maxi(0, (Run.owned_passives.size() - 1) / 8))
	for cell in range(8):
		var index := passive_page * 8 + cell
		if index >= Run.owned_passives.size():
			break
		var pid := String(Run.owned_passives[index])
		var p := Balance.passive_by_id(pid)
		var active := Run.passives.has(pid)
		var r := Rect2(LIST_X + (cell % 2) * 354, 218 + (cell / 2) * 107, 340, 99)
		_passive_row(r, p, active)
		ui.button(self, Rect2(r.end.x - 120, r.position.y + 9, 110, 32),
				"해제" if active else "활성화", "active:" + pid, active or not Run.passive_full(),
				Look.CRYSTAL if active else Look.PANEL_EDGE, 17)
	if Run.owned_passives.is_empty():
		Look.text_center(self, Vector2(390, 390), "보유 패시브가 없습니다", 23, Look.INK_DIM)
	if Run.owned_passives.size() > 8:
		ui.button(self, Rect2(LIST_X, 658, 100, 40), "이전", "passives:prev", passive_page > 0, Look.PANEL_EDGE, 20)
		Look.text_center(self, Vector2(388, 678), "%d / %d" % [passive_page + 1, ceili(Run.owned_passives.size() / 8.0)], 21, Look.INK_DIM)
		ui.button(self, Rect2(634, 658, 100, 40), "다음", "passives:next", (passive_page + 1) * 8 < Run.owned_passives.size(), Look.PANEL_EDGE, 20)
	for slot in range(Balance.PASSIVE_SLOTS):
		var r := Rect2(SIDE_X, 218 + slot * 48, SIDE_W, 42)
		Look.material_panel(self, r, Look.PANEL, Look.CRYSTAL_DEEP)
		if slot < Run.passives.size():
			var pid := String(Run.passives[slot])
			var p := Balance.passive_by_id(pid)
			Look.draw_passive_icon(self, r.position + Vector2(25, 21), 14, p, Color(p.get("tint", "#f6c445")))
			Look.text_box(self, Rect2(r.position + Vector2(50, 4), Vector2(r.size.x - 174, 34)), String(p.get("ko", "")), 21, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
			ui.button(self, Rect2(r.end.x - 116, r.position.y + 4, 110, 34), "해제", "active:" + pid, true, Look.PANEL_EDGE, 17)
		else:
			Look.text_center(self, r.get_center(), "빈 칸", 19, Look.INK_DIM)
	Look.text_left(self, Vector2(SIDE_X, 386), "판매 목록", 25, Look.INK)
	var offers := Run.offer_passives(3)
	for index in range(offers.size()):
		var p: Dictionary = offers[index]
		var pid := String(p["id"])
		var r := Rect2(SIDE_X, 406 + index * 97, SIDE_W, 89)
		_passive_row(r, p, false)
		ui.button(self, Rect2(r.end.x - 104, r.position.y + 8, 96, 34), "%d G" % int(p["cost"]),
				"p:" + pid, Run.gold >= int(p["cost"]), Look.GOLD, 19)
	if offers.is_empty():
		Look.text_center(self, Vector2(1015, 494), "모두 구매 완료", 23, Look.INK_DIM)


func _passive_row(r: Rect2, p: Dictionary, active: bool) -> void:
	var tint := Color(p.get("tint", "#f6c445"))
	Look.material_panel(self, r, Look.PANEL.lerp(tint, 0.05), Look.CRYSTAL if active else Look.PANEL_EDGE)
	Look.draw_passive_icon(self, r.position + Vector2(28, 27), 17, p, tint)
	HeroCard._text_left_fit(self, r.position + Vector2(53, 25), String(p.get("ko", "")), 19, tint, r.size.x - 181)
	var description := String(p.get("desc", ""))
	var desc_box := Rect2(r.position + Vector2(12, 46), Vector2(r.size.x - 24, r.size.y - 49))
	var font_size := 16
	while font_size > 12 and Look.wrapped_lines(description, desc_box.size.x, font_size).size() * Look.line_height(font_size) > desc_box.size.y:
		font_size -= 1
	Look.wrap_text(self, description, desc_box, font_size, Look.INK_DIM)


# --------------------------------------------------------------------------- #
# 오른쪽 — 적용 중인 패시브
# --------------------------------------------------------------------------- #
## 강화 화면 우측은 활성 패시브만 반영한 최종 능력치를 보여 준다.
func _draw_owned(box: Rect2, stats: bool = false) -> void:
	var plate := Rect2(box.position - Vector2(14, 18), Vector2(box.size.x + 28, 460 if stats else 232))
	Look.material_panel(self, plate, Look.PANEL, Look.PANEL_EDGE)
	var y: float = box.position.y
	Look.text_left(self, Vector2(box.position.x, y), "적용 중인 패시브", 24, Look.INK)
	y += 32.0
	if Run.passives.is_empty():
		Look.text_left(self, Vector2(box.position.x, y), "없음", 20, Look.INK_DIM)
		y += 28.0
	else:
		for pid in Run.passives:
			var p := Balance.passive_by_id(String(pid))
			var tint := Color(String(p.get("tint", "#f6c445")))
			Look.draw_passive_icon(self, Vector2(box.position.x + 13.0, y + 6.0), 11.0, p, tint)
			Look.text_left(self, Vector2(box.position.x + 30.0, y), String(p.get("ko", "")),
					21, tint)
			var desc := String(p.get("desc", ""))
			var desc_size := 15
			while desc_size > 12 and Look.text_width(desc, desc_size) > box.size.x - 30.0:
				desc_size -= 1
			Look.text_box(self, Rect2(box.position.x + 30, y + 10, box.size.x - 30, 24), desc, desc_size, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
			y += 46.0
	y += 10.0
	if not stats:
		return
	# ★ y 를 손으로 따라가 본 값이다. 패시브 셋(제일 긴 경우)이면
	#   208 → 240 → (46x3) 378 → 388 → 418 → 448 → 456(머리글) → 482 부터 26px 씩 여덟 줄,
	#   마지막 줄이 664 라 판(694)에도 「다음 탄」 단추(706)에도 안 닿는다.
	#   (30 은 바로 위 「전장 / 전당」 줄이 쓰는 몫이고, 8 이 그 아래 숨통이다.)
	y += 20.0
	Look.text_left(self, Vector2(box.position.x, y), "최종 능력치 (패시브 포함)", 20, Look.INK)
	y += 26.0
	for u in Balance.UPGRADES:
		var id := String(u["id"])
		HeroCard._text_left_fit(self, Vector2(box.position.x, y), String(u["ko"]), 20, Look.INK_DIM, box.size.x - 112)
		Look.text_right(self, Vector2(box.position.x + box.size.x, y),
				Balance.upgrade_show(id, Run.stat_now(id)), 21, Look.GREEN)
		y += 26.0
