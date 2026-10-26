class_name Ignition
extends RefCounted

# Батарейная система зажигания: контактный прерыватель-распределитель с
# центробежным и вакуумным автоматами опережения и катушка Б117А.

var initial_advance_deg := EngineSpecs.IGNITION_INITIAL_DEG  # поворот корпуса трамблёра
var dwell_fraction := EngineSpecs.DWELL_FRACTION              # зазор контактов
var vacuum_unit_ok := true
var centrifugal_ok := true
var wire_connected := [true, true, true, true]
var plug_gap_mm := [0.65, 0.65, 0.65, 0.65]

var advance_deg := 0.0
var centrifugal_deg := 0.0
var vacuum_deg := 0.0
var spark_energy_mj := 0.0
var coil_current := 0.0


static func _curve(rpm: float) -> float:
	var c: Array = EngineSpecs.CENTRIFUGAL_CURVE
	if rpm <= c[0][0]:
		return c[0][1]
	for i in range(1, c.size()):
		if rpm <= c[i][0]:
			return lerpf(c[i - 1][1], c[i][1], (rpm - c[i - 1][0]) / (c[i][0] - c[i - 1][0]))
	return c[c.size() - 1][1]


func update(rpm: float, ported_vacuum: float, voltage: float, switched_on: bool) -> void:
	centrifugal_deg = _curve(rpm) if centrifugal_ok else 0.0
	vacuum_deg = 0.0
	if vacuum_unit_ok:
		vacuum_deg = clampf((ported_vacuum - 9000.0) / 35000.0, 0.0, 1.0) * EngineSpecs.VACUUM_ADVANCE_MAX_DEG
	advance_deg = initial_advance_deg + centrifugal_deg + vacuum_deg
	# Ток катушки нарастает по экспоненте за время замкнутого состояния контактов.
	if not switched_on or rpm < 20.0:
		spark_energy_mj = 0.0
		coil_current = voltage / EngineSpecs.COIL_RESISTANCE if switched_on else 0.0
		return
	var spark_interval := 30.0 / rpm
	var dwell_time := spark_interval * dwell_fraction
	var tau := EngineSpecs.COIL_INDUCTANCE / EngineSpecs.COIL_RESISTANCE
	coil_current = voltage / EngineSpecs.COIL_RESISTANCE * (1.0 - exp(-dwell_time / tau))
	spark_energy_mj = 0.5 * EngineSpecs.COIL_INDUCTANCE * coil_current * coil_current * 0.6 * 1000.0


# Энергия, которую нужно подвести в искру, чтобы поджечь смесь данного состава.
static func required_energy_mj(lambda: float, residual: float, gap_mm: float) -> float:
	var d := lambda - 0.9
	return (1.2 + 22.0 * d * d + 9.0 * residual) * (gap_mm / 0.65)


func average_current(rpm: float, switched_on: bool) -> float:
	if not switched_on:
		return 0.0
	return coil_current * (dwell_fraction if rpm > 20.0 else 1.0) + 0.3
