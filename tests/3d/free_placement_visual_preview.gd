extends Harness

var out_dir := "build/free-placement-render/1280x800"
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
		_prepare()
		main.go_shop()
		main.screen.tab="f"
		main.screen.hero_info_tab=false
		await frames(5)
		await snap(out_dir+"/"+locale+"_formation.png")
		var formation: FormationView=main.screen.formation
		formation.selected=4
		await paint(main.screen)
		await snap(out_dir+"/"+locale+"_selected.png")
		var candidate := _candidate(4)
		formation.view_3d.placement_preview(candidate,true)
		await paint(main.screen)
		await snap(out_dir+"/"+locale+"_valid.png")
		formation.view_3d.placement_preview(Balance.ARENA_CENTER,false)
		await paint(main.screen)
		await snap(out_dir+"/"+locale+"_invalid.png")
		formation.view_3d.placement_preview(Vector2.INF,false)
		main.go_battle()
		var screen: BattleScreen=main.screen
		await frames(4)
		screen.set_process(false)
		for n in range(180): screen._process(1.0/60)
		await paint(screen)
		await snap(out_dir+"/"+locale+"_battle.png")
		screen.selected_hero=4
		await paint(screen)
		await snap(out_dir+"/"+locale+"_battle_selected.png")
		for id in ["camera:left","camera:left","camera:in"]: screen.view_3d.camera_button(id)
		await paint(screen)
		await snap(out_dir+"/"+locale+"_battle_orbit.png")
		screen.selected_hero=-1
		screen.view_3d.camera_button("camera:reset")
		for n in range(8):
			for step in range(3): screen._process(1.0/60)
			await paint(screen)
			await snap(out_dir+"/"+locale+"_motion_%02d.png"%n)
		var geometry := {"meshes":0,"vertices":0,"triangles":0}
		_count(screen.view_3d.world,geometry)
		var file := FileAccess.open(out_dir+"/geometry.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(geometry,"  ")+"\n")
		file=null
		formation=null
		screen=null
	I18n.set_locale("ko")
	main.show_title()
	await frames(4)
	await snap(out_dir+"/ko_title.png")
	main.queue_free()
	main=null
	await frames(5)
	StellarModels._rigs.clear()
	StellarModels._materials.clear()
	StellarModels._mesh.clear()
	StellarModels._contacts.clear()
	StellarPortraits._cache.clear()
	Art._cache.clear()
	Art._previews.clear()
	await frames(4)
	await RenderingServer.frame_post_draw
	await get_tree().create_timer(0.25).timeout
	print("Free placement and render review: "+out_dir)
	# Let this coroutine release temporary snapshot Images before engine shutdown.
	get_tree().call_deferred("quit",0 if failures==0 else 1)

func _prepare() -> void:
	Fixture.prepare(16,20261008)
	Run.heroes.clear()
	Run.bench.clear()
	for i in range(12): Run.gain_hero(Roster.UNITS[i*4],i%10)
	Run.ensure_posts()
	for index in range(Run.heroes.size()):
		var original := Run.hero_position(Run.heroes[index])
		for offset in [Vector2(17,14),Vector2(-17,14),Vector2(14,-17),Vector2(-14,-17)]:
			if Run.move_hero_to(index,original+offset): break
		check(not Run.hero_position(Run.heroes[index]).is_equal_approx(Balance.post_position(int(Run.heroes[index]["post"]))),"visually inspect genuinely free positions")

func _candidate(index: int) -> Vector2:
	var original := Run.hero_position(Run.heroes[index])
	for point in [Vector2(82,192),Vector2(742,190),Vector2(82,706),Vector2(750,670)]:
		if Run.placement_error(point,index).is_empty() and point.distance_to(original)>70: return point
	for offset in [Vector2(19,0),Vector2(-19,0),Vector2(0,19),Vector2(0,-19)]:
		if Run.placement_error(original+offset,index).is_empty(): return original+offset
	return original

func _count(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D and node.is_visible_in_tree():
		result["meshes"]+=1
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			result["vertices"]+=arrays[Mesh.ARRAY_VERTEX].size()
			var indices=arrays[Mesh.ARRAY_INDEX]
			result["triangles"]+=(indices.size() if indices!=null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size())/3
	for child in node.get_children(): _count(child,result)
