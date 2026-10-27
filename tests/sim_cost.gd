extends SceneTree

# Цена расчёта двигателя: сколько миллисекунд процессора уходит на секунду модели.
func _initialize() -> void:
	var sim := EngineSim.new()
	sim.set_seed(7)
	sim.reset(363.15)
	sim.drivetrain.mode = Drivetrain.Mode.DYNO
	sim.drivetrain.dyno_hold_rpm = true
	sim.electrical.key = 1
	for pair in [[900.0, 0.0], [3000.0, 0.5], [5500.0, 1.0]]:
		sim.drivetrain.dyno_target_rpm = pair[0]
		sim.carb.pedal = pair[1]
		sim.omega = pair[0] * TAU / 60.0
		for k in 30:
			sim.advance(1.0 / 60.0)
		var steps := 0
		var t0 := Time.get_ticks_usec()
		for k in 60:
			steps += sim.advance(1.0 / 60.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("%5.0f об/мин: %6.1f мс на секунду модели, шагов %d, %.1f мкс на шаг" % [sim.rpm(), ms, steps, ms * 1000.0 / steps])
	quit()
