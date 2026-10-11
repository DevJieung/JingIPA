shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Alpha-blended underlay of the slash arc: the second surface of the Slashes mesh, with
// the same instance data, sweep and life as vfx_slash.gdshader. It lays a deep,
// element-tinted body under the additive wake so the cut keeps a readable edge on bright
// snow and ice floors, where additive light alone washes out to the floor colour.
//   COLOR: colour   CUSTOM: x birth   y swing sign times band fraction   z seed   w element
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float vfx_time = 0.0;
uniform float vfx_wash = 0.0;
uniform float vfx_epoch = 0.0;

const float SWEEP = 0.10;
const float LIFE = 0.34;
const float MESH_BAND = 0.58;

varying vec4 v_tint;
varying vec3 v_state;   // sweep head position, along, seed

void vertex() {
	float birth = INSTANCE_CUSTOM.x;
	float packed = INSTANCE_CUSTOM.y;
	float seed = INSTANCE_CUSTOM.z;
	int elem = int(INSTANCE_CUSTOM.w + 0.5);
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float f = clamp(age / LIFE, 0.0, 1.0);
	float head = ease_out(min(age / SWEEP, 1.0));
	float along = packed < 0.0 ? 1.0 - UV.x : UV.x;
	float band = clamp(abs(packed), 0.2, MESH_BAND);
	float across = UV.y * MESH_BAND / band;
	VERTEX *= 1.0 + 0.08 * f;
	// Linear values: ACES lifts midtones, so this saturated ink reads as a clear mid
	// tone, darker than snow and lighter than a night forest floor.
	vec3 ink = elem_tint(elem) * 0.42 + COLOR.rgb * 0.10;
	v_tint = vec4(ink, pow(1.0 - f, 1.3) * mix(0.66, 0.78, vfx_wash));
	v_state = vec3(head, along, seed);
	UV = vec2(UV.x, across);
}

void fragment() {
	float head = v_state.x;
	float along = v_state.y;
	float across = UV.y;
	if (across > 1.0) discard;
	float behind = head - along;
	float wake = smoothstep(-0.015, 0.02, behind) * exp(-max(behind, 0.0) * 1.0);
	float body = pow(1.0 - across, 0.45) * (1.0 - smoothstep(0.62, 1.0, across)) * smoothstep(0.0, 0.08, across);
	// A defined outer edge keeps the fan legible at 60 px where the soft body alone blurs.
	float edge = exp(-pow((across - 0.05) / 0.045, 2.0));
	float n = texture(noise_tex, vec2(along * 3.0 + v_state.z, across * 0.6 - vfx_time * 2.0)).b;
	ALBEDO = v_tint.rgb * (1.0 - 0.35 * edge);
	ALPHA = clamp(wake * (body * (0.75 + 0.25 * n) + edge * 0.7), 0.0, 1.0) * v_tint.a;
}
