// Shared helpers for the battle VFX shaders (GLES3 / GL Compatibility safe).
// Atlas layout: see tools/vfx/gen_vfx_textures.py (4x4 cells of 256px).
//  0 glow  1 star4  2 sparkle6  3 ring  4 smoke  5 flame  6 shard  7 lightning
//  8 drop  9 arrow 10 tracer   11 crescent 12 rune 13 hex 14 ember 15 shock arc
// Element codes: 0 none, 1 fire, 2 ice, 3 elec, 4 water.

vec2 cell_uv(int cell, vec2 uv) {
	vec2 c = vec2(float(cell % 4), float(cell / 4));
	// Inset by one texel so linear filtering never bleeds a neighbouring cell.
	return (c + clamp(uv, 0.004, 0.996)) * 0.25;
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float ease_out(float x) {
	x = clamp(x, 0.0, 1.0);
	return 1.0 - (1.0 - x) * (1.0 - x);
}

float ease_out3(float x) {
	x = clamp(x, 0.0, 1.0);
	float y = 1.0 - x;
	return 1.0 - y * y * y;
}

// Saturated glow colour of an element (particles, trails, rings).
vec3 elem_tint(int e) {
	if (e == 1) return vec3(1.0, 0.46, 0.16);
	if (e == 2) return vec3(0.50, 0.87, 1.0);
	if (e == 3) return vec3(1.0, 0.85, 0.30);
	if (e == 4) return vec3(0.24, 0.56, 1.0);
	return vec3(0.86, 0.90, 0.96);
}

// Hot core colour of an element (flash centres, bullet cores).
vec3 elem_hot(int e) {
	if (e == 1) return vec3(1.0, 0.95, 0.72);
	if (e == 2) return vec3(0.94, 0.99, 1.0);
	if (e == 3) return vec3(1.0, 1.0, 0.86);
	if (e == 4) return vec3(0.84, 0.95, 1.0);
	return vec3(1.0, 0.97, 0.90);
}

int spark_cell(int e) {
	if (e == 1) return 14;
	if (e == 2) return 6;
	if (e == 3) return 7;
	if (e == 4) return 8;
	return 10;
}

int mote_cell(int e) {
	if (e == 1) return 14;
	if (e == 2) return 6;
	if (e == 3) return 2;
	if (e == 4) return 8;
	return 0;
}

// Rotate a 2D corner offset.
vec2 rot2(vec2 p, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}
