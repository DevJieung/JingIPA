extends RefCounted
class_name Look

## 색 · 글꼴 · 카드 그리기. 화면들이 저마다 색을 짓지 않게 여기 한곳에 모은다.
##
## 도트 그림과 UI 소재는 Krea로, 읽어야 하는 글자와 카드 무늬는 코드로 그린다.
## 카드는 숫자가 또렷해야 하는데 96px 도트로 뽑으면 J 와 Q 가 구별이 안 됐다.

# 밤의 도박장. 배경은 아주 어둡게 깔고 카드와 금색만 튀게 한다.
const BG        := Color("#101b20")
const BG_DEEP   := Color("#0a1117")
const PANEL     := Color("#233033")
const PANEL_EDGE := Color("#746347")
const FELT      := Color("#123527")   ## 카드 테이블의 초록 천
const FELT_EDGE := Color("#0a2018")

const INK       := Color("#f4efe4")   ## 밝은 글자
const INK_DIM   := Color("#c8d2cb")
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
const YARD       := Color("#123527")   ## 영웅이 선 전장(초록 천)
const GATE       := Color("#f6c445")   ## 문
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
const DMG_NORMAL := Color("#f4efe4")   ## 보통 — 흰 글자와 같은 색
const DMG_RESIST := Color("#847bA2")   ## 반감 — 식은 잿빛

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

## 화면 전체. 덮개·섬광·터치 자리처럼 「화면 통째로」를 뜻하는 곳이 전부 이것을 쓴다.
const SCREEN := Rect2(0, 0, 1280, 800)

## 도트 한 칸의 크기. 카드와 포커 화면의 도형을 **이 격자에 맞춰** 그린다.
## ★ 사용자가 정한 것: 「포커하는 화면도 2D 픽셀로, 디자인적으로 이질감이 안 느껴지게」.
##   캐릭터·몬스터는 96~141px 도트 그림이라 한 칸이 대략 3~4px 로 보인다. 카드만
##   매끈한 벡터로 그리면 같은 화면 안에서 **다른 게임 두 개**처럼 보인다.
const PX := 4.0

## 좌표를 도트 격자에 맞춘다. 반올림이 아니라 **내림**이다 — 반올림하면 같은 도형이
## 프레임마다 한 칸씩 튄다(카드가 숨 쉬듯 떠 있어서 좌표가 늘 소수다).
static func snap(v: float, g: float = PX) -> float:
	return floor(v / g) * g


static func snap_v(v: Vector2, g: float = PX) -> Vector2:
	return Vector2(snap(v.x, g), snap(v.y, g))


static func snap_rect(r: Rect2, g: float = PX) -> Rect2:
	var a := snap_v(r.position, g)
	var b := snap_v(r.position + r.size + Vector2(g - 0.01, g - 0.01), g)
	return Rect2(a, b - a)


## 도트 판때기 — 계단 모서리 · 두꺼운 테두리 · 위쪽 하이라이트.
## ★ 둥근 모서리(fill_round)는 원을 네 개 그려서 매끈하다. 도트 화면에서는 그것이
##   곧 이질감이라, 모서리를 **한 칸씩 깎은 팔각**으로 만든다.
static func px_panel(ci: CanvasItem, rect: Rect2, face: Color, edge: Color,
		lip: float = 0.0) -> void:
	var r := snap_rect(rect)
	var g := PX
	# 테두리 — 바깥으로 한 칸.
	ci.draw_rect(Rect2(r.position + Vector2(g, 0), Vector2(r.size.x - g * 2.0, r.size.y)), edge)
	ci.draw_rect(Rect2(r.position + Vector2(0, g), Vector2(r.size.x, r.size.y - g * 2.0)), edge)
	var i := Rect2(r.position + Vector2(g, g), r.size - Vector2(g * 2.0, g * 2.0))
	ci.draw_rect(Rect2(i.position + Vector2(g, 0), Vector2(i.size.x - g * 2.0, i.size.y)), face)
	ci.draw_rect(Rect2(i.position + Vector2(0, g), Vector2(i.size.x, i.size.y - g * 2.0)), face)
	if lip > 0.0:
		# 위쪽 한 줄만 밝게 — 이 한 줄이 있어야 납작한 네모가 아니라 판때기로 보인다.
		ci.draw_rect(Rect2(i.position + Vector2(g, g), Vector2(i.size.x - g * 2.0, g)),
				face.lightened(lip))

## 좁은 칸에 쓰는 짧은 등급 이름. 인덱스는 Poker.Hand 값과 같다.
##
## ★ 왜 Roster.TIER_KO 를 그냥 안 쓰는가: 「스트레이트플러시」는 여덟 자라, 전당
##   칸이 좁아지면(94px) 이름 하나가 칸을 넘어 옆 칸까지 흘러넘친다. 등급은 **어디서나
##   보여야 하는 것**이라 좁은 자리용 이름을 따로 둔다. 색(TIER_COLOR)이 늘 같이 붙으므로
##   줄인 이름만으로도 어느 등급인지 헷갈리지 않는다.
const TIER_SHORT := ["하이", "원페어", "투페어", "트리플", "스트레", "플러시",
	"풀하우스", "포카드", "스트플", "로열"]

static func tier_color(t: int) -> Color:
	return TIER_COLOR[clampi(t, 0, TIER_COLOR.size() - 1)]


static func tier_short(t: int) -> String:
	return TIER_SHORT[clampi(t, 0, TIER_SHORT.size() - 1)]


## 영웅 카드의 바탕과 테두리는 공격 속성만 따른다. 등급은 별로, 선택은 꺾쇠로 읽는다.
static func hero_card_face(element: String) -> Color:
	return BG_DEEP.lerp(Balance.elem_color(element), 0.20)


static func hero_card_edge(element: String) -> Color:
	return Balance.elem_color(element).darkened(0.12)


static func hero_card_panel(ci: CanvasItem, rect: Rect2, element: String) -> void:
	fill_round(ci, rect, 5, hero_card_edge(element))
	fill_round(ci, rect.grow(-3), 4, hero_card_face(element))


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


## 캐릭터의 **레어 등급표**. 등급 색으로 꽉 채운 알약 안에 등급 이름을 적는다.
##
## ★ 왜 색 막대만으로 안 두는가: 색만 있으면 "저 보라색이 스트레이트였나 플러시였나"를
##   외워야 한다. 열 등급이나 되는 게임에서 그건 아무도 안 외운다. 글자가 같이 있어야
##   색이 **이름을 부르는 표시**가 되고, 그제서야 색만 봐도 등급이 읽히기 시작한다.
## ★ 글자를 어두운 색(BG_DEEP)으로 쓰는 이유: 등급 색은 높을수록 밝다(로열은 흰 금빛).
##   밝은 바탕에 밝은 글자를 얹으면 제일 귀한 등급이 제일 안 읽힌다.
##
## 돌려주는 것: 실제로 그린 폭(px). 옆에 무언가를 이어 그릴 때 쓴다.
static func draw_tier_chip(ci: CanvasItem, at: Vector2, tier: int, size: int = 18,
		full: bool = false) -> float:
	var s: String = tier_name(tier, full)
	var w := tier_chip_w(tier, size, full)
	var h := float(size) + 8.0
	var r := Rect2(at.x, at.y - h * 0.5, w, h)
	fill_round(ci, r.grow(1.5), h * 0.5 + 1.5, BG_DEEP)
	fill_round(ci, r, h * 0.5, tier_color(tier))
	text_center(ci, Vector2(at.x + w * 0.5, at.y), s, size, BG_DEEP)
	return w


static func tier_name(tier: int, full: bool = false) -> String:
	return Roster.TIER_KO[clampi(tier, 0, 9)] if full else tier_short(tier)


## 등급표를 그리면 얼마나 넓어지는가. **오른쪽 끝에 맞춰 놓을 때** 미리 재는 데 쓴다.
static func tier_chip_w(tier: int, size: int = 18, full: bool = false) -> float:
	return text_width(tier_name(tier, full), size) + float(size)


## 속성을 한 글자로. 칸이 40px 도 안 되는 자리에 「무상성」을 쓸 수는 없다.
##
## ★ 지금은 **그림이 먼저다**(아래 ELEM_ART). 이 글자는 그림이 없을 때의 되돌림 길이다 —
##   지우지 마라(CLAUDE.md 18-1·10-12 와 같은 규칙).
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


## 속성 아이콘 그림. **공격 속성 다섯**과 **몸 다섯**이 그림 일곱 장을 나눠 쓴다 —
## 물몸(aqua)과 물 공격은 같은 물방울이고, 나무·바위는 공격 속성이 없어서 저만 쓴다.
##
## ★ 사용자가 정한 것: 「불 물 이런식으로 말고 아이콘으로 표기해줘 이것도 이미지생성해서」.
## ★ **몸과 공격을 같은 그림으로 두는 것이 맞다.** 불 아이콘 옆에 불 아이콘이 서면
##   그것이 곧 「불은 불에 반만 들어간다」라서, 그림 두 벌을 따로 뽑는 것보다 규칙이
##   빨리 읽힌다. 대신 **테두리 모양으로** 둘을 가른다 — draw_elem 은 동그라미,
##   draw_body 는 네모다(아래 주석).
const ELEM_ART := {"none": "el_none", "fire": "el_fire", "ice": "el_ice",
	"elec": "el_elec", "water": "el_water"}
const BODY_ART := {"aqua": "el_water", "flame": "el_fire", "wood": "el_wood",
	"rock": "el_rock", "frost": "el_ice"}
## 아이콘 그림 한 장의 실제 크기(px). 화면에서는 반지름에 맞춰 줄여 그린다.
const ELEM_PX := 32.0


## 속성 표시 한 개 — **동그라미 받침 위의 아이콘 한 장**.
##
## ★ 왜 그림인가: 예전에는 속성 색 동그라미 안에 한글 한 자였다. 그런데 몬스터 옆에
##   화상 불꽃이 타고 있으면 그 몬스터가 불속성으로 보이는 것처럼, 글자 한 자는
##   「무엇의 이름인가」를 말하지 못한다. 그림은 옆에 무엇이 있든 제 뜻을 지킨다.
## ★ 받침을 어둡게 까는 까닭: 테마 바닥이 그림 백 장이라 어떤 곳은 밝고 어떤 곳은
##   어지럽다. 받침이 없으면 밝은 바닥 위에서 아이콘이 통째로 사라진다
##   (무늬 밑에 받침을 까는 것과 같은 뜻이다 — battle_screen._aura_mark).
## ★ **그림이 없어도 게임이 돌아야 한다**(CLAUDE.md 18-1). 없으면 예전 그대로
##   속성 색 동그라미에 한 글자다 — 그 가지를 지우지 마라.
static func draw_elem(ci: CanvasItem, c: Vector2, r: float, e: String) -> void:
	if r < 3.0:
		return
	# 받침은 아이콘보다 조금 넓게. 아이콘은 네모라 모서리가 1.49r 까지 나가는데,
	# 받침이 그보다 훨씬 좁으면 밝은 바닥에서 모서리 몇 점이 배경에 녹는다.
	if e != "elec":
		ci.draw_circle(c, r + 2.2, BG_DEEP)
	if _icon(ci, c, r, String(ELEM_ART.get(e, ""))):
		return
	var col := Color(String(Balance.ELEM.get(e, Balance.ELEM["none"])["color"]))
	ci.draw_circle(c, r, col)
	var sz := int(r * 1.5)
	if sz >= 9:
		text_center(ci, c, elem_char(e), sz, BG_DEEP)


## **몬스터의 몸** 표시 한 개 — 네모 받침 위의 아이콘 한 장.
##
## ★ 사용자가 정한 것: 「몬스터의 속성을 표기해주자」. 예전에는 몬스터 옆에 「무엇에
##   약한가」만 붙어 있었고 **그 몬스터가 무엇인지는 어디에도 없었다.** 그래서 화상
##   불꽃이 붙은 몬스터가 불 몬스터로 보였다.
## ★ **네모다.** 공격 속성(draw_elem)은 동그라미이므로, 같은 불 아이콘이라도 네모면
##   「이 몬스터는 불이다」이고 동그라미면 「불이 잘 든다」다. 모양으로 안 가르면
##   나무 몬스터 옆의 불·얼음 동그라미와 몸 아이콘이 한 줄로 뭉쳐서, 몸이 약점으로
##   읽힌다. (테마 판의 범례가 이 규칙을 글로도 적어 둔다)
static func draw_body(ci: CanvasItem, c: Vector2, r: float, body: String) -> void:
	if r < 3.0:
		return
	var col := Balance.body_color(body)
	var box := Rect2(c.x - r - 2.0, c.y - r - 2.0, (r + 2.0) * 2.0, (r + 2.0) * 2.0)
	fill_round(ci, box, r * 0.42, Color(col.r * 0.42, col.g * 0.42, col.b * 0.42, 1.0))
	fill_round(ci, box.grow(-1.5), r * 0.36, BG_DEEP)
	if _icon(ci, c, r, String(BODY_ART.get(body, ""))):
		return
	ci.draw_circle(c, r * 0.86, col)
	var sz2 := int(r * 1.4)
	if sz2 >= 9:
		text_center(ci, c, body_char(body), sz2, BG_DEEP)


## 아이콘 그림 한 장을 c 한가운데에 놓는다. 그림이 없으면 거짓.
##
## ★ Art.draw_at 은 **발밑**이 기준이라 c.y 에 반쪽 높이를 더해야 한가운데에 온다.
static func _icon(ci: CanvasItem, c: Vector2, r: float, key: String) -> bool:
	if key == "":
		return false
	var s: float = r * 2.1
	return Art.draw_fill(ci, String(Roster.ART.get(key, "")), Rect2(c - Vector2.ONE * s * 0.5, Vector2.ONE * s))


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
static func fill_round(ci: CanvasItem, rect: Rect2, r: float, col: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var cut := minf(4.0, minf(r, minf(rect.size.x, rect.size.y) * 0.25))
	ci.draw_rect(Rect2(rect.position + Vector2(cut, 0), rect.size - Vector2(cut * 2, 0)), col)
	ci.draw_rect(Rect2(rect.position + Vector2(0, cut), rect.size - Vector2(0, cut * 2)), col)

## Shared Krea timber/stone surfaces with readable quiet centers and brass corners.
static func material_panel(ci: CanvasItem, rect: Rect2, face: Color = PANEL,
		edge: Color = PANEL_EDGE, material: String = "wood") -> void:
	px_panel(ci, Rect2(rect.position + Vector2(0, 4), rect.size), BG_DEEP, BG_DEEP)
	px_panel(ci, rect, face, edge, 0.15)
	var inside := rect.grow(-8)
	var tex := Art.tex("res://art/ui/refuge/%s.png" % material)
	if tex != null and inside.size.x > 0 and inside.size.y > 0:
		ci.draw_texture_rect(tex, inside, true, Color(0.75, 0.8, 0.78, 0.16 if material == "wood" else 0.38))
	for corner in [rect.position + Vector2(6, 6), Vector2(rect.end.x - 10, rect.position.y + 6),
		Vector2(rect.position.x + 6, rect.end.y - 10), rect.end - Vector2(10, 10)]:
		ci.draw_rect(Rect2(corner, Vector2(4, 4)), edge.lightened(0.25))

static func camp_backdrop(ci: CanvasItem) -> void:
	if not Art.draw_fill(ci, "res://art/ui/refuge/camp.png", SCREEN):
		Art.draw_fill(ci, Roster.ART.get("shop_bg", ""), SCREEN)
	ci.draw_rect(SCREEN, Color(0.025, 0.06, 0.08, 0.32))

## 테두리만 그린다(안을 비우지 않고). 겹쳐 그리는 순서로 해결한다.
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
## ★ **그림(art/ui/crystal.png)이 먼저다**(사용자가 정한 것: 「크리스탈 전부 이미지생성해서」).
##   그림이 없으면 아래 도형으로 그대로 그린다 — 그림 없이도 게임이 돌아야 한다는
##   규칙(18-1)은 이펙트에도 똑같이 걸린다.
## ★ **아주 작을 때는 도형으로 되돌린다.** 크리스탈은 스무 개가 제단을 빙 둘러 놓이고,
##   전투 정보판의 줄에서는 반지름이 6.5px 다. 32x50 짜리 도트 그림을 거기까지 줄이면
##   면(facet)이 뭉개져 그냥 파란 점이 된다 — 도형이 그 크기에서는 훨씬 또렷하다.
## ★ 깨진 자리도 **같은 그림**을 어둡게 그린다. 한쪽만 그림이면 상점의 크리스탈 탭에서
##   산 것과 안 산 것이 다른 재질로 보인다(거기서는 깨진 칸이 「되살 자리」로 빛난다).
const CRYSTAL_PX := 9.0
static func draw_crystal(ci: CanvasItem, c: Vector2, r: float, alive: bool,
		glow: float = 0.0) -> void:
	if r >= CRYSTAL_PX:
		# 도형과 같은 자리에 놓는다 — 도형은 위가 c.y - r*1.5, 밑동이 c.y + r*1.0 이라
		# 높이가 2.5r 이고, 그림은 50px 높이다. draw_at 은 **발밑**이 기준이다.
		if glow > 0.001:
			var gc: Color = CRYSTAL if alive else Color(1, 1, 1, 1)
			ci.draw_circle(c, r * ((1.8 + glow) if alive else (1.0 + glow * 1.6)),
					Color(gc.r, gc.g, gc.b, (0.18 if alive else 0.55) * clampf(glow, 0.0, 1.0)))
		var md: Color = Color.WHITE if alive else Color(0.30, 0.36, 0.48, 0.80)
		if Art.draw_at(ci, Roster.ART.get("crystal", ""), c.x, c.y + r, r * 0.05, md):
			return
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


## 카드 한 장. pos 는 왼쪽 위 모서리, scale 로 크기를 바꾼다.
## hi 가 참이면 족보를 이룬 카드라는 뜻으로 테두리를 금색으로 두른다.
##
## ★ **도트로 그린다**(사용자가 정한 것: 「포커하는 화면도 2D 픽셀로」). 예전에는 둥근
##   모서리와 매끈한 곡선 무늬였는데, 같은 화면 아래쪽에 96px 도트 캐릭터가 서 있어서
##   카드만 다른 게임에서 온 것처럼 보였다.
##
## ★ **실제 트럼프와 같은 판짜기**(사용자가 정한 것: 「실제 트럼프카드와 똑같이」).
##   세 가지를 실제 카드에서 그대로 옮겨 왔다:
##     1. 모서리 표시는 **왼쪽 위와 오른쪽 아래**, 아래쪽은 180도 돌아간다.
##     2. 숫자 카드의 무늬는 **3열 x 7행 격자**의 정해진 자리에 놓인다(PIP_LAYOUT).
##        그리고 **아래 절반은 거꾸로** 찍힌다 — 이 한 가지가 "진짜 카드"를 만든다.
##     3. J·Q·K 는 **반쪽 그림을 위아래로 마주 붙인** 틀 그림이다(COURT_PX).
static func draw_card(ci: CanvasItem, pos: Vector2, code: int, sc: float = 1.0,
		hi: bool = false, dim: bool = false) -> void:
	var w := roundf(CARD_W * sc)
	var h := roundf(CARD_H * sc)
	var p := pos.round()
	var rect := Rect2(p, Vector2(w, h))
	var edge := GOLD if hi else CARD_EDGE
	fill_round(ci, Rect2(p + Vector2(2, 5), rect.size), 5, Color(0, 0, 0, 0.42))
	fill_round(ci, rect, 5, edge)
	fill_round(ci, rect.grow(-2), 4, CARD_BG.darkened(0.3) if dim else CARD_BG)
	if hi:
		ci.draw_rect(rect.grow(-5), Color(GOLD, 0.68), false, 1)
	var suit := Poker.suit_of(code)
	var col := CARD_RED if suit in [Poker.Suit.HEART, Poker.Suit.DIAMOND] else CARD_BLK
	if dim:
		col = col.lerp(CARD_BG, 0.45)
	var rank := Poker.rank_of(code)
	var rc: String = Poker.RANK_CHAR[rank - Poker.RANK_MIN]
	var cx := w * 0.16
	var mark := maxi(10, int(22 * sc))
	text_center_fit(ci, p + Vector2(cx, h * 0.085), rc, mark, col, w * 0.28, 10)
	card_suit(ci, p + Vector2(cx, h * 0.205), 6.4 * sc, suit, col)
	text_center_fit(ci, p + Vector2(w - cx, h * 0.915), rc, mark, col, w * 0.28, 10)
	card_suit(ci, p + Vector2(w - cx, h * 0.795), 6.4 * sc, suit, col)
	if rank in [11, 12, 13]:
		_court(ci, Rect2(p + Vector2(w * 0.235, h * 0.115), Vector2(w * 0.53, h * 0.77)), rc, suit, col, dim)
		return
	if rank == 14:
		card_suit(ci, rect.get_center(), 31 * sc, suit, col)
		return
	for q in (PIP_LAYOUT.get(rank, []) as Array):
		var v: Vector2 = q
		card_suit(ci, p + Vector2(w * (0.33 + 0.34 * v.x), h * (0.17 + 0.66 * v.y)), 7.1 * sc, suit, col)


## Continuous suit contours retain clean edges at both hand and picker sizes.
static func card_suit(ci: CanvasItem, at: Vector2, radius: float, suit: int, col: Color) -> void:
	var points := PackedVector2Array()
	match suit:
		Poker.Suit.DIAMOND:
			points = PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.72, 0), at + Vector2(0, radius), at - Vector2(radius * 0.72, 0)])
		Poker.Suit.HEART, Poker.Suit.SPADE:
			for i in range(49):
				var a := TAU * i / 48.0
				var x := 16 * pow(sin(a), 3) / 17.0
				var y := -(13 * cos(a) - 5 * cos(2*a) - 2 * cos(3*a) - cos(4*a)) / 17.0
				points.append(at + Vector2(x, y * (-1 if suit == Poker.Suit.SPADE else 1)) * radius)
		_:
			ci.draw_circle(at + Vector2(0, -radius * 0.46), radius * 0.47, col)
			ci.draw_circle(at + Vector2(-radius * 0.43, radius * 0.08), radius * 0.48, col)
			ci.draw_circle(at + Vector2(radius * 0.43, radius * 0.08), radius * 0.48, col)
	if not points.is_empty():
		ci.draw_colored_polygon(points, col)
		points.append(points[0])
		ci.draw_polyline(points, col, 0.7, true)
	if suit in [Poker.Suit.SPADE, Poker.Suit.CLUB]:
		ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius * 0.1), at + Vector2(radius * 0.4, radius), at + Vector2(-radius * 0.4, radius)]), col)


## 숫자 카드의 무늬 자리. 실제 트럼프의 **3열 x 7행 격자**를 그대로 옮겼다 —
## x 는 0.0 / 0.5 / 1.0 (왼·가운데·오른쪽), y 는 0/6 부터 6/6 까지 일곱 자리다.
## 눈이 이미 외우고 있는 배치라, 한 자리만 틀려도 "가짜 카드"로 읽힌다.
const PIP_LAYOUT := {
	2:  [Vector2(0.5, 0.0), Vector2(0.5, 1.0)],
	3:  [Vector2(0.5, 0.0), Vector2(0.5, 0.5), Vector2(0.5, 1.0)],
	4:  [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
	5:  [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 0.5),
		 Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
	6:  [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 0.5), Vector2(1.0, 0.5),
		 Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
	7:  [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 0.25),
		 Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
	8:  [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 0.25),
		 Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(0.5, 0.75),
		 Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
	9:  [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0 / 3.0),
		 Vector2(1.0, 1.0 / 3.0), Vector2(0.5, 0.5), Vector2(0.0, 2.0 / 3.0),
		 Vector2(1.0, 2.0 / 3.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
	10: [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 1.0 / 6.0),
		 Vector2(0.0, 1.0 / 3.0), Vector2(1.0, 1.0 / 3.0),
		 Vector2(0.0, 2.0 / 3.0), Vector2(1.0, 2.0 / 3.0), Vector2(0.5, 5.0 / 6.0),
		 Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
}


## 그림 카드(J·Q·K). **반쪽 그림 하나를 위아래로 마주 붙인다** — 실제 트럼프가 그렇다.
##
## ★ 예전에는 왕관 하나와 글자 하나였다. 그것으로도 "그림 카드"인 줄은 알지만
##   실제 카드와 나란히 놓으면 곧바로 가짜로 보였다. 사람 반쪽을 21x26 도트로 찍고
##   180도 돌려 아래에 붙이면, 30px 안에서도 왕·여왕·기사가 서로 다르게 읽힌다.
## ★ 무늬 색이 검정일 때 옷을 그대로 검정으로 칠하면 윤곽과 붙어 **덩어리 하나**가
##   된다. 그래서 옷은 무늬 색을 바탕 쪽으로 조금 민 색이고 윤곽은 더 어둡게 민 색이다.
static var _court_texture: CanvasTexture
static var _court_regions: Dictionary = {}

static func _court_portrait(ci: CanvasItem, box: Rect2, rank: String, dim: bool) -> bool:
	if _court_texture == null:
		var source := Art.tex("res://art/ui/dealer/card_courts.png")
		if source == null:
			return false
		_court_texture = CanvasTexture.new()
		_court_texture.diffuse_texture = source
		_court_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		for i in range(3):
			_court_regions[["J", "Q", "K"][i]] = Rect2(i * 512 + 4, 88, 504, 848)
	var src: Rect2 = _court_regions.get(rank, _court_regions["K"])
	var half := Rect2(box.position + Vector2(2, 3), Vector2(box.size.x - 4, (box.size.y - 6) * 0.5))
	var target := Art.fit_rect(src.size, half)
	var tint := Color(0.68, 0.68, 0.68, 1) if dim else Color.WHITE
	ci.draw_texture_rect_region(_court_texture, target, src, tint)
	var lower := Rect2(Vector2(target.position.x, box.get_center().y), target.size)
	var size := Vector2(_court_texture.get_width(), _court_texture.get_height())
	ci.draw_polygon(PackedVector2Array([lower.position, Vector2(lower.end.x, lower.position.y), lower.end, Vector2(lower.position.x, lower.end.y)]), PackedColorArray([tint]), PackedVector2Array([src.end / size, Vector2(src.position.x, src.end.y) / size, src.position / size, Vector2(src.end.x, src.position.y) / size]), _court_texture)
	ci.draw_line(Vector2(box.position.x + 2, box.get_center().y), Vector2(box.end.x - 2, box.get_center().y), GOLD_DEEP, 1)
	return true


static func _court(ci: CanvasItem, box: Rect2, rc: String, suit: int, col: Color,
		dim: bool) -> void:
	var r := Rect2(box.position.round(), box.size.round())
	var edge := col
	# 틀 — 실제 카드의 그 네모 테두리.
	fill_round(ci, r, 1, edge)
	fill_round(ci, r.grow(-1), 1, CARD_BG.darkened(0.04) if not dim else CARD_BG.darkened(0.30))
	if _court_portrait(ci, r, rc, dim):
		return
	var rows: Array = COURT_PX.get(rc, COURT_PX["K"])
	var nr := rows.size()
	var nc: int = (rows[0] as String).length()
	var blk: float = maxf(1.0, floor(minf(r.size.x * 0.88 / float(nc),
			r.size.y * 0.490 / float(nr))))
	var pal := {
		"o": col.darkened(0.55),
		"s": Color("#f0c9a0"),
		"h": Color("#a8743a"),
		"r": col.lerp(CARD_BG, 0.16),
		"w": Color("#eee9dd"),
		"g": GOLD,
	}
	if dim:
		for k in pal.keys():
			pal[k] = (pal[k] as Color).lerp(CARD_BG, 0.45)
	var fw := blk * float(nc)
	var fh := blk * float(nr)
	var mx := r.position.x + r.size.x * 0.5
	var my := r.position.y + r.size.y * 0.5
	_blit_court(ci, rows, pal, Vector2(mx - fw * 0.5, my - fh), blk, false)
	_blit_court(ci, rows, pal, Vector2(mx - fw * 0.5, my), blk, true)
	# 틀 안 모서리의 작은 무늬 — 실제 카드가 여기에 무늬를 하나씩 넣는다.
	# ★ **틀이 좁으면(sc 1.0) 넣지 않는다.** 모서리 표시(cg 는 어느 크기에서나 2다)와
	#   이 무늬 사이에 틀 테두리 한 줄밖에 안 남아서, 셋이 한 덩어리로 뭉쳐 카드 모서리에
	#   정체 모를 얼룩이 생긴다(타이틀의 부채꼴이 그 크기다). 자리 비율을 밀어서 고칠 수는
	#   없다 — sc 1.0 에서 비키게 만든 비율이 sc 1.3 에서는 사람 그림을 파고든다.
	if blk < 3.0:
		return
	var sg: float = maxf(1.0, floor(blk * 0.55))
	draw_suit_px(ci, r.position + Vector2(r.size.x * 0.10, r.size.y * 0.075), sg, suit, col)
	draw_suit_px(ci, r.position + Vector2(r.size.x * 0.90, r.size.y * 0.925), sg, suit,
			col, true)


## 팔레트 도트판 한 장. rot 이 참이면 180도 돌린다(마주 붙는 아래 절반).
## ★ 같은 색이 가로로 이어지면 한 번에 그린다 — 21x26 을 한 칸씩 그리면 546개다.
static func _blit_court(ci: CanvasItem, rows: Array, pal: Dictionary, at: Vector2,
		blk: float, rot: bool) -> void:
	var nr := rows.size()
	var nc: int = (rows[0] as String).length()
	for y in range(nr):
		var line: String = rows[nr - 1 - y] if rot else rows[y]
		var run := -1
		var cur := ""
		for x in range(nc + 1):
			var ch := ""
			if x < nc:
				ch = line[nc - 1 - x] if rot else line[x]
				if not pal.has(ch):
					ch = ""
			if ch != cur:
				if cur != "" and run >= 0:
					ci.draw_rect(Rect2(at.x + blk * float(run), at.y + blk * float(y),
							blk * float(x - run), blk), pal[cur])
				cur = ch
				run = x


## 카드 무늬 도트판. 실제 트럼프의 실루엣을 그대로 옮긴 **11칸 폭 x 12줄**이다.
##
## ★ 글꼴로 그리지 않는 이유는 core/poker.gd 의 SUIT_KO 주석에 적어 뒀다.
##   번들 폰트에 ♠♦♣ 가 없어서 두부로 깨진다.
## ★ **열쇠는 인덱스가 Poker.Suit 와 정확히 같아야 한다는 것이다.** 예전 표는
##   스페이드 자리(0)에 하트를, 하트 자리(1)에 스페이드를 넣어 두어서 — 색까지
##   같이 갈리므로 — **검은 하트와 빨간 스페이드**가 화면에 찍혔다. 사용자가 본
##   「카드모양 좀 이상하게 생성됨」이 정확히 이것이다.
const SUIT_PX := {
	Poker.Suit.SPADE: [
		".....#.....", "....###....", "...#####...", "..#######..", ".#########.",
		"###########", "###########", "###########", "###########", ".###...###.",
		"....###....", "...#####...",
	],
	Poker.Suit.HEART: [
		"..##...##..", ".####.####.", "###########", "###########", "###########",
		"###########", ".#########.", "..#######..", "...#####...", "....###....",
		".....#.....", "...........",
	],
	Poker.Suit.DIAMOND: [
		".....#.....", "....###....", "...#####...", "..#######..", ".#########.",
		".#########.", ".#########.", "..#######..", "...#####...", "....###....",
		".....#.....", "...........",
	],
	Poker.Suit.CLUB: [
		"....###....", "...#####...", "...#####...", ".##.###.##.", "###########",
		"###########", "###########", ".##.###.##.", ".....#.....", "....###....",
		"...#####...", "..#######..",
	],
}


## 그림 카드의 반쪽 사람. 21칸 폭 x 26줄.
## 글자는 팔레트다 — o 윤곽 · s 살 · h 머리 · r 옷(무늬색) · w 밝은 것 · g 금.
## ★ 셋이 **실루엣부터** 달라야 한다. 왕은 뿔 셋 왕관에 흰 수염과 칼,
##   여왕은 어깨를 덮는 긴 머리와 꽃, 잭은 깃 꽂은 챙모자와 창이다.
##   얼굴 생김새로만 가르면 30px 안에서 셋이 같은 사람이 된다.
const COURT_PX := {
	"K": [
		"......g...g...g......",
		".....ggg.ggg.ggg.....",
		".....ggggggggggg.....",
		".....ggwggwggwgg.....",
		".......ooooooo.......",
		"......hsssssssh......",
		"......hsssssssh......",
		"......hsosssosh..wo..",
		"......hsssssssh..wo..",
		"......hssooossh..wo..",
		"......wwwwwwwww.gggg.",
		".......wwwwwww...wo..",
		"........wwwww....wo..",
		".......ogggggo...wo..",
		".....orgggggggro.wo..",
		"...orrrrrrgrrrrrrwo..",
		".orrrrrrrrgrrrrrrwoo.",
		"orrrrrrrrrgrrrrrrworo",
		"orrrrrrrrrgrrrrrrworo",
		"orrrrrrrrrgrrrrrrworo",
		"orrrrrrrrrgrrrrrrworo",
		"orrrrrrrrrgrrrrrrworo",
		"orrrrrrrrrgrrrrrrworo",
		"orrrrrrrrrgrrrrrrworo",
		"orrrrrrrrrgrrrrrrworo",
		"orrrrrrrrrgrrrrrrworo",
	],
	"Q": [
		".....................",
		"......w.w.w.w.w......",
		".....ggggggggggg.....",
		".....ggggggggggg.....",
		".......hhhhhhh.......",
		".....hhssssssshh.....",
		".....hhssssssshh.....",
		".....hhsosssoshh.....",
		".....hhssssssshh.....",
		".....hhssssssshh.....",
		"..w..hhssssssshh.....",
		".wgw.h..ooooo..h.....",
		"..w.hh.........hh....",
		"..g.hh.owwwwwo.hh....",
		"..g.hhrwwwwwwwrhh....",
		"..gohhrrrrwrrrrhho...",
		".ogrhhrrrrwrrrrhhrro.",
		"orgrhhrrrrwrrrrhhrrro",
		"orgrhhrrrrwrrrrhhrrro",
		"orgrhhrrrrwrrrrhhrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
	],
	"J": [
		"..g..............w...",
		"..g....rrrrrrr....w..",
		"..g..rrrrrrrrrrr..w..",
		"..w.ooooooooooooow...",
		"..w....hhhhhhh.......",
		".wgw..hsssssssh......",
		"..w...hsssssssh......",
		"..g...hsosssosh......",
		"..g...hsssssssh......",
		"..g...hssooossh......",
		"..g...hsssssssh......",
		"..g.....ooooo........",
		"..g..................",
		"..g....owwwwwo.......",
		"..g..orwwwwwwwro.....",
		"..gorrrrrrwrrrrrro...",
		".ogrrrrrrrwrrrrrrrro.",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
		"orgrrrrrrrwrrrrrrrrro",
	],
}


## 무늬를 도트판으로 찍는다. blk 은 한 칸의 크기, flip 이면 180도 돌린다
## (실제 트럼프의 아래쪽 절반이 그렇다).
static func draw_suit_px(ci: CanvasItem, c: Vector2, blk: float, suit: int,
		col: Color, flip: bool = false) -> void:
	var rows: Array = SUIT_PX.get(suit, SUIT_PX[Poker.Suit.SPADE])
	var nr := rows.size()
	var nc: int = (rows[0] as String).length()
	var x0: float = snap(c.x - blk * float(nc) * 0.5, 1.0)
	var y0: float = snap(c.y - blk * float(nr) * 0.5, 1.0)
	for r in range(nr):
		var line: String = rows[nr - 1 - r] if flip else rows[r]
		var run := -1
		for x in range(nc + 1):
			var on := false
			if x < nc:
				on = (line[nc - 1 - x] if flip else line[x]) == "#"
			if on and run < 0:
				run = x
			elif not on and run >= 0:
				# ★ 한 칸씩 draw_rect 하면 카드 한 장에 도형이 삼백 개다. 가로로 이어진
				#   칸은 한 번에 그린다 — 같은 그림인데 도형이 6분의 1로 준다.
				ci.draw_rect(Rect2(x0 + blk * float(run), y0 + blk * float(r),
						blk * float(x - run), blk), col)
				run = -1


## 무늬 하나를 반지름 r 로 그린다. 도트판을 그 크기에 맞춰 찍을 뿐이다 —
## ★ 실루엣의 원본은 SUIT_PX **한 곳뿐이다.** 예전에는 여기가 원과 삼각형으로 따로
##   그려서, 같은 스페이드가 자리에 따라 다른 모양으로 나왔다.
static func draw_suit(ci: CanvasItem, c: Vector2, r: float, suit: int, col: Color) -> void:
	draw_suit_px(ci, c, maxf(1.0, floor(r * 2.0 / 12.0)), suit, col)

## 카드 뒷면. 리롤 연출에서 뒤집을 때 쓴다.
static func draw_card_back(ci: CanvasItem, pos: Vector2, sc: float = 1.0) -> void:
	var g: float = maxf(2.0, snap(PX * sc, 1.0))
	var w := snap(CARD_W * sc, g)
	var h := snap(CARD_H * sc, g)
	var p := snap_v(pos, g)
	px_panel(ci, Rect2(p + Vector2(g, g * 2.0), Vector2(w, h)), Color(0, 0, 0, 0.45),
			Color(0, 0, 0, 0.45))
	# 그려 둔 뒷면 그림이 있으면 그걸 쓰고, 없으면 아래 도형으로 대신 그린다.
	var t := Art.tex(Roster.ART.get("card_back", ""))
	if t != null:
		px_panel(ci, Rect2(p, Vector2(w, h)), CARD_BACK, CARD_EDGE)
		ci.draw_texture_rect(t, Rect2(p + Vector2(g, g), Vector2(w - g * 2.0, h - g * 2.0)),
				false)
		return
	px_panel(ci, Rect2(p, Vector2(w, h)), CARD_BACK, CARD_EDGE)
	px_panel(ci, Rect2(p + Vector2(g * 2.0, g * 2.0), Vector2(w - g * 4.0, h - g * 4.0)),
			CARD_BACK2, GOLD_DEEP)
	# 금색 마름모 격자 — 도트로 찍는다.
	var step: float = g * 5.0
	var y := p.y + g * 4.0
	var row := 0
	while y < p.y + h - g * 4.0:
		var x := p.x + (g * 4.0 if row % 2 == 0 else g * 6.5)
		while x < p.x + w - g * 4.0:
			ci.draw_rect(Rect2(snap(x, g), snap(y, g), g, g), GOLD_DEEP)
			ci.draw_rect(Rect2(snap(x - g, g), snap(y + g, g), g * 3.0, g), GOLD_DEEP)
			ci.draw_rect(Rect2(snap(x, g), snap(y + g * 2.0, g), g, g), GOLD_DEEP)
			x += step
		y += step * 0.8
		row += 1


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
## ★ 사용자가 정한 것: 「패시브도 카드 형태로 일러스트해서 이쁘게」. 포커 게임이라
##   카드 모양이 이 게임의 말투이기도 하다 — 상점의 진열이 손패처럼 보이면 뜻이 맞는다.
## ★ 등급(rank)은 **테두리 겹 수**로 말한다. 색만으로 두면 스물여섯 장 사이에서
##   어느 것이 귀한지가 안 읽힌다.
static func draw_passive_card(ci: CanvasItem, r: Rect2, p: Dictionary, owned: bool,
		can: bool, glow: float = 0.0) -> void:
	var tint := Color(String(p.get("tint", "#f6c445")))
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


## A film frame and play mark identify rewarded video without verbose labels.
static func draw_reward_icon(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var box := Rect2(center - Vector2(radius, radius * 0.77), Vector2(radius * 2, radius * 1.54))
	ci.draw_rect(box, color, false, 1.8)
	for side in [-1, 1]:
		for row in [-1, 0, 1]:
			ci.draw_rect(Rect2(center + Vector2(side * radius * 0.77 - 1, row * radius * 0.45 - 1), Vector2(2, 2)), color)
	ci.draw_colored_polygon(PackedVector2Array([center + Vector2(-radius * 0.27, -radius * 0.42), center + Vector2(radius * 0.44, 0), center + Vector2(-radius * 0.27, radius * 0.42)]), color)
