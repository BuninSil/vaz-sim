extends SceneTree
var f := 0
var main: Node
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	match f:
		5:
			main.set_drive_mode(true)
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			main.hud.gauge_row.visible = false
			main.rig.follow_auto_yaw = false
			main.rig._goal_yaw = 0.25
			main.rig._goal_pitch = 0.12
			main.rig._goal_distance = 3.4
		70:
			root.get_texture().get_image().save_png("res://screenshots/24_zad_vykl.png")
			var lens := main.car.body_model.model_root.find_child("Object_16", true, false) as MeshInstance3D
			print("линза: поверхностей ", lens.mesh.get_surface_count(), " override ", lens.get_surface_override_material(0))
			for c in lens.get_parent().get_children():
				if String(c.name).begins_with("Lamp_"):
					var m := (c as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
					print(c.name, " прозр ", m.transparency, " альфа ", m.albedo_color.a, " шерох ", m.roughness, " текстура ", m.albedo_texture != null)
			return true
	return false
