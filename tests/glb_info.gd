extends SceneTree

func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://models/lada_2106.glb"), st)
	var root_node := doc.generate_scene(st)
	_walk(root_node, 0, Transform3D.IDENTITY)
	quit()

func _walk(n: Node, depth: int, xf: Transform3D) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	var line := "  ".repeat(depth) + n.name + " (" + n.get_class() + ")"
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var aabb := t * mi.mesh.get_aabb()
		line += " surf %d aabb %s" % [mi.mesh.get_surface_count(), aabb]
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			line += " [%s v%d]" % [m.resource_name if m else "-", mi.mesh.surface_get_array_len(i)]
	print(line)
	for c in n.get_children():
		_walk(c, depth + 1, t)
