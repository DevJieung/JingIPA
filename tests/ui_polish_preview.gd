extends Harness

var main: Node2D
var output := "build/ui-polish/1280x800"

func capture(name_: String) -> void:
	main.screen.queue_redraw()
	await frames(2)
	await snap(output + "/" + name_ + ".png")

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
		main.show_title()
		await capture(language + "_title")
		check(tap(main.screen, "language:" + language), "title language selector is reachable")
		Fixture.prepare(24, 15092026)
		Run.begin_draw()
		Fixture.stack(2)
		Run.passives.clear()
		Run.rerolled = [1, 1, 1, 1, 1]
		var draw := DrawScreen.new()
		main._swap(draw)
		draw.set_process(false)
		await capture(language + "_poker")
		draw._flip[0] = 0.15
		await capture(language + "_redraw")
		draw._flip[0] = 0.0
		Fixture.stack(9)
		await capture(language + "_poker_royal")
		Fixture.stack(2)
		Run.rerolled = [1, 1, 1, 1, 1]
		var original_gold := Run.gold
		Run.gold = 0
		await capture(language + "_poker_no_gold")
		for i in range(5):
			check(bool(zone_of(draw, "want:%d" % i).get("on", false)), "card choice remains available with spent rerolls")
			check(not bool(zone_of(draw, "re%d" % i).get("on", true)), "rerolls disable without gold")
		check(ui_hit(draw, "go"), "hand can still be confirmed without gold")
		draw._confirm()
		Run.gold = original_gold
		draw.rt = 0.5
		await capture(language + "_summon_gather")
		draw.rt = 1.2
		await capture(language + "_summon_cast")
		draw.rt = 3
		for id in ["pip", "thalassa", "morrigan", "rhiannon", "shift"]:
			var unit := Roster.unit_by_id(id)
			draw.result["unit"] = unit
			draw.result["hand"] = int(unit["tier"])
			await capture(language + "_hero_" + id)
		draw.state = DrawScreen.SWAP
		draw.formation._focused = true
		draw.formation.selected = 0
		await capture(language + "_deployment")
		check(zone_of(draw, "formation:info").is_empty(), "deployment has no duplicate hero info button")
		check(tap(draw, "formation:roster"), "hero info tab is reachable beside deployment")
		await capture(language + "_deployment_roster")
		check(tap(draw, "hv:f0"), "hero info tab card opens details")
		check(draw.hv.info == 0, "hero info tab shows chosen hero")
		await capture(language + "_deployment_info")
		check(main.screen_modal_open(), "hero info blocks main menu")
		check(tap(draw, "hv:close"), "hero info close")
		check(draw.hv.info == -1, "actual close button dismisses hero info")
		Run.phase = Run.Phase.SHOP
		var shop := ShopScreen.new()
		main._swap(shop)
		shop.set_process(false)
		shop.tab = "f"
		shop.formation._focused = true
		shop.formation.selected = 0
		await capture(language + "_camp_deployment")
		check(zone_of(shop, "formation:info").is_empty(), "camp deployment has no duplicate hero info button")
		check(tap(shop, "tab:i"), "camp info tab is reachable")
		await capture(language + "_camp_roster")
		check(tap(shop, "hv:f0"), "camp hero card opens details")
		check(shop.hv.info == 0, "camp hero detail selected")
		await capture(language + "_camp_info")
		check(main.screen_modal_open(), "camp hero detail blocks main menu")
		var old_wave := Run.wave
		mouse(shop, Vector2(1015, 740), true)
		check(Run.wave == old_wave and not main._next.is_valid(), "info overlay intercepts underlying next button")
		shop.hv.info = 0
		await capture(language + "_camp_info")
		check(tap(shop, "hv:move"), "move from details enters roster placement")
		check(shop.hv.sel == 0 and shop.hero_info_tab, "move retains exact chosen hero")
		shop.hv.sel = -1
		shop.tab = "c"
		Run.lives = 9
		await capture(language + "_reward_button")
		Ads._finish(true, "광고 보상을 받았습니다.")
		await capture(language + "_reward_notice")
		Ads._message_left = 0
		shop.fusion.opened = true
		while Run.bench.size() < 5:
			Run.gain_hero(Run.heroes[0]["unit"], int(Run.heroes[0]["tier"]), false)
		shop.fusion.selected.clear()
		for index in range(5):
			shop.fusion.selected.append(Run.FUSION_BENCH + index)
		await capture(language + "_fusion_selection")
		check(tap(shop, "fusion:go"), "fusion result opens")
		shop.fusion.update(2)
		shop.fusion.update(0.5)
		await capture(language + "_fusion_result")
		var failed: bool = Run.fusion_pending["failed"]
		Run.fusion_pending["failed"] = true
		await capture(language + "_fusion_recovery")
		Run.fusion_pending["failed"] = failed
		Run.accept_fusion()
		shop.fusion.opened = false
		for tab in ["u", "p"]:
			shop.tab = tab
			await capture(language + "_camp_" + tab)
		main.menu.open()
		for page in ["menu", "rules", "hands", "elements"]:
			main.menu.page = page
			await capture(language + "_menu_" + page)
		main.menu.close()
		Run.phase = Run.Phase.SWAP
		Run.prepare_battle()
		var battle := BattleScreen.new()
		main._swap(battle)
		battle.set_process(false)
		for frame in range(240):
			battle._process(1.0 / 60.0)
		await capture(language + "_battle")
		battle.ended = true
		await capture(language + "_battle_result")
		Run.phase = Run.Phase.OVER
		main.go_over()
		main.screen.set_process(false)
		await capture(language + "_over")
		# Every hero identity stays on one row and its concept fits two lines.
		for unit in Roster.UNITS:
			var id := String(unit["id"])
			check(not I18n.hero_concept(id).is_empty(), "hero concept exists: " + id)
			check(Look.wrapped_lines(I18n.hero_concept(id), 432, 22).size() * Look.line_height(22) <= 82, "hero concept fits: " + id)
			check(SummonArt.trait_labels(unit).size() >= 1, "hero attack type exists: " + id)
		var audit := FileAccess.open(output + "/" + language + "_missing.json", FileAccess.WRITE)
		audit.store_string(JSON.stringify(I18n.missing, "\t"))
	var fx := Fx.new()
	for multiplier in [2.0, 1.0, 0.5]:
		for critical in [false, true]:
			fx.clear()
			fx.dmg_text(Vector2.ZERO, 100, multiplier, critical, Balance.elem_color("fire"))
			var color: Color = fx.items.back()["c"]
			check(color == (Balance.elem_color("fire") if multiplier == 2 else Color("#eeeae2") if multiplier == 1 else Color("#9a9da3")), "crit preserves matchup damage color")
	main.queue_free()
	await frames(3)
	finish("UI polish preview")

func ui_hit(screen: Node, id: String) -> bool:
	var zone := zone_of(screen, id)
	return not zone.is_empty() and screen.ui.hit(Rect2(zone["rect"]).get_center()) == id
