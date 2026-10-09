extends Harness

## 별맞춤 의식의 규칙을 검사한다 — 뽑기의 심장(core/rite.gd)이 적힌 그대로 도는가.
##
## 포커 시절에는 2,598,960가지 손패를 전수로 돌려 족보를 믿었다. 의식은 규칙이 훨씬
## 작아서 **경계는 전수로, 확률은 실제 굴림으로** 본다:
##   1. 문의 경계 — 모든 궤도의 모든 칸(1,800개)에서 「문 안」이 정확히 문 너비만큼인가
##   2. 별 세기 — 경계 칸을 섞은 512가지 자리에서 별 수·빗나간 별·끌어올 별이 맞는가
##   3. 확률표 — odds() 가 실제로 굴려 본 분포와 맞는가 (다시 돌리기 0·1·4번)
##   4. 다시 돌리기 — 문 안의 별이 한 번도 안 빠지는가, 붙들린 별은 안 도는가
##   5. 그리는 자리 — angle() 이 문 안의 칸만 문 안에 놓는가 (보이는 문 = 판정)
##   6. 소환 — 별 수가 등급이 되고, 쉰 명 누구든 어느 등급으로든 나오는가
##   7. 첫 의식 — 판의 첫 영웅만 2성이 보장되는가
##
##   godot --headless --path . res://tests/rite_check.tscn
##   godot --headless --path . res://tests/rite_check.tscn -- --quick   (굴림을 줄인다)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if not require_no_save():
		return
	_rng.seed = 20261007
	var quick := Harness.has_arg("--quick")
	_check_table()
	_check_gate_edges()
	_check_counting()
	_check_valid()
	_check_odds_shape()
	var rolled := 0
	for respins in [0, 1, 4]:
		rolled += _check_odds_by_rolling(respins, 40000 if quick else 200000)
	print("  굴림 검사 %d판" % rolled)
	_check_respin()
	_check_pull()
	_check_angles()
	_check_first_rite()
	_check_summon()
	_check_passives()
	_check_anyone_any_star()
	finish("별맞춤 의식 규칙 검사")


## 표의 꼴 — 문은 한 궤도를 넘지 않고, 바깥으로 갈수록 좁아지고, 가장 안쪽 별은 붙들려 있다.
func _check_table() -> void:
	check(Rite.RINGS == 5 and Balance.RITE_GATE.size() == Rite.RINGS, "궤도는 다섯이고 문 너비도 다섯 줄이다")
	check(Rite.MIN_STARS == 1 and Rite.MAX_STARS == Rite.RINGS, "별은 1개부터 궤도 수까지다")
	check(Balance.RITE_ANCHORED == 1 and Rite.anchored(0) and not Rite.anchored(1),
			"붙들린 별은 가장 안쪽 하나뿐이다 — 최소 1성이 여기서 나온다")
	check(not Rite.anchored(-1) and not Rite.anchored(Rite.RINGS), "궤도 밖 번호는 붙들린 별이 아니다")
	for ring in range(Rite.RINGS):
		check(Rite.gate(ring) >= 1 and Rite.gate(ring) <= Rite.slots(), "문 너비가 한 궤도 안이다: %d번" % ring)
		if ring >= 2:
			check(Rite.gate(ring) < Rite.gate(ring - 1), "바깥 궤도일수록 문이 좁다: %d번" % ring)
		var p := Rite.chance(ring)
		if Rite.anchored(ring):
			check(is_equal_approx(p, 1.0), "붙들린 별은 언제나 문 안이다")
		else:
			check(p > 0.0 and p < 1.0 and is_equal_approx(p, float(Rite.gate(ring)) / Rite.slots()),
					"문 너비가 곧 확률이다: %d번" % ring)
	for stars in range(1, 6):
		var tier := Rite.tier_of(stars)
		check(tier == stars * 2 - 1 and tier % 2 == 1, "%d성은 홀수 칸(온 별)이다" % stars)
		check(is_equal_approx(Rite.tier_stars(tier), float(stars)) and Rite.star_text(tier) == str(stars),
				"등급 %d 는 %d성으로 적힌다" % [tier, stars])
	check(Rite.tier_of(0) == 1 and Rite.tier_of(9) == Balance.TIER_MAX, "별 수가 범위를 벗어나도 1성~5성 안이다")
	check(Rite.star_text(4) == "2.5" and Rite.star_text(0) == "0.5" and Rite.star_text(Balance.TIER_MAX) == "5",
			"반 별은 소수 한 자리로 적힌다")
	check(Balance.TIER_ATK.size() == Balance.TIER_MAX + 1 and Balance.TIER_RATE.size() == Balance.TIER_MAX + 1
			and Roster.TIER_KO.size() == Balance.TIER_MAX + 1, "등급 표가 열 칸이다")
	for tier in range(1, Balance.TIER_MAX + 1):
		check(Balance.TIER_ATK[tier] * Balance.TIER_RATE[tier] > Balance.TIER_ATK[tier - 1] * Balance.TIER_RATE[tier - 1],
				"등급이 오르면 반드시 세진다: %d" % tier)
		check(Roster.TIER_KO[tier] == Rite.star_text(tier) + "성", "등급 이름이 별 수다: %d" % tier)


## 모든 궤도의 모든 칸 — 문 안인 칸이 정확히 0..gate-1 이다.
func _check_gate_edges() -> void:
	for ring in range(Rite.RINGS):
		var inside := 0
		for pos in range(Rite.slots()):
			if Rite.in_gate(ring, pos):
				inside += 1
				check(pos < Rite.gate(ring), "문 안의 칸은 문 너비보다 작은 번호다")
		check(inside == Rite.gate(ring), "문 안인 칸 수가 문 너비와 같다: %d번 (%d칸)" % [ring, inside])
		check(not Rite.in_gate(ring, -1) and not Rite.in_gate(ring, Rite.slots()), "궤도 밖 칸은 문 안이 아니다")
		check(Rite.in_gate(ring, 0) and Rite.in_gate(ring, Rite.gate(ring) - 1), "문의 두 끝 칸은 문 안이다")
		if Rite.gate(ring) < Rite.slots():
			check(not Rite.in_gate(ring, Rite.gate(ring)), "문 바로 다음 칸은 문 밖이다")


## 경계 칸을 섞은 512가지 자리(붙들린 별 2 x 나머지 4^4) — 별 수 · 빗나간 별 · 끌어올 별.
func _check_counting() -> void:
	var options: Array = []
	for ring in range(Rite.RINGS):
		# 문 안의 두 끝, 문 밖의 두 끝. 붙들린 별은 문 안에만 설 수 있다.
		var row: Array = [0, Rite.gate(ring) - 1]
		if not Rite.anchored(ring):
			row.append(Rite.gate(ring))
			row.append(Rite.slots() - 1)
		options.append(row)
	var seen := 0
	var index := [0, 0, 0, 0, 0]
	while true:
		var orbit: Array[int] = []
		var want := 0
		var want_misses: Array[int] = []
		for ring in range(Rite.RINGS):
			var pos := int(options[ring][index[ring]])
			orbit.append(pos)
			if pos < Rite.gate(ring):
				want += 1
			else:
				want_misses.append(ring)
		seen += 1
		check(Rite.valid(orbit), "경계 자리는 쓸 수 있는 꼴이다")
		check(Rite.stars(orbit) == want, "문 안의 별 수가 등급이다 %s" % str(orbit))
		check(Rite.misses(orbit) == want_misses, "빗나간 별의 목록 %s" % str(orbit))
		var hits := Rite.hits(orbit)
		for ring in range(Rite.RINGS):
			check(hits[ring] == (not want_misses.has(ring)), "궤도별 명중 %s" % str(orbit))
		check(Rite.pull_target(orbit) == (want_misses[-1] if not want_misses.is_empty() else -1),
				"끌어올 별은 문 밖의 가장 바깥 별이다 %s" % str(orbit))
		# 다음 조합으로.
		var ring_i := 0
		while ring_i < Rite.RINGS:
			index[ring_i] += 1
			if index[ring_i] < options[ring_i].size():
				break
			index[ring_i] = 0
			ring_i += 1
		if ring_i >= Rite.RINGS:
			break
	print("  경계 자리 %d가지" % seen)


func _check_valid() -> void:
	var good := Fixture.orbit_for(3)
	check(Rite.valid(good), "바른 자리는 통과한다")
	check(not Rite.valid([]) and not Rite.valid([0, 0, 0, 0]) and not Rite.valid([0, 0, 0, 0, 0, 0]),
			"별이 다섯이 아니면 거절한다")
	check(not Rite.valid("orbit") and not Rite.valid(null) and not Rite.valid({}), "배열이 아니면 거절한다")
	# 형이 없는 배열로 옮긴다 — 정수 배열에는 「정수가 아닌 칸」을 넣어 볼 수가 없다.
	var broken: Array = []
	broken.assign(good)
	broken[2] = Rite.slots()
	check(not Rite.valid(broken), "칸 번호가 궤도를 넘으면 거절한다")
	broken[2] = -1
	check(not Rite.valid(broken), "음수 칸은 거절한다")
	broken[2] = 1.5
	check(not Rite.valid(broken), "정수가 아닌 칸은 거절한다")
	if Rite.gate(0) < Rite.slots():
		broken.assign(good)
		broken[0] = Rite.gate(0)
		check(not Rite.valid(broken), "붙들린 별이 문 밖에 서 있으면 거절한다 — 규칙으로는 못 만드는 상태다")
	for stars in range(1, 6):
		check(Rite.stars(Fixture.orbit_for(stars)) == stars and Rite.valid(Fixture.orbit_for(stars)),
				"검사용 자리가 정확히 %d성이다" % stars)


func _check_odds_shape() -> void:
	var last_mean := 0.0
	for spin_count in range(1, 13):
		var odds := Rite.odds(spin_count)
		check(odds.size() == Rite.RINGS + 1, "확률표는 0성부터 5성까지 여섯 칸이다")
		var total := 0.0
		var mean := 0.0
		for stars in range(odds.size()):
			check(odds[stars] >= 0.0 and odds[stars] <= 1.0, "확률은 0과 1 사이다")
			total += odds[stars]
			mean += odds[stars] * stars
		check(is_equal_approx(total, 1.0), "확률의 합은 1이다 (%d번 돌림)" % spin_count)
		check(is_zero_approx(odds[0]), "0성은 없다 — 붙들린 별이 있다")
		check(mean > last_mean, "더 돌리면 기대 별 수가 오른다 (%d번)" % spin_count)
		last_mean = mean
	check(Rite.odds(0) == Rite.odds(1) and Rite.odds(-3) == Rite.odds(1), "돌린 횟수는 적어도 한 번으로 센다")
	# 한 번 돌렸을 때의 5성은 문 넷에 다 드는 것이다.
	var all_in := 1.0
	for ring in range(Rite.RINGS):
		all_in *= Rite.chance(ring)
	check(is_equal_approx(Rite.odds(1)[Rite.MAX_STARS], all_in), "한 번에 5성일 확률은 문 확률의 곱이다")


## 실제 규칙 함수로 굴려서 odds() 와 맞춘다. 돌려주는 것은 굴린 판 수.
func _check_odds_by_rolling(respins: int, rounds: int) -> int:
	var counts := [0, 0, 0, 0, 0, 0]
	for i in range(rounds):
		var orbit := Rite.roll(_rng)
		for r in range(respins):
			Rite.respin(orbit, _rng)
		counts[Rite.stars(orbit)] += 1
	var odds := Rite.odds(1 + respins)
	var shown := PackedStringArray()
	for stars in range(1, 6):
		var want: float = odds[stars]
		var got := float(counts[stars]) / float(rounds)
		# 다섯 표준편차 — 씨앗이 고정이라 흔들리지 않지만, 문 너비를 다시 잡아도 살아남게 넉넉히.
		var slack := 5.0 * sqrt(want * (1.0 - want) / float(rounds)) + 0.0005
		check(absf(got - want) <= slack,
				"다시 돌리기 %d번 · %d성 비율 %.3f%% (표는 %.3f%%)" % [respins, stars, got * 100.0, want * 100.0])
		shown.append("%d성 %.1f%%" % [stars, got * 100.0])
	check(counts[0] == 0, "0성은 한 번도 안 나온다")
	print("  다시 돌리기 %d번: %s" % [respins, " · ".join(shown)])
	return rounds


func _check_respin() -> void:
	for i in range(4000):
		var orbit := Rite.roll(_rng)
		check(Rite.valid(orbit) and Rite.in_gate(0, orbit[0]), "굴린 자리는 언제나 쓸 수 있는 꼴이다")
		var before: Array[int] = orbit.duplicate()
		var missed := Rite.misses(orbit)
		var moved := Rite.respin(orbit, _rng)
		check(moved == missed, "다시 도는 것은 문 밖의 별 전부다")
		for ring in range(Rite.RINGS):
			if not moved.has(ring):
				check(orbit[ring] == before[ring], "문 안의 별은 제자리다")
		check(Rite.stars(orbit) >= Rite.stars(before), "다시 돌려서 별이 줄어드는 일은 없다")
		check(not moved.has(0), "붙들린 별은 다시 돌지 않는다")
	var full := Fixture.orbit_for(5)
	var snapshot: Array[int] = full.duplicate()
	check(Rite.respin(full, _rng).is_empty() and full == snapshot, "다 든 5성은 다시 돌 것이 없다")


func _check_pull() -> void:
	for stars in range(1, 5):
		var orbit := Fixture.orbit_for(stars)
		var target := Rite.pull_target(orbit)
		check(target == Rite.RINGS - 1, "끌어올 별은 가장 바깥 별이다 (%d성에서)" % stars)
		Rite.pull(orbit, target, _rng)
		check(Rite.in_gate(target, orbit[target]) and Rite.stars(orbit) == stars + 1 and Rite.valid(orbit),
				"끌어온 별은 문 안에 서고 별이 하나 는다")
	# 안쪽 별부터 채운다 — 판의 첫 의식이 쓰는 보정이다.
	for have in range(1, 6):
		for want in range(0, 7):
			var start := Fixture.orbit_for(have)
			var orbit: Array[int] = start.duplicate()
			Rite.ensure_stars(orbit, want, _rng)
			check(Rite.stars(orbit) == clampi(want, have, Rite.MAX_STARS) and Rite.valid(orbit),
					"%d성에서 %d성 보장" % [have, want])
			for ring in range(Rite.RINGS):
				check(Rite.in_gate(ring, orbit[ring]) == (ring < Rite.stars(orbit)), "보정은 안쪽 별부터 세운다")
				if ring < have:
					check(orbit[ring] == start[ring], "이미 든 별은 건드리지 않는다")
	var full := Fixture.orbit_for(5)
	check(Rite.pull_target(full) == -1, "다 들었으면 끌어올 별이 없다")
	var same: Array[int] = full.duplicate()
	Rite.pull(full, -1, _rng)
	Rite.pull(full, Rite.RINGS, _rng)
	check(full == same, "없는 궤도를 끌어오면 아무 일도 없다")


## 보이는 문 = 판정. 문 안의 칸만 문의 호 안에 놓인다.
func _check_angles() -> void:
	for ring in range(Rite.RINGS):
		var half := Rite.gate_half(ring)
		check(half > 0.0 and half <= PI + 0.0001, "문의 반각이 반 바퀴를 안 넘는다")
		check(is_equal_approx(half * 2.0, TAU * Rite.chance(ring)) or Rite.anchored(ring),
				"문의 호가 한 바퀴에서 차지하는 몫이 곧 확률이다: %d번" % ring)
		var last := -INF
		for pos in range(Rite.slots()):
			var a := Rite.angle(ring, pos)
			check(a > last, "칸은 한쪽으로만 돌며 놓인다")
			last = a
			var off := absf(a - Rite.GATE_ANGLE)
			if Rite.in_gate(ring, pos):
				check(off < half, "문 안의 칸은 문의 호 안에 그려진다: %d번 %d칸" % [ring, pos])
			else:
				check(off > half and a - Rite.GATE_ANGLE < TAU - half,
						"문 밖의 칸은 문의 호 밖에 그려진다: %d번 %d칸" % [ring, pos])
		check(Rite.angle(ring, Rite.slots() - 1) - Rite.angle(ring, 0) < TAU, "한 바퀴를 넘겨 겹치지 않는다")


## 판의 첫 의식만 별 둘을 세운 채로 열린다. 2탄부터는 굴린 그대로다.
func _check_first_rite() -> void:
	var low_later := 0
	for i in range(300):
		Run.start_run(20263000 + i)
		Run.begin_draw()
		check(Run.wave == 1 and Run.rite_stars() >= Balance.RITE_FIRST_STARS and Rite.valid(Run.orbit),
				"판의 첫 의식은 %d성 이상으로 열린다" % Balance.RITE_FIRST_STARS)
		check(Run.spins == 0 and Run.paid_spins == 0 and Run.respins_left() == Run.free_rerolls(),
				"첫 의식의 보정은 다시 돌리기 횟수를 쓰지 않는다")
		Run.confirm_summon()
		Run.begin_draw()
		if Run.rite_stars() < Balance.RITE_FIRST_STARS:
			low_later += 1
	check(low_later > 0, "2탄부터는 보정이 없다 — 1성으로 열리는 의식이 나온다 (%d번)" % low_later)


## 문 안의 별 수가 그대로 등급이 되고, 영웅 한 장이 그 등급을 갖는다.
func _check_summon() -> void:
	for stars in range(1, 6):
		Fixture.fresh(20261007 + stars)
		Fixture.stack(stars)
		check(Run.rite_stars() == stars, "판이 문 안의 별을 %d개로 센다" % stars)
		var preview := Run.rite_preview()
		check(int(preview["stars"]) == stars and int(preview["tier"]) == Rite.tier_of(stars) and int(preview["joker"]) == -1,
				"조커가 없으면 미리보기는 지금 별 수 그대로다")
		var result := Run.confirm_summon()
		check(int(result["stars"]) == stars and int(result["tier"]) == Rite.tier_of(stars), "%d성이 등급 %d 이 된다" % [stars, Rite.tier_of(stars)])
		check(bool(result["showy"]) == (int(result["tier"]) >= Balance.SHOWY_TIER), "화려한 연출의 경계")
		check(Run.phase == Run.Phase.SWAP and Run.heroes.size() == 1, "확정하면 영웅 한 명을 받고 편성 단계가 된다")
		var hero: Dictionary = Run.heroes[0]
		check(int(hero["tier"]) == Rite.tier_of(stars) and hero["unit"] == result["unit"], "영웅 한 장이 그 등급을 갖는다")
		check(not hero.has("value") and not hero.has("variant"), "포커 문장 값은 더 이상 붙지 않는다")
		check(Run.confirm_summon() == result and Run.heroes.size() == 1, "두 번 확정해도 영웅은 한 명이다")
		check(Save.best_of(String(hero["unit"]["id"])) >= Rite.tier_of(stars), "도감이 그 캐릭터의 최고 등급을 기억한다")
	# 같은 캐릭터라도 등급이 세기를 정한다 — 캐릭터 표의 원화 격은 능력치와 무관하다.
	Fixture.fresh(20261099)
	for unit in [Roster.UNITS[0], Roster.UNITS[Roster.UNITS.size() - 1]]:
		var last_dps := 0.0
		for tier in range(Balance.TIER_MAX + 1):
			var dps := Run.hero_dps({"unit": unit, "tier": tier, "wave": 1, "n": 1})
			check(dps > last_dps, "%s 는 등급이 오를수록 세다 (%d)" % [unit["id"], tier])
			last_dps = dps
	# 원화 격만 다른 쌍둥이를 만들어 본다. 능력치가 한 톨이라도 다르면 표의 tier 가 새고 있다.
	for unit in Roster.UNITS:
		var twin: Dictionary = unit.duplicate(true)
		twin["tier"] = Balance.TIER_MAX - int(unit["tier"])
		for tier in [1, 5, 9]:
			check(Run.hero_stats({"unit": unit, "tier": tier, "n": 1}) == Run.hero_stats({"unit": twin, "tier": tier, "n": 1}),
					"%s 의 능력치는 원화 격과 무관하다 (등급 %d)" % [unit["id"], tier])


func _check_passives() -> void:
	# 조커: 문 밖의 가장 바깥 별 하나를 끌어온다. 정확히 +1성이고, 5성에서는 아무 일도 없다.
	for stars in range(1, 6):
		Fixture.fresh(20261200 + stars)
		Run.owned_passives.assign(["joker"])
		Run.passives.assign(["joker"])
		Fixture.stack(stars)
		var preview := Run.rite_preview()
		var result := Run.confirm_summon()
		if stars < 5:
			check(int(preview["stars"]) == stars + 1 and int(preview["joker"]) == Rite.RINGS - 1,
					"조커 미리보기는 끌어올 별까지 센다 (%d성)" % stars)
			check(int(result["stars"]) == stars + 1 and int(result["joker"]) == Rite.RINGS - 1
					and int(result["tier"]) == Rite.tier_of(stars + 1), "조커는 정확히 한 별을 더한다 (%d성)" % stars)
			check(Rite.in_gate(Rite.RINGS - 1, int(result["orbit"][Rite.RINGS - 1])), "조커가 끌어온 별이 문 안에 서 있다")
		else:
			check(int(preview["joker"]) == -1 and int(result["joker"]) == -1 and int(result["stars"]) == 5,
					"5성에서는 조커가 끌어올 별이 없다")
		check(Rite.stars(result["orbit"]) == int(result["stars"]), "결과의 별 자리와 별 수가 같은 말을 한다")
	# 도박꾼의 눈: 확률로 반 별. 의식의 온 별 위에만 얹히고 5성을 넘지 않는다.
	var bumped := 0
	var rounds := 600
	for i in range(rounds):
		Fixture.fresh(20261300 + i)
		Run.owned_passives.assign(["eye"])
		Run.passives.assign(["eye"])
		var stars := 1 + i % 5
		Fixture.stack(stars)
		var result := Run.confirm_summon()
		var base := Rite.tier_of(stars)
		if bool(result["bumped"]):
			bumped += 1
			check(int(result["tier"]) == base + 1 and stars < 5, "눈은 정확히 반 별을 얹고 5성에는 안 얹는다")
		else:
			check(int(result["tier"]) == base, "눈이 안 뜨면 등급은 별 수 그대로다")
		check(int(result["stars"]) == stars and int(result["tier"]) <= Balance.TIER_MAX, "눈은 문 안의 별 수를 바꾸지 않는다")
	# 5성(다섯 판에 한 판)에서는 굴리지 않으므로 기대 비율은 0.8 x 확률이다.
	var want := 0.8 * Balance.PASSIVE_EYE_P
	var slack := 5.0 * sqrt(want * (1.0 - want) / float(rounds))
	check(absf(float(bumped) / float(rounds) - want) <= slack,
			"도박꾼의 눈이 뜨는 비율 %.1f%% (기대 %.1f%%)" % [float(bumped) * 100.0 / rounds, want * 100.0])


## 쉰 명 누구든 어느 등급으로든 나온다 — 캐릭터와 등급은 서로 상관이 없다.
func _check_anyone_any_star() -> void:
	var rounds := 20000
	var counts := {}
	for i in range(rounds):
		var unit := Roster.pick_unit(_rng)
		counts[unit["id"]] = int(counts.get(unit["id"], 0)) + 1
	check(counts.size() == Roster.UNITS.size(), "뽑기에 쉰 명이 전부 나온다 (%d명)" % counts.size())
	var want := float(rounds) / float(Roster.UNITS.size())
	var slack := 5.0 * sqrt(want * (1.0 - 1.0 / Roster.UNITS.size()))
	for id in counts:
		check(absf(float(counts[id]) - want) <= slack, "%s 가 고르게 나온다 (%d번)" % [id, counts[id]])
		check(not bool(Roster.unit_by_id(String(id)).get("fusion_only", false)), "합성 전용 수호자는 뽑기에 안 나온다")
	# 실제 판에서: 캐릭터마다 여러 등급으로 받아진다.
	var tiers_by_unit := {}
	for i in range(400):
		Fixture.fresh(20262000 + i)
		Fixture.stack(1 + i % 5)
		var result := Run.confirm_summon()
		var id := String(result["unit"]["id"])
		if not tiers_by_unit.has(id):
			tiers_by_unit[id] = {}
		tiers_by_unit[id][int(result["tier"])] = true
	var many := 0
	for id in tiers_by_unit:
		if tiers_by_unit[id].size() >= 2:
			many += 1
	check(many >= Roster.UNITS.size() / 2, "같은 캐릭터가 여러 등급으로 나온다 (%d명이 둘 이상의 등급)" % many)
