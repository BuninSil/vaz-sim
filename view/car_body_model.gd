class_name CarBodyModel
extends Node3D

# Внешний вид автомобиля и подвижные узлы ходовой части.
# Координаты — в системе кузова (центр масс в начале, вперёд -Z, вправо +X).

var car: Car
var body: Node3D
var body_materials: Array[StandardMaterial3D] = []
var wheels: Array[Node3D] = []
var wheel_spin_nodes: Array[Node3D] = []
var _links := []          # [узел, функция концов]
var _springs := []        # [пружина, верх, низ-функция]
var _axle: Node3D
var _diff: Node3D
var _prop: Node3D
var _prop_spin: Node3D
var _stab: Node3D
var _brake_lights: Array[StandardMaterial3D] = []
var xray := false
var chassis: Node3D                       # трансмиссия и выпуск — видны под любым кузовом
var model_root: Node3D                     # внешняя модель кузова (если загружена)
var model_materials: Array[StandardMaterial3D] = []

# Светотехника: 0 — выкл, 1 — габариты, 2 — ближний, 3 — дальний.
var light_mode := 0
var turn_left := false
var turn_right := false
var hazard := false
var _blink_t := 0.0
var blink_on := false     # лампы поворотников горят (для щелчков реле)
var _lamp_mats := {}      # роль -> Array[StandardMaterial3D] (секции стёкол, светящиеся своим цветом)
var _head_glass: Array[StandardMaterial3D] = []        # внешние фары: ближний + дальний (двухнитевые лампы)
var _head_glass_inner: Array[StandardMaterial3D] = []  # внутренние фары: только дальний
var _bulbs_outer: Array[OmniLight3D] = []
var _bulbs_inner: Array[OmniLight3D] = []
var _beams: Array[SpotLight3D] = []
var _high_beams: Array[SpotLight3D] = []
var _glow_lights := {}    # роль -> Array[OmniLight3D] — подсветка асфальта у фонарей
var _model_xf := Transform3D.IDENTITY   # из сантиметров модели в систему кузова
# Открывающиеся панели: имя -> {pivot, axis, max, angle, target}
var openings := {}
var interior: CarInterior

signal opening_moved(name: String, opening: bool)

# Контуры дверей сбоку (продольная координата, высота) в сантиметрах модели —
# по зазорам панелей. Петли передних дверей у передней кромки, задних — у средней стойки.
const DOOR_FRONT := [Vector2(-1.2, -20), Vector2(-1.2, 74.5), Vector2(51, 74.5), Vector2(81, 37), Vector2(85.5, 35), Vector2(88, 31), Vector2(88.5, -17), Vector2(87, -19.5), Vector2(85, -20)]
const DOOR_REAR := [Vector2(-1.2, -20), Vector2(-1.2, 74.5), Vector2(-57, 74.5), Vector2(-88, 34.5), Vector2(-86, 13), Vector2(-80, 9.5), Vector2(-71, 3), Vector2(-63, -7), Vector2(-59, -17), Vector2(-57, -20)]

const MODEL_PATH := "res://models/lada_2106.glb"
# Колёса во внешней модели: [диск, шина] по порядку ЛП, ПП, ЛЗ, ПЗ.
const MODEL_WHEELS := [["Object_29", "Object_33"], ["Object_32", "Object_36"], ["Object_30", "Object_34"], ["Object_31", "Object_35"]]
const MODEL_FRONT_AXLE_CM := 142.25
const MODEL_REAR_AXLE_CM := -96.28
const MODEL_WHEEL_Z_CM := -21.4
const MODEL_TIRE_R_CM := 27.12

const GROUND := -0.55     # уровень земли под центром масс в покое
const PAINT := Color(0.55, 0.05, 0.06)


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	chassis = Node3D.new()
	add_child(chassis)
	_build_body()
	_build_wheels()
	_build_front_suspension()
	_build_rear_axle()
	_build_driveline()
	MeshUtil.merge_static(body)
	MeshUtil.merge_static(chassis)
	for w in wheels:
		MeshUtil.merge_static(w)
	if FileAccess.file_exists(MODEL_PATH):
		_load_external_model()


# Подключает детальную модель кузова (glTF): масштабирует по колёсной базе,
# ставит колёса модели на наши колёсные узлы, правит материалы.
func _load_external_model() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(MeshUtil.raw_path(MODEL_PATH), state) != OK:
		push_warning("Не удалось загрузить модель кузова: " + MODEL_PATH)
		return
	var scene := doc.generate_scene(state) as Node3D
	if scene == null:
		return
	var sk := scene.find_child("Sketchfab_model", true, false) as Node3D
	if sk == null:
		push_warning("В модели нет узла Sketchfab_model")
		scene.queue_free()
		return
	# Исходные единицы — сантиметры, ось длины +Y, вверх +Z.
	var s := car.WHEELBASE / ((MODEL_FRONT_AXLE_CM - MODEL_REAR_AXLE_CM) * 0.01) * 0.01
	var wheel_y := 0.27 - car.CG_HEIGHT
	var front_z: float = car.mount_local[0].z
	sk.transform = Transform3D(Basis(Vector3(s, 0, 0), Vector3(0, 0, -s), Vector3(0, s, 0)), Vector3(0, wheel_y - MODEL_WHEEL_Z_CM * s, front_z + MODEL_FRONT_AXLE_CM * s))
	_model_xf = sk.transform
	add_child(scene)
	model_root = scene
	_tune_materials(scene)
	# Свои временные кузов и колёса прячем — их заменяет модель.
	body.visible = false
	for i in 4:
		for c in wheel_spin_nodes[i].get_children():
			c.queue_free()
		for c in wheels[i].get_children():
			if c != wheel_spin_nodes[i]:
				c.queue_free()
	_setup_lamps(scene, s)
	# Колпаки, диски тормозов и прочее в зоне колеса бывают слиты с кузовом в общие сетки —
	# вырезаем их треугольники в отдельные сетки, чтобы они крутились с колесом.
	var extra := _split_wheel_geometry(scene)
	# Колёса модели переезжают в наши вращающиеся узлы.
	update_pose()
	var tire_scale := EngineSpecs.WHEEL_RADIUS / (MODEL_TIRE_R_CM * s)
	for i in 4:
		var spin := wheel_spin_nodes[i]
		var box := AABB()
		var parts: Array[MeshInstance3D] = []
		var candidates: Array = []
		for nm in MODEL_WHEELS[i]:
			candidates.append(scene.find_child(nm, true, false))
		candidates.append_array(extra[i])
		var measured := 0
		for k in candidates.size():
			var m := candidates[k] as MeshInstance3D
			if m == null:
				continue
			parts.append(m)
			# Центр колеса считаем только по диску и шине — вырезанные куски его не смещают.
			if k < MODEL_WHEELS[i].size():
				var b := m.global_transform * m.mesh.get_aabb()
				box = b if measured == 0 else box.merge(b)
				measured += 1
		if parts.is_empty():
			continue
		var center_in_spin := spin.global_transform.affine_inverse() * box.get_center()
		for m in parts:
			var local := spin.global_transform.affine_inverse() * m.global_transform
			m.get_parent().remove_child(m)
			spin.add_child(m)
			local.origin -= center_in_spin
			m.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * tire_scale) * local
	_split_openings(scene)
	if MeshUtil.lite:
		var movable: Array = [interior]
		for name in openings:
			movable.append(openings[name]["pivot"])
		MeshUtil.merge_by_material(scene, movable)
		MeshUtil.merge_by_material(interior, interior.movable_parts())
		for name in openings:
			MeshUtil.merge_by_material(openings[name]["pivot"])
		MeshUtil.generate_mesh_lods(scene)
		# Тени салона и ходовой под кузовом не видны, а отрисовка теней — каждый кусок заново.
		for root in [interior, chassis]:
			for n in (root as Node).find_children("*", "GeometryInstance3D", true, false):
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Возвращает для каждого колеса список новых мешей, вырезанных из общих сеток модели.
func _split_wheel_geometry(scene: Node) -> Array:
	var centers: Array[Vector3] = []   # в исходных сантиметрах модели
	for i in 4:
		var x := -1.0 if i == 0 or i == 2 else 1.0
		var y := MODEL_FRONT_AXLE_CM if i < 2 else MODEL_REAR_AXLE_CM
		var z := MODEL_WHEEL_Z_CM if i < 2 else -23.63
		centers.append(Vector3(x, y, z))
	var out: Array = [[], [], [], []]
	var wheel_names: Array[String] = []
	for w in MODEL_WHEELS:
		wheel_names.append_array(w)
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if wheel_names.has(String(mi.name)) or mi.mesh == null:
			continue
		var new_mesh := ArrayMesh.new()
		var pieces: Array = [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]
		var moved_any := false
		for k in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(k)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(verts.size())
				for t in verts.size():
					idx[t] = t
			var keep := PackedInt32Array()
			var take: Array = [[], [], [], []]   # обычные массивы: упакованные при извлечении копируются
			for t in range(0, idx.size(), 3):
				var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
				var wheel_owner := -1
				# Только наружная часть колеса (колпак, обод, диск): рычаги подвески глубже.
				if absf(c.x) > 63.0:
					for w in 4:
						var wc: Vector3 = centers[w]
						if signf(c.x) == wc.x and Vector2(c.y - wc.y, c.z - wc.z).length() < 23.5:
							wheel_owner = w
							break
				if wheel_owner < 0:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
				else:
					(take[wheel_owner] as Array).append_array([idx[t], idx[t + 1], idx[t + 2]])
			var mat := mi.get_active_material(k)
			if not keep.is_empty():
				var a2 := arrays.duplicate()
				a2[Mesh.ARRAY_INDEX] = keep
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
				new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, mat)
			for w in 4:
				var ti := PackedInt32Array(take[w])
				if ti.is_empty():
					continue
				moved_any = true
				var a3 := arrays.duplicate()
				a3[Mesh.ARRAY_INDEX] = ti
				var pm: ArrayMesh = pieces[w]
				pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a3)
				pm.surface_set_material(pm.get_surface_count() - 1, mat)
		if not moved_any:
			continue
		mi.mesh = new_mesh
		for w in 4:
			var pm2: ArrayMesh = pieces[w]
			if pm2.get_surface_count() == 0:
				continue
			var piece := MeshInstance3D.new()
			piece.mesh = pm2
			piece.name = "%s_wheel%d" % [mi.name, w]
			mi.get_parent().add_child(piece)
			piece.transform = mi.transform
			out[w].append(piece)
	return out


# --- Двери, капот, багажник ------------------------------------------------------

# К какой открывающейся панели относится треугольник (центр в сантиметрах модели).
static func opening_of(c: Vector3) -> String:
	var side := "r" if c.x > 0.0 else "l"
	var ax := absf(c.x)
	# Капот: боковые щели на |x|≈64 см, задняя кромка у стекла выгнута дугой,
	# спереди панель загибается вниз до решётки.
	if ax < 63.8 and c.y > 110.0 - 5.5 * pow(ax / 64.0, 2.0) and c.y < 199.0 and c.z > 21.5:
		return "hood"
	if ax < 63.0 and c.y < -128.5 and c.y > -194.0 and c.z > 28.0:
		return "trunk"
	if ax > 55.0:
		var p := Vector2(c.y, c.z)
		if Geometry2D.is_point_in_polygon(p, PackedVector2Array(DOOR_FRONT)):
			return "door_f" + side
		if Geometry2D.is_point_in_polygon(p, PackedVector2Array(DOOR_REAR)):
			return "door_r" + side
		# Зеркало заднего вида стоит на передней двери.
		if ax > 80.0 and c.y > 55.0 and c.y < 92.0 and c.z > 30.0 and c.z < 62.0:
			return "door_f" + side
	return ""


func _split_openings(scene: Node) -> void:
	# Петли: точка оси (см модели), ось вращения, угол открытия.
	var hinges := {
		"door_fl": [Vector3(-77, 88, 0), Vector3(0, 0, -1), deg_to_rad(64.0)],
		"door_fr": [Vector3(77, 88, 0), Vector3(0, 0, 1), deg_to_rad(64.0)],
		"door_rl": [Vector3(-77, -1.5, 0), Vector3(0, 0, -1), deg_to_rad(62.0)],
		"door_rr": [Vector3(77, -1.5, 0), Vector3(0, 0, 1), deg_to_rad(62.0)],
		# Капот классики на петлях у решётки радиатора: поднимается кромка у лобового стекла.
		"hood": [Vector3(0, 186, 31), Vector3(-1, 0, 0), deg_to_rad(55.0)],
		"trunk": [Vector3(0, -128, 38), Vector3(-1, 0, 0), deg_to_rad(68.0)],
	}
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var parent: Node3D = null
	var pieces := {}   # имя -> ArrayMesh
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.transform.is_equal_approx(Transform3D.IDENTITY):
			continue
		var rest := ArrayMesh.new()
		var moved := false
		for k in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(k)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(verts.size())
				for t in verts.size():
					idx[t] = t
			var keep := PackedInt32Array()
			var take := {}
			var owners := _owners_by_panel(verts, idx)
			for t in range(0, idx.size(), 3):
				var owner: String = owners[t / 3]
				if owner == "":
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
				else:
					if not take.has(owner):
						take[owner] = []
					(take[owner] as Array).append_array([idx[t], idx[t + 1], idx[t + 2]])
			var mat := mi.get_active_material(k)
			if not keep.is_empty():
				var a2 := arrays.duplicate()
				a2[Mesh.ARRAY_INDEX] = keep
				rest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
				rest.surface_set_material(rest.get_surface_count() - 1, mat)
			for owner in take:
				moved = true
				var a3 := arrays.duplicate()
				a3[Mesh.ARRAY_INDEX] = PackedInt32Array(take[owner])
				if not pieces.has(owner):
					pieces[owner] = ArrayMesh.new()
				var pm: ArrayMesh = pieces[owner]
				pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a3)
				pm.surface_set_material(pm.get_surface_count() - 1, mat)
		if moved:
			mi.mesh = rest
			for k in rest.get_surface_count():
				mi.set_surface_override_material(k, null)
			parent = mi.get_parent() as Node3D
	if parent == null:
		return
	for name in pieces:
		var h: Array = hinges[name]
		var pivot := Node3D.new()
		pivot.name = name
		pivot.position = h[0]
		parent.add_child(pivot)
		var piece := MeshInstance3D.new()
		piece.mesh = pieces[name]
		piece.position = -h[0]
		pivot.add_child(piece)
		openings[name] = {"pivot": pivot, "axis": h[1], "max": h[2], "angle": 0.0, "target": 0.0}
	# В модели нет салона — строим его сами, дверные карты крепим к дверям.
	interior = CarInterior.new()
	parent.add_child(interior)
	var doors := {}
	for name in openings:
		if str(name).begins_with("door"):
			doors[name] = (openings[name]["pivot"] as Node3D).get_child(0)
	var paint_mat: Material = null
	for m in model_materials:
		if m.get_meta("paint", false):
			paint_mat = m
			break
	interior.build(doors, paint_mat)
	model_materials.append_array(interior.materials)


# Владелец каждого треугольника. Панели модели (капот, дверь, ручка) — отдельные
# связные куски сетки, разделённые зазором; если кусок почти целиком лежит в зоне
# двери или капота, он уходит туда весь — край получается точно по зазору, без «пилы».
static func _owners_by_panel(verts: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var tri_count := idx.size() / 3
	# Объединение вершин по совпадающим координатам (швы развёртки дублируют вершины).
	var key_of := {}
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var key := Vector3i(roundi(v.x * 100.0), roundi(v.y * 100.0), roundi(v.z * 100.0))
		if key_of.has(key):
			parent[i] = key_of[key]
		else:
			key_of[key] = i
			parent[i] = i
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for t in range(0, idx.size(), 3):
		var a: int = find.call(idx[t])
		for k in [1, 2]:
			var b: int = find.call(idx[t + k])
			if a != b:
				parent[b] = a
	var labels: Array = []
	labels.resize(tri_count)
	var stats := {}   # корень -> {метка: число}
	var roots := PackedInt32Array()
	roots.resize(tri_count)
	for t in tri_count:
		var c := (verts[idx[t * 3]] + verts[idx[t * 3 + 1]] + verts[idx[t * 3 + 2]]) / 3.0
		var lab := opening_of(c)
		labels[t] = lab
		var r: int = find.call(idx[t * 3])
		roots[t] = r
		if not stats.has(r):
			stats[r] = {}
		var d: Dictionary = stats[r]
		d[lab] = int(d.get(lab, 0)) + 1
	var panel_owner := {}
	for r in stats:
		var d: Dictionary = stats[r]
		var total := 0
		var best := ""
		var best_n := -1
		for lab in d:
			total += d[lab]
			if d[lab] > best_n:
				best_n = d[lab]
				best = lab
		panel_owner[r] = best if float(best_n) / total >= 0.85 else null
	for t in tri_count:
		var po = panel_owner[roots[t]]
		if po != null:
			labels[t] = po
	return labels


func toggle_opening(name: String) -> void:
	if not openings.has(name):
		return
	var o: Dictionary = openings[name]
	o["target"] = 0.0 if o["target"] > 0.0 else 1.0
	if o["target"] > 0.0:
		opening_moved.emit(name, true)


func is_open(name: String) -> bool:
	return openings.has(name) and openings[name]["angle"] > 0.01


func _update_openings(delta: float) -> void:
	for name in openings:
		var o: Dictionary = openings[name]
		var a: float = o["angle"]
		var t: float = o["target"]
		if is_equal_approx(a, t):
			continue
		a = move_toward(a, t, delta * (1.3 if t > a else 1.8))
		if t == 0.0 and a <= 0.0:
			opening_moved.emit(name, false)
		o["angle"] = a
		# Плавный старт и дотягивание до упора.
		var e := a * a * (3.0 - 2.0 * a)
		(o["pivot"] as Node3D).transform.basis = Basis(o["axis"], e * float(o["max"]))


# --- Фары и фонари -------------------------------------------------------------

# Раскладывает стёкла фонарей модели на секции по цвету рассеивателя в текстуре:
# жёлтые — поворотники, белые спереди — габариты, белые сзади — задний ход,
# красные сзади — габариты и стоп-сигналы (катафот не светится).
func _setup_lamps(scene: Node, s: float) -> void:
	var lens := scene.find_child("Object_16", true, false) as MeshInstance3D
	if lens != null:
		_split_lamp_lens(lens)
	var heads := scene.find_child("Object_28", true, false) as MeshInstance3D
	if heads != null:
		_split_headlights(heads)
	# Лампы внутри фар: маленькие источники у нитей подсвечивают отражатель.
	for side in [-1.0, 1.0]:
		for lx in [58.0, 42.0]:
			var bulb := OmniLight3D.new()
			bulb.position = _model_xf * Vector3(side * lx, 189.0, 8.4)
			bulb.omni_range = 0.14
			bulb.omni_attenuation = 1.5
			bulb.light_energy = 0.0
			bulb.light_color = Color(1.0, 0.9, 0.75)
			bulb.shadow_enabled = false
			add_child(bulb)
			(_bulbs_outer if lx > 50.0 else _bulbs_inner).append(bulb)
	# Источники света в точках ламп (координаты — в сантиметрах модели).
	for side in [-1.0, 1.0]:
		var low := SpotLight3D.new()
		low.position = _model_xf * Vector3(side * 58.0, 194.0, 8.4)
		low.rotation = Vector3(-0.06, 0, 0)
		low.spot_range = 60.0
		low.spot_angle = 36.0
		low.spot_attenuation = 0.45
		low.light_specular = 0.3
		low.light_energy = 0.0
		low.light_color = Color(1.0, 0.93, 0.8)
		low.shadow_enabled = side > 0.0
		add_child(low)
		_beams.append(low)
		var high := SpotLight3D.new()
		high.position = _model_xf * Vector3(side * 42.0, 194.0, 8.4)
		high.rotation = Vector3(-0.015, 0, 0)
		high.spot_range = 110.0
		high.spot_angle = 14.0
		high.light_energy = 0.0
		high.light_color = Color(1.0, 0.95, 0.85)
		add_child(high)
		_high_beams.append(high)
		for role in ["tail", "turn_r", "reverse"]:
			var o := OmniLight3D.new()
			o.position = _model_xf * Vector3(side * 55.0, -225.0, -12.0)   # под бампером, а не в стекле
			o.omni_range = 2.0
			o.light_energy = 0.0
			add_child(o)
			var key: String = role + ("_l" if side < 0.0 else "_r")
			_glow_lights[key] = o
		var of := OmniLight3D.new()
		of.position = _model_xf * Vector3(side * 62.0, 222.0, -16.0)
		of.omni_range = 1.6
		of.light_energy = 0.0
		add_child(of)
		_glow_lights["turn_f" + ("_l" if side < 0.0 else "_r")] = of
	update_lights(0.0, false, false)


# Стёкла четырёх фар в модели — одна сетка. Делим её на внешнюю пару (ближний и
# дальний) и внутреннюю (только дальний) по расстоянию от оси машины.
func _split_headlights(heads: MeshInstance3D) -> void:
	var outer_mesh := ArrayMesh.new()
	var inner_mesh := ArrayMesh.new()
	for k in heads.mesh.get_surface_count():
		var arrays := heads.mesh.surface_get_arrays(k)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var outer: Array = []
		var inner: Array = []
		for t in range(0, idx.size(), 3):
			var cx := absf((verts[idx[t]].x + verts[idx[t + 1]].x + verts[idx[t + 2]].x) / 3.0)
			(outer if cx > 50.0 else inner).append_array([idx[t], idx[t + 1], idx[t + 2]])
		var src := heads.get_active_material(k) as StandardMaterial3D
		var glow_tex := _headlight_glow_texture(src.albedo_texture)
		for pair in [[outer, outer_mesh, _head_glass], [inner, inner_mesh, _head_glass_inner]]:
			if (pair[0] as Array).is_empty():
				continue
			var a := arrays.duplicate()
			a[Mesh.ARRAY_INDEX] = PackedInt32Array(pair[0])
			var mesh: ArrayMesh = pair[1]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			var m := src.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			m.emission_texture = glow_tex
			m.emission = Color(1.0, 0.94, 0.82)
			m.emission_energy_multiplier = 0.0
			# Стекло остаётся гладким: блики неба поверх свечения дают ощущение стекла.
			m.roughness = 0.02
			m.metallic_specular = 0.9
			mesh.surface_set_material(mesh.get_surface_count() - 1, m)
			(pair[2] as Array).append(m)
			model_materials.append(m)
	heads.mesh = outer_mesh
	# Переопределения материалов от общей настройки перекрыли бы светящиеся материалы секций.
	for k in outer_mesh.get_surface_count():
		heads.set_surface_override_material(k, null)
	var inner_mi := MeshInstance3D.new()
	inner_mi.name = "Headlights_inner"
	inner_mi.mesh = inner_mesh
	heads.get_parent().add_child(inner_mi)
	inner_mi.transform = heads.transform


# Текстура свечения фары: ярче всего напротив лампы в центре, к ободу спадает;
# рифление рассеивателя из исходной текстуры просвечивает сквозь свечение.
func _headlight_glow_texture(lens_tex: Texture2D) -> Texture2D:
	if lens_tex == null:
		return null
	var src := lens_tex.get_image()
	if src == null:
		return lens_tex
	if src.is_compressed():
		src.decompress()
	src = src.duplicate()
	var n := 256
	src.resize(n, n, Image.INTERPOLATE_BILINEAR)
	var out := Image.create(n, n, false, Image.FORMAT_RGB8)
	# В текстуре два рассеивателя-овала: левый и правый.
	var centers := [Vector2(0.265, 0.5), Vector2(0.755, 0.5)]
	var radii := [Vector2(0.225, 0.4), Vector2(0.225, 0.41)]
	for y in n:
		for x in n:
			var uv := Vector2((x + 0.5) / n, (y + 0.5) / n)
			var best := 0.0
			for i in 2:
				var d: Vector2 = (uv - centers[i]) / radii[i]
				var r := d.length()
				if r < 1.0:
					# Мягкое пятно отражателя плюс горячая точка напротив нити.
					best = maxf(best, 0.25 + 0.6 * pow(1.0 - r, 0.9) + 1.3 * exp(-r * r * 32.0))
			var luma := src.get_pixel(x, y).get_luminance()
			var v := best * (0.55 + 0.75 * luma)
			out.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(out)


func _split_lamp_lens(lens: MeshInstance3D) -> void:
	var groups := {}   # "роль_сторона" -> {surface_index: [индексы]}
	var keep_mesh := ArrayMesh.new()
	var src_mesh := lens.mesh
	for k in src_mesh.get_surface_count():
		var mat := lens.get_active_material(k) as StandardMaterial3D
		var arrays := src_mesh.surface_get_arrays(k)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var img: Image = null
		if mat != null and mat.albedo_texture != null:
			img = mat.albedo_texture.get_image()
			if img != null and img.is_compressed():
				img.decompress()
		var keep: Array = []
		var by_role := {}
		for t in range(0, idx.size(), 3):
			var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			var uv := (uvs[idx[t]] + uvs[idx[t + 1]] + uvs[idx[t + 2]]) / 3.0 if not uvs.is_empty() else Vector2.ZERO
			var role := _lamp_role(img, uv, c)
			if role == "":
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			else:
				var key := role + ("_l" if c.x < 0.0 else "_r")
				if not by_role.has(key):
					by_role[key] = []
				(by_role[key] as Array).append_array([idx[t], idx[t + 1], idx[t + 2]])
		if not keep.is_empty():
			var a := arrays.duplicate()
			a[Mesh.ARRAY_INDEX] = PackedInt32Array(keep)
			keep_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			keep_mesh.surface_set_material(keep_mesh.get_surface_count() - 1, mat)
		for key in by_role:
			var a2 := arrays.duplicate()
			a2[Mesh.ARRAY_INDEX] = PackedInt32Array(by_role[key])
			var pm := ArrayMesh.new()
			pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
			var lm := mat.duplicate() as StandardMaterial3D
			lm.emission_enabled = true
			lm.emission_texture = lm.albedo_texture
			# Чистый цвет секции: текстура только задаёт рисунок рассеивателя,
			# иначе светлые блики рельефа при свечении уходят в белый.
			var role_name := String(key).substr(0, String(key).length() - 2)
			match role_name:
				"tail":
					lm.emission = Color(1.0, 0.03, 0.01)
				"turn_f", "turn_r", "turn_s":
					lm.emission = Color(1.0, 0.42, 0.0)
				"reverse":
					lm.emission = Color(1.0, 1.0, 0.95)
				_:
					lm.emission = Color(1.0, 0.92, 0.75)
			lm.emission_energy_multiplier = 0.0
			pm.surface_set_material(0, lm)
			var piece := MeshInstance3D.new()
			piece.mesh = pm
			piece.name = "Lamp_" + String(key)
			lens.get_parent().add_child(piece)
			piece.transform = lens.transform
			if not _lamp_mats.has(key):
				_lamp_mats[key] = []
			(_lamp_mats[key] as Array).append(lm)
			model_materials.append(lm)
	lens.mesh = keep_mesh
	for k in keep_mesh.get_surface_count():
		lens.set_surface_override_material(k, keep_mesh.surface_get_material(k))


func _lamp_role(img: Image, uv: Vector2, c: Vector3) -> String:
	if img == null:
		return ""
	var px := Vector2i(clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1), clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))
	var col := img.get_pixelv(px)
	var rear := c.y < -150.0
	var front := c.y > 150.0
	if col.v < 0.12:
		return ""
	var amber := col.s > 0.45 and col.h > 0.04 and col.h < 0.16
	var red := col.s > 0.45 and (col.h <= 0.04 or col.h > 0.93)
	var white := col.s < 0.3 and col.v > 0.35
	if amber:
		return "turn_f" if front else ("turn_r" if rear else "turn_s")
	if rear and red:
		# Нижняя полоса средней секции — катафот, он не светится.
		if uv.x > 0.19 and uv.x < 0.49 and uv.y > 0.59 and uv.y < 0.84:
			return ""
		return "tail"
	if rear and white:
		return "reverse"
	if front and white:
		return "park"
	return ""


func _set_role(role: String, energy: float) -> void:
	for side in ["_l", "_r"]:
		for m in _lamp_mats.get(role + side, []):
			(m as StandardMaterial3D).emission_energy_multiplier = energy


func _set_role_side(role: String, side: String, energy: float) -> void:
	for m in _lamp_mats.get(role + side, []):
		(m as StandardMaterial3D).emission_energy_multiplier = energy


func update_lights(delta: float, braking: bool, reversing: bool) -> void:
	var flashing := turn_left or turn_right or hazard
	# Реле включает лампы сразу при повороте рычага, затем 90 миганий в минуту.
	_blink_t = fmod(_blink_t + delta, 0.67) if flashing else 0.0
	blink_on = flashing and _blink_t < 0.36
	var parking := light_mode >= 1
	_set_role("park", 0.6 if parking else 0.0)
	# Красная секция: габарит слабее, стоп-сигнал ярко.
	_set_role("tail", 2.6 if braking else (0.8 if parking else 0.0))
	_set_role("reverse", 0.9 if reversing else 0.0)
	var left := (turn_left or hazard) and blink_on
	var right := (turn_right or hazard) and blink_on
	for role in ["turn_f", "turn_r", "turn_s"]:
		_set_role_side(role, "_l", 2.2 if left else 0.0)
		_set_role_side(role, "_r", 2.2 if right else 0.0)
	# Как на ВАЗ-2106: ближний — горят только внешние фары (нить ближнего света);
	# дальний — внешние переключаются на нить дальнего, и загораются внутренние.
	for m in _head_glass:
		m.emission_energy_multiplier = (0.0 if light_mode < 2 else (0.85 if light_mode == 2 else 1.25))
	for m in _head_glass_inner:
		m.emission_energy_multiplier = 1.25 if light_mode == 3 else 0.0
	for b in _bulbs_outer:
		b.light_energy = 0.0 if light_mode < 2 else (1.5 if light_mode == 2 else 2.2)
	for b in _bulbs_inner:
		b.light_energy = 2.2 if light_mode == 3 else 0.0
	for b in _beams:
		# Внешние фары: на ближнем пучок опущен и короче, на дальнем поднимается и бьёт дальше.
		b.light_energy = (5.0 if light_mode == 2 else 7.0) if light_mode >= 2 else 0.0
		b.rotation.x = -0.06 if light_mode == 2 else -0.02
		b.spot_range = 60.0 if light_mode == 2 else 100.0
		b.spot_angle = 36.0 if light_mode == 2 else 22.0
	for b in _high_beams:
		b.light_energy = 9.0 if light_mode == 3 else 0.0
	for side in ["_l", "_r"]:
		var lt: OmniLight3D = _glow_lights.get("tail" + side)
		if lt != null:
			lt.light_color = Color(1.0, 0.05, 0.02)
			lt.light_energy = 1.2 if braking else (0.3 if parking else 0.0)
		var lr: OmniLight3D = _glow_lights.get("reverse" + side)
		if lr != null:
			lr.light_color = Color(1, 1, 1)
			lr.light_energy = 0.8 if reversing else 0.0
		var on := left if side == "_l" else right
		for key in ["turn_r" + side, "turn_f" + side]:
			var lo: OmniLight3D = _glow_lights.get(key)
			if lo != null:
				lo.light_color = Color(1.0, 0.55, 0.05)
				lo.light_energy = 0.9 if on else 0.0


func _tune_materials(root: Node) -> void:
	# У исходных материалов шероховатость часто 0 — всё блестит как зеркало.
	# Даём каждому правдоподобные свойства по цвету и прозрачности.
	# На телефоне одинаковые исходные материалы настраиваются один раз и делятся между
	# сетками — иначе у каждой своя копия и слить их в один вызов отрисовки нельзя.
	var shared := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for k in mi.mesh.get_surface_count():
			var src := mi.get_active_material(k) as StandardMaterial3D
			if src == null:
				continue
			var share_key := "%d_%s" % [src.get_instance_id(), mi.name == "Object_27"]
			if MeshUtil.lite and shared.has(share_key):
				mi.set_surface_override_material(k, shared[share_key])
				continue
			var m := src.duplicate() as StandardMaterial3D
			var c := m.albedo_color
			var transparent := m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			if mi.name == "Object_27":
				# Стёкла в модели — непрозрачный чёрный материал; делаем их стеклом.
				transparent = true
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				c = Color(0.3, 0.36, 0.35, 0.3)
				m.albedo_color = c
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if transparent:
				m.roughness = 0.05
				m.metallic = 0.0
				# Заводское стекло «шестёрки» — прозрачное с лёгкой зеленцой.
				c = Color(c.r, c.g, c.b).lerp(Color(0.55, 0.62, 0.6), 0.5)
				c.a = minf(c.a, 0.38)
				m.albedo_color = c
				m.set_meta("glass", true)
				m.set_meta("glass_color", c)
			elif c.s > 0.5 and c.v > 0.3:
				# Лакокрасочное покрытие кузова.
				m.set_meta("paint", true)
				m.roughness = 0.32
				m.metallic = 0.25
				m.clearcoat_enabled = true
				m.clearcoat = 1.0
				m.clearcoat_roughness = 0.06
			elif absf(c.r - 0.51) < 0.02 and c.s < 0.05:
				# Хром: молдинги, бамперы, ободки фар.
				m.metallic = 1.0
				m.roughness = 0.12
				m.albedo_color = Color(0.82, 0.83, 0.85)
			elif m.roughness < 0.05:
				m.roughness = 0.6 if c.v < 0.2 else 0.45
			m.set_meta("orig_alpha", c.a)
			m.set_meta("orig_transparency", m.transparency)
			mi.set_surface_override_material(k, m)
			model_materials.append(m)
			shared[share_key] = m


func _paint(name: String, color: Color, metallic := 0.35, rough := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	m.resource_name = name
	return m


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = scale
	parent.add_child(m)
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	return c


# Боковой профиль кузова, выдавленный поперёк: точки (z, y) по контуру (любой формы,
# в том числе с вырезами колёсных арок). belt — высота, выше которой боковины заваливаются внутрь.
func _profile_mesh(points: PackedVector2Array, width: float, taper := 0.0, belt := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var area := 0.0
	for i in n:
		var p := points[i]
		var q := points[(i + 1) % n]
		area += p.x * q.y - q.x * p.y
	var ccw := area > 0.0
	var hw := width * 0.5
	var k := func(y: float) -> float: return 1.0 - taper * clampf((y - belt) / 0.5, 0.0, 1.0)
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		var ka: float = k.call(a.y)
		var kb: float = k.call(b.y)
		var a0 := Vector3(-hw * ka, a.y, a.x)
		var a1 := Vector3(hw * ka, a.y, a.x)
		var b0 := Vector3(-hw * kb, b.y, b.x)
		var b1 := Vector3(hw * kb, b.y, b.x)
		var dz := b.x - a.x
		var dy := b.y - a.y
		var nrm := Vector3(0, -dz, dy).normalized()
		if not ccw:
			nrm = -nrm
		MeshUtil._tri(st, a0, b0, b1, nrm)
		MeshUtil._tri(st, a0, b1, a1, nrm)
	# Боковины — триангуляция контура.
	var idx := Geometry2D.triangulate_polygon(points)
	for t in range(0, idx.size(), 3):
		for side in [-1.0, 1.0]:
			var p0 := points[idx[t]]
			var p1 := points[idx[t + 1]]
			var p2 := points[idx[t + 2]]
			var v0 := Vector3(side * hw * k.call(p0.y), p0.y, p0.x)
			var v1 := Vector3(side * hw * k.call(p1.y), p1.y, p1.x)
			var v2 := Vector3(side * hw * k.call(p2.y), p2.y, p2.x)
			MeshUtil._tri(st, v0, v1, v2, Vector3(side, 0, 0))
	st.generate_normals()
	return st.commit()


# Полуцилиндр (свод колёсной ниши) поперёк кузова шириной width.
func _wheel_well(r: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	for k in seg:
		var a0 := PI * k / seg
		var a1 := PI * (k + 1) / seg
		var p0 := Vector3(0, sin(a0) * r, cos(a0) * r)
		var p1 := Vector3(0, sin(a1) * r, cos(a1) * r)
		var hw := Vector3(width * 0.5, 0, 0)
		var n := -Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		MeshUtil._tri(st, p0 - hw, p1 - hw, p1 + hw, n)
		MeshUtil._tri(st, p0 - hw, p1 + hw, p0 + hw, n)
	st.generate_normals()
	return st.commit()


func _arch(points: PackedVector2Array, zc: float, yc: float, r: float, sill: float) -> void:
	# Вырез арки снизу: от заднего края к переднему поверх колеса.
	points.append(Vector2(zc - r, sill))
	for k in 17:
		var th := PI * (1.0 - k / 16.0)
		points.append(Vector2(zc + r * cos(th), yc + r * sin(th)))
	points.append(Vector2(zc + r, sill))


func _build_body() -> void:
	var paint := _paint("paint", PAINT, 0.4, 0.28)
	var chrome := _paint("chrome", Color(0.85, 0.86, 0.88), 1.0, 0.12)
	var black := _paint("black", Color(0.03, 0.03, 0.035), 0.2, 0.6)
	var glass := _paint("glass", Color(0.15, 0.2, 0.25, 0.45), 0.1, 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := GROUND
	var zf: float = car.mount_local[0].z
	var zr: float = car.mount_local[2].z
	var yc := g + 0.28
	var sill := g + 0.2
	# Нижняя часть кузова: контур сбоку против часовой стрелки (z вперёд к минусу).
	var lower := PackedVector2Array([
		Vector2(2.08, g + 0.36), Vector2(2.1, g + 0.66), Vector2(2.05, g + 0.9), Vector2(1.35, g + 0.93),
		Vector2(-0.35, g + 0.93), Vector2(-1.0, g + 0.88), Vector2(-2.02, g + 0.82), Vector2(-2.1, g + 0.62),
		Vector2(-2.08, g + 0.36), Vector2(-1.9, sill)])
	_arch(lower, zf, yc, 0.37, sill)
	_arch(lower, zr, yc, 0.37, sill)
	lower.append(Vector2(1.9, sill))
	lower.reverse()
	_add(body, _profile_mesh(lower, 1.61, 0.03, g + 0.75), paint, Vector3.ZERO)
	body_materials.append(paint)
	# Колёсные ниши: полуоболочка над колесом по форме выреза арки и внутренняя стенка.
	var liner := _paint("liner", Color(0.06, 0.06, 0.06), 0.1, 0.9)
	liner.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arch_mesh := _wheel_well(0.37, 0.26)
	for zc in [zf, zr]:
		for side in [-1.0, 1.0]:
			_add(body, arch_mesh, liner, Vector3(side * 0.675, yc, zc))
			_add(body, _box(Vector3(0.01, 0.36, 0.72)), liner, Vector3(side * 0.545, yc + 0.17, zc))
	body_materials.append(liner)
	# Кабина: стойки, крыша, стёкла.
	var cabin := PackedVector2Array([
		Vector2(1.38, g + 0.93), Vector2(1.05, g + 1.42), Vector2(0.1, g + 1.4), Vector2(-0.35, g + 0.93)])
	var roof := _add(body, _profile_mesh(cabin, 1.36, 0.12, g + 0.93), glass, Vector3.ZERO)
	roof.name = "Glass"
	_add(body, _box(Vector3(1.24, 0.04, 0.98)), paint, Vector3(0, g + 1.425, 0.58))
	for side in [-1.0, 1.0]:
		_add(body, _box(Vector3(0.05, 0.56, 0.06)), paint, Vector3(side * 0.66, g + 1.16, -0.12), Vector3(0.82, 0, 0))   # стойка A
		_add(body, _box(Vector3(0.05, 0.5, 0.06)), paint, Vector3(side * 0.66, g + 1.17, 0.5))                        # стойка B
		_add(body, _box(Vector3(0.05, 0.56, 0.1)), paint, Vector3(side * 0.64, g + 1.17, 1.22), Vector3(-0.6, 0, 0))   # стойка C
		# Молдинги, ручки дверей, зеркала.
		_add(body, _box(Vector3(0.012, 0.02, 3.6)), chrome, Vector3(side * 0.808, g + 0.7, 0.0))
		_add(body, _box(Vector3(0.02, 0.025, 0.12)), chrome, Vector3(side * 0.812, g + 0.82, -0.05))
		_add(body, _box(Vector3(0.02, 0.025, 0.12)), chrome, Vector3(side * 0.812, g + 0.82, 0.85))
		_add(body, _box(Vector3(0.1, 0.07, 0.03)), chrome, Vector3(side * 0.86, g + 1.0, -0.4))
	body_materials.append(glass)
	# Швы капота, крышки багажника и дверей — тонкие тёмные линии.
	var seam := _paint("seam", Color(0.12, 0.02, 0.02), 0.2, 0.6)
	for side in [-1.0, 1.0]:
		_add(body, _box(Vector3(0.006, 0.004, 1.45)), seam, Vector3(side * 0.66, g + 0.885, -1.28), Vector3(0.05, 0, 0))
		_add(body, _box(Vector3(0.006, 0.004, 0.62)), seam, Vector3(side * 0.66, g + 0.93, 1.72))
		for dz in [-0.32, 0.5, 1.33]:
			_add(body, _box(Vector3(0.004, 0.7, 0.006)), seam, Vector3(side * 0.806, g + 0.58, dz))
	_add(body, _box(Vector3(1.32, 0.004, 0.006)), seam, Vector3(0, g + 0.88, -0.56))
	_add(body, _box(Vector3(1.32, 0.004, 0.006)), seam, Vector3(0, g + 0.84, -2.0))
	_add(body, _box(Vector3(1.32, 0.004, 0.006)), seam, Vector3(0, g + 0.93, 1.41))
	# Дворники и решётка воздухозаборника.
	for side in [-0.3, 0.25]:
		_add(body, _box(Vector3(0.45, 0.01, 0.015)), black, Vector3(side, g + 0.95, -0.42), Vector3(0, 0.25, 0))
	_add(body, _box(Vector3(1.2, 0.012, 0.08)), black, Vector3(0, g + 0.935, -0.5))
	# Облицовка радиатора с четырьмя круглыми фарами.
	_add(body, _box(Vector3(1.5, 0.22, 0.03)), black, Vector3(0, g + 0.7, -2.1))
	for k in 4:
		var x: float = [-0.6, -0.42, 0.42, 0.6][k]
		_add(body, _cyl(0.072, 0.03), chrome, Vector3(x, g + 0.7, -2.115), Vector3(PI * 0.5, 0, 0))
		var lamp := _paint("lamp", Color(0.9, 0.92, 0.85), 0.2, 0.05)
		lamp.emission_enabled = true
		lamp.emission = Color(0.9, 0.88, 0.7) * 0.4
		_add(body, _cyl(0.06, 0.032), lamp, Vector3(x, g + 0.7, -2.12), Vector3(PI * 0.5, 0, 0))
	for k in 5:
		_add(body, _box(Vector3(0.5, 0.012, 0.035)), chrome, Vector3(0, g + 0.62 + k * 0.04, -2.12))
	# Бамперы с клыками.
	for zz in [-2.16, 2.14]:
		_add(body, _box(Vector3(1.66, 0.09, 0.07)), chrome, Vector3(0, g + 0.47, zz))
		for side in [-1.0, 1.0]:
			_add(body, _box(Vector3(0.07, 0.16, 0.06)), black, Vector3(side * 0.45, g + 0.49, zz))
	# Фонари сзади, номер.
	for side in [-1.0, 1.0]:
		var tail := _paint("tail", Color(0.7, 0.05, 0.03), 0.2, 0.2)
		tail.emission_enabled = true
		tail.emission = Color(0.6, 0.02, 0.01) * 0.2
		_brake_lights.append(tail)
		_add(body, _box(Vector3(0.42, 0.14, 0.03)), tail, Vector3(side * 0.56, g + 0.72, 2.1))
		var amber := _paint("amber", Color(0.95, 0.5, 0.05), 0.2, 0.2)
		_add(body, _box(Vector3(0.12, 0.14, 0.031)), amber, Vector3(side * 0.28, g + 0.72, 2.1))
	_add(body, _box(Vector3(0.52, 0.11, 0.01)), _paint("plate", Color(0.92, 0.92, 0.9), 0.0, 0.5), Vector3(0, g + 0.62, 2.112))
	# Днище, подрамник передней подвески, лонжероны.
	var floor := _paint("floor", Color(0.12, 0.12, 0.12), 0.3, 0.8)
	_add(body, _box(Vector3(1.4, 0.02, 2.0)), floor, Vector3(0, g + 0.22, 0.25))
	body_materials.append(floor)
	_add(body, _box(Vector3(1.0, 0.08, 0.12)), black, Vector3(0, g + 0.3, zf + 0.05))
	for side in [-1.0, 1.0]:
		_add(body, _box(Vector3(0.08, 0.1, 3.6)), black, Vector3(side * 0.5, g + 0.26, 0.0))

func set_xray(on: bool) -> void:
	xray = on
	for m in model_materials:
		var orig_t: int = m.get_meta("orig_transparency", BaseMaterial3D.TRANSPARENCY_DISABLED)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else orig_t
		m.albedo_color.a = 0.12 if on else float(m.get_meta("orig_alpha", 1.0))
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED if on else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	for m in body_materials:
		if m.resource_name == "glass":
			continue
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = 0.15 if on else 1.0


# Перекраска кузова: цвет эмали и «металлик» (алюминиевая пудра даёт блеск и глубину).
func set_paint(color: Color, metallic: bool) -> void:
	for m in model_materials:
		if not m.get_meta("paint", false):
			continue
		m.albedo_color = Color(color, m.albedo_color.a)
		m.metallic = 0.75 if metallic else 0.25
		m.roughness = 0.22 if metallic else 0.32


# Тонировка стёкол: 0 — заводские, 1 — почти непрозрачные.
func set_tint(amount: float) -> void:
	for m in model_materials:
		if not m.get_meta("glass", false):
			continue
		var c: Color = m.get_meta("glass_color")
		var t := Color(c.r, c.g, c.b).lerp(Color(0.02, 0.02, 0.03), amount)
		m.albedo_color = Color(t, lerpf(c.a, 0.97, amount * 0.9) if not xray else 0.12)
		m.set_meta("orig_alpha", lerpf(c.a, 0.97, amount * 0.9))


func set_brake_lights(on: bool) -> void:
	for m in _brake_lights:
		m.emission = Color(1.0, 0.05, 0.02) * (2.5 if on else 0.2)


func _build_wheels() -> void:
	var tire := _paint("tire", Color(0.04, 0.04, 0.04), 0.0, 0.85)
	var rim := _paint("rim", Color(0.6, 0.6, 0.62), 0.8, 0.35)
	var cap := _paint("cap", Color(0.85, 0.86, 0.88), 1.0, 0.15)
	for i in 4:
		var w := Node3D.new()
		add_child(w)
		var spin := Node3D.new()
		w.add_child(spin)
		var side := signf(car.mount_local[i].x)
		var t := TorusMesh.new()
		t.inner_radius = 0.17
		t.outer_radius = EngineSpecs.WHEEL_RADIUS
		t.rings = 40
		t.ring_segments = 12
		_add(spin, t, tire, Vector3.ZERO, Vector3(0, 0, PI * 0.5), Vector3(1, 1.6, 1))
		_add(spin, _cyl(0.17, 0.15, 32), rim, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
		_add(spin, _cyl(0.09, 0.02, 24), cap, Vector3(side * 0.08, 0, 0), Vector3(0, 0, PI * 0.5))
		for k in 6:
			var hole := _add(spin, _cyl(0.018, 0.155), tire, Vector3(0, cos(k * TAU / 6.0) * 0.125, sin(k * TAU / 6.0) * 0.125), Vector3(0, 0, PI * 0.5))
			hole.name = "vent"
		# Тормоз: диск спереди, барабан сзади.
		if i < 2:
			_add(w, _cyl(0.12, 0.012, 32), _paint("disc", Color(0.4, 0.38, 0.36), 0.9, 0.4), Vector3(-side * 0.04, 0, 0), Vector3(0, 0, PI * 0.5))
			_add(w, _box(Vector3(0.05, 0.08, 0.1)), _paint("caliper", Color(0.3, 0.3, 0.3), 0.7, 0.5), Vector3(-side * 0.04, 0.0, 0.1))
		else:
			_add(w, _cyl(0.13, 0.06, 32), _paint("drum", Color(0.25, 0.24, 0.23), 0.8, 0.6), Vector3(-side * 0.06, 0, 0), Vector3(0, 0, PI * 0.5))
		wheels.append(w)
		wheel_spin_nodes.append(spin)


# Стержень от точки a к точке b (в системе кузова).
func _beam(node: Node3D, a: Vector3, b: Vector3, thickness := 1.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return
	node.position = (a + b) * 0.5
	node.basis = EngineModel._basis_along(d) * Basis.from_scale(Vector3(thickness, len, thickness))


func _link(radius: float, mat: Material, ends: Callable) -> void:
	var m := _add(self, _cyl(radius, 1.0, 10), mat, Vector3.ZERO)
	_links.append([m, ends])


func _build_front_suspension() -> void:
	var arm_mat := _paint("arm", Color(0.08, 0.08, 0.09), 0.5, 0.6)
	var spring_mat := _paint("spring", Color(0.15, 0.2, 0.5), 0.5, 0.4)
	var shock_mat := _paint("shock", Color(0.6, 0.6, 0.62), 0.8, 0.3)
	var g := GROUND
	for i in 2:
		var ii := i
		var side := signf(car.mount_local[i].x)
		var z: float = car.mount_local[i].z
		var inner_low := Vector3(side * 0.3, g + 0.18, z)
		var inner_up := Vector3(side * 0.38, g + 0.47, z)
		# Нижний и верхний рычаги (по две ветви, буквой А).
		for dz in [-0.13, 0.13]:
			var a0 := inner_low + Vector3(0, 0, dz)
			_link(0.014, arm_mat, func() -> Array: return [a0, _knuckle(ii, -0.11)])
			var a1 := inner_up + Vector3(0, 0, dz * 0.7)
			_link(0.011, arm_mat, func() -> Array: return [a1, _knuckle(ii, 0.13)])
		# Поворотный кулак.
		_link(0.02, arm_mat, func() -> Array: return [_knuckle(ii, -0.11), _knuckle(ii, 0.13)])
		# Пружина между нижним рычагом и опорой на лонжероне, амортизатор внутри.
		var top := Vector3(side * 0.46, g + 0.62, z)
		var spring := _add(self, MeshUtil.spring_mesh(0.055, 0.007, 6.5), spring_mat, Vector3.ZERO)
		_springs.append([spring, top, func() -> Vector3: return inner_low.lerp(_knuckle(ii, -0.11), 0.55) + Vector3(0, 0.03, 0)])
		_link(0.016, shock_mat, func() -> Array: return [top, inner_low.lerp(_knuckle(ii, -0.11), 0.55)])
		# Рулевая тяга.
		_link(0.008, shock_mat, func() -> Array: return [Vector3(side * 0.25, g + 0.26, z + 0.16), _knuckle(ii, -0.02) + Vector3(0, 0, 0.15)])
	# Стабилизатор: торсион вдоль подрамника и концы к нижним рычагам.
	_link(0.009, arm_mat, func() -> Array: return [Vector3(-0.5, g + 0.24, car.mount_local[0].z - 0.28), Vector3(0.5, g + 0.24, car.mount_local[0].z - 0.28)])
	for i in 2:
		var ii := i
		var side := signf(car.mount_local[i].x)
		_link(0.009, arm_mat, func() -> Array: return [Vector3(side * 0.5, g + 0.24, car.mount_local[0].z - 0.28), _knuckle(ii, -0.11).lerp(Vector3(side * 0.3, g + 0.18, car.mount_local[0].z), 0.4)])


func _knuckle(i: int, dy: float) -> Vector3:
	var c := car.wheel_center_local(i)
	return Vector3(c.x - signf(c.x) * 0.08, c.y + dy, c.z)


func _build_rear_axle() -> void:
	var axle_mat := _paint("axle", Color(0.07, 0.07, 0.08), 0.6, 0.5)
	var spring_mat := _paint("spring_r", Color(0.15, 0.2, 0.5), 0.5, 0.4)
	var shock_mat := _paint("shock_r", Color(0.6, 0.6, 0.62), 0.8, 0.3)
	var g := GROUND
	_axle = Node3D.new()
	add_child(_axle)
	_add(_axle, _cyl(0.04, 1.0, 16), axle_mat, Vector3.ZERO)
	_diff = Node3D.new()
	add_child(_diff)
	_add(_diff, MeshUtil.sphere(0.14, "black").mesh, axle_mat, Vector3.ZERO)
	_add(_diff, _cyl(0.05, 0.16, 16), axle_mat, Vector3(0, 0.02, -0.14), Vector3(PI * 0.5, 0, 0))
	var z: float = car.mount_local[2].z
	for i in [2, 3]:
		var ii: int = i
		var side := signf(car.mount_local[i].x)
		# Нижняя и верхняя продольные тяги.
		_link(0.016, axle_mat, func() -> Array: return [Vector3(side * 0.42, g + 0.24, z - 0.85), _axle_point(ii, -0.07, 0.3)])
		_link(0.013, axle_mat, func() -> Array: return [Vector3(side * 0.3, g + 0.42, z - 0.55), _axle_point(ii, 0.08, 0.45)])
		# Пружина и амортизатор.
		var top := Vector3(side * 0.5, g + 0.68, z - 0.02)
		var spring := _add(self, MeshUtil.spring_mesh(0.06, 0.007, 6.0), spring_mat, Vector3.ZERO)
		_springs.append([spring, top, func() -> Vector3: return _axle_point(ii, 0.05, 0.12)])
		_link(0.014, shock_mat, func() -> Array: return [Vector3(side * 0.42, g + 0.6, z + 0.18), _axle_point(ii, -0.05, 0.22)])
	# Поперечная тяга (панар).
	_link(0.013, axle_mat, func() -> Array: return [Vector3(-0.55, g + 0.4, z + 0.12), _axle_point(3, 0.02, 0.85)])


# Точка на балке моста: t — от колеса к середине (0..1).
func _axle_point(i: int, dy: float, t: float) -> Vector3:
	var c := car.wheel_center_local(i)
	var other := car.wheel_center_local(5 - i)
	var mid := (c + other) * 0.5
	return c.lerp(mid, t) + Vector3(0, dy, 0)


func _build_driveline() -> void:
	var mat := _paint("gearbox", Color(0.6, 0.6, 0.62), 0.7, 0.5)
	var dark := _paint("prop", Color(0.1, 0.1, 0.11), 0.7, 0.4)
	var g := GROUND
	# Картер сцепления и КПП за двигателем.
	_add(chassis, MeshUtil.cone(0.17, 0.11, 0.2, "aluminum").mesh, mat, Vector3(0, -0.08, -0.88), Vector3(PI * 0.5, 0, 0))
	_add(chassis, _box(Vector3(0.2, 0.2, 0.42)), mat, Vector3(0, -0.1, -0.58))
	_add(chassis, _cyl(0.045, 0.16), mat, Vector3(0, -0.12, -0.3), Vector3(PI * 0.5, 0, 0))
	_add(chassis, _cyl(0.012, 0.35), dark, Vector3(0, 0.12, -0.55), Vector3(-0.3, 0, 0))   # рычаг КПП
	_prop = Node3D.new()
	add_child(_prop)
	_prop_spin = Node3D.new()
	_prop.add_child(_prop_spin)
	_add(_prop_spin, _cyl(0.035, 1.0, 12), dark, Vector3.ZERO)
	_add(_prop_spin, _box(Vector3(0.012, 0.03, 0.09)), mat, Vector3(0, 0.3, 0))
	# Выпускная труба и глушитель.
	_add(chassis, _cyl(0.025, 2.6), _paint("pipe", Color(0.3, 0.25, 0.22), 0.6, 0.8), Vector3(-0.25, g + 0.2, 0.4), Vector3(PI * 0.5, 0, 0))
	_add(chassis, _box(Vector3(0.3, 0.14, 0.6)), _paint("muffler", Color(0.25, 0.22, 0.2), 0.6, 0.8), Vector3(-0.2, g + 0.22, 1.85))


func update_pose() -> void:
	_update_openings(get_process_delta_time())
	if interior != null and car.sim != null:
		interior.update_view(car, car.sim, get_process_delta_time(), light_mode >= 1)
	for i in 4:
		var w := wheels[i]
		w.position = car.wheel_center_local(i)
		w.rotation = Vector3(0, -car.wheel_heading[i], 0)
		wheel_spin_nodes[i].rotation.x = -car.wheel_spin[i]
	for l in _links:
		var ends: Array = l[1].call()
		_beam(l[0], ends[0], ends[1])
	for s in _springs:
		var bottom: Vector3 = s[2].call()
		_beam(s[0], bottom, s[1])
	# Балка моста и редуктор следуют за задними колёсами.
	var c2 := car.wheel_center_local(2)
	var c3 := car.wheel_center_local(3)
	_beam(_axle, c2, c3)

	var mid := (c2 + c3) * 0.5
	_diff.position = mid
	_diff.rotation = Vector3(0, 0, atan2(c3.y - c2.y, c3.x - c2.x))
	# Карданный вал от КПП к редуктору, вращается со скоростью вала.
	var a := Vector3(0, -0.12, -0.22)
	var b := mid + Vector3(0, 0.02, -0.22)
	_beam(_prop, a, b)
	var vd := car.vd
	if vd != null:
		var prop_w := (vd.wheel_omega[2] + vd.wheel_omega[3]) * 0.5 * EngineSpecs.FINAL_DRIVE
		_prop_spin.rotation.y = fposmod(_prop_spin.rotation.y + prop_w * get_process_delta_time(), TAU)
		set_brake_lights(vd.brake > 0.05)
		update_lights(get_process_delta_time(), vd.brake > 0.05, vd.gear == 0)
