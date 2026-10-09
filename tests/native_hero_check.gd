extends Harness

## --ids checks a production pilot; the default requires the entire roster.
func _ready() -> void:
	if not require_no_save(): return
	var selected := arg("--ids", "")
	var wanted := selected.split(",") if selected != "" else PackedStringArray()
	var units: Array[Dictionary] = []
	var expected: Array[String] = []
	for unit in Roster.UNITS:
		if unit["id"] == "limne": continue
		expected.append(String(unit["id"]))
		if wanted.is_empty() or String(unit["id"]) in wanted: units.append(unit)
	check(not units.is_empty(), "native validation has actual roster subjects")
	var manifest := NativeCharacterModel.manifest()
	if wanted.is_empty():
		var ready: Array = manifest.get("ready_ids", [])
		check(ready.size() == expected.size(), "all additional heroes passed visual review")
		check(manifest.get("heroes", {}).size() == expected.size(), "native manifest covers exactly the additional roster")
		for id in expected: check(id in ready, "native model reviewed: " + id)
	for unit in units:
		await _character_contract(unit)
	if failures == 0 and not units.is_empty(): await _world_contract(units[0])
	StellarModels._rigs.clear()
	finish("Native 영웅·이벤트 모션·데이터 보존" + (" (지정 샘플)" if selected != "" else " (전체)"))

func _character_contract(unit: Dictionary) -> void:
	var id := String(unit["id"])
	check(NativeCharacterModel.has_model(id), id + ": visually reviewed native model is available")
	if not NativeCharacterModel.has_model(id): return
	var original := unit.duplicate(true)
	var row: Dictionary = NativeCharacterModel.manifest()["heroes"][id]
	check(bool(row.get("ready", false)), id + ": published roster agrees with the character's review state")
	var path := String(row["path"])
	check(FileAccess.get_sha256(path) == String(row.get("glb_sha256", "")), id + ": reviewed fingerprint matches the runtime source")
	for grade in [0, 4, 9]:
		var model := StellarModels.hero(unit, grade)
		check(model is NativeCharacterModel, "%s/%d: factory dispatches the native adapter" % [id, grade])
		check(model.get_meta("identity", "") == id and model.get_meta("grade", -1) == grade,
			"%s/%d: identity and rank are preserved" % [id, grade])
		check(model.get_meta("model_source", "") == path, id + ": actual native GLB is used")
		for name in ["Body", "ArmL", "ArmR", "LegL", "LegR"]:
			check(model.get_node_or_null(name) is Node3D, id + ": direct pivot " + name)
		check(_textured_skin(model), id + ": geometry has skin weights, UVs and an albedo texture")
		var skeleton := _skeleton(model)
		check(skeleton != null and skeleton.get_bone_count() >= 5, id + ": imported deformation skeleton")
		check(skeleton != null and skeleton.get_bone_count() == int(row.get("rig", 0)), id + ": declared character rig matches the actual native skin")
		model.free()
	for tier in range(10):
		for fusion in Roster.fusion_units(tier):
			if fusion.get("base_id", "") != id: continue
			var model := StellarModels.hero(fusion, tier)
			check(model is NativeCharacterModel and model.get_meta("model_source", "") == path,
				id + ": awakened form uses its native base model")
			model.free()
	var first := StellarModels.hero(unit, 4) as NativeCharacterModel
	var second := StellarModels.hero(unit, 4) as NativeCharacterModel
	if first == null or second == null:
		if first != null: first.free()
		if second != null: second.free()
		return
	add_child(first)
	add_child(second)
	await frames(1)
	var skeleton := _skeleton(first)
	var player := _player(first)
	for socket in row.get("sockets", []):
		check(skeleton != null and skeleton.find_bone(String(socket["bone"])) >= 0,
			id + ": each declared release socket resolves to an actual imported bone")
	check(player != null and _has_clip(player, "IdleLoop") and _has_clip(player, "Attack"),
		id + ": real idle and attack animation clips import")
	first.animate_visual(0)
	second.animate_visual(0)
	var idle := _poses(skeleton)
	var second_idle := _poses(_skeleton(second))
	var resources := _resources(first)
	var artillery := String(row.get("attack", "")) == "artillery"
	if artillery:
		check(not row.get("sockets", []).is_empty(), id + ": mounted artillery declares its actual release port")
		for socket in row.get("sockets", []):
			var declared: Array = socket.get("physical_axis", [])
			var axis := Vector3.ZERO
			if declared.size() == 3:
				axis = Vector3(float(declared[0]), float(declared[1]), float(declared[2]))
			check(axis.is_finite() and absf(axis.length()-1.0)<0.01,
				id + ": artillery port has a measured unit axis in root rest space")
	first.animate_visual(6)
	check(_poses_close(idle, _poses(skeleton)), id + ": idle clip closes its loop")
	first.visual_event({"t": "aim", "w": 0.30})
	first.animate_visual(6.15, 0.15, 0.30, true)
	check(first.visual_phase() == 1 and is_zero_approx(first.fire_strength()), id + ": aim cannot emit a release")
	check(_poses(skeleton) != idle, id + ": actual attack clip articulates the imported skin")
	check(_poses(_skeleton(second)) == second_idle and is_zero_approx(second.fire_strength()),
		id + ": cached cards keep independent joint and effect state")
	first.animate_visual(6.36, 0.36, 0.30, true)
	check(first.visual_phase() == 3 and is_zero_approx(first.fire_strength()),
		id + ": missing actual fire cancels the prepared attack")
	first.animate_visual(6.70, 0.70, 0.30, true)
	var clock := 7.0
	for wind in [0.30, 0.02, 0.0]:
		first.animate_visual(clock, 9, wind, true)
		first.visual_event({"t": "aim", "w": wind})
		first.animate_visual(clock, wind, wind, true)
		check(is_zero_approx(first.fire_strength()), "%s: raw wind %.2f alone never fires" % [id, wind])
		first.visual_event({"t": "fire"})
		first.animate_visual(clock+0.065, wind + 0.065, wind, true)
		check(first.visual_phase() == 2 and first.fire_strength() > 0.01, "%s: actual fire supports raw wind %.2f" % [id, wind])
		if String(row.get("attack", "")) in ["gun", "rifle"]:
			var rotation_before := first.rotation
			for angle in [0.0, PI*0.5, PI, PI*1.5]:
				first.rotation.y = rotation_before.y+angle
				var facing := (first.global_basis*Vector3.FORWARD).normalized()
				for side in [-1, 1] if row.get("sockets", []).size() > 1 else [-1]:
					var mouth := first.weapon_transform(side)
					var forward := (mouth.basis*Vector3.FORWARD).normalized()
					check(mouth.origin.is_finite() and forward.dot(facing)>0.95,
						id + ": gun release sockets align with actual facing in every cardinal direction")
			first.rotation = rotation_before
		elif artillery:
			_artillery_release_contract(first, second, skeleton, row, id)
		first.visual_event({"t": "aim", "w": wind})
		first.animate_visual(clock+0.065, 0, wind, true)
		check(is_zero_approx(first.fire_strength()), id + ": next aim clears a previous release")
		first.visual_event({"t": "cancel"})
		first.animate_visual(clock+0.065, 1, wind, true)
		clock += 1.0
	first.animate_visual(clock, 1, 0.30, true)
	check(first.visual_phase() == 0 and is_zero_approx(first.fire_strength()), id + ": recovery returns to idle")
	if artillery:
		for n in row.get("sockets", []).size():
			var release := first.get_node_or_null("NativeRelease"+str(n)) as Node3D
			check(release != null and not release.visible, id + ": artillery pressure ends after actual release recovery")
	first.animate_visual(clock, 1, 0.30, false)
	check(is_zero_approx(first.fire_strength()), id + ": previews clear combat state")
	check(_resources(first) == resources, id + ": motion reuses nodes, meshes and materials")
	check(unit == original, id + ": model creation leaves roster data unchanged")
	first.free()
	second.free()

func _artillery_release_contract(model: NativeCharacterModel, other: NativeCharacterModel,
		skeleton: Skeleton3D, row: Dictionary, id: String) -> void:
	var before := model.rotation
	for angle in [0.0, PI*0.5, PI, PI*1.5]:
		model.rotation.y = before.y+angle
		var skeleton_to_root := model.global_transform.affine_inverse()*skeleton.global_transform
		for n in row.get("sockets", []).size():
			var socket: Dictionary = row["sockets"][n]
			var xyz: Array = socket.get("physical_axis", [])
			var bone := skeleton.find_bone(String(socket["bone"]))
			if xyz.size() != 3 or bone < 0: continue
			var axis := Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
			var rest := skeleton_to_root*skeleton.get_bone_global_rest(bone)
			var posed := skeleton_to_root*skeleton.get_bone_global_pose(bone)
			var expected := (model.global_basis*(posed.basis*rest.basis.inverse())*axis).normalized()
			var mouth := model.weapon_transform(-1 if n == 0 else 1)
			var forward := (mouth.basis*Vector3.FORWARD).normalized()
			check(mouth.origin.is_finite() and forward.is_finite() and forward.dot(expected)>0.995,
				id + ": artillery socket follows its physical port axis at every facing")
			var release := model.get_node_or_null("NativeRelease"+str(n)) as Node3D
			var independent := other.get_node_or_null("NativeRelease"+str(n)) as Node3D
			check(release != null and release.visible and independent != null and not independent.visible,
				id + ": actual artillery release is visible only on the firing instance")
			if release != null:
				var pressure_axis := (release.global_basis*Vector3.FORWARD).normalized()
				check(release.global_position.distance_to(mouth.origin)<0.15 and pressure_axis.dot(expected)>0.995,
					id + ": pressure effect originates at the port and follows the physical axis")
	model.rotation = before

func _world_contract(unit: Dictionary) -> void:
	Fixture.fresh(9102026)
	Run.gain_hero(unit, 4, false)
	Run.ensure_posts()
	var sim := BattleSim.new()
	sim.setup(Run, 1, 9102026)
	var saved := Run.snapshot().duplicate(true)
	var sim_state := [sim.heroes.duplicate(true), sim.monsters.duplicate(true), sim.bullets.duplicate(true),
		sim._pending.duplicate(true), sim.events.duplicate(true), sim._rng.state, Run.rng.state]
	var stats := Run.hero_stats(Run.heroes[0]).duplicate(true)
	var world := StellarWorld.new()
	add_child(world)
	await frames(1)
	# Events precede the first rendered model, actual fire retargets, and the
	# generic VFX pool is full. All three must retain the native release.
	world.effects.resize(72)
	var aim := {"t": "aim", "src": 0, "d": Vector2.UP, "w": 0.02}
	var fire := {"t": "fire", "src": 0, "d": Vector2.RIGHT}
	var inputs := [aim.duplicate(true), fire.duplicate(true)]
	world.event(aim)
	world.event(fire)
	var visual := sim.heroes.duplicate(true)
	visual[0]["fx_t"] = 0.02
	visual[0]["fx_w"] = 0.02
	visual[0]["fx_d"] = Vector2.UP
	var before := visual.duplicate(true)
	world.sync_heroes(visual, 40, true)
	check(visual == before, "world sync leaves its input dictionaries unchanged")
	var model := world.hero_nodes.values()[0] as NativeCharacterModel
	check(model != null, "combat world uses the actual native hero")
	if model != null:
		world.sync_heroes(visual, 40.065, true)
		check(model.visual_phase() == 2 and model.fire_strength() > 0.01, "pre-spawn fast release survives the effect limit")
		var facing := model.basis * Vector3.FORWARD
		check(facing.dot(Vector3.RIGHT) > 0.999, "actual fire direction persists despite stale aim data")
		var release := model.fire_strength()
		world.sync_heroes(visual, 40.065, true)
		check(model.visual_phase() == 2 and is_equal_approx(model.fire_strength(), release), "paused simulation clock holds the native release pose")
		world.event({"t": "aim", "src": 0, "d": Vector2.LEFT, "w": 0.0})
		visual[0]["fx_t"] = 0
		visual[0]["fx_w"] = 0
		world.sync_heroes(visual, 40.1, true)
		check(is_zero_approx(model.fire_strength()) and (model.basis * Vector3.FORWARD).dot(Vector3.LEFT) > 0.999,
			"new zero-wind aim clears old release and retargets")
		world.event({"t": "fire", "src": 0, "d": Vector2.DOWN})
		world.sync_heroes(visual, 40.5, true)
		world.sync_heroes(visual, 40.565, true)
		check(model.visual_phase() == 2 and model.fire_strength() > 0.01, "fire between fast rendered frames retains its release")
		world.sync_heroes([sim.heroes[0]["h"]], 41, false)
		check(is_zero_approx(model.fire_strength()), "leaving battle clears native effects")
	check(aim == inputs[0] and fire == inputs[1], "bridge leaves simulation events unchanged")
	check(Run.snapshot() == saved and Run.hero_stats(Run.heroes[0]) == stats, "visuals preserve saves and combat stats")
	check([sim.heroes, sim.monsters, sim.bullets, sim._pending, sim.events, sim._rng.state, Run.rng.state] == sim_state,
		"visuals preserve combat state, pending damage, events and both RNGs")
	world.effects.clear()
	world.free()

func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var result := _skeleton(child)
		if result != null: return result
	return null

func _player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var result := _player(child)
		if result != null: return result
	return null

func _has_clip(player: AnimationPlayer, suffix: String) -> bool:
	for name in player.get_animation_list():
		if String(name).ends_with(suffix): return true
	return false

func _textured_skin(node: Node) -> bool:
	if node is MeshInstance3D and node.skin != null and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var mat := node.get_active_material(i) as BaseMaterial3D
			if mat != null and mat.albedo_texture != null and arrays[Mesh.ARRAY_TEX_UV] != null \
				and arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null: return true
	for child in node.get_children():
		if _textured_skin(child): return true
	return false

func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	if skeleton != null:
		for i in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(i))
	return result

func _poses_close(a: Array[Transform3D], b: Array[Transform3D]) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]): return false
	return true

func _resources(node: Node) -> Array:
	var result: Array = [node.get_instance_id()]
	if node is MeshInstance3D and node.mesh != null:
		result.append(node.mesh.get_instance_id())
		for i in node.mesh.get_surface_count():
			var mat: Material = node.get_active_material(i)
			if mat != null: result.append(mat.get_instance_id())
	for child in node.get_children(): result.append_array(_resources(child))
	return result
