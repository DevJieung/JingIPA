extends Harness

var main: Node2D
var output := "build/voc-hero/1280x800"
var report: Array = []

func capture(stem: String, stats_allowed := false) -> void:
	Look.text_audit.clear()
	Look.raw_text_audit.clear()
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	await snap(output + "/" + stem + ".png")
	check(I18n.missing.is_empty(), "translated: " + stem + str(I18n.missing))
	for box in Look.text_audit:
		check(float(box["width"]) <= Rect2(box["box"]).size.x + 0.5, "text width fits: " + String(box["text"]))
		check(float(box["height"]) <= Rect2(box["box"]).size.y + 0.5, "text height fits: " + String(box["text"]))
	for entry in Look.raw_text_audit:
		if not stats_allowed:
			check(not String(entry["text"]).contains("사거리") and not String(entry["text"]).contains("Range"), "no card combat statistics: " + stem)
	for zone in main.screen.ui.zones:
		check(Look.SCREEN.encloses(zone["rect"]), "touch stays within screen: " + String(zone["id"]))
	report.append({"frame": stem, "text_boxes": Look.text_audit.duplicate(true)})

func setup_roster() -> void:
	Fixture.prepare(40, 21092026)
	Run.heroes.clear()
	Run.bench.clear()
	var ids := ["marea", "jokull", "solana", "caden", "protea", "rhiannon", "candela", "morrigan", "finn", "vidarr", "kari", "sigrid"]
	for index in range(ids.size()):
		var unit := Roster.unit_by_id(ids[index])
		Run.heroes.append({"unit": unit, "tier": int(unit["tier"]), "wave": 1, "n": 1, "post": index})
	for unit in Roster.UNITS:
		Run.bench.append({"unit": unit, "tier": int(unit["tier"]), "wave": 1, "n": 1})
	Run.last_result = {}
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
	Look.text_audit_enabled = true
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		setup_roster()
		var draw := DrawScreen.new()
		main._swap(draw)
		draw.state = DrawScreen.SWAP
		draw.set_process(false)
		draw.formation.element = "ice"
		draw.formation._focused = true
		await capture(language + "_formation")
		# Adjacent long English names must have separate, legible name plates.
		var names: Array = []
		for entry in Look.raw_text_audit:
			if Rect2(entry["rect"]).position.x < 880:
				for hero in Run.heroes:
					if String(entry["text"]) == Look.unit_name(hero["unit"]):
						names.append(entry)
		for i in range(names.size()):
			for j in range(i + 1, names.size()):
				check(not Rect2(names[i]["rect"]).intersects(Rect2(names[j]["rect"])), "field names never overlap")
		draw.formation.selected = 5
		await capture(language + "_formation_selected")
		draw.formation_tab = false
		await capture(language + "_hero_cards")
		draw.hv.info = 11
		await capture(language + "_hero_detail", true)
		draw.hv.info = -1
		draw.fusion.opened = true
		draw.fusion.selected.assign(Run.fusion_candidates().slice(0, 5))
		await capture(language + "_fusion")
		draw.fusion.opened = false
		# The two camp and post-draw title sets use the same labels and cards.
		Run.phase = Run.Phase.SHOP
		var shop := ShopScreen.new()
		main._swap(shop)
		shop.set_process(false)
		shop.tab = "f"
		shop.hero_info_tab = true
		Run.heroes.resize(2)
		Run.bench.clear()
		await capture(language + "_empty_slots")
		if language == "en":
			var wrapped := false
			for entry in Look.text_audit:
				if entry["text"] == "Empty\nslot" and int(entry["lines"]) == 2:
					wrapped = true
			check(wrapped, "English field Empty slot uses two lines")
		# Ordinary summon keeps identity and traits but no combat stat boxes.
		Run.phase = Run.Phase.DRAW
		draw = DrawScreen.new()
		main._swap(draw)
		draw.set_process(false)
		draw.state = DrawScreen.REVEAL
		draw.rt = 3.0
		draw.result = {"unit": Roster.unit_by_id("sigrid"), "hand": 9, "where": "bench"}
		await capture(language + "_summon")
		for unit in Roster.units_of_tier(Poker.Hand.ROYAL):
			Run.phase = Run.Phase.SWAP
			Run.running = true
			Run.continue_used = true
			var slot := Run.bench.size()
			Run.bench.append({"unit": unit, "tier": Poker.Hand.ROYAL, "wave": Run.wave, "n": 1})
			Run.last_result = {"unit": unit, "hand": Poker.Hand.ROYAL, "where": "bench", "slot": slot, "revived": true, "reward_pending": true}
			draw = DrawScreen.new()
			main._swap(draw)
			draw.set_process(false)
			check(draw.state == DrawScreen.REVIVE_REWARD, "saved pending reward opens dedicated reveal")
			check(main.screen_modal_open(), "reward blocks menu navigation")
			var initial_count := Run.heroes.size() + Run.bench.size()
			if String(unit["id"]) == "nerea":
				var times := [0.0, 0.16, 0.34, 0.5, 0.75, 1.1, 1.5, 2.2, 4.0]
				for index in range(times.size()):
					draw.revive_reward.update(float(times[index]) - draw.revive_reward.age)
					await capture(language + "_reward_motion_%02d" % index)
			else:
				for tick in range(120):
					draw.revive_reward.update(0.02)
			await capture(language + "_reward_" + String(unit["id"]))
			check(tap(draw, "revive:confirm"), "explicit reward confirmation is reachable")
			check(await wait_screen(main, "shop_screen", 120), "reward confirm opens the main camp")
			main._process(1.0)
			shop = main.screen as ShopScreen
			shop.set_process(false)
			shop.tab = "f"
			check(Run.phase == Run.Phase.SHOP and Run.retry_wave, "camp retains the revived stage")
			check(not bool(Run.last_result.get("reward_pending", true)), "reward confirmation is persisted")
			check(Run.heroes.size() + Run.bench.size() == initial_count, "confirmation never grants another hero")
			check(shop.formation.selected == -1 and shop.formation.bench_selected == -1, "reward leaves placement to the player")
			await capture(language + "_reward_placed_" + String(unit["id"]))
			check(shop.formation.is_new(Run.bench[slot]), "exact reward card highlighted in hall")
		check(I18n.missing.is_empty(), "all new copy translated")
	Look.text_audit_enabled = false
	var file := FileAccess.open(output + "/text-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("VOC hero UI visual review")
