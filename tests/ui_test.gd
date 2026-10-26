extends SceneTree

# Обход всего интерфейса: каждую кнопку нажимаем, ползунки двигаем, флажки
# переключаем, списки перебираем. После каждого действия сверяем, что изменилось
# то, за что элемент отвечает (по снимку состояния модели и сцены).
#   godot --path . --script res://tests/ui_test.gd --fixed-fps 60

var main: Node
var f := 0
var queue: Array = []        # [описание, Callable действия]
var current := ""
var before := {}
var results: Array = []
var dead: Array = []


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


# Снимок всего, что может изменить элемент интерфейса.
func _state() -> Dictionary:
	var sim: EngineSim = main.sim
	var hud: Hud = main.hud
	var d := {
		"key": sim.electrical.key, "choke": sim.carb.choke, "hand": hud.hand_throttle, "pedal": sim.carb.pedal,
		"heat": sim.thermal.heat_speedup, "time": hud.time_scale, "adv": sim.ignition.initial_advance_deg,
		"idle_screw": sim.carb.idle_speed_screw, "mix_screw": sim.carb.idle_mixture_screw, "clear": sim.valve_clearance_extra,
		"dwell": sim.ignition.dwell_fraction, "octane": sim.fuel_octane, "t_cool": snappedf(sim.thermal.t_coolant, 0.1),
		"xray": MeshUtil.material("cast_iron").transparency, "mode": sim.drivetrain.mode, "dyno_t": sim.drivetrain.dyno_torque,
		"hold": sim.drivetrain.dyno_hold_rpm, "target": sim.drivetrain.dyno_target_rpm, "gear": sim.drivetrain.gear,
		"clutch": sim.drivetrain.clutch, "brake": sim.drivetrain.brake, "slope": sim.drivetrain.slope, "lights": sim.electrical.headlights,
		"faults": str(hud.faults), "gap": sim.ignition.plug_gap_mm[0], "vac_ok": sim.ignition.vacuum_unit_ok, "cf_ok": sim.ignition.centrifugal_ok,
		"leak": sim.carb.vacuum_leak_area, "idle_clog": sim.carb.idle_jet_clog, "main_clog": sim.carb.main_jet_clog, "pump_ok": sim.carb.accel_pump_ok,
		"ex_clog": sim.exhaust_clog, "rings": "%f%f%f%f" % [sim.cylinders[0].ring_wear, sim.cylinders[1].ring_wear, sim.cylinders[2].ring_wear, sim.cylinders[3].ring_wear],
		"burnt": sim.cylinders[2].valve_burnt, "coolant": sim.thermal.coolant_level, "oil": sim.thermal.oil_level, "soc": snappedf(sim.electrical.soc, 0.001),
		"yaw": snappedf(main.rig._goal_yaw, 0.01), "dist": snappedf(main.rig._goal_distance, 0.01), "follow_yaw": main.rig.follow_auto_yaw,
		"tabs": hud.tabs.visible, "gauges": hud.gauge_row.visible, "info": hud.info_panel.visible, "scale": hud.ui_scale,
		"phi": snappedf(main._view_phi, 0.001), "removed": main._removed_stack.size(), "queue": main._queue.size(),
		"sweep": main._sweep_active, "drive": main.drive_mode, "msg": hud.message_label.text,
		"auto_clutch": sim.drivetrain.vehicle.auto_clutch,
		"car_xray": main.car.body_model.xray if main.car != null else false,
		"car_pos": snappedf(-main.car.global_position.z, 1.0) if main.car != null else 0.0,
	}
	return d


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is BaseButton or c is HSlider or c is OptionButton:
			out.append(c)
		_collect(c, out)


func _label(c: Control) -> String:
	if c is Button and (c as Button).text != "":
		return (c as Button).text
	var p := c.get_parent()
	for s in p.get_children():
		if s is Label:
			return (s as Label).text
	return c.name


func _plan_tab(tab_index: int) -> void:
	var hud: Hud = main.hud
	var tab_name := hud.tabs.get_tab_title(tab_index)
	queue.append(["вкладка " + tab_name, func() -> void: hud.tabs.current_tab = tab_index])
	var controls: Array = []
	_collect(hud.tabs.get_tab_control(tab_index), controls)
	for c in controls:
		var ctrl: Control = c
		var name := "%s → %s" % [tab_name, _label(ctrl)]
		if ctrl is OptionButton:
			var ob := ctrl as OptionButton
			for i in range(ob.item_count - 1, -1, -1):
				var ii := i
				queue.append([name + " = " + ob.get_item_text(i), func() -> void:
					ob.select(ii)
					ob.item_selected.emit(ii)
				])
		elif ctrl is HSlider:
			var s := ctrl as HSlider
			queue.append([name + " (вправо)", func() -> void: s.value = s.max_value])
			queue.append([name + " (влево)", func() -> void: s.value = s.min_value])
		elif ctrl is CheckBox:
			var cb := ctrl as CheckBox
			queue.append([name + " (вкл/выкл)", func() -> void: cb.button_pressed = not cb.button_pressed])
		elif ctrl is Button:
			var b := ctrl as Button
			if b.text.begins_with("▶") or b.text.begins_with("■"):
				continue   # выезд на трассу проверяется отдельно
			if b.text == "Стартер":
				queue.append([name, func() -> void: b.button_down.emit()])
				queue.append([name + " (отпустить)", func() -> void: b.button_up.emit()])
			elif b.toggle_mode:
				queue.append([name, func() -> void:
					b.button_pressed = true
					b.pressed.emit()
				])
			else:
				queue.append([name, func() -> void: b.pressed.emit()])


func _process(_d: float) -> bool:
	f += 1
	if f == 5:
		var hud: Hud = main.hud
		# Панель инструментов.
		for b in hud.toolbar.get_children():
			var btn := b as Button
			queue.append(["панель → " + btn.text, func() -> void:
				if btn.toggle_mode:
					btn.button_pressed = not btn.button_pressed
				else:
					btn.pressed.emit()
			])
			if btn.toggle_mode:
				queue.append(["панель → " + btn.text + " (вернуть)", func() -> void: btn.button_pressed = not btn.button_pressed])
		# Заводим двигатель, чтобы проверять и то, что требует работающего мотора.
		queue.append(["пуск двигателя", func() -> void: main.hud.start_cranking()])
		for t in hud.tabs.get_tab_count():
			if hud.tabs.get_tab_title(t) == "Заезд":
				continue
			_plan_tab(t)
		# Выбор детали и её снятие/установка из вкладки «Разборка».
		queue.append(["выбор детали «Крышка клапанов»", func() -> void: main._select(main.model.get_part("valve_cover"))])
		var parts_tab := hud.tabs.get_tab_count() - 1
		queue.append(["Разборка → Снять", func() -> void: hud.btn_remove.pressed.emit()])
		queue.append(["Разборка → Установить", func() -> void: hud.btn_install.pressed.emit()])
		# Затем трасса.
		queue.append(["Заезд → ▶ Выехать на трассу", func() -> void: hud.drive_button.pressed.emit()])
		for t in hud.tabs.get_tab_count():
			if hud.tabs.get_tab_title(t) == "Заезд":
				_plan_tab(t)
		queue.append(["Заезд → ■ Вернуть на стенд", func() -> void: hud.drive_button.pressed.emit()])
		return false
	if f < 6:
		return false
	# Через каждые 8 кадров: сверяем результат прошлого действия и выполняем следующее.
	if (f - 6) % 8 != 0:
		return false
	if current != "":
		var after := _state()
		var changed := []
		for k in after:
			if str(after[k]) != str(before[k]) and k != "msg" and k != "t_cool" and k != "soc" and k != "pedal":
				changed.append(k)
		var msg_changed: bool = str(after["msg"]) != str(before["msg"])
		var ok := not changed.is_empty() or msg_changed
		results.append([current, ok, changed, after["msg"] if msg_changed else ""])
		if not ok:
			dead.append(current)
	if queue.is_empty():
		print("\n===== ИТОГ: проверено %d действий, без видимого эффекта: %d" % [results.size(), dead.size()])
		for r in results:
			print(("  ok   " if r[1] else "  НЕТ  ") + r[0] + ("   [" + ", ".join(r[2]) + "]" if not r[2].is_empty() else "") + ("   «" + str(r[3]).left(70) + "»" if str(r[3]) != "" else ""))
		return true
	var item: Array = queue.pop_front()
	current = item[0]
	before = _state()
	print("→ ", current)
	(item[1] as Callable).call()
	return false
