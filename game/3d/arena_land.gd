extends RefCounted

## Generated ground of an arena battlefield: the land (and water) around the rim, the
## road surfaces and their kerbs. Visual only; the road geometry is ArenaGeometry's.
##
## The land is one height function of the map position. It decides the ring of terrain,
## the depth under the liquid, where props stand and how the passes open at the gates,
## so cliffs, shores and entrances always agree with each other.

const UNIT := StellarWorld.UNIT
const RADIUS := ArenaGeometry.RADIUS / UNIT
## Rings of the terrain mesh, as distance outside the rim (denser where cliffs stand).
const RINGS: Array[float] = [-0.06, 0.25, 0.55, 0.9, 1.3, 1.7, 2.15, 2.6, 3.1, 3.7, 4.4, 5.3, 6.4, 7.8, 9.6, 12.0, 15.0, 19.0]
const SEGMENTS := 144
## Height of the road surfaces above the soil disc (top at 0.015). Feeders lie a hair
## under the arms: the arm's own paving then runs unbroken past the mouth and the join
## follows the arm's edge. Arms cross each other near the plaza, each on its own layer.
const FEEDER_HEIGHT := 0.0245
const ARM_HEIGHT := 0.029
const LAYER_STEP := 0.0012
const PLAZA_TOP := 0.046

var spec: Dictionary
var gates: Array[Vector2] = []
var _big := FastNoiseLite.new()
var _small := FastNoiseLite.new()
var _heights := PackedFloat32Array()

func _init(land: Dictionary, seed_value: int) -> void:
	spec = land
	_big.seed = seed_value
	_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_big.frequency = float(land.get("ridge_scale", 0.07))
	_big.fractal_octaves = 2
	_small.seed = seed_value + 77
	_small.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_small.frequency = float(land.get("rough_scale", 0.42))
	_small.fractal_octaves = 2
	for lane in range(ArenaGeometry.route_count()):
		gates.append((ArenaGeometry.route_points(lane)[0] - Balance.ARENA_CENTER).normalized())

## True when `angle` (world XZ, radians) lies within `half_angle` of a gate.
func gate_near(angle: float, half_angle: float) -> bool:
	for gate in gates:
		if absf(wrapf(angle - gate.angle(), -PI, PI)) < half_angle: return true
	return false

## Distance from a world XZ point to the nearest approach corridor's centre line
## (INF when no gate lies on that side).
func corridor(x: float, z: float) -> float:
	var nearest := INF
	for gate in gates:
		var along := x * gate.x + z * gate.y
		if along <= 0.0: continue
		nearest = minf(nearest, absf(x * gate.y - z * gate.x))
	return nearest

## Ground height at a world XZ point outside the field (the field itself is flat).
func height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var d := r - RADIUS
	var base := float(spec.get("base", -0.04))
	if d <= 0.0: return base
	var big := _big.get_noise_2d(x, z)
	var small := _small.get_noise_2d(x, z)
	var rise := float(spec.get("rise", 0.8))
	var start := float(spec.get("start", 0.4))
	var climb := smoothstep(start, start + float(spec.get("width", 2.6)), d)
	var h := rise * (1.0 + float(spec.get("ridge", 0.5)) * big) * climb
	var islands := float(spec.get("islands", 0.0))
	if islands > 0.0:
		h += islands * maxf(0.0, big * 0.6 + small * 0.5 - float(spec.get("island_level", 0.28))) * smoothstep(0.6, 2.0, d)
	var terrace := float(spec.get("terrace", 0.0))
	if terrace > 0.0 and h > 0.0:
		var step := float(spec.get("step", 0.8))
		var t := h / step + small * 0.18
		var tread := floorf(t)
		h = lerpf(h, (tread + smoothstep(0.34, 0.66, t - tread)) * step, terrace)
	h += float(spec.get("rough", 0.12)) * small * minf(1.0, d * 0.8)
	h += float(spec.get("peaks", 0.0)) * smoothstep(5.0, 13.0, d) * (0.65 + 0.35 * big)
	var south := z / maxf(r, 0.001)
	if h > 0.0:
		# The camera stands in the south: land there stays low so it never hides the field.
		h *= lerpf(1.0, float(spec.get("south", 0.3)), smoothstep(-0.2, 0.7, south))
		# East and west walls may stand, but ease in a little later than the far side.
		h *= lerpf(1.0, float(spec.get("flank", 0.8)), smoothstep(0.5, 1.0, absf(x) / maxf(r, 0.001)) * (1.0 - smoothstep(-0.2, 0.3, south)))
	# Where the camera side was levelled it may also drop away (into the water a cliff
	# stands in), so levelled land never lies exactly in a liquid's surface.
	var south_sink := float(spec.get("south_sink", 0.0))
	if south_sink > 0.0: h -= south_sink * smoothstep(-0.2, 0.6, south) * smoothstep(0.2, 1.4, d)
	# A moat: the ground dips just outside the rim before it does anything else, so a
	# field in water has water all round it even under a cliff.
	var moat := float(spec.get("moat", 0.0))
	if moat > 0.0:
		var reach := float(spec.get("moat_width", 1.2))
		h -= moat * smoothstep(0.0, 0.35, d) * (1.0 - smoothstep(reach, reach + 0.9, d + small * 0.3))
	# Far out the land may fall away (open sea beyond a flat, a drop beyond a ledge).
	var sink := float(spec.get("sink", 0.0))
	if sink != 0.0: h -= sink * smoothstep(float(spec.get("sink_start", 6.0)), float(spec.get("sink_start", 6.0)) + 4.0, d + big * 1.5)
	# Every gate opens a level pass through whatever stands (or lies) outside it.
	var lane := corridor(x, z)
	if lane < INF:
		var half := float(spec.get("pass", 1.9))
		var open := 1.0 - smoothstep(half, half * 2.1, lane + small * 0.25)
		open *= 1.0 - smoothstep(float(spec.get("pass_length", 6.5)), float(spec.get("pass_length", 6.5)) + 3.0, d)
		h = lerpf(h, float(spec.get("pass_level", base)) - base, open * float(spec.get("pass_open", 1.0)))
	return base + h if d > 0.3 else lerpf(base, base + h, d / 0.3)

## The terrain ring as one indexed mesh with smooth normals. Keeps the sampled heights
## for liquid().
func terrain() -> ArrayMesh:
	var rings := RINGS.size()
	var count := SEGMENTS * rings
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(count)
	normals.resize(count)
	_heights.resize(count)
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / SEGMENTS
		var cx := cos(angle)
		var sz := sin(angle)
		for j in range(rings):
			var r := RADIUS + RINGS[j]
			var h := height(cx * r, sz * r)
			_heights[i * rings + j] = h
			vertices[i * rings + j] = Vector3(cx * r, h, sz * r)
	for i in range(SEGMENTS):
		var before := posmod(i - 1, SEGMENTS) * rings
		var after := ((i + 1) % SEGMENTS) * rings
		for j in range(rings):
			var around := vertices[after + j] - vertices[before + j]
			var outward := vertices[i * rings + mini(j + 1, rings - 1)] - vertices[i * rings + maxi(j - 1, 0)]
			var normal := around.cross(outward)
			normals[i * rings + j] = normal.normalized() if normal.length_squared() > 1.0e-10 else Vector3.UP
	return _grid_mesh(vertices, normals, PackedVector2Array())

## Flat liquid surface over the same grid; UV2.x carries the depth of the land under it.
func liquid(level: float) -> ArrayMesh:
	var rings := RINGS.size()
	var count := SEGMENTS * rings
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var depth := PackedVector2Array()
	vertices.resize(count)
	normals.resize(count)
	depth.resize(count)
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / SEGMENTS
		for j in range(rings):
			var r := RADIUS + RINGS[j]
			var index := i * rings + j
			vertices[index] = Vector3(cos(angle) * r, level, sin(angle) * r)
			normals[index] = Vector3.UP
			depth[index] = Vector2(level - _heights[index], 0.0)
	return _grid_mesh(vertices, normals, depth)

func _grid_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uv2: PackedVector2Array) -> ArrayMesh:
	var rings := RINGS.size()
	var indices := PackedInt32Array()
	indices.resize(SEGMENTS * (rings - 1) * 6)
	var at := 0
	for i in range(SEGMENTS):
		var a := i * rings
		var b := ((i + 1) % SEGMENTS) * rings
		for j in range(rings - 1):
			# Clockwise seen from above (Godot front faces).
			indices[at] = a + j
			indices[at + 1] = b + j + 1
			indices[at + 2] = b + j
			indices[at + 3] = a + j
			indices[at + 4] = a + j + 1
			indices[at + 5] = b + j + 1
			at += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not uv2.is_empty(): arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# --------------------------------------------------------------------------- #
# Roads
# --------------------------------------------------------------------------- #
static func _world(p: Vector2, y: float) -> Vector3:
	return Vector3((p.x - Balance.ARENA_CENTER.x) / UNIT, y, (p.y - Balance.ARENA_CENTER.y) / UNIT)

## Centre line of one drawable road with its approach outside the rim prepended.
## Returns logical points; index `skip` is the first point that lies on the field.
static func road_line(road: PackedVector2Array, approach: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radial := (road[0] - Balance.ARENA_CENTER).normalized()
	var reach := ArenaGeometry.RADIUS + approach * UNIT
	var steps := maxi(1, ceili((reach - (road[0] - Balance.ARENA_CENTER).length()) / (ArenaGeometry.SAMPLE * 2.0)))
	for i in range(steps):
		points.append(Balance.ARENA_CENTER + radial * lerpf(reach, (road[0] - Balance.ARENA_CENTER).length(), float(i) / steps))
	points.append_array(road)
	return points

static func _tangent(points: PackedVector2Array, i: int) -> Vector2:
	return (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()

## Road surface: a strip along the centre line (UV.x = distance in world units, UV.y
## across), closed by a round cap where an arm runs into the plaza, which is the true
## shape of the walkable road there (ArenaGeometry.on_road measures to the centre line).
static func road_mesh(points: PackedVector2Array, y: float, cap: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := ArenaGeometry.ROAD_WIDTH * 0.5
	var along := 0.0
	var previous_left := Vector3.ZERO
	var previous_right := Vector3.ZERO
	for i in range(points.size()):
		var tangent := _tangent(points, i)
		var normal := Vector2(-tangent.y, tangent.x)
		var left := _world(points[i] + normal * half, y)
		var right := _world(points[i] - normal * half, y)
		if i > 0:
			var length := points[i].distance_to(points[i - 1]) / UNIT
			var corners: Array[Vector3] = [previous_right, previous_left, left, right]
			var coords: Array[Vector2] = [Vector2(along, 0), Vector2(along, 1), Vector2(along + length, 1), Vector2(along + length, 0)]
			for index in [0, 2, 1, 0, 3, 2]:
				surface.set_normal(Vector3.UP)
				surface.set_uv(coords[index])
				surface.add_vertex(corners[index])
			along += length
		previous_left = left
		previous_right = right
	if cap:
		var heading := _tangent(points, points.size() - 1)
		var normal := Vector2(-heading.y, heading.x)
		var centre := points[-1]
		var steps := 10
		for step in range(steps):
			var a0 := -PI * 0.5 + PI * float(step) / steps
			var a1 := -PI * 0.5 + PI * float(step + 1) / steps
			var d0 := heading * cos(a0) + normal * sin(a0)
			var d1 := heading * cos(a1) + normal * sin(a1)
			var triangle: Array[Vector2] = [centre, centre + d0 * half, centre + d1 * half]
			var coords: Array[Vector2] = [Vector2(along, 0.5), Vector2(along + cos(a0) * half / UNIT, 0.5 + sin(a0) * 0.5), Vector2(along + cos(a1) * half / UNIT, 0.5 + sin(a1) * 0.5)]
			for index in range(3):
				surface.set_normal(Vector3.UP)
				surface.set_uv(coords[index])
				surface.add_vertex(_world(triangle[index], y))
	return surface.commit()

## Runs of the road's border that really are a border: stretches of the offset curve
## whose outside is neither another road nor the plaza. Each run is a list of
## [logical point on the border, outward unit normal, distance along in world units].
static func kerb_runs(points: PackedVector2Array, cap: bool) -> Array:
	var half := ArenaGeometry.ROAD_WIDTH * 0.5
	var probe := 7.0
	var runs: Array = []
	for side: float in [1.0, -1.0]:
		var samples: Array = []
		var along := 0.0
		for i in range(points.size()):
			if i > 0: along += points[i].distance_to(points[i - 1]) / UNIT
			var tangent := _tangent(points, i)
			var normal := Vector2(-tangent.y, tangent.x) * side
			samples.append([points[i] + normal * half, normal, along])
		if cap and side > 0.0:
			# Carry the left border around the round end to meet the right one.
			var heading := _tangent(points, points.size() - 1)
			var normal := Vector2(-heading.y, heading.x)
			var steps := 12
			for step in range(1, steps + 1):
				var angle := PI * 0.5 - PI * float(step) / steps
				var out := heading * cos(angle) + normal * sin(angle)
				samples.append([points[-1] + out * half, out, along + float(step) / steps * PI * half / UNIT])
		var run: Array = []
		var was_open := false
		for n in range(samples.size()):
			var sample: Array = samples[n]
			var open := not ArenaGeometry.on_road(Vector2(sample[0]) + Vector2(sample[1]) * probe)
			if n > 0 and open != was_open:
				# Find where the border starts or stops between the two samples.
				var lo: Array = samples[n - 1]
				var hi: Array = sample
				for refine in range(4):
					var mid: Array = [Vector2(lo[0]).lerp(Vector2(hi[0]), 0.5), Vector2(lo[1]).lerp(Vector2(hi[1]), 0.5).normalized(), lerpf(float(lo[2]), float(hi[2]), 0.5)]
					if (not ArenaGeometry.on_road(Vector2(mid[0]) + Vector2(mid[1]) * probe)) == was_open: lo = mid
					else: hi = mid
				run.append(lo if was_open else hi)
				if was_open:
					if run.size() >= 2: runs.append(run)
					run = []
			if open: run.append(sample)
			was_open = open
		if run.size() >= 2: runs.append(run)
	return runs

## Raised kerb along the border runs, as vertex-coloured geometry for the scenery
## material. `width` and `tall` in world units; stones alternate between the two tones.
## The kerb fades into the ground along the approach outside the rim.
static func kerb_mesh(runs: Array, width: float, tall: float, road_y: float, tone_a: Color, tone_b: Color,
		stone: float, fade_length: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Vertex colours are linearised by the renderer: store them as they are.
	var a := tone_a
	var b := tone_b
	for run in runs:
		for n in range(run.size() - 1):
			var s0: Array = run[n]
			var s1: Array = run[n + 1]
			var block := int(floor((float(s0[2]) + float(s1[2])) * 0.5 / stone))
			var color := a.lerp(b, fposmod(block * 0.618, 1.0))
			var rows: Array = []
			for sample in [s0, s1]:
				var out := Vector2(sample[1])
				var edge := Vector2(sample[0])
				var beyond := (edge - Balance.ARENA_CENTER).length() / UNIT - RADIUS
				var top := road_y + tall * (1.0 - smoothstep(0.3, fade_length, beyond))
				rows.append([_world(edge, road_y - 0.03), _world(edge, top), _world(edge - out * width * UNIT, top), _world(edge - out * width * UNIT, road_y),
					Vector3(out.x, 0, out.y)])
			var o: Vector3 = rows[0][4]
			_kerb_quad(surface, rows[0][0], rows[1][0], rows[1][1], rows[0][1], o, color, 0.74, 0.0)
			_kerb_quad(surface, rows[0][1], rows[1][1], rows[1][2], rows[0][2], Vector3.UP, color, 1.0, 0.6)
			_kerb_quad(surface, rows[0][2], rows[1][2], rows[1][3], rows[0][3], -o, color, 0.82, 0.0)
	return surface.commit()

static func _kerb_quad(surface: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, out: Vector3, color: Color, shade: float, cover: float) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (p1 - p0).cross(p2 - p0).dot(out) > 0.0: order = [0, 2, 1, 0, 3, 2]
	var corners: Array[Vector3] = [p0, p1, p2, p3]
	for index in order:
		surface.set_normal(out)
		surface.set_color(color)
		surface.set_uv(Vector2(shade, 0.0))
		surface.set_uv2(Vector2(0.0, cover))
		surface.add_vertex(corners[index])
