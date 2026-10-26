extends SceneTree

# Кадры кинорежима: за машиной, из салона, кинокамера; день, вечер, ночь.
var f := 0
var main: Node
var t0 := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % name)
	print("снимок ", name, " %.0f км/ч" % main.car.speed_kmh())

func _process(_d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	var vd: VehicleDynamics = sim.drivetrain.vehicle
	match f:
		3:
			main.set_drive_mode(true)
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			main.hud.gauge_row.visible = false
			main.hud.start_cranking()
		100:
			vd.request_gear(2)
	if f > 110:
		main.hud.hand_throttle = 0.7
		if f == 260: vd.request_gear(3)
		if f == 420: vd.request_gear(4)
	match f:
		300: _shot("60_kino_za_mashinoy")
		301: main.rig.set_mode(1)
		340: _shot("61_kino_iz_salona")
		341: main.rig.set_mode(2)
		400: _shot("62_kino_kamera_1")
		470: _shot("63_kino_kamera_2")
		540: _shot("64_kino_kamera_3")
		541:
			main._set_daytime(1)
			main._set_lights(1)
			main.rig.set_mode(0)
		600: _shot("65_kino_vecher")
		601:
			main._set_daytime(2)
			main._set_lights(2)
		660: _shot("66_kino_noch")
		661: main.rig.set_mode(1)
		700:
			_shot("67_kino_noch_salon")
			return true
	return false
