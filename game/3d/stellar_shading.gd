extends RefCounted
class_name StellarShading

## Surface styling shared by native heroes and monsters, plus per-instance
## hit-flash / dissolve state used by motion and effect code. Visual only.
##
## style(root, metal) runs at model creation (pre-pack for heroes) and only tunes the
## shared GLB materials to the painterly skin of 2026-10-18 (build/casual-overhaul/PLAN.md
## §3 WP-B): wrapped diffuse, no specular on cloth and skin, a rim in the skin's own
## colour, a budgeted cool tint on the shade side, unfogged. outline(root, width_px)
## hangs the inverted-hull ink line on heroes and bosses as the skin's `next_pass`.
##
## Per-instance state (flash, dissolve) needs values that differ per live body. The
## skin stays a StandardMaterial3D (the contract below), which has no instance uniforms,
## so prepare_instance(root) creates one StandardMaterial3D override per skinned surface
## (a duplicate of the shared material with emission at energy 0 and the dissolve dither
## at "whole") once, when the live instance enters the world's actor tree (StellarVfx
## connects actors.child_entered_tree) or on its first non-zero flash/dissolve. Later
## frames only change values, never create resources. Overrides are deliberately not
## created before packing: the headless (dummy) renderer cannot enumerate packed
## local-to-scene override materials, and the skin contract checks that a card's
## resource set is stable while it animates. Instance shader parameters themselves do
## work in 4.7.1 Compatibility (analysis/tech_probe/frames/40_instance_uniform_actor1_red.png):
## the hull's `cut` and the contact disc's `fade` ride on them, through the next_pass.
##
## Why StandardMaterial3D and not a ShaderMaterial: the skin contract reads
## get_active_material(i) as a BaseMaterial3D carrying the albedo texture, and the
## standard material already provides rim light, emission and a pixel dither. Material
## modes, `next_pass`, scale and lights are invisible to it.
##
## The dissolve never uses alpha (2026-10-12). GL Compatibility's scene shader has no
## alpha-hash path: an ALPHA_HASH material is drawn fully opaque in the opaque pass and
## its ALPHA is written to the frame buffer's alpha channel. The arena draws the 3D
## viewport texture on the 2D canvas with alpha blending, so a dying body used to stay
## solid and then turn into a hard, mesh-shaped hole onto the screen's dark backdrop
## (Look.BG_DEEP) for the last 0.2 s of its death. Measured with tests/3d/
## vfx_visual_preview --dissolve-probe: the viewport's alpha under the body reads 1 down
## to a material alpha of 0.17 and 0 from 0.16, while the body's colour is still in the
## colour buffer; an environment clear colour set to magenta never shows, so it is not a
## depth-only silhouette. The fade is the standard material's
## distance-fade pixel dither instead: interleaved gradient noise + discard, identical
## in the depth pre-pass, the colour pass and the shadow pass, with the frame buffer
## alpha left at 1, so the holes show the ground behind the body.

const META_MATERIALS := "_stellar_materials"
const META_INSTANCE := "stellar_instance_material"
const META_FLASH := "hit_flash"
const META_DISSOLVE := "dissolve"
## A crit / weak-point accent riding on the current flash: {"strength", "color"}; it is
## dropped when the flash has decayed to 0 (StellarVfx sets it, 2026-10-17).
const META_ACCENT := "hit_accent"
## MeshInstance3Ds of a live instance whose skin carries the hull outline (the dissolve
## pushes its `cut`), and the contact disc that fades with the body.
const META_OUTLINE_NODES := "_stellar_outline_nodes"
const META_CONTACT := "_stellar_contact"
const META_OUTLINE := "_stellar_outline"
## Authored glow surfaces of a live instance (ember_imp's crown): their own dithered
## duplicates, which fade with the body and keep their authored emission (2026-10-19 X1).
const META_GLOW := "_stellar_glow_materials"
const META_GLOW_INSTANCE := "stellar_glow_material"
## Per-instance ground marks that crumble with the body like the contact disc: an elite's
## aura (2026-10-19), driven through the same `fade` instance uniform.
const META_AURA := "_stellar_aura"
const IRIS_MATERIAL := "Eye_brown_radial_iris"

## Rim light in the skin's own colour: a painted edge light, not a blue plastic sheen.
const RIM := 0.22
const RIM_TINT := 0.85
## Textured skins: wrap width (the terminator wraps to NdotL = -roughness) and the
## amount of the toon specular disc on the authored-metal heroes (cloth has none).
const SKIN_ROUGHNESS := 0.62
const SKIN_SPECULAR := 0.18
## Cool tint on the shade side of every light (BaseMaterial3D backlight). It is added
## per light, so the rear rim light stays weak (StellarLighting.RIM_ENERGY_MAX) and the
## value is half the proposal's: the A/B of 2026-10-18 (off / this / double) in
## build/casual-overhaul/after/wp-b/ab.
const SHADE_TINT := Color(0.15, 0.17, 0.25)
const SHADE_TINT_ENABLED := true
## Plain multiplier on the skin albedo: 1.0 ships (the painted atlases carry their own
## light); 1.15 is only the fallback while the re-bake has not landed.
const ALBEDO_LIFT := 1.0
## Hit flash: a short warm brightening of the skin texture (emission multiplied by the
## albedo texture, so the silhouette and markings stay readable instead of a white
## cut-out). The simulator's flash starts at 1 and decays 5/s; the smoothstep window
## keeps the white on the first one or two frames only, so the coloured squash of the
## body (the adapters' hit reaction) is what the eye keeps.
const FLASH_COLOR := Color(1.0, 0.92, 0.78)
const FLASH_ENERGY := 2.6
const FLASH_WHITE := Vector2(0.80, 0.95)
## Dissolve: dithered fade whose body glows cold in its own detail.
const DISSOLVE_COLOR := Color(0.55, 0.90, 1.0)
const DISSOLVE_ENERGY := 1.9
## Dissolve shaping over the adapter's death progress q (0..1): the body stays whole
## while the death pose plays, then crumbles quickly so the dithered half-state is brief.
const DISSOLVE_HOLD := 0.30
const DISSOLVE_END := 0.92
## The dither's amount is `smoothstep(fade_min, fade_max, distance to the camera)`. A
## window this wide around a typical view distance makes that practically one value for
## every pixel of the body (it drifts by about 1% over the whole 80-unit view depth), so
## shifting the window sets the visible fraction of the instance: no camera maths, two
## uniforms. Every value stays inside +-16384, the range a mediump float must hold, in
## case a mobile driver evaluates the comparison below full precision.
const DITHER_WINDOW := 8000.0
const DITHER_CENTRE := 30.0
## Inverted-hull outline (2026-10-18): a 1 px night-shade ink line around heroes and a
## 1.5 px one around bosses, pixel-constant through the boss zoom, never on swarm, fast,
## caster or tank bodies (cost; their separation is value and the contact disc). One
## shared ShaderMaterial per width hangs as the skin's next_pass; the user's decision
## (PLAN §7-1) is this one flag.
const OUTLINE_ENABLED := true
const OUTLINE_HERO_PX := 1.0
const OUTLINE_BOSS_PX := 1.5
const OUTLINE_COLOR := Color(0.055, 0.047, 0.11)
## Elite monsters (2026-10-19, feedback O5/M6): a violet line of light instead of ink, on
## that one instance only (outline_instance), so an elite reads at 35 px among its own kind.
const OUTLINE_ELITE_PX := 1.6
const OUTLINE_ELITE_COLOR := Color(0.58, 0.28, 1.0)
const OUTLINE_SHADER := preload("res://art/models/skin_outline.gdshader")

static var _outlines: Dictionary = {}

static func style(node: Node, metal: float) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null: continue
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var colored: bool = arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty()
			_tune(mat, metal, colored)
	for child in node.get_children(): style(child, metal)

## Shared look of a skinned surface: wrapped diffuse (a soft terminator that lifts the
## shade side), no specular on cloth and skin (a toon disc only where the character
## authors metal), rim in the skin's colour, the cool shade tint, authored metal amount,
## unfogged. Idempotent: style() runs again for every rank of a hero.
static func _tune(mat: StandardMaterial3D, metal: float, colored: bool) -> void:
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON if metal > 0.0 else BaseMaterial3D.SPECULAR_DISABLED
	mat.metallic_specular = SKIN_SPECULAR
	mat.clearcoat_enabled = false
	if mat.albedo_texture != null:
		mat.roughness_texture = null
		mat.metallic_texture = null
		mat.roughness = SKIN_ROUGHNESS
		mat.metallic = metal
	if colored:
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = false
	mat.rim_enabled = true
	mat.rim = RIM
	mat.rim_tint = RIM_TINT
	mat.backlight_enabled = SHADE_TINT_ENABLED
	mat.backlight = SHADE_TINT
	mat.disable_fog = true
	if ALBEDO_LIFT != 1.0:
		mat.albedo_color = Color(ALBEDO_LIFT, ALBEDO_LIFT, ALBEDO_LIFT, mat.albedo_color.a)

## Hangs the hull outline on every skinned, non-emissive skin surface under `root`
## (Brasa's reactor lens and Limne's irises are skipped) as the base material's
## next_pass, and on any per-instance override that already exists (monsters are
## prepared before the hull is asked for; later overrides duplicate the base and
## inherit the reference). get_active_material(i) never returns a next_pass, so the
## skin contract is untouched.
static func outline(root: Node3D, width_px: float) -> void:
	if not OUTLINE_ENABLED or width_px <= 0.0: return
	_outline(root, _outline_material(width_px))
	# A live instance records its outlined nodes now; a model still being built (no
	# overrides yet) records them in prepare_instance, which runs once it is live.
	if root.has_meta(META_MATERIALS): _collect_outline_nodes(root)

static func _outline(node: Node, hull: ShaderMaterial) -> void:
	if node is MeshInstance3D and node.mesh != null and node.skin != null:
		for i in node.mesh.get_surface_count():
			var base := node.mesh.surface_get_material(i) as StandardMaterial3D
			if base == null or base.emission_enabled or base.resource_name == IRIS_MATERIAL: continue
			base.next_pass = hull
			var override := node.get_surface_override_material(i) as StandardMaterial3D
			if override != null and override.has_meta(META_INSTANCE): override.next_pass = hull
	for child in node.get_children(): _outline(child, hull)

## One shared hull material per line width and colour (heroes, bosses, elites).
static func _outline_material(width_px: float, color: Color = OUTLINE_COLOR) -> ShaderMaterial:
	var key := "%.2f/%s" % [width_px, color.to_html()]
	if _outlines.has(key): return _outlines[key]
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mat.resource_name = "StellarOutline"
	mat.set_shader_parameter("width_px", width_px)
	mat.set_shader_parameter("line_color", color)
	mat.set_meta(META_OUTLINE, true)
	_outlines[key] = mat
	return mat

## A hull on this live instance only: an elite shares its monster type's base materials
## with its ordinary kin, so the line hangs on the instance's own skin overrides (made by
## prepare_instance, never the base) and dissolves with them. Glow surfaces and irises
## are skipped as in outline().
static func outline_instance(root: Node3D, width_px: float, color: Color) -> void:
	if not OUTLINE_ENABLED or width_px <= 0.0: return
	prepare_instance(root)
	_outline_instance(root, _outline_material(width_px, color))
	_collect_outline_nodes(root)

static func _outline_instance(node: Node, hull: ShaderMaterial) -> void:
	if node is MeshInstance3D and node.mesh != null and node.skin != null:
		for i in node.mesh.get_surface_count():
			var mat := node.get_surface_override_material(i) as StandardMaterial3D
			if mat != null and mat.has_meta(META_INSTANCE) and mat.resource_name != IRIS_MATERIAL: mat.next_pass = hull
	for child in node.get_children(): _outline_instance(child, hull)

static func _collect_outline_nodes(root: Node3D) -> void:
	var nodes: Array = []
	_find_outlined(root, nodes)
	root.set_meta(META_OUTLINE_NODES, nodes)

static func _find_outlined(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var mat := node.get_active_material(i) as StandardMaterial3D
			if mat != null and mat.next_pass != null and mat.next_pass.has_meta(META_OUTLINE):
				out.append(node)
				break
	for child in node.get_children(): _find_outlined(child, out)

## Called once per live instance after instantiation (never per frame). Creates this
## instance's own surface materials; later calls only update their values. Idempotent.
static func prepare_instance(root: Node3D) -> void:
	if root.has_meta(META_MATERIALS): return
	var materials: Array[StandardMaterial3D] = []
	var glows: Array[StandardMaterial3D] = []
	_prepare(root, materials, glows)
	root.set_meta(META_MATERIALS, materials)
	if not glows.is_empty(): root.set_meta(META_GLOW, glows)
	_collect_outline_nodes(root)
	if not root.has_meta(META_FLASH): root.set_meta(META_FLASH, 0.0)
	if not root.has_meta(META_DISSOLVE): root.set_meta(META_DISSOLVE, 0.0)

## Skin surfaces get the flash/dissolve override; authored glow surfaces (emission on the
## base, e.g. ember_imp's crown) get their own duplicate that only ever dithers: it keeps
## the authored emission colour, energy and texture, a hit flash never writes it, and it
## crumbles (shadow included) with the body. Before 2026-10-19 they were skipped and the
## crown kept glowing alone after the body had gone (feedback X1).
static func _prepare(node: Node, out: Array[StandardMaterial3D], glows: Array[StandardMaterial3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var existing := node.get_surface_override_material(i) as StandardMaterial3D
			if existing != null and existing.has_meta(META_INSTANCE):
				out.append(existing)
				continue
			if existing != null and existing.has_meta(META_GLOW_INSTANCE):
				glows.append(existing)
				continue
			if existing != null: continue   # an adapter owns this surface (e.g. reactor accents)
			var base := node.mesh.surface_get_material(i) as StandardMaterial3D
			if base == null: continue
			if base.emission_enabled:
				var glow := base.duplicate() as StandardMaterial3D
				glow.set_meta(META_GLOW_INSTANCE, true)
				glow.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
				_set_visible(glow, 1.0)
				node.set_surface_override_material(i, glow)
				glows.append(glow)
				continue
			var instance := base.duplicate() as StandardMaterial3D
			instance.set_meta(META_INSTANCE, true)
			_instance_features(instance)
			node.set_surface_override_material(i, instance)
			out.append(instance)
	for child in node.get_children(): _prepare(child, out, glows)

## Per-instance state lives in features that are enabled once and only have their
## values changed later. Toggling a feature at runtime would recompile the shader.
static func _instance_features(mat: StandardMaterial3D) -> void:
	mat.emission_enabled = true
	mat.emission = FLASH_COLOR
	mat.emission_energy_multiplier = 0.0
	# Emission = colour x emission texture; using the skin texture there keeps the
	# flash and the dissolve glow shaped by the body's own markings.
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	if mat.albedo_texture != null: mat.emission_texture = mat.albedo_texture
	# The dissolve dither stays in the opaque pass (depth, shadows, sorting intact) and
	# reads as disintegration while the body thins. Alpha is never used: see the header.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var albedo := mat.albedo_color
	albedo.a = 1.0
	mat.albedo_color = albedo
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	_set_visible(mat, 1.0)

## Fraction 0..1 of a prepared material's pixels that survive the dither (1 whole, 0 gone).
static func _set_visible(mat: StandardMaterial3D, fraction: float) -> void:
	# Whole and gone sit entirely on one side of the window, so they are exact: a live
	# body never loses a stray pixel and a finished one never keeps one.
	var t := 1.5 if fraction >= 1.0 else -0.5 if fraction <= 0.0 else _inverse_smoothstep(fraction)
	var low := DITHER_CENTRE - t * DITHER_WINDOW
	if is_equal_approx(mat.distance_fade_min_distance, low): return
	mat.distance_fade_min_distance = low
	mat.distance_fade_max_distance = low + DITHER_WINDOW

## x with smoothstep(0, 1, x) = y, so the dither's own smoothstep cancels out.
static func _inverse_smoothstep(y: float) -> float:
	return 0.5 - sin(asin(1.0 - 2.0 * clampf(y, 0.0, 1.0)) / 3.0)

static func _materials(root: Node3D) -> Array:
	if not root.has_meta(META_MATERIALS): prepare_instance(root)
	return root.get_meta(META_MATERIALS)

## amount 0..1: brief whitening/emissive flash when the simulation reports a hit.
static func set_hit_flash(root: Node3D, amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if root.has_meta(META_FLASH) and float(root.get_meta(META_FLASH)) == amount: return
	var idle := amount == 0.0 and not root.has_meta(META_FLASH)
	root.set_meta(META_FLASH, amount)
	if idle and not root.has_meta(META_MATERIALS): return
	_apply(root)

## amount 0..1: death dissolve progress (1 = fully gone).
static func set_dissolve(root: Node3D, amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if root.has_meta(META_DISSOLVE) and float(root.get_meta(META_DISSOLVE)) == amount: return
	var idle := amount == 0.0 and not root.has_meta(META_DISSOLVE)
	root.set_meta(META_DISSOLVE, amount)
	if idle and not root.has_meta(META_MATERIALS): return
	_apply(root)

static func hit_flash(root: Node3D) -> float:
	return float(root.get_meta(META_FLASH, 0.0))

## A critical or weak-point hit: the body's flash (the simulator's mo.flash, applied by
## the world every frame) is pushed `strength` (0..1) brighter and toward `color` until it
## has decayed. Applied at once if the body is flashing already.
static func set_hit_accent(root: Node3D, strength: float, color: Color) -> void:
	root.set_meta(META_ACCENT, {"strength": clampf(strength, 0.0, 1.0), "color": color})
	if float(root.get_meta(META_FLASH, 0.0)) > 0.0: _apply(root)

static func dissolve(root: Node3D) -> float:
	return float(root.get_meta(META_DISSOLVE, 0.0))

static func _apply(root: Node3D) -> void:
	var flash := float(root.get_meta(META_FLASH, 0.0))
	var q := float(root.get_meta(META_DISSOLVE, 0.0))
	# Whole body until DISSOLVE_HOLD, then a quick crumble; the cold glow rises just
	# before the crumble and peaks while the body thins, so the half-state never reads
	# as a flat cut-out. A hit flash during the fade wins when it is brighter.
	var fade := smoothstep(DISSOLVE_HOLD, DISSOLVE_END, q)
	var glow := sin(clampf((q - DISSOLVE_HOLD * 0.6) / (1.0 - DISSOLVE_HOLD * 0.6), 0.0, 1.0) * PI)
	var flash_color := FLASH_COLOR
	var flash_energy := FLASH_ENERGY * smoothstep(FLASH_WHITE.x, FLASH_WHITE.y, flash)
	if root.has_meta(META_ACCENT):
		if flash <= 0.0:
			root.remove_meta(META_ACCENT)
		else:
			var accent: Dictionary = root.get_meta(META_ACCENT)
			var strength := float(accent.get("strength", 0.5))
			flash_energy *= 1.0 + strength
			flash_color = FLASH_COLOR.lerp(Color(accent.get("color", FLASH_COLOR)), 0.4 + 0.3 * strength)
	var energy := maxf(flash_energy, glow * DISSOLVE_ENERGY)
	var color := flash_color if flash_energy >= glow * DISSOLVE_ENERGY else DISSOLVE_COLOR
	var whole := 1.0 - fade
	for mat in _materials(root):
		mat.emission_energy_multiplier = energy
		mat.emission = color
		_set_visible(mat, whole)
	# Authored glow keeps its own light and only thins with the body.
	for mat in root.get_meta(META_GLOW, []):
		_set_visible(mat, whole)
	# The hull, the contact disc and an elite's aura crumble with the body (instance
	# uniforms on shared materials; nothing is created here).
	for node in root.get_meta(META_OUTLINE_NODES, []):
		if is_instance_valid(node): node.set_instance_shader_parameter(&"cut", whole)
	for key in [META_CONTACT, META_AURA]:
		if not root.has_meta(key): continue
		var mark: Node = root.get_meta(key)
		if is_instance_valid(mark): mark.set_instance_shader_parameter(&"fade", whole)
