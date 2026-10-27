extends Node3D

# Главная сцена: связывает модель двигателя, трёхмерную модель, звук и интерфейс.

const RUNNING_REMOVABLE := ["wire_1", "wire_2", "wire_3", "wire_4", "air_filter_lid", "air_filter_element", "air_filter_housing", "dipstick", "valve_cover"]

var sim := EngineSim.new()
var model: EngineModel
var rig: CameraRig
var audio: EngineAudio
var hud: Hud
var touch: TouchControls

var selected: EnginePart
var hovered: EnginePart
var real_factor := 1.0
var _pedal := 0.0
var _graph_timer := 0.0
var _sweep_active := false
var _sweep_rpm := 0.0
var _sweep_time := 0.0
var _sweep_points: Array = []
var _sweep_saved := {}
var _queue: Array = []        # отложенные операции разборки/сборки
var _queue_timer := 0.0
var _removed_stack: Array[EnginePart] = []
var _view_phi := 0.0
var hover_enabled := true
# Раскладка снятых деталей на полу: текущий угол и радиус «верстака».
var _lay_angle := 0.0
var _lay_radius := 0.75
const FLOOR_Y := -0.36
var _last_click_time := 0
var _was_running := false
var drive_mode := false
var car: Car
var effects: CarEffects
var garage := {}
var cinematic: Cinematic
var road: Road
var stand_floor: MeshInstance3D
var sun: DirectionalLight3D
var env: Environment


func _ready() -> void:
	_build_world()
	model = EngineModel.new()
	add_child(model)
	model.part_changed.connect(_on_part_changed)
	rig = CameraRig.new()
	add_child(rig)
	rig.cinematic = cinematic
	rig.cockpit_xf = func() -> Transform3D:
		var bm := car.body_model
		# Глаза водителя: над подушкой сиденья, у средней стойки, взгляд вперёд.
		var eye := bm.global_transform * (bm._model_xf * Vector3(-37, 8, 54))
		var ahead := bm.global_transform * (bm._model_xf * Vector3(-37, 108, 44))
		return Transform3D.IDENTITY.looking_at(ahead - eye, bm.global_basis.y).translated(eye)
	audio = EngineAudio.new()
	add_child(audio)
	sim.record_audio = true
	var layer := CanvasLayer.new()
	add_child(layer)
	# Сенсорные кнопки лежат под вкладками: открытая панель их перекрывает.
	touch = TouchControls.new()
	touch.visible = false
	layer.add_child(touch)
	hud = Hud.new()
	hud.sim = sim
	hud.model = model
	layer.add_child(hud)
	touch.blocked = hud.is_over_ui
	rig.touch_blocked = func(p: Vector2) -> bool: return hud.is_over_ui(p) or touch.is_over_pad(p)
	touch.crank.connect(func(on: bool) -> void:
		if on:
			if sim.electrical.key == 0:
				sim.electrical.key = 1
			hud.start_cranking()
		else:
			hud.stop_cranking()
	)
	touch.gear_step.connect(_shift)
	touch.action.connect(func(a: String) -> void:
		match a:
			"camera":
				_next_camera()
			"lights":
				_next_lights()
			"ignition":
				sim.electrical.key = 0 if sim.electrical.key >= 1 else 1
	)
	hud.request_touch.connect(func(on: bool) -> void: touch.visible = on)
	hud.request_remove.connect(func() -> void: _remove(selected))
	hud.request_install.connect(func() -> void: _install(selected))
	hud.request_disassemble_all.connect(_disassemble_all)
	hud.request_assemble_all.connect(_assemble_all)
	hud.request_reset.connect(_reset_engine)
	hud.request_sweep.connect(_start_sweep)
	hud.request_view.connect(_on_view)
	hud.request_drive.connect(set_drive_mode)
	hud.request_teleport.connect(func(d: float) -> void:
		if car != null and drive_mode:
			car.place(d)
	)
	hud.request_lights.connect(_set_lights)
	hud.request_turn.connect(_set_turn)
	hud.request_hazard.connect(func() -> void:
		if car != null:
			car.body_model.hazard = not car.body_model.hazard
	)
	hud.request_daytime.connect(_set_daytime)
	hud.request_engine.connect(_swap_engine)
	hud.request_gearbox.connect(func(id: String, fd: float) -> void:
		if sim.rpm() > 30.0:
			hud.show_message("Коробку меняют на заглушённом двигателе.")
			return
		EngineSpecs.apply_gearbox(id, fd)
		sim.drivetrain.gear = 1
		sim.drivetrain.vehicle.reset()
		hud.set_gear(1)
		hud.refresh_gear_buttons()
		hud.show_message("Установлена %s, главная пара %.2f" % [EngineSpecs.GEARBOXES[id]["title"], fd])
	)
	hud.request_quality.connect(func(i: int) -> void:
		cinematic.set_quality(i)
		_apply_quality_extras()
	)
	hud.request_camera.connect(func(m: int) -> void:
		if drive_mode:
			rig.set_mode(m)
	)
	hud.request_opening.connect(func(n: String) -> void:
		if car != null and drive_mode:
			car.body_model.toggle_opening(n)
	)
	hud.request_garage.connect(func(param: String, value: Variant) -> void:
		garage[param] = value
		_apply_garage()
	)
	hud.request_body_xray.connect(func(on: bool) -> void:
		if car != null:
			car.body_model.set_xray(on)
			# Под непрозрачным капотом двигатель не виден — не тратим на него отрисовку.
			model.visible = on or car.body_model.is_open("hood")
	)
	hud.request_crank_turn.connect(_turn_crank)
	hud.request_xray.connect(func(on: bool) -> void: MeshUtil.set_xray(on))
	_reset_engine(90.0, 20.0)
	sim.electrical.key = 1
	hud.show_part(null, [], [], false, false)
	_draw_passport_curve()
	hud.show_message("Двигатель прогрет, зажигание включено. Удерживайте пробел или кнопку «Стартер», чтобы завести.")
	if OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args():
		hud.touch_check.button_pressed = true
		hud.setup_mobile()
		_setup_lite()


func _build_world() -> void:
	env = Environment.new()
	# Небо даёт и фон на трассе, и отражения/рассеянный свет металлу в обоих режимах.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.75)
	sky_mat.sky_horizon_color = Color(0.68, 0.76, 0.86)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.13)
	sky_mat.ground_horizon_color = Color(0.55, 0.58, 0.6)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_hdr_threshold = 1.3
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_apply_environment(false)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, -0.7, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_angular_distance = 0.6   # мягкий край теней
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 4.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.4, 0.0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)
	cinematic = Cinematic.new()
	add_child(cinematic)
	cinematic.setup(env, sun, self)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(6, 6)
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.position = Vector3(0, -0.36, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.11, 0.12, 0.13)
	fm.roughness = 0.9
	floor.material_override = fm
	add_child(floor)
	stand_floor = floor



func _reset_engine(t_c: float, ambient_c: float) -> void:
	_stop_sweep()
	sim.reset(t_c + 273.15, ambient_c + 273.15)
	sim.electrical.soc = clampf(sim.electrical.soc, 0.0, 1.0)
	if ambient_c < 0.0:
		sim.electrical.soc = minf(sim.electrical.soc, 0.75)
	hud.show_message("Состояние: %s" % ("прогретый двигатель" if t_c > 60.0 else "холодный двигатель, %.0f °C — нужен подсос" % t_c))


func _process(delta: float) -> void:
	_apply_part_states()
	_handle_controls(delta)
	_run_queue(delta)
	var phi := _view_phi
	var running_ok := ""
	var missing := model.missing_critical()
	var assembled := missing.is_empty()
	if drive_mode:
		# На трассе модель двигателя шагает в физике машины (_physics_process автомобиля).
		phi = sim.phi
		_view_phi = phi
		audio.feed(sim, delta)
		hud.refresh_drive(car)
	elif assembled:
		if not _was_running:
			# Двигатель только что собран — синхронизируем модель с положением вала.
			sim.phi = _view_phi
			sim.reset_gas()
			_was_running = true
		var t0 := Time.get_ticks_usec()
		var target_scale := hud.time_scale
		var dt := minf(delta, 1.0 / 20.0) * target_scale * real_factor
		sim.advance(dt)
		sim.publish()
		var cost := (Time.get_ticks_usec() - t0) / 1e6
		# Если расчёт не успевает за кадром, плавно замедляем время модели.
		if cost > 0.016:
			real_factor = maxf(real_factor * 0.92, 0.05)
		elif cost < 0.010:
			real_factor = minf(real_factor * 1.03, 1.0)
		phi = sim.phi
		_view_phi = phi
		audio.feed(sim, delta)
		if _sweep_active:
			_sweep_step(dt)
	else:
		_was_running = false
		if sim.electrical.key == 2:
			running_ok = "Стартер не крутит: двигатель не собран (нет: %s)" % _names(missing, 3)
		sim.omega = 0.0
		sim.publish()
		sim.out_dt.clear()
		sim.out_exhaust.clear()
		sim.out_intake.clear()
		sim.out_mech.clear()
		sim.out_knock.clear()
		audio.feed(sim, delta)
	model.update_view(sim, phi, delta)
	hud.refresh(delta, (1.0 if drive_mode else real_factor) * hud.time_scale, running_ok)
	if drive_mode:
		hud.g_speed.set_value(absf(car.speed_kmh()))
	_graph_timer -= delta
	if _graph_timer <= 0.0:
		_graph_timer = 0.15
		hud.refresh_graphs()
	_update_hover()


func _names(list: Array, limit: int) -> String:
	var names := []
	for p in list:
		if names.size() >= limit:
			names.append("…")
			break
		names.append((p as EnginePart).title)
	return ", ".join(names)


# Снятые детали превращаются в неисправности модели.
func _apply_part_states() -> void:
	var f := hud.faults
	for i in 4:
		sim.ignition.wire_connected[i] = model.is_installed("wire_%d" % (i + 1)) and not f.get("wire_%d" % i, false)
		sim.cylinders[i].plug_hole = not model.is_installed("spark_plug_%d" % (i + 1))
	var belt := model.is_installed("belt") and model.is_installed("crank_pulley")
	sim.thermal.water_pump_ok = belt and model.is_installed("water_pump") and model.is_installed("pump_pulley")
	sim.thermal.fan_ok = model.is_installed("fan")
	sim.electrical.alternator_ok = belt and model.is_installed("alternator") and not f.get("alternator", false)
	sim.carb.fuel_supply_ok = model.is_installed("fuel_pump") and not f.get("no_fuel", false)
	var th: int = f.get("thermostat", 0)
	sim.thermal.thermostat_mode = 2 if not model.is_installed("thermostat") else th
	audio.belt_loose = f.get("belt_loose", false)
	var clog: float = f.get("air_filter", 0.0)
	sim.carb.air_filter_clog = clog if model.is_installed("air_filter_element") else -0.07
	if not model.is_installed("water_pump"):
		sim.thermal.coolant_level = maxf(sim.thermal.coolant_level - 0.01 * get_process_delta_time(), 0.05)


func _handle_controls(delta: float) -> void:
	if drive_mode:
		_drive_controls(delta)
	var foot := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var target := 1.0 if foot else maxf(hud.hand_throttle, _touch_throttle())
	# Автосцепление переключает как водитель: на время переключения газ сброшен,
	# иначе мотор без нагрузки за доли секунды улетает за отсечку прочности (8200 об/мин).
	if drive_mode and sim.drivetrain.vehicle.auto_clutch and sim.drivetrain.vehicle.shift_timer > 0.0:
		target = 0.0
	_pedal = move_toward(_pedal, target, delta * (4.0 if target > _pedal else 3.0))
	if not _sweep_active:
		sim.carb.pedal = _pedal
	if sim.drivetrain.mode == Drivetrain.Mode.CAR:
		if Input.is_key_pressed(KEY_SHIFT) or _touch_on("clutch"):
			sim.drivetrain.clutch = move_toward(sim.drivetrain.clutch, 0.0, delta * 6.0)
		else:
			sim.drivetrain.clutch = move_toward(sim.drivetrain.clutch, hud.clutch_slider.value, delta * 1.5)
		if Input.is_key_pressed(KEY_B) or _touch_on("brake"):
			sim.drivetrain.brake = 1.0
	if sim.electrical.key == 2 and not model.is_installed("starter"):
		hud.show_message("Стартер снят — завести нечем")
		hud.stop_cranking()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE and not k.echo:
			if k.pressed:
				if sim.electrical.key == 0:
					sim.electrical.key = 1
				hud.start_cranking()
			else:
				hud.stop_cranking()
			get_viewport().set_input_as_handled()
			return
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_TAB:
				hud.toggle_panel()
			KEY_L:
				_next_lights()
			KEY_H:
				if drive_mode:
					car.body_model.hazard = not car.body_model.hazard
			KEY_I:
				sim.electrical.key = 0 if sim.electrical.key >= 1 else 1
			KEY_C:
				var ch := sim.carb.choke
				hud.choke_slider.value = 0.6 if ch < 0.3 else (1.0 if ch < 0.8 else 0.0)
			KEY_X:
				MeshUtil.set_xray(not MeshUtil.material("cast_iron").transparency)
			KEY_DELETE:
				_remove(selected)
			KEY_INSERT, KEY_ENTER:
				_install(selected)
			KEY_BRACKETLEFT:
				if drive_mode:
					_set_turn(-1)
				else:
					_turn_crank(-10.0)
			KEY_BRACKETRIGHT:
				if drive_mode:
					_set_turn(1)
				else:
					_turn_crank(10.0)
			KEY_Q:
				_shift(-1)
			KEY_E:
				_shift(1)
			KEY_V:
				hud.follow_check.button_pressed = not hud.follow_check.button_pressed
			KEY_K:
				_next_camera()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				if drive_mode:
					return
				var idx: int = k.keycode - KEY_1
				rig.set_view(CameraRig.VIEWS.keys()[idx])
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not drive_mode:
			var p := _pick(mb.position)
			var now := Time.get_ticks_msec()
			var double := p != null and p == selected and now - _last_click_time < 400
			_last_click_time = now
			_select(p)
			if double:
				if p.removed:
					_install(p)
				else:
					_remove(p)


# Телефон: трёхмерная картинка в 0,7 разрешения с FSR, тени в две полосы и мельче,
# растения и модели облегчаются при постройке трассы (MeshUtil.lite).
func _setup_lite() -> void:
	MeshUtil.lite = true
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.mesh_lod_threshold = 4.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	Engine.max_fps = 60
	_apply_quality_extras()


# Что зависит от качества графики помимо настроек окружения (Cinematic.set_quality):
# разрешение 3D, тень солнца, трава. На минимуме — половина разрешения, без теней и травы.
func _apply_quality_extras() -> void:
	var q := cinematic.quality
	var vp := get_viewport()
	if MeshUtil.lite:
		vp.scaling_3d_scale = 0.5 if q == 3 else 0.7
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 0.75 if q == 3 else 1.0
	sun.shadow_enabled = q != 3
	if road != null:
		for n in road.get_children():
			if n.get_meta("veg", "") in ["grass", "plant"]:
				(n as Node3D).visible = q != 3


func _shift(dir: int) -> void:
	var vd := sim.drivetrain.vehicle
	if drive_mode:
		vd.request_gear((vd.requested_gear if vd.shift_timer > 0.0 else vd.gear) + dir)
	else:
		hud.set_gear(clampi(sim.drivetrain.gear + dir, 0, EngineSpecs.GEAR_RATIOS.size() - 1))


func _next_camera() -> void:
	if drive_mode:
		rig.set_mode((rig.mode + 1) % 3)
		hud.show_message(["Камера за машиной", "Вид из салона (ПКМ или палец — оглядеться)", "Кинокамера"][rig.mode])


func _next_lights() -> void:
	if drive_mode:
		var next := (car.body_model.light_mode + 1) % 4
		hud.lights_option.select(next)
		_set_lights(next)


func _touch_on(what: String) -> bool:
	return touch.visible and touch.get(what)


func _touch_throttle() -> float:
	return touch.throttle if touch.visible else 0.0


func _pick(screen: Vector2) -> EnginePart:
	var cam := rig.camera
	return model.pick(cam.project_ray_origin(screen), cam.project_ray_normal(screen))


func _update_hover() -> void:
	if drive_mode or not hover_enabled:
		if hovered != null and hovered != selected:
			hovered.set_highlight("")
		hovered = null
		return
	var mouse := get_viewport().get_mouse_position()
	var over_ui := hud.tabs.get_global_rect().has_point(mouse) or touch.is_over_pad(mouse)
	var p: EnginePart = null if over_ui else _pick(mouse)
	if p != hovered:
		if hovered != null and hovered != selected:
			hovered.set_highlight("")
		hovered = p
	if hovered != null and hovered != selected:
		hovered.set_highlight("hover")


func _select(p: EnginePart) -> void:
	if selected != null:
		selected.set_highlight("")
	selected = p
	if p != null:
		p.set_highlight("hover")
		if not drive_mode:
			hud.tabs.current_tab = hud.tabs.get_tab_count() - 1
	_refresh_part_panel()


func _refresh_part_panel() -> void:
	if selected == null:
		hud.show_part(null, [], [], false, false)
		return
	var blockers := model.blocking_parts(selected)
	var missing: Array[EnginePart] = []
	if selected.removed:
		missing = model.missing_children(selected)
	hud.show_part(selected, blockers, missing, model.can_remove(selected) and _running_allows(selected, false), model.can_install(selected) and _running_allows(selected, false))


func _running_allows(p: EnginePart, verbose: bool) -> bool:
	if sim.rpm() < 30.0 or RUNNING_REMOVABLE.has(p.id):
		return true
	if verbose:
		hud.show_message("Сначала заглушите двигатель: на ходу можно снимать только провода свечей, воздушный фильтр, щуп и клапанную крышку.")
	return false


func _remove(p: EnginePart) -> void:
	if p == null:
		return
	if drive_mode:
		hud.show_message("Разбирать двигатель можно на стенде — верните его с трассы.")
		return
	if p == model.block:
		hud.show_message("Блок цилиндров — основа двигателя, на нём держится всё остальное.")
		return
	if p.removed:
		hud.show_message("%s уже снята." % p.title)
		return
	if not _running_allows(p, true):
		return
	var blockers := model.blocking_parts(p)
	if not blockers.is_empty():
		hud.show_message("Чтобы снять «%s», сначала снимите: %s" % [p.title, _names(blockers, 4)])
		p.set_highlight("blocked")
		for b in blockers:
			(b as EnginePart).set_highlight("blocked")
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			for b in blockers:
				(b as EnginePart).set_highlight("hover" if b == selected else "")
			p.set_highlight("hover" if p == selected else "")
		)
		return
	p.detach(model, 0.8, _lay_out_target(p))
	_removed_stack.append(p)
	hud.show_message("Снято: %s" % p.title)


# Место на полу для снятой детали: по дуге с дальней от камеры стороны,
# ряд за рядом, с шагом по размеру детали.
func _lay_out_target(p: EnginePart) -> Vector3:
	var box := p.world_aabb()
	var size := maxf(box.size.x, box.size.z)
	var step := (size + 0.06) / _lay_radius
	if _lay_angle + step > PI * 1.6:
		_lay_angle = 0.0
		_lay_radius += 0.35
	_lay_angle += step * 0.5
	var a := _lay_angle - PI * 0.35
	_lay_angle += step * 0.5
	var spot := Vector3(sin(a) * _lay_radius + 0.05, 0.0, -cos(a) * _lay_radius)
	var center := box.get_center()
	var offset := p.global_position - center
	return Vector3(spot.x + offset.x, FLOOR_Y + (p.global_position.y - box.position.y) + 0.002, spot.z + offset.z)


func _install(p: EnginePart) -> void:
	if p == null or not p.removed:
		return
	if not _running_allows(p, true):
		return
	var blockers := model.blocking_parts(p)
	if not blockers.is_empty():
		hud.show_message("«%s» не поставить: мешают %s" % [p.title, _names(blockers, 4)])
		return
	var missing := model.missing_children(p)
	if not missing.is_empty():
		hud.show_message("Сначала соберите узел: не хватает %s" % _names(missing, 4))
		return
	p.attach()
	_removed_stack.erase(p)
	hud.show_message("Установлено: %s" % p.title)
	if _removed_stack.is_empty():
		_lay_angle = 0.0
		_lay_radius = 0.75


func _on_part_changed(_p: EnginePart) -> void:
	hud.refresh_removed(model)
	_refresh_part_panel()


# Полная разборка: снимаем всё, что уже можно снять, волнами, пока есть что снимать.
func _disassemble_all() -> void:
	if sim.rpm() > 30.0:
		hud.show_message("Сначала заглушите двигатель.")
		return
	_queue = [["disassemble"]]


func _assemble_all() -> void:
	_queue = [["assemble"]]


func _run_queue(delta: float) -> void:
	if _queue.is_empty():
		return
	_queue_timer -= delta
	if _queue_timer > 0.0:
		return
	_queue_timer = 0.18
	var job: String = _queue[0][0]
	if job == "disassemble":
		for p in model.part_order:
			if model.can_remove(p):
				_remove(p)
				return
		_queue.clear()
		hud.show_message("Двигатель разобран полностью: %d деталей." % _removed_stack.size())
	else:
		for i in range(_removed_stack.size() - 1, -1, -1):
			var p := _removed_stack[i]
			if model.can_install(p):
				_install(p)
				return
		_queue.clear()
		if _removed_stack.is_empty():
			hud.show_message("Двигатель собран.")
		else:
			hud.show_message("Не удалось поставить: %s" % _names(_removed_stack, 4))


func _turn_crank(deg: float) -> void:
	if sim.rpm() > 30.0:
		hud.show_message("Проворачивать вал вручную можно только на заглушённом двигателе.")
		return
	if not model.is_installed("crankshaft"):
		hud.show_message("Коленвал снят.")
		return
	if is_inf(deg):
		# Ставим 1-й цилиндр в ВМТ такта сжатия (метка на шкиве против 0°).
		_view_phi = 2.0 * PI
	else:
		_view_phi = fposmod(_view_phi + deg_to_rad(deg), 4.0 * PI)
	sim.phi = _view_phi
	sim.reset_gas()
	var local := fposmod(_view_phi, 4.0 * PI)
	var strokes: Array[String] = ["впуск", "сжатие", "рабочий ход", "выпуск"]
	var stroke := strokes[int(local / PI) % 4]
	hud.show_message("Коленвал: %.0f° · 1-й цилиндр: %s" % [rad_to_deg(fmod(local, TAU)), stroke])


# --- Снятие внешней характеристики ------------------------------------------

func _start_sweep() -> void:
	if sim.rpm() < 500.0:
		hud.show_message("Заведите двигатель, чтобы снять характеристику.")
		return
	_sweep_saved = {"hold": sim.drivetrain.dyno_hold_rpm, "target": sim.drivetrain.dyno_target_rpm, "heat": sim.thermal.heat_speedup}
	sim.drivetrain.mode = Drivetrain.Mode.DYNO
	sim.drivetrain.dyno_hold_rpm = true
	_sweep_active = true
	_sweep_rpm = 1000.0
	_sweep_time = 0.0
	_sweep_points.clear()
	hud.sweep_button.disabled = true
	hud.show_message("Снимаю характеристику: полный дроссель, 1000 → 6000 об/мин")


func _sweep_step(dt: float) -> void:
	sim.carb.pedal = 1.0
	sim.drivetrain.dyno_target_rpm = _sweep_rpm
	_sweep_time += dt
	if _sweep_time > 0.7:
		_sweep_points.append(Vector3(_sweep_rpm, sim.torque_avg, sim.power_avg / 1000.0))
		_sweep_rpm += 250.0
		_sweep_time = 0.0
		_draw_passport_curve()
		if _sweep_rpm > 6000.0:
			_stop_sweep()
			var best_t := Vector3.ZERO
			var best_p := Vector3.ZERO
			for pt in _sweep_points:
				if pt.y > best_t.y:
					best_t = pt
				if pt.z > best_p.z:
					best_p = pt
			hud.show_message("Максимум момента %.1f Н·м при %.0f об/мин, мощности %.1f кВт (%.0f л.с.) при %.0f об/мин" % [best_t.y, best_t.x, best_p.z, best_p.z * 1.36, best_p.x])


func _stop_sweep() -> void:
	if not _sweep_active:
		return
	_sweep_active = false
	sim.drivetrain.dyno_hold_rpm = _sweep_saved.get("hold", false)
	sim.drivetrain.dyno_target_rpm = _sweep_saved.get("target", 3000.0)
	hud.sweep_button.disabled = false


func _draw_passport_curve() -> void:
	var g := hud.graph_dyno
	g.clear_series()
	# Паспортная кривая ВАЗ-2103 (по заводскому графику).
	# Паспортная кривая ВАЗ-2103, масштабированная к моменту и оборотам выбранного мотора.
	var base := [Vector2(1000, 88), Vector2(1500, 93), Vector2(2000, 97), Vector2(2500, 100), Vector2(3000, 103), Vector2(3400, 104), Vector2(4000, 103), Vector2(4500, 100), Vector2(5000, 96), Vector2(5600, 90), Vector2(6000, 85)]
	var ref_t := PackedVector2Array()
	for pt in base:
		var k_rpm := EngineSpecs.MAX_TORQUE_RPM / 3400.0
		ref_t.append(Vector2(pt.x * lerpf(1.0, k_rpm, smoothstep(1000.0, 3400.0, pt.x)), pt.y * EngineSpecs.MAX_TORQUE_NM / 104.0))
	var ref_p := PackedVector2Array()
	for pt in ref_t:
		ref_p.append(Vector2(pt.x, pt.y * pt.x * TAU / 60.0 / 1000.0))
	g.add_series(ref_t, Color(0.6, 0.6, 0.6, 0.6), 1.0, "паспорт")
	g.add_series(ref_p, Color(0.5, 0.5, 0.7, 0.6), 1.0)
	var t := PackedVector2Array()
	var p := PackedVector2Array()
	for pt in _sweep_points:
		t.append(Vector2(pt.x, pt.y))
		p.append(Vector2(pt.x, pt.z))
	g.add_series(t, Color(1.0, 0.55, 0.2), 2.5, "момент, Н·м")
	g.add_series(p, Color(0.3, 0.75, 1.0), 2.5, "мощность, кВт")
	g.queue_redraw()


# --- Заезд на трассе ----------------------------------------------------------

func _on_view(v: String) -> void:
	if v == "__follow_on" or v == "__follow_off":
		rig.follow_auto_yaw = v == "__follow_on"
		return
	if drive_mode:
		return
	rig.set_view(v)


func set_drive_mode(on: bool) -> void:
	if on == drive_mode:
		return
	if on:
		var missing := model.missing_critical()
		if not missing.is_empty():
			hud.show_message("Сначала соберите двигатель: не хватает %s" % _names(missing, 3))
			return
		_stop_sweep()
		if road == null:
			hud.show_message("Строю трассу…")
			road = Road.new()
			add_child(road)
			car = Car.new()
			car.sim = sim
			car.road = road
			car.vd = sim.drivetrain.vehicle
			add_child(car)
			hud.perf.car = car
			car.teleported.connect(func() -> void:
				if effects != null:
					effects.clear_skids()
				if drive_mode:
					rig.start_follow.call_deferred(car.visual)
			)
			car.body_model.opening_moved.connect(_on_opening_moved)
			_apply_garage()
			_apply_quality_extras()
			effects = CarEffects.new()
			effects.car = car
			effects.sim = sim
			car.visual.add_child(effects)
			audio.backfire.connect(func(s: float) -> void:
				if drive_mode:
					effects.flash(s)
			)
		road.visible = true
		car.visible = true
		car.process_mode = Node.PROCESS_MODE_INHERIT
		stand_floor.visible = false
		sim.drivetrain.mode = Drivetrain.Mode.ROAD
		sim.drivetrain.vehicle.reset()
		car.place(5.0)
		# Двигатель переезжает со стенда под капот.
		remove_child(model)
		car.engine_mount.add_child(model)
		model.transform = Transform3D.IDENTITY
		rig.start_follow(car.visual)
		sun.directional_shadow_max_distance = 25.0 if MeshUtil.lite else 40.0
		_apply_environment(true)
		model.visible = car.body_model.xray
		audio.car = car
		Engine.physics_ticks_per_second = 60
		Engine.max_physics_steps_per_frame = 3
		drive_mode = true
		hud.set_drive_mode_ui(true)
		touch.set_drive_mode(true)
		hud.show_message("На трассе. Заводите (пробел), Q/E — передача, W — газ. Автосцепление включено.")
	else:
		car.finish_sim()
		car.engine_mount.remove_child(model)
		add_child(model)
		model.transform = Transform3D.IDENTITY
		car.visible = false
		audio.car = null
		audio.horn = false
		car.process_mode = Node.PROCESS_MODE_DISABLED
		road.visible = false
		stand_floor.visible = true
		sim.drivetrain.mode = Drivetrain.Mode.FREE
		rig.stop_follow()
		sun.directional_shadow_max_distance = 4.0
		_apply_environment(false)
		model.visible = true
		Engine.time_scale = 1.0
		drive_mode = false
		hud.set_drive_mode_ui(false)
		touch.set_drive_mode(false)
		hud.show_message("Двигатель снова на стенде.")


func _drive_controls(delta: float) -> void:
	var vd := sim.drivetrain.vehicle
	var steer := touch.steer if touch.visible else 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer += 1.0
	car.steer_input = clampf(steer, -1.0, 1.0)
	var braking := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or _touch_on("brake")
	vd.brake = move_toward(vd.brake, 1.0 if braking else 0.0, delta * (4.0 if braking else 6.0))
	vd.handbrake = 1.0 if Input.is_key_pressed(KEY_CTRL) or _touch_on("handbrake") else 0.0
	audio.horn = Input.is_key_pressed(KEY_G) or _touch_on("horn")
	var clutch_in := Input.is_key_pressed(KEY_SHIFT) or _touch_on("clutch")
	vd.clutch_pedal = move_toward(vd.clutch_pedal, 1.0 if clutch_in else 0.0, delta * (8.0 if clutch_in else 1.6))
	car.throttle = sim.carb.pedal
	Engine.time_scale = hud.time_scale
	if vd.last_message != "" and vd.grinding > 0.9:
		hud.show_message(vd.last_message)
		vd.last_message = ""

# Студия для стенда (тёмный фон, свет и отражения от неба) и открытая местность для трассы.
func _apply_environment(outdoor: bool) -> void:
	_apply_environment_base(outdoor)
	if cinematic != null:
		cinematic.apply_outdoor(outdoor)


func _apply_environment_base(outdoor: bool) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if outdoor:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_energy = 1.0
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssao_enabled = false
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = Color(0.68, 0.75, 0.85)
		env.fog_depth_begin = 60.0
		env.fog_depth_end = 700.0
		env.fog_aerial_perspective = 0.6
		env.fog_sky_affect = 0.15
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.045, 0.05, 0.06)
		env.ambient_light_energy = 0.6
		env.ssr_enabled = false
		env.ssao_enabled = true
		env.fog_enabled = false

func _set_lights(mode: int) -> void:
	if car == null:
		return
	car.body_model.light_mode = mode
	# Фары нагружают генератор: ближний/дальний — около 10 А.
	sim.electrical.headlights = mode >= 2
	hud.show_message(["Свет выключен", "Включены габариты", "Ближний свет", "Дальний свет"][mode])


# Повторное нажатие в ту же сторону выключает поворотник, как рычаг на руле.
func _set_turn(side: int) -> void:
	if car == null:
		return
	var bm := car.body_model
	if side < 0:
		bm.turn_left = not bm.turn_left
		bm.turn_right = false
	elif side > 0:
		bm.turn_right = not bm.turn_right
		bm.turn_left = false
	else:
		bm.turn_left = false
		bm.turn_right = false


func _set_daytime(index: int) -> void:
	match index:
		0:
			sun.light_energy = 1.25
			sun.light_color = Color(1.0, 0.96, 0.9)
			sun.rotation = Vector3(-0.75, -0.7, 0.0)
			env.ambient_light_energy = 1.0
			env.fog_light_color = Color(0.68, 0.75, 0.85)
		1:
			sun.light_energy = 0.55
			sun.light_color = Color(1.0, 0.6, 0.35)
			sun.rotation = Vector3(-0.12, -1.2, 0.0)
			env.ambient_light_energy = 0.7
			env.fog_light_color = Color(0.6, 0.45, 0.4)
		2:
			sun.light_energy = 0.04
			sun.light_color = Color(0.6, 0.7, 1.0)
			sun.rotation = Vector3(-0.9, 0.5, 0.0)
			env.ambient_light_energy = 0.35
			env.fog_light_color = Color(0.02, 0.025, 0.04)
	hud.show_message(["День", "Вечер", "Ночь — включите фары (L)"][index])
	if cinematic != null:
		cinematic.set_daytime(index)


# Настройки «Гаража» применяются к машине сразу и при её создании.
func _apply_garage() -> void:
	if car == null:
		return
	var bm := car.body_model
	var paint: int = garage.get("paint", 0)
	if garage.has("paint") or garage.has("metallic"):
		bm.set_paint(Hud.PAINTS[paint][1], garage.get("metallic", false))
	if garage.has("tint"):
		bm.set_tint(garage["tint"])
	var k_spring: float = garage.get("springs", 1.0)
	var k_damp: float = garage.get("dampers", 1.0)
	for i in 4:
		car.SPRING[i] = Car.SPRING_DEFAULT[i] * k_spring
		car.BUMP_DAMP[i] = Car.BUMP_DEFAULT[i] * k_damp
		car.REBOUND_DAMP[i] = Car.REBOUND_DEFAULT[i] * k_damp
	car.ANTIROLL_FRONT = Car.ANTIROLL_DEFAULT * float(garage.get("arb", 1.0))
	car.cargo_kg = garage.get("cargo", 75.0)
	car.ride_height = garage.get("ride_height", 0.0)
	car.steer_assist = garage.get("steer_assist", true)
	car.retune()


func _on_opening_moved(n: String, opening: bool) -> void:
	if n == "hood":
		audio.play("hood_open" if opening else "hood_close", 0.9)
		# Под открытым капотом виден двигатель.
		model.visible = opening or car.body_model.xray
	elif n == "trunk":
		audio.play("trunk_open" if opening else "trunk_close", 0.9)
	elif opening:
		audio.play("door_open", 0.8)
		if n.begins_with("door_r") and randf() < 0.5:
			audio.play("door_squeak", 0.5)
	else:
		audio.play("door_close" if randf() < 0.5 else "door_close2", 0.9)


# Замена двигателя: новый паспорт, новая модель на стенде (разборка — как у всех моторов семейства).
func _swap_engine(id: String) -> void:
	if sim.rpm() > 30.0:
		hud.show_message("Двигатель меняют заглушённым.")
		return
	if drive_mode:
		hud.show_message("Двигатель меняют на стенде — верните машину с трассы.")
		return
	if not _removed_stack.is_empty():
		hud.show_message("Сначала соберите текущий двигатель.")
		return
	EngineSpecs.apply_engine(id)
	sim.apply_specs()
	_reset_engine(90.0, 20.0)
	sim.electrical.key = 1
	# Пересобираем трёхмерную модель под новый диаметр и ход.
	_select(null)
	hovered = null
	var parent := model.get_parent()
	parent.remove_child(model)
	model.queue_free()
	model = EngineModel.new()
	parent.add_child(model)
	model.part_changed.connect(_on_part_changed)
	hud.model = model
	hud.refresh_removed(model)
	hud.refresh_gear_buttons()
	_draw_passport_curve()
	hud.show_message("Установлен %s" % EngineSpecs.ENGINES[id]["title"])
