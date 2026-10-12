extends Harness

## Grounding probe: how far the feet are from the ground and how much they slide
## while a hero (or monster) travels, measured on the real skinned mesh (the lowest
## skin vertices of each leg), with side and game-angle captures over a ruled ground.
##
##   godot --path . --resolution 1280x800 res://tests/3d/grounding_probe.tscn -- \
##       --id echo --speed 3.4 --root-y 0.07 --out build/walk-grounding/before/echo_3.4
##   --monster blaze_fox [--speed 1.64]   creature on the arena path clock (1 clip s = 1.64 u)
##   --root-y Y     world root height to simulate (default: StellarWorld.HERO_GROUND /
##                  MONSTER_GROUND when present, else 0.07 / 0.14)
##   --frames N     rendered samples at 30 fps after a 12-sample warm-up (default 48)
##   --no-capture   numbers only (headless)
##
## The model really travels along +X at the given speed and both cameras follow it, so a
## foot that moves on screen against the ground stripes is sliding on the ground.
## Numbers go to <out>/grounding.json; nothing here is a game path.

const STEP := 1.0 / 30.0
const GROUND_TOP := 0.015          # ArenaWorld soil disc top (y)
const CONTACT := 0.02              # foot bottom within this of the model's y=0 counts as planted
const GAME_SCALE := 26.0 * 640.0 / 1280.0   # arena camera.size 26 over 1280 px → 49.2 px/u at 640 px

var out_dir := ""
var capture := true
var viewport: SubViewport
var stage: Node3D
var cam_side: Camera3D
var cam_game: Camera3D
var model: Node3D
var skeleton: Skeleton3D
var monster := false
var speed := 3.4
var root_y := 0.07
var height := 1.65
var soles: Array = []       # per vertex: {"v": Vector3 (skeleton space rest), "bones": [int], "binds": [Transform3D], "w": [float], "group": String}
var groups: Array = []
var body_bone := -1
var body_rest_y := 0.0
var records: Array = []
var motion_t := 0.0

func _ready() -> void:
	if not require_no_save(): return
	if has_arg("--measure-all"):
		_measure_all()
		return
	print("probe: start")
	out_dir = arg("--out", "build/walk-grounding/probe")
	capture = not has_arg("--no-capture")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var frames_n := int(arg("--frames", "48"))
	var mid := arg("--monster", "")
	monster = mid != ""
	var hid := arg("--id", "echo")
	var default_speed := 1.64 if monster else 3.4
	speed = float(arg("--speed", str(default_speed)))
	var world_default := _world_ground(monster)
	root_y = float(arg("--root-y", str(world_default)))
	_setup_stage()
	print("probe: stage ready")
	if monster:
		var row: Dictionary = {}
		for m in Roster.MONSTERS:
			if String(m["id"]) == mid: row = m
		check(not row.is_empty(), "monster id exists: " + mid)
		if row.is_empty(): get_tree().quit(1); return
		if not NativeMonsterModel.has_model(mid): NativeMonsterModel.manifest()["ready_ids"].append(mid)
		model = StellarModels.monster(row)
		height = float(NativeMonsterModel.manifest()["monsters"][mid].get("height", 1.0))
	else:
		var unit: Dictionary = Roster.unit_by_id(hid)
		check(not unit.is_empty(), "hero id exists: " + hid)
		if unit.is_empty(): get_tree().quit(1); return
		model = StellarModels.hero(unit, 4)
		# The world adds the same contact shadow and team ring under every hero.
		StellarModels.contact(model, Vector3(0, 0.008, 0), Vector2(0.96, 0.68), 0.40)
		var ring := StellarModels.part(model, "ring", Vector3(0, 0.019, 0), Vector3(0.79, 0.021, 0.79), Color("#879e91"), 0.1, 0.04)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if hid == "limne": height = 1.63
		else: height = float(NativeCharacterModel.manifest()["heroes"].get(hid, {}).get("height", 1.65))
	model.position = Vector3(0, root_y, 0)
	print("probe: model created ", model.name)
	stage.add_child(model)
	await frames(2)
	print("probe: in tree")
	skeleton = _find_type(model, "Skeleton3D") as Skeleton3D
	check(skeleton != null, "model has a skeleton")
	if skeleton == null: get_tree().quit(1); return
	body_bone = skeleton.find_bone("SkinBody")
	if body_bone < 0: body_bone = skeleton.find_bone("Body")
	if body_bone >= 0: body_rest_y = skeleton.get_bone_rest(body_bone).origin.y
	_collect_soles()
	check(soles.size() > 0, "sole vertices found (%d)" % soles.size())
	if not monster and model is NativeCharacterModel and model.has_method("_measure_sole"):
		var native: NativeCharacterModel = model
		var started := Time.get_ticks_usec()
		native._sole_cache.erase(String(native.get_meta("native_id", "")))
		var measured: Dictionary = native._measure_sole(height)
		print("runtime sole measure: %s in %.1f ms (toe %.3f h, heel %.3f h) | loco leg %.3f toe %.3f heel %.3f swing %.3f" % [str(measured), (Time.get_ticks_usec() - started) / 1000.0, float(measured["toe"]) / height, float(measured["heel"]) / height, native._loco.leg, native._loco.toe, native._loco.heel, native._loco.swing])
	var dir := Vector2(1, 0)
	var t := 20.0
	if monster and has_arg("--death"):
		await _death_sequence(dir)
		finish("Death probe " + mid)
		return
	# Warm-up: the smoothed speed reaches the target and the first facing snaps.
	_drive(dir, t, 0.0)
	for n in range(12):
		t += STEP
		_drive(dir, t, STEP)
	for n in range(frames_n):
		t += STEP
		_drive(dir, t, STEP)
		_record(n, t)
		if capture:
			await _shoot("side_%02d" % n, cam_side)
			await _shoot("game_%02d" % n, cam_game)
	_summarise()
	finish("Grounding probe " + (mid if monster else hid) + " %.2f u/s" % speed)

## Sole reach (toe ahead / heel behind the hip pivot, in heights) of every ready hero.
func _measure_all() -> void:
	for id in NativeCharacterModel.manifest().get("ready_ids", []):
		var m: NativeCharacterModel = NativeCharacterModel.create(String(id))
		if m == null: continue
		add_child(m)
		var h := float(NativeCharacterModel.manifest()["heroes"][id].get("height", 1.65))
		var sole: Dictionary = m._measure_sole(h)
		print("SOLE %s toe %.3f heel %.3f (h) swing %.2f stride %.2f" % [id, float(sole["toe"]) / h, float(sole["heel"]) / h, m._loco.swing, m._loco.cycle_stride()])
		m.free()
	finish("sole survey")

## A creature walks, dies (visual_event "die") and plays its death through
## advance_death exactly as the world drives it; every frame is captured from both
## cameras so a stray flat/black body between the collapse and the release shows up.
func _death_sequence(dir: Vector2) -> void:
	var t := 20.0
	_drive(dir, t, 0.0)
	for n in range(10):
		t += STEP
		_drive(dir, t, STEP)
	for n in range(3):
		await _shoot("death_side_%02d" % n, cam_side)
		await _shoot("death_game_%02d" % n, cam_game)
		t += STEP
		_drive(dir, t, STEP)
	model.visual_event("die", {"p": StellarWorld.logical(model.global_position)})
	var frame := 3
	var done := false
	while frame < 60 and not done:
		done = model.advance_death(STEP)
		var pivot: Node3D = model._pivot
		var dissolve: float = StellarShading.dissolve(model)
		print("death %02d t %.2f dissolve %.2f pivot y %+.3f scale %.2f" % [frame, model._death_t, dissolve, pivot.position.y, pivot.scale.y])
		await _shoot("death_side_%02d" % frame, cam_side)
		await _shoot("death_game_%02d" % frame, cam_game)
		frame += 1
	print("death done after %d frames (total %.2f s)" % [frame, model._death_t])

func _world_ground(for_monster: bool) -> float:
	var script := load("res://game/3d/stellar_world.gd")
	var constants: Dictionary = script.get_script_constant_map()
	var key := "MONSTER_GROUND" if for_monster else "HERO_GROUND"
	if constants.has(key): return float(constants[key])
	return 0.14 if for_monster else 0.07

func _drive(dir: Vector2, t: float, dt: float) -> void:
	var v := Vector3(dir.x, 0, dir.y) * speed
	if dt > 0.0: model.position += v * dt
	if monster:
		model.face_toward(dir, dt)
		motion_t += dt * speed / (Balance.PATH_SPEED / StellarWorld.UNIT)
		model.animate_visual(motion_t, true)
	else:
		model.set_locomotion(v, dt)
		model.face_toward(dir, dt)
		model.animate_visual(t, 9, 0, true)
	var follow := Vector3(model.position.x, 0, 0)
	cam_side.position = follow + Vector3(0.0, 0.42, 4.0)
	cam_side.look_at(follow + Vector3(0, 0.42, 0), Vector3.UP)
	cam_game.position = follow + Vector3(-3.0, 19.0, 23.0)
	cam_game.look_at(follow + Vector3(0, 0.4, 0), Vector3.UP)

## Lowest skin vertices per leg (dominant bone), in skeleton space, with their skin binds.
func _collect_soles() -> void:
	var lowest := 1e9
	var all: Array = []
	for mi: MeshInstance3D in _meshes(model):
		var skin: Skin = mi.skin
		if skin == null: skin = skeleton.create_skin_from_rest_transforms()
		var bind_bones: Array[int] = []
		var bind_poses: Array[Transform3D] = []
		for i in skin.get_bind_count():
			var b := skin.get_bind_bone(i)
			if b < 0: b = skeleton.find_bone(skin.get_bind_name(i))
			bind_bones.append(b)
			bind_poses.append(skin.get_bind_pose(i))
		var mesh: Mesh = mi.mesh
		var to_skeleton: Transform3D = skeleton.global_transform.affine_inverse() * mi.global_transform
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null: continue
			var per := 8 if (mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
			for k in verts.size():
				var entry := {"bones": [], "binds": [], "w": []}
				var best_w := 0.0
				var best_b := -1
				for j in per:
					var w := float(weights[k * per + j])
					if w <= 0.0: continue
					var bi := int(bones[k * per + j])
					if bi < 0 or bi >= bind_bones.size(): continue
					entry["bones"].append(bind_bones[bi])
					entry["binds"].append(bind_poses[bi])
					entry["w"].append(w)
					if w > best_w:
						best_w = w
						best_b = bind_bones[bi]
				if entry["bones"].is_empty(): continue
				var v: Vector3 = to_skeleton * verts[k]
				entry["v"] = v
				entry["group"] = skeleton.get_bone_name(best_b) if best_b >= 0 else "?"
				# Rest-pose skinned height decides which vertices form the soles.
				var rest := _skinned(entry, true)
				entry["rest_y"] = rest.y
				lowest = minf(lowest, rest.y)
				all.append(entry)
	var band := lowest + maxf(0.012, 0.012 * height)
	# Feet only: leg bones when the rig names them, else every bone that reaches the band
	# (quadrupeds, blobs). Weapon tips and robes near the floor are not feet.
	var legs: Array = []
	for entry in all:
		if float(entry["rest_y"]) <= band and String(entry["group"]).contains("Leg") and not legs.has(entry["group"]): legs.append(entry["group"])
	for entry in all:
		if float(entry["rest_y"]) > band: continue
		if not legs.is_empty() and not legs.has(entry["group"]): continue
		soles.append(entry)
		if not groups.has(entry["group"]): groups.append(entry["group"])
	print("soles: %d vertices in %s (rest lowest y %.4f)" % [soles.size(), str(groups), lowest])
	# Sole extents relative to each leg bone's pivot (skeleton space): toe reach (-z) and heel (+z).
	for g in groups:
		var bone := skeleton.find_bone(g)
		if bone < 0: continue
		var pivot := skeleton.get_bone_global_rest(bone).origin
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for entry in soles:
			if entry["group"] != g: continue
			var d: Vector3 = entry["v"] - pivot
			lo = Vector3(minf(lo.x, d.x), minf(lo.y, d.y), minf(lo.z, d.z))
			hi = Vector3(maxf(hi.x, d.x), maxf(hi.y, d.y), maxf(hi.z, d.z))
		print("sole %s: pivot y %.3f (%.3f h) | z %.3f..%.3f (toe %.3f h, heel %.3f h) | x %.3f..%.3f" % [g, pivot.y, pivot.y / height, lo.z, hi.z, -lo.z / height, hi.z / height, lo.x, hi.x])
	if not monster and model is NativeCharacterModel: _clip_amplitudes()

## Authored WalkLoop amplitudes straight from the clip (no runtime shaping).
func _clip_amplitudes() -> void:
	var native: NativeCharacterModel = model
	if native._clips.size() < 2 or native._clips[1] == null: return
	var length: float = native._clips[1].length
	var max_angle := {"SkinLegL": 0.0, "SkinLegR": 0.0}
	var min_angle := {"SkinLegL": 0.0, "SkinLegR": 0.0}
	var max_lift := 0.0
	var vault_min := 0.0
	var vault_max := 0.0
	var axis_note := ""
	for n in range(64):
		var pose: Array = native._sample(1, length * float(n) / 64.0)
		for g in max_angle:
			var bone := skeleton.find_bone(g)
			if bone < 0: continue
			var q: Quaternion = (pose[bone].basis * native._rest[bone].basis.inverse()).get_rotation_quaternion()
			if q.w < 0.0: q = -q
			var axis := q.get_axis()
			var signed := q.get_angle() * (1.0 if axis.x >= 0.0 else -1.0)
			max_angle[g] = maxf(max_angle[g], signed)
			min_angle[g] = minf(min_angle[g], signed)
			if n == 0 and g == "SkinLegL": axis_note = str(axis.snapped(Vector3.ONE * 0.01))
			max_lift = maxf(max_lift, pose[bone].origin.y - native._rest[bone].origin.y)
		if native._body_bone >= 0:
			var dy: float = pose[native._body_bone].origin.y - native._rest[native._body_bone].origin.y
			vault_min = minf(vault_min, dy)
			vault_max = maxf(vault_max, dy)
	print("clip WalkLoop %.3fs: legL %+.3f..%+.3f rad, legR %+.3f..%+.3f rad (axis at 0: %s) | lift max %.3f (%.3f h) | body y %+.3f..%+.3f | manifest stride %.3f | hip %.3f" % [
		length, min_angle["SkinLegL"], max_angle["SkinLegL"], min_angle["SkinLegR"], max_angle["SkinLegR"], axis_note, max_lift, max_lift / height, vault_min, vault_max, native._loco.stride, native._hip])

func _skinned(entry: Dictionary, rest: bool) -> Vector3:
	var p := Vector3.ZERO
	var total := 0.0
	var bones: Array = entry["bones"]
	var binds: Array = entry["binds"]
	var w: Array = entry["w"]
	for j in bones.size():
		var b: int = bones[j]
		var pose: Transform3D = skeleton.get_bone_global_rest(b) if rest else skeleton.get_bone_global_pose(b)
		p += (pose * binds[j]) * entry["v"] * float(w[j])
		total += float(w[j])
	return p / maxf(total, 0.0001)

func _record(n: int, t: float) -> void:
	var world_of_skeleton := skeleton.global_transform
	var per_group: Dictionary = {}
	for entry in soles:
		var p := world_of_skeleton * _skinned(entry, false)
		var g: String = entry["group"]
		if not per_group.has(g): per_group[g] = {"min_y": 1e9, "sum": Vector3.ZERO, "n": 0, "cx": 0.0, "cz": 0.0}
		if p.y < float(per_group[g]["min_y"]):
			per_group[g]["min_y"] = p.y
			per_group[g]["cx"] = p.x
			per_group[g]["cz"] = p.z
		per_group[g]["sum"] += p
		per_group[g]["n"] += 1
	var row := {"n": n, "t": t, "root_y": model.position.y, "feet": {}}
	var lowest := 1e9
	for g in per_group:
		var mean: Vector3 = per_group[g]["sum"] / float(per_group[g]["n"])
		# bottom: lowest sole vertex above the model's own floor; x/z: sole centre; cx/cz: that lowest vertex (contact point)
		row["feet"][g] = {"bottom": float(per_group[g]["min_y"]) - model.position.y, "x": mean.x, "z": mean.z,
			"cx": float(per_group[g]["cx"]), "cz": float(per_group[g]["cz"])}
		lowest = minf(lowest, float(per_group[g]["min_y"]) - model.position.y)
	row["lowest"] = lowest
	row["gap_to_ground"] = lowest + model.position.y - GROUND_TOP
	if body_bone >= 0: row["body_dy"] = skeleton.get_bone_pose(body_bone).origin.y - body_rest_y
	if not monster:
		var loco: HeroLocomotion = model._loco
		row["phase"] = loco.walk_phase
		row["speed"] = loco.speed
	records.append(row)

func _summarise() -> void:
	var summary := {"id": arg("--monster", arg("--id", "echo")), "speed": speed, "root_y": root_y,
		"ground_top": GROUND_TOP, "frames": records.size(), "groups": groups, "height": height}
	var lowest_sum := 0.0
	var sink_sum := 0.0
	var float_sum := 0.0
	var off := 0
	var body_min := 1e9
	var body_max := -1e9
	var slide_abs := 0.0
	var slide_along := 0.0
	var centre_slide := 0.0
	var contact_frames := 0
	var strike_gaps: Array = []
	var per_group_contact: Dictionary = {}
	for i in records.size():
		var row: Dictionary = records[i]
		lowest_sum += float(row["lowest"])
		sink_sum += minf(0.0, float(row["lowest"]))
		float_sum += maxf(0.0, float(row["lowest"]))
		if float(row["lowest"]) > CONTACT: off += 1
		if row.has("body_dy"):
			body_min = minf(body_min, float(row["body_dy"]))
			body_max = maxf(body_max, float(row["body_dy"]))
		if row.has("phase"):
			# The striking foot's sole height at the moment it should land (L near 0, R near 0.5).
			var ph := fposmod(float(row["phase"]), 1.0)
			var near_l := ph < 0.04 or ph > 0.96
			var near_r := absf(ph - 0.5) < 0.04
			if near_l and row["feet"].has("SkinLegL"): strike_gaps.append(float(row["feet"]["SkinLegL"]["bottom"]))
			elif near_r and row["feet"].has("SkinLegR"): strike_gaps.append(float(row["feet"]["SkinLegR"]["bottom"]))
		if i == 0: continue
		var prev: Dictionary = records[i - 1]
		for g in row["feet"]:
			var foot: Dictionary = row["feet"][g]
			if float(foot["bottom"]) > CONTACT or not prev["feet"].has(g): continue
			var pf: Dictionary = prev["feet"][g]
			if float(pf["bottom"]) > CONTACT: continue
			# Planted means down and not moving vertically: landing and lift-off frames are
			# rotations of the foot, not slides.
			if float(foot["bottom"]) > 0.012 or absf(float(foot["bottom"]) - float(pf["bottom"])) > 0.015: continue
			# Contact point = the lowest sole vertex; a heel -> toe hand-over moves it by the
			# foot length in one frame and is not a slide.
			var dx := float(foot["cx"]) - float(pf["cx"])
			var dz := float(foot["cz"]) - float(pf["cz"])
			# A planted sole cannot out-run the body; larger jumps are the contact vertex
			# changing identity (heel -> toe hand-over, lift-off), not slides.
			if sqrt(dx * dx + dz * dz) > speed * STEP + 0.01: continue
			var vx := dx / STEP
			var vz := dz / STEP
			slide_abs += sqrt(vx * vx + vz * vz)
			slide_along += vx   # travel is +X
			centre_slide += absf(float(foot["x"]) - float(pf["x"])) / STEP
			contact_frames += 1
			per_group_contact[g] = int(per_group_contact.get(g, 0)) + 1
	var n := maxi(records.size(), 1)
	summary["lowest_foot_mean"] = lowest_sum / n
	summary["sink_mean"] = sink_sum / n
	summary["float_mean"] = float_sum / n
	summary["both_off_ratio"] = float(off) / n
	summary["vertical_amplitude"] = (body_max - body_min) if body_max > body_min else 0.0
	summary["strike_gap_mean"] = _mean(strike_gaps)
	summary["contact_frames"] = contact_frames
	summary["contact_per_group"] = per_group_contact
	summary["slide_ratio"] = (slide_abs / contact_frames / speed) if contact_frames > 0 else -1.0
	summary["slide_along_ratio"] = (slide_along / contact_frames / speed) if contact_frames > 0 else -1.0
	summary["centre_slide_ratio"] = (centre_slide / contact_frames / speed) if contact_frames > 0 else -1.0
	summary["ground_gap_mean"] = summary["lowest_foot_mean"] + root_y - GROUND_TOP
	if records.size() > 1 and records[0].has("phase"):
		var cycles := float(records[-1]["phase"]) - float(records[0]["phase"])
		while cycles < 0.0: cycles += 1.0
		# Unwrap: count wraps by stepping.
		var total := 0.0
		for i in range(1, records.size()):
			var d := float(records[i]["phase"]) - float(records[i - 1]["phase"])
			if d < -0.5: d += 1.0
			total += d
		summary["cadence_cycles_per_s"] = total / (STEP * (records.size() - 1))
	summary["records"] = records
	var file := FileAccess.open(out_dir + "/grounding.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "  ") + "\n")
	file = null
	print("GROUNDING %s %.2f u/s root %.3f | lowest foot %.3f u (sink %.3f, float %.3f) | both off %.0f%% | strike gap %.3f | contact slide %.0f%% (along %+.0f%%; sole centre %.0f%%) over %d frames | body amp %.3f | cadence %.2f c/s | gap to soil %.3f" % [
		summary["id"], speed, root_y, summary["lowest_foot_mean"], summary["sink_mean"], summary["float_mean"], summary["both_off_ratio"] * 100.0,
		summary["strike_gap_mean"], summary["slide_ratio"] * 100.0, summary["slide_along_ratio"] * 100.0, summary["centre_slide_ratio"] * 100.0,
		contact_frames, summary["vertical_amplitude"], float(summary.get("cadence_cycles_per_s", 0.0)), summary["ground_gap_mean"]])

static func _mean(values: Array) -> float:
	if values.is_empty(): return -1.0
	var s := 0.0
	for v in values: s += float(v)
	return s / values.size()

func _setup_stage() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 400)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	StellarLighting.setup(stage)
	StellarLighting.apply_arena(stage)
	# Ruled ground: arena soil tone with its top at the arena's soil height, a dark
	# stripe every 0.5 u so foot slide shows against it.
	StellarModels.part(stage, "box", Vector3(0, GROUND_TOP - 0.075, 0), Vector3(60, 0.15, 12), Color("#223e40"))
	for n in range(-20, 61):
		StellarModels.part(stage, "box", Vector3(n * 0.5, GROUND_TOP + 0.0005, 0), Vector3(0.025, 0.001, 12), Color("#0d1c22"))
	for n in range(-6, 7):
		StellarModels.part(stage, "box", Vector3(10, GROUND_TOP + 0.0005, n * 0.5), Vector3(60, 0.001, 0.02), Color("#0d1c22"))
	cam_side = Camera3D.new()
	cam_side.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam_side.keep_aspect = Camera3D.KEEP_HEIGHT
	cam_side.size = 1.9
	stage.add_child(cam_side)
	cam_game = Camera3D.new()
	cam_game.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam_game.keep_aspect = Camera3D.KEEP_WIDTH
	cam_game.size = GAME_SCALE
	cam_game.near = 0.1
	cam_game.far = 80
	stage.add_child(cam_game)
	cam_side.current = true

func _shoot(label: String, cam: Camera3D) -> void:
	cam.current = true
	await frames(2)
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out_dir + "/" + label + ".png")

func _meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D and node.get_parent() is Skeleton3D: found.append(node)
	for child in node.get_children(): found += _meshes(child)
	return found

static func _find_type(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find_type(child, type)
		if found != null: return found
	return null
