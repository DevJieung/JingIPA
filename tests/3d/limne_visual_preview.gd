extends Harness

var out_dir := "build/limne-game-motion/game-review/1280x800"
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var main: Node2D

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out",out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_setup_stage()
	var model := StellarModels.hero(Roster.UNITS[0],0)
	stage.add_child(model)
	var stats := {"meshes":0,"vertices":0,"triangles":0,"materials":{}}
	await frames(3)
	_count(model,stats)
	stats["materials"] = stats["materials"].size()
	var file := FileAccess.open(out_dir+"/model_geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"  ")+"\n")
	file = null
	for view in ["front","side","back","three_quarter","face_closeup"]:
		_position_camera(view)
		await _portrait("gallery_"+view)
	_position_camera("three_quarter")
	for n in range(60):
		model.animate_visual(float(n)/10.0)
		await _portrait("idle_%02d"%n)
	for n in range(40):
		model.animate_visual(float(n)/40.0,float(n)/40.0,0.6,true)
		await _portrait("attack_%02d"%n)
	model.animate_visual(0)
	model.free()
	for grade in [0,4,9]:
		model = StellarModels.hero(Roster.UNITS[0],grade)
		stage.add_child(model)
		await _portrait("grade_%02d"%grade)
		model.free()
	var awakened: Dictionary = Roster.fusion_units(0)[0]
	model = StellarModels.hero(awakened,0)
	stage.add_child(model)
	await _portrait("awakened")
	model.free()
	model = null
	viewport.queue_free()
	viewport = null
	stage = null
	camera = null
	await frames(3)
	main = load("res://game/main.gd").new()
	add_child(main)
	await frames(4)
	Fixture.prepare(16,20261008)
	Run.heroes.clear()
	Run.bench.clear()
	for i in range(12):
		Run.gain_hero(Roster.UNITS[i*4],4 if i==0 else i%10)
	Run.ensure_posts()
	check(Run.heroes.size()==12,"actual battle capture deploys Limne and eleven unique heroes")
	main.go_shop()
	main.screen.tab = "f"
	main.screen.hero_info_tab = false
	await frames(5)
	await snap(out_dir+"/formation.png")
	main.go_battle()
	var screen: BattleScreen = main.screen
	await frames(4)
	screen.set_process(false)
	for n in range(120): screen._process(1.0/60)
	await paint(screen)
	await snap(out_dir+"/battle.png")
	screen.selected_hero = 0
	await paint(screen)
	await snap(out_dir+"/battle_selected.png")
	for id in ["camera:left","camera:left","camera:in"]:
		screen.view_3d.camera_button(id)
	await paint(screen)
	await snap(out_dir+"/battle_orbit.png")
	screen.selected_hero = -1
	screen.view_3d.camera_button("camera:reset")
	for n in range(8):
		for step in range(5): screen._process(1.0/60)
		await paint(screen)
		await snap(out_dir+"/battle_motion_%02d.png"%n)
	screen = null
	main.queue_free()
	main = null
	await frames(5)
	print("Limne live GLB visual captures: "+out_dir)
	# Finish the capture coroutine first, including temporary return Images and
	# imported-scene references, before clearing caches in a separate coroutine.
	call_deferred("_cleanup_and_quit")

func _cleanup_and_quit() -> void:
	await frames(5)
	# This silent visual fixture owns no ongoing audio. Finish the mixer voices
	# before deleting cached scenes, rather than leave Ogg playback alive at exit.
	Sfx.set_process(false)
	for child in Sfx.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	await frames(5)
	StellarModels._rigs.clear()
	StellarModels._materials.clear()
	StellarModels._mesh.clear()
	StellarModels._contacts.clear()
	StellarPortraits._cache.clear()
	Art._cache.clear()
	Art._previews.clear()
	LimneModel._tube = null
	LimneModel._spray_mesh = null
	LimneModel._drop_mesh = null
	LimneModel._drop_material = null
	await frames(10)
	await RenderingServer.frame_post_draw
	await get_tree().create_timer(0.5).timeout
	get_tree().call_deferred("quit",0 if failures==0 else 1)

func _setup_stage() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(512,640)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0,0,0,0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#b5d3e7")
	env.environment.ambient_light_energy = 0.58
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35,145,0)
	key.light_energy = 1.25
	key.light_color = Color("#ffe5c5")
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20,-35,0)
	fill.light_energy = 0.55
	fill.light_color = Color("#97caff")
	stage.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	stage.add_child(camera)
	camera.current = true
	_position_camera("three_quarter")

func _position_camera(view: String) -> void:
	camera.size = 2.4
	match view:
		"front": camera.position = Vector3(0,1.03,-4)
		"side": camera.position = Vector3(4,1.03,0)
		"back": camera.position = Vector3(0,1.03,4)
		"face_closeup":
			camera.position = Vector3(.4,1.40,-4)
			camera.size = .72
			camera.look_at(Vector3(0,1.34,0),Vector3.UP)
			return
		_: camera.position = Vector3(2.0,1.7,-4)
	camera.look_at(Vector3(0,0.94,0),Vector3.UP)

func _portrait(label: String) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out_dir+"/"+label+".png")

func _count(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D:
		result["meshes"] += 1
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			result["vertices"] += arrays[Mesh.ARRAY_VERTEX].size()
			var indices = arrays[Mesh.ARRAY_INDEX]
			result["triangles"] += (indices.size() if indices!=null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size())/3
			var mat: Material = node.material_override if node.material_override != null else node.mesh.surface_get_material(surface)
			result["materials"][mat.get_instance_id()] = true
	for child in node.get_children(): _count(child,result)
