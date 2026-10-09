extends Node3D
class_name LimneModel

## Continuous Blender GLB skin driven by the existing five visual pivots.
## No attack clock, damage, RNG, or roster values are owned by this adapter.
const SOURCE := "res://art/models/limne/limne.glb"
const HOSE_SHADER := preload("res://art/models/limne/hose.gdshader")
const WATER_SHADER := preload("res://art/models/limne/water_spray.gdshader")
static var _tube: ArrayMesh
static var _spray_mesh: ArrayMesh
static var _drop_mesh: SphereMesh
static var _drop_material: StandardMaterial3D
var _hoses: Array[ShaderMaterial] = []
var _skeleton: Skeleton3D
var _bone_bindings: Array[Dictionary] = []
var _joint_bindings: Array[Dictionary] = []
var _hand_deltas: Array[Transform3D] = [Transform3D.IDENTITY,Transform3D.IDENTITY]
var _streams: Array[Node3D] = []
var _drops: Array[MeshInstance3D] = []
var _spray_material: ShaderMaterial
var _elbow_angle := 0.0
var _spray_strength := 0.0
var _motion_time := 0.0
var _aim_amount := 0.0

static func create() -> Node3D:
	var scene: PackedScene = load(SOURCE)
	var root: Node3D = scene.instantiate()
	# Keep the raw GLB complete for external editors; use deforming hoses in play.
	var rest := root.get_node_or_null("RestHoses")
	if rest != null: rest.free()
	root.set_script(load("res://game/3d/limne_model.gd"))
	root.set_meta("model_source", SOURCE)
	_fix_iris_vertex_color(root)
	return root

static func _fix_iris_vertex_color(node: Node) -> void:
	# The GLB carries radial brown COLOR_0, but the importer leaves the
	# textureless iris material's vertex-color switch disabled. Share its small
	# corrected material through the existing PackedScene cache, not per frame.
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and mat.resource_name == "Eye_brown_radial_iris":
				mat.vertex_color_use_as_albedo = true
				mat.vertex_color_is_srgb = false
				mat.clearcoat = 0.12
				mat.clearcoat_roughness = 0.35
			if mat != null:
				mat.metallic_specular = 0.16
				var name := mat.resource_name
				if mat.albedo_texture != null:
					mat.roughness_texture = null
					mat.metallic_texture = null
					mat.roughness = 0.86
					mat.metallic = 0.0
				elif name.contains("Hair"):
					mat.roughness = 0.82
					mat.metallic_specular = 0.12
				elif name.contains("Skin_"):
					mat.roughness = 0.78
					mat.clearcoat_enabled = false
	for child in node.get_children():
		_fix_iris_vertex_color(child)

static func tube_mesh() -> ArrayMesh:
	if _tube != null: return _tube
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in range(19):
		for side in range(8):
			var angle := TAU*float(side)/8.0
			vertices.append(Vector3(cos(angle)*0.026,sin(angle)*0.026,float(ring)/18.0))
			normals.append(Vector3(cos(angle),sin(angle),0))
	for ring in range(18):
		for side in range(8):
			var a := ring*8+side
			var b := ring*8+(side+1)%8
			indices.append_array(PackedInt32Array([a,a+8,b,b,a+8,b+8]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	_tube = ArrayMesh.new()
	_tube.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return _tube

func _ready() -> void:
	_skeleton = _find_skeleton(self)
	if _skeleton != null:
		var skeleton_to_root := global_transform.affine_inverse()*_skeleton.global_transform
		for name in ["Body","ArmL","ArmR","LegL","LegR"]:
			var index := _skeleton.find_bone("Skin"+name)
			if index < 0: continue
			var control: Node3D = get_node(name)
			_bone_bindings.append({"index":index,"control":control,
				"control_bind_inverse":control.transform.affine_inverse(),
				"root_rest":skeleton_to_root*_skeleton.get_bone_global_rest(index)})
		for side in ["L","R"]:
			for part in ["Forearm","Hand"]:
				var index := _skeleton.find_bone("Skin"+part+side)
				if index >= 0:
					_joint_bindings.append({"index":index,"side":side,"part":part,
						"root_rest":skeleton_to_root*_skeleton.get_bone_global_rest(index)})
		_setup_spray()
		update_visuals()
		return
	for side in [-1,1]:
		var hose := MeshInstance3D.new()
		hose.name = "HoseL" if side == -1 else "HoseR"
		hose.mesh = tube_mesh()
		hose.custom_aabb = AABB(Vector3(-0.9,0,-0.7),Vector3(1.8,2.0,1.4))
		var mat := ShaderMaterial.new()
		mat.shader = HOSE_SHADER
		hose.material_override = mat
		_hoses.append(mat)
		add_child(hose)
	update_visuals()

func update_visuals() -> void:
	if _skeleton != null:
		var root_to_skeleton := _skeleton.global_transform.affine_inverse()*global_transform
		for binding in _bone_bindings:
			var control: Node3D = binding["control"]
			var target: Transform3D = root_to_skeleton*control.transform*binding["control_bind_inverse"]*binding["root_rest"]
			var index: int = binding["index"]
			var parent := _skeleton.get_bone_parent(index)
			if parent >= 0: target = _skeleton.get_bone_global_pose(parent).affine_inverse()*target
			# Godot 4 bone poses are absolute local transforms, not rest deltas.
			_skeleton.set_bone_pose(index,target)
		for binding in _joint_bindings:
			var side: String = binding["side"]
			var n := 0 if side == "L" else 1
			var sign_value := -1.0 if n==0 else 1.0
			var arm: Node3D = get_node("Arm"+side)
			var bind_arm := Transform3D(Basis.IDENTITY,Vector3(sign_value*0.32,1.035,0))
			var arm_delta := arm.transform*bind_arm.affine_inverse()
			var elbow := _around(Vector3(sign_value*0.34,0.82,-0.14),Basis(Vector3.RIGHT,_elbow_angle))
			var delta := arm_delta*elbow
			if binding["part"] == "Hand":
				# Counter-rotate the palm, so the nozzle stays aligned with the
				# character's -Z forward even while its elbow lifts the wrist.
				delta = delta*_around(Vector3(sign_value*0.347,0.565,-0.213),delta.basis.inverse())
				_hand_deltas[n] = delta
			_skeleton.set_bone_pose(int(binding["index"]),root_to_skeleton*delta*binding["root_rest"])
		_update_spray()
		return
	if _hoses.size() != 2: return
	var body: Node3D = get_node("Body")
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var arm: Node3D = get_node("ArmL" if i == 0 else "ArmR")
		var start: Vector3 = body.transform*Vector3(side*0.418,0.916,0.271)
		var end: Vector3 = arm.transform*Vector3(side*0.065,-0.323,0.086)
		var mat := _hoses[i]
		mat.set_shader_parameter("p0",start)
		mat.set_shader_parameter("p1",start+Vector3(side*0.15,-0.48,0.025))
		mat.set_shader_parameter("p2",end+Vector3(side*0.18,-0.22,0.14))
		mat.set_shader_parameter("p3",end)

static func _around(point: Vector3, rotation: Basis) -> Transform3D:
	return Transform3D(rotation,point-rotation*point)

func animate_visual(time: float, age: float = 9.0, wind: float = 0.6, battle: bool = false) -> void:
	_motion_time = time
	wind = maxf(wind,0.04)
	var active := battle and age>=0.0 and age<wind+0.22
	_aim_amount = smoothstep(0.0,0.72,age/wind) if active and age<wind else 1.0-smoothstep(0.0,1.0,(age-wind)/0.22) if active else 0.0
	var release := maxf(0.0,age-wind)
	var recoil := exp(-release*28.0)*sin(release*48.0)*0.025 if active and age>=wind else 0.0
	var breath := sin(time*TAU/3.0)*0.008
	var sway := sin(time*TAU/6.0)
	var body: Node3D = get_node("Body")
	body.position = Vector3(sway*0.004,breath,0)
	body.rotation = Vector3(-_aim_amount*0.03-recoil,0,sway*0.007*(1.0-_aim_amount))
	for side in ["L","R"]:
		var sign_value := -1.0 if side=="L" else 1.0
		var arm: Node3D = get_node("Arm"+side)
		arm.position = Vector3(sign_value*0.32,1.035+breath,0)
		arm.rotation = Vector3(_aim_amount*0.035,0,sin(time*TAU/3.0+sign_value*0.3)*0.015*(1.0-_aim_amount))
	_elbow_angle = _aim_amount*0.86
	# A visual release burst follows the already-existing gameplay release time.
	_spray_strength = sin(clampf(release/0.13,0,1)*PI) if active and age>=wind and release<0.13 else 0.0
	update_visuals()

func spray_strength() -> float:
	return _spray_strength

func nozzle_transform(side: int) -> Transform3D:
	var n := 0 if side<0 else 1
	var sign_value := -1.0 if n==0 else 1.0
	return global_transform*_hand_deltas[n]*Transform3D(Basis.IDENTITY,Vector3(sign_value*0.347,0.565,-0.400))

func _setup_spray() -> void:
	if _spray_mesh == null:
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for ring in range(13):
			var t := float(ring)/12.0
			for side in range(12):
				var angle := TAU*float(side)/12.0
				vertices.append(Vector3(cos(angle)*(0.012+t*0.095),sin(angle)*(0.012+t*0.095)-t*t*0.055,-t*0.88))
				uvs.append(Vector2(t,float(side)/12.0))
		for ring in range(12):
			for side in range(12):
				var a := ring*12+side
				var b := ring*12+(side+1)%12
				indices.append_array(PackedInt32Array([a,b,a+12,b,b+12,a+12]))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_TEX_UV]=uvs
		arrays[Mesh.ARRAY_INDEX]=indices
		_spray_mesh=ArrayMesh.new()
		_spray_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_drop_mesh=SphereMesh.new()
		_drop_mesh.radius=0.014
		_drop_mesh.height=0.028
		_drop_mesh.radial_segments=6
		_drop_mesh.rings=3
		_drop_material=StandardMaterial3D.new()
		_drop_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		_drop_material.albedo_color=Color(0.33,0.86,1.0)
	_spray_material=ShaderMaterial.new()
	_spray_material.shader=WATER_SHADER
	for side in ["L","R"]:
		var stream:=MeshInstance3D.new()
		stream.name="WaterSpray"+side
		stream.mesh=_spray_mesh
		stream.material_override=_spray_material
		stream.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stream)
		_streams.append(stream)
		for i in range(7):
			var drop:=MeshInstance3D.new()
			drop.mesh=_drop_mesh
			drop.material_override=_drop_material
			drop.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(drop)
			_drops.append(drop)

func _update_spray() -> void:
	if _spray_material == null:return
	_spray_material.set_shader_parameter("strength",_spray_strength)
	_spray_material.set_shader_parameter("flow_time",_motion_time)
	for n in range(2):
		var mouth := global_transform.affine_inverse()*nozzle_transform(-1 if n==0 else 1)
		_streams[n].transform=mouth
		_streams[n].visible=_spray_strength>0.002
		for i in range(7):
			var drop := _drops[n*7+i]
			var t := fposmod(_motion_time*7.0+float(i)*0.17,1.0)
			drop.position=mouth*Vector3(sin(i*2.9)*t*0.075,cos(i*2.3)*t*0.045-t*t*0.10,-0.10-t*0.94)
			drop.scale=Vector3.ONE*(0.6+_spray_strength*0.6)
			drop.visible=_spray_strength>0.02

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null: return found
	return null
