extends "res://tests/3d/native_monster_visual_preview.gd"

func _ready() -> void:
	if not require_no_save(): return
	check("--density" in OS.get_cmdline_user_args(),"density fixture explicit mode")
	check(NativeCharacterModel.manifest()["ready_ids"].size()==49,"density final new hero coverage")
	check(NativeMonsterModel.manifest()["ready_ids"].size()==25,"density final monster coverage")
	if failures:
		get_tree().quit(1)
		return
	out_dir=arg("--out","build/character-3d/density-review/1280x800")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _battle()
	print("Actual final native density visual capture: "+out_dir)
	call_deferred("_cleanup_and_quit")
