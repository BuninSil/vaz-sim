extends SceneTree

# Внешняя характеристика каждого мотора на балансирной машине против паспорта.
func _initialize() -> void:
	for id in EngineSpecs.ENGINES:
		EngineSpecs.apply_engine(id)
		var sim := EngineSim.new()
		sim.set_seed(7)
		sim.reset(363.15)
		sim.drivetrain.mode = Drivetrain.Mode.DYNO
		sim.drivetrain.dyno_hold_rpm = true
		sim.electrical.key = 1
		sim.carb.pedal = 1.0
		var best_t := 0.0
		var best_t_rpm := 0.0
		var best_p := 0.0
		var best_p_rpm := 0.0
		var r := 1500.0
		while r <= EngineSpecs.REDLINE_RPM + 400.0:
			sim.drivetrain.dyno_target_rpm = r
			sim.omega = r * TAU / 60.0
			for k in 50:
				sim.advance(0.01)
			var t := 0.0
			var p := 0.0
			for k in 30:
				sim.advance(0.01)
				t += sim.torque_avg
				p += sim.power_avg
			t /= 30.0
			p /= 30.0
			if t > best_t:
				best_t = t
				best_t_rpm = r
			if p > best_p:
				best_p = p
				best_p_rpm = r
			r += 250.0
		print("%s: момент %.0f Н·м при %.0f (паспорт %.0f при %.0f), мощность %.1f кВт = %.0f л.с. при %.0f (паспорт %.0f л.с. при %.0f)" % [id, best_t, best_t_rpm, EngineSpecs.MAX_TORQUE_NM, EngineSpecs.MAX_TORQUE_RPM, best_p / 1000.0, best_p / 735.5, best_p_rpm, EngineSpecs.RATED_POWER_KW * 1.36, EngineSpecs.RATED_POWER_RPM])
	quit()
