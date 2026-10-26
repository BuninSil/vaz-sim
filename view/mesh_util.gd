class_name MeshUtil
extends RefCounted

# Построение простых деталей: примитивы, выдавленные профили, материалы.

static var _materials := {}


static func material(name: String) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	match name:
		"cast_iron":
			m.albedo_color = Color(0.30, 0.31, 0.32)
			m.metallic = 0.55
			m.roughness = 0.75
		"aluminum":
			m.albedo_color = Color(0.66, 0.67, 0.68)
			m.metallic = 0.55
			m.roughness = 0.6
		"steel":
			m.albedo_color = Color(0.78, 0.79, 0.80)
			m.metallic = 0.9
			m.roughness = 0.22
		"dark_steel":
			m.albedo_color = Color(0.32, 0.33, 0.35)
			m.metallic = 0.85
			m.roughness = 0.35
		"forged":
			m.albedo_color = Color(0.45, 0.45, 0.47)
			m.metallic = 0.8
			m.roughness = 0.4
		"piston":
			m.albedo_color = Color(0.80, 0.80, 0.78)
			m.metallic = 0.7
			m.roughness = 0.35
		"ring":
			m.albedo_color = Color(0.25, 0.25, 0.27)
			m.metallic = 0.9
			m.roughness = 0.3
		"valve_cover":
			m.albedo_color = Color(0.12, 0.16, 0.22)
			m.metallic = 0.3
			m.roughness = 0.5
		"black":
			m.albedo_color = Color(0.06, 0.06, 0.07)
			m.metallic = 0.1
			m.roughness = 0.7
		"rubber":
			m.albedo_color = Color(0.04, 0.04, 0.04)
			m.roughness = 0.9
		"brass":
			m.albedo_color = Color(0.78, 0.62, 0.30)
			m.metallic = 0.9
			m.roughness = 0.3
		"copper":
			m.albedo_color = Color(0.72, 0.42, 0.25)
			m.metallic = 0.9
			m.roughness = 0.3
		"ceramic":
			m.albedo_color = Color(0.93, 0.92, 0.88)
			m.roughness = 0.35
		"wire":
			m.albedo_color = Color(0.55, 0.08, 0.06)
			m.roughness = 0.6
		"distributor_cap":
			m.albedo_color = Color(0.10, 0.10, 0.11)
			m.roughness = 0.4
		"exhaust":
			m.albedo_color = Color(0.28, 0.22, 0.19)
			m.metallic = 0.6
			m.roughness = 0.8
			m.emission_enabled = true
			m.emission = Color(0, 0, 0)
		"painted_red":
			m.albedo_color = Color(0.55, 0.10, 0.08)
			m.metallic = 0.3
			m.roughness = 0.45
		"painted_blue":
			m.albedo_color = Color(0.13, 0.25, 0.45)
			m.metallic = 0.3
			m.roughness = 0.45
		"oil_filter":
			m.albedo_color = Color(0.85, 0.55, 0.10)
			m.metallic = 0.3
			m.roughness = 0.4
		"chain":
			m.albedo_color = Color(0.55, 0.56, 0.58)
			m.metallic = 0.95
			m.roughness = 0.25
		"plastic_white":
			m.albedo_color = Color(0.85, 0.85, 0.82)
			m.roughness = 0.6
		"gasket":
			m.albedo_color = Color(0.35, 0.33, 0.30)
			m.metallic = 0.4
			m.roughness = 0.7
		"gas":
			m.albedo_color = Color(0.3, 0.6, 1.0, 0.15)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.no_depth_test = false
		"highlight":
			m.albedo_color = Color(1.0, 0.75, 0.2, 0.28)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = Color(1.0, 0.6, 0.1)
		"blocked":
			m.albedo_color = Color(1.0, 0.15, 0.1, 0.32)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_:
			m.albedo_color = Color(0.6, 0.6, 0.6)
	_materials[name] = m
	return m


# Материалы корпусных деталей, которые становятся прозрачными в режиме «рентген».
const HOUSING := ["cast_iron", "aluminum", "valve_cover", "black", "painted_blue"]


static func set_xray(enabled: bool) -> void:
	for n in HOUSING:
		var m := material(n)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if enabled else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = 0.18 if enabled else 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED if enabled else BaseMaterial3D.CULL_BACK


static func mi(mesh: Mesh, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material(mat)
	m.position = pos
	m.rotation = rot
	return m


static func box(size: Vector3, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mi(b, mat, pos, rot)


# Цилиндр вдоль оси Y.
static func cyl(radius: float, height: float, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO, segments := 24) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return mi(c, mat, pos, rot)


# Цилиндр вдоль оси X.
static func cyl_x(radius: float, length: float, mat: String, pos := Vector3.ZERO, segments := 24) -> MeshInstance3D:
	return cyl(radius, length, mat, pos, Vector3(0, 0, PI * 0.5), segments)


# Цилиндр вдоль оси Z.
static func cyl_z(radius: float, length: float, mat: String, pos := Vector3.ZERO, segments := 24) -> MeshInstance3D:
	return cyl(radius, length, mat, pos, Vector3(PI * 0.5, 0, 0), segments)


static func cone(r_bottom: float, r_top: float, height: float, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = height
	c.radial_segments = 24
	return mi(c, mat, pos, rot)


# Кольцо (тор) в плоскости XZ.
static func torus(inner: float, outer: float, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 32
	t.ring_segments = 8
	return mi(t, mat, pos, rot)


static func sphere(radius: float, mat: String, pos := Vector3.ZERO) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	return mi(s, mat, pos)


# Выпуклый профиль в плоскости YZ, выдавленный вдоль X на ширину width.
# Точки задаются как Vector2(y, z) и должны обходить контур по порядку.
static func extrude_x(profile: PackedVector2Array, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var hx := width * 0.5
	var center := Vector2.ZERO
	for p in profile:
		center += p
	center /= n
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var a0 := Vector3(-hx, a.x, a.y)
		var a1 := Vector3(hx, a.x, a.y)
		var b0 := Vector3(-hx, b.x, b.y)
		var b1 := Vector3(hx, b.x, b.y)
		var normal := Vector3(0, b.x - a.x, b.y - a.y).cross(Vector3(1, 0, 0)).normalized()
		if normal.dot(Vector3(0, (a.x + b.x) * 0.5 - center.x, (a.y + b.y) * 0.5 - center.y)) < 0.0:
			normal = -normal
		st.set_normal(normal)
		_tri(st, a0, b0, b1, normal)
		_tri(st, a0, b1, a1, normal)
		# Торцы.
		var c0 := Vector3(-hx, center.x, center.y)
		var c1 := Vector3(hx, center.x, center.y)
		_tri(st, c0, b0, a0, Vector3(-1, 0, 0))
		_tri(st, c1, a1, b1, Vector3(1, 0, 0))
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	# Порядок вершин подбираем так, чтобы лицевая сторона смотрела по нормали.
	var face := (b - a).cross(c - a)
	st.set_normal(normal)
	if face.dot(normal) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)


static func convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	return Geometry2D.convex_hull(points)


static func circle_points(center: Vector2, radius: float, from: float, to: float, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count + 1:
		var a := lerpf(from, to, float(i) / count)
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


# Спираль пружины вдоль оси Y высотой 1 (масштабируется по Y при сжатии).
static func spring_mesh(radius: float, wire: float, turns: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := int(turns * 20.0)
	var sides := 6
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var p0 := Vector3(cos(t0 * turns * TAU) * radius, t0 - 0.5, sin(t0 * turns * TAU) * radius)
		var p1 := Vector3(cos(t1 * turns * TAU) * radius, t1 - 0.5, sin(t1 * turns * TAU) * radius)
		var tangent := (p1 - p0).normalized()
		var n0 := Vector3(p0.x, 0, p0.z).normalized()
		var b0 := tangent.cross(n0).normalized()
		for s in sides:
			var a0 := float(s) / sides * TAU
			var a1 := float(s + 1) / sides * TAU
			var o00 := (n0 * cos(a0) + b0 * sin(a0)) * wire
			var o01 := (n0 * cos(a1) + b0 * sin(a1)) * wire
			var n1 := Vector3(p1.x, 0, p1.z).normalized()
			var b1 := tangent.cross(n1).normalized()
			var o10 := (n1 * cos(a0) + b1 * sin(a0)) * wire
			var o11 := (n1 * cos(a1) + b1 * sin(a1)) * wire
			_tri(st, p0 + o00, p1 + o10, p1 + o11, o00.normalized())
			_tri(st, p0 + o00, p1 + o11, p0 + o01, o00.normalized())
	return st.commit()


# --- Сложные формы ----------------------------------------------------------

# Тело вращения вокруг оси Y. Профиль — точки (y, радиус) от одного торца к другому.
# Нулевой радиус на концах закрывает торцы.
static func lathe(profile: PackedVector2Array, segments := 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		for s in segments:
			var a0 := TAU * s / segments
			var a1 := TAU * (s + 1) / segments
			var v00 := Vector3(cos(a0) * p0.y, p0.x, sin(a0) * p0.y)
			var v01 := Vector3(cos(a1) * p0.y, p0.x, sin(a1) * p0.y)
			var v10 := Vector3(cos(a0) * p1.y, p1.x, sin(a0) * p1.y)
			var v11 := Vector3(cos(a1) * p1.y, p1.x, sin(a1) * p1.y)
			# Нормаль — наружу от оси с учётом наклона образующей.
			var mid := (a0 + a1) * 0.5
			var radial := Vector3(cos(mid), 0, sin(mid))
			var dy := p1.x - p0.x
			var dr := p1.y - p0.y
			var n := (radial * dy - Vector3.UP * dr).normalized()
			if n.length() < 0.5:
				n = radial
			_tri(st, v00, v10, v11, n)
			_tri(st, v00, v11, v01, n)
	st.generate_normals()
	return st.commit()


# Труба вдоль ломаной (с переносом сечения без скручивания).
static func tube(points: PackedVector3Array, radius: float, sides := 10, closed_ends := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	if n < 2:
		return st.commit()
	var tangent := (points[1] - points[0]).normalized()
	var normal := tangent.cross(Vector3.UP)
	if normal.length() < 0.1:
		normal = tangent.cross(Vector3.RIGHT)
	normal = normal.normalized()
	var rings: Array = []
	for i in n:
		var t: Vector3
		if i == 0:
			t = points[1] - points[0]
		elif i == n - 1:
			t = points[i] - points[i - 1]
		else:
			t = points[i + 1] - points[i - 1]
		t = t.normalized()
		normal = (normal - t * normal.dot(t)).normalized()
		var binormal := t.cross(normal)
		var ring := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			ring.append(points[i] + (normal * cos(a) + binormal * sin(a)) * radius)
		rings.append(ring)
	for i in n - 1:
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		for s in sides:
			var s1 := (s + 1) % sides
			var out := (r0[s] - points[i]).normalized()
			_tri(st, r0[s], r1[s], r1[s1], out)
			_tri(st, r0[s], r1[s1], r0[s1], out)
	if closed_ends:
		for e in [0, n - 1]:
			var ring_e: PackedVector3Array = rings[e]
			var dir := (points[1] - points[0]).normalized() * -1.0 if e == 0 else (points[n - 1] - points[n - 2]).normalized()
			for s in sides:
				_tri(st, points[e], ring_e[s], ring_e[(s + 1) % sides], dir)
	st.generate_normals()
	return st.commit()


# Сглаженная ломаная: кривая Катмулла — Рома через опорные точки.
static func smooth_path(ctrl: Array, per_segment := 6) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0: Vector3 = ctrl[maxi(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[mini(i + 2, n - 1)]
		for k in per_segment:
			var t := float(k) / per_segment
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[n - 1])
	return out


# Зубчатый венец звёздочки/шестерни, выдавленный вдоль X.
static func gear_x(teeth: int, r_root: float, r_tip: float, width: float) -> ArrayMesh:
	var pts := PackedVector2Array()
	for t in teeth:
		var a := TAU * t / teeth
		var step := TAU / teeth
		pts.append(Vector2(cos(a), sin(a)) * r_root)
		pts.append(Vector2(cos(a + step * 0.22), sin(a + step * 0.22)) * r_tip)
		pts.append(Vector2(cos(a + step * 0.45), sin(a + step * 0.45)) * r_tip)
		pts.append(Vector2(cos(a + step * 0.67), sin(a + step * 0.67)) * r_root)
	return extrude_x(pts, width)


static func hex_bolt(size: float, height: float, mat: String, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = size * 0.577
	c.bottom_radius = size * 0.577
	c.height = height
	c.radial_segments = 6
	c.rings = 1
	return mi(c, mat, pos, rot)

# Склеивает неподвижные меши одного материала, лежащие в одном узле, в одну сетку.
# Тысячи мелких деталей (болты, гайки, рёбра) иначе дают тысячи вызовов отрисовки.
static func merge_static(root: Node, skip: Array = []) -> int:
	var removed := 0
	var groups := {}
	for c in root.get_children():
		if not (c is MeshInstance3D) or skip.has(c):
			continue
		var m := c as MeshInstance3D
		if m.mesh == null or m.get_child_count() > 0 or m.material_override == null or m.mesh.get_surface_count() != 1:
			continue
		if m.mesh is ArrayMesh and (m.mesh as ArrayMesh).get_blend_shape_count() > 0:
			continue
		var key := "%d_%s" % [m.material_override.get_instance_id(), "p" if m.mesh is PrimitiveMesh else "a"]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(m)
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		for m in list:
			st.append_from((m as MeshInstance3D).mesh, 0, (m as MeshInstance3D).transform)
		var merged := MeshInstance3D.new()
		merged.mesh = st.commit()
		merged.material_override = (list[0] as MeshInstance3D).material_override
		merged.name = "Merged"
		root.add_child(merged)
		for m in list:
			root.remove_child(m)
			(m as Node).queue_free()
			removed += 1
	for c in root.get_children():
		if c is CSGShape3D or skip.has(c):
			continue
		removed += merge_static(c, skip)
	return removed