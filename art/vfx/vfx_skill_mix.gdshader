shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Alpha-blended layer of vfx_skill.gdshader (same instance contract): ground cracks and
// scorch, the dark ring under the shock ring (what keeps the blast readable on bright snow
// and ice, where additive gold alone washes out), smoke, flung debris and the gate's mist.
// Parts (UV2.x): 20 cracks  21 dark ring  22 smoke x6  23 debris x10  24 mist x8
//   25 sigil body  26 ground colour (both drawn first, bright fields only)
//   27 trail smoke x5 (the meteor's smoky wake, 2026-10-17)
// Colours are linear values: ACES + sRGB output lifts them, so 0.15..0.3 reads mid-tone.
//
// Body + light on bright fields (2026-10-13). Additive gold or crimson on a pale floor is
// white: the lock-on sigil, the boss rune and the colour of the struck ground vanished on
// the brightest battlefields. Where the floor is bright (vfx_wash = ArenaWorld.ground_wash,
// 0 up to L* 57, 1 from L* 67) parts 25 and 26 paint those marks in saturated mid-tones
// under the additive ones and the ring band takes the effect's colour. Everything added
// here is scaled by vfx_wash: on a dark field (0) the quads collapse and the ring keeps
// its old ink, so the picture there is exactly what it was.
// Frost pulse (kind 3): a pale band under the wavefront, frost mist along it, low fog
// behind it and, on bright floors, a deep blue wash inside the wave.
// Level-up (kind 4): gold on the altar for bright floors only.
// Elite entrance (kind 5): the boss arrival's bodies, smaller (bk) and violet (see
// vfx_skill.gdshader). Hero arrival (kind 6): gold on the landing spot, bright floors only.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D zone_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
uniform float vfx_epoch = 0.0;
uniform float vfx_wash = 0.0;

const float HIT = 0.32;        // StellarVfx.BLAST_FALL
const float FREEZE_SEC = 0.95;
const float RISE = 0.45;
const float ARRIVE = 0.28;

varying vec4 v_tint;
varying float v_cell;
varying vec2 v_plane;
varying vec4 v_ring;

float freeze_wave(float t, float R) {
	return mix(0.4, R, ease_out3(t / FREEZE_SEC));
}

float freeze_arrival(float r, float R) {
	float f = clamp((r - 0.4) / max(R - 0.4, 0.01), 0.0, 1.0);
	return FREEZE_SEC * (1.0 - pow(1.0 - f, 1.0 / 3.0));
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 mx = normalize(MODEL_MATRIX[0].xyz);
	vec3 fwd = normalize(-MODEL_MATRIX[2].xyz);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	vec3 away = vec3(-cam_fwd.x, 0.0, -cam_fwd.z);
	away = length(away) < 0.02 ? vec3(0.0, 0.0, -1.0) : normalize(away);
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	float birth = INSTANCE_CUSTOM.x;
	float R = max(INSTANCE_CUSTOM.y, 0.2);
	float dur = max(INSTANCE_CUSTOM.z, 0.5);
	int kind = int(INSTANCE_CUSTOM.w + 0.5);
	bool elite = kind == 5;
	if (elite) kind = 2;
	float bk = elite ? clamp(R / 1.5, 0.35, 1.0) : 1.0;
	float field = INSTANCE_CUSTOM.z < 1.5 ? 1.0 : 0.0;
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
	vec3 gate_dark = elite ? vec3(0.04, 0.01, 0.07) : vec3(0.06, 0.008, 0.05);
	vec3 gate_lit = elite ? vec3(0.22, 0.12, 0.32) : vec3(0.30, 0.13, 0.17);
	// The boss arrival's crimson bodies; the elite's violet.
	vec3 gate_body = elite ? vec3(0.36, 0.08, 0.62) : vec3(0.55, 0.04, 0.12);
	vec3 frost = mix(vec3(0.50, 0.68, 0.86), vec3(0.22, 0.44, 0.74), vfx_wash);
	// The meteor's line (vfx_skill.gdshader keeps the same numbers).
	vec3 sky = origin + up * 8.4 + away * 2.8 + mx * 1.5;
	vec3 target = origin + up * 0.12;
	vec3 fall_dir = normalize(target - sky);
	vec3 fall_side = normalize(cross(fall_dir, cam_fwd));
	float since = age - RISE;
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
		} else if (kind == 2) {
			float f = clamp(age / 2.2, 0.0, 1.0);
			s = R * 2.0;
			a = 0.9 * pow(1.0 - f, 0.9);
			col = vec3(0.04, 0.02, 0.03);
		}
		vec2 rr = rot2(c, seed * 6.283);
		world = origin + up * 0.07 + (mx * rr.x + fwd * rr.y) * 2.0 * s;
		alpha = a;
		v_cell = 18.0;
		if (a <= 0.0) world = origin;
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
				a = mix(0.62, 0.82, vfx_wash) * pow(fade, 1.1);
				col = mix(vec3(0.30, 0.13, 0.03), vec3(0.80, 0.43, 0.07), vfx_wash);
			}
			rmax = R + 0.7;
		} else if (kind == 1) {
			float throb = 0.75 + 0.25 * sin(age * (3.0 + 6.0 * prog));
			r = R * (0.9 + 0.1 * sin(age * 2.0));
			w = 0.55;
			a = (0.15 + 0.3 * prog) * throb * live;
			col = gate_dark;
			rmax = R * 2.1;
		} else if (kind == 2) {
			float f = clamp(age / 0.55, 0.0, 1.0);
			r = mix(0.2, R * 2.8, ease_out3(f));
			w = mix(0.75, 0.45, f) * 1.4 * bk;
			a = mix(0.6, 0.76, vfx_wash) * pow(1.0 - clamp((age - 0.2) / 0.6, 0.0, 1.0), 1.1);
			fill = 0.35 * pow(1.0 - clamp(age / 0.5, 0.0, 1.0), 1.2);
			col = mix(elite ? vec3(0.12, 0.08, 0.18) : vec3(0.16, 0.10, 0.12), gate_body * 0.92, vfx_wash);
			rmax = R * 3.0 + 0.8 * bk;
		} else if (kind == 3) {
			// The frost band under the wavefront: pale on dark soil, deep blue on snow.
			float f = clamp(age / FREEZE_SEC, 0.0, 1.0);
			r = freeze_wave(age, R);
			w = mix(1.3, 0.9, f);
			a = 0.5 * pow(1.0 - f, 0.9) + 0.08 * (1.0 - clamp((age - FREEZE_SEC) / 0.5, 0.0, 1.0));
			col = frost;
			rmax = R + 1.5;
		}
		world = origin + up * 0.075 + mx * c.x * 2.0 * rmax + fwd * c.y * 2.0 * rmax;
		v_ring = vec4(r / rmax, w / rmax, fill, 0.0);
		alpha = a;
		v_cell = -1.0;
		if (a <= 0.0) world = origin;
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
		} else if (kind == 2) {
			float t = age - h1 * 0.05;
			float life = 1.7 + 0.4 * h2;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				s = mix(0.8, 3.4, ease_out3(f)) * bk;
				at = origin + radial * (0.3 * bk + 2.2 * R * ease_out(f)) + up * (0.4 + 1.6 * f) * bk;
				rot += f * (h2 - 0.5) * 1.5;
				col = mix(gate_lit, vec3(0.20, 0.17, 0.17), smoothstep(0.0, 0.5, f));
				a = 0.6 * pow(1.0 - f, 1.2) * smoothstep(0.0, 0.05, f);
			}
		} else if (kind == 3) {
			// Frost mist riding the wavefront outward, left behind as it thins.
			float t = age - h1 * 0.06;
			float life = 1.4 + 0.3 * h2;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				float rad = min(freeze_wave(t, R) * 0.9, R * 0.95);
				s = mix(0.9, 2.6, ease_out3(f)) * (0.85 + 0.3 * h2);
				at = origin + radial * rad + up * (0.25 + 0.4 * f);
				rot += f * (h2 - 0.5) * 1.5;
				col = frost;
				a = 0.42 * pow(1.0 - f, 1.2) * smoothstep(0.0, 0.05, f);
			}
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.12;
		if (a <= 0.0) world = origin;
		alpha = a;
		v_cell = 4.0;
	} else if (part == 25) {
		// Body of the ground sigil: the lock-on star of the blast, the rune circle of the
		// boss gate. Same size, turn and envelope as the additive one that rides on it
		// (vfx_skill.gdshader part 1).
		float s = R;
		float a = 0.0;
		float rot = 0.0;
		v_cell = 24.0;
		if (kind == 0) {
			float lock = clamp(age / HIT, 0.0, 1.0);
			s = R * mix(1.35, 1.0, ease_out3(lock)) * 1.05;
			rot = seed * 6.283 + age * 0.9;
			float t = age - HIT;
			a = t < 0.0 ? 0.9 * smoothstep(0.0, 0.05, age) : pow(1.0 - clamp(t / 0.60, 0.0, 1.0), 1.3);
			col = vec3(0.80, 0.43, 0.07);
			v_cell = 16.0;
		} else if (kind == 1) {
			float grow = ease_out3(clamp(age / 1.0, 0.0, 1.0));
			s = R * mix(0.4, 1.05, grow);
			rot = -age * (0.35 + 2.5 * pow(prog, 6.0));
			a = (0.45 + 0.55 * pow(prog, 1.3)) * grow * live;
			col = vec3(0.55, 0.04, 0.12);
		} else if (kind == 2) {
			float f = clamp(age / 0.6, 0.0, 1.0);
			s = R * mix(1.05, 1.7, ease_out3(f));
			rot = seed * 6.283 + age * 1.5;
			a = pow(1.0 - f, 1.4);
			col = gate_body;
		}
		vec2 rr = rot2(c, rot);
		world = origin + up * 0.095 + (mx * rr.x + fwd * rr.y) * 2.0 * s * 1.02;
		alpha = a * 0.85 * vfx_wash;
		if (alpha <= 0.0) world = origin;
	} else if (part == 26) {
		// Colour of the struck ground: gold inside the blast's radius, crimson where the
		// boss arrives, deep blue inside the frost wave, gold on the altar at a level-up
		// (the additive afterglow, part 9 there, is the light on it).
		float s = R;
		float a = 0.0;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				s = R * 1.15;
				a = 0.45 * pow(1.0 - clamp(t / 1.0, 0.0, 1.0), 1.3) * smoothstep(0.0, 0.05, t);
				col = vec3(0.85, 0.50, 0.10);
			}
		} else if (kind == 2) {
			s = R * 1.9;
			a = 0.40 * pow(1.0 - clamp(age / 1.2, 0.0, 1.0), 1.3);
			col = gate_body * 0.92;
		} else if (kind == 6) {
			float t = field > 0.5 ? age - ARRIVE : -1.0;
			if (t >= 0.0) {
				s = R * 1.6;
				a = 0.42 * pow(1.0 - clamp(t / 0.9, 0.0, 1.0), 1.3) * smoothstep(0.0, 0.05, t);
				col = vec3(0.85, 0.50, 0.10);
			}
		} else if (kind == 3) {
			s = freeze_wave(age, R) * 0.95;
			a = 0.35 * pow(1.0 - clamp(age / 1.4, 0.0, 1.0), 1.2);
			col = vec3(0.18, 0.40, 0.75);
		} else if (kind == 4) {
			if (since >= 0.0) {
				s = R * 1.4;
				a = 0.4 * pow(1.0 - clamp(since / 0.8, 0.0, 1.0), 1.3);
				col = vec3(0.85, 0.50, 0.10);
			}
		}
		world = origin + up * 0.072 + (mx * c.x + fwd * c.y) * 2.0 * s;
		alpha = a * vfx_wash;
		if (alpha <= 0.0) world = origin;
		v_cell = 26.0;
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
		if (kind == 0 && idx < 8) {
			// Dark clods thrown up with the star fragments: the impact has weight.
			t = age - HIT;
			life = 0.8 + 0.3 * h3;
			float ang = (float(idx) + h1 * 0.9) / 8.0 * 6.283;
			vel = (mx * sin(ang) + fwd * cos(ang)) * (1.5 + 2.8 * h2) + up * (4.0 + 4.5 * h1);
			g = 12.0;
			s = 0.08 + 0.09 * h2;
			col = soot;
			show = true;
		} else if (kind == 2) {
			life = 1.1 + 0.4 * h3;
			float ang = (float(idx) + h1 * 0.9) / 10.0 * 6.283;
			vel = ((mx * sin(ang) + fwd * cos(ang)) * (2.0 + 4.0 * h2) + up * (4.5 + 5.0 * h1)) * bk;
			g = 10.0 * bk;
			s = (0.14 + 0.14 * h2) * mix(1.0, bk, 0.6);
			col = elite ? vec3(0.05, 0.035, 0.07) : vec3(0.05, 0.035, 0.04);
			show = true;
		}
		// Gold bodies under the arrival's five big stars (vfx_skill part 7, the same placement):
		// additive white-gold alone washes out over a bright floor.
		bool star5 = false;
		float push = 0.2;
		if (kind == 6 && idx < 5) {
			float t5 = field > 0.5 ? age - ARRIVE : age - RISE;
			float life5 = field > 0.5 ? 1.05 : 1.55;
			if (t5 >= 0.0 && t5 < life5) {
				float f5 = t5 / life5;
				float ang = (float(idx) - 2.0) * 0.52;
				vec3 out_dir = cam_right * sin(ang) + cam_up * cos(ang);
				float reach = field > 0.5 ? 1.35 + 0.25 * ease_out3(f5) : 1.25;
				vec3 from = field > 0.5 ? origin + up * 0.5 : origin + up * 2.8;
				vec3 lift = field > 0.5 ? up * (0.9 + 0.5 * ease_out(f5)) : vec3(0.0);
				at = from + lift + out_dir * reach * ease_out3(clamp(t5 / 0.22, 0.0, 1.0));
				float big = 0.92;
				if (field < 0.5) {
					// Bench: the ring round the aegis dome's foot (vfx_skill part 7, same path).
					float ca = float(idx) * 1.2566 + t5 * 1.7 + seed * 6.283;
					vec3 ring = (mx * cos(ca) + fwd * sin(ca)) * 1.5 + up * (0.75 + 0.10 * sin(t5 * 4.0 + float(idx) * 1.7));
					at = mix(from, origin + ring, ease_out3(clamp(t5 / 0.30, 0.0, 1.0)));
					big = 1.0;
				}
				float pulse = 1.0 + 0.25 * overshoot(clamp(t5 / 0.25, 0.0, 1.0)) - 0.25;
				s = big * pulse * (1.0 - smoothstep(0.75, 1.0, f5)) * 1.08;
				rot = seed * 2.0 + float(idx) * 1.3 + t5 * 2.0;
				a = 0.9 * (0.35 + 0.65 * vfx_wash) * (1.0 - smoothstep(0.80, 1.0, f5));
				col = vec3(0.85, 0.50, 0.10);
				star5 = true;
				push = 0.48;
			}
		}
		if (!star5 && show && t >= 0.0 && t < life) {
			at = origin + up * 0.2 + vel * t + up * (-0.5 * g * t * t);
			rot += t * (4.0 + 6.0 * h2) * (h3 < 0.5 ? -1.0 : 1.0);
			a = (at.y > 0.0 ? 1.0 : 0.0) * 0.95 * (1.0 - smoothstep(0.7, 1.0, t / life));
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * push;
		if (a <= 0.0) world = origin;
		alpha = a;
		v_cell = star5 ? 1.0 : 22.0;
	} else if (part == 24) {
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
			at = origin + (mx * cos(turn) + fwd * sin(turn)) * (0.4 * bk + 3.0 * R * ease_out3(f)) + up * (0.3 + 0.5 * f) * bk;
			s = (0.8 + 1.2 * f) * bk;
			rot += f * (h1 - 0.5) * 3.0;
			col = elite ? vec3(0.10, 0.04, 0.16) : vec3(0.12, 0.03, 0.10);
			a = 0.55 * pow(1.0 - f, 1.2);
		} else if (kind == 3) {
			// Low fog left across the field behind the wave.
			float rad = R * (0.15 + 0.8 * h3);
			float turn = h2 * 6.283;
			float t = age - freeze_arrival(rad, R);
			float life = 1.5 + 0.5 * h1;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				at = origin + (mx * cos(turn) + fwd * sin(turn)) * rad + up * (0.12 + 0.2 * f);
				s = (1.2 + 1.0 * h1) * (0.6 + 0.4 * ease_out(f));
				rot += f * (h1 - 0.5) * 1.5;
				col = frost;
				a = 0.30 * pow(sin(f * 3.14159), 0.8);
			}
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.1;
		if (a <= 0.0) world = origin;
		alpha = a;
		v_cell = 23.0;
	} else {
		// Trail smoke x5: dropped along the meteor's line as the head passes, each puff
		// swelling and drifting off the line while it fades.
		float h1 = hash11(seed * 3.3 + float(idx) * 1.7);
		float h2 = hash11(seed * 5.9 + float(idx) * 0.9);
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin;
		if (kind == 0) {
			float born = (float(idx) + 0.6) / 5.0 * HIT;
			float t = age - born;
			float life = 0.7 + 0.3 * h2;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				float bf = born / HIT;
				at = mix(sky, target, bf * bf) + fall_side * (h1 - 0.5) * 0.5 * (1.0 + f) - fall_dir * 0.5 * f + up * 0.25 * f;
				s = mix(0.8, 2.6, ease_out3(f)) * (0.85 + 0.3 * h1);
				col = mix(vec3(0.45, 0.20, 0.06), vec3(0.10, 0.08, 0.075), smoothstep(0.0, 0.35, f));
				a = 0.85 * pow(1.0 - f, 1.2) * smoothstep(0.0, 0.05, f);
			}
		}
		vec2 rr = rot2(c, h1 * 6.283 + age * (h2 - 0.5));
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.15;
		if (a <= 0.0) world = origin;
		alpha = a;
		v_cell = 39.0;
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
	} else if (v_cell > 31.5) {
		a = texture(zone_sprites, cell_uv(int(v_cell + 0.5) - 32, UV)).a;
	} else if (v_cell > 15.5) {
		a = texture(skill_sprites, cell_uv(int(v_cell + 0.5) - 16, UV)).a;
	} else {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	}
	ALBEDO = v_tint.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * v_tint.a;
}
