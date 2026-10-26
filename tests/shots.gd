extends SceneTree
# Снимает скриншоты основных режимов: godot --path . --script res://tests/shots.gd
var f := 0
var main: Node
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("res://screenshots/%s.png" % name)
	print("снимок ", name)
func _process(_d: float) -> bool:
	f += 1
	match f:
		40: shot("01_obshiy_vid")
		50: main.hud.start_cranking()
		150: print("прокрутка: ", main.sim.rpm(), " λ ", main.sim.cylinders[0].trapped_lambda)
		260: print("после пуска: ", main.sim.rpm(), " реальное время ×", main.real_factor)
		200: main.hud.stop_cranking()
		230: main.hud.hand_throttle = 0.35
		400:
			main.hud.tabs.current_tab = 3
			shot("02_rabota_grafiki")
		410:
			main.hud.hand_throttle = 0.0
			MeshUtil.set_xray(true)
			main.rig.set_view("Спереди (привод ГРМ)")
			main.hud.tabs.current_tab = 0
		520: shot("03_rentgen_grm")
		530:
			MeshUtil.set_xray(false)
			main.rig.set_view("Общий вид")
			main.sim.electrical.key = 0
		620:
			main._select(main.model.get_part("valve_cover"))
			for id in ["air_filter_lid", "air_filter_element", "air_filter_housing", "valve_cover"]:
				main._remove(main.model.get_part(id))
		660:
			main._remove(main.model.get_part("cylinder_head"))
			main._select(main.model.get_part("cylinder_head"))
		700: shot("04_blokirovka_razborki")
		710: main._disassemble_all()
		1600:
			main.rig.set_view("Общий вид")
			main.rig._goal_distance = 2.2
		1700:
			main._select(main.model.get_part("piston_assy_1"))
			shot("05_razobran")
			return true
	return false
