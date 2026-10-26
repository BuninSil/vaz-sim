extends SceneTree
func _init():
	var sim := EngineSim.new()
	sim.reset(363.0)
	sim.electrical.key = 2
	var caught := 0.0
	for i in 600:
		sim.advance(1.0/60.0)
		if sim.electrical.key == 2:
			caught = caught + 1.0/60.0 if sim.rpm() > 650.0 else 0.0
			if caught > 0.25 or i > 300: sim.electrical.key = 1
		if i % 20 == 0:
			var c = sim.cylinders[0]
			print("t=%.2f key=%d rpm=%4.0f pim=%5.1f air=%.2f fuel=%.3f AFRsup=%.1f λ=%.2f/%.2f/%.2f/%.2f res=%.2f mis=%s%s%s%s Tq=%.1f" % [i/60.0, sim.electrical.key, sim.rpm(), sim.im_p/1000, sim.carb.air_flow*1000, sim.carb.fuel_flow*1000, sim.carb.air_flow/maxf(sim.carb.fuel_flow,1e-9), sim.cylinders[0].trapped_lambda, sim.cylinders[1].trapped_lambda, sim.cylinders[2].trapped_lambda, sim.cylinders[3].trapped_lambda, c.residual, int(sim.cylinders[0].last_misfire), int(sim.cylinders[1].last_misfire), int(sim.cylinders[2].last_misfire), int(sim.cylinders[3].last_misfire), sim.torque_avg])
	quit()
