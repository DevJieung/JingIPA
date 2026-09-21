extends Node2D
class_name BattleScreen

## 전투 화면. 계산은 전부 BattleSim 이 하고 여기서는 **그리기와 손가락만** 맡는다.
##
## 몬스터는 바깥 문으로 들어와 **벽으로 나뉜 길**을 돌아 전장의 크리스탈까지 걸어온다.
## 한 마리가 닿을 때마다 크리스탈이 하나 깨진다. 제한 시간은 없다.

const PANEL_X := 830.0

## 상성별 피해 세 토막 — 시뮬레이터의 통 이름 · 화면에 적는 말 · 색.
## ★ 셋이 **같은 차례**여야 한다. 흩어 놓으면 「반감 토막이 주황으로 차는」 판이 된다.
## ★ 세 토막은 **한 막대에 이어 붙는다**(_stack_bar). 자는 이번 탄 몬스터 체력의 합이다.
const DMG_KEYS := ["dw", "dn", "dr"]
const DMG_KO := ["2배", "보통", "반감"]
const DMG_COL := [Look.DMG_WEAK, Look.DMG_NORMAL, Look.DMG_RESIST]

var main = null
var ui := Ui.new()
var fx := Fx.new()
var area_fx := preload("res://game/area_fx.gd").new()
## ★ BattleSim 이 아니라 **DbgSim** 이다 — 디버그 오버레이(F3)가 hp 가 깎이는 자리를
## 들여다볼 수 있게 한 겹 씌운 것이다. `Dbg.on` 이 꺼져 있으면 override 들이 첫 줄에서
## 곧장 super() 로 빠지므로 값도 속도도 예전과 한 톨도 안 다르다.
## (자동 플레이 검사 tests/balance_check 는 BattleSim 을 그대로 만든다)
var sim := DbgSim.new()

## 배속. **설정에 남는다**(사용자가 정한 것: 「배속 설정해놨으면 그거 유지되게」).
## ★ 화면마다 1배로 되돌아가면 100탄을 도는 동안 백 번을 다시 눌러야 한다.
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
## ★ Run.total_dps() 는 영웅마다 능력치와 패시브를 매번 처음부터 곱해 센다. 전투 중에는
##   값이 바뀌지 않는데 매 프레임 부르면, 몬스터 60마리·이펙트 800개가 도는 바로 그
##   프레임에서 폰이 그 시간을 이 숫자 하나에 쓴다. 반 초에 한 번만 센다.
var _dps: float = 0.0
var _dps_t: float = 0.0
## 「무효」 전투 피드백이 연속으로 겹치지 않도록 간격을 둔다.
var _imm_t: float = 0.0
## 보통 데미지 숫자의 텀. 겹친 영웅이 한 번에 다섯 발을 쏘므로, 이것이 없으면
## 투기장이 통째로 숫자밭이 된다.
var _num_t: float = 0.0
## 장판(zone) 숫자의 텀. **보통 숫자와 따로** 둔다 — 장판은 0.25초마다 꼬박꼬박 오는데
## 그 박자를 탄알의 텀(_num_t 0.06초)에 얹으면 총알이 날아드는 동안 장판의 숫자만
## 매번 밀려서, 장판 영웅이 「아무것도 안 하는 것」으로 보인다.
var _zone_t: float = 0.0
## 크리스탈을 그리는 차례 — **y 가 작은 것부터**. 무더기로 쌓여 있어서 그리는 차례가
## 곧 앞뒤다(아래에 있는 알이 앞이다). 자리가 상수라 한 번만 세어 두면 된다 —
## 매 프레임 sort_custom 을 돌리면 스무 개를 위해 아흔 번씩 crystal_slot 을 부른다.
var _crystal_order: Array = []
var selected_hero: int = -1
var _post_press: int = -1
var _post_press_at := Vector2.ZERO
var _move_note := ""



func _ready() -> void:
	speed = Save.speed
	_crystal_order = []
	for i in range(Balance.MAX_LIVES):
		_crystal_order.append(i)
	_crystal_order.sort_custom(func(a, b):
		return Balance.crystal_slot(a).y < Balance.crystal_slot(b).y)
	# 지난 탄의 줄이 남아 있으면 「지금 무슨 일이 일어나는가」를 못 읽는다.
	Dbg.reset()
	sim.setup(Run, Run.wave)
	_dps = Run.total_dps()
	Sfx.play("wave")
	if Balance.is_boss_wave(Run.wave):
		Sfx.play("boss")
	set_process(true)


func _process(dt: float) -> void:
	if Ads.busy:
		return
	t += dt
	_dps_t -= dt
	if _dps_t <= 0.0:
		_dps_t = 0.5
		_dps = Run.total_dps()
	if _crack_t > 0.0:
		_crack_t = max(0.0, _crack_t - dt)
	if _imm_t > 0.0:
		_imm_t = max(0.0, _imm_t - dt)
	if _num_t > 0.0:
		_num_t = max(0.0, _num_t - dt)
	if _zone_t > 0.0:
		_zone_t = max(0.0, _zone_t - dt)
	var sdt: float = dt * speed
	# 디버그 오버레이의 **멈춤 / 한 걸음**. 오버레이를 안 켠 판에서는 Dbg.paused 가
	# 언제나 false 라 이 두 줄은 아무 일도 안 한다.
	# ★ 여기서 통째로 돌아 나가는 까닭: 시뮬레이터만 멈추고 이펙트·걸음새·유령을 계속
	#   굴리면, 멈춘 화면에서 몬스터가 제자리걸음을 하고 숫자가 흘러가 「멈췄다」가
	#   화면에서 안 읽힌다. 날씨만 계속 흐르게 두어 화면이 죽은 것과 구별한다.
	if Dbg.paused:
		if Dbg.step_once:
			Dbg.step_once = false
			sdt = 1.0 / 60.0
		else:
			queue_redraw()
			return
	if not sim.done:
		# ★ 배속을 걸어도 한 걸음이 너무 커지지 않게 잘라서 여러 번 돈다.
		#   한 프레임에 0.05초를 넘게 굴리면 빠른 탄이 몬스터를 통과해 버린다.
		var left := sdt
		var guard := 0
		while left > 0.0001 and guard < 16 and not sim.done:
			var step: float = min(0.02, left)
			# 모션도 같은 걸음으로 진행하고 사건을 즉시 반영한다. 프레임 끝에
			# aim을 몰아서 받으면 배속·프레임 지연 때 모션만 늦게 시작한다.
			_tick_heroes(step)
			area_fx.update(step)
			sim.step(step)
			_drain()
			left -= step
			guard += 1
	else:
		_tick_heroes(sdt)
		area_fx.update(sdt)
		_drain()
		if not _settled:
			_settle()
		end_t += dt
	_tick_ghosts(sdt)
	fx.update(dt)
	queue_redraw()


func _input(e: InputEvent) -> void:
	if Ads.busy:
		return
	# 디버그 오버레이의 자판. **에디터에서 직접 플레이하며 볼 때만** 쓰는 것이라
	# 손가락(터치)에는 아무 자리도 안 내준다 — 안드로이드에서는 F3 을 누를 길이 없으므로
	# 오버레이가 켜질 일 자체가 없다.
	if e is InputEventKey and e.pressed and not (e as InputEventKey).echo:
		if _dbg_key(e as InputEventKey):
			get_viewport().set_input_as_handled()
			return
	if not ended and not _leaving and _formation_input(e):
		get_viewport().set_input_as_handled()
		return
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
		# ★ 설정에 바로 적는다. 다음 탄에도, 앱을 껐다 켜도 그대로다.
		Save.set_speed(speed)
		Sfx.play("button")


func _post_at(p: Vector2) -> int:
	for post in range(Balance.POST_SLOTS):
		var at := Balance.post_position(post) + _sh
		if Rect2(at - Vector2(30, 78), Vector2(60, 108)).has_point(p):
			return post
	return -1

func _formation_input(e: InputEvent) -> bool:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and selected_hero >= 0:
		selected_hero = -1
		return true
	if not e is InputEventMouseButton or e.button_index != MOUSE_BUTTON_LEFT:
		return false
	if e.pressed:
		var id := ui.hit(e.position)
		if id == "post:cancel":
			selected_hero = -1
			return true
		if id.begins_with("hero:"):
			selected_hero = int(id.get_slice(":", 1))
			return true
		_post_press = _post_at(e.position)
		_post_press_at = e.position
		return _post_press >= 0
	if _post_press < 0:
		return false
	var start := _post_press
	_post_press = -1
	var target := _post_at(e.position)
	if target < 0:
		return true
	if target != start and e.position.distance_to(_post_press_at) > 8.0:
		selected_hero = Run.hero_at_post(start)
	if selected_hero < 0:
		selected_hero = Run.hero_at_post(target)
	elif sim.move_hero(selected_hero, target):
		_move_note = "이동 완료"
		fx.ring(Balance.post_position(target), Look.CRYSTAL, 8, 42, 0.35, 3)
		Sfx.play("button")
		selected_hero = -1
	else:
		selected_hero = -1
	return true

## 디버그 오버레이의 자판. 먹었으면 true.
##
##   F3 켜기/끄기 · Tab 탭 · 1~6 영웅 · 스페이스 멈춤 · 마침표 한 걸음
func _dbg_key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_F3:
			Dbg.on = not Dbg.on
			if Dbg.on:
				Dbg.reset()
			else:
				Dbg.paused = false
			return true
		KEY_TAB:
			if Dbg.on:
				Dbg.tab = (Dbg.tab + 1) % DebugView.TABS.size()
				return true
		KEY_SPACE:
			if Dbg.on:
				Dbg.paused = not Dbg.paused
				return true
		KEY_PERIOD:
			if Dbg.on:
				Dbg.paused = true
				Dbg.step_once = true
				return true
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			if Dbg.on:
				Dbg.sel = k.keycode - KEY_1
				return true
	return false


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
	if _settled:
		return
	_settled = true
	ended = true
	_lost = sim.leaked
	# ★ 처치 수는 BattleSim 이 잡을 때마다 Run.kills 에 바로 올린다. 여기서 또 더하면 두 배다.
	_bonus = Run.settle_wave(sim.wiped)
	if _lost > 0:
		fx.do_shake(12.0)
		fx.do_flash(Color(0.9, 0.1, 0.2, 0.4), 0.45)
		Sfx.force("defeat" if not Run.running else "hit_resist")
	else:
		fx.do_flash(Color(1, 1, 1, 0.35), 0.3)
		fx.ring(Balance.ARENA_CENTER, Look.GOLD, 40.0, 460.0, 0.9, 8.0)
		Sfx.force("victory")


## 시뮬레이터가 남긴 사건을 이펙트와 소리로 바꾼다.
##
## ★ 여기가 **화면과 소리의 유일한 입구**다. 시뮬레이터는 그리기도 소리도 모르고
##   "무슨 일이 있었다"만 적는다. 그래서 헤드리스로 100탄을 수백 번 돌릴 수 있다.
func _drain() -> void:
	for e in sim.events:
		var p: Vector2 = e.get("p", Vector2.ZERO)
		match String(e["t"]):
			"aim":
				# 팔을 뻗기 시작했다. **탄은 아직 안 나갔다** — 이 사건과 「fire」 사이가
				# 그 캐릭터가 팔을 뻗는 시간이다(BattleSim._aim).
				var asrc0: int = int(e.get("src", -1))
				_hero_aim(asrc0, float(e.get("w", 0.0)), e.get("d", Vector2.ZERO))
				# ★ **광역 마법은 여기서 몸을 훑고 올라가는 파동이 시작된다.**
				#   사용자가 정한 연출: 「두 팔을 들어올림과 동시에 발밑에서 머리위로
				#   이펙트가 지나가고」. 그 「지나감」이 이 한 항목이고, 팔을 드는 시간
				#   (w = windup + BULLET.zone.cast)에 딱 맞춰 끝난다.
				if String(e.get("kind", "")) == "zone" and asrc0 >= 0 \
						and asrc0 < sim.heroes.size():
					var zhe: Dictionary = sim.heroes[asrc0]
					var zel := String(zhe["elem"])
					fx.rise(Vector2(zhe["pos"]), zhe["col"], Balance.elem_color(zel),
							Art.unit_h(zhe["h"]["unit"],
									Balance.hero_scale(sim.heroes.size())) * 1.06,
							maxf(0.18, float(e.get("w", 0.3))), zel)
			"fire":
				# 총구 불꽃 — 누가 쐈는지가 보여야 화면이 살아 있다.
				var d: Vector2 = e.get("d", Vector2.RIGHT)
				var c0: Color = e.get("c", Look.GOLD)
				var fel := String(e.get("el", "none"))
				var tier := _source_tier(int(e.get("src", -1)))
				var glow := Fx.shot_scale(tier)
				fx.beam(p + d * 6.0, p + d * (20.0 + glow * 6.0), c0, 0.09, 5.0 * glow)
				if tier >= 4:
					fx.ring(p, Color(c0, 0.7), 3.0, 8.0 + float(tier), 0.16, 2.0)
				# 튀는 알갱이만 속성 색으로. 빛줄기는 캐릭터 색 그대로다 —
				# 누가 쐈는지(색)와 무엇으로 쐈는지(알갱이)를 한 자리에서 같이 보여 준다.
				fx.burst(p + d * 16.0, Balance.elem_color(fel) if fel != "none" else c0,
						3 + tier / 2, 100.0 + float(tier) * 9.0, 0.16, 2.6, 0.0)
				Sfx.play(Sfx.shot_id(fel, String(e.get("kind", "shot"))), -6.0, 1.0, 0.07)
			"hit":
				_on_hit(p, e)
				if String(e.get("kind", "")) != "splash":
					_unit_impact(p, int(e.get("src", -1)), 36.0, float(e.get("em", 1.0)))
			"splash":
				# ★ **들어온 방향(d)**을 같이 넘긴다 — 폭발과 파편이 그 반대쪽으로 쏠려야
				#   「어느 쪽에서 맞았는지」가 화면에 남는다.
				# ★ 분열 조각(split)인지도 넘긴다. 그것은 명중마다 터져서 초당 수십 번이라
				#   화면을 흔들면 안 된다(_boom).
				_boom(p, e.get("c", Look.GOLD), float(e["r"]), float(e.get("em", 1.0)),
						String(e.get("el", "none")), e.get("d", Vector2.ZERO),
						bool(e.get("split", false)), int(e.get("src", -1)))
			"beam":
				var src: int = int(e.get("src", -1))
				var tier := _source_tier(src)
				if tier >= 4:
					fx.beam(e["a"], e["b"], Color(e.get("c", Look.BLUE), 0.28),
							0.32, 9.0 * Fx.shot_scale(tier), false)
				if src >= 0 and src < sim.heroes.size():
					var shot := Anim.clip(sim.heroes[src]["h"]["unit"], "shot")
					if not shot.is_empty():
						fx.clip_beam(e["a"], e["b"], shot, tier)
						continue
				# ★ 광선도 속성을 말해야 한다. **캐릭터 색 광선은 그대로 두고**, 그 뒤에
				# 속성 색 빛무리를 한 겹 깐다(흰 심지는 끈다 — 두 번 그리면 굵은 흰
				# 막대가 되어 무슨 색인지 사라진다). 전기는 그 위에 한 번 지직거린다.
				var bel := String(e.get("el", "none"))
				if bel != "none":
					fx.beam(e["a"], e["b"], Balance.elem_color(bel), 0.24, 13.0, false)
				fx.beam(e["a"], e["b"], e.get("c", Look.BLUE), 0.20, 7.0)
				if bel == "elec":
					fx.bolt(e["a"], e["b"], Balance.elem_color(bel), 0.16, 3.0)
			"bolt":
				var tier := _source_tier(int(e.get("src", -1)))
				var shot_src := int(e.get("shot_src", -1))
				if shot_src >= 0 and shot_src < sim.heroes.size():
					var chain_shot := Anim.clip(sim.heroes[shot_src]["h"]["unit"], "shot")
					if not chain_shot.is_empty():
						fx.clip_chain(e["a"], e["b"], chain_shot, _source_tier(shot_src))
				fx.bolt(e["a"], e["b"], e.get("c", Look.BLUE), 0.24, 5.0 * Fx.shot_scale(tier))
				Sfx.play("chain", -8.0, 1.0, 0.10)
				if e.has("n"):
					_on_hit(e.get("p", e["b"]), e)
			"die":
				var col: Color = e.get("c", Look.RED)
				var huge: bool = float(e.get("h", 50.0)) > 100.0
				fx.burst(p, col, 30 if huge else 14, 340.0 if huge else 220.0, 0.55, 3.6)
				fx.ring(p, col, 6.0, 76.0 if huge else 38.0, 0.34, 3.5)
				fx.debris(p, col, 10 if huge else 4, 300.0 if huge else 190.0, 0.5, 4.0)
				if huge:
					fx.do_shake(9.0)
					fx.do_flash(Color(1, 0.9, 0.5, 0.4), 0.3)
					fx.sprite(p, Roster.ART.get("boom", ""), 1.6, 0.55)
					Sfx.force("die_big")
				else:
					Sfx.play("die", -10.0, 1.0, 0.14)
			"wildfire":
				# 패시브 「들불」 — 타는 놈이 죽으면서 둘레로 옮아 붙는다.
				# ★ 예전에는 납작한 주황 원(disc) 하나에 고리 하나였다. 그것은 「어디까지 옮아
				#   붙었나」를 그린 **범위 표시**이지 불이 아니다 — 광역과 똑같은 까닭으로
				#   갈아 끼운다(_boom 주석 참고).
				# ★ 다만 세기를 0.85 로 눌러 둔다. 들불의 반경은 96px 로 못 박혀 있어 보통
				#   광역(48px)의 **두 배**인데, 세기까지 1.0 이면 덤으로 붙는 불이 진짜
				#   광역탄보다 더 센 폭발로 읽힌다.
				var wr: float = float(e.get("r", 90.0))
				area_fx.impact(p, wr, "fire", Balance.elem_color("fire"), 4, true)
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
					fx.debris(cp, Look.CRYSTAL_DEEP, 8, 260.0, 0.7, 4.5)
				var cp0: Vector2 = Balance.ARENA_CENTER + Balance.crystal_slot(top)
				fx.beam(p, cp0, Look.RED, 0.3, 6.0)
				fx.float_text(cp0 + Vector2(0, -40),
						"크리스탈 깨짐" if n_break == 1 else "크리스탈 %d개 깨짐" % n_break,
						Look.RED, 22, 1.0, 0.7, true)
				fx.do_shake(10.0 + 4.0 * float(n_break))
				fx.do_flash(Color(0.9, 0.15, 0.25, 0.30), 0.28)
				_crack_t = 0.6
				_crack_n = n_break
				Sfx.force("leak")
			"block":
				# 패시브 「수정 방벽」이 막았다. **막았다는 것이 보여야** 산 보람이 있다.
				var bh: float = float(e.get("h", 50.0))
				fx.ring(p, Look.CRYSTAL, 4.0, bh * 1.6, 0.34, 5.0)
				fx.burst(p, Look.CRYSTAL, 12, 200.0, 0.4, 3.0, 0.0)
				fx.float_text(p + Vector2(0, -40), "방어!", Look.CRYSTAL, 24, 0.9, 0.8, true)
				Sfx.play("block")
			"curse":
				fx.bolt(p, Balance.ARENA_CENTER, Look.PURPLE, 0.3, 6.0)
				fx.ring(Balance.ARENA_CENTER, Look.PURPLE, 20.0, 170.0, 0.5, 4.0)
			"zone":
				var zshot: Dictionary = {}
				var zshot_src := int(e.get("src", -1))
				if zshot_src >= 0 and zshot_src < sim.heroes.size():
					zshot = Anim.clip(sim.heroes[zshot_src]["h"]["unit"], "shot")
				area_fx.zone(p, float(e["r"]), String(e.get("el", "none")),
						e.get("c", Look.GOLD), _source_tier(int(e.get("src", -1))),
						float(e.get("delay", 0.0)), float(Balance.BULLET["zone"]["tick"]),
						Balance.zone_ticks(), zshot)
				# 피해 전에는 중앙의 작은 충전 이펙트가, 이후에는 영웅 Shot과
				# 파편이 보인다. 범위를 두르는 안내 원 없이 기존 delay/틱을 따른다.
				Sfx.play("shot_zone", -9.0, 1.0, 0.12)
			"zone_tick":
				# ★ 장판이 한 번 때렸다. 숫자·소리·「무효」가 여기서 나온다 —
				#   예전 장판은 이 자리가 통째로 비어 있어서 「약점 2배」도 「무효」도
				#   장판에서만 아무 데도 안 떴다(CLAUDE.md 10-8).
				# ★ n 은 시뮬레이터가 **상성을 이미 곱한** 값이다(「hit」과 같은 규약).
				#   화면이 em 을 또 곱하면 전투와 표시가 어긋난다 — em 은 약점/무효 중
				#   어느 얼굴로 띄울지를 고르는 데만 쓴다.
				var zsrc: int = int(e.get("src", -1))
				var zem: float = float(e.get("em", 1.0))
				var zmp: Vector2 = e.get("mp", p)
				if e.has("n") and _zone_t <= 0.0:
					_zone_t = 0.22
					fx.dmg_text(zmp + Vector2(0, -26), float(e["n"]), zem, false,
							Balance.elem_color(String(e.get("el", "none"))))
					Sfx.play(Sfx.hit_id(zem), -12.0)
					if zem <= 0.001 and _imm_t <= 0.0:
						# 면역이면 숫자가 아예 안 뜬다(dmg_text 가 0 을 안 그린다).
						# 그대로 두면 「장판이 고장 났다」로 읽힌다(CLAUDE.md 10-8).
						_imm_t = 0.5
						fx.float_text(zmp + Vector2(0, -34), "0",
								Color("#9a9da3"), 28, 0.8, 0.6, true)
					elif zem > 1.01:
						fx.weak_impact(zmp, Balance.elem_color(String(e.get("el", "none"))), _source_tier(zsrc))
			"ric":
				# ★ **도탄이 꺾였다.** 번개(bolt)와 **다르게 그린다** — 연쇄는 지직거리는
				#   지그재그이고 도탄은 물건이 튄 것이라 **곧은 흔적** 하나다.
				#   같은 그림으로 두면 화면에서 둘을 구별할 수 없고, 그러면 「연쇄는 반드시
				#   전기」라는 규칙(CLAUDE.md 5-4)이 화면에서 뜻을 잃는다.
				var rel := String(e.get("el", "none"))
				var rc: Color = e.get("c", Look.GOLD)
				fx.beam(e["a"], e["b"], rc, 0.11, 2.4, false)
				fx.burst(e["a"], Balance.elem_color(rel) if rel != "none" else rc,
						4, 130.0, 0.2, 2.2, 0.0)
				Sfx.play("ric", -11.0, 1.0, 0.06)
			"push":
				# 물 「특효」가 밀어냈다. 발밑에서 뒤로 물살이 한 번 퍼진다.
				var pe: Color = Balance.elem_color("water")
				fx.ring(p + Vector2(0, float(e.get("h", 50.0)) * 0.30), pe,
						3.0, 26.0, 0.24, 3.0)
				fx.burst(p, pe, 5, 150.0, 0.24, 2.4, 0.0)
			"frost":
				# 처음 얼어붙는 순간에만 온다(BattleSim._slow 참고). 조각이 튀고
				# 발밑으로 성에가 한 번 퍼진다.
				# ★ **이 한 방짜리 연출은 그림으로 안 바꾼다.** 걸려 있는 동안의 겉그림
				#   (fx_ice_bg · fx_ice_fg)만 그림이고 여기는 도형 그대로다. 까닭이 둘:
				#   (1) 이것은 조각이 사방으로 **날아가는** 것이라 한 장으로는 못 그린다.
				#   (2) Fx.sprite 는 **한가운데** 기준인데 상태이상 겉그림은 **발밑**
				#       기준(Art.draw_at)이라, 한쪽만 그림으로 바꾸면 같은 얼음이 두 가지
				#       기준점으로 놓여서 얼음이 발에서 떠 보인다.
				var fh: float = float(e.get("h", 50.0))
				fx.frost(p, 8, 80.0 + fh * 0.9, 0.5)
				fx.ring(p, Look.ICE, 3.0, fh * 0.75, 0.28, 3.0)
				Sfx.play("frost", -10.0, 1.0, 0.10)
			"stun":
				# 마비가 **처음 걸리는 순간**에만 온다(BattleSim._stun 참고).
				# 얼음(frost)과 결이 반대여야 한다 — 성에는 퍼지고 전기는 **터진다.**
				# ★ 여기도 도형 그대로다 — 바로 위 「frost」의 두 가지 까닭과 같다.
				var sh2: float = float(e.get("h", 50.0))
				var sc2 := Balance.elem_color("elec")
				fx.burst(p, sc2.lightened(0.3), 5, 110.0, 0.22, 1.8, 0.0)
				fx.bolt(p + Vector2(-sh2 * 0.5, -sh2 * 0.5),
						p + Vector2(sh2 * 0.5, sh2 * 0.2), sc2, 0.16, 1.8)
				Sfx.play("stun", -8.0, 1.0, 0.10)
	sim.events.clear()


## 한 대 맞았다 — 상성에 따라 **연출의 세기가 통째로 달라진다.**
##
## 사용자가 정한 것: 「데미지를 숫자로 임팩트 있게, 두 배면 더 큰 이펙트, 반감이면
## 소극적인 이펙트」. 그래서 세 갈래를 뚜렷하게 갈라 놓는다:
##   약점(2배)  속성 색 · 큰 숫자 · 고리와 불똥이 두 배 · 「약점!」
##   저항(0.5)  잿빛 · 작은 숫자 · 불똥 셋
##   면역(0배)  회색 숫자 0 · 튕기는 소리
##
## ★ 배수는 시뮬레이터가 **실제로 적용한** 값을 그대로 받는다. 화면이 제 나름대로
##   곱하면 언젠가 전투와 표시가 어긋나고, 그 어긋남은 아무도 못 잡는다.
## ★ 숫자에는 텀이 있다. 겹친 영웅이 한 번에 다섯 발을 쏘므로 매 명중마다 띄우면
##   투기장이 통째로 숫자밭이 된다 — 불똥은 매번 튀고 **숫자만** 텀으로 잡는다.
func _on_hit(p: Vector2, e: Dictionary) -> void:
	var hc: Color = e.get("c", Look.INK)
	var big: bool = bool(e.get("crit", false))
	var em: float = float(e.get("em", 1.0))
	var el := String(e.get("el", "none"))
	var ec := Balance.elem_color(el)
	var n: float = float(e.get("n", 0.0))
	var tier := _source_tier(int(e.get("src", -1)))
	if em > 0.001:
		fx.rarity_impact(p, hc, tier, 1.20 if em > 1.01 else (0.55 if em < 0.99 else 1.0))
	if em > 1.01:
		fx.weak_impact(p, ec, tier, big)
		if _num_t <= 0.0 or big:
			_num_t = 0.09
			fx.dmg_text(p + Vector2(0, -30), n, em, big, ec)
		Sfx.play("hit_weak", -6.0, 1.0, 0.06)

	elif em <= 0.001:
		# ★ **아예 안 통했다**(나무·바위 몸 x 전기). 저항(반감)과 **다르게** 그려야 한다 —
		#   둘 다 "색이 빠진 작은 불똥"이면 플레이어는 반만 들어가는 것과 한 톨도
		#   안 들어가는 것을 구별할 길이 없고, 그러면 열 탄을 통째로 잃고도 왜 그랬는지
		#   모른다. **숫자를 아예 안 띄우는 것**이 여기서 제일 정직한 표시다.
		fx.ring(p, Color(0.55, 0.58, 0.68), 6.0, 22.0, 0.22, 3.0)
		if _imm_t <= 0.0:
			_imm_t = 0.5
			fx.float_text(p + Vector2(0, -34), "0", Color("#9a9da3"), 28, 0.8,
					0.6, true)
			Sfx.play("hit_immune", -6.0)
	elif em < 0.99:
		# 튕겨 냈다 — 불똥이 몇 알 안 튀고 색이 빠진다.
		fx.burst(p, Color(hc.r, hc.g, hc.b, 0.55), 3, 130.0, 0.20, 2.4, 0.0)
		fx.ring(p, Color(0.72, 0.72, 0.80), 2.0, 13.0, 0.16, 2.0)
		Sfx.play("hit_resist", -12.0, 1.0, 0.06)
		if _num_t <= 0.0:
			_num_t = 0.09
			fx.dmg_text(p + Vector2(0, -26), n, em, big, ec)
	else:
		if String(e.get("kind", "")) != "beam":
			# ★ 광선은 평상시엔 불똥을 안 그린다. 이미 제 몸(fx.beam)이 끝점에
			#   흰 구슬을 그려서, 여기에 또 그리면 광선 영웅만 유난히 번쩍인다.
			fx.burst(p, hc, 10 if big else 6, 220.0, 0.28, 3.4, 0.0)
			fx.ring(p, Color(1, 1, 1, 1), 2.0, 26.0 if big else 17.0, 0.20, 3.0)
		Sfx.play("crit" if big else "hit", -10.0, 1.0, 0.06)
		if _num_t <= 0.0 or big:
			_num_t = 0.06
			fx.dmg_text(p + Vector2(0, -30), n, em, big, ec)


## 광역이 터진다. **사용자가 「밋밋하다」고 한 바로 그 자리다.**
##
## ★ 왜 밋밋했는가 — 예전에는 Fx 항목 여섯을 냈는데 **여섯이 전부 뒤 layer 였다.**
##   코어 섬광도 속성 원반도 충격파도 **방금 때린 그 몬스터 뒤에** 깔려서, 62x52 짜리
##   스프라이트 뒤의 25px 짜리 섬광은 한 조각도 안 보였다 — 그래서 「범위 표시」처럼 보였다.
## ★ 지금은 폭발 그림(AreaFx.impact)이 땅과 몸통 두 겹으로 나뉘어 배우 앞뒤에 그려진다.
##   겹친 영웅(x5)이 한 번에 다섯 발을 터뜨려도 항목은 다섯 개다.
## ★ 약점이면 통째로 1.35배, 저항이면 0.72배다 — 「두 배면 더 큰 이펙트」(CLAUDE.md
##   10-8)가 폭발에도 그대로 걸린다.
## ★ `_d`(탄이 들어온 쪽)는 시뮬레이터가 흘려 주는 값이다. 지금 그림은 사방으로 터지므로
##   안 쓰지만, 사건의 모양은 그대로 둔다(화면이 다시 쓰게 될 때 시뮬레이터를 안 건드리게).
func _boom(p: Vector2, col: Color, r: float, em: float, el: String,
		_d: Vector2 = Vector2.ZERO, split: bool = false, src: int = -1) -> void:
	if em <= 0.001:
		return
	# Weakness changes damage, never the damage footprint.
	area_fx.impact(p, r, el, col, _source_tier(src), split)
	if not split and r > 34.0:
		fx.do_shake(minf(5.0, 1.5 + r * 0.035))
	Sfx.play("splash", -6.0, 1.0, 0.08)


## 속성이 폭발의 **모양**을 고른다 — 불은 뭉게뭉게, 얼음과 물은 각진 조각,
## 전기는 튀는 불꽃. 넷이 같은 모양으로 터지면 도트 화면에서 색만 다른 같은 얼룩이다
## (CLAUDE.md 18-6 과 같은 뜻).
##
## ★ 표를 **Fx 가 아니라 여기** 둔다. Fx 는 그리기만 아는 곳이라 Balance 의 속성 표를
##   모르게 두는 편이 낫다 — 알게 하면 이펙트가 밸런스 표를 따라다니게 된다.
func _source_tier(src: int) -> int:
	if src < 0 or src >= sim.heroes.size():
		return 0
	return clampi(int(sim.heroes[src]["h"]["tier"]), 0, 9)


func _unit_impact(p: Vector2, src: int, radius: float, em: float) -> bool:
	if em <= 0.001 or src < 0 or src >= sim.heroes.size():
		return false
	var animation := Anim.clip(sim.heroes[src]["h"]["unit"], "effect")
	if animation.is_empty():
		return false
	fx.clip(p, animation, radius)
	return true


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
	# 장판의 **시전 발판**(누가 깔고 있는가) — 배우 아래다.
	# ★ 그리고 **실제로 깔린 원**(어디를 때리고 있는가). 둘은 다른 것이다 —
	#   발판은 시전자 발밑에 붙어 있고, 원은 시전자와 멀리 떨어진 무리 위에 깔린다.
	_draw_zones_ground()
	fx.draw_back(self)
	_draw_actor_effects()
	area_fx.draw_front(self)
	_draw_crystals()
	_draw_bullets()
	fx.draw(self)
	_draw_weather()
	# 모든 효과와 섬광 뒤에 캐릭터를 그린다. 메뉴/결과 UI는 그보다 위다.
	fx.draw_flash(self, Rect2(-40, -40, 1360, 880))
	_draw_actors()
	_draw_hp_bars()
	_draw_hero_tags()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_panel()
	_draw_topbar()
	_draw_boss_bar()
	if not ended and selected_hero >= 0:
		ui.button(self, Rect2(708, 748, 80, 30), "취소", "post:cancel", true, Look.PANEL_EDGE, 16)
	if ended:
		_draw_result()
	# ★ 맨 마지막이다. 화면 섬광(draw_flash)보다도 위라야 로열 연출이나 큰 폭발이
	#   터지는 순간에도 숫자가 안 씻긴다. 이 시점에는 draw_set_transform 이 이미
	#   단위 변환으로 되돌아와 있으므로(위의 _draw_panel 앞) 흔들림도 안 탄다.
	DebugView.draw(self, sim, speed)


## 눈·비·불티·잎·먼지는 지형과 공격 효과 위, 캐릭터 몸체 아래에 그린다.
## ★ 정보판(x>PANEL_X)과 위쪽 띠에는 안 뿌린다. 글자 위에 눈이 오면 안 읽힌다.
func _draw_weather() -> void:
	Scenery.draw_weather(self, _theme(), Rect2(0, 68, PANEL_X, 732), t, 44)


## 이 탄이 걸린 테마. 한 프레임에 여러 번 물으므로 한 번만 재어 둔다.
func _theme() -> Dictionary:
	return Run.theme_for(Run.wave) if Run.has_method("theme_for") else {}


## 배경. **테마마다 다른 곳처럼 보여야 한다**(사용자가 정한 것: 「테마별 배경 좀 바뀌게」).
##
## ★ 예전에는 투기장 그림 한 장에 테마 색을 곱하기만 했다. 그러면 쉰 곳이 「색만 다른
##   같은 곳」이고, 실제로 첫 사진에서 호수와 화산이 구별이 안 됐다. 지금은 하늘·능선·
##   땅·날씨를 코드로 그린다(core/scenery.gd) — 물이면 수평선과 비, 불이면 화산과
##   불티, 나무면 우거진 숲과 잎, 바위면 각진 봉우리와 먼지, 얼음이면 눈 덮인 산과 눈.
func _draw_bg() -> void:
	Scenery.draw_backdrop(self, _theme(), Look.SCREEN, t)


## 투기장 — 벽 세 겹, 그 사이의 길 두 겹, 가운데 전장.
##
## ★ 여기가 이 게임에서 제일 중요한 그림이다. "몬스터가 어디로 오는가"가 한눈에
##   안 보이면 플레이어는 무엇을 막고 있는지도 모른 채 목숨만 잃는다.
func _draw_arena() -> void:
	Battlefield.draw_map(self, t, Color(0.88, 0.88, 0.90))
	if selected_hero >= 0 and selected_hero < sim.heroes.size():
		var hero: Dictionary = sim.heroes[selected_hero]
		Battlefield.draw_range(self, hero["pos"], float(hero["range"]), Look.GOLD)
	for post in range(Balance.POST_SLOTS):
		var occupant := Run.hero_at_post(post)
		Battlefield.draw_post(self, post, occupant >= 0 and selected_hero == occupant, selected_hero >= 0)


## 제단 바닥. 배우들 **아래**에 깔린다.
func _draw_altar() -> void:
	var c := Balance.ARENA_CENTER
	draw_circle(c, Balance.ALTAR_R + 10.0, Color(0, 0, 0, 0.45))
	draw_circle(c, Balance.ALTAR_R + 4.0, Color(0.10, 0.16, 0.22, 0.85))
	draw_arc(c, Balance.ALTAR_R + 4.0, 0.0, TAU, 56, Color(Look.CRYSTAL.r, Look.CRYSTAL.g,
			Look.CRYSTAL.b, 0.30), 2.0, true)


## **실제로 깔린 장판.** 배우 아래에 그린다.
##
## 사용자가 정한 것: 「특정 area 에 특정범위를 가진 애니메이션을 생성하고 **그 범위에
## 해당되는 애들만** 데미지를 받도록」. 그래서 여기 그리는 원은 「닿는 데까지」가 아니라
## **맞는 자리 그 자체**다 — 원 안에 든 놈만 맞는다.
##
## ★ **이것은 사용자가 지운 「동그라미 영역표시」가 아니다.** 지운 것은 사거리를 그린
##   원이었다(닿는 데까지를 알려 주는 안내선). 이것은 **피해가 실제로 들어가는 자리**라,
##   안 그리면 왜 저 놈만 맞는지를 화면에서 알 길이 없다(CLAUDE.md 10-9-2 의 마지막 줄이
##   그 구별을 못 박아 뒀다: 「그리는 원은 **damaged area** 여야 한다」).
## ★ **깔리기 전(delay)에는 표적만** 그린다 — 테두리가 안으로 조여들고 안쪽은 비어 있다.
##   그 틈이 「여기 떨어진다」를 말하는 유일한 시간이다.
## ★ 파티클 배열을 안 쓴다(발판·날씨와 같은 수법, CLAUDE.md 10-10). 자리는 시간과
##   번호로 셈한다 — 원 여섯이 초당 수백 개를 Fx 에 넣으면 타격 이펙트가 그 안에 묻힌다.
func _draw_zones_ground() -> void:
	area_fx.draw_back(self)


## 크리스탈 제단 — 목숨이 곧 여기 놓인 크리스탈 개수다.
##
## ★ 스무 개가 **한 무더기로 모여** 있다(Balance.CRYSTAL_RING_N). 예전에는 반지름 62
##   짜리 고리 하나로 넓게 둘러서 있었는데, 크리스탈은 배우보다 **나중에** 그리므로
##   그 고리가 영웅 그림 위에 가로줄을 그었다 — 사용자가 본 「캐릭과 일러스트가
##   겹친다」가 그것이다.
## ★ **아래에 있는 알을 나중에** 그린다(_crystal_order). 겹쳐 쌓인 무더기라 그리는 차례가
##   곧 앞뒤다. 번호 차례로 그리면 바깥 겹이 한가운데 알을 덮어 「고리 두 개」로 보인다.
func _draw_crystals() -> void:
	var c := Balance.ARENA_CENTER
	var pr: float = Balance.crystal_pile_r()
	# 배우 위에 그리므로, 무더기가 허공에 뜬 것처럼 보이지 않게 그늘을 깐다.
	# ★ 넓이를 **무더기에 딱 맞춘다.** 예전에는 제단 크기(74+2)만큼 깔아서, 그 어두운
	#   원이 영웅 그림의 다리 위에 통째로 얹혔다.
	draw_circle(c, pr + 3.0, Color(0.04, 0.06, 0.10, 0.40))
	draw_circle(c, pr * 0.70, Color(0.04, 0.06, 0.10, 0.34))
	var mx: int = Run.max_lives()
	var alive: int = Run.lives
	for i in _crystal_order:
		if i >= mx:
			continue
		var p: Vector2 = c + Balance.crystal_slot(i)
		var on: bool = i < alive
		var glow := 0.0
		if on and i == alive - 1:
			# 다음에 깨질 놈이 숨 쉬듯 빛난다 — 위험을 눈으로 알려 준다.
			glow = 0.5 + 0.5 * sin(t * 4.0)
		if _crack_t > 0.0 and i >= alive and i < alive + _crack_n:
			glow = _crack_t / 0.6
		Look.draw_crystal(self, p, Balance.CRYSTAL_DRAW_R, on, glow)


func _draw_actor_effects() -> void:
	var scale := Balance.hero_scale(sim.heroes.size())
	for hero in sim.heroes:
		_draw_hero(hero, scale, true)
	for monster in sim.monsters:
		_draw_monster(monster, true)


func _draw_actors() -> void:
	# 몬스터보다 영웅을 앞에 둔다. 같은 종류끼리는 아래에 있는 몸체가 앞이다.
	var items: Array = []
	var n: int = sim.heroes.size()
	var hsc := Balance.hero_scale(n)
	for he in sim.heroes:
		items.append({"y": float(he["pos"].y), "kind": "h", "d": he})
	for mo in sim.monsters:
		items.append({"y": BattleSim.mpos(mo).y, "kind": "m", "d": mo})
	items.sort_custom(func(a, b):
		if a["kind"] != b["kind"]:
			return a["kind"] == "m"
		return float(a["y"]) < float(b["y"]))

	for it in items:
		if String(it["kind"]) == "h":
			_draw_hero(it["d"], hsc)
		else:
			_draw_monster(it["d"])


## 클립이 없는 캐릭터가 코드로 흉내 내는 내지르기에서, 가장 앞으로 나가는 지점의 k.
## `sin(pow(k, 0.55) * PI)` 가 최대가 되는 자리다 — 여기에 탄이 떠나는 순간을 맞춘다.
const JAB_PEAK := 0.285


## 영웅의 공격 모션을 굴린다.
##
## ★ 이것도 **화면만의 값**이다(체력 막대 잔상과 같은 수법). BattleSim 은 그리기를
##   모르므로 영웅 딕셔너리에 fx_ 키를 여기서 얹는다. 헤드리스 검사는 이 함수를 아예
##   안 부르니 전투 계산은 한 톨도 안 달라진다.
## ★ 배속(sdt)으로 굴린다. 실제 시간으로 굴리면 3배속에서 모션만 제 속도로 남아,
##   쏘는 것과 몸짓이 따로 논다.
func _tick_heroes(sdt: float) -> void:
	for he in sim.heroes:
		he["fx_t"] = float(he.get("fx_t", 9.0)) + sdt


## 그 영웅이 팔을 뻗기 시작했다. 모션 시계를 되감는다.
##
## ★ **바라보는 쪽은 여기서 안 정한다.** 시뮬레이터가 들고 있는 `he["face"]` 를 그대로
##   본다 — 총구 자리가 그 값에 달려 있어서, 화면이 따로 굴리면 그림은 왼쪽을 보는데
##   탄은 오른쪽에서 나가는 어긋남이 생긴다.
## ★ `w` 는 그 발이 **팔을 뻗는 데 쓰는 시간**이다. 클립의 놓는 칸이 정확히 그때 오도록
##   클립 속도를 맞추는 데 쓴다(_draw_hero). 연사로 쿨다운이 짧아 시간이 깎였으면
##   클립도 그만큼 빨리 돈다.
func _hero_aim(src: int, w: float, d: Vector2 = Vector2.ZERO) -> void:
	if src < 0 or src >= sim.heroes.size():
		return
	var he: Dictionary = sim.heroes[src]
	he["fx_t"] = 0.0
	he["fx_w"] = w
	he["fx_d"] = d


## 영웅 한 명 — 그림자 · 등급 고리 · 공격 모션.
##
## ★ 그림을 draw_set_transform 아래에서 그린다. 그래야 **바라보는 쪽(좌우 뒤집기)**과
##   내지르는 순간의 눌림을 한 번에 줄 수 있다. Art 쪽에 뒤집기 인자를 더하면 화면
##   세 곳이 저마다 다른 방법으로 뒤집게 되고, 언젠가 한 곳이 빠진다.
## ★ 되돌릴 때는 반드시 _sh 로 되돌린다 — Vector2.ZERO 로 되돌리면 흔들림이 사라진다.
func _draw_hero(he: Dictionary, sc: float, effects_only: bool = false) -> void:
	var h: Dictionary = he["h"]
	var u: Dictionary = h["unit"]
	var pos: Vector2 = he["pos"]
	var dh: float = Art.unit_h(u, sc)
	# 발밑 그림자 — 이게 없으면 캐릭터가 바닥에 안 붙고 떠 보인다.
	# ★ 크기는 그려지는 키에 맞춘다. 22px 로 고정해 두면 큰 영웅은 발끝만 그늘지고
	#   작은 영웅은 그늘 위에 올라선 것처럼 보인다.
	if effects_only:
		draw_set_transform(pos + _sh, 0.0, Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, dh * 0.22, Color(0, 0, 0, 0.35))
		draw_set_transform(_sh, 0.0, Vector2.ONE)
		_draw_tier_ring(pos, dh, int(h["tier"]))
		return

	# 공격 모션 — 쏜 쪽으로 한 번 내질렀다가 제자리로 돌아온다.
	var ft: float = float(he.get("fx_t", 9.0))
	# ★ 바라보는 쪽은 **시뮬레이터가 정한다**(총구 자리가 여기 달려 있다). 거기에
	#   그림이 애초에 어느 쪽을 겨누고 뽑혔는지를 곱한다 — 서른 장 중 여섯은 왼쪽을
	#   겨누고 나왔고, 그대로 그리면 목표가 오른쪽인데 왼쪽으로 쏘는 그림이 된다.
	var face: float = float(he.get("face", 1.0))
	var flip: float = face * Balance.art_aim(u)
	var bob := sin(t * 3.0 + pos.x * 0.05) * 2.0

	# ★ 클립이 있으면 **몸짓은 그림이 낸다.** 그때는 코드로 내지르는 시늉(jab)을 끈다 —
	#   둘을 겹치면 팔은 클립대로 도는데 몸이 따로 밀려서 두 사람이 겹친 것처럼 보인다.
	#   클립이 아직 없는 캐릭터는 지금까지 하던 대로 코드가 흉내 낸다.
	var span: float = Anim.length(u, "attack")
	var has_clip: bool = span > 0.0
	if bool(Anim.clip(u, "idle").get("fixed_feet", false)):
		bob = 0.0
	var jab := 0.0
	var ct := ft
	if has_clip:
		# ★ 클립을 **끝까지** 돌린다. 예전에는 0.26초에서 잘라 아이들로 돌아갔는데
		#   공격 클립은 0.405초짜리라 팔을 가장 앞으로 뻗는 칸을 아무도 못 봤다.
		# ★ 그리고 **놓는 칸이 탄이 떠나는 순간에 오도록** 속도를 맞춘다. 연사로
		#   뻗는 시간이 깎였으면 클립도 그만큼 빨리 돈다(_hero_aim 의 w).
		var ht: float = Anim.hit_time(u, "attack")
		var w: float = float(he.get("fx_w", ht))
		if ht > 0.0 and w > 0.0:
			ct = ft * (ht / w)
		span = span * (1.0 if ht <= 0.0 or w <= 0.0 else w / ht)
	else:
		# ★ 코드 모션도 **가장 앞으로 나가는 순간**이 탄이 떠나는 순간과 맞아야 한다.
		var w2: float = float(he.get("fx_w", 0.0))
		span = maxf(0.12, (w2 / JAB_PEAK) if w2 > 0.0 else 0.26)
		# ★ 앞이 빠르고 뒤가 느리게 굴린다(pow 0.55). 대칭으로 두면 "내지른다"가 아니라
		#   "흔들린다"로 보여서, 때리는 순간이 어디인지가 안 읽힌다.
		jab = sin(pow(clampf(ft / span, 0.0, 1.0), 0.55) * PI)

	var clip_name: String = "attack" if ft < span else "idle"
	var d: Vector2 = he.get("fx_d", Vector2.ZERO)
	var at := pos + Vector2(0.0, bob) + d * (9.0 * jab)
	draw_set_transform(at + _sh, flip * 0.12 * jab,
			Vector2(flip * (1.0 + 0.07 * jab), 1.0 - 0.05 * jab))
	if not Anim.draw_unit(self, u, clip_name,
			ct if clip_name == "attack" else t, 0.0, 0.0, sc):
		Art.draw_unit(self, u, 0.0, 0.0, sc)
	draw_set_transform(_sh, 0.0, Vector2.ONE)


## 영웅 발밑의 **등급 고리**. 전투 중에 "저 애가 몇 등급인가"를 말해 주는 표시다.
##
## ★ 왜 글자가 아니라 고리인가: 머리 위는 이미 「n겹」이 차지하고 있고, 그 위에 등급
##   이름까지 얹으면 전장이 글자밭이 된다. 발밑 고리는 그림을 한 조각도 안 가리면서
##   색만으로 등급을 말한다 — 오른쪽 정보판의 등급표와 **같은 색**이라 짝이 지어진다.
## ★ 그림자와 같은 눌린 원(세로 0.34배)에 얹어야 바닥에 놓인 판으로 보인다.
func _draw_tier_ring(pos: Vector2, dh: float, tier: int) -> void:
	var tc := Look.tier_color(tier)
	var r: float = dh * 0.27
	draw_set_transform(pos + _sh, 0.0, Vector2(1.0, 0.34))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(0, 0, 0, 0.55), 6.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(tc.r, tc.g, tc.b, 0.95), 3.4, true)
	draw_set_transform(_sh, 0.0, Vector2.ONE)


## 겹친 영웅의 「n겹」 표. **크리스탈보다 나중에** 그린다 —
## ★ 영웅과 같이 그렸더니 제단 쪽에 선 영웅의 표가 크리스탈에 통째로 가려졌다.
##   몇 겹인지가 안 보이면 "같은 애가 또 나왔는데 아무 일도 안 일어났다"가 된다.
func _draw_hero_tags() -> void:
	var sc := Balance.hero_scale(sim.heroes.size())
	for he in sim.heroes:
		var h: Dictionary = he["h"]
		var pos: Vector2 = he["pos"]
		var dh := Art.unit_h(h["unit"], sc)
		Look.draw_rarity(self, pos - Vector2(0, dh + 14), int(h["tier"]), 4.5)
		var n := int(h.get("n", 1))
		if n > 1:
			Look.text_center_out(self, pos - Vector2(0, dh + 40), "x%d" % n, 20, Look.GOLD, Look.BG_DEEP, 2)


## 몬스터가 바라보는 쪽(-1 왼쪽 / +1 오른쪽). 길에서 **앞으로** 가는 방향의 x 부호다.
##
## ★ 죽은 구간(3px)을 두고 **지난 값을 기억**한다. 문을 지날 때는 똑바로 안쪽으로 걸어서
##   x 가 거의 안 변하는데, 그때 매 프레임 새로 재면 좌우로 발작하듯 뒤집힌다.
##   (ghost 와 같이 화면만 쓰는 값이라 몬스터 딕셔너리에 얹어 둔다)
func _face_of(mo: Dictionary, p: Vector2) -> float:
	var ahead := Balance.path_at(float(mo["s"]) + 14.0, float(mo["off"]), int(mo.get("route", 0)))
	var dx: float = ahead.x - p.x
	if absf(dx) > 3.0:
		mo["fx_face"] = -1.0 if dx < 0.0 else 1.0
	return float(mo.get("fx_face", 1.0))


func _draw_monster(mo: Dictionary, effects_only: bool = false) -> void:
	var p := BattleSim.mpos(mo)
	var m: Dictionary = mo["m"]
	var mh: float = float(mo["h"])
	var art := String(m.get("art", ""))
	var col := Color(String(m.get("color", "#ffffff")))
	var flash: float = float(mo["flash"])
	var mod := Color.WHITE.lerp(Color(2.2, 1.6, 1.6), flash)
	var ice: float = _frost_k(mo)
	if ice > 0.01:
		# 얼음이 짙은 만큼 몸이 식어 파래진다.
		mod = mod * Color.WHITE.lerp(Color(0.60, 0.84, 1.45), ice)
	var zap: float = _stun_k(mo)
	if zap > 0.01:
		# 감전된 만큼 몸이 하얗게 뜬다. 얼음과 반대로 **더 밝아진다** —
		# 둘이 겹쳐 걸릴 수 있으므로 색이 서로 반대 방향이어야 구별된다.
		mod = mod * Color.WHITE.lerp(Color(1.55, 1.42, 0.78), zap)
	# ★ 그림자는 **발밑**에 와야 한다. 스프라이트는 p.y + 0.30h 를 바닥선으로 그리는데
	#   그림자만 p.y 에 두면 발보다 0.30h 위에 깔려 스프라이트 뒤에 통째로 가려진다.
	var foot: float = p.y + mh * 0.30

	# 몸 전체를 기울이거나 늘리지 않는다. 실제 H3 프레임만 재생한다.
	var face := _face_of(mo, p)
	var clip := Anim.clip(m, "move")
	var phase := float(mo.get("motion_t", 0.0))
	if not clip.is_empty():
		phase += float(mo.get("motion_phase", 0.0)) * float(clip["total"]) / 1000.0
	var frame := Anim.frame_at(clip, phase)
	if effects_only:
		draw_set_transform(Vector2(p.x, foot) + _sh, 0.0, Vector2(1.0, 0.32))
		draw_circle(Vector2.ZERO, mh * 0.26, Color(0, 0, 0, 0.30))
		draw_set_transform(_sh, 0.0, Vector2.ONE)

		# 상태이상 그림도 모든 캐릭터의 뒤에서 그린다.
		if ice > 0.01:
			if not _fx_art("fx_ice_bg", p.x, foot, mh, ice * 0.88, 0.217, 60.0):
				_draw_frost_floor(p, foot, mh, ice)
				_draw_frost_spikes(p, foot, mh, ice, false)
		if zap > 0.01:
			_draw_stun_floor(p, foot, mh, zap)
		# 발밑 조각도 몸체 아래에서 그려 상태이상이 겹쳐도 캐릭터를 가리지 않는다.
		if ice > 0.01:
			if not _fx_art("fx_ice_fg", p.x, foot, mh, ice * 0.92, 0.06, 88.0):
				_draw_frost_spikes(p, foot, mh, ice, true)
				_draw_frost_glint(p, foot, mh, ice)
		if zap > 0.01:
			_draw_stun_arcs(p, foot, mh, zap)
		if float(mo["burn_t"]) > 0.0:
			_draw_burn(p, foot, mh)
		return
	draw_set_transform(Vector2(p.x, foot) + _sh, 0.0, Vector2(face, 1.0))
	if clip.is_empty():
		Art.draw_actor(self, art, col, mh, 0.0, 0.0, 1.0, mod)
	else:
		Anim.draw_frame(self, clip, frame, 0.0, 0.0, 1.0, mod)
	if ice > 0.01:
		var frost := Color(0.74, 0.94, 1.35, 0.36 * ice)
		if clip.is_empty():
			Art.draw_actor(self, art, col, mh, 0.0, 0.0, 1.0, frost)
		else:
			Anim.draw_frame(self, clip, frame, 0.0, 0.0, 1.0, frost)
	draw_set_transform(_sh, 0.0, Vector2.ONE)


## 타고 있는 몬스터. 발밑에서 불꽃 혀가 몇 가닥 올라온다.
##
## ★ 예전에는 몸 한가운데 붉은 점 하나였다. 몬스터가 예순 마리면 그 점이 무엇인지
##   아무도 몰랐고, 무엇보다 **불로 안 보였다.** 얼음(기둥)과 달리 화상은 표시가
##   없으면 초당 피해가 통째로 안 보이는 효과다.
## ★ 스프라이트 뒤에 그리며 발밑 3분의 1 높이에서 타오른다.
func _draw_burn(p: Vector2, foot: float, mh: float) -> void:
	for i in range(3):
		var a: float = float(i) * 2.1 + p.x * 0.03
		var x: float = p.x + (float(i) - 1.0) * mh * 0.20
		var y: float = foot - mh * 0.06
		var hgt: float = mh * (0.20 + 0.10 * sin(t * 14.0 + a))
		if hgt < 3.0:
			continue
		# ★ 그림이 있으면 불꽃 혀 **한 가닥짜리 그림을 세 번** 놓는다. 큰 것 한 장으로
		#   늘리면 세 가닥이 저마다 다른 박자로 흔들리는 것이 사라져서, 「탄다」가 아니라
		#   「고동친다」로 보인다. 그림은 36x48 에 내용이 칸을 꽉 채우므로 배율은 hgt/48
		#   이고, draw_at 은 발밑 기준이라 불꽃 밑동이 그대로 y 에 앉는다.
		if Art.draw_at(self, Roster.ART.get("fx_fire", ""), x, y, hgt / 48.0,
				Color(1, 1, 1, 0.92)):
			continue
		var w: float = mh * 0.075
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, y - hgt), Vector2(x + w, y - hgt * 0.35), Vector2(x, y),
			Vector2(x - w, y - hgt * 0.35)]), Color(1.0, 0.38, 0.06, 0.80))
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, y - hgt * 0.62), Vector2(x + w * 0.45, y - hgt * 0.2),
			Vector2(x, y - hgt * 0.02), Vector2(x - w * 0.45, y - hgt * 0.2)]),
			Color(1.0, 0.86, 0.35, 0.90))


## 상태이상 겉그림 한 장. **그림이 없으면 false** 를 돌려주고, 부르는 쪽이 예전 도형으로
## 그린다 — 그림이 없어도 게임은 돌아가야 한다(CLAUDE.md 18-1 과 같은 규칙).
##
##   k     짙기(0~1). 그대로 알파가 된다.
##   drop  발밑에서 얼마나 **내려** 앉힐지(키 대비). 바닥에 눕는 조각은 조금 내려야
##         타원의 한가운데가 발에 온다.
##   nat   그 그림의 「제 키」. 몬스터 키(mh)를 이것으로 나눠 배율을 낸다 — 그림마다
##         제 크기가 다르므로 여기 한 곳에서 맞춘다.
##
## ★ 부르는 쪽은 **걸음새 변환 밖**이어야 한다. 같이 기울이면 얼음이 몬스터를 따라
##   흔들려서 「얼어붙었다」가 아니라 「매달렸다」로 보인다(CLAUDE.md 10-2).
func _fx_art(id: String, cx: float, foot: float, mh: float, k: float, drop: float,
		nat: float) -> bool:
	return Art.draw_at(self, Roster.ART.get(id, ""), cx, foot + mh * drop, mh / nat,
				Color(1, 1, 1, clampf(k, 0.0, 1.0)))


# --------------------------------------------------------------------------- #
# 얼음 — 둔화에 걸린 몬스터
#
# ★ 아래 도형들은 이제 **그림(fx_ice_bg · fx_ice_fg)이 없을 때의 되돌림 길**이다.
#   지우지 마라 — 그림 없이도 게임이 돌아가야 하고(CLAUDE.md 18-1), 앞뒤로 나눈
#   깊이(바닥은 뒤 · 기둥 앞쪽은 앞)의 근거가 여기 주석에 남아 있다.
# --------------------------------------------------------------------------- #
## 지금 이 몬스터가 얼마나 얼어 있는가 (0~1).
##
## ★ 남은 시간과 **둔화의 세기**를 함께 담는다. 세기만 보면 0.15 짜리 약한 둔화도
##   0.30 짜리와 똑같이 새하얘지고, 시간만 보면 다 끝나는 순간까지 그대로 있다가
##   툭 사라진다. 둘을 곱해야 "약하게 걸렸다 / 이제 풀린다"가 눈으로 읽힌다.
func _frost_k(mo: Dictionary) -> float:
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
# 마비 — 전기에 감전된 몬스터
#
# 가는 금색 전류와 흰 중심선을 코드로 그린다. 검은 원형 받침은 사용하지 않는다.
# --------------------------------------------------------------------------- #
## 지금 이 몬스터가 얼마나 마비되어 있는가 (0~1).
##
## ★ 얼음(둔화)과 달리 **세기가 없다.** 마비는 걸리거나 안 걸리거나 둘뿐이라
##   남은 시간만 본다. 대신 끝나기 0.25초 전부터 옅어져서 툭 사라지지 않는다.
func _stun_k(mo: Dictionary) -> float:
	var st: float = float(mo.get("stun_t", 0.0))
	if st <= 0.0:
		return 0.0
	return clampf(st / 0.25, 0.0, 1.0)


## 배경 원반 없이 발 옆의 짧은 전류만 남긴다. 흰 중심선과 금색 잔광을 공유한다.
func _draw_stun_floor(p: Vector2, foot: float, mh: float, k: float) -> void:
	var ec := Balance.elem_color("elec")
	for side in [-1.0, 1.0]:
		var phase: float = t * 6.0 + side * 1.7 + p.x * 0.03
		var alpha := k * (0.45 + 0.25 * sin(phase))
		var c := Vector2(p.x + side * mh * 0.24, foot)
		var pts := PackedVector2Array([c + Vector2(side * mh * 0.23, 0), c + Vector2(side * mh * 0.12, -3), c + Vector2(side * mh * 0.05, 1), c + Vector2(0, -1)])
		draw_polyline(pts, Color(ec, alpha * 0.24), 4.0)
		draw_polyline(pts, Color(ec.lightened(0.45), alpha), 1.4)


## 짧은 아크 두 줄을 실루엣 양쪽에 번갈아 켠다. 얼굴과 체력바는 비워 둔다.
func _draw_stun_arcs(p: Vector2, foot: float, mh: float, k: float) -> void:
	var ec := Balance.elem_color("elec")
	for side in [-1.0, 1.0]:
		var phase: float = t * 8.0 + side * 2.3 + p.x * 0.03
		var pulse := 0.50 + 0.50 * sin(phase)
		var cx: float = p.x + side * mh * 0.37
		var cy := foot - mh * (0.56 if side < 0 else 0.34)
		var pts := PackedVector2Array([Vector2(cx, cy - mh * 0.18), Vector2(cx - side * mh * 0.07, cy - mh * 0.06), Vector2(cx + side * mh * 0.05, cy - mh * 0.02), Vector2(cx - side * mh * 0.04, cy + mh * 0.14)])
		var alpha := k * (0.38 + pulse * 0.48)
		draw_polyline(pts, Color(ec, alpha * 0.20), 5.0)
		draw_polyline(pts, Color(ec, alpha), 2.2)
		draw_polyline(pts, Color("#fff5d5", alpha), 1.0)
		if pulse > 0.78:
			var spark := pts[0] + Vector2(side * 3, -2)
			draw_line(spark - Vector2(2, 0), spark + Vector2(2, 0), Color("#fff5d5", alpha), 1)
			draw_line(spark - Vector2(0, 2), spark + Vector2(0, 2), Color("#fff5d5", alpha), 1)


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
		# 몬스터 자신의 속성만 붙인다.
		var bd := String(mo.get("body", ""))
		Look.draw_body(self, Vector2(p.x - w * 0.5 - 14.0, maxf(y + 3.5, 82)), 10, bd)


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
	# ★ 왼쪽 끝을 800 으로 물렸다(예전 596). 596 이면 정보띠의 **테마 이름과 약점/면역 칩**
	#   (x 700~880, y 34)을 통째로 덮는다 — 띠는 _draw_topbar 뒤에 그려지므로 이긴다.
	#   하필 보스탄에서만 「무엇에 약하고 무엇이 안 통하는가」가 화면에서 사라졌다.
	# 보스 체력은 상단 정보띠 아래에 두어 메뉴·배속 조작과 겹치지 않는다.
	var r := Rect2(236, 82, 360, 24)
	_hp_bar(r, hp, ghost)
	Look.text_center_out(self, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 12.0),
			"%s  %d%%" % [String(boss["m"].get("ko", "보스")), int(ceil(hp * 100.0))],
			20, Look.INK, Look.BG_DEEP, 2.0)


# --------------------------------------------------------------------------- #
# 탄 — 공격 속성마다 다른 모양
# --------------------------------------------------------------------------- #
## 날아가는 탄 한 무더기.
##
## ★ 몸 색은 **언제나 그 캐릭터의 색**이다(CLAUDE.md 4-2). 속성이 바꾸는 것은 모양과
##   꼬리와 흘리는 부스러기뿐이다. 색까지 속성으로 갈아 버리면 불 영웅 넷이 전부 같은
##   주황 점을 쏘게 되어, 캐릭터마다 색을 정해 둔 뜻이 통째로 사라진다.
## ★ **방식(kind)은 크기와 길이로 말한다** — 광역은 굵고 관통은 길다. 속성으로만 갈라
##   두면 "저게 뚫고 지나가는 탄인지"가 화면에서 사라진다.
## ★ 어느 것이든 한가운데에 밝은 심지를 남긴다. 몬스터 그림 위를 지날 때 심지가 없으면
##   탄이 통째로 묻힌다 — 예전에 반지름 5px 짜리 점 하나였을 때 실제로 그랬다.
func _draw_bullets() -> void:
	for b in sim.bullets:
		var col: Color = b["c"]
		var p: Vector2 = b["p"]
		var prev: Vector2 = b.get("prev", p)
		# ★ 속도가 0 이면 방향도 0 이 되고, 그 0 으로 만든 도형은 점 하나로 뭉쳐
		#   triangulation failed 가 프레임마다 쏟아진다(규칙 10번). 있을 법하지 않은
		#   일이지만 한 줄로 막을 수 있는 것을 열어 둘 이유가 없다.
		var dir: Vector2 = Vector2(b["v"]).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var kind := String(b["kind"])
		var src: int = int(b.get("src", -1))
		var tier := _source_tier(src)
		Fx.projectile_glow(self, p, prev, dir, col, tier, sim.elapsed)
		if src >= 0 and src < sim.heroes.size():
			var shot := Anim.clip(sim.heroes[src]["h"]["unit"], "shot")
			if not shot.is_empty():
				draw_set_transform(p + _sh, dir.angle(), Vector2.ONE)
				Anim.draw_frame(self, shot, Anim.frame_at(shot, sim.elapsed),
						0.0, 0.0, (0.42 if kind == "splash" else 0.32) * Fx.shot_scale(tier))
				draw_set_transform(_sh, 0.0, Vector2.ONE)
				continue
		# 광역은 굵게, 관통은 가늘고 길게.
		var big: float = 1.30 if kind == "splash" else (0.88 if kind == "pierce" else 1.0)
		big *= Fx.shot_scale(tier)
		var lng: float = 1.9 if kind == "pierce" else 1.0
		# 자리에서 뽑은 흔들림 씨앗. 매 프레임 달라지므로 불과 번개가 저절로 일렁인다.
		var sd: float = fmod(absf(p.x) * 0.37 + absf(p.y) * 0.21, TAU)
		match String(b.get("el", "none")):
			"fire":
				_bul_fire(p, prev, dir, col, big, lng, sd)
			"ice":
				_bul_ice(p, prev, dir, col, big, lng, sd)
			"elec":
				_bul_elec(p, prev, dir, col, big, sd)
			"water":
				_bul_water(p, prev, dir, col, big, lng)
			_:
				_bul_plain(p, prev, dir, col, big, kind)


## 지나온 자리에 남는 꼬리. 속성마다 색과 굵기만 다르고 셈은 같다.
func _bul_tail(p: Vector2, prev: Vector2, dir: Vector2, col: Color, w: float,
		back: float = 10.0) -> void:
	var a: Vector2 = prev - dir * back
	draw_line(a, p, Color(col.r, col.g, col.b, 0.26), w * 2.2, true)
	draw_line(a, p, Color(col.r, col.g, col.b, 0.62), w, true)


## 불 — 앞이 뾰족하고 뒤가 갈라지는 불덩이. 꼬리가 매 프레임 일렁인다.
func _bul_fire(p: Vector2, prev: Vector2, dir: Vector2, col: Color,
		big: float, lng: float, sd: float) -> void:
	var ec := Balance.elem_color("fire")
	_bul_tail(p, prev, dir, ec, 4.6 * big, 16.0)
	var s := Vector2(-dir.y, dir.x)
	var flick: float = 0.80 + 0.20 * sin(t * 34.0 + sd * 5.0)
	var l: float = 15.0 * big * lng
	var w: float = 7.0 * big
	# ★ 속성 색은 **몸 뒤에 두른 불빛**으로만 쓴다. 몸을 속성 색으로 칠하면 불 영웅
	#   다섯이 전부 같은 주황 덩이가 되어, 캐릭터마다 색을 정해 둔 뜻이 사라진다(10-5).
	draw_colored_polygon(PackedVector2Array([
		p + dir * l * 0.74,
		p + s * w * 0.86 - dir * l * 0.18,
		p - dir * l * (1.05 + 0.35 * flick),
		p - s * w * 0.86 - dir * l * 0.18]),
		Color(ec.r, ec.g, ec.b, 0.50))
	draw_colored_polygon(PackedVector2Array([
		p + dir * l * 0.60,
		p + s * w * 0.62 - dir * l * 0.18,
		p - dir * l * (0.85 + 0.35 * flick),
		p - s * w * 0.62 - dir * l * 0.18]),
		Color(col.r, col.g, col.b, 0.96))
	draw_circle(p + dir * l * 0.10, 3.2 * big, Color(1.0, 0.96, 0.80, 0.95))


## 얼음 — 각진 결정 하나. 뒤로 성에 부스러기를 흘린다.
## ★ 둥글게 그리면 물과 구별이 안 된다. 얼음은 **각**이 있어야 얼음으로 읽힌다
##   (fx.frost 의 마름모와 같은 이유다).
func _bul_ice(p: Vector2, prev: Vector2, dir: Vector2, col: Color,
		big: float, lng: float, sd: float) -> void:
	_bul_tail(p, prev, dir, Look.ICE_DEEP, 3.4 * big, 12.0)
	var s := Vector2(-dir.y, dir.x)
	var l: float = 13.0 * big * lng
	var w: float = 6.2 * big
	# 얼음빛은 **테두리와 한쪽 면**에만. 몸은 캐릭터 색이다(10-5).
	draw_colored_polygon(PackedVector2Array([
		p + dir * l * 1.14, p + s * w * 1.22, p - dir * l * 0.92, p - s * w * 1.22]),
		Color(Look.ICE_DEEP.r, Look.ICE_DEEP.g, Look.ICE_DEEP.b, 0.55))
	draw_colored_polygon(PackedVector2Array([
		p + dir * l, p + s * w, p - dir * l * 0.80, p - s * w]),
		Color(col.r, col.g, col.b, 0.96))
	# 한쪽 면만 밝게 — Look.draw_crystal 과 같은 수법이다. 납작한 마름모가 결정이 된다.
	draw_colored_polygon(PackedVector2Array([
		p + dir * l, p + s * w, p - dir * l * 0.80]),
		Color(Look.ICE.r, Look.ICE.g, Look.ICE.b, 0.42))
	draw_line(p - dir * l * 0.4, p + dir * l * 0.85, Color(1, 1, 1, 0.85), 1.8 * big, true)
	var fr: float = 2.2 * big
	draw_circle(p - dir * (13.0 + 4.0 * sin(sd * 3.0)) + s * (2.5 * sin(sd)), fr,
			Color(Look.ICE.r, Look.ICE.g, Look.ICE.b, 0.65))


## 전기 — 지그재그로 꺾인 꼬리에 네 갈래 불꽃 머리.
## ★ 꼬리를 곧게 두면 광선(fx.beam)과 구별이 안 된다. 꺾인 선이라야 "전기"로 읽힌다 —
##   연쇄 번개(fx.bolt)를 지그재그로 그리는 것과 같은 까닭이다.
func _bul_elec(p: Vector2, prev: Vector2, dir: Vector2, col: Color,
		big: float, sd: float) -> void:
	var ec := Balance.elem_color("elec")
	var s := Vector2(-dir.y, dir.x)
	var back: Vector2 = prev - dir * 16.0
	var pts := PackedVector2Array()
	for i in range(5):
		var k: float = float(i) / 4.0
		var off: float = 0.0
		if i > 0 and i < 4:
			off = sin(sd * 4.0 + float(i) * 2.3 + t * 47.0) * 5.5 * big
		pts.append(back.lerp(p, k) + s * off)
	draw_polyline(pts, Color(ec.r, ec.g, ec.b, 0.28), 6.5 * big, true)
	draw_polyline(pts, Color(col.r, col.g, col.b, 0.95), 2.8 * big, true)
	var r: float = 6.6 * big
	draw_colored_polygon(PackedVector2Array([
		p + dir * r * 1.75, p + s * r * 0.78, p - dir * r * 1.05, p - s * r * 0.78]),
		Color(ec.r, ec.g, ec.b, 0.45))
	draw_colored_polygon(PackedVector2Array([
		p + dir * r * 1.45, p + s * r * 0.55, p - dir * r * 0.85, p - s * r * 0.55]),
		Color(col.r, col.g, col.b, 0.96))
	draw_circle(p, 2.9 * big, Color(1, 1, 0.94, 0.95))


## 물 — 앞이 둥글고 뒤가 뾰족한 물방울. 위쪽에 빛점 하나.
func _bul_water(p: Vector2, prev: Vector2, dir: Vector2, col: Color,
		big: float, lng: float) -> void:
	var ec := Balance.elem_color("water")
	_bul_tail(p, prev, dir, ec, 4.0 * big, 12.0)
	var s := Vector2(-dir.y, dir.x)
	var l: float = 13.0 * big * lng
	var w: float = 6.6 * big
	var head: Vector2 = p + dir * l * 0.18
	# 물빛은 **바깥 빛무리**로만. 방울 몸은 캐릭터 색이다(10-5).
	draw_circle(head, w * 1.18, Color(ec.r, ec.g, ec.b, 0.42))
	draw_colored_polygon(PackedVector2Array([
		head + s * w * 0.66, p - dir * l, head - s * w * 0.66]),
		Color(col.r, col.g, col.b, 0.88))
	draw_circle(head, w * 0.92, Color(col.r, col.g, col.b, 0.96))
	draw_circle(head + dir * w * 0.24 - s * w * 0.28, 2.6 * big, Color(1, 1, 1, 0.92))


## 무상성 — 마법이 아닌 것들. 방식이 곧 생김새다: 포탄 · 화살 · 탄알.
func _bul_plain(p: Vector2, prev: Vector2, dir: Vector2, col: Color,
		big: float, kind: String) -> void:
	_bul_tail(p, prev, dir, col, 4.0 * big, 10.0)
	var s := Vector2(-dir.y, dir.x)
	match kind:
		"splash":
			# 포탄 — 묵직한 쇳덩이. 어두운 테두리가 있어야 납작한 원이 아니라 공으로 보인다.
			draw_circle(p, 10.2, Color(0.09, 0.08, 0.13, 0.85))
			draw_circle(p, 7.8, col)
			draw_circle(p - dir * 2.2 + s * 2.2, 2.9, Color(1, 1, 1, 0.72))
		"pierce":
			# 화살 — 촉 · 대 · 깃. 길어야 "뚫고 간다"가 읽힌다.
			var l: float = 17.0
			var tailp: Vector2 = p - dir * l * 1.45
			draw_line(tailp, p + dir * l * 0.2, Color(col.r, col.g, col.b, 0.95), 3.0, true)
			draw_colored_polygon(PackedVector2Array([
				p + dir * l * 0.58, p + s * 4.4 - dir * l * 0.12,
				p - s * 4.4 - dir * l * 0.12]), col)
			draw_line(p - dir * l * 0.1, p + dir * l * 0.5, Color(1, 1, 1, 0.85), 1.6, true)
			draw_line(tailp, tailp + dir * 5.0 + s * 4.2, Color(1, 1, 1, 0.45), 2.0, true)
			draw_line(tailp, tailp + dir * 5.0 - s * 4.2, Color(1, 1, 1, 0.45), 2.0, true)
		_:
			# 탄알 — 앞이 둥글고 뒤가 잘린 짧은 캡슐.
			var l2: float = 8.5
			draw_line(p - dir * l2, p + dir * l2 * 0.35,
					Color(col.r, col.g, col.b, 0.95), 6.4, true)
			draw_circle(p + dir * l2 * 0.35, 3.1, Color(1, 1, 0.96, 0.95))


func _draw_topbar() -> void:
	var th := _theme()
	var title := ("보스 · " if Balance.is_boss_wave(Run.wave) else "") + String(th.get("ko", ""))
	Hud.topbar(self, "%d탄" % Run.wave, Look.INK if Run.lives > 5 else Look.RED,
		Hud.INFO_SIZE, title, Look.RED if Balance.is_boss_wave(Run.wave) else Look.INK_DIM)
	_draw_speed()


## 배속 단추 셋. 위쪽 띠의 메뉴 바로 왼쪽이다.
##
## ★ 사용자가 정한 것: 「배속설정은 상단으로 올리고」. 예전에는 오른쪽 정보판 **맨 아래**
##   (y 750)에 있었다 — 화면에서 가장 먼 구석이라 손이 매번 거기까지 내려가야 했고,
##   그만큼 세 막대가 쓸 세로를 먹었다.
## ★ id 는 그대로 `sp1`·`sp2`·`sp3` 다 — tests/play_check 가 그 이름으로 눌러 본다
##   (자리는 안 본다. Ui 가 그리면서 등록하기 때문이다 — CLAUDE.md 7번).
const SPD_W := 50.0
const SPD_GAP := 6.0
const SPD_X := Hud.MENU_RECT.position.x - 16.0 - SPD_W * 3.0 - SPD_GAP * 2.0

func _draw_speed() -> void:
	for i in range(3):
		var sp := float(i + 1)
		var r := Rect2(SPD_X + float(i) * (SPD_W + SPD_GAP), 17.0, SPD_W, 34.0)
		# ★ '×'(U+00D7) 는 번들 폰트에 없다. 한글로 쓴다.
		ui.button(self, r, "%d배" % int(sp), "sp%d" % int(sp), true,
				Look.GOLD if is_equal_approx(speed, sp) else Look.PANEL_EDGE, 21)


## 오른쪽 정보판.
##
## ★ 사용자가 정한 것(두 번에 걸쳐):
##   1. 「인겜에서 우측 패널을 캐릭별 실시간 준 데미지를 바로 쌓아 주는 걸로 가득 채우자.
##      대신 두 배로 준 데미지, 일반 데미지, 반감 데미지 세 막대로」
##   2. 「최대값을 해당탄 전체 몬스터 HP합으로해서 누적치를 Normalize해서 누적되는방식으로」
## ★ 2번이 바꾼 것: 예전에는 막대의 자가 **그 탄에서 가장 큰 통 하나**였다. 그래서 막대는
##   「누가 제일 많이 때렸나」만 말했고, **얼마나 남았나**는 한 톨도 말하지 못했다 —
##   여섯이 고르게 나눠 가진 탄이나 하나가 다 한 탄이나 제일 긴 막대는 늘 꽉 찼다.
##   지금 자는 **이번 탄 몬스터 체력의 합**(sim.total_hp)이라 막대 길이가 곧 「이 영웅이
##   이 탄의 몇 할을 깎았나」이고, 여섯 줄을 다 더하면 그것이 곧 전투의 진행도다.
##   그래서 맨 위에 팀 합계 막대를 한 줄 두어 그 자를 눈에 보이게 한다.
## ★ 세 통을 **한 막대에 이어 붙인다**(누적). 따로 세 줄로 두면 같은 자를 세 번 그리는
##   셈이라 줄마다 길이가 짧아져 「이 영웅이 이 탄의 몇 할인가」가 안 읽혔다.
## ★ 그 자가 참말이려면 **넘겨 죽인 몫이 안 세어져야 한다** — BattleSim._hurt 가 남은
##   체력까지만 깎고, 화상 도트도 붙인 영웅 몫으로 센다. 안 그러면 막대가 자를 넘는다.
## ★ 크리스탈 줄을 여기서 뺐다. 위쪽 정보띠에 이미 「20 / 20」이 있고, 제단에도 스무
##   개가 놓여 있다 — 같은 것을 한 화면에 세 번 적을 자리가 아니다.
## ★ 배속 단추는 **위쪽 띠로 갔다**(_draw_speed). 여기 맨 아래에는 패시브만 남는다.
func _draw_panel() -> void:
	var x := PANEL_X
	Look.material_panel(self, Rect2(x, 68, 1280 - x, 800 - 68), Look.PANEL, Look.PANEL_EDGE)
	draw_rect(Rect2(x, 68, 2, 800 - 68), Look.PANEL_EDGE)
	var x0: float = x + 20.0
	var w: float = 1280.0 - x - 40.0
	var right: float = x0 + w

	# --- 누적 피해 (이 판의 본체) ---
	# 막대의 자. **이번 탄에 걸어 들어오는 몬스터 체력의 합** 하나뿐이다 —
	# 팀 막대도 영웅 여섯 줄도 전부 이 자로 잰다. 줄마다 따로 재면 막대 길이를
	# 영웅끼리 비교할 수 없게 되는데, 그 비교가 이 판의 전부다.
	var denom: float = maxf(1.0, sim.total_hp)
	var tw3 := [0.0, 0.0, 0.0]
	var tot := 0.0
	for he in sim.heroes:
		tot += float(he.get("dmg", 0.0))
		for k in range(3):
			tw3[k] = float(tw3[k]) + float(he.get(DMG_KEYS[k], 0.0))
	# 두 토막을 가르는 실 — 없으면 위의 「남은 몬스터」와 아래의 막대가 한 덩어리로 붙는다.
	Look.text_left(self, Vector2(x0, 98), "누적 피해", 21, Look.INK_DIM)
	# 분모를 **글자로도** 적는다. 막대만 두면 「무엇에 대한 몇 할인가」를 알 길이 없다.
	Look.text_right(self, Vector2(right, 98), "%s / %s"
			% [Fx._short_num(tot), Fx._short_num(sim.total_hp)], 20, Look.GOLD)
	# 팀 합계 막대 — 이 한 줄이 곧 「이번 탄을 얼마나 깎았나」다.
	_stack_bar(Rect2(x0, 121, w - 54.0, 18.0), tw3, denom)
	Look.text_right(self, Vector2(right, 130), "%d%%"
			% int(round(clampf(tot / denom, 0.0, 1.0) * 100.0)), 20, Look.INK)
	# 범례 — 세 토막이 무엇인지를 **한 번만** 적는다. 줄마다 크게 적으면 여섯 번 반복된다.
	var lx: float = x0
	for k2 in range(3):
		draw_rect(Rect2(lx, 158.0, 12, 12), DMG_COL[k2])
		Look.text_left(self, Vector2(lx + 17.0, 164), DMG_KO[k2], 18, Look.INK_DIM)
		lx += 17.0 + Look.text_width(DMG_KO[k2], 18) + 16.0

	# --- 맨 아래 한 줄: 지금 걸려 있는 패시브. 전투 중에는 바꿀 수 없으니 보여 주기만 한다. ---
	var pv_y := 754.0
	if not Run.passives.is_empty():
		Look.text_left(self, Vector2(x0, pv_y), "패시브", 17, Look.INK_DIM)
		var px0: float = x0 + 66.0
		# ★ 이름까지 다 들어가는가를 **먼저 재 본다.** 이름이 여섯 자인 것이 셋 있고
		#   (「처형인의 눈」·「도박꾼의 눈」·「마무리 일격」), 그 셋이 걸리면 줄이 정보판을
		#   28px 넘어 화면 밖으로 흘러나간다. 안 들어가면 문양만 늘어놓는다 —
		#   전투 중에는 패시브를 바꿀 수 없으니 「무엇이 걸려 있나」만 보이면 된다.
		var need := 0.0
		for pid0 in Run.passives:
			need += 44.0 + Look.text_width(
					String(Balance.passive_by_id(String(pid0)).get("ko", "")), 14)
		var with_name: bool = px0 + need <= right
		var pxx: float = px0
		for pid in Run.passives:
			var pp := Balance.passive_by_id(String(pid))
			var tint := Color(String(pp.get("tint", "#f6c445")))
			Look.draw_passive_icon(self, Vector2(pxx + 13.0, pv_y), 13.0, pp, tint)
			if with_name:
				Look.text_left(self, Vector2(pxx + 30.0, pv_y),
						String(pp.get("ko", "")), 14, Look.INK_DIM)
				pxx += 44.0 + Look.text_width(String(pp.get("ko", "")), 14)
			else:
				pxx += 32.0

	_draw_dmg_list(x0, 190.0, w, pv_y - 20.0, denom)


## 상성별 세 토막을 **한 막대에 이어 붙인다** — 2배 · 보통 · 반감 차례로.
##
## ★ **뒤에서부터 그린다.** 「합계까지」를 반감 색으로 먼저 깔고, 그 위에 「2배+보통까지」를,
##   맨 위에 「2배까지」를 덮는다. 토막마다 따로 그리면 둥근 끝이 경계마다 생겨서 막대가
##   알약 세 개로 끊어져 보인다.
## ★ 0 으로 줄어드는 도형에 draw_colored_polygon 을 부르지 않는다(CLAUDE.md 10번).
## ★ 빈 홈(track)의 색을 받는다. 자가 **이번 탄 전체 체력**이라 영웅 한 명의 막대는
##   길어야 홈의 5분의 1이다 — 홈이 안 보이면 막대가 허공에 뜬 알약으로 보이고,
##   그러면 「전체의 몇 할인가」가 통째로 안 읽힌다. 어두운 줄(BG_DEEP) 위에서는
##   홈을 밝게(PANEL), 밝은 판(PANEL) 위에서는 어둡게(BG_DEEP) 깐다.
func _stack_bar(rect: Rect2, v3: Array, denom: float, track: Color = Look.BG_DEEP) -> void:
	Look.fill_round(self, rect, rect.size.y * 0.5, track)
	var acc := 0.0
	var ends := [0.0, 0.0, 0.0]
	for k in range(3):
		acc += maxf(0.0, float(v3[k]))
		ends[k] = acc
	for k2 in range(2, -1, -1):
		var kk: float = clampf(float(ends[k2]) / denom, 0.0, 1.0)
		var ww: float = rect.size.x * kk
		if ww <= 1.0:
			continue
		Look.fill_round(self, Rect2(rect.position, Vector2(ww, rect.size.y)),
				rect.size.y * 0.5, DMG_COL[k2])


## 영웅마다 한 줄. 얼굴 · 이름 · 등급 · 합계, 그리고 **상성을 이어 붙인 막대 하나**.
##
## ★ 전장에 선 차례 그대로 그린다. 피해 순으로 세우면 값이 매 프레임 바뀌므로 줄이
##   전투 내내 자리를 바꿔서, 「내 두 번째 영웅」을 눈으로 못 쫓는다. 정렬은 탄이
##   끝난 뒤 전과 판에서 한 번만 한다(그때는 값이 멎어 있다).
## ★ 칸 높이를 남은 자리에 맞춰 늘린다. 1탄에는 영웅이 하나뿐인데 88px 줄 하나만
##   그리면 정보판이 통째로 비어 보인다 — 「가득 채우자」가 그 말이었다.
func _draw_dmg_list(x0: float, top: float, w: float, bot: float, denom: float) -> void:
	var n: int = sim.heroes.size()
	# ★ 자리를 **언제나 여섯 개** 깐다. 선 사람 수로 나누면 1탄에는 120px 줄 하나만 있고
	#   그 밑이 통째로 비며, 영웅이 늘 때마다 줄 높이가 달라져서 「내 두 번째 영웅」이
	#   탄마다 다른 자리에 온다. 빈 자리를 그대로 보여 주는 편이 「한 명 더 세울 수 있다」도
	#   같이 말해 준다.
	var slots: int = maxi(6, n)
	var rh: float = clampf((bot - top) / float(slots), 36.0, 120.0)
	var y: float = top
	for i in range(slots):
		if y + rh > bot + 0.5:
			break
		var rr := Rect2(x0, y, w, rh - 3.0)
		if i < n:
			_draw_dmg_row(rr, sim.heroes[i], denom)
			ui.zone(rr, "hero:%d" % i)
		else:
			Look.fill_round(self, rr, 8.0, Color(Look.BG_DEEP.r, Look.BG_DEEP.g,
					Look.BG_DEEP.b, 0.5))
			Look.text_center(self, rr.position + rr.size * 0.5, "빈 자리", 18,
					Look.INK_DIM.darkened(0.45))
		y += rh


func _draw_dmg_row(rr: Rect2, he: Dictionary, denom: float) -> void:
	var h: Dictionary = he["h"]
	var u: Dictionary = h["unit"]
	var tier: int = int(h["tier"])
	var tc := Look.tier_color(tier)
	Look.fill_round(self, rr, 8.0, Look.BG_DEEP)
	draw_rect(Rect2(rr.position, Vector2(5.0, rr.size.y)), tc)

	# 얼굴 — 칸 왼쪽. **Art.draw_unit** 이라야 그림 크기 보정(sc)이 들어간다(CLAUDE.md 4-1).
	var fh: float = clampf(rr.size.y - 20.0, 30.0, 84.0)
	Art.draw_unit_fit(self, u, Rect2(rr.position.x + 8, rr.end.y - fh - 4, 54, fh))

	var tx: float = rr.position.x + 68.0
	var right: float = rr.position.x + rr.size.x - 10.0
	var ty: float = rr.position.y + 17.0
	# 속성 — 막대가 **무엇으로** 2배를 냈는지는 여기서만 읽힌다.
	Look.draw_elem(self, Vector2(tx + 10.0, ty), 9.0, String(u.get("elem", "none")))
	var tot: float = float(he.get("dmg", 0.0))
	var ts := Fx._short_num(tot)
	var tw: float = Look.text_width(ts, 22)
	Look.text_right(self, Vector2(right, ty), ts, 22, Look.GOLD)

	var nm := Look.unit_name(u)
	var nn: int = int(h.get("n", 1))
	if nn > 1:
		nm += "  x%d" % nn
	var nx0: float = tx + 24.0
	var nx1: float = right - tw - 14.0
	Look.text_center_fit(self, Vector2((nx0 + nx1) * 0.5, ty), nm, 20,
			Look.GOLD if nn > 1 else Look.INK, maxf(20.0, nx1 - nx0), 17)

	# --- 막대 하나: 2배 · 보통 · 반감을 이어 붙인다 ---
	# ★ 셋을 합치면 합계(dmg)와 정확히 같고, 자는 **이번 탄 몬스터 체력의 합**이다.
	#   그래서 막대 길이가 곧 「이 영웅이 이 탄의 몇 할을 깎았나」다. 면역(0배)은
	#   피해가 0 이라 어디에도 안 쌓인다 — 「무효」는 투기장의 글자가 따로 말한다.
	var v3 := [float(he.get(DMG_KEYS[0], 0.0)), float(he.get(DMG_KEYS[1], 0.0)),
			float(he.get(DMG_KEYS[2], 0.0))]
	var bh: float = clampf(rr.size.y * 0.18, 5.0, 16.0)
	var by: float = rr.position.y + minf(31.0, rr.size.y - bh - 3.0)
	var trk1: float = right - 46.0
	_stack_bar(Rect2(tx, by, trk1 - tx, bh), v3, denom, Look.PANEL.lightened(0.06))
	Look.text_right(self, Vector2(right, by + bh * 0.5), "%d%%"
			% int(round(clampf(tot / denom, 0.0, 1.0) * 100.0)), 16,
			Look.INK if tot > 0.5 else Look.INK_DIM.darkened(0.35))

	# 토막마다의 숫자. 막대는 **몫**을 말하고 이 줄이 **값**을 말한다 — 둘 다 있어야
	# 「반감으로 열 대」와 「약점으로 두 대」가 갈린다.
	var ny: float = by + bh + 13.0
	if ny <= rr.position.y + rr.size.y - 4.0:
		var nx: float = tx
		for k in range(3):
			var v: float = float(v3[k])
			var col: Color = DMG_COL[k] if v > 0.5 else Look.INK_DIM
			var lab := "%s %s" % [DMG_KO[k], Fx._short_num(v)]
			Look.text_left(self, Vector2(nx, ny), lab, 16, col)
			nx += Look.text_width(lab, 16) + 14.0


# --------------------------------------------------------------------------- #
# 라운드 전과 — 누가 얼마나 일했는가
# --------------------------------------------------------------------------- #
## 사용자가 정한 것: 「라운드 끝날 때마다 캐릭터별 처치수 & 데미지를 이쁘게 팝업」.
##
## ★ 왜 값어치가 있는가: 이 게임에서 제일 어려운 선택이 「여섯 중 누구를 물릴까」다.
##   그런데 예전 결과 상자는 잡은 수와 골드 합계뿐이라, **누가 일했는지**를 알 길이
##   없었다. 상성이 맞은 영웅과 헛돈 영웅이 화면에서 똑같이 생겼던 셈이다.
## ★ 막대는 **가장 많이 때린 영웅을 1 로** 잡는다. 전체 합으로 잡으면 여섯이 고르게
##   나눠 가진 판에서 막대가 전부 짧아 아무것도 안 읽힌다.
func _draw_result() -> void:
	var alpha := clampf(end_t / 0.3, 0, 1)
	draw_rect(Look.SCREEN, Color(0, 0, 0, alpha * 0.78))
	var columns := 2 if sim.heroes.size() > 6 else 1
	var count := maxi(1, ceili(float(sim.heroes.size()) / columns))
	var height := maxf(388, 240 + count * 60)
	var box := Rect2(190, (800 - height) * 0.5, 900, height)
	Look.material_panel(self, box, Look.PANEL, Look.GOLD_DEEP)
	Look.text_left(self, box.position + Vector2(30, 40), "전투 결과", 38, Look.INK)
	Look.text_right(self, Vector2(box.end.x - 30, box.position.y + 40), "%d탄" % Run.wave, 24, Look.INK_DIM)
	Look.text_left(self, box.position + Vector2(30, 88), "전투 기록", 22, Look.INK_DIM)
	Look.text_right(self, Vector2(box.end.x - 30, box.position.y + 88), "피해량", 20, Look.INK_DIM)
	var rows := sim.heroes.duplicate()
	rows.sort_custom(func(a, b): return float(a.get("dmg", 0)) > float(b.get("dmg", 0)))
	var best := 1.0
	var total := 0.0
	for he in rows:
		best = maxf(best, float(he.get("dmg", 0)))
		total += float(he.get("dmg", 0))
	var width := (box.size.x - 60 - (columns - 1) * 12) / columns
	for i in range(rows.size()):
		var he: Dictionary = rows[i]
		var hero: Dictionary = he["h"]
		var unit: Dictionary = hero["unit"]
		var tier := int(hero["tier"])
		var dmg := float(he.get("dmg", 0))
		var row := Rect2(box.position + Vector2(30 + (i % columns) * (width + 12), 112 + (i / columns) * 60), Vector2(width, 54))
		Look.fill_round(self, row, 5, Look.BG_DEEP)
		if dmg > 0:
			Look.fill_round(self, Rect2(row.position, Vector2(row.size.x * dmg / best, row.size.y)), 5, Color(Look.tier_color(tier), 0.15))
		Art.draw_unit_fit(self, unit, Rect2(row.position + Vector2(8, 3), Vector2(53, 48)))
		Look.draw_elem(self, row.position + Vector2(75, 25), 10, String(unit.get("elem", "none")))
		var name_width := width - 198
		Look.text_center_fit(self, row.position + Vector2(94 + name_width * 0.5, 18), Look.unit_name(unit), 22, Look.INK, name_width, 15)
		Look.draw_rarity_fit(self, Rect2(row.position + Vector2(94, 34), Vector2(100, 17)), tier, 4.5)
		Look.text_right(self, Vector2(row.end.x - 14, row.position.y + 18), Fx._short_num(dmg), 24, Look.GOLD)
		Look.text_right(self, Vector2(row.end.x - 14, row.position.y + 40), "%d%%" % int(round(dmg * 100 / maxf(total, 1))), 16, Look.INK_DIM)
	var fy := box.end.y - 108
	for i in range(2):
		var r := Rect2(box.position.x + 30 + i * 426, fy, 414, 60)
		Look.material_panel(self, r, Look.BG_DEEP, Look.PANEL_EDGE)
		if i == 0:
			Look.draw_crystal(self, r.position + Vector2(25, 30), 12, true)
			Look.text_left(self, r.position + Vector2(50, 30), "잃어버린 크리스탈", 21, Look.INK_DIM)
			Look.text_right(self, Vector2(r.end.x - 18, r.get_center().y), str(_lost), 29, Look.CRYSTAL)
		else:
			Look.text_left(self, r.position + Vector2(18, 30), "최종 획득 Gold", 21, Look.INK_DIM)
			Look.text_right(self, Vector2(r.end.x - 18, r.get_center().y), str(sim.gold + _bonus), 29, Look.GOLD)
	Look.text_center(self, Vector2(640, box.end.y - 24), "화면을 터치하여 계속", 20, Look.INK_DIM)
