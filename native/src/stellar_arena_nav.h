#pragma once

#include "stellar_roads.h"

#include <godot_cpp/classes/a_star_grid2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <vector>

namespace godot {

/// ArenaSim's monster navigation kernels: the segment tests against the road and the
/// guardians, the path query (grid candidates around the start, A* on the simulator's
/// own AStarGrid2D, the join that drops waypoints already in view) and the static road
/// mask of a layout. The rules that use them (burn, siege, curse, events) stay in
/// ArenaSim; this only answers the same geometric questions faster.
class StellarArenaNav : public RefCounted {
	GDCLASS(StellarArenaNav, RefCounted)

	Ref<StellarRoads> roads;
	Ref<AStarGrid2D> nav;
	Ref<AStarGrid2D> road_nav;
	Rect2 map_rect;
	Vector2 cell_size;
	Rect2i region;
	double hero_radius = 18.0;
	double monster_radius = 10.0;
	double step = 6.0;
	std::vector<Vector2> heroes;

	struct Candidate {
		Vector2i cell;
		real_t distance;
	};
	std::vector<Candidate> candidates(const Vector2 &p_from, const Ref<AStarGrid2D> &p_grid, bool p_avoid_heroes) const;

protected:
	static void _bind_methods();

public:
	void setup(const Ref<StellarRoads> &p_roads, const Ref<AStarGrid2D> &p_nav, const Ref<AStarGrid2D> &p_road_nav, const Rect2 &p_map_rect, double p_hero_radius, double p_monster_radius, double p_step);
	void set_heroes(const PackedVector2Array &p_positions);
	bool road_segment_clear(const Vector2 &p_from, const Vector2 &p_to, double p_margin) const;
	bool segment_clear(const Vector2 &p_from, const Vector2 &p_to, double p_road_margin) const;
	Vector2i cell(const Vector2 &p_point) const;
	PackedVector2Array path_from(const Vector2 &p_from, const Vector2 &p_target, bool p_fly);
	PackedVector2Array join_path(const Vector2 &p_from, const PackedVector2Array &p_path, bool p_avoid_heroes) const;
	PackedByteArray road_mask(double p_monster_radius) const;
};

} // namespace godot
