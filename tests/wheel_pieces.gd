extends SceneTree
var f := 0
var main: Node
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		main.set_drive_mode(true)
	if f == 10:
		for n in main.car.body_model.find_children("*_wheel*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			print(mi.name, " aabb ", mi.mesh.get_aabb())
		return true
	return false
