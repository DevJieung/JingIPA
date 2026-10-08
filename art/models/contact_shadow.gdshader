shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity : hint_range(0.0, 1.0) = 0.4;
void fragment() {
 float radius = length((UV - vec2(0.5)) * 2.0);
 ALBEDO = vec3(0.012, 0.028, 0.040);
 ALPHA = (1.0 - smoothstep(0.10, 0.95, radius)) * opacity;
}
