extends SceneTree

# Проверка заезда без окна:
#   godot --headless --path . --script res://tests/drive_test.gd --fixed-fps 60
var f := 0
var main: Node
var vd: VehicleDynamics
var stage := 0
var t_stage := 0
var peak_travel := 0.0
var peak_load := 0.0
var max_speed := 0.0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _log(tag: String) -> void:
	var car: Car = main.car
	print("%-24s t=%5.1f с  %5.1f км/ч  %s  %4.0f об/мин  сцепл %.2f  крен %+.1f°  тангаж %+.1f°  ходы %+.0f/%+.0f/%+.0f/%+.0f мм  нагрузки %.0f/%.0f/%.0f/%.0f" % [
		tag, f / 60.0, car.speed_kmh(), vd.gear_name(), main.sim.rpm(), vd.clutch_engagement(), car.roll_deg(), car.pitch_deg(),
		(Car.REST_LEN - car.susp_len[0]) * 1000.0, (Car.REST_LEN - car.susp_len[1]) * 1000.0, (Car.REST_LEN - car.susp_len[2]) * 1000.0, (Car.REST_LEN - car.susp_len[3]) * 1000.0,
		car.tire_force[0], car.tire_force[1], car.tire_force[2], car.tire_force[3]])


func _next(s: int) -> void:
	stage = s
	t_stage = 0


func _process(_d: float) -> bool:
	f += 1
	t_stage += 1
	if f == 3:
		main.set_drive_mode(true)
		vd = main.sim.drivetrain.vehicle
		_next(1)
		return false
	if stage == 0:
		return false
	var car: Car = main.car
	max_speed = maxf(max_speed, car.speed_kmh())
	match stage:
		1:
			if t_stage == 30:
				main.hud.start_cranking()
			if t_stage > 30 and main.sim.rpm() > 750.0 and t_stage > 60:
				main.hud.stop_cranking()
				_log("завёлся")
				_next(2)
			if t_stage > 400:
				print("НЕ ЗАВЁЛСЯ")
				return true
		2:
			if t_stage == 60:
				vd.request_gear(2)
			if t_stage == 80:
				main.hud.hand_throttle = 0.45
			if t_stage == 260:
				_log("трогание, 1-я")
				main.hud.hand_throttle = 0.0
				vd.request_gear(3)
			if t_stage == 290:
				main.hud.hand_throttle = 0.8
			if t_stage == 500:
				_log("2-я")
				main.hud.hand_throttle = 0.0
				vd.request_gear(4)
			if t_stage == 530:
				main.hud.hand_throttle = 0.8
			if t_stage == 800:
				_log("3-я")
				main.hud.hand_throttle = 0.0
				vd.request_gear(5)
			if t_stage == 830:
				main.hud.hand_throttle = 0.6
			if t_stage == 1100:
				_log("4-я")
				main.hud.hand_throttle = 0.3
				car.place(280.0)
				car.linear_velocity = -car.global_basis.z * 8.33
				for i in 4:
					vd.wheel_omega[i] = 8.33 / EngineSpecs.WHEEL_RADIUS
				vd.request_gear(3)
				_next(3)
		3:
			var d := -car.global_position.z
			for i in 4:
				peak_travel = maxf(peak_travel, absf(Car.REST_LEN - car.susp_len[i]))
				peak_load = maxf(peak_load, car.tire_force[i])
			if d > 298.0 and d < 304.0 and t_stage % 3 == 0:
				_log("  лежачий полицейский")
			if d > 345.0:
				_log("после лежачих")
				print("наибольший ход подвески %.0f мм, наибольшая нагрузка на колесо %.0f Н" % [peak_travel * 1000.0, peak_load])
				_next(4)
		4:
			vd.brake = 1.0
			if t_stage == 240:
				_log("остановка тормозом")
				var ok := car.global_basis.y.y > 0.9 and not is_nan(car.global_position.y)
				print("максимальная скорость %.0f км/ч, кузов в норме: %s" % [max_speed, ok])
				return true
	return false
