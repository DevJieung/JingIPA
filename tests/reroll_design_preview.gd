extends Harness

var main: Node2D
var output := "build/reroll-design/1280x800"


func capture(stem: String) -> void:
	I18n.observed.clear()
	I18n._cache.clear()
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	await snap(output + "/" + stem + ".png")
	check(I18n.missing.is_empty(), "localized text: " + stem)


func setup_draw(level: int, active: bool) -> DrawScreen:
	Fixture.fresh(20092026)
	Fixture.stack(2)
	Run.levels["reroll"] = level
	Run.gold = 1000
	Run.owned_passives.assign(["deal"])
	Run.passives.assign(["deal"] if active else [])
	var draw := DrawScreen.new()
	main._swap(draw)
	draw.set_process(false)
	return draw


func check_actions(draw: DrawScreen) -> void:
	var actions: Array[Rect2] = []
	for zone in draw.ui.zones:
		var id := String(zone["id"])
		var rect: Rect2 = zone["rect"]
		if id.begins_with("re") or id.begins_with("want:") or id == "go":
			check(Look.SCREEN.encloses(rect), "action inside screen: " + id)
			for other in actions:
				check(not other.intersects(rect), "redraw, card and ad targets never overlap")
			actions.append(rect)
	for slot in range(5):
		check(bool(zone_of(draw, "re%d" % slot)["on"]) == Run.can_reroll(slot), "card action follows true affordability")
		check(not zone_of(draw, "want:%d" % slot).is_empty(), "reward action is retained")
	for label in I18n.observed:
		check(not String(label).begins_with("교체 (무료"), "compact action has no parenthesized quota")


func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly = true
	output = arg("--out", output)
	DirAccess.make_dir_recursive_absolute(output)
	main = load("res://game/main.gd").new()
	add_child(main)
	I18n.audit_enabled = true
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		Run.running = false
		Save.cur_run = {}
		main.show_title()
		main.screen.set_process(false)
		await capture(language + "_title")
		for state in [[0, false, "basic", 1], [3, false, "inactive", 4], [3, true, "active", 6], [4, true, "max", 7]]:
			var draw := setup_draw(int(state[0]), bool(state[1]))
			check(Run.free_rerolls() == int(state[3]), "expected actual free count: " + String(state[2]))
			await capture(language + "_draw_" + String(state[2]))
			check_actions(draw)
			Run.phase = Run.Phase.SHOP
			var shop := ShopScreen.new()
			main._swap(shop)
			shop.set_process(false)
			await capture(language + "_shop_" + String(state[2]))
			check(I18n.observed.has("%d번" % Run.free_rerolls()), "shop renders true total including active passive")
			if not Balance.upgrade_maxed("reroll", Run.lv("reroll")):
				check(I18n.observed.has("%d번" % Run.free_rerolls_at(Run.lv("reroll") + 1)), "shop next count preserves active passive")
		var mixed := setup_draw(3, true)
		Run.rerolled.assign([0, 2, 5, 6, 7])
		Run.paid.assign([0, 0, 0, 0, 1])
		await capture(language + "_draw_mixed")
		check_actions(mixed)
		Run.rerolled.assign([6, 6, 6, 6, 6])
		Run.paid.assign([0, 0, 0, 0, 0])
		await capture(language + "_draw_paid")
		check_actions(mixed)
		check(Run.reroll_cost_of(0) == 15, "first paid price is shown correctly")
		Run.gold = 0
		await capture(language + "_draw_no_gold")
		check_actions(mixed)
		check(not tap(mixed, "re0"), "unaffordable card cannot be redrawn")
		var clicked := setup_draw(3, true)
		await paint(clicked)
		var old_gold := Run.gold
		# The visible button is the last duplicate target; tap its real center.
		for zone in clicked.ui.zones:
			if String(zone["id"]) == "re0" and Rect2(zone["rect"]).size.y == 48:
				mouse(clicked, Rect2(zone["rect"]).get_center(), true)
		check(Run.rerolls_left(0) == 5 and Run.gold == old_gold, "separate action consumes one free redraw without gold")
		clicked._flip.fill(0.0)
		await capture(language + "_draw_after_click")
		Fixture.fresh(20092026)
		var brasa := Roster.unit_by_id("brasa")
		Run.gain_hero(brasa, int(brasa["tier"]))
		Run.phase = Run.Phase.SHOP
		var detail := ShopScreen.new()
		main._swap(detail)
		detail.set_process(false)
		detail.tab = "f"
		detail.hero_info_tab = true
		detail.hv.info = 0
		await capture(language + "_brasa_detail")
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Reroll quota and repaired portrait review")
