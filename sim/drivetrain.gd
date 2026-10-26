class_name Drivetrain
extends RefCounted

# Нагрузка на двигатель: нейтраль, тормозной стенд или автомобиль ВАЗ-2106
# (сцепление, 4-ступенчатая КПП, главная передача 3,9).

enum Mode { FREE, DYNO, CAR, ROAD }

var mode := Mode.FREE
# Полноценный автомобиль на трассе (колёса и трансмиссия считаются здесь же).
var vehicle := VehicleDynamics.new()
# Стенд: либо постоянный тормозной момент, либо удержание оборотов регулятором.
var dyno_torque := 0.0
var dyno_hold_rpm := false
var dyno_target_rpm := 3000.0
# Автомобиль.
var gear := 1                 # индекс в EngineSpecs.GEAR_RATIOS (1 — нейтраль)
var clutch := 1.0             # 1 — отпущена (включена), 0 — выжата
var brake := 0.0
var vehicle_speed := 0.0      # м/с
var slope := 0.0              # уклон дороги, рад

var clutch_locked := false
var load_torque := 0.0        # момент, которым нагрузка тормозит коленвал
var _dyno_integral := 0.0

const CLUTCH_CAPACITY := 160.0
const DRIVELINE_EFFICIENCY := 0.92


func ratio() -> float:
	return EngineSpecs.GEAR_RATIOS[gear] * EngineSpecs.FINAL_DRIVE


# Момент нагрузки на коленвал для текущего шага. omega — обороты коленвала, рад/с.
func load_on_engine(dt: float, omega: float, engine_inertia: float, engine_torque: float) -> float:
	match mode:
		Mode.FREE:
			load_torque = 0.0
		Mode.DYNO:
			if dyno_hold_rpm:
				# ПИ-регулятор балансирной машины.
				var err := omega - dyno_target_rpm * TAU / 60.0
				_dyno_integral = clampf(_dyno_integral + err * dt * 40.0, 0.0, 400.0)
				load_torque = clampf(err * 6.0 + _dyno_integral, 0.0, 400.0)
			else:
				load_torque = dyno_torque if omega > 1.0 else 0.0
		Mode.CAR:
			load_torque = _car_step(dt, omega, engine_inertia, engine_torque)
		Mode.ROAD:
			load_torque = vehicle.step(dt, omega)
	return load_torque


func _car_step(dt: float, omega: float, engine_inertia: float, engine_torque: float) -> float:
	var r := ratio()
	var resist := _road_force() * EngineSpecs.WHEEL_RADIUS  # момент сопротивления на колёсах
	var j_vehicle := EngineSpecs.VEHICLE_MASS * EngineSpecs.WHEEL_RADIUS * EngineSpecs.WHEEL_RADIUS
	var wheel_omega := vehicle_speed / EngineSpecs.WHEEL_RADIUS
	if r == 0.0 or clutch < 0.02:
		clutch_locked = false
		_advance_vehicle(dt, -resist, j_vehicle)
		return 0.0
	var capacity := CLUTCH_CAPACITY * clampf(clutch, 0.0, 1.0)
	var input_omega := wheel_omega * r
	var slip := omega - input_omega
	if clutch_locked:
		# Сцеплённое состояние: двигатель и машина вращаются вместе.
		var j_eq := j_vehicle / (r * r)
		var t_eq := resist / r / DRIVELINE_EFFICIENCY
		var t_through := (engine_torque * j_eq + t_eq * engine_inertia) / (engine_inertia + j_eq)
		if absf(t_through) > capacity:
			clutch_locked = false
		else:
			var acc := (engine_torque - t_eq) / (engine_inertia + j_eq)
			var new_omega := omega + acc * dt
			vehicle_speed = new_omega / r * EngineSpecs.WHEEL_RADIUS
			return t_through
	var t_clutch := capacity * signf(slip) * minf(absf(slip) / 3.0, 1.0)
	_advance_vehicle(dt, t_clutch * r * DRIVELINE_EFFICIENCY - resist, j_vehicle)
	var new_slip := omega - vehicle_speed / EngineSpecs.WHEEL_RADIUS * r
	if signf(new_slip) != signf(slip) or absf(new_slip) < 0.5:
		clutch_locked = clutch > 0.9
	return t_clutch


func _advance_vehicle(dt: float, wheel_torque: float, j_vehicle: float) -> void:
	vehicle_speed += wheel_torque / j_vehicle * EngineSpecs.WHEEL_RADIUS * dt
	if absf(vehicle_speed) < 0.05 and absf(wheel_torque) < brake * 2500.0 * EngineSpecs.WHEEL_RADIUS + 30.0:
		vehicle_speed = 0.0


func _road_force() -> float:
	var v := vehicle_speed
	var s := signf(v)
	var f := 0.5 * 1.2 * EngineSpecs.DRAG_AREA * v * v * s
	f += EngineSpecs.VEHICLE_MASS * 9.81 * (0.014 * (1.0 + v * v / 1500.0)) * s
	f += EngineSpecs.VEHICLE_MASS * 9.81 * sin(slope)
	f += brake * 9000.0 * s
	return f
