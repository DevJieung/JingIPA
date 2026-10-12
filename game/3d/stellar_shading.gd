extends RefCounted
class_name StellarShading

## Surface styling shared by native heroes and monsters, plus per-instance
## hit-flash / dissolve state used by motion and effect code. Visual only.
##
## style(root, metal) runs at model creation (pre-pack for heroes) and only tunes the
## shared GLB materials: soft specular, authored metal amount, rim light.
##
## GL Compatibility has no per-instance shader uniforms, so per-instance state needs
## a material per live instance. prepare_instance(root) creates one StandardMaterial3D
## override per skinned surface (a duplicate of the shared material with emission at
## energy 0 and the dissolve dither at "whole") once, when the live instance
## enters the world's actor tree (StellarVfx connects actors.child_entered_tree) or on
## its first non-zero flash/dissolve. Later frames only change values, never create
## resources. Overrides are deliberately not created before packing: the headless
## (dummy) renderer cannot enumerate packed local-to-scene override materials, and the
## skin contract checks that a card's resource set is stable while it animates.
##
## Why StandardMaterial3D and not a ShaderMaterial: the skin contract reads
## get_active_material(i) as a BaseMaterial3D carrying the albedo texture, and the
## standard material already provides rim light, emission and a pixel dither.
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

## Rim light separates the silhouette from the night ground under the cool back light.
const RIM := 0.34
const RIM_TINT := 0.55
## Textured skins: a believable soft specular instead of the old flat plastic 0.84/0.16.
const SKIN_ROUGHNESS := 0.70
const SKIN_SPECULAR := 0.33
## Hit flash: a short warm brightening of the skin texture (emission multiplied by the
## albedo texture, so the silhouette and markings stay readable instead of a white
## cut-out); dissolve: dithered fade whose body glows cold in its own detail.
const FLASH_COLOR := Color(1.0, 0.92, 0.78)
const FLASH_ENERGY := 1.5
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

static func style(node: Node, metal: float) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null: continue
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var colored: bool = arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty()
			_tune(mat, metal, colored)
	for child in node.get_children(): style(child, metal)

## Shared look of a skinned surface: soft specular, rim, authored metal amount.
static func _tune(mat: StandardMaterial3D, metal: float, colored: bool) -> void:
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

## Called once per live instance after instantiation (never per frame). Creates this
## instance's own surface materials; later calls only update their values. Idempotent.
static func prepare_instance(root: Node3D) -> void:
	if root.has_meta(META_MATERIALS): return
	var materials: Array[StandardMaterial3D] = []
	_prepare(root, materials)
	root.set_meta(META_MATERIALS, materials)
	if not root.has_meta(META_FLASH): root.set_meta(META_FLASH, 0.0)
	if not root.has_meta(META_DISSOLVE): root.set_meta(META_DISSOLVE, 0.0)

static func _prepare(node: Node, out: Array[StandardMaterial3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var existing := node.get_surface_override_material(i) as StandardMaterial3D
			if existing != null and existing.has_meta(META_INSTANCE):
				out.append(existing)
				continue
			if existing != null: continue   # an adapter owns this surface (e.g. reactor accents)
			var base := node.mesh.surface_get_material(i) as StandardMaterial3D
			if base == null or base.emission_enabled: continue
			var instance := base.duplicate() as StandardMaterial3D
			instance.set_meta(META_INSTANCE, true)
			_instance_features(instance)
			node.set_surface_override_material(i, instance)
			out.append(instance)
	for child in node.get_children(): _prepare(child, out)

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
	var energy := maxf(flash * FLASH_ENERGY, glow * DISSOLVE_ENERGY)
	var color := FLASH_COLOR if flash * FLASH_ENERGY >= glow * DISSOLVE_ENERGY else DISSOLVE_COLOR
	for mat in _materials(root):
		mat.emission_energy_multiplier = energy
		mat.emission = color
		_set_visible(mat, 1.0 - fade)
