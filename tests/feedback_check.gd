extends Harness

var main: Node2D

func click_screen(id: String) -> bool:
	await paint(main.screen)
	return tap(main.screen, id)


## 문 밖에 별 넷을 다시 세운다(횟수는 그대로). 다시 돌리다 우연히 다 들어 버리면 단추가 꺼져서
## 「골드 때문에 꺼졌는가」를 잴 수 없게 된다.
func scatter() -> void:
	Run.orbit.assign(Fixture.orbit_for(1))

func _ready() -> void:
	if not require_no_save():
		return
	main = load("res://game/main.gd").new()
	add_child(main)
	Fixture.fresh(14092026, 6)
	Run.phase = Run.Phase.SHOP
	main.go_shop()
	for tab in ["u", "p", "c", "f"]:
		main.screen.tab = tab
		check(await click_screen("tab:h"), "fusion opener reachable from " + tab)
		check(main.screen.fusion.opened and main.screen.tab == tab, "fusion preserves underlying tab " + tab)
		main.menu.open()
		check(not main.menu.opened, "fusion blocks direct menu opening")
		main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
		check(not main.menu.opened, "fusion blocks Android back opening menu")
		await paint(main.menu)
		var menu_zone := zone_of(main.menu, "menu")
		check(not menu_zone.is_empty() and not bool(menu_zone.get("on", true)), "modal disables the current menu button")
		if not menu_zone.is_empty():
			check(main.menu.ui.hit(Rect2(menu_zone["rect"]).get_center()) != "menu", "disabled menu has no active hit target")
		check(await click_screen("fusion:close"), "fusion close reachable")
		check(not main.screen.fusion.opened and main.screen.tab == tab, "closing fusion restores " + tab)
	# --- 별맞춤 의식: 무료 → 유료 → 골드가 바닥난 뒤에도 소환과 별 끌어오기는 남는다 ---
	# (단추 id 는 화면과의 약속이다: 소환 `go` · 다시 돌리기 `rite:respin` · 별 끌어오기 `rite:pull`)
	Run.phase = Run.Phase.DRAW
	Fixture.stack(1)            # 문 밖에 별 넷 · 돌린 횟수 0
	Run.gold = 0
	main.show_draw()
	await paint(main.screen)
	check(main.screen.state == DrawScreen.PICK, "the rite opens on its pick state")
	# 무료 횟수는 골드가 없어도 눌린다.
	for attempt in range(Run.free_rerolls()):
		scatter()
		check(await click_screen("rite:respin"), "free re-spins work without gold")
	check(Run.spins == Run.free_rerolls() and Run.paid_spins == 0 and Run.gold == 0 and Run.respins_left() == 0,
			"free re-spins take no gold and use up the allowance")
	# 무료를 다 쓰면 값이 붙는다 — 골드가 없으면 단추가 꺼지고, 마지막 골드까지는 쓸 수 있다.
	scatter()
	await paint(main.screen)
	check(not tap(main.screen, "rite:respin") and Run.spins == Run.free_rerolls(), "paid re-spin button is disabled without gold")
	Run.gold = Run.respin_cost()
	check(Run.gold == Balance.reroll_cost(0) and Run.gold > 0, "the first paid re-spin has a price")
	# 문 안에 별 둘(붙들린 0번과, 제 힘으로 든 1번)을 세워 두고 돌린다 — 둘 다 잠겨 있어야 한다.
	Run.orbit.assign(Fixture.orbit_for(2))
	await paint(main.screen)
	var locked: Array[int] = Run.orbit.duplicate()
	check(await click_screen("rite:respin"), "paid re-spin remains reachable")
	check(Run.gold == 0 and Run.paid_spins == 1 and Run.spins == Run.free_rerolls() + 1
			and Run.orbit[0] == locked[0] and Run.orbit[1] == locked[1] and Run.rite_stars() >= 2,
			"paid re-spin spends the last gold and leaves the stars inside the gate alone")
	scatter()
	await paint(main.screen)
	check(not tap(main.screen, "rite:respin"), "unaffordable re-spin button stays disabled")
	main.menu.open()
	check(main.menu.opened, "exhausted rite leaves menu available")
	main.menu.close()
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(main.menu.opened, "Android back opens the menu on the rite")
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not main.menu.opened and main.screen.state == DrawScreen.PICK and Run.phase == Run.Phase.DRAW,
			"Android back closes the menu and leaves the rite open")
	# 다 든 5성에서는 돌릴 것도 끌어올 것도 없다 — 두 단추가 다 꺼지고 소환만 남는다.
	Run.gold = 100000
	Run.orbit.assign(Fixture.orbit_for(Rite.MAX_STARS))
	await paint(main.screen)
	check(not tap(main.screen, "rite:respin") and Run.gold == 100000,
			"with five stars in the gate re-spin cannot be tapped")
	Run.gold = 0
	scatter()
	check(await click_screen("go"), "summon remains reachable with no re-spins left")
	check(Run.phase == Run.Phase.SWAP and Run.hero_total() == 7, "exhausted rite still summons one hero and advances to formation")
	main.show_draw()
	main.screen.formation_tab = false
	check(await click_screen("formation:fusion"), "draw hall fusion reachable")
	check(await click_screen("fusion:close"), "draw fusion closes")
	check(not main.screen.formation_tab, "draw hall tab survives closing fusion")
	main.menu.open()
	check(main.menu.opened, "menu works again once modal is closed")
	main.menu.close()
	# Exercise actual damage application, with passive modifications disabled.
	Fixture.fresh(14092026, 1)
	Run.phase = Run.Phase.BATTLE
	var sim := BattleSim.new()
	sim.setup(Run, Run.wave)
	sim.monsters.clear()
	for body in ["wood", "rock"]:
		var unit: Dictionary = {}
		for monster in Roster.MONSTERS:
			if monster.get("body") == body:
				unit = monster
				break
		sim._spawn(unit)
		var i := sim.monsters.size() - 1
		sim.monsters[i]["hp"] = 1000.0
		sim._cache_positions()
		var mult := sim._hurt(i, 100.0, false, 0, "elec", false)
		check(is_equal_approx(mult, .5 if body == "wood" else 0.0), "actual electric multiplier: " + body)
		check(is_equal_approx(sim.monsters[i]["hp"], 950.0 if body == "wood" else 1000.0), "actual electric HP loss: " + body)
	main.queue_free()
	await frames(2)
	finish("사용자 피드백 동작 회귀 검사")
