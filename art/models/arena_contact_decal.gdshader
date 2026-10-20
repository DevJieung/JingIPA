shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;
// Contact shadow pool under a prop of an arena battlefield (game/3d/arena_scenery.gd).
// A flat quad lying on the ground that darkens what is under it: a dense centre where
// the trunk or the rock meets the ground, fading out by 1.3x the footprint, so every
// tree, rock, post and lantern sits in its own pool instead of floating on the land.
// Nothing is lit: the pool is a colour (the field's haze, darkened) mixed over the
// ground by its alpha. Fog is left on so pools in the far haze fade with the land.
//   MultiMesh instances  COLOR.rgb  pool colour     INSTANCE_CUSTOM.a  strength
//   generated meshes     COLOR.rgb  pool colour     COLOR.a            strength
//                        (the kerb skirt and the plaza rim: `vertex_strength` 1)
//   UV                   0..1 across the quad; the centre (0.5, 0.5) is the darkest
// INSTANCE_CUSTOM exists in the vertex function only: the strength is read there.
uniform float vertex_strength : hint_range(0.0, 1.0) = 0.0;
uniform float core : hint_range(0.0, 1.0) = 0.45;
uniform float edge_fade : hint_range(0.0, 1.0) = 1.0;
varying float strength;

void vertex() {
	strength = mix(INSTANCE_CUSTOM.a, COLOR.a, vertex_strength);
}

void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float pool = 1.0 - smoothstep(core, edge_fade, radius);
	ALBEDO = COLOR.rgb;
	ALPHA = pool * clamp(strength, 0.0, 1.0);
}
