shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Alpha-blended layer of the burst MultiMesh: smoke/mist puffs, ground scorch and flung
// debris. Same instance contract as vfx_burst.gdshader (COLOR.a = body scale: puffs lift
// and clear a larger body, the scorch stays on the ground).
// Parts (UV2.x): 4 puff billboard x2, 6 ground scorch, 9 debris x4 (dark chunks with
// weight: clods out of a splash, chips off a blade contact, the pieces of a big body,
// rock out of a magma zone's last gout).
// Kinds without a row (16..19, among them beam and bolt caps) draw nothing in this layer.
// Kind 21 (seal) leaves a pool of gold under the monster the revival's wave stopped.
// Kind 22 (scatter) is the haze a fleeing body thins into. -Z is the way the body runs
// (StellarVfx.scatter_heading); the puffs follow it for the 0.5 s of its run
// (NativeMonsterModel.FLEE_SEC / FLEE_DIST / FLEE_EASE: the same bolt, 1 - (1 - u)^1.8)
// but stay behind it, a trail between the body and the crystal, and thicken only as the
// body thins: the body is seen to run before the haze is all that is left.
// Kind 24 (zone_end, size = R) settles a zone: frost mist or lingering smoke, a frost
// pane or soot on the ground, rock from a magma gout.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D skill_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D zone_sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
uniform float vfx_epoch = 0.0;
// 1 on bright snow/ice fields (the scatter haze and frost bodies read it: pale haze is
// lost on snow).
uniform float vfx_wash = 0.0;

const float BODY_CLEAR = 1.9;

varying vec4 v_tint;
varying float v_cell;
varying vec2 v_plane;
varying float v_edge;

float kind_lift(int k, float size) {
	if (k == 0) return 0.5;
	if (k == 1) return 0.4;
	if (k == 3) return 0.45 * size;
	if (k == 4) return 0.7;
	if (k == 7) return 0.4;
	if (k == 8) return size;
	if (k == 9) return 0.3;
	if (k == 10) return 0.3;
	if (k == 11) return 0.3;
	if (k == 12) return 0.5;
	if (k == 13) return 0.4;
	if (k == 14) return 0.6;
	if (k == 22) return 0.5;
	if (k == 23) return 0.55;
	if (k == 24) return 0.3;
	return 0.0;
}

// size0, size1, duration, alpha
vec4 puff_params(int k, float size, int e) {
	if (k == 0) return vec4(0.12, 0.32, 0.40, 0.18);
	if (k == 1) return vec4(0.26, 0.80, 0.65, 0.22);
	if (k == 3) return vec4(0.24 * size, 0.70 * size, 0.80, 0.26);
	if (k == 7) return vec4(0.16, 0.40, 0.70, 0.18);
	if (k == 10) return vec4(0.28, 0.70, 0.65, 0.24);
	if (k == 11) return vec4(0.32, 1.00, 0.80, 0.30);
	if (k == 12) return vec4(0.70, 2.20, 1.00, 0.40);
	if (k == 13) return vec4(1.10, 3.40, 1.20, 0.26);
	if (k == 15) return vec4(0.12, 0.42, 0.52, 0.26);
	if (k == 22) return vec4(0.55, 1.75, 0.95, 1.15);
	if (k == 23) return vec4(0.16, 0.44, 0.36, 0.16);
	if (k == 24) {
		if (e == 1) return vec4(size * 0.5, size * 1.5, 1.7, 0.55);
		if (e == 2) return vec4(size * 0.5, size * 1.3, 1.1, 0.45);
		if (e == 4) return vec4(size * 0.4, size * 1.0, 0.8, 0.35);
		if (e == 0) return vec4(size * 0.4, size * 1.1, 0.9, 0.35);
		return vec4(size * 0.3, size * 0.8, 0.5, 0.18);
	}
	return vec4(0.0, 0.0, 0.1, 0.0);
}

// radius, duration, tone (1 dark soot, 0 bright frost, 2 gold pool, 3 wet sheen), unused
vec4 scorch_params(int k, float size, int e) {
	if (k == 11) return vec4(size * 0.9, 1.00, 1.0, 0.0);
	if (k == 12) return vec4(size * 0.80, 1.25, 1.0, 0.0);
	if (k == 13) return vec4(size * 0.55, 1.35, 0.0, 0.0);
	if (k == 21) return vec4(0.72, 0.80, 2.0, 0.0);
	if (k == 24) {
		if (e == 1) return vec4(size * 1.0, 2.2, 1.0, 0.0);
		if (e == 2) return vec4(size * 0.95, 1.8, 0.0, 0.0);
		if (e == 4) return vec4(size * 0.9, 1.3, 3.0, 0.0);
		return vec4(0.0, 0.1, 1.0, 0.0);
	}
	return vec4(0.0, 0.1, 1.0, 0.0);
}

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
	float size = INSTANCE_CUSTOM.y;
	int elem = int(INSTANCE_CUSTOM.z + 0.5);
	int kind = int(INSTANCE_CUSTOM.w + 0.5);
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float seed = hash11(birth * 7.31 + float(INSTANCE_ID) * 0.173);
	float body = max(COLOR.a, 1.0);
	float lift = kind_lift(kind, size) * (kind == 8 ? 1.0 : body);
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	v_plane = c * 2.0;
	v_edge = 0.0;
	v_cell = 4.0;
	if (part == 4) {
		vec4 pp = puff_params(kind, size, elem);
		float f = clamp(age / pp.z, 0.0, 1.0);
		float h = hash11(seed * 4.1 + float(idx));
		float s = mix(pp.x, pp.y, ease_out3(f)) * (0.85 + 0.3 * h);
		vec3 drift = (kind == 15 ? fwd * 0.42 : fwd * 0.08) * f + up * (0.25 + 0.2 * h) * f;
		if (kind == 13 || kind == 7) drift = up * 0.12 * f;
		if (kind == 22) {
			float run = clamp(f / 0.53, 0.0, 1.0);
			drift = fwd * (1.50 * (0.48 + 0.36 * h) * (1.0 - pow(1.0 - run, 1.8)) + 0.30 * ease_out(clamp((f - 0.53) / 0.47, 0.0, 1.0)))
				+ up * (0.20 + 0.30 * h) * f;
		}
		if (kind == 24) {
			// The two puffs sit on either side of the zone and spread outward.
			vec3 side = (idx == 0 ? mx : -mx) * size * 0.35;
			drift = side * (1.0 + 0.8 * f) + up * ((elem == 1 ? 0.9 : 0.25) + 0.3 * h) * f;
		}
		vec2 r = rot2(c, h * 6.283 + f * (h - 0.5) * 2.0);
		world = origin + up * lift + drift + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * (0.12 + (body - 1.0) * BODY_CLEAR);
		// Smoke colour (linear values; ACES + sRGB output lifts midtones, so these read as
		// mid-greys on screen): warm soot for fire, cool haze for ice/water, dust otherwise.
		vec3 soot = vec3(0.20, 0.16, 0.15);
		vec3 mist = vec3(0.34, 0.50, 0.68);
		vec3 dust = vec3(0.27, 0.33, 0.42);
		vec3 base = dust;
		if (elem == 1) base = mix(soot, vec3(1.0, 0.45, 0.16), pow(1.0 - f, 3.0) * 0.8);
		if (elem == 2) base = mist;
		if (elem == 4) base = mix(mist, vec3(0.20, 0.42, 0.85), 0.4);
		if (kind == 9) base = vec3(0.12, 0.05, 0.20);
		if (kind == 10) base = mix(vec3(0.20, 0.10, 0.40), COLOR.rgb * 0.3, 0.3);
		if (kind == 13) base = mist;
		if (kind == 3) base = mix(dust, COLOR.rgb * 0.35, 0.3);
		if (kind == 15) base = vec3(0.26, 0.28, 0.32);
		if (kind == 22) base = mix(mix(vec3(0.62, 0.70, 0.82), COLOR.rgb * 0.6, 0.3), mix(vec3(0.20, 0.32, 0.55), COLOR.rgb * 0.4, 0.3), vfx_wash);
		if (kind == 24) {
			if (elem == 1) base = mix(vec3(0.09, 0.06, 0.05), vec3(0.6, 0.2, 0.05), pow(1.0 - f, 2.5) * 0.7);
			else if (elem == 2) base = mix(vec3(0.46, 0.62, 0.80), vec3(0.22, 0.38, 0.62), vfx_wash);
			else if (elem == 4) base = mix(vec3(0.55, 0.70, 0.84), vec3(0.25, 0.42, 0.70), vfx_wash);
			else if (elem == 0) base = vec3(0.24, 0.10, 0.38);
			else base = vec3(0.28, 0.30, 0.36);
		}
		col = base;
		alpha = pp.w * pow(1.0 - f, 1.3) * smoothstep(0.0, 0.08, f);
		// The scatter haze thickens while the body thins (it is not a puff of impact smoke).
		if (kind == 22) alpha = pp.w * smoothstep(0.08, 0.50, f) * pow(1.0 - f, 1.0);
		v_cell = (kind == 24 && elem == 1) ? 39.0 : 4.0;
	} else if (part == 6) {
		vec4 sp = scorch_params(kind, size, elem);
		float f = clamp(age / sp.y, 0.0, 1.0);
		float rr = sp.x * (0.6 + 0.4 * ease_out3(min(f * 4.0, 1.0)));
		world = origin + up * 0.06 + mx * c.x * 2.0 * rr + fwd * c.y * 2.0 * rr;
		col = sp.z > 0.5 ? vec3(0.07, 0.055, 0.045) : vec3(0.60, 0.80, 1.0);
		alpha = (sp.z > 0.5 ? 0.30 : 0.40) * pow(1.0 - f, 0.9) * (sp.x > 0.001 ? 1.0 : 0.0);
		if (sp.z > 1.5 && sp.z < 2.5) {
			// Seal: a pool of the blessing's gold under the monster it stopped.
			col = vec3(0.85, 0.48, 0.08);
			alpha = 0.62 * pow(1.0 - f, 1.2) * smoothstep(0.0, 0.08, f);
		}
		if (sp.z > 2.5) {
			// Wet sheen left by a geyser.
			col = vec3(0.05, 0.12, 0.30);
			alpha = 0.40 * pow(1.0 - f, 1.1);
		}
		if (kind == 24 && elem == 2) {
			// The frost pane a blizzard leaves: pale body on dark soil, deep blue on snow.
			col = mix(vec3(0.52, 0.70, 0.88), vec3(0.22, 0.44, 0.72), vfx_wash);
			alpha = 0.5 * pow(1.0 - f, 1.3);
			v_cell = 41.0;
			vec2 r = rot2(c, seed * 6.283);
			world = origin + up * 0.06 + (mx * r.x + fwd * r.y) * 2.0 * rr;
		}
		v_edge = 1.0;
		if (v_cell < 30.0) v_cell = -1.0;
	} else {
		// Debris x4: dark chunks with weight.
		float h1 = hash11(seed * 7.3 + float(idx));
		float h2 = hash11(seed * 11.9 + float(idx) * 1.3);
		float h3 = hash11(seed * 19.7 + float(idx) * 0.9);
		float life = 0.0;
		float s = 0.0;
		vec3 vel = vec3(0.0);
		vec3 start = origin + up * 0.15;
		float g = 10.0;
		if (kind == 1) {
			// Clods out of the splash crater.
			life = 0.55 + 0.25 * h3;
			float ang = (float(idx) + h1 * 0.9) * 1.5708;
			vel = (mx * sin(ang) + fwd * cos(ang)) * (1.0 + 1.6 * h2) * clamp(size, 0.6, 1.6) + up * (2.6 + 2.4 * h1);
			s = 0.055 + 0.05 * h2;
			col = mix(vec3(0.05, 0.04, 0.035), elem_deep(elem), elem == 0 ? 0.0 : 0.3);
		} else if (kind == 20) {
			// Chips off the body, flung along the blade's travel.
			life = 0.45 + 0.2 * h3;
			vel = normalize(fwd * (0.6 + 0.4 * h2) + mx * (h1 - 0.5) * 1.1 + up * (0.4 + 0.6 * h2)) * (1.8 + 1.5 * h1) * clamp(size, 0.6, 1.9);
			start = origin;
			s = 0.045 + 0.04 * h2;
			g = 8.0;
			col = vec3(0.06, 0.045, 0.04);
		} else if (kind == 3 && size >= 1.25) {
			// A big body comes apart: pieces thrown out and up.
			life = 0.7 + 0.3 * h3;
			float ang = (float(idx) + h1 * 0.9) * 1.5708 + seed * 6.283;
			vel = (mx * sin(ang) + fwd * cos(ang)) * (1.2 + 1.4 * h2) * size + up * (3.0 + 2.5 * h1) * size;
			start = origin + up * (0.4 * size);
			s = (0.09 + 0.07 * h2) * size;
			col = mix(vec3(0.05, 0.04, 0.045), COLOR.rgb * 0.25, 0.5);
		} else if (kind == 24 && elem == 1) {
			// Rock out of the last gout.
			life = 0.8 + 0.3 * h3;
			float ang = (float(idx) + h1 * 0.9) * 1.5708 + seed * 6.283;
			vel = (mx * sin(ang) + fwd * cos(ang)) * (1.0 + 1.5 * h2) * size * 0.45 + up * (3.5 + 3.0 * h1);
			start = origin + (mx * sin(ang) + fwd * cos(ang)) * size * 0.4 + up * 0.2;
			s = 0.08 + 0.07 * h2;
			col = vec3(0.05, 0.03, 0.025);
		}
		float a = 0.0;
		vec3 at = origin;
		float rot = h1 * 6.283;
		if (life > 0.0 && age < life) {
			at = start + vel * age + up * (-0.5 * g * age * age);
			rot += age * (4.0 + 6.0 * h2) * (h3 < 0.5 ? -1.0 : 1.0);
			a = (at.y > 0.0 ? 1.0 : 0.0) * 0.95 * (1.0 - smoothstep(0.7, 1.0, age / life));
		}
		vec2 r = rot2(c, rot);
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * (0.2 + (body - 1.0) * BODY_CLEAR);
		if (a <= 0.0) world = origin;
		alpha = a;
		v_cell = (kind == 20) ? 46.0 : 22.0;
	}
	v_tint = vec4(col, alpha);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	if (v_cell < -0.5) {
		float d = length(v_plane);
		a = 1.0 - smoothstep(0.25, 1.0, d);
	} else if (v_cell > 31.5) {
		a = texture(zone_sprites, cell_uv(int(v_cell + 0.5) - 32, UV)).a;
	} else if (v_cell > 15.5) {
		a = texture(skill_sprites, cell_uv(int(v_cell + 0.5) - 16, UV)).a;
	} else {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	}
	ALBEDO = v_tint.rgb;
	ALPHA = a * v_tint.a;
}
