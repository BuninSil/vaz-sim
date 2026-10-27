class_name PerfOverlay
extends Label

# Счётчик производительности: где теряются кадры — процессор, видеокарта или расчёт двигателя.
# Включается кнопкой «FPS» в тулбаре, на телефоне — сразу.

var car: Car
var _t := 0.0
var _frames := 0
var _worst := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_theme_constant_override("outline_size", 5)
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	position.y = 52
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if _t < 0.5:
		return
	var vp := get_viewport().get_viewport_rid()
	var fps := _frames / _t
	var lines := "%.0f FPS (худший кадр %.0f мс)   CPU кадр %.1f мс · физика %.1f мс   GPU %.1f мс" % [fps, _worst * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_gpu(vp)]
	if car != null and car.is_inside_tree() and car.visible:
		lines += "\nмотор %.1f мс на шаг (ждали %.1f) · шагов физики %d/с" % [car.sim_ms, car.wait_ms, Engine.physics_ticks_per_second]
	lines += "\nвызовов %d · треугольников %.2f млн · 3D %.0f %% · %s, %s" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
		get_viewport().scaling_3d_scale * 100.0,
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()]
	text = lines
	_t = 0.0
	_frames = 0
	_worst = 0.0
