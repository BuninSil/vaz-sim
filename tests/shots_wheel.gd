extends SceneTree
# Крупный план колеса на ходу: колпак должен вращаться вместе с колесом.
var f := 0
var main: Node
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	var vd: VehicleDynamics = main.sim.drivetrain.vehicle
	match f:
		5: main.set_drive_mode(true)
		20:
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			main.hud.gauge_row.visible = false
			main.rig.follow_auto_yaw = false
			main.rig._goal_yaw = PI * 0.5
			main.rig._goal_pitch = -0.08
			main.rig._goal_distance = 3.2
		60:
			for w in 4:
				var names := []
				for n in main.car.body_model.wheel_spin_nodes[w].get_children():
					names.append(n.name)
				print("колесо ", w, ": ", names)
			var o12 := main.car.body_model.model_root.find_child("Object_12", true, false) as MeshInstance3D
			if o12 != null:
				print("Object_12 aabb ", o12.mesh.get_aabb(), " поверхностей ", o12.mesh.get_surface_count())
		90:
			main.car.body_model.wheel_spin_nodes[0].rotation.x = 0.0
			root.get_texture().get_image().save_png("res://screenshots/17_koleso_a.png")
		91:
			main.car.wheel_spin[0] = 0.8
			main.car.wheel_spin[2] = 0.8
		95:
			root.get_texture().get_image().save_png("res://screenshots/18_koleso_b.png")
			return true
	return false
