shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"
#include "res://art/vfx/vfx_moment.gdshaderinc"

// Light of the run-level moments (StellarVfx "Moments" pool): the crystal's revival, a
// stage clear, the reveal of a new battlefield and the final boss. One MultiMesh instance
// plays one whole sequence; every part reads its own window of the instance's age.
// This layer is the light only: hot edges, flashes, rays, glints. The colour and the shape
// of every ring, crest and mark live in vfx_moment_mix.gdshader, alpha-blended, because
// additive gold on a pale road or on snow is just white. Keep fills out of this layer.
//   transform: origin on the ground. -Z is world north for the crystal-centred kinds (the
//              revival's timer ring drains clockwise from the top of the screen), the way
//              into the field for a gate beacon, the direction of the fallen boss for a
//              stage clear. The basis scale is 1 + a distance (stage clear: to that boss).
//   COLOR:     rgb main colour, a = one scalar per kind (stage clear: how much the crystal
//              mended, 0..1, plus 2 on the last stage; gate seal: 3)
//   CUSTOM:    x birth (vfx seconds, epoch relative)  y radius R (world units: the field
//              for the crystal kinds, the boss footprint for the final boss)
//              z duration (revival: seconds the crystal cannot be hurt; stage clear: seconds
//              until the world is rebuilt; final warning: seconds until the boss)  w kind
// Kinds: 0 revive  1 stage_clear  2 stage_sweep  3 gate_beacon  4 final_warning  5 final_burst
//        6 gate_seal (the last clear closes every gate)
// Parts (UV2.x): 0 ground ring x3   1 ground sprite x2   2 flash x2   3 flare x2
//   4 pillar x2   5 shards x16   6 motes x16   7 marks x4 (the halos rising up a mending
//   crystal; the chevrons of a gate are drawn by the road ribbon, vfx_road)   8 lightning x6
// Kinds 2 and 3 are spawned under the battlefield card while the battle is paused: what
// they draw at age 0 is the picture the player sees behind the card, so the layers meant
// to be seen there have no fade-in. The ground mark of a gate (its ring and the chevrons
// at the road's mouth) is NOT one of them: under the card the HUD draws that mark itself
// (ArenaScreen._draw_gate_beacons, animated in real time), so here it only appears once
// time runs again, growing out of the HUD's ring. Under the card a gate shows its column
// of light and star, which a flat mark cannot give.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are dimmed and
// pushed toward their saturated hue (the mix layer carries the shape).
uniform float vfx_wash = 0.0;
uniform float vfx_epoch = 0.0;

varying vec4 v_tint;
varying vec3 v_wake;     // ring: colour of the wake / fill (the lead edge uses v_tint)
varying float v_cell;    // -1 procedural ring, 0..15 battle atlas, 16..31 skill atlas
varying vec2 v_plane;
varying vec4 v_ring;     // r, width (fractions of the quad), fill, direction (+1 out, -1 in)
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
	vec3 pillar_side = normalize(cross(up, cam_fwd));
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
	float dist = link - 1.0;
	float prog = clamp(age / dur, 0.0, 1.0);
	float live = age < dur ? 1.0 : 0.0;
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = COLOR.rgb;
	float alpha = 0.0;
	float cell = 0.0;
	v_plane = c * 2.0;
	v_ring = vec4(0.0, 0.0, 0.0, 1.0);
	v_arc = vec2(-1.0, 1.0);
	v_wake = COLOR.rgb;
	// Palettes: `rich` is the main colour deepened so it survives being added to a pale
	// ground, `hot` a warm near-white for edges and cores.
	vec3 tone = COLOR.rgb;
	vec3 rich = min(tone * vec3(1.08, 0.85, 0.43), vec3(1.0));
	vec3 hot = mix(tone, vec3(1.0, 0.97, 0.88), 0.75);
	vec3 deep = rich * vec3(1.0, 0.70, 0.45);
	vec3 crystal = vec3(0.37, 0.90, 1.0);
	vec3 crystal_hot = vec3(0.86, 0.98, 1.0);
	vec3 red = vec3(1.0, 0.16, 0.26);
	vec3 violet = vec3(0.58, 0.28, 1.0);
	vec3 ember = vec3(1.0, 0.70, 0.28);
	vec3 ember_hot = vec3(1.0, 0.94, 0.78);
	vec3 coral = vec3(1.0, 0.51, 0.21);
	float aura = revive_aura(age, dur);
	// Stage clear: nothing of an ordinary clear may be left when the world is rebuilt at
	// `dur`. The last clear (and its gate seals) settles instead into a rest that holds
	// under the result panel, and leaves by itself only if time runs on.
	float fin = (kind == 1 || kind == 6) && amount >= 1.5 ? 1.0 : 0.0;
	float mend = amount - 2.0 * fin;
	float clear_out = fin > 0.5 ? 1.0 : 1.0 - smoothstep(dur - 0.42, dur - 0.10, age);
	float rest = fin * (1.0 - smoothstep(dur + 2.0, dur + 3.4, age));
	vec3 sun = dark_sun(origin, fwd, cam_fwd, R);
	if (part == 0) {
		float r = 0.0;
		float w = 0.1;
		float fill = 0.0;
		float a = 0.0;
		float rmax = 1.0;
		float dir = 1.0;
		float y = 0.09;
		if (kind == 0) {
			if (idx == 0) {
				if (age < FL) {
					// Collapse: light is drawn into the breaking crystal, faster and faster.
					float f = age / FL;
					r = mix(3.6, 0.25, f * f);
					w = 0.20;
					a = 0.35 + 0.65 * f;
					col = mix(rich, hot, f);
					rmax = 4.0;
					dir = -1.0;
				} else {
					// The shockwave that stops every monster: across the whole field.
					float t = age - FL;
					float f = clamp(t / 0.50, 0.0, 1.0);
					r = revive_wave(t, R);
					w = mix(0.50, 0.28, f);
					a = 0.95 * (1.0 - f * f * f);
					fill = 0.14 * pow(1.0 - clamp(t / 0.20, 0.0, 1.0), 1.5);
					col = mix(vec3(1.0), hot, 0.4 + 0.6 * f);
					v_wake = rich;
					rmax = R * 1.06 + 1.0;
				}
			} else if (idx == 1) {
				// The aura's clock: the part of the ring still to run glows, the head burns.
				if (age < dur) {
					r = 2.0;
					w = 0.085;
					a = 0.80 * aura;
					v_arc = vec2(seg(FL, dur, age), max(floor(dur + 0.5), 1.0));
					col = hot;
				} else {
					float f = clamp((age - dur) / 0.32, 0.0, 1.0);
					r = mix(2.0, 2.8, ease_out(f));
					w = 0.10;
					a = 0.7 * pow(1.0 - f, 1.4);
					col = rich;
				}
				rmax = 3.0;
				y = 0.11;
			} else {
				// Echo of the shockwave, thinner and deeper.
				float t = age - FL - 0.10;
				if (t >= 0.0) {
					float f = clamp(t / 0.62, 0.0, 1.0);
					r = mix(0.3, R * 1.06, 1.0 - pow(1.0 - f, 2.2));
					w = 0.22;
					a = 0.45 * pow(1.0 - f, 0.8);
					col = mix(hot, rich, 0.6);
					v_wake = deep;
				}
				rmax = R * 1.06 + 1.0;
			}
		} else if (kind == 1) {
			if (idx == 0) {
				// The victory release: the bright front of a broad band crossing the field.
				float f = clamp(age / 0.60, 0.0, 1.0);
				r = clear_wave(age, R);
				w = mix(0.80, 0.45, f);
				a = 0.75 * (1.0 - f * f);
				fill = 0.10 * pow(1.0 - clamp(age / 0.25, 0.0, 1.0), 1.5);
				col = mix(vec3(1.0), hot, 0.5);
				v_wake = rich;
				rmax = R * 1.04 + 1.3;
			} else if (idx == 1) {
				// The mend: light closing on the crystal.
				float f = seg(MEND_RING, MEND_RING + 0.72, age);
				r = mix(2.7, 0.85, ease_out(f));
				w = 0.11;
				a = 0.80 * mend * pow(sin(f * PI), 0.7);
				col = crystal_hot;
				rmax = 3.0;
				dir = -1.0;
				y = 0.11;
			} else if (fin > 0.5) {
				// The last clear: a second wave that reaches the rim and locks there, hot
				// for a moment, then a steady gold ring around the whole field.
				float t = age - SEAL_WAVE;
				if (t >= 0.0) {
					float f = clamp(t / (SEAL_LOCK - SEAL_WAVE), 0.0, 1.0);
					float locked = step(1.0, f);
					float heat = 1.0 - seg(SEAL_LOCK, SEAL_LOCK + 0.45, age);
					r = mix(0.4, R, 1.0 - pow(1.0 - f, 2.2));
					w = mix(0.60, 0.15, f);
					a = mix(0.72, 0.42 + 0.55 * heat, locked) * rest;
					col = mix(rich, hot, mix(0.5, 0.25 + 0.65 * heat, locked));
					v_wake = rich;
				}
				rmax = R * 1.04 + 1.3;
			} else {
				float t = age - 0.12;
				if (t >= 0.0) {
					float f = clamp(t / 0.62, 0.0, 1.0);
					r = mix(0.4, R * 1.04, 1.0 - pow(1.0 - f, 2.0));
					w = 0.26;
					a = 0.34 * pow(1.0 - f, 0.8);
					col = rich;
					v_wake = deep;
				}
				rmax = R * 1.04 + 1.3;
			}
			a *= clear_out;
		} else if (kind == 2) {
			if (idx == 0) {
				// The scan: charged around the plaza while the card is open, then outward.
				float f = clamp(age / ARR, 0.0, 1.0);
				r = sweep_radius(age, R);
				w = mix(0.28, 0.42, smoothstep(0.0, 0.15, f));
				a = 0.95 * (1.0 - seg(ARR, ARR + 0.22, age));
				fill = 0.08 * (1.0 - f);
				col = mix(vec3(1.0), hot, 0.5);
				v_wake = rich;
			} else if (idx == 1) {
				// The rim of the new field: lit from the first frame, flares as the scan lands.
				r = R;
				w = 0.13;
				float after = max(age - ARR, 0.0);
				a = age < ARR ? 0.50 + 0.08 * sin(age * 7.0) : pow(1.0 - clamp(after / 1.25, 0.0, 1.0), 1.5);
				col = age < ARR ? mix(rich, hot, 0.4) : mix(hot, rich, clamp(after / 0.4, 0.0, 1.0) * 0.7);
			} else if (age < dur) {
				float t = age - 0.13;
				if (t >= 0.0) {
					r = sweep_radius(t, R);
					w = 0.18;
					a = 0.40 * (1.0 - seg(ARR, ARR + 0.20, t));
					col = rich;
					v_wake = deep;
				}
			} else {
				// The first runner has reached the plaza: this is where they are headed.
				float f = clamp((age - dur) / 0.50, 0.0, 1.0);
				r = mix(2.1, 3.1, ease_out3(f));
				w = 0.16;
				a = 0.85 * pow(1.0 - f, 1.3);
				col = mix(vec3(1.0, 0.95, 0.88), coral, f);
				v_wake = coral;
			}
			rmax = R + 1.0;
		} else if (kind == 3) {
			float t = age - ARR;
			if (idx == 0) {
				if (t < 0.0) {
					// The mouth of the gate. Nothing at age 0 (the HUD's own ring marks the
					// gate under the card); once time runs it grows out of that ring's size.
					r = mix(0.6, 1.25, ease_out3(age / 0.22));
					w = 0.11;
					a = (0.72 + 0.14 * sin(age * 6.0)) * smoothstep(0.0, 0.14, age);
					col = mix(rich, hot, 0.45);
				} else {
					float f = clamp(t / 0.45, 0.0, 1.0);
					r = mix(0.3, 2.8, ease_out3(f));
					w = mix(0.40, 0.16, f);
					a = pow(1.0 - f, 1.1);
					fill = 0.22 * pow(1.0 - f, 2.0);
					col = mix(vec3(1.0), hot, f);
				}
			} else if (idx == 1) {
				if (t >= 0.0) {
					r = 1.25;
					w = 0.10;
					a = 0.70 * (1.0 - smoothstep(1.1, 1.9, t)) * (0.85 + 0.15 * sin(age * 6.0));
					col = mix(rich, hot, 0.3);
				}
			} else {
				float t2 = t - 0.09;
				if (t2 >= 0.0) {
					float f = clamp(t2 / 0.50, 0.0, 1.0);
					r = mix(0.3, 3.3, ease_out3(f));
					w = 0.14;
					a = 0.5 * pow(1.0 - f, 1.2);
					col = rich;
				}
			}
			v_wake = rich;
			rmax = 3.6;
		} else if (kind == 6) {
			// The last clear seals a gate: a ring closes on it as the wave locks on the
			// rim and stays; the stamp of the crest sends one short shock outward.
			float t = age - SEAL_LOCK;
			if (idx == 0) {
				if (t >= 0.0) {
					float f = clamp(t / SEAL_STAMP, 0.0, 1.0);
					float heat = 1.0 - seg(SEAL_STAMP, SEAL_STAMP + 0.45, t);
					r = mix(2.6, 0.95, f * f);
					w = mix(0.22, 0.10, f);
					a = (0.40 + 0.60 * heat) * smoothstep(0.0, 0.05, t) * rest;
					col = mix(rich, hot, 0.25 + 0.65 * heat);
					dir = -1.0;
				}
			} else if (idx == 1) {
				float t2 = t - SEAL_STAMP;
				if (t2 >= 0.0) {
					float f = clamp(t2 / 0.34, 0.0, 1.0);
					r = mix(0.3, 2.3, ease_out3(f));
					w = mix(0.34, 0.14, f);
					a = 0.9 * pow(1.0 - f, 1.2);
					fill = 0.18 * pow(1.0 - f, 2.0);
					col = mix(vec3(1.0), hot, f);
				}
			}
			v_wake = rich;
			rmax = 3.0;
		} else if (kind == 4) {
			// Rings from across the field closing on the gate: everything is drawn to it.
			float f = fract(age / 1.35 + fi / 3.0);
			r = mix(8.6, 0.4, pow(f, 1.7));
			w = mix(0.46, 0.15, f);
			a = (0.22 + 0.58 * prog) * pow(sin(f * PI), 0.6) * live * smoothstep(0.0, 0.25, age);
			col = mix(red, ember, 0.25 + 0.45 * prog);
			v_wake = red;
			rmax = 9.2;
			dir = -1.0;
		} else if (kind == 5) {
			if (idx == 0) {
				float f = clamp(age / 0.50, 0.0, 1.0);
				r = mix(0.3, R * 5.0, ease_out3(f));
				w = mix(0.60, 0.30, f);
				a = 0.75 * pow(1.0 - f, 1.0);
				col = mix(ember_hot, ember, 0.5);
				v_wake = mix(red, ember, 0.35);
				rmax = R * 5.0 + 1.4;
			} else if (idx == 1) {
				// The aftershock: the final boss is felt across the whole field.
				float t = age - AFT;
				if (t >= 0.0) {
					float f = clamp(t / 0.95, 0.0, 1.0);
					r = mix(0.5, 13.5, 1.0 - pow(1.0 - f, 2.0));
					w = mix(0.50, 0.28, f);
					a = 0.62 * pow(1.0 - f, 0.7);
					col = mix(ember_hot, ember, 0.5 + 0.5 * f);
					v_wake = red;
				}
				rmax = 14.6;
			} else {
				// The ground the boss claimed keeps smouldering.
				r = R * 3.0;
				w = 0.12;
				a = 0.62 * smoothstep(0.30, 0.55, age) * (1.0 - smoothstep(0.9, 2.9, age)) * (0.75 + 0.25 * sin(age * 9.0));
				col = mix(red, ember, 0.3);
				v_wake = red;
				rmax = R * 3.0 + 0.8;
			}
		}
		world = origin + up * y + mx * c.x * 2.0 * rmax + fwd * c.y * 2.0 * rmax;
		v_ring = vec4(r / rmax, w / rmax, fill, dir);
		alpha = a;
		cell = -1.0;
	} else if (part == 1) {
		float s = 1.0;
		float a = 0.0;
		float rot = 0.0;
		cell = 26.0;
		if (kind == 0) {
			float t = age - FL;
			if (idx == 0) {
				// The guardian crest: white-hot as the flash stamps it on the plaza, then a
				// low glow over its gold body (mix layer) for as long as the aura holds.
				if (t >= 0.0) {
					s = 1.78 * mix(1.5, 1.0, ease_out3(t / 0.18));
					rot = 0.22 * age;
					float heat = 1.0 - clamp(t / 0.45, 0.0, 1.0);
					a = (0.20 + 0.80 * heat + 0.05 * sin(age * 3.2)) * (1.0 - smoothstep(dur - 0.22, dur, age));
					a *= 1.0 - 0.45 * step(dur - 1.0, age) * step(0.5, fract((dur - age) * 5.0));
					col = mix(rich, hot, 0.3 + 0.7 * heat);
				}
				cell = 28.0;
			} else if (t >= 0.0) {
				float f = clamp(t / 0.9, 0.0, 1.0);
				s = 2.4 + 0.4 * ease_out(f);
				a = 0.30 * pow(1.0 - f, 1.5);
				col = rich;
			}
		} else if (kind == 1) {
			if (idx == 0) {
				float f = seg(0.30, 1.50, age);
				s = 2.0;
				a = 0.36 * mend * pow(sin(f * PI), 0.8) * clear_out;
				col = crystal;
			} else if (fin > 0.5 && age >= CREST_AT) {
				// The last clear: the guardian crest is stamped on the plaza and stays.
				float t = age - CREST_AT;
				float heat = 1.0 - clamp(t / 0.45, 0.0, 1.0);
				s = 1.78 * mix(1.5, 1.0, ease_out3(t / 0.18));
				a = (0.20 + 0.80 * heat) * rest;
				col = mix(rich, hot, 0.3 + 0.7 * heat);
				cell = 28.0;
			} else {
				float f = clamp(age / 0.8, 0.0, 1.0);
				s = 2.2 + 0.4 * ease_out(f);
				a = 0.28 * pow(1.0 - f, 1.4);
				col = rich;
			}
		} else if (kind == 2) {
			if (idx == 0) {
				s = 2.3;
				a = 0.36 * (1.0 - smoothstep(0.15, 1.2, age));
				col = rich;
			}
		} else if (kind == 3) {
			if (idx == 0) {
				float t = age - ARR;
				s = 1.7 + (t >= 0.0 ? 0.5 * ease_out(t / 0.3) : 0.0);
				a = t < 0.0 ? 0.18 : mix(0.55, 0.0, smoothstep(0.0, 1.9, t));
				col = t < 0.0 ? rich : mix(hot, rich, clamp(t / 0.35, 0.0, 1.0));
			}
		} else if (kind == 6) {
			// The crest lands on the sealed gate: white-hot, then a low glow over its body.
			float t = age - SEAL_LOCK - SEAL_STAMP;
			if (idx == 0 && t >= 0.0) {
				float heat = 1.0 - clamp(t / 0.40, 0.0, 1.0);
				s = 0.98 * mix(1.6, 1.0, ease_out3(t / 0.16));
				a = (0.22 + 0.78 * heat) * rest;
				col = mix(rich, hot, 0.3 + 0.7 * heat);
				cell = 28.0;
			}
		} else if (kind == 4) {
			float throb = 0.78 + 0.22 * sin(age * (4.0 + 9.0 * prog));
			if (idx == 0) {
				// A second, outer rune ring turning against the gate's own.
				float grow = ease_out3(clamp(age / 1.2, 0.0, 1.0));
				s = R * 2.05 * mix(0.5, 1.0, grow);
				rot = age * (0.30 + 2.2 * pow(prog, 5.0));
				a = (0.30 + 0.55 * pow(prog, 1.2)) * throb * grow * live;
				col = mix(red, ember, 0.35 + 0.25 * sin(age * 1.3));
				cell = 24.0;
			} else {
				s = R * (1.6 + 1.3 * prog);
				a = (0.10 + 0.40 * pow(prog, 1.4)) * throb * live;
				col = mix(red, violet, 0.25) * 0.9;
			}
		} else if (kind == 5) {
			if (idx == 0) {
				float f = clamp(age / 0.7, 0.0, 1.0);
				s = R * mix(2.05, 3.5, ease_out3(f));
				rot = seed * TAU + age * 1.2;
				a = pow(1.0 - f, 1.3);
				col = mix(ember_hot, red, f);
				cell = 24.0;
			} else {
				float f = clamp(age / 2.4, 0.0, 1.0);
				s = R * (2.6 + 0.8 * ease_out(f));
				a = 0.70 * pow(1.0 - f, 1.5);
				col = mix(ember, red, clamp(f * 1.6, 0.0, 1.0));
			}
		}
		vec2 rr = rot2(c, rot);
		world = origin + up * 0.10 + (mx * rr.x + fwd * rr.y) * 2.0 * s;
		alpha = a;
	} else if (part == 2) {
		float a = 0.0;
		float s = 0.0;
		float rot = seed * TAU;
		vec3 at = origin + up * 1.0;
		cell = 0.0;
		if (kind == 0) {
			if (idx == 0) {
				// The hard flash: two frames of white, gone in an eighth of a second.
				float t = age - FL;
				if (t >= 0.0) {
					float f = clamp(t / 0.12, 0.0, 1.0);
					s = 3.2 + 1.6 * ease_out(f);
					a = pow(1.0 - f, 1.5);
					col = mix(vec3(1.0), hot, 0.5);
				}
			} else if (age < 0.09) {
				// The break itself: a sharp cold glint as the crystal gives way.
				float f = age / 0.09;
				s = 1.7 + 0.9 * f;
				a = 1.0 - f;
				col = crystal_hot;
				cell = 1.0;
			} else if (age >= 0.90) {
				// The crystal is whole again: a glint on its tip.
				float f = seg(0.90, 1.22, age);
				s = 1.2 + 1.1 * ease_out(f);
				rot += age * 3.0;
				a = pow(1.0 - f, 1.2);
				col = mix(vec3(1.0), crystal_hot, 0.5);
				at = origin + up * 2.0;
				cell = 1.0;
			}
		} else if (kind == 1) {
			if (idx == 0) {
				float f = clamp(age / 0.12, 0.0, 1.0);
				s = 2.6 + 1.4 * ease_out(f);
				a = pow(1.0 - f, 1.5);
				col = mix(vec3(1.0), hot, 0.5);
			} else if (age >= MEND_DING) {
				float f = seg(MEND_DING, MEND_DING + 0.28, age);
				s = 1.0 + 1.0 * ease_out(f);
				rot += age * 3.0;
				a = pow(1.0 - f, 1.2) * mend * clear_out;
				col = crystal_hot;
				at = origin + up * 2.0;
				cell = 1.0;
			}
		} else if (kind == 2) {
			if (idx == 0) {
				s = 2.6;
				a = 0.42 * (1.0 - smoothstep(0.0, 0.7, age));
				col = mix(rich, crystal_hot, 0.4);
			}
		} else if (kind == 3) {
			float t = age - ARR;
			float fade = 1.0 - smoothstep(1.0, 1.9, t);
			if (idx == 0) {
				// Lantern glow at the foot of the beacon, then the flare when the scan arrives.
				at = origin + up * 0.45;
				if (t < 0.0) {
					s = 1.25;
					a = 0.36 + 0.08 * sin(age * 6.0);
				} else {
					float f = clamp(t / 0.18, 0.0, 1.0);
					s = mix(2.9, 1.3, f);
					a = mix(1.0, 0.36 * fade, f);
				}
				col = t < 0.0 ? mix(rich, hot, 0.3) : mix(hot, rich, clamp(t / 0.3, 0.0, 1.0));
			} else {
				// The beacon's head: a star at the top of the column.
				float h = t < 0.0 ? 5.2 : mix(7.5, 6.2, clamp(t / 1.5, 0.0, 1.0));
				at = origin + up * h - cam_fwd * 0.2;
				s = 0.95 + 0.12 * sin(age * 5.0);
				rot = age * 0.8;
				a = (t < 0.0 ? 0.85 : fade);
				col = hot;
				cell = 1.0;
			}
		} else if (kind == 4) {
			if (idx == 0) {
				// The red halo around the dark sun: a ring outside the limb, the disc stays black.
				s = (1.3 + 2.2 * prog) * (1.0 + 0.5 * pow(seg(dur - 0.5, dur, age), 2.0)) * 1.02;
				a = (0.45 + 0.40 * prog) * live * smoothstep(0.0, 0.5, age);
				col = mix(red, violet, 0.15);
				at = sun;
				rot = 0.0;
				cell = 3.0;
			} else {
				float late = seg(dur - 1.0, dur, age);
				float fl = step(0.55, hash11(floor(age * 24.0) + seed * 7.0));
				s = 1.4 + 1.6 * late;
				a = 0.5 * late * fl * live;
				col = ember_hot;
				at = sun;
			}
		} else if (kind == 6) {
			// The stamp of the crest on a sealed gate.
			float t = age - SEAL_LOCK - SEAL_STAMP;
			if (idx == 0 && t >= 0.0) {
				float f = clamp(t / 0.12, 0.0, 1.0);
				s = 1.5 + 1.1 * ease_out(f);
				a = pow(1.0 - f, 1.5);
				col = mix(vec3(1.0), hot, 0.5);
				at = origin + up * 0.5;
			}
		} else if (kind == 5) {
			if (idx == 0) {
				// The ordinary gate's burst already flashes white: this is the ember glow
				// that stays around it a moment longer.
				float f = clamp(age / 0.40, 0.0, 1.0);
				s = 5.0 + 3.0 * ease_out(f);
				a = 0.60 * pow(1.0 - f, 1.6);
				col = mix(ember, red, 0.25 + 0.5 * f);
				at = origin + up * 1.6 - cam_fwd * R;
			} else if (age >= AFT) {
				float f = seg(AFT, AFT + 0.14, age);
				s = 3.0 + 1.8 * ease_out(f);
				a = 0.6 * pow(1.0 - f, 1.4);
				col = mix(ember_hot, ember, 0.5);
				at = origin + up * 1.6 - cam_fwd * R;
			}
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.4;
		alpha = a * (s > 0.001 ? 1.0 : 0.0);
	} else if (part == 3) {
		float a = 0.0;
		float s = 0.0;
		float rot = seed * TAU;
		vec3 at = origin + up * 1.0;
		vec2 anchor = vec2(0.0);
		cell = 21.0;
		if (kind == 0) {
			float t = age - FL;
			if (t >= 0.0) {
				if (idx == 0) {
					float f = clamp(t / 0.42, 0.0, 1.0);
					s = 1.5 + 6.0 * ease_out3(f);
					rot += f * 0.4;
					a = 0.9 * pow(1.0 - f, 1.5);
					col = mix(hot, rich, 0.3 + 0.6 * f);
				} else {
					// The blessing's light rising from the crystal.
					float f = clamp(t / 0.95, 0.0, 1.0);
					s = 4.6 + 2.0 * ease_out(f);
					rot = 0.05 * sin(age * 2.3);
					a = 0.50 * pow(1.0 - f, 1.3) * smoothstep(0.0, 0.05, t);
					col = rich;
					at = origin + up * 1.75;
					anchor = vec2(0.0, 0.40);
					cell = 31.0;
				}
			}
		} else if (kind == 1) {
			if (idx == 0) {
				float f = clamp(age / 0.42, 0.0, 1.0);
				s = 1.2 + 4.2 * ease_out3(f);
				rot += f * 0.4;
				a = 0.9 * pow(1.0 - f, 1.5);
				col = mix(hot, rich, 0.3 + 0.6 * f);
			} else {
				float f = clamp(age / 0.85, 0.0, 1.0);
				s = 3.4 + 1.3 * ease_out(f);
				rot = 0.04 * sin(age * 2.3);
				a = 0.38 * pow(1.0 - f, 1.3) * smoothstep(0.0, 0.05, age);
				col = rich;
				at = origin + up * 0.5;
				anchor = vec2(0.0, 0.40);
				cell = 31.0;
			}
		} else if (kind == 3) {
			float t = age - ARR;
			if (idx == 0 && t >= 0.0) {
				float f = clamp(t / 0.4, 0.0, 1.0);
				s = 1.0 + 3.6 * ease_out3(f);
				a = pow(1.0 - f, 1.5);
				col = mix(hot, rich, f);
				at = origin + up * 0.6;
			}
		} else if (kind == 4) {
			// The corona of the dark sun, and a wider one turning against it.
			float flick = 0.8 + 0.2 * sin(age * 19.0 + seed * 9.0) * sin(age * 6.1);
			float grow = (1.3 + 2.2 * prog) * (1.0 + 0.5 * pow(seg(dur - 0.5, dur, age), 2.0));
			if (idx == 0) {
				s = grow;
				rot = age * 0.5;
				a = (0.55 + 0.45 * prog) * flick * live * smoothstep(0.0, 0.4, age);
				col = mix(red, ember_hot, 0.30 + 0.45 * prog);
			} else {
				s = grow * 1.45;
				rot = -age * 0.33;
				a = (0.20 + 0.35 * prog) * flick * live * smoothstep(0.0, 0.6, age);
				col = mix(red, violet, 0.35);
			}
			at = sun;
			cell = 30.0;
		} else if (kind == 5) {
			if (idx == 0) {
				// The dark sun bursts.
				float f = clamp(age / 0.55, 0.0, 1.0);
				s = 3.5 + 8.0 * ease_out3(f);
				rot += age * 1.2;
				a = pow(1.0 - f, 1.2);
				col = mix(ember_hot, red, f);
				at = sun;
				cell = 30.0;
			} else {
				float f = clamp(age / 0.7, 0.0, 1.0);
				s = 2.0 + 10.5 * ease_out3(f);
				rot -= f * 0.5;
				a = pow(1.0 - f, 1.5);
				col = mix(ember_hot, mix(red, ember, 0.4), 0.2 + 0.7 * f);
				at = origin + up * 1.6 - cam_fwd * R;
			}
		}
		vec2 rr = rot2(c + anchor, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.38;
		alpha = a * (s > 0.001 ? 1.0 : 0.0);
	} else if (part == 4) {
		float a = 0.0;
		float h = 0.0;
		float w = 0.0;
		float push = 0.35;
		float foot = 0.0;
		vec3 lean = vec3(0.0);       // how far the top of the column stands from its foot
		if (kind == 0) {
			float t = age - FL;
			if (idx == 0) {
				if (t >= 0.0) {
					// A shaft from the sky onto the crystal: it lifts off the crystal's body
					// after the flash so the regrowing crystal stays in view.
					float f = clamp(t / 0.9, 0.0, 1.0);
					h = 9.5 * ease_out3(clamp(t / 0.08, 0.0, 1.0)) * (1.0 - 0.1 * f);
					w = mix(1.9, 0.42, ease_out(clamp(t / 0.35, 0.0, 1.0)));
					a = 0.9 * pow(1.0 - f, 1.2);
					col = mix(hot, rich, 0.3 + 0.5 * f);
					foot = 1.85 * smoothstep(0.10, 0.28, t);
				}
			} else {
				// A little light held inside the aegis while it lasts.
				h = 2.9;
				w = 0.9;
				a = 0.10 * aura;
				col = rich;
				push = 0.1;
			}
		} else if (kind == 1) {
			if (idx == 0) {
				float f = seg(0.30, 1.50, age);
				h = 3.4 * ease_out3(seg(0.30, 0.52, age));
				w = 1.15;
				a = 0.30 * mend * pow(sin(f * PI), 0.8) * clear_out;
				col = mix(crystal, crystal_hot, 0.3);
			} else if (fin > 0.5 && age >= CREST_AT) {
				// The last clear: a column of light answers from the crystal and stays,
				// quiet, above its tip.
				float t = age - CREST_AT;
				float calm = clamp(t / 0.5, 0.0, 1.0);
				h = 7.0 * ease_out3(clamp(t / 0.10, 0.0, 1.0));
				w = mix(1.6, 0.75, ease_out(calm));
				a = mix(0.80, 0.26, calm) * rest;
				col = mix(hot, rich, 0.2 + 0.6 * calm);
				foot = 1.85 * smoothstep(0.10, 0.28, t);
			}
		} else if (kind == 6) {
			// A short column where the crest lands on a sealed gate; gone before the rest.
			float t = age - SEAL_LOCK - SEAL_STAMP;
			if (idx == 0 && t >= 0.0) {
				float f = clamp(t / 0.45, 0.0, 1.0);
				h = 4.2 * ease_out3(clamp(t / 0.08, 0.0, 1.0)) * (1.0 - 0.2 * f);
				w = mix(1.3, 0.4, ease_out(f));
				a = 0.9 * pow(1.0 - f, 1.3);
				col = mix(hot, rich, 0.2 + 0.6 * f);
				push = 0.2;
			}
		} else if (kind == 3) {
			float t = age - ARR;
			if (idx == 0) {
				push = 0.2;
				if (t < 0.0) {
					h = 5.2;
					w = 1.75 + 0.12 * sin(age * 6.0);
					a = 0.90 + 0.08 * sin(age * 6.0 + 1.0);
					col = mix(rich, hot, 0.30);
				} else {
					float f = clamp(t / 1.9, 0.0, 1.0);
					h = mix(5.2, 7.5, ease_out3(clamp(t / 0.09, 0.0, 1.0))) * (1.0 - 0.18 * f);
					w = mix(3.4, 0.9, ease_out(clamp(t / 0.5, 0.0, 1.0)));
					a = pow(1.0 - f, 1.3);
					col = mix(hot, rich, clamp(t / 0.6, 0.0, 1.0) * 0.8);
				}
			}
		} else if (kind == 4) {
			if (idx == 0) {
				// A thread of light from the gate up to the dark sun.
				float flick = 0.7 + 0.3 * sin(age * 23.0 + seed * 9.0) * sin(age * 7.3);
				float reach = ease_out(clamp(prog * 3.0, 0.0, 1.0));
				h = (3.0 - 0.25 * (1.3 + 2.2 * prog)) * reach;
				lean = fwd * 2.2 * reach;
				w = 0.30 + 0.25 * prog;
				a = (0.18 + 0.42 * prog) * flick * live;
				col = mix(ember, red, 0.4);
				push = R;
			}
		} else if (kind == 5) {
			push = R;
			if (idx == 0) {
				float f = clamp(age / 1.3, 0.0, 1.0);
				h = 12.0 * ease_out3(clamp(age / 0.10, 0.0, 1.0));
				w = mix(3.1, 0.9, ease_out(f));
				a = pow(1.0 - f, 1.2);
				col = mix(ember_hot, mix(red, ember, 0.3), f * 0.85);
			} else {
				float f = clamp(age / 0.6, 0.0, 1.0);
				h = 14.0 * ease_out3(clamp(age / 0.08, 0.0, 1.0));
				w = mix(0.7, 0.25, f);
				a = pow(1.0 - f, 1.5);
				col = vec3(1.0);
			}
		}
		world = origin + up * (foot + (c.y + 0.5) * max(h - foot, 0.0)) + lean * (c.y + 0.5) + pillar_side * c.x * w - cam_fwd * push;
		// A column stands against the far field, not on the bright ground: undo the wash.
		alpha = a * (h > 0.001 ? 1.0 : 0.0) * (1.0 + 0.38 * vfx_wash);
		cell = 17.0;
	} else if (part == 5) {
		float h1 = hash11(seed * 13.0 + fi);
		float h2 = hash11(seed * 29.0 + fi * 1.7);
		float h3 = hash11(seed * 41.0 + fi * 0.37);
		float a = 0.0;
		if (kind == 0) {
			// The glint on each crystal shard (its body is in the mix layer).
			float t_ar = shard_arrival(h2);
			if (age < t_ar + 0.06) {
				vec3 at = revive_shard(age, h1, h2, h3, fi, origin, mx, fwd);
				vec3 vel = (at - revive_shard(age - 0.02, h1, h2, h3, fi, origin, mx, fwd)) / 0.02;
				float speed = length(vel);
				float tum = h1 * TAU + age * (3.0 + 4.0 * h3);
				vec3 tumble = normalize(cam_up * cos(tum) + cam_right * sin(tum));
				float fast = smoothstep(0.6, 3.0, speed);
				vec3 along = normalize(mix(tumble, vel / max(speed, 0.001), fast));
				float len = (0.50 + 0.26 * h2) * (1.0 + 0.9 * fast);
				world = streak(at, along, c, len, 0.11 + 0.05 * h1, cam_fwd, cam_right) - cam_fwd * 0.32;
				float pull = seg(FL + 0.04 + 0.10 * h1, t_ar, age);
				a = smoothstep(0.0, 0.04, age) * (1.0 - seg(t_ar, t_ar + 0.06, age));
				a *= (0.45 + 0.55 * pull) * (0.75 + 0.25 * sin(vfx_time * 30.0 + h1 * 20.0));
				col = mix(crystal_hot, hot, pull);
				cell = 27.0;
			}
		} else if (kind == 1) {
			// The hot core of each star of the fountain (its body is in the mix layer).
			float life = 0.75 + 0.30 * h3;
			if (age < life) {
				float f = age / life;
				vec3 at = fountain_star(age, h1, h2, fi, origin, mx, fwd);
				vec3 now = at - fountain_star(age - 0.02, h1, h2, fi, origin, mx, fwd);
				vec3 along = normalize(now + vec3(0.0, 0.00001, 0.0));
				bool star = idx % 3 == 0;
				float len = star ? 0.46 + 0.14 * h2 : (0.50 + 0.35 * h2) * clamp(length(now) / 0.02 * 0.16, 0.6, 1.7);
				float wid = star ? len : 0.24 + 0.10 * h1;
				world = streak(at, star ? normalize(cam_up * cos(age * 5.0 + fi) + cam_right * sin(age * 5.0 + fi)) : along, c, len, wid, cam_fwd, cam_right) - cam_fwd * 0.32;
				a = pow(1.0 - f, 0.7) * (0.8 + 0.2 * sin(vfx_time * 42.0 + h1 * 25.0)) * clear_out;
				col = mix(mix(vec3(1.0), hot, 0.4), rich, clamp(f * 1.1 - 0.2, 0.0, 1.0));
				cell = star ? 1.0 : 27.0;
			}
		} else if (kind == 6) {
			// Sparks struck by the crest landing; all of them are out before the rest.
			float t = age - SEAL_LOCK - SEAL_STAMP;
			float life = 0.28 + 0.14 * h3;
			if (idx < 8 && t >= 0.0 && t < life) {
				float f = t / life;
				float ang = (fi + h1 * 0.9) / 8.0 * TAU;
				vec3 vel = (mx * sin(ang) + fwd * cos(ang)) * (1.6 + 1.6 * h2) + up * (2.4 + 2.2 * h1);
				vec3 at = origin + up * 0.3 + vel * t + up * (-4.5 * t * t);
				vec3 along = normalize(vel + up * (-9.0 * t) + vec3(0.0, 0.0001, 0.0));
				world = streak(at, along, c, 0.32 + 0.18 * h2, 0.16, cam_fwd, cam_right) - cam_fwd * 0.25;
				a = pow(1.0 - f, 0.8);
				col = mix(hot, rich, f);
				cell = 27.0;
			}
		} else if (kind == 3) {
			float t = age - ARR;
			float life = 0.50 + 0.30 * h3;
			if (idx < 10 && t >= 0.0 && t < life) {
				float f = t / life;
				float ang = (fi + h1 * 0.9) / 10.0 * TAU;
				vec3 vel = (mx * sin(ang) + fwd * cos(ang)) * (1.0 + 1.6 * h2) + up * (3.2 + 3.0 * h1);
				vec3 at = origin + up * 0.4 + vel * t + up * (-4.5 * t * t);
				vec3 along = normalize(vel + up * (-9.0 * t) + vec3(0.0, 0.0001, 0.0));
				world = streak(at, along, c, 0.36 + 0.22 * h2, 0.18, cam_fwd, cam_right) - cam_fwd * 0.25;
				a = pow(1.0 - f, 0.8);
				col = mix(hot, rich, f);
				cell = 27.0;
			}
		} else if (kind == 4) {
			// Embers torn off the ground and drawn up into the dark sun.
			float cycle = 1.5 + 0.5 * h3;
			float ph = fract(age / cycle + h1);
			float ang = h2 * TAU + age * (0.8 + 1.4 * prog) + ph * 2.2;
			float rad = R * (2.6 - 2.4 * pow(ph, 0.8)) * (0.7 + 0.5 * h1);
			vec3 at = mix(origin + (mx * cos(ang) + fwd * sin(ang)) * rad + up * 0.15, sun, pow(ph, 1.6));
			vec3 was = mix(origin + (mx * cos(ang - 0.08) + fwd * sin(ang - 0.08)) * (rad + 0.1) + up * 0.15, sun, pow(max(ph - 0.03, 0.0), 1.6));
			vec3 along = normalize(at - was + vec3(0.0, 0.0001, 0.0));
			world = streak(at, along, c, 0.30 + 0.25 * h2, 0.15, cam_fwd, cam_right) - cam_fwd * 0.25;
			a = pow(sin(ph * PI), 0.8) * (0.25 + 0.75 * prog) * live;
			col = mix(red, ember_hot, ph * (0.4 + 0.4 * prog));
			cell = 27.0;
		} else if (kind == 5) {
			// Molten fragments thrown far across the field.
			float life = 1.0 + 0.6 * h3;
			if (age < life) {
				float f = age / life;
				float ang = (fi + h1 * 0.9) / 16.0 * TAU;
				vec3 vel = (mx * sin(ang) + fwd * cos(ang)) * (4.0 + 6.0 * h2) + up * (4.5 + 5.0 * h1);
				vec3 at = origin + up * 1.0 + vel * age + up * (-4.5 * age * age);
				vec3 now = vel + up * (-9.0 * age);
				vec3 along = normalize(now + vec3(0.0, 0.0001, 0.0));
				float len = (0.55 + 0.4 * h2) * clamp(length(now) * 0.12, 0.7, 1.9);
				world = streak(at, along, c, len, 0.24, cam_fwd, cam_right) - cam_fwd * 0.3;
				a = (at.y > 0.0 ? 1.0 : 0.0) * pow(1.0 - f, 0.7) * (0.8 + 0.2 * sin(vfx_time * 30.0 + h1 * 20.0));
				col = mix(ember_hot, mix(red, ember, h2), clamp(f * 1.4, 0.0, 1.0));
				cell = 27.0;
			}
		}
		alpha = a;
	} else if (part == 6) {
		float h1 = hash11(seed * 3.7 + fi);
		float h2 = hash11(seed * 5.3 + fi * 2.3);
		float h3 = hash11(seed * 9.1 + fi * 0.7);
		float a = 0.0;
		float s = 0.0;
		float rot = h1 * TAU;
		vec3 at = origin;
		bool placed = false;
		cell = 2.0;
		if (kind == 0) {
			// Motes rising inside the aegis for as long as it holds.
			float cycle = 1.5 + 0.6 * h3;
			float ph = fract(age / cycle + h1);
			float ang = h1 * TAU + age * 0.8 + fi;
			at = origin + (mx * cos(ang) + fwd * sin(ang)) * (0.42 + 0.55 * h2) + up * (0.2 + 2.3 * ph);
			s = 0.11 + 0.09 * h2;
			rot += ph * 3.0;
			a = pow(sin(ph * PI), 0.8) * aura * (0.7 + 0.3 * sin(vfx_time * 21.0 + h2 * 20.0));
			col = mix(rich, hot, 0.3 + 0.5 * h3);
		} else if (kind == 1) {
			if (idx < 8) {
				// Glitter riding the front of the victory wave.
				float f = clamp(age / 0.60, 0.0, 1.0);
				float ang = (fi + h1) / 8.0 * TAU;
				at = origin + (mx * cos(ang) + fwd * sin(ang)) * clear_wave(age, R) * (0.90 + 0.12 * h2) + up * (0.25 + 0.5 * h3);
				s = 0.20 + 0.12 * h2;
				rot += age * 4.0;
				a = smoothstep(0.02, 0.08, f) * pow(1.0 - f, 0.5) * (0.6 + 0.4 * sin(vfx_time * 34.0 + h1 * 25.0));
				col = mix(hot, rich, f);
			} else {
				float k = fi - 8.0;
				float t0 = 0.10 + 0.05 * k;
				float g = seg(t0, t0 + 0.55 + 0.20 * h1, age);
				if (age >= t0 && g < 1.0) {
					if (dist > 0.5) {
						// What is left of the boss flows to the crystal and mends it: comets
						// that leave its body dark violet and arrive as the crystal's own light.
						vec3 here = essence_path(g, h1, h2, h3, dist, origin, fwd);
						vec3 was = essence_path(max(g - 0.05, 0.0), h1, h2, h3, dist, origin, fwd);
						vec3 along = normalize(here - was + vec3(0.0, 0.00001, 0.0));
						world = streak(here, along, c, 1.0 + 0.5 * h2, 0.42, cam_fwd, cam_right) - cam_fwd * 0.3;
						placed = true;
						a = pow(sin(g * PI), 0.5);
						col = mix(vec3(0.80, 0.45, 1.0), crystal_hot, smoothstep(0.2, 0.9, g));
						cell = 20.0;
					} else {
						float ang = h2 * TAU + g * 4.0;
						at = origin + (mx * cos(ang) + fwd * sin(ang)) * mix(2.2, 0.25, g * g) + up * (0.2 + 1.5 * g);
						s = 0.17 + 0.10 * h2;
						a = pow(sin(g * PI), 0.6) * mend;
						col = mix(crystal, crystal_hot, g);
						rot += g * 6.0;
					}
				}
			}
			a *= clear_out;
		} else if (kind == 2) {
			// Sparks on the scan front.
			float ang = (fi + h1) / 16.0 * TAU;
			at = origin + (mx * cos(ang) + fwd * sin(ang)) * sweep_radius(age, R) * (0.97 + 0.05 * h2) + up * (0.2 + 0.35 * h3);
			s = 0.16 + 0.10 * h2;
			rot += age * 4.0;
			a = (1.0 - seg(ARR, ARR + 0.18, age)) * (0.55 + 0.45 * sin(vfx_time * 31.0 + h1 * 25.0));
			col = mix(hot, rich, 0.4);
		} else if (kind == 3) {
			// Embers climbing the beacon.
			float t = age - ARR;
			float ph = fract(age / (1.2 + 0.5 * h3) + h1);
			float ang = h2 * TAU + age * 1.6;
			at = origin + (mx * cos(ang) + fwd * sin(ang)) * (0.16 + 0.22 * h2) + up * (0.2 + 4.8 * ph) - cam_fwd * 0.2;
			s = 0.12 + 0.08 * h2;
			a = pow(sin(ph * PI), 0.8) * (t < 0.0 ? 0.8 : 1.0 - smoothstep(0.6, 1.9, t));
			col = mix(rich, hot, 0.3 + 0.5 * h3);
		} else if (kind == 4) {
			// Sparks circling the dark sun.
			float grow = 1.3 + 2.2 * prog;
			float ang = h1 * TAU + age * (1.4 + 2.0 * prog) * (h2 < 0.5 ? -1.0 : 1.0);
			at = sun + (cam_right * cos(ang) + cam_up * sin(ang)) * grow * (0.56 + 0.10 * h3);
			s = 0.12 + 0.10 * h2 + 0.06 * prog;
			a = (0.3 + 0.7 * prog) * (0.5 + 0.5 * sin(vfx_time * 23.0 + h2 * 20.0)) * live * smoothstep(0.0, 0.5, age);
			col = mix(red, ember_hot, h3);
		} else if (kind == 5) {
			// Embers raining back down over the ground the boss claimed.
			float t = age - 0.10 - 0.5 * h3;
			float life = 1.6 + 1.0 * h2;
			if (t >= 0.0 && t < life) {
				float g = t / life;
				vec3 spread = (mx * (h1 - 0.5) + fwd * (h2 - 0.5)) * 2.0 * R * 3.2;
				at = origin + spread + up * (0.3 + (1.6 + 2.0 * h1) * sin(g * PI * 0.85))
					+ mx * sin(g * 6.0 + h1 * 6.0) * 0.15;
				s = (0.14 + 0.12 * h2) * (1.0 - g * 0.4);
				rot += g * 3.0;
				a = pow(sin(g * PI), 0.7) * (0.7 + 0.3 * sin(vfx_time * 25.0 + h1 * 30.0));
				col = mix(ember_hot, mix(red, ember, h1), g);
				cell = 14.0;
			}
		}
		if (placed) {
			alpha = a;
		} else {
			vec2 rr = rot2(c, rot);
			world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
			alpha = a * (s > 0.001 ? 1.0 : 0.0);
		}
	} else if (part == 7) {
		float a = 0.0;
		if (kind == 1) {
			// Halos rising up the crystal as it mends (glow over their mix bodies).
			if (idx < 3) {
				float f = seg(MEND_HALO + 0.20 * fi, MEND_HALO + 0.58 + 0.20 * fi, age);
				float s = mix(1.20, 0.78, f);
				world = origin + up * mix(0.35, 2.35, ease_out(f)) + (mx * c.x + fwd * c.y) * 2.0 * s;
				a = 0.70 * mend * pow(sin(f * PI), 0.7) * clear_out;
				col = crystal_hot;
				cell = 3.0;
			}
		}
		alpha = a;
	} else {
		float h1 = hash11(seed * 17.0 + fi);
		float h2 = hash11(seed * 23.0 + fi * 1.3);
		float a = 0.0;
		float window = 0.0;
		float strength = 0.0;
		float reach = 1.0;
		if (kind == 4) {
			window = (0.25 + 0.75 * prog) * live;
			strength = 0.5 + 0.5 * prog;
			reach = 2.0;
		} else if (kind == 5) {
			window = age < 1.3 ? 1.0 : 0.0;
			strength = 1.0 - clamp(age / 1.3, 0.0, 1.0);
			reach = 3.0;
		}
		if (window > 0.0) {
			float slot = floor(vfx_time * 18.0 + h1 * 10.0);
			float on = step(1.0 - 0.38 * window, hash11(slot * 0.731 + fi * 3.1 + seed));
			float ang = h2 * TAU + slot * 1.7;
			vec3 at = origin + (mx * cos(ang) + fwd * sin(ang)) * R * (0.5 + reach * hash11(slot + h2));
			float hgt = 1.5 + 2.2 * hash11(slot * 1.3 + h1);
			world = at + up * (c.y + 0.5) * hgt + pillar_side * c.x * (0.6 + 0.4 * h1) - cam_fwd * 0.2;
			a = on * strength;
			col = mix(mix(red, ember, 0.6), vec3(1.0), 0.5);
			cell = 7.0;
		}
		alpha = a;
	}
	// A part that is not showing collapses to a point: no fill cost for the large quads.
	if (alpha <= 0.0005) world = origin;
	v_tint = vec4(col, alpha);
	v_cell = cell;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	vec3 rgb = v_tint.rgb;
	if (v_cell < -0.5) {
		float d = length(v_plane);
		float r = v_ring.x;
		float w = max(v_ring.y, 0.004);
		if (v_arc.x >= 0.0) {
			// Timer ring: light on the part still to run and a hot head where it burns down.
			float band = exp(-pow((d - r) / w, 2.0));
			float head = timer_head(v_plane, v_arc.x) * exp(-pow((d - r) / (w * 2.4), 2.0));
			a = band * 0.75 * timer_left(v_plane, v_arc.x, v_arc.y) + head;
			rgb = mix(v_tint.rgb, vec3(1.0), clamp(head, 0.0, 1.0) * 0.7);
		} else {
			// Shock ring: a hard edge on the side it travels toward, a soft wake behind it,
			// and an optional fill in the wake colour.
			float sharp = w * 0.30;
			float soft = w * 1.5;
			float lead;
			float wake = 0.0;
			if (v_ring.w > 0.0) {
				lead = (1.0 - smoothstep(r, r + sharp, d)) * smoothstep(r - soft, r, d);
				wake = (1.0 - smoothstep(r * 0.55, r, d)) * v_ring.z;
			} else {
				lead = smoothstep(r - sharp, r, d) * (1.0 - smoothstep(r, r + soft, d));
			}
			a = (lead + wake) * (1.0 - smoothstep(0.92, 1.0, d));
			rgb = (lead * v_tint.rgb + wake * v_wake) / max(lead + wake, 0.001);
		}
	} else if (v_cell < 15.5) {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	} else {
		a = texture(skill_sprites, cell_uv(int(v_cell + 0.5) - 16, UV)).a;
	}
	ALBEDO = mix(rgb, rgb * rgb * 1.25, vfx_wash * 0.5);
	ALPHA = clamp(a, 0.0, 1.0) * v_tint.a * mix(1.0, 0.72, vfx_wash);
}
