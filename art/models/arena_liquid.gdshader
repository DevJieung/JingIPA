shader_type spatial;
render_mode diffuse_burley;
// Water, lava, sea ice or bog around an arena battlefield: one flat ring whose vertices
// carry the depth of the ground beneath them (UV2.x, in world units), so the shore, the
// shallows and the foam follow the generated land instead of a fixed circle.
// Uniform driven like the other field shaders (game/3d/arena_biome.gd).
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 deep_color : source_color = vec3(0.02, 0.10, 0.16);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.34, 0.38);
uniform vec3 foam_color : source_color = vec3(0.75, 0.90, 0.92);
uniform vec3 crust_color : source_color = vec3(0.06, 0.05, 0.06);
uniform vec3 glow_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 glint_color : source_color = vec3(0.75, 0.92, 1.0);
uniform vec3 haze_color : source_color = vec3(0.04, 0.09, 0.13);
// ripple scale, ripple speed, normal tilt, depth at which the water is fully "deep"
uniform vec4 wave = vec4(0.16, 0.02, 0.5, 1.6);
// foam width at the shore, foam breakup, streak amount (current lines), streak scale
uniform vec4 foam = vec4(0.22, 0.6, 0.0, 0.3);
// coverage (0 = none), scale, gap width, drift speed  (ice floes, lava crust, lily mats)
uniform vec4 crust = vec4(0.0, 0.12, 0.10, 0.0);
// arms, tightness, turn speed, strength  (maelstrom; 0 arms = off)
uniform vec4 swirl = vec4(0.0, 2.2, 0.12, 0.0);
// amount, sharpness, glow in gaps between crust, pulse
uniform vec4 shine = vec4(0.5, 120.0, 0.0, 0.0);
// start distance from the centre, end distance, strength, roughness
uniform vec4 haze = vec4(14.0, 30.0, 0.7, 0.34);
uniform vec3 half_dir = vec3(0.20, 0.956, 0.217);
uniform vec2 seed = vec2(0.0);
varying vec3 world_pos;
varying float depth;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = UV2.x;
}

void fragment() {
	vec2 p = world_pos.xz + seed;
	float t = TIME * wave.y;
	vec4 r1 = texture(noise_tex, p * wave.x + vec2(t, t * 0.7));
	vec4 r2 = texture(noise_tex, p * wave.x * 1.9 - vec2(t * 0.8, t * 1.1) + vec2(0.37, 0.11));
	float swell = r1.r + r2.r - 1.0;
	vec3 facet = normalize(vec3((r1.r - r2.a) * wave.z, 1.0, (r1.a - r2.r) * wave.z));
	// Wind lies on water in patches: glitter and ruffle come and go across the surface.
	float gust = smoothstep(0.40, 0.66, texture(noise_tex, p * 0.019 + vec2(t * 0.25, t * 0.1)).r);
	float shallow = 1.0 - smoothstep(0.0, wave.w, depth + swell * 0.25);
	vec3 albedo = mix(deep_color, shallow_color, shallow);
	albedo *= 0.86 + swell * 0.18 + gust * 0.14;
	float whitewater = 0.0;
	if (swirl.x > 0.0) {
		// Spiral arms of foam winding into the centre: sample the ridge field in
		// (angle, log radius) space so the arms stay sharp at every distance.
		float radius = length(world_pos.xz);
		float angle = atan(world_pos.z, world_pos.x) / 6.2831853;
		float wind = log(radius + 0.5) * swirl.y;
		float turn = angle * swirl.x + wind - TIME * swirl.z;
		// Streaks of foam drawn out along the winding (ridge field in spiral space),
		// gathered into broad arms that darken the troughs between them.
		float streak = texture(noise_tex, vec2(turn * 0.5, log(radius + 0.5) * 0.3 + 0.21)).a;
		float arm = 0.5 + 0.5 * sin(turn * 6.2831853 * 0.5);
		whitewater = smoothstep(0.60, 0.84, streak * 0.8 + arm * 0.28) * swirl.w * smoothstep(42.0, 14.0, radius);
		albedo = mix(albedo, deep_color * 0.5, (1.0 - arm) * 0.6 * swirl.w);
	}
	if (foam.z > 0.0) {
		float streak = texture(noise_tex, p * foam.w + vec2(t * 1.6, 0.0)).a;
		whitewater = max(whitewater, smoothstep(0.66, 0.86, streak) * foam.z);
	}
	float surf = (1.0 - smoothstep(0.0, foam.x, depth - (r2.a - 0.5) * foam.x * foam.y)) * step(0.0, depth + 0.4) * (0.55 + 0.45 * r1.a);
	whitewater = max(whitewater, surf);
	float plates = 0.0;
	vec3 emission = vec3(0.0);
	if (crust.x > 0.0) {
		vec4 cell = texture(noise_tex, p * crust.y + vec2(TIME * crust.w, 0.0));
		float edge = fwidth(cell.g) * 1.2;
		float keep = smoothstep(1.0 - crust.x - 0.04, 1.0 - crust.x + 0.04, cell.b * 0.7 + r1.r * 0.45);
		plates = smoothstep(crust.z - edge, crust.z + edge, cell.g) * keep;
		albedo = mix(albedo, crust_color * (0.82 + cell.b * 0.36), plates);
	}
	albedo = mix(albedo, foam_color, whitewater * (1.0 - plates));
	float hot = (1.0 - plates) * (0.55 + 0.45 * r1.r) * (1.0 + shine.w * sin(TIME * 1.3 + r2.r * 7.0));
	emission += glow_color * hot * mix(1.0, 1.0 - plates, shine.z);
	float spark = pow(max(dot(facet, half_dir), 0.0), shine.y);
	emission += glint_color * spark * shine.x * (0.15 + 0.85 * gust) * (1.0 - plates) * (1.0 - whitewater);
	float far = smoothstep(haze.x, haze.y, length(world_pos.xz)) * haze.z;
	ALBEDO = mix(albedo, haze_color, far);
	ROUGHNESS = mix(haze.w, 0.9, max(plates, whitewater));
	SPECULAR = 0.3;
	NORMAL = normalize(mat3(VIEW_MATRIX) * mix(facet, vec3(0.0, 1.0, 0.0), plates));
	EMISSION = emission * (1.0 - far * 0.8);
}
