extends "res://game/arena_screen.gd"
## Test-only ArenaScreen for the jewel-box captures (tests/box_game_preview.gd): the real screen,
## drawing the box modal through ArenaBoxView even before the screen's own draw match names it.
## Nothing in the game uses this file.

var _screen_draws_box := -1

func _draw() -> void:
	super._draw()
	if Arena.modal == "box" and not _box_drawn_by_screen():
		box_view.draw_box()

## Once ArenaScreen draws the box itself (its match has a "box" arm), this subclass stays out.
func _box_drawn_by_screen() -> bool:
	if _screen_draws_box < 0:
		var src: String = (load("res://game/arena_screen.gd") as GDScript).source_code
		_screen_draws_box = 1 if src.contains("\"box\": box_view") else 0
	return _screen_draws_box == 1
