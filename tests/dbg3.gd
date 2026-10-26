extends SceneTree
func _init():
	var sim := EngineSim.new()
	sim.reset(363.0)
	sim.thermal.heat_speedup = 0.0
	sim.electrical.key = 1
	sim.drivetrain.mode = Drivetrain.Mode.DYNO
	sim.drivetrain.dyno_hold_rpm = true
	sim.carb.pedal = 1.0
	for rpm in [2000.0, 3400.0, 5500.0]:
		sim.omega = rpm * TAU / 60.0
		sim.drivetrain.dyno_target_rpm = rpm
		for i in 50: sim.advance(1.0/60.0)
		var pim := 0.0
		var pex := 0.0
		var pmin := 1e9
		var pmax := 0.0
		var n := 0
		for i in 20:
			sim.advance(1.0/60.0)
			pim += sim.im_p; pex += sim.ex_p; n += 1
		var c = sim.cylinders[0]
		print("%4d rpm: p_im %.1f kPa  p_ex %.1f kPa  air %.1f g/s  ve %.2f  res %.3f  trapped %.3f g  sec %.2f  prim %.0f°  filt drop %.1f kPa" % [rpm, pim/n/1000, pex/n/1000, sim.air_mass_rate*1000, sim.volumetric_efficiency, c.residual, c.trapped_air*1000, sim.carb.secondary_open, sim.carb.primary_angle_deg, Carburetor.AIR_FILTER_K*sim.carb.air_flow*sim.carb.air_flow/1000])
	quit()
