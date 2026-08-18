extends RefCounted

## 개발용: 화면 대신 그리기 명령을 모아 JSON으로 뽑아낸다.
## (그래픽 카드 없는 서버에서 화면 구성을 확인하려고 만든 도구)

var cmds: Array = []

var _node := Transform2D.IDENTITY
var _draw := Transform2D.IDENTITY


func set_node(x: Transform2D) -> void:
	_node = x
	_draw = Transform2D.IDENTITY


func draw_set_transform(offset: Vector2, rot := 0.0, sc := Vector2.ONE) -> void:
	_draw = Transform2D(rot, sc, 0.0, offset)


func _t(p: Vector2) -> Array:
	var q: Vector2 = _node * (_draw * p)
	return [snappedf(q.x, 0.01), snappedf(q.y, 0.01)]


func _scale() -> float:
	var s := (_node * _draw).get_scale()
	return maxf(0.05, (absf(s.x) + absf(s.y)) * 0.5)


func _c(col: Color) -> Array:
	return [int(col.r8), int(col.g8), int(col.b8), int(col.a * 255.0)]


func _poly(pts: Array, col: Color) -> void:
	cmds.append({"t": "poly", "p": pts, "c": _c(col)})


func draw_colored_polygon(pts, col: Color, _uv = null, _tex = null) -> void:
	var out: Array = []
	for p in pts:
		out.append(_t(p))
	_poly(out, col)


func draw_polyline(pts, col: Color, width := 1.0, _aa := false) -> void:
	var out: Array = []
	for p in pts:
		out.append(_t(p))
	cmds.append({"t": "line", "p": out, "c": _c(col), "w": maxf(1.0, width * _scale())})


func draw_line(a: Vector2, b: Vector2, col: Color, width := 1.0, _aa := false) -> void:
	cmds.append({"t": "line", "p": [_t(a), _t(b)], "c": _c(col), "w": maxf(1.0, width * _scale())})


func draw_rect(r: Rect2, col: Color, filled := true, width := -1.0) -> void:
	var pts := [_t(r.position), _t(Vector2(r.end.x, r.position.y)), _t(r.end), _t(Vector2(r.position.x, r.end.y))]
	if filled:
		_poly(pts, col)
	else:
		var closed := pts.duplicate()
		closed.append(pts[0])
		cmds.append({"t": "line", "p": closed, "c": _c(col), "w": maxf(1.0, width * _scale())})


func draw_circle(pos: Vector2, radius: float, col: Color, filled := true, _w := -1.0, _aa := false) -> void:
	var pts: Array = []
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(_t(pos + Vector2(cos(a), sin(a)) * radius))
	if filled:
		_poly(pts, col)


func draw_arc(center: Vector2, radius: float, a0: float, a1: float, count: int, col: Color, width := 1.0, _aa := false) -> void:
	var pts: Array = []
	for i in count + 1:
		var a: float = lerpf(a0, a1, float(i) / float(count))
		pts.append(_t(center + Vector2(cos(a), sin(a)) * radius))
	cmds.append({"t": "line", "p": pts, "c": _c(col), "w": maxf(1.0, width * _scale())})


## 공룡 그림. 파일 이름만 넘겨주면 파이썬 쪽에서 games/dino/dinos/ 에서 찾아 붙인다.
func draw_texture_rect(tex, rect: Rect2, _tile := false, modulate := Color.WHITE, _transpose := false) -> void:
	cmds.append({
		"t": "img", "src": _src(tex), "c": _c(modulate),
		"p": [_t(rect.position), _t(rect.end)],
	})


func _src(tex) -> String:
	if tex == null:
		return ""
	var p := String(tex.resource_path)
	var f := p.get_file()
	# 임포트된 텍스처는 res://.godot/imported/trex.png-<해시>.ctex 로 잡힌다
	var cut := f.rfind(".png-")
	if cut > 0:
		f = f.substr(0, cut + 4)
	return f


func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(cmds))
	f.close()
