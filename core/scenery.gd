extends RefCounted
class_name Scenery

## 테마 배경. **그림 파일 없이 코드로 그린다.**
##
## 사용자가 정한 것: 「테마별 배경 좀 바뀌게」. 예전에는 투기장 그림 한 장에 테마 색을
## 곱하기만 해서(지금은 없앤 battle_screen._tint), 쉰 곳이 전부 「색만 다른 같은 곳」이었다.
##
## ★ 왜 그림을 안 뽑는가: 테마가 쉰 개이고 한 곳에 배경·바닥 두 장이면 백 장이다.
##   이 머신의 GPU 로 두 시간이고, 테마 표를 한 줄 고칠 때마다 다시 두 시간이다.
##   대신 **몸 다섯 가지의 결**을 코드로 그린다 — 물은 수평선과 물결, 불은 화산 실루엣과
##   올라가는 불티, 나무는 우거진 윤곽과 떨어지는 잎, 바위는 각진 봉우리와 먼지,
##   얼음은 눈 덮인 산과 내리는 눈. 같은 몸 안에서도 테마의 색(bg·floor)이 다르므로
##   쉰 곳이 저마다 다르게 보인다.
## ★ 진짜 그림이 생기면(`art_bg`) 그쪽이 먼저다. 나중에 몇 곳만 뽑아도 코드는 그대로다.
##   (`python3 tools/gen_art.py --kind theme --only 화산`)
## ★ **띠(밴딩)로 그린다.** 매끈한 그라디언트는 도트 화면에서 저 혼자 매끈해 보인다.
##   스물넉 줄로 끊어 칠하면 그것 자체가 도트의 결이 된다.

const BANDS := 24


## 그 테마의 하늘 색 두 개 [위, 아래]. 테마의 bg 색을 밑동으로 삼고 몸에 따라 결을 준다.
static func sky(theme: Dictionary) -> Array:
	var base := Color(String(theme.get("bg", "#141422")))
	var body := String(theme.get("main_body", "rock"))
	# 위는 어둡고 아래는 밝다(지평선 쪽에 빛이 남는다). 몸마다 그 빛의 색이 다르다.
	var glow := Color(0.5, 0.5, 0.6)
	match body:
		"aqua":
			glow = Color(0.22, 0.52, 0.72)
		"flame":
			glow = Color(0.78, 0.32, 0.12)
		"wood":
			glow = Color(0.34, 0.56, 0.26)
		"rock":
			glow = Color(0.62, 0.50, 0.32)
		"frost":
			glow = Color(0.56, 0.72, 0.88)
	# ★ 아래쪽(지평선 쪽)을 넉넉히 밝게 잡는다. 0.45 로 두었더니 테마 색이 원래 어두워서
	#   (그곳의 색이니까) 하늘도 능선도 통째로 진흙빛 한 덩이가 됐다 — 사진에서 능선이
	#   있는지조차 안 보였다. 실루엣은 **밝은 하늘 위에서만** 실루엣으로 읽힌다.
	return [base.darkened(0.22), base.lerp(glow, 0.62)]


## 지평선의 높이(칸 안의 비율).
static func horizon(theme: Dictionary) -> float:
	match String(theme.get("main_body", "rock")):
		"aqua":
			return 0.52
		"flame":
			return 0.58
		"wood":
			return 0.50
		"frost":
			return 0.55
	return 0.56


## 테마 id 로 정해지는 씨앗. **같은 곳은 언제 와도 같은 모양이어야 한다** —
## 매번 굴리면 산의 능선이 프레임마다 춤춘다.
static func seed_of(theme: Dictionary) -> float:
	var s := String(theme.get("id", "x"))
	var acc := 0.0
	for i in range(s.length()):
		acc += float(s.unicode_at(i)) * float(i + 3)
	return fmod(acc, 1000.0)


## 씨앗 하나에서 0~1 사이 값 하나. 난수 객체를 만들지 않으려고 손으로 짠다 —
## 배경 한 장에 수백 번 부르는 자리라 객체를 만들면 그것만으로 프레임이 떨어진다.
static func rnd(seed_value: float, i: float) -> float:
	var v: float = sin(seed_value * 0.017 + i * 12.9898) * 43758.5453
	return v - floor(v)


## 배경 한 장. rect 를 통째로 채운다.
static func draw_backdrop(ci: CanvasItem, theme: Dictionary, rect: Rect2,
		t: float) -> void:
	if theme.is_empty():
		ci.draw_rect(rect, Look.BG)
		return
	# 진짜 그림이 있으면 그쪽이 먼저다.
	if Art.draw_fill(ci, String(theme.get("art_bg", "")), rect):
		return
	var cols := sky(theme)
	var top: Color = cols[0]
	var bot: Color = cols[1]
	var hz: float = rect.position.y + rect.size.y * horizon(theme)
	var bh: float = rect.size.y / float(BANDS)
	for i in range(BANDS):
		var y: float = rect.position.y + bh * float(i)
		var k: float = float(i) / float(BANDS - 1)
		# 지평선 아래는 땅이다 — 한 번 더 어둡게 눌러서 하늘과 갈라 놓는다.
		var c: Color = top.lerp(bot, pow(k, 0.75))
		if y > hz:
			c = c.darkened(0.34)
		ci.draw_rect(Rect2(rect.position.x, y, rect.size.x, bh + 1.0), c)
	var sd := seed_of(theme)
	var body := String(theme.get("main_body", "rock"))
	_stars(ci, rect, hz, sd, body)
	_ridge(ci, rect, hz, sd, body, bot)
	_ground(ci, rect, hz, sd, body, bot, t)


## 하늘의 점 — 별·불티·홀씨. 몸마다 뜻이 다르지만 그리는 값은 같다.
static func _stars(ci: CanvasItem, rect: Rect2, hz: float, sd: float,
		body: String) -> void:
	var col := Color(1, 1, 1, 0.30)
	var n := 40
	match body:
		"flame":
			col = Color(1.0, 0.62, 0.22, 0.35)
		"wood":
			col = Color(0.72, 1.0, 0.62, 0.22)
		"aqua":
			col = Color(0.62, 0.88, 1.0, 0.24)
			n = 24
		"rock":
			col = Color(1.0, 0.92, 0.74, 0.18)
			n = 20
	for i in range(n):
		var x: float = rect.position.x + rnd(sd, float(i) * 1.7) * rect.size.x
		var y: float = rect.position.y + rnd(sd, float(i) * 3.1 + 5.0) * (hz - rect.position.y)
		var s: float = 2.0 + rnd(sd, float(i) * 7.3) * 2.0
		ci.draw_rect(Rect2(floor(x), floor(y), s, s), col)


## 먼 능선. 몸마다 실루엣이 다르다 — 이 한 줄이 「어디인가」를 말한다.
static func _ridge(ci: CanvasItem, rect: Rect2, hz: float, sd: float, body: String,
		tone: Color) -> void:
	# 먼 능선은 하늘에 살짝 잠기고(0.55), 가까운 능선은 더 짙다(0.74).
	var far := tone.darkened(0.55)
	var near := tone.darkened(0.74)
	match body:
		"aqua":
			# 물 — 능선 대신 **수평선과 물결 줄** 몇 개.
			ci.draw_rect(Rect2(rect.position.x, floor(hz) - 3.0, rect.size.x, 3.0),
					tone.lightened(0.25))
			for i in range(7):
				var y: float = hz + 10.0 + float(i) * 13.0
				if y > rect.position.y + rect.size.y:
					break
				var w: float = rect.size.x * (0.3 + rnd(sd, float(i) * 2.3) * 0.5)
				var x: float = rect.position.x + rnd(sd, float(i) * 5.1) * (rect.size.x - w)
				ci.draw_rect(Rect2(floor(x), floor(y), w, 3.0),
						Color(1, 1, 1, 0.10 - 0.01 * float(i)))
		"wood":
			# 나무 — 둥글게 뭉친 우듬지 여럿.
			for layer in range(2):
				var c: Color = far if layer == 0 else near
				var yb: float = hz + float(layer) * 26.0
				var n := 14 + layer * 4
				for i in range(n):
					var x2: float = rect.position.x + (float(i) + 0.5) / float(n) * rect.size.x
					var r: float = 34.0 + rnd(sd, float(i + layer * 40) * 1.9) * 42.0
					ci.draw_circle(Vector2(floor(x2), floor(yb - r * 0.35)), r, c)
					ci.draw_rect(Rect2(floor(x2 - r * 0.10), floor(yb - r * 0.4),
							r * 0.20, r * 0.6), c)
		_:
			# 불·바위·얼음 — 각진 봉우리. 얼음만 꼭대기에 흰 눈을 얹는다.
			for layer in range(2):
				var c2: Color = far if layer == 0 else near
				var yb2: float = hz + 6.0 + float(layer) * 30.0
				var n2 := 6 + layer * 3
				var pts := PackedVector2Array()
				pts.append(Vector2(rect.position.x, rect.position.y + rect.size.y))
				for i in range(n2 + 1):
					var x3: float = rect.position.x + float(i) / float(n2) * rect.size.x
					var h: float = (48.0 + rnd(sd, float(i + layer * 30) * 3.7) * 96.0) \
							* (1.0 - 0.35 * float(layer))
					pts.append(Vector2(floor(x3), floor(yb2 - h)))
				pts.append(Vector2(rect.position.x + rect.size.x,
						rect.position.y + rect.size.y))
				ci.draw_colored_polygon(pts, c2)
				if body == "frost" and layer == 0:
					for i in range(n2 + 1):
						var p: Vector2 = pts[i + 1]
						ci.draw_colored_polygon(PackedVector2Array([
							p, p + Vector2(11.0, 18.0), p + Vector2(-11.0, 18.0)]),
							Color(0.88, 0.94, 1.0, 0.85))
				if body == "flame" and layer == 0:
					# 화산 꼭대기의 붉은 빛.
					for i in range(n2 + 1):
						var p2: Vector2 = pts[i + 1]
						ci.draw_circle(p2, 7.0, Color(1.0, 0.42, 0.10, 0.55))


## 지평선 아래 — 땅의 결. 물이면 반짝임, 바위면 자갈, 얼음이면 눈밭.
static func _ground(ci: CanvasItem, rect: Rect2, hz: float, sd: float, body: String,
		tone: Color, t: float) -> void:
	var y0: float = hz + 30.0
	var h: float = rect.position.y + rect.size.y - y0
	if h <= 0.0:
		return
	match body:
		"rock", "flame":
			for i in range(70):
				var x: float = rect.position.x + rnd(sd, float(i) * 1.3) * rect.size.x
				var y: float = y0 + rnd(sd, float(i) * 2.9 + 11.0) * h
				var s: float = 3.0 + rnd(sd, float(i) * 4.1) * 5.0
				ci.draw_rect(Rect2(floor(x), floor(y), s, s * 0.6),
						tone.darkened(0.5) if i % 2 == 0 else tone.lightened(0.06))
		"frost":
			for i in range(40):
				var x2: float = rect.position.x + rnd(sd, float(i) * 1.9) * rect.size.x
				var y2: float = y0 + rnd(sd, float(i) * 3.3 + 7.0) * h
				var w: float = 20.0 + rnd(sd, float(i) * 5.7) * 60.0
				ci.draw_rect(Rect2(floor(x2), floor(y2), w, 4.0), Color(1, 1, 1, 0.10))
		"aqua":
			for i in range(26):
				var x3: float = rect.position.x + rnd(sd, float(i) * 2.7) * rect.size.x
				var y3: float = y0 + rnd(sd, float(i) * 4.3 + 3.0) * h
				var w2: float = 16.0 + rnd(sd, float(i) * 6.1) * 40.0
				var a: float = 0.06 + 0.05 * sin(t * 1.4 + float(i))
				ci.draw_rect(Rect2(floor(x3), floor(y3), w2, 3.0), Color(1, 1, 1, a))
		_:
			for i in range(30):
				var x4: float = rect.position.x + rnd(sd, float(i) * 3.1) * rect.size.x
				var y4: float = y0 + rnd(sd, float(i) * 2.1 + 13.0) * h
				ci.draw_rect(Rect2(floor(x4), floor(y4), 5.0, 3.0), tone.darkened(0.45))


## 날씨 — 눈·비·불티·잎·먼지. **상태를 안 들고 있다**: 자리를 시간과 번호로 바로 셈한다.
##
## ★ 왜 파티클 배열을 안 쓰는가: 배경 날씨는 전투 내내 백 개가 떠 있어야 하는데,
##   그것을 Fx 에 넣으면 이펙트 배열이 늘 백 개로 차 있어서 실제 타격 이펙트가
##   묻힌다. 시간으로 바로 셈하면 배열이 아예 없고 프레임도 안 먹는다.
static func draw_weather(ci: CanvasItem, theme: Dictionary, rect: Rect2, t: float,
		n: int = 70) -> void:
	if theme.is_empty():
		return
	var body := String(theme.get("main_body", "rock"))
	var sd := seed_of(theme)
	match body:
		"frost":
			for i in range(n):
				var sp: float = 26.0 + rnd(sd, float(i) * 1.1) * 40.0
				var x: float = rect.position.x + rnd(sd, float(i) * 2.3) * rect.size.x \
						+ sin(t * 0.7 + float(i)) * 14.0
				var y: float = rect.position.y + fposmod(rnd(sd, float(i) * 3.7)
						* rect.size.y + t * sp, rect.size.y)
				var s: float = 2.0 + rnd(sd, float(i) * 5.3) * 3.0
				ci.draw_rect(Rect2(floor(x), floor(y), s, s), Color(1, 1, 1, 0.55))
		"flame":
			for i in range(n):
				var sp2: float = 40.0 + rnd(sd, float(i) * 1.7) * 60.0
				var x2: float = rect.position.x + rnd(sd, float(i) * 2.9) * rect.size.x \
						+ sin(t * 1.6 + float(i) * 2.0) * 10.0
				var y2: float = rect.position.y + rect.size.y - fposmod(
						rnd(sd, float(i) * 4.1) * rect.size.y + t * sp2, rect.size.y)
				var s2: float = 2.0 + rnd(sd, float(i) * 6.7) * 3.0
				ci.draw_rect(Rect2(floor(x2), floor(y2), s2, s2),
						Color(1.0, 0.55 + 0.3 * rnd(sd, float(i)), 0.18, 0.7))
		"aqua":
			for i in range(n):
				var sp3: float = 240.0 + rnd(sd, float(i) * 1.3) * 160.0
				var x3: float = rect.position.x + rnd(sd, float(i) * 2.1) * rect.size.x
				var y3: float = rect.position.y + fposmod(rnd(sd, float(i) * 3.3)
						* rect.size.y + t * sp3, rect.size.y)
				ci.draw_rect(Rect2(floor(x3), floor(y3), 2.0, 11.0),
						Color(0.66, 0.86, 1.0, 0.30))
		"wood":
			for i in range(n / 2):
				var sp4: float = 22.0 + rnd(sd, float(i) * 1.9) * 26.0
				var x4: float = rect.position.x + rnd(sd, float(i) * 2.7) * rect.size.x \
						+ sin(t * 0.9 + float(i) * 1.3) * 26.0
				var y4: float = rect.position.y + fposmod(rnd(sd, float(i) * 4.7)
						* rect.size.y + t * sp4, rect.size.y)
				ci.draw_rect(Rect2(floor(x4), floor(y4), 5.0, 3.0),
						Color(0.62, 0.88, 0.40, 0.45))
		_:
			for i in range(n / 2):
				var sp5: float = 14.0 + rnd(sd, float(i) * 1.5) * 22.0
				var x5: float = rect.position.x + fposmod(rnd(sd, float(i) * 2.5)
						* rect.size.x + t * sp5, rect.size.x)
				var y5: float = rect.position.y + rnd(sd, float(i) * 3.9) * rect.size.y
				ci.draw_rect(Rect2(floor(x5), floor(y5), 3.0, 2.0),
						Color(0.85, 0.78, 0.62, 0.22))
