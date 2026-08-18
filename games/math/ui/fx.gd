## 화면 연출(이펙트) 모음 — 스스로 정리되는 작은 효과들.
##
## 어느 화면에서든 `Fx.confetti(self, pos)` 처럼 한 줄로 부를 수 있는 정적 라이브러리다.
## 각 효과는 부모 아래에 **가벼운 노드 하나만** 만들고, 연출이 끝나면 스스로
## queue_free() 한다. 색종이나 별처럼 조각이 여러 개인 효과도 노드를 여러 개 만들지 않고
## 한 노드의 _draw() 안에서 배열을 통째로 그린다 (노드 24개 대신 1개).
##
## 규칙:
## * 이미지 에셋을 쓰지 않는다. 전부 _draw() 안의 CanvasItem 드로잉 호출이다.
## * 채워진 도형은 DrawUtil.fill_aa / circle_aa 로만 그린다 (gl_compatibility 계단 현상 방지).
## * 모든 지속 시간에 MathGame.anim_scale() 을 곱한다.
## * 부모가 도중에 사라져도 Tween 이 노드에 묶여 있어 함께 정리되므로 누수가 없다.
## * 시간 압박을 주는 연출(카운트다운 등)은 없다. 전부 "칭찬"이나 "여기를 봐" 용도다.
class_name Fx
extends RefCounted

# --------------------------------------------------------------------------- #
# 상수
# --------------------------------------------------------------------------- #

## 효과가 형제 노드들 위에 보이도록 하는 z 값 (부모 기준 상대값).
const FX_Z := 90

## 전체 화면 플래시는 같은 캔버스 안에서 확실히 맨 위에 오도록 절대 z 를 쓴다.
const FLASH_Z := 4000

## 떠오르는 글자가 올라가는 높이(디자인 픽셀).
const FLOAT_RISE := 70.0

## 흔들기에서 원래 위치와 진행 중인 Tween 을 기억해 두는 메타 키.
const SHAKE_HOME_META := "_fx_shake_home"
const SHAKE_TWEEN_META := "_fx_shake_tween"

## 색종이 조각 색 — 게임 팔레트에서 골라 쓴다.
const CONFETTI_COLORS: Array[Color] = [
	Palette.BLOCK_A,
	Palette.BLOCK_B,
	Palette.HELMET,
	Palette.FROG_BODY,
	Palette.HEART,
	Palette.STAR,
	Palette.SNAKE_BELLY,
	Palette.CORRECT_LIGHT,
]

## 별 조각 색 — 금빛 계열만.
const STAR_COLORS: Array[Color] = [
	Palette.STAR,
	Palette.HELMET,
	Palette.ROD_GLOW,
]

## 흔들기 방향 순서. 규칙적인 좌우 흔들림이라 아이에게 거칠게 보이지 않는다.
const SHAKE_DIRS: Array[Vector2] = [
	Vector2(1.0, -0.30),
	Vector2(-0.82, 0.26),
	Vector2(0.62, 0.20),
	Vector2(-0.44, -0.16),
	Vector2(0.24, 0.10),
]

## 조각 하나의 기준 모양(가로세로 1인 둥근 사각형). 매 프레임 새로 만들지 않으려고 캐시한다.
static var _chip_unit := PackedVector2Array()


# --------------------------------------------------------------------------- #
# 공개 API
# --------------------------------------------------------------------------- #

## 숫자나 짧은 낱말이 톡 튀어나온 뒤 위로 떠오르며 사라진다.
## "+1", "정답!", 세는 중인 블록 개수 같은 곳에 쓴다.
## pos 는 parent 기준 좌표.
static func float_text(parent: Node, text: String, pos: Vector2, color: Color,
		font_size: int = 44) -> void:
	if text.is_empty() or not _usable(parent):
		return
	var s := MathGame.anim_scale()
	var node := FloatText.new()
	node.text = text
	node.font_size = maxi(8, font_size)
	node.tint = color
	# 밝은 글자에는 어두운 테두리, 진한 글자에는 흰 테두리를 둘러 배경 위에서도 읽히게 한다.
	node.outline = Palette.INK if color.get_luminance() > 0.70 else Palette.CARD
	node.position = pos
	node.z_index = FX_Z
	node.scale = Vector2(0.4, 0.4)
	parent.add_child(node)

	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector2.ONE, 0.34 * s) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", pos + Vector2(0, -FLOAT_RISE), 0.90 * s) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 0.0, 0.42 * s) \
			.set_delay(0.48 * s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(node.queue_free)


## 팔레트 색의 작은 둥근 조각들이 사방으로 터져 나가며 중력에 떨어지고, 돌면서 사라진다.
## 조각 전부를 노드 하나가 그린다.
## tint 를 주면 모든 조각 색에 곱해진다(월드 색에 맞출 때).
static func confetti(parent: Node, pos: Vector2, amount: int = 24,
		tint: Color = Color(1, 1, 1, 1)) -> void:
	if not _usable(parent):
		return
	var n := clampi(amount, 1, 64)
	var node := Burst.new()
	node.shape = Burst.Shape.CHIP
	node.gravity = 1150.0
	node.drag = 1.35
	node.position = pos
	node.z_index = FX_Z
	node.time_scale = _time_scale()

	for i in n:
		# 위쪽으로 살짝 치우친 부채꼴로 뿌려야 "축하 폭죽"처럼 보인다.
		var ang := randf_range(-PI * 0.96, -PI * 0.04) + randf_range(-0.35, 0.35)
		var speed := randf_range(240.0, 620.0)
		var vel := Vector2(cos(ang), sin(ang)) * speed
		vel.x *= 1.15
		var w := randf_range(11.0, 19.0)
		var h := w * randf_range(0.45, 0.85)
		var base: Color = CONFETTI_COLORS[randi() % CONFETTI_COLORS.size()]
		node.add_piece(Vector2.ZERO, vel, randf_range(0.0, TAU),
				randf_range(-9.0, 9.0), Vector2(w, h),
				randf_range(0.85, 1.35), base * tint)
	parent.add_child(node)


## 금빛 별 조각들이 퍼져 나가며 천천히 작아지고 사라진다. 별을 얻었을 때 쓴다.
static func star_burst(parent: Node, pos: Vector2, amount: int = 10) -> void:
	if not _usable(parent):
		return
	var n := clampi(amount, 1, 32)
	var node := Burst.new()
	node.shape = Burst.Shape.STAR
	node.gravity = 340.0
	node.drag = 1.9
	node.position = pos
	node.z_index = FX_Z
	node.time_scale = _time_scale()

	var step := TAU / float(n)
	for i in n:
		# 고르게 퍼지도록 각도를 나눠 주고 약간만 흔든다.
		var ang := step * float(i) + randf_range(-step * 0.35, step * 0.35)
		var speed := randf_range(200.0, 420.0)
		var r := randf_range(11.0, 20.0)
		var base: Color = STAR_COLORS[randi() % STAR_COLORS.size()]
		node.add_piece(Vector2.ZERO, Vector2(cos(ang), sin(ang)) * speed,
				randf_range(0.0, TAU), randf_range(-4.5, 4.5), Vector2(r, r),
				randf_range(0.70, 1.10), base)
	parent.add_child(node)


## 한 점에서 퍼져 나가며 옅어지는 고리. "여기를 봐" 신호로 쓴다.
static func ring_pulse(parent: Node, pos: Vector2, color: Color,
		max_radius: float = 120.0) -> void:
	if not _usable(parent):
		return
	var s := MathGame.anim_scale()
	var node := Ring.new()
	node.tint = color
	node.max_radius = maxf(8.0, max_radius)
	node.position = pos
	node.z_index = FX_Z
	parent.add_child(node)

	var tw := node.create_tween()
	tw.tween_property(node, "progress", 1.0, 0.55 * s) \
			.from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(node.queue_free)


## 노드를 잠깐 흔든다. 끝나면 **항상** 원래 위치로 정확히 되돌아온다.
## 흔들리는 도중에 다시 불려도 처음 위치를 기억하고 있어 위치가 밀리지 않는다.
## 아이용 게임이라 세기는 일부러 약하게 잡는다.
static func shake(node: Node2D, strength: float = 12.0, duration: float = 0.35) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return

	# 이미 흔들리는 중이면 그때 기억해 둔 "원래 위치"를 그대로 쓴다.
	var home: Vector2 = node.position
	if node.has_meta(SHAKE_HOME_META):
		home = node.get_meta(SHAKE_HOME_META)
	else:
		node.set_meta(SHAKE_HOME_META, home)

	if node.has_meta(SHAKE_TWEEN_META):
		var prev: Variant = node.get_meta(SHAKE_TWEEN_META)
		if prev is Tween and (prev as Tween).is_valid():
			(prev as Tween).kill()
	node.position = home

	var amp := maxf(0.0, strength)
	var total := maxf(0.10, duration) * MathGame.anim_scale()
	var steps := SHAKE_DIRS.size()
	var seg := total / float(steps + 1)

	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in steps:
		var damp := 1.0 - float(i) / float(steps)
		tw.tween_property(node, "position", home + SHAKE_DIRS[i] * amp * damp, seg)
	# 마지막 구간에서 반드시 원래 위치로 되돌린다.
	tw.tween_property(node, "position", home, seg)
	tw.tween_callback(func() -> void: _clear_shake_meta(node))
	node.set_meta(SHAKE_TWEEN_META, tw)


## 화면 전체를 덮었다가 옅어지는 색 막. 입력을 막지 않고 형제 노드들 위에 그려진다.
static func flash_screen(parent: CanvasItem, color: Color, duration: float = 0.25) -> void:
	if not _usable(parent):
		return
	var s := MathGame.anim_scale()
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.focus_mode = Control.FOCUS_NONE
	# 부모의 변형/크기와 무관하게 화면 전체를 덮는다.
	rect.top_level = true
	rect.z_as_relative = false
	rect.z_index = FLASH_Z
	rect.modulate.a = 0.0

	var vr := parent.get_viewport_rect()
	rect.position = vr.position - Vector2(8, 8)
	rect.size = vr.size + Vector2(16, 16)
	parent.add_child(rect)

	var total := maxf(0.06, duration) * s
	var tw := rect.create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	# 갑자기 번쩍이면 아이에게 거칠게 느껴지므로 아주 짧게 차올랐다가 길게 빠진다.
	tw.tween_property(rect, "modulate:a", 1.0, total * 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(rect, "modulate:a", 0.0, total * 0.82).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(rect.queue_free)


# --------------------------------------------------------------------------- #
# 내부 헬퍼
# --------------------------------------------------------------------------- #

## 효과를 붙일 수 있는 부모인지 확인 (create_tween 은 트리 안에서만 된다).
static func _usable(parent: Node) -> bool:
	return is_instance_valid(parent) and parent.is_inside_tree()


## 애니메이션을 짧게 설정했으면 파티클 시간도 같은 비율로 빨리 흐르게 한다.
static func _time_scale() -> float:
	return 1.0 / maxf(0.2, MathGame.anim_scale())


static func _clear_shake_meta(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	node.remove_meta(SHAKE_HOME_META)
	node.remove_meta(SHAKE_TWEEN_META)


## 가로세로 1짜리 둥근 사각형 점들(조각 하나의 기준 모양). 한 번만 만들어 재사용한다.
static func _chip_shape() -> PackedVector2Array:
	if _chip_unit.is_empty():
		_chip_unit = DrawUtil.round_rect(Rect2(-0.5, -0.5, 1.0, 1.0), 0.30, 2)
	return _chip_unit


# --------------------------------------------------------------------------- #
# 내부 노드들
# --------------------------------------------------------------------------- #

## 떠오르는 글자 한 덩어리. 크기/위치/투명도는 Node2D 내장 속성을 Tween 이 움직인다.
class FloatText extends Node2D:

	var text := ""
	var font_size := 44
	var tint: Color = Palette.INK
	var outline: Color = Palette.CARD

	func _draw() -> void:
		var ow := maxi(4, int(round(float(font_size) * 0.16)))
		Fonts.draw_centered_outlined(self, text, Vector2.ZERO, font_size, tint,
				outline, ow)


## 조각 여러 개(색종이 / 별)를 노드 하나에서 전부 그리는 파티클.
##
## 상태는 병렬 배열에 담고 _process 에서 한꺼번에 적분한 뒤 queue_redraw() 한다.
## 조각마다 노드를 만드는 것보다 훨씬 싸고, 다 꺼지면 스스로 사라진다.
class Burst extends Node2D:

	enum Shape { CHIP, STAR }

	## 조각 모양.
	var shape: Shape = Shape.CHIP
	## 아래로 당기는 힘 (픽셀/초²).
	var gravity := 1150.0
	## 공기 저항 계수 — 클수록 빨리 느려진다.
	var drag := 1.35
	## 시간 배속 (빠른 애니메이션 설정용).
	var time_scale := 1.0
	## 사라지기 시작하는 남은 시간.
	var fade_time := 0.35

	var _pos := PackedVector2Array()
	var _vel := PackedVector2Array()
	var _size := PackedVector2Array()
	var _ang := PackedFloat32Array()
	var _spin := PackedFloat32Array()
	var _life := PackedFloat32Array()
	var _col := PackedColorArray()
	var _alive := 0

	## 조각 하나를 추가한다 (부모 노드 기준 지역 좌표).
	func add_piece(p: Vector2, v: Vector2, angle: float, spin: float,
			size: Vector2, life: float, color: Color) -> void:
		_pos.append(p)
		_vel.append(v)
		_size.append(size)
		_ang.append(angle)
		_spin.append(spin)
		_life.append(maxf(0.05, life))
		_col.append(color)
		_alive += 1

	func _process(delta: float) -> void:
		var t := minf(delta, 0.05) * time_scale   # 프레임이 튀어도 조각이 날아가지 않게 제한
		var alive := 0
		for i in _life.size():
			if _life[i] <= 0.0:
				continue
			_life[i] -= t
			if _life[i] <= 0.0:
				_life[i] = 0.0
				continue
			var v := _vel[i]
			v.y += gravity * t
			v *= maxf(0.0, 1.0 - drag * t)
			_vel[i] = v
			_pos[i] += v * t
			_ang[i] += _spin[i] * t
			alive += 1
		_alive = alive
		queue_redraw()
		if alive == 0:
			set_process(false)
			queue_free()

	func _draw() -> void:
		if _alive <= 0:
			return
		var unit := Fx._chip_shape()
		for i in _life.size():
			var life := _life[i]
			if life <= 0.0:
				continue
			var fade := clampf(life / fade_time, 0.0, 1.0)
			var c := _col[i]
			var col := Color(c.r, c.g, c.b, c.a * fade)
			if col.a <= 0.004:
				continue
			if shape == Shape.STAR:
				# 별은 사라지면서 작아지기까지 해야 "반짝 하고 꺼지는" 느낌이 난다.
				var r: float = _size[i].x * (0.35 + 0.65 * fade)
				var pts := DrawUtil.star(_pos[i], r, r * 0.47, 5, _ang[i])
				DrawUtil.fill_aa(self, pts, col)
				DrawUtil.draw_outline(self, pts,
						Color(1, 1, 1, 0.55 * fade), maxf(1.0, r * 0.10))
			else:
				DrawUtil.fill_aa(self, _chip_points(unit, i), col)

	## 기준 모양을 조각 크기/각도/위치에 맞춰 옮긴 점들.
	func _chip_points(unit: PackedVector2Array, i: int) -> PackedVector2Array:
		var out := PackedVector2Array()
		out.resize(unit.size())
		var ca := cos(_ang[i])
		var sa := sin(_ang[i])
		var w: float = _size[i].x
		var h: float = _size[i].y
		var origin: Vector2 = _pos[i]
		for k in unit.size():
			var u := unit[k]
			var x := u.x * w
			var y := u.y * h
			out[k] = origin + Vector2(x * ca - y * sa, x * sa + y * ca)
		return out


## 퍼져 나가며 옅어지는 고리. progress(0~1) 하나만 Tween 이 움직이고
## 반지름/두께/투명도는 _draw() 에서 계산한다 (_draw 를 상태의 순수 함수로 유지).
class Ring extends Node2D:

	var tint: Color = Palette.CARD
	var max_radius := 120.0

	var progress := 0.0:
		set(v):
			progress = v
			queue_redraw()

	func _draw() -> void:
		var t := clampf(progress, 0.0, 1.0)
		var e := DrawUtil.ease_out_cubic(t)
		var a := tint.a * (1.0 - t) * (1.0 - t)
		if a <= 0.004:
			return
		var r := maxf(1.0, max_radius * (0.12 + 0.88 * e))
		var w := lerpf(16.0, 3.0, e)
		# 안쪽의 옅은 빛 → 고리 순서로 그려야 고리가 또렷하게 보인다.
		DrawUtil.circle_aa(self, Vector2.ZERO, r * 0.94,
				Color(tint.r, tint.g, tint.b, a * 0.16))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48,
				Color(tint.r, tint.g, tint.b, a), w, true)
