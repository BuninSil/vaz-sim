class_name Gauge
extends Control

# Стрелочный прибор в духе комбинации приборов «шестёрки».

var title := ""
var units := ""
var min_value := 0.0
var max_value := 100.0
var value := 0.0
var red_from := INF
var yellow_from := INF
var low_red_to := -INF
var major_step := 10.0
var label_scale := 1.0
var decimals := 0
var warn_lamp := ""
var warn_on := false

var _shown := 0.0


func _init(p_title := "", p_units := "", p_min := 0.0, p_max := 100.0, p_step := 10.0) -> void:
	title = p_title
	units = p_units
	min_value = p_min
	max_value = p_max
	major_step = p_step
	custom_minimum_size = Vector2(150, 150)


func set_value(v: float) -> void:
	value = v
	queue_redraw()


func _process(delta: float) -> void:
	var target := clampf(value, min_value, max_value)
	if absf(target - _shown) > (max_value - min_value) * 0.0005:
		_shown = lerpf(_shown, target, clampf(delta * 14.0, 0.0, 1.0))
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	var font := get_theme_default_font()
	draw_circle(c, r + 4.0, Color(0.02, 0.025, 0.03, 0.92))
	draw_arc(c, r + 3.0, 0.0, TAU, 64, Color(0.35, 0.38, 0.42), 2.0, true)
	var a0 := deg_to_rad(135.0)
	var a1 := deg_to_rad(405.0)
	# Цветные зоны.
	if red_from < max_value:
		draw_arc(c, r - 6.0, _angle(red_from, a0, a1), a1, 32, Color(0.85, 0.12, 0.08), 7.0, true)
	if yellow_from < max_value:
		draw_arc(c, r - 6.0, _angle(yellow_from, a0, a1), _angle(minf(red_from, max_value), a0, a1), 32, Color(0.9, 0.7, 0.1), 7.0, true)
	if low_red_to > min_value:
		draw_arc(c, r - 6.0, a0, _angle(low_red_to, a0, a1), 32, Color(0.85, 0.12, 0.08), 7.0, true)
	# Шкала.
	var v := min_value
	var fs := int(maxf(r * 0.16, 8.0) * label_scale)
	while v <= max_value + 1e-6:
		var a := _angle(v, a0, a1)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 14.0), c + dir * (r - 2.0), Color(0.9, 0.92, 0.95), 2.0, true)
		var txt := ("%." + str(decimals) + "f") % v if decimals > 0 else str(int(round(v)))
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + dir * (r - 28.0) - Vector2(ts.x * 0.5, -fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.85, 0.88, 0.9))
		var half := v + major_step * 0.5
		if half < max_value:
			var ah := _angle(half, a0, a1)
			var dh := Vector2(cos(ah), sin(ah))
			draw_line(c + dh * (r - 8.0), c + dh * (r - 2.0), Color(0.6, 0.63, 0.66), 1.0, true)
		v += major_step
	# Подписи.
	var tsz := int(maxf(r * 0.15, 9.0) * (0.85 if r < 70.0 else 1.0))
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, tsz)
	draw_string(font, c + Vector2(-tw.x * 0.5, r * 0.42), title, HORIZONTAL_ALIGNMENT_CENTER, -1, tsz, Color(0.7, 0.75, 0.8))
	var vt := (("%." + str(maxi(decimals, 0)) + "f") % value) + " " + units
	var vw := font.get_string_size(vt, HORIZONTAL_ALIGNMENT_CENTER, -1, tsz + 2)
	draw_string(font, c + Vector2(-vw.x * 0.5, r * 0.68), vt, HORIZONTAL_ALIGNMENT_CENTER, -1, tsz + 2, Color(1, 1, 1))
	if warn_lamp != "":
		var lc := Color(1.0, 0.2, 0.1) if warn_on else Color(0.2, 0.08, 0.06)
		draw_circle(c + Vector2(0, -r * 0.38), r * 0.09, lc)
		var lw := font.get_string_size(warn_lamp, HORIZONTAL_ALIGNMENT_CENTER, -1, tsz - 2)
		draw_string(font, c + Vector2(-lw.x * 0.5, -r * 0.18), warn_lamp, HORIZONTAL_ALIGNMENT_CENTER, -1, tsz - 2, lc.lightened(0.2))
	# Стрелка.
	var an := _angle(_shown, a0, a1)
	var nd := Vector2(cos(an), sin(an))
	draw_line(c - nd * r * 0.15, c + nd * (r - 10.0), Color(1.0, 0.45, 0.1), 3.0, true)
	draw_circle(c, r * 0.07, Color(0.2, 0.2, 0.22))


func _angle(v: float, a0: float, a1: float) -> float:
	return lerpf(a0, a1, clampf((v - min_value) / (max_value - min_value), 0.0, 1.0))
