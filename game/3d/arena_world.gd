extends StellarWorld
class_name ArenaWorld

## Arena visuals adapt the existing real models; simulation owns every position.
var _walk: Dictionary = {}
var _ward: Node3D
var _ward_material: StandardMaterial3D
var _crystal_light: OmniLight3D
var _weather_body := "wood"
var _map_key := ""
var _weather_material: ShaderMaterial
## How bright the playfield floor of the current field is, for the effects layer (which
## may read these instead of inferring brightness from the theme's biome):
## `floor_lightness` is its measured CIE L* (44..66 across the fifty fields),
## `ground_wash` the same as a 0..1 hint (0 up to L 57, 1 from L 67).
var floor_lightness := 54.0
var ground_wash := 0.0
const Biome := preload("res://game/3d/arena_biome.gd")
const Land := preload("res://game/3d/arena_land.gd")
const Props := preload("res://game/3d/arena_scenery.gd")
const NOISE := preload("res://art/models/terrain_noise.png")
const GROUND_SHADER := preload("res://art/models/arena_ground.gdshader")
const TERRAIN_SHADER := preload("res://art/models/arena_terrain.gdshader")
const LIQUID_SHADER := preload("res://art/models/arena_liquid.gdshader")
const ROAD_SHADER := preload("res://art/models/arena_road.gdshader")
const HAZE_SHADER := preload("res://art/models/arena_haze.gdshader")
const WEATHER_SHADER := preload("res://art/vfx/weather.gdshader")
## Full-field framing (2026-10-12): 34 world units across the 1280px viewport puts the
## whole 24-unit spiral field inside the 992px open battle box with 44px to spare on
## each side, so the roads read at a glance. Actors are smaller by the user's choice
## (a 2u hero is 58px tall at 1280x800, 45px at 1000x625). The magnification is
## otherwise constant: following never rescales anything.
const CAMERA_SIZE := 34.0
## Brief orthographic zoom-in (>1) that ArenaView drives for the boss entrance only.
var camera_punch := 1.0

func camera_update() -> void:
	camera.size = CAMERA_SIZE / maxf(0.5, camera_punch)
	camera.position = camera_target + Vector3(-3.0, 19.0, 23.0)
	camera.look_at(camera_target + Vector3(0, 0.4, 0), Vector3.UP)

func _ready() -> void:
	super._ready()
	StellarLighting.apply_arena(self)
	# Not every field has water or lava: draw one buried triangle with that shader from
	# the first frame, so a later battlefield never compiles it in the middle of a run.
	var warm := MeshInstance3D.new()
	var triangle := ImmediateMesh.new()
	triangle.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for corner in [Vector3(0, -30, 0), Vector3(0.01, -30, 0), Vector3(0, -30, 0.01)]:
		triangle.surface_set_normal(Vector3.UP)
		triangle.surface_set_uv2(Vector2.ZERO)
		triangle.surface_add_vertex(corner)
	triangle.surface_end()
	warm.mesh = triangle
	warm.material_override = _material(LIQUID_SHADER, {})
	warm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warm.extra_cull_margin = 100.0
	add_child(warm)

func build_map(theme: Dictionary) -> void:
	var id := String(theme.get("id", "wood"))
	# A battlefield is its theme and its road layout (ArenaGeometry.use_layout).
	var key := id + "|" + ArenaGeometry.layout()
	if key == _map_key: return
	_map_key = key
	theme_id = id
	_clear(terrain)
	crystals.clear()
	var biome := Biome.new(theme)
	var look: Dictionary = biome.look
	_weather_body = biome.body
	ground_wash = float(look["wash"])
	floor_lightness = float(look["floor_l"])
	StellarLighting.apply_biome(self, look)
	var radius := ArenaGeometry.RADIUS / UNIT
	var seed_offset: Vector2 = look["seed"]
	var half_dir := _half_vector()
	var lift := float(look["lift"])
	# Land (and water, lava, sea ice) from the rim outward: one height function decides
	# the terrain, the shore and where everything stands.
	var land := Land.new(look["land"], absi(id.hash()))
	_mesh(land.terrain(), _material(TERRAIN_SHADER, look["terrain"],
		{"haze_color": look["haze"], "seed": seed_offset, "haze": Vector4(14.0, 30.0, 0.72, lift)}), true)
	var liquid: Dictionary = look["liquid"]
	if not liquid.is_empty():
		_mesh(land.liquid(float(liquid["level"])), _material(LIQUID_SHADER, liquid,
			{"haze_color": look["haze"], "seed": seed_offset, "half_dir": half_dir}), false)
	# The playfield: the 128-sided disc uses the same radius as movement and lanes.
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.15
	disc.radial_segments = 128
	disc.cap_bottom = false
	var soil := _mesh(disc, _material(GROUND_SHADER, look["ground"], {"field_radius": radius, "seed": seed_offset}), false)
	soil.position.y = -0.06
	# Props share one material; the kerbs below use it too.
	var scenery := Props.new()
	scenery.material.set_shader_parameter("cover_color", look["cover"])
	scenery.material.set_shader_parameter("cover_amount", look["cover_amount"])
	scenery.material.set_shader_parameter("wind", look["wind"])
	scenery.material.set_shader_parameter("lift", lift)
	# Roads: every arm in full on its own hair of height (arms cross near the plaza),
	# feeders above them so their mouths cover the arm, an approach outside every gate.
	# The kerb follows the true outline of all roads together, so no edge crosses a
	# junction and every arm meets the plaza with its rounded end.
	var road_material := _material(ROAD_SHADER, look["road"], {"field_radius": radius, "fade_color": look["fade"],
		"fade_length": look["fade_length"], "road_width": ArenaGeometry.ROAD_WIDTH / UNIT})
	var roads := ArenaGeometry.road_polylines()
	var runs: Array = []
	var arms := 0
	var feeders := 0
	for i in range(roads.size()):
		var is_arm := ArenaGeometry.road_layer(i) == 0
		var line := Land.road_line(roads[i], float(look["approach"]))
		var height := Land.ARM_HEIGHT + arms * Land.LAYER_STEP if is_arm else Land.FEEDER_HEIGHT + feeders * Land.LAYER_STEP
		if is_arm: arms += 1
		else: feeders += 1
		_mesh(Land.road_mesh(line, height, is_arm), road_material, false)
		runs.append_array(Land.kerb_runs(line, is_arm))
	var kerb: Dictionary = look["kerb"]
	if float(kerb["tall"]) > 0.0:
		_mesh(Land.kerb_mesh(runs, float(kerb["width"]), float(kerb["tall"]), Land.ARM_HEIGHT, kerb["a"], kerb["b"],
			float(kerb["stone"]), minf(float(look["fade_length"]), float(look["approach"]))), scenery.material, false)
	var plaza_disc := CylinderMesh.new()
	plaza_disc.top_radius = ArenaGeometry.PLAZA_RADIUS / UNIT
	plaza_disc.bottom_radius = plaza_disc.top_radius
	plaza_disc.height = 0.018
	plaza_disc.radial_segments = 96
	plaza_disc.cap_bottom = false
	var plaza := _mesh(plaza_disc, _material(ROAD_SHADER, look["plaza"], {"field_radius": radius, "plaza": true,
		"road_width": ArenaGeometry.PLAZA_RADIUS * 2.0 / UNIT}), false)
	plaza.position.y = Land.PLAZA_TOP - 0.009
	# Border, gates and the surroundings of this biome; then the sanctuary itself.
	biome.dress(scenery, land)
	scenery.covered = false
	_altar(scenery, look["altar"])
	scenery.commit(terrain)
	if biome.haze_quads > 0:
		var haze_material := ShaderMaterial.new()
		haze_material.shader = HAZE_SHADER
		haze_material.set_shader_parameter("noise_tex", NOISE)
		_mesh(biome.haze.commit(), haze_material, false)
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
	StellarModels.compact(crystal)
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
	_crystal_light.light_color = look["crystal_light"]
	_crystal_light.light_energy = 1.55
	_crystal_light.omni_range = 4.4
	terrain.add_child(_crystal_light)
	# One warm lamp per gate plus the few lights a place asks for. The ground is a handful
	# of large meshes, so every light here is paid on every pixel of it: keep them few.
	for n in range(mini(biome.lights.size(), MAX_FIELD_LIGHTS)):
		var spec: Dictionary = biome.lights[n]
		var lamp := OmniLight3D.new()
		lamp.position = spec["at"]
		lamp.light_color = spec["color"]
		lamp.light_energy = float(spec["energy"])
		lamp.omni_range = float(spec["range"])
		terrain.add_child(lamp)
	_build_weather(look["weather"], radius)

## Point lights a field may add to the crystal's: one lamp per gate first, then the
## lights a place asks for, in its own order of importance. The old field had one lamp
## per gate (four) beside the crystal; this allows one more at most.
const MAX_FIELD_LIGHTS := 5

func _mesh(mesh: Mesh, material: Material, shadow: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	if not shadow: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(node)
	return node

func _material(shader: Shader, params: Dictionary, extra: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("noise_tex", NOISE)
	for parameter in extra: material.set_shader_parameter(parameter, extra[parameter])
	for parameter in params: material.set_shader_parameter(parameter, params[parameter])
	return material

## Direction halfway between the key light and the fixed camera: where a facet has to
## point to flash. Constant for an orthographic view, so glints cost one dot product.
func _half_vector() -> Vector3:
	var to_light := Vector3(0.40, 0.80, -0.45)
	for child in get_children():
		if child is DirectionalLight3D and child.shadow_enabled: to_light = child.global_transform.basis.z
	return (to_light.normalized() + camera.global_transform.basis.z.normalized()).normalized()

## The crystal sanctuary: the same three steps, twelve stones and rune ring on every
## field, in the stone of the place.
func _altar(scenery: Props, altar: Dictionary) -> void:
	var stone: Color = altar["stone"]
	var trim: Color = altar["trim"]
	for ring in range(3):
		scenery.part("cylinder", Vector3(0, 0.07 + ring * 0.075, 0), Vector3(2.30 - ring * 0.24, 0.14, 2.30 - ring * 0.24), stone.lightened(ring * 0.07))
	for n in range(12):
		var angle := n * TAU / 12.0
		scenery.part("stone", Vector3(cos(angle) * 1.05, 0.11, sin(angle) * 1.05), Vector3(0.47, 0.22, 0.33), trim, 0.0, Vector3(0, -angle + PI / 2, 0))
		scenery.part("box", Vector3(cos(angle) * 0.74, 0.28, sin(angle) * 0.74), Vector3(0.055, 0.013, 0.12), altar["rune"], 0.7, Vector3(0, -angle, 0))
	scenery.part("ring", Vector3(0, 0.27, 0), Vector3(1.8, 0.035, 1.8), Color("#94e8fa"), 0.55)

## Ambient motes of the field. They are placed once; the shader carries them, so a
## frame only costs one uniform (weather_update).
func _build_weather(spec: Dictionary, radius: float) -> void:
	if is_instance_valid(weather): weather.free()
	weather = MultiMeshInstance3D.new()
	weather.multimesh = MultiMesh.new()
	weather.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	weather.multimesh.mesh = QuadMesh.new()
	var count := int(spec["count"])
	weather.multimesh.instance_count = count
	var extent := radius + 6.0
	var tall := float(spec["height"])
	var size: Vector2 = spec["size"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013
	for n in range(count):
		var scale_value := rng.randf_range(0.7, 1.45)
		var basis := Basis.from_scale(Vector3(size.x * scale_value, size.y * scale_value, 1.0))
		weather.multimesh.set_instance_transform(n, Transform3D(basis, Vector3(rng.randf_range(-extent, extent), rng.randf_range(0.0, tall), rng.randf_range(-extent, extent))))
	_weather_material = ShaderMaterial.new()
	_weather_material.shader = WEATHER_SHADER
	_weather_material.set_shader_parameter("sprites", preload("res://art/vfx/sprites.png"))
	_weather_material.set_shader_parameter("tint", spec["tint"])
	for parameter in ["opacity", "sprite", "drift", "sway", "twinkle", "stretch"]:
		_weather_material.set_shader_parameter(parameter, spec[parameter])
	# Motes that only add light (sparks, fireflies) need more of it to read at 5 px.
	_weather_material.set_shader_parameter("brightness", float(spec["brightness"]) * (1.0 + 0.9 * (1.0 - float(spec["opacity"]))))
	_weather_material.set_shader_parameter("box", Vector3(extent * 2.0, tall, extent * 2.0))
	_weather_material.set_shader_parameter("box_origin", Vector3(-extent, 0.15, -extent))
	weather.material_override = _weather_material
	weather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weather.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 14, 80))
	add_child(weather)
	weather_update(0.0)

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
	if _weather_material != null: _weather_material.set_shader_parameter("time", time)

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
		_hero_motion[i] = {"v": track["v"], "dt": elapsed, "walking": walking, "attacking": attacking,
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
	if type in ["arena_blast", "arena_freeze", "arena_ward", "arena_boss_warning", "arena_boss",
			"arena_stage", "arena_stage_clear", "arena_revive"]:
		vfx.arena_event(e)
		return
	super.event(e)
