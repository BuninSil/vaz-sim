extends SceneTree

# Снимки спецэффектов: пар из трубы холодного мотора, сизый дым, дым из-под
# колёс и следы юза, брызги на мокром участке, пыль на обочине, пар из-под капота.
var f := 0
var main: Node
var shots := {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % name)
	var fx: CarEffects = main.effects
	print("снимок ", name, " об/мин %.0f, %.0f км/ч, выхлоп %.2f %s" % [main.sim.rpm(), main.car.speed_kmh(), fx._exhaust.amount_ratio, fx._exhaust_mat.color])


func _view(yaw: float, pitch: float, dist: float) -> void:
	main.rig.follow_auto_yaw = false
	main.rig._goal_yaw = yaw
	main.rig._goal_pitch = pitch
	main.rig._goal_distance = dist


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


# Разгоняет машину сразу до скорости v (м/с) на передаче gear.
func _launch(v: float, gear: int) -> void:
	var car: Car = main.car
	var vd: VehicleDynamics = main.sim.drivetrain.vehicle
	vd.gear = gear
	vd.requested_gear = gear
	car.linear_velocity = -car.global_basis.z * v
	for i in 4:
		vd.wheel_omega[i] = v / EngineSpecs.WHEEL_RADIUS
	main.sim.omega = v / EngineSpecs.WHEEL_RADIUS * vd.ratio()


func _crank() -> void:
	main.hud.start_cranking()


func _process(_d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	# Стартер держим, пока мотор не схватит (не дольше 4 с).
	if sim.electrical.key == 2:
		if sim.rpm() > 950.0 or f - int(shots.get("crank", 0)) > 240:
			main.hud.stop_cranking()
	var vd: VehicleDynamics = sim.drivetrain.vehicle
	match f:
		3:
			main._reset_engine(5.0, 5.0)
			main.set_drive_mode(true)
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			main.hud.gauge_row.visible = false
			main.hud.choke_slider.value = 1.0
			shots["crank"] = f
			_crank()
			_view(0.25, -0.05, 4.5)
		300:
			_shot("30_fx_holodnyy_vyhlop")
			main.hud.choke_slider.value = 0.0
			main._reset_engine(90.0, 20.0)
			for c in sim.cylinders:
				c.ring_wear = 0.7
			shots["crank"] = f
			_crank()
		480:
			_shot("31_fx_sizyy_dym")
			for c in sim.cylinders:
				c.ring_wear = 0.0
			vd.request_gear(2)
			_view(0.6, -0.2, 6.0)
	# Занос с ручником на скорости 60 км/ч.
	if f == 490:
		_launch(17.0, 4)
	if f > 490 and f < 720:
		main.hud.hand_throttle = 0.4
	if f == 520:
		_key(KEY_D, true)
		_key(KEY_CTRL, true)
	if f == 600:
		_shot("33_fx_dym_shin")
	if f == 640:
		_key(KEY_D, false)
		_key(KEY_CTRL, false)
	if f == 720:
		main.hud.hand_throttle = 0.0
		_view(1.2, -0.75, 9.0)
	if f == 800:
		_shot("34_fx_sledy_yuza")
		main.car.place(1300.0)   # мокрый асфальт
		_view(0.35, -0.12, 6.0)
	if f == 805:
		_launch(16.0, 3)
	if f > 805 and f < 980:
		main.hud.hand_throttle = 0.8
	if f == 900:
		_shot("35_fx_bryzgi")
		main.car.place(40.0, 7.5)   # обочина
	if f == 905:
		_launch(13.0, 3)
	if f > 905 and f < 1100:
		main.hud.hand_throttle = 0.8
	if f == 1000:
		_shot("36_fx_pyl")
		main.hud.hand_throttle = 0.0
		main.car.place(30.0)
		sim.thermal.t_coolant = 391.0
		_view(PI - 0.6, -0.25, 5.0)
	if f == 1100:
		_shot("32_fx_par_iz_pod_kapota")
		return true
	return false
