class_name DinoArt
extends RefCounted

## 귀여운 공룡 그리기.
## 원점(0,0)이 발바닥, 위쪽(-y)으로 키 약 150px, 기본은 오른쪽을 봄.

const H := 150.0
const KIND_COUNT := 5

static var PALETTES := [
	{"body": Color("74cf72"), "belly": Color("e2f6bd"), "trim": Color("3d9a55")},
	{"body": Color("ff9f6b"), "belly": Color("ffe3c8"), "trim": Color("d76a3c")},
	{"body": Color("6fc7f2"), "belly": Color("dbf1ff"), "trim": Color("3a8fc9")},
	{"body": Color("f57fa8"), "belly": Color("ffdfea"), "trim": Color("c65182")},
	{"body": Color("b79cf0"), "belly": Color("e9dcff"), "trim": Color("7d61c6")},
	{"body": Color("ffd166"), "belly": Color("fff2c9"), "trim": Color("d9a327")},
	{"body": Color("5fd6c0"), "belly": Color("d6fbf3"), "trim": Color("2f9e8c")},
]

const INK := Color("2f2b3a")


# ---------------------------------------------------------------- 도형 도우미

static func palette(i: int) -> Dictionary:
	return PALETTES[i % PALETTES.size()]


static func ellipse(c: Vector2, rx: float, ry: float, steps := 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func rrect(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[r.position + Vector2(rad, rad), PI, PI * 1.5],
		[Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5, TAU],
		[r.end - Vector2(rad, rad), 0.0, PI * 0.5],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5, PI],
	]
	for c in corners:
		var center: Vector2 = c[0]
		var a0: float = c[1]
		var a1: float = c[2]
		for i in 5:
			var a: float = lerpf(a0, a1, float(i) / 4.0)
			pts.append(center + Vector2(cos(a), sin(a)) * rad)
	return pts


## 시작점 a에서 끝점 b까지 ctrl로 휘어지는, 두께가 변하는 팔다리/꼬리/목.
static func limb(a: Vector2, b: Vector2, ctrl: Vector2, w0: float, w1: float, steps := 10) -> PackedVector2Array:
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p0 := a.lerp(ctrl, t)
		var p1 := ctrl.lerp(b, t)
		var p := p0.lerp(p1, t)
		var d := (p1 - p0)
		if d.length() < 0.001:
			d = b - a
		d = d.normalized()
		var n := Vector2(-d.y, d.x)
		var w: float = lerpf(w0, w1, t) * 0.5
		top.append(p + n * w)
		bot.append(p - n * w)
	var pts := top
	for i in range(bot.size() - 1, -1, -1):
		pts.append(bot[i])
	return pts


static func blob(ci, pts: PackedVector2Array, fill: Color, line := Color(0, 0, 0, 0), w := 4.0) -> void:
	ci.draw_colored_polygon(pts, fill)
	if line.a > 0.0 and w > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, line, w, true)


static func tri(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b, c])


# ---------------------------------------------------------------- 부위 그리기

static func _eye(ci, p: Vector2, r: float, blink: bool) -> void:
	if blink:
		ci.draw_line(p + Vector2(-r, 0), p + Vector2(r, 0), INK, maxf(2.0, r * 0.45), true)
		return
	blob(ci, ellipse(p, r, r * 1.08, 14), Color.WHITE, INK, r * 0.28)
	blob(ci, ellipse(p + Vector2(r * 0.18, r * 0.12), r * 0.48, r * 0.55, 12), INK)
	blob(ci, ellipse(p + Vector2(-r * 0.14, -r * 0.34), r * 0.2, r * 0.2, 8), Color(1, 1, 1, 0.9))


static func _smile(ci, p: Vector2, r: float, trim: Color) -> void:
	ci.draw_arc(p, r, 0.25, PI - 0.25, 14, trim, maxf(2.0, r * 0.22), true)


static func _leg(ci, pal: Dictionary, x: float, top: float, w: float, dark: bool) -> void:
	var body: Color = pal["body"]
	var trim: Color = pal["trim"]
	var col := body.darkened(0.16) if dark else body
	blob(ci, rrect(Rect2(x - w * 0.5, top, w, absf(top)), w * 0.45), col, trim, 3.0)
	blob(ci, ellipse(Vector2(x + w * 0.18, -w * 0.16), w * 0.62, w * 0.3, 12), col.darkened(0.05), trim, 3.0)


static func _belly(ci, pal: Dictionary, c: Vector2, rx: float, ry: float) -> void:
	blob(ci, ellipse(c, rx, ry, 18), pal["belly"])


# ---------------------------------------------------------------- 공룡 5종

static func _brachio(ci, pal: Dictionary, blink: bool) -> void:
	var body: Color = pal["body"]
	var trim: Color = pal["trim"]
	_leg(ci, pal, -22, -60, 26, true)
	_leg(ci, pal, 22, -58, 26, true)
	blob(ci, limb(Vector2(-10, -74), Vector2(-104, -30), Vector2(-70, -86), 34, 8), body.darkened(0.08), trim, 3.5)
	_leg(ci, pal, -8, -62, 27, false)
	_leg(ci, pal, 30, -60, 27, false)
	blob(ci, ellipse(Vector2(0, -76), 48, 40), body, trim, 4.0)
	_belly(ci, pal, Vector2(2, -62), 34, 24)
	blob(ci, limb(Vector2(20, -96), Vector2(56, -140), Vector2(24, -128), 30, 20), body, trim, 4.0)
	blob(ci, ellipse(Vector2(62, -146), 22, 17), body, trim, 4.0)
	blob(ci, ellipse(Vector2(78, -143), 8, 6, 10), body.darkened(0.1))
	_eye(ci, Vector2(68, -152), 6.5, blink)
	_smile(ci, Vector2(72, -142), 7, trim)
	# 등 무늬
	for i in 3:
		blob(ci, ellipse(Vector2(-24 + i * 20, -96 + i * 3), 8, 5, 10), body.darkened(0.14))


static func _stego(ci, pal: Dictionary, blink: bool) -> void:
	var body: Color = pal["body"]
	var trim: Color = pal["trim"]
	_leg(ci, pal, -26, -50, 26, true)
	_leg(ci, pal, 26, -48, 26, true)
	blob(ci, limb(Vector2(-16, -64), Vector2(-108, -74), Vector2(-70, -50), 32, 9), body.darkened(0.08), trim, 3.5)
	_leg(ci, pal, -12, -52, 27, false)
	_leg(ci, pal, 34, -50, 27, false)
	blob(ci, ellipse(Vector2(0, -70), 54, 38), body, trim, 4.0)
	_belly(ci, pal, Vector2(4, -56), 40, 22)
	# 등판
	var plate := pal["belly"] as Color
	var xs := [-46.0, -24.0, 0.0, 24.0, 44.0]
	var hs := [16.0, 26.0, 32.0, 26.0, 16.0]
	for i in xs.size():
		var x: float = xs[i]
		var h: float = hs[i]
		var y: float = -104.0 + absf(x) * 0.18
		blob(ci, tri(Vector2(x - 13, y + 6), Vector2(x + 13, y + 6), Vector2(x + 2, y - h)), plate, trim, 3.0)
	blob(ci, limb(Vector2(38, -84), Vector2(66, -104), Vector2(56, -84), 30, 26), body, trim, 4.0)
	blob(ci, ellipse(Vector2(70, -106), 22, 18), body, trim, 4.0)
	_eye(ci, Vector2(74, -112), 6.5, blink)
	_smile(ci, Vector2(78, -102), 7, trim)
	# 꼬리 가시
	blob(ci, tri(Vector2(-96, -80), Vector2(-104, -96), Vector2(-88, -86)), plate, trim, 2.5)
	blob(ci, tri(Vector2(-100, -70), Vector2(-114, -78), Vector2(-98, -62)), plate, trim, 2.5)


static func _trike(ci, pal: Dictionary, blink: bool) -> void:
	var body: Color = pal["body"]
	var trim: Color = pal["trim"]
	_leg(ci, pal, -28, -50, 26, true)
	_leg(ci, pal, 20, -48, 26, true)
	blob(ci, limb(Vector2(-20, -66), Vector2(-100, -50), Vector2(-64, -72), 30, 8), body.darkened(0.08), trim, 3.5)
	_leg(ci, pal, -14, -52, 28, false)
	_leg(ci, pal, 26, -50, 28, false)
	blob(ci, ellipse(Vector2(-4, -72), 50, 38), body, trim, 4.0)
	_belly(ci, pal, Vector2(0, -58), 36, 22)
	# 프릴
	blob(ci, ellipse(Vector2(48, -92), 34, 32, 20), pal["belly"], trim, 4.0)
	for i in 5:
		var a: float = lerpf(-2.3, 0.6, float(i) / 4.0)
		var p := Vector2(48, -92) + Vector2(cos(a), sin(a)) * 30.0
		blob(ci, ellipse(p, 7, 7, 10), pal["belly"], trim, 2.5)
	blob(ci, ellipse(Vector2(62, -88), 28, 24), body, trim, 4.0)
	# 뿔
	blob(ci, tri(Vector2(72, -108), Vector2(84, -104), Vector2(88, -128)), Color("fff4de"), trim, 2.5)
	blob(ci, tri(Vector2(84, -84), Vector2(90, -94), Vector2(104, -88)), Color("fff4de"), trim, 2.5)
	blob(ci, ellipse(Vector2(84, -78), 12, 9, 12), pal["belly"], trim, 3.0)
	_eye(ci, Vector2(68, -96), 6.5, blink)


static func _rex(ci, pal: Dictionary, blink: bool) -> void:
	var body: Color = pal["body"]
	var trim: Color = pal["trim"]
	blob(ci, limb(Vector2(-14, -74), Vector2(-110, -46), Vector2(-72, -92), 34, 8), body.darkened(0.1), trim, 3.5)
	_leg(ci, pal, -20, -66, 34, true)
	_leg(ci, pal, 18, -64, 34, false)
	blob(ci, ellipse(Vector2(0, -84), 44, 42), body, trim, 4.0)
	_belly(ci, pal, Vector2(6, -70), 30, 26)
	# 짧은 팔
	blob(ci, limb(Vector2(26, -98), Vector2(46, -84), Vector2(40, -100), 12, 8), body.darkened(0.05), trim, 3.0)
	# 머리
	blob(ci, limb(Vector2(10, -112), Vector2(36, -132), Vector2(20, -128), 30, 28), body, trim, 4.0)
	blob(ci, ellipse(Vector2(44, -136), 34, 26), body, trim, 4.0)
	# 아래턱
	blob(ci, rrect(Rect2(24, -124, 54, 20), 9), body.darkened(0.06), trim, 3.5)
	blob(ci, rrect(Rect2(30, -122, 42, 12), 5), Color("ffe6ea"))
	for i in 4:
		blob(ci, tri(Vector2(34 + i * 12, -124), Vector2(42 + i * 12, -124), Vector2(38 + i * 12, -114)), Color.WHITE)
	_eye(ci, Vector2(50, -146), 7.0, blink)
	blob(ci, ellipse(Vector2(74, -142), 4, 3, 8), trim)
	# 등 돌기
	for i in 4:
		blob(ci, tri(Vector2(-30 + i * 12, -118 + i * 2), Vector2(-18 + i * 12, -118 + i * 2), Vector2(-24 + i * 12, -132 + i * 2)), pal["belly"], trim, 2.0)


static func _ptera(ci, pal: Dictionary, blink: bool) -> void:
	var body: Color = pal["body"]
	var trim: Color = pal["trim"]
	# 뒷날개
	blob(ci, PackedVector2Array([
		Vector2(-6, -104), Vector2(-96, -136), Vector2(-84, -96), Vector2(-30, -74),
	]), body.darkened(0.16), trim, 3.5)
	_leg(ci, pal, -14, -54, 20, true)
	_leg(ci, pal, 16, -52, 20, false)
	blob(ci, ellipse(Vector2(0, -78), 34, 32), body, trim, 4.0)
	_belly(ci, pal, Vector2(4, -70), 22, 20)
	# 앞날개
	blob(ci, PackedVector2Array([
		Vector2(2, -102), Vector2(84, -142), Vector2(96, -104), Vector2(34, -74),
	]), pal["belly"], trim, 3.5)
	blob(ci, limb(Vector2(6, -100), Vector2(26, -128), Vector2(8, -120), 22, 18), body, trim, 4.0)
	blob(ci, ellipse(Vector2(34, -134), 22, 17), body, trim, 4.0)
	# 부리
	blob(ci, tri(Vector2(48, -142), Vector2(48, -126), Vector2(86, -132)), Color("ffcf6b"), trim, 3.0)
	# 볏
	blob(ci, tri(Vector2(22, -148), Vector2(38, -148), Vector2(6, -170)), pal["belly"], trim, 3.0)
	_eye(ci, Vector2(40, -140), 6.0, blink)


# ---------------------------------------------------------------- 진입점

static func draw_dino(ci, kind: int, pal: Dictionary, sc := 1.0, face := 1.0, blink := false, at := Vector2.ZERO) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(sc * face, sc))
	match kind % KIND_COUNT:
		0: _brachio(ci, pal, blink)
		1: _stego(ci, pal, blink)
		2: _trike(ci, pal, blink)
		3: _rex(ci, pal, blink)
		_: _ptera(ci, pal, blink)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 발밑 그림자
static func draw_shadow(ci, sc := 1.0, alpha := 0.16, at := Vector2.ZERO) -> void:
	blob(ci, ellipse(at + Vector2(0, -4 * sc), 54 * sc, 13 * sc, 18), Color(0, 0, 0, alpha))


## 아직 못 찾은 공룡 표시용 회색 팔레트
static func grey_palette() -> Dictionary:
	return {"body": Color("cfc7d6"), "belly": Color("e6e1ec"), "trim": Color("b1a8bd")}
