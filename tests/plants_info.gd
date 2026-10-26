extends SceneTree
func _initialize() -> void:
	for m in ["grass_medium_01", "grass_medium_02", "dandelion_01", "nettle_plant", "shrub_04"]:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file(ProjectSettings.globalize_path("res://models/plants/%s/%s.gltf" % [m, m]), st)
		var scene := doc.generate_scene(st)
		var tris := 0
		var nodes := []
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var c := 0
			for s in mi.mesh.get_surface_count():
				var a := mi.mesh.surface_get_arrays(s)
				c += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
				nodes.append("%s: %d tris, alpha=%d, aabb %s" % [mi.name, c, mat.transparency if mat else -1, (mi.global_transform * mi.mesh.get_aabb()).size if mi.is_inside_tree() else mi.mesh.get_aabb().size])
			tris += c
		print(m, " err=", err, " всего ", tris, " треуг.: ", nodes)
	quit()
