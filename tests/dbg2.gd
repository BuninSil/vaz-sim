extends SceneTree
func _init():
	var sim := EngineSim.new()
	sim.reset(363.0)
	sim.thermal.heat_speedup = 0.0
	sim.electrical.key = 1
	sim.drivetrain.mode = Drivetrain.Mode.DYNO
	sim.drivetrain.dyno_hold_rpm = true
	sim.carb.pedal = 1.0
	for rpm in [1000.0, 3400.0]:
		sim.omega = rpm * TAU / 60.0
		sim.drivetrain.dyno_target_rpm = rpm
		for i in 60: sim.advance(1.0/60.0)
		var c = sim.cylinders[0]
		var last := -1
		var guard := 0
		print("--- %d rpm, pim %.1f" % [rpm, sim.im_p/1000])
		while guard < 200000:
			sim._step(minf(1.2e-4, 0.5 * PI / 180.0 / sim.omega))
			guard += 1
			var d := int(rad_to_deg(c.local))
			if d % 10 == 0 and d != last and (d >= 120 and d <= 260):
				last = d
				var rm = c.r_air + c.r_fuel + c.r_burned
				print("  %3d° lift_i=%.1fmm lift_e=%.1fmm p=%.1f kPa p_run=%.1f q=%.4f m=%.3fg T=%.0f" % [d, c.intake_lift*1000, c.exhaust_lift*1000, c.p/1000, rm*287.0*c.r_t/(EngineSim.RUNNER_AREA*EngineSim.RUNNER_LENGTH)/1000, c.runner_flow, (c.m_air+c.m_fuel+c.m_burned)*1000, c.t])
			if last >= 260: break
	quit()

