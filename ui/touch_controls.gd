class_name TouchControls
extends Control

# Экранные органы управления для телефона: руль, педали, стартер, передачи.
# Каждый палец ведём по его индексу — газ, руль и сцепление жмутся одновременно.

signal crank(pressed: bool)
signal gear_step(dir: int)
signal action(name: String)

var drive_mode := false

# Состояние «педалей» — main.gd складывает его с клавиатурой.
var throttle := 0.0
var steer := 0.0
var brake := false
var clutch := false
var handbrake := false
var horn := false

var blocked: Callable        # (Vector2) -> bool: точку перекрыл интерфейс поверх кнопок
var _pads: Array[Dictionary] = []
var _touch_pad := {}          # индекс пальца → имя площадки
var _touch_pos := {}          # индекс пальца → последняя точка
var _font_size := 18


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Площадки сами решают, чьё касание: остальной экран остаётся камере и интерфейсу.
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_layout)
	_layout()


func set_drive_mode(on: bool) -> void:
	drive_mode = on
	_release_all()
	_layout()


# Площадки раскладываем от краёв экрана, размер — от его высоты.
func _layout() -> void:
	var vs := get_viewport_rect().size
	# Ряд кнопок занимает по ширине около 10 u (руль слева, педали и стартер справа):
	# на узком экране (планшет 4:3) уменьшаем кнопки, чтобы они не наезжали друг на друга.
	var u := clampf(minf(vs.y / 7.0, vs.x / 10.4), 40.0, 140.0)
	var m := u * 0.2
	# Вырез камеры и скруглённые углы: кнопки держим внутри безопасной зоны экрана.
	var left := m
	var right := m
	var win := Vector2(DisplayServer.window_get_size())
	if OS.has_feature("mobile") and win.x > 0.0:
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var k := vs.x / win.x
		left = maxf(m, safe.position.x * k)
		right = maxf(m, (win.x - safe.end.x) * k)
	_pads.clear()
	var bottom := vs.y - m
	if drive_mode:
		# Руль — широкая полоса слева: чем дальше палец от центра, тем круче поворот.
		_add("steer", Rect2(left, bottom - u * 1.3, u * 3.6, u * 1.3), "◀  РУЛЬ  ▶", Color(0.35, 0.45, 0.6))
		_add("clutch", Rect2(left, bottom - u * 2.5, u * 1.7, u * 1.0), "СЦЕП", Color(0.45, 0.45, 0.5))
		_add("handbrake", Rect2(left + u * 1.9, bottom - u * 2.5, u * 1.7, u * 1.0), "РУЧН", Color(0.55, 0.4, 0.3))
		var rx := vs.x - right
		# Педали рядом и одной высоты, как в машине; передачи — строкой над ними.
		_add("throttle", Rect2(rx - u * 1.3, bottom - u * 2.6, u * 1.3, u * 2.6), "ГАЗ", Color(0.3, 0.6, 0.35))
		_add("brake", Rect2(rx - u * 2.8, bottom - u * 2.6, u * 1.3, u * 2.6), "ТОРМ", Color(0.65, 0.3, 0.3))
		_add("gear_up", Rect2(rx - u * 1.3, bottom - u * 3.7, u * 1.3, u * 0.9), "▲ ПЕР", Color(0.4, 0.4, 0.55))
		_add("gear_down", Rect2(rx - u * 2.8, bottom - u * 3.7, u * 1.3, u * 0.9), "▼ ПЕР", Color(0.4, 0.4, 0.55))
		_add("crank", Rect2(rx - u * 4.3, bottom - u * 1.0, u * 1.3, u * 1.0), "СТАРТ", Color(0.7, 0.55, 0.2))
		_add("horn", Rect2(rx - u * 4.3, bottom - u * 2.0, u * 1.3, u * 0.9), "СИГН", Color(0.4, 0.4, 0.45))
		_add("camera", Rect2(left + u * 3.8, bottom - u * 0.8, u * 1.1, u * 0.8), "КАМ", Color(0.3, 0.35, 0.4))
		_add("lights", Rect2(left + u * 3.8, bottom - u * 1.7, u * 1.1, u * 0.8), "ФАРЫ", Color(0.3, 0.35, 0.4))
	else:
		# На стенде нужны только стартер и газ, остальное — во вкладках.
		_add("crank", Rect2(left, bottom - u * 1.0, u * 1.6, u * 1.0), "СТАРТЕР", Color(0.7, 0.55, 0.2))
		_add("ignition", Rect2(left + u * 1.8, bottom - u * 1.0, u * 1.6, u * 1.0), "ЗАЖИГ", Color(0.4, 0.4, 0.5))
		_add("throttle", Rect2(left + u * 3.6, bottom - u * 1.8, u * 1.0, u * 1.8), "ГАЗ", Color(0.3, 0.6, 0.35))
	_font_size = int(clampf(u * 0.24, 14.0, 30.0))
	queue_redraw()


func _add(id: String, r: Rect2, text: String, c: Color) -> void:
	_pads.append({"id": id, "rect": r, "text": text, "color": c})


func _pad_at(p: Vector2) -> String:
	for pad in _pads:
		if (pad["rect"] as Rect2).has_point(p):
			return pad["id"]
	return ""


func is_over_pad(p: Vector2) -> bool:
	return visible and _pad_at(p) != ""


# Мышь, эмулированная из касания, проходит сквозь пустые места к камере и деталям.
func _has_point(p: Vector2) -> bool:
	return _pad_at(p) != "" and not (blocked.is_valid() and blocked.call(p))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var id := _pad_at(t.position)
			if id == "" or (blocked.is_valid() and blocked.call(t.position)):
				return
			_touch_pad[t.index] = id
			_touch_pos[t.index] = t.position
			_press(id, true)
			get_viewport().set_input_as_handled()
		elif _touch_pad.has(t.index):
			var id: String = _touch_pad[t.index]
			_touch_pad.erase(t.index)
			_touch_pos.erase(t.index)
			# Двумя пальцами на одной кнопке: отпускаем, только когда снят последний.
			if not (id in _touch_pad.values()):
				_press(id, false)
			get_viewport().set_input_as_handled()
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if not _touch_pad.has(d.index):
			return
		_touch_pos[d.index] = d.position
		_update_analog()
		get_viewport().set_input_as_handled()
		queue_redraw()


func _press(id: String, on: bool) -> void:
	match id:
		"brake":
			brake = on
		"clutch":
			clutch = on
		"handbrake":
			handbrake = on
		"horn":
			horn = on
		"crank":
			crank.emit(on)
		"gear_up":
			if on:
				gear_step.emit(1)
		"gear_down":
			if on:
				gear_step.emit(-1)
		"camera", "lights", "ignition":
			if on:
				action.emit(id)
	_update_analog()


# Газ — по высоте пальца на площадке (внизу чуть-чуть, вверху в пол), руль — по смещению от центра.
func _update_analog() -> void:
	throttle = 0.0
	steer = 0.0
	for idx in _touch_pad:
		var id: String = _touch_pad[idx]
		var r := _rect(id)
		var p: Vector2 = _touch_pos[idx]
		if id == "throttle":
			throttle = maxf(throttle, clampf(1.15 - (p.y - r.position.y) / r.size.y, 0.25, 1.0))
		elif id == "steer":
			var x := clampf((p.x - r.get_center().x) / (r.size.x * 0.42), -1.0, 1.0)
			steer = signf(x) * pow(absf(x), 1.4)


func _rect(id: String) -> Rect2:
	for pad in _pads:
		if pad["id"] == id:
			return pad["rect"]
	return Rect2()


func _release_all() -> void:
	for idx in _touch_pad.keys():
		_press(_touch_pad[idx], false)
	_touch_pad.clear()
	_touch_pos.clear()
	throttle = 0.0
	steer = 0.0


func _notification(what: int) -> void:
	# Свернули приложение посреди газа — педали не должны залипнуть.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_release_all()
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var active := {}
	for idx in _touch_pad:
		active[_touch_pad[idx]] = true
	for pad in _pads:
		var r: Rect2 = pad["rect"]
		var c: Color = pad["color"]
		var on: bool = active.has(pad["id"])
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c, 0.75 if on else 0.32)
		sb.border_color = Color(c.lightened(0.4), 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(r.size.y * 0.18))
		draw_style_box(sb, r)
		# Подписи одного кегля; длинная подпись ужимается под ширину кнопки.
		var fs := _font_size
		var ts := font.get_string_size(pad["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		if ts.x > r.size.x * 0.88:
			fs = int(fs * r.size.x * 0.88 / ts.x)
			ts = font.get_string_size(pad["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, Vector2(r.position.x + (r.size.x - ts.x) * 0.5, r.get_center().y + fs * 0.35), pad["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.92))
	if drive_mode:
		var sr := _rect("steer")
		var cx := sr.get_center().x + steer * sr.size.x * 0.42
		draw_line(Vector2(cx, sr.position.y + 6), Vector2(cx, sr.end.y - 6), Color(1, 1, 1, 0.8), 3.0)
