extends SceneTree

# Прогон для записи звука (godot --write-movie out.png): пуск, холостой ход,
# перегазовки, торможение двигателем, неисправности, остановка.
# Обороты по времени пишутся в user://audio_rpm.txt для сверки со спектром.
var f := 0
var main: Node
var log_lines := PackedStringArray()


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	f += 1
	var t := f / 60.0
	var sim: EngineSim = main.sim
	if f == 5:
		main.hud.start_cranking()
	if f == 75:
		main.hud.stop_cranking()
	# Перегазовки: 4–6 с полный газ, 8–10 с половина.
	var pedal := 0.0
	if t > 4.0 and t < 5.6:
		pedal = 1.0
	elif t > 8.0 and t < 9.5:
		pedal = 0.5
	elif t > 12.0 and t < 13.0:
		pedal = 1.0
	main.hud.hand_throttle = pedal
	if f == int(14.5 * 60):
		main.audio.belt_loose = true
		sim.valve_clearance_extra = 0.0003
	if f == int(15.0 * 60):
		main.hud.hand_throttle = 0.0
	if t > 15.0 and t < 15.8:
		main.hud.hand_throttle = 0.8
	if f == int(17.0 * 60):
		main.audio.belt_loose = false
		sim.valve_clearance_extra = 0.0
		sim.bearing_damage = 0.8
	if t > 18.0 and t < 19.0:
		main.hud.hand_throttle = 0.7
	if f == int(20.5 * 60):
		sim.bearing_damage = 0.0
		sim.electrical.key = 0
	if f % 6 == 0:
		log_lines.append("%.2f %.0f %.2f" % [t, sim.rpm(), sim.im_p / Gas.P_ATM])
	if f == int(23.0 * 60):
		var fa := FileAccess.open("user://audio_rpm.txt", FileAccess.WRITE)
		fa.store_string("\n".join(log_lines))
		fa.close()
		print("готово, записано ", log_lines.size(), " точек")
		return true
	return false
