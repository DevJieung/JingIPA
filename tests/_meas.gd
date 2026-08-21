extends SceneTree
func _init() -> void:
	var f := ThemeDB.fallback_font
	print("font=", f, " res=", f.resource_path if f != null else "nil")
	for s in [150,145,140,130,120,110,100,92,96]:
		var w := f.get_string_size("로열 스트레이트 플러시", HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
		print("size=", s, " w=", w, " plate=", w+80.0)
	for nm in ["로열 스트레이트 플러시","스트레이트 플러시","포카드","풀하우스"]:
		print(nm, " @150 = ", f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 150).x)
	quit()
