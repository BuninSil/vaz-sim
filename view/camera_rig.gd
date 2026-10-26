class_name CameraRig
extends Node3D

# Орбитальная камера: правая или средняя кнопка — вращать, Shift+ПКМ или СКМ — сдвигать,
# колесо — приближать. Клавиши 1–6 — готовые ракурсы.
# На телефоне: один палец — вращать (в салоне — оглядеться), два пальца — щипок, масштаб.

var yaw := -0.75
var pitch := -0.35
var distance := 1.25
var target := Vector3(0.0, 0.12, 0.0)
var camera: Camera3D

var _goal_yaw := yaw
var _goal_pitch := pitch
var _goal_distance := distance
var _goal_target := target
var _dragging := false
var _panning := false
var follow: Node3D            # машина, за которой следует камера
var follow_auto_yaw := true   # камера сама заходит за корму
var _free_timer := 0.0
var _follow_pos := Vector3.ZERO
# Режим на трассе: 0 — за машиной, 1 — из салона (место водителя), 2 — кино.
var mode := 0
var cockpit_xf: Callable          # -> Transform3D глаз водителя в мире
var cinematic: Cinematic
var _head := Vector2.ZERO          # повороты головы в салоне (рысканье, наклон)
var _cine_spot := Vector3.ZERO
var _cine_look := Vector3.ZERO
var _cine_kind := 0
var _cine_side := 1.0
var _cine_rng := RandomNumberGenerator.new()
var _touches := {}                # индекс пальца → точка, только касания мимо интерфейса
var _pinch := 0.0
var touch_blocked: Callable       # (Vector2) -> bool: касание пришлось на интерфейс

const VIEWS := {
	"Общий вид": [-0.75, -0.35, 1.25, Vector3(0.0, 0.12, 0.0)],
	"Спереди (привод ГРМ)": [-1.57, -0.12, 0.95, Vector3(-0.2, 0.15, 0.0)],
	"Слева (впуск/выпуск)": [0.0, -0.18, 1.0, Vector3(0.0, 0.2, 0.05)],
	"Справа (зажигание)": [PI, -0.2, 1.0, Vector3(0.0, 0.15, -0.05)],
	"Сверху (ГРМ, клапаны)": [-0.6, -1.25, 0.8, Vector3(0.0, 0.3, 0.0)],
	"Снизу (коленвал)": [-0.7, 0.9, 0.9, Vector3(0.0, 0.0, 0.0)],
}


func _ready() -> void:
	# Камера обновляется после всех остальных узлов, когда машина уже стоит
	# на своём месте в этом кадре.
	process_priority = 1000
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.near = 0.01
	camera.far = 50.0
	add_child(camera)
	camera.current = true
	_apply()


func set_view(view_name: String) -> void:
	var v: Array = VIEWS[view_name]
	_goal_yaw = v[0]
	_goal_pitch = v[1]
	_goal_distance = v[2]
	_goal_target = v[3]


func focus_on(point: Vector3) -> void:
	_goal_target = point
	_goal_distance = minf(_goal_distance, 0.7)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed and (mb.shift_pressed or mb.button_index == MOUSE_BUTTON_MIDDLE)
			_dragging = mb.pressed and not _panning
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and not (touch_blocked.is_valid() and touch_blocked.call(st.position)):
			_touches[st.index] = st.position
		elif not st.pressed:
			_touches.erase(st.index)
		_pinch = _pinch_span()
		_dragging = _touches.size() == 1
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _touches.has(sd.index):
			return
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			_look(sd.relative * 1.4)
		elif _touches.size() == 2:
			var span := _pinch_span()
			if _pinch > 1.0 and span > 1.0:
				_zoom(_pinch / span)
			_pinch = span
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and _touches.is_empty():
			_look(mm.relative)
		elif _panning:
			var b := camera.global_transform.basis
			_goal_target += (-b.x * mm.relative.x + b.y * mm.relative.y) * 0.0012 * _goal_distance


func _notification(what: int) -> void:
	# Свернули приложение с пальцем на экране — отпускания уже не придёт.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _touches.is_empty():
		_touches.clear()
		_dragging = false


func _look(rel: Vector2) -> void:
	if mode == 1:
		_head.x = clampf(_head.x - rel.x * 0.005, -2.2, 2.2)
		_head.y = clampf(_head.y - rel.y * 0.005, -0.9, 0.7)
	else:
		_goal_yaw -= rel.x * 0.006
		_goal_pitch = clampf(_goal_pitch - rel.y * 0.006, -1.5, 1.5)


func _zoom(k: float) -> void:
	_goal_distance = clampf(_goal_distance * k, 0.25, 25.0 if follow != null else 4.0)


func _pinch_span() -> float:
	if _touches.size() != 2:
		return 0.0
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1])


func start_follow(node: Node3D) -> void:
	follow = node
	_follow_pos = node.global_position + Vector3(0, 0.45, 0)
	var back := node.global_basis.z
	yaw = atan2(back.x, back.z)
	_goal_yaw = yaw
	_goal_distance = 6.5
	_goal_pitch = -0.28
	camera.far = 600.0


func stop_follow() -> void:
	follow = null
	set_mode(0)
	camera.far = 50.0
	set_view("Общий вид")


func _process(delta: float) -> void:
	# Экспоненциальное сглаживание не зависит от частоты кадров.
	var k := 1.0 - exp(-delta * 8.0)
	if follow != null and mode == 1 and cockpit_xf.is_valid():
		_cockpit(delta)
		return
	if follow != null and mode == 2:
		_cinema(delta)
		return
	if follow != null:
		var ft := follow.global_transform
		var p := ft.origin + Vector3(0, 0.45, 0)
		# По горизонтали камера держится за машиной плотно, по вертикали — мягко:
		# толчки подвески на кочках не должны трясти картинку.
		var kh := 1.0 - exp(-delta * 14.0)
		var kv := 1.0 - exp(-delta * 3.0)
		_follow_pos.x = lerpf(_follow_pos.x, p.x, kh)
		_follow_pos.z = lerpf(_follow_pos.z, p.z, kh)
		_follow_pos.y = lerpf(_follow_pos.y, p.y, kv)
		_free_timer -= delta
		if follow_auto_yaw and not _dragging and _free_timer <= 0.0:
			# Курс берём по горизонтальной проекции и сглаживаем медленно —
			# рыскание кузова на неровностях камеру не раскачивает.
			var back := ft.basis.z
			var heading := atan2(back.x, back.z)
			_goal_yaw = lerp_angle(_goal_yaw, heading, 1.0 - exp(-delta * 1.8))
		if _dragging:
			_free_timer = 2.5
		yaw = lerp_angle(yaw, _goal_yaw, 1.0 - exp(-delta * 10.0))
		pitch = lerpf(pitch, _goal_pitch, k)
		distance = lerpf(distance, _goal_distance, k)
		target = _follow_pos
		_apply()
		if cinematic != null:
			cinematic.focus(camera, distance, 0.35)
		return
	yaw = lerp_angle(yaw, _goal_yaw, k)
	pitch = lerpf(pitch, _goal_pitch, k)
	distance = lerpf(distance, _goal_distance, k)
	target = target.lerp(_goal_target, k)
	_apply()


func _apply() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
	camera.global_position = target + dir * distance
	camera.look_at(target, Vector3.UP)


func set_mode(m: int) -> void:
	mode = m
	_head = Vector2.ZERO
	camera.fov = 45.0
	camera.near = 0.01 if m == 1 else 0.05
	_cine_spot = Vector3.ZERO
	if cinematic != null:
		cinematic.set_bars(m == 2)


# Вид с места водителя: голова слегка покачивается вместе с кузовом.
func _cockpit(_delta: float) -> void:
	var xf: Transform3D = cockpit_xf.call()
	var b := xf.basis * Basis(Vector3.UP, _head.x) * Basis(Vector3.RIGHT, _head.y)
	camera.global_transform = Transform3D(b.orthonormalized(), xf.origin)
	camera.fov = 68.0
	if cinematic != null:
		cinematic.focus(camera, 1.0, 0.0)


# Кинокамера: «оператор» стоит у обочины впереди машины и ведёт её длинным
# объективом; когда машина проезжает мимо, переходит на новую точку.
func _cinema(delta: float) -> void:
	var car_pos := follow.global_position + Vector3(0, 0.25, 0)
	var fwd := -follow.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var rel := car_pos - _cine_spot
	var passed := _cine_spot == Vector3.ZERO or rel.dot(fwd) > 22.0 or rel.length() > 90.0
	if passed:
		_cine_kind = _cine_rng.randi() % 4
		_cine_side = -_cine_side
		var ahead := _cine_rng.randf_range(25.0, 55.0)
		var side := Vector3(-fwd.z, 0, fwd.x) * _cine_side
		match _cine_kind:
			0:   # низкая точка у обочины
				_cine_spot = car_pos + fwd * ahead + side * _cine_rng.randf_range(5.0, 8.0) + Vector3(0, -0.15, 0)
			1:   # с пригорка
				_cine_spot = car_pos + fwd * ahead + side * _cine_rng.randf_range(10.0, 18.0) + Vector3(0, 4.5, 0)
			2:   # почти в лоб, издалека
				_cine_spot = car_pos + fwd * (ahead + 25.0) + side * 2.5 + Vector3(0, 0.6, 0)
			3:   # проводка рядом: камера едет параллельно
				_cine_spot = car_pos + side * 6.0 + Vector3(0, 0.9, 0)
		_cine_look = car_pos
	if _cine_kind == 3:
		# Камера на «машине сопровождения»: держит дистанцию сбоку.
		var side3 := Vector3(-fwd.z, 0, fwd.x) * _cine_side
		var want := car_pos + side3 * 6.0 - fwd * 1.5 + Vector3(0, 0.9, 0)
		_cine_spot = _cine_spot.lerp(want, 1.0 - exp(-delta * 3.0))
	_cine_look = _cine_look.lerp(car_pos, 1.0 - exp(-delta * 6.0))
	camera.global_position = _cine_spot
	camera.look_at(_cine_look, Vector3.UP)
	var dist := _cine_spot.distance_to(car_pos)
	# Длинный фокус: машина занимает примерно треть кадра на любом расстоянии.
	camera.fov = clampf(rad_to_deg(2.0 * atan(5.5 / maxf(dist, 1.0))), 8.0, 55.0)
	if cinematic != null:
		cinematic.focus(camera, dist, 1.0)
