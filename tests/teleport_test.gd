extends SceneTree

# Нажимает каждую кнопку «Перейти к участку» и проверяет, что машина и камера
# действительно оказались у начала участка.
var f := 0
var main: Node
var buttons: Array[Button] = []
var idx := 0
var wait := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _find(n: Node) -> void:
	for c in n.get_children():
		if c is Button:
			for z in Road.ZONES:
				if (c as Button).text == z[2]:
					buttons.append(c)
		_find(c)


func _process(_d: float) -> bool:
	f += 1
	if f == 5:
		main.set_drive_mode(true)
		var hud: Hud = main.hud
		for t in hud.tabs.get_tab_count():
			if hud.tabs.get_tab_title(t) == "Заезд":
				hud.tabs.current_tab = t
				_find(hud.tabs.get_tab_control(t))
		print("кнопок участков: ", buttons.size())
		return false
	if f < 40:
		return false
	if wait > 0:
		wait -= 1
		if wait == 0:
			var car: Car = main.car
			var b := buttons[idx]
			var zone_start := 0.0
			for z in Road.ZONES:
				if z[2] == b.text:
					zone_start = z[0]
			var d := -car.global_position.z
			var cam_d: float = -main.rig.camera.global_position.z
			var ok := absf(d - maxf(zone_start - 25.0, 0.0)) < 3.0 and absf(cam_d - d) < 15.0
			print("%s  %-28s машина %6.1f м  камера %6.1f м  ожидалось %6.1f" % ["ok  " if ok else "НЕТ ", b.text, d, cam_d, maxf(zone_start - 25.0, 0.0)])
			if idx == 6:
				root.get_texture().get_image().save_png("res://screenshots/19_teleport.png")
			idx += 1
		return false
	if idx >= buttons.size():
		return true
	# Нажатие, как мышью: сигнал pressed.
	buttons[idx].pressed.emit()
	wait = 45
	return false
