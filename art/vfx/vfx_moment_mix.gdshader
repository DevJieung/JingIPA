shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"
#include "res://art/vfx/vfx_moment.gdshaderinc"

// Body of the run-level moments (same instance contract as vfx_moment.gdshader, drawn
// before it). Additive gold on a pale road or on snow is just white, so the colour and the
// shape of every ring, crest, mark and shard are painted here, alpha-blended, in saturated
// mid-tones that read on dark soil and on bright ice alike; the additive layer only adds
// the light on top. This layer also carries what light cannot: the darkening before the
// revival's flash, the dark sun of the final boss, smoke and stones.
// Kinds: 0 revive  1 stage_clear  2 stage_sweep  3 gate_beacon  4 final_warning  5 final_burst
//        6 gate_seal  7 wave_clear (2026-10-19; a gate beacon with COLOR.a 2 is an elite wave's,
//        violet instead of coral)
// Parts (UV2.x): 20 ring body x3 (the same three rings as the additive part 0)
//   21 disc x3 (0 dark stain, 1 crest body, 2 colour wash)   22 smoke x6   23 stones x8
//   24 marks x4 (mend halos; the beacon column's body)   25 shards x16
// Colours are linear values: ACES + sRGB output lifts them, so 0.15..0.3 reads mid-tone.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
uniform float vfx_epoch = 0.0;
// 1 on bright snow/ice fields: a mid-tone body has nothing to stand against on white, so
// the coloured bodies deepen and gain weight there (dark stains are left as they are).
uniform float vfx_wash = 0.0;

varying vec4 v_tint;
varying vec3 v_ink;      // timer ring: colour of the part that has already run out
varying float v_cell;    // -1 ring band, -2 hard disc, 0..15 battle atlas, 16..31 skill atlas
varying vec2 v_plane;
varying vec4 v_ring;     // r, width (fractions of the quad), fill, unused
varying vec2 v_arc;      // timer ring: x elapsed fraction (-1 = a plain ring), y segments

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float link = max(length(MODEL_MATRIX[0].xyz), 0.001);
	vec3 mx = MODEL_MATRIX[0].xyz / link;
	vec3 fwd = normalize(-MODEL_MATRIX[2].xyz);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	float fi = float(idx);
	float birth = INSTANCE_CUSTOM.x;
	float R = max(INSTANCE_CUSTOM.y, 0.2);
	float dur = max(INSTANCE_CUSTOM.z, 0.5);
	int kind = int(INSTANCE_CUSTOM.w + 0.5);
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float seed = hash11(birth * 5.17 + float(INSTANCE_ID) * 0.311);
	float amount = COLOR.a;
	float prog = clamp(age / dur, 0.0, 1.0);
	float live = age < dur ? 1.0 : 0.0;
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	v_plane = c * 2.0;
	v_ring = vec4(0.0);
	v_arc = vec2(-1.0, 1.0);
	v_ink = vec3(0.0);
	v_cell = 0.0;
	// Body colours (linear): the gold of the blessing and of victory, its ink, the coral of
	// the gates, the cyan of the crystal.
	vec3 gold = vec3(0.80, 0.43, 0.07);
	vec3 gold_ink = vec3(0.20, 0.085, 0.015);
	vec3 coral = vec3(0.85, 0.23, 0.09);
	vec3 cyan = vec3(0.10, 0.52, 0.74);
	vec3 pale = vec3(0.74, 0.50, 0.17);
	vec3 dust = vec3(0.24, 0.27, 0.33);
	vec3 gate_dark = vec3(0.06, 0.008, 0.05);
	// A gate's body colour: coral, or violet when an elite wave opens it (COLOR.a 2).
	vec3 gate_tone = kind == 3 && amount > 1.5 ? vec3(0.36, 0.08, 0.62) : coral;
	vec3 gate_dust = kind == 3 && amount > 1.5 ? vec3(0.26, 0.13, 0.32) : vec3(0.42, 0.20, 0.12);
	// The last stage's clear and its gate seals hold a rest (see vfx_moment.gdshader).
	float fin = (kind == 1 || kind == 6) && amount >= 1.5 ? 1.0 : 0.0;
	float mend = amount - 2.0 * fin;
	float clear_out = fin > 0.5 ? 1.0 : 1.0 - smoothstep(dur - 0.42, dur - 0.10, age);
	float rest = fin * (1.0 - smoothstep(dur + 2.0, dur + 3.4, age));
	vec3 sun = dark_sun(origin, fwd, cam_fwd, R);
	// Wave clear (vfx_moment.gdshader): the sweep, and the mend.
	float wsweep = kind == 7 && amount < 1.5 ? 1.0 : 0.0;
	float wmend = kind == 7 ? (amount < 1.5 ? amount : amount - 2.0) : 0.0;
	if (part == 20) {
		float r = 0.0;
		float w = 0.1;
		float fill = 0.0;
		float a = 0.0;
		float rmax = 1.0;
		float y = 0.075;
		if (kind == 0) {
			if (idx == 0) {
				if (age < FL) {
					float f = age / FL;
					r = mix(3.6, 0.25, f * f);
					w = 0.24;
					a = 0.55 * (0.35 + 0.65 * f);
					col = gold;
					rmax = 4.0;
				} else {
					// The shockwave's golden band.
					float t = age - FL;
					float f = clamp(t / 0.50, 0.0, 1.0);
					r = revive_wave(t, R);
					w = mix(0.50, 0.28, f) * 1.7;
					a = 0.70 * (1.0 - f * f * f);
					col = gold;
					rmax = R * 1.06 + 1.0;
				}
			} else if (idx == 1) {
				// The aura's clock: gold on the part still to run, ink where it has run out.
				if (age < dur) {
					r = 2.0;
					w = 0.15;
					a = 0.92 * smoothstep(FL, FL + 0.25, age) * (1.0 - smoothstep(dur - 0.22, dur, age));
					v_arc = vec2(seg(FL, dur, age), max(floor(dur + 0.5), 1.0));
					// The last second blinks between gold and ink.
					col = mix(gold, gold_ink, 0.7 * step(dur - 1.0, age) * step(0.5, fract((dur - age) * 5.0)));
					v_ink = gold_ink;
				}
				rmax = 3.0;
				y = 0.095;
			} else {
				float t = age - FL - 0.10;
				if (t >= 0.0) {
					float f = clamp(t / 0.62, 0.0, 1.0);
					r = mix(0.3, R * 1.06, 1.0 - pow(1.0 - f, 2.2));
					w = 0.34;
					a = 0.36 * pow(1.0 - f, 0.8);
					col = mix(gold, gold_ink, 0.35);
				}
				rmax = R * 1.06 + 1.0;
			}
		} else if (kind == 1) {
			if (idx == 0) {
				float f = clamp(age / 0.60, 0.0, 1.0);
				r = clear_wave(age, R);
				w = mix(0.80, 0.45, f) * 1.7;
				a = 0.56 * (1.0 - f * f);
				col = gold;
				rmax = R * 1.04 + 1.3;
			} else if (idx == 1) {
				float f = seg(MEND_RING, MEND_RING + 0.72, age);
				r = mix(2.7, 0.85, ease_out(f));
				w = 0.19;
				a = 0.62 * mend * pow(sin(f * PI), 0.7);
				col = cyan;
				rmax = 3.0;
				y = 0.095;
			} else if (fin > 0.5) {
				// The last clear: the gold body of the wave that locks on the rim.
				float t = age - SEAL_WAVE;
				if (t >= 0.0) {
					float f = clamp(t / (SEAL_LOCK - SEAL_WAVE), 0.0, 1.0);
					r = mix(0.4, R, 1.0 - pow(1.0 - f, 2.2));
					w = mix(0.60, 0.15, f) * 1.7;
					a = mix(0.56, 0.74, step(1.0, f)) * rest;
					col = gold;
				}
				rmax = R * 1.04 + 1.3;
			} else {
				float t = age - 0.12;
				if (t >= 0.0) {
					float f = clamp(t / 0.62, 0.0, 1.0);
					r = mix(0.4, R * 1.04, 1.0 - pow(1.0 - f, 2.0));
					w = 0.36;
					a = 0.28 * pow(1.0 - f, 0.8);
					col = mix(gold, gold_ink, 0.35);
				}
				rmax = R * 1.04 + 1.3;
			}
			a *= clear_out;
		} else if (kind == 2) {
			if (idx == 0) {
				r = sweep_radius(age, R);
				w = 0.56;
				a = 0.52 * (1.0 - seg(ARR, ARR + 0.22, age));
				col = pale;
			} else if (idx == 1) {
				r = R;
				w = 0.22;
				a = age < ARR ? 0.46 : 0.62 * pow(1.0 - clamp((age - ARR) / 1.25, 0.0, 1.0), 1.5);
				col = pale;
			} else if (age < dur) {
				float t = age - 0.13;
				if (t >= 0.0) {
					r = sweep_radius(t, R);
					w = 0.28;
					a = 0.28 * (1.0 - seg(ARR, ARR + 0.20, t));
					col = mix(pale, gold_ink, 0.4);
				}
			} else {
				float f = clamp((age - dur) / 0.50, 0.0, 1.0);
				r = mix(2.1, 3.1, ease_out3(f));
				w = 0.26;
				a = 0.72 * pow(1.0 - f, 1.2);
				col = coral;
			}
			rmax = R + 1.0;
		} else if (kind == 3) {
			float t = age - ARR;
			col = gate_tone;
			if (idx == 0) {
				if (t < 0.0) {
					// Nothing at age 0: under the card the HUD's own ring marks the gate.
					r = mix(0.6, 1.25, ease_out3(age / 0.22));
					w = 0.19;
					a = 0.80 * smoothstep(0.0, 0.14, age);
				} else {
					float f = clamp(t / 0.45, 0.0, 1.0);
					r = mix(0.3, 2.8, ease_out3(f));
					w = mix(0.40, 0.16, f) * 1.6;
					a = 0.70 * pow(1.0 - f, 1.0);
				}
			} else if (idx == 1) {
				if (t >= 0.0) {
					r = 1.25;
					w = 0.18;
					a = 0.74 * (1.0 - smoothstep(1.1, 1.9, t));
				}
			} else {
				float t2 = t - 0.09;
				if (t2 >= 0.0) {
					float f = clamp(t2 / 0.50, 0.0, 1.0);
					r = mix(0.3, 3.3, ease_out3(f));
					w = 0.24;
					a = 0.40 * pow(1.0 - f, 1.2);
					col = mix(gate_tone, vec3(0.26, 0.07, 0.035), 0.4);
				}
			}
			rmax = 3.6;
		} else if (kind == 7) {
			rmax = R * 1.03 + 1.0;
			if (idx == 0) {
				float f = clamp(age / WAVE_SWEEP, 0.0, 1.0);
				r = wave_sweep(age, R);
				w = mix(0.38, 0.22, f) * 1.6;
				a = 0.42 * (1.0 - f * f) * wsweep;
				col = gold;
			} else if (idx == 2 && wmend > 0.0) {
				float f = seg(MEND_RING, MEND_RING + 0.72, age);
				r = mix(2.7, 0.85, ease_out(f));
				w = 0.19;
				a = 0.62 * wmend * pow(sin(f * PI), 0.7);
				col = cyan;
				rmax = 3.0;
				y = 0.095;
			}
		} else if (kind == 4) {
			float f = fract(age / 1.35 + fi / 3.0);
			r = mix(8.6, 0.4, pow(f, 1.7));
			w = mix(0.46, 0.15, f) * 1.7;
			a = (0.20 + 0.40 * prog) * pow(sin(f * PI), 0.6) * live * smoothstep(0.0, 0.25, age);
			col = vec3(0.09, 0.008, 0.02);
			rmax = 9.2;
		} else if (kind == 6) {
			// Gold body of the ring that closes on a sealed gate and stays.
			float t = age - SEAL_LOCK;
			if (idx == 0 && t >= 0.0) {
				float f = clamp(t / SEAL_STAMP, 0.0, 1.0);
				r = mix(2.6, 0.95, f * f);
				w = mix(0.22, 0.10, f) * 1.7;
				a = 0.78 * smoothstep(0.0, 0.05, t) * rest;
				col = gold;
			}
			rmax = 3.0;
		} else if (kind == 5) {
			if (idx == 0) {
				float f = clamp(age / 0.50, 0.0, 1.0);
				r = mix(0.3, R * 5.0, ease_out3(f));
				w = mix(0.90, 0.40, f) * 1.5;
				a = 0.66 * pow(1.0 - seg(0.2, 0.7, age), 1.1);
				fill = 0.35 * pow(1.0 - clamp(age / 0.5, 0.0, 1.0), 1.2);
				col = vec3(0.34, 0.05, 0.05);
				rmax = R * 5.0 + 1.4;
			} else if (idx == 1) {
				float t = age - AFT;
				if (t >= 0.0) {
					float f = clamp(t / 0.95, 0.0, 1.0);
					r = mix(0.5, 13.5, 1.0 - pow(1.0 - f, 2.0));
					w = mix(0.80, 0.42, f) * 1.6;
					a = 0.72 * pow(1.0 - f, 0.8);
					col = vec3(0.46, 0.05, 0.06);
				}
				rmax = 14.6;
			} else {
				r = R * 3.0;
				w = 0.20;
				a = 0.55 * smoothstep(0.30, 0.55, age) * (1.0 - smoothstep(0.9, 2.9, age));
				col = vec3(0.30, 0.035, 0.05);
				rmax = R * 3.0 + 0.8;
			}
		}
		world = origin + up * y + mx * c.x * 2.0 * rmax + fwd * c.y * 2.0 * rmax;
		v_ring = vec4(r / rmax, w / rmax, fill, 0.0);
		alpha = a;
		v_cell = -1.0;
	} else if (part == 21) {
		float s = 1.0;
		float a = 0.0;
		float rot = 0.0;
		bool facing = false;
		vec3 at = origin + up * 0.07;
		v_cell = 26.0;
		if (kind == 0) {
			float t = age - FL;
			if (idx == 0) {
				// The world darkens around the breaking crystal: the flash lands on black.
				s = 5.4;
				a = 0.62 * smoothstep(0.0, 0.13, age) * (1.0 - seg(FL, FL + 0.28, age));
				col = vec3(0.008, 0.012, 0.03);
			} else if (idx == 1) {
				// The guardian crest in gold on the plaza for as long as the aura holds.
				if (t >= 0.0) {
					s = 1.78 * mix(1.5, 1.0, ease_out3(t / 0.18));
					rot = 0.22 * age;
					a = 0.86 * (1.0 - smoothstep(dur - 0.22, dur, age));
					col = mix(gold, gold_ink, 0.6 * step(dur - 1.0, age) * step(0.5, fract((dur - age) * 5.0)));
				}
				at = origin + up * 0.09;
				v_cell = 28.0;
			} else if (t >= 0.0) {
				// Gold light washing over the plaza after the flash.
				float f = clamp(t / 1.1, 0.0, 1.0);
				s = 3.0;
				a = 0.40 * pow(1.0 - f, 1.3) * smoothstep(0.0, 0.05, t);
				col = vec3(0.85, 0.50, 0.10);
				at = origin + up * 0.065;
			}
		} else if (kind == 1) {
			if (idx == 0) {
				// The mend's cyan on the plaza.
				float f = seg(0.30, 1.50, age);
				s = 2.1;
				a = 0.30 * mend * pow(sin(f * PI), 0.8) * clear_out;
				col = cyan;
			} else if (idx == 2) {
				float f = clamp(age / 0.8, 0.0, 1.0);
				s = 2.6;
				a = 0.34 * pow(1.0 - f, 1.3);
				col = vec3(0.85, 0.50, 0.10);
				at = origin + up * 0.065;
			} else if (fin > 0.5 && age >= CREST_AT) {
				// The last clear: the guardian crest in gold on the plaza, to stay.
				s = 1.78 * mix(1.5, 1.0, ease_out3((age - CREST_AT) / 0.18));
				a = 0.86 * rest;
				col = gold;
				at = origin + up * 0.09;
				v_cell = 28.0;
			}
		} else if (kind == 7) {
			if (idx == 2) {
				float f = clamp(age / 0.8, 0.0, 1.0);
				s = 2.5;
				a = 0.28 * pow(1.0 - f, 1.3) * wsweep;
				col = vec3(0.85, 0.50, 0.10);
				at = origin + up * 0.065;
			} else if (idx == 0) {
				// The mend's cyan on the plaza.
				float f = seg(0.30, 1.50, age);
				s = 2.1;
				a = 0.30 * wmend * pow(sin(f * PI), 0.8);
				col = cyan;
			}
		} else if (kind == 6) {
			// The crest in gold on a sealed gate.
			float t = age - SEAL_LOCK - SEAL_STAMP;
			if (idx == 1 && t >= 0.0) {
				s = 0.98 * mix(1.6, 1.0, ease_out3(t / 0.16));
				a = 0.86 * rest;
				col = gold;
				at = origin + up * 0.09;
				v_cell = 28.0;
			}
		} else if (kind == 4) {
			if (idx == 0) {
				// The ground around the gate goes dark.
				s = R * 4.2;
				a = 0.56 * ease_out(clamp(prog * 2.0, 0.0, 1.0)) * live;
				col = vec3(0.035, 0.006, 0.014);
			} else if (idx == 1) {
				// The dark sun: a black disc inside the corona's limb.
				float grow = (1.3 + 2.2 * prog) * (1.0 + 0.5 * pow(seg(dur - 0.5, dur, age), 2.0));
				s = grow * 0.252;
				a = 0.94 * live * smoothstep(0.0, 0.4, age);
				col = vec3(0.012, 0.0, 0.012);
				at = sun;
				facing = true;
				v_cell = -2.0;
			}
		} else if (kind == 5) {
			if (idx == 0) {
				float f = clamp(age / 3.3, 0.0, 1.0);
				s = R * 4.2;
				a = 0.62 * pow(1.0 - f, 0.9);
				col = vec3(0.04, 0.012, 0.02);
			} else if (idx == 1 && age < 0.12) {
				s = 3.5 * 0.252 * (1.0 - age / 0.12);
				a = 0.94;
				col = vec3(0.012, 0.0, 0.012);
				at = sun;
				facing = true;
				v_cell = -2.0;
			}
		}
		if (facing) {
			world = at + (cam_right * c.x + cam_up * c.y) * 2.0 * s - cam_fwd * 0.36;
		} else {
			vec2 rr = rot2(c, rot);
			world = at + (mx * rr.x + fwd * rr.y) * 2.0 * s;
		}
		alpha = a;
	} else if (part == 22) {
		float h1 = hash11(seed * 4.1 + fi);
		float h2 = hash11(seed * 6.7 + fi * 1.9);
		float ang = (fi + h1 * 0.8) / 6.0 * TAU;
		vec3 radial = mx * cos(ang) + fwd * sin(ang);
		float a = 0.0;
		float s = 0.0;
		float rot = h1 * TAU;
		vec3 at = origin;
		if (kind == 0) {
			// Dust lit gold by the flash, rolling off the plaza.
			float t = age - FL - h1 * 0.05;
			float life = 1.0 + 0.3 * h2;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				s = mix(0.7, 2.2, ease_out3(f)) * (0.85 + 0.3 * h2);
				at = origin + radial * (1.2 + 2.2 * ease_out(f)) + up * (0.3 + 0.7 * f);
				rot += f * (h2 - 0.5) * 2.0;
				col = mix(vec3(0.60, 0.36, 0.10), dust, smoothstep(0.0, 0.6, f));
				a = 0.30 * pow(1.0 - f, 1.3) * smoothstep(0.0, 0.06, f);
			}
		} else if (kind == 3) {
			float t = age - ARR - h1 * 0.04;
			float life = 0.8 + 0.3 * h2;
			if (idx < 4 && t >= 0.0 && t < life) {
				float f = t / life;
				s = mix(0.5, 1.6, ease_out3(f));
				at = origin + radial * (0.4 + 1.3 * ease_out(f)) + up * (0.25 + 0.6 * f);
				rot += f * (h2 - 0.5) * 2.0;
				col = mix(gate_dust, dust, smoothstep(0.0, 0.5, f));
				a = 0.30 * pow(1.0 - f, 1.3) * smoothstep(0.0, 0.08, f);
			}
		} else if (kind == 4) {
			// A wide, slow whirl of dark mist around the gate.
			float ph = fract(age / (2.8 + 0.8 * h2) + h1);
			float turn = h2 * TAU + age * (0.45 + 0.5 * prog);
			at = origin + (mx * cos(turn) + fwd * sin(turn)) * R * (0.9 + 1.6 * ph) + up * (0.2 + 0.6 * ph);
			s = 1.2 + 1.5 * ph;
			rot += age * 0.4;
			col = mix(gate_dark, vec3(0.20, 0.03, 0.05), 0.35 * prog);
			a = (0.28 + 0.42 * prog) * pow(sin(ph * PI), 0.8) * live;
		} else if (kind == 5) {
			float t = age - h1 * 0.06;
			float life = 2.3 + 0.6 * h2;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				s = mix(1.2, 4.6, ease_out3(f));
				at = origin + radial * (0.5 + 3.2 * R * ease_out(f)) + up * (0.5 + 2.0 * f);
				rot += f * (h2 - 0.5) * 1.5;
				col = mix(vec3(0.40, 0.14, 0.10), vec3(0.14, 0.09, 0.10), smoothstep(0.0, 0.4, f));
				a = 0.62 * pow(1.0 - f, 1.2) * smoothstep(0.0, 0.04, f);
			}
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.12;
		alpha = a;
		v_cell = 4.0;
	} else if (part == 23) {
		float h1 = hash11(seed * 7.3 + fi);
		float h2 = hash11(seed * 11.9 + fi * 1.3);
		float h3 = hash11(seed * 19.7 + fi * 0.9);
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin;
		float rot = h1 * TAU;
		if (kind == 4) {
			// Stones leave the ground and drift up toward the dark sun.
			float t = age - 0.4 - 2.0 * h3;
			if (t >= 0.0) {
				float ang = (fi + h1) / 8.0 * TAU;
				float lift = (0.3 + 1.9 * h2) * ease_out(clamp(t / 1.8, 0.0, 1.0));
				at = origin + (mx * cos(ang) + fwd * sin(ang)) * R * (0.7 + 1.5 * h1)
					+ up * (0.15 + lift + 0.10 * sin(age * 2.3 + h1 * 9.0));
				s = 0.10 + 0.12 * h2;
				rot += age * (0.6 + 1.2 * h3) * (h2 < 0.5 ? -1.0 : 1.0);
				a = 0.95 * smoothstep(0.0, 0.3, t) * live;
				col = vec3(0.035, 0.02, 0.03);
			}
		} else if (kind == 5) {
			float life = 1.2 + 0.4 * h3;
			if (age < life) {
				float ang = (fi + h1 * 0.9) / 8.0 * TAU;
				vec3 vel = (mx * sin(ang) + fwd * cos(ang)) * (3.0 + 4.0 * h2) + up * (5.0 + 5.0 * h1);
				at = origin + up * 0.3 + vel * age + up * (-5.0 * age * age);
				s = 0.18 + 0.16 * h2;
				rot += age * (4.0 + 6.0 * h2) * (h3 < 0.5 ? -1.0 : 1.0);
				a = (at.y > 0.0 ? 1.0 : 0.0) * 0.95 * (1.0 - smoothstep(0.7, 1.0, age / life));
				col = vec3(0.05, 0.03, 0.035);
			}
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
		alpha = a;
		v_cell = 22.0;
	} else if (part == 24) {
		float a = 0.0;
		if (kind == 1 || kind == 7) {
			// Bodies of the halos rising up the mending crystal.
			if (idx < 3) {
				float f = seg(MEND_HALO + 0.20 * fi, MEND_HALO + 0.58 + 0.20 * fi, age);
				float s = mix(1.20, 0.78, f) * 1.04;
				world = origin + up * mix(0.35, 2.35, ease_out(f)) + (mx * c.x + fwd * c.y) * 2.0 * s;
				a = 0.60 * (kind == 7 ? wmend : mend * clear_out) * pow(sin(f * PI), 0.7);
				col = cyan;
				v_cell = 3.0;
			}
		} else if (kind == 3) {
			// Body of the beacon's column. Light alone cannot stand against snow, so on a
			// bright field a coral column carries it (on dark ground it is barely there
			// and the additive column does the work). Same height and timing as the light.
			if (idx == 0) {
				float t = age - ARR;
				float h = 5.2;
				float w = 1.75;
				a = 1.0;
				if (t >= 0.0) {
					float f = clamp(t / 1.9, 0.0, 1.0);
					h = mix(5.2, 7.5, ease_out3(clamp(t / 0.09, 0.0, 1.0))) * (1.0 - 0.18 * f);
					w = mix(3.4, 0.9, ease_out(clamp(t / 0.5, 0.0, 1.0)));
					a = pow(1.0 - f, 1.3);
				}
				vec3 pillar_side = normalize(cross(up, cam_fwd));
				world = origin + up * (c.y + 0.5) * h + pillar_side * c.x * w * 0.62 - cam_fwd * 0.18;
				a *= 0.05 + 0.30 * vfx_wash;
				col = gate_tone;
				v_cell = 17.0;
			}
		}
		alpha = a;
	} else {
		float h1 = hash11(seed * 13.0 + fi);
		float h2 = hash11(seed * 29.0 + fi * 1.7);
		float h3 = hash11(seed * 41.0 + fi * 0.37);
		float a = 0.0;
		if (kind == 0) {
			// Solid shards of the crystal: out, held, and back in.
			float t_ar = shard_arrival(h2);
			if (age < t_ar + 0.06) {
				vec3 at = revive_shard(age, h1, h2, h3, fi, origin, mx, fwd);
				vec3 vel = (at - revive_shard(age - 0.02, h1, h2, h3, fi, origin, mx, fwd)) / 0.02;
				float speed = length(vel);
				float tum = h1 * TAU + age * (3.0 + 4.0 * h3);
				vec3 tumble = normalize(cam_up * cos(tum) + cam_right * sin(tum));
				float fast = smoothstep(0.6, 3.0, speed);
				vec3 along = normalize(mix(tumble, vel / max(speed, 0.001), fast));
				float len = (0.50 + 0.26 * h2) * (1.0 + 0.5 * fast);
				world = streak(at, along, c, len, 0.24 + 0.10 * h1, cam_fwd, cam_right) - cam_fwd * 0.3;
				float pull = seg(FL + 0.04 + 0.10 * h1, t_ar, age);
				a = 0.95 * smoothstep(0.0, 0.04, age) * (1.0 - seg(t_ar, t_ar + 0.06, age));
				col = mix(vec3(0.22, 0.72, 0.95), vec3(0.95, 0.80, 0.42), pull * pull);
				v_cell = 6.0;
			}
		} else if (kind == 1) {
			// Bodies of the fountain's stars.
			float life = 0.75 + 0.30 * h3;
			if (age < life) {
				float f = age / life;
				vec3 at = fountain_star(age, h1, h2, fi, origin, mx, fwd);
				vec3 now = at - fountain_star(age - 0.02, h1, h2, fi, origin, mx, fwd);
				vec3 along = normalize(now + vec3(0.0, 0.00001, 0.0));
				bool star = idx % 3 == 0;
				float len = star ? (0.46 + 0.14 * h2) * 1.15 : (0.50 + 0.35 * h2) * clamp(length(now) / 0.02 * 0.16, 0.6, 1.7) * 1.1;
				float wid = star ? len : 0.30 + 0.12 * h1;
				world = streak(at, star ? normalize(cam_up * cos(age * 5.0 + fi) + cam_right * sin(age * 5.0 + fi)) : along, c, len, wid, cam_fwd, cam_right) - cam_fwd * 0.3;
				a = 0.80 * pow(1.0 - f, 0.8) * clear_out;
				col = gold;
				v_cell = star ? 1.0 : 27.0;
			}
		}
		alpha = a;
	}
	if (alpha <= 0.0005) world = origin;
	v_tint = vec4(col, alpha);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	vec3 rgb = v_tint.rgb;
	if (v_cell < -1.5) {
		a = 1.0 - smoothstep(0.93, 1.0, length(v_plane));
	} else if (v_cell < -0.5) {
		float d = length(v_plane);
		float r = v_ring.x;
		float w = max(v_ring.y, 0.004);
		float band = smoothstep(r - w, r - w * 0.45, d) * (1.0 - smoothstep(r + w * 0.45, r + w, d));
		float fill = (1.0 - smoothstep(r * 0.4, r, d)) * v_ring.z;
		a = (band + fill) * (1.0 - smoothstep(0.92, 1.0, d));
		if (v_arc.x >= 0.0) {
			float left = timer_left(v_plane, v_arc.x, v_arc.y);
			rgb = mix(v_ink, v_tint.rgb, left);
			a *= mix(0.62, 1.0, left);
		}
	} else if (v_cell < 15.5) {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	} else {
		a = texture(skill_sprites, cell_uv(int(v_cell + 0.5) - 16, UV)).a;
	}
	float coloured = smoothstep(0.10, 0.30, max(rgb.r, max(rgb.g, rgb.b))) * vfx_wash;
	ALBEDO = mix(rgb, pow(rgb, vec3(1.6)), coloured);
	ALPHA = clamp(clamp(a, 0.0, 1.0) * v_tint.a * (1.0 + 0.4 * coloured), 0.0, 1.0);
}
