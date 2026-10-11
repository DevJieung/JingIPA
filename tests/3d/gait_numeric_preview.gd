extends Harness
## Numeric gait review aid: phase, leg swing, lift, arm swing and body height per frame
## for one native hero at a ground speed (world units/s), e.g.
##   godot --headless --path . res://tests/3d/gait_numeric_preview.tscn -- --id pip --speed 5.1
func _ready() -> void:
	if not require_no_save(): return
	var cid := arg("--id", "pip")
	var speed := float(arg("--speed", "5.1"))
	var model: NativeCharacterModel = NativeCharacterModel.create(cid)
	add_child(model)
	await frames(1)
	var skeleton: Skeleton3D = model._skeleton
	var leg_l := skeleton.find_bone("SkinLegL")
	var arm_l := skeleton.find_bone("SkinArmL")
	var arm_r := skeleton.find_bone("SkinArmR")
	var body := skeleton.find_bone("SkinBody")
	var rest_l := skeleton.get_bone_rest(leg_l)
	var rest_al := skeleton.get_bone_rest(arm_l)
	var rest_ar := skeleton.get_bone_rest(arm_r)
	var rest_b := skeleton.get_bone_rest(body)
	var t := 20.0
	var step := 1.0 / 30.0
	var dir := Vector2(-0.45, -1).normalized()
	model.animate_visual(t, 9, 0, true)
	for n in range(30):
		t += step
		model.set_locomotion(Vector3(dir.x, 0, dir.y) * speed, step)
		model.face_toward(dir, step)
		model.animate_visual(t, 9, 0, true)
		var loco: HeroLocomotion = model._loco
		var pl := skeleton.get_bone_pose(leg_l)
		var ql := (pl.basis * rest_l.basis.inverse()).get_rotation_quaternion()
		if ql.w < 0: ql = -ql
		var pal := skeleton.get_bone_pose(arm_l)
		var qal := (pal.basis * rest_al.basis.inverse()).get_rotation_quaternion()
		if qal.w < 0: qal = -qal
		var par := skeleton.get_bone_pose(arm_r)
		var qar := (par.basis * rest_ar.basis.inverse()).get_rotation_quaternion()
		if qar.w < 0: qar = -qar
		var pb := skeleton.get_bone_pose(body)
		print("%02d phase %.3f speed %.2f run %.2f scale %.2f | legL %.1f deg axis %s lift %.3f | armL %.1f armR %.1f | body dy %.3f" % [n, loco.walk_phase, loco.speed, loco.run_factor(), loco.stride_scale(), rad_to_deg(ql.get_angle()) * signf(ql.get_axis().x if absf(ql.get_axis().x) > 0.01 else 1.0), str(ql.get_axis().snapped(Vector3.ONE * 0.01)), pl.origin.y - rest_l.origin.y, rad_to_deg(qal.get_angle()), rad_to_deg(qar.get_angle()), pb.origin.y - rest_b.origin.y])
	print("stride", model._loco.stride, " legs", model._legs, " chains", model._arm_chains, " pump", model._arm_pump, " lead", model._lead)
	finish("gait probe")
