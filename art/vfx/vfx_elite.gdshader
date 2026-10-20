shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// The elite's mark (2026-10-19, feedback O5 / PLAN M6), one per elite body, shared mesh and
// material (StellarVfx.elite_aura): a slow violet sigil on the ground under the body and a
// few motes rising round it. The body itself carries a violet line (StellarShading
// OUTLINE_ELITE_*). Alpha-blended in saturated violet with a dark edge, so it reads on
// snow and sand as well as on dark soil; the body stands over its middle.
//   node:   a child of the body root, scaled (ring radius, body height, ring radius) in the
//           root's units, so MODEL_MATRIX carries the world radius and height (the elite's
//           1.35 root scale included)
//   parts:  UV2.x 0 the ground sigil   1 motes x6
//   fade:   instance uniform pushed by StellarShading while the body dissolves
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
// Calibrated through ACES and the field grade like the ring colours (arena_world.gd).
uniform vec4 core : source_color = vec4(0.62, 0.32, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.42, 0.13, 0.86, 1.0);
uniform vec4 edge : source_color = vec4(0.10, 0.02, 0.16, 0.62);
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;

varying vec4 v_tint;
varying vec2 v_plane;
varying float v_part;
varying float v_radius;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float radius = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec4 tint = vec4(0.0);
	v_plane = c * 2.0;
	v_radius = radius;
	if (part == 0) {
		// Ground sigil: the quad lies on the ground, 1.0 = the ring's world radius.
		world = origin + vec3(0.0, 0.035, 0.0) + vec3(c.x, 0.0, c.y) * 2.0 * radius * 1.12;
		tint = vec4(1.0);
	} else {
		// Motes: rise round the body, each on its own slow orbit and cycle.
		float fi = float(idx);
		float h1 = hash11(fi * 3.7 + 0.41);
		float h2 = hash11(fi * 5.3 + 1.37);
		float cycle = 1.4 + 0.6 * h2;
		float ph = fract(vfx_time / cycle + h1);
		float ang = fi * 1.047 + h1 * 1.2 + vfx_time * (0.6 + 0.4 * h2);
		vec3 at = origin + vec3(cos(ang), 0.0, sin(ang)) * radius * (0.78 + 0.12 * h2)
			+ vec3(0.0, height * (0.08 + 1.0 * ph), 0.0);
		float s = (0.075 + 0.035 * h2) * clamp(height / 0.9, 0.8, 1.6) * (1.0 - 0.35 * ph);
		vec2 rr = rot2(c, h1 * 6.283 + ph * 2.5);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s * 2.0 - cam_fwd * 0.15;
		tint = vec4(mix(vec3(0.95, 0.86, 1.0), core.rgb, ph), pow(sin(ph * 3.14159), 0.8) * 0.95);
	}
	v_part = float(part);
	v_tint = tint;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

float inside(float sdf, float upp) {
	return 1.0 - smoothstep(-0.5 * upp, 0.5 * upp, sdf);
}

vec4 over(vec4 top, vec4 under) {
	return top + under * (1.0 - top.a);
}

vec4 stroke(float sdf, float upp, float halo, vec3 rgb) {
	float c = inside(sdf, upp);
	float e = inside(sdf - halo, upp);
	return over(vec4(rgb, 1.0) * c, vec4(edge.rgb, 1.0) * (edge.a * clamp(e - c, 0.0, 1.0)));
}

void fragment() {
	vec4 acc;
	if (v_part < 0.5) {
		// In units of the ring radius (the quad spans 1.12 of it each way).
		vec2 p = v_plane * 1.12;
		float d = length(p);
		float upp = max(length(vec2(dFdx(d), dFdy(d))), 1e-5);
		float k = clamp(VIEWPORT_SIZE.y / 800.0, 0.78, 1.6);
		float breathe = 0.86 + 0.14 * sin(vfx_time * 5.0);
		// A violet wash that gathers to the outer ring.
		float fill = 0.20 * smoothstep(0.25, 0.92, d) * (1.0 - smoothstep(0.92 - upp, 0.92, d));
		acc = vec4(deep.rgb, 1.0) * fill * breathe;
		// The inner ring: six dashes turning against the outer marks.
		float a_in = atan(p.y, p.x) + vfx_time * 0.7;
		float u = fract(a_in / 6.2831853 * 6.0) - 0.5;
		float dash = length(vec2(max(abs(u) * 6.2831853 * 0.62 / 6.0 - 0.17, 0.0), abs(d - 0.62))) - 0.6 * k * upp;
		acc = over(stroke(dash, upp, 1.2 * k * upp, deep.rgb), acc);
		// Three chevrons on the outer ring, turning slowly: the mark of a champion.
		float a_out = atan(p.y, p.x) - vfx_time * 0.45;
		float sector = 6.2831853 / 3.0;
		float local = (fract(a_out / sector + 0.5) - 0.5) * sector;
		vec2 q = vec2(cos(local), sin(local)) * d;
		float chev = max((abs(q.y) * 1.35 + q.x - 1.04) / 1.68, 0.80 - q.x);
		acc = over(stroke(chev, upp, 1.2 * k * upp, core.rgb * breathe), acc);
		// The outer ring.
		acc = over(stroke(abs(d - 0.92) - 1.1 * k * upp, upp, 1.4 * k * upp, core.rgb), acc);
	} else {
		float a = texture(sprites, cell_uv(2, UV)).a;
		acc = vec4(v_tint.rgb, 1.0) * (a * v_tint.a);
	}
	float alpha = acc.a * fade;
	if (alpha <= 0.002) discard;
	ALBEDO = acc.rgb / max(acc.a, 1e-4);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
