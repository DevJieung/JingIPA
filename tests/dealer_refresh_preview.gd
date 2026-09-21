extends Harness

var main: Node2D
var output := "build/dealer-refresh/1280x800"
var cards_only := false

func capture(name_: String) -> void:
	if main.screen != null:
		main.screen.queue_redraw()
	await frames(2)
	await snap(output + "/" + name_ + ".png")

func _ready() -> void:
	Save._readonly = true
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	main = load("res://game/main.gd").new()
	add_child(main)
	Fixture.prepare(24, 14092026)
	Run.begin_draw()
	Fixture.stack(9)
	var draw := DrawScreen.new()
	main._swap(draw)
	draw.set_process(false)
	await capture("draw")
	draw._confirm()
	for i in range(18):
		draw.rt = i * 0.15
		draw.t = draw.rt
		draw.fx.update(0.15)
		draw._reveal_beats()
		await capture("summon_%02d" % i)
	draw.rt = 3
	draw.fx.clear()
	await capture("summon_result")
	# The result must fit every hero's actual portrait and longest descriptions.
	for id in ["thalassa", "brasa", "lugh", "blank", "rhiannon", "morrigan"]:
		var unit := Roster.unit_by_id(id)
		draw.result["unit"] = unit
		draw.result["hand"] = int(unit["tier"])
		await capture("result_" + id)
	draw._after_reveal()
	draw.state = DrawScreen.SWAP
	draw.formation._focused = true
	draw.formation.selected = 0
	draw.formation.bench_selected = -1
	await capture("selected_formation")
	draw.formation_tab = false
	await capture("hero_hall")
	Run.phase = Run.Phase.SHOP
	var shop := ShopScreen.new()
	main._swap(shop)
	shop.set_process(false)
	for tab in ["u", "p", "c", "f"]:
		shop.tab = tab
		await capture("camp_" + tab)
	shop.fusion.opened = true
	while Run.bench.size() < 5:
		Run.gain_hero(Run.heroes[0]["unit"], int(Run.heroes[0]["tier"]), false)
	shop.fusion.selected.clear()
	for index in range(5):
		shop.fusion.selected.append(Run.FUSION_BENCH + index)
	await capture("fusion_selected")
	check(tap(shop, "fusion:go"), "fusion animation starts from real submit button")
	for i in range(18):
		shop.fusion.update(0.12)
		await capture("fusion_%02d" % i)
	await capture("fusion_result")
	Run.accept_fusion()
	shop.fusion.opened = false
	main.menu.open()
	for page in ["menu", "rules", "hands", "elements"]:
		main.menu.page = page
		await capture("menu_" + page)
	main.menu.close()
	for i in range(Roster.THEMES.size()):
		var ts := ThemeScreen.new()
		main._swap(ts)
		ts.set_process(false)
		ts.theme = Roster.THEMES[i]
		ts.t = 2
		await capture("theme_%02d" % i)
	main.screen.hide()
	add_child(CardsPreview.new())
	await capture("cards_52")
	finish("Dealer refresh rendering")

class CardsPreview extends Node2D:
	func _draw() -> void:
		draw_rect(Look.SCREEN, Look.BG_DEEP)
		for card in range(52):
			Look.draw_card(self, Vector2(40 + (card % 13) * 94, 42 + (card / 13) * 186), card, 0.74)
