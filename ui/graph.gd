class_name Graph
extends Control

# Простой график с осями. Серии — массивы точек Vector2 в единицах осей.

var title := ""
var x_label := ""
var y_label := ""
var x_min := 0.0
var x_max := 1.0
var y_min := 0.0
var y_max := 1.0
var log_x := false
var x_ticks: Array = []
var y_step := 0.0
var series: Array = []      # [{points: PackedVector2Array, color: Color, width: float, label: String}]
var markers: Array = []     # [{x: float, color: Color, label: String}]


func _init() -> void:
	custom_minimum_size = Vector2(300, 170)


func clear_series() -> void:
	series.clear()


func add_series(points: PackedVector2Array, color: Color, width := 2.0, label := "") -> void:
	series.append({"points": points, "color": color, "width": width, "label": label})


func _map(p: Vector2, rect: Rect2) -> Vector2:
	var xv := p.x
	var x0 := x_min
	var x1 := x_max
	if log_x:
		xv = log(maxf(xv, 1e-9))
		x0 = log(x_min)
		x1 = log(x_max)
	var u := (xv - x0) / (x1 - x0)
	var v := (p.y - y_min) / (y_max - y_min)
	return Vector2(rect.position.x + u * rect.size.x, rect.position.y + rect.size.y * (1.0 - v))


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035, 0.88))
	var rect := Rect2(Vector2(44, 22), size - Vector2(56, 44))
	draw_string(font, Vector2(8, 15), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 0.95))
	# Сетка.
	if y_step > 0.0:
		var y := ceilf(y_min / y_step) * y_step
		while y <= y_max + 1e-6:
			var a := _map(Vector2(x_min, y), rect)
			var b := _map(Vector2(x_max, y), rect)
			draw_line(a, b, Color(1, 1, 1, 0.07), 1.0)
			draw_string(font, a + Vector2(-40, 4), _fmt(y), HORIZONTAL_ALIGNMENT_RIGHT, 36, 10, Color(0.6, 0.65, 0.7))
			y += y_step
	for xt in x_ticks:
		var a2 := _map(Vector2(xt, y_min), rect)
		var b2 := _map(Vector2(xt, y_max), rect)
		draw_line(a2, b2, Color(1, 1, 1, 0.07), 1.0)
		draw_string(font, a2 + Vector2(-20, 13), _fmt(xt), HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color(0.6, 0.65, 0.7))
	draw_rect(rect, Color(0.4, 0.45, 0.5, 0.6), false, 1.0)
	draw_string(font, Vector2(rect.end.x - 160, size.y - 4), x_label, HORIZONTAL_ALIGNMENT_RIGHT, 160, 10, Color(0.6, 0.65, 0.7))
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 11), y_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.65, 0.7))
	for m in markers:
		var a3 := _map(Vector2(m["x"], y_min), rect)
		var b3 := _map(Vector2(m["x"], y_max), rect)
		draw_dashed_line(a3, b3, m["color"], 1.0, 4.0)
		draw_string(font, b3 + Vector2(3, 10), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, m["color"])
	var legend_x := rect.position.x + 6.0
	for s in series:
		var pts: PackedVector2Array = s["points"]
		if pts.size() < 2:
			continue
		var mapped := PackedVector2Array()
		for p in pts:
			var q := _map(p, rect)
			q.x = clampf(q.x, rect.position.x, rect.end.x)
			q.y = clampf(q.y, rect.position.y, rect.end.y)
			mapped.append(q)
		draw_polyline(mapped, s["color"], s["width"], true)
		if s["label"] != "":
			draw_string(font, Vector2(legend_x, rect.end.y - 6), s["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, s["color"])
			legend_x += font.get_string_size(s["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0


func _fmt(v: float) -> String:
	if absf(v) >= 100.0 or is_equal_approx(v, round(v)):
		return str(int(round(v)))
	return "%.1f" % v
