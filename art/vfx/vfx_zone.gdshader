shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Ground zones (sim.zones) and caster circles in one MultiMesh.
//   transform: origin on the ground, XZ scale = radius (world units)
//   COLOR:     rgb colour, a = remaining life fraction (zones) or 1
//   CUSTOM:    x age t  y delay (>= 0 zone; -1 caster circle, then x = wind-up progress 0..1)
//              z tick interval  w element
// Parts (UV2.x): 0 rune disc, 1 motes x8 (UV2.y index).
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue.
uniform float vfx_wash = 0.0;

varying vec4 v_tint;
varying vec4 v_state;   // mode(0 zone,1 cast), landed fraction, pulse, element
varying vec2 v_plane;
varying float v_cell;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 mx = MODEL_MATRIX[0].xyz;
	vec3 mz = MODEL_MATRIX[2].xyz;
	float radius = max(length(mx), 0.001);
	vec3 ux = mx / radius;
	vec3 uz = mz / max(length(mz), 0.001);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	float t = INSTANCE_CUSTOM.x;
	float delay = INSTANCE_CUSTOM.y;
	float tick = max(INSTANCE_CUSTOM.z, 0.05);
	int elem = int(INSTANCE_CUSTOM.w + 0.5);
	bool cast = delay < -0.5;
	float seed = float(INSTANCE_ID) * 0.31 + 0.7;
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	float alpha = 0.0;
	vec3 col = COLOR.rgb;
	float landed = cast ? clamp(t, 0.0, 1.0) : clamp((t - delay) / 0.12, 0.0, 1.0);
	float pulse = 0.0;
	if (!cast && t > delay) pulse = exp(-fract((t - delay) / tick) * tick * 7.0);
	v_plane = c * 2.0;
	if (part == 0) {
		// Telegraph: a converging ring; landed: the full rune disc.
		float grow = cast ? (0.55 + 0.45 * landed) : (t < delay ? 1.25 - 0.25 * clamp(t / max(delay, 0.01), 0.0, 1.0) : 1.0);
		world = origin + up * 0.05 + (ux * c.x + uz * c.y) * 2.0 * radius * grow;
		alpha = cast ? 0.35 + 0.65 * landed : (t < delay ? 0.45 + 0.4 * clamp(t / max(delay, 0.01), 0.0, 1.0) : 1.0);
		alpha *= cast ? 1.0 : (0.55 + 0.45 * COLOR.a);
		v_cell = 12.0;
	} else {
		float h1 = hash11(seed * 3.7 + float(idx));
		float h2 = hash11(seed * 5.3 + float(idx) * 2.3);
		float h3 = hash11(seed * 9.1 + float(idx) * 0.7);
		float cycle = 0.75 + 0.35 * h3;
		float phase = fract(vfx_time / cycle + h1);
		float ang = h2 * 6.283;
		float dist = sqrt(h1) * radius * 0.85;
		float rise = elem == 1 ? 1.1 : elem == 4 ? 0.45 : 0.75;
		vec3 at = origin + ux * cos(ang) * dist + uz * sin(ang) * dist + up * (0.08 + rise * phase);
		if (elem == 4) at += up * sin(phase * 12.0 + float(idx)) * 0.06;
		float s = (0.06 + 0.05 * h2) * (1.0 - phase * 0.5) * (elem == 2 ? 1.6 : 1.0) * (radius > 1.2 ? 1.3 : 1.0);
		vec2 r = rot2(c, h1 * 6.283 + phase * 3.0);
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.2;
		float present = cast ? landed : (t > delay ? 1.0 : 0.0);
		alpha = pow(sin(phase * 3.14159), 0.8) * present * (0.6 + 0.4 * COLOR.a);
		col = mix(mix(COLOR.rgb, elem_tint(elem), 0.5), vec3(1.0), 0.3);
		v_cell = float(mote_cell(elem));
		if (cast) v_cell = 2.0;
	}
	v_tint = vec4(col, alpha);
	v_state = vec4(cast ? 1.0 : 0.0, landed, pulse, float(elem));
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	if (v_cell > 11.5 && v_cell < 12.5) {
		vec2 p = v_plane;
		float d = length(p);
		float ang = atan(p.y, p.x);
		float spin = vfx_time * (v_state.x > 0.5 ? 1.6 : 0.7);
		vec2 ruv = rot2(p, spin) * 0.5 + 0.5;
		vec2 ruv2 = rot2(p, -spin * 0.6) * 0.5 + 0.5;
		float rune = texture(sprites, cell_uv(12, ruv)).a;
		float rune2 = texture(sprites, cell_uv(12, ruv2 * 0.8 + 0.1)).a * (1.0 - smoothstep(0.55, 0.62, d));
		float edge = exp(-pow((d - 0.94) / 0.045, 2.0));
		float outer_fade = 1.0 - smoothstep(0.97, 1.0, d);
		float shimmer = texture(noise_tex, p * 0.9 + vec2(vfx_time * 0.08, -vfx_time * 0.05)).r;
		float ticks = pow(abs(sin(ang * 16.0 - spin * 3.0)), 24.0) * smoothstep(0.80, 0.86, d) * (1.0 - smoothstep(0.90, 0.93, d));
		if (v_state.x > 0.5) {
			// Caster circle: ring + inner runes brightening with the wind-up.
			a = edge * 1.2 + rune * 0.75 * v_state.y + ticks * 0.8 + (1.0 - smoothstep(0.0, 0.9, d)) * 0.08 * v_state.y;
		} else if (v_state.y < 0.999) {
			// Telegraph ring: dashed converging outline, inner wash grows while it lands.
			float dashes = step(0.5, fract(ang * 3.82 + vfx_time * 1.5));
			a = edge * (0.35 + 0.65 * dashes) + (1.0 - smoothstep(0.2, 0.95, d)) * 0.10 * v_state.y + rune * 0.4 * v_state.y;
		} else {
			float fill = (1.0 - smoothstep(0.0, 0.95, d)) * (0.10 + 0.18 * v_state.z);
			a = edge * (0.9 + 0.6 * v_state.z) + rune * 0.55 + rune2 * 0.25 + ticks * 0.6 + fill * (0.6 + 0.8 * shimmer);
			// Water zones ripple outward; fire zones breathe.
			if (v_state.w > 3.5) a += exp(-pow((fract(d * 2.0 - vfx_time * 1.2) - 0.5) / 0.08, 2.0)) * 0.25 * (1.0 - d);
			if (v_state.w > 0.5 && v_state.w < 1.5) a *= 0.85 + 0.25 * sin(vfx_time * 9.0 + d * 8.0);
		}
		a *= outer_fade;
	} else {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	}
	ALBEDO = mix(v_tint.rgb, v_tint.rgb * v_tint.rgb * 1.25, vfx_wash * 0.6);
	ALPHA = (clamp(a, 0.0, 1.0) * v_tint.a) * mix(1.0, 0.66, vfx_wash);
}
