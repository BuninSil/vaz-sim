extends SceneTree
func _try(mode: int, warm: float) -> String:
	var sim := EngineSim.new()
	sim.reset(warm + 273.15, 293.15)
	sim.drivetrain.mode = mode
	sim.electrical.key = 2
	var t := 0.0
	while t < 4.0:
		if sim.electrical.key == 2 and sim.rpm() > 950.0:
			sim.electrical.key = 1
			return "завёлся за %.1f с" % t
		sim.carb.update_controls(1.0 / 60.0, sim.rpm())
		sim.advance(1.0 / 60.0)
		sim.publish()
		t += 1.0 / 60.0
	return "не завёлся, %.0f об/мин λ %.2f" % [sim.rpm(), sim.lambda_avg]
func _initialize() -> void:
	for m in [Drivetrain.Mode.FREE, Drivetrain.Mode.ROAD]:
		for w in [90.0, 20.0]:
			print("режим %d, %.0f °C: %s" % [m, w, _try(m, w)])
	quit()
