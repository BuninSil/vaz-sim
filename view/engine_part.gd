class_name EnginePart
extends Node3D

# Деталь или узел двигателя, которую можно снять и поставить обратно.
# Геометрия и вложенные детали лежат в content — его двигает кинематика,
# а сам узел двигает анимация разборки.

signal state_changed(part: EnginePart)

var id := ""
var title := ""
var description := ""
var specs := ""
var group := ""
var requires: PackedStringArray = []   # что нужно снять раньше
var offset := Vector3.UP * 0.3          # куда уезжает деталь при снятии (мировые координаты)
var critical := true                    # без неё двигатель не запустится
var removed := false
var animating := false
var content: Node3D

var _home_parent: Node3D
var _home_transform := Transform3D.IDENTITY
var _tween: Tween
var _highlight := ""


func _init(p_id := "", p_title := "") -> void:
	id = p_id
	title = p_title
	name = p_id
	content = Node3D.new()
	content.name = "Content"
	add_child(content)


func add(node: Node3D) -> Node3D:
	content.add_child(node)
	return node


# Где деталь стоит на двигателе (для снятой — куда она вернётся).
func home_parent() -> Node:
	if removed and _home_parent != null:
		return _home_parent
	return get_parent()


# Сам узел или какой-нибудь его предок снят с двигателя.
func is_detached() -> bool:
	var n: Node = self
	while n != null:
		if n is EnginePart and (n as EnginePart).removed:
			return true
		n = n.get_parent()
	return false


func sub_parts() -> Array[EnginePart]:
	var out: Array[EnginePart] = []
	_collect_parts(content, out)
	return out


func _collect_parts(n: Node, out: Array[EnginePart]) -> void:
	for c in n.get_children():
		if c is EnginePart:
			out.append(c)
		else:
			_collect_parts(c, out)


# Меши, принадлежащие именно этой детали (без вложенных деталей).
func own_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(content, out)
	return out


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if c is EnginePart:
			continue
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)


func set_highlight(mode: String) -> void:
	if mode == _highlight:
		return
	_highlight = mode
	var overlay: Material = null
	if mode == "hover":
		overlay = MeshUtil.material("highlight")
	elif mode == "blocked":
		overlay = MeshUtil.material("blocked")
	for m in own_meshes():
		m.material_overlay = overlay


# Снять деталь: переносим её в корень модели и уводим в сторону.
func detach(root: Node3D, duration := 0.7, target := Vector3.INF) -> void:
	if removed:
		return
	removed = true
	_home_parent = get_parent()
	_home_transform = transform
	var g := global_transform
	_home_parent.remove_child(self)
	root.add_child(self)
	global_transform = g
	if target == Vector3.INF:
		target = global_position + offset
	_animate(target, duration)
	state_changed.emit(self)


# Габариты детали вместе с вложенными узлами в мировых координатах.
func world_aabb() -> AABB:
	var box := AABB()
	var first := true
	for m in _all_meshes(self):
		if m.mesh == null:
			continue
		var b := m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out


# Поставить деталь на место.
func attach(duration := 0.7) -> void:
	if not removed:
		return
	removed = false
	var home_global := _home_parent.global_transform * _home_transform
	_animate(home_global.origin, duration, func() -> void:
		var parent := get_parent()
		if parent != null:
			parent.remove_child(self)
		_home_parent.add_child(self)
		transform = _home_transform
	)
	state_changed.emit(self)


func _animate(target: Vector3, duration: float, done: Callable = Callable()) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	animating = true
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "global_position", target, duration)
	_tween.tween_callback(func() -> void:
		animating = false
		if done.is_valid():
			done.call()
	)


# Пересечение луча с габаритами собственных мешей; возвращает расстояние или -1.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	var best := -1.0
	for m in own_meshes():
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var inv := m.global_transform.affine_inverse()
		var o := inv * origin
		var d := inv.basis * dir
		var aabb := m.mesh.get_aabb()
		var hit = aabb.intersects_ray(o, d)
		if hit != null:
			var dist := origin.distance_to(m.global_transform * (hit as Vector3))
			if best < 0.0 or dist < best:
				best = dist
	return best
