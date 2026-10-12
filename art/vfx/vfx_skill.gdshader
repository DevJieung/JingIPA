shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Additive layer of the big one-shot sequences: the Starlight Burst guardian skill and the
// boss gate (four-second warning gather, arrival burst). One MultiMesh instance plays a whole
// sequence; every part reads its own window of the instance's age, so the anticipation,
// impact, shockwave, fragments and afterglow are one draw call and one budget slot.
//   transform: origin on the ground, -Z = a deterministic yaw (variety only)
//   COLOR:     main colour (gold for the blast, crimson for the boss gate)
//   CUSTOM:    x birth (vfx seconds, epoch relative)  y radius R (world units; the blast's
//              actual damage radius, the boss footprint otherwise)
//              z duration (boss warning seconds; unused otherwise)  w kind
// Kinds: 0 blast  1 boss_warning  2 boss_burst
// Parts (UV2.x): 0 ground shock ring  1 ground sigil  2 flash  3 flare  4 light pillar
//   5 comet tail (strip)  6 comet head  7 sparks x16  8 embers x12  9 ground afterglow
//   10 sky flare  11 lightning x4  12 facing portal ring  13 crack glow
// Blast timeline (seconds): 0 sky flare + lock-on sigil, the star falls 0..HIT, HIT impact
// flash / flare / pillar, shock ring reaches R at HIT+0.30 and lingers to HIT+0.80,
// fragments to HIT+1.0, embers / afterglow / crack glow to ~1.5. The simulator's damage is
// at 0; the lock-on at 0 marks the struck area while the star is still in the air.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue (the mix layer carries the body).
uniform float vfx_wash = 0.0;
uniform float vfx_epoch = 0.0;

const float HIT = 0.18;

varying vec4 v_tint;
varying vec3 v_wake;     // ring: colour of the wake / fill (the lead edge uses v_tint)
varying float v_cell;    // -1 procedural ring, 0..15 battle atlas, 16..31 skill atlas
varying vec2 v_plane;
varying vec4 v_ring;     // r, width (fractions of the quad), fill, unused

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
	vec3 pillar_side = normalize(cross(up, cam_fwd));
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	float birth = INSTANCE_CUSTOM.x;
	float R = max(INSTANCE_CUSTOM.y, 0.2);
	float dur = max(INSTANCE_CUSTOM.z, 0.5);
	int kind = int(INSTANCE_CUSTOM.w + 0.5);
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float seed = hash11(birth * 5.17 + float(INSTANCE_ID) * 0.311);
	float prog = clamp(age / dur, 0.0, 1.0);
	float live = age < dur ? 1.0 : 0.0;         // warning parts stop at the arrival
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = COLOR.rgb;
	float alpha = 0.0;
	float cell = 0.0;
	v_plane = c * 2.0;
	v_ring = vec4(0.0);
	v_wake = COLOR.rgb;
	// Palettes.
	vec3 gold = COLOR.rgb;
	vec3 hot = mix(gold, vec3(1.0, 0.98, 0.92), 0.8);
	vec3 deep = gold * vec3(1.0, 0.62, 0.30);
	vec3 red = vec3(1.0, 0.16, 0.26);
	vec3 violet = vec3(0.58, 0.28, 1.0);
	vec3 boss_hot = vec3(1.0, 0.80, 0.90);
	// The falling star's start point: high above and up the screen, a little to one side.
	vec3 sky = origin + up * 5.2 + away * 1.0 + mx * 1.4;
	if (part == 0) {
		float r = 0.0;
		float w = 0.0;
		float fill = 0.0;
		float a = 0.0;
		float rmax = 1.0;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.30, 0.0, 1.0);
				r = mix(0.15, R, ease_out3(f));
				w = mix(0.48, 0.26, f);
				float fade = 1.0 - clamp((t - 0.30) / 0.50, 0.0, 1.0);
				a = (0.6 + 0.4 * (1.0 - f)) * pow(fade, 1.2);
				fill = 0.45 * pow(1.0 - clamp(t / 0.28, 0.0, 1.0), 1.5);
				col = mix(vec3(1.0), hot, 0.4 + f * 0.6);
				v_wake = mix(hot, gold, 0.5 + 0.5 * f);
			}
			rmax = R + 0.7;
		} else if (kind == 1) {
			// Rings converging into the gate: energy being pulled in, faster near the end.
			float cycle = 0.85;
			float k = floor(age / cycle);
			float f = fract(age / cycle);
			r = mix(R * 1.9, R * 0.12, ease_out(f));
			w = 0.2;
			a = (0.5 + 0.5 * prog) * pow(1.0 - f, 0.6) * smoothstep(0.0, 0.1, f) * live;
			col = mix(red, violet, 0.5 + 0.5 * sin(k * 2.1));
			v_wake = col;
			rmax = R * 2.1;
		} else {
			float f = clamp(age / 0.55, 0.0, 1.0);
			r = mix(0.2, R * 2.8, ease_out3(f));
			w = mix(0.75, 0.35, f);
			a = pow(1.0 - f, 1.1);
			fill = 0.45 * pow(1.0 - clamp(age / 0.3, 0.0, 1.0), 1.4);
			col = mix(boss_hot, violet, 0.2);
			v_wake = mix(red, violet, 0.5);
			rmax = R * 3.0 + 0.8;
		}
		world = origin + up * 0.09 + mx * c.x * 2.0 * rmax + fwd * c.y * 2.0 * rmax;
		v_ring = vec4(r / rmax, w / rmax, fill, 0.0);
		alpha = a;
		cell = -1.0;
	} else if (part == 1) {
		float s = R;
		float a = 0.0;
		float rot = 0.0;
		if (kind == 0) {
			// Lock-on: the sigil snaps from 1.35R to the damage radius while the star falls.
			float lock = clamp(age / HIT, 0.0, 1.0);
			s = R * mix(1.35, 1.0, ease_out3(lock)) * 1.05;
			rot = seed * 6.283 + age * 0.9;
			float t = age - HIT;
			if (t < 0.0) {
				a = 0.9 * smoothstep(0.0, 0.05, age);
				col = mix(gold, hot, 0.3);
			} else {
				a = pow(1.0 - clamp(t / 0.60, 0.0, 1.0), 1.3);
				col = mix(hot, gold, clamp(t / 0.25, 0.0, 1.0));
			}
			cell = 16.0;
		} else if (kind == 1) {
			float grow = ease_out3(clamp(age / 1.0, 0.0, 1.0));
			s = R * mix(0.4, 1.05, grow);
			rot = -age * (0.35 + 2.5 * pow(prog, 6.0));
			float throb = 0.8 + 0.2 * sin(age * (5.0 + 8.0 * prog));
			a = (0.45 + 0.55 * pow(prog, 1.3)) * throb * grow * live;
			col = mix(red, violet, 0.45 + 0.3 * sin(age * 1.7));
			cell = 24.0;
		} else {
			float f = clamp(age / 0.6, 0.0, 1.0);
			s = R * mix(1.05, 1.7, ease_out3(f));
			rot = seed * 6.283 + age * 1.5;
			a = pow(1.0 - f, 1.4);
			col = mix(boss_hot, violet, f);
			cell = 24.0;
		}
		vec2 rr = rot2(c, rot);
		world = origin + up * 0.10 + (mx * rr.x + fwd * rr.y) * 2.0 * s;
		alpha = a;
	} else if (part == 2) {
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin + up * 0.6;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.13, 0.0, 1.0);
				s = 1.9 + 1.3 * ease_out(f);
				a = pow(1.0 - f, 1.6);
				col = hot;
			}
		} else if (kind == 2) {
			float f = clamp(age / 0.22, 0.0, 1.0);
			s = 3.0 + 2.5 * ease_out(f);
			a = pow(1.0 - f, 1.3);
			col = mix(boss_hot, violet, 0.3);
			at = origin + up * 1.3;
		} else {
			// A dim strobe at the gate's heart during the last second.
			float late = clamp((age - (dur - 1.0)) / 1.0, 0.0, 1.0);
			float fl = step(0.6, hash11(floor(age * 24.0) + seed * 7.0));
			s = 0.9 + 1.5 * late;
			a = 0.35 * late * fl * live;
			col = mix(red, violet, 0.5);
		}
		vec2 rr = rot2(c, seed * 6.283);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.4;
		alpha = a * (s > 0.001 ? 1.0 : 0.0);
		cell = 0.0;
	} else if (part == 3) {
		float a = 0.0;
		float s = 0.0;
		float rot = seed * 6.283;
		vec3 at = origin + up * 0.55;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.42, 0.0, 1.0);
				s = 1.0 + 4.4 * ease_out3(f);
				rot += f * 0.5;
				a = pow(1.0 - f, 1.6);
				col = mix(hot, gold, 0.35 + 0.5 * f);
			}
		} else if (kind == 2) {
			float f = clamp(age / 0.5, 0.0, 1.0);
			s = 1.5 + 6.0 * ease_out3(f);
			rot -= f * 0.6;
			a = pow(1.0 - f, 1.5);
			col = mix(boss_hot, violet, 0.25 + f * 0.65);
			at = origin + up * 1.3;
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.38;
		alpha = a * (s > 0.001 ? 1.0 : 0.0);
		cell = 21.0;
	} else if (part == 4) {
		float a = 0.0;
		float h = 0.0;
		float w = 0.0;
		float push = 0.35;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.5, 0.0, 1.0);
				h = 5.0 * ease_out3(clamp(t / 0.10, 0.0, 1.0)) * (1.0 - 0.15 * f);
				w = mix(1.0, 0.4, ease_out(f));
				a = pow(1.0 - f, 1.3);
				col = mix(hot, gold, 0.3 + 0.5 * f);
			}
		} else if (kind == 2) {
			float f = clamp(age / 0.7, 0.0, 1.0);
			h = 7.5 * ease_out3(clamp(age / 0.12, 0.0, 1.0));
			w = mix(2.0, 0.7, ease_out(f));
			a = pow(1.0 - f, 1.2);
			col = mix(boss_hot, mix(red, violet, 0.6), f * 0.8);
			push = R;
		} else {
			// A thin, flickering beacon climbing out of the gate over the warning.
			float flick = 0.7 + 0.3 * sin(age * 23.0 + seed * 9.0) * sin(age * 7.3);
			h = 6.5 * ease_out(prog);
			w = 0.35 + 0.35 * prog;
			a = (0.15 + 0.45 * prog) * flick * live;
			col = mix(violet, red, 0.3);
			push = R;
		}
		world = origin + up * (c.y + 0.5) * h + pillar_side * c.x * w - cam_fwd * push;
		alpha = a * (h > 0.001 ? 1.0 : 0.0);
		cell = 17.0;
	} else if (part == 5) {
		float a = 0.0;
		if (kind == 0) {
			float t = clamp(age / HIT, 0.0, 1.0);
			float s = t * t;
			vec3 target = origin + up * 0.12;
			vec3 head = mix(sky, target, s);
			vec3 dir = normalize(target - sky);
			vec3 side = normalize(cross(dir, cam_fwd));
			float along = VERTEX.y;
			float len = 2.2 + 3.0 * s;
			float w = (0.32 + 0.18 * s) * (1.0 - along * 0.8);
			world = head - dir * along * len + side * c.x * w;
			float post = clamp((age - HIT) / 0.08, 0.0, 1.0);
			a = (0.5 + 0.5 * s) * (1.0 - post) * smoothstep(0.0, 0.03, age);
			col = mix(hot, gold, along);
		}
		alpha = a;
		cell = 20.0;
	} else if (part == 6) {
		float a = 0.0;
		if (kind == 0) {
			float t = clamp(age / HIT, 0.0, 1.0);
			float s = t * t;
			vec3 head = mix(sky, origin + up * 0.12, s);
			float size = 0.9 + 0.5 * s;
			vec2 rr = rot2(c, seed * 6.283 + age * 14.0);
			world = head + (cam_right * rr.x + cam_up * rr.y) * size - cam_fwd * 0.3;
			float post = clamp((age - HIT) / 0.06, 0.0, 1.0);
			a = (1.0 - post) * smoothstep(0.0, 0.03, age);
			col = mix(vec3(1.0), hot, 0.4);
		}
		alpha = a;
		cell = 1.0;
	} else if (part == 7) {
		float h1 = hash11(seed * 13.0 + float(idx));
		float h2 = hash11(seed * 29.0 + float(idx) * 1.7);
		float h3 = hash11(seed * 41.0 + float(idx) * 0.37);
		float a = 0.0;
		if (kind == 0) {
			// Star fragments: a fountain that arcs out and falls, twinkling, white to deep gold.
			float t = age - HIT;
			float life = 0.55 + 0.45 * h3;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				float ang = (float(idx) + h1 * 0.9) / 16.0 * 6.283;
				vec3 radial = mx * sin(ang) + fwd * cos(ang);
				vec3 vel = radial * (1.6 + 2.8 * h2) + up * (5.0 + 4.5 * h1);
				float g = 11.0;
				vec3 at = origin + up * 0.5 + vel * t + up * (-0.5 * g * t * t);
				vec3 now = vel + up * (-g * t);
				vec3 along = normalize(now + vec3(0.0, 0.0001, 0.0));
				vec3 side = cross(along, cam_fwd);
				side = length(side) < 0.02 ? cam_right : normalize(side);
				float len = (0.6 + 0.4 * h2) * clamp(length(now) * 0.14, 0.6, 1.8);
				float wid = 0.28 + 0.12 * h1;
				world = at + along * c.y * len + side * c.x * wid - cam_fwd * 0.3;
				float twinkle = 0.8 + 0.2 * sin(vfx_time * 42.0 + h1 * 25.0);
				a = pow(1.0 - f, 0.7) * twinkle;
				col = mix(mix(vec3(1.0), hot, 0.3), deep, clamp(f * 1.1 - 0.2, 0.0, 1.0));
				cell = (idx % 3 == 0) ? 1.0 : 27.0;
			}
		} else if (kind == 1) {
			// Wisps spiralling up into the gate, faster and brighter toward the arrival.
			float cycle = 1.4 + 0.5 * h3;
			float ph = fract(age / cycle + h1);
			float ang = h2 * 6.283 + age * (1.2 + 2.0 * prog) + float(idx) * 0.4;
			float rad = R * (1.1 - 0.75 * ph) * (0.8 + 0.3 * h1);
			vec3 at = origin + (mx * cos(ang) + fwd * sin(ang)) * rad + up * (0.1 + ph * (1.2 + 1.5 * prog));
			float s = 0.14 + 0.12 * h2;
			vec2 rr = rot2(c, ang);
			world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
			a = pow(sin(ph * 3.14159), 0.9) * (0.25 + 0.75 * prog) * live;
			col = mix(red, violet, h2);
			cell = 2.0;
		} else {
			float life = 0.7 + 0.5 * h3;
			if (age < life) {
				float f = age / life;
				float ang = (float(idx) + h1 * 0.9) / 16.0 * 6.283;
				vec3 radial = mx * sin(ang) + fwd * cos(ang);
				vec3 vel = radial * (2.5 + 3.5 * h2) + up * (3.0 + 4.0 * h1);
				float g = 7.0;
				vec3 at = origin + up * 0.8 + vel * age + up * (-0.5 * g * age * age);
				vec3 now = vel + up * (-g * age);
				vec3 along = normalize(now + vec3(0.0, 0.0001, 0.0));
				vec3 side = cross(along, cam_fwd);
				side = length(side) < 0.02 ? cam_right : normalize(side);
				float len = 0.35 + 0.3 * h2;
				world = at + along * c.y * len + side * c.x * 0.16 - cam_fwd * 0.25;
				a = (1.0 - f) * (0.75 + 0.25 * sin(vfx_time * 30.0 + h1 * 20.0));
				col = mix(boss_hot, mix(red, violet, h2), clamp(f * 1.5, 0.0, 1.0));
				cell = 27.0;
			}
		}
		if (a <= 0.0) world = origin;
		alpha = a;
	} else if (part == 8) {
		float h1 = hash11(seed * 3.7 + float(idx));
		float h2 = hash11(seed * 5.3 + float(idx) * 2.3);
		float h3 = hash11(seed * 9.1 + float(idx) * 0.7);
		float a = 0.0;
		float s = 0.0;
		if (kind == 0) {
			float t = age - HIT - 0.08 - h3 * 0.3;
			float life = 0.9 + 0.5 * h2;
			if (t >= 0.0 && t < life) {
				float g = t / life;
				vec3 spread = (mx * (h1 - 0.5) + fwd * (h2 - 0.5)) * 2.0 * R * 0.7;
				vec3 at = origin + spread + up * (0.2 + (1.0 + 1.2 * h1) * ease_out(g))
					+ mx * sin(g * 6.0 + h1 * 6.0) * 0.12 + fwd * cos(g * 5.0 + h2 * 4.0) * 0.1;
				s = (0.12 + 0.12 * h2) * (1.0 - g * 0.4);
				vec2 rr = rot2(c, h1 * 6.283 + g * 3.0);
				world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
				a = pow(sin(g * 3.14159), 0.7) * (0.7 + 0.3 * sin(vfx_time * 25.0 + h1 * 30.0));
				col = mix(hot, gold, g);
				cell = 2.0;
			}
		} else if (kind == 1) {
			// Sparks orbiting the rune low over the ground, drawn inward as the gate charges.
			float ang = h1 * 6.283 - age * (0.9 + 2.4 * prog) + float(idx) * 0.5;
			float rad = R * (0.55 + 0.5 * h2) * (1.0 - 0.3 * prog);
			vec3 at = origin + (mx * cos(ang) + fwd * sin(ang)) * rad
				+ up * (0.12 + 0.35 * h3 + 0.15 * sin(age * 3.0 + h1 * 9.0));
			s = 0.08 + 0.1 * prog;
			vec2 rr = rot2(c, ang * 2.0);
			world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
			a = (0.3 + 0.7 * prog) * (0.6 + 0.4 * sin(vfx_time * 20.0 + h2 * 20.0)) * live;
			col = mix(red, violet, h1);
			cell = 2.0;
		} else {
			float t = age - 0.05 - h3 * 0.25;
			float life = 1.0 + 0.5 * h2;
			if (t >= 0.0 && t < life) {
				float g = t / life;
				vec3 spread = (mx * (h1 - 0.5) + fwd * (h2 - 0.5)) * 2.0 * R * 1.3;
				vec3 at = origin + spread + up * (0.3 + (1.5 + 1.5 * h1) * ease_out(g));
				s = (0.12 + 0.12 * h2) * (1.0 - g * 0.4);
				vec2 rr = rot2(c, h1 * 6.283 + g * 3.0);
				world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
				a = pow(sin(g * 3.14159), 0.7);
				col = mix(boss_hot, mix(red, violet, h1), g);
				cell = 2.0;
			}
		}
		if (a <= 0.0) world = origin;
		alpha = a;
	} else if (part == 9) {
		float a = 0.0;
		float s = R;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 1.15, 0.0, 1.0);
				s = R * (1.1 + 0.2 * ease_out(f));
				a = 0.65 * pow(1.0 - f, 1.5);
				col = mix(hot, deep, clamp(f * 2.2, 0.0, 1.0));
			}
		} else if (kind == 1) {
			float throb = 0.75 + 0.25 * sin(age * (4.0 + 10.0 * prog));
			s = R * (0.6 + 0.6 * prog);
			a = (0.08 + 0.5 * pow(prog, 1.5)) * throb * live;
			col = mix(red, violet, 0.35) * 0.9;
		} else {
			float f = clamp(age / 1.2, 0.0, 1.0);
			s = R * (1.6 + 0.6 * ease_out(f));
			a = 0.8 * pow(1.0 - f, 1.5);
			col = mix(boss_hot, violet, clamp(f * 1.5, 0.0, 1.0));
		}
		world = origin + up * 0.08 + (mx * c.x + fwd * c.y) * 2.0 * s;
		alpha = a;
		cell = 26.0;
	} else if (part == 10) {
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin;
		if (kind == 0) {
			// The cast moment: a flare in the sky where the star is born.
			float f = clamp(age / 0.24, 0.0, 1.0);
			at = sky;
			s = 1.6 + 2.2 * ease_out(f);
			a = pow(1.0 - f, 1.2);
			col = mix(vec3(1.0), hot, 0.5);
		}
		vec2 rr = rot2(c, seed * 2.0);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s;
		alpha = a * (s > 0.001 ? 1.0 : 0.0);
		cell = 0.0;
	} else if (part == 11) {
		float h1 = hash11(seed * 17.0 + float(idx));
		float h2 = hash11(seed * 23.0 + float(idx) * 1.3);
		float a = 0.0;
		float window = 0.0;
		float strength = 0.0;
		if (kind == 1) {
			float late = clamp((age - (dur - 1.3)) / 1.3, 0.0, 1.0);
			window = late * live;
			strength = 0.5 + 0.5 * late;
		} else if (kind == 2) {
			window = age < 0.55 ? 1.0 : 0.0;
			strength = 1.0 - clamp(age / 0.55, 0.0, 1.0);
		}
		if (window > 0.0) {
			float slot = floor(vfx_time * 18.0 + h1 * 10.0);
			float on = step(1.0 - 0.35 * window, hash11(slot * 0.731 + float(idx) * 3.1 + seed));
			float ang = h2 * 6.283 + slot * 1.7;
			float rad = R * (0.5 + 0.7 * hash11(slot + h2));
			vec3 at = origin + (mx * cos(ang) + fwd * sin(ang)) * rad;
			float hgt = 1.2 + 1.2 * hash11(slot * 1.3 + h1);
			float wid = 0.5 + 0.3 * h1;
			world = at + up * (c.y + 0.5) * hgt + pillar_side * c.x * wid - cam_fwd * 0.2;
			a = on * strength;
			col = mix(violet, vec3(1.0), 0.45);
			cell = 7.0;
		}
		if (a <= 0.0) world = origin;
		alpha = a;
	} else if (part == 12) {
		float a = 0.0;
		float s = 0.0;
		float rot = seed * 6.283;
		if (kind == 2) {
			// The portal mouth snaps open and shatters outward.
			float f = clamp(age / 0.6, 0.0, 1.0);
			s = 1.0 + (R * 3.2) * ease_out3(clamp(age / 0.28, 0.0, 1.0));
			rot += age * 2.0;
			a = pow(1.0 - f, 1.2) * smoothstep(0.0, 0.03, age);
			col = mix(boss_hot, mix(red, violet, 0.5), clamp(f * 1.5, 0.0, 1.0));
		} else if (kind == 1) {
			// It forms during the last 0.7 s of the warning so the burst continues it.
			float late = clamp((age - (dur - 0.7)) / 0.7, 0.0, 1.0);
			s = R * 1.2 * ease_out(late);
			rot -= age * 3.0;
			a = (0.3 + 0.7 * late) * late * live;
			col = mix(red, violet, 0.6);
		}
		vec2 rr = rot2(c, rot);
		world = origin + up * (R * 1.3) + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * R;
		alpha = a * (s > 0.001 ? 1.0 : 0.0);
		cell = 25.0;
	} else {
		float a = 0.0;
		float s = R;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.9, 0.0, 1.0);
				s = R * 1.45;
				a = 0.9 * pow(1.0 - f, 1.4);
				col = mix(hot, deep, clamp(f * 1.3, 0.0, 1.0));
			}
		} else if (kind == 1) {
			float grow = ease_out(clamp(age / (dur * 0.6), 0.0, 1.0));
			s = R * (0.5 + 1.0 * grow);
			float throb = 0.7 + 0.3 * sin(age * (3.0 + 9.0 * prog) + 1.0);
			a = (0.1 + 0.9 * pow(prog, 1.2)) * throb * live;
			col = mix(red, violet, 0.2);
		} else {
			float f = clamp(age / 1.3, 0.0, 1.0);
			s = R * 2.0;
			a = pow(1.0 - f, 1.2);
			col = mix(boss_hot, red, clamp(f * 1.5, 0.0, 1.0));
		}
		vec2 rr = rot2(c, seed * 6.283);
		world = origin + up * 0.085 + (mx * rr.x + fwd * rr.y) * 2.0 * s;
		alpha = a;
		cell = 19.0;
	}
	v_tint = vec4(col, alpha);
	v_cell = cell;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	vec3 rgb = v_tint.rgb;
	if (v_cell < -0.5) {
		// Shock ring: crisp hot leading edge, softer wake and fill in the wake colour.
		float d = length(v_plane);
		float r = v_ring.x;
		float w = max(v_ring.y, 0.004);
		float lead = smoothstep(r - w * 0.35, r, d) * (1.0 - smoothstep(r, r + w * 1.4, d));
		float wake = (1.0 - smoothstep(r * 0.55, r, d)) * v_ring.z;
		a = (lead + wake) * (1.0 - smoothstep(0.9, 1.0, d));
		rgb = (lead * v_tint.rgb + wake * v_wake) / max(lead + wake, 0.001);
	} else if (v_cell < 15.5) {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	} else {
		a = texture(skill_sprites, cell_uv(int(v_cell + 0.5) - 16, UV)).a;
	}
	ALBEDO = mix(rgb, rgb * rgb * 1.25, vfx_wash * 0.5);
	ALPHA = clamp(a, 0.0, 1.0) * v_tint.a * mix(1.0, 0.72, vfx_wash);
}
