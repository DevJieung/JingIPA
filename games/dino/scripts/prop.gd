class_name Prop
extends Node2D

## 방 안의 가구/소품. 원점(0,0)이 바닥에 닿는 지점(아래 가운데).

var kind := "sofa"
var w := 200.0
var h := 150.0
var col := Color("d98b6a")
var col2 := Color("f6e2c8")

var _ci: Object = null
var _t := 0.0
var _jiggle := 0.0

const INK := Color("463a45")


func setup(p_kind: String, p_w: float, p_h: float, p_col: Color, p_col2: Color) -> void:
	kind = p_kind
	w = p_w
	h = p_h
	col = p_col
	col2 = p_col2


func jiggle() -> void:
	_jiggle = 1.0


func _process(delta: float) -> void:
	if _jiggle > 0.0:
		_jiggle = maxf(0.0, _jiggle - delta * 2.2)
		_t += delta
		rotation = sin(_t * 26.0) * 0.045 * _jiggle
		scale = Vector2.ONE * (1.0 + 0.03 * _jiggle * sin(_t * 20.0))
		if _jiggle == 0.0:
			rotation = 0.0
			scale = Vector2.ONE


func rect() -> Rect2:
	return Rect2(position + Vector2(-w * 0.5, -h), Vector2(w, h))


# ---------------------------------------------------------------- 도우미

func _box(r: Rect2, c: Color, rad := 10.0, line := true) -> void:
	DinoArt.blob(_ci, DinoArt.rrect(r, rad), c, INK if line else Color(0, 0, 0, 0), 3.0)


func _oval(c: Vector2, rx: float, ry: float, cc: Color, line := true) -> void:
	DinoArt.blob(_ci, DinoArt.ellipse(c, rx, ry), cc, INK if line else Color(0, 0, 0, 0), 3.0)


func _shadow() -> void:
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -3), w * 0.52, 12), Color(0, 0, 0, 0.12))


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	_paint(self)


func _paint(ci: Object) -> void:
	_ci = ci
	match kind:
		"sofa": _sofa()
		"tv": _tv()
		"lamp": _lamp()
		"plant": _plant()
		"table": _table()
		"fridge": _fridge()
		"counter": _counter()
		"bin": _bin()
		"bed": _bed()
		"wardrobe": _wardrobe()
		"nightstand": _nightstand()
		"bathtub": _bathtub()
		"sink": _sink()
		"toilet": _toilet()
		"basket": _basket()
		"toybox": _toybox()
		"blocks": _blocks()
		"horse": _horse()
		"balls": _balls()
		"boxes": _boxes()
		"trunk": _trunk()
		"chair": _chair()
		"window": _window()
		"picture": _picture()
		"rug": _rug()
		"curtain": _curtain()
		"cobweb": _cobweb()
		"shelf": _shelf()
		_: _box(Rect2(-w * 0.5, -h, w, h), col, 12.0)


func _sofa() -> void:
	_shadow()
	var back := Rect2(-w * 0.5, -h, w, h * 0.66)
	_box(back, col.darkened(0.08), h * 0.2)
	_box(Rect2(-w * 0.5, -h * 0.55, w * 0.16, h * 0.55), col.darkened(0.16), 12.0)
	_box(Rect2(w * 0.5 - w * 0.16, -h * 0.55, w * 0.16, h * 0.55), col.darkened(0.16), 12.0)
	_box(Rect2(-w * 0.5 + w * 0.14, -h * 0.5, w * 0.72, h * 0.34), col.lightened(0.08), 12.0)
	for i in 2:
		var cx := -w * 0.18 + i * w * 0.36
		_box(Rect2(cx - w * 0.11, -h * 0.86, w * 0.22, h * 0.26), col2, 10.0)
	_box(Rect2(-w * 0.42, -h * 0.18, w * 0.08, h * 0.18), INK.lightened(0.2), 4.0, false)
	_box(Rect2(w * 0.34, -h * 0.18, w * 0.08, h * 0.18), INK.lightened(0.2), 4.0, false)


func _tv() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h * 0.34, w, h * 0.34), col.darkened(0.1), 10.0)
	_box(Rect2(-w * 0.06, -h * 0.46, w * 0.12, h * 0.14), INK.lightened(0.3), 4.0, false)
	_box(Rect2(-w * 0.44, -h, w * 0.88, h * 0.56), INK.lightened(0.15), 10.0)
	_box(Rect2(-w * 0.38, -h * 0.95, w * 0.76, h * 0.46), col2, 6.0, false)
	DinoArt.blob(_ci, DinoArt.tri(Vector2(-w * 0.38, -h * 0.95), Vector2(-w * 0.05, -h * 0.95), Vector2(-w * 0.38, -h * 0.62)), Color(1, 1, 1, 0.45))


func _lamp() -> void:
	_shadow()
	_oval(Vector2(0, -8), w * 0.4, 10, col.darkened(0.15))
	_ci.draw_line(Vector2(0, -10), Vector2(0, -h * 0.62), INK.lightened(0.25), 7.0, true)
	DinoArt.blob(_ci, PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.6), Vector2(w * 0.5, -h * 0.6),
		Vector2(w * 0.32, -h), Vector2(-w * 0.32, -h),
	]), col2, INK, 3.0)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -h * 0.58), w * 0.5, 10, 18), col2.darkened(0.12))


func _plant() -> void:
	_shadow()
	DinoArt.blob(_ci, PackedVector2Array([
		Vector2(-w * 0.3, -h * 0.34), Vector2(w * 0.3, -h * 0.34),
		Vector2(w * 0.22, 0), Vector2(-w * 0.22, 0),
	]), col2, INK, 3.0)
	_box(Rect2(-w * 0.33, -h * 0.4, w * 0.66, h * 0.1), col2.darkened(0.12), 6.0)
	var leaf := col
	for i in 7:
		var a: float = lerpf(-2.6, -0.5, float(i) / 6.0)
		var tip := Vector2(cos(a), sin(a)) * (h * 0.6) + Vector2(0, -h * 0.34)
		var ctrl := Vector2(cos(a), sin(a)) * (h * 0.3) + Vector2(0, -h * 0.34) + Vector2(-sin(a), cos(a)) * 22.0
		DinoArt.blob(_ci, DinoArt.limb(Vector2(0, -h * 0.34), tip, ctrl, 30, 4), leaf.darkened(0.06 * (i % 2)), INK, 2.5)


func _table() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h, w, h * 0.24), col, 10.0)
	_box(Rect2(-w * 0.42, -h * 0.76, w * 0.09, h * 0.76), col.darkened(0.14), 5.0)
	_box(Rect2(w * 0.33, -h * 0.76, w * 0.09, h * 0.76), col.darkened(0.14), 5.0)
	_box(Rect2(-w * 0.36, -h * 0.44, w * 0.72, h * 0.1), col.darkened(0.08), 4.0, false)
	_oval(Vector2(w * 0.22, -h * 1.12), w * 0.09, h * 0.14, col2)


func _fridge() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h, w, h), col2, 14.0)
	_ci.draw_line(Vector2(-w * 0.5, -h * 0.62), Vector2(w * 0.5, -h * 0.62), INK, 3.0, true)
	_box(Rect2(w * 0.24, -h * 0.56, w * 0.1, h * 0.26), INK.lightened(0.35), 5.0, false)
	_box(Rect2(w * 0.24, -h * 0.94, w * 0.1, h * 0.24), INK.lightened(0.35), 5.0, false)
	_box(Rect2(-w * 0.34, -h * 0.5, w * 0.3, h * 0.2), col, 5.0, false)


func _counter() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h, w, h * 0.18), col2, 8.0)
	_box(Rect2(-w * 0.46, -h * 0.86, w * 0.92, h * 0.86), col, 8.0)
	for i in 3:
		var x := -w * 0.4 + i * w * 0.3
		_box(Rect2(x, -h * 0.78, w * 0.26, h * 0.3), col.lightened(0.12), 6.0)
		_ci.draw_line(Vector2(x + w * 0.08, -h * 0.6), Vector2(x + w * 0.18, -h * 0.6), INK, 4.0, true)


func _bin() -> void:
	_shadow()
	DinoArt.blob(_ci, PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.9), Vector2(w * 0.5, -h * 0.9),
		Vector2(w * 0.38, 0), Vector2(-w * 0.38, 0),
	]), col, INK, 3.0)
	_box(Rect2(-w * 0.56, -h, w * 1.12, h * 0.16), col.darkened(0.12), 8.0)


func _bed() -> void:
	_shadow()
	# 머리판 / 발치판
	_box(Rect2(-w * 0.5, -h, w * 0.17, h * 0.96), col.darkened(0.12), 18.0)
	_box(Rect2(w * 0.37, -h * 0.66, w * 0.13, h * 0.66), col.darkened(0.12), 14.0)
	# 침대 틀 + 매트리스
	_box(Rect2(-w * 0.46, -h * 0.5, w * 0.92, h * 0.42), col.darkened(0.04), 12.0)
	_box(Rect2(-w * 0.44, -h * 0.6, w * 0.88, h * 0.22), Color("fffaf2"), 12.0)
	# 이불
	_box(Rect2(-w * 0.08, -h * 0.64, w * 0.52, h * 0.28), col, 14.0)
	for i in 3:
		_oval(Vector2(w * 0.06 + i * w * 0.14, -h * 0.5), w * 0.035, h * 0.05, col.lightened(0.22), false)
	# 베개
	_box(Rect2(-w * 0.4, -h * 0.7, w * 0.28, h * 0.18), col2, 14.0)
	# 다리
	_box(Rect2(-w * 0.42, -h * 0.1, w * 0.07, h * 0.1), INK.lightened(0.25), 3.0, false)
	_box(Rect2(w * 0.35, -h * 0.1, w * 0.07, h * 0.1), INK.lightened(0.25), 3.0, false)


func _wardrobe() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h, w, h), col, 10.0)
	_box(Rect2(-w * 0.44, -h * 0.94, w * 0.4, h * 0.88), col.lightened(0.1), 8.0)
	_box(Rect2(w * 0.04, -h * 0.94, w * 0.4, h * 0.88), col.lightened(0.1), 8.0)
	_oval(Vector2(-w * 0.08, -h * 0.5), 5, 5, INK.lightened(0.3), false)
	_oval(Vector2(w * 0.08, -h * 0.5), 5, 5, INK.lightened(0.3), false)
	_box(Rect2(-w * 0.54, -h - h * 0.06, w * 1.08, h * 0.08), col.darkened(0.12), 6.0)


func _nightstand() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h, w, h * 0.86), col, 8.0)
	_box(Rect2(-w * 0.38, -h * 0.86, w * 0.76, h * 0.28), col.lightened(0.12), 6.0)
	_box(Rect2(-w * 0.38, -h * 0.52, w * 0.76, h * 0.28), col.lightened(0.12), 6.0)
	_oval(Vector2(0, -h * 0.72), 5, 5, INK.lightened(0.3), false)
	_oval(Vector2(0, -h * 0.38), 5, 5, INK.lightened(0.3), false)
	_oval(Vector2(0, -h * 1.06), w * 0.2, h * 0.2, col2)


func _bathtub() -> void:
	_shadow()
	DinoArt.blob(_ci, PackedVector2Array([
		Vector2(-w * 0.5, -h), Vector2(w * 0.5, -h),
		Vector2(w * 0.4, 0), Vector2(-w * 0.4, 0),
	]), col2, INK, 3.5)
	_box(Rect2(-w * 0.5, -h, w, h * 0.18), Color.WHITE, 10.0)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -h * 0.92), w * 0.44, h * 0.1, 20), col.lightened(0.2))
	for i in 3:
		_oval(Vector2(-w * 0.22 + i * w * 0.22, -h * 1.02), 14, 12, Color(1, 1, 1, 0.75), false)


func _sink() -> void:
	_shadow()
	_box(Rect2(-w * 0.12, -h * 0.6, w * 0.24, h * 0.6), col2.darkened(0.1), 6.0)
	_box(Rect2(-w * 0.5, -h, w, h * 0.4), col2, 12.0)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -h * 0.9), w * 0.32, h * 0.1, 18), col.lightened(0.15))
	_ci.draw_line(Vector2(0, -h * 1.0), Vector2(0, -h * 1.24), INK.lightened(0.3), 6.0, true)
	_ci.draw_line(Vector2(0, -h * 1.24), Vector2(w * 0.14, -h * 1.18), INK.lightened(0.3), 6.0, true)


func _toilet() -> void:
	_shadow()
	_box(Rect2(-w * 0.42, -h, w * 0.84, h * 0.5), col2, 10.0)
	_box(Rect2(-w * 0.3, -h * 0.55, w * 0.6, h * 0.32), col2.darkened(0.06), 8.0)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -h * 0.3), w * 0.42, h * 0.2, 20), col2, INK, 3.0)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -h * 0.3), w * 0.3, h * 0.13, 18), col.lightened(0.25))
	_oval(Vector2(w * 0.24, -h * 0.94), 6, 6, col, false)


func _basket() -> void:
	_shadow()
	DinoArt.blob(_ci, PackedVector2Array([
		Vector2(-w * 0.42, -h), Vector2(w * 0.42, -h),
		Vector2(w * 0.5, 0), Vector2(-w * 0.5, 0),
	]), col, INK, 3.0)
	for i in 3:
		_ci.draw_line(Vector2(-w * 0.44, -h * 0.75 + i * h * 0.24), Vector2(w * 0.44, -h * 0.75 + i * h * 0.24), col.darkened(0.14), 5.0, true)
	_box(Rect2(-w * 0.48, -h - h * 0.1, w * 0.96, h * 0.14), col.darkened(0.1), 6.0)


func _toybox() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h * 0.86, w, h * 0.86), col, 12.0)
	_box(Rect2(-w * 0.52, -h, w * 1.04, h * 0.2), col.darkened(0.14), 10.0)
	for i in 3:
		var c := [Color("ff8fa3"), Color("ffd166"), Color("6fc7f2")][i] as Color
		_oval(Vector2(-w * 0.26 + i * w * 0.26, -h * 0.42), w * 0.09, w * 0.09, c)


func _blocks() -> void:
	_shadow()
	var cols := [Color("ff8fa3"), Color("6fc7f2"), Color("ffd166"), Color("74cf72")]
	var n := 4
	for i in n:
		var s := w * (0.9 - i * 0.12)
		var y := -h * float(i + 1) / float(n)
		_box(Rect2(-s * 0.5 + sin(float(i)) * 6.0, y, s, h / float(n)), cols[i % 4], 8.0)


func _horse() -> void:
	_shadow()
	# 흔들 받침
	DinoArt.blob(_ci, DinoArt.limb(Vector2(-w * 0.48, -h * 0.28), Vector2(w * 0.48, -h * 0.28), Vector2(0, h * 0.16), 16, 16), col.darkened(0.18), INK, 3.0)
	# 받침 기둥
	_box(Rect2(-w * 0.26, -h * 0.5, w * 0.08, h * 0.34), col.darkened(0.1), 4.0)
	_box(Rect2(w * 0.16, -h * 0.5, w * 0.08, h * 0.34), col.darkened(0.1), 4.0)
	# 몸통
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(-w * 0.02, -h * 0.6), w * 0.34, h * 0.19, 22), col, INK, 3.5)
	# 꼬리
	DinoArt.blob(_ci, DinoArt.limb(Vector2(-w * 0.3, -h * 0.66), Vector2(-w * 0.5, -h * 0.34), Vector2(-w * 0.48, -h * 0.7), 20, 6), col2, INK, 2.5)
	# 목 + 머리
	DinoArt.blob(_ci, DinoArt.limb(Vector2(w * 0.16, -h * 0.68), Vector2(w * 0.3, -h * 0.94), Vector2(w * 0.18, -h * 0.9), 30, 24), col, INK, 3.5)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(w * 0.34, -h * 0.98), w * 0.16, h * 0.11, 18), col, INK, 3.5)
	# 갈기 / 귀 / 눈
	DinoArt.blob(_ci, DinoArt.limb(Vector2(w * 0.24, -h * 1.06), Vector2(w * 0.02, -h * 0.72), Vector2(w * 0.1, -h * 1.04), 22, 8), col2, INK, 2.5)
	DinoArt.blob(_ci, DinoArt.tri(Vector2(w * 0.26, -h * 1.04), Vector2(w * 0.34, -h * 1.04), Vector2(w * 0.28, -h * 1.2)), col, INK, 2.5)
	_oval(Vector2(w * 0.38, -h * 1.0), 5, 5, INK, false)
	# 안장 + 손잡이
	_box(Rect2(-w * 0.14, -h * 0.78, w * 0.22, h * 0.14), col2.darkened(0.06), 8.0)
	_ci.draw_line(Vector2(w * 0.1, -h * 0.8), Vector2(w * 0.24, -h * 0.86), INK.lightened(0.3), 6.0, true)


func _balls() -> void:
	_shadow()
	var cols := [Color("ff8fa3"), Color("6fc7f2"), Color("ffd166"), Color("74cf72"), Color("b79cf0")]
	var r := h * 0.42
	var xs := [-w * 0.32, w * 0.02, w * 0.34, -w * 0.16, w * 0.2]
	var ys := [-r, -r * 0.9, -r * 1.05, -r * 2.1, -r * 2.2]
	for i in 5:
		var c := cols[i] as Color
		_oval(Vector2(xs[i], ys[i]), r, r, c)
		_oval(Vector2(xs[i] - r * 0.3, ys[i] - r * 0.35), r * 0.22, r * 0.18, Color(1, 1, 1, 0.6), false)


func _boxes() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h * 0.5, w, h * 0.5), col, 8.0)
	_ci.draw_line(Vector2(0, -h * 0.5), Vector2(0, 0), col.darkened(0.16), 4.0, true)
	_box(Rect2(-w * 0.4, -h * 0.94, w * 0.78, h * 0.46), col.lightened(0.08), 8.0)
	_ci.draw_line(Vector2(-w * 0.4, -h * 0.72), Vector2(w * 0.38, -h * 0.72), col.darkened(0.14), 4.0, true)
	_box(Rect2(-w * 0.16, -h * 0.98, w * 0.3, h * 0.08), col2, 4.0, false)


func _trunk() -> void:
	_shadow()
	_box(Rect2(-w * 0.5, -h * 0.7, w, h * 0.7), col, 8.0)
	DinoArt.blob(_ci, PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.68), Vector2(-w * 0.42, -h),
		Vector2(w * 0.42, -h), Vector2(w * 0.5, -h * 0.68),
	]), col.lightened(0.1), INK, 3.0)
	for i in 2:
		var x := -w * 0.3 + i * w * 0.6
		_ci.draw_line(Vector2(x, -h), Vector2(x, 0), col2, 7.0, true)
	_box(Rect2(-w * 0.08, -h * 0.74, w * 0.16, h * 0.16), col2, 4.0)


func _chair() -> void:
	_shadow()
	_box(Rect2(-w * 0.44, -h, w * 0.88, h * 0.5), col, 10.0)
	_box(Rect2(-w * 0.5, -h * 0.5, w, h * 0.14), col.lightened(0.08), 8.0)
	_box(Rect2(-w * 0.42, -h * 0.38, w * 0.1, h * 0.38), col.darkened(0.1), 5.0)
	_box(Rect2(w * 0.32, -h * 0.38, w * 0.1, h * 0.38), col.darkened(0.1), 5.0)


# ---------------------------------------------------------------- 벽 장식(뒤)

func _window() -> void:
	_box(Rect2(-w * 0.5, -h, w, h), col, 10.0)
	_box(Rect2(-w * 0.44, -h * 0.94, w * 0.88, h * 0.88), Color("bfe9ff"), 6.0, false)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(-w * 0.16, -h * 0.72), w * 0.14, h * 0.1, 16), Color(1, 1, 1, 0.85))
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(-w * 0.02, -h * 0.74), w * 0.1, h * 0.08, 16), Color(1, 1, 1, 0.85))
	_ci.draw_line(Vector2(0, -h * 0.94), Vector2(0, -h * 0.06), col, 8.0)
	_ci.draw_line(Vector2(-w * 0.44, -h * 0.5), Vector2(w * 0.44, -h * 0.5), col, 8.0)


func _picture() -> void:
	_box(Rect2(-w * 0.5, -h, w, h), col, 6.0)
	_box(Rect2(-w * 0.42, -h * 0.9, w * 0.84, h * 0.8), col2, 4.0, false)
	DinoArt.blob(_ci, DinoArt.tri(Vector2(-w * 0.3, -h * 0.2), Vector2(0, -h * 0.72), Vector2(w * 0.3, -h * 0.2)), Color("9fd8a0"))
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(w * 0.24, -h * 0.66), w * 0.1, h * 0.14, 14), Color("ffd166"))


func _rug() -> void:
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -h * 0.5), w * 0.5, h * 0.5, 28), col)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -h * 0.5), w * 0.38, h * 0.36, 26), col2)
	DinoArt.blob(_ci, DinoArt.ellipse(Vector2(0, -h * 0.5), w * 0.24, h * 0.22, 24), col)


func _curtain() -> void:
	for s: float in [-1.0, 1.0]:
		var x: float = s * w * 0.5
		DinoArt.blob(_ci, PackedVector2Array([
			Vector2(x, -h), Vector2(x - s * w * 0.3, -h),
			Vector2(x - s * w * 0.22, 0), Vector2(x, 0),
		]), col, INK, 3.0)
		for i in 3:
			_ci.draw_line(Vector2(x - s * (w * 0.06 + i * w * 0.07), -h * 0.94), Vector2(x - s * (w * 0.04 + i * w * 0.06), -h * 0.06), col.darkened(0.1), 4.0, true)
	_box(Rect2(-w * 0.56, -h - 12, w * 1.12, 14), col.darkened(0.2), 7.0)


func _cobweb() -> void:
	var o := Vector2(-w * 0.5, -h)
	for i in 5:
		var a: float = lerpf(0.0, PI * 0.5, float(i) / 4.0)
		_ci.draw_line(o, o + Vector2(cos(a), sin(a)) * w, col, 3.0, true)
	for k in 3:
		var r := w * (0.35 + k * 0.3)
		var pts := PackedVector2Array()
		for i in 9:
			var a: float = lerpf(0.0, PI * 0.5, float(i) / 8.0)
			pts.append(o + Vector2(cos(a), sin(a)) * r * (1.0 - 0.08 * sin(float(i) * 1.7)))
		_ci.draw_polyline(pts, col, 3.0, true)


func _shelf() -> void:
	_box(Rect2(-w * 0.5, -h * 0.18, w, h * 0.18), col, 5.0)
	var cols := [Color("ff8fa3"), Color("6fc7f2"), Color("ffd166"), Color("74cf72"), Color("b79cf0")]
	for i in 5:
		var bh := h * (0.5 + 0.12 * sin(float(i) * 2.1))
		_box(Rect2(-w * 0.42 + i * w * 0.17, -h * 0.18 - bh, w * 0.12, bh), cols[i], 3.0)
