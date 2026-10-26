extends SceneTree

# Разгон с полным газом и переключением на 5500 об/мин: время до 60/100 км/ч,
# по каждой передаче — обороты, момент, сопротивления.
var f := 0
var main: Node
var t := 0.0
var marks := {}
var last_print := 0.0
var last_shift := 0.0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	var vd: VehicleDynamics = sim.drivetrain.vehicle
	if f == 3:
		main.set_drive_mode(true)
		main.car.place(5.0)
		main.hud.start_cranking()
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	if f == 120:
		vd.request_gear(2)
		t = 0.0
	if f > 120:
		t += d
		main.hud.hand_throttle = 1.0
		var v: float = main.car.speed_kmh()
		if sim.rpm() > 5400.0 and vd.gear >= 2 and vd.gear < EngineSpecs.GEAR_RATIOS.size() - 1 and vd.shift_timer <= 0.0 and t - last_shift > 1.0:
			last_shift = t
			print("  переключение на %s при %.0f км/ч" % [EngineSpecs.GEAR_NAMES[vd.gear + 1], v])
			vd.request_gear(vd.gear + 1)
		for m in [60.0, 100.0, 120.0]:
			if v >= m and not marks.has(m):
				marks[m] = t
				print("%.0f км/ч за %.1f с" % [m, t])
		if t - last_print > 1.0:
			last_print = t
			print("t %.0f с: %.0f км/ч, передача %s, %.0f об/мин, момент %.0f Н·м, дроссель %.2f, разрежение %.0f кПа, λ %.2f, сцепл. %.2f" % [t, v, vd.gear_name(), sim.rpm(), sim.torque_avg, sim.carb.primary_angle_deg, sim.manifold_vacuum_kpa(), sim.lambda_avg, vd.clutch_engagement()])
		if t > 40.0:
			print("макс. за 60 с: %.0f км/ч" % v)
			return true
	return false
