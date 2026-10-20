#include "stellar_roads.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <algorithm>

using namespace godot;

void StellarRoads::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "center", "radius", "plaza_radius", "road_width", "map_rect", "grid", "roads"), &StellarRoads::configure);
	ClassDB::bind_method(D_METHOD("contains", "point", "margin"), &StellarRoads::contains, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("clamp_point", "point", "margin"), &StellarRoads::clamp_point, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("on_road", "point", "margin"), &StellarRoads::on_road, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("segment_on_road", "from", "to", "margin", "step"), &StellarRoads::segment_on_road);
	ClassDB::bind_method(D_METHOD("nearest_road_point", "point"), &StellarRoads::nearest_road_point);
	ClassDB::bind_method(D_METHOD("road_direction", "point"), &StellarRoads::road_direction);
	ClassDB::bind_method(D_METHOD("segment_count"), &StellarRoads::segment_count);
}

Vector2 StellarRoads::closest_point(const Vector2 &p_point, const Vector2 &p_a, const Vector2 &p_b) {
	Vector2 p = p_point - p_a;
	Vector2 n = p_b - p_a;
	real_t l2 = n.length_squared();
	if (l2 < 1e-20f) {
		return p_a;
	}
	real_t d = n.dot(p) / l2;
	if (d <= 0.0f) {
		return p_a;
	} else if (d >= 1.0f) {
		return p_b;
	}
	return p_a + n * d;
}

void StellarRoads::configure(const Vector2 &p_center, double p_radius, double p_plaza_radius, double p_road_width, const Rect2 &p_map_rect, double p_grid, const Array &p_roads) {
	center = p_center;
	radius = p_radius;
	plaza_radius = p_plaza_radius;
	road_width = p_road_width;
	map_rect = p_map_rect;
	grid = p_grid;
	grid_w = (int)Math::ceil((double)map_rect.size.x / grid);
	cells.assign((size_t)grid_w * (size_t)grid_w, std::vector<int32_t>());
	seg_a.clear();
	seg_b.clear();
	for (int r = 0; r < p_roads.size(); r++) {
		PackedVector2Array road = p_roads[r];
		for (int i = 0; i + 1 < road.size(); i++) {
			int32_t index = (int32_t)seg_a.size();
			seg_a.push_back(road[i]);
			seg_b.push_back(road[i + 1]);
			Vector2 lo = (road[i].min(road[i + 1]) - map_rect.position) / (real_t)grid;
			Vector2 hi = (road[i].max(road[i + 1]) - map_rect.position) / (real_t)grid;
			int y0 = CLAMP((int)Math::floor((double)lo.y), 0, grid_w - 1);
			int y1 = CLAMP((int)Math::floor((double)hi.y), 0, grid_w - 1);
			int x0 = CLAMP((int)Math::floor((double)lo.x), 0, grid_w - 1);
			int x1 = CLAMP((int)Math::floor((double)hi.x), 0, grid_w - 1);
			for (int gy = y0; gy <= y1; gy++) {
				for (int gx = x0; gx <= x1; gx++) {
					cells[(size_t)gy * grid_w + gx].push_back(index);
				}
			}
		}
	}
}

bool StellarRoads::contains(const Vector2 &p_point, double p_margin) const {
	if (!p_point.is_finite()) {
		return false;
	}
	return (double)p_point.distance_squared_to(center) <= Math::pow(std::max(0.0, radius - p_margin) + 0.001, 2.0);
}

Vector2 StellarRoads::clamp_point(const Vector2 &p_point, double p_margin) const {
	return center + (p_point - center).limit_length((real_t)std::max(0.0, radius - p_margin));
}

bool StellarRoads::on_road(const Vector2 &p_point, double p_margin) const {
	if (!contains(p_point, p_margin)) {
		return false;
	}
	if ((double)p_point.distance_squared_to(center) <= Math::pow(std::max(0.0, plaza_radius - p_margin), 2.0)) {
		return true;
	}
	double half = std::max(0.0, road_width * 0.5 - p_margin);
	double half_sq = half * half;
	Vector2 local = p_point - map_rect.position;
	int x0 = CLAMP((int)Math::floor(((double)local.x - half) / grid), 0, grid_w - 1);
	int x1 = CLAMP((int)Math::floor(((double)local.x + half) / grid), 0, grid_w - 1);
	int y0 = CLAMP((int)Math::floor(((double)local.y - half) / grid), 0, grid_w - 1);
	int y1 = CLAMP((int)Math::floor(((double)local.y + half) / grid), 0, grid_w - 1);
	for (int gy = y0; gy <= y1; gy++) {
		for (int gx = x0; gx <= x1; gx++) {
			for (int32_t index : cells[(size_t)gy * grid_w + gx]) {
				if ((double)closest_point(p_point, seg_a[index], seg_b[index]).distance_squared_to(p_point) <= half_sq) {
					return true;
				}
			}
		}
	}
	return false;
}

bool StellarRoads::segment_on_road(const Vector2 &p_from, const Vector2 &p_to, double p_margin, double p_step) const {
	int samples = std::max(1, (int)Math::ceil((double)p_from.distance_to(p_to) / p_step));
	for (int i = 0; i <= samples; i++) {
		if (!on_road(p_from.lerp(p_to, (real_t)((double)i / samples)), p_margin)) {
			return false;
		}
	}
	return true;
}

Vector2 StellarRoads::nearest_road_point(const Vector2 &p_point) const {
	Vector2 nearest = center;
	double distance = p_point.distance_squared_to(nearest);
	for (size_t i = 0; i < seg_a.size(); i++) {
		Vector2 candidate = closest_point(p_point, seg_a[i], seg_b[i]);
		if ((double)candidate.distance_squared_to(p_point) < distance) {
			nearest = candidate;
			distance = candidate.distance_squared_to(p_point);
		}
	}
	return nearest;
}

Vector2 StellarRoads::road_direction(const Vector2 &p_point) const {
	double distance = Math::INF;
	Vector2 direction = (center - p_point).normalized();
	for (size_t i = 0; i < seg_a.size(); i++) {
		Vector2 candidate = closest_point(p_point, seg_a[i], seg_b[i]);
		if ((double)candidate.distance_squared_to(p_point) < distance) {
			distance = candidate.distance_squared_to(p_point);
			direction = (seg_b[i] - seg_a[i]).normalized();
		}
	}
	return direction;
}
