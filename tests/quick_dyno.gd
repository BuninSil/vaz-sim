extends SceneTree
func _initialize() -> void:
	var id: String = OS.get_environment("ENG") if OS.get_environment("ENG") != "" else "2103"
	EngineSpecs.apply_engine(id)
	var sim := EngineSim.new()
	sim.set_seed(7)
	sim.reset(363.15)
	sim.drivetrain.mode = Drivetrain.Mode.DYNO
	sim.drivetrain.dyno_hold_rpm = true
	sim.electrical.key = 1
	sim.carb.pedal = 1.0
	var line := id + ":"
	for r in [1500.0, 2500.0, 3500.0, 4500.0, 5000.0, 5600.0, 6000.0, 6500.0, 7000.0]:
		sim.drivetrain.dyno_target_rpm = r
		sim.omega = r * TAU / 60.0
		for k in 60:
			sim.advance(1.0 / 60.0)
		var t := 0.0
		var ve := 0.0
		var mp := 0.0
		for k in 30:
			sim.advance(1.0 / 60.0)
			t += sim.torque_avg
			ve += sim.volumetric_efficiency
			mp += sim.im_p
		var mis := 0
		for c in sim.cylinders:
			mis += 1 if c.last_misfire else 0
		line += "
  %.0f (факт %.0f): %.0f Нм ηv %.2f λ %.2f пропуски %d поплавок %.2f p_вп %.0f опер %.0f детон %.2f" % [r, sim.rpm(), t / 30.0, ve / 30.0, sim.lambda_avg, mis, sim.valve_float, mp / 30000.0, sim.ignition.advance_deg, sim.cylinders[0].last_knock]
	print(line)
	quit()
