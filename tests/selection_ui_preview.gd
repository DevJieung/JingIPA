extends Harness

var main: Node2D
var output := "build/selection-ui/1280x800"


func capture(name_: String) -> void:
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	await snap(output + "/" + name_ + ".png")


func check_menu() -> void:
	await paint(main.menu)
	var zone := zone_of(main.menu, "menu")
	check(not zone.is_empty() and bool(zone.get("on", false)), "menu is available")
	if zone.is_empty():
		return
	var rect: Rect2 = zone["rect"]
	check(is_equal_approx(rect.end.x, Hud.LANGUAGE_RECT.position.x - 12), "menu sits beside the right-edge language control")
	for screen_zone in main.screen.ui.zones:
		var other: Rect2 = screen_zone["rect"]
		if other.size.x < Look.SCREEN.size.x and bool(screen_zone.get("on", false)):
			check(not rect.intersects(other), "menu does not cover screen action " + String(screen_zone["id"]))
	check(tap(main.menu, "menu") and main.menu.opened, "right-edge menu opens by its actual hit target")
	main.menu.close()
	await paint(main.menu)


func duplicate_inventory() -> void:
	Fixture.fresh(16092026)
	Run.heroes.clear()
	Run.bench.clear()
	for id in ["thalassa", "morrigan", "brasa", "sigrid", "lugh", "blank", "brian", "brigid", "caden", "candela", "carmen", "ceniza"]:
		var unit := Roster.unit_by_id(id)
		Run.gain_hero(unit, int(unit["tier"]))
	for id in ["thalassa", "thalassa", "thalassa", "thalassa", "thalassa", "morrigan", "morrigan", "morrigan"]:
		var unit := Roster.unit_by_id(id)
		Run.gain_hero(unit, int(unit["tier"]))
	Run.phase = Run.Phase.SWAP


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
		main.show_title()
		main.screen.set_process(false)
		await capture(language + "_title")
		await check_menu()
		Fixture.fresh(16092026)
		Fixture.stack(2)
		var draw := DrawScreen.new()
		main._swap(draw)
		draw.set_process(false)
		await capture(language + "_draw")
		await check_menu()
		duplicate_inventory()
		draw = DrawScreen.new()
		main._swap(draw)
		draw.set_process(false)
		draw.fusion.opened = true
		await capture(language + "_fusion_duplicates")
		check(not bool(zone_of(main.menu, "menu").get("on", true)), "fusion disables menu")
		var visible: Array[int] = []
		for page_index in range(ceili(float(Run.bench.size()) / FusionView.PAGE_SIZE)):
			draw.fusion.page = page_index
			await capture(language + "_fusion_page_%d" % page_index)
			for zone in draw.ui.zones:
				var id := String(zone["id"])
				if id.begins_with("material:"):
					var code := int(id.get_slice(":", 1))
					visible.append(code)
					check(bool(zone["on"]) == Run.fusion_material_allowed(code), "only reserve material targets are enabled")
					if code < Run.FUSION_BENCH:
						mouse(draw, Rect2(zone["rect"]).get_center(), true)
						check(draw.fusion.selected.is_empty(), "touching a deployed card cannot select it")
		check(visible.size() == Run.bench.size(), "every waiting copy appears and deployed cards are excluded")
		check(visible == Run.fusion_candidates(), "waiting cards follow the shared rarity and element order")
		draw.fusion.page = 0
		await paint(draw)
		# Even an old enabled hit zone cannot add a deployed material code.
		var forged_ui := Ui.new()
		forged_ui.zone(Rect2(0, 0, 20, 20), "material:0")
		var event := InputEventMouseButton.new()
		event.position = Vector2(10, 10)
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		draw.fusion.input(event, forged_ui)
		check(draw.fusion.selected.is_empty(), "controller rejects stale enabled deployed targets")
		draw.fusion.selected.assign([0])
		await paint(draw)
		check(draw.fusion.selected.is_empty(), "redraw removes stale deployed selections")
		for code in visible.slice(0, 5):
			check(tap(draw, "material:%d" % code), "each duplicate can be selected separately")
			await paint(draw)
		check(draw.fusion.selected.size() == 5 and not draw.fusion.selected.has(0), "five identical reserves are selected while deployed hero stays protected")
		check(bool(zone_of(draw, "fusion:go").get("on", false)), "five identical heroes enable fusion")
		await capture(language + "_fusion_selected")
		check(tap(draw, "material:%d" % visible[0]), "selected duplicate can be individually removed")
		await paint(draw)
		check(draw.fusion.selected.size() == 4 and not draw.fusion.selected.has(0), "removing one reserve preserves the other reserve choices")
		draw.fusion.opened = false
		Run.phase = Run.Phase.SHOP
		Run.wave = 99
		Run.roll_shop()
		var shop := ShopScreen.new()
		main._swap(shop)
		shop.set_process(false)
		await capture(language + "_shop")
		await check_menu()
		Run.wave = 100
		await capture(language + "_shop_complete")
		Fixture.prepare(80, 16092026)
		Run.begin_draw()
		Run.confirm_hand()
		Run.prepare_battle()
		var battle := BattleScreen.new()
		main._swap(battle)
		battle.set_process(false)
		await capture(language + "_battle")
		await check_menu()
		for speed in [1, 2, 3]:
			check(tap(battle, "sp%d" % speed), "speed control remains reachable")
			check(is_equal_approx(battle.speed, float(speed)), "speed control applies requested speed")
		Run.running = false
		Run.phase = Run.Phase.OVER
		main.go_over()
		main.screen.set_process(false)
		main.screen.fx.clear()
		await capture(language + "_over")
		await check_menu()
		check(I18n.missing.is_empty(), "no missing UI translations in " + language)
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Selection and right-edge menu preview")
