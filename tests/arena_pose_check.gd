extends Harness

## Constant animation channels must not accumulate the arena's additive gait.
func _ready() -> void:
	if not require_no_save(): return
	var world := ArenaWorld.new()
	add_child(world)
	for unit in Roster.UNITS:
		var hero := {"unit": unit, "tier": 5}
		var data := {"h": hero, "pos": Balance.ARENA_CENTER, "fx_t": 9.0, "fx_w": 0.3}
		world.sync_heroes([data], 0, true)
		var node: Node3D = world.hero_nodes.values()[0]
		var skeleton: Skeleton3D = world._find_skeleton(node)
		var rests: Dictionary = {}
		for side in ["L", "R"]:
			var bone := skeleton.find_bone("SkinLeg" + side)
			if bone >= 0: rests[bone] = skeleton.get_bone_pose(bone)
		check(rests.size() == 2, String(unit["id"]) + " has native leg controls")
		var maximum_drift := 0.0
		for frame in range(1, 1801):
			data["pos"] = Balance.ARENA_CENTER + Vector2(sin(frame * 0.01), cos(frame * 0.01)) * 100
			world.sync_heroes([data], frame / 60.0, true)
			for bone in rests:
				maximum_drift = maxf(maximum_drift, skeleton.get_bone_pose_position(bone).distance_to(rests[bone].origin))
		check(maximum_drift < 0.10, String(unit["id"]) + " leg position stays grounded after 30 seconds: " + str(maximum_drift))
		var paused: Dictionary = {}
		for bone in rests: paused[bone] = skeleton.get_bone_pose(bone)
		for frame in range(120): world.sync_heroes([data], 30.0, true)
		for bone in rests:
			check(skeleton.get_bone_pose(bone).is_equal_approx(paused[bone]), String(unit["id"]) + " paused redraw cannot accumulate gait")
		world.sync_heroes([data], 30.1, true)
		for bone in rests:
			check(skeleton.get_bone_pose_position(bone).distance_to(rests[bone].origin) < 0.025,
				String(unit["id"]) + " stopping restores authored leg position")
		world.sync_heroes([], 30.1, true)
	world.queue_free()
	await frames(2)
	finish("Native hero persistent walking and paused pose regression")
