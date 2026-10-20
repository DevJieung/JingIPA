shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Additive layer of the big one-shot sequences: the Starlight Burst guardian skill, the
// boss gate (four-second warning gather, arrival burst), the frost pulse and the level-up
// flare. One MultiMesh instance plays a whole sequence; every part reads its own window of
// the instance's age, so the anticipation, impact, shockwave, fragments and afterglow are
// one draw call and one budget slot.
//   transform: origin on the ground, -Z = a deterministic yaw (variety only)
//   COLOR:     main colour (gold for the blast, crimson for the boss gate, ice for the
//              frost pulse, gold for the level-up)
//   CUSTOM:    x birth (vfx seconds, epoch relative)  y radius R (world units; the blast's
//              actual damage radius, the boss footprint, the frost pulse's reach, the altar)
//              z duration (boss warning seconds; unused otherwise)  w kind
// Kinds: 0 blast  1 boss_warning  2 boss_burst  3 freeze  4 levelup  5 elite_burst  6 hero_arrive
// Parts (UV2.x): 0 ground shock ring  1 ground sigil  2 flash  3 flare  4 light pillar
//   5 comet tail (strip)  6 comet head  7 sparks x16  8 embers x12  9 ground afterglow
//   10 sky flare  11 lightning x4  12 facing ring  13 crack glow  14 trail embers x10
// Blast (2026-10-17, a meteor): the star is born far up the screen at the cast and falls
// for HIT seconds along a steep line, accelerating: a hot head with a long two-tone tail,
// embers and smoke shed along the way (the smoke is in vfx_skill_mix). At HIT: the impact
// flash, an eight-ray flare, a light pillar, a facing shockwave, the ground ring to R
// (HIT+0.30, lingering to HIT+0.80), fragments, embers, afterglow and cracks. The
// simulator's damage is at 0; the lock-on sigil at 0 marks the struck area while the
// star is still in the air.
// Freeze (kind 3): an ice wave from the crystal to R (0.95 s, the same curve as the old
// ring), crystal spikes erupting along the wavefront where it passes them, a cold flash
// and column at the crystal, snowflakes drifting down behind the wave, a cold wash.
// Level-up (kind 4): a star rises from the crystal for 0.45 s and bursts gold-white:
// flash, flare, a facing ring, a fountain of sparks and sparkles, a soft column. ~1.2 s.
// Elite entrance (kind 5, 2026-10-19): the boss arrival in miniature and in the elite's
// violet. The shader runs the kind 2 timeline with `bk` = R / 1.5 on its absolute sizes
// (flash, flare, pillar, sparks, lightning), so a 0.95 R elite gate is about 0.63 of a
// boss gate, and swaps the crimson for violet.
// Hero arrival (kind 6, 2026-10-19): the five-star guardian a revival grants. CUSTOM.z is
// the mode: 1 on the field (a gold star falls from the sky onto the hero's spot for ARRIVE
// seconds as the hero drops in, then the landing: flash, flare, a column, a ground ring,
// five big stars thrown up into a crown and sparkles), 2 on the bench (no spot to land on:
// the star climbs out of the crystal and its aegis, bursts just over the dome and its five
// stars fly down into a ring round the dome's foot and circle it for a moment — low and
// outside the dome, so the crown belongs to the crystal, is not lost in the dome's gold and
// never hangs over the guardian standing behind it).
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D zone_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue (the mix layer carries the body).
uniform float vfx_wash = 0.0;
uniform float vfx_epoch = 0.0;

const float HIT = 0.32;        // StellarVfx.BLAST_FALL
const float FREEZE_SEC = 0.95; // the ice wave's travel time
const float RISE = 0.45;       // level-up: the star rises for this long, then bursts
const float ARRIVE = 0.28;     // hero arrival: the star's fall (NativeCharacterModel spawn landing)

varying vec4 v_tint;
varying vec3 v_wake;     // ring: colour of the wake / fill (the lead edge uses v_tint)
varying float v_cell;    // -1 procedural ring, 0..15 battle atlas, 16..31 skill, 32..47 zone
varying vec2 v_plane;
varying vec4 v_ring;     // r, width (fractions of the quad), fill, unused

// Radius of the frost pulse's wave `t` seconds after the cast.
float freeze_wave(float t, float R) {
	return mix(0.4, R, ease_out3(t / FREEZE_SEC));
}

// Seconds the frost wave needs to reach radius r.
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
	vec3 pillar_side = normalize(cross(up, cam_fwd));
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	float birth = INSTANCE_CUSTOM.x;
	float R = max(INSTANCE_CUSTOM.y, 0.2);
	float dur = max(INSTANCE_CUSTOM.z, 0.5);
	int kind = int(INSTANCE_CUSTOM.w + 0.5);
	// Elite entrance: the boss arrival's timeline, smaller (bk) and violet.
	bool elite = kind == 5;
	if (elite) kind = 2;
	float bk = elite ? clamp(R / 1.5, 0.35, 1.0) : 1.0;
	float mode = INSTANCE_CUSTOM.z;              // hero arrival: 1 field, 2 bench
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
	vec3 red = elite ? vec3(0.62, 0.22, 1.0) : vec3(1.0, 0.16, 0.26);
	vec3 violet = elite ? vec3(0.80, 0.52, 1.0) : vec3(0.58, 0.28, 1.0);
	vec3 boss_hot = elite ? vec3(0.96, 0.90, 1.0) : vec3(1.0, 0.80, 0.90);
	vec3 ice = vec3(0.62, 0.90, 1.0);
	vec3 ice_hot = vec3(0.95, 0.99, 1.0);
	vec3 ice_deep = vec3(0.30, 0.60, 1.0);
	// The meteor: born far up the screen (up and away from the camera) and to one side, it
	// falls on a steep line to the ground point, accelerating (ease-in squared).
	vec3 sky = origin + up * 8.4 + away * 2.8 + mx * 1.5;
	vec3 target = origin + up * 0.12;
	vec3 fall_dir = normalize(target - sky);
	float fall = clamp(age / HIT, 0.0, 1.0);
	float fall_s = fall * fall;
	vec3 head_at = mix(sky, target, fall_s);
	vec3 fall_side = normalize(cross(fall_dir, cam_fwd));
	// The level-up star: it climbs out of the crystal's tip and bursts at RISE.
	float rise = clamp(age / RISE, 0.0, 1.0);
	vec3 star_at = origin + up * mix(2.0, 4.2, ease_out3(rise));
	vec3 burst_at = origin + up * 4.2;
	float since = age - RISE;
	// Hero arrival: the star falls from up and a little beyond the spot; on the bench it rises
	// from the crystal's tip like the level-up star, only lower.
	vec3 drop_from = origin + up * 6.2 + away * 1.2 + mx * 0.6;
	float drop_f = clamp(age / ARRIVE, 0.0, 1.0);
	vec3 drop_at = mix(drop_from, origin + up * 0.35, drop_f * drop_f);
	vec3 drop_dir = normalize(origin - drop_from);
	float landed = age - ARRIVE;                   // field: seconds since the landing
	// Bench: the burst sits just over the revival's aegis dome (StellarVfx AEGIS_HEIGHT 2.55,
	// up for the whole arrival). The default posts are 2.2 u out: a crown hanging at 3.3 (the
	// first cut) sat on the head of the guardian behind the crystal, and one inside the dome
	// (the second) was lost in its gold — the five stars now circle the dome's foot (ring).
	vec3 crown_at = origin + up * 2.8;
	vec3 bench_star = origin + up * mix(1.4, 2.8, ease_out3(clamp(age / RISE, 0.0, 1.0)));
	float field = mode < 1.5 ? 1.0 : 0.0;
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
		} else if (kind == 2) {
			float f = clamp(age / 0.55, 0.0, 1.0);
			r = mix(0.2, R * 2.8, ease_out3(f));
			w = mix(0.75, 0.35, f) * bk;
			a = pow(1.0 - f, 1.1);
			fill = 0.45 * pow(1.0 - clamp(age / 0.3, 0.0, 1.0), 1.4);
			col = mix(boss_hot, violet, 0.2);
			v_wake = mix(red, violet, 0.5);
			rmax = R * 3.0 + 0.8 * bk;
		} else if (kind == 6) {
			if (field > 0.5) {
				if (landed < 0.0) {
					// It is coming here: a ring tightening on the spot while the star falls.
					float f = drop_f;
					r = mix(R * 1.7, R, ease_out(f));
					w = 0.16;
					a = 0.25 + 0.55 * f;
					col = mix(gold, hot, f);
					v_wake = gold;
				} else {
					float f = clamp(landed / 0.45, 0.0, 1.0);
					r = mix(0.2, R * 2.3, ease_out3(f));
					w = mix(0.55, 0.22, f);
					a = pow(1.0 - f, 1.2);
					fill = 0.5 * pow(1.0 - clamp(landed / 0.25, 0.0, 1.0), 1.4);
					col = mix(vec3(1.0), hot, 0.4 + 0.6 * f);
					v_wake = gold;
				}
			}
			rmax = R * 2.4 + 0.6;
		} else if (kind == 3) {
			// The ice wave: crisp white lead, a wide cold wake that lingers.
			float f = clamp(age / FREEZE_SEC, 0.0, 1.0);
			r = freeze_wave(age, R);
			w = mix(1.1, 0.7, f);
			a = pow(1.0 - f, 0.8) * 0.9 + 0.1 * (1.0 - clamp((age - FREEZE_SEC) / 0.4, 0.0, 1.0));
			fill = 0.2 * pow(1.0 - f, 1.2);
			col = mix(ice_hot, ice, f * 0.5);
			v_wake = mix(ice, ice_deep, 0.5);
			rmax = R + 1.5;
		} else {
			// Level-up: a gold ring runs out over the altar at the burst.
			if (since >= 0.0) {
				float f = clamp(since / 0.42, 0.0, 1.0);
				r = mix(0.25, R * 1.6, ease_out3(f));
				w = mix(0.3, 0.18, f);
				a = pow(1.0 - f, 1.3);
				fill = 0.25 * pow(1.0 - clamp(since / 0.25, 0.0, 1.0), 1.4);
				col = mix(vec3(1.0), hot, 0.5);
				v_wake = gold;
			}
			rmax = R * 1.7 + 0.4;
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
		} else if (kind == 2) {
			float f = clamp(age / 0.6, 0.0, 1.0);
			s = R * mix(1.05, 1.7, ease_out3(f));
			rot = seed * 6.283 + age * 1.5;
			a = pow(1.0 - f, 1.4);
			col = mix(boss_hot, violet, f);
			cell = 24.0;
		} else if (kind == 3) {
			// A frost pane under the crystal, cracking outward as the wave leaves.
			float f = clamp(age / 1.3, 0.0, 1.0);
			s = 2.4 * (0.6 + 0.4 * ease_out3(age / 0.3));
			rot = seed * 6.283;
			a = 0.8 * pow(1.0 - f, 1.2);
			col = mix(ice, ice_hot, 0.4);
			cell = 41.0;
		}
		vec2 rr = rot2(c, rot);
		world = origin + up * 0.10 + (mx * rr.x + fwd * rr.y) * 2.0 * s;
		alpha = a * (s > 0.001 ? 1.0 : 0.0);
		if (a <= 0.0) world = origin;
	} else if (part == 2) {
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin + up * 0.6;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.14, 0.0, 1.0);
				s = 2.4 + 1.8 * ease_out(f);
				a = pow(1.0 - f, 1.5);
				col = hot;
			}
		} else if (kind == 2) {
			float f = clamp(age / 0.22, 0.0, 1.0);
			s = (3.0 + 2.5 * ease_out(f)) * bk;
			a = pow(1.0 - f, 1.3);
			col = mix(boss_hot, violet, 0.3);
			at = origin + up * 1.3 * bk;
		} else if (kind == 6) {
			float t = field > 0.5 ? landed : since;
			if (t >= 0.0) {
				float f = clamp(t / 0.15, 0.0, 1.0);
				s = (field > 0.5 ? 1.8 : 1.5) + 1.5 * ease_out(f);
				a = pow(1.0 - f, 1.4);
				col = mix(vec3(1.0), hot, 0.4);
				at = field > 0.5 ? origin + up * 0.7 : crown_at;
			}
		} else if (kind == 1) {
			// A dim strobe at the gate's heart during the last second.
			float late = clamp((age - (dur - 1.0)) / 1.0, 0.0, 1.0);
			float fl = step(0.6, hash11(floor(age * 24.0) + seed * 7.0));
			s = 0.9 + 1.5 * late;
			a = 0.35 * late * fl * live;
			col = mix(red, violet, 0.5);
		} else if (kind == 3) {
			float f = clamp(age / 0.18, 0.0, 1.0);
			s = 2.2 + 1.6 * ease_out(f);
			a = pow(1.0 - f, 1.4);
			col = ice_hot;
			at = origin + up * 1.4;
		} else {
			if (since >= 0.0) {
				float f = clamp(since / 0.16, 0.0, 1.0);
				s = 1.9 + 1.5 * ease_out(f);
				a = pow(1.0 - f, 1.4);
				col = mix(vec3(1.0), hot, 0.4);
				at = burst_at;
			}
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
				s = 1.2 + 5.0 * ease_out3(f);
				rot += f * 0.5;
				a = pow(1.0 - f, 1.6);
				col = mix(hot, gold, 0.35 + 0.5 * f);
			}
		} else if (kind == 2) {
			float f = clamp(age / 0.5, 0.0, 1.0);
			s = (1.5 + 6.0 * ease_out3(f)) * bk;
			rot -= f * 0.6;
			a = pow(1.0 - f, 1.5);
			col = mix(boss_hot, violet, 0.25 + f * 0.65);
			at = origin + up * 1.3 * bk;
		} else if (kind == 6) {
			float t = field > 0.5 ? landed : since;
			if (t >= 0.0) {
				float f = clamp(t / 0.42, 0.0, 1.0);
				s = 1.0 + (field > 0.5 ? 3.6 : 2.8) * ease_out3(f);
				rot += f * 0.5;
				a = pow(1.0 - f, 1.5);
				col = mix(hot, gold, 0.3 + 0.5 * f);
				at = field > 0.5 ? origin + up * 0.6 : crown_at;
			}
		} else if (kind == 3) {
			float f = clamp(age / 0.45, 0.0, 1.0);
			s = 1.5 + 5.0 * ease_out3(f);
			rot -= f * 0.4;
			a = pow(1.0 - f, 1.5);
			col = mix(ice_hot, ice, 0.3 + 0.5 * f);
			at = origin + up * 1.4;
		} else if (kind == 4) {
			if (since >= 0.0) {
				float f = clamp(since / 0.40, 0.0, 1.0);
				s = 1.4 + 3.6 * ease_out3(f);
				rot += f * 0.4;
				a = pow(1.0 - f, 1.5);
				col = mix(hot, gold, 0.3 + 0.5 * f);
				at = burst_at;
			}
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
		vec3 foot = origin;
		if (kind == 0) {
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.5, 0.0, 1.0);
				h = 5.5 * ease_out3(clamp(t / 0.10, 0.0, 1.0)) * (1.0 - 0.15 * f);
				w = mix(1.1, 0.4, ease_out(f));
				a = pow(1.0 - f, 1.3);
				col = mix(hot, gold, 0.3 + 0.5 * f);
			}
		} else if (kind == 2) {
			float f = clamp(age / 0.7, 0.0, 1.0);
			h = 7.5 * bk * ease_out3(clamp(age / 0.12, 0.0, 1.0));
			w = mix(2.0, 0.7, ease_out(f)) * bk;
			a = pow(1.0 - f, 1.2);
			col = mix(boss_hot, mix(red, violet, 0.6), f * 0.8);
			push = R;
		} else if (kind == 6) {
			if (field > 0.5 && landed >= 0.0) {
				// The column the guardian stands in for a moment after landing.
				float f = clamp(landed / 0.6, 0.0, 1.0);
				h = 4.6 * ease_out3(clamp(landed / 0.10, 0.0, 1.0)) * (1.0 - 0.15 * f);
				w = mix(1.5, 0.45, ease_out(f));
				a = 0.9 * pow(1.0 - f, 1.3);
				col = mix(hot, gold, 0.3 + 0.5 * f);
				push = 0.7;
			}
		} else if (kind == 1) {
			// A thin, flickering beacon climbing out of the gate over the warning.
			float flick = 0.7 + 0.3 * sin(age * 23.0 + seed * 9.0) * sin(age * 7.3);
			h = 6.5 * ease_out(prog);
			w = 0.35 + 0.35 * prog;
			a = (0.15 + 0.45 * prog) * flick * live;
			col = mix(violet, red, 0.3);
			push = R;
		} else if (kind == 3) {
			float f = clamp(age / 0.55, 0.0, 1.0);
			h = 5.0 * ease_out3(clamp(age / 0.10, 0.0, 1.0)) * (1.0 - 0.2 * f);
			w = mix(1.4, 0.5, ease_out(f));
			a = pow(1.0 - f, 1.3);
			col = mix(ice_hot, ice, 0.3 + 0.5 * f);
			push = 1.2;
		} else {
			if (since >= 0.0) {
				float f = clamp(since / 0.55, 0.0, 1.0);
				h = 4.6 * ease_out3(clamp(since / 0.12, 0.0, 1.0)) * (1.0 - 0.1 * f);
				w = mix(1.3, 0.5, ease_out(f));
				a = 0.9 * pow(1.0 - f, 1.3);
				col = mix(hot, gold, 0.4 + 0.4 * f);
				push = 1.2;
			}
		}
		world = foot + up * (c.y + 0.5) * h + pillar_side * c.x * w - cam_fwd * push;
		alpha = a * (h > 0.001 ? 1.0 : 0.0);
		cell = 17.0;
	} else if (part == 5) {
		float a = 0.0;
		if (kind == 0) {
			// The meteor's tail: long, two-tone (hot near the head, ember-orange behind), a
			// little wider as it speeds up; it burns out in the frames after the impact.
			float along = VERTEX.y;
			float len = 4.0 + 7.5 * fall_s;
			float w = (0.9 + 0.5 * fall_s) * (1.0 - along * 0.75);
			world = head_at - fall_dir * along * len + fall_side * c.x * w;
			float post = clamp((age - HIT) / 0.10, 0.0, 1.0);
			a = (0.7 + 0.3 * fall_s) * (1.0 - post) * smoothstep(0.0, 0.03, age);
			col = mix(hot, deep, along * 0.9);
		} else if (kind == 6 && field > 0.5 && landed < 0.06) {
			// The falling star's tail: gold, shorter and finer than the meteor's.
			float along = VERTEX.y;
			float len = 2.0 + 3.2 * drop_f;
			float w = 0.62 * (1.0 - along * 0.8);
			vec3 side = normalize(cross(drop_dir, cam_fwd));
			world = drop_at - drop_dir * along * len + side * c.x * w - cam_fwd * 0.3;
			a = 0.85 * smoothstep(0.0, 0.04, age) * (1.0 - clamp(landed / 0.06, 0.0, 1.0));
			col = mix(hot, gold, along);
		} else if (kind == 6 && field < 0.5 && since < 0.08) {
			// The bench star's short tail as it climbs out of the crystal.
			float along = VERTEX.y;
			float len = 0.8 * clamp(age / RISE, 0.0, 1.0);
			float w = 0.26 * (1.0 - along * 0.8);
			world = bench_star - up * along * len + cam_right * c.x * w - cam_fwd * 0.3;
			a = 0.8 * smoothstep(0.0, 0.08, age) * (1.0 - clamp(since / 0.08, 0.0, 1.0));
			col = mix(hot, gold, along);
		} else if (kind == 4 && since < 0.08) {
			// The rising star's short tail.
			float along = VERTEX.y;
			float len = 0.9 * rise;
			float w = 0.28 * (1.0 - along * 0.8);
			world = star_at - up * along * len + cam_right * c.x * w - cam_fwd * 0.3;
			a = 0.8 * smoothstep(0.0, 0.08, age) * (1.0 - clamp(since / 0.08, 0.0, 1.0));
			col = mix(hot, gold, along);
		}
		alpha = a;
		cell = 20.0;
		if (a <= 0.0) world = origin;
	} else if (part == 6) {
		float a = 0.0;
		if (kind == 0) {
			// The meteor's head: a hot core turned so its flare trails the fall.
			float size = 2.1 + 1.2 * fall_s;
			vec3 along = fall_dir - cam_fwd * dot(fall_dir, cam_fwd);
			along = length(along) < 0.02 ? -cam_up : normalize(along);
			vec3 side = normalize(cross(along, cam_fwd));
			// The cell's tail points to -y: put -y along the fall direction's reverse.
			world = head_at + along * (-c.y) * size * 1.1 + side * c.x * size - cam_fwd * 0.3;
			float post = clamp((age - HIT) / 0.06, 0.0, 1.0);
			a = (1.0 - post) * smoothstep(0.0, 0.03, age);
			col = mix(vec3(1.0), hot, 0.35);
			cell = 38.0;
		} else if (kind == 6) {
			// The guardian's star: falling onto its spot, or rising from the crystal.
			float t = field > 0.5 ? landed : since;
			float f = clamp(t / 0.08, 0.0, 1.0);
			float size = (field > 0.5 ? 1.35 + 0.45 * drop_f : 0.85 + 0.4 * clamp(age / RISE, 0.0, 1.0)) * (1.0 - f);
			vec2 rr = rot2(c, seed * 6.283 + age * 4.0);
			world = (field > 0.5 ? drop_at : bench_star) + (cam_right * rr.x + cam_up * rr.y) * size - cam_fwd * 0.3;
			a = smoothstep(0.0, 0.05, age) * (1.0 - f);
			col = mix(vec3(1.0), hot, 0.3);
			cell = 1.0;
		} else if (kind == 4) {
			// The rising star.
			float f = clamp(since / 0.1, 0.0, 1.0);
			float size = mix(0.8, 1.15, rise) * (1.0 - f);
			vec2 rr = rot2(c, seed * 6.283 + age * 3.0);
			world = star_at + (cam_right * rr.x + cam_up * rr.y) * size - cam_fwd * 0.3;
			a = smoothstep(0.0, 0.06, age) * (1.0 - f);
			col = mix(vec3(1.0), hot, 0.3);
			cell = 1.0;
		}
		alpha = a;
		if (a <= 0.0) world = origin;
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
		} else if (kind == 2) {
			float life = 0.7 + 0.5 * h3;
			if (age < life) {
				float f = age / life;
				float ang = (float(idx) + h1 * 0.9) / 16.0 * 6.283;
				vec3 radial = mx * sin(ang) + fwd * cos(ang);
				vec3 vel = (radial * (2.5 + 3.5 * h2) + up * (3.0 + 4.0 * h1)) * bk;
				float g = 7.0 * bk;
				vec3 at = origin + up * 0.8 * bk + vel * age + up * (-0.5 * g * age * age);
				vec3 now = vel + up * (-g * age);
				vec3 along = normalize(now + vec3(0.0, 0.0001, 0.0));
				vec3 side = cross(along, cam_fwd);
				side = length(side) < 0.02 ? cam_right : normalize(side);
				float len = (0.35 + 0.3 * h2) * bk;
				world = at + along * c.y * len + side * c.x * 0.16 * bk - cam_fwd * 0.25;
				a = (1.0 - f) * (0.75 + 0.25 * sin(vfx_time * 30.0 + h1 * 20.0));
				col = mix(boss_hot, mix(red, violet, h2), clamp(f * 1.5, 0.0, 1.0));
				cell = 27.0;
			}
		} else if (kind == 3) {
			// Crystal spikes: each stands at its own radius and erupts when the wave passes
			// it (overshoot), holds, then sinks and fades.
			float rad = R * (0.16 + 0.80 * h1);
			float ang = (float(idx) + h2 * 0.9) / 16.0 * 6.283 + seed * 6.283;
			float born = freeze_arrival(rad, R);
			float t = age - born;
			float life = 0.95 + 0.4 * h3;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				float hgt = (1.1 + 0.9 * h2) * overshoot(t / 0.14) * (1.0 - smoothstep(0.6, 1.0, f));
				float wid = 0.65 + 0.3 * h3;
				vec3 foot = origin + (mx * cos(ang) + fwd * sin(ang)) * rad;
				world = foot + up * (c.y + 0.5) * hgt + pillar_side * c.x * wid - cam_fwd * 0.35;
				a = (1.0 - smoothstep(0.7, 1.0, f)) * 0.95;
				col = mix(ice_hot, ice, 0.3 + 0.4 * f);
				cell = (idx % 2 == 0) ? 33.0 : 40.0;
			}
		} else if (kind == 6) {
			float t = field > 0.5 ? landed : since;
			vec3 from = field > 0.5 ? origin + up * 0.5 : crown_at;
			if (idx < 5) {
				// Five big stars: the guardian's grade. Thrown up and out into a crown on the
				// field; on the bench they fly into a ring round the aegis dome and circle it
				// (vfx_skill_mix part 23 lays the same path under them).
				float life = field > 0.5 ? 1.05 : 1.55;
				if (t >= 0.0 && t < life) {
					float f = t / life;
					float ang = (float(idx) - 2.0) * 0.52;
					vec3 out_dir = cam_right * sin(ang) + cam_up * cos(ang);
					float reach = field > 0.5 ? 1.35 + 0.25 * ease_out3(f) : 1.25;
					vec3 lift = field > 0.5 ? up * (0.9 + 0.5 * ease_out(f)) : vec3(0.0);
					vec3 at = from + lift + out_dir * reach * ease_out3(clamp(t / 0.22, 0.0, 1.0));
					float big = 0.92;
					if (field < 0.5) {
						float ca = float(idx) * 1.2566 + t * 1.7 + seed * 6.283;
						vec3 ring = (mx * cos(ca) + fwd * sin(ca)) * 1.5 + up * (0.75 + 0.10 * sin(t * 4.0 + float(idx) * 1.7));
						at = mix(from, origin + ring, ease_out3(clamp(t / 0.30, 0.0, 1.0)));
						big = 1.0;
					}
					float pulse = 1.0 + 0.25 * overshoot(clamp(t / 0.25, 0.0, 1.0)) - 0.25;
					float size = big * pulse * (1.0 - smoothstep(0.75, 1.0, f));
					vec2 rr = rot2(c, seed * 2.0 + float(idx) * 1.3 + t * 2.0);
					world = at + (cam_right * rr.x + cam_up * rr.y) * size - cam_fwd * 0.5;
					a = (0.85 + 0.15 * sin(vfx_time * 23.0 + float(idx) * 2.0)) * (1.0 - smoothstep(0.80, 1.0, f));
					col = mix(vec3(1.0), hot, 0.35);
					cell = 1.0;
				}
			} else {
				float life = 0.5 + 0.35 * h3;
				if (t >= 0.0 && t < life) {
					float f = t / life;
					float ang = (float(idx) + h1 * 0.9) / 11.0 * 6.283;
					vec3 radial = mx * sin(ang) + fwd * cos(ang);
					vec3 vel = radial * (1.4 + 2.2 * h2) + up * (2.0 + 2.8 * h1);
					float g = 7.0;
					vec3 at = from + vel * t + up * (-0.5 * g * t * t);
					vec3 now = vel + up * (-g * t);
					vec3 along = normalize(now + vec3(0.0, 0.0001, 0.0));
					vec3 side = cross(along, cam_fwd);
					side = length(side) < 0.02 ? cam_right : normalize(side);
					float len = (0.45 + 0.35 * h2) * clamp(length(now) * 0.2, 0.5, 1.4);
					world = at + along * c.y * len + side * c.x * 0.2 - cam_fwd * 0.3;
					a = pow(1.0 - f, 0.8) * (0.8 + 0.2 * sin(vfx_time * 40.0 + h1 * 20.0));
					col = mix(mix(vec3(1.0), hot, 0.4), gold, clamp(f * 1.2, 0.0, 1.0));
					cell = 27.0;
				}
			}
		} else {
			// Level-up: a fountain of gold sparks from the burst point.
			float t = since;
			float life = 0.5 + 0.35 * h3;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				float ang = (float(idx) + h1 * 0.9) / 16.0 * 6.283;
				vec3 radial = mx * sin(ang) + fwd * cos(ang);
				vec3 vel = radial * (1.2 + 2.0 * h2) + up * (1.5 + 2.5 * h1);
				float g = 7.0;
				vec3 at = burst_at + vel * t + up * (-0.5 * g * t * t);
				vec3 now = vel + up * (-g * t);
				vec3 along = normalize(now + vec3(0.0, 0.0001, 0.0));
				vec3 side = cross(along, cam_fwd);
				side = length(side) < 0.02 ? cam_right : normalize(side);
				float len = (0.5 + 0.35 * h2) * clamp(length(now) * 0.2, 0.5, 1.4);
				world = at + along * c.y * len + side * c.x * 0.22 - cam_fwd * 0.3;
				a = pow(1.0 - f, 0.8) * (0.8 + 0.2 * sin(vfx_time * 40.0 + h1 * 20.0));
				col = mix(mix(vec3(1.0), hot, 0.4), gold, clamp(f * 1.2, 0.0, 1.0));
				cell = (idx % 3 == 0) ? 1.0 : 27.0;
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
		} else if (kind == 2) {
			float t = age - 0.05 - h3 * 0.25;
			float life = 1.0 + 0.5 * h2;
			if (t >= 0.0 && t < life) {
				float g = t / life;
				vec3 spread = (mx * (h1 - 0.5) + fwd * (h2 - 0.5)) * 2.0 * R * 1.3;
				vec3 at = origin + spread + up * (0.3 + (1.5 + 1.5 * h1) * ease_out(g)) * bk;
				s = (0.12 + 0.12 * h2) * (1.0 - g * 0.4) * mix(1.0, bk, 0.5);
				vec2 rr = rot2(c, h1 * 6.283 + g * 3.0);
				world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
				a = pow(sin(g * 3.14159), 0.7);
				col = mix(boss_hot, mix(red, violet, h1), g);
				cell = 2.0;
			}
		} else if (kind == 3) {
			// Snowflakes drifting down behind the wave, across the field.
			float rad = R * (0.1 + 0.85 * h1);
			float ang = h2 * 6.283 + float(idx) * 0.5;
			float t = age - freeze_arrival(rad, R) - 0.05;
			float life = 1.1 + 0.5 * h3;
			if (t >= 0.0 && t < life) {
				float g = t / life;
				vec3 at = origin + (mx * cos(ang) + fwd * sin(ang)) * rad + up * (2.6 - 2.2 * g)
					+ mx * sin(g * 5.0 + h1 * 6.0) * 0.25;
				s = 0.16 + 0.12 * h2;
				vec2 rr = rot2(c, h1 * 6.283 + g * 2.0);
				world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
				a = pow(sin(g * 3.14159), 0.6) * 0.9;
				col = mix(ice_hot, ice, g);
				cell = 34.0;
			}
		} else if (kind == 6) {
			// Sparkles settling over the guardian (or round the crystal on the bench).
			float t = (field > 0.5 ? landed : since) - 0.06 - h3 * 0.25;
			float life = 0.8 + 0.5 * h2;
			if (t >= 0.0 && t < life) {
				float g = t / life;
				vec3 spread = (mx * (h1 - 0.5) + fwd * (h2 - 0.5)) * 2.6;
				vec3 top = field > 0.5 ? origin + up * 2.2 : crown_at;
				vec3 at = top + spread * ease_out(g) + up * (0.3 - (field > 0.5 ? 2.0 : 1.6) * g * g) + mx * sin(g * 6.0 + h1 * 6.0) * 0.1;
				s = (0.11 + 0.1 * h2) * (1.0 - g * 0.3);
				vec2 rr = rot2(c, h1 * 6.283 + g * 3.0);
				world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.25;
				a = pow(sin(g * 3.14159), 0.7) * (0.7 + 0.3 * sin(vfx_time * 25.0 + h1 * 30.0));
				col = mix(hot, gold, g);
				cell = 2.0;
			}
		} else {
			// Level-up: sparkles drifting down from the burst.
			float t = since - 0.05 - h3 * 0.2;
			float life = 0.7 + 0.4 * h2;
			if (t >= 0.0 && t < life) {
				float g = t / life;
				vec3 spread = (mx * (h1 - 0.5) + fwd * (h2 - 0.5)) * 2.4;
				vec3 at = burst_at + spread * ease_out(g) + up * (0.3 - 2.2 * g * g) + mx * sin(g * 6.0 + h1 * 6.0) * 0.1;
				s = (0.10 + 0.1 * h2) * (1.0 - g * 0.3);
				vec2 rr = rot2(c, h1 * 6.283 + g * 3.0);
				world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.2;
				a = pow(sin(g * 3.14159), 0.7) * (0.7 + 0.3 * sin(vfx_time * 25.0 + h1 * 30.0));
				col = mix(hot, gold, g);
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
		} else if (kind == 2) {
			float f = clamp(age / 1.2, 0.0, 1.0);
			s = R * (1.6 + 0.6 * ease_out(f));
			a = 0.8 * pow(1.0 - f, 1.5);
			col = mix(boss_hot, violet, clamp(f * 1.5, 0.0, 1.0));
		} else if (kind == 6) {
			float t = field > 0.5 ? landed : -1.0;
			if (t >= 0.0) {
				float f = clamp(t / 0.9, 0.0, 1.0);
				s = R * 1.5;
				a = 0.6 * pow(1.0 - f, 1.5);
				col = mix(hot, deep, clamp(f * 2.0, 0.0, 1.0));
			}
		} else if (kind == 3) {
			// The cold wash: a pale disc that follows the wave and dies after it.
			float f = clamp(age / 1.4, 0.0, 1.0);
			s = freeze_wave(age, R) * 0.92;
			a = 0.28 * pow(1.0 - f, 1.3);
			col = mix(ice, ice_deep, 0.4);
		} else {
			if (since >= 0.0) {
				float f = clamp(since / 0.8, 0.0, 1.0);
				s = R * 1.3;
				a = 0.6 * pow(1.0 - f, 1.5);
				col = mix(hot, deep, clamp(f * 2.0, 0.0, 1.0));
			}
		}
		world = origin + up * 0.08 + (mx * c.x + fwd * c.y) * 2.0 * s;
		alpha = a;
		cell = 26.0;
		if (a <= 0.0) world = origin;
	} else if (part == 10) {
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin;
		if (kind == 0) {
			// The cast moment: a flare in the sky where the star is born.
			float f = clamp(age / 0.26, 0.0, 1.0);
			at = sky;
			s = 1.8 + 2.4 * ease_out(f);
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
			float hgt = (1.2 + 1.2 * hash11(slot * 1.3 + h1)) * bk;
			float wid = (0.5 + 0.3 * h1) * bk;
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
		vec3 at = origin + up * (R * 1.3);
		float push = R;
		if (kind == 2) {
			// The portal mouth snaps open and shatters outward.
			float f = clamp(age / 0.6, 0.0, 1.0);
			s = bk + (R * 3.2) * ease_out3(clamp(age / 0.28, 0.0, 1.0));
			rot += age * 2.0;
			a = pow(1.0 - f, 1.2) * smoothstep(0.0, 0.03, age);
			col = mix(boss_hot, mix(red, violet, 0.5), clamp(f * 1.5, 0.0, 1.0));
			cell = 25.0;
		} else if (kind == 1) {
			// It forms during the last 0.7 s of the warning so the burst continues it.
			float late = clamp((age - (dur - 0.7)) / 0.7, 0.0, 1.0);
			s = R * 1.2 * ease_out(late);
			rot -= age * 3.0;
			a = (0.3 + 0.7 * late) * late * live;
			col = mix(red, violet, 0.6);
			cell = 25.0;
		} else if (kind == 0) {
			// A facing shockwave at the impact: the blow seen edge-on, over the ground ring.
			float t = age - HIT;
			if (t >= 0.0) {
				float f = clamp(t / 0.34, 0.0, 1.0);
				s = 0.4 + R * 1.7 * ease_out3(f);
				a = pow(1.0 - f, 1.4) * 0.9;
				col = mix(vec3(1.0), hot, 0.5);
			}
			at = origin + up * 0.7;
			push = 0.6;
			cell = 3.0;
		} else if (kind == 6) {
			float t = field > 0.5 ? landed : since;
			if (t >= 0.0) {
				float f = clamp(t / 0.36, 0.0, 1.0);
				s = 0.3 + 2.1 * ease_out3(f);
				a = pow(1.0 - f, 1.3) * 0.85;
				col = mix(vec3(1.0), gold, 0.5);
			}
			at = field > 0.5 ? origin + up * 0.7 : crown_at;
			push = 0.7;
			cell = 3.0;
		} else if (kind == 3) {
			float f = clamp(age / 0.36, 0.0, 1.0);
			s = 0.5 + 3.4 * ease_out3(f);
			a = pow(1.0 - f, 1.3) * 0.9;
			col = mix(ice_hot, ice, 0.4);
			at = origin + up * 1.4;
			push = 1.0;
			cell = 3.0;
		} else {
			if (since >= 0.0) {
				float f = clamp(since / 0.45, 0.0, 1.0);
				s = 0.3 + 2.4 * ease_out3(f);
				a = pow(1.0 - f, 1.3) * 0.85;
				col = mix(vec3(1.0), gold, 0.5);
			}
			at = burst_at;
			push = 0.8;
			cell = 3.0;
		}
		vec2 rr = rot2(c, rot);
		world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * push;
		alpha = a * (s > 0.001 ? 1.0 : 0.0);
		if (a <= 0.0) world = origin;
	} else if (part == 13) {
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
		} else if (kind == 2) {
			float f = clamp(age / 1.3, 0.0, 1.0);
			s = R * 2.0;
			a = pow(1.0 - f, 1.2);
			col = mix(boss_hot, red, clamp(f * 1.5, 0.0, 1.0));
		}
		vec2 rr = rot2(c, seed * 6.283);
		world = origin + up * 0.085 + (mx * rr.x + fwd * rr.y) * 2.0 * s;
		alpha = a;
		cell = 19.0;
		if (a <= 0.0) world = origin;
	} else {
		// Trail embers x10: shed along the meteor's path, drifting off it and fading.
		float h1 = hash11(seed * 7.1 + float(idx) * 1.9);
		float h2 = hash11(seed * 9.7 + float(idx) * 0.8);
		float a = 0.0;
		float s = 0.0;
		if (kind == 6 && field > 0.5) {
			// Gold glitter shed along the star's fall.
			float born = (float(idx) + 0.5) / 10.0 * ARRIVE;
			float t = age - born;
			float life = 0.40 + 0.2 * h2;
			if (t >= 0.0 && t < life) {
				float f = t / life;
				float bf = born / ARRIVE;
				vec3 side = normalize(cross(drop_dir, cam_fwd));
				vec3 at = mix(drop_from, origin + up * 0.35, bf * bf) + side * (h1 - 0.5) * 0.5 * (1.0 + 2.0 * f) + up * (-1.2 * f * f);
				s = (0.16 + 0.10 * h2) * (1.0 - 0.5 * f);
				vec2 rr = rot2(c, h1 * 6.283 + f * 4.0);
				world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.25;
				a = pow(1.0 - f, 0.9) * (0.8 + 0.2 * sin(vfx_time * 30.0 + h1 * 20.0));
				col = mix(hot, gold, f);
				cell = 2.0;
			}
		} else if (kind == 0) {
			float born = (float(idx) + 0.5) / 10.0 * HIT;      // the head passed here then
			float t = age - born;
			float life = 0.42 + 0.2 * h2;
			if (t >= 0.0 && t < life && age < HIT + 0.3) {
				float f = t / life;
				float bf = born / HIT;
				vec3 at = mix(sky, target, bf * bf) + fall_side * (h1 - 0.5) * 0.7 * (1.0 + 2.0 * f)
					- fall_dir * (0.4 + 1.6 * f) + up * (-0.5 * 4.0 * f * f);
				s = (0.3 + 0.18 * h2) * (1.0 - 0.5 * f);
				vec2 rr = rot2(c, h1 * 6.283 + f * 4.0);
				world = at + (cam_right * rr.x + cam_up * rr.y) * s - cam_fwd * 0.25;
				a = pow(1.0 - f, 0.9) * (0.8 + 0.2 * sin(vfx_time * 30.0 + h1 * 20.0));
				col = mix(hot, deep, f);
				cell = 14.0;
			}
		}
		if (a <= 0.0) world = origin;
		alpha = a;
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
	} else if (v_cell > 31.5) {
		a = texture(zone_sprites, cell_uv(int(v_cell + 0.5) - 32, UV)).a;
	} else if (v_cell > 15.5) {
		a = texture(skill_sprites, cell_uv(int(v_cell + 0.5) - 16, UV)).a;
	} else {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	}
	ALBEDO = mix(rgb, rgb * rgb * 1.25, vfx_wash * 0.5);
	ALPHA = clamp(a, 0.0, 1.0) * v_tint.a * mix(1.0, 0.72, vfx_wash);
}
