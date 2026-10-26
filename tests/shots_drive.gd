extends SceneTree
# Скриншоты режима трассы.
var f := 0
var main: Node
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % name)
	print("снимок ", name)
func _process(_d: float) -> bool:
	f += 1
	var vd: VehicleDynamics = main.sim.drivetrain.vehicle
	match f:
		5: main.set_drive_mode(true)
		20:
			main.hud.tabs.current_tab = 1
			main.hud.start_cranking()
		170: main.hud.stop_cranking()
		200: vd.request_gear(2)
		220: main.hud.hand_throttle = 0.5
		330:
			main.hud.hand_throttle = 0.0
			vd.request_gear(3)
		350: main.hud.hand_throttle = 0.6
		420: shot("06_trassa_razgon")
		430:
			main.car.place(284.0)
			main.car.linear_velocity = -main.car.global_basis.z * 7.0
			for i in 4:
				vd.wheel_omega[i] = 7.0 / EngineSpecs.WHEEL_RADIUS
			main.hud.hand_throttle = 0.3
			main.rig.follow_auto_yaw = false
			main.rig._goal_yaw = PI * 0.5 + 0.3
			main.rig._goal_pitch = -0.12
			main.rig._goal_distance = 5.5
			main.car.body_model.set_xray(true)
		560: shot("07_lezhachiy_rentgen")
		570:
			main.car.body_model.set_xray(false)
			main.rig._goal_yaw = -0.6
			main.rig._goal_pitch = -0.2
			main.rig._goal_distance = 7.0
		640: shot("08_vid_speredi")
		650:
			main.car.place(660.0, 0.0)
			main.car.linear_velocity = -main.car.global_basis.z * 5.0
			for i in 4:
				vd.wheel_omega[i] = 5.0 / EngineSpecs.WHEEL_RADIUS
			main.rig._goal_yaw = 2.6
			main.rig._goal_distance = 6.0
		780:
			shot("09_diagonal")
			return true
	return false
