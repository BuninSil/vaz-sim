class_name Road
extends Node3D

# Испытательная трасса. Высота задаётся аналитически, поэтому колёса опрашивают её
# напрямую (без физических столкновений), а сетка строится из той же функции.
# Дорога идёт от старта на север (вдоль -Z), ширина асфальта 9 м.

const WIDTH := 9.0
const LENGTH := 1600.0

# Участки: [начало, конец, название, описание, тип]
const ZONES := [
	[0.0, 100.0, "Ровный асфальт", "Разгон, торможение, проверка КПП", "flat"],
	[100.0, 170.0, "Гребёнка", "Волны 15 мм с шагом 0,6 м — высокочастотные колебания колёс", "wash"],
	[190.0, 270.0, "Ямы", "Выбоины до 9 см — удары в подвеску, отбой", "holes"],
	[290.0, 350.0, "Лежачие полицейские", "Искусственные неровности 7 см", "bumps"],
	[370.0, 530.0, "Разбитая дорога", "Случайный микропрофиль до 5 см", "broken"],
	[550.0, 630.0, "Брусчатка", "Мелкие частые удары", "cobble"],
	[650.0, 730.0, "Диагональное вывешивание", "Бугры поочерёдно под левыми и правыми колёсами — крен, перекос моста", "diag"],
	[750.0, 880.0, "Подъём и спуск 12 %", "Тяга на подъёме, торможение двигателем", "hill"],
	[900.0, 960.0, "Железнодорожный переезд", "Два рельса — короткие резкие удары", "rails"],
	[980.0, 1250.0, "Просёлок, длинные волны", "Волны 15 см с шагом 25 м — галопирование кузова", "waves"],
	[1270.0, 1450.0, "Мокрый асфальт", "Сцепление 0,55 — пробуксовка и блокировка колёс", "wet"],
	[1450.0, 1600.0, "Ровный асфальт", "Разворот: съезд на площадку", "flat"],
]

var noise := FastNoiseLite.new()
var hole_noise := FastNoiseLite.new()
var _chunk_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	noise.seed = 2106
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	hole_noise.seed = 77
	hole_noise.frequency = 0.45
	_build()


static func zone_at(d: float) -> int:
	for i in ZONES.size():
		if d >= ZONES[i][0] and d < ZONES[i][1]:
			return i
	return -1


func zone_type(d: float) -> String:
	var z := zone_at(d)
	return ZONES[z][4] if z >= 0 else "flat"


# Высота поверхности в точке мира (x — поперёк, z — вдоль трассы, d = -z).
func height(x: float, z: float) -> float:
	var d := -z
	var h := 0.0
	var ax := absf(x)
	if d < -30.0 or d > LENGTH + 40.0:
		return -0.03
	var edge := smoothstep(WIDTH * 0.5, WIDTH * 0.5 + 1.5, ax)
	var zi := zone_at(d)
	if zi >= 0 and ax < WIDTH * 0.5 + 0.5:
		var t: String = ZONES[zi][4]
		var z0: float = ZONES[zi][0]
		var z1: float = ZONES[zi][1]
		var fade := smoothstep(z0, z0 + 2.0, d) * (1.0 - smoothstep(z1 - 2.0, z1, d))
		match t:
			"wash":
				h += 0.0075 * (1.0 - cos(TAU * d / 0.6)) * fade
			"holes":
				var n := hole_noise.get_noise_2d(x * 1.0, d * 1.0)
				h -= clampf((n - 0.32) * 0.5, 0.0, 0.09) * fade
			"bumps":
				for c: float in [300.0, 320.0, 340.0]:
					var u := (d - c) / 0.5
					if absf(u) < 1.0:
						h += 0.07 * pow(cos(u * PI * 0.5), 2.0)
			"broken":
				h += (noise.get_noise_2d(x * 0.8, d * 0.8) * 0.035 + noise.get_noise_2d(x * 3.0, d * 3.0) * 0.012) * fade
			"cobble":
				var cx := fposmod(x, 0.12) / 0.12
				var cz := fposmod(d, 0.1) / 0.1
				h += 0.006 * (sin(cx * PI) * sin(cz * PI)) * fade
			"diag":
				var phase := sin(TAU * (d - z0) / 16.0)
				var side := 1.0 if x > 0.0 else -1.0
				h += 0.13 * maxf(phase * side, 0.0) * smoothstep(0.0, 1.2, ax) * fade
			"hill":
				var k := clampf((d - z0) / (z1 - z0), 0.0, 1.0)
				h += 7.5 * pow(sin(k * PI), 2.0)
			"rails":
				for c: float in [925.0, 926.5]:
					if absf(d - c) < 0.04:
						h += 0.03
				h += 0.01 * fade
			"waves":
				h += 0.075 * (1.0 - cos(TAU * (d - z0) / 25.0)) * fade
	# Обочины и поле.
	# Обочина чуть ниже асфальта, поле — пологие неровности.
	h -= edge * 0.06
	h += edge * noise.get_noise_2d(x * 0.08, d * 0.08) * 0.08
	return h


# Огибающая шины: колесо не проваливается в узкие щели и «чувствует» край кочки
# заранее — берём максимум по пятну контакта.
func tire_height(x: float, z: float, fwd: Vector2) -> float:
	var best := -INF
	for k: float in [-0.09, -0.045, 0.0, 0.045, 0.09]:
		var hh := height(x + fwd.x * k, z + fwd.y * k) - absf(k) * absf(k) * 3.0
		best = maxf(best, hh)
	return best


func normal(x: float, z: float) -> Vector3:
	var e := 0.05
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func friction(x: float, z: float) -> float:
	if absf(x) > WIDTH * 0.5 + 0.8:
		return 0.55
	var t := zone_type(-z)
	if t == "wet":
		return 0.55
	if t == "cobble":
		return 0.8
	return 0.95


# --- Сетка ------------------------------------------------------------------

func _row_step(d: float) -> float:
	var t := zone_type(d)
	match t:
		"wash", "cobble", "rails", "bumps":
			return 0.05
		"holes", "broken":
			return 0.12
		_:
			return 0.4


static func _noise_tex(freq: float, seed_v: int, normal_map: bool, cellular := false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	t.as_normal_map = normal_map
	t.bump_strength = 3.0
	if not normal_map:
		# Узкий диапазон яркости: зерно заметно, но не пестрит.
		var g := Gradient.new()
		g.set_color(0, Color(0.78, 0.78, 0.78))
		g.set_color(1, Color(1.0, 1.0, 1.0))
		t.color_ramp = g
	return t


func _build() -> void:
	# Асфальт: цвет участка из вершин, поверх — зернистость щебня и карта нормалей,
	# натянутые трипланарно в мировых координатах (у сетки нет развёртки).
	var mat: Material = StandardMaterial3D.new()
	var smat := mat as StandardMaterial3D
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = _noise_tex(0.08, 11, false, true)
	smat.normal_enabled = true
	smat.normal_texture = _noise_tex(0.12, 12, true, true)
	smat.normal_scale = 0.22
	smat.roughness = 0.93
	smat.roughness_texture = _noise_tex(0.03, 13, false)
	smat.uv1_triplanar = true
	smat.uv1_world_triplanar = true
	smat.uv1_scale = Vector3(0.9, 0.9, 0.9)
	smat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if TexLib.has("asphalt_02") and TexLib.has("gravel_road") and TexLib.has("sparse_grass"):
		mat = _surface_material()
	elif TexLib.has("asphalt_02"):
		# Фотоскан асфальта; цвет вершин (зоны, разметка) тонирует его.
		smat.albedo_texture = TexLib.tex("asphalt_02", "diff")
		smat.albedo_color = Color(2.4, 2.4, 2.4)
		smat.normal_texture = TexLib.tex("asphalt_02", "nor")
		smat.normal_scale = 1.0
		smat.roughness_texture = TexLib.tex("asphalt_02", "rough")
		smat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		smat.roughness = 1.0
		smat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	var chunk := 25.0
	var d := -30.0
	while d < LENGTH + 30.0:
		_build_chunk(d, minf(d + chunk, LENGTH + 30.0), mat)
		d += chunk
	# Поле вокруг.
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, LENGTH + 6000)   # до горизонта: края поля не видно
	var field := MeshInstance3D.new()
	field.mesh = plane
	field.position = Vector3(0, -0.18, -LENGTH * 0.5)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.5, 0.24)
	fm.albedo_texture = _noise_tex(0.02, 21, false)
	fm.normal_enabled = true
	fm.normal_texture = _noise_tex(0.2, 22, true)
	fm.roughness = 1.0
	fm.uv1_triplanar = true
	fm.uv1_world_triplanar = true
	fm.uv1_scale = Vector3(0.08, 0.08, 0.08)
	if TexLib.has("sparse_grass"):
		fm = TexLib.material("sparse_grass", 0.25)
	field.material_override = fm
	add_child(field)
	_plant_trees()
	# Таблички участков.
	for zdef in ZONES:
		var l := Label3D.new()
		l.text = "%s\n%s" % [zdef[2], zdef[3]]
		l.font_size = 64
		l.pixel_size = 0.004
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.modulate = Color(1, 0.95, 0.7)
		l.outline_size = 12
		l.position = Vector3(WIDTH * 0.5 + 1.6, 1.6 + height(WIDTH * 0.5 + 1.6, -zdef[0]), -zdef[0])
		add_child(l)
		var post := MeshUtil.box(Vector3(0.08, 1.5, 0.08), "steel", l.position - Vector3(0, 0.9, 0))
		add_child(post)
	# Километровые столбики через 50 м.
	var m := 0.0
	while m < LENGTH:
		var p := MeshUtil.box(Vector3(0.12, 0.8, 0.12), "plastic_white", Vector3(-WIDTH * 0.5 - 0.9, height(-WIDTH * 0.5 - 0.9, -m) + 0.4, -m))
		add_child(p)
		var t := Label3D.new()
		t.text = "%d м" % int(m)
		t.font_size = 48
		t.pixel_size = 0.004
		t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		t.position = p.position + Vector3(0, 0.6, 0)
		add_child(t)
		m += 50.0


func _surface_color(x: float, d: float) -> Color:
	var ax := absf(x)
	if ax > WIDTH * 0.5 + 0.3:
		return Color(0.25, 0.33, 0.16).lerp(Color(0.33, 0.28, 0.2), clampf(noise.get_noise_2d(x, d) + 0.5, 0.0, 1.0))
	var t := zone_type(d)
	var c := Color(0.17, 0.17, 0.18)
	match t:
		"cobble":
			c = Color(0.38, 0.35, 0.32)
		"broken", "holes":
			c = Color(0.23, 0.22, 0.21)
		"wet":
			c = Color(0.09, 0.1, 0.12)
		"rails":
			c = Color(0.3, 0.27, 0.24)
	# Разметка: осевая прерывистая и краевые линии.
	if ax < 0.06 and fposmod(d, 9.0) < 3.0:
		c = Color(0.85, 0.85, 0.8)
	if absf(ax - (WIDTH * 0.5 - 0.25)) < 0.06:
		c = Color(0.85, 0.85, 0.8)
	if t == "bumps":
		for b in [300.0, 320.0, 340.0]:
			if absf(d - b) < 0.5:
				c = Color(0.85, 0.7, 0.1) if int((x + 10.0) / 0.5) % 2 == 0 else Color(0.1, 0.1, 0.1)
	if t == "rails":
		for r in [925.0, 926.5]:
			if absf(d - r) < 0.04:
				c = Color(0.55, 0.55, 0.58)
	return c


func _build_chunk(d0: float, d1: float, mat: Material) -> void:
	var xs := PackedFloat32Array()
	var x := -WIDTH * 0.5 - 6.0
	while x <= WIDTH * 0.5 + 6.0 + 1e-4:
		xs.append(x)
		var ax := absf(x)
		x += 0.12 if ax < WIDTH * 0.5 + 0.5 else 0.75
	var ds := PackedFloat32Array()
	var d := d0
	while d < d1:
		ds.append(d)
		d += _row_step(d)
	ds.append(d1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := xs.size()
	for r in ds.size():
		for c in cols:
			var px := xs[c]
			var pd := ds[r]
			st.set_color(_surface_color(px, pd))
			st.add_vertex(Vector3(px, height(px, -pd), -pd))
	for r in ds.size() - 1:
		for c in cols - 1:
			var i0 := r * cols + c
			var i1 := i0 + 1
			var i2 := i0 + cols
			var i3 := i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	_chunk_meshes.append(mi)


# Лесополосы и трава — см. Vegetation.
func _plant_trees() -> void:
	Vegetation.plant(self)


# Покрытие из фотосканов: асфальт (цвет зоны и разметка — из вершин), гравийная
# обочина с рваной кромкой, дальше земля с травой. На мокром участке асфальт
# темнеет и блестит, в колеях стоит вода.
const SURFACE_SHADER := """
shader_type spatial;
uniform sampler2D a_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_rgh : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_rgh : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D s_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D s_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float half_width = 4.5;
varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 uva = wp.xz * 0.33;
	vec2 uvg = wp.xz * 0.45;
	vec2 uvs = wp.xz * 0.25;
	float ax = abs(wp.x);
	float n = vnoise(wp.xz * 0.9) * 0.35 + vnoise(wp.xz * 3.1) * 0.15;
	float shoulder = smoothstep(half_width + 0.12, half_width + 0.32, ax + n * 0.25);
	float grass = smoothstep(half_width + 1.0, half_width + 1.9, ax + n * 1.2);
	vec3 vc = COLOR.rgb;
	float lum = dot(vc, vec3(0.333));
	float wet = (vc.b > vc.r + 0.015 && lum < 0.13) ? 1.0 : 0.0;
	float paint = smoothstep(0.45, 0.7, lum);
	// Асфальт: светлеет на обкатанных колеях, разметка стёрта местами.
	vec3 at = texture(a_alb, uva).rgb;
	float wheel_track = smoothstep(0.5, 0.0, abs(abs(mod(wp.x, 4.5) - 2.25) - 0.9)) * 0.08;
	vec3 asphalt = at * vc * 2.4 * (1.0 + wheel_track);
	float worn = smoothstep(0.35, 0.75, vnoise(wp.xz * vec2(1.5, 0.4)));
	asphalt = mix(asphalt, mix(vec3(0.82, 0.82, 0.78) * (0.8 + 0.2 * at.r * 2.0), at * 0.55, worn * 0.45), paint);
	float ra = mix(texture(a_rgh, uva).r, 0.65, paint);
	// Мокрый асфальт: темнее, глаже, в колеях — лужицы.
	float puddle = wet * smoothstep(0.55, 0.75, vnoise(wp.xz * 0.35) + wheel_track * 4.0);
	asphalt *= mix(1.0, 0.55, wet);
	ra = mix(ra, mix(0.25, 0.04, puddle), wet);
	vec3 soil = texture(s_alb, uvs).rgb;
	vec3 gravel = texture(g_alb, uvg).rgb;
	// Щебень обочины серый, а не рыжий: убираем насыщенность скана.
	gravel = mix(vec3(dot(gravel, vec3(0.3, 0.55, 0.15))), gravel, 0.35) * 0.9;
	soil *= vec3(0.95, 1.0, 0.9);
	vec3 col = mix(mix(asphalt, gravel, shoulder), soil, grass);
	vec3 nm = mix(mix(texture(a_nor, uva).rgb, texture(g_nor, uvg).rgb, shoulder), texture(s_nor, uvs).rgb, grass);
	nm = mix(nm, vec3(0.5, 0.5, 1.0), puddle * 0.9);
	ALBEDO = col;
	NORMAL_MAP = nm;
	ROUGHNESS = mix(mix(ra, texture(g_rgh, uvg).r, shoulder), 0.95, grass);
	SPECULAR = 0.5;
}
"""


func _surface_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SURFACE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("a_alb", TexLib.tex("asphalt_02", "diff"))
	m.set_shader_parameter("a_nor", TexLib.tex("asphalt_02", "nor"))
	m.set_shader_parameter("a_rgh", TexLib.tex("asphalt_02", "rough"))
	m.set_shader_parameter("g_alb", TexLib.tex("gravel_road", "diff"))
	m.set_shader_parameter("g_nor", TexLib.tex("gravel_road", "nor"))
	m.set_shader_parameter("g_rgh", TexLib.tex("gravel_road", "rough"))
	m.set_shader_parameter("s_alb", TexLib.tex("sparse_grass", "diff"))
	m.set_shader_parameter("s_nor", TexLib.tex("sparse_grass", "nor"))
	m.set_shader_parameter("half_width", WIDTH * 0.5)
	return m
