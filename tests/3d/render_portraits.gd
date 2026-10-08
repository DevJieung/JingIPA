extends Node

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(256,320)
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(0,0,0,0)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("#c7d8e9")
	env.environment.ambient_light_energy=0.70
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-35,145,0)
	key.light_energy=1.50
	key.light_color=Color("#fff0d9")
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-20,-35,0)
	fill.light_energy=0.45
	fill.light_color=Color("#a5cdff")
	stage.add_child(fill)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.size=2.25
	stage.add_child(camera)
	camera.position=Vector3(1.7,1.65,-3.2)
	camera.look_at(Vector3(0,0.97,0),Vector3.UP)
	camera.current=true
	var count := 0
	var ids := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): ids=arg.substr(6)
	for unit in Roster.UNITS:
		if ids!="" and not String(unit["id"]) in ids.split(","): continue
		for grade in range(10):
			await _render(stage,viewport,camera,unit,grade)
			count+=1
	# Fusion guardians use their canonical base identity at all tiers.
	for grade in range(10):
		for unit in Roster.fusion_units(grade):
			if ids!="" and not String(unit["base_id"]) in ids.split(","): continue
			await _render(stage,viewport,camera,unit,grade)
			count+=1
	for monster in Roster.MONSTERS:
		await _render_monster(stage,viewport,camera,monster)
	print("Stellar 3D portraits generated: %d heroes + 25 monsters"%count)
	viewport.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _render(stage: Node3D, viewport: SubViewport, camera: Camera3D, unit: Dictionary, grade: int) -> void:
	var model := StellarModels.hero(unit,grade)
	stage.add_child(model)
	camera.position=Vector3(1.7,1.65,-3.2)
	camera.look_at(Vector3(0,0.97,0),Vector3.UP)
	var corners: Array[Vector3]=[]
	_corners(model,corners)
	var bounds := Rect2()
	var first := true
	for point in corners:
		var local := camera.global_transform.affine_inverse()*point
		var xy := Vector2(local.x,local.y)
		if first:
			bounds=Rect2(xy,Vector2.ZERO)
			first=false
		else: bounds=bounds.expand(xy)
	var aspect := float(viewport.size.x)/viewport.size.y
	camera.size=maxf(bounds.size.y,bounds.size.x/aspect)/0.84
	var middle := bounds.get_center()
	camera.position+=camera.global_basis*Vector3(middle.x,middle.y,0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := StellarPortraits.path(unit,grade)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := image.save_png(path)
	if err!=OK: push_error("Portrait write failed: "+path)
	model.free()

func _corners(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var box: AABB=node.mesh.get_aabb()
		for n in range(8): points.append(node.global_transform*box.get_endpoint(n))
	for child in node.get_children(): _corners(child,points)

func _render_monster(stage: Node3D, viewport: SubViewport, camera: Camera3D, data: Dictionary) -> void:
	var model := StellarModels.monster(data)
	stage.add_child(model)
	camera.position=Vector3(1.7,1.65,-3.2)
	camera.look_at(Vector3(0,0.97,0),Vector3.UP)
	var points: Array[Vector3]=[]
	_corners(model,points)
	var bounds := Rect2()
	var first := true
	for point in points:
		var local := camera.global_transform.affine_inverse()*point
		var xy := Vector2(local.x,local.y)
		if first:
			bounds=Rect2(xy,Vector2.ZERO)
			first=false
		else: bounds=bounds.expand(xy)
	camera.size=maxf(bounds.size.y,bounds.size.x/(float(viewport.size.x)/viewport.size.y))/0.84
	var middle := bounds.get_center()
	camera.position+=camera.global_basis*Vector3(middle.x,middle.y,0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://art/models/monsters/%s.png"%data["id"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	viewport.get_texture().get_image().save_png(path)
	model.free()
