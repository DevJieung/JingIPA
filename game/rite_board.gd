extends RefCounted
class_name RiteBoard

## 별맞춤 의식판 — 생명 수정 둘레의 다섯 궤도, 그 위의 별, 위로 솟은 「빛의 문」.
## 뽑기 화면 · 전투 중간 지원 · 메뉴 도움말 · 타이틀이 **같은 판**을 크기만 바꿔 그린다.
##
## ★ **여기는 그림뿐이다.** 별이 어디에 섰는가는 Run.orbit 이, 문 안인가는 Rite 가 정한다.
## ★ **문의 폭은 확률 그 자체다**(core/rite.gd 의 ★). 문은 언제나 Rite.gate_half(ring) 으로,
##   별은 Rite.angle(ring, pos) 로 놓는다. 숫자를 여기 적어 두면 밸런스가 문 너비를 바꾼 날
##   「문 안에 섰는데 빗나갔다」가 된다 — 그 순간 이 뽑기는 못 믿을 것이 된다.
## ★ **룰렛처럼 보이면 안 된다**(사용자가 정한 것: 「룰렛과 같지만 룰렛이 아닌, 새롭고
##   신비한」). 색 칸 · 숫자 · 구슬 · 바퀴살을 두지 않는다. 천체 관측의(astrolabe)의 눈금 테와
##   궤도, 수정에서 솟는 빛기둥이 이 판의 말투다.
## ★ **색만으로 말하지 않는다.** 문 안의 별은 꽉 찬 금빛 별에 잠금 고리를 두르고, 문 밖의
##   별은 속이 빈 식은 별이다 — 등급 배지(Look.draw_rarity)의 찬 별 · 빈 별과 같은 모양이라
##   「문 안의 별 = 등급 별」이 그림으로 이어진다.

## 가장 안쪽 궤도의 반지름과 궤도 사이의 간격(판 크기 1.0 기준, px).
const ORBIT_0 := 80.0
const ORBIT_STEP := 38.0
## 가장 바깥 궤도 띠의 끝 = 눈금 테의 안쪽.
const RIM := 252.0
const RIM_W := 10.0
## 테까지 포함한 판의 반지름. 화면이 자리를 잡을 때 쓴다.
const EXTENT := RIM + RIM_W
## 문 꼭대기의 뾰족한 빛 끝이 테 밖으로 솟는 높이.
const SPIRE := 20.0

## 별 한 개의 모습.
##   OUT  문 밖 — 속이 빈 식은 별            IN   문 안 — 금빛 별 + 잠금 고리
##   HELD 수정이 붙든 별 — 금빛 별 + 수정빛 고리   SPIN 도는 중 — 흰 금빛 별(꼬리는 draw_trail)
enum { OUT, IN, HELD, SPIN }

const NIGHT := Color("#0a141d")
const LANE_A := Color("#0f1d29")
const LANE_B := Color("#0b1722")
const ORBIT := Color("#527383")
const BRASS := Look.GOLD_DEEP
const BRASS_DARK := Color("#222b32")
## 문의 테와 별빛 — 흰 금빛. 등급 5성의 색(Look.TIER_COLOR 의 끝)과 같은 결이다.
const LIGHT := Color("#fff0b8")
## 문 안을 채우는 빛 — 수정에서 나오는 찬 흰빛. 금빛으로 채우면 밤빛 판 위에서 탁한 올리브색이
## 되고, 그 위에 선 금빛 별이 묻힌다. 찬 빛 위의 금빛 별은 색이 맞서서 또렷하다.
const BEAM := Color("#d3efff")
## 빛의 면을 나누는 각 격자(라디안). 모든 궤도가 같은 격자를 쓴다(draw_gate 의 ★).
const FILL_STEP := 0.035
## 문 밖의 별. 빈 등급 별(Look.draw_rarity)과 같은 두 색이다.
const COLD := Color("#8b9aa5")
const COLD_FILL := Color("#39454f")


static func orbit_radius(ring: int, sc: float = 1.0) -> float:
	return (ORBIT_0 + ORBIT_STEP * float(ring)) * sc


## 그 궤도가 차지하는 띠의 안쪽 · 바깥쪽 반지름.
static func lane_inner(ring: int, sc: float = 1.0) -> float:
	return (ORBIT_0 + ORBIT_STEP * (float(ring) - 0.5)) * sc


static func lane_outer(ring: int, sc: float = 1.0) -> float:
	return (ORBIT_0 + ORBIT_STEP * (float(ring) + 0.5)) * sc


## 궤도 위의 한 점. `angle` 은 화면 좌표의 각(Rite.angle 이 주는 값)이다.
static func point(center: Vector2, ring: int, angle: float, sc: float = 1.0) -> Vector2:
	return center + Vector2.from_angle(angle) * orbit_radius(ring, sc)


## 궤도 ring 의 pos 번 칸이 화면에 놓이는 자리.
static func slot_point(center: Vector2, ring: int, pos: int, sc: float = 1.0) -> Vector2:
	return point(center, ring, Rite.angle(ring, pos), sc)


## 설명용 별 자리 — 문 안에 `star_count` 개가 선 판 한 장(도움말 · 지원 팝업 · 타이틀).
## 문 안의 별은 그 문의 한가운데에, 문 밖의 별은 문 밖 여기저기에 흩어 세운다.
## ★ 자리를 **Rite 의 문 너비에서** 뽑는다. 문 너비를 다시 잡아도 그림의 별이 문턱에 걸리지 않는다.
static func sample_orbit(star_count: int) -> Array[int]:
	var spread := [0.50, 0.24, 0.62, 0.38, 0.74]
	var orbit: Array[int] = []
	for ring in range(Rite.RINGS):
		var gate := Rite.gate(ring)
		if ring < star_count or Rite.anchored(ring) or gate >= Rite.slots():
			orbit.append(gate / 2)
		else:
			orbit.append(gate + int(float(Rite.slots() - gate) * float(spread[ring % spread.size()])))
	return orbit


## 확률을 화면에 적는 꼴 — 「25%」·「7.5%」. 소수가 있어야 뜻이 달라질 때만 한 자리 붙인다.
static func percent(value: float) -> String:
	var pct := value * 100.0
	if pct >= 9.95 or is_equal_approx(pct, roundf(pct)):
		return "%d%%" % roundi(pct)
	# 5성처럼 아주 드문 것은 자리를 더 준다 — 「0.0%」라고 적으면 없는 일처럼 읽힌다.
	if pct < 0.0095:
		return "%.3f%%" % pct
	if pct < 0.095:
		return "%.2f%%" % pct
	return "%.1f%%" % pct


## 멈춰 선 별의 모습 — 문 안인가, 그리고 수정이 붙든 별인가.
static func look_of(ring: int, pos: int) -> int:
	if not Rite.in_gate(ring, pos):
		return OUT
	return HELD if Rite.anchored(ring) else IN


# --------------------------------------------------------------------------- #
# 판 — 눈금 테 · 궤도 띠 · 먼 별
# --------------------------------------------------------------------------- #
## 판의 바탕. 궤도 띠를 한 칸 건너 한 칸 다른 밤빛으로 깔아 다섯 궤도가 저마다 읽힌다.
## `dome` 이면 **위쪽 절반만** 그린다 — 반원의 관측의. 판 전체를 놓을 자리가 없는 타이틀이 쓴다.
static func draw_base(ci: CanvasItem, c: Vector2, sc: float = 1.0, time: float = 0.0,
		dome: bool = false) -> void:
	var rim := RIM * sc
	_disc(ci, c, rim + (RIM_W + 5.0) * sc, Color(0, 0, 0, 0.42), dome)
	_disc(ci, c, rim + RIM_W * sc, BRASS_DARK, dome)
	_disc(ci, c, rim + (RIM_W - 2.0) * sc, BRASS, dome)
	_disc(ci, c, rim + 2.0 * sc, BRASS_DARK, dome)
	ci.draw_arc(c, rim + (RIM_W - 1.0) * sc, PI * 1.08, PI * 1.92, 80,
			Color(Look.GOLD.lightened(0.22), 0.78), maxf(1.0, 1.7 * sc), true)
	for ring in range(Rite.RINGS - 1, -1, -1):
		_disc(ci, c, lane_outer(ring, sc), LANE_A if ring % 2 == 0 else LANE_B, dome)
	_disc(ci, c, lane_inner(0, sc), NIGHT, dome)
	# 수정의 빛이 안쪽 궤도까지 옅게 번진다 — 판의 한가운데가 살아 있어 보이게.
	_disc(ci, c, lane_outer(1, sc), Color(Look.CRYSTAL, 0.035), dome)
	_disc(ci, c, lane_outer(0, sc), Color(Look.CRYSTAL, 0.045), dome)
	# 눈금 테 — 관측의의 도수 눈금. 색 칸이나 숫자는 두지 않는다(룰렛의 주머니가 된다).
	var ticks := 72 if sc >= 0.6 else 36
	var long_every := ticks / 12
	for i in range(ticks / 2 + 1 if dome else ticks):
		var d := Vector2.from_angle(PI + TAU * float(i) / float(ticks))
		var tall := i % long_every == 0
		ci.draw_line(c + d * (rim + 2.5 * sc), c + d * (rim + (RIM_W - 2.0 if tall else RIM_W * 0.55) * sc),
				Color(BRASS_DARK, 0.9), maxf(1.0, (2.0 if tall else 1.4) * sc))
	# 테의 징 — 왼 · 오른 · 아래. 문 꼭대기(위)는 빛 끝이 차지한다.
	for stud in ([0.0, PI] if dome else [0.0, PI * 0.5, PI]):
		var at := c + Vector2.from_angle(float(stud)) * (rim + RIM_W * 0.5 * sc)
		ci.draw_colored_polygon(_diamond(at, maxf(3.0, 7.0 * sc)), BRASS_DARK)
		ci.draw_colored_polygon(_diamond(at, maxf(2.0, 4.5 * sc)), Look.GOLD)
	# 궤도 — 별이 도는 길. 문의 금빛 문턱이 이 선 위에 얹힌다(draw_gate).
	var points := 80 if sc >= 0.6 else 44
	for ring in range(Rite.RINGS):
		ci.draw_arc(c, orbit_radius(ring, sc), PI, TAU if dome else PI + TAU, points, Color(ORBIT, 0.55),
				maxf(1.0, 1.4 * sc), true)
	if dome:
		# 반원의 밑변 — 관측의가 놓인 황동 받침.
		var half_w := rim + (RIM_W + 8.0) * sc
		ci.draw_rect(Rect2(c.x - half_w, c.y - 2.0 * sc, half_w * 2.0, 9.0 * sc), BRASS_DARK)
		ci.draw_rect(Rect2(c.x - half_w + 2.0, c.y, half_w * 2.0 - 4.0, 4.0 * sc), BRASS)
	if sc < 0.5:
		return
	# 궤도를 따라 흐르는 빛 조각 — 별이 서 있을 때에도 「도는 판」으로 보이게 한다. 궤도마다
	# 도는 쪽이 엇갈린다(별이 돌 때와 같다). 선 위의 짧은 호라서 별과 헷갈리지 않는다.
	for ring in range(Rite.RINGS):
		var turn := (1.0 if ring % 2 == 0 else -1.0) * time * (0.10 + 0.025 * float(ring))
		for piece in range(2):
			var from := turn + PI * float(piece) + float(ring) * 1.3
			if dome and sin(from + 0.09) > -0.1:
				continue
			ci.draw_arc(c, orbit_radius(ring, sc), from, from + 0.18, 6, Color(ORBIT.lightened(0.45), 0.55),
					maxf(1.0, 2.2 * sc), true)
	# 먼 별 — 아주 작고 흐리게. 의식의 별 다섯과 헷갈리면 안 된다.
	for i in range(26):
		var angle := float(i) * 2.39996
		if dome and sin(angle) > -0.12:
			continue
		var radius := lerpf(lane_inner(0, sc) + 6.0, rim - 6.0, fposmod(float(i) * 0.618034, 1.0))
		var twinkle := 0.5 + 0.5 * sin(time * (0.7 + float(i % 5) * 0.21) + float(i) * 1.7)
		var size := 2.0 if i % 4 != 0 else 3.0
		ci.draw_rect(Rect2((c + Vector2.from_angle(angle) * radius).floor(), Vector2(size, size)),
				Color(0.78, 0.9, 1.0, 0.10 + 0.22 * twinkle))


## 꽉 찬 원, 또는(`dome`) 위쪽 반원.
static func _disc(ci: CanvasItem, c: Vector2, radius: float, col: Color, dome: bool) -> void:
	if not dome:
		ci.draw_circle(c, radius, col)
		return
	var points := PackedVector2Array()
	for i in range(41):
		points.append(c + Vector2.from_angle(PI + PI * float(i) / 40.0) * radius)
	ci.draw_colored_polygon(points, col)


# --------------------------------------------------------------------------- #
# 빛의 문 — 폭이 곧 확률이다
# --------------------------------------------------------------------------- #
## 수정에서 위로 솟는 빛기둥. 궤도마다 그 문의 폭만큼만 밝다.
##
## ★ 궤도 띠 하나가 문 하나다. 띠의 양 끝 선은 정확히 `GATE_ANGLE ± gate_half(ring)` 에
##   서고, 궤도 선 위의 굵은 금빛 호(문턱)도 같은 두 각 사이다 — 별의 한가운데가 그 호
##   위에 있으면 문 안이다. 띠와 띠 사이는 단(段)으로 이어서 솟을수록 좁아지는 첨탑이 된다.
## ★ 가장 바깥 문은 아주 좁다(8~9칸). 그래서 문턱 양 끝에 **문설주**(작은 마름모)를 세우고
##   꼭대기에 **뾰족한 빛 끝**을 올려, 폭이 좁아도 「여기가 문」이 한눈에 읽히게 한다.
static func draw_gate(ci: CanvasItem, c: Vector2, sc: float = 1.0, time: float = 0.0,
		power: float = 1.0) -> void:
	if power <= 0.01:
		return
	var g := Rite.GATE_ANGLE
	var last := Rite.RINGS - 1
	var line_w := maxf(1.0, 2.0 * sc)
	var shimmer := 0.93 + 0.07 * sin(time * 2.3)
	for ring in range(Rite.RINGS):
		var half := minf(Rite.gate_half(ring), PI)
		var r0 := lane_inner(ring, sc)
		var r1 := lane_outer(ring, sc)
		# 1) 빛의 면 — 수정에 가까울수록, 그리고 문 한가운데일수록 밝다. 가장자리는 옅게 식어서
		#    종이를 오려 붙인 판이 아니라 **빛기둥**으로 보인다(끝 선이 경계를 또렷이 긋는다).
		# ★ 조각의 경계를 **모든 궤도가 같은 각 격자**(FILL_STEP)에 맞춘다. 궤도마다 따로 나누면
		#   띠와 띠가 맞닿는 호를 서로 다른 현으로 긋게 되어, 그 사이로 판이 점점이 비쳐 보인다.
		var a_in := lerpf(0.40, 0.24, float(ring) / float(Rite.RINGS)) * power * shimmer
		var a_out := lerpf(0.40, 0.24, float(ring + 1) / float(Rite.RINGS)) * power * shimmer
		var cuts: PackedFloat32Array = [-half]
		var cut := ceilf(-half / FILL_STEP + 0.001) * FILL_STEP
		while cut < half - 0.0005:
			cuts.append(cut)
			cut += FILL_STEP
		cuts.append(half)
		for i in range(cuts.size() - 1):
			var d0 := Vector2.from_angle(g + cuts[i])
			var d1 := Vector2.from_angle(g + cuts[i + 1])
			var f0 := lerpf(1.0, 0.30, pow(absf(cuts[i]) / half, 1.3))
			var f1 := lerpf(1.0, 0.30, pow(absf(cuts[i + 1]) / half, 1.3))
			ci.draw_polygon(
					PackedVector2Array([c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d1 * r0]),
					PackedColorArray([Color(BEAM, a_in * f0), Color(BEAM, a_out * f0),
						Color(BEAM, a_out * f1), Color(BEAM, a_in * f1)]))
		if half >= PI - 0.001:
			continue      # 한 바퀴가 다 문이면 가장자리도 문설주도 없다
		# 2) 문의 양 끝 선 — 판정과 같은 각에 선다.
		for side in [-1.0, 1.0]:
			var d := Vector2.from_angle(g + half * float(side))
			ci.draw_line(c + d * r0, c + d * r1, Color(LIGHT, 0.85 * power), line_w, true)
		# 3) 띠 사이의 단 — 이 띠의 문 끝과 바깥 띠의 문 끝을 호로 잇는다.
		var next_half := minf(Rite.gate_half(ring + 1), PI) if ring < last else 0.0
		if ring < last and not is_equal_approx(half, next_half):
			var lo := minf(half, next_half)
			var hi := maxf(half, next_half)
			ci.draw_arc(c, r1, g - hi, g - lo, 12, Color(LIGHT, 0.85 * power), line_w, true)
			ci.draw_arc(c, r1, g + lo, g + hi, 12, Color(LIGHT, 0.85 * power), line_w, true)
		if ring == 0:
			ci.draw_arc(c, r0, g - half, g + half, cuts.size(), Color(LIGHT, 0.55 * power), line_w, true)
	# 4) 꼭대기의 뾰족한 빛 끝 — 가장 좁은 문이 어디인지를 가리킨다.
	var tip_half := minf(Rite.gate_half(last), 0.5)
	var top := lane_outer(last, sc)
	var left := c + Vector2.from_angle(g - tip_half) * top
	var right := c + Vector2.from_angle(g + tip_half) * top
	var apex := c + Vector2.from_angle(g) * (RIM + RIM_W + SPIRE) * sc
	ci.draw_polygon(PackedVector2Array([left, apex, right]),
			PackedColorArray([Color(BEAM, 0.16 * power), Color(BEAM, 0.9 * power), Color(BEAM, 0.16 * power)]))
	# 수정에서 꼭대기까지 곧게 선 한 줄기 — 다섯 문이 한 기둥이라는 것을 잇는다.
	ci.draw_line(c + Vector2.from_angle(g) * lane_inner(0, sc), apex, Color(1, 1, 1, 0.20 * power * shimmer),
			maxf(1.0, 2.0 * sc), true)
	ci.draw_line(left, apex, Color(LIGHT, 0.85 * power), line_w, true)
	ci.draw_line(right, apex, Color(LIGHT, 0.85 * power), line_w, true)
	var gem := maxf(3.0, 6.0 * sc)
	ci.draw_colored_polygon(_diamond(apex, gem + 2.0), Color(Look.BG_DEEP, power))
	ci.draw_colored_polygon(_diamond(apex, gem), Color(Look.GOLD, power))
	# 5) 문턱과 문설주 — 별이 서는 선 위의 금빛 호와 그 양 끝.
	for ring in range(Rite.RINGS):
		var half := minf(Rite.gate_half(ring), PI)
		var radius := orbit_radius(ring, sc)
		ci.draw_arc(c, radius, g - half, g + half, clampi(int(ceil(half * 2.0 / 0.09)), 2, 80),
				Color(Look.GOLD, 0.95 * power), maxf(2.0, 4.0 * sc), true)
		if half >= PI - 0.001:
			continue
		for side in [-1.0, 1.0]:
			var post := c + Vector2.from_angle(g + half * float(side)) * radius
			ci.draw_colored_polygon(_diamond(post, maxf(2.5, 5.0 * sc) + 1.5), Color(Look.BG_DEEP, power))
			ci.draw_colored_polygon(_diamond(post, maxf(2.5, 5.0 * sc)), Color(LIGHT, power))
	# 6) 빛 알갱이 — 수정에서 문을 따라 위로 오른다. 문 밖으로 새지 않는다(문이 넓어 보인다).
	if sc < 0.5:
		return
	for i in range(10):
		var k := fposmod(time * (0.17 + 0.04 * float(i % 3)) + float(i) * 0.371, 1.0)
		var radius := lerpf(lane_inner(0, sc), lane_outer(last, sc), k)
		var ring := clampi(int((radius / sc - (ORBIT_0 - ORBIT_STEP * 0.5)) / ORBIT_STEP), 0, last)
		var angle := g + minf(Rite.gate_half(ring), PI) * 0.78 * sin(float(i) * 2.4 + time * 0.6)
		var size := maxf(2.0, 3.0 * sc)
		ci.draw_rect(Rect2((c + Vector2.from_angle(angle) * radius - Vector2(size, size) * 0.5).floor(),
				Vector2(size, size)), Color(LIGHT, sin(k * PI) * 0.8 * power))


static func _diamond(at: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.72, 0),
		at + Vector2(0, radius), at - Vector2(radius * 0.72, 0)])


# --------------------------------------------------------------------------- #
# 수정 — 판의 한가운데
# --------------------------------------------------------------------------- #
## 생명 수정과 그 둘레의 느린 고리. `charge` 가 오르면(확정 연출) 빛이 차오른다.
## `dome` 이면 수정이 반원의 밑변 위에 올라앉는다.
static func draw_core(ci: CanvasItem, c: Vector2, sc: float = 1.0, time: float = 0.0,
		charge: float = 0.0, dome: bool = false) -> void:
	var well := lane_inner(0, sc)
	if dome:
		_disc(ci, c, well * 0.9, Color(Look.CRYSTAL, 0.10), true)
		ci.draw_arc(c, well * 0.93, PI, TAU, 28, Color(Look.CRYSTAL, 0.30), maxf(1.0, 1.6 * sc), true)
		var small := 24.0 * sc
		Look.draw_crystal(ci, c + Vector2(0, -small - 2.0 * sc), small, true, 0.30 + 0.18 * sin(time * 2.1))
		return
	ci.draw_circle(c, well * 0.9, Color(Look.CRYSTAL, 0.07 + 0.20 * charge))
	for band in range(2):
		var spin := time * (0.45 if band == 0 else -0.3) * (1.0 + charge * 4.0)
		ci.draw_arc(c, well * (0.78 if band == 0 else 0.93), spin, spin + TAU * 0.78, 40,
				Color(Look.CRYSTAL, (0.34 if band == 0 else 0.22) + 0.4 * charge), maxf(1.0, 1.6 * sc), true)
	var radius := 40.0 * sc
	Look.draw_crystal(ci, c + Vector2(0, radius * 0.25), radius, true,
			0.30 + 0.18 * sin(time * 2.1) + charge * 0.9)


## 수정이 별을 붙든 줄. 가장 안쪽 별이 왜 언제나 문 안인지를 그림으로 말한다.
static func draw_tether(ci: CanvasItem, c: Vector2, star: Vector2, sc: float = 1.0,
		time: float = 0.0, col: Color = Look.CRYSTAL) -> void:
	var from := c + (star - c).normalized() * lane_inner(0, sc) * 0.55
	ci.draw_line(from, star, Color(col, 0.20), maxf(2.0, 5.0 * sc), true)
	ci.draw_line(from, star, Color(col, 0.55 + 0.25 * sin(time * 3.0)), maxf(1.0, 1.6 * sc), true)


# --------------------------------------------------------------------------- #
# 별
# --------------------------------------------------------------------------- #
## 별 하나. `flash` 는 잠기는 순간의 번쩍임(1 → 0), `alpha` 는 사라지는 별의 옅음이다.
static func draw_star(ci: CanvasItem, at: Vector2, look: int, sc: float = 1.0,
		time: float = 0.0, flash: float = 0.0, alpha: float = 1.0) -> void:
	if alpha <= 0.01:
		return
	var s := maxf(sc, 0.3)
	match look:
		OUT:
			var radius := 11.5 * s
			ci.draw_colored_polygon(Look.star_points(at, radius + 2.5 * s), Color(Look.BG_DEEP, alpha))
			var points := Look.star_points(at, radius)
			ci.draw_colored_polygon(points, Color(COLD_FILL, alpha))
			points.append(points[0])
			ci.draw_polyline(points, Color(COLD, alpha), maxf(1.0, 1.6 * s), true)
		SPIN:
			var radius := 11.5 * s
			ci.draw_circle(at, radius * 1.7, Color(LIGHT, 0.16 * alpha))
			ci.draw_colored_polygon(Look.star_points(at, radius + 2.5 * s), Color(Look.BG_DEEP, alpha))
			ci.draw_colored_polygon(Look.star_points(at, radius), Color(LIGHT, alpha))
		_:
			var radius := 13.0 * s
			var ring_col: Color = Look.CRYSTAL if look == HELD else Look.GOLD
			ci.draw_circle(at, radius * 1.9, Color(Look.GOLD, 0.12 * alpha))
			# 잠금 꺾쇠 — 「이 별은 다시 돌지 않는다」. 색을 몰라도 네 꺾쇠가 둘렀으면 문 안이다.
			# (꽉 막힌 고리로 두르면 별이 금화처럼 보인다 — 도박장의 칩이 아니라 붙들린 별이어야 한다.)
			for corner in range(4):
				var mid := PI * 0.25 + PI * 0.5 * float(corner)
				ci.draw_arc(at, radius * 1.48, mid - 0.50, mid + 0.50, 8, Color(Look.BG_DEEP, 0.85 * alpha), maxf(3.0, 4.6 * s), true)
				ci.draw_arc(at, radius * 1.48, mid - 0.46, mid + 0.46, 8, Color(ring_col, alpha), maxf(1.4, 2.4 * s), true)
			ci.draw_colored_polygon(Look.star_points(at, radius + 2.5 * s), Color(Look.BG_DEEP, alpha))
			ci.draw_colored_polygon(Look.star_points(at, radius), Color(Look.GOLD, alpha))
			ci.draw_colored_polygon(Look.star_points(at, radius * 0.46), Color(Color("#fff6d0"), alpha))
	if flash > 0.01:
		ci.draw_arc(at, (17.0 + (1.0 - flash) * 30.0) * s, 0.0, TAU, 32,
				Color(1.0, 0.97, 0.8, flash * alpha), maxf(1.5, 4.0 * s * flash), true)
		ci.draw_circle(at, 10.0 * s * flash, Color(1, 1, 1, 0.55 * flash * alpha))


## 도는 별의 꼬리. `sweep` 은 방금 지나온 각(부호가 도는 방향이다) — 빠를수록 길다.
static func draw_trail(ci: CanvasItem, c: Vector2, ring: int, angle: float, sweep: float,
		sc: float = 1.0, alpha: float = 1.0, col: Color = LIGHT) -> void:
	if absf(sweep) < 0.015:
		return
	var radius := orbit_radius(ring, sc)
	for layer in range(3):
		var part := sweep * (1.0 - float(layer) * 0.3)
		var from := angle - part
		ci.draw_arc(c, radius, minf(from, angle), maxf(from, angle), 16,
				Color(col, alpha * (0.14 + 0.17 * float(layer))), (3.0 + 2.5 * float(layer)) * sc, true)


## 멈춰 선 판 한 장 — 도움말 · 지원 팝업 · 타이틀처럼 연출 없이 결과만 보여 줄 때.
## `star_sc` 로 별만 따로 키울 수 있다(작은 판에서 별이 점이 되지 않게).
## `dome` 이면 위쪽 반원만 그린다 — 문 밖의 별이 밑변 아래에 서면 그리지 않는다.
static func draw_still(ci: CanvasItem, c: Vector2, sc: float, orbit: Array,
		time: float = 0.0, star_sc: float = -1.0, dome: bool = false) -> void:
	var size := sc if star_sc <= 0.0 else star_sc
	draw_base(ci, c, sc, time, dome)
	draw_gate(ci, c, sc, time)
	draw_core(ci, c, sc, time, 0.0, dome)
	for ring in range(mini(Rite.RINGS, orbit.size())):
		var pos := int(orbit[ring])
		var look := look_of(ring, pos)
		var at := slot_point(c, ring, pos, sc)
		if dome and at.y > c.y - 14.0 * size:
			continue
		if look == HELD:
			draw_tether(ci, c, at, sc, time)
		draw_star(ci, at, look, size, time)
