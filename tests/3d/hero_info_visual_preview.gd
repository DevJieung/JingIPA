extends Harness

## The hero information pop-up (SummonArt.hero_info with the stat grid) for melee and
## ranged heroes in Korean and English, captured from the real DrawScreen / HeroView.
##
##   godot --path . --resolution 1280x800 res://tests/3d/hero_info_visual_preview.tscn -- --out DIR [--ids a,b]
##
## Checks the stat grid actually renders a move-speed cell whose value is the hero's
## Run.hero_stats speed, that a sword hero's first trait chip reads 근접 (Melee) while a
## bow hero's does not, and that every text box stays inside the pop-up panel.

const IDS := ["jokull", "pip", "helga", "caden", "echo", "brasa"]
const PANEL := Rect2(174, 154, 932, 508)
const INFO := Rect2(555, 180, 514, 400)   # SummonArt.hero_info box in HeroView._info_panel

var out_dir := "build/melee-speed/1280x800"

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ids := arg("--ids", ",".join(IDS)).split(",")
	var main: Node2D = load("res://game/main.gd").new()
	add_child(main)
	await frames(3)
	Fixture.prepare(13, 20261011)
	Run.passives.clear()
	Run.heroes.clear()
	Run.bench.clear()
	for i in range(ids.size()):
		Run.gain_hero(Roster.unit_by_id(String(ids[i])), 3 + (i % 3) * 2)
	Run.begin_draw()
	Run.confirm_summon()
	var details := DrawScreen.new()
	details.formation_tab = false
	main._swap(details)
	await frames(3)
	var report := {"heroes": {}}
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		# Texts of the screen behind the pop-up (hero list, buttons) are recorded with
		# the pop-up closed, so the panel checks below only judge the pop-up's own text.
		details.hv.info = -1
		Look.text_audit_enabled = true
		Look.text_audit.clear()
		Look.raw_text_audit.clear()
		details.queue_redraw()
		await frames(3)
		var background := {}
		for item in Look.text_audit: background[String(item["text"]) + str(item["box"])] = true
		for item in Look.raw_text_audit: background[String(item["text"]) + str(item["rect"])] = true
		Look.text_audit_enabled = false
		for id in ids:
			var index := -1
			for i in range(Run.heroes.size()):
				if String(Run.heroes[i]["unit"]["id"]) == id: index = i
			for i in range(Run.bench.size()):
				if String(Run.bench[i]["unit"]["id"]) == id: index = HeroView.BENCH + i
			check(index >= 0, "hero %s is in the run" % id)
			if index < 0: continue
			details.hv.info = index
			Look.text_audit_enabled = true
			Look.text_audit.clear()
			Look.raw_text_audit.clear()
			details.queue_redraw()
			await frames(3)
			# Fitted boxes (stat values) and raw draws (labels, chips) of the pop-up only:
			# the hero list behind the modal also draws text, so only boxes that touch the
			# identity area are held to the panel.
			var texts: Array[String] = []
			for item in Look.text_audit:
				var box: Rect2 = item["box"]
				if background.has(String(item["text"]) + str(box)) or not INFO.intersects(box): continue
				texts.append(String(item["text"]))
				check(box.size.x > 0 and box.size.y > 0, "%s/%s visible text box: %s" % [id, locale, item["text"]])
				check(PANEL.encloses(box), "%s/%s text stays inside the pop-up panel: %s" % [id, locale, item["text"]])
			for item in Look.raw_text_audit:
				var rect: Rect2 = item["rect"]
				if background.has(String(item["text"]) + str(rect)) or not INFO.intersects(rect): continue
				texts.append(I18n.t(String(item["text"])))
				check(PANEL.encloses(rect), "%s/%s label stays inside the pop-up panel: %s" % [id, locale, item["text"]])
			Look.text_audit_enabled = false
			var hero: Dictionary = Run.heroes[index] if index < HeroView.BENCH else Run.bench[index - HeroView.BENCH]
			var st := Run.hero_stats(hero)
			var unit: Dictionary = hero["unit"]
			check(I18n.t("이동속도") in texts, "%s/%s move speed label is rendered" % [id, locale])
			check(str(int(st["speed"])) in texts, "%s/%s move speed value %d is rendered" % [id, locale, int(st["speed"])])
			check(I18n.t("공격력") in texts and I18n.t("사거리") in texts and I18n.t("치명타") in texts, "%s/%s the other stat labels remain" % [id, locale])
			var chips := SummonArt.trait_labels(unit)
			if Balance.is_melee(unit):
				check(chips[0] == "근접" and I18n.t("근접") in texts, "%s/%s a sword hero's first chip is 근접" % [id, locale])
			else:
				check(chips[0] != "근접" and I18n.t("근접") not in texts, "%s/%s a ranged hero has no 근접 chip" % [id, locale])
			await snap(out_dir + "/hero_info_%s_%s.png" % [id, locale])
			report["heroes"]["%s_%s" % [id, locale]] = {"speed": int(st["speed"]), "range": int(st["range"]), "chips": chips}
	I18n.set_locale("ko")
	var file := FileAccess.open(out_dir + "/hero-info-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file = null
	main.queue_free()
	await frames(2)
	finish("Hero info pop-up (stat grid, melee chip) visual preview")
