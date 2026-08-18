## 게임 전체 색 팔레트.
##
## 모든 그래픽을 코드로 그리기 때문에 색은 여기 한 곳에서만 정의한다.
## 톤은 "블록 장난감" 컨셉 — 채도는 높지만 눈이 편한 파스텔 계열.
class_name Palette
extends RefCounted

# --- 배경 / 월드 ---------------------------------------------------------- #
const SKY_TOP := Color("9fdcff")
const SKY_BOTTOM := Color("d8f3ff")
const HILL_FAR := Color("7fd08a")
const HILL_NEAR := Color("5cba6a")
const GROUND := Color("74c264")
const GROUND_DARK := Color("57a24a")
const WATER := Color("57bff0")
const WATER_DEEP := Color("3a9ed1")
const LILY := Color("46b06a")
const REED := Color("3f9e57")

# --- 개구리 용사 ---------------------------------------------------------- #
const FROG_BODY := Color("5fd35a")
const FROG_BODY_DARK := Color("3fae42")
const FROG_BELLY := Color("d6f7ae")
const FROG_EYE_WHITE := Color("ffffff")
const FROG_PUPIL := Color("22302a")
const FROG_CHEEK := Color("ff9db1")
const FROG_TONGUE := Color("ff6f8d")
const FROG_TONGUE_DARK := Color("e04b6d")
const HELMET := Color("ffcc4d")
const HELMET_DARK := Color("e0a92b")
const HELMET_GEM := Color("59d0ff")

# --- 나쁜 뱀 -------------------------------------------------------------- #
const SNAKE_BODY := Color("9b6ef3")
const SNAKE_BODY_DARK := Color("7549cc")
const SNAKE_BELLY := Color("d9c7ff")
const SNAKE_EYE := Color("fff3b0")
const SNAKE_PUPIL := Color("2a1a3d")
const SNAKE_TONGUE := Color("ff4d6d")
const SNAKE_BOSS := Color("e0556f")
const SNAKE_BOSS_DARK := Color("b53a52")
const SNAKE_BOSS_BELLY := Color("ffd0d8")

# --- 블록 (수 모형) ------------------------------------------------------- #
## ★색이 곧 "어느 수인가"다. 왼쪽 항 = 주황, 오른쪽 항 = 파랑,
## 뺄셈에서 없앨 오른쪽 항만 빨강. 문제 카드의 숫자 강조도 **반드시 같은 색**을 쓴다
## (`Problem.term_color()` 한 곳에서 정한다). 카드와 블록의 색이 다르면
## 아이가 "위의 숫자"와 "아래 블록"을 서로 다른 것으로 읽는다.
## 합쳐진 뒤에도 색을 유지해서 "전체 안에 부분이 남아 있다"는 걸 볼 수 있게 한다.
const BLOCK_A := Color("ff9f43")
const BLOCK_A_DARK := Color("d97b1f")
const BLOCK_A_LIGHT := Color("ffc182")
const BLOCK_B := Color("4fc3f7")
const BLOCK_B_DARK := Color("2b96c9")
const BLOCK_B_LIGHT := Color("9adcfb")
## 세 수의 계산에서 세 번째 항. 보기(초록)와 겹치지 않게 보라 계열로 둔다.
const BLOCK_C := Color("b98ce8")
const BLOCK_GHOST := Color("c9d4dd")       # 사라질 예정 표시
const BLOCK_REMOVE := Color("ff7043")      # 빼기에서 없어지는 블록
const BLOCK_REMOVE_DARK := Color("cf4c22")
const ROD_GLOW := Color("ffd54f")          # 십 막대 묶음 테두리

## '아직 모르는 수' 색 — 보기 버튼, 문제 카드의 물음표 상자,
## 빈칸 문제에서 찾아야 할 블록이 전부 이 색이다.
## 셋을 같은 색으로 묶어야 아이가 "초록 = 내가 찾을 것"으로 읽는다.
## 항 색(주황/파랑/빨강)과 절대 겹치면 안 된다.
const CHOICE := Color("8ed98f")
const CHOICE_DARK := Color("5faa62")
const CHOICE_TEXT := Color("1a3a1d")

# --- UI ------------------------------------------------------------------- #
const INK := Color("28382e")
const INK_SOFT := Color("5d7266")
const CARD := Color("ffffff")
const CARD_EDGE := Color("dbe7de")
const SHADOW := Color(0, 0, 0, 0.16)
const PANEL := Color("fffaf0")

const BTN := Color("ffb03a")
const BTN_DARK := Color("d98a1c")
const BTN_TEXT := Color("4a2f00")
const BTN_BLUE := Color("55b9f0")
const BTN_BLUE_DARK := Color("2f92c9")
const BTN_GREEN := Color("62c96b")
const BTN_GREEN_DARK := Color("3f9e47")
const BTN_GREY := Color("bfc9c2")
const BTN_GREY_DARK := Color("94a19a")

const CORRECT := Color("4caf50")
const CORRECT_LIGHT := Color("a5e8a8")
const WRONG := Color("ff7043")
const WRONG_LIGHT := Color("ffc7b3")
const HEART := Color("ff5a76")
const HEART_EMPTY := Color("d8ccc9")
const STAR := Color("ffd23f")
const STAR_EMPTY := Color("d7dbd4")
const LOCK := Color("9aa7a0")

# --- 월드별 대표색 --------------------------------------------------------- #
## 월드 인덱스에 따라 배경/버튼 톤을 바꿔 진행감을 준다.
const WORLD_TINTS: Array[Color] = [
	Color("8fd97a"),  # 개굴 늪지
	Color("6fd3e8"),  # 연꽃 호수
	Color("c9a86a"),  # 버섯 숲
	Color("f0a35e"),  # 바위 골짜기
	Color("9ba7e0"),  # 안개 동굴
	Color("f2d06b"),  # 황금 들판
	Color("7fd8b0"),  # 곱셈 신전 1
	Color("6ab8f0"),  # 곱셈 신전 2
	Color("b98ce8"),  # 곱셈 신전 3
	Color("e8757f"),  # 뱀왕의 성
]


static func world_tint(world_index: int) -> Color:
	if WORLD_TINTS.is_empty():
		return SKY_TOP
	return WORLD_TINTS[clampi(world_index, 0, WORLD_TINTS.size() - 1)]


## 색을 어둡게(amount<0) 또는 밝게(amount>0) 민다. 알파는 유지.
static func shade(c: Color, amount: float) -> Color:
	var out := c
	if amount >= 0.0:
		out = c.lerp(Color(1, 1, 1, c.a), clampf(amount, 0.0, 1.0))
	else:
		out = c.lerp(Color(0, 0, 0, c.a), clampf(-amount, 0.0, 1.0))
	out.a = c.a
	return out


## 채도만 조절 (회색으로 빼거나 더 진하게).
static func saturate(c: Color, amount: float) -> Color:
	var out := c
	out.s = clampf(c.s * amount, 0.0, 1.0)
	return out


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
