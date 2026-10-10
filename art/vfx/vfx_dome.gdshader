shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Energy dome (crystal ward activation, passive block): fresnel shell with a hex
// lattice and a rising scan band. One hemisphere mesh per dome node.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 color : source_color = vec4(0.37, 0.9, 1.0, 1.0);
uniform float birth = -10.0;
uniform float duration = 0.9;
uniform float vfx_time = 0.0;

varying float v_env;
varying float v_height;

void vertex() {
	float age = max(vfx_time - birth, 0.0);
	float f = clamp(age / duration, 0.0, 1.0);
	float rise = ease_out3(min(f * 2.2, 1.0));
	// The shell inflates from the ground and then holds while it fades.
	VERTEX *= 0.5 + 0.5 * rise;
	v_env = smoothstep(0.0, 0.08, f) * pow(1.0 - f, 1.4);
	v_height = VERTEX.y;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.4);
	vec2 huv = fract(vec2(UV.x * 6.0, UV.y * 3.0));
	float hex = texture(sprites, cell_uv(13, huv)).a;
	float scan = exp(-pow((v_height - fract(vfx_time * 0.9) * 1.1) / 0.06, 2.0));
	float a = fresnel * 0.95 + hex * 0.18 + scan * 0.35 + 0.04;
	ALBEDO = mix(color.rgb, vec3(1.0), fresnel * 0.4 + scan * 0.3);
	ALPHA = clamp(a, 0.0, 1.0) * v_env;
}
