shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Sword slash arcs: an arc strip mesh placed by the adapter facing (MODEL transform),
// swept by a bright head that leaves a fading wake. One MultiMesh.
//   COLOR: colour   CUSTOM: x birth  y swing sign (+1 left-to-right, -1 reverse)  z seed  w element
// Arc mesh: UV.x along the arc 0..1, UV.y across (0 outer edge, 1 inner edge).
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue.
uniform float vfx_wash = 0.0;
uniform float vfx_epoch = 0.0;

varying vec4 v_tint;
varying vec3 v_state;   // sweep head position, fade, seed

void vertex() {
	float birth = INSTANCE_CUSTOM.x;
	float sign_value = INSTANCE_CUSTOM.y;
	float seed = INSTANCE_CUSTOM.z;
	int elem = int(INSTANCE_CUSTOM.w + 0.5);
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float dur = 0.22;
	float f = clamp(age / dur, 0.0, 1.0);
	float head = ease_out(min(f * 1.6, 1.0));
	// Reverse swings sweep the arc from the other end.
	float along = sign_value < 0.0 ? 1.0 - UV.x : UV.x;
	// The wake widens slightly as it dissipates.
	VERTEX *= 1.0 + 0.12 * f;
	v_tint = vec4(mix(COLOR.rgb, elem_hot(elem), 0.45), pow(1.0 - f, 1.2));
	v_state = vec3(head, along, seed);
}

void fragment() {
	float head = v_state.x;
	float along = v_state.y;
	float wake = smoothstep(head - 0.55, head - 0.04, along) * (1.0 - smoothstep(head - 0.03, head + 0.02, along));
	float tip = exp(-pow((along - head + 0.02) / 0.03, 2.0));
	float across = UV.y;
	float edge = pow(1.0 - across, 0.6) * (1.0 - smoothstep(0.75, 1.0, across));
	float n = texture(noise_tex, vec2(along * 3.0 + v_state.z, across * 0.5 - vfx_time * 2.0)).b;
	float a = (wake * (0.55 + 0.45 * n) + tip * 1.4) * edge;
	ALBEDO = mix(mix(v_tint.rgb, v_tint.rgb * v_tint.rgb * 1.25, vfx_wash * 0.6), vec3(1.0), tip * 0.8 + (1.0 - across) * 0.35);
	ALPHA = clamp(a, 0.0, 1.0) * v_tint.a * mix(1.0, 0.7, vfx_wash);
}
