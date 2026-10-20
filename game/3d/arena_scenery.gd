extends RefCounted

## Instanced static scenery of an arena battlefield. Visual only.
##
## Every prop is an instance of a small shared template mesh: one MultiMesh per template
## a field uses and one material for all of them. A whole biome's surroundings cost a few
## dozen draw calls and a few milliseconds to rebuild at a stage switch, where merging
## thousands of primitives into unique geometry cost hundreds (see docs/BATTLEFIELD_BIOMES.md).
##
## Template vertex data (read by art/models/arena_scenery.gdshader):
##   UV.x  baked shade        UV.y  blend toward the instance's second tint
##   UV2.x sway weight        UV2.y cover weight (snow / moss on upward faces), +2 where
##                                  the vertex may glow (the instance decides how much)
##
## Contact pools (2026-10-18, Lantern Stage): every standing prop of a solid kind gets a
## flat "contact" quad on the ground under it, drawn with art/models/arena_contact_decal
## .gdshader as one more MultiMesh, so trees, rocks and posts sit in a pool of shadow
## instead of floating on the land. Kerb skirts and the plaza rim use the same shader as
## generated meshes (decal_mesh()).

const SHADER := preload("res://art/models/arena_scenery.gdshader")
const DECAL_SHADER := preload("res://art/models/arena_contact_decal.gdshader")
const FLOATS := 20
## Templates too thin or flat to need a place in the shadow pass.
const NO_SHADOW := ["tuft", "reed", "pad", "slab0", "slab1", "slab2", "contact"]
## Kinds (by template base name) that stand in a contact pool: [strength, pool size as a
## multiple of the footprint]. Compact props need a wide pool (their body covers its
## centre from the camera); trees keep a tighter one under their overhanging crown.
const CONTACT_KINDS := {"rock": [0.6, 1.9], "tree": [0.55, 1.4], "fir": [0.55, 1.5], "dead": [0.5, 1.9], "mush": [0.5, 1.7],
	"column": [0.6, 2.0], "spire": [0.55, 1.9], "dome": [0.4, 1.5], "hoodoo": [0.6, 1.8], "crystal": [0.55, 1.9], "slab": [0.4, 1.5]}
## Widest pool in world units: a bigger one would cut into the bumps of the land.
const CONTACT_MAX := 3.2
static var _templates: Dictionary = {}

var material := ShaderMaterial.new()
## Material of the contact pools (instances) and of the generated skirt meshes.
var decal_material := ShaderMaterial.new()
var skirt_material := ShaderMaterial.new()
## Whether the instances placed next take the field's cover (snow, moss, ash) on their
## upward faces. The sanctuary and anything that must keep its own colour turn it off.
var covered := true
## Whether stand() lays a contact pool under solid props (off for the sanctuary).
var pools := true
## Colour of the pools: the field's haze, darkened (set by the biome).
var pool_color := Color(0.03, 0.05, 0.07)
## Ground height function (x, z) -> y of the land, so a pool lies on the land's slope;
## unset, pools lie level at the prop's own foot.
var ground_height := Callable()
## Surface of the field's water or lava: props standing below it get no pool (the
## liquid hides the land anyway).
var water_level := -INF
var _buffers: Dictionary = {}
var _decal_meshes: Array[ArrayMesh] = []

func _init() -> void:
	material.shader = SHADER
	decal_material.shader = DECAL_SHADER
	decal_material.render_priority = 1
	skirt_material.shader = DECAL_SHADER
	skirt_material.render_priority = 1
	skirt_material.set_shader_parameter("vertex_strength", 1.0)

# --------------------------------------------------------------------------- #
# Placing instances
# --------------------------------------------------------------------------- #
## One instance of `kind`. `second` tints the template's secondary parts (trunk, stem,
## leaves); `glow` lights the parts the template marks; `sway` moves foliage tips.
func add(kind: String, xform: Transform3D, color: Color, second: Color = Color.BLACK,
		glow: float = 0.0, sway: float = 0.0) -> void:
	_push(kind, xform, color, second.srgb_to_linear(), 1.0 - clampf(glow, 0.0, 1.0), sway if covered else -1.0)

## One raw instance: `alpha` is the colour's alpha slot (1 - glow), `custom_a` the custom
## data's alpha slot (sway; below 0 = never covered; the pool strength of a decal).
func _push(kind: String, xform: Transform3D, color: Color, second: Color, alpha: float, custom_a: float) -> void:
	var buffer: PackedFloat32Array = _buffers.get(kind, PackedFloat32Array())
	var b := xform.basis
	var o := xform.origin
	# The renderer linearises instance (and vertex) colours itself; custom data is raw.
	buffer.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z, color.r, color.g, color.b, alpha, second.r, second.g, second.b, custom_a]))
	_buffers[kind] = buffer

## A scaled, rotated primitive, like StellarModels.part().
func part(kind: String, at: Vector3, dimensions: Vector3, color: Color, glow: float = 0.0,
		angles: Vector3 = Vector3.ZERO) -> void:
	add(kind, Transform3D(Basis.from_euler(angles) * Basis.from_scale(dimensions), at), color, color, glow)

## A cylinder from `a` to `b`.
func link(a: Vector3, b: Vector3, radius: float, color: Color, glow: float = 0.0, kind: String = "cylinder") -> void:
	var direction := b - a
	var length := direction.length()
	if length < 0.0001: return
	var basis := Basis(Quaternion(Vector3.UP, direction / length)) * Basis.from_scale(Vector3(radius, length, radius))
	add(kind, Transform3D(basis, (a + b) * 0.5), color, color, glow)

## An upright prop standing on the ground: `size` is (width, height, depth) in world
## units for a template that is one unit wide and tall.
func stand(kind: String, at: Vector3, size: Vector3, yaw: float, color: Color, second: Color = Color.BLACK,
		glow: float = 0.0, sway: float = 0.0, lean: Vector2 = Vector2.ZERO) -> void:
	var basis := Basis.from_euler(Vector3(lean.x, yaw, lean.y)) * Basis.from_scale(size)
	add(kind, Transform3D(basis, at), color, second, glow, sway)
	if not pools: return
	var spec: Array = CONTACT_KINDS.get(kind.rstrip("0123456789"), [])
	if not spec.is_empty(): contact(at, Vector2(size.x, size.z) * float(spec[1]), float(spec[0]))

## A pool of contact shadow lying on the ground at `at`, `size` across in world units.
## Skipped for things that hang or stack well above the land and for things standing in
## the water. The quad follows the land's slope so it lies on the surface.
func contact(at: Vector3, size: Vector2, strength: float = 0.55, yaw: float = 0.0) -> void:
	var across := Vector2(minf(size.x, CONTACT_MAX), minf(size.y, CONTACT_MAX))
	var normal := Vector3.UP
	var y := at.y
	if ground_height.is_valid():
		var step := maxf(0.25, across.x * 0.3)
		var h := float(ground_height.call(at.x, at.z))
		# Hanging or stacked things get none; sunk things (piles, half-buried rocks) do.
		if at.y - h > 0.35 or at.y - h < -0.9: return
		y = h
		var dx := (float(ground_height.call(at.x + step, at.z)) - float(ground_height.call(at.x - step, at.z))) / (2.0 * step)
		var dz := (float(ground_height.call(at.x, at.z + step)) - float(ground_height.call(at.x, at.z - step))) / (2.0 * step)
		normal = Vector3(-dx, 1.0, -dz).normalized()
	if y < water_level - 0.03: return
	var tx := (Vector3.RIGHT - normal * normal.x).normalized()
	var tz := tx.cross(normal).normalized()
	var basis := Basis(normal, yaw) * Basis(tx * across.x, normal, tz * across.y)
	# Lifted 0.05 u (1.5 px on screen): the land mesh interpolates between its rings by a
	# few hundredths, and a pool under that surface is hidden by the depth test.
	_push("contact", Transform3D(basis, Vector3(at.x, y, at.z) + normal * 0.05), pool_color, Color.BLACK, 1.0, strength)

## A generated mesh drawn with the pool shader: vertex colour = pool colour, vertex
## alpha = strength (kerb skirts, the plaza rim). One draw each.
func decal_mesh(mesh: ArrayMesh) -> void:
	if mesh != null and mesh.get_surface_count() > 0: _decal_meshes.append(mesh)

func count() -> int:
	var total := 0
	for kind in _buffers: total += (_buffers[kind] as PackedFloat32Array).size() / FLOATS
	return total

## Create the MultiMeshes under `parent`. Call once, after every instance was placed.
func commit(parent: Node3D) -> void:
	for kind in _buffers:
		var buffer: PackedFloat32Array = _buffers[kind]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = template(kind)
		multimesh.instance_count = buffer.size() / FLOATS
		multimesh.buffer = buffer
		var node := MultiMeshInstance3D.new()
		node.name = "Scenery_" + String(kind)
		node.multimesh = multimesh
		node.material_override = decal_material if kind == "contact" else material
		if kind in NO_SHADOW: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
	_buffers.clear()
	for mesh in _decal_meshes:
		var node := MeshInstance3D.new()
		node.name = "Scenery_skirt"
		node.mesh = mesh
		node.material_override = skirt_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
	_decal_meshes.clear()

# --------------------------------------------------------------------------- #
# Templates
# --------------------------------------------------------------------------- #
static func template(kind: String) -> ArrayMesh:
	if _templates.has(kind): return _templates[kind]
	var mesh: ArrayMesh
	var base := kind.rstrip("0123456789")
	var variant := int(kind.substr(base.length())) if kind.length() > base.length() else 0
	match base:
		"box", "stone", "cylinder", "cone", "pentagon", "sphere", "ring": mesh = _from_primitive(kind)
		"pyramid": mesh = _pyramid()
		"dome": mesh = _dome()
		"arch": mesh = _arch()
		"rock": mesh = _rock(variant)
		"spire": mesh = _spire(variant)
		"column": mesh = _column()
		"hoodoo": mesh = _hoodoo(variant)
		"fir": mesh = _fir(variant)
		"tree": mesh = _tree(variant)
		"dead": mesh = _dead(variant)
		"mush": mesh = _mushroom(variant)
		"tuft": mesh = _tuft(7, 0.42, false, 11)
		"reed": mesh = _tuft(8, 0.20, true, 23)
		"bamboo": mesh = _bamboo()
		"slab": mesh = _slab(variant)
		"pad": mesh = _pad()
		"crystal": mesh = _crystal(variant)
		"contact": mesh = _contact()
		_:
			push_error("unknown scenery template " + kind)
			mesh = _from_primitive("box")
	_templates[kind] = mesh
	return mesh

## Accumulates one template.
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var a := PackedVector2Array()
	var b := PackedVector2Array()

	## Flat triangle whose front faces `out`. `shade`, `sway` are per corner.
	func tri(p0: Vector3, p1: Vector3, p2: Vector3, out: Vector3, shade: Vector3, mask: float = 0.0,
			sway: Vector3 = Vector3.ZERO, extra: float = 1.0) -> void:
		var normal := (p1 - p0).cross(p2 - p0)
		if normal.length_squared() < 1.0e-12: return
		normal = normal.normalized()
		var order := [0, 1, 2]
		# Godot front faces wind clockwise: the geometric normal must point away from `out`.
		if normal.dot(out) > 0.0: order = [0, 2, 1]
		else: normal = -normal
		var points := [p0, p1, p2]
		for i in order:
			v.append(points[i])
			n.append(normal)
			a.append(Vector2(shade[i], mask))
			b.append(Vector2(sway[i], extra))

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, out: Vector3, shade: Array, mask: float = 0.0,
			sway: Array = [0.0, 0.0, 0.0, 0.0], extra: float = 1.0) -> void:
		tri(p0, p1, p2, out, Vector3(shade[0], shade[1], shade[2]), mask, Vector3(sway[0], sway[1], sway[2]), extra)
		tri(p0, p2, p3, out, Vector3(shade[0], shade[2], shade[3]), mask, Vector3(sway[0], sway[2], sway[3]), extra)

	## Smooth triangle with given normals (winding fixed against the first normal).
	func smooth(p: Array, normals: Array, shade: Array, mask: float = 0.0, sway: Array = [0.0, 0.0, 0.0], extra: float = 1.0) -> void:
		var order := [0, 1, 2]
		if ((p[1] - p[0]) as Vector3).cross(p[2] - p[0]).dot(normals[0] + normals[1] + normals[2]) > 0.0: order = [0, 2, 1]
		for i in order:
			v.append(p[i])
			n.append((normals[i] as Vector3).normalized())
			a.append(Vector2(shade[i], mask))
			b.append(Vector2(sway[i], extra))

	## Flat-shaded skin between rings of equal size (closed loops), bottom to top.
	func loft(rings: Array, centres: Array, shades: Array, mask: float = 0.0, sways: Array = [], extra: float = 1.0) -> void:
		for level in range(rings.size() - 1):
			var low: PackedVector3Array = rings[level]
			var high: PackedVector3Array = rings[level + 1]
			var s0: float = sways[level] if not sways.is_empty() else 0.0
			var s1: float = sways[level + 1] if not sways.is_empty() else 0.0
			for i in range(low.size()):
				var j := (i + 1) % low.size()
				var out := (low[i] + low[j] + high[i] + high[j]) * 0.25 - ((centres[level] as Vector3) + (centres[level + 1] as Vector3)) * 0.5
				quad(low[i], low[j], high[j], high[i], out, [shades[level], shades[level], shades[level + 1], shades[level + 1]], mask, [s0, s0, s1, s1], extra)

	## Fan from a closed ring to one point (a tip above, or a floor below).
	func fan(ring: PackedVector3Array, tip: Vector3, centre: Vector3, shade_ring: float, shade_tip: float, mask: float = 0.0,
			sway_ring: float = 0.0, sway_tip: float = 0.0, extra: float = 1.0) -> void:
		for i in range(ring.size()):
			var j := (i + 1) % ring.size()
			var out := (ring[i] + ring[j] + tip) / 3.0 - centre
			tri(ring[i], ring[j], tip, out, Vector3(shade_ring, shade_ring, shade_tip), mask, Vector3(sway_ring, sway_ring, sway_tip), extra)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = a
		arrays[Mesh.ARRAY_TEX_UV2] = b
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out

static func _ring(centre: Vector3, radius: float, sides: int, rng: RandomNumberGenerator = null, jitter: float = 0.0,
		turn: float = 0.0, squash: float = 1.0) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(sides):
		var angle := TAU * float(i) / float(sides) + turn
		var r := radius * (1.0 + (rng.randf_range(-jitter, jitter) if rng != null else 0.0))
		points.append(centre + Vector3(cos(angle) * r, 0.0, sin(angle) * r * squash))
	return points

## The shared primitives with the scenery vertex layout. Shade rises with height so a
## pillar is a little darker at its foot.
static func _from_primitive(kind: String) -> ArrayMesh:
	var source: Mesh = StellarModels.primitive(kind)
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var shade := PackedVector2Array()
	var extra := PackedVector2Array()
	shade.resize(vertices.size())
	extra.resize(vertices.size())
	for i in range(vertices.size()):
		shade[i] = Vector2(0.78 + 0.22 * clampf(vertices[i].y + 0.5, 0.0, 1.0), 0.0)
		extra[i] = Vector2(0.0, 3.0)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
	out[Mesh.ARRAY_TEX_UV] = shade
	out[Mesh.ARRAY_TEX_UV2] = extra
	out[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh

## Unit icosphere: {"v": Array[Vector3], "f": Array of [i, j, k]}.
static func _icosphere(level: int) -> Dictionary:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = []
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
			Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((p as Vector3).normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6],
		[7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for step in range(level):
		var cache := {}
		var next: Array = []
		for face in faces:
			var mid: Array = []
			for e in range(3):
				var i0: int = face[e]
				var i1: int = face[(e + 1) % 3]
				var key := Vector2i(mini(i0, i1), maxi(i0, i1))
				if not cache.has(key):
					verts.append(((verts[i0] + verts[i1]) * 0.5).normalized())
					cache[key] = verts.size() - 1
				mid.append(cache[key])
			next.append([face[0], mid[0], mid[2]])
			next.append([face[1], mid[1], mid[0]])
			next.append([face[2], mid[2], mid[1]])
			next.append([mid[0], mid[1], mid[2]])
		faces = next
	return {"v": verts, "f": faces}

## A lump of faceted geometry from a displaced icosphere, standing on y = 0.
static func _blob(geo: Geo, rng: RandomNumberGenerator, level: int, centre: Vector3, size: Vector3, rough: float,
		shade_low: float, shade_high: float, mask: float = 0.0, sway: float = 0.0, flat_base: float = -2.0, extra: float = 1.0) -> void:
	var sphere := _icosphere(level)
	var points: Array[Vector3] = []
	for p in sphere["v"]:
		var q: Vector3 = (p as Vector3) * (1.0 + rng.randf_range(-rough, rough))
		q.y = maxf(q.y, flat_base)
		points.append(centre + q * size * 0.5)
	var low := centre.y - size.y * 0.5
	var span := maxf(0.001, size.y)
	for face in sphere["f"]:
		var p0 := points[face[0]]
		var p1 := points[face[1]]
		var p2 := points[face[2]]
		var out := (p0 + p1 + p2) / 3.0 - centre
		var tone := rng.randf_range(-0.035, 0.035)
		var shades := Vector3.ZERO
		var sways := Vector3.ZERO
		for i in range(3):
			var height := clampf(([p0, p1, p2][i].y - low) / span, 0.0, 1.0)
			shades[i] = lerpf(shade_low, shade_high, height) + tone
			sways[i] = sway * height
		geo.tri(p0, p1, p2, out, shades, mask, sways, extra)

static func _pyramid() -> ArrayMesh:
	var geo := Geo.new()
	var base := _ring(Vector3.ZERO, 0.7071, 4, null, 0.0, PI / 4.0)
	geo.fan(base, Vector3(0, 1, 0), Vector3(0, 0.3, 0), 0.86, 1.0)
	geo.fan(base, Vector3.ZERO, Vector3(0, 0.3, 0), 0.6, 0.6, 0.0, 0.0, 0.0, 0.0)
	return geo.mesh()

## Smooth half sphere, radius 0.5, flat on y = 0.
static func _dome() -> ArrayMesh:
	var geo := Geo.new()
	var rings := 4
	var sides := 12
	for level in range(rings):
		var e0 := PI * 0.5 * float(level) / rings
		var e1 := PI * 0.5 * float(level + 1) / rings
		for i in range(sides):
			var a0 := TAU * float(i) / sides
			var a1 := TAU * float(i + 1) / sides
			var p00 := Vector3(cos(a0) * cos(e0), sin(e0), sin(a0) * cos(e0))
			var p10 := Vector3(cos(a1) * cos(e0), sin(e0), sin(a1) * cos(e0))
			var p01 := Vector3(cos(a0) * cos(e1), sin(e1), sin(a0) * cos(e1))
			var p11 := Vector3(cos(a1) * cos(e1), sin(e1), sin(a1) * cos(e1))
			var s0 := 0.80 + 0.22 * sin(e0)
			var s1 := 0.80 + 0.22 * sin(e1)
			geo.smooth([p00 * 0.5, p10 * 0.5, p11 * 0.5], [p00, p10, p11], [s0, s0, s1])
			if level < rings - 1: geo.smooth([p00 * 0.5, p11 * 0.5, p01 * 0.5], [p00, p11, p01], [s0, s1, s1])
	return geo.mesh()

## Half ring standing on y = 0: span one unit along x, half a unit high, one unit deep
## along z (scale the instance). Rectangular section, flat faces.
static func _arch() -> ArrayMesh:
	var geo := Geo.new()
	var steps := 8
	var outer := 0.5
	var inner := 0.34
	for i in range(steps):
		var a0 := PI * float(i) / steps
		var a1 := PI * float(i + 1) / steps
		var o0 := Vector3(cos(a0) * outer, sin(a0) * outer, 0)
		var o1 := Vector3(cos(a1) * outer, sin(a1) * outer, 0)
		var i0 := Vector3(cos(a0) * inner, sin(a0) * inner, 0)
		var i1 := Vector3(cos(a1) * inner, sin(a1) * inner, 0)
		var z := Vector3(0, 0, 0.5)
		var mid := (o0 + o1) * 0.5
		var s0 := 0.84 + 0.2 * sin(a0)
		var s1 := 0.84 + 0.2 * sin(a1)
		geo.quad(o0 - z, o1 - z, o1 + z, o0 + z, mid, [s0, s1, s1, s0])
		geo.quad(i0 - z, i1 - z, i1 + z, i0 + z, -mid, [0.62, 0.62, 0.62, 0.62], 0.0, [0.0, 0.0, 0.0, 0.0], 0.0)
		geo.quad(o0 + z, o1 + z, i1 + z, i0 + z, Vector3(0, 0, 1), [s0, s1, s1 * 0.92, s0 * 0.92])
		geo.quad(o0 - z, o1 - z, i1 - z, i0 - z, Vector3(0, 0, -1), [s0, s1, s1 * 0.92, s0 * 0.92])
	return geo.mesh()

## Faceted boulder, about one unit across and 0.62 high, standing on y = 0.
static func _rock(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + variant * 131
	var geo := Geo.new()
	var tall: Array[float] = [0.74, 0.60, 0.92, 0.50]
	var deep: Array[float] = [0.86, 1.0, 0.78, 0.94]
	var size := Vector3(1.0, tall[variant % 4], deep[variant % 4])
	_blob(geo, rng, 1, Vector3(0, size.y * 0.36, 0), size, 0.17, 0.58, 1.06, 0.0, 0.0, -0.72)
	return geo.mesh()

## Tapering six-sided shard: one unit tall, one wide at the foot. Ice spires, stalagmites.
static func _spire(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301 + variant * 97
	var geo := Geo.new()
	var sides := 6 if variant != 1 else 5
	var lean := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
	var heights: Array[float] = [0.0, 0.30, 0.66]
	var radii: Array[float] = [0.5, 0.40, 0.23]
	var rings: Array = []
	var centres: Array = []
	for level in range(3):
		var centre := Vector3(0, heights[level], 0) + lean * heights[level] * 2.0
		centres.append(centre)
		rings.append(_ring(centre, radii[level], sides, rng, 0.16, variant * 0.4 + level * 0.21))
	var tip := Vector3(0, 1, 0) + lean * 2.6
	geo.loft(rings, centres, [0.74, 0.90, 1.04], 0.0, [], 3.0)
	geo.fan(rings[2], tip, centres[2], 1.04, 1.16, 0.0, 0.0, 0.0, 3.0)
	return geo.mesh()

## Straight six-sided column with a flat top (basalt, piles, pillars).
static func _column() -> ArrayMesh:
	var geo := Geo.new()
	var low := _ring(Vector3.ZERO, 0.5, 6)
	var high := _ring(Vector3(0, 1, 0), 0.5, 6)
	geo.loft([low, high], [Vector3.ZERO, Vector3(0, 1, 0)], [0.74, 1.0])
	geo.fan(high, Vector3(0, 1, 0), Vector3(0, 0.5, 0), 1.04, 1.08)
	return geo.mesh()

## Capped rock pillar (mesa / mushroom rock), one unit tall.
static func _hoodoo(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7501 + variant * 61
	var geo := Geo.new()
	var heights: Array[float] = [0.0, 0.26, 0.56, 0.68, 0.86, 1.0]
	var radii: Array[float] = [0.40, 0.27, 0.24, 0.48, 0.50, 0.36]
	var rings: Array = []
	var centres: Array = []
	for level in range(heights.size()):
		var centre := Vector3(rng.randf_range(-0.03, 0.03), heights[level], rng.randf_range(-0.03, 0.03))
		centres.append(centre)
		rings.append(_ring(centre, radii[level], 7, rng, 0.11, level * 0.3))
	geo.loft(rings, centres, [0.70, 0.80, 0.86, 0.78, 1.0, 1.08])
	geo.fan(rings[-1], Vector3(0, 1.02, 0), centres[-1], 1.08, 1.12)
	return geo.mesh()

## Conifer: five jagged skirts on a short trunk. One unit tall. Second tint = trunk.
## The skirts are shallow so their upper faces catch the key light (and the snow).
static func _fir(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7701 + variant * 53
	var geo := Geo.new()
	var trunk_low := _ring(Vector3.ZERO, 0.055, 5)
	var trunk_high := _ring(Vector3(0, 0.30, 0), 0.04, 5)
	geo.loft([trunk_low, trunk_high], [Vector3.ZERO, Vector3(0, 0.30, 0)], [0.7, 0.85], 1.0, [], 0.0)
	var tiers := 5
	var widths: Array[float] = [1.0, 0.86, 1.12]
	for tier in range(tiers):
		var f := float(tier) / float(tiers - 1)
		var base_y := 0.14 + f * 0.62 + rng.randf_range(-0.012, 0.012)
		var radius := lerpf(0.47, 0.13, pow(f, 0.85)) * widths[variant % 3]
		var height := lerpf(0.24, 0.22, f)
		var skirt := PackedVector3Array()
		var sides := 9
		for i in range(sides):
			var angle := TAU * float(i) / sides + tier * 0.7
			var r := radius * (1.0 if i % 2 == 0 else 0.72) * rng.randf_range(0.88, 1.10)
			skirt.append(Vector3(cos(angle) * r, base_y - (0.04 if i % 2 == 0 else 0.0), sin(angle) * r))
		var tip := Vector3(rng.randf_range(-0.012, 0.012), base_y + height, rng.randf_range(-0.012, 0.012))
		var sway_low := pow(base_y, 1.6)
		var sway_high := pow(base_y + height, 1.6)
		geo.fan(skirt, tip, Vector3(0, base_y - 0.3, 0), 1.08, 0.62, 0.0, sway_low, sway_high)
	return geo.mesh()

## Broadleaf tree: short trunk under a full crown of leaf masses. One unit tall, about
## 0.9 wide. Second tint = trunk.
static func _tree(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7901 + variant * 47
	var geo := Geo.new()
	var trunk_top := Vector3(rng.randf_range(-0.04, 0.04), 0.40, rng.randf_range(-0.04, 0.04))
	geo.loft([_ring(Vector3.ZERO, 0.085, 6), _ring(trunk_top * 0.55, 0.06, 6), _ring(trunk_top, 0.045, 6)],
		[Vector3.ZERO, trunk_top * 0.55, trunk_top], [0.66, 0.8, 0.9], 1.0, [], 0.0)
	var crowns := 5 if variant != 2 else 4
	var sizes: Array[float] = [1.0, 1.12, 0.92]
	for i in range(crowns):
		var angle := TAU * float(i) / float(crowns - 1) + rng.randf() * 0.8
		var reach := 0.24 if i > 0 else 0.0
		var centre := Vector3(cos(angle) * reach, 0.70 if i == 0 else 0.56 + rng.randf_range(-0.05, 0.06), sin(angle) * reach)
		var size: Vector3 = Vector3(0.62, 0.52, 0.62) * (1.0 if i == 0 else rng.randf_range(0.66, 0.84)) * sizes[variant % 3]
		_blob(geo, rng, 1 if i == 0 else 0, centre, size, 0.15, 0.45, 1.12, 0.0, 0.04)
	return geo.mesh()

## Bare, broken tree (burnt trunks, drowned snags, thorn stems). One unit tall.
static func _dead(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8101 + variant * 43
	var geo := Geo.new()
	var points: Array[Vector3] = [Vector3.ZERO, Vector3(rng.randf_range(-0.05, 0.05), 0.36, rng.randf_range(-0.05, 0.05)),
		Vector3(rng.randf_range(-0.09, 0.09), 0.70, rng.randf_range(-0.09, 0.09)), Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12))]
	var radii: Array[float] = [0.085, 0.062, 0.042, 0.012]
	var rings: Array = []
	for i in range(4): rings.append(_ring(points[i], radii[i], 5, rng, 0.14, i * 0.5))
	geo.loft(rings, points, [0.70, 0.85, 0.96, 1.05])
	geo.fan(rings[3], points[3] + Vector3(0, 0.02, 0), points[3], 1.05, 1.05)
	for branch in range(3 + variant % 2):
		var from: Vector3 = points[1].lerp(points[2], rng.randf_range(0.0, 1.0))
		var angle := TAU * float(branch) / 3.0 + rng.randf()
		var to := from + Vector3(cos(angle) * 0.27, rng.randf_range(0.14, 0.30), sin(angle) * 0.27)
		var low := _ring(from, 0.034, 4, null, 0.0, angle)
		geo.fan(low, to, from - (to - from) * 0.5, 0.82, 1.0)
	return geo.mesh()

## Mushroom: stem under a domed cap. One unit wide, 0.9 tall. Second tint = stem;
## the gills and the cap's rim are the parts that may glow.
static func _mushroom(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8301 + variant * 41
	var geo := Geo.new()
	var lean := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
	var neck := Vector3(0, 0.56, 0) + lean
	geo.loft([_ring(Vector3.ZERO, 0.13, 8), _ring(neck * 0.5, 0.09, 8), _ring(neck, 0.075, 8)], [Vector3.ZERO, neck * 0.5, neck],
		[0.74, 0.92, 1.0], 1.0, [], 0.0)
	var flat := variant % 2 == 1
	var profile: Array[Vector2] = [Vector2(0.50, 0.50), Vector2(0.47, 0.60), Vector2(0.36, 0.74 if not flat else 0.68), Vector2(0.18, 0.84 if not flat else 0.73)]
	var rings: Array = []
	var centres: Array = []
	for level in profile:
		var centre := Vector3(0, level.y, 0) + lean
		centres.append(centre)
		rings.append(_ring(centre, level.x, 10, rng, 0.05))
	geo.loft(rings, centres, [0.92, 1.0, 1.06, 1.10])
	geo.fan(rings[-1], Vector3(0, profile[-1].y + 0.05, 0) + lean, centres[-1], 1.10, 1.14)
	# Underside: gills fold up into the cap and carry the glow.
	geo.fan(rings[0], neck + Vector3(0, 0.04, 0), neck + Vector3(0, 0.4, 0), 1.0, 0.55, 0.0, 0.0, 0.0, 2.0)
	return geo.mesh()

## Clump of blades (grass, sedge) or reeds with seed heads. One unit tall.
static func _tuft(blades: int, spread: float, heads: bool, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var geo := Geo.new()
	for blade in range(blades):
		var angle := TAU * float(blade) / blades + rng.randf() * 0.6
		var foot := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.02, 0.12)
		var height := rng.randf_range(0.55, 1.0)
		var tip := foot + Vector3(cos(angle) * spread * rng.randf_range(0.4, 1.0), height, sin(angle) * spread * rng.randf_range(0.4, 1.0))
		var width := 0.035 if heads else 0.06
		var base := _ring(foot, width, 3, null, 0.0, angle)
		geo.fan(base, tip, foot + Vector3(0, -0.5, 0), 0.62, 1.08, 0.0, 0.0, height * height, 0.0)
		if heads and blade % 2 == 0:
			var at := foot.lerp(tip, 0.80)
			var low := _ring(at, 0.045, 4, null, 0.0, angle)
			var high := _ring(foot.lerp(tip, 0.97), 0.035, 4, null, 0.0, angle)
			geo.loft([low, high], [at, foot.lerp(tip, 0.97)], [0.9, 1.0], 1.0, [height * 0.7, height], 0.0)
	return geo.mesh()

## Three jointed stalks with leaf sprays. One unit tall. Second tint = leaves.
static func _bamboo() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8501
	var geo := Geo.new()
	for stalk in range(3):
		var foot := Vector3(cos(stalk * 2.1) * 0.10, 0, sin(stalk * 2.1) * 0.10)
		var top := foot + Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(0.82, 1.0), rng.randf_range(-0.07, 0.07))
		var rings: Array = []
		var centres: Array = []
		var shades: Array = []
		var sways: Array = []
		for joint in range(4):
			var f := float(joint) / 3.0
			var centre := foot.lerp(top, f)
			centres.append(centre)
			rings.append(_ring(centre, 0.028 - f * 0.008, 5, null, 0.0, stalk))
			shades.append(0.78 + 0.26 * f)
			sways.append(f * f)
		geo.loft(rings, centres, shades, 0.0, sways, 0.0)
		for leaf in range(4):
			var angle := TAU * float(leaf) / 4.0 + stalk
			var from := foot.lerp(top, rng.randf_range(0.62, 0.98))
			var to := from + Vector3(cos(angle) * 0.20, rng.randf_range(-0.05, 0.12), sin(angle) * 0.20)
			geo.fan(_ring(from, 0.04, 3, null, 0.0, angle), to, from - Vector3(0, 0.3, 0), 0.82, 1.1, 1.0, 0.7, 1.0, 0.0)
	return geo.mesh()

## Irregular flat plate: one unit across, one unit thick (scale the instance thin).
## Ice floes, basalt tiles, stepping stones, broken paving.
static func _slab(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8701 + variant * 37
	var geo := Geo.new()
	var sides: int = [6, 5, 7][variant % 3]
	var low := _ring(Vector3.ZERO, 0.5, sides, rng, 0.2, variant * 0.5)
	var high := PackedVector3Array()
	for p in low: high.append(Vector3(p.x * 0.93, 1.0, p.z * 0.93))
	geo.loft([low, high], [Vector3.ZERO, Vector3(0, 1, 0)], [0.70, 0.94])
	geo.fan(high, Vector3(0, 1, 0), Vector3(0, 0.5, 0), 1.0, 1.05)
	return geo.mesh()

## Flat unit quad on y = 0 (x, z in -0.5..0.5) with UV 0..1: the contact pool. Drawn
## with the pool shader, so shade and sway slots are unused.
static func _contact() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	# Clockwise seen from above (Godot front faces); the material does not cull anyway.
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Round leaf lying on water with a notch, one unit across.
static func _pad() -> ArrayMesh:
	var geo := Geo.new()
	var sides := 11
	for i in range(sides - 1):
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		geo.tri(Vector3.ZERO, Vector3(cos(a0), 0, sin(a0)) * 0.5, Vector3(cos(a1), 0, sin(a1)) * 0.5, Vector3.UP, Vector3(0.86, 1.04, 1.04), 0.0, Vector3.ZERO, 0.0)
	return geo.mesh()

## Cluster of pointed crystals, one unit tall; the upper half may glow.
static func _crystal(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8901 + variant * 31
	var geo := Geo.new()
	var count := 4 + variant
	for i in range(count):
		var angle := TAU * float(i) / count + rng.randf() * 0.7
		var tilt := 0.0 if i == 0 else rng.randf_range(0.22, 0.55)
		var axis := Vector3(sin(tilt) * cos(angle), cos(tilt), sin(tilt) * sin(angle))
		var length := 1.0 if i == 0 else rng.randf_range(0.42, 0.74)
		var radius := 0.13 if i == 0 else rng.randf_range(0.06, 0.10)
		var foot := Vector3(cos(angle), 0, sin(angle)) * (0.0 if i == 0 else 0.12)
		var basis := Basis(Quaternion(Vector3.UP, axis))
		var low := PackedVector3Array()
		var high := PackedVector3Array()
		for side in range(6):
			var a := TAU * float(side) / 6.0
			var rim := Vector3(cos(a) * radius, 0, sin(a) * radius)
			low.append(foot + basis * rim)
			high.append(foot + basis * (rim * 0.86 + Vector3(0, length * 0.74, 0)))
		geo.loft([low, high], [foot, foot + axis * length * 0.74], [0.66, 1.0], 0.0, [], 3.0)
		geo.fan(high, foot + axis * length, foot + axis * length * 0.5, 1.0, 1.2, 0.0, 0.0, 0.0, 3.0)
	return geo.mesh()
