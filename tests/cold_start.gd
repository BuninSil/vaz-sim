extends SceneTree

# Холодный пуск и прогрев при разных положениях подсоса.
func _initialize() -> void:
	for amb in [20.0, 5.0, -10.0]:
		for choke in [0.6, 1.0]:
			var sim := EngineSim.new()
			sim.reset(amb + 273.15, amb + 273.15)
			if amb < 0.0:
				sim.electrical.soc = 0.75
			sim.carb.choke = choke
			sim.electrical.key = 2
			var t := 0.0
			var caught := -1.0
			var rpm_sum := 0.0
			var lam_sum := 0.0
			var n := 0
			while t < 25.0:
				sim.advance(1.0 / 60.0)
				sim.publish()
				t += 1.0 / 60.0
				if sim.electrical.key == 2 and sim.rpm() > 950.0:
					sim.electrical.key = 1
					caught = t
				if sim.electrical.key == 2 and t > 6.0:
					break
				if caught > 0.0 and t > caught + 5.0:
					rpm_sum += sim.rpm()
					lam_sum += sim.lambda_avg
					n += 1
			var tail := "" if n == 0 else ", после пуска %.0f об/мин, λ %.2f" % [rpm_sum / n, lam_sum / n]
			print("%+.0f °C, подсос %.1f: %s%s" % [amb, choke, ("завёлся за %.1f с" % caught) if caught > 0.0 else "не завёлся", tail])
	quit()
