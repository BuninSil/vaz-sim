extends SceneTree
# Загружает главную сцену без окна, прогоняет кадры, пуск и разборку.
var frames := 0
var main: Node
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(delta: float) -> bool:
	frames += 1
	if frames == 5:
		print("частей: ", main.model.part_order.size())
		main.hud.start_cranking()
	if frames == 120:
		main.hud.stop_cranking()
		print("обороты после пуска: ", main.sim.rpm())
	if frames == 200:
		main.hud.stop_cranking()
		main.sim.electrical.key = 0
	if frames == 320:
		print("обороты после выключения: ", main.sim.rpm())
		main._disassemble_all()
	if frames == 320 + 160 * 12:
		print("снято: ", main._removed_stack.size(), " из ", main.model.part_order.size() - 1)
		for p in main.model.part_order:
			if not p.removed and p != main.model.block:
				var bl := []
				for b in main.model.blocking_parts(p):
					bl.append(b.id)
				print("  не снято: ", p.id, " мешают: ", bl, " отсоединена с узлом: ", p.is_detached())
		main._assemble_all()
	if frames == 320 + 160 * 24:
		print("осталось снятых: ", main._removed_stack.size())
		return true
	return false
