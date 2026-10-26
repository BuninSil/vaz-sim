extends SceneTree
func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://models/lada_2106.glb"), st)
	var scene := doc.generate_scene(st)
	for n in scene.find_children("Object_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
		print(mi.name, " ", m.resource_name, " tr=", m.transparency, " col=", m.albedo_color, " tex=", m.albedo_texture != null, " aabb=", mi.mesh.get_aabb().size)
	quit()
