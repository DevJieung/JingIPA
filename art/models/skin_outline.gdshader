shader_type spatial;
render_mode cull_front, unshaded, skip_vertex_transform, depth_draw_opaque, fog_disabled;
// Inverted-hull ink line around a skinned body (2026-10-18, heroes and bosses only):
// the skin's next_pass draws the already-skinned mesh again, pushed out along the view
// normal by a fixed number of screen pixels and drawn with front faces culled, so only
// the rim of the extruded shell shows. The orthographic projection gives units per pixel
// directly (PROJECTION_MATRIX[0][0] = 2 / view width), so the line keeps its width
// through the boss zoom and at any root scale. `cut` follows the body's dissolve: the
// same interleaved gradient noise as the skin's pixel dither, so the line crumbles with
// the body and nothing stands after it.
uniform vec4 line_color : source_color = vec4(0.055, 0.047, 0.11, 1.0);   // night-shade ink, L ~0.12
uniform float width_px = 1.0;      // at 800 px of viewport height; scales with the viewport
uniform float depth_push = 0.012;  // hides slivers from the open rims left by hidden-face deletion
instance uniform float cut : hint_range(0.0, 1.0) = 1.0;   // 1 whole, 0 gone (dissolve)

void vertex() {
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_nrm = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	float units_per_px = 2.0 / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);   // orthographic
	view_pos += view_nrm * width_px * (VIEWPORT_SIZE.y / 800.0) * units_per_px;
	view_pos.z -= depth_push;
	VERTEX = view_pos;
	NORMAL = view_nrm;
}

void fragment() {
	float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (n > cut) {
		discard;
	}
	ALBEDO = line_color.rgb;
}
