shader_type canvas_item;
// The battle frame's post pass (2026-10-18, casual overhaul WP-E). ArenaFrame — the one
// LINEAR child of the battle screen — draws the 3D picture once per frame through this
// material. Three quiet touches, nothing else:
//   vignette  a cool fall-off toward the night about the OPEN battle box (not the window),
//             so the field reads as a framed picture; the sidebar and the top strip are
//             drawn over it by the screen and stay untouched.
//   sharpen   a light 3x3 unsharp mask in texel space, so the phone's soft bilinear
//             upscale (1280x800 -> 1000x625) keeps its kerb and plank edges without the
//             nearest-neighbour stair-steps. 0 switches it off (the kill switch).
//   dither    1/255 interleaved-gradient noise against banding in sky and water ramps.
// No tilt-shift (it blurs the spawn gates). Colour grading lives in the Environment's
// adjustment_* and never here, so nothing is graded twice. No back-buffer copy: only
// TEXTURE (the viewport texture) is sampled.
uniform vec4 frame_rect = vec4(0.0, 0.0, 1280.0, 800.0);   // canvas rect of the blit (px)
uniform vec2 box_center = vec2(496.0, 435.0);               // open battle box centre (canvas px)
uniform vec2 box_size = vec2(992.0, 730.0);                 // open battle box size (canvas px)
uniform float vignette : hint_range(0.0, 1.0) = 0.24;       // corner fall-off strength
uniform vec4 vignette_color = vec4(0.031, 0.059, 0.098, 1.0); // Look.BG_DEEP, set by ArenaView
uniform float sharpen : hint_range(0.0, 1.0) = 0.30;
uniform float dither : hint_range(0.0, 1.0) = 1.0;

// Interleaved gradient noise (Jimenez 2014): a stable per-pixel pattern, no texture.
float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec4 c = COLOR;
	// Only the picture is treated. The node's own clear under it (draw_rect: the 1x1
	// white default texture) keeps its flat colour.
	if (TEXTURE_PIXEL_SIZE.x < 0.1) {
		if (sharpen > 0.0) {
			// 3x3 cross unsharp mask (centre + 4 neighbours, 5 taps: half the fetches of
			// the full 3x3 for the same edge gain), clamped so a bright kerb never rings dark.
			vec2 d = TEXTURE_PIXEL_SIZE;
			vec3 ring = texture(TEXTURE, UV + vec2(d.x, 0.0)).rgb + texture(TEXTURE, UV - vec2(d.x, 0.0)).rgb
					+ texture(TEXTURE, UV + vec2(0.0, d.y)).rgb + texture(TEXTURE, UV - vec2(0.0, d.y)).rgb;
			vec3 blur = (c.rgb + ring) * 0.2;
			c.rgb = clamp(c.rgb + sharpen * (c.rgb - blur), 0.0, 1.0);
		}
		vec2 px = frame_rect.xy + UV * frame_rect.zw;
		float r = length((px - box_center) / (box_size * 0.5));
		float v = 1.0 - vignette * smoothstep(0.55, 1.25, r);
		c.rgb = mix(vignette_color.rgb, c.rgb, v);
		c.rgb += (ign(FRAGCOORD.xy) - 0.5) / 255.0 * dither;
	}
	COLOR = c;
}
