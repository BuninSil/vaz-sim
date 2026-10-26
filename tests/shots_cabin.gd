extends SceneTree

# Снимки салона собственной камерой (точки — в сантиметрах модели кузова).
var f := 0
var main: Node
var cam: Camera3D

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % name)
	print("снимок ", name)

func _pt(cm: Vector3) -> Vector3:
	var bm: CarBodyModel = main.car.body_model
	return bm.global_transform * (bm._model_xf * cm)

func _look(from_cm: Vector3, to_cm: Vector3, fov := 60.0) -> void:
	cam.fov = fov
	cam.global_position = _pt(from_cm)
	cam.look_at(_pt(to_cm), main.car.global_basis.y)

func _process(_d: float) -> bool:
	f += 1
	match f:
		3:
			main.set_drive_mode(true)
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			main.hud.gauge_row.visible = false
			main.hud.start_cranking()
			for n in ["door_fl", "door_rl"]:
				main.hud.request_opening.emit(n)
		120:
			main.hud.stop_cranking()
			main._set_lights(1)
			cam = Camera3D.new()
			root.add_child(cam)
			cam.current = true
			_look(Vector3(-37, 8, 52), Vector3(-30, 80, 22), 70.0)
		130:
			_shot("47_salon_voditel")
			_look(Vector3(-15, 48, 40), Vector3(-37, 78, 24), 45.0)
		140:
			_shot("48_pribory")
			_look(Vector3(-75, -15, 45), Vector3(-125, 62, 8), 60.0)
		150:
			_shot("49_dvernaya_karta")
			_look(Vector3(-150, -40, 50), Vector3(0, -60, 5), 60.0)
		160:
			_shot("50_zadniy_divan")
			_look(Vector3(-160, 140, 70), Vector3(0, 20, 10), 50.0)
		170:
			_shot("51_salon_snaruzhi")
			return true
	return false
