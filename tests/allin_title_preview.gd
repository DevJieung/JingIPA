extends Harness

var main: Node2D
var output := "build/allin-title/1280x800"

func capture(stem: String) -> void:
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	await snap(output + "/" + stem + ".png")
	check(I18n.missing.is_empty(), "localized copy at " + stem)
	var ko := zone_of(main.menu, "language:ko")
	var en := zone_of(main.menu, "language:en")
	check(not ko.is_empty() and not en.is_empty(), "both language choices are always visible")
	if not ko.is_empty() and not en.is_empty():
		check(not Rect2(ko["rect"]).intersects(en["rect"]), "language targets are separate")
		check(is_equal_approx(Rect2(en["rect"]).end.x, 1264), "language respects right safe margin")
		for zone in main.screen.ui.zones:
			var r: Rect2 = zone["rect"]
			if r.size.x < 1200 and bool(zone["on"]):
				check(not r.intersects(ko["rect"]) and not r.intersects(en["rect"]), "language avoids " + String(zone["id"]))

func check_language() -> void:
	for code in ["en", "ko"]:
		check(tap(main.menu, "language:" + code), "explicit language target works")
		check(I18n.locale == code, "explicit language target selects requested code")
		check(tap(main.menu, "language:" + code), "current language remains selectable")
		check(I18n.locale == code, "current language tap does not toggle away")
		await paint(main.menu)

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
		Save.best_wave = 100
		Save.best_hand = 9
		for unit in Roster.UNITS:
			Save.seen_units[String(unit["id"])] = true
		Save.cur_run = {}
		main.show_title()
		main.screen.set_process(false)
		await capture(language + "_title_new")
		check(I18n.t("올인 디펜스") == ("All-in Defense" if language == "en" else "올인 디펜스"), "localized title matches brand")
		check(Art.has(String(Roster.ART["title_art"])), "new title art is imported")
		Save.cur_run = {"wave": 99}
		await capture(language + "_title_continue")
		await check_language()
		I18n.set_locale(language)
		main.screen.collection.opened = true
		await capture(language + "_collection")
		await check_language()
		I18n.set_locale(language)
		main.screen.collection.close()
		Fixture.prepare(40, 20092026)
		Run.phase = Run.Phase.SHOP
		Run.gold = 1000000
		var shop := ShopScreen.new()
		main._swap(shop)
		shop.set_process(false)
		I18n.observed.clear()
		await capture(language + "_upgrades_middle")
		for label in I18n.observed:
			check(not String(label).begins_with("Lv "), "upgrade rows omit all level labels")
		for u in Balance.UPGRADES:
			Run.levels[String(u["id"])] = int(u["cap"]) if int(u["cap"]) > 0 else 0
		await capture(language + "_upgrades_max")
		shop.fusion.opened = true
		await capture(language + "_fusion")
		await check_language()
		I18n.set_locale(language)
		shop.fusion.opened = false
		Run.prepare_battle()
		var battle := BattleScreen.new()
		main._swap(battle)
		battle.set_process(false)
		await capture(language + "_battle")
		var menu_rect: Rect2 = zone_of(main.menu, "menu")["rect"]
		for speed in [1, 2, 3]:
			check(not menu_rect.intersects(zone_of(battle, "sp%d" % speed)["rect"]), "speed avoids menu")
			check(tap(battle, "sp%d" % speed), "speed remains reachable")
		await check_language()
		I18n.set_locale(language)
		main.menu.open()
		await capture(language + "_menu")
		await check_language()
		main.menu.close()
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("All-in title and language review")
