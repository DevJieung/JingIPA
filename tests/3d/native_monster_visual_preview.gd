extends Harness

var cid := "drop_slime"
var out_dir := "build/character-3d/monster-review/drop_slime/1280x800"
var row: Dictionary
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var main: Node2D

func _ready() -> void:
	if not require_no_save(): return
	cid = arg("--id",cid)
	out_dir = arg("--out",out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for monster in Roster.MONSTERS:
		if String(monster["id"])==cid: row=monster
	check(not row.is_empty(),"native creature canonical identity")
	if row.is_empty(): get_tree().quit(1); return
	# Isolated no-save candidate proof, never publish the on-disk manifest.
	if not NativeMonsterModel.has_model(cid): NativeMonsterModel.manifest()["ready_ids"].append(cid)
	_setup_stage()
	var model := StellarModels.monster(row)
	stage.add_child(model)
	await frames(3)
	var stats := {"meshes":0,"vertices":0,"triangles":0,"materials":{}}
	_count(model,stats)
	stats["materials"] = stats["materials"].size()
	var file := FileAccess.open(out_dir+"/model_geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"  ")+"\n")
	file = null
	for view in ["front","side","back","three_quarter"]:
		_position_camera(view,model)
		await _portrait("gallery_"+view)
	_position_camera("three_quarter",model)
	for n in range(24):
		model.animate_visual(float(n)/8.0,false)
		await _portrait("idle_%02d"%n)
	for n in range(32):
		model.animate_visual(float(n)/30.0,true)
		await _portrait("move_%02d"%n)
	for status in ["Burn","Frost","Stun"]:
		model.get_node("Stellar"+status).visible=true
		await _portrait("status_"+status.to_lower())
		model.get_node("Stellar"+status).visible=false
	model.free()
	model=null
	await _reactions()
	viewport.queue_free()
	viewport=null
	stage=null
	camera=null
	await frames(3)
	await _battle()
	print("Actual native creature visual capture: "+cid+" "+out_dir)
	call_deferred("_cleanup_and_quit")

## Reaction states of the live adapter, each on a fresh instance so the
## contract clocks (world dt through face_toward, simulator motion_time) start
## from zero exactly as in battle.
func _reactions() -> void:
	const SOUTH := Vector2(0,-1)
	# Smooth turn with banking: walking, then the heading swings to the right.
	var model := await _fresh()
	model.face_toward(SOUTH,0.0)
	for n in range(16):
		model.face_toward(SOUTH if n==0 else Vector2(1,-0.4).normalized(),1.0/30.0)
		model.animate_visual(float(n)/30.0*1.7,true)
		await _portrait("turn_%02d"%n)
	model.free()
	# Blocked by a hero: the simulator clock is frozen, the body keeps breathing on world dt.
	model = await _fresh()
	model.face_toward(SOUTH,0.0)
	model.animate_visual(0.37,true)
	for n in range(12):
		model.face_toward(SOUTH,1.0/15.0)
		model.animate_visual(0.37,false)
		await _portrait("blocked_%02d"%n)
	model.free()
	# Crystal siege: one full phase, the strike lands at the wrap (frame 29 → 0).
	model = await _fresh()
	model.face_toward(SOUTH,0.0)
	model.animate_visual(0.0,true)
	for n in range(30):
		model.face_toward(SOUTH,1.0/30.0)
		model.set_siege(float(n)/30.0)
		model.animate_visual(0.0,false)
		await _portrait("siege_%02d"%n)
	model.free()
	# Hit from the left: flash 1 decaying at the simulator's 5/s.
	model = await _fresh()
	model.face_toward(SOUTH,0.0)
	model.animate_visual(0.2,true)
	var here := StellarWorld.logical(model.global_position)
	model.visual_event("hit",{"p": here+Vector2(-40,0),"crit": false})
	for n in range(8):
		model.face_toward(SOUTH,1.0/30.0)
		model.set_hit_flash(maxf(0.0,1.0-float(n)/6.0))
		model.animate_visual(0.2+float(n)/30.0,true)
		await _portrait("hit_%02d"%n)
	model.free()
	# Spawn: rise, drop or descend over 0.45 s while the clock already walks.
	model = await _fresh()
	model.visual_event("spawn",{"p": Vector2.ZERO})
	model.face_toward(SOUTH,0.0)
	for n in range(14):
		model.face_toward(SOUTH,1.0/30.0)
		model.animate_visual(float(n)/30.0,true)
		await _portrait("spawn_%02d"%n)
	model.free()
	# Death: collapse clip, topple/sink and dissolve until the body reports done.
	model = await _fresh()
	model.face_toward(SOUTH,0.0)
	model.animate_visual(0.3,true)
	model.visual_event("die",{"c": Color.WHITE,"h": 1.0})
	var frame := 0
	var done := false
	while frame < 48 and not done:
		done = model.advance_death(1.0/30.0)
		await _portrait("die_%02d"%frame)
		frame += 1
	check(done,"death presentation finishes within 1.6 s")
	model.free()

func _fresh() -> Node3D:
	var model := StellarModels.monster(row)
	stage.add_child(model)
	await frames(2)
	_position_camera("three_quarter",model)
	return model

func _battle() -> void:
	main=load("res://game/main.gd").new()
	add_child(main)
	await frames(4)
	Fixture.prepare(16,20261009)
	Run.heroes.clear()
	Run.bench.clear()
	for unit in Roster.UNITS:
		if Run.heroes.size()<12: Run.gain_hero(unit,Run.heroes.size()%10)
	Run.ensure_posts()
	main.go_battle()
	await frames(4)
	var screen: BattleScreen=main.screen
	screen.set_process(false)
	# Actual BattleSim/factory/world, with an isolated display fixture spread
	# across both paths. Canonical creature dictionaries/data stay unchanged.
	var sim=screen.sim
	sim.monsters.clear()
	var dense := "--density" in OS.get_cmdline_user_args()
	var count := 41 if dense else 12
	for n in range(count):
		var monster: Dictionary=Roster.MONSTERS[n%Roster.MONSTERS.size()] if dense else row
		sim._spawn(monster)
		var mo: Dictionary=sim.monsters[-1]
		mo["spawn_id"]=9000+n
		mo["s"]=float(n/2+1)*sim._path_len/(float(count)/2.0+2.0)
		mo["route"]=n%2
		mo["motion_t"]=float(n)*0.07
		mo["off"]=0.0
		if n%7==0: mo["burn_t"]=1.0
		if n%7==1: mo["slow_t"]=1.0
		if n%7==2: mo["stun_t"]=1.0
	check(Run.heroes.size()==12,"creature proof has twelve unique heroes")
	check(sim.monsters.size()==count,"creature proof expected density")
	await paint(screen)
	var proof := {"heroes":[],"monsters":[],"monster_count":count,"all_native":true}
	var world := screen.view_3d.world
	for node in world.hero_nodes.values():
		var source := String(node.get_meta("model_source",""))
		proof["heroes"].append({"source":source,"identity":node.get_meta("identity","")})
		if source.is_empty(): proof["all_native"]=false
	var seen: Dictionary={}
	for node in world.monster_nodes.values():
		var source := String(node.get_meta("model_source",""))
		var identity := String(node.get_meta("_stellar_monster_id",""))
		proof["monsters"].append({"source":source,"identity":identity})
		seen[identity]=true
		if source.is_empty(): proof["all_native"]=false
	proof["distinct_monsters"]=seen.size()
	if dense:
		check(proof["all_native"],"density proof uses native actors only")
		check(proof["heroes"].size()==12 and proof["monsters"].size()==41,"density actual twelve heroes and forty-one monsters")
		check(seen.size()==25,"density actual all twenty-five monster identities")
	var metadata := FileAccess.open(out_dir+"/battle_metadata.json",FileAccess.WRITE)
	metadata.store_string(JSON.stringify(proof,"  ")+"\n")
	metadata=null
	await snap(out_dir+"/battle.png")
	screen.selected_hero=0
	await paint(screen)
	await snap(out_dir+"/battle_selected.png")
	for action in ["camera:left","camera:left","camera:in"]: screen.view_3d.camera_button(action)
	await paint(screen)
	await snap(out_dir+"/battle_orbit.png")
	screen.selected_hero=-1
	screen.view_3d.camera_button("camera:reset")
	for n in range(12):
		for mo in sim.monsters:
			if float(mo["stun_t"])<=0: mo["motion_t"]+=0.07
		await paint(screen)
		await snap(out_dir+"/battle_motion_%02d.png"%n)
	screen=null
	main.queue_free()
	main=null
	await frames(5)

func _cleanup_and_quit() -> void:
	await frames(5)
	Sfx.set_process(false)
	for child in Sfx.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream=null
	await frames(5)
	StellarModels._rigs.clear()
	StellarModels._materials.clear()
	StellarModels._mesh.clear()
	StellarModels._contacts.clear()
	StellarPortraits._cache.clear()
	Art._cache.clear()
	Art._previews.clear()
	NativeCharacterModel._flash_mesh=null
	NativeCharacterModel._manifest.clear()
	NativeMonsterModel._manifest.clear()
	await frames(10)
	await RenderingServer.frame_post_draw
	get_tree().call_deferred("quit",0 if failures==0 else 1)

func _setup_stage() -> void:
	viewport=SubViewport.new()
	viewport.size=Vector2i(512,640)
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	stage=Node3D.new()
	viewport.add_child(stage)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(0,0,0,0)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("#b5d3e7")
	env.environment.ambient_light_energy=0.58
	stage.add_child(env)
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-35,145,0)
	key.light_energy=1.25
	key.light_color=Color("#ffe5c5")
	stage.add_child(key)
	var fill:=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-20,-35,0)
	fill.light_energy=0.55
	fill.light_color=Color("#97caff")
	stage.add_child(fill)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	stage.add_child(camera)
	camera.current=true

func _position_camera(view: String,model: Node3D) -> void:
	var height: float=NativeMonsterModel.manifest()["monsters"][cid]["height"]
	var target:=Vector3(0,height*0.50,0)
	match view:
		"front": camera.position=Vector3(0,height*.6,-4)
		"side": camera.position=Vector3(4,height*.6,0)
		"back": camera.position=Vector3(0,height*.6,4)
		_: camera.position=Vector3(2,height+0.25,-4)
	camera.look_at(target,Vector3.UP)
	var points: Array[Vector3]=[]
	_corners(model,points)
	var bounds:=Rect2()
	var first:=true
	for point in points:
		var local:=camera.global_transform.affine_inverse()*point
		var xy:=Vector2(local.x,local.y)
		if first: bounds=Rect2(xy,Vector2.ZERO);first=false
		else: bounds=bounds.expand(xy)
	camera.size=maxf(bounds.size.y,bounds.size.x/(float(viewport.size.x)/viewport.size.y))/0.82
	var center:=bounds.get_center()
	camera.position+=camera.global_basis*Vector3(center.x,center.y,0)

func _corners(node: Node,points: Array[Vector3]) -> void:
	if node is MeshInstance3D and node.visible:
		var box: AABB=node.mesh.get_aabb()
		for n in range(8): points.append(node.global_transform*box.get_endpoint(n))
	for child in node.get_children():
		if child is Node3D and not child.visible: continue
		_corners(child,points)

func _portrait(label: String) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out_dir+"/"+label+".png")

func _count(node: Node,result: Dictionary) -> void:
	if node is MeshInstance3D:
		result["meshes"]+=1
		for surface in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			result["vertices"]+=arrays[Mesh.ARRAY_VERTEX].size()
			var indices=arrays[Mesh.ARRAY_INDEX]
			result["triangles"]+=(indices.size() if indices!=null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size())/3
			var mat: Material=node.material_override if node.material_override!=null else node.mesh.surface_get_material(surface)
			result["materials"][mat.get_instance_id()]=true
	for child in node.get_children(): _count(child,result)
