extends SceneTree

# Пуск и сразу резкий газ: не должен глохнуть. Холодный и прогретый мотор, полный и частичный газ.
func _run(t_c: float, choke: float, pedal: float, delay: float) -> String:
	var sim := EngineSim.new()
	sim.reset(t_c + 273.15, 293.15)
	sim.carb.choke = choke
	sim.electrical.key = 2
	var t := 0.0
	var caught := -1.0
	var minr := 99999.0
	var log := ""
	while t < 8.0:
		var dt := 1.0 / 60.0
		if sim.electrical.key == 2 and sim.rpm() > 900.0:
			sim.electrical.key = 1
			caught = t
		if sim.electrical.key == 2 and t > 5.0:
			return "не завёлся"
		if caught > 0.0 and t > caught + delay:
			sim.carb.pedal = pedal
			minr = minf(minr, sim.rpm())
			if int((t - caught - delay) * 60.0) % 12 == 0 and t - caught - delay < 1.2:
				log += " %.0f(λ%.2f)" % [sim.rpm(), sim.lambda_avg]
		sim.carb.update_controls(dt, sim.rpm())
		sim.advance(dt)
		sim.publish()
		t += dt
	return "мин %.0f, итог %.0f об/мин;%s" % [minr, sim.rpm(), log]

func _initialize() -> void:
	for cfg in [[90.0, 0.0, 1.0, 0.3], [90.0, 0.0, 0.4, 0.3], [90.0, 0.0, 1.0, 1.5], [20.0, 0.6, 1.0, 0.5], [20.0, 0.6, 0.4, 0.5]]:
		print("%.0f °C подсос %.1f газ %.1f через %.1f с: %s" % [cfg[0], cfg[1], cfg[2], cfg[3], _run(cfg[0], cfg[1], cfg[2], cfg[3])])
	quit()
