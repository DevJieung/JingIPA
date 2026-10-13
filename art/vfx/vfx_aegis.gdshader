shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_aegis.gdshaderinc"

// Light of the Guardian's aegis (see the include). The gem's gold body is painted by
// vfx_aegis_base.gdshader; this layer adds only light: facets that flare as they turn
// edge-on to the camera while the gem slowly rotates, a glint climbing each facet, a hot
// line on the edges, and the bright crown where the gem is burning down. Facets that face
// the camera stay clear, so the crystal and the bodies around it are never hidden.
uniform vec4 color : source_color = vec4(1.0, 0.72, 0.25, 1.0);
// 1 on bright snow/ice fields (see vfx_moment.gdshader).
uniform float vfx_wash = 0.0;

varying float v_height;
varying float v_facing;
varying float v_cut;
varying float v_env;
varying float v_glint;   // phase of the glint that climbs the facets (time stays in vertex())

void vertex() {
	float age = max(vfx_time - birth, 0.0);
	float grow = aegis_grow(age);
	v_glint = fract(age * 0.42);
	v_height = VERTEX.y;
	VERTEX *= vec3(mix(0.55, 1.0, grow), mix(0.35, 1.0, grow), mix(0.55, 1.0, grow));
	// Orthographic view: the direction to the camera is the same everywhere.
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_facing = abs(dot(n, normalize(INV_VIEW_MATRIX[2].xyz)));
	v_cut = aegis_cut(age);
	v_env = aegis_envelope(age) * step(0.001, grow);
}

void fragment() {
	float facet = UV2.x;
	float edge = aegis_edge(UV);
	float fresnel = pow(1.0 - v_facing, 2.2);
	vec2 burn = aegis_burn(v_height, v_cut, facet);
	float glint = exp(-pow((v_height - fract(v_glint + facet * 0.37) * 1.4 + 0.2) / 0.09, 2.0));
	float a = (edge * 0.34 + fresnel * 0.46 + glint * 0.14) * burn.x + burn.y * 0.85;
	vec3 rgb = mix(color.rgb, vec3(1.0, 0.96, 0.84), clamp(edge * 0.3 + burn.y * 0.7, 0.0, 1.0));
	ALBEDO = mix(rgb, rgb * rgb * 1.25, vfx_wash * 0.5);
	ALPHA = clamp(a, 0.0, 1.0) * v_env * mix(1.0, 0.78, vfx_wash);
}
