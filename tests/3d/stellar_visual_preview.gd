extends Harness

var out_dir := "build/stellar-3d/1280x800"
var main: Node2D

func _ready() -> void:
	if not require_no_save(): return
	out_dir=arg("--out",out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main=load("res://game/main.gd").new()
	add_child(main)
	await frames(3)
	for locale in ["ko","en"]:
		I18n.set_locale(locale)
		Fixture.prepare(16,20261008)
		main.show_title()
		await frames(4)
		await snap(out_dir+"/"+locale+"_title.png")
		Fixture.prepare(16,20261008)
		Run.heroes.clear()
		Run.bench.clear()
		for i in range(12): Run.gain_hero(Roster.UNITS[i*4],i%10)
		Run.ensure_posts()
		main.go_shop()
		main.screen.tab="f"
		main.screen.hero_info_tab=false
		await frames(5)
		await snap(out_dir+"/"+locale+"_formation.png")
		main.go_battle()
		var screen: BattleScreen=main.screen
		await frames(5)
		screen.set_process(false)
		for n in range(180):
			screen._process(1.0/60)
		await frames(3)
		await snap(out_dir+"/"+locale+"_battle.png")
		for id in ["camera:left","camera:left","camera:in"]: screen.view_3d.camera_button(id)
		screen.queue_redraw()
		await frames(3)
		await snap(out_dir+"/"+locale+"_battle_orbit.png")
		screen.view_3d.camera_button("camera:reset")
		for n in range(12):
			for step in range(3): screen._process(1.0/60)
			screen.queue_redraw()
			await frames(2)
			await snap(out_dir+"/"+locale+"_motion_%02d.png"%n)
		var card := DrawScreen.new()
		Run.begin_draw()
		Run.confirm_summon()
		main._swap(card)
		card.state=DrawScreen.REVEAL
		card.rt=2.0
		await frames(4)
		await snap(out_dir+"/"+locale+"_summon.png")
	I18n.set_locale("en")
	for page in range(5):
		var gallery := Gallery.new()
		gallery.page=page
		main._swap(gallery)
		await frames(4)
		await snap(out_dir+"/identities_%d.png"%page)
	for unit in [Roster.unit_by_id("limne"),Roster.unit_by_id("brasa"),Roster.unit_by_id("zero"),Roster.unit_by_id("echo")]:
		var gallery := Gallery.new()
		gallery.unit=unit
		main._swap(gallery)
		await frames(4)
		await snap(out_dir+"/rank_"+String(unit["id"])+".png")
	main.queue_free()
	main=null
	await frames(5)
	StellarModels._rigs.clear()
	StellarModels._materials.clear()
	StellarModels._mesh.clear()
	StellarPortraits._cache.clear()
	Art._cache.clear()
	Art._previews.clear()
	await frames(4)
	await RenderingServer.frame_post_draw
	await get_tree().create_timer(0.2).timeout
	print("Stellar visual captures: "+out_dir)
	get_tree().quit()

class Gallery extends Node2D:
	var page := 0
	var unit: Dictionary = {}
	func _draw() -> void:
		draw_rect(Look.SCREEN,Color("#102131"))
		Look.text_center(self,Vector2(640,34),"STELLAR DEFENSE · 3D HEROES" if unit.is_empty() else Look.unit_name(unit)+" · HALF-STAR EVOLUTION",28,Look.GOLD)
		for i in range(10):
			var u: Dictionary=Roster.UNITS[page*10+i] if unit.is_empty() else unit
			var grade := 9 if unit.is_empty() else i
			var box := Rect2(18+i%5*253,75+i/5*355,239,337)
			Look.hero_card_panel(self,box,String(u["elem"]))
			Art.draw_unit_fit(self,u,Rect2(box.position+Vector2(14,20),Vector2(211,258)),Color.WHITE,grade)
			Look.text_center_fit(self,box.position+Vector2(120,294),Look.unit_name(u),23,Look.INK,224,17)
			Look.draw_rarity(self,box.position+Vector2(120,322),grade,8)
