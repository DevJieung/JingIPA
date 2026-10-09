extends RefCounted
class_name Fixture

## 검사·촬영이 세우는 **판**. 「n탄까지 간 판」 · 「원하는 별 수가 나오는 의식」 —
## shot.gd 와 demo.gd 가 같은 손으로 베껴 쓰던 것을 한 곳에 둔다.
##
## ★ 배열을 직접 만지는 것은 tests/ 라서 괜찮다. 화면에서 그러면 안 된다(CLAUDE.md 14-3).

## 문 안에 별이 정확히 `star_count` 개 서는 별 자리(1~5). 안쪽 궤도부터 문 안에 세운다.
## 문 안의 별은 문 한가운데에, 문 밖의 별은 문 맞은편에 선다 — 문 너비를 다시 잡아도
## (Balance.RITE_GATE) 경계에 걸리지 않는다.
static func orbit_for(star_count: int) -> Array[int]:
	var want := clampi(star_count, Rite.MIN_STARS, Rite.MAX_STARS)
	var orbit: Array[int] = []
	for ring in range(Rite.RINGS):
		if ring < want:
			orbit.append(Rite.gate(ring) / 2)
		else:
			orbit.append(Rite.gate(ring) + (Rite.slots() - Rite.gate(ring)) / 2)
	return orbit


## 새 판을 열고 첫 탄의 의식을 연다. `count` 명이면 표의 앞에서부터 그만큼 영웅을 준다.
## ★ 등급은 캐릭터의 것이 아니지만(Balance.TIER_ATK 의 ★) 여기서는 표의 원화 격을 그대로
##   등급으로 준다 — 검사가 0.5성부터 5성까지 고루 섞인 편성을 보게 하려는 것이다.
static func fresh(seed_value: int, count: int = 0) -> void:
	Run.start_run(seed_value)
	Run.begin_draw()
	for i in range(count):
		var u: Dictionary = Roster.UNITS[i]
		Run.gain_hero(u, int(u["tier"]))


## 원하는 탄까지 상태를 만든다(영웅 n명 · 골드 넉넉히). `wave` 탄을 **뽑기 직전**(wave = w-1)
## 까지 만들어 두므로, 부르는 쪽이 `Run.begin_draw()` 로 그 탄을 연다.
static func prepare(wave: int, seed_value: int) -> void:
	Run.start_run(seed_value)
	Run.gold = 400 + wave * 90
	for i in range(maxi(0, wave - 1)):
		Run.begin_draw()
		Run.confirm_summon()
	# ★ 성역은 자리가 정해져 있다. 사람이라면 센 쪽을 세워 두므로 검사 정책과 같은 손으로
	#   정리해 둔다 — 안 그러면 사진 속 성역이 "먼저 뽑은 것들"이라 실제 화면과 다르다.
	PlayPolicy.arrange(Run)
	# 상점을 몇 번 거친 것처럼 능력치도 조금 올려 둔다 — 빈 상점은 실제 화면이 아니다.
	Run.levels["atk"] = int(wave / 3)
	Run.levels["rate"] = int(wave / 5)
	# ★ **상한(cap)이 있는 능력치는 그 위로 못 올린다.** 공격속도 등 상한이 있는 줄은
	#   현재 강화 표를 따라 검사·촬영용 단계도 제한한다.
	#   여기에 그런 줄을 하나라도 더하는 날, 이 고리가 없으면 사진이 **상점에서 살 수도
	#   없는 판**을 보여 주게 된다 — 없앤 사거리 줄이 실제로 그랬다(42탄이면 7단계로
	#   박히는데 상점은 6단계까지만 팔았다).
	for k in Run.levels.keys():
		var cap: int = int(Balance.upgrade_by_id(String(k)).get("cap", 0))
		if cap > 0:
			Run.levels[k] = mini(int(Run.levels[k]), cap)
	# 패시브도 몇 장 쥐여 준다. 빈 칸만 찍으면 새 화면이 제대로 도는지 안 보인다.
	Run.passives.clear()
	if wave >= 4:
		Run.passives.append("keenedge")
	if wave >= 8:
		Run.passives.append("repeater")
	if wave >= 12:
		Run.passives.append("pierce")
	Run.owned_passives.assign(Run.passives)
	# 상점 진열도 채워 둔다 — 화면을 안 타므로(main.go_shop) 여기서 굴려 준다.
	Run.shop_offer.clear()
	Run.roll_shop()


## 문 안에 별이 `star_count` 개 서도록 이번 탄의 의식을 손으로 깔아 준다(1~5).
## 다시 돌린 횟수도 처음으로 되돌린다.
static func stack(star_count: int) -> void:
	Run.orbit.assign(orbit_for(star_count))
	Run.spins = 0
	Run.paid_spins = 0
