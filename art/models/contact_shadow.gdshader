shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled, specular_disabled;
// Contact shadow under an actor: a dense core where the feet touch the ground that
// falls off quickly, plus a wide faint penumbra. Keeps bodies grounded even where the
// directional shadow is thrown away from the camera.
uniform float opacity : hint_range(0.0, 1.0) = 0.4;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float radius = length(p);
	float core = 1.0 - smoothstep(0.08, 0.62, radius);
	float penumbra = 1.0 - smoothstep(0.30, 1.0, radius);
	ALBEDO = vec3(0.010, 0.022, 0.034);
	ALPHA = (core * 0.75 + penumbra * 0.45) * opacity;
}
