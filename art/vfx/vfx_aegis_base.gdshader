shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_aegis.gdshaderinc"

// Body of the Guardian's aegis, drawn before its light: the facet edges and the burning
// crown in solid gold, and a faint gold tint on each facet (stronger on the facets seen
// edge-on) so the gem reads as cut glass, not as a wire cage. Alpha-blended, because
// additive gold on a pale plaza or on snow is just white. Linear colours.
// 1 on bright snow/ice fields: the body deepens there (see vfx_moment_mix.gdshader).
uniform float vfx_wash = 0.0;

varying float v_height;
varying float v_facing;
varying float v_cut;
varying float v_env;

void vertex() {
	float age = max(vfx_time - birth, 0.0);
	float grow = aegis_grow(age);
	v_height = VERTEX.y;
	VERTEX *= vec3(mix(0.55, 1.0, grow), mix(0.35, 1.0, grow), mix(0.55, 1.0, grow));
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_facing = abs(dot(n, normalize(INV_VIEW_MATRIX[2].xyz)));
	v_cut = aegis_cut(age);
	v_env = aegis_envelope(age) * step(0.001, grow);
}

void fragment() {
	float facet = UV2.x;
	float edge = aegis_edge(UV);
	vec2 burn = aegis_burn(v_height, v_cut, facet);
	float glass = (0.04 + 0.10 * facet) * (0.35 + 0.65 * pow(1.0 - v_facing, 1.5));
	// On a bright field thin gold lines read as a wire cage: give every facet some body
	// there and let the edges run a little wider.
	glass += 0.11 * vfx_wash;
	edge = mix(edge, sqrt(edge), 0.6 * vfx_wash);
	float a = (edge * 0.86 + glass) * burn.x + burn.y * 0.6;
	vec3 rgb = mix(vec3(0.80, 0.43, 0.07), vec3(0.95, 0.66, 0.20), clamp(burn.y + facet * 0.3, 0.0, 1.0));
	ALBEDO = mix(rgb, pow(rgb, vec3(1.6)), vfx_wash);
	ALPHA = clamp(a * (1.0 + 0.3 * vfx_wash), 0.0, 1.0) * v_env;
}
