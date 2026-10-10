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
	for data in subjects:
		await _model_contract(data)
		await _reaction_contract(data)
	if failures == 0 and not subjects.is_empty(): await _world_contract(subjects[0])
	if has_arg("--bench"): await _bench()
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

## Reaction layer contract: turning, hit squash, spawn, siege strike, death and
## pause stability on top of the simulator clock. Every state is driven only by
## the dt the world hands to face_toward/advance_death or by motion_time steps.
func _reaction_contract(data: Dictionary) -> void:
	var id := String(data["id"])
	if not adapter.has_model(id): return
	var original := data.duplicate(true)
	var row: Dictionary = adapter.manifest()["monsters"][id]
	check("Attack" in row.get("clips", []) and "Die" in row.get("clips", []), id + ": manifest lists the strike and death clips")
	var motion: Dictionary = row.get("motion", {})
	check(motion.has("death") and motion.has("spawn") and motion.has("turn_rate") and float(motion.get("cycle", 0.0)) > 0.0, id + ": manifest carries runtime motion parameters")
	var first := StellarModels.monster(data)
	var second := StellarModels.monster(data)
	add_child(first)
	add_child(second)
	await frames(1)
	var skeleton := _skeleton(first)
	var player := _player(first)
	var attack := _clip(player, "Attack")
	var die := _clip(player, "Die")
	check(attack != null and attack.length > 0.0 and die != null and die.length > 0.0, id + ": strike and death clips import")
	var resources := _resources(first)
	# Turning: the first heading snaps, dt 0 holds, positive dt converges smoothly.
	first.face_toward(Vector2(0, 1), 0.0)
	check(absf(angle_difference(first.rotation.y, atan2(0.0, -1.0))) < 0.0001, id + ": first heading snaps the body")
	first.face_toward(Vector2(1, 0), 0.0)
	check(absf(angle_difference(first.rotation.y, atan2(0.0, -1.0))) < 0.0001, id + ": paused frames never turn the body")
	var previous := absf(angle_difference(first.rotation.y, atan2(-1.0, 0.0)))
	var monotonic := true
	var turned_in_one_step := false
	for n in range(90):
		first.face_toward(Vector2(1, 0), 1.0 / 30.0)
		var remaining := absf(angle_difference(first.rotation.y, atan2(-1.0, 0.0)))
		if remaining > previous + 0.0001: monotonic = false
		if n == 0 and remaining < 0.0001: turned_in_one_step = true
		previous = remaining
	check(monotonic and not turned_in_one_step and previous < 0.02, id + ": heading converges smoothly instead of snapping (remaining %.3f)" % previous)
	# Same clock, same pose: the walk sample does not depend on how the body turned.
	first.animate_visual(0.41)
	second.face_toward(Vector2(1, 0), 0.0)
	second.animate_visual(0.41)
	check(_poses_near(_poses(skeleton), _poses(_skeleton(second)), 0.0001), id + ": turning history does not change the authored walk pose")
	var pivot_rest: Transform3D = first.motion_state()["pivot"]
	# Hit: squash while the flash lasts, exact recovery when it is gone.
	var before_hit := _poses(skeleton)
	first.visual_event("hit", {"p": StellarWorld.logical(first.global_position) + Vector2(-40, 0), "c": Color.WHITE, "n": 1.0})
	first.set_hit_flash(1.0)
	first.animate_visual(0.41)
	var squashed: Transform3D = first.motion_state()["pivot"]
	check(squashed.basis.get_scale().y < pivot_rest.basis.get_scale().y - 0.02, id + ": a hit squashes the body")
	check(not _poses_near(before_hit, _poses(skeleton), 0.0001), id + ": a hit flinches the joints")
	first.set_hit_flash(0.0)
	first.animate_visual(0.41)
	check(_poses_near(before_hit, _poses(skeleton), 0.0001) and first.motion_state()["pivot"].is_equal_approx(pivot_rest), id + ": the body recovers exactly once the flash decays")
	# Pause stability includes the reaction layers.
	first.animate_visual(0.41)
	check(_poses_near(before_hit, _poses(skeleton), 0.0001) and first.motion_state()["pivot"].is_equal_approx(pivot_rest), id + ": repeated identical calls hold the whole presentation")
	# Spawn: an entrance offset on the pivot that leaves the authored joints alone.
	var spawned := StellarModels.monster(data)
	add_child(spawned)
	await frames(1)
	spawned.visual_event("spawn", {"p": Vector2.ZERO})
	spawned.face_toward(Vector2(1, 0), 1.0 / 30.0)
	spawned.animate_visual(0.41)
	var entrance: Transform3D = spawned.motion_state()["pivot"]
	check(not entrance.is_equal_approx(pivot_rest), id + ": spawning plays an entrance")
	check(_poses_near(before_hit, _poses(_skeleton(spawned)), 0.0001), id + ": the entrance never alters the simulator-driven pose")
	for n in range(24):
		spawned.face_toward(Vector2(1, 0), 1.0 / 30.0)
		spawned.animate_visual(0.41)
	check(_transform_near(spawned.motion_state()["pivot"], pivot_rest, 0.002), id + ": the entrance settles within 0.8 s")
	spawned.free()
	# Siege: standing bodies strike exactly when the phase wraps, then recover.
	first.set_siege(0.5)
	first.animate_visual(0.41, false)
	for n in range(10):
		first.face_toward(Vector2(1, 0), 1.0 / 30.0)
		first.animate_visual(0.41, false)
	var hold := _poses(skeleton)
	first.set_siege(0.95)
	first.animate_visual(0.41, false)
	var windup := _poses(skeleton)
	check(not _poses_near(hold, windup, 0.001), id + ": the siege wind-up changes the pose before the damage tick")
	first.set_siege(0.9999)
	first.animate_visual(0.41, false)
	var strike := _poses(skeleton)
	first.set_siege(0.0)
	first.animate_visual(0.41, false)
	check(_poses_near(strike, _poses(skeleton), 0.01), id + ": the strike pose is continuous across the phase wrap")
	check(not _poses_near(strike, hold, 0.001), id + ": the strike differs from the hold")
	first.set_siege(-1.0)
	first.animate_visual(0.41, false)
	for n in range(12):
		first.face_toward(Vector2(1, 0), 1.0 / 30.0)
		first.animate_visual(0.41, false)
	check(first.motion_state()["attack"] <= 0.0001 and first.motion_state()["idle"] >= 0.9999, id + ": leaving the altar fades back to standing")
	check(_resources(first) == resources, id + ": reactions never create nodes, meshes or materials")
	# Death: the world keeps the node, dt 0 freezes it, the body finishes inside 1.6 s.
	first.get_node("StellarStun").visible = true
	first.visual_event("die", {"c": Color.WHITE, "h": 1.0})
	check(not first.get_node("StellarStun").visible, id + ": status rings leave with the dying body")
	var at_death := _poses(skeleton)
	check(not first.advance_death(0.0) and _poses_near(at_death, _poses(skeleton), 0.0001), id + ": a paused frame does not advance the death")
	var steps := 0
	var finished := false
	while steps < 60 and not finished:
		finished = first.advance_death(1.0 / 30.0)
		steps += 1
	check(finished and steps <= 48, id + ": death presentation completes within 1.6 s (%d frames)" % steps)
	check(is_equal_approx(float(first.get_meta("dissolve", 0.0)), 1.0), id + ": the body hands a full dissolve to the material layer")
	check(not _poses_near(at_death, _poses(skeleton), 0.001) or not first.motion_state()["pivot"].is_equal_approx(pivot_rest), id + ": the death moves the body")
	var frozen := _poses(skeleton)
	first.animate_visual(2.0)
	check(_poses_near(frozen, _poses(skeleton), 0.0001), id + ": a dead body ignores the walking clock")
	second.visual_event("leak", {"i": 0, "n": 1})
	var leak_steps := 0
	while leak_steps < 30 and not second.advance_death(1.0 / 30.0): leak_steps += 1
	check(leak_steps <= 15, id + ": a leaking body vanishes quickly")
	check(data == original, id + ": reactions preserve original roster values")
	first.free()
	second.free()

## Optional (--bench): adapter cost at the maximum density, one world-style frame
## per body (face_toward, set_hit_flash, set_siege, animate_visual). Headless, so
## this is GDScript/skeleton cost only, not rendering.
func _bench() -> void:
	var bodies: Array = []
	var holder := Node3D.new()
	add_child(holder)
	for n in range(41):
		var model := StellarModels.monster(Roster.MONSTERS[n % Roster.MONSTERS.size()])
		holder.add_child(model)
		bodies.append(model)
	await frames(1)
	var clock := 0.0
	var start := Time.get_ticks_usec()
	for frame in range(300):
		clock += 1.0 / 30.0
		for i in bodies.size():
			var body: Node3D = bodies[i]
			body.face_toward(Vector2(sin(clock + i), cos(clock * 0.7 + i)), 1.0 / 30.0)
			body.set_hit_flash(0.0)
			body.set_siege(-1.0 if i % 3 else fposmod(clock, 1.0))
			body.animate_visual(clock * 1.3 + i * 0.1, i % 3 != 0)
	var total := (Time.get_ticks_usec() - start) / 1000.0
	print("BENCH 41 native monsters x 300 frames: %.1f ms total, %.3f ms per frame, %.1f us per body" % [total, total / 300.0, total / 300.0 / 41.0 * 1000.0])
	check(total / 300.0 < 8.0, "41 native monster adapters cost under 8 ms per frame on this host (%.3f ms)" % (total / 300.0))
	holder.free()

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
		# A stunned body stands (idle clip) at the same simulator clock; the world
		# never advances or re-scales that clock itself.
		var standing := float(sim.monsters[0].get("stun_t", 0.0)) > 0.0
		reference.call("animate_visual", float(sim.monsters[0]["motion_t"])+float(sim.monsters[0]["motion_phase"]), not standing)
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

func _transform_near(a: Transform3D, b: Transform3D, tolerance: float) -> bool:
	if (a.origin - b.origin).length() > tolerance: return false
	for axis in range(3):
		if (a.basis[axis] - b.basis[axis]).length() > tolerance: return false
	return true

func _poses_near(a: Array[Transform3D], b: Array[Transform3D], tolerance: float) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if (a[i].origin - b[i].origin).length() > tolerance: return false
		for axis in range(3):
			if (a[i].basis[axis] - b[i].basis[axis]).length() > tolerance: return false
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
