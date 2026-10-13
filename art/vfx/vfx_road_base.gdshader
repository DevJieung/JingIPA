shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_road.gdshaderinc"

// Body of the road reveal, drawn before its light: the chevrons that mark each road, the
// runner and the road mouths in solid coral, alpha-blended so they keep their colour on a
// pale road (additive coral there is just white). Linear colour.
// 1 on bright snow/ice fields: the body deepens there (see vfx_moment_mix.gdshader).
uniform float vfx_wash = 0.0;

varying float v_rad;
varying float v_age;

void vertex() {
	v_rad = length(VERTEX.xz);
	v_age = max(vfx_time - birth, 0.0);
}

void fragment() {
	vec3 light = road_light(UV.y, UV.x * 2.0 - 1.0, v_rad, UV2.y, v_age);
	vec3 rgb = mix(vec3(0.85, 0.23, 0.09), vec3(1.0, 0.62, 0.36), light.y);
	ALBEDO = mix(rgb, pow(rgb, vec3(1.5)), vfx_wash);
	ALPHA = clamp(light.z, 0.0, 1.0) * 0.78;
}
