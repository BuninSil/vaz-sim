extends SceneTree

# Снимки: открытые двери, капот (виден двигатель), багажник; перекраска в «Гараже».
var f := 0
var main: Node


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % name)
	print("снимок ", name, " открыто: ", main.car.body_model.openings.keys().filter(func(k): return main.car.body_model.is_open(k)))


func _view(yaw: float, pitch: float, dist: float) -> void:
	main.rig.follow_auto_yaw = false
	main.rig._goal_yaw = yaw
	main.rig._goal_pitch = pitch
	main.rig._goal_distance = dist


func _process(_d: float) -> bool:
	f += 1
	match f:
		3:
			main.set_drive_mode(true)
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			main.hud.gauge_row.visible = false
			print("панели: ", main.car.body_model.openings.keys())
			_view(PI + 0.75, -0.2, 6.5)
		20:
			for n in ["door_fl", "door_rl", "door_fr", "door_rr", "hood"]:
				main.hud.request_opening.emit(n)
		110:
			_shot("40_dveri_kapot")
			_view(0.6, -0.25, 6.5)
			main.hud.request_opening.emit("trunk")
		200:
			_shot("41_bagazhnik")
			for n in ["door_fl", "door_rl", "door_fr", "door_rr", "hood", "trunk"]:
				main.hud.request_opening.emit(n)
			main.hud.request_garage.emit("paint", 1)
			main.hud.request_garage.emit("metallic", true)
			main.hud.request_garage.emit("tint", 0.7)
			main.hud.request_garage.emit("ride_height", -0.04)
			_view(PI + 0.9, -0.12, 6.0)
		320:
			_shot("42_garazh_korrida")
			main.hud.request_garage.emit("paint", 5)
			main.hud.request_garage.emit("metallic", false)
			main.hud.request_garage.emit("tint", 0.0)
			main.hud.request_garage.emit("ride_height", 0.04)
		420:
			_shot("43_garazh_adriatika")
			return true
	return false
