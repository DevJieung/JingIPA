shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
// Soft moving air of a battlefield, drawn on a handful of static quads that already face
// the fixed arena camera: the veil in a gate, smoke and steam plumes, waterfalls, lava
// falls, aurora curtains, mist lying on the ground. No particles, no extra pass.
//   vertex COLOR.rgb  tint * strength      COLOR.a  1 = covers what is behind, 0 = adds light
//   UV                across 0..1, up 0..1 UV2.x    scroll speed      UV2.y  pattern + phase:
//   0 veil (rising streaks)  1 plume (widening smoke)  2 curtain (aurora rays)
//   3 fall (streaks running down)  4 mist (drifting ground fog)
//   The fraction of UV2.y is the quad's own phase, so no two quads show the same puff.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float strength = 1.0;
varying vec4 tint;
varying vec2 motion;

void vertex() {
	tint = COLOR;
	motion = UV2;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float side = abs(u - 0.5) * 2.0;
	float t = TIME * motion.x;
	float shape = 0.0;
	int pattern = int(floor(motion.y + 0.001));
	float phase = fract(motion.y + 0.001);
	vec2 jitter = vec2(phase * 7.31, phase * 3.77);
	if (pattern == 0) {
		float streak = texture(noise_tex, vec2(u * 0.9 + jitter.x, v * 0.35 - t)).a;
		float body = texture(noise_tex, vec2(u * 0.4 + jitter.y, v * 0.5 - t * 0.6)).r;
		shape = (0.30 + 0.9 * smoothstep(0.45, 0.8, streak) + 0.4 * body) * (1.0 - smoothstep(0.55, 1.0, side));
		shape *= (1.0 - smoothstep(0.35, 1.0, v)) * smoothstep(0.0, 0.06, v);
	} else if (pattern == 1) {
		float puff = texture(noise_tex, vec2(u * 0.5 + jitter.x, v * 0.6 - t)).r;
		float curl = texture(noise_tex, vec2(u * 1.1 - jitter.y, v * 1.2 - t * 1.7)).r;
		float width = mix(0.28, 1.0, smoothstep(0.0, 0.8, v));
		float lean = (curl - 0.5) * 0.5 * v;
		shape = 1.0 - smoothstep(0.25, 1.0, abs(u - 0.5 + lean) * 2.0 / width + (0.5 - puff) * 0.9);
		shape *= (1.0 - smoothstep(0.45, 1.0, v)) * smoothstep(0.0, 0.1, v) * (0.55 + 0.6 * curl);
	} else if (pattern == 2) {
		// A curtain: a wavering lower hem, long soft rays above it, folds drifting along.
		float fold = texture(noise_tex, vec2(u * 0.22 - t * 0.6 + jitter.x, 0.67)).r;
		float rays = texture(noise_tex, vec2(u * 0.55 + jitter.y + t, 0.31)).r;
		float fine = texture(noise_tex, vec2(u * 2.1 - t * 1.5, 0.12 + jitter.x)).a;
		float foot = 0.16 + (fold - 0.5) * 0.34;
		shape = smoothstep(foot - 0.05, foot + 0.03, v) * pow(1.0 - smoothstep(foot, 1.0, v), 1.9);
		shape *= (0.30 + 0.9 * smoothstep(0.3, 0.75, rays)) * (0.7 + 0.3 * fine) * (1.0 - smoothstep(0.55, 1.0, side));
	} else if (pattern == 3) {
		float streak = texture(noise_tex, vec2(u * 1.4 + jitter.x, v * 0.25 + t)).a;
		float sheet = texture(noise_tex, vec2(u * 0.6, v * 0.6 + t * 0.7)).r;
		shape = (0.5 + 0.7 * smoothstep(0.4, 0.75, streak) + 0.3 * sheet) * (1.0 - smoothstep(0.7, 1.0, side));
		shape *= smoothstep(0.0, 0.04, v) * (1.0 - smoothstep(0.92, 1.0, v));
	} else {
		float bank = texture(noise_tex, vec2(u * 0.7 + t + jitter.x, v * 0.7 + t * 0.4)).r;
		float wisp = texture(noise_tex, vec2(u * 1.5 - t * 0.7, v * 1.5 + jitter.y)).r;
		float fade = (1.0 - smoothstep(0.5, 1.0, side)) * (1.0 - smoothstep(0.5, 1.0, abs(v - 0.5) * 2.0));
		shape = smoothstep(0.38, 0.8, bank * 0.7 + wisp * 0.4) * fade;
	}
	float amount = clamp(shape * strength, 0.0, 1.0);
	ALBEDO = tint.rgb * amount;
	ALPHA = amount * tint.a;
}
