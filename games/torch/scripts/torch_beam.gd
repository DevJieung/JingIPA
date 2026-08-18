class_name TorchBeam
extends Node2D

## 어둠과 손전등. 화면 전체를 덮되 빛 웅덩이만 뚫려 있다.
##
## ★ 셰이더도 Light2D 도 CanvasModulate 도 쓰지 않는다. 그리기 명령만으로 만든다.
##   (1) 이 앱은 gl_compatibility 로 도는 옛 기기까지 받는다.
##   (2) **CanvasLayer 를 새로 만들면 안 된다** — 그 순간 프로젝트 폰트가 조용히
##       시스템 fallback 으로 넘어간다 (CLAUDE.md 규칙 18). 그래서 이건 world 안의
##       평범한 Node2D 이고, 공룡(10)보다 위·찾은 공룡(60)보다 아래인 z_index 50 이다.
##   (3) 무엇보다 — **"여기는 밝다"를 판정하는 함수와 그리는 코드가 같은 숫자를 본다.**
##       빛이 셰이더 안에 있으면 판정은 반드시 두 벌이 되고 언젠가 어긋난다.
##       (공룡 찾기에서 Rooms.band() 를 생성기와 검사기가 같이 보는 것과 같은 이유다.)
##
## ★ 어둠은 절대 완전한 검정이 아니고, 색이 있는 짙은 남보라다. 검정은 "없음"이지만
##   남보라는 "밤"이다 — 이 나이대에게 그 둘은 전혀 다른 것이다. 가구 실루엣이 희미하게
##   남아 있어야 "깜깜한 방"이지 "아무것도 없는 화면"이 아니다.
##
## ★ 어둠은 **놀이 중에 절대 스스로 짙어지지 않는다.** 방이 열릴 때 한 번 해가 지고,
##   그 뒤로는 내려가기만 한다(힌트가 거듭될수록 · 다 찾으면 0으로). 짙어지는 연출은
##   재촉이자 위협이다.
##
## ★ 반투명 조각을 겹쳐 칠하면 겹친 자리만 두 번 어두워져 이음매가 보인다.
##   그래서 어둠은 **겹치지 않게 타일링**한다: 빛 원 밖은
##     (a) 빛을 감싸는 정사각형 바깥의 네모 4장
##     (b) 원과 그 정사각형 사이를 채우는 부채꼴 조각들
##   로 정확히 나뉜다. 조각 수를 8의 배수로 두면 정사각형 모서리 각(45도)이
##   조각 경계와 딱 맞아 틈도 겹침도 생기지 않는다.

const W := 1280.0
const H := 720.0

## 기준 화면 밖으로도 이만큼 더 덮는다. 실제 앱에서는 뷰포트가 keep 이라 필요 없지만,
## 촬영·다른 종횡비에서 화면 가장자리에 밝은 띠가 남지 않는다.
const EX := 400.0

## 부채꼴 조각 수. **반드시 8의 배수**여야 한다 (위 주석의 이유).
const SEG := 40

## 이 비율 안쪽은 100% 밝다. 여기서부터 반경까지 어둠으로 녹아든다.
const CORE := 0.60

## "밝다"고 판정하는 반경 비율. 그림과 판정이 **같은 숫자**를 보게 여기 한 곳에 둔다.
## 0.90 — 눈에 또렷하게 밝은 데까지만 인정한다. 가장자리에 겨우 걸친 공룡이
## 우연히 눌려서 찾아지면, 아이가 배우는 규칙이 "비춰 보고 누른다"가 아니게 된다.
const HIT := 0.90

## 밤의 색. 검정이 아니라 짙은 남보라 — 달빛 아래 방의 색이다.
const NIGHT := Color(0.085, 0.078, 0.185)
## 손전등의 색 (따뜻하다)
const WARM := Color(1.0, 0.94, 0.74)
## 창으로 드는 달빛 (차갑다). 손전등과 색이 갈려야 둘이 따로 읽힌다.
const MOON := Color(0.74, 0.83, 1.0)

var on := false
var pos := Vector2(W * 0.5, H * 0.56)
var radius := 300.0
var dark := 0.0            ## 지금 실제로 깔린 어둠 (해가 지는 동안 0 -> dark_full)
var dark_full := 0.86      ## 이 방의 목표 어둠
## 아직 안 켰을 때 "여기를 눌러 보세요" 하고 숨 쉬는 자리
var suggest := Vector2(W * 0.5, H * 0.56)
## 창으로 드는 달빛. 절대 꺼지지도 움직이지도 않는다 — 방에 **항상 안전한 구석**이 있다.
var moon := Vector2(W * 0.5, 300.0)
var moon_r := 220.0

## 어둠을 움직이는 트윈은 **한 번에 하나뿐**이다. 해질녘과 불켜기가 겹치면
## 두 트윈이 같은 값을 서로 밀어서 깜빡인다.
var _dark_tw: Tween
var _fade := 0.0       ## 0 = 손전등 꺼짐, 1 = 켜짐 (부드럽게 오간다)
var _pop := 0.0        ## 막 켜졌을 때의 반짝임
var _t := 0.0
var _glows: Array = [] ## 남아 있는 빛 [{pos, r, a, t}] — 찾은 공룡 자리 · 힌트 잔광
var _tw: Array = []    ## 힌트 반짝임 [{pos, t}]


func _ready() -> void:
	z_index = 50


## 방을 새로 열 때. 어둠 0(=밝은 방)에서 시작하고, 손전등은 꺼져 있다.
func setup(p_radius: float, p_dark: float, p_suggest: Vector2, p_moon: Vector2) -> void:
	radius = maxf(TorchGen.BEAM_ABS_MIN, p_radius)
	if _dark_tw != null and _dark_tw.is_valid():
		_dark_tw.kill()
	dark = 0.0
	dark_full = clampf(p_dark, 0.0, TorchGen.DARK_CEIL)
	suggest = p_suggest
	pos = p_suggest
	moon = p_moon
	on = false
	_fade = 0.0
	_pop = 0.0
	_glows.clear()
	_tw.clear()
	queue_redraw()


## 해가 진다. 급전환 금지 — 어두워지는 것을 아이가 보고 있어야 무섭지 않다.
func dusk(secs := 0.9) -> Tween:
	return _tween_dark(dark_full, secs)


## 손전등을 여기로. 이 게임의 유일한 조작이다.
func aim(p: Vector2) -> void:
	pos = p
	on = true
	_pop = 1.0
	queue_redraw()


## 이 자리가 지금 밝은가. **찾기 판정이 이 함수 하나만 본다.**
func lit(p: Vector2) -> bool:
	return on and pos.distance_squared_to(p) <= pow(radius * HIT, 2.0)


## 남는 빛 — 찾은 공룡 자리, 그리고 힌트가 거듭될 때의 잔광.
## 방은 놀수록 밝아진다. 이게 이 게임의 감정 곡선이다.
func add_glow(p: Vector2, r := 130.0, a := 0.055) -> void:
	_glows.append({"pos": p, "r": r, "a": a, "t": 0.0})


## 힌트. 어둠 **위**에 그려지므로 손전등을 어디에 두고 있든 보인다.
func twinkle(p: Vector2) -> void:
	_tw.append({"pos": p, "t": 0.0})


## 힌트가 거듭되면 방이 조금 밝아진다. **내려가기만 한다.**
func ease_dark(amount: float, floor_a := 0.55) -> void:
	dark_full = maxf(floor_a, dark_full - amount)
	dark = minf(dark, dark_full)


## 다 찾았다 — 방에 불이 켜진다. 이게 이 게임의 보상이다(놀이의 연장).
func reveal(secs := 0.8) -> Tween:
	dark_full = 0.0
	return _tween_dark(0.0, secs)


func _tween_dark(to: float, secs: float) -> Tween:
	if _dark_tw != null and _dark_tw.is_valid():
		_dark_tw.kill()
	_dark_tw = create_tween()
	_dark_tw.tween_property(self, "dark", to, maxf(0.02, secs))
	return _dark_tw


func _process(delta: float) -> void:
	_t += delta
	var want := 1.0 if on else 0.0
	if _fade != want:
		_fade = move_toward(_fade, want, delta / 0.22)
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta * 2.2)
	for g in _glows:
		g["t"] = float(g["t"]) + delta
	for k in _tw:
		k["t"] = float(k["t"]) + delta
	_tw = _tw.filter(func(k): return float(k["t"]) < 2.4)
	queue_redraw()


func _draw() -> void:
	_paint(self)


func _paint(ci: Object) -> void:
	if dark <= 0.003:
		# 밝은 방 — 어둠이 아예 없다 (방을 처음 보여 줄 때와 다 찾은 뒤)
		_paint_glows(ci)
		_paint_twinkles(ci)
		return
	# 아직 안 켠 만큼은 화면 전체가 균일하게 어둡다.
	var a_in: float = dark * (1.0 - _fade)
	if a_in > 0.003:
		ci.draw_rect(Rect2(-EX, -EX, W + EX * 2.0, H + EX * 2.0),
				Color(NIGHT.r, NIGHT.g, NIGHT.b, a_in))
	if _fade > 0.003:
		# 빛 밖에 **덧칠할** 알파. 위의 a_in 에 이걸 겹치면 정확히 dark 가 된다.
		#   1 - dark = (1 - a_in) * (1 - b)
		# 이 식이 없으면 켜지는 동안 빛 밖이 두 번 어두워져 계단처럼 보인다.
		var b: float = 1.0 - (1.0 - dark) / maxf(0.05, 1.0 - a_in)
		_paint_dark(ci, clampf(b, 0.0, 1.0))
		_paint_pool(ci)
	_paint_moon(ci)
	_paint_glows(ci)
	_paint_twinkles(ci)
	if not on:
		_paint_suggest(ci)


## 빛 원 바깥의 어둠. 겹치지 않게 정확히 타일링한다.
func _paint_dark(ci: Object, b: float) -> void:
	var col := Color(NIGHT.r, NIGHT.g, NIGHT.b, b)
	var clear := Color(NIGHT.r, NIGHT.g, NIGHT.b, 0.0)
	var s := radius                        # 빛을 감싸는 정사각형의 반쪽
	var lo := Vector2(-EX, -EX)
	var hi := Vector2(W + EX, H + EX)
	var x0 := clampf(pos.x - s, lo.x, hi.x)
	var x1 := clampf(pos.x + s, lo.x, hi.x)
	var y0 := clampf(pos.y - s, lo.y, hi.y)
	var y1 := clampf(pos.y + s, lo.y, hi.y)
	# (a) 정사각형 바깥 — 네모 4장으로 화면 나머지를 덮는다
	if y0 > lo.y:
		ci.draw_rect(Rect2(lo.x, lo.y, hi.x - lo.x, y0 - lo.y), col)
	if y1 < hi.y:
		ci.draw_rect(Rect2(lo.x, y1, hi.x - lo.x, hi.y - y1), col)
	if x0 > lo.x and y1 > y0:
		ci.draw_rect(Rect2(lo.x, y0, x0 - lo.x, y1 - y0), col)
	if x1 < hi.x and y1 > y0:
		ci.draw_rect(Rect2(x1, y0, hi.x - x1, y1 - y0), col)
	# (b) 원과 정사각형 사이 + 부드러운 가장자리
	var inner := radius * CORE
	for i in SEG:
		var d0 := _dir(i)
		var d1 := _dir(i + 1)
		var e0 := pos + d0 * radius
		var e1 := pos + d1 * radius
		ci.draw_polygon(
				PackedVector2Array([e0, e1, pos + d1 * _to_square(d1, s), pos + d0 * _to_square(d0, s)]),
				PackedColorArray([col, col, col, col]))
		ci.draw_polygon(
				PackedVector2Array([pos + d0 * inner, pos + d1 * inner, e1, e0]),
				PackedColorArray([clear, clear, col, col]))


func _dir(i: int) -> Vector2:
	var a := TAU * float(i % SEG) / float(SEG)
	return Vector2(cos(a), sin(a))


## 이 방향으로, 반쪽이 s 인 정사각형 테두리까지의 거리
func _to_square(d: Vector2, s: float) -> float:
	return s / maxf(absf(d.x), absf(d.y))


## 부드러운 원형 빛. **동심원을 겹쳐 그리면 안 된다** — 겹친 만큼 알파가 쌓여
## 눈에 보이는 띠(밴딩)가 생긴다. 가운데에서 가장자리로 정점 색을 보간하는
## 삼각형 부채로 그리면 한 겹으로 매끄럽게 나온다.
func _radial(ci: Object, c: Vector2, r: float, col: Color, seg := 20) -> void:
	if r <= 1.0 or col.a <= 0.002:
		return
	var edge := Color(col.r, col.g, col.b, 0.0)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		ci.draw_polygon(
				PackedVector2Array([c,
						c + Vector2(cos(a0), sin(a0)) * r,
						c + Vector2(cos(a1), sin(a1)) * r]),
				PackedColorArray([col, edge, edge]))


## 빛 웅덩이 — 그냥 뚫린 구멍이 아니라 따뜻한 불빛으로 보이게
func _paint_pool(ci: Object) -> void:
	var k := _fade * (1.0 + 0.55 * _pop)
	_radial(ci, pos, radius * 0.98, Color(WARM.r, WARM.g, WARM.b, 0.13 * k), SEG)
	ci.draw_arc(pos, radius * 0.985, 0.0, TAU, SEG,
			Color(WARM.r, WARM.g, WARM.b, 0.10 * _fade), 3.0)


## 창으로 드는 달빛. 꺼지지 않고 움직이지 않는다 — 손전등이 어디 있든 돌아갈 곳이 있다.
## 이 게임에서 가장 중요한 한 조각이다.
func _paint_moon(ci: Object) -> void:
	var k: float = clampf(dark / maxf(0.05, dark_full), 0.0, 1.0)
	_radial(ci, moon, moon_r, Color(MOON.r, MOON.g, MOON.b, 0.20 * k))


## 남아 있는 빛. 찾은 공룡 자리마다 하나씩 늘어난다.
func _paint_glows(ci: Object) -> void:
	for g in _glows:
		var grow: float = clampf(float(g["t"]) * 3.0, 0.0, 1.0)
		var r: float = float(g["r"]) * (0.45 + 0.55 * grow)
		var breathe: float = 0.9 + 0.1 * sin(_t * 1.6 + float(g["r"]))
		if Shell.reduce_motion:
			breathe = 0.95
		_radial(ci, g["pos"], r,
				Color(WARM.r, WARM.g, WARM.b, float(g["a"]) * 3.0 * grow * breathe), 16)


## 힌트 반짝임. 0.7초에 한 번씩 세 번 (스트로브가 되지 않게 주기를 길게).
func _paint_twinkles(ci: Object) -> void:
	for k in _tw:
		var t: float = float(k["t"])
		var a: float = maxf(0.0, sin(t * PI / 0.7)) * clampf(1.0 - t / 2.4, 0.0, 1.0)
		if a <= 0.01:
			continue
		_star(ci, k["pos"], 26.0 + 6.0 * a, Color(WARM.r, WARM.g, WARM.b, a * 0.85))
		_radial(ci, k["pos"], 46.0, Color(WARM.r, WARM.g, WARM.b, a * 0.22), 16)


## 아직 안 켰다 — 여기를 눌러 보라고 숨 쉬는 동그라미. 글자도 화살표도 손가락도 없다.
func _paint_suggest(ci: Object) -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	if Shell.reduce_motion:
		pulse = 0.5
	var r := 54.0 + 12.0 * pulse
	ci.draw_arc(suggest, r, 0.0, TAU, 32,
			Color(WARM.r, WARM.g, WARM.b, 0.20 + 0.22 * pulse), 5.0)
	_radial(ci, suggest, r * 0.9, Color(WARM.r, WARM.g, WARM.b, 0.10 + 0.08 * pulse), 16)


func _star(ci: Object, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0 - PI * 0.5
		var rr: float = r if i % 2 == 0 else r * 0.34
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)
