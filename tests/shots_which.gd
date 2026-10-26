extends SceneTree

# Поочерёдно прячет группы узлов кузова, чтобы понять, чья деталь торчит у задней арки.
var f := 0
var main: Node
var cam: Camera3D
var groups := []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _pt(cm: Vector3) -> Vector3:
	var bm: CarBodyModel = main.car.body_model
	return bm.global_transform * (bm._model_xf * cm)

func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		main.set_drive_mode(true)
		main.hud.tabs.visible = false
		main.hud.info_panel.visible = false
		main.hud.gauge_row.visible = false
	if f == 40:
		cam = Camera3D.new()
		root.add_child(cam)
		cam.current = true
		cam.fov = 25.0
		cam.global_position = _pt(Vector3(-250, -60, -15))
		cam.look_at(_pt(Vector3(-70, -75, -22)), Vector3.UP)
		var bm: CarBodyModel = main.car.body_model
		for c in bm.find_children("*", "MeshInstance3D", true, false):
			if bm.model_root.is_ancestor_of(c) or String(c.name).begins_with("Object"):
				groups.append(c)
	if f >= 40:
		var i := (f - 40) / 10
		if i > groups.size():
			return true
		if (f - 40) % 10 == 0:
			for k in groups.size():
				(groups[k] as Node3D).visible = k != i - 1
		if (f - 40) % 10 == 9:
			root.get_texture().get_image().save_png("res://screenshots/_which_%d.png" % i)
			print(i, " спрятан: ", "ничего" if i == 0 else str(groups[i - 1].name) + " " + groups[i - 1].get_class() + " детей " + str(groups[i - 1].get_child_count()))
	return false
