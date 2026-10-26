class_name Vegetation
extends RefCounted

# Растительность у трассы: берёзы, липы и ели — стволы с корой и кроны из
# карточек листвы (альфа-отсечение, просвет на солнце, покачивание ветром),
# ближняя лесополоса и дальний лес для глубины кадра, трава с полевыми цветами
# вдоль обочин (кусками по 50 м, дальние отсекаются по расстоянию).

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
uniform float sway = 1.0;
uniform float translucency = 0.6;
uniform bool grass = false;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.15 + wp.x * 0.13 + wp.z * 0.09) * 0.6 + sin(TIME * 2.9 + wp.x * 0.7 + wp.z) * 0.25;
	if (grass) {
		float k = 1.0 - UV.y;
		VERTEX.x += w * 0.06 * k * k * sway;
		VERTEX.z += w * 0.04 * k * k * sway;
	} else {
		float h = max(VERTEX.y, 0.0);
		VERTEX.x += w * 0.01 * h * h * sway;
		VERTEX.z += w * 0.007 * h * h * sway;
	}
}
void fragment() {
	vec4 t = texture(tex, UV);
	vec3 c = t.rgb * tint * COLOR.rgb;
	if (grass) {
		c *= mix(0.55, 1.05, 1.0 - UV.y);
	}
	ALBEDO = c;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = c * translucency;
}
"""


static func leaf_material(tex: Texture2D, tint: Color, grass := false, sway := 1.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = LEAF_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("grass", grass)
	m.set_shader_parameter("sway", sway)
	return m


# Текстура ветки: россыпь листочков (или хвои) разного оттенка, гуще к центру.
static func leaf_texture(seed_v: int, leaf_len: float, needles: bool) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.3, 0.1, 0.0))
	var count := 520 if needles else 150
	for i in count:
		var r := pow(rng.randf(), 0.6) * n * 0.46
		var a := rng.randf() * TAU
		var c := Vector2(n * 0.5, n * 0.5) + Vector2(cos(a), sin(a)) * r
		var ang := rng.randf() * TAU
		var col := Color(0.22, 0.36, 0.09).lerp(Color(0.48, 0.6, 0.18), rng.randf()).darkened(rng.randf() * 0.35)
		if needles:
			col = Color(0.08, 0.2, 0.08).lerp(Color(0.16, 0.3, 0.12), rng.randf())
		var L := leaf_len * rng.randf_range(0.7, 1.3)
		var W := L * (0.12 if needles else 0.45)
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x)
		for y in range(int(c.y - L), int(c.y + L) + 1):
			for x in range(int(c.x - L), int(c.x + L) + 1):
				if x < 0 or y < 0 or x >= n or y >= n:
					continue
				var p := Vector2(x, y) - c
				var u := p.dot(dir) / L
				var v := p.dot(side) / W
				if u * u + v * v <= 1.0:
					var shade := 0.85 + 0.25 * (1.0 - absf(v)) - 0.1 * u
					img.set_pixel(x, y, Color(col.r * shade, col.g * shade, col.b * shade, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func grass_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.4, 0.15, 0.0))
	for i in 38:
		var x0 := rng.randf_range(10, w - 10)
		var top := rng.randf_range(0.0, h * 0.75)
		var lean := rng.randf_range(-26.0, 26.0)
		var width := rng.randf_range(1.2, 2.4)
		var col := Color(0.3, 0.45, 0.13).lerp(Color(0.55, 0.6, 0.22), rng.randf())
		if rng.randf() < 0.15:
			col = Color(0.62, 0.58, 0.3)   # сухие травинки
		for y in range(int(top), h):
			var t := (y - top) / (h - top)
			var x := x0 + lean * (1.0 - t) * (1.0 - t)
			var half := width * t * 0.5 + 0.4
			for xx in range(int(x - half), int(x + half) + 1):
				if xx >= 0 and xx < w:
					img.set_pixel(xx, y, Color(col.r, col.g, col.b, 1.0))
	# Редкие полевые цветы: ромашки, лютики, колокольчики.
	for i in 6:
		var c := Vector2(rng.randf_range(10, w - 10), rng.randf_range(10, h * 0.5))
		var fc: Color = [Color(1, 1, 0.9), Color(1.0, 0.85, 0.2), Color(0.6, 0.55, 1.0)][rng.randi() % 3]
		for y in range(-3, 4):
			for x in range(-3, 4):
				if x * x + y * y <= 8:
					img.set_pixel(int(c.x) + x, int(c.y) + y, fc)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func bark_texture(birch: bool) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 41 if birch else 42
	n.frequency = 0.05
	var img := Image.create(64, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 64:
			var v := n.get_noise_2d(x * (3.0 if birch else 0.6), y * (0.5 if birch else 3.0))
			var c: Color
			if birch:
				c = Color(0.86, 0.85, 0.8)
				if v > 0.35:
					c = Color(0.1, 0.1, 0.09)
				elif v > 0.2:
					c = Color(0.5, 0.48, 0.44)
			else:
				c = Color(0.3, 0.24, 0.18).darkened(clampf(0.5 * (v + 0.5), 0.0, 0.7))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# Сетка дерева единичной высоты: ствол-конус и карточки листвы в объёме кроны.
# kind: 0 — берёза (узкая высокая крона), 1 — липа (округлая), 2 — ель (ярусы).
static func tree_mesh(kind: int, seed_v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 := 0.022 if kind != 2 else 0.028
	var seg := 8
	var rings := 6
	for i in rings:
		for j in seg:
			for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				var t: float = float(q[0]) / rings
				var a: float = TAU * q[1] / seg
				var r := r0 * (1.0 - t * 0.85)
				var bend := Vector3(sin(t * 3.0 + seed_v) * 0.01, 0, cos(t * 2.0 + seed_v) * 0.01)
				st.set_normal(Vector3(cos(a), 0.2, sin(a)).normalized())
				st.set_uv(Vector2(float(q[1]) / seg, t * 4.0))
				st.add_vertex(Vector3(cos(a) * r, t * (0.9 if kind != 2 else 1.0), sin(a) * r) + bend)
	st.commit(mesh)
	var lt := SurfaceTool.new()
	lt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cards := 120 if kind != 2 else 140
	for k in cards:
		var c: Vector3
		var size: float
		if kind == 2:
			var t := rng.randf_range(0.12, 1.0)
			var rad := (1.0 - t) * 0.26 + 0.02
			var a := rng.randf() * TAU
			c = Vector3(cos(a) * rad * rng.randf_range(0.4, 1.0), t * 0.98, sin(a) * rad * rng.randf_range(0.4, 1.0))
			size = 0.07 + (1.0 - t) * 0.1
		else:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
			var rr := pow(rng.randf(), 0.5)
			var crown := Vector3(0.24, 0.24, 0.24) if kind == 1 else Vector3(0.17, 0.27, 0.17)
			c = Vector3(0, 0.66 if kind == 1 else 0.68, 0) + dir * crown * rr
			size = rng.randf_range(0.09, 0.16) if kind == 1 else rng.randf_range(0.07, 0.12)
		# Нормали — от центра кроны: свет ложится объёмно, а не по плоскостям карточек.
		var nrm := (c - Vector3(0, 0.62, 0)).normalized() if kind != 2 else Vector3(c.x, 0.3, c.z).normalized()
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.9, 0.9))
		if kind == 2:
			basis = Basis(Vector3.UP, atan2(c.x, c.z) + rng.randf_range(-0.4, 0.4)) * Basis(Vector3.RIGHT, -1.25 + rng.randf_range(-0.2, 0.2))
		var ex := basis.x * size
		var ey := basis.y * size
		var pts := [c - ex - ey, c + ex - ey, c + ex + ey, c - ex + ey]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			lt.set_normal(nrm)
			lt.set_uv(uvs[idx])
			lt.add_vertex(pts[idx])
	lt.commit(mesh)
	return mesh


static func plant(road: Road) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2106
	var w := Road.WIDTH
	var kinds := [[], [], []]
	var d := -40.0
	while d < Road.LENGTH + 40.0:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.8:
				var x: float = side * rng.randf_range(w * 0.5 + 7.0, w * 0.5 + 28.0)
				kinds[rng.randi() % 3].append(Vector3(x, road.height(x, -d) - 0.05, -d + rng.randf_range(-3.0, 3.0)))
			if rng.randf() < 0.9:
				var x2: float = side * rng.randf_range(w * 0.5 + 40.0, w * 0.5 + 110.0)
				kinds[2 if rng.randf() < 0.5 else rng.randi() % 2].append(Vector3(x2, -0.2, -d + rng.randf_range(-4.0, 4.0)))
		d += rng.randf_range(5.0, 10.0)
	var bark_birch := StandardMaterial3D.new()
	bark_birch.albedo_texture = bark_texture(true)
	bark_birch.roughness = 0.85
	var bark_dark := StandardMaterial3D.new()
	bark_dark.albedo_texture = bark_texture(false)
	bark_dark.roughness = 0.95
	if TexLib.has("bark_brown_02"):
		# Фотоскан коры: развёртка ствола — 1 оборот по окружности, 4 повтора по высоте.
		bark_dark.albedo_texture = TexLib.tex("bark_brown_02", "diff")
		bark_dark.normal_enabled = true
		bark_dark.normal_texture = TexLib.tex("bark_brown_02", "nor")
		bark_dark.normal_scale = 1.5
		bark_dark.roughness_texture = TexLib.tex("bark_brown_02", "rough")
		bark_dark.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		bark_dark.uv1_scale = Vector3(1.0, 1.5, 1.0)
		# Берёзе — рельеф трещин той же коры поверх белой бересты.
		bark_birch.normal_enabled = true
		bark_birch.normal_texture = bark_dark.normal_texture
		bark_birch.normal_scale = 0.6
	var leaves := [
		leaf_material(leaf_texture(1, 7.0, false), Color(1.05, 1.1, 0.95)),
		leaf_material(leaf_texture(2, 10.0, false), Color(0.85, 0.95, 0.8)),
		leaf_material(leaf_texture(3, 14.0, true), Color(0.9, 1.0, 0.9), false, 0.4),
	]
	for k in 3:
		var spots: Array = kinds[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var mesh := tree_mesh(k, 10 + k)
		mesh.surface_set_material(0, bark_birch if k == 0 else bark_dark)
		mesh.surface_set_material(1, leaves[k])
		mm.mesh = mesh
		mm.instance_count = spots.size()
		for i in spots.size():
			var h := rng.randf_range(9.0, 16.0) if k == 0 else (rng.randf_range(8.0, 13.0) if k == 1 else rng.randf_range(10.0, 20.0))
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h * rng.randf_range(0.85, 1.15), h, h * rng.randf_range(0.85, 1.15)))
			mm.set_instance_transform(i, Transform3D(b, spots[i]))
			mm.set_instance_color(i, Color(1, 1, 1).lerp(Color(0.8, 0.88, 0.7), rng.randf()))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		road.add_child(mi)
	_plant_grass(road)
	_plant_photo_plants(road)


static func _plant_grass(road: Road) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var w := Road.WIDTH
	# Пучок: три перекрещённые карточки.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := PI * k / 3.0
		var ex := Vector3(cos(a), 0, sin(a)) * 0.22
		var lean := Vector3(sin(a * 3.0), 0, cos(a * 2.0)) * 0.05
		var pts := [-ex, ex, ex + Vector3(0, 0.34, 0) + lean, -ex + Vector3(0, 0.34, 0) + lean]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(pts[idx])
	var clump := st.commit()
	clump.surface_set_material(0, leaf_material(grass_texture(), Color(0.95, 1.0, 0.9), true))
	var d0 := -30.0
	while d0 < Road.LENGTH + 30.0:
		var xf: Array[Transform3D] = []
		var cols: Array[Color] = []
		for side in [-1.0, 1.0]:
			var dd := d0
			while dd < d0 + 50.0:
				var x := w * 0.5 + 6.5
				while x < w * 0.5 + 24.0:
					var px: float = side * (x + rng.randf_range(-0.3, 0.3))
					var pz := -(dd + rng.randf_range(-0.3, 0.3))
					var s := rng.randf_range(0.6, 1.5) * (0.6 if x < w * 0.5 + 2.5 else 1.0)
					var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25))
					xf.append(Transform3D((tilt * Basis(Vector3.UP, rng.randf() * TAU)).scaled(Vector3(s, s * rng.randf_range(0.6, 1.6), s)), Vector3(px, road.height(px, pz) - 0.03, pz)))
					cols.append(Color(1, 1, 1).lerp(Color(0.85, 0.82, 0.6), rng.randf() * rng.randf()))
					x += rng.randf_range(0.5, 1.0)
				dd += rng.randf_range(0.5, 1.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = clump
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
			mm.set_instance_color(i, cols[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 110.0
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		road.add_child(mi)
		d0 += 50.0


# --- Фотомодели растений (Poly Haven, CC0) ---------------------------------------

const PLANTS_DIR := "res://models/plants/"


# Достаёт из glTF нужные варианты: [сетка с материалами, базис узла (поворот/масштаб)].
static func _load_variants(model: String, names: Array) -> Array:
	var path := MeshUtil.raw_path(PLANTS_DIR + "%s/%s.gltf" % [model, model])
	if not FileAccess.file_exists(path):
		return []
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return []
	var scene := doc.generate_scene(st) as Node3D
	var out := []
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var ok := names.is_empty()
		for nm in names:
			ok = ok or String(mi.name).begins_with(nm)
		if not ok:
			continue
		# Базис узла относительно корня сцены (перевод осей glTF и масштаб).
		var b := Basis.IDENTITY
		var node: Node = mi
		while node != null and node != scene:
			if node is Node3D:
				b = (node as Node3D).basis * b
			node = node.get_parent()
		var mesh := mi.mesh.duplicate() as ArrayMesh
		for k in mesh.get_surface_count():
			var m := mesh.surface_get_material(k) as StandardMaterial3D
			if m != null:
				m = m.duplicate() as StandardMaterial3D
				# Альфа-отсечение вместо сортировки прозрачности: тысячи экземпляров без мерцания.
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = 0.4
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.backlight_enabled = true
				m.backlight = Color(0.25, 0.3, 0.12)
				mesh.surface_set_material(k, m)
		out.append([mesh, b])
	scene.free()
	return out


static func _plant_photo_plants(road: Road) -> void:
	var w := Road.WIDTH * 0.5
	# [модель, варианты, плотность на м², полоса от кромки (м), масштаб, дальность видимости]
	var groups := [
		["grass_medium_01", ["grass_medium_01_tall", "grass_medium_01_mid_b", "grass_medium_01_small"], 1.6, [1.3, 7.0], [1.4, 2.6], 45.0],
		["grass_medium_02", ["grass_medium_02_a", "grass_medium_02_b", "grass_medium_02_c"], 0.9, [1.6, 8.0], [1.1, 1.8], 45.0],
		["dandelion_01", ["dandelion_01_c", "dandelion_01_d", "dandelion_01_e"], 0.12, [1.4, 7.0], [1.0, 1.4], 35.0],
		["nettle_plant", ["nettle_plant_small", "nettle_plant_medium", "nettle_plant_tall"], 0.1, [1.8, 6.0], [3.0, 5.0], 45.0],
		["shrub_04", [], 0.004, [6.0, 22.0], [2.5, 4.5], 160.0],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	for g in groups:
		var variants := _load_variants(g[0], g[1])
		if variants.is_empty():
			continue
		var density: float = g[2]
		var band: Array = g[3]
		var sc: Array = g[4]
		var d0 := -30.0
		while d0 < Road.LENGTH + 30.0:
			var per_variant := []
			for v in variants:
				per_variant.append([])
			var area := 100.0 * (float(band[1]) - float(band[0])) * 2.0
			var count := int(area * density)
			for i in count:
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				# Кучнее у кромки, реже вдаль — как растёт трава у дороги.
				var x: float = side * (w + lerpf(band[0], band[1], pow(rng.randf(), 1.4)))
				var z := -(d0 + rng.randf() * 100.0)
				var s := rng.randf_range(sc[0], sc[1])
				per_variant[rng.randi() % variants.size()].append(Transform3D.IDENTITY.scaled(Vector3.ONE * s).rotated(Vector3.UP, rng.randf() * TAU).translated(Vector3(x, road.height(x, z) - 0.02, z)))
			for k in variants.size():
				var xf: Array = per_variant[k]
				if xf.is_empty():
					continue
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = variants[k][0]
				mm.instance_count = xf.size()
				var nb: Basis = variants[k][1]
				for i in xf.size():
					var t: Transform3D = xf[i]
					mm.set_instance_transform(i, Transform3D(t.basis * nb, t.origin))
				var mi := MultiMeshInstance3D.new()
				mi.multimesh = mm
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if g[0] != "shrub_04" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				mi.visibility_range_end = g[5]
				mi.visibility_range_end_margin = 8.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				road.add_child(mi)
			d0 += 100.0
