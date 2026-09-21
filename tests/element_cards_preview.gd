extends Harness

const IDS := ["thalassa", "brasa", "sigrid", "lugh", "blank"]
var output := "build/element-cards/1280x800"
var main: Node2D


class CardSheet extends Node2D:
	func _draw() -> void:
		draw_rect(Look.SCREEN, Look.BG)
		Look.text_center(self, Vector2(640, 28), "ELEMENT CARDS  /  BASE - SELECTED - PROTECTED - COMPACT", 23, Look.INK)
		for i in range(5):
			var unit := Roster.unit_by_id(IDS[i])
			var x := 22.0 + i * 252
			Look.draw_elem(self, Vector2(x + 70, 80), 13, String(unit["elem"]))
			Look.text_left(self, Vector2(x + 95, 80), Balance.elem_ko(String(unit["elem"])), 24, Look.INK)
			HeroCard.draw(self, Rect2(x, 110, 226, 172), {"unit": unit, "tier": 0})
			HeroCard.draw(self, Rect2(x, 306, 226, 172), {"unit": unit, "tier": 9}, true)
			HeroCard.draw(self, Rect2(x, 502, 226, 172), {"unit": unit, "tier": 4}, false, "출전 중", true)
			HeroCard.draw(self, Rect2(x, 698, 226, 88), {"unit": unit, "tier": 7})


func capture(name_: String) -> Image:
	main.screen.queue_redraw()
	await frames(2)
	return await snap(output + "/" + name_ + ".png")


func prepare_inventory() -> void:
	Fixture.fresh(16092026)
	Run.heroes.clear()
	Run.bench.clear()
	for id in IDS + ["morrigan", "brian", "brigid", "caden", "candela", "carmen", "ceniza"]:
		var unit := Roster.unit_by_id(id)
		Run.gain_hero(unit, int(unit["tier"]))
	for id in IDS + ["morrigan", "thalassa", "thalassa", "thalassa", "thalassa", "thalassa"]:
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
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		main.menu.hide()
		var sheet := CardSheet.new()
		main._swap(sheet)
		var rendered := await capture(language + "_palette")
		# Sample actual rendered pixels: rarity, selection and protection must retain
		# exactly the same element face and edge, including at the smaller viewport.
		var scale := Vector2(rendered.get_width(), rendered.get_height()) / Look.SCREEN.size
		for i in range(5):
			for offset in [Vector2(60, 20), Vector2(112, 1)]:
				var top: Vector2 = (Vector2(22 + i * 252, 110) + offset) * scale
				var expected := rendered.get_pixelv(Vector2i(top))
				for y in [306, 502]:
					var sample: Vector2 = (Vector2(22 + i * 252, y) + offset) * scale
					check(rendered.get_pixelv(Vector2i(sample)).is_equal_approx(expected), "rendered element color survives rarity and card states")
		main.menu.show()
		prepare_inventory()
		var draw := DrawScreen.new()
		main._swap(draw)
		draw.set_process(false)
		draw.state = DrawScreen.SWAP
		draw.formation.bench_selected = 0
		await capture(language + "_formation")
		draw.formation_tab = false
		draw.hv.new_id = "morrigan"
		await capture(language + "_roster")
		for i in range(IDS.size()):
			draw.hv.info = i
			await capture(language + "_detail_" + IDS[i])
		draw.hv.info = -1
		draw.fusion.opened = true
		await capture(language + "_fusion_locked")
		draw.fusion.selected.assign([Run.FUSION_BENCH, Run.FUSION_BENCH + 1, Run.FUSION_BENCH + 2, Run.FUSION_BENCH + 3, Run.FUSION_BENCH + 4])
		await capture(language + "_fusion_selected")
		check(tap(draw, "fusion:go"), "available reserve cards open fusion result")
		draw.fusion.reveal_age = 2.0
		for id in IDS:
			Run.fusion_pending["unit"] = id
			Run.fusion_pending["tier"] = int(Roster.unit_by_id(id)["tier"])
			await capture(language + "_fusion_result_" + id)
		Run.accept_fusion()
		draw.fusion.opened = false
		draw.state = DrawScreen.REVEAL
		draw.rt = 3
		for id in IDS:
			var unit := Roster.unit_by_id(id)
			draw.result = {"unit": unit, "hand": int(unit["tier"]), "where": "bench"}
			await capture(language + "_summon_" + id)
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Element card presentation")
