extends Node3D
class_name StellarVfx

## Projectile, muzzle, impact, beam, zone, status, death and skill presentation.
## Reads simulation state only and owns no combat value.
##
## Everything is pooled into a handful of MultiMeshes created once in _ready():
##   Bullets  (120)  core sprite + hero-colour glow + ribbon trail + element motes
##   Muzzles  (24)   per live weapon socket, polled from the hero adapters each frame
##   Bursts   (64)   one-shot impacts / deaths / status / skills: ground shock ring,
##                   flash, streak sparks, rising motes, smoke or mist, scorch
##   Beams    (16)   beams, chain lightning, ricochet traces
##   Slashes  (12)   sword arcs: the melee fan at the hero's actual reach, aimed along the
##                   simulator's fire direction, swept by the blade head in 0.1 s
##   Zones    (36)   ground rune discs for sim.zones plus caster wind-up circles
##   Skills   (6)    whole sequences in one instance each: the Starlight Burst (falling
##                   star, impact, shockwave to the damage radius, fragments, afterglow)
##                   and the boss gate (four-second warning gather, arrival burst)
## plus two energy domes and six pooled OmniLights for the brightest pulses.
## Instances animate in their shaders from `vfx_time`, a clock that only advances in
## update(dt): a paused battle freezes every effect, and no node, mesh or material is
## created after start-up. The `effects` array is shared with StellarWorld and acts as
## the one-shot budget (EFFECT_LIMIT); the pools recycle their oldest slot when full.
const UNIT := 50.0
const EFFECT_LIMIT := 72
const MAX_BULLETS := 120
const MAX_BURSTS := 64
const MAX_BEAMS := 16
const MAX_MUZZLES := 24
const MAX_SLASHES := 12
const MAX_ZONES := 24
const MAX_CASTS := 12
const MAX_SKILLS := 6
const MAX_LIGHTS := 6
## Sword presentation. Swords fly no projectile: at the release the simulator cuts the
## bodies inside Balance.MELEE_ARC within the hero's reach (fire.melee, then hit.melee
## in the same tick). The arc mesh spans that fan plus a little follow-through on each
## side, is scaled to sim.heroes[src].range and aimed along fire.d; each blade contact is
## timed to the moment the sweeping head passes that body, so a pierce reads as three
## distinct cuts instead of one white blot.
const SLASH_OVERSHOOT_DEG := 9.0
const SLASH_SPAN_DEG := Balance.MELEE_ARC + 2.0 * SLASH_OVERSHOOT_DEG
const SLASH_SWEEP := 0.10         # seconds the head needs to cross the arc (the 3-frame cut)
const SLASH_LIFE := 0.34
const SLASH_HEIGHT := 0.88        # chest height of the horizontal arc
const SLASH_BAND := 0.72          # world units of radius the wake covers (clamped to the mesh)
const SLASH_TILT := 0.38          # roll: the wind-up side rides high, the follow-through low
const SLASH_PITCH := -0.22        # the leading edge dips forward
const BULLET_HEIGHT := 0.64
const PARKED := Transform3D(Basis.IDENTITY, Vector3(0, -60, 0))
## GL Compatibility stores MultiMesh custom data as 16-bit floats, so a birth time
## is kept relative to a rolling epoch (uniform `vfx_epoch`) and live instances are
## rebased when the epoch moves; otherwise ages would drift after a minute of battle.
const EPOCH_STEP := 8.0

const SPRITES: Texture2D = preload("res://art/vfx/sprites.png")
const SKILL_SPRITES: Texture2D = preload("res://art/vfx/skill_sprites.png")
const NOISE: Texture2D = preload("res://art/vfx/noise.png")
const SHADER_PROJECTILE: Shader = preload("res://art/vfx/vfx_projectile.gdshader")
const SHADER_BURST: Shader = preload("res://art/vfx/vfx_burst.gdshader")
const SHADER_BURST_MIX: Shader = preload("res://art/vfx/vfx_burst_mix.gdshader")
const SHADER_MUZZLE: Shader = preload("res://art/vfx/vfx_muzzle.gdshader")
const SHADER_BEAM: Shader = preload("res://art/vfx/vfx_beam.gdshader")
const SHADER_ZONE: Shader = preload("res://art/vfx/vfx_zone.gdshader")
const SHADER_ZONE_BASE: Shader = preload("res://art/vfx/vfx_zone_base.gdshader")
const SHADER_SLASH: Shader = preload("res://art/vfx/vfx_slash.gdshader")
const SHADER_SLASH_BASE: Shader = preload("res://art/vfx/vfx_slash_base.gdshader")
const SHADER_DOME: Shader = preload("res://art/vfx/vfx_dome.gdshader")
const SHADER_STATUS: Shader = preload("res://art/vfx/vfx_status.gdshader")
const SHADER_SKILL: Shader = preload("res://art/vfx/vfx_skill.gdshader")
const SHADER_SKILL_MIX: Shader = preload("res://art/vfx/vfx_skill_mix.gdshader")
## Shared looping status materials (burn / frost / stun) handed to body adapters by
## status_group(); the live world's VFX node keeps their clock in step with the battle.
static var _status_materials: Dictionary = {}
static var _status_mesh: ArrayMesh

## Burst kinds; the shaders key their timing tables on this order.
enum Kind { HIT, SPLASH, ZONE_TICK, DIE, LEAK, BLOCK, PUSH, FROST, STUN, CURSE, SPAWN, WILDFIRE,
	BLAST, FREEZE, WARD, MUZZLE_SMOKE, RIC_SPARK, BEAM_CAP, BOLT_CAP, CAST_RELEASE, SLASH_HIT }
## Seconds a burst slot stays reserved: at least the longest layer of that kind.
const KIND_LIFE := [0.50, 0.75, 0.55, 1.05, 0.60, 0.45, 0.35, 0.95, 0.45, 0.65, 0.90, 1.10,
	1.30, 1.40, 0.90, 0.62, 0.25, 0.30, 0.30, 0.50, 0.44]
const ELEM_INDEX := {"none": 0, "fire": 1, "ice": 2, "elec": 3, "water": 4}
const WEAPON_INDEX := {"rifle": 0, "gun": 0, "bow": 1, "cast": 2, "artillery": 3, "sword": 4, "tool": 5}
## Projectile head sprites: 0 tracer, 1 arrow, 2 shell, 3 bead, 4 orb, 5 crescent.
const BULLET_SIZE := {"shot": 0.13, "pierce": 0.15, "splash": 0.19, "chain": 0.14, "ricochet": 0.12}
const TRAIL_LENGTH := {"shot": 1.05, "pierce": 1.65, "splash": 0.85, "chain": 1.15, "ricochet": 0.95}
## Budget priority per burst kind: when the shared 72-slot budget is full, a new
## effect evicts the oldest live effect of lower or equal priority (skills never drop).
const KIND_PRIORITY := [0, 1, 0, 2, 3, 2, 1, 1, 1, 1, 2, 2, 4, 4, 4, 0, 0, 1, 1, 1, 0]
## Per-frame caps keep bulk events (a freeze slowing 40 bodies) from flooding one frame.
const FRAME_CAPS := {"hit": 10, "splash": 6, "frost": 4, "stun": 5, "die": 8, "push": 6, "zone_tick": 8}
## Girth of a scaled body in world units, measured once by fit_body().
const META_BODY_RADIUS := "_stellar_body_radius"
const PORTAL_COLOR := Color("#9d86ff")
const PUSH_COLOR := Color("#e8f1ff")
## Sequence kinds of the Skills pool (vfx_skill*.gdshader key their timelines on this order).
enum SkillKind { BLAST, BOSS_WARNING, BOSS_BURST }
## Starlight Burst: the star falls for BLAST_FALL seconds after the cast (the simulator's
## damage is immediate; the lock-on sigil marks the struck radius from the cast moment),
## then the impact layers run out over the rest of BLAST_LIFE.
const BLAST_FALL := 0.18
const BLAST_LIFE := 2.0
const BLAST_HOT := Color("#fff4d6")
## Boss gate: crimson gather, violet light; R is the arrival footprint (the 2.8x boss).
const BOSS_RED := Color("#ff3d5c")
const BOSS_VIOLET := Color("#9a4dff")
const BOSS_SIZE := 1.5
const BOSS_BURST_LIFE := 2.4
const STUN_COLOR := Color("#ffe38b")
const CURSE_COLOR := Color("#7a4fc9")

var projectiles: Node3D                 # shared parent for pooled bullet nodes
var effects: Array[Dictionary] = []     # shared with StellarWorld.effects (same array)

var _world: StellarWorld
var _clock := 0.0
var _epoch := 0.0
var _wash_theme := ""
var _materials: Array[ShaderMaterial] = []
var _bullets: MultiMeshInstance3D
var _muzzles: MultiMeshInstance3D
var _bursts: MultiMeshInstance3D
var _beams: MultiMeshInstance3D
var _slashes: MultiMeshInstance3D
var _zones: MultiMeshInstance3D
var _skills: MultiMeshInstance3D
var _domes: Array[MeshInstance3D] = []
var _dome_fx: Array[Dictionary] = []
var _lights: Array[OmniLight3D] = []
var _light_fx: Array[Dictionary] = []
var _next := {"dome": 0}
var _generation := {"burst": [], "beam": [], "slash": [], "skill": []}
var _free := {"burst": [], "beam": [], "slash": [], "skill": []}
var _pending_fires: Array[Dictionary] = []
var _pending_hits: Array[Dictionary] = []   # this tick's melee hits, timed after their fire
var _delayed: Array[Dictionary] = []        # bursts / pulses waiting on the effect clock
var _aims: Dictionary = {}
var _melee: Dictionary = {}                 # src -> last melee release (origin, dir, reach, sign)
var _big_bodies: Array[Node3D] = []         # live bodies whose root is scaled (bosses)
var _hero_cache: Dictionary = {}
var _split_gap := 0.0
var _hit_light_gap := 0.0
var _counter := 0
var _frame_counts: Dictionary = {}

static func world(p: Vector2, height: float = 0.0) -> Vector3:
	return StellarWorld.world(p, height)

func _ready() -> void:
	_world = get_parent() as StellarWorld
	# Live cards get their per-instance surface materials the moment they join the
	# actor tree, before their first frame: no resource is created mid-battle.
	if _world != null and _world.actors != null:
		_world.actors.child_entered_tree.connect(_on_actor_entered)
	var sizes := {"burst": MAX_BURSTS, "beam": MAX_BEAMS, "slash": MAX_SLASHES, "skill": MAX_SKILLS}
	for key in _generation.keys():
		var gen: Array = _generation[key]
		gen.resize(int(sizes[key]))
		gen.fill(0)
		var free: Array = _free[key]
		for i in range(int(sizes[key]) - 1, -1, -1): free.append(i)
	_bullets = _pool("Bullets", _bullet_mesh(), MAX_BULLETS, 0)
	_muzzles = _pool("Muzzles", _muzzle_mesh(), MAX_MUZZLES, 1)
	_bursts = _pool("Bursts", _burst_mesh(), MAX_BURSTS, -1, MAX_BURSTS)
	_beams = _pool("Beams", _beam_mesh(), MAX_BEAMS, 1, MAX_BEAMS)
	_slashes = _pool("Slashes", _slash_mesh(), MAX_SLASHES, 1, MAX_SLASHES)
	_zones = _pool("Zones", _zone_mesh(), MAX_ZONES + MAX_CASTS, -2)
	_skills = _pool("Skills", _skill_mesh(), MAX_SKILLS, 1, MAX_SKILLS)
	for n in range(2):
		var dome := MeshInstance3D.new()
		dome.name = "Dome" + str(n)
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 1.0
		sphere.is_hemisphere = true
		sphere.radial_segments = 28
		sphere.rings = 10
		dome.mesh = sphere
		var material := _material(SHADER_DOME, 2)
		dome.material_override = material
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dome.visible = false
		add_child(dome)
		_domes.append(dome)
		_dome_fx.append({"age": 0.0, "life": 0.0})
	for n in range(MAX_LIGHTS):
		var light := StellarLighting.pulse_light(Color.WHITE, 0.0, 2.0)
		light.name = "Pulse" + str(n)
		add_child(light)
		_lights.append(light)
		_light_fx.append({"age": 0.0, "life": 0.0, "energy": 0.0})

func _on_actor_entered(node: Node) -> void:
	if node is Node3D and (node.has_meta("native_id") or node.has_meta("_stellar_native_monster")):
		StellarShading.prepare_instance(node)
		# The world sets a body's root scale before it joins the actors (bosses: 2x).
		if fit_body(node): _big_bodies.append(node)

# --------------------------------------------------------------------------- #
# Pools, meshes and materials (created once)
# --------------------------------------------------------------------------- #
func _material(shader: Shader, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	material.set_shader_parameter("sprites", SPRITES)
	material.set_shader_parameter("skill_sprites", SKILL_SPRITES)
	material.set_shader_parameter("noise_tex", NOISE)
	material.set_shader_parameter("vfx_time", _clock)
	material.set_shader_parameter("vfx_epoch", _epoch)
	_materials.append(material)
	return material

func _pool(name: String, mesh: Mesh, count: int, _priority: int, visible_count: int = 0) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	for i in range(count):
		multimesh.set_instance_transform(i, PARKED)
		multimesh.set_instance_custom_data(i, Color(-1000.0, 0.0, 0.0, 0.0))
	multimesh.visible_instance_count = visible_count
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.ignore_occlusion_culling = true
	# Shaders displace vertices far from the instance origin (trails, blast rings),
	# so culling must use a generous fixed bound instead of the tiny source quads.
	node.custom_aabb = AABB(Vector3(-70, -70, -70), Vector3(140, 140, 140))
	add_child(node)
	return node

## A unit quad in XY with UV (0,0) at the top-left corner; the shaders rebuild
## its world position from (VERTEX.xy, UV2 = part/index).
static func _quad(st: SurfaceTool, part: int, index: int) -> void:
	var corners := [Vector3(-0.5, 0.5, 0), Vector3(0.5, 0.5, 0), Vector3(0.5, -0.5, 0), Vector3(-0.5, -0.5, 0)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(part, index))
		st.add_vertex(corners[i])

## A strip of `columns` quads: VERTEX.x = across (+-0.5), VERTEX.y = UV.y = along 0..1.
static func _strip(st: SurfaceTool, part: int, index: int, columns: int) -> void:
	for n in range(columns):
		var t0 := float(n) / columns
		var t1 := float(n + 1) / columns
		var points := [Vector3(-0.5, t0, 0), Vector3(0.5, t0, 0), Vector3(0.5, t1, 0), Vector3(-0.5, t1, 0)]
		var uvs := [Vector2(0, t0), Vector2(1, t0), Vector2(1, t1), Vector2(0, t1)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[i])
			st.set_uv2(Vector2(part, index))
			st.add_vertex(points[i])

func _bullet_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_strip(st, 0, 0, 6)
	_quad(st, 1, 0)
	_quad(st, 2, 0)
	for n in range(4): _quad(st, 3, n)
	st.set_material(_material(SHADER_PROJECTILE, 0))
	return st.commit()

func _muzzle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, 0, 0)
	_quad(st, 1, 0)
	_strip(st, 2, 0, 5)
	_quad(st, 3, 0)
	for n in range(6): _quad(st, 4, n)
	st.set_material(_material(SHADER_MUZZLE, 1))
	return st.commit()

func _burst_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, 0, 0)
	_quad(st, 1, 0)
	for n in range(8): _quad(st, 2, n)
	for n in range(8): _quad(st, 3, n)
	_quad(st, 5, 0)
	st.set_material(_material(SHADER_BURST, -1))
	var mesh := st.commit()
	var soft := SurfaceTool.new()
	soft.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(soft, 6, 0)
	for n in range(2): _quad(soft, 4, n)
	soft.set_material(_material(SHADER_BURST_MIX, -3))
	soft.commit(mesh)
	return mesh

func _beam_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := 16
	for n in range(columns):
		var t0 := float(n) / columns
		var t1 := float(n + 1) / columns
		# VERTEX.x across, UV.x along the line, UV.y across 0..1.
		var points := [Vector3(-0.5, 0, -t0), Vector3(0.5, 0, -t0), Vector3(0.5, 0, -t1), Vector3(-0.5, 0, -t1)]
		var uvs := [Vector2(t0, 0), Vector2(t0, 1), Vector2(t1, 1), Vector2(t1, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[i])
			st.set_uv2(Vector2(0, n))
			st.add_vertex(points[i])
	st.set_material(_material(SHADER_BEAM, 1))
	return st.commit()

## Unit-radius arc of the melee fan (plus follow-through), -Z at its centre; the
## instance transform scales it to the hero's reach and aims it (see _slash). Two
## surfaces over the same strip: an alpha-blended ink underlay (readable on bright
## snow and ice) and the additive blade wake on top.
func _slash_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = null
	for layer in range(2):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var columns := 28
		var span := deg_to_rad(SLASH_SPAN_DEG)
		var inner := 0.42
		for n in range(columns):
			var a0 := -span * 0.5 + span * float(n) / columns
			var a1 := -span * 0.5 + span * float(n + 1) / columns
			var points := [
				Vector3(sin(a0), 0, -cos(a0)), Vector3(sin(a1), 0, -cos(a1)),
				Vector3(sin(a1) * inner, 0, -cos(a1) * inner), Vector3(sin(a0) * inner, 0, -cos(a0) * inner)]
			var uvs := [Vector2(float(n) / columns, 0), Vector2(float(n + 1) / columns, 0),
				Vector2(float(n + 1) / columns, 1), Vector2(float(n) / columns, 1)]
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[i])
				st.set_uv2(Vector2(0, n))
				st.add_vertex(points[i])
		st.set_material(_material(SHADER_SLASH_BASE, 0) if layer == 0 else _material(SHADER_SLASH, 1))
		mesh = st.commit(mesh)
	return mesh

## One sequence per instance (vfx_skill / vfx_skill_mix): every quad is a part of the
## timeline (UV2.x) and the shaders place it from the instance's age. Additive surface:
## shock ring, sigil, flash, flare, pillar, comet tail strip + head, 16 sparks, 12 embers,
## afterglow, sky flare, 4 lightning bolts, portal ring, crack glow. Mix surface: cracks,
## dark ring, 6 smoke puffs, 10 debris chunks, 8 mist wisps.
func _skill_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [0, 1, 2, 3, 4]: _quad(st, part, 0)
	_strip(st, 5, 0, 8)
	_quad(st, 6, 0)
	for n in range(16): _quad(st, 7, n)
	for n in range(12): _quad(st, 8, n)
	for part in [9, 10]: _quad(st, part, 0)
	for n in range(4): _quad(st, 11, n)
	for part in [12, 13]: _quad(st, part, 0)
	st.set_material(_material(SHADER_SKILL, 1))
	var mesh := st.commit()
	var soft := SurfaceTool.new()
	soft.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [20, 21]: _quad(soft, part, 0)
	for n in range(6): _quad(soft, 22, n)
	for n in range(10): _quad(soft, 23, n)
	for n in range(8): _quad(soft, 24, n)
	soft.set_material(_material(SHADER_SKILL_MIX, -3))
	soft.commit(mesh)
	return mesh

func _zone_mesh() -> ArrayMesh:
	var base := SurfaceTool.new()
	base.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(base, 0, 0)
	base.set_material(_material(SHADER_ZONE_BASE, -4))
	var mesh := base.commit()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, 0, 0)
	for n in range(8): _quad(st, 1, n)
	st.set_material(_material(SHADER_ZONE, -2))
	st.commit(mesh)
	return mesh

# --------------------------------------------------------------------------- #
# Per-frame presentation from the simulator's current lists
# --------------------------------------------------------------------------- #
func sync(sim, _time: float) -> void:
	if _bullets == null: return
	_frame_counts.clear()
	_sync_wash()
	_sync_bullets(sim)
	_sync_muzzles(sim)
	_sync_zones(sim)
	_flush_fires(sim)

## Bright snow and ice fields wash additive layers out to white; tell the shaders.
func _sync_wash() -> void:
	if _world == null or _world.theme_id == _wash_theme: return
	_wash_theme = _world.theme_id
	var bright := 0.0
	for theme in Roster.THEMES:
		if String(theme.get("id", "")) == _wash_theme and String(theme.get("main_body", "")) in ["aqua", "frost"]:
			bright = 1.0
	for material in _materials: material.set_shader_parameter("vfx_wash", bright)

func _sync_bullets(sim) -> void:
	var multimesh := _bullets.multimesh
	var count := mini(MAX_BULLETS, sim.bullets.size())
	multimesh.visible_instance_count = count
	for i in range(count):
		var b: Dictionary = sim.bullets[i]
		var v: Vector2 = b.get("v", Vector2.ZERO)
		var direction := Vector3(v.x, 0.0, v.y)
		if direction.length_squared() < 0.0001: direction = Vector3(0, 0, -1)
		var basis := Basis.looking_at(direction.normalized(), Vector3.UP)
		multimesh.set_instance_transform(i, Transform3D(basis, world(Vector2(b["p"]), BULLET_HEIGHT)))
		var info := _hero_info(int(b.get("src", -1)), sim)
		var kind := String(b.get("kind", "shot"))
		var boost := 1.3 if bool(b.get("crit", false)) else 1.0
		var elem := String(b.get("el", info.get("elem", "none")))
		multimesh.set_instance_color(i, Color(b.get("c", info.get("color", Color.WHITE))))
		multimesh.set_instance_custom_data(i, Color(_shape(String(info.get("weapon", "gun")), kind),
			float(TRAIL_LENGTH.get(kind, 0.95)) * boost, float(BULLET_SIZE.get(kind, 0.10)) * boost,
			float(ELEM_INDEX.get(elem, 0))))

## Projectile head shape. Swords never appear here: the simulator cuts directly (_slash).
static func _shape(weapon: String, kind: String) -> float:
	match weapon:
		"bow": return 1.0
		"deck": return 4.0
		"whip": return 4.0 if kind == "chain" else 2.0 if kind == "splash" else 3.0
	return 2.0 if kind == "splash" else 4.0 if kind == "chain" else 0.0

func _sync_muzzles(sim) -> void:
	var multimesh := _muzzles.multimesh
	var n := 0
	if _world != null:
		for i in range(sim.heroes.size()):
			if n >= MAX_MUZZLES: break
			var node := _world.hero_node(i)
			if node == null or not node.has_method("fire_strength") or not node.has_method("weapon_transform"): continue
			var strength := float(node.call("fire_strength"))
			if strength <= 0.01: continue
			var info := _hero_info(i, sim)
			var elem := String(info.get("elem", "none"))
			var weapon := float(WEAPON_INDEX.get(String(info.get("attack", "rifle")), 0))
			var color := _effect_color(info, elem)
			for s in range(int(info.get("sockets", 1))):
				if n >= MAX_MUZZLES: break
				var mouth: Transform3D = node.call("weapon_transform", -1 if s == 0 else 1)
				multimesh.set_instance_transform(n, Transform3D(mouth.basis.orthonormalized(), mouth.origin))
				multimesh.set_instance_color(n, color)
				multimesh.set_instance_custom_data(n, Color(weapon, strength, float(i) * 0.37 + float(s) * 0.5 + 0.11, float(ELEM_INDEX.get(elem, 0))))
				n += 1
	multimesh.visible_instance_count = n

func _sync_zones(sim) -> void:
	var multimesh := _zones.multimesh
	var n := 0
	for z in sim.zones:
		if n >= MAX_ZONES: break
		var radius := float(z.get("r", 128.0)) / UNIT
		multimesh.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)), world(Vector2(z["at"]), 0.0)))
		var color := Color(z.get("c", Color.WHITE))
		color.a = 1.0 - float(z.get("n", 0)) / maxf(1.0, float(z.get("max", 1)))
		multimesh.set_instance_color(n, color)
		multimesh.set_instance_custom_data(n, Color(float(z.get("t", 0.0)), float(z.get("delay", 0.26)),
			float(z.get("tick", 0.25)), float(ELEM_INDEX.get(String(z.get("el", "none")), 0))))
		n += 1
	# Caster wind-up circles follow the adapter's actual aim phase.
	if _world != null:
		for src in _aims.keys():
			if n >= MAX_ZONES + MAX_CASTS: break
			var node := _world.hero_node(int(src))
			if node == null or not node.has_method("visual_phase") or int(node.call("visual_phase")) != 1:
				_aims.erase(src)
				continue
			var aim: Dictionary = _aims[src]
			var info := _hero_info(int(src), sim)
			if String(info.get("attack", "")) != "cast":
				_aims.erase(src)
				continue
			var elem := String(info.get("elem", "none"))
			var progress := clampf((_clock - float(aim["birth"])) / maxf(float(aim.get("w", 0.3)), 0.05), 0.0, 1.0)
			var at := node.global_position
			multimesh.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(0.66, 1.0, 0.66)), Vector3(at.x, 0.0, at.z)))
			multimesh.set_instance_color(n, _effect_color(info, elem))
			multimesh.set_instance_custom_data(n, Color(progress, -1.0, 0.25, float(ELEM_INDEX.get(elem, 0))))
			n += 1
	multimesh.visible_instance_count = n

## Release effects that need the posed socket: spawned after the heroes have been
## synced for this frame, so the smoke, light and slash start at the real mouth.
## Melee releases (fire.melee) instead spawn the reach-sized arc from the simulator's
## hero position and fire direction, then time this tick's blade contacts to it.
func _flush_fires(sim) -> void:
	if _pending_fires.is_empty() and _pending_hits.is_empty(): return
	for e in _pending_fires:
		var src := int(e.get("src", -1))
		var info := _hero_info(src, sim)
		var attack := String(info.get("attack", "rifle"))
		var elem := String(e.get("el", info.get("elem", "none")))
		var elem_index := float(ELEM_INDEX.get(elem, 0))
		var color := _effect_color(info, elem)
		var shots := maxi(1, int(e.get("n", 1)))
		var node: Node3D = _world.hero_node(src) if _world != null else null
		if bool(e.get("melee", false)) or attack == "sword":
			_melee_release(src, e, sim, info, color, elem_index)
			_aims.erase(src)
			continue
		if node != null and node.has_method("weapon_transform"):
			var sockets := int(info.get("sockets", 1))
			for s in range(sockets):
				var mouth: Transform3D = node.call("weapon_transform", -1 if s == 0 else 1)
				var basis := mouth.basis.orthonormalized()
				match attack:
					"rifle", "tool":
						_burst(Kind.MUZZLE_SMOKE, mouth.origin, basis, color, 1.0, elem_index)
					"artillery":
						_burst(Kind.MUZZLE_SMOKE, mouth.origin, basis, color, 1.7, elem_index)
					"cast":
						var foot := node.global_position
						_burst(Kind.CAST_RELEASE, Vector3(foot.x, 0.0, foot.z), basis, color, 1.0, elem_index)
				if s == 0:
					var energy := 2.4 if attack in ["rifle", "artillery"] else 1.3 if attack == "bow" else 1.9
					_pulse(mouth.origin + basis * Vector3(0, 0, -0.25), color, energy * sqrt(float(mini(shots, 4))),
						3.0 if attack == "artillery" else 2.3, 0.14)
			_aims.erase(src)
		elif e.has("p"):
			_pulse(world(Vector2(e["p"]), 0.9), color, 1.5, 2.2, 0.12)
	_pending_fires.clear()
	for e in _pending_hits: _melee_hit(e)
	_pending_hits.clear()

## A sword (or Pip's wrench) release: the arc at the hero's actual reach, centred on the
## body the simulator struck first this tick (BattleSim._strike centres its fan on the hero's
## own position; fire.d is measured from the muzzle point, which sits to the weapon side,
## so it can lean up to ~60 degrees off the struck bodies at sword reach), remembered so
## this tick's contacts can follow the blade.
func _melee_release(src: int, e: Dictionary, sim, info: Dictionary, color: Color, elem: float) -> void:
	var d: Vector2 = e.get("d", Vector2.ZERO)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector2(0, 1)
	var at: Vector2 = e.get("p", Vector2.ZERO)
	var reach := float(Balance.WEAPON_RANGE.get("sword", 60.0)) / UNIT
	if sim != null and src >= 0 and src < sim.heroes.size():
		at = sim.heroes[src]["pos"]
		reach = float(sim.heroes[src].get("range", reach * UNIT)) / UNIT
	for hit in _pending_hits:
		if int(hit.get("src", -1)) != src: continue
		var to: Vector2 = Vector2(hit.get("p", at)) - at
		if to.length_squared() > 1.0: d = to.normalized()
		break
	var tool := String(info.get("attack", "")) == "tool"
	# The authored cut travels from the weapon hand across to the other side; the wrench falls.
	var sign_value := -1.0 if tool or String(info.get("lead", "L")) == "R" else 1.0
	_melee[src] = {"at": at, "d": d, "reach": reach, "sign": sign_value, "tool": tool, "birth": _clock}
	_slash(at, d, reach, sign_value, tool, color, elem)
	var forward := Vector3(d.x, 0.0, d.y)
	_pulse(world(at, 0.45) + forward * reach * 0.55, color, 1.9, 2.0 + reach * 0.6, 0.14)

## A melee hit: a blade-contact burst on the body, facing the blade's travel there, spawned
## when the sweeping head reaches that body (0..SLASH_SWEEP after the release). Pierce
## contacts therefore land one after another along the arc.
func _melee_hit(e: Dictionary) -> void:
	var scale := _impact_scale(e)
	if scale <= 0.0: return
	var src := int(e.get("src", -1))
	var p: Vector2 = e.get("p", Vector2.ZERO)
	var color := Color(e.get("c", Color("#eacb81")))
	var elem := float(ELEM_INDEX.get(String(e.get("el", "none")), 0))
	# Body centre. The ceiling keeps tall ordinary bodies near the blade's plane and grows
	# with the root scale, so a 2x boss is cut on its body, not at its ankles.
	var sid := int(e.get("sid", 0))
	var big := _big_body_at(p)
	var body := big.scale.y if big != null else 1.0
	var origin := world(p, clampf(_monster_height(sid) * 0.55, 0.3, 1.1 * body))
	var basis := _yaw()
	var delay := 0.0
	var record: Dictionary = _melee.get(src, {})
	if big != null and not record.is_empty():
		# On a boss the cut sits on the flank that faces the blade, so two guardians on
		# either side leave two readable marks instead of one at the body's axis.
		var toward: Vector2 = Vector2(record["at"]) - p
		if toward.length_squared() > 1.0:
			toward = toward.normalized() * float(big.get_meta(META_BODY_RADIUS, 0.0)) * 0.5
			origin += Vector3(toward.x, 0.0, toward.y)
	if not record.is_empty() and _clock - float(record["birth"]) < 0.5:
		var d: Vector2 = record["d"]
		var facing := Basis.looking_at(Vector3(d.x, 0.0, d.y), Vector3.UP)
		var sign_value := float(record["sign"])
		var fraction := 0.72
		var tangent := Vector3.DOWN
		if not bool(record["tool"]):
			var to: Vector2 = p - Vector2(record["at"])
			var theta := atan2(to.dot(Vector2(-d.y, d.x)), to.dot(d))
			var half := deg_to_rad(SLASH_SPAN_DEG) * 0.5
			fraction = clampf((theta * sign_value + half) / (2.0 * half), 0.0, 1.0)
			tangent = facing * Vector3(cos(theta), 0.0, sin(theta)) * sign_value
		basis = _travel_basis(tangent, facing)
		# The head eases out across the arc (vfx_slash); invert that for the arrival time.
		delay = maxf(0.0, float(record["birth"]) + SLASH_SWEEP * (1.0 - sqrt(1.0 - fraction)) - _clock)
	var fx := {"at": _clock + delay, "kind": Kind.SLASH_HIT, "origin": origin, "basis": basis,
		"color": color, "size": scale, "elem": elem, "body": body}
	if (bool(e.get("crit", false)) or float(e.get("em", 1.0)) >= 2.0) and _hit_light_gap <= 0.0:
		_hit_light_gap = 0.08
		fx["pulse"] = 1.4 * scale
	_delayed.append(fx)

## A burst basis whose -Z is the blade's travel direction at the contact point.
static func _travel_basis(tangent: Vector3, facing: Basis) -> Basis:
	if absf(tangent.y) < 0.9:
		return Basis.looking_at(tangent.normalized(), Vector3.UP)
	var x := facing.x.normalized()
	var z := -tangent.normalized()
	return Basis(x, z.cross(x).normalized(), z)

# --------------------------------------------------------------------------- #
# One-shot combat events
# --------------------------------------------------------------------------- #
func event(e: Dictionary) -> void:
	if _bullets == null: return
	var type := String(e.get("t", ""))
	match type:
		"aim":
			var src := int(e.get("src", -1))
			if src >= 0: _aims[src] = {"birth": _clock, "w": float(e.get("w", 0.3))}
			return
		"cancel":
			_aims.erase(int(e.get("src", -1)))
			return
		"fire":
			_pending_fires.append(e)
			return
	if FRAME_CAPS.has(type):
		var seen := int(_frame_counts.get(type, 0)) + 1
		_frame_counts[type] = seen
		if seen > int(FRAME_CAPS[type]): return
	var color := Color(e.get("c", Color("#eacb81")))
	var elem := float(ELEM_INDEX.get(String(e.get("el", "none")), 0))
	# Root scale of the boss whose body this effect lands in (1 anywhere else): the air
	# parts of the burst then lift with the body and are drawn in front of it.
	var body := _body_scale_at(e.get("b", e.get("p")))
	match type:
		"hit":
			if bool(e.get("melee", false)):
				# Blade contacts wait for this tick's release so they can follow the arc.
				_pending_hits.append(e)
				return
			var p: Vector2 = e.get("p", Vector2.ZERO)
			var scale := _impact_scale(e)
			if scale <= 0.0: return
			_burst(Kind.HIT, world(p, 0.0), _yaw(), color, scale, elem, body)
			if (bool(e.get("crit", false)) or float(e.get("em", 1.0)) >= 2.0) and _hit_light_gap <= 0.0:
				_hit_light_gap = 0.08
				_pulse(world(p, 0.6), color, 1.4 * scale, 2.0, 0.12)
		"splash":
			var p: Vector2 = e.get("p", Vector2.ZERO)
			var radius := float(e.get("r", 48.0)) / UNIT
			var d: Vector2 = e.get("d", Vector2.ZERO)
			var facing := _yaw() if d.length_squared() < 0.001 else Basis.looking_at(Vector3(d.x, 0, d.y).normalized(), Vector3.UP)
			if bool(e.get("split", false)):
				# Split warheads burst on every hit: a small bloom, rate limited.
				if _split_gap > 0.0: return
				_split_gap = 0.09
				_burst(Kind.SPLASH, world(p, 0.0), facing, color, radius * 0.55, elem, body)
				return
			var scale := _impact_scale(e)
			if scale <= 0.0: return
			_burst(Kind.SPLASH, world(p, 0.0), facing, color, radius * minf(scale, 1.3), elem, body)
			_pulse(world(p, 0.5), color, 2.2 * scale, 2.6 + radius, 0.18)
		"zone_tick":
			var p: Vector2 = e.get("p", Vector2.ZERO)
			_burst(Kind.ZONE_TICK, world(p, 0.0), _yaw(), color, float(e.get("r", 128.0)) / UNIT, elem)
		"beam":
			var a := world(Vector2(e.get("a", Vector2.ZERO)), 0.92)
			var b := world(Vector2(e.get("b", Vector2.ZERO)), 0.62)
			_beam(0, a, b, color, 1.0 if bool(e.get("big", false)) else 0.0)
			_burst(Kind.BEAM_CAP, b, _yaw(), color, 1.0, elem, body)
			_pulse(b, color, 1.6, 2.2, 0.16)
		"bolt":
			var a := world(Vector2(e.get("a", Vector2.ZERO)), 0.62)
			var b := world(Vector2(e.get("b", Vector2.ZERO)), 0.62)
			_beam(1, a, b, color, 0.0)
			_burst(Kind.BOLT_CAP, b, _yaw(), color, 1.0, 3.0, body)
		"ric":
			var a := world(Vector2(e.get("a", Vector2.ZERO)), BULLET_HEIGHT)
			var b := world(Vector2(e.get("b", Vector2.ZERO)), BULLET_HEIGHT)
			_beam(2, a, b, color, 0.0)
			_burst(Kind.RIC_SPARK, a, _yaw(), color, 1.0, elem)
		"die":
			var p: Vector2 = e.get("p", Vector2.ZERO)
			_burst(Kind.DIE, world(p, 0.0), _yaw(), color, 1.0, elem, body)
			_pulse(world(p, 0.5), color.lightened(0.3), 1.3, 2.2, 0.35)
		"leak":
			var p: Vector2 = e.get("p", Vector2.ZERO)
			var radius := float(e.get("r", 32.0)) / UNIT
			_burst(Kind.LEAK, world(p, 0.0), _yaw(), color, radius, elem)
			_pulse(world(p, 0.8), color, 3.2, 3.6, 0.32)
		"block":
			var p: Vector2 = e.get("p", Vector2.ZERO)
			_burst(Kind.BLOCK, world(p, 0.0), _yaw(), Look.CRYSTAL, 1.0, 0.0)
			_dome(world(p, 0.0), 0.62, Look.CRYSTAL, 0.5)
		"push":
			var p: Vector2 = e.get("p", Vector2.ZERO)
			var node: Node3D = _world.monster_node(int(e.get("sid", 0))) if _world != null else null
			var facing := _yaw()
			if node != null:
				var back: Vector3 = node.global_basis.z
				if back.length_squared() > 0.001: facing = Basis.looking_at(Vector3(back.x, 0, back.z).normalized(), Vector3.UP)
			_burst(Kind.PUSH, world(p, 0.0), facing, PUSH_COLOR, 1.0, 0.0, body)
		"frost":
			_burst(Kind.FROST, world(Vector2(e.get("p", Vector2.ZERO)), 0.0), _yaw(), Look.ICE, 1.0, 2.0, body)
		"stun":
			var sid := int(e.get("sid", 0))
			_burst(Kind.STUN, world(Vector2(e.get("p", Vector2.ZERO)), 0.0), _yaw(), STUN_COLOR, _monster_height(sid) + 0.12 * _monster_scale(sid), 3.0, body)
		"curse":
			_burst(Kind.CURSE, world(Vector2(e.get("p", Vector2.ZERO)), 0.0), _yaw(), CURSE_COLOR, 1.0, 0.0, body)
		"spawn":
			var p: Vector2 = e.get("p", Vector2.ZERO)
			_burst(Kind.SPAWN, world(p, 0.0), _yaw(), PORTAL_COLOR, 1.0, 0.0)
			_pulse(world(p, 0.5), PORTAL_COLOR, 1.2, 2.4, 0.45)
		"wildfire":
			var p: Vector2 = e.get("p", Vector2.ZERO)
			var radius := float(e.get("r", 60.0)) / UNIT
			_burst(Kind.WILDFIRE, world(p, 0.0), _yaw(), Balance.elem_color("fire"), radius, 1.0)
			_pulse(world(p, 0.4), Balance.elem_color("fire"), 2.0, 2.0 + radius, 0.4)

## Arena-wide guardian skills (blast / freeze / ward) and the boss gate.
##   arena_blast         p (ground point), r (damage radius, logical units)
##   arena_freeze        p, r (map diagonal)      arena_ward  p, r (altar radius)
##   arena_boss_warning  p (the gate the boss will come through), sec (seconds until it does;
##                       the gather runs exactly that long and hands over to the burst)
##   arena_boss          p (where the boss stands as it arrives)
func arena_event(e: Dictionary) -> void:
	if _bullets == null: return
	var type := String(e.get("t", ""))
	var at := world(Vector2(e.get("p", Balance.ARENA_CENTER)), 0.0)
	var radius := float(e.get("r", 70.0)) / UNIT
	match type:
		"arena_blast":
			# The star is born at the cast (sky flare + lock-on on the struck radius), hits
			# BLAST_FALL later; the big light waits for the impact on the effect clock.
			radius = float(e.get("r", Balance.ARENA_BLAST_RADIUS)) / UNIT
			_skill(SkillKind.BLAST, at, radius, Look.GOLD, 0.0, BLAST_LIFE)
			_pulse(at + Vector3(0, 0.5, 0), Look.GOLD, 2.0, radius * 1.8, BLAST_FALL + 0.05)
			_delayed.append({"at": _clock + BLAST_FALL, "kind": -1, "origin": at + Vector3(0, 0.8, 0),
				"color": BLAST_HOT, "pulse": 9.0, "range": radius * 3.6, "life": 0.9})
		"arena_freeze":
			_burst(Kind.FREEZE, at, _yaw(), Look.ICE, minf(radius * 0.36, 10.5), 2.0)
			_pulse(at + Vector3(0, 0.8, 0), Look.ICE_DEEP, 4.0, 8.0, 0.6)
		"arena_ward":
			_burst(Kind.WARD, at, _yaw(), Look.CRYSTAL, radius, 0.0)
			_dome(at, radius * 1.25, Look.CRYSTAL, 0.95)
			_pulse(at + Vector3(0, 1.0, 0), Look.CRYSTAL, 3.2, 4.5, 0.55)
		"arena_boss_warning":
			var sec := maxf(float(e.get("sec", 4.0)), 0.5)
			_skill(SkillKind.BOSS_WARNING, at, BOSS_SIZE, BOSS_RED, sec, sec + 0.2)
			_pulse(at + Vector3(0, 0.7, 0), BOSS_VIOLET, 4.5, BOSS_SIZE * 5.5, sec, 1)
		"arena_boss":
			_skill(SkillKind.BOSS_BURST, at, BOSS_SIZE, BOSS_RED, 0.0, BOSS_BURST_LIFE)
			_pulse(at + Vector3(0, 1.3, 0), BOSS_VIOLET.lerp(Color.WHITE, 0.3), 8.0, BOSS_SIZE * 7.5, 1.5, 2)

func update(dt: float) -> void:
	if _bullets == null: return
	if dt > 0.0:
		_clock += dt
		if _clock - _epoch >= EPOCH_STEP: _rebase()
		for material in _materials: material.set_shader_parameter("vfx_time", _clock)
		for material in _status_materials.values(): material.set_shader_parameter("vfx_time", _clock)
	_split_gap = maxf(0.0, _split_gap - dt)
	_hit_light_gap = maxf(0.0, _hit_light_gap - dt)
	# Blade contacts spawn when the sweeping head reaches them, the blast's light when the
	# star lands; a paused clock holds them. kind -1 is a pulse without a burst.
	for i in range(_delayed.size() - 1, -1, -1):
		var fx: Dictionary = _delayed[i]
		if float(fx["at"]) > _clock: continue
		if int(fx["kind"]) >= 0:
			_burst(int(fx["kind"]), fx["origin"], fx["basis"], fx["color"], float(fx["size"]), float(fx["elem"]), float(fx.get("body", 1.0)))
		if fx.has("pulse"): _pulse(fx["origin"], fx["color"], float(fx["pulse"]), float(fx.get("range", 2.0)), float(fx.get("life", 0.12)))
		_delayed.remove_at(i)
	for i in range(effects.size() - 1, -1, -1):
		var fx = effects[i]
		if typeof(fx) != TYPE_DICTIONARY or not fx.has("vfx"): continue
		fx["age"] = float(fx["age"]) + dt
		if float(fx["age"]) >= float(fx["life"]):
			_release(fx)
			effects.remove_at(i)
	for i in range(_lights.size()):
		var fx: Dictionary = _light_fx[i]
		if float(fx["life"]) <= 0.0: continue
		fx["age"] = float(fx["age"]) + dt
		var q := float(fx["age"]) / float(fx["life"])
		if q >= 1.0:
			fx["life"] = 0.0
			_lights[i].visible = false
			_lights[i].light_energy = 0.0
		else:
			_lights[i].light_energy = float(fx["energy"]) * _light_curve(int(fx.get("mode", 0)), q, float(fx["age"]))
	for i in range(_domes.size()):
		var fx: Dictionary = _dome_fx[i]
		if float(fx["life"]) <= 0.0: continue
		fx["age"] = float(fx["age"]) + dt
		if float(fx["age"]) >= float(fx["life"]):
			fx["life"] = 0.0
			_domes[i].visible = false

# --------------------------------------------------------------------------- #
# Slot allocation
# --------------------------------------------------------------------------- #
## A free slot of the pool; when every slot is live, the oldest record of lowest
## priority (never one more important than the newcomer) is released first.
func _take(pool: String, priority: int) -> int:
	var free: Array = _free[pool]
	if free.is_empty() and not _evict(pool, priority): return -1
	var slot: int = free.pop_back()
	var gen: Array = _generation[pool]
	gen[slot] = int(gen[slot]) + 1
	return slot

func _record(pool: String, slot: int, life: float, priority: int, custom: Color) -> void:
	effects.append({"vfx": pool, "slot": slot, "gen": _generation[pool][slot], "age": 0.0, "life": life,
		"pri": priority, "birth": _clock, "custom": custom})

func _pool_node(pool: String) -> MultiMeshInstance3D:
	match pool:
		"burst": return _bursts
		"beam": return _beams
		"skill": return _skills
	return _slashes

## Move the shader epoch forward and re-encode every live birth relative to it.
func _rebase() -> void:
	_epoch = floor(_clock / EPOCH_STEP) * EPOCH_STEP
	for material in _materials: material.set_shader_parameter("vfx_epoch", _epoch)
	for fx in effects:
		if typeof(fx) != TYPE_DICTIONARY or not fx.has("vfx"): continue
		var custom: Color = fx["custom"]
		custom.r = float(fx["birth"]) - _epoch
		_pool_node(String(fx["vfx"])).multimesh.set_instance_custom_data(int(fx["slot"]), custom)

## The shared budget (StellarWorld.effects, 72) may also be filled by others. When it is
## full, drop the oldest of our own effects whose priority is not higher than the newcomer.
func _make_room(priority: int) -> bool:
	if effects.size() < EFFECT_LIMIT: return true
	return _evict("", priority)

## Release the lowest-priority, oldest live record (optionally of one pool).
func _evict(pool: String, priority: int) -> bool:
	var victim := -1
	var worst := -INF
	for i in range(effects.size()):
		var fx = effects[i]
		if typeof(fx) != TYPE_DICTIONARY or not fx.has("vfx"): continue
		if pool != "" and String(fx["vfx"]) != pool: continue
		var pri := int(fx.get("pri", 0))
		if pri > priority: continue
		var rank := float(priority - pri) * 10.0 + float(fx["age"]) / maxf(float(fx["life"]), 0.01)
		if rank > worst:
			worst = rank
			victim = i
	if victim < 0: return false
	_release(effects[victim])
	effects.remove_at(victim)
	return true

func _release(fx: Dictionary) -> void:
	var pool := String(fx["vfx"])
	var slot := int(fx["slot"])
	if not _generation.has(pool) or int(_generation[pool][slot]) != int(fx["gen"]): return
	var node := _pool_node(pool)
	node.multimesh.set_instance_transform(slot, PARKED)
	node.multimesh.set_instance_custom_data(slot, Color(-1000.0, 0.0, 0.0, 0.0))
	var free: Array = _free[pool]
	if not free.has(slot): free.append(slot)

## `body` is the root scale of the body the burst lands in (see _body_scale_at); it rides in
## the instance colour's alpha, which the burst shaders read as lift and camera clearance.
func _burst(kind: int, origin: Vector3, basis: Basis, color: Color, size: float, elem: float, body: float = 1.0) -> void:
	if not _make_room(KIND_PRIORITY[kind]): return
	var slot := _take("burst", KIND_PRIORITY[kind])
	if slot < 0: return
	var multimesh := _bursts.multimesh
	multimesh.set_instance_transform(slot, Transform3D(basis, origin))
	color.a = maxf(body, 1.0)
	multimesh.set_instance_color(slot, color)
	var custom := Color(_clock - _epoch, size, elem, float(kind))
	multimesh.set_instance_custom_data(slot, custom)
	_record("burst", slot, KIND_LIFE[kind], KIND_PRIORITY[kind], custom)

## A whole skill / gate sequence in one Skills instance (priority 4: never evicted by
## ordinary combat effects). `radius` is in world units; `duration` is the warning's
## length (its parts stop exactly there so the arrival burst takes over).
func _skill(kind: int, origin: Vector3, radius: float, color: Color, duration: float, life: float) -> void:
	if not _make_room(4): return
	var slot := _take("skill", 4)
	if slot < 0: return
	var multimesh := _skills.multimesh
	multimesh.set_instance_transform(slot, Transform3D(_yaw(), origin))
	multimesh.set_instance_color(slot, color)
	var custom := Color(_clock - _epoch, radius, duration, float(kind))
	multimesh.set_instance_custom_data(slot, custom)
	_record("skill", slot, life, 4, custom)

func _beam(kind: int, a: Vector3, b: Vector3, color: Color, big: float) -> void:
	if not _make_room(1): return
	var axis := b - a
	if axis.length_squared() < 0.0004: return
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.0001: side = Vector3.RIGHT
	var slot := _take("beam", 1)
	if slot < 0: return
	var multimesh := _beams.multimesh
	multimesh.set_instance_transform(slot, Transform3D(Basis(side.normalized(), Vector3.UP, -axis), a))
	multimesh.set_instance_color(slot, color)
	_counter += 1
	var custom := Color(_clock - _epoch, float(kind), fposmod(float(_counter) * 0.37, 1.0), big)
	multimesh.set_instance_custom_data(slot, custom)
	_record("beam", slot, 0.28, 1, custom)

## The slash arc: unit mesh scaled to `reach` (world units) at the hero's simulated
## position `at`, centred on the fire direction `d`. Swords roll so the wind-up side
## rides high and the follow-through low; the wrench stands the arc upright and falls.
func _slash(at: Vector2, d: Vector2, reach: float, sign_value: float, tool: bool, color: Color, elem: float) -> void:
	if not _make_room(1): return
	var slot := _take("slash", 1)
	if slot < 0: return
	reach = maxf(reach, 0.3)
	var facing := Basis.looking_at(Vector3(d.x, 0.0, d.y), Vector3.UP)
	var basis: Basis
	if tool:
		basis = facing * Basis(Vector3.BACK, PI * 0.5)
	else:
		basis = facing * Basis(Vector3.BACK, -sign_value * SLASH_TILT) * Basis(Vector3.RIGHT, SLASH_PITCH)
	basis = basis * Basis.from_scale(Vector3.ONE * reach)
	var band := clampf(SLASH_BAND / reach, 0.3, 0.58)
	var multimesh := _slashes.multimesh
	multimesh.set_instance_transform(slot, Transform3D(basis, world(at, SLASH_HEIGHT + (0.1 if tool else 0.0))))
	multimesh.set_instance_color(slot, color)
	_counter += 1
	var custom := Color(_clock - _epoch, sign_value * band, fposmod(float(_counter) * 0.61, 1.0), elem)
	multimesh.set_instance_custom_data(slot, custom)
	_record("slash", slot, SLASH_LIFE, 1, custom)

func _dome(at: Vector3, radius: float, color: Color, life: float) -> void:
	var index: int = _next["dome"]
	_next["dome"] = (index + 1) % _domes.size()
	var dome := _domes[index]
	dome.position = at + Vector3(0, 0.02, 0)
	dome.scale = Vector3.ONE * radius
	var material: ShaderMaterial = dome.material_override
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("birth", _clock)
	material.set_shader_parameter("duration", life)
	dome.visible = true
	_dome_fx[index] = {"age": 0.0, "life": life}

## Energy envelope of a pulse light over its life fraction q:
##   0 decay (impacts, releases)   1 gather: throbbing ramp that peaks at the end (boss warning)
##   2 arrival: a hard flash that settles into a slow tail (boss burst)
static func _light_curve(mode: int, q: float, age: float) -> float:
	match mode:
		1:
			return (0.25 + 0.75 * q * q) * (0.8 + 0.2 * sin(age * (7.0 + 9.0 * q))) + 0.6 * maxf(0.0, (q - 0.88) / 0.12)
		2:
			return 0.55 * pow(maxf(0.0, 1.0 - q * 5.0), 1.2) + 0.45 * pow(1.0 - q, 2.0)
	return (1.0 - q) * (1.0 - q)

func _pulse(at: Vector3, color: Color, energy: float, range_value: float, life: float, mode: int = 0) -> void:
	var index := -1
	var oldest := -1.0
	for i in range(_lights.size()):
		if float(_light_fx[i]["life"]) <= 0.0:
			index = i
			break
		var q := float(_light_fx[i]["age"]) / float(_light_fx[i]["life"])
		if q > oldest:
			oldest = q
			index = i
	if index < 0: return
	var light := _lights[index]
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.visible = true
	_light_fx[index] = {"age": 0.0, "life": life, "energy": energy, "mode": mode}

# --------------------------------------------------------------------------- #
# Status markers for body adapters (replacement for the old cone groups)
# --------------------------------------------------------------------------- #
## A ready-made looping status marker: "Burn", "Frost" or "Stun". Returns a hidden
## MeshInstance3D the adapter parents to the body root (same group names as before);
## the mesh and one material per kind are shared by every body, nothing is created
## per frame. `height` is the body height in world units (stun ring sits above it).
static func status_group(status: String, height: float = 0.9) -> MeshInstance3D:
	if _status_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for n in range(4): _quad(st, 0, n)
		_status_mesh = st.commit()
	var node := MeshInstance3D.new()
	node.name = "Stellar" + status
	node.mesh = _status_mesh
	node.material_override = _status_material(status, height, 1.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 4, 3))
	node.visible = false
	return node

## The shared marker material of one status, body height (unscaled), root scale and girth.
static func _status_material(status: String, height: float, body_scale: float, orbit: float = 0.0) -> ShaderMaterial:
	var key := "%s:%.2f:%.2f:%.2f" % [status, height, body_scale, orbit]
	if not _status_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = SHADER_STATUS
		material.render_priority = 1
		material.set_shader_parameter("sprites", SPRITES)
		material.set_shader_parameter("kind", int({"Burn": 0, "Frost": 1, "Stun": 2}.get(status, 0)))
		material.set_shader_parameter("height", height)
		material.set_shader_parameter("body_scale", body_scale)
		material.set_shader_parameter("orbit", orbit)
		_status_materials[key] = material
	return _status_materials[key]

## A body whose root is scaled (bosses stand at 2x) is measured once, when it joins the
## world: its girth (mean half-extent of its meshes at rest, world units) is remembered on
## the node, and its status marks switch to the material of that scale and girth, so the
## flames and shards circle the body instead of sitting inside it and the stun ring orbits
## its real head height. Ordinary bodies (scale 1) are left exactly as they were.
## Returns true for a scaled body.
static func fit_body(root: Node3D) -> bool:
	var body_scale := root.scale.y
	if is_equal_approx(body_scale, 1.0): return false
	var radius := _body_radius(root)
	root.set_meta(META_BODY_RADIUS, radius)
	for status in ["Burn", "Frost", "Stun"]:
		var marker := root.get_node_or_null("Stellar" + status) as MeshInstance3D
		if marker == null: continue
		var current := marker.material_override as ShaderMaterial
		if current == null or current.shader != SHADER_STATUS: continue
		marker.material_override = _status_material(status, float(current.get_shader_parameter("height")), body_scale, snappedf(radius * 0.75, 0.01))
	return true

## Mean horizontal half-extent of a body's meshes at rest, in world units (root scale
## included). Parent transforms are walked by hand: the body's children have not entered
## the tree yet when it joins the actors.
static func _body_radius(root: Node3D) -> float:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name).begins_with("Stellar"): continue
		var to_root := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk != null and walk != root:
			if walk is Node3D: to_root = (walk as Node3D).transform * to_root
			walk = walk.get_parent()
		var aabb: AABB = (mesh as MeshInstance3D).get_aabb()
		for corner in range(8):
			var point: Vector3 = to_root * aabb.get_endpoint(corner)
			low = low.min(Vector2(point.x, point.z))
			high = high.max(Vector2(point.x, point.z))
	if not low.is_finite() or not high.is_finite(): return 0.0
	return 0.25 * (high.x - low.x + high.y - low.y) * absf(root.scale.x)

# --------------------------------------------------------------------------- #
# Lookups (presentation data only)
# --------------------------------------------------------------------------- #
## Weapon family, element, sockets and colours of the hero in simulation slot `index`.
func _hero_info(index: int, sim = null) -> Dictionary:
	if index < 0: return {}
	var unit: Dictionary = {}
	if sim != null and index < sim.heroes.size():
		unit = sim.heroes[index].get("h", {}).get("unit", {})
	if unit.is_empty() and _world != null:
		var node := _world.hero_node(index)
		if node != null: unit = Roster.unit_by_id(String(node.get_meta("identity", "")))
	var id := String(unit.get("id", ""))
	if id == "": return {}
	var cached: Dictionary = _hero_cache.get(index, {})
	if String(cached.get("id", "")) == id: return cached
	var base := String(unit.get("base_id", id))
	var row: Dictionary = NativeCharacterModel.manifest().get("heroes", {}).get(base, {})
	var weapon := String(unit.get("weapon", "gun"))
	var attack := String(row.get("attack", ""))
	if attack == "": attack = "cast" if weapon in ["deck", "whip"] else "bow" if weapon == "bow" else "sword" if weapon == "sword" else "rifle"
	var sockets: Array = row.get("sockets", [])
	var lead := "R" if not sockets.is_empty() and String(sockets[0].get("bone", "")).ends_with("R") else "L"
	var info := {"id": id, "elem": String(unit.get("elem", "none")), "weapon": weapon, "attack": attack,
		"sockets": maxi(1, sockets.size()), "lead": lead, "color": Color(String(unit.get("color", "#ffffff"))),
		"effect": Color(String(row.get("effect_color", unit.get("color", "#ffffff"))))}
	_hero_cache[index] = info
	return info

## Release colour: the character's authored effect accent pulled toward its element.
static func _effect_color(info: Dictionary, elem: String) -> Color:
	var accent: Color = info.get("effect", Color.WHITE)
	if elem == "none" or elem == "": return accent
	return accent.lerp(Balance.elem_color(elem), 0.5)

## Impact size from the simulator's crit / affinity flags. Immune hits stay silent.
static func _impact_scale(e: Dictionary) -> float:
	var em := float(e.get("em", 1.0))
	if em <= 0.0: return 0.0
	var scale := 1.0
	if bool(e.get("crit", false)): scale *= 1.35
	if em >= 2.0: scale *= 1.3
	elif em <= 0.5: scale *= 0.72
	return scale

func _monster_height(sid: int) -> float:
	if _world == null: return 0.9
	var node := _world.monster_node(sid)
	if node == null: return 0.9
	var id := String(node.get_meta("_stellar_monster_id", ""))
	var row: Dictionary = NativeMonsterModel.manifest().get("monsters", {}).get(id, {})
	return float(row.get("height", 0.9)) * maxf(node.scale.y, 0.01)

## Root scale of a monster body (bosses stand at StellarModels.BOSS_SCALE).
func _monster_scale(sid: int) -> float:
	if _world == null: return 1.0
	var node := _world.monster_node(sid)
	return maxf(node.scale.y, 0.01) if node != null else 1.0

## The scaled body (a boss) whose girth contains the logical point, or null. Only scaled
## bodies are tracked, so this is a loop over at most a couple of nodes.
func _big_body_at(p: Vector2) -> Node3D:
	if _big_bodies.is_empty(): return null
	var at := world(p, 0.0)
	for i in range(_big_bodies.size() - 1, -1, -1):
		var node := _big_bodies[i]
		if not is_instance_valid(node) or not node.is_inside_tree():
			_big_bodies.remove_at(i)
			continue
		var radius := maxf(float(node.get_meta(META_BODY_RADIUS, 0.0)), 0.4)
		if Vector2(node.position.x - at.x, node.position.z - at.z).length_squared() <= radius * radius: return node
	return null

## Root scale of the boss whose body contains an event's position (1 when there is none).
func _body_scale_at(p) -> float:
	if _big_bodies.is_empty() or not (p is Vector2): return 1.0
	var node := _big_body_at(p)
	return node.scale.y if node != null else 1.0

## A deterministic pseudo-random yaw (never touches any gameplay RNG).
func _yaw() -> Basis:
	_counter += 1
	return Basis(Vector3.UP, fposmod(float(_counter) * 2.399963 + _clock * 0.7, TAU))
