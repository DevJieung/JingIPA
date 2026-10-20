// Shared helpers for the battle VFX shaders (GLES3 / GL Compatibility safe).
// Atlas layout: see tools/vfx/gen_vfx_textures.py (4x4 cells of 256px).
//  0 glow  1 star4  2 sparkle6  3 ring  4 smoke  5 flame  6 shard  7 lightning
//  8 drop  9 arrow 10 tracer   11 crescent 12 rune 13 hex 14 ember 15 shock arc
// Shaders that read more than one atlas number their cells in ranges: 0..15 the battle
// atlas, 16..31 the skill atlas (skill_sprites.png: 16 star sigil, 17 light pillar,
// 18 ground cracks, 19 crack glow, 20 comet tail, 21 eight-ray flare, 22 debris chunk,
// 23 fog wisp, 24 boss rune, 25 thorn ring, 26 glow disc, 27 star streak, 28 crest,
// 30 eclipse corona, 31 glory rays) and 32..47 the zone atlas (zone_sprites.png, 2026-10-17:
// 32 vortex veil, 33 ice spike, 34 snowflake, 35 lava gout, 36 spray column, 37 card,
// 38 meteor head, 39 smoke trail, 40 rime cluster, 41 frost disc, 42 whirlpool,
// 43 strike bolt, 44 magma cracks, 45 ray burst, 46 debris shard, 47 glow column).
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

float ease_in(float x) {
	x = clamp(x, 0.0, 1.0);
	return x * x;
}

// Snap with overshoot and settle: 0 -> 1.18 at a third of the way -> 1 (a "pop").
float overshoot(float x) {
	x = clamp(x, 0.0, 1.0);
	float y = x - 1.0;
	return 1.0 + 2.70158 * y * y * y + 1.70158 * y * y;
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

// Deep, saturated body colour of an element for alpha-blended layers (linear values:
// ACES and the sRGB output lift them, so these read as rich mid-tones on screen).
vec3 elem_deep(int e) {
	if (e == 1) return vec3(0.55, 0.12, 0.02);
	if (e == 2) return vec3(0.22, 0.48, 0.72);
	if (e == 3) return vec3(0.50, 0.40, 0.06);
	if (e == 4) return vec3(0.06, 0.22, 0.60);
	return vec3(0.28, 0.14, 0.46);
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
