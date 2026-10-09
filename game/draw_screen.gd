extends Node2D
class_name DrawScreen

## 별맞춤 의식 — 별 다섯을 돌리고, 문 밖의 별만 다시 돌리고, 확정해 영웅을 부르는 화면.
##
## 규칙(사용자가 정한 것 · core/rite.gd):
##  - 탄마다 생명 수정 둘레의 별 다섯이 한 번 돈다. **빛의 문 안에 든 별의 수가 곧 등급**이다.
##  - 맘에 안 들면 **문 밖의 별만** 다시 돌린다. 무료 횟수를 다 쓰면 골드를 낸다(두 배씩 오른다).
##  - 확정하면 그 등급의 영웅이 쉰 명 중에서 **무작위로** 나온다. 4성부터 연출이 화려해진다.
##
## ★ **결과는 Run.orbit 이 이미 정했다.** 여기서 별이 도는 것은 연출이고, 멈추는 자리는
##   언제나 Rite.angle(ring, Run.orbit[ring]) 이다 — 손으로 멈추는 타이밍 게임이 아니다.
##   그래서 도는 중에도 단추는 바로 듣는다(누르면 별을 제자리에 세우고 처리한다).
## ★ 판은 game/rite_board.gd 가 그린다. 문의 폭 · 별의 자리는 전부 Rite 의 함수에서 온다.

enum { PICK, REVEAL, SWAP }

## 의식판의 한가운데. 큰 판 하나가 이 화면의 주인이다.
const BOARD := Vector2(640, 400)
## 확정 연출에서 영웅이 터져 나오는 자리(원화 한가운데).
const HERO_AT := Vector2(414, 438)
## 판을 놓는 밤하늘 판과 그 양옆의 읽을거리.
const SKY := Rect2(72, 92, 1136, 600)
const LEFT := Rect2(96, 128, 264, 528)       ## 문 안의 별 — 지금 몇 성인가
const RIGHT := Rect2(920, 128, 264, 528)     ## 별마다 문에 들 확률
const RESPIN_RECT := Rect2(230, 702, 380, 68)
const GO_RECT := Rect2(642, 702, 408, 68)

## 화면에 들어와 첫 별이 멈추기까지. 화면 전환의 페이드(0.28초)가 걷히는 시간을 품는다.
const ENTRY_FIRST := 0.70
## 다시 돌렸을 때 첫 별이 멈추기까지.
const RESPIN_FIRST := 0.42
## 별과 별 사이. 안쪽 별부터 멈추고, 문이 가장 좁은 바깥 별이 마지막이라 긴장이 끝에 온다.
## ★ 다섯이 다 서는 데 1.7초 안쪽이다. 한 판에 백 번 보는 화면이라 더 끌면 고문이다.
const STOP_GAP := 0.24
const JOKER_SEC := 0.40
## 별이 잠기는 번쩍임이 가시는 시간.
const LOCK_SEC := 0.45
## 확정한 뒤 영웅이 터져 나오는 시각. 4성부터는 조금 더 끈다(showy).
const BURST_AT := 1.35
const BURST_SHOWY := 1.65
## 터진 뒤 등급 별이 하나씩 박히는 박자.
const STAR_IN_FIRST := 0.14
const STAR_IN_GAP := 0.09

var main = null
var ui := Ui.new()
var fx := Fx.new()
## 확정 연출이 끝나면 **탄마다** 뜨는 편성 판. 상점의 「영웅」 탭과 같은 것이다.
var hv := HeroView.new()
var formation := FormationView.new()
var fusion := FusionView.new()
var formation_tab := true

var state: int = PICK
var t: float = 0.0
var rt: float = 0.0              ## 확정 뒤 흐른 시간
var result: Dictionary = {}
var showy: bool = false
var _fired: Dictionary = {}      ## 연출 중 한 번만 터뜨릴 것들
## ★ 전투로 넘어가는 중인가. 페이드가 도는 0.28초 동안에도 이 화면은 트리에 남아
##   _input 을 받는다. 예전에는 state 를 PICK 으로 되돌려 막았는데, 그러면 뽑기 화면이
##   다시 그려져서 「결정!」을 한 번 더 누를 수 있었고 **영웅이 공짜로 하나 더 생겼다.**
var _leaving: bool = false

## 이번 프레임의 흔들림 오프셋. battle_screen 의 _sh 와 같은 이유다 —
## draw_set_transform 을 되돌릴 때 Vector2.ZERO 로 되돌리면 흔들림이 날아간다.
var _sh: Vector2 = Vector2.ZERO

## 별마다의 움직임. **비어 있으면 그 별은 Run.orbit 의 제자리에 멈춰 서 있다.**
##   {"from": 시작 각, "to": 끝 각(바퀴 수까지 풀어 쓴 값), "t0": 시작 시각, "dur": 초}
var _move: Array[Dictionary] = []
## 별이 멈춘 시각. 잠기는 순간의 번쩍임에 쓴다.
var _landed: Array[float] = []
## 확정 직전의 별 자리. 조커가 끌어온 별이 어디서 왔는지 연출이 안다.
var _before: Array[int] = []
## 문 안의 별 수가 마지막으로 바뀐 시각 — 왼쪽 판의 별과 등급 글자가 그때 튄다.
var _tally: int = 0
var _tally_t: float = -9.0


func _init() -> void:
	for ring in range(Rite.RINGS):
		_move.append({})
		_landed.append(-9.0)


func _ready() -> void:
	set_process(true)
	# ★ 이미 확정한 탄을 이어 하는 경우 — 연출은 건너뛰고 **편성 판부터** 연다.
	#   영웅은 이미 받았으므로 뽑기 화면을 다시 띄우면 「결정!」을 한 번 더 누르게 되고,
	#   그것이 곧 영웅 복제다. 그렇다고 전투로 바로 보내면 그 탄만 편성 판이 없어진다
	#   (CLAUDE.md 2-1: 편성 판은 **탄마다** 뜬다).
	if Run.phase == Run.Phase.SWAP and not Run.last_result.is_empty():
		result = Run.last_result
		showy = bool(result.get("showy", false))
		state = SWAP
		hv.new_id = String((result.get("unit", {}) as Dictionary).get("id", ""))
		_focus_latest()
	elif Rite.valid(Run.orbit):
		# 별이 돌다가 Run.orbit 의 자리에 차례로 멈춘다. 이어하기로 들어와도 같은 자리다.
		_spin(_all_rings(), [])


# --------------------------------------------------------------------------- #
# 별의 움직임 — 자리는 Run.orbit 이 정했고 여기는 거기까지 가는 길만 짓는다
# --------------------------------------------------------------------------- #
func _all_rings() -> Array[int]:
	var out: Array[int] = []
	for ring in range(Rite.RINGS):
		out.append(ring)
	return out


## 별들을 돌린다. `was` 가 비어 있으면 화면에 들어올 때의 첫 회전이고, 아니면 다시 돌리기다
## (그 별이 서 있던 각에서 출발한다). 궤도마다 도는 쪽이 엇갈려 관측의처럼 보인다.
func _spin(rings: Array[int], was: Array[float]) -> void:
	var entry := was.is_empty()
	var order := 0
	for ring in rings:
		var to := Rite.angle(ring, Run.orbit[ring])
		var dir := 1.0 if ring % 2 == 0 else -1.0
		var turns := 1.0 + 0.3 * float(order)
		var from := to - dir * TAU * turns
		if not entry:
			# 서 있던 자리에서 출발해 turns 바퀴를 넘겨 돈 뒤에 새 자리에 선다.
			from = was[ring]
			var rest := fposmod((to - from) * dir, TAU)
			to = from + dir * (rest + TAU * ceilf(maxf(0.0, turns - rest / TAU)))
		_move[ring] = {"from": from, "to": to, "t0": t,
				"dur": (ENTRY_FIRST if entry else RESPIN_FIRST) + STOP_GAP * float(order)}
		order += 1
	if order > 0:
		Sfx.play("flip")


func _spinning() -> bool:
	for move in _move:
		if not move.is_empty():
			return true
	return false


func _pos(ring: int) -> int:
	return int(Run.orbit[ring]) if ring < Run.orbit.size() else 0


## 그 별을 지금 그릴 각. 멈춰 선 별은 언제나 Run.orbit 의 제자리다 — 화면이 따로 기억하지 않는다.
func _angle(ring: int) -> float:
	var move: Dictionary = _move[ring]
	if move.is_empty():
		return Rite.angle(ring, _pos(ring))
	var k := clampf((t - float(move["t0"])) / float(move["dur"]), 0.0, 1.0)
	# 도는 별은 끝으로 갈수록 느려져 문 앞에서 기어간다.
	var eased := 1.0 - pow(1.0 - k, 3.0)
	return lerpf(float(move["from"]), float(move["to"]), eased)


## 그 별이 방금 지나온 각 — 꼬리의 길이다. 빠를수록 길고, 멈출 즈음에는 없어진다.
func _sweep(ring: int) -> float:
	var move: Dictionary = _move[ring]
	if move.is_empty():
		return 0.0
	var k := clampf((t - float(move["t0"])) / float(move["dur"]), 0.0, 1.0)
	var slope := 3.0 * pow(1.0 - k, 2.0)
	return clampf((float(move["to"]) - float(move["from"])) * slope / float(move["dur"]) * 0.055, -1.3, 1.3)


## 그 별의 지금 모습. 도는 별은 문 안으로 치지 않는다.
func _look(ring: int) -> int:
	if not _move[ring].is_empty():
		return RiteBoard.SPIN
	if not Rite.valid(Run.orbit):
		return RiteBoard.OUT
	return RiteBoard.look_of(ring, _pos(ring))


## 지금 화면에서 문 안에 **선** 별의 수. 도는 별은 멈춘 뒤에야 센다 — 그래서 별이 하나씩 찬다.
func _shown_stars() -> int:
	var n := 0
	for ring in range(Rite.RINGS):
		if _look(ring) in [RiteBoard.IN, RiteBoard.HELD]:
			n += 1
	return n


## 별 하나가 멈췄다. 문 안이면 잠기는 소리가 별 수만큼 높아진다 — 몇 번째 별인지 귀로도 세어진다.
func _land(ring: int, quiet: bool = false) -> void:
	_move[ring] = {}
	_landed[ring] = t
	if not Rite.valid(Run.orbit):
		return
	var at := RiteBoard.slot_point(BOARD, ring, _pos(ring))
	if Rite.in_gate(ring, _pos(ring)):
		fx.ring(at, Look.GOLD, 12.0, 46.0, 0.42, 3.0)
		fx.burst(at, Look.GOLD.lightened(0.3), 8, 150.0, 0.45, 3.0, 60.0)
		if not quiet:
			Sfx.force("block", -5.0, 0.84 + 0.12 * float(_shown_stars()))
	elif not quiet:
		Sfx.play("button", -16.0, 0.75)


## 도는 별을 전부 제자리에 세운다. **연출은 언제든 넘길 수 있어야 한다** — 백 탄을 도는
## 게임에서 못 넘기는 연출은 고문이다.
func skip_spin() -> void:
	var any := false
	for ring in range(Rite.RINGS):
		if not _move[ring].is_empty():
			_land(ring, true)
			any = true
	if any:
		Sfx.play("block", -6.0, 0.84 + 0.12 * float(_shown_stars()))


func _step_stars() -> void:
	for ring in range(Rite.RINGS):
		var move: Dictionary = _move[ring]
		if not move.is_empty() and t >= float(move["t0"]) + float(move["dur"]):
			_land(ring)
	var shown := _shown_stars()
	if shown != _tally:
		_tally = shown
		_tally_t = t


func _process(dt: float) -> void:
	t += dt
	fusion.update(dt)
	fx.update(dt)
	hv.update(dt)
	if state == PICK:
		_step_stars()
	if state == REVEAL:
		rt += dt
		_reveal_beats()
	queue_redraw()


# --------------------------------------------------------------------------- #
# 입력
# --------------------------------------------------------------------------- #
## ★ 편성 판은 **끌어서 굴린다.** 그래서 누르는 순간에 바로 처리하면 안 된다 —
##   목록을 굴리려고 손을 댄 자리의 영웅이 골라져 버린다. 눌렀다(press) · 움직였다
##   (motion) · 뗐다(release) 를 판에 그대로 넘기고, 판이 "굴린 것인지 고른 것인지"를
##   정한다(HeroView.release).
func _input(e: InputEvent) -> void:
	if _leaving:
		return
	if hv.info >= 0:
		hv.input(e, ui)
		if hv.info < 0 and hv.sel >= 0:
			formation_tab = false
		return
	if fusion.input(e, ui):
		return
	if state == SWAP:
		_swap_input(e)
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if state == REVEAL:
		# 연출은 언제든 넘길 수 있어야 한다. 100탄을 도는 게임에서 못 넘기는 연출은 고문이다.
		if rt > 0.7:
			_after_reveal()
		return
	# 의식판 — 단추 둘은 별이 도는 중에도 바로 듣는다. 빈 자리를 누르면 도는 별만 세운다.
	match ui.hit(e.position):
		"go":
			Sfx.play("button")
			_confirm()
		"rite:respin":
			_respin()
		_:
			skip_spin()


## 문 밖의 별만 다시 돌린다. 문 안의 별은 잠긴 채 그대로 빛난다.
func _respin() -> void:
	if state != PICK or _leaving:
		return
	skip_spin()
	var was: Array[float] = []
	for ring in range(Rite.RINGS):
		was.append(_angle(ring))
	var moved := Run.respin()
	if moved.is_empty():
		return
	_spin(moved, was)
	fx.ring(BOARD, Look.CRYSTAL, 34.0, 104.0, 0.4, 3.0)


func _swap_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var id := ui.hit(e.position)
		if id == "formation:fusion":
			fusion.opened = true
			return
		if id == "formation:map" or id == "formation:roster":
			formation_tab = id == "formation:map"
			if not formation_tab:
				_focus_info_latest()
			return
	if formation_tab:
		if formation.input(e, ui):
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and ui.hit(e.position) == "tobattle":
			_leave()
		return

	if e is InputEventMouseMotion:
		hv.motion(e.position)
		return
	if not (e is InputEventMouseButton):
		return
	var mb := e as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		hv.wheel(-1.0)
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		hv.wheel(1.0)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if hv.press(mb.position):
			return
		# 편성 판 밖(전투 시작 단추 · 팝업 단추)은 누르는 순간 그대로 처리한다.
		var id := ui.hit(mb.position)
		if id == "":
			return
		# ★ 편성 판은 **넘길 수 없다.** 자리를 안 바꾸겠다면 「전투 시작」을 누른다 —
		#   아무 데나 눌러서 넘어가게 두면 새로 온 영웅이 조용히 전당에 남는다.
		if id == "tobattle":
			Sfx.play("button")
			_leave()
		else:
			Sfx.play("button", -14.0)
			hv.tap(id)
	else:
		hv.release(mb.position, ui)


func _confirm() -> void:
	if _leaving:
		return
	# ★ 이미 확정한 탄이면 편성 판으로 보낸다. 그냥 돌아가면 「소환」이 죽은 단추가 되고
	#   _leave() 가 state == PICK 을 거절하므로(아래) 그 판에서 나갈 길이 없어진다.
	if Run.phase == Run.Phase.SWAP:
		result = Run.last_result
		showy = bool(result.get("showy", false))
		state = SWAP
		hv.new_id = String((result.get("unit", {}) as Dictionary).get("id", ""))
		_focus_latest()
		return
	# 도는 별을 세우고 확정한다 — 단추는 연출을 기다리지 않는다.
	skip_spin()
	_before.assign(Run.orbit)
	var got := Run.confirm_summon()
	if got.is_empty():
		return
	result = got
	showy = bool(result.get("showy", false))
	state = REVEAL
	rt = 0.0
	_fired.clear()
	Sfx.play("summon_charge")


## 연출이 끝났다. **탄마다 빠짐없이** 편성 판을 띄운다.
##
## ★ 예전에는 "전장이 꽉 찬 채로 새 영웅이 왔을 때"만 띄웠다. 그러면 앞 여섯 탄은 판을
##   한 번도 못 보고, 그 뒤로도 겹치는 탄에는 안 떠서 **언제 자리를 짤 수 있는지**를
##   플레이어가 배울 데가 없었다. 다음 탄의 몬스터 속성을 보고 여섯을 다시 짜는 것이
##   이 게임의 절반인데, 그 절반이 우연히 뜨는 창 뒤에 숨어 있었던 셈이다.
## ★ 고를 것이 없는 탄에는 「전투 시작」 한 번이면 끝난다 — 성가심은 한 번의 탭이고,
##   얻는 것은 "여기서 짤 수 있다"는 규칙이 매 탄 같은 자리에 있다는 것이다.
func _after_reveal() -> void:
	if state != REVEAL or _leaving:
		return
	state = SWAP
	hv.new_id = String(result.get("unit", {}).get("id", ""))
	fx.clear()
	_focus_latest()


func _focus_latest() -> void:
	formation.focus_latest()
	_focus_info_latest()


func _focus_info_latest() -> void:
	# 정보 탭은 터치하면 설명을 여는 동작을 유지하고, 새 카드에 강조 테두리를 준다.
	hv.sel = -1
	hv.new_id = String(Run.last_result.get("unit", {}).get("id", ""))


func _leave() -> void:
	if main == null or _leaving or state != SWAP:
		return
	_leaving = true
	main.go(main.go_battle)


# --------------------------------------------------------------------------- #
# 확정 연출 — 별이 수정으로 모여 영웅으로 터진다. 4성부터 화려하고 5성은 한 겹 더 얹는다
# --------------------------------------------------------------------------- #
func _once(key: String, at: float) -> bool:
	if rt >= at and not _fired.has(key):
		_fired[key] = true
		return true
	return false


func _burst_at() -> float:
	return BURST_SHOWY if showy else BURST_AT


## 최종 등급을 이루는 꽉 찬 별의 수와, 반 별이 붙는가.
static func _rank_parts(tier: int) -> Array:
	var cells := clampi(tier, 0, Balance.TIER_MAX) + 1
	return [cells / 2, cells % 2 == 1]


func _reveal_beats() -> void:
	var tier := int(result.get("tier", 0))
	var col := Look.tier_color(tier)
	var at := _burst_at()
	var grand := tier >= Balance.TIER_MAX
	var joker := int(result.get("joker", -1))
	var orbit: Array = result.get("orbit", [])
	if joker >= 0 and joker < orbit.size() and _once("joker", JOKER_SEC):
		var gate_at := RiteBoard.slot_point(BOARD, joker, int(orbit[joker]))
		fx.ring(gate_at, Look.GOLD, 12.0, 70.0, 0.42, 3.0)
		fx.burst(gate_at, Look.GOLD.lightened(0.3), 16, 150.0, 0.45, 3.0, 60.0)
		Sfx.force("block", -5.0, 1.3)
	if _once("burst", at):
		# 판 위에 남은 잠금 고리 · 불똥을 걷는다 — 영웅 판 위에 판의 이펙트가 겹쳐 보이면 안 된다.
		fx.clear()
		Sfx.play("summon_burst")
		Sfx.force("reveal%d" % tier)
		fx.do_flash(Color(1, 0.96, 0.8, 0.56 if showy else 0.34), 0.28)
		fx.do_shake(6 + tier * 0.9)
		fx.rays(HERO_AT, col, 14 + tier * 2, 380 + tier * 25, 0.85)
		for i in range(3):
			fx.ring(HERO_AT, Look.GOLD if i == 1 else col, 18, 170 + i * 65, 0.7 + i * 0.1, 5)
		# 수정 조각 — 별을 모았던 수정의 빛이 흩어진다.
		fx.shards(Rect2(HERO_AT - Vector2(42, 58), Vector2(84, 116)), Look.CRYSTAL.lightened(0.45), 32)
		fx.burst(HERO_AT, col.lightened(0.3), 32 + tier * 15, 360, 0.9, 4, 140)
		if grand:
			# 5성 — 금빛 빛살을 한 겹 더 깔고 고리를 멀리까지 보낸다.
			fx.rays(HERO_AT, Look.GOLD, 28, 760, 1.5)
			fx.burst(HERO_AT, Look.GOLD.lightened(0.35), 110, 420, 1.4, 5, 100)
			for i in range(3):
				fx.ring(HERO_AT, RiteBoard.LIGHT, 24, 330 + i * 80, 0.95 + i * 0.12, 5)
	if grand and _once("echo", at + 0.34):
		fx.do_flash(Color(1, 0.95, 0.74, 0.36), 0.3)
		fx.do_shake(8.0)
		fx.ring(HERO_AT, Look.GOLD, 30, 560, 0.9, 6)
	# 등급 별이 하나씩 박힌다 — 문 안에 든 별을 다시 한번 **센다.**
	var parts := _rank_parts(tier)
	var full := int(parts[0])
	for i in range(full):
		if _once("star%d" % i, at + STAR_IN_FIRST + STAR_IN_GAP * float(i)):
			var star_at := _rank_star(i)
			fx.burst(star_at, Look.GOLD.lightened(0.3), 7, 130.0, 0.4, 3.0, 80.0)
			Sfx.force("block", -7.0, 0.96 + 0.12 * float(i))
	if bool(parts[1]) and bool(result.get("bumped", false)) and _once("bump", _half_at(full)):
		var bump_at := _rank_star(full)
		fx.ring(bump_at, Color("#ff7ac0"), 10.0, 64.0, 0.5, 4.0)
		fx.burst(bump_at, Color("#ff7ac0").lightened(0.3), 18, 170.0, 0.55, 3.0, 80.0)
		Sfx.play("gain")


## 큰 등급 별 줄에서 i 번째 별의 자리.
static func _rank_star(i: int) -> Vector2:
	return Vector2(640.0 + float(i - 2) * 56.0, 196.0)


## 반 별이 박히는 시각. 도박꾼의 눈으로 얹힌 반 별은 한 박자 쉬었다가 온다 — 덤이라는 것이 보이게.
func _half_at(full: int) -> float:
	return _burst_at() + STAR_IN_FIRST + STAR_IN_GAP * float(full) \
			+ (0.30 if bool(result.get("bumped", false)) else 0.0)


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #
func _draw() -> void:
	ui.begin()
	_sh = fx.shake_offset()
	draw_set_transform(_sh, 0.0, Vector2.ONE)
	_draw_bg()
	match state:
		PICK:
			_draw_pick()
		SWAP:
			_draw_swap()
		_:
			_draw_reveal()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	fusion.draw(self, ui)
	hv.draw_info(self, ui)


## 의식의 자리 — 야영지에 놓인 **밤하늘 판**. 도트로 그린다.
##
## ★ 사용자가 정한 것: 「뽑는 화면도 2D 픽셀로 하고 디자인적으로 이질감이 안 느껴지게」.
##   그래서 (1) 모서리를 한 칸씩 깎고 (2) 테두리를 나무 널빤지 두 겹으로 두르고
##   (3) 하늘에 먼 별을 **도트 격자에 맞춰** 찍는다. 포커 시절의 초록 천 자리에 밤하늘이 들어왔다.
func _draw_bg() -> void:
	Look.camp_backdrop(self)
	if state == SWAP:
		_draw_topbar()
		return
	var g := Look.PX
	# 널빤지 테두리 두 겹 — 바깥이 어둡고 안쪽이 밝다.
	Look.px_panel(self, SKY, Look.NIGHT_EDGE, Color("#2a1a12"), 0.0)
	Look.px_panel(self, SKY.grow(-g * 3.0), Look.NIGHT, Color("#4a3220"), 0.10)
	# 먼 별 — 격자에 맞춘 작은 점. 몇 개만 천천히 깜빡인다.
	var sky := SKY.grow(-g * 5.0)
	for i in range(64):
		var hx := fposmod(sin(float(i) * 127.1) * 43758.5453, 1.0)
		var hy := fposmod(sin(float(i) * 311.7) * 43758.5453, 1.0)
		var at := Look.snap_v(sky.position + Vector2(hx, hy) * (sky.size - Vector2(g, g)), g)
		var twinkle := 0.5 + 0.5 * sin(t * (0.5 + hx) + float(i))
		var bright := i % 6 == 0
		draw_rect(Rect2(at, Vector2(g, g) if bright else Vector2(g, g) * 0.5),
				Color(0.76, 0.89, 1.0, 0.30 * twinkle if bright else 0.07 + 0.06 * twinkle))
	_draw_topbar()


func _draw_topbar() -> void:
	Hud.topbar(self, "%d탄" % Run.wave, Look.INK, Hud.INFO_SIZE,
			"별맞춤 의식" if state == PICK or state == REVEAL else "", Look.GOLD)


func _panel(rect: Rect2) -> void:
	Look.material_panel(self, rect, Color("#13212c"), Color("#3f5866"), "stone")


# --------------------------------------------------------------------------- #
# 의식판 — 세면 읽힌다: 문 안의 별 = 등급
# --------------------------------------------------------------------------- #
func _draw_pick() -> void:
	var valid := Rite.valid(Run.orbit)
	var settled := valid and not _spinning()
	var shown := _shown_stars()
	# 지금 확정하면 나올 등급. 조커가 끌어올 별까지 센다(Run.rite_preview) — 화면이 「별 셋」이라
	# 적어 놓고 4성을 내놓으면 안 된다. 별이 도는 동안에는 멈춘 별만 센다(결과를 미리 말하지 않는다).
	var preview := Run.rite_preview() if settled else {"stars": shown, "tier": Rite.tier_of(shown) if shown > 0 else -1, "joker": -1}
	var joker := int(preview.get("joker", -1))

	RiteBoard.draw_base(self, BOARD, 1.0, t)
	RiteBoard.draw_gate(self, BOARD, 1.0, t)
	RiteBoard.draw_core(self, BOARD, 1.0, t)
	fx.draw_back(self)
	for ring in range(Rite.RINGS if valid else 0):
		var angle := _angle(ring)
		var at := RiteBoard.point(BOARD, ring, angle)
		var look := _look(ring)
		if look == RiteBoard.SPIN:
			RiteBoard.draw_trail(self, BOARD, ring, angle, _sweep(ring), 1.0, 1.0,
					RiteBoard.LIGHT)
		if look == RiteBoard.HELD:
			RiteBoard.draw_tether(self, BOARD, at, 1.0, t)
		if ring == joker:
			_draw_pull_hint(ring, angle)
		var flash := clampf(1.0 - (t - _landed[ring]) / LOCK_SEC, 0.0, 1.0) \
				if look == RiteBoard.IN or look == RiteBoard.HELD else 0.0
		RiteBoard.draw_star(self, at, look, 1.0, t, flash)
	fx.draw(self)

	_draw_tally(shown, settled, preview)
	_draw_odds(settled, joker)
	_draw_actions(settled, preview)


## 조커가 확정 때 끌어올 별 — 그 별에서 가까운 문 끝까지 흐르는 점선.
func _draw_pull_hint(ring: int, angle: float) -> void:
	var side := signf(wrapf(angle - Rite.GATE_ANGLE, -PI, PI))
	var delta := wrapf(Rite.GATE_ANGLE + (1.0 if side == 0.0 else side) * Rite.gate_half(ring) - angle, -PI, PI)
	var radius := RiteBoard.orbit_radius(ring)
	var count := maxi(2, int(absf(delta) * radius / 16.0))
	var flow := fposmod(t * 1.6, 1.0)
	for i in range(count):
		var a0 := angle + delta * (float(i) + flow * 0.5) / float(count)
		var a1 := angle + delta * (float(i) + flow * 0.5 + 0.45) / float(count)
		draw_arc(BOARD, radius, minf(a0, a1), maxf(a0, a1), 4, Color(RiteBoard.LIGHT, 0.9), 3.0, true)
	Look.draw_passive_icon(self, RiteBoard.point(BOARD, ring, angle) + Vector2(0, -27), 11.0,
			Balance.passive_by_id("joker"), RiteBoard.LIGHT)


## 왼쪽 판 — 문 안의 별이 몇 개인가, 그래서 몇 성인가. 아래에는 의식의 안내자가 한마디를 건넨다.
func _draw_tally(shown: int, settled: bool, preview: Dictionary) -> void:
	_panel(LEFT)
	var cx := LEFT.get_center().x
	var top := LEFT.position.y
	var joker := int(preview.get("joker", -1))
	var pop := clampf(1.0 - (t - _tally_t) / 0.25, 0.0, 1.0)
	Look.text_center(self, Vector2(cx, top + 28), "문 안의 별", 21, Look.INK_DIM)
	for i in range(Rite.MAX_STARS):
		var at := Vector2(cx + float(i - 2) * 46.0, top + 76)
		var lit := i < shown
		var radius := 19.0 * (1.0 + 0.45 * pop if lit and i == shown - 1 else 1.0)
		var points := Look.star_points(at, radius)
		draw_colored_polygon(Look.star_points(at, 19.0), RiteBoard.COLD_FILL)
		if lit:
			draw_colored_polygon(points, Look.GOLD)
		elif joker >= 0 and i == shown:
			# 조커가 채울 자리 — 속이 빈 금테 별이 숨 쉰다. 아직 문 안의 별이 아니다.
			draw_colored_polygon(points, Color(Look.GOLD, 0.16 + 0.16 * sin(t * 4.0)))
		points.append(points[0])
		draw_polyline(points, Look.GOLD if lit or (joker >= 0 and i == shown) else RiteBoard.COLD, 1.6, true)
	var tier := int(preview.get("tier", -1))
	if tier >= 0:
		Look.text_center_out(self, Vector2(cx, top + 150), Look.star_label(tier), 72 + int(10.0 * pop),
				Look.tier_color(tier).lightened(0.18), Look.BG_DEEP, 3)
	var chip_y := top + 202
	if joker >= 0:
		_chip(Rect2(LEFT.position.x + 14, chip_y, LEFT.size.x - 28, 34), "joker", "소환 때 별 +1")
		chip_y += 40
	if settled and Run.has("eye") and tier < Balance.TIER_MAX:
		_chip(Rect2(LEFT.position.x + 14, chip_y, LEFT.size.x - 28, 34), "eye",
				"%d%% 확률로 +0.5성" % roundi(Balance.PASSIVE_EYE_P * 100.0))
	# 의식의 안내자 — 지금 무엇을 볼지 한 줄로 말한다.
	var face := Vector2(cx, LEFT.end.y - 72)
	SummonArt.bubble(self, Rect2(LEFT.position.x + 12, face.y - 54 - 5 - 14 - 92, LEFT.size.x - 24, 92),
			_guide_line(settled), face.x)
	SummonArt.guide(self, face, 54, t)


func _guide_line(settled: bool) -> String:
	if not settled:
		return "빛의 문 안에 멈춘 별을 세어 보세요."
	var out := Rite.misses(Run.orbit).size()
	if out == 0:
		return "다섯 별이 모두 문 안에 들었습니다!"
	if Run.can_respin():
		return "문 밖의 별 %d개만 다시 돕니다." % out
	return "빛의 문 안에 멈춘 별을 세어 보세요."


func _chip(rect: Rect2, passive_id: String, label: String) -> void:
	var passive := Balance.passive_by_id(passive_id)
	var tint := Color(String(passive.get("tint", "#f6c445")))
	Look.fill_round(self, rect, 4, tint.darkened(0.55))
	Look.fill_round(self, rect.grow(-1), 3, Look.BG_DEEP.lerp(tint, 0.10))
	Look.draw_passive_icon(self, rect.position + Vector2(20, rect.size.y * 0.5), 12.0, passive, tint)
	Look.text_box(self, Rect2(rect.position.x + 40, rect.position.y + 2, rect.size.x - 48, rect.size.y - 4),
			label, 18, tint.lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT)


## 오른쪽 판 — 별마다 문에 들 확률. **문의 폭이 곧 확률**이라는 것을 막대로 다시 말한다.
## 줄의 차례는 판과 같다: 바깥 별(문이 가장 좁다)이 위, 수정이 붙든 안쪽 별이 아래.
func _draw_odds(settled: bool, joker: int) -> void:
	_panel(RIGHT)
	Look.text_box(self, Rect2(RIGHT.position.x + 12, RIGHT.position.y + 12, RIGHT.size.x - 24, 32),
			"별마다 문에 들 확률", 20, Look.INK_DIM)

	for row in range(Rite.RINGS):
		var ring := Rite.RINGS - 1 - row
		var box := Rect2(RIGHT.position.x + 10, RIGHT.position.y + 54 + row * 84, RIGHT.size.x - 20, 76)
		var look := _look(ring)
		var inside := look == RiteBoard.IN or look == RiteBoard.HELD
		Look.fill_round(self, box, 4, Color(Look.GOLD, 0.10) if inside else Color(0, 0, 0, 0.24))
		RiteBoard.draw_star(self, box.position + Vector2(27, 27), look, 0.88, t)
		var chance := Rite.chance(ring)
		var track := Rect2(box.position.x + 56, box.position.y + 21, 112, 12)
		Look.fill_round(self, track, 3, Look.BG_DEEP)
		Look.fill_round(self, Rect2(track.position, Vector2(maxf(5.0, track.size.x * chance), track.size.y)),
				3, Look.GOLD if inside else RiteBoard.COLD)
		Look.text_box(self, Rect2(box.end.x - 70, box.position.y + 9, 62, 36),
				"항상" if Rite.anchored(ring) else RiteBoard.percent(chance), 23,
				Look.GOLD if inside else Look.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		var status := "도는 중"
		var status_col := Look.INK_DIM
		if inside:
			status = "수정이 붙든 별" if look == RiteBoard.HELD else "문 안 · 잠김"
			status_col = Look.GOLD
		elif look == RiteBoard.OUT:
			status = "문 밖"
			if ring == joker:
				status = "문 밖 · 조커가 끌어옴"
				status_col = RiteBoard.LIGHT
		Look.text_box(self, Rect2(box.position.x + 56, box.position.y + 43, box.size.x - 64, 26),
				status, 17, status_col, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(self, Rect2(RIGHT.position.x + 12, RIGHT.end.y - 46, RIGHT.size.x - 24, 32),
			"문이 넓을수록 잘 듭니다", 17, Look.INK_DIM)


## 단추 둘 — 다시 돌리기 · 소환. id 와 켜짐 조건은 검사기와의 약속이다.
func _draw_actions(settled: bool, preview: Dictionary) -> void:
	var free := Run.respins_left()
	var can := Run.can_respin()
	var has_miss := Rite.valid(Run.orbit) and not Rite.misses(Run.orbit).is_empty()
	var accent := Look.GREEN if free > 0 else Color("#d9a441")
	ui.button(self, RESPIN_RECT, "", "rite:respin", can, accent, 26)
	var ink := Look.INK if can else Color("#8b9aa5")
	var icon := RESPIN_RECT.position + Vector2(34, RESPIN_RECT.size.y * 0.5 - 1)
	draw_arc(icon, 11.0, -PI * 0.25, PI * 1.25, 18, ink, 3.0, true)
	var head := icon + Vector2.from_angle(-PI * 0.25) * 11.0
	draw_colored_polygon(PackedVector2Array([head + Vector2(-7, -5), head + Vector2(5, -6), head + Vector2(2, 6)]), ink)
	# 남은 무료 횟수 또는 골드 값 — 조작명 옆의 따로 난 칸에서 바로 읽는다.
	var chip := Rect2(RESPIN_RECT.end.x - 114, RESPIN_RECT.position.y + 13, 102, 40)
	var label_w: float = RESPIN_RECT.size.x - 62.0 - (chip.size.x + 18.0 if has_miss else 12.0)
	Look.text_box(self, Rect2(RESPIN_RECT.position.x + 56, RESPIN_RECT.position.y + 4, label_w, RESPIN_RECT.size.y - 10),
			"다시 돌리기", 26, ink, HORIZONTAL_ALIGNMENT_LEFT)
	if has_miss:
		var value_col := Look.GREEN if free > 0 else (Look.GOLD if can else Look.RED)
		Look.fill_round(self, chip, 4, Look.BG_DEEP)
		draw_rect(Rect2(chip.position.x + 6, chip.end.y - 3, chip.size.x - 12, 2), Color(value_col, 0.7))
		Look.text_box(self, chip.grow(-5), "무료 %d" % free if free > 0 else "%d G" % Run.respin_cost(),
				22, value_col)

	var tier := int(preview.get("tier", -1))
	ui.button(self, GO_RECT, "%s 소환" % Look.star_label(tier) if settled and tier >= 0 else "소환",
			"go", true, Look.GOLD, 34)


# --------------------------------------------------------------------------- #
# 확정 연출의 그림
# --------------------------------------------------------------------------- #
func _draw_reveal() -> void:
	var tier := int(result.get("tier", 0))
	var at := _burst_at()
	# ★ 밤하늘 판을 한 번 어둡게 덮는다. 안 덮으면 빛살(반투명)이 판의 색에 물들어
	#   등급 색이 안 읽힌다 — 등급 색이 안 읽히면 화려할 이유가 없다.
	draw_rect(Rect2(-40, -40, 1360, 880), Color(0, 0, 0, clampf((rt - 0.45) / 0.25, 0.0, 1.0) * 0.62))
	if rt < at:
		_draw_gather(at)
		return
	var unit: Dictionary = result.get("unit", {})
	var element := String(unit.get("elem", "none"))
	Look.material_panel(self, Rect2(180, 235, 920, 424), Look.hero_card_face(element), Look.hero_card_edge(element))
	fx.draw_back(self)      # 빛살·고리는 글자 **뒤에** 깔린다
	fx.draw(self)
	fx.draw_flash(self, Rect2(-40, -40, 1360, 880))
	var pop := clampf((rt - at) / 0.3, 0.0, 1.0)
	SummonArt.seal(self, HERO_AT, 142, rt * 0.35, Balance.elem_color(element), 0.40)
	if tier >= Balance.TIER_MAX:
		# 5성만의 금빛 인장과 둘레를 도는 별 — 4성과 한눈에 갈린다.
		SummonArt.seal(self, HERO_AT, 166, -rt * 0.26, Look.GOLD, 0.6 * pop)
		for i in range(12):
			var around := HERO_AT + Vector2.from_angle(float(i) * TAU / 12.0 + rt * 0.14) * Vector2(184, 170)
			var twinkle := 0.55 + 0.45 * sin(rt * 2.4 + float(i) * 1.7)
			draw_colored_polygon(Look.star_points(around, 3.0 + twinkle * 3.0, 0.35),
					Color(RiteBoard.LIGHT, (0.45 + twinkle * 0.5) * pop))
	Art.draw_unit_fit(self, unit, Rect2(248, 268 + (1.0 - pop) * 48.0, 332, 340), Color(1, 1, 1, pop), tier)
	SummonArt.hero_info(self, unit, tier, Rect2(622, 262, 432, 380))
	_draw_rank(tier, at)
	if String(result.get("where", "field")) == "bench":
		Look.text_center(self, Vector2(640, 690), "영웅 전당에 보관되었습니다", 21, Look.CRYSTAL)
	Look.text_center_out(self, Vector2(640, 748), "터치하여 배치하기", 24, Look.INK)


## 터지기 전 — 문 안의 별이 수정으로 모여 한 덩이 빛이 되고, 영웅이 설 자리로 날아간다.
func _draw_gather(at: float) -> void:
	var orbit: Array = result.get("orbit", [])
	var joker := int(result.get("joker", -1))
	var charge := clampf((rt - 0.40) / maxf(0.1, at - 0.77), 0.0, 1.0)
	var launch := clampf((rt - (at - 0.37)) / 0.37, 0.0, 1.0)
	var orb := BOARD.lerp(HERO_AT, launch * launch)
	RiteBoard.draw_base(self, BOARD, 1.0, t)
	RiteBoard.draw_gate(self, BOARD, 1.0, t, 1.0 - launch)
	draw_circle(BOARD, RiteBoard.EXTENT, Color(0, 0, 0, 0.32 * charge))     # 판은 물러나고 빛만 남는다
	RiteBoard.draw_core(self, BOARD, 1.0, t, charge * (1.0 - launch))
	fx.draw_back(self)
	SummonArt.seal(self, orb, 30.0 + charge * 64.0, rt * 3.0, Look.CRYSTAL, charge)
	draw_circle(orb, 16.0 + charge * 28.0, Color(RiteBoard.LIGHT, 0.22 * charge))
	var inside: Array[int] = []
	for ring in range(mini(Rite.RINGS, orbit.size())):
		if Rite.in_gate(ring, int(orbit[ring])):
			inside.append(ring)
	for ring in range(mini(Rite.RINGS, orbit.size())):
		var home := Rite.angle(ring, int(orbit[ring]))
		var order := inside.find(ring)
		var begin := 0.06 * float(maxi(0, order))
		if ring == joker and ring < _before.size():
			# 조커가 끌어온 별 — 문 밖의 제자리에서 문 안으로 끌려온 뒤에 모인다.
			if rt < JOKER_SEC:
				var from := Rite.angle(ring, _before[ring])
				var k := clampf(rt / JOKER_SEC, 0.0, 1.0)
				var swing := wrapf(home - from, -PI, PI)
				var angle := from + swing * k * k * (3.0 - 2.0 * k)
				var star := RiteBoard.point(BOARD, ring, angle)
				RiteBoard.draw_tether(self, BOARD, star, 1.0, t, RiteBoard.LIGHT)
				RiteBoard.draw_trail(self, BOARD, ring, angle, swing * 0.28 * sin(k * PI))
				RiteBoard.draw_star(self, star, RiteBoard.SPIN, 1.0, t)
				continue
			begin = JOKER_SEC
		if order < 0:
			# 문 밖의 별은 식어서 사라진다.
			RiteBoard.draw_star(self, RiteBoard.point(BOARD, ring, home), RiteBoard.OUT, 1.0, t, 0.0,
					1.0 - clampf(rt / 0.35, 0.0, 1.0))
			continue
		var gather := clampf((rt - begin) / 0.5, 0.0, 1.0)
		var eased := gather * gather * (3.0 - 2.0 * gather)
		var radius := lerpf(RiteBoard.orbit_radius(ring), lerpf(36.0, 18.0, charge), eased)
		var whirl := 5.5 * pow(maxf(0.0, rt - begin - 0.25), 1.7)
		var angle := home + eased * (1.4 + TAU * float(order) / float(inside.size())) + whirl
		var star := orb + Vector2.from_angle(angle) * radius
		# 모이는 별은 꼬리를 끈다 — 지나온 쪽으로 옅은 빛 한 줄.
		var behind := orb + Vector2.from_angle(angle - 0.5 * eased - 0.12) * (radius + 10.0 * (1.0 - eased))
		draw_line(behind, star, Color(RiteBoard.LIGHT, 0.35 * gather), 4.0, true)
		RiteBoard.draw_star(self, star, RiteBoard.IN if gather <= 0.0 else RiteBoard.SPIN,
				lerpf(1.0, 0.86, eased), t)
	draw_circle(orb, 10.0 * launch, Color(1, 1, 1, 0.85 * launch))
	fx.draw(self)


## 영웅 위의 큰 별 줄과 「N성」. 모였던 별이 하나씩 박히며 등급을 **다시 센다.**
## 도박꾼의 눈으로 얹힌 반 별과 조커가 끌어온 별은 옆의 딱지가 무엇 덕인지 말해 준다.
func _draw_rank(tier: int, at: float) -> void:
	var parts := _rank_parts(tier)
	var full := int(parts[0])
	var half := bool(parts[1])
	var bumped := bool(result.get("bumped", false))
	var landed := 0
	for i in range(full):
		if rt >= at + STAR_IN_FIRST + STAR_IN_GAP * float(i):
			landed += 1
	var half_at := _half_at(full)
	var half_in := half and rt >= half_at
	Look.fill_round(self, Rect2(640 - 154, 196 - 31, 308, 62), 6, Color(Look.BG_DEEP, 0.86))
	for i in range(Rite.MAX_STARS):
		var c := _rank_star(i)
		var slot := Look.star_points(c, 21.0)
		draw_colored_polygon(slot, RiteBoard.COLD_FILL)
		var lit := i < landed
		var halved := i == full and half_in
		if lit or halved:
			var born := at + STAR_IN_FIRST + STAR_IN_GAP * float(i) if lit else half_at
			var points := Look.star_points(c, 21.0 * (1.0 + 0.7 * clampf(1.0 - (rt - born) / 0.2, 0.0, 1.0)))
			if lit:
				draw_colored_polygon(points, Look.GOLD)
			else:
				# 왼쪽 반쪽 별 — 등급 배지(Look.draw_rarity)와 같은 자름이다.
				draw_colored_polygon(PackedVector2Array([points[0], points[5], points[6], points[7], points[8], points[9]]),
						Color("#ff7ac0") if bumped else Look.GOLD)
		slot.append(slot[0])
		draw_polyline(slot, Look.GOLD if lit or halved else RiteBoard.COLD, 1.6, true)
	var shown := landed * 2 - 1 + (1 if half_in else 0)
	var size := 66 if showy else 58
	if shown >= 0:
		Look.text_center_out(self, Vector2(640, 122), Look.star_label(shown), size,
				Look.tier_color(shown).lightened(0.12), Look.BG_DEEP, 3)
	# 딱지는 등급 글자의 양옆에 선다. 영문 「4.5-Star」처럼 글자가 길어져도 겹치지 않게 최종 등급의 폭을 잰다.
	var reach := maxf(96.0, Look.text_width(Look.star_label(tier), size) * 0.5 + 18.0)
	if int(result.get("joker", -1)) >= 0:
		_chip(Rect2(640.0 - reach - 260.0, 104, 260, 36), "joker", "조커 · 별 하나 더")
	if bumped and half_in:
		_chip(Rect2(640.0 + reach, 104, 300, 36), "eye", "도박꾼의 눈 · +0.5성")


## 편성 판 — **탄마다** 뜬다. 새로 온 영웅을 어디에 세울지, 이번 탄에 오는 몬스터에
## 맞춰 여섯을 어떻게 짤지를 여기서 고른다.
func _draw_swap() -> void:
	Look.material_panel(self, Rect2(24, 86, 1232, 698), Look.PANEL, Look.GOLD_DEEP)
	_draw_wave_monsters()

	ui.tab(self, Rect2(46, 152, 170, 42), "전장 배치", "formation:map", formation_tab, 21)
	ui.tab(self, Rect2(224, 152, 170, 42), "영웅 정보", "formation:roster", not formation_tab, 21)
	ui.tab(self, Rect2(402, 152, 170, 42), "영웅 합성", "formation:fusion", false, 21)
	if formation_tab:
		formation.draw(self, ui, Rect2(44, 214, 1192, 490), t)
	else:
		hv.draw(self, ui, Rect2(60, 214, 1160, 490), 6, false)
	ui.button(self, Rect2(490, 706, 300, 66), "전투시작", "tobattle", not Run.heroes.is_empty(), Look.GOLD, 28)


## 이번 탄의 몬스터 이름과 해당 몬스터의 속성만 표시한다.
func _draw_wave_monsters() -> void:
	var pool: Array = Run.wave_lineup(Run.wave)
	var head := Hud.wave_head(Run.wave, "Next Stage")
	var x := maxf(60, 640.0 - Hud.lineup_width(head, pool) * 0.5)
	Hud.draw_lineup(self, Vector2(x, 117), head, pool)
