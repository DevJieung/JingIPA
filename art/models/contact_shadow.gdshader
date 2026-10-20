shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled, specular_disabled;
// Contact shadow under an actor: a dense core where the feet touch the ground that
// falls off quickly, plus a wide faint penumbra. It grounds every body now that the
// directional shadow is thrown behind-right (2026-10-18): heroes, every walking monster
// and, lighter and wider, the flyers. `soft` 1 is the shadow of a body that rides in the
// air: the core spreads out and lightens, the penumbra stays. `fade` is pushed per
// instance by StellarShading while a body dissolves, so the disc goes with it.
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
uniform float soft : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color : source_color = vec3(0.02, 0.035, 0.07);
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float radius = length(p);
	float core = 1.0 - smoothstep(0.16 + 0.22 * soft, 0.70 + 0.30 * soft, radius);
	float penumbra = 1.0 - smoothstep(0.30, 1.0, radius);
	ALBEDO = color;
	ALPHA = (core * (0.80 - 0.35 * soft) + penumbra * 0.40) * opacity * fade;
}
