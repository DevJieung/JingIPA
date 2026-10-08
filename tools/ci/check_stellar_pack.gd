extends SceneTree


func _initialize() -> void:
	var manifest_path := "res://art/models/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		_fail("Missing packaged 3D model manifest")
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary or not data.get("heroes") is Dictionary or data["heroes"].size() != 50:
		_fail("Incomplete packaged 3D hero profiles")
		return
	for identity in data["heroes"]:
		for grade in range(10):
			if not ResourceLoader.exists("res://art/models/portraits/%s/%02d.png" % [identity, grade]):
				_fail("Missing packaged ranked 3D portrait: %s/%d" % [identity, grade])
				return
	for module in ["stellar_models", "stellar_world", "stellar_view", "stellar_portraits", "stellar_backdrop"]:
		if not ResourceLoader.exists("res://game/3d/%s.gd" % module):
			_fail("Missing packaged 3D rendering module: " + module)
			return
	if ProjectSettings.get_setting("application/config/name") != "스텔라 디펜스":
		_fail("Exported pack has the previous game identity")
		return
	print("3D pack verified: Stellar Defense identity, 50 hero profiles and five rendering modules")
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
