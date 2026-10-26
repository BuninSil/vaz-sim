extends SceneTree
var f := 0
var main: Node
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	if f == 3:
		if OS.get_environment("DRV") != "0": main.set_drive_mode(true)
		if main.car: main.car.threaded = OS.get_environment("THR") != "0"
		main.hud.start_cranking()
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	if f % 10 == 0:
		var mis := 0
		for c in sim.cylinders:
			mis += 1 if c.last_misfire else 0
		print("поплавк %.2f топл %.2f г/с возд %.1f г/с плёнка %.3f г насос %s фильтр %.2f | " % [sim.carb.bowl_level, sim.carb.fuel_flow * 1000.0, sim.carb.air_flow * 1000.0, sim.im_film * 1000.0, sim.carb.fuel_supply_ok, sim.carb.air_filter_clog], "%3d об/мин %4.0f ключ %d λ %.2f пропуски %d дроссель %.1f° педаль %.2f подсос %.2f t ОЖ %.0f цепь %s клин %s вода %s нагр %.1f" % [f, sim.rpm(), sim.electrical.key, sim.lambda_avg, mis, sim.carb.primary_angle_deg, sim.carb.pedal, sim.carb.choke, sim.thermal.t_coolant - 273.15, sim.timing_broken, sim.seized, sim.drivetrain.mode, sim.drivetrain.load_torque])
	return f > 200
