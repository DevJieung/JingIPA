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


## 캐릭터의 분리된 착탄 애니메이션. 범위는 전투가 정한 반경을 따른다.
func clip(pos: Vector2, animation: Dictionary, radius: float) -> void:
	if animation.is_empty():
		return
	var life: float = float(animation["total"]) / 1000.0
	items.append({"t": "clip", "p": pos, "clip": animation, "r": radius,
		"life": life, "max": life, "c": Color.WHITE, "bk": false})


## 즉시 닿는 광선도 캐릭터의 Shot 시트를 사용한다. 피해 시점은 바꾸지 않는다.
func clip_beam(a: Vector2, b: Vector2, animation: Dictionary, tier: int = 0) -> void:
	if animation.is_empty() or a.distance_squared_to(b) < 1.0:
		return
	items.append({"t": "clip_beam", "a": a, "b": b, "clip": animation,
		"life": 0.28, "max": 0.28, "c": Color.WHITE, "bk": false,
		"width": 24.0 * shot_scale(tier)})


## Native chain attacks supply their own horizontal Shot segment. Passive
## lightning has no owning sprite and keeps the normal procedural bolt.
func clip_chain(a: Vector2, b: Vector2, animation: Dictionary, tier: int = 0) -> void:
	if animation.is_empty() or a.distance_squared_to(b) < 1.0:
		return
	items.append({"t": "clip_beam", "a": a, "b": b, "clip": animation,
		"life": 0.24, "max": 0.24, "c": Color.WHITE, "bk": false,
		"width": 15.0 * shot_scale(tier), "native_chain": true})


## 희귀도는 연출만 바꾼다. 피해·발사 수·충돌 반경에는 관여하지 않는다.
static func shot_scale(tier: int) -> float:
	return [1.0, 1.05, 1.12, 1.20, 1.30, 1.42, 1.56, 1.70, 1.86, 2.04][clampi(tier, 0, 9)]


## 한 착탄을 한 항목으로 관리해서 중첩 연사에도 파티클 수가 폭증하지 않게 한다.
func rarity_impact(pos: Vector2, col: Color, tier: int, power: float = 1.0) -> void:
	if tier < 2 or power <= 0.0 or items.size() >= 900:
		return
	var life := 0.24 + float(tier) * 0.022
	items.append({"t": "rarity", "p": pos, "c": col, "tier": clampi(tier, 0, 9),
		"r": (14.0 + float(tier) * 3.4) * power, "life": life, "max": life,
		"phase": _rng.randf() * TAU, "bk": false})


## One bounded item per weak hit: paired shockwaves, sharp rays and pixel sparks.
func weak_impact(pos: Vector2, col: Color, tier: int, crit: bool = false) -> void:
	if items.size() >= 900:
		return
	items.append({"t": "weak", "p": pos, "c": col, "tier": tier,
		"r": (38.0 + clampi(tier, 0, 9) * 3.0) * (1.25 if crit else 1.0),
		"life": 0.42, "max": 0.42, "phase": _rng.randf() * TAU, "bk": false})


static func projectile_glow(ci: CanvasItem, p: Vector2, prev: Vector2, direction: Vector2,
		col: Color, tier: int, time: float) -> void:
	if tier < 2:
		return
	var power := shot_scale(tier)
	var side := direction.orthogonal()
	var tail := prev - direction * (9.0 + float(tier) * 4.5)
	ci.draw_line(tail, p, Color(col, 0.13), 8.0 * power, true)
	ci.draw_line(tail.lerp(p, 0.22), p, Color(col, 0.62), 2.2 * power, true)
	ci.draw_circle(p, 5.0 * power, Color(col, 0.18))
	if tier >= 4:
		for sign in [-1.0, 1.0]:
			var offset: Vector2 = side * float(sign) * (3.0 + float(tier) * 0.65)
			ci.draw_line(tail + offset * 0.4, p + offset, Color(col.lightened(0.24), 0.62), 1.8, true)
	if tier >= 6:
		for i in range(3):
			var phase := time * 8.0 + float(i) * TAU / 3.0
			var q := p - direction * (9.0 + float(i) * 10.0) + side * sin(phase) * 9.0
			var spark := col.lightened(0.55)
			ci.draw_line(q - direction * 3.0, q + direction * 3.0, spark, 2.0, true)
			ci.draw_line(q - side * 2.0, q + side * 2.0, Color(spark, 0.8), 1.5, true)
	if tier >= 8:
		ci.draw_arc(p, 10.0 * power, time * 6.0, time * 6.0 + PI * 1.5,
				18, Color(col.lightened(0.3), 0.72), 2.0, true)
		ci.draw_line(p - side * 7.0 * power, p + side * 7.0 * power,
				Color(col.lightened(0.75), 0.75), 2.0, true)


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
##
## ★ pop 은 **튀어나오는 세기**다. 0 이면 예전처럼 그냥 떠오르고, 1 이면 태어나는 순간
##   1.6배로 부풀었다가 제 크기로 내려앉는다. 데미지 숫자가 그것 없이 그냥 떠오르면
##   여섯 발이 동시에 맞아도 화면이 조용해서 "때리고 있다"가 안 읽힌다.
func float_text(pos: Vector2, s: String, col: Color, size: int = 20,
		life: float = 0.8, pop: float = 0.0, edge: bool = false,
		vel: Vector2 = Vector2(0, -46.0)) -> void:
	items.append({"t": "text", "p": pos, "v": vel, "life": life,
		"max": life, "c": col, "s": s, "sz": size, "pop": pop, "edge": edge})


## 데미지 숫자. **상성이 곧 연출의 세기다** (사용자가 정한 것: 「두 배면 더 큰 이펙트,
## 반감이면 소극적인 이펙트」).
##
##   em > 1  약점 — 크고, 속성 색이고, 테두리를 두르고, 높이 튄다
##   em < 1  저항 — 작고, 잿빛이고, 거의 안 튄다
##   crit    치명타 — 상성 색을 유지하며 크기와 외곽선을 강화한다
##
## ★ 숫자를 **줄여서** 보여 준다. 후반 한 대가 30만이라 그대로 찍으면 여섯 자리가
##   투기장을 가로지른다. 1.2k · 34k 로 줄이면 자릿수만으로도 세기가 읽힌다.
func dmg_text(pos: Vector2, n: float, em: float, crit: bool, elem_col: Color) -> void:
	if n < 0.5:
		return
	var s: String = _short_num(n)
	var col := Color("#eeeae2")
	var size := 20
	var life := 0.62
	var pop := 0.5
	var edge := false
	var up := -60.0
	if em > 1.01:
		col = elem_col
		size = 34
		life = 0.85
		pop = 1.0
		edge = true
		up = -96.0
		s += "!"
	elif em < 0.99:
		col = Color("#9a9da3")
		size = 15
		life = 0.42
		pop = 0.0
		up = -34.0
	if crit:
		size = int(float(size) * 1.35)
		pop = maxf(pop, 0.85)
		edge = true
		life += 0.15
	float_text(pos, s, col, size, life, pop, edge,
			Vector2(_rng.randf_range(-26.0, 26.0), up))


## 큰 수를 짧게. 1240 → 1.2k · 34000 → 34k
static func _short_num(n: float) -> String:
	if n < 1000.0:
		return "%d" % int(round(n))
	if n < 10000.0:
		return "%.1fk" % (n / 1000.0)
	if n < 1000000.0:
		return "%dk" % int(round(n / 1000.0))
	return "%.1fM" % (n / 1000000.0)


## **시전 파동** — 발밑에서 머리 위로 훑고 지나가는 고리.
##
## 사용자가 정한 광역 마법의 연출이다: 「두 팔을 들어올림과 동시에 발밑에서 머리위로
## 이펙트가 지나가고」. 그래서 이것은 폭발도 고리도 아니고 **위로 올라가는 한 줄**이다.
##
## ★ **항목 하나로 그린다**(blast 와 같은 까닭). 겹친 x5 시전자가 원시 도형을 다섯 배로
##   낳으면 이펙트 배열이 그것으로 차서 정작 타격 이펙트가 묻힌다.
## ★ **앞 layer 다**(bk:false). 뒤에 깔면 시전자 제 그림이 파동을 통째로 가린다 —
##   폭발이 겪었던 것과 똑같은 함정이다(CLAUDE.md 10-9-1).
func rise(pos: Vector2, col: Color, ec: Color, h: float, life: float = 0.42,
		el: String = "none") -> void:
	items.append({"t": "rise", "p": pos, "c": col, "ec": ec, "h": maxf(8.0, h),
		"life": life, "max": life, "el": el,
		"sd": _rng.randf() * TAU, "bk": false})


## 네모난 파편. 불똥(둥근 점)과 **모양으로** 갈라 둔다 — 폭발에는 부서진 조각이 있어야
## 터진 것으로 보이고, 도트 화면에서는 네모가 훨씬 결이 맞는다.
##
## ★ `dir` 을 주면 그쪽으로 쏠려 튄다(퍼짐은 `spread` 만큼). 탄이 날아온 쪽을 뒤집어
##   넘기면 「맞고 튕겨 나온 조각」이 된다 — 사방으로 고르게 뿌리면 무엇이 어느 쪽에서
##   때렸는지가 화면에서 통째로 사라진다.
## ★ **넘겨받은 인자 그대로** ZERO 인지 본다. 부르는 쪽이 `-d` 를 넘기는데 ZERO 를
##   뒤집어도 ZERO 라, 정규화한 값으로 재면 「방향 없음」과 구별할 길이 없다.
func debris(pos: Vector2, col: Color, n: int = 10, speed: float = 260.0,
		life: float = 0.6, size: float = 5.0,
		dir: Vector2 = Vector2.ZERO, spread: float = TAU) -> void:
	var aimed: bool = dir != Vector2.ZERO
	var base: float = dir.angle() if aimed else 0.0
	for i in range(n):
		var a := (base + _rng.randf_range(-spread * 0.5, spread * 0.5)) if aimed \
				else _rng.randf() * TAU
		items.append({"t": "chunk", "p": pos,
			"v": Vector2(cos(a), sin(a)) * speed * _rng.randf_range(0.4, 1.3),
			"life": life * _rng.randf_range(0.7, 1.3), "max": life, "c": col,
			"s": size * _rng.randf_range(0.6, 1.4), "rot": _rng.randf() * TAU,
			"spin": _rng.randf_range(-11.0, 11.0), "g": 620.0})


## 두 점을 잇는 번쩍이는 선. 광선.
##
## ★ core 를 끄면 흰 심지와 끝점 구슬을 안 그린다. **속성 빛무리**를 광선 뒤에 한 겹
##   더 깔 때 쓴다 — 심지를 두 번 그리면 굵은 흰 막대가 되어 무슨 색 광선인지 사라진다.
func beam(a: Vector2, b: Vector2, col: Color, life: float = 0.14,
		width: float = 4.0, core: bool = true) -> void:
	items.append({"t": "beam", "a": a, "b": b, "life": life, "max": life,
		"c": col, "w": width, "core": core})


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


## 시전 파동 한 장. 발밑(p)에서 머리 위(p.y - h)까지 올라가는 납작한 고리 하나와,
## 그 고리를 따라 위로 끌려 올라가는 알갱이 몇.
##
## ★ **납작한 타원**이다. 정원으로 그리면 바닥에 깔린 원반으로 보여서 「올라간다」가
##   안 읽힌다 — 올라가는 것은 세로로 움직이는 가로선이라야 읽힌다.
## ★ 위로 갈수록 **넓어지고 옅어진다.** 좁아지면 빨려 들어가는 것으로 보인다.
func _paint_rise(ci: CanvasItem, it: Dictionary, k: float) -> void:
	var p: Vector2 = it["p"]
	var h: float = float(it["h"])
	var col: Color = it["c"]
	var ec: Color = it["ec"]
	# k 는 1 에서 0 으로 준다. 파동은 아래에서 위로 가므로 뒤집어 쓴다.
	var u: float = 1.0 - k
	var y: float = p.y - h * u
	var rw: float = h * (0.20 + 0.26 * u)
	var rh: float = maxf(1.5, rw * 0.30)
	var a: float = sin(u * PI) * 0.9
	if rw < 1.2 or a <= 0.01:
		return
	# 고리 — 바깥 한 겹(속성색)과 안쪽 한 겹(캐릭터색).
	_ellipse(ci, Vector2(p.x, y), rw, rh, Color(ec.r, ec.g, ec.b, a * 0.85), 3.0)
	_ellipse(ci, Vector2(p.x, y), rw * 0.62, rh * 0.62, Color(col.r, col.g, col.b, a * 0.7), 2.0)
	# 끌려 올라가는 알갱이. 배열을 안 쓰고 번호와 시간으로 자리를 셈한다(날씨와 같은 수법).
	var sd: float = float(it["sd"])
	for i in range(6):
		var ph: float = fposmod(u + float(i) * 0.17, 1.0)
		var ang: float = sd + float(i) * 1.31
		var qy: float = p.y - h * ph
		var qx: float = p.x + cos(ang + ph * 3.0) * rw * 0.78
		var s: float = 2.6 * (1.0 - ph) + 0.8
		ci.draw_circle(Vector2(qx, qy), s, Color(ec.r, ec.g, ec.b, a * 0.8))


## 납작한 타원 하나를 선분으로 그린다. `draw_arc` 는 정원만 그리므로 직접 잇는다.
func _ellipse(ci: CanvasItem, c: Vector2, rw: float, rh: float, col: Color,
		w: float = 2.0) -> void:
	var pts := PackedVector2Array()
	for i in range(19):
		var a: float = TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * rw, sin(a) * rh))
	ci.draw_polyline(pts, col, w, true)


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
			"spark", "shard", "chunk":
				it["v"] = Vector2(it["v"]) + Vector2(0, float(it.get("g", 0.0))) * dt
				it["p"] = Vector2(it["p"]) + Vector2(it["v"]) * dt
				if it["t"] != "spark":
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
const BACK := ["rays", "ring"]


func draw_back(ci: CanvasItem) -> void:
	_paint(ci, true)


func draw(ci: CanvasItem) -> void:
	_paint(ci, false)


func _paint(ci: CanvasItem, back: bool) -> void:
	for it in items:
		# ★ layer 는 항목마다 정할 수 있다(bk). 적어 두지 않으면 표(BACK) 그대로다 —
		#   확정 연출·결과·테마 판이 그 표에 기대고 있어서(빛살이 족보 이름을 덮으면 안 된다)
		#   기본값이 한 톨이라도 달라지면 안 된다(CLAUDE.md 8).
		var bk: bool = bool(it.get("bk", String(it["t"]) in BACK))
		if bk != back:
			continue
		var k: float = clampf(float(it["life"]) / max(0.001, float(it["max"])), 0.0, 1.0)
		var col: Color = it["c"]
		match String(it["t"]):
			"weak":
				var p: Vector2 = it["p"]
				var progress := 1.0 - k
				var radius := float(it["r"]) * (1.0 - pow(k, 3))
				if radius > 1:
					ci.draw_arc(p, radius, 0, TAU, 24, Color(col, k * 0.8), 2.0 + k * 4, false)
					ci.draw_arc(p, radius * 0.67, 0, TAU, 20, Color(col.lightened(0.7), k), 1.0 + k * 3, false)
				for ray in range(8):
					var angle := float(it["phase"]) + ray * TAU / 8
					var dir := Vector2.from_angle(angle)
					ci.draw_line(p + dir * radius * 0.35, p + dir * (radius + 14 * k), Color(col.lightened(0.6), k), 1 + 3 * k, false)
					var spark := p + dir * float(it["r"]) * (0.3 + progress)
					ci.draw_rect(Rect2(spark.round(), Vector2.ONE * (2 + 3 * k)), Color(col, k))
				if progress < 0.22:
					ci.draw_circle(p, 12 * (1 - progress / 0.22), Color(1, 1, 1, k * 0.9))
			"rarity":
				_paint_rarity(ci, it, k)
			"clip_beam":
				var animation: Dictionary = it["clip"]
				var frame := Anim.frame_at(animation, (1.0 - k) * float(animation["total"]) / 1000.0)
				var a: Vector2 = it["a"]
				var b: Vector2 = it["b"]
				var direction := (b - a).normalized()
				var side := Vector2(-direction.y, direction.x) * float(it.get("width", 24.0))
				var left := float(frame) / float(animation["n"])
				var right := float(frame + 1) / float(animation["n"])
				ci.draw_polygon(PackedVector2Array([a - side, b - side, b + side, a + side]),
						PackedColorArray([Color(1, 1, 1, minf(1.0, k * 3.0))]),
						PackedVector2Array([Vector2(left, 0), Vector2(right, 0),
						Vector2(right, 1), Vector2(left, 1)]), animation["tex"])
			"clip":
				var animation: Dictionary = it["clip"]
				var elapsed: float = float(it["max"]) - float(it["life"])
				var frame := Anim.frame_at(animation, elapsed)
				var cell := Vector2(float(animation["w"]), float(animation["h"]))
				ci.draw_texture_rect_region(animation["tex"], AreaFx.sprite_rect(it["p"], float(it["r"])), Rect2(Vector2(frame * cell.x, 0), cell))
			"rise":
				_paint_rise(ci, it, k)
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
				# ★ 태어나는 순간 부풀었다가 제 크기로 내려앉는다(pop). 그 0.1초가
				#   "탁 꽂혔다"를 만든다 — 없으면 숫자가 그냥 흘러갈 뿐이다.
				var age: float = 1.0 - k
				var pk: float = float(it.get("pop", 0.0))
				var grow := 1.0
				if pk > 0.0:
					grow = 1.0 + pk * 0.62 * pow(1.0 - minf(1.0, age / 0.16), 2.0)
				var tsz: int = maxi(8, int(float(it["sz"]) * grow))
				# 끝의 3분의 1에서만 옅어진다. 처음부터 옅어지면 제일 세게 보여야 할
				# 순간이 제일 흐리다.
				var ta: float = clampf(k / 0.34, 0.0, 1.0)
				if bool(it.get("edge", false)):
					Look.text_center_out(ci, it["p"], String(it["s"]), tsz,
							Color(col.r, col.g, col.b, ta),
							Color(0.03, 0.02, 0.06, ta * 0.9), maxf(2.0, float(tsz) * 0.09))
				else:
					Look.text_center(ci, it["p"], String(it["s"]), tsz,
							Color(col.r, col.g, col.b, ta))
			"chunk":
				var cs: float = float(it["s"]) * (0.5 + k * 0.5)
				if cs < 0.7:
					continue
				var cr: float = float(it["rot"])
				var cp: Vector2 = it["p"]
				var cpts := PackedVector2Array()
				for j in range(4):
					var ca: float = cr + TAU * float(j) / 4.0 + PI * 0.25
					cpts.append(cp + Vector2(cos(ca), sin(ca)) * cs)
				ci.draw_colored_polygon(cpts, Color(col.r, col.g, col.b, minf(1.0, k * 1.4)))
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
				if bool(it.get("core", true)):
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
func _paint_rarity(ci: CanvasItem, it: Dictionary, k: float) -> void:
	if k < 0.015:
		return
	var tier: int = int(it["tier"])
	var p: Vector2 = it["p"]
	var col: Color = it["c"]
	var progress := 1.0 - k
	var r: float = float(it["r"]) * (0.35 + 0.65 * sqrt(progress))
	var rays := 4 + tier
	for i in range(rays):
		var angle: float = float(it["phase"]) + float(i) * TAU / float(rays)
		var d := Vector2.from_angle(angle)
		ci.draw_line(p + d * r * 0.5, p + d * r, Color(col.lightened(0.25), k * 0.85),
				(1.5 + float(tier) * 0.15) * k, true)
	if tier >= 4:
		ci.draw_arc(p, r * 0.8, progress * 2.0, progress * 2.0 + TAU * 0.8,
				24, Color(col, k * 0.72), 2.2 * k, true)
	if tier >= 6:
		ci.draw_arc(p, r * 1.05, -progress * 2.0, -progress * 2.0 + TAU * 0.7,
				28, Color(col.lightened(0.5), k * 0.65), 2.0 * k, true)
	if tier >= 8:
		var core := maxf(0.0, 1.0 - progress * 3.5)
		ci.draw_line(p - Vector2(r, 0), p + Vector2(r, 0), Color(col.lightened(0.8), core), 3.0, true)
		ci.draw_line(p - Vector2(0, r * 0.7), p + Vector2(0, r * 0.7), Color(col.lightened(0.8), core), 3.0, true)


func draw_flash(ci: CanvasItem, screen: Rect2) -> void:
	if flash_t <= 0.0:
		return
	var k: float = flash_t / max(0.001, flash_max)
	ci.draw_rect(screen, Color(flash_color.r, flash_color.g, flash_color.b,
			flash_color.a * k))
