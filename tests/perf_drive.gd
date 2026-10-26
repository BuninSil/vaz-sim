extends SceneTree
# Замер производительности в режиме трассы (с окном).
var f := 0
var main: Node
var t0 := 0
var frames := 0
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _count(n: Node) -> int:
	var c := 1 if n is MeshInstance3D or n is CSGShape3D else 0
	for ch in n.get_children():
		c += _count(ch)
	return c
func _process(_d: float) -> bool:
	f += 1
	var vd: VehicleDynamics = main.sim.drivetrain.vehicle
	match f:
		5:
			print("мешей в двигателе: ", _count(main.model))
			main.set_drive_mode(true)
		10: print("мешей в машине: ", _count(main.car), ", в дороге: ", _count(main.road))
		20: main.hud.start_cranking()
		170: main.hud.stop_cranking()
		200: vd.request_gear(2)
		220: main.hud.hand_throttle = 0.4
		300:
			t0 = Time.get_ticks_usec()
			frames = 0
		590:
			var fns := {
				"hud.refresh": func(): main.hud.refresh(0.016, 1.0, ""),
				"hud.refresh_drive": func(): main.hud.refresh_drive(main.car),
				"hud.refresh_graphs": func(): main.hud.refresh_graphs(),
				"model.update_view": func(): main.model.update_view(main.sim, main.sim.phi, 0.016),
				"body.update_pose": func(): main.car.body_model.update_pose(),
				"apply_part_states": func(): main._apply_part_states(),
				"sim.advance(1/120)": func(): main.sim.advance(1.0 / 120.0),
			}
			for k in fns:
				var a := Time.get_ticks_usec()
				for i in 5:
					fns[k].call()
				print("  %-22s %.2f мс" % [k, (Time.get_ticks_usec() - a) / 5000.0])
			var a3 := Time.get_ticks_usec()
			for i in 5:
				main._process(0.016)
			print("  %-22s %.2f мс" % ["main._process целиком", (Time.get_ticks_usec() - a3) / 5000.0])
			var a4 := Time.get_ticks_usec()
			for i in 5:
				main.car._physics_process(1.0 / 60.0)
			print("  %-22s %.2f мс" % ["car._physics_process", (Time.get_ticks_usec() - a4) / 5000.0])
			var a5 := Time.get_ticks_usec()
			for i in 5:
				for g in [main.hud.tacho, main.hud.g_coolant, main.hud.g_oil]:
					g._process(0.016)
				main.rig._process(0.016)
			print("  %-22s %.2f мс" % ["приборы+камера", (Time.get_ticks_usec() - a5) / 5000.0])
			var a2 := Time.get_ticks_usec()
			main.audio.feed(main.sim, 0.016)
			print("  %-22s %.2f мс" % ["audio.feed", (Time.get_ticks_usec() - a2) / 1000.0])
		600:
			var dt := (Time.get_ticks_usec() - t0) / 1e6
			print("кадров в секунду: %.1f, об/мин %.0f, физика %.2f мс, процесс %.2f мс, отрисовка объектов %d, вызовов %d" % [frames / dt, main.sim.rpm(),
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
			return true
	frames += 1
	return false
