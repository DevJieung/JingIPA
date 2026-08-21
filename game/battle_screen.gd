extends Node2D
class_name BattleScreen

## 전투 화면. 계산은 전부 BattleSim 이 하고 여기서는 **그리기와 손가락만** 맡는다.
##
## 몬스터는 바깥에서 나타나 영웅들 주위를 돌면서 안쪽으로 조여 온다.
## 제한 시간이 끝났을 때 **남아 있는 마릿수만큼 목숨이 깎인다.**

const PANEL_X := 830.0

var main = null
var ui := Ui.new()
var fx := Fx.new()
var sim := BattleSim.new()

var speed: float = 1.0
var t: float = 0.0
var end_t: float = 0.0
## 전투가 끝났는가(결과창을 그린다).
var ended: bool = false
## ★ 나가는 중인가. ended 하나로 둘을 겸하게 했더니, 탭해서 넘기는 순간 ended 가
##   false 가 되어 **결과 상자가 사라지고 빈 투기장이 0.28초 노출됐다.**
var _leaving: bool = false
var _settled: bool = false
var _lost: int = 0
var _bonus: int = 0
## ★ 이번 프레임의 흔들림 오프셋. draw_set_transform 은 **덮어쓰기**라서,
##   그림자를 그리려고 잠깐 바꿨다가 Vector2.ZERO 로 되돌리면 흔들림이 사라진다.
##   되돌릴 때는 반드시 이 값으로 되돌린다. (예전에는 첫 배우 이후로 화면이 안 흔들렸다)
var _sh: Vector2 = Vector2.ZERO


func _ready() -> void:
	sim.setup(Run, Run.wave)
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	var sdt: float = dt * speed
	if not sim.done:
		# ★ 배속을 걸어도 한 걸음이 너무 커지지 않게 잘라서 여러 번 돈다.
		#   한 프레임에 0.05초를 넘게 굴리면 빠른 탄이 몬스터를 통과해 버린다.
		var left := sdt
		var guard := 0
		while left > 0.0001 and guard < 16 and not sim.done:
			var step: float = min(0.02, left)
			sim.step(step)
			left -= step
			guard += 1
		_drain()
	else:
		if not _settled:
			_settle()
		end_t += dt
		if end_t > 2.4:
			_leave()
	fx.update(dt)
	queue_redraw()


func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if _leaving:
		return
	if ended and end_t > 0.6:
		_leave()
		return
	var id := ui.hit(e.position)
	if id.begins_with("sp"):
		speed = float(id.substr(2))


func _leave() -> void:
	if main == null or not ended or _leaving:
		return
	_leaving = true
	if not Run.running:
		main.go(main.go_over)
	elif Run.wave >= Balance.LAST_WAVE:
		# ★ 마지막 탄을 넘겼으면 상점을 건너뛴다. 뒤에 살 이유가 있는 탄이 없다.
		main.go(main.go_draw)
	else:
		main.go(main.go_shop)


## 시간이 끝났을 때의 정산. **한 번만** 한다.
func _settle() -> void:
	_settled = true
	ended = true
	_lost = sim.leaked
	Run.kills += sim.kills
	_bonus = Balance.clear_bonus(Run.wave, sim.wiped, sim.time_left)
	Run.add_gold(_bonus)
	if _lost > 0:
		fx.do_shake(14.0)
		fx.do_flash(Color(0.9, 0.1, 0.2, 0.5), 0.5)
		Run.add_lives(-_lost)     # ★ 여기서 목숨이 0 이 되면 Run 이 판을 끝낸다
	else:
		fx.do_flash(Color(1, 1, 1, 0.35), 0.3)
		fx.ring(Balance.ARENA_CENTER, Look.GOLD, 40.0, 460.0, 0.9, 8.0)


## 시뮬레이터가 남긴 사건을 이펙트로 바꾼다.
func _drain() -> void:
	for e in sim.events:
		var p: Vector2 = e.get("p", Vector2.ZERO)
		match String(e["t"]):
			"hit":
				fx.burst(p, e.get("c", Look.INK), 4, 130.0, 0.22, 2.4, 0.0)
			"splash":
				fx.ring(p, e.get("c", Look.GOLD), 8.0, float(e["r"]), 0.3, 4.0)
			"beam":
				fx.beam(e["a"], e["b"], e.get("c", Look.BLUE), 0.13, 5.0)
			"die":
				var col: Color = e.get("c", Look.RED)
				var big: bool = float(e.get("h", 50.0)) > 100.0
				fx.burst(p, col, 26 if big else 12, 320.0 if big else 200.0, 0.55, 3.4)
				fx.ring(p, col, 6.0, 70.0 if big else 34.0, 0.32, 3.0)
				if big:
					fx.do_shake(9.0)
					fx.do_flash(Color(1, 0.9, 0.5, 0.4), 0.3)
					fx.sprite(p, Roster.ART.get("boom", ""), 1.6, 0.55)
				fx.float_text(p + Vector2(0, -22), "+%d" % int(e.get("gold", 0)), Look.GOLD, 20)
			"life":
				fx.float_text(p + Vector2(0, -46), "목숨 +1", Look.RED, 24, 1.1)
			"curse":
				fx.beam(p, Balance.ARENA_CENTER, Look.PURPLE, 0.3, 6.0)
				fx.ring(Balance.ARENA_CENTER, Look.PURPLE, 20.0, 150.0, 0.5, 4.0)
			"aura":
				fx.ring(p, Look.GOLD, float(e["r"]) * 0.85, float(e["r"]), 0.25, 2.0)
	sim.events.clear()


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #
func _draw() -> void:
	ui.begin()
	_sh = fx.shake_offset()
	_draw_bg()
	draw_set_transform(_sh, 0.0, Vector2.ONE)
	_draw_arena()
	fx.draw_back(self)
	_draw_actors()
	_draw_bullets()
	fx.draw(self)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_panel()
	_draw_topbar()
	if ended:
		_draw_result()
	fx.draw_flash(self, Rect2(0, 0, 1280, 800))


func _draw_bg() -> void:
	if not Art.draw_fill(self, Roster.ART.get("arena_bg", ""), Rect2(0, 0, 1280, 800),
			Color(0.55, 0.55, 0.66)):
		draw_rect(Rect2(0, 0, 1280, 800), Look.BG)


func _draw_arena() -> void:
	var c := Balance.ARENA_CENTER
	var r := Balance.SPAWN_R
	var tex := Art.tex(Roster.ART.get("arena_floor", ""))
	if tex != null:
		var d := r * 2.0
		draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(d, d)), false,
				Color(0.85, 0.85, 0.9))
	else:
		draw_circle(c, r, Look.FELT_EDGE)
		draw_circle(c, r - 8.0, Look.FELT)
	# 몬스터가 도는 길과 더는 못 들어오는 안쪽 한계를 흐리게 보여 준다.
	draw_arc(c, r, 0.0, TAU, 72, Color(1, 1, 1, 0.10), 2.0, true)
	draw_arc(c, Balance.INNER_R, 0.0, TAU, 64, Color(1, 0.4, 0.4, 0.16), 2.0, true)


func _draw_actors() -> void:
	# 아래에 있는 것을 나중에 그려야 앞뒤가 맞다.
	var items: Array = []
	var n: int = sim.heroes.size()
	var hsc := Balance.hero_scale(n)
	for he in sim.heroes:
		items.append({"y": float(he["pos"].y), "kind": "h", "d": he})
	for mo in sim.monsters:
		items.append({"y": BattleSim.mpos(mo).y, "kind": "m", "d": mo})
	items.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))

	for it in items:
		if String(it["kind"]) == "h":
			_draw_hero(it["d"], hsc)
		else:
			_draw_monster(it["d"])


func _draw_hero(he: Dictionary, sc: float) -> void:
	var u: Dictionary = he["h"]["unit"]
	var pos: Vector2 = he["pos"]
	var col := Color(String(u.get("color", "#ffffff")))
	# 발밑 그림자 — 이게 없으면 캐릭터가 바닥에 안 붙고 떠 보인다.
	draw_set_transform(pos + _sh, 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, 22.0 * sc, Color(0, 0, 0, 0.35))
	draw_set_transform(_sh, 0.0, Vector2.ONE)
	var bob := sin(t * 3.0 + pos.x * 0.05) * 2.0
	Art.draw_actor(self, String(u.get("art", "")), col, float(u.get("h", 100)),
			pos.x, pos.y + bob, sc)


func _draw_monster(mo: Dictionary) -> void:
	var p := BattleSim.mpos(mo)
	var m: Dictionary = mo["m"]
	var col := Color(String(m.get("color", "#ffffff")))
	var flash: float = float(mo["flash"])
	var mod := Color.WHITE.lerp(Color(2.2, 1.6, 1.6), flash)
	if float(mo["slow_t"]) > 0.0:
		mod = mod * Color(0.72, 0.86, 1.25)
	# ★ 그림자는 **발밑**에 와야 한다. 스프라이트는 p.y + 0.30h 를 바닥선으로 그리는데
	#   그림자만 p.y 에 두면 발보다 0.30h 위에 깔려 스프라이트 뒤에 통째로 가려진다.
	var foot: float = p.y + float(mo["h"]) * 0.30
	draw_set_transform(Vector2(p.x, foot) + _sh, 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, float(mo["h"]) * 0.26, Color(0, 0, 0, 0.34))
	draw_set_transform(_sh, 0.0, Vector2.ONE)
	Art.draw_actor(self, String(m.get("art", "")), col, float(mo["h"]),
			p.x, foot, 1.0, mod)
	if float(mo["burn_t"]) > 0.0:
		draw_circle(p + Vector2(0, -float(mo["h"]) * 0.2), 5.0,
				Color(1.0, 0.5, 0.1, 0.7 + 0.3 * sin(t * 22.0)))
	# 체력 막대 — 다친 놈만.
	var hp: float = float(mo["hp"]) / max(1.0, float(mo["max"]))
	if hp < 0.999:
		var w: float = max(26.0, float(mo["h"]) * 0.6)
		var y: float = p.y - float(mo["h"]) * 0.78
		draw_rect(Rect2(p.x - w * 0.5 - 1.0, y - 1.0, w + 2.0, 7.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(p.x - w * 0.5, y, w * hp, 5.0),
				Look.GREEN if hp > 0.35 else Look.RED)


func _draw_bullets() -> void:
	for b in sim.bullets:
		var col: Color = b["c"]
		var p: Vector2 = b["p"]
		match String(b["kind"]):
			"splash":
				draw_circle(p, 8.0, col)
				draw_circle(p, 4.0, Color(1, 1, 1, 0.9))
			"pierce":
				var d: Vector2 = Vector2(b["v"]).normalized() * 13.0
				draw_line(p - d, p + d, col, 4.0, true)
			_:
				draw_circle(p, 5.0, col)
				draw_circle(p, 2.2, Color(1, 1, 1, 0.9))


func _draw_topbar() -> void:
	draw_rect(Rect2(0, 0, 1280, 68), Look.PANEL)
	draw_rect(Rect2(0, 66, 1280, 2), Look.PANEL_EDGE)
	Look.text_left(self, Vector2(28, 34), "%d탄" % Run.wave, 34, Look.INK)
	if Balance.is_boss_wave(Run.wave):
		Look.text_left(self, Vector2(120, 34), "보스", 26, Look.RED)
	var hx := 220.0
	if not Art.draw_at(self, Roster.ART.get("heart", ""), hx, 46.0):
		draw_circle(Vector2(hx, 34), 12.0, Look.RED)
	Look.text_left(self, Vector2(hx + 22, 34), "%d / %d" % [Run.lives, Run.max_lives()],
			28, Look.INK if Run.lives > 5 else Look.RED)
	var gx := 420.0
	if not Art.draw_at(self, Roster.ART.get("coin", ""), gx, 47.0):
		draw_circle(Vector2(gx, 34), 12.0, Look.GOLD)
	Look.text_left(self, Vector2(gx + 22, 34), "%d G" % Run.gold, 28, Look.GOLD)


func _draw_panel() -> void:
	var x := PANEL_X
	draw_rect(Rect2(x, 68, 1280 - x, 800 - 68), Look.PANEL)
	draw_rect(Rect2(x, 68, 2, 800 - 68), Look.PANEL_EDGE)
	var w := 1280.0 - x - 40.0

	# 남은 시간
	var k: float = sim.time_left / max(0.001, sim.total_time)
	Look.text_left(self, Vector2(x + 20, 106), "남은 시간", 22, Look.INK_DIM)
	Look.text_right(self, Vector2(x + 20 + w, 106), "%0.1f초" % sim.time_left, 26,
			Look.INK if k > 0.25 else Look.RED)
	Look.fill_round(self, Rect2(x + 20, 122, w, 18), 9.0, Look.BG_DEEP)
	Look.fill_round(self, Rect2(x + 20, 122, w * k, 18), 9.0,
			Look.GOLD if k > 0.25 else Look.RED)

	# 남은 몬스터 = 지금 시간이 끝나면 깎일 목숨
	var left: int = sim.remaining()
	Look.text_left(self, Vector2(x + 20, 176), "남은 몬스터", 22, Look.INK_DIM)
	Look.text_right(self, Vector2(x + 20 + w, 176), "%d" % left, 30,
			Look.INK if left == 0 else Look.RED)
	Look.text_left(self, Vector2(x + 20, 208), "시간이 끝나면 이만큼 목숨이 깎인다", 17, Look.INK_DIM)

	Look.text_left(self, Vector2(x + 20, 246), "초당 피해", 22, Look.INK_DIM)
	Look.text_right(self, Vector2(x + 20 + w, 246), "%0.0f" % Run.total_dps(), 24, Look.GREEN)

	# 배속
	Look.text_left(self, Vector2(x + 20, 288), "배속", 20, Look.INK_DIM)
	for i in range(3):
		var s := float(i + 1)
		var r := Rect2(x + 90 + float(i) * 82.0, 270, 74, 40)
		# ★ '×'(U+00D7) 는 번들 폰트에 없다. 한글로 쓴다.
		ui.button(self, r, "%d배" % int(s), "sp%d" % int(s), true,
				Look.GOLD if speed == s else Look.PANEL_EDGE, 22)

	# 영웅 목록 — 최근에 온 순서로. 40명이 되면 다 못 보여 주므로 뒤에서부터 자른다.
	Look.text_left(self, Vector2(x + 20, 342), "영웅 %d명" % Run.heroes.size(), 22, Look.INK_DIM)
	var y := 366.0
	var start: int = maxi(0, Run.heroes.size() - 11)
	for i in range(Run.heroes.size() - 1, start - 1, -1):
		var h: Dictionary = Run.heroes[i]
		var u: Dictionary = h["unit"]
		var tc := Look.tier_color(int(h["tier"]))
		Look.fill_round(self, Rect2(x + 20, y, w, 32), 6.0, Look.BG_DEEP)
		draw_rect(Rect2(x + 20, y, 6, 32), tc)
		Look.text_left(self, Vector2(x + 36, y + 16), String(u.get("ko", "")), 20, Look.INK)
		Look.text_right(self, Vector2(x + 20 + w - 8, y + 16),
				Roster.TIER_KO[int(h["tier"])], 16, tc)
		y += 36.0
	if start > 0:
		Look.text_left(self, Vector2(x + 20, y + 12), "… 그리고 %d명 더" % start, 18, Look.INK_DIM)


func _draw_result() -> void:
	var a: float = clampf(end_t / 0.3, 0.0, 1.0)
	draw_rect(Rect2(0, 0, 1280, 800), Color(0, 0, 0, 0.55 * a))
	var box := Rect2(300, 250, 680, 300)
	Look.fill_round(self, box, 20.0, Look.PANEL)
	Look.fill_round(self, box.grow(-5.0), 16.0, Look.BG_DEEP)
	var cx := box.position.x + box.size.x * 0.5
	if sim.wiped:
		Look.text_center(self, Vector2(cx, 320), "전멸!", 68, Look.GOLD)
		Look.text_center(self, Vector2(cx, 392), "%d마리를 모두 잡았다" % sim.kills, 28, Look.INK)
	else:
		Look.text_center(self, Vector2(cx, 320), "시간 끝", 62, Look.RED)
		Look.text_center(self, Vector2(cx, 392), "%d마리가 남아 목숨 %d 감소"
				% [_lost, _lost], 28, Look.RED)
	Look.text_center(self, Vector2(cx, 448), "잡은 수 %d  ·  번 골드 %dG  ·  보너스 %dG"
			% [sim.kills, sim.gold, _bonus], 24, Look.INK_DIM)
	Look.text_center(self, Vector2(cx, 508), "아무 데나 눌러 상점으로", 20, Look.INK_DIM)
