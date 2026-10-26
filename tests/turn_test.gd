extends SceneTree
# Резкий поворот на скорости: не должно вставать на два колеса.
var f := 0
var main: Node
var vd: VehicleDynamics
var min_load := [1e9, 1e9, 1e9, 1e9]
var max_roll := 0.0
var max_lat := 0.0
var phase := ""
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _report(tag: String) -> void:
	print("%s: крен до %.1f°, поперечное до %.2f g, наименьшие нагрузки ЛП %.0f ПП %.0f ЛЗ %.0f ПЗ %.0f Н, скорость %.0f км/ч" % [tag, max_roll, max_lat, min_load[0], min_load[1], min_load[2], min_load[3], main.car.speed_kmh()])
	max_roll = 0.0
	max_lat = 0.0
	min_load = [1e9, 1e9, 1e9, 1e9]
func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
func _process(_d: float) -> bool:
	f += 1
	if main.car != null and f > 10:
		var car: Car = main.car
		for i in 4:
			min_load[i] = minf(min_load[i], car.tire_force[i])
		if f > 200 and f < 320 and f % 6 == 0:
			print("  t=%.2f руль %.1f° крен %+.1f° поперечн %.2f g  нагрузки %4.0f %4.0f %4.0f %4.0f  ходы %+3.0f %+3.0f %+3.0f %+3.0f мм  увод %+.1f %+.1f %+.1f %+.1f" % [(f - 200) / 60.0, rad_to_deg(car.steer), car.roll_deg(), car.accel_g.x, car.tire_force[0], car.tire_force[1], car.tire_force[2], car.tire_force[3], (Car.REST_LEN - car.susp_len[0]) * 1000, (Car.REST_LEN - car.susp_len[1]) * 1000, (Car.REST_LEN - car.susp_len[2]) * 1000, (Car.REST_LEN - car.susp_len[3]) * 1000, rad_to_deg(car.slip_angle[0]), rad_to_deg(car.slip_angle[1]), rad_to_deg(car.slip_angle[2]), rad_to_deg(car.slip_angle[3])])
		max_roll = maxf(max_roll, absf(car.roll_deg()))
		max_lat = maxf(max_lat, absf(car.accel_g.x))
	match f:
		3:
			main.set_drive_mode(true)
			vd = main.sim.drivetrain.vehicle
			main.car.place(1460.0, 0.0)
			main.hud.start_cranking()
		150: main.hud.stop_cranking()
		160:
			# Разгоняем машину сразу до 70 км/ч на 4-й передаче.
			var car: Car = main.car
			car.linear_velocity = -car.global_basis.z * 19.5
			for i in 4:
				vd.wheel_omega[i] = 19.5 / EngineSpecs.WHEEL_RADIUS
			vd.request_gear(5)
			main.hud.hand_throttle = 0.35
		200: _report("прямо")
		201: _key(KEY_D, true)
		320:
			_report("руль до упора вправо на 70 км/ч")
			_key(KEY_D, false)
			_key(KEY_A, true)
		440:
			_report("перекладка влево")
			_key(KEY_A, false)
			return true
	return false
