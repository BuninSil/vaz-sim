extends SceneTree
# Крупный план фар ночью: ближний и дальний.
var f := 0
var main: Node
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	match f:
		5:
			main.set_drive_mode(true)
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			main.hud.gauge_row.visible = false
			main.rig.follow_auto_yaw = false
			main.rig._goal_yaw = PI + 0.35
			main.rig._goal_pitch = 0.1
			main.rig._goal_distance = 3.2
		10:
			main._set_daytime(1)
			main._set_lights(2)
		90: root.get_texture().get_image().save_png("res://screenshots/25_fary_blizhniy.png")
		91: main._set_lights(3)
		130:
			root.get_texture().get_image().save_png("res://screenshots/26_fary_dalniy.png")
			return true
	return false
