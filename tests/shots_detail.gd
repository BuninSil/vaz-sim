extends SceneTree
# Крупные планы деталей двигателя.
var f := 0
var main: Node
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % name)
	print("снимок ", name)
func view(yaw: float, pitch: float, dist: float, target: Vector3) -> void:
	main.rig._goal_yaw = yaw
	main.rig._goal_pitch = pitch
	main.rig._goal_distance = dist
	main.rig._goal_target = target
func rm(ids: Array) -> void:
	for id in ids:
		main._remove(main.model.get_part(id))
func _process(_d: float) -> bool:
	f += 1
	match f:
		5:
			main.hover_enabled = false
			main.hud.tabs.visible = false
			main.hud.info_panel.visible = false
			view(-0.9, -0.3, 0.95, Vector3(0, 0.15, 0))
		60: shot("10_detal_obshiy")
		61: view(0.4, -0.25, 0.8, Vector3(0, 0.25, 0.1))
		120: shot("11_detal_vpusk_vypusk")
		121: view(PI - 0.4, -0.25, 0.8, Vector3(-0.02, 0.18, -0.08))
		180: shot("12_detal_zazhiganie")
		181:
			rm(["air_filter_lid", "air_filter_element", "air_filter_housing", "valve_cover"])
			view(-0.5, -0.9, 0.6, Vector3(-0.05, 0.33, 0.0))
		260: shot("13_detal_grm_klapany")
		261:
			MeshUtil.set_xray(true)
			view(-1.45, -0.1, 0.75, Vector3(-0.22, 0.15, 0.0))
		320: shot("14_detal_cep_rentgen")
		321:
			MeshUtil.set_xray(false)
			rm(["oil_pan", "oil_pump"])
			view(-0.7, 0.75, 0.7, Vector3(0, 0.0, 0))
		400: shot("15_detal_kolenval_snizu")
		401:
			main.hud.tabs.visible = true
			main._disassemble_all()
		1300:
			view(-0.75, -0.75, 3.2, Vector3(0.2, -0.2, -0.4))
		1380:
			shot("16_detal_razobran")
			return true
	return false
