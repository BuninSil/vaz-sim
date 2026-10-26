class_name CarEffects
extends Node3D

# Спецэффекты машины, управляемые моделью:
#  • выхлоп: белый пар у холодного мотора, чёрная копоть при богатой смеси,
#    сизый дым при угаре масла (кольца, поршни), белый — при пробитой прокладке;
#  • вспышка пламени из трубы при хлопке в глушителе;
#  • дым из-под колёс при пробуксовке и заносе, чёрные следы на асфальте;
#  • пыль на обочине и разбитой дороге, брызги на мокром асфальте;
#  • пар из-под капота при закипании, искры при пробое подвески.

const TAILPIPE := Vector3(0.31, -0.33, 2.06)    # срез выхлопной трубы, координаты кузова
const SKID_MAX := 2400

var car: Car
var sim: EngineSim

var _exhaust: GPUParticles3D
var _exhaust_mat: ParticleProcessMaterial
var _flame: GPUParticles3D
var _flash: OmniLight3D
var _flash_t := 0.0
var _steam: GPUParticles3D
var _sparks: GPUParticles3D
var _tire_smoke: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _spray: Array[GPUParticles3D] = []
var _skids: MultiMeshInstance3D
var _skid_next := 0
var _skid_count := 0
var _skid_prev: Array = [null, null, null, null]
var _prev_bump: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _smoke_tex: Texture2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_smoke_tex = _make_smoke_texture()
	_exhaust = _particles(200, 2.6, Color(0.9, 0.9, 0.9, 0.5), 0.15, 1.5, Vector3(0, 0.3, 0), 0.25)
	_exhaust_mat = _exhaust.process_material
	_exhaust_mat.direction = Vector3(0, -0.15, 1)
	_exhaust_mat.spread = 8.0
	_exhaust_mat.initial_velocity_min = 1.5
	_exhaust_mat.initial_velocity_max = 2.5
	_exhaust_mat.damping_min = 1.5
	_exhaust_mat.damping_max = 2.5
	_exhaust.position = TAILPIPE
	add_child(_exhaust)
	# Пламя хлопка: короткая вспышка частиц и света.
	_flame = _particles(24, 0.12, Color(1.0, 0.55, 0.15, 1.0), 0.05, 0.22, Vector3.ZERO, 0.0, true)
	var fm: ParticleProcessMaterial = _flame.process_material
	fm.direction = Vector3(0, 0, 1)
	fm.spread = 14.0
	fm.initial_velocity_min = 4.0
	fm.initial_velocity_max = 8.0
	_flame.one_shot = true
	_flame.explosiveness = 0.9
	_flame.emitting = false
	_flame.position = TAILPIPE
	add_child(_flame)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.55, 0.2)
	_flash.omni_range = 3.0
	_flash.light_energy = 0.0
	_flash.position = TAILPIPE + Vector3(0, 0.05, 0.2)
	add_child(_flash)
	# Пар из-под капота: из щели между капотом и решёткой.
	_steam = _particles(120, 2.0, Color(0.95, 0.95, 0.95, 0.45), 0.2, 1.3, Vector3(0, 1.4, 0), 0.4)
	var sm: ParticleProcessMaterial = _steam.process_material
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(0.55, 0.02, 0.15)
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 25.0
	sm.initial_velocity_min = 0.6
	sm.initial_velocity_max = 1.4
	_steam.position = Vector3(0, 0.22, -1.62)
	_steam.amount_ratio = 0.0
	add_child(_steam)
	# Искры от удара днищем.
	_sparks = _particles(60, 0.45, Color(1.0, 0.7, 0.25, 1.0), 0.015, 0.03, Vector3(0, -9.8, 0), 0.0, true)
	var spm: ParticleProcessMaterial = _sparks.process_material
	spm.direction = Vector3(0, 0.4, 1)
	spm.spread = 60.0
	spm.initial_velocity_min = 3.0
	spm.initial_velocity_max = 7.0
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	_sparks.position = Vector3(0, -0.45, -0.3)
	add_child(_sparks)
	for i in 4:
		var ts := _particles(200, 2.6, Color(0.93, 0.93, 0.93, 0.8), 0.35, 3.0, Vector3(0, 0.35, 0), 0.6)
		ts.amount_ratio = 0.0
		add_child(ts)
		_tire_smoke.append(ts)
		var du := _particles(220, 2.6, Color(0.62, 0.55, 0.43, 0.7), 0.3, 2.6, Vector3(0, -0.3, 0), 0.5)
		var dm: ParticleProcessMaterial = du.process_material
		dm.direction = Vector3(0, 0.6, 1)
		dm.spread = 30.0
		dm.initial_velocity_min = 1.0
		dm.initial_velocity_max = 3.0
		du.amount_ratio = 0.0
		add_child(du)
		_dust.append(du)
		var sp := _particles(140, 1.0, Color(0.88, 0.9, 0.93, 0.55), 0.12, 1.1, Vector3(0, -6.0, 0), 0.2)
		var spr: ParticleProcessMaterial = sp.process_material
		spr.direction = Vector3(0, 0.8, 1)
		spr.spread = 25.0
		spr.initial_velocity_min = 2.0
		spr.initial_velocity_max = 4.5
		sp.amount_ratio = 0.0
		add_child(sp)
		_spray.append(sp)
	_build_skids()


func _make_smoke_texture() -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.09
	n.fractal_octaves = 3
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var fall := clampf(1.0 - d, 0.0, 1.0)
			fall = fall * fall * (3.0 - 2.0 * fall)
			var wisp := 0.55 + 0.45 * n.get_noise_2d(x, y)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(pow(fall, 0.8) * wisp * 1.7, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# Облако частиц в мировых координатах: след остаётся на месте, когда машина уезжает.
func _particles(amount: int, life: float, color: Color, size0: float, size1: float, gravity: Vector3, turbulence: float, glow := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 20, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.gravity = gravity
	m.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.08, Color(1, 1, 1, 1.0))
	ramp.add_point(0.5, Color(1, 1, 1, 0.6))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	m.color_ramp = rt
	var curve := Curve.new()
	# Облако быстро распухает и потом медленно расплывается.
	curve.add_point(Vector2(0, size0 / size1))
	curve.add_point(Vector2(0.2, lerpf(size0 / size1, 1.0, 0.7)))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.scale_min = size1 * 0.8
	m.scale_max = size1 * 1.2
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -40.0
	m.angular_velocity_max = 40.0
	if turbulence > 0.0:
		m.turbulence_enabled = true
		m.turbulence_noise_strength = turbulence * 3.0
		m.turbulence_noise_scale = 2.0
		m.turbulence_influence_min = 0.05
		m.turbulence_influence_max = 0.15
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _smoke_tex
	mat.disable_receive_shadows = true
	if glow:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.2)
		mat.emission_energy_multiplier = 4.0
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		mat.roughness = 1.0
	quad.material = mat
	p.draw_pass_1 = quad
	return p


func _build_skids() -> void:
	_skids = MultiMeshInstance3D.new()
	_skids.top_level = true
	_skids.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 1
	plane.material = mat
	mm.mesh = plane
	mm.instance_count = SKID_MAX
	mm.visible_instance_count = 0
	_skids.multimesh = mm
	add_child(_skids)
	_skids.global_transform = Transform3D.IDENTITY


func clear_skids() -> void:
	_skids.multimesh.visible_instance_count = 0
	_skid_next = 0
	_skid_count = 0
	_skid_prev = [null, null, null, null]


func flash(strength: float) -> void:
	_flash_t = 0.09
	_flash.light_energy = 6.0 * strength
	_flame.amount_ratio = clampf(strength, 0.3, 1.0)
	_flame.restart()


func _process(delta: float) -> void:
	if car == null or sim == null:
		return
	_flash_t -= delta
	if _flash_t <= 0.0:
		_flash.light_energy = 0.0
	_update_exhaust()
	_update_wheels()
	var boil := 0.0
	if sim.thermal.boiling:
		boil = clampf((sim.thermal.t_coolant - 375.0) / 12.0, 0.3, 1.0)
	_steam.amount_ratio = boil
	_steam.emitting = boil > 0.01


func _update_exhaust() -> void:
	var rpm := sim.rpm()
	var running := rpm > 300.0
	var load := clampf((sim.im_p / Gas.P_ATM - 0.3) / 0.6, 0.0, 1.0)
	var flow := clampf(rpm / 5500.0, 0.05, 1.0) * lerpf(0.4, 1.0, load)
	# Цвет и густота дыма по состоянию мотора.
	var cold := clampf((335.0 - sim.thermal.t_coolant) / 40.0, 0.0, 1.0) * clampf((300.0 - sim.thermal.t_ambient) / 25.0 + 0.4, 0.2, 1.0)
	var rich := clampf((0.88 - sim.lambda_avg) / 0.2, 0.0, 1.0) * load
	var oil := 0.0
	for c in sim.cylinders:
		oil = maxf(oil, c.ring_wear * 0.8 + c.piston_damage)
	oil = clampf(oil, 0.0, 1.0)
	var coolant := clampf((sim.head_gasket_damage - 0.4) * 2.0, 0.0, 1.0)
	var white := maxf(cold, coolant)
	var density := 0.06 + white * 0.75 + rich * 0.7 + oil * 0.6
	var col := Color(0.92, 0.92, 0.92)
	col = col.lerp(Color(0.55, 0.6, 0.7), oil * (1.0 - white))
	col = col.lerp(Color(0.08, 0.08, 0.08), rich)
	col.a = clampf(density, 0.0, 0.85)
	_exhaust_mat.color = col
	_exhaust_mat.initial_velocity_min = 1.0 + 4.0 * flow
	_exhaust_mat.initial_velocity_max = 2.0 + 6.0 * flow
	_exhaust.amount_ratio = clampf(0.3 + flow, 0.0, 1.0)
	_exhaust.emitting = running


func _update_wheels() -> void:
	var vd := car.vd
	var v := absf(car.speed_kmh()) / 3.6
	var xf := car.global_transform
	var zone := car.road.zone_type(-xf.origin.z)
	var off_road := absf(xf.origin.x) > Road.WIDTH * 0.5 + 0.8
	var wet := zone == "wet" and not off_road
	var dusty := off_road or zone == "broken" or zone == "waves"
	var mm := _skids.multimesh
	for i in 4:
		var local := car.wheel_center_local(i) - Vector3(0, EngineSpecs.WHEEL_RADIUS - 0.03, 0)
		var world := xf * local
		var lat := smoothstep(0.1, 0.25, absf(car.slip_angle[i]))
		var lon := smoothstep(0.15, 0.5, absf(vd.slip[i]))
		var slide := maxf(lat, lon) if car.contact[i] else 0.0
		var spin_speed := absf(vd.wheel_omega[i] * EngineSpecs.WHEEL_RADIUS)
		var rub := clampf(maxf(v, spin_speed) / 6.0, 0.0, 1.0)
		var asphalt := not off_road and not wet and zone != "cobble"
		for list in [_tire_smoke, _dust, _spray]:
			(list[i] as GPUParticles3D).global_position = world
		var smoke := slide * rub * (1.0 if asphalt else 0.0)
		_tire_smoke[i].amount_ratio = smoke
		_tire_smoke[i].emitting = smoke > 0.02
		var dust := clampf(v / 15.0, 0.0, 1.0) * (1.0 if dusty and car.contact[i] else 0.0)
		dust = maxf(dust, slide * rub * (1.0 if off_road else 0.0))
		_dust[i].amount_ratio = dust * (0.5 if i < 2 else 1.0)
		_dust[i].emitting = dust > 0.02
		var spray := clampf((v - 3.0) / 15.0, 0.0, 1.0) * (1.0 if wet and car.contact[i] else 0.0)
		_spray[i].amount_ratio = spray
		_spray[i].emitting = spray > 0.02
		# Следы юза: тёмная полоса между прошлым и текущим положением пятна контакта.
		var marking := _skid_prev[i] != null
		if smoke > (0.12 if marking else 0.25):
			var ground := Vector3(world.x, _ground_y(world.x, world.z), world.z)
			var prev = _skid_prev[i]
			if prev != null and (prev as Vector3).distance_to(ground) > 0.05 and (prev as Vector3).distance_to(ground) < 2.0:
				var a: Vector3 = prev
				var dir := ground - a
				var len := dir.length()
				var fwd := dir / len
				var side := Vector3.UP.cross(fwd).normalized()
				var b := Basis(side * 0.17, Vector3.UP, fwd * len)
				mm.set_instance_transform(_skid_next, Transform3D(b, (a + ground) * 0.5))
				mm.set_instance_color(_skid_next, Color(0.05, 0.05, 0.05, 0.4 + 0.35 * smoke))
				_skid_next = (_skid_next + 1) % SKID_MAX
				_skid_count = mini(_skid_count + 1, SKID_MAX)
				mm.visible_instance_count = _skid_count
				_skid_prev[i] = ground
			elif prev == null or (prev as Vector3).distance_to(ground) >= 2.0:
				_skid_prev[i] = ground
		else:
			_skid_prev[i] = null
		# Пробой подвески на скорости — днище чиркает по дороге.
		var b_hit: float = car.bump_hit[i]
		if b_hit > _prev_bump[i] + 0.5 and v > 8.0 and _rng.randf() < 0.6:
			_sparks.global_position = world + xf.basis.y * 0.12
			_sparks.restart()
		_prev_bump[i] = b_hit


# Сетка дороги линейно интерполирует высоту между узлами, поэтому полоса
# кладётся по наибольшей высоте вокруг пятна — иначе она местами тонет в асфальте.
func _ground_y(x: float, z: float) -> float:
	var r := car.road
	var h := r.height(x, z)
	for o in [Vector2(0.35, 0), Vector2(-0.35, 0), Vector2(0, 0.35), Vector2(0, -0.35)]:
		h = maxf(h, r.height(x + o.x, z + o.y))
	return h + 0.015
