class_name Cinematic
extends Node

# Кинематографичная картинка:
#  • небо — свой шейдер: рассеяние у горизонта, солнечный диск с ореолом,
#    кучевые облака, подсвеченные солнцем, звёзды и Млечный Путь ночью;
#  • объёмная дымка с рассеянием вперёд (лучи солнца), мягкие тени с полутенью,
#    непрямое освещение (SSIL) и затенение (SSAO), отражения SSR, свечение;
#  • «плёнка»: виньетка, зерно, лёгкая хроматическая аберрация на краях,
#    раздельное тонирование теней и светов, размытие заднего плана.

const SKY_SHADER := """
shader_type sky;
render_mode use_quarter_res_pass;

uniform vec3 zenith : source_color = vec3(0.16, 0.34, 0.68);
uniform vec3 horizon : source_color = vec3(0.68, 0.76, 0.86);
uniform vec3 ground : source_color = vec3(0.24, 0.24, 0.22);
uniform float energy = 1.0;
uniform float cloud_cover = 0.5;
uniform vec3 cloud_light : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 cloud_shadow : source_color = vec3(0.52, 0.56, 0.64);
uniform float night = 0.0;
uniform float sun_size = 0.012;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 sd = LIGHT0_DIRECTION;
	float mu = dot(d, sd);
	// Небо светлеет к горизонту (толща воздуха) и у солнца (рассеяние Ми).
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.45));
	float low_sun = 1.0 - clamp(sd.y * 3.0, 0.0, 1.0);
	col = mix(col, col * vec3(1.25, 0.85, 0.6), low_sun * pow(1.0 - clamp(h, 0.0, 1.0), 6.0) * 0.8);
	col += LIGHT0_COLOR * (pow(max(mu, 0.0), 8.0) * 0.25 + pow(max(mu, 0.0), 120.0) * 0.8) * LIGHT0_ENERGY * 0.4;
	if (h < 0.0) {
		col = mix(horizon * 0.85, ground, clamp(-h * 5.0, 0.0, 1.0));
	}
	// Солнечный диск (виден сквозь редкие облака).
	float disk = smoothstep(cos(sun_size), cos(sun_size * 0.7), mu) * step(0.0, h + 0.02);
	// Облака на «куполе»: проекция луча на плоскость высоко над землёй.
	float cl = 0.0;
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.06) * 0.55;
		float base = fbm(uv * 1.3);
		float detail = fbm(uv * 5.0 + 3.0);
		float c = base * 0.75 + detail * 0.25;
		cl = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, c) * smoothstep(0.0, 0.12, h);
		// Освещённость облака: толщина и сторона к солнцу.
		float thick = smoothstep(0.4, 0.9, c);
		float lit = clamp(0.55 + 0.6 * pow(max(mu, 0.0), 3.0) - thick * 0.45, 0.0, 1.3);
		vec3 ccol = mix(cloud_shadow, cloud_light * (0.7 + 0.5 * LIGHT0_COLOR), lit);
		// Серебристая кромка облаков возле солнца.
		ccol += LIGHT0_COLOR * pow(max(mu, 0.0), 24.0) * (1.0 - thick) * 1.5;
		col = mix(col, ccol, cl * 0.95);
	}
	col += LIGHT0_COLOR * disk * (1.0 - cl) * 30.0;
	// Ночь: звёзды и полоса Млечного Пути.
	if (night > 0.0 && h > 0.0) {
		vec2 g = d.xz / (h + 0.3) * 160.0;
		float s = hash(floor(g));
		float star = step(0.9965, s) * smoothstep(0.5, 0.0, length(fract(g) - 0.5)) * (0.5 + 0.5 * hash(floor(g) + 7.0));
		float milky = fbm(d.xz * 6.0) * exp(-pow(dot(d, normalize(vec3(0.4, 0.5, -0.75))) * 3.0, 2.0));
		col += (vec3(star) * 2.5 + vec3(0.25, 0.27, 0.35) * milky * 0.35) * night * (1.0 - cl);
	}
	COLOR = col * energy;
}
"""

const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.32;
uniform float grain = 0.03;
uniform float aberration = 0.0006;
uniform float toning = 0.45;
uniform float bars = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 off = c * aberration * (1.0 + r2 * 6.0);
	vec3 col = vec3(texture(screen, uv + off).r, texture(screen, uv).g, texture(screen, uv - off).b);
	// Тени чуть в бирюзу, света — в тёплое, как на киноплёнке.
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 split = mix(vec3(0.93, 1.0, 1.06), vec3(1.07, 1.0, 0.9), smoothstep(0.15, 0.75, l));
	col = mix(col, col * split, toning);
	col *= 1.0 - vignette * smoothstep(0.08, 0.6, r2 * 1.6);
	float n = fract(sin(dot(uv * vec2(1931.0, 1087.0) + fract(TIME * 7.13) * 91.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * grain * (1.2 - l);
	// Кинокашетирование 2,39:1.
	float bar = step(abs(c.y) * 2.0, 1.0 - bars);
	COLOR = vec4(col * bar, 1.0);
}
"""

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var post: ColorRect
var post_mat: ShaderMaterial
var attrs: CameraAttributesPractical
var quality := 0          # 0 — кино, 1 — высокое, 2 — быстрое
var outdoor := false


func setup(environment: Environment, sun_light: DirectionalLight3D, layer_parent: Node) -> void:
	env = environment
	sun = sun_light
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	env.sky.sky_material = sky_mat
	env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	# Плёночная обработка поверх 3D, но под интерфейсом.
	var layer := CanvasLayer.new()
	layer.layer = 0
	layer_parent.add_child(layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := Shader.new()
	ps.code = POST_SHADER
	post_mat = ShaderMaterial.new()
	post_mat.shader = ps
	post.material = post_mat
	layer.add_child(post)
	attrs = CameraAttributesPractical.new()
	# Мягкие тени с физичной полутенью (PCSS) и большой атлас.
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	set_quality(0)


func set_quality(q: int) -> void:
	quality = q
	var vp := get_viewport()
	vp.use_taa = q <= 1
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if q <= 1 else Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_debanding = true
	env.ssil_enabled = q == 0
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.volumetric_fog_enabled = q <= 1 and outdoor
	post.visible = q <= 1
	sun.shadow_blur = 1.0 if q == 0 else 1.5
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if q == 0 else (RenderingServer.SHADOW_QUALITY_SOFT_LOW if q == 1 else RenderingServer.SHADOW_QUALITY_HARD))
	apply_outdoor(outdoor)


func apply_outdoor(on: bool) -> void:
	outdoor = on
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	env.ssao_enabled = quality <= 1
	env.ssao_radius = 1.2 if on else 0.6
	env.ssao_intensity = 1.8
	env.ssao_light_affect = 0.15
	env.volumetric_fog_enabled = on and quality <= 1
	if on:
		env.volumetric_fog_density = 0.0025
		env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_length = 120.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_sky_affect = 0.0
		env.volumetric_fog_ambient_inject = 0.3
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2


# Время суток: краски неба, облака, звёзды; солнце и туман настраивает main.
func set_daytime(index: int) -> void:
	match index:
		0:
			_sky(Color(0.16, 0.34, 0.68), Color(0.68, 0.76, 0.86), 1.0, 0.45, Color(1.0, 0.98, 0.94), Color(0.52, 0.56, 0.64), 0.0)
		1:
			_sky(Color(0.14, 0.17, 0.38), Color(0.98, 0.58, 0.34), 0.75, 0.55, Color(1.0, 0.7, 0.45), Color(0.4, 0.3, 0.38), 0.0)
		2:
			_sky(Color(0.004, 0.007, 0.02), Color(0.03, 0.04, 0.07), 0.6, 0.3, Color(0.1, 0.11, 0.14), Color(0.03, 0.035, 0.05), 1.0)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_albedo = [Color(0.9, 0.92, 0.95), Color(1.0, 0.75, 0.6), Color(0.2, 0.22, 0.3)][index]
		env.volumetric_fog_density = [0.0025, 0.005, 0.006][index]


func _sky(zen: Color, hor: Color, e: float, cover: float, cl: Color, cs: Color, night: float) -> void:
	sky_mat.set_shader_parameter("zenith", zen)
	sky_mat.set_shader_parameter("horizon", hor)
	sky_mat.set_shader_parameter("energy", e)
	sky_mat.set_shader_parameter("cloud_cover", cover)
	sky_mat.set_shader_parameter("cloud_light", cl)
	sky_mat.set_shader_parameter("cloud_shadow", cs)
	sky_mat.set_shader_parameter("night", night)


# Глубина резкости под камеру: фокус на машине, задний план мягко размыт.
func focus(cam: Camera3D, distance: float, strength: float) -> void:
	if cam.attributes != attrs:
		cam.attributes = attrs
	var on := quality == 0 and strength > 0.0
	attrs.dof_blur_far_enabled = on
	attrs.dof_blur_near_enabled = on and distance > 8.0
	attrs.dof_blur_far_distance = distance + 6.0 + distance * 0.6
	attrs.dof_blur_far_transition = 25.0 + distance
	attrs.dof_blur_near_distance = maxf(distance * 0.45, 1.0)
	attrs.dof_blur_near_transition = maxf(distance * 0.3, 1.0)
	attrs.dof_blur_amount = 0.06 * strength


func set_bars(on: bool) -> void:
	post_mat.set_shader_parameter("bars", 0.24 if on else 0.0)
