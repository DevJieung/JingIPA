shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Dark ground base under a landed zone so the additive runes stay legible on bright
// snow and ice. Same instance contract as vfx_zone.gdshader; caster circles skip it.
uniform float vfx_time = 0.0;

varying float v_alpha;
varying vec2 v_plane;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 mx = MODEL_MATRIX[0].xyz;
	vec3 mz = MODEL_MATRIX[2].xyz;
	float radius = max(length(mx), 0.001);
	vec3 ux = mx / radius;
	vec3 uz = mz / max(length(mz), 0.001);
	float t = INSTANCE_CUSTOM.x;
	float delay = INSTANCE_CUSTOM.y;
	bool cast = delay < -0.5;
	float landed = clamp((t - delay) / 0.15, 0.0, 1.0);
	vec2 c = VERTEX.xy;
	v_plane = c * 2.0;
	vec3 world = origin + vec3(0.0, 0.04, 0.0) + (ux * c.x + uz * c.y) * 2.0 * radius;
	v_alpha = cast ? 0.0 : landed * (0.35 + 0.25 * COLOR.a);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float d = length(v_plane);
	float a = (1.0 - smoothstep(0.55, 0.97, d));
	ALBEDO = vec3(0.02, 0.03, 0.05);
	ALPHA = a * v_alpha;
}
