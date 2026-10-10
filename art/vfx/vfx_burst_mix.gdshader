shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Alpha-blended layer of the burst MultiMesh: smoke/mist puffs and ground scorch.
// Same instance contract as vfx_burst.gdshader. Parts (UV2.x): 4 puff billboard, 6 ground scorch.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
uniform float vfx_epoch = 0.0;

varying vec4 v_tint;
varying float v_cell;
varying vec2 v_plane;
varying float v_edge;

float kind_lift(int k, float size) {
	if (k == 0) return 0.5;
	if (k == 1) return 0.4;
	if (k == 3) return 0.45;
	if (k == 4) return 0.7;
	if (k == 7) return 0.4;
	if (k == 8) return size;
	if (k == 9) return 0.3;
	if (k == 10) return 0.3;
	if (k == 11) return 0.3;
	if (k == 12) return 0.5;
	if (k == 13) return 0.4;
	if (k == 14) return 0.6;
	return 0.0;
}

// size0, size1, duration, alpha
vec4 puff_params(int k, float size) {
	if (k == 0) return vec4(0.12, 0.32, 0.40, 0.18);
	if (k == 1) return vec4(0.26, 0.80, 0.65, 0.22);
	if (k == 3) return vec4(0.24, 0.70, 0.80, 0.26);
	if (k == 7) return vec4(0.16, 0.40, 0.70, 0.18);
	if (k == 10) return vec4(0.28, 0.70, 0.65, 0.24);
	if (k == 11) return vec4(0.32, 1.00, 0.80, 0.30);
	if (k == 12) return vec4(0.70, 2.20, 1.00, 0.40);
	if (k == 13) return vec4(1.10, 3.40, 1.20, 0.26);
	if (k == 15) return vec4(0.12, 0.42, 0.52, 0.26);
	return vec4(0.0, 0.0, 0.1, 0.0);
}

// radius, duration, darkness (1 dark, 0 bright frost), unused
vec4 scorch_params(int k, float size) {
	if (k == 11) return vec4(size * 0.9, 1.00, 1.0, 0.0);
	if (k == 12) return vec4(size * 0.80, 1.25, 1.0, 0.0);
	if (k == 13) return vec4(size * 0.55, 1.35, 0.0, 0.0);
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
	float lift = kind_lift(kind, size);
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	v_plane = c * 2.0;
	v_edge = 0.0;
	if (part == 4) {
		vec4 pp = puff_params(kind, size);
		float f = clamp(age / pp.z, 0.0, 1.0);
		float h = hash11(seed * 4.1 + float(idx));
		float s = mix(pp.x, pp.y, ease_out3(f)) * (0.85 + 0.3 * h);
		vec3 drift = (kind == 15 ? fwd * 0.42 : fwd * 0.08) * f + up * (0.25 + 0.2 * h) * f;
		if (kind == 13 || kind == 7) drift = up * 0.12 * f;
		vec2 r = rot2(c, h * 6.283 + f * (h - 0.5) * 2.0);
		world = origin + up * lift + drift + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.12;
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
		col = base;
		alpha = pp.w * pow(1.0 - f, 1.3) * smoothstep(0.0, 0.08, f);
		v_cell = 4.0;
	} else {
		vec4 sp = scorch_params(kind, size);
		float f = clamp(age / sp.y, 0.0, 1.0);
		float rr = sp.x * (0.6 + 0.4 * ease_out3(min(f * 4.0, 1.0)));
		world = origin + up * 0.06 + mx * c.x * 2.0 * rr + fwd * c.y * 2.0 * rr;
		col = sp.z > 0.5 ? vec3(0.07, 0.055, 0.045) : vec3(0.60, 0.80, 1.0);
		alpha = (sp.z > 0.5 ? 0.30 : 0.40) * pow(1.0 - f, 0.9) * (sp.x > 0.001 ? 1.0 : 0.0);
		v_edge = 1.0;
		v_cell = -1.0;
	}
	v_tint = vec4(col, alpha);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	if (v_cell < -0.5) {
		float d = length(v_plane);
		a = 1.0 - smoothstep(0.25, 1.0, d);
	} else {
		a = texture(sprites, cell_uv(4, UV)).a;
	}
	ALBEDO = v_tint.rgb;
	ALPHA = a * v_tint.a;
}
