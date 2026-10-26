class_name TexLib
extends RefCounted

# Фотосканированные PBR-текстуры (Poly Haven, CC0) из models/textures:
# <имя>_diff.jpg — цвет, <имя>_nor.jpg — нормали (OpenGL), <имя>_rough.jpg — шероховатость.
# Загружаются во время работы, с мипмапами; по запросу цвет обесцвечивается,
# чтобы обивку можно было тонировать под комплектацию.

const DIR := "res://models/textures/"
static var _cache := {}


static func has(name: String) -> bool:
	return FileAccess.file_exists(DIR + name + "_diff.jpg")


static func tex(name: String, map: String, gray := false) -> Texture2D:
	var key := "%s_%s_%s" % [name, map, gray]
	if _cache.has(key):
		return _cache[key]
	var img := Image.load_from_file(MeshUtil.raw_path(DIR + name + "_" + map + ".jpg"))
	if img == null:
		return null
	if gray:
		# Обесцвечиваем средствами движка (попиксельный цикл на 2K слишком медленный),
		# среднюю яркость запоминаем — материал выровняет её к 0,5.
		var sum := 0.0
		var cnt := 0
		for y in range(0, img.get_height(), 16):
			for x in range(0, img.get_width(), 16):
				sum += img.get_pixel(x, y).get_luminance()
				cnt += 1
		_cache[key + "_mean"] = sum / maxf(cnt, 1)
		img.convert(Image.FORMAT_L8)
		img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


# Готовый материал: triplanar в мировых или локальных координатах, scale — повторов на единицу.
static func material(name: String, scale: float, tint := Color.WHITE, gray := false, world := true, normal_strength := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name, "diff", gray)
	m.albedo_color = tint
	if gray:
		var mean: float = _cache.get("%s_diff_true_mean" % name, 0.5)
		m.albedo_color = Color(tint * (0.5 / maxf(mean, 0.05)), 1.0)
	m.normal_enabled = true
	m.normal_texture = tex(name, "nor")
	m.normal_scale = normal_strength
	m.roughness_texture = tex(name, "rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# Накладывает фотоскан на готовый материал: обесцвеченный цвет (тон задаёт
# albedo_color, поправка яркости — в meta "gain"), нормали и шероховатость.
static func apply(m: StandardMaterial3D, name: String, scale: float, normal_strength := 1.0, triplanar := true) -> void:
	if not has(name):
		return
	m.albedo_texture = tex(name, "diff", true)
	var mean: float = _cache.get("%s_diff_true_mean" % name, 0.5)
	m.set_meta("gain", 0.5 / maxf(mean, 0.05))
	m.albedo_color = Color(m.albedo_color * float(m.get_meta("gain")), m.albedo_color.a)
	m.normal_enabled = true
	m.normal_texture = tex(name, "nor")
	m.normal_scale = normal_strength
	m.roughness_texture = tex(name, "rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.roughness = 1.0
	m.uv1_triplanar = triplanar
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
