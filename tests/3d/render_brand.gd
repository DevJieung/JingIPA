extends Node

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(512,512)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_4X
	add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color8(35,93,72)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("#a5c5df")
	env.environment.ambient_light_energy=0.5
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-35,155,0)
	light.light_color=Color("#fff2d5")
	light.light_energy=1.3
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3.0
	stage.add_child(camera)
	camera.position=Vector3(0.7,1.7,-4)
	camera.look_at(Vector3(0,1.0,0),Vector3.UP)
	camera.current=true
	var symbol := Node3D.new()
	stage.add_child(symbol)
	var gold := Color("#ddbd73")
	# The crystal shrine and an orbital star crest replace every spade mark.
	StellarModels.part(symbol,"cylinder",Vector3(0,0.22,0),Vector3(1.8,0.40,1.5),Color("#314b5b"),0.4)
	StellarModels.part(symbol,"ring",Vector3(0,0.45,0),Vector3(1.68,0.15,1.42),gold,0.75)
	var crystal := MeshInstance3D.new()
	crystal.mesh=_gem()
	crystal.material_override=StellarModels.material(Color("#75d4e5"),0.25,0.20)
	symbol.add_child(crystal)
	StellarModels.part(symbol,"ring",Vector3(0,1.06,0.14),Vector3(2.05,0.10,2.05),gold,0.75,0.2,Vector3(PI/2,0,0))
	for n in range(5):
		var angle := -PI*0.5+(n-2)*0.51
		var star := MeshInstance3D.new()
		star.mesh=_star()
		star.material_override=StellarModels.material(gold,0.15,0.2)
		star.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
		star.position=Vector3(cos(angle)*1.04,1.0-sin(angle)*1.04,-0.13)
		star.scale=Vector3.ONE*(0.40 if n==2 else 0.31)
		symbol.add_child(star)
	await _save(viewport,"res://art/ui/launcher_main.png")
	await _save(viewport,"res://art/ui/startup_logo.png")
	viewport.transparent_bg=true
	camera.size=3.85
	await _save(viewport,"res://art/ui/launcher_adaptive.png")
	symbol.free()
	var coin := Node3D.new()
	stage.add_child(coin)
	StellarModels.part(coin,"cylinder",Vector3(0,1,0),Vector3(1.1,0.17,1.1),gold,0.75,0,Vector3(PI/2,0,0))
	StellarModels.part(coin,"ring",Vector3(0,1,-0.12),Vector3(1.0,0.10,1.0),Color("#efce81"),0.8,0,Vector3(PI/2,0,0))
	var star := MeshInstance3D.new()
	star.mesh=_star()
	star.material_override=StellarModels.material(Color("#fff0be"),0.15,0.12)
	star.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	star.position=Vector3(0,1,-0.15)
	star.scale=Vector3.ONE*0.68
	coin.add_child(star)
	viewport.size=Vector2i(64,64)
	camera.size=1.5
	camera.position=Vector3(0.4,1.4,-4)
	camera.look_at(Vector3(0,1,0),Vector3.UP)
	await _save(viewport,"res://art/ui/coin.png")
	print("Stellar 3D brand icons generated")
	viewport.queue_free()
	await get_tree().process_frame
	get_tree().quit()

func _save(viewport: SubViewport, path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)

func _star() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := PackedVector2Array()
	for n in range(10):
		var a := -PI/2+n*PI/5
		outline.append(Vector2(cos(a),sin(a))*(0.50 if n%2==0 else 0.23))
	for n in range(10):
		var a := outline[n]
		var b := outline[(n+1)%10]
		for v in [Vector3(0,0,-0.055),Vector3(a.x,-a.y,-0.025),Vector3(b.x,-b.y,-0.025)]: surface.add_vertex(v)
		for v in [Vector3(a.x,-a.y,-0.025),Vector3(b.x,-b.y,-0.025),Vector3(b.x,-b.y,0.06),Vector3(a.x,-a.y,-0.025),Vector3(b.x,-b.y,0.06),Vector3(a.x,-a.y,0.06)]: surface.add_vertex(v)
	surface.generate_normals()
	return surface.commit()

func _gem() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in range(6):
		var a := Vector3(cos(n*TAU/6)*0.44,0.98,sin(n*TAU/6)*0.39)
		var b := Vector3(cos((n+1)*TAU/6)*0.44,0.98,sin((n+1)*TAU/6)*0.39)
		for v in [Vector3(0,1.83,0),b,a,a,b,Vector3(0,0.49,0)]: surface.add_vertex(v)
	surface.generate_normals()
	return surface.commit()
