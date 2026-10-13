shader_type spatial;
render_mode diffuse_burley, skip_vertex_transform;
// One material for every static prop of an arena battlefield (game/3d/arena_scenery.gd).
// Props are MultiMesh instances of small shared templates, plus a few generated meshes.
//   instance COLOR.rgb        main tint (linear)           1 - COLOR.a   glow amount
//   INSTANCE_CUSTOM.rgb       second tint (trunk, stem)    INSTANCE_CUSTOM.a  sway amount; below 0 = never covered
//   vertex UV.x   baked shade (occlusion / height ramp)    UV.y   blend toward the second tint
//   vertex UV2.x  sway weight (tips of foliage)            UV2.y  cover weight, +2 where it may glow
// A generated mesh (kerbs, gate frames) has no instance data: its vertex colour is the tint.
uniform vec3 cover_color : source_color = vec3(0.80, 0.86, 0.92);
uniform float cover_amount = 0.0;
uniform float wind = 0.0;
uniform float glow_scale = 2.2;
// Self light: keeps the sides that face the camera (away from the key) in colour.
uniform float lift = 0.0;
uniform float rough = 0.86;
varying vec3 v_albedo;
varying float v_glow;
varying float v_cover;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Instances are scaled unevenly (boxes into beams, cones into roofs): the normal
	// needs the inverse transpose, which the instancing path does not apply by itself.
	vec3 normal = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);
	float sway = UV2.x * max(INSTANCE_CUSTOM.a, 0.0) * wind;
	if (sway > 0.0) {
		float phase = dot(MODEL_MATRIX[3].xz, vec2(0.37, 0.61));
		world.x += sin(TIME * 1.3 + phase) * sway;
		world.z += cos(TIME * 0.9 + phase * 1.7) * sway * 0.6;
	}
	float glows = step(1.5, UV2.y);
	v_albedo = mix(COLOR.rgb, INSTANCE_CUSTOM.rgb, UV.y) * UV.x;
	v_glow = (1.0 - COLOR.a) * glows;
	v_cover = smoothstep(0.42, 0.86, normal.y) * (UV2.y - 2.0 * glows) * cover_amount * step(-0.5, INSTANCE_CUSTOM.a);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize(mat3(VIEW_MATRIX) * normal);
}

void fragment() {
	ALBEDO = mix(v_albedo, cover_color, clamp(v_cover, 0.0, 1.0) * (1.0 - v_glow));
	ROUGHNESS = rough;
	SPECULAR = 0.28;
	EMISSION = v_albedo * (v_glow * glow_scale + lift);
}
