shader_type spatial;
render_mode diffuse_burley;
// Road and plaza surface of an arena battlefield. UV.x runs along the road in world
// units, UV.y across it from 0 to 1, so pavers and boards follow every bend. The same
// cell pattern serves stone setts, boardwalk planks, basalt slabs, packed earth and
// cleared ice: only the uniforms differ (game/3d/arena_biome.gd). The kerb is separate
// geometry built from the true road outline, so nothing here draws an edge line that
// could cross a junction. The road is one clean light ribbon (2026-10-18): pavers are
// about two units long (at most two joints under a hero), their tone and grain are
// faint and each carries one soft bevel inside its joint.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 color_a : source_color = vec3(0.30, 0.36, 0.36);
uniform vec3 color_b : source_color = vec3(0.40, 0.46, 0.44);
uniform vec3 joint_color : source_color = vec3(0.08, 0.11, 0.12);
uniform vec3 edge_color : source_color = vec3(0.14, 0.24, 0.18);
uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 fade_color : source_color = vec3(0.06, 0.12, 0.14);
// cell length along the road, rows across, stagger between rows, joint width (world units)
uniform vec4 cell = vec4(2.2, 3.0, 0.5, 0.035);
// tone variation between cells, grain amount, grain scale along, grain scale across
uniform vec4 tone = vec4(0.10, 0.08, 0.9, 0.9);
// side band width (share of the half width), strength, raggedness, wheel ruts
uniform vec4 edge = vec4(0.16, 0.5, 0.5, 0.0);
// joint glow, share of cells with a glowing joint, rails, joint darkness
uniform vec4 glow = vec4(0.0, 0.3, 0.0, 0.5);
uniform float field_radius = 12.0;
uniform float fade_length = 4.0;
uniform float road_width = 2.32;
uniform bool plaza = false;
uniform float rough = 0.9;
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q;       // position inside the pattern, world units (along, across)
	vec2 span;    // size of one cell, world units
	vec2 id;      // which cell
	float side;   // 0 on the centre line, 1 on the border
	if (plaza) {
		float radius = length(world_pos.xz);
		float ring_width = road_width * 0.5 / cell.y;
		float ring = floor(radius / ring_width);
		float middle = (ring + 0.5) * ring_width;
		float count = max(4.0, floor(6.2831853 * middle / cell.x + 0.5));
		float turn = (atan(world_pos.z, world_pos.x) / 6.2831853 + 0.5) * count + ring * cell.z;
		span = vec2(6.2831853 * middle / count, ring_width);
		q = vec2(fract(turn) * span.x, fract(radius / ring_width) * span.y);
		id = vec2(floor(turn), ring + 17.0);
		side = clamp(radius / (road_width * 0.5), 0.0, 1.0);
	} else {
		float across = UV.y * cell.y;
		float row = floor(across);
		float along = UV.x / cell.x + row * cell.z + hash(vec2(row, 3.0)) * cell.z;
		span = vec2(cell.x, road_width / cell.y);
		q = vec2(fract(along) * span.x, fract(across) * span.y);
		id = vec2(floor(along), row);
		side = abs(UV.y - 0.5) * 2.0;
	}
	float pick = hash(id);
	// Outside the rim the paving breaks up: pavers go missing one by one and the last
	// stretch is loose stones, so an approach never ends in a cut edge.
	float beyond = smoothstep(0.0, fade_length, length(world_pos.xz) - field_radius);
	float gap = min(min(q.x, span.x - q.x), min(q.y, span.y - q.y));
	if (beyond > 0.45 && !plaza) {
		float lost = (beyond - 0.45) / 0.55;
		if (pick < lost * 1.1 || gap < cell.w * (1.0 + lost * 6.0)) discard;
	}
	vec4 grain = texture(noise_tex, vec2(world_pos.x, world_pos.z) * 0.9 + pick * 3.0);
	vec4 fibre = texture(noise_tex, vec2(q.x * tone.z, q.y * tone.w) + id * 0.173);
	vec3 albedo = mix(color_a, color_b, pick * tone.x * 2.0 + (fibre.r - 0.5) * tone.y * 2.0);
	albedo *= 0.97 + grain.r * 0.06;
	float soft = fwidth(gap) * 1.2;
	float joint = 1.0 - smoothstep(cell.w - soft, cell.w + soft, gap);
	// One lighter bevel just inside the joint gives every paver its form.
	float chamfer = (1.0 - smoothstep(cell.w, cell.w * 4.5 + soft, gap)) * (1.0 - joint);
	albedo = mix(albedo * (1.0 + chamfer * 0.24), joint_color, joint * glow.w);
	vec3 emission = vec3(0.0);
	if (glow.x > 0.0) {
		float hot = step(1.0 - glow.y, hash(id + 7.0));
		float seam = 1.0 - smoothstep(0.0, cell.w * 2.6 + soft, gap);
		emission = glow_color * glow.x * seam * hot * (0.75 + 0.25 * sin(TIME * 1.9 + pick * 20.0));
	}
	if (edge.w > 0.0 && !plaza) {
		float rut = (1.0 - smoothstep(0.035, 0.085, abs(UV.y - 0.31))) + (1.0 - smoothstep(0.035, 0.085, abs(UV.y - 0.69)));
		albedo *= 1.0 - rut * edge.w * (0.6 + 0.4 * grain.a);
	}
	if (glow.z > 0.0 && !plaza) {
		float sleeper = 1.0 - smoothstep(0.07, 0.10, abs(fract(UV.x * 1.6) - 0.5) * 0.625);
		sleeper *= step(0.24, UV.y) * step(UV.y, 0.76);
		albedo = mix(albedo, joint_color * 1.6, sleeper * 0.85 * glow.z);
		float rail = (1.0 - smoothstep(0.010, 0.018, abs(UV.y - 0.33))) + (1.0 - smoothstep(0.010, 0.018, abs(UV.y - 0.67)));
		albedo = mix(albedo, vec3(0.42, 0.44, 0.47), clamp(rail, 0.0, 1.0) * glow.z);
	}
	// The side band (moss, frost, sand creeping in) follows one continuous field, not the
	// pavers, so it wanders along the kerb instead of stepping from stone to stone.
	float creep = texture(noise_tex, world_pos.xz * 0.37 + vec2(0.21, 0.63)).r + texture(noise_tex, world_pos.xz * 1.3).a * 0.4 - 0.7;
	float band = smoothstep(1.0 - edge.x * (1.0 + edge.z), 1.0 - edge.x * (1.0 - edge.z) + 0.001, side + creep * edge.x * edge.z * 2.2);
	albedo = mix(albedo, edge_color, band * edge.y);
	ALBEDO = mix(albedo, fade_color, beyond * 0.85);
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	EMISSION = emission * (1.0 - beyond);
}
