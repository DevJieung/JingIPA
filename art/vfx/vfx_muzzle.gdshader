shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Muzzle release layer, polled every frame from each hero adapter's
// weapon_transform() / fire_strength(). One MultiMesh instance per live socket.
//   transform: the weapon socket (origin = mouth, -Z = forward)
//   COLOR:     effect colour (character accent blended with element)
//   CUSTOM:    x weapon (0 rifle,1 bow,2 cast,3 artillery,4 sword,5 tool)
//              y strength 1 -> 0     z seed      w element
// Parts (UV2.x): 0 core star, 1 glow, 2 forward streak, 3 forward disc/ring, 4 sparks x6.
uniform sampler2D sprites : source_color, filter_linear_mipmap, repeat_disable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue.
uniform float vfx_wash = 0.0;

varying vec4 v_tint;
varying float v_cell;
varying vec2 v_local;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 fwd = normalize(-MODEL_MATRIX[2].xyz);
	vec3 sx = normalize(MODEL_MATRIX[0].xyz);
	vec3 sy = normalize(MODEL_MATRIX[1].xyz);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	vec3 side = cross(fwd, cam_fwd);
	side = length(side) < 0.02 ? cam_right : normalize(side);
	int part = int(UV2.x + 0.5);
	int idx = int(UV2.y + 0.5);
	int weapon = int(INSTANCE_CUSTOM.x + 0.5);
	float s = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	float seed = INSTANCE_CUSTOM.z;
	int elem = int(INSTANCE_CUSTOM.w + 0.5);
	float k = 1.0 - s;   // 0 at release, 1 when spent
	vec2 c = VERTEX.xy;
	vec3 world = origin;
	vec3 col = COLOR.rgb;
	float alpha = 0.0;
	float cell = 0.0;
	v_local = c * 2.0;
	bool rifle = weapon == 0;
	bool bow = weapon == 1;
	bool cast = weapon == 2;
	bool artillery = weapon == 3;
	bool sword = weapon == 4;
	bool tool = weapon == 5;
	if (part == 0) {
		float size = rifle ? 0.40 : bow ? 0.20 : cast ? 0.34 : artillery ? 0.50 : sword ? 0.24 : 0.22;
		size *= 0.7 + 0.5 * k;
		vec2 r = rot2(c, seed * 6.283 + (cast ? vfx_time * 4.0 : 0.0));
		world = origin + fwd * (rifle || artillery ? 0.08 : 0.0) + (cam_right * r.x + cam_up * r.y) * size - cam_fwd * 0.3;
		cell = (cast || tool || elem == 3) ? 2.0 : 1.0;
		col = mix(elem_hot(elem), vec3(1.0), 0.5);
		alpha = pow(s, 0.8);
	} else if (part == 1) {
		float size = rifle ? 0.70 : bow ? 0.42 : cast ? 0.85 : artillery ? 1.0 : sword ? 0.38 : 0.34;
		size *= 0.8 + 0.4 * k;
		world = origin + fwd * (rifle || artillery ? 0.12 : 0.0) + (cam_right * c.x + cam_up * c.y) * size - cam_fwd * 0.25;
		cell = 0.0;
		alpha = pow(s, 1.1) * (cast ? 0.8 : 0.65);
	} else if (part == 2) {
		// Streak along the barrel: rifle muzzle flame, bow release line, artillery pressure cone.
		float len = rifle ? 0.62 : bow ? 1.05 : artillery ? 1.15 : 0.0;
		float wid = rifle ? 0.19 : bow ? 0.045 : artillery ? 0.42 : 0.0;
		len *= 0.8 + 0.6 * k;
		wid *= 1.0 - 0.3 * k;
		float t = UV.y;   // 0 at mouth, 1 at tip
		float taper = artillery ? (0.35 + 0.9 * t) : (1.0 - t * t * 0.85);
		world = origin + fwd * (0.02 + t * len) + side * c.x * wid * taper - cam_fwd * 0.2;
		if (artillery) world += side * sin(t * 18.0 - vfx_time * 50.0 + seed * 6.0) * 0.03 * t;
		cell = -1.0;
		col = mix(elem_hot(elem), COLOR.rgb, bow ? 0.1 : 0.4);
		alpha = pow(s, 0.9) * (1.0 - t) * (len > 0.001 ? 1.0 : 0.0) * (bow ? 1.0 : 0.9);
	} else if (part == 3) {
		// Rune disc for casters (horizontal under the hand) and pressure ring for artillery.
		float size = cast ? 0.78 : artillery ? 0.55 : 0.0;
		size *= 0.5 + 0.7 * k;
		vec2 r = rot2(c, (cast ? -vfx_time * 2.5 : 0.0) + seed * 6.283);
		if (cast) {
			world = origin + sx * r.x * size + fwd * r.y * size + sy * 0.02;
			cell = 12.0;
		} else {
			world = origin + fwd * (0.25 + 0.45 * k) + sx * r.x * size + sy * r.y * size;
			cell = 3.0;
		}
		alpha = pow(s, 0.7) * (size > 0.001 ? 1.0 : 0.0) * 0.95;
		col = mix(COLOR.rgb, vec3(1.0), 0.25);
	} else {
		int count = rifle ? 5 : bow ? 3 : cast ? 6 : artillery ? 6 : sword ? 4 : 6;
		float h1 = hash11(seed * 13.0 + float(idx));
		float h2 = hash11(seed * 31.0 + float(idx) * 1.3);
		vec3 dir;
		if (cast) {
			float ang = float(idx) / 6.0 * 6.283 + vfx_time * 1.5;
			dir = normalize(sx * cos(ang) + fwd * sin(ang) * 0.6 + sy * (0.8 + h1 * 0.6));
		} else {
			float ang = (h1 - 0.5) * (tool ? 2.4 : 0.9);
			dir = normalize(fwd * cos(ang) + side * sin(ang) + sy * (h2 - 0.4) * (tool ? 1.2 : 0.5));
		}
		float speed = (rifle ? 2.6 : bow ? 1.2 : cast ? 1.1 : artillery ? 3.2 : sword ? 1.8 : 3.0) * (0.7 + 0.6 * h2);
		float travel = k * (0.10 + 0.12 * h1) * speed;
		vec3 at = origin + dir * travel + fwd * (rifle || artillery ? 0.1 : 0.0);
		vec3 along = dir;
		vec3 sside = cross(along, cam_fwd);
		sside = length(sside) < 0.02 ? cam_right : normalize(sside);
		float len = (cast ? 0.07 : 0.14) * (0.8 + 0.5 * h1);
		float wid = cast ? 0.07 : 0.045;
		world = at + along * c.y * len + sside * c.x * wid - cam_fwd * 0.22;
		cell = cast ? 2.0 : (elem == 3 ? 7.0 : 10.0);
		col = mix(elem_hot(elem), elem_tint(elem), 0.4);
		alpha = (idx < count ? 1.0 : 0.0) * pow(s, 0.6);
		if (idx >= count) world = origin;
	}
	v_tint = vec4(col, alpha);
	v_cell = cell;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float a;
	if (v_cell < -0.5) {
		float across = abs(v_local.x);
		a = pow(max(1.0 - across * across, 0.0), 1.6);
	} else {
		a = texture(sprites, cell_uv(int(v_cell + 0.5), UV)).a;
	}
	ALBEDO = mix(v_tint.rgb, v_tint.rgb * v_tint.rgb * 1.25, vfx_wash * 0.6);
	ALPHA = (a * v_tint.a) * mix(1.0, 0.66, vfx_wash);
}
