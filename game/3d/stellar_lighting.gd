extends RefCounted
class_name StellarLighting

## Environment, three-point lighting and per-stage overrides for the real 3D world.
## Visual only: nothing here reads or changes combat state.
##
## Rig (world space, camera sits on +Z looking toward -Z and down):
##   KeyLight   cool moonlight from the upper right-rear. Casts the one shadow map.
##              Coming from behind the actors it lays their shadows toward the camera
##              and lights shoulders/heads, which is what makes them read as solid.
##   FillLight  warm lantern bounce from the camera's left, no shadows; keeps faces
##              and fronts legible against the cold key.
##   RimLight   faint cold back light from straight behind; with the rim term of the
##              character materials (StellarShading) it draws a thin silhouette edge.
## Post: ACES tonemap, additive glow that only blooms the hottest pixels (flashes,
## crystals, lanterns, projectile cores), depth fog toward the woodland.

const KEY_COLOR := Color("#c4dbf5")
const FILL_COLOR := Color("#ffcf9a")
const RIM_COLOR := Color("#7fb0ff")

static func setup(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.name = "Environment"
	environment.environment = make_environment()
	world.add_child(environment)
	var moon := DirectionalLight3D.new()
	moon.name = "KeyLight"
	moon.light_color = KEY_COLOR
	moon.light_energy = 1.12
	moon.light_specular = 0.85
	moon.basis = Basis.looking_at(Vector3(-0.42, -0.74, 0.52).normalized(), Vector3.UP)
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 46
	moon.shadow_bias = 0.028
	moon.shadow_normal_bias = 1.1
	moon.shadow_blur = 1.6
	moon.shadow_opacity = 0.86
	world.add_child(moon)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = FILL_COLOR
	fill.light_energy = 0.34
	fill.light_specular = 0.25
	fill.basis = Basis.looking_at(Vector3(0.55, -0.55, -0.62).normalized(), Vector3.UP)
	world.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_color = RIM_COLOR
	rim.light_energy = 0.42
	rim.light_specular = 0.6
	rim.basis = Basis.looking_at(Vector3(0.08, -0.48, 0.87).normalized(), Vector3.UP)
	world.add_child(rim)

static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0f2131")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8fb2d4")
	env.ambient_light_energy = 0.27
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.04
	env.tonemap_white = 4.0
	env.fog_enabled = true
	env.fog_light_color = Color("#1a3449")
	env.fog_light_energy = 1.0
	env.fog_density = 0.0042
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	# Compatibility renders into an LDR buffer, so the "HDR" threshold is a plain
	# luminance cut: only near-white pixels bloom. Additive blend keeps the ground
	# from milking out while flashes and crystal light spill softly.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 0.42
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.84
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 6.0
	env.set("glow_levels/1", 0.0)
	env.set("glow_levels/2", 0.6)
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 0.7)
	env.set("glow_levels/5", 0.35)
	return env

## The continuous arena stage: a touch brighter ambient, denser fog and a steeper key
## so the whole circular field reads under the fixed oblique camera.
static func apply_arena(world: Node3D) -> void:
	for child in world.get_children():
		if child is WorldEnvironment:
			var env: Environment = child.environment
			env.background_color = Color("#0a1a29")
			env.fog_light_color = Color("#143148")
			env.fog_density = 0.0070
			env.ambient_light_color = Color("#8db4da")
			env.ambient_light_energy = 0.29
			env.glow_intensity = 0.48
		elif child is DirectionalLight3D and child.shadow_enabled:
			child.light_energy = 1.08
			child.basis = Basis.looking_at(Vector3(-0.40, -0.80, 0.45).normalized(), Vector3.UP)
			child.directional_shadow_max_distance = 66

## Transient point light used by effects: warm or elemental pulses that die fast.
static func pulse_light(color: Color, energy: float, range_value: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.light_specular = 0.6
	light.visible = false
	return light
