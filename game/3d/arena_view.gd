extends StellarView
class_name ArenaView

## HUD overlays the full world texture; follow and picking use the open field.
var battle_box := Rect2(0, 70, 1280, 490)
var minimap_box := Rect2(1088, 88, 174, 130)
var _follow_offset := Vector3.ZERO
var _camera_initialized := false
var _camera_sim = null

func attach(parent: CanvasItem, rect: Rect2) -> void:
	box = rect
	if viewport == null or not is_instance_valid(viewport):
		viewport = SubViewport.new()
		viewport.name = "Arena3DViewport"
		viewport.own_world_3d = true
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_2X
		parent.add_child(viewport)
		world = ArenaWorld.new()
		viewport.add_child(world)
	var wanted := Vector2i(maxi(64, int(rect.size.x)), maxi(64, int(rect.size.y)))
	if viewport.size != wanted:
		viewport.size = wanted
	_apply_camera(_follow_offset)

func _active_box() -> Rect2:
	return battle_box.intersection(box)

func _apply_camera(offset: Vector3) -> void:
	world.camera_target = offset
	world.camera_update()
	# Reframe the fixed orthographic view into the space between the HUD strips.
	var center := box.get_center()
	var focus := _active_box().get_center()
	var a := world.ground_at(center - box.position)
	var b := world.ground_at(focus - box.position)
	world.camera.position += Vector3((a.x - b.x) / StellarWorld.UNIT, 0,
		(a.y - b.y) / StellarWorld.UNIT)

func _ground_shift(from: Vector2, to: Vector2) -> Vector3:
	var a := world.ground_at(from - box.position)
	var b := world.ground_at(to - box.position)
	return Vector3((a.x - b.x) / StellarWorld.UNIT, 0, (a.y - b.y) / StellarWorld.UNIT)

func _keep_crystal_visible(offset: Vector3) -> Vector3:
	_apply_camera(offset)
	var safe := _active_box().grow(-28)
	# Preserve the complete crystal, including its point and the altar's base.
	for height in [0.08, 1.95]:
		var pixel := project(Balance.ARENA_CENTER, height)
		var target := pixel.clamp(safe.position, safe.end)
		offset += _ground_shift(pixel, target)
		_apply_camera(offset)
	# A crystal at the upper right must not disappear underneath the minimap.
	var crystal := project(Balance.ARENA_CENTER, 1.0)
	var obstacle := minimap_box.grow(30)
	if obstacle.has_point(crystal):
		var left := Vector2(obstacle.position.x, crystal.y)
		var below := Vector2(crystal.x, obstacle.end.y)
		var target := left if crystal.distance_squared_to(left) < crystal.distance_squared_to(below) else below
		offset += _ground_shift(crystal, target)
	return offset

func follow_selected(at: Vector2, dt: float) -> void:
	if world == null or not at.is_finite(): return
	_apply_camera(_follow_offset)
	if _camera_initialized and dt <= 0.0: return
	var active := _active_box()
	var deadzone := Rect2(active.position + active.size * Vector2(0.34, 0.32),
		active.size * Vector2(0.32, 0.36))
	var pixel := project(at, 0.5)
	var desired := _follow_offset + _ground_shift(pixel, pixel.clamp(deadzone.position, deadzone.end))
	desired = _keep_crystal_visible(desired)
	var weight := 1.0 if not _camera_initialized else 1.0 - exp(-8.0 * minf(dt, 0.25))
	_follow_offset = _keep_crystal_visible(_follow_offset.lerp(desired, weight))
	_camera_initialized = true
	_apply_camera(_follow_offset)

func minimap_bounds() -> Rect2:
	return ArenaGeometry.MAP_RECT

func minimap_point(point: Vector2, rect: Rect2) -> Vector2:
	var bounds := minimap_bounds()
	return rect.position + ((point - bounds.position) / bounds.size).clamp(Vector2.ZERO, Vector2.ONE) * rect.size

func camera_ground_polygon() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if world == null: return polygon
	for point in ArenaGeometry.corners(_active_box()):
		polygon.append(world.ground_at(point - box.position))
	return polygon

func minimap_footprint(rect: Rect2) -> PackedVector2Array:
	if world == null: return PackedVector2Array()
	# Clip the actual oblique footprint before scaling, rather than clamping each
	# corner (which would distort the view area when it straddles the map edge).
	var clipped := Geometry2D.intersect_polygons(camera_ground_polygon(), ArenaGeometry.outline())
	var polygon := PackedVector2Array()
	if clipped.is_empty(): return polygon
	for point in clipped[0]: polygon.append(minimap_point(point, rect))
	return polygon

func draw_arena(ci: CanvasItem, rect: Rect2, theme: Dictionary, sim, selected: int, dt: float) -> void:
	attach(ci, rect)
	world.build_map(theme)
	world.actors.visible = sim != null
	world.projectiles.visible = sim != null
	_hero_hits.clear()
	if sim != _camera_sim:
		_camera_sim = sim
		_camera_initialized = false
		_follow_offset = Vector3.ZERO
	if sim != null:
		for hero in sim.heroes:
			hero["fx_t"] = float(hero.get("fx_t", 9.0)) + dt
		for e in sim.events:
			if String(e.get("t", "")) == "aim":
				var source := int(e.get("src", -1))
				if source >= 0 and source < sim.heroes.size():
					var hero: Dictionary = sim.heroes[source]
					hero["fx_t"] = 0.0
					hero["fx_w"] = float(e.get("w", 0.0))
					hero["fx_d"] = e.get("d", Vector2.DOWN)
			if String(e.get("t", "")) == "fire":
				Sfx.play(Sfx.shot_id(String(e.get("el", "none")), String(e.get("kind", "shot"))), -6.0, 1.0, 0.07)
			if String(e.get("t", "")) == "arena_boss":
				Sfx.play("boss")
			world.event(e)
		sim.events.clear()
		world.sync_battle(sim, sim.elapsed, 1, dt)
		var at := Vector2.INF
		var radius := 0.0
		for i in range(sim.heroes.size()):
			var data: Dictionary = sim.heroes[i]
			_hero_hits.append({"index": i, "post": i, "at": data["pos"]})
			if i == selected:
				at = data["pos"]
				radius = float(data.get("range", 0.0))
		world.set_selection(at, false, radius)
		follow_selected(at, dt)
	else:
		world.set_selection(Vector2.INF, false)
		_apply_camera(Vector3.ZERO)
	ci.draw_texture_rect(viewport.get_texture(), rect, false)
	if sim == null: return
	for item in world.texts:
		var at := project(item["p"], 1.1) + Vector2(0, -float(item["age"]) * 30)
		if not rect.grow(-12).has_point(at): continue
		var color: Color = item["color"]
		color.a = clampf(1.5 - float(item["age"]) * 2, 0, 1)
		Look.text_center_out(ci, at, Fx._short_num(float(item["n"])), 19 if item["big"] else 14, color, Look.BG_DEEP, 1.5)

func camera_input(_e: InputEvent) -> bool:
	return false

func camera_button(_id: String) -> bool:
	return false
