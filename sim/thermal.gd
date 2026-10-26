class_name Thermal
extends RefCounted

# Системы охлаждения и смазки.
# Охлаждение: жидкостное, насос и вентилятор от ремня, термостат (начало
# открытия 80 °C, полное 94 °C), радиатор, пробка радиатора 0,5 бар.
# Смазка: шестерёнчатый насос от промежуточного вала, редукционный клапан,
# моторное масло 10W-40, 3,75 л.

const COOLANT_CAPACITY := 9.85  # л
const OIL_CAPACITY := 3.75      # л

var t_ambient := Gas.T_AMB
var t_coolant := Gas.T_AMB
var t_oil := Gas.T_AMB
var t_metal := Gas.T_AMB
var coolant_level := 1.0         # 0..1
var oil_level := 1.0             # 0..1 (1 — метка MAX)
var thermostat_mode := 0         # 0 — исправен, 1 — заклинил закрытым, 2 — открытым
var fan_ok := true
var water_pump_ok := true
var heat_speedup := 1.0          # ускорение тепловых процессов

var thermostat_open := 0.0
var fan_on := false
var oil_pressure := 0.0          # Па избыточного
var oil_relief_open := false
var boiling := false
var heat_to_coolant := 0.0
var heat_rejected := 0.0

const C_METAL := 52000.0   # Дж/К: блок, головка, поршни
const C_OIL := 11000.0


func set_uniform(t: float) -> void:
	t_coolant = t
	t_oil = t
	t_metal = t
	thermostat_open = clampf((t - 353.15) / 14.0, 0.0, 1.0)


func coolant_c() -> float:
	return 3600.0 * COOLANT_CAPACITY * maxf(coolant_level, 0.05)


# Кинематическая вязкость масла 10W-40, сСт.
func oil_viscosity() -> float:
	var t := t_oil - 273.15
	return clampf(90.0 * exp(-0.0311 * (t - 40.0)), 6.0, 9000.0)


func step(dt: float, rpm: float, wall_heat: float, friction_power: float, vehicle_speed: float, wear: float) -> void:
	var sdt := dt * heat_speedup
	# Термостат: восковой элемент с запаздыванием.
	var target := clampf((t_coolant - 353.15) / 14.0, 0.0, 1.0)
	if thermostat_mode == 1:
		target = 0.0
	elif thermostat_mode == 2:
		target = 1.0
	thermostat_open = move_toward(thermostat_open, target, sdt / 25.0)
	# Крыльчатка вентилятора на шкиве насоса: обдув растёт с оборотами.
	fan_on = fan_ok and water_pump_ok and rpm > 100.0
	var fan_air := clampf(rpm / 2500.0, 0.0, 1.3) if fan_on else 0.0
	var pump := clampf(rpm / 2200.0, 0.0, 1.0) * (1.0 if water_pump_ok else 0.08)
	# Металл получает тепло от газов и трения, отдаёт охлаждающей жидкости.
	var h_metal := 420.0 * (0.35 + 0.65 * pump) * clampf(coolant_level * 1.3, 0.1, 1.0)
	boiling = t_coolant > 383.15 or coolant_level < 0.3
	if boiling:
		h_metal *= 0.45  # паровые пробки
	var q_metal_coolant := h_metal * (t_metal - t_coolant)
	var q_metal_oil := 90.0 * (t_metal - t_oil)
	t_metal += (wall_heat + friction_power * 0.35 - q_metal_coolant - q_metal_oil - 6.0 * (t_metal - t_ambient)) * sdt / C_METAL
	# Радиатор: обдув набегающим потоком и вентилятором.
	var ua := (55.0 + 14.0 * minf(vehicle_speed, 35.0) + 300.0 * fan_air) * (0.35 + 0.65 * pump)
	var q_radiator := ua * thermostat_open * (t_coolant - t_ambient)
	var q_heater := 18.0 * (t_coolant - t_ambient)  # малый круг и отопитель
	var q_surface := 9.0 * (t_coolant - t_ambient)
	heat_to_coolant = q_metal_coolant
	heat_rejected = q_radiator
	t_coolant += (q_metal_coolant - q_radiator - q_heater - q_surface) * sdt / coolant_c()
	# Масло: тепло трения в подшипниках, отвод через поддон.
	var q_pan := (10.0 + 1.2 * minf(vehicle_speed, 35.0)) * (t_oil - t_ambient)
	t_oil += (friction_power * 0.4 + q_metal_oil - q_pan) * sdt / (C_OIL * maxf(oil_level, 0.2))
	_update_oil_pressure(rpm, wear)


func _update_oil_pressure(rpm: float, wear: float) -> void:
	# Подача насоса пропорциональна оборотам; давление — подача на проводимость
	# зазоров подшипников, которая растёт с износом и падает с вязкостью.
	var nu := oil_viscosity()
	var flow := rpm / 1000.0
	var conductance := (1.0 + wear * 3.0) * pow(14.0 / nu, 0.55)
	var p := flow * 0.62e5 / conductance
	# При низком уровне насос захватывает воздух.
	if oil_level < 0.45:
		p *= clampf((oil_level - 0.12) / 0.33, 0.0, 1.0) * clampf(1.4 - rpm / 6000.0, 0.3, 1.0)
	var relief := 4.9e5
	oil_relief_open = p > relief
	oil_pressure = minf(p, relief + (p - relief) * 0.08) if oil_relief_open else p
