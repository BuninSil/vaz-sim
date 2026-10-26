extends SceneTree

# Сенсорное управление: включаем экранные кнопки, выезжаем, заводим стартером,
# жмём газ и руль пальцами одновременно — машина должна поехать и повернуть.
var f := 0
var main: Node


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


# Касания приходят в координатах окна; без окна оно крошечное, а интерфейс растянут.
func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _touch(idx: int, p: Vector2, on: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = _win(p)
	e.pressed = on
	Input.parse_input_event(e)


func _drag(idx: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = _win(p)
	Input.parse_input_event(e)


func _process(_d: float) -> bool:
	f += 1
	var tc: TouchControls = main.touch
	if f == 3:
		main.hud.touch_check.button_pressed = true
		main.set_drive_mode(true)
		main.car.place(30.0)
		print("кнопки видны: ", tc.visible, ", площадок: ", tc._pads.size())
	if f == 10:
		_touch(0, tc._rect("crank").get_center(), true)
	if f > 10 and f < 200 and main.sim.rpm() > 900.0 and main.sim.electrical.key == 2:
		_touch(0, tc._rect("crank").get_center(), false)
		print("завёлся на кадре ", f, ", обороты ", int(main.sim.rpm()))
	if f == 220:
		_touch(1, tc._rect("gear_up").get_center(), true)
		_touch(1, tc._rect("gear_up").get_center(), false)
	if f == 250:
		var r: Rect2 = tc._rect("throttle")
		_touch(2, r.get_center(), true)
		_drag(2, r.position + Vector2(r.size.x * 0.5, 4))
		var s: Rect2 = tc._rect("steer")
		_touch(3, s.get_center(), true)
		_drag(3, Vector2(s.end.x - 4, s.get_center().y))
	if f == 260:
		print("газ ", snappedf(tc.throttle, 0.01), ", руль ", snappedf(tc.steer, 0.01), ", педаль ", snappedf(main.sim.carb.pedal, 0.01), ", передача ", main.sim.drivetrain.vehicle.gear, "→", main.sim.drivetrain.vehicle.requested_gear)
	if f == 500:
		print("скорость через 4 с: ", snappedf(main.car.speed_kmh(), 0.1), " км/ч, руль ", snappedf(main.car.steer_input, 0.01))
		_touch(2, Vector2.ZERO, false)
		_touch(3, Vector2.ZERO, false)
		var b: Rect2 = tc._rect("brake")
		_touch(4, b.get_center(), true)
	if f == 520:
		print("после отпускания: газ ", tc.throttle, ", руль ", tc.steer, ", тормоз ", tc.brake, ", тормоз машины ", snappedf(main.sim.drivetrain.vehicle.brake, 0.01))
		return true
	return false
