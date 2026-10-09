extends StellarWorld
class_name ArenaWorld

## Arena visuals adapt the existing real models; simulation owns every position.
var _walk: Dictionary = {}
var _ward: Node3D
var _ward_material: StandardMaterial3D
var _crystal_light: OmniLight3D
var _skill_fx: Array[Dictionary] = []
var _weather_body := "wood"
var _skill_ring: TorusMesh

func camera_update() -> void:
	# Fixed overview. Fit all four spawn edges even in the wide battle viewport.
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(1.0, size.y)
	camera.size = maxf(19.4, 12.4 * aspect)
	camera.position = Vector3(-3.0, 19.0, 23.0)
	camera.look_at(Vector3(0, 0.4, 0), Vector3.UP)

func build_map(theme: Dictionary) -> void:
	var id := String(theme.get("id", "wood"))
	if id == theme_id: return
	theme_id = id
	_clear(terrain)
	crystals.clear()
	var body := String(theme.get("main_body", "wood"))
	_weather_body = body
	var palette := {"aqua":"#253e46", "flame":"#3e3239", "wood":"#263d35", "rock":"#424041", "frost":"#5b6d7b"}
	var ground := Color(String(palette.get(body, "#263d35"))).lerp(Color(String(theme.get("floor", "#324d42"))), 0.14)
	var moss := Color("#496953")
	if body == "flame": moss = Color("#653d33")
	elif body == "frost": moss = Color("#a4baca")
	elif body == "rock": moss = Color("#6b7375")
	elif body == "aqua": moss = Color("#2e6c73")
	StellarModels.part(terrain, "box", Vector3(0, -0.31, 0), Vector3(17.1, 0.62, 13.7), ground.darkened(0.3))
	var soil := StellarModels.part(terrain, "box", Vector3(0, -0.04, 0), Vector3(16.8, 0.16, 13.4), ground)
	var soil_material := ShaderMaterial.new()
	soil_material.shader = preload("res://art/models/terrain.gdshader")
	soil_material.set_shader_parameter("ground_color", ground)
	soil_material.set_shader_parameter("moss_color", moss)
	soil_material.set_shader_parameter("motif_seed", float(absi(id.hash()) % 1000))
	soil.material_override = soil_material
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(id.hash())
	# Quiet low relief inside the arena. Trees and large motifs frame its outside.
	for n in range(95):
		var at := Vector3(rng.randf_range(-7.8, 7.8), 0.035, rng.randf_range(-5.9, 5.9))
		if Vector2(at.x, at.z).length() < 1.8: continue
		StellarModels.part(terrain, "sphere", at, Vector3(rng.randf_range(0.2, 0.55), 0.025, rng.randf_range(0.15, 0.4)), moss.darkened(float(n % 4) * 0.055))
	for n in range(28):
		var side := -1.0 if n % 2 else 1.0
		_tree(terrain, Vector3(side * 8.65, 0, (float(n / 2) - 6.5) * 0.91), 0.6 + rng.randf() * 0.28, moss.darkened(0.25), body == "frost")
	for n in range(13):
		_tree(terrain, Vector3((n - 6) * 1.25, 0, -7.0), 0.50 + rng.randf() * 0.2, moss.darkened(0.32), body == "frost")
	_landmark(terrain, String(Scenery.MAP_MOTIFS.get(id, "gravel")), body, moss, rng)
	for ring in range(3):
		StellarModels.part(terrain, "cylinder", Vector3(0, 0.08 + ring * 0.055, 0), Vector3(1.95 - ring * 0.22, 0.11, 1.95 - ring * 0.22), Color("#41576b").lightened(ring * 0.045))
	StellarModels.part(terrain, "ring", Vector3(0, 0.25, 0), Vector3(1.63, 0.035, 1.63), Color("#99d5d9"), 0.35, 0.25)
	for side in [-1, 1]:
		for z in [-5.8, 5.8]: _lantern(terrain, Vector3(side * 8.0, 0, z), 0.8)
	StellarModels.compact(terrain)
	var crystal := Node3D.new()
	crystal.position = Vector3(0, 0.25, 0)
	StellarModels.part(crystal, "cone", Vector3(0, 0.82, 0), Vector3(0.73, 1.45, 0.73), Color("#79e8f5"), 0.28, 0.7)
	StellarModels.part(crystal, "cone", Vector3(0, 0.22, 0), Vector3(0.73, 0.42, 0.73), Color("#49b3d0"), 0.22, 0.4, Vector3(PI, 0, 0))
	terrain.add_child(crystal)
	crystals.append(crystal)
	_ward = Node3D.new()
	var ward_ring := StellarModels.part(_ward, "ring", Vector3(0, 0.10, 0), Vector3(2.2, 0.08, 2.2), Look.CRYSTAL, 0, 0.6)
	_ward_material = StellarModels.material(Color("#90eafa"), 0.0, 0.4).duplicate()
	_ward_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ward_material.albedo_color.a = 0.2
	var ward_shell := StellarModels.part(_ward, "sphere", Vector3(0, 0.82, 0), Vector3(2.05, 2.6, 2.05), Look.CRYSTAL)
	ward_shell.material_override = _ward_material
	ward_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ward_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ward.visible = false
	terrain.add_child(_ward)
	_crystal_light = OmniLight3D.new()
	_crystal_light.position = Vector3(0, 1.2, 0)
	_crystal_light.light_color = Look.CRYSTAL
	_crystal_light.light_energy = 1.1
	_crystal_light.omni_range = 3.5
	terrain.add_child(_crystal_light)
	for side in [-1, 1]:
		for z in [-5.8, 5.8]:
			var light := OmniLight3D.new()
			light.position = Vector3(side * 8.0, 0.6, z)
			light.light_color = Color("#ffc875")
			light.light_energy = 0.9
			light.omni_range = 2.6
			terrain.add_child(light)
	if is_instance_valid(weather): weather.free()
	weather = MultiMeshInstance3D.new()
	weather.multimesh = MultiMesh.new()
	weather.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	weather.multimesh.mesh = StellarModels.primitive("sphere")
	weather.multimesh.instance_count = 24
	weather.material_override = StellarModels.material(Color("#b6d6df") if body in ["aqua", "frost"] else Color("#e8a45d") if body == "flame" else Color("#839d82"), 0, 0.15)
	weather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(weather)
	weather_update(0)

func weather_update(time: float) -> void:
	if not is_instance_valid(weather): return
	for n in range(weather.multimesh.instance_count):
		var x := sin(n * 18.3) * 7.8
		var z := cos(n * 9.8) * 6.0
		var y := fposmod(n * 0.71 - time * (1.0 if _weather_body == "aqua" else 0.42), 2.7) + 0.2
		if _weather_body == "flame": y = fposmod(n * 0.71 + time * 0.47, 2.7) + 0.2
		var size := Vector3(0.012, 0.13, 0.012) if _weather_body == "aqua" else Vector3(0.025, 0.025, 0.025)
		weather.multimesh.set_instance_transform(n, Transform3D(Basis.from_scale(size), Vector3(x + sin(time + n) * 0.14, y, z)))

func sync_heroes(heroes: Array, time: float, battle: bool = false) -> void:
	# Limne's adapter drives its skin from controls, unlike sampled native clips.
	# Restore the authored leg controls before adding this frame's locomotion.
	for key in _walk:
		if not hero_nodes.has(key) or not hero_nodes[key] is LimneModel: continue
		var node: Node3D = hero_nodes[key]
		var rests: Dictionary = _walk[key].get("leg_rests", {})
		for side in rests: node.get_node("Leg" + side).transform = rests[side]
	super.sync_heroes(heroes, time, battle)
	var keep: Dictionary = {}
	for i in range(heroes.size()):
		var data: Dictionary = heroes[i]
		var hero: Dictionary = data["h"] if battle else data
		var key := "%d:%s:%d" % [i, hero["unit"]["id"], int(hero["tier"])]
		keep[key] = true
		if not hero_nodes.has(key): continue
		var node: Node3D = hero_nodes[key]
		var p: Vector2 = data["pos"] if battle else hero.get("pos", Balance.ARENA_CENTER)
		var track: Dictionary = _walk.get(key, {"p": p, "time": time, "phase": 0.0, "skeleton": _find_skeleton(node)})
		if node is LimneModel and not track.has("leg_rests"):
			track["leg_rests"] = {"L": node.get_node("LegL").transform, "R": node.get_node("LegR").transform}
		var delta: Vector2 = p - Vector2(track["p"])
		var elapsed := maxf(0.0, time - float(track["time"]))
		var moved := delta.length() > 0.025 and delta.length() < 70
		var walking: bool = battle and (moved if elapsed > 0.00001 else bool(track.get("walking", false)))
		if walking:
			if elapsed > 0.00001:
				track["phase"] = float(track["phase"]) + delta.length() * 0.11
				track["direction"] = delta
			var phase := float(track["phase"])
			var skeleton: Skeleton3D = track["skeleton"]
			if skeleton != null:
				for side in ["L", "R"]:
					var bone := skeleton.find_bone("SkinLeg" + side)
					if bone < 0: bone = skeleton.find_bone("Leg" + side)
					if bone < 0: continue
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
			if float(data.get("fx_t", 9.0)) > float(data.get("fx_w", 0.0)) + 0.3:
				var direction: Vector2 = track.get("direction", Vector2.DOWN)
				node.rotation.y = atan2(-direction.x, -direction.y)
		track["walking"] = walking
		track["p"] = p
		track["time"] = time
		_walk[key] = track
	for key in _walk.keys():
		if not keep.has(key): _walk.erase(key)

func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D: return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null: return found
	return null

func sync_battle(sim, time: float, lives: int, dt: float = 0.016) -> void:
	super.sync_battle(sim, time, lives, dt)
	for mo in sim.monsters:
		var key := int(mo.get("spawn_id", 0))
		if not monster_nodes.has(key): continue
		var node: Node3D = monster_nodes[key]
		var velocity: Vector2 = mo.get("vel", Vector2.ZERO)
		if velocity.length_squared() > 0.001:
			node.rotation.y = atan2(-velocity.x, -velocity.y)
		else:
			var toward: Vector2 = Balance.ARENA_CENTER - Vector2(mo["pos"])
			if toward.length_squared() > 0.01: node.rotation.y = atan2(-toward.x, -toward.y)
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
	if type not in ["arena_blast", "arena_freeze", "arena_ward"]:
		super.event(e)
		return
	if _skill_fx.size() >= 6: return
	var node := Node3D.new()
	node.position = world(Vector2(e.get("p", Balance.ARENA_CENTER)), 0.12)
	var color := Look.GOLD if type == "arena_blast" else Look.CRYSTAL if type == "arena_ward" else Look.ICE
	var radius := float(e.get("r", 70.0)) / UNIT
	if type == "arena_freeze": radius *= 0.5
	if _skill_ring == null:
		_skill_ring = TorusMesh.new()
		_skill_ring.inner_radius = 0.47
		_skill_ring.outer_radius = 0.5
		_skill_ring.rings = 48
		_skill_ring.ring_segments = 6
	var ring := StellarModels.part(node, "ring", Vector3.ZERO, Vector3(radius * 2.0, 0.04, radius * 2.0), color, 0.1, 0.25)
	ring.mesh = _skill_ring
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n in range(8):
		var a := TAU * n / 8.0
		StellarModels.part(node, "cone", Vector3(cos(a) * radius * 0.75, 0.18, sin(a) * radius * 0.75), Vector3(0.07, 0.42, 0.07), color, 0, 0.15)
	add_child(node)
	_skill_fx.append({"node": node, "age": 0.0, "life": 0.65, "kind": type})

func update_effects(dt: float) -> void:
	super.update_effects(dt)
	for i in range(_skill_fx.size() - 1, -1, -1):
		var fx: Dictionary = _skill_fx[i]
		fx["age"] += dt
		if fx["age"] >= fx["life"]:
			fx["node"].free()
			_skill_fx.remove_at(i)
		else:
			var q := float(fx["age"]) / float(fx["life"])
			fx["node"].scale = Vector3.ONE * (0.08 + q * 0.95 if fx["kind"] == "arena_freeze" else 0.82 + q * 0.7)
			fx["node"].position.y = 0.12 + q * 0.18
