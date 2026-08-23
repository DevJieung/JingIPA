extends RefCounted
class_name Fx

## 이펙트 한 무더기. 화면 하나가 Fx 를 하나 들고 매 프레임 update() → draw() 한다.
##
## 왜 노드로 안 만들었나: 풀하우스 연출 하나에 파티클이 300개 넘게 뜨는데, 그걸 전부
## Node2D 로 만들면 프레임마다 노드가 300개 생겼다 사라진다. 폰에서 그대로 끊긴다.
## 여기서는 딕셔너리 배열 하나이고 그리기도 한 번에 끝난다.

var items: Array = []
## 화면 흔들림. 화면 쪽에서 shake_offset() 을 읽어 카메라 대신 좌표를 밀어 준다.
var shake: float = 0.0
var shake_seed: float = 0.0
## 화면 전체를 덮는 섬광.
var flash_color: Color = Color(0, 0, 0, 0)
var flash_t: float = 0.0
var flash_max: float = 0.0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	items.clear()
	shake = 0.0
	flash_t = 0.0


# --------------------------------------------------------------------------- #
# 낳기
# --------------------------------------------------------------------------- #
## 사방으로 튀는 불똥. 몬스터가 죽을 때, 탄이 맞을 때.
func burst(pos: Vector2, col: Color, n: int = 10, speed: float = 190.0,
		life: float = 0.45, size: float = 3.0, grav: float = 240.0) -> void:
	for i in range(n):
		var a := _rng.randf() * TAU
		var sp := speed * _rng.randf_range(0.45, 1.25)
		items.append({"t": "spark", "p": pos, "v": Vector2(cos(a), sin(a)) * sp,
			"life": life * _rng.randf_range(0.7, 1.3), "max": life, "c": col,
			"s": size * _rng.randf_range(0.7, 1.4), "g": grav})


## 퍼져 나가는 고리. 광역 공격·등장 연출.
func ring(pos: Vector2, col: Color, r0: float, r1: float, life: float = 0.4,
		width: float = 4.0) -> void:
	items.append({"t": "ring", "p": pos, "r0": r0, "r1": r1, "life": life,
		"max": life, "c": col, "w": width})


## 위로 떠오르며 사라지는 글자. 골드·데미지 표시.
func float_text(pos: Vector2, s: String, col: Color, size: int = 20,
		life: float = 0.8) -> void:
	items.append({"t": "text", "p": pos, "v": Vector2(0, -46.0), "life": life,
		"max": life, "c": col, "s": s, "sz": size})


## 두 점을 잇는 번쩍이는 선. 광선.
func beam(a: Vector2, b: Vector2, col: Color, life: float = 0.14,
		width: float = 4.0) -> void:
	items.append({"t": "beam", "a": a, "b": b, "life": life, "max": life,
		"c": col, "w": width})


## 지그재그로 튀는 번개. 연쇄 공격.
## ★ 곧은 선으로 그리면 광선과 구별이 안 되고, 무엇보다 **눈에 안 띈다.**
##   꺾인 선은 짧게 번쩍여도 "번개가 튀었다"가 읽힌다.
func bolt(a: Vector2, b: Vector2, col: Color, life: float = 0.22,
		width: float = 5.0) -> void:
	var d := b - a
	var len_px := d.length()
	if len_px < 1.0:
		return
	var nrm := Vector2(-d.y, d.x) / len_px
	var pts := PackedVector2Array()
	var n := 5
	for i in range(n + 1):
		var k := float(i) / float(n)
		var off := 0.0
		if i > 0 and i < n:
			off = _rng.randf_range(-1.0, 1.0) * len_px * 0.10
		pts.append(a.lerp(b, k) + nrm * off)
	items.append({"t": "bolt", "pts": pts, "life": life, "max": life,
		"c": col, "w": width})


## 꽉 찬 원이 부풀며 사라진다. 장판·폭탄처럼 **넓이**가 보여야 하는 것.
func disc(pos: Vector2, col: Color, r: float, life: float = 0.35,
		alpha: float = 0.30) -> void:
	items.append({"t": "disc", "p": pos, "r": r, "life": life, "max": life,
		"c": col, "a": alpha})


## 가운데에서 뻗어 나가는 빛살. 풀하우스 이상에서만 쓴다.
func rays(pos: Vector2, col: Color, n: int = 16, len_px: float = 620.0,
		life: float = 1.1) -> void:
	items.append({"t": "rays", "p": pos, "n": n, "len": len_px, "life": life,
		"max": life, "c": col, "spin": _rng.randf() * TAU})


## 카드가 깨져 흩어지는 조각.
func shards(rect: Rect2, col: Color, n: int = 18) -> void:
	for i in range(n):
		var p := rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		var a := _rng.randf() * TAU
		items.append({"t": "shard", "p": p, "v": Vector2(cos(a), sin(a)) * _rng.randf_range(90.0, 420.0),
			"life": _rng.randf_range(0.6, 1.2), "max": 1.2, "c": col,
			"s": _rng.randf_range(6.0, 15.0), "rot": _rng.randf() * TAU,
			"spin": _rng.randf_range(-9.0, 9.0), "g": 520.0})


## 얼음 조각이 사방으로 튄다. 둔화가 **새로 걸리는 순간**에만 쓴다.
##
## ★ 왜 불똥(burst)으로 안 쓰나: 불똥은 둥근 점이라 화상·타격과 구별이 안 된다.
##   얼음은 **각진 마름모가 돌면서** 퍼지고, 떨어지지 않고 공기에 걸린 듯 멎어야
##   얼음으로 읽힌다. 그래서 중력(g)이 없고 속도가 감쇠한다.
func frost(pos: Vector2, n: int = 8, speed: float = 130.0, life: float = 0.5) -> void:
	for i in range(n):
		var a := _rng.randf() * TAU
		items.append({"t": "ice", "p": pos,
			"v": Vector2(cos(a), sin(a)) * speed * _rng.randf_range(0.45, 1.25),
			"life": life * _rng.randf_range(0.7, 1.3), "max": life,
			"c": Look.ICE, "s": _rng.randf_range(3.0, 6.0),
			"rot": _rng.randf() * TAU, "spin": _rng.randf_range(-4.0, 4.0)})


## 그림 한 장을 잠깐 띄운다(폭발 스프라이트 같은 것). 커지면서 사라진다.
func sprite(pos: Vector2, path: String, sc: float = 1.0, life: float = 0.45) -> void:
	if Art.tex(path) == null:
		return
	items.append({"t": "spr", "p": pos, "path": path, "sc": sc, "life": life, "max": life,
		"c": Color.WHITE})


func do_shake(power: float) -> void:
	shake = max(shake, power)
	shake_seed = _rng.randf() * 100.0


func do_flash(col: Color, sec: float = 0.35) -> void:
	flash_color = col
	flash_t = sec
	flash_max = sec


func shake_offset() -> Vector2:
	if shake <= 0.01:
		return Vector2.ZERO
	var t := Time.get_ticks_msec() * 0.06 + shake_seed
	return Vector2(sin(t * 1.7) , cos(t * 2.3)) * shake


# --------------------------------------------------------------------------- #
# 굴리기
# --------------------------------------------------------------------------- #
func update(dt: float) -> void:
	shake = move_toward(shake, 0.0, dt * 46.0)
	if flash_t > 0.0:
		flash_t = max(0.0, flash_t - dt)
	var keep: Array = []
	for it in items:
		it["life"] = float(it["life"]) - dt
		if float(it["life"]) <= 0.0:
			continue
		match String(it["t"]):
			"spark", "shard":
				it["v"] = Vector2(it["v"]) + Vector2(0, float(it.get("g", 0.0))) * dt
				it["p"] = Vector2(it["p"]) + Vector2(it["v"]) * dt
				if it["t"] == "shard":
					it["rot"] = float(it["rot"]) + float(it["spin"]) * dt
			"ice":
				# 공기에 걸리듯 천천히 멎는다. 불똥처럼 떨어뜨리면 얼음이 아니라 불티다.
				it["p"] = Vector2(it["p"]) + Vector2(it["v"]) * dt
				it["v"] = Vector2(it["v"]) * (1.0 - clampf(dt * 3.4, 0.0, 0.95))
				it["rot"] = float(it["rot"]) + float(it["spin"]) * dt
			"text":
				it["p"] = Vector2(it["p"]) + Vector2(it["v"]) * dt
				it["v"] = Vector2(it["v"]) * 0.94
		keep.append(it)
	items = keep


## 빛살·고리처럼 **글자 뒤에** 깔려야 하는 것들. 내용을 그리기 **전에** 부른다.
## ★ 예전에는 전부 한 번에 앞에 그렸는데, 로열 연출에서 빛살이 족보 이름을 덮어
##   무슨 족보인지 안 보였다. 게임에서 제일 드문 순간인데 그게 안 읽히면 안 된다.
const BACK := ["rays", "ring", "disc"]


func draw_back(ci: CanvasItem) -> void:
	_paint(ci, true)


func draw(ci: CanvasItem) -> void:
	_paint(ci, false)


func _paint(ci: CanvasItem, back: bool) -> void:
	for it in items:
		if (String(it["t"]) in BACK) != back:
			continue
		var k: float = clampf(float(it["life"]) / max(0.001, float(it["max"])), 0.0, 1.0)
		var col: Color = it["c"]
		match String(it["t"]):
			"spark":
				ci.draw_circle(it["p"], float(it["s"]) * k, Color(col.r, col.g, col.b, k))
			"shard":
				var s: float = float(it["s"])
				# ★ 너무 작아지면 네 점이 한 점으로 뭉쳐 "triangulation failed" 오류가
				#   프레임마다 쏟아진다. 안 보일 만큼 작으면 그냥 건너뛴다.
				if s * k < 0.7:
					continue
				var r: float = float(it["rot"])
				var p: Vector2 = it["p"]
				var pts := PackedVector2Array()
				for j in range(4):
					var a := r + TAU * float(j) / 4.0
					pts.append(p + Vector2(cos(a), sin(a)) * s * k)
				ci.draw_colored_polygon(pts, Color(col.r, col.g, col.b, k))
			"ice":
				# 세로로 긴 마름모 — 정사각형으로 두면 카드 조각(shard)과 똑같아 보인다.
				var isz: float = float(it["s"]) * (0.55 + k * 0.45)
				# ★ 0 으로 줄어든 도형을 draw_colored_polygon 에 넘기면 점이 뭉쳐
				#   triangulation failed 오류가 프레임마다 쏟아진다.
				if isz < 0.7:
					continue
				var ir: float = float(it["rot"])
				var ip: Vector2 = it["p"]
				var ipts := PackedVector2Array()
				for j in range(4):
					var ia: float = ir + TAU * float(j) / 4.0
					var ilen: float = isz * (1.55 if j % 2 == 0 else 0.60)
					ipts.append(ip + Vector2(cos(ia), sin(ia)) * ilen)
				ci.draw_colored_polygon(ipts, Color(col.r, col.g, col.b, k))
			"ring":
				var rr: float = lerpf(float(it["r1"]), float(it["r0"]), k)
				ci.draw_arc(it["p"], rr, 0.0, TAU, 48, Color(col.r, col.g, col.b, k),
						float(it["w"]) * k, true)
			"text":
				Look.text_center(ci, it["p"], String(it["s"]), int(it["sz"]),
						Color(col.r, col.g, col.b, k))
			"spr":
				var tx := Art.tex(String(it["path"]))
				if tx != null:
					var gs: float = float(it["sc"]) * (1.35 - k * 0.35)
					var tw: float = float(tx.get_width()) * gs
					var th: float = float(tx.get_height()) * gs
					ci.draw_texture_rect(tx, Rect2(Vector2(it["p"]) - Vector2(tw, th) * 0.5,
							Vector2(tw, th)), false, Color(1, 1, 1, k))
			"beam":
				# ★ 세 겹으로 그린다 — 넓고 흐린 빛무리 · 색 · 흰 심.
				#   한 겹짜리 선은 배경에 묻혀서 "쐈는지 안 쐈는지"가 안 보였다.
				var bw: float = float(it["w"]) * k
				ci.draw_line(it["a"], it["b"], Color(col.r, col.g, col.b, k * 0.28),
						bw * 3.0, true)
				ci.draw_line(it["a"], it["b"], Color(col.r, col.g, col.b, k), bw, true)
				ci.draw_line(it["a"], it["b"], Color(1, 1, 1, k * 0.9), bw * 0.35, true)
				ci.draw_circle(it["b"], bw * 1.4, Color(1, 1, 1, k * 0.55))
			"bolt":
				var bpts: PackedVector2Array = it["pts"]
				var lw: float = float(it["w"]) * k
				if lw < 0.6 or bpts.size() < 2:
					continue
				ci.draw_polyline(bpts, Color(col.r, col.g, col.b, k * 0.30), lw * 2.6, true)
				ci.draw_polyline(bpts, Color(col.r, col.g, col.b, k), lw, true)
				ci.draw_polyline(bpts, Color(1, 1, 1, k * 0.85), lw * 0.4, true)
			"disc":
				var dr: float = float(it["r"]) * (1.25 - k * 0.25)
				if dr < 1.0:
					continue
				ci.draw_circle(it["p"], dr, Color(col.r, col.g, col.b,
						float(it["a"]) * k))
			"rays":
				var n: int = int(it["n"])
				var p2: Vector2 = it["p"]
				var spin: float = float(it["spin"]) + (1.0 - k) * 1.6
				var ln: float = float(it["len"]) * (1.0 - k * 0.35)
				if ln < 2.0:
					continue
				for j in range(n):
					var a2 := spin + TAU * float(j) / float(n)
					var wdt := 0.055
					var q := PackedVector2Array([
						p2,
						p2 + Vector2(cos(a2 - wdt), sin(a2 - wdt)) * ln,
						p2 + Vector2(cos(a2 + wdt), sin(a2 + wdt)) * ln])
					ci.draw_colored_polygon(q, Color(col.r, col.g, col.b, k * 0.30))


## 화면 전체를 덮는 섬광. 다른 것을 다 그린 **뒤에** 부른다.
func draw_flash(ci: CanvasItem, screen: Rect2) -> void:
	if flash_t <= 0.0:
		return
	var k: float = flash_t / max(0.001, flash_max)
	ci.draw_rect(screen, Color(flash_color.r, flash_color.g, flash_color.b,
			flash_color.a * k))
