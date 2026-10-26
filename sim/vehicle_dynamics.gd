class_name VehicleDynamics
extends RefCounted

# Трансмиссия и колёса ВАЗ-2106 на дороге.
# Считается на мелком шаге вместе с двигателем: сцепление (диск с трением),
# 4-ступенчатая КПП с синхронизаторами, карданный вал, главная передача 3,9
# с открытым дифференциалом, тормоза (передние дисковые, задние барабанные,
# стояночный на задние), продольные силы шин по «магической формуле» Пасейки.
# Вертикальные нагрузки и скорости пятен контакта приходят из физики кузова.

const WHEELS := 4                      # 0 ЛП, 1 ПП, 2 ЛЗ, 3 ПЗ
const WHEEL_INERTIA: Array[float] = [1.0, 1.0, 1.25, 1.25]   # колесо+ступица (+полуось сзади), кг·м²
const DRIVELINE_INERTIA := 0.035       # первичный вал, шестерни, кардан — на входе КПП
const BRAKE_TORQUE: Array[float] = [950.0, 950.0, 520.0, 520.0]  # при полном нажатии педали, Н·м
const HANDBRAKE_TORQUE := 900.0
const CLUTCH_CAPACITY := 165.0
const CLUTCH_STIFFNESS := 45.0         # Н·м на рад/с проскальзывания при полной затяжке
const SYNCHRO_RPM_WINDOW := 450.0

var wheel_omega := PackedFloat64Array([0, 0, 0, 0])
var fz := PackedFloat64Array([2700, 2700, 2700, 2700])   # нагрузка на колесо, Н
var v_long := PackedFloat64Array([0, 0, 0, 0])           # скорость пятна вдоль колеса, м/с
var mu := PackedFloat64Array([0.95, 0.95, 0.95, 0.95])   # сцепление с покрытием
var fx_avg := PackedFloat64Array([0, 0, 0, 0])           # средняя продольная сила за кадр
var slip := PackedFloat64Array([0, 0, 0, 0])

var gear := 1               # индекс в EngineSpecs.GEAR_RATIOS (1 — нейтраль)
var requested_gear := 1
var shift_timer := 0.0
var clutch_pedal := 0.0     # 0 — отпущена, 1 — выжата
var auto_clutch := true
var brake := 0.0
var handbrake := 0.0
var throttle_demand := 0.0
var engine_rpm := 0.0

var clutch_torque := 0.0
var clutch_slip := 0.0
var grinding := 0.0         # скрежет синхронизатора
var last_message := ""

var _fx_acc := PackedFloat64Array([0, 0, 0, 0])
var _acc_time := 0.0
var _auto_engage := 0.0


func ratio() -> float:
	return EngineSpecs.GEAR_RATIOS[gear] * EngineSpecs.FINAL_DRIVE


func gear_name() -> String:
	if shift_timer > 0.0:
		return "…"
	return EngineSpecs.GEAR_NAMES[gear]


func vehicle_speed() -> float:
	return (v_long[0] + v_long[1] + v_long[2] + v_long[3]) * 0.25


# Переключение передачи через синхронизатор.
func request_gear(g: int) -> void:
	g = clampi(g, 0, EngineSpecs.GEAR_RATIOS.size() - 1)
	if g == gear and shift_timer <= 0.0:
		return
	if g == 0 and absf(vehicle_speed()) > 1.0:
		last_message = "Задний ход включается только на месте — шестерни без синхронизатора"
		grinding = 1.0
		return
	if clutch_engagement() > 0.35 and g != 1 and not auto_clutch:
		last_message = "Скрежет! Выжмите сцепление (Shift), чтобы включить передачу"
		grinding = 1.0
		return
	requested_gear = g
	gear = 1
	shift_timer = 0.28   # ход рычага и работа синхронизатора


func clutch_engagement() -> float:
	# Ход педали мёртвый в начале и в конце, «схватывает» в середине.
	var pedal := clutch_pedal
	if auto_clutch:
		pedal = maxf(pedal, 1.0 - _auto_engage)
	return clampf((0.85 - pedal) / 0.6, 0.0, 1.0)


# Обновление органов управления раз в кадр физики.
func update_controls(dt: float) -> void:
	grinding = maxf(grinding - dt * 3.0, 0.0)
	if shift_timer > 0.0:
		shift_timer -= dt
		if shift_timer <= 0.0:
			gear = requested_gear
	if auto_clutch:
		# Автосцепление: выключается при переключении и на холостых оборотах,
		# плавно включается с ростом оборотов — как центробежное сцепление.
		var target := 0.0
		if gear != 1 and shift_timer <= 0.0:
			var launch := clampf((engine_rpm - 1050.0) / 1100.0, 0.0, 1.0)
			var rolling := clampf(absf(vehicle_speed()) / 4.0, 0.0, 1.0)
			target = maxf(launch, rolling if engine_rpm > 900.0 else 0.0)
			if throttle_demand < 0.05 and absf(vehicle_speed()) < 1.5:
				target = 0.0
		_auto_engage = move_toward(_auto_engage, target, dt * (2.5 if target > _auto_engage else 6.0))


# Магическая формула Пасейки для продольной силы (нормированная).
static func pacejka(s: float, b: float, c: float, e: float) -> float:
	var bs := b * s
	return sin(c * atan(bs - e * (bs - atan(bs))))


# Шаг трансмиссии и колёс; вызывается из шага двигателя. Возвращает момент сцепления.
func step(h: float, engine_omega: float) -> float:
	var r := ratio()
	var rw := EngineSpecs.WHEEL_RADIUS
	var prop := (wheel_omega[2] + wheel_omega[3]) * 0.5 * EngineSpecs.FINAL_DRIVE
	var input_omega := prop * EngineSpecs.GEAR_RATIOS[gear]
	clutch_torque = 0.0
	clutch_slip = engine_omega - input_omega
	if r != 0.0:
		var cap := CLUTCH_CAPACITY * clutch_engagement()
		clutch_torque = clampf(CLUTCH_STIFFNESS * clutch_engagement() * clutch_slip, -cap, cap)
	var drive_each := clutch_torque * r * 0.92 * 0.5
	# Инерция трансмиссии приводится к ведущим колёсам.
	var j_drive := DRIVELINE_INERTIA * r * r * 0.5
	for i in WHEELS:
		var w := wheel_omega[i]
		var v := v_long[i]
		var denom := maxf(absf(v), 1.5)
		var s := clampf((w * rw - v) / denom, -1.5, 1.5)
		slip[i] = s
		var load := maxf(fz[i], 0.0)
		var fx := load * mu[i] * pacejka(s, 11.0, 1.65, 0.6)
		var t := -fx * rw - signf(w) * load * 0.012 * rw
		var j: float = WHEEL_INERTIA[i]
		if i >= 2:
			t += drive_each
			j += j_drive
		var tb: float = BRAKE_TORQUE[i] * brake
		if i >= 2:
			tb += HANDBRAKE_TORQUE * handbrake
		var new_w := w + t / j * h
		# Тормоз — сухое трение: останавливает колесо, но не раскручивает назад.
		if tb > 0.0:
			var dw := tb / j * h
			if absf(new_w) <= dw:
				new_w = 0.0
			else:
				new_w -= signf(new_w) * dw
		wheel_omega[i] = new_w
		_fx_acc[i] += fx * h
	_acc_time += h
	return clutch_torque


# Средние силы за прошедший кадр — для физики кузова.
func take_forces() -> PackedFloat64Array:
	if _acc_time > 0.0:
		for i in WHEELS:
			fx_avg[i] = _fx_acc[i] / _acc_time
			_fx_acc[i] = 0.0
	_acc_time = 0.0
	return fx_avg


func reset() -> void:
	for i in WHEELS:
		wheel_omega[i] = 0.0
		fx_avg[i] = 0.0
		_fx_acc[i] = 0.0
	gear = 1
	requested_gear = 1
	shift_timer = 0.0
	_auto_engage = 0.0
