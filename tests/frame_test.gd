extends SceneTree

# Разгон на трассе с записью длительности каждого кадра, числа шагов физики
# за кадр и времени видеокарты — ищем, откуда рывки.
var f := 0
var main: Node
var vd: VehicleDynamics
var frames: Array = []
var phys_ticks := 0
var last_us := 0
var recording := false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _physics_process(_d: float) -> bool:
	phys_ticks += 1
	return false


func _process(_d: float) -> bool:
	f += 1
	var now := Time.get_ticks_usec()
	if recording:
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
		frames.append([(now - last_us) / 1000.0, phys_ticks, main.sim.rpm(), main.car.speed_kmh(), gpu, cpu, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	phys_ticks = 0
	last_us = now
	match f:
		3:
			RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
			main.set_drive_mode(true)
			vd = main.sim.drivetrain.vehicle
			main.car.place(1460.0)
			main.hud.start_cranking()
		150:
			main.hud.stop_cranking()
		170: vd.request_gear(2)
		190:
			main.hud.hand_throttle = 1.0
			recording = true
		400:
			main.hud.hand_throttle = 0.0
			vd.request_gear(3)
		420: main.hud.hand_throttle = 1.0
		700:
			recording = false
			var worst := 0.0
			var hitches := 0
			for i in frames.size():
				var fr: Array = frames[i]
				worst = maxf(worst, fr[0])
				if fr[0] > 40.0:
					hitches += 1
				if i % 15 == 0:
					print("кадр %5.1f мс  шагов физики %d  %4.0f об/мин  %5.1f км/ч  видеокарта %5.1f мс  отрисовка ЦП %5.1f мс  физика %5.1f мс" % fr)
			var avg := 0.0
			for fr in frames:
				avg += fr[0]
			avg /= frames.size()
			print("средний кадр %.1f мс (%.0f к/с), худший %.1f мс, кадров дольше 40 мс: %d из %d" % [avg, 1000.0 / avg, worst, hitches, frames.size()])
			return true
	return false
