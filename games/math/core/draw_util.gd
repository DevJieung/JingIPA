## 코드로 그리는 벡터 아트용 공용 드로잉/보간 헬퍼.
##
## 이미지 에셋을 전혀 쓰지 않으므로 둥근 사각형, 캡슐, 별, 하트 같은
## 기본 도형을 여기서 폴리곤으로 만들어 쓴다.
##
## ★안티에일리어싱 규칙★
## 이 프로젝트는 기기 호환성을 위해 gl_compatibility 렌더러를 쓰고, 이 렌더러에서는
## MSAA 가 동작하지 않는다. 게다가 draw_polygon()/draw_colored_polygon() 에는
## antialiased 인자가 없다. 그래서 채워진 도형은 반드시 fill_aa() 로 그린다 —
## 폴리곤을 채운 뒤 같은 색의 안티에일리어싱된 외곽선을 덧그려 가장자리를 부드럽게 만든다.
## 직접 draw_colored_polygon() 을 부르면 계단 현상이 그대로 보인다.
class_name DrawUtil
extends RefCounted

## 가장자리를 부드럽게 만드는 덧칠 선의 두께 (디자인 픽셀).
const AA_WIDTH := 1.6


# --------------------------------------------------------------------------- #
# 안티에일리어싱 채우기
# --------------------------------------------------------------------------- #

## 채워진 폴리곤 + 같은 색 AA 외곽선. 채워진 도형은 전부 이걸로 그린다.
static func fill_aa(ci: CanvasItem, pts: PackedVector2Array, color: Color,
		aa_width: float = AA_WIDTH) -> void:
	var n := pts.size()
	if n < 3:
		return
	ci.draw_colored_polygon(pts, color)
	if aa_width <= 0.0 or color.a <= 0.003:
		return
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, color, aa_width, true)


## 채우기 + 다른 색 테두리를 한 번에.
static func fill_stroke(ci: CanvasItem, pts: PackedVector2Array, fill: Color,
		stroke: Color, width: float = 3.0) -> void:
	fill_aa(ci, pts, fill)
	if stroke.a > 0.003 and width > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		ci.draw_polyline(loop, stroke, width, true)


## 안티에일리어싱된 원. draw_circle 은 4.3+ 에서 antialiased 인자를 받는다.
static func circle_aa(ci: CanvasItem, center: Vector2, radius: float,
		color: Color) -> void:
	ci.draw_circle(center, radius, color, true, -1.0, true)


## 안티에일리어싱된 타원 (원을 눌러 만든 것).
static func ellipse_aa(ci: CanvasItem, center: Vector2, radius: Vector2,
		color: Color, seg: int = 30) -> void:
	fill_aa(ci, ellipse(center, radius, seg), color)


# --------------------------------------------------------------------------- #
# 도형 폴리곤 생성
# --------------------------------------------------------------------------- #

## 모서리가 둥근 사각형의 외곽선 점들.
static func round_rect(rect: Rect2, radius: float, seg: int = 5) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	if r <= 0.01:
		pts.append(rect.position)
		pts.append(rect.position + Vector2(rect.size.x, 0))
		pts.append(rect.position + rect.size)
		pts.append(rect.position + Vector2(0, rect.size.y))
		return pts
	var corners := [
		Vector2(rect.position.x + rect.size.x - r, rect.position.y + r),           # 우상
		Vector2(rect.position.x + rect.size.x - r, rect.position.y + rect.size.y - r),  # 우하
		Vector2(rect.position.x + r, rect.position.y + rect.size.y - r),           # 좌하
		Vector2(rect.position.x + r, rect.position.y + r),                         # 좌상
	]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for i in 4:
		var c: Vector2 = corners[i]
		var a0: float = start_angles[i]
		for s in range(seg + 1):
			var a := a0 + (PI * 0.5) * (float(s) / float(seg))
			pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## 양 끝이 반원인 캡슐 (가로 방향).
static func capsule_h(rect: Rect2, seg: int = 8) -> PackedVector2Array:
	return round_rect(rect, rect.size.y * 0.5, seg)


## 타원 폴리곤.
static func ellipse(center: Vector2, radius: Vector2, seg: int = 28,
		from_angle: float = 0.0, to_angle: float = TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		var a: float = lerpf(from_angle, to_angle, float(i) / float(seg))
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return pts


## 별 (뾰족한 꼭짓점 n개).
static func star(center: Vector2, outer: float, inner: float, points: int = 5,
		rotation: float = -PI * 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(points * 2):
		var r := outer if i % 2 == 0 else inner
		var a := rotation + TAU * float(i) / float(points * 2)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## 하트.
static func heart(center: Vector2, size: float, seg: int = 30) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		var t := TAU * float(i) / float(seg)
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(center + Vector2(x, y) * (size / 32.0))
	return pts


## 부드러운 물방울/구름 모양 — 여러 원을 감싸는 껍데기.
static func blob(center: Vector2, radius: Vector2, wobble: float, phase: float,
		seg: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		var a := TAU * float(i) / float(seg)
		var w := 1.0 + sin(a * 3.0 + phase) * wobble
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y) * w)
	return pts


## 두 점을 잇는 두꺼운 곡선(catmull 유사)을 폴리라인 점으로 변환.
static func smooth_path(points: PackedVector2Array, samples_per_seg: int = 8) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array()
	var n := points.size()
	for i in range(n - 1):
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, n - 1)]
		for s in range(samples_per_seg):
			var t := float(s) / float(samples_per_seg)
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(points[n - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# --------------------------------------------------------------------------- #
# 합성 드로잉 (그림자 + 본체 + 하이라이트)
# --------------------------------------------------------------------------- #

## 입체감 있는 둥근 사각형 블록 하나. 아래쪽에 두께, 위쪽에 하이라이트.
static func draw_block(ci: CanvasItem, rect: Rect2, radius: float, face: Color,
		side: Color, top_light: Color, depth: float = 6.0) -> void:
	if depth > 0.0:
		var under := Rect2(rect.position + Vector2(0, depth), rect.size)
		fill_aa(ci, round_rect(under, radius), side)
	fill_aa(ci, round_rect(rect, radius), face)
	# 위쪽 하이라이트 바
	var hl := Rect2(rect.position + Vector2(rect.size.x * 0.16, rect.size.y * 0.13),
			Vector2(rect.size.x * 0.68, rect.size.y * 0.20))
	fill_aa(ci, round_rect(hl, hl.size.y * 0.5), top_light)


## 부드러운 드롭 섀도 (동심 폴리곤 몇 겹).
static func draw_soft_shadow(ci: CanvasItem, rect: Rect2, radius: float,
		color: Color, layers: int = 4, spread: float = 5.0) -> void:
	for i in range(layers, 0, -1):
		var g := float(i) / float(layers)
		var grow := spread * g
		var r := Rect2(rect.position - Vector2(grow, grow),
				rect.size + Vector2(grow, grow) * 2.0)
		var c := Color(color.r, color.g, color.b, color.a / float(layers) * 0.85)
		ci.draw_colored_polygon(round_rect(r, radius + grow), c)


## 카드/패널: 그림자 + 본체 + 테두리.
static func draw_card(ci: CanvasItem, rect: Rect2, radius: float, fill: Color,
		edge: Color, shadow: Color, shadow_offset: float = 6.0) -> void:
	var sh := Rect2(rect.position + Vector2(0, shadow_offset), rect.size)
	fill_aa(ci, round_rect(sh, radius), shadow)
	fill_stroke(ci, round_rect(rect, radius), fill, edge, 2.0)


## 폴리곤 외곽선 (닫힌 루프).
static func draw_outline(ci: CanvasItem, pts: PackedVector2Array, color: Color,
		width: float = 2.0) -> void:
	if pts.size() < 2:
		return
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, color, width, true)


# --------------------------------------------------------------------------- #
# 이징 (Tween 밖에서 직접 보간할 때)
# --------------------------------------------------------------------------- #

static func ease_out_back(t: float, overshoot: float = 1.70158) -> float:
	var c3 := overshoot + 1.0
	var u := t - 1.0
	return 1.0 + c3 * u * u * u + overshoot * u * u


static func ease_out_elastic(t: float) -> float:
	if is_zero_approx(t) or is_equal_approx(t, 1.0):
		return t
	var p := 0.35
	return pow(2.0, -10.0 * t) * sin((t - p / 4.0) * TAU / p) + 1.0


static func ease_out_cubic(t: float) -> float:
	var u := 1.0 - t
	return 1.0 - u * u * u


static func ease_in_out_cubic(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	var u := -2.0 * t + 2.0
	return 1.0 - u * u * u * 0.5


static func ease_out_bounce(t: float) -> float:
	var n := 7.5625
	var d := 2.75
	if t < 1.0 / d:
		return n * t * t
	elif t < 2.0 / d:
		t -= 1.5 / d
		return n * t * t + 0.75
	elif t < 2.5 / d:
		t -= 2.25 / d
		return n * t * t + 0.9375
	t -= 2.625 / d
	return n * t * t + 0.984375


## 0..1 구간에서 살짝 부풀었다 돌아오는 펄스.
static func pulse(t: float, amount: float = 0.25) -> float:
	return 1.0 + sin(clampf(t, 0.0, 1.0) * PI) * amount
