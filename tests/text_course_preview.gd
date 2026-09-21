extends Harness

var main: Node2D
var output := "build/text-course/1280x800"
var report: Array[Dictionary] = []
var overlaps: Array[Dictionary] = []
var minimum := 100
var focused := false

func review(stem: String, screenshot: bool = true) -> void:
	Look.text_audit.clear()
	Look.raw_text_audit.clear()
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	if screenshot:
		await snap(output + "/" + stem + ".png")
	var unique := {}
	for row in Look.text_audit:
		var key := str(row)
		if unique.has(key):
			continue
		unique[key] = true
		var box: Rect2 = row["box"]
		check(float(row["width"]) <= box.size.x + 0.5 and float(row["height"]) <= box.size.y + 0.5, "complete boxed text at " + stem + ": " + row["text"])
		if not String(row["text"]).is_empty():
			minimum = mini(minimum, int(row["size"]))
		var saved := row.duplicate()
		saved["screen"] = stem
		saved["box"] = [box.position.x, box.position.y, box.size.x, box.size.y]
		report.append(saved)
	var raw := {}
	for row in Look.raw_text_audit:
		var key := str(row)
		raw[key] = row
	var rows: Array = raw.values()
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var box: Rect2 = row["rect"]
		if box.position.x < -1 or box.end.x > 1281:
			overlaps.append({"screen": stem, "kind": "screen edge", "text": row["text"], "box": str(box)})
		for j in range(i + 1, rows.size()):
			var other: Dictionary = rows[j]
			if row["text"] == other["text"] or row["canvas"] != other["canvas"]:
				continue
			var other_box: Rect2 = other["rect"]
			if absf(box.get_center().y - other_box.get_center().y) < 5 and box.intersection(other_box).size.x > 3:
				overlaps.append({"screen": stem, "kind": "same-row overlap", "text": row["text"], "other": other["text"], "box": str(box), "other_box": str(other_box)})

func swap(screen: Node2D) -> void:
	main._swap(screen)
	screen.set_process(false)

func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly = true
	output = arg("--out", output)
	focused = arg("--focused", "false") == "true"
	DirAccess.make_dir_recursive_absolute(output)
	main = load("res://game/main.gd").new()
	add_child(main)
	main.menu.set_process(false)
	Look.text_audit_enabled = true
	I18n.audit_enabled = true
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Save.best_wave = 100
		Save.best_hand = 9
		Save.cur_run = {"wave": 100}
		for unit in Roster.UNITS:
			Save.seen_units[String(unit["id"])] = true
		Run.running = false
		swap(TitleScreen.new())
		await review(locale + "_title")
		main.screen.collection.opened = true
		for element in CollectionView.ELEMENTS:
			main.screen.collection.element = element
			await review(locale + "_collection_" + element)
		main.screen.collection.close()
		Fixture.fresh(20092026, 12)
		Run.wave = 100
		Run.gold = 99999999
		var draw := DrawScreen.new()
		swap(draw)
		for hand in range(10):
			Fixture.stack(hand)
			await review(locale + "_draw_%d" % hand, hand == 9)
		draw.card_choice.opened = true
		draw.card_choice.slot = 0
		await review(locale + "_card_choice")
		draw.card_choice.opened = false
		Run.rerolled.fill(4)
		Run.paid.fill(8)
		await review(locale + "_draw_paid")
		if focused:
			continue
		Run.phase = Run.Phase.SHOP
		for unit in Roster.UNITS:
			Run.gain_hero(unit, int(unit["tier"]))
		var shop := ShopScreen.new()
		swap(shop)
		await review(locale + "_upgrades")
		var saved_wave := Run.wave
		Run.wave = 9
		for theme_index in range(Roster.THEMES.size()):
			Run.themes[0] = theme_index
			await review(locale + "_lineup_%02d" % theme_index, false)
		Run.wave = saved_wave
		for upgrade in Balance.UPGRADES:
			Run.levels[String(upgrade["id"])] = int(upgrade["cap"]) if int(upgrade["cap"]) > 0 else 99
		await review(locale + "_upgrades_max")
		Run.owned_passives.clear()
		for passive in Balance.PASSIVES:
			Run.owned_passives.append(String(passive["id"]))
		shop.tab = "p"
		for page in range(4):
			shop.passive_page = page
			Run.passives.assign(Run.owned_passives.slice(page * 6, page * 6 + 3))
			await review(locale + "_passives_%d" % page)
		# Both copies of each toggle must remain separate and act on the same passive.
		shop.passive_page = 0
		Run.passives.assign(Run.owned_passives.slice(0, 3))
		await review(locale + "_passives_touch", false)
		var target := String(Run.passives[0])
		for zone in shop.ui.zones:
			if String(zone["id"]) == "active:" + target:
				check(Look.SCREEN.encloses(zone["rect"]), "active control remains on screen")
		check(tap(shop, "active:" + target) and not Run.passives.has(target), "visible deactivate control removes active state")
		await paint(shop)
		check(tap(shop, "active:" + target) and Run.passives.has(target), "visible activate control restores active state")
		shop.tab = "f"
		await review(locale + "_formation")
		shop.formation.selected = 0
		await review(locale + "_formation_selected")
		shop.hero_info_tab = true
		for i in range(Run.heroes.size() + Run.bench.size()):
			shop.hv.info = i if i < Run.heroes.size() else Run.FUSION_BENCH + i - Run.heroes.size()
			await review(locale + "_hero_%d" % i, i in [0, 9, 39, 49])
		shop.hv.info = -1
		shop.fusion.opened = true
		shop.fusion.selected.assign(Run.fusion_candidates().slice(0, 5))
		await review(locale + "_fusion")
		shop.fusion.opened = false
		main.menu.open()
		for page in ["menu", "rules", "hands", "elements"]:
			main.menu.page = page
			await review(locale + "_menu_" + page)
		main.menu.close()
		Fixture.fresh(20092026, 12)
		Run.wave = 10
		Run.gold = 999999
		Run.phase = Run.Phase.BATTLE
		var battle := BattleScreen.new()
		swap(battle)
		for index in range(Roster.THEMES.size()):
			Run.themes[0] = index
			battle.sim.setup(Run, Run.wave)
			battle.t = 1.0
			await review(locale + "_course_%02d" % index)
		# Consecutive actual movement frames around the extra inner corners.
		battle.sim._queue.clear()
		for index in range(2):
			battle.sim._spawn(Roster.MONSTERS[0])
			battle.sim.monsters[index]["s"] = Balance.path_len() - 280
			battle.sim.monsters[index]["hp"] = 1000000000.0
			battle.sim.monsters[index]["max"] = 1000000000.0
		for frame in range(7):
			await review(locale + "_turn_%02d" % frame)
			for tick in range(20):
				battle.sim.step(0.025)
		battle.sim.monsters.clear()
		Run.gold = 9223372036854775807
		await review(locale + "_gold_int64")
		Run.gold = 999999
		battle.ended = true
		battle._lost = 20
		battle._bonus = 999999
		await review(locale + "_battle_result")
		Run.wave = 0
		for index in range(Roster.THEMES.size()):
			Run.themes[0] = index
			var theme := ThemeScreen.new()
			swap(theme)
			theme.t = 1.0
			theme.fx.clear()
			await review(locale + "_theme_%02d" % index, index % 10 == 0)
		Run.hero_damage = {"sigrid": {"tier": 9, "damage": 999999999.0}}
		Run.running = false
		Run.phase = Run.Phase.OVER
		Run.lives = 0
		swap(OverScreen.new())
		main.screen.fx.clear()
		await review(locale + "_over")
		check(I18n.missing.is_empty(), "all copy localized: " + str(I18n.missing))
	var file := FileAccess.open(output + "/text-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"boxes": report, "review_candidates": overlaps, "minimum_font": minimum}, "\t"))
	file.close()
	print("text box records: ", report.size(), "; minimum font: ", minimum, "; review candidates: ", overlaps.size())
	Look.text_audit_enabled = false
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Text boxes and all courses review")
