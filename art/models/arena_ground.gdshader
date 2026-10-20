shader_type spatial;
render_mode diffuse_burley;
// Playfield floor of an arena battlefield. One shader for every biome: the look comes
// from the uniforms (game/3d/arena_biome.gd), so a stage switch never compiles a shader.
// Layers, bottom to top: base colour drifting into a patch colour -> plates with joints
// -> winding lines (ripples, roots, drifts) -> pools (puddles, ice, lava) -> specks
// (flowers, pebbles, sparks) -> a band along the rim -> glints on wet or frozen ground
// -> the stage: a lit centre falling off toward the rim (2026-10-18, Lantern Stage).
// The floor is a quiet stage: marks are few, large and soft, so the actors and the
// effects are the sharpest things on it. All patterns are thresholded fields of
// art/models/terrain_noise.png.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 color_a : source_color = vec3(0.10, 0.20, 0.20);
uniform vec3 color_b : source_color = vec3(0.16, 0.30, 0.24);
uniform vec3 joint_color : source_color = vec3(0.03, 0.06, 0.07);
uniform vec3 line_color : source_color = vec3(0.20, 0.30, 0.30);
uniform vec3 pool_color : source_color = vec3(0.05, 0.20, 0.26);
uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 speck_color : source_color = vec3(0.9, 0.9, 0.7);
uniform vec3 rim_color : source_color = vec3(0.2, 0.3, 0.3);
uniform vec3 glint_color : source_color = vec3(0.8, 0.95, 1.0);
// level, softness, scale, grain contrast (patches twice as large and soft as before)
uniform vec4 patch = vec4(0.5, 0.30, 0.045, 0.06);
// scale, joint width (0 = no plates), tone variation per plate, joint strength
uniform vec4 plate = vec4(0.30, 0.0, 0.0, 0.0);
// amount, scale, threshold, softness (broad soft darkenings, not squiggles)
uniform vec4 lines = vec4(0.0, 0.2, 0.62, 0.14);
// coverage (0 = none), softness, scale, roughness inside
uniform vec4 pool = vec4(0.0, 0.14, 0.12, 0.2);
// joint glow, pool glow, share of joints that glow, pulse
uniform vec4 glow = vec4(0.0, 0.0, 0.5, 0.0);
// amount, share of cells that carry one, scale, glow
uniform vec4 speck = vec4(0.0, 0.08, 1.2, 0.0);
// strength, width, unused, unused (a wide band: the stage falls off toward the kerb)
uniform vec4 rim = vec4(0.0, 3.5, 0.0, 0.0);
// amount, unused, pools only (0/1), twinkle speed
uniform vec4 glint = vec4(0.0, 0.0, 0.0, 0.0);
// The painted spotlight: radius of the fully lit centre (the fall-off starts at 45 % of
// it), and how much darker the floor is at the rim (0 = evenly lit as before).
uniform vec2 stage = vec2(12.0, 0.0);
uniform float field_radius = 12.0;
uniform float rough = 0.93;
uniform vec2 seed = vec2(0.0);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz + seed;
	vec4 drift = texture(noise_tex, p * 0.027);
	vec4 mid = texture(noise_tex, p * patch.z + drift.ar * 0.12);
	vec4 fine = texture(noise_tex, p * 0.61 + vec2(0.31, 0.77));
	float cloud = mix(mid.r, drift.r, 0.4) + (fine.r - 0.5) * 0.10;
	float patches = smoothstep(patch.x - patch.y, patch.x + patch.y, cloud);
	vec3 albedo = mix(color_a, color_b, patches);
	albedo *= 1.0 + (fine.r - 0.5) * patch.w + (fine.a - 0.5) * patch.w * 0.6;
	float roughness = rough;
	vec3 emission = vec3(0.0);
	float pulse = 1.0 + glow.w * sin(TIME * 1.7 + drift.r * 9.0);
	float wet = 0.0;
	float from_centre = length(world_pos.xz);
	if (plate.y > 0.0) {
		vec4 cell = texture(noise_tex, p * plate.x + (mid.rg - 0.5) * 0.02);
		albedo *= 1.0 + (cell.b - 0.5) * plate.z;
		float edge = fwidth(cell.g) * 1.1;
		float joint = 1.0 - smoothstep(plate.y - edge, plate.y + edge, cell.g);
		albedo = mix(albedo, joint_color, joint * plate.w);
		// Only some joints glow, in drifting regions, so the floor is not a uniform grid.
		float hot = smoothstep(1.0 - glow.z - 0.12, 1.0 - glow.z + 0.12, drift.a * 0.6 + mid.r * 0.5);
		float seam = 1.0 - smoothstep(0.0, plate.y * 2.6 + edge, cell.g);
		emission += glow_color * glow.x * hot * seam * seam * pulse;
	}
	if (lines.x > 0.0) {
		float ridge = texture(noise_tex, p * lines.y + vec2(0.11, 0.53)).a;
		float mark = smoothstep(lines.z - lines.w, lines.z + lines.w, ridge);
		albedo = mix(albedo, line_color, mark * lines.x);
	}
	if (pool.x > 0.0) {
		float basin = texture(noise_tex, p * pool.z + vec2(0.63, 0.21)).r * 0.75 + mid.a * 0.25;
		float level = 1.0 - pool.x;
		wet = smoothstep(level - pool.y, level + pool.y, basin);
		float shore = wet * (1.0 - wet) * 4.0;
		albedo = mix(albedo * (1.0 - shore * 0.25), pool_color * (0.90 + fine.r * 0.20), wet);
		roughness = mix(roughness, pool.w, wet);
		float deep = smoothstep(level, level + pool.y * 4.0 + 0.08, basin);
		emission += glow_color * glow.y * wet * (0.35 + 0.65 * deep) * (0.8 + 0.4 * fine.a) * pulse;
	}
	if (speck.x > 0.0) {
		vec4 dot_cell = texture(noise_tex, p * speck.z + vec2(0.47, 0.19));
		float keep = step(1.0 - speck.y, dot_cell.b);
		float edge = fwidth(dot_cell.g) * 1.5;
		float blob = smoothstep(0.62 - edge, 0.62 + edge, dot_cell.g) * keep * (1.0 - wet);
		albedo = mix(albedo, speck_color, blob * speck.x);
		emission += speck_color * blob * speck.w;
	}
	if (rim.x > 0.0) {
		float inside = field_radius - from_centre;
		float band = 1.0 - smoothstep(0.0, rim.y, inside + (cloud - 0.5) * rim.y * 0.6);
		albedo = mix(albedo, rim_color, band * rim.x);
	}
	if (glint.x > 0.0) {
		// Sparkle: a few cells of a fine grid catch the light for a moment each. Small
		// points only, so wet or frozen ground glitters without getting any lighter.
		vec4 grit = texture(noise_tex, p * 0.71 + vec2(0.71, 0.13));
		float lit = step(0.93, grit.b) * smoothstep(0.50, 0.80, grit.g);
		float twinkle = 0.55 + 0.45 * sin(TIME * (1.0 + glint.w * 3.0) + grit.b * 157.0 + drift.r * 9.0);
		emission += glint_color * lit * twinkle * glint.x * mix(1.0, wet, glint.z);
	}
	// The stage light: full in the centre, falling toward the rim. One multiply, no tap.
	albedo *= mix(1.0, 1.0 - stage.y, smoothstep(stage.x * 0.45, field_radius, from_centre));
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = 0.32;
	EMISSION = emission;
}
