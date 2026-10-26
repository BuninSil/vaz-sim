extends SceneTree

# Вперёд → тормоз до остановки → задний ход → тормоз → снова вперёд. Всё клавишами.
var f := 0
var main: Node
var phase := ""

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _tap(k: Key) -> void:
	_key(k, true)
	_key(k, false)

func _process(_d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	if f == 3:
		main.set_drive_mode(true)
		main.car.place(30.0)
		main.hud.start_cranking()
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	var vd: VehicleDynamics = sim.drivetrain.vehicle
	match f:
		120: _tap(KEY_E)                    # 1-я
		140: _key(KEY_W, true); phase = "вперёд"
		320: _key(KEY_W, false); _key(KEY_S, true); phase = "тормоз"
		480: _key(KEY_S, false); _tap(KEY_Q); phase = "Q"
		500: _tap(KEY_Q); phase = "Q2"
		520: _key(KEY_W, true); phase = "назад газ"
		700: _key(KEY_W, false); _key(KEY_S, true); phase = "тормоз2"
		860: _key(KEY_S, false); _tap(KEY_E)
		880: _tap(KEY_E)
		900: _key(KEY_W, true); phase = "снова вперёд"
		1080:
			_key(KEY_W, false)
			return true
	if (f % 30 == 0 and f > 110) or (f > 520 and f < 640 and f % 6 == 0):
		print("%4d %-12s %+6.1f км/ч передача %s об/мин %.0f сцепл %.2f педаль %.2f тормоз %.2f λ %.2f p_вп %.0f кПа насос %.4f плёнка %.3f г возд %.1f топл %.2f г/с дросс %.0f°" % [f, phase, main.car.speed_kmh(), vd.gear_name(), sim.rpm(), vd.clutch_engagement(), sim.carb.pedal, vd.brake, sim.lambda_avg, sim.im_p / 1000.0, sim.carb._pump_fuel_pending * 1000.0, sim.im_film * 1000.0, sim.carb.air_flow * 1000.0, sim.carb.fuel_flow * 1000.0, sim.carb.primary_angle_deg])
	return false
