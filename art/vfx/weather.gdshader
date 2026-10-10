shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Ambient weather motes (snow, embers, pollen) as soft camera-facing sprites in one
// MultiMesh. The instance transform carries position and size (scale.x); the world
// moves them. COLOR tints; the sprite is the atlas glow.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.78, 0.88, 0.94, 1.0);
uniform float brightness = 0.55;

varying vec4 v_tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// Instance scale: x = width, y = height (rain streaks stay elongated).
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = origin + cam_right * VERTEX.x * sx + cam_up * VERTEX.y * sy;
	v_tint = vec4(tint.rgb, brightness * (0.6 + 0.4 * hash11(float(INSTANCE_ID) * 0.173)));
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a = texture(sprites, cell_uv(0, UV)).a;
	ALBEDO = v_tint.rgb;
	ALPHA = a * v_tint.a;
}
