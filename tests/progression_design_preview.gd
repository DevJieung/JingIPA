extends Harness

var main: Node2D
var output := "build/progression-design/1280x800"
var report: Array = []

func capture(stem: String, image_: bool = true) -> void:
	Look.text_audit.clear()
	Look.raw_text_audit.clear()
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	if image_:
		await snap(output + "/" + stem + ".png")
	var found := {}
	for row in Look.text_audit:
		if found.has(str(row)):
			continue
		found[str(row)] = true
		var box: Rect2 = row["box"]
		check(float(row["width"]) <= box.size.x + 0.5 and float(row["height"]) <= box.size.y + 0.5, stem + ": complete text " + row["text"])
		var saved := row.duplicate()
		saved["screen"] = stem
		saved["box"] = str(box)
		report.append(saved)

func swap(screen: Node2D) -> void:
	main._swap(screen)
	screen.set_process(false)

func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly = true
	Save.cur_run = {}
	output = arg("--out", output)
	DirAccess.make_dir_recursive_absolute(output)
	main = load("res://game/main.gd").new()
	add_child(main)
	Look.text_audit_enabled = true
	I18n.audit_enabled = true
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		Save.seen_units.clear()
		Save.unit_best.clear()
		Save.best_tier = 9
		swap(TitleScreen.new())
		await capture(language + "_title")
		main.menu.open()
		await capture(language + "_menu")
		main.menu.page = "rite"
		await capture(language + "_rite_guide")
		main.menu.close()
		var title: TitleScreen = main.screen
		title.collection.opened = true
		title.collection.fusion_only = true
		for element in CollectionView.ELEMENTS:
			title.collection.element = element
			await capture(language + "_collection_" + element)
		check(title.collection._fusion_seen_count() == 0, "undiscovered fusion kinds are locked")
		title.collection.element = "water"
		Save.seen_units["awakened_water_2"] = true
		check(int(title.collection.heroes()[0]["tier"]) == 2, "actual low-star fusion guardian uses its own art and rank")
		await capture(language + "_collection_water_low")
		Save.seen_units["awakened_water_5"] = true
		check(int(title.collection.heroes()[0]["tier"]) == 5 and title.collection._fusion_seen_count() == 1, "highest discovered rank represents a single guardian kind")
		await capture(language + "_collection_water_high")
		Fixture.fresh(20261006)
		var draw := DrawScreen.new()
		swap(draw)
		draw.skip_spin()
		for stars in range(Rite.MIN_STARS, Rite.MAX_STARS + 1):
			Fixture.stack(stars)
			await capture(language + "_draw_%02d" % stars)
		Run.heroes.clear()
		Run.bench.clear()
		Run.phase = Run.Phase.SWAP
		for tier in [0,1,4,8,9]:
			Run.bench.append({"unit": Roster.units_of_tier(tier)[0], "tier": tier, "wave": 1, "n": 1})
		draw.fusion.opened = true
		draw.fusion.selected.assign(Run.fusion_candidates())
		await capture(language + "_fusion_materials")
		check(tap(draw,"fusion:go"), "fusion starts from actual UI")
		draw.fusion.reveal_age = 3
		await capture(language + "_fusion_awakened")
		check(tap(draw,"fusion:accept"), "fusion reward confirmed")
		draw.fusion.opened = false
		Fixture.fresh(20261006,12)
		Run.wave = 12
		Run.phase = Run.Phase.BATTLE
		var battle := BattleScreen.new()
		swap(battle)
		battle.sim.support_pending = true
		Run.support_available = true
		battle.support_age = 3
		await capture(language + "_support_choices")
		check(tap(battle,"support:hero:4"), "support promotion target selection")
		await capture(language + "_support_selected")
		check(tap(battle,"support:promote"), "support promotion actual UI")
		battle.support_age = 1
		await capture(language + "_support_promoted")
		check(tap(battle,"support:continue"), "support acknowledgment continues assault")
		Fixture.fresh(20261007,12)
		Run.wave=12
		Run.phase=Run.Phase.BATTLE
		battle=BattleScreen.new()
		swap(battle)
		battle.sim.support_pending = true
		Run.support_available = true
		check(battle.sim.support_enabled,"actual battle enables support")
		await capture(language + "_support_second")
		check(tap(battle,"support:summon"),"free summon actual UI")
		battle.support_age=1
		await capture(language + "_support_summoned")
		check(String(battle.support_result.get("where",""))=="bench", "full field stores summon explicitly")
		check(tap(battle,"support:continue"),"summon confirmation")
		for index in range(10):
			battle._process(0.09)
			battle.fx.strike(Vector2(160+index*11,350),Look.GOLD,index%2==0)
			await capture(language + "_battle_motion_%02d" % index)
		Run.themes.fill(0)
		for index in range(Roster.THEMES.size()):
			Run.themes.fill(index)
			battle.sim.monsters.clear()
			battle.fx.clear()
			battle.area_fx.fields.clear()
			await capture(language + "_map_%02d" % index)
			check(Scenery.MAP_MOTIFS.has(Roster.THEMES[index]["id"]),"named map motif present")
			check(Scenery.map_landmark_positions(Roster.THEMES[index]).size()>=2,"visible terrain landmarks present: " + Roster.THEMES[index]["id"])
	check(I18n.missing.is_empty(),"English UI has no untranslated text: " + str(I18n.missing))
	var file := FileAccess.open(output + "/text-audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	Look.text_audit_enabled=false
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream=null
	await get_tree().create_timer(0.15).timeout
	finish("Progression design actual render review")
