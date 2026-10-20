extends RefCounted

## Look and dressing of one arena battlefield. Visual only: nothing here reads or
## changes combat state, and no value here is game data (those live in data/game.db).
##
## A battlefield is its biome (theme.main_body), how harsh it is (theme.rank, 1 calm ..
## 5 hostile) and its own place (theme.id). `look` holds every colour and shader
## parameter the world needs; dress() stands the border, the gates and the surroundings.
## Design record: docs/BATTLEFIELD_BIOMES.md.

const Props := preload("res://game/3d/arena_scenery.gd")
const Land := preload("res://game/3d/arena_land.gd")
const RADIUS := ArenaGeometry.RADIUS / StellarWorld.UNIT
const HALF_ROAD := ArenaGeometry.ROAD_WIDTH / (StellarWorld.UNIT * 2.0)
## Colour of everything that says "they come from here" (HUD gate marks and the stage
## reveal of the effects layer use the same hue).
const GATE_HUE := Color("#ff9a7a")
## Direction on the ground that points away from the fixed arena camera, and the
## camera's right: upright haze quads are laid along `CAMERA_RIGHT` so they face it.
const CAMERA_RIGHT := Vector3(0.9916, 0.0, 0.1293)

var theme: Dictionary
var id := ""
var body := "wood"
var rank := 1
## 0 at rank 1, 1 at rank 5.
var harsh := 0.0
var look: Dictionary = {}
var scn: Props
var land: Land
var rng := RandomNumberGenerator.new()
var haze := SurfaceTool.new()
var haze_quads := 0
## Point lights the dressing asks for: {"at": Vector3, "color": Color, "energy": float, "range": float}.
var lights: Array[Dictionary] = []

func _init(field: Dictionary) -> void:
	theme = field
	# Without a theme (title and camp backdrops before any run) the field is the plain
	# night forest: the wood biome with no place of its own.
	id = String(field.get("id", "wood"))
	body = String(field.get("main_body", "wood"))
	rank = clampi(int(field.get("rank", 1)), 1, 5)
	harsh = float(rank - 1) / 4.0
	rng.seed = absi(id.hash())
	look = _base()
	match body:
		"aqua": _merge(look, _aqua())
		"flame": _merge(look, _flame())
		"rock": _merge(look, _rock())
		"frost": _merge(look, _frost())
		_: _merge(look, _wood())
	if has_method("_theme_" + id): _merge(look, call("_theme_" + id))
	# Review hook (decision 7-3 of the 2026-10-18 overhaul): STELLARDEFENSE_LIGHT_TABLE=frost
	# lights any field with the moonlit frost table, for a side-by-side capture only.
	if OS.get_environment("STELLARDEFENSE_LIGHT_TABLE") == "frost":
		_merge(look, {"ambient": Color("#6c88c8"), "ambient_energy": 0.42, "key": Color("#e8eefc"), "key_energy": 1.0,
			"fill": Color("#6f8fc0"), "fill_energy": 0.26, "rim": Color("#7fb0ff"), "rim_energy": 0.34, "bloom": 0.26})
	_paint(look)
	look["seed"] = Vector2(float(absi(id.hash()) % 97), float(absi((id + "z").hash()) % 89))
	look["floor_l"] = _floor_lightness()
	look["wash"] = smoothstep(57.0, 67.0, float(look["floor_l"]))

# --------------------------------------------------------------------------- #
# The stage
# --------------------------------------------------------------------------- #
## The playfield floor is a stage: battle effects add light to it and the actors on it
## are dark. Its lightness (CIE L* as displayed, mean over the bare floor) is kept
## between 40 and 66 whatever the place is: above that effects wash out to white
## (measured: the starlight sigils vanish on L 85 snow and still read on L 61), below it
## the actors sink into the floor. The brightness of a place lives outside the rim.
##
## FLOOR_L is that lightness as measured on GL captures of every field by
## `python3 tests/arena_visual_review.py --only biome --sets fields --themes all
## --res 1280x800 --out-root build/biomes/all50`. That run writes the table to
## `<out>/1280x800/floor_l_table.txt` and fails when a floor is outside the window or
## differs from this table by more than 5. The table feeds `look["wash"]`, the 0..1
## hint for the effects layer (ArenaWorld.ground_wash, ArenaWorld.floor_lightness).
const FLOOR_L := {
	"calm_lake": 57, "reed_marsh": 51, "aqueduct_ruin": 60, "falls_gorge": 58, "tidal_flats": 58,
	"glacier_lake": 56, "sunken_fleet": 56, "geyser_mud": 62, "deep_trench": 57, "maelstrom_sea": 62,
	"kiln_yard": 47, "burn_field": 56, "forge_canyon": 52, "burnt_forest": 62, "sulfur_springs": 58,
	"ash_city": 55, "lava_river": 50, "obsidian_flats": 49, "volcano_crater": 53, "ash_blizzard": 54,
	"spring_grove": 59, "mushroom_hollow": 47, "bamboo_grove": 55, "vine_ruins": 43, "misty_cedar": 57,
	"thornbrake": 54, "moss_bog": 47, "frost_pines": 60, "rotroot_hollow": 56, "worldtree_roots": 46,
	"gravel_hills": 57, "stone_terraces": 61, "quarry_pit": 61, "red_canyon": 54, "broken_wall": 64,
	"crystal_cavern": 54, "desert_mesa": 63, "iron_mine": 48, "peak_cliffs": 50, "rift_chasm": 65,
	"first_snow_hills": 57, "frozen_pond": 43, "snowed_village": 56, "frost_gorge": 55, "drift_ice_sea": 56,
	"icicle_cave": 58, "blizzard_plateau": 53, "glacier_crevasse": 53, "ice_spire_field": 52, "polar_night": 61,
}

func _floor_lightness() -> float:
	if FLOOR_L.has(id): return float(FLOOR_L[id])
	return 62.0 if body == "frost" else 54.0

## The colour of distant air: fog and haze move a fifth of the way toward it (aerial
## perspective: the far cliffs are lighter than the sky, not darker).
const AIR := Color("#8ea0b4")
## Multiplier on every floor's base colours (see _paint).
const STAGE_GAIN := 1.22

## The painterly pass (2026-10-18, Lantern Stage), applied to every look after its
## theme: the stage is quiet whatever the place is. Fog and haze lighten toward the air,
## the contact pools take the colour of the shade, and the floor, road, land and water
## marks are clamped to a few, large, soft ones so no theme keeps noise at body
## frequency (the families and the showcase themes set these values outright; the
## clamps catch the theme overrides).
func _paint(l: Dictionary) -> void:
	l["fog"] = Color(l["fog"]).lerp(AIR, 0.20)
	l["haze"] = Color(l["haze"]).lerp(AIR, 0.20)
	if not l.has("pool"): l["pool"] = Color(l["haze"]).darkened(0.55)
	var g: Dictionary = l["ground"]
	# The stage gain: the fifty floors were authored under the old rig; under the
	# painterly one (stage fall-off, wider rim band, a darker sky-coloured ambient) the
	# same colours measure about a fifth darker, so their base colours are scaled once
	# here to keep every floor inside the 40..66 window (hue and saturation unchanged).
	for key in ["color_a", "color_b"]:
		if g.has(key): g[key] = Color(g[key]) * STAGE_GAIN
	_clamp(g, "patch", Vector4(-INF, 0.25, -INF, -INF), Vector4(INF, INF, 0.05, 0.08))
	_clamp(g, "lines", Vector4(-INF, -INF, -INF, 0.12), Vector4(0.35, INF, INF, INF))
	_clamp(g, "speck", Vector4(-INF, -INF, -INF, -INF), Vector4(INF, 0.10, 1.3, INF))
	_clamp(g, "pool", Vector4(-INF, 0.10, -INF, -INF), Vector4(0.32, INF, INF, INF))
	_clamp(g, "plate", Vector4(-INF, -INF, -INF, -INF), Vector4(INF, INF, 0.20, INF))
	_clamp(g, "glint", Vector4(-INF, -INF, -INF, -INF), Vector4(0.35, INF, INF, INF))
	_clamp(g, "rim", Vector4(-INF, 2.6, -INF, -INF), Vector4(0.40, INF, INF, INF))
	for key in ["road", "plaza"]:
		var r: Dictionary = l[key]
		_clamp(r, "cell", Vector4(2.0, -INF, -INF, -INF), Vector4(INF, INF, INF, INF))
		_clamp(r, "tone", Vector4(-INF, -INF, -INF, -INF), Vector4(0.12, 0.08, INF, INF))
		_clamp(r, "glow", Vector4(-INF, -INF, -INF, -INF), Vector4(INF, INF, INF, 0.5))
	var t: Dictionary = l["terrain"]
	_clamp(t, "strata", Vector4(-INF, -INF, -INF, -INF), Vector4(INF, INF, 0.20, INF))
	_clamp(t, "patch", Vector4(-INF, -INF, -INF, -INF), Vector4(INF, INF, INF, 0.10))
	var w: Dictionary = l["liquid"]
	if not w.is_empty():
		if w.has("wave"):
			var wave: Vector4 = w["wave"]
			w["wave"] = Vector4(minf(wave.x, 0.14), wave.y * 0.6, minf(wave.z, 0.5), wave.w)
		_clamp(w, "foam", Vector4(-INF, -INF, -INF, -INF), Vector4(0.16, INF, 0.30, INF))
		_clamp(w, "shine", Vector4(-INF, -INF, -INF, -INF), Vector4(0.25, INF, INF, INF))

## Clamps the components of a Vector4 uniform that a look sets (missing keys are left to
## the shader's own defaults, which already are the quiet values).
static func _clamp(d: Dictionary, key: String, lo: Vector4, hi: Vector4) -> void:
	if not d.has(key): return
	var v: Vector4 = d[key]
	d[key] = Vector4(clampf(v.x, lo.x, hi.x), clampf(v.y, lo.y, hi.y), clampf(v.z, lo.z, hi.z), clampf(v.w, lo.w, hi.w))

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
static func _merge(into: Dictionary, from: Dictionary) -> void:
	for key in from:
		if from[key] is Dictionary and into.get(key) is Dictionary and not (from[key] as Dictionary).has("_replace"):
			_merge(into[key], from[key])
		else:
			into[key] = from[key]

func _c(a: String, b: String) -> Color:
	return Color(a).lerp(Color(b), harsh)

func _f(a: float, b: float) -> float:
	return lerpf(a, b, harsh)

func ground(x: float, z: float) -> float:
	return land.height(x, z)

func at_ground(x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, land.height(x, z) + lift, z)

## How far a point is from being hidden behind the field for the camera: 1 in the far
## half, falling to 0 in the south where tall things would cover the playfield.
func tall_room(x: float, z: float) -> float:
	var r := maxf(0.001, sqrt(x * x + z * z))
	return 1.0 - smoothstep(-0.15, 0.62, z / r)

## Visit `count` scattered points in the ring between `near` and `far` outside the rim.
## `visit` receives (position on the ground, angle, distance outside the rim, index).
## Points in a gate's approach corridor are skipped unless `corridors` is true.
func scatter(count: int, near: float, far: float, visit: Callable, corridors: bool = false, arc_from: float = 0.0, arc_to: float = TAU) -> void:
	for n in range(count):
		var angle := rng.randf_range(arc_from, arc_to)
		var d := lerpf(near, far, sqrt(rng.randf()))
		var x := cos(angle) * (RADIUS + d)
		var z := sin(angle) * (RADIUS + d)
		if not corridors and land.corridor(x, z) < HALF_ROAD + 0.9: continue
		visit.call(at_ground(x, z), angle, d, n)

## Vertex colour of a haze quad: the tint scaled in light, stored the way the renderer
## expects vertex colours (it linearises them), with the blend in alpha.
static func _haze_tint(color: Color, strength: float, mix: float) -> Color:
	var tint := (color.srgb_to_linear() * strength).linear_to_srgb()
	tint.a = mix
	return tint

## Camera-facing upright quad for arena_haze.gdshader. `mix` 1 covers, 0 adds light.
func haze_quad(foot: Vector3, width: float, tall: float, color: Color, mix: float, speed: float, pattern: int, strength: float = 1.0) -> void:
	var tint := _haze_tint(color, strength, mix)
	var half := CAMERA_RIGHT * width * 0.5
	var corners: Array[Vector3] = [foot - half, foot + half, foot + half + Vector3(0, tall, 0), foot - half + Vector3(0, tall, 0)]
	var coords: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var phase := fposmod(float(haze_quads) * 0.381966, 0.98)
	for index in [0, 2, 1, 0, 3, 2]:
		haze.set_color(tint)
		haze.set_uv(coords[index])
		haze.set_uv2(Vector2(speed, float(pattern) + phase))
		haze.add_vertex(corners[index])
	haze_quads += 1

## Flat quad lying on the ground (mist banks, glow pools under a gate).
func haze_floor(centre: Vector3, size: Vector2, yaw: float, color: Color, mix: float, speed: float, pattern: int = 4, strength: float = 1.0) -> void:
	var tint := _haze_tint(color, strength, mix)
	var ax := Vector3(cos(yaw), 0, sin(yaw)) * size.x * 0.5
	var az := Vector3(-sin(yaw), 0, cos(yaw)) * size.y * 0.5
	var corners: Array[Vector3] = [centre - ax - az, centre + ax - az, centre + ax + az, centre - ax + az]
	var coords: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var phase := fposmod(float(haze_quads) * 0.381966, 0.98)
	for index in [0, 2, 1, 0, 3, 2]:
		haze.set_color(tint)
		haze.set_uv(coords[index])
		haze.set_uv2(Vector2(speed, float(pattern) + phase))
		haze.add_vertex(corners[index])
	haze_quads += 1

func light(at: Vector3, color: Color, energy: float, reach: float) -> void:
	lights.append({"at": at, "color": color, "energy": energy, "range": reach})

## Angle (world XZ, radians) nearest to `wanted` that keeps `clear` radians away from
## every gate, searched `spread` to either side. Landmarks stand where no road runs.
func clear_angle(wanted: float, clear: float = 0.34, spread: float = 0.9) -> float:
	var best := wanted
	var best_score := -INF
	for step in range(-12, 13):
		var angle := wanted + spread * float(step) / 12.0
		var room := INF
		for gate in land.gates: room = minf(room, absf(wrapf(angle - gate.angle(), -PI, PI)))
		var score := minf(room, clear) * 4.0 - absf(float(step)) / 12.0
		if score > best_score:
			best_score = score
			best = angle
	return best

## Ground point at `degrees` clockwise from north as the camera sees it (0 = the far
## side, 90 = right, -90 = left, 180 = the camera side), `d` units outside the rim,
## moved off any gate.
func spot(degrees: float, d: float, clear: float = 0.34) -> Vector3:
	var angle := clear_angle(deg_to_rad(degrees - 90.0), clear)
	return at_ground(cos(angle) * (RADIUS + d), sin(angle) * (RADIUS + d))

## Yaw that turns a prop's front (+Z) toward the field centre from `at`.
func facing(at: Vector3) -> float:
	return atan2(-at.x, -at.z)

## Per-instance imperfection (2026-10-18): a slight random tilt for a standing prop, and
## on about four in ten a tint darkened a little, so a belt of trees is not a stamp.
func _lean(amount: float = 0.06) -> Vector2:
	return Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))

func _vary(color: Color) -> Color:
	return color.darkened(rng.randf_range(0.0, 0.12)) if rng.randf() < 0.4 else color

## Local frame of a built prop: origin `at`, turned by `yaw`, uniformly scaled.
func frame(at: Vector3, yaw: float, size: float = 1.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3.ONE * size), at)

## One part of a built prop, placed in its frame.
func put(f: Transform3D, kind: String, at: Vector3, dims: Vector3, color: Color, glow: float = 0.0, angles: Vector3 = Vector3.ZERO) -> void:
	scn.add(kind, f * Transform3D(Basis.from_euler(angles) * Basis.from_scale(dims), at), color, color, glow)

func put_link(f: Transform3D, a: Vector3, b: Vector3, radius: float, color: Color, glow: float = 0.0) -> void:
	scn.link(f * a, f * b, radius * f.basis.get_scale().x, color, glow)

# --------------------------------------------------------------------------- #
# Built props (shared by the biomes)
# --------------------------------------------------------------------------- #
## Column of smoke or steam rising from `at`.
func plume(at: Vector3, width: float, tall: float, color: Color, strength: float = 0.5, speed: float = 0.05) -> void:
	haze_quad(at, width, tall, color, 1.0, speed, 1, strength)

## Water (or lava, with `mix` 0) running down a face from `top` over `drop` units.
func fall(top: Vector3, width: float, drop: float, color: Color, mix: float = 1.0, strength: float = 0.8, speed: float = 0.5) -> void:
	haze_quad(top - Vector3(0, drop, 0), width, drop, color, mix, speed, 3, strength)

## Bank of mist lying over `at`.
func mist(at: Vector3, size: Vector2, color: Color, strength: float = 0.35, yaw: float = 0.0) -> void:
	haze_floor(at, size, yaw, color, 1.0, 0.012, 4, strength)

func hut(f: Transform3D, wall: Color, roof: Color, window: float = 0.8, chimney: bool = true) -> void:
	put(f, "box", Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 1.3), wall)
	put(f, "pyramid", Vector3(0, 1.0, 0), Vector3(2.0, 0.9, 1.7), roof)
	put(f, "box", Vector3(0.0, 0.36, 0.66), Vector3(0.36, 0.7, 0.05), wall.darkened(0.5))
	if window > 0.0:
		put(f, "box", Vector3(-0.48, 0.58, 0.66), Vector3(0.30, 0.30, 0.05), Color(look["lamp"]), window)
		put(f, "box", Vector3(0.81, 0.58, 0.1), Vector3(0.05, 0.30, 0.34), Color(look["lamp"]), window)
	if chimney: put(f, "box", Vector3(0.45, 1.45, -0.2), Vector3(0.26, 0.6, 0.26), wall.darkened(0.3))
	scn.contact(f.origin, Vector2(2.3, 2.0) * f.basis.get_scale().x, 0.6, f.basis.get_euler().y)

func boat(f: Transform3D, wood: Color) -> void:
	put(f, "stone", Vector3(0, 0.12, 0), Vector3(0.82, 0.30, 1.9), wood)
	put(f, "pyramid", Vector3(0, -0.03, 0.95), Vector3(0.82, 0.62, 0.30), wood, 0.0, Vector3(PI * 0.5, 0, 0))
	put(f, "pyramid", Vector3(0, 0.27, -0.95), Vector3(0.82, 0.5, 0.30), wood, 0.0, Vector3(-PI * 0.5, 0, 0))
	put(f, "box", Vector3(0, 0.275, 0), Vector3(0.62, 0.02, 1.6), wood.darkened(0.45))
	for z in [-0.5, 0.2]: put(f, "box", Vector3(0, 0.30, z), Vector3(0.78, 0.04, 0.16), wood.lightened(0.12))
	put_link(f, Vector3(0.5, 0.36, 0.5), Vector3(-0.3, 0.3, -0.7), 0.035, wood.lightened(0.2))

## Hull of a wrecked ship lying on its side: keel, ribs, a leaning mast with a torn sail.
func wreck(f: Transform3D, wood: Color, sail: Color, length: float = 5.0) -> void:
	put(f, "box", Vector3(0, 0.2, 0), Vector3(0.36, 0.4, length), wood.darkened(0.2))
	var ribs := int(length / 0.75)
	for n in range(ribs):
		var z := -length * 0.5 + (float(n) + 0.5) * length / ribs
		var width := 1.9 * sin(PI * (float(n) + 0.5) / ribs) + 0.5
		if (n * 7 + int(length * 3.0)) % 5 == 0: continue
		put(f, "arch", Vector3(0, width * 0.75 + 0.05, z), Vector3(width, width * 1.5, 0.16), wood, 0.0, Vector3(PI, 0, 0.0))
	put(f, "box", Vector3(0.0, 0.36, length * 0.22), Vector3(1.5, 0.08, length * 0.36), wood.lightened(0.08))
	put_link(f, Vector3(0, 0.3, -length * 0.1), Vector3(1.3, 3.4, -length * 0.25), 0.11, wood.darkened(0.1))
	put_link(f, Vector3(0.35, 2.3, -length * 0.3), Vector3(1.55, 2.5, 0.35), 0.06, wood)
	put(f, "box", Vector3(0.95, 1.75, 0.0), Vector3(0.04, 1.25, 0.95), sail, 0.0, Vector3(0.0, 0.25, -0.38))
	put_link(f, Vector3(0, 0.45, length * 0.5), Vector3(0, 1.0, length * 0.5 + 1.2), 0.08, wood)

## Round-arched bridge span on two piers (aqueducts, ruined gateways). Its front faces +Z.
func span(f: Transform3D, stone: Color, wide: float = 2.6, tall: float = 2.6, whole: bool = true) -> void:
	for side: float in [-1.0, 1.0]:
		put(f, "stone", Vector3(side * wide * 0.5, tall * 0.33, 0), Vector3(0.7, tall * 0.66, 0.9), stone.darkened(0.04 if side > 0 else 0.0))
	if whole:
		put(f, "arch", Vector3(0, tall * 0.62, 0), Vector3(wide + 0.7, tall * 0.76, 0.9), stone)
		put(f, "box", Vector3(0, tall + 0.12, 0), Vector3(wide + 1.5, 0.3, 1.0), stone.lightened(0.05))
	else:
		put(f, "stone", Vector3(-wide * 0.5, tall * 0.76, 0), Vector3(0.9, 0.5, 0.9), stone.lightened(0.04), 0.0, Vector3(0, 0, 0.22))
		put(f, "stone", Vector3(wide * 0.2, 0.2, 0.8), Vector3(0.9, 0.5, 0.7), stone.darkened(0.08), 0.0, Vector3(0.2, 0.6, 0.1))

## Standing or broken column (ruins).
func pillar(f: Transform3D, stone: Color, tall: float = 2.4, broken: bool = false) -> void:
	put(f, "stone", Vector3(0, 0.12, 0), Vector3(0.7, 0.24, 0.7), stone.darkened(0.06))
	var height := tall * (0.45 if broken else 1.0)
	put(f, "cylinder", Vector3(0, 0.24 + height * 0.5, 0), Vector3(0.44, height, 0.44), stone)
	if broken: put(f, "cylinder", Vector3(0.7, 0.2, 0.5), Vector3(0.44, 0.9, 0.44), stone.darkened(0.05), 0.0, Vector3(0.0, 0.5, PI * 0.5))
	else: put(f, "stone", Vector3(0, 0.36 + height, 0), Vector3(0.74, 0.22, 0.74), stone.lightened(0.05))
	scn.contact(f.origin, Vector2(1.2, 1.2) * f.basis.get_scale().x, 0.55)

## Length of battlemented wall, its long side along X.
func rampart(f: Transform3D, stone: Color, wide: float = 3.2, tall: float = 1.9, ruined: float = 0.0) -> void:
	put(f, "box", Vector3(0, tall * 0.5, 0), Vector3(wide, tall, 0.7), stone)
	var teeth := int(wide / 0.55)
	for n in range(teeth):
		if rng.randf() < ruined: continue
		if n % 2 == 0: put(f, "stone", Vector3(-wide * 0.5 + (float(n) + 0.5) * wide / teeth, tall + 0.16, 0.18), Vector3(wide / teeth - 0.04, 0.34, 0.28), stone.lightened(0.04))
	put(f, "box", Vector3(0, tall - 0.1, -0.2), Vector3(wide, 0.12, 0.5), stone.darkened(0.2))
	scn.contact(f.origin, Vector2(wide + 0.4, 1.3) * f.basis.get_scale().x, 0.55, f.basis.get_euler().y)

func tower(f: Transform3D, stone: Color, roof: Color, tall: float = 3.4) -> void:
	put(f, "cylinder", Vector3(0, tall * 0.5, 0), Vector3(1.9, tall, 1.9), stone)
	put(f, "cylinder", Vector3(0, tall + 0.1, 0), Vector3(2.2, 0.26, 2.2), stone.lightened(0.05))
	for n in range(8):
		var angle := TAU * float(n) / 8.0
		if n % 3 != 2: put(f, "stone", Vector3(cos(angle) * 0.98, tall + 0.4, sin(angle) * 0.98), Vector3(0.44, 0.4, 0.3), stone, 0.0, Vector3(0, -angle + PI * 0.5, 0))
	put(f, "box", Vector3(0, tall * 0.62, 0.94), Vector3(0.22, 0.5, 0.08), roof, 0.6)
	scn.contact(f.origin, Vector2(2.6, 2.6) * f.basis.get_scale().x, 0.6)

## Timber frame of a pit head or scaffold; `dark` fills the opening behind it.
func timber_frame(f: Transform3D, wood: Color, wide: float = 1.9, tall: float = 2.1, opening: bool = true) -> void:
	for side: float in [-1.0, 1.0]:
		put(f, "box", Vector3(side * wide * 0.5, tall * 0.5, 0), Vector3(0.2, tall, 0.2), wood)
		put_link(f, Vector3(side * wide * 0.5, tall * 0.55, 0), Vector3(side * wide * 0.18, tall, 0), 0.07, wood.darkened(0.1))
	put(f, "box", Vector3(0, tall + 0.1, 0), Vector3(wide + 0.5, 0.22, 0.26), wood.lightened(0.06))
	if opening: put(f, "box", Vector3(0, tall * 0.5, -0.35), Vector3(wide - 0.1, tall, 0.5), Color("#0b0a0c"))
	scn.contact(f.origin, Vector2(wide + 0.8, 1.3) * f.basis.get_scale().x, 0.5, f.basis.get_euler().y)

func cart(f: Transform3D, wood: Color, load: Color) -> void:
	put(f, "box", Vector3(0, 0.42, 0), Vector3(0.7, 0.4, 1.0), wood)
	put(f, "box", Vector3(0, 0.62, 0), Vector3(0.6, 0.06, 0.9), load)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]: put(f, "cylinder", Vector3(x * 0.38, 0.17, z * 0.3), Vector3(0.34, 0.06, 0.34), Color("#2a2622"), 0.0, Vector3(0, 0, PI * 0.5))
	put(f, "rock1", Vector3(0, 0.6, 0), Vector3(0.6, 0.45, 0.85), load)
	scn.contact(f.origin, Vector2(1.2, 1.6) * f.basis.get_scale().x, 0.5, f.basis.get_euler().y)

## Stack of squared blocks (quarry stone, crates, firewood bundles).
func stack(f: Transform3D, color: Color, rows: int = 3, block: Vector3 = Vector3(0.7, 0.45, 0.5)) -> void:
	for level in range(rows):
		for n in range(rows - level):
			put(f, "stone", Vector3((float(n) - (rows - level - 1) * 0.5) * block.x * 1.04, block.y * (level + 0.5), 0), block, color.darkened(0.06 * ((n + level) % 3)), 0.0, Vector3(0, rng.randf_range(-0.08, 0.08), 0))
	scn.contact(f.origin, Vector2(rows * block.x * 1.1 + 0.4, block.z + 0.5) * f.basis.get_scale().x, 0.5, f.basis.get_euler().y)

## Brick kiln with a lit fire mouth and a smoking chimney.
func kiln(f: Transform3D, brick: Color, fire: float = 0.9, smoke: float = 0.45) -> void:
	put(f, "cylinder", Vector3(0, 0.14, 0), Vector3(2.0, 0.28, 2.0), brick.darkened(0.3))
	put(f, "dome", Vector3(0, 0.2, 0), Vector3(1.8, 2.4, 1.8), brick)
	put(f, "box", Vector3(0, 0.52, 0.80), Vector3(0.46, 0.56, 0.20), Color("#ff9a3a"), fire)
	put(f, "arch", Vector3(0, 0.22, 0.86), Vector3(0.86, 1.36, 0.22), brick.darkened(0.35))
	put(f, "cylinder", Vector3(0, 1.5, -0.25), Vector3(0.36, 0.9, 0.36), brick.darkened(0.22))
	put(f, "cylinder", Vector3(0, 1.97, -0.25), Vector3(0.44, 0.08, 0.44), Color("#2a2422"))
	if smoke > 0.0: plume(f * Vector3(0, 2.0, -0.25), 1.2 * f.basis.get_scale().x, 3.0 * f.basis.get_scale().x, Color("#8a7c78"), smoke)
	scn.contact(f.origin, Vector2(2.8, 2.8) * f.basis.get_scale().x, 0.6)

func cairn(at: Vector3, stone: Color, levels: int = 4) -> void:
	var y := 0.0
	for level in range(levels):
		var size := 0.8 - level * 0.14
		scn.stand("rock%d" % ((level + 1) % 4), at + Vector3(rng.randf_range(-0.05, 0.05), y - 0.05, rng.randf_range(-0.05, 0.05)), Vector3(size, size * 0.5, size), level * 1.3, stone.darkened(0.05 * (level % 2)))
		y += size * 0.26

func fence(from: Vector3, to: Vector3, wood: Color, posts: int = 5) -> void:
	for n in range(posts):
		var at := from.lerp(to, float(n) / float(maxi(1, posts - 1)))
		at.y = ground(at.x, at.z)
		scn.part("box", at + Vector3(0, 0.35, 0), Vector3(0.09, 0.7, 0.09), wood)
		if n > 0:
			var before := from.lerp(to, float(n - 1) / float(maxi(1, posts - 1)))
			before.y = ground(before.x, before.z)
			scn.link(before + Vector3(0, 0.5, 0), at + Vector3(0, 0.5, 0), 0.03, wood.lightened(0.1))
			scn.link(before + Vector3(0, 0.26, 0), at + Vector3(0, 0.26, 0), 0.03, wood.lightened(0.1))

## A thick root (or tentacle of rock, ice, bone) arching from `from` to `to`.
func arc(from: Vector3, to: Vector3, rise: float, thick: float, thin: float, color: Color, glow: float = 0.0, steps: int = 7) -> void:
	var previous := from
	for n in range(1, steps + 1):
		var t := float(n) / steps
		var point := from.lerp(to, t) + Vector3(0, sin(t * PI) * rise, 0)
		scn.link(previous, point, lerpf(thick, thin, t - 0.5 / steps), color.darkened(0.06 * (n % 2)), glow)
		# A knuckle hides the joint between two segments.
		if n < steps: scn.part("rock0", point - Vector3(0, lerpf(thick, thin, t) * 0.4, 0), Vector3.ONE * lerpf(thick, thin, t) * 1.25, color, glow, Vector3(t * 3.0, t * 5.0, 0.0))
		previous = point

# --------------------------------------------------------------------------- #
# Looks
# --------------------------------------------------------------------------- #
## Everything a field needs, with the neutral values the biomes override.
func _base() -> Dictionary:
	return {
		"sky": Color("#0a1a29"), "fog": Color("#143148"), "fog_density": 0.0070,
		## Depth fog (the lighting reads these keys with defaults): how dense the air is at
		## most beyond the rim, and the view depths where it begins and ends. `fog_density`
		## is the old exponential value and is ignored once the depth fog is in.
		"fog_max": 0.70, "fog_begin": 36.0, "fog_end": 70.0,
		## The toy light budget (2026-10-18, Lantern Stage): a warm key near 1.0 from the
		## camera side, the night sky as a 0.40 ambient, a cool kicker and a faint rim. The
		## time of day of a place lives in its key colour; the night stays in the sky, the
		## border, the fog and the lanterns.
		"ambient": Color("#8cb0d2"), "ambient_energy": 0.40,
		"key": Color("#f0e2c6"), "key_energy": 1.02,
		"fill": Color("#7f9fc8"), "fill_energy": 0.26,
		"rim": Color("#9cc4ff"), "rim_energy": 0.30,
		"bloom": 0.36, "exposure": 1.0,
		"haze": Color("#0c2030"),
		## Self light of land and props: a trace only, so shade stays shade.
		"lift": 0.03,
		## How bright the playfield is for additive effects: 0 dark ground .. 1 snow.
		"wash": 0.0,
		## The stage light of the floor: lit out to 45 % of 12 u, 22 % darker at the rim.
		"ground": {"rough": 0.93, "stage": Vector2(12.0, 0.22)},
		"land": {"base": -0.04, "rise": 0.7, "start": 0.4, "width": 2.6, "ridge": 0.5, "rough": 0.12, "south": 0.3},
		## Aerial haze from 13 u out, 80 % by 30 u; the last value is the land's self light.
		"terrain": {"haze": Vector4(13.0, 30.0, 0.80, 0.03)},
		"liquid": {},
		"road": {},
		"plaza": {},
		## A slab, not a line: 0.12 u tall (3.5 px) with a lit chamfer and a dark groove.
		"kerb": {"a": Color("#60706f"), "b": Color("#506064"), "width": 0.20, "tall": 0.12, "stone": 0.46},
		## Length of the road drawn outside each gate, and what it sinks into out there.
		"approach": 4.6, "fade": Color("#122a2e"), "fade_length": 4.2,
		"cover": Color("#cfdde8"), "cover_amount": 0.0, "wind": 0.5,
		## Lanterns are tight warm pools on the ground (the gate lamp hangs low, see _gate).
		"lamp": Color("#ffc57b"), "lamp_energy": 2.6,
		"crystal_light": Color("#62dfff"),
		## The sanctuary's stone is mid-value: the crystal is the light there, not the steps.
		"altar": {"stone": Color("#3a5066"), "trim": Color("#5a7388"), "rune": Color("#a2ecff")},
		"weather": {"count": 106, "tint": Color("#a9c9c6"), "brightness": 0.42, "opacity": 0.0, "sprite": 0, "size": Vector2(0.161, 0.161),
			"drift": Vector3(0.05, -0.30, 0.02), "sway": 0.35, "twinkle": 0.0, "stretch": 1.0, "height": 4.2},
	}

## Forest clearing under the moon: the game's home look. Calm = a spring grove, hostile
## = the roots of something enormous.
func _wood() -> Dictionary:
	return {
		"sky": _c("#0b1d27", "#081416"), "fog": _c("#16343c", "#102a26"), "fog_density": _f(0.0062, 0.0094), "fog_max": _f(0.66, 0.78),
		## Dusk in the clearing (golden hour): a warm key, the night sky in the ambient and
		## the rim, a cool kicker.
		"ambient": _c("#8cb0d2", "#7ea4c2"), "ambient_energy": _f(0.40, 0.38),
		"key": _c("#f0e2c6", "#e2d8c4"), "key_energy": _f(1.02, 0.98),
		"fill": _c("#7f9fc8", "#78a8a4"), "fill_energy": 0.26,
		"rim": Color("#9cc4ff"), "rim_energy": 0.30,
		"haze": _c("#0f262c", "#0a1e1a"),
		"ground": {"color_a": _c("#2a4634", "#22392f"), "color_b": _c("#4b6238", "#33492f"),
			"patch": Vector4(0.50, 0.30, 0.045, 0.06),
			"line_color": _c("#3b3526", "#2a2a22"), "lines": Vector4(_f(0.28, 0.35), 0.15, 0.63, 0.14),
			"speck_color": _c("#e9e2bd", "#7fe6c2"), "speck": Vector4(_f(0.9, 0.7), _f(0.08, 0.06), 1.2, _f(0.0, 0.5)),
			"rim_color": _c("#1e3a2c", "#162a24"), "rim": Vector4(0.40, 3.5, 0, 0)},
		"land": {"rise": _f(0.5, 1.5), "width": _f(3.2, 2.4), "ridge": _f(0.45, 0.7), "rough": _f(0.10, 0.22), "terrace": _f(0.0, 0.35), "step": 0.7, "peaks": _f(0.5, 1.6)},
		"terrain": {"top_a": _c("#1d3329", "#172822"), "top_b": _c("#2c4329", "#223425"), "side_a": _c("#33291f", "#261f1a"), "side_b": _c("#4a3d2c", "#352b22"),
			"strata": Vector4(1.6, 0.9, 0.14, 0.30), "cover_color": _c("#3a5a34", "#2c4630"), "cover": Vector4(0.35, 0.72, -1.0, 0.3)},
		## The road is a step darker than the lawn (about 10-12 L*) and a neutral warm grey,
		## not a green one: the green swarm keeps its hue contrast and the actors on it are
		## the brightest things; the lit kerb draws its edge.
		"road": {"color_a": _c("#4c4a47", "#403f3d"), "color_b": _c("#5c5955", "#4c4a47"), "joint_color": _c("#232c27", "#1a211e"),
			"edge_color": _c("#3c5a34", "#2e4630"), "edge": Vector4(0.18, 0.55, 0.8, 0.0)},
		"plaza": {"color_a": _c("#504e4b", "#444341"), "color_b": _c("#605d59", "#504e4b"), "joint_color": _c("#232c27", "#1a211e"),
			"edge_color": _c("#3c5a34", "#2e4630"), "edge": Vector4(0.08, 0.35, 0.8, 0.0)},
		"kerb": {"a": _c("#5f6b70", "#4f585e"), "b": _c("#525d63", "#444c52")},
		"fade": _c("#1d3329", "#172822"),
		## Moss caps: lighter than the leaf masses under them.
		"cover": _c("#5a8a48", "#3f6a40"), "cover_amount": _f(0.35, 0.45), "wind": _f(0.5, 0.9),
		"altar": {"stone": Color("#42545f"), "trim": Color("#5f7380")},
		"weather": {"count": int(_f(75, 132)), "tint": _c("#e8f2a0", "#8ef0c8"), "brightness": _f(0.75, 0.9), "sprite": 0, "size": Vector2(0.196, 0.196),
			"drift": Vector3(0.10, 0.06, 0.04), "sway": 0.8, "twinkle": 0.9, "height": 2.6},
		## What grows here: weights of fir / broadleaf / bamboo / dead / giant mushroom.
		## Leaf and needle masses are dark (about 35 % under the old pastel values): the
		## trees are silhouettes framing the lit stage, their caps carry the light.
		"kit": {"fir": _f(0.45, 0.55), "tree": _f(0.55, 0.15), "bamboo": 0.0, "dead": _f(0.0, 0.30), "mush": 0.0,
			"leaf": [_c("#2f5a2c", "#24402c"), _c("#3b5f2a", "#2c472e"), _c("#28492f", "#1f382c")],
			"needle": [_c("#24504a", "#1c3a34"), _c("#2c5a48", "#22443a"), _c("#1f4640", "#183632")],
			"bark": _c("#5f4b3a", "#3a302a"), "stone": _c("#56626a", "#474f56"), "fern": _c("#4d8040", "#355c3e"),
			"cap": _c("#c9584f", "#59c8b0"), "cap_glow": _f(0.0, 0.7), "density": 1.0},
	}

func _theme_spring_grove() -> Dictionary:
	return {"ground": {"color_a": Color("#35543a"), "color_b": Color("#5c7a40"), "speck_color": Color("#f4e6ee"), "speck": Vector4(0.9, 0.08, 1.2, 0.0), "lines": Vector4(0.28, 0.15, 0.63, 0.14)},
		"terrain": {"top_a": Color("#24402e"), "top_b": Color("#3a5a30")},
		## Blossom as dark rose masses with pale caps (the cover), never brighter than the lawn.
		"cover": Color("#f0c8d8"), "cover_amount": 0.42,
		"kit": {"fir": 0.12, "tree": 0.88, "leaf": [Color("#b0658a"), Color("#3f7a34"), Color("#9e5a7e")], "fern": Color("#4f8a3c")},
		"weather": {"tint": Color("#ffd2e2"), "sprite": 0, "size": Vector2(0.161, 0.161), "brightness": 0.6, "opacity": 0.7, "drift": Vector3(0.3, -0.35, 0.1), "sway": 0.6, "twinkle": 0.0, "count": 110, "height": 4.0}}

func _theme_mushroom_hollow() -> Dictionary:
	return {"fog": Color("#1a2a34"), "haze": Color("#12202a"),
		"ground": {"color_a": Color("#454339"), "color_b": Color("#5a573e"), "speck_color": Color("#e2c898"), "speck": Vector4(0.9, 0.2, 2.4, 0.15), "line_color": Color("#28261f")},
		"terrain": {"top_a": Color("#2a2c26"), "top_b": Color("#3a3c2c")},
		"kit": {"fir": 0.2, "tree": 0.2, "mush": 0.6, "cap": Color("#c8503f"), "cap_glow": 0.22, "density": 0.75}}

func _theme_bamboo_grove() -> Dictionary:
	return {"ground": {"color_a": Color("#3a4a30"), "color_b": Color("#5f6a3c"), "speck_color": Color("#c8c070"), "speck": Vector4(0.8, 0.26, 2.2, 0.0)},
		"terrain": {"top_a": Color("#2a3c28"), "top_b": Color("#445030")},
		"kit": {"fir": 0.0, "tree": 0.12, "bamboo": 0.88, "leaf": [Color("#6a9a48"), Color("#86a850"), Color("#5a8a4a")], "density": 1.2}}

func _theme_vine_ruins() -> Dictionary:
	return {"ground": {"color_a": Color("#464d4b"), "color_b": Color("#394e34"), "patch": Vector4(0.55, 0.1, 0.1, 0.2), "joint_color": Color("#2e4a30"), "plate": Vector4(0.115, 0.05, 0.2, 0.85),
			"lines": Vector4(0.0, 0.15, 0.63, 0.06)},
		"cover_amount": 0.6,
		"kit": {"fir": 0.15, "tree": 0.85, "density": 0.8}}

func _theme_misty_cedar() -> Dictionary:
	return {"fog": Color("#1c3a44"), "fog_density": 0.0088, "fog_max": 0.86, "fog_begin": 32.0, "fog_end": 64.0, "ambient": Color("#9cc4cc"), "haze": Color("#16303a"),
		"ground": {"color_a": Color("#3a5a4a"), "color_b": Color("#587a54")},
		"kit": {"fir": 0.92, "tree": 0.08, "stilt": 0.55, "needle": [Color("#2f6460"), Color("#3a7468"), Color("#28565a")], "bark": Color("#5a4034"), "density": 0.9}}

func _theme_thornbrake() -> Dictionary:
	return {"sky": Color("#14120c"), "fog": Color("#3a3420"), "ambient": Color("#b4aa7c"), "key": Color("#f0e6c0"), "haze": Color("#28241a"),
		"ground": {"color_a": Color("#55462f"), "color_b": Color("#6c5a3a"), "joint_color": Color("#2a2014"), "plate": Vector4(0.15, 0.03, 0.18, 0.8),
			"speck": Vector4(0.0, 0.2, 1.7, 0.0), "lines": Vector4(0.0, 0.15, 0.63, 0.06), "rim_color": Color("#3a3020")},
		"terrain": {"top_a": Color("#3f3524"), "top_b": Color("#55462c"), "cover": Vector4(0.0, 0.7, -1.0, 0.3)},
		"road": {"edge_color": Color("#4a3e26")}, "plaza": {"edge_color": Color("#4a3e26")},
		"fade": Color("#3f3524"), "cover": Color("#6a5a38"), "cover_amount": 0.2,
		"kit": {"fir": 0.0, "tree": 0.06, "dead": 0.94, "bark": Color("#3a3026"), "fern": Color("#7a6a3c"), "stone": Color("#5a5448"), "leaf": [Color("#6a6030"), Color("#7a6c34"), Color("#5a5430")]},
		"weather": {"tint": Color("#d8c890"), "brightness": 0.35, "opacity": 0.5, "twinkle": 0.0, "drift": Vector3(0.6, 0.05, 0.2), "count": 110, "sprite": 4, "size": Vector2(0.207, 0.207)}}

func _theme_moss_bog() -> Dictionary:
	return {"fog": Color("#12302a"), "fog_density": 0.0095, "fog_max": 0.88, "fog_begin": 32.0, "fog_end": 64.0, "haze": Color("#0c2420"),
		"ground": {"color_a": Color("#2c4a2c"), "color_b": Color("#4f7038"), "pool_color": Color("#0e2420"), "pool": Vector4(0.3, 0.04, 0.13, 0.1),
			"glint_color": Color("#b8ffd8"), "glint": Vector4(0.3, 260.0, 1.0, 0.5)},
		"land": {"base": -0.08, "rise": -0.5, "start": 0.2, "width": 1.6, "terrace": 0.0, "islands": 2.4, "island_level": 0.08, "peaks": 0.6, "south": 0.8},
		"terrain": {"top_a": Color("#2c4a2c"), "top_b": Color("#4f7038"), "cover_color": Color("#5c8a3c"), "cover": Vector4(0.7, 0.6, -0.05, 0.3)},
		"liquid": {"level": -0.11, "deep_color": Color("#07140f"), "shallow_color": Color("#1c3a26"), "foam_color": Color("#4f7a44"), "crust_color": Color("#3f6a30"),
			"glint_color": Color("#b8ffd8"), "wave": Vector4(0.12, 0.006, 0.2, 0.8), "foam": Vector4(0.1, 0.7, 0.0, 0.2), "crust": Vector4(0.42, 0.21, 0.16, 0.0), "shine": Vector4(0.3, 420.0, 0, 0)},
		"road": {"edge": Vector4(0.3, 0.8, 0.9, 0.0)},
		"cover": Color("#5c8a3c"), "cover_amount": 0.6,
		"kit": {"fir": 0.1, "tree": 0.3, "dead": 0.6, "density": 0.55},
		"weather": {"tint": Color("#b8ffd0"), "brightness": 0.95, "size": Vector2(0.23, 0.23), "count": 88}}

func _theme_frost_pines() -> Dictionary:
	# Still a forest: dark needle-litter ground with hoarfrost on it and snow on the firs.
	return {"sky": Color("#0c1a28"), "fog": Color("#20384c"), "ambient": Color("#a0bcd8"), "key": Color("#dcecff"), "haze": Color("#182c3c"),
		"ground": {"color_a": Color("#2c4640"), "color_b": Color("#47625a"), "line_color": Color("#9db4c0"), "lines": Vector4(0.42, 0.2, 0.68, 0.05),
			"speck_color": Color("#c4d4e0"), "speck": Vector4(0.85, 0.2, 2.2, 0.0), "rim_color": Color("#7890a0"), "rim": Vector4(0.6, 1.2, 0, 0),
			"glint_color": Color("#ffffff"), "glint": Vector4(0.3, 300.0, 0.0, 0.0)},
		"terrain": {"top_a": Color("#21383a"), "top_b": Color("#345050"), "cover_color": Color("#8098ac"), "cover": Vector4(0.5, 0.74, -1.0, 0.5)},
		"road": {"edge_color": Color("#a8bccc"), "edge": Vector4(0.2, 0.75, 0.9, 0.0)}, "plaza": {"edge_color": Color("#a8bccc")},
		"kerb": {"a": Color("#8c9cac"), "b": Color("#7a8a9a")}, "fade": Color("#2c4444"),
		"cover": Color("#c6d4e0"), "cover_amount": 0.8,
		"kit": {"fir": 1.0, "tree": 0.0, "dead": 0.1, "needle": [Color("#2f5a56"), Color("#386660"), Color("#284e50")], "stone": Color("#6a7884"), "fern": Color("#5a7868"), "density": 1.25},
		"weather": {"tint": Color("#ffffff"), "brightness": 0.75, "opacity": 0.8, "twinkle": 0.0, "drift": Vector3(0.3, -0.8, 0.1), "sway": 0.4, "count": 154, "height": 5.0, "size": Vector2(0.138, 0.138)}}

func _theme_rotroot_hollow() -> Dictionary:
	return {"sky": Color("#080c08"), "fog": Color("#1a2414"), "fog_density": 0.0105, "fog_max": 0.90, "fog_begin": 32.0, "fog_end": 64.0,
		"ambient": Color("#8aa878"), "ambient_energy": 0.36, "key": Color("#c8dcb8"), "haze": Color("#101810"),
		"fill": Color("#8aff9a"), "fill_energy": 0.2,
		"ground": {"color_a": Color("#5d5e48"), "color_b": Color("#7d8253"), "line_color": Color("#1c1a12"), "lines": Vector4(0.85, 0.19, 0.58, 0.05),
			"speck_color": Color("#8affb0"), "speck": Vector4(0.9, 0.1, 2.2, 0.8), "rim_color": Color("#1a1c14")},
		"terrain": {"top_a": Color("#20221a"), "top_b": Color("#30321f")},
		"kit": {"fir": 0.1, "tree": 0.0, "dead": 0.75, "mush": 0.15, "cap": Color("#6adcb0"), "cap_glow": 0.7, "bark": Color("#2e261e"), "density": 0.7},
		"weather": {"tint": Color("#b8ff8a"), "drift": Vector3(0.06, 0.2, 0.03), "brightness": 0.9, "count": 154}}

func _theme_worldtree_roots() -> Dictionary:
	return {"ambient": Color("#8fd0c0"), "ambient_energy": 0.38, "fog": Color("#123430"),
		"ground": {"color_a": Color("#27433a"), "color_b": Color("#3a5a40"), "line_color": Color("#8f8c72"), "lines": Vector4(0.45, 0.13, 0.68, 0.04),
			"speck_color": Color("#7ffcd8"), "speck": Vector4(0.8, 0.07, 2.0, 0.6)},
		"kit": {"fir": 0.5, "tree": 0.3, "dead": 0.2, "density": 0.55},
		"weather": {"tint": Color("#8ffce0"), "brightness": 0.95, "count": 176, "size": Vector2(0.207, 0.207)}}

## Water's edge: boardwalks over shallows. Calm = a still lake, hostile = an open sea
## turning around the field.
func _aqua() -> Dictionary:
	return {
		"sky": _c("#0a2230", "#06131c"), "fog": _c("#17404c", "#0e2630"), "fog_density": _f(0.0058, 0.0100), "fog_max": _f(0.62, 0.76),
		## Late afternoon on the water: a warm key, the teal sky in the ambient, a cool kicker.
		"ambient": _c("#72aac6", "#6a9cbc"), "ambient_energy": 0.40,
		"key": _c("#f6ead4", "#dce4ea"), "key_energy": _f(1.02, 0.98),
		"fill": _c("#88b0c8", "#8aaabf"), "fill_energy": 0.26,
		"rim": _c("#b8d8ff", "#d8e4ff"), "rim_energy": 0.30,
		"haze": _c("#0f3440", "#07181f"),
		"ground": {"color_a": _c("#59685a", "#33444a"), "color_b": _c("#8a8866", "#4c5a58"),
			"patch": Vector4(0.56, 0.30, 0.045, 0.06),
			"line_color": _c("#a5a380", "#6a7a80"), "lines": Vector4(0.30, 0.26, 0.60, 0.14),
			"pool_color": _c("#1b6670", "#103846"), "pool": Vector4(_f(0.30, 0.26), 0.14, 0.10, 0.10),
			"glint_color": _c("#d8f6ff", "#a8d0e6"), "glint": Vector4(_f(0.20, 0.30), 150.0, 1.0, 1.0),
			"rim_color": _c("#3f5a52", "#22383e"), "rim": Vector4(0.40, 3.5, 0, 0), "rough": 0.9},
		"land": {"base": -0.10, "rise": _f(-0.9, -1.4), "start": 0.15, "width": 1.6, "ridge": 0.25, "rough": 0.10,
			"islands": _f(1.3, 1.9), "island_level": _f(0.26, 0.34), "pass_open": 0.0, "south": 0.6},
		"terrain": {"top_a": _c("#46503f", "#2e383a"), "top_b": _c("#5e6448", "#3e4846"), "side_a": _c("#363d3a", "#232a2e"), "side_b": _c("#4f5852", "#353e42"),
			"cover_color": _c("#557a48", "#3a5244"), "cover": Vector4(0.5, 0.6, 0.05, 0.3), "strata": Vector4(2.4, 0.8, 0.14, 0.3)},
		## Calm water: slow, low ripples, a hint of glitter, little shore foam.
		"liquid": {"level": -0.09, "deep_color": _c("#0a3040", "#04141e"), "shallow_color": _c("#1c6a72", "#12404e"), "foam_color": _c("#bfe2e2", "#a8bcc6"),
			"glint_color": _c("#dff8ff", "#b8d8ea"), "wave": Vector4(_f(0.10, 0.14), _f(0.007, 0.027), _f(0.20, 0.6), 1.5),
			"foam": Vector4(_f(0.05, 0.10), 0.7, _f(0.0, 0.3), 0.22), "shine": Vector4(_f(0.20, 0.35), _f(420.0, 220.0), 0, 0)},
		## The boardwalk: three long boards across, so a hero never stands on a tiling.
		"road": {"color_a": _c("#584632", "#48392d"), "color_b": _c("#6a553a", "#54483a"), "joint_color": _c("#2b1f15", "#1c1814"),
			"cell": Vector4(2.2, 3.0, 0.5, 0.028), "tone": Vector4(0.12, 0.08, 0.25, 2.6),
			"edge_color": _c("#55422d", "#3c3733"), "edge": Vector4(0.13, 0.75, 0.15, 0.0), "rough": 0.82},
		"plaza": {"color_a": _c("#544735", "#423c31"), "color_b": _c("#635540", "#4e473a"), "joint_color": _c("#2b1f15", "#1c1814"),
			"cell": Vector4(2.0, 3.0, 0.5, 0.03), "tone": Vector4(0.12, 0.08, 2.2, 0.3), "edge_color": _c("#55422d", "#3c3733"), "edge": Vector4(0.08, 0.6, 0.2, 0.0)},
		"kerb": {"a": _c("#5f4830", "#463c30"), "b": _c("#6d5438", "#52463a"), "width": 0.16, "tall": 0.12, "stone": 1.3},
		"approach": 5.6, "fade": _c("#5f4830", "#463c30"), "fade_length": 60.0,
		"cover": _c("#557a48", "#3a5244"), "cover_amount": _f(0.2, 0.08), "wind": _f(0.6, 1.3),
		"altar": {"stone": Color("#3f5e65"), "trim": Color("#6a8a8c")},
		"weather": {"count": int(_f(66, 242)), "tint": _c("#d8f2f4", "#b9d6e6"), "brightness": _f(0.34, 0.5), "sprite": 0 if rank < 4 else 8,
			"size": Vector2(0.161, 0.161) if rank < 4 else Vector2(0.06, 0.62), "drift": Vector3(0.12, 0.04, 0.05) if rank < 4 else Vector3(-1.4, -9.5, 0.6),
			"sway": 0.7 if rank < 4 else 0.0, "twinkle": 0.3 if rank < 4 else 0.0, "stretch": 1.0 if rank < 4 else 2.2, "height": 2.4 if rank < 4 else 7.0},
		## reeds / lily pads / rocks / drowned snags per unit of shore, and what the piles are made of.
		"kit": {"reeds": _f(1.0, 0.3), "pads": _f(1.0, 0.0), "rocks": _f(0.4, 1.0), "snags": _f(0.1, 0.5), "boats": 1 if rank <= 3 else 0,
			"wood": _c("#4b3626", "#3a2e26"), "reed": _c("#8a9a55", "#5f6f50"), "head": _c("#6b4a2e", "#3f3026"), "stone": _c("#5c6866", "#414b50"),
			"pad": Color("#3f7a4a")},
	}

func _theme_calm_lake() -> Dictionary:
	return {"ground": {"color_a": Color("#535846"), "color_b": Color("#746e50"), "pool": Vector4(0.30, 0.14, 0.09, 0.08), "pool_color": Color("#12525a"),
			"speck_color": Color("#b7b29a"), "speck": Vector4(0.5, 0.08, 1.2, 0.0)},
		"kit": {"pads": 1.6, "reeds": 1.0}}

func _theme_reed_marsh() -> Dictionary:
	# Golden reed beds in teal water: the marsh stays a water place, not a green wood.
	return {"fog": Color("#1c3a44"), "fog_density": 0.0085, "ambient": Color("#9cc0c4"), "haze": Color("#12303a"), "key": Color("#ffe6c0"),
		"ground": {"color_a": Color("#374035"), "color_b": Color("#5d5835"), "line_color": Color("#b8a468"), "lines": Vector4(0.5, 0.2, 0.6, 0.07),
			"pool_color": Color("#1f5a62"), "pool": Vector4(0.34, 0.05, 0.13, 0.12), "rim_color": Color("#5a5236")},
		"land": {"rise": -0.55, "islands": 2.3, "island_level": 0.12, "rough": 0.16},
		"terrain": {"top_a": Color("#5a5438"), "top_b": Color("#8a7a44"), "cover_color": Color("#a8924a")},
		"liquid": {"deep_color": Color("#0c3038"), "shallow_color": Color("#236a70"), "foam_color": Color("#9ab8a8"), "shine": Vector4(0.4, 300.0, 0, 0),
			"crust_color": Color("#4a6a44"), "crust": Vector4(0.12, 0.16, 0.14, 0.0)},
		"cover": Color("#a8924a"), "cover_amount": 0.3,
		"kit": {"reeds": 2.8, "pads": 0.5, "snags": 0.6, "rocks": 0.2, "reed": Color("#c8a85a"), "head": Color("#7a5632"), "boats": 0},
		"weather": {"tint": Color("#ffe8b0"), "count": 97}}

func _theme_aqueduct_ruin() -> Dictionary:
	return {"ground": {"color_a": Color("#4e565d"), "color_b": Color("#616b62"), "joint_color": Color("#1b5560"), "plate": Vector4(0.11, 0.06, 0.20, 0.9),
			"pool": Vector4(0.22, 0.04, 0.11, 0.1), "lines": Vector4(0.0, 0.2, 0.6, 0.07), "rim_color": Color("#3f5248")},
		"road": {"color_a": Color("#6f7478"), "color_b": Color("#878c8c"), "joint_color": Color("#1c2a2c"), "cell": Vector4(0.9, 3.0, 0.5, 0.035),
			"tone": Vector4(0.24, 0.14, 0.9, 0.9), "edge_color": Color("#3f6a50"), "edge": Vector4(0.2, 0.6, 0.8, 0.0)},
		"plaza": {"color_a": Color("#767b7e"), "color_b": Color("#8e9392"), "joint_color": Color("#1c2a2c"), "cell": Vector4(0.82, 3.0, 0.5, 0.035), "tone": Vector4(0.22, 0.14, 0.9, 0.9)},
		"kerb": {"a": Color("#7c8488"), "b": Color("#687074"), "tall": 0.12, "stone": 0.5},
		"fade": Color("#5a626a"), "fade_length": 5.0,
		"kit": {"reeds": 0.6, "pads": 0.5, "rocks": 1.2, "wood": Color("#6a7074"), "boats": 0}}

func _theme_falls_gorge() -> Dictionary:
	return {"ground": {"color_a": Color("#3f4a4f"), "color_b": Color("#57635f"), "joint_color": Color("#22343a"), "plate": Vector4(0.085, 0.07, 0.3, 0.75),
			"line_color": Color("#a8c8cc"), "lines": Vector4(0.45, 0.31, 0.68, 0.05), "pool": Vector4(0.30, 0.05, 0.12, 0.1)},
		"land": {"rise": 3.6, "start": 2.2, "width": 1.5, "terrace": 0.7, "step": 1.1, "islands": 0.0, "south": 0.0, "flank": 0.3, "ridge": 0.5, "peaks": 2.0,
			"pass_open": 0.0, "moat": 1.0, "moat_width": 2.6, "south_sink": 1.2},
		"terrain": {"top_a": Color("#3f4f44"), "top_b": Color("#566650"), "side_a": Color("#3a4448"), "side_b": Color("#5a686a"), "strata": Vector4(1.5, 1.3, 0.3, 0.25)},
		"liquid": {"foam": Vector4(0.4, 0.8, 0.75, 0.3), "wave": Vector4(0.2, 0.06, 0.9, 1.2)},
		"kit": {"reeds": 0.3, "pads": 0.0, "rocks": 1.8, "boats": 0}}

func _theme_tidal_flats() -> Dictionary:
	return {"sky": Color("#101c26"), "fog": Color("#2a3d48"), "ambient": Color("#9ab0c0"), "haze": Color("#1a2a34"),
		"ground": {"color_a": Color("#41484d"), "color_b": Color("#5a5e58"), "line_color": Color("#868a80"), "lines": Vector4(0.75, 0.36, 0.56, 0.05),
			"pool_color": Color("#3a6a78"), "pool": Vector4(0.36, 0.035, 0.15, 0.06), "glint": Vector4(0.7, 120.0, 1.0, 0.6)},
		"land": {"rise": 0.10, "start": 0.3, "width": 1.0, "ridge": 0.0, "rough": 0.13, "rough_scale": 0.3, "islands": 0.0, "sink": 1.2, "sink_start": 5.5, "south": 1.0, "flank": 1.0},
		"terrain": {"top_a": Color("#4a5258"), "top_b": Color("#62665e"), "cover": Vector4(0.0, 0.6, 0.05, 0.3), "patch": Vector4(0.5, 0.18, 0.11, 0.2)},
		"liquid": {"deep_color": Color("#12303c"), "shallow_color": Color("#3a6270"), "wave": Vector4(0.2, 0.03, 0.4, 0.5), "foam": Vector4(0.06, 0.8, 0.0, 0.2)},
		"kit": {"reeds": 0.15, "pads": 0.0, "rocks": 0.7, "snags": 0.0, "boats": 2, "stakes": 1}}

func _theme_glacier_lake() -> Dictionary:
	# A lake of meltwater under a glacier: milky turquoise water and wet moraine, with
	# the ice behind it. The field itself is gravel, so it does not read as a snowfield.
	return {"sky": Color("#122c40"), "fog": Color("#2f6078"), "ambient": Color("#a0c8e0"), "ambient_energy": 0.40, "key": Color("#dcf0ff"), "haze": Color("#2a5a74"), "bloom": 0.3,
		"ground": {"color_a": Color("#384248"), "color_b": Color("#4f5a60"), "pool_color": Color("#124e5a"), "pool": Vector4(0.30, 0.05, 0.1, 0.08),
			"line_color": Color("#72828a"), "lines": Vector4(0.4, 0.26, 0.62, 0.06), "speck_color": Color("#c4d6e0"), "speck": Vector4(0.9, 0.12, 1.6, 0.0),
			"glint": Vector4(0.6, 160.0, 1.0, 0.6), "rim_color": Color("#6c7c84")},
		"land": {"rise": 2.8, "start": 3.0, "width": 2.0, "terrace": 0.5, "step": 1.2, "islands": 0.0, "south": 0.0, "flank": 0.3, "peaks": 2.4, "pass_open": 0.0,
			"moat": 1.0, "moat_width": 3.4, "south_sink": 1.2},
		"terrain": {"top_a": Color("#7f94a8"), "top_b": Color("#9fb2c4"), "side_a": Color("#4a7ea4"), "side_b": Color("#86b0cc"), "cover_color": Color("#b8c8d8"), "cover": Vector4(0.9, 0.5, -1.0, 0.3)},
		"liquid": {"deep_color": Color("#126078"), "shallow_color": Color("#3ab4c0"), "crust_color": Color("#d4e6f0"), "crust": Vector4(0.16, 0.07, 0.12, 0.002)},
		"cover": Color("#b8c8d8"), "cover_amount": 0.5,
		"kit": {"reeds": 0.0, "pads": 0.0, "rocks": 1.0, "snags": 0.0, "boats": 0, "stone": Color("#7e96a8"), "ice": 1},
		"weather": {"tint": Color("#ffffff"), "opacity": 0.8, "count": 110, "drift": Vector3(0.2, -0.6, 0.1), "brightness": 0.7}}

func _theme_sunken_fleet() -> Dictionary:
	return {"ground": {"color_a": Color("#4c595e"), "color_b": Color("#666c62"), "speck_color": Color("#7a6040"), "speck": Vector4(0.8, 0.12, 0.9, 0.0),
			"pool": Vector4(0.30, 0.05, 0.12, 0.1)},
		"fog_density": 0.0105, "fog_max": 0.88, "fog_begin": 32.0, "fog_end": 64.0,
		"kit": {"reeds": 0.1, "rocks": 0.8, "snags": 1.0, "boats": 0}}

func _theme_geyser_mud() -> Dictionary:
	return {"sky": Color("#16191e"), "fog": Color("#3a3f44"), "ambient": Color("#b0b4b8"), "haze": Color("#24282c"),
		"ground": {"color_a": Color("#55524c"), "color_b": Color("#6c675c"), "joint_color": Color("#a8a08c"), "plate": Vector4(0.075, 0.05, 0.25, 0.7),
			"pool_color": Color("#4a8a8c"), "pool": Vector4(0.26, 0.03, 0.15, 0.12), "lines": Vector4(0.0, 0.2, 0.6, 0.07)},
		"land": {"rise": 0.08, "start": 0.3, "width": 1.0, "ridge": 0.0, "rough": 0.16, "rough_scale": 0.26, "islands": 0.0, "south": 1.0, "flank": 1.0},
		"terrain": {"top_a": Color("#55524c"), "top_b": Color("#6c675c"), "cover": Vector4(0.0, 0.6, 0.05, 0.3)},
		"liquid": {"deep_color": Color("#2a5458"), "shallow_color": Color("#5a8a86"), "foam_color": Color("#b8c4ba"), "wave": Vector4(0.2, 0.05, 0.4, 0.4), "foam": Vector4(0.05, 0.8, 0.0, 0.2)},
		"kit": {"reeds": 0.0, "pads": 0.0, "rocks": 0.9, "snags": 0.2, "boats": 0, "stone": Color("#6a665e")},
		"weather": {"sprite": 4, "size": Vector2(0.48, 0.48), "tint": Color("#d8dcd8"), "opacity": 0.35, "brightness": 0.3, "drift": Vector3(0.15, 0.5, 0.05), "sway": 0.5,
			"stretch": 1.0, "twinkle": 0.0, "count": 132, "height": 3.5}}

func _theme_deep_trench() -> Dictionary:
	return {"sky": Color("#02070e"), "fog": Color("#06141e"), "fog_density": 0.011, "fog_max": 0.90, "fog_begin": 32.0, "fog_end": 64.0,
		"ambient": Color("#5a86b0"), "ambient_energy": 0.36, "key": Color("#9fc4e6"), "key_energy": 0.82,
		"haze": Color("#020810"),
		"ground": {"color_a": Color("#506475"), "color_b": Color("#6b8298"), "joint_color": Color("#0e161c"), "plate": Vector4(0.12, 0.05, 0.3, 0.8),
			"pool": Vector4(0.0, 0.05, 0.1, 0.1), "lines": Vector4(0.0, 0.2, 0.6, 0.07), "speck_color": Color("#5ff0e0"), "speck": Vector4(1.0, 0.13, 2.2, 1.1)},
		"land": {"rise": -3.0, "start": 0.2, "width": 1.2, "islands": 2.6, "island_level": 0.34},
		"terrain": {"top_a": Color("#1c242a"), "top_b": Color("#28323a"), "side_a": Color("#141a20"), "side_b": Color("#232c34"), "cover": Vector4(0.0, 0.6, 0.05, 0.3),
			"glow_color": Color("#3fe0d0"), "glow": Vector4(0.5, 0.2, 0.05, 0.3)},
		"liquid": {"deep_color": Color("#01060c"), "shallow_color": Color("#0c2a38"), "foam_color": Color("#2f6a70"), "glint_color": Color("#5ff0e0"),
			"shine": Vector4(0.5, 520.0, 0, 0), "wave": Vector4(0.1, 0.01, 0.4, 2.4), "foam": Vector4(0.08, 0.7, 0.0, 0.2)},
		"kit": {"reeds": 0.0, "pads": 0.0, "rocks": 1.2, "snags": 0.0, "boats": 0, "stone": Color("#2a343c")},
		"weather": {"sprite": 0, "size": Vector2(0.138, 0.138), "tint": Color("#bfe8f0"), "brightness": 0.5, "drift": Vector3(0.05, -0.22, 0.03), "sway": 0.6, "stretch": 1.0,
			"twinkle": 0.4, "count": 198, "height": 5.0}}

func _theme_maelstrom_sea() -> Dictionary:
	return {"ground": {"color_a": Color("#505e66"), "color_b": Color("#687476"), "joint_color": Color("#1a2228"), "plate": Vector4(0.1, 0.055, 0.3, 0.7),
			"pool": Vector4(0.3, 0.04, 0.13, 0.08), "lines": Vector4(0.0, 0.2, 0.6, 0.07)},
		"land": {"rise": -1.8, "islands": 2.4, "island_level": 0.36},
		"liquid": {"deep_color": Color("#06202c"), "shallow_color": Color("#1a4c58"), "swirl": Vector4(6.0, 1.25, 0.06, 0.95), "foam": Vector4(0.3, 0.8, 0.0, 0.25),
			"wave": Vector4(0.22, 0.07, 1.0, 1.4)},
		"kit": {"reeds": 0.0, "rocks": 1.6, "snags": 0.3}}

## Burnt ground over fire: basalt and embers. Calm = a kiln yard at dusk, hostile = the
## inside of a crater.
func _flame() -> Dictionary:
	return {
		"sky": _c("#16100f", "#120605"), "fog": _c("#2a1a17", "#34100a"), "fog_density": _f(0.0066, 0.0105), "fog_max": _f(0.72, 0.80),
		## Night over fire: the air is kept cool (a violet-grey ambient, a blue rim) and the
		## lava bounce is the fill, so everything that burns stands out against the rock.
		"ambient": _c("#847494", "#80708a"), "ambient_energy": 0.38,
		"key": _c("#ffdcb8", "#ffd6b0"), "key_energy": 1.0,
		"fill": _c("#ff9a66", "#ff8a50"), "fill_energy": _f(0.22, 0.26),
		"rim": Color("#9ab4ff"), "rim_energy": 0.34,
		"bloom": 0.40,
		"haze": _c("#1a1210", "#1c0806"),
		## The floor the actors stand on is the lit stage (ash-grey basalt), the land around
		## it stays dark and the fire supplies the colour.
		"ground": {"color_a": _c("#555254", "#524e58"), "color_b": _c("#716c69", "#6c6672"),
			"patch": Vector4(0.52, 0.30, 0.045, 0.06),
			"joint_color": _c("#1c1616", "#0c0808"), "plate": Vector4(_f(0.16, 0.13), _f(0.05, 0.075), _f(0.12, 0.18), _f(0.5, 0.75)),
			"glow_color": Color("#ff6a1c"), "glow": Vector4(_f(0.0, 0.7), _f(0.0, 1.0), _f(0.18, 0.26), 0.18),
			"pool_color": Color("#3a0e05"), "pool": Vector4(0.0 if rank < 4 else _f(0.0, 0.16), 0.12, 0.11, 0.5),
			"speck_color": _c("#8f8076", "#ff9a4a"), "speck": Vector4(0.7, _f(0.08, 0.06), 1.2, _f(0.0, 0.9)),
			"rim_color": _c("#2a2020", "#140c0c"), "rim": Vector4(0.40, 3.5, 0, 0), "rough": 0.88},
		"land": {"base": -0.05, "rise": _f(0.6, 3.2), "start": _f(0.5, 1.6), "width": _f(2.8, 1.8), "ridge": _f(0.5, 0.75), "rough": _f(0.14, 0.34),
			"terrace": _f(0.0, 0.6), "step": 0.95, "peaks": _f(0.5, 3.0), "south": _f(0.3, 0.16)},
		"terrain": {"top_a": _c("#2c2827", "#231c1e"), "top_b": _c("#403a38", "#342a2c"), "side_a": _c("#262122", "#1c1618"), "side_b": _c("#3d3433", "#30262a"),
			"strata": Vector4(1.5, 1.2, 0.16, 0.26), "cover_color": _c("#58504e", "#4a4246"), "cover": Vector4(_f(0.3, 0.5), 0.66, -1.0, 0.3),
			"glow_color": Color("#ff5a16"), "glow": Vector4(_f(0.0, 1.6), 0.15, 0.06, 0.2)},
		## Fire monsters are yellow to red: their road is cool blue-black basalt, kept free
		## of ember seams so nothing on it glows but them.
		"road": {"color_a": _c("#56606e", "#4d5564"), "color_b": _c("#687280", "#5e6676"), "joint_color": _c("#1a1c22", "#101014"),
			"cell": Vector4(2.2, 2.0, 0.5, 0.04), "tone": Vector4(0.10, 0.08, 0.7, 0.7),
			"glow_color": Color("#ff6a1c"), "glow": Vector4(0.0, 0.0, 0.0, 0.5),
			"edge_color": _c("#2a2222", "#161012"), "edge": Vector4(0.16, 0.6, 0.6, 0.0), "rough": 0.84},
		"plaza": {"color_a": _c("#5e6876", "#545c6c"), "color_b": _c("#707a88", "#666e7e"), "joint_color": _c("#1a1c22", "#101014"),
			"glow_color": Color("#ff6a1c"), "glow": Vector4(_f(0.0, 0.5), _f(0.0, 0.2), 0.0, 0.5), "edge_color": _c("#2a2222", "#161012"), "edge": Vector4(0.08, 0.5, 0.5, 0.0)},
		"kerb": {"a": _c("#3a3334", "#262226"), "b": _c("#463d3c", "#2f2a2e")},
		"fade": _c("#2c2827", "#231c1e"),
		"cover": _c("#58504e", "#4a4246"), "cover_amount": _f(0.15, 0.4), "wind": 0.3,
		"lamp": Color("#ffa85a"), "lamp_energy": _f(2.4, 2.8),
		"altar": {"stone": Color("#423c40"), "trim": Color("#6a5e5c")},
		"weather": {"count": int(_f(57, 211)), "tint": _c("#ffb066", "#ff8a3a"), "brightness": _f(0.5, 0.8), "sprite": 14, "size": Vector2(0.138, 0.138),
			"drift": Vector3(0.10, _f(0.42, 0.85), 0.04), "sway": 0.45, "twinkle": 0.5, "height": 4.4},
		## basalt columns / charred trunks / boulders / shards per unit of surroundings.
		"kit": {"columns": _f(0.5, 1.0), "trunks": _f(0.6, 0.3), "rocks": 1.0, "shards": _f(0.1, 1.0),
			"basalt": _c("#3a3234", "#262024"), "char": _c("#2a2422", "#161214"), "ember": _f(0.0, 0.5)},
	}

## Lava is a moat of light around a dark stage: more crust than open lava and a glow
## a third under the old one, so the fire frames the field instead of competing with it.
func _lava(coverage: float = 0.70, level: float = -0.26) -> Dictionary:
	return {"_replace": true, "level": level, "deep_color": Color("#3a0c04"), "shallow_color": Color("#7a2206"), "foam_color": Color("#ffb04a"),
		"crust_color": Color("#1c1416"), "glow_color": Color("#d64a10"), "glint_color": Color("#000000"),
		"wave": Vector4(0.10, 0.006, 0.12, 0.6), "foam": Vector4(0.10, 0.8, 0.0, 0.2), "crust": Vector4(coverage, 0.10, 0.13, 0.0012),
		"shine": Vector4(0.0, 100.0, 1.0, 0.16), "haze": Vector4(14.0, 30.0, 0.6, 0.8)}

func _theme_kiln_yard() -> Dictionary:
	return {"ground": {"color_a": Color("#575049"), "color_b": Color("#73675b"), "plate": Vector4(0.16, 0.0, 0.0, 0.0),
			"speck_color": Color("#2a2624"), "speck": Vector4(0.8, 0.18, 1.5, 0.0), "line_color": Color("#3a3430"), "lines": Vector4(0.4, 0.2, 0.62, 0.06)},
		"terrain": {"top_a": Color("#2f2c2e"), "top_b": Color("#453f3c")},
		"kit": {"columns": 0.0, "trunks": 0.3, "rocks": 0.5, "shards": 0.0}}

func _theme_burn_field() -> Dictionary:
	return {"sky": Color("#2a160c"), "fog": Color("#4a2816"), "ambient": Color("#c89a78"), "ambient_energy": 0.38, "haze": Color("#2e190e"),
		"ground": {"color_a": Color("#3a302a"), "color_b": Color("#8a7448"), "patch": Vector4(0.47, 0.06, 0.12, 0.2), "plate": Vector4(0.16, 0.0, 0.0, 0.0),
			"line_color": Color("#6a5836"), "lines": Vector4(0.5, 0.33, 0.56, 0.05), "speck_color": Color("#ff8a2a"), "speck": Vector4(0.9, 0.06, 2.4, 1.0)},
		"land": {"rise": 0.25, "rough": 0.08, "peaks": 0.3},
		"terrain": {"top_a": Color("#2a2320"), "top_b": Color("#4a3a2a"), "patch": Vector4(0.5, 0.2, 0.12, 0.2)},
		"kit": {"columns": 0.0, "trunks": 0.15, "rocks": 0.2, "shards": 0.0, "stubble": 1}}

func _theme_forge_canyon() -> Dictionary:
	return {"ground": {"color_a": Color("#55504e"), "color_b": Color("#6c6460"), "plate": Vector4(0.2, 0.045, 0.2, 0.9), "glow": Vector4(0.25, 0.0, 0.3, 0.2)},
		"land": {"rise": 3.0, "start": 1.0, "width": 1.4, "terrace": 0.75, "step": 1.0, "peaks": 2.0},
		"terrain": {"side_a": Color("#3a2e2c"), "side_b": Color("#5a443c"), "strata": Vector4(1.7, 0.9, 0.4, 0.22)},
		"kit": {"columns": 0.4, "trunks": 0.0, "rocks": 1.0, "shards": 0.0}}

func _theme_burnt_forest() -> Dictionary:
	return {"fog": Color("#2e2624"), "fog_density": 0.0095, "fog_max": 0.86, "fog_begin": 32.0, "fog_end": 64.0, "ambient": Color("#b0a09a"), "haze": Color("#1e1a18"),
		"ground": {"color_a": Color("#625e5a"), "color_b": Color("#7e7872"), "plate": Vector4(0.16, 0.0, 0.0, 0.0),
			"line_color": Color("#2a2524"), "lines": Vector4(0.75, 0.17, 0.62, 0.05), "speck_color": Color("#ff7a2a"), "speck": Vector4(0.8, 0.05, 2.0, 0.9)},
		"terrain": {"top_a": Color("#2e2a28"), "top_b": Color("#4a4440")},
		"cover_amount": 0.45,
		"kit": {"columns": 0.0, "trunks": 2.6, "rocks": 0.4, "shards": 0.0, "ember": 0.25}}

func _theme_sulfur_springs() -> Dictionary:
	# Pale mineral crust stained with sulfur around turquoise hot pools, steam everywhere.
	return {"sky": Color("#1a1a10"), "fog": Color("#4a4624"), "ambient": Color("#c8c4a0"), "ambient_energy": 0.38, "key": Color("#fff2d4"), "haze": Color("#2e2c16"),
		"fill": Color("#e8dc9a"), "rim": Color("#9ad8d0"),
		"ground": {"color_a": Color("#484020"), "color_b": Color("#675d36"), "patch": Vector4(0.5, 0.2, 0.09, 0.16), "joint_color": Color("#5a4c1c"), "plate": Vector4(0.13, 0.04, 0.24, 0.7),
			"glow": Vector4(0.0, 0.0, 0.3, 0.0), "pool_color": Color("#3aa090"), "pool": Vector4(0.30, 0.04, 0.13, 0.12),
			"speck_color": Color("#e2d23a"), "speck": Vector4(0.9, 0.24, 1.3, 0.0),
			"glint_color": Color("#e8fff0"), "glint": Vector4(0.4, 200.0, 1.0, 0.6), "rim_color": Color("#6a5c2a")},
		"land": {"rise": 1.4, "start": 1.6, "width": 2.2, "terrace": 0.95, "step": 0.42, "ridge": 0.6, "rough": 0.06, "peaks": 1.2, "moat": 0.5, "moat_width": 1.5},
		"terrain": {"top_a": Color("#6f6436"), "top_b": Color("#9a8c52"), "side_a": Color("#5f5428"), "side_b": Color("#b0a67c"), "strata": Vector4(4.5, 0.5, 0.3, 0.2),
			"cover": Vector4(0.0, 0.6, -1.0, 0.3), "glow": Vector4(0.0, 0.2, 0.06, 0.0)},
		"liquid": {"_replace": true, "level": -0.2, "deep_color": Color("#1c6a62"), "shallow_color": Color("#5ac0aa"), "foam_color": Color("#f0f0c0"),
			"glint_color": Color("#f0fff4"), "wave": Vector4(0.15, 0.02, 0.3, 0.7), "foam": Vector4(0.16, 0.7, 0.0, 0.2), "shine": Vector4(0.5, 380.0, 0, 0)},
		"road": {"edge_color": Color("#9a8a44")},
		"plaza": {"glow": Vector4(0.0, 0.0, 0.0, 0.85)},
		"kerb": {"a": Color("#b0a05a"), "b": Color("#96884a")},
		"fade": Color("#958848"), "cover": Color("#c8bc74"), "cover_amount": 0.4,
		"kit": {"columns": 0.0, "trunks": 0.2, "rocks": 0.8, "shards": 0.0, "basalt": Color("#8f8250"), "char": Color("#4a4226")},
		"weather": {"sprite": 4, "size": Vector2(0.544, 0.544), "tint": Color("#f0f0d0"), "opacity": 0.3, "brightness": 0.28, "drift": Vector3(0.12, 0.45, 0.04), "count": 123, "twinkle": 0.0, "height": 3.6}}

func _theme_ash_city() -> Dictionary:
	return {"fog": Color("#2c2a2c"), "ambient": Color("#aca6a8"), "haze": Color("#1c1b1d"), "fill": Color("#ff8a52"), "fill_energy": 0.26,
		"ground": {"color_a": Color("#55525a"), "color_b": Color("#706c74"), "plate": Vector4(0.24, 0.035, 0.18, 0.75), "glow": Vector4(0.4, 0.0, 0.25, 0.2)},
		"terrain": {"top_a": Color("#333034"), "top_b": Color("#4c484e")},
		"cover": Color("#68636a"), "cover_amount": 0.7,
		"kit": {"columns": 0.0, "trunks": 0.3, "rocks": 0.8, "shards": 0.0}}

func _theme_lava_river() -> Dictionary:
	return {"land": {"base": -0.08, "rise": -0.7, "start": 0.2, "width": 1.4, "terrace": 0.0, "islands": 2.6, "island_level": 0.18, "peaks": 1.5, "south": 0.8, "pass_open": 0.0},
		"liquid": _lava(0.62),
		"approach": 5.0, "fade_length": 60.0,
		"kit": {"columns": 1.4, "trunks": 0.0, "rocks": 1.0, "shards": 0.6}}

func _theme_obsidian_flats() -> Dictionary:
	return {"sky": Color("#0c0a10"), "fog": Color("#1c1622"), "ambient": Color("#9a8ab8"), "ambient_energy": 0.36, "key": Color("#e8dcff"), "haze": Color("#100c14"),
		"ground": {"color_a": Color("#4c4460"), "color_b": Color("#6a5e7e"), "joint_color": Color("#6a5a7c"), "plate": Vector4(0.085, 0.022, 0.5, 0.8),
			"glow": Vector4(0.35, 0.0, 0.16, 0.2), "pool": Vector4(0.0, 0.03, 0.1, 0.3), "speck": Vector4(0.0, 0.1, 2.0, 0.0),
			"glint_color": Color("#d8c8ff"), "glint": Vector4(0.6, 260.0, 0.0, 0.0), "rough": 0.34},
		"land": {"rise": 0.7, "terrace": 0.6, "step": 0.5, "peaks": 1.2},
		"terrain": {"top_a": Color("#1a161e"), "top_b": Color("#2c2434"), "side_a": Color("#120e16"), "side_b": Color("#2a2232"), "glow": Vector4(0.5, 0.12, 0.05, 0.2), "rough": 0.4},
		"road": {"color_a": Color("#454a5c"), "color_b": Color("#575c70")},
		"plaza": {"color_a": Color("#4c5164"), "color_b": Color("#5e6378")},
		"kit": {"columns": 0.3, "trunks": 0.0, "rocks": 0.6, "shards": 2.4, "basalt": Color("#1c1822")}}

func _theme_volcano_crater() -> Dictionary:
	return {"land": {"rise": 4.4, "start": 2.6, "width": 1.6, "terrace": 0.7, "step": 1.2, "peaks": 3.2, "moat": 0.9, "moat_width": 2.6, "south_sink": 0.9, "pass_open": 0.0},
		"liquid": _lava(0.66),
		"approach": 4.6, "fade_length": 60.0,
		"kit": {"columns": 1.0, "trunks": 0.0, "rocks": 1.2, "shards": 1.0}}

func _theme_ash_blizzard() -> Dictionary:
	return {"sky": Color("#141216"), "fog": Color("#3a363c"), "fog_density": 0.012, "fog_max": 0.90, "fog_begin": 32.0, "fog_end": 64.0,
		"ambient": Color("#a89ca8"), "ambient_energy": 0.38, "key": Color("#e8dcdc"), "haze": Color("#242026"),
		"fill": Color("#ff8a5a"), "fill_energy": 0.3,
		"ground": {"color_a": Color("#55525a"), "color_b": Color("#6f6b74"), "glow": Vector4(0.9, 0.0, 0.34, 0.2), "pool": Vector4(0.0, 0.03, 0.1, 0.3),
			"line_color": Color("#5c575e"), "lines": Vector4(0.5, 0.24, 0.6, 0.07), "speck": Vector4(0.0, 0.1, 2.0, 0.0)},
		"land": {"rise": 1.6, "terrace": 0.2, "peaks": 4.6, "width": 3.0},
		"terrain": {"top_a": Color("#333036"), "top_b": Color("#4b474e"), "cover_color": Color("#5a555c"), "cover": Vector4(0.9, 0.5, -1.0, 0.3), "glow": Vector4(1.6, 0.11, 0.05, 0.25)},
		"road": {"edge_color": Color("#57525a"), "edge": Vector4(0.24, 0.85, 0.9, 0.0)},
		"cover": Color("#5c575e"), "cover_amount": 0.95,
		"kit": {"columns": 0.5, "trunks": 0.8, "rocks": 1.0, "shards": 0.3},
		"weather": {"sprite": 4, "size": Vector2(0.253, 0.253), "tint": Color("#9a949a"), "opacity": 0.9, "brightness": 0.6, "drift": Vector3(1.6, -1.5, 0.5), "sway": 0.4, "count": 330, "twinkle": 0.0, "height": 5.5}}

## Stone country at dusk: warm rock under a low sun. Calm = gravel hills, hostile = the
## ground itself breaking open.
func _rock() -> Dictionary:
	return {
		"sky": _c("#231c26", "#16121a"), "fog": _c("#4a3840", "#33262a"), "fog_density": _f(0.0052, 0.0088), "fog_max": _f(0.62, 0.72),
		## Dusk on stone: a low warm sun, the violet-grey sky in the ambient, a cool rim.
		"ambient": _c("#a09cb4", "#9890ac"), "ambient_energy": 0.40,
		"key": _c("#ffd9a6", "#ffcf98"), "key_energy": 1.0,
		"fill": _c("#8fa8c8", "#9a8ec4"), "fill_energy": 0.26,
		"rim": _c("#9cb8ff", "#9ab8ff"), "rim_energy": 0.30,
		"haze": _c("#3a2c32", "#241a1e"),
		"ground": {"color_a": _c("#8a7458", "#6a5644"), "color_b": _c("#a48a66", "#806850"),
			"patch": Vector4(0.50, 0.30, 0.045, 0.06),
			"joint_color": _c("#4a3a2c", "#2a1e18"), "plate": Vector4(_f(0.20, 0.15), _f(0.028, 0.05), _f(0.12, 0.18), _f(0.5, 0.8)),
			"speck_color": _c("#b8b0a2", "#8a7a6a"), "speck": Vector4(0.8, 0.08, 1.2, 0.0),
			"line_color": _c("#6f5c46", "#4f3e30"), "lines": Vector4(_f(0.28, 0.35), 0.14, 0.62, 0.14),
			"rim_color": _c("#6a5642", "#4a3a2e"), "rim": Vector4(0.40, 3.5, 0, 0)},
		"land": {"rise": _f(1.3, 4.4), "start": _f(0.6, 1.3), "width": _f(2.6, 1.5), "ridge": _f(0.5, 0.7), "rough": _f(0.14, 0.3),
			"terrace": _f(0.45, 0.92), "step": _f(0.8, 1.15), "peaks": _f(0.8, 3.4), "south": _f(0.28, 0.14)},
		"terrain": {"top_a": _c("#8a7458", "#6a5644"), "top_b": _c("#a48a66", "#806850"), "side_a": _c("#8a4e36", "#6a3a2c"), "side_b": _c("#c08a58", "#9a6a48"),
			"strata": Vector4(_f(2.6, 2.0), 1.0, 0.18, 0.22), "cover_color": _c("#b8a27c", "#8a7458"), "cover": Vector4(0.45, 0.72, 0.4, 0.3)},
		## Stone monsters are grey, tan and amber: their road is dark blue slate.
		"road": {"color_a": _c("#4e586c", "#465066"), "color_b": _c("#606a80", "#566078"), "joint_color": _c("#1c2030", "#161924"),
			"cell": Vector4(2.0, 3.0, 0.5, 0.03), "tone": Vector4(0.10, 0.08, 1.1, 1.1),
			"edge_color": _c("#9a8262", "#6f5a46"), "edge": Vector4(0.16, 0.6, 0.85, 0.0)},
		"plaza": {"color_a": _c("#566074", "#4e586e"), "color_b": _c("#687288", "#5e6880"), "joint_color": _c("#1c2030", "#161924"),
			"edge_color": _c("#9a8262", "#6f5a46"), "edge": Vector4(0.08, 0.5, 0.8, 0.0)},
		"kerb": {"a": _c("#b09a76", "#8a7458"), "b": _c("#9c8664", "#78644c"), "stone": 0.52},
		"fade": _c("#8a7458", "#6a5644"),
		"cover": _c("#bca680", "#8e7860"), "cover_amount": _f(0.3, 0.2), "wind": 0.4,
		"altar": {"stone": Color("#5c545a"), "trim": Color("#827870")},
		"weather": {"count": int(_f(66, 198)), "tint": _c("#e8c89a", "#c89a6a"), "brightness": _f(0.30, 0.42), "opacity": 0.55, "sprite": 4, "size": Vector2(0.253, 0.253),
			"drift": Vector3(_f(0.5, 2.4), -0.04, _f(0.15, 0.7)), "sway": 0.5, "height": 2.2},
		## boulders / capped pillars / dry scrub / bare trees per unit of surroundings.
		"kit": {"rocks": 1.0, "hoodoos": _f(0.2, 0.8), "scrub": _f(1.0, 0.3), "trees": _f(0.4, 0.1),
			"stone": _c("#a08a6a", "#7c6a56"), "rust": _c("#9a5a3c", "#703f30"), "dry": _c("#8a8250", "#6a5f44"), "wood": Color("#5a4a3c")},
	}

func _theme_gravel_hills() -> Dictionary:
	return {"key": Color("#ffe6c8"), "fog": Color("#4a4248"), "haze": Color("#35303a"),
		"ground": {"color_a": Color("#4e4940"), "color_b": Color("#60594e"), "plate": Vector4(0.2, 0.0, 0.0, 0.0),
			"speck_color": Color("#b4aca0"), "speck": Vector4(0.85, 0.42, 3.0, 0.0), "lines": Vector4(0.25, 0.14, 0.62, 0.06)},
		"land": {"rise": 1.0, "terrace": 0.0, "ridge": 0.8, "width": 3.4, "peaks": 1.4, "rough": 0.1},
		"terrain": {"top_a": Color("#6f685c"), "top_b": Color("#8a8070"), "side_a": Color("#5e574e"), "side_b": Color("#7c7466"), "strata": Vector4(1.4, 1.2, 0.2, 0.4),
			"cover_color": Color("#7a7c50"), "cover": Vector4(0.35, 0.8, 0.3, 0.4)},
		"kerb": {"a": Color("#9a9284"), "b": Color("#857e72")}, "fade": Color("#6f685c"),
		"kit": {"rocks": 1.6, "hoodoos": 0.0, "scrub": 1.2, "trees": 0.3, "stone": Color("#8a8276"), "rust": Color("#746a5e")}}

func _theme_stone_terraces() -> Dictionary:
	return {"key": Color("#ffe2bc"), "ambient": Color("#a8b0c0"),
		"ground": {"color_a": Color("#5d523c"), "color_b": Color("#645d38"), "patch": Vector4(0.52, 0.12, 0.1, 0.2), "plate": Vector4(0.2, 0.0, 0.0, 0.0),
			"speck_color": Color("#c8c09a"), "speck": Vector4(0.6, 0.14, 2.6, 0.0), "rim_color": Color("#625a3c")},
		"land": {"rise": 1.9, "start": 0.7, "width": 3.6, "terrace": 0.96, "step": 0.42, "ridge": 0.5, "rough": 0.04, "peaks": 1.2},
		"terrain": {"top_a": Color("#75703f"), "top_b": Color("#9a8c4c"), "side_a": Color("#716b5e"), "side_b": Color("#958e7e"), "strata": Vector4(5.5, 0.3, 0.45, 0.2),
			"cover": Vector4(0.0, 0.7, 0.4, 0.3)},
		"fade": Color("#75703f"), "cover": Color("#9a8c4c"), "cover_amount": 0.2,
		"kit": {"rocks": 0.6, "hoodoos": 0.0, "scrub": 1.6, "trees": 0.5, "stone": Color("#8a8476"), "rust": Color("#787264"), "dry": Color("#a0924a")}}

func _theme_quarry_pit() -> Dictionary:
	return {"key": Color("#fff0d8"), "ambient": Color("#b0acc0"), "ambient_energy": 0.40, "haze": Color("#4a4448"), "bloom": 0.22,
		"ground": {"color_a": Color("#514d45"), "color_b": Color("#5f5b53"), "joint_color": Color("#5a544a"), "plate": Vector4(0.085, 0.03, 0.2, 0.75),
			"speck": Vector4(0.0, 0.2, 2.3, 0.0), "lines": Vector4(0.0, 0.14, 0.62, 0.06), "rim_color": Color("#8a8274")},
		"land": {"rise": 3.9, "start": 1.1, "width": 1.6, "terrace": 1.0, "step": 1.0, "ridge": 0.4, "rough": 0.03, "peaks": 1.5},
		"terrain": {"top_a": Color("#8a8476"), "top_b": Color("#a09888"), "side_a": Color("#9a9282"), "side_b": Color("#c4bcaa"), "strata": Vector4(1.0, 0.25, 0.5, 0.2),
			"cover": Vector4(0.0, 0.7, 0.4, 0.3)},
		"kerb": {"a": Color("#d0c8b6"), "b": Color("#b8b09e")}, "fade": Color("#a09888"),
		"kit": {"rocks": 0.5, "hoodoos": 0.0, "scrub": 0.2, "trees": 0.0, "stone": Color("#c2baa8"), "rust": Color("#a8a090")}}

func _theme_red_canyon() -> Dictionary:
	return {"key": Color("#ffc890"), "fog": Color("#5a3028"), "haze": Color("#4a2620"), "ambient": Color("#b890a8"),
		"ground": {"color_a": Color("#6a3926"), "color_b": Color("#824c2e"), "joint_color": Color("#4a2218"), "line_color": Color("#c88252"), "lines": Vector4(0.5, 0.22, 0.6, 0.06),
			"speck_color": Color("#c89a78"), "rim_color": Color("#6a3626")},
		"land": {"rise": 3.6, "start": 0.9, "width": 1.5, "terrace": 0.86, "step": 0.9, "peaks": 2.6},
		"terrain": {"top_a": Color("#8a4c34"), "top_b": Color("#a8633e"), "side_a": Color("#8e3a26"), "side_b": Color("#d48c54"), "strata": Vector4(2.8, 1.1, 0.45, 0.2),
			"cover_color": Color("#c88252")},
		"kerb": {"a": Color("#b87a52"), "b": Color("#9e6442")}, "fade": Color("#8a4c34"),
		"kit": {"rocks": 0.9, "hoodoos": 1.2, "scrub": 0.5, "trees": 0.2, "stone": Color("#a8603e"), "rust": Color("#8a3e2a")}}

func _theme_broken_wall() -> Dictionary:
	return {"key": Color("#ffd8b0"), "ambient": Color("#98a0c8"), "fog": Color("#333848"), "haze": Color("#262a38"),
		"ground": {"color_a": Color("#5b5d60"), "color_b": Color("#707276"), "joint_color": Color("#3f4a30"), "plate": Vector4(0.12, 0.045, 0.2, 0.85),
			"speck": Vector4(0.0, 0.2, 2.3, 0.0), "lines": Vector4(0.0, 0.14, 0.62, 0.06), "rim_color": Color("#5c5a3c")},
		"land": {"rise": 1.1, "start": 0.8, "width": 3.0, "terrace": 0.0, "ridge": 0.5, "peaks": 1.0},
		"terrain": {"top_a": Color("#5c5a3c"), "top_b": Color("#7a7448"), "side_a": Color("#5a5650"), "side_b": Color("#787268"), "cover_color": Color("#7c7648"), "cover": Vector4(0.4, 0.7, 0.2, 0.3)},
		"kerb": {"a": Color("#8a8c90"), "b": Color("#75777b")}, "fade": Color("#5c5a3c"), "cover": Color("#767044"), "cover_amount": 0.3,
		"kit": {"rocks": 0.8, "hoodoos": 0.0, "scrub": 1.0, "trees": 0.5, "stone": Color("#7a7c80"), "rust": Color("#66686c"), "dry": Color("#8a8448")}}

func _theme_crystal_cavern() -> Dictionary:
	# Violet, not blue: the cave must not be taken for an ice field.
	return {"sky": Color("#0e0a18"), "fog": Color("#1e1430"), "fog_density": 0.0095, "fog_max": 0.88, "fog_begin": 32.0, "fog_end": 64.0, "ambient": Color("#8a70c0"), "ambient_energy": 0.36,
		"key": Color("#d4c4ff"), "key_energy": 0.9, "fill": Color("#c078ff"), "fill_energy": 0.32, "rim": Color("#ff8ad8"), "rim_energy": 0.42, "haze": Color("#120c1e"),
		"ground": {"color_a": Color("#5c4f75"), "color_b": Color("#7a6b96"), "joint_color": Color("#1c1626"), "plate": Vector4(0.13, 0.04, 0.26, 0.8),
			"speck_color": Color("#d890ff"), "speck": Vector4(1.0, 0.1, 2.0, 1.0), "lines": Vector4(0.0, 0.14, 0.62, 0.06), "rim_color": Color("#221a30"),
			"glint_color": Color("#e0b0ff"), "glint": Vector4(0.35, 280.0, 0.0, 0.0)},
		"land": {"rise": 4.0, "start": 0.9, "width": 1.6, "terrace": 0.5, "step": 1.2, "peaks": 3.0, "rough": 0.34},
		"terrain": {"top_a": Color("#2c2440"), "top_b": Color("#3e3454"), "side_a": Color("#221a34"), "side_b": Color("#463a60"), "strata": Vector4(1.2, 1.4, 0.3, 0.26),
			"cover": Vector4(0.0, 0.7, 0.4, 0.3), "glow_color": Color("#b46aff"), "glow": Vector4(0.7, 0.13, 0.045, 0.25)},
		"road": {"color_a": Color("#565a6e"), "color_b": Color("#6a6e84"), "edge_color": Color("#30283e")},
		"plaza": {"color_a": Color("#5c6076"), "color_b": Color("#72768c"), "edge_color": Color("#30283e")},
		"kerb": {"a": Color("#4c4460"), "b": Color("#3e3650")}, "fade": Color("#2c2440"), "cover_amount": 0.0, "lamp": Color("#e0a8ff"),
		"kit": {"rocks": 0.8, "hoodoos": 0.0, "scrub": 0.0, "trees": 0.0, "stone": Color("#42385a"), "rust": Color("#342c4a")},
		"weather": {"sprite": 2, "tint": Color("#e0a8ff"), "opacity": 0.0, "brightness": 0.7, "size": Vector2(0.207, 0.207), "drift": Vector3(0.04, 0.08, 0.03), "twinkle": 1.0, "count": 97, "height": 3.0}}

func _theme_desert_mesa() -> Dictionary:
	return {"key": Color("#ffd49a"), "fog": Color("#6a4a34"), "haze": Color("#5a3e2c"), "ambient": Color("#c0a0a8"), "bloom": 0.22,
		"ground": {"color_a": Color("#584426"), "color_b": Color("#674f30"), "joint_color": Color("#dcc08a"), "plate": Vector4(0.12, 0.045, 0.2, 0.7),
			"line_color": Color("#d4b47a"), "lines": Vector4(0.4, 0.2, 0.6, 0.06), "speck": Vector4(0.0, 0.2, 2.3, 0.0), "rim_color": Color("#c8a468")},
		"land": {"rise": 1.3, "start": 0.5, "width": 3.4, "terrace": 0.0, "ridge": 0.9, "rough": 0.08, "peaks": 1.6},
		"terrain": {"top_a": Color("#9a7848"), "top_b": Color("#b48c54"), "side_a": Color("#8a5a38"), "side_b": Color("#c08c58"), "strata": Vector4(2.2, 0.8, 0.3, 0.3),
			"patch": Vector4(0.5, 0.22, 0.045, 0.14), "cover": Vector4(0.0, 0.7, 0.4, 0.3)},
		"kerb": {"a": Color("#d0aa72"), "b": Color("#b8945e")}, "fade": Color("#b48c54"),
		"kit": {"rocks": 0.7, "hoodoos": 2.4, "scrub": 0.4, "trees": 0.15, "stone": Color("#b88a56"), "rust": Color("#a06a40")},
		"weather": {"count": 242, "drift": Vector3(3.4, -0.05, 1.0), "size": Vector2(0.23, 0.23), "brightness": 0.36, "stretch": 3.0}}

func _theme_iron_mine() -> Dictionary:
	return {"sky": Color("#100e0e"), "fog": Color("#1e1816"), "fog_density": 0.009, "fog_max": 0.86, "fog_begin": 32.0, "fog_end": 64.0,
		"ambient": Color("#948478"), "ambient_energy": 0.36, "key": Color("#ffdcb8"), "key_energy": 0.96,
		"fill": Color("#ff9a52"), "fill_energy": 0.3, "haze": Color("#141010"),
		"ground": {"color_a": Color("#55504c"), "color_b": Color("#6c6258"), "joint_color": Color("#1a1614"), "plate": Vector4(0.2, 0.0, 0.0, 0.0),
			"speck_color": Color("#9a5a3a"), "speck": Vector4(0.9, 0.3, 2.8, 0.0), "line_color": Color("#2a2422"), "lines": Vector4(0.5, 0.16, 0.62, 0.06), "rim_color": Color("#2a2422")},
		"land": {"rise": 3.4, "start": 1.0, "width": 1.5, "terrace": 0.8, "step": 1.1, "peaks": 2.4},
		"terrain": {"top_a": Color("#342e2c"), "top_b": Color("#484038"), "side_a": Color("#2e2826"), "side_b": Color("#5a4234"), "strata": Vector4(1.6, 1.2, 0.4, 0.22),
			"cover": Vector4(0.0, 0.7, 0.4, 0.3)},
		"road": {"color_a": Color("#585660"), "color_b": Color("#6a6872"), "joint_color": Color("#1e1c20"), "cell": Vector4(0.5, 5.0, 0.5, 0.02), "tone": Vector4(0.2, 0.2, 1.4, 1.4),
			"edge_color": Color("#2e2826"), "edge": Vector4(0.14, 0.7, 0.8, 0.0), "glow": Vector4(0.0, 0.0, 1.0, 0.5)},
		"plaza": {"color_a": Color("#605e68"), "color_b": Color("#72707a"), "edge_color": Color("#2e2826")},
		"kerb": {"a": Color("#5a4636"), "b": Color("#4a3a2e"), "stone": 1.1}, "fade": Color("#342e2c"), "cover_amount": 0.1,
		"kit": {"rocks": 1.2, "hoodoos": 0.0, "scrub": 0.0, "trees": 0.0, "stone": Color("#4a4240"), "rust": Color("#8a4e34")}}

func _theme_peak_cliffs() -> Dictionary:
	# A summit above the clouds at sunset. The ground is bare rock with snow only in its
	# cracks and hollows, so the field stays a stone place.
	return {"sky": Color("#2a2238"), "fog": Color("#7a5a6a"), "fog_density": 0.006, "ambient": Color("#b0a4cc"), "ambient_energy": 0.40, "key": Color("#ffd8a8"), "key_energy": 1.05,
		"fill": Color("#a8b0f0"), "rim": Color("#ffb890"), "haze": Color("#b08a8c"),
		"ground": {"color_a": Color("#3c3f47"), "color_b": Color("#4f5259"), "joint_color": Color("#dfe6ee"), "plate": Vector4(0.13, 0.05, 0.2, 0.75),
			"speck_color": Color("#e6ecf4"), "speck": Vector4(0.9, 0.08, 1.1, 0.0), "lines": Vector4(0.0, 0.14, 0.62, 0.06), "rim_color": Color("#9aa8b8"), "rim": Vector4(0.35, 2.6, 0, 0),
			"glint_color": Color("#ffffff"), "glint": Vector4(0.3, 260.0, 0.0, 0.0)},
		"land": {"base": -0.05, "rise": -7.0, "start": 0.5, "width": 2.2, "terrace": 0.0, "ridge": 0.2, "rough": 0.3, "islands": 16.0, "island_level": 0.42, "peaks": 0.0,
			"south": 1.0, "flank": 1.0, "pass_open": 0.0},
		"terrain": {"top_a": Color("#56606c"), "top_b": Color("#6e7884"), "side_a": Color("#48525e"), "side_b": Color("#7a8490"), "strata": Vector4(0.9, 1.6, 0.3, 0.3),
			"cover_color": Color("#c8d4e0"), "cover": Vector4(0.9, 0.66, -9.0, 0.3)},
		"liquid": {"_replace": true, "level": -2.3, "deep_color": Color("#8a6f8c"), "shallow_color": Color("#d8a890"), "foam_color": Color("#ffe2c0"), "glint_color": Color("#000000"),
			"wave": Vector4(0.045, 0.004, 0.05, 2.6), "foam": Vector4(1.4, 0.9, 0.8, 0.05), "shine": Vector4(0.0, 100.0, 0, 0), "haze": Vector4(16.0, 32.0, 0.5, 0.95)},
		"kerb": {"a": Color("#8a949e"), "b": Color("#76808a")}, "fade": Color("#5c6672"), "approach": 5.0, "fade_length": 60.0,
		"cover": Color("#c8d4e0"), "cover_amount": 0.7,
		"kit": {"rocks": 0.6, "hoodoos": 0.0, "scrub": 0.0, "trees": 0.0, "stone": Color("#66707c"), "rust": Color("#586270")},
		"weather": {"sprite": 0, "tint": Color("#ffffff"), "opacity": 0.8, "brightness": 0.7, "size": Vector2(0.138, 0.138), "drift": Vector3(4.2, -0.5, 1.2), "stretch": 3.2, "count": 264, "height": 5.0}}

func _theme_rift_chasm() -> Dictionary:
	return {"fog": Color("#3a2c26"), "fog_density": 0.0098, "fog_max": 0.86, "fog_begin": 32.0, "fog_end": 64.0, "haze": Color("#22181a"),
		"ground": {"color_a": Color("#7f6e5c"), "color_b": Color("#9a8670"), "joint_color": Color("#1c1410"), "plate": Vector4(0.10, 0.085, 0.3, 1.0),
			"glow_color": Color("#ff7a2a"), "glow": Vector4(0.7, 0.0, 0.28, 0.2), "speck": Vector4(0.0, 0.2, 2.3, 0.0)},
		"land": {"rise": 3.4, "start": 2.6, "width": 1.4, "terrace": 0.9, "step": 1.3, "rough": 0.5, "rough_scale": 0.3, "peaks": 2.6, "moat": 4.5, "moat_width": 1.9, "pass_open": 0.0},
		"terrain": {"side_a": Color("#3a2c26"), "side_b": Color("#7a5a44"), "glow_color": Color("#ff6a1e"), "glow": Vector4(0.9, 0.16, 0.05, 0.3)},
		"approach": 4.6, "fade_length": 60.0,
		"kit": {"rocks": 1.6, "hoodoos": 0.3, "scrub": 0.1, "trees": 0.2},
		"weather": {"count": 242, "drift": Vector3(2.6, 0.3, 0.8), "brightness": 0.4}}

## Snow and ice: the one bright field. Calm = first snow on the hills, hostile = polar
## night between ice spires.
func _frost() -> Dictionary:
	return {
		"sky": _c("#1c2e44", "#0a1426"), "fog": _c("#3f6088", "#1c3060"), "fog_density": _f(0.0036, 0.0056), "fog_max": _f(0.70, 0.80),
		## Moonlit: the one family that keeps a cool key; the ambient is the night sky.
		"ambient": _c("#7a96cc", "#6c88c8"), "ambient_energy": 0.42,
		"key": _c("#eef2fc", "#e8eefc"), "key_energy": 1.0,
		"fill": _c("#7f9cc8", "#6f8fc0"), "fill_energy": 0.26,
		"rim": _c("#8fc0ff", "#7fb0ff"), "rim_energy": 0.34,
		## Snow is near white, so bloom would spill over every dark thing on it: keep it low.
		"bloom": 0.26,
		"haze": _c("#5a7fa4", "#1c3058"),
		## The stage is blue ice and packed snow in shade (effects add light, so it must not
		## be white); the white of the place is the land and the drifts around it, kept to
		## snow in shadow so the stage stays the lit thing.
		"ground": {"color_a": _c("#364e6a", "#304462"), "color_b": _c("#496584", "#3f567a"),
			"patch": Vector4(0.50, 0.30, 0.045, 0.06),
			"line_color": _c("#6480a2", "#577096"), "lines": Vector4(0.30, 0.17, 0.62, 0.14),
			"pool_color": _c("#294a6e", "#223c64"), "pool": Vector4(_f(0.22, 0.30), 0.12, 0.10, 0.16),
			"joint_color": _c("#d8eaf6", "#b8d4ee"), "plate": Vector4(0.11, 0.0, 0.0, 0.0),
			"glint_color": _c("#ffffff", "#c8e0ff"), "glint": Vector4(_f(0.25, 0.35), 300.0, 0.0, 0.0),
			"rim_color": _c("#8ea4bc", "#6f86a8"), "rim": Vector4(0.35, 3.0, 0, 0), "rough": 0.86},
		"land": {"rise": _f(0.8, 2.6), "start": 0.3, "width": _f(3.4, 2.0), "ridge": _f(0.55, 0.75), "rough": _f(0.10, 0.26),
			"terrace": _f(0.0, 0.55), "step": 1.0, "peaks": _f(0.8, 2.8), "south": _f(0.34, 0.18)},
		"terrain": {"top_a": _c("#5e7890", "#506680"), "top_b": _c("#7a90a8", "#6a809c"), "side_a": _c("#4a6a8e", "#3a567e"), "side_b": _c("#7a9cc0", "#5e80a8"),
			"strata": Vector4(1.3, 1.4, 0.12, 0.34), "cover_color": _c("#a4b6ca", "#8a9eb8"), "cover": Vector4(0.85, 0.5, -1.0, 0.3)},
		## Frost monsters are white to pale blue: their road is the darkest thing on the field.
		"road": {"color_a": _c("#0f1728", "#0d1424"), "color_b": _c("#172036", "#141c30"), "joint_color": _c("#060912", "#05080e"),
			"cell": Vector4(2.0, 3.0, 0.5, 0.032), "tone": Vector4(0.10, 0.08, 1.0, 1.0),
			"edge_color": _c("#cfdbe8", "#b2c6de"), "edge": Vector4(0.10, 0.8, 0.9, 0.0), "rough": 0.7},
		"plaza": {"color_a": _c("#141c30", "#11182a"), "color_b": _c("#1c263e", "#182036"), "joint_color": _c("#060912", "#05080e"),
			"edge_color": _c("#cfdbe8", "#b2c6de"), "edge": Vector4(0.10, 0.8, 0.9, 0.0)},
		"kerb": {"a": _c("#c4d2e2", "#a8bcd6"), "b": _c("#b2c2d4", "#98aecb"), "width": 0.22, "tall": 0.11, "stone": 0.9},
		"fade": _c("#a8bbd0", "#90a6c2"),
		"cover": _c("#c4d2e2", "#a8bcd4"), "cover_amount": _f(0.8, 0.9), "wind": _f(0.4, 1.0),
		"altar": {"stone": Color("#4e6278"), "trim": Color("#7f98ad")},
		"weather": {"count": int(_f(132, 330)), "tint": Color("#ffffff"), "brightness": _f(0.75, 0.9), "opacity": 0.85, "sprite": 0,
			"size": Vector2(0.149, 0.149), "drift": Vector3(_f(0.25, 2.6), _f(-0.85, -2.2), _f(0.1, 0.8)), "sway": _f(0.45, 0.2), "height": 5.5},
		## snowy firs / ice spires / boulders / snow mounds / bare trees per unit of surroundings.
		"kit": {"firs": _f(1.0, 0.2), "spires": _f(0.15, 1.6), "rocks": 0.6, "mounds": 1.0, "bare": _f(0.3, 0.0),
			## Dark firs under their snow: the pine language of the reference.
			"ice": _c("#a6d2ee", "#8fb8e6"), "needle": _c("#24464e", "#1c3640"), "bark": Color("#4a4640"), "stone": _c("#7a8ea2", "#62779a"), "snow": _c("#b4c4d6", "#98acc4")},
	}

func _theme_first_snow_hills() -> Dictionary:
	return {"key": Color("#ffeedd"), "fog": Color("#566a82"), "ambient": Color("#b8c6dc"), "haze": Color("#5a6c84"),
		"ground": {"color_a": Color("#373120"), "color_b": Color("#575d64"), "patch": Vector4(0.5, 0.07, 0.13, 0.16), "lines": Vector4(0.0, 0.2, 0.6, 0.07),
			"pool": Vector4(0.0, 0.03, 0.1, 0.2), "speck_color": Color("#d8e2ec"), "speck": Vector4(0.8, 0.3, 2.6, 0.0), "rim_color": Color("#a8b6c4"), "glint": Vector4(0.25, 300.0, 0.0, 0.0)},
		"land": {"rise": 1.0, "ridge": 0.8, "width": 3.8, "peaks": 1.2},
		"terrain": {"top_a": Color("#7a7050"), "top_b": Color("#948a5c"), "side_a": Color("#5c5444"), "side_b": Color("#7a7260"), "cover": Vector4(0.7, 0.86, -1.0, 0.5),
			"strata": Vector4(1.3, 1.4, 0.2, 0.62)},
		"road": {"edge": Vector4(0.10, 0.7, 0.9, 0.0)},
		"fade": Color("#7a7050"), "cover_amount": 0.55,
		"kit": {"firs": 0.5, "spires": 0.0, "rocks": 0.7, "mounds": 0.4, "bare": 1.4, "needle": Color("#44705e")},
		"weather": {"count": 101, "drift": Vector3(0.2, -0.7, 0.1)}}

func _theme_frozen_pond() -> Dictionary:
	return {"ground": {"color_a": Color("#203342"), "color_b": Color("#30414d"), "joint_color": Color("#d4e6f2"), "plate": Vector4(0.07, 0.014, 0.14, 0.85),
			"lines": Vector4(0.25, 0.5, 0.7, 0.04), "line_color": Color("#c2d8e8"), "pool": Vector4(0.0, 0.03, 0.1, 0.2),
			"speck_color": Color("#e2eef6"), "speck": Vector4(0.85, 0.08, 1.2, 0.0), "rim_color": Color("#9fb2c6"), "rim": Vector4(0.35, 2.6, 0, 0),
			"glint": Vector4(0.7, 220.0, 0.0, 0.0), "rough": 0.3},
		"land": {"rise": 0.9, "start": 0.1, "width": 2.2, "peaks": 1.0},
		"kit": {"firs": 0.6, "spires": 0.0, "bare": 0.8, "reeds": 1},
		"wash": 0.6}

func _theme_snowed_village() -> Dictionary:
	return {"fog": Color("#3f5878"), "ambient": Color("#a8bede"), "key": Color("#dcecff"), "haze": Color("#3f587a"),
		"ground": {"color_a": Color("#2f445b"), "color_b": Color("#3f5671"), "line_color": Color("#516a88"), "lines": Vector4(0.55, 0.12, 0.6, 0.08), "pool": Vector4(0.1, 0.03, 0.1, 0.2)},
		"land": {"rise": 0.7, "width": 4.0, "peaks": 1.0},
		"kit": {"firs": 0.9, "spires": 0.0, "bare": 0.3}}

func _theme_frost_gorge() -> Dictionary:
	return {"ground": {"pool": Vector4(0.36, 0.035, 0.07, 0.14)},
		"land": {"rise": 3.9, "start": 0.9, "width": 1.5, "terrace": 0.85, "step": 1.05, "peaks": 2.6},
		"terrain": {"side_a": Color("#465468"), "side_b": Color("#70849a"), "strata": Vector4(1.7, 1.2, 0.35, 0.26), "cover": Vector4(0.95, 0.56, -1.0, 0.3)},
		"kit": {"firs": 0.5, "spires": 0.5, "rocks": 1.2}}

func _theme_drift_ice_sea() -> Dictionary:
	return {"sky": Color("#0c1c30"), "fog": Color("#2f4f72"), "haze": Color("#16304e"),
		"ground": {"pool_color": Color("#2f6a94"), "pool": Vector4(0.3, 0.03, 0.09, 0.12), "joint_color": Color("#3a6f98"), "plate": Vector4(0.05, 0.02, 0.1, 0.6)},
		"land": {"base": -0.12, "rise": -1.4, "start": 0.15, "width": 1.4, "ridge": 0.3, "terrace": 0.0, "islands": 2.6, "island_level": 0.3, "peaks": 0.0, "south": 0.7, "pass_open": 0.0},
		"terrain": {"side_a": Color("#5a94bc"), "side_b": Color("#a8d4ec"), "cover": Vector4(1.0, 0.4, -9.0, 0.3)},
		"liquid": {"level": -0.11, "deep_color": Color("#081e34"), "shallow_color": Color("#1e567a"), "foam_color": Color("#d8eaf4"), "crust_color": Color("#c8dae8"),
			"glint_color": Color("#cfeaff"), "wave": Vector4(0.15, 0.02, 0.4, 1.2), "foam": Vector4(0.14, 0.7, 0.0, 0.2), "crust": Vector4(0.46, 0.075, 0.13, 0.0015),
			"shine": Vector4(0.5, 400.0, 0, 0)},
		"approach": 5.2, "fade_length": 60.0,
		"road": {"color_a": Color("#5a4a3c"), "color_b": Color("#705c48"), "joint_color": Color("#1c1612"), "cell": Vector4(0.34, 1.0, 0.0, 0.028), "tone": Vector4(0.3, 0.22, 0.25, 2.6)},
		"kit": {"firs": 0.0, "spires": 0.8, "rocks": 0.2, "mounds": 0.3, "bare": 0.0, "floes": 1}}

func _theme_icicle_cave() -> Dictionary:
	return {"sky": Color("#060e1c"), "fog": Color("#12284a"), "fog_density": 0.0095, "fog_max": 0.88, "fog_begin": 32.0, "fog_end": 64.0,
		"ambient": Color("#6e98d4"), "ambient_energy": 0.36, "key": Color("#bcdcff"), "key_energy": 0.9,
		"fill": Color("#6ad0ff"), "fill_energy": 0.3, "rim": Color("#5ab0ff"), "haze": Color("#0a1830"),
		"ground": {"color_a": Color("#2f4e6f"), "color_b": Color("#466787"), "joint_color": Color("#bfe2f8"), "plate": Vector4(0.085, 0.016, 0.2, 0.8),
			"lines": Vector4(0.0, 0.2, 0.6, 0.07), "pool": Vector4(0.0, 0.03, 0.1, 0.2), "glint": Vector4(0.7, 240.0, 0.0, 0.0), "rim_color": Color("#2c4c72"), "rough": 0.36,
			"glow_color": Color("#5ac8ff"), "glow": Vector4(0.25, 0.0, 0.3, 0.2)},
		"land": {"rise": 4.2, "start": 0.9, "width": 1.5, "terrace": 0.6, "step": 1.2, "peaks": 3.0, "rough": 0.3},
		"terrain": {"top_a": Color("#3c5f88"), "top_b": Color("#5880aa"), "side_a": Color("#2f5a8c"), "side_b": Color("#7fb6e0"), "strata": Vector4(0.9, 1.8, 0.2, 0.28),
			"cover": Vector4(0.3, 0.7, 0.5, 0.3), "glow_color": Color("#5ac8ff"), "glow": Vector4(0.7, 0.12, 0.045, 0.25)},
		"road": {"color_a": Color("#14244c"), "color_b": Color("#1c3060"), "edge_color": Color("#8ab8dc"), "edge": Vector4(0.13, 0.7, 0.9, 0.0)},
		"plaza": {"color_a": Color("#182a54"), "color_b": Color("#223668")},
		"kerb": {"a": Color("#7fa6c8"), "b": Color("#6c92b6")}, "fade": Color("#3c5f88"),
		"cover": Color("#a8c8e4"), "cover_amount": 0.45,
		"kit": {"firs": 0.0, "spires": 1.8, "rocks": 0.4, "mounds": 0.2, "bare": 0.0, "ice": Color("#8ec8f0")},
		"weather": {"sprite": 2, "tint": Color("#bfe6ff"), "opacity": 0.0, "brightness": 0.7, "size": Vector2(0.207, 0.207), "drift": Vector3(0.05, -0.12, 0.03), "twinkle": 1.0, "count": 110, "height": 3.4}}

func _theme_blizzard_plateau() -> Dictionary:
	# A storm: flat grey light, snow driven sideways, drifts combed by the wind.
	return {"sky": Color("#39465a"), "fog": Color("#5f7896"), "fog_density": 0.0056, "haze": Color("#7088a4"),
		"ambient": Color("#b0c0d8"), "ambient_energy": 0.40, "key": Color("#d6e0f2"), "key_energy": 0.84, "fill_energy": 0.26,
		"ground": {"color_a": Color("#38434f"), "color_b": Color("#48535f"), "line_color": Color("#62748a"), "lines": Vector4(0.5, 0.13, 0.56, 0.1), "pool": Vector4(0.0, 0.03, 0.1, 0.2),
			"rim_color": Color("#b0c0d4")},
		"land": {"rise": 1.3, "terrace": 0.0, "ridge": 0.9, "width": 3.4, "peaks": 1.6},
		"terrain": {"top_a": Color("#6c8098"), "top_b": Color("#8ea2ba"), "cover_color": Color("#a8b8cc")},
		"cover": Color("#b0c0d4"),
		"kit": {"firs": 0.2, "spires": 0.1, "rocks": 1.0, "mounds": 1.8, "snow": Color("#a4b6ca")},
		"weather": {"count": 480, "drift": Vector3(5.2, -1.6, 1.5), "stretch": 4.0, "size": Vector2(0.11, 0.16), "sway": 0.1, "brightness": 0.95}}

func _theme_glacier_crevasse() -> Dictionary:
	return {"ground": {"color_a": Color("#364857"), "color_b": Color("#4a5864"), "joint_color": Color("#0e3462"), "plate": Vector4(0.075, 0.07, 0.16, 1.0),
			"glow_color": Color("#3a9cff"), "glow": Vector4(0.55, 0.0, 0.5, 0.15), "pool": Vector4(0.0, 0.03, 0.1, 0.2), "lines": Vector4(0.3, 0.21, 0.6, 0.07),
			"glint": Vector4(0.6, 260.0, 0.0, 0.0), "rough": 0.5},
		"land": {"rise": 3.0, "start": 2.2, "width": 1.5, "terrace": 0.7, "step": 1.1, "peaks": 2.6, "moat": 3.6, "moat_width": 1.5, "pass_open": 0.0},
		"terrain": {"side_a": Color("#3f7ab4"), "side_b": Color("#92c8ee"), "strata": Vector4(1.1, 1.6, 0.2, 0.3), "glow_color": Color("#3a9cff"), "glow": Vector4(0.6, 0.14, 0.05, 0.2)},
		"approach": 4.6, "fade_length": 60.0,
		"kit": {"firs": 0.0, "spires": 1.2, "rocks": 0.4, "mounds": 0.6}}

func _theme_ice_spire_field() -> Dictionary:
	# Blue hour among the spires: the snow is in shadow and the ice carries its own light.
	return {"sky": Color("#0a1230"), "fog": Color("#1a2c60"), "fog_density": 0.006, "ambient": Color("#7c98e0"), "ambient_energy": 0.38,
		"key": Color("#c0d2ff"), "key_energy": 0.92, "fill": Color("#6ae0ff"), "fill_energy": 0.3, "rim": Color("#b09aff"), "rim_energy": 0.5, "haze": Color("#101c44"), "bloom": 0.3,
		"ground": {"color_a": Color("#30476d"), "color_b": Color("#475e82"), "joint_color": Color("#c4e6ff"), "plate": Vector4(0.06, 0.012, 0.14, 0.7),
			"glow_color": Color("#5ad0ff"), "glow": Vector4(0.4, 0.0, 0.3, 0.2), "line_color": Color("#3c5890"),
			"pool": Vector4(0.0, 0.03, 0.1, 0.2), "glint_color": Color("#bfeaff"), "glint": Vector4(0.8, 220.0, 0.0, 0.0), "rim_color": Color("#3a5490"), "rough": 0.42},
		"land": {"rise": 1.4, "terrace": 0.3, "peaks": 2.0},
		"terrain": {"top_a": Color("#3c5a94"), "top_b": Color("#5878b2"), "side_a": Color("#2f5a9c"), "side_b": Color("#7ab0e8"), "cover_color": Color("#88a6da"),
			"glow_color": Color("#5ad0ff"), "glow": Vector4(0.5, 0.13, 0.05, 0.2)},
		"road": {"color_a": Color("#171e3c"), "color_b": Color("#202a4c")}, "plaza": {"color_a": Color("#1b2342"), "color_b": Color("#253052")},
		"kerb": {"a": Color("#6f8ac0"), "b": Color("#5f7ab0")}, "fade": Color("#3c5a94"),
		"cover": Color("#8aa8dc"), "cover_amount": 0.85,
		"kit": {"firs": 0.0, "spires": 3.2, "rocks": 0.3, "mounds": 0.5, "ice": Color("#8ed0ff"), "stone": Color("#4c649c"), "snow": Color("#7c9ad0")},
		"weather": {"sprite": 2, "tint": Color("#c8ecff"), "opacity": 0.0, "brightness": 0.7, "size": Vector2(0.18, 0.18), "drift": Vector3(0.1, -0.2, 0.05), "twinkle": 1.0, "count": 150, "height": 4.5}}

func _theme_polar_night() -> Dictionary:
	return {"sky": Color("#040814"), "fog": Color("#101c44"), "fog_density": 0.0085, "fog_max": 0.88, "fog_begin": 32.0, "fog_end": 64.0,
		## The frost table under the aurora: a white moon key, the night sky as ambient, an
		## aurora-green kicker kept quiet so faces do not go green, a violet rim.
		"ambient": Color("#6c88c8"), "ambient_energy": 0.42, "key": Color("#e8eefc"), "key_energy": 1.0,
		"fill": Color("#7fd0b8"), "fill_energy": 0.26, "rim": Color("#b486ff"), "rim_energy": 0.34, "haze": Color("#0a1230"),
		## Ice with some grey in it, so the field is not one saturated blue wall.
		"ground": {"color_a": Color("#4c5c7a"), "color_b": Color("#687894"), "joint_color": Color("#a8c4f0"), "plate": Vector4(0.05, 0.012, 0.14, 0.5),
			"line_color": Color("#30426a"), "lines": Vector4(0.30, 0.21, 0.6, 0.14), "pool_color": Color("#2c4474"), "pool": Vector4(0.26, 0.12, 0.08, 0.12),
			"glint_color": Color("#7affc8"), "glint": Vector4(0.35, 200.0, 0.0, 0.4), "rim_color": Color("#2a3858"), "rough": 0.4},
		"land": {"rise": 0.9, "terrace": 0.4, "step": 0.5, "ridge": 0.7, "width": 3.6, "peaks": 2.6},
		"terrain": {"top_a": Color("#26324e"), "top_b": Color("#364668"), "side_a": Color("#243258"), "side_b": Color("#445a88"), "cover_color": Color("#4a5c84"), "cover": Vector4(0.55, 0.6, -1.0, 0.3)},
		"road": {"color_a": Color("#20284c"), "color_b": Color("#2c3858"), "edge_color": Color("#7890c0"), "edge": Vector4(0.13, 0.6, 0.9, 0.0)},
		"plaza": {"color_a": Color("#242c50"), "color_b": Color("#303c5c"), "edge_color": Color("#7890c0")},
		"kerb": {"a": Color("#5c729e"), "b": Color("#4f648e")}, "fade": Color("#26324e"),
		"cover": Color("#58709c"), "cover_amount": 0.55,
		"kit": {"firs": 0.0, "spires": 1.0, "rocks": 0.5, "mounds": 0.8, "ice": Color("#7ea4e6"), "stone": Color("#3a4868"), "snow": Color("#4c6088")},
		"weather": {"sprite": 2, "tint": Color("#d0e6ff"), "opacity": 0.0, "brightness": 0.75, "size": Vector2(0.172, 0.172), "drift": Vector3(0.1, -0.18, 0.05), "twinkle": 1.0, "count": 198, "height": 4.5}}

# --------------------------------------------------------------------------- #
# Dressing
# --------------------------------------------------------------------------- #
## Stand everything around the field. `scenery` receives the instances, `ground` is the
## land they stand on. Returns nothing; lights and haze quads are left in this object.
func dress(scenery: Props, ground_land: Land) -> void:
	scn = scenery
	land = ground_land
	# Contact pools lie on the land, in the colour of the shade, never under the water.
	scn.ground_height = Callable(land, "height")
	scn.pool_color = look["pool"]
	scn.water_level = float(look["liquid"].get("level", -INF))
	haze.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gate in land.gates: _gate(gate)
	match body:
		"aqua": _dress_aqua()
		"flame": _dress_flame()
		"rock": _dress_rock()
		"frost": _dress_frost()
		_: _dress_wood()
	_grooves()

## The dark groove at the foot of every kerb and around the plaza, drawn with the pool
## shader as one mesh each (zero instances). The kerb runs are the ones the world builds
## its kerb from (the same road lines), so the groove follows every border exactly.
func _grooves() -> void:
	var pool: Color = look["pool"]
	if float(look["kerb"]["tall"]) > 0.0:
		var runs: Array = []
		var roads := ArenaGeometry.road_polylines()
		for i in range(roads.size()):
			runs.append_array(Land.kerb_runs(Land.road_line(roads[i], float(look["approach"])), ArenaGeometry.road_layer(i) == 0))
		scn.decal_mesh(Land.kerb_skirt_mesh(runs, 0.18, Land.ARM_HEIGHT - 0.011, pool, 0.55, minf(float(look["fade_length"]), float(look["approach"]))))
	scn.decal_mesh(Land.skirt_ring(ArenaGeometry.PLAZA_RADIUS / StellarWorld.UNIT, 0.22, Land.PLAZA_TOP - 0.004, pool, 0.45))

## Half angle of the rim a gate keeps clear of border props.
func _gate_gap() -> float:
	return asin((HALF_ROAD + 0.95) / RADIUS)

## Border props along the rim: `visit` gets (position, angle, index) for every slot
## that is not in front of a gate.
func border(slots: int, visit: Callable, offset: float = 0.32) -> void:
	for n in range(slots):
		var angle := TAU * (float(n) + 0.5) / slots + rng.randf_range(-0.25, 0.25) * TAU / slots
		if land.gate_near(angle, _gate_gap()): continue
		var r := RADIUS + offset + rng.randf_range(-0.05, 0.12)
		visit.call(at_ground(cos(angle) * r, sin(angle) * r), angle, n)

# ----- gates ---------------------------------------------------------------- #
## Every gate: two pylons in the biome's own make flanking the road at the rim, a warm
## lantern on each, a glowing threshold in the gate hue and a slow rift haze between the
## pylons. Built the same way at every angle so an entrance reads from any side.
func _gate(direction: Vector2) -> void:
	var out := Vector3(direction.x, 0, direction.y)
	var across := Vector3(-direction.y, 0, direction.x)
	var yaw := atan2(-direction.x, -direction.y)
	var centre := out * (RADIUS + 0.28)
	var reach := HALF_ROAD + 0.50
	var tall := 2.25 + 0.14 * (rank - 1)
	var threat := 0.5 + 0.5 * harsh
	for side: float in [-1.0, 1.0]:
		var foot := centre + across * reach * side
		foot.y = 0.0
		match body:
			"aqua": _pile(foot, tall, side, yaw, across)
			"flame": _horn(foot, tall, side, yaw, across)
			"rock": _pier(foot, tall, side, yaw, across)
			"frost": _ice_post(foot, tall, side, yaw, across)
			_: _shrine_post(foot, tall, side, yaw, across)
		# Every pylon stands in its own pool of shadow.
		scn.contact(foot, Vector2(1.5, 1.5), 0.6)
	_lintel(centre, across, reach, tall, yaw)
	# Threshold: a lit sill across the road and bevelled studs marching inward.
	var sill := out * (RADIUS - 0.10) + Vector3(0, 0.045, 0)
	scn.part("stone", sill, Vector3(HALF_ROAD * 2.0 - 0.3, 0.03, 0.10), GATE_HUE, 0.55 + 0.35 * harsh, Vector3(0, yaw, 0))
	for step in range(3):
		for side: float in [-1.0, 1.0]:
			var stud := out * (RADIUS - 0.55 - step * 0.5) + across * (HALF_ROAD - 0.42) * side + Vector3(0, 0.04, 0)
			scn.part("stone", stud, Vector3(0.16, 0.03, 0.16), GATE_HUE, 0.35 + 0.3 * harsh, Vector3(0, yaw + PI / 4, 0))
	haze_floor(out * (RADIUS + 0.5) + Vector3(0, 0.06, 0), Vector2(HALF_ROAD * 2.0 + 0.9, 3.4), -yaw, GATE_HUE, 0.0, 0.05, 4, 0.10 + 0.12 * harsh)
	haze_quad(out * (RADIUS + 0.55) + Vector3(0, 0.05, 0), HALF_ROAD * 2.0 + 0.5, tall * 0.95, GATE_HUE.lerp(Color("#ff5a48"), harsh), 0.0, 0.07 + 0.05 * harsh, 0, 0.16 * threat + 0.05)
	# The gate lamp hangs low with a short reach: a tight warm pool on the ground.
	light(out * (RADIUS + 0.9) + Vector3(0, 1.6, 0), look["lamp"], float(look["lamp_energy"]), 3.6)

## Cross member of a gate. Thin on purpose: a gate on the camera side must not hide
## what steps through it.
func _lintel(centre: Vector3, across: Vector3, reach: float, tall: float, yaw: float) -> void:
	var span := reach * 2.0
	match body:
		"aqua":
			scn.part("box", centre + Vector3(0, tall - 0.34, 0), Vector3(span + 0.7, 0.13, 0.17), Color("#4b3626"), 0.0, Vector3(0, yaw, 0))
			for n in range(5):
				var f := (float(n) + 0.5) / 5.0 - 0.5
				scn.link(centre + across * span * f + Vector3(0, tall - 0.40, 0), centre + across * span * f + Vector3(0, tall - 0.40 - 0.22 - absf(f) * 0.3, 0), 0.016, Color("#b7a88a"))
		"flame":
			var a := centre - across * (reach - 0.22) + Vector3(0, tall - 0.2, 0)
			var b := centre + across * (reach - 0.22) + Vector3(0, tall - 0.2, 0)
			var links := 9
			var previous := a
			for n in range(1, links + 1):
				var f := float(n) / links
				var point := a.lerp(b, f) - Vector3(0, sin(f * PI) * 0.42, 0)
				scn.link(previous, point, 0.028, Color("#2a2426"))
				previous = point
		"rock":
			scn.part("box", centre + Vector3(0, tall - 0.12, 0), Vector3(span + 1.0, 0.22, 0.30), Color("#5a4636"), 0.0, Vector3(0, yaw, 0))
			for side: float in [-1.0, 1.0]:
				scn.part("box", centre + across * (reach + 0.38) * side + Vector3(0, tall - 0.62, 0), Vector3(0.30, 0.78, 0.035), Color("#b8483c").lerp(Color("#7a2a2a"), harsh), 0.0, Vector3(0, yaw, 0))
		"frost":
			var a := centre - across * (reach - 0.1) + Vector3(0, tall * 0.80, 0)
			var b := centre + across * (reach - 0.1) + Vector3(0, tall * 0.80, 0)
			var previous := a
			for n in range(1, 9):
				var f := float(n) / 8.0
				var point := a.lerp(b, f) + Vector3(0, sin(f * PI) * 0.34, 0)
				scn.link(previous, point, 0.045, Color("#a9d4ee"), 0.12)
				if n % 2 == 0 and n < 8: scn.stand("spire0", point, Vector3(0.11, 0.36, 0.11), 0.0, Color("#bfe2f6"), Color.BLACK, 0.1, 0.0, Vector2(PI, 0.0))
				previous = point
		_:
			scn.part("box", centre + Vector3(0, tall - 0.08, 0), Vector3(span + 1.25, 0.15, 0.26), Color("#7a3f34"), 0.0, Vector3(0, yaw, 0))
			scn.part("box", centre + Vector3(0, tall + 0.04, 0), Vector3(span + 1.5, 0.08, 0.34), Color("#3a3432"), 0.0, Vector3(0, yaw, 0))
			scn.part("box", centre + Vector3(0, tall - 0.48, 0), Vector3(span + 0.5, 0.11, 0.15), Color("#7a3f34"), 0.0, Vector3(0, yaw, 0))

## A small warm lantern (the sanctuary's own light) on top of `at`.
func _lantern(at: Vector3, scale: float = 1.0, stone: Color = Color("#657c91")) -> void:
	scn.part("stone", at + Vector3(0, 0.05, 0) * scale, Vector3(0.44, 0.10, 0.44) * scale, stone)
	scn.part("box", at + Vector3(0, 0.27, 0) * scale, Vector3(0.25, 0.34, 0.25) * scale, look["lamp"], 0.9)
	for x in [-1, 1]:
		for z in [-1, 1]: scn.part("box", at + Vector3(x * 0.15, 0.27, z * 0.15) * scale, Vector3(0.045, 0.38, 0.045) * scale, Color("#4a4238"))
	scn.part("pyramid", at + Vector3(0, 0.45, 0) * scale, Vector3(0.62, 0.26, 0.62) * scale, stone.darkened(0.12))

func _shrine_post(foot: Vector3, tall: float, side: float, yaw: float, across: Vector3) -> void:
	scn.part("stone", foot + Vector3(0, 0.12, 0), Vector3(0.62, 0.24, 0.62), Color("#66786f"), 0.0, Vector3(0, yaw, 0))
	scn.part("cylinder", foot + Vector3(0, tall * 0.5, 0), Vector3(0.26, tall, 0.26), Color("#7a3f34"))
	scn.part("cylinder", foot + Vector3(0, 0.36, 0), Vector3(0.31, 0.24, 0.31), Color("#2f2a28"))
	# Stone lantern beside the post, away from the road.
	var out := across * side
	var beside := foot + out * 0.80
	scn.part("stone", beside + Vector3(0, 0.10, 0), Vector3(0.56, 0.20, 0.56), Color("#66786f"), 0.0, Vector3(0, yaw, 0))
	scn.part("stone", beside + Vector3(0, 0.50, 0), Vector3(0.30, 0.62, 0.30), Color("#586a62"), 0.0, Vector3(0, yaw, 0))
	_lantern(beside + Vector3(0, 0.80, 0), 1.15, Color("#66786f"))
	scn.contact(beside, Vector2(0.9, 0.9), 0.5)
	if rank >= 3:
		scn.stand("dead0", foot + out * 1.55, Vector3(0.9, 1.5 + 0.2 * rank, 0.9), yaw + side, Color("#2f2a26"))

func _pile(foot: Vector3, tall: float, side: float, yaw: float, across: Vector3) -> void:
	scn.stand("column", foot - Vector3(0, 0.5, 0), Vector3(0.36, tall + 0.5, 0.36), yaw, Color("#4b3626"))
	scn.part("ring", foot + Vector3(0, tall * 0.42, 0), Vector3(0.44, 0.5, 0.44), Color("#b7a88a"))
	scn.part("ring", foot + Vector3(0, tall * 0.42 + 0.07, 0), Vector3(0.44, 0.5, 0.44), Color("#a3947a"))
	scn.part("cylinder", foot + Vector3(0, tall + 0.03, 0), Vector3(0.44, 0.07, 0.44), Color("#39291d"))
	_lantern(foot + Vector3(0, tall + 0.06, 0), 0.95, Color("#5a4632"))
	var out := across * side
	scn.stand("column", foot + out * 0.62 - Vector3(0, 0.5, 0), Vector3(0.24, tall * 0.62 + 0.5, 0.24), yaw + 0.5, Color("#43301f"), Color.BLACK, 0.0, 0.0, Vector2(0.0, 0.10 * side))
	if rank >= 4:
		scn.part("box", foot + out * 0.3 + Vector3(0, tall * 0.7, 0), Vector3(0.9, 0.5, 0.03), Color("#3a4a50"), 0.0, Vector3(0.1, yaw, 0.2 * side))

func _horn(foot: Vector3, tall: float, side: float, yaw: float, across: Vector3) -> void:
	scn.stand("rock1", foot - Vector3(0, 0.06, 0), Vector3(1.05, 0.7, 1.05), yaw + side, Color("#352c2e"))
	var lean := Vector2(0.0, 0.0)
	var glow := 0.10 + 0.45 * harsh
	scn.stand("spire0", foot + Vector3(0, 0.18, 0), Vector3(0.62, tall + 0.35, 0.62), yaw, Color("#2c2528"), Color.BLACK, glow, 0.0, lean)
	scn.stand("spire2", foot - across * side * 0.34 + Vector3(0, 0.1, 0), Vector3(0.40, tall * 0.58, 0.40), yaw + 1.0, Color("#3a2e30"), Color.BLACK, glow * 0.7)
	# Fire bowl on the outer shoulder.
	var bowl := foot + across * side * 0.62 + Vector3(0, 0.62, 0)
	scn.part("cylinder", bowl - Vector3(0, 0.32, 0), Vector3(0.20, 0.62, 0.20), Color("#2a2426"))
	scn.part("sphere", bowl, Vector3(0.50, 0.24, 0.50), Color("#3a3032"))
	scn.part("sphere", bowl + Vector3(0, 0.10, 0), Vector3(0.36, 0.16, 0.36), Color("#ff8a2e"), 0.95)
	scn.part("cone", bowl + Vector3(0, 0.30, 0), Vector3(0.24, 0.42, 0.24), Color("#ffb14a"), 0.95)

func _pier(foot: Vector3, tall: float, side: float, yaw: float, across: Vector3) -> void:
	var stone := Color("#a08a6a").lerp(Color("#7c6a56"), harsh)
	var levels := 4
	for level in range(levels):
		var size := 0.82 - level * 0.07
		var height := (tall - 0.2) / levels
		scn.part("stone", foot + Vector3(0, height * (level + 0.5), 0), Vector3(size, height - 0.02, size), stone.darkened(0.05 * (level % 2)), 0.0, Vector3(0, yaw + level * 0.06 * side, 0))
	var out := across * side
	scn.link(foot + out * 0.34 + Vector3(0, tall - 0.3, 0), foot + out * 0.34 + Vector3(0, tall - 0.75, 0), 0.014, Color("#3a3028"))
	scn.part("box", foot + out * 0.34 + Vector3(0, tall - 0.88, 0), Vector3(0.20, 0.26, 0.20), look["lamp"], 0.9)
	scn.part("pyramid", foot + out * 0.34 + Vector3(0, tall - 0.76, 0), Vector3(0.30, 0.12, 0.30), Color("#3a3028"))
	if rank >= 3:
		scn.stand("rock2", foot + out * 0.95, Vector3(0.9, 0.8, 0.9), yaw + side * 2.0, stone.darkened(0.1))

func _ice_post(foot: Vector3, tall: float, side: float, yaw: float, across: Vector3) -> void:
	scn.stand("rock0", foot - Vector3(0, 0.05, 0), Vector3(1.0, 0.62, 1.0), yaw + side, Color("#8ea8c0"))
	scn.stand("spire1", foot + Vector3(0, 0.12, 0), Vector3(0.66, tall + 0.45, 0.66), yaw + side, Color("#a6d2ee"), Color.BLACK, 0.10 + 0.14 * harsh)
	var out := across * side
	scn.stand("spire2", foot + out * 0.46 + Vector3(0, 0.05, 0), Vector3(0.38, tall * 0.55, 0.38), yaw + 2.0, Color("#bfe0f4"), Color.BLACK, 0.08)
	scn.part("stone", foot + out * 0.98 + Vector3(0, 0.34, 0), Vector3(0.30, 0.68, 0.30), Color("#6f8296"), 0.0, Vector3(0, yaw, 0))
	_lantern(foot + out * 0.98 + Vector3(0, 0.68, 0), 1.05, Color("#7f93a8"))
	scn.contact(foot + out * 0.98, Vector2(0.8, 0.8), 0.5)

# ----- wood ----------------------------------------------------------------- #
## One tree of the field's own mix at `at`; `size` is its height in world units.
func _grow(at: Vector3, size: float, pick: float, n: int, yaw: float) -> void:
	var kit: Dictionary = look["kit"]
	var total := float(kit["fir"]) + float(kit["tree"]) + float(kit["bamboo"]) + float(kit["dead"]) + float(kit["mush"])
	var roll := pick * total
	var bark: Color = kit["bark"]
	if roll < float(kit["fir"]):
		# `stilt` lifts the crown on a bare trunk (old cedars, high pines).
		var stilt := float(kit.get("stilt", 0.0)) * size
		if stilt > 0.0: scn.stand("column", at - Vector3(0, 0.2, 0), Vector3(size * 0.13, stilt + 0.5, size * 0.13), yaw, bark)
		scn.stand("fir%d" % (n % 3), at + Vector3(0, stilt, 0), Vector3(size * 0.60, size, size * 0.60), yaw, _vary(kit["needle"][n % 3]), bark, 0.0, 0.04, _lean())
		return
	roll -= float(kit["fir"])
	if roll < float(kit["tree"]):
		scn.stand("tree%d" % (n % 3), at, Vector3(size * 0.92, size * 0.84, size * 0.92), yaw, _vary(kit["leaf"][n % 3]), bark, 0.0, 0.05, _lean())
		return
	roll -= float(kit["tree"])
	if roll < float(kit["bamboo"]):
		for k in range(3):
			var offset := Vector3(cos(yaw + k * 2.2), 0, sin(yaw + k * 2.2)) * 0.34 * k
			scn.stand("bamboo", at + offset, Vector3(size * 0.8, size * rng.randf_range(0.8, 1.15), size * 0.8), yaw + k, Color(kit["leaf"][0]).lerp(Color("#b9c46a"), 0.45), kit["leaf"][(n + k) % 3], 0.0, 0.10)
		return
	roll -= float(kit["bamboo"])
	if roll < float(kit["dead"]):
		scn.stand("dead%d" % (n % 2), at, Vector3(size * 0.6, size * 0.8, size * 0.6), yaw, bark.darkened(0.25), Color.BLACK, 0.0, 0.0, _lean(0.08))
		return
	var cap: Color = kit["cap"]
	scn.stand("mush%d" % (n % 2), at, Vector3(size * 0.72, size * 0.62, size * 0.72), yaw, cap.lerp(Color("#e8c46a"), 0.25 * (n % 3)), Color("#e6dcc2"), float(kit["cap_glow"]))

func _dress_wood() -> void:
	var kit: Dictionary = look["kit"]
	var stone: Color = kit["stone"]
	var fern: Color = kit["fern"]
	var density := float(kit["density"])
	# The edge of the clearing: mossy stones, ferns and the first small mushrooms.
	border(60, func(at: Vector3, angle: float, n: int) -> void:
		match n % 6:
			0, 3: scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.05, 0), Vector3(0.8, 0.62, 0.8) * rng.randf_range(0.75, 1.3), angle * 3.0, stone)
			1: scn.stand("tuft", at, Vector3(0.75, rng.randf_range(0.42, 0.66), 0.75), angle, fern.lightened(0.08), fern, 0.0, 0.05)
			2: scn.stand("mush%d" % (n % 2), at, Vector3.ONE * rng.randf_range(0.26, 0.44), angle, kit["cap"], Color("#e6dcc2"), float(kit["cap_glow"]))
			4: scn.stand("rock3", at - Vector3(0, 0.04, 0), Vector3(1.15, 0.5, 0.85), angle * 2.0, stone.darkened(0.08))
			_: scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.03, 0), Vector3(0.7, 0.55, 0.7) * rng.randf_range(0.8, 1.2), angle * 5.0, fern.darkened(0.12))
	)
	# Three belts of trees: a close rank of fewer, bigger trees that frames the clearing,
	# the body of the forest behind it and the giants that fill the far corners.
	scatter(int(60 * density), 1.25, 3.1, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		_grow(at, rng.randf_range(2.0, 3.0) * lerpf(0.5, 1.0, tall_room(at.x, at.z)), rng.randf(), n, angle * 7.0)
	)
	scatter(int(90 * density), 3.0, 7.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		_grow(at, rng.randf_range(2.4, 3.7) * lerpf(0.45, 1.0, tall_room(at.x, at.z)), rng.randf(), n, angle * 7.0)
	)
	scatter(int(90 * density), 7.0, 14.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		_grow(at, rng.randf_range(3.2, 4.8) * lerpf(0.5, 1.0, tall_room(at.x, at.z)), rng.randf(), n, angle * 7.0)
	)
	# Undergrowth between the trunks.
	scatter(90, 0.7, 9.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		match n % 4:
			0: scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.08, 0), Vector3(1.0, 0.8, 1.0) * rng.randf_range(0.6, 1.5), angle * 3.0, stone.darkened(0.06))
			1: scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.05, 0), Vector3(1.1, 0.8, 1.1) * rng.randf_range(0.6, 1.2), angle * 3.0, Color(kit["leaf"][n % 3]).darkened(0.18))
			_: scn.stand("tuft", at, Vector3(0.9, 0.5, 0.9) * rng.randf_range(0.8, 1.4), angle, fern, fern, 0.0, 0.05)
	)
	if has_method("_place_" + id): call("_place_" + id)

func _place_spring_grove() -> void:
	# Petal drifts under the blossom and a couple of beehives at the edge of the wood.
	for n in range(8):
		var at := spot(-160.0 + n * 45.0, 1.5 + (n % 3) * 0.6, 0.2)
		haze_floor(at + Vector3(0, 0.05, 0), Vector2(2.6, 1.8), n * 0.9, Color("#f2c8d8"), 1.0, 0.0, 4, 0.5)
	for n in range(3):
		var at := spot(-50.0 + n * 50.0, 2.2)
		scn.part("cylinder", at + Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.5), Color("#c8a85a"))
		scn.part("cone", at + Vector3(0, 0.75, 0), Vector3(0.66, 0.34, 0.66), Color("#8a6a3a"))

func _place_mushroom_hollow() -> void:
	# The elders of the hollow: a ring of giants behind the clearing.
	for n in range(7):
		var at := spot(-84.0 + n * 28.0, 2.6 + (n % 2) * 1.0, 0.2)
		var size := lerpf(1.4, 4.4, tall_room(at.x, at.z)) * (0.8 + 0.2 * (n % 3))
		scn.stand("mush%d" % (n % 2), at, Vector3(size * 0.9, size * 0.8, size * 0.9), n * 1.3, [Color("#c8503f"), Color("#d08a3a"), Color("#8a5aa8")][n % 3], Color("#e6dcc2"), 0.3)
	light(spot(-30.0, 2.4) + Vector3(0, 1.2, 0), Color("#ffb070"), 0.9, 6.0)

func _place_bamboo_grove() -> void:
	var stone := Color("#6e7a74")
	for n in range(5):
		var at := spot(-110.0 + n * 55.0, 1.9)
		scn.part("stone", at + Vector3(0, 0.12, 0), Vector3(0.6, 0.24, 0.6), stone)
		scn.part("stone", at + Vector3(0, 0.55, 0), Vector3(0.3, 0.66, 0.3), stone.darkened(0.1))
		_lantern(at + Vector3(0, 0.88, 0), 1.1, stone)
		scn.contact(at, Vector2(1.0, 1.0), 0.5)
	var at := spot(-6.0, 3.6)
	hut(frame(at, facing(at), 0.95), Color("#6a5238"), Color("#3f4a44"), 0.7, false)
	light(at + Vector3(0, 0.9, 1.4), look["lamp"], 0.9, 4.2)

func _place_vine_ruins() -> void:
	var stone := Color("#7a8078")
	for n in range(9):
		var at := spot(-150.0 + n * 37.0, 2.0 + (n % 3) * 0.9, 0.22)
		var f := frame(at, facing(at) + 0.15 * ((n % 3) - 1), lerpf(0.6, 1.1, tall_room(at.x, at.z)))
		match n % 3:
			0: span(f, stone, 2.4, 2.7, n % 2 == 0)
			1: pillar(f, stone.darkened(0.05), 2.6, n % 4 == 1)
			_: rampart(f, stone.darkened(0.08), 2.6, 1.5, 0.6)
		# Vines hang off every piece.
		for k in range(3):
			scn.link(f * Vector3((k - 1) * 0.8, 2.5, 0.4), f * Vector3((k - 1) * 0.8 + 0.2, 0.6 + k * 0.4, 0.5), 0.08, Color("#3f6a3a"))

func _place_misty_cedar() -> void:
	for n in range(9):
		var at := spot(-170.0 + n * 42.0, 2.0 + (n % 3) * 2.2, 0.06)
		mist(at + Vector3(0, 0.45, 0), Vector2(11, 5), Color("#9cc0c8"), 0.28, n * 0.7)

func _place_thornbrake() -> void:
	var thorn := Color("#2a221a")
	# Briars arch over the edge of the field and close the wood behind it.
	scatter(46, 0.9, 7.5, func(at: Vector3, angle: float, d: float, n: int) -> void:
		var reach := rng.randf_range(1.6, 3.4)
		var tall := lerpf(0.6, 2.2, tall_room(at.x, at.z)) * rng.randf_range(0.7, 1.2)
		var to := at + Vector3(cos(angle * 5.0), 0, sin(angle * 5.0)) * reach
		to.y = ground(to.x, to.z)
		arc(at, to, tall, 0.16, 0.06, thorn, 0.0, 6)
		for k in range(4):
			var t := (float(k) + 0.5) / 4.0
			var point := at.lerp(to, t) + Vector3(0, sin(t * PI) * tall, 0)
			scn.stand("spire0", point, Vector3(0.1, 0.34, 0.1), k * 1.7, thorn.lightened(0.1), Color.BLACK, 0.0, 0.0, Vector2(sin(k * 2.0) * 0.9, cos(k * 1.4) * 0.9))
	)

func _place_moss_bog() -> void:
	var level := float(look["liquid"]["level"])
	for n in range(6):
		var at := spot(-150.0 + n * 60.0, 3.0 + (n % 2) * 2.0, 0.1)
		mist(Vector3(at.x, level + 0.35, at.z), Vector2(9, 4.5), Color("#8fc8a0"), 0.36, n * 0.8)
	light(spot(-46.0, 3.0) + Vector3(0, 0.8, 0), Color("#8affb0"), 1.0, 5.5)
	light(spot(52.0, 3.4) + Vector3(0, 0.8, 0), Color("#8affb0"), 0.9, 5.5)

func _place_frost_pines() -> void:
	for n in range(6):
		var at := spot(-150.0 + n * 60.0, 2.2 + (n % 2) * 1.6)
		scn.stand("dome", at - Vector3(0, 0.1, 0), Vector3(2.4, 0.9 * lerpf(0.6, 1.0, tall_room(at.x, at.z)), 2.0), n * 0.9, Color("#9fb2c4"))

func _place_rotroot_hollow() -> void:
	var root := Color("#342a20")
	# The hollow: a mouth of roots behind the field and roots crawling out of it.
	var mouth := spot(-8.0, 3.4)
	var f := frame(Vector3(mouth.x, 0.0, mouth.z), facing(mouth), 1.0)
	put(f, "arch", Vector3(0, 0, 0), Vector3(6.4, 7.6, 2.2), root.darkened(0.1))
	put(f, "box", Vector3(0, 1.4, -0.9), Vector3(4.2, 2.8, 0.4), Color("#060806"))
	for k in range(7): put_link(f, Vector3((k - 3) * 0.62, 3.1 - absf(k - 3) * 0.5, 0.9), Vector3((k - 3) * 0.7, 1.1 + (k % 3) * 0.5, 1.1), 0.09, root.lightened(0.05))
	for n in range(11):
		var from := spot(-100.0 + n * 21.0, 3.0 + (n % 2) * 1.6, 0.14)
		var angle := atan2(from.z, from.x) + (0.5 if n % 2 == 0 else -0.5)
		var to := at_ground(cos(angle) * (RADIUS + 0.9), sin(angle) * (RADIUS + 0.9))
		arc(from + Vector3(0, 0.6, 0), to, lerpf(0.4, 1.5, tall_room(from.x, from.z)), 0.62, 0.16, root.darkened(0.04 * (n % 3)), 0.0, 7)
	for n in range(10):
		var at := spot(-160.0 + n * 36.0, 1.5 + (n % 3) * 0.8, 0.18)
		scn.stand("mush%d" % (n % 2), at, Vector3.ONE * (0.5 + 0.25 * (n % 3)), n * 1.1, Color("#5fe0b0"), Color("#c8d8b8"), 0.8)
	light(f * Vector3(0, 1.0, 2.0), Color("#7affa0"), 1.1, 6.5)

func _place_worldtree_roots() -> void:
	var bark := Color("#6a5a48")
	var pale := Color("#b0aa8a")
	# The foot of the tree fills the far side; its roots run round the clearing.
	var foot := spot(0.0, 6.2, 0.0)
	for n in range(7):
		var angle := TAU * float(n) / 7.0
		var at := Vector3(foot.x + cos(angle) * 2.3, -0.5, foot.z + sin(angle) * 1.6)
		scn.stand("column", at, Vector3(3.2 + (n % 3) * 0.7, 13.0, 3.2 + (n % 2) * 0.8), angle, bark.darkened(0.05 * (n % 3)))
	scn.stand("column", Vector3(foot.x, -0.5, foot.z), Vector3(5.4, 14.0, 4.6), 0.3, bark)
	# Roots reach the rim only where the way there does not cross the field; further
	# round they surface on their own and dive again.
	for n in range(9):
		var spread := -1.0 + 2.0 * float(n) / 8.0
		var from := Vector3(foot.x + spread * 3.6, 1.6 + absf(spread) * 0.3, foot.z + 1.3)
		var angle := deg_to_rad(-90.0 + spread * 40.0)
		if land.gate_near(angle, 0.16): angle += 0.26
		var to := at_ground(cos(angle) * (RADIUS + 0.8 + (n % 3) * 0.5), sin(angle) * (RADIUS + 0.8 + (n % 3) * 0.5))
		arc(from, to, 0.9 + absf(spread) * 0.9, 1.0, 0.2, pale.darkened(0.06 * (n % 3)), 0.0, 9)
	for n in range(12):
		var angle := deg_to_rad(-90.0 + (52.0 + n * 23.0) * (1.0 if n % 2 == 0 else -1.0))
		if land.gate_near(angle, 0.2): continue
		var from := at_ground(cos(angle) * (RADIUS + 3.6), sin(angle) * (RADIUS + 3.6))
		var to := at_ground(cos(angle + 0.2) * (RADIUS + 0.9), sin(angle + 0.2) * (RADIUS + 0.9))
		arc(from - Vector3(0, 0.3, 0), to, lerpf(0.4, 1.4, tall_room(from.x, from.z)), 0.7, 0.18, pale.darkened(0.06 * (n % 3)), 0.0, 7)
	for n in range(12):
		var at := spot(-120.0 + n * 21.0, 2.0 + (n % 4) * 1.1, 0.14)
		scn.stand("crystal%d" % (n % 2), at - Vector3(0, 0.1, 0), Vector3(0.9, lerpf(0.8, 1.7, tall_room(at.x, at.z)), 0.9), n * 1.9, Color("#5fe8cc"), Color.BLACK, 0.5)
	light(foot + Vector3(-3.5, 1.6, 3.0), Color("#6affd8"), 1.3, 8.0)
	light(foot + Vector3(3.5, 1.6, 3.0), Color("#6affd8"), 1.2, 8.0)

# ----- aqua ----------------------------------------------------------------- #
func _dress_aqua() -> void:
	var kit: Dictionary = look["kit"]
	var wood: Color = kit["wood"]
	var reed: Color = kit["reed"]
	var head: Color = kit["head"]
	var stone: Color = kit["stone"]
	var level := float(look["liquid"].get("level", -0.09))
	var reeds := float(kit["reeds"])
	# Quay edge: piles stand in the water all round, reed beds between them.
	border(44, func(at: Vector3, angle: float, n: int) -> void:
		if n % 2 == 0:
			scn.stand("column", Vector3(at.x, level - 0.5, at.z), Vector3(0.22, 0.5 + rng.randf_range(0.42, 0.78), 0.22), angle, wood, Color.BLACK, 0.0, 0.0, Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08)))
		elif rng.randf() < reeds:
			scn.stand("reed", Vector3(at.x, maxf(at.y, level - 0.05), at.z), Vector3(0.9, rng.randf_range(0.7, 1.1), 0.9), angle * 3.0, reed, head, 0.0, 0.08)
		else:
			scn.stand("rock%d" % (n % 4), Vector3(at.x, maxf(at.y, level) - 0.12, at.z), Vector3(0.8, 0.6, 0.8) * rng.randf_range(0.7, 1.2), angle * 3.0, stone)
	)
	for gate in land.gates: _jetty(gate, level)
	scatter(int(110 * maxf(reeds, 0.2)), 0.6, 12.0, func(at: Vector3, angle: float, d: float, n: int) -> void:
		var dry := at.y > level + 0.02
		if dry and rng.randf() < reeds:
			scn.stand("reed", at, Vector3(1.1, rng.randf_range(0.8, 1.5) * lerpf(0.7, 1.0, tall_room(at.x, at.z)), 1.1), angle * 5.0, reed, head, 0.0, 0.08)
		elif at.y > level - 0.3 and rng.randf() < reeds * 0.6:
			scn.stand("reed", Vector3(at.x, level - 0.06, at.z), Vector3(0.9, rng.randf_range(0.6, 1.1), 0.9), angle * 5.0, reed, head, 0.0, 0.08)
		elif not dry and d < 6.0 and rng.randf() < float(kit["pads"]) * 0.5:
			scn.stand("pad", Vector3(at.x, level + 0.012, at.z), Vector3.ONE * rng.randf_range(0.35, 0.75), angle * 9.0, Color(kit["pad"]).lerp(Color("#5a8a4a"), rng.randf()))
	)
	scatter(int(48 * float(kit["rocks"])), 0.8, 12.5, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		var size := rng.randf_range(0.75, 2.1)
		scn.stand("rock%d" % (n % 4), Vector3(at.x, maxf(at.y, level) - 0.18 * size, at.z), Vector3(1.2, lerpf(0.8, 1.5, tall_room(at.x, at.z)), 1.2) * size, angle * 3.0, _vary(stone.darkened(0.05 * (n % 3))), Color.BLACK, 0.0, 0.0, _lean(0.05))
	)
	scatter(int(32 * float(kit["snags"])), 1.0, 11.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		scn.stand("dead%d" % (n % 2), Vector3(at.x, maxf(at.y, level) - 0.1, at.z), Vector3(1.0, rng.randf_range(1.2, 2.6) * lerpf(0.5, 1.0, tall_room(at.x, at.z)), 1.0), angle * 5.0, wood.darkened(0.3), Color.BLACK, 0.0, 0.0, Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)))
	)
	if has_method("_place_" + id): call("_place_" + id)

## A pier is the approach of a water field: posts down both sides of the boardwalk,
## taller mooring posts at its end, and a boat tied there on the calmer waters.
func _jetty(direction: Vector2, level: float) -> void:
	var kit: Dictionary = look["kit"]
	var wood: Color = kit["wood"]
	var out := Vector3(direction.x, 0, direction.y)
	var across := Vector3(-direction.y, 0, direction.x)
	var reach := float(look["approach"])
	if float(look["fade_length"]) < 20.0: return
	var steps := int(reach / 1.25)
	for step in range(1, steps + 1):
		var d := float(step) * reach / steps
		for side: float in [-1.0, 1.0]:
			var at := out * (RADIUS + d) + across * (HALF_ROAD + 0.06) * side
			var last := step == steps
			scn.stand("column", Vector3(at.x, level - 0.6, at.z), Vector3(0.2 if not last else 0.28, 0.6 + (0.34 if not last else 0.95), 0.2 if not last else 0.28), d, wood.darkened(0.08 * (step % 2)))
			if last: scn.part("ring", Vector3(at.x, 0.52, at.z), Vector3(0.36, 0.5, 0.36), Color("#b7a88a"))
	if int(kit["boats"]) > 0:
		var side := 1.0 if direction.x > 0.0 else -1.0
		var at := out * (RADIUS + reach - 1.1) + across * (HALF_ROAD + 0.85) * side
		boat(frame(Vector3(at.x, level - 0.04, at.z), atan2(direction.x, direction.y) + 0.12), wood.lightened(0.12))

func _place_calm_lake() -> void:
	var level := float(look["liquid"]["level"])
	# A fishing hut on stilts across the water, a lantern at its door.
	var at := spot(-38.0, 3.6)
	var f := frame(Vector3(at.x, level + 0.75, at.z), facing(at) + 0.3, 1.05)
	for x: float in [-0.7, 0.7]:
		for z: float in [-0.55, 0.55]: put(f, "column", Vector3(x, -1.4, z), Vector3(0.16, 1.4, 0.16), Color("#43301f"))
	put(f, "box", Vector3(0, 0.0, 0.25), Vector3(2.2, 0.1, 2.2), Color("#7a6040"))
	hut(f, Color("#7a6546"), Color("#4f5a52"), 0.85, false)
	put_link(f, Vector3(0.95, 0.0, 1.2), Vector3(1.35, -0.8, 1.9), 0.05, Color("#43301f"))
	light(f * Vector3(0, 0.9, 1.2), look["lamp"], 0.9, 3.6)
	boat(frame(Vector3(at.x + 2.2, level - 0.04, at.z + 1.4), 0.9), Color("#6f5638"))
	for n in range(5):
		var hill := spot(-70.0 + n * 34.0, 10.5 + (n % 2) * 2.0, 0.0)
		scn.stand("dome", Vector3(hill.x, level - 0.3, hill.z), Vector3(6.5, 2.2, 5.0) * (0.8 + 0.2 * (n % 3)), n * 1.1, Color("#2f4a40"))
	mist(Vector3(-5.0, level + 0.3, -15.5), Vector2(16, 5), Color("#9fc8d0"), 0.3)

func _place_reed_marsh() -> void:
	var level := float(look["liquid"]["level"])
	for n in range(7):
		var angle := TAU * float(n) / 7.0 + 0.4
		var d := 4.0 + (n % 3) * 2.2
		mist(Vector3(cos(angle) * (RADIUS + d), level + 0.35, sin(angle) * (RADIUS + d)), Vector2(9, 4.5), Color("#a8c8b4"), 0.34, angle)
	for n in range(4):
		var at := spot(-80.0 + n * 52.0, 3.4 + (n % 2) * 1.6)
		scn.stand("dead%d" % (n % 2), Vector3(at.x, level - 0.1, at.z), Vector3(1.6, 3.0 + n * 0.3, 1.6), n * 2.0, Color("#3a342c"), Color.BLACK, 0.0, 0.0, Vector2(0.12, -0.1))

func _place_aqueduct_ruin() -> void:
	var level := float(look["liquid"]["level"])
	var stone := Color("#7f8482")
	# The aqueduct crosses behind the field: a run of arches, two of them fallen.
	for n in range(-4, 5):
		var x := float(n) * 3.4
		var z := -RADIUS - 3.6 - absf(float(n)) * 0.28
		if land.corridor(x, z) < HALF_ROAD + 1.8: continue
		span(frame(Vector3(x, level - 0.5, z), 0.0, 1.15), stone.darkened(0.04 * (absi(n) % 2)), 2.6, 3.0, n not in [-2, 3])
	for n in range(6):
		var at := spot(-150.0 + n * 60.0, 2.2 + (n % 2) * 1.2)
		pillar(frame(Vector3(at.x, maxf(at.y, level) - 0.1, at.z), n * 0.7, 1.0 if at.z < 0 else 0.7), stone, 2.3, n % 2 == 1)

func _place_falls_gorge() -> void:
	var level := float(look["liquid"]["level"])
	# The river comes over the far wall in three falls.
	for n in range(3):
		var angle := clear_angle(deg_to_rad(-90.0 + (n - 1) * 34.0), 0.3, 0.3)
		var edge := RADIUS + 2.7
		var top := ground(cos(angle) * (RADIUS + 4.0), sin(angle) * (RADIUS + 4.0))
		if top < 1.2: continue
		var at := Vector3(cos(angle) * edge, top, sin(angle) * edge)
		fall(at, 2.6 if n == 1 else 1.7, top - level, Color("#d8f0f4"), 0.9, 0.85, 0.55)
		plume(Vector3(at.x, level, at.z) + Vector3(0, 0, 0.7), 3.6, 1.8, Color("#cfe8ee"), 0.45, 0.08)
		mist(Vector3(at.x, level + 0.2, at.z + 2.2), Vector2(5, 3.5), Color("#cfe8ee"), 0.4)

func _place_tidal_flats() -> void:
	var level := float(look["liquid"]["level"])
	var wood := Color("#4a3c30")
	# Fish stakes march out over the flats; two boats lie where the tide left them.
	for row in range(3):
		var base := spot(-60.0 + row * 55.0, 3.0)
		var away := Vector3(base.x, 0, base.z).normalized()
		var along := Vector3(-away.z, 0, away.x)
		for n in range(9):
			var at := base + away * (n * 0.9) + along * sin(n * 0.7) * 0.5
			scn.stand("column", Vector3(at.x, level - 0.5, at.z), Vector3(0.09, 0.5 + lerpf(0.9, 1.8, tall_room(at.x, at.z)), 0.09), n * 1.0, wood, Color.BLACK, 0.0, 0.0, Vector2(sin(n * 2.0) * 0.12, cos(n * 1.3) * 0.12))
			if n > 0 and n % 2 == 0: scn.link(Vector3(at.x, level + 0.7, at.z), Vector3(at.x, level + 0.75, at.z) - away * 0.9, 0.02, Color("#8a8270"))
	for n in range(2):
		var at := spot(-135.0 + n * 250.0, 2.6)
		var f := frame(Vector3(at.x, maxf(at.y, level) + 0.02, at.z), n * 2.2 + 0.5, 1.15)
		f.basis = f.basis * Basis.from_euler(Vector3(0.0, 0.0, 0.32))
		boat(f, Color("#6a5a48"))

func _place_glacier_lake() -> void:
	var level := float(look["liquid"]["level"])
	var ice := Color("#bfe0f0")
	scatter(34, 0.8, 7.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y > level - 0.2: return
		scn.stand("slab%d" % (n % 3), Vector3(at.x, level - 0.1, at.z), Vector3(rng.randf_range(0.9, 2.4), rng.randf_range(0.22, 0.5), rng.randf_range(0.9, 2.0)), angle * 4.0, Color("#dcecf4"))
	)
	for n in range(9):
		var at := spot(-110.0 + n * 26.0, 3.2 + (n % 3) * 0.6, 0.2)
		scn.stand("spire%d" % (n % 3), at - Vector3(0, 0.2, 0), Vector3(1.6, 2.2 + (n % 4) * 0.7, 1.6), n * 1.3, ice, Color.BLACK, 0.08)

func _place_sunken_fleet() -> void:
	var level := float(look["liquid"]["level"])
	var wood := Color("#4f4234")
	var sail := Color("#8f9088")
	var spots := [[-52.0, 4.2, 0.5, 6.0], [-12.0, 6.0, -0.6, 5.0], [36.0, 4.6, 1.9, 5.5], [-118.0, 3.6, 2.5, 4.6], [150.0, 3.4, 0.2, 3.6]]
	for item in spots:
		var at := spot(float(item[0]), float(item[1]))
		var f := frame(Vector3(at.x, level - 0.35, at.z), float(item[2]), lerpf(0.55, 1.0, tall_room(at.x, at.z)))
		f.basis = f.basis * Basis.from_euler(Vector3(0.12, 0.0, 0.34))
		wreck(f, wood, sail, float(item[3]))
	for n in range(4):
		mist(Vector3(-10.0 + n * 7.0, level + 0.3, -RADIUS - 3.0 - (n % 2) * 3.0), Vector2(10, 4), Color("#8fa4ac"), 0.38)

func _place_geyser_mud() -> void:
	var level := float(look["liquid"]["level"])
	var mud := Color("#6a665e")
	for n in range(9):
		var at := spot(-150.0 + n * 38.0, 2.6 + (n % 3) * 1.5, 0.25)
		var size := 1.6 + (n % 3) * 0.7
		var y := maxf(at.y, level) - 0.1
		scn.stand("dome", Vector3(at.x, y, at.z), Vector3(size * 1.6, size * 0.5 * lerpf(0.7, 1.0, tall_room(at.x, at.z)), size * 1.6), n * 0.6, mud)
		scn.part("ring", Vector3(at.x, y + size * 0.24, at.z), Vector3(size * 0.6, size * 0.5, size * 0.6), mud.lightened(0.12))
		scn.part("cylinder", Vector3(at.x, y + size * 0.23, at.z), Vector3(size * 0.42, 0.04, size * 0.42), Color("#5fa8a8"), 0.25)
		plume(Vector3(at.x, y + size * 0.22, at.z), size * 0.9, lerpf(1.6, 4.2, tall_room(at.x, at.z)) * (1.0 + 0.3 * (n % 2)), Color("#d8dcd6"), 0.5, 0.09)

func _place_deep_trench() -> void:
	var level := float(look["liquid"]["level"])
	var rock := Color("#222c34")
	# Black smokers stand on the lip of the trench, their vents the only light out there.
	for n in range(10):
		var at := spot(-160.0 + n * 36.0, 2.4 + (n % 3) * 1.3, 0.22)
		var tall := lerpf(1.1, 3.6, tall_room(at.x, at.z)) * (0.8 + 0.3 * (n % 3))
		var y := maxf(at.y, level) - 0.3
		scn.stand("spire%d" % (n % 3), Vector3(at.x, y, at.z), Vector3(1.2, tall, 1.2), n * 1.1, rock, Color.BLACK, 0.0)
		scn.stand("crystal%d" % (n % 2), Vector3(at.x + 0.5, maxf(at.y, level) - 0.05, at.z + 0.3), Vector3(0.7, 0.8, 0.7), n * 2.0, Color("#3fd8cc"), Color.BLACK, 0.8)
		plume(Vector3(at.x, y + tall * 0.9, at.z), 1.0, 2.6, Color("#1c2a34"), 0.6, 0.06)
	# Ribs of something that fell in long ago.
	var spine := spot(-20.0, 4.6)
	for n in range(6):
		var f := frame(Vector3(spine.x + n * 0.9, level - 0.3, spine.z - n * 0.25), 0.4, 1.0)
		put(f, "arch", Vector3(0, 0, 0), Vector3(2.6 - absf(n - 2.5) * 0.3, 4.2 - absf(n - 2.5) * 0.5, 0.2), Color("#aab4b0"))
	light(Vector3(spine.x + 2.2, 1.2, spine.z), Color("#3fe0d0"), 1.1, 6.0)

func _place_maelstrom_sea() -> void:
	var level := float(look["liquid"]["level"])
	var rock := Color("#323c42")
	for n in range(12):
		var at := spot(-170.0 + n * 30.0, 2.0 + (n % 4) * 1.4, 0.22)
		scn.stand("spire%d" % (n % 3), Vector3(at.x, level - 0.5, at.z), Vector3(1.5, lerpf(1.0, 3.8, tall_room(at.x, at.z)) * (0.7 + 0.3 * (n % 3)), 1.5), n * 1.7, rock, Color.BLACK, 0.0, 0.0, Vector2(sin(n * 1.3) * 0.2, cos(n * 2.1) * 0.2))
	var at := spot(-64.0, 5.0)
	var f := frame(Vector3(at.x, level - 0.5, at.z), 1.2, 0.9)
	f.basis = f.basis * Basis.from_euler(Vector3(0.3, 0.0, 0.5))
	wreck(f, Color("#4a4036"), Color("#7f8684"), 5.0)

# ----- flame ---------------------------------------------------------------- #
func _dress_flame() -> void:
	var kit: Dictionary = look["kit"]
	var basalt: Color = kit["basalt"]
	var char_wood: Color = kit["char"]
	var ember := float(kit["ember"])
	var liquid: Dictionary = look["liquid"]
	var level := float(liquid.get("level", -9.0))
	# Lip of the field: basalt columns in steps, scorched boulders, burnt stumps.
	border(48, func(at: Vector3, angle: float, n: int) -> void:
		var y := maxf(at.y, level)
		if n % 3 == 0 and float(kit["columns"]) > 0.0:
			for k in range(3): scn.stand("column", Vector3(at.x, y - 0.25, at.z) + Vector3(cos(angle + k * 2.1), 0, sin(angle + k * 2.1)) * 0.22, Vector3(0.36, 0.25 + rng.randf_range(0.2, 0.7), 0.36), angle + k, basalt.lightened(0.04 * k))
		elif n % 3 == 2 and float(kit["trunks"]) > 0.0:
			scn.stand("dead%d" % (n % 2), Vector3(at.x, y, at.z), Vector3(0.9, rng.randf_range(0.7, 1.3) * lerpf(0.6, 1.0, tall_room(at.x, at.z)), 0.9), angle * 5.0, char_wood)
		else:
			scn.stand("rock%d" % (n % 4), Vector3(at.x, y - 0.06, at.z), Vector3(0.9, 0.7, 0.9) * rng.randf_range(0.7, 1.2), angle * 3.0, basalt, Color.BLACK, ember * 0.5 if n % 4 == 0 else 0.0)
	)
	scatter(int(48 * float(kit["columns"])), 0.9, 11.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		var room := tall_room(at.x, at.z)
		for k in range(4):
			var offset := Vector3(cos(angle * 3.0 + k * 1.6), 0, sin(angle * 3.0 + k * 1.6)) * 0.42
			scn.stand("column", Vector3(at.x, maxf(at.y, level) - 0.4, at.z) + offset, Vector3(0.52, 0.4 + lerpf(0.5, 2.6, room) * rng.randf_range(0.4, 1.0), 0.52), angle + k, basalt.lightened(0.03 * k))
	)
	scatter(int(54 * float(kit["trunks"])), 1.0, 12.5, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y < level: return
		scn.stand("dead%d" % (n % 2), at, Vector3(1.3, lerpf(1.0, 3.4, tall_room(at.x, at.z)) * rng.randf_range(0.7, 1.2), 1.3), angle * 5.0, char_wood, Color.BLACK, 0.0, 0.0, Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)))
		if n % 4 == 0: scn.link(at + Vector3(0.3, 0.12, 0.2), at + Vector3(cos(angle * 9.0) * 1.6, 0.14, sin(angle * 9.0) * 1.6), 0.2, char_wood.lightened(0.05), ember)
	)
	scatter(int(54 * float(kit["rocks"])), 1.0, 12.5, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		scn.stand("rock%d" % (n % 4), Vector3(at.x, maxf(at.y, level) - 0.12, at.z), Vector3(1.3, 1.0, 1.3) * rng.randf_range(0.7, 1.9), angle * 3.0, _vary(basalt.lightened(0.03 * (n % 3))), Color.BLACK, ember * rng.randf() * 0.6, 0.0, _lean(0.05))
	)
	scatter(int(40 * float(kit["shards"])), 1.0, 12.5, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		scn.stand("spire%d" % (n % 3), Vector3(at.x, maxf(at.y, level) - 0.15, at.z), Vector3(0.9, lerpf(0.8, 2.6 + 1.8 * harsh, tall_room(at.x, at.z)) * rng.randf_range(0.5, 1.2), 0.9), angle * 3.0, basalt, Color.BLACK,
			ember * rng.randf(), 0.0, Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)))
	)
	if has_method("_place_" + id): call("_place_" + id)

func _place_kiln_yard() -> void:
	var brick := Color("#8a5240")
	var spots := [[-62.0, 2.6, 1.25], [-24.0, 3.4, 1.5], [18.0, 2.8, 1.3], [58.0, 3.2, 1.2], [-112.0, 2.6, 1.1], [112.0, 2.6, 1.0]]
	for n in range(spots.size()):
		var item: Array = spots[n]
		var at := spot(float(item[0]), float(item[1]))
		kiln(frame(at, facing(at) + 0.2 * (n % 2), float(item[2]) * lerpf(0.6, 1.0, tall_room(at.x, at.z))), brick.darkened(0.06 * (n % 3)), 0.9, 0.45)
		var beside := at + Vector3(cos(n * 1.7) * 2.0, 0, sin(n * 1.7) * 1.4)
		beside.y = ground(beside.x, beside.z)
		stack(frame(beside, n * 0.9, 0.8), Color("#7a5a3c"), 3, Vector3(0.9, 0.28, 0.3))
	for n in range(10):
		var at := spot(-150.0 + n * 33.0, 1.4 + (n % 3) * 0.5, 0.2)
		scn.part("sphere", at + Vector3(0, 0.2, 0), Vector3(0.42, 0.44, 0.42), Color("#9a6a4a").darkened(0.1 * (n % 3)))
		scn.part("cylinder", at + Vector3(0, 0.42, 0), Vector3(0.22, 0.08, 0.22), Color("#6a4632"))
	light(spot(-24.0, 2.0) + Vector3(0, 1.0, 0), Color("#ff9a4a"), 1.0, 5.0)

func _place_burn_field() -> void:
	# Stubble still burning in the furrows, fence lines and smoke along the horizon.
	scatter(70, 0.8, 10.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		scn.stand("tuft", at, Vector3(0.7, rng.randf_range(0.3, 0.55), 0.7), angle * 3.0, Color("#ff8a2a") if n % 3 == 0 else Color("#3a2c20"), Color("#3a2c20"), 0.8 if n % 3 == 0 else 0.0, 0.2)
	)
	for n in range(7):
		var at := spot(-130.0 + n * 44.0, 5.0 + (n % 3) * 1.6, 0.1)
		plume(at, 2.4, lerpf(2.0, 5.0, tall_room(at.x, at.z)), Color("#6a5a50"), 0.5, 0.045)
		haze_floor(at + Vector3(0, 0.08, 0), Vector2(3.4, 2.4), n * 0.7, Color("#ff7a22"), 0.0, 0.04, 4, 0.9)
		for k in range(5):
			var flame := at + Vector3(cos(k * 1.3 + n) * 0.6, 0, sin(k * 1.3 + n) * 0.5)
			scn.stand("tuft", flame, Vector3(0.7, 0.6 + 0.2 * (k % 3), 0.7), k * 1.1, Color("#ffa23a"), Color("#ff6a1c"), 0.9, 0.3)
	for n in range(4):
		var from := spot(-150.0 + n * 78.0, 1.6)
		var to := spot(-150.0 + n * 78.0 + 30.0, 2.4)
		fence(from, to, Color("#3a2e26"), 6)

func _place_forge_canyon() -> void:
	# Hearths cut into the canyon wall, anvils and quench troughs before them.
	for n in range(5):
		var angle := clear_angle(deg_to_rad(-90.0 + (n - 2) * 33.0), 0.28, 0.25)
		var at := at_ground(cos(angle) * (RADIUS + 2.0), sin(angle) * (RADIUS + 2.0))
		var f := frame(Vector3(at.x, 0.0, at.z), facing(at), 1.2)
		put(f, "arch", Vector3(0, 0, 0), Vector3(1.9, 3.0, 0.9), Color("#4a3a36"))
		put(f, "box", Vector3(0, 0.6, -0.1), Vector3(1.2, 1.1, 0.5), Color("#ff8a2e"), 0.9)
		put(f, "box", Vector3(0, 0.12, 0.3), Vector3(1.5, 0.24, 0.5), Color("#2a2424"))
		put(f, "cylinder", Vector3(0, 2.0, -0.2), Vector3(0.5, 1.4, 0.5), Color("#3a2e2c"))
		put(f, "box", Vector3(1.3, 0.3, 1.2), Vector3(0.4, 0.6, 0.4), Color("#5a4a3c"))
		put(f, "box", Vector3(1.3, 0.68, 1.2), Vector3(0.7, 0.18, 0.3), Color("#2a2a30"))
		put(f, "box", Vector3(-1.4, 0.2, 1.3), Vector3(0.6, 0.4, 1.1), Color("#3a3230"))
		put(f, "box", Vector3(-1.4, 0.41, 1.3), Vector3(0.46, 0.02, 0.95), Color("#2a5a6a"))
		plume(f * Vector3(0, 2.7, -0.2), 1.3, 2.6, Color("#5a4c48"), 0.45)
		if n % 2 == 0: light(f * Vector3(0, 0.9, 0.8), Color("#ff8a3a"), 1.2, 4.6)

func _place_burnt_forest() -> void:
	for n in range(6):
		var at := spot(-140.0 + n * 52.0, 2.4 + (n % 2) * 2.0, 0.1)
		mist(at + Vector3(0, 0.4, 0), Vector2(9, 4.5), Color("#6a6260"), 0.4, n * 0.8)
	for n in range(8):
		var at := spot(-160.0 + n * 44.0, 1.6 + (n % 3) * 0.7, 0.2)
		scn.part("cylinder", at + Vector3(0, 0.22, 0), Vector3(0.5, 0.44, 0.5), Color("#1c1816"))
		scn.part("cylinder", at + Vector3(0, 0.45, 0), Vector3(0.36, 0.03, 0.36), Color("#ff6a1c"), 0.8)

func _place_sulfur_springs() -> void:
	var level := float(look["liquid"]["level"])
	for n in range(9):
		var at := spot(-150.0 + n * 37.0, 2.2 + (n % 3) * 1.6, 0.15)
		plume(Vector3(at.x, maxf(at.y, level), at.z), 1.6, lerpf(1.6, 4.0, tall_room(at.x, at.z)), Color("#f0f0d8"), 0.42, 0.07)
	for n in range(14):
		var at := spot(-170.0 + n * 26.0, 1.3 + (n % 4) * 0.8, 0.12)
		scn.stand("dome", Vector3(at.x, maxf(at.y, level) - 0.05, at.z), Vector3(1.0 + (n % 3) * 0.5, 0.3, 0.9 + (n % 2) * 0.5), n * 0.7, Color("#d8cc7a"))

func _place_ash_city() -> void:
	var stone := Color("#6a6468")
	for n in range(7):
		var at := spot(-100.0 + n * 34.0, 2.6 + (n % 2) * 1.0, 0.24)
		var f := frame(at, facing(at) + 0.1 * (n % 3), lerpf(0.6, 1.1, tall_room(at.x, at.z)))
		match n % 3:
			0: rampart(f, stone, 3.0, 2.2, 0.5)
			1: span(f, stone.darkened(0.05), 2.4, 2.6, n % 2 == 0)
			_:
				pillar(f, stone, 2.6, false)
				pillar(frame(at + Vector3(1.6, 0, 0.4), 0.3, f.basis.get_scale().x), stone, 2.6, true)
	for n in range(8):
		var at := spot(-160.0 + n * 45.0, 1.5 + (n % 3) * 0.6, 0.2)
		scn.stand("slab%d" % (n % 3), at - Vector3(0, 0.1, 0), Vector3(1.3, 0.4, 1.0), n * 1.2, stone.darkened(0.1), Color.BLACK, 0.0, 0.0, Vector2(0.25, 0.1))

func _place_lava_river() -> void:
	var level := float(look["liquid"]["level"])
	for n in range(4):
		var at := spot(-120.0 + n * 78.0, 6.5)
		plume(Vector3(at.x, level, at.z), 2.6, lerpf(2.4, 5.0, tall_room(at.x, at.z)), Color("#3a2a28"), 0.5, 0.04)
	light(Vector3(-7.0, 0.8, -RADIUS - 2.5), Color("#ff6a2a"), 1.3, 7.0)
	light(Vector3(RADIUS + 1.5, 0.8, 5.0), Color("#ff6a2a"), 1.1, 6.0)

func _place_obsidian_flats() -> void:
	for n in range(7):
		var at := spot(-150.0 + n * 50.0, 6.0 + (n % 2) * 2.0, 0.1)
		plume(at, 3.0, lerpf(2.2, 5.5, tall_room(at.x, at.z)), Color("#b8b4c4"), 0.4, 0.05)
	for n in range(6):
		var at := spot(-120.0 + n * 48.0, 2.2, 0.2)
		scn.stand("crystal%d" % (n % 2), at - Vector3(0, 0.1, 0), Vector3(1.6, lerpf(1.2, 2.6, tall_room(at.x, at.z)), 1.6), n * 1.3, Color("#1c1822"), Color.BLACK, 0.0)

func _place_volcano_crater() -> void:
	var level := float(look["liquid"]["level"])
	# Lava pours down the crater wall into the lake on the far side.
	for n in range(4):
		var angle := clear_angle(deg_to_rad(-90.0 + (n - 1.5) * 38.0), 0.28, 0.25)
		var top := ground(cos(angle) * (RADIUS + 4.6), sin(angle) * (RADIUS + 4.6))
		if top < 1.5: continue
		var at := Vector3(cos(angle) * (RADIUS + 3.5), top, sin(angle) * (RADIUS + 3.5))
		fall(at, 1.3 + (n % 2) * 0.6, top - level, Color("#ff7a1e"), 0.0, 1.0, 0.16)
		haze_floor(Vector3(at.x, level + 0.05, at.z + 1.2), Vector2(4.0, 3.0), 0.0, Color("#ffb04a"), 0.0, 0.03, 4, 0.5)
	light(Vector3(-6.0, 1.0, -RADIUS - 2.0), Color("#ff5a1e"), 1.5, 8.0)
	light(Vector3(RADIUS + 1.5, 1.0, 3.0), Color("#ff5a1e"), 1.3, 7.0)
	for n in range(5):
		var at := spot(-150.0 + n * 60.0, 7.0, 0.1)
		plume(Vector3(at.x, maxf(at.y, level), at.z), 3.0, lerpf(2.6, 6.0, tall_room(at.x, at.z)), Color("#2a1c1a"), 0.55, 0.05)

func _place_ash_blizzard() -> void:
	for n in range(8):
		var at := spot(-160.0 + n * 45.0, 3.0 + (n % 3) * 2.0, 0.1)
		mist(at + Vector3(0, 0.5, 0), Vector2(11, 5), Color("#8a848a"), 0.45, n * 0.6)
	light(Vector3(0.0, 2.5, -RADIUS - 6.0), Color("#ff5a2a"), 1.4, 12.0)

# ----- rock ----------------------------------------------------------------- #
func _dress_rock() -> void:
	var kit: Dictionary = look["kit"]
	var stone: Color = kit["stone"]
	var rust: Color = kit["rust"]
	var dry: Color = kit["dry"]
	var floor_level := float(look["liquid"].get("level", -99.0))
	border(52, func(at: Vector3, angle: float, n: int) -> void:
		if at.y < -0.6: return
		if n % 3 == 2 and float(kit["scrub"]) > 0.0: scn.stand("tuft", at, Vector3(0.8, rng.randf_range(0.35, 0.55), 0.8), angle, dry, dry, 0.0, 0.05)
		else: scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.06, 0), Vector3(0.9, 0.75, 0.9) * rng.randf_range(0.7, 1.5), angle * 3.0, [stone, rust][n % 2])
	)
	scatter(int(62 * float(kit["rocks"])), 0.9, 12.5, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y < floor_level: return
		scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.12, 0), Vector3(1.4, 1.1, 1.4) * rng.randf_range(0.7, 2.1), angle * 3.0, _vary([stone, rust, stone.darkened(0.1)][n % 3]), Color.BLACK, 0.0, 0.0, _lean(0.05))
	)
	scatter(int(28 * float(kit["hoodoos"])), 1.2, 12.5, func(at: Vector3, angle: float, d: float, n: int) -> void:
		if at.y < floor_level: return
		var tall := lerpf(0.9, 3.0 + d * 0.35, tall_room(at.x, at.z)) * rng.randf_range(0.6, 1.2)
		scn.stand("hoodoo%d" % (n % 2), at - Vector3(0, 0.15, 0), Vector3(1.0 + tall * 0.34, tall, 1.0 + tall * 0.34), angle * 3.0, [stone, rust][n % 2])
	)
	scatter(int(54 * float(kit["scrub"])), 0.8, 11.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y < floor_level: return
		if n % 3 == 0: scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.05, 0), Vector3(0.9, 0.6, 0.9) * rng.randf_range(0.6, 1.1), angle * 3.0, dry.darkened(0.1))
		else: scn.stand("tuft", at, Vector3(1.0, rng.randf_range(0.4, 0.7), 1.0), angle, dry, dry, 0.0, 0.06)
	)
	scatter(int(32 * float(kit["trees"])), 1.2, 11.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y < floor_level: return
		scn.stand("dead%d" % (n % 2), at, Vector3(1.1, lerpf(0.9, 2.3, tall_room(at.x, at.z)) * rng.randf_range(0.8, 1.2), 1.1), angle * 5.0, kit["wood"])
	)
	if has_method("_place_" + id): call("_place_" + id)

## Stone piers under an approach that crosses a drop (a summit, a rift).
func _viaduct(deep: float, stone: Color) -> void:
	var reach := float(look["approach"])
	for gate in land.gates:
		var out := Vector3(gate.x, 0, gate.y)
		var across := Vector3(-gate.y, 0, gate.x)
		var yaw := atan2(-gate.x, -gate.y)
		for step in range(1, int(reach / 1.5) + 1):
			var at := out * (RADIUS + step * 1.5 - 0.4)
			scn.part("stone", at + Vector3(0, -deep * 0.5 - 0.02, 0), Vector3(HALF_ROAD * 2.0 + 0.1, deep, 0.5), stone.darkened(0.1 + 0.03 * (step % 2)), 0.0, Vector3(0, yaw, 0))
		scn.part("box", out * (RADIUS + reach * 0.5) + Vector3(0, -0.12, 0), Vector3(HALF_ROAD * 2.0 + 0.2, 0.24, reach), stone.darkened(0.06), 0.0, Vector3(0, yaw, 0))
		for side: float in [-1.0, 1.0]:
			scn.stand("spire0", out * (RADIUS + reach) + across * side * (HALF_ROAD + 0.1) - Vector3(0, 0.2, 0), Vector3(0.5, 1.3, 0.5), yaw + side, stone)

func _place_gravel_hills() -> void:
	var stone := Color("#8a8276")
	for n in range(6):
		var at := spot(-150.0 + n * 58.0, 2.4 + (n % 2) * 1.4)
		cairn(at, stone, 3 + n % 3)
	for n in range(3):
		var from := spot(-100.0 + n * 80.0, 1.8)
		fence(from, spot(-100.0 + n * 80.0 + 26.0, 2.6), Color("#5a4c3e"), 5)

func _place_stone_terraces() -> void:
	# Field walls, hay and two small barns up on the terraces.
	for n in range(12):
		var at := spot(-170.0 + n * 30.0, 1.5 + (n % 3) * 0.9, 0.16)
		scn.stand("dome", at - Vector3(0, 0.02, 0), Vector3(0.9, 1.3 * lerpf(0.6, 1.0, tall_room(at.x, at.z)), 0.9), n * 0.7, Color("#c8a85a"))
	for n in range(3):
		var at := spot(-60.0 + n * 58.0, 4.2)
		hut(frame(at, facing(at) + 0.2, 1.0), Color("#8a8072"), Color("#5a4a3a"), 0.6, true)
	for n in range(26):
		var angle := TAU * float(n) / 26.0
		if land.gate_near(angle, 0.22): continue
		var at := at_ground(cos(angle) * (RADIUS + 1.15), sin(angle) * (RADIUS + 1.15))
		scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.1, 0), Vector3(1.5, 0.75, 0.8), -angle, Color("#8a8476").darkened(0.05 * (n % 3)))

func _place_quarry_pit() -> void:
	var stone := Color("#d2cab8")
	var wood := Color("#6a543e")
	for n in range(8):
		var at := spot(-150.0 + n * 42.0, 1.9 + (n % 3) * 0.7, 0.2)
		stack(frame(at, facing(at) + n * 0.5, lerpf(0.7, 1.15, tall_room(at.x, at.z))), stone.darkened(0.04 * (n % 3)), 2 + n % 2, Vector3(0.9, 0.6, 0.7))
	for n in range(3):
		# A shear-leg crane on a ledge: two legs, a boom and the block it lifts.
		var at := spot(-58.0 + n * 56.0, 3.4)
		var f := frame(at, facing(at) + 0.3 * (n - 1), lerpf(0.75, 1.1, tall_room(at.x, at.z)))
		put_link(f, Vector3(-0.8, 0, 0.5), Vector3(0, 3.2, 0), 0.13, wood)
		put_link(f, Vector3(0.8, 0, 0.5), Vector3(0, 3.2, 0), 0.13, wood)
		put_link(f, Vector3(0, 0, -1.2), Vector3(0, 3.2, 0), 0.10, wood.darkened(0.1))
		put_link(f, Vector3(0, 3.2, 0), Vector3(0, 3.6, 1.9), 0.11, wood)
		put_link(f, Vector3(0, 3.6, 1.9), Vector3(0, 1.3, 1.9), 0.025, Color("#3a3028"))
		put(f, "stone", Vector3(0, 0.95, 1.9), Vector3(0.9, 0.7, 0.8), stone)
	for n in range(4):
		var at := spot(-110.0 + n * 72.0, 2.6)
		timber_frame(frame(at, facing(at), 0.9), wood, 2.0, 1.6, false)

func _place_red_canyon() -> void:
	for n in range(3):
		var at := spot(-64.0 + n * 62.0, 5.0)
		# A natural arch spanning two buttes.
		var f := frame(at, facing(at) + 0.3 * (n - 1), 1.3)
		put(f, "hoodoo0", Vector3(-1.9, -0.2, 0), Vector3(1.6, 3.2, 1.6), Color("#a8603e"))
		put(f, "hoodoo1", Vector3(1.9, -0.2, 0), Vector3(1.5, 2.9, 1.5), Color("#9a5234"))
		put(f, "arch", Vector3(0, 1.9, 0), Vector3(4.6, 1.6, 0.9), Color("#b46a44"))

func _place_broken_wall() -> void:
	var stone := Color("#807c78")
	# The curtain wall runs behind the field; a gate tower still stands at each end.
	for n in range(-4, 5):
		var angle := deg_to_rad(-90.0 + n * 15.0)
		if land.gate_near(angle, 0.2): continue
		var at := at_ground(cos(angle) * (RADIUS + 3.0), sin(angle) * (RADIUS + 3.0))
		rampart(frame(at, facing(at), 1.15), stone.darkened(0.04 * (absi(n) % 2)), 3.4, 2.3 if absi(n) % 3 != 1 else 1.3, 0.25 + 0.5 * float(absi(n) % 3 == 1))
	for side: float in [-1.0, 1.0]:
		var at := spot(side * 72.0, 3.3)
		tower(frame(at, facing(at), 1.1 * lerpf(0.7, 1.0, tall_room(at.x, at.z))), stone.lightened(0.04), Color(look["lamp"]), 3.6)
		scn.part("box", at + Vector3(0.9, 3.0, 0.9), Vector3(0.06, 1.4, 0.5), Color("#8a3030"))
	for n in range(9):
		var at := spot(-160.0 + n * 40.0, 1.5 + (n % 3) * 0.6, 0.2)
		scn.stand("slab%d" % (n % 3), at - Vector3(0, 0.05, 0), Vector3(1.1, 0.5, 0.9), n * 1.4, stone.darkened(0.12), Color.BLACK, 0.0, 0.0, Vector2(0.2, 0.15))

func _place_crystal_cavern() -> void:
	var crystal := Color("#a67cf2")
	for n in range(14):
		var at := spot(-170.0 + n * 26.0, 1.5 + (n % 4) * 0.9, 0.16)
		var size := lerpf(1.0, 2.8, tall_room(at.x, at.z)) * (0.7 + 0.3 * (n % 3))
		scn.stand("crystal%d" % (n % 2), at - Vector3(0, 0.1, 0), Vector3(size * 0.9, size, size * 0.9), n * 1.7, crystal.lerp(Color("#6ab8ff"), 0.3 * (n % 3)), Color.BLACK, 0.42)
	for n in range(22):
		var at := spot(-175.0 + n * 16.5, 2.2 + (n % 5) * 0.8, 0.12)
		scn.stand("spire%d" % (n % 3), at - Vector3(0, 0.1, 0), Vector3(0.9, lerpf(0.8, 3.4, tall_room(at.x, at.z)) * (0.6 + 0.4 * (n % 2)), 0.9), n * 1.1, Color("#34364e"))
	light(spot(-52.0, 2.2) + Vector3(0, 1.4, 0), Color("#a070ff"), 1.5, 7.0)
	light(spot(48.0, 2.2) + Vector3(0, 1.4, 0), Color("#7aa0ff"), 1.3, 7.0)

func _place_desert_mesa() -> void:
	for n in range(6):
		var at := spot(-150.0 + n * 60.0, 3.0 + (n % 2) * 1.5)
		scn.stand("dead%d" % (n % 2), at, Vector3(1.0, lerpf(1.0, 2.0, tall_room(at.x, at.z)), 1.0), n * 1.9, Color("#6a5238"))
	for n in range(5):
		var at := spot(-120.0 + n * 60.0, 6.0)
		plume(at, 4.0, lerpf(1.8, 3.6, tall_room(at.x, at.z)), Color("#d8b888"), 0.3, 0.06)

func _place_iron_mine() -> void:
	var wood := Color("#6a5038")
	for n in range(5):
		# Adits in the wall behind the field, each with its own lamp and a waiting cart.
		var angle := clear_angle(deg_to_rad(-90.0 + (n - 2) * 34.0), 0.28, 0.25)
		var at := at_ground(cos(angle) * (RADIUS + 2.0), sin(angle) * (RADIUS + 2.0))
		var f := frame(Vector3(at.x, 0.0, at.z), facing(at), 1.2)
		timber_frame(f, wood, 2.0, 2.1, true)
		put(f, "box", Vector3(0.75, 1.5, 0.2), Vector3(0.2, 0.26, 0.2), Color(look["lamp"]), 0.9)
		cart(frame(f * Vector3(0.2, 0.0, 1.5), facing(at) + 0.2, 1.0), wood.darkened(0.1), Color("#7a4630"))
		if n % 2 == 0: light(f * Vector3(0, 1.4, 1.0), Color("#ffa85a"), 1.1, 4.5)
	for n in range(8):
		var at := spot(-160.0 + n * 45.0, 1.6 + (n % 3) * 0.7, 0.2)
		for k in range(3): scn.stand("rock%d" % ((n + k) % 4), at + Vector3(k * 0.5 - 0.5, -0.1, (k % 2) * 0.4), Vector3(0.9, 0.7 + 0.2 * k, 0.9), n + k * 1.0, Color("#8a4e34").darkened(0.08 * k))
	for n in range(4):
		var at := spot(-130.0 + n * 86.0, 3.0)
		timber_frame(frame(at, facing(at) + 0.5, 0.9), wood, 1.8, 2.6, false)

func _place_peak_cliffs() -> void:
	var stone := Color("#6a7480")
	_viaduct(4.0, stone)
	for n in range(18):
		var at := spot(-175.0 + n * 20.0, 1.6 + (n % 5) * 1.5, 0.1)
		scn.stand("spire%d" % (n % 3), Vector3(at.x, -3.4, at.z), Vector3(2.4 + (n % 3) * 0.8, 3.6 + lerpf(0.6, 4.6, tall_room(at.x, at.z)) * (0.5 + 0.5 * (n % 2)), 2.4 + (n % 2) * 0.8), n * 1.3, stone.darkened(0.06 * (n % 3)))
	for n in range(6):
		var at := spot(-150.0 + n * 60.0, 5.0 + (n % 2) * 3.0, 0.0)
		mist(Vector3(at.x, -2.0, at.z), Vector2(14, 7), Color("#ffe0c8"), 0.5, n * 0.9)

func _place_rift_chasm() -> void:
	var stone := Color("#6a5846")
	_viaduct(4.5, stone)
	# Slabs heaved up along the lip, dust rising out of the rift.
	for n in range(16):
		var at := spot(-170.0 + n * 22.5, 3.0 + (n % 3) * 0.7, 0.16)
		scn.stand("slab%d" % (n % 3), at - Vector3(0, 0.5, 0), Vector3(2.4, lerpf(0.6, 1.6, tall_room(at.x, at.z)), 1.8), n * 1.3, stone.darkened(0.05 * (n % 3)), Color.BLACK, 0.0, 0.0, Vector2(sin(n * 1.7) * 0.45, cos(n * 2.3) * 0.45))
	for n in range(7):
		var angle := deg_to_rad(-90.0 + (n - 3) * 50.0)
		var at := Vector3(cos(angle) * (RADIUS + 1.2), -1.5, sin(angle) * (RADIUS + 1.2))
		plume(at, 2.6, lerpf(2.2, 4.6, tall_room(at.x, at.z)), Color("#8a6e58"), 0.42, 0.05)
	light(Vector3(-RADIUS - 1.2, -0.8, -3.0), Color("#ff6a2a"), 1.2, 6.0)
	light(Vector3(4.0, -0.8, -RADIUS - 1.2), Color("#ff6a2a"), 1.2, 6.0)

# ----- frost ---------------------------------------------------------------- #
func _dress_frost() -> void:
	var kit: Dictionary = look["kit"]
	var ice: Color = kit["ice"]
	var needle: Color = kit["needle"]
	var bark: Color = kit["bark"]
	var stone: Color = kit["stone"]
	var snow: Color = kit["snow"]
	var level := float(look["liquid"].get("level", -99.0))
	border(48, func(at: Vector3, angle: float, n: int) -> void:
		if at.y < level - 0.05: return
		if n % 3 == 0: scn.stand("dome", at - Vector3(0, 0.05, 0), Vector3(1.3, rng.randf_range(0.5, 0.9), 1.1), angle, snow)
		elif n % 3 == 1: scn.stand("spire%d" % (n % 3), at - Vector3(0, 0.05, 0), Vector3(0.36, rng.randf_range(0.4, 0.9), 0.36), angle * 3.0, ice, Color.BLACK, 0.08, 0.0, Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25)))
		else: scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.08, 0), Vector3(0.9, 0.7, 0.9) * rng.randf_range(0.7, 1.3), angle * 3.0, stone)
	)
	scatter(int(110 * float(kit["firs"])), 1.2, 13.0, func(at: Vector3, angle: float, d: float, n: int) -> void:
		if at.y < level: return
		var size := lerpf(1.6, 3.6, clampf((d - 1.0) / 7.0, 0.0, 1.0)) * lerpf(0.45, 1.0, tall_room(at.x, at.z)) * rng.randf_range(0.75, 1.3)
		scn.stand("fir%d" % (n % 3), at, Vector3(size * 0.62, size, size * 0.62), angle * 7.0, _vary(needle.darkened(0.06 * (n % 3))), bark, 0.0, 0.03, _lean())
	)
	scatter(int(48 * float(kit["spires"])), 1.0, 13.0, func(at: Vector3, angle: float, d: float, n: int) -> void:
		var tall := lerpf(0.9, 2.6 + 2.6 * harsh + d * 0.12, tall_room(at.x, at.z)) * rng.randf_range(0.5, 1.25)
		scn.stand("spire%d" % (n % 3), Vector3(at.x, maxf(at.y, level) - 0.15, at.z), Vector3(0.5 + tall * 0.3, tall, 0.5 + tall * 0.3), angle * 3.0, ice.darkened(0.05 * (n % 3)), Color.BLACK, 0.05 + 0.12 * harsh,
			0.0, Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)))
	)
	scatter(int(48 * float(kit["rocks"])), 1.0, 12.5, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y < level: return
		scn.stand("rock%d" % (n % 4), at - Vector3(0, 0.12, 0), Vector3(1.4, 1.0, 1.4) * rng.randf_range(0.7, 1.8), angle * 3.0, _vary(stone.darkened(0.06 * (n % 2))), Color.BLACK, 0.0, 0.0, _lean(0.05))
	)
	scatter(int(38 * float(kit["mounds"])), 0.9, 11.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y < level: return
		scn.stand("dome", at - Vector3(0, 0.1, 0), Vector3(rng.randf_range(1.6, 3.4), rng.randf_range(0.5, 1.1) * lerpf(0.6, 1.0, tall_room(at.x, at.z)), rng.randf_range(1.4, 2.6)), angle * 2.0, snow)
	)
	scatter(int(36 * float(kit["bare"])), 1.2, 11.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y < level: return
		scn.stand("dead%d" % (n % 2), at, Vector3(1.2, lerpf(1.0, 2.8, tall_room(at.x, at.z)) * rng.randf_range(0.8, 1.2), 1.2), angle * 5.0, bark.lightened(0.08), Color.BLACK, 0.0, 0.0, _lean(0.08))
	)
	if has_method("_place_" + id): call("_place_" + id)

## Curtain of aurora hanging over the far side.
func aurora(degrees: float, d: float, width: float, color: Color, strength: float = 0.7) -> void:
	var angle := deg_to_rad(degrees - 90.0)
	haze_quad(Vector3(cos(angle) * (RADIUS + d), 0.8, sin(angle) * (RADIUS + d)), width, 7.5, color, 0.0, 0.006, 2, strength)

func _place_first_snow_hills() -> void:
	for n in range(4):
		var from := spot(-130.0 + n * 76.0, 1.8)
		fence(from, spot(-130.0 + n * 76.0 + 28.0, 2.5), Color("#5a4a3c"), 6)
	for n in range(5):
		var at := spot(-120.0 + n * 60.0, 3.4)
		scn.stand("dome", at - Vector3(0, 0.02, 0), Vector3(1.1, 1.5 * lerpf(0.6, 1.0, tall_room(at.x, at.z)), 1.1), n * 0.9, Color("#b89a58"))

func _place_frozen_pond() -> void:
	var straw := Color("#b8a878")
	border(26, func(at: Vector3, angle: float, n: int) -> void:
		scn.stand("reed", at, Vector3(1.0, rng.randf_range(0.8, 1.3), 1.0), angle * 4.0, straw, Color("#8a6a48"), 0.0, 0.05)
	, 0.75)
	# An ice-fishing shelter and its sledge on the bank.
	var at := spot(-42.0, 3.0)
	hut(frame(at, facing(at) + 0.3, 0.95), Color("#6f5a46"), Color("#4a5a6a"), 0.85, true)
	plume(at + Vector3(0.45, 1.7, -0.2), 0.8, 2.4, Color("#c8d0d8"), 0.4)
	light(at + Vector3(0.6, 0.8, 1.0), look["lamp"], 0.9, 3.6)
	var sledge := frame(at + Vector3(2.0, 0.05, 1.2), 0.8)
	put(sledge, "box", Vector3(0, 0.16, 0), Vector3(0.6, 0.06, 1.3), Color("#7a5a3c"))
	for side: float in [-1.0, 1.0]: put(sledge, "box", Vector3(side * 0.27, 0.06, 0), Vector3(0.05, 0.1, 1.5), Color("#5a4230"))

func _place_snowed_village() -> void:
	var wall := Color("#6f5a48")
	var roof := Color("#4a4250")
	var spots := [[-66.0, 2.8], [-40.0, 4.2], [-14.0, 3.0], [14.0, 4.4], [42.0, 2.9], [68.0, 3.8], [-112.0, 2.6], [112.0, 2.6]]
	for n in range(spots.size()):
		var item: Array = spots[n]
		var at := spot(float(item[0]), float(item[1]))
		var f := frame(at, facing(at) + 0.25 * ((n % 3) - 1), lerpf(0.62, 1.1, tall_room(at.x, at.z)))
		hut(f, wall.darkened(0.06 * (n % 3)), roof, 0.9, true)
		plume(f * Vector3(0.45, 1.75, -0.2), 0.8, 2.6, Color("#c8d0dc"), 0.42, 0.06)
		if n in [1, 4]: light(f * Vector3(0, 0.9, 1.3), look["lamp"], 1.0, 4.4)
	# The well in the square and the fences between the plots.
	var well := spot(-2.0, 1.9)
	scn.part("cylinder", well + Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 1.0), Color("#7a8494"))
	for side: float in [-1.0, 1.0]: scn.part("box", well + Vector3(side * 0.4, 0.9, 0), Vector3(0.1, 1.2, 0.1), Color("#5a4636"))
	scn.part("pyramid", well + Vector3(0, 1.5, 0), Vector3(1.4, 0.5, 1.2), roof)
	for n in range(4):
		var from := spot(-150.0 + n * 84.0, 1.7)
		fence(from, spot(-150.0 + n * 84.0 + 24.0, 2.2), Color("#5a4a3c"), 5)

func _place_frost_gorge() -> void:
	# Frozen falls hang on the gorge wall.
	for n in range(4):
		var angle := clear_angle(deg_to_rad(-90.0 + (n - 1.5) * 36.0), 0.28, 0.25)
		var top := ground(cos(angle) * (RADIUS + 3.4), sin(angle) * (RADIUS + 3.4))
		if top < 1.4: continue
		var at := Vector3(cos(angle) * (RADIUS + 1.9), 0.0, sin(angle) * (RADIUS + 1.9))
		for k in range(5):
			var hang := at + Vector3(cos(angle + PI * 0.5), 0, sin(angle + PI * 0.5)) * (k - 2) * 0.42
			scn.stand("spire%d" % (k % 3), hang + Vector3(0, top * 0.92, 0), Vector3(0.5, top * rng.randf_range(0.5, 0.9), 0.5), k * 1.0, Color("#bfe2f6"), Color.BLACK, 0.12, 0.0, Vector2(PI, 0.0))

func _place_drift_ice_sea() -> void:
	var level := float(look["liquid"]["level"])
	scatter(46, 0.7, 9.0, func(at: Vector3, angle: float, _d: float, n: int) -> void:
		if at.y > level - 0.25: return
		scn.stand("slab%d" % (n % 3), Vector3(at.x, level - 0.16, at.z), Vector3(rng.randf_range(1.2, 3.2), rng.randf_range(0.3, 0.6), rng.randf_range(1.0, 2.6)), angle * 4.0, Color("#c4d8e8"))
	)
	for gate in land.gates: _jetty_plain(gate, level, Color("#3f3228"))
	var at := spot(-36.0, 4.0)
	var f := frame(Vector3(at.x, level - 0.3, at.z), 0.7, 0.9)
	f.basis = f.basis * Basis.from_euler(Vector3(0.1, 0.0, 0.28))
	wreck(f, Color("#4a4038"), Color("#a8b4c0"), 4.6)

## Plain posts under a boardwalk that crosses water outside the aqua biome.
func _jetty_plain(direction: Vector2, level: float, wood: Color) -> void:
	var out := Vector3(direction.x, 0, direction.y)
	var across := Vector3(-direction.y, 0, direction.x)
	var reach := float(look["approach"])
	for step in range(1, int(reach / 1.3) + 1):
		for side: float in [-1.0, 1.0]:
			var at := out * (RADIUS + step * 1.3) + across * (HALF_ROAD + 0.06) * side
			scn.stand("column", Vector3(at.x, level - 0.6, at.z), Vector3(0.2, 0.95, 0.2), step * 1.0, wood)

func _place_icicle_cave() -> void:
	var ice := Color("#9ad0f4")
	# The cave mouth behind the field: ribs of ice with icicles hanging from them.
	for n in range(5):
		var at := spot(-56.0 + n * 28.0, 2.6)
		var f := frame(Vector3(at.x, 0.0, at.z), facing(at), 1.25)
		put(f, "arch", Vector3(0, 0, 0), Vector3(4.4, 6.4, 0.7), ice.darkened(0.15), 0.1)
		for k in range(7):
			var x := (k - 3) * 0.48
			put(f, "spire%d" % (k % 3), Vector3(x, 2.55 - absf(x) * 0.52, 0.1), Vector3(0.26, 0.7 + (k % 3) * 0.3, 0.26), ice, 0.22, Vector3(PI, 0, 0))
	for n in range(8):
		var at := spot(-160.0 + n * 45.0, 1.8 + (n % 3) * 0.8, 0.2)
		scn.stand("crystal%d" % (n % 2), at - Vector3(0, 0.1, 0), Vector3(1.3, lerpf(1.0, 2.2, tall_room(at.x, at.z)), 1.3), n * 1.9, Color("#6ad0ff"), Color.BLACK, 0.4)
	light(spot(-40.0, 2.0) + Vector3(0, 1.4, 0), Color("#5ac8ff"), 1.3, 7.0)
	light(spot(44.0, 2.0) + Vector3(0, 1.4, 0), Color("#7aa8ff"), 1.2, 7.0)

func _place_blizzard_plateau() -> void:
	for n in range(9):
		var at := spot(-170.0 + n * 42.0, 2.4 + (n % 3) * 2.2, 0.08)
		haze_floor(at + Vector3(0, 0.5, 0), Vector2(13, 5.5), n * 0.7, Color("#ffffff"), 0.35, 0.02, 4, 0.5)
	for n in range(7):
		var at := spot(-150.0 + n * 50.0, 2.0 + (n % 2) * 1.2)
		cairn(at, Color("#6a7a8e"), 3 + n % 3)
	for n in range(3):
		var at := spot(-70.0 + n * 70.0, 3.6)
		scn.part("box", at + Vector3(0, 1.1, 0), Vector3(0.12, 2.2, 0.12), Color("#4a4038"), 0.0, Vector3(0.1, 0, 0.12))
		scn.part("box", at + Vector3(0.4, 1.9, 0), Vector3(0.7, 0.4, 0.04), Color("#a83838"), 0.0, Vector3(0, 0, 0.12))

func _place_glacier_crevasse() -> void:
	_viaduct(3.6, Color("#9ac4e4"))
	for n in range(6):
		var angle := deg_to_rad(-90.0 + (n - 2.5) * 56.0)
		haze_floor(Vector3(cos(angle) * (RADIUS + 0.9), -1.2, sin(angle) * (RADIUS + 0.9)), Vector2(5.0, 2.4), -angle + PI * 0.5, Color("#3aa0ff"), 0.0, 0.02, 4, 0.7)
	light(Vector3(-RADIUS - 1.0, -0.6, -2.0), Color("#3aa0ff"), 1.2, 6.0)
	light(Vector3(3.0, -0.6, -RADIUS - 1.0), Color("#3aa0ff"), 1.2, 6.0)

func _place_ice_spire_field() -> void:
	var ice := Color("#a6d6f6")
	# A ring of great spires stands behind the field, lit from inside.
	for n in range(11):
		var at := spot(-112.0 + n * 22.4, 2.4 + (n % 3) * 0.9, 0.18)
		var tall := lerpf(1.6, 5.6, tall_room(at.x, at.z)) * (0.7 + 0.3 * ((n * 7) % 4) / 3.0)
		scn.stand("spire%d" % (n % 3), at - Vector3(0, 0.2, 0), Vector3(1.2 + tall * 0.22, tall, 1.2 + tall * 0.22), n * 1.3, ice, Color.BLACK, 0.42, 0.0, Vector2(sin(n * 1.9) * 0.1, cos(n * 1.3) * 0.1))
	aurora(-30.0, 9.0, 16.0, Color("#6affc0"), 0.4)
	aurora(34.0, 11.0, 14.0, Color("#9a8aff"), 0.36)
	light(spot(-30.0, 2.6) + Vector3(0, 1.6, 0), Color("#7ad8ff"), 1.3, 7.5)
	light(spot(40.0, 2.6) + Vector3(0, 1.6, 0), Color("#8ab8ff"), 1.2, 7.5)

func _place_polar_night() -> void:
	# Aurora over the far ice, its colours on everything below it.
	aurora(-58.0, 6.5, 18.0, Color("#5affb0"), 0.8)
	aurora(-8.0, 8.5, 20.0, Color("#7af0d0"), 0.7)
	aurora(40.0, 7.0, 17.0, Color("#b488ff"), 0.75)
	aurora(-100.0, 9.0, 14.0, Color("#b488ff"), 0.6)
	aurora(84.0, 9.5, 14.0, Color("#5affb0"), 0.55)
	for n in range(8):
		var at := spot(-160.0 + n * 45.0, 2.2 + (n % 3) * 1.4, 0.16)
		scn.stand("slab%d" % (n % 3), at - Vector3(0, 0.4, 0), Vector3(2.6, lerpf(0.7, 1.9, tall_room(at.x, at.z)), 2.0), n * 1.3, Color("#6a86c0"), Color.BLACK, 0.0, 0.0, Vector2(sin(n * 1.7) * 0.5, cos(n * 2.3) * 0.5))
