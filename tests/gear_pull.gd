extends SceneTree

# Тяга на ровном асфальте: стартуем с заданной скоростью на передаче, полный газ,
# меряем ускорение и силы.
var f := 0
var main: Node
var stage := 0
var t := 0.0
var v0 := 0.0
const CASES := [[4, 40.0], [5, 60.0], [5, 90.0], [3, 30.0]]   # индекс передачи (3 — 2-я, 4 — 3-я, 5 — 4-я), км/ч

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _launch(gear: int, kmh: float) -> void:
	var car: Car = main.car
	var vd: VehicleDynamics = main.sim.drivetrain.vehicle
	car.place(1455.0)
	var v := kmh / 3.6
	car.linear_velocity = -car.global_basis.z * v
	vd.gear = gear
	vd.requested_gear = gear
	vd.shift_timer = 0.0
	for i in 4:
		vd.wheel_omega[i] = v / EngineSpecs.WHEEL_RADIUS
	main.sim.omega = v / EngineSpecs.WHEEL_RADIUS * vd.ratio()

func _process(d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	if f == 3:
		main.set_drive_mode(true)
		main.hud.start_cranking()
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	if f < 150:
		return false
	if stage >= CASES.size():
		return true
	var c: Array = CASES[stage]
	if t == 0.0:
		_launch(c[0], c[1])
		v0 = c[1]
	main.hud.hand_throttle = 1.0
	t += d
	if t > 4.0:
		var car: Car = main.car
		var vd: VehicleDynamics = sim.drivetrain.vehicle
		var v: float = car.speed_kmh()
		var fx := vd.fx_avg
		print("передача %s, %.0f→%.0f км/ч за 4 с: ускорение %.2f м/с², %.0f об/мин, момент %.0f Н·м, сцепл. проск. %.0f об/мин, Fx колёс %.0f/%.0f/%.0f/%.0f Н, воздух %.0f Н" % [vd.gear_name(), v0, v, (v - v0) / 3.6 / 4.0, sim.rpm(), sim.torque_avg, vd.clutch_slip * 60.0 / TAU, fx[0], fx[1], fx[2], fx[3], pow(v / 3.6, 2) * 0.6 * EngineSpecs.DRAG_AREA])
		stage += 1
		t = 0.0
	return false
