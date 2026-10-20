shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Alpha-blended bodies under and around a zone (same instance contract as vfx_zone):
//   part 0  dark ground base under a landed zone, so the additive runes stay legible on
//           bright snow and ice
//   part 8  mist x4 at the foot of the column: frost mist, lingering smoke, foam, haze
//   part 9  the floor's body: frost under an ice zone, soot and a dark pool under a magma
//           zone, a wet sheen under a geyser, a violet cloth under a card storm
// Caster circles draw nothing here. Colours are linear values.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D zone_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
uniform float vfx_wash = 0.0;


varying vec4 v_tint;
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
	float seed = hash21(origin.xz * 0.37 + vec2(11.0, 7.0));
	float landed = clamp((t - delay) / 0.15, 0.0, 1.0);
	float since = t - delay;
	float pulse = (!cast && since > 0.0) ? exp(-fract(since / tick) * tick * 7.0) : 0.0;
	float remain = 0.6 + 0.4 * COLOR.a;
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = vec3(0.02, 0.03, 0.05);
	float alpha = 0.0;
	v_plane = c * 2.0;
	v_cell = -1.0;
	if (part == 0) {
		world = origin + vec3(0.0, 0.04, 0.0) + (ux * c.x + uz * c.y) * 2.0 * radius;
		alpha = cast ? 0.0 : landed * (0.35 + 0.25 * COLOR.a);
	} else if (cast) {
		alpha = 0.0;
	} else if (part == 8) {
		float h1 = hash11(seed * 4.1 + float(idx));
		float h2 = hash11(seed * 6.7 + float(idx) * 1.9);
		float h3 = hash11(seed * 9.3 + float(idx) * 0.6);
		float cycle = 1.6 + 0.8 * h3;
		float ph = fract(max(since, 0.0) / cycle + h1);
		float turn = h2 * TAU + since * 0.9;
		vec3 radial = ux * cos(turn) + uz * sin(turn);
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin;
		if (elem == 2) {
			// Frost mist rolling around the foot of the blizzard.
			at = origin + radial * radius * (0.45 + 0.35 * ph) + up * (0.12 + 0.2 * ph);
			s = 0.7 + 0.8 * ph;
			col = mix(vec3(0.42, 0.58, 0.78), vec3(0.20, 0.34, 0.58), vfx_wash);
			a = 0.7 * pow(sin(ph * 3.14159), 0.8);
		} else if (elem == 1) {
			// Smoke leaning away from the eruption, thickening after each gout.
			at = origin + radial * radius * (0.3 + 0.6 * ph) + up * (0.35 + 1.6 * ph);
			s = 0.9 + 1.7 * ph;
			col = mix(vec3(0.08, 0.06, 0.05), vec3(0.45, 0.16, 0.04), (1.0 - ph) * 0.5 * pulse);
			a = 0.9 * pow(sin(ph * 3.14159), 0.9);
		} else if (elem == 4) {
			// Foam spreading low over the water.
			at = origin + radial * radius * (0.35 + 0.5 * ph) + up * (0.08 + 0.1 * ph);
			s = 0.65 + 0.9 * ph;
			col = mix(vec3(0.62, 0.74, 0.85), vec3(0.30, 0.45, 0.70), vfx_wash);
			a = 0.5 * pow(sin(ph * 3.14159), 0.8);
		} else if (elem == 0) {
			at = origin + radial * radius * (0.3 + 0.5 * ph) + up * (0.2 + 0.7 * ph);
			s = 0.75 + 1.0 * ph;
			col = vec3(0.22, 0.10, 0.36);
			a = 0.45 * pow(sin(ph * 3.14159), 0.8);
		} else {
			// Thunder: a little dust kicked up by the strikes.
			at = origin + radial * radius * (0.3 + 0.5 * h3) + up * (0.1 + 0.25 * ph);
			s = 0.45 + 0.5 * ph;
			col = vec3(0.26, 0.28, 0.34);
			a = 0.22 * pulse * (1.0 - ph);
		}
		a *= smoothstep(0.0, 0.2, since) * remain;
		vec2 r = rot2(c, h1 * TAU + since * (h2 - 0.5) * 0.8);
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.15;
		alpha = a;
		v_cell = 4.0;
		if (a <= 0.0) world = origin;
	} else {
		// The floor's body.
		float a = 0.0;
		float turn = seed * TAU;
		float s = radius;
		if (elem == 2) {
			v_cell = 41.0;
			col = mix(vec3(0.50, 0.68, 0.86), vec3(0.22, 0.46, 0.72), vfx_wash);
			a = 0.55;
		} else if (elem == 1) {
			v_cell = 44.0;
			col = vec3(0.05, 0.02, 0.015);
			a = 0.7;
			s = radius * 1.04;
		} else if (elem == 4) {
			v_cell = 42.0;
			col = mix(vec3(0.04, 0.12, 0.32), vec3(0.03, 0.10, 0.36), vfx_wash);
			a = 0.7;
			turn = -since * 2.4;
		} else if (elem == 0) {
			v_cell = 42.0;
			col = vec3(0.20, 0.06, 0.34);
			a = 0.45;
			turn = since * 1.2;
		} else {
			v_cell = -2.0;
			a = 0.0;
		}
		a *= landed * remain;
		vec2 r = rot2(c, turn);
		world = origin + up * 0.055 + (ux * r.x + uz * r.y) * 2.0 * s;
		alpha = a;
		if (a <= 0.0) world = origin;
	}
	v_tint = vec4(col, alpha);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	if (v_cell < -1.5) {
		a = 0.0;
	} else if (v_cell < -0.5) {
		float d = length(v_plane);
		a = (1.0 - smoothstep(0.55, 0.97, d));
	} else if (v_cell > 31.5) {
		a = texture(zone_sprites, cell_uv(int(v_cell + 0.5) - 32, UV)).a;
	} else {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	}
	ALBEDO = v_tint.rgb;
	ALPHA = a * v_tint.a;
}
