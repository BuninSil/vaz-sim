class_name CarInterior
extends Node3D

# Салон ВАЗ-2106 по образцу серийной машины. Строится в сантиметрах модели
# кузова (x — вправо, y — вперёд, z — вверх), руль слева.
#  • торпедо: мягкий чёрный верх, накладка «под дерево», бардачок, щиток
#    приборов под козырьком — указатель температуры ОЖ, спидометр до 180,
#    тахометр до 8000, указатель топлива с давлением масла; часы над пультом
#    отопителя с тремя рычажками;
#  • двухспицевый руль на колонке, три подвесные педали, рычаг КПП в чехле,
#    рычаг стояночного тормоза между сиденьями;
#  • передние сиденья с откидными спинками и подголовниками, задний диван;
#  • дверные карты из винила с тиснением, подлокотник-ручка, хромированная
#    ручка открывания, ручка стеклоподъёмника, кнопка блокировки;
#  • перфорированный потолок, солнцезащитные козырьки, салонное зеркало.

const DRIVER_X := -37.0
const STEER_RATIO := 16.4

var needles := {}         # имя -> [узел, мин. угол, макс. угол]
var steering_wheel: Node3D
var gear_lever: Node3D
var pedals: Array[Node3D] = []   # сцепление, тормоз, газ
var handbrake_lever: Node3D
var dial_mats: Array[StandardMaterial3D] = []
var materials: Array[StandardMaterial3D] = []
var paint: Material

var vinyl: StandardMaterial3D
var fabric: StandardMaterial3D
var carpet: StandardMaterial3D
var wood: StandardMaterial3D
var chrome: StandardMaterial3D
var headliner: StandardMaterial3D
var door_vinyl: StandardMaterial3D
var plastic: StandardMaterial3D
var dial_face: StandardMaterial3D
var white: StandardMaterial3D
var needle_mat: StandardMaterial3D


# parent — узел модели кузова (сантиметры), doors — имя -> сетка двери на петле.
func build(doors: Dictionary, body_paint: Material) -> void:
	paint = body_paint
	_make_materials()
	_floor()
	_dashboard()
	_cluster()
	_steering()
	_controls()
	_seats()
	_roof()
	for name in doors:
		_door_card(name, doors[name])


func set_trim(index: int) -> void:
	# Обивка: чёрная, коричневая, красная (варианты заводской комплектации).
	var f: Array[Color] = [Color(0.09, 0.085, 0.08), Color(0.3, 0.17, 0.09), Color(0.42, 0.06, 0.06)]
	var d: Array[Color] = [Color(0.07, 0.07, 0.07), Color(0.22, 0.13, 0.08), Color(0.32, 0.05, 0.05)]
	fabric.albedo_color = f[index] * float(fabric.get_meta("gain", 1.0))
	door_vinyl.albedo_color = d[index] * float(door_vinyl.get_meta("gain", 1.0))


# --- Материалы ------------------------------------------------------------------

func _mat(color: Color, rough: float, metal := 0.0, tex: Texture2D = null, scale := 0.05) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
	m.set_meta("orig_alpha", 1.0)
	m.set_meta("orig_transparency", BaseMaterial3D.TRANSPARENCY_DISABLED)
	materials.append(m)
	return m


func _make_materials() -> void:
	vinyl = _mat(Color(0.06, 0.06, 0.06), 0.55, 0.0, _grain_tex(11, 0.9, 0.06), 0.18)
	fabric = _mat(Color(0.3, 0.17, 0.09), 0.95, 0.0, _fabric_tex(), 0.11)
	carpet = _mat(Color(0.05, 0.05, 0.05), 1.0, 0.0, _grain_tex(5, 0.6, 0.35), 0.25)
	wood = _mat(Color(1, 1, 1), 0.3, 0.0, _wood_tex(), 0.012)
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.6
	chrome = _mat(Color(0.85, 0.86, 0.88), 0.12, 1.0)
	headliner = _mat(Color(0.82, 0.8, 0.72), 0.9, 0.0, _perforation_tex(), 0.18)
	door_vinyl = _mat(Color(0.22, 0.13, 0.08), 0.6, 0.0, _door_tex(), 0.025)
	door_vinyl.uv1_triplanar = false
	door_vinyl.cull_mode = BaseMaterial3D.CULL_DISABLED
	plastic = _mat(Color(0.035, 0.035, 0.035), 0.7)
	plastic.metallic_specular = 0.3
	dial_face = _mat(Color(0.015, 0.015, 0.02), 0.35)
	dial_face.emission_enabled = true
	dial_face.emission = Color(0.0, 0.0, 0.0)
	white = _mat(Color(0.92, 0.92, 0.9), 0.4)
	white.emission_enabled = true
	white.emission = Color(0.0, 0.0, 0.0)
	needle_mat = _mat(Color(1.0, 0.45, 0.1), 0.4)
	needle_mat.emission_enabled = true
	needle_mat.emission = Color(0.0, 0.0, 0.0)
	dial_mats = [white, needle_mat]
	# Фотосканы обивки (сантиметры модели: велюр ~40 см на повтор, кожзам ~50, ковролин ~1 м).
	TexLib.apply(fabric, "velour_velvet", 0.025, 1.2)
	TexLib.apply(vinyl, "fabric_leather_02", 0.02, 0.8)
	TexLib.apply(door_vinyl, "fabric_leather_02", 1.0, 0.8, false)
	TexLib.apply(carpet, "dirty_carpet", 0.012, 1.0)
	# Матовый пластик-кожзам торпедо: почти без блика.
	vinyl.roughness = 1.0
	vinyl.metallic_specular = 0.25
	carpet.metallic_specular = 0.1
	fabric.metallic_specular = 0.2
	door_vinyl.metallic_specular = 0.3


func _grain_tex(seed_v: int, freq: float, amp: float) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := 1.0 - amp + amp * (0.5 + 0.5 * n.get_noise_2d(x, y))
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# Ворсовая ткань с продольными полосами, как вставки сидений «шестёрки».
func _fabric_tex() -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = 3
	n.frequency = 0.6
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var stripe := 0.82 + 0.18 * (1.0 if (x / 8) % 2 == 0 else 0.0)
			var groove := 0.65 if x % 8 == 0 else 1.0
			var v := stripe * groove * (0.85 + 0.15 * n.get_noise_2d(x, y))
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.94))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# Шпон «под дерево»: вытянутые годовые кольца.
func _wood_tex() -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = 21
	n.frequency = 0.02
	var img := Image.create(256, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 256:
			var w := n.get_noise_2d(x * 0.15, y * 3.0) * 6.0
			var ring := 0.5 + 0.5 * sin((y * 0.35 + w) * 3.0)
			var c := Color(0.42, 0.22, 0.1).lerp(Color(0.25, 0.12, 0.05), ring * 0.8)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _perforation_tex() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	for y in range(2, 64, 6):
		for x in range(2 + (y / 6 % 2) * 3, 64, 6):
			img.set_pixel(x, y, Color(0.55, 0.55, 0.52))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# Винил дверной карты: горизонтальное тиснение с прострочкой.
func _door_tex() -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = 9
	n.frequency = 0.9
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := 0.9 + 0.1 * n.get_noise_2d(x, y)
			if y % 16 == 0:
				v *= 0.55
			elif y % 16 == 1:
				v *= 1.15
			if y % 16 == 3 and x % 4 < 2:
				v *= 0.75
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- Геометрия ------------------------------------------------------------------

func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float, r2 := -1.0, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


# «Подушка» — суперэллипсоид: коробка со скруглёнными, набитыми краями.
static func pillow(size: Vector3, roundness := 0.3, seg := 20) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e := roundness
	var pts := []
	for i in seg + 1:
		var row := []
		var v := -PI * 0.5 + PI * i / seg
		for j in seg * 2 + 1:
			var u := -PI + TAU * j / (seg * 2)
			var cv := cos(v)
			var p := Vector3(
				signf(cv) * pow(absf(cv), e) * signf(cos(u)) * pow(absf(cos(u)), e),
				signf(sin(v)) * pow(absf(sin(v)), e),
				signf(cv) * pow(absf(cv), e) * signf(sin(u)) * pow(absf(sin(u)), e))
			row.append(Vector3(p.x * size.x, p.y * size.z, p.z * size.y) * 0.5)
		pts.append(row)
	for i in seg:
		for j in seg * 2:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			# Ось y суперэллипсоида — высота, поворачиваем в систему (x, y-вперёд, z-вверх).
			for q in [a, c, b, a, d, c]:
				var w: Vector3 = q
				st.add_vertex(Vector3(w.x, w.z, w.y))
	st.generate_normals()
	return st.commit()


func _floor() -> void:
	# Пол с ковриком, тоннель КПП и кардана, щит передка, арки задних колёс.
	_add(self, _box(Vector3(134, 190, 3)), carpet, Vector3(0, 4, -22.5))
	_add(self, pillow(Vector3(28, 160, 26), 0.35), carpet, Vector3(0, 18, -21))
	_add(self, _box(Vector3(142, 3, 42)), carpet, Vector3(0, 99, -1))
	for sx in [-1.0, 1.0]:
		# Арки задних колёс внутри салона — не выходят за боковину (до ±68 см).
		_add(self, pillow(Vector3(16, 44, 30), 0.4), carpet, Vector3(sx * 60, -96, -10))
		# Пороги изнутри.
		# Пороги — только между арками колёс, иначе видны снаружи в вырезе арки.
		_add(self, _box(Vector3(5, 136, 8)), vinyl, Vector3(sx * 72, 14, -17))


func _dashboard() -> void:
	# Основной объём торпедо и мягкая накладка верха.
	_add(self, pillow(Vector3(146, 24, 24), 0.35), vinyl, Vector3(0, 90, 20))
	_add(self, pillow(Vector3(144, 22, 7), 0.4), vinyl, Vector3(0, 88, 32))
	# Накладка «под дерево» через всю панель и крышка бардачка справа.
	_add(self, _box(Vector3(118, 0.8, 5.5)), wood, Vector3(8, 77.6, 14))
	_add(self, pillow(Vector3(36, 2.5, 14), 0.2), vinyl, Vector3(40, 78.0, 21.5))
	_add(self, _box(Vector3(8, 0.6, 1.4)), chrome, Vector3(40, 76.6, 26.5))
	# Решётки обдува по краям.
	for x in [-62.0, 62.0]:
		var g := _add(self, _cyl(4.0, 1.2), plastic, Vector3(x, 77.5, 26))
		g.name = "vent"
	# Нижняя часть пульта: отопитель с тремя рычажками и часы.
	_add(self, _box(Vector3(30, 14, 22)), vinyl, Vector3(0, 86, 2))
	var heater := _add(self, _box(Vector3(24, 0.6, 9)), plastic, Vector3(0, 78.8, 5))
	heater.name = "heater"
	for k in 3:
		_add(self, _box(Vector3(5.5, 0.6, 0.5)), white, Vector3(-7 + k * 7, 78.4, 7.5))
		_add(self, _box(Vector3(1.4, 1.8, 2.2)), chrome, Vector3(-7 + k * 7, 78.0, 3.5 + k))
	# Часы.
	_dial(Vector3(0, 78.2, 16), 3.6, 0, "clock")
	# Глушка радиоприёмника.
	_add(self, _box(Vector3(18, 0.6, 4.5)), plastic, Vector3(0, 78.6, -3))


func _dial(pos: Vector3, r: float, ticks: int, name: String, a0 := -2.3, a1 := 2.3, labels: Array = []) -> void:
	# Ось цилиндра — продольная ось машины: циферблат смотрит на водителя.
	var face := _add(self, _cyl(r, 0.4), dial_face, pos)
	face.name = name
	var rim := _add(self, _cyl(r + 0.5, 0.6), chrome, pos + Vector3(0, 0.15, 0))
	rim.name = name + "_rim"
	var n := maxi(ticks, 12 if name == "clock" else 0)
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / maxf(n, 1)) if name != "clock" else TAU * i / 12.0
		var big := i % 2 == 0 or name == "clock"
		var len := r * (0.22 if big else 0.12)
		var t := _add(self, _box(Vector3(0.25 if big else 0.15, 0.1, len)), white,
			pos + Vector3(sin(a) * (r - len * 0.5 - 0.2), -0.3, cos(a) * (r - len * 0.5 - 0.2)), Vector3(0, -a, 0))
		t.rotation = Vector3(0, a, 0)
	for k in labels.size():
		var a := lerpf(a0, a1, float(k) / maxf(labels.size() - 1, 1))
		var l := Label3D.new()
		l.text = str(labels[k])
		l.font_size = 48
		l.pixel_size = r * 0.0045
		l.modulate = Color(0.95, 0.95, 0.9)
		l.outline_size = 0
		l.position = pos + Vector3(sin(a) * r * 0.62, -0.35, cos(a) * r * 0.62)
		l.rotation = Vector3(PI * 0.5, 0, 0)
		l.double_sided = false
		add_child(l)
	# Стрелка вращается вокруг оси циферблата (продольной оси машины).
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0, -0.45, 0)
	add_child(pivot)
	_add(pivot, _box(Vector3(0.35, 0.15, r * 0.88)), needle_mat, Vector3(0, 0, r * 0.4))
	_add(pivot, _cyl(r * 0.12, 0.4), plastic, Vector3.ZERO)
	needles[name] = [pivot, a0, a1]


func _cluster() -> void:
	var cx := DRIVER_X
	# Козырёк щитка приборов.
	_add(self, pillow(Vector3(50, 12, 6), 0.35), vinyl, Vector3(cx, 80, 33.5))
	_add(self, _box(Vector3(48, 0.8, 15)), plastic, Vector3(cx, 79.0, 24))
	_dial(Vector3(cx - 19.5, 78.4, 24), 4.6, 4, "temp", -0.9, 0.9, [])
	_dial(Vector3(cx - 7.5, 78.4, 24), 6.8, 18, "speed", -2.4, 2.4, [0, 20, 40, 60, 80, 100, 120, 140, 160, 180])
	_dial(Vector3(cx + 7.5, 78.4, 24), 6.8, 16, "rpm", -2.4, 2.4, [0, 1, 2, 3, 4, 5, 6, 7, 8])
	_dial(Vector3(cx + 19.5, 78.4, 24), 4.6, 4, "fuel", -0.9, 0.9, [])
	# Красная зона тахометра.
	for i in 3:
		var a := lerpf(-2.4, 2.4, (6.0 + i * 0.5) / 8.0)
		var c := Vector3(cx + 7.5, 78.1, 24)
		_add(self, _box(Vector3(0.5, 0.1, 1.2)), _mat(Color(0.8, 0.05, 0.03), 0.4), c + Vector3(sin(a) * 6.0, 0, cos(a) * 6.0), Vector3(0, a, 0))


func _steering() -> void:
	# Колонка от щита к рулю: наклон ~22° к горизонту.
	var center := Vector3(DRIVER_X, 60, 25)
	var axis := Vector3(0, 1, -0.42).normalized()
	var col := Node3D.new()
	col.position = center
	col.basis = Basis.looking_at(-axis, Vector3(0, 0, 1))
	add_child(col)
	_add(col, _cyl(2.6, 26, 3.2), plastic, Vector3(0, 0, 13), Vector3(PI * 0.5, 0, 0))
	steering_wheel = Node3D.new()
	col.add_child(steering_wheel)
	var ring := TorusMesh.new()
	ring.inner_radius = 17.6
	ring.outer_radius = 20.2
	ring.rings = 48
	ring.ring_segments = 12
	_add(steering_wheel, ring, plastic, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	# Две спицы чуть ниже горизонта и накладка сигнала с эмблемой.
	for sx in [-1.0, 1.0]:
		_add(steering_wheel, _box(Vector3(15, 3.0, 1.2)), plastic, Vector3(sx * 9.5, -1.6, 0.4), Vector3(0, 0, sx * 0.12))
	_add(steering_wheel, pillow(Vector3(10, 9, 3.5), 0.4), plastic, Vector3(0, 0, -0.8))
	_add(steering_wheel, _cyl(1.6, 0.4), chrome, Vector3(0, 0, -2.7), Vector3(PI * 0.5, 0, 0))
	# Подрулевые переключатели.
	for sx in [-1.0, 1.0]:
		_add(col, _box(Vector3(9, 1.0, 1.0)), plastic, Vector3(sx * 7, 0, 6))


func _controls() -> void:
	# Подвесные педали: сцепление, тормоз, газ.
	for x in [-50.0, -38.0, -27.0]:
		var p := Node3D.new()
		p.position = Vector3(x, 92, 14)
		add_child(p)
		_add(p, _box(Vector3(1.2, 1.2, 28)), plastic, Vector3(0, -3, -14), Vector3(-0.25, 0, 0))
		_add(p, _box(Vector3(6.5 if x > -30.0 else 7.5, 1.6, 6.0 if x > -30.0 else 5.5)), _mat(Color(0.12, 0.12, 0.12), 0.8), Vector3(0, -7, -27))
		pedals.append(p)
	# Рычаг КПП в резиновом чехле.
	_add(self, pillow(Vector3(12, 12, 8), 0.5), plastic, Vector3(0, 52, -5))
	gear_lever = Node3D.new()
	gear_lever.position = Vector3(0, 52, -3)
	add_child(gear_lever)
	_add(gear_lever, _cyl(0.7, 30), chrome, Vector3(0, 0, 15))
	gear_lever.get_child(0).rotation = Vector3(PI * 0.5, 0, 0)
	gear_lever.get_child(0).position = Vector3(0, 0, 15)
	_add(gear_lever, pillow(Vector3(4.2, 4.2, 4.2), 0.5), plastic, Vector3(0, 0, 31))
	# Ручник между сиденьями.
	handbrake_lever = Node3D.new()
	handbrake_lever.position = Vector3(0, 8, -6)
	add_child(handbrake_lever)
	_add(handbrake_lever, _box(Vector3(3, 26, 2.5)), plastic, Vector3(0, -13, 0))
	_add(handbrake_lever, _cyl(0.6, 1.5), chrome, Vector3(0, -26, 0.5), Vector3(PI * 0.5, 0, 0))
	handbrake_lever.rotation.x = 0.25
	# Пепельница и прикуриватель в тоннеле.
	_add(self, _box(Vector3(10, 0.6, 4)), chrome, Vector3(0, 78.6, -8))


func _seat(x: float, y: float, width: float, cushion_d: float, back_h: float, headrest: bool, recline: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, y, 0)
	add_child(root)
	# Каркас и салазки.
	_add(root, _box(Vector3(width - 8, cushion_d - 10, 14)), plastic, Vector3(0, 0, -15))
	# Подушка: винил по краям, ворс посередине.
	_add(root, pillow(Vector3(width, cushion_d, 13), 0.3), vinyl, Vector3(0, 0, 0))
	_add(root, pillow(Vector3(width * 0.62, cushion_d * 0.8, 4), 0.3), fabric, Vector3(0, 1, 5.5))
	# Спинка с наклоном назад.
	var back := Node3D.new()
	back.position = Vector3(0, -cushion_d * 0.5 + 3, 4)
	back.rotation.x = recline
	root.add_child(back)
	_add(back, pillow(Vector3(width, 11, back_h), 0.3), vinyl, Vector3(0, -2, back_h * 0.5))
	_add(back, pillow(Vector3(width * 0.62, 4, back_h * 0.8), 0.3), fabric, Vector3(0, 3.5, back_h * 0.5))
	if headrest:
		for sx in [-1.0, 1.0]:
			_add(back, _cyl(0.55, 10), chrome, Vector3(sx * 6, -2, back_h + 4), Vector3(PI * 0.5, 0, 0))
		_add(back, pillow(Vector3(26, 8, 16), 0.35), vinyl, Vector3(0, -2, back_h + 13))
		_add(back, pillow(Vector3(18, 2.5, 11), 0.3), fabric, Vector3(0, 1.6, back_h + 13))


func _seats() -> void:
	_seat(DRIVER_X, 30, 50, 50, 56, true, 0.3)
	_seat(-DRIVER_X, 30, 50, 50, 56, true, 0.3)
	_seat(0, -70, 128, 48, 50, false, 0.32)


func _roof() -> void:
	# Перфорированный потолок, козырьки, зеркало, плафоны на средних стойках.
	_add(self, pillow(Vector3(112, 150, 2.5), 0.25), headliner, Vector3(0, -18, 77))
	for sx in [-1.0, 1.0]:
		var v := Node3D.new()
		v.position = Vector3(sx * 28, 68, 76)
		v.rotation.x = 0.35
		add_child(v)
		_add(v, pillow(Vector3(36, 1.6, 15), 0.3), headliner, Vector3(0, 0, -7.5))
		_add(self, _box(Vector3(3, 6, 2)), white, Vector3(sx * 70, -1, 66))
	_add(self, _box(Vector3(2, 2, 6)), plastic, Vector3(0, 70, 76))
	_add(self, pillow(Vector3(20, 2.2, 6.5), 0.3), plastic, Vector3(0, 70, 72))


# Дверная карта: плоская панель по контуру двери ниже стекла, торцы двери
# в цвет кузова, подлокотник, ручки.
func _door_card(name: String, piece: Node3D) -> void:
	var front := name.begins_with("door_f")
	var sx := 1.0 if name.ends_with("r") else -1.0
	var poly: PackedVector2Array
	if front:
		poly = PackedVector2Array([Vector2(0.5, -18.5), Vector2(0.5, 34), Vector2(84.5, 34), Vector2(86.5, 31), Vector2(87, -17.5)])
	else:
		poly = PackedVector2Array([Vector2(-0.5, -18.5), Vector2(-0.5, 34), Vector2(-86.5, 34), Vector2(-85, 13.5), Vector2(-79.5, 10.5), Vector2(-70.5, 4.5), Vector2(-62, -5.5), Vector2(-58.5, -16), Vector2(-57, -18.5)])
	var x_in := sx * 71.0
	var x_out := sx * 77.0
	piece.add_child(_flat_poly(poly, x_in, door_vinyl, -sx))
	# Торцы двери в цвет кузова (видны, когда дверь открыта).
	piece.add_child(_rim(poly, x_in, x_out, paint))
	# Внутренний подоконник.
	var y0 := poly[0].x
	var y1 := poly[2].x
	_add(piece, _box(Vector3(5, absf(y1 - y0), 2.5)), vinyl, Vector3(sx * 73.5, (y0 + y1) * 0.5, 35))
	var mid := (y0 + y1) * 0.5
	# Подлокотник-ручка.
	_add(piece, pillow(Vector3(5, 30 if front else 22, 5), 0.35), vinyl, Vector3(sx * 68.5, mid + (6 if front else -4) * signf(y1), 12))
	# Хромированная ручка открывания и кнопка блокировки на подоконнике.
	var handle_y := y1 - signf(y1) * 12.0
	_add(piece, _box(Vector3(1.2, 9, 2.2)), chrome, Vector3(sx * 70.2, handle_y, 22))
	_add(piece, _cyl(0.5, 4), chrome, Vector3(sx * 73.5, y0 + signf(y1) * 6.0, 37.5), Vector3(PI * 0.5, 0, 0))
	# Ручка стеклоподъёмника.
	var crank := Vector3(sx * 70.0, mid - signf(y1) * 4.0, 2)
	_add(piece, _cyl(2.2, 1.5), chrome, crank, Vector3(0, 0, PI * 0.5))
	_add(piece, _box(Vector3(1.0, 9, 1.4)), chrome, crank + Vector3(-sx * 1.0, 4, 0))
	_add(piece, _cyl(1.0, 3.5), plastic, crank + Vector3(-sx * 2.5, 8, 0), Vector3(0, 0, PI * 0.5))


func _flat_poly(poly: PackedVector2Array, x: float, mat: Material, nx: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tris.size(), 3):
		var order := [tris[i], tris[i + 1], tris[i + 2]]
		if nx > 0.0:
			order = [tris[i], tris[i + 2], tris[i + 1]]
		for k in order:
			var p := poly[k]
			st.set_normal(Vector3(nx, 0, 0))
			st.set_uv(Vector2(p.x, -p.y) * 0.025)
			st.add_vertex(Vector3(x, p.x, p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


func _rim(poly: PackedVector2Array, x0: float, x1: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Торцы по всему контуру, кроме верхней кромки (там подоконник и рамка стекла).
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if absf(a.y - 34.0) < 0.5 and absf(b.y - 34.0) < 0.5:
			continue
		var q := [Vector3(x0, a.x, a.y), Vector3(x1, a.x, a.y), Vector3(x1, b.x, b.y), Vector3(x0, b.x, b.y)]
		for k in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
			st.add_vertex(q[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


# --- Анимация -------------------------------------------------------------------

func _set_needle(name: String, t: float) -> void:
	if not needles.has(name):
		return
	var n: Array = needles[name]
	(n[0] as Node3D).rotation = Vector3(0, lerpf(n[1], n[2], clampf(t, 0.0, 1.0)), 0)


# Подвижные части салона — их нельзя сливать с неподвижной геометрией.
func movable_parts() -> Array:
	var out: Array = [steering_wheel, gear_lever, handbrake_lever]
	out.append_array(pedals)
	for k in needles:
		out.append(needles[k][0])
	return out


func update_view(car: Car, sim: EngineSim, delta: float, backlight: bool) -> void:
	var k := 1.0 - exp(-delta * 8.0)
	var powered := sim.electrical.key >= 1
	_smooth("speed", absf(car.speed_kmh()) / 180.0, k)
	_smooth("rpm", sim.rpm_display / 8000.0, k)
	_smooth("temp", ((sim.thermal.t_coolant - 273.15) - 50.0) / 80.0 if powered else 0.0, k * 0.3)
	_smooth("fuel", 0.0 if not powered or not sim.carb.fuel_supply_ok else 0.72, k * 0.3)
	var t := Time.get_datetime_dict_from_system()
	if needles.has("clock"):
		(needles["clock"][0] as Node3D).rotation = Vector3(0, TAU * (t.hour % 12 + t.minute / 60.0) / 12.0, 0)
	# Руль: угол поворота колёс через рулевой механизм.
	if steering_wheel != null:
		steering_wheel.rotation.z = -car.steer * STEER_RATIO
	var vd := car.vd
	# Педали и рычаги.
	if pedals.size() == 3:
		pedals[0].rotation.x = vd.clutch_pedal * 0.35
		pedals[1].rotation.x = vd.brake * 0.25
		pedals[2].rotation.x = car.throttle * 0.3
	handbrake_lever.rotation.x = 0.25 + vd.handbrake * 0.45
	# Схема КПП ВАЗ: 1 — влево-вперёд, 2 — влево-назад, 3 — вправо-вперёд,
	# 4 — вправо-назад, задний ход — вправо до упора и назад.
	var pos := [Vector2(0.24, -0.22), Vector2(0, 0), Vector2(-0.12, 0.2), Vector2(-0.12, -0.2), Vector2(0.12, 0.2), Vector2(0.12, -0.2)]
	var g: Vector2 = pos[clampi(vd.gear, 0, 5)]
	gear_lever.rotation = gear_lever.rotation.lerp(Vector3(-g.y - 0.15, 0, -g.x), k)
	# Подсветка приборов вместе с габаритами.
	var glow := Color(0.35, 0.9, 0.5) * 0.6 if backlight and powered else Color(0, 0, 0)
	white.emission = glow
	needle_mat.emission = Color(1.0, 0.4, 0.1) * 0.8 if backlight and powered else Color(0, 0, 0)


func _smooth(name: String, target: float, k: float) -> void:
	if not needles.has(name):
		return
	var n: Array = needles[name]
	var node: Node3D = n[0]
	var cur := inverse_lerp(n[1], n[2], node.rotation.y)
	_set_needle(name, lerpf(cur, target, k))
