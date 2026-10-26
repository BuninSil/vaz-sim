extends SceneTree
func _initialize():
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://models/lada_2106.glb"), st)
	var scene := doc.generate_scene(st)
	var all := scene.find_children("*", "MeshInstance3D", true, false)
	print("мешей: ", all.size())
	var o := scene.find_child("Object_12", true, false) as MeshInstance3D
	var arrays := o.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx = arrays[Mesh.ARRAY_INDEX]
	print("verts ", verts.size(), " idx type ", typeof(idx), " size ", (idx.size() if idx != null else -1))
	var hits := 0
	for t in range(0, idx.size(), 3):
		var c: Vector3 = (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
		if absf(c.x) > 56.0 and Vector2(c.y + 96.28, c.z + 23.63).length() < 23.5:
			hits += 1
	print("треугольников в зоне колеса: ", hits, " из ", idx.size() / 3)
	print("names: ", all.map(func(n): return n.name).slice(0, 8))
	quit()
