extends SceneTree

# Проверка модели без графики:
#   godot --headless --path . --script res://tests/sim_test.gd
# Сверяет обороты холостого хода, внешнюю скоростную характеристику и пуск
# с паспортными данными ВАЗ-2103.

var failures := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_test_warm_start_and_idle()
	_test_cold_start()
	_test_full_load_curve()
	_test_performance()
	print("Всего %.1f с, ошибок: %d" % [(Time.get_ticks_msec() - t0) / 1000.0, failures])
	quit(1 if failures > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + text)
	if not ok:
		failures += 1


func _run(sim: EngineSim, seconds: float, frame := 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		sim.advance(frame)
		t += frame


func _crank_until_start(sim: EngineSim, limit: float) -> float:
	sim.electrical.key = 2
	var t := 0.0
	var caught := 0.0
	while t < limit:
		sim.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		# Как водитель: держим ключ, пока двигатель не подхватит уверенно.
		caught = caught + 1.0 / 60.0 if sim.rpm() > 650.0 else 0.0
		if caught > 0.25:
			break
	sim.electrical.key = 1
	return t


func _test_warm_start_and_idle() -> void:
	print("Тёплый пуск и холостой ход")
	var sim := EngineSim.new()
	sim.reset(363.0)
	sim.electrical.key = 2
	var crank_rpm := 0.0
	for i in 30:
		sim.advance(1.0 / 60.0)
		crank_rpm = maxf(crank_rpm, sim.rpm())
	print("    прокрутка стартером: %.0f об/мин, напряжение %.1f В, ток стартера %.0f А" % [sim.rpm(), sim.electrical.voltage, sim.electrical.starter_current])
	var t := _crank_until_start(sim, 4.0)
	_check(sim.rpm() > 500.0, "заводится за %.2f с" % t)
	_run(sim, 6.0)
	var rpm_sum := 0.0
	var samples := 0
	for i in 120:
		sim.advance(1.0 / 60.0)
		rpm_sum += sim.rpm()
		samples += 1
	var idle := rpm_sum / samples
	print("    ХХ %.0f об/мин, разрежение %.1f кПа, λ %.2f, масло %.2f бар, %.2f л/ч, напряжение %.1f В, опережение %.1f°" % [idle, sim.manifold_vacuum_kpa(), sim.lambda_avg, sim.thermal.oil_pressure / 1e5, sim.fuel_consumption_lph(), sim.electrical.voltage, sim.ignition.advance_deg])
	for c in sim.cylinders:
		print("      цил %d: λ %.2f, ост.газы %.2f, Pmax %.1f бар, IMEP %.2f бар, пропуск %s" % [c.index + 1, c.trapped_lambda, c.residual, c.peak_pressure / 1e5, c.imep / 1e5, c.last_misfire])
	_check(idle > 700.0 and idle < 1000.0, "обороты ХХ в пределах 700..1000")
	_check(sim.manifold_vacuum_kpa() > 45.0, "разрежение на ХХ больше 45 кПа")
	_check(sim.thermal.oil_pressure > 0.5e5, "давление масла на ХХ не ниже 0,5 бар")


func _test_cold_start() -> void:
	print("Холодный пуск (+20 °C)")
	var sim := EngineSim.new()
	sim.reset(293.0)
	sim.carb.choke = 0.0
	var t := _crank_until_start(sim, 3.0)
	print("    без подсоса: %s (%.1f с, %.0f об/мин)" % ["завёлся" if sim.rpm() > 500 else "не завёлся", t, sim.rpm()])
	sim = EngineSim.new()
	sim.reset(293.0)
	sim.carb.choke = 0.8
	t = _crank_until_start(sim, 4.0)
	_run(sim, 4.0)
	_check(sim.rpm() > 600.0, "с подсосом заводится и работает: %.0f об/мин через 4 с (пуск за %.1f с), λ %.2f" % [sim.rpm(), t, sim.lambda_avg])


func _test_full_load_curve() -> void:
	print("Внешняя скоростная характеристика (полный дроссель, стенд)")
	var sim := EngineSim.new()
	sim.reset(363.0)
	sim.thermal.heat_speedup = 0.0
	sim.omega = 1000.0 * TAU / 60.0
	sim.electrical.key = 1
	sim.drivetrain.mode = Drivetrain.Mode.DYNO
	sim.drivetrain.dyno_hold_rpm = true
	sim.carb.pedal = 1.0
	var best_t := 0.0
	var best_t_rpm := 0.0
	var best_p := 0.0
	var best_p_rpm := 0.0
	var rpm := 1000.0
	while rpm <= 6000.0:
		sim.drivetrain.dyno_target_rpm = rpm
		_run(sim, 0.8)
		var tq := 0.0
		var pw := 0.0
		var n := 0
		var lam := 0.0
		var ve := 0.0
		for i in 36:
			sim.advance(1.0 / 60.0)
			tq += sim.torque_avg
			pw += sim.power_avg
			lam += sim.lambda_avg
			ve += sim.volumetric_efficiency
			n += 1
		tq /= n
		pw /= n
		var knock := 0.0
		for c in sim.cylinders:
			knock = maxf(knock, c.last_knock)
		print("    %4.0f об/мин: %5.1f Н·м  %4.1f кВт  λ %.2f  ηv %.2f  опер. %4.1f°  Pmax %4.1f бар  выпуск %3.0f °C  детон. %.2f  2-я камера %.2f" % [sim.rpm(), tq, pw / 1000.0, lam / n, ve / n, sim.ignition.advance_deg, sim.cylinders[0].peak_pressure / 1e5, sim.exhaust_temp - 273.15, knock, sim.carb.secondary_open])
		if tq > best_t:
			best_t = tq
			best_t_rpm = rpm
		if pw > best_p:
			best_p = pw
			best_p_rpm = rpm
		rpm += 500.0
	_check(absf(best_t - EngineSpecs.MAX_TORQUE_NM) < 12.0, "максимальный момент %.1f Н·м при %.0f (паспорт 104 при 3400)" % [best_t, best_t_rpm])
	_check(absf(best_p / 1000.0 - EngineSpecs.RATED_POWER_KW) < 6.0, "максимальная мощность %.1f кВт при %.0f (паспорт 52,9 при 5600)" % [best_p / 1000.0, best_p_rpm])


func _test_performance() -> void:
	print("Производительность")
	var sim := EngineSim.new()
	sim.reset(363.0)
	sim.omega = 6000.0 * TAU / 60.0
	sim.carb.pedal = 1.0
	sim.electrical.key = 1
	sim.drivetrain.mode = Drivetrain.Mode.DYNO
	sim.drivetrain.dyno_hold_rpm = true
	sim.drivetrain.dyno_target_rpm = 6000.0
	var t0 := Time.get_ticks_usec()
	var steps := 0
	for i in 60:
		steps += sim.advance(1.0 / 60.0)
	var real := (Time.get_ticks_usec() - t0) / 1e6
	print("    1 с при %.0f об/мин считалась %.2f с (%d шагов)" % [sim.rpm(), real, steps])
	_check(real < 0.8, "модель успевает в реальном времени на высоких оборотах")
