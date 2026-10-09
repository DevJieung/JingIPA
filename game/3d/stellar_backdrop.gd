extends RefCounted
class_name StellarBackdrop

## Shared real arena scenery for title, camp, collection and result screens.
static func draw(ci: CanvasItem, rect: Rect2, theme: Dictionary, time: float = 0.0, camp: bool = false) -> void:
	var view: ArenaView = ci.get_meta("stellar_backdrop") if ci.has_meta("stellar_backdrop") else null
	if view == null:
		view = ArenaView.new()
		ci.set_meta("stellar_backdrop", view)
	view.attach(ci, rect)
	view.world.build_map(theme)
	view.world.camera.size = 19.8
	view.world.camera.position = Vector3(-3.5, 16.5, 19.5)
	view.world.camera.look_at(Vector3(0, 0.3, 0), Vector3.UP)
	view.world.weather_update(time)
	ci.draw_texture_rect(view.viewport.get_texture(), rect, false)
	ci.draw_rect(rect, Color(0.025, 0.055, 0.09, 0.46 if camp else 0.19))
