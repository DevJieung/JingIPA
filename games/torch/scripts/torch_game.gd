extends Node2D

## 손전등 찾기 — 깜깜한 방을 좁은 손전등으로 비춰 공룡을 찾는다.
##
## 공룡 찾기(games/dino/)의 **개조판**이다. 방·가구·공룡·효과음을 그대로 빌려 쓰고
## 바꾼 것은 하나뿐 — 무엇이 공룡을 숨기는가. 저기서는 가구가 숨기고, 여기서는 어둠이 숨긴다.
##
## ★ 조작 규칙은 하나뿐이다:
##
##     탭 -> 손전등이 그 자리로 간다.
##     그때 그 공룡이 **이미 비춰져 있었으면**, 그 공룡을 찾은 것이다.
##
##   그래서 어두운 데를 마구 찍어서 얻어걸리는 일이 없다. 비춰 보고, 보고 나서 누른다.
##   드래그도 길게 누르기도 없고, 두 탭 사이에 시간 제한도 없다 (더블탭이 아니다 —
##   두 번의 탭이 각각 다른 뜻을 가진, 순서만 있는 두 동작이다).
##
##   ⚠ 첫 탭은 **절대 무반응이 아니다.** 빛이 닿은 자리에 공룡이 있으면 그 공룡이
##     몸을 흔들고 작은 소리가 난다. 이 나이대에게 "맞게 눌렀는데 아무 일도 없음"은
##     틀린 것과 구분되지 않는다 (규칙 2·11).
##
## ★ 어둠이 무섭지 않게 하는 장치들 — 하나라도 빼지 마라:
##   1. 방은 **밝게 시작한다.** 아이가 방을 다 본 뒤에 해가 진다 (1.1초 + 0.9초).
##      어둠에 던져지는 것이 아니라 어둠이 찾아오는 것이다.
##   2. 어둠은 검정이 아니라 짙은 남보라이고, 상한이 있다 (TorchGen.DARK_CEIL).
##   3. 창으로 드는 **달빛은 꺼지지 않는다.** 방에 항상 안전한 구석이 있다.
##   4. 찾은 공룡은 어둠 위에서 계속 빛나며 춤춘다. **놀수록 방이 밝아진다.**
##   5. 다 찾으면 방에 불이 켜진다. 매 방이 밝음으로 끝난다.
##   6. 놀이 중에 어둠이 짙어지는 일은 없다. 내려가기만 한다.
##   7. 어둠 속에서 움직이는 것은 착한 것뿐이다 — 눈도 그림자도 그리지 않는다.
##
## ★ 공룡 찾기에서 빌려 오는 것 (games/dino/ 를 고칠 때 여기도 같이 본다):
##     Rooms · RoomGen (방 생성)   Prop · RoomBg (가구·배경)
##     Dino · DinoSpecies · DinoArt · DinoRow (공룡)   Sfx · Confetti (소리·반짝이)
##   언젠가 이것들을 core/ 로 승격하는 것이 옳다. 그때까지는 tests/torch_check.gd 가
##   방 생성이 조용히 어긋나는 것을 잡아 준다.

const W := 1280.0
const H := 720.0

## 아무것도 안 누르고 이만큼 지나면 손전등이 저절로 켜진다.
## (재촉이 아니라 안내다. 아이를 어둠에 혼자 두지 않는다.)
const WAKE_SEC := 3.0

var stage := 1
var room: Dictionary = {}
var dinos: Array[Dino] = []
var props: Array[Prop] = []
var found := 0
var total_found := 0           ## 이번 판에서 찾은 수 (누적 아님 — 규칙 5)
var best_stage := 1
var lifetime_found := 0
var state := "intro"           ## intro -> play -> clear
var busy := false
var idle := 0.0
var wake := 0.0

## --- 적응형 난이도 ------------------------------------------------------- ##
## 아이 눈에 절대 보이지 않는다. 탄 번호는 그대로 두고 난이도만 조용히 움직인다.
## ★ 신호는 **힌트 발동 횟수 하나뿐**이다. 초시계도, 빗나간 탭 수도 안 본다 —
##   손전등 게임에서 빛을 옮기는 탭은 실수가 아니라 **정상적인 탐색**이기 때문이다.
##   그걸 실수로 세면 열심히 훑는 아이가 못하는 아이로 읽힌다.
const SKILL_MIN := -8
const SKILL_MAX := 10
var skill := 0
var ease_streak := 0
var cushion := 0
var hints_this_room := 0
## 마지막으로 공룡을 보거나 찾은 뒤로 **헛되이 비춘** 횟수.
## ★ 이게 없으면 힌트가 영영 안 뜬다. 이 게임은 탭마다 idle 을 리셋하기 때문에
##   (그래야 훑는 아이에게 힌트가 안 터진다) "가만히 있으면 힌트"라는 조건 하나만으로는
##   **두드리는 동안 절대 발동하지 않는다.** 그러면 힌트 횟수를 신호로 쓰는 적응형이
##   "힌트 0회 = 잘했다"를 "쉬지 않고 두드렸다"로 오독해서, 헤매는 아이의 난이도까지
##   조용히 올린다. 실제로 그렇게 짜여 있었다 — 방을 한 바퀴 반 훑도록 아무것도 못 봤으면
##   그건 "가만히 있는 것"과 똑같이 도와줘야 하는 상태다.
var dry_taps := 0
var axes: Dictionary = {}

## tests/torch_check.gd 가 켠다. 켜지면 연출을 건너뛰고 여행/세션도 건드리지 않는다.
var dev_mode := false
var _slow := 1.0
var _pool: Array = []
## 방이 새로 만들어질 때마다 오른다. await 뒤에 이 값이 바뀌었으면 그 흐름은 버린다.
var _gen := 0
var _intro_done := false

var world: Node2D
var beam: TorchBeam
var fx: Confetti
var sfx: Sfx
var hud: TorchHud


# ================================================================= 준비

func _ready() -> void:
	randomize()
	_load_record()

	world = Node2D.new()
	add_child(world)
	beam = TorchBeam.new()
	world.add_child(beam)
	fx = Confetti.new()
	add_child(fx)
	sfx = Sfx.new()
	sfx.enabled = Shell.sfx_enabled
	add_child(sfx)
	Shell.settings_changed.connect(_pull_settings)

	hud = TorchHud.new()
	hud.slow = _slow
	hud.home_pressed.connect(_go_home)
	add_child(hud)

	stage = maxi(1, best_stage)
	total_found = 0
	_build_room()


func _pull_settings() -> void:
	if sfx != null:
		sfx.enabled = Shell.sfx_enabled


# ================================================================= 저장

## 이 프로필의 손전등 찾기 기록. 없으면 만들어서 준다.
##
## ★ 공룡 찾기와 **칸을 나눠 쓰지 않는다.** best_stage 는 설계상 절대 안 내려가는데
##   (규칙 14), 칸을 공유하면 손전등에서 번 탄이 밝은 방의 난이도를 올려 버리고
##   되돌릴 방법이 없다. 두 게임의 유효탄은 같은 단위가 아니다.
##   단, **도감은 공용이다** — 어둠 속에서 만난 트리케라톱스도 같은 트리케라톱스다.
func _state() -> Dictionary:
	var p := Shell.profile()
	if not p.has("torch"):
		p["torch"] = {
			"best_stage": 1, "lifetime_found": 0,
			"skill": 0, "ease_streak": 0, "cushion": 0,
		}
	return p["torch"]


func _load_record() -> void:
	var d := _state()
	best_stage = maxi(1, int(d.get("best_stage", 1)))
	lifetime_found = maxi(0, int(d.get("lifetime_found", 0)))
	skill = clampi(int(d.get("skill", 0)), SKILL_MIN, SKILL_MAX)
	ease_streak = maxi(0, int(d.get("ease_streak", 0)))
	cushion = maxi(0, int(d.get("cushion", 0)))


func _save_record() -> void:
	best_stage = maxi(best_stage, stage)
	var d := _state()
	d["best_stage"] = best_stage
	d["lifetime_found"] = lifetime_found
	d["skill"] = skill
	d["ease_streak"] = ease_streak
	d["cushion"] = cushion
	Shell.mark_dirty()


# ================================================================= 방 만들기

## 난이도용 유효탄. 아이가 보는 탄 번호(stage)와 분리돼 있다.
## 10탄 배수(축하 방)는 항상 조금 쉽게 — 축하하는 방이 제일 어려우면 안 된다.
func effective_stage() -> int:
	var e := stage + skill - cushion * 2
	if stage % 10 == 0:
		e -= 3
	return clampi(e, 1, 999)


func _clear_world() -> void:
	for c in world.get_children():
		if c != beam:
			c.queue_free()
	dinos.clear()
	props.clear()


func _add_props(list: Array, z: int) -> Array[Prop]:
	var out: Array[Prop] = []
	for d in list:
		var p := Prop.new()
		p.setup(String(d["kind"]), float(d["w"]), float(d["h"]), d["col"], d["col2"])
		p.position = Vector2(float(d["x"]), float(d["y"]))
		p.z_index = z
		world.add_child(p)
		out.append(p)
	return out


func _build_room() -> void:
	_gen += 1
	var gen := _gen
	var e := effective_stage()
	var t := Shell.tuning()
	axes = TorchGen.axes(e, t)
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	room = TorchGen.stage_room(e, rng, stage, t)

	_clear_world()
	fx.clear_all()
	found = 0
	idle = 0.0
	wake = 0.0
	dry_taps = 0
	busy = false
	hints_this_room = 0
	state = "intro"
	_intro_done = false

	var bg := RoomBg.new()
	bg.data = room
	bg.z_index = -20
	world.add_child(bg)
	_add_props(room["back"], -10)

	var places: Array = []
	for sp in (room["spots"] as Array).slice(0, int(room["count"])):
		places.append(Rooms.spot_transform(room["front"], sp))
	# ★ 안전망. 공룡이 하나도 없는 방은 **끝날 방법이 없다** — 다 찾았는지 세는 곳이
	#   _on_found 뿐이라 아이가 무엇을 눌러도 영원히 그 방에 남는다.
	#   검사기가 312방을 봐도 한 번도 안 나왔지만, 여기서 막는 값이 0원이다.
	if places.is_empty():
		push_warning("손전등 찾기: 숨을 자리가 없는 방 — 가운데에 한 마리를 세운다")
		places.append({"pos": Vector2(W * 0.5, 620.0), "face": 1.0})
	var species: Array = []
	for i in places.size():
		var sp := _next_species(species)
		var st: Dictionary = places[i]
		var d := Dino.new()
		d.setup(sp, st["pos"], st["face"])
		# ★ 밝은 방을 보여 주는 동안에는 공룡이 없다. 여기서 보여 주면 게임이 시작 전에 끝난다.
		d.visible = false
		world.add_child(d)
		dinos.append(d)
		species.append(sp)
	props = _add_props(room["front"], 20)

	beam.setup(float(axes["beam"]), float(axes["dark"]), _suggest_spot(), _moon_spot(room))
	hud.set_room(String(room["name"]), _sub_text(), species)
	_intro(gen)


## 처음 두 방은 첫 탭이 곧바로 성공으로 이어지게 한다 (편입 규칙 5: 첫 60초 안에 성공).
## 숨는 자리를 손보는 것이 아니라 **어디를 눌러 보라고 할지**만 정한다 — 그래서
## 난이도 곡선에는 아무 영향이 없고, 규칙을 배우는 첫 두 방만 확실히 성공한다.
func _suggest_spot() -> Vector2:
	if stage <= 2 and not dinos.is_empty():
		var best: Dino = dinos[0]
		var bd := 1e30
		for d in dinos:
			var dd := absf(d.base_pos.x - W * 0.5)
			if dd < bd:
				bd = dd
				best = d
		return best.hit_rect().get_center()
	return Vector2(W * 0.5, H * 0.56)


## 달빛이 드는 자리 = 창. 창이 없는 방이면 벽 가운데를 약하게 밝힌다.
func _moon_spot(r: Dictionary) -> Vector2:
	for p in (r["back"] as Array):
		if String((p as Dictionary)["kind"]) == "window":
			return Vector2(float(p["x"]), float(p["y"]) - float(p["h"]) * 0.5)
	return Vector2(W * 0.5, 270.0)


## 한 방 안에서 같은 종이 겹치지 않게, 한 판 동안은 골고루 나오게 뽑는다.
##
## ★ 공룡 찾기의 "작은 종 편향" 축은 여기 없다. 어둠 속에서는 크기가 아니라
##   **어디를 비췄는가**가 난이도를 정하고, 작은 종까지 얹으면 축이 하나 더 곱해진다.
func _next_species(avoid: Array) -> int:
	# 아직 도감에 없는 종을 먼저 (큰 아이 프로필만). 도감은 두 게임이 같이 채운다.
	if bool(Shell.tune("dino_dex_hunt", false)) and avoid.is_empty():
		var unmet := Shell.unmet_indices()
		if not unmet.is_empty():
			var pick := int(unmet[randi() % unmet.size()])
			_pool.erase(pick)
			return pick
	for attempt in 2:
		if _pool.is_empty():
			_pool = range(DinoSpecies.count())
			_pool.shuffle()
		for i in _pool.size():
			if not avoid.has(_pool[i]):
				return int(_pool.pop_at(i))
		_pool.clear()
	return randi() % DinoSpecies.count()


func _sub_text() -> String:
	if Shell.journey_active:
		return "섬 %d번째" % Shell.journey_stage
	return "%d탄 · 공룡 %d마리" % [stage, total_found]


# ================================================================= 해가 진다

## 방을 밝게 한 번 보여 주고 나서 어두워진다.
## 어둠에 던져지는 것과 어둠이 찾아오는 것은 이 나이대에게 완전히 다른 경험이다.
func _intro(gen: int) -> void:
	var mot := Shell.anim_scale()
	await _wait(1.1 * _slow * mot)
	if gen != _gen or not is_inside_tree() or _intro_done:
		return
	for d in dinos:
		d.visible = true
	beam.dusk(0.9 * _slow * mot)
	await _wait(0.95 * _slow * mot)
	if gen != _gen or not is_inside_tree():
		return
	_finish_intro(true)


## 아이가 기다리지 않고 눌렀으면 그 자리에서 해를 마저 넘긴다 (재촉의 반대 — 기다림을 없앤다).
##
## ★ 그래도 **뚝 끊어서 어두워지지는 않는다.** 밝은 방을 보는 중에 눌렀으면
##   0.3초에 걸쳐 해가 진다. 급전환은 이 나이대에게 그 자체로 놀라운 사건이다.
func _finish_intro(instant := false) -> void:
	if _intro_done:
		return
	_intro_done = true
	for d in dinos:
		d.visible = true
	if instant:
		beam.dark = beam.dark_full
	elif beam.dark < beam.dark_full - 0.01:
		beam.dusk(0.30 * _slow * Shell.anim_scale())
	state = "play"
	idle = 0.0
	wake = 0.0


func _wait(secs: float) -> void:
	await get_tree().create_timer(maxf(0.01, secs), true, false, true).timeout


# ================================================================= 입력

func _unhandled_input(event: InputEvent) -> void:
	if busy:
		return
	if not (event is InputEventMouseButton and event.pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	var p := get_global_mouse_position()
	if state == "intro":
		_finish_intro()
		_aim(p)
	elif state == "play":
		_tap(p)


## 누른 곳에 걸리는 공룡. 겹칠 때는 가운데에 가장 가까운 것.
func _pick_tapped(p: Vector2) -> Dino:
	var best: Dino = null
	var bd := 1e30
	for d in dinos:
		if d.found or not d.hit_rect().has_point(p):
			continue
		var dist := absf(d.base_pos.x - p.x) + absf(d.base_pos.y - 60.0 - p.y) * 0.5
		if dist < bd:
			bd = dist
			best = d
	return best


func _tap(p: Vector2) -> void:
	# ★ idle 은 **모든 탭에서** 리셋한다. 밝은 방의 공룡 찾기와 정반대인 지점이다 —
	#   거기서 빗나간 탭은 "헤매는 중"이지만, 여기서 빛을 옮기는 탭은 방을 훑는
	#   정상적인 탐색이다. 리셋을 안 하면 열심히 훑는 아이에게 힌트가 계속 터지고,
	#   적응형이 그걸 "헤맨다"로 읽어 잘하는 아이의 난이도를 내린다.
	idle = 0.0
	# ★ 판정의 기준은 **손가락이 아니라 공룡**이다: 그 공룡이 비춰져 있었으면 찾은 것이다.
	#   손가락이 빛 원 안이어야 한다고 하면, 빛 가장자리에 걸린 공룡을 아이가 보고
	#   정확히 눌렀는데 **아무 일도 안 일어나는** 경우가 생긴다. 이 나이대에게 그건
	#   틀린 것과 구분되지 않는다 (규칙 2·11). 반대로 어두운 데의 공룡은 여전히
	#   절대 안 찾아진다 — 그 공룡이 비춰지지 않았기 때문이다.
	var hit := _pick_tapped(p)
	if hit != null and beam.lit(hit.hit_rect().get_center()):
		_on_found(hit)
		return
	# ★ `hit == null` 이 빠져 있었다. 손가락 밑에 공룡이 있는데 그 공룡의 중심이
	#   아직 안 밝은 경우(판정 반경 HIT=0.90 이 눈에 보이는 빛 웅덩이 0.98 보다 좁다),
	#   여기 가구 분기가 탭을 통째로 먹고 **손전등이 그 자리로 가지도 않았다.**
	#   아이는 보이는 공룡을 정확히 눌렀는데 "틀림" 소리만 듣고, 같은 데를 다시 눌러도
	#   똑같다 — 이 나이대에게 그건 틀린 것과 구분되지 않는다 (규칙 2·11).
	#   숨는 자리가 전부 가구 옆·뒤라(가림 평균 50%) 방마다 2~4곳씩 있었다.
	#   이제 공룡 위를 누른 탭은 언제나 _aim 으로 간다 — 빛이 그리로 옮겨 가고
	#   공룡이 몸을 흔든다("여기 뭔가 있다"). 다음 탭이 그 공룡을 찾는다.
	if hit == null and beam.lit(p):
		# 빛 안인데 공룡이 아니다 — 벌은 없고 가구가 반응만 한다.
		for i in range(props.size() - 1, -1, -1):
			if props[i].rect().has_point(p):
				props[i].jiggle()
				sfx.play("miss", randf_range(0.95, 1.1))
				fx.burst(p, 4, Color("ffe9b0"))
				dry_taps += 1
				return
	_aim(p)


func _aim(p: Vector2) -> void:
	beam.aim(p)
	sfx.play("tap", 1.15)
	# ★ 빛이 닿은 자리에 공룡이 있으면 몸을 흔들고 작은 소리가 난다.
	#   찾은 것은 아니지만 "여기 뭔가 있다"가 반드시 와야 한다 — 정확히 누른 아이에게
	#   침묵으로 답하면, 그건 이 나이대에게 실패와 구분되지 않는다.
	var seen := false
	for d in dinos:
		if d.found:
			continue
		if beam.lit(d.hit_rect().get_center()):
			d.hint()
			seen = true
	if seen:
		sfx.play("find", 0.62)
		dry_taps = 0        # 뭔가 보였다 = 헛걸음이 아니다
	else:
		dry_taps += 1


func _on_found(d: Dino) -> void:
	d.celebrate()
	# ★ 어둠(z 50) 위로 올라온다 — 찾은 공룡은 방이 어두워도 계속 빛나며 춤춘다.
	d.z_index = 60
	var c := d.hit_rect().get_center()
	beam.add_glow(c, 150.0, 0.055)
	found += 1
	total_found += 1
	lifetime_found += 1
	idle = 0.0
	dry_taps = 0
	# 도감은 집 공용이다. 어둠 속에서 만났든 밝은 방에서 만났든 같은 칸이 찬다.
	var first := Shell.dex_meet(DinoSpecies.id_of(d.species))
	Shell.bump_today("torch")
	# 방 중간에 앱을 꺼도 찾은 것이 사라지지 않게 여기서 저장한다.
	_save_record()
	if first:
		fx.rain(30)
	hud.set_sub(_sub_text())
	hud.set_found(found)
	sfx.play("find", 1.0 + 0.06 * float(found - 1))
	fx.burst(d.base_pos + Vector2(0, -100), 22, DinoSpecies.data(d.species)["col"])
	hud.show_card(d)
	if found >= dinos.size():
		_room_clear()


# ================================================================= 진행

func _room_clear() -> void:
	busy = true
	state = "clear"
	_update_skill()
	var gen := _gen
	var mot := Shell.anim_scale()
	# ★ 다 찾으면 방에 불이 켜진다. 미리 예고하지 않고 그냥 일어나고,
	#   보상이 놀이 밖 화폐가 아니라 **놀이 그 자체의 연장**이다 (규칙 6).
	beam.reveal(0.8 * _slow * mot)
	await _wait(1.1 * _slow * mot)
	if gen != _gen or not is_inside_tree():
		return
	var milestone := stage % 10 == 0
	var rain := 150 if milestone else 70
	if Shell.reduce_motion:
		rain = rain / 2
	sfx.play("hooray" if milestone else "clear")
	fx.rain(rain)
	# ★ 칭찬은 사람이 아니라 사건을 말한다. "잘했어요"는 능력 귀인을 만들고,
	#   그 귀인은 실패할 때 정확히 반대로 뒤집힌다.
	hud.show_banner("%d탄 돌파!" % stage if milestone else "%s 불 켰다!" % String(room["name"]))
	await _wait((1.9 if milestone else 1.3) * _slow * mot)
	if gen != _gen or not is_inside_tree():
		return
	hud.hide_banner()
	stage += 1
	_save_record()
	# 「섬 한 바퀴」로 들어왔으면 한 방만 하고 셸에 돌려준다.
	if Shell.journey_active and not dev_mode:
		Shell.journey_advance()
		return
	# 방 하나가 개구리 문제 3개쯤의 놀이 단위다 (공룡 찾기와 같다).
	# ★ 상한에 닿았으면 셸이 쉼표를 찍고 허브로 보낸다 — 여기서 제 페이드로 덮은 뒤
	#   Router 를 부르면 [덮임 -> 방이 다시 보임 -> 다시 덮임] 으로 한 번 깜빡였다.
	#   아이 눈에는 "넘어가려다 실패한 것"으로 보인다.
	if Shell.round_done(dev_mode):
		return
	await _fade(_build_room)


func _go_home() -> void:
	if busy:
		return
	sfx.play("tap")
	_save_record()
	Shell.journey_end()
	Router.goto_hub()


## 적응형 조정. 방 하나가 끝날 때마다 딱 한 번.
## 내려갈 땐 한 방 만에, 올라갈 땐 두 방 연속. 중간은 데드존이라 아무 일도 없다.
func _update_skill() -> void:
	if cushion > 0:
		cushion -= 1
	if hints_this_room >= 2:
		skill = maxi(skill - 1, SKILL_MIN)
		ease_streak = 0
		cushion = 1           # 다음 한 방은 무조건 완충
	elif hints_this_room == 0:
		ease_streak += 1
		if ease_streak >= 2:
			skill = mini(skill + 1, SKILL_MAX)
			ease_streak = 0
	else:
		ease_streak = 0


## ★ 트윈의 finished 를 기다리지 않는다. 트윈이 한 번이라도 finished 를 안 내면
##   (씬 전환 타이밍에 실제로 그런다) 여기서 영영 안 깨어나고, 그 뒤로는 아이가
##   무엇을 눌러도 아무 일이 안 일어난다. 같은 시간짜리 타이머만 기다린다.
func _fade(cb: Callable) -> void:
	busy = true
	var gen := _gen
	hud.fade_to(1.0, 0.30 * _slow)
	await _wait(0.33 * _slow)
	if gen != _gen or not is_inside_tree():
		return
	cb.call()
	hud.fade_to(0.0, 0.35 * _slow)


# ================================================================= 매 프레임

func _process(delta: float) -> void:
	if state != "play" or busy:
		return
	if not beam.on:
		# 아이를 어둠 속에 혼자 두지 않는다 — 잠깐 기다리면 불이 저절로 켜진다.
		wake += delta
		if wake >= WAKE_SEC * _slow:
			idle = 0.0
			_aim(beam.suggest)
		return
	idle += delta
	var wait := float(axes.get("hint_sec", 13.0))
	# 힌트가 뜨는 조건은 둘이고, 어느 쪽도 초시계가 아니다:
	#   (1) 아무것도 안 누르고 hint_sec 이 지났다  — 아이가 멈췄다
	#   (2) 방을 한 바퀴 반 훑도록 아무것도 못 봤다 — 헤매는 중이다
	if idle > wait or dry_taps >= dry_limit():
		idle = wait * 0.45
		dry_taps = 0
		hints_this_room += 1
		_hint()


## 방을 한 번 훑는 데 드는 탭 수 (빛 넓이 대비 화면 넓이. 겹쳐 훑으므로 1.7배).
func sweep_taps() -> float:
	var r := maxf(60.0, beam.radius)
	return W * H / (PI * r * r) * 1.7


## 이만큼 헛되이 비추면 도와준다. 반경이 좁아질수록 함께 늘어난다 —
## 빛이 좁아진 것 때문에 힌트가 빨리 터지면 그건 벌이지 도움이 아니다.
func dry_limit() -> int:
	return maxi(6, int(ceil(sweep_taps() * 1.5)))


## 힌트. 손전등에서 가장 가까운 못 찾은 공룡 자리가 반짝인다 ("아, 여기 있었네!").
##
## ★ 힌트는 **무한히 반복되고, 거듭될수록 더 친절해진다.** 세 번 하고 끝내면
##   못 찾은 아이가 깜깜한 방에 도움 없이 남는데, 그건 이 앱이 금지한 게임오버의
##   정서적 등가물이다. 아이 눈에는 "설명이 다시 친절해진 것"으로만 보여야 한다.
func _hint() -> void:
	var target: Dino = null
	var bd := 1e30
	for d in dinos:
		if d.found:
			continue
		var dd := beam.pos.distance_squared_to(d.hit_rect().get_center())
		if dd < bd:
			bd = dd
			target = d
	if target == null:
		return
	var c := target.hit_rect().get_center()
	beam.twinkle(c)
	target.hint()
	sfx.play("tap", 0.7)
	if hints_this_room == 2:
		beam.add_glow(c, 90.0, 0.030)     # 그 자리에 희미한 잔광이 남는다
	elif hints_this_room == 3:
		beam.radius += 40.0               # 이 방 동안 빛이 조금 넓어진다
	elif hints_this_room >= 4:
		beam.ease_dark(0.06)              # 방이 조금 밝아진다 (내려가기만)


# ============================================ 개발용 (tests/torch_check.gd 가 쓴다)

## 연출을 건너뛰고 바로 놀 수 있는 상태로. 검사기가 방마다 부른다.
func skip_intro() -> void:
	_finish_intro(true)
