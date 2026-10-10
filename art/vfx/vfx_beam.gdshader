shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Beams, chain lightning and ricochet traces in one MultiMesh of 16-segment strips.
//   transform: origin at the start point, -Z axis = (end - start) including its length
//   COLOR:     colour      CUSTOM: x birth  y kind (0 beam, 1 bolt, 2 ric)  z seed  w big
// Strip vertices: x = +-0.5 across, UV.x = position along the line (0 start, 1 end).
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue.
uniform float vfx_wash = 0.0;
uniform float vfx_epoch = 0.0;

varying vec4 v_tint;
varying vec3 v_info;   // kind, seed, flicker

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = -MODEL_MATRIX[2].xyz;
	float len = max(length(axis), 0.001);
	vec3 dir = axis / len;
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	vec3 side = cross(dir, cam_fwd);
	side = length(side) < 0.02 ? cam_right : normalize(side);
	vec3 lift = normalize(cross(side, dir));
	float birth = INSTANCE_CUSTOM.x;
	int kind = int(INSTANCE_CUSTOM.y + 0.5);
	float seed = INSTANCE_CUSTOM.z;
	float big = INSTANCE_CUSTOM.w;
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float dur = kind == 0 ? 0.24 : kind == 1 ? 0.22 : 0.16;
	float f = clamp(age / dur, 0.0, 1.0);
	float t = UV.x;
	float env = smoothstep(0.0, 0.12, f) * pow(1.0 - f, kind == 2 ? 1.0 : 1.5);
	float width = kind == 0 ? 0.30 * (1.0 + 0.5 * big) : kind == 1 ? 0.22 : 0.10;
	width *= 0.55 + 0.45 * env;
	float flicker = 1.0;
	vec3 world = origin + dir * t * len + side * VERTEX.x * width;
	if (kind == 1) {
		// Jagged lightning: each column jumps sideways, re-rolled a few times per frame.
		float step_t = floor(vfx_time * 36.0);
		float col_id = floor(t * 16.0 + 0.5);
		float j1 = hash21(vec2(col_id + seed * 17.0, step_t)) - 0.5;
		float j2 = hash21(vec2(col_id * 3.0 + seed * 7.0, step_t + 11.0)) - 0.5;
		float amp = 0.22 * sin(t * 3.14159) * (1.0 + big * 0.4);
		world += side * j1 * amp * 2.0 + lift * j2 * amp;
		flicker = 0.7 + 0.5 * hash11(step_t + seed * 3.0);
	} else if (kind == 2) {
		// Ricochet trace: the bright part runs from the bounce point toward the next target.
		env *= smoothstep(f - 0.1, f + 0.25, t) * (1.0 - smoothstep(f + 0.55, f + 0.9, t));
	} else {
		// Beam: a wide glowing shaft that pinches slightly at the source.
		world += side * VERTEX.x * width * (0.25 * sin(t * 3.14159));
	}
	v_tint = vec4(COLOR.rgb, env * flicker);
	v_info = vec3(float(kind), seed, t);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	int kind = int(v_info.x + 0.5);
	float core = exp(-pow(across / (kind == 1 ? 0.22 : 0.30), 2.0));
	float glow = pow(max(1.0 - across, 0.0), 2.2) * 0.45;
	float a = core + glow;
	if (kind == 0) {
		float n = texture(noise_tex, vec2(v_info.z * 2.2 - vfx_time * 3.5, v_info.y)).g;
		a *= 0.72 + 0.55 * n;
	}
	ALBEDO = mix(mix(v_tint.rgb, v_tint.rgb * v_tint.rgb * 1.25, vfx_wash * 0.6), vec3(1.0), core * 0.85);
	ALPHA = clamp(a, 0.0, 1.0) * v_tint.a * mix(1.0, 0.72, vfx_wash);
}
