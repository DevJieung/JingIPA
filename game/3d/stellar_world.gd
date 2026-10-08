extends Node3D
class_name StellarWorld

## Rendering adapter. BattleSim owns every position, target, timer and damage value.
const UNIT := 50.0
var camera := Camera3D.new()
var terrain := Node3D.new()
var actors := Node3D.new()
var projectiles := Node3D.new()
var selection := Node3D.new()
var weather: MultiMeshInstance3D
var zone_nodes: Array[Node3D] = []
var texts: Array[Dictionary] = []
var _text_gap := 0.0
var crystals: Array[Node3D] = []
var hero_nodes: Dictionary = {}
var monster_nodes: Dictionary = {}
var bullet_nodes: Array[Node3D] = []
var effects: Array[Dictionary] = []
var theme_id := ""
var yaw := -0.12
var zoom := 1.0
var camera_target := Vector3.ZERO
var _selected := -2
var _available := false
var _range := -1.0
var _occupied := ""

static func world(p: Vector2, height: float = 0.0) -> Vector3:
	return Vector3((p.x - Balance.ARENA_CENTER.x) / UNIT, height, (p.y - Balance.ARENA_CENTER.y) / UNIT)

static func logical(p: Vector3) -> Vector2:
	return Vector2(p.x * UNIT, p.z * UNIT) + Balance.ARENA_CENTER

func _ready() -> void:
	add_child(terrain)
	add_child(actors)
	add_child(projectiles)
	add_child(selection)
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.1
	camera.far = 80
	camera.current = true
	camera_update()
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#101e2c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#acb6c1")
	env.ambient_light_energy = 0.26
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#263a51")
	env.fog_density = 0.007
	env.fog_sky_affect = 0
	environment.environment = env
	add_child(environment)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("#c3ccda")
	moon.light_energy = 0.64
	moon.rotation_degrees = Vector3(-58,-28,0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(moon)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#ffcd8f")
	fill.light_energy = 0.18
	fill.rotation_degrees = Vector3(-25,140,0)
	add_child(fill)

func camera_update() -> void:
	camera.size = 18.5 / zoom
	camera.position = camera_target + Vector3(sin(yaw)*14.0,16.5,cos(yaw)*14.0)
	camera.look_at(camera_target, Vector3.UP)

func screen(p: Vector2, height: float = 0.0) -> Vector2:
	return camera.unproject_position(world(p,height))

func ground_at(pixel: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	if absf(direction.y) < 0.001: return Vector2.INF
	return logical(origin + direction * (-origin.y / direction.y))

func _clear(node: Node) -> void:
	for child in node.get_children(): child.free()

func build_map(theme: Dictionary) -> void:
	var id := String(theme.get("id", "rock"))
	if id == theme_id: return
	theme_id = id
	_clear(terrain)
	crystals.clear()
	var body := String(theme.get("main_body","wood"))
	var motif := String(Scenery.MAP_MOTIFS.get(id,"gravel"))
	var palette := {"aqua":"#253e46","flame":"#3e3239","wood":"#263d35","rock":"#424041","frost":"#5b6d7b"}
	var ground := Color(String(palette.get(body,"#263d35"))).lerp(Color(String(theme.get("floor","#324d42"))),0.14)
	var moss := Color("#365950")
	if body == "flame": moss = Color("#653d33")
	elif body == "frost": moss = Color("#a4baca")
	elif body == "rock": moss = Color("#6b7375")
	elif body == "aqua": moss = Color("#2e6c73")
	StellarModels.part(terrain,"box",Vector3(0,-0.30,0),Vector3(17.1,0.65,13.7),ground.darkened(0.3))
	var soil := StellarModels.part(terrain,"box",Vector3(0,-0.025,0),Vector3(16.8,0.16,13.4),ground)
	var soil_material := ShaderMaterial.new()
	soil_material.shader=preload("res://art/models/terrain.gdshader")
	soil_material.set_shader_parameter("ground_color",ground)
	soil_material.set_shader_parameter("moss_color",moss)
	soil_material.set_shader_parameter("motif_seed",float(absi(id.hash())%1000))
	soil.material_override=soil_material
	# Paths follow exactly both Balance polylines; raised curbs and slabs catch real light.
	for route in range(2):
		var points := Balance.route_points(route)
		for i in range(points.size()-1):
			var a := world(points[i],0.074)
			var b := world(points[i+1],0.074)
			var length := a.distance_to(b)
			var center := (a+b)*0.5
			var along_x := absf(a.x-b.x)>0.01
			StellarModels.part(terrain,"box",center,Vector3(length+0.70,0.095,0.83) if along_x else Vector3(0.83,0.095,length+0.70),Color("#506476"))
			StellarModels.part(terrain,"box",center+Vector3(0,0.048,0),Vector3(length+0.65,0.04,0.69) if along_x else Vector3(0.69,0.04,length+0.65),Color("#6f7e85").lerp(ground,0.20))
			for n in range(int(length/0.45)):
				var p := a.lerp(b,(n+0.5)/maxf(1,int(length/0.45)))+Vector3(0,0.08,0)
				StellarModels.part(terrain,"box",p,Vector3(0.025,0.012,0.65) if along_x else Vector3(0.65,0.012,0.025),Color("#677680"))
		# Entrance beacon, clear warm landmark against cold terrain.
		var gate := world(points[0])
		for side in [-1,1]:
			StellarModels.part(terrain,"cylinder",gate+Vector3(0,0.35,side*0.54),Vector3(0.24,0.7,0.24),Color("#344456"))
			StellarModels.part(terrain,"sphere",gate+Vector3(0,0.80,side*0.54),Vector3(0.19,0.26,0.19),Color("#ffb95f"),0,1.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(id.hash())
	for n in range(114):
		var p := Vector2(rng.randf_range(5,827),rng.randf_range(100,745))
		if _reserved(p,42): continue
		var at := world(p)
		var scale_value := rng.randf_range(0.65,1.3)
		if n % 4 == 0 and body in ["wood","aqua","frost"]:
			_tree(terrain,at,scale_value,moss,body=="frost")
		else:
			StellarModels.part(terrain,"sphere",at+Vector3(0,0.14,0),Vector3(0.52,0.30,0.40)*scale_value,Color("#637682").lerp(moss,0.35),0,0,Vector3(0,rng.randf()*TAU,0.12))
			StellarModels.part(terrain,"sphere",at+Vector3(0,0.29,0),Vector3(0.40,0.11,0.34)*scale_value,moss)
			if body in ["flame","frost"]:
				StellarModels.part(terrain,"cone",at+Vector3(0,0.3,0),Vector3(0.24,0.54,0.23),Color("#fa9546") if body=="flame" else Color("#b8e1ef"),0.15,0.25)
	for n in range(135):
		var p := Vector2(rng.randf_range(25,807),rng.randf_range(116,729))
		if _reserved(p,25): continue
		var at := world(p,0.09)
		StellarModels.part(terrain,"sphere",at,Vector3(rng.randf_range(0.22,0.64),0.035,rng.randf_range(0.17,0.53)),moss.darkened(rng.randf_range(0.1,0.3)))
		for stem in range(2): StellarModels.part(terrain,"cone",at+Vector3(stem*0.06,0.05,0),Vector3(0.035,0.11,0.035),moss.lightened(0.12))
	# Night woodland border makes the scene a diorama rather than a flat rectangle.
	for n in range(30):
		var side := -1.0 if n%2 else 1.0
		var at := Vector3(side*8.2,0,(n/2-7)*0.94)
		_tree(terrain,at,0.69+rng.randf()*0.45,moss.darkened(0.30),body=="frost")
	# A recognizable landmark determined by all 50 existing motif ids, without changing data.
	_landmark(terrain,motif,body,moss,rng)
	# Stone deployment plinths with small amber lanterns, preserving all twelve slots.
	for post in range(Balance.POST_SLOTS):
		var at := world(Balance.post_position(post))
		StellarModels.part(terrain,"cylinder",at+Vector3(0,0.085,0),Vector3(1.12,0.22,1.12),Color("#536779"))
		StellarModels.part(terrain,"cylinder",at+Vector3(0,0.195,0),Vector3(0.91,0.055,0.91),Color("#849492"))
		StellarModels.part(terrain,"ring",at+Vector3(0,0.24,0),Vector3(0.94,0.045,0.94),Color("#a59a76"),0.5)
		var lantern := at+Vector3(-0.45,0.42,0.36)
		StellarModels.part(terrain,"box",lantern,Vector3(0.11,0.30,0.11),Color("#c99a4c"),0.6)
		StellarModels.part(terrain,"sphere",lantern+Vector3(0,0.07,0),Vector3(0.13,0.13,0.13),Color("#ffbd65"),0,1.6)
	# Central life shrine. Lives remain individually visible 3D crystals.
	for ring in range(3):
		StellarModels.part(terrain,"cylinder",Vector3(0,0.10+ring*0.085,0),Vector3(2.23-ring*0.29,0.15,2.23-ring*0.29),Color("#41576b").lightened(ring*0.05))
	StellarModels.part(terrain,"ring",Vector3(0,0.32,0),Vector3(1.89,0.06,1.89),Color("#99d5d9"),0.5,0.3)
	StellarModels.compact(terrain)
	var mist := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(16.8,13.4)
	mist.mesh=plane
	mist.position.y=0.30
	var mist_material := ShaderMaterial.new()
	mist_material.shader=preload("res://art/models/mist.gdshader")
	mist.material_override=mist_material
	mist.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(mist)
	for i in range(Balance.MAX_LIVES):
		var gem := Node3D.new()
		gem.position = world(Balance.ARENA_CENTER+Balance.crystal_slot(i),0.32)
		StellarModels.part(gem,"cone",Vector3(0,0.26,0),Vector3(0.21,0.54,0.21),Color("#79e8f5"),0.35,0.7)
		StellarModels.part(gem,"cone",Vector3(0,0.06,0),Vector3(0.21,0.19,0.21),Color("#49b3d0"),0.35,0.3,Vector3(PI,0,0))
		terrain.add_child(gem)
		crystals.append(gem)
	for post in [0,3,8,11]:
		var lantern_light := OmniLight3D.new()
		lantern_light.position=world(Balance.post_position(post),0.58)+Vector3(-0.4,0,0.32)
		lantern_light.light_color=Color("#ffc875")
		lantern_light.light_energy=0.80
		lantern_light.omni_range=1.9
		terrain.add_child(lantern_light)
	var crystal_light := OmniLight3D.new()
	crystal_light.position = Vector3(0,1.0,0)
	crystal_light.light_color = Color("#6bdcef")
	crystal_light.light_energy = 1.25
	crystal_light.omni_range = 3.5
	terrain.add_child(crystal_light)
	if is_instance_valid(weather): weather.free()
	weather=MultiMeshInstance3D.new()
	weather.multimesh=MultiMesh.new()
	weather.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	weather.multimesh.mesh=StellarModels.primitive("sphere")
	weather.multimesh.instance_count=34
	weather.material_override=StellarModels.material(Color("#b6d6df") if body in ["aqua","frost"] else Color("#e8a45d") if body=="flame" else Color("#839d82"),0,0.2)
	weather.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(weather)
	weather_update(0.0)
	_selected = -2

func weather_update(time: float) -> void:
	if not is_instance_valid(weather): return
	var body := String(Run.theme_for(Run.wave).get("main_body","wood"))
	for n in range(34):
		var x := sin(n*18.3)*7.8
		var z := cos(n*9.8)*6.0
		var y := fposmod(n*0.71-time*(1.0 if body=="aqua" else 0.42),2.7)+0.2
		if body=="flame": y=fposmod(n*0.71+time*0.47,2.7)+0.2
		var size := Vector3(0.012,0.13,0.012) if body=="aqua" else Vector3(0.025,0.025,0.025)
		weather.multimesh.set_instance_transform(n,Transform3D(Basis.from_scale(size),Vector3(x+sin(time+n)*0.14,y,z)))

func _reserved(p: Vector2, distance: float) -> bool:
	if p.distance_to(Balance.ARENA_CENTER)<92: return true
	for post in range(Balance.POST_SLOTS):
		if p.distance_to(Balance.post_position(post))<distance: return true
	for route in range(2):
		var pts := Balance.route_points(route)
		for n in range(pts.size()-1):
			if Geometry2D.get_closest_point_to_segment(p,pts[n],pts[n+1]).distance_to(p)<distance: return true
	return false

func _tree(root: Node3D, at: Vector3, value: float, color: Color, snow: bool) -> void:
	StellarModels.part(root,"cylinder",at+Vector3(0,0.40*value,0),Vector3(0.13,0.8,0.13)*value,Color("#4a4b49"))
	for level in range(3):
		StellarModels.part(root,"cone",at+Vector3(0,(0.68+level*0.34)*value,0),Vector3(0.94-level*0.22,0.88,0.94-level*0.22)*value,color.lightened(level*0.035))
		if snow: StellarModels.part(root,"cone",at+Vector3(0,(0.84+level*0.34)*value,0),Vector3(0.60-level*0.12,0.64,0.60-level*0.12)*value,Color("#c7d4db"))

func _landmark(root: Node3D, motif: String, body: String, moss: Color, rng: RandomNumberGenerator) -> void:
	var at := world(Vector2(221,405))
	var stone := Color("#5e7585")
	var style: int = absi(motif.hash())%5
	if body == "aqua":
		StellarModels.part(root,"sphere",at+Vector3(0,0.08,0),Vector3(1.5,0.05,3.2),Color("#30788c"),0.45)
		for n in range(6): StellarModels.part(root,"cone",at+Vector3(rng.randf_range(-0.6,0.6),0.19,rng.randf_range(-1.5,1.5)),Vector3(0.08,0.47,0.08),moss)
	elif body == "flame":
		for n in range(3):
			StellarModels.part(root,"cone",at+Vector3(0,0.15,n-1),Vector3(1.2,0.6,0.9),stone.darkened(0.3))
			StellarModels.part(root,"sphere",at+Vector3(0,0.36,n-1),Vector3(0.65,0.08,0.57),Color("#f99b50"),0.1,0.7)
	elif body == "wood":
		for n in range(4): _tree(root,at+Vector3(0,0,n*0.67-1),0.75+n*0.1,moss,false)
	elif body == "frost":
		for n in range(6): StellarModels.part(root,"cone",at+Vector3((n%2)*0.5-0.25,0.5,n/2*0.75-1),Vector3(0.49,1.0+n%3*0.23,0.4),Color("#9bc8dc"),0.25)
	else:
		for n in range(3):
			StellarModels.part(root,"box",at+Vector3(0,0.5,n-1),Vector3(0.50,1.0,0.47),stone,0,0,Vector3(0,0.1*n,0))
			StellarModels.part(root,"cone",at+Vector3(0,1.22,n-1),Vector3(0.45,0.50,0.42),Color("#aa8adb"),0.15,0.15)

	# Named landmarks retain the fifty existing map identities as actual geometry.
	var detail := at+Vector3(0.10,0,0)
	match motif:
		"aqueduct", "wall", "ruin", "vine":
			for side in [-1,1]: StellarModels.part(root,"box",detail+Vector3(0,0.45,side*0.84),Vector3(0.50,0.90,0.45),stone)
			StellarModels.part(root,"box",detail+Vector3(0,1.08,0),Vector3(0.60,0.27,2.25),stone.lightened(0.08))
			if motif=="vine":
				for n in range(5): StellarModels.part(root,"sphere",detail+Vector3(0.32,0.41+n*0.12,n*0.27-0.5),Vector3(0.16,0.27,0.18),moss)
		"ship":
			StellarModels.part(root,"sphere",detail+Vector3(0,0.23,0),Vector3(0.96,0.42,2.12),Color("#584d43"))
			StellarModels.link(root,detail+Vector3(0,0.2,0),detail+Vector3(0,1.62,0),0.07,Color("#665a47"))
			StellarModels.part(root,"box",detail+Vector3(0,1.12,0.25),Vector3(0.05,0.80,0.86),Color("#b1b7ad"),0,0,Vector3(0.10,0.13,0))
		"falls", "geyser":
			StellarModels.part(root,"box",detail+Vector3(0,0.68,0),Vector3(0.58,1.35,1.34),stone)
			StellarModels.part(root,"box",detail+Vector3(-0.31,0.63,0),Vector3(0.045,1.23,0.43),Color("#8dc8d5"),0.2,0.10)
		"whirlpool", "trench", "tidal", "ice_lake", "pond", "ice_floe":
			for n in range(3): StellarModels.part(root,"ring",detail+Vector3(0,0.10+n*0.015,0),Vector3(0.74+n*0.20,0.035,1.42+n*0.23),Color("#a5d7df") if motif in ["ice_lake","pond","ice_floe"] else Color("#598897"),0.35)
		"kiln", "forge", "crater", "sulfur", "lava":
			StellarModels.part(root,"cylinder",detail+Vector3(0,0.44,0),Vector3(1.0,0.83,1.32),stone.darkened(0.35))
			StellarModels.part(root,"ring",detail+Vector3(0,0.84,0),Vector3(1.03,0.19,1.32),Color("#7a7466"))
			StellarModels.part(root,"sphere",detail+Vector3(0,0.82,0),Vector3(0.62,0.12,0.98),Color("#f59a48"),0.1,0.8)
			if motif in ["kiln","forge"]: StellarModels.part(root,"cylinder",detail+Vector3(0,1.15,0.55),Vector3(0.28,0.94,0.28),stone.darkened(0.35))
		"burnt", "ash", "field", "obsidian":
			for n in range(4):
				var p := detail+Vector3(0,0,n*0.52-0.75)
				StellarModels.link(root,p,p+Vector3(0,0.91,0.12),0.075,Color("#332f36"))
				StellarModels.link(root,p+Vector3(0,0.55,0),p+Vector3(0.22,0.79,0),0.035,Color("#332f36"))
		"flowers", "mushroom", "moss":
			for n in range(6):
				var p := detail+Vector3((n%2-0.5)*0.67,0,n/2*0.64-0.75)
				StellarModels.part(root,"cylinder",p+Vector3(0,0.22,0),Vector3(0.09,0.45,0.09),Color("#899c73"))
				StellarModels.part(root,"sphere",p+Vector3(0,0.48,0),Vector3(0.44,0.22,0.42),Color("#a47382") if motif=="mushroom" else Color("#e5d4a0"))
		"bamboo", "reeds":
			for n in range(7):
				var p := detail+Vector3((n%2-0.5)*0.53,0,n/2*0.40-0.70)
				StellarModels.part(root,"cylinder",p+Vector3(0,0.54+n%3*0.10,0),Vector3(0.065,1.05+n%3*0.2,0.065),moss.lightened(0.17))
		"root_cave", "worldroot", "thorn":
			for n in range(4):
				StellarModels.part(root,"ring",detail+Vector3(0,0.40,n*0.29-0.45),Vector3(1.02,0.19,0.94),Color("#596456"),0,0,Vector3(PI/2,0,0))
		"mine", "quarry":
			for side in [-1,1]: StellarModels.part(root,"box",detail+Vector3(0,0.53,side*0.46),Vector3(0.19,1.05,0.17),Color("#807565"))
			StellarModels.part(root,"box",detail+Vector3(0,1.06,0),Vector3(0.24,0.21,1.19),Color("#807565"))
			StellarModels.part(root,"sphere",detail+Vector3(0,0.35,0),Vector3(0.74,0.70,0.73),Color("#c2a46a"))
		"terrace", "mesa", "canyon", "cliff", "gorge", "crevasse", "rift":
			for n in range(3): StellarModels.part(root,"box",detail+Vector3(0,0.18+n*0.28,n*0.18-0.2),Vector3(1.24-n*0.22,0.28,1.75-n*0.31),stone.lightened(n*0.06))
		"crystal", "icicle", "spire", "aurora", "blizzard":
			for n in range(4): StellarModels.part(root,"cone",detail+Vector3((n%2-0.5)*0.50,0.57+n%2*0.20,n/2*0.63-0.30),Vector3(0.31,1.14+n%2*0.4,0.30),Color("#a0c9dd") if body=="frost" else Color("#a18fc9"),0.25,0.15)
	# Motif-specific count, footprint, geometry and insignia; not solely a recolor.
	for n in range(style+1):
		var p := world(Vector2(660,305+n*36))
		StellarModels.part(root,"box" if style%2 else "cylinder",p+Vector3(0,0.22+n*0.025,0),Vector3(0.39,0.44+n*0.05,0.39),stone.lerp(moss,0.25),0.1)
		StellarModels.part(root,"sphere",p+Vector3(0,0.48+n*0.05,0),Vector3(0.24,0.18,0.24),Color("#ddbd74"),0.3,0.2)

func sync_heroes(heroes: Array, time: float, battle: bool = false) -> void:
	var keep: Dictionary = {}
	for i in range(heroes.size()):
		var data: Dictionary = heroes[i]
		var hero: Dictionary = data["h"] if battle else data
		var id := String(hero["unit"]["id"])
		var grade := int(hero["tier"])
		var key := "%d:%s:%d"%[i,id,grade]
		keep[key] = true
		if not hero_nodes.has(key):
			var model := StellarModels.hero(hero["unit"],grade)
			actors.add_child(model)
			hero_nodes[key] = model
		var node: Node3D = hero_nodes[key]
		var p: Vector2 = data["pos"] if battle else Balance.post_position(int(hero.get("post",i)))
		node.position = world(p,0.23)
		var direction: Vector2 = data.get("fx_d",Vector2(0,1)) if battle else Vector2(0,1)
		if direction.length_squared()>0.001: node.rotation.y = atan2(-direction.x,-direction.y)
		var ft := float(data.get("fx_t",9))
		var wind := maxf(0.04,float(data.get("fx_w",0.35)))
		var attack := 0.0
		if battle and ft<wind+0.22:
			attack = ft/wind if ft<=wind else maxf(0,1-(ft-wind)/0.22)
		var body: Node3D = node.get_node("Body")
		body.rotation.x = -attack*0.11
		body.position.y = sin(time*2.7+i)*0.012
		for side in ["L","R"]:
			var arm: Node3D = node.get_node("Arm"+side)
			arm.rotation.x = -attack*(2.50 if String(hero["unit"].get("bullet",""))=="zone" else 1.30)
			arm.rotation.z = sin(time*2.7+i)*0.018
	for key in hero_nodes.keys():
		if not keep.has(key):
			hero_nodes[key].free()
			hero_nodes.erase(key)

func sync_battle(sim, time: float, lives: int, dt: float = 0.016) -> void:
	sync_heroes(sim.heroes,time,true)
	weather_update(time)
	var keep: Dictionary = {}
	for mo in sim.monsters:
		var key: int = int(mo.get("spawn_id", 0))
		if key == 0:
			key = int(float(mo.get("motion_phase", 0.0)) * 1000000) + int(mo.get("route", 0)) * 1000001
		keep[key] = true
		if not monster_nodes.has(key):
			var model := StellarModels.monster(mo["m"])
			actors.add_child(model)
			monster_nodes[key] = model
		var node: Node3D = monster_nodes[key]
		var p := BattleSim.mpos(mo)
		var ahead := Balance.path_at(float(mo["s"])+4,float(mo["off"]),int(mo.get("route",0)))
		var d := ahead-p
		node.position = world(p,0.14+sin(time*10+key)*0.035)
		if d.length_squared()>0.001: node.rotation.y = atan2(-d.x,-d.y)
		node.rotation.z = sin(time*10+key)*0.035
		node.get_node("StellarBurn").visible=float(mo.get("burn_t",0))>0
		node.get_node("StellarFrost").visible=float(mo.get("slow_t",0))>0
		node.get_node("StellarStun").visible=float(mo.get("stun_t",0))>0
		node.get_node("StellarBurn").scale=Vector3.ONE*(0.9+sin(time*18+key)*0.13)
		node.get_node("StellarStun").rotation.y=time*5
		if float(mo.get("stun_t",0))>0: node.rotation.z = sin(time*35+key)*0.025
	for key in monster_nodes.keys():
		if not keep.has(key):
			monster_nodes[key].free()
			monster_nodes.erase(key)
	while bullet_nodes.size()<mini(120,sim.bullets.size()):
		var bullet := Node3D.new()
		StellarModels.part(bullet,"sphere",Vector3.ZERO,Vector3(0.10,0.10,0.22),Color("#fff4c6"),0,1.2)
		projectiles.add_child(bullet)
		bullet_nodes.append(bullet)
	for i in range(bullet_nodes.size()):
		var node: Node3D = bullet_nodes[i]
		node.visible = i<sim.bullets.size()
		if not node.visible: continue
		var b: Dictionary = sim.bullets[i]
		node.position = world(b["p"],0.64)
		var d: Vector2 = b["v"]
		if d.length_squared()>0.01: node.rotation.y = atan2(-d.x,-d.y)
		var geometry: MeshInstance3D = node.get_child(0)
		geometry.material_override = StellarModels.material(b["c"],0,0.9)
		geometry.scale = Vector3(0.12,0.12,0.33) if String(b["kind"])=="pierce" else Vector3(0.16,0.16,0.16) if String(b["kind"])=="splash" else Vector3(0.095,0.095,0.17)
	for i in range(crystals.size()): crystals[i].visible = i<lives
	while zone_nodes.size()<mini(24,sim.zones.size()):
		var zone := Node3D.new()
		for n in range(9):
			var a := n*TAU/9
			StellarModels.part(zone,"cone",Vector3(cos(a)*0.66,0.06,sin(a)*0.66),Vector3(0.13,0.33,0.13),Color("#acd6dd"),0.1,0.4)
		StellarModels.compact(zone)
		add_child(zone)
		zone_nodes.append(zone)
	for i in range(zone_nodes.size()):
		var node: Node3D=zone_nodes[i]
		node.visible=i<sim.zones.size()
		if not node.visible: continue
		var zone: Dictionary=sim.zones[i]
		node.position=world(zone["at"],0.16)
		var radius := float(zone["r"])/UNIT
		node.scale=Vector3(radius,0.55+sin(time*12+i)*0.15,radius)
		node.rotation.y=time*0.7
		for child in node.get_children(): child.material_override=StellarModels.material(zone["c"],0.1,0.45)
	update_effects(dt)

func set_selection(post: int, available: bool, radius: float = 0.0) -> void:
	var occupied := ""
	for hero in Run.heroes: occupied += str(hero.get("post",-1))+","
	if post==_selected and available==_available and is_equal_approx(radius,_range) and occupied==_occupied: return
	_selected=post
	_available=available
	_range=radius
	_occupied=occupied
	_clear(selection)
	for i in range(Balance.POST_SLOTS):
		var color := Color("#ffe0a1") if i==post else Color("#9ce9e4")
		if i==post or available:
			StellarModels.part(selection,"ring",world(Balance.post_position(i),0.265),Vector3(1.15,0.055,1.15),color,0.25,0.55)
		if Run.hero_at_post(i)<0:
			var p := world(Balance.post_position(i),0.27)
			StellarModels.part(selection,"box",p,Vector3(0.34,0.025,0.065),Color("#c6cdb8"),0.25)
			StellarModels.part(selection,"box",p,Vector3(0.065,0.025,0.34),Color("#c6cdb8"),0.25)
	if post>=0 and radius>0:
		var origin := Balance.post_position(post)
		for n in range(64):
			var a := origin+Vector2.from_angle(TAU*n/64.0)*radius
			var b := origin+Vector2.from_angle(TAU*(n+0.65)/64.0)*radius
			if Balance.MAP_RECT.has_point(a) and Balance.MAP_RECT.has_point(b): StellarModels.link(selection,world(a,0.18),world(b,0.18),0.035,Color("#ebc77f"),0.2,0.5)
	StellarModels.compact(selection)

func event(e: Dictionary) -> void:
	var type := String(e.get("t",""))
	if type in ["hit","zone_tick"] and e.has("n") and _text_gap<=0 and texts.size()<24:
		texts.append({"p":Vector2(e.get("mp",e.get("p",Vector2.ZERO))),"n":float(e["n"]),"color":Color("#ffd390") if bool(e.get("big",false)) else Color("#e5f4f6"),"age":0.0,"big":bool(e.get("big",false))})
		_text_gap=0.07
	if effects.size()>=72: return
	if type in ["beam","bolt","ric"]:
		var a: Vector2 = e.get("a",Vector2.ZERO)
		var b: Vector2 = e.get("b",Vector2.ZERO)
		var node := Node3D.new()
		var color: Color = e.get("c",Color("#b4deff"))
		StellarModels.link(node,world(a,0.74),world(b,0.53),0.065 if type=="beam" else 0.035,color,0.1,1.2)
		add_child(node)
		effects.append({"node":node,"age":0.0,"life":0.20,"kind":"beam"})
	elif type in ["hit","splash","zone_tick","die","leak","block","wildfire"]:
		var node := Node3D.new()
		var p: Vector2 = e.get("p",Vector2.ZERO)
		node.position=world(p,0.25)
		var color: Color = e.get("c",Color("#eacb81"))
		var radius := float(e.get("r",22.0))/UNIT
		for i in range(5 if type=="die" else 3):
			var a := TAU*i/5.0
			StellarModels.part(node,"cone",Vector3(sin(a)*radius*0.34,0.2,cos(a)*radius*0.34),Vector3(0.08,0.42,0.08),color,0,0.9,Vector3(cos(a)*0.6,0,-sin(a)*0.6))
		add_child(node)
		effects.append({"node":node,"age":0.0,"life":0.33,"kind":"burst"})

func update_effects(dt: float) -> void:
	_text_gap=maxf(0,_text_gap-dt)
	for i in range(texts.size()-1,-1,-1):
		texts[i]["age"]+=dt
		if texts[i]["age"]>0.65: texts.remove_at(i)
	for i in range(effects.size()-1,-1,-1):
		var fx: Dictionary = effects[i]
		fx["age"] += dt
		if fx["age"]>=fx["life"]:
			fx["node"].free()
			effects.remove_at(i)
		elif fx["kind"]=="burst":
			fx["node"].scale=Vector3.ONE*(1.0+fx["age"]*2.0)
