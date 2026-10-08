extends RefCounted
class_name Rite

## 별맞춤 의식 — 영웅을 불러내는 뽑기의 규칙. **순수 함수만 있다** — 화면도 저장도 모른다.
##
## 생명 수정 둘레를 다섯 궤도의 별이 돈다. 별이 멈췄을 때 「빛의 문」 안에 든 별의
## 개수가 곧 등급이다 — 하나면 1성, 다섯이면 5성. **규칙은 이것 하나뿐이다.**
##
## 사용자가 정한 것(2026-10-07): 「캐릭터 뽑는 도박이 너무 어렵게 되어 있다. 조금 더
## 직관적이고 (룰렛과 같지만 룰렛이 아닌, 새롭고 신비한) 게임으로 뽑게 하고, 결과에 따라
## 1성부터 5성까지 분류되게」. 포커는 족보 열 가지를 외워야 읽혔다. 여기서는 **세면 읽힌다.**
##
## 한 탄의 흐름:
##   1. 별 다섯이 멈춘다(roll). 가장 안쪽 별은 수정이 붙들어 **언제나 문 안**이다 — 최소 1성.
##   2. 문 밖의 별만 다시 돌린다(respin). 문 안에 든 별은 그대로 잠긴다.
##      몇 번을 돌려도 **이미 든 별은 안 빠진다** — 다시 돌려서 손해 보는 일이 없다.
##   3. 확정하면 문 안의 별 수가 등급이 된다(tier_of).
##
## ★ 이 파일이 뽑기의 심장이다. 여기가 틀리면 「문 안에 셋이 섰는데 2성이 나오는」
##   종류의 버그가 나고, 그건 플레이어가 게임을 못 믿게 만든다. 그래서
##   tests/rite_check.gd 가 odds() 를 **수십만 번의 실제 굴림**과 맞춰 본다.
## ★ **그리는 쪽이 지켜야 할 것: 문의 폭은 장식이 아니라 확률 그 자체다.**
##   궤도 r 의 문은 0번 칸부터 gate(r) 칸이다. 화면은 angle() 과 gate_half() 가 주는
##   자리 그대로 그려야 한다 — 보이는 문과 판정이 어긋나면 「문 안에 섰는데 빗나갔다」가
##   되고, 그 순간 이 뽑기는 못 믿을 것이 된다.

## 궤도(별)의 수. 문 안에 다 들면 5성이다.
const RINGS := 5
const MIN_STARS := 1
const MAX_STARS := 5


## 한 궤도를 나눈 칸 수. 별이 멈춘 자리는 0..slots()-1 의 정수다.
static func slots() -> int:
	return Balance.RITE_SLOTS


## 그 궤도의 문 너비(칸). 문은 0번 칸에서 시작해 이만큼이다.
static func gate(ring: int) -> int:
	return int(Balance.RITE_GATE[clampi(ring, 0, RINGS - 1)])


## 수정이 붙드는 별인가. 붙들린 별은 **언제나 문 안**에 멈춘다 — 그래서 최소 1성이다.
static func anchored(ring: int) -> bool:
	return ring >= 0 and ring < Balance.RITE_ANCHORED


## 그 궤도의 별이 한 번 돌아서 문 안에 멈출 확률.
static func chance(ring: int) -> float:
	if anchored(ring):
		return 1.0
	return float(gate(ring)) / float(slots())


static func in_gate(ring: int, pos: int) -> bool:
	return pos >= 0 and pos < gate(ring)


## 저장 파일에서 온 값이 별 다섯의 자리로 쓸 수 있는 꼴인가.
## 붙들린 별이 문 밖에 서 있는 것도 거절한다 — 규칙으로는 만들 수 없는 상태다.
static func valid(orbit: Variant) -> bool:
	if not orbit is Array or orbit.size() != RINGS:
		return false
	for ring in range(RINGS):
		var pos: Variant = orbit[ring]
		if not pos is int or pos < 0 or pos >= slots():
			return false
		if anchored(ring) and not in_gate(ring, pos):
			return false
	return true


## 궤도마다 문 안에 들었는가.
static func hits(orbit: Array) -> Array[bool]:
	var out: Array[bool] = []
	for ring in range(RINGS):
		out.append(ring < orbit.size() and in_gate(ring, int(orbit[ring])))
	return out


## 문 안에 든 별의 수 = 등급(1~5성).
static func stars(orbit: Array) -> int:
	var n := 0
	for ring in range(mini(RINGS, orbit.size())):
		if in_gate(ring, int(orbit[ring])):
			n += 1
	return clampi(n, MIN_STARS, MAX_STARS)


## 문 밖에 선 별의 궤도 번호들(안쪽부터). 다시 돌릴 때 도는 것이 이들이다.
static func misses(orbit: Array) -> Array[int]:
	var out: Array[int] = []
	for ring in range(mini(RINGS, orbit.size())):
		if not in_gate(ring, int(orbit[ring])):
			out.append(ring)
	return out


## 끌어올 별 — 문 밖의 별 중 **가장 바깥** 것. 없으면 -1.
## ★ 왜 바깥부터인가: 바깥 궤도일수록 문이 좁아 다시 돌려서는 잘 안 든다.
##   확정으로 끌어오는 수단(광고 · 조커)은 제일 어려운 별에 쓰는 것이 언제나 이득이다.
static func pull_target(orbit: Array) -> int:
	var out := misses(orbit)
	return out[-1] if not out.is_empty() else -1


## 별 하나를 한 번 돌린다. 붙들린 별은 문 안의 아무 자리에나 선다.
static func roll_ring(ring: int, rng: RandomNumberGenerator) -> int:
	if anchored(ring):
		return rng.randi_range(0, gate(ring) - 1)
	return rng.randi_range(0, slots() - 1)


## 새 의식 — 별 다섯을 한 번씩 돌린다.
static func roll(rng: RandomNumberGenerator) -> Array[int]:
	var orbit: Array[int] = []
	for ring in range(RINGS):
		orbit.append(roll_ring(ring, rng))
	return orbit


## 문 밖의 별만 다시 돌린다. 다시 돈 궤도 번호들을 돌려준다(화면이 그 별만 돌린다).
static func respin(orbit: Array[int], rng: RandomNumberGenerator) -> Array[int]:
	var moved := misses(orbit)
	for ring in moved:
		orbit[ring] = roll_ring(ring, rng)
	return moved


## 그 궤도의 별을 문 안으로 끌어온다(광고 보상 · 조커).
static func pull(orbit: Array[int], ring: int, rng: RandomNumberGenerator) -> void:
	if ring >= 0 and ring < orbit.size():
		orbit[ring] = rng.randi_range(0, gate(ring) - 1)


## 문 안의 별이 `want` 개가 될 때까지 **안쪽 별부터** 문 안에 세운다. 이미 넉넉하면 그대로다.
## 판의 첫 의식이 쓴다(Balance.RITE_FIRST_STARS).
static func ensure_stars(orbit: Array[int], want: int, rng: RandomNumberGenerator) -> void:
	for ring in misses(orbit):
		if stars(orbit) >= mini(want, MAX_STARS):
			return
		pull(orbit, ring, rng)


# --------------------------------------------------------------------------- #
# 별과 등급 — 등급은 반 별 단위(0~9)이고, 의식은 온 별만 준다
# --------------------------------------------------------------------------- #
## 문 안의 별 수 → 영웅 등급. 1성 = 1, 2성 = 3 … 5성 = 9.
##
## ★ 등급(tier)은 **반 별 단위**의 열 칸(0~9)이다(Balance.TIER_ATK). 의식이 주는 것은
##   언제나 온 별이라 홀수 칸에만 떨어지고, 그 사이의 반 별은 **전투 중 승급과 합성**으로만
##   오른다 — 사용자가 정한 것: 「0.5성 단위 유지」.
static func tier_of(star_count: int) -> int:
	return clampi(star_count, MIN_STARS, MAX_STARS) * 2 - 1


## 등급 → 별 수(반 별 포함). 3 → 2.0, 4 → 2.5.
static func tier_stars(tier: int) -> float:
	return float(clampi(tier, 0, Balance.TIER_MAX) + 1) * 0.5


## 등급을 별 숫자로 적는다. 「2」·「2.5」처럼 — 「성」은 화면이 붙인다.
static func star_text(tier: int) -> String:
	var value := tier_stars(tier)
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value


# --------------------------------------------------------------------------- #
# 확률 — 화면의 안내와 검사기가 같은 표를 본다
# --------------------------------------------------------------------------- #
## 모두 `spin_count` 번 돌렸을 때(처음 한 번 포함) 별 수의 분포. out[n] = n성이 될 확률.
## 0번 칸은 언제나 0 이다 — 붙들린 별 때문에 0성은 없다.
##
## ★ 다시 돌리기는 **문 밖의 별 전부**를 돌리므로, n 번 돌린 뒤 한 궤도가 문 안에 있을
##   확률은 1 - (1 - p)^n 이다. 궤도끼리는 서로 상관이 없어서 그 다섯을 차례로 접으면 된다.
static func odds(spin_count: int = 1) -> Array[float]:
	var out: Array[float] = []
	out.resize(RINGS + 1)
	out.fill(0.0)
	out[0] = 1.0
	var tries := maxi(1, spin_count)
	for ring in range(RINGS):
		var hit := 1.0 - pow(1.0 - chance(ring), float(tries))
		for n in range(RINGS, -1, -1):
			out[n] = out[n] * (1.0 - hit) + (out[n - 1] * hit if n > 0 else 0.0)
	return out


# --------------------------------------------------------------------------- #
# 그리는 자리 — 판정과 그림이 같은 숫자를 쓴다
# --------------------------------------------------------------------------- #
## 문 한가운데가 가리키는 쪽. 화면 좌표라 -PI/2 가 위다.
const GATE_ANGLE := -PI * 0.5


## 그 궤도의 문이 한가운데에서 양쪽으로 벌어진 각(라디안).
static func gate_half(ring: int) -> float:
	return float(gate(ring)) / float(slots()) * PI


## 궤도 ring 의 pos 번 칸이 놓이는 각(라디안, 화면 좌표).
## 문 안의 칸(0..gate-1)은 GATE_ANGLE 을 가운데로 한 호 위에 고르게 놓이고,
## 문 밖의 칸은 그 바깥을 시계 방향으로 이어 돈다.
static func angle(ring: int, pos: int) -> float:
	var step := TAU / float(slots())
	return GATE_ANGLE - gate_half(ring) + (float(pos) + 0.5) * step
