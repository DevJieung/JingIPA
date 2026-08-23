extends RefCounted
class_name Look

## 색 · 글꼴 · 카드 그리기. 화면들이 저마다 색을 짓지 않게 여기 한곳에 모은다.
##
## 도트 그림(캐릭터·몬스터)은 Krea 로 뽑지만, **카드와 UI 도형은 코드로 그린다.**
## 카드는 숫자가 또렷해야 하는데 96px 도트로 뽑으면 J 와 Q 가 구별이 안 됐다.

# 밤의 도박장. 배경은 아주 어둡게 깔고 카드와 금색만 튀게 한다.
const BG        := Color("#0e0b16")
const BG_DEEP   := Color("#070510")
const PANEL     := Color("#1b1526")
const PANEL_EDGE := Color("#3a2f4f")
const FELT      := Color("#123527")   ## 카드 테이블의 초록 천
const FELT_EDGE := Color("#0a2018")

const INK       := Color("#f4efe4")   ## 밝은 글자
const INK_DIM   := Color("#9c93ac")
const GOLD      := Color("#f6c445")
const GOLD_DEEP := Color("#a97b12")
const RED       := Color("#e2415a")
const BLUE      := Color("#4aa3ff")
const GREEN     := Color("#5ad07a")
const PURPLE    := Color("#a56cf0")

## 투기장 — 벽·길·크리스탈
const WALL       := Color("#413a5c")   ## 돌벽 몸통
const WALL_TOP   := Color("#6a6090")   ## 벽 윗면(빛 받는 쪽)
const WALL_DARK  := Color("#241f36")   ## 벽 그림자
const LANE       := Color("#1c1730")   ## 몬스터가 걷는 길
const LANE_EDGE  := Color("#2b2445")   ## 길에 그은 줄
const YARD       := Color("#123527")   ## 영웅이 선 안뜰(초록 천)
const GATE       := Color("#f6c445")   ## 문
const CRYSTAL      := Color("#5fe6ff")
const CRYSTAL_DEEP := Color("#1f7fa8")
const CRYSTAL_DEAD := Color("#3a3450")

## 얼음 — 둔화에 걸린 몬스터에 낀 성에와 얼음 조각.
## ★ 크리스탈(#5fe6ff)보다 **희게** 잡았다. 같은 하늘색으로 두면 몬스터 몸에 붙은 얼음이
##   제단의 크리스탈처럼 보여서, 목숨이 굴러다니는 줄 알게 된다.
const ICE      := Color("#d6f4ff")
const ICE_DEEP := Color("#59bfe6")

const CARD_BG   := Color("#f7f3e8")
const CARD_EDGE := Color("#2a2233")
const CARD_RED  := Color("#c62a44")
const CARD_BLK  := Color("#22202b")
const CARD_BACK := Color("#8c1d2f")
const CARD_BACK2 := Color("#5d0f1e")

## 족보 등급별 색. 낮으면 수수하게, 높으면 눈이 부시게.
const TIER_COLOR := [
	Color("#8b8b98"),  # 하이카드 — 회색
	Color("#79c07a"),  # 원페어 — 풀색
	Color("#5aa9d8"),  # 투페어 — 하늘
	Color("#4a7fe0"),  # 트리플 — 파랑
	Color("#8a6ae8"),  # 스트레이트 — 보라
	Color("#c15ce0"),  # 플러시 — 자주
	Color("#ff7ac0"),  # 풀하우스 — 분홍 ★
	Color("#ff9a3c"),  # 포카드 — 주황 ★
	Color("#ffd24a"),  # 스트레이트 플러시 — 금 ★
	Color("#fff0b8"),  # 로열 — 흰 금빛 ★ (순백은 빛 연출 위에서 글자가 안 읽힌다)
]

const CARD_W := 118.0
const CARD_H := 168.0
const CARD_R := 12.0

static func tier_color(t: int) -> Color:
	return TIER_COLOR[clampi(t, 0, TIER_COLOR.size() - 1)]


## 속성을 한 글자로. 칸이 40px 도 안 되는 자리에 「무상성」을 쓸 수는 없다.
const ELEM_CHAR := {"none": "무", "fire": "불", "ice": "얼", "elec": "전", "water": "물"}

static func elem_char(e: String) -> String:
	return String(ELEM_CHAR.get(e, "무"))


## 속성 표시 한 개 — 속성 색 동그라미 안에 한 글자.
##
## ★ 왜 색만으로 안 두는가: 캐릭터마다 이미 제 색(탄알 색)이 있어서, 색 점 하나를 더
##   찍으면 그게 속성인지 그 캐릭터 색인지 구별이 안 된다. 글자가 한 자 들어가야
##   "아, 이건 속성이구나"가 읽힌다. 무상성은 회백색이라 저절로 뒤로 물러난다.
## ★ 테두리를 두르는 이유: 얼음(하늘)과 크리스탈, 전기(노랑)와 금색이 같은 화면에 있다.
##   어두운 테두리가 있어야 배경이 무엇이든 동그라미로 읽힌다.
static func draw_elem(ci: CanvasItem, c: Vector2, r: float, e: String) -> void:
	if r < 3.0:
		return
	var col := Color(String(Balance.ELEM.get(e, Balance.ELEM["none"])["color"]))
	ci.draw_circle(c, r + 1.5, BG_DEEP)
	ci.draw_circle(c, r, col)
	var sz := int(r * 1.5)
	if sz >= 9:
		text_center(ci, c, elem_char(e), sz, BG_DEEP)


## 체력 막대의 색. 넉넉하면 초록, 반쯤이면 금색, 얼마 안 남으면 빨강.
##
## ★ 세 토막으로 딱 끊지 않고 이어서 섞는다. 끊어 두면 34%와 36%가 전혀 다른 색이라
##   "얼마나 남았나"가 아니라 "어느 칸에 들어갔나"로 읽힌다 — 막대를 두는 뜻이 없어진다.
static func hp_color(k: float) -> Color:
	if k > 0.5:
		return GOLD.lerp(GREEN, clampf((k - 0.5) * 2.0, 0.0, 1.0))
	return RED.lerp(GOLD, clampf(k * 2.0, 0.0, 1.0))


## 모서리가 둥근 사각형을 채운다. Godot 에는 이 기본 함수가 없다.
static func fill_round(ci: CanvasItem, rect: Rect2, r: float, col: Color) -> void:
	r = min(r, min(rect.size.x, rect.size.y) * 0.5)
	if r <= 0.5:
		ci.draw_rect(rect, col)
		return
	ci.draw_rect(Rect2(rect.position + Vector2(r, 0), rect.size - Vector2(r * 2.0, 0)), col)
	ci.draw_rect(Rect2(rect.position + Vector2(0, r), Vector2(r, rect.size.y - r * 2.0)), col)
	ci.draw_rect(Rect2(rect.position + Vector2(rect.size.x - r, r), Vector2(r, rect.size.y - r * 2.0)), col)
	for c in [rect.position + Vector2(r, r),
			rect.position + Vector2(rect.size.x - r, r),
			rect.position + Vector2(r, rect.size.y - r),
			rect.position + Vector2(rect.size.x - r, rect.size.y - r)]:
		ci.draw_circle(c, r, col)


## 테두리만 그린다(안을 비우지 않고). 겹쳐 그리는 순서로 해결한다.
static func outline_round(ci: CanvasItem, rect: Rect2, r: float, col: Color, w: float) -> void:
	fill_round(ci, rect.grow(w), r + w, col)


## 크리스탈 하나. alive 가 거짓이면 깨진 자리를 어둡게 남긴다.
##
## ★ 그림 파일로 안 만든 이유: 크리스탈은 마흔 개가 화면 한가운데에 촘촘히 놓인다.
##   도트 그림이면 12px 로 줄어들어 무슨 모양인지 안 보인다. 도형이 훨씬 또렷하다.
static func draw_crystal(ci: CanvasItem, c: Vector2, r: float, alive: bool,
		glow: float = 0.0) -> void:
	if not alive:
		# 깨진 자리 — 밑동만 남는다.
		# ★ glow 는 **여기서도** 써야 한다. "방금 깨진 칸이 번쩍인다"는 표시가
		#   이 가지에만 오는데(깨졌으니 alive 가 거짓이다), 예전에는 위에서 바로
		#   돌아가 버려서 그 연출이 조용히 사라졌다.
		if glow > 0.001:
			ci.draw_circle(c, r * (1.0 + glow * 1.6),
					Color(1.0, 1.0, 1.0, clampf(glow, 0.0, 1.0) * 0.55))
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.5, r * 0.7), c + Vector2(r * 0.5, r * 0.7),
			c + Vector2(r * 0.28, r * 0.1), c + Vector2(-r * 0.34, r * 0.2)]),
			CRYSTAL_DEAD)
		return
	if glow > 0.001:
		ci.draw_circle(c, r * (1.8 + glow), Color(CRYSTAL.r, CRYSTAL.g, CRYSTAL.b, 0.18 * glow))
	var body := PackedVector2Array([
		c + Vector2(0, -r * 1.5), c + Vector2(r * 0.78, -r * 0.2),
		c + Vector2(r * 0.42, r * 1.0), c + Vector2(-r * 0.42, r * 1.0),
		c + Vector2(-r * 0.78, -r * 0.2)])
	ci.draw_colored_polygon(body, CRYSTAL_DEEP)
	# 왼쪽 면만 밝게 — 이 한 조각이 있어야 평평한 오각형이 아니라 보석으로 보인다.
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r * 1.5), c + Vector2(0, r * 1.0),
		c + Vector2(-r * 0.42, r * 1.0), c + Vector2(-r * 0.78, -r * 0.2)]), CRYSTAL)
	ci.draw_line(c + Vector2(0, -r * 1.5), c + Vector2(0, r * 1.0),
			Color(1, 1, 1, 0.55), max(1.0, r * 0.16), true)


static func font() -> Font:
	return ThemeDB.fallback_font


## 가운데 정렬 글자. 화면마다 같은 계산을 반복하지 않으려고 뺐다.
static func text_center(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color) -> void:
	var f := font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(f, pos + Vector2(-w * 0.5, size * 0.36), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## 어두운 테두리를 두른 가운데 정렬 글자.
## 화려한 연출 위에서는 테두리가 없으면 글자가 배경에 먹혀 안 읽힌다.
static func text_center_out(ci: CanvasItem, pos: Vector2, s: String, size: int,
		col: Color, edge: Color = BG_DEEP, w: float = 3.0) -> void:
	for a in [Vector2(-w, 0), Vector2(w, 0), Vector2(0, -w), Vector2(0, w),
			Vector2(-w, -w), Vector2(w, -w), Vector2(-w, w), Vector2(w, w)]:
		text_center(ci, pos + a, s, size, edge)
	text_center(ci, pos, s, size, col)


static func text_left(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color) -> void:
	ci.draw_string(font(), pos + Vector2(0, size * 0.36), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_right(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color) -> void:
	var f := font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(f, pos + Vector2(-w, size * 0.36), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_width(s: String, size: int) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 카드 한 장. pos 는 왼쪽 위 모서리, scale 로 크기를 바꾼다.
## hi 가 참이면 족보를 이룬 카드라는 뜻으로 테두리를 금색으로 두른다.
static func draw_card(ci: CanvasItem, pos: Vector2, code: int, sc: float = 1.0,
		hi: bool = false, dim: bool = false) -> void:
	var w := CARD_W * sc
	var h := CARD_H * sc
	var rect := Rect2(pos, Vector2(w, h))
	# 그림자 — 카드가 천 위에 떠 있게 보이면 훨씬 낫다.
	fill_round(ci, Rect2(pos + Vector2(0, 5.0 * sc), rect.size), CARD_R * sc, Color(0, 0, 0, 0.45))
	if hi:
		fill_round(ci, rect.grow(4.0 * sc), (CARD_R + 4.0) * sc, GOLD)
	else:
		fill_round(ci, rect.grow(2.0 * sc), (CARD_R + 2.0) * sc, CARD_EDGE)
	fill_round(ci, rect, CARD_R * sc, CARD_BG if not dim else CARD_BG.darkened(0.35))

	var suit := Poker.suit_of(code)
	var col := CARD_RED if (suit == Poker.Suit.HEART or suit == Poker.Suit.DIAMOND) else CARD_BLK
	if dim:
		col = col.lerp(CARD_BG, 0.45)
	var rc: String = Poker.RANK_CHAR[Poker.rank_of(code) - Poker.RANK_MIN]

	# 왼쪽 위 · 오른쪽 아래(뒤집힌 것처럼) 작은 표시, 가운데에 큰 무늬.
	var small := int(28.0 * sc)
	text_center(ci, pos + Vector2(20.0 * sc, 24.0 * sc), rc, small, col)
	draw_suit(ci, pos + Vector2(20.0 * sc, 52.0 * sc), 9.0 * sc, suit, col)
	text_center(ci, pos + Vector2(w - 20.0 * sc, h - 52.0 * sc), rc, small, col)
	draw_suit(ci, pos + Vector2(w - 20.0 * sc, h - 24.0 * sc), 9.0 * sc, suit, col)
	draw_suit(ci, pos + Vector2(w * 0.5, h * 0.5), 30.0 * sc, suit, col)


## 카드 무늬를 **도형으로** 그린다. r 은 대략 반지름(무늬의 절반 크기).
##
## ★ 글꼴로 그리지 않는 이유는 core/poker.gd 의 SUIT_KO 주석에 적어 뒀다.
##   번들 폰트에 ♠♦♣ 가 없어서 두부로 깨진다. 도형이면 어느 기기에서든 똑같이 나온다.
static func draw_suit(ci: CanvasItem, c: Vector2, r: float, suit: int, col: Color) -> void:
	match suit:
		Poker.Suit.HEART:
			_heart(ci, c, r, col, false)
		Poker.Suit.SPADE:
			_heart(ci, c + Vector2(0, -r * 0.10), r, col, true)
			_stem(ci, c + Vector2(0, r * 0.62), r, col)
		Poker.Suit.DIAMOND:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 1.18), c + Vector2(r * 0.86, 0),
				c + Vector2(0, r * 1.18), c + Vector2(-r * 0.86, 0)]), col)
		_:
			# 클로버 — 동그라미 셋에 줄기 하나.
			# ★ 동그라미 사이가 벌어지면 가운데에 흰 틈이 생겨 클로버로 안 보인다.
			#   반지름을 키우고 간격을 좁혀 서로 물리게 해 뒀다.
			ci.draw_circle(c + Vector2(0, -r * 0.50), r * 0.58, col)
			ci.draw_circle(c + Vector2(-r * 0.50, r * 0.26), r * 0.58, col)
			ci.draw_circle(c + Vector2(r * 0.50, r * 0.26), r * 0.58, col)
			_stem(ci, c + Vector2(0, r * 0.74), r, col)


## 하트 한 덩이. flip 이 참이면 뒤집혀서 스페이드의 몸이 된다.
static func _heart(ci: CanvasItem, c: Vector2, r: float, col: Color, flip: bool) -> void:
	var f := -1.0 if flip else 1.0
	ci.draw_circle(c + Vector2(-r * 0.45, -r * 0.34 * f), r * 0.52, col)
	ci.draw_circle(c + Vector2(r * 0.45, -r * 0.34 * f), r * 0.52, col)
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.95, -r * 0.20 * f),
		c + Vector2(r * 0.95, -r * 0.20 * f),
		c + Vector2(0, r * 1.10 * f)]), col)


## 스페이드·클로버의 밑동.
static func _stem(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.12, -r * 0.30), c + Vector2(r * 0.12, -r * 0.30),
		c + Vector2(r * 0.42, r * 0.48), c + Vector2(-r * 0.42, r * 0.48)]), col)


## 카드 뒷면. 리롤 연출에서 뒤집을 때 쓴다.
static func draw_card_back(ci: CanvasItem, pos: Vector2, sc: float = 1.0) -> void:
	var w := CARD_W * sc
	var h := CARD_H * sc
	var rect := Rect2(pos, Vector2(w, h))
	fill_round(ci, Rect2(pos + Vector2(0, 5.0 * sc), rect.size), CARD_R * sc, Color(0, 0, 0, 0.45))
	fill_round(ci, rect.grow(2.0 * sc), (CARD_R + 2.0) * sc, CARD_EDGE)
	# 그려 둔 뒷면 그림이 있으면 그걸 쓰고, 없으면 아래 도형으로 대신 그린다.
	var t := Art.tex(Roster.ART.get("card_back", ""))
	if t != null:
		ci.draw_texture_rect(t, rect, false)
		return
	fill_round(ci, rect, CARD_R * sc, CARD_BACK)
	fill_round(ci, rect.grow(-8.0 * sc), CARD_R * sc * 0.6, CARD_BACK2)
	# 금색 마름모 격자
	var step := 22.0 * sc
	var y := pos.y + 16.0 * sc
	var row := 0
	while y < pos.y + h - 12.0 * sc:
		var x := pos.x + (12.0 * sc if row % 2 == 0 else 23.0 * sc)
		while x < pos.x + w - 12.0 * sc:
			var d := 5.0 * sc
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x, y - d), Vector2(x + d, y), Vector2(x, y + d), Vector2(x - d, y)]),
				GOLD_DEEP)
			x += step
		y += step * 0.62
		row += 1
