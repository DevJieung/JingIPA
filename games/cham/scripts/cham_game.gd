extends Control

## 참참참 — 친구가 어느 쪽으로 뛸지 손으로 가리켜서 잡는다.
##
## ★ 진짜 참참참에서 바꾼 것 하나: **박자를 없앴다.**
##   원래 놀이는 "참! 참! 참!" 세 번째에 맞춰 손을 내밀고, 늦으면 진다. 그건 이 앱이
##   금지한 것 셋(타이머·시간 압박·지는 것)을 한꺼번에 건드린다. 그래서 여기서는
##   **아이가 누르는 순간이 곧 세 번째 참**이다. 친구는 아이가 누를 때까지 영원히
##   기다리고, 못 맞혀도 지는 것이 아니라 그냥 한 번 더 한다.
##
## ★ 대신 진짜 놀이의 알맹이는 그대로 남겼다 — **상대의 버릇 읽기.**
##   아이들이 참참참에서 이기는 방법이 바로 그것이고, 여기서 친구가 뛰는 방향은
##   무작위가 아니라 주기가 있는 버릇이다 (ChamGen.pattern). 그 증거인 **발자국**이
##   화면에 계속 남아 있어서, 외우는 것이 아니라 보고 읽는 놀이가 된다.
##
## ★ 그래서 **틀리는 것이 벌이 아니라 단서다.** 놓칠 때마다 발자국이 하나 늘고,
##   버릇 한 바퀴가 다 드러나면 다음 방향은 결정돼 있다. 헤맬수록 쉬워진다.
##
## ★ 첫 한 바퀴 동안은 친구가 **뛸 쪽으로 몸을 크게 기울인다(tell).** 그래서 글을 못 읽는
##   아이도 첫 판 첫 탭에 잡을 수 있고(편입 규칙 5), 큰 아이는 tell 이 옅어진 뒤
##   발자국으로 읽는다. 하나의 놀이가 두 나이대를 함께 받는다.
##
## ★ **한 판에 친구는 하나**이고, 그 친구를 여러 번 잡아야 판이 끝난다.
##   잡을 때마다 새 친구가 오면 언제나 "그 친구의 첫 턴"이라 tell 이 공짜로 켜지고,
##   버릇도 발자국도 아무 뜻이 없어진다 — 놀이가 통째로 눈치 게임이 된다.
##   같은 친구와 계속 하는 것이 진짜 참참참이기도 하다: 사람은 여러 판을 하면서
##   상대의 버릇을 읽는다.
##
## ★ 공룡 찾기에서 빌려 오는 것: DinoSpecies (그림·이름·도감 id) · Confetti · Sfx.
##   새 이미지 자산은 0장이다.

const W := 1280.0
const H := 800.0

const BG := Look.BG
const BG2 := Look.BG2
const INK := Look.INK
const INK_SOFT := Look.INK_SOFT
## ★ 바닥과 손은 **바탕보다 확실히 진해야** 한다. 크림 바탕에 살구색 손을 그대로 얹으면
##   손이 배경에 녹아서, 아이가 "누를 것"을 못 알아본다 (한 번 그랬다).
const FLOOR := Color("ddc9a8")
const SKIN := Look.SKIN
const SKIN_HI := Look.SKIN_HI
const MARK := Color("c9a86a")
const MARK_NOW := Color("e8734a")

## 바닥선 (친구의 발이 닿는 높이)
const GROUND := 470.0
## 손 크기. 손목이 축이고 손이 그 위로 1.05r 만큼 올라앉는다 (Look.HAND_LIFT).
const HAND_R := 95.0
## 손목(소매)이 앉는 자리의 높이. 화면 아래끝(800)에 거의 닿아서, 팔을 따로 안 그려도
## "아래에서 올라온 손"으로 읽힌다.
const WRIST_Y := 772.0
## 손이 옆으로 기우는 각 (약 60도). **이것이 방향을 말하는 전부다.**
## ★ 예전에는 옆을 가리키는 손 그림을 따로 뽑아 썼는데, 손가락 하나가 옆으로 뻗은
##   장난감 손은 작게 그려 놓으면 기괴했다. 지금은 가위바위보의 **가위 손**(검지·중지를
##   펴고 주먹 쥔 손)을 손목 축으로 기울인다 — 그림은 늘어나지 않고, 방향은 더 잘 읽힌다.
## ★ 45도로 낮추면 두 손이 "그냥 비스듬한 손 둘"로 보인다. 90도로 올리면 손목이
##   옆으로 눕는다 (아래에서 올라온 손이 아니라 옆에서 들어온 팔이 된다).
const HAND_TILT := 1.05
## 친구 그림의 키
const FRIEND_H := 230.0

## 발자국 줄에 한 번에 보여 줄 최대 개수 (12 x 72px + 여백 < 1280)
const MARKS_MAX := 12

## 연출 길이 (초). ★ 전부 재촉이 아니라 "무슨 일이 일어났는지 보이게" 하는 시간이다.
const JUMP_SEC := 0.42
const CATCH_SEC := 1.20
const MISS_SEC := 0.85
const ENTER_SEC := 0.45
const CLEAR_SEC := 1.60

var stage := 1
var caught := 0                ## 이번 판에서 잡은 수
var misses := 0                ## 이번 판에서 놓친 수
var lifetime := 0
var best_stage := 1
var axes: Dictionary = {}

## --- 적응형 난이도 ------------------------------------------------------- ##
## 아이 눈에 절대 보이지 않는다. 신호는 **놓친 횟수 하나뿐**이고 시간은 안 잰다.
## 이 게임에서 놓침은 공룡 찾기의 빗나간 탭과 달리 뜻이 분명하다 — 가리켰는데 틀렸다.
const SKILL_MIN := -8
const SKILL_MAX := 10
var skill := 0
var ease_streak := 0
var cushion := 0

## 지금 친구
var _sp := 0                   ## 종 인덱스
var _pat: Array[int] = []      ## 이 친구의 버릇
var _turn := 0                 ## 이 친구가 여태 뛴 횟수
var _hist: Array[int] = []     ## 발자국 (뛴 방향들)
var _miss_streak := 0
var _met := false              ## 이 판의 친구를 도감에 한 번 넣었는가

## enter -> wait -> jump -> catch|miss -> ... -> clear -> gone
## ("gone" 은 화면이 갈리기를 기다리는 상태다. 여기서는 _process 가 아무것도 안 한다.)
var _state := "enter"
var _anim := 0.0               ## 0..1
var _pick := -1                ## 아이가 가리킨 쪽
var _dir := -1                 ## 친구가 뛴 쪽
var _t := 0.0
var _bounce := 0.0             ## 손이 "여기야" 하고 튀는 연출

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
	# 색종이는 이 화면의 좌표계(1280x800)에 맞춰 얹는다.
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
		"jump":
			_anim += delta / (JUMP_SEC * mot)
			if _anim >= 1.0:
				_land()
		"catch":
			_anim += delta / (CATCH_SEC * mot)
			if _anim >= 1.0:
				_after_catch()
		"miss":
			_anim += delta / (MISS_SEC * mot)
			if _anim >= 1.0:
				_state = "wait"
				_anim = 0.0
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
	if not p.has("cham"):
		p["cham"] = {
			"best_stage": 1, "caught": 0,
			"skill": 0, "ease_streak": 0, "cushion": 0,
		}
	return p["cham"]


func _load_record() -> void:
	var d := _state_dict()
	best_stage = maxi(1, int(d.get("best_stage", 1)))
	lifetime = maxi(0, int(d.get("caught", 0)))
	skill = clampi(int(d.get("skill", 0)), SKILL_MIN, SKILL_MAX)
	ease_streak = maxi(0, int(d.get("ease_streak", 0)))
	cushion = maxi(0, int(d.get("cushion", 0)))


func _save_record() -> void:
	best_stage = maxi(best_stage, stage)
	var d := _state_dict()
	d["best_stage"] = best_stage
	d["caught"] = lifetime
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
	axes = ChamGen.axes(effective_stage(), Shell.tuning())
	caught = 0
	misses = 0
	fx.clear_all()
	_new_friend()


func _new_friend() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	_sp = _next_species()
	_pat = ChamGen.pattern(int(axes.get("pattern_len", 2)), int(axes.get("dirs", 2)), rng)
	_turn = 0
	_hist.clear()
	_miss_streak = 0
	_pick = -1
	_dir = -1
	_met = false
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
# 이 친구의 버릇 — 게임과 검사기가 같은 함수를 본다
# --------------------------------------------------------------------------- #

## 다음에 뛸 쪽
func next_dir() -> int:
	if _pat.is_empty():
		return ChamGen.LEFT
	return int(_pat[_turn % _pat.size()])


## 지금 몸이 얼마나 기우는가 (0 = 아무 표시 없음, 1 = 확실하게)
##
## ★ 첫 한 바퀴는 **난이도와 상관없이 언제나 1.0** 이다. 그 한 바퀴가 끝나면
##   발자국이 버릇 한 주기를 통째로 담고 있으므로, tell 이 사라져도 다음 쪽이 결정돼 있다.
##   이 두 줄이 "언제나 읽을 수 있다"를 보장한다.
func tell_now() -> float:
	if _turn < _pat.size():
		return 1.0
	if _miss_streak >= 3:
		return 1.0          # 세 번 놓쳤으면 설명이 다시 친절해진다 (규칙 11)
	return float(axes.get("tell", 1.0))


## 다섯 번 놓치면 맞는 손이 조용히 숨을 쉰다. 그래도 "틀렸다"는 말은 어디에도 없다.
func hint_dir() -> int:
	return next_dir() if _miss_streak >= 5 else -1


## tell 이 몸에 드러나는 방식 — 옆으로 선 정도(dx) · 웅크림(squash) · 기울기(rot).
##
## ★ 그리기와 검사기가 **이 함수 하나**를 같이 본다. 검사기가 정답 함수(next_dir)를
##   그냥 부르면 "기울기를 반대로 그려도 통과하는" 항등식이 된다 — 실제로 그랬고
##   적대적 리뷰가 잡았다. 검사기는 이제 여기서 나온 값만 보고 방향을 고른다.
static func tell_pose(dir: int, tell: float) -> Dictionary:
	if dir == ChamGen.UP:
		# 하늘로 뛰기 전에는 웅크린다 (떠 있으면 이미 뛴 것처럼 보인다).
		# ★ 웅크림의 세기(0.26)는 눈대중이 아니다 — tell 이 가장 옅어졌을 때도 옆으로
		#   서는 것만큼은 보여야 한다 (ChamGen.TELL_SQUASH_MAX). 0.16 이었을 때는
		#   높은 탄에서 웅크림이 2.4% 밖에 안 돼 하늘 신호만 먼저 사라졌다.
		return {"dx": 0.0, "dy": 16.0 * tell, "rot": 0.0, "squash": 1.0 - 0.26 * tell}
	var s := -1.0 if dir == ChamGen.LEFT else 1.0
	return {"dx": s * 70.0 * tell, "dy": 0.0, "rot": s * 0.28 * tell, "squash": 1.0}


## 지금 화면에 실제로 그려지고 있는 tell (검사기가 이것만 보고 고른다)
func tell_pose_now() -> Dictionary:
	return tell_pose(next_dir(), tell_now())


# --------------------------------------------------------------------------- #
# 좌표 — 1280x800 로 그리고 화면에 맞춰 통째로 옮긴다
# --------------------------------------------------------------------------- #

func _scale() -> float:
	return minf(size.x / W, size.y / H)


func _origin() -> Vector2:
	var s := _scale()
	return Vector2((size.x - W * s) * 0.5, (size.y - H * s) * 0.5)


func _to_local(p: Vector2) -> Vector2:
	var s := _scale()
	return Vector2.ZERO if s <= 0.0 else (p - _origin()) / s


func dir_count() -> int:
	return int(axes.get("dirs", 2))


## 이 방향 손의 **손목**이 앉는 자리. 여기가 고정이고 손이 이 점을 축으로 기운다.
func hand_wrist(dir: int) -> Vector2:
	if dir_count() >= 3:
		match dir:
			ChamGen.LEFT: return Vector2(300.0, WRIST_Y)
			ChamGen.UP: return Vector2(640.0, WRIST_Y)
			_: return Vector2(980.0, WRIST_Y)
	return Vector2(380.0, WRIST_Y) if dir == ChamGen.LEFT else Vector2(900.0, WRIST_Y)


## 이 방향 손의 손가락이 뻗는 쪽 (기울기). 위 손만 똑바로 선다.
func hand_aim(dir: int) -> Vector2:
	if dir == ChamGen.UP:
		return Vector2.UP
	return Vector2.UP.rotated(-HAND_TILT if dir == ChamGen.LEFT else HAND_TILT)


## 이 방향을 가리키는 손(주먹)의 한가운데. 손목에서 손가락 쪽으로 Look.HAND_LIFT 만큼.
## ★ 잡힌 친구가 앉는 자리도, 힌트 무리도 전부 여기를 본다 — 손이 기울면 같이 따라간다.
func hand_center(dir: int) -> Vector2:
	return hand_wrist(dir) + hand_aim(dir) * (Look.HAND_LIFT * HAND_R)


## 이 방향의 탭 영역. 아래쪽을 통째로 나눠 써서 손가락이 큰 아이도 못 빗나간다.
func hand_zone(dir: int) -> Rect2:
	var n := dir_count()
	var top := 548.0
	var wide := (W - 60.0) / float(n)
	var i := 0
	if n >= 3:
		i = [ChamGen.LEFT, ChamGen.UP, ChamGen.RIGHT].find(dir)
	else:
		i = 0 if dir == ChamGen.LEFT else 1
	return Rect2(30.0 + wide * float(i), top, wide, H - top - 14.0)


## 잔잔하게가 켜져 있으면 반짝이를 절반으로 (다른 게임들과 같은 규칙)
func _fx(n: int) -> int:
	return n / 2 if Shell.reduce_motion else n


## 잡혔을 때 친구가 앉는 자리 (손바닥 위). 그리기와 색종이가 같은 자리를 본다.
func _catch_spot(dir: int) -> Vector2:
	return hand_center(dir) - Vector2(0, 26.0)


## 친구가 그쪽으로 뛰었을 때 발이 닿는 자리
func _land_spot(dir: int) -> Vector2:
	match dir:
		ChamGen.LEFT: return Vector2(hand_center(ChamGen.LEFT).x, GROUND)
		ChamGen.RIGHT: return Vector2(hand_center(ChamGen.RIGHT).x, GROUND)
		_: return Vector2(W * 0.5, GROUND - 190.0)     # 하늘로 폴짝
	return Vector2(W * 0.5, GROUND)


func _home_rect() -> Rect2:
	return Rect2(W - 196.0, 24.0, 164.0, 72.0)


# --------------------------------------------------------------------------- #
# 입력 — 규칙은 하나뿐이다: 손을 하나 누른다
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
		return                      # 축하 중 — 곧 다음 판이다
	if _state != "wait":
		return                      # 뛰는 중에는 받지 않는다 (연타로 두 번 세지 않게)
	for d in _dirs():
		if hand_zone(d).has_point(p):
			_choose(d)
			return
	# 손이 아닌 데를 눌렀다 — 벌이 아니라 "여기야" 하고 손이 한 번 튄다.
	_bounce = 1.0


func _dirs() -> Array[int]:
	var out: Array[int] = []
	out.append(ChamGen.LEFT)
	if dir_count() >= 3:
		out.append(ChamGen.UP)
	out.append(ChamGen.RIGHT)
	return out


func _choose(dir: int) -> void:
	_pick = dir
	_dir = next_dir()
	_state = "jump"
	_anim = 0.0
	sfx.play("tap", 1.1)


# --------------------------------------------------------------------------- #
# 진행
# --------------------------------------------------------------------------- #

func _land() -> void:
	_hist.append(_dir)
	_turn += 1
	_anim = 0.0
	if _dir == _pick:
		_state = "catch"
		_miss_streak = 0
		caught += 1
		lifetime += 1
		# 도감은 집 공용이다 — 여기서 만난 공룡도 같은 칸을 채운다.
		# ★ 한 판에 한 번만 센다. 같은 친구를 세 번 잡았다고 세 번 만난 것은 아니다.
		Shell.bump_today("cham")
		_save_record()
		sfx.play("find", 1.0 + 0.06 * float(caught - 1))
		# ★ 색종이는 친구가 **실제로 있는 자리**(손바닥 위)에서 터져야 한다.
		#   _land_spot 은 빗나갔을 때 떨어지는 바닥 자리라 엉뚱한 데서 터졌다.
		# ★ 크게 터뜨린다. "잡았는지 잘 모르겠다"는 말이 나온 뒤에 22 -> 54 로 올렸다.
		#   두 군데서 터진다 — 손 위(친구가 있는 자리)와 그 아래(손). 한 군데서만
		#   터지면 친구 그림에 가려서 색종이가 절반쯤 안 보인다.
		var cs := _catch_spot(_dir)
		fx.burst(cs + Vector2(0, -110), _fx(54), DinoSpecies.data(_sp)["col"])
		fx.burst(cs + Vector2(0, 10), _fx(26), Look.GOLD)
		if not _met:
			_met = true
			# 도감에 처음 들어가는 종이면 그때 한 번만 비가 내린다.
			# (판마다가 아니라 한 판에 한 번 — 같은 친구를 다섯 번 잡아도 한 번이다.)
			if Shell.dex_meet(DinoSpecies.id_of(_sp)):
				fx.rain(_fx(30))
	else:
		_state = "miss"
		misses += 1
		_miss_streak += 1
		# ★ 놓쳐도 벌이 없다. 발자국이 하나 늘었으니 다음이 오히려 쉬워졌다.
		sfx.play("miss", randf_range(1.0, 1.15))


## 잡았다고 친구가 가 버리지 않는다 — 툭툭 털고 다시 선다. 그래야 버릇이 이어지고,
## 발자국이 쌓이고, 놀이가 "눈치"가 아니라 "읽기"가 된다.
func _after_catch() -> void:
	if caught >= int(axes.get("catches", 3)):
		_state = "clear"
		_anim = 0.0
		_update_skill()
		sfx.play("hooray" if stage % 10 == 0 else "clear")
		fx.rain(_fx(150 if stage % 10 == 0 else 70))
		return
	_state = "wait"
	_anim = 0.0


func _next_stage() -> void:
	# ★ 제일 먼저 상태를 "gone" 으로 돌린다. Router 의 화면 전환은 페이드 때문에
	#   비동기라서, 그동안 _process 가 계속 돌면 여기가 매 프레임 다시 불린다 —
	#   여행이 한 판에 수십 번 넘어가 버린다 (실제로 그랬고, 여행 검사가 잡았다).
	_state = "gone"
	stage += 1
	_save_record()
	if Shell.journey_active and not dev_mode:
		Shell.journey_advance()
		return
	# 한 판이 몇 단위인지는 **등록표가 안다** (game_registry 의 journey_units).
	# 게임이 숫자를 직접 들면 여행 안과 밖이 서로 다른 값으로 세어진다.
	# ★ 상한에 닿았으면 셸이 쉼표를 찍고 허브로 보낸다 (Shell.round_done) —
	#   세션을 새로 열지 않으면 그 뒤로는 한 판마다 튕겨 나간다.
	if Shell.round_done(dev_mode):
		return
	_build_stage()


func _go_home() -> void:
	# ★ 이미 화면이 갈리는 중이면 받지 않는다. 여행에서 판이 끝난 뒤 1초쯤은 옛 씬이
	#   살아서 입력을 받는데, 그때 집으로를 누르면 journey_end() 는 돌고 goto_hub() 는
	#   Router._busy 에 삼켜져서 **여행만 조용히 죽는다.** (공룡·손전등의 `if busy` 와 같은 가드)
	if _state == "gone":
		return
	_state = "gone"
	sfx.play("tap")
	_save_record()
	Shell.journey_end()
	Router.goto_hub()


## 판 하나가 끝날 때 딱 한 번. 신호는 놓친 횟수뿐이고 시간은 안 잰다.
func _update_skill() -> void:
	if cushion > 0:
		cushion -= 1
	var n := maxi(1, int(axes.get("catches", 3)))
	if misses >= n:
		# 잡은 만큼 놓쳤다 = 사실상 찍고 있다. 다음 판은 쉽게, 그 다음은 완충.
		skill = maxi(skill - 1, SKILL_MIN)
		ease_streak = 0
		cushion = 1
	elif misses <= 1:
		# 한 판에 한 번만 놓쳤다 = 읽은 것이다.
		# ★ "놓침 x 2 <= 잡기" 로 두면 찍어도 3판 중 31%가 통과해서, 두 판 연속도 10%다.
		#   규칙 9 가 "4지선다 2연속(1/16)을 숙련으로 오독하지 마라"고 못 박은 그 문턱보다
		#   헐거웠다. 1회 이하로 조이면 잡기 5회 기준 찍어서 나올 확률이 3.5% 다.
		ease_streak += 1
		if ease_streak >= 2:
			skill = mini(skill + 1, SKILL_MAX)
			ease_streak = 0
	else:
		ease_streak = 0


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #

func _draw() -> void:
	var s := _scale()
	var o := _origin()
	draw_set_transform(o, 0.0, Vector2(s, s))

	draw_rect(Rect2(0, 0, W, H), BG)
	for i in 5:
		draw_rect(Rect2(0, 96.0 + float(i) * 150.0, W, 62.0), BG2)
	draw_rect(Rect2(0, GROUND, W, H - GROUND), FLOOR)
	draw_rect(Rect2(0, GROUND, W, 6.0), Color(0, 0, 0, 0.07))

	_paint_header()
	for d in _dirs():
		_paint_hand(d)
	# ★ 발자국은 손보다 **뒤에** 그린다. 하늘 손의 뻗은 검지가 발자국 줄 한가운데를
	#   물어서, 이 게임에서 유일하게 가려지면 안 되는 것을 가렸다.
	_paint_marks()
	_paint_friend()
	if _state == "catch" and caught <= 1:
		_paint_name()
	if _state == "clear":
		_paint_clear()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 기준 화면 밖 여백을 바탕색으로 (레터박스가 검게 보이지 않게)
	if o.x > 0.5:
		draw_rect(Rect2(0, 0, o.x, size.y), BG)
		draw_rect(Rect2(size.x - o.x, 0, o.x, size.y), BG)
	if o.y > 0.5:
		draw_rect(Rect2(0, 0, size.x, o.y), BG)
		draw_rect(Rect2(0, size.y - o.y, size.x, o.y), BG)


func _paint_header() -> void:
	_text("%d번째 판" % stage, Vector2(64.0, 46.0), 30, INK)
	_text("%d번 잡았어요" % caught, Vector2(64.0, 84.0), 22, INK_SOFT)
	# 이번 판에 몇 번 잡아야 하는지 (지금 이 판만 — 누적 기록은 아이 화면에 두지 않는다)
	var need := int(axes.get("catches", 3))
	var col: Color = DinoSpecies.data(_sp)["col"]
	for i in need:
		var at := Vector2(W * 0.5 - float(need - 1) * 40.0 + float(i) * 80.0, 62.0)
		if i < caught:
			draw_circle(at, 19.0, col)
			draw_circle(at, 8.0, Color(1, 1, 1, 0.55))
		else:
			draw_circle(at, 19.0, Color(INK_SOFT, 0.18))
	var hr := _home_rect()
	_round_rect(hr, 18.0, Color("ffe0e6"))
	_text_centered("집으로", Vector2(hr.position.x + hr.size.x * 0.5, hr.position.y + 48.0), 26, INK)


## 발자국 — 이 친구가 여태 뛴 방향. **버릇을 읽는 증거**라서 계속 보인다.
func _paint_marks() -> void:
	if _hist.is_empty():
		return
	# ★ 최근 것만 보여 준다. 다 보여 주면 많이 놓친 아이의 발자국 줄이 화면 밖으로 나간다.
	#   12개면 가장 긴 버릇(5)도 두 바퀴가 넘게 담겨서 읽는 데 모자라지 않는다.
	var n := mini(_hist.size(), MARKS_MAX)
	var from := _hist.size() - n
	var gap := 72.0
	var y := GROUND + 36.0
	var wide := float(n) * gap + 28.0
	_round_rect(Rect2(W * 0.5 - wide * 0.5, y - 27.0, wide, 54.0), 26.0, Color(1, 1, 1, 0.72))
	for i in n:
		var at := Vector2(W * 0.5 - float(n - 1) * gap * 0.5 + float(i) * gap, y)
		var col := MARK_NOW if i == n - 1 else MARK
		_paint_arrow(at, int(_hist[from + i]), 21.0, col)


func _paint_arrow(at: Vector2, dir: int, r: float, col: Color) -> void:
	var d := Vector2.LEFT if dir == ChamGen.LEFT else (Vector2.RIGHT if dir == ChamGen.RIGHT else Vector2.UP)
	var pp := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([
			at + d * r, at - d * r * 0.5 + pp * r * 0.85, at - d * r * 0.5 - pp * r * 0.85]), col)


## 손. 아이가 고른 손은 위로 뻗고, 오래 못 맞히면 맞는 손이 조용히 숨을 쉰다.
##
## ★ 손 그림은 [`core/look.gd`](../../../core/look.gd) 에 있다 — 가위바위보와 **같은 손**이다.
##   두 게임이 다른 손을 쓰면 한 앱으로 안 읽힌다 (원래 색을 같이 쓴 것과 같은 이유).
##   그림이 없으면 거기 있는 도형으로 돈다.
## ★ 방향은 **손을 기울여서** 말한다 (hand_aim). 손목이 축이라 소매는 늘 화면
##   아래끝에 그대로 있고 손만 그쪽으로 눕는다 — 진짜로 손목을 꺾는 것과 같은 움직임이다.
##   손 모양은 가위바위보의 **가위 손**(검지·중지를 펴고 주먹)을 그대로 쓴다.
## ★ 왼손은 오른손 그림을 **뒤집은 것**이다. 여기는 손이 **둘**이라 뒤집으면 그냥
##   왼손이 되고, 그게 곧 아이 자신의 두 손이다 (Look.draw_hand 의 flip 설명).
## ★ 힌트를 **살빛으로** 말하지 않는다. 그림은 제 색을 갖고 있어서 금색을 섞을 수가
##   없기 때문이다. 대신 손 **뒤에서 금빛 무리가 숨을 쉰다** — 신호는 그대로 남고
##   여전히 "틀렸다"는 말은 어디에도 없다.
func _paint_hand(dir: int) -> void:
	var aim := hand_aim(dir)
	var c := hand_center(dir)
	var lift := 0.0
	if _state == "jump" and dir == _pick:
		lift = sin(clampf(_anim, 0.0, 1.0) * PI * 0.5)
	elif (_state == "catch" or _state == "miss") and dir == _pick:
		lift = 1.0
	var bounce := 0.0
	if _bounce > 0.0:
		bounce = sin(_bounce * PI) * 10.0
	var hint := 0.0
	if hint_dir() == dir and _state == "wait":
		hint = 0.5 + 0.5 * sin(_t * 3.0)
		if Shell.reduce_motion:
			hint = 0.5
	# 고른 손은 그 손이 뻗은 쪽으로 쑥 나간다 (위로만 올리면 기운 손이 어색하다)
	var at := c + aim * (30.0 * lift) - Vector2(0, bounce)
	if hint > 0.0:
		# ★ 손 **뒤에** 깐다. 위에 얹으면 그림을 덮어서 무슨 손인지 안 보인다.
		#   한가운데를 손목 쪽으로 조금 내린다 — 그림 손은 `at` 뒤쪽이 더 길다.
		#   ★ 동그라미 셋을 겹쳐서 가장자리를 흐린다. 한 겹이면 테두리가 칼같이 잘려서
		#     "안내"가 아니라 "표시된 것"으로 보인다 — 이 나이대에는 그게 지목이 된다.
		var hc := at - aim * (HAND_R * 0.14)
		for hk in 3:
			var hr := HAND_R * (1.34 + 0.08 * hint) * (1.0 - 0.16 * float(hk))
			draw_circle(hc, hr, Color(Look.GOLD, (0.05 + 0.11 * hint)))
	var col := SKIN_HI if lift > 0.01 else SKIN
	# ★ 손목은 화면 아래끝(800)에 거의 닿는다 — 그래서 팔을 따로 안 그려도
	#   "아래에서 올라온 손"으로 읽힌다. HAND_R 을 키우면 손목이 화면 밖으로 나간다.
	Look.draw_hand(self, at, HAND_R, Look.HAND_SCISSORS, aim, col, dir == ChamGen.LEFT)
	# 잡은 순간 — 그 손에서 금빛이 터진다. "여기서 일어났다"를 말하는 것이다.
	if _state == "catch" and dir == _pick and not Shell.reduce_motion:
		Look.draw_pop(self, c, clampf(_anim, 0.0, 1.4) * 1.6, HAND_R * 0.95)


## 친구가 지금 그림에서 **어느 쪽을 보고 있는가** (1 = 그림 그대로, -1 = 뒤집힘).
##
## ★ 이 게임에서 유일하게 그림을 뒤집는 곳이고, 그래서 조건이 좁다:
##   **뛴 뒤에만** 돌린다 (jump · catch · miss). 뛰기 전(wait)에 돌리면 답을 미리
##   알려 주는 것이라 난이도 축이 통째로 무너진다. 여기가 "이겼는지 알아차리기"를
##   돕는 장치이지 tell 이 아니다.
## ★ 뒤집어도 되는 이유는 **방향 표**가 있기 때문이다 (DinoSpecies.FACE, 규칙 26).
##   표에 없거나 정면을 보는 종(0)은 **안 돌린다** — 모르는 채로 뒤집는 것이
##   그 규칙이 막으려는 일이다.
func friend_face() -> float:
	if _state != "jump" and _state != "catch" and _state != "miss":
		return 1.0
	if _dir == ChamGen.UP:
		return 1.0                  # 하늘로 뛰면 돌아볼 쪽이 없다
	var art := DinoSpecies.face_of(_sp)
	if art == 0:
		return 1.0                  # 정면을 보는 그림 — 뒤집어도 아무 말이 안 된다
	var want := -1 if _dir == ChamGen.LEFT else 1
	return float(want * art)


## 친구. 상태에 따라 자리·기울기·납작함이 달라진다.
func _paint_friend() -> void:
	var pos := Vector2(W * 0.5, GROUND)
	var rot := 0.0
	var squash := 1.0
	var tell := tell_now()
	var nd := next_dir()
	match _state:
		"enter":
			var a := clampf(_anim, 0.0, 1.0)
			pos.x = W * 0.5 + (1.0 - a) * 420.0
			pos.y = GROUND - sin(a * PI) * 40.0
		"wait":
			# 참~ 참~ 참~ — **위아래로만** 살랑살랑.
			# ★ 좌우로는 흔들지 않는다. 좌우 움직임은 오직 tell 이어야 한다 —
			#   흔들림이 옅어진 tell 보다 크면, 그 순간 몸이 **반대쪽을 가리키는 것처럼**
			#   보인다. 신호를 섞어서 아이에게 거짓말을 하는 셈이다.
			pos.y = GROUND - absf(sin(_t * 3.4)) * 10.0
			squash = 1.0 + sin(_t * 6.8) * 0.03
			var tp := tell_pose(nd, tell)
			pos.x += float(tp["dx"])
			pos.y += float(tp["dy"])
			rot = float(tp["rot"])
			squash *= float(tp["squash"])
		"jump":
			var a := clampf(_anim, 0.0, 1.0)
			var to := _land_spot(_dir)
			if _dir == _pick:
				to = _catch_spot(_dir)                      # 손바닥 위로
			pos = Vector2(W * 0.5, GROUND).lerp(to, a)
			pos.y -= sin(a * PI) * 150.0
			rot = sin(a * PI) * (0.0 if _dir == ChamGen.UP else (-0.5 if _dir == ChamGen.LEFT else 0.5))
		"catch":
			var to := _catch_spot(_dir)
			var a := clampf(_anim, 0.0, 1.0)
			if a < 0.65:
				# 손바닥 위에서 폴짝폴짝 (잡혔는데 신났다)
				pos = to - Vector2(0, absf(sin(_t * 7.0)) * 16.0)
				squash = 1.0 + sin(_t * 14.0) * 0.05
			else:
				# 툭툭 털고 제자리로 — 이 친구와 한 판 더 한다
				var b := (a - 0.65) / 0.35
				pos = to.lerp(Vector2(W * 0.5, GROUND), b)
				pos.y -= sin(b * PI) * 90.0
		"miss":
			var a := clampf(_anim, 0.0, 1.0)
			var from := _land_spot(_dir)
			if a < 0.6:
				# 까르르 웃으며 폴짝폴짝 (놀리는 것이 아니라 신난 것)
				pos = from - Vector2(0, absf(sin(_t * 9.0)) * 18.0)
				rot = sin(_t * 9.0) * 0.10
			else:
				var b := (a - 0.6) / 0.4
				pos = from.lerp(Vector2(W * 0.5, GROUND), b)
				pos.y -= sin(b * PI) * 90.0
		"clear":
			pos = Vector2(W * 0.5, GROUND - absf(sin(_t * 6.0)) * 22.0)
			squash = 1.0 + sin(_t * 12.0) * 0.05
	# ★ 뛴 뒤에는 친구가 **뛴 쪽으로 몸을 돌린다** (friend_face). 예전에는 여기서
	#   절대 안 뒤집었는데, 그건 50종의 방향 표가 없었기 때문이다 — 이제 표가 있다
	#   (DinoSpecies.FACE). 뛰기 전에는 여전히 안 돌린다: 그건 tell 이 아니라 답이다.
	var face := friend_face()
	# 그림자
	var sh: float = clampf(1.0 - (GROUND - pos.y) / 260.0, 0.25, 1.0)
	_ellipse(Vector2(pos.x, GROUND + 4.0), Vector2(66.0 * sh, 14.0 * sh), Color(0, 0, 0, 0.10))
	# 발밑 먼지 — 뛰려는 쪽으로 발을 비빈다. 몸이 기우는 것만으로는 공룡 그림이
	# 좌우 대칭이 아니라서 읽기 어려운 아이가 있다. tell 이 옅어지면 같이 옅어진다.
	if _state == "wait" and tell > 0.02:
		if nd == ChamGen.UP:
			# 웅크린 발 양옆으로 먼지 — "위로 튀어 오를 참"
			for sgn in [-1.0, 1.0]:
				_ellipse(Vector2(pos.x + sgn * 58.0, GROUND - 6.0), Vector2(20.0, 12.0),
						Color(0.58, 0.47, 0.36, 0.5 * tell))
		else:
			var dd := Vector2.LEFT if nd == ChamGen.LEFT else Vector2.RIGHT
			for i in 3:
				var puff := Vector2(pos.x, GROUND) + dd * (52.0 + float(i) * 34.0) + Vector2(0, -8.0 - float(i) * 7.0)
				_ellipse(puff, Vector2(22.0 - float(i) * 4.0, 13.0 - float(i) * 3.0),
						Color(0.58, 0.47, 0.36, (0.55 - 0.13 * float(i)) * tell))
	_paint_dino(_sp, pos, FRIEND_H, face, rot, Color.WHITE, squash)


## 잡은 친구의 이름 (도감과 같은 이름이다 — 두 놀이가 같은 세계로 묶인다)
func _paint_name() -> void:
	var nm := DinoSpecies.full_name(_sp)
	var f := ThemeDB.fallback_font
	var w: float = f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 56.0
	# ★ 위쪽에 띄운다. 친구 옆이나 바닥에 두면 발자국 줄을 덮는데, 발자국은 이 게임에서
	#   가려지면 안 되는 유일한 것이다.
	var box := Rect2(W * 0.5 - w * 0.5, 104.0, w, 60.0)
	_round_rect(box, 24.0, Color(1, 1, 1, 0.94))
	_text_centered(nm, Vector2(box.position.x + w * 0.5, box.position.y + 42.0), 34, INK)


func _paint_clear() -> void:
	var box := Rect2(W * 0.5 - 300.0, 150.0, 600.0, 130.0)
	_round_rect(box, 40.0, Color(1, 1, 1, 0.94))
	var msg := "%d판 돌파!" % stage if stage % 10 == 0 else "친구 다 잡았다!"
	_text_centered(msg, Vector2(W * 0.5, box.position.y + 84.0), 52, Look.ACCENT)
	# 두리가 같이 만세한다 (다섯 게임이 같은 순간에 같은 표정을 짓는다)
	Look.draw_duri(self, "cheer", Vector2(box.position.x - 40.0, box.end.y + 24.0), 210.0)


## 공룡 그림 하나. 발이 at 에 닿게, 키를 h 로 맞춰서.
func _paint_dino(sp: int, at: Vector2, h: float, face: float, rot: float,
		tint: Color, squash := 1.0) -> void:
	var tex := DinoSpecies.texture(sp)
	var dr := DinoSpecies.draw_rect_for(sp)
	if tex == null or dr.size.y <= 0.0:
		_ellipse(at - Vector2(0, h * 0.4), Vector2(h * 0.36, h * 0.4), DinoSpecies.data(sp)["col"])
		return
	var k := h / dr.size.y
	_set_tf(at, rot, Vector2(face * k / squash, k * squash))
	draw_texture_rect(tex, dr, false, tint)
	_reset_tf()


# --------------------------------------------------------------------------- #
# 그리기 도우미
# --------------------------------------------------------------------------- #

## 바깥 좌표계(_draw 가 걸어 둔 것) 위에 한 겹 더 얹는다.
## ★ draw_set_transform 은 **덮어쓴다**. 화면 맞춤(origin/scale)을 여기서 다시 곱해 주지 않으면
##   다른 해상도에서 공룡만 엉뚱한 자리에 그려진다.
func _set_tf(at: Vector2, rot: float, sc: Vector2) -> void:
	var s := _scale()
	draw_set_transform(_origin() + at * s, rot, sc * s)


func _reset_tf() -> void:
	var s := _scale()
	draw_set_transform(_origin(), 0.0, Vector2(s, s))


func _round_rect(r: Rect2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2.0, r.size.y), col)
	draw_rect(Rect2(r.position.x, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	draw_rect(Rect2(r.position.x + r.size.x - rad, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	for corner in [Vector2(rad, rad), Vector2(r.size.x - rad, rad),
			Vector2(rad, r.size.y - rad), Vector2(r.size.x - rad, r.size.y - rad)]:
		draw_circle(r.position + corner, rad, col)


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
