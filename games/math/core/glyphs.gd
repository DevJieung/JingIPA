## 연산 기호를 "블록"으로 직접 그린다.
##
## 폰트(Jua)에 ×, − 글리프가 없기도 하고, 굵은 블록 모양으로 그리는 편이
## 게임 컨셉과 훨씬 잘 맞는다. 모든 기호는 주어진 사각형 안에 꽉 차게 그려진다.
class_name Glyphs
extends RefCounted


## 연산 기호 하나. size 는 기호가 차지하는 정사각형 한 변.
static func draw_op(ci: CanvasItem, op: Problem.Op, center: Vector2, size: float,
		color: Color, shade: Color = Color(0, 0, 0, 0)) -> void:
	match op:
		Problem.Op.ADD:
			draw_plus(ci, center, size, color, shade)
		Problem.Op.SUB:
			draw_minus(ci, center, size, color, shade)
		Problem.Op.MUL:
			draw_times(ci, center, size, color, shade)


static func _bar(ci: CanvasItem, center: Vector2, length: float, thick: float,
		angle: float, color: Color, shade: Color) -> void:
	var rect := Rect2(-length * 0.5, -thick * 0.5, length, thick)
	var pts := DrawUtil.round_rect(rect, thick * 0.42, 4)
	var xf := Transform2D(angle, center)
	var world := PackedVector2Array()
	for p in pts:
		world.append(xf * p)
	if shade.a > 0.0:
		var below := PackedVector2Array()
		for p in world:
			below.append(p + Vector2(0, thick * 0.28))
		DrawUtil.fill_aa(ci, below, shade)
	DrawUtil.fill_aa(ci, world, color)


static func draw_plus(ci: CanvasItem, center: Vector2, size: float, color: Color,
		shade: Color = Color(0, 0, 0, 0)) -> void:
	var t := size * 0.30
	var l := size
	_bar(ci, center, l, t, 0.0, color, shade)
	_bar(ci, center, l, t, PI * 0.5, color, shade)


static func draw_minus(ci: CanvasItem, center: Vector2, size: float, color: Color,
		shade: Color = Color(0, 0, 0, 0)) -> void:
	_bar(ci, center, size, size * 0.30, 0.0, color, shade)


static func draw_times(ci: CanvasItem, center: Vector2, size: float, color: Color,
		shade: Color = Color(0, 0, 0, 0)) -> void:
	var t := size * 0.28
	var l := size * 0.94
	_bar(ci, center, l, t, PI * 0.25, color, shade)
	_bar(ci, center, l, t, -PI * 0.25, color, shade)


static func draw_equals(ci: CanvasItem, center: Vector2, size: float, color: Color,
		shade: Color = Color(0, 0, 0, 0)) -> void:
	var t := size * 0.24
	var gap := size * 0.30
	_bar(ci, center - Vector2(0, gap * 0.5), size, t, 0.0, color, shade)
	_bar(ci, center + Vector2(0, gap * 0.5), size, t, 0.0, color, shade)


## 체크 표시 (정답).
static func draw_check(ci: CanvasItem, center: Vector2, size: float, color: Color,
		width: float = 0.0) -> void:
	var w := width if width > 0.0 else size * 0.22
	var pts := PackedVector2Array([
		center + Vector2(-size * 0.40, size * 0.02),
		center + Vector2(-size * 0.10, size * 0.32),
		center + Vector2(size * 0.44, -size * 0.34),
	])
	ci.draw_polyline(pts, color, w, true)
	DrawUtil.circle_aa(ci, pts[0], w * 0.5, color)
	DrawUtil.circle_aa(ci, pts[2], w * 0.5, color)


## X 표시 (오답) — draw_times 와 같지만 선 느낌.
static func draw_cross(ci: CanvasItem, center: Vector2, size: float, color: Color,
		width: float = 0.0) -> void:
	var w := width if width > 0.0 else size * 0.20
	ci.draw_line(center + Vector2(-size * 0.32, -size * 0.32),
			center + Vector2(size * 0.32, size * 0.32), color, w, true)
	ci.draw_line(center + Vector2(size * 0.32, -size * 0.32),
			center + Vector2(-size * 0.32, size * 0.32), color, w, true)


## 별 (스테이지 평가).
static func draw_star(ci: CanvasItem, center: Vector2, radius: float, fill: Color,
		outline: Color = Color(0, 0, 0, 0), outline_w: float = 3.0) -> void:
	var pts := DrawUtil.star(center, radius, radius * 0.47, 5)
	DrawUtil.fill_aa(ci, pts, fill)
	if outline.a > 0.0:
		DrawUtil.draw_outline(ci, pts, outline, outline_w)


## 하트 (남은 기회).
static func draw_heart(ci: CanvasItem, center: Vector2, size: float, fill: Color,
		outline: Color = Color(0, 0, 0, 0), outline_w: float = 3.0) -> void:
	var pts := DrawUtil.heart(center, size)
	DrawUtil.fill_aa(ci, pts, fill)
	if outline.a > 0.0:
		DrawUtil.draw_outline(ci, pts, outline, outline_w)


## 자물쇠 (잠긴 스테이지).
static func draw_lock(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var body := Rect2(center.x - size * 0.34, center.y - size * 0.08,
			size * 0.68, size * 0.52)
	DrawUtil.fill_aa(ci, DrawUtil.round_rect(body, size * 0.12), color)
	var shackle := DrawUtil.ellipse(Vector2(center.x, center.y - size * 0.08),
			Vector2(size * 0.24, size * 0.28), 20, PI, TAU)
	ci.draw_polyline(shackle, color, size * 0.13, true)
	DrawUtil.circle_aa(ci, Vector2(center.x, center.y + size * 0.16), size * 0.07,
			Color(0, 0, 0, 0.35))


## 다시 보기 (원형 화살표). 블록 시연을 아이가 언제든 다시 부를 수 있어야 한다.
static func draw_replay(ci: CanvasItem, center: Vector2, size: float,
		color: Color) -> void:
	var r := size * 0.34
	var w := size * 0.15
	var arc := DrawUtil.ellipse(center, Vector2(r, r), 26, -PI * 0.62, PI * 0.95)
	ci.draw_polyline(arc, color, w, true)
	# 화살촉
	var tip: Vector2 = arc[0]
	var dir := (arc[0] - arc[1]).normalized()
	var side := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([
		tip + dir * size * 0.16,
		tip - dir * size * 0.06 + side * size * 0.15,
		tip - dir * size * 0.06 - side * size * 0.15,
	])
	DrawUtil.fill_aa(ci, head, color)


## 왼쪽 화살표 (뒤로 가기).
static func draw_back_arrow(ci: CanvasItem, center: Vector2, size: float,
		color: Color) -> void:
	var w := size * 0.18
	var pts := PackedVector2Array([
		center + Vector2(size * 0.22, -size * 0.34),
		center + Vector2(-size * 0.20, 0.0),
		center + Vector2(size * 0.22, size * 0.34),
	])
	ci.draw_polyline(pts, color, w, true)
	for p in pts:
		DrawUtil.circle_aa(ci, p, w * 0.5, color)


## 톱니바퀴 (설정).
static func draw_gear(ci: CanvasItem, center: Vector2, radius: float, color: Color,
		teeth: int = 8) -> void:
	var pts := PackedVector2Array()
	var steps := teeth * 4
	for i in range(steps + 1):
		var a := TAU * float(i) / float(steps)
		var phase := fposmod(float(i), 4.0)
		var r := radius if phase < 2.0 else radius * 0.78
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	DrawUtil.fill_aa(ci, pts, color)
	DrawUtil.circle_aa(ci, center, radius * 0.34, Palette.PANEL)


## 스피커 (소리 켬/끔).
static func draw_speaker(ci: CanvasItem, center: Vector2, size: float, color: Color,
		muted: bool) -> void:
	var box := Rect2(center.x - size * 0.42, center.y - size * 0.16,
			size * 0.26, size * 0.32)
	DrawUtil.fill_aa(ci, DrawUtil.round_rect(box, size * 0.06), color)
	var cone := PackedVector2Array([
		Vector2(center.x - size * 0.18, center.y - size * 0.16),
		Vector2(center.x + size * 0.06, center.y - size * 0.40),
		Vector2(center.x + size * 0.06, center.y + size * 0.40),
		Vector2(center.x - size * 0.18, center.y + size * 0.16),
	])
	DrawUtil.fill_aa(ci, cone, color)
	if muted:
		ci.draw_line(center + Vector2(size * 0.16, -size * 0.22),
				center + Vector2(size * 0.44, size * 0.22), color, size * 0.11, true)
		ci.draw_line(center + Vector2(size * 0.44, -size * 0.22),
				center + Vector2(size * 0.16, size * 0.22), color, size * 0.11, true)
	else:
		for i in 2:
			var r := size * (0.20 + 0.13 * float(i))
			var arc := DrawUtil.ellipse(Vector2(center.x + size * 0.06, center.y),
					Vector2(r, r), 16, -PI * 0.38, PI * 0.38)
			ci.draw_polyline(arc, color, size * 0.08, true)
