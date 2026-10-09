extends RefCounted
class_name Look

## 색 · 글꼴 · 공통 표식(별 · 속성 · 패시브 문양) 그리기.
## 화면들이 저마다 색을 짓지 않게 여기 한곳에 모은다.
##
## 실제 3D 전장과 같은 청흑색 금속·황동·수정빛을 코드 기반 UI에 공유한다.
## ★ 포커 시절의 트럼프 카드 · 판타지 문장 카드 그리기는 2026-10-07 에 통째로 걷어냈다
##   (뽑기가 별맞춤 의식으로 바뀌었다 — game/rite_board.gd). 등급은 어디서나 별이다.

# 밤의 야영지. 배경은 아주 어둡게 깔고 별빛과 금색만 튀게 한다.
const BG        := Color("#10212d")
const BG_DEEP   := Color("#080f19")
const PANEL     := Color("#172c3b")
const PANEL_EDGE := Color("#536a7a")
const NIGHT      := Color("#0c1722")  ## 의식판을 놓는 밤하늘 판
const NIGHT_EDGE := Color("#060d14")

const INK       := Color("#f3f3e9")   ## 밝은 글자
const INK_DIM   := Color("#b9cad3")
const GOLD      := Color("#edc879")
const GOLD_DEEP := Color("#957041")
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
const YARD       := Color("#123527")   ## 영웅이 선 전장(초록 천)
const GATE       := Color("#edc879")   ## 문
const CRYSTAL      := Color("#5fe6ff")
const CRYSTAL_DEEP := Color("#1f7fa8")
const CRYSTAL_DEAD := Color("#3a3450")

## 얼음 — 둔화에 걸린 몬스터에 낀 성에와 얼음 조각.
## ★ 크리스탈(#5fe6ff)보다 **희게** 잡았다. 같은 하늘색으로 두면 몬스터 몸에 붙은 얼음이
##   제단의 크리스탈처럼 보여서, 목숨이 굴러다니는 줄 알게 된다.
const ICE      := Color("#d6f4ff")
const ICE_DEEP := Color("#59bfe6")

## 상성별 피해 막대의 색 — 전투 정보판이 영웅마다 세 줄로 쌓는다.
##
## ★ 데미지 숫자(Fx.dmg_text)와 **결이 같아야 한다**: 약점은 뜨겁게, 보통은 희게,
##   저항은 식은 잿빛으로. 그래야 투기장에서 튀는 숫자와 정보판의 막대가 같은 규칙을
##   말한다. 색을 여기 한곳에 두는 까닭은 막대·범례가 같은 색을 봐야 하기 때문이다.
## ★ 약점을 **속성 색으로 두지 않는다.** 속성 색으로 두면 범례에 찍을 색이 없어지고
##   (영웅마다 다르니까), 여섯 줄이 저마다 다른 색으로 2배를 그려서 「어느 줄이 2배
##   막대인가」를 매번 다시 찾아야 한다. 속성은 줄머리의 동그라미가 따로 말한다.
## ★ GOLD(합계·골드) · GREEN(초당 피해) · RED(위험) · CRYSTAL(목숨)과 겹치지 않게 골랐다.
const DMG_WEAK   := Color("#ff8a3c")   ## 2배 — 뜨거운 주황
const DMG_NORMAL := Color("#f3f3e9")   ## 보통 — 흰 글자와 같은 색
const DMG_RESIST := Color("#847bA2")   ## 반감 — 식은 잿빛

## 등급별 색 — 반 별 단위의 열 칸(Balance.TIER_ATK). 낮으면 수수하게, 높으면 눈이 부시게.
## 별맞춤 의식은 온 별(1 · 3 · 5 · 7 · 9번 칸)만 주고, 사이의 반 별은 승급과 합성으로 오른다.
## ★ 는 소환 연출이 화려해지는 등급이다(Balance.SHOWY_TIER — 지금은 4성부터).
## ★ 색은 덤이다. 등급은 언제나 별의 **수**로 먼저 읽힌다(draw_rarity · star_label).
const TIER_COLOR := [
	Color("#8b8b98"),  # 0.5성 — 회색
	Color("#79c07a"),  # 1성 — 풀색
	Color("#5aa9d8"),  # 1.5성 — 하늘
	Color("#4a7fe0"),  # 2성 — 파랑
	Color("#8a6ae8"),  # 2.5성 — 보라
	Color("#c15ce0"),  # 3성 — 자주
	Color("#ff7ac0"),  # 3.5성 — 분홍
	Color("#ff9a3c"),  # 4성 — 주황 ★
	Color("#ffd24a"),  # 4.5성 — 금 ★
	Color("#fff0b8"),  # 5성 — 흰 금빛 ★ (순백은 빛 연출 위에서 글자가 안 읽힌다)
]

## 화면 전체. 덮개·섬광·터치 자리처럼 「화면 통째로」를 뜻하는 곳이 전부 이것을 쓴다.
const SCREEN := Rect2(0, 0, 1280, 800)

## Legacy particle helpers retain their sampling grid; UI surfaces do not snap.
const PX := 4.0

## 좌표를 도트 격자에 맞춘다. 반올림이 아니라 **내림**이다 — 반올림하면 같은 도형이
## 프레임마다 한 칸씩 튄다(떠 있는 것의 좌표는 늘 소수다).
static func snap(v: float, g: float = PX) -> float:
	return floor(v / g) * g


static func snap_v(v: Vector2, g: float = PX) -> Vector2:
	return Vector2(snap(v.x, g), snap(v.y, g))


static func snap_rect(r: Rect2, g: float = PX) -> Rect2:
	var a := snap_v(r.position, g)
	var b := snap_v(r.position + r.size + Vector2(g - 0.01, g - 0.01), g)
	return Rect2(a, b - a)


## Legacy call sites use the same smooth bevel as the native 3D presentation.
static func px_panel(ci: CanvasItem, rect: Rect2, face: Color, edge: Color,
		lip: float = 0.0) -> void:
	material_panel(ci, rect, face, edge)

static func tier_color(t: int) -> Color:
	return TIER_COLOR[clampi(t, 0, TIER_COLOR.size() - 1)]


## 등급을 별 수로 적는다 — 「3성」·「3.5성」. **등급의 이름은 게임 어디서나 이것 하나다.**
##
## ★ 포커 시절에는 등급마다 족보 이름(원페어 · 풀하우스 …)이 있었고 좁은 칸용 줄임말까지
##   따로 뒀다. 별맞춤 의식에서는 문 안의 별을 **세면** 등급이다 — 외울 이름이 없다.
##   등급은 반 별 단위의 열 칸(Balance.TIER_ATK)이라 짝수 칸은 「2.5성」처럼 반 별이 붙는다.
static func star_label(tier: int) -> String:
	var t := clampi(tier, 0, Balance.TIER_MAX)
	if t % 2 == 1:
		return "%d성" % ((t + 1) / 2)
	return "%.1f성" % (float(t + 1) * 0.5)



## 영웅 카드의 바탕과 테두리는 공격 속성만 따른다. 등급은 별로, 선택은 꺾쇠로 읽는다.
static func hero_card_face(element: String) -> Color:
	return BG_DEEP.lerp(Balance.elem_color(element), 0.20)


static func hero_card_edge(element: String) -> Color:
	return Balance.elem_color(element).darkened(0.12)


static func hero_card_panel(ci: CanvasItem, rect: Rect2, element: String) -> void:
	material_panel(ci, rect, hero_card_face(element), hero_card_edge(element))
	ci.draw_line(rect.position + Vector2(12, 2), Vector2(rect.end.x - 12, rect.position.y + 2), hero_card_edge(element).lightened(0.3), 2, true)


## 꼭짓점이 위를 보는 별 다섯 개짜리 꼭짓점 열 개. `inner` 는 골의 깊이(바깥 반지름 대비).
## 등급 별(draw_rarity)과 테마 판의 험한 정도 별이 같은 별을 쓴다.
static func star_points(c: Vector2, r: float, inner: float = 0.46) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		points.append(c + Vector2(cos(angle), sin(angle)) * r * (1.0 if i % 2 == 0 else inner))
	return points


## 열 등급을 반 별부터 다섯 별까지 표시한다. 색을 몰라도 채워진 양으로 비교한다.
static func draw_rarity(ci: CanvasItem, c: Vector2, tier: int, radius: float = 5.0) -> void:
	var step := radius * 2.3
	var w := step * 4.0 + radius * 2.0 + 8.0
	fill_round(ci, Rect2(c - Vector2(w * 0.5, radius + 4), Vector2(w, radius * 2 + 8)), 3, BG_DEEP)
	var filled := clampi(tier, 0, 9) + 1
	for star in range(5):
		var points := star_points(c + Vector2(float(star - 2) * step, 0), radius)
		ci.draw_colored_polygon(points, Color("#39454f"))
		if filled >= star * 2 + 2:
			ci.draw_colored_polygon(points, GOLD)
		elif filled == star * 2 + 1:
			# 왼쪽 반쪽 별: 꼭짓점과 아래 골을 잇는 대칭축에서 자른다.
			ci.draw_colored_polygon(PackedVector2Array([points[0], points[5], points[6], points[7], points[8], points[9]]), GOLD)
		points.append(points[0])
		ci.draw_polyline(points, GOLD if filled > star * 2 else Color("#8b9aa5"), 1.0, true)


## 배지의 바깥 여백까지 주어진 칸 안에 맞춘다. 좁은 카드도 별 다섯 개를 유지한다.
static func rarity_rect(box: Rect2, radius: float = 5.0) -> Rect2:
	var r := maxf(0.0, minf(radius, minf((box.size.x - 8.0) / 11.2, (box.size.y - 8.0) * 0.5)))
	var extent := Vector2(r * 11.2 + 8.0, r * 2.0 + 8.0)
	return Rect2(box.get_center() - extent * 0.5, extent)

static func draw_rarity_fit(ci: CanvasItem, box: Rect2, tier: int, radius: float = 5.0) -> void:
	if box.size.x < 10 or box.size.y < 10:
		return
	var fit := rarity_rect(box, radius)
	draw_rarity(ci, fit.get_center(), tier, (fit.size.y - 8.0) * 0.5)


## 속성을 한 글자로. 칸이 40px 도 안 되는 자리에 「무상성」을 쓸 수는 없다.
##
## 도형을 쓰기 어려운 텍스트 목록을 위한 짧은 이름이다.
const ELEM_CHAR := {"none": "무", "fire": "불", "ice": "얼", "elec": "전", "water": "물"}
## 몸을 한 글자로. 「나무」·「바위」는 두 자라 한 자로 줄인다.
const BODY_CHAR := {"aqua": "물", "flame": "불", "wood": "나", "rock": "바", "frost": "얼"}

static func elem_char(e: String) -> String:
	return String(ELEM_CHAR.get(e, "무"))

static func body_char(b: String) -> String:
	return String(BODY_CHAR.get(b, "?"))


static func monster_chip_width(monster: Dictionary, size: int = 20) -> float:
	return text_width(String(monster["ko"]), size) + 44.0


static func draw_monster_chip(ci: CanvasItem, at: Vector2, monster: Dictionary, size: int = 20) -> float:
	var w := monster_chip_width(monster, size)
	fill_round(ci, Rect2(at - Vector2(0, 17), Vector2(w, 34)), 4, BG_DEEP)
	draw_body(ci, at + Vector2(17, 0), 11, String(monster.get("body", "")))
	text_box(ci, Rect2(at + Vector2(35, -16), Vector2(w - 35, 32)), String(monster["ko"]), size, INK, HORIZONTAL_ALIGNMENT_LEFT)
	return w


## Element emblems are small faceted metal inlays, consistent with the real 3D art.
## A circle means attack element; a rounded square means the monster's body.
const ELEM_PX := 32.0

static func draw_elem(ci: CanvasItem, c: Vector2, r: float, e: String) -> void:
	if r < 3.0:
		return
	var col := Balance.elem_color(e)
	ci.draw_circle(c + Vector2(0, 1), r + 2, BG_DEEP, true, -1, true)
	ci.draw_circle(c, r + 1, col.darkened(0.50), true, -1, true)
	ci.draw_circle(c, r, BG_DEEP.lerp(col, 0.10), true, -1, true)
	_element_glyph(ci, c, r * 0.79, e, col)

static func draw_body(ci: CanvasItem, c: Vector2, r: float, body: String) -> void:
	if r < 3.0:
		return
	var col := Balance.body_color(body)
	var box := Rect2(c - Vector2.ONE * (r + 2), Vector2.ONE * (r + 2) * 2)
	fill_round(ci, box, r * 0.21, col.darkened(0.45))
	fill_round(ci, box.grow(-1), r * 0.16, BG_DEEP.lerp(col, 0.08))
	var glyph := String({"aqua": "water", "flame": "fire", "frost": "ice"}.get(body, body))
	_element_glyph(ci, c, r * 0.82, glyph, col)

static func _element_glyph(ci: CanvasItem, c: Vector2, r: float, glyph: String, color: Color) -> void:
	var light := color.lightened(0.36)
	var stroke := maxf(1.1, r * 0.18)
	if glyph == "ice":
		for i in range(6):
			var direction := Vector2.from_angle(i * TAU / 6)
			var normal := direction.orthogonal()
			ci.draw_line(c, c + direction * r, light, stroke, true)
			ci.draw_line(c + direction * r * 0.52, c + direction * r * 0.76 + normal * r * 0.25, color, stroke, true)
			ci.draw_line(c + direction * r * 0.52, c + direction * r * 0.76 - normal * r * 0.25, color, stroke, true)
		return
	if glyph == "none":
		for side in [-1, 1]:
			var tip := c + Vector2(side * 0.72, -0.86) * r
			var hilt := c + Vector2(-side * 0.65, 0.78) * r
			var guard := tip.lerp(hilt, 0.72)
			ci.draw_line(tip, hilt, light, stroke * 1.2, true)
			ci.draw_line(guard + Vector2(-side, -0.75) * r * 0.22, guard + Vector2(side, 0.75) * r * 0.22, GOLD, stroke, true)
		return
	var points := PackedVector2Array()
	match glyph:
		"water":
			points.append(c + Vector2(0, -r * 1.08))
			for i in range(25):
				var angle := lerpf(-0.3, PI + 0.3, i / 24.0)
				points.append(c + Vector2(cos(angle) * r * 0.72, sin(angle) * r * 0.72 + r * 0.20))
		"fire":
			for v in [Vector2(0.22, -1.08), Vector2(0.38, -0.36), Vector2(0.70, -0.55), Vector2(0.83, 0.23), Vector2(0.48, 0.88), Vector2(-0.43, 0.88), Vector2(-0.78, 0.38), Vector2(-0.64, -0.22), Vector2(-0.30, 0.03), Vector2(-0.24, -0.63)]:
				points.append(c + v * r)
		"elec":
			for v in [Vector2(0.20, -1.08), Vector2(-0.72, 0.18), Vector2(-0.09, 0.18), Vector2(-0.26, 1.08), Vector2(0.78, -0.26), Vector2(0.08, -0.26)]:
				points.append(c + v * r)
		"wood":
			for v in [Vector2(0.77, -0.99), Vector2(0.84, -0.03), Vector2(0.38, 0.69), Vector2(-0.35, 0.76), Vector2(-0.78, 0.32), Vector2(-0.66, -0.36)]:
				points.append(c + v * r)
		"rock":
			for v in [Vector2(-0.54, -0.84), Vector2(0.42, -0.94), Vector2(0.87, -0.20), Vector2(0.76, 0.72), Vector2(-0.63, 0.85), Vector2(-0.91, 0.10)]:
				points.append(c + v * r)
		_:
			points = star_points(c, r, 0.48)
	ci.draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	ci.draw_polyline(outline, light, maxf(0.7, stroke * 0.46), true)
	if glyph == "wood":
		ci.draw_line(c + Vector2(-0.76, 0.95) * r, c + Vector2(0.55, -0.68) * r, light, stroke, true)
	elif glyph == "rock":
		var facet := c + Vector2(-0.12, -0.05) * r
		ci.draw_colored_polygon(PackedVector2Array([points[0], points[1], facet, points[4]]), Color(light, 0.72))
	else:
		ci.draw_line(c + Vector2(-0.22, -0.12) * r, c + Vector2(-0.29, 0.40) * r, Color(light, 0.82), stroke, true)


## **면역**을 나타내는 글리프. 속성 동그라미에 어두운 빗금 하나를 긋는다.
##
## ★ 왜 따로 두는가: 바위 몸은 전기를 **아예 안 받는다**(0배). 약점만 보여 주고 면역을
##   안 보여 주면 전기 영웅을 세운 사람이 그 열 탄을 통째로 잃고도 왜 그랬는지 모른다.
## ★ 「×」(U+00D7)를 쓰지 마라 — 번들 폰트에 없다(CLAUDE.md 6번). 도형으로 긋는다.
static func draw_elem_x(ci: CanvasItem, c: Vector2, r: float, e: String) -> void:
	if r < 3.0:
		return
	draw_elem(ci, c, r, e)
	var d := r * 0.86
	ci.draw_line(c + Vector2(-d, -d), c + Vector2(d, d), BG_DEEP, maxf(2.0, r * 0.42))
	ci.draw_line(c + Vector2(-d, -d), c + Vector2(d, d), Color(1, 1, 1, 0.85), maxf(1.0, r * 0.20))


## 체력 막대의 색. 넉넉하면 초록, 반쯤이면 금색, 얼마 안 남으면 빨강.
##
## ★ 세 토막으로 딱 끊지 않고 이어서 섞는다. 끊어 두면 34%와 36%가 전혀 다른 색이라
##   "얼마나 남았나"가 아니라 "어느 칸에 들어갔나"로 읽힌다 — 막대를 두는 뜻이 없어진다.
static func hp_color(k: float) -> Color:
	if k > 0.5:
		return GOLD.lerp(GREEN, clampf((k - 0.5) * 2.0, 0.0, 1.0))
	return RED.lerp(GOLD, clampf(k * 2.0, 0.0, 1.0))


## 모서리가 둥근 사각형을 채운다. Godot 에는 이 기본 함수가 없다.
static var _surface_cache: Dictionary = {}

static func _surface(color: Color, radius: float) -> StyleBoxFlat:
	var key := "%s:%.1f" % [color.to_html(), radius]
	if not _surface_cache.has(key):
		if _surface_cache.size() >= 512:
			_surface_cache.clear()
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(roundi(radius))
		style.corner_detail = 8
		style.anti_aliasing = true
		_surface_cache[key] = style
	return _surface_cache[key]

static func fill_round(ci: CanvasItem, rect: Rect2, r: float, col: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var radius := minf(r * 1.6, minf(rect.size.x, rect.size.y) * 0.5)
	ci.draw_style_box(_surface(col, radius), rect)

## A quiet metal face with a cool rim, warm inlay and a cast shadow.
## The legacy material argument remains so old screens share this surface too.
static func material_panel(ci: CanvasItem, rect: Rect2, face: Color = PANEL,
		edge: Color = PANEL_EDGE, _material: String = "metal") -> void:
	fill_round(ci, Rect2(rect.position + Vector2(0, 5), rect.size), 9, Color(0.01, 0.02, 0.035, 0.60))
	fill_round(ci, rect, 9, edge.darkened(0.35))
	fill_round(ci, rect.grow(-1), 8.5, face)
	fill_round(ci, Rect2(rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, minf(24, rect.size.y * 0.22))), 8, Color(face.lightened(0.15), 0.24))
	ci.draw_line(rect.position + Vector2(16, 2), Vector2(rect.end.x - 16, rect.position.y + 2), Color(edge.lightened(0.35), 0.64), 1, true)
	ci.draw_line(Vector2(rect.position.x + 16, rect.end.y - 2), rect.end - Vector2(16, 2), Color(BG_DEEP, 0.70), 1, true)

static func camp_backdrop(ci: CanvasItem) -> void:
	StellarBackdrop.draw(ci, SCREEN, Run.theme_for(Run.wave), 0.0, true)


static func outline_round(ci: CanvasItem, rect: Rect2, r: float, col: Color, w: float) -> void:
	fill_round(ci, rect.grow(w), r + w, col)


## 네 모서리에 ㄱ자 꺾쇠를 친다 — 「골랐다」를 속성·등급 줄을 안 가리고 말하는 표시.
## 영웅 카드(HeroCard)와 투기장 발판(Battlefield.draw_post)이 같은 꺾쇠를 쓴다.
static func draw_brackets(ci: CanvasItem, rect: Rect2, len_px: float, col: Color,
		width: float = 3.0) -> void:
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]:
		var dx := 1.0 if corner.x == rect.position.x else -1.0
		var dy := 1.0 if corner.y == rect.position.y else -1.0
		ci.draw_line(corner, corner + Vector2(dx * len_px, 0), col, width)
		ci.draw_line(corner, corner + Vector2(0, dy * len_px), col, width)


## 크리스탈 하나. alive 가 거짓이면 깨진 자리를 어둡게 남긴다.
##
## Faceted crystal shares the silhouette and lighting of the real 3D altar.
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


## 캐릭터 이름은 선택 언어에 따라 원래 영문명 또는 기존 한글 음차로 표시한다.
##
## ★ 왜 함수로 두는가: 이름이 뜨는 곳이 여섯 군데다(전장 판·전당 판·전투 목록·확정
##   연출·설명 팝업·전과 판). 여섯 곳에서 저마다 u["en"] 을 읽으면 언젠가 한 곳이
##   u["ko"] 로 남아, 한 화면에서만 이름이 다른 게임이 된다.
static func unit_name(u: Dictionary) -> String:
	return I18n.hero_name(String(u.get("id", "")))


## 데이터·개발 도구에서 사용하는 캐릭터의 한글 음차 이름.
static func unit_ko(u: Dictionary) -> String:
	return String(u.get("ko", ""))


## 주어진 폭에 **들어갈 때까지 글자를 줄여** 가운데 정렬로 그린다.
##
## ★ 영문 이름은 한글보다 길다(「Thunderthrone」 13자). 칸 폭에 맞춰 크기를 못 박아 두면
##   전당 칸이 좁아지는 후반에 이름이 옆 칸까지 흘러넘친다 — 예전에 「스트레이트플러시」로
##   똑같은 일을 겪었다(CLAUDE.md 10-6).
static func text_center_fit(ci: CanvasItem, pos: Vector2, s: String, size: int,
		col: Color, max_w: float, min_size: int = 9) -> int:
	s = I18n.t(s)
	var sz := fit_size(s, size, Vector2(max_w, 1000), min_size)
	_audit_box(s, Rect2(pos - Vector2(max_w * 0.5, font(sz).get_height(sz) * 0.5), Vector2(max_w, font(sz).get_height(sz))), sz)
	text_center(ci, pos, s, sz, col)
	return sz


## Boxed copy is measured after translation, in both axes, without dropping letters.
static func fit_size(s: String, size: int, area: Vector2, _preferred_min: int = 12) -> int:
	var fitted := size
	while fitted > 1 and (text_width(s, fitted) > area.x or font(fitted).get_height(fitted) > area.y):
		fitted -= 1
	return fitted


static func text_box(ci: CanvasItem, box: Rect2, s: String, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> int:
	var fitted := fit_size(s, size, box.size)
	_audit_box(I18n.t(s), box, fitted)
	match align:
		HORIZONTAL_ALIGNMENT_LEFT:
			text_left(ci, Vector2(box.position.x, box.get_center().y), s, fitted, col)
		HORIZONTAL_ALIGNMENT_RIGHT:
			text_right(ci, Vector2(box.end.x, box.get_center().y), s, fitted, col)
		_:
			text_center(ci, box.get_center(), s, fitted, col)
	return fitted


## Opt-in measurements used by the real-render audit; disabled during normal play.
static var text_audit_enabled := false
static var text_audit: Array[Dictionary] = []
static var raw_text_audit: Array[Dictionary] = []

static func _audit_box(s: String, box: Rect2, size: int, lines: int = 1) -> void:
	if text_audit_enabled:
		text_audit.append({"text": I18n.t(s), "box": box, "size": size, "lines": lines,
			"width": text_width(s, size) if lines == 1 else 0.0,
			"height": font(size).get_height(size) if lines == 1 else line_height(size) * lines})


static func _audit_raw(ci: CanvasItem, s: String, top_left: Vector2, size: int) -> void:
	if text_audit_enabled and not s.is_empty():
		raw_text_audit.append({"text": s, "rect": Rect2(top_left, Vector2(text_width(s, size), font(size).get_height(size))),
			"size": size, "canvas": ci.get_script().resource_path if ci.get_script() != null else ""})


static var _font: Font = null

static func font(_size: int = 24) -> Font:
	# 제목·본문·영문·숫자에 같은 글꼴을 써서 크기가 바뀌어도 모양이 달라지지 않는다.
	if _font == null:
		_font = load("res://core/fonts/RefugeSans-Bold.otf")
	return _font


static func _baseline(f: Font, pos: Vector2, size: int) -> Vector2:
	return (pos + Vector2(0, (f.get_ascent(size) - f.get_descent(size)) * 0.5)).round()


## 가운데 정렬 글자. 화면마다 같은 계산을 반복하지 않으려고 뺐다.
static func text_center(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color) -> void:
	s = I18n.t(s)
	var f := font(size)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_audit_raw(ci, s, pos - Vector2(w * 0.5, f.get_height(size) * 0.5), size)
	ci.draw_string(f, _baseline(f, pos - Vector2(w * 0.5, 0), size), s,
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
	s = I18n.t(s)
	var f := font(size)
	_audit_raw(ci, s, pos - Vector2(0, f.get_height(size) * 0.5), size)
	ci.draw_string(f, _baseline(f, pos, size), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_right(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color) -> void:
	s = I18n.t(s)
	var f := font(size)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_audit_raw(ci, s, pos - Vector2(w, f.get_height(size) * 0.5), size)
	ci.draw_string(f, _baseline(f, pos - Vector2(w, 0), size), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_width(s: String, size: int) -> float:
	s = I18n.t(s)
	return font(size).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 합성 전용 각성 수호자의 금색 표식 — 여섯 모 방패 안의 별.
##
## ★ 포커 시절에는 여기에 패의 숫자를 적은 「숫자 방패 문장」이 있었다. 별맞춤 의식으로
##   바뀌면서 패의 숫자가 없어졌으므로 숫자 문장은 폐기했다. 남은 것은 「이 영웅은 합성으로만
##   만나는 각성 수호자」라는 표시 하나다 — 뽑기로 얻은 영웅에는 아무것도 안 그린다.
static func draw_awakened_mark(ci: CanvasItem, center: Vector2, hero: Dictionary, radius: float = 14) -> void:
	if not bool(hero.get("awakened", false)) and not bool((hero.get("unit", {}) as Dictionary).get("fusion_only", false)):
		return
	var points := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, -radius * 0.35), center + Vector2(radius * 0.72, radius * 0.67), center + Vector2(0, radius), center + Vector2(-radius * 0.72, radius * 0.67), center + Vector2(-radius, -radius * 0.35)])
	ci.draw_colored_polygon(points, BG_DEEP)
	points.append(points[0])
	ci.draw_polyline(points, GOLD, 2, false)
	ci.draw_colored_polygon(star_points(center + Vector2(0, radius * 0.04), radius * 0.60), GOLD)


# --------------------------------------------------------------------------- #
# 패시브 카드 — 「무기·아이템 없이 패시브만」이 되면서 상점의 얼굴이 됐다
# --------------------------------------------------------------------------- #
## 패시브 문양 한 장이 저장된 크기(정사각). Look 이 이 값으로 배율을 낸다 —
## 그림은 art/ui/pi_<패시브id>.png 이고 tools/gen_art.py 가 96x96 으로 찍는다.
const PASSIVE_ICON_PX := 96.0

## 패시브 문양 하나. **그림이 먼저고 도형이 되돌림 길이다**(CLAUDE.md 10-12).
##
## ★ **icon 이 아니라 패시브 id 로 찾는다.** 그림은 스물여섯 장, 패시브 하나마다 한 장이다.
##   icon 이름으로 찾으면 「예리한 촉」과 「처형인의 눈」이 blade 한 장을 나눠 쓰는데,
##   도형으로 그리던 시절에는 tint 색이 그 둘을 갈라 줬지만 **그림은 제 색을 갖고 오므로**
##   그 구별이 통째로 사라진다. 화면에 같은 카드가 두 장 서는 셈이다.
## ★ **그림에 tint 를 덮어씌우지 않는다.** 스물여섯 장이 저마다 제 색으로 뽑혀 있어서
##   modulate 로 곱하면 그 색이 통째로 물든다. tint 는 카드 테두리·이름·도형 되돌림 길이
##   계속 쓴다.
## ★ 그림이 **없어도 게임이 돌아야 한다.** Art.draw_at 이 거짓을 돌려주면 아래 도형 코드가
##   그대로 그린다 — 이 코드를 지우지 마라(그림 스물여섯 장은 GPU 로 서른 분이다).
static func draw_passive_icon(ci: CanvasItem, c: Vector2, r: float, p: Dictionary,
		col: Color) -> void:
	if r < 3.0:
		return
	var path := String(Roster.ART.get("pi_" + String(p.get("id", "")), ""))
	# 세로 가운데를 c 에 맞춘다 — Art.draw_at 은 **발밑**을 기준으로 놓으므로 c.y + r 이다.
	if Art.draw_at(ci, path, c.x, c.y + r, r * 2.0 / PASSIVE_ICON_PX):
		return
	var icon := String(p.get("icon", ""))
	var dim := Color(col.r, col.g, col.b, 0.45)
	match icon:
		"gear":
			ci.draw_arc(c, r * 0.72, 0.0, TAU, 20, col, r * 0.26, true)
			for i in range(6):
				var a: float = TAU * float(i) / 6.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.62,
						c + Vector2(cos(a), sin(a)) * r, col, r * 0.22, true)
		"arc":
			ci.draw_arc(c + Vector2(r * 0.35, 0), r * 0.95, 2.2, 4.1, 16, col, r * 0.20, true)
			ci.draw_line(c + Vector2(r * 0.35, -r * 0.8), c + Vector2(r * 0.35, r * 0.8),
					dim, r * 0.10, true)
			ci.draw_line(c - Vector2(r, 0), c + Vector2(r * 0.7, 0), col, r * 0.14, true)
		"spike":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r * 0.55, r * 0.3),
				c + Vector2(0, r * 0.05), c + Vector2(-r * 0.55, r * 0.3)]), col)
			ci.draw_rect(Rect2(c.x - r * 0.16, c.y + r * 0.1, r * 0.32, r * 0.9), dim)
		"eye":
			ci.draw_arc(c, r * 0.9, -0.9, 0.9 + PI, 20, col, r * 0.16, true)
			ci.draw_circle(c, r * 0.42, col)
			ci.draw_circle(c, r * 0.18, BG_DEEP)
		"coin":
			ci.draw_circle(c, r * 0.9, col)
			ci.draw_circle(c, r * 0.62, Color(col.r, col.g, col.b, 0.35))
			text_center(ci, c, "G", int(r * 1.1), BG_DEEP)
		"flag":
			ci.draw_rect(Rect2(c.x - r * 0.8, c.y - r, r * 0.22, r * 2.0), dim)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.58, -r * 0.9), c + Vector2(r * 0.9, -r * 0.45),
				c + Vector2(-r * 0.58, 0.0)]), col)
		"card":
			for i in range(3):
				var o := Vector2(float(i - 1) * r * 0.34, -absf(float(i - 1)) * r * 0.14)
				var rr := Rect2(c + o - Vector2(r * 0.34, r * 0.72), Vector2(r * 0.68, r * 1.44))
				fill_round(ci, rr.grow(r * 0.07), r * 0.16, BG_DEEP)
				fill_round(ci, rr, r * 0.14, col if i == 1 else dim)
		"snow":
			for i in range(6):
				var a2: float = PI * float(i) / 6.0
				var d := Vector2(cos(a2), sin(a2)) * r
				ci.draw_line(c - d, c + d, col, r * 0.16, true)
			ci.draw_circle(c, r * 0.22, col)
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r * 0.7, r * 0.1),
				c + Vector2(r * 0.42, r * 0.9), c + Vector2(-r * 0.42, r * 0.9),
				c + Vector2(-r * 0.7, r * 0.1)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.28), c + Vector2(r * 0.34, r * 0.35),
				c + Vector2(0, r * 0.85), c + Vector2(-r * 0.34, r * 0.35)]),
				Color(1, 1, 1, 0.55))
		"arrow":
			ci.draw_line(c + Vector2(-r * 0.9, r * 0.5), c + Vector2(r * 0.6, -r * 0.35),
					dim, r * 0.20, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(r, -r * 0.6), c + Vector2(r * 0.25, -r * 0.55),
				c + Vector2(r * 0.62, 0.05)]), col)
		"burst":
			for i in range(8):
				var a3: float = TAU * float(i) / 8.0
				ci.draw_line(c + Vector2(cos(a3), sin(a3)) * r * 0.3,
						c + Vector2(cos(a3), sin(a3)) * r, col, r * 0.16, true)
			ci.draw_circle(c, r * 0.3, col)
		"ring":
			ci.draw_arc(c, r * 0.95, 0.0, TAU, 24, dim, r * 0.14, true)
			ci.draw_arc(c, r * 0.60, 0.0, TAU, 20, col, r * 0.16, true)
			ci.draw_circle(c, r * 0.22, col)
		"rage":
			for i in range(3):
				var x2: float = c.x + float(i - 1) * r * 0.62
				ci.draw_colored_polygon(PackedVector2Array([
					Vector2(x2, c.y - r), Vector2(x2 + r * 0.26, c.y + r * 0.2),
					Vector2(x2, c.y + r), Vector2(x2 - r * 0.26, c.y + r * 0.2)]),
					col if i == 1 else dim)
		"blade":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.2, -r), c + Vector2(r * 0.3, -r * 0.8),
				c + Vector2(r * 0.1, r * 0.4), c + Vector2(-r * 0.3, r * 0.4)]), col)
			ci.draw_rect(Rect2(c.x - r * 0.6, c.y + r * 0.36, r * 1.2, r * 0.2), dim)
		"skull":
			ci.draw_circle(c + Vector2(0, -r * 0.16), r * 0.8, col)
			ci.draw_rect(Rect2(c.x - r * 0.4, c.y + r * 0.44, r * 0.8, r * 0.4), col)
			ci.draw_circle(c + Vector2(-r * 0.32, -r * 0.2), r * 0.22, BG_DEEP)
			ci.draw_circle(c + Vector2(r * 0.32, -r * 0.2), r * 0.22, BG_DEEP)
		"crown":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r, r * 0.5), c + Vector2(-r * 0.8, -r * 0.7),
				c + Vector2(-r * 0.35, r * 0.0), c + Vector2(0, -r * 0.9),
				c + Vector2(r * 0.35, r * 0.0), c + Vector2(r * 0.8, -r * 0.7),
				c + Vector2(r, r * 0.5)]), col)
			ci.draw_rect(Rect2(c.x - r, c.y + r * 0.45, r * 2.0, r * 0.34), dim)
		"spark":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.1, -r), c + Vector2(-r * 0.55, r * 0.12),
				c + Vector2(-r * 0.05, r * 0.12), c + Vector2(-r * 0.15, r),
				c + Vector2(r * 0.6, -r * 0.1), c + Vector2(r * 0.08, -r * 0.1)]), col)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r * 0.85, -r * 0.55),
				c + Vector2(r * 0.6, r * 0.6), c + Vector2(0, r),
				c + Vector2(-r * 0.6, r * 0.6), c + Vector2(-r * 0.85, -r * 0.55)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.55), c + Vector2(r * 0.42, -r * 0.3),
				c + Vector2(0, r * 0.5), c + Vector2(-r * 0.42, -r * 0.3)]),
				Color(1, 1, 1, 0.42))
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.15, -r), c + Vector2(-r * 0.6, r * 0.1),
				c + Vector2(-r * 0.1, r * 0.1), c + Vector2(-r * 0.2, r),
				c + Vector2(r * 0.62, -r * 0.15), c + Vector2(r * 0.1, -r * 0.15)]), col)
		"chain":
			for i in range(2):
				var o2 := Vector2(float(i) * r * 0.7 - r * 0.35, float(i) * r * 0.5 - r * 0.25)
				ci.draw_arc(c + o2, r * 0.48, 0.0, TAU, 16, col if i == 0 else dim,
						r * 0.18, true)
		"wildfire":
			for i in range(3):
				var o3 := Vector2(float(i - 1) * r * 0.66, absf(float(i - 1)) * r * 0.28)
				ci.draw_colored_polygon(PackedVector2Array([
					c + o3 + Vector2(0, -r * 0.8), c + o3 + Vector2(r * 0.4, r * 0.1),
					c + o3 + Vector2(0, r * 0.7), c + o3 + Vector2(-r * 0.4, r * 0.1)]),
					col if i == 1 else dim)
		"rune":
			ci.draw_arc(c, r * 0.9, 0.0, TAU, 6, col, r * 0.16, true)
			ci.draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.7), col, r * 0.14, true)
			ci.draw_line(c + Vector2(-r * 0.5, -r * 0.2), c + Vector2(r * 0.5, -r * 0.2),
					col, r * 0.14, true)
		"yin":
			ci.draw_circle(c, r * 0.92, dim)
			ci.draw_arc(c, r * 0.92, -PI * 0.5, PI * 0.5, 18, col, r * 0.9, false)
			ci.draw_circle(c + Vector2(0, -r * 0.46), r * 0.46, col)
			ci.draw_circle(c + Vector2(0, r * 0.46), r * 0.46, dim)
		"echo":
			for i in range(3):
				ci.draw_arc(c, r * (0.34 + 0.3 * float(i)), 0.0, TAU, 20,
						Color(col.r, col.g, col.b, 0.9 - 0.25 * float(i)), r * 0.14, true)
		"joker":
			# ★ 예전에는 이 갈래가 통째로 없었다. balance.gd 의 조커는 "icon": "joker" 인데
			#   match 에 자리가 없어서 **조용히 아무것도 안 그렸다** — 상점에 문양 없는
			#   카드가 한 장 섞여 있었고, ns_check 는 icon 이 비었는지만 봐서 못 잡았다.
			#   광대 모자 셋과 방울 셋.
			for i in range(3):
				var ja: float = -PI * 0.5 + (float(i) - 1.0) * 0.85
				var tip := c + Vector2(cos(ja), sin(ja)) * r
				ci.draw_colored_polygon(PackedVector2Array([
						c + Vector2(-r * 0.55, r * 0.35), tip, c + Vector2(r * 0.55, r * 0.35)]),
						col if i == 1 else dim)
				ci.draw_circle(tip, r * 0.18, col)
			ci.draw_rect(Rect2(c.x - r * 0.8, c.y + r * 0.3, r * 1.6, r * 0.36), col)
		"dice":
			var d2 := Rect2(c - Vector2(r * 0.82, r * 0.82), Vector2(r * 1.64, r * 1.64))
			fill_round(ci, d2, r * 0.28, col)
			for q in [Vector2(-0.4, -0.4), Vector2(0.4, 0.4), Vector2(0, 0)]:
				ci.draw_circle(c + q * r * 1.3, r * 0.17, BG_DEEP)
		_:
			# joker 그 밖 — 방울 셋 달린 고깔.
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, r * 0.9), c + Vector2(-r, -r * 0.5), c + Vector2(0, -r * 0.1),
				c + Vector2(r, -r * 0.5)]), col)
			ci.draw_circle(c + Vector2(-r, -r * 0.5), r * 0.24, dim)
			ci.draw_circle(c + Vector2(r, -r * 0.5), r * 0.24, dim)


## 패시브 한 장을 **카드 모양**으로 그린다. 상점이 이 한 함수로 진열을 만든다.
##
## ★ 사용자가 정한 것: 「패시브도 카드 형태로 일러스트해서 이쁘게」. 영웅 카드와 같은
##   카드 모양이라, 상점의 진열이 「내가 쥘 수 있는 것」으로 읽힌다.
## ★ 등급(rank)은 **테두리 겹 수**로 말한다. 색만으로 두면 스물여섯 장 사이에서
##   어느 것이 귀한지가 안 읽힌다.
static func draw_passive_card(ci: CanvasItem, r: Rect2, p: Dictionary, owned: bool,
		can: bool, glow: float = 0.0) -> void:
	var tint := Color(String(p.get("tint", "#edc879")))
	var rank := int(p.get("rank", 1))
	var g: float = PX
	var edge: Color = CRYSTAL if owned else (tint if can else PANEL_EDGE)
	px_panel(ci, r.grow(g), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.5))
	material_panel(ci, r, PANEL.lerp(tint, 0.10 + glow * 0.35), edge)
	# 귀한 카드일수록 테두리를 한 겹씩 더 두른다.
	for i in range(rank - 1):
		var ir := r.grow(-g * (2.0 + float(i) * 1.2))
		ci.draw_rect(Rect2(ir.position, Vector2(ir.size.x, g)), Color(tint.r, tint.g, tint.b, 0.5))
		ci.draw_rect(Rect2(ir.position + Vector2(0, ir.size.y - g), Vector2(ir.size.x, g)),
				Color(tint.r, tint.g, tint.b, 0.5))
	# 문양 — 카드 위쪽 절반을 통째로 쓴다.
	var ic := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.34)
	var ir2: float = minf(r.size.x * 0.24, r.size.y * 0.22)
	ci.draw_circle(ic, ir2 * 1.5, Color(BG_DEEP.r, BG_DEEP.g, BG_DEEP.b, 0.55))
	draw_passive_icon(ci, ic, ir2, p, tint)
	# 이름과 설명
	var nm := String(p.get("ko", ""))
	text_center_fit(ci, Vector2(r.position.x + r.size.x * 0.5,
			r.position.y + r.size.y * 0.60), nm, 23, INK if not owned else CRYSTAL,
			r.size.x - 16.0, 14)
	var desc := String(p.get("desc", ""))
	var desc_box := Rect2(r.position.x + 9.0, r.position.y + r.size.y * 0.67,
			r.size.x - 18.0, r.size.y * 0.30)
	var desc_size := 15
	while desc_size > 12 and wrapped_lines(desc, desc_box.size.x, desc_size).size() > 2:
		desc_size -= 1
	wrap_text(ci, desc, desc_box, desc_size, INK_DIM)


## 긴 어절과 명시적인 줄바꿈도 처리한다. 폭 측정과 실제 그리기가 같은 글꼴을 쓴다.
static func wrapped_lines(s: String, width: float, size: int) -> Array[String]:
	s = I18n.t(s)
	var lines: Array[String] = []
	var line := ""
	for paragraph in s.split("\n"):
		line = ""
		for word in paragraph.split(" ", false):
			var joined: String = word if line.is_empty() else line + " " + word
			if text_width(joined, size) <= width:
				line = joined
				continue
			if not line.is_empty():
				lines.append(line)
			line = ""
			for ch in word:
				if not line.is_empty() and text_width(line + ch, size) > width:
					lines.append(line)
					line = ""
				line += ch
		lines.append(line)
	return lines


static func line_height(size: int) -> float:
	return ceilf(font(size).get_height(size)) + 3.0


## 글자의 중심이 아니라 줄 전체 높이로 경계를 검사한다. 마지막 줄도 칸 안에 둔다.
static func wrap_text(ci: CanvasItem, s: String, box: Rect2, size: int, col: Color,
		left: bool = false) -> void:
	var lines := wrapped_lines(s, box.size.x, size)
	while size > 1 and lines.size() * line_height(size) > box.size.y:
		size -= 1
		lines = wrapped_lines(s, box.size.x, size)
	var step := line_height(size)
	var count := lines.size()
	_audit_box(s, box, size, count)
	for i in range(count):
		var line: String = lines[i]
		var y := box.position.y + step * (float(i) + 0.5)
		if left:
			text_left(ci, Vector2(box.position.x, y), line, size, col)
		else:
			text_center(ci, Vector2(box.get_center().x, y), line, size, col)

## Frosted blue glass for the continuous arena HUD. Text stays native and crisp.
static func glass_panel(ci: CanvasItem, rect: Rect2, edge: Color = PANEL_EDGE,
		face: Color = Color(0.035, 0.09, 0.13, 0.82), selected: bool = false) -> void:
	var p := rect.position
	var e := rect.end
	var cut := 5.0
	var shape := PackedVector2Array([p + Vector2(cut, 0), Vector2(e.x - cut, p.y),
		Vector2(e.x - cut, p.y + 3), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y - 3), e - Vector2(cut, 0), Vector2(p.x + cut, e.y),
		Vector2(p.x + cut, e.y - 3), Vector2(p.x, e.y - cut), p + Vector2(0, cut), p + Vector2(cut, 3)])
	ci.draw_colored_polygon(shape, face)
	ci.draw_polyline(shape + PackedVector2Array([shape[0]]), Color(edge, 0.95 if selected else 0.70), 1.6 if selected else 1.0, true)
	ci.draw_line(p + Vector2(9, 2), Vector2(e.x - 9, p.y + 2), Color(edge.lightened(0.35), 0.62), 1, true)
	ci.draw_line(Vector2(p.x + 9, e.y - 2), e - Vector2(9, 2), Color(edge, 0.26), 1, true)
	for n in range(9):
		ci.draw_line(p + Vector2(7, 4 + n), Vector2(e.x - 7, p.y + 4 + n), Color(edge, (0.045 if selected else 0.020) * (1 - n / 9.0)), 1)
	if selected:
		for side in [-1, 1]:
			var x: float = rect.get_center().x + side * (rect.size.x * 0.5 - 3)
			ci.draw_circle(Vector2(x, p.y + 7), 1.8, edge.lightened(0.35))
