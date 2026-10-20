#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

/// The roads of the circular battlefield: ArenaGeometry's point and segment tests.
/// Same definition as the GDScript reference (ArenaGeometry.on_road_exhaustive): a point
/// is on the road when it is inside the rim, and inside the plaza or within half the
/// road width (less the margin) of a centreline segment. Same broad phase too (every
/// segment listed in the grid cells its bounding box touches) and the same float32
/// vector arithmetic, so the answers agree with the GDScript everywhere.
class StellarRoads : public RefCounted {
	GDCLASS(StellarRoads, RefCounted)

	Vector2 center;
	double radius = 600.0;
	double plaza_radius = 103.0;
	double road_width = 116.0;
	Rect2 map_rect;
	double grid = 60.0;
	int grid_w = 0;
	std::vector<std::vector<int32_t>> cells;
	std::vector<Vector2> seg_a;
	std::vector<Vector2> seg_b;

protected:
	static void _bind_methods();

public:
	/// Geometry2D.get_closest_point_to_segment, as the engine computes it.
	static Vector2 closest_point(const Vector2 &p_point, const Vector2 &p_a, const Vector2 &p_b);

	void configure(const Vector2 &p_center, double p_radius, double p_plaza_radius, double p_road_width, const Rect2 &p_map_rect, double p_grid, const Array &p_roads);
	bool contains(const Vector2 &p_point, double p_margin = 0.0) const;
	Vector2 clamp_point(const Vector2 &p_point, double p_margin = 0.0) const;
	bool on_road(const Vector2 &p_point, double p_margin = 0.0) const;
	/// ArenaSim._road_segment_clear: the segment sampled every `step` units (both ends
	/// included) must lie on the road.
	bool segment_on_road(const Vector2 &p_from, const Vector2 &p_to, double p_margin, double p_step) const;
	Vector2 nearest_road_point(const Vector2 &p_point) const;
	Vector2 road_direction(const Vector2 &p_point) const;
	int segment_count() const { return (int)seg_a.size(); }
};

} // namespace godot
