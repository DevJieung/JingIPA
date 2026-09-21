extends Harness

var main: Node2D

func click_screen(id: String) -> bool:
	await paint(main.screen)
	return tap(main.screen, id)

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
	Run.phase = Run.Phase.DRAW
	Run.rerolled.assign([Run.free_rerolls(), 0, 0, 0, 0])
	main.show_draw()
	Run.gold = Run.reroll_cost_of(0)
	await paint(main.screen)
	check(bool(zone_of(main.screen, "want:0").get("on", false)), "direct card choice available beside paid redraw")
	var previous: int = Run.cards[0]
	check(await click_screen("re0"), "paid replacement remains reachable")
	check(Run.gold == 0 and Run.cards[0] != previous, "paid replacement spends the last gold and changes the card")
	for slot in range(1, 5):
		for attempt in range(Run.free_rerolls()):
			check(await click_screen("re%d" % slot), "remaining free replacements work without gold")
	await paint(main.screen)
	var before := Run.cards.duplicate()
	for slot in range(5):
		check(bool(zone_of(main.screen, "want:%d" % slot).get("on", false)), "direct card choice available with no gold")
		check(not tap(main.screen, "re%d" % slot), "unaffordable replacement button stays disabled")
	check(await click_screen("want:0"), "open direct card choice without gold")
	check(main.screen.card_choice.opened and Run.cards == before and not Ads.busy, "opening choice does not request ad or change cards")
	main.menu.open()
	check(not main.menu.opened, "card choice blocks menu opening")
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not main.menu.opened and not main.screen.card_choice.opened, "Android back closes only card choice")
	main.menu.open()
	check(main.menu.opened, "exhausted draw leaves menu available")
	main.menu.close()
	check(await click_screen("go"), "hand confirmation remains reachable with no replacements left")
	check(Run.phase == Run.Phase.SWAP, "exhausted draw still advances to formation")
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
