extends RefCounted
class_name StellarLighting

## Environment, three-point lighting and per-stage overrides for the real 3D world.
## Visual only: nothing here reads or changes combat state.
##
## "Lantern Stage" rig (2026-10-18, build/casual-overhaul/PLAN.md §3 WP-B). World space,
## the camera sits on +Z (a little toward -X) looking toward -Z and down:
##   KeyLight   the stage lamp from the camera's upper left-front (elevation ~51 deg),
##              travelling away from the camera: faces and chests sit in the lit band and
##              the one shadow map falls behind-right, never toward the camera. Toy light
##              budget: energy 1.0-1.05, the only light that keeps any specular.
##   FillLight  a cool sky "kicker" from the upper right-rear (where the old moon key
##              stood), no shadow, no specular: the shade side stays sky-coloured instead
##              of black. Flame fields hand it a warm lava colour (arena_biome.gd).
##   RimLight   a faint cold light from straight behind (the moon's survivor); with the
##              rim term of the skin materials (StellarShading) it draws the silhouette.
##   Ambient    sky colour at 0.40, so every shade side carries the hue of the place.
## Post: ACES at a constant exposure 1.0; depth fog that starts beyond the field's rim
## (the play disc stays clean, the surround recedes to the fog colour, capped per look);
## screen-blend glow for the hottest pixels only (Compatibility ignores the blend mode,
## strength and level members, so they are not set); a grade of saturation 1.08,
## contrast 1.05 and a per-look 1D colour ramp (shadows toward the sky, highlights toward
## the lamp).
##
## A look (game/3d/arena_biome.gd) is read with defaults, so one written before a key
## existed still renders: `key_energy` 1.0, `fill` / `fill_energy` 0.26, `rim_energy` 0.30
## (capped 0.34: with the skins' backlight a strong rear light washes the camera side),
## `ambient_energy` 0.40 (floored 0.36), `bloom` <= 0.40, `fog_max` 0.75 (the depth fog's
## cap), `fog_begin` 36, `fog_end` 70, `lamp`. `exposure` and the old exponential
## `fog_density` are ignored.

const KEY_COLOR := Color("#c4dbf5")
const FILL_COLOR := Color("#8fb4e8")
const RIM_COLOR := Color("#7fb0ff")
## Directions the three lights travel along (world space). apply_biome() never touches
## them, so actors keep the same form light on all fifty fields and only the colour of
## the place changes around them. Probe: analysis/tech_probe/sheets/sheetF_keyfront.png.
const KEY_DIRECTION := Vector3(0.38, -0.78, -0.50)
const FILL_DIRECTION := Vector3(-0.45, -0.70, 0.55)
const RIM_DIRECTION := Vector3(0.08, -0.48, 0.87)
const KEY_ENERGY := 1.0
const KEY_SPECULAR := 0.35
const FILL_ENERGY := 0.26
const RIM_ENERGY := 0.30
const RIM_ENERGY_MAX := 0.34
const AMBIENT_ENERGY := 0.40
const AMBIENT_ENERGY_MIN := 0.36
const EXPOSURE := 1.0
## Shadow: the far rim is ~39 u deep in view space and the gates ~43 u; with the fade
## starting at 0.9 the map covers the whole field and only the far approach softens.
const SHADOW_DISTANCE := 50.0
const SHADOW_FADE_START := 0.9
const SHADOW_OPACITY := 0.72
const SHADOW_BIAS := 0.028
const SHADOW_NORMAL_BIAS := 1.1
const FOG_BEGIN := 36.0
const FOG_END := 70.0
const FOG_CURVE := 1.2
const FOG_MAX := 0.75
const BLOOM := 0.40
const BLOOM_MAX := 0.40
const GLOW_THRESHOLD := 0.88
const GLOW_SCALE := 1.6
## Never above 1.10: the additive VFX cores saturate with it.
const SATURATION := 1.08
const CONTRAST := 1.05
## The neutral arena stage: the values a look overrides (arena_biome.gd _base()).
const ARENA_SKY := Color("#0a1a29")
const ARENA_FOG := Color("#143148")
const ARENA_AMBIENT := Color("#8db4da")
const ARENA_LAMP := Color("#ffc57b")

static var _grades: Dictionary = {}

static func setup(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.name = "Environment"
	environment.environment = make_environment()
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = KEY_COLOR
	key.light_energy = 1.05
	key.light_specular = KEY_SPECULAR
	key.basis = Basis.looking_at(KEY_DIRECTION.normalized(), Vector3.UP)
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = SHADOW_DISTANCE
	key.directional_shadow_fade_start = SHADOW_FADE_START
	key.shadow_bias = SHADOW_BIAS
	key.shadow_normal_bias = SHADOW_NORMAL_BIAS
	key.shadow_opacity = SHADOW_OPACITY
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.light_specular = 0.0
	fill.basis = Basis.looking_at(FILL_DIRECTION.normalized(), Vector3.UP)
	world.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_color = RIM_COLOR
	rim.light_energy = RIM_ENERGY
	rim.light_specular = 0.0
	rim.basis = Basis.looking_at(RIM_DIRECTION.normalized(), Vector3.UP)
	world.add_child(rim)

static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0f2131")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8fb2d4")
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = EXPOSURE
	env.tonemap_white = 4.0
	# Depth fog: none inside the play disc, the surround recedes toward the fog colour.
	# In DEPTH mode `fog_density` is the maximum amount, not a rate (the old exponential
	# 0.004-0.012 values would make every field fog-free).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#1a3449")
	env.fog_light_energy = 1.0
	env.fog_depth_begin = FOG_BEGIN
	env.fog_depth_end = FOG_END
	env.fog_depth_curve = FOG_CURVE
	env.fog_density = FOG_MAX
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	# Compatibility renders into an LDR buffer and always screen-blends the glow, so the
	# "HDR" threshold is a plain luminance cut: only near-white pixels bloom (flashes,
	# crystal light, lanterns, projectile cores).
	env.glow_enabled = true
	env.glow_intensity = BLOOM
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.glow_hdr_scale = GLOW_SCALE
	env.glow_hdr_luminance_cap = 6.0
	# Grade, inside the post pass the glow already runs: a little saturation and
	# contrast plus the per-look colour ramp (see grade()).
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_saturation = SATURATION
	env.adjustment_contrast = CONTRAST
	env.adjustment_color_correction = grade(env.background_color, ARENA_LAMP)
	return env

## 1D colour ramp of a look, built once per (sky, lamp) pair: black lifts toward the
## sky's shade, mid grey stays neutral, white leans toward the lamp.
static func grade(sky: Color, lamp: Color) -> GradientTexture1D:
	var key := sky.to_html(false) + "/" + lamp.to_html(false)
	if _grades.has(key): return _grades[key]
	var gradient := Gradient.new()
	gradient.set_color(0, sky.lerp(Color.BLACK, 0.5))
	gradient.set_color(1, lamp.lerp(Color.WHITE, 0.7))
	gradient.add_point(0.5, Color(0.5, 0.5, 0.5))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	_grades[key] = texture
	return texture

## The continuous arena stage with no look yet: the neutral values every field starts
## from (the same rig, the arena's own sky, fog and ambient colours).
static func apply_arena(world: Node3D) -> void:
	apply_biome(world, {})

## Mood of one arena battlefield (`look` of game/3d/arena_biome.gd): sky, fog, ambient,
## the colour and strength of the three lights and the colour ramp. Light directions and
## the shadow stay as setup() made them. Every key is read with a default (header).
static func apply_biome(world: Node3D, look: Dictionary) -> void:
	var sky: Color = look.get("sky", ARENA_SKY)
	var lamp: Color = look.get("lamp", ARENA_LAMP)
	for child in world.get_children():
		if child is WorldEnvironment:
			var env: Environment = child.environment
			env.background_color = sky
			env.fog_light_color = look.get("fog", ARENA_FOG)
			env.fog_depth_begin = float(look.get("fog_begin", FOG_BEGIN))
			env.fog_depth_end = float(look.get("fog_end", FOG_END))
			env.fog_density = clampf(float(look.get("fog_max", FOG_MAX)), 0.3, 0.95)
			env.ambient_light_color = look.get("ambient", ARENA_AMBIENT)
			env.ambient_light_energy = maxf(float(look.get("ambient_energy", AMBIENT_ENERGY)), AMBIENT_ENERGY_MIN)
			env.glow_intensity = minf(float(look.get("bloom", BLOOM)), BLOOM_MAX)
			env.tonemap_exposure = EXPOSURE
			env.adjustment_color_correction = grade(sky, lamp)
		elif child is DirectionalLight3D:
			match String(child.name):
				"KeyLight":
					child.light_color = look.get("key", KEY_COLOR)
					child.light_energy = float(look.get("key_energy", KEY_ENERGY))
				"FillLight":
					child.light_color = look.get("fill", FILL_COLOR)
					child.light_energy = float(look.get("fill_energy", FILL_ENERGY))
				"RimLight":
					child.light_color = look.get("rim", RIM_COLOR)
					child.light_energy = minf(float(look.get("rim_energy", RIM_ENERGY)), RIM_ENERGY_MAX)

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
