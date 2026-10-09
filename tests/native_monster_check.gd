extends Harness

const ADAPTER_PATH := "res://game/3d/native_monster_model.gd"
var adapter: Script

func _ready() -> void:
	if not require_no_save(): return
	check(ResourceLoader.exists(ADAPTER_PATH), "native monster adapter exists")
	if not ResourceLoader.exists(ADAPTER_PATH):
		finish("Native 몬스터·이동 시계·데이터 보존")
		return
	adapter = load(ADAPTER_PATH)
	var selected := arg("--ids", "")
	var wanted := selected.split(",") if selected != "" else PackedStringArray()
	var subjects: Array[Dictionary] = []
	var expected: Array[String] = []
	for data in Roster.MONSTERS:
		expected.append(String(data["id"]))
		if wanted.is_empty() or String(data["id"]) in wanted: subjects.append(data)
	check(expected.size() == 25 and not subjects.is_empty(), "validation uses the canonical monster roster")
	var manifest: Dictionary = adapter.manifest()
	if wanted.is_empty():
		var ready: Array = manifest.get("ready_ids", [])
		check(ready.size() == expected.size(), "all monsters passed visual review")
		check(manifest.get("monsters", {}).size() == expected.size(), "exact native monster coverage")
		for id in expected: check(id in ready, "native monster reviewed: " + id)
	for data in subjects: await _model_contract(data)
	if failures == 0 and not subjects.is_empty(): await _world_contract(subjects[0])
	finish("Native 몬스터·이동 시계·데이터 보존" + (" (지정 샘플)" if selected != "" else " (전체)"))

func _model_contract(data: Dictionary) -> void:
	var id := String(data["id"])
	check(adapter.has_model(id), id + ": reviewed native model is available")
	if not adapter.has_model(id): return
	var original := data.duplicate(true)
	var row: Dictionary = adapter.manifest()["monsters"][id]
	check(bool(row.get("ready", false)), id + ": review state agrees with published roster")
	check(FileAccess.get_sha256(row["path"]) == String(row.get("glb_sha256", "")), id + ": actual source matches reviewed fingerprint")
	var first := StellarModels.monster(data)
	var second := StellarModels.monster(data)
	check(first.get_script() == adapter and second.get_script() == adapter, id + ": factory uses actual native adapter")
	check(bool(first.get_meta("_stellar_native_monster", false)), id + ": world receives native motion dispatch metadata")
	check(first.get_meta("identity", "") == id and first.get_meta("model_source", "") == row["path"], id + ": identity and actual GLB path are preserved")
	check(_textured_skin(first), id + ": native mesh has texture, UVs and skin weights")
	var skeleton := _skeleton(first)
	var player := _player(first)
	check(skeleton != null and skeleton.get_bone_count() > 0 and skeleton.get_bone_count() == int(row.get("rig", 0)), id + ": imported body-specific skeleton matches declared rig")
	var move := _clip(player, "MoveLoop")
	var idle := _clip(player, "IdleLoop")
	check(move != null and idle != null, id + ": actual move and idle clips import")
	for animation in [move, idle]:
		if animation != null:
			check(animation.length > 0 and animation.loop_mode != Animation.LOOP_NONE, id + ": authored motion has a positive loop duration")
	for name in ["StellarBurn", "StellarFrost", "StellarStun"]:
		var status := first.get_node_or_null(name) as Node3D
		check(status != null and not status.visible, id + ": independent status group " + name)
	if first.get_script() != adapter or second.get_script() != adapter or skeleton == null or move == null or idle == null:
		first.free()
		second.free()
		return
	add_child(first)
	add_child(second)
	await frames(1)
	first.call("animate_visual", 0.0)
	second.call("animate_visual", 0.0)
	var start := _poses(skeleton)
	var second_start := _poses(_skeleton(second))
	var resources := _resources(first)
	first.call("animate_visual", move.length*0.23)
	check(not _poses_close(start, _poses(skeleton)), id + ": move clip articulates the actual skin")
	check(_poses_close(second_start, _poses(_skeleton(second))), id + ": instances keep independent joints")
	var stopped := _poses(skeleton)
	first.call("animate_visual", move.length*0.23)
	check(_poses_close(stopped, _poses(skeleton)), id + ": repeated simulation clock freezes native locomotion")
	first.call("animate_visual", move.length)
	check(_poses_close(start, _poses(skeleton)), id + ": move cycle closes without pose jump")
	first.call("animate_visual", 0.0, false)
	var idle_start := _poses(skeleton)
	first.call("animate_visual", idle.length, false)
	check(_poses_close(idle_start, _poses(skeleton)), id + ": idle cycle closes")
	check(_resources(first) == resources, id + ": sampling reuses nodes, meshes and materials")
	check(data == original, id + ": creation and motion preserve original roster values")
	first.free()
	second.free()

func _world_contract(data: Dictionary) -> void:
	Fixture.fresh(9102575)
	var sim := BattleSim.new()
	sim.setup(Run, 1, 9102575)
	sim._spawn(data)
	sim._spawn(data)
	sim.monsters[0]["motion_t"] = 1.125
	sim.monsters[0]["stun_t"] = 0.4
	sim.monsters[0]["slow_t"] = 0.6
	sim.monsters[0]["burn_t"] = 0.8
	sim.monsters[1]["motion_t"] = 2.5
	var saved := Run.snapshot().duplicate(true)
	var state := [sim.heroes.duplicate(true), sim.monsters.duplicate(true), sim.bullets.duplicate(true),
		sim._pending.duplicate(true), sim.events.duplicate(true), sim._rng.state, Run.rng.state]
	var world := StellarWorld.new()
	add_child(world)
	await frames(1)
	world.sync_battle(sim, 80.0, Run.lives)
	check(world.monster_nodes.size() == 2, "repeated native monsters have distinct battle instances")
	var nodes: Array = world.monster_nodes.values()
	if nodes.size() == 2:
		var first: Node3D = nodes[0]
		var second: Node3D = nodes[1]
		check(first.get_script() == adapter and second.get_script() == adapter, "battle dispatches actual native monster models")
		check(first.get_node("StellarBurn").visible and first.get_node("StellarFrost").visible and first.get_node("StellarStun").visible, "battle retains burn, slow and stun visibility")
		check(not second.get_node("StellarBurn").visible and not second.get_node("StellarFrost").visible and not second.get_node("StellarStun").visible, "status effects do not leak to another instance")
		var at := BattleSim.mpos(sim.monsters[0])
		check(first.position.is_equal_approx(world.world(at, 0.14)) and is_zero_approx(first.rotation.z), "native body uses actual path position and stable authored ground")
		var pose := _poses(_skeleton(first))
		var second_pose := _poses(_skeleton(second))
		var reference := StellarModels.monster(data)
		add_child(reference)
		await frames(1)
		reference.call("animate_visual", float(sim.monsters[0]["motion_t"])+float(sim.monsters[0]["motion_phase"]))
		check(_poses_close(pose, _poses(_skeleton(reference))), "world samples the simulator's clock without applying slow or stun twice")
		world.sync_battle(sim, 90.0, Run.lives, 0.0)
		check(_poses_close(pose, _poses(_skeleton(first))) and _poses_close(second_pose, _poses(_skeleton(second))), "paused simulator clocks hold both native models despite changed UI time")
		reference.free()
	check(Run.snapshot() == saved, "native monster visuals preserve saves")
	check([sim.heroes, sim.monsters, sim.bullets, sim._pending, sim.events, sim._rng.state, Run.rng.state] == state, "native visuals preserve positions, timers, events, damage and both RNGs")
	sim.monsters.clear()
	world.sync_battle(sim, 91.0, Run.lives)
	check(world.monster_nodes.is_empty(), "removed monsters release their world instances")
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

func _clip(player: AnimationPlayer, suffix: String) -> Animation:
	if player != null:
		for name in player.get_animation_list():
			if String(name).ends_with(suffix): return player.get_animation(name)
	return null

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
