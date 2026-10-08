extends Harness

func _ready() -> void:
	if not require_no_save(): return
	check(StellarModels.profiles().size()==50,"all fifty hero design profiles")
	for unit in Roster.UNITS:
		var previous := -1
		for grade in range(10):
			var model := StellarModels.hero(unit,grade)
			check(model is Node3D,"real 3D hero: %s/%d"%[unit["id"],grade])
			check(model.get_meta("grade")==grade,"instance grade, not artwork tier")
			check(model.has_node("ArmL") and model.has_node("ArmR") and model.has_node("LegL") and model.has_node("LegR"),"animated rig pivots")
			var vertices := _vertices(model)
			check(vertices>previous,"new equipment at every half-star: %s/%d"%[unit["id"],grade])
			previous=vertices
			check(ResourceLoader.exists(StellarPortraits.path(unit,grade)),"rendered portrait present")
			StellarPortraits.preview(unit,grade)
			model.free()
	for grade in range(10):
		for unit in Roster.fusion_units(grade):
			var model := StellarModels.hero(unit,grade)
			check(model is Node3D,"awakened 3D hero")
			check(ResourceLoader.exists(StellarPortraits.path(unit,grade)),"awakened rendered portrait")
			model.free()
	for data in Roster.MONSTERS:
		var model := StellarModels.monster(data)
		check(_vertices(model)>100,"real geometry for every monster: "+String(data["id"]))
		model.free()
	check(StellarModels._rigs.size()<=96,"packed rig LRU bound")
	check(StellarPortraits._cache.size()<=64,"decoded portrait LRU bound")
	finish("Stellar 3D model coverage / rank evolution / mobile caches")

func _vertices(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()): count+=node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
	for child in node.get_children(): count+=_vertices(child)
	return count
