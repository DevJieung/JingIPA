extends RefCounted
class_name StellarBackdrop

## Shared real arena scenery for title, camp, collection and result screens.
##
## ★ F7 (2026-10-19, 「게임 끝나고 돌아오면 초기화면 배경이 사라져있음」): the view is Main's
##   persistent one (Main.backdrop_view(): one 3D world and render target for the whole
##   session, built under the boot loading cover) whenever the screen has a `main`. Before,
##   every TitleScreen built a brand-new world and 1280x800 render target inside its first
##   draw, in the same frame the arena's were being freed, and a world that failed to build
##   was never tried again. Screens built alone (tests, tools) keep the old per-CanvasItem
##   view in the "stellar_backdrop" meta.
## ★ A view without a world (it failed to build; ArenaView.attach tries again at most once a
##   second) draws a plain night gradient instead of calling into a null world every frame.
## ★ Battery saver (M13, 2026-10-19): Main's view is paced (Main.BACKDROP_PACE: one frame in
##   three, about 10 fps under the title's 30 fps cap) and this draw is its clock, so it rests
##   whenever the screen stops drawing (the pause menu stops the screen). Under a sheet of the
##   screen (overlay_open(): shop, stage select, squad, collection) or the menu it is frozen.
static func draw(ci: CanvasItem, rect: Rect2, theme: Dictionary, time: float = 0.0, camp: bool = false) -> void:
	var host: CanvasItem = ci
	var view: ArenaView = null
	var paced := false
	var main: Variant = ci.get("main")
	if main is CanvasItem and is_instance_valid(main) and main.has_method("backdrop_view"):
		view = main.backdrop_view()
		host = main
		paced = true
	else:
		view = ci.get_meta("stellar_backdrop") if ci.has_meta("stellar_backdrop") else null
		if view == null:
			view = ArenaView.new()
			ci.set_meta("stellar_backdrop", view)
	view.attach(host, rect)
	if view.world == null or not is_instance_valid(view.world) or view.viewport == null:
		draw_fallback(ci, rect, camp)
		return
	if paced:
		var menu: Variant = main.get("menu")
		var covered: bool = (ci.has_method("overlay_open") and bool(ci.call("overlay_open"))) \
			or (menu is Object and is_instance_valid(menu) and bool(menu.get("opened")))
		view.set_live(not covered)
		view.tick()
	var map_before := String(view.world._map_key)
	view.world.build_map(theme)
	# A new field (another screen's theme, a layout) shows at once, not on the next beat.
	if String(view.world._map_key) != map_before:
		view.refresh_once()
	view.world.camera.size = 19.8
	view.world.camera.position = Vector3(-3.5, 16.5, 19.5)
	view.world.camera.look_at(Vector3(0, 0.3, 0), Vector3.UP)
	view.world.weather_update(time)
	ci.draw_texture_rect(view.viewport.get_texture(), rect, false)
	ci.draw_rect(rect, Color(0.025, 0.055, 0.09, 0.46 if camp else 0.19))


## The stand-in when there is no 3D world: the deep night of the battle frame fading to the
## game's background, under the same shade, so the title UI still sits on a finished field.
static func draw_fallback(ci: CanvasItem, rect: Rect2, camp: bool = false) -> void:
	var top := Look.BG_DEEP
	var bottom := Look.BG_DEEP.lerp(Look.BG, 0.65)
	ci.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]), PackedColorArray([top, top, bottom, bottom]))
	ci.draw_rect(rect, Color(0.025, 0.055, 0.09, 0.46 if camp else 0.19))
