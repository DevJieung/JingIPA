shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Additive layer of one-shot bursts (impacts, deaths, status, skills) in one MultiMesh.
//   transform: origin on the ground (or the 3D point for kinds >= 15, or the hover height
//              of a flying body), -Z = facing / incoming direction (impacts: the shot's
//              travel direction, so sparks spray on through the body)
//   COLOR:     rgb effect colour, a = root scale of the body the burst sits in (1 for ordinary
//              bodies; bosses stand at 2x). Air parts lift with it and are pulled toward the
//              camera by BODY_CLEAR per extra unit of scale so they are drawn in front of the
//              larger body instead of inside it; the view is orthographic, so the pull does
//              not move them on screen. Ground parts stay where they are.
//   CUSTOM:    x birth (vfx seconds)  y size  z element  w kind
// Kinds: 0 hit 1 splash 2 zone_tick 3 die 4 leak 5 block 6 push 7 frost 8 stun 9 curse
//        10 spawn 11 wildfire 12 blast 13 freeze 14 ward 15 muzzle_smoke 16 ric_spark
//        17 beam_cap 18 bolt_cap 19 cast_release 20 slash_hit (blade contact: origin is the
//        3D point on the body, -Z = the blade's travel direction there)
//        21 seal (the revival's shockwave reaching a monster: a ring closing on it)
//        22 scatter (an escort fleeing after its stage boss fell: -Z = the way it runs;
//        wisps and a drifting haze, no ground ring, no star flash: it must not read as a kill)
//        23 crit (2026-10-17: a critical or weak-point hit; size carries the impact scale.
//        A ray burst snaps open in the screen plane, a hot star, long sparks on through
//        the body, a facing ring: the accent on top of the ordinary hit)
//        24 zone_end (a ground zone's last tick: the element's weather settles; size = R)
// Parts (UV2.x): 0 ground ring, 1 flash billboard, 2 sparks x8, 3 motes x8, 5 facing ring
// (kind 20 draws its crescent cut mark in part 5), 7 plume (a short vertical column: dust
// lifted by a splash, a kill's exhale, a zone's last breath), 8 accents x6 (crit rays and
// streaks, the kill pop's sparkles, blade chips, shatter shards).
// `size` is the impact scale (crit x1.35, weak point x1.3, resisted x0.72) on hits, a
// radius in world units on area kinds and the body's height ratio on kills.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D zone_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue.
uniform float vfx_wash = 0.0;
uniform float vfx_epoch = 0.0;

const float BODY_CLEAR = 1.9;

varying vec4 v_tint;
varying float v_cell;
varying vec2 v_plane;
varying vec4 v_ring;   // r (0..1 of quad), width, arc mask, fill

float kind_lift(int k, float size) {
	if (k == 0) return 0.5;
	if (k == 1) return 0.4;
	if (k == 2) return 0.1;
	if (k == 3) return 0.45 * size;
	if (k == 4) return 0.7;
	if (k == 5) return 0.5;
	if (k == 6) return 0.3;
	if (k == 7) return 0.4;
	if (k == 8) return size;
	if (k == 9) return 0.3;
	if (k == 10) return 0.3;
	if (k == 11) return 0.3;
	if (k == 12) return 0.5;
	if (k == 13) return 0.4;
	if (k == 14) return 0.6;
	if (k == 19) return 0.05;
	if (k == 21) return 0.55;
	if (k == 22) return 0.5;
	if (k == 23) return 0.55;
	if (k == 24) return 0.3;
	return 0.0;
}

// r0, r1, duration, width (world units)
vec4 ring_params(int k, float size) {
	if (k == 0) return vec4(0.10, 0.52, 0.30, 0.12);
	if (k == 1) return vec4(0.18, size, 0.40, 0.22);
	if (k == 2) return vec4(size * 0.78, size, 0.32, 0.10);
	if (k == 3) return vec4(0.12, 0.78 * size, 0.55, 0.13);
	if (k == 4) return vec4(0.25, size, 0.42, 0.18);
	if (k == 5) return vec4(0.35, 0.72, 0.36, 0.09);
	if (k == 6) return vec4(0.18, 0.62, 0.30, 0.12);
	if (k == 7) return vec4(0.08, 0.50, 0.42, 0.10);
	if (k == 8) return vec4(0.22, 0.42, 0.34, 0.07);
	if (k == 9) return vec4(0.62, 0.22, 0.52, 0.10);
	if (k == 10) return vec4(0.05, 0.72, 0.60, 0.12);
	if (k == 11) return vec4(0.15, size, 0.48, 0.22);
	if (k == 12) return vec4(0.30, size, 0.46, 0.34);
	if (k == 13) return vec4(0.40, size, 0.95, 1.30);
	if (k == 14) return vec4(0.50, size * 1.5, 0.52, 0.16);
	if (k == 19) return vec4(0.30, 0.95, 0.36, 0.12);
	if (k == 21) return vec4(0.95, 0.34, 0.30, 0.10);
	if (k == 23) return vec4(0.12, 0.62 * size, 0.26, 0.16);
	if (k == 24) return vec4(size * 0.9, size * 1.18, 0.46, 0.20);
	return vec4(0.0, 0.0, 0.1, 0.1);
}

// size, duration, sprite cell, extra (unused)
vec4 flash_params(int k, int e) {
	int star = e == 3 ? 2 : 1;
	if (k == 0) return vec4(0.46, 0.11, float(star), 0.0);
	if (k == 1) return vec4(0.95, 0.15, float(star), 0.0);
	if (k == 3) return vec4(0.80, 0.22, 0.0, 0.0);
	if (k == 4) return vec4(1.05, 0.17, 1.0, 0.0);
	if (k == 5) return vec4(0.55, 0.14, 0.0, 0.0);
	if (k == 6) return vec4(0.36, 0.09, 1.0, 0.0);
	if (k == 7) return vec4(0.44, 0.13, 2.0, 0.0);
	if (k == 8) return vec4(0.32, 0.12, 2.0, 0.0);
	if (k == 9) return vec4(0.34, 0.24, 0.0, 0.0);
	if (k == 10) return vec4(0.46, 0.30, 0.0, 0.0);
	if (k == 11) return vec4(0.60, 0.16, 0.0, 0.0);
	if (k == 12) return vec4(2.10, 0.22, 1.0, 0.0);
	if (k == 13) return vec4(1.70, 0.26, 2.0, 0.0);
	if (k == 14) return vec4(1.20, 0.22, 0.0, 0.0);
	if (k == 16) return vec4(0.30, 0.09, float(star), 0.0);
	if (k == 17) return vec4(0.52, 0.20, float(star), 0.0);
	if (k == 18) return vec4(0.46, 0.13, 2.0, 0.0);
	if (k == 19) return vec4(0.55, 0.16, 2.0, 0.0);
	if (k == 20) return vec4(0.30, 0.08, float(star), 0.0);
	if (k == 21) return vec4(0.56, 0.16, 1.0, 0.0);
	if (k == 22) return vec4(0.90, 0.30, 0.0, 0.0);
	if (k == 23) return vec4(0.95, 0.17, 1.0, 0.0);
	if (k == 24) return vec4(1.30, 0.24, 0.0, 0.0);
	return vec4(0.0, 0.1, 0.0, 0.0);
}

// count, speed (units/s), duration, elongation
vec4 spark_params(int k) {
	if (k == 0) return vec4(7.0, 3.6, 0.27, 1.3);
	if (k == 1) return vec4(8.0, 4.6, 0.36, 1.3);
	if (k == 2) return vec4(6.0, 2.6, 0.32, 1.0);
	if (k == 3) return vec4(6.0, 2.4, 0.42, 0.9);
	if (k == 4) return vec4(8.0, 3.6, 0.36, 1.2);
	if (k == 6) return vec4(4.0, 3.0, 0.26, 1.0);
	if (k == 7) return vec4(6.0, 1.5, 0.52, 1.1);
	if (k == 8) return vec4(6.0, 1.4, 0.34, 0.8);
	if (k == 11) return vec4(6.0, 3.0, 0.32, 1.0);
	if (k == 12) return vec4(8.0, 7.2, 0.48, 1.6);
	if (k == 13) return vec4(8.0, 2.6, 0.62, 1.2);
	if (k == 15) return vec4(5.0, 2.6, 0.22, 0.9);
	if (k == 16) return vec4(5.0, 2.4, 0.20, 1.0);
	if (k == 17) return vec4(4.0, 2.0, 0.22, 1.0);
	if (k == 18) return vec4(6.0, 2.2, 0.22, 0.9);
	if (k == 20) return vec4(7.0, 3.6, 0.26, 1.5);
	if (k == 22) return vec4(3.0, 4.6, 0.75, 2.6);
	if (k == 23) return vec4(8.0, 6.0, 0.34, 2.2);
	if (k == 24) return vec4(8.0, 3.4, 0.55, 1.2);
	return vec4(0.0, 0.0, 0.1, 1.0);
}

// forward bias, upward amount, gravity, unused
vec4 spark_shape(int k) {
	if (k == 0) return vec4(0.60, 0.45, 1.0, 0.0);
	if (k == 1) return vec4(0.45, 0.9, 1.0, 0.0);
	if (k == 2) return vec4(0.0, 1.5, 0.7, 0.0);
	if (k == 3) return vec4(0.0, 0.9, 1.1, 0.0);
	if (k == 6) return vec4(0.85, 0.3, 0.8, 0.0);
	if (k == 7) return vec4(0.0, 1.2, 0.5, 0.0);
	if (k == 8) return vec4(0.0, 0.2, 0.0, 0.0);
	if (k == 13) return vec4(0.0, 1.0, 0.4, 0.0);
	if (k == 15) return vec4(0.9, 0.15, 0.6, 0.0);
	if (k == 16) return vec4(0.3, 0.5, 0.8, 0.0);
	if (k == 20) return vec4(0.72, 0.30, 0.9, 0.0);
	if (k == 22) return vec4(0.90, 0.45, 0.0, 0.0);
	if (k == 23) return vec4(0.70, 0.40, 0.9, 0.0);
	if (k == 24) return vec4(0.0, 1.4, 0.8, 0.0);
	return vec4(0.0, 0.55, 1.0, 0.0);
}

// rise (units), duration, spread, size
vec4 mote_params(int k, float size) {
	if (k == 0) return vec4(0.40, 0.45, 0.18, 0.08);
	if (k == 1) return vec4(0.65, 0.70, size * 0.5, 0.10);
	if (k == 2) return vec4(0.55, 0.50, size * 0.8, 0.075);
	if (k == 3) return vec4(1.35 * size, 0.95, 0.28 * size, 0.11);
	if (k == 4) return vec4(0.60, 0.50, 0.35, 0.08);
	if (k == 7) return vec4(0.50, 0.85, 0.30, 0.09);
	if (k == 9) return vec4(-0.80, 0.55, 0.30, 0.08);
	if (k == 10) return vec4(1.25, 0.85, 0.32, 0.10);
	if (k == 11) return vec4(0.95, 0.80, size * 0.7, 0.10);
	if (k == 12) return vec4(1.10, 0.90, size * 0.55, 0.12);
	if (k == 13) return vec4(1.20, 1.05, size * 0.30, 0.14);
	if (k == 14) return vec4(1.50, 0.80, 0.90, 0.10);
	if (k == 19) return vec4(1.00, 0.45, 0.45, 0.08);
	if (k == 20) return vec4(0.30, 0.42, 0.14, 0.06);
	if (k == 21) return vec4(0.85, 0.80, 0.30, 0.09);
	if (k == 22) return vec4(1.50, 0.95, 0.30, 0.10);
	if (k == 23) return vec4(0.55, 0.50, 0.22, 0.09);
	if (k == 24) return vec4(1.40, 1.00, size * 0.75, 0.11);
	return vec4(0.0, 0.1, 0.0, 0.0);
}

// facing ring: size, duration, sprite cell (3 ring / 13 hex), unused
vec4 ring2_params(int k, float size) {
	if (k == 3) return vec4(0.95 * size, 0.60, 3.0, 0.0);
	if (k == 4) return vec4(size * 1.6, 0.40, 3.0, 0.0);
	if (k == 5) return vec4(0.95, 0.38, 13.0, 0.0);
	if (k == 12) return vec4(size * 1.4, 0.40, 3.0, 0.0);
	if (k == 19) return vec4(0.90, 0.32, 3.0, 0.0);
	if (k == 21) return vec4(0.85, 0.34, 3.0, 0.0);
	if (k == 23) return vec4(1.05 * size, 0.30, 3.0, 0.0);
	return vec4(0.0, 0.1, 3.0, 0.0);
}

// plume: height, width, duration, mode (0 rises then fades, 1 holds then fades)
vec4 plume_params(int k, float size) {
	if (k == 1) return vec4(0.7 + 0.7 * size, 0.5 + 0.35 * size, 0.36, 0.0);
	if (k == 3) return size >= 1.25 ? vec4(1.8 * size, 0.7 * size, 0.5, 0.0) : vec4(0.0);
	if (k == 11) return vec4(1.5, 0.9, 0.40, 0.0);
	if (k == 24) return vec4(2.3, size * 1.4, 0.6, 0.0);
	return vec4(0.0);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 mx = normalize(MODEL_MATRIX[0].xyz);
	vec3 fwd = normalize(-MODEL_MATRIX[2].xyz);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	vec3 pillar_side = normalize(cross(up, cam_fwd));
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	float birth = INSTANCE_CUSTOM.x;
	float size = INSTANCE_CUSTOM.y;
	int elem = int(INSTANCE_CUSTOM.z + 0.5);
	int kind = int(INSTANCE_CUSTOM.w + 0.5);
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float seed = hash11(birth * 7.31 + float(INSTANCE_ID) * 0.173);
	float body = max(COLOR.a, 1.0);
	// The stun pop already receives the scaled head height as its size.
	float lift = kind_lift(kind, size) * (kind == 8 ? 1.0 : body);
	// Hits and contacts grow with their impact scale (a crit is a bigger event than a graze).
	float impact = (kind == 0 || kind == 20 || kind == 23) ? clamp(size, 0.6, 1.9) : 1.0;
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = COLOR.rgb;
	float alpha = 0.0;
	float cell = 0.0;
	v_plane = c * 2.0;
	v_ring = vec4(0.0);
	if (part == 0) {
		vec4 rp = ring_params(kind, size);
		float f = clamp(age / rp.z, 0.0, 1.0);
		float r = mix(rp.x, rp.y, ease_out3(f));
		if (kind == 10) r = rp.y * sin(f * 3.14159) + 0.05;
		float rmax = max(max(rp.x, rp.y) + rp.w * 1.8, 0.01);
		// Rings at the altar must clear its stone platform; elsewhere just clear the plaza.
		float y = kind == 8 ? lift : (kind == 4 || kind == 14) ? 0.34 : 0.07;
		world = origin + up * y + mx * c.x * 2.0 * rmax + fwd * c.y * 2.0 * rmax;
		if (kind == 1) world += fwd * rp.y * 0.18 * f;
		if (kind == 6) world += fwd * 0.2;
		float arc = (kind == 6) ? 1.0 : 0.0;
		float fill = (kind == 1 || kind == 11) ? 0.22 : (kind == 12 ? 0.12 : (kind == 10 || kind == 14 ? 0.10 : (kind == 24 ? 0.08 : 0.0)));
		v_ring = vec4(r / rmax, rp.w / rmax, arc, fill);
		alpha = pow(1.0 - f, kind == 13 ? 0.9 : 1.3) * (rp.y > 0.001 ? 1.0 : 0.0);
		if (kind == 13) alpha *= 0.75;
		col = mix(col, elem_tint(elem), (elem == 0 || kind == 3) ? 0.15 : 0.45);
		if (kind == 23) col = mix(elem_hot(elem), col, 0.3);
		cell = -1.0;
	} else if (part == 1) {
		vec4 fp = flash_params(kind, elem);
		float f = clamp(age / fp.y, 0.0, 1.0);
		float s = fp.x * (0.75 + 0.55 * ease_out(f)) * impact * (kind == 3 ? size : 1.0);
		if (kind == 23) s = fp.x * impact * overshoot(f * 2.2) * (1.0 - 0.3 * f);
		vec2 r = rot2(c, seed * 6.283 + (kind == 8 ? vfx_time * 6.0 : 0.0));
		world = origin + up * lift + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.32;
		alpha = pow(1.0 - f, 1.6) * (fp.x > 0.001 ? 1.0 : 0.0);
		cell = fp.z;
		// Impacts flash hot-white; deaths, portals, crystal hits and skills keep their colour.
		float keep = (kind == 9 || kind == 10) ? 0.9 : (kind == 3 || kind == 4 || kind == 5 || kind == 12 || kind == 13 || kind == 14 || kind == 21 || kind == 22) ? 0.82 : 0.35;
		if (kind == 24) keep = 0.5;
		col = mix(elem_hot(elem), COLOR.rgb, keep);
	} else if (part == 2) {
		vec4 sp = spark_params(kind);
		vec4 ss = spark_shape(kind);
		int count = int(sp.x + 0.5);
		float f = clamp(age / sp.z, 0.0, 1.0);
		float h1 = hash11(seed * 13.0 + float(idx));
		float h2 = hash11(seed * 29.0 + float(idx) * 1.7);
		float ang = (float(idx) + h1 * 0.8) / max(float(count), 1.0) * 6.283;
		vec3 radial = normalize(mx * sin(ang) + fwd * cos(ang));
		vec3 dir = normalize(mix(radial, fwd, ss.x));
		float speed = sp.y * (0.7 + 0.6 * h2) * (kind == 24 ? size * 0.5 : impact);
		vec3 vel = dir * speed + up * (ss.y * speed * (0.5 + h1 * 0.5));
		float grav = ss.z * 6.0;
		vec3 start = origin + up * lift;
		if (kind == 24) start += radial * size * (0.3 + 0.6 * h2);
		vec3 at = start + vel * ease_out(f) * sp.z + up * (-0.5 * grav * f * f * sp.z * sp.z);
		vec3 now = vel * (1.0 - f) + up * (-grav * f * sp.z);
		vec3 along = normalize(now + vec3(0.0, 0.0001, 0.0));
		vec3 side = cross(along, cam_fwd);
		side = length(side) < 0.02 ? cam_right : normalize(side);
		float base = (kind == 22 ? 0.34 : kind == 12 ? 0.22 : kind == 13 ? 0.20 : kind == 20 ? 0.15 : kind == 23 ? 0.16 : kind == 24 ? 0.17 : 0.12) * (0.8 + 0.4 * h2);
		float len = base * sp.w * (1.3 - 0.6 * f) * (elem == 3 ? 1.5 : 1.0);
		float wid = base * (kind == 22 ? 0.85 : elem == 2 ? 0.9 : 0.55);
		world = at + along * c.y * len + side * c.x * wid - cam_fwd * 0.26;
		cell = float(spark_cell(elem));
		if (kind == 4) cell = 6.0;
		// Scatter: soft wisps, not sparks.
		if (kind == 22) cell = 0.0;
		// A zone's last breath flings its own weather: shards, embers, bolts, drops, cards.
		if (kind == 24) cell = elem == 0 ? 37.0 : (elem == 2 && idx % 2 == 0) ? 46.0 : float(spark_cell(elem));
		if (kind == 24 && elem == 0) { wid = base * 1.2; len = base * 1.6; }
		col = mix(elem_tint(elem), elem_hot(elem), 0.45);
		if (kind == 4 || kind == 5 || kind == 14) col = mix(COLOR.rgb, vec3(1.0), 0.4);
		if (kind == 22) col = mix(COLOR.rgb, vec3(1.0), 0.2);
		if (kind == 23) col = mix(elem_hot(elem), elem_tint(elem), f * 0.8);
		alpha = (idx < count ? 1.0 : 0.0) * pow(1.0 - f, 1.1) * (kind == 22 ? 0.8 : 1.0);
		if (idx >= count) world = origin;
	} else if (part == 3) {
		vec4 mp = mote_params(kind, size);
		float f = clamp(age / mp.y, 0.0, 1.0);
		float h1 = hash11(seed * 3.7 + float(idx));
		float h2 = hash11(seed * 5.3 + float(idx) * 2.3);
		float h3 = hash11(seed * 9.1 + float(idx) * 0.7);
		float delay = h3 * 0.35;
		float g = clamp((f - delay) / max(1.0 - delay, 0.05), 0.0, 1.0);
		vec3 spread = (mx * (h1 - 0.5) + fwd * (h2 - 0.5)) * 2.0 * mp.z;
		vec3 at = origin + up * (lift * 0.5 + mp.x * ease_out(g)) + spread + mx * sin(g * 7.0 + h1 * 6.0) * 0.08;
		float s = mp.w * (0.7 + 0.6 * h2) * (1.0 - g * 0.45) * (elem == 2 ? 1.5 : 1.0);
		vec2 r = rot2(c, h1 * 6.283 + g * 2.0);
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.2;
		cell = float(mote_cell(kind == 3 || kind == 10 ? 0 : elem));
		if (kind == 10 || kind == 14 || kind == 21) cell = 2.0;
		if (kind == 24 && elem == 2) cell = 34.0;
		if (kind == 24 && elem == 0) cell = 1.0;
		col = mix(mix(COLOR.rgb, elem_tint(elem), 0.5), vec3(1.0), 0.25);
		alpha = pow(sin(g * 3.14159), 0.8) * (mp.w > 0.001 ? 0.95 : 0.0);
	} else if (part == 5 && kind == 20) {
		// Blade contact: a crescent cut mark that snaps open along the blade's travel
		// direction in the screen plane and fades; the sparks above fly the same way.
		float f = clamp(age / 0.20, 0.0, 1.0);
		vec3 along = fwd - cam_fwd * dot(fwd, cam_fwd);
		along = length(along) < 0.02 ? cam_right : normalize(along);
		vec3 side = normalize(cross(along, cam_fwd));
		float len = size * (0.56 + 0.36 * ease_out3(min(f * 3.0, 1.0)));
		float wid = size * 0.21 * (1.0 - 0.4 * f);
		world = origin + along * c.y * len + side * c.x * wid - cam_fwd * 0.36;
		cell = 11.0;
		alpha = pow(1.0 - f, 1.2);
		col = mix(elem_hot(elem), COLOR.rgb, 0.3);
	} else if (part == 5) {
		vec4 qp = ring2_params(kind, size);
		float f = clamp(age / qp.y, 0.0, 1.0);
		float s = qp.x * (0.35 + 0.65 * ease_out3(f));
		if (kind == 23) s = qp.x * (0.2 + 0.8 * ease_out3(f * 1.6));
		vec3 r_axis = cam_right;
		vec3 u_axis = cam_up;
		if (kind == 3) {
			// A rising halo above the fallen body.
			world = origin + up * (lift + 0.35 * f);
		} else {
			world = origin + up * lift;
		}
		world += (r_axis * c.x + u_axis * c.y) * s - cam_fwd * 0.34;
		cell = qp.z;
		alpha = pow(1.0 - f, 1.4) * (qp.x > 0.001 ? 0.9 : 0.0);
		col = mix(COLOR.rgb, vec3(1.0), 0.3);
		if (kind == 23) col = mix(elem_hot(elem), elem_tint(elem), 0.4);
	} else if (part == 7) {
		// Plume: a column that shoots up and thins out (dust of a splash, the breath that
		// leaves a big body, a zone's last exhale).
		vec4 pp = plume_params(kind, size);
		float f = clamp(age / max(pp.z, 0.01), 0.0, 1.0);
		float hgt = pp.x * ease_out3(f * 2.2) * (1.0 + 0.15 * f);
		float wid = pp.y * (0.7 + 0.5 * f);
		world = origin + up * (lift * 0.3) + up * (c.y + 0.5) * hgt + pillar_side * c.x * wid - cam_fwd * 0.3;
		cell = 47.0;
		alpha = pow(1.0 - f, 1.5) * (kind == 24 ? 0.9 : 0.75) * (pp.x > 0.001 ? 1.0 : 0.0);
		col = mix(elem_tint(elem), elem_hot(elem), 0.35);
		if (kind == 3) col = mix(COLOR.rgb, vec3(1.0), 0.45);
		if (kind == 1 && elem == 0) col = vec3(0.85, 0.78, 0.65);
		if (pp.x <= 0.001) world = origin;
	} else {
		// Accents x6.
		float h1 = hash11(seed * 19.0 + float(idx) * 2.3);
		float h2 = hash11(seed * 37.0 + float(idx) * 0.9);
		float a = 0.0;
		vec3 at = origin + up * lift;
		float s = 0.0;
		float turn = h1 * 6.283;
		bool placed = false;     // the branch put the quad in the world itself (streaks)
		if (kind == 23 && idx == 0) {
			// The ray burst: snaps open with overshoot in the screen plane.
			float f = clamp(age / 0.24, 0.0, 1.0);
			s = 2.0 * impact * overshoot(f * 2.5) * (1.0 - 0.25 * f);
			a = pow(1.0 - f, 1.3);
			turn = seed * 6.283 + f * 0.6;
			cell = 45.0;
			col = mix(vec3(1.0), elem_hot(elem), 0.5);
		} else if (kind == 23) {
			// Long streaks on through the body, along the shot.
			float f = clamp(age / 0.30, 0.0, 1.0);
			float ang = (float(idx) - 3.0) * 0.42 + (h1 - 0.5) * 0.3;
			vec3 dir = normalize(fwd * cos(ang) + mx * sin(ang) + up * (0.2 + 0.4 * h2));
			float reach = (1.3 + 1.2 * h2) * impact;
			vec3 head = at + dir * reach * ease_out3(f);
			vec3 along = dir - cam_fwd * dot(dir, cam_fwd);
			along = length(along) < 0.02 ? cam_right : normalize(along);
			vec3 side = normalize(cross(along, cam_fwd));
			float len = 0.6 * impact * (1.0 - 0.5 * f);
			world = head - along * c.y * len + side * c.x * 0.12 - cam_fwd * 0.3;
			cell = 27.0;
			a = pow(1.0 - f, 1.2);
			col = mix(elem_hot(elem), elem_tint(elem), 0.3);
			placed = true;
		} else if (kind == 3) {
			// The kill pop: six sparkles snap out in a ring and wink out.
			float f = clamp(age / 0.36, 0.0, 1.0);
			float ang = float(idx) * 1.0472 + seed * 6.283;
			float reach = (0.55 + 0.35 * h2) * size * overshoot(f * 1.6);
			at = origin + up * (lift + 0.25 * size) + (cam_right * cos(ang) + cam_up * sin(ang)) * reach;
			s = (0.22 + 0.12 * h1) * size * (1.0 - 0.5 * f);
			a = pow(1.0 - f, 0.9) * (0.75 + 0.25 * step(0.5, fract(vfx_time * 24.0 + h1 * 5.0)));
			cell = 2.0;
			col = mix(COLOR.rgb, vec3(1.0), 0.55);
		} else if (kind == 20 && idx < 4) {
			// Bright chips flung along the blade's travel.
			float f = clamp(age / 0.34, 0.0, 1.0);
			vec3 dir = normalize(fwd * (0.7 + 0.3 * h2) + mx * (h1 - 0.5) * 0.9 + up * (0.6 + 0.8 * h2));
			vec3 vel = dir * (2.0 + 1.6 * h1) * impact;
			at = origin + vel * f * 0.34 + up * (-0.5 * 7.0 * f * f * 0.34 * 0.34);
			s = 0.10 + 0.06 * h2;
			turn = h1 * 6.283 + f * (6.0 + 8.0 * h2);
			a = pow(1.0 - f, 0.8);
			cell = 46.0;
			col = mix(elem_hot(elem), COLOR.rgb, 0.4);
		} else if (kind == 24 && elem == 2) {
			// Rime shatter: the standing crystals burst into shards that fly up and out.
			float f = clamp(age / 0.6, 0.0, 1.0);
			float ang = float(idx) * 1.0472 + h1 * 0.6 + seed * 6.283;
			vec3 dir = mx * cos(ang) + fwd * sin(ang);
			vec3 vel = dir * (1.2 + 1.5 * h2) * size * 0.45 + up * (2.6 + 2.2 * h1);
			at = origin + dir * size * 0.5 + up * 0.4 + vel * f * 0.6 + up * (-0.5 * 9.0 * f * f * 0.36);
			s = 0.16 + 0.1 * h2;
			turn = h1 * 6.283 + f * (4.0 + 6.0 * h2);
			a = pow(1.0 - f, 0.7);
			cell = 46.0;
			col = mix(vec3(0.85, 0.96, 1.0), vec3(1.0), 0.4);
		} else if (kind == 1 && idx < 4) {
			// Dust streaks thrown up out of the splash.
			float f = clamp(age / 0.30, 0.0, 1.0);
			float ang = float(idx) * 1.5708 + h1 * 0.8 + seed * 6.283;
			vec3 dir = normalize(mx * cos(ang) * 0.5 + fwd * sin(ang) * 0.5 + up * (1.4 + 0.8 * h2));
			float reach = (0.6 + 0.7 * h2) * clamp(size, 0.6, 1.6);
			vec3 head = origin + up * 0.2 + dir * reach * ease_out3(f);
			vec3 along = dir - cam_fwd * dot(dir, cam_fwd);
			along = length(along) < 0.02 ? cam_up : normalize(along);
			vec3 side = normalize(cross(along, cam_fwd));
			world = head - along * c.y * 0.3 * (1.0 - 0.4 * f) + side * c.x * 0.08 - cam_fwd * 0.3;
			cell = 27.0;
			a = pow(1.0 - f, 1.3) * 0.8;
			col = mix(elem_tint(elem), elem_hot(elem), 0.5);
			if (elem == 0) col = vec3(0.9, 0.84, 0.7);
			placed = true;
		}
		if (!placed) {
			vec2 r = rot2(c, turn);
			world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.3;
			if (s <= 0.001) a = 0.0;
		}
		alpha = a;
		if (a <= 0.0) world = origin;
	}
	if (part != 0) world -= cam_fwd * (body - 1.0) * BODY_CLEAR;
	v_tint = vec4(col, alpha);
	v_cell = cell;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	if (v_cell < -0.5) {
		// Procedural shock ring: crisp hot leading edge, soft trailing wake.
		float d = length(v_plane);
		float r = v_ring.x;
		float w = max(v_ring.y, 0.004);
		float lead = smoothstep(r - w * 0.35, r, d) * (1.0 - smoothstep(r, r + w * 1.4, d));
		float wake = (1.0 - smoothstep(r * 0.55, r, d)) * v_ring.w;
		a = lead + wake;
		if (v_ring.z > 0.5) a *= smoothstep(-0.25, 0.55, v_plane.y);
		a *= 1.0 - smoothstep(0.9, 1.0, d);
	} else if (v_cell > 12.5 && v_cell < 13.5) {
		vec2 uv = fract(UV * 2.0);
		float hex = texture(sprites, cell_uv(13, uv)).a;
		float disc = texture(sprites, cell_uv(0, UV)).a;
		a = hex * disc * 1.6 + disc * 0.25;
	} else if (v_cell > 31.5) {
		a = texture(zone_sprites, cell_uv(int(v_cell + 0.5) - 32, UV)).a;
	} else if (v_cell > 15.5) {
		a = texture(skill_sprites, cell_uv(int(v_cell + 0.5) - 16, UV)).a;
	} else {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	}
	ALBEDO = mix(v_tint.rgb, v_tint.rgb * v_tint.rgb * 1.25, vfx_wash * 0.6);
	ALPHA = (clamp(a, 0.0, 1.0) * v_tint.a) * mix(1.0, 0.66, vfx_wash);
}
