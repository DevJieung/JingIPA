extends RefCounted
class_name StellarBackdrop

static func draw(ci: CanvasItem, rect: Rect2, theme: Dictionary, time: float = 0.0, camp: bool = false) -> void:
	var view: StellarView = ci.get_meta("stellar_backdrop") if ci.has_meta("stellar_backdrop") else null
	if view==null:
		view=StellarView.new()
		ci.set_meta("stellar_backdrop",view)
	view.attach(ci,rect)
	view.world.build_map(theme)
	view.world.yaw=-0.22
	view.world.zoom=1.06
	view.world.camera_update()
	view.world.weather_update(time)
	for gem in view.world.crystals: gem.visible=true
	ci.draw_texture_rect(view.viewport.get_texture(),rect,false)
	ci.draw_rect(rect,Color(0.035,0.065,0.10,0.50 if camp else 0.19))
