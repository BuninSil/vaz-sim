extends SceneTree
var f := 0
var main: Node
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	if f == 10:
		main.hover_enabled = false
		main.hud.start_cranking()
	if f == 140:
		main.hud.stop_cranking()
	if f == 200:
		var size := DisplayServer.window_get_size()
		root.get_texture().get_image().save_png("res://screenshots/ui_%dx%d.png" % [size.x, size.y])
		return true
	return false
