extends RefCounted
class_name Balance

## 게임의 숫자가 **전부** 여기 있다. 순수 함수만 두고 화면·저장을 모른다.
##
## 왜 한곳에 모았나: 디펜스 게임은 "이 판이 왜 안 깨지는지"를 사람이 손으로 계산할 수
## 있어야 고칠 수 있다. 숫자가 전투 코드 안에 흩어지면 그게 불가능해진다.
## tests/balance_check.gd 가 이 표만 읽어 40탄까지 자동으로 돌려 보고 클리어율을 뽑는다.

# --------------------------------------------------------------------------- #
# 투기장 — 벽으로 나뉜 길과, 그 안쪽의 안뜰
# --------------------------------------------------------------------------- #
## 1280x800 기준. 오른쪽 430px 는 정보판이라 원의 중심을 왼쪽으로 당겨 놨다.
const ARENA_CENTER := Vector2(470, 420)

## 벽 세 겹의 반지름. 바깥부터 [바깥벽, 가운데벽, 안뜰벽].
## ★ 몬스터가 다니는 길과 영웅이 선 안뜰을 **벽으로 갈라 놓는 것**이 이 배치의 전부다.
##   예전에는 몬스터가 그냥 안쪽으로 조여들어서 "어디로 오는지"가 안 보였다.
const WALL_R := [340.0, 258.0, 176.0]
## 길(복도)의 중심선. 벽과 벽 사이 한가운데다. 몬스터는 이 선 위를 걷는다.
const LANE_R := [299.0, 217.0]
## 벽마다 문이 하나씩 뚫려 있다. 바깥문 → 가운뎃문 → 안뜰문 순서로 지난다.
## ★ 문끼리 90도씩 어긋나 있어야 길이 나선으로 보인다. 각도를 바꾸면 LANE_SWEEP 도 같이 봐라.
##   바깥문을 위(-PI/2)에 두면 몬스터가 나타나는 자리가 상단 정보띠에 가려진다. 그래서 왼쪽이다.
const GATE_A := [PI, -PI * 0.5, 0.0]
## 문이 열린 폭(라디안, 반각). 벽을 그릴 때 이만큼 비운다.
const GATE_HALF := 0.22
## 몬스터가 나타나는 자리(바깥벽 바로 바깥).
const SPAWN_R := 372.0
## 한 겹에서 도는 각도. 문이 90도 어긋나 있으니 한 바퀴+90도면 다음 문에 정확히 닿는다.
const LANE_SWEEP := TAU + PI * 0.5
## 길을 걷는 기본 속도(px/초). 종류별 속도 배수가 곱해진다.
## ★ 이 값과 길이(path_len 약 4350px)가 곧 **몬스터를 때릴 수 있는 시간**이다.
##   키우면 그냥 지나가 버리고, 줄이면 하염없이 길에서 죽는다. tests/balance_check 로 재라.
const PATH_SPEED := 150.0
## 길 위에서 좌우로 흩어지는 폭. 한 줄로 겹쳐 서면 뒤엣놈이 안 보인다.
const LANE_JITTER := 22.0
## 토막이 바뀌는 자리(=문) 앞뒤로 이만큼은 흩어짐을 0 으로 좁힌다.
## ★ 복도에서는 좌우가 반지름 방향인데 문에서는 각도 방향이다. 그 둘이 만나는 지점에서
##   "좌우"가 90도 홱 돌기 때문에, 좁히지 않으면 몬스터가 문 앞에서 32px 씩 옆으로
##   순간이동한다(유도탄 조준도 같이 튄다). 좁혀 두면 문을 한 줄로 지나가 보기도 낫다.
const GATE_NARROW := 40.0

## 크리스탈 제단. 길의 끝이 여기다.
const ALTAR_R := 74.0
## 크리스탈이 놓이는 고리. 스물 한 겹, 넘치면 안쪽 고리에 더 놓는다.
const CRYSTAL_R := [62.0, 38.0]
const CRYSTAL_PER_RING := 20

## 영웅이 서는 고리의 안쪽/바깥쪽 한계. 안쪽은 제단을 비우고, 바깥쪽은 안뜰벽에 안 닿는다.
## ★ 안쪽 한계를 92 에서 108 로 밀었다. 92 에 서면 영웅 그림의 발이 크리스탈 고리(62)
##   바로 위에 얹혀서, 넷만 서도 제단을 밟고 선 것처럼 보였다(사진으로 확인).
const HERO_MIN_R := 108.0
const HERO_MAX_R := 150.0
## 영웅 하나가 차지하는 폭. 안뜰에 여섯 명뿐이라 넉넉히 잡는다 —
## 예전에는 마흔 명을 밀어 넣느라 44px 였고, 그래서 안뜰이 그림 무더기였다.
const HERO_SPACING := 104.0
## 안뜰문에서 제단으로 이어지는 진입로. 영웅은 이 각도 안에 서지 않는다 —
## 몬스터가 들어오는 길목을 비워 둬야 "어디로 오는지"가 보인다.
const HERO_GAP := 0.34

# --------------------------------------------------------------------------- #
# 영웅 편성 — 안뜰에 여섯, 나머지는 인벤토리
# --------------------------------------------------------------------------- #
## 안뜰에 동시에 세울 수 있는 영웅 수.
## ★ 왜 여섯인가: 예전에는 40탄이면 영웅이 40명이었다. 그러면 (1) 안뜰이 누가 누군지
##   모를 그림 무더기가 되고 (2) 뽑은 영웅을 **버릴 일이 없어서** 족보를 맞추는 것 말고는
##   고를 것이 하나도 없었다. 여섯으로 묶으면 "누구를 세우고 누구를 물리는가"가
##   매 탄의 선택이 된다.
const HERO_SLOTS := 6
## 캐릭터 인벤토리(벤치)에 넣어 둘 수 있는 수.
## ★ 캐릭터가 31명이고 안뜰에 여섯이 서므로 25면 **절대 넘치지 않는다.**
##   넘칠 수 있게 두면 "내 영웅이 조용히 사라졌다"는 규칙을 만들게 된다. 그건 안 만든다.
const BENCH_SLOTS := 25

## 같은 캐릭터가 또 나오면 옆에 세우지 않고 **겹친다.** n겹이면 공격력이 n배다.
## ★ 왜 곱셈이 아니라 그냥 n배인가: 예전처럼 같은 영웅 n명을 나란히 세운 것과
##   단일 대상 피해가 정확히 같다. 그래야 "겹치기로 바뀌어서 약해졌다"가 안 된다.
##   (광역·장판도 마찬가지다 — n명이 같은 자리에서 같이 쏜 것과 같은 셈이다)
static func stack_atk(n: int) -> float:
	return float(maxi(1, n))

# --------------------------------------------------------------------------- #
# 한 판(런)의 기본값
# --------------------------------------------------------------------------- #
## 시작 크리스탈 = 시작 목숨. 화면 가운데에 이 개수만큼 놓인다.
const START_LIVES := 20
const MAX_LIVES := 40
const START_GOLD := 60
## 몇 탄마다 보스가 나오는가.
const BOSS_EVERY := 5
## 마지막 탄. 여기를 넘기면 이긴 것이다.
const LAST_WAVE := 40
## 그 탄의 몬스터가 전부 나오는 데 걸리는 시간(초).
## ★ 길게 잡으면 마지막 놈이 나올 때 앞엣놈은 벌써 크리스탈에 닿아 있다 — 한 번에
##   두어 마리씩만 상대하게 되어 광역·장판이 통째로 무의미해진다.
const SPAWN_WINDOW := 9.0

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
## ★ 사거리는 **길까지 닿아야** 뜻이 있다. 안뜰 한가운데(제단)에서 안쪽 길까지가 217px,
##   바깥 길까지가 299px 다. 그래서 가장 낮은 등급의 가장 짧은 사거리도 270px 는 된다 —
##   안쪽 길은 거의 다 덮고 바깥 길은 조금만 덮는다. (tests/ns_check 의 _check_geometry)
const TIER_RNG  := [300.0, 318.0, 337.0, 358.0, 380.0, 404.0, 430.0, 458.0, 490.0, 530.0]

## 같은 등급 안에서 캐릭터의 결을 가르는 배수. DPS 합은 거의 같게 맞춰 놨다
## (rapid 1.045 · heavy 1.05 · sniper 1.04).
## ★ 예전에 있던 「수호(guard)」는 없앴다 — 사거리가 0.8배라 길까지 닿지도 못했다.
##   이 게임은 벽 너머로 **멀리 쏘는** 게임이다. 근거리는 설 자리가 없다.
const PROFILE := {
	"balance": {"atk": 1.00, "rate": 1.00, "rng": 1.00, "ko": "균형"},
	"rapid":   {"atk": 0.55, "rate": 1.90, "rng": 0.90, "ko": "연사"},
	"heavy":   {"atk": 2.10, "rate": 0.50, "rng": 1.05, "ko": "일격"},
	"sniper":  {"atk": 1.30, "rate": 0.80, "rng": 1.55, "ko": "저격"},
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
	"boss":   {"hp": 14.0, "spd": 0.72, "gold": 12.0, "crush": 5, "ko": "보스"},
}
## 주술사가 거는 저주 — 영웅 전체의 공격속도를 이만큼 깎는다. 겹치지 않고 시간만 새로 찬다.
const CURSE_RATE := 0.18
const CURSE_SEC := 2.5
## 주술사가 저주를 던지는 간격(초).
const CURSE_EVERY := 6.0

## 앞 탄을 두껍게 하는 덤. 1탄이 (1 + EARLY_TOUGH)배이고, 한 탄 지날 때마다
## EARLY_FADE 를 곱해 얇아진다 — 8탄쯤이면 사실상 사라진다.
##
## ★ 왜 넣었나: 예전에는 1탄 떼거리가 3.2 라 **어떤 영웅이든 한 방**이었다. 한 방에
##   죽는 몬스터는 체력 막대도 못 보여 주고, 그 탄이 8초 만에 끝나서(길을 걷는 데 29초다)
##   화면에 아무것도 안 남았다 — 게임을 켠 사람이 처음 보는 장면이 그것이다.
##   덤을 곱하면 1탄 떼거리가 열 남짓이 되어 보통 영웅이 **세 방쯤** 때려야 죽는다.
## ★ 왜 곱셈 덤인가: 뒤 탄의 곡선을 건드리지 않아야 클리어율(25~30%)이 그대로 남는다.
##   지수를 바꾸면 40탄까지 전부 흔들린다 — 1.465 는 24판 중 11판, 1.482 는 5판이었다.
const EARLY_TOUGH := 2.3
const EARLY_FADE := 0.72

## w 탄의 몬스터 한 마리 기준 체력.
## ★ 이 지수는 손으로 고른 게 아니라 tests/balance_check 를 돌려서 맞춘 값이다.
##   **이 줄을 건드리면 반드시 다시 돌려라.** (기대값: 중간값 26~33탄, 12판 중 2~5판 클리어)
static func wave_hp(w: int) -> float:
	return 4.3 * pow(1.469, float(w - 1)) * early_tough(w)


## 앞 탄에 곱하는 덤. 1탄 3.30배 → 3탄 2.19배 → 6탄 1.44배 → 10탄 1.12배.
static func early_tough(w: int) -> float:
	return 1.0 + EARLY_TOUGH * pow(EARLY_FADE, float(w - 1))

## w 탄의 몬스터 수(보스 제외).
static func wave_count(w: int) -> int:
	if is_boss_wave(w):
		return 4 + int(floor(float(w) * 0.5))
	return 5 + int(floor(float(w) * 1.2))

static func is_boss_wave(w: int) -> bool:
	return w % BOSS_EVERY == 0

## 몬스터 한 마리를 잡았을 때 나오는 골드(배수 적용 전).
static func kill_gold(w: int, kind: String) -> int:
	var base := 3.0 + float(w) * 0.25
	return int(round(base * float(MKIND[kind]["gold"])))

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
## 길은 토막(segment) 몇 개로 되어 있다.
##   {"arc": r, "a0", "a1"}      벽과 벽 사이를 도는 복도
##   {"rad": ang, "r0", "r1"}    문을 지나 안쪽 겹으로 내려가는 통로
## ★ 한 번만 만들어 두고 계속 쓴다. 좌표를 물을 때마다 다시 만들면 한 프레임에
##   몬스터 수만큼 배열이 생긴다. 값이 상수뿐이라 캐시해도 순수하다.
static var _segs: Array = []
static var _seg_len: float = 0.0


static func _ensure_path() -> void:
	if not _segs.is_empty():
		return
	var segs: Array = []
	# 바깥문으로 들어온다
	segs.append({"rad": GATE_A[0], "r0": SPAWN_R, "r1": LANE_R[0]})
	for i in range(LANE_R.size()):
		var a0: float = GATE_A[i]
		segs.append({"arc": LANE_R[i], "a0": a0, "a1": a0 + LANE_SWEEP})
		var r1: float = LANE_R[i + 1] if i + 1 < LANE_R.size() else ALTAR_R
		segs.append({"rad": GATE_A[i + 1], "r0": LANE_R[i], "r1": r1})
	var total := 0.0
	for s in segs:
		var l: float = 0.0
		if s.has("arc"):
			l = absf(float(s["a1"]) - float(s["a0"])) * float(s["arc"])
		else:
			l = absf(float(s["r1"]) - float(s["r0"]))
		s["len"] = l
		s["from"] = total
		total += l
	_segs = segs
	_seg_len = total


## 길 전체의 길이(px).
static func path_len() -> float:
	_ensure_path()
	return _seg_len


## 길을 s(px)만큼 걸었을 때의 자리. off 는 길 좌우로 흩어지는 정도(px).
static func path_at(s: float, off: float = 0.0) -> Vector2:
	_ensure_path()
	s = clampf(s, 0.0, _seg_len)
	for i in range(_segs.size()):
		var seg: Dictionary = _segs[i]
		var from: float = seg["from"]
		var l: float = seg["len"]
		# 마지막 토막은 무조건 여기서 받는다 — 부동소수 오차로 아무 토막도 안 걸리면
		# 몬스터가 통째로 투기장 한가운데로 순간이동한다.
		if s > from + l and i < _segs.size() - 1:
			continue
		var k: float = clampf((s - from) / max(0.001, l), 0.0, 1.0)
		# 토막 경계(문) 가까이에서는 좌우 흩어짐을 0 으로 좁힌다 — 위 GATE_NARROW 주석 참고.
		var edge: float = min(s - from, from + l - s)
		off *= clampf(edge / GATE_NARROW, 0.0, 1.0)
		if seg.has("arc"):
			# 복도를 돈다 — 좌우로 흩어지는 것은 반지름을 밀면 된다.
			var a: float = lerpf(float(seg["a0"]), float(seg["a1"]), k)
			var r: float = float(seg["arc"]) + off
			return ARENA_CENTER + Vector2(cos(a), sin(a)) * r
		# 문을 지나 안쪽으로 내려간다 — 여기서는 좌우가 곧 각도다.
		var ang: float = float(seg["rad"])
		var rr: float = lerpf(float(seg["r0"]), float(seg["r1"]), k)
		var da: float = off / max(20.0, rr)
		return ARENA_CENTER + Vector2(cos(ang + da), sin(ang + da)) * rr
	return ARENA_CENTER


# --------------------------------------------------------------------------- #
# 카드 리롤 — "한 번 리롤한 카드는 추가 골드를 내야 더 리롤할 수 있다"
# --------------------------------------------------------------------------- #
## 카드 한 장당 공짜 리롤 횟수(기본). 상점에서 늘릴 수 있다.
const FREE_REROLL := 1
## 공짜를 다 쓴 뒤 n 번째 유료 리롤의 값 (n 은 1부터).
static func reroll_cost(paid_times: int) -> int:
	return int(15 * pow(2.0, float(paid_times)))

# --------------------------------------------------------------------------- #
# 상점 1 — 값이 오르는 능력치. lv 은 지금까지 산 횟수.
# --------------------------------------------------------------------------- #
const UPGRADES := [
	{"id": "atk",    "ko": "공격력",     "desc": "모든 영웅 공격력 +15%",     "base": 40,  "grow": 1.34, "cap": 0},
	{"id": "rate",   "ko": "공격속도",   "desc": "모든 영웅 공격속도 +9%",    "base": 45,  "grow": 1.37, "cap": 0},
	{"id": "rng",    "ko": "사거리",     "desc": "모든 영웅 사거리 +8%",      "base": 35,  "grow": 1.30, "cap": 12},
	{"id": "crit",   "ko": "치명타 확률", "desc": "치명타 확률 +5%",          "base": 60,  "grow": 1.40, "cap": 11},
	{"id": "critx",  "ko": "치명타 배율", "desc": "치명타 배율 +0.35배",      "base": 70,  "grow": 1.42, "cap": 0},
	{"id": "gold",   "ko": "골드 획득",   "desc": "처치 골드 +12%",           "base": 55,  "grow": 1.45, "cap": 0},
	{"id": "life",   "ko": "크리스탈",   "desc": "크리스탈 +1",              "base": 80,  "grow": 1.62, "cap": 20},
	{"id": "reroll", "ko": "공짜 리롤",   "desc": "카드마다 공짜 리롤 +1",     "base": 50,  "grow": 1.55, "cap": 4},
	# ★ 제한 시간이 없어졌으므로(크리스탈이 곧 목숨이다) 그 자리에 「길」을 산다.
	#   몬스터가 느려지면 그만큼 오래 얻어맞는다 — 예전 「제한 시간 +2초」와 같은 자리다.
	{"id": "mire",   "ko": "길 진창",    "desc": "몬스터 이동속도 -5%",       "base": 95,  "grow": 1.55, "cap": 5},
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
# 상점 2 — 무기. **장착 칸이 셋뿐**이라 무엇을 빼고 무엇을 들지가 곧 선택이다.
# --------------------------------------------------------------------------- #
## 무기 하나는 모든 영웅에게 함께 걸린다(영웅마다 따로 채우지 않는다).
## 왜 셋으로 묶었나: 무기를 영웅마다 따로 채우게 하면 안뜰을 다시 짤 때마다 무기도
## 같이 옮겨 붙여야 한다. "전군에 걸리는 장비 셋"이 훨씬 빠르고 셈도 쉽다 —
## 영웅을 바꿔 세워도 무기는 그대로 걸린다.
const WEAPON_SLOTS := 3
const WEAPONS := [
	{"id": "longbow",  "ko": "장궁",       "desc": "사거리 +18%",              "cost": 170, "rng": 1.18},
	{"id": "repeater", "ko": "연발 장치",   "desc": "공격속도 +16%",            "cost": 190, "rate": 1.16},
	{"id": "heavytip", "ko": "무거운 촉",   "desc": "공격력 +24%, 공격속도 -7%", "cost": 210, "atk": 1.24, "rate": 0.93},
	{"id": "scope",    "ko": "조준경",     "desc": "치명타 확률 +8%",           "cost": 220, "crit": 0.08},
	{"id": "splitter", "ko": "분열 탄두",   "desc": "모든 탄이 작게 터진다",      "cost": 270, "split": 40.0},
	{"id": "frostcore","ko": "서리 심",     "desc": "모든 공격이 15% 둔화",      "cost": 240, "slow": 0.15, "slow_sec": 1.6},
	{"id": "goldbar",  "ko": "금장 총열",   "desc": "처치 골드 +20%",           "cost": 200, "gold": 1.20},
	{"id": "mortar",   "ko": "공성 박격포", "desc": "광역 반경 +45%, 공격력 +12%", "cost": 300, "atk": 1.12, "radius": 1.45},
]

static func weapon_by_id(id: String) -> Dictionary:
	for w in WEAPONS:
		if w["id"] == id:
			return w
	return {}

## 무기를 뺄 때 돌려받는 골드. 절반이라 "일단 사 보는" 것이 벌이 되지는 않게.
static func weapon_refund(id: String) -> int:
	var w := weapon_by_id(id)
	return int(float(w.get("cost", 0)) * 0.5) if not w.is_empty() else 0

# --------------------------------------------------------------------------- #
# 상점 3 — 아이템. 사 두었다가 **전투 중에 눌러서** 쓴다.
# --------------------------------------------------------------------------- #
## 왜 넣었나: 전투가 100% 자동이라 손댈 곳이 배속 버튼뿐이었다. 위험한 순간에
## 쓸 것이 하나라도 있어야 40탄을 도는 동안 화면을 보게 된다.
const ITEM_MAX := 5
const ITEMS := [
	{"id": "bomb",   "ko": "벼락 폭탄",   "desc": "길 위 모두에게 큰 피해",   "cost": 90},
	{"id": "freeze", "ko": "시간 정지",   "desc": "3초간 몬스터가 멈춘다",    "cost": 110},
	{"id": "repair", "ko": "크리스탈 수리", "desc": "크리스탈 둘을 되살린다",  "cost": 140},
	{"id": "rally",  "ko": "진군 나팔",   "desc": "8초간 공격속도 +60%",     "cost": 100},
]

static func item_by_id(id: String) -> Dictionary:
	for it in ITEMS:
		if it["id"] == id:
			return it
	return {}

const ITEM_FREEZE_SEC := 3.0
const ITEM_RALLY_SEC := 8.0
const ITEM_RALLY_RATE := 0.60
const ITEM_REPAIR := 2

## 벼락 폭탄의 피해. 그 탄 몬스터 한 마리의 체력을 기준으로 잡아야
## 40탄에서도 쓸모가 남는다(고정값이면 후반에 아무 일도 안 일어난다).
static func bomb_damage(w: int) -> float:
	return wave_hp(w) * 1.7

# --------------------------------------------------------------------------- #
# 상점 4 — 패시브. 한 번만 산다. 상점이 매번 이 중 셋을 골라 내놓는다.
# --------------------------------------------------------------------------- #
const PASSIVES := [
	{"id": "flame",  "ko": "화염 부적", "desc": "모든 공격이 3초간 태운다",        "cost": 140},
	{"id": "frost",  "ko": "서리 부적", "desc": "모든 공격이 2초간 느리게 만든다",  "cost": 140},
	{"id": "pierce", "ko": "관통 촉",   "desc": "모든 탄이 한 마리를 더 뚫는다",    "cost": 170},
	{"id": "vamp",   "ko": "흡혈",     "desc": "처치할 때 4% 확률로 크리스탈 +1",  "cost": 220},
	{"id": "bolt",   "ko": "연쇄 낙뢰", "desc": "12% 확률로 번개가 튄다",          "cost": 200},
	{"id": "midas",  "ko": "황금손",   "desc": "처치 골드 +25%",                 "cost": 180},
	{"id": "rage",   "ko": "광폭화",   "desc": "탄이 시작하고 25초 뒤 공격속도 +50%", "cost": 190},
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
## ★ 제한 시간이 없어져서 「남은 10초」라는 기준이 사라졌다. 대신 **탄이 오래 끌면**
##   켜지는 것으로 바꿨다 — 뜻은 그대로다(막판에 힘을 낸다).
const PASSIVE_RAGE_AFTER := 25.0
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

## 길 진창 — 몬스터가 이만큼 느려진다.
static func mire_mult(lv: int) -> float:
	return pow(0.95, float(lv))


# --------------------------------------------------------------------------- #
# 크리스탈이 놓이는 자리 — 제단을 둘러싼 고리
# --------------------------------------------------------------------------- #
## i 번째 크리스탈의 자리(투기장 중심 기준 상대 좌표).
## 스물까지는 바깥 고리에, 그 위는 안쪽 고리에 놓는다(상점에서 마흔까지 늘 수 있다).
static func crystal_slot(i: int) -> Vector2:
	var ring: int = mini(int(i / CRYSTAL_PER_RING), CRYSTAL_R.size() - 1)
	var idx: int = i - ring * CRYSTAL_PER_RING
	var a: float = TAU * float(idx) / float(CRYSTAL_PER_RING) - PI * 0.5 + float(ring) * 0.16
	return Vector2(cos(a), sin(a)) * float(CRYSTAL_R[ring])


# --------------------------------------------------------------------------- #
# 영웅이 서는 자리 — 여섯 명이 한 겹으로 둘러선다
# --------------------------------------------------------------------------- #
## 한 겹에 몇 명까지 서는가. 안뜰 바깥 고리를 HERO_SPACING 으로 나눈 값이다.
static func hero_ring_cap() -> int:
	return maxi(1, int(floor((TAU - HERO_GAP * 2.0) * HERO_MAX_R / HERO_SPACING)))

## n 명이 한 겹으로 설 때의 반지름.
##
## ★ 사람이 적으면 **안쪽으로 모인다.** 여섯이 늘 바깥 고리에 서면 한둘뿐인 첫 탄에
##   투기장 반대편에 뚝 떨어져 서서 안뜰이 텅 비어 보인다.
static func hero_ring_r(n: int) -> float:
	var need: float = float(maxi(1, n)) * HERO_SPACING / (TAU - HERO_GAP * 2.0)
	return clampf(need, HERO_MIN_R, HERO_MAX_R)

## n 명 중 i 번째 영웅이 설 자리(투기장 중심 기준 상대 좌표).
##
## ★ **아무도 가운데에 서지 않는다.** 가운데는 크리스탈 제단이다.
## ★ 안뜰문에서 제단으로 이어지는 진입로(HERO_GAP)도 비운다. 몬스터가 마지막에
##   들어오는 길목인데 영웅이 그 위에 서 있으면 "어디로 들어오는지"가 안 보인다.
## ★ 안뜰에는 HERO_SLOTS(6)명뿐이라 한 겹이면 늘 충분하다. 그보다 많이 넣으면
##   (검사기가 일부러 그렇게 해 본다) 겹을 늘려 안뜰 안에 우겨 넣는다.
static func hero_slot(i: int, n: int) -> Vector2:
	if n <= 0:
		return Vector2(0, -HERO_MIN_R)
	var span: float = TAU - HERO_GAP * 2.0
	var cap := hero_ring_cap()
	var rings: int = maxi(1, int(ceil(float(n) / float(cap))))
	var per: int = int(ceil(float(n) / float(rings)))
	var j: int = mini(i / per, rings - 1)             # 몇 번째 겹인가
	var idx: int = i - j * per
	var take: int = maxi(1, mini(per, n - j * per))
	var r: float = hero_ring_r(take) if rings == 1 \
			else lerpf(HERO_MIN_R, HERO_MAX_R, float(j) / float(rings - 1))
	# 진입로(안뜰문 각도)를 비우고 나머지 둘레에 고르게 편다.
	var a: float = GATE_A[GATE_A.size() - 1] + HERO_GAP \
			+ span * ((float(idx) + 0.5) / float(take))
	return Vector2(cos(a), sin(a)) * r

## 영웅이 늘어날수록 그림을 조금씩 줄인다. 안 그러면 안뜰이 그림 무더기가 된다.
## ★ 여섯 명까지는 줄이지 않는다 — 안뜰이 그만큼 한가해졌다.
static func hero_scale(n: int) -> float:
	return clampf(1.0 - float(maxi(0, n - HERO_SLOTS)) * 0.02, 0.62, 1.0)
