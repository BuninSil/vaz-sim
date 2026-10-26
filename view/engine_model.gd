class_name EngineModel
extends Node3D

# Трёхмерная модель двигателя ВАЗ-2103 в натуральную величину (метры).
# Ось коленвала — X (перед двигателя в сторону -X), Y — вверх.
# Слева по ходу (+Z) — впускной и выпускной коллекторы с карбюратором,
# справа (-Z) — свечи, трамблёр, бензонасос, генератор, масляный фильтр.

signal part_changed(part: EnginePart)

const CX: Array[float] = [-0.1425, -0.0475, 0.0475, 0.1425]
const MAIN_X: Array[float] = [-0.19, -0.095, 0.0, 0.095, 0.19]
const DECK := 0.2105
const HEAD_BOTTOM := 0.212
const HEAD_TOP := 0.29
const CAM_Y := 0.3365
const CAM_Z := -0.015
const PIVOT_Z := -0.045
const VALVE_SEAT_Y := 0.2185
const VALVE_TIP_Y := 0.312
const CAM_BASE_R := 0.0165
const PIN_HEIGHT := 0.034   # от оси пальца до днища поршня
const BELT_X := -0.272
const CHAIN_X := -0.226

var parts := {}               # id -> EnginePart
var part_order: Array[EnginePart] = []
var block: EnginePart

# Кинематика.
var _crank_content: Node3D
var _pistons: Array[EnginePart] = []
var _rods: Array[EnginePart] = []
var _rod_caps: Array[EnginePart] = []
var _gas: Array[MeshInstance3D] = []
var _gas_mat: Array[StandardMaterial3D] = []
var _flames: Array[OmniLight3D] = []
var _valves: Array[Dictionary] = []   # {part, rocker, spring, cyl, intake, x}
var _cam_content: Node3D
var _chain_links: MultiMeshInstance3D
var _chain_path := PackedVector3Array()
var _chain_dist := PackedFloat32Array()
var _chain_length := 0.0
var _spin := []                       # [node, axis, ratio] — шкивы, звёздочки
var _rotor: Node3D
var _throttle1: Node3D
var _throttle2: Node3D
var _choke_plate: Node3D
var _throttle_lever: Node3D
var _fuel_pump_lever: Node3D
var _crank_unwrapped := 0.0
var _last_phi := 0.0
var _profile_sim: EngineSim


func _ready() -> void:
	_build()
	for p in part_order:
		p.state_changed.connect(func(pp: EnginePart) -> void: part_changed.emit(pp))


# --- Вспомогательное ------------------------------------------------------

func _part(id: String, title: String, parent: Node3D, req: Array, off: Vector3, crit: bool, group: String, desc: String, spec: String) -> EnginePart:
	var p := EnginePart.new(id, title)
	p.requires = PackedStringArray(req)
	p.offset = off
	p.critical = crit
	p.group = group
	p.description = desc
	p.specs = spec
	if parent is EnginePart:
		(parent as EnginePart).content.add_child(p)
	else:
		parent.add_child(p)
	parts[id] = p
	part_order.append(p)
	return p


func get_part(id: String) -> EnginePart:
	return parts.get(id)


func is_installed(id: String) -> bool:
	var p: EnginePart = parts.get(id)
	return p != null and not p.is_detached()


# --- Построение -------------------------------------------------------------

func _build() -> void:
	_build_block()
	_build_crank_train()
	_build_head()
	_build_timing()
	_build_front_drive()
	_build_lubrication()
	_build_ignition()
	_build_fuel_intake()
	_build_rear()
	var skip: Array = []
	for g in _gas:
		skip.append(g)
	var merged := MeshUtil.merge_static(self, skip)
	print_verbose("Склеено мешей: %d" % merged)


func _build_block() -> void:
	block = _part("block", "Блок цилиндров", self, [], Vector3.ZERO, true, "Блок",
		"Чугунный блок с четырьмя цилиндрами в ряд, расточенными прямо в теле блока. Внутри — рубашка охлаждения, масляная магистраль и пять коренных опор коленвала. Сбоку — постель промежуточного вала.",
		"Материал: серый чугун\nДиаметр цилиндра: 76 мм (классы A–E через 0,01 мм)\nХод поршня: 80 мм\nМежцентровое расстояние: 95 мм\nРабочий объём: 1452 см³")
	var csg := CSGCombiner3D.new()
	block.add(csg)
	var outer := CSGBox3D.new()
	outer.size = Vector3(0.41, 0.25, 0.17)
	outer.position = Vector3(0, DECK - 0.125, 0)
	outer.material = MeshUtil.material("cast_iron")
	csg.add_child(outer)
	for x in CX:
		var bore := CSGCylinder3D.new()
		bore.operation = CSGShape3D.OPERATION_SUBTRACTION
		bore.radius = EngineSpecs.BORE * 0.5
		bore.height = 0.17
		bore.sides = 32
		bore.position = Vector3(x, DECK - 0.07, 0)
		bore.material = MeshUtil.material("steel")
		csg.add_child(bore)
	var cavity := CSGBox3D.new()
	cavity.operation = CSGShape3D.OPERATION_SUBTRACTION
	cavity.size = Vector3(0.39, 0.13, 0.15)
	cavity.position = Vector3(0, -0.005, 0)
	cavity.material = MeshUtil.material("cast_iron")
	csg.add_child(cavity)
	# Коренные опоры (перегородки) с постелями вкладышей.
	for x in MAIN_X:
		var web := CSGBox3D.new()
		web.size = Vector3(0.014, 0.075, 0.15)
		web.position = Vector3(x, 0.0375, 0)
		web.material = MeshUtil.material("cast_iron")
		csg.add_child(web)
		var hole := CSGCylinder3D.new()
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		hole.radius = 0.0265
		hole.height = 0.02
		hole.rotation = Vector3(0, 0, PI * 0.5)
		hole.position = Vector3(x, 0, 0)
		csg.add_child(hole)
	# Прилив промежуточного вала и платики агрегатов справа.
	block.add(MeshUtil.box(Vector3(0.40, 0.04, 0.03), "cast_iron", Vector3(0, 0.08, -0.095)))
	block.add(MeshUtil.box(Vector3(0.06, 0.05, 0.02), "cast_iron", Vector3(0.1, 0.05, -0.095)))
	block.add(MeshUtil.cyl(0.035, 0.012, "cast_iron", Vector3(0.12, 0.045, -0.1), Vector3(PI * 0.5 * 0.6, 0, 0)))  # платик фильтра
	# Опоры двигателя (кронштейны с резиновыми подушками).
	for side in [-1.0, 1.0]:
		block.add(MeshUtil.box(Vector3(0.06, 0.05, 0.03), "cast_iron", Vector3(-0.08, 0.05, side * 0.1)))
		block.add(MeshUtil.box(Vector3(0.07, 0.008, 0.07), "dark_steel", Vector3(-0.08, 0.02, side * 0.15), Vector3(side * 0.6, 0, 0)))
		block.add(MeshUtil.cyl(0.025, 0.03, "rubber", Vector3(-0.08, -0.005, side * 0.18), Vector3(side * 0.6, 0, 0)))
	# Заглушки рубашки охлаждения (по три с каждой стороны) и рёбра жёсткости.
	for side in [-1.0, 1.0]:
		for x in [-0.095, 0.0, 0.095]:
			block.add(MeshUtil.cyl(0.016, 0.004, "brass", Vector3(x, 0.15, side * 0.0855), Vector3(PI * 0.5, 0, 0)))
		for x in MAIN_X:
			block.add(MeshUtil.box(Vector3(0.008, 0.09, 0.006), "cast_iron", Vector3(x, 0.0, side * 0.087)))
		# Фланец крепления поддона.
		block.add(MeshUtil.box(Vector3(0.41, 0.008, 0.012), "cast_iron", Vector3(0, -0.0355, side * 0.091)))
	# Задний фланец под картер сцепления и передний под крышку привода.
	var flange := CSGCombiner3D.new()
	block.add(flange)
	var fl := CSGBox3D.new()
	fl.size = Vector3(0.012, 0.27, 0.27)
	fl.position = Vector3(0.199, 0.06, 0)
	fl.material = MeshUtil.material("cast_iron")
	flange.add_child(fl)
	var fl_hole := CSGCylinder3D.new()
	fl_hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	fl_hole.radius = 0.04
	fl_hole.height = 0.03
	fl_hole.rotation = Vector3(0, 0, PI * 0.5)
	fl_hole.position = Vector3(0.199, 0, 0)
	flange.add_child(fl_hole)
	for k in 8:
		var a := TAU * k / 8.0
		block.add(MeshUtil.hex_bolt(0.013, 0.008, "dark_steel", Vector3(0.208, 0.06 + cos(a) * 0.12, sin(a) * 0.12), Vector3(0, 0, PI * 0.5)))
	# Патрубок подвода охлаждающей жидкости и датчик давления масла.
	block.add(MeshUtil.cyl_z(0.014, 0.05, "aluminum", Vector3(-0.17, 0.17, 0.1)))
	block.add(MeshUtil.cyl(0.009, 0.03, "brass", Vector3(-0.15, 0.1, -0.108), Vector3(PI * 0.5, 0, 0)))


func _build_crank_train() -> void:
	var crank := _part("crankshaft", "Коленчатый вал", block, ["main_cap_1", "main_cap_2", "main_cap_3", "main_cap_4", "main_cap_5", "rod_cap_1", "rod_cap_2", "rod_cap_3", "rod_cap_4", "flywheel", "crank_sprocket", "front_cover"], Vector3(0, -0.45, 0), true, "КШМ",
		"Пятиопорный литой коленвал с восемью противовесами. Кривошипы 1-го и 4-го цилиндров направлены в одну сторону, 2-го и 3-го — в противоположную: поршни ходят парами, вспышки идут через 180° поворота вала в порядке 1-3-4-2.",
		"Материал: высокопрочный чугун\nКоренные шейки: Ø 50,8 мм\nШатунные шейки: Ø 47,8 мм\nРадиус кривошипа: 40 мм\nМомент инерции вместе с маховиком: 0,135 кг·м²")
	_crank_content = crank.content
	for x in MAIN_X:
		crank.add(MeshUtil.cyl_x(0.0254, 0.02, "steel", Vector3(x, 0, 0), 32))
		# Галтели у щёк и масляный канал на шейке.
		crank.add(MeshUtil.cyl_x(0.027, 0.002, "forged", Vector3(x - 0.0095, 0, 0), 32))
		crank.add(MeshUtil.cyl_x(0.027, 0.002, "forged", Vector3(x + 0.0095, 0, 0), 32))
		crank.add(MeshUtil.cyl(0.003, 0.0004, "black", Vector3(x, 0.0254, 0)))
	# Носок: шпонка звёздочки, шкива, храповик.
	crank.add(MeshUtil.cyl_x(0.016, 0.06, "steel", Vector3(-0.225, 0, 0)))
	crank.add(MeshUtil.box(Vector3(0.05, 0.004, 0.005), "dark_steel", Vector3(-0.225, 0.016, 0)))
	crank.add(MeshUtil.hex_bolt(0.032, 0.014, "dark_steel", Vector3(-0.287, 0, 0), Vector3(0, 0, PI * 0.5)))
	crank.add(MeshUtil.cyl_x(0.007, 0.02, "steel", Vector3(-0.3, 0, 0)))
	# Задний фланец маховика с сальником.
	crank.add(MeshUtil.cyl_x(0.04, 0.012, "steel", Vector3(0.208, 0, 0), 32))
	crank.add(MeshUtil.cyl_x(0.034, 0.012, "steel", Vector3(0.196, 0, 0), 32))
	var r := EngineSpecs.CRANK_RADIUS
	for i in 4:
		var up := 1.0 if (i == 0 or i == 3) else -1.0
		var pin := Vector3(CX[i], r * up, 0)
		crank.add(MeshUtil.cyl_x(0.0239, 0.024, "steel", pin, 32))
		crank.add(MeshUtil.cyl(0.003, 0.0004, "black", pin + Vector3(0, 0.0239 * up, 0)))
		var cheek := _cheek_mesh(up)
		for side in [-1.0, 1.0]:
			var m := MeshUtil.mi(cheek, "forged", Vector3(CX[i] + side * 0.0195, 0, 0))
			crank.add(m)
		# Шатун и поршень.
		_build_cylinder_set(i)
	# Крышки коренных подшипников.
	for k in 5:
		var cap := _part("main_cap_%d" % (k + 1), "Крышка коренного подшипника %d" % (k + 1), block, ["oil_pan", "oil_pump"], Vector3(0, -0.32 - k * 0.012, -0.12 + k * 0.06), true, "КШМ",
			"Крышка коренной опоры растачивается вместе с блоком, поэтому крышки не взаимозаменяемы: на каждой выбит номер. Третья крышка держит упорные полукольца, ограничивающие осевой люфт коленвала.",
			"Крепление: 2 болта М10\nМомент затяжки: 68–84 Н·м\nОсевой люфт коленвала: 0,06–0,26 мм")
		# Крышка: полукольцо вокруг шейки с двумя лапами под болты.
		var cap_profile := PackedVector2Array()
		cap_profile.append(Vector2(0.0, 0.058))
		cap_profile.append_array(MeshUtil.circle_points(Vector2.ZERO, 0.042, PI * 0.5 + 0.35, PI * 1.5 - 0.35, 10))
		cap_profile.append(Vector2(0.0, -0.058))
		var hull := MeshUtil.convex_hull(cap_profile)
		hull.remove_at(hull.size() - 1)
		cap.add(MeshUtil.mi(MeshUtil.extrude_x(hull, 0.018 if k != 2 else 0.026), "cast_iron", Vector3(MAIN_X[k], 0, 0)))
		for side in [-1.0, 1.0]:
			cap.add(MeshUtil.hex_bolt(0.016, 0.01, "dark_steel", Vector3(MAIN_X[k], -0.047, side * 0.045)))
			cap.add(MeshUtil.cyl(0.005, 0.01, "steel", Vector3(MAIN_X[k], -0.056, side * 0.045)))
		if k == 2:
			# Упорные полукольца на третьей опоре.
			for dx in [-0.014, 0.014]:
				cap.add(MeshUtil.cyl_x(0.034, 0.0025, "brass", Vector3(MAIN_X[k] + dx, -0.004, 0), 32))
		var label := Label3D.new()
		label.text = str(k + 1)
		label.font_size = 24
		label.pixel_size = 0.0004
		label.position = Vector3(MAIN_X[k], -0.03, -0.0405)
		label.rotation = Vector3(0, PI, 0)
		label.modulate = Color(0.8, 0.8, 0.8)
		cap.add(label)


func _cheek_mesh(up: float) -> ArrayMesh:
	# Щека с противовесом: выпуклая оболочка вокруг шатунной шейки и сектора противовеса.
	var pts := PackedVector2Array()
	pts.append_array(MeshUtil.circle_points(Vector2(EngineSpecs.CRANK_RADIUS * up, 0), 0.03, 0.0, TAU, 16))
	var start := (PI if up > 0.0 else 0.0) - 1.0
	pts.append_array(MeshUtil.circle_points(Vector2.ZERO, 0.058, start, start + 2.0, 12))
	var hull := MeshUtil.convex_hull(pts)
	hull.remove_at(hull.size() - 1)
	return MeshUtil.extrude_x(hull, 0.013)


func _build_cylinder_set(i: int) -> void:
	var n := i + 1
	var x: float = CX[i]
	var assy := _part("piston_assy_%d" % n, "Поршень с шатуном (цил. %d)" % n, block, ["rod_cap_%d" % n, "cylinder_head", "head_gasket"], Vector3(0, 0.3, -0.45), true, "КШМ",
		"Поршень вынимается вверх вместе с шатуном после снятия головки и шатунной крышки. Перед этим нужно убрать нагар из верхнего пояса цилиндра, чтобы не сломать кольца.",
		"Сборка: поршень, 3 кольца, палец, шатун\nПорядок работы цилиндров: 1-3-4-2")
	# Поршень.
	var piston := _part("piston_%d" % n, "Поршень (цил. %d)" % n, assy, ["piston_assy_%d" % n, "pin_%d" % n], Vector3(0, 0.12, 0.12), true, "КШМ",
		"Литой поршень из алюминиевого сплава. Юбка овальная и коническая: на прогретом двигателе она принимает форму цилиндра. Палец смещён от оси на 2 мм в сторону, чтобы поршень не стучал при перекладке в ВМТ.",
		"Материал: алюминиевый сплав АК12\nМасса: около 430 г\nВысота сжатия: 34 мм\nЗазор в цилиндре: 0,05–0,07 мм")
	_pistons.append(piston)
	# Тело поршня — тело вращения: юбка, канавки колец, жаровой пояс, днище с фаской.
	var land := 0.0377
	var groove := 0.0336
	var prof := PackedVector2Array([
		Vector2(-0.026, 0.034), Vector2(-0.026, 0.0372), Vector2(0.010, 0.0373), Vector2(0.0125, land),
		Vector2(0.0125, groove), Vector2(0.0175, groove), Vector2(0.0175, land), Vector2(0.0205, land),
		Vector2(0.0205, groove), Vector2(0.0235, groove), Vector2(0.0235, land), Vector2(0.0265, land),
		Vector2(0.0265, groove), Vector2(0.0295, groove), Vector2(0.0295, land), Vector2(0.0332, land),
		Vector2(PIN_HEIGHT, 0.0365), Vector2(PIN_HEIGHT, 0.0)])
	piston.add(MeshUtil.mi(MeshUtil.lathe(prof, 40), "piston", Vector3(x, 0, 0)))
	# Выборки под клапаны и нагар на днище.
	piston.add(MeshUtil.cyl(0.03, 0.0006, "dark_steel", Vector3(x, PIN_HEIGHT + 0.0002, 0)))
	for vx in [-0.017, 0.017]:
		piston.add(MeshUtil.cyl(0.0125, 0.0008, "piston", Vector3(x + vx, PIN_HEIGHT + 0.0005, 0)))
	# Бобышки пальца с отверстиями и стопорными канавками.
	for side in [-1.0, 1.0]:
		piston.add(MeshUtil.cyl_x(0.0115, 0.002, "dark_steel", Vector3(x + side * 0.0365, 0, 0)))
		piston.add(MeshUtil.cyl_x(0.016, 0.012, "piston", Vector3(x + side * 0.024, 0, 0)))
	# Маркировка класса и стрелка «вперёд».
	piston.add(MeshUtil.box(Vector3(0.008, 0.0004, 0.002), "dark_steel", Vector3(x - 0.02, PIN_HEIGHT + 0.0008, 0.0)))
	var ring_names := ["Верхнее компрессионное кольцо", "Нижнее компрессионное кольцо", "Маслосъёмное кольцо"]
	var ring_desc := [
		"Хромированное кольцо с бочкообразной рабочей поверхностью, держит давление газов до 50–60 бар.",
		"Скребкового типа, с проточкой снизу: доуплотняет газы и снимает излишек масла.",
		"Коробчатое кольцо с прорезями и пружинным расширителем: снимает масло со стенок цилиндра и сбрасывает его внутрь поршня."]
	var ring_y := [PIN_HEIGHT - 0.006, PIN_HEIGHT - 0.012, PIN_HEIGHT - 0.019]
	for k in 3:
		var ring := _part("ring_%d_%d" % [n, k + 1], "%s (цил. %d)" % [ring_names[k], n], piston, ["piston_assy_%d" % n], Vector3(0, 0.05 + k * 0.035, -0.14), true, "КШМ", ring_desc[k],
			"Зазор в замке: 0,25–0,45 мм\nЗазор по высоте в канавке: 0,02–0,07 мм")
		ring.add(MeshUtil.torus(0.0362, 0.0381, "ring", Vector3(x, ring_y[k], 0)))
	var pin := _part("pin_%d" % n, "Поршневой палец (цил. %d)" % n, piston, ["piston_assy_%d" % n], Vector3(0.12, 0, 0), true, "КШМ",
		"Стальной пустотелый палец. Запрессован в верхнюю головку шатуна с натягом и свободно вращается в бобышках поршня.",
		"Наружный диаметр: 22 мм\nДлина: 65 мм\nСталь 12ХН3А, цементация")
	pin.add(MeshUtil.cyl_x(0.011, 0.062, "steel", Vector3(x, 0, 0)))
	# Шатун: строится от оси нижней головки вдоль +Y.
	var rod := _part("rod_%d" % n, "Шатун (цил. %d)" % n, assy, ["piston_assy_%d" % n, "pin_%d" % n], Vector3(0, -0.05, 0.16), true, "КШМ",
		"Стальной кованый шатун двутаврового сечения. Нижняя головка разъёмная, с тонкостенными вкладышами; крышка обрабатывается вместе с шатуном.",
		"Длина (межцентровое расстояние): 136 мм\nМасса: около 810 г\nДиаметр нижней головки: 51,3 мм")
	_rods.append(rod)
	var l := EngineSpecs.ROD_LENGTH
	# Стержень двутаврового сечения: стенка и две полки, расширяется к нижней головке.
	var shank := l - 0.05
	rod.add(MeshUtil.box(Vector3(0.006, shank, 0.016), "forged", Vector3(x, 0.025 + shank * 0.5, 0)))
	for side in [-1.0, 1.0]:
		var flange_mesh := BoxMesh.new()
		flange_mesh.size = Vector3(0.017, shank, 0.004)
		var fl_mi := MeshUtil.mi(flange_mesh, "forged", Vector3(x, 0.025 + shank * 0.5, side * 0.0095))
		fl_mi.rotation.x = -side * 0.05
		rod.add(fl_mi)
	# Верхняя головка с бронзовой втулкой и маслоподводящим отверстием.
	rod.add(MeshUtil.cyl_x(0.016, 0.022, "forged", Vector3(x, l, 0), 32))
	rod.add(MeshUtil.cyl_x(0.0118, 0.0225, "brass", Vector3(x, l, 0), 32))
	rod.add(MeshUtil.cyl(0.002, 0.004, "black", Vector3(x, l + 0.016, 0)))
	# Нижняя головка (верхняя половина) с приливами под болты.
	rod.add(MeshUtil.cyl_x(0.031, 0.022, "forged", Vector3(x, 0.006, 0), 32))
	for side in [-1.0, 1.0]:
		rod.add(MeshUtil.box(Vector3(0.022, 0.02, 0.016), "forged", Vector3(x, 0.006, side * 0.029)))
	# Номер цилиндра, выбитый на шатуне.
	var num := Label3D.new()
	num.text = str(n)
	num.font_size = 24
	num.pixel_size = 0.0004
	num.position = Vector3(x - 0.0115, 0.006, 0.02)
	num.rotation = Vector3(0, -PI * 0.5, 0)
	rod.add(num)
	var cap := _part("rod_cap_%d" % n, "Крышка шатуна (цил. %d)" % n, rod, ["oil_pan", "oil_pump"], Vector3(0, -0.22, -0.05), true, "КШМ",
		"Крышка нижней головки шатуна. Ставится только своим шатуном и в том же положении — по номеру цилиндра, выбитому на обеих деталях.",
		"Крепление: 2 гайки М9\nМомент затяжки: 44–54 Н·м")
	_rod_caps.append(cap)
	var cap_pts := PackedVector2Array()
	cap_pts.append(Vector2(-0.002, 0.037))
	cap_pts.append_array(MeshUtil.circle_points(Vector2(0, 0), 0.033, PI * 0.5 + 0.5, PI * 1.5 - 0.5, 10))
	cap_pts.append(Vector2(-0.002, -0.037))
	var cap_hull := MeshUtil.convex_hull(cap_pts)
	cap_hull.remove_at(cap_hull.size() - 1)
	cap.add(MeshUtil.mi(MeshUtil.extrude_x(cap_hull, 0.022), "forged", Vector3(x, 0, 0)))
	for side in [-1.0, 1.0]:
		cap.add(MeshUtil.cyl(0.0045, 0.05, "dark_steel", Vector3(x, -0.004, side * 0.029)))
		cap.add(MeshUtil.hex_bolt(0.014, 0.008, "dark_steel", Vector3(x, -0.03, side * 0.029)))
	# Газ в цилиндре — светится в зависимости от температуры и фазы сгорания.
	var gas := MeshUtil.cyl(0.0375, 1.0, "gas", Vector3(x, 0.2, 0), Vector3.ZERO, 24)
	var gm := (MeshUtil.material("gas") as StandardMaterial3D).duplicate() as StandardMaterial3D
	gas.material_override = gm
	block.add(gas)
	_gas.append(gas)
	_gas_mat.append(gm)
	var flame := OmniLight3D.new()
	flame.position = Vector3(x, HEAD_BOTTOM - 0.008, -0.02)
	flame.light_color = Color(1.0, 0.55, 0.2)
	flame.omni_range = 0.12
	flame.light_energy = 0.0
	block.add(flame)
	_flames.append(flame)


func _build_head() -> void:
	var gasket := _part("head_gasket", "Прокладка головки блока", block, ["cylinder_head"], Vector3(0, 0.5, 0.25), true, "ГБЦ",
		"Металлоармированная прокладка между блоком и головкой. Уплотняет камеры сгорания, каналы охлаждающей жидкости и масла. После снятия головки ставится только новая.",
		"Толщина в сжатом состоянии: 1,5 мм\nОкантовка отверстий цилиндров: сталь")
	var gcsg := CSGCombiner3D.new()
	gasket.add(gcsg)
	var gbox := CSGBox3D.new()
	gbox.size = Vector3(0.405, 0.0015, 0.165)
	gbox.position = Vector3(0, DECK + 0.00075, 0)
	gbox.material = MeshUtil.material("gasket")
	gcsg.add_child(gbox)
	for gx in CX:
		var gh := CSGCylinder3D.new()
		gh.operation = CSGShape3D.OPERATION_SUBTRACTION
		gh.radius = 0.0385
		gh.height = 0.01
		gh.sides = 32
		gh.position = Vector3(gx, DECK, 0)
		gcsg.add_child(gh)
		# Стальная окантовка отверстия цилиндра.
		gasket.add(MeshUtil.torus(0.0385, 0.0405, "steel", Vector3(gx, DECK + 0.0008, 0)))
	for k in 10:
		var bx := -0.19 + (k / 2) * 0.095
		var gb := CSGCylinder3D.new()
		gb.operation = CSGShape3D.OPERATION_SUBTRACTION
		gb.radius = 0.0065
		gb.height = 0.01
		gb.position = Vector3(bx, DECK, -0.07 if k % 2 == 0 else 0.07)
		gcsg.add_child(gb)
	var head := _part("cylinder_head", "Головка блока цилиндров", block, ["cam_housing", "intake_manifold", "exhaust_manifold", "thermostat", "cam_sprocket", "spark_plug_1", "spark_plug_2", "spark_plug_3", "spark_plug_4"], Vector3(0, 0.45, 0.45), true, "ГБЦ",
		"Головка из алюминиевого сплава с клиновыми камерами сгорания. Клапаны стоят в один ряд под распредвалом, впускные и выпускные каналы выходят на левую сторону. Сёдла и направляющие втулки запрессованы.",
		"Материал: алюминиевый сплав АЛ4\nОбъём камеры сгорания: около 48 см³\nСтепень сжатия: 8,5\nКрепление: 10 болтов, затяжка в 2 приёма до 104–116 Н·м")
	var csg := CSGCombiner3D.new()
	head.add(csg)
	var hb := CSGBox3D.new()
	hb.size = Vector3(0.41, HEAD_TOP - HEAD_BOTTOM, 0.17)
	hb.position = Vector3(0, (HEAD_TOP + HEAD_BOTTOM) * 0.5, 0)
	hb.material = MeshUtil.material("aluminum")
	csg.add_child(hb)
	for x in CX:
		var ch := CSGCylinder3D.new()
		ch.operation = CSGShape3D.OPERATION_SUBTRACTION
		ch.radius = 0.034
		ch.height = 0.013
		ch.position = Vector3(x, HEAD_BOTTOM + 0.0055, -0.002)
		csg.add_child(ch)
	# Приливы каналов на левой стороне.
	for px in [-0.095, 0.095]:
		head.add(MeshUtil.box(Vector3(0.05, 0.04, 0.02), "aluminum", Vector3(px, 0.255, 0.093)))
	for px in [-0.16, 0.0, 0.16]:
		head.add(MeshUtil.box(Vector3(0.04, 0.03, 0.02), "aluminum", Vector3(px, 0.232, 0.093)))
	# Колодцы свечей на правой стороне.
	for px in CX:
		head.add(MeshUtil.cyl(0.016, 0.03, "aluminum", Vector3(px, 0.25, -0.08), Vector3(-0.35, 0, 0)))
	# Болты крепления головки (шестигранные головки под корпусом распредвала) и шпильки корпуса.
	for k in 10:
		var bx := -0.19 + (k / 2) * 0.095
		var bz := -0.07 if k % 2 == 0 else 0.07
		head.add(MeshUtil.hex_bolt(0.019, 0.012, "dark_steel", Vector3(bx, HEAD_TOP + 0.006, bz)))
		head.add(MeshUtil.cyl(0.011, 0.002, "steel", Vector3(bx, HEAD_TOP + 0.001, bz)))
	for k in 6:
		head.add(MeshUtil.cyl(0.004, 0.035, "steel", Vector3(-0.17 + k * 0.068, HEAD_TOP + 0.017, CAM_Z + (0.03 if k % 2 == 0 else -0.03))))
	# Отводящий патрубок рубашки охлаждения спереди и рым-болт.
	head.add(MeshUtil.box(Vector3(0.03, 0.03, 0.05), "aluminum", Vector3(-0.218, 0.262, 0.04)))
	head.add(MeshUtil.cyl_x(0.013, 0.04, "aluminum", Vector3(-0.24, 0.262, 0.06)))
	head.add(MeshUtil.box(Vector3(0.006, 0.04, 0.03), "dark_steel", Vector3(0.21, 0.3, 0.06)))
	_build_valvetrain(head)


func _valve_x(cyl: int, intake: bool) -> float:
	# Порядок клапанов спереди: В-Вп | Вп-В | В-Вп | Вп-В (выпускной/впускной).
	var first_exhaust := cyl == 0 or cyl == 2
	var front := CX[cyl] - 0.017
	var back := CX[cyl] + 0.017
	if intake:
		return back if first_exhaust else front
	return front if first_exhaust else back


func _build_valvetrain(head: EnginePart) -> void:
	for i in 4:
		for intake in [false, true]:
			var n := i + 1
			var kind := "впускной" if intake else "выпускной"
			var x := _valve_x(i, intake)
			var key := "%s_%d" % ["in" if intake else "ex", n]
			var rocker := _part("rocker_" + key, "Рычаг привода клапана — %s, цил. %d" % [kind, n], head, ["cam_housing"], Vector3(0, 0.3, -0.12), true, "ГРМ",
				"Рычаг (коромысло) одним концом опирается на сферическую головку регулировочного болта, другим давит на торец стержня клапана; посередине его нажимает кулачок. Плечи 1:1,5 — подъём клапана в полтора раза больше подъёма кулачка. Держится пружинной скобой.",
				"Тепловой зазор кулачок–рычаг на холодном: 0,15 мм\nПередаточное отношение: 1,5")
			var pivot := Node3D.new()
			pivot.position = Vector3(x, VALVE_TIP_Y + 0.004, PIVOT_Z)
			rocker.add(pivot)
			# Штампованный рычаг: корытообразное сечение, сфера под болт, пятка под стержень,
			# площадка под кулачок посередине.
			pivot.add_child(MeshUtil.box(Vector3(0.014, 0.005, 0.054), "dark_steel", Vector3(0, -0.0015, 0.022)))
			for side in [-1.0, 1.0]:
				pivot.add_child(MeshUtil.box(Vector3(0.0015, 0.009, 0.05), "dark_steel", Vector3(side * 0.0065, 0.001, 0.022)))
			pivot.add_child(MeshUtil.box(Vector3(0.012, 0.0035, 0.016), "steel", Vector3(0, 0.0025, 0.03)))
			pivot.add_child(MeshUtil.cyl(0.0068, 0.008, "dark_steel", Vector3.ZERO))
			pivot.add_child(MeshUtil.box(Vector3(0.01, 0.003, 0.007), "steel", Vector3(0, -0.004, 0.045)))
			# Пружинная скоба, прижимающая рычаг к болту.
			pivot.add_child(MeshUtil.torus(0.006, 0.0075, "steel", Vector3(0, 0.004, 0.006), Vector3(PI * 0.5, 0, 0)))
			# Регулировочный болт с контргайкой и втулка.
			head.add(MeshUtil.cyl(0.005, 0.03, "steel", Vector3(x, VALVE_TIP_Y - 0.012, PIVOT_Z)))
			head.add(MeshUtil.hex_bolt(0.016, 0.006, "dark_steel", Vector3(x, VALVE_TIP_Y - 0.016, PIVOT_Z)))
			head.add(MeshUtil.cyl(0.009, 0.012, "aluminum", Vector3(x, HEAD_TOP + 0.003, PIVOT_Z)))
			var valve := _part("valve_" + key, "Клапан %s с пружинами (цил. %d)" % [kind, n], head, ["rocker_" + key, "cylinder_head"], Vector3(0, 0.22, 0.12 if intake else 0.16), true, "ГРМ",
				"Тарельчатый клапан. Закрывается двумя пружинами — наружной и внутренней, — опирающимися на тарелку с сухарями. На стержне маслоотражательный колпачок.\n" + ("Впускной клапан крупнее: через него идёт холодная смесь." if intake else "Выпускной клапан из жаропрочной стали работает при 700–800 °C."),
				("Диаметр тарелки: 38 мм" if intake else "Диаметр тарелки: 33 мм") + "\nДиаметр стержня: 8 мм\nПодъём: 9,5 мм\nПружины: наружная и внутренняя")
			var stem_len := VALVE_TIP_Y - VALVE_SEAT_Y
			var head_r := EngineSpecs.INTAKE_VALVE_DIAMETER * 0.5 if intake else EngineSpecs.EXHAUST_VALVE_DIAMETER * 0.5
			# Тарельчатый клапан — тело вращения: фаска 45°, поясок, плавный переход в стержень.
			var vprof := PackedVector2Array([
				Vector2(0.0, 0.0), Vector2(0.0, head_r - 0.0015), Vector2(0.0012, head_r), Vector2(0.002, head_r),
				Vector2(0.0035, head_r - 0.0015), Vector2(0.006, head_r * 0.55), Vector2(0.01, 0.0065), Vector2(0.016, 0.0042),
				Vector2(stem_len - 0.006, 0.004), Vector2(stem_len - 0.0055, 0.0034), Vector2(stem_len - 0.0045, 0.004),
				Vector2(stem_len, 0.004), Vector2(stem_len, 0.0)])
			valve.add(MeshUtil.mi(MeshUtil.lathe(vprof, 28), "steel" if intake else "dark_steel", Vector3(x, VALVE_SEAT_Y, 0)))
			# Тарелка пружин с сухарями.
			var rprof := PackedVector2Array([Vector2(0.0, 0.0045), Vector2(0.0, 0.0135), Vector2(0.002, 0.0135), Vector2(0.0045, 0.008), Vector2(0.0045, 0.0045)])
			valve.add(MeshUtil.mi(MeshUtil.lathe(rprof, 24), "steel", Vector3(x, VALVE_TIP_Y - 0.0105, 0)))
			valve.add(MeshUtil.cyl(0.0052, 0.006, "dark_steel", Vector3(x, VALVE_TIP_Y - 0.008, 0)))
			# Маслоотражательный колпачок на направляющей втулке.
			head.add(MeshUtil.cyl(0.0065, 0.008, "rubber", Vector3(x, HEAD_TOP + 0.002, 0)))
			head.add(MeshUtil.cyl(0.0135, 0.0015, "steel", Vector3(x, HEAD_TOP - 0.003, 0)))
			# Две пружины — наружная и внутренняя (навивка в разные стороны).
			var spring := Node3D.new()
			spring.position = Vector3(x, 0, 0)
			spring.add_child(MeshUtil.mi(MeshUtil.spring_mesh(0.0115, 0.0017, 5.5), "steel"))
			spring.add_child(MeshUtil.mi(MeshUtil.spring_mesh(0.0082, 0.0012, 7.0), "dark_steel", Vector3.ZERO, Vector3(0, PI, 0)))
			head.add(spring)
			_valves.append({"part": valve, "rocker": pivot, "rocker_part": rocker, "spring": spring, "cyl": i, "intake": intake, "x": x})
	# Корпус подшипников распредвала с валом.
	var housing := _part("cam_housing", "Корпус подшипников распредвала", head, ["valve_cover", "cam_sprocket"], Vector3(0, 0.55, -0.1), true, "ГРМ",
		"Алюминиевый корпус с пятью опорами распредвала. Крепится к головке шпильками, часть которых одновременно держит саму головку. Снимается вместе с валом.",
		"Материал: алюминиевый сплав\nОпор: 5")
	for k in 5:
		housing.add(MeshUtil.box(Vector3(0.018, 0.03, 0.05), "aluminum", Vector3(MAIN_X[k], CAM_Y - 0.004, CAM_Z)))
	housing.add(MeshUtil.box(Vector3(0.40, 0.012, 0.012), "aluminum", Vector3(0, CAM_Y - 0.022, CAM_Z + 0.03)))
	housing.add(MeshUtil.box(Vector3(0.40, 0.012, 0.012), "aluminum", Vector3(0, CAM_Y - 0.022, CAM_Z - 0.03)))
	var cam := _part("camshaft", "Распределительный вал", housing, ["cam_housing"], Vector3(0.36, 0.05, 0), true, "ГРМ",
		"Литой чугунный распредвал с отбелёнными кулачками, вращается вдвое медленнее коленвала. Восемь кулачков через рычаги открывают клапаны по фазам 12°–40° для впуска и 42°–10° для выпуска.",
		"Опор: 5\nПодъём кулачка: 6,3 мм\nПродолжительность впуска/выпуска: 232°\nПерекрытие клапанов: 22°")
	_cam_content = Node3D.new()
	_cam_content.position = Vector3(0, CAM_Y, CAM_Z)
	cam.add(_cam_content)
	_cam_content.add_child(MeshUtil.cyl_x(0.0115, 0.42, "dark_steel", Vector3(-0.005, 0, 0)))
	for k in 5:
		_cam_content.add_child(MeshUtil.cyl_x(0.0228, 0.016, "steel", Vector3(MAIN_X[k], 0, 0)))
	for v in _valves:
		var lobe_profile := _lobe_profile(v["intake"])
		var lobe := MeshUtil.mi(MeshUtil.extrude_x(lobe_profile, 0.013), "steel", Vector3(v["x"], 0, 0))
		lobe.rotation.x = PI + EngineSpecs.CYCLE_OFFSET[v["cyl"]] * 0.5
		_cam_content.add_child(lobe)
	# Крышка головки.
	var cover := _part("valve_cover", "Крышка головки (клапанная)", head, ["air_filter_housing"], Vector3(0, 0.32, -0.25), false, "ГБЦ",
		"Штампованная крышка закрывает распредвал, рычаги и звёздочку. Сверху — маслозаливная горловина, сбоку — патрубок вентиляции картера, ведущий в воздушный фильтр.",
		"Уплотнение: пробковая или резиновая прокладка\nКрепление: 8 гаек")
	# Штампованная крышка: сечение со скруглёнными углами, выдавленное вдоль двигателя.
	var sec := PackedVector2Array()
	sec.append(Vector2(0.352, -0.082))
	sec.append_array(MeshUtil.circle_points(Vector2(0.378, -0.058), 0.022, -PI * 0.5, 0.0, 6))
	sec.append_array(MeshUtil.circle_points(Vector2(0.378, 0.048), 0.022, 0.0, PI * 0.5, 6))
	sec.append(Vector2(0.352, 0.072))
	cover.add(MeshUtil.mi(MeshUtil.extrude_x(sec, 0.45), "valve_cover", Vector3(-0.025, 0, 0)))
	cover.add(MeshUtil.box(Vector3(0.46, 0.006, 0.165), "valve_cover", Vector3(-0.025, 0.353, -0.005)))   # отбортовка
	cover.add(MeshUtil.box(Vector3(0.452, 0.004, 0.158), "rubber", Vector3(-0.025, 0.3505, -0.005)))     # прокладка
	for rz in [-0.035, 0.0, 0.035]:
		cover.add(MeshUtil.box(Vector3(0.36, 0.004, 0.006), "valve_cover", Vector3(-0.0, 0.4005, rz - 0.005)))
	# Гайки крепления с шайбами.
	for k in 8:
		var nx := -0.21 + (k % 4) * 0.14
		var nz := 0.078 if k < 4 else -0.088
		cover.add(MeshUtil.cyl(0.011, 0.002, "steel", Vector3(nx, 0.357, nz)))
		cover.add(MeshUtil.hex_bolt(0.011, 0.007, "dark_steel", Vector3(nx, 0.361, nz)))
	# Маслозаливная горловина с крышкой и патрубок вентиляции картера.
	cover.add(MeshUtil.cyl(0.022, 0.015, "valve_cover", Vector3(0.12, 0.405, -0.02)))
	var cap_prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.028), Vector2(0.006, 0.028), Vector2(0.012, 0.022), Vector2(0.014, 0.0)])
	cover.add(MeshUtil.mi(MeshUtil.lathe(cap_prof, 24), "black", Vector3(0.12, 0.412, -0.02)))
	cover.add(MeshUtil.box(Vector3(0.04, 0.008, 0.006), "black", Vector3(0.12, 0.428, -0.02)))
	cover.add(MeshUtil.cyl_z(0.008, 0.03, "valve_cover", Vector3(0.17, 0.39, 0.075)))
	cover.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(0.17, 0.39, 0.09), Vector3(0.17, 0.41, 0.12), Vector3(0.09, 0.43, 0.13), Vector3(0.05, 0.43, 0.13)], 6), 0.009, 10), "rubber"))


func _lobe_profile(intake: bool) -> PackedVector2Array:
	# Кулачок: радиус = базовая окружность + подъём кулачка в данной точке.
	var pts := PackedVector2Array()
	if _profile_sim == null:
		_profile_sim = EngineSim.new()
	var sim := _profile_sim
	var full := EngineSpecs.VALVE_LIFT / EngineSpecs.ROCKER_RATIO + EngineSpecs.VALVE_CLEARANCE
	for k in 72:
		var psi := TAU * k / 72.0
		var r := CAM_BASE_R + sim.cam_profile(psi * 2.0, intake) * full
		pts.append(Vector2(cos(psi), sin(psi)) * r)
	return pts


func _build_timing() -> void:
	var front_cover := _part("front_cover", "Крышка привода распредвала", block, ["crank_pulley", "oil_pan"], Vector3(-0.3, 0, 0), true, "ГРМ",
		"Алюминиевая крышка закрывает цепной привод. В ней сальник коленвала; на прилив ставится датчик-указатель ВМТ, а напротив него — метки на шкиве.",
		"Материал: алюминиевый сплав\nСальник: 40×56×7")
	# Контур крышки повторяет привод: оболочка звёздочек коленвала и промвала плюс фланец.
	var cpts := PackedVector2Array()
	cpts.append_array(MeshUtil.circle_points(Vector2(0.0, 0.0), 0.06, 0.0, TAU, 20))
	cpts.append_array(MeshUtil.circle_points(Vector2(0.08, -0.07), 0.075, 0.0, TAU, 20))
	cpts.append_array(MeshUtil.circle_points(Vector2(0.26, -0.02), 0.07, 0.0, TAU, 20))
	cpts.append(Vector2(0.29, 0.08))
	cpts.append(Vector2(0.29, -0.09))
	cpts.append(Vector2(-0.04, 0.085))
	var chull := MeshUtil.convex_hull(cpts)
	chull.remove_at(chull.size() - 1)
	front_cover.add(MeshUtil.mi(MeshUtil.extrude_x(chull, 0.018), "aluminum", Vector3(-0.247, 0, 0)))
	front_cover.add(MeshUtil.cyl_x(0.03, 0.012, "aluminum", Vector3(-0.258, 0, 0)))     # прилив сальника
	front_cover.add(MeshUtil.cyl_x(0.021, 0.004, "rubber", Vector3(-0.264, 0, 0)))
	for k in 11:
		var p := chull[(k * chull.size()) / 11]
		var inset := p.normalized() * 0.008 if p.length() > 0.01 else Vector2.ZERO
		front_cover.add(MeshUtil.hex_bolt(0.011, 0.006, "dark_steel", Vector3(-0.259, p.x - inset.x, p.y - inset.y), Vector3(0, 0, PI * 0.5)))
	# Указатель ВМТ с метками 0°, 5°, 10° напротив шкива.
	for k in 3:
		var a := PI + 0.25 + k * deg_to_rad(5.0)
		front_cover.add(MeshUtil.box(Vector3(0.006, 0.012 if k == 0 else 0.008, 0.002), "plastic_white", Vector3(-0.258, cos(a) * 0.072, sin(a) * 0.072)))
	var aux_center := Vector3(CHAIN_X, 0.08, -0.07)
	var cam_center := Vector3(CHAIN_X, CAM_Y, CAM_Z)
	var crank_sp := _part("crank_sprocket", "Звёздочка коленвала", block, ["timing_chain"], Vector3(-0.2, -0.15, 0), true, "ГРМ",
		"Двухрядная ведущая звёздочка на носке коленвала, сидит на шпонке.", "Зубьев: 19")
	crank_sp.add(_sprocket(0.0295, Vector3(CHAIN_X, 0, 0)))
	_spin.append([crank_sp.content.get_child(0), 1.0, "crank", crank_sp])
	var aux_sp := _part("aux_sprocket", "Звёздочка промежуточного вала", block, ["timing_chain"], Vector3(-0.2, 0, -0.2), true, "ГРМ",
		"Звёздочка вала привода масляного насоса, трамблёра и бензонасоса.", "Зубьев: 38")
	aux_sp.add(_sprocket(0.058, aux_center))
	_spin.append([aux_sp.content.get_child(0), 0.5, "chain", aux_sp])
	var cam_sp := _part("cam_sprocket", "Звёздочка распредвала", block, ["valve_cover", "chain_tensioner"], Vector3(-0.2, 0.2, 0), true, "ГРМ",
		"Ведомая звёздочка на распредвале. Метка на ней совмещается с приливом корпуса подшипников при положении 4-го цилиндра в ВМТ такта сжатия — так выставляются фазы.",
		"Зубьев: 38\nПередаточное отношение привода: 2:1")
	cam_sp.add(_sprocket(0.058, cam_center))
	_spin.append([cam_sp.content.get_child(0), 0.5, "chain", cam_sp])
	var tensioner := _part("chain_tensioner", "Натяжитель цепи с башмаком", block, ["valve_cover"], Vector3(-0.15, 0.25, 0.25), true, "ГРМ",
		"Плунжерный натяжитель с пружиной поджимает башмак к ведомой ветви цепи. Ослабленная цепь стучит и может перескочить через зубья — тогда сбиваются фазы.",
		"Ход плунжера: регулируется гайкой\nБашмак: пластмасса на стальном основании")
	tensioner.add(MeshUtil.box(Vector3(0.012, 0.22, 0.012), "black", Vector3(CHAIN_X, 0.17, 0.068), Vector3(-0.12, 0, 0)))
	tensioner.add(MeshUtil.cyl_z(0.008, 0.04, "steel", Vector3(CHAIN_X, 0.2, 0.095)))
	var chain := _part("timing_chain", "Цепь привода распредвала", block, ["front_cover", "cam_sprocket"], Vector3(-0.45, 0.1, 0), true, "ГРМ",
		"Двухрядная втулочно-роликовая цепь. Охватывает звёздочки коленвала, промежуточного вала и распредвала. Растягивается со временем, отсюда характерный «звон» изношенного привода.",
		"Шаг: 9,525 мм\nЗвеньев: 116\nУспокоитель на ведущей ветви")
	_build_chain(chain, [Vector3(0, 0, 0), aux_center, cam_center], [0.0295, 0.058, 0.058])


func _sprocket(radius: float, center: Vector3) -> Node3D:
	# Двухрядная звёздочка: два зубчатых венца, ступица, облегчающие окна, болт.
	var n := Node3D.new()
	n.position = center
	var teeth := 19 if radius < 0.04 else 38
	var gear := MeshUtil.gear_x(teeth, radius - 0.0045, radius + 0.002, 0.007)
	n.add_child(MeshUtil.mi(gear, "steel", Vector3(-0.0045, 0, 0)))
	n.add_child(MeshUtil.mi(gear, "steel", Vector3(0.0045, 0, 0)))
	n.add_child(MeshUtil.cyl_x(radius - 0.006, 0.004, "dark_steel", Vector3.ZERO, 40))
	if teeth == 38:
		for k in 4:
			var a := TAU * k / 4.0 + 0.4
			n.add_child(MeshUtil.cyl_x(radius * 0.28, 0.005, "black", Vector3(-0.0005, cos(a) * radius * 0.55, sin(a) * radius * 0.55), 16))
		n.add_child(MeshUtil.box(Vector3(0.002, 0.008, 0.002), "plastic_white", Vector3(-0.009, radius * 0.75, 0)))  # метка
	n.add_child(MeshUtil.cyl_x(0.016, 0.022, "dark_steel"))
	n.add_child(MeshUtil.hex_bolt(0.017, 0.008, "steel", Vector3(-0.015, 0, 0), Vector3(0, 0, PI * 0.5)))
	return n


func _build_chain(chain: EnginePart, centers: Array, radii: Array) -> void:
	# Путь цепи — выпуклая оболочка окружностей звёздочек (в плоскости YZ).
	var pts := PackedVector2Array()
	for k in centers.size():
		var c: Vector3 = centers[k]
		pts.append_array(MeshUtil.circle_points(Vector2(c.y, c.z), radii[k] + 0.004, 0.0, TAU, 48))
	var hull := MeshUtil.convex_hull(pts)
	_chain_path.clear()
	_chain_dist.clear()
	var total := 0.0
	for k in hull.size():
		var p := Vector3(CHAIN_X, hull[k].x, hull[k].y)
		if k > 0:
			total += p.distance_to(_chain_path[k - 1])
		_chain_path.append(p)
		_chain_dist.append(total)
	_chain_length = total
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Звено двухрядной цепи: три пластины и два ролика, собранные в одну сетку.
	var st := SurfaceTool.new()
	for px in [-0.0085, 0.0, 0.0085]:
		var plate := BoxMesh.new()
		plate.size = Vector3(0.0012, 0.0115, 0.006)
		st.append_from(plate, 0, Transform3D(Basis.IDENTITY, Vector3(px, 0, 0)))
	for py in [-0.0047, 0.0047]:
		var roller := CylinderMesh.new()
		roller.top_radius = 0.003
		roller.bottom_radius = 0.003
		roller.height = 0.018
		roller.radial_segments = 8
		st.append_from(roller, 0, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, py, 0)))
	mm.mesh = st.commit()
	var count := int(_chain_length / 0.009525)
	mm.instance_count = count
	_chain_links = MultiMeshInstance3D.new()
	_chain_links.multimesh = mm
	_chain_links.material_override = MeshUtil.material("chain")
	chain.add(_chain_links)
	_update_chain(0.0)


func _chain_point(s: float) -> Array:
	s = fposmod(s, _chain_length)
	var lo := 0
	var hi := _chain_dist.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _chain_dist[mid] > s:
			hi = mid
		else:
			lo = mid
	var a := _chain_path[lo]
	var b := _chain_path[hi]
	var seg := maxf(_chain_dist[hi] - _chain_dist[lo], 1e-6)
	var t := (s - _chain_dist[lo]) / seg
	return [a.lerp(b, t), (b - a).normalized()]


func _update_chain(travel: float) -> void:
	var mm := _chain_links.multimesh
	var step := _chain_length / mm.instance_count
	for k in mm.instance_count:
		var pd := _chain_point(travel + k * step)
		var p: Vector3 = pd[0]
		var d: Vector3 = pd[1]
		var up := d
		var side := Vector3.RIGHT
		var normal := side.cross(up).normalized()
		mm.set_instance_transform(k, Transform3D(Basis(side, up, normal), p))


func _build_front_drive() -> void:
	var belt_pts := [Vector3(BELT_X, 0, 0), Vector3(BELT_X, 0.165, 0.045), Vector3(BELT_X, 0.04, -0.165)]
	var belt := _part("belt", "Ремень привода генератора и насоса", block, ["fan"], Vector3(-0.25, 0.0, 0), false, "Охлаждение",
		"Клиновой ремень от шкива коленвала вращает насос охлаждающей жидкости с вентилятором и генератор. Без ремня не заряжается аккумулятор и встаёт циркуляция — двигатель быстро перегреется.",
		"Размер: 10×8×944 мм\nПрогиб под усилием 10 кгс: 10–15 мм")
	var path := PackedVector2Array()
	var radii := [0.066, 0.056, 0.034]
	for k in 3:
		var c: Vector3 = belt_pts[k]
		path.append_array(MeshUtil.circle_points(Vector2(c.y, c.z), radii[k] + 0.003, 0.0, TAU, 40))
	var hull := MeshUtil.convex_hull(path)
	var loop := PackedVector3Array()
	for k in hull.size():
		loop.append(Vector3(BELT_X, hull[k].x, hull[k].y))
	belt.add(MeshUtil.mi(MeshUtil.tube(loop, 0.0055, 6, false), "rubber"))
	var pulley := _part("crank_pulley", "Шкив коленвала", block, ["belt"], Vector3(-0.3, -0.1, 0), true, "Охлаждение",
		"Шкив на носке коленвала, затянут храповиком. На ободе метка: при её совпадении с отметками на крышке ГРМ (0°, 5°, 10°) выставляют момент зажигания.",
		"Диаметр: 132 мм\nМетки опережения: 0°, 5°, 10°")
	var pn := _pulley(0.066, Vector3(BELT_X, 0, 0))
	pulley.add(pn)
	pn.add_child(MeshUtil.box(Vector3(0.012, 0.012, 0.004), "plastic_white", Vector3(-0.01, 0.063, 0)))
	_spin.append([pn, 1.0, "crank", pulley])
	var pump := _part("water_pump", "Насос охлаждающей жидкости", block, ["pump_pulley"], Vector3(-0.25, 0.15, 0.1), false, "Охлаждение",
		"Центробежный насос гонит антифриз через рубашку блока и головки к термостату и радиатору. Вал на двухрядном подшипнике, сальник самоподжимной.",
		"Производительность: около 70 л/мин при 5600 об/мин\nПривод: ремнём от шкива коленвала")
	var wprof := PackedVector2Array([Vector2(-0.02, 0.0), Vector2(-0.02, 0.045), Vector2(-0.008, 0.045), Vector2(0.0, 0.03), Vector2(0.012, 0.022), Vector2(0.02, 0.012), Vector2(0.02, 0.0)])
	pump.add(MeshUtil.mi(MeshUtil.lathe(wprof, 32), "aluminum", Vector3(-0.247, 0.165, 0.045), Vector3(0, 0, PI * 0.5)))
	pump.add(MeshUtil.cyl_x(0.015, 0.04, "aluminum", Vector3(-0.245, 0.2, 0.085)))   # входной патрубок
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		pump.add(MeshUtil.hex_bolt(0.011, 0.006, "dark_steel", Vector3(-0.268, 0.165 + cos(a) * 0.038, 0.045 + sin(a) * 0.038), Vector3(0, 0, PI * 0.5)))
	var pump_pulley := _part("pump_pulley", "Шкив насоса", pump, ["fan", "belt"], Vector3(-0.22, 0.1, 0.0), false, "Охлаждение", "Шкив насоса и ступица вентилятора.", "Диаметр: 112 мм")
	var ppn := _pulley(0.056, Vector3(BELT_X, 0.165, 0.045))
	pump_pulley.add(ppn)
	_spin.append([ppn, 66.0 / 56.0, "belt", pump_pulley])
	var fan := _part("fan", "Вентилятор", pump_pulley, [], Vector3(-0.35, 0.2, 0.0), false, "Охлаждение",
		"Четырёхлопастный вентилятор на ступице насоса продувает радиатор, пока работает двигатель. Без него на стоянке и в пробке двигатель перегревается.",
		"Диаметр: 330 мм\nЛопастей: 4")
	var fn := Node3D.new()
	fn.position = Vector3(-0.30, 0.165, 0.045)
	fan.add(fn)
	# Лопасть — плоская трапеция с закруглённым концом, поставленная под углом атаки.
	var blade_pts := PackedVector2Array([Vector2(0.03, -0.018), Vector2(0.15, -0.032), Vector2(0.162, -0.012), Vector2(0.162, 0.012), Vector2(0.15, 0.032), Vector2(0.03, 0.018)])
	var blade_mesh := MeshUtil.extrude_x(blade_pts, 0.003)
	for k in 4:
		var holder := Node3D.new()
		holder.rotation.x = k * PI * 0.5 + 0.2
		var blade := MeshUtil.mi(blade_mesh, "black", Vector3.ZERO, Vector3(0.0, 0.0, 0.0))
		blade.rotation = Vector3(0, 0.0, 0)
		var pitch := Node3D.new()
		pitch.rotation.y = 0.38
		pitch.add_child(blade)
		holder.add_child(pitch)
		fn.add_child(holder)
		fn.add_child(MeshUtil.cyl_x(0.004, 0.012, "steel", Vector3(0, cos(k * PI * 0.5 + 0.2) * 0.04, sin(k * PI * 0.5 + 0.2) * 0.04)))
	fn.add_child(MeshUtil.cyl_x(0.035, 0.012, "black", Vector3.ZERO, 24))
	fn.add_child(MeshUtil.cyl_x(0.02, 0.02, "steel", Vector3(0.012, 0, 0)))
	_spin.append([fn, 66.0 / 56.0, "belt", fan])
	var alt := _part("alternator", "Генератор Г-222", block, ["belt"], Vector3(0, -0.05, -0.3), false, "Электрика",
		"Генератор переменного тока со встроенным выпрямительным блоком и регулятором напряжения. Заряжает аккумулятор и питает бортсеть, пока двигатель работает выше ~900 об/мин.",
		"Максимальный ток: 55 А\nРегулируемое напряжение: 13,6–14,6 В\nПередаточное отношение привода: 2,04")
	# Корпус из двух крышек со стяжными болтами, окна охлаждения, крыльчатка за шкивом.
	var aprof := PackedVector2Array([Vector2(-0.065, 0.0), Vector2(-0.065, 0.035), Vector2(-0.058, 0.05), Vector2(-0.04, 0.058), Vector2(-0.01, 0.058),
		Vector2(-0.008, 0.055), Vector2(-0.004, 0.058), Vector2(0.03, 0.058), Vector2(0.05, 0.052), Vector2(0.06, 0.03), Vector2(0.06, 0.0)])
	alt.add(MeshUtil.mi(MeshUtil.lathe(aprof, 36), "aluminum", Vector3(-0.19, 0.04, -0.165), Vector3(0, 0, PI * 0.5)))
	for k in 12:
		var a := TAU * k / 12.0
		alt.add(MeshUtil.box(Vector3(0.02, 0.006, 0.012), "black", Vector3(-0.245, 0.04 + cos(a) * 0.045, -0.165 + sin(a) * 0.045), Vector3(a, 0, 0)))
	for k in 4:
		var a2 := TAU * k / 4.0 + 0.78
		alt.add(MeshUtil.cyl_x(0.003, 0.125, "steel", Vector3(-0.19, 0.04 + cos(a2) * 0.05, -0.165 + sin(a2) * 0.05)))
	alt.add(MeshUtil.mi(MeshUtil.gear_x(10, 0.02, 0.05, 0.006), "dark_steel", Vector3(-0.258, 0.04, -0.165)))   # крыльчатка
	alt.add(MeshUtil.box(Vector3(0.03, 0.03, 0.04), "aluminum", Vector3(-0.15, 0.065, -0.12)))     # ушко крепления
	alt.add(MeshUtil.box(Vector3(0.006, 0.08, 0.015), "dark_steel", Vector3(-0.235, 0.09, -0.125), Vector3(0.6, 0, 0)))   # натяжная планка
	alt.add(MeshUtil.cyl_x(0.006, 0.012, "copper", Vector3(-0.122, 0.06, -0.165)))   # клемма «30»
	alt.add(MeshUtil.box(Vector3(0.012, 0.02, 0.025), "black", Vector3(-0.125, 0.02, -0.17)))   # регулятор напряжения
	var apn := _pulley(0.034, Vector3(BELT_X, 0.04, -0.165))
	alt.add(apn)
	_spin.append([apn, 2.04, "belt", alt])
	var thermostat := _part("thermostat", "Термостат", block, [], Vector3(-0.15, 0.25, 0.2), false, "Охлаждение",
		"Термостат с твёрдым наполнителем направляет жидкость по малому кругу (мимо радиатора), пока двигатель холодный, и по большому — когда прогрелся. Заклинивший закрытым — перегрев, открытым — двигатель не прогревается.",
		"Начало открытия: 80±2 °C\nПолное открытие: 94±2 °C\nХод клапана: не менее 6 мм")
	# Корпус термостата с тремя патрубками и шлангами: от головки, к насосу (малый круг), к радиатору.
	var tc := Vector3(-0.3, 0.25, 0.12)
	var tprof := PackedVector2Array([Vector2(-0.035, 0.0), Vector2(-0.035, 0.022), Vector2(-0.02, 0.03), Vector2(0.02, 0.03), Vector2(0.035, 0.022), Vector2(0.035, 0.0)])
	thermostat.add(MeshUtil.mi(MeshUtil.lathe(tprof, 24), "black", tc, Vector3(PI * 0.5, 0, 0)))
	thermostat.add(MeshUtil.cyl(0.031, 0.006, "steel", tc))
	thermostat.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(-0.255, 0.262, 0.06), Vector3(-0.28, 0.262, 0.075), Vector3(-0.3, 0.255, 0.09)], 6), 0.014, 12), "rubber"))
	thermostat.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(-0.3, 0.23, 0.13), Vector3(-0.29, 0.21, 0.11), Vector3(-0.26, 0.2, 0.09), Vector3(-0.245, 0.2, 0.085)], 6), 0.011, 12), "rubber"))
	thermostat.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(-0.31, 0.26, 0.14), Vector3(-0.36, 0.27, 0.15), Vector3(-0.42, 0.27, 0.15)], 6), 0.016, 12), "rubber"))
	for hc in [Vector3(-0.285, 0.262, 0.07), Vector3(-0.26, 0.2, 0.09), Vector3(-0.39, 0.27, 0.15)]:
		thermostat.add(MeshUtil.torus(0.014, 0.018, "steel", hc, Vector3(0, 0, PI * 0.5)))


func _pulley(radius: float, center: Vector3) -> Node3D:
	# Шкив с клиновым ручьём (тело вращения) и диском со спицами.
	var n := Node3D.new()
	n.position = center
	var prof := PackedVector2Array([
		Vector2(-0.008, radius * 0.82), Vector2(-0.008, radius), Vector2(-0.006, radius), Vector2(0.0, radius - 0.008),
		Vector2(0.006, radius), Vector2(0.008, radius), Vector2(0.008, radius * 0.82)])
	var rim := MeshUtil.mi(MeshUtil.lathe(prof, 48), "dark_steel", Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	n.add_child(rim)
	n.add_child(MeshUtil.cyl_x(radius * 0.83, 0.004, "dark_steel", Vector3.ZERO, 40))
	for k in 6:
		var a := TAU * k / 6.0
		n.add_child(MeshUtil.cyl_x(radius * 0.17, 0.005, "black", Vector3(-0.0005, cos(a) * radius * 0.52, sin(a) * radius * 0.52), 12))
	n.add_child(MeshUtil.cyl_x(0.018, 0.02, "steel"))
	return n


func _build_lubrication() -> void:
	var pan := _part("oil_pan", "Поддон картера", block, [], Vector3(0, -0.4, 0), true, "Смазка",
		"Штампованный стальной поддон — резервуар масла. Внизу сливная пробка с магнитом, собирающим стальную стружку.",
		"Объём масла в двигателе: 3,75 л\nМасло: 10W-40, 15W-40 (полусинтетика или минеральное)")
	# Отбортовка с отверстиями под болты, мелкая передняя часть и глубокий отстойник сзади.
	pan.add(MeshUtil.box(Vector3(0.412, 0.004, 0.194), "painted_blue", Vector3(0, -0.0415, 0)))
	var shallow := PackedVector2Array([Vector2(-0.042, -0.085), Vector2(-0.042, 0.085), Vector2(-0.1, 0.078), Vector2(-0.108, 0.07), Vector2(-0.108, -0.07), Vector2(-0.1, -0.078)])
	pan.add(MeshUtil.mi(MeshUtil.extrude_x(shallow, 0.405), "painted_blue", Vector3(0, 0, 0)))
	var sump := PackedVector2Array([Vector2(-0.1, -0.075), Vector2(-0.1, 0.075), Vector2(-0.185, 0.07), Vector2(-0.195, 0.06), Vector2(-0.195, -0.06), Vector2(-0.185, -0.07)])
	pan.add(MeshUtil.mi(MeshUtil.extrude_x(sump, 0.2), "painted_blue", Vector3(0.085, 0, 0)))
	pan.add(MeshUtil.box(Vector3(0.012, 0.09, 0.15), "painted_blue", Vector3(-0.012, -0.145, 0), Vector3(0, 0, -0.5)))  # скос отстойника
	for k in 16:
		var bx := -0.19 + (k % 8) * (0.38 / 7.0)
		var bz := 0.091 if k < 8 else -0.091
		pan.add(MeshUtil.hex_bolt(0.01, 0.005, "dark_steel", Vector3(bx, -0.0455, bz)))
	pan.add(MeshUtil.hex_bolt(0.019, 0.01, "steel", Vector3(0.14, -0.2, 0)))   # сливная пробка
	# Рёбра жёсткости на днище.
	for rx in [-0.12, -0.06]:
		pan.add(MeshUtil.box(Vector3(0.004, 0.004, 0.13), "painted_blue", Vector3(rx, -0.109, 0)))
	var pump := _part("oil_pump", "Масляный насос с маслоприёмником", block, ["oil_pan"], Vector3(0, -0.35, -0.15), true, "Смазка",
		"Шестерённый насос с приводом от промежуточного вала. Через сетку маслоприёмника забирает масло из поддона и под давлением гонит через фильтр в главную магистраль. Редукционный клапан ограничивает давление на холодном масле.",
		"Давление на прогретом двигателе: 3,5–4,5 кгс/см² при 5600 об/мин\nНа холостом ходу: не менее 0,5 кгс/см²")
	var oprof := PackedVector2Array([Vector2(-0.03, 0.0), Vector2(-0.03, 0.026), Vector2(0.015, 0.026), Vector2(0.02, 0.03), Vector2(0.025, 0.03), Vector2(0.025, 0.0)])
	pump.add(MeshUtil.mi(MeshUtil.lathe(oprof, 24), "aluminum", Vector3(0.0, -0.085, -0.06)))
	pump.add(MeshUtil.cyl(0.012, 0.02, "aluminum", Vector3(0.018, -0.1, -0.06)))   # редукционный клапан
	pump.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(0.0, -0.115, -0.06), Vector3(0.01, -0.15, -0.06), Vector3(0.03, -0.165, -0.06)], 6), 0.007, 10), "dark_steel"))
	pump.add(MeshUtil.cyl(0.032, 0.008, "steel", Vector3(0.045, -0.178, -0.06)))     # маслоприёмник
	pump.add(MeshUtil.cyl(0.03, 0.001, "black", Vector3(0.045, -0.1825, -0.06)))     # сетка
	for k in 3:
		var a := TAU * k / 3.0
		pump.add(MeshUtil.hex_bolt(0.01, 0.006, "dark_steel", Vector3(cos(a) * 0.03, -0.054, -0.06 + sin(a) * 0.03)))
	var filter := _part("oil_filter", "Масляный фильтр", block, [], Vector3(0, -0.12, -0.3), true, "Смазка",
		"Полнопоточный фильтр с бумажным элементом, перепускным и противодренажным клапанами. Без него масло сразу выльется из магистрали — давление пропадёт.",
		"Замена: вместе с маслом, через 10–15 тыс. км")
	var fprof2 := PackedVector2Array([Vector2(-0.045, 0.0), Vector2(-0.045, 0.04), Vector2(-0.04, 0.045), Vector2(0.03, 0.045),
		Vector2(0.031, 0.043), Vector2(0.033, 0.045), Vector2(0.04, 0.045), Vector2(0.045, 0.04), Vector2(0.045, 0.0)])
	filter.add(MeshUtil.mi(MeshUtil.lathe(fprof2, 32), "oil_filter", Vector3(0.12, 0.03, -0.135), Vector3(PI * 0.5 * 0.6, 0, 0)))
	filter.add(MeshUtil.cyl(0.04, 0.006, "rubber", Vector3(0.12, 0.058, -0.115), Vector3(PI * 0.5 * 0.6, 0, 0)))
	var dipstick := _part("dipstick", "Указатель уровня масла (щуп)", block, [], Vector3(0, 0.35, -0.1), false, "Смазка",
		"Щуп с метками MIN и MAX. Уровень проверяют на холодном двигателе, стоящем на ровной площадке.", "Между метками MIN и MAX: около 1 л масла")
	dipstick.add(MeshUtil.cyl(0.003, 0.3, "steel", Vector3(0.05, 0.08, -0.1), Vector3(-0.2, 0, 0)))
	dipstick.add(MeshUtil.torus(0.006, 0.012, "painted_red", Vector3(0.05, 0.235, -0.13)))
	var aux := _part("aux_shaft", "Промежуточный вал", block, ["aux_sprocket", "distributor", "fuel_pump", "oil_pump"], Vector3(0.45, 0, -0.1), true, "Смазка",
		"Вал в правой части блока вращается вдвое медленнее коленвала. Винтовой шестернёй вращает масляный насос и трамблёр, эксцентриком толкает шток бензонасоса.",
		"Опор: 2 (втулки)\nПривод: цепь, звёздочка 38 зубьев")
	aux.add(MeshUtil.cyl_x(0.012, 0.25, "dark_steel", Vector3(-0.1, 0.08, -0.07)))
	aux.add(MeshUtil.cyl_x(0.018, 0.012, "brass", Vector3(-0.0, 0.08, -0.07)))


func _build_ignition() -> void:
	var dist := _part("distributor", "Распределитель зажигания (трамблёр)", block, ["distributor_cap"], Vector3(0, 0.25, -0.25), true, "Зажигание",
		"Распределитель 30.3706: кулачок размыкает контакты прерывателя, ток в первичной обмотке катушки обрывается, и во вторичной наводится 15–20 кВ. Центробежный регулятор увеличивает опережение с ростом оборотов, вакуумный — при малой нагрузке. Поворотом корпуса выставляют начальный угол.",
		"Угол замкнутого состояния контактов: 55±3°\nЗазор контактов: 0,35–0,45 мм\nНачальное опережение: 1–3° до ВМТ\nЦентробежный регулятор: до 27° по коленвалу")
	var dprof := PackedVector2Array([Vector2(-0.06, 0.0), Vector2(-0.06, 0.012), Vector2(-0.02, 0.012), Vector2(-0.018, 0.03), Vector2(-0.012, 0.03),
		Vector2(-0.01, 0.022), Vector2(0.04, 0.024), Vector2(0.05, 0.034), Vector2(0.058, 0.034), Vector2(0.058, 0.0)])
	dist.add(MeshUtil.mi(MeshUtil.lathe(dprof, 32), "aluminum", Vector3(-0.06, 0.17, -0.11)))
	dist.add(MeshUtil.box(Vector3(0.04, 0.006, 0.02), "aluminum", Vector3(-0.06, 0.152, -0.135)))   # пластина крепления
	dist.add(MeshUtil.hex_bolt(0.012, 0.007, "dark_steel", Vector3(-0.06, 0.157, -0.14)))
	# Вакуумный регулятор: «тарелка» с диафрагмой, тяга к пластине прерывателя, шланг к карбюратору.
	var vprof2 := PackedVector2Array([Vector2(-0.008, 0.0), Vector2(-0.008, 0.022), Vector2(0.008, 0.022), Vector2(0.012, 0.01), Vector2(0.02, 0.006), Vector2(0.02, 0.0)])
	dist.add(MeshUtil.mi(MeshUtil.lathe(vprof2, 24), "aluminum", Vector3(-0.06, 0.21, -0.16), Vector3(PI * 0.5, 0, 0)))
	dist.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(-0.06, 0.21, -0.18), Vector3(-0.06, 0.3, -0.2), Vector3(-0.1, 0.42, -0.05), Vector3(-0.04, 0.37, 0.2)], 8), 0.003, 8), "rubber"))
	# Октан-корректор с делениями.
	for k in 5:
		dist.add(MeshUtil.box(Vector3(0.0015, 0.004, 0.001), "plastic_white", Vector3(-0.07 + k * 0.004, 0.156, -0.146)))
	var cap := _part("distributor_cap", "Крышка распределителя и бегунок", dist, ["wire_coil"], Vector3(0, 0.18, -0.12), true, "Зажигание",
		"Пластмассовая крышка с центральным угольным контактом и четырьмя боковыми выводами. Бегунок с резистором вращается внутри и передаёт высокое напряжение на провод нужной свечи.",
		"Сопротивление резистора бегунка: 4–6 кОм")
	var cprof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.036), Vector2(0.006, 0.038), Vector2(0.03, 0.036), Vector2(0.036, 0.03), Vector2(0.038, 0.0)])
	cap.add(MeshUtil.mi(MeshUtil.lathe(cprof, 32), "distributor_cap", Vector3(-0.06, 0.226, -0.11)))
	# Пять выводов: центральный от катушки и четыре к свечам.
	cap.add(MeshUtil.cyl(0.007, 0.016, "distributor_cap", Vector3(-0.06, 0.27, -0.11)))
	for t in 4:
		cap.add(MeshUtil.cyl(0.0065, 0.014, "distributor_cap", _cap_tower(t) - Vector3(0, 0.006, 0)))
	for side in [-1.0, 1.0]:
		cap.add(MeshUtil.box(Vector3(0.004, 0.03, 0.006), "steel", Vector3(-0.06 + side * 0.039, 0.215, -0.11)))   # пружинные защёлки
	_rotor = Node3D.new()
	_rotor.position = Vector3(-0.06, 0.225, -0.11)
	cap.add(_rotor)
	_rotor.add_child(MeshUtil.box(Vector3(0.006, 0.006, 0.03), "black", Vector3(0, 0, 0.012)))
	var coil_wire := _part("wire_coil", "Центральный провод катушки", cap, [], Vector3(0, 0.25, -0.1), true, "Зажигание",
		"Провод высокого напряжения от катушки зажигания Б117А к центральному выводу крышки.", "")
	coil_wire.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(-0.06, 0.278, -0.11), Vector3(-0.07, 0.33, -0.13), Vector3(-0.15, 0.38, -0.17), Vector3(-0.21, 0.36, -0.19)], 8), 0.0035, 8), "wire"))
	# Катушка зажигания Б117А на кронштейне.
	var kprof := PackedVector2Array([Vector2(-0.06, 0.0), Vector2(-0.06, 0.029), Vector2(0.05, 0.029), Vector2(0.055, 0.022), Vector2(0.065, 0.02), Vector2(0.065, 0.0)])
	coil_wire.add(MeshUtil.mi(MeshUtil.lathe(kprof, 28), "black", Vector3(-0.21, 0.29, -0.19)))
	coil_wire.add(MeshUtil.cyl(0.004, 0.012, "copper", Vector3(-0.195, 0.355, -0.19)))
	coil_wire.add(MeshUtil.cyl(0.004, 0.012, "copper", Vector3(-0.225, 0.355, -0.19)))
	coil_wire.add(MeshUtil.box(Vector3(0.07, 0.012, 0.004), "dark_steel", Vector3(-0.21, 0.29, -0.159)))
	for i in 4:
		var n := i + 1
		var plug_base := Vector3(CX[i], 0.255, -0.08)
		var plug := _part("spark_plug_%d" % n, "Свеча зажигания (цил. %d)" % n, get_part("cylinder_head"), ["wire_%d" % n], Vector3(0, 0.12, -0.15), true, "Зажигание",
			"Свеча А17ДВ: центральный электрод в керамическом изоляторе, боковой — на корпусе. Искра пробивает зазор и поджигает смесь. Без свечи цилиндр теряет компрессию — через отверстие со свистом выходит газ.",
			"Резьба: М14×1,25\nЗазор между электродами: 0,5–0,6 мм\nКалильное число: 17")
		# Свеча вдоль своей оси: резьба, уплотнительное кольцо, шестигранник 21 мм,
		# рёбристый изолятор, контактная гайка.
		var axis := Node3D.new()
		axis.position = plug_base
		axis.rotation = Vector3(-0.35, 0, 0)
		plug.add(axis)
		axis.add_child(MeshUtil.cyl(0.007, 0.019, "dark_steel", Vector3(0, -0.016, 0)))
		axis.add_child(MeshUtil.cyl(0.009, 0.002, "copper", Vector3(0, -0.006, 0)))
		axis.add_child(MeshUtil.hex_bolt(0.021, 0.012, "steel", Vector3(0, 0.001, 0)))
		var iprof := PackedVector2Array([Vector2(0.007, 0.0), Vector2(0.007, 0.0085), Vector2(0.012, 0.0085), Vector2(0.014, 0.0072), Vector2(0.017, 0.0072),
			Vector2(0.018, 0.0066), Vector2(0.021, 0.0066), Vector2(0.022, 0.0061), Vector2(0.025, 0.0061), Vector2(0.026, 0.0056), Vector2(0.038, 0.0052), Vector2(0.038, 0.0)])
		axis.add_child(MeshUtil.mi(MeshUtil.lathe(iprof, 20), "ceramic"))
		axis.add_child(MeshUtil.cyl(0.0035, 0.008, "steel", Vector3(0, 0.042, 0)))
		var wire := _part("wire_%d" % n, "Провод высокого напряжения (цил. %d)" % n, block, [], Vector3(0, 0.15, -0.2), false, "Зажигание",
			"Провод с распределённым сопротивлением от крышки трамблёра к свече. Если его снять, цилиндр перестанет работать, а двигатель затрясёт на трёх цилиндрах.",
			"Сопротивление: около 2 кОм/м")
		var plug_dir := Basis(Vector3.RIGHT, -0.35) * Vector3.UP
		var a := plug_base + plug_dir * 0.05
		var b := _cap_tower(i) + Vector3(0, 0.002, 0)
		var mid := (a + b) * 0.5 + Vector3(0, 0.06, -0.05)
		wire.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([a + plug_dir * 0.02, a + plug_dir * 0.05 + Vector3(0, 0.02, -0.02), mid, b + Vector3(0, 0.03, 0), b], 8), 0.0035, 8), "wire"))
		# Наконечник свечи и колпачок вывода крышки.
		var tip := MeshUtil.cyl(0.0095, 0.03, "black", a + plug_dir * 0.005, Vector3(-0.35, 0, 0))
		wire.add(tip)
		wire.add(MeshUtil.cyl(0.0075, 0.012, "rubber", b + Vector3(0, 0.004, 0)))


# Вывод крышки трамблёра к свече цилиндра i (выводы по кругу в порядке работы).
func _cap_tower(i: int) -> Vector3:
	var order: Array[int] = [0, 3, 1, 2]
	var a := TAU * order[i] / 4.0 + 0.4
	return Vector3(-0.06 + cos(a) * 0.024, 0.262, -0.11 + sin(a) * 0.024)


func _wire(part: EnginePart, a: Vector3, b: Vector3) -> void:
	# Провод — дуга из нескольких отрезков.
	var mid := (a + b) * 0.5 + Vector3(0, 0.05, -0.03)
	var pts := [a, a.lerp(mid, 0.5) + Vector3(0, 0.01, 0), mid, mid.lerp(b, 0.5) + Vector3(0, 0.01, 0), b]
	for k in pts.size() - 1:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var seg := MeshUtil.cyl(0.0035, p0.distance_to(p1), "wire", (p0 + p1) * 0.5)
		seg.basis = _basis_along(p1 - p0)
		part.add(seg)


static func _basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	return Basis(x, y, z)


func _build_fuel_intake() -> void:
	var exhaust := _part("exhaust_manifold", "Выпускной коллектор", block, ["intake_manifold"], Vector3(0, -0.1, 0.35), true, "Впуск/выпуск",
		"Чугунный коллектор собирает отработавшие газы цилиндров в приёмную трубу. На полной нагрузке раскаляется до тёмно-вишнёвого цвета.",
		"Материал: чугун\nТемпература газов на полной нагрузке: 800–900 °C")
	# Литые патрубки от трёх выпускных окон плавно сходятся в фланец приёмной трубы.
	var collector := Vector3(0.05, 0.17, 0.165)
	for px in [-0.16, 0.0, 0.16]:
		var port := Vector3(px, 0.232, 0.094)
		exhaust.add(MeshUtil.box(Vector3(0.05, 0.036, 0.01), "exhaust", port + Vector3(0, 0, 0.004)))   # фланец окна
		for sx in [-0.02, 0.02]:
			exhaust.add(MeshUtil.hex_bolt(0.012, 0.007, "dark_steel", port + Vector3(sx, -0.018, 0.012), Vector3(PI * 0.5, 0, 0)))
		var path := MeshUtil.smooth_path([port, port + Vector3(0, -0.005, 0.03), Vector3(lerpf(px, collector.x, 0.6), 0.205, 0.155), collector + Vector3(0, 0.02, 0)], 8)
		exhaust.add(MeshUtil.mi(MeshUtil.tube(path, 0.017, 14), "exhaust"))
	exhaust.add(MeshUtil.cyl(0.032, 0.012, "exhaust", collector))
	exhaust.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([collector, collector + Vector3(0.005, -0.08, 0.01), Vector3(0.06, -0.06, 0.18), Vector3(0.12, -0.12, 0.18)], 8), 0.024, 16), "exhaust"))
	for k in 3:
		var a := TAU * k / 3.0
		exhaust.add(MeshUtil.hex_bolt(0.012, 0.008, "dark_steel", collector + Vector3(cos(a) * 0.036, -0.004, sin(a) * 0.036)))
	var intake := _part("intake_manifold", "Впускной коллектор", block, ["carburetor"], Vector3(0, 0.1, 0.3), true, "Впуск/выпуск",
		"Алюминиевый коллектор подводит смесь от карбюратора к каналам головки. Снизу проходит канал охлаждающей жидкости: подогрев улучшает испарение бензина на холодном двигателе.",
		"Материал: алюминиевый сплав\nПодогрев: жидкостный")
	# Под карбюратором — площадка с двумя каналами, от неё изогнутые патрубки к окнам головки.
	intake.add(MeshUtil.box(Vector3(0.1, 0.012, 0.08), "aluminum", Vector3(0, 0.3, 0.16)))
	intake.add(MeshUtil.box(Vector3(0.09, 0.03, 0.07), "aluminum", Vector3(0, 0.281, 0.16)))
	for px in [-0.095, 0.095]:
		var port := Vector3(px, 0.255, 0.094)
		intake.add(MeshUtil.box(Vector3(0.06, 0.044, 0.01), "aluminum", port + Vector3(0, 0, 0.004)))
		var path := MeshUtil.smooth_path([port, port + Vector3(0, 0.005, 0.03), Vector3(px * 0.55, 0.275, 0.15), Vector3(px * 0.2, 0.28, 0.16)], 8)
		intake.add(MeshUtil.mi(MeshUtil.tube(path, 0.0185, 14), "aluminum"))
		for sx in [-0.024, 0.024]:
			intake.add(MeshUtil.hex_bolt(0.012, 0.007, "dark_steel", port + Vector3(sx, 0.02, 0.012), Vector3(PI * 0.5, 0, 0)))
	# Канал подогрева жидкостью снизу и шланги к нему.
	intake.add(MeshUtil.cyl_x(0.012, 0.16, "aluminum", Vector3(0, 0.262, 0.172)))
	intake.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(-0.08, 0.262, 0.172), Vector3(-0.15, 0.25, 0.17), Vector3(-0.22, 0.24, 0.12)], 6), 0.007, 10), "rubber"))
	# Шпильки карбюратора.
	for k in 4:
		intake.add(MeshUtil.cyl(0.004, 0.02, "steel", Vector3(-0.04 + (k % 2) * 0.08, 0.312, 0.125 + (k / 2) * 0.07)))
	var carb := _part("carburetor", "Карбюратор «Озон 2107»", block, ["air_filter_housing"], Vector3(0, 0.35, 0.3), true, "Топливо",
		"Двухкамерный карбюратор с падающим потоком. Первая камера открывается педалью, вторая — пневмоприводом при большом расходе воздуха. Системы: главные дозирующие, холостого хода с винтами количества и качества, ускорительный насос, экономайзер мощностных режимов, эконостат, пусковое устройство с воздушной заслонкой.",
		"Диффузоры: 22 и 25 мм\nГлавные топливные жиклёры: 112 и 150\nТопливный жиклёр ХХ: 50\nУровень топлива в поплавковой камере: 6,5 мм")
	# Корпус дроссельных заслонок, корпус с диффузорами, крышка с воздушной горловиной.
	carb.add(MeshUtil.box(Vector3(0.1, 0.022, 0.085), "aluminum", Vector3(0, 0.317, 0.16)))
	carb.add(MeshUtil.box(Vector3(0.098, 0.05, 0.08), "aluminum", Vector3(0, 0.352, 0.16)))
	carb.add(MeshUtil.box(Vector3(0.1, 0.014, 0.09), "aluminum", Vector3(0, 0.384, 0.16)))
	carb.add(MeshUtil.cyl(0.042, 0.012, "aluminum", Vector3(0, 0.397, 0.16)))
	# Поплавковая камера со смотровой крышкой и штуцер подачи топлива.
	carb.add(MeshUtil.box(Vector3(0.06, 0.05, 0.035), "aluminum", Vector3(0.0, 0.348, 0.217)))
	carb.add(MeshUtil.cyl_z(0.007, 0.03, "brass", Vector3(0.025, 0.38, 0.235)))
	# Ускорительный насос (крышка с диафрагмой) и пневмопривод второй камеры.
	carb.add(MeshUtil.cyl_x(0.018, 0.012, "aluminum", Vector3(-0.056, 0.35, 0.18)))
	var pneumo := PackedVector2Array([Vector2(-0.01, 0.0), Vector2(-0.01, 0.024), Vector2(0.006, 0.024), Vector2(0.012, 0.012), Vector2(0.016, 0.0)])
	carb.add(MeshUtil.mi(MeshUtil.lathe(pneumo, 24), "aluminum", Vector3(0.062, 0.335, 0.13), Vector3(0, 0, -PI * 0.5)))
	carb.add(MeshUtil.cyl_x(0.002, 0.04, "steel", Vector3(0.06, 0.32, 0.13)))
	# Винты количества и качества смеси, клапан ЭПХХ, рычаг подсоса.
	carb.add(MeshUtil.cyl(0.004, 0.02, "brass", Vector3(-0.03, 0.31, 0.205), Vector3(0.6, 0, 0)))
	carb.add(MeshUtil.cyl(0.0045, 0.018, "brass", Vector3(0.03, 0.31, 0.205), Vector3(0.6, 0, 0)))
	carb.add(MeshUtil.cyl_z(0.008, 0.02, "black", Vector3(-0.035, 0.36, 0.205)))
	carb.add(MeshUtil.box(Vector3(0.004, 0.025, 0.008), "steel", Vector3(-0.054, 0.39, 0.14)))
	# Винты крепления крышки и гайки на шпильках.
	for k in 5:
		carb.add(MeshUtil.cyl(0.004, 0.004, "steel", Vector3(-0.042 + k * 0.021, 0.392, 0.118)))
	for k in 4:
		carb.add(MeshUtil.hex_bolt(0.011, 0.006, "dark_steel", Vector3(-0.04 + (k % 2) * 0.08, 0.31, 0.125 + (k / 2) * 0.07)))
	# Шланг от бензонасоса.
	carb.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(0.025, 0.38, 0.25), Vector3(0.05, 0.4, 0.26), Vector3(0.12, 0.42, 0.2), Vector3(0.15, 0.42, 0.0), Vector3(0.1, 0.35, -0.13), Vector3(0.04, 0.12, -0.16)], 8), 0.0045, 8), "rubber"))
	for k in 2:
		var xb := -0.022 if k == 0 else 0.022
		var plate := Node3D.new()
		plate.position = Vector3(xb, 0.315, 0.16)
		carb.add(plate)
		plate.add_child(MeshUtil.cyl(0.014 if k == 0 else 0.016, 0.0015, "brass"))
		if k == 0:
			_throttle1 = plate
		else:
			_throttle2 = plate
	_choke_plate = Node3D.new()
	_choke_plate.position = Vector3(-0.022, 0.398, 0.16)
	carb.add(_choke_plate)
	_choke_plate.add_child(MeshUtil.cyl(0.0145, 0.0015, "brass"))
	_throttle_lever = Node3D.new()
	_throttle_lever.position = Vector3(-0.055, 0.315, 0.16)
	carb.add(_throttle_lever)
	_throttle_lever.add_child(MeshUtil.box(Vector3(0.004, 0.035, 0.008), "steel", Vector3(0, 0.015, 0)))
	var filter := _part("air_filter_housing", "Корпус воздушного фильтра", block, ["air_filter_lid"], Vector3(0, 0.3, 0.25), false, "Топливо",
		"Корпус («кастрюля») фильтра стоит на карбюраторе. Заборник поворачивается: летом воздух берётся снаружи, зимой — от выпускного коллектора.",
		"Сопротивление чистого фильтра: около 1 кПа на полной мощности")
	filter.add(MeshUtil.cyl(0.13, 0.006, "black", Vector3(0, 0.41, 0.13)))
	filter.add(MeshUtil.mi(_open_ring(0.13, 0.127, 0.062), "black", Vector3(0, 0.442, 0.13)))
	filter.add(MeshUtil.torus(0.128, 0.134, "black", Vector3(0, 0.411, 0.13)))   # завальцованная кромка
	filter.add(MeshUtil.cyl(0.045, 0.012, "black", Vector3(0, 0.404, 0.16)))     # горловина на карбюратор
	# Поворотный воздухозаборник и патрубок к выпускному коллектору (зимний режим).
	filter.add(MeshUtil.mi(MeshUtil.tube(MeshUtil.smooth_path([Vector3(-0.12, 0.44, 0.13), Vector3(-0.2, 0.44, 0.14), Vector3(-0.25, 0.43, 0.16)], 6), 0.032, 16), "black"))
	filter.add(MeshUtil.torus(0.032, 0.036, "steel", Vector3(-0.165, 0.44, 0.13), Vector3(0, 0, PI * 0.5)))
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		filter.add(MeshUtil.box(Vector3(0.012, 0.03, 0.006), "steel", Vector3(cos(a) * 0.133, 0.462, 0.13 + sin(a) * 0.133), Vector3(0, -a, 0)))   # защёлки
	var element := _part("air_filter_element", "Фильтрующий элемент", filter, ["air_filter_lid"], Vector3(0, 0.25, 0.1), false, "Топливо",
		"Кольцевой элемент из гофрированного картона. Забитый элемент обогащает смесь и отнимает мощность на высоких оборотах.",
		"Замена: через 20 тыс. км, в пыльных условиях чаще")
	# Гофрированный картон: зубчатый «венец» с крупным шагом складок плюс торцевые кольца.
	element.add(MeshUtil.mi(MeshUtil.gear_x(96, 0.108, 0.116, 0.048), "plastic_white", Vector3(0, 0.44, 0.13), Vector3(0, 0, PI * 0.5)))
	for ey in [0.415, 0.465]:
		element.add(MeshUtil.mi(_open_ring(0.118, 0.08, 0.004), "oil_filter", Vector3(0, ey, 0.13)))
	element.add(MeshUtil.mi(_open_ring(0.082, 0.078, 0.048), "steel", Vector3(0, 0.44, 0.13)))   # сетка
	var lid := _part("air_filter_lid", "Крышка воздушного фильтра", filter, [], Vector3(0, 0.2, 0.0), false, "Топливо",
		"Крышка на трёх защёлках или гайке-барашке.", "")
	var lprof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.134), Vector2(0.004, 0.134), Vector2(0.008, 0.12), Vector2(0.012, 0.06), Vector2(0.012, 0.0)])
	lid.add(MeshUtil.mi(MeshUtil.lathe(lprof, 48), "black", Vector3(0, 0.471, 0.13)))
	# Гайка-барашек.
	lid.add(MeshUtil.cyl(0.009, 0.01, "steel", Vector3(0, 0.487, 0.13)))
	lid.add(MeshUtil.box(Vector3(0.04, 0.012, 0.004), "steel", Vector3(0, 0.494, 0.13)))
	var fuel_pump := _part("fuel_pump", "Бензонасос", block, [], Vector3(0, 0.0, -0.3), false, "Топливо",
		"Диафрагменный насос: эксцентрик промежуточного вала через шток качает рычаг и диафрагму, подавая бензин из бака в поплавковую камеру карбюратора. Ручной рычаг подкачки.",
		"Давление подачи: 0,2–0,3 кгс/см²\nПривод: шток от эксцентрика промвала")
	var pprof := PackedVector2Array([Vector2(-0.015, 0.0), Vector2(-0.015, 0.02), Vector2(0.0, 0.03), Vector2(0.01, 0.034), Vector2(0.016, 0.036), Vector2(0.028, 0.036), Vector2(0.034, 0.03), Vector2(0.036, 0.0)])
	fuel_pump.add(MeshUtil.mi(MeshUtil.lathe(pprof, 28), "aluminum", Vector3(0.03, 0.08, -0.11), Vector3(-PI * 0.5, 0, 0)))
	fuel_pump.add(MeshUtil.hex_bolt(0.01, 0.006, "steel", Vector3(0.03, 0.08, -0.149), Vector3(PI * 0.5, 0, 0)))   # винт крышки
	for k in 6:
		var a := TAU * k / 6.0
		fuel_pump.add(MeshUtil.cyl_z(0.0025, 0.004, "steel", Vector3(0.03 + cos(a) * 0.032, 0.08 + sin(a) * 0.032, -0.128)))
	fuel_pump.add(MeshUtil.cyl_x(0.004, 0.03, "brass", Vector3(0.055, 0.1, -0.135)))   # штуцер выхода
	fuel_pump.add(MeshUtil.cyl_x(0.004, 0.03, "brass", Vector3(0.005, 0.1, -0.135)))   # штуцер входа
	fuel_pump.add(MeshUtil.box(Vector3(0.006, 0.04, 0.008), "dark_steel", Vector3(0.06, 0.05, -0.13), Vector3(0, 0, 0.4)))   # рычаг ручной подкачки
	for k in 2:
		fuel_pump.add(MeshUtil.hex_bolt(0.012, 0.007, "dark_steel", Vector3(0.03 + (k * 2 - 1) * 0.035, 0.08, -0.105), Vector3(PI * 0.5, 0, 0)))
	_fuel_pump_lever = Node3D.new()
	_fuel_pump_lever.position = Vector3(0.03, 0.08, -0.11)
	fuel_pump.add(_fuel_pump_lever)
	_fuel_pump_lever.add_child(MeshUtil.box(Vector3(0.01, 0.03, 0.004), "steel", Vector3(0, -0.02, 0)))



func _open_ring(outer: float, inner: float, height: float) -> ArrayMesh:
	# Обечайка (кольцо с толщиной стенки) — для корпуса фильтра и элемента.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		for r in [outer, inner]:
			var p00 := Vector3(cos(a0) * r, -height * 0.5, sin(a0) * r)
			var p01 := Vector3(cos(a1) * r, -height * 0.5, sin(a1) * r)
			var p10 := Vector3(cos(a0) * r, height * 0.5, sin(a0) * r)
			var p11 := Vector3(cos(a1) * r, height * 0.5, sin(a1) * r)
			var nrm := Vector3(cos(a0), 0, sin(a0)) * (1.0 if r == outer else -1.0)
			MeshUtil._tri(st, p00, p10, p11, nrm)
			MeshUtil._tri(st, p00, p11, p01, nrm)
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		for y in [-height * 0.5, height * 0.5]:
			var nrm2 := Vector3.UP * signf(y)
			MeshUtil._tri(st, o0 * inner + Vector3.UP * y, o0 * outer + Vector3.UP * y, o1 * outer + Vector3.UP * y, nrm2)
			MeshUtil._tri(st, o0 * inner + Vector3.UP * y, o1 * outer + Vector3.UP * y, o1 * inner + Vector3.UP * y, nrm2)
	return st.commit()


func _build_rear() -> void:
	var flywheel := _part("flywheel", "Маховик", block, ["clutch_disc"], Vector3(0.35, -0.05, 0), true, "Сцепление",
		"Чугунный маховик накапливает энергию между рабочими ходами и сглаживает вращение. На ободе напрессован зубчатый венец, с которым зацепляется шестерня стартера.",
		"Зубьев венца: 129\nКрепление: 6 болтов\nМасса: около 6,5 кг")
	var fw := Node3D.new()
	fw.position = Vector3(0.225, 0, 0)
	flywheel.add(fw)
	var fprof := PackedVector2Array([
		Vector2(-0.012, 0.0), Vector2(-0.012, 0.135), Vector2(-0.008, 0.138), Vector2(0.006, 0.138), Vector2(0.006, 0.1),
		Vector2(0.012, 0.1), Vector2(0.012, 0.0)])
	fw.add_child(MeshUtil.mi(MeshUtil.lathe(fprof, 64), "cast_iron", Vector3.ZERO, Vector3(0, 0, PI * 0.5)))
	# Зубчатый венец 129 зубьев.
	fw.add_child(MeshUtil.mi(MeshUtil.gear_x(129, 0.139, 0.145, 0.012), "steel", Vector3(-0.004, 0, 0)))
	for k in 6:
		var a := TAU * k / 6.0
		fw.add_child(MeshUtil.hex_bolt(0.012, 0.007, "dark_steel", Vector3(-0.015, cos(a) * 0.03, sin(a) * 0.03), Vector3(0, 0, PI * 0.5)))
	fw.add_child(MeshUtil.box(Vector3(0.026, 0.01, 0.004), "plastic_white", Vector3(0, 0.125, 0)))
	_spin.append([fw, 1.0, "crank", flywheel])
	var disc := _part("clutch_disc", "Ведомый диск сцепления", flywheel, ["clutch_basket"], Vector3(0.28, -0.12, 0), true, "Сцепление",
		"Диск с фрикционными накладками и пружинным гасителем крутильных колебаний. Зажат между маховиком и нажимным диском корзины.",
		"Наружный диаметр накладок: 200 мм\nТолщина: 7,8 мм")
	var dn := Node3D.new()
	dn.position = Vector3(0.242, 0, 0)
	disc.add(dn)
	dn.add_child(MeshUtil.mi(_open_ring(0.1, 0.07, 0.008), "copper", Vector3.ZERO, Vector3(0, 0, PI * 0.5)))
	dn.add_child(MeshUtil.cyl_x(0.072, 0.002, "steel", Vector3.ZERO, 40))
	dn.add_child(MeshUtil.cyl_x(0.03, 0.03, "steel", Vector3(0.008, 0, 0), 24))
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		dn.add_child(MeshUtil.cyl_z(0.006, 0.022, "dark_steel", Vector3(0.0, cos(a) * 0.05, sin(a) * 0.05)))
	_spin.append([dn, 1.0, "crank", disc])
	var basket := _part("clutch_basket", "Корзина сцепления", disc, [], Vector3(0.3, 0.1, 0), true, "Сцепление",
		"Нажимной диск с диафрагменной пружиной прижимает ведомый диск к маховику. Выжимной подшипник давит на лепестки пружины и разжимает сцепление.",
		"Усилие пружины: около 4000 Н")
	var bn := Node3D.new()
	bn.position = Vector3(0.262, 0, 0)
	basket.add(bn)
	var bprof := PackedVector2Array([
		Vector2(-0.014, 0.112), Vector2(-0.01, 0.112), Vector2(-0.01, 0.105), Vector2(0.01, 0.1), Vector2(0.014, 0.085), Vector2(0.014, 0.07)])
	bn.add_child(MeshUtil.mi(MeshUtil.lathe(bprof, 48), "steel", Vector3.ZERO, Vector3(0, 0, PI * 0.5)))
	bn.add_child(MeshUtil.cyl_x(0.1, 0.006, "dark_steel", Vector3(-0.008, 0, 0), 40))   # нажимной диск
	# Лепестки диафрагменной пружины.
	for k in 18:
		var a := TAU * k / 18.0
		var finger := MeshUtil.box(Vector3(0.002, 0.045, 0.011), "dark_steel", Vector3(0.015, 0, 0))
		var holder := Node3D.new()
		holder.rotation.x = a
		holder.add_child(finger)
		finger.position = Vector3(0.016, 0.05, 0)
		finger.rotation.z = 0.25
		bn.add_child(holder)
	for k in 6:
		var a2 := TAU * k / 6.0
		bn.add_child(MeshUtil.hex_bolt(0.012, 0.006, "dark_steel", Vector3(-0.01, cos(a2) * 0.108, sin(a2) * 0.108), Vector3(0, 0, PI * 0.5)))
	_spin.append([bn, 1.0, "crank", basket])
	var starter := _part("starter", "Стартер 35.3708", block, [], Vector3(0.15, -0.1, 0.3), false, "Электрика",
		"Электродвигатель постоянного тока последовательного возбуждения. Тяговое реле вводит шестерню в зацепление с венцом маховика и замыкает силовые контакты; обгонная муфта не даёт двигателю раскрутить якорь.",
		"Мощность: 1,3 кВт\nТок полного торможения: до 500 А\nМомент полного торможения: 13,5 Н·м")
	var sprof := PackedVector2Array([Vector2(-0.09, 0.0), Vector2(-0.09, 0.03), Vector2(-0.08, 0.042), Vector2(0.05, 0.042), Vector2(0.06, 0.036), Vector2(0.075, 0.032), Vector2(0.075, 0.0)])
	starter.add(MeshUtil.mi(MeshUtil.lathe(sprof, 32), "dark_steel", Vector3(0.34, -0.03, 0.15), Vector3(0, 0, -PI * 0.5)))
	var rprof := PackedVector2Array([Vector2(-0.045, 0.0), Vector2(-0.045, 0.02), Vector2(0.04, 0.022), Vector2(0.045, 0.012), Vector2(0.05, 0.0)])
	starter.add(MeshUtil.mi(MeshUtil.lathe(rprof, 24), "steel", Vector3(0.33, 0.028, 0.15), Vector3(0, 0, -PI * 0.5)))   # тяговое реле
	starter.add(MeshUtil.cyl(0.004, 0.015, "copper", Vector3(0.36, 0.052, 0.15)))
	starter.add(MeshUtil.cyl(0.003, 0.012, "copper", Vector3(0.31, 0.05, 0.15)))
	starter.add(MeshUtil.mi(MeshUtil.gear_x(11, 0.009, 0.012, 0.012), "steel", Vector3(0.255, -0.03, 0.15)))   # шестерня привода
	for k in 2:
		starter.add(MeshUtil.cyl_x(0.004, 0.18, "steel", Vector3(0.34, -0.03 + (0.035 if k == 0 else -0.035), 0.15)))


# --- Анимация от модели ---------------------------------------------------

func update_view(sim: EngineSim, phi: float, delta: float) -> void:
	var dphi := fposmod(phi - _last_phi + PI * 2.0, PI * 4.0) - PI * 2.0
	_last_phi = phi
	var chain_on := is_installed("timing_chain") and is_installed("crank_sprocket")
	var crank_on := is_installed("crankshaft")
	if crank_on:
		_crank_unwrapped += dphi
	var alpha := fmod(phi, TAU)
	if crank_on:
		_crank_content.rotation.x = alpha
	var r := EngineSpecs.CRANK_RADIUS
	var l := EngineSpecs.ROD_LENGTH
	for i in 4:
		var throw := alpha + (PI if (i == 1 or i == 2) else 0.0)
		var pin := Vector2(r * cos(throw), r * sin(throw))  # (y, z)
		var connected := crank_on and is_installed("rod_cap_%d" % (i + 1))
		var py := pin.x + sqrt(l * l - pin.y * pin.y)
		if connected and not _pistons[i].is_detached():
			_pistons[i].content.position = Vector3(0, py, 0)
			var dir := Vector2(py - pin.x, -pin.y)
			_rods[i].content.transform = Transform3D(Basis(Vector3.RIGHT, atan2(dir.y, dir.x)), Vector3(0, pin.x, pin.y))
		# Газ над поршнем.
		var c: EngineSim.Cylinder = sim.cylinders[i]
		var crown := _pistons[i].content.position.y + PIN_HEIGHT
		var g := _gas[i]
		var top := HEAD_BOTTOM + 0.004
		var show := not _pistons[i].is_detached() and is_installed("cylinder_head")
		g.visible = show and top - crown > 0.001
		if g.visible:
			g.scale = Vector3(1, top - crown, 1)
			g.position.y = (top + crown) * 0.5
			var heat := clampf((c.t - 300.0) / 2200.0, 0.0, 1.0)
			var col := Color(0.25, 0.55, 1.0).lerp(Color(1.0, 0.55, 0.15), heat).lerp(Color(1, 0.95, 0.8), maxf(heat - 0.7, 0.0) * 2.0)
			var m := _gas_mat[i]
			m.albedo_color = Color(col.r, col.g, col.b, 0.10 + 0.35 * heat)
		_flames[i].light_energy = (c.spark_flash * 2.5 + (1.2 if c.burning else 0.0) * (1.0 - c.burn_fraction)) if show else 0.0
	# Клапанный механизм.
	var cam_on := chain_on and is_installed("camshaft")
	if cam_on:
		_cam_content.rotation.x = -phi * 0.5
	for v in _valves:
		var lift := 0.0
		if cam_on:
			var local := fposmod(phi - EngineSpecs.CYCLE_OFFSET[v["cyl"]], 4.0 * PI)
			lift = sim.valve_lift(local, v["intake"])
		var vp: EnginePart = v["part"]
		if not vp.is_detached():
			vp.content.position.y = -lift
		var spring: Node3D = v["spring"]
		var bottom := HEAD_TOP - 0.004
		var top_y := VALVE_TIP_Y - 0.008 - (lift if not vp.is_detached() else 0.0)
		spring.visible = not vp.is_detached()
		spring.scale = Vector3(1, maxf(top_y - bottom, 0.001), 1)
		spring.position.y = (top_y + bottom) * 0.5
		var rp: EnginePart = v["rocker_part"]
		if not rp.is_detached():
			(v["rocker"] as Node3D).rotation.x = asin(clampf(lift / 0.045, -1.0, 1.0))
	# Цепь, шкивы, трамблёр.
	if chain_on:
		_update_chain(_crank_unwrapped * 0.0295)
	var belt_on := crank_on and is_installed("belt") and is_installed("crank_pulley")
	for s in _spin:
		var owner_part: EnginePart = s[3]
		if owner_part.is_detached() or not crank_on:
			continue
		if (s[2] == "belt" and not belt_on) or (s[2] == "chain" and not chain_on):
			continue
		(s[0] as Node3D).rotation.x = fposmod(_crank_unwrapped * s[1], TAU)
	if _rotor != null:
		_rotor.rotation.y = -phi * 0.5
	if _fuel_pump_lever != null:
		_fuel_pump_lever.rotation.z = sin(phi * 0.5) * 0.15
	# Заслонки карбюратора.
	_throttle1.rotation.x = deg_to_rad(90.0 - sim.carb.primary_angle_deg)
	_throttle2.rotation.x = deg_to_rad(90.0 - sim.carb.secondary_angle_deg)
	_choke_plate.rotation.x = deg_to_rad(90.0 * (1.0 - sim.carb.choke * 0.93))
	_throttle_lever.rotation.x = -sim.carb.pedal * 1.2
	# Раскалённый выпускной коллектор.
	var glow := clampf((sim.ex_t - 750.0) / 500.0, 0.0, 1.0)
	var em := MeshUtil.material("exhaust")
	em.emission = Color(0.9, 0.18, 0.04) * glow * glow * 2.0


# Сборка, в которой сейчас находится деталь: ближайший снятый узел-предок
# (или null — двигатель). Детали разных сборок друг другу не мешают.
func _assembly_of(p: EnginePart, include_self: bool) -> EnginePart:
	var n: Node = p if include_self else p.home_parent()
	while n != null and n != self:
		if n is EnginePart and (n as EnginePart).removed:
			return n
		n = (n as EnginePart).home_parent() if n is EnginePart else n.get_parent()
	return null


# Детали, которые мешают снять или поставить эту: они не сняты и стоят в той же сборке.
func blocking_parts(p: EnginePart) -> Array[EnginePart]:
	var out: Array[EnginePart] = []
	var here := _assembly_of(p, false)
	for rid in p.requires:
		var q: EnginePart = parts.get(rid)
		if q == null or q.removed:
			continue
		if _assembly_of(q, true) == here:
			out.append(q)
	return out


# Вложенные детали, снятые с этой: без них узел не поставить на место.
func missing_children(p: EnginePart) -> Array[EnginePart]:
	var out: Array[EnginePart] = []
	for q in p.sub_parts():
		if q.removed:
			out.append(q)
		else:
			out.append_array(missing_children(q))
	return out


func can_remove(p: EnginePart) -> bool:
	return p != block and not p.removed and not p.animating and blocking_parts(p).is_empty()


func can_install(p: EnginePart) -> bool:
	if not p.removed or p.animating:
		return false
	if not blocking_parts(p).is_empty():
		return false
	return missing_children(p).is_empty()


func all_installed() -> bool:
	for p in part_order:
		if p.removed:
			return false
	return true


func missing_critical() -> Array[EnginePart]:
	var out: Array[EnginePart] = []
	for p in part_order:
		if p.critical and p.is_detached():
			out.append(p)
	return out


func pick(origin: Vector3, dir: Vector3) -> EnginePart:
	var best: EnginePart = null
	var best_d := 1e9
	for p in part_order:
		var d := p.ray_hit(origin, dir)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = p
	return best
