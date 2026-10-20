// Shared by vfx_road.gdshader (additive light) and vfx_road_base.gdshader (ink underlay):
// the roads of a freshly built battlefield announcing themselves.
//   mesh (StellarVfx._roads_start): one ribbon per road of the current layout, rebuilt when
//   a battlefield opens. UV.x = across the road 0..1, UV.y = distance from the road's gate
//   (world units), UV2.y = the road's length. The ribbon lies at the world origin, so the
//   distance from the crystal is the length of VERTEX.xz.
//   birth: effect clock at the arena_stage event (the battle is paused under the card
//   then: age 0 is the frame the player sees behind it).
// Timeline: nothing at age 0 (under the card the HUD draws its own ring and chevrons on
// every gate, ArenaScreen._draw_gate_beacons; two sets of marks at once clashed). Once
// time runs, chevrons fade in at the mouth of every road where the HUD's were; the scan
// from the crystal marks the rest of each road as it passes (0..ARR); at ARR a runner
// leaves every gate and races down its road at SPEED with a tail of chevrons pointing the
// way the enemy will walk, and the road is plain again behind it.
uniform float birth = -100.0;
uniform float vfx_time = 0.0;
uniform float field_radius = 12.0;
// 1 for a new battlefield (the scan marks each road as it passes); 0 for a wave start
// (2026-10-19): StellarVfx starts the ribbon ARR into its timeline so the runners leave
// the gates at once, and only the mouths and the runners' tails are marked.
uniform float scan_marks = 1.0;

const float ARR = 0.75;
const float SPEED = 30.0;
const float PLAZA = 2.1;

// x: light (additive)   y: how hot (0 road glow .. 1 the runner's head)   z: body (alpha-blended)
vec3 road_light(float along, float across, float rad, float total, float age) {
	float lane = 1.0 - smoothstep(0.72, 0.92, abs(across));
	float centre = exp(-pow(across / 0.45, 2.0));
	// Lit by the scan from the crystal as it passes; the mouth takes over from the HUD's
	// marks as soon as time runs.
	float scan = mix(PLAZA, field_radius, 1.0 - pow(1.0 - clamp(age / ARR, 0.0, 1.0), 1.5));
	float lit = (1.0 - smoothstep(scan - 0.6, scan, rad)) * smoothstep(0.0, 0.14, age) * scan_marks;
	float mouth = (1.0 - smoothstep(2.8, 6.5, along)) * smoothstep(0.0, 0.14, age);
	float head = (age - ARR) * SPEED;
	float behind = head - along;
	float ahead = behind < 0.0 ? 1.0 : 0.0;
	float started = step(ARR, age);
	float core = (behind >= 0.0 ? exp(-behind / 1.1) : exp(-pow(behind / 0.45, 2.0))) * started;
	float tail = (behind >= 0.0 ? exp(-behind / 6.5) : 0.0) * started;
	// Chevrons pointing down the road (toward the crystal) and drifting that way: at the
	// mouth, along the whole road once the scan has passed, and in the runner's tail.
	// They follow the road's own bend.
	float phase = fract((along + 1.15 * abs(across)) * 0.52 - age * 1.2);
	float chevron = smoothstep(0.0, 0.05, phase) * (1.0 - smoothstep(0.33, 0.38, phase));
	float end = 1.0 - smoothstep(total - 1.6, total - 0.1, along);
	float marked = max(mouth, 0.46 * lit) * ahead;
	float runner = core * (0.35 + 0.65 * centre) + tail * (0.10 + 0.50 * chevron);
	float glow = (marked * (0.10 + 0.26 * chevron) + runner) * lane * end;
	float body = (marked * chevron * 0.92 + core * centre * 0.9 + tail * chevron * 0.85) * lane * end;
	return vec3(glow, clamp(core * centre, 0.0, 1.0), body);
}
