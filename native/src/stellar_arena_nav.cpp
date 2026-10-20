#include "stellar_arena_nav.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>

using namespace godot;

void StellarArenaNav::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "roads", "nav", "road_nav", "map_rect", "hero_radius", "monster_radius", "step"), &StellarArenaNav::setup);
	ClassDB::bind_method(D_METHOD("set_heroes", "positions"), &StellarArenaNav::set_heroes);
	ClassDB::bind_method(D_METHOD("road_segment_clear", "from", "to", "margin"), &StellarArenaNav::road_segment_clear);
	ClassDB::bind_method(D_METHOD("segment_clear", "from", "to", "road_margin"), &StellarArenaNav::segment_clear);
	ClassDB::bind_method(D_METHOD("cell", "point"), &StellarArenaNav::cell);
	ClassDB::bind_method(D_METHOD("path_from", "from", "target", "fly"), &StellarArenaNav::path_from);
	ClassDB::bind_method(D_METHOD("join_path", "from", "path", "avoid_heroes"), &StellarArenaNav::join_path);
	ClassDB::bind_method(D_METHOD("road_mask", "monster_radius"), &StellarArenaNav::road_mask);
}

void StellarArenaNav::setup(const Ref<StellarRoads> &p_roads, const Ref<AStarGrid2D> &p_nav, const Ref<AStarGrid2D> &p_road_nav, const Rect2 &p_map_rect, double p_hero_radius, double p_monster_radius, double p_step) {
	roads = p_roads;
	nav = p_nav;
	road_nav = p_road_nav;
	map_rect = p_map_rect;
	hero_radius = p_hero_radius;
	monster_radius = p_monster_radius;
	step = p_step;
	ERR_FAIL_COND(roads.is_null() || nav.is_null() || road_nav.is_null());
	cell_size = nav->get_cell_size();
	region = nav->get_region();
}

void StellarArenaNav::set_heroes(const PackedVector2Array &p_positions) {
	heroes.assign(p_positions.ptr(), p_positions.ptr() + p_positions.size());
}

bool StellarArenaNav::road_segment_clear(const Vector2 &p_from, const Vector2 &p_to, double p_margin) const {
	ERR_FAIL_COND_V(roads.is_null(), false);
	return roads->segment_on_road(p_from, p_to, p_margin, step);
}

bool StellarArenaNav::segment_clear(const Vector2 &p_from, const Vector2 &p_to, double p_road_margin) const {
	if (!road_segment_clear(p_from, p_to, p_road_margin)) {
		return false;
	}
	double radius = hero_radius + monster_radius;
	for (const Vector2 &p : heroes) {
		Vector2 near = StellarRoads::closest_point(p, p_from, p_to);
		if ((double)near.distance_squared_to(p) < radius * radius) {
			return false;
		}
	}
	return true;
}

Vector2i StellarArenaNav::cell(const Vector2 &p_point) const {
	Vector2 local = (p_point - map_rect.position) / cell_size;
	return Vector2i(CLAMP((int)Math::floor((double)local.x), 0, region.size.x - 1), CLAMP((int)Math::floor((double)local.y), 0, region.size.y - 1));
}

// The free grid cells around the start that the body can walk to in a straight line,
// nearest first. Insertion sort: Array.sort_custom sorts this few elements the same way,
// so equally distant cells (a body standing on a cell centre) keep their scan order.
std::vector<StellarArenaNav::Candidate> StellarArenaNav::candidates(const Vector2 &p_from, const Ref<AStarGrid2D> &p_grid, bool p_avoid_heroes) const {
	std::vector<Candidate> out;
	Vector2i start = cell(p_from);
	for (int y = start.y - 1; y <= start.y + 1; y++) {
		for (int x = start.x - 1; x <= start.x + 1; x++) {
			Vector2i c(x, y);
			if (!region.has_point(c) || p_grid->is_point_solid(c)) {
				continue;
			}
			Vector2 at = p_grid->get_point_position(c);
			bool clear = p_avoid_heroes ? segment_clear(p_from, at, monster_radius) : road_segment_clear(p_from, at, monster_radius);
			if (!clear) {
				continue;
			}
			Candidate candidate = { c, p_from.distance_squared_to(at) };
			size_t i = out.size();
			out.push_back(candidate);
			while (i > 0 && candidate.distance < out[i - 1].distance) {
				out[i] = out[i - 1];
				i--;
			}
			out[i] = candidate;
		}
	}
	return out;
}

PackedVector2Array StellarArenaNav::path_from(const Vector2 &p_from, const Vector2 &p_target, bool p_fly) {
	ERR_FAIL_COND_V(nav.is_null() || road_nav.is_null(), PackedVector2Array());
	Vector2i end = cell(p_target);
	if (p_fly) {
		// Flyers follow the road only: the guardians' bodies are no obstacle to them.
		if (!road_segment_clear(p_from, p_from, monster_radius)) {
			return PackedVector2Array();
		}
		for (const Candidate &candidate : candidates(p_from, road_nav, false)) {
			PackedVector2Array path = road_nav->get_point_path(candidate.cell, end);
			if (!path.is_empty()) {
				return join_path(p_from, path, false);
			}
		}
		return PackedVector2Array();
	}
	// A coarse blocked cell can contain a collision-free starting point: enter a visible
	// free neighbour rather than trapping the body for ever.
	if (!segment_clear(p_from, p_from, monster_radius)) {
		return PackedVector2Array();
	}
	PackedVector2Array fallback;
	for (const Candidate &candidate : candidates(p_from, nav, true)) {
		PackedVector2Array path = nav->get_point_path(candidate.cell, end);
		if (!path.is_empty()) {
			return join_path(p_from, path, true);
		}
		if (fallback.is_empty()) {
			fallback = road_nav->get_point_path(candidate.cell, end);
		}
	}
	// A distant guardian can seal a lane: follow the road up to it (every movement
	// segment still checks the real collision radius).
	return join_path(p_from, fallback, false);
}

PackedVector2Array StellarArenaNav::join_path(const Vector2 &p_from, const PackedVector2Array &p_path, bool p_avoid_heroes) const {
	// Join ahead of the nearest grid centre while it is in view, with half the road
	// sampling interval of clearance so a shortcut cannot graze a bend.
	double margin = monster_radius + 3.0;
	int skip = 0;
	int size = p_path.size();
	while (size - skip > 1) {
		const Vector2 &next = p_path[skip + 1];
		bool clear = p_avoid_heroes ? segment_clear(p_from, next, margin) : road_segment_clear(p_from, next, margin);
		if (!clear) {
			break;
		}
		skip++;
	}
	return skip == 0 ? p_path : p_path.slice(skip);
}

PackedByteArray StellarArenaNav::road_mask(double p_monster_radius) const {
	PackedByteArray mask;
	ERR_FAIL_COND_V(nav.is_null() || roads.is_null(), mask);
	Vector2i size = region.size;
	mask.resize((int64_t)size.x * size.y);
	mask.fill(0);
	uint8_t *out = mask.ptrw();
	// Insertion order of the GDScript dictionary of shallow cells: row by row.
	std::vector<Vector2i> shallow_cells;
	std::vector<int> depth((size_t)size.x * size.y, -1);
	double reach = p_monster_radius + (double)cell_size.length() + 0.1;
	const double margins[3] = { 14.0, 17.0, 20.0 };
	for (int y = 0; y < size.y; y++) {
		for (int x = 0; x < size.x; x++) {
			Vector2 at = nav->get_point_position(Vector2i(x, y));
			if (!roads->on_road(at, p_monster_radius + 1)) {
				continue;
			}
			out[(size_t)y * size.x + x] = 1;
			// Deep cells keep every step to a neighbour inside the road; only cells near
			// a kerb can be part of a notch (below).
			if (roads->on_road(at, reach)) {
				continue;
			}
			int d = 0;
			for (double margin : margins) {
				if (roads->on_road(at, margin)) {
					d++;
				}
			}
			depth[(size_t)y * size.x + x] = d;
			shallow_cells.push_back(Vector2i(x, y));
		}
	}
	// Where two road shapes meet at an angle the kerbs leave a notch thinner than a
	// cell: both neighbours are open, yet the straight step between their centres leaves
	// the road. Close the shallower cell of every such pair.
	const Vector2i steps[4] = { Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1) };
	auto index_of = [&](const Vector2i &c) { return (size_t)c.y * size.x + c.x; };
	auto is_shallow = [&](const Vector2i &c) { return c.x >= 0 && c.y >= 0 && c.x < size.x && c.y < size.y && depth[index_of(c)] >= 0; };
	for (const Vector2i &c : shallow_cells) {
		if (out[index_of(c)] == 0) {
			continue;
		}
		for (const Vector2i &s : steps) {
			Vector2i other = c + s;
			if (!is_shallow(other) || out[index_of(other)] == 0) {
				continue;
			}
			Vector2 from = nav->get_point_position(c);
			Vector2 to = nav->get_point_position(other);
			int samples = (int)Math::ceil((double)from.distance_to(to) / 1.5);
			bool inside = true;
			for (int i = 1; i < samples; i++) {
				if (!roads->on_road(from.lerp(to, (real_t)((double)i / samples)), p_monster_radius)) {
					inside = false;
					break;
				}
			}
			if (inside) {
				continue;
			}
			Vector2i shut = depth[index_of(c)] <= depth[index_of(other)] ? c : other;
			out[index_of(shut)] = 0;
			if (shut == c) {
				break;
			}
		}
	}
	return mask;
}
