shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Looping status markers attached to a body (replacement for the old cone groups).
// The mesh is a handful of unit quads whose UV2 says which part/index each is:
//   kind 0 burn:  flame tongues flickering and rising around the hips
//   kind 1 frost: ice shards drifting slowly around the body with glints
//   kind 2 stun:  sparkles orbiting at head height
// MODEL_MATRIX origin = body origin; `height` places the stun ring. StellarVfx keeps
// `vfx_time` in step with the battle clock, so the loops pause with the battle.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform int kind = 0;
uniform float height = 0.9;
uniform float vfx_time = 0.0;

varying vec4 v_tint;
varying float v_cell;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	vec3 up = vec3(0.0, 1.0, 0.0);
	int idx = int(UV2.y + 0.5);
	float h = hash11(float(idx) * 3.1 + 0.37);
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = vec3(1.0);
	float alpha = 0.0;
	float cell = 0.0;
	if (kind == 0) {
		float cycle = 0.55 + 0.25 * h;
		float phase = fract(vfx_time / cycle + h);
		float ang = float(idx) * 2.094 + vfx_time * 0.8;
		vec3 at = origin + vec3(cos(ang), 0.0, sin(ang)) * 0.22 + up * (0.12 + phase * 0.55);
		float s = (0.22 + 0.08 * h) * (1.0 - phase * 0.55);
		vec2 r = rot2(c, sin(vfx_time * 9.0 + h * 6.0) * 0.25);
		world = at + (cam_right * r.x + cam_up * (r.y + 0.3)) * s - cam_fwd * 0.2;
		col = mix(vec3(1.0, 0.45, 0.12), vec3(1.0, 0.85, 0.45), 1.0 - phase);
		alpha = pow(sin(phase * 3.14159), 0.7) * 0.9;
		cell = 5.0;
	} else if (kind == 1) {
		float ang = float(idx) * 1.571 + sin(vfx_time * 0.7 + h) * 0.3;
		float bob = sin(vfx_time * 2.0 + float(idx)) * 0.04;
		vec3 at = origin + vec3(cos(ang), 0.0, sin(ang)) * 0.30 + up * (0.25 + h * 0.35 + bob);
		float s = 0.16 + 0.07 * h;
		vec2 r = rot2(c, h * 6.283 + sin(vfx_time + h) * 0.2);
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.2;
		float glint = pow(max(sin(vfx_time * 3.0 + h * 9.0), 0.0), 12.0);
		col = mix(vec3(0.72, 0.92, 1.0), vec3(1.0), glint);
		alpha = 0.8 + glint * 0.4;
		cell = 6.0;
	} else {
		float ang = float(idx) * 2.094 + vfx_time * 5.0;
		vec3 at = origin + vec3(cos(ang), 0.0, sin(ang)) * 0.24 + up * (height + 0.12 + sin(vfx_time * 6.0 + float(idx)) * 0.02);
		float s = 0.14 + 0.04 * h;
		vec2 r = rot2(c, vfx_time * 4.0 + h);
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.25;
		col = vec3(1.0, 0.9, 0.5);
		alpha = 0.85 + 0.15 * sin(vfx_time * 20.0 + h * 5.0);
		cell = 2.0;
	}
	v_tint = vec4(col, alpha);
	v_cell = cell;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	ALBEDO = v_tint.rgb;
	ALPHA = a * v_tint.a;
}
