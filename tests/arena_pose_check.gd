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
		var early_drift := 0.0
		var late_drift := 0.0
		for frame in range(1, 1801):
			data["pos"] = Balance.ARENA_CENTER + Vector2(sin(frame * 0.01), cos(frame * 0.01)) * 100
			world.sync_heroes([data], frame / 60.0, true)
			for bone in rests:
				var drift := skeleton.get_bone_pose_position(bone).distance_to(rests[bone].origin)
				maximum_drift = maxf(maximum_drift, drift)
				if frame <= 600: early_drift = maxf(early_drift, drift)
				elif frame > 1200: late_drift = maxf(late_drift, drift)
		# The planted gait (2026-10-12) carries the leg pivots on the solved hip height and
		# the swing lift (0.11~0.13 across the roster), so "grounded" is no longer "within
		# 0.10 of rest". What this regression guards is accumulation: a pose that adds to
		# itself every frame grows without bound, so the last ten seconds may not exceed
		# the first ten, and the whole walk stays inside a fixed envelope.
		check(maximum_drift < 0.20, String(unit["id"]) + " leg pivot stays inside the gait envelope for 30 seconds: " + str(maximum_drift))
		check(late_drift <= early_drift + 0.005, String(unit["id"]) + " leg pivot does not accumulate (first 10 s %.4f, last 10 s %.4f)" % [early_drift, late_drift])
		var paused: Dictionary = {}
		for bone in rests: paused[bone] = skeleton.get_bone_pose(bone)
		for frame in range(120): world.sync_heroes([data], 30.0, true)
		for bone in rests:
			check(skeleton.get_bone_pose(bone).is_equal_approx(paused[bone]), String(unit["id"]) + " paused redraw cannot accumulate gait")
		for frame in range(1, 31): world.sync_heroes([data], 30.0 + frame / 60.0, true)
		for bone in rests:
			check(skeleton.get_bone_pose_position(bone).distance_to(rests[bone].origin) < 0.025,
				String(unit["id"]) + " stopping restores authored leg position within half a second")
		world.sync_heroes([], 30.1, true)
	world.queue_free()
	await frames(2)
	finish("Native hero persistent walking and paused pose regression")
