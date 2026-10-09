shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float strength = 0.0;
uniform float flow_time = 0.0;
void fragment() {
	float ripple = 0.72 + 0.28 * sin(UV.x * 48.0 - flow_time * 64.0);
	float edge = pow(max(0.0, 1.0 - UV.x), 0.65);
	ALBEDO = vec3(0.15, 0.70, 0.98);
	EMISSION = vec3(0.08, 0.32, 0.42);
	ALPHA = strength * 0.48 * ripple * edge;
}
