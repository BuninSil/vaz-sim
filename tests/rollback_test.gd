extends SceneTree

# Откат и смена направления: машина катится вперёд 0,5 км/ч, включён задний — должна уехать назад;
# катится назад, включена первая — должна уехать вперёд. И проверка тряски на тормозе.
var f := 0
var main: Node

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	var car: Car = main.car
	if f == 3:
		main.set_drive_mode(true)
		main.car.place(30.0)
		main.hud.start_cranking()
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	var vd: VehicleDynamics = sim.drivetrain.vehicle
	if f == 150 or f == 450:
		var v := 0.15 if f == 150 else -0.15
		car.linear_velocity = -car.global_basis.z * v
		for i in 4:
			vd.wheel_omega[i] = v / EngineSpecs.WHEEL_RADIUS
		vd.request_gear(0 if f == 150 else 2)
	if (f > 170 and f < 400) or (f > 470 and f < 700):
		main.hud.hand_throttle = 0.6
	else:
		main.hud.hand_throttle = 0.0
	if f == 400 or f == 700:
		print("%s: скорость %+.1f км/ч, колёса %+.1f рад/с, передача %s" % ["задний после отката вперёд" if f == 400 else "первая после отката назад", car.speed_kmh(), vd.wheel_omega[2], vd.gear_name()])
		vd.request_gear(1)
	if f == 720:
		return true
	return false
