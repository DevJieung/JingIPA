extends RefCounted
class_name Balance

## 게임의 숫자가 **전부** 여기 있다. 순수 함수만 두고 화면·저장을 모른다.
##
## 왜 한곳에 모았나: 디펜스 게임은 "이 판이 왜 안 깨지는지"를 사람이 손으로 계산할 수
## 있어야 고칠 수 있다. 숫자가 전투 코드 안에 흩어지면 그게 불가능해진다.
## tests/balance_check.gd 가 이 표만 읽어 40탄까지 자동으로 돌려 보고 클리어율을 뽑는다.

# --------------------------------------------------------------------------- #
# 투기장 — 몬스터는 이 원 위를 돌면서 안쪽으로 조여 온다
# --------------------------------------------------------------------------- #
## 1280x800 기준. 오른쪽 430px 는 정보판이라 원의 중심을 왼쪽으로 당겨 놨다.
const ARENA_CENTER := Vector2(470, 420)
## 몬스터가 나타나는 바깥 반지름. 오른쪽 정보판(x 830~)에 닿지 않는 크기다.
const SPAWN_R := 340.0
## 더는 안쪽으로 못 오는 한계. 여기 도달한 몬스터는 영웅들을 에워싸고 촘촘히 돈다.
## ★ 이 값보다 짧은 사거리가 있으면 **중앙의 영웅이 아무도 못 때린다.** 가장 짧은 사거리는
##   하이카드 수호형 215*0.80 = 172 라 이 값보다 크다. 둘 중 하나를 바꾸면 다른 쪽도 봐라.
##   (tests/ns_check 의 _check_geometry 가 이걸 지킨다)
const INNER_R := 150.0
## 바깥에서 안쪽 한계까지 조여 오는 데 걸리는 시간(초). 종류별 속도 배수가 곱해진다.
## ★ 이 값이 크면 몬스터가 사거리 안으로 못 들어와서 **아무도 아무것도 못 때린 채**
##   시간이 끝난다. 26초로 뒀더니 1탄부터 일곱 마리가 그냥 살아 나갔다. 실제로 물렸다.
##   TIER_RNG(사거리)·SPAWN_R 과 한 몸이니 하나를 고치면 tests/balance_check 를 꼭 돌려라.
const CLOSE_IN_SEC := 13.0
## 접선 속도(px/초). 반지름이 작아질수록 각속도가 커져 안쪽이 빠르게 휘몰아친다.
const TANGENT_SPEED := 105.0
## 각속도 상한(라디안/초). 없으면 안쪽 한계에서 눈이 아플 만큼 빨리 돈다.
const MAX_ANGULAR := 2.0
## 영웅 하나가 차지하는 폭. 사람이 늘면 좁혀 세운다(아래 hero_spacing).
const HERO_SPACING := 44.0
## 영웅 무리가 퍼질 수 있는 최대 반지름. INNER_R 보다 작아야 몬스터와 안 겹친다.
const HERO_MAX_R := 118.0

# --------------------------------------------------------------------------- #
# 한 판(런)의 기본값
# --------------------------------------------------------------------------- #
const START_LIVES := 20
const MAX_LIVES := 40
const START_GOLD := 60
## 라운드 제한 시간. 보스탄은 더 길다.
const ROUND_SEC := 30.0
const BOSS_ROUND_SEC := 42.0
## 몇 탄마다 보스가 나오는가.
const BOSS_EVERY := 5
## 마지막 탄. 여기를 넘기면 이긴 것이다.
const LAST_WAVE := 40

# --------------------------------------------------------------------------- #
# 족보 등급별 기본 능력치 — 인덱스가 Poker.Hand 값과 같다
#   atk   한 대 데미지
#   rate  초당 공격 횟수
#   rng   사거리(px)
# 등급 하나 올라갈 때 DPS 가 약 1.6배씩 오른다. 이 배수를 키우면 로열 한 방에
# 게임이 끝나 버리고, 줄이면 족보를 맞춘 보람이 없어진다.
# --------------------------------------------------------------------------- #
const TIER_ATK  := [5.0, 8.0, 13.0, 21.0, 33.0, 52.0, 82.0, 128.0, 200.0, 320.0]
const TIER_RATE := [1.00, 1.05, 1.10, 1.15, 1.20, 1.25, 1.30, 1.35, 1.40, 1.50]
const TIER_RNG  := [215.0, 228.0, 242.0, 258.0, 275.0, 293.0, 313.0, 335.0, 360.0, 400.0]

## 같은 등급 안에서 캐릭터의 결을 가르는 배수. DPS 합은 거의 같게 맞춰 놨다
## (rapid 1.045 · heavy 1.05 · sniper 1.04 · guard 1.08) — guard 만 사거리가 짧은 대신 조금 세다.
const PROFILE := {
	"balance": {"atk": 1.00, "rate": 1.00, "rng": 1.00, "ko": "균형"},
	"rapid":   {"atk": 0.55, "rate": 1.90, "rng": 0.90, "ko": "연사"},
	"heavy":   {"atk": 2.10, "rate": 0.50, "rng": 1.05, "ko": "일격"},
	"sniper":  {"atk": 1.30, "rate": 0.80, "rng": 1.55, "ko": "저격"},
	"guard":   {"atk": 0.92, "rate": 1.15, "rng": 0.80, "ko": "수호"},
}

## 공격 방식. dmg 는 기본 데미지 배수다 — 부수 효과가 좋을수록 배수를 깎아 균형을 잡는다.
const BULLET := {
	"shot":   {"ko": "단발", "dmg": 1.00, "speed": 640.0},
	"pierce": {"ko": "관통", "dmg": 0.80, "speed": 760.0, "pierce": 3},
	"splash": {"ko": "광역", "dmg": 0.70, "speed": 520.0, "radius": 48.0, "falloff": 0.7},
	"chain":  {"ko": "연쇄", "dmg": 0.75, "speed": 900.0, "jumps": 3, "decay": 0.65, "hop": 130.0},
	"beam":   {"ko": "광선", "dmg": 1.15, "speed": 0.0},
	"slow":   {"ko": "둔화", "dmg": 0.85, "speed": 600.0, "slow": 0.25, "slow_sec": 2.0},
	"burn":   {"ko": "화상", "dmg": 0.80, "speed": 600.0, "burn": 0.35, "burn_sec": 3.0},
	# ★ 장판은 **사거리 안 모두**를 동시에 때린다. 다른 방식과 같은 배수를 주면
	#   몬스터가 50마리일 때 혼자 50배를 뽑는다(실제로 그래서 40탄이 그냥 깨졌다).
	#   그래서 한 마리당 피해를 크게 깎아 둔다 — 여럿일 때만 이득인 것이 이 방식의 정체다.
	"aura":   {"ko": "장판", "dmg": 0.10, "speed": 0.0},
}

# --------------------------------------------------------------------------- #
# 몬스터
# --------------------------------------------------------------------------- #
## hp 배수 · 속도 배수 · 골드 배수.
## ★ 그림 크기(h)는 여기 두지 않는다 — core/roster.gd 가 tools/gen_art.py 가 실제로
##   저장한 픽셀 높이를 들고 있고, 두 곳에 적으면 반드시 어긋난다.
const MKIND := {
	"swarm":  {"hp": 0.75, "spd": 1.00, "gold": 1.0, "ko": "떼거리"},
	"fast":   {"hp": 0.60, "spd": 1.75, "gold": 1.1, "ko": "쾌속"},
	"tank":   {"hp": 2.40, "spd": 0.75, "gold": 1.4, "ko": "육중"},
	"caster": {"hp": 1.00, "spd": 0.85, "gold": 1.2, "ko": "주술"},
	"boss":   {"hp": 14.0, "spd": 0.50, "gold": 12.0, "ko": "보스"},
}
## 주술사가 거는 저주 — 영웅 전체의 공격속도를 이만큼 깎는다. 겹치지 않고 시간만 새로 찬다.
const CURSE_RATE := 0.18
const CURSE_SEC := 2.5
## 주술사가 저주를 던지는 간격(초).
const CURSE_EVERY := 6.0

## w 탄의 몬스터 한 마리 기준 체력.
## ★ 1.28 이라는 지수는 손으로 고른 게 아니라 tests/balance_check 를 돌려서 맞춘 값이다.
##   1.255 → 12판 전부 클리어(너무 쉽다) · 1.30 → 한 판도 못 깬다 · 1.28 → 중간값 37탄,
##   12판 중 3판 클리어. **이 줄을 건드리면 반드시 다시 돌려라.**
static func wave_hp(w: int) -> float:
	return 12.0 * pow(1.28, float(w - 1))

## w 탄의 몬스터 수(보스 제외).
static func wave_count(w: int) -> int:
	if is_boss_wave(w):
		return 4 + int(floor(float(w) * 0.5))
	return 5 + int(floor(float(w) * 1.2))

static func is_boss_wave(w: int) -> bool:
	return w % BOSS_EVERY == 0

static func round_sec(w: int) -> float:
	return BOSS_ROUND_SEC if is_boss_wave(w) else ROUND_SEC

## 몬스터 한 마리를 잡았을 때 나오는 골드(배수 적용 전).
static func kill_gold(w: int, kind: String) -> int:
	var base := 3.0 + float(w) * 0.25
	return int(round(base * float(MKIND[kind]["gold"])))

## 라운드를 마쳤을 때의 보너스. 남은 시간이 아니라 **전멸시켰는가**에 크게 준다 —
## 시간에 비례해 주면 약한 판을 질질 끄는 쪽이 이득이 되는 순간이 생긴다.
static func clear_bonus(w: int, wiped: bool, left_sec: float) -> int:
	var g := 10 + w * 2
	if wiped:
		g += 20 + int(left_sec)
	return g

# --------------------------------------------------------------------------- #
# 카드 리롤 — "한 번 리롤한 카드는 추가 골드를 내야 더 리롤할 수 있다"
# --------------------------------------------------------------------------- #
## 카드 한 장당 공짜 리롤 횟수(기본). 상점에서 늘릴 수 있다.
const FREE_REROLL := 1
## 공짜를 다 쓴 뒤 n 번째 유료 리롤의 값 (n 은 1부터).
static func reroll_cost(paid_times: int) -> int:
	return int(15 * pow(2.0, float(paid_times)))

# --------------------------------------------------------------------------- #
# 상점 — 값이 오르는 능력치. lv 은 지금까지 산 횟수.
# --------------------------------------------------------------------------- #
const UPGRADES := [
	{"id": "atk",    "ko": "공격력",     "desc": "모든 영웅 공격력 +15%",     "base": 40,  "grow": 1.34, "cap": 0},
	{"id": "rate",   "ko": "공격속도",   "desc": "모든 영웅 공격속도 +9%",    "base": 45,  "grow": 1.37, "cap": 0},
	{"id": "rng",    "ko": "사거리",     "desc": "모든 영웅 사거리 +8%",      "base": 35,  "grow": 1.30, "cap": 12},
	{"id": "crit",   "ko": "치명타 확률", "desc": "치명타 확률 +5%",          "base": 60,  "grow": 1.40, "cap": 11},
	{"id": "critx",  "ko": "치명타 배율", "desc": "치명타 배율 +0.35배",      "base": 70,  "grow": 1.42, "cap": 0},
	{"id": "gold",   "ko": "골드 획득",   "desc": "처치 골드 +12%",           "base": 55,  "grow": 1.45, "cap": 0},
	{"id": "life",   "ko": "목숨",       "desc": "목숨 +1",                  "base": 80,  "grow": 1.62, "cap": 20},
	{"id": "reroll", "ko": "공짜 리롤",   "desc": "카드마다 공짜 리롤 +1",     "base": 50,  "grow": 1.55, "cap": 4},
	{"id": "time",   "ko": "제한 시간",   "desc": "라운드 시간 +2초",         "base": 90,  "grow": 1.50, "cap": 6},
]

static func upgrade_cost(id: String, lv: int) -> int:
	for u in UPGRADES:
		if u["id"] == id:
			return int(round(float(u["base"]) * pow(float(u["grow"]), float(lv))))
	return 0

## 그 능력치를 더 살 수 있는가. cap 이 0 이면 한도가 없다.
static func upgrade_maxed(id: String, lv: int) -> bool:
	for u in UPGRADES:
		if u["id"] == id:
			return int(u["cap"]) > 0 and lv >= int(u["cap"])
	return true

# --------------------------------------------------------------------------- #
# 패시브 — 한 번만 산다. 상점이 매번 이 중 셋을 골라 내놓는다.
# --------------------------------------------------------------------------- #
const PASSIVES := [
	{"id": "flame",  "ko": "화염 부적", "desc": "모든 공격이 3초간 태운다",        "cost": 140},
	{"id": "frost",  "ko": "서리 부적", "desc": "모든 공격이 2초간 느리게 만든다",  "cost": 140},
	{"id": "pierce", "ko": "관통 촉",   "desc": "모든 탄이 한 마리를 더 뚫는다",    "cost": 170},
	{"id": "vamp",   "ko": "흡혈",     "desc": "처치할 때 4% 확률로 목숨 +1",     "cost": 220},
	{"id": "bolt",   "ko": "연쇄 낙뢰", "desc": "12% 확률로 번개가 튄다",          "cost": 200},
	{"id": "midas",  "ko": "황금손",   "desc": "처치 골드 +25%",                 "cost": 180},
	{"id": "rage",   "ko": "광폭화",   "desc": "남은 10초 동안 공격속도 +50%",     "cost": 190},
	{"id": "first",  "ko": "첫 격돌",   "desc": "라운드 첫 5초 공격력 2배",        "cost": 190},
	{"id": "eye",    "ko": "도박꾼의 눈", "desc": "15% 확률로 족보가 한 단계 오른다", "cost": 260},
	{"id": "joker",  "ko": "조커",     "desc": "카드 한 장을 가장 좋은 패로 친다",  "cost": 950},
]

const PASSIVE_FLAME_BURN := 0.30
const PASSIVE_FLAME_SEC := 3.0
const PASSIVE_FROST_SLOW := 0.22
const PASSIVE_FROST_SEC := 2.0
const PASSIVE_VAMP_P := 0.04
const PASSIVE_BOLT_P := 0.12
const PASSIVE_MIDAS := 0.25
const PASSIVE_RAGE := 0.50
const PASSIVE_RAGE_LEFT := 10.0
const PASSIVE_FIRST := 2.0
const PASSIVE_FIRST_SEC := 5.0
const PASSIVE_EYE_P := 0.15

const CRIT_BASE_MULT := 2.0

## 업그레이드 단계를 실제 배수로. 전투와 검사기가 **같은 함수**를 써야
## "검사기에서는 되는데 게임에서는 안 되는" 종류의 어긋남이 안 생긴다.
static func atk_mult(lv: int) -> float:
	return pow(1.15, float(lv))

static func rate_mult(lv: int) -> float:
	return pow(1.09, float(lv))

static func rng_mult(lv: int) -> float:
	return pow(1.08, float(lv))

static func crit_chance(lv: int) -> float:
	return min(0.60, 0.05 * float(lv))

static func crit_mult(lv: int) -> float:
	return CRIT_BASE_MULT + 0.35 * float(lv)

static func gold_mult(lv: int) -> float:
	return pow(1.12, float(lv))


# --------------------------------------------------------------------------- #
# 영웅이 서는 자리 — 사람이 늘수록 촘촘하게, 여러 겹으로
# --------------------------------------------------------------------------- #
## n 명일 때 한 명이 차지하는 폭. 40탄이면 영웅이 40명이라 좁히지 않으면 화면을 넘는다.
static func hero_spacing(n: int) -> float:
	return clampf(HERO_SPACING - float(maxi(0, n - 8)) * 0.42, 28.0, HERO_SPACING)

## n 명 중 i 번째 영웅이 설 자리(투기장 중심 기준 상대 좌표).
##
## ★ 한 명일 때만 정중앙이고, 둘 이상이면 **아무도 가운데 서지 않는다.**
##   예전에는 0번을 가운데 두고 1번을 첫 겹에 세웠는데, 둘뿐일 때 두 그림이 겹쳐
##   한 덩어리로 보였다. 지금은 그 겹에 실제로 설 사람 수로 나눠 고르게 벌린다.
static func hero_slot(i: int, n: int) -> Vector2:
	if n <= 1:
		return Vector2.ZERO
	var sp := hero_spacing(n)
	var idx := i
	var placed := 0
	# 겹은 열두 개면 충분하다. 넘어가면 가운데로 보낸다(있을 수 없는 일이지만).
	for ring in range(1, 13):
		var r: float = min(HERO_MAX_R, float(ring) * sp * 1.25)
		var cap: int = maxi(4, int(floor(TAU * r / sp)))
		var take: int = mini(cap, n - placed)
		if idx < take:
			var a := TAU * float(idx) / float(take) - PI * 0.5
			return Vector2(cos(a), sin(a)) * r
		idx -= take
		placed += take
		if placed >= n:
			break
	return Vector2.ZERO

## 영웅이 늘어날수록 그림을 조금씩 줄인다. 안 그러면 가운데가 그림 무더기가 된다.
static func hero_scale(n: int) -> float:
	return clampf(1.0 - float(maxi(0, n - 8)) * 0.011, 0.62, 1.0)
