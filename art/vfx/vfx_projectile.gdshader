shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Projectile layer drawn as one MultiMesh. Every instance is one live bullet:
//   transform: origin at the bullet, -Z along its velocity (unit basis)
//   COLOR:     hero colour
//   CUSTOM:    x shape (0 tracer,1 arrow,2 shell,3 bead,4 orb,5 crescent)
//              y trail length (world units)   z size (world units)   w element
// Mesh parts (UV2.x): 0 trail strip, 1 glow billboard, 2 core sprite, 3 sparks (UV2.y index).
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue.
uniform float vfx_wash = 0.0;

varying vec4 v_tint;
varying float v_cell;
varying vec2 v_local;

int shape_cell(int shape) {
	if (shape == 1) return 9;
	if (shape == 2) return 0;
	if (shape == 3) return 0;
	if (shape == 4) return 2;
	if (shape == 5) return 11;
	return 10;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 fwd = normalize(-MODEL_MATRIX[2].xyz);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	vec3 side = cross(fwd, cam_fwd);
	side = length(side) < 0.02 ? cam_right : normalize(side);
	vec3 lift = normalize(cross(side, fwd));
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	int shape = int(INSTANCE_CUSTOM.x + 0.5);
	float trail_len = INSTANCE_CUSTOM.y;
	float size = INSTANCE_CUSTOM.z;
	int elem = int(INSTANCE_CUSTOM.w + 0.5);
	float seed = float(INSTANCE_ID) * 0.618034 + 0.137;
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = COLOR.rgb;
	float alpha = 1.0;
	float cell = 0.0;
	v_local = c * 2.0;
	if (part == 0) {
		// Ribbon trail: a tapered strip behind the head. Elements wobble it.
		float t = UV.y;
		float w = size * 1.5 * (1.0 - t * t) * (shape == 2 ? 1.5 : 1.0);
		world = origin - fwd * t * trail_len + side * c.x * w;
		if (elem == 3) world += side * sin(t * 38.0 + vfx_time * 70.0 + seed * 9.0) * size * 0.35 * t;
		if (elem == 1) world += lift * sin(t * 12.0 - vfx_time * 20.0 + seed * 5.0) * size * 0.25 * t;
		if (elem == 4) world += side * sin(t * 20.0 - vfx_time * 30.0 + seed) * size * 0.2 * t;
		col = mix(col, elem_tint(elem), 0.6);
		alpha = pow(1.0 - t, 1.3) * (shape == 2 ? 0.6 : 1.0);
		cell = -1.0;
	} else if (part == 1) {
		// Soft glow around the head, in the hero's colour.
		float s = size * (shape == 2 ? 4.4 : 3.4);
		world = origin + (cam_right * c.x + cam_up * c.y) * s - cam_fwd * 0.2;
		alpha = shape == 2 ? 0.85 : 0.7;
		cell = 0.0;
	} else if (part == 2) {
		// Hot core sprite aligned with the flight direction (sprite "up" = forward).
		float len = size * (shape == 1 ? 3.6 : shape == 5 ? 2.6 : shape == 2 ? 1.9 : 2.8);
		float wid = size * (shape == 5 ? 2.6 : shape == 2 ? 1.9 : shape == 1 ? 1.2 : 1.05);
		world = origin + fwd * c.y * len + side * c.x * wid - cam_fwd * 0.22;
		if (shape == 4) {
			// Electric orb rotates and crackles.
			vec2 r = rot2(c, vfx_time * 9.0 + seed);
			world = origin + (cam_right * r.x + cam_up * r.y) * size * 2.4 - cam_fwd * 0.22;
		}
		cell = float(shape_cell(shape));
		col = mix(elem_hot(elem), vec3(1.0), 0.35);
		alpha = 1.0;
	} else {
		// Element motes streaming off the trail (fire embers rise, drops fall, shards drift).
		float cycle = 1.4 + 0.5 * hash11(seed + float(idx) * 3.1);
		float life = fract(vfx_time * cycle + hash11(seed * 1.7 + float(idx)));
		float back = (0.15 + life * 0.85) * trail_len;
		float swing = sin(seed * 7.0 + float(idx) * 2.1 + vfx_time * 3.0) * size * (0.8 + life * 1.6);
		vec3 lat = (idx % 2 == 0) ? side : lift;
		float vert = elem == 1 ? life * size * 2.2 : (elem == 4 ? -life * life * size * 2.5 : sin(life * 6.283 + float(idx)) * size * 0.4);
		vec3 at = origin - fwd * back + lat * swing + lift * vert;
		float s = size * (1.1 - life * 0.7) * (elem == 2 ? 1.6 : elem == 3 ? 1.7 : 1.0);
		vec2 r = rot2(c, hash11(seed + float(idx)) * 6.283 + (elem == 2 ? vfx_time * 2.0 : 0.0));
		world = at + (cam_right * r.x + cam_up * r.y) * s - cam_fwd * 0.15;
		cell = float(spark_cell(elem));
		if (elem == 0 && idx > 1) s = 0.0;
		col = mix(elem_tint(elem), elem_hot(elem), 0.3);
		alpha = (1.0 - life) * (elem == 0 ? 0.3 : 0.85);
		if (elem == 0 && idx > 1) alpha = 0.0;
	}
	v_tint = vec4(col, alpha);
	v_cell = cell;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	if (v_cell < -0.5) {
		float across = abs(v_local.x);
		a = 1.0 - across * across;
		a = a * a;
	} else {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	}
	ALBEDO = mix(v_tint.rgb, v_tint.rgb * v_tint.rgb * 1.25, vfx_wash * 0.6);
	ALPHA = (a * v_tint.a) * mix(1.0, 0.66, vfx_wash);
}
