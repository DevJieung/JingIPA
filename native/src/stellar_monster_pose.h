#pragma once

#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <vector>

namespace godot {

/// NativeMonsterModel's pose: the authored clips sampled straight from the Animation
/// tracks and blended with normalised weights, bone by bone, then written to the
/// skeleton in one call. The blend order, the lerp/slerp factor and the hit flinch are
/// the GDScript sampler's (NativeMonsterModel._compose), so a body poses the same whether
/// this library is loaded or not.
class StellarMonsterPose : public RefCounted {
	GDCLASS(StellarMonsterPose, RefCounted)

	struct Clip {
		Ref<Animation> animation;
		double length = 0.001;
		std::vector<int32_t> pos;
		std::vector<int32_t> rot;
		std::vector<int32_t> scl;
	};
	std::vector<Clip> clips;
	int bone_count = 0;
	int head = -1;
	int body = -1;
	std::vector<Vector3> rest_pos;
	std::vector<Quaternion> rest_rot;
	std::vector<Vector3> rest_scale;
	std::vector<Vector3> acc_pos;
	std::vector<Quaternion> acc_rot;
	std::vector<Vector3> acc_scale;
	double acc_w = 0.0;

protected:
	static void _bind_methods();

public:
	/// Rest poses and the flinch bones of the skeleton this pose is for.
	void bind(Skeleton3D *p_skeleton);
	/// A clip with its per-bone track indices (-1 where a bone has no track). Returns
	/// the clip's index for sample().
	int add_clip(const Ref<Animation> &p_animation, const PackedInt32Array &p_pos, const PackedInt32Array &p_rot, const PackedInt32Array &p_scl);
	void begin();
	void sample(int p_clip, double p_time, double p_weight, bool p_loop);
	/// Rest pose when nothing was sampled; then the hit flinch (`flinch` 0..1 scaled,
	/// 0 for none) on the head and body bones.
	void finish(double p_flinch, double p_height);
	void apply(Skeleton3D *p_skeleton) const;

	int get_bone_count() const { return bone_count; }
	int get_clip_count() const { return (int)clips.size(); }
	double get_accumulated_weight() const { return acc_w; }
	Vector3 bone_position(int p_bone) const;
	Quaternion bone_rotation(int p_bone) const;
	Vector3 bone_scale(int p_bone) const;
};

} // namespace godot
