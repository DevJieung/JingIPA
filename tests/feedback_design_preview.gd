extends Harness

var main: Node2D
var output := "build/feedback-design/1280x800"

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
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		for wave in range(1, Balance.LAST_WAVE, 10):
			Fixture.prepare(wave, 15092026)
			var theme := ThemeScreen.new()
			main._swap(theme)
			theme.set_process(false)
			theme.t = 2.0
			theme.fx.clear()
			await capture(language + "_theme_%03d" % wave)
			for row in theme.preview["rows"]:
				for monster in row["monsters"]:
					check(Look.wrapped_lines(String(monster["ko"]), 142, 17).size() <= 2, "monster name fits two lines")
		Fixture.prepare(11, 15092026)
		Run.begin_draw()
		var draw := DrawScreen.new()
		main._swap(draw)
		draw.set_process(false)
		for hand in [0, 4, 9]:
			Fixture.stack(hand)
			await capture(language + "_hand_%d" % hand)
		Ads._finish(true, "광고 보상을 받았습니다.")
		await capture(language + "_reward_notice")
		Ads._message_left = 0
	I18n.set_locale("ko")
	Fixture.prepare(41, 15092026)
	Run.heroes.clear()
	Run.bench.clear()
	var ids := ["thalassa", "brasa", "sigrid", "lugh", "blank"]
	for id in ids:
		var unit := Roster.unit_by_id(id)
		Run.gain_hero(unit, int(unit["tier"]))
	Run.wave = 41
	Run.phase = Run.Phase.BATTLE
	var battle := BattleScreen.new()
	main._swap(battle)
	battle.set_process(false)
	battle.sim._queue.clear()
	battle.sim.monsters.clear()
	for i in range(6):
		battle.sim._spawn(Roster.MONSTERS[i])
		battle.sim.monsters[-1]["s"] = 190.0 + i * 110.0
		battle.sim.monsters[-1]["hp"] = 100000.0
		battle.sim.monsters[-1]["max"] = 100000.0
	battle.sim._cache_positions()
	var centers := [Vector2(164, 269), Vector2(347, 291), Vector2(575, 262), Vector2(235, 576), Vector2(584, 584)]
	for i in range(ids.size()):
		var unit := Roster.unit_by_id(ids[i])
		battle.area_fx.zone(centers[i], 100.0, String(unit["elem"]), Balance.elem_color(String(unit["elem"])), 9, 0.25, 0.25, 4, Anim.clip(unit, "shot"))
	battle.area_fx.update(0.1)
	for i in range(12):
		await capture("area_%02d" % i)
		battle.area_fx.update(0.12)
	main.queue_free()
	await frames(3)
	finish("Feedback design preview")
