class_name EngineSim
extends RefCounted

# Нульмерная модель четырёхтактного двигателя с разрешением по углу поворота коленвала.
# Для каждого цилиндра на каждом шаге решаются: кинематика КШМ, перетекание газов
# через клапаны (сопло с учётом сжимаемости), первый закон термодинамики,
# теплообмен со стенками (Вошни), сгорание по Вибе с межцикловым разбросом,
# самовоспламенение конечного заряда (Ливенгуд — Ву), утечки мимо колец.
# Коленвал интегрируется с учётом газовых и инерционных моментов, трения,
# привода агрегатов, стартера и нагрузки.

const DEG := PI / 180.0
const CYCLE := 4.0 * PI
const LIFT_TABLE := 1440  # точек на 720°
# Впускной канал: ответвление коллектора плюс канал в головке.
const RUNNER_AREA := 0.00095
const RUNNER_FRICTION := 3.0e5
const RUNNER_DAMPING := 140.0
const HEAT_TRANSFER_SCALE := 3.0
const PORT_HEATING_RATE := 12.0
# Поправка корреляции Дуо — Эйза к упрощённой температуре конечного заряда.
const KNOCK_SCALE := 3.0

class Cylinder:
	var index := 0
	var offset := 0.0
	var m_air := 0.0
	var m_fuel := 0.0
	var m_burned := 0.0
	var t := 300.0
	var p := Gas.P_ATM
	var v := 0.0
	var local := 0.0           # угол в цикле цилиндра, 0 — ВМТ начала впуска
	var intake_lift := 0.0
	var exhaust_lift := 0.0
	# Сгорание текущего цикла.
	var burning := false
	var burn_start := 0.0
	var burn_duration := 1.0
	var burn_fraction := 0.0
	var heat_total := 0.0
	var fuel_to_burn := 0.0
	var air_to_burn := 0.0
	var spark_done := false
	var misfire := false
	var knock_integral := 0.0
	var knock := 0.0
	var t_ivc := 300.0
	var p_ivc := Gas.P_ATM
	# Показатели последнего цикла.
	var trapped_lambda := 1.0
	var residual := 0.0
	var trapped_air := 0.0
	var peak_pressure := 0.0
	var cycle_work := 0.0
	var imep := 0.0
	var last_misfire := false
	var last_knock := 0.0
	var spark_flash := 0.0
	var _work_acc := 0.0
	var _peak_acc := 0.0
	# Впускной канал (от коллектора до клапана).
	var r_air := 0.0
	var r_fuel := 0.0
	var r_burned := 0.0
	var r_t := 300.0
	var runner_flow := 0.0
	# Неисправности и повреждения.
	var ring_wear := 0.0
	var piston_damage := 0.0
	var valve_burnt := 0.0
	var plug_hole := false      # свеча вывернута — цилиндр сообщается с атмосферой


var specs := EngineSpecs
var carb := Carburetor.new()
var ignition := Ignition.new()
var thermal := Thermal.new()
var electrical := Electrical.new()
var drivetrain := Drivetrain.new()
var cylinders: Array[Cylinder] = []

# Состояние коленвала.
var phi := 0.0            # угол цикла 0..4π, 0 — ВМТ впуска 1-го цилиндра
var omega := 0.0
var sim_time := 0.0

# Впускной коллектор.
var im_air := 0.0
var im_fuel := 0.0
var im_burned := 0.0
var im_film := 0.0
var im_t := Gas.T_AMB
var im_p := Gas.P_ATM
# Выпускной коллектор и система выпуска.
var ex_mass := 0.0
var ex_t := Gas.T_AMB
var ex_p := Gas.P_ATM
var ex_flow_out := 0.0     # расход в атмосферу — источник звука
var exhaust_clog := 0.0

# Настройки.
var fuel_octane := 92.0
var valve_clearance_extra := 0.0  # м сверх нормы
var cycle_variation := 0.06
var max_step_angle := 3.0 * DEG
var max_step_time := 3.0e-4

# Повреждения всего двигателя.
var bearing_damage := 0.0
var head_gasket_damage := 0.0
var seized := false
var valve_float := 0.0
var rod_failure := false
var timing_broken := false   # оборвало/сорвало цепь ГРМ — распредвал стоит
var _cam_frozen := 0.0       # угол цикла, на котором встал распредвал
var ev_chain := 0            # события для звука: обрыв цепи, удары клапанов о поршни, обрыв шатуна
var ev_valve_hits := 0
var ev_rod := 0
var damage_log: Array[String] = []

# Усреднённые выходные показатели.
var torque_gross := 0.0     # мгновенный суммарный газовый + инерционный
var torque_avg := 0.0       # эффективный момент за цикл
var power_avg := 0.0
var friction_torque := 0.0
var accessory_torque := 0.0
var air_mass_rate := 0.0
var fuel_mass_rate := 0.0
var volumetric_efficiency := 0.0
var lambda_avg := 1.0
var exhaust_temp := Gas.T_AMB
var last_wall_heat := 0.0
var rpm_display := 0.0

var _cycle_torque_acc := 0.0
var _cycle_time_acc := 0.0
var _cycle_air_acc := 0.0
var _cycle_fuel_acc := 0.0
var _cycle_angle_acc := 0.0
var _wall_heat_acc := 0.0
var _rng := RandomNumberGenerator.new()

var _knock_coef := 0.0
var _over_rev_time := 0.0
var _viscosity_factor := 1.0
var _alternator_drag := 0.0
var _intake_table := PackedFloat64Array()
var _exhaust_table := PackedFloat64Array()
var _v_clear := 0.0
var _a_piston := 0.0

# Запись индикаторной диаграммы 1-го цилиндра за последний цикл.
var trace_pressure := PackedFloat32Array()
var trace_volume := PackedFloat32Array()
var _trace_pressure_build := PackedFloat32Array()
var _trace_volume_build := PackedFloat32Array()
const TRACE_POINTS := 360

# Звук: значения расхода выпуска на каждом шаге и времена шагов.
var audio_exhaust := PackedFloat32Array()
var audio_intake := PackedFloat32Array()
var audio_knock := PackedFloat32Array()
var audio_mech := PackedFloat32Array()
var audio_dt := PackedFloat32Array()
var record_audio := false
# То же для главного потока: модель может считаться в фоновом потоке, а звук и
# графики читают только эти копии, обновляемые в publish().
var out_exhaust := PackedFloat32Array()
var out_intake := PackedFloat32Array()
var out_mech := PackedFloat32Array()
var out_knock := PackedFloat32Array()
var out_dt := PackedFloat32Array()
var view_pressure := PackedFloat32Array()
var view_volume := PackedFloat32Array()
# События сгорания для звука: вспышки и пропуски с прошлой публикации.
var ev_fires := 0
var ev_misfires := 0
var out_fires := 0
var out_misfires := 0


# Передаёт накопленный звук и индикаторную диаграмму главному потоку.
# Вызывается в главном потоке, когда расчёт шага завершён.
func publish() -> void:
	out_exhaust.append_array(audio_exhaust)
	out_intake.append_array(audio_intake)
	out_mech.append_array(audio_mech)
	out_knock.append_array(audio_knock)
	out_dt.append_array(audio_dt)
	audio_exhaust.clear()
	audio_intake.clear()
	audio_mech.clear()
	audio_knock.clear()
	audio_dt.clear()
	# Не даём очереди звука расти, если его не забирают.
	if out_dt.size() > 60000:
		var cut := out_dt.size() - 60000
		out_exhaust = out_exhaust.slice(cut)
		out_intake = out_intake.slice(cut)
		out_mech = out_mech.slice(cut)
		out_knock = out_knock.slice(cut)
		out_dt = out_dt.slice(cut)
	view_pressure = trace_pressure.duplicate()
	view_volume = trace_volume.duplicate()
	out_fires += ev_fires
	out_misfires += ev_misfires
	ev_fires = 0
	ev_misfires = 0


func _init() -> void:
	_rng.seed = 2103
	apply_specs()
	trace_pressure.resize(TRACE_POINTS)
	trace_volume.resize(TRACE_POINTS)
	_trace_pressure_build.resize(TRACE_POINTS)
	_trace_volume_build.resize(TRACE_POINTS)
	for i in EngineSpecs.CYLINDERS:
		var c := Cylinder.new()
		c.index = i
		c.offset = EngineSpecs.CYCLE_OFFSET[i]
		cylinders.append(c)
	reset(Gas.T_AMB)


# Пересчитывает всё, что зависит от паспорта двигателя (после смены мотора).
func apply_specs() -> void:
	_v_clear = EngineSpecs.clearance_volume()
	_a_piston = EngineSpecs.piston_area()
	_build_lift_tables()


func set_seed(s: int) -> void:
	_rng.seed = s


func reset(temperature: float, ambient := Gas.T_AMB) -> void:
	thermal.t_ambient = ambient
	thermal.set_uniform(temperature)
	omega = 0.0
	reset_gas()
	carb.bowl_level = 1.0
	seized = false
	rod_failure = false
	timing_broken = false


# Заполняет цилиндры и коллекторы воздухом при текущем положении коленвала
# (после ручного проворота или сборки двигателя).
func reset_gas() -> void:
	im_t = Gas.T_AMB
	im_p = Gas.P_ATM
	var im_v := EngineSpecs.INTAKE_MANIFOLD_VOLUME
	im_air = Gas.P_ATM * im_v / (Gas.R_AIR * im_t)
	im_fuel = 0.0
	im_burned = 0.0
	im_film = 0.0
	# Горячий мотор после остановки: бензин из поплавковой камеры испаряется
	# во впускной коллектор (горячая стоянка) — в каналах стоит готовая смесь,
	# поэтому прогретый двигатель схватывает с пол-оборота.
	var hot := smoothstep(315.0, 345.0, thermal.t_coolant)
	im_fuel = im_air / (EngineSpecs.AFR_STOICH * 0.95) * hot
	im_film = 0.00002 * hot
	ex_t = Gas.T_AMB
	ex_p = Gas.P_ATM
	ex_mass = Gas.P_ATM * EngineSpecs.EXHAUST_MANIFOLD_VOLUME / (Gas.R_BURNED * ex_t)
	for c in cylinders:
		c.local = fposmod(phi - c.offset, CYCLE)
		c.v = _volume(c.local)
		c.t = Gas.T_AMB
		c.p = Gas.P_ATM
		var m := c.p * c.v / (Gas.R_AIR * c.t)
		c.m_air = m
		c.m_fuel = 0.0
		c.m_burned = 0.0
		c.burning = false
		c.spark_done = false
		c.r_t = Gas.T_AMB
		c.r_air = Gas.P_ATM * RUNNER_AREA * EngineSpecs.RUNNER_LENGTH / (Gas.R_AIR * c.r_t)
		c.r_fuel = c.r_air / (EngineSpecs.AFR_STOICH * 0.95) * hot
		c.r_burned = 0.0
		c.runner_flow = 0.0
		c.intake_lift = 0.0
		c.exhaust_lift = 0.0


# --- Кинематика ----------------------------------------------------------

# Ход поршня от ВМТ (м) при угле поворота кривошипа a.
static func piston_travel(a: float) -> float:
	var r := EngineSpecs.CRANK_RADIUS
	var l := EngineSpecs.ROD_LENGTH
	var s := sin(a)
	return r * (1.0 - cos(a)) + l - sqrt(l * l - r * r * s * s)


static func piston_travel_derivative(a: float) -> float:
	var r := EngineSpecs.CRANK_RADIUS
	var l := EngineSpecs.ROD_LENGTH
	var s := sin(a)
	var q := sqrt(l * l - r * r * s * s)
	return r * s * (1.0 + r * cos(a) / q)


static func piston_travel_second(a: float) -> float:
	var r := EngineSpecs.CRANK_RADIUS
	var l := EngineSpecs.ROD_LENGTH
	var s := sin(a)
	var c := cos(a)
	var q := sqrt(l * l - r * r * s * s)
	return r * c + r * r * (c * c - s * s) / q + pow(r, 4) * s * s * c * c / (q * q * q)


func _volume(local: float) -> float:
	return _v_clear + _a_piston * piston_travel(fmod(local, TAU))


# --- Газораспределение ----------------------------------------------------

static func _lobe(u: float) -> float:
	# Профиль кулачка: плавный подъём с «полкой» у максимума.
	if u <= 0.0 or u >= 1.0:
		return 0.0
	var s := sin(PI * u)
	return pow(s, 1.35)


func _build_lift_tables() -> void:
	_intake_table.resize(LIFT_TABLE + 1)
	_exhaust_table.resize(LIFT_TABLE + 1)
	var ivo := CYCLE - EngineSpecs.IVO_BTDC * DEG
	var int_dur := (EngineSpecs.IVO_BTDC + 180.0 + EngineSpecs.IVC_ABDC) * DEG
	var evo := 3.0 * PI - EngineSpecs.EVO_BBDC * DEG
	var exh_dur := (EngineSpecs.EVO_BBDC + 180.0 + EngineSpecs.EVC_ATDC) * DEG
	for i in LIFT_TABLE + 1:
		var a := CYCLE * i / LIFT_TABLE
		_intake_table[i] = _lobe(fposmod(a - ivo, CYCLE) / int_dur)
		_exhaust_table[i] = _lobe(fposmod(a - evo, CYCLE) / exh_dur)


# Нормированный подъём кулачка 0..1 для угла цикла цилиндра.
func cam_profile(local: float, intake: bool) -> float:
	var f := fposmod(local, CYCLE) / CYCLE * LIFT_TABLE
	var i := int(f)
	var tbl := _intake_table if intake else _exhaust_table
	if i >= LIFT_TABLE:
		return tbl[LIFT_TABLE]
	return lerpf(tbl[i], tbl[i + 1], f - i)


# Подъём клапана (м) с учётом теплового зазора и зависания на высоких оборотах.
func valve_lift(local: float, intake: bool) -> float:
	var full := EngineSpecs.VALVE_LIFT + EngineSpecs.VALVE_CLEARANCE * EngineSpecs.ROCKER_RATIO
	var lift := cam_profile(local, intake) * full - (EngineSpecs.VALVE_CLEARANCE + valve_clearance_extra) * EngineSpecs.ROCKER_RATIO
	if valve_float > 0.0:
		# Пружина не успевает: клапан отрывается от кулачка, садится с большим
		# опозданием и подпрыгивает на седле — заряд выталкивается обратно,
		# сжатие травит. Обороты без нагрузки упираются в это, как на живом моторе.
		var late := cam_profile(local - 60.0 * DEG * valve_float, intake) * full * 0.95
		lift = maxf(lift, late - EngineSpecs.VALVE_CLEARANCE * EngineSpecs.ROCKER_RATIO)
		var bounce := cam_profile(local - 95.0 * DEG * valve_float, intake)
		if bounce > 0.02:
			lift = maxf(lift, 0.0012 * valve_float)
	return maxf(lift, 0.0)


# --- Основной цикл ---------------------------------------------------------

func rpm() -> float:
	return omega * 60.0 / TAU


# Продвигает модель на dt секунд реального времени, дробя на шаги по углу.
func advance(dt: float) -> int:
	var steps := 0
	var remaining := dt
	carb.update_controls(dt, rpm())
	ignition.update(rpm(), carb.ported_vacuum(im_p), electrical.voltage, electrical.key >= 1)
	_knock_coef = 0.01768 * KNOCK_SCALE * pow(fuel_octane / 100.0, 3.402)
	_viscosity_factor = pow(thermal.oil_viscosity() / 19.0, 0.25)
	_alternator_drag = electrical.alternator_drag_torque(rpm())
	var step_angle := lerpf(max_step_angle, max_step_angle * 2.0, clampf((rpm() - 2000.0) / 3500.0, 0.0, 1.0))
	while remaining > 1e-9:
		var h := max_step_time
		if omega > 1.0:
			h = minf(h, step_angle / omega)
		h = minf(h, remaining)
		_step(h)
		remaining -= h
		steps += 1
	_slow_update(dt)
	return steps


func _slow_update(dt: float) -> void:
	var r := rpm()
	rpm_display = lerpf(rpm_display, r, clampf(dt * 12.0, 0.0, 1.0))
	var fric_power := friction_torque * omega
	var wear := bearing_damage
	thermal.step(dt, r, last_wall_heat, fric_power, absf(drivetrain.vehicle_speed), wear)
	electrical.step(dt, r, thermal.t_ambient, ignition.average_current(r, electrical.key >= 1), thermal.fan_on)
	_update_damage(dt, r)


func _update_damage(dt: float, r: float) -> void:
	# Масляное голодание — задиры вкладышей.
	if r > 200.0 and thermal.oil_pressure < 0.35e5:
		var severity := (1.0 - thermal.oil_pressure / 0.35e5) * (r / 3000.0)
		bearing_damage = minf(bearing_damage + severity * dt * 0.02, 1.0)
		if bearing_damage >= 1.0 and not seized:
			seized = true
			_log("Масляное голодание: провернуло вкладыши, двигатель заклинил")
	# Перегрев — пробой прокладки ГБЦ.
	if thermal.t_coolant > 388.15:
		head_gasket_damage = minf(head_gasket_damage + (thermal.t_coolant - 388.15) * dt * 0.004, 1.0)
		if head_gasket_damage >= 1.0 and not _logged("прокладк"):
			_log("Перегрев: пробита прокладка головки блока, антифриз в цилиндрах")
	# Зависание клапанов при перекрутке.
	valve_float = clampf((r - EngineSpecs.VALVE_FLOAT_RPM) / 700.0, 0.0, 1.0)
	# Перекрутка: цепь ГРМ не выдерживает рывков зависающих клапанов и рвётся
	# (у классики клапаны встречаются с поршнями — гнёт). Дальше — шатун.
	if r > 8000.0 and not timing_broken:
		_over_rev_time += dt
		if _over_rev_time > 0.15:
			timing_broken = true
			_cam_frozen = phi
			ev_chain += 1
			_log("Перекрутка свыше 8000 об/мин: сорвало цепь ГРМ, клапаны встретились с поршнями")
	else:
		_over_rev_time = maxf(_over_rev_time - dt, 0.0)
	if r > 8800.0 and not rod_failure:
		rod_failure = true
		seized = true
		ev_rod += 1
		_log("Перекрутка свыше 8800 об/мин: оборвало шатун")


func _logged(fragment: String) -> bool:
	for s in damage_log:
		if s.contains(fragment):
			return true
	return false


func _log(text: String) -> void:
	damage_log.append(text)


func _step(h: float) -> void:
	var d_phi := omega * h
	phi = fposmod(phi + d_phi, CYCLE)
	sim_time += h
	var im_v := EngineSpecs.INTAKE_MANIFOLD_VOLUME
	var ex_v := EngineSpecs.EXHAUST_MANIFOLD_VOLUME
	var im_m := im_air + im_fuel + im_burned
	var im_r := (im_air * Gas.R_AIR + im_fuel * Gas.R_FUEL + im_burned * Gas.R_BURNED) / maxf(im_m, 1e-9)
	var t_wall := thermal.t_metal + 70.0
	var t_port := thermal.t_coolant + 5.0
	var mean_piston_speed := 2.0 * EngineSpecs.STROKE * omega / TAU
	var torque := 0.0
	var wall_heat := 0.0
	var ex_in_mass := 0.0
	var ex_in_energy := 0.0
	var im_in_air := 0.0
	var im_in_fuel := 0.0
	var im_in_burned := 0.0
	var intake_audio := 0.0
	var knock_audio := 0.0
	var mech_audio := 0.0
	var r_now := omega * 60.0 / TAU
	var rr := EngineSpecs.CRANK_RADIUS
	var ll := EngineSpecs.ROD_LENGTH
	var omega2 := omega * omega
	var runner_k := RUNNER_AREA / EngineSpecs.RUNNER_LENGTH
	var runner_v := RUNNER_AREA * EngineSpecs.RUNNER_LENGTH
	var lift_full := EngineSpecs.VALVE_LIFT + EngineSpecs.VALVE_CLEARANCE * EngineSpecs.ROCKER_RATIO
	var lift_cut := (EngineSpecs.VALVE_CLEARANCE + valve_clearance_extra) * EngineSpecs.ROCKER_RATIO
	var port_in := PI * pow(EngineSpecs.INTAKE_VALVE_DIAMETER, 2) * 0.25
	var port_ex := PI * pow(EngineSpecs.EXHAUST_VALVE_DIAMETER, 2) * 0.22
	var woschni := 3.26 * pow(EngineSpecs.BORE, -0.2)
	var leak_base := EngineSpecs.BLOWBY_AREA
	var spark_at := 2.0 * PI - ignition.advance_deg * DEG
	var trap_mark := PI + (EngineSpecs.IVC_ABDC + 8.0) * DEG
	Gas._ensure_table()
	var psi_tab := Gas._psi
	var psi_n := float(Gas.TABLE_SIZE)

	for c in cylinders:
		var prev_local := c.local
		c.local = fposmod(phi - c.offset, CYCLE)
		# Кинематика: ход поршня и его производные по углу.
		var a := fmod(c.local, TAU)
		var sa := sin(a)
		var ca := cos(a)
		var q := sqrt(ll * ll - rr * rr * sa * sa)
		var x := rr * (1.0 - ca) + ll - q
		var dxda := rr * sa * (1.0 + rr * ca / q)
		var d2xda := rr * ca + rr * rr * (ca * ca - sa * sa) / q + rr * rr * rr * rr * sa * sa * ca * ca / (q * q * q)
		var v_new := _v_clear + _a_piston * x
		var dv := v_new - c.v
		var m := c.m_air + c.m_fuel + c.m_burned
		var rc := (c.m_air * Gas.R_AIR + c.m_fuel * Gas.R_FUEL + c.m_burned * Gas.R_BURNED) / m
		var gamma := clampf(1.385 - 0.075 * c.m_burned / m - 0.00006 * (c.t - 300.0), 1.24, 1.40)
		var cv := rc / (gamma - 1.0)
		var u := m * cv * c.t - c.p * dv
		if c.index == 0:
			c._work_acc += c.p * dv

		# Подъём клапанов по таблицам профиля кулачка.
		var was_open := c.intake_lift > 0.0 or c.exhaust_lift > 0.0
		if timing_broken:
			# Распредвал стоит: клапаны замерли там, где их застал обрыв цепи.
			var cl := fposmod(_cam_frozen - c.offset, CYCLE)
			c.intake_lift = maxf(cam_profile(cl, true) * lift_full - lift_cut, 0.0)
			c.exhaust_lift = maxf(cam_profile(cl, false) * lift_full - lift_cut, 0.0)
			# Открытый клапан бьёт по поршню у ВМТ (выборки в поршне классики нет).
			var opened := maxf(c.intake_lift, c.exhaust_lift)
			if opened > 0.002 and x < 0.0015 and c.valve_burnt < 1.0:
				c.valve_burnt = 1.0
				c.piston_damage = minf(c.piston_damage + 0.4, 1.0)
				ev_valve_hits += 1
				_log("Клапаны %d-го цилиндра погнуты о поршень" % (c.index + 1))
		elif valve_float > 0.0:
			c.intake_lift = valve_lift(c.local, true)
			c.exhaust_lift = valve_lift(c.local, false)
		else:
			var f := c.local / CYCLE * LIFT_TABLE
			var li := mini(int(f), LIFT_TABLE - 1)
			var fr := f - li
			c.intake_lift = maxf(lerpf(_intake_table[li], _intake_table[li + 1], fr) * lift_full - lift_cut, 0.0)
			c.exhaust_lift = maxf(lerpf(_exhaust_table[li], _exhaust_table[li + 1], fr) * lift_full - lift_cut, 0.0)

		# Впускной канал: столб газа с инерцией между коллектором и клапаном.
		var rm := c.r_air + c.r_fuel + c.r_burned
		var r_r := (c.r_air * Gas.R_AIR + c.r_fuel * Gas.R_FUEL + c.r_burned * Gas.R_BURNED) / rm
		var p_r := rm * r_r * c.r_t / runner_v
		c.runner_flow += runner_k * ((im_p - p_r) - RUNNER_FRICTION * c.runner_flow * absf(c.runner_flow)) * h
		c.runner_flow *= 1.0 - RUNNER_DAMPING * h
		var dq := c.runner_flow * h
		if dq > 0.0:
			dq = minf(dq, im_m * 0.2)
			var ga := im_air / im_m
			var gf := im_fuel / im_m
			var gb := im_burned / im_m
			c.r_t = (rm * c.r_t + dq * im_t) / (rm + dq)
			c.r_air += dq * ga
			c.r_fuel += dq * gf
			c.r_burned += dq * gb
			im_in_air -= dq * ga
			im_in_fuel -= dq * gf
			im_in_burned -= dq * gb
		elif dq < 0.0:
			var back_r := minf(-dq, rm * 0.4)
			var ka_r := c.r_air / rm
			var kf_r := c.r_fuel / rm
			var kb_r := c.r_burned / rm
			c.r_air -= back_r * ka_r
			c.r_fuel -= back_r * kf_r
			c.r_burned -= back_r * kb_r
			im_in_air += back_r * ka_r
			im_in_fuel += back_r * kf_r
			im_in_burned += back_r * kb_r
		intake_audio += c.runner_flow

		# Впускной клапан: между каналом и цилиндром.
		if c.intake_lift > 0.0:
			rm = c.r_air + c.r_fuel + c.r_burned
			r_r = (c.r_air * Gas.R_AIR + c.r_fuel * Gas.R_FUEL + c.r_burned * Gas.R_BURNED) / rm
			p_r = rm * r_r * c.r_t / runner_v
			var area := minf(PI * EngineSpecs.INTAKE_VALVE_DIAMETER * c.intake_lift, port_in)
			# Расход через клапан (сопло со сжимаемостью; табличная функция расхода, без вызовов).
			var dm := 0.0
			var cda := 0.78 * area * h
			if p_r >= c.p:
				var fi := c.p / p_r * psi_n
				var ii := mini(int(fi), Gas.TABLE_SIZE - 1)
				dm = cda * p_r / sqrt(r_r * c.r_t) * lerpf(psi_tab[ii], psi_tab[ii + 1], fi - ii)
			else:
				var fi2 := p_r / c.p * psi_n
				var ii2 := mini(int(fi2), Gas.TABLE_SIZE - 1)
				dm = -cda * c.p / sqrt(rc * c.t) * lerpf(psi_tab[ii2], psi_tab[ii2 + 1], fi2 - ii2)
			var lim := 0.6 * absf(p_r - c.p) / (r_r * c.r_t / runner_v + rc * c.t / v_new)
			dm = clampf(dm, -lim, lim)
			if dm > 0.0:
				dm = minf(dm, rm * 0.5)
				var fa := c.r_air / rm
				var ff := c.r_fuel / rm
				var fb := c.r_burned / rm
				c.m_air += dm * fa
				c.m_fuel += dm * ff
				c.m_burned += dm * fb
				c.r_air -= dm * fa
				c.r_fuel -= dm * ff
				c.r_burned -= dm * fb
				u += dm * r_r * 3.5 * c.r_t  # энтальпия притока cp·T
			elif dm < 0.0:
				# Обратный выброс в канал (перекрытие клапанов, позднее закрытие впускного).
				var back := minf(-dm, m * 0.5)
				var ka := c.m_air / m
				var kf := c.m_fuel / m
				var kb := c.m_burned / m
				c.m_air -= back * ka
				c.m_fuel -= back * kf
				c.m_burned -= back * kb
				u -= back * (cv + rc) * c.t
				var rm2 := rm + back
				c.r_t = (rm * c.r_t + back * c.t * 1.15) / rm2
				c.r_air += back * ka
				c.r_fuel += back * kf
				c.r_burned += back * kb
			m = c.m_air + c.m_fuel + c.m_burned
		# Стенки канала в головке греют заряд: чем дольше газ стоит в канале
		# (низкие обороты), тем сильнее подогрев и тем хуже наполнение.
		c.r_t += (t_port - c.r_t) * minf(h * PORT_HEATING_RATE, 1.0)

		# Выпускной клапан.
		if c.exhaust_lift > 0.0:
			var area_e := minf(PI * EngineSpecs.EXHAUST_VALVE_DIAMETER * c.exhaust_lift, port_ex)
			var dme := 0.0
			var cde := 0.74 * area_e * h
			if c.p >= ex_p:
				var fe := ex_p / c.p * psi_n
				var ie := mini(int(fe), Gas.TABLE_SIZE - 1)
				dme = cde * c.p / sqrt(rc * c.t) * lerpf(psi_tab[ie], psi_tab[ie + 1], fe - ie)
			else:
				var fe2 := c.p / ex_p * psi_n
				var ie2 := mini(int(fe2), Gas.TABLE_SIZE - 1)
				dme = -cde * ex_p / sqrt(Gas.R_BURNED * ex_t) * lerpf(psi_tab[ie2], psi_tab[ie2 + 1], fe2 - ie2)
			var lim_e := 0.6 * absf(c.p - ex_p) / (rc * c.t / v_new + Gas.R_BURNED * ex_t / ex_v)
			dme = clampf(dme, -lim_e, lim_e)
			if dme > 0.0:
				dme = minf(dme, m * 0.6)
				var k := 1.0 - dme / m
				c.m_air *= k
				c.m_fuel *= k
				c.m_burned *= k
				u -= dme * (cv + rc) * c.t
				ex_in_mass += dme
				ex_in_energy += dme * c.t
			elif dme < 0.0:
				var back_e := minf(-dme, ex_mass * 0.3)
				c.m_burned += back_e
				u += back_e * 1150.0 * ex_t
				ex_in_mass -= back_e
				ex_in_energy -= back_e * ex_t
			m = c.m_air + c.m_fuel + c.m_burned

		# Посадка клапана на седло — источник клапанного стука в звуке.
		if was_open and c.intake_lift == 0.0 and c.exhaust_lift == 0.0:
			mech_audio += 1.0 + valve_clearance_extra * 6000.0

		# Утечка мимо колец, через прогар поршня или клапана, через прокладку ГБЦ (критический расход).
		if c.p > 1.9 * Gas.P_ATM or (c.plug_hole and c.p > Gas.P_ATM * 1.02):
			var leak := leak_base * (1.0 + 30.0 * c.ring_wear) + 18e-6 * c.piston_damage + 10e-6 * c.valve_burnt + 6e-6 * head_gasket_damage + (2.0e-4 if c.plug_hole else 0.0)
			var dml := minf(0.7 * leak * c.p * 0.0404 / sqrt(c.t) * h, m * 0.2)
			var kl := 1.0 - dml / m
			c.m_air *= kl
			c.m_fuel *= kl
			c.m_burned *= kl
			u -= dml * (cv + rc) * c.t

		# Теплообмен со стенками по Вошни.
		var area_wall := 2.2 * _a_piston + PI * EngineSpecs.BORE * x
		var w := 2.28 * mean_piston_speed + (3.2 * mean_piston_speed if c.burning else 0.0) + 0.3
		var hcoef := woschni * exp(0.8 * log(c.p * 0.001 * w) - 0.55 * log(c.t)) * HEAT_TRANSFER_SCALE
		var q_wall := hcoef * area_wall * (c.t - t_wall) * h
		u -= q_wall
		wall_heat += q_wall

		# Отсечка заряда и искра.
		if prev_local < trap_mark and c.local >= trap_mark:
			_on_charge_trapped(c)
		if not timing_broken and not c.spark_done and prev_local < spark_at and c.local >= spark_at and c.local < 2.5 * PI:
			_on_spark(c)
		# Сгорание по Вибе.
		if c.burning:
			var xw := clampf((c.local - c.burn_start) / c.burn_duration, 0.0, 2.0)
			var xb := 1.0 - exp(-6.9 * xw * xw * xw)
			# Детонация: интеграл задержки самовоспламенения конечного заряда.
			if xb < 0.9 and c.knock == 0.0 and c.p > 5.0 * Gas.P_ATM:
				var t_u := c.t_ivc * exp(0.22 * log(c.p / c.p_ivc))
				var tau := _knock_coef * exp(-1.7 * log(c.p / Gas.P_ATM) + 3800.0 / t_u)
				c.knock_integral += h / tau
				if c.knock_integral >= 1.0:
					c.knock = 1.0 - xb
					xb = minf(xb + c.knock, 1.0)
					knock_audio += c.knock
					c.piston_damage = minf(c.piston_damage + c.knock * c.knock * 0.002, 1.0)
			var dxb := xb - c.burn_fraction
			if dxb > 0.0:
				u += c.heat_total * dxb
				var conv_f := minf(c.fuel_to_burn * dxb, c.m_fuel)
				var conv_a := minf(c.air_to_burn * dxb, c.m_air)
				c.m_fuel -= conv_f
				c.m_air -= conv_a
				c.m_burned += conv_f + conv_a
				c.burn_fraction = xb
			if xw >= 1.6:
				c.burning = false
		if c.spark_flash > 0.0:
			c.spark_flash = maxf(c.spark_flash - h * 60.0, 0.0)

		# Новое состояние газа.
		m = maxf(c.m_air + c.m_fuel + c.m_burned, 1e-9)
		rc = (c.m_air * Gas.R_AIR + c.m_fuel * Gas.R_FUEL + c.m_burned * Gas.R_BURNED) / m
		cv = rc / (gamma - 1.0)
		c.t = clampf(u / (m * cv), 200.0, 3200.0)
		c.v = v_new
		c.p = m * rc * c.t / v_new
		if c.index == 0:
			c._peak_acc = maxf(c._peak_acc, c.p)
			var bin := int(c.local / CYCLE * TRACE_POINTS) % TRACE_POINTS
			_trace_pressure_build[bin] = c.p
			_trace_volume_build[bin] = v_new
			if prev_local > c.local:
				var tp := trace_pressure
				trace_pressure = _trace_pressure_build
				_trace_pressure_build = tp
				var tv := trace_volume
				trace_volume = _trace_volume_build
				_trace_volume_build = tv
		if prev_local > c.local:
			c.cycle_work = c._work_acc
			c.imep = c._work_acc / (_a_piston * EngineSpecs.STROKE)
			c._work_acc = 0.0
			c.peak_pressure = c._peak_acc
			c._peak_acc = 0.0

		# Моменты от давления газов и сил инерции поступательно движущихся масс.
		torque += ((c.p - Gas.P_ATM) * _a_piston - EngineSpecs.RECIP_MASS * d2xda * omega2) * dxda

	last_wall_heat = lerpf(last_wall_heat, wall_heat / h, 0.002)

	# Впускной коллектор: приток из карбюратора и неплотностей, отток в каналы.
	var fl := carb.flows(h, im_p, Gas.T_AMB, r_now)
	var air_in := fl[0] * h + carb.vacuum_leak_flow(im_p, Gas.T_AMB) * h
	var eq_in := 0.6 * Gas.equalizing_mass(Gas.P_ATM, 1e3, Gas.R_AIR * Gas.T_AMB, im_p, im_v, im_r * im_t) + 1e-12
	air_in = clampf(air_in, -eq_in, eq_in)
	var fuel_liquid := fl[1] * h
	# Плёнка топлива на стенках: часть оседает и испаряется с запаздыванием.
	var warm := clampf((thermal.t_coolant - 283.0) / 75.0, 0.0, 1.0)
	var film_share := lerpf(0.7, 0.3, warm)
	var film_tau := lerpf(2.2, 0.18, warm)
	im_film += fuel_liquid * film_share
	var evaporated := im_film * h / film_tau
	im_film -= evaporated
	im_air = maxf(im_air + air_in + im_in_air, 1e-7)
	im_fuel = maxf(im_fuel + fuel_liquid * (1.0 - film_share) + evaporated + im_in_fuel, 0.0)
	im_burned = maxf(im_burned + im_in_burned, 0.0)
	# Коллектор подогревается охлаждающей жидкостью.
	im_t = lerpf(im_t, Gas.T_AMB + 0.3 * (thermal.t_coolant - Gas.T_AMB), clampf(h * 0.5, 0.0, 1.0))
	im_m = im_air + im_fuel + im_burned
	im_r = (im_air * Gas.R_AIR + im_fuel * Gas.R_FUEL + im_burned * Gas.R_BURNED) / im_m
	im_p = im_m * im_r * im_t / im_v

	# Выпускной коллектор и глушитель.
	var ex_energy := ex_mass * ex_t + ex_in_energy
	ex_mass = maxf(ex_mass + ex_in_mass, 1e-7)
	ex_t = clampf(ex_energy / ex_mass, Gas.T_AMB, 1600.0)
	ex_t -= (ex_t - Gas.T_AMB) * h * 0.6
	ex_p = ex_mass * Gas.R_BURNED * ex_t / ex_v
	var out := Gas.orifice(0.8 * EngineSpecs.EXHAUST_SYSTEM_AREA * (1.0 - 0.9 * exhaust_clog), ex_p, ex_t, Gas.R_BURNED, Gas.P_ATM, Gas.T_AMB, Gas.R_AIR) * h
	out = clampf(out, -0.5 * Gas.equalizing_mass(Gas.P_ATM, 1e3, Gas.R_AIR * Gas.T_AMB, ex_p, ex_v, Gas.R_BURNED * ex_t), 0.6 * Gas.equalizing_mass(ex_p, ex_v, Gas.R_BURNED * ex_t, Gas.P_ATM, 1e3, Gas.R_AIR * Gas.T_AMB))
	if out < 0.0:
		ex_t = (ex_mass * ex_t - out * Gas.T_AMB) / (ex_mass - out)
	ex_mass = maxf(ex_mass - out, 1e-7)
	ex_p = ex_mass * Gas.R_BURNED * ex_t / ex_v
	ex_flow_out = out / h

	# Трение: механические потери растут с оборотами и вязкостью масла.
	var n := r_now / 1000.0
	# Механические потери по корреляции Барнса — Мосса без насосных (они считаются явно).
	var fmep := (70e3 + 11e3 * n + 2.8e3 * n * n) * _viscosity_factor
	fmep *= 1.0 + 1.5 * bearing_damage * bearing_damage
	friction_torque = fmep * EngineSpecs.displacement() / (4.0 * PI)
	accessory_torque = _alternator_drag + 0.35 + 0.00012 * r_now + thermal.oil_pressure * 2.2e-6 * clampf(n, 0.0, 6.0)
	if seized:
		friction_torque = 900.0
	var t_starter := electrical.starter_torque
	torque_gross = torque
	var t_resist := friction_torque + accessory_torque
	var net_engine := torque + t_starter - t_resist * signf(omega)
	var t_load := drivetrain.load_on_engine(h, omega, EngineSpecs.CRANK_INERTIA, net_engine)
	# Сухое трение покоя: остановившийся коленвал не стронется, пока момент мал.
	if omega < 0.6 and absf(torque + t_starter - t_load) < t_resist:
		omega = 0.0
	else:
		omega = maxf(omega + (net_engine - t_load) / EngineSpecs.CRANK_INERTIA * h, 0.0)

	# Средние за цикл показатели.
	_cycle_torque_acc += (torque - t_resist) * h
	_cycle_time_acc += h
	_cycle_angle_acc += d_phi
	_cycle_air_acc += air_in
	_cycle_fuel_acc += fuel_liquid
	if _cycle_angle_acc >= CYCLE or _cycle_time_acc > 0.5:
		_close_cycle()

	if record_audio:
		mech_audio += bearing_damage * 3.0 * maxf(sin(phi * 2.0), 0.0)
		audio_exhaust.append(ex_flow_out)
		audio_intake.append(intake_audio)
		audio_knock.append(knock_audio)
		audio_mech.append(mech_audio)
		audio_dt.append(h)


func _close_cycle() -> void:
	var avg := _cycle_torque_acc / _cycle_time_acc
	torque_avg = avg
	power_avg = avg * (_cycle_angle_acc / _cycle_time_acc)
	air_mass_rate = _cycle_air_acc / _cycle_time_acc
	fuel_mass_rate = _cycle_fuel_acc / _cycle_time_acc
	var displaced_rate := EngineSpecs.displacement() * (_cycle_angle_acc / _cycle_time_acc) / CYCLE
	volumetric_efficiency = air_mass_rate / maxf(displaced_rate * Gas.P_ATM / (Gas.R_AIR * Gas.T_AMB), 1e-9)
	var lam := 0.0
	for c in cylinders:
		lam += c.trapped_lambda
	lambda_avg = lam / cylinders.size()
	exhaust_temp = ex_t
	_cycle_torque_acc = 0.0
	_cycle_time_acc = 0.0
	_cycle_angle_acc = 0.0
	_cycle_air_acc = 0.0
	_cycle_fuel_acc = 0.0


func _on_charge_trapped(c: Cylinder) -> void:
	var m := c.m_air + c.m_fuel + c.m_burned
	c.trapped_air = c.m_air
	c.residual = c.m_burned / m
	c.t_ivc = c.t
	c.p_ivc = c.p
	c.last_knock = c.knock
	c.knock_integral = 0.0
	c.knock = 0.0
	c.spark_done = false
	c.burning = false
	c.burn_fraction = 0.0
	# Испаряемость топлива на холодном двигателе — часть его не участвует в горении.
	var vap := lerpf(0.62, 1.0, smoothstep(253.0, 338.0, thermal.t_coolant))
	c.trapped_lambda = minf(c.m_air / maxf(c.m_fuel * vap * EngineSpecs.AFR_STOICH, 1e-12), 20.0)
	# Антифриз из пробитой прокладки гасит горение в цилиндре.
	if head_gasket_damage > 0.6 and (c.index == 1 or c.index == 2):
		c.trapped_lambda = 9.0


func _on_spark(c: Cylinder) -> void:
	c.spark_done = true
	var lam := c.trapped_lambda
	var energy := ignition.spark_energy_mj if ignition.wire_connected[c.index] else 0.0
	var need := Ignition.required_energy_mj(lam, c.residual, ignition.plug_gap_mm[c.index])
	var lean_limit := 1.55 - 1.4 * maxf(c.residual - 0.08, 0.0)
	# Предел воспламенения богатой смеси с горячими остаточными газами — λ≈0,42.
	var ok := energy >= need and lam > 0.42 and lam < lean_limit
	# Контакты прерывателя на высоких оборотах подпрыгивают — искра пропадает.
	var bounce := smoothstep(EngineSpecs.POINTS_BOUNCE_RPM, EngineSpecs.POINTS_BOUNCE_RPM + 900.0, rpm())
	if bounce > 0.0 and _rng.randf() < bounce * 0.95:
		ok = false
	ok = ok and c.trapped_air > 1e-6
	c.misfire = not ok
	c.last_misfire = not ok
	if not ok:
		ev_misfires += 1
		return
	ev_fires += 1
	c.spark_flash = 1.0
	var vap := lerpf(0.62, 1.0, smoothstep(253.0, 338.0, thermal.t_coolant))
	var fuel_avail := c.m_fuel * vap
	var eff := 0.95  # несгоревшие углеводороды в щелях и пристеночном слое
	if lam < 1.0:
		var d := 1.0 - lam
		eff = (1.0 - 2.2 * d * d - 0.35 * d) * 0.95
	c.heat_total = fuel_avail * EngineSpecs.FUEL_LHV * eff * (1.0 - 0.6 * maxf(c.residual - 0.2, 0.0))
	c.fuel_to_burn = c.m_fuel
	c.air_to_burn = minf(c.m_air, fuel_avail * EngineSpecs.AFR_STOICH)
	# Продолжительность сгорания: состав смеси, остаточные газы, турбулентность.
	var r := rpm()
	var dur := 44.0 * (1.0 + 3.0 * pow(lam - 0.88, 2.0)) * (1.0 + 2.2 * c.residual) * pow(maxf(r, 300.0) / 2000.0, 0.22)
	if thermal.t_coolant < 323.0:
		dur *= 1.15
	dur *= 1.0 + cycle_variation * _rng.randfn(0.0, 1.0)
	c.burn_duration = clampf(dur, 28.0, 140.0) * DEG
	c.burn_start = c.local + 6.0 * DEG  # задержка воспламенения
	c.burning = true
	c.burn_fraction = 0.0


# --- Удобные показатели для интерфейса -------------------------------------

func manifold_vacuum_kpa() -> float:
	return (Gas.P_ATM - im_p) / 1000.0


func fuel_consumption_lph() -> float:
	return fuel_mass_rate / EngineSpecs.FUEL_DENSITY * 3600.0 * 1000.0


func bsfc() -> float:
	if power_avg < 500.0:
		return 0.0
	return fuel_mass_rate * 3.6e9 / power_avg  # г/кВт·ч


func can_run_reason() -> String:
	if seized:
		return "двигатель заклинил"
	if timing_broken:
		return "сорвана цепь ГРМ — распредвал не вращается, клапаны погнуты"
	return ""
