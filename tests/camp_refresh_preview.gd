extends Harness

var main: Node2D
var output := "build/camp-refresh/1280x800"

func capture(stem: String) -> void:
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	await snap(output + "/" + stem + ".png")
	if I18n.locale == "en":
		check(I18n.missing.is_empty(), "no untranslated copy at " + stem + ": " + str(I18n.missing))
	for zone in main.screen.ui.zones:
		check(Look.SCREEN.encloses(zone["rect"]), "action stays within screen: " + String(zone["id"]))

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
		Save.best_wave = 100
		Save.best_hand = 9
		Save.seen_units.clear()
		Save.cur_run = {}
		Run.running = false
		main.show_title()
		main.screen.set_process(false)
		await capture(language + "_title_empty")
		check(tap(main.screen, "collection"), "record box opens collection")
		await capture(language + "_collection_empty")
		check(main.screen_modal_open(), "collection blocks background menu")
		check(tap(main.menu, "language:en" if language == "ko" else "language:ko"), "language switches inside collection")
		check(I18n.locale != language, "language actually changed")
		I18n.set_locale(language)
		for unit in Roster.UNITS:
			Save.seen_units[String(unit["id"])] = true
		for element in CollectionView.ELEMENTS:
			main.screen.collection.element = element
			await capture(language + "_collection_" + element)
			var entries: Array = main.screen.collection.heroes()
			for index in range(1, entries.size()):
				check(int(entries[index - 1]["tier"]) >= int(entries[index]["tier"]), "collection descends by rarity")
		main.screen.collection.close()
		Save.cur_run = {"wave": 40}
		await capture(language + "_title_records")
		Fixture.prepare(40, 20092026)
		Run.phase = Run.Phase.SHOP
		Run.gold = 1000000
		var shop := ShopScreen.new()
		main._swap(shop)
		shop.set_process(false)
		await capture(language + "_upgrades")
		for u in Balance.UPGRADES:
			Run.levels[String(u["id"])] = int(u["cap"]) if int(u["cap"]) > 0 else 0
		await capture(language + "_upgrades_max")
		shop.tab = "p"
		Run.owned_passives.clear()
		Run.passives.clear()
		await capture(language + "_passives_empty")
		Run.owned_passives.clear()
		for index in range(8):
			Run.owned_passives.append(String(Balance.PASSIVES[index]["id"]))
		Run.passives.assign(Run.owned_passives.slice(0, 3))
		Run.roll_shop()
		await capture(language + "_passives_owned")
		var deactivated := Run.passives[0]
		check(tap(shop, "active:" + deactivated), "active passive can be deactivated")
		await capture(language + "_passives_two")
		check(Run.passives.size() == 2 and Run.owned_passives.has(deactivated), "deactivation preserves ownership")
		check(tap(shop, "active:" + deactivated), "owned passive can be activated")
		for p in Balance.PASSIVES:
			if not Run.owned_passives.has(String(p["id"])):
				Run.owned_passives.append(String(p["id"]))
		Run.shop_offer.clear()
		for page in range(ceili(Run.owned_passives.size() / 8.0)):
			shop.passive_page = page
			await capture(language + "_passives_all_%d" % page)
		shop.tab = "f"
		shop.formation.focus_latest()
		await capture(language + "_formation_new")
		check(shop.formation.selected == -1 and shop.formation.bench_selected == -1, "new hero is never automatically selected")
		shop.formation.selected = 0
		await capture(language + "_formation_selected")
		check(tap(shop, "post:bench"), "send selected field hero to hall")
		await capture(language + "_formation_returned")
		check(shop.formation.selected == -1 and shop.formation.bench_selected == -1, "return to hall clears selection")
		shop.formation.element = "water"
		if not shop.formation.visible_indices().is_empty():
			shop.formation.bench_selected = shop.formation.visible_indices()[0]
		await capture(language + "_formation_reserve")
		shop.fusion.opened = true
		await capture(language + "_fusion")
		for zone in shop.ui.zones:
			if String(zone["id"]).begins_with("material:"):
				check(int(String(zone["id"]).get_slice(":", 1)) >= Run.FUSION_BENCH, "fusion list excludes all deployed heroes")
		var candidates := Run.fusion_candidates()
		shop.fusion.selected.assign(candidates.slice(0, 5))
		await capture(language + "_fusion_selected")
		shop.fusion.opened = false
		Run.prepare_battle()
		Run.lives = 0
		Run.continue_used = false
		Run.hero_damage = {"sigrid": {"tier": 9, "damage": 12345678.0}, "brasa": {"tier": 9, "damage": 5300.0}}
		Run.phase = Run.Phase.OVER
		Run.running = false
		main.go_over()
		main.screen.set_process(false)
		main.screen.fx.clear()
		await capture(language + "_over")
		check(Run.best_player()["unit"]["id"] == "sigrid", "best player uses cumulative damage")
		Run.continue_used = true
		await capture(language + "_over_used")
		main.menu.open()
		await capture(language + "_menu")
		check(tap(main.menu, "language:en" if language == "ko" else "language:ko"), "language switches while menu is open")
		I18n.set_locale(language)
		main.menu.close()
		check(I18n.missing.is_empty(), "all new copy translated: " + str(I18n.missing))
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Camp refresh visual and interaction review")
