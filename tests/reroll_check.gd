extends Harness

## 능력치 표시 기준값과 실제 카드별 무료 교체·구매·저장 복구를 함께 검증한다.
func _ready() -> void:
	if not require_no_save():
		return
	for level in range(5):
		for passive_state in ["absent", "inactive", "active"]:
			_check_allowance(level, passive_state)
	_check_passive_toggle()
	finish("무료 교체 횟수 회귀 검사")


func _check_allowance(level: int, passive_state: String) -> void:
	Fixture.fresh(20092026 + level)
	Run.levels["reroll"] = level
	if passive_state != "absent":
		Run.owned_passives.assign(["deal"])
	if passive_state == "active":
		Run.passives.assign(["deal"])
	var expected := 1 + level + (2 if passive_state == "active" else 0)
	var label := "level %d / %s" % [level, passive_state]
	check(Run.free_rerolls_at(level) == expected, "shop allowance: " + label)
	check(Run.stat_now("reroll") == expected, "current effective stat: " + label)
	check(Run.rerolls_left(-1) == 0 and Run.rerolls_left(5) == 0, "invalid slots have no allowance")
	Run.gold = 0
	for slot in range(5):
		for used in range(expected):
			check(Run.rerolls_left(slot) == expected - used, "remaining before replacement: " + label)
			check(Run.reroll_cost_of(slot) == 0 and Run.reroll(slot), "displayed allowance works without gold: " + label)
			check(Run.gold == 0 and Run.paid[slot] == 0, "free replacement never charges gold")
			if slot < 4:
				check(Run.rerolls_left(slot + 1) == expected, "each card has an independent allowance")
		check(Run.rerolls_left(slot) == 0 and not Run.can_reroll(slot), "exhausted card is blocked without gold")
		check(Run.reroll_cost_of(slot) == 15, "first paid replacement costs 15 G")
		Run.gold = 15
		check(Run.reroll(slot) and Run.gold == 0, "first paid replacement spends exact cost")
		check(Run.rerolls_left(slot) == 0 and Run.reroll_cost_of(slot) == 30, "paid replacement preserves zero remaining")
	var saved := Run.snapshot().duplicate(true)
	check(Run.restore(saved), "consumed allowance survives restore: " + label)
	for slot in range(5):
		check(Run.rerolls_left(slot) == 0 and Run.reroll_cost_of(slot) == 30, "restore retains each card's usage and price")
	Run.confirm_hand()
	Run.phase = Run.Phase.SHOP
	Run.gold = 100000
	var before := Run.snapshot().duplicate(true)
	var next := Run.free_rerolls_at(level + 1)
	check(Run.snapshot() == before, "preview does not modify level or save")
	if level < 4:
		check(Run.buy_upgrade("reroll"), "buy the previewed next level")
		check(Run.free_rerolls() == next and next == expected + 1, "next stat matches purchased allowance")
	else:
		check(not Run.buy_upgrade("reroll") and Run.lv("reroll") == 4, "passive bonus does not change upgrade cap")
	Run.begin_draw()
	for slot in range(5):
		check(Run.rerolls_left(slot) == Run.free_rerolls() and Run.paid[slot] == 0, "next round refreshes all five allowances")


func _check_passive_toggle() -> void:
	Fixture.fresh(20092026)
	Run.levels["reroll"] = 3
	Run.owned_passives.assign(["deal"])
	Run.confirm_hand()
	Run.phase = Run.Phase.SHOP
	check(Run.free_rerolls_at(3) == 4 and Run.free_rerolls_at(4) == 5, "owned inactive Big Deal has no effect")
	check(Run.toggle_passive("deal"), "activate owned Big Deal")
	check(Run.free_rerolls_at(3) == 6 and Run.free_rerolls_at(4) == 7, "active Big Deal applies to current and next")
	check(Run.restore(Run.snapshot()) and Run.free_rerolls() == 6, "restored passive retains six replacements")
	check(Run.toggle_passive("deal") and Run.free_rerolls() == 4, "deactivation updates allowance immediately")
	check(Run.toggle_passive("deal"), "reactivate before the next draw")
	Run.begin_draw()
	for slot in range(5):
		check(Run.rerolls_left(slot) == 6, "new poker hand matches camp's displayed six replacements")
