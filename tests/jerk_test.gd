extends SceneTree
# Поиск продольных колебаний машины на ровной дороге.
var f := 0
var main: Node
var vd: VehicleDynamics
var log_on := false
var samples: Array = []
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _physics_process(_d: float) -> bool:
	if log_on:
		var car: Car = main.car
		samples.append([car.speed_kmh(), -car.accel_g.z, main.sim.rpm(), vd.clutch_engagement(), vd.wheel_omega[2] * EngineSpecs.WHEEL_RADIUS * 3.6, car.pitch_deg()])
	return false
func _process(_d: float) -> bool:
	f += 1
	match f:
		3:
			main.set_drive_mode(true)
			vd = main.sim.drivetrain.vehicle
			main.car.place(1460.0)
		20: main.hud.start_cranking()
		170: main.hud.stop_cranking()
		200: vd.request_gear(2)
		220: main.hud.hand_throttle = 0.35
		400:
			vd.request_gear(3)
		600:
			log_on = true
			main.hud.hand_throttle = 1.0
		660:
			main.hud.hand_throttle = 0.0
		720:
			log_on = false
			var amin := 99.0
			var amax := -99.0
			var sign_changes := 0
			var prev := 0.0
			for i in samples.size():
				var s: Array = samples[i]
				amin = minf(amin, s[1])
				amax = maxf(amax, s[1])
				if i > 0 and signf(s[1] - 0.0) != signf(prev):
					sign_changes += 1
				prev = s[1]
				if i % 3 == 0:
					print("%5.1f км/ч  a=%+.3f g  %4.0f об/мин  сцепл %.2f  колесо %5.1f км/ч  тангаж %+.2f°" % [s[0], s[1], s[2], s[3], s[4], s[5]])
			print("ускорение от %+.3f до %+.3f g, смен знака за 2 с: %d" % [amin, amax, sign_changes])
			return true
	return false
