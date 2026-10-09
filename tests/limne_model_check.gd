extends Harness

const MODEL_PATH := "res://art/models/limne/limne.glb"


func _ready() -> void:
	if not require_no_save(): return
	var unit: Dictionary = {}
	for candidate in Roster.UNITS:
		if candidate["id"] == "limne": unit = candidate
	check(not unit.is_empty(), "Limne roster identity exists")
	check(ResourceLoader.exists(MODEL_PATH, "PackedScene"), "Blender model imports as an actual 3D scene")
	if unit.is_empty() or not ResourceLoader.exists(MODEL_PATH, "PackedScene"):
		finish("Limne GLB integration")
		return
	var scene := ResourceLoader.load(MODEL_PATH) as PackedScene
	check(scene != null, "GLB payload loads")
	if scene == null:
		finish("Limne GLB integration")
		return
	var imported := scene.instantiate()
	check(_mesh_count(imported) > 0, "GLB contains renderable geometry")
	check(_skeleton(imported) != null, "GLB contains a deformable character skeleton")
	check(_skinned_mesh_count(imported) > 0, "character geometry contains skin weights")
	check(_textured_mesh_count(imported) > 0, "character retains its UV and surface texture")
	imported.free()
	for grade in range(10):
		var model := StellarModels.hero(unit, grade)
		check(model != null, "live model builds at grade %d" % grade)
		if model == null: continue
		check(model.get_meta("model_source", "") == MODEL_PATH, "live Limne uses imported model at grade %d" % grade)
		check(model.get_meta("identity", "") == "limne" and model.get_meta("grade", -1) == grade,
			"model preserves identity and per-card grade %d" % grade)
		check(_mesh_count(model) > 0, "live model retains geometry at grade %d" % grade)
		for pivot in ["Body", "ArmL", "ArmR", "LegL", "LegR"]:
			check(model.get_node_or_null(pivot) is Node3D, "existing animation pivot: %s/%d" % [pivot, grade])
		model.free()
	for grade in range(10):
		for guardian in Roster.fusion_units(grade):
			if guardian.get("base_id", "") != "limne": continue
			var model := StellarModels.hero(guardian, grade)
			check(model != null, "awakened model builds")
			if model == null: continue
			check(model.get_meta("model_source", "") == MODEL_PATH, "awakened Limne uses the same imported model")
			model.free()
	if failures > 0:
		finish("Limne GLB integration")
		return
	# Multiple cards of one hero must animate independently despite the shared cache.
	var first := StellarModels.hero(unit, 4)
	var second := StellarModels.hero(unit, 4)
	add_child(first)
	add_child(second)
	await frames(1)
	check(_brown_iris_surface_count(first) >= 2 and _brown_iris_surface_count(second) >= 2,
		"imported iris materials display the original brown vertex colors")
	var second_body := second.get_node("Body") as Node3D
	var second_arm := second.get_node("ArmR") as Node3D
	var body_before := second_body.transform
	var arm_before := second_arm.transform
	var first_skeleton := _skeleton(first)
	var second_skeleton := _skeleton(second)
	var first_poses := _bone_poses(first_skeleton)
	var second_poses := _bone_poses(second_skeleton)
	(first.get_node("Body") as Node3D).position.y += 0.2
	(first.get_node("ArmR") as Node3D).rotation.x = -1.3
	first.call("update_visuals")
	await frames(1)
	check(second_body.transform == body_before and second_arm.transform == arm_before,
		"cached instances have independent body and arm transforms")
	check(first_skeleton != null and first_skeleton.get_bone_count() >= 5,
		"body and limbs have deformation bones")
	check(_bone_poses(first_skeleton) != first_poses, "animation pivots drive the skinned model")
	check(_bone_poses(second_skeleton) == second_poses, "cached instances have independent bone poses")
	_motion_contract(first as LimneModel, second as LimneModel)
	first.free()
	second.free()
	await _battle_contract(unit)
	StellarModels._rigs.clear()
	StellarPortraits._cache.clear()
	finish("Limne GLB·등급·독립 모션·전투 데이터 보존 검사")


func _motion_contract(first: LimneModel, second: LimneModel) -> void:
	check(first != null and second != null, "live character exposes its motion adapter")
	if first == null or second == null: return
	var skeleton := _skeleton(first)
	for name in ["SkinForearmL", "SkinForearmR", "SkinHandL", "SkinHandR"]:
		check(skeleton.find_bone(name) >= 0, "articulated aiming joint: " + name)
	first.animate_visual(0.0)
	second.animate_visual(0.0)
	var idle := _bone_poses(skeleton)
	var other_idle := _bone_poses(_skeleton(second))
	var resources := _render_resources(first)
	first.animate_visual(6.0)
	check(_poses_close(idle, _bone_poses(skeleton), 0.0001), "idle motion joins smoothly after a complete loop")
	for age in [0.0, 0.15, 0.299]:
		first.animate_visual(0.0, age, 0.30, true)
		check(is_zero_approx(first.spray_strength()), "no water before damage release at %.3f" % age)
	first.animate_visual(0.0, 0.365, 0.30, true)
	check(first.spray_strength() > 0.5, "water appears during the actual release window")
	check(_bone_poses(skeleton) != idle, "aiming articulates the model")
	for side in ["L", "R"]:
		var index := skeleton.find_bone("SkinForearm" + side)
		if index >= 0:
			check(skeleton.get_bone_pose(index) != idle[index], "forearm bends during aiming: " + side)
		index = skeleton.find_bone("SkinLeg" + side)
		if index >= 0:
			check(skeleton.get_bone_pose(index) == idle[index], "stationary attack keeps the foot planted: " + side)
	check(_bone_poses(_skeleton(second)) == other_idle and is_zero_approx(second.spray_strength()),
		"one card's aiming and water do not animate another cached card")
	for age in [0.431, 0.52, 9.0]:
		first.animate_visual(0.0, age, 0.30, true)
		check(is_zero_approx(first.spray_strength()), "water stops after release at %.3f" % age)
	check(_poses_close(idle, _bone_poses(skeleton), 0.0001), "attack recovers to the same idle pose")
	for boundary in [0.30, 0.52]:
		first.animate_visual(0.0, boundary - 0.0001, 0.30, true)
		var before := _bone_poses(skeleton)
		first.animate_visual(0.0, boundary + 0.0001, 0.30, true)
		check(_poses_close(before, _bone_poses(skeleton), 0.002), "no pose jump at attack boundary %.2f" % boundary)
	first.animate_visual(0.0, 0.365, 0.30, false)
	check(is_zero_approx(first.spray_strength()), "non-battle previews do not emit combat water")
	check(_render_resources(first) == resources, "motion reuses nodes, meshes and materials across frames")


func _battle_contract(unit: Dictionary) -> void:
	Fixture.fresh(8102026)
	Run.gain_hero(unit, 4, false)
	for candidate in Roster.UNITS:
		if candidate["id"] == "limne": continue
		Run.gain_hero(candidate, [0, 4, 9][Run.heroes.size() % 3], false)
		if Run.heroes.size() == 12: break
	Run.ensure_posts()
	var sim := BattleSim.new()
	sim.setup(Run, 1, 8102026)
	var saved := Run.snapshot().duplicate(true)
	var heroes_before := sim.heroes.duplicate(true)
	var monsters_before := sim.monsters.duplicate(true)
	var bullets_before := sim.bullets.duplicate(true)
	var pending_before := sim._pending.duplicate(true)
	var events_before := sim.events.duplicate(true)
	var run_rng_before := Run.rng.state
	var sim_rng_before := sim._rng.state
	var stats: Array[Dictionary] = []
	for hero in Run.heroes: stats.append(Run.hero_stats(hero).duplicate(true))
	var world := StellarWorld.new()
	add_child(world)
	await frames(1)
	for phase in [0.0, 0.15, 0.30, 0.45, 9.0]:
		var visual_heroes := sim.heroes.duplicate(true)
		for hero in visual_heroes:
			hero["fx_t"] = phase
			hero["fx_w"] = 0.30
		world.sync_heroes(visual_heroes, phase, true)
		check(world.hero_nodes.size() == 12, "twelve mixed heroes during animation phase %.2f" % phase)
		var limne_count := 0
		for model in world.hero_nodes.values():
			if model.get_meta("identity", "") == "limne":
				limne_count += 1
				check(model.get_meta("model_source", "") == MODEL_PATH, "combat uses Limne GLB during idle and attack")
		check(limne_count == 1, "imported hero coexists with the other eleven hero identities")
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var visual_heroes := sim.heroes.duplicate(true)
		for hero in visual_heroes:
			hero["fx_t"] = 0.365
			hero["fx_w"] = 0.30
			hero["fx_d"] = direction
		var visual_before := visual_heroes.duplicate(true)
		world.sync_heroes(visual_heroes, 1.0, true)
		for model in world.hero_nodes.values():
			if not model is LimneModel: continue
			check(model.spray_strength() > 0.5, "world connects release timing to water strength")
			for side in [-1, 1]:
				var forward: Vector3 = (model.nozzle_transform(side).basis * Vector3.FORWARD).normalized()
				var target := Vector3(direction.x, 0.0, direction.y)
				check(forward.dot(target) > 0.98, "aimed nozzle follows target %s / side %d" % [direction, side])
		check(visual_heroes == visual_before, "motion reads visual timing and aim without writing hero data")
	check(Run.snapshot() == saved and Run.rng.state == run_rng_before, "model updates preserve saved state and summon RNG")
	check(sim.heroes == heroes_before and sim.monsters == monsters_before and sim.bullets == bullets_before,
		"model updates preserve combat origins, timers and projectiles")
	check(sim._pending == pending_before and sim.events == events_before and sim._rng.state == sim_rng_before,
		"model updates preserve pending damage, events and combat RNG")
	for index in range(Run.heroes.size()):
		check(Run.hero_stats(Run.heroes[index]) == stats[index], "visual equipment preserves combat stats")
	world.queue_free()
	await frames(2)


func _poses_close(a: Array[Transform3D], b: Array[Transform3D], tolerance: float) -> bool:
	if a.size() != b.size(): return false
	for index in range(a.size()):
		if a[index].origin.distance_to(b[index].origin) > tolerance: return false
		for axis in range(3):
			if a[index].basis[axis].distance_to(b[index].basis[axis]) > tolerance: return false
	return true


func _render_resources(node: Node) -> Array[int]:
	var result: Array[int] = [node.get_instance_id()]
	if node is MeshInstance3D and node.mesh != null:
		result.append(node.mesh.get_instance_id())
		for surface in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface)
			if material != null: result.append(material.get_instance_id())
	for child in node.get_children(): result.append_array(_render_resources(child))
	return result


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and node.mesh != null else 0
	for child in node.get_children(): count += _mesh_count(child)
	return count


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null: return found
	return null


func _bone_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	if skeleton != null:
		for bone in range(skeleton.get_bone_count()):
			result.append(skeleton.get_bone_pose(bone))
	return result


func _skinned_mesh_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null and node.skin != null:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null:
				if not arrays[Mesh.ARRAY_BONES].is_empty() and not arrays[Mesh.ARRAY_WEIGHTS].is_empty():
					count += 1
	for child in node.get_children(): count += _skinned_mesh_count(child)
	return count


func _textured_mesh_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface)
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if material is BaseMaterial3D and material.albedo_texture != null:
				if arrays[Mesh.ARRAY_TEX_UV] != null and not arrays[Mesh.ARRAY_TEX_UV].is_empty():
					count += 1
	for child in node.get_children(): count += _textured_mesh_count(child)
	return count


func _brown_iris_surface_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface)
			if not material is BaseMaterial3D or material.resource_name != "Eye_brown_radial_iris": continue
			if not material.vertex_color_use_as_albedo: continue
			var colors: Variant = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			if colors == null: continue
			for color in colors:
				if color.r > color.g * 1.5 and color.g > color.b * 1.5:
					count += 1
					break
	for child in node.get_children(): count += _brown_iris_surface_count(child)
	return count
