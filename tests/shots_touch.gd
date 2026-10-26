extends SceneTree

# Снимки сенсорного интерфейса на «телефонном» экране: стенд и трасса.
# Запуск: godot --path . --resolution 2400x1080 --script res://tests/shots_touch.gd -- --touch [папка]
var f := 0
var main: Node
var out := "res://screenshots"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a != "--touch":
			out = a
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	var path := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(path)
	print("снимок: ", path)


func _process(_d: float) -> bool:
	f += 1
	if f == 10:
		main.hover_enabled = false
		main.hud.start_cranking()
	if f == 120:
		main.hud.stop_cranking()
	if f == 150:
		_shot("touch_stend")
	if f == 160:
		main.set_drive_mode(true)
	if f == 400:
		_shot("touch_trassa")
		(main.hud.toolbar.get_child(0) as Button).button_pressed = true
	if f == 420:
		_shot("touch_trassa_panel")
		return true
	return false
