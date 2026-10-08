extends Harness

## 상점이 적어 주는 「무료 다시 돌리기」 횟수와 의식이 실제로 주는 횟수가 같은지,
## 다 쓴 뒤의 유료 값·저장 복구·구매·다음 탄의 새 횟수까지 함께 검증한다.
##
## ★ 숫자는 전부 Balance 에서 읽는다(기본 횟수 · 강화 상한 · 큰손 · 유료 값). 밸런스를
##   다시 잡아도 이 검사는 「표시와 실제가 같은가」만 묻는다.
func _ready() -> void:
	if not require_no_save():
		return
	var cap := int(Balance.upgrade_by_id("reroll")["cap"])
	for level in range(cap + 1):
		for passive_state in ["absent", "inactive", "active"]:
			_check_allowance(level, passive_state, cap)
	_check_passive_toggle(cap)
	finish("무료 다시 돌리기 회귀 검사")


## 문 밖에 별 넷을 다시 세운다. 다시 돌리다 우연히 다 들어 버리면 횟수를 끝까지 못 세기 때문이다.
## 횟수(spins · paid_spins)는 건드리지 않는다.
func _scatter() -> void:
	Run.orbit.assign(Fixture.orbit_for(1))


func _check_allowance(level: int, passive_state: String, cap: int) -> void:
	Fixture.fresh(20092026 + level)
	Run.levels["reroll"] = level
	if passive_state != "absent":
		Run.owned_passives.assign(["deal"])
	if passive_state == "active":
		Run.passives.assign(["deal"])
	var expected := Balance.FREE_REROLL + level + (Balance.PASSIVE_DEAL if passive_state == "active" else 0)
	var label := "level %d / %s" % [level, passive_state]
	check(Run.free_rerolls_at(level) == expected, "shop allowance: " + label)
	check(Run.stat_now("reroll") == expected, "current effective stat: " + label)
	Run.gold = 0
	_scatter()
	for used in range(expected):
		check(Run.respins_left() == expected - used, "remaining before re-spin: " + label)
		check(Run.respin_cost() == 0 and Run.can_respin(), "displayed allowance works without gold: " + label)
		var moved := Run.respin()
		check(moved == [1, 2, 3, 4], "a re-spin turns every star outside the gate, never the anchored one")
		check(Run.gold == 0 and Run.paid_spins == 0 and Run.spins == used + 1, "free re-spin never charges gold")
		_scatter()
	check(Run.respins_left() == 0 and not Run.can_respin(), "exhausted allowance is blocked without gold")
	var first := Balance.reroll_cost(0)
	check(Run.respin_cost() == first and first > 0, "first paid re-spin costs the base price")
	var before_orbit: Array[int] = Run.orbit.duplicate()
	check(Run.respin().is_empty() and Run.spins == expected and Run.orbit == before_orbit, "a blocked re-spin changes nothing")
	Run.gold = first
	check(not Run.respin().is_empty() and Run.gold == 0, "first paid re-spin spends the exact cost")
	check(Run.paid_spins == 1 and Run.spins == expected + 1, "paid re-spin is counted once")
	check(Run.respins_left() == 0 and Run.respin_cost() == Balance.reroll_cost(1)
			and Balance.reroll_cost(1) == first * 2, "the price doubles after each paid re-spin")
	_scatter()
	Run.gold = Balance.reroll_cost(1) - 1
	check(not Run.can_respin(), "one gold short blocks the re-spin")
	# 다 들었으면 돌릴 것이 없다 — 골드를 받고 아무 일도 안 일어나면 안 된다.
	Run.orbit.assign(Fixture.orbit_for(5))
	Run.gold = 100000
	check(not Run.can_respin() and Run.respin().is_empty() and Run.gold == 100000 and Run.paid_spins == 1,
			"five stars in the gate: nothing to re-spin and no gold taken")
	_scatter()
	Run.gold = 0
	var revision := Run.rite_revision()
	var saved := Run.snapshot().duplicate(true)
	Run.begin_draw()
	check(Run.restore(saved), "consumed allowance survives restore: " + label)
	check(Run.respins_left() == 0 and Run.respin_cost() == Balance.reroll_cost(1) and Run.paid_spins == 1
			and Run.spins == expected + 1 and Run.rite_revision() == revision, "restore retains usage and price")
	check(Run.orbit == Fixture.orbit_for(1), "restore keeps every star where it stopped")
	Run.confirm_summon()
	Run.phase = Run.Phase.SHOP
	Run.gold = 100000
	var before := Run.snapshot().duplicate(true)
	var next := Run.free_rerolls_at(level + 1)
	check(Run.snapshot() == before, "preview does not modify level or save")
	if level < cap:
		check(Run.buy_upgrade("reroll"), "buy the previewed next level")
		check(Run.free_rerolls() == next and next == expected + 1, "next stat matches purchased allowance")
	else:
		check(not Run.buy_upgrade("reroll") and Run.lv("reroll") == cap, "passive bonus does not change upgrade cap")
	Run.begin_draw()
	check(Run.respins_left() == Run.free_rerolls() and Run.paid_spins == 0 and Run.spins == 0 and Run.pulls == 0,
			"next round refreshes the allowance and the price")


func _check_passive_toggle(cap: int) -> void:
	Fixture.fresh(20092026)
	var level := maxi(0, cap - 1)
	var base := Balance.FREE_REROLL
	Run.levels["reroll"] = level
	Run.owned_passives.assign(["deal"])
	Run.confirm_summon()
	Run.phase = Run.Phase.SHOP
	check(Run.free_rerolls_at(level) == base + level and Run.free_rerolls_at(level + 1) == base + level + 1,
			"owned inactive Big Deal has no effect")
	check(Run.toggle_passive("deal"), "activate owned Big Deal")
	check(Run.free_rerolls_at(level) == base + level + Balance.PASSIVE_DEAL
			and Run.free_rerolls_at(level + 1) == base + level + 1 + Balance.PASSIVE_DEAL,
			"active Big Deal applies to current and next")
	check(Run.restore(Run.snapshot()) and Run.free_rerolls() == base + level + Balance.PASSIVE_DEAL,
			"restored passive retains its extra re-spins")
	check(Run.toggle_passive("deal") and Run.free_rerolls() == base + level, "deactivation updates allowance immediately")
	check(Run.toggle_passive("deal"), "reactivate before the next rite")
	Run.begin_draw()
	check(Run.respins_left() == base + level + Balance.PASSIVE_DEAL,
			"the new rite matches the allowance the camp displayed")
