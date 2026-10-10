extends StellarWorld
class_name ArenaWorld

## Arena visuals adapt the existing real models; simulation owns every position.
var _walk: Dictionary = {}
var _ward: Node3D
var _ward_material: StandardMaterial3D
var _crystal_light: OmniLight3D
var _weather_body := "wood"

func camera_update() -> void:
	# Constant magnification: enlarging the arena never shrinks its actors.
	camera.size = 26.0
	camera.position = camera_target + Vector3(-3.0, 19.0, 23.0)
	camera.look_at(camera_target + Vector3(0, 0.4, 0), Vector3.UP)

func _ready() -> void:
	super._ready()
	StellarLighting.apply_arena(self)

func build_map(theme: Dictionary) -> void:
	var id := String(theme.get("id", "wood"))
	if id == theme_id: return
	theme_id = id
	_clear(terrain)
	crystals.clear()
	var body := String(theme.get("main_body", "wood"))
	_weather_body = body
	var snowy := body in ["aqua", "frost"]
	var radius := ArenaGeometry.RADIUS / UNIT
	var palette := {"aqua":"#16445a", "flame":"#342d38", "wood":"#223e40", "rock":"#384653", "frost":"#24506a"}
	var ground := Color(String(palette.get(body, "#223e40")))
	var moss := Color("#597779")
	if body == "flame": moss = Color("#756260")
	elif snowy: moss = Color("#7596b2")
	elif body == "rock": moss = Color("#80909b")
	# A continuous woodland apron replaces the empty blue border of a floating board.
	var woodland := StellarModels.part(terrain, "box", Vector3(0, -0.66, 0), Vector3(72, 0.65, 60), Color("#102331"))
	var woodland_material := ShaderMaterial.new()
	woodland_material.shader = preload("res://art/models/arena_ground.gdshader")
	woodland_material.set_shader_parameter("ground_color", Color("#122c3c"))
	woodland_material.set_shader_parameter("edge_color", Color("#254255"))
	woodland_material.set_shader_parameter("half_extent", Vector2(36, 30))
	woodland_material.set_shader_parameter("frozen", 0.0)
	woodland_material.set_shader_parameter("motif_seed", 27.0)
	woodland.material_override = woodland_material
	var soil := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.15
	disc.radial_segments = 128
	soil.mesh = disc
	soil.position.y = -0.06
	terrain.add_child(soil)
	var soil_material := ShaderMaterial.new()
	soil_material.shader = preload("res://art/models/arena_ground.gdshader")
	soil_material.set_shader_parameter("ground_color", ground)
	soil_material.set_shader_parameter("edge_color", moss)
	soil_material.set_shader_parameter("field_radius", radius)
	soil_material.set_shader_parameter("frozen", 1.0 if snowy else 0.08)
	soil_material.set_shader_parameter("motif_seed", float(absi(id.hash()) % 1000))
	soil.material_override = soil_material
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(id.hash())
	# The 128-sided disc and stone arc use the same radius as movement and lanes.
	for n in range(96):
		var angle := TAU * (n + 0.5) / 96.0
		if _gate_near(angle, 0.12): continue
		var at := Vector3(cos(angle) * (radius + 0.16), -0.14, sin(angle) * (radius + 0.16))
		var turn := Vector3(0, -angle - PI / 2, 0)
		var width := TAU * radius / 96.0 - 0.015
		StellarModels.part(terrain, "stone", at, Vector3(width, 0.48, 0.40), Color("#425b71").lightened((n % 3) * 0.035), 0, 0, turn)
		if snowy: StellarModels.part(terrain, "stone", at + Vector3(0, 0.25, 0), Vector3(width + 0.01, 0.07, 0.44), moss, 0, 0, turn)
	for lane in range(ArenaGeometry.ROUTE_COUNT): _arena_road(ArenaGeometry.route_points(lane), snowy)
	var plaza := MeshInstance3D.new()
	var plaza_disc := CylinderMesh.new()
	plaza_disc.top_radius = ArenaGeometry.PLAZA_RADIUS / UNIT
	plaza_disc.bottom_radius = plaza_disc.top_radius
	plaza_disc.height = 0.018
	plaza_disc.radial_segments = 96
	plaza.mesh = plaza_disc
	plaza.position.y = 0.037
	var plaza_material := ShaderMaterial.new()
	plaza_material.shader = preload("res://art/models/arena_road.gdshader")
	plaza_material.set_shader_parameter("road_color", Color("#536f7b") if snowy else Color("#6b7774"))
	plaza_material.set_shader_parameter("field_radius", radius)
	plaza_material.set_shader_parameter("plaza", true)
	plaza.material_override = plaza_material
	plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(plaza)
	# Woodland follows concentric irregular arcs; foreground trees stay off the rim.
	for n in range(150):
		var at := Vector3(rng.randf_range(-radius - 15, radius + 15), -0.32, rng.randf_range(-radius - 13, radius + 13))
		var distance := Vector2(at.x, at.z).length() - radius
		if distance < 2.3: continue
		var value := rng.randf_range(0.95, 1.85) if distance > 4 else rng.randf_range(0.65, 1.0)
		_fir(terrain, at, value, snowy, n % 3)
		if n % 3 == 0:
			StellarModels.part(terrain, "stone", at + Vector3(0.7, 0.18, 0.3), Vector3(1.35, 0.85, 1.15) * value, Color("#344c62"), 0, 0, Vector3(0.1, n, 0.15))
			if snowy: StellarModels.part(terrain, "sphere", at + Vector3(0.7, 0.59, 0.3), Vector3(1.25, 0.16, 1.05) * value, moss)
	for n in range(68):
		var angle := n * TAU / 68.0
		if _gate_near(angle, 0.16): continue
		var distance := radius + 1.8 + (n % 3) * 0.28
		var at := Vector3(cos(angle) * distance, -0.20, sin(angle) * distance)
		_fir(terrain, at, 0.62 + (n % 3) * 0.12, snowy, n % 3)
	for n in range(30):
		var angle := n * TAU / 30.0
		if _gate_near(angle, 0.18): continue
		var at := Vector3(cos(angle) * (radius + 3.4), -0.39, sin(angle) * (radius + 3.4))
		var stone := Vector3(1.4 + (n % 3) * 0.36, 0.65 + (n % 4) * 0.20, 1.6)
		StellarModels.part(terrain, "stone", at, stone, Color("#2c435b"), 0, 0, Vector3(0.07, n * 0.7, 0.1))
		if snowy: StellarModels.part(terrain, "sphere", at + Vector3(0, stone.y * 0.5, 0), Vector3(stone.x * 0.82, 0.10, stone.z * 0.88), Color("#68869c"))
	for n in range(43):
		var angle := rng.randf() * TAU
		if _gate_near(angle, 0.14): continue
		var distance := radius - rng.randf_range(0.2, 0.7)
		var at := Vector3(cos(angle) * distance, 0.06, sin(angle) * distance)
		StellarModels.part(terrain, "stone", at, Vector3(0.14 + (n % 3) * 0.06, 0.10, 0.12 + (n % 4) * 0.04), moss, 0.05)
	# Preserve each theme's authored landmark, relocated outside the larger arena.
	var landmark := Node3D.new()
	terrain.add_child(landmark)
	_landmark(landmark, String(Scenery.MAP_MOTIFS.get(id, "gravel")), body, moss, rng)
	for part in landmark.get_children():
		if part is Node3D:
			part.position.x += (-radius - 2.8 + 8.6) * (-1 if part.position.x > 0 else 1)
	for ring in range(3):
		StellarModels.part(terrain, "cylinder", Vector3(0, 0.07 + ring * 0.075, 0), Vector3(2.30 - ring * 0.24, 0.14, 2.30 - ring * 0.24), Color("#405a72").lightened(ring * 0.07), 0.1)
	for n in range(12):
		var angle := n * TAU / 12.0
		StellarModels.part(terrain, "stone", Vector3(cos(angle) * 1.05, 0.11, sin(angle) * 1.05), Vector3(0.47, 0.22, 0.33), Color("#7896ad"), 0.12, 0, Vector3(0, -angle + PI / 2, 0))
		var rune := Vector3(cos(angle) * 0.74, 0.28, sin(angle) * 0.74)
		StellarModels.part(terrain, "box", rune, Vector3(0.055, 0.013, 0.12), Color("#a2ecff"), 0.2, 0.7, Vector3(0, -angle, 0))
	StellarModels.part(terrain, "ring", Vector3(0, 0.27, 0), Vector3(1.8, 0.035, 1.8), Color("#94e8fa"), 0.3, 0.55)
	var lamp_positions: Array[Vector3] = []
	for lane in range(ArenaGeometry.ROUTE_COUNT):
		var entry := world(ArenaGeometry.route_points(lane)[0])
		var radial := Vector3(entry.x, 0, entry.z).normalized()
		var tangent := Vector3(-radial.z, 0, radial.x)
		var at := radial * (radius + 0.85) + tangent * 1.35
		_sanctuary_lantern(terrain, at, snowy)
		lamp_positions.append(at)
	StellarModels.compact(terrain)
	var crystal := Node3D.new()
	crystal.position = Vector3(0, 0.30, 0)
	var shard := MeshInstance3D.new()
	shard.mesh = _crystal_mesh()
	shard.material_override = StellarModels.material(Color("#4bd8ff"), 0.38, 0.31)
	crystal.add_child(shard)
	for n in range(6):
		var angle := n * TAU / 6.0
		var point := Vector3(cos(angle) * 0.332, 0.68, sin(angle) * 0.332)
		StellarModels.link(crystal, Vector3(0, 1.65, 0), point, 0.012, Color("#bef8ff"), 0, 0.5)
		StellarModels.link(crystal, point, Vector3(0, 0.01, 0), 0.009, Color("#79e7ff"), 0, 0.3)
	for n in range(5):
		var angle := n * TAU / 5
		StellarModels.part(crystal, "cone", Vector3(cos(angle) * 0.29, 0.18, sin(angle) * 0.29), Vector3(0.15, 0.49, 0.15), Color("#83e9ff"), 0.28, 0.46, Vector3(0.14 * cos(angle), 0, 0.14 * sin(angle)))
	terrain.add_child(crystal)
	crystals.append(crystal)
	_ward = Node3D.new()
	var ward_ring := StellarModels.part(_ward, "ring", Vector3(0, 0.10, 0), Vector3(2.4, 0.08, 2.4), Look.CRYSTAL, 0, 0.6)
	_ward_material = StellarModels.material(Color("#90eafa"), 0.0, 0.4).duplicate()
	_ward_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ward_material.albedo_color.a = 0.2
	var ward_shell := StellarModels.part(_ward, "sphere", Vector3(0, 0.82, 0), Vector3(2.15, 2.8, 2.15), Look.CRYSTAL)
	ward_shell.material_override = _ward_material
	ward_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ward_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ward.visible = false
	terrain.add_child(_ward)
	_crystal_light = OmniLight3D.new()
	_crystal_light.position = Vector3(0, 1.3, 0)
	_crystal_light.light_color = Color("#62dfff")
	_crystal_light.light_energy = 1.55
	_crystal_light.omni_range = 4.4
	terrain.add_child(_crystal_light)
	for at in lamp_positions:
		var light := OmniLight3D.new()
		light.position = at + Vector3(0, 1.15, 0)
		light.light_color = Color("#ffc57b")
		light.light_energy = 2.3
		light.omni_range = 4.8
		terrain.add_child(light)
	if is_instance_valid(weather): weather.free()
	weather = MultiMeshInstance3D.new()
	weather.multimesh = MultiMesh.new()
	weather.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# Soft camera-facing motes (snow / embers / pollen) instead of lit micro-spheres.
	weather.multimesh.mesh = QuadMesh.new()
	weather.multimesh.instance_count = 56
	var weather_material := ShaderMaterial.new()
	weather_material.shader = preload("res://art/vfx/weather.gdshader")
	weather_material.set_shader_parameter("sprites", preload("res://art/vfx/sprites.png"))
	weather_material.set_shader_parameter("tint", Color("#d5ecf8") if snowy else Color("#ffb066") if body == "flame" else Color("#a9c9c6"))
	weather_material.set_shader_parameter("brightness", 0.5 if snowy else 0.42)
	weather.material_override = weather_material
	weather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weather.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 12, 80))
	add_child(weather)
	weather_update(0)

func _gate_near(angle: float, half_angle: float) -> bool:
	for lane in range(ArenaGeometry.ROUTE_COUNT):
		var at := ArenaGeometry.route_points(lane)[0] - Balance.ARENA_CENTER
		if absf(wrapf(angle - at.angle(), -PI, PI)) < half_angle: return true
	return false

func _arena_road(route: PackedVector2Array, snowy: bool) -> void:
	if route.size() < 2: return
	var points := route.duplicate()
	# The visual entrance fills the route's round end cap up to the circular rim.
	points.insert(0, Balance.ARENA_CENTER + (points[0] - Balance.ARENA_CENTER).normalized() * ArenaGeometry.RADIUS)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var half_width := ArenaGeometry.ROAD_WIDTH / (UNIT * 2)
	for i in range(points.size() - 1):
		var a := world(points[i], 0.029)
		var b := world(points[i + 1], 0.029)
		var tangent_a := (world(points[mini(i + 1, points.size() - 1)]) - world(points[maxi(0, i - 1)])).normalized()
		var tangent_b := (world(points[mini(i + 2, points.size() - 1)]) - world(points[i])).normalized()
		var normal_a := Vector3(-tangent_a.z, 0, tangent_a.x) * half_width
		var normal_b := Vector3(-tangent_b.z, 0, tangent_b.x) * half_width
		var length := a.distance_to(b)
		var vertices: Array[Vector3] = [a - normal_a, a + normal_a, b + normal_b, b - normal_b]
		var coords: Array[Vector2] = [Vector2(along, 0), Vector2(along, 1), Vector2(along + length, 1), Vector2(along + length, 0)]
		for index in [0, 2, 1, 0, 3, 2]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(coords[index])
			surface.add_vertex(vertices[index])
		along += length
	var road := MeshInstance3D.new()
	road.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://art/models/arena_road.gdshader")
	material.set_shader_parameter("road_color", Color("#536f7b") if snowy else Color("#6b7774"))
	material.set_shader_parameter("field_radius", ArenaGeometry.RADIUS / UNIT)
	road.material_override = material
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(road)

func _fir(root: Node3D, at: Vector3, value: float, snow: bool, tone: int) -> void:
	var needles: Color = [Color("#193a4e"), Color("#21465b"), Color("#2a5062")][tone]
	var snow_color: Color = [Color("#64859f"), Color("#7899b3"), Color("#8faac0")][tone]
	StellarModels.part(root, "cylinder", at + Vector3(0, 1.0 * value, 0), Vector3(0.13, 2.0, 0.13) * value, Color("#344650"))
	for level in range(4):
		var width := (1.35 - level * 0.24) * value
		var y := (0.64 + level * 0.42) * value
		var rot := Vector3(0, level * 0.49 + at.z, 0)
		StellarModels.part(root, "cone", at + Vector3(0, y + 0.30 * value, 0), Vector3(width, 0.95 * value, width), needles, 0, 0, rot)
		for branch in range(5):
			var angle := branch * TAU / 5.0 + level * 0.8
			var offset := Vector3(cos(angle), 0, sin(angle)) * width * 0.33
			StellarModels.part(root, "cone", at + offset + Vector3(0, y + 0.10 * value, 0), Vector3(width * 0.53, 0.43 * value, width * 0.53), needles, 0, 0, rot)
			if snow:
				StellarModels.part(root, "cone", at + offset * 0.86 + Vector3(0, y + 0.20 * value, 0), Vector3(width * 0.45, 0.36 * value, width * 0.45), snow_color, 0, 0, rot)
		if snow: StellarModels.part(root, "cone", at + Vector3(0, y + 0.50 * value, 0), Vector3(width * 0.71, 0.76 * value, width * 0.71), snow_color, 0, 0, rot)

func _sanctuary_lantern(root: Node3D, at: Vector3, snow: bool) -> void:
	var stone := Color("#657c91")
	StellarModels.part(root, "stone", at + Vector3(0, 0.12, 0), Vector3(0.76, 0.24, 0.76), stone)
	StellarModels.part(root, "stone", at + Vector3(0, 0.48, 0), Vector3(0.43, 0.66, 0.43), stone.darkened(0.14))
	StellarModels.part(root, "stone", at + Vector3(0, 0.84, 0), Vector3(0.61, 0.12, 0.61), stone)
	StellarModels.part(root, "box", at + Vector3(0, 1.11, 0), Vector3(0.29, 0.42, 0.29), Color("#ffb34e"), 0, 0.85)
	for x in [-1, 1]:
		for z in [-1, 1]: StellarModels.part(root, "box", at + Vector3(x * 0.2, 1.11, z * 0.2), Vector3(0.055, 0.47, 0.055), Color("#766e61"), 0.35)
	StellarModels.part(root, "cone", at + Vector3(0, 1.47, 0), Vector3(0.83, 0.36, 0.83), Color("#a3b7c7") if snow else stone, 0.15, 0, Vector3(0, PI / 4, 0))
	StellarModels.part(root, "sphere", at + Vector3(0, 1.71, 0), Vector3(0.10, 0.16, 0.10), Color("#d2bd91"), 0.4)

func _crystal_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in range(6):
		var a := TAU * n / 6.0
		var b := TAU * (n + 1) / 6.0
		var v1 := Vector3(cos(a) * 0.33, 0.68, sin(a) * 0.33)
		var v2 := Vector3(cos(b) * 0.33, 0.68, sin(b) * 0.33)
		for triangle in [[Vector3(0, 1.65, 0), v2, v1], [Vector3(0, 0.01, 0), v1, v2]]:
			var normal: Vector3 = (triangle[2] - triangle[0]).cross(triangle[1] - triangle[0]).normalized()
			for vertex in triangle:
				surface.set_normal(normal)
				surface.add_vertex(vertex)
	return surface.commit()

func weather_update(time: float) -> void:
	if not is_instance_valid(weather): return
	var half := ArenaGeometry.MAP_RECT.size / (UNIT * 2.0)
	for n in range(weather.multimesh.instance_count):
		var x := sin(n * 18.3) * (half.x + 2)
		var z := cos(n * 9.8) * (half.y + 2)
		var y := fposmod(n * 0.71 - time * 0.35, 4.0) + 0.2
		if _weather_body == "flame": y = fposmod(n * 0.71 + time * 0.47, 4.0) + 0.2
		var size := Vector3.ONE * (0.07 + (n % 3) * 0.03)
		weather.multimesh.set_instance_transform(n, Transform3D(Basis.from_scale(size), Vector3(x + sin(time * 0.4 + n) * 0.35, y, z)))

func sync_heroes(heroes: Array, time: float, battle: bool = false) -> void:
	# Adapters without their own locomotion still receive the legacy additive gait.
	# Remove the previous frame's deltas before clips are sampled: AnimationPlayer
	# can skip constant translation tracks on seek, so adding to their last pose
	# each frame makes legs stretch upward indefinitely (also on paused redraws).
	for key in _walk:
		if not hero_nodes.has(key): continue
		var node: Node3D = hero_nodes[key]
		if node.has_method("set_locomotion"): continue
		var track: Dictionary = _walk[key]
		var skeleton: Skeleton3D = track.get("skeleton")
		if is_instance_valid(skeleton):
			var poses: Dictionary = track.get("base_poses", {})
			for bone in poses: skeleton.set_bone_pose(int(bone), poses[bone])
		if node is LimneModel:
			var rests: Dictionary = track.get("leg_rests", {})
			for side in rests: node.get_node("Leg" + side).transform = rests[side]
	# Locomotion input comes from simulation positions only; the simulator never
	# learns about it. Velocity is in world units per second, dt is the simulated
	# interval since the previous rendered sample (0 on paused redraws).
	_hero_motion.clear()
	var keep: Dictionary = {}
	for i in range(heroes.size()):
		var data: Dictionary = heroes[i]
		var hero: Dictionary = data["h"] if battle else data
		var key := "%d:%s:%d" % [i, hero["unit"]["id"], int(hero["tier"])]
		keep[key] = true
		if not battle: continue
		var p: Vector2 = data["pos"]
		var track: Dictionary = _walk.get(key, {"p": p, "time": time, "phase": 0.0, "v": Vector3.ZERO, "walking": false})
		var delta: Vector2 = p - Vector2(track["p"])
		var elapsed := maxf(0.0, time - float(track["time"]))
		var moved := delta.length() > 0.025 and delta.length() < 70
		if elapsed > 0.00001:
			track["walking"] = moved
			track["v"] = Vector3(delta.x, 0, delta.y) / (UNIT * elapsed) if moved else Vector3.ZERO
			if moved:
				track["direction"] = delta
				track["phase"] = float(track["phase"]) + delta.length() * 0.11
		var walking := bool(track["walking"])
		var attacking := float(data.get("fx_t", 9.0)) <= float(data.get("fx_w", 0.0)) + 0.3
		_hero_motion[i] = {"v": track["v"], "dt": elapsed, "walking": walking,
			"dir": Vector2(track.get("direction", Vector2.DOWN)) if walking and not attacking else Vector2.INF}
		track["p"] = p
		track["time"] = time
		_walk[key] = track
	super.sync_heroes(heroes, time, battle)
	for i in range(heroes.size()):
		var data: Dictionary = heroes[i]
		var hero: Dictionary = data["h"] if battle else data
		var key := "%d:%s:%d" % [i, hero["unit"]["id"], int(hero["tier"])]
		if not hero_nodes.has(key) or not _walk.has(key): continue
		var node: Node3D = hero_nodes[key]
		if node.has_method("set_locomotion"): continue
		var track: Dictionary = _walk[key]
		if not track.has("skeleton"): track["skeleton"] = _find_skeleton(node)
		if node is LimneModel and not track.has("leg_rests"):
			track["leg_rests"] = {"L": node.get_node("LegL").transform, "R": node.get_node("LegR").transform}
		track["base_poses"] = {}
		if not bool(track.get("walking", false)): continue
		var phase := float(track["phase"])
		var skeleton: Skeleton3D = track["skeleton"]
		if skeleton != null and not node is LimneModel:
			for side in ["L", "R"]:
				var bone := skeleton.find_bone("SkinLeg" + side)
				if bone < 0: bone = skeleton.find_bone("Leg" + side)
				if bone < 0: continue
				track["base_poses"][bone] = skeleton.get_bone_pose(bone)
				var wave := sin(phase + (0.0 if side == "L" else PI))
				skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(Vector3.RIGHT, wave * 0.29))
				var shift := skeleton.get_bone_pose_position(bone)
				shift.y += maxf(0.0, wave) * 0.045
				skeleton.set_bone_pose_position(bone, shift)
			if node.has_method("_sync_controls_from_skin"): node.call("_sync_controls_from_skin")
		if node is LimneModel:
			for side in ["L", "R"]:
				var leg: Node3D = node.get_node("Leg" + side)
				leg.rotation.x += sin(phase + (0.0 if side == "L" else PI)) * 0.29
			node.update_visuals()
		node.position.y += absf(sin(phase)) * 0.025
	for key in _walk.keys():
		if not keep.has(key): _walk.erase(key)

func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D: return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null: return found
	return null

func _monster_heading(mo: Dictionary, p: Vector2, _ahead: Vector2) -> Vector2:
	var velocity: Vector2 = mo.get("vel", Vector2.ZERO)
	if velocity.length_squared() > 0.001: return velocity
	return Balance.ARENA_CENTER - p

func sync_battle(sim, time: float, lives: int, dt: float = 0.016) -> void:
	super.sync_battle(sim, time, lives, dt)
	for crystal in crystals: crystal.visible = sim.crystal_hp > 0
	if is_instance_valid(_ward): _ward.visible = sim.shield > 0
	if is_instance_valid(_crystal_light):
		_crystal_light.light_energy = 0.35 + 0.75 * clampf(sim.crystal_hp / maxf(1, sim.crystal_max), 0, 1)

func set_selection(at: Vector2, available: bool, radius: float = 0.0) -> void:
	selection.visible = at.is_finite()
	if not at.is_finite(): return
	selection.position = world(at, 0.10)
	if is_equal_approx(radius, _range) and selection.get_child_count() > 0: return
	_range = radius
	_clear(selection)
	StellarModels.part(selection, "ring", Vector3.ZERO, Vector3(1.0, 0.038, 1.0), Color("#ffe0a1"), 0.25, 0.35)
	for side in [-1, 1]:
		StellarModels.part(selection, "cone", Vector3(side * 0.54, 0.09, 0), Vector3(0.10, 0.16, 0.10), Color("#ffe0a1"), 0, 0.3)
	if radius > 0:
		for n in range(56):
			var a := Vector3(cos(TAU * n / 56.0), 0.035, sin(TAU * n / 56.0)) * (radius / UNIT)
			var b := Vector3(cos(TAU * (n + 0.55) / 56.0), 0.035, sin(TAU * (n + 0.55) / 56.0)) * (radius / UNIT)
			StellarModels.link(selection, a, b, 0.019, Color("#ebc77f"), 0.1, 0.15)
	StellarModels.compact(selection)

func event(e: Dictionary) -> void:
	var type := String(e.get("t", ""))
	if type == "arena_crystal_hit":
		if float(e.get("n", 0.0)) > 0:
			super.event({"t": "leak", "p": Balance.ARENA_CENTER, "c": Look.RED, "r": 42.0})
		return
	if type in ["arena_blast", "arena_freeze", "arena_ward"]:
		vfx.arena_event(e)
		return
	super.event(e)
