shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Ground rings drawn as UI on the battlefield (2026-10-19, feedback O3 and F6):
//   mode 0  the selected hero: its attack range as rounded dashes and a ring at its feet
//   mode 1  the starlight-burst aim, valid: the damage radius (solid), a translucent fill,
//           eight lock-on arrowheads at 1.35 R pointing in (where the cast's sigil starts;
//           `lock` closes them onto R at the cast) and a centre star
//   mode 2  the aim, invalid: red-grey dashes and a cross
// The quad (PlaneMesh 2x2 in XZ, the node scaled to the ring's extent) is shaded per
// fragment from the distance to its centre. Every stroke is a fixed number of screen pixels:
// the screen-space derivative of that distance says how many world units one pixel covers
// across the ring, so the line reads the same on a 1 u melee ring and an 8 u bow ring,
// on the foreshortened top and bottom of the ellipse and at both window sizes (widths are
// given at 800 px of viewport height). Unshaded and fog-free, drawn after every effect
// (render_priority 10+) and depth-tested against the bodies, with a dark halo around the
// gold so it holds on snow, sand and lava alike. Animation values (draw-in, flash, lock,
// spin, presence) are uniforms set by ArenaWorld: nothing here reads a clock.
uniform int mode = 0;
uniform float radius = 2.0;          // world units: the range or damage radius
uniform float foot = 0.0;            // world units: the ring at the hero's feet (mode 0; 0 = none)
uniform float stroke_px = 3.6;       // core width of the range / damage ring
uniform float foot_px = 4.2;         // core width of the foot ring
uniform float halo_px = 1.7;         // dark edge on each side of every core
uniform vec4 color : source_color = vec4(1.0, 0.79, 0.24, 1.0);
uniform vec4 halo_color : source_color = vec4(0.09, 0.05, 0.01, 0.66);
uniform float fill = 0.10;           // fill alpha just inside the ring (fades toward the centre)
uniform float dashes = 0.0;          // whole number of dashes around the ring, 0 = solid
uniform float dash_on = 0.62;        // drawn fraction of each dash period
uniform float appear = 1.0;          // 0..1 draw-in: the ring grows out from 0.82 R and fades in
uniform float flash = 0.0;           // brightening (a new selection, the aim locking on)
uniform float lock = 0.0;            // aim: 0..1 the arrowheads close from 1.35 R onto R (the cast)
uniform float spin = 0.0;            // aim: radians the lock-on arrowheads have turned
uniform float presence = 1.0;        // overall opacity (fades)
// Picture-to-screen compensation (ArenaWorld._sync_screen_k): the picture is drawn at
// 1280x800 and shown smaller on a small window, so every pixel width is multiplied by this
// (1 / screen scale, 1..2) to keep its design width on the real screen.
uniform float screen_k = 1.0;

varying vec2 v_p;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_p = w.xz - MODEL_MATRIX[3].xz;
}

// 1 inside the shape whose signed distance is `sdf` (world units), anti-aliased over one
// pixel of `upp` world units.
float inside(float sdf, float upp) {
	return 1.0 - smoothstep(-0.5 * upp, 0.5 * upp, sdf);
}

// Premultiplied "over".
vec4 over(vec4 top, vec4 under) {
	return top + under * (1.0 - top.a);
}

// A stroke of signed distance `sdf` (0 at its edge, negative inside) in `rgb`, with the
// halo around it: returns the premultiplied layer to put over what is under it.
vec4 stroke(float sdf, float upp, float halo, vec3 rgb, vec4 halo_tint) {
	float core = inside(sdf, upp);
	float edge = inside(sdf - halo, upp);
	vec4 h = vec4(halo_tint.rgb, 1.0) * (halo_tint.a * clamp(edge - core, 0.0, 1.0));
	vec4 c = vec4(rgb, 1.0) * core;
	return over(c, h);
}

// Signed distance to a dashed ring of radius r (rounded dashes, half width hw). `dashes`
// must be a whole number so the dash pattern closes where atan wraps.
float dashed_ring(vec2 p, float d, float r, float hw, float count, float on) {
	float across = abs(d - r);
	if (count < 0.5) return across - hw;
	float period = TAU * r / count;
	float u = fract((atan(p.y, p.x) / TAU + 0.5) * count) - 0.5;
	float along = abs(u) * period;
	float half_len = max(0.5 * on * period - hw, 0.0);
	return length(vec2(max(along - half_len, 0.0), across)) - hw;
}

// Signed distance to a segment from a to b with half width hw.
float segment(vec2 p, vec2 a, vec2 b, float hw) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(p - a - ab * t) - hw;
}

void fragment() {
	vec2 p = v_p;
	float d = length(p);
	float upp = max(length(vec2(dFdx(d), dFdy(d))), 1e-5);
	float k = clamp(VIEWPORT_SIZE.y / 800.0, 0.78, 1.6) * screen_k;
	float halo = halo_px * k * upp;
	float grow = 0.82 + 0.18 * ease_out3(appear);
	float r = radius * grow;
	vec3 hot = min(color.rgb * (1.0 + 0.9 * flash) + vec3(0.25) * flash, vec3(1.0));
	vec4 acc = vec4(0.0);
	if (mode == 0) {
		// The reach: a light fill that gathers toward the edge, then the dashed ring.
		float hw = 0.5 * stroke_px * k * upp;
		float in_r = 1.0 - smoothstep(r - upp, r, d);
		float f = fill * in_r * (0.30 + 0.70 * smoothstep(r * 0.45, r, d));
		acc = vec4(color.rgb, 1.0) * f;
		acc = over(stroke(dashed_ring(p, d, r, hw, dashes, dash_on), upp, halo, hot, halo_color), acc);
		if (foot > 0.0) {
			// The feet: a double ring (a bold outer line, a fine inner one, dark between them)
			// with a warm glow inside and four small diamonds on the outer line.
			float fr = foot * mix(0.7, 1.0, ease_out3(appear));
			float fw = 0.5 * foot_px * k * upp;
			float glow = 0.22 * (1.0 - smoothstep(fr * 0.30, fr * 0.80, d)) * smoothstep(fr * 0.10, fr * 0.45, d);
			acc = over(vec4(color.rgb, 1.0) * glow, acc);
			float rings = min(abs(d - fr) - fw, abs(d - fr * 0.78) - 0.45 * fw);
			acc = over(stroke(rings, upp, halo, hot, halo_color), acc);
			vec2 q = abs(p);
			vec2 marker = q.x > q.y ? vec2(q.x - fr, q.y) : vec2(q.y - fr, q.x);
			float diamond = (abs(marker.x) + abs(marker.y)) * 0.7071 - 2.4 * k * upp;
			acc = over(stroke(diamond, upp, halo * 0.8, mix(hot, vec3(1.0), 0.55), halo_color), acc);
		}
	} else if (mode == 1) {
		// The aim: the struck area filled, the damage radius solid, the lock-on arrowheads.
		float hw = 0.5 * stroke_px * k * upp;
		float in_r = 1.0 - smoothstep(r - upp, r, d);
		float f = fill * in_r * (0.55 + 0.45 * smoothstep(r * 0.3, r, d));
		acc = vec4(color.rgb, 1.0) * f;
		acc = over(stroke(abs(d - r) - hw, upp, halo, hot, halo_color), acc);
		// Eight arrowheads pointing in, at 1.35 R while aiming; they close on R as the star is
		// cast (the cast's sigil starts at 1.35 R too). Arrowheads, not dashes, so they never
		// read as a second range ring.
		float tick_r = r * mix(1.35, 1.0, ease_out3(lock));
		float tick_len = r * 0.12 * (1.0 - 0.5 * lock);
		float tick_w = tick_len * 0.48;
		float a = atan(p.y, p.x) - spin;
		float sector = TAU / 8.0;
		float local = (fract(a / sector + 0.5) - 0.5) * sector;
		vec2 q = vec2(cos(local), sin(local)) * d;
		float along = q.x - tick_r;
		float side_d = (abs(q.y) - tick_w * clamp(along / max(tick_len, 1e-4), 0.0, 1.0)) * inversesqrt(1.0 + (tick_w / max(tick_len, 1e-4)) * (tick_w / max(tick_len, 1e-4)));
		float tick = max(max(-along, along - tick_len), side_d);
		acc = over(stroke(tick, upp, halo, hot, halo_color), acc);
		// A four-point star at the centre: where the star will land.
		float star_len = r * 0.16;
		float arm = min(segment(p, vec2(-star_len, 0.0), vec2(star_len, 0.0), hw * 0.8),
			segment(p, vec2(0.0, -star_len * 0.8), vec2(0.0, star_len * 0.8), hw * 0.8));
		acc = over(stroke(arm, upp, halo, hot, halo_color), acc);
	} else {
		// The aim where the star cannot fall: grey-red dashes and a cross.
		float hw = 0.5 * stroke_px * k * upp;
		float in_r = 1.0 - smoothstep(r - upp, r, d);
		acc = vec4(color.rgb, 1.0) * (fill * in_r);
		acc = over(stroke(dashed_ring(p, d, r, hw, dashes, dash_on), upp, halo, color.rgb, halo_color), acc);
		float x_len = r * 0.20;
		float cross_sdf = min(segment(p, vec2(-x_len), vec2(x_len), hw), segment(p, vec2(-x_len, x_len), vec2(x_len, -x_len), hw));
		acc = over(stroke(cross_sdf, upp, halo, color.rgb, halo_color), acc);
	}
	float a = acc.a * presence * smoothstep(0.0, 0.35, appear);
	if (a <= 0.002) discard;
	ALBEDO = acc.rgb / max(acc.a, 1e-4);
	ALPHA = clamp(a, 0.0, 1.0);
}
