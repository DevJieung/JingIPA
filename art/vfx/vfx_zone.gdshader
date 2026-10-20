shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Ground zones (sim.zones) and caster circles in one MultiMesh: the additive light.
//   transform: origin on the ground, XZ scale = radius R (the simulator's damage radius)
//   COLOR:     rgb colour, a = remaining life fraction (zones) or 1
//   CUSTOM:    x age t  y delay (>= 0 zone; -1 caster circle, then x = wind-up progress 0..1)
//              z tick interval  w element
// Volumetric zones (2026-10-17). The rune disc still marks the damage radius exactly; the
// column above it is the element's weather, timed to the simulator's own clock (t, delay,
// tick), so it anticipates during the telegraph, snaps when the zone lands and strikes on
// every tick:
//   ice    a blizzard: shards and flakes climb a tightening helix, frost veils orbit the
//          column, rime crystals jut up at every tick and are replaced at the next
//   fire   a magma eruption: cracks glow and pulse, lava gouts burst upward at every tick,
//          embers climb a heat column, smoke lingers (vfx_zone_base)
//   elec   thunder: a charged sigil, then bolts strike from above the column at every tick
//          with a sky flash; sparks climb
//   water  a geyser whirlpool: a spiral floor, spray columns at every tick, droplets and
//          foam veils swirling
//   none   a card storm: glowing cards and starlight spiral up
// Parts (UV2.x): 0 rune disc  1 motes x8  2 vortex shards x16  3 veils x4 (0 the soft
// column body, 1..3 orbiting streak sheets)  4 strikes x6  5 tick caps x2 (ground, top)
// 6 landing column  7 crown ring  8 floor glow.
// A zone's seed comes from its position, so a zone keeps its particles when the list it
// is drawn from reorders (the instance index changes as earlier zones end).
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D zone_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue.
uniform float vfx_wash = 0.0;

const float LAND = 0.12;      // seconds the landing snap takes

varying vec4 v_tint;
varying vec4 v_state;   // mode(0 zone,1 cast), landed fraction, pulse, element
varying vec2 v_plane;
varying float v_cell;

// Column height of an element's weather (world units above the disc).
float column_height(int e) {
	if (e == 1) return 2.5;
	if (e == 3) return 2.7;
	if (e == 4) return 2.1;
	if (e == 2) return 2.5;
	return 2.3;
}

// How fast the helix turns (rad/s): a blizzard whips, water swirls, fire breathes.
float spin_rate(int e) {
	if (e == 2) return 4.6;
	if (e == 4) return 5.2;
	if (e == 3) return 6.0;
	if (e == 1) return 3.0;
	return 2.8;
}

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
	vec3 pillar_side = normalize(cross(up, cam_fwd));
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	float t = INSTANCE_CUSTOM.x;
	float delay = INSTANCE_CUSTOM.y;
	float tick = max(INSTANCE_CUSTOM.z, 0.05);
	int elem = int(INSTANCE_CUSTOM.w + 0.5);
	bool cast = delay < -0.5;
	float seed = hash21(origin.xz * 0.37 + vec2(11.0, 7.0));
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	float alpha = 0.0;
	vec3 col = COLOR.rgb;
	float cell = 0.0;
	float landed = cast ? clamp(t, 0.0, 1.0) : clamp((t - delay) / LAND, 0.0, 1.0);
	float since = cast ? 0.0 : t - delay;                       // seconds since the landing
	float pre = cast ? 0.0 : clamp(t / max(delay, 0.01), 0.0, 1.0);   // telegraph progress
	float phase = since > 0.0 ? fract(since / tick) : 0.0;      // position inside the tick
	float k = since > 0.0 ? floor(since / tick) : -1.0;         // tick index since landing
	float ts = phase * tick;                                    // seconds since the last tick
	float pulse = 0.0;
	if (!cast && since > 0.0) pulse = exp(-ts * 7.0);
	float remain = 0.6 + 0.4 * COLOR.a;
	float H = column_height(elem);
	float spin = spin_rate(elem);
	vec3 tint = elem_tint(elem);
	vec3 hot = elem_hot(elem);
	vec3 body_col = mix(mix(COLOR.rgb, tint, 0.55), hot, 0.2);
	v_plane = c * 2.0;
	v_cell = 0.0;
	if (part == 0) {
		// Telegraph: a converging ring; landed: the full rune disc.
		float grow = cast ? (0.55 + 0.45 * landed) : (t < delay ? 1.25 - 0.25 * pre : 1.0);
		world = origin + up * 0.05 + (ux * c.x + uz * c.y) * 2.0 * radius * grow;
		alpha = cast ? 0.35 + 0.65 * landed : (t < delay ? 0.45 + 0.4 * pre : 1.0);
		alpha *= cast ? 1.0 : (0.55 + 0.45 * COLOR.a);
		v_cell = 12.0;
	} else if (part == 1) {
		float h1 = hash11(seed * 3.7 + float(idx));
		float h2 = hash11(seed * 5.3 + float(idx) * 2.3);
		float h3 = hash11(seed * 9.1 + float(idx) * 0.7);
		float cycle = 0.75 + 0.35 * h3;
		float ph = fract(vfx_time / cycle + h1);
		float ang = h2 * TAU;
		float dist = sqrt(h1) * radius * 0.85;
		float rise = elem == 1 ? 1.1 : elem == 4 ? 0.45 : 0.75;
		vec3 at = origin + ux * cos(ang) * dist + uz * sin(ang) * dist + up * (0.08 + rise * ph);
		if (elem == 4) at += up * sin(ph * 12.0 + float(idx)) * 0.06;
		float s = (0.08 + 0.06 * h2) * (1.0 - ph * 0.5) * (elem == 2 ? 1.6 : 1.0) * (radius > 1.2 ? 1.3 : 1.0);
		vec2 r = rot2(c, h1 * TAU + ph * 3.0);
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.2;
		float present = cast ? landed : (t > delay ? 1.0 : 0.0);
		alpha = pow(sin(ph * 3.14159), 0.8) * present * remain;
		col = mix(mix(COLOR.rgb, tint, 0.5), vec3(1.0), 0.3);
		v_cell = float(mote_cell(elem));
		if (cast) v_cell = 2.0;
	} else if (cast) {
		// Caster circles draw nothing more.
		alpha = 0.0;
	} else if (part == 2) {
		// Vortex shards: each climbs the column on a tightening helix, again and again.
		float h1 = hash11(seed * 13.0 + float(idx));
		float h2 = hash11(seed * 29.0 + float(idx) * 1.7);
		float h3 = hash11(seed * 41.0 + float(idx) * 0.37);
		float climb = 0.55 + 0.35 * h3;                          // climbs per second
		float ph = fract(max(since, 0.0) * climb + h1);
		float ang = h2 * TAU + since * spin + ph * 2.6;
		float rad = radius * (0.92 - 0.50 * ph) * (0.82 + 0.36 * h1);
		vec3 radial = ux * cos(ang) + uz * sin(ang);
		vec3 at;
		float a;
		if (since < 0.0) {
			// Anticipation: drawn in over the ground from outside the radius.
			float g = ease_in(pre);
			ang = h2 * TAU + t * spin * 0.6;
			radial = ux * cos(ang) + uz * sin(ang);
			at = origin + radial * radius * (1.35 - 0.5 * g) + up * (0.12 + 0.25 * g * h1);
			a = 0.55 * pre;
			ph = 0.15;
		} else {
			at = origin + radial * rad + up * (0.08 + H * ph);
			a = pow(sin(ph * 3.14159), 0.6) * remain * smoothstep(0.0, LAND, since);
		}
		float s = 0.30 + 0.22 * h2;
		float turn = h1 * TAU + since * (2.0 + 4.0 * h3);
		if (elem == 2) { v_cell = (idx % 3 == 0) ? 34.0 : 6.0; s *= (idx % 3 == 0) ? 1.45 : 1.25; }
		else if (elem == 1) { v_cell = (idx % 2 == 0) ? 14.0 : 5.0; s *= 1.35; turn = h1 * TAU + sin(since * 6.0 + h2 * 9.0) * 0.35; }
		else if (elem == 3) { v_cell = (idx % 4 == 0) ? 7.0 : 2.0; s *= 1.05; turn = since * 11.0 * (h2 - 0.5); }
		else if (elem == 4) { v_cell = 8.0; s *= 1.2; turn = ang + 1.57; }
		else { v_cell = (idx % 3 == 0) ? 1.0 : 37.0; s *= (idx % 3 == 0) ? 1.0 : 1.5; turn = since * (3.0 + 5.0 * h3) + h1 * TAU; }
		vec2 r = rot2(c, turn);
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.25;
		col = mix(mix(tint, hot, 0.35), COLOR.rgb, 0.2);
		if (elem == 0) col = mix(vec3(0.92, 0.85, 1.0), COLOR.rgb, 0.45);
		alpha = min(a * 1.35, 1.0);
	} else if (part == 3) {
		// The column: a soft body (0) and three streak veils that orbit it, bright when
		// they pass in front: the swirl reads even in additive blending.
		float present = smoothstep(0.0, LAND * 1.5, since) * remain;
		float a;
		float w;
		float hgt;
		vec3 base;
		float front = 1.0;
		if (idx == 0) {
			w = radius * 1.75;
			hgt = H * 1.08;
			base = origin + up * 0.04;
			a = (elem == 3 ? 0.30 : elem == 0 ? 0.36 : 0.55) * present;
			// A faint charging column shows where the weather will stand.
			if (since < 0.0) a = 0.18 * pre * pre;
			v_cell = 47.0;
		} else {
			float ang = since * spin * 0.55 * (elem == 4 ? -1.0 : 1.0) + float(idx) * TAU / 3.0 + seed * TAU;
			vec3 radial = ux * cos(ang) + uz * sin(ang);
			front = 0.5 + 0.5 * dot(radial, -cam_fwd);
			w = radius * (1.15 - 0.1 * float(idx));
			hgt = H * (0.78 + 0.1 * float(idx));
			base = origin + radial * radius * 0.42 + up * 0.05;
			a = (elem == 3 ? 0.30 : elem == 1 ? 0.50 : 0.70) * present * (0.35 + 0.65 * front);
			v_cell = 32.0;
		}
		float taper = mix(1.0, 0.62, c.y + 0.5);
		world = base + up * (c.y + 0.5) * hgt + pillar_side * c.x * w * taper - cam_fwd * (0.3 + 0.25 * front);
		col = idx == 0 ? mix(tint, COLOR.rgb, 0.35) : mix(mix(tint, hot, 0.3), COLOR.rgb, 0.25);
		if (elem == 1 && idx > 0) col = mix(vec3(1.0, 0.55, 0.15), hot, 0.3);
		alpha = a;
	} else if (part == 4) {
		// Strikes: at every tick, six of them in a staggered burst over the disc.
		float stagger = float(idx) * 0.03;
		float local = ts - stagger;                         // seconds since this strike
		float kk = k;
		if (local < 0.0 && k > 0.0) {
			// The tail of the previous tick's strike is still falling.
			local += tick;
			kk = k - 1.0;
		}
		float h1 = hash11(seed * 17.0 + float(idx) * 3.1 + kk * 7.7);
		float h2 = hash11(seed * 23.0 + float(idx) * 1.3 + kk * 5.1);
		float h3 = hash11(seed * 31.0 + float(idx) * 0.7 + kk * 3.3);
		float rad = sqrt(h1) * radius * 0.82;
		float ang = h2 * TAU;
		vec3 foot = origin + (ux * cos(ang) + uz * sin(ang)) * rad;
		float a = 0.0;
		float hgt = 0.0;
		float wid = 0.0;
		vec3 colour = hot;
		bool valid = since > 0.0 && local >= 0.0;
		if (elem == 3) {
			// A bolt from above the column, strobing through its first frames.
			float life = 0.22;
			if (valid && local < life) {
				float f = local / life;
				hgt = H + 1.6;
				wid = 1.15 + 0.4 * h3;
				float strobe = 0.75 + 0.25 * step(0.5, fract(vfx_time * 31.0 + h3 * 5.0));
				a = pow(1.0 - f, 0.9) * strobe;
				colour = mix(vec3(1.0), vec3(0.85, 0.9, 1.0), 0.4);
			}
			v_cell = 43.0;
		} else if (elem == 1) {
			// A lava gout: up with a snap, then it falls back and dims.
			float life = 0.40;
			if (valid && local < life) {
				float f = local / life;
				hgt = (1.7 + 1.0 * h3) * overshoot(local / 0.13) * (1.0 - smoothstep(0.42, 1.0, f));
				wid = 1.0 + 0.35 * h3;
				a = (1.0 - smoothstep(0.55, 1.0, f));
				colour = mix(vec3(1.0, 0.86, 0.55), vec3(1.0, 0.42, 0.08), f);
			}
			v_cell = 35.0;
		} else if (elem == 2) {
			// Rime: crystals jut up at the tick and stand until the next replaces them.
			float life = tick;
			if (valid && local < life) {
				float f = local / life;
				hgt = (1.15 + 0.85 * h3) * overshoot(local / 0.11);
				wid = 1.0 + 0.35 * h3;
				a = 0.85 * (1.0 - smoothstep(0.75, 1.0, f));
				colour = mix(vec3(0.85, 0.96, 1.0), vec3(0.6, 0.85, 1.0), h2);
			}
			v_cell = idx % 2 == 0 ? 40.0 : 33.0;
		} else if (elem == 4) {
			// A geyser: a spray column snaps up and collapses in a third of a second.
			float life = 0.34;
			if (valid && local < life) {
				float f = local / life;
				hgt = (1.8 + 0.9 * h3) * overshoot(local / 0.10) * (1.0 - smoothstep(0.45, 1.0, f));
				wid = 1.1 + 0.35 * h3;
				a = 0.95 * (1.0 - smoothstep(0.5, 1.0, f));
				colour = mix(vec3(0.9, 0.97, 1.0), vec3(0.45, 0.72, 1.0), f);
			}
			v_cell = 36.0;
		} else {
			// Card storm: star streaks shoot up out of the deck.
			float life = 0.30;
			if (valid && local < life) {
				float f = local / life;
				hgt = (1.8 + 1.0 * h3) * ease_out3(local / 0.12);
				wid = 0.6;
				a = (1.0 - f) * (1.0 - f);
				colour = mix(vec3(1.0), mix(COLOR.rgb, vec3(0.9, 0.8, 1.0), 0.5), f);
			}
			v_cell = 27.0;
		}
		world = foot + up * (c.y + 0.5) * hgt + pillar_side * c.x * wid - cam_fwd * 0.35;
		col = colour;
		alpha = a * remain;
		if (a <= 0.0) world = origin;
	} else if (part == 5) {
		// Tick caps: a flash on the disc and one at the top of the weather.
		float a = 0.0;
		float s = 0.0;
		vec3 at = origin;
		float turn = seed * TAU;
		if (idx == 0) {
			s = radius * (0.75 + 0.5 * (1.0 - pulse));
			a = 0.85 * pulse * (since > 0.0 ? 1.0 : 0.0);
			at = origin + up * 0.18;
			v_cell = 0.0;
			col = mix(hot, tint, 0.4);
			if (elem == 4) { v_cell = 3.0; s = radius * (0.5 + 0.6 * (1.0 - pulse)); a *= 1.2; }
		} else {
			if (elem == 3) {
				// Sky flash over the column at each tick.
				s = radius * 2.0;
				at = origin + up * (H + 1.2);
				a = 0.8 * pulse * (since > 0.0 ? 1.0 : 0.0);
				v_cell = 0.0;
				col = vec3(0.9, 0.93, 1.0);
			} else if (elem == 1) {
				s = radius * 0.9;
				at = origin + up * 0.35;
				a = 0.5 * pulse * (since > 0.0 ? 1.0 : 0.0);
				v_cell = 0.0;
				col = vec3(1.0, 0.55, 0.15);
			} else if (elem == 2) {
				s = 0.55 + 0.35 * (1.0 - pulse);
				at = origin + up * (H + 0.1);
				a = 0.9 * pulse * (since > 0.0 ? 1.0 : 0.0);
				turn += since * 1.5;
				v_cell = 2.0;
				col = vec3(1.0);
			} else if (elem == 4) {
				s = 0.8;
				at = origin + up * (H * 0.9);
				a = 0.5 * pulse * (since > 0.0 ? 1.0 : 0.0);
				v_cell = 0.0;
				col = vec3(0.8, 0.92, 1.0);
			} else {
				s = 0.5 + 0.4 * (1.0 - pulse);
				at = origin + up * (H + 0.1);
				a = 0.85 * pulse * (since > 0.0 ? 1.0 : 0.0);
				turn += since * 2.0;
				v_cell = 1.0;
				col = vec3(1.0, 0.95, 1.0);
			}
		}
		vec2 r = rot2(c, turn);
		if (idx == 0) world = at + (ux * r.x + uz * r.y) * 2.0 * s;
		else world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.3;
		alpha = a * remain;
		if (a <= 0.0) world = origin;
	} else if (part == 6) {
		// The landing: a column of light snaps up out of the disc and dies in a quarter
		// second; before it, a faint beam thickens through the telegraph (anticipation).
		float a = 0.0;
		float hgt = 0.0;
		float wid = radius * 0.9;
		if (since < 0.0) {
			hgt = H * 1.2 * pre;
			a = 0.08 + 0.22 * pre * pre;
			wid = radius * 0.35;
		} else {
			float f = clamp(since / 0.28, 0.0, 1.0);
			hgt = H * 1.35 * ease_out3(since / 0.06);
			wid = radius * mix(0.95, 0.5, f);
			a = pow(1.0 - f, 1.4);
		}
		world = origin + up * (c.y + 0.5) * hgt + pillar_side * c.x * wid - cam_fwd * 0.4;
		col = mix(hot, tint, 0.3);
		v_cell = 17.0;
		alpha = a;
	} else if (part == 7) {
		// Crown: a ring at the top of the column, turning with it.
		float a = (elem == 3 ? 0.3 : 0.6) * smoothstep(0.0, 0.3, since) * remain;
		vec2 r = rot2(c, since * spin * 0.4);
		float s = radius * (elem == 2 ? 0.5 : 0.42) * (0.9 + 0.1 * sin(since * 4.0));
		world = origin + up * (H * (elem == 4 ? 0.82 : 0.98)) + (ux * r.x + uz * r.y) * 2.0 * s;
		col = mix(tint, hot, 0.3);
		v_cell = elem == 1 ? 14.0 : 3.0;
		if (elem == 1) v_cell = 3.0;
		alpha = a;
		if (a <= 0.0) world = origin;
	} else {
		// Floor glow: the element's ground, lit from within and pulsing with the ticks.
		float a = 0.0;
		float turn = 0.0;
		float s = radius;
		if (elem == 1) { v_cell = 44.0; a = 0.7 + 0.5 * pulse; turn = seed * TAU; }
		else if (elem == 2) { v_cell = 41.0; a = 0.6 + 0.35 * pulse; turn = seed * TAU; s = radius * 1.02; }
		else if (elem == 4) { v_cell = 42.0; a = 0.75 + 0.3 * pulse; turn = -since * 2.4; }
		else if (elem == 0) { v_cell = 42.0; a = 0.35 + 0.2 * pulse; turn = since * 1.2; }
		else { v_cell = 0.0; a = 0.18 * pulse; s = radius * 0.6; }
		a *= landed * remain;
		vec2 r = rot2(c, turn);
		world = origin + up * 0.065 + (ux * r.x + uz * r.y) * 2.0 * s;
		col = mix(tint, hot, 0.25);
		if (elem == 1) col = mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.8, 0.4), pulse * 0.6);
		alpha = a;
		if (a <= 0.0) world = origin;
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
