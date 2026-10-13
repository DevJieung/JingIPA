// Shared by vfx_moment.gdshader (additive light) and vfx_moment_mix.gdshader (alpha-blended
// body): the clocks, wave curves and particle paths of the run-level moments. The two
// layers must agree to the pixel, and StellarVfx times its own hand-offs (the seals on the
// monsters, the fleeing escort, the gate flares) to the same curves.

const float FL = 0.26;     // revival: the collapse ends in the flash (StellarVfx.REVIVE_FLASH)
const float ARR = 0.75;    // new battlefield: the scan reaches the rim (StellarVfx.SWEEP_ARRIVE)
const float AFT = 0.24;    // final boss: the aftershock (StellarVfx.FINAL_AFTERSHOCK)

float seg(float a, float b, float x) {
	return clamp((x - a) / (b - a), 0.0, 1.0);
}

// Radius of the revival's shockwave `t` seconds after the flash (StellarVfx.REVIVE_WAVE).
float revive_wave(float t, float field) {
	return mix(0.3, field * 1.06, 1.0 - pow(1.0 - clamp(t / 0.50, 0.0, 1.0), 2.4));
}

// Radius of the stage clear's victory wave (StellarVfx.CLEAR_WAVE, scatter_delay).
float clear_wave(float t, float field) {
	return mix(0.4, field * 1.04, 1.0 - pow(1.0 - clamp(t / 0.60, 0.0, 1.0), 2.2));
}

// Radius of the new battlefield's scan: charged around the plaza at 0, at the rim at ARR.
float sweep_radius(float t, float field) {
	return mix(2.1, field, 1.0 - pow(1.0 - clamp(t / ARR, 0.0, 1.0), 1.5));
}

// Revival aura: from the flash until the crystal can be hurt again, blinking through its
// last second.
float revive_aura(float age, float dur) {
	float a = smoothstep(FL, FL + 0.25, age) * (1.0 - smoothstep(dur - 0.22, dur, age));
	return a * (1.0 - 0.45 * step(dur - 1.0, age) * step(0.5, fract((dur - age) * 5.0)));
}

// Timer ring: 1 on the part of the ring still to run. `plane` is the quad plane (-1..1,
// +y = the top of the screen), the ring drains clockwise from there in `segments` pieces.
float timer_left(vec2 plane, float elapsed, float segments) {
	float frac = fract(atan(plane.x, plane.y) / TAU + 1.0);
	float q = fract(frac * segments);
	return smoothstep(elapsed - 0.004, elapsed + 0.004, frac) * smoothstep(0.012, 0.040, min(q, 1.0 - q));
}

// Timer ring: 1 at the point where the ring is burning down.
float timer_head(vec2 plane, float elapsed) {
	float frac = fract(atan(plane.x, plane.y) / TAU + 1.0);
	float gap = abs(frac - elapsed);
	return exp(-pow(min(gap, 1.0 - gap) / 0.016, 2.0));
}

// The revival's shards: flung out of the breaking crystal, held in the air, then drawn
// back in along a tightening swirl. Arrival is staggered over 0.54..0.90 s.
float shard_arrival(float h2) {
	return 0.54 + 0.36 * h2;
}

vec3 revive_shard(float t, float h1, float h2, float h3, float i, vec3 origin, vec3 mx, vec3 fwd) {
	float ang = (i + h1 * 0.8) / 16.0 * TAU + 0.5 * t;
	float t_go = FL + 0.04 + 0.10 * h1;
	float out_f = ease_out3(t / 0.22);
	float pull = pow(seg(t_go, shard_arrival(h2), t), 2.4);
	float swirl = ang + 1.6 * pull;
	float rad = (1.5 + 1.3 * h2) * out_f * (1.0 - pull) + 0.10 * pull;
	float y = mix(mix(0.5 + 1.1 * h3, 0.55 + 2.2 * h3, out_f), 0.45 + 1.35 * h1, pull);
	return origin + (mx * cos(swirl) + fwd * sin(swirl)) * rad + vec3(0.0, y, 0.0);
}

// Stage clear: a dome of stars bursting from the crystal's tip and falling around the plaza.
vec3 fountain_star(float t, float h1, float h2, float i, vec3 origin, vec3 mx, vec3 fwd) {
	float ang = (i + h1 * 0.9) / 16.0 * TAU;
	vec3 vel = (mx * sin(ang) + fwd * cos(ang)) * (1.2 + 2.2 * h2) + vec3(0.0, 2.6 + 2.4 * h1, 0.0);
	return origin + vec3(0.0, 1.9, 0.0) + vel * t + vec3(0.0, -3.25 * t * t, 0.0);
}

// Stage clear: when the mend's parts happen (seconds). The release takes the first third
// of the 1.8 s, the mend the rest; everything fades with clear_out before the rebuild.
const float MEND_RING = 0.38;      // the closing ring starts
const float MEND_HALO = 0.46;      // the first halo starts (two more follow, 0.2 s apart)
const float MEND_DING = 1.22;      // the glint on the crystal's tip

// The last stage's clear (COLOR.a >= 1.5): the run is won. A second wave leaves at
// SEAL_WAVE, reaches the rim at SEAL_LOCK and stays there as a gold ring; the guardian
// crest is stamped on the plaza at CREST_AT; every gate is sealed (kind 6: a ring closes
// on it from SEAL_LOCK, the crest lands SEAL_STAMP later). Everything that moves is over
// by FINAL_REST (StellarVfx.FINAL_REST): from there the picture is still, because the
// result panel freezes it at `dur`.
const float SEAL_WAVE = 0.25;
const float SEAL_LOCK = 0.85;
const float SEAL_STAMP = 0.22;
const float CREST_AT = 0.42;
const float FINAL_REST = 1.62;

// Stage clear: what is left of the boss travels to the crystal in an arc.
vec3 essence_path(float g, float h1, float h2, float h3, float dist, vec3 origin, vec3 fwd) {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 from = origin + fwd * dist + up * (1.0 + 0.8 * h2);
	vec3 to = origin + up * (0.8 + 0.8 * h3);
	float e = g * g * (3.0 - 2.0 * g);
	vec3 side = normalize(cross(up, fwd));
	return mix(from, to, e) + up * sin(g * PI) * (1.2 + 1.0 * h1) + side * sin(g * PI) * (h2 - 0.5) * 2.4;
}

// Final boss: where the dark sun hangs. Over the road a little inside the gate (`fwd` is
// the way to the crystal) and only 3 units up, so that it stays below the HUD strip even
// for a gate at the top of the screen; pulled toward the camera by the boss footprint so
// the 2.8x body does not cover it.
vec3 dark_sun(vec3 origin, vec3 fwd, vec3 cam_fwd, float footprint) {
	return origin + fwd * 2.2 + vec3(0.0, 3.0, 0.0) - cam_fwd * footprint;
}

// A sprite stretched along `along` (unit) in the screen plane: the corner `c` of its quad.
vec3 streak(vec3 at, vec3 along, vec2 c, float len, float wid, vec3 cam_fwd, vec3 cam_right) {
	vec3 side = cross(along, cam_fwd);
	side = length(side) < 0.02 ? cam_right : normalize(side);
	return at + along * c.y * len + side * c.x * wid;
}
