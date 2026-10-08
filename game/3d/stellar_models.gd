extends RefCounted
class_name StellarModels

## Geometry, materials and packed rigs are shared. No combat values live here.
const MANIFEST := "res://art/models/manifest.json"
static var _profiles: Dictionary = {}
static var _mesh: Dictionary = {}
static var _materials: Dictionary = {}
static var _rigs: Dictionary = {}

static func profiles() -> Dictionary:
	if _profiles.is_empty():
		var file := FileAccess.open(MANIFEST, FileAccess.READ)
		if file != null:
			_profiles = JSON.parse_string(file.get_as_text()).get("heroes", {})
	return _profiles

static func material(color: Color, metal: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [color.to_html(), metal, glow]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.38 if metal > 0.2 else 0.78
	if glow > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	_materials[key] = mat
	return mat

static func primitive(kind: String) -> Mesh:
	if _mesh.has(kind):
		return _mesh[kind]
	var mesh: PrimitiveMesh
	match kind:
		"box": mesh = BoxMesh.new()
		"cylinder", "cone", "pentagon":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.0 if kind == "cone" else 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 5 if kind == "pentagon" else 10
			mesh = cylinder
		"ring":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.40
			torus.outer_radius = 0.50
			torus.rings = 16
			torus.ring_segments = 6
			mesh = torus
		_:
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh = sphere
	_mesh[kind] = mesh
	return mesh

static func part(parent: Node3D, kind: String, at: Vector3, dimensions: Vector3,
		color: Color, metal: float = 0.0, glow: float = 0.0, angles := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = primitive(kind)
	node.material_override = material(color, metal, glow)
	node.position = at
	node.scale = dimensions
	node.rotation = angles
	parent.add_child(node)
	return node

static func link(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color,
		metal: float = 0.0, glow: float = 0.0) -> MeshInstance3D:
	var node := part(parent, "cylinder", (a + b) * 0.5,
		Vector3(radius, a.distance_to(b), radius), color, metal, glow)
	var direction := (b - a).normalized()
	if direction.length_squared() > 0.01:
		node.quaternion = Quaternion(Vector3.UP, direction)
	return node

## Merge static primitives by material, retaining the arm/leg pivots for animation.
static func compact(root: Node3D) -> void:
	var groups: Dictionary = {}
	for child in root.get_children():
		if child is MeshInstance3D:
			var mat: Material = child.material_override
			if not groups.has(mat): groups[mat] = []
			groups[mat].append(child)
		elif child is Node3D:
			compact(child)
	for mat in groups:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for node in groups[mat]:
			surface.append_from(node.mesh, 0, node.transform)
			node.free()
		surface.set_material(mat)
		var merged := MeshInstance3D.new()
		merged.mesh = surface.commit()
		root.add_child(merged)

static func _ownership(root: Node, owner: Node) -> void:
	for child in root.get_children():
		child.owner = owner
		_ownership(child, owner)

static func hero(unit: Dictionary, grade: int) -> Node3D:
	grade = clampi(grade, 0, 9)
	var id := String(unit.get("base_id", unit.get("id", "limne")))
	var key := "%s:%d:%s" % [id, grade, str(unit.get("fusion_only", false))]
	if _rigs.has(key):
		var cached: PackedScene = _rigs[key]
		_rigs.erase(key)
		_rigs[key] = cached
		return cached.instantiate()
	var profile: Dictionary = profiles().get(id, profiles().get("limne", {}))
	var root := Node3D.new()
	root.name = "StellarHero_" + id
	root.set_meta("identity", id)
	root.set_meta("grade", grade)
	var width := 1.24 if profile.get("build") == "heavy" else 0.84 if profile.get("build") == "slim" else 1.0
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var base := Color(String(profile.get("coat", unit.get("color", "#5ce8ff"))))
	var skin := Color(String(profile.get("skin", "#e2b798")))
	var hair := Color(String(profile.get("hair", "#2d3547")))
	var brass := Color("#caa263") if grade < 6 else Color("#f2d297")
	var steel := Color("#c6dbe0")
	var dark := Color("#23303e")
	part(body, "sphere", Vector3(0, 0.82, 0), Vector3(0.55 * width, 0.67, 0.38), base)
	part(body, "sphere", Vector3(0, 0.55, 0), Vector3(0.46 * width, 0.32, 0.33), dark)
	part(body, "ring", Vector3(0, 0.64, 0), Vector3(0.54 * width, 0.16, 0.37), brass, 0.65)
	part(body, "sphere", Vector3(0, 1.29, -0.005), Vector3(0.51, 0.50, 0.45), skin)
	part(body, "sphere", Vector3(0, 1.47, 0.045), Vector3(0.54, 0.25, 0.47), hair)
	for side in [-1,1]:
		part(body,"sphere",Vector3(side*0.255,1.28,0),Vector3(0.085,0.13,0.10),skin)
		part(body,"box",Vector3(side*0.105,1.365,-0.215),Vector3(0.095,0.026,0.025),hair)
		part(body,"sphere",Vector3(side*0.148,1.255,-0.197),Vector3(0.065,0.045,0.020),skin.lerp(Color("#c87566"),0.30))
	# Workwear seams, collar and broad cuffs read at portrait size.
	for side in [-1,1]:
		part(body,"box",Vector3(side*0.12,1.074,-0.17),Vector3(0.16,0.13,0.035),base.lightened(0.18),0,0,Vector3(0,0,side*0.5))
		link(body,Vector3(side*0.18,0.70,-0.15),Vector3(side*0.17,1.00,-0.15),0.016,brass,0.3)
	for n in range(3): part(body,"sphere",Vector3(0,0.75+n*0.10,-0.195),Vector3(0.025,0.025,0.015),brass,0.6)
	# Visible face features, consistently on -Z; yaw animation rotates the whole rig.
	for side in [-1, 1]:
		part(body, "sphere", Vector3(side * 0.105, 1.32, -0.222), Vector3(0.085, 0.065, 0.025), Color("#17212d"))
		part(body, "sphere", Vector3(side * 0.095, 1.335, -0.239), Vector3(0.022, 0.022, 0.012), Color("#ffffff"), 0, 0.1)
		var leg := Node3D.new()
		leg.name = "LegL" if side == -1 else "LegR"
		leg.position = Vector3(side * 0.155 * width, 0.49, 0)
		root.add_child(leg)
		part(leg, "sphere", Vector3(0, -0.18, 0), Vector3(0.20 * width, 0.47, 0.21), base.darkened(0.28))
		part(leg, "sphere", Vector3(0, -0.40, -0.04), Vector3(0.25 * width, 0.20, 0.32), dark)
		var arm := Node3D.new()
		arm.name = "ArmL" if side == -1 else "ArmR"
		arm.position = Vector3(side * 0.30 * width, 1.02, 0)
		root.add_child(arm)
		part(arm, "sphere", Vector3(side * 0.07, -0.16, 0), Vector3(0.22, 0.43, 0.23), base)
		part(arm, "sphere", Vector3(side * 0.09, -0.36, -0.02), Vector3(0.18, 0.18, 0.18), skin)
		part(arm, "sphere", Vector3(side * 0.03, 0.0, 0), Vector3(0.32 + grade * 0.012, 0.22, 0.30), steel if grade >= 3 else base.lightened(0.15), 0.5 if grade >= 3 else 0)
	part(body, "sphere", Vector3(0, 1.26, -0.245), Vector3(0.09, 0.10, 0.09), skin.darkened(0.05))
	part(body, "box", Vector3(0, 1.18, -0.213), Vector3(0.10, 0.020, 0.018), Color("#8b554b"))
	match String(profile.get("hair_style", "short")):
		"bald":
			part(body, "sphere", Vector3(0, 1.46, 0.02), Vector3(0.54, 0.25, 0.46), skin)
		"tail":
			part(body, "sphere", Vector3(0, 1.56, 0.16), Vector3(0.22, 0.32, 0.25), hair)
			part(body, "sphere", Vector3(0, 1.23, 0.27), Vector3(0.20, 0.50, 0.18), hair)
		"braids":
			for side in [-1, 1]:
				for n in range(4): part(body, "sphere", Vector3(side * 0.24, 1.37 - n * 0.09, 0.12), Vector3(0.13, 0.14, 0.14), hair)
	_build_kit(body, String(profile.get("kit", "reservoir")), base, brass, steel)
	_build_weapon(root.get_node("ArmR"), String(unit.get("weapon", "deck")), base, brass, grade, int(profile.get("index", 0)))
	_rank_details(body, base, brass, grade, int(profile.get("index", 0)), bool(unit.get("fusion_only", false)))
	compact(root)
	_ownership(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	_rigs[key] = packed
	while _rigs.size() > 96: _rigs.erase(_rigs.keys()[0])
	root.free()
	return packed.instantiate()

static func _build_weapon(arm: Node3D, kind: String, base: Color, brass: Color, grade: int, index: int) -> void:
	var steel := Color("#c5dce0")
	var p := Vector3(0.10, -0.32, -0.06)
	match kind:
		"sword":
			part(arm, "cylinder", p, Vector3(0.09, 0.25, 0.09), brass, 0.7)
			part(arm, "box", p + Vector3(0, 0.14, 0), Vector3(0.32, 0.045, 0.12), brass, 0.7)
			part(arm, "box", p + Vector3(0, 0.53, 0), Vector3(0.13 + (index % 3) * 0.045, 0.76 + grade * 0.015, 0.055), steel, 0.75)
			part(arm, "box", p + Vector3(0, 0.53, -0.032), Vector3(0.028, 0.62 + grade * 0.014, 0.02), base, 0.2, 0.25 if grade < 6 else 0.7)
			part(arm, "cone", p + Vector3(0, 0.95 + grade * 0.008, 0), Vector3(0.15, 0.17, 0.05), steel, 0.65)
		"gun":
			part(arm, "box", p + Vector3(0, 0, -0.18), Vector3(0.20, 0.21, 0.38 + (index % 3) * 0.09), brass, 0.7)
			link(arm, p + Vector3(0, 0, -0.20), p + Vector3(0, 0, -0.57), 0.12, steel, 0.8)
			part(arm, "sphere", p + Vector3(0, 0, -0.57), Vector3(0.09, 0.09, 0.025), base, 0.1, 0.5)
		"bow":
			var previous := p + Vector3(0.1, -0.51, -0.13)
			var start := previous
			for i in range(1, 9):
				var a := -PI * 0.5 + PI * i / 8.0
				var next := p + Vector3(0.1, sin(a) * 0.51, -0.13 - cos(a) * 0.25)
				link(arm, previous, next, 0.065, brass, 0.65)
				previous = next
			link(arm, start, previous, 0.018, steel)
			link(arm, p + Vector3(-0.20, 0, -0.1), p + Vector3(0.2, 0, -0.65), 0.025, steel, 0.5)
		"whip":
			for i in range(10):
				var a := float(i) / 10 * TAU
				part(arm, "sphere", p + Vector3(cos(a) * 0.22, sin(a) * 0.31 - 0.13, -0.08), Vector3(0.09, 0.12, 0.085), brass, 0.8)
		_:
			part(arm, "ring", p, Vector3(0.33, 0.14, 0.33), brass, 0.7)
			part(arm, "sphere", p + Vector3(0, 0.12, 0), Vector3(0.23, 0.29, 0.23), base, 0.2, 0.6)

static func _build_kit(body: Node3D, kit: String, base: Color, brass: Color, steel: Color) -> void:
	var back := Vector3(0, 1.14, 0.29)
	var rim := base.lightened(0.27)
	match kit:
		"reservoir", "irrigation", "life_ring", "twin_tanks", "sun_bow", "burner", "snowflake", "hexframe", "patchpanel", "safety", "transmission":
			var radius := 0.78 if kit in ["irrigation", "hexframe", "patchpanel", "transmission"] else 0.57
			if kit == "burner": back = Vector3(0, 0.67, 0)
			part(body, "pentagon" if kit=="patchpanel" else "ring", back, Vector3(radius * 1.9, 0.14, radius * 1.9), brass, 0.7, 0, Vector3(PI * 0.5, 0, 0))
			if kit in ["reservoir", "twin_tanks"]:
				part(body, "sphere", back, Vector3(0.90, 0.90, 0.27), base, 0.4)
			if kit == "twin_tanks":
				for side in [-1,1]: part(body, "sphere", back + Vector3(side * 0.46, 0, 0), Vector3(0.65, 0.70, 0.20), rim, 0.35)
			var count := 5 if kit == "patchpanel" else 6
			for n in range(count):
				var a := TAU * n / count
				var p := back + Vector3(sin(a) * radius, cos(a) * radius, 0)
				part(body, "box" if kit == "patchpanel" else "sphere", p, Vector3(0.20, 0.22, 0.19), rim, 0.3, 0.3)
			if kit == "transmission":
				for side in [-1, 1]:
					part(body, "cylinder", back + Vector3(side * 0.48, 0.24, 0), Vector3(0.24, 0.69, 0.24), brass, 0.75)
		"petals":
			for n in range(6):
				var a := TAU * n / 6
				part(body, "sphere", back + Vector3(sin(a) * 0.49, cos(a) * 0.49, 0), Vector3(0.39, 0.63, 0.15), brass, 0.5, 0, Vector3(0, 0, -a))
				part(body, "sphere", back + Vector3(sin(a) * 0.49, cos(a) * 0.49, -0.08), Vector3(0.24, 0.45, 0.08), base, 0.2, 0.35, Vector3(0, 0, -a))
			part(body, "sphere", Vector3(0, 0.86, -0.21), Vector3(0.32, 0.32, 0.10), Color("#ffb76a"), 0.2, 0.7)
		"sluice", "bulwark", "press", "crossframe", "counterweight":
			for side in [-1, 1]:
				part(body, "box", back + Vector3(side * 0.35, 0.16, 0), Vector3(0.34, 0.96, 0.15), steel, 0.55, 0, Vector3(0, 0, side * 0.32 if kit == "crossframe" else 0))
				part(body, "box", back + Vector3(side * 0.35, 0.16, -0.09), Vector3(0.21, 0.74, 0.025), base)
			part(body, "box", Vector3(0, 0.87, -0.24), Vector3(0.27, 0.32, 0.09), brass, 0.7)
		"columns", "rockets", "antenna", "triangle", "furnace":
			var count := 6 if kit == "rockets" else 2 if kit == "furnace" else 3
			for n in range(count):
				var p := back + Vector3((n - (count - 1) * 0.5) * 0.22, 0.21 + (n % 3) * 0.10, 0)
				part(body, "cylinder", p, Vector3(0.16, 0.8 + n % 3 * 0.17, 0.16), rim if kit == "columns" else brass, 0.5)
				part(body, "cone", p + Vector3(0, 0.52, 0), Vector3(0.22, 0.27, 0.22), base, 0.2, 0.25)
		"sharkfin", "polar":
			part(body, "cone", back + Vector3(0, 0.2, 0), Vector3(0.32, 0.95, 0.37), rim, 0.2)
			if kit == "polar": part(body, "ring", Vector3(0, 1.30, 0), Vector3(0.70, 0.29, 0.66), steel)
		"gear", "meter", "pendulum", "capacitors", "batteries", "railgun", "piston", "gauntlet", "heatshield":
			part(body, "ring", Vector3(0, 0.87, -0.24), Vector3(0.39, 0.12, 0.39), brass, 0.8, 0, Vector3(PI / 2, 0, 0))
			part(body, "sphere", Vector3(0, 0.87, -0.28), Vector3(0.24, 0.24, 0.07), base, 0.4, 0.25)
			for side in [-1, 1]: part(body, "cylinder", Vector3(side * 0.31, 0.68, 0.1), Vector3(0.18, 0.30, 0.18), brass, 0.8)
			if kit in ["railgun", "piston", "gauntlet", "heatshield"]:
				part(body, "sphere", Vector3(0.35, 1.05, 0), Vector3(0.40, 0.37, 0.38), brass, 0.75)
				link(body, Vector3(0.39, 1.0, 0), Vector3(0.46, 0.62, 0), 0.17, brass, 0.8)
		"conch":
			var cannon := back+Vector3(0.37,0.17,0)
			part(body,"cylinder",cannon,Vector3(0.33,0.80,0.33),brass,0.6)
			part(body,"ring",cannon+Vector3(0,0.40,0),Vector3(0.54,0.19,0.54),brass,0.6)
			for n in range(3): part(body,"ring",cannon+Vector3(0,-0.20+n*0.17,0),Vector3(0.36,0.075,0.36),steel,0.6)
			link(body,cannon+Vector3(0,-0.34,0),Vector3(0.28,0.63,0.13),0.13,base)
			part(body,"cylinder",Vector3(0,1.49,0),Vector3(0.61,0.07,0.52),base.darkened(0.2))
			part(body,"cylinder",Vector3(0,1.56,0.04),Vector3(0.47,0.13,0.43),base)

		"fan_bow", "double_bow", "electrode_bow":
			var count := 3 if kit=="fan_bow" else 2
			for n in range(count):
				var offset := Vector3(-0.36-n*0.11,0.91,0.22)
				link(body,offset+Vector3(-0.17,-0.41,0),offset+Vector3(-0.28,0,0),0.075,brass,0.65)
				link(body,offset+Vector3(-0.28,0,0),offset+Vector3(-0.17,0.41,0),0.075,brass,0.65)
				link(body,offset+Vector3(-0.17,-0.41,0),offset+Vector3(-0.17,0.41,0),0.015,steel)
				if kit=="electrode_bow":
					for side in [-1,1]: part(body,"sphere",offset+Vector3(-0.17,side*0.41,0),Vector3(0.18,0.18,0.18),brass,0.7)
		"reel", "cables", "bristles", "segments", "anchor":
			var at := Vector3(-0.34,0.62,0)
			part(body,"ring",at,Vector3(0.42,0.19,0.42),brass,0.7,0,Vector3(0,0,PI/2))
			for n in range(8):
				var a := n*TAU/8
				part(body,"box" if kit=="segments" else "sphere",at+Vector3(0,cos(a)*0.30,sin(a)*0.22),Vector3(0.09,0.15,0.12),steel,0.7)
			if kit=="anchor":
				link(body,Vector3(0.39,0.46,0),Vector3(0.39,0.86,0),0.07,steel,0.6)
				link(body,Vector3(0.20,0.42,0),Vector3(0.57,0.42,0),0.08,steel,0.6)
			elif kit=="bristles":
				for n in range(5): part(body,"box",Vector3(-0.47+n*0.05,0.29,0),Vector3(0.025,0.18,0.07),brass,0.6)
		"stamp":
			part(body,"box",Vector3(-0.17,0.12,-0.06),Vector3(0.44,0.25,0.49),steel,0.5)
			part(body,"cylinder",back,Vector3(0.57,0.69,0.38),base,0.2)
			link(body,back+Vector3(-0.22,-0.20,0),Vector3(-0.19,0.22,0.11),0.09,brass,0.5)
		"revolver", "shotgun", "dual_pistol", "sniper", "pneumatic":
			var count := 6 if kit=="revolver" else 2 if kit in ["shotgun","dual_pistol"] else 3
			for n in range(count):
				var p := back+Vector3((n-(count-1)*0.5)*0.11,0,0)
				part(body,"cylinder",p,Vector3(0.11,0.64 if kit=="sniper" else 0.38,0.11),rim,0.35)
				part(body,"ring",p+Vector3(0,0.16,0),Vector3(0.13,0.065,0.13),brass,0.75)
			if kit=="dual_pistol":
				for side in [-1,1]: part(body,"box",Vector3(side*0.32,0.56,-0.08),Vector3(0.18,0.30,0.10),brass,0.7)
		"cleaver", "tension":
			for side in [-1,1]: link(body,back+Vector3(side*0.21,-0.31,0),back+Vector3(side*0.21,0.62,0),0.055,steel,0.65)
			if kit=="cleaver": part(body,"box",Vector3(-0.41,0.58,0.10),Vector3(0.24,0.92,0.08),steel,0.7)

		_:
			# Reels, visible channels, quivers and articulation remain unique by equipment index.
			part(body, "ring", Vector3(-0.33, 0.66, 0.04), Vector3(0.39, 0.17, 0.39), brass, 0.75, 0, Vector3(0, 0, PI / 2))
			for n in range(3):
				part(body, "cylinder", back + Vector3((n - 1) * 0.16, 0.05, 0), Vector3(0.10, 0.49 + n * 0.08, 0.10), rim if kit in ["sniper", "shotgun", "pneumatic"] else brass, 0.55)

	if kit=="pendulum":
		part(body,"cylinder",Vector3(0,1.51,0),Vector3(0.77,0.07,0.60),Color("#485566"))
		part(body,"cylinder",Vector3(0,1.62,0),Vector3(0.48,0.23,0.42),Color("#65717b"))
		part(body,"ring",Vector3(0,1.53,0),Vector3(0.53,0.07,0.46),brass,0.5)
		part(body,"ring",Vector3(0.105,1.32,-0.26),Vector3(0.17,0.027,0.17),brass,0.7,0,Vector3(PI/2,0,0))
	elif kit=="snowflake":
		for side in [-1,1]: part(body,"cone",Vector3(side*0.18,1.57,0),Vector3(0.18,0.31,0.17),steel)
	elif kit=="revolver":
		part(body,"cylinder",Vector3(0,1.52,0),Vector3(0.59,0.17,0.48),base.darkened(0.1))

static func _rank_details(body: Node3D, base: Color, gold: Color, grade: int, index: int, awakened: bool) -> void:
	# Every half-star changes equipment, not just a tint or uniform scaling.
	if grade >= 1: part(body, "sphere", Vector3(0, 0.95, -0.205), Vector3(0.13, 0.16, 0.08), gold, 0.75)
	if grade >= 2:
		for side in [-1,1]: part(body, "box", Vector3(side * 0.16, 0.25, -0.13), Vector3(0.19, 0.24, 0.065), Color("#bacdd4"), 0.5)
	if grade >= 3:
		for side in [-1,1]: part(body, "sphere", Vector3(side * 0.30, 1.10, 0), Vector3(0.39, 0.18, 0.35), gold, 0.65)
	if grade >= 4:
		part(body, "box", Vector3(0, 0.78, 0.27), Vector3(0.70, 0.91, 0.06), base.darkened(0.26), 0, 0, Vector3(0.20, 0, 0))
		for side in [-1,1]: link(body, Vector3(side * 0.33, 0.38, 0.33), Vector3(side * 0.33, 1.2, 0.19), 0.037, gold, 0.75)
	if grade >= 5:
		part(body, "ring", Vector3(0, 1.46, 0), Vector3(0.55, 0.17, 0.48), gold, 0.8)
		for n in range(3): part(body, "cone", Vector3((n - 1) * 0.13, 1.60, -0.10), Vector3(0.09, 0.23, 0.09), gold, 0.8)
	if grade >= 6:
		for side in [-1,1]: part(body, "sphere", Vector3(side * 0.39, 1.10, -0.13), Vector3(0.12, 0.15, 0.08), base.lightened(0.45), 0.2, 0.7)
	if grade >= 7:
		for side in [-1,1]:
			for n in range(3): part(body, "cone", Vector3(side * (0.41 + 0.10 * n), 1.11 + n * 0.09, 0.21), Vector3(0.13, 0.34, 0.11), gold, 0.7, 0, Vector3(0,0,side * -0.8))
	if grade >= 8:
		part(body, "ring", Vector3(0, 1.62, 0.36), Vector3(0.91, 0.07, 0.91), gold, 0.65, 0.5, Vector3(PI / 2,0,0))
	if grade >= 9:
		for n in range(5):
			var a := n * TAU / 5 + float(index) * 0.1
			part(body, "cone", Vector3(sin(a) * 0.54, 1.60 + cos(a) * 0.38, 0.36), Vector3(0.11,0.17,0.09), base.lightened(0.60), 0.2,0.8)
	if awakened:
		part(body, "ring", Vector3(0, 0.10, 0), Vector3(1.26, 0.045, 1.26), gold, 0.75, 0.65)
		for side in [-1,1]: part(body,"cone",Vector3(side*0.57,1.3,0.3),Vector3(0.22,0.72,0.14),base,0.5,0.4,Vector3(0,0,-side*0.5))

static func monster(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "StellarMonster_" + String(data.get("id", "monster"))
	var kind := String(data.get("kind", "swarm"))
	var body := String(data.get("body", "rock"))
	var color := Color(String(data.get("color", "#7286a2")))
	var dark := color.darkened(0.45)
	var giant := kind in ["tank", "boss"]
	if kind == "tank" and body == "flame":
		part(root,"sphere",Vector3(0,0.45,0),Vector3(0.82,0.70,1.0),dark)
		part(root,"box",Vector3(0,0.54,-0.57),Vector3(0.54,0.43,0.48),dark)
		for side in [-1,1]:
			for z in [-0.30,0.34]: part(root,"box",Vector3(side*0.35,0.22,z),Vector3(0.29,0.43,0.29),dark)
			part(root,"cone",Vector3(side*0.29,0.79,-0.52),Vector3(0.20,0.44,0.17),Color("#baa691"),0.1,0,Vector3(0,0,-side*0.7))
		for n in range(4): part(root,"box",Vector3(0,0.65,-0.25+n*0.16),Vector3(0.83,0.045,0.034),color,0,0.65)
	elif kind == "fast":
		part(root,"sphere",Vector3(0,0.33,0),Vector3(0.43,0.45,0.80),color)
		part(root,"sphere",Vector3(0,0.45,-0.40),Vector3(0.34,0.34,0.40),color.lightened(0.05))
		for side in [-1,1]:
			for z in [-0.22,0.23]: part(root,"sphere",Vector3(side*0.21,0.17,z),Vector3(0.15,0.31,0.16),dark)
		link(root,Vector3(0,0.31,0.35),Vector3(0,0.39,0.77),0.12,color)
		if body == "aqua":
			for side in [-1,1]: part(root,"sphere",Vector3(side*0.43,0.28,0),Vector3(0.77,0.085,0.53),color)
	elif kind == "caster":
		part(root,"cone",Vector3(0,0.36,0),Vector3(0.58,0.75,0.45),dark)
		part(root,"sphere",Vector3(0,0.81,0),Vector3(0.43,0.39,0.42),color)
		if body in ["wood", "aqua"]:
			part(root,"sphere",Vector3(0,0.93,0),Vector3(0.90,0.39,0.75),color)
			for n in range(6): link(root,Vector3((n-2.5)*0.1,0.5,0.05),Vector3((n-2.5)*0.13,0.04,0.18),0.055,color)
		else:
			link(root,Vector3(0.37,0.05,0),Vector3(0.37,1.08,0),0.05,Color("#857b64"))
			part(root,"sphere",Vector3(0.37,1.08,0),Vector3(0.20,0.23,0.20),color,0.1,0.7)
	elif giant:
		part(root,"sphere" if body == "aqua" else "box",Vector3(0,0.60,0),Vector3(0.74,0.74,0.46),dark)
		part(root,"sphere",Vector3(0,1.02,-0.09),Vector3(0.53,0.43,0.47),color)
		for side in [-1,1]:
			part(root,"sphere",Vector3(side*0.47,0.67,0),Vector3(0.36,0.61,0.38),color)
			part(root,"sphere",Vector3(side*0.21,0.17,0),Vector3(0.30,0.35,0.36),dark)
			for n in range(3): part(root,"cone",Vector3(side*(0.31+n*0.13),0.97+n*0.1,0.19),Vector3(0.17,0.51,0.18),color.lightened(0.2),0.25)
		part(root,"sphere",Vector3(0,0.68,-0.245),Vector3(0.24,0.28,0.04),color,0.1,0.4)
		if kind == "boss":
			if body in ["flame","frost","aqua"]:
				for side in [-1,1]: part(root,"sphere",Vector3(side*0.75,0.95,0.22),Vector3(1.17,0.14,0.63),color,0.3,0,Vector3(0,0,side*0.30))
			elif body == "wood":
				for n in range(6):
					var a := n * TAU/6
					part(root,"sphere",Vector3(sin(a)*0.59,1.03+cos(a)*0.47,0),Vector3(0.49,0.60,0.18),color)
	else:
		part(root,"sphere",Vector3(0,0.27,0),Vector3(0.55,0.55,0.47),color)
		if body != "aqua":
			for side in [-1,1]: part(root,"sphere",Vector3(side*0.28,0.19,0),Vector3(0.16,0.24,0.15),dark)
			part(root,"cone",Vector3(0,0.64,0),Vector3(0.21,0.28,0.19),color.lightened(0.28),0.1)

	# Body-specific silhouettes are independent of colors: roots, crystal spines and tails.
	if body in ["wood","frost","rock"]:
		for n in range(4):
			part(root,"cone",Vector3((n%2-0.5)*0.29,0.64 if kind=="fast" else 0.40+n*0.12,0.18+n*0.10),Vector3(0.12,0.31+n%2*0.09,0.14),color.lightened(0.18),0.15)
	if kind=="fast" and body!="aqua":
		for side in [-1,1]: part(root,"cone",Vector3(side*0.13,0.66,-0.37),Vector3(0.15,0.30,0.12),dark)
		part(root,"sphere",Vector3(0,0.34,0.79),Vector3(0.24,0.24,0.53),color)
	if kind=="tank" and body=="wood":
		for n in range(5): part(root,"sphere",Vector3((n%3-1)*0.35,1.15+n%2*0.15,0.12),Vector3(0.63,0.49,0.57),color.darkened(0.2))
	if kind=="caster" and body=="wood":
		for n in range(5): part(root,"sphere",Vector3((n%3-1)*0.21,1.06+n%2*0.09,-0.14),Vector3(0.12,0.035,0.10),Color("#d9d3ba"))
	if kind=="caster" and body=="rock":
		part(root,"box",Vector3(0,0.60,0),Vector3(0.48,0.84,0.42),color,0.1)
		part(root,"cone",Vector3(0,1.23,0),Vector3(0.29,0.31,0.28),Color("#c1afee"),0.2,0.4)
	if kind=="boss" and body in ["flame","frost","aqua"]:
		part(root,"sphere",Vector3(0,0.88,-0.44),Vector3(0.48,0.36,0.83),color)
		for side in [-1,1]:
			part(root,"cone",Vector3(side*0.18,1.12,-0.43),Vector3(0.14,0.46,0.17),color.lightened(0.2),0.25,0,Vector3(-0.3,0,-side*0.5))
		part(root,"sphere",Vector3(0,0.44,0.58),Vector3(0.35,0.37,0.96),dark)
		link(root,Vector3(0,0.45,0.88),Vector3(0.30,0.64,1.13),0.15,color)
	var face_y := 1.06 if giant else 0.83 if kind == "caster" else 0.46 if kind == "fast" else 0.36
	var face_z := -0.82 if kind=="boss" and body in ["flame","frost","aqua"] else -0.76 if kind=="tank" and body=="flame" else -0.52 if kind == "fast" else -0.245
	for side in [-1,1]:
		part(root,"sphere",Vector3(side*0.10,face_y,face_z),Vector3(0.065,0.060,0.026),Color("#d1edff"),0,0.9)
	for status in ["Burn","Frost","Stun"]:
		var group := Node3D.new()
		group.name="Stellar"+status
		root.add_child(group)
		group.visible=false
		if status=="Stun":
			part(group,"ring",Vector3(0,face_y+0.20,0),Vector3(0.65,0.045,0.65),Color("#eeda70"),0,0.9)
		else:
			for n in range(4):
				var a := n*TAU/4
				part(group,"cone",Vector3(cos(a)*0.25,0.10,sin(a)*0.25),Vector3(0.10,0.44 if status=="Burn" else 0.26,0.09),Color("#ff994d") if status=="Burn" else Color("#a5e6f0"),0,0.6)
	compact(root)
	root.scale *= 1.40 if kind == "boss" else 1.13 if kind == "tank" else 0.86
	return root
