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
## Prop sway (2026-10-18): the field's resting `wind` plus a gust that a starfall blast
## raises through `pulse_wind` and that settles within 0.4 s.
var _scenery_material: ShaderMaterial
var _wind_base := 0.0
var _wind_pulse := 0.0
const WIND_PULSE_DECAY := 1.5
## Gusts waiting on the simulated clock: the trees answer the meteor when it lands, not
## when it is cast ([seconds left, amount]).
var _wind_due: Array = []
## Gust strengths: the starfall's impact, the boss and an elite stepping in, the revival's
## shockwave crossing the field.
const GUST_BLAST := 0.6
const GUST_BOSS := 0.5
const GUST_ELITE := 0.3
const GUST_REVIVE := 0.45
## Ground rings (2026-10-19, feedback O3/F6; art/vfx/vfx_ring.gdshader): one quad for the
## selected hero's reach and feet, one for the starlight-burst aim. Unshaded, fixed screen
## width, drawn above every effect and under the bodies; nothing is rebuilt when the
## radius changes (two uniforms). Gold for the reach and a valid aim, red-grey for an aim
## the star cannot take.
const RING_SHADER := preload("res://art/vfx/vfx_ring.gdshader")
## Colours are chosen for what reaches the screen through ACES and the field's grade (a
## calibration over the four reference fields: tests/3d/d3_visual_preview --scene calib):
## RING_GOLD shows about (254, 190, 55), AIM_GOLD (252, 175, 40), AIM_BAD (228, 120, 112).
const RING_GOLD := Color(1.0, 0.66, 0.04)
const RING_HALO := Color(0.09, 0.05, 0.01, 0.70)
const AIM_GOLD := Color(1.0, 0.58, 0.03)
const AIM_BAD := Color(0.78, 0.40, 0.38)
const AIM_BAD_HALO := Color(0.05, 0.03, 0.035, 0.62)
## Heights over the ground (the plaza tops out at 0.046): the aim draws over the reach.
const RING_HEIGHT := 0.10
const AIM_HEIGHT := 0.115
## The feet: radius in world units (the battle hero's disc is 0.96 x 0.68 x HERO_SCALE).
const FOOT_RADIUS := 0.50
## Screen length of one dash period at 1280x800 (37.6 px per world unit across, the ground
## ellipse 0.63 as tall): about a 16 px dash and a 10 px gap.
const DASH_PX := 26.0
const RING_DRAW_IN := 0.20
const AIM_DRAW_IN := 0.14
const AIM_LOCK := 0.22
const AIM_FADE := 0.12
var _ring: MeshInstance3D
var _ring_material: ShaderMaterial
var _ring_at := Vector2.INF
var _ring_born := -10.0
var _ring_reach := -1.0
var _ring_settled := false
var _ring_lit := false
var _aim: MeshInstance3D
var _aim_material: ShaderMaterial
var _aim_state := {"at": Vector2.INF, "radius": 0.0, "valid": true, "shown": false, "born": -10.0,
	"hidden": -10.0, "locked": -10.0}
## Start-up frames that still draw the buried warm bodies and the hidden ring quads
## (counted only when this world's viewport actually renders); see _process.
const WARM_FRAMES := 4
var _warm_left := WARM_FRAMES
var _warm_nodes: Array[Node3D] = []
## The five-star guardian the next revival would bring (2026-10-19, LA3) is loaded while the
## battlefield card is up — ArenaRun.revive_candidate, fixed by the run seed and the stage —
## and its body stands buried for WARM_FRAMES drawn frames so its top-grade details compile:
## the revival then neither reads a model from storage nor compiles in the middle of the
## fight. Only while a revival can still come (the DLC's tickets); see _keep_revival.
var _revival_seed := 0
var _revival_stage := -1
var _revival_unit: Dictionary = {}
var _revival_body: Node3D
var _revival_left := 0
## Picture-to-screen compensation of the ring strokes (see _sync_screen_k).
var _screen_k := 1.0
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
	_warm_bodies()
	_ring = _ring_node("RangeRing", 10)
	_ring_material = _ring.material_override
	selection.add_child(_ring)
	_aim = _ring_node("AimRing", 11)
	_aim_material = _aim.material_override
	add_child(_aim)
	# Both ring quads stay drawn (fully transparent) through the warm frames so their
	# shader is compiled before the first selection or aim.
	for ring in [_ring, _aim]:
		var material: ShaderMaterial = ring.material_override
		material.set_shader_parameter("presence", 0.0)
		ring.visible = true
	selection.visible = true

## A ground ring quad with its own material (render priority over every effect layer).
func _ring_node(name_value: String, priority: int) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	var node := MeshInstance3D.new()
	node.name = name_value
	node.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = RING_SHADER
	material.render_priority = priority
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(0, -30, 0)
	node.extra_cull_margin = 100.0
	return node

## The warm frames are counted only while this world's viewport is drawn (the battery
## saver may freeze it on still screens), then the buried bodies are hidden, not freed:
## their per-instance materials stay alive, so the compiled skin variants stay cached and
## the first placement on the field does not stall (O8d, 2026-10-19). A hidden node costs
## nothing to draw and the bodies were never animated.
## Also runs the aim ring's lock and fade after the screen has stopped calling set_aim, and
## hides the revival candidate's buried body after its own warm frames (_keep_revival).
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var drawn := _view_live()
	if _revival_left > 0 and drawn:
		_revival_left -= 1
		if _revival_left == 0 and is_instance_valid(_revival_body): _revival_body.visible = false
	if _warm_left > 0:
		if not drawn: return
		_warm_left -= 1
		if _warm_left > 0: return
		for body in _warm_nodes:
			if is_instance_valid(body): body.visible = false
		for ring in [_ring, _aim]:
			var material: ShaderMaterial = ring.material_override
			material.set_shader_parameter("presence", 1.0)
		_ring_lit = true
		if not _ring_at.is_finite(): _ring.visible = false
	_draw_aim(now)
	if not _aim_settling(now) and _revival_left <= 0: set_process(false)

## Whether this world's picture is really being drawn every frame. A frozen view keeps
## UPDATE_ONCE on its node after its one refresh (ArenaView leaves it there), so only a live
## view (UPDATE_ALWAYS) or a world drawn straight into a window counts: a frozen battlefield
## never ticks the warm frames away before their materials have been drawn and compiled.
func _view_live() -> bool:
	var view := get_viewport()
	if not (view is SubViewport): return true
	return (view as SubViewport).render_target_update_mode == SubViewport.UPDATE_ALWAYS

## How many screen pixels one pixel of this world's picture covers. The picture is drawn at
## the battle box's design size (1280x800) and the window scales the canvas it is shown on
## (canvas_items stretch; a film SubViewport with a 2D override does the same), so at
## 1000x625 one picture pixel is 0.78 screen pixels.
func screen_scale() -> float:
	var view := get_viewport()
	if not (view is SubViewport) or view.get_parent() == null: return 1.0
	var host := view.get_parent().get_viewport()
	if host == null: return 1.0
	return clampf(host.get_final_transform().get_scale().y, 0.25, 4.0)

## The ring strokes stay at least their design width on the real screen: below 1:1 they are
## drawn wider in the picture by 1 / scale (3.6 px at 1000x625 instead of 2.8); above it they
## grow with the canvas like the rest of the HUD.
func _sync_screen_k() -> void:
	var k := 1.0 / clampf(screen_scale(), 0.5, 1.0)
	if is_equal_approx(k, _screen_k): return
	_screen_k = k
	for material in [_ring_material, _aim_material]:
		(material as ShaderMaterial).set_shader_parameter("screen_k", k)
	_ring_reach = -1.0

## True while the aim ring is still locking on or fading out without the screen's calls.
func _aim_settling(now: float) -> bool:
	return not bool(_aim_state["shown"]) and (now - float(_aim_state["locked"]) < AIM_LOCK or now - float(_aim_state["hidden"]) < AIM_FADE)

## One native hero and one native monster stand buried under the field from the first
## frame so every skin material variant (wrap, shade tint, fog-free, hull, flash) is
## compiled before the first placement rather than during it (docs/PERF_NATIVE.md).
func _warm_bodies() -> void:
	var bodies: Array = []
	var unit := Roster.unit_by_id("echo")
	if not unit.is_empty(): bodies.append(StellarModels.hero(unit, 4))
	var monster := Roster.monster_by_id("ember_imp")
	if not monster.is_empty(): bodies.append(StellarModels.monster(monster))
	# The monster wears the elite look (violet hull, aura) so those variants compile too.
	if bodies.size() > 1: StellarModels.elite(bodies[-1])
	for body in bodies:
		body.name = "Warm" + body.name
		_bury(body)
		_warm_nodes.append(body)

## Stand a body under the field, drawn (never culled, no shadow) while it is visible.
func _bury(body: Node3D) -> void:
	body.position = Vector3(0, -30, 0)
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		mesh.extra_cull_margin = 100.0
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)

## See _revival_unit. Runs every picture: from sync_battle with the simulator's run, and from
## build_map with the run autoload — ArenaView may skip the battle's sync under a frozen
## window such as the battlefield card, which is exactly when this should load. It does work
## only when the run's seed or stage has changed and a revival can still come. The previous
## candidate, if it never joined, is let go from the model cache. No screen call is needed.
func _keep_revival(sim) -> void:
	var run = sim.get("run") if sim is Object else null
	if run == null: run = get_node_or_null(^"/root/Arena")
	if run == null or not (run is Object) or not run.has_method("revive_candidate") or not run.has_method("revives_left"): return
	var seed_now := int(run.get("run_seed"))
	var stage_now := int(run.get("stage"))
	if seed_now == _revival_seed and stage_now == _revival_stage: return
	if int(run.call("revives_left")) <= 0: return
	_revival_seed = seed_now
	_revival_stage = stage_now
	var unit: Dictionary = run.call("revive_candidate")
	var id := String(unit.get("id", ""))
	var previous := String(_revival_unit.get("id", ""))
	if id == previous: return
	if previous != "" and run.has_method("find_hero") and int(run.call("find_hero", previous)[1]) < 0:
		StellarModels.forget_hero(_revival_unit, Balance.TIER_MAX)
	if is_instance_valid(_revival_body): _revival_body.queue_free()
	_revival_body = null
	_revival_unit = unit
	if id == "": return
	_revival_body = StellarModels.hero(unit, Balance.TIER_MAX)
	_revival_body.name = "WarmRevival"
	_revival_body.scale = Vector3.ONE * StellarModels.HERO_SCALE
	_bury(_revival_body)
	_revival_left = WARM_FRAMES
	set_process(true)

func build_map(theme: Dictionary) -> void:
	_keep_revival(null)
	var id := String(theme.get("id", "wood"))
	# A battlefield is its theme and its road layout (ArenaGeometry.use_layout).
	var key := id + "|" + ArenaGeometry.layout()
	if key == _map_key: return
	# The key is written at the end (F7): a build that stops part-way is built again on the
	# next call instead of being taken for done.
	_map_key = ""
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
	_scenery_material = scenery.material
	_wind_base = float(look["wind"])
	_wind_pulse = 0.0
	_wind_due.clear()
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
	_map_key = key

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

## Unused here (the heading above is the simulator's velocity): skip the legacy lookup.
func _monster_ahead(_mo: Dictionary, p: Vector2) -> Vector2:
	return p

func sync_battle(sim, time: float, lives: int, dt: float = 0.016) -> void:
	super.sync_battle(sim, time, lives, dt)
	_keep_revival(sim)
	for crystal in crystals: crystal.visible = sim.crystal_hp > 0
	if is_instance_valid(_ward): _ward.visible = sim.shield > 0
	if is_instance_valid(_crystal_light):
		_crystal_light.light_energy = 0.35 + 0.75 * clampf(sim.crystal_hp / maxf(1, sim.crystal_max), 0, 1)
	if dt > 0.0:
		for i in range(_wind_due.size() - 1, -1, -1):
			var due: Array = _wind_due[i]
			due[0] = float(due[0]) - dt
			if float(due[0]) <= 0.0:
				pulse_wind(float(due[1]))
				_wind_due.remove_at(i)
	if _wind_pulse > 0.0 and _scenery_material != null:
		_wind_pulse = maxf(0.0, _wind_pulse - WIND_PULSE_DECAY * dt)
		_scenery_material.set_shader_parameter("wind", _wind_base + _wind_pulse)

## A gust through every prop: the trees answer a starfall blast.
func pulse_wind(amount: float) -> void:
	_wind_pulse = maxf(_wind_pulse, amount)

## The same gust `delay` simulated seconds from now (a paused battle holds it).
func pulse_wind_later(delay: float, amount: float) -> void:
	if delay <= 0.0:
		pulse_wind(amount)
		return
	_wind_due.append([delay, amount])

## The selected hero's reach (contract unchanged: ArenaView calls it every frame with the
## hero's logical position and range, INF to hide). One quad and two uniforms: switching
## to a hero with another range rebuilds nothing. A new selection draws the ring in from
## the feet with a short flash so the eye finds it.
func set_selection(at: Vector2, available: bool, radius: float = 0.0) -> void:
	_available = available
	if not at.is_finite():
		_ring_at = Vector2.INF
		if _warm_left <= 0: _ring.visible = false
		return
	var now := Time.get_ticks_msec() * 0.001
	# Another hero (or a fresh selection): the ring jumped or its reach changed.
	if not _ring_at.is_finite() or _ring_at.distance_to(at) > 40.0 or not is_equal_approx(radius, _range):
		_ring_born = now
		_ring_settled = false
	_ring_at = at
	_range = radius
	var reach := maxf(radius / UNIT, 0.0)
	_ring.position = world(at, RING_HEIGHT)
	var m := _ring_material
	_sync_screen_k()
	if not is_equal_approx(reach, _ring_reach):
		# Only a new reach writes the ring's shape (most frames just move it with the hero).
		_ring_reach = reach
		var extent := maxf(reach, FOOT_RADIUS) + 0.45
		_ring.scale = Vector3(extent, 1.0, extent)
		m.set_shader_parameter("mode", 0)
		m.set_shader_parameter("radius", reach)
		m.set_shader_parameter("foot", FOOT_RADIUS)
		m.set_shader_parameter("color", RING_GOLD)
		m.set_shader_parameter("halo_color", RING_HALO)
		m.set_shader_parameter("stroke_px", 3.6)
		m.set_shader_parameter("fill", 0.10 if reach > 2.6 else 0.16)
		m.set_shader_parameter("dashes", ring_dashes(reach, 1.0 / _screen_k))
		m.set_shader_parameter("dash_on", 0.62)
	var age := now - _ring_born
	if age < 0.4 or not _ring_settled:
		# The draw-in: animated for its 0.4 s, then written once more at rest.
		m.set_shader_parameter("appear", clampf(age / RING_DRAW_IN, 0.0, 1.0))
		m.set_shader_parameter("flash", 1.0 - smoothstep(0.0, 0.32, age))
		_ring_settled = age >= 0.4
	if _warm_left <= 0 and not _ring_lit:
		m.set_shader_parameter("presence", 1.0)
		_ring_lit = true
	_ring.visible = true

## Dashes around a ring of `reach` world units: a whole, even number, about DASH_PX of
## screen per dash period (`scale`: screen pixels per picture pixel, below 1 on a small
## window, so the period stays DASH_PX on the real screen); at least 12, so a melee reach
## (40-95 px) gets a finer dash instead of a few fat pills.
static func ring_dashes(reach: float, scale: float = 1.0) -> float:
	var around := TAU * reach * 37.6 * 0.82 * scale
	return float(maxi(12, int(round(around / DASH_PX / 2.0)) * 2))

## The starlight-burst aim (2026-10-19, F6). The screen calls this every frame while the
## blast is armed: `at` the logical ground point under the finger or cursor, `radius` the
## damage radius in logical units (sim.blast_radius()), `valid` whether the star may fall
## there, `shown` false once aiming ends. Valid is gold: the struck area filled, its edge
## solid, eight lock-on arrowheads waiting at 1.35 R and a star at the centre. Invalid is
## red-grey dashes with a cross. When the cast lands (arena_blast within a moment of the
## aim closing, see _aim_cast) the arrowheads close onto R and the ring hands over to the cast's
## own sigil, which starts at 1.35 R and settles on R (StellarVfx, vfx_skill part 1); a
## cancel just fades.
func set_aim(at: Vector2, radius: float, valid: bool, shown: bool) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var state := _aim_state
	if shown and at.is_finite():
		if not bool(state["shown"]): state["born"] = now
		state["shown"] = true
		state["at"] = at
		state["radius"] = radius
		state["valid"] = valid
		state["locked"] = -10.0
	elif bool(state["shown"]):
		state["shown"] = false
		state["hidden"] = now
		set_process(true)
	_draw_aim(now)

## Pose the aim quad for this moment.
func _draw_aim(now: float) -> void:
	var state := _aim_state
	var at: Vector2 = state["at"]
	var shown := bool(state["shown"])
	var locking := now - float(state["locked"]) < AIM_LOCK
	var fading := not shown and now - float(state["hidden"]) < AIM_FADE
	if not at.is_finite() or not (shown or locking or fading):
		if _warm_left <= 0: _aim.visible = false
		return
	var reach := maxf(float(state["radius"]) / UNIT, 0.2)
	var valid := bool(state["valid"])
	_aim.position = world(at, AIM_HEIGHT)
	var extent := reach * 1.55 + 0.45
	_aim.scale = Vector3(extent, 1.0, extent)
	var m := _aim_material
	_sync_screen_k()
	m.set_shader_parameter("mode", 1 if valid else 2)
	m.set_shader_parameter("radius", reach)
	m.set_shader_parameter("foot", 0.0)
	m.set_shader_parameter("color", AIM_GOLD if valid else AIM_BAD)
	m.set_shader_parameter("halo_color", RING_HALO if valid else AIM_BAD_HALO)
	m.set_shader_parameter("stroke_px", 4.2 if valid else 3.4)
	m.set_shader_parameter("fill", 0.15 if valid else 0.07)
	m.set_shader_parameter("dashes", 0.0 if valid else ring_dashes(reach, 1.0 / _screen_k))
	m.set_shader_parameter("dash_on", 0.55)
	m.set_shader_parameter("appear", clampf((now - float(state["born"])) / AIM_DRAW_IN, 0.0, 1.0))
	m.set_shader_parameter("spin", now * 0.9)
	var lock := clampf((now - float(state["locked"])) / AIM_LOCK, 0.0, 1.0) if locking else 0.0
	m.set_shader_parameter("lock", lock)
	m.set_shader_parameter("flash", 0.8 * sin(PI * lock) if locking else 0.0)
	var presence := 1.0
	if locking: presence = 1.0 - smoothstep(0.35, 1.0, lock)
	elif fading: presence = 1.0 - (now - float(state["hidden"])) / AIM_FADE
	if _warm_left <= 0: m.set_shader_parameter("presence", presence)
	_aim.visible = true

func event(e: Dictionary) -> void:
	var type := String(e.get("t", ""))
	if type == "arena_crystal_hit":
		if float(e.get("n", 0.0)) > 0:
			super.event({"t": "leak", "p": Balance.ARENA_CENTER, "c": Look.RED, "r": 42.0})
		return
	if type in ["arena_blast", "arena_freeze", "arena_ward", "arena_boss_warning", "arena_boss",
			"arena_stage", "arena_stage_clear", "arena_revive", "arena_levelup",
			"arena_wave", "arena_wave_clear", "arena_elite", "arena_heal"]:
		match type:
			"arena_blast":
				# The trees answer the starfall when it lands (BLAST_FALL after the cast).
				pulse_wind_later(StellarVfx.BLAST_FALL, GUST_BLAST)
				_aim_cast(Vector2(e.get("p", Vector2.INF)))
			"arena_boss":
				pulse_wind_later(0.05, GUST_BOSS)
			"arena_elite":
				pulse_wind_later(0.05, GUST_ELITE)
			"arena_revive":
				pulse_wind_later(StellarVfx.REVIVE_FLASH, GUST_REVIVE)
		vfx.arena_event(e)
		return
	super.event(e)

## The star was cast: if the aim was up a moment ago over that point, its arrowheads close onto
## the struck radius while the cast's own lock-on sigil takes over.
func _aim_cast(p: Vector2) -> void:
	var state := _aim_state
	var at: Vector2 = state["at"]
	if not at.is_finite() or not p.is_finite() or at.distance_to(p) > 60.0: return
	var now := Time.get_ticks_msec() * 0.001
	if not bool(state["shown"]) and now - float(state["hidden"]) > 0.30: return
	state["shown"] = false
	state["hidden"] = now
	state["locked"] = now
	state["valid"] = true
	set_process(true)
	_draw_aim(now)
