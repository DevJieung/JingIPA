// Shared by vfx_aegis.gdshader (additive light) and vfx_aegis_base.gdshader (ink underlay):
// the Guardian's aegis, a faceted gem of light around the revived crystal.
//   mesh (StellarVfx._aegis_mesh): unit height, unit base radius; every triangle is one
//   facet with its own flat normal. UV = two barycentric weights (the edge lines),
//   UV2.x = a hash per facet.
//   birth: effect clock at the arena_revive event    duration: seconds the crystal is safe
// Timeline: the gem snaps out of the flash (FL) with a small overshoot, holds whole until
// HOLD, then burns down from its tip so that the wall still standing is the time left;
// the last facet goes out exactly at `duration`. Each facet breaks off at its own height,
// so the burning edge is a jagged crown, and the gem blinks through its last second.
uniform float birth = -100.0;
uniform float duration = 5.0;
uniform float vfx_time = 0.0;

const float FL = 0.26;      // the revival's flash (StellarVfx.REVIVE_FLASH)
const float HOLD = 1.06;

float aegis_seg(float a, float b, float x) {
	return clamp((x - a) / (b - a), 0.0, 1.0);
}

// Scale of the shell while it forms (0 before the flash).
float aegis_grow(float age) {
	if (age < FL) return 0.0;
	float x = aegis_seg(FL, FL + 0.32, age) - 1.0;
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x;
}

// Height (0..1 of the gem) above which the shell has already burned away.
float aegis_cut(float age) {
	return mix(1.16, -0.09, aegis_seg(HOLD, max(duration, HOLD + 0.1), age));
}

float aegis_envelope(float age) {
	float e = step(FL, age) * (1.0 - smoothstep(duration - 0.04, duration, age));
	return e * (1.0 - 0.42 * step(duration - 1.0, age) * step(0.5, fract((duration - age) * 5.0)));
}

// x: 1 below the facet's own cut line   y: the bright line where it is burning
vec2 aegis_burn(float height, float cut, float facet) {
	float line = cut + (facet - 0.5) * 0.13;
	float below = 1.0 - smoothstep(line - 0.006, line + 0.006, height);
	return vec2(below, exp(-pow((line - height) / 0.05, 2.0)) * below);
}

float aegis_edge(vec2 uv) {
	float m = min(uv.x, min(uv.y, 1.0 - uv.x - uv.y));
	return exp(-pow(m / 0.055, 2.0));
}
