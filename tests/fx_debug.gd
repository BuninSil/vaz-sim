extends SceneTree

var f := 0
var main: Node

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _process(_d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	if f == 3:
		main.set_drive_mode(true)
		main.hud.start_cranking()
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	var vd: VehicleDynamics = sim.drivetrain.vehicle
	if f == 150:
		vd.request_gear(2)
	if f > 150 and f < 600:
		main.hud.hand_throttle = 1.0
		if f == 330:
			vd.request_gear(3)
		if f == 420: _key(KEY_D, true)
		if f == 450: _key(KEY_CTRL, true)
		if f == 520: _key(KEY_CTRL, false)
	if f % 20 == 0 and f > 150:
		var fx: CarEffects = main.effects
		print("%d %.0f км/ч slip %s угол %s дым %.2f %.2f %.2f %.2f контакт %s" % [f, main.car.speed_kmh(), vd.slip, main.car.slip_angle, fx._tire_smoke[0].amount_ratio, fx._tire_smoke[1].amount_ratio, fx._tire_smoke[2].amount_ratio, fx._tire_smoke[3].amount_ratio, main.car.contact])
	return f > 600
