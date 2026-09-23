extends RefCounted
class_name Balance

## 게임의 숫자가 **전부** 여기 있다. 순수 함수만 두고 화면·저장을 모른다.
##
## 왜 한곳에 모았나: 디펜스 게임은 "이 판이 왜 안 깨지는지"를 사람이 손으로 계산할 수
## 있어야 고칠 수 있다. 숫자가 전투 코드 안에 흩어지면 그게 불가능해진다.
## tests/balance_check.gd 가 이 표만 읽어 40탄까지 자동으로 돌려 보고 클리어율을 뽑는다.

# --------------------------------------------------------------------------- #
# 투기장 — 벽으로 나뉜 길과, 그 안쪽의 전장
# --------------------------------------------------------------------------- #
## voc2.png: two interleaved routes with an additional inner turn around the shrine.
## Every theme and the simulation share these points; route 1 is point-mirrored.
const ARENA_CENTER := Vector2(416, 420)
const MAP_RECT := Rect2(20, 112, 792, 620)
const ROUTE_POINTS := [Vector2(24, 150), Vector2(156, 150), Vector2(156, 690),
	Vector2(606, 690), Vector2(606, 210), Vector2(296, 210),
	Vector2(296, 520), Vector2(476, 520), Vector2(476, 420), Vector2(474, 420)]
const POST_POINTS := [Vector2(74, 260), Vector2(74, 380), Vector2(74, 500), Vector2(74, 620),
	Vector2(380, 282), Vector2(452, 282), Vector2(380, 568), Vector2(452, 568),
	Vector2(758, 260), Vector2(758, 380), Vector2(758, 500), Vector2(758, 620)]
const POST_ORDER := [4, 0, 8, 5, 1, 9, 6, 2, 10, 7, 3, 11]
## Keep walking speed unchanged: the extra inner turn extends the base walk to 30.5s.
const PATH_SPEED := 82.0
const LANE_JITTER := 10.0
const GATE_NARROW := 28.0
const ROAD_WIDTH := 46.0

## 크리스탈 제단. 길의 끝이 여기다.
## ★ 74 에서 58 로 좁혔다. 크리스탈이 **무더기**로 모이면서(아래) 제단이 감쌀 것이
##   작아졌기 때문이다. 넓은 채로 두면 제단만 텅 빈 접시로 남는다.
const ALTAR_R := 58.0
## 크리스탈이 놓이는 자리 — 제단 한가운데에 **촘촘히 쌓인 무더기**. 안쪽부터 겹마다 몇 개씩.
##
## ★ 사용자가 정한 것: 「크리스탈 20개 모여있는 데를 좀 더 좁히고 대신 안에도 꽉꽉 채워서
##   캐릭과 일러스트가 겹치지 않게」.
## ★ 예전에는 스무 개가 **고리 하나**(반지름 62)로 넓게 둘러서 있었다. 그 고리의 바깥
##   테두리가 77 까지 뻗는데 영웅은 108 에 서므로, 96~161px 짜리 영웅 그림(발밑 기준으로
##   위로 자란다)의 정강이와 허리를 크리스탈이 가로질러 그어졌다 — 크리스탈은 배우보다
##   **나중에** 그리기 때문이다(battle_screen 의 그리기 차례).
## ★ 지금은 1 · 6 · 13 개씩 세 겹으로 **모아 쌓는다.** 바깥 테두리가 77 → 44 로 줄어
##   영웅 그림과 닿는 넓이가 3분의 1 이 된다. 안쪽을 비우지 않는 것(가운데에 한 개)이
##   「꽉꽉 채워서」의 몫이다 — 고리로 두면 가운데가 뚫린 도넛이 되어 더 넓어진다.
const CRYSTAL_RING_N := [1, 6, 13]
const CRYSTAL_R := [0.0, 15.0, 30.0]
## 크리스탈 한 개를 그리는 반지름.
## ★ `Look.CRYSTAL_PX`(9.0) 밑으로 내리지 마라 — 그 밑에서는 그림(art/ui/crystal.png)이
##   아니라 도형으로 되돌아간다. 무더기를 더 좁히고 싶으면 알을 줄이지 말고 겹 반지름
##   (CRYSTAL_R)을 줄여라. 다만 서로 겹치지 않을 만큼은 띄워야 한다(ns_check 가 잰다).
const CRYSTAL_DRAW_R := 9.0

## 출전할 수 있는 영웅 수와 발판 수. 발판은 좌/중/우 4곳씩 총 12곳이고, 영웅은 발판마다
## 하나씩 서므로 둘은 언제나 같다(POST_POINTS · POST_ORDER 가 열두 자리다).
const HERO_SLOTS := 12
const POST_SLOTS := 12

## 영웅 전당(벤치)에 넣어 둘 수 있는 수. **사실상 무제한**이다.
## ★ **캐릭터 수보다 커야 한다.** 넘칠 수 있게 두면 `Run.gain_hero()` 가 가장 오래된
##   영웅을 조용히 지우게 되는데, "내 영웅이 사라졌다"는 규칙은 안 만든다.
##   `ns_check` 가 이 부등식을 잰다.
const BENCH_SLOTS := 10000

## 같은 캐릭터가 또 나오면 옆에 세우지 않고 **겹친다.** 화면에는 「x4」로 적는다.
##
## ★ **겹치면 공격 자체가 그 수만큼 나간다** (사용자가 정한 것: 「그냥 샷이 배수로
##   나가는걸로, 추가효과도 같이 배수로」). 예전에는 공격력만 n배였는데, 그러면
##   광역 반경도 연쇄 횟수도 마비 굴림도 한 번뿐이라 「x8」이 화면에서 하나도 안 보였다.
##   지금은 x4 면 탄이 넷 나가고, 넷이 저마다 터지고 저마다 상태이상을 굴린다.
## ★ 다만 **탄 수에는 상한을 둔다**(STACK_SHOT_MAX). x16 이 되면 영웅 여섯이 한 발에
##   96발을 뿌려서 폰이 먼저 무너진다. 상한을 넘는 몫은 **한 발의 세기**로 돌린다 —
##   단일 대상 피해는 언제나 정확히 n배로 같다(stack_shots x stack_atk = n).
const STACK_SHOT_MAX := 5

## 한 번에 몇 발이 나가는가.
static func stack_shots(n: int) -> int:
	return clampi(n, 1, STACK_SHOT_MAX)

## 그 한 발의 세기 배수. 발 수와 곱하면 언제나 n 이다.
static func stack_atk(n: int) -> float:
	var k := maxi(1, n)
	return float(k) / float(stack_shots(k))

# --------------------------------------------------------------------------- #
# 한 판(런)의 기본값
# --------------------------------------------------------------------------- #
## 시작 크리스탈 = 시작 목숨. 화면 가운데에 이 개수만큼 놓인다.
##
## ★ **최대치는 늘지 않는다** (사용자가 정한 것: 「크리스탈은 무조건 max 20개」).
##   예전에는 상점의 「크리스탈 +1」이 최대치를 같이 올려서, 잘 하는 판일수록 크리스탈이
##   20 에서 31 로 **늘어** 있었다 — 목숨이 늘어나는 디펜스는 긴장이 통째로 사라진다.
##   깨진 것은 상점에서 **골드로 다시 사서** 20 까지만 채운다(repair_cost).
const START_LIVES := 20
const MAX_LIVES := 20
const START_GOLD := 60
const REVIVE_GOLD := 1_000_000
## 몇 탄마다 보스가 나오는가. **한 테마 블록이 열 탄이고 그 마지막이 보스맵이다** —
## 그래서 이 값과 THEME_BLOCK 은 언제나 같아야 한다.
const BOSS_EVERY := 10
## 한 테마가 몇 탄을 맡는가. 10·20·30…100탄이 보스맵이다.
const THEME_BLOCK := 10
## 마지막 탄. 여기를 넘기면 이긴 것이다. 100탄 = 테마 블록 열 개.
const LAST_WAVE := 100
## 그 탄의 몬스터가 전부 나오는 데 걸리는 시간(초).
## ★ 길게 잡으면 마지막 놈이 나올 때 앞엣놈은 벌써 크리스탈에 닿아 있다 — 한 번에
##   두어 마리씩만 상대하게 되어 광역·장판이 통째로 무의미해진다.
const SPAWN_WINDOW := 9.0

# --------------------------------------------------------------------------- #
# 족보 등급별 기본 능력치 — 인덱스가 Poker.Hand 값과 같다
#   atk   한 대 데미지
#   rate  초당 공격 횟수
# 등급 하나 올라갈 때 DPS 가 약 1.6배씩 오른다. 이 배수를 키우면 로열 한 방에
# 게임이 끝나 버리고, 줄이면 족보를 맞춘 보람이 없어진다.
# --------------------------------------------------------------------------- #
const TIER_ATK  := [5.0, 8.0, 13.0, 21.0, 33.0, 52.0, 82.0, 128.0, 200.0, 320.0]
const TIER_RATE := [1.00, 1.05, 1.10, 1.15, 1.20, 1.25, 1.30, 1.35, 1.40, 1.50]
# --------------------------------------------------------------------------- #
## 사거리는 영웅 발판에서 몬스터 중심까지의 거리다.
## 무기·공격 성향·희귀도에 따라 달라지며 공격력 강화로 늘어나지 않는다.
const WEAPON_RANGE := {"sword": 170.0, "whip": 205.0, "deck": 235.0, "gun": 285.0, "bow": 320.0}
const PROFILE_RANGE := {"rapid": 0.93, "balance": 1.0, "heavy": 0.97, "sniper": 1.10}

static func attack_range(unit: Dictionary, tier: int = -1) -> float:
	var rank := clampi(int(unit.get("tier", 0)) if tier < 0 else tier, 0, 9)
	var base: float = WEAPON_RANGE.get(String(unit.get("weapon", "deck")), 235.0)
	var multiplier: float = PROFILE_RANGE.get(String(unit.get("profile", "balance")), 1.0)
	return clampf(roundf((base + rank * 6.0) * multiplier), 160.0, 400.0)

## 같은 등급 안에서 캐릭터의 결을 가르는 배수. **축은 하나다** — 연사에서 일격까지,
## 「잘게 여러 번」과 「크게 한 번」 사이 어디에 서는가. 넷 다 초당 피해(atk x rate)는
## 거의 같게 맞춰 놨다(1.045 · 1.00 · 1.0385 · 1.05).
## 합이 같아도 피해의 모양은 다르다. 연사는 치명타를 자주 굴리고 화상을 계속 덧발라 잔몹을 훑고,
##   일격은 한 대가 크니 넘치는 몫(오버킬)을 버리는 대신 두꺼운 놈을 한 번에 끊는다.
## 정밀(sniper)은 같은 무기보다 사거리가 길고 연사는 짧다(PROFILE_RANGE).
## ★ 예전에 있던 「수호(guard)」는 없앴다 — 공격력도 공격속도도 낮아 설 자리가 없었다.
const PROFILE := {
	"rapid":   {"atk": 0.55, "rate": 1.90, "ko": "연사"},
	"balance": {"atk": 1.00, "rate": 1.00, "ko": "균형"},
	"sniper":  {"atk": 1.55, "rate": 0.67, "ko": "정밀"},
	"heavy":   {"atk": 2.10, "rate": 0.50, "ko": "일격"},
}

## 공격 방식 여섯. **어떻게 닿는가**만 정한다. dmg 는 기본 데미지 배수다 —
## 부수 효과가 좋을수록 배수를 깎아 균형을 잡는다.
##
## ★ 예전에 있던 「둔화(slow)」·「화상(burn)」 방식을 **없앴다.** 둘은 방식이 아니라
##   **속성이 붙이는 것**이다(ELEM 의 rider). 방식으로 두면 「불 속성인데 안 태우는 영웅」과
##   「무상성인데 태우는 영웅」이 같이 생겨서, 플레이어가 화면을 보고 규칙을 배울 수가 없다.
##   지금은 얼음이면 반드시 느려지고 불이면 반드시 탄다 — 예외가 없다.
const BULLET := {
	"shot":   {"ko": "단발", "dmg": 1.00, "speed": 640.0},
	"pierce": {"ko": "관통", "dmg": 0.80, "speed": 760.0, "pierce": 3},
	"splash": {"ko": "광역", "dmg": 0.70, "speed": 520.0, "radius": 48.0, "falloff": 0.7},
	"chain":  {"ko": "연쇄", "dmg": 0.75, "speed": 900.0, "jumps": 3, "decay": 0.65, "hop": 130.0},
	# ★ **도탄** — 맞은 자리에서 **아무 데로나** 튕긴다. 연쇄와 다른 점이 셋이다:
	#   1. 연쇄는 **가장 가까운** 놈으로 간다(argmin). 도탄은 닿는 거리 안에서
	#      **무작위로** 고른다 — 그래서 「어디로 튈지 모른다」가 화면에서 읽힌다.
	#   2. 연쇄는 순간이동한다(번개니까). 도탄은 **실제로 날아간다** — 탄이 꺾여서
	#      다음 놈에게 간다. 그래서 화면이 번개가 아니라 꺾인 궤적으로 그린다.
	#   3. ★ 연쇄는 반드시 전기다(CLAUDE.md 5-4, 화면이 번개로 그리므로). 도탄은
	#      **어느 속성이든 된다** — 튕기는 것은 물건이지 번개가 아니기 때문이다.
	#   한 대는 연쇄보다 약하다(0.56 vs 0.75). 사용자가 정한 것: 「공격이 조금 약할수
	#   있으나 랜덤으로 튕기는 공격」.
	"ricochet": {"ko": "도탄", "dmg": 0.56, "speed": 700.0,
		"bounce": 3, "decay": 0.80, "hop": 210.0},
	"beam":   {"ko": "광선", "dmg": 1.15, "speed": 0.0},
	# ★ **장판(zone)** — 예전의 「장판(aura)」을 통째로 갈아 끼운 것이다.
	#
	#   사용자가 정한 것: 「광역마법같은경우는 굳이 캐릭터에서 바로 샷이 나갈 필요없고
	#   약간 두팔을 들어올림과 동시에 발밑에서 머리위로 이펙트가 지나가고, 그게 특정
	#   area 에 특정범위를 가진 애니메이션을 생성하고 **그 범위에 해당되는 애들만**
	#   데미지를 받도록」.
	#
	#   ★ 옛 aura 는 **판 위의 전부**를 언제나 때렸다. 그래서 한 마리당 몫을 0.085 까지
	#     깎아야 했고(몬스터가 50마리면 혼자 50배를 뽑았다), 그러면 화면에 그릴 「범위」가
	#     아예 없어서 무엇이 왜 맞고 있는지가 안 보였다. 지금은 **범위가 진짜로 있다** —
	#     그리는 원이 곧 맞는 자리이고, 그래서 배수를 정상으로 되돌릴 수 있었다.
	#   ★ **이것은 사거리가 아니다**(CLAUDE.md 14). 영웅은 여전히 판 위 어디든 때린다 —
	#     장판은 「내가 어디까지 닿는가」가 아니라 「내가 **어디를** 때리기로 골랐는가」다.
	#     자리는 `BattleSim._zone_spot()` 이 **가장 많이 겹치는 곳**으로 고른다.
	#
	#   cast   두 팔을 들어 발밑에서 머리 위로 이펙트가 지나가는 시간(초).
	#   delay  다 든 뒤 땅에 깔리기까지(초). 이 틈이 「어디에 깔릴지」를 보여 준다.
	#   dur    깔린 채로 남는 시간(초). 걸어 들어온 놈도 맞는다.
	#   tick   때리는 간격(초). 한 번 시전한 몫(dmg)을 틱 수로 나눠 준다 —
	#          그래서 **단일 대상 초당 피해는 dmg 배수 그대로**이고, Run.total_dps()
	#          가 거짓말을 하지 않는다. 여럿을 덮는 몫이 그대로 이 방식의 값어치다.
	"zone":   {"ko": "장판", "dmg": 0.62, "speed": 0.0, "radius": 128.0,
		"cast": 0.34, "delay": 0.26, "dur": 1.10, "tick": 0.25},
}

## 시전한 장판 하나가 때리는 횟수. dur 를 tick 으로 나눈 것에 깔리는 순간 한 번을 더한다.
static func zone_ticks() -> int:
	var z: Dictionary = BULLET["zone"]
	return maxi(1, int(floor(float(z["dur"]) / float(z["tick"]))) + 1)

# --------------------------------------------------------------------------- #
# 역할 넷 — **등급마다 이 넷이 전부 선다**
#
# 사용자가 정한 것: 「대체로 광역 데미지주는것들이 상위티어에 몰려있는데 그러지말고
# 티어별로 단일타겟이지만 데미지가 센 캐릭, 공격이 조금 약할수있으나 랜덤으로 튕기는
# 공격을하는 캐릭, 특정 효과를 갖는 단일타겟을 하는 캐릭, 광역데미지를 주는 캐릭 등
# 풍부하게 생성바라」.
#
# ★ 역할은 **탄 방식(bullet)과 다른 축이다.** 방식은 「어떻게 닿는가」이고 역할은
#   「무엇으로 값을 하는가」다. 같은 `shot` 이라도 일격은 한 대가 무겁고 특효는
#   한 대가 가벼운 대신 상태이상이 두 배다.
# ★★ **역할은 무기가 정한다** (설계서 §2 — 「무기는 전부 카드를 다루는 손동작에서
#   나왔다」). 등급 하나에 **다섯**이 서고 그 다섯이 **속성 다섯 x 무기 다섯**이라,
#   무기가 역할을 정하면 등급마다 역할 배분이 **한 톨도 안 흔들린다**:
#     검 sword 컷    → 일격  한 번에 무겁게 벤다
#     총 gun   딜링  → 일격  카드 한 장 = 탄 한 발, 정밀 단일
#     활 bow   플릭  → 도탄  튕겨 날린다 (설계서에 도약·분산이 반복된다)
#     채찍 whip 리플 → 특효  파동이 중첩을 남긴다 (설계서에 제어가 반복된다)
#     광역 deck 올인 → 광역
#   ☆ 그래서 등급마다 **일격 2 · 도탄 1 · 특효 1 · 광역 1** 이고, 열 등급이 다 같다.
#     한 줄이라도 어긋나면 플레이어가 무기를 보고 성능을 못 읽는다 —
#     `ns_check._check_roster` 가 쉰 줄을 다 잰다.
# --------------------------------------------------------------------------- #
const ROLE := {
	"single":   {"ko": "일격", "atk": 1.26, "desc": "단일 대상 고화력 공격"},
	"ricochet": {"ko": "도탄", "atk": 1.00, "desc": "낮은 피해 · 무작위 도탄"},
	"rider":    {"ko": "특효", "atk": 0.74, "desc": "낮은 피해 · 부가 효과 강화"},
	"area":     {"ko": "광역", "atk": 1.00, "desc": "범위 내 모든 적 공격"},
}
const ROLE_ORDER := ["single", "ricochet", "rider", "area"]

## 「특효」가 속성마다 무엇을 세게 하는가.
##
## ★ **불·얼음·전기**는 그 속성이 늘 붙이는 상태이상 자체가 RIDER_MULT 배로 세진다.
##   상태이상을 속성이 정한다는 규칙(CLAUDE.md 5-4-1)은 그대로다 — 세기만 바뀐다.
## ★ **물**은 상태이상이 없다. 대신 맞은 놈을 **뒤로 민다** — 걸은 거리를 되돌린다.
##   디펜스에서 이보다 값진 「효과」가 없고, 물의 결(물살)과도 맞는다.
##   ☆ 한 마리가 한 번에 밀릴 수 있는 총량에 뚜껑을 씌운다(RIDER_PUSH_MAX). 없으면
##     물 특효 여섯이 길목에서 몬스터를 **영원히 제자리에** 붙들어 전투가 멎는다
##     (마비에 STUN_IMMUNE_SEC 을 둔 것과 정확히 같은 까닭이다 — CLAUDE.md 5-4-2).
## ★ **무상성**도 상태이상이 없다. 대신 **치명타**에 특화된다.
##   ☆ 이것은 몬스터에게 아무것도 안 붙인다 — 쏘는 쪽의 능력치다. 그래서
##     「무상성은 어떤 몸에도 1.0배이고 상태이상이 없다」(CLAUDE.md 5-2)가 그대로 산다.
##     여기에 몬스터에게 붙는 효과를 만들면 그 규칙이 깨진다. 만들지 마라.
const RIDER_MULT := 2.2
const RIDER_PUSH := 34.0        ## 물 특효가 한 대에 되돌리는 걸음 거리(px)
const RIDER_PUSH_MAX := 170.0   ## 한 마리가 통틀어 밀릴 수 있는 총량(px). 스톨 방지.
const RIDER_PUSH_SEC := 0.28    ## 한 번의 밀림은 이 시간 동안 감속하며 이동한다.
const RIDER_CRIT := 0.20        ## 무상성 특효의 치명타 확률 덤

## 그 역할이 「특효」인가. 상태이상 세기와 밀어내기가 여기에 달렸다.
static func role_rider(role: String) -> bool:
	return role == "rider"

## 그 영웅이 붙이는 상태이상의 세기 배수.
static func rider_mult(role: String) -> float:
	return RIDER_MULT if role == "rider" else 1.0

static func role_ko(r: String) -> String:
	return String(ROLE.get(r, ROLE["single"])["ko"])

# --------------------------------------------------------------------------- #
# 속성 — 다섯 가지 공격과, 몬스터의 다섯 가지 몸
# --------------------------------------------------------------------------- #
## 공격 속성 다섯. 영웅마다 하나씩 갖는다(tools/roster.json 의 elem).
##
## ★ **속성이 상태이상을 정한다. 탄 방식(bullet)이 아니다.** 이것이 예전 규칙과 갈라지는
##   가장 큰 자리다 — 옛날에는 「둔화탄」·「화상탄」이라는 **방식**이 따로 있어서, 불 속성인데
##   안 태우는 영웅과 무상성인데 태우는 영웅이 같이 있었다. 그러면 플레이어가 화면에서
##   규칙을 배울 수가 없다. 지금은 얼음이면 반드시 느려지고 불이면 반드시 탄다.
##   방식(shot·pierce·splash·chain·beam·aura)은 **어떻게 닿는가**만 정한다.
##
## ★ **무상성(none)은 언제나 정확히 1.0 배다.** 활·총·대포·표창처럼 마법이 아닌 것들이
##   여기 들어간다. 상성으로 재미를 보지 못하는 대신 **어떤 몬스터에게도 손해를 안 본다** —
##   이것이 무상성 영웅의 값어치 전부다. 여기에 예외를 만들면(예: 무상성이 어떤 몸에 약하다)
##   "안전한 줄" 자체가 없어져서 뽑기가 순전히 운이 된다.
##
## ★ **물(water)만 상태이상이 없다.** 사용자가 정한 규칙이 얼음=둔화 · 불=화상 · 전기=마비
##   셋뿐이기 때문이다. 그냥 두면 물은 「불·얼음과 상성 폭이 같은데 덤이 없는 줄」이 되어
##   고를 까닭이 없어진다. 그래서 물에만 **기본 화력 덤(dmg)** 을 준다 — 물은 상태이상
##   대신 순수 피해로 값을 한다. 이 숫자는 tests/balance_check 로 잰 것이다.
const ELEM := {
	"none":  {"ko": "무상성", "color": "#D8DEE6", "rider": "",     "dmg": 1.00},
	"fire":  {"ko": "불",     "color": "#FF6A2A", "rider": "burn", "dmg": 1.00},
	"ice":   {"ko": "얼음",   "color": "#7BDCFF", "rider": "slow", "dmg": 1.00},
	# ★★ **전기만 상성 폭이 통째로 좁다 — 그 몫을 기본 화력으로 돌려준다.**
	#   몸 다섯에 걸친 평균 배수를 재 보면 불·얼음·물은 1.10 인데(약점 둘·저항 둘)
	#   **전기는 0.80** 이다(약점 **하나**·**면역 둘**·나머지는 1.0). 대신 전기만 마비를
	#   건다 — 그런데 그 값어치는 `Run.total_dps()` 에 한 톨도 안 들어가서, 상점의
	#   「초당 피해」도 자동 플레이 정책도 전기를 **구조적으로 과소평가한다.**
	#   ★★ **평균이 그대로인데 화력을 1.20 → 1.44 로 올려야 했던 까닭**(나무를 면역으로
	#     바꾼 뒤): 평균 배수는 0.80 그대로다(나무가 0.5→0 으로 잃은 몫을 얼음이
	#     0.5→1.0 으로 받았다). 그런데 **자동 플레이 정책은 평균으로 안 센다** —
	#     `tests/policy.gd` 가 그 탄에 면역인 놈이 한 종 섞일 때마다 0.55 를 곱한다
	#     (디펜스에서 못 잡는 놈 하나는 평균의 문제가 아니기 때문이다). 면역인 몸이
	#     하나에서 둘이 되면서 **그 벌칙이 걸리는 탄이 대략 두 배**가 됐고, 그래서
	#     평균이 안 변했는데도 전기가 전장에서 밀려났다.
	#   실측(24판, 전장에 선 비율): 옛 표(면역 하나)에서 dmg 1.00 → **9.3%** /
	#   1.12 → 10.5% (문턱에 너무 붙었다) / 1.20 → 11.6%.
	#   **새 표(면역 둘)에서 같은 1.20 이 9.6% 로 떨어졌다** (verify.sh 의 「10% 밑이면
	#   죽은 속성」 검사에 걸린다) / 1.32 → 10.6% (또 문턱에 붙는다) /
	#   **1.44 → 11.4% (지금)** — 표를 바꾸기 전의 11.6% 를 되찾은 값이다.
	#   클리어율은 24판 중 5~6판으로 그대로다 — 전기는 전장의 10분의 1이라 여기를
	#   만져도 판 전체 화력은 1~2% 밖에 안 움직인다.
	#   ☆ 1.44 를 곱하면 전기의 기대 출력은 0.80 x 1.44 = **1.15** 로 불·얼음(1.10)을
	#     조금 넘고 물(1.10 x 1.12 = 1.23)보다는 낮다. 그 몫이 곧 **면역 둘의 값**이다 —
	#     전기는 판을 열에 여덟은 남에게 내주고, 제 자리에서만 세게 때린다.
	#   ☆ 물이 상태이상이 없는 몫을 1.12 로 돌려받는 것과 **똑같은 수법**이다.
	#   ☆ 상성 표(MBODY)는 사용자가 정한 것이라 안 건드린다. 고치는 것은 화력뿐이다.
	"elec":  {"ko": "전기",   "color": "#FFD84D", "rider": "stun", "dmg": 1.52},
	"water": {"ko": "물",     "color": "#3B8CFF", "rider": "",     "dmg": 1.12},
}
## 화면에 늘어놓을 때의 차례. 딕셔너리 순서에 기대지 않으려고 따로 둔다.
const ELEM_ORDER := ["none", "fire", "ice", "elec", "water"]

## 몬스터의 몸 다섯. 사용자가 정한 표를 그대로 옮긴 것이다.
##
##   | 몸        | 2.0배      | 0.5배            | 0.0배 |
##   |-----------|------------|------------------|-------|
##   | aqua 물   | elec       | water fire ice   | —     |
##   | flame 불  | water      | fire ice         | —     |
##   | wood 나무 | fire ice   | water elec       |       |
##   | rock 바위 | water ice  | fire             | elec  |
##   | frost 얼음| fire       | water ice        | —     |
##
## 전기는 물 2배, 불 1배, 나무 0.5배, 바위 0배, 얼음 1배다.
## 2026-09-14 사용자 요청으로 나무를 면역에서 저항으로 변경했다.
## 전기의 기본 화력·마비 확률과 다른 몸의 상성은 유지한다.
## 테마별 면역 몸의 합은 기존 상한을 유지하며 다음 탄 예고에서 상성을 확인할 수 있다.
##
## ★ **`color` 는 그 몸의 표시색이다.** 예전에는 이 다섯 색이 `game/theme_screen.gd` 의
##   `_body_color()` 안에만 있었다 — 테마 판의 막대 다섯만 색을 알고, 투기장·상점·편성
##   판은 몸을 색으로도 그림으로도 못 보여 줬다. 몸은 이 게임의 규칙 절반이라
##   **표 한 곳**(여기)에 있어야 한다.
const MBODY := {
	"aqua":  {"ko": "물",   "color": "#3B8CFF", "weak": ["elec"],        "resist": ["water", "fire", "ice"], "immune": []},
	"flame": {"ko": "불",   "color": "#FF6A2A", "weak": ["water"],       "resist": ["fire", "ice"],          "immune": []},
	"wood":  {"ko": "나무", "color": "#5AD07A", "weak": ["fire", "ice"], "resist": ["water", "elec"],       "immune": []},
	"rock":  {"ko": "바위", "color": "#C89B5A", "weak": ["water", "ice"],"resist": ["fire"],                 "immune": ["elec"]},
	"frost": {"ko": "얼음", "color": "#7BDCFF", "weak": ["fire"],        "resist": ["water", "ice"],        "immune": []},
}
## 화면에 늘어놓을 때의 차례.
const MBODY_ORDER := ["aqua", "flame", "wood", "rock", "frost"]

## 약점을 찌르면 2배, 저항에 막히면 반, 면역이면 0.
##
## ★ 이 셋을 고치면 **반드시 tests/balance_check 를 다시 돌려라.**
## ★ 상성 배수 자체는 **무딘 손잡이**다. 옛 표에서 저항을 0.40 으로 하든 0.70 으로 하든
##   클리어율이 24판 중 13~14판으로 거의 같았다. 밸런스를 다시 잡을 일이 생기면
##   상성이 아니라 **kill_gold** 를 만져라 — 그쪽이 훨씬 곱게 듣는다 (6% 만 덜어내도
##   14판이 7판이 된다).
const ELEM_WEAK := 2.0
const ELEM_RESIST := 0.5
const ELEM_IMMUNE := 0.0

## attack 속성의 공격이 body 몸에 들어갈 때의 피해 배수.
##
## ★ 데미지가 깎이는 곳은 BattleSim._hurt() 한 군데뿐이고, 그 한 줄이 이 함수를 부른다.
##   상성을 여러 곳에서 곱하기 시작하면 "광역은 상성을 타는데 연쇄는 안 타는" 식으로
##   조용히 갈라진다. (딱 하나 예외가 화상 도트다 — _burn() 이 붙이는 순간에 미리 곱한다)
## ★ 표에 없는 몸이 오면 1.0 이다. 화면이 안 죽게 하려는 것이지 규칙이 아니다 —
##   표에 없는 몸이 실제로 생기면 tests/ns_check 가 잡는다.
static func elem_mult(attack: String, body: String) -> float:
	if attack == "" or attack == "none":
		return 1.0
	var b: Dictionary = MBODY.get(body, {})
	if b.is_empty():
		return 1.0
	if (b["immune"] as Array).has(attack):
		return ELEM_IMMUNE
	if (b["weak"] as Array).has(attack):
		return ELEM_WEAK
	if (b["resist"] as Array).has(attack):
		return ELEM_RESIST
	return 1.0


## 그 속성이 명중할 때마다 거는 상태이상. "" 이면 없다 (무상성·물).
static func elem_rider(e: String) -> String:
	return String(ELEM.get(e, ELEM["none"]).get("rider", ""))

## 그 속성의 **기본 화력 배수.** 상성과 곱해진다. 물만 1.0 이 아니다.
static func elem_dmg(e: String) -> float:
	return float(ELEM.get(e, ELEM["none"]).get("dmg", 1.0))

## 그 속성의 이름 · 색. 표에 없는 값이 와도 화면이 안 죽게 무상성으로 받는다.
static func elem_ko(e: String) -> String:
	return String(ELEM.get(e, ELEM["none"])["ko"])

static func elem_color(e: String) -> Color:
	return Color(String(ELEM.get(e, ELEM["none"])["color"]))


## 그 몸의 이름. 표에 없으면 빈 문자열 — 화면이 그 줄을 통째로 건너뛴다.
static func body_ko(body: String) -> String:
	return String(MBODY.get(body, {}).get("ko", ""))

## 그 몸의 표시색. 표에 없으면 잿빛 — 화면이 안 죽게 하려는 것이지 규칙이 아니다.
static func body_color(body: String) -> Color:
	return Color(String(MBODY.get(body, {}).get("color", "#9C93AC")))

## 그 몸이 무엇에 약한가 / 무엇을 튕겨 내는가 / 무엇이 아예 안 통하는가.
##
## ★ **배열을 돌려준다.** 옛 표는 몸마다 약점이 하나뿐이라 String 이었는데, 새 표는
##   나무가 불·얼음 둘에 약하고 바위가 물·얼음 둘에 약하다. String 으로 두고 첫 번째만
##   보여 주면 화면이 **거짓말을 한다** — 얼음 영웅을 세운 사람이 「나무는 불에 약함」만
##   보고 물린다.
static func body_weak(body: String) -> Array:
	return MBODY.get(body, {}).get("weak", []) as Array

static func body_resist(body: String) -> Array:
	return MBODY.get(body, {}).get("resist", []) as Array

static func body_immune(body: String) -> Array:
	return MBODY.get(body, {}).get("immune", []) as Array

# --------------------------------------------------------------------------- #
# 상태이상 — 속성이 붙이는 것 셋
# --------------------------------------------------------------------------- #
## 얼음 = 둔화 · 불 = 화상 · 전기 = 마비. 사용자가 정한 규칙이다.
##
## ★ **셋 다 「센 쪽으로 덮어쓴다」** (CLAUDE.md 15번). 곱하면 둔화 둘만 겹쳐도 몬스터가
##   멈추고, 화상은 보스에게 한 번 박힌 강한 불이 라운드 내내 타게 된다.
## ★ 마비만 **확률**이다. 사용자의 말: 「전기공격은 특정확률로 마비시킬 수 있음」.
##   확률로 둔 까닭이 있다 — 마비는 완전 정지라 늘 걸리면 연사 영웅 하나가 길을 통째로
##   막아 버린다. 확률이면 **떼거리를 흩뜨리는** 효과가 되어 게임이 안 멈춘다.
## ★ 마비 중에는 **둔화가 뜻이 없다**(이미 0이다). 그래서 굳이 곱하지 않는다 —
##   BattleSim._move_monsters 가 마비를 먼저 보고 걸음을 0 으로 만든다.
const STATUS := {
	# 얼음 — 걸음이 이만큼 느려진다. 2초.
	"slow": {"ko": "둔화", "amount": 0.30, "sec": 2.0},
	# 불 — 한 대 피해의 이만큼을 초당, 3초간. (★ 붙이는 순간에 상성을 미리 곱한다)
	"burn": {"ko": "화상", "amount": 0.32, "sec": 3.0},
	# 전기 — 이 확률로 이만큼 **완전히 멎는다.**
	#   ★ 보스는 확률이 BOSS_STUN_MUL 배로 깎인다. 안 그러면 보스가 길에서 계속 서 있다가
	#     "보스탄이 제일 쉬운 탄"이 된다 — 광역의 몫을 못 받는 보스를 세워 두면 그냥 표적이다.
	"stun": {"ko": "마비", "chance": 0.16, "sec": 0.9},
}
## 보스에게 마비가 걸릴 확률의 배수. 0 으로 두면 「보스는 마비 면역」이 된다.
const BOSS_STUN_MUL := 0.35
## 마비가 풀린 뒤 이만큼은 다시 안 걸린다(초). 없으면 연사 영웅이 사실상 영구 정지를 건다.
const STUN_IMMUNE_SEC := 1.4

static func status_ko(s: String) -> String:
	return String(STATUS.get(s, {}).get("ko", ""))

# --------------------------------------------------------------------------- #
# 몬스터
# --------------------------------------------------------------------------- #
## hp 배수 · 속도 배수 · 골드 배수 · crush(크리스탈에 닿았을 때 깨뜨리는 개수).
## ★ 보스는 다섯 개를 부순다. 이유가 있다 — 광역·장판은 몬스터가 많을수록 세지는데
##   보스는 혼자라서 그 몫을 못 받는다. 보스가 한 개만 부수면 "떼거리는 다 잡고
##   보스는 그냥 통과시키는" 것이 최선의 수가 되어 버린다(실제로 40탄이 그랬다).
## ★ 그림 크기(h)는 여기 두지 않는다 — core/roster.gd 가 tools/gen_art.py 가 실제로
##   저장한 픽셀 높이를 들고 있고, 두 곳에 적으면 반드시 어긋난다.
const MKIND := {
	"swarm":  {"hp": 0.75, "spd": 1.00, "gold": 1.0, "crush": 1, "ko": "떼거리"},
	"fast":   {"hp": 0.60, "spd": 1.70, "gold": 1.1, "crush": 1, "ko": "쾌속"},
	"tank":   {"hp": 2.40, "spd": 0.80, "gold": 1.4, "crush": 1, "ko": "육중"},
	"caster": {"hp": 1.00, "spd": 0.88, "gold": 1.2, "crush": 1, "ko": "주술"},
	# ★ 보스는 체력을 14 → 18 로 올리고 부수는 크리스탈을 5 → 3 으로 내렸다.
	#   까닭이 있다 — 크리스탈을 **상점에서 되살 수 있게** 되면서 5개는 너무 커졌다.
	#   50탄에서 다섯 개면 되사는 데 2800골드인데 그 탄의 지갑이 600골드다. 그러면
	#   보스 한 번에 판이 끝나는 「사고」가 되고, 사고는 난이도가 아니다.
	#   셋이면 아프되 되살 수 있다 — 그 되사기가 곧 그 판의 긴장이다.
	"boss":   {"hp": 18.0, "spd": 0.72, "gold": 12.0, "crush": 3, "ko": "보스"},
}
## 주술사가 거는 저주 — 영웅 전체의 공격속도를 이만큼 깎는다. 겹치지 않고 시간만 새로 찬다.
const CURSE_RATE := 0.18
const CURSE_SEC := 2.5
## 주술사가 저주를 던지는 간격(초).
const CURSE_EVERY := 6.0

## 앞 탄을 두껍게 하는 덤. 1탄이 (1 + EARLY_TOUGH)배이고, 한 탄 지날 때마다
## EARLY_FADE 를 곱해 얇아진다 — 8탄쯤이면 사실상 사라진다.
## ★ 값을 2.3 에서 0.55 로 크게 낮췄다. 밑값(HP_BASE)이 4.3 에서 9.0 으로 올라가서
##   덤이 없어도 1탄 몬스터가 한 방에 안 죽기 때문이다. 그대로 뒀으면 1탄이 세 배가 된다.
##
## ★ 왜 넣었나: 예전에는 1탄 떼거리가 3.2 라 **어떤 영웅이든 한 방**이었다. 한 방에
##   죽는 몬스터는 체력 막대도 못 보여 주고, 그 탄이 8초 만에 끝나서(길을 걷는 데 29초다)
##   화면에 아무것도 안 남았다 — 게임을 켠 사람이 처음 보는 장면이 그것이다.
##   덤을 곱하면 1탄 떼거리가 열 남짓이 되어 보통 영웅이 **세 방쯤** 때려야 죽는다.
## ★ 왜 곱셈 덤인가: 뒤 탄의 곡선을 건드리지 않아야 클리어율(25~30%)이 그대로 남는다.
##   지수를 바꾸면 40탄까지 전부 흔들린다 — 1.465 는 24판 중 11판, 1.482 는 5판이었다.
## 첫 테마에서는 적이 더 오래 살아남도록 체력을 높인다.
## 추가 체력은 탄마다 0.84배로 줄어 후반 곡선에 미치는 영향이 작다.
const EARLY_TOUGH := 0.95
const EARLY_FADE := 0.84

## 중반을 두껍게 하는 덤 — **사용자가 본 「50탄까지 하나도 입구를 못 벗어난다」의 본체다.**
##
## ★ 무엇이 문제였나: 곡선이 지수 하나(HP_GROW)뿐이라 앞·중반이 통째로 얇았다.
##   그러면 몬스터가 나오자마자 죽어서 4350px 짜리 길이 장식이 되고, 그러다 어느 탄에서
##   지수가 사람의 힘을 앞지르는 순간 **한 탄에 크리스탈 스무 개가 통째로** 날아간다.
##   쉬운 게임이 아니라 **아무 일도 안 일어나다가 갑자기 끝나는** 게임이었던 셈이다.
## ★ 이 덤은 1탄에 1.0 이고 스무 탄쯤에서 3.4 로 차오른 뒤 3.6 에 눕는다. 앞 탄은
##   그대로 두면서 중반을 세 배쯤 두껍게 하는 모양이다 — 몬스터가 **걸어 들어와야**
##   죽으므로 길과 벽과 문이 그제서야 뜻을 갖는다.
## ★ 대신 지수(HP_GROW)를 1.181 → 1.1135 로 낮췄다. 안 낮추면 벽이 55탄으로 **앞당겨져서**
##   뒤 테마를 아무도 못 본다. 「중반은 두껍게, 끝은 늦게」가 이 두 줄의 뜻이다.
const RAMP := 3.2
const RAMP_FADE := 0.88

## w 탄에 곱해지는 중반 덤.
static func mid_ramp(w: int) -> float:
	return 1.0 + RAMP * (1.0 - pow(RAMP_FADE, float(maxi(1, w) - 1)))

## 체력 곡선. **한 탄 지날 때마다 HP_GROW 배씩** 두꺼워진다.
##
## ★ 40탄에서 100탄으로 늘리면서 다시 잡은 값이다. 옛값(1.469)을 그대로 100탄까지
##   끌면 100탄 체력이 10의 20제곱을 넘어 float 이 먼저 무너진다. 왜 이렇게 낮춰도
##   되는가 하면 — **플레이어의 힘도 100탄에 걸쳐 자라기 때문**이다:
##     · 겹치기 — 100탄이면 영웅을 백 번 뽑는다. 여섯 자리에 나눠 쌓이니 한 자리가
##       열여섯 겹까지 간다(40탄이면 예닐곱 겹이었다). 여기서만 2.4배가 더 난다.
##     · 골드 — 처치 골드가 탄에 비례하므로 누적은 탄의 제곱으로 는다. 40탄 대비
##       6.25배이고, 상점 값이 1.34배씩 오르므로 실제 화력은 약 2.5배가 더 붙는다.
##   둘을 곱하면 100탄의 플레이어는 40탄의 플레이어보다 약 6배 세다. 그래서 곡선을
##   낮추지 않으면 30탄 언저리에서 벽에 부딪혀 뒷 테마를 아무도 못 본다.
## ★ **이 줄을 건드리면 반드시 tests/balance_check 를 다시 돌려라.**
##   기대값: **클리어율 약 25%(24판 중 5~9판) · 도달 중간값 95~99탄 · 1~6탄은 크리스탈
##   손실 0.**
## ★★ **여든 명 · 역할 넷 · 새 방식(도탄·장판)으로 갈아엎으면서 다시 잰 값이다.**
##   같은 1.1135 에서 클리어가 3판 → 4판(--runs 12)으로 늘었다. 순 이득이 셋이다:
##     1. 옛 장판(aura)은 한 마리당 0.085 였는데, 범위가 생긴 새 장판(zone)은 0.62 다
##     2. 겹친 장판이 **보스에게도 n배**로 들어가게 고쳤다(dmg_check --selftest 7번이 잡았다)
##     3. 「일격」 역할이 화력 x1.26 을 얹는다
##   그 몫을 되받아 올렸다가, 앞 탄의 바위 규칙을 고친 뒤 다시 내렸다(아래).
##   실측(지금 규칙, `--runs 24`):
##     **1.1130 → 6판 · 중간값 95 (지금 — 나무 면역 + 전기 화력 1.44 로 다시 잰 값.
##       같은 값이 그 전에는 5판·94 였다)** / 1.1145 → 3~6판 · 94~95 /
##     1.1165 → **1판** · 93.   (`--runs 12`) 1.1135 → 4판 · 98.
##   ☆ 같은 값을 두 번 재면 24판에서 ±3판쯤 흔들린다. **한 번 재고 결론 내지 마라.**
##   ★ **0.002 안에서 6판이 1판이 된다. 넷째 자리까지 적어 두고 만져라.**
##   (옛 규칙에서의 실측: 1.181 → 6판·97 / 1.183 → 5판·96 / 1.185 → 5판·95 /
##    1.180 → 10판·99 / 1.215 → 0판·75 / 1.240 → 0판·60)
##
## ★ 여기서 크게 한 번 헤맸으니 적어 둔다. 처음에 1.170 으로 두었더니 24판이 **전부**
##   클리어였고, 1.240 으로 올려도 여전히 전부 클리어였다(체력이 314배인데!). 곡선이
##   손잡이가 아니었던 것이다 — 범인은 **아이템 값이 고정이었던 것**이다. 골드는 탄에
##   비례해 느는데 「벼락 폭탄」 값은 90 그대로라, 후반에는 한 탄 벌이로 폭탄을 열 개 사서
##   판을 통째로 살 수 있었다. 폭탄 피해가 wave_hp 에 비례하므로(bomb_damage) 체력을
##   아무리 세워도 언제나 그 탄을 쓸어버린다. 아이템 값을 탄에 따라 오르게 하자
##   (Balance.item_cost) 같은 1.240 에서 클리어가 **0판**이 됐다. **체력 곡선을 만지기
##   전에 「골드로 살 수 있는 것」부터 봐라.**
const HP_BASE := 9.0
## 2026-09-16: 탄별 증가율을 기존 11.5%에서 20% 높여 13.8%로 조정했다.
## 위 자동 플레이 수치는 이전 곡선의 기록이다. 첫 탄의 기준 체력은 유지한다.
const HP_GROW := 1.1380
## 모든 탄·테마·종류에 동일하게 적용하는 체력 증가분.
const DIFFICULTY_HP := 1.80

## w 탄의 몬스터 한 마리 기준 체력. rank 는 그 탄이 걸린 **테마의 험한 정도**(1~5)다.
##
## ★ 왜 테마가 체력에 끼어드는가: 사용자가 「뒤로 갈수록 몬스터가 더 세지게」라고 했는데,
##   테마는 무작위로 걸리고 반복도 된다. 곡선만으로는 "같은 호수인데 90탄이 10탄보다
##   센" 것을 설명할 길이 없다. 테마마다 험한 정도를 두고 **뒤 블록일수록 험한 테마가
##   잘 걸리게** 하면(Run.roll_themes), 곡선과 테마가 같은 방향으로 겹쳐 오른다.
static func wave_hp(w: int, rank: int = 1) -> float:
	return HP_BASE * pow(HP_GROW, float(w - 1)) * mid_ramp(w) * early_tough(w) * theme_hp(rank) * DIFFICULTY_HP


## 테마의 험한 정도가 체력에 곱하는 값. rank 1 은 순한 곳, 5 는 험한 곳이다.
## ★ 크게 잡지 마라 — 테마는 무작위로 걸린다. 세게 잡으면 "험한 테마가 연달아 걸려서
##   졌다"가 되어 실력이 아니라 운이 판을 정한다.
const THEME_RANK_HP := [1.00, 1.00, 1.05, 1.10, 1.16, 1.22]

static func theme_hp(rank: int) -> float:
	return THEME_RANK_HP[clampi(rank, 0, THEME_RANK_HP.size() - 1)]


## 초반 압박: 1탄 1.95배 → 3탄 1.67배 → 6탄 1.40배 → 10탄 1.20배.
## 기존 대비 1~6탄 체력 약 29~36% 증가. 30탄부터 추가분은 1% 미만이다.
static func early_tough(w: int) -> float:
	return 1.0 + EARLY_TOUGH * pow(EARLY_FADE, float(w - 1))

## 30탄 수준에서 출현 수를 고정한다. 3배속에서도 후반에 몬스터가 더 쌓이지 않는다.
## 일반 탄은 41마리, 보스 탄은 일반 19마리 + 보스 1마리다.
## 이후 난이도는 wave_hp의 탄별 성장(13.8%)과 테마 체력 보정으로 높인다.
const MONSTER_COUNT_CAP_WAVE := 30
const MAX_ON_FIELD := 41
const MAX_BOSS_ESCORT := 19

## w 탄의 몬스터 수(보스 제외).
##
## ★ **첫 두 탄만 따로 얇게 잡는다.** 1탄에는 영웅이 **하나**뿐인데, 하필 그 하나가
##   일격형(공격속도 0.5)이고 상대가 저항까지 걸면 초당 피해가 2 남짓이다. 그때 여섯
##   마리면 25초 안에 못 잡아서 크리스탈이 깨진다 — 게임을 켠 사람이 처음 보는 장면에서
##   벌을 주는 셈이다. 실측으로 24판 중 1판이 1탄에 하나를 잃었다(평균 -0.04).
static func wave_count(w: int) -> int:
	if is_boss_wave(w):
		return mini(MAX_BOSS_ESCORT, 4 + int(floor(float(w) * 0.5)))
	if w <= 2:
		return 3 + w
	return mini(MAX_ON_FIELD, 5 + int(floor(float(w) * 1.2)))

static func is_boss_wave(w: int) -> bool:
	return w % BOSS_EVERY == 0

## w 탄이 몇 번째 테마 블록인가 (0부터).
static func theme_block(w: int) -> int:
	return int(floor(float(maxi(1, w) - 1) / float(THEME_BLOCK)))

## 몬스터 한 마리를 잡았을 때 나오는 골드(배수 적용 전).
##
## ★ 상성이 들어오면서 6% 를 덜어냈다(옛값 3.0 + 0.25w). 약점 2배는 실력을 크게 올리는데
##   — 상점의 「영웅」 탭이 다음 탄의 몬스터를 정확히 보여 주니 플레이어가 골라 세운다 —
##   그만큼 클리어율이 24판 중 14판까지 올라갔다. 골드로 6% 를 덜어내니 7판(29%)으로
##   제자리다. **밸런스를 다시 잡을 일이 생기면 상성 배수가 아니라 여기를 만져라** —
##   상성은 0.40 이든 0.70 이든 클리어율이 거의 안 움직이는 무딘 손잡이다(13~14판).
## ★ 100탄으로 늘리면서 기울기를 낮췄다(옛값 2.82 + 0.235w). 옛 기울기를 100탄까지
##   끌면 100탄 한 마리가 26골드이고 한 탄에 일흔 마리라 **한 탄에 1800골드**가 나온다 —
##   상점이 통째로 무의미해진다(살 것이 남지 않는다). 보정 전 100탄 떼거리 보상은 13골드다.
##   30탄 이후에는 줄인 개체 수에 맞춰 아래에서 마리당 보상을 추가 보정한다.
static func kill_gold(w: int, kind: String) -> int:
	var base := 2.82 + float(w) * 0.105
	var reward := int(round(base * float(MKIND[kind]["gold"])))
	if w <= MONSTER_COUNT_CAP_WAVE or kind == "boss":
		return reward
	# 줄어든 일반 몬스터 수만큼 개체당 보상을 올려 후반 상점 수입을 유지한다.
	# 72/40은 이전 일반/보스 탄의 보상 예산이며 실제 출현 수에 사용하지 않는다.
	var reward_count := mini(40, 4 + int(floor(float(w) * 0.5))) if is_boss_wave(w) \
			else mini(72, 5 + int(floor(float(w) * 1.2)))
	return int(round(float(reward) * float(reward_count) / float(wave_count(w))))

## 라운드를 마쳤을 때의 보너스. **크리스탈을 하나도 안 깨뜨렸는가**에 크게 준다 —
## 시간에 비례해 주면 약한 판을 질질 끄는 쪽이 이득이 되는 순간이 생긴다.
static func clear_bonus(w: int, wiped: bool) -> int:
	var g := 10 + w * 2
	if wiped:
		g += 34 + w
	return g

# --------------------------------------------------------------------------- #
# 몬스터가 걷는 길 — 순수한 좌표 계산
# --------------------------------------------------------------------------- #
static var _segs: Array = []
static var _seg_len: float = 0.0

## 두 길은 전장을 중심으로 **점대칭**이다. 홀수 길(route 1)의 자리는 짝수 길을 뒤집은 것이다.
static func _mirror(p: Vector2, route: int) -> Vector2:
	return p if route % 2 == 0 else ARENA_CENTER * 2.0 - p

static func route_points(route: int = 0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in ROUTE_POINTS:
		points.append(_mirror(p, route))
	return points

static func _ensure_path() -> void:
	if not _segs.is_empty():
		return
	for i in range(ROUTE_POINTS.size() - 1):
		var a: Vector2 = ROUTE_POINTS[i]
		var b: Vector2 = ROUTE_POINTS[i + 1]
		var length := a.distance_to(b)
		_segs.append({"a": a, "b": b, "from": _seg_len, "len": length})
		_seg_len += length

static func path_len() -> float:
	_ensure_path()
	return _seg_len

## Progress is measured in pixels for both routes; jitter narrows at each corner.
static func path_at(s: float, off: float = 0.0, route: int = 0) -> Vector2:
	_ensure_path()
	s = clampf(s, 0.0, _seg_len)
	for seg in _segs:
		var start: float = seg["from"]
		var length: float = seg["len"]
		if s > start + length:
			continue
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var along := clampf(s - start, 0.0, length)
		var normal := (b - a).normalized().orthogonal()
		var jitter := off * clampf(minf(along, length - along) / GATE_NARROW, 0.0, 1.0)
		return _mirror(a.lerp(b, along / length) + normal * jitter, route)
	return _mirror(ROUTE_POINTS[-1], route)

static func post_position(post: int) -> Vector2:
	return POST_POINTS[clampi(post, 0, POST_SLOTS - 1)]

# --------------------------------------------------------------------------- #
# 카드 리롤 — "한 번 리롤한 카드는 추가 골드를 내야 더 리롤할 수 있다"
# --------------------------------------------------------------------------- #
## 카드 한 장당 무료 교체 횟수(기본). 상점에서 늘릴 수 있다.
const FREE_REROLL := 1
## 공짜를 다 쓴 뒤 n 번째 유료 리롤의 값 (n 은 1부터).
static func reroll_cost(paid_times: int) -> int:
	return int(15 * pow(2.0, float(paid_times)))

# --------------------------------------------------------------------------- #
# 상점 1 — 값이 오르는 능력치. lv 은 지금까지 산 횟수.
# --------------------------------------------------------------------------- #
## ★ 「크리스탈 +1」을 없앴다. 최대치가 20 으로 못 박혔기 때문이다(START_LIVES 주석).
##   깨진 크리스탈은 아래 repair_cost 로 **하나씩 되사서** 20 까지만 채운다.
## ★ 「사거리」 줄은 **통째로 없앴다.** 사거리라는 개념 자체가 없어졌으므로(PROFILE 위의
##   ★★ 블록) 살 것도 없다. 여덟 줄이 일곱 줄이 됐다.
## ★ **desc 에서 숫자를 걷어냈다.** 예전에는 「모든 영웅 공격력 +15%」처럼 한 단계 몫을
##   적어 두었는데, 그건 화면이 공식을 두 번째로 적어 두는 것이라 언젠가 반드시 어긋난다
##   (없앤 사거리 줄이 실제로 그렇게 어긋나 있었다 — 표에는 6단계라 적어 두고 함수는
##   12단계짜리 배수를 그대로 돌려주고 있었다). 지금 desc 는 「무엇이
##   오르는가」만 말하고, **얼마나 올랐는가는 upgrade_show() 가 실제 함수에서 뽑아 적는다.**
## show 는 값의 종류다 — mult 곱셈배수 · pct 확률 계수 · x 배수 · count 횟수 ·
## slow 이동속도 계수. 상점에서는 횟수를 제외한 모든 값을 x 표기로 통일한다.
const UPGRADES := [
	{"id": "atk",    "ko": "공격력",     "desc": "모든 영웅의 공격력",        "show": "mult",  "base": 40,  "grow": 1.34, "cap": 0},
	{"id": "rate",   "ko": "공격속도",   "desc": "모든 영웅의 공격속도",      "show": "mult",  "base": 45,  "grow": 1.37, "cap": 23},
	{"id": "crit",   "ko": "치명타 확률", "desc": "치명타 발생 확률",        "show": "pct",   "base": 60,  "grow": 1.40, "cap": 15},
	{"id": "critx",  "ko": "치명타 배율", "desc": "치명타 피해 배율",       "show": "x",     "base": 70,  "grow": 1.42, "cap": 20},
	{"id": "gold",   "ko": "골드 획득량",   "desc": "몬스터 처치 골드",   "show": "mult",  "base": 55,  "grow": 1.45, "cap": 0},
	{"id": "reroll", "ko": "카드 무료 교체 횟수",   "desc": "카드마다 무료 교체",        "show": "count", "base": 100, "grow": 1.65, "cap": 4},
	# ★ 제한 시간이 없어졌으므로(크리스탈이 곧 목숨이다) 그 자리에 「길」을 산다.
	#   몬스터가 느려지면 그만큼 오래 얻어맞는다 — 예전 「제한 시간 +2초」와 같은 자리다.
	{"id": "mire",   "ko": "몬스터 이동속도",    "desc": "몬스터의 이동속도",         "show": "slow",  "base": 95,  "grow": 1.55, "cap": 5},
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

## 능력치 한 줄을 id 로 찾는다. 없으면 빈 사전 (passive_by_id 와 같은 결이다).
static func upgrade_by_id(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return {}


## 현재·다음·최종 능력치를 같은 x 표기로 표시한다. 백분율을 함께 붙이지 않는다.
## 확률은 실제 확률 계수(x0.05), 진창은 실제 이동속도 계수(x0.95)를 보존한다.
## ★ 값 v 는 반드시 **Run.up_at() / Run.stat_now()** 가 준 것을 넣어라. 여기서 다시
##   계산하면 상점만 아는 두 번째 공식이 생긴다(CLAUDE.md 18).
## ★ 「x」는 **ASCII 소문자 x** 다. U+00D7 은 번들 폰트에 없다(CLAUDE.md 6 · 14-6).
static func upgrade_show(id: String, v: float) -> String:
	if String(upgrade_by_id(id).get("show", "mult")) == "count":
		return "%d번" % int(round(v))
	return "x%.2f" % v

# --------------------------------------------------------------------------- #
# 상점 2 — 깨진 크리스탈 되사기
# --------------------------------------------------------------------------- #
## 사용자가 정한 규칙: 「크리스탈은 무조건 max 20개에, 깨졌으면 상점에서 골드로 산다」.
##
## ★ 값이 탄에 따라 올라야 한다. 고정이면 후반 한 탄 벌이로 스무 개를 통째로 되사서
##   **크리스탈이 목숨이 아니게 된다** — 예전 「크리스탈 수리」 아이템이 정확히 그랬다
##   (자동 플레이 12판이 12판 다 클리어했고 크리스탈은 20에서 31로 늘어 있었다).
## ★ 그리고 **한 판에 살수록 비싸진다.** 그래야 "몇 개까지 되살릴 것인가"가 선택으로 남는다.
const REPAIR_BASE := 62.0
const REPAIR_WAVE := 0.145
const REPAIR_GROW := 1.075

static func repair_cost(w: int, bought: int) -> int:
	return int(round(REPAIR_BASE * (0.86 + REPAIR_WAVE * float(maxi(1, w)))
			* pow(REPAIR_GROW, float(maxi(0, bought)))))

# --------------------------------------------------------------------------- #
# 상점 3 — 패시브. **골드로 사는 「빌드」는 이제 이것 하나뿐이다.**
# --------------------------------------------------------------------------- #
## ★ 무기와 아이템을 통째로 없앴다(사용자가 정한 것). 까닭이 있다 —
##   **무기**는 「전군에 걸리는 곱셈」이라 고를 것이 사실상 없었다(제일 센 셋을 사면 끝이고,
##   그 셋은 판마다 늘 같았다). **아이템**은 값만 내면 그 탄을 통째로 사 버리는 안전망이라
##   밸런스의 손잡이를 먹었다 — CLAUDE.md 15-3 에 적힌 그 사고가 이것이다.
## ★ 대신 패시브를 스물여섯으로 늘리고 **셋만** 들게 했다(PASSIVE_SLOTS).
##   셋뿐이면 「무엇을 버리는가」가 곧 빌드다. 넷째를 사려면 하나를 빼야 한다.
##
## 표의 뜻:
##   rank  언제부터 상점에 나오는가 (1 처음부터 · 2 중반 · 3 후반)
##   icon  카드에 그리는 문양 이름 — Look.draw_passive_icon() 이 도형으로 그린다
##   tint  카드 테두리 색
##   그 밖의 키(atk·rate·gold·crit·critx·radius·split·slow…)는 **곱셈/덧셈 효과**다.
##   Run.pas_mult / pas_add / pas_best 만 이 값을 읽는다 — 상점 설명과 전투가 같은
##   함수를 봐야 "상점에는 +20% 라고 적혀 있는데 실제로는 안 오르는" 일이 안 생긴다.
const PASSIVE_SLOTS := 3
const PASSIVES := [
	# --- rank 1 : 처음부터 나온다 ---
	{"id": "repeater", "ko": "연발 장치", "desc": "모든 영웅 공격속도 x1.20", "cost": 255, "rank": 1, "icon": "gear", "tint": "#F6C445", "rate": 1.20},
	# ★ 여기 있던 「긴 활대」(사거리 +22%)를 갈아 끼운 자리다. 사거리가 없어져 살 것이
	#   없어졌는데, **rank 1 은 여덟 줄이어야 한다** — 상점은 rank 1 에서 셋을 진열하므로
	#   줄이 줄면 초반 진열이 얇아져 매번 같은 카드가 뜬다. 값·rank·색은 그대로 두고
	#   효과만 바꿨다.
	{"id": "keenedge", "ko": "예리한 촉", "desc": "치명타 배율 x0.50 추가", "cost": 263, "rank": 1, "icon": "blade", "tint": "#5AD07A", "critx": 0.5},
	{"id": "heavytip", "ko": "무거운 촉", "desc": "공격력 x1.30, 공격속도 x0.90", "cost": 278, "rank": 1, "icon": "spike", "tint": "#E2415A", "atk": 1.30, "rate": 0.90},
	{"id": "scope", "ko": "조준경", "desc": "치명타 확률 x0.10 추가", "cost": 270, "rank": 1, "icon": "eye", "tint": "#4AA3FF", "crit": 0.10},
	{"id": "midas", "ko": "황금손", "desc": "처치 골드 x1.28", "cost": 263, "rank": 1, "icon": "coin", "tint": "#F6C445", "gold": 1.28},
	{"id": "first", "ko": "첫 격돌", "desc": "라운드 첫 5초 공격력 x2.00", "cost": 285, "rank": 1, "icon": "flag", "tint": "#FF6A2A"},
	{"id": "deal", "ko": "큰손", "desc": "카드마다 무료 교체 +2", "cost": 255, "rank": 1, "icon": "card", "tint": "#A56CF0"},
	{"id": "frost", "ko": "서리 부적", "desc": "명중 시 2초간 적 이동속도 x0.78", "cost": 293, "rank": 1, "icon": "snow", "tint": "#7BDCFF", "slow": 0.22, "slow_sec": 2.0},
	# --- rank 2 : 중반부터 ---
	{"id": "flame", "ko": "화염 부적", "desc": "모든 공격에 3초간 화상", "cost": 480, "rank": 2, "icon": "flame", "tint": "#FF6A2A"},
	{"id": "pierce", "ko": "관통 촉", "desc": "모든 투사체 관통 +1", "cost": 450, "rank": 2, "icon": "arrow", "tint": "#5AD07A"},
	{"id": "split", "ko": "분열 탄두", "desc": "모든 투사체 명중 시 소형 폭발", "cost": 510, "rank": 2, "icon": "burst", "tint": "#FF9A3C", "split": 44.0},
	{"id": "mortar", "ko": "공성 조준", "desc": "광역 반경 x1.50, 공격력 x1.10", "cost": 495, "rank": 2, "icon": "ring", "tint": "#FF9A3C", "atk": 1.10, "radius": 1.50},
	{"id": "rage", "ko": "광폭화", "desc": "전투 시작 25초 후 공격속도 x1.55", "cost": 465, "rank": 2, "icon": "rage", "tint": "#E2415A"},
	{"id": "headsman", "ko": "처형인의 눈", "desc": "치명타 배율 x1.00 추가", "cost": 503, "rank": 2, "icon": "blade", "tint": "#F6C445", "critx": 1.0},
	{"id": "overkill", "ko": "마무리 일격", "desc": "체력 25% 미만인 적에게 피해 x1.90", "cost": 495, "rank": 2, "icon": "skull", "tint": "#A56CF0"},
	{"id": "giantslay", "ko": "거인 사냥", "desc": "보스에게 피해 x1.70", "cost": 518, "rank": 2, "icon": "crown", "tint": "#FF7AC0"},
	{"id": "surge", "ko": "과열", "desc": "처치 공속 x1.05~x1.45 · 0.05씩 누적 · 3초", "cost": 488, "rank": 2, "icon": "spark", "tint": "#FFD84D"},
	{"id": "bulwark", "ko": "수정 방벽", "desc": "30% 확률로 크리스탈 피해 방어", "cost": 525, "rank": 2, "icon": "shield", "tint": "#5FE6FF"},
	# --- rank 3 : 후반부터 ---
	{"id": "bolt", "ko": "연쇄 낙뢰", "desc": "명중 시 14% 확률로 연쇄 번개", "cost": 840, "rank": 3, "icon": "bolt", "tint": "#FFD84D"},
	{"id": "chainmaster", "ko": "뇌격 증폭", "desc": "연쇄 횟수 +2", "cost": 870, "rank": 3, "icon": "chain", "tint": "#FFD84D"},
	{"id": "wildfire", "ko": "들불", "desc": "화상 상태의 적 처치 시 주변에 화상 전파", "cost": 900, "rank": 3, "icon": "wildfire", "tint": "#FF6A2A"},
	{"id": "resonance", "ko": "속성 공명", "desc": "동일 속성 2명 이상: 해당 속성 피해 x1.25", "cost": 930, "rank": 3, "icon": "rune", "tint": "#A56CF0"},
	{"id": "antibody", "ko": "상극 파훼", "desc": "저항 대상 피해 x0.50 > x0.80", "cost": 960, "rank": 3, "icon": "yin", "tint": "#5AD07A"},
	{"id": "echo", "ko": "잔향", "desc": "중복 영웅 획득 시 합성 재료 1장 추가", "cost": 1050, "rank": 3, "icon": "echo", "tint": "#5FE6FF"},
	{"id": "eye", "ko": "도박꾼의 눈", "desc": "18% 확률로 족보 +1단계", "cost": 1020, "rank": 3, "icon": "dice", "tint": "#FF7AC0"},
	{"id": "joker", "ko": "조커", "desc": "카드 1장 자동 교체 · 최적 족보", "cost": 1650, "rank": 3, "icon": "joker", "tint": "#FFF0B8"},
]

static func passive_by_id(id: String) -> Dictionary:
	for p in PASSIVES:
		if p["id"] == id:
			return p
	return {}

## 패시브는 판매하지 않는다. 오래된 호출도 환급을 만들지 않는다.
static func passive_refund(_id: String) -> int:
	return 0

## w 탄의 상점에 나올 수 있는 rank 상한. 1탄에 조커가 나오면 살 수도 없는 카드가
## 자리만 먹는다 — 셋만 내놓는 상점에서 그건 통째로 헛돈 진열이다.
static func passive_rank_cap(w: int) -> int:
	if w >= int(LAST_WAVE * 0.34):
		return 3
	if w >= int(LAST_WAVE * 0.12):
		return 2
	return 1

const PASSIVE_FLAME_BURN := 0.30
const PASSIVE_FLAME_SEC := 3.0
const PASSIVE_BOLT_P := 0.14
const PASSIVE_RAGE := 0.55
## ★ 제한 시간이 없어져서 「남은 10초」라는 기준이 사라졌다. 대신 **탄이 오래 끌면**
##   켜지는 것으로 바꿨다 — 뜻은 그대로다(막판에 힘을 낸다).
const PASSIVE_RAGE_AFTER := 25.0
const PASSIVE_FIRST := 2.0
const PASSIVE_FIRST_SEC := 5.0
const PASSIVE_EYE_P := 0.18
## 「마무리 일격」 — 체력이 이 밑이면 이만큼 세게 맞는다.
const PASSIVE_OVERKILL_AT := 0.25
const PASSIVE_OVERKILL := 1.9
## 「거인 사냥」 — 보스에게만.
const PASSIVE_GIANT := 1.70
## 「과열」 — 한 마리 잡을 때마다 오르는 공격속도와 그 상한, 그리고 식는 시간.
const PASSIVE_SURGE_STEP := 0.05
const PASSIVE_SURGE_MAX := 0.45
const PASSIVE_SURGE_SEC := 3.0
## 「수정 방벽」 — 이 확률로 크리스탈이 안 깨진다.
const PASSIVE_BULWARK_P := 0.30
## 「속성 공명」 — 전장에 같은 속성이 둘 이상이면.
const PASSIVE_RESONANCE := 1.25
## 「상극 파훼」 — 저항이 0.5 대신 이 값이 된다.
const PASSIVE_ANTIBODY := 0.80
## 「잔향」 — 겹칠 때 한 번에 오르는 겹 수.
const PASSIVE_ECHO := 2
## 「뇌격 증폭」 — 연쇄가 이만큼 더 튄다.
const PASSIVE_CHAIN_JUMPS := 2
## 「들불」 — 타는 적이 죽을 때 둘레로 옮아 붙는 반경과, 남은 화상의 몇 배로 옮는가.
const PASSIVE_WILDFIRE_R := 96.0
const PASSIVE_WILDFIRE := 0.7
## 「큰손」 — 무료 교체이 이만큼 는다.
const PASSIVE_DEAL := 2

const CRIT_BASE_MULT := 2.0

## 업그레이드 단계를 실제 배수로. 전투와 검사기가 **같은 함수**를 써야
## "검사기에서는 되는데 게임에서는 안 되는" 종류의 어긋남이 안 생긴다.
static func atk_mult(lv: int) -> float:
	return pow(1.15, float(lv))

## 상점 강화 상한. 패시브와 영웅 고유 효과는 이 값 뒤에 별도로 적용한다.
static func rate_mult(lv: int) -> float:
	return minf(3.0, pow(1.05, float(clampi(lv, 0, 23))))

static func crit_chance(lv: int) -> float:
	return minf(0.60, 0.04 * float(maxi(0, lv)))

static func crit_mult(lv: int) -> float:
	return minf(6.0, CRIT_BASE_MULT + 0.20 * float(maxi(0, lv)))

static func gold_mult(lv: int) -> float:
	return pow(1.12, float(lv))

## 길 진창 — 몬스터가 이만큼 느려진다.
static func mire_mult(lv: int) -> float:
	return pow(0.95, float(lv))


# --------------------------------------------------------------------------- #
# 크리스탈이 놓이는 자리 — 제단을 둘러싼 고리
# --------------------------------------------------------------------------- #
## i 번째 크리스탈의 자리(투기장 중심 기준 상대 좌표).
##
## 안쪽 겹부터 차례로 채운다 — 0번은 한가운데, 1~6번은 안쪽 겹, 7~19번은 바깥 겹이다.
## ★ **깨지는 차례가 곧 이 차례의 반대**다(화면은 i < lives 를 살아 있는 것으로 그린다).
##   그래서 바깥부터 사라지고 마지막 한 개가 한가운데에 남는다 — 「마지막 하나」가
##   제단 한복판에서 혼자 빛나는 것이 목숨 하나 남았다는 가장 또렷한 그림이다.
## ★ 겹마다 **반 칸씩 돌려** 놓는다. 안팎이 같은 각도로 서면 무더기에 세로 골이 생겨서
##   「모아 쌓은 것」이 아니라 「고리 두 개」로 보인다.
static func crystal_slot(i: int) -> Vector2:
	var k: int = clampi(i, 0, MAX_LIVES - 1)
	var ring := 0
	while ring < CRYSTAL_RING_N.size() - 1 and k >= int(CRYSTAL_RING_N[ring]):
		k -= int(CRYSTAL_RING_N[ring])
		ring += 1
	var n: int = maxi(1, int(CRYSTAL_RING_N[ring]))
	var a: float = TAU * (float(k) + 0.5 * float(ring)) / float(n) - PI * 0.5
	return Vector2(cos(a), sin(a)) * float(CRYSTAL_R[ring])


## 무더기가 실제로 **그려지는** 반지름. 알 하나가 c.y - 1.5r 까지 솟으므로 그 몫까지 친다.
## 제단 크기(ALTAR_R)와 검사기가 이 값을 본다 — 겹 반지름만 보면 알의 키를 빠뜨린다.
static func crystal_pile_r() -> float:
	var m := 0.0
	for r in CRYSTAL_R:
		m = maxf(m, float(r))
	return m + CRYSTAL_DRAW_R * 1.5


# --------------------------------------------------------------------------- #
# 영웅이 서는 자리 — 발판(post_position)이 정한다
# --------------------------------------------------------------------------- #
## 투기장에서 영웅 그림에 곱하는 배수. 발판 열두 자리는 서로 붙어 있어서 1.0 으로 그리면
## 옆 발판의 영웅과 겹친다. 전장에 몇이 서든 같은 값이다 — 자리가 정해져 있기 때문이다.
static func hero_scale(_n: int) -> float:
	return 0.70


## Higher total rarity shifts every upper-tail probability upward.
static func fusion_probabilities(score: int) -> Array[float]:
	var center := float(clampi(score, 5, 50)) / 5.0 - 0.35
	var weights: Array[float] = []
	var total := 0.0
	for tier in range(10):
		var weight := exp(-0.5 * pow((float(tier) - center) / 1.6, 2.0))
		weights.append(weight)
		total += weight
	for i in range(weights.size()):
		weights[i] /= total
	return weights


# --------------------------------------------------------------------------- #
# 총구 — 탄이 나가는 자리와, 팔을 뻗는 데 걸리는 시간
# --------------------------------------------------------------------------- #
## 클립이 없는 캐릭터의 어림수. `Roster` 가 늘 채워 주므로 실제로는 잘 안 쓰인다.
const MUZ_FALLBACK := Vector2(0.34, -0.80)
const WIND_FALLBACK := 0.24
## 뻗는 시간이 쿨다운을 넘지 않게 하는 몫. 넘으면 팔을 다 뻗기 전에 다음 발이 밀려온다.
const WIND_MAX_OF_COOL := 0.72


## 그림이 **어느 쪽을 겨누고 있는가**(+1 오른쪽 · -1 왼쪽).
##
## ★ 서른 장을 다 오른쪽 향으로 뽑았지만 여섯은 왼쪽을 겨누고 나왔다(활을 왼쪽으로 든
##   초승궁수처럼). 그것을 그대로 그리면 목표가 오른쪽인데 왼쪽으로 쏘는 그림이 된다.
##   총구 자리(muz)의 **가로 부호**가 곧 그 답이라 따로 적을 것이 없다.
static func art_aim(u: Dictionary) -> float:
	var m: Array = u.get("muz", [])
	if m.size() < 2:
		return 1.0
	return -1.0 if float(m[0]) < 0.0 else 1.0


## 탄이 나가는 자리 — 영웅이 선 자리(발밑)에서 잰 상대 좌표(px).
##
## `face` 는 그 영웅이 바라보는 쪽(+1 오른쪽 · -1 왼쪽)이다. 그림이 왼쪽을 겨누고
## 뽑혔든 오른쪽이든, 화면은 **겨누는 쪽이 목표를 보도록** 좌우를 뒤집으므로
## 총구도 언제나 `face` 쪽에 선다 — 그래서 가로는 절댓값을 쓴다.
##
## ★ 왜 이 함수가 있어야 하는가: 없으면 탄이 발판(`post_position()`) 자리, 곧 **발바닥**에서
##   나간다. 화면에서는 영웅이 팔을 치켜드는데 불꽃과 탄은 신발 밑에서 튀어나온다.
static func muzzle_off(u: Dictionary, sc: float, face: float) -> Vector2:
	var m: Array = u.get("muz", [])
	var mx: float = MUZ_FALLBACK.x
	var my: float = MUZ_FALLBACK.y
	if m.size() >= 2:
		mx = float(m[0])
		my = float(m[1])
	# 그려지는 높이 = 그림 높이 × 그림 보정 × 화면 배수 (Art.unit_h 와 같은 셈이다).
	var dh: float = float(u.get("h", 100)) * float(u.get("sc", 1.0)) * sc
	return Vector2(absf(mx) * (1.0 if face >= 0.0 else -1.0), my) * dh


## 쏘기로 정하고 나서 **탄이 실제로 떠나기까지** 걸리는 시간(초).
##
## ★ 이것이 0 이면 팔을 뻗기도 전에 탄이 나간다 — 모션과 사건이 따로 논다.
##   값은 그 캐릭터 클립이 **놓는 칸**에 닿는 데 걸리는 시간이고, 클립을 다시 짜면
##   같이 따라온다(Roster 의 wind).
## ★ 다만 쿨다운보다 길면 안 된다. 연사 영웅은 한 발이 0.2초도 안 되는데 뻗는 데
##   0.265초를 쓰면 탄이 밀려서 쌓이기만 한다. 그래서 쿨다운에 맞춰 줄인다 —
##   화면은 그만큼 클립을 빨리 돌려서 놓는 칸을 같은 자리에 맞춘다.
static func windup(u: Dictionary, cool: float) -> float:
	var w: float = float(u.get("wind", WIND_FALLBACK))
	return clampf(w, 0.0, maxf(0.02, cool * WIND_MAX_OF_COOL))
