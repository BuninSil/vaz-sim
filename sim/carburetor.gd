class_name Carburetor
extends RefCounted

# Двухкамерный карбюратор «Озон 2107» с последовательным открытием камер.
# Первичная камера открывается педалью, вторичная — пневмоприводом от разрежения
# в диффузорах. Топливо подаётся главными дозирующими системами (по разрежению
# в диффузоре), системой холостого хода (по разрежению за дросселем),
# эконостатом и ускорительным насосом. Воздушная заслонка («подсос») прикрывает
# первичную камеру и приоткрывает дроссель пусковым устройством.

var pedal := 0.0             # 0..1 — положение педали газа
var choke := 0.0             # 0..1 — ручка подсоса
var idle_speed_screw := 1.0  # винт количества смеси (упор дросселя)
var idle_mixture_screw := 1.0  # винт качества смеси
var main_jet_clog := 0.0     # 0..1 — засор главного жиклёра первичной камеры
var idle_jet_clog := 0.0     # 0..1 — засор топливного жиклёра холостого хода
var accel_pump_ok := true
var air_filter_clog := 0.0   # 0..1
var vacuum_leak_area := 0.0  # м², подсос воздуха мимо карбюратора
var fuel_supply_ok := true   # бензонасос/бак

# Состояние.
var secondary_open := 0.0
var bowl_level := 1.0        # уровень в поплавковой камере (1 — норма)
var primary_angle_deg := 0.0
var secondary_angle_deg := 0.0
var venturi_depression := 0.0
var air_flow := 0.0
var fuel_flow := 0.0
var _prev_pedal := 0.0
var _pump_fuel_pending := 0.0

# Калибровка дозирования (подобрана так, чтобы состав смеси совпадал с паспортом карбюратора).
const MAIN_K := 0.88
const SECONDARY_K := 0.62
const IDLE_K := 0.37
const ECONOSTAT_K := 0.12
const AIR_FILTER_K := 7.0e5
const PUMP_STROKE_FUEL := 0.00052  # кг за полный ход ускорительного насоса
const BOWL_FUEL := 0.016           # кг топлива в полной поплавковой камере
const IDLE_STOP_DEG := 5.7
const POWER_VALVE_ENRICH := 0.13
const IDLE_REF_VACUUM := 65000.0


static func throttle_area(diameter: float, angle_deg: float) -> float:
	# Площадь кольцевой щели вокруг дроссельной заслонки.
	var closed := deg_to_rad(EngineSpecs.THROTTLE_CLOSED_DEG)
	var a := clampf(deg_to_rad(angle_deg), closed, PI * 0.5)
	var full := PI * diameter * diameter * 0.25
	return full * (1.0 - cos(a) / cos(closed)) + full * 0.0025


# Угол дросселя на упоре: винт количества и пусковое устройство подсоса.
func idle_stop_angle() -> float:
	return EngineSpecs.THROTTLE_CLOSED_DEG + IDLE_STOP_DEG * idle_speed_screw + choke * 6.0


# Пересчитывает углы заслонок; вызывается раз в кадр и между шагами.
func update_controls(dt: float, rpm: float) -> void:
	var closed := EngineSpecs.THROTTLE_CLOSED_DEG
	# Упор дросселя (винт количества) и пусковое устройство приоткрывают первичную камеру.
	var stop := idle_stop_angle()
	primary_angle_deg = lerpf(stop, 90.0, clampf(pedal, 0.0, 1.0))
	# Пневмопривод вторичной камеры: открывается только при большом расходе первичной.
	var demand := clampf((air_flow - 0.022) / 0.016, 0.0, 1.0)
	if pedal < 0.6:
		demand = 0.0
	secondary_open = move_toward(secondary_open, demand, dt * (2.5 if demand > secondary_open else 6.0))
	secondary_angle_deg = lerpf(closed, 90.0, secondary_open)
	# Ускорительный насос впрыскивает топливо при резком открытии дросселя.
	var dp := pedal - _prev_pedal
	if dp > 0.0 and accel_pump_ok and rpm > 0.0:
		_pump_fuel_pending += dp * PUMP_STROKE_FUEL * bowl_level
	_prev_pedal = pedal


# Шаг расходов: давление во впускном коллекторе -> воздух и топливо в коллектор.
# Возвращает [воздух кг/с, топливо жидкое кг/с].
func flows(dt: float, p_manifold: float, t_ambient: float, rpm: float) -> PackedFloat64Array:
	var rho := Gas.P_ATM / (Gas.R_AIR * t_ambient)
	var a_primary := throttle_area(EngineSpecs.PRIMARY_BORE, primary_angle_deg)
	var a_secondary := throttle_area(EngineSpecs.SECONDARY_BORE, secondary_angle_deg)
	# Воздушная заслонка последовательно с дросселем первичной камеры.
	var bore_area := PI * EngineSpecs.PRIMARY_BORE * EngineSpecs.PRIMARY_BORE * 0.25
	# Пусковое устройство: после пуска разрежение за дросселем тянет диафрагму,
	# и она приоткрывает воздушную заслонку, чтобы прогревающийся мотор не залило.
	var pull := clampf((Gas.P_ATM - p_manifold - 12000.0) / 30000.0, 0.0, 1.0) if rpm > 400.0 else 0.0
	var a_choke := bore_area * maxf(1.0 - choke * 0.93 * (1.0 - 0.55 * pull), 0.05)
	var a_primary_eff := 1.0 / sqrt(1.0 / (a_primary * a_primary) + 1.0 / (a_choke * a_choke))
	var cd_area := 0.82 * (a_primary_eff + a_secondary)
	# Воздушный фильтр создаёт сопротивление, растущее с квадратом расхода.
	var p_in := Gas.P_ATM - AIR_FILTER_K * (1.0 + air_filter_clog * 12.0) * air_flow * air_flow
	p_in = maxf(p_in, p_manifold + 1.0)
	var m_air := Gas.orifice(cd_area, p_in, t_ambient, Gas.R_AIR, p_manifold, t_ambient, Gas.R_AIR)
	air_flow = lerpf(air_flow, maxf(m_air, 0.0), 0.2)
	var share_primary := a_primary_eff / (a_primary_eff + a_secondary)
	var m_primary := maxf(m_air, 0.0) * share_primary
	var m_secondary := maxf(m_air, 0.0) - m_primary

	# Разрежение в малом диффузоре первичной камеры.
	var av1 := PI * EngineSpecs.PRIMARY_VENTURI * EngineSpecs.PRIMARY_VENTURI * 0.25
	var av2 := PI * EngineSpecs.SECONDARY_VENTURI * EngineSpecs.SECONDARY_VENTURI * 0.25
	var g1 := m_primary / (0.95 * av1)
	var dp1 := g1 * g1 / (2.0 * rho)
	var g2 := m_secondary / (0.95 * av2)
	var dp2 := g2 * g2 / (2.0 * rho)
	# Прикрытая воздушная заслонка создаёт разрежение над диффузором.
	var gc := m_primary / (0.9 * a_choke)
	var gb := m_primary / (0.9 * bore_area)
	var dp_choke := (gc * gc - gb * gb) / (2.0 * rho)
	venturi_depression = dp1
	var head := 45.0  # перепад уровня топлива до распылителя, Па
	var level := clampf(bowl_level * 1.2, 0.0, 1.0)

	var fuel := 0.0
	# Главная дозирующая система первичной камеры.
	var jet1 := PI * EngineSpecs.PRIMARY_MAIN_JET * EngineSpecs.PRIMARY_MAIN_JET * 0.25 * (1.0 - main_jet_clog)
	var drive1 := maxf(dp1 * 1.35 + maxf(dp_choke, 0.0) - head, 0.0)
	var main1 := MAIN_K * jet1 * sqrt(2.0 * EngineSpecs.FUEL_DENSITY * drive1) * level
	# Экономайзер мощностных режимов: при малом разрежении за дросселем
	# пневмоклапан открывает дополнительный жиклёр.
	var power_valve := clampf((16000.0 - (Gas.P_ATM - p_manifold)) / 8000.0, 0.0, 1.0)
	fuel += main1 * (1.0 + POWER_VALVE_ENRICH * power_valve)
	# Главная дозирующая система вторичной камеры + эконостат на мощностном режиме.
	var jet2 := PI * EngineSpecs.SECONDARY_MAIN_JET * EngineSpecs.SECONDARY_MAIN_JET * 0.25
	var drive2 := maxf(dp2 * 1.35 - head, 0.0)
	fuel += SECONDARY_K * jet2 * sqrt(2.0 * EngineSpecs.FUEL_DENSITY * drive2) * level
	fuel += ECONOSTAT_K * jet2 * sqrt(2.0 * EngineSpecs.FUEL_DENSITY * maxf(dp2 * 1.35 - 900.0, 0.0)) * level
	# Система холостого хода работает от разрежения за дросселем и затухает при его открытии
	# (переходные отверстия ещё подпитывают смесь на малых углах).
	var idle_gate := clampf(1.0 - (primary_angle_deg - idle_stop_angle()) / 20.0, 0.0, 1.0)
	var jet_idle := PI * EngineSpecs.IDLE_FUEL_JET * EngineSpecs.IDLE_FUEL_JET * 0.25 * (1.0 - idle_jet_clog)
	var vacuum := maxf(Gas.P_ATM - p_manifold, 0.0)
	# Эмульсионный воздушный жиклёр ХХ делает подачу слабо зависящей от разрежения
	# (показатель ~0,3 вместо 0,5 у «голого» жиклёра) — на прокрутке смесь не беднеет.
	var idle_drive := sqrt(2.0 * EngineSpecs.FUEL_DENSITY * IDLE_REF_VACUUM * 0.07) * pow(vacuum / IDLE_REF_VACUUM, 0.3)
	fuel += IDLE_K * jet_idle * idle_drive * idle_gate * idle_mixture_screw * level

	# Ускорительный насос.
	if _pump_fuel_pending > 0.0:
		# Диафрагму насоса дожимает пружина — впрыск растянут почти на секунду.
		var shot := minf(_pump_fuel_pending, PUMP_STROKE_FUEL / 0.8 * dt)
		_pump_fuel_pending -= shot
		fuel += shot / dt

	# Поплавковая камера: бензонасос (от промвала) доливает, двигатель расходует.
	var refill := 0.0
	if fuel_supply_ok and rpm > 30.0:
		refill = (1.0 - bowl_level) * 4.0 * BOWL_FUEL * clampf(rpm / 600.0, 0.0, 1.0)
	bowl_level = clampf(bowl_level + (refill - fuel) * dt / BOWL_FUEL, 0.0, 1.0)
	fuel_flow = fuel
	return PackedFloat64Array([m_air, fuel])


func vacuum_leak_flow(p_manifold: float, t_ambient: float) -> float:
	return maxf(Gas.orifice(0.7 * vacuum_leak_area, Gas.P_ATM, t_ambient, Gas.R_AIR, p_manifold, t_ambient, Gas.R_AIR), 0.0)


# Разрежение в порту вакуумного корректора трамблёра: он над дросселем на холостом ходу.
func ported_vacuum(p_manifold: float) -> float:
	var open := clampf((primary_angle_deg - idle_stop_angle() - 1.0) / 3.0, 0.0, 1.0)
	return maxf(Gas.P_ATM - p_manifold, 0.0) * open
