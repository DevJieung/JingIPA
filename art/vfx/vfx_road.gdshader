shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_road.gdshaderinc"

// Light of the road reveal (see the include).
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.48, 1.0);
// 1 on bright snow/ice fields (see vfx_moment.gdshader).
uniform float vfx_wash = 0.0;

varying float v_rad;
varying float v_age;

void vertex() {
	v_rad = length(VERTEX.xz);
	v_age = max(vfx_time - birth, 0.0);
}

void fragment() {
	vec3 light = road_light(UV.y, UV.x * 2.0 - 1.0, v_rad, UV2.y, v_age);
	vec3 rgb = mix(color.rgb, vec3(1.0, 0.97, 0.90), light.y * 0.85);
	ALBEDO = mix(rgb, rgb * rgb * 1.25, vfx_wash * 0.5);
	ALPHA = clamp(light.x, 0.0, 1.0) * mix(1.0, 0.75, vfx_wash);
}
