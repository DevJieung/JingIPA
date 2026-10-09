extends StellarView
class_name ArenaView

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
		world.camera_update()

func draw_arena(ci: CanvasItem, rect: Rect2, theme: Dictionary, sim, selected: int, dt: float) -> void:
	attach(ci, rect)
	world.build_map(theme)
	world.actors.visible = sim != null
	world.projectiles.visible = sim != null
	_hero_hits.clear()
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
	else:
		world.set_selection(Vector2.INF, false)
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
