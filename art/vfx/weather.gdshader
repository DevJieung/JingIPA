shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Ambient weather motes (snow, rain, embers, ash, pollen, fireflies, dust) as soft
// camera-facing sprites in one MultiMesh. The instance transform carries a position and
// a size (scale.x, scale.y).
// Two ways to move them:
//   box == 0   the world writes every transform each frame (the legacy battle map).
//   box  > 0   the motes are placed once inside `box`; this shader carries them along
//              `drift` and wraps them, so the world only sets `time` (the arena).
// opacity 0 adds light (glowing motes); 1 covers what is behind (ash, dark dust).
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.78, 0.88, 0.94, 1.0);
uniform float brightness = 0.55;
uniform float opacity = 0.0;
uniform int sprite = 0;
uniform float time = 0.0;
uniform vec3 drift = vec3(0.0);
uniform vec3 box = vec3(0.0);
uniform vec3 box_origin = vec3(0.0);
uniform float sway = 0.0;
uniform float twinkle = 0.0;
uniform float stretch = 1.0;

varying vec4 v_tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// Instance scale: x = width, y = height (rain streaks stay elongated).
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float id = float(INSTANCE_ID);
	float pace = 0.72 + 0.56 * hash11(id * 0.37 + 1.0);
	float fade = 1.0;
	if (box.x > 0.0) {
		vec3 moved = origin + drift * time * pace;
		moved.x += sin(time * 0.61 * pace + id * 1.3) * sway;
		moved.z += cos(time * 0.47 * pace + id * 2.1) * sway;
		vec3 inside = mod(moved - box_origin, box);
		origin = box_origin + inside;
		// Motes ease in and out at the ends of their travel instead of popping.
		float along = abs(drift.y) > 0.001 ? inside.y / box.y : inside.x / box.x;
		fade = smoothstep(0.0, 0.14, along) * (1.0 - smoothstep(0.86, 1.0, along));
	}
	float flicker = mix(1.0, 0.5 + 0.5 * sin(time * 2.6 * pace + id * 12.9), twinkle);
	v_tint = vec4(tint.rgb, brightness * (0.6 + 0.4 * hash11(id * 0.173)) * fade * flicker);
	vec3 centre = (VIEW_MATRIX * vec4(origin, 1.0)).xyz;
	vec2 up = vec2(0.0, 1.0);
	if (stretch > 1.001) {
		vec2 fall = (mat3(VIEW_MATRIX) * drift).xy;
		if (dot(fall, fall) > 0.0001) up = normalize(fall);
	}
	vec2 right = vec2(up.y, -up.x);
	VERTEX = centre + vec3(right * VERTEX.x * sx + up * VERTEX.y * sy * stretch, 0.0);
}

void fragment() {
	float a = texture(sprites, cell_uv(sprite, UV)).a * v_tint.a;
	ALBEDO = v_tint.rgb * a;
	ALPHA = a * opacity;
}
