class_name Car
extends RigidBody3D

# ВАЗ-2106 на дороге.
# Кузов — твёрдое тело (подрессоренная масса). Каждое колесо — отдельная
# неподрессоренная масса на своей пружине и амортизаторе (с разной силой на сжатие
# и отбой, отбойниками хода), шина — вертикальная пружина с демпфированием и
# огибающей пятна контакта. Спереди — независимая двухрычажная подвеска со
# стабилизатором, сзади — неразрезной мост на пяти тягах (крены моста видны,
# силы считаются по колёсам). Продольные силы шин — из VehicleDynamics,
# боковые — по углу увода с ограничением кругом трения.

const WHEELBASE := 2.424
const TRACK_F := 1.365
const TRACK_R := 1.321
const CG_HEIGHT := 0.55
const FRONT_SHARE := 0.53
const SPRUNG_MASS := 984.0
const UNSPRUNG: Array[float] = [30.0, 30.0, 38.0, 38.0]
# Подвеска «классики» мягкая: собственная частота кузова около 1,15 Гц спереди
# и 1,3 Гц сзади, амортизаторы — около 0,3 критического на сжатие и 0,55 на отбой.
# Значения по умолчанию; в «Гараже» их можно менять.
const SPRING_DEFAULT: Array[float] = [13600.0, 13600.0, 15400.0, 15400.0]   # Н/м, приведённые к колесу
const BUMP_DEFAULT: Array[float] = [1130.0, 1130.0, 1100.0, 1100.0]          # сжатие, Н·с/м
const REBOUND_DEFAULT: Array[float] = [2100.0, 2100.0, 2000.0, 2000.0]       # отбой, Н·с/м
const TRAVEL_UP: Array[float] = [0.09, 0.09, 0.11, 0.11]          # ход сжатия до отбойника
const TRAVEL_DOWN: Array[float] = [0.11, 0.11, 0.12, 0.12]        # ход отбоя
const ANTIROLL_DEFAULT := 9000.0
# Центры крена: передняя двухрычажная подвеска — низко, задний мост держит
# поперечная тяга (Панара) — высоко. Боковые силы шин передаются кузову здесь.
const ROLL_CENTER: Array[float] = [0.08, 0.08, 0.33, 0.33]   # над дорогой, м
const TIRE_K := 200000.0
const TIRE_C := 350.0
const REST_LEN := 0.35
const MAX_STEER := deg_to_rad(33.0)
const SUBSTEPS := 8
const SUBSTEPS_LITE := 4   # телефон: шины и подвеска вдвое реже — крен, сцепление и торможение те же, отличаются лишь пики в переходных

signal teleported

var sim_ms := 0.0      # сколько считался последний шаг двигателя (фоновый поток)
var wait_ms := 0.0     # сколько главный поток ждал этот расчёт
var sim: EngineSim
var SPRING: Array[float] = SPRING_DEFAULT.duplicate()
var BUMP_DAMP: Array[float] = BUMP_DEFAULT.duplicate()
var REBOUND_DAMP: Array[float] = REBOUND_DEFAULT.duplicate()
var ANTIROLL_FRONT := ANTIROLL_DEFAULT
var cargo_kg := 75.0          # водитель и груз сверх снаряжённой массы
var steer_assist := true      # ограничение угла руля по скорости (для клавиатуры)
var ride_height := 0.0        # занижение (−) или лифт (+), м
var road: Road
var vd: VehicleDynamics

var steer_input := 0.0
var steer := 0.0
var throttle := 0.0

# Состояние подвески (по колёсам: 0 ЛП, 1 ПП, 2 ЛЗ, 3 ПЗ).
var mount_local: Array[Vector3] = []
var free_len: Array[float] = []
var susp_len: Array[float] = []
var susp_vel: Array[float] = []
var tire_prev: Array[float] = []
var tire_force: Array[float] = [0.0, 0.0, 0.0, 0.0]
var spring_force: Array[float] = [0.0, 0.0, 0.0, 0.0]
var contact: Array[bool] = [false, false, false, false]
var wheel_spin: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_heading: Array[float] = [0.0, 0.0, 0.0, 0.0]
var lat_force: Array[float] = [0.0, 0.0, 0.0, 0.0]
const RELAXATION_LENGTH := 0.45   # м: шине нужно прокатиться, чтобы набрать боковую силу
var slip_angle: Array[float] = [0.0, 0.0, 0.0, 0.0]
var bump_hit: Array[float] = [0.0, 0.0, 0.0, 0.0]
var accel_g := Vector3.ZERO

var body_model: CarBodyModel
var engine_mount: Node3D
# Видимая часть машины живёт отдельно от физического тела и каждый кадр ставится
# между двумя последними шагами физики — без этого на неровной частоте кадров
# машина на экране движется рывками.
var visual: Node3D
var _prev_xf := Transform3D.IDENTITY
var _curr_xf := Transform3D.IDENTITY
var _task := -1           # фоновая задача расчёта двигателя и трансмиссии
var threaded := true
var _prev_up_vel := 0.0
var _prev_vel := Vector3.ZERO
var history: Array = []   # [[t, len0..3]] для графика ходов подвески
var _hist_t := 0.0


func _init() -> void:
	var a := WHEELBASE * (1.0 - FRONT_SHARE)
	var b := WHEELBASE * FRONT_SHARE
	var wy := 0.27 - CG_HEIGHT
	mount_local = [
		Vector3(-TRACK_F * 0.5, wy + REST_LEN, -a), Vector3(TRACK_F * 0.5, wy + REST_LEN, -a),
		Vector3(-TRACK_R * 0.5, wy + REST_LEN, b), Vector3(TRACK_R * 0.5, wy + REST_LEN, b)]
	for i in 4:
		free_len.append(REST_LEN)
		susp_len.append(REST_LEN)
		susp_vel.append(0.0)
		tire_prev.append(0.0)
	retune()


# Свободная длина пружин подбирается так, чтобы под текущей массой кузов стоял
# на заданной высоте (как подбор пружин по классу при ремонте).
func retune() -> void:
	var m := SPRUNG_MASS - 75.0 + cargo_kg
	for i in 4:
		var share := FRONT_SHARE if i < 2 else 1.0 - FRONT_SHARE
		var static_load := m * 9.81 * share * 0.5
		free_len[i] = REST_LEN + ride_height + static_load / SPRING[i]
	if is_inside_tree():
		mass = m


func _ready() -> void:
	mass = SPRUNG_MASS - 75.0 + cargo_kg
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	inertia = Vector3(360.0, 1450.0, 1400.0)   # крен, рыскание, тангаж
	can_sleep = false
	# Демпфирование проекта по умолчанию (0,1) прибавляется к своему и даёт
	# невидимую силу 0,1·m·v — около 1800 Н на 60 км/ч. Сопротивления считаем сами.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.05
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.55, 0.5, 4.0)
	shape.shape = box
	shape.position = Vector3(0, 0.15, 0)
	add_child(shape)
	visual = Node3D.new()
	visual.name = "Visual"
	visual.top_level = true
	add_child(visual)
	body_model = CarBodyModel.new()
	body_model.car = self
	visual.add_child(body_model)
	engine_mount = Node3D.new()
	engine_mount.position = Vector3(0, -0.08, -1.25)
	engine_mount.rotation = Vector3(0, -PI * 0.5, 0)
	visual.add_child(engine_mount)


func place(distance: float, lateral := 1.8) -> void:
	var z := -distance
	var g := road.height(lateral, z)
	global_transform = Transform3D(Basis.IDENTITY, Vector3(lateral, g + CG_HEIGHT + 0.01, z))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for i in 4:
		susp_len[i] = REST_LEN
		susp_vel[i] = 0.0
		vd.wheel_omega[i] = 0.0
	steer = 0.0
	history.clear()
	_prev_xf = global_transform
	_curr_xf = global_transform
	teleported.emit()


func speed_kmh() -> float:
	return -linear_velocity.dot(global_basis.z) * 3.6


func _physics_process(delta: float) -> void:
	if sim == null:
		return
	vd = sim.drivetrain.vehicle
	# Сначала дожидаемся фонового расчёта прошлого шага: дальше пишем ему новые входы.
	finish_sim()
	_prev_xf = _curr_xf
	_curr_xf = global_transform
	# Руль: скорость поворота ограничена, на скорости угол уменьшается.
	var v := linear_velocity.length()
	var max_steer := MAX_STEER
	if steer_assist:
		# Не больше угла, дающего около 0,8 g в установившемся повороте:
		# с клавиатуры иначе руль на скорости «втыкается» до упора.
		max_steer = minf(MAX_STEER, atan(WHEELBASE * 8.0 / maxf(v * v, 1.0)))
	var steer_rate := 1.3 if steer_assist else 2.5
	steer = move_toward(steer, steer_input * max_steer, delta * steer_rate)
	vd.update_controls(delta)
	vd.throttle_demand = throttle
	vd.engine_rpm = sim.rpm()

	var basis := global_basis
	var up := basis.y
	var fwd_body := -basis.z
	var up_vel := linear_velocity.dot(up)
	var a_up := (up_vel - _prev_up_vel) / delta
	_prev_up_vel = up_vel
	accel_g = basis.inverse() * ((linear_velocity - _prev_vel) / delta) / 9.81
	_prev_vel = linear_velocity

	# Колея и рулевые углы (Аккерман).
	var a := WHEELBASE
	for i in 4:
		wheel_heading[i] = 0.0
	if absf(steer) > 1e-4:
		var radius := a / tan(absf(steer))
		var inner := atan(a / (radius - TRACK_F * 0.5))
		var outer := atan(a / (radius + TRACK_F * 0.5))
		if steer > 0.0:   # вправо
			wheel_heading[1] = inner
			wheel_heading[0] = outer
		else:
			wheel_heading[0] = -inner
			wheel_heading[1] = -outer

	# Вертикальная динамика колёс на подшагах.
	var substeps := SUBSTEPS_LITE if MeshUtil.lite else SUBSTEPS
	var h := delta / substeps
	var spring_acc: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var tire_acc: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var origin := global_position
	for s in substeps:
		var forces: Array[float] = [0.0, 0.0, 0.0, 0.0]
		for i in 4:
			var l := susp_len[i]
			var lv := susp_vel[i]
			var f := SPRING[i] * (free_len[i] - l)
			f -= (BUMP_DAMP[i] if lv < 0.0 else REBOUND_DAMP[i]) * lv
			# Отбойники сжатия (резиновые, прогрессивные) и ограничитель отбоя.
			var lmin: float = REST_LEN - TRAVEL_UP[i]
			var lmax: float = REST_LEN + TRAVEL_DOWN[i]
			if l < lmin:
				var dd := lmin - l
				f += 250000.0 * dd + 3.0e6 * dd * dd + 4000.0 * maxf(-lv, 0.0)
				bump_hit[i] = 1.0
			if l > lmax:
				f -= 400000.0 * (l - lmax) + 3000.0 * maxf(lv, 0.0)
			forces[i] = f
		# Стабилизатор поперечной устойчивости спереди: подпирает сжатую сторону
		# и тянет вниз разгруженную (сжатая — та, у которой подвеска короче).
		var arb := ANTIROLL_FRONT * (susp_len[1] - susp_len[0])
		forces[0] += arb
		forces[1] -= arb
		for i in 4:
			var mount_w := origin + basis * mount_local[i]
			var center := mount_w - up * susp_len[i]
			var hd := Vector2(fwd_body.x, fwd_body.z).normalized()
			var ground := road.tire_height(center.x, center.z, hd)
			var defl := EngineSpecs.WHEEL_RADIUS - (center.y - ground)
			var dv := (defl - tire_prev[i]) / h
			tire_prev[i] = defl
			var ft := 0.0
			if defl > 0.0:
				ft = maxf(TIRE_K * defl + TIRE_C * dv, 0.0)
			var m: float = UNSPRUNG[i]
			# Ускорение колеса относительно кузова вдоль оси подвески (вниз — плюс).
			var acc := (forces[i] - ft * up.y + m * 9.81 * up.y) / m + a_up
			susp_vel[i] += acc * h
			susp_len[i] += susp_vel[i] * h
			spring_acc[i] += forces[i] / substeps
			tire_acc[i] += ft / substeps
	for i in 4:
		spring_force[i] = spring_acc[i]
		tire_force[i] = tire_acc[i]
		contact[i] = tire_force[i] > 1.0
		bump_hit[i] = maxf(bump_hit[i] - delta * 4.0, 0.0)

	# Продольные силы считает трансмиссия на мелком шаге — сначала передаём ей
	# нагрузки и скорости пятен, затем двигаем модель двигателя на этот кадр.
	var contact_vel: Array[Vector3] = []
	var fwd_g: Array[Vector3] = []
	var side_g: Array[Vector3] = []
	var contact_pt: Array[Vector3] = []
	for i in 4:
		var mount_w := origin + basis * mount_local[i]
		var center := mount_w - up * susp_len[i]
		var n := road.normal(center.x, center.z)
		var p := center - n * (EngineSpecs.WHEEL_RADIUS - maxf(tire_prev[i], 0.0))
		var hdg := fwd_body.rotated(up, -wheel_heading[i])
		var fg := (hdg - n * hdg.dot(n)).normalized()
		var sg := fg.cross(n).normalized()
		var vc := linear_velocity + angular_velocity.cross(p - origin)
		contact_vel.append(vc)
		fwd_g.append(fg)
		side_g.append(sg)
		contact_pt.append(p)
		vd.fz[i] = tire_force[i]
		vd.v_long[i] = vc.dot(fg)
		vd.mu[i] = road.friction(p.x, p.z)
	# Двигатель с трансмиссией считаются в фоновом потоке параллельно отрисовке.
	# Здесь забираем результат прошлого шага и сразу запускаем следующий —
	# главный поток не простаивает, а шаги физики остаются равномерными.
	var fx := vd.take_forces().duplicate()
	if threaded:
		_task = WorkerThreadPool.add_task(_advance_timed.bind(delta), true, "Расчёт двигателя")
	else:
		sim.advance(delta)
		sim.publish()
	for i in 4:
		# Пружина давит на кузов в точке крепления.
		var mount_w := origin + basis * mount_local[i]
		apply_force(up * spring_force[i], mount_w - origin)
		if not contact[i]:
			lat_force[i] = 0.0
			continue
		var vc := contact_vel[i]
		var vl := vc.dot(fwd_g[i])
		var vs := vc.dot(side_g[i])
		var load := tire_force[i]
		var mu := vd.mu[i]
		var alpha := atan2(vs, maxf(absf(vl), 0.6))
		slip_angle[i] = alpha
		var fy := -load * mu * VehicleDynamics.pacejka(alpha, 8.5, 1.4, -0.5)
		# На малой скорости угол увода не определён — гасим боковое скольжение демпфером.
		var low := clampf(1.0 - absf(vl) / 2.5, 0.0, 1.0)
		fy = lerpf(fy, clampf(-vs * 9000.0, -mu * load, mu * load), low)
		# Запаздывание боковой силы: каркас шины деформируется по мере качения.
		var relax := clampf(maxf(absf(vl), 2.0) * delta / RELAXATION_LENGTH, 0.0, 1.0)
		fy = lerpf(lat_force[i], fy, relax)
		var fxi := fx[i]
		# На малой скорости сила трения колеса не должна разворачивать скорость за шаг:
		# иначе машина на тормозе раскачивается вперёд-назад. Ограничиваем её тем,
		# что гасит скорость пятна ровно до нуля, и добавляем удержание на уклоне.
		var wheel_locked := absf(vd.wheel_omega[i]) < 0.05 and (vd.brake > 0.05 or vd.handbrake > 0.05 and i >= 2)
		if absf(vl) < 1.5:
			var m_share := mass * 0.25
			var stop_force := m_share * absf(vl) / delta * 0.7
			# Ограничиваем только тормозящую силу (колесо медленнее машины или стоит).
			# Если колесо раскручено двигателем в обратную сторону — это тяга,
			# она должна разворачивать машину (откатилась вперёд — уезжает назад).
			var spin_v := vd.wheel_omega[i] * EngineSpecs.WHEEL_RADIUS
			var driven_back := signf(spin_v) == signf(fxi) and absf(spin_v) > 0.15
			if fxi * vl < 0.0 and not driven_back:
				fxi = clampf(fxi, -stop_force, stop_force)
			if wheel_locked and absf(vl) < 0.3:
				var slope_pull := m_share * Vector3(0, -9.81, 0).dot(fwd_g[i])
				fxi = clampf(-slope_pull - vl * m_share / delta * 0.7, -mu * load, mu * load)
		var total := sqrt(fxi * fxi + fy * fy)
		var limit := mu * load * 1.05
		if total > limit:
			fy *= limit / total
		lat_force[i] = fy
		# Продольная сила — в пятне контакта (клевки и приседания), боковая — на высоте
		# центра крена соответствующей оси.
		apply_force(fwd_g[i] * fxi, contact_pt[i] - origin)
		apply_force(side_g[i] * fy, contact_pt[i] + up * ROLL_CENTER[i] - origin)
	# Аэродинамика.
	apply_central_force(-linear_velocity * linear_velocity.length() * 0.5 * 1.2 * EngineSpecs.DRAG_AREA)
	# Вращение колёс для картинки.
	for i in 4:
		wheel_spin[i] = fmod(wheel_spin[i] + vd.wheel_omega[i] * delta, TAU)
	_hist_t += delta
	if history.size() == 0 or _hist_t - history[history.size() - 1][0] > 0.02:
		history.append([_hist_t, susp_len[0] - REST_LEN, susp_len[1] - REST_LEN, susp_len[2] - REST_LEN, susp_len[3] - REST_LEN])
		while history.size() > 300:
			history.pop_front()


# Положение центра колеса в координатах кузова.
func wheel_center_local(i: int) -> Vector3:
	return mount_local[i] - Vector3(0, susp_len[i], 0)


func roll_deg() -> float:
	return rad_to_deg(asin(clampf(global_basis.x.y, -1.0, 1.0)))


func pitch_deg() -> float:
	return rad_to_deg(asin(clampf(-global_basis.z.y, -1.0, 1.0)))


func _process(_delta: float) -> void:
	var k := Engine.get_physics_interpolation_fraction()
	visual.global_transform = _prev_xf.interpolate_with(_curr_xf, k)
	body_model.update_pose()


# Шаг двигателя в фоне с замером: счётчик производительности показывает его отдельно.
func _advance_timed(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	sim.advance(delta)
	sim_ms = (Time.get_ticks_usec() - t0) / 1000.0


# Дожидается фонового расчёта и передаёт его результаты главному потоку.
func finish_sim() -> void:
	if _task >= 0:
		var t0 := Time.get_ticks_usec()
		WorkerThreadPool.wait_for_task_completion(_task)
		wait_ms = (Time.get_ticks_usec() - t0) / 1000.0
		_task = -1
		sim.publish()


func _exit_tree() -> void:
	finish_sim()