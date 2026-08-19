class_name Look
extends RefCounted

## 앱 전체의 룩앤필이 사는 한 곳 — 색 · 주인공 · 공통 배경.
##
## ★ 세계관은 여전히 없다. 두리는 **이야기가 아니라 안내자**다 — 허브에서 인사하고,
##   판을 깨면 만세하고, 그것뿐이다. 게임끼리 이야기로 묶으면 결이 다른 다섯 개가
##   오히려 이질적으로 보인다는 것이 이 저장소가 이미 배운 것이다 (CLAUDE.md 맨 위).
##   두리가 하는 일은 "이 다섯 개가 한 앱이다"를 글자 없이 말해 주는 것뿐이다.
##
## ★ 화풍은 **장난감 상자 속 세상**이다. 공룡 50종이 손으로 칠한 수집용 피규어라서,
##   주인공 두리도 같은 피규어로 만들었다 (tools/theme/gen_theme.py).
##   새 그림이 필요하면 그 도구에 한 줄을 더해라 — 화풍 앵커가 거기 있다.
##
## ★ 새 게임을 넣을 때 색을 새로 짓지 마라. 여기서 가져다 써라.
##   게임마다 제 색을 지어내면 다섯 개가 다섯 앱처럼 보인다.

# --------------------------------------------------------------------------- #
# 색 — 크림 바탕에 따뜻한 나무/장난감 색
# --------------------------------------------------------------------------- #
const BG := Color("f7f0e4")        ## 모든 화면의 바탕
const BG2 := Color("efe4d2")       ## 바탕 위의 아주 옅은 띠 (밋밋함 방지)
const CARD := Color("fffdf8")      ## 카드 · 판넬 · 위쪽 바
const INK := Color("3b3038")       ## 글자
const INK_SOFT := Color("8b7d84")  ## 보조 글자
const SHADOW := Color(0, 0, 0, 0.10)
const ACCENT := Color("e8734a")    ## 강조 — 제목, 축하 문구
const GOLD := Color("ffd166")      ## 반짝임 · 보상
const FLOOR := Color("e7d9c2")     ## 바닥/선반

## 아이 손가락 기준. 누를 수 있는 것은 이보다 작게 만들지 않는다.
const TAP_MIN := 96.0

const ART := "res://core/art/"


# --------------------------------------------------------------------------- #
# 주인공 두리
# --------------------------------------------------------------------------- #

## 포즈: "" (인사) · "cheer" (만세) · "point" (가리키기) · "torch" (손전등) · "face" (얼굴)
##
## ★ preload 를 쓰지 않는다. 그림이 아직 없어도 게임은 돌아야 한다 —
##   자산 하나 때문에 아이 화면이 통째로 안 뜨는 일은 없어야 한다.
static func duri(pose := "") -> Texture2D:
	var id := "duri" if pose.is_empty() else "duri_" + pose
	if _cache.has(id):
		return _cache[id]
	var path := ART + id + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[id] = tex
	return tex


static var _cache: Dictionary = {}


## 두리를 그린다. **발이 at 에 닿게**, 키를 h 로 맞춰서 (공룡 그리기와 같은 규약).
## 그림이 없으면 아무것도 안 그리고 false 를 돌려준다.
static func draw_duri(ci: Object, pose: String, at: Vector2, h: float,
		flip := false, tint := Color.WHITE) -> bool:
	var tex := duri(pose)
	if tex == null:
		return false
	var ts := Vector2(tex.get_width(), tex.get_height())
	if ts.y <= 0.0:
		return false
	var w := h * ts.x / ts.y
	var r := Rect2(at + Vector2(-w * 0.5, -h), Vector2(w, h))
	if flip:
		r = Rect2(r.position + Vector2(r.size.x, 0.0), Vector2(-r.size.x, r.size.y))
	ci.draw_texture_rect(tex, r, false, tint)
	return true


# --------------------------------------------------------------------------- #
# 공통 배경 — 다섯 게임이 같은 바탕 위에서 논다
# --------------------------------------------------------------------------- #

## 크림 바탕 + 아주 옅은 가로 띠. 밋밋하지 않되 눈에 걸리지 않게.
static func paint_bg(ci: Object, w: float, h: float, band := 96.0) -> void:
	ci.draw_rect(Rect2(0, 0, w, h), BG)
	var y := 0.0
	while y < h:
		ci.draw_rect(Rect2(0, y, w, band * 0.5), BG2)
		y += band


## 기준 화면 밖 여백을 바탕색으로 (레터박스가 검게 보이지 않게).
## Control 게임들이 _draw 끝에서 부르는 것과 같은 일을 한 곳에 모은 것.
static func paint_letterbox(ci: Object, o: Vector2, screen: Vector2) -> void:
	if o.x > 0.5:
		ci.draw_rect(Rect2(0, 0, o.x, screen.y), BG)
		ci.draw_rect(Rect2(screen.x - o.x, 0, o.x, screen.y), BG)
	if o.y > 0.5:
		ci.draw_rect(Rect2(0, 0, screen.x, o.y), BG)
		ci.draw_rect(Rect2(0, screen.y - o.y, screen.x, o.y), BG)


# --------------------------------------------------------------------------- #
# 공통 그리기 도우미 (게임마다 같은 것을 다시 쓰지 않게)
# --------------------------------------------------------------------------- #

static func round_rect(ci: Object, r: Rect2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	ci.draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2.0, r.size.y), col)
	ci.draw_rect(Rect2(r.position.x, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	ci.draw_rect(Rect2(r.position.x + r.size.x - rad, r.position.y + rad, rad,
			r.size.y - rad * 2.0), col)
	for corner in [Vector2(rad, rad), Vector2(r.size.x - rad, rad),
			Vector2(rad, r.size.y - rad), Vector2(r.size.x - rad, r.size.y - rad)]:
		ci.draw_circle(r.position + corner, rad, col)


static func text(ci: Object, s: String, at: Vector2, px: int, col: Color) -> void:
	ci.draw_string(ThemeDB.fallback_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


static func text_centered(ci: Object, s: String, at: Vector2, px: int, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_string(f, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
