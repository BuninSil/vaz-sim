extends SceneTree

# Проверка светотехники ночью: фары, габариты, стоп-сигналы, поворотники.
var f := 0
var main: Node


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % name)
	print("снимок ", name)


func _view(yaw: float, pitch: float, dist: float) -> void:
	main.rig.follow_auto_yaw = false
	main.rig._goal_yaw = yaw
	main.rig._goal_pitch = pitch
	main.rig._goal_distance = dist


func _process(_d: float) -> bool:
	f += 1
	var bm: CarBodyModel = main.car.body_model if main.car != null else null
	match f:
		5:
			main.set_drive_mode(true)
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			main.hud.gauge_row.visible = false
		10:
			var roles := []
			for k in main.car.body_model._lamp_mats:
				roles.append("%s×%d" % [k, (main.car.body_model._lamp_mats[k] as Array).size()])
			print("секции фонарей: ", roles)
			main._set_daytime(2)
			main._set_lights(2)
			_view(PI + 0.5, -0.12, 6.0)   # спереди-сбоку
		90: _shot("20_noch_blizhniy")
		91: main._set_lights(3)
		130: _shot("21_noch_dalniy")
		131:
			main._set_lights(1)
			main.sim.drivetrain.vehicle.brake = 1.0
			main._set_turn(-1)
			_view(0.35, -0.15, 5.5)       # сзади
		170: _shot("22_noch_stop_povorot")
		171:
			main._set_daytime(0)
			main._set_turn(0)
			bm.hazard = true
			_view(-0.5, -0.1, 5.0)
		215:
			_shot("23_den_avariyka")
			return true
	if f > 131 and f < 171:
		main.sim.drivetrain.vehicle.brake = 1.0
	return false
