extends SceneTree

# Нагрузка на отрисовку на трассе: объекты, вызовы, треугольники — по слоям сцены.
var f := 0
var main: Node


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _stats(tag: String) -> void:
	print("%-28s объектов %5d  вызовов %5d  треугольников %8d" % [tag,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		if "--touch" in OS.get_cmdline_user_args():
			main.hud.setup_mobile()
		main._setup_lite()
		main.set_drive_mode(true)
	if f == 12:
		_stats("всё")
		main.road.visible = false
	if f == 15:
		_stats("без дороги и растений")
		main.road.visible = true
		main.car.visible = false
	if f == 18:
		_stats("без машины")
		main.car.visible = true
		main.sun.shadow_enabled = false
	if f == 21:
		_stats("без теней солнца")
		return true
	return false
