shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Alpha-blended layer of vfx_skill.gdshader (same instance contract): ground cracks and
// scorch, the dark ring under the shock ring (what keeps the blast readable on bright snow
// and ice, where additive gold alone washes out), smoke, flung debris and the gate's mist.
// Parts (UV2.x): 20 cracks  21 dark ring  22 smoke x6  23 debris x10  24 mist x8
// Colours are linear values: ACES + sRGB output lifts them, so 0.15..0.3 reads mid-tone.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
uniform float vfx_epoch = 0.0;

const float HIT = 0.18;

varying vec4 v_tint;
varying float v_cell;
varying vec2 v_plane;
varying vec4 v_ring;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 mx = normalize(MODEL_MATRIX[0].xyz);
	vec3 fwd = normalize(-MODEL_MATRIX[2].xyz);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	float birth = INSTANCE_CUSTOM.x;
	float R = max(INSTANCE_CUSTOM.y, 0.2);
	float dur = max(INSTANCE_CUSTOM.z, 0.5);
	int kind = int(INSTANCE_CUSTOM.w + 0.5);
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float seed = hash11(birth * 5.17 + float(INSTANCE_ID) * 0.311);
	float prog = clamp(age / dur, 0.0, 1.0);
	float live = age < dur ? 1.0 : 0.0;
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	v_plane = c * 2.0;
	v_ring = vec4(0.0);
	v_cell = 0.0;
	vec3 soot = vec3(0.045, 0.03, 0.022);
	vec3 dust = vec3(0.24, 0.27, 0.33);
	vec3 lit = vec3(0.52, 0.27, 0.08);
	vec3 gate_dark = vec3(0.06, 0.008, 0.05);
	vec3 gate_lit = vec3(0.30, 0.13, 0.17);
	if (part == 20) {
		float s = R;
		float a = 0.0;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 1.9, 0.0, 1.0);
				s = R * 1.45;
				a = 0.85 * pow(1.0 - f, 1.1) * smoothstep(0.0, 0.04, t);
				col = soot;
			}
		} else if (kind == 1) {
			// The ground fractures outward from the gate as it charges.
			float grow = ease_out(clamp(age / (dur * 0.6), 0.0, 1.0));
			s = R * (0.5 + 1.0 * grow);
			a = (0.15 + 0.75 * prog) * grow * live;
			col = vec3(0.05, 0.01, 0.03);
		} else {
			float f = clamp(age / 2.2, 0.0, 1.0);
			s = R * 2.0;
			a = 0.9 * pow(1.0 - f, 0.9);
			col = vec3(0.04, 0.02, 0.03);
		}
		vec2 rr = rot2(c, seed * 6.283);
		world = origin + up * 0.07 + (mx * rr.x + fwd * rr.y) * 2.0 * s;
		alpha = a;
		v_cell = 18.0;
	} else if (part == 21) {
		float r = 0.0;
		float w = 0.0;
		float fill = 0.0;
		float a = 0.0;
		float rmax = 1.0;
		if (kind == 0) {
			// Deep amber band under the additive shock ring, same radius curve.
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.30, 0.0, 1.0);
				r = mix(0.15, R, ease_out3(f));
				w = mix(0.48, 0.30, f) * 1.4;
				float fade = 1.0 - clamp((t - 0.30) / 0.55, 0.0, 1.0);
				a = 0.62 * pow(fade, 1.1);
				col = vec3(0.30, 0.13, 0.03);
			}
			rmax = R + 0.7;
		} else if (kind == 1) {
			float throb = 0.75 + 0.25 * sin(age * (3.0 + 6.0 * prog));
			r = R * (0.9 + 0.1 * sin(age * 2.0));
			w = 0.55;
			a = (0.15 + 0.3 * prog) * throb * live;
			col = gate_dark;
			rmax = R * 2.1;
		} else {
			float f = clamp(age / 0.55, 0.0, 1.0);
			r = mix(0.2, R * 2.8, ease_out3(f));
			w = mix(0.75, 0.45, f) * 1.4;
			a = 0.6 * pow(1.0 - clamp((age - 0.2) / 0.6, 0.0, 1.0), 1.1);
			fill = 0.35 * pow(1.0 - clamp(age / 0.5, 0.0, 1.0), 1.2);
			col = vec3(0.16, 0.10, 0.12);
			rmax = R * 3.0 + 0.8;
		}
		world = origin + up * 0.075 + mx * c.x * 2.0 * rmax + fwd * c.y * 2.0 * rmax;
		v_ring = vec4(r / rmax, w / rmax, fill, 0.0);
		alpha = a;
		v_cell = -1.0;
	} else if (part == 22) {
		float h1 = hash11(seed * 4.1 + float(idx));
		float h2 = hash11(seed * 6.7 + float(idx) * 1.9);
		float ang = (float(idx) + h1 * 0.8) / 6.0 * 6.283;
		vec3 radial = mx * cos(ang) + fwd * sin(ang);
		float a = 0.0;
		float s = 0.0;
		float rot = h1 * 6.283;
		vec3 at = origin;
		if (kind == 0) {
			// Smoke lit gold by the impact, cooling to dust as it rises and spreads.
			float t = age - HIT - h1 * 0.08;
			float life = 1.3 + 0.3 * h2;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				s = mix(0.5, 2.1, ease_out3(f)) * (0.85 + 0.3 * h2);
				at = origin + radial * R * 0.55 * (0.3 + 0.7 * ease_out(f)) + up * (0.35 + 1.1 * f);
				rot += f * (h2 - 0.5) * 2.0;
				col = mix(lit, dust, smoothstep(0.0, 0.45, f));
				a = 0.6 * pow(1.0 - f, 1.3) * smoothstep(0.0, 0.06, f);
			}
		} else if (kind == 1) {
			// Looping dark mist circulating over the gate, denser as it charges.
			float cycle = 2.6 + 0.6 * h2;
			float ph = fract(age / cycle + h1);
			float turn = h2 * 6.283 + age * 0.5;
			vec3 rad2 = mx * cos(turn) + fwd * sin(turn);
			at = origin + rad2 * R * (0.35 + 0.5 * ph) + up * (0.15 + 0.5 * ph);
			s = 0.6 + 0.9 * ph;
			rot += age * 0.4;
			col = mix(gate_dark, gate_lit, 0.25 * prog);
			a = (0.3 + 0.55 * prog) * pow(sin(ph * 3.14159), 0.8) * live;
		} else {
			float t = age - h1 * 0.05;
			float life = 1.7 + 0.4 * h2;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				s = mix(0.8, 3.4, ease_out3(f));
				at = origin + radial * (0.3 + 2.2 * R * ease_out(f)) + up * (0.4 + 1.6 * f);
				rot += f * (h2 - 0.5) * 1.5;
				col = mix(gate_lit, vec3(0.20, 0.17, 0.17), smoothstep(0.0, 0.5, f));
				a = 0.6 * pow(1.0 - f, 1.2) * smoothstep(0.0, 0.05, f);
			}
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.12;
		if (a <= 0.0) world = origin;
		alpha = a;
		v_cell = 4.0;
	} else if (part == 23) {
		float h1 = hash11(seed * 7.3 + float(idx));
		float h2 = hash11(seed * 11.9 + float(idx) * 1.3);
		float h3 = hash11(seed * 19.7 + float(idx) * 0.9);
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin;
		float rot = h1 * 6.283;
		bool show = false;
		float t = age;
		float life = 1.0;
		float g = 10.0;
		vec3 vel = vec3(0.0);
		if (kind == 0 && idx < 6) {
			// A few dark clods thrown up with the star fragments: the impact has weight.
			t = age - HIT;
			life = 0.8 + 0.3 * h3;
			float ang = (float(idx) + h1 * 0.9) / 6.0 * 6.283;
			vel = (mx * sin(ang) + fwd * cos(ang)) * (1.5 + 2.5 * h2) + up * (4.0 + 4.0 * h1);
			g = 12.0;
			s = 0.08 + 0.08 * h2;
			col = soot;
			show = true;
		} else if (kind == 2) {
			life = 1.1 + 0.4 * h3;
			float ang = (float(idx) + h1 * 0.9) / 10.0 * 6.283;
			vel = (mx * sin(ang) + fwd * cos(ang)) * (2.0 + 4.0 * h2) + up * (4.5 + 5.0 * h1);
			g = 10.0;
			s = 0.14 + 0.14 * h2;
			col = vec3(0.05, 0.035, 0.04);
			show = true;
		}
		if (show && t >= 0.0 && t < life) {
			at = origin + up * 0.2 + vel * t + up * (-0.5 * g * t * t);
			rot += t * (4.0 + 6.0 * h2) * (h3 < 0.5 ? -1.0 : 1.0);
			a = (at.y > 0.0 ? 1.0 : 0.0) * 0.95 * (1.0 - smoothstep(0.7, 1.0, t / life));
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
		if (a <= 0.0) world = origin;
		alpha = a;
		v_cell = 22.0;
	} else {
		float h1 = hash11(seed * 2.9 + float(idx));
		float h2 = hash11(seed * 8.3 + float(idx) * 1.1);
		float h3 = hash11(seed * 12.1 + float(idx) * 0.6);
		float a = 0.0;
		float s = 0.0;
		float rot = h1 * 6.283;
		vec3 at = origin;
		if (kind == 1) {
			// Low ground fog creeping around the gate.
			float cycle = 3.0 + 1.5 * h2;
			float ph = fract(age / cycle + h3);
			float turn = h2 * 6.283 + age * 0.35 * (1.0 + prog);
			at = origin + (mx * cos(turn) + fwd * sin(turn)) * R * (0.25 + 0.9 * h3) * (1.0 - 0.2 * ph)
				+ up * (0.1 + 0.25 * h1);
			s = 0.9 + 0.8 * h1;
			rot += age * 0.25 * (h2 - 0.5);
			col = gate_dark;
			a = (0.35 + 0.5 * prog) * (0.6 + 0.4 * sin(age * 1.5 + h1 * 6.0)) * live;
		} else if (kind == 2) {
			// Wisps blasted outward at the arrival.
			float f = clamp(age / 1.2, 0.0, 1.0);
			float turn = h2 * 6.283;
			at = origin + (mx * cos(turn) + fwd * sin(turn)) * (0.4 + 3.0 * R * ease_out3(f)) + up * (0.3 + 0.5 * f);
			s = 0.8 + 1.2 * f;
			rot += f * (h1 - 0.5) * 3.0;
			col = vec3(0.12, 0.03, 0.10);
			a = 0.55 * pow(1.0 - f, 1.2);
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.1;
		if (a <= 0.0) world = origin;
		alpha = a;
		v_cell = 23.0;
	}
	v_tint = vec4(col, alpha);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	if (v_cell < -0.5) {
		float d = length(v_plane);
		float r = v_ring.x;
		float w = max(v_ring.y, 0.004);
		float band = smoothstep(r - w, r, d) * (1.0 - smoothstep(r, r + w, d));
		float fill = (1.0 - smoothstep(r * 0.4, r, d)) * v_ring.z;
		a = (band + fill) * (1.0 - smoothstep(0.9, 1.0, d));
	} else if (v_cell < 15.5) {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	} else {
		a = texture(skill_sprites, cell_uv(int(v_cell + 0.5) - 16, UV)).a;
	}
	ALBEDO = v_tint.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * v_tint.a;
}
