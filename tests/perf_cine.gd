extends SceneTree

# Замер кадров в секунду при езде для трёх уровней графики.
var f := 0
var main: Node
var acc := {}

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(d: float) -> bool:
	f += 1
	var sim: EngineSim = main.sim
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	var vd: VehicleDynamics = sim.drivetrain.vehicle
	if f == 3:
		main.set_drive_mode(true)
		main.hud.start_cranking()
	if f == 100: vd.request_gear(2)
	if f > 110: main.hud.hand_throttle = 0.7
	if f == 260: vd.request_gear(3)
	for q in 3:
		var a := 300 + q * 300
		if f == a:
			main.cinematic.set_quality(q)
		if f > a + 60 and f < a + 300:
			if not acc.has(q): acc[q] = []
			acc[q].append(d)
	if f == 1200:
		for q in acc:
			var arr: Array = acc[q]
			arr.sort()
			var mean := 0.0
			for x in arr: mean += x
			mean /= arr.size()
			print("графика %d: средний кадр %.1f мс (%.0f к/с), худший 5%% %.1f мс" % [q, mean * 1000.0, 1.0 / mean, arr[int(arr.size() * 0.95)] * 1000.0])
		return true
	return false
