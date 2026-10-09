extends SceneTree


func _initialize() -> void:
	for module in ["core/arena_run", "core/arena_validation", "game/arena_sim", "game/arena_screen", "game/3d/arena_view", "game/3d/arena_world"]:
		if not ResourceLoader.exists("res://%s.gd" % module):
			_fail("Missing packaged continuous battle module: " + module)
			return
	var balance: Script = load("res://core/balance.gd")
	if balance.ARENA_HERO_LIMIT != 6 or balance.ARENA_BOSS_AT != 1080.0:
		_fail("Packaged continuous battle balance differs from approved data")
		return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://core/locales/ui.json"))
	if not catalog is Dictionary:
		_fail("Missing packaged UI translations")
		return
	for locale in ["ko", "en"]:
		for key in ["arena.title", "arena.rules.control", "arena.rules.growth", "arena.rules.boss"]:
			if not catalog.get(locale, {}).get(key):
				_fail("Missing packaged continuous battle translation: %s/%s" % [locale, key])
				return
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
		var awakened_grade := floori(float(data["heroes"][identity]["index"])/5.0)
		if not ResourceLoader.exists("res://art/models/portraits/%s/%02d_awakened.png" % [identity, awakened_grade]):
			_fail("Missing packaged awakened 3D portrait: " + identity)
			return
	for module in ["stellar_models", "stellar_world", "stellar_view", "stellar_portraits", "stellar_backdrop"]:
		if not ResourceLoader.exists("res://game/3d/%s.gd" % module):
			_fail("Missing packaged 3D rendering module: " + module)
			return
	if not ResourceLoader.exists("res://game/3d/limne_model.gd"):
		_fail("Missing packaged Limne model adapter")
		return
	if not ResourceLoader.exists("res://art/models/limne/water_spray.gdshader", "Shader"):
		_fail("Missing packaged Limne water shader")
		return
	var limne := ResourceLoader.load("res://art/models/limne/limne.glb") as PackedScene
	if limne == null:
		_fail("Missing imported Limne GLB payload")
		return
	var model := limne.instantiate()
	for pivot in ["Body", "ArmL", "ArmR", "LegL", "LegR"]:
		if not model.find_child(pivot, true, false) is Node3D:
			model.free()
			_fail("Packaged Limne is missing its animation pivot: " + pivot)
			return
	if not _has_textured_skin(model):
		model.free()
		_fail("Packaged Limne is missing its skinned geometry or surface texture")
		return
	if not _has_motion_rig(model):
		model.free()
		_fail("Packaged Limne is missing its aiming joints")
		return
	model.free()
	var native_path := "res://art/models/native_heroes.json"
	if not FileAccess.file_exists(native_path) or not ResourceLoader.exists("res://game/3d/native_character_model.gd"):
		_fail("Missing packaged native hero manifest or adapter")
		return
	var native: Variant = JSON.parse_string(FileAccess.get_file_as_string(native_path))
	if not native is Dictionary or not native.get("heroes") is Dictionary or not native.get("ready_ids") is Array:
		_fail("Invalid packaged native hero manifest")
		return
	if native["heroes"].size() != data["heroes"].size()-1 or native["ready_ids"].size() != data["heroes"].size()-1:
		_fail("Incomplete native hero coverage")
		return
	for identity in data["heroes"]:
		if identity == "limne": continue
		if identity not in native["ready_ids"] or not native["heroes"].has(identity):
			_fail("Native hero was not visually reviewed: " + identity)
			return
		if not native["heroes"][identity].get("ready", false):
			_fail("Native hero review state is incomplete: " + identity)
			return
		var path := "res://art/models/%s/%s.glb" % [identity, identity]
		if native["heroes"][identity].get("path") != path:
			_fail("Invalid native hero resource path: " + identity)
			return
		var scene := ResourceLoader.load(path) as PackedScene
		if scene == null:
			_fail("Missing packaged native hero payload: " + identity)
			return
		var hero := scene.instantiate()
		var valid := _has_textured_skin(hero) and _has_native_motion(hero)
		for pivot in ["Body", "ArmL", "ArmR", "LegL", "LegR"]:
			valid = valid and hero.find_child(pivot, true, false) is Node3D
		hero.free()
		if not valid:
			_fail("Packaged native hero is missing skin, textures, rig or clips: " + identity)
			return
	var monsters_path := "res://art/models/native_monsters.json"
	if not FileAccess.file_exists(monsters_path) or not ResourceLoader.exists("res://game/3d/native_monster_model.gd"):
		_fail("Missing packaged native monster manifest or adapter")
		return
	var monsters: Variant = JSON.parse_string(FileAccess.get_file_as_string(monsters_path))
	if not monsters is Dictionary or not monsters.get("monsters") is Dictionary or not monsters.get("ready_ids") is Array:
		_fail("Invalid packaged native monster manifest")
		return
	var monster_roster: Array = load("res://core/roster.gd").MONSTERS
	if monster_roster.size() != 25 or monsters["monsters"].size() != 25 or monsters["ready_ids"].size() != 25:
		_fail("Incomplete native monster coverage")
		return
	for monster_data in monster_roster:
		var identity := String(monster_data["id"])
		if identity not in monsters["ready_ids"] or not monsters["monsters"].has(identity) or not monsters["monsters"][identity].get("ready", false):
			_fail("Native monster was not visually reviewed: " + identity)
			return
		var path := "res://art/models/monsters/%s/%s.glb" % [identity, identity]
		if monsters["monsters"][identity].get("path") != path:
			_fail("Invalid native monster resource path: " + identity)
			return
		if not ResourceLoader.exists("res://art/models/monsters/%s.png" % identity):
			_fail("Missing packaged native monster portrait: " + identity)
			return
		var scene := ResourceLoader.load(path) as PackedScene
		if scene == null:
			_fail("Missing packaged native monster payload: " + identity)
			return
		var model_node := scene.instantiate()
		var rig := _native_skeleton(model_node)
		var player := _native_player(model_node)
		var valid := _has_textured_skin(model_node) and rig != null and player != null
		if rig != null:
			valid = valid and rig.get_bone_count() == int(monsters["monsters"][identity].get("rig", 0)) and rig.get_bone_count() > 0
		if player != null:
			for clip in ["IdleLoop", "MoveLoop"]:
				var found := false
				for name in player.get_animation_list():
					found = found or String(name).ends_with(clip)
				valid = valid and found
		model_node.free()
		if not valid:
			_fail("Packaged native monster is missing skin, texture, body-specific rig or clips: " + identity)
			return
	if ProjectSettings.get_setting("application/config/name") != "스텔라 디펜스":
		_fail("Exported pack has the previous game identity")
		return
	print("3D pack verified: Stellar Defense identity, 50 native heroes, 25 native monsters, textures, rigs and motion clips")
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)


func _has_textured_skin(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null and node.skin != null:
		for surface in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface)
			if material is BaseMaterial3D and material.albedo_texture != null: return true
	for child in node.get_children():
		if _has_textured_skin(child): return true
	return false


func _has_motion_rig(node: Node) -> bool:
	if node is Skeleton3D:
		for name in ["SkinForearmL", "SkinForearmR", "SkinHandL", "SkinHandR"]:
			if node.find_bone(name) < 0: return false
		return true
	for child in node.get_children():
		if _has_motion_rig(child): return true
	return false


func _has_native_motion(node: Node) -> bool:
	var skeleton := _native_skeleton(node)
	var player := _native_player(node)
	if skeleton == null or player == null: return false
	for name in ["SkinBody", "SkinArmL", "SkinArmR", "SkinLegL", "SkinLegR"]:
		if skeleton.find_bone(name)<0: return false
	var idle := false
	var attack := false
	for name in player.get_animation_list():
		idle = idle or String(name).ends_with("IdleLoop")
		attack = attack or String(name).ends_with("Attack")
	return idle and attack


func _native_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var result := _native_skeleton(child)
		if result != null: return result
	return null


func _native_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var result := _native_player(child)
		if result != null: return result
	return null
