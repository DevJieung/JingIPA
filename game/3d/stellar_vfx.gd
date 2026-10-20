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
##   Zones    (36)   sim.zones: the rune disc at the damage radius and, above it, the
##                   element's weather (blizzard helix, magma gouts, thunder strikes,
##                   geyser whirl, card storm) timed to the simulator's ticks; the last
##                   tick settles through a ZONE_END burst. Plus caster wind-up circles
##   Skills   (6)    whole sequences in one instance each: the Starlight Burst (a meteor
##                   falling from the top of the view, impact, shockwave to the damage
##                   radius, fragments, afterglow), the boss gate (four-second warning
##                   gather, arrival burst), the frost pulse (an ice wave with crystal
##                   spikes along its front), the level-up flare at the crystal, an elite's
##                   entrance (the boss arrival in miniature, violet) and the arrival of the
##                   five-star guardian a revival grants (2026-10-19)
##   Moments  (8)    run-level sequences, one instance each: the crystal's revival, a stage
##                   clear (the last one settles into a held picture and seals every gate),
##                   the reveal of a new battlefield (one sweep from the crystal and a beacon
##                   per gate), the final boss's extra layers, a wave's start (the gate
##                   beacons flare) and its clear (a light sweeping the field). Hidden while
##                   idle.
## plus two energy domes, the Guardian's aegis (a faceted gem around the revived crystal),
## the road ribbons of a battlefield reveal and six pooled OmniLights for the brightest pulses.
## Instances animate in their shaders from `vfx_time`, a clock that only advances in
## update(dt): a paused battle freezes every effect, and no node, mesh or material is
## created after start-up (one exception: the road ribbon mesh is refilled when a new
## battlefield opens, in the paused frame its world is rebuilt in). The `effects` array
## is shared with StellarWorld and acts as the one-shot budget (EFFECT_LIMIT); the pools
## recycle their oldest slot when full.
## The world is paused (dt 0) under every card and panel, so what is alive when a pause
## begins stays on screen for as long as the player reads. Two rules follow: a new
## battlefield (arena_stage) and a new run start from nothing (_clear_field), and a won
## run freezes on the last clear at rest and nothing else (_settle_victory).
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
const MAX_MOMENTS := 8
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
const ZONE_SPRITES: Texture2D = preload("res://art/vfx/zone_sprites.png")
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
const SHADER_MOMENT: Shader = preload("res://art/vfx/vfx_moment.gdshader")
const SHADER_MOMENT_MIX: Shader = preload("res://art/vfx/vfx_moment_mix.gdshader")
const SHADER_AEGIS: Shader = preload("res://art/vfx/vfx_aegis.gdshader")
const SHADER_AEGIS_BASE: Shader = preload("res://art/vfx/vfx_aegis_base.gdshader")
const SHADER_ROAD: Shader = preload("res://art/vfx/vfx_road.gdshader")
const SHADER_ROAD_BASE: Shader = preload("res://art/vfx/vfx_road_base.gdshader")
const SHADER_ELITE: Shader = preload("res://art/vfx/vfx_elite.gdshader")
## Shared looping status materials (burn / frost / stun) handed to body adapters by
## status_group(); the live world's VFX node keeps their clock in step with the battle.
static var _status_materials: Dictionary = {}
static var _status_mesh: ArrayMesh
static var _elite_mesh: ArrayMesh

## Burst kinds; the shaders key their timing tables on this order.
enum Kind { HIT, SPLASH, ZONE_TICK, DIE, LEAK, BLOCK, PUSH, FROST, STUN, CURSE, SPAWN, WILDFIRE,
	BLAST, FREEZE, WARD, MUZZLE_SMOKE, RIC_SPARK, BEAM_CAP, BOLT_CAP, CAST_RELEASE, SLASH_HIT,
	SEAL, SCATTER, CRIT, ZONE_END }
## Seconds a burst slot stays reserved: at least the longest layer of that kind.
const KIND_LIFE := [0.50, 0.75, 0.55, 1.05, 0.60, 0.45, 0.35, 0.95, 0.45, 0.65, 0.90, 1.10,
	1.30, 1.40, 0.90, 0.62, 0.25, 0.30, 0.30, 0.50, 0.44, 0.82, 0.96, 0.55, 2.30]
const ELEM_INDEX := {"none": 0, "fire": 1, "ice": 2, "elec": 3, "water": 4}
const WEAPON_INDEX := {"rifle": 0, "gun": 0, "bow": 1, "cast": 2, "artillery": 3, "sword": 4, "tool": 5}
## Projectile head sprites: 0 tracer, 1 arrow, 2 shell, 3 bead, 4 orb, 5 crescent.
const BULLET_SIZE := {"shot": 0.13, "pierce": 0.15, "splash": 0.19, "chain": 0.14, "ricochet": 0.12}
const TRAIL_LENGTH := {"shot": 1.05, "pierce": 1.65, "splash": 0.85, "chain": 1.15, "ricochet": 0.95}
## Budget priority per burst kind: when the shared 72-slot budget is full, a new
## effect evicts the oldest live effect of lower or equal priority (skills never drop).
const KIND_PRIORITY := [0, 1, 0, 2, 3, 2, 1, 1, 1, 1, 2, 2, 4, 4, 4, 0, 0, 1, 1, 1, 0, 2, 2, 0, 1]
## Per-frame caps keep bulk events (a freeze slowing 40 bodies) from flooding one frame.
const FRAME_CAPS := {"hit": 10, "splash": 6, "frost": 4, "stun": 5, "die": 8, "push": 6, "zone_tick": 8}
## Girth of a scaled body in world units, measured once by fit_body().
const META_BODY_RADIUS := "_stellar_body_radius"
## Hover height of a flying body (NativeMonsterModel.FLY_META, world units above the
## ground; 0 on walkers): hits, status marks and deaths on it are drawn up there.
const META_FLY := "_stellar_fly_height"
## Height (logical units) of an ordinary swarm body: a kill's pop grows with die.h / this.
const BODY_HEIGHT_BASE := 52.0
const PORTAL_COLOR := Color("#9d86ff")
const PUSH_COLOR := Color("#e8f1ff")
## Sequence kinds of the Skills pool (vfx_skill*.gdshader key their timelines on this order).
enum SkillKind { BLAST, BOSS_WARNING, BOSS_BURST, FREEZE, LEVELUP, ELITE_BURST, HERO_ARRIVE }
## Starlight Burst: the meteor falls for BLAST_FALL seconds after the cast (the simulator's
## damage is immediate; the lock-on sigil marks the struck radius from the cast moment),
## then the impact layers run out over the rest of BLAST_LIFE. The shaders' HIT constant
## is this value.
const BLAST_FALL := 0.32
const BLAST_LIFE := 2.1
const BLAST_HOT := Color("#fff4d6")
const BLAST_LIGHT_REACH := 10.0
## Frost pulse: the ice wave crosses its reach in FREEZE_WAVE seconds (vfx_skill FREEZE_SEC);
## the snow and fog behind it are gone by FREEZE_LIFE.
const FREEZE_WAVE := 0.95
const FREEZE_LIFE := 2.2
## Level-up: a star rises from the crystal for LEVELUP_RISE seconds and bursts.
const LEVELUP_RISE := 0.45
const LEVELUP_LIFE := 1.3
## Boss gate: crimson gather, violet light; R is the arrival footprint (the 2.8x boss).
const BOSS_RED := Color("#ff3d5c")
const BOSS_VIOLET := Color("#9a4dff")
const BOSS_SIZE := 1.5
const BOSS_BURST_LIFE := 2.4
const STUN_COLOR := Color("#ffe38b")
const CURSE_COLOR := Color("#7a4fc9")
## Sequence kinds of the Moments pool (vfx_moment*.gdshader key their timelines on this order).
enum MomentKind { REVIVE, STAGE_CLEAR, STAGE_SWEEP, GATE_BEACON, FINAL_WARNING, FINAL_BURST, GATE_SEAL, WAVE_CLEAR }
## Crystal revival (Guardian's blessing). The simulator has already revived the crystal and
## stopped every monster when the event arrives; the picture tells it as a break and a
## reforming: REVIVE_FLASH seconds of collapse, the flash, a shockwave that crosses the field
## in REVIVE_WAVE seconds (a seal closes on each monster as it passes), the shards drawn
## back in, the crystal whole again at REVIVE_WHOLE, and the aegis for the rest of `sec`.
const REVIVE_FLASH := 0.26
const REVIVE_WAVE := 0.50
const REVIVE_WHOLE := 0.94
const SEAL_CAP := 24
## Additive gold has to be deeper than Look.GOLD to stay gold on a pale road.
const BLESSING_LIGHT := Color("#ffc24a")
const SEAL_COLOR := Color("#ffbd47")
## The aegis gem: base radius and height in world units (the altar is 1.15 wide, the
## crystal 1.95 tall, besiegers stand 1.36 from the centre: they stay outside the gem).
const AEGIS_RADIUS := 1.12
const AEGIS_HEIGHT := 2.55
const AEGIS_SPIN := 0.45
## The revival reshapes the real crystal for a second (it shatters and regrows); false
## leaves the crystal node alone and only the effect layers tell the story.
const REVIVE_DRIVES_CRYSTAL := true
## Stage clear: the victory wave crosses the field in CLEAR_WAVE seconds and each escort
## turns to haze as it passes (scatter_delay). Nothing of it may outlive `sec`: the world
## is rebuilt then and the next battlefield opens paused under its card.
const CLEAR_WAVE := 0.60
## Every escort gets its haze (the arena holds at most 48 bodies; they are spread over the
## 0.6 s the wave needs, inside the burst pool of 64).
const SCATTER_CAP := 48
## Radians a fleeing escort's heading may turn off the straight line from the crystal.
const SCATTER_SPREAD := 0.6
const SPIRIT_COLOR := Color("#cfe2ff")
## The last stage's clear (arena_stage_clear with final): the run is won. A second wave
## locks on the rim as a gold ring, the guardian crest is stamped on the plaza and on every
## gate (the gates are sealed), a quiet column stays on the crystal. Everything that moves
## is over by FINAL_REST seconds; the result panel opens at `sec` and freezes the picture,
## so from FINAL_REST on it is a still. It stays for FINAL_HOLD more seconds if time runs on.
const FINAL_REST := 1.62
const FINAL_CREST := 0.42
const FINAL_HOLD := 3.6
## New battlefield: the scan from the crystal reaches the rim at SWEEP_ARRIVE, the gate
## beacons flare and a runner leaves every gate down its road at ROAD_SPEED units a second.
const SWEEP_ARRIVE := 0.75
const SWEEP_LIFE := 2.1
const BEACON_LIFE := 2.75
const ROAD_SPEED := 30.0
const ROAD_HEIGHT := 0.085
## The same coral the battlefield card and the minimap mark gates with.
const GATE_COLOR := Color("#ff9a7a")
const STAR_PALE := Color("#ffe9c2")
const GATE_INSET := 28.0
## Final boss: the ordinary gate grown by FINAL_SCALE plus the dark sun's layers.
const FINAL_SCALE := 1.3
const FINAL_AFTERSHOCK := 0.24
const FINAL_BURST_LIFE := 3.5
const FINAL_EMBER := Color("#ffb347")
## Waves (2026-10-19, feedback O5; ArenaSim arena_wave / arena_wave_clear / arena_elite).
## A wave starts: every gate's beacon flares at once (the GATE_BEACON sequence entered
## WAVE_BEACON_SKIP seconds in, right at its flare) and a runner leaves every gate down its
## road with only the mouths marked (the road ribbon restarted with scan_marks 0). Coral for
## an ordinary wave, violet for an elite wave; the boss wave has no beacons (its own warning
## and arrival hold the stage), only crimson runners.
const WAVE_BEACON_SKIP := SWEEP_ARRIVE - 0.04
## A wave is beaten: a thin light sweeps from the crystal to the rim in WAVE_SWEEP seconds
## (vfx_moment.gdshaderinc wave_sweep) with glints popping where it passes; gone by
## WAVE_CLEAR_LIFE. Lighter than a stage clear, because it comes ten times a stage.
const WAVE_SWEEP := 0.85
const WAVE_CLEAR_LIFE := 1.25
## With a mend (the defence's heal, arena_wave_clear heal / arena_heal) the sequence also
## closes a cyan ring on the crystal, raises halos up it and glints on its tip (the stage
## clear's mend layers), so it lives MEND_LIFE. A heal outside a wave clear (a constellation
## node) plays the mend alone.
const MEND_LIFE := 1.6
## Elites: the colour of their line, aura, entrance and wave (the HUD's elite bar may share
## it), and the entrance's footprint R in world units (the boss gate is BOSS_SIZE 1.5; the
## shaders scale the sequence by R / 1.5).
const ELITE_COLOR := Color("#9b62ff")
const ELITE_SIZE := 0.95
const ELITE_BURST_LIFE := 2.0
## Roads body colours (linear) per wave tone: ordinary (the coral of the reveal), elite, boss.
const ROAD_BODY := {"coral": [Vector3(0.85, 0.23, 0.09), Vector3(1.0, 0.62, 0.36)],
	"elite": [Vector3(0.36, 0.08, 0.62), Vector3(0.86, 0.66, 1.0)],
	"boss": [Vector3(0.55, 0.04, 0.12), Vector3(1.0, 0.48, 0.52)]}
## The five-star guardian a revival grants (arena_revive unit / tier / where): its arrival
## follows the crystal's reforming (REVIVE_WHOLE). On the field a gold star falls onto its
## spot for ARRIVE_FALL seconds (a ring tightens there as it comes) and lands: flash, column,
## ground ring, five big stars thrown into a crown, sparkles; the world has held the body out
## of sight until then and shows it in the column with its drop-in (NativeCharacterModel's
## spawn beat). On the bench (or when no body turns up within ARRIVE_WAIT) the star climbs
## out of the crystal and the revival's aegis dome, bursts just over the dome and its five
## stars circle the dome's foot — low and outside the dome, inside the ring of default posts
## (2.24 u), so the crown sits on no guardian's head. ARRIVE_SIZE is the ring R.
const ARRIVE_FALL := 0.28
const ARRIVE_SIZE := 0.9
const ARRIVE_LIFE := 1.75
const ARRIVE_BENCH_LIFE := 2.3
const ARRIVE_WAIT := 0.6
## Bosses and elites walk through guardians (2026-10-19, feedback F4 / PLAN M5: the simulator
## no longer lets a guardian's body stop them). It is drawn as a shove, never as a block: a
## puff of trampled dust under the guardian when the big body reaches it and every
## TRAMPLE_GAP seconds while it pushes through, and the guardian's figure is nudged aside
## (StellarWorld.shove_hero, up to TRAMPLE_SHOVE world units, eased back after). Visual only.
const TRAMPLE_GAP := 0.4
const TRAMPLE_SHOVE := 0.34
const TRAMPLE_DUST := Color(0.46, 0.38, 0.30)

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
var _moments: MultiMeshInstance3D
var _live_moments := 0
var _aegis: MeshInstance3D
var _aegis_fx := {"age": 0.0, "life": 0.0}
var _roads: MeshInstance3D
var _roads_fx := {"age": 0.0, "life": 0.0}
var _reform := {"t": -1.0}               # the crystal node being reshaped by a revival
var _boss_fall := {"clock": -99.0}       # where the last scaled body died (stage clear link)
var _sim_ref: WeakRef                    # the simulator of the last sync (read only)
var _final_stage := false
var _reveal_pending := false             # arena_stage arrived this frame (spawned in update)
var _reveal_at := Vector3.ZERO
var _won_seen := false                   # the simulator's victory has been settled
var _arrivals: Array[Dictionary] = []     # revival gifts waiting for their arrival beat
var _roads_key := ""                     # the layout the road ribbon mesh was built for
var _roads_longest := 0.0                # its longest road (world units)
var _trample: Dictionary = {}            # "sid:hero" -> seconds to the next dust puff
var _heal_stash := 0.0                   # arena_heal seen this frame, not yet shown
var _trample_clock := 0.0
## Frames the idle Moments pool, aegis and road ribbons are still drawn after start-up
## (nothing shows: every part is at alpha 0). GL compiles a shader at its first draw; this
## puts that cost on the loading frames instead of on the frame a stage boss falls.
var _warm := 3
var _road_materials: Array[ShaderMaterial] = []
var _domes: Array[MeshInstance3D] = []
var _dome_fx: Array[Dictionary] = []
var _lights: Array[OmniLight3D] = []
var _light_fx: Array[Dictionary] = []
var _next := {"dome": 0}
var _generation := {"burst": [], "beam": [], "slash": [], "skill": [], "moment": []}
var _free := {"burst": [], "beam": [], "slash": [], "skill": [], "moment": []}
var _pending_fires: Array[Dictionary] = []
var _pending_hits: Array[Dictionary] = []   # this tick's melee hits, timed after their fire
var _delayed: Array[Dictionary] = []        # bursts / pulses waiting on the effect clock
var _aims: Dictionary = {}
var _melee: Dictionary = {}                 # src -> last melee release (origin, dir, reach, sign)
var _big_bodies: Array[Node3D] = []         # live bodies whose root is scaled (bosses)
var _zone_live: Dictionary = {}             # zones drawn last frame (key -> {p, r, el, c})
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
	var sizes := {"burst": MAX_BURSTS, "beam": MAX_BEAMS, "slash": MAX_SLASHES, "skill": MAX_SKILLS, "moment": MAX_MOMENTS}
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
	_moments = _pool("Moments", _moment_mesh(), MAX_MOMENTS, 1, MAX_MOMENTS)
	_aegis = MeshInstance3D.new()
	_aegis.name = "Aegis"
	_aegis.mesh = _aegis_mesh()
	_aegis.scale = Vector3(AEGIS_RADIUS, AEGIS_HEIGHT, AEGIS_RADIUS)
	_aegis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aegis)
	_roads = MeshInstance3D.new()
	_roads.name = "Roads"
	_roads.mesh = ArrayMesh.new()
	_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_roads.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 3, 40))
	add_child(_roads)
	_road_materials.assign([_material(SHADER_ROAD_BASE, -3), _material(SHADER_ROAD, -1)])
	# One buried quad so the road shaders are compiled with the others (see _warm).
	var warm := SurfaceTool.new()
	warm.begin(Mesh.PRIMITIVE_TRIANGLES)
	_road_ribbon(warm, PackedVector2Array([Balance.ARENA_CENTER, Balance.ARENA_CENTER + Vector2(40, 0)]), 0.1)
	var warm_arrays := warm.commit_to_arrays()
	for layer in range(2):
		(_roads.mesh as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warm_arrays)
		_roads.mesh.surface_set_material(layer, _road_materials[layer])
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
	material.set_shader_parameter("zone_sprites", ZONE_SPRITES)
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

## Additive: ground ring, flash, 8 sparks, 8 motes, facing ring, plume, 6 accents.
## Mix: scorch, 2 puffs, 4 debris.
func _burst_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, 0, 0)
	_quad(st, 1, 0)
	for n in range(8): _quad(st, 2, n)
	for n in range(8): _quad(st, 3, n)
	_quad(st, 5, 0)
	_quad(st, 7, 0)
	for n in range(6): _quad(st, 8, n)
	st.set_material(_material(SHADER_BURST, -1))
	var mesh := st.commit()
	var soft := SurfaceTool.new()
	soft.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(soft, 6, 0)
	for n in range(2): _quad(soft, 4, n)
	for n in range(4): _quad(soft, 9, n)
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
## afterglow, sky flare, 4 lightning bolts, facing ring, crack glow, 10 trail embers. Mix
## surface: ground colour and sigil body (first, so everything else lies on them; they only
## draw on bright fields), cracks, dark ring, 6 smoke puffs, 10 debris chunks, 8 mist
## wisps, 5 trail smoke puffs.
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
	for n in range(10): _quad(st, 14, n)
	st.set_material(_material(SHADER_SKILL, 1))
	var mesh := st.commit()
	var soft := SurfaceTool.new()
	soft.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [26, 25, 20, 21]: _quad(soft, part, 0)
	for n in range(6): _quad(soft, 22, n)
	for n in range(10): _quad(soft, 23, n)
	for n in range(8): _quad(soft, 24, n)
	for n in range(5): _quad(soft, 27, n)
	soft.set_material(_material(SHADER_SKILL_MIX, -3))
	soft.commit(mesh)
	return mesh

## One run-level sequence per instance (vfx_moment / vfx_moment_mix), built like the Skills
## mesh. Additive surface: 3 ground rings, 2 ground sprites, 2 flashes, 2 flares, 2 pillars,
## 16 shards, 16 motes, 4 marks, 6 lightning bolts. Mix surface (the bodies the light
## rides on): 3 rings, 3 discs, 6 smoke puffs, 8 stones, 4 marks, 16 shards.
func _moment_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in range(3): _quad(st, 0, n)
	for part in [1, 2, 3, 4]:
		for n in range(2): _quad(st, part, n)
	for n in range(16): _quad(st, 5, n)
	for n in range(16): _quad(st, 6, n)
	for n in range(4): _quad(st, 7, n)
	for n in range(6): _quad(st, 8, n)
	st.set_material(_material(SHADER_MOMENT, 1))
	var mesh := st.commit()
	var soft := SurfaceTool.new()
	soft.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [20, 21]:
		for n in range(3): _quad(soft, part, n)
	for n in range(6): _quad(soft, 22, n)
	for n in range(8): _quad(soft, 23, n)
	for n in range(4): _quad(soft, 24, n)
	for n in range(16): _quad(soft, 25, n)
	soft.set_material(_material(SHADER_MOMENT_MIX, -3))
	soft.commit(mesh)
	return mesh

## The Guardian's aegis: a gem of unit height and unit base radius cut in three tiers of
## eight (base, belt turned half a side, shoulder, tip), 40 flat facets. Each triangle
## carries barycentric weights in UV (the edge lines) and its own hash in UV2.x. Two
## surfaces over the same facets: the gold body (alpha-blended), then the additive light.
func _aegis_mesh() -> ArrayMesh:
	var tiers := [[0.0, 1.0, 0.0], [0.34, 1.06, 0.5], [0.74, 0.70, 0.0]]   # height, radius, turn
	var sides := 8
	var facets: Array = []
	var ring := func(tier: Array, n: int) -> Vector3:
		var angle := TAU * (float(n) + float(tier[2])) / sides
		return Vector3(cos(angle) * float(tier[1]), float(tier[0]), sin(angle) * float(tier[1]))
	for band in range(tiers.size() - 1):
		var low: Array = tiers[band]
		var high: Array = tiers[band + 1]
		# The upper tier is turned half a side against the lower one: an antiprism band.
		var lead := 0 if float(high[2]) > float(low[2]) else 1
		for n in range(sides):
			facets.append([ring.call(low, n), ring.call(low, n + 1), ring.call(high, n + lead)])
			facets.append([ring.call(high, n), ring.call(high, n + 1), ring.call(low, n + 1 - lead)])
	var tip := Vector3(0, 1, 0)
	for n in range(sides):
		facets.append([ring.call(tiers[-1], n), ring.call(tiers[-1], n + 1), tip])
	var weights := [Vector2(1, 0), Vector2(0, 1), Vector2(0, 0)]
	var mesh: ArrayMesh = null
	for layer in range(2):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(facets.size()):
			var corners: Array = facets[index]
			var normal: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized()
			var centre: Vector3 = (corners[0] + corners[1] + corners[2]) / 3.0
			if normal.dot(Vector3(centre.x, 0.25, centre.z)) < 0.0: normal = -normal
			var facet := fposmod(float(index) * 0.6180339 + 0.137, 1.0)
			for corner in range(3):
				st.set_normal(normal)
				st.set_uv(weights[corner])
				st.set_uv2(Vector2(facet, float(index)))
				st.add_vertex(corners[corner])
		st.set_material(_material(SHADER_AEGIS_BASE, 1) if layer == 0 else _material(SHADER_AEGIS, 2))
		mesh = st.commit(mesh)
	return mesh

## Mix (under): dark base, 4 mist puffs, the floor's body. Additive: rune disc, 8 motes,
## 16 vortex shards, 4 veils, 6 strikes, 2 tick caps, landing column, crown, floor glow.
func _zone_mesh() -> ArrayMesh:
	var base := SurfaceTool.new()
	base.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(base, 0, 0)
	_quad(base, 9, 0)
	for n in range(4): _quad(base, 8, n)
	base.set_material(_material(SHADER_ZONE_BASE, -4))
	var mesh := base.commit()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, 0, 0)
	_quad(st, 8, 0)
	for n in range(8): _quad(st, 1, n)
	for n in range(4): _quad(st, 3, n)
	for n in range(16): _quad(st, 2, n)
	for n in range(6): _quad(st, 4, n)
	for n in range(2): _quad(st, 5, n)
	_quad(st, 6, 0)
	_quad(st, 7, 0)
	st.set_material(_material(SHADER_ZONE, -2))
	st.commit(mesh)
	return mesh

# --------------------------------------------------------------------------- #
# Per-frame presentation from the simulator's current lists
# --------------------------------------------------------------------------- #
func sync(sim, _time: float) -> void:
	if _bullets == null: return
	_frame_counts.clear()
	if _sim_ref == null or _sim_ref.get_ref() != sim:
		# Another run on this world (a retry, a restored save): nothing of the last one
		# may be left on its first, paused picture. This frame's events were handled
		# before sync(): a reveal the new run has just announced (arena_stage for its
		# first battlefield) stays pending and is born at the end of update().
		if _sim_ref != null: _clear_field()
		_sim_ref = weakref(sim)
		_won_seen = false
	_final_stage = sim.has_method("final_stage") and bool(sim.final_stage())
	var won: bool = "won" in sim and bool(sim.won)
	if won and not _won_seen: _settle_victory()
	_won_seen = won
	# The revival's untouchable window is simulator state: it carries over a stage change
	# and a restored save, and neither sends arena_revive. Show the rest of the aegis from
	# that state (no burst) so the protection that is still running can be read.
	if not won and float(_aegis_fx["life"]) <= 0.0 and "invuln_t" in sim and float(sim.invuln_t) > 0.1:
		_resume_aegis(float(sim.invuln_t))
	_sync_wash()
	_sync_bullets(sim)
	_sync_muzzles(sim)
	_sync_zones(sim)
	_flush_fires(sim)
	_sync_trample(sim)
	if _heal_stash > 0.0:
		# A heal on its own (a constellation node): the mend without the sweep.
		var centre := world(Balance.ARENA_CENTER, 0.0)
		_moment(MomentKind.WAVE_CLEAR, centre, Basis.IDENTITY, ArenaGeometry.RADIUS / UNIT, Look.CRYSTAL,
			2.0 + _mend_amount(_heal_stash), 0.0, MEND_LIFE)
		_delayed.append({"at": _clock + 0.35, "kind": -1, "origin": centre + Vector3(0, 1.0, 0), "color": Look.CRYSTAL,
			"pulse": 2.6, "range": 5.0, "life": 0.8})
		_heal_stash = 0.0

## 0..1 strength of the crystal's mend for `heal` crystal points (0 when nothing mended):
## half at once, full from a tenth of the crystal.
func _mend_amount(heal: float) -> float:
	if heal <= 0.0: return 0.0
	var sim = _sim_ref.get_ref() if _sim_ref != null else null
	var top := float(sim.crystal_max) if sim != null and "crystal_max" in sim else 1200.0
	return clampf(0.5 + 5.0 * heal / maxf(top, 1.0), 0.5, 1.0)

## A boss or an elite pushing through a guardian (see TRAMPLE_GAP).
func _sync_trample(sim) -> void:
	var dt := maxf(_clock - _trample_clock, 0.0)
	_trample_clock = _clock
	if _world == null or sim.heroes.is_empty():
		_trample.clear()
		return
	var seen: Dictionary = {}
	for mo in sim.monsters:
		var row = mo.get("m", {})
		var boss: bool = row is Dictionary and String(row.get("kind", "")) == "boss"
		if not boss and not bool(mo.get("elite", false)): continue
		if float(mo.get("hp", 1.0)) <= 0.0: continue
		var sid := int(mo.get("spawn_id", 0))
		var node := _world.monster_node(sid)
		var girth := float(node.get_meta(META_BODY_RADIUS, 0.45)) if node != null else 0.45
		var reach := Balance.ARENA_HERO_RADIUS + girth * UNIT * 0.8
		var p := BattleSim.mpos(mo)
		var vel: Vector2 = mo.get("vel", Vector2.ZERO)
		var heading := vel.normalized() if vel.length_squared() > 0.01 else (Balance.ARENA_CENTER - p).normalized()
		for i in range(sim.heroes.size()):
			if not sim.heroes[i].has("pos"): continue
			var at: Vector2 = sim.heroes[i]["pos"]
			var gap := at.distance_to(p)
			if gap >= reach: continue
			var key := "%d:%d" % [sid, i]
			seen[key] = true
			var left := float(_trample.get(key, 0.0)) - dt
			# Aside, away from the line the big body walks, harder the deeper it is in.
			var rel := at - p
			var side := Vector2(-heading.y, heading.x)
			if rel.dot(side) < 0.0: side = -side
			if not _trample.has(key) or left <= 0.0:
				var facing := Basis.looking_at(Vector3(heading.x, 0.0, heading.y), Vector3.UP)
				_burst(Kind.SPLASH, world(at, 0.0), facing, TRAMPLE_DUST, 1.0 if boss else 0.7, 0.0)
				if not _trample.has(key):
					# The first contact: the guardian is jostled (the stumble ring, sideways).
					_burst(Kind.PUSH, world(at, 0.0), Basis.looking_at(Vector3(side.x, 0.0, side.y), Vector3.UP), PUSH_COLOR, 1.0, 0.0)
				left = TRAMPLE_GAP
			_trample[key] = left
			var push := TRAMPLE_SHOVE * (1.0 - gap / reach) * (1.0 if boss else 0.7)
			if _world.has_method("shove_hero"): _world.call("shove_hero", i, Vector3(side.x, 0.0, side.y) * push)
	for key in _trample.keys():
		if not seen.has(key): _trample.erase(key)

## Bright snow and ice fields wash additive layers out to white; tell the shaders.
## The arena states how bright its playfield is itself (ArenaWorld.ground_wash, 0 dark
## soil .. 1 snow, set per battlefield); worlds without it fall back to the biome rule.
func _sync_wash() -> void:
	if _world == null: return
	var hint := float(_world.get("ground_wash")) if "ground_wash" in _world else -1.0
	var key := "%s|%.2f" % [_world.theme_id, hint]
	if key == _wash_theme: return
	_wash_theme = key
	var bright := 0.0
	if hint >= 0.0:
		bright = clampf(hint, 0.0, 1.0)
	else:
		for theme in Roster.THEMES:
			if String(theme.get("id", "")) == _world.theme_id and String(theme.get("main_body", "")) in ["aqua", "frost"]:
				bright = 1.0
	for material in _materials: material.set_shader_parameter("vfx_wash", bright)

func _sync_bullets(sim) -> void:
	var multimesh := _bullets.multimesh
	var count := mini(MAX_BULLETS, sim.bullets.size())
	multimesh.visible_instance_count = count
	# A revival's guardian before its arrival beat is not shown yet, nor are its shots.
	var hidden: Dictionary = {}
	if _world != null and _world.has_held(): hidden = _world.held_slots()
	for i in range(count):
		var b: Dictionary = sim.bullets[i]
		if not hidden.is_empty() and hidden.has(int(b.get("src", -1))):
			multimesh.set_instance_transform(i, PARKED)
			continue
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
			if node == null or not node.visible or not node.has_method("fire_strength") or not node.has_method("weapon_transform"): continue
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
	var live: Dictionary = {}
	for z in sim.zones:
		if n >= MAX_ZONES: break
		var radius := float(z.get("r", 128.0)) / UNIT
		var at := Vector2(z["at"])
		multimesh.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)), world(at, 0.0)))
		var color := Color(z.get("c", Color.WHITE))
		color.a = 1.0 - float(z.get("n", 0)) / maxf(1.0, float(z.get("max", 1)))
		multimesh.set_instance_color(n, color)
		var elem := String(z.get("el", "none"))
		multimesh.set_instance_custom_data(n, Color(float(z.get("t", 0.0)), float(z.get("delay", 0.26)),
			float(z.get("tick", 0.25)), float(ELEM_INDEX.get(elem, 0))))
		# A zone that has landed and vanishes from the list has run its last tick: it
		# settles (ZONE_END). One that never landed (a run that ended) just goes.
		if float(z.get("t", 0.0)) >= float(z.get("delay", 0.26)):
			live["%.1f,%.1f,%d" % [at.x, at.y, int(z.get("src", -1))]] = {"p": at, "r": radius, "el": elem, "c": Color(z.get("c", Color.WHITE))}
		n += 1
	for key in _zone_live:
		if live.has(key): continue
		var gone: Dictionary = _zone_live[key]
		var elem_index := float(ELEM_INDEX.get(String(gone["el"]), 0))
		var tint: Color = Balance.elem_color(String(gone["el"])) if String(gone["el"]) != "none" else Color(gone["c"])
		_burst(Kind.ZONE_END, world(gone["p"], 0.0), _yaw(), Color(gone["c"]), float(gone["r"]), elem_index)
		_pulse(world(gone["p"], 0.7), tint, 2.6, float(gone["r"]) * 2.2, 0.45)
	_zone_live = live
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
		if (node != null and not node.visible) or (node == null and _world != null and _world.has_held() and _world.held_slots().has(src)):
			# A revival's guardian before its arrival beat: the body is not shown yet (or its
			# model is still loading).
			_aims.erase(src)
			continue
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
	var origin := world(p, clampf(_monster_height(sid) * 0.55, 0.3, 1.1 * body) + _fly_height(e))
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
		"die":
			if bool(e.get("scatter", false)):
				_scatter(e)
				return
			# A scaled body (a boss) fell here: a stage clear in the same tick links to it.
			if e.get("p") is Vector2 and _big_body_at(e["p"]) != null:
				_boss_fall = {"clock": _clock, "p": e["p"]}
		"zone":
			# The disc itself is drawn from sim.zones; this is the light of its landing,
			# timed to the delay the simulator gave the telegraph.
			var p: Vector2 = e.get("p", Vector2.ZERO)
			var elem_name := String(e.get("el", "none"))
			var tint := Balance.elem_color(elem_name) if elem_name != "none" else Color(e.get("c", Color.WHITE))
			_delayed.append({"at": _clock + float(e.get("delay", 0.26)), "kind": -1, "origin": world(p, 0.6),
				"color": tint, "pulse": 3.0, "range": float(e.get("r", 128.0)) / UNIT * 2.0, "life": 0.3})
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
			# Sparks spray on through the body along the shot; a hovering body is hit
			# up where it flies; a crit or weak-point hit is its own, bigger burst and
			# the body's flash takes the element's colour.
			var big := bool(e.get("crit", false)) or float(e.get("em", 1.0)) >= 2.0
			var fly := _fly_height(e)
			_burst(Kind.CRIT if big else Kind.HIT, world(p, fly), _travel(int(e.get("src", -1)), p), color, scale, elem, body)
			if big:
				_accent(int(e.get("sid", 0)), String(e.get("el", "none")), scale)
				if _hit_light_gap <= 0.0:
					_hit_light_gap = 0.08
					_pulse(world(p, 0.6 + fly), color, 1.6 * scale, 2.2, 0.14)
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
			# The pop grows with the body: a tank's end is a bigger event than an imp's.
			var p: Vector2 = e.get("p", Vector2.ZERO)
			var size := clampf(float(e.get("h", BODY_HEIGHT_BASE)) / BODY_HEIGHT_BASE, 0.9, 1.6)
			var fly := _fly_height(e)
			_burst(Kind.DIE, world(p, fly), _yaw(), color, size, elem, body)
			_pulse(world(p, 0.5 + fly), color.lightened(0.3), 1.3 * size, 2.2 + 0.6 * (size - 1.0), 0.35)
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
			_burst(Kind.PUSH, world(p, _fly_height(e)), facing, PUSH_COLOR, 1.0, 0.0, body)
		"frost":
			_burst(Kind.FROST, world(Vector2(e.get("p", Vector2.ZERO)), _fly_height(e)), _yaw(), Look.ICE, 1.0, 2.0, body)
		"stun":
			var sid := int(e.get("sid", 0))
			_burst(Kind.STUN, world(Vector2(e.get("p", Vector2.ZERO)), _fly_height(e)), _yaw(), STUN_COLOR, _monster_height(sid) + 0.12 * _monster_scale(sid), 3.0, body)
		"curse":
			_burst(Kind.CURSE, world(Vector2(e.get("p", Vector2.ZERO)), _fly_height(e)), _yaw(), CURSE_COLOR, 1.0, 0.0, body)
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
##   arena_levelup       p (the crystal), level: a short gold flare rising from the crystal
##                       (the HUD's popup is the UI's)
##   arena_boss_warning  p (the gate the boss will come through), sec (seconds until it does;
##                       the gather runs exactly that long and hands over to the burst).
##                       On the last stage (final in the event, else read from the simulator)
##                       the gate is larger and a dark sun gathers over it.
##   arena_boss          p (where the boss stands as it arrives), final (the last stage's boss)
##   arena_revive        p (crystal), r (field radius), sec (seconds the crystal cannot be hurt:
##                       the aegis lasts exactly that long), stun
##   arena_stage_clear   p, heal (crystal health restored), sec (seconds until the world is
##                       rebuilt: every layer is gone by then), final (the last stage: the
##                       run ends in victory at `sec` and the result panel freezes the
##                       picture, so this one settles into a still by FINAL_REST)
##   arena_stage         p: a battlefield has just been built and is paused under its card
##                       (every stage, the run's first included; a restored run sends
##                       none); everything born before it is released first
##   arena_revive        (2026-10-19) also unit, tier, where ("field" | "bench"): the
##                       five-star guardian it grants arrives after the reforming
##   arena_wave          wave, total, elite, boss: a wave starts (gate beacons, runners)
##   arena_wave_clear    wave, gold, prep, heal: it is beaten (the sweep of light, the mend)
##   arena_heal          n: the crystal mended (shown with the wave clear, or alone)
##   arena_elite         p, sid: an elite steps in (a small violet boss arrival)
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
			# The impact light reaches 3.6 R, capped at BLAST_LIGHT_REACH so the wider radius
			# awaiting approval (160) does not light the whole field (unchanged at 110).
			_delayed.append({"at": _clock + BLAST_FALL, "kind": -1, "origin": at + Vector3(0, 0.8, 0),
				"color": BLAST_HOT, "pulse": 9.0, "range": minf(radius * 3.6, BLAST_LIGHT_REACH), "life": 0.9})
		"arena_freeze":
			# An ice wave from the crystal with crystal spikes along its front (one Skills
			# instance); the per-monster frost bursts follow from the simulator's own events.
			_skill(SkillKind.FREEZE, at, minf(radius * 0.36, 10.5), Look.ICE, 0.0, FREEZE_LIFE)
			_pulse(at + Vector3(0, 0.8, 0), Look.ICE_DEEP, 4.5, 8.5, 0.6)
			_delayed.append({"at": _clock + FREEZE_WAVE * 0.5, "kind": -1, "origin": at + Vector3(0, 0.6, 0),
				"color": Look.ICE, "pulse": 2.0, "range": 12.0, "life": 0.5})
		"arena_levelup":
			_skill(SkillKind.LEVELUP, at, Balance.ALTAR_R / UNIT, Look.GOLD, 0.0, LEVELUP_LIFE)
			_delayed.append({"at": _clock + LEVELUP_RISE, "kind": -1, "origin": at + Vector3(0, 3.0, 0),
				"color": BLAST_HOT, "pulse": 4.0, "range": 7.0, "life": 0.5})
		"arena_ward":
			_burst(Kind.WARD, at, _yaw(), Look.CRYSTAL, radius, 0.0)
			_dome(at, radius * 1.25, Look.CRYSTAL, 0.95)
			_pulse(at + Vector3(0, 1.0, 0), Look.CRYSTAL, 3.2, 4.5, 0.55)
		"arena_boss_warning":
			var sec := maxf(float(e.get("sec", 4.0)), 0.5)
			if bool(e.get("final", _final_stage)):
				# The last boss: the same gate, larger, under a dark sun that gathers over it.
				var size := BOSS_SIZE * FINAL_SCALE
				var facing := _inward(at)
				_skill(SkillKind.BOSS_WARNING, at, size, BOSS_RED, sec, sec + 0.2)
				_moment(MomentKind.FINAL_WARNING, at, facing, size, BOSS_RED, 1.0, sec, sec + 0.05)
				_pulse(at + Vector3(0, 0.7, 0), BOSS_VIOLET, 5.5, size * 5.5, sec, 1)
				# The dark sun's own glow (vfx_moment.gdshaderinc dark_sun: 2.2 inside the gate, 3 up).
				_pulse(at - facing.z * 2.2 + Vector3(0, 3.0, 0), BOSS_RED.lerp(FINAL_EMBER, 0.4), 3.5, 9.0, sec, 1)
			else:
				_skill(SkillKind.BOSS_WARNING, at, BOSS_SIZE, BOSS_RED, sec, sec + 0.2)
				_pulse(at + Vector3(0, 0.7, 0), BOSS_VIOLET, 4.5, BOSS_SIZE * 5.5, sec, 1)
		"arena_boss":
			if bool(e.get("final", false)):
				var size := BOSS_SIZE * FINAL_SCALE
				_skill(SkillKind.BOSS_BURST, at, size, BOSS_RED, 0.0, BOSS_BURST_LIFE)
				_moment(MomentKind.FINAL_BURST, at, _inward(at), size, BOSS_RED, 1.0, 0.0, FINAL_BURST_LIFE)
				_pulse(at + Vector3(0, 1.6, 0), FINAL_EMBER.lerp(BOSS_RED, 0.25), 8.5, 15.0, 1.8, 2)
				_delayed.append({"at": _clock + FINAL_AFTERSHOCK, "kind": -1, "origin": at + Vector3(0, 1.0, 0),
					"color": BOSS_RED.lerp(FINAL_EMBER, 0.4), "pulse": 5.0, "range": 12.0, "life": 1.2})
			else:
				_skill(SkillKind.BOSS_BURST, at, BOSS_SIZE, BOSS_RED, 0.0, BOSS_BURST_LIFE)
				_pulse(at + Vector3(0, 1.3, 0), BOSS_VIOLET.lerp(Color.WHITE, 0.3), 8.0, BOSS_SIZE * 7.5, 1.5, 2)
		"arena_revive":
			_revive(at, float(e.get("r", ArenaGeometry.RADIUS)) / UNIT, maxf(float(e.get("sec", Balance.ARENA_REVIVE_INVULN)), 1.3))
			var unit := String(e.get("unit", ""))
			if unit != "":
				var where := String(e.get("where", "field"))
				_arrivals.append({"unit": unit, "where": where, "at": _clock + REVIVE_WHOLE, "until": _clock + REVIVE_WHOLE + ARRIVE_WAIT})
				if where == "field" and _world != null and _world.has_method("hold_hero"): _world.call("hold_hero", unit)
		"arena_wave":
			_wave_start(bool(e.get("elite", false)), bool(e.get("boss", false)))
		"arena_wave_clear":
			# The heal of this clear arrived as arena_heal just before: it is shown here.
			_heal_stash = 0.0
			var centre := world(Balance.ARENA_CENTER, 0.0)
			var mend := _mend_amount(float(e.get("heal", 0.0)))
			_moment(MomentKind.WAVE_CLEAR, centre, Basis.IDENTITY, ArenaGeometry.RADIUS / UNIT, Look.GOLD, mend, WAVE_SWEEP,
				MEND_LIFE if mend > 0.0 else WAVE_CLEAR_LIFE)
			_pulse(centre + Vector3(0, 1.4, 0), BLESSING_LIGHT, 3.2, 7.0, 0.55)
			if mend > 0.0:
				_delayed.append({"at": _clock + 0.35, "kind": -1, "origin": centre + Vector3(0, 1.0, 0), "color": Look.CRYSTAL,
					"pulse": 2.2, "range": 4.5, "life": 0.8})
		"arena_heal":
			_heal_stash += float(e.get("n", 0.0))
		"arena_elite":
			_skill(SkillKind.ELITE_BURST, at, ELITE_SIZE, ELITE_COLOR, 0.0, ELITE_BURST_LIFE)
			_pulse(at + Vector3(0, 1.0, 0), ELITE_COLOR.lerp(Color.WHITE, 0.3), 5.5, ELITE_SIZE * 6.0, 1.1, 2)
		"arena_stage_clear":
			_stage_clear(at, e)
		"arena_stage":
			# The card pauses the battle from the next frame on: nothing of the previous
			# field may be left in that picture (a late burst, a pulse light, a dome, a
			# queued entry would stay frozen on the new field while the player reads).
			_clear_field()
			# The reveal itself is spawned at the end of update(), after this frame's clock
			# step, so the picture behind the card is the reveal at age 0 whatever this
			# frame's dt was.
			_reveal_pending = true
			_reveal_at = at

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
		if fx.has("pulse"):
			var lit := _pulse(fx["origin"], fx["color"], float(fx["pulse"]), float(fx.get("range", 2.0)), float(fx.get("life", 0.12)), int(fx.get("mode", 0)))
			if lit >= 0 and bool(fx.get("rest", false)): _light_fx[lit]["rest"] = true
		_delayed.remove_at(i)
	if not _arrivals.is_empty(): _update_arrivals()
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
	if _warm > 0:
		# Still inside the start-up frames that compile the idle shaders.
		_warm -= 1
		if _warm == 0:
			_aegis.visible = float(_aegis_fx["life"]) > 0.0
			_roads.visible = float(_roads_fx["life"]) > 0.0
	else:
		_moments.visible = _live_moments > 0
	if float(_aegis_fx["life"]) > 0.0:
		_aegis_fx["age"] = float(_aegis_fx["age"]) + dt
		_aegis.rotation.y += dt * AEGIS_SPIN
		if float(_aegis_fx["age"]) >= float(_aegis_fx["life"]):
			_aegis_fx["life"] = 0.0
			_aegis.visible = false
	if float(_roads_fx["life"]) > 0.0:
		_roads_fx["age"] = float(_roads_fx["age"]) + dt
		if float(_roads_fx["age"]) >= float(_roads_fx["life"]):
			_roads_fx["life"] = 0.0
			_roads.visible = false
	_reform_crystal(dt)
	# Last, so that nothing above has aged it: the reveal of a new battlefield is born
	# after this frame's clock step and stays at age 0 for as long as the card is open.
	if _reveal_pending:
		_reveal_pending = false
		_stage_reveal(_reveal_at)

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
		"moment": return _moments
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
	if pool == "moment": _live_moments = maxi(0, _live_moments - 1)

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
	# Where it plays (a skill is rare: the checks read it without the renderer's copy).
	effects[-1]["at"] = origin

# --------------------------------------------------------------------------- #
# Run-level moments: crystal revival, stage clear, new battlefield, final boss
# --------------------------------------------------------------------------- #
## A whole run-level sequence in one Moments instance (priority 4). `basis` gives the
## sequence its directions (see vfx_moment.gdshader) and a uniform scale on it carries one
## distance; `amount` is the kind's scalar, `duration` its length in seconds. `elapsed`
## starts the sequence that many seconds in (a revival's aura resumed from a save).
func _moment(kind: int, origin: Vector3, basis: Basis, radius: float, color: Color, amount: float, duration: float, life: float, elapsed: float = 0.0) -> bool:
	if not _make_room(4): return false
	var slot := _take("moment", 4)
	if slot < 0: return false
	var multimesh := _moments.multimesh
	multimesh.set_instance_transform(slot, Transform3D(basis, origin))
	color.a = amount
	multimesh.set_instance_color(slot, color)
	var custom := Color(_clock - elapsed - _epoch, radius, duration, float(kind))
	multimesh.set_instance_custom_data(slot, custom)
	_record("moment", slot, life, 4, custom)
	if elapsed > 0.0:
		effects[-1]["age"] = elapsed
		effects[-1]["birth"] = _clock - elapsed
	_live_moments += 1
	_moments.visible = true
	return true

## Release everything this node shows that is not read from the simulator each frame:
## one-shot records of every pool, queued entries, pulse lights, domes, the aegis, the
## road ribbons and a crystal caught mid-reform. With `keep_rest` the sequences and the
## light of a held picture (the last clear) stay.
func _clear_field(keep_rest: bool = false) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var fx = effects[i]
		if typeof(fx) != TYPE_DICTIONARY or not fx.has("vfx"): continue
		if keep_rest and bool(fx.get("rest", false)): continue
		_release(fx)
		effects.remove_at(i)
	_delayed.clear()
	_pending_fires.clear()
	_pending_hits.clear()
	_aims.clear()
	_melee.clear()
	_zone_live.clear()
	_boss_fall = {"clock": -99.0}
	# A guardian still waiting for its arrival beat is shown at once (nothing may stay hidden).
	_arrivals.clear()
	_trample.clear()
	_heal_stash = 0.0
	if _world != null and _world.has_method("release_holds"): _world.call("release_holds")
	for i in range(_lights.size()):
		if keep_rest and bool(_light_fx[i].get("rest", false)): continue
		_light_fx[i]["life"] = 0.0
		_lights[i].visible = false
		_lights[i].light_energy = 0.0
	for i in range(_domes.size()):
		_dome_fx[i]["life"] = 0.0
		_domes[i].visible = false
	# During the start-up frames these two stay drawn (empty) to compile their shaders.
	_aegis_fx["life"] = 0.0
	_aegis.visible = _warm > 0
	_roads_fx["life"] = 0.0
	_roads.visible = _warm > 0
	if float(_reform["t"]) >= 0.0 and is_instance_valid(_reform.get("node")):
		(_reform["node"] as Node3D).scale = _reform["base"]
	_reform = {"t": -1.0}
	if _warm == 0: _moments.visible = _live_moments > 0

## The run is won: the result panel freezes the picture from this frame on. Whatever the
## clocks did on the way (a hitch can leave the effect clock behind the simulator's), the
## frozen picture is the last clear at rest and nothing else: every other effect is
## released, and the clear's own sequences jump to their rest if they are not there yet.
func _settle_victory() -> void:
	_clear_field(true)
	var lit := false
	for fx in _light_fx: lit = lit or (float(fx["life"]) > 0.0 and bool(fx.get("rest", false)))
	for fx in effects:
		if typeof(fx) != TYPE_DICTIONARY or not bool(fx.get("rest", false)): continue
		if float(fx["age"]) < FINAL_REST:
			var custom: Color = fx["custom"]
			fx["birth"] = _clock - FINAL_REST
			fx["age"] = FINAL_REST
			custom.r = float(fx["birth"]) - _epoch
			fx["custom"] = custom
			_moments.multimesh.set_instance_custom_data(int(fx["slot"]), custom)
		if not lit and int(round((fx["custom"] as Color).a)) == MomentKind.STAGE_CLEAR:
			lit = true
			var index := _pulse(world(Balance.ARENA_CENTER, 1.3), BLESSING_LIGHT, 1.5, 6.0, FINAL_HOLD, 3)
			if index >= 0: _light_fx[index]["rest"] = true

## A basis whose -Z points from the world point `at` to the crystal (a random yaw at the
## crystal itself): the final boss's dark sun hangs a little inside its gate.
func _inward(at: Vector3) -> Basis:
	var to := world(Balance.ARENA_CENTER, 0.0) - Vector3(at.x, 0.0, at.z)
	return _yaw() if to.length_squared() < 0.01 else Basis.looking_at(to.normalized(), Vector3.UP)

## Seconds a ring that grows from `start` to `reach` in `seconds` (ease-out of `power`,
## the curve the moment shaders draw) needs to reach `distance`.
static func _wave_delay(distance: float, reach: float, seconds: float, power: float, start: float) -> float:
	var k := clampf((distance - start) / maxf(reach - start, 0.01), 0.0, 1.0)
	return seconds * (1.0 - pow(1.0 - k, 1.0 / power))

## The crystal broke and the Guardian's blessing brought it back (see REVIVE_FLASH).
func _revive(at: Vector3, radius: float, sec: float) -> void:
	_moment(MomentKind.REVIVE, at, Basis.IDENTITY, radius, Look.GOLD, 1.0, sec, sec + 0.4)
	# The hard flash, then the aura's own glow for exactly as long as it holds.
	_delayed.append({"at": _clock + REVIVE_FLASH, "kind": -1, "origin": at + Vector3(0, 1.4, 0),
		"color": BLESSING_LIGHT, "pulse": 7.0, "range": 10.0, "life": 0.6, "mode": 2})
	_delayed.append({"at": _clock + REVIVE_FLASH, "kind": -1, "origin": at + Vector3(0, 1.2, 0),
		"color": BLESSING_LIGHT, "pulse": 1.3, "range": 4.5, "life": maxf(sec - REVIVE_FLASH, 0.5), "mode": 3})
	_raise_aegis(at, sec, 0.0)
	_shatter_crystal()
	# The wave is what stops the monsters: a seal closes on each one as it passes
	# (nearest first; the cap keeps a full field inside the burst pool).
	var sim = _sim_ref.get_ref() if _sim_ref != null else null
	if sim == null: return
	var reached: Array = []
	for mo in sim.monsters:
		if float(mo.get("hp", 1.0)) <= 0.0: continue
		var p: Vector2 = BattleSim.mpos(mo)
		reached.append([world(p, 0.0).distance_to(at), p])
	reached.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in range(mini(reached.size(), SEAL_CAP)):
		var p: Vector2 = reached[i][1]
		var delay := REVIVE_FLASH + _wave_delay(float(reached[i][0]), radius * 1.06, REVIVE_WAVE, 2.4, 0.3)
		_delayed.append({"at": _clock + delay, "kind": Kind.SEAL, "origin": world(p, 0.0), "basis": _yaw(),
			"color": SEAL_COLOR, "size": 1.0, "elem": 0.0, "body": _body_scale_at(p)})

## The aegis gem around the crystal for `sec` seconds, `elapsed` of which have already run.
func _raise_aegis(at: Vector3, sec: float, elapsed: float) -> void:
	_aegis.position = at + Vector3(0, 0.03, 0)
	_aegis.rotation.y = elapsed * AEGIS_SPIN
	for surface in range(_aegis.mesh.get_surface_count()):
		var material := _aegis.mesh.surface_get_material(surface) as ShaderMaterial
		material.set_shader_parameter("birth", _clock - elapsed)
		material.set_shader_parameter("duration", sec)
	_aegis.visible = true
	_aegis_fx = {"age": elapsed, "life": sec}

## The rest of a revival's aura for a run restored inside it: the sequence is a function
## of its age, so it simply continues from where the untouchable window stands (the gem,
## the crest and the timer ring end exactly when the crystal can be hurt again).
func _resume_aegis(left: float) -> void:
	var sec: float = maxf(Balance.ARENA_REVIVE_INVULN, left)
	var elapsed := sec - left
	if elapsed >= sec - 0.05: return
	var at := world(Balance.ARENA_CENTER, 0.0)
	_moment(MomentKind.REVIVE, at, Basis.IDENTITY, ArenaGeometry.RADIUS / UNIT, Look.GOLD, 1.0, sec, sec + 0.4, elapsed)
	_pulse(at + Vector3(0, 1.2, 0), BLESSING_LIGHT, 1.3, 4.5, sec - elapsed, 3)
	_raise_aegis(at, sec, elapsed)

## The revival on the real crystal: it shatters (or is already gone, when the blessing
## takes back a defeat), stays away while the shards hang in the air and regrows with a
## small overshoot as they arrive. Only its scale is touched, and only for REVIVE_WHOLE
## seconds; visibility stays with the world.
func _shatter_crystal() -> void:
	if not REVIVE_DRIVES_CRYSTAL or _world == null or _world.crystals.is_empty(): return
	var node: Node3D = _world.crystals[0]
	if not is_instance_valid(node): return
	if float(_reform["t"]) >= 0.0 and is_instance_valid(_reform.get("node")):
		(_reform["node"] as Node3D).scale = _reform["base"]
	var broken := not node.visible
	_reform = {"t": 0.0, "node": node, "base": node.scale, "broken": broken}
	if broken: node.scale = node.scale * 0.001

func _reform_crystal(dt: float) -> void:
	if float(_reform["t"]) < 0.0: return
	var node = _reform.get("node")
	if not is_instance_valid(node):
		# The battlefield was rebuilt in the meantime: its new crystal is whole.
		_reform = {"t": -1.0}
		return
	var t := float(_reform["t"]) + dt
	_reform["t"] = t
	var base: Vector3 = _reform["base"]
	if t >= REVIVE_WHOLE + 0.12:
		node.scale = base
		_reform = {"t": -1.0}
		return
	node.scale = base * crystal_scale(t, bool(_reform["broken"]))

## Shape of the crystal `t` seconds into a revival (1 = whole). It implodes to a sliver in
## 0.07 s unless it was already broken, is gone until the shards return, then grows back
## stretched along its axis and settles at REVIVE_WHOLE.
static func crystal_scale(t: float, broken: bool) -> Vector3:
	if t < 0.07 and not broken:
		var f := t / 0.07
		return Vector3(maxf(1.0 - pow(f, 1.5), 0.001), maxf(1.0 - pow(f, 2.5), 0.001), maxf(1.0 - pow(f, 1.5), 0.001))
	if t < 0.56: return Vector3.ONE * 0.001
	if t >= REVIVE_WHOLE: return Vector3.ONE
	var g := (t - 0.56) / (REVIVE_WHOLE - 0.56)
	var x := g - 1.0
	var k := maxf(1.0 + 2.70158 * x * x * x + 1.70158 * x * x, 0.001)
	var stretch := sin(PI * g)
	return Vector3(k * (1.0 - 0.07 * stretch), k * (1.0 + 0.14 * stretch), k * (1.0 - 0.07 * stretch))

## An escort removed when its stage boss fell (die with scatter). The body is not killed:
## NativeMonsterModel halts it and, when the victory wave reaches it, runs it away from
## the crystal while it thins out (NativeMonsterModel.FLEE_SEC). This is the haze it thins
## into: born when the wave arrives (scatter_delay), drifting the way the body runs
## (scatter_heading) with a few wisps ahead of it. No ground ring, no star flash, no halo,
## no pulse light: it must not read as a kill.
func _scatter(e: Dictionary) -> void:
	var seen := int(_frame_counts.get("scatter", 0)) + 1
	_frame_counts["scatter"] = seen
	if seen > SCATTER_CAP: return
	var p: Vector2 = e.get("p", Vector2.ZERO)
	var heading := scatter_heading(p, int(e.get("sid", 0)))
	var basis := Basis.looking_at(Vector3(heading.x, 0.0, heading.y), Vector3.UP)
	var color := Color(e.get("c", SPIRIT_COLOR)).lerp(SPIRIT_COLOR, 0.5)
	_delayed.append({"at": _clock + scatter_delay(p), "kind": Kind.SCATTER, "origin": world(p, 0.0), "basis": basis,
		"color": color, "size": 1.0, "elem": 0.0, "body": _body_scale_at(p)})

## Seconds after arena_stage_clear at which the victory wave reaches the logical point `p`:
## the moment a fleeing body bolts and its haze is born.
static func scatter_delay(p: Vector2) -> float:
	return _wave_delay(p.distance_to(Balance.ARENA_CENTER) / UNIT, ArenaGeometry.RADIUS / UNIT * 1.04, CLEAR_WAVE, 2.2, 0.4)

## The way an escort flees from the logical point `p` (unit vector, +y south): away from
## the crystal, turned a little by its spawn id so a crowd does not leave as one pattern
## of spokes. Body and haze both use it.
static func scatter_heading(p: Vector2, sid: int) -> Vector2:
	var away := p - Balance.ARENA_CENTER
	var turn := fposmod(float(sid) * 0.6180339 + 0.17, 1.0)
	if away.length_squared() < 4.0: return Vector2.from_angle(turn * TAU)
	return away.normalized().rotated((turn - 0.5) * SCATTER_SPREAD)

## A stage boss fell: the release at the crystal, the mend, and what is left of the boss
## flowing to the crystal when it fell this very tick. Every layer is gone by `sec`.
## The last stage's boss (`final`) wins the run: the same release, then the field is
## sealed (see FINAL_REST) and that picture is held under the result panel.
func _stage_clear(at: Vector3, e: Dictionary) -> void:
	var sec := maxf(float(e.get("sec", Balance.ARENA_CLEAR_DELAY)), 1.0)
	var heal := float(e.get("heal", 0.0))
	var mend := 0.0 if heal <= 0.0 else clampf(0.55 + 0.45 * heal / maxf(1.0, Balance.ARENA_CRYSTAL_HP * Balance.ARENA_STAGE_HEAL), 0.0, 1.0)
	var basis := Basis.IDENTITY
	if _boss_fall.has("p") and _clock - float(_boss_fall["clock"]) < 0.05:
		var to: Vector3 = world(_boss_fall["p"], 0.0) - at
		if to.length() > 0.6: basis = Basis.looking_at(to.normalized(), Vector3.UP).scaled(Vector3.ONE * (1.0 + to.length()))
	var radius := ArenaGeometry.RADIUS / UNIT
	if bool(e.get("final", false)):
		# The shaders read a mend above 1.5 as "the last clear" (mend + 2).
		if _moment(MomentKind.STAGE_CLEAR, at, basis, radius, Look.GOLD, mend + 2.0, sec, sec + FINAL_HOLD): effects[-1]["rest"] = true
		for lane in range(mini(ArenaGeometry.route_count(), ArenaGeometry.MAX_ROUTES)):
			var gate := ArenaGeometry.gate_point(lane, GATE_INSET)
			var inward := Balance.ARENA_CENTER - gate
			if _moment(MomentKind.GATE_SEAL, world(gate, 0.0), Basis.looking_at(Vector3(inward.x, 0.0, inward.y).normalized(), Vector3.UP),
					radius, Look.GOLD, 3.0, sec, sec + FINAL_HOLD):
				effects[-1]["rest"] = true
		_pulse(at + Vector3(0, 1.2, 0), BLAST_HOT, 8.0, 12.0, 0.7)
		# The light of the held picture: it comes up with the crest and stays with it.
		_delayed.append({"at": _clock + FINAL_CREST, "kind": -1, "origin": at + Vector3(0, 1.3, 0), "color": BLESSING_LIGHT,
			"pulse": 1.5, "range": 6.0, "life": sec + FINAL_HOLD - FINAL_CREST, "mode": 3, "rest": true})
	else:
		_moment(MomentKind.STAGE_CLEAR, at, basis, radius, Look.GOLD, mend, sec, sec - 0.02)
		_pulse(at + Vector3(0, 1.2, 0), BLAST_HOT, 6.0, 10.0, minf(0.7, sec - 0.1))
	if mend > 0.0:
		_delayed.append({"at": _clock + 0.35, "kind": -1, "origin": at + Vector3(0, 1.0, 0), "color": Look.CRYSTAL,
			"pulse": 2.6, "range": 5.0, "life": clampf(sec - 0.55, 0.2, 0.8)})

## A new battlefield has just been built and waits, paused, under its card. Everything
## spawned here is drawn at age 0 until the card is confirmed: the rim, the charged ring
## at the plaza and a column of light at every gate. The ground mark of a gate (ring and
## chevrons) is the HUD's while the card is up (ArenaScreen._draw_gate_beacons); ours
## grows out of it when time runs again. Then the scan runs out from the crystal, the
## gates flare when it lands and a runner goes down every road.
func _stage_reveal(at: Vector3) -> void:
	var radius := ArenaGeometry.RADIUS / UNIT
	# The sweep's duration is the moment the first runner reaches the plaza (its ping there).
	var arrival := _roads_start()
	_moment(MomentKind.STAGE_SWEEP, at, Basis.IDENTITY, radius, STAR_PALE, 1.0, arrival, maxf(SWEEP_LIFE, arrival + 0.6))
	for lane in range(mini(ArenaGeometry.route_count(), ArenaGeometry.MAX_ROUTES)):
		var gate := ArenaGeometry.gate_point(lane, GATE_INSET)
		var inward := Balance.ARENA_CENTER - gate
		_moment(MomentKind.GATE_BEACON, world(gate, 0.0), Basis.looking_at(Vector3(inward.x, 0.0, inward.y).normalized(), Vector3.UP),
			radius, GATE_COLOR, 1.0, 0.0, BEACON_LIFE)
	_pulse(at + Vector3(0, 1.2, 0), STAR_PALE, 2.2, 6.5, 0.9)

## Rebuild the road ribbons for the battlefield that has just opened and start their
## reveal: one ribbon per drawable road of the layout, from the rim to where it ends.
## This is the one place a mesh surface is rebuilt after start-up; it happens while the
## battle is paused under the card, in the frame the world itself was rebuilt.
## Returns the seconds until the first runner reaches the plaza (the shortest arm).
func _roads_start() -> float:
	var mesh := _roads.mesh as ArrayMesh
	mesh.clear_surfaces()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := ArenaGeometry.ROAD_WIDTH / UNIT * 0.5 * 0.92
	var longest := 0.0
	var shortest_arm := INF
	var roads := ArenaGeometry.road_polylines()
	for i in range(roads.size()):
		var length := _road_ribbon(st, roads[i], half)
		longest = maxf(longest, length)
		# Arms end at the plaza; feeders end where they join an arm.
		if length > 0.0 and ArenaGeometry.road_layer(i) == 0: shortest_arm = minf(shortest_arm, length)
	if longest <= 0.0:
		_roads.visible = false
		_roads_fx["life"] = 0.0
		return SWEEP_LIFE
	var arrays := st.commit_to_arrays()
	for layer in range(2):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(layer, _road_materials[layer])
		_road_materials[layer].set_shader_parameter("birth", _clock)
		_road_materials[layer].set_shader_parameter("field_radius", ArenaGeometry.RADIUS / UNIT)
		_road_materials[layer].set_shader_parameter("scan_marks", 1.0)
	_road_tone("coral", GATE_COLOR)
	_roads_key = ArenaGeometry.layout()
	_roads_longest = longest
	_roads.visible = true
	_roads_fx = {"age": 0.0, "life": SWEEP_ARRIVE + longest / ROAD_SPEED + 1.2}
	return SWEEP_ARRIVE + (shortest_arm if is_finite(shortest_arm) else longest) / ROAD_SPEED

## The road ribbon's colours: the light (additive) and the body (linear, ROAD_BODY).
func _road_tone(body: String, light: Color) -> void:
	var tones: Array = ROAD_BODY.get(body, ROAD_BODY["coral"])
	_road_materials[0].set_shader_parameter("body", tones[0])
	_road_materials[0].set_shader_parameter("body_hot", tones[1])
	_road_materials[1].set_shader_parameter("color", light)

## A wave starts (see WAVE_BEACON_SKIP).
func _wave_start(elite: bool, boss: bool) -> void:
	var tone := BOSS_RED if boss else ELITE_COLOR if elite else GATE_COLOR
	# A beacon still burning at a gate (the battlefield's reveal when the first prep is short,
	# or the last wave's) gives way to the new one instead of crowding the pool.
	for i in range(effects.size() - 1, -1, -1):
		var fx = effects[i]
		if typeof(fx) != TYPE_DICTIONARY or String(fx.get("vfx", "")) != "moment": continue
		if int(round((fx["custom"] as Color).a)) != MomentKind.GATE_BEACON: continue
		_release(fx)
		effects.remove_at(i)
	if not boss:
		var radius := ArenaGeometry.RADIUS / UNIT
		for lane in range(mini(ArenaGeometry.route_count(), ArenaGeometry.MAX_ROUTES)):
			var gate := ArenaGeometry.gate_point(lane, GATE_INSET)
			var inward := Balance.ARENA_CENTER - gate
			_moment(MomentKind.GATE_BEACON, world(gate, 0.0), Basis.looking_at(Vector3(inward.x, 0.0, inward.y).normalized(), Vector3.UP),
				radius, tone, 2.0 if elite else 1.0, 0.0, BEACON_LIFE, WAVE_BEACON_SKIP)
	_wave_roads("boss" if boss else "elite" if elite else "coral", tone)

## Runners down every road at a wave's start: the ribbon of the current layout (rebuilt here
## only when it is not, e.g. a run restored without a battlefield reveal) restarted already
## SWEEP_ARRIVE into its timeline, so they leave the gates at once, with only the mouths and
## the runners' tails marked.
func _wave_roads(body: String, light: Color) -> void:
	if _roads_key != ArenaGeometry.layout():
		_roads_start()
	if _roads_longest <= 0.0: return
	for material in _road_materials:
		material.set_shader_parameter("birth", _clock - SWEEP_ARRIVE)
		material.set_shader_parameter("scan_marks", 0.0)
	_road_tone(body, light)
	_roads.visible = true
	_roads_fx = {"age": 0.0, "life": _roads_longest / ROAD_SPEED + 1.2}

## One road as a ribbon of quads: UV.x across, UV.y the distance from its gate, UV2.y its
## length (all world units). Returns that length.
func _road_ribbon(st: SurfaceTool, road: PackedVector2Array, half: float) -> float:
	if road.size() < 2: return 0.0
	# From the rim: the drawn road runs to the edge of the field.
	var rim: Vector2 = Balance.ARENA_CENTER + (road[0] - Balance.ARENA_CENTER).normalized() * ArenaGeometry.RADIUS
	var points: Array[Vector3] = [world(rim, ROAD_HEIGHT)]
	for p in road:
		var at := world(p, ROAD_HEIGHT)
		if at.distance_to(points[-1]) >= 0.44: points.append(at)
	var last := world(road[road.size() - 1], ROAD_HEIGHT)
	if last.distance_to(points[-1]) > 0.05: points.append(last)
	if points.size() < 2: return 0.0
	var along: Array[float] = [0.0]
	for i in range(1, points.size()): along.append(along[-1] + points[i].distance_to(points[i - 1]))
	var total: float = along[-1]
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in range(points.size()):
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var normal := Vector3(-tangent.z, 0.0, tangent.x) * half
		left.append(points[i] - normal)
		right.append(points[i] + normal)
	for i in range(points.size() - 1):
		var corners := [left[i], right[i], right[i + 1], left[i + 1]]
		var uvs := [Vector2(0, along[i]), Vector2(1, along[i]), Vector2(1, along[i + 1]), Vector2(0, along[i + 1])]
		for n in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[n])
			st.set_uv2(Vector2(0.0, total))
			st.add_vertex(corners[n])
	return total

## Revival gifts whose arrival time has come. On the field the star is sent down onto the
## held body's spot at once and the body is shown ARRIVE_FALL later, inside the landing's
## column of light, dropping in (NativeCharacterModel's spawn beat); with no body on the field
## (bench, or it never turned up within ARRIVE_WAIT) the star rises from the crystal instead.
func _update_arrivals() -> void:
	for i in range(_arrivals.size() - 1, -1, -1):
		var arrival: Dictionary = _arrivals[i]
		var unit := String(arrival["unit"])
		if arrival.has("reveal"):
			if _clock < float(arrival["reveal"]): continue
			_arrivals.remove_at(i)
			if _world != null and _world.has_method("reveal_hero"): _world.call("reveal_hero", unit)
			continue
		if _clock < float(arrival["at"]): continue
		var node: Node3D = null
		if String(arrival["where"]) == "field" and _world != null and _world.has_method("held_hero"):
			node = _world.call("held_hero", unit)
			# Still waiting for its body: within ARRIVE_WAIT, or while its model loads.
			if node == null and (_clock < float(arrival["until"]) or bool(_world.call("loading", unit))): continue
		if node != null:
			_hero_arrive(Vector3(node.global_position.x, 0.0, node.global_position.z), true)
			arrival["reveal"] = _clock + ARRIVE_FALL
			continue
		_arrivals.remove_at(i)
		if _world != null and _world.has_method("release_hold"): _world.call("release_hold", unit)
		_hero_arrive(world(Balance.ARENA_CENTER, 0.0), false)

## The five-star arrival (see ARRIVE_FALL): `field` lands on `at`, otherwise the crown round
## the crystal at `at`.
func _hero_arrive(at: Vector3, field: bool) -> void:
	if field:
		_skill(SkillKind.HERO_ARRIVE, at, ARRIVE_SIZE, BLESSING_LIGHT, 1.0, ARRIVE_LIFE)
		_delayed.append({"at": _clock + ARRIVE_FALL, "kind": -1, "origin": at + Vector3(0, 1.0, 0),
			"color": BLESSING_LIGHT, "pulse": 5.5, "range": 5.5, "life": 0.6})
	else:
		# The burst over the aegis dome (vfx_skill kind 6 bench: crown_at 2.8 u).
		_skill(SkillKind.HERO_ARRIVE, at, ARRIVE_SIZE, BLESSING_LIGHT, 2.0, ARRIVE_BENCH_LIFE)
		_delayed.append({"at": _clock + LEVELUP_RISE, "kind": -1, "origin": at + Vector3(0, 2.8, 0),
			"color": BLESSING_LIGHT, "pulse": 4.0, "range": 6.5, "life": 0.6})

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
##   3 hold: a steady, slowly breathing glow that goes out at the end (the aegis)
static func _light_curve(mode: int, q: float, age: float) -> float:
	match mode:
		3:
			return (0.82 + 0.18 * sin(age * 3.0)) * (1.0 - smoothstep(0.90, 1.0, q))
		1:
			return (0.25 + 0.75 * q * q) * (0.8 + 0.2 * sin(age * (7.0 + 9.0 * q))) + 0.6 * maxf(0.0, (q - 0.88) / 0.12)
		2:
			return 0.55 * pow(maxf(0.0, 1.0 - q * 5.0), 1.2) + 0.45 * pow(1.0 - q, 2.0)
	return (1.0 - q) * (1.0 - q)

## Light one pooled pulse (the oldest is reused when all six are lit; the light of a held
## picture is never taken). Returns the light's index, -1 when none could be used.
func _pulse(at: Vector3, color: Color, energy: float, range_value: float, life: float, mode: int = 0) -> int:
	var index := -1
	var oldest := -1.0
	for i in range(_lights.size()):
		if float(_light_fx[i]["life"]) <= 0.0:
			index = i
			break
		if bool(_light_fx[i].get("rest", false)): continue
		var q := float(_light_fx[i]["age"]) / float(_light_fx[i]["life"])
		if q > oldest:
			oldest = q
			index = i
	if index < 0: return -1
	var light := _lights[index]
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.visible = true
	_light_fx[index] = {"age": 0.0, "life": life, "energy": energy, "mode": mode}
	return index

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

## The elite's mark (StellarModels.elite): a shared mesh (ground sigil + 6 motes) and one
## shared material whose clock is the battle's (it sits in _status_materials, so update()
## moves its vfx_time and a paused battle holds it). The node is scaled to the ring radius
## and the body height; its `fade` instance uniform goes with the dissolve (StellarShading
## META_AURA). Named Stellar* so the girth measurement (_body_radius) skips it.
static func elite_aura(height: float) -> MeshInstance3D:
	if _elite_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(st, 0, 0)
		for n in range(6): _quad(st, 1, n)
		_elite_mesh = st.commit()
	if not _status_materials.has("Elite"):
		var material := ShaderMaterial.new()
		material.shader = SHADER_ELITE
		material.render_priority = 1
		material.set_shader_parameter("sprites", SPRITES)
		_status_materials["Elite"] = material
	var node := MeshInstance3D.new()
	node.name = "StellarEliteAura"
	node.mesh = _elite_mesh
	node.material_override = _status_materials["Elite"]
	var ring := clampf(0.70 * height, 0.50, 1.10)
	node.scale = Vector3(ring, maxf(height, 0.4), ring)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1.4, -0.2, -1.4), Vector3(2.8, 1.8, 2.8))
	return node

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

## Hover height of the body an event names (sid): the hit, the frost, the death are drawn
## up there. 0 for walkers and for events without a body.
func _fly_height(e: Dictionary) -> float:
	var sid := int(e.get("sid", 0))
	if sid == 0 or _world == null: return 0.0
	var node := _world.monster_node(sid)
	if node == null: return 0.0
	return maxf(float(node.get_meta(META_FLY, 0.0)), 0.0)

## A basis whose -Z runs from the shooting hero to the struck point: the impact's sparks
## spray on through the body the way the shot travelled. A random yaw without a shooter.
func _travel(src: int, p: Vector2) -> Basis:
	var sim = _sim_ref.get_ref() if _sim_ref != null else null
	if sim != null and src >= 0 and src < sim.heroes.size():
		var d: Vector2 = p - Vector2(sim.heroes[src]["pos"])
		if d.length_squared() > 1.0: return Basis.looking_at(Vector3(d.x, 0.0, d.y).normalized(), Vector3.UP)
	return _yaw()

## A crit or weak-point hit colours and strengthens the body's own hit flash (the flash
## itself is the simulator's mo.flash, applied by the world each frame).
func _accent(sid: int, elem_name: String, scale: float) -> void:
	if sid == 0 or _world == null: return
	var node := _world.monster_node(sid)
	if node == null: return
	var tint := Balance.elem_color(elem_name) if elem_name != "none" else Color("#fff1c9")
	StellarShading.set_hit_accent(node, clampf(0.45 * scale, 0.4, 0.9), tint)

## A deterministic pseudo-random yaw (never touches any gameplay RNG).
func _yaw() -> Basis:
	_counter += 1
	return Basis(Vector3.UP, fposmod(float(_counter) * 2.399963 + _clock * 0.7, TAU))
