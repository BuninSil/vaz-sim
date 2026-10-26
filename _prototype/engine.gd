extends Node3D

# Кинематика рядного 4-цилиндрового двигателя. Все детали находятся в
# Engine.tscn отдельными нодами: их можно выделять и менять в редакторе.
@export_range(100.0, 6000.0, 10.0) var rpm := 900.0
@export var crank_radius := 0.30
@export var rod_length := 1.20
@export var min_rpm := 100.0
@export var max_rpm := 6000.0

@onready var crankshaft: Node3D = $Crankshaft
@onready var rpm_label: Label = $HUD/RPM

var crank_angle := 0.0
var firing_cycle_angle := 0.0
var pistons: Array[CSGCylinder3D]
var crank_pins: Array[Node3D]
var connecting_rods: Array[CSGCylinder3D]
var piston_materials: Array[StandardMaterial3D]


func _ready() -> void:
	$Camera3D.look_at(Vector3(0.0, 0.75, 0.0))
	pistons.assign([$Piston, $Piston2, $Piston3, $Piston4])
	crank_pins.assign([$Crankshaft/CrankPin, $Crankshaft/CrankPin2, $Crankshaft/CrankPin3, $Crankshaft/CrankPin4])
	connecting_rods.assign([$ConnectingRod, $ConnectingRod2, $ConnectingRod3, $ConnectingRod4])
	# У каждого поршня свой материал: вспышка показывает текущий рабочий цилиндр.
	for piston in pistons:
		var material := piston.material.duplicate() as StandardMaterial3D
		piston.material = material
		piston_materials.append(material)
	set_process_input(true)
	_update_mechanism()


func _process(delta: float) -> void:
	# Стрелки / W и S сразу меняют обороты, пробел ставит двигатель на паузу.
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		rpm = min(rpm + 1800.0 * delta, max_rpm)
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		rpm = max(rpm - 1800.0 * delta, min_rpm)
	if Input.is_key_pressed(KEY_SPACE):
		rpm = 0.0

	var angle_step := rpm * TAU / 60.0 * delta
	crank_angle = fmod(crank_angle + angle_step, TAU)
	firing_cycle_angle = fmod(firing_cycle_angle + angle_step, TAU * 2.0)
	_update_mechanism()
	var firing_order := [1, 3, 4, 2]
	var firing_index := int(floor(firing_cycle_angle / (TAU * 0.5)))
	for index in piston_materials.size():
		piston_materials[index].emission_enabled = index + 1 == firing_order[firing_index]
		piston_materials[index].emission = Color(1.0, 0.22, 0.03, 1.0)
	rpm_label.text = "ВАЗ-21061 · рядный 4-цилиндровый\n%d об/мин · рабочий такт: цилиндр %d\nПорядок работы: 1-3-4-2\n↑/W — быстрее   ↓/S — медленнее   Space — стоп" % [round(rpm), firing_order[firing_index]]


func _input(event: InputEvent) -> void:
	# Реакция происходит уже на одно короткое нажатие, а не только при удержании.
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	if event.keycode == KEY_UP or event.keycode == KEY_W or event.physical_keycode == KEY_W:
		rpm = min(rpm + 300.0, max_rpm)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DOWN or event.keycode == KEY_S or event.physical_keycode == KEY_S:
		rpm = max(rpm - 300.0, min_rpm)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE:
		rpm = 0.0
		get_viewport().set_input_as_handled()


func _update_mechanism() -> void:
	# Кривошипы 1/4 и 2/3 развёрнуты на 180°, как у рядного ВАЗовского I4.
	crankshaft.rotation.x = crank_angle
	for index in crank_pins.size():
		var pin_position := crank_pins[index].global_position
		# Поршень скользит только по вертикальной оси своего цилиндра.
		var piston_y := pin_position.y + sqrt(max(rod_length * rod_length - pin_position.z * pin_position.z, 0.0))
		var piston_position := Vector3(pin_position.x, piston_y, 0.0)
		pistons[index].global_position = piston_position

		var rod_vector := pin_position - piston_position
		connecting_rods[index].global_position = (pin_position + piston_position) * 0.5
		connecting_rods[index].global_basis = Basis(Quaternion(Vector3.UP, rod_vector.normalized())).scaled(Vector3(1.0, rod_vector.length() / rod_length, 1.0))
