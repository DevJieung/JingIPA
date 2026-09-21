extends RefCounted
class_name Hud

## 화면 셋(뽑기 · 전투 · 상점)이 **똑같이** 그리는 위쪽 정보띠 조각과, 「이 탄에 오는 몬스터」 줄.
##
## ★ 왜 한곳에 두는가: 예전에는 세 화면이 저마다 판·크리스탈·골드를 그렸다. 셋이 같은
##   자리에 같은 것을 그려야 화면을 넘길 때 값이 제자리에 있는데, 따로 적어 두면 한 화면만
##   자리가 어긋나도 아무도 못 잡는다. 오른쪽 끝(다음 탄 · 배속 · 전장/전당)은 화면마다
##   다르므로 부르는 쪽이 이어서 그린다.

## 위쪽 정보띠의 자리. 화면들이 그 밑에 자기 판을 깐다.
const BAR := Rect2(0, 0, 1280, 68)
const COIN_X := 324.0
const TITLE_BOX := Rect2(24, 12, 130, 44)
const LIVES_BOX := Rect2(198, 12, 102, 44)
const GOLD_BOX := Rect2(346, 12, 126, 44)
const THEME_BOX := Rect2(490, 12, 278, 44)
const INFO_SIZE := 24
## 모든 화면의 메뉴는 우측 16px 안전 여백을 공유한다.
const MENU_RECT := Rect2(958, 10, 150, 48)
const LANGUAGE_RECT := Rect2(1120, 10, 144, 48)


## 판 · 제목 · 크리스탈(목숨) · 골드. `lives_col` 은 목숨 글자의 색이다 — 전투·상점은
## 다섯 개 밑으로 떨어지면 빨갛게 적는다.
static func topbar(ci: CanvasItem, title: String, lives_col: Color = Look.INK,
		_gold_size: int = INFO_SIZE, theme_title: String = "", theme_col: Color = Look.INK_DIM) -> void:
	Look.material_panel(ci, BAR, Look.PANEL, Look.PANEL_EDGE)
	ci.draw_rect(Rect2(0, BAR.size.y - 2.0, BAR.size.x, 2), Look.PANEL_EDGE)
	var life_text := "%d / %d" % [Run.lives, Run.max_lives()]
	var gold_text := "%d G" % Run.gold
	var shared := INFO_SIZE
	var flexible_width := THEME_BOX.end.x - GOLD_BOX.position.x
	while shared > 1:
		var values_fit := Look.text_width(title, shared) <= TITLE_BOX.size.x and Look.text_width(life_text, shared) <= LIVES_BOX.size.x
		var suffix_fit := maxf(GOLD_BOX.size.x, Look.text_width(gold_text, shared)) + 18 + Look.text_width(theme_title, shared) <= flexible_width
		if values_fit and suffix_fit:
			break
		shared -= 1
	var gold_box := GOLD_BOX
	gold_box.size.x = maxf(gold_box.size.x, Look.text_width(gold_text, shared))
	var theme_box := THEME_BOX
	theme_box.position.x = gold_box.end.x + 18
	theme_box.size.x = THEME_BOX.end.x - theme_box.position.x
	Look.text_box(ci, TITLE_BOX, title, shared, Look.INK)
	Look.text_box(ci, LIVES_BOX, life_text, shared, lives_col, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(ci, gold_box, gold_text, shared, Look.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	Look.text_box(ci, theme_box, theme_title, shared, theme_col)

	# Both source textures use a foot anchor. Explicit bounds share y=34 exactly.
	if not Art.draw_at(ci, Roster.ART.get("crystal", ""), 178, 48, 0.56):
		Look.draw_crystal(ci, Vector2(178, 36.8), 11.2, true)
	if not Art.draw_at(ci, Roster.ART.get("coin", ""), COIN_X, 48, 28.0 / 36.0):
		ci.draw_circle(Vector2(COIN_X, 34), 12.0, Look.GOLD)


## 「w탄 · 테마」 머리글. 보스탄이면 「· 보스」를 붙인다.
static func wave_head(w: int, prefix: String) -> String:
	var head := "%s · %s" % [prefix, String(Run.theme_for(w).get("ko", ""))]
	if Balance.is_boss_wave(w):
		head += " · 보스"
	return head


## 머리글 뒤에 몬스터 칩을 늘어놓았을 때의 전체 폭. 가운데 맞춤에 쓴다.
static func lineup_width(head: String, pool: Array, size: int = 20) -> float:
	var w := Look.text_width(head, size) + 18.0
	for m in pool:
		w += Look.monster_chip_width(m, size) + 8.0
	return w


## 머리글과 그 탄의 몬스터 칩(몸 아이콘 + 이름)을 한 줄로 그린다.
static func draw_lineup(ci: CanvasItem, at: Vector2, head: String, pool: Array) -> void:
	var size := 20
	while size > 1 and lineup_width(head, pool, size) > 1240.0 - at.x:
		size -= 1
	var head_width := Look.text_width(head, size)
	Look.text_box(ci, Rect2(at - Vector2(0, 16), Vector2(head_width, 32)), head, size, Look.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	var x: float = at.x + head_width + 18.0
	for m in pool:
		x += Look.draw_monster_chip(ci, Vector2(x, at.y), m, size) + 8.0
