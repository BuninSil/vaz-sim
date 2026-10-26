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
		main._reset_engine(5.0, 5.0)
		main.set_drive_mode(true)
		main.hud.choke_slider.value = 1.0
		main.hud.start_cranking()
	if sim.electrical.key == 2 and sim.rpm() > 950.0:
		main.hud.stop_cranking()
	if f % 15 == 0:
		print("%d об/мин %.0f ключ %d подсос %.2f λ %.2f ток стартера %.0f U %.1f" % [f, sim.rpm(), sim.electrical.key, sim.carb.choke, sim.lambda_avg, sim.electrical.starter_current, sim.electrical.voltage])
	return f > 600
