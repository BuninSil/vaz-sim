extends SceneTree

# 1) Машина стоит на тормозе — не должно быть раскачки.
# 2) Кузов приподнимают и отпускают — меряем частоту собственных колебаний.
var f := 0
var main: Node
var vd: VehicleDynamics
var acc: Array[float] = []
var heights: Array[float] = []


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _physics_process(_d: float) -> bool:
	if main.car == null:
		return false
	var car: Car = main.car
	if f > 120 and f < 300:
		acc.append(-car.accel_g.z)
	if f > 330 and f < 600:
		heights.append(car.global_position.y)
	return false


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		main.set_drive_mode(true)
		vd = main.sim.drivetrain.vehicle
		main.car.place(10.0)
		main.hud.start_cranking()
	if f == 100:
		main.hud.stop_cranking()
	if f > 3 and f < 320:
		vd.brake = 1.0
	if f == 300:
		var lo := 99.0
		var hi := -99.0
		var mean := 0.0
		for a in acc:
			lo = minf(lo, a)
			hi = maxf(hi, a)
			mean += a
		print("на тормозе: продольное ускорение от %+.4f до %+.4f g, скорость %.3f км/ч, об/мин %.0f" % [lo, hi, main.car.speed_kmh(), main.sim.rpm()])
	if f == 330:
		# Подбрасываем кузов на 6 см и отпускаем.
		var car: Car = main.car
		car.global_position += Vector3(0, 0.06, 0)
		car.linear_velocity = Vector3.ZERO
	if f == 600:
		# Частота по пересечениям средней линии.
		var mean_h := 0.0
		for h in heights:
			mean_h += h
		mean_h /= heights.size()
		var crossings: Array[int] = []
		for i in range(1, heights.size()):
			if (heights[i - 1] - mean_h) * (heights[i] - mean_h) < 0.0:
				crossings.append(i)
		if crossings.size() >= 3:
			var period := float(crossings[2] - crossings[0]) / Engine.physics_ticks_per_second
			print("собственная частота кузова ≈ %.2f Гц (период %.2f с), пересечений за 4,5 с: %d" % [1.0 / period, period, crossings.size()])
		else:
			print("колебаний почти нет (пересечений %d) — сильно задемпфировано" % crossings.size())
		return true
	return false
