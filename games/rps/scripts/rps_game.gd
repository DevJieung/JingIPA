extends Control

## 가위바위보 — 친구가 낸 손을 보고, 이기는(또는 비기는·지는) 손을 낸다.
##
## ★ 진짜 가위바위보에서 바꾼 것 하나: **동시에 내지 않는다.**
##   동시에 내면 아무리 잘 봐도 세 번에 두 번은 진다. 그건 이 앱이 금지한 것 셋을
##   한꺼번에 건드린다 — 지는 것(규칙 2) · 평가받는 느낌(F축) · 운을 숙련으로
##   오독하는 적응형(규칙 9). 그래서 **친구가 먼저 손을 내고 영원히 기다린다.**
##   (참참참에서 박자를 뺀 것과 정확히 같은 자리다.)
##
## ★ 대신 진짜 놀이의 알맹이는 그대로 남았다 — **세 손의 관계**와, 커서는 **일부러 지기.**
##   둘 다 운이 아니라 아는 것이라, 자랄 것이 있다.
##
## ★ 틀리는 것이 벌이 아니라 **설명**이다. 잘못 고르면 두 손이 그대로 만나서
##   **무슨 일이 일어났는지**를 보여 준다 (진 손은 작아지고 이긴 손 옆에 별이 뜬다).
##   목표 팻말에도 같은 그림이 있으니, 아이는 **별의 자리 둘을 견주기만** 하면 된다.
##   글자를 못 읽어도 된다. 그리고 다시 고를 수 있다 — 라운드는 맞힐 때까지 이어진다.
##
## ★ 그래서 **막다른 길이 없다**: 목표가 무엇이든 정답은 언제나 정확히 하나 있고
##   (RpsGen.answer), 그 카드는 반드시 화면에 있고, 틀려도 판이 안 줄어든다.
##
## ★ 관계 고리(가위>보>바위>가위)가 옆에 그려져 있다. 이게 **커닝페이퍼이자 B축**이다 —
##   단계가 오르면 옅어지고, 두 번 틀리면 다시 진해진다. 아이 눈에는 난이도가 내려간 것이
##   아니라 "설명이 다시 친절해진 것"으로만 보인다 (규칙 11).
##
## ★ 공룡 찾기에서 빌려 오는 것: DinoSpecies (그림·이름·도감) · Confetti · Sfx.
##   새 이미지 자산은 0장이다. 손은 전부 코드로 그린다 (규칙 27).

const W := 1280.0
const H := 800.0

const BG := Look.BG
const BG2 := Look.BG2
const INK := Look.INK
const INK_SOFT := Look.INK_SOFT
const CARD_BG := Look.CARD
const FLOOR := Color("ddc9a8")
## 손 색은 참참참과 **같은 것을 쓴다** — 두 게임의 손이 다른 색이면 한 앱으로 안 읽힌다.
const SKIN := Look.SKIN

## 놀이 마당 자리
const FRIEND_AT := Vector2(600.0, 318.0)     ## 친구 손이 서는 자리
const MINE_AT := Vector2(600.0, 492.0)       ## 내 손이 올라와 만나는 자리
const HAND_R := 80.0
const MARK_X := 792.0                        ## 별 · 등호가 뜨는 가로 자리
const RING_AT := Vector2(1058.0, 358.0)      ## 관계 고리
const RING_R := 112.0
const GROUND := 530.0
const CARD_TOP := 552.0

## 연출 길이 (초). 전부 재촉이 아니라 "무슨 일이 일어났는지 보이게" 하는 시간이다.
const ENTER_SEC := 0.45
const SHOW_SEC := 0.40
const OK_SEC := 1.05
const NO_SEC := 1.30
const CLEAR_SEC := 1.60

var stage := 1
var hit := 0                   ## 이번 판에서 맞힌 라운드 수
var misses := 0                ## 이번 판에서 잘못 고른 횟수
var lifetime := 0
var best_stage := 1
var axes: Dictionary = {}

## --- 적응형 난이도 ------------------------------------------------------- ##
## 아이 눈에 절대 보이지 않는다. 신호는 **틀린 횟수 하나뿐**이고 시간은 안 잰다.
const SKILL_MIN := -8
const SKILL_MAX := 10
var skill := 0
var ease_streak := 0
var cushion := 0

var _sp := 0                   ## 친구 종 인덱스
var _rounds: Array = []        ## [{friend, goal, answer, cards}]
var _idx := 0                  ## 지금 라운드
var _miss_streak := 0          ## 이 라운드에서 연달아 틀린 횟수
var _met := false

## enter -> wait -> show -> ok|no -> ... -> clear -> gone
var _state := "enter"
var _anim := 0.0
var _pick := -1                ## 아이가 고른 손
var _t := 0.0
var _bounce := 0.0

var dev_mode := false
var _slow := 1.0
var _pool: Array = []

var fx: Confetti
var sfx: Sfx


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	randomize()
	fx = Confetti.new()
	add_child(fx)
	sfx = Sfx.new()
	sfx.enabled = Shell.sfx_enabled
	add_child(sfx)
	Shell.settings_changed.connect(_pull_settings)
	_load_record()
	stage = maxi(1, best_stage)
	_build_stage()


func _pull_settings() -> void:
	if sfx != null:
		sfx.enabled = Shell.sfx_enabled


func _process(delta: float) -> void:
	_t += delta
	if fx != null:
		fx.position = _origin()
		fx.scale = Vector2.ONE * _scale()
	_bounce = maxf(0.0, _bounce - delta * 3.0)
	var mot := maxf(0.05, _slow * Shell.anim_scale())
	match _state:
		"enter":
			_anim += delta / (ENTER_SEC * mot)
			if _anim >= 1.0:
				_state = "wait"
				_anim = 0.0
		"show":
			_anim += delta / (SHOW_SEC * mot)
			if _anim >= 1.0:
				_judge()
		"ok":
			_anim += delta / (OK_SEC * mot)
			if _anim >= 1.0:
				_after_hit()
		"no":
			_anim += delta / (NO_SEC * mot)
			if _anim >= 1.0:
				_state = "wait"
				_anim = 0.0
				_pick = -1
		"clear":
			_anim += delta / (CLEAR_SEC * mot)
			if _anim >= 1.0:
				_next_stage()
	queue_redraw()


# --------------------------------------------------------------------------- #
# 저장 — 자기 칸에만 쓴다 (편입 규칙 7)
# --------------------------------------------------------------------------- #

func _state_dict() -> Dictionary:
	var p := Shell.profile()
	if not p.has("rps"):
		p["rps"] = {
			"best_stage": 1, "hits": 0,
			"skill": 0, "ease_streak": 0, "cushion": 0,
		}
	return p["rps"]


func _load_record() -> void:
	var d := _state_dict()
	best_stage = maxi(1, int(d.get("best_stage", 1)))
	lifetime = maxi(0, int(d.get("hits", 0)))
	skill = clampi(int(d.get("skill", 0)), SKILL_MIN, SKILL_MAX)
	ease_streak = maxi(0, int(d.get("ease_streak", 0)))
	cushion = maxi(0, int(d.get("cushion", 0)))


func _save_record() -> void:
	best_stage = maxi(best_stage, stage)
	var d := _state_dict()
	d["best_stage"] = best_stage
	d["hits"] = lifetime
	d["skill"] = skill
	d["ease_streak"] = ease_streak
	d["cushion"] = cushion
	Shell.mark_dirty()


# --------------------------------------------------------------------------- #
# 판 만들기
# --------------------------------------------------------------------------- #

## 난이도용 유효탄. 10판 배수(축하 판)는 언제나 조금 쉽게.
func effective_stage() -> int:
	var e := stage + skill - cushion * 2
	if stage % 10 == 0:
		e -= 3
	return clampi(e, 1, 999)


func _build_stage() -> void:
	axes = RpsGen.axes(effective_stage(), Shell.tuning())
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	hit = 0
	misses = 0
	_idx = 0
	_miss_streak = 0
	_pick = -1
	_met = false
	_sp = _next_species()
	_rounds = RpsGen.make_rounds(int(axes.get("cards", 3)), int(axes.get("goals", 1)),
			int(axes.get("rounds", 5)), rng)
	fx.clear_all()
	_state = "enter"
	_anim = 0.0


## 종을 골고루 뽑는다. 아직 도감에 없는 종을 먼저 (큰 아이 프로필만).
func _next_species() -> int:
	if bool(Shell.tune("dino_dex_hunt", false)):
		var unmet := Shell.unmet_indices()
		if not unmet.is_empty():
			var pick := int(unmet[randi() % unmet.size()])
			_pool.erase(pick)
			return pick
	if _pool.is_empty():
		_pool = range(DinoSpecies.count())
		_pool.shuffle()
	return int(_pool.pop_back())


# --------------------------------------------------------------------------- #
# 지금 라운드 — **그리기와 검사기가 같은 함수를 본다**
#
# ★ 검사기가 게임의 정답 함수를 그냥 부르면 "무엇을 그리든 통과하는" 항등식이 된다.
#   그래서 검사기는 아래 셋(친구 손 · 목표 · 카드)만 읽고, 정답은 **스스로** 규칙으로
#   구해서 누른다. 화면에 그린 것과 판정이 어긋나면 그때 걸린다.
#   (참참참이 tell_pose 하나로 같은 함정을 막은 것과 같은 자리다.)
# --------------------------------------------------------------------------- #

func _now() -> Dictionary:
	if _rounds.is_empty():
		return {}
	# ★ 마지막 라운드를 맞히면 _idx 가 끝을 넘어간다. 그때 빈 값을 돌려주면 친구 손이
	#   축하하는 순간에 갑자기 **다른 손으로 바뀐다** (기본값 바위로). 끝에 붙여 둔다.
	return _rounds[clampi(_idx, 0, _rounds.size() - 1)]


## 친구가 지금 내밀고 있는 손 (화면에 그려지는 그것)
func friend_hand() -> int:
	var r := _now()
	return int(r.get("friend", RpsGen.ROCK)) if not r.is_empty() else RpsGen.ROCK


## 지금 팻말에 걸린 목표
func goal_now() -> int:
	var r := _now()
	return int(r.get("goal", RpsGen.WIN)) if not r.is_empty() else RpsGen.WIN


## 지금 내놓은 카드들 (가위·바위·보 순서)
func cards_now() -> Array:
	var r := _now()
	if r.is_empty():
		return [RpsGen.SCISSORS, RpsGen.ROCK, RpsGen.PAPER]
	return r["cards"]


## 관계 고리가 지금 얼마나 진한가 (0 = 안 보임, 1 = 또렷)
##
## ★ 두 번 잘못 고르면 **난이도와 상관없이** 다시 또렷해진다. 아이 눈에는 난이도가
##   내려간 것이 아니라 설명이 다시 친절해진 것으로만 보인다 (규칙 11).
func help_now() -> float:
	if _miss_streak >= 2:
		return 1.0
	return float(axes.get("help", 1.0))


## 세 번 잘못 고르면 정답 카드가 조용히 숨을 쉰다. 그래도 "틀렸다"는 말은 없다.
func hint_hand() -> int:
	if _miss_streak < 3:
		return -1
	var r := _now()
	return int(r["answer"]) if not r.is_empty() else -1


# --------------------------------------------------------------------------- #
# 좌표
# --------------------------------------------------------------------------- #

func _scale() -> float:
	return minf(size.x / W, size.y / H)


func _origin() -> Vector2:
	var s := _scale()
	return Vector2((size.x - W * s) * 0.5, (size.y - H * s) * 0.5)


func _to_local(p: Vector2) -> Vector2:
	var s := _scale()
	return Vector2.ZERO if s <= 0.0 else (p - _origin()) / s


## 카드 하나의 자리. **아래쪽을 통째로 나눠 써서** 손가락이 큰 아이도 못 빗나간다.
func card_rect(i: int) -> Rect2:
	var n := maxi(1, cards_now().size())
	var gap := 20.0
	var wide := (W - 60.0 - gap * float(n - 1)) / float(n)
	return Rect2(30.0 + (wide + gap) * float(i), CARD_TOP, wide, H - CARD_TOP - 14.0)


## 이 손이 몇 번째 카드인가 (없으면 -1)
func card_index(h: int) -> int:
	return (cards_now() as Array).find(h)


func _home_rect() -> Rect2:
	return Rect2(W - 196.0, 24.0, 164.0, 72.0)


func _goal_rect() -> Rect2:
	return Rect2(W * 0.5 - 250.0, 88.0, 500.0, 104.0)


# --------------------------------------------------------------------------- #
# 입력 — 규칙은 하나뿐이다: 카드를 하나 누른다
# --------------------------------------------------------------------------- #

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	_on_tap(_to_local(mb.position))


func _on_tap(p: Vector2) -> void:
	if _home_rect().grow(12.0).has_point(p):
		_go_home()
		return
	if _state == "clear":
		return
	if _state != "wait":
		return                      # 손이 만나는 중에는 안 받는다 (연타로 두 번 세지 않게)
	var cs: Array = cards_now()
	for i in cs.size():
		if card_rect(i).has_point(p):
			_choose(int(cs[i]))
			return
	# 카드가 아닌 데를 눌렀다 — 벌이 아니라 "여기야" 하고 카드가 한 번 튄다.
	_bounce = 1.0


func _choose(h: int) -> void:
	_pick = h
	_state = "show"
	_anim = 0.0
	sfx.play("tap", 1.1)


# --------------------------------------------------------------------------- #
# 진행
# --------------------------------------------------------------------------- #

## 두 손이 만났다. 목표대로 됐는가.
func _judge() -> void:
	_anim = 0.0
	var r := _now()
	if r.is_empty():
		_state = "wait"
		return
	if _pick == int(r["answer"]):
		_state = "ok"
		_miss_streak = 0
		hit += 1
		lifetime += 1
		Shell.bump_today("rps")
		_save_record()
		sfx.play("find", 1.0 + 0.06 * float(hit - 1))
		fx.burst(MINE_AT + Vector2(0, -40.0), _fx(20), DinoSpecies.data(_sp)["col"])
		if not _met:
			_met = true
			# 도감은 집 공용이다 — 여기서 만난 공룡도 같은 칸을 채운다.
			# ★ 한 판에 한 번만. 같은 친구와 다섯 번 놀았다고 다섯 번 만난 것은 아니다.
			if Shell.dex_meet(DinoSpecies.id_of(_sp)):
				fx.rain(_fx(30))
	else:
		_state = "no"
		misses += 1
		_miss_streak += 1
		# ★ 벌이 아니다. 두 손은 그대로 만난 채로 **무슨 일이 일어났는지** 보여 준다.
		sfx.play("miss", randf_range(1.0, 1.15))


func _after_hit() -> void:
	_idx += 1
	_pick = -1
	if hit >= int(axes.get("rounds", 5)) or _idx >= _rounds.size():
		_state = "clear"
		_anim = 0.0
		_update_skill()
		sfx.play("hooray" if stage % 10 == 0 else "clear")
		fx.rain(_fx(150 if stage % 10 == 0 else 70))
		return
	_state = "wait"
	_anim = 0.0


func _next_stage() -> void:
	# ★ 제일 먼저 "gone" 으로 돌린다. 화면 전환은 페이드 때문에 비동기라서, 그동안
	#   _process 가 계속 돌면 여기가 매 프레임 다시 불린다 (여행 검사가 잡는 사고다).
	_state = "gone"
	stage += 1
	_save_record()
	if Shell.journey_active and not dev_mode:
		Shell.journey_advance()
		return
	# ★ 상한에 닿았으면 셸이 쉼표를 찍고 허브로 보낸다 (Shell.round_done) —
	#   세션을 새로 열지 않으면 그 뒤로는 한 판마다 튕겨 나간다.
	if Shell.round_done(dev_mode):
		return
	_build_stage()


func _go_home() -> void:
	if _state == "gone":
		return
	_state = "gone"
	sfx.play("tap")
	_save_record()
	Shell.journey_end()
	Router.goto_hub()


## 판 하나가 끝날 때 딱 한 번. 신호는 틀린 횟수뿐이고 시간은 안 잰다.
##
## ★ 문턱을 "틀림 <= 1" 로 조인 근거는 RpsGen.guess_pass 에 있다. 카드 3장 5라운드에서
##   아무렇게나 찍는 아이가 여기 걸릴 확률은 2.5%, 두 판 연속은 0.06% 다.
##   (규칙 9 가 "4지선다 2연속 1/16 을 숙련으로 오독하지 마라"고 못 박은 문턱보다 촘촘하다.)
func _update_skill() -> void:
	if cushion > 0:
		cushion -= 1
	var n := maxi(1, int(axes.get("rounds", 5)))
	if misses >= n:
		# 맞힌 만큼 틀렸다 = 사실상 하나씩 눌러 보고 있다. 다음 판은 쉽게, 그 다음은 완충.
		skill = maxi(skill - 1, SKILL_MIN)
		ease_streak = 0
		cushion = 1
	elif misses <= 1:
		ease_streak += 1
		if ease_streak >= 2:
			skill = mini(skill + 1, SKILL_MAX)
			ease_streak = 0
	else:
		ease_streak = 0


func _fx(n: int) -> int:
	return n / 2 if Shell.reduce_motion else n


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #

func _draw() -> void:
	var s := _scale()
	var o := _origin()
	draw_set_transform(o, 0.0, Vector2(s, s))

	draw_rect(Rect2(0, 0, W, H), BG)
	for i in 4:
		draw_rect(Rect2(0, 116.0 + float(i) * 118.0, W, 54.0), BG2)
	draw_rect(Rect2(0, GROUND, W, CARD_TOP - GROUND), FLOOR)
	draw_rect(Rect2(0, GROUND, W, 6.0), Color(0, 0, 0, 0.07))

	_paint_header()
	_paint_ring()
	# ★ 축하할 때는 놀이판을 걷는다. 그대로 두면 축하 상자가 친구 손을 **반으로 자르고**
	#   두리가 공룡 등에 올라탄다. 다 끝난 판의 손과 카드는 이제 볼 일도 없다.
	if _state != "clear":
		_paint_goal()
	_paint_friend()
	if _state != "clear":
		_paint_field()
		_paint_cards()
	if _state == "ok" and hit <= 1:
		_paint_name()
	if _state == "clear":
		_paint_clear()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if o.x > 0.5:
		draw_rect(Rect2(0, 0, o.x, size.y), BG)
		draw_rect(Rect2(size.x - o.x, 0, o.x, size.y), BG)
	if o.y > 0.5:
		draw_rect(Rect2(0, 0, size.x, o.y), BG)
		draw_rect(Rect2(0, size.y - o.y, size.x, o.y), BG)


func _paint_header() -> void:
	_text("%d번째 판" % stage, Vector2(64.0, 46.0), 30, INK)
	_text("%d번 맞혔어요" % hit, Vector2(64.0, 84.0), 22, INK_SOFT)
	# 이번 판에 몇 번 맞혀야 하는지 (지금 이 판만 — 누적 기록은 아이 화면에 두지 않는다)
	var need := int(axes.get("rounds", 5))
	var col: Color = DinoSpecies.data(_sp)["col"]
	for i in need:
		var at := Vector2(W * 0.5 - float(need - 1) * 34.0 + float(i) * 68.0, 52.0)
		if i < hit:
			draw_circle(at, 17.0, col)
			draw_circle(at, 7.0, Color(1, 1, 1, 0.55))
		else:
			draw_circle(at, 17.0, Color(INK_SOFT, 0.18))
	var hr := _home_rect()
	_round_rect(hr, 18.0, Color("ffe0e6"))
	_text_centered("집으로", Vector2(hr.position.x + hr.size.x * 0.5, hr.position.y + 48.0), 26, INK)


## 목표 팻말. **별이 어느 쪽에 있는가**가 전부다 — 글자를 못 읽어도 읽힌다.
## 위가 친구, 아래가 나. 놀이 마당과 위아래가 똑같아서 그대로 견줄 수 있다.
func _paint_goal() -> void:
	var r := _goal_rect()
	_round_rect(r, 28.0, Color(1, 1, 1, 0.94))
	_round_rect_outline(r, 28.0, Color(Look.ACCENT, 0.55), 4.0)
	# ★ 별을 팻말 **오른쪽**에 둔다 — 놀이 마당의 결과 별(MARK_X)과 같은 세로줄이라
	#   아이가 하는 일이 "위아래로 눈만 옮겨 둘을 견주는 것"이 된다.
	#   왼쪽 끝에 뒀을 때는 두 그림이 가로로 422px 떨어져 있어서 견줄 수가 없었다.
	var want := RpsGen.goal_outcome(goal_now())
	_paint_verdict(Vector2(MARK_X, r.position.y + r.size.y * 0.5), 22.0, want, 1.0)
	_text_centered(RpsGen.goal_name(goal_now()),
			Vector2(r.position.x + 170.0, r.position.y + 68.0), 46, Look.ACCENT)


## 별(이김) · 등호(비김) 를 위/아래 어느 쪽에 붙일지 그린다.
## v = 1 이면 아래쪽(나)이, -1 이면 위쪽(친구)이 이겼다는 뜻.
func _paint_verdict(c: Vector2, r: float, v: int, a: float) -> void:
	# ★ 등호를 금색으로 두면 크림 바탕에서 대비가 1.15:1 이라 **안 보인다** — 비겼을 때의
	#   유일한 신호가 사라지는 것이다. 별은 모양이 뚜렷해서 금색이어도 읽히지만,
	#   그 별도 짙은 테를 둘러야 옅은 바탕에서 산다.
	var gold := Color(Look.GOLD, a)
	var ink := Color(INK_SOFT, a * 0.75)
	var line := Color(INK, a)
	# 위(친구) · 아래(나) 자리를 점 둘로. 놀이 마당과 위아래가 같아서 그대로 견줄 수 있다.
	var dx := -r * 0.72
	draw_circle(c + Vector2(dx, -r * 1.05), r * 0.44, ink)
	draw_circle(c + Vector2(dx, r * 1.05), r * 0.44, ink)
	if v == 0:
		for k in 2:
			var y := -r * 0.20 + float(k) * r * 0.40
			draw_line(c + Vector2(dx - r * 0.55, y), c + Vector2(dx + r * 0.55, y), line, r * 0.20)
		return
	# ★ 별은 점 **옆에** 둔다. 점 위에 겹치면 "어느 쪽이 이겼나"가 안 읽힌다.
	var sc := c + Vector2(dx + r * 1.05, r * 1.05 * float(v))
	_paint_star(sc, r * 0.95, Color(INK, a * 0.85))
	_paint_star(sc, r * 0.85, gold)


func _paint_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a) * rr, sin(a) * rr))
	draw_colored_polygon(pts, col)


## 세 손의 관계 고리 — 이 게임의 커닝페이퍼이자 B축.
func _paint_ring() -> void:
	var a := help_now()
	if a <= 0.02:
		return
	# ★ 알파를 그대로 쓰면 중간값에서 너무 빨리 사라진다 (0.45 에서 이미 안 보였다).
	#   제곱근을 태워 "옅어지지만 남아 있는" 구간을 넓힌다 — 0 은 그대로 0 이라 B축은 산다.
	a = sqrt(a)
	var pos := {
		RpsGen.SCISSORS: RING_AT + Vector2(0, -RING_R),
		RpsGen.ROCK: RING_AT + Vector2(RING_R * 0.87, RING_R * 0.5),
		RpsGen.PAPER: RING_AT + Vector2(-RING_R * 0.87, RING_R * 0.5),
	}
	# 이긴다 화살표: 가위 -> 보 -> 바위 -> 가위
	for from in [RpsGen.SCISSORS, RpsGen.PAPER, RpsGen.ROCK]:
		var p0: Vector2 = pos[from]
		var p1: Vector2 = pos[RpsGen.beats(from)]
		var d := (p1 - p0).normalized()
		var s0 := p0 + d * 52.0
		var s1 := p1 - d * 58.0
		draw_line(s0, s1, Color(Look.ACCENT, 0.42 * a), 9.0)
		var pp := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([
				s1 + d * 17.0, s1 + pp * 13.0, s1 - pp * 13.0]), Color(Look.ACCENT, 0.42 * a))
	for h in pos:
		draw_circle(pos[h], 44.0, Color(CARD_BG, 0.92 * a))
		_hand_at(pos[h], 30.0, int(h), Vector2.UP, Color(SKIN, a), 0.0, 1.0)


## 친구 공룡 — 손은 따로 그린다 (놀이 마당 쪽에서).
func _paint_friend() -> void:
	var pos := Vector2(232.0, GROUND)
	if _state == "enter":
		var a := clampf(_anim, 0.0, 1.0)
		pos.x -= (1.0 - a) * 340.0
		pos.y -= sin(a * PI) * 34.0
	elif _state == "clear":
		pos.y -= absf(sin(_t * 6.0)) * 20.0
	else:
		pos.y -= absf(sin(_t * 3.0)) * 7.0
	var sh: float = clampf(1.0 - (GROUND - pos.y) / 240.0, 0.3, 1.0)
	_ellipse(Vector2(pos.x, GROUND + 4.0), Vector2(58.0 * sh, 13.0 * sh), Color(0, 0, 0, 0.10))
	# ★ 그림을 좌우로 뒤집지 않는다 — 공룡 50종은 바라보는 방향이 종마다 다르다 (규칙 26).
	_paint_dino(_sp, pos, 176.0)


## 놀이 마당 — 친구 손, 내 손, 그리고 결과.
func _paint_field() -> void:
	var fh := friend_hand()
	var res := 0                     # -1 친구가 이김 / 0 비김 / 1 내가 이김
	var shown := _state == "show" or _state == "ok" or _state == "no"
	if shown and _pick >= 0:
		res = RpsGen.outcome(_pick, fh)
	# 두 손의 크기 — 이긴 손이 조금 커지고 진 손이 조금 작아진다.
	# ★ 이것이 "왜 그런지"의 알맹이다. 별은 그 위에 얹는 표식일 뿐이다.
	var grow := 0.0
	if _state == "ok" or _state == "no":
		grow = clampf(_anim * 2.2, 0.0, 1.0)
	var f_sc := 1.0 + 0.16 * grow * float(-res)
	var m_sc := 1.0 + 0.16 * grow * float(res)
	var f_rot := 0.0
	if res > 0:
		f_rot = 0.22 * grow          # 진 손이 힘없이 기운다
	var m_rot := 0.0
	if res < 0:
		m_rot = -0.22 * grow

	# 친구 손 (위에서 내려온 손)
	var fa := 1.0
	var fat := FRIEND_AT
	if _state == "enter":
		var a := clampf(_anim, 0.0, 1.0)
		fa = a
		fat.y -= (1.0 - a) * 90.0
	_hand_at(fat, HAND_R * f_sc, fh, Vector2.DOWN, Color(SKIN, fa), f_rot, 1.0)

	# 내 손 (카드에서 올라와 만난다)
	if _pick >= 0 and shown:
		var from := MINE_AT
		var ci := card_index(_pick)
		if ci >= 0:
			var cr := card_rect(ci)
			from = cr.position + Vector2(cr.size.x * 0.5, 108.0)
		var a2 := 1.0 if _state != "show" else clampf(_anim, 0.0, 1.0)
		var at := from.lerp(MINE_AT, a2 * a2)
		var rr := lerpf(66.0, HAND_R, a2) * m_sc
		# ★ 두 손은 **같은 색**이다. 누가 이겼는지는 크기·기울기·별이 말한다.
		#   색으로 "내 손"을 구분하면 신호가 둘이 되고, 옅은 색은 크림 바탕에 녹는다.
		_hand_at(at, rr, _pick, Vector2.UP, SKIN, m_rot, 1.0)

	# 결과 표식 — 목표 팻말과 **똑같은 그림**이라 그대로 견주면 된다.
	if (_state == "ok" or _state == "no") and _pick >= 0:
		var pulse: float = clampf(_anim * 3.0, 0.0, 1.0)
		_paint_verdict(Vector2(MARK_X, (FRIEND_AT.y + MINE_AT.y) * 0.5), 34.0, res, pulse)


func _paint_cards() -> void:
	var cs: Array = cards_now()
	var hintq := hint_hand()
	for i in cs.size():
		var h := int(cs[i])
		var r := card_rect(i)
		var lift := 0.0
		if _bounce > 0.0:
			lift = sin(_bounce * PI) * 8.0
		if _pick == h and _state != "wait":
			lift = 14.0
		var rr := Rect2(r.position - Vector2(0, lift), r.size)
		var bg := CARD_BG
		if hintq == h and _state == "wait":
			var k := 0.5 + 0.5 * sin(_t * 3.0)
			if Shell.reduce_motion:
				k = 0.5
			bg = CARD_BG.lerp(Color(Look.GOLD), 0.55 * k)
		_round_rect(rr, 30.0, bg)
		_round_rect_outline(rr, 30.0, Color(INK_SOFT, 0.35), 4.0)
		_hand_at(rr.position + Vector2(rr.size.x * 0.5, 104.0), 66.0, h, Vector2.UP,
				SKIN, 0.0, 1.0)
		_text_centered(RpsGen.hand_name(h),
				Vector2(rr.position.x + rr.size.x * 0.5, rr.position.y + rr.size.y - 34.0),
				34, INK)


func _paint_name() -> void:
	var nm := DinoSpecies.full_name(_sp)
	var f := ThemeDB.fallback_font
	var w: float = f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x + 52.0
	# ★ 바닥 바로 아래는 카드 자리다. 거기 두면 첫 카드의 손끝을 덮는다.
	var box := Rect2(232.0 - w * 0.5, 246.0, w, 54.0)
	_round_rect(box, 22.0, Color(1, 1, 1, 0.94))
	_text_centered(nm, Vector2(box.position.x + w * 0.5, box.position.y + 38.0), 32, INK)


func _paint_clear() -> void:
	var box := Rect2(W * 0.5 - 300.0, 300.0, 600.0, 130.0)
	_round_rect(box, 40.0, Color(1, 1, 1, 0.94))
	var msg := "%d판 돌파!" % stage if stage % 10 == 0 else "다 맞혔다!"
	_text_centered(msg, Vector2(W * 0.5, box.position.y + 84.0), 52, Look.ACCENT)
	# 두리가 같이 만세한다 (여섯 게임이 같은 순간에 같은 표정을 짓는다).
	# ★ 공룡(x=232) 반대쪽에 세운다 — 왼쪽에 두면 둘이 겹쳐서 등에 올라탄 것처럼 보인다.
	Look.draw_duri(self, "cheer", Vector2(760.0, box.end.y + 222.0), 210.0)


# --------------------------------------------------------------------------- #
# 손 그리기 — 전부 코드다 (규칙 27). 이미지가 아니라 도형이므로 뒤집어도 거짓말이 안 된다.
# --------------------------------------------------------------------------- #

## 손 하나. dir 은 손가락이 뻗는 쪽 (내 손은 위, 친구 손은 아래).
## 그리기 자체는 core/look.gd 에 있다 — 허브 카드와 **같은 손**이어야 하기 때문이다.
func _hand_at(at: Vector2, r: float, kind: int, dir: Vector2, col: Color,
		rot: float, sc: float) -> void:
	_set_tf(at, rot, Vector2(sc, sc))
	Look.draw_hand(self, Vector2.ZERO, r, kind, dir, col)
	_reset_tf()


# --------------------------------------------------------------------------- #
# 그리기 도우미
# --------------------------------------------------------------------------- #

func _set_tf(at: Vector2, rot: float, sc: Vector2) -> void:
	var s := _scale()
	draw_set_transform(_origin() + at * s, rot, sc * s)


func _reset_tf() -> void:
	var s := _scale()
	draw_set_transform(_origin(), 0.0, Vector2(s, s))


func _paint_dino(sp: int, at: Vector2, h: float) -> void:
	var tex := DinoSpecies.texture(sp)
	var dr := DinoSpecies.draw_rect_for(sp)
	if tex == null or dr.size.y <= 0.0:
		_ellipse(at - Vector2(0, h * 0.4), Vector2(h * 0.36, h * 0.4), DinoSpecies.data(sp)["col"])
		return
	var k := h / dr.size.y
	_set_tf(at, 0.0, Vector2(k, k))
	draw_texture_rect(tex, dr, false)
	_reset_tf()


func _round_rect(r: Rect2, rad: float, col: Color) -> void:
	_round_rect_local(r.position, r.size, rad, col)


func _round_rect_local(p: Vector2, sz: Vector2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(sz.x, sz.y) * 0.5)
	draw_rect(Rect2(p.x + rad, p.y, sz.x - rad * 2.0, sz.y), col)
	draw_rect(Rect2(p.x, p.y + rad, rad, sz.y - rad * 2.0), col)
	draw_rect(Rect2(p.x + sz.x - rad, p.y + rad, rad, sz.y - rad * 2.0), col)
	for corner in [Vector2(rad, rad), Vector2(sz.x - rad, rad),
			Vector2(rad, sz.y - rad), Vector2(sz.x - rad, sz.y - rad)]:
		draw_circle(p + corner, rad, col)


func _round_rect_outline(r: Rect2, rad: float, col: Color, wdt: float) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	draw_line(r.position + Vector2(rad, 0), r.position + Vector2(r.size.x - rad, 0), col, wdt)
	draw_line(r.position + Vector2(rad, r.size.y), r.position + Vector2(r.size.x - rad, r.size.y), col, wdt)
	draw_line(r.position + Vector2(0, rad), r.position + Vector2(0, r.size.y - rad), col, wdt)
	draw_line(r.position + Vector2(r.size.x, rad), r.position + Vector2(r.size.x, r.size.y - rad), col, wdt)
	# ★ 귀퉁이는 **사분원**만 그린다. 통째로 그리면 네 귀퉁이에 큰 동그라미가 붙는다.
	draw_arc(r.position + Vector2(rad, rad), rad, PI, PI * 1.5, 8, col, wdt)
	draw_arc(r.position + Vector2(r.size.x - rad, rad), rad, PI * 1.5, TAU, 8, col, wdt)
	draw_arc(r.position + Vector2(r.size.x - rad, r.size.y - rad), rad, 0.0, PI * 0.5, 8, col, wdt)
	draw_arc(r.position + Vector2(rad, r.size.y - rad), rad, PI * 0.5, PI, 8, col, wdt)


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 26:
		var a := TAU * float(i) / 26.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


func _text(s: String, at: Vector2, px: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_centered(s: String, at: Vector2, px: int, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(f, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
