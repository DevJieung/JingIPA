shader_type spatial;
render_mode diffuse_burley;
// The land around an arena battlefield: one generated ring of ground from the rim out
// (game/3d/arena_world.gd). Flat parts take the ground colours, steep parts show rock
// strata banded by height, upward ledges take a cover (snow, moss, ash), seams may glow
// (lava) and everything settles into the haze colour with distance so the eye stays on
// the field (aerial perspective: the haze is lighter than the sky, 2026-10-18). Strata
// and grain are faint so the land is a calm dark mass around the lit stage. All
// patterns come from art/models/terrain_noise.png.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 top_a : source_color = vec3(0.08, 0.16, 0.16);
uniform vec3 top_b : source_color = vec3(0.12, 0.22, 0.18);
uniform vec3 side_a : source_color = vec3(0.16, 0.18, 0.22);
uniform vec3 side_b : source_color = vec3(0.26, 0.28, 0.32);
uniform vec3 cover_color : source_color = vec3(0.8, 0.86, 0.92);
uniform vec3 glow_color : source_color = vec3(1.0, 0.4, 0.1);
uniform vec3 haze_color : source_color = vec3(0.04, 0.09, 0.13);
// level, softness, scale, grain
uniform vec4 patch = vec4(0.5, 0.18, 0.07, 0.08);
// bands per unit of height, warp, band contrast, slope where rock begins
uniform vec4 strata = vec4(2.2, 0.9, 0.15, 0.10);
// amount, slope limit (normal.y above which it lies), lowest height, edge noise
uniform vec4 cover = vec4(0.0, 0.62, 0.0, 0.25);
// amount, scale, seam width, pulse
uniform vec4 glow = vec4(0.0, 0.2, 0.08, 0.0);
// start distance from the centre, end distance, strength, self light
uniform vec4 haze = vec4(13.0, 30.0, 0.8, 0.0);
uniform float rough = 0.94;
uniform vec2 seed = vec2(0.0);
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec2 p = world_pos.xz + seed;
	vec3 normal = normalize(world_normal);
	vec4 mid = texture(noise_tex, p * patch.z);
	vec4 fine = texture(noise_tex, p * 0.57 + vec2(0.13, 0.71));
	float cloud = mid.r + (fine.r - 0.5) * 0.14;
	vec3 top = mix(top_a, top_b, smoothstep(patch.x - patch.y, patch.x + patch.y, cloud));
	top *= 1.0 + (fine.r - 0.5) * patch.w + (fine.a - 0.5) * patch.w * 0.5;
	// Strata: flat-lying beds that wander a little, each with its own tone and a dark
	// parting line; a fine vertical grain breaks the bands on the wall.
	float bed = world_pos.y * strata.x + (mid.a - 0.5) * strata.y + fine.r * 0.25;
	float layer = fract(bed);
	float tone = texture(noise_tex, vec2(floor(bed) * 0.173 + 0.05, 0.37)).b;
	vec3 wall = mix(side_a, side_b, tone);
	wall *= 1.0 - smoothstep(0.80, 0.97, layer) * strata.z;
	wall *= 0.92 + 0.16 * texture(noise_tex, vec2(p.x + p.y, world_pos.y * 0.31) * 0.9).a;
	float steep = smoothstep(strata.w, strata.w + 0.2, 1.0 - normal.y);
	vec3 albedo = mix(top, wall, steep);
	float lying = smoothstep(cover.y - 0.1, cover.y + 0.1, normal.y + (fine.a - 0.5) * cover.w);
	lying *= smoothstep(cover.z, cover.z + 0.5, world_pos.y + (mid.r - 0.5) * 0.6);
	albedo = mix(albedo, cover_color * (0.92 + fine.r * 0.16), lying * cover.x);
	vec3 emission = albedo * haze.w;
	if (glow.x > 0.0) {
		vec4 cell = texture(noise_tex, p * glow.y + vec2(world_pos.y * 0.07));
		float edge = fwidth(cell.g) * 1.2;
		float seam = 1.0 - smoothstep(glow.z - edge, glow.z * 2.4 + edge, cell.g);
		float hot = smoothstep(0.35, 0.7, mid.a) * (1.0 - lying * cover.x);
		emission += glow_color * glow.x * seam * seam * hot * (1.0 + glow.w * sin(TIME * 1.5 + mid.r * 8.0));
	}
	float far = smoothstep(haze.x, haze.y, length(world_pos.xz)) * haze.z;
	ALBEDO = mix(albedo, haze_color, far);
	ROUGHNESS = rough;
	SPECULAR = 0.15;
	EMISSION = emission * (1.0 - far);
}
