shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, specular_disabled;
#include "res://art/vfx/vfx_common.gdshaderinc"

// Sword slash arcs: an arc strip mesh (span = Balance.MELEE_ARC plus a little follow-through,
// unit outer radius, inner radius 0.42) scaled by the adapter to the hero's actual reach and
// aimed along the simulator's fire direction (MODEL transform). A bright blade head sweeps the
// arc in SWEEP seconds (the authored 3-frame cut) and leaves a wake that fades over LIFE.
// Pip's wrench uses the same mesh stood upright (overhead smash). One MultiMesh.
//   COLOR: colour   CUSTOM: x birth   y swing sign (+1 UV.x 0->1, -1 reverse) times the band
//                            fraction of the radius the wake covers (0.3..0.58)   z seed   w element
// Arc mesh: UV.x along the arc 0..1, UV.y across (0 outer edge, 1 inner edge at 0.42 r).
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float vfx_time = 0.0;
// 1 on bright snow/ice fields: additive layers wash to white there, so they are
// dimmed and pushed toward their saturated hue.
uniform float vfx_wash = 0.0;
uniform float vfx_epoch = 0.0;

const float SWEEP = 0.10;
const float LIFE = 0.34;
const float MESH_BAND = 0.58;   // 1 - inner radius ratio of the mesh

varying vec4 v_tint;
varying vec4 v_state;   // sweep head position, along, seed, age

void vertex() {
	float birth = INSTANCE_CUSTOM.x;
	float packed = INSTANCE_CUSTOM.y;
	float seed = INSTANCE_CUSTOM.z;
	int elem = int(INSTANCE_CUSTOM.w + 0.5);
	float age = max(vfx_time - vfx_epoch - birth, 0.0);
	float f = clamp(age / LIFE, 0.0, 1.0);
	float head = ease_out(min(age / SWEEP, 1.0));
	// Reverse swings sweep the arc from the other end.
	float along = packed < 0.0 ? 1.0 - UV.x : UV.x;
	// Only the outer `band` of the radius is the blade's wake; remap across to it.
	float band = clamp(abs(packed), 0.2, MESH_BAND);
	float across = UV.y * MESH_BAND / band;
	// The wake drifts outward a little as it dissipates (air pushed by the blade).
	VERTEX *= 1.0 + 0.08 * f;
	// A saturated body (the hot white lives in the rim and the head) so the wake keeps
	// its hue over bright floors; vfx_slash_base.gdshader inks the same band beneath it.
	v_tint = vec4(mix(COLOR.rgb, elem_tint(elem), 0.45), pow(1.0 - f, 1.5));
	v_state = vec4(head, along, seed, age);
	UV = vec2(UV.x, across);
}

void fragment() {
	float head = v_state.x;
	float along = v_state.y;
	float age = v_state.w;
	float across = UV.y;
	if (across > 1.0) discard;
	// Only what the blade has already passed is lit; the whole swept fan stays lit
	// (slow decay along the arc) and fades together, so the cut reads as a fan, not a
	// crescent that flickers from one end to the other.
	float behind = head - along;
	float wake = smoothstep(-0.015, 0.02, behind) * exp(-max(behind, 0.0) * 1.1);
	// The hot head itself: a short bright streak that leaves with the follow-through.
	float tip = exp(-pow(behind / 0.028, 2.0)) * (1.0 - smoothstep(SWEEP, SWEEP + 0.05, age));
	// Across the band: a crisp rim where the tip travels, a soft body toward the hand.
	float body = pow(1.0 - across, 0.55) * (1.0 - smoothstep(0.66, 1.0, across));
	float rim = exp(-pow(across / 0.075, 2.0));
	float n = texture(noise_tex, vec2(along * 3.0 + v_state.z, across * 0.6 - vfx_time * 2.0)).b;
	// The additive pass is the rim and the head; the body is mostly the ink underlay.
	float a = wake * (body * (0.22 + 0.26 * n) + rim * 1.5) + tip * 2.0 * (0.35 + 0.65 * body);
	vec3 tint = mix(v_tint.rgb, v_tint.rgb * v_tint.rgb * 1.25, vfx_wash * 0.6);
	ALBEDO = mix(tint, vec3(1.0), clamp(tip * 0.85 + rim * wake * 0.5 + (1.0 - across) * 0.15, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 1.0) * v_tint.a * mix(1.0, 0.8, vfx_wash);
}
