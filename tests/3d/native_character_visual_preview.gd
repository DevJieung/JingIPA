extends Harness

var out_dir := "build/character-3d/review/echo/1280x800"
var cid := "echo"
var unit: Dictionary
var base_index := 0
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var main: Node2D

func _ready() -> void:
	if not require_no_save(): return
	cid = arg("--id",cid)
	out_dir = arg("--out",out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for i in Roster.UNITS.size():
		if String(Roster.UNITS[i]["id"]) == cid:
			unit = Roster.UNITS[i]
			base_index = i
	check(not unit.is_empty(),"native visual ID exists")
	if unit.is_empty(): get_tree().quit(1); return
	# Full candidate QA routes the candidate through the actual factory/world in
	# this isolated no-save process only. It never publishes the on-disk manifest.
	if "--candidate-only" not in OS.get_cmdline_user_args() and not NativeCharacterModel.has_model(cid):
		NativeCharacterModel.manifest()["ready_ids"].append(cid)
	_setup_stage()
	var model := _make(0)
	stage.add_child(model)
	await frames(3)
	if "--release-only" in OS.get_cmdline_user_args():
		model.visual_event({"t":"aim","w":0.6,"d":Vector2(0,1)})
		model.animate_visual(0.6,0.6,0.6,true)
		model.visual_event({"t":"fire","d":Vector2(0,1)})
		for n in range(8):
			model.animate_visual(0.6+float(n)*0.02,0.6+float(n)*0.02,0.6,true)
			await _portrait("release_%02d"%n)
		model.free()
		model = null
		viewport.queue_free()
		viewport = null
		stage = null
		camera = null
		await frames(3)
		await _battle()
		call_deferred("_cleanup_and_quit")
		return
	var stats := {"meshes":0,"vertices":0,"triangles":0,"materials":{}}
	_count(model,stats)
	stats["materials"] = stats["materials"].size()
	var file := FileAccess.open(out_dir+"/model_geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"  ")+"\n")
	file = null
	for view in ["front","side","back","three_quarter","face_closeup"]:
		_position_camera(view)
		await _portrait("gallery_"+view)
	_position_camera("three_quarter")
	for n in range(24):
		model.animate_visual(float(n)/4.0)
		await _portrait("idle_%02d"%n)
	model.animate_visual(0)
	_aim(model,0.6,Vector2(0,1))
	for n in range(40):
		var time := float(n)*0.03
		if n==20:
			model.animate_visual(time,time,0.6,true)
			_fire(model,Vector2(0,1))
		model.animate_visual(time,time,0.6,true)
		await _portrait("attack_%02d"%n)
	model.animate_visual(0)
	if "--no-motion" not in OS.get_cmdline_user_args():
		await _motion_sequences(model)
	model.free()
	for grade in [0,4,9]:
		model = _make(grade)
		stage.add_child(model)
		await _portrait("grade_%02d"%grade)
		model.free()
	var awakened: Dictionary
	for fusion in Roster.fusion_units(base_index/5):
		if String(fusion.get("base_id","")) == cid: awakened = fusion
	model = _make(0,awakened)
	stage.add_child(model)
	await _portrait("awakened")
	model.free()
	model = null
	viewport.queue_free()
	viewport = null
	stage = null
	camera = null
	await frames(3)
	if "--candidate-only" not in OS.get_cmdline_user_args(): await _battle()
	print("Actual native visual capture: "+cid+" "+out_dir)
	call_deferred("_cleanup_and_quit")

## Locomotion, turning, aim twist and walk+attack layering on the isolated stage.
## The model stays at the origin: the world owns positions, the adapter owns the pose.
func _motion_sequences(model: Node3D) -> void:
	if not model.has_method("set_locomotion"): return
	var step := 1.0/30.0
	var t := 20.0
	# The stage camera sits in front of the model (-Z), so the base facing is north.
	var south := Vector2(0,-1)
	# Straight run toward the camera side, then stop and settle.
	var run_dir := Vector2(-0.45,-1).normalized()
	model.animate_visual(t,9,0,true)
	for n in range(24):
		t += step
		model.set_locomotion(Vector3(run_dir.x,0,run_dir.y)*3.4,step)
		model.face_toward(run_dir,step)
		model.animate_visual(t,9,0,true)
		await _portrait("walk_%02d"%n)
	for n in range(24):
		t += step
		var moving := n < 8
		model.set_locomotion(Vector3(run_dir.x,0,run_dir.y)*(3.4 if moving else 0.0),step)
		model.face_toward(run_dir,step)
		model.animate_visual(t,9,0,true)
		await _portrait("walk_stop_%02d"%n)
	# Curved run: heading sweeps 150 degrees while moving.
	for n in range(24):
		t += step
		var heading := run_dir.rotated(deg_to_rad(150.0)*float(n)/23.0)
		model.set_locomotion(Vector3(heading.x,0,heading.y)*3.4,step)
		model.face_toward(heading,step)
		model.animate_visual(t,9,0,true)
		await _portrait("walk_curve_%02d"%n)
	# Standing turns: 90 degrees, then 180 degrees.
	for n in range(6):
		t += step
		model.set_locomotion(Vector3.ZERO,step)
		model.face_toward(south,step)
		model.animate_visual(t,9,0,true)
	for n in range(16):
		t += step
		model.set_locomotion(Vector3.ZERO,step)
		model.face_toward(Vector2(1,0) if n < 8 else Vector2(-1,0),step)
		model.animate_visual(t,9,0,true)
		await _portrait("turn_%02d"%n)
	# Aim twist: the torso answers immediately, the root follows.
	for n in range(8):
		t += step
		model.set_locomotion(Vector3.ZERO,step)
		model.face_toward(south,step)
		model.animate_visual(t,9,0,true)
	var aim_dir := south.rotated(deg_to_rad(55.0))
	_aim(model,0.3,aim_dir)
	for n in range(12):
		var age := float(n)/60.0
		if n == 9: _fire(model,aim_dir)
		t += 1.0/60.0
		model.set_locomotion(Vector3.ZERO,1.0/60.0)
		model.face_toward(aim_dir,1.0/60.0)
		model.animate_visual(t,age,0.3,true)
		await _portrait("aim_%02d"%n)
	model.animate_visual(t+1.0,9,0,true)
	# Walking while attacking: legs keep travelling, the upper body attacks.
	t += 1.0
	for n in range(8):
		t += step
		model.set_locomotion(Vector3(south.x,0,south.y)*3.4,step)
		model.face_toward(south,step)
		model.animate_visual(t,9,0,true)
	var side_dir := south.rotated(deg_to_rad(-50.0))
	_aim(model,0.25,side_dir)
	for n in range(24):
		var age := float(n)*step
		if n == 8: _fire(model,side_dir)
		t += step
		model.set_locomotion(Vector3(south.x,0,south.y)*3.4,step)
		model.face_toward(side_dir if n < 17 else south,step)
		model.animate_visual(t,age,0.25,true)
		await _portrait("walk_attack_%02d"%n)
	model.set_locomotion(Vector3.ZERO,step)
	model.animate_visual(t+1.0)

func _aim(model: Node3D, wind: float, direction: Vector2) -> void:
	if model.has_method("visual_event"): model.visual_event({"t":"aim","w":wind,"d":direction})

func _fire(model: Node3D, direction: Vector2) -> void:
	if model.has_method("visual_event"): model.visual_event({"t":"fire","d":direction})

func _make(grade: int, fusion: Dictionary = {}) -> Node3D:
	if cid == "limne" or NativeCharacterModel.has_model(cid): return StellarModels.hero(unit if fusion.is_empty() else fusion,grade)
	var model := NativeCharacterModel.create(cid)
	model.set_meta("identity",cid)
	model.set_meta("grade",grade)
	var profile: Dictionary = StellarModels.profiles()[cid]
	var equipment := Node3D.new()
	equipment.name = "RankEquipment"
	model.get_node("Body").add_child(equipment)
	StellarModels._rank_details(equipment,Color(String(profile["coat"])),Color("#caa263") if grade<6 else Color("#f2d297"),grade,int(profile["index"]),not fusion.is_empty())
	StellarModels.compact(equipment)
	return model

func _battle() -> void:
	main = load("res://game/main.gd").new()
	add_child(main)
	await frames(4)
	Fixture.prepare(16,20261009)
	Run.heroes.clear()
	Run.bench.clear()
	Run.gain_hero(unit,4)
	for u in Roster.UNITS:
		if String(u["id"])!=cid and Run.heroes.size()<12: Run.gain_hero(u,Run.heroes.size()%10)
	Run.ensure_posts()
	check(Run.heroes.size()==12,"native battle fixture contains twelve unique IDs")
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
	for id in ["camera:left","camera:left","camera:in"]: screen.view_3d.camera_button(id)
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

func _cleanup_and_quit() -> void:
	await frames(5)
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
	NativeCharacterModel._flash_mesh = null
	NativeCharacterModel._manifest.clear()
	await frames(10)
	await RenderingServer.frame_post_draw
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
	camera.size = 2.95
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	stage.add_child(camera)
	camera.current = true
	_position_camera("three_quarter")

func _position_camera(view: String) -> void:
	camera.size = 2.95
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
