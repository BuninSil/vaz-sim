extends SceneTree

# Полный газ в нейтрали на прогретом моторе: где упрутся обороты.
func _initialize() -> void:
	for id in ["2103", "2106", "2106s"]:
		EngineSpecs.apply_engine(id)
		var sim := EngineSim.new()
		sim.reset(363.15, 293.15)
		sim.electrical.key = 2
		var t := 0.0
		var peak := 0.0
		var line := ""
		while t < 9.0:
			var dt := 1.0 / 60.0
			if sim.electrical.key == 2 and sim.rpm() > 900.0:
				sim.electrical.key = 1
			if t > 2.0:
				sim.carb.pedal = 1.0
			sim.carb.update_controls(dt, sim.rpm())
			sim.advance(dt)
			sim.publish()
			t += dt
			peak = maxf(peak, sim.rpm())
			if int(t * 60.0) % 60 == 0:
				line += " %.0f" % sim.rpm()
		print("%s: пик %.0f, по секундам%s, цепь %s, шатун %s, ηv %.2f, поплавок %.2f" % [id, peak, line, sim.timing_broken, sim.rod_failure, sim.volumetric_efficiency, sim.valve_float])
	quit()
