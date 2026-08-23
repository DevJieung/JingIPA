extends Node2D
class_name BattleScreen

## 전투 화면. 계산은 전부 BattleSim 이 하고 여기서는 **그리기와 손가락만** 맡는다.
##
## 몬스터는 바깥 문으로 들어와 **벽으로 나뉜 길**을 돌아 안뜰의 크리스탈까지 걸어온다.
## 한 마리가 닿을 때마다 크리스탈이 하나 깨진다. 제한 시간은 없다.

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
## 방금 깨진 크리스탈이 번쩍이는 시간과 개수(보스는 다섯 개를 부순다).
var _crack_t: float = 0.0
var _crack_n: int = 1
## ★ 이번 프레임의 흔들림 오프셋. draw_set_transform 은 **덮어쓰기**라서,
##   그림자를 그리려고 잠깐 바꿨다가 Vector2.ZERO 로 되돌리면 흔들림이 사라진다.
##   되돌릴 때는 반드시 이 값으로 되돌린다. (예전에는 첫 배우 이후로 화면이 안 흔들렸다)
var _sh: Vector2 = Vector2.ZERO
## ★ Run.total_dps() 는 영웅마다 능력치와 무기를 매번 처음부터 곱해 센다. 전투 중에는
##   값이 바뀌지 않는데 매 프레임 부르면, 몬스터 60마리·이펙트 800개가 도는 바로 그
##   프레임에서 폰이 그 시간을 이 숫자 하나에 쓴다. 반 초에 한 번만 센다.
var _dps: float = 0.0
var _dps_t: float = 0.0


func _ready() -> void:
	sim.setup(Run, Run.wave)
	_dps = Run.total_dps()
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	_dps_t -= dt
	if _dps_t <= 0.0:
		_dps_t = 0.5
		_dps = Run.total_dps()
	if _crack_t > 0.0:
		_crack_t = max(0.0, _crack_t - dt)
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
		_drain()
		if not _settled:
			_settle()
		end_t += dt
		if end_t > 2.4:
			_leave()
	_tick_ghosts(sdt)
	fx.update(dt)
	queue_redraw()


func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if _leaving:
		return
	# ★ 결과 상자가 떠 있는 동안에는 어디를 눌러도 넘어간다. 배속 버튼이 결과 상자
	#   뒤에 그대로 살아 있으면, 거기를 누른 손가락은 아무 일도 안 일어난 것처럼 느낀다.
	if ended:
		if end_t > 0.6:
			_leave()
		return
	var id := ui.hit(e.position)
	if id.begins_with("sp"):
		speed = float(id.substr(2))
		return
	if id.begins_with("it:"):
		_use_item(id.substr(3))


## 아이템 한 개를 쓴다. 개수는 Run 이 줄이고 효과는 BattleSim 이 낸다.
func _use_item(iid: String) -> void:
	if sim.done or not sim.use_item(iid):
		return
	_drain()


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


## 전투가 끝났을 때의 정산. **한 번만** 한다.
##
## ★ 목숨(크리스탈)은 여기서 안 깎는다. 몬스터가 닿는 그 순간 BattleSim 이 이미 깎았다.
##   양쪽에서 깎으면 두 배로 깎인다 — 예전 규칙(시간이 끝나면 남은 수만큼)의 흔적이다.
func _settle() -> void:
	_settled = true
	ended = true
	_lost = sim.leaked
	# ★ 처치 수는 BattleSim 이 잡을 때마다 Run.kills 에 바로 올린다. 여기서 또 더하면 두 배다.
	_bonus = Balance.clear_bonus(Run.wave, sim.wiped)
	Run.add_gold(_bonus)
	if _lost > 0:
		fx.do_shake(12.0)
		fx.do_flash(Color(0.9, 0.1, 0.2, 0.4), 0.45)
	else:
		fx.do_flash(Color(1, 1, 1, 0.35), 0.3)
		fx.ring(Balance.ARENA_CENTER, Look.GOLD, 40.0, 460.0, 0.9, 8.0)


## 시뮬레이터가 남긴 사건을 이펙트로 바꾼다.
func _drain() -> void:
	for e in sim.events:
		var p: Vector2 = e.get("p", Vector2.ZERO)
		match String(e["t"]):
			"fire":
				# 총구 불꽃 — 누가 쐈는지가 보여야 화면이 살아 있다.
				var d: Vector2 = e.get("d", Vector2.RIGHT)
				var c0: Color = e.get("c", Look.GOLD)
				fx.beam(p + d * 6.0, p + d * 26.0, c0, 0.09, 5.0)
				fx.burst(p + d * 16.0, c0, 2, 90.0, 0.14, 2.6, 0.0)
			"hit":
				var hc: Color = e.get("c", Look.INK)
				var big: bool = bool(e.get("crit", false))
				fx.burst(p, hc, 10 if big else 6, 220.0, 0.28, 3.4, 0.0)
				fx.ring(p, Color(1, 1, 1, 1), 2.0, 26.0 if big else 17.0, 0.20, 3.0)
			"splash":
				fx.disc(p, e.get("c", Look.GOLD), float(e["r"]), 0.28, 0.26)
				fx.ring(p, e.get("c", Look.GOLD), 8.0, float(e["r"]), 0.32, 5.0)
			"beam":
				fx.beam(e["a"], e["b"], e.get("c", Look.BLUE), 0.20, 7.0)
			"bolt":
				fx.bolt(e["a"], e["b"], e.get("c", Look.BLUE), 0.24, 5.0)
			"die":
				var col: Color = e.get("c", Look.RED)
				var huge: bool = float(e.get("h", 50.0)) > 100.0
				fx.burst(p, col, 30 if huge else 14, 340.0 if huge else 220.0, 0.55, 3.6)
				fx.ring(p, col, 6.0, 76.0 if huge else 38.0, 0.34, 3.5)
				if huge:
					fx.do_shake(9.0)
					fx.do_flash(Color(1, 0.9, 0.5, 0.4), 0.3)
					fx.sprite(p, Roster.ART.get("boom", ""), 1.6, 0.55)
				fx.float_text(p + Vector2(0, -22), "+%d" % int(e.get("gold", 0)), Look.GOLD, 20)
			"leak":
				# 크리스탈이 깨진다 — 이 게임에서 제일 아픈 순간이라 크게 친다.
				# 보스는 한 번에 다섯 개를 부수므로 그만큼 여러 개가 터진다.
				var n_break: int = maxi(1, int(e.get("n", 1)))
				var top: int = int(e.get("i", 0))
				for k in range(n_break):
					var cp: Vector2 = Balance.ARENA_CENTER \
							+ Balance.crystal_slot(maxi(0, top - k))
					fx.burst(cp, Look.CRYSTAL, 22, 300.0, 0.6, 4.0, 380.0)
					fx.ring(cp, Look.CRYSTAL, 4.0, 90.0, 0.45, 5.0)
				var cp0: Vector2 = Balance.ARENA_CENTER + Balance.crystal_slot(top)
				fx.beam(p, cp0, Look.RED, 0.3, 6.0)
				fx.float_text(cp0 + Vector2(0, -40),
						"크리스탈 깨짐" if n_break == 1 else "크리스탈 %d개 깨짐" % n_break,
						Look.RED, 22, 1.0)
				fx.do_shake(10.0 + 4.0 * float(n_break))
				fx.do_flash(Color(0.9, 0.15, 0.25, 0.30), 0.28)
				_crack_t = 0.6
			"life":
				fx.float_text(p + Vector2(0, -46), "크리스탈 +1", Look.CRYSTAL, 24, 1.1)
			"curse":
				fx.bolt(p, Balance.ARENA_CENTER, Look.PURPLE, 0.3, 6.0)
				fx.ring(Balance.ARENA_CENTER, Look.PURPLE, 20.0, 170.0, 0.5, 4.0)
			"aura":
				var ac: Color = e.get("c", Look.GOLD)
				fx.disc(p, ac, float(e["r"]), 0.26, 0.10)
				fx.ring(p, ac, float(e["r"]) * 0.80, float(e["r"]), 0.26, 3.0)
			"bomb":
				fx.do_flash(Color(0.6, 0.85, 1.0, 0.5), 0.35)
				fx.do_shake(14.0)
				fx.ring(Balance.ARENA_CENTER, Look.BLUE, 20.0, 360.0, 0.6, 10.0)
				for mo in sim.monsters:
					fx.bolt(Balance.ARENA_CENTER, BattleSim.mpos(mo), Look.BLUE, 0.3, 5.0)
			"frost":
				# 처음 얼어붙는 순간에만 온다(BattleSim._slow 참고). 조각이 튀고
				# 발밑으로 성에가 한 번 퍼진다.
				var fh: float = float(e.get("h", 50.0))
				fx.frost(p, 8, 80.0 + fh * 0.9, 0.5)
				fx.ring(p, Look.ICE, 3.0, fh * 0.75, 0.28, 3.0)
			"freeze":
				fx.do_flash(Color(0.6, 0.9, 1.0, 0.35), 0.3)
				fx.ring(Balance.ARENA_CENTER, Look.CRYSTAL, 20.0, 360.0, 0.7, 8.0)
				# ★ 고리 하나로는 "멈췄다"가 안 읽힌다. 길 위 **모두**가 그 자리에서
				#   얼어붙는 것이 이 아이템의 전부이므로 한 마리씩 얼려 보여 준다.
				for mo in sim.monsters:
					fx.frost(BattleSim.mpos(mo), 6, 70.0, 0.6)
			"rally":
				fx.do_flash(Color(1.0, 0.85, 0.3, 0.3), 0.3)
				fx.ring(Balance.ARENA_CENTER, Look.GOLD, 20.0, 240.0, 0.6, 8.0)
			"repair":
				fx.ring(Balance.ARENA_CENTER, Look.CRYSTAL, 10.0, 140.0, 0.6, 6.0)
				fx.float_text(Balance.ARENA_CENTER + Vector2(0, -110),
						"크리스탈 수리", Look.CRYSTAL, 26, 1.1)
			"crit":
				fx.float_text(p + Vector2(0, -30), "%d" % int(e.get("n", 0)), Look.GOLD, 22, 0.6)
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
	_draw_altar()
	fx.draw_back(self)
	_draw_actors()
	_draw_hp_bars()
	# ★ 크리스탈은 배우들보다 **나중에** 그린다. 안뜰에 여섯이 서면 그림이 제단 위를
	#   덮는다. 목숨이 몇 개 남았는지가 안 보이는 디펜스 게임은 성립하지 않는다.
	#   (영웅이 스물넷까지 서던 시절 24탄 사진에서는 하나도 안 보였다)
	_draw_crystals()
	_draw_hero_tags()
	_draw_bullets()
	fx.draw(self)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_panel()
	_draw_topbar()
	_draw_boss_bar()
	if ended:
		_draw_result()
	fx.draw_flash(self, Rect2(0, 0, 1280, 800))


func _draw_bg() -> void:
	if not Art.draw_fill(self, Roster.ART.get("arena_bg", ""), Rect2(0, 0, 1280, 800),
			Color(0.42, 0.42, 0.52)):
		draw_rect(Rect2(0, 0, 1280, 800), Look.BG)


## 투기장 — 벽 세 겹, 그 사이의 길 두 겹, 가운데 안뜰.
##
## ★ 여기가 이 게임에서 제일 중요한 그림이다. "몬스터가 어디로 오는가"가 한눈에
##   안 보이면 플레이어는 무엇을 막고 있는지도 모른 채 목숨만 잃는다.
func _draw_arena() -> void:
	var c := Balance.ARENA_CENTER
	var r_out: float = Balance.WALL_R[0]
	var r_in: float = Balance.WALL_R[Balance.WALL_R.size() - 1]

	# 바닥 그림(있으면) → 그 위에 길과 안뜰을 색으로 나눈다.
	var tex := Art.tex(Roster.ART.get("arena_floor", ""))
	if tex != null:
		var d := r_out * 2.0
		draw_texture_rect(tex, Rect2(c - Vector2(r_out, r_out), Vector2(d, d)), false,
				Color(0.55, 0.55, 0.62))
	else:
		draw_circle(c, r_out, Look.LANE_EDGE)
	# ★ 길만 어둡게 누르는 방법: 원 전체를 어둡게 덮고 **안뜰을 다시 밝게** 그린다.
	#   두꺼운 draw_arc 로 띠를 그리면 96조각 폴리라인의 이음매가 톱니로 보인다.
	draw_circle(c, r_out, Color(0.05, 0.03, 0.10, 0.58))
	# 안뜰 — 영웅이 선 초록 천.
	draw_circle(c, r_in, Color(Look.YARD.r, Look.YARD.g, Look.YARD.b, 0.90))
	draw_arc(c, r_in - 3.0, 0.0, TAU, 72, Color(1, 1, 1, 0.06), 2.0, true)

	# 길 한가운데 점선과, 걷는 쪽을 가리키는 화살표
	for i in range(Balance.LANE_R.size()):
		var lr: float = Balance.LANE_R[i]
		draw_arc(c, lr, 0.0, TAU, 96, Color(1, 1, 1, 0.055), 2.0, true)
		_draw_chevrons(c, lr, i)

	# 벽 — 문 자리를 비운 두꺼운 호
	for i in range(Balance.WALL_R.size()):
		_draw_wall(c, Balance.WALL_R[i], Balance.GATE_A[i], i == Balance.WALL_R.size() - 1)

	# 바깥 문 앞의 등장 지점
	var ep: Vector2 = c + Vector2(cos(Balance.GATE_A[0]), sin(Balance.GATE_A[0])) * Balance.SPAWN_R
	var pulse: float = 0.35 + 0.25 * sin(t * 3.0)
	draw_circle(ep, 20.0, Color(Look.RED.r, Look.RED.g, Look.RED.b, pulse * 0.5))
	draw_circle(ep, 11.0, Color(Look.RED.r, Look.RED.g, Look.RED.b, 0.8))
	Look.text_center(self, ep + Vector2(0, -34), "몬스터", 16, Look.RED)


## 벽 하나. gate 각도만큼은 비우고, 그 양옆에 문기둥을 세운다.
func _draw_wall(c: Vector2, r: float, gate: float, is_core: bool) -> void:
	var w: float = 14.0 if is_core else 11.0
	var a0: float = gate + Balance.GATE_HALF
	var a1: float = gate + TAU - Balance.GATE_HALF
	var seg: int = 84
	draw_arc(c, r, a0, a1, seg, Look.WALL_DARK, w + 5.0, true)
	draw_arc(c, r, a0, a1, seg, Look.WALL, w, true)
	draw_arc(c, r - w * 0.34, a0, a1, seg, Look.WALL_TOP, w * 0.30, true)
	# 문기둥 둘 — 여기가 뚫린 곳이라는 표시
	for a in [a0, a1]:
		var p := c + Vector2(cos(a), sin(a)) * r
		draw_circle(p, w * 0.62, Look.WALL_TOP)
		draw_circle(p, w * 0.34, Look.GATE)
	# 문지방 — 지나가는 자리를 금색 선으로 긋는다
	var g0 := c + Vector2(cos(a1), sin(a1)) * r
	var g1 := c + Vector2(cos(a0 + TAU), sin(a0 + TAU)) * r
	draw_line(g0, g1, Color(Look.GATE.r, Look.GATE.g, Look.GATE.b, 0.35), 3.0, true)


## 길 위에 걷는 쪽을 가리키는 화살표를 뿌린다. 천천히 흘러가게 해서 방향이 읽히게.
func _draw_chevrons(c: Vector2, r: float, lane: int) -> void:
	var n := 22
	var flow: float = fmod(t * 0.22, 1.0) * TAU / float(n)
	var col := Color(Look.GATE.r, Look.GATE.g, Look.GATE.b, 0.20)
	for i in range(n):
		var a: float = TAU * float(i) / float(n) + flow + float(lane) * 0.1
		var p := c + Vector2(cos(a), sin(a)) * r
		# 걷는 쪽(각도가 커지는 쪽)의 접선
		var dir := Vector2(-sin(a), cos(a))
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			p + dir * 9.0, p - dir * 5.0 + side * 7.0, p - dir * 5.0 - side * 7.0]), col)


## 제단 바닥. 배우들 **아래**에 깔린다.
func _draw_altar() -> void:
	var c := Balance.ARENA_CENTER
	draw_circle(c, Balance.ALTAR_R + 10.0, Color(0, 0, 0, 0.45))
	draw_circle(c, Balance.ALTAR_R + 4.0, Color(0.10, 0.16, 0.22, 0.85))
	draw_arc(c, Balance.ALTAR_R + 4.0, 0.0, TAU, 56, Color(Look.CRYSTAL.r, Look.CRYSTAL.g,
			Look.CRYSTAL.b, 0.30), 2.0, true)


## 크리스탈 제단 — 목숨이 곧 여기 놓인 크리스탈 개수다.
func _draw_crystals() -> void:
	var c := Balance.ARENA_CENTER
	# 배우 위에 그리므로, 크리스탈이 뜬 것처럼 보이지 않게 그늘을 한 번 깐다.
	draw_circle(c, Balance.ALTAR_R + 2.0, Color(0.04, 0.06, 0.10, 0.55))
	var mx: int = Run.max_lives()
	var alive: int = Run.lives
	for i in range(mx):
		var p: Vector2 = c + Balance.crystal_slot(i)
		var on: bool = i < alive
		var glow := 0.0
		if on and i == alive - 1:
			# 다음에 깨질 놈이 숨 쉬듯 빛난다 — 위험을 눈으로 알려 준다.
			glow = 0.5 + 0.5 * sin(t * 4.0)
		if _crack_t > 0.0 and i >= alive and i < alive + _crack_n:
			glow = _crack_t / 0.6
		Look.draw_crystal(self, p, 10.0, on, glow)


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
	var h: Dictionary = he["h"]
	var u: Dictionary = h["unit"]
	var pos: Vector2 = he["pos"]
	var dh: float = Art.unit_h(u, sc)
	# 발밑 그림자 — 이게 없으면 캐릭터가 바닥에 안 붙고 떠 보인다.
	# ★ 크기는 그려지는 키에 맞춘다. 22px 로 고정해 두면 큰 영웅은 발끝만 그늘지고
	#   작은 영웅은 그늘 위에 올라선 것처럼 보인다.
	draw_set_transform(pos + _sh, 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, dh * 0.22, Color(0, 0, 0, 0.35))
	draw_set_transform(_sh, 0.0, Vector2.ONE)
	var bob := sin(t * 3.0 + pos.x * 0.05) * 2.0
	Art.draw_unit(self, u, pos.x, pos.y + bob, sc)


## 겹친 영웅의 「n겹」 표. **크리스탈보다 나중에** 그린다 —
## ★ 영웅과 같이 그렸더니 제단 쪽에 선 영웅의 표가 크리스탈에 통째로 가려졌다.
##   몇 겹인지가 안 보이면 "같은 애가 또 나왔는데 아무 일도 안 일어났다"가 된다.
func _draw_hero_tags() -> void:
	var sc := Balance.hero_scale(sim.heroes.size())
	for he in sim.heroes:
		var n: int = int(he["h"].get("n", 1))
		if n <= 1:
			continue
		var pos: Vector2 = he["pos"]
		var dh: float = Art.unit_h(he["h"]["unit"], sc)
		Look.text_center_out(self, Vector2(pos.x, pos.y - dh - 10.0), "%d겹" % n,
				21, Look.GOLD, Look.BG_DEEP, 3.0)


func _draw_monster(mo: Dictionary) -> void:
	var p := BattleSim.mpos(mo)
	var m: Dictionary = mo["m"]
	var mh: float = float(mo["h"])
	var col := Color(String(m.get("color", "#ffffff")))
	var flash: float = float(mo["flash"])
	var mod := Color.WHITE.lerp(Color(2.2, 1.6, 1.6), flash)
	var ice: float = _frost_k(mo)
	if ice > 0.01:
		# 얼음이 짙은 만큼 몸이 식어 파래진다.
		mod = mod * Color.WHITE.lerp(Color(0.60, 0.84, 1.45), ice)
	# ★ 그림자는 **발밑**에 와야 한다. 스프라이트는 p.y + 0.30h 를 바닥선으로 그리는데
	#   그림자만 p.y 에 두면 발보다 0.30h 위에 깔려 스프라이트 뒤에 통째로 가려진다.
	var foot: float = p.y + mh * 0.30
	draw_set_transform(Vector2(p.x, foot) + _sh, 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, mh * 0.26, Color(0, 0, 0, 0.34))
	draw_set_transform(_sh, 0.0, Vector2.ONE)
	# 성에와 **뒤쪽** 얼음 기둥을 먼저 깔고, 스프라이트를 얹고, **앞쪽** 기둥을 그 위에
	# 세운다. 전부 앞에 그리면 얼굴이 통째로 가려져서 무슨 몬스터인지 안 보인다 —
	# 느려진 걸 보여 주려다 정체를 지우는 셈이다.
	if ice > 0.01:
		_draw_frost_floor(p, foot, mh, ice)
		_draw_frost_spikes(p, foot, mh, ice, false)
	Art.draw_actor(self, String(m.get("art", "")), col, mh,
			p.x, foot, 1.0, mod)
	if ice > 0.01:
		# 성에가 낀 겉면 — 같은 그림을 얼음빛으로 한 겹 얇게 덧씌운다.
		# ★ 도형을 더 그리는 것보다 이 **한 번**이 훨씬 또렷하고 싸다(텍스처 한 장).
		#   물만 들여서는 "파란 몬스터"로 읽히지 "얼어붙은 몬스터"로는 안 읽혔다.
		Art.draw_actor(self, String(m.get("art", "")), col, mh, p.x, foot, 1.0,
				Color(0.74, 0.94, 1.35, 0.36 * ice))
		_draw_frost_spikes(p, foot, mh, ice, true)
		_draw_frost_glint(p, foot, mh, ice)
	if float(mo["burn_t"]) > 0.0:
		draw_circle(p + Vector2(0, -mh * 0.2), 5.0,
				Color(1.0, 0.5, 0.1, 0.7 + 0.3 * sin(t * 22.0)))


# --------------------------------------------------------------------------- #
# 얼음 — 둔화에 걸린 몬스터
# --------------------------------------------------------------------------- #
## 지금 이 몬스터가 얼마나 얼어 있는가 (0~1).
##
## ★ 남은 시간과 **둔화의 세기**를 함께 담는다. 세기만 보면 0.15 짜리 약한 둔화도
##   0.30 짜리와 똑같이 새하얘지고, 시간만 보면 다 끝나는 순간까지 그대로 있다가
##   툭 사라진다. 둘을 곱해야 "약하게 걸렸다 / 이제 풀린다"가 눈으로 읽힌다.
func _frost_k(mo: Dictionary) -> float:
	# 「시간 정지」 동안에는 길 위 **모두**가 통째로 얼어붙는다.
	if sim.freeze_t > 0.0:
		return 1.0
	var st: float = float(mo["slow_t"])
	if st <= 0.0:
		return 0.0
	var pw: float = clampf(float(mo["slow"]) / 0.30, 0.55, 1.0)
	return pw * clampf(st / 0.6, 0.0, 1.0)


## 발밑에 깔리는 성에. 바닥에 눕혀 그리므로 그림자와 같은 눌린 원을 쓴다.
## ★ 테두리 선(draw_arc)으로 그렸더니 어두운 길 위에서 통째로 묻혔다. 채운 원 두 겹이
##   훨씬 또렷하다 — 바깥은 짙게, 안쪽은 희게.
func _draw_frost_floor(p: Vector2, foot: float, mh: float, k: float) -> void:
	var r: float = mh * (0.36 + 0.14 * k)
	draw_set_transform(Vector2(p.x, foot) + _sh, 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, r,
			Color(Look.ICE_DEEP.r, Look.ICE_DEEP.g, Look.ICE_DEEP.b, 0.62 * k))
	draw_circle(Vector2.ZERO, r * 0.58,
			Color(Look.ICE.r, Look.ICE.g, Look.ICE.b, 0.50 * k))
	draw_set_transform(_sh, 0.0, Vector2.ONE)


## 발밑을 빙 둘러 돋은 얼음 기둥. front 가 참이면 발 **앞쪽** 것만 그린다.
##
## ★ 몸 한가운데에 세우면 스프라이트에 통째로 가려져 아무것도 안 보인다 — 처음에 그렇게
##   짰다가 사진에서 얼음이 한 조각도 안 보여 알았다. **발밑 고리 위**에 세워야 옆으로
##   삐져나오고, 앞쪽 것은 다리만 가려서 얼굴이 안 지워진다.
## ★ 자리는 좌표를 씨앗 삼아 고정한다. 매 프레임 새로 뽑으면 얼음이 부글부글 끓어서
##   얼음이 아니라 잡음으로 보인다.
## ★ 몬스터가 많으면 기둥 수를 줄인다. 「시간 정지」는 길 위 **모두**를 얼리는데,
##   예순 마리 × 다섯 기둥이면 한 프레임에 도형이 육백 개다.
func _draw_frost_spikes(p: Vector2, foot: float, mh: float, k: float, front: bool) -> void:
	var n: int = 3 if sim.monsters.size() > 24 else 5
	# ★ 반지름을 스프라이트 폭(약 0.62h)의 절반보다 **넉넉히 밖**으로 잡는다.
	#   0.40h 로 뒀더니 기둥이 몸에 파묻혀 다섯 중 하나만 보였다(사진으로 확인).
	var rx: float = mh * 0.46
	var seed_a: float = p.x * 0.011 + p.y * 0.007
	for i in range(n):
		var a: float = TAU * float(i) / float(n) + seed_a
		# sin(a) > 0 이면 발 앞쪽(화면에서 아래)이다.
		if (sin(a) > 0.0) != front:
			continue
		var c := Vector2(p.x + cos(a) * rx, foot + sin(a) * rx * 0.34)
		var hgt: float = mh * (0.32 + 0.16 * absf(cos(a))) * k
		# ★ 0 으로 줄어든 도형을 넘기면 triangulation failed 가 프레임마다 쏟아진다.
		if hgt < 3.0:
			continue
		_ice_spike(c, hgt * 0.34, hgt, 0.70 + 0.28 * k)


## 얼음 기둥 하나. 짙은 몸과 **왼쪽 밝은 면** 두 조각으로 그린다 —
## 이 한 조각이 있어야 납작한 삼각형이 아니라 결정으로 보인다(Look.draw_crystal 과 같은 수법).
func _ice_spike(c: Vector2, w: float, h: float, al: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -h), c + Vector2(w, -h * 0.34), c + Vector2(w * 0.60, 0),
		c + Vector2(-w * 0.60, 0), c + Vector2(-w, -h * 0.34)]),
		Color(Look.ICE_DEEP.r, Look.ICE_DEEP.g, Look.ICE_DEEP.b, al))
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -h), c + Vector2(0, 0), c + Vector2(-w * 0.60, 0),
		c + Vector2(-w, -h * 0.34)]),
		Color(Look.ICE.r, Look.ICE.g, Look.ICE.b, al))


## 몸 위에서 반짝이는 빛. 스프라이트 **앞**에 그리는 유일한 얼음이라 아주 작게만 둔다.
func _draw_frost_glint(p: Vector2, foot: float, mh: float, k: float) -> void:
	var sp: float = 2.2 + 2.0 * k * (0.6 + 0.4 * sin(t * 5.0 + p.x * 0.05))
	if sp < 0.7:
		return
	var c := Vector2(p.x + mh * 0.16, foot - mh * 0.62)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -sp * 1.7), c + Vector2(sp * 0.6, 0),
		c + Vector2(0, sp * 1.7), c + Vector2(-sp * 0.6, 0)]),
		Color(1, 1, 1, 0.55 + 0.35 * k))


# --------------------------------------------------------------------------- #
# 체력 게이지
# --------------------------------------------------------------------------- #
## 체력 막대의 **잔상**을 굴린다. 한 대 맞은 순간 얼마나 깎였는지가 흰 띠로 남았다가
## 뒤늦게 따라 내려온다 — 이게 없으면 큰 한 방과 잔 매질이 똑같아 보인다.
##
## ★ 잔상은 **화면만의 값**이다. BattleSim 은 그리기를 모르므로 여기서 몬스터 딕셔너리에
##   ghost 키를 얹는다. 헤드리스 검사(balance_check)는 이 함수를 아예 안 부르니
##   계산은 한 톨도 달라지지 않는다.
## ★ 배속(sdt)으로 굴린다. 실제 시간으로 굴리면 3배속에서 잔상이 화면에 늘 붙어 있다.
func _tick_ghosts(sdt: float) -> void:
	for mo in sim.monsters:
		var hp: float = clampf(float(mo["hp"]) / maxf(0.001, float(mo["max"])), 0.0, 1.0)
		var g: float = float(mo.get("ghost", hp))
		if g <= hp:
			g = hp
		else:
			# 크게 깎였을수록 빨리 따라온다. 늘 같은 속도로 두면 큰 한 방의 잔상이
			# 몇 초씩 남아 "아직 저만큼 있나" 하고 잘못 읽힌다.
			g = maxf(hp, g - sdt * maxf(0.28, (g - hp) * 2.4))
		mo["ghost"] = g


## 몬스터 체력 막대. **배우를 전부 그린 뒤 한 번에** 그린다.
##
## ★ 예전에는 몬스터를 그리면서 같이 그렸다. 그리는 차례가 y 순서라, 아래쪽 몬스터가
##   바로 위 몬스터의 막대를 덮었다 — 떼로 몰려오는 탄에서 정작 다친 놈의 막대가
##   가려졌다.
## ★ 크리스탈보다는 **먼저** 그린다. 크리스탈이 몇 개 남았는지가 언제나 우선이다.
## ★ 다치지 않은 놈도 그린다. 첫 탄에 아무 막대도 안 보이면 "체력이란 게 있구나"를
##   배울 자리가 없고, 육중(넓은 막대)과 쾌속(좁은 막대)이 한눈에 안 갈린다.
func _draw_hp_bars() -> void:
	for mo in sim.monsters:
		var mh: float = float(mo["h"])
		var p := BattleSim.mpos(mo)
		var hp: float = clampf(float(mo["hp"]) / maxf(0.001, float(mo["max"])), 0.0, 1.0)
		var ghost: float = clampf(float(mo.get("ghost", hp)), hp, 1.0)
		var w: float = clampf(mh * 0.80, 32.0, 86.0)
		var y: float = p.y - mh * 0.84
		# ★ 보스는 키가 132 라 바깥 길 꼭대기에 서면 머리 위 막대가 y≈10 이 된다. 아래로
		#   밀면 제 몸 위에 얹혀서 고장 난 것처럼 보이는데, 보스는 위쪽에 제 띠가 따로
		#   있으니(_draw_boss_bar) 그냥 접는다 — 잃는 정보가 없다.
		if String(mo["kind"]) == "boss":
			if y < 72.0:
				continue
		else:
			# ★ 바깥 길 맨 위(y≈99)에 선 몬스터는 막대가 y≈42 에 놓여 **위쪽 정보띠
			#   (y<68)에 통째로 가려진다.** 이쪽은 대신 보여 줄 곳이 없으니 밀어 내린다.
			y = maxf(72.0, y)
		_hp_bar(Rect2(p.x - w * 0.5, y, w, 7.0), hp, ghost)


## 막대 하나. ghost 는 방금 깎인 만큼을 남겨 둔 흰 띠다.
##
## ★ **draw_rect 만** 쓴다. 둥근 모서리(Look.fill_round)는 하나에 도형을 일곱 개 그려서,
##   몬스터가 예순 마리면 한 프레임에 사백 개가 된다. 7px 짜리 막대에서 둥근 끝은
##   어차피 보이지도 않는다.
func _hp_bar(r: Rect2, hp: float, ghost: float) -> void:
	# 어두운 길 위에서도 막대의 끝이 어디인지 보이게 테두리를 한 겹 깐다.
	draw_rect(Rect2(r.position - Vector2(1.5, 1.5), r.size + Vector2(3.0, 3.0)),
			Color(0, 0, 0, 0.72))
	draw_rect(r, Color(0.14, 0.12, 0.20, 0.95))
	if ghost > hp + 0.005:
		# ★ 흐릿한 흰빛으로 둔다. 진하게 두면 잔상이 남은 체력보다 밝아서, 반쯤 죽은
		#   몬스터가 멀쩡해 보인다(사진으로 확인했다).
		draw_rect(Rect2(r.position, Vector2(r.size.x * ghost, r.size.y)),
				Color(1.0, 0.98, 0.96, 0.42))
	if hp > 0.005:
		draw_rect(Rect2(r.position, Vector2(r.size.x * hp, r.size.y)), Look.hp_color(hp))
		# 윗면에 밝은 줄 하나 — 납작한 네모가 아니라 유리관처럼 보인다.
		draw_rect(Rect2(r.position + Vector2(0, 1.0),
				Vector2(r.size.x * hp, r.size.y * 0.28)), Color(1, 1, 1, 0.24))


## 보스 체력 띠. 위쪽 정보띠의 빈 자리에 크게 하나.
##
## ★ 왜 따로 두는가: 보스는 체력이 다른 몬스터의 열댓 배라, 머리 위 작은 막대로는
##   깎이고 있는지 아닌지가 안 읽힌다. 보스탄은 그 한 마리가 곧 그 탄이다.
## ★ 투기장 위가 아니라 **정보띠 안**에 둔다. 투기장 위쪽(y 80~120)은 바깥 길이라
##   거기에 띠를 얹으면 막 들어온 몬스터를 가린다.
func _draw_boss_bar() -> void:
	var boss: Dictionary = {}
	for mo in sim.monsters:
		if String(mo["kind"]) == "boss":
			boss = mo
			break
	if boss.is_empty():
		return
	var hp: float = clampf(float(boss["hp"]) / maxf(0.001, float(boss["max"])), 0.0, 1.0)
	var ghost: float = clampf(float(boss.get("ghost", hp)), hp, 1.0)
	var r := Rect2(596, 20, 656, 28)
	_hp_bar(r, hp, ghost)
	Look.text_center_out(self, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 14.0),
			"%s  %d%%" % [String(boss["m"].get("ko", "보스")), int(ceil(hp * 100.0))],
			20, Look.INK, Look.BG_DEEP, 2.0)


## 탄 — 꼬리와 빛무리를 함께 그린다.
## ★ 예전에는 반지름 5px 짜리 점 하나였다. 몬스터 그림 위에서 그냥 안 보였다.
func _draw_bullets() -> void:
	for b in sim.bullets:
		var col: Color = b["c"]
		var p: Vector2 = b["p"]
		var prev: Vector2 = b.get("prev", p)
		var back: Vector2 = Vector2(b["v"]).normalized()
		var kind := String(b["kind"])
		# 꼬리 — 지난 자리에서 지금 자리까지 길게 늘여 그린다.
		var tail: Vector2 = prev - back * 10.0
		draw_line(tail, p, Color(col.r, col.g, col.b, 0.30), 9.0, true)
		draw_line(tail, p, Color(col.r, col.g, col.b, 0.65), 4.0, true)
		match kind:
			"splash":
				draw_circle(p, 13.0, Color(col.r, col.g, col.b, 0.30))
				draw_circle(p, 8.0, col)
				draw_circle(p, 4.0, Color(1, 1, 1, 0.95))
			"pierce":
				var d: Vector2 = back * 16.0
				draw_line(p - d, p + d, Color(col.r, col.g, col.b, 0.35), 9.0, true)
				draw_line(p - d, p + d, col, 4.5, true)
				draw_line(p - d * 0.5, p + d, Color(1, 1, 1, 0.9), 2.0, true)
			_:
				draw_circle(p, 11.0, Color(col.r, col.g, col.b, 0.28))
				draw_circle(p, 6.0, col)
				draw_circle(p, 2.8, Color(1, 1, 1, 0.95))


func _draw_topbar() -> void:
	draw_rect(Rect2(0, 0, 1280, 68), Look.PANEL)
	draw_rect(Rect2(0, 66, 1280, 2), Look.PANEL_EDGE)
	Look.text_left(self, Vector2(28, 34), "%d탄" % Run.wave, 34, Look.INK)
	if Balance.is_boss_wave(Run.wave):
		Look.text_left(self, Vector2(120, 34), "보스", 26, Look.RED)
	Look.draw_crystal(self, Vector2(224, 34), 11.0, true)
	Look.text_left(self, Vector2(244, 34), "%d / %d" % [Run.lives, Run.max_lives()],
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

	# 크리스탈 — 남은 개수가 곧 목숨이다
	Look.text_left(self, Vector2(x + 20, 100), "크리스탈", 22, Look.INK_DIM)
	Look.text_right(self, Vector2(x + 20 + w, 100), "%d / %d" % [Run.lives, Run.max_lives()],
			26, Look.CRYSTAL if Run.lives > 5 else Look.RED)
	var mx: int = Run.max_lives()
	var per: int = mini(20, mx)
	var step: float = w / float(maxi(1, per))
	for i in range(mx):
		var row: int = i / per
		var cx: float = x + 20 + step * (float(i % per) + 0.5)
		Look.draw_crystal(self, Vector2(cx, 128.0 + float(row) * 22.0), 6.5, i < Run.lives)

	# 남은 몬스터 · 선두가 얼마나 왔나
	var left: int = sim.remaining()
	var ly: float = 128.0 + float((mx - 1) / per) * 22.0 + 36.0
	Look.text_left(self, Vector2(x + 20, ly), "남은 몬스터", 22, Look.INK_DIM)
	Look.text_right(self, Vector2(x + 20 + w, ly), "%d" % left, 30,
			Look.INK if left == 0 else Look.RED)

	var lead := 0.0
	for mo in sim.monsters:
		lead = max(lead, sim.progress(mo))
	Look.text_left(self, Vector2(x + 20, ly + 34), "선두가 온 만큼", 20, Look.INK_DIM)
	Look.fill_round(self, Rect2(x + 20, ly + 50, w, 16), 8.0, Look.BG_DEEP)
	if lead > 0.001:
		Look.fill_round(self, Rect2(x + 20, ly + 50, w * lead, 16), 8.0,
				Look.RED if lead > 0.72 else Look.GOLD)

	var dy: float = ly + 96.0
	Look.text_left(self, Vector2(x + 20, dy), "초당 피해", 22, Look.INK_DIM)
	Look.text_right(self, Vector2(x + 20 + w, dy), "%0.0f" % _dps, 24, Look.GREEN)

	# 배속
	Look.text_left(self, Vector2(x + 20, dy + 42), "배속", 20, Look.INK_DIM)
	for i in range(3):
		var s := float(i + 1)
		var r := Rect2(x + 90 + float(i) * 82.0, dy + 24.0, 74, 40)
		# ★ '×'(U+00D7) 는 번들 폰트에 없다. 한글로 쓴다.
		ui.button(self, r, "%d배" % int(s), "sp%d" % int(s), true,
				Look.GOLD if speed == s else Look.PANEL_EDGE, 22)

	var iy: float = dy + 86.0
	iy = _draw_items(x, iy, w)
	_draw_hero_list(x, iy, w)


## 가진 아이템 — 눌러서 쓴다.
##
## ★ 자리는 **표(Balance.ITEMS)의 순서로 고정**한다. 가진 것만 추려서 그리면, 하나를
##   다 쓰는 순간 뒤엣것이 그 자리로 올라온다 — 급하게 두 번 두드리면 두 번째 손가락이
##   엉뚱한 아이템(비싼 「시간 정지」)을 써 버린다. 없는 것은 자리만 두고 꺼 놓는다.
func _draw_items(x: float, y: float, w: float) -> float:
	var any := false
	for it in Balance.ITEMS:
		if Run.item_count(String(it["id"])) > 0:
			any = true
			break
	if not any:
		return y
	Look.text_left(self, Vector2(x + 20, y), "아이템", 20, Look.INK_DIM)
	Look.text_right(self, Vector2(x + 20 + w, y), "눌러서 쓴다", 16, Look.INK_DIM)
	var bw: float = (w - 10.0) * 0.5
	for i in range(Balance.ITEMS.size()):
		var it2: Dictionary = Balance.ITEMS[i]
		var id := String(it2["id"])
		var cnt: int = Run.item_count(id)
		var col: int = i % 2
		var row: int = i / 2
		var r := Rect2(x + 20 + float(col) * (bw + 10.0), y + 16.0 + float(row) * 54.0,
				bw, 46)
		# 「크리스탈 수리」는 꽉 찼을 때 눌러 봐야 140G 만 사라진다 — 그때는 꺼 둔다.
		ui.button(self, r, "%s %d" % [String(it2["ko"]), cnt], "it:" + id,
				sim.can_use_item(id), Look.CRYSTAL, 20)
	return y + 16.0 + float((Balance.ITEMS.size() + 1) / 2) * 54.0 + 14.0


## 안뜰에 선 영웅 목록. 여섯 자리뿐이라 **전부** 보여 준다 — 지금 누가 싸우고 있고
## 누가 몇 겹인지가 이 게임에서 제일 중요한 정보다.
func _draw_hero_list(x: float, y: float, w: float) -> void:
	Look.text_left(self, Vector2(x + 20, y), "안뜰 %d / %d"
			% [Run.heroes.size(), Balance.HERO_SLOTS], 22, Look.INK_DIM)
	if not Run.bench.is_empty():
		Look.text_right(self, Vector2(x + 20 + w, y), "대기 %d명" % Run.bench.size(),
				18, Look.INK_DIM)
	var row_y := y + 24.0
	for i in range(Run.heroes.size()):
		if row_y + 34.0 > 792.0:
			break
		var h: Dictionary = Run.heroes[i]
		var u: Dictionary = h["unit"]
		var tc := Look.tier_color(int(h["tier"]))
		var n: int = int(h.get("n", 1))
		Look.fill_round(self, Rect2(x + 20, row_y, w, 32), 6.0, Look.BG_DEEP)
		draw_rect(Rect2(x + 20, row_y, 6, 32), tc)
		Look.text_left(self, Vector2(x + 36, row_y + 16), String(u.get("ko", "")), 20, Look.INK)
		if n > 1:
			Look.text_right(self, Vector2(x + 20 + w - 8, row_y + 16),
					"%d겹" % n, 20, Look.GOLD)
		else:
			Look.text_right(self, Vector2(x + 20 + w - 8, row_y + 16),
					Roster.TIER_KO[int(h["tier"])], 16, tc)
		row_y += 36.0


func _draw_result() -> void:
	var a: float = clampf(end_t / 0.3, 0.0, 1.0)
	draw_rect(Rect2(0, 0, 1280, 800), Color(0, 0, 0, 0.55 * a))
	var box := Rect2(300, 250, 680, 300)
	Look.fill_round(self, box, 20.0, Look.PANEL)
	Look.fill_round(self, box.grow(-5.0), 16.0, Look.BG_DEEP)
	var cx := box.position.x + box.size.x * 0.5
	if sim.wiped:
		Look.text_center(self, Vector2(cx, 320), "완벽 방어!", 62, Look.GOLD)
		Look.text_center(self, Vector2(cx, 392), "%d마리를 하나도 안 놓쳤다" % sim.kills, 28, Look.INK)
	else:
		Look.text_center(self, Vector2(cx, 320), "돌파당했다", 58, Look.RED)
		Look.text_center(self, Vector2(cx, 392), "%d마리가 닿아 크리스탈 %d개가 깨졌다"
				% [sim.leak_n, _lost], 28, Look.RED)
	Look.text_center(self, Vector2(cx, 448), "잡은 수 %d  ·  번 골드 %dG  ·  보너스 %dG"
			% [sim.kills, sim.gold, _bonus], 24, Look.INK_DIM)
	Look.text_center(self, Vector2(cx, 508),
			"아무 데나 눌러 " + ("결과로" if Run.wave >= Balance.LAST_WAVE or not Run.running
			else "상점으로"), 20, Look.INK_DIM)
