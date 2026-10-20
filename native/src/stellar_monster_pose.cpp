#include "stellar_monster_pose.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>

using namespace godot;

void StellarMonsterPose::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "skeleton"), &StellarMonsterPose::bind);
	ClassDB::bind_method(D_METHOD("add_clip", "animation", "pos", "rot", "scl"), &StellarMonsterPose::add_clip);
	ClassDB::bind_method(D_METHOD("begin"), &StellarMonsterPose::begin);
	ClassDB::bind_method(D_METHOD("sample", "clip", "time", "weight", "loop"), &StellarMonsterPose::sample);
	ClassDB::bind_method(D_METHOD("finish", "flinch", "height"), &StellarMonsterPose::finish);
	ClassDB::bind_method(D_METHOD("apply", "skeleton"), &StellarMonsterPose::apply);
	ClassDB::bind_method(D_METHOD("get_bone_count"), &StellarMonsterPose::get_bone_count);
	ClassDB::bind_method(D_METHOD("get_clip_count"), &StellarMonsterPose::get_clip_count);
	ClassDB::bind_method(D_METHOD("get_accumulated_weight"), &StellarMonsterPose::get_accumulated_weight);
	ClassDB::bind_method(D_METHOD("bone_position", "bone"), &StellarMonsterPose::bone_position);
	ClassDB::bind_method(D_METHOD("bone_rotation", "bone"), &StellarMonsterPose::bone_rotation);
	ClassDB::bind_method(D_METHOD("bone_scale", "bone"), &StellarMonsterPose::bone_scale);
}

void StellarMonsterPose::bind(Skeleton3D *p_skeleton) {
	ERR_FAIL_NULL(p_skeleton);
	bone_count = p_skeleton->get_bone_count();
	rest_pos.resize(bone_count);
	rest_rot.resize(bone_count);
	rest_scale.resize(bone_count);
	acc_pos.assign(bone_count, Vector3());
	acc_rot.assign(bone_count, Quaternion());
	acc_scale.assign(bone_count, Vector3(1, 1, 1));
	for (int i = 0; i < bone_count; i++) {
		Transform3D rest = p_skeleton->get_bone_rest(i);
		rest_pos[i] = rest.origin;
		rest_rot[i] = rest.basis.get_rotation_quaternion();
		rest_scale[i] = rest.basis.get_scale();
	}
	head = p_skeleton->find_bone("Head");
	body = p_skeleton->find_bone("Body");
	clips.clear();
	acc_w = 0.0;
}

int StellarMonsterPose::add_clip(const Ref<Animation> &p_animation, const PackedInt32Array &p_pos, const PackedInt32Array &p_rot, const PackedInt32Array &p_scl) {
	ERR_FAIL_COND_V(p_animation.is_null(), -1);
	ERR_FAIL_COND_V(p_pos.size() != bone_count || p_rot.size() != bone_count || p_scl.size() != bone_count, -1);
	Clip clip;
	clip.animation = p_animation;
	clip.length = std::max(p_animation->get_length(), 0.001);
	clip.pos.assign(p_pos.ptr(), p_pos.ptr() + p_pos.size());
	clip.rot.assign(p_rot.ptr(), p_rot.ptr() + p_rot.size());
	clip.scl.assign(p_scl.ptr(), p_scl.ptr() + p_scl.size());
	clips.push_back(clip);
	return (int)clips.size() - 1;
}

void StellarMonsterPose::begin() {
	acc_w = 0.0;
}

void StellarMonsterPose::sample(int p_clip, double p_time, double p_weight, bool p_loop) {
	ERR_FAIL_INDEX(p_clip, (int)clips.size());
	const Clip &clip = clips[p_clip];
	const Animation *animation = clip.animation.ptr();
	double time = p_loop ? Math::fposmod(p_time, clip.length) : CLAMP(p_time, 0.0, clip.length);
	bool first = acc_w <= 0.0;
	real_t f = (real_t)(p_weight / (acc_w + p_weight));
	for (int i = 0; i < bone_count; i++) {
		Vector3 p = clip.pos[i] >= 0 ? animation->position_track_interpolate(clip.pos[i], time) : rest_pos[i];
		Quaternion q = clip.rot[i] >= 0 ? animation->rotation_track_interpolate(clip.rot[i], time) : rest_rot[i];
		Vector3 sc = clip.scl[i] >= 0 ? animation->scale_track_interpolate(clip.scl[i], time) : rest_scale[i];
		if (first) {
			acc_pos[i] = p;
			acc_rot[i] = q;
			acc_scale[i] = sc;
		} else {
			acc_pos[i] = acc_pos[i].lerp(p, f);
			acc_rot[i] = acc_rot[i].slerp(q, f);
			acc_scale[i] = acc_scale[i].lerp(sc, f);
		}
	}
	acc_w += p_weight;
}

void StellarMonsterPose::finish(double p_flinch, double p_height) {
	if (acc_w <= 0.0) {
		for (int i = 0; i < bone_count; i++) {
			acc_pos[i] = rest_pos[i];
			acc_rot[i] = rest_rot[i];
			acc_scale[i] = rest_scale[i];
		}
	}
	if (p_flinch > 0.0) {
		// Flinch: head and torso snap up/back for the few frames the flash lasts.
		if (head >= 0 && head < bone_count) {
			acc_rot[head] = Quaternion(Vector3(1, 0, 0), (real_t)(0.22 * p_flinch)) * acc_rot[head];
		}
		if (body >= 0 && body < bone_count) {
			acc_rot[body] = Quaternion(Vector3(1, 0, 0), (real_t)(0.06 * p_flinch)) * acc_rot[body];
			acc_pos[body] += Vector3(0, 0, (real_t)(0.02 * p_height * p_flinch));
		}
	}
}

void StellarMonsterPose::apply(Skeleton3D *p_skeleton) const {
	ERR_FAIL_NULL(p_skeleton);
	ERR_FAIL_COND(p_skeleton->get_bone_count() != bone_count);
	for (int i = 0; i < bone_count; i++) {
		p_skeleton->set_bone_pose_position(i, acc_pos[i]);
		p_skeleton->set_bone_pose_rotation(i, acc_rot[i]);
		p_skeleton->set_bone_pose_scale(i, acc_scale[i]);
	}
}

Vector3 StellarMonsterPose::bone_position(int p_bone) const {
	ERR_FAIL_INDEX_V(p_bone, bone_count, Vector3());
	return acc_pos[p_bone];
}

Quaternion StellarMonsterPose::bone_rotation(int p_bone) const {
	ERR_FAIL_INDEX_V(p_bone, bone_count, Quaternion());
	return acc_rot[p_bone];
}

Vector3 StellarMonsterPose::bone_scale(int p_bone) const {
	ERR_FAIL_INDEX_V(p_bone, bone_count, Vector3(1, 1, 1));
	return acc_scale[p_bone];
}
