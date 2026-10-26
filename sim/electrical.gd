class_name Electrical
extends RefCounted

# Бортовая сеть: аккумулятор 6СТ-55, генератор Г-222 (55 А) с регулятором
# напряжения 14,2 В, стартер 35.3708 с обгонной муфтой.

const BATTERY_CAPACITY_AH := 55.0
const ALTERNATOR_RATIO := 2.04
const STARTER_R := 0.018
const STARTER_K := 0.027     # 13,5 Н·м при 500 А в режиме полного торможения
const STARTER_FRICTION := 0.25

var soc := 0.9                # заряженность аккумулятора
var alternator_ok := true     # ремень и диодный мост
var headlights := false
var key := 0                  # 0 — выкл, 1 — зажигание, 2 — стартер

var voltage := 12.6
var battery_current := 0.0    # + разряд
var alternator_current := 0.0
var starter_current := 0.0
var starter_torque := 0.0     # на коленвале
var charge_lamp := false


func battery_emf() -> float:
	return 11.75 + 0.95 * clampf(soc, 0.0, 1.0)


func battery_resistance(t_ambient: float) -> float:
	return (0.011 + 0.04 * (1.0 - soc)) * (1.0 + clampf((288.0 - t_ambient) / 30.0, 0.0, 1.5))


func alternator_max_current(rpm: float) -> float:
	var n := rpm * ALTERNATOR_RATIO
	return clampf((n - 1050.0) / 3400.0, 0.0, 1.0) * 55.0 if alternator_ok else 0.0


func step(dt: float, rpm: float, t_ambient: float, ignition_current: float, fan_on: bool) -> void:
	var omega_crank := rpm * TAU / 60.0
	var cranking := key == 2
	var emf := battery_emf()
	var rb := battery_resistance(t_ambient)
	var g_load := 0.0
	if key >= 1:
		g_load += 1.0 / 30.0  # приборы, реле

		if headlights:
			g_load += 1.0 / 1.25
	var bemf := 0.0
	var omega_motor := omega_crank * EngineSpecs.STARTER_RATIO
	var overrun := false
	if cranking:
		# Обгонная муфта: когда мотор раскрутился, якорь отстаёт и вращается
		# почти вхолостую — генератором он не становится и вал не толкает.
		overrun = STARTER_K * omega_motor > emf * 0.97
		bemf = minf(STARTER_K * omega_motor, emf * 0.97)
	var i_alt_max := alternator_max_current(rpm)
	# Регулятор держит 14,2 В, если хватает тока генератора; иначе генератор отдаёт максимум.
	var v := 14.2
	var i_st := (v - bemf) / STARTER_R if cranking else 0.0
	var i_batt_charge := (v - emf) / (rb * 4.0)
	var needed := g_load * v + ignition_current + maxf(i_st, 0.0) + i_batt_charge
	if needed <= i_alt_max and i_alt_max > 0.0:
		alternator_current = needed
	else:
		# Генератор на пределе: решаем линейную цепь относительно напряжения сети.
		var g_st := 1.0 / STARTER_R if cranking else 0.0
		v = (emf / rb + i_alt_max - ignition_current + bemf * g_st) / (1.0 / rb + g_load + g_st)
		if v > emf:
			v = (emf / (rb * 4.0) + i_alt_max - ignition_current + bemf * g_st) / (1.0 / (rb * 4.0) + g_load + g_st)
		alternator_current = i_alt_max
		i_st = (v - bemf) * g_st
	voltage = maxf(v, 0.0)
	starter_current = maxf(i_st, 0.0) if cranking else 0.0
	battery_current = g_load * voltage + ignition_current + starter_current - alternator_current
	soc = clampf(soc - battery_current * dt / (BATTERY_CAPACITY_AH * 3600.0), 0.0, 1.0)
	# Обгонная муфта: стартер толкает коленвал, только пока якорь не отстаёт.
	starter_torque = 0.0
	if cranking and not overrun:
		var t_motor := STARTER_K * starter_current - STARTER_FRICTION
		starter_torque = maxf(t_motor, 0.0) * EngineSpecs.STARTER_RATIO
	charge_lamp = key >= 1 and alternator_current < 2.0 and rpm < 1200.0


func alternator_drag_torque(rpm: float) -> float:
	if rpm < 50.0:
		return 0.0
	var omega := rpm * TAU / 60.0
	return voltage * alternator_current / 0.55 / omega + 0.25
