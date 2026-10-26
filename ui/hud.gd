class_name Hud
extends Control

# Интерфейс: приборы, показания модели, вкладки управления, неисправностей,
# графиков и разборки. Логику кадра ведёт main.gd, сюда приходят готовые данные.

signal request_remove
signal request_install
signal request_disassemble_all
signal request_assemble_all
signal request_reset(temperature_c: float, ambient_c: float)
signal request_sweep
signal request_view(view_name: String)
signal request_crank_turn(delta_deg: float)
signal request_xray(enabled: bool)
signal request_drive(on: bool)
signal request_teleport(distance: float)
signal request_body_xray(on: bool)
signal request_lights(mode: int)
signal request_turn(side: int)       # -1 — левый, 1 — правый, 0 — выключить
signal request_hazard
signal request_daytime(index: int)
signal request_opening(name: String)
signal request_quality(index: int)
signal request_engine(id: String)
signal request_gearbox(id: String, final_drive: float)
signal request_camera(mode: int)
signal request_garage(param: String, value: Variant)

var sim: EngineSim
var model: EngineModel

var tacho: Gauge
var g_coolant: Gauge
var g_oil: Gauge
var g_volt: Gauge
var g_vacuum: Gauge
var g_speed: Gauge
var info: RichTextLabel
var log_label: RichTextLabel
var message_label: Label
var tabs: TabContainer
var graph_p: Graph
var graph_pv: Graph
var graph_lift: Graph
var graph_dyno: Graph
var cyl_table: RichTextLabel
var part_title: Label
var part_body: RichTextLabel
var btn_remove: Button
var btn_install: Button
var removed_list: ItemList
var pedal_slider: HSlider
var choke_slider: HSlider
var time_slider: HSlider
var key_buttons: Array[Button] = []
var gear_buttons: Array[Button] = []
var load_mode: OptionButton
var dyno_box: VBoxContainer
var car_box: VBoxContainer
var clutch_slider: HSlider
var sweep_button: Button
var help_label: Label
var drive_button: Button
var drive_info: RichTextLabel
var graph_susp: Graph
var drive_mode := false
var auto_clutch_check: CheckBox
var follow_check: CheckBox
var lights_option: OptionButton
var _view_buttons: Array[Button] = []

var gauge_row: HBoxContainer
var info_panel: PanelContainer
var toolbar: HBoxContainer

var time_scale := 1.0
var hand_throttle := 0.0
var faults := {}
var ui_scale := 1.0
var _msg_time := 0.0
# Значения по умолчанию для сброса разделов: имя вкладки -> [[элемент, значение], ...]
var _defaults := {}
var _current_tab := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_gauges()
	_build_info()
	_build_tabs()
	_build_help()
	_build_toolbar()
	_no_keyboard_focus(self)
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	get_viewport().size_changed.connect(_layout)
	_layout()


# Кнопки и ползунки не забирают клавиатуру: иначе пробел (стартер) повторно жмёт
# последнюю нажатую кнопку, а W/S/стрелки двигают ползунки вместо газа и тормоза.
func _no_keyboard_focus(n: Node) -> void:
	for c in n.get_children():
		if c is BaseButton or c is Slider or c is ItemList or c is ScrollContainer:
			(c as Control).focus_mode = Control.FOCUS_NONE
		_no_keyboard_focus(c)


# Раскладка под размер окна: панели сжимаются на узких экранах,
# на совсем узких показания прячутся (их можно вернуть кнопкой).
func _layout() -> void:
	var vs := get_viewport_rect().size
	var tab_w := clampf(vs.x * 0.27, 330.0, 470.0)
	tabs.offset_left = -tab_w - 10.0
	var free_w := vs.x - tab_w - 30.0
	var gauge_k := clampf(minf(free_w / 600.0, vs.y / 900.0), 0.6, 1.25)
	tacho.custom_minimum_size = Vector2(210, 210) * gauge_k
	for g in [g_coolant, g_oil, g_volt, g_vacuum, g_speed]:
		(g as Control).custom_minimum_size = Vector2(118, 118) * gauge_k
	gauge_row.reset_size()
	var info_w := clampf(free_w - 20.0, 300.0, 470.0)
	info.custom_minimum_size.x = info_w - 16.0
	message_label.custom_minimum_size.x = info_w - 16.0
	info_panel.custom_minimum_size.x = info_w
	info_panel.position = Vector2(10, gauge_row.position.y + (maxf(210.0, 118.0 * 2.0 + 4.0) * gauge_k + 8.0 if gauge_row.visible else 0.0))
	info_panel.reset_size()
	toolbar.position = Vector2(vs.x - tab_w - 20.0 - toolbar.size.x, 10)
	if free_w < 330.0 and info_panel.visible:
		info_panel.visible = false
	help_label.visible = vs.x > 1100.0


func _build_toolbar() -> void:
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	add_child(toolbar)
	var t_panel := _toggle(toolbar, "Панель", true, func(on: bool) -> void: tabs.visible = on)
	t_panel.tooltip_text = "Показать/скрыть вкладки справа (Tab)"
	_toggle(toolbar, "Приборы", true, func(on: bool) -> void:
		gauge_row.visible = on
		_layout()
	)
	_toggle(toolbar, "Показания", true, func(on: bool) -> void: info_panel.visible = on)
	var minus := _button(toolbar, "A−", func() -> void: set_ui_scale(ui_scale - 0.1))
	minus.tooltip_text = "Уменьшить интерфейс"
	var plus := _button(toolbar, "A+", func() -> void: set_ui_scale(ui_scale + 0.1))
	plus.tooltip_text = "Увеличить интерфейс"
	toolbar.reset_size()


func _toggle(parent: Control, text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.toggled.connect(cb)
	parent.add_child(b)
	return b


func set_ui_scale(k: float) -> void:
	ui_scale = clampf(k, 0.6, 1.8)
	get_window().content_scale_factor = ui_scale
	show_message("Масштаб интерфейса: %.0f %%" % (ui_scale * 100.0))
	_layout.call_deferred()


func toggle_panel() -> void:
	tabs.visible = not tabs.visible
	(toolbar.get_child(0) as Button).button_pressed = tabs.visible


func _register(ctrl: Control, value: Variant) -> void:
	if _current_tab == "":
		return
	_defaults[_current_tab].append([ctrl, value])


func _add_reset(parent: Control, title: String, extra := Callable()) -> void:
	var b := _button(parent, "↺ Сбросить раздел «%s»" % title, func() -> void:
		for pair in _defaults[title]:
			var ctrl: Control = pair[0]
			if ctrl is HSlider:
				(ctrl as HSlider).value = pair[1]
			elif ctrl is CheckBox:
				(ctrl as CheckBox).button_pressed = pair[1]
			elif ctrl is OptionButton:
				var ob := ctrl as OptionButton
				ob.select(pair[1])
				ob.item_selected.emit(pair[1])
		if extra.is_valid():
			extra.call()
		show_message("Раздел «%s» сброшен к заводским значениям" % title)
	)
	b.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.05, 0.07, 0.86)
	panel.border_color = Color(0.25, 0.3, 0.36, 0.8)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_color("font_color", "Label", Color(0.86, 0.9, 0.94))
	t.set_color("font_color", "CheckBox", Color(0.86, 0.9, 0.94))
	t.set_font_size("font_size", "TabContainer", 12)
	t.set_constant("side_margin", "TabContainer", 0)
	return t


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	parent.add_child(p)
	return p


func _build_gauges() -> void:
	var row := HBoxContainer.new()
	gauge_row = row
	row.position = Vector2(10, 10)
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	tacho = Gauge.new("ТАХОМЕТР", "об/мин", 0, 8000, 1000)
	tacho.custom_minimum_size = Vector2(210, 210)
	tacho.red_from = 6000
	tacho.yellow_from = 5600
	tacho.label_scale = 0.9
	row.add_child(tacho)
	var col := GridContainer.new()
	col.columns = 3
	row.add_child(col)
	g_coolant = Gauge.new("ОЖ", "°C", 40, 130, 20)
	g_coolant.red_from = 112
	g_coolant.yellow_from = 100
	g_oil = Gauge.new("МАСЛО", "бар", 0, 6, 1)
	g_oil.decimals = 1
	g_oil.warn_lamp = "давл."
	g_volt = Gauge.new("СЕТЬ", "В", 8, 16, 2)
	g_volt.decimals = 1
	g_volt.warn_lamp = "заряд"
	g_vacuum = Gauge.new("РАЗРЕЖЕНИЕ", "кПа", 0, 100, 20)
	g_speed = Gauge.new("СКОРОСТЬ", "км/ч", 0, 180, 20)
	for g in [g_coolant, g_oil, g_volt, g_vacuum, g_speed]:
		g.custom_minimum_size = Vector2(118, 118)
		g.label_scale = 0.75
		col.add_child(g)


func _build_info() -> void:
	var p := _panel(self)
	info_panel = p
	p.position = Vector2(10, 232)
	p.custom_minimum_size = Vector2(430, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.custom_minimum_size = Vector2(414, 0)
	v.add_child(info)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	v.add_child(log_label)
	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	message_label.custom_minimum_size = Vector2(414, 0)
	v.add_child(message_label)


func show_message(text: String) -> void:
	message_label.text = text
	_msg_time = 5.0


func _build_help() -> void:
	help_label = Label.new()
	help_label.text = "ЛКМ — выбрать деталь · двойной щелчок — снять/поставить · ПКМ — вращать · Shift+ПКМ/СКМ — сдвиг · колесо — масштаб\nW/↑ — газ · Пробел — стартер · I — зажигание · C — подсос · X — рентген · 1–6 — ракурсы · Del/Ins — снять/поставить · [ ] — провернуть вал"
	help_label.add_theme_font_size_override("font_size", 11)
	help_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.85))
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.position = Vector2(12, -44)
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_top = -40
	help_label.offset_bottom = -6
	add_child(help_label)


# --- Вкладки ---------------------------------------------------------------

func _build_tabs() -> void:
	tabs = TabContainer.new()
	tabs.anchor_left = 1.0
	tabs.anchor_right = 1.0
	tabs.anchor_bottom = 1.0
	tabs.offset_left = -420
	tabs.offset_right = -10
	tabs.offset_top = 10
	tabs.offset_bottom = -10
	add_child(tabs)
	_tab_engine()
	_tab_drive()
	_tab_load()
	_tab_faults()
	_tab_graphs()
	_tab_parts()


func _scroll_tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	_current_tab = title
	_defaults[title] = []
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	return v


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.62, 0.67, 0.72))
	l.custom_minimum_size = Vector2(370, 0)
	parent.add_child(l)
	return l


func _slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float, fmt: String, cb: Callable) -> HSlider:
	var box := VBoxContainer.new()
	parent.add_child(box)
	var l := Label.new()
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(360, 18)
	box.add_child(s)
	# Доли 0..1 в процентных подписях показываем как проценты.
	var k := 100.0 if fmt.ends_with("%%") and hi <= 1.0 else 1.0
	var upd := func(v: float) -> void:
		l.text = label + ": " + (fmt % (v * k))
		cb.call(v)
	s.value_changed.connect(upd)
	l.text = label + ": " + (fmt % (value * k))
	_register(s, value)
	return s


func _check(parent: Control, label: String, value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = value
	c.toggled.connect(cb)
	parent.add_child(c)
	_register(c, value)
	return c


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	return h


func _tab_engine() -> void:
	var v := _scroll_tab("Мотор")
	_header(v, "Замок зажигания")
	var r := _row(v)
	for k in 3:
		var names := ["Выкл", "Зажигание", "Стартер"]
		var b := Button.new()
		b.text = names[k]
		b.toggle_mode = k < 2
		b.custom_minimum_size = Vector2(110, 30)
		r.add_child(b)
		key_buttons.append(b)
		if k < 2:
			var kk := k
			b.pressed.connect(func() -> void: sim.electrical.key = kk)
		else:
			b.button_down.connect(func() -> void: start_cranking())
			b.button_up.connect(func() -> void: stop_cranking())
	_note(v, "Стартер крутит, пока кнопка (или пробел) удерживается. Холодный двигатель заводится с подсосом.")
	_header(v, "Двигатель и коробка")
	var eo := OptionButton.new()
	var ids := EngineSpecs.ENGINES.keys()
	for id in ids:
		eo.add_item(EngineSpecs.ENGINES[id]["title"])
	eo.select(ids.find(EngineSpecs.engine_id))
	eo.item_selected.connect(func(i: int) -> void: request_engine.emit(ids[i]))
	eo.custom_minimum_size = Vector2(360, 0)
	v.add_child(eo)
	_register(eo, ids.find("2103"))
	var gr := _row(v)
	var go := OptionButton.new()
	var gids := EngineSpecs.GEARBOXES.keys()
	for id in gids:
		go.add_item(EngineSpecs.GEARBOXES[id]["title"])
	gr.add_child(go)
	_register(go, 0)
	var fo := OptionButton.new()
	for fd in EngineSpecs.FINAL_DRIVES:
		fo.add_item("ГП %.2f" % fd)
	gr.add_child(fo)
	_register(fo, 0)
	var send_box := func(_i: int) -> void:
		request_gearbox.emit(gids[go.selected], EngineSpecs.FINAL_DRIVES[fo.selected])
	go.item_selected.connect(send_box)
	fo.item_selected.connect(send_box)
	_note(v, "Все моторы — семейство «классики» с цепным ГРМ: разбираются одинаково, ломаются по-своему. Менять двигатель и коробку можно на заглушённом моторе. Главная пара: 3,9 — «шестёрка», 4,1 — 2105/2107, 4,3 — 2101/2103, 4,44 — «Нива».")
	_header(v, "Органы управления")
	pedal_slider = _slider(v, "Ручной газ (педаль)", 0.0, 1.0, 0.01, 0.0, "%.2f", func(x: float) -> void: hand_throttle = x)
	choke_slider = _slider(v, "Подсос (воздушная заслонка)", 0.0, 1.0, 0.01, 0.0, "%.2f", func(x: float) -> void: sim.carb.choke = x)
	_header(v, "Тепловое состояние")
	var r2 := _row(v)
	_button(r2, "Прогретый", func() -> void: request_reset.emit(90.0, 20.0))
	_button(r2, "Холодный +20 °C", func() -> void: request_reset.emit(20.0, 20.0))
	_button(r2, "Мороз −20 °C", func() -> void: request_reset.emit(-20.0, -20.0))
	_slider(v, "Ускорение тепловых процессов", 1.0, 60.0, 1.0, 1.0, "×%.0f", func(x: float) -> void: sim.thermal.heat_speedup = x)
	_note(v, "Прогрев от +20 °C на холостом ходу занимает около 10–15 минут; ускорение сокращает ожидание, не меняя механику.")
	_header(v, "Время")
	time_slider = _slider(v, "Скорость времени", 0.01, 1.0, 0.01, 1.0, "×%.2f", func(x: float) -> void: time_scale = x)
	_note(v, "Замедление до ×0,01 позволяет рассмотреть каждый такт: открытие клапанов, искру и фронт пламени.")
	_header(v, "Регулировки")
	_slider(v, "Установка зажигания (поворот трамблёра)", -6.0, 16.0, 0.5, EngineSpecs.IGNITION_INITIAL_DEG, "%.1f° до ВМТ", func(x: float) -> void: sim.ignition.initial_advance_deg = x)
	_slider(v, "Винт количества смеси (обороты ХХ)", 0.5, 1.8, 0.01, 1.0, "%.2f", func(x: float) -> void: sim.carb.idle_speed_screw = x)
	_slider(v, "Винт качества смеси (состав на ХХ)", 0.4, 1.6, 0.01, 1.0, "%.2f", func(x: float) -> void: sim.carb.idle_mixture_screw = x)
	_slider(v, "Тепловой зазор клапанов (сверх 0,15 мм)", 0.0, 0.4, 0.01, 0.0, "+%.2f мм", func(x: float) -> void: sim.valve_clearance_extra = x * 0.001)
	_slider(v, "Угол замкнутого состояния контактов", 40.0, 70.0, 1.0, 55.0, "%.0f°", func(x: float) -> void: sim.ignition.dwell_fraction = x / 90.0)
	var oct := OptionButton.new()
	for item in ["А-76", "АИ-92", "АИ-95", "АИ-98"]:
		oct.add_item(item)
	oct.select(1)
	oct.item_selected.connect(func(i: int) -> void: sim.fuel_octane = [76.0, 92.0, 95.0, 98.0][i])
	_register(oct, 1)
	var r3 := _row(v)
	var ol := Label.new()
	ol.text = "Бензин:"
	r3.add_child(ol)
	r3.add_child(oct)
	_header(v, "Вид")
	_check(v, "Рентген (полупрозрачные корпуса)", false, func(on: bool) -> void: request_xray.emit(on))
	var views := GridContainer.new()
	views.columns = 2
	v.add_child(views)
	for vn in CameraRig.VIEWS.keys():
		var name: String = vn
		_view_buttons.append(_button(views, name, func() -> void: request_view.emit(name)))
	_add_reset(v, "Мотор")


func _tab_load() -> void:
	var v := _scroll_tab("Нагрузка")
	_header(v, "Режим")
	load_mode = OptionButton.new()
	for item in ["Без нагрузки (нейтраль)", "Тормозной стенд", "Автомобиль ВАЗ-2106"]:
		load_mode.add_item(item)
	load_mode.item_selected.connect(func(i: int) -> void:
		sim.drivetrain.mode = i
		dyno_box.visible = i == 1
		car_box.visible = i == 2
	)
	v.add_child(load_mode)
	_register(load_mode, 0)
	dyno_box = VBoxContainer.new()
	v.add_child(dyno_box)
	dyno_box.visible = false
	_slider(dyno_box, "Тормозной момент", 0.0, 140.0, 1.0, 0.0, "%.0f Н·м", func(x: float) -> void: sim.drivetrain.dyno_torque = x)
	_check(dyno_box, "Удерживать обороты (балансирная машина)", false, func(on: bool) -> void: sim.drivetrain.dyno_hold_rpm = on)
	_slider(dyno_box, "Заданные обороты", 800.0, 6500.0, 50.0, 3000.0, "%.0f об/мин", func(x: float) -> void: sim.drivetrain.dyno_target_rpm = x)
	sweep_button = _button(dyno_box, "Снять внешнюю скоростную характеристику", func() -> void: request_sweep.emit())
	_note(dyno_box, "Полный дроссель, стенд проходит обороты от 1000 до 6000 и замеряет эффективный момент и мощность. Пунктир — паспорт выбранного двигателя.")
	graph_dyno = Graph.new()
	graph_dyno.title = "Внешняя характеристика"
	graph_dyno.x_min = 800
	graph_dyno.x_max = 6200
	graph_dyno.y_min = 0
	graph_dyno.y_max = 130
	graph_dyno.y_step = 20
	graph_dyno.x_ticks = [1000, 2000, 3000, 4000, 5000, 6000]
	graph_dyno.x_label = "об/мин"
	graph_dyno.y_label = "Н·м / кВт"
	graph_dyno.custom_minimum_size = Vector2(380, 220)
	dyno_box.add_child(graph_dyno)
	car_box = VBoxContainer.new()
	v.add_child(car_box)
	car_box.visible = false
	var gr := _row(car_box)
	for k in 7:
		var b := Button.new()
		b.text = ["R", "N", "1", "2", "3", "4", "5"][k]
		b.visible = k < EngineSpecs.GEAR_NAMES.size()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(52, 30)
		var kk := k
		b.pressed.connect(func() -> void: set_gear(kk))
		gr.add_child(b)
		gear_buttons.append(b)
	clutch_slider = _slider(car_box, "Сцепление (1 — отпущено)", 0.0, 1.0, 0.01, 1.0, "%.2f", func(x: float) -> void: sim.drivetrain.clutch = x)
	_slider(car_box, "Тормоз", 0.0, 1.0, 0.01, 0.0, "%.2f", func(x: float) -> void: sim.drivetrain.brake = x)
	_slider(car_box, "Уклон дороги", -10.0, 15.0, 0.5, 0.0, "%.1f %%", func(x: float) -> void: sim.drivetrain.slope = atan(x / 100.0))
	_check(car_box, "Включить фары (нагрузка на генератор)", false, func(on: bool) -> void: sim.electrical.headlights = on)
	_note(car_box, "Передаточные числа КПП: 3,667 / 2,10 / 1,361 / 1,0, главная пара 3,9. Q/E — передача вниз/вверх, Shift — выжать сцепление, B — тормоз.")
	_add_reset(v, "Нагрузка", func() -> void:
		set_gear(1)
		sim.drivetrain.vehicle_speed = 0.0
	)


func _tab_drive() -> void:
	var v := _scroll_tab("Заезд")
	_header(v, "Автомобиль ВАЗ-2106 на испытательной трассе")
	drive_button = _button(v, "▶ Выехать на трассу", func() -> void: request_drive.emit(not drive_mode))
	drive_button.custom_minimum_size = Vector2(360, 34)
	_note(v, "W — газ · S — тормоз · A/D — руль · Shift — сцепление · Q/E — передача вниз/вверх (R, N, 1–4) · Ctrl — ручник · Пробел — стартер · V — камера свободно/за машиной · L — свет · [ ] — поворотники · H — аварийка · G — клаксон · K — камера (за машиной / из салона / кино)")
	auto_clutch_check = _check(v, "Автосцепление (выжимается при переключении и трогании)", true, func(on: bool) -> void: sim.drivetrain.vehicle.auto_clutch = on)
	follow_check = _check(v, "Камера заходит за машину", true, func(on: bool) -> void: request_view.emit("__follow_on" if on else "__follow_off"))
	_check(v, "Прозрачный кузов (видны двигатель, подвеска, кардан)", false, func(on: bool) -> void: request_body_xray.emit(on))
	_header(v, "Светотехника")
	var lr := _row(v)
	var ll := Label.new()
	ll.text = "Свет (L):"
	lr.add_child(ll)
	lights_option = OptionButton.new()
	for item in ["Выключен", "Габариты", "Ближний", "Дальний"]:
		lights_option.add_item(item)
	lights_option.item_selected.connect(func(i: int) -> void: request_lights.emit(i))
	lr.add_child(lights_option)
	_register(lights_option, 0)
	var tr := _row(v)
	_button(tr, "◀ Поворот ([)", func() -> void: request_turn.emit(-1))
	_button(tr, "Аварийка (H)", func() -> void: request_hazard.emit())
	_button(tr, "Поворот ▶ (])", func() -> void: request_turn.emit(1))
	var dr := _row(v)
	var dl := Label.new()
	dl.text = "Время суток:"
	dr.add_child(dl)
	var day := OptionButton.new()
	for item in ["День", "Вечер", "Ночь"]:
		day.add_item(item)
	day.item_selected.connect(func(i: int) -> void: request_daytime.emit(i))
	dr.add_child(day)
	_register(day, 0)
	var qr := _row(v)
	var ql := Label.new()
	ql.text = "Графика:"
	qr.add_child(ql)
	var q := OptionButton.new()
	for item in ["Кино (SSIL, объёмный туман, ГРИП)", "Высокая", "Быстрая"]:
		q.add_item(item)
	q.item_selected.connect(func(i: int) -> void: request_quality.emit(i))
	qr.add_child(q)
	_register(q, 0)
	var cr := _row(v)
	var cl := Label.new()
	cl.text = "Камера (K):"
	cr.add_child(cl)
	for pair in [[0, "За машиной"], [1, "Из салона"], [2, "Кино"]]:
		var m: int = pair[0]
		_button(cr, pair[1], func() -> void: request_camera.emit(m))
	_header(v, "Двери, капот, багажник")
	var orow := _row(v)
	_button(orow, "Капот", func() -> void: request_opening.emit("hood"))
	_button(orow, "Багажник", func() -> void: request_opening.emit("trunk"))
	var drow := _row(v)
	for pair in [["door_fl", "Дверь ЛП"], ["door_fr", "ПП"], ["door_rl", "ЛЗ"], ["door_rr", "ПЗ"]]:
		var nm: String = pair[0]
		_button(drow, pair[1], func() -> void: request_opening.emit(nm))
	_header(v, "Перейти к участку")
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	for z in Road.ZONES:
		var d: float = z[0]
		var b := _button(grid, z[2], func() -> void: request_teleport.emit(maxf(d - 25.0, 0.0)))
		b.tooltip_text = z[3]
		b.custom_minimum_size = Vector2(178, 0)
	_header(v, "Телеметрия")
	drive_info = RichTextLabel.new()
	drive_info.bbcode_enabled = true
	drive_info.fit_content = true
	drive_info.scroll_active = false
	drive_info.custom_minimum_size = Vector2(370, 0)
	v.add_child(drive_info)
	graph_susp = Graph.new()
	graph_susp.title = "Ход подвески за 6 с (+ сжатие)"
	graph_susp.x_min = -6.0
	graph_susp.x_max = 0.0
	graph_susp.y_min = -110
	graph_susp.y_max = 110
	graph_susp.y_step = 50
	graph_susp.x_ticks = [-6, -4, -2, 0]
	graph_susp.x_label = "с"
	graph_susp.y_label = "мм"
	graph_susp.custom_minimum_size = Vector2(370, 200)
	v.add_child(graph_susp)
	_tab_garage(v)
	_note(v, "Модель кузова: «LADA 2106», автор ivsxworx (sketchfab.com/ivsxworx), лицензия CC BY 4.0. Подвеска, трансмиссия и двигатель — собственная модель симулятора.")
	_add_reset(v, "Заезд")


# Заводские эмали ВАЗ и цвета-«народные» названия по каталогу.
const PAINTS := [
	["Апельсин (как на модели)", Color(0.78, 0.33, 0.05)],
	["Коррида", Color(0.58, 0.05, 0.05)],
	["Валентина (вишня)", Color(0.32, 0.05, 0.08)],
	["Белая ночь", Color(0.86, 0.85, 0.8)],
	["Снежная королева", Color(0.93, 0.93, 0.92)],
	["Адриатика", Color(0.12, 0.27, 0.45)],
	["Мурена", Color(0.06, 0.24, 0.26)],
	["Сафари", Color(0.72, 0.64, 0.45)],
	["Бежевый «Жасмин»", Color(0.85, 0.8, 0.62)],
	["Чёрный", Color(0.03, 0.03, 0.035)],
]


func _tab_garage(v: VBoxContainer) -> void:
	_header(v, "Гараж: окраска и настройка")
	var pr := _row(v)
	var pl := Label.new()
	pl.text = "Цвет:"
	pr.add_child(pl)
	var paint := OptionButton.new()
	for p in PAINTS:
		paint.add_item(p[0])
	paint.item_selected.connect(func(i: int) -> void: request_garage.emit("paint", i))
	pr.add_child(paint)
	_register(paint, 0)
	_check(v, "Металлик", false, func(on: bool) -> void: request_garage.emit("metallic", on))
	_slider(v, "Тонировка стёкол", 0.0, 1.0, 0.05, 0.0, "%.0f %%", func(x: float) -> void: request_garage.emit("tint", x))
	_slider(v, "Клиренс (− занижение, + лифт)", -60.0, 50.0, 5.0, 0.0, "%+.0f мм", func(x: float) -> void: request_garage.emit("ride_height", x / 1000.0))
	_slider(v, "Жёсткость пружин", 60.0, 180.0, 5.0, 100.0, "%.0f %%", func(x: float) -> void: request_garage.emit("springs", x / 100.0))
	_slider(v, "Амортизаторы", 40.0, 220.0, 5.0, 100.0, "%.0f %%", func(x: float) -> void: request_garage.emit("dampers", x / 100.0))
	_slider(v, "Передний стабилизатор", 0.0, 200.0, 5.0, 100.0, "%.0f %%", func(x: float) -> void: request_garage.emit("arb", x / 100.0))
	_slider(v, "Пассажиры и груз", 0.0, 400.0, 25.0, 75.0, "%.0f кг", func(x: float) -> void: request_garage.emit("cargo", x))
	_check(v, "Ограничивать угол руля по скорости (удобно с клавиатуры)", true, func(on: bool) -> void: request_garage.emit("steer_assist", on))
	_note(v, "Пружины подбираются под нагрузку так, чтобы клиренс сохранялся (как подбор пружин по классу). Жёсткость меняет частоту колебаний кузова, амортизаторы — их затухание.")


func refresh_drive(car: Car) -> void:
	if car == null or not drive_info.is_visible_in_tree():
		return
	var vd := car.vd
	var names := ["ЛП", "ПП", "ЛЗ", "ПЗ"]
	var t := "[b]Скорость[/b] %.0f км/ч · [b]передача[/b] %s · %.0f об/мин\n" % [car.speed_kmh(), vd.gear_name(), sim.rpm()]
	t += "Сцепление %.0f %% · проскальзывание %.0f об/мин · момент %.0f Н·м\n" % [vd.clutch_engagement() * 100.0, vd.clutch_slip * 60.0 / TAU, vd.clutch_torque]
	t += "Крен %.1f° · тангаж %.1f° · ускорения: продольное %.2f g, поперечное %.2f g, вертикальное %.2f g\n" % [car.roll_deg(), car.pitch_deg(), -car.accel_g.z, car.accel_g.x, car.accel_g.y]
	t += "[b]Колесо  нагрузка  ход    скольж.  увод[/b]\n"
	for i in 4:
		var travel := (Car.REST_LEN - car.susp_len[i]) * 1000.0
		var mark := " [color=#f55]отбойник![/color]" if car.bump_hit[i] > 0.5 else ("" if car.contact[i] else " [color=#fc3]в воздухе[/color]")
		t += "  %s     %5.0f Н   %+4.0f мм  %+4.0f %%   %+4.1f°%s\n" % [names[i], car.tire_force[i], travel, vd.slip[i] * 100.0, rad_to_deg(car.slip_angle[i]), mark]
	var d := -car.global_position.z
	var zi := Road.zone_at(d)
	t += "Участок: %s (%.0f м)\n" % [Road.ZONES[zi][2] if zi >= 0 else "площадка", d]
	if vd.grinding > 0.0 or vd.last_message != "":
		t += "[color=#fc6]%s[/color]" % vd.last_message
	drive_info.text = t
	var series := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	if car.history.size() > 1:
		var t_end: float = car.history[car.history.size() - 1][0]
		for h in car.history:
			for i in 4:
				series[i].append(Vector2(h[0] - t_end, -h[i + 1] * 1000.0))
	graph_susp.clear_series()
	var cols := [Color(1, 0.5, 0.2), Color(1, 0.85, 0.3), Color(0.3, 0.7, 1), Color(0.5, 1, 0.6)]
	for i in 4:
		graph_susp.add_series(series[i], cols[i], 1.5, names[i])
	graph_susp.queue_redraw()


func set_drive_mode_ui(on: bool) -> void:
	drive_mode = on
	drive_button.text = "■ Вернуть двигатель на стенд" if on else "▶ Выехать на трассу"
	g_speed.title = "СКОРОСТЬ"
	# На трассе нагрузку задаёт сама машина, а разбирают на стенде — эти вкладки блокируем.
	for t in tabs.get_tab_count():
		var title := tabs.get_tab_title(t)
		if title == "Нагрузка" or title == "Разборка":
			tabs.set_tab_disabled(t, on)
	for b in _view_buttons:
		b.disabled = on


func refresh_gear_buttons() -> void:
	for i in gear_buttons.size():
		gear_buttons[i].visible = i < EngineSpecs.GEAR_NAMES.size()
	tacho.red_from = EngineSpecs.REDLINE_RPM


func set_gear(k: int) -> void:
	sim.drivetrain.gear = k
	for i in gear_buttons.size():
		gear_buttons[i].button_pressed = i == k


func _tab_faults() -> void:
	var v := _scroll_tab("Поломки")
	_note(v, "Вносите неисправности и наблюдайте их проявления — так тренируют диагностику. Те же эффекты дают снятые детали: провод свечи, ремень, термостат…")
	_header(v, "Зажигание")
	for i in 4:
		var ii := i
		_check(v, "Пробит провод свечи %d-го цилиндра" % (i + 1), false, func(on: bool) -> void: faults["wire_%d" % ii] = on)
	_slider(v, "Зазор свечей", 0.4, 1.6, 0.05, 0.65, "%.2f мм", func(x: float) -> void:
		for i in 4:
			sim.ignition.plug_gap_mm[i] = x
	)
	_check(v, "Не работает вакуумный регулятор опережения", false, func(on: bool) -> void: sim.ignition.vacuum_unit_ok = not on)
	_check(v, "Заклинил центробежный регулятор", false, func(on: bool) -> void: sim.ignition.centrifugal_ok = not on)
	_header(v, "Питание")
	_slider(v, "Подсос воздуха мимо карбюратора", 0.0, 12.0, 0.1, 0.0, "%.1f мм²", func(x: float) -> void: sim.carb.vacuum_leak_area = x * 1e-6)
	_slider(v, "Засор жиклёра холостого хода", 0.0, 1.0, 0.05, 0.0, "%.0f %%", func(x: float) -> void: sim.carb.idle_jet_clog = x)
	_slider(v, "Засор главного жиклёра 1-й камеры", 0.0, 0.8, 0.05, 0.0, "%.0f %%", func(x: float) -> void: sim.carb.main_jet_clog = x)
	_slider(v, "Засор воздушного фильтра", 0.0, 1.0, 0.05, 0.0, "%.0f %%", func(x: float) -> void: faults["air_filter"] = x)
	_check(v, "Не работает ускорительный насос", false, func(on: bool) -> void: sim.carb.accel_pump_ok = not on)
	_check(v, "Кончился бензин", false, func(on: bool) -> void: faults["no_fuel"] = on)
	_slider(v, "Засор глушителя", 0.0, 0.9, 0.05, 0.0, "%.0f %%", func(x: float) -> void: sim.exhaust_clog = x)
	_header(v, "Механика")
	for i in 4:
		var ii := i
		_slider(v, "Износ колец %d-го цилиндра" % (i + 1), 0.0, 1.0, 0.05, 0.0, "%.0f %%", func(x: float) -> void: sim.cylinders[ii].ring_wear = x)
	_slider(v, "Прогар выпускного клапана 3-го цилиндра", 0.0, 1.0, 0.05, 0.0, "%.0f %%", func(x: float) -> void: sim.cylinders[2].valve_burnt = x)
	_header(v, "Охлаждение и смазка")
	var th := OptionButton.new()
	for item in ["Термостат исправен", "Термостат заклинил закрытым", "Термостат заклинил открытым"]:
		th.add_item(item)
	th.item_selected.connect(func(i: int) -> void: faults["thermostat"] = i)
	v.add_child(th)
	_register(th, 0)
	_slider(v, "Уровень охлаждающей жидкости", 0.1, 1.0, 0.05, 1.0, "%.0f %%", func(x: float) -> void: sim.thermal.coolant_level = x)
	_slider(v, "Уровень масла", 0.05, 1.0, 0.05, 1.0, "%.0f %%", func(x: float) -> void: sim.thermal.oil_level = x)
	_header(v, "Электрика")
	_slider(v, "Заряд аккумулятора", 0.05, 1.0, 0.05, 0.9, "%.0f %%", func(x: float) -> void: sim.electrical.soc = x)
	_check(v, "Неисправен генератор (диодный мост)", false, func(on: bool) -> void: faults["alternator"] = on)
	_check(v, "Ослаб ремень генератора (свистит при перегазовке и нагрузке)", false, func(on: bool) -> void: faults["belt_loose"] = on)
	_add_reset(v, "Поломки")
	_header(v, "Сброс повреждений")
	_button(v, "Отремонтировать двигатель (вкладыши, прокладка, поршни)", func() -> void:
		sim.bearing_damage = 0.0
		sim.head_gasket_damage = 0.0
		sim.seized = false
		sim.rod_failure = false
		sim.timing_broken = false
		for c in sim.cylinders:
			c.piston_damage = 0.0
			c.valve_burnt = 0.0
		sim.damage_log.clear()
		show_message("Двигатель отремонтирован")
	)


func _tab_graphs() -> void:
	var v := _scroll_tab("Графики")
	graph_p = Graph.new()
	graph_p.title = "Давление в 1-м цилиндре по углу поворота коленвала"
	graph_p.x_min = 0
	graph_p.x_max = 720
	graph_p.y_min = 0
	graph_p.y_max = 60
	graph_p.y_step = 10
	graph_p.x_ticks = [0, 180, 360, 540, 720]
	graph_p.x_label = "° п.к.в. (0 — ВМТ впуска)"
	graph_p.y_label = "бар"
	graph_p.markers = [{"x": 360.0, "color": Color(1, 0.6, 0.2, 0.6), "label": "ВМТ сжатия"}]
	v.add_child(graph_p)
	graph_pv = Graph.new()
	graph_pv.title = "Индикаторная диаграмма p–V (логарифмическая)"
	graph_pv.log_x = true
	graph_pv.x_min = 40
	graph_pv.x_max = 450
	graph_pv.y_min = -0.3
	graph_pv.y_max = 1.9
	graph_pv.y_step = 0.5
	graph_pv.x_ticks = [50, 100, 200, 400]
	graph_pv.x_label = "объём, см³"
	graph_pv.y_label = "lg p, бар"
	v.add_child(graph_pv)
	graph_lift = Graph.new()
	graph_lift.title = "Подъём клапанов 1-го цилиндра (фазы ГРМ)"
	graph_lift.x_min = 0
	graph_lift.x_max = 720
	graph_lift.y_min = 0
	graph_lift.y_max = 10
	graph_lift.y_step = 2
	graph_lift.x_ticks = [0, 180, 360, 540, 720]
	graph_lift.x_label = "° п.к.в."
	graph_lift.y_label = "мм"
	v.add_child(graph_lift)
	cyl_table = RichTextLabel.new()
	cyl_table.bbcode_enabled = true
	cyl_table.fit_content = true
	cyl_table.scroll_active = false
	cyl_table.custom_minimum_size = Vector2(380, 0)
	v.add_child(cyl_table)


func _tab_parts() -> void:
	var v := _scroll_tab("Разборка")
	part_title = Label.new()
	part_title.text = "Выберите деталь щелчком мыши"
	part_title.add_theme_font_size_override("font_size", 16)
	part_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	part_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	part_title.custom_minimum_size = Vector2(370, 0)
	v.add_child(part_title)
	part_body = RichTextLabel.new()
	part_body.bbcode_enabled = true
	part_body.fit_content = true
	part_body.scroll_active = false
	part_body.custom_minimum_size = Vector2(370, 0)
	v.add_child(part_body)
	var r := _row(v)
	btn_remove = _button(r, "Снять", func() -> void: request_remove.emit())
	btn_install = _button(r, "Установить", func() -> void: request_install.emit())
	var r2 := _row(v)
	_button(r2, "Разобрать полностью", func() -> void: request_disassemble_all.emit())
	_button(r2, "Собрать", func() -> void: request_assemble_all.emit())
	_header(v, "Провернуть коленвал вручную")
	var r3 := _row(v)
	_button(r3, "−90°", func() -> void: request_crank_turn.emit(-90.0))
	_button(r3, "−10°", func() -> void: request_crank_turn.emit(-10.0))
	_button(r3, "+10°", func() -> void: request_crank_turn.emit(10.0))
	_button(r3, "+90°", func() -> void: request_crank_turn.emit(90.0))
	_button(r3, "ВМТ 1-го", func() -> void: request_crank_turn.emit(INF))
	_note(v, "Ключом за болт шкива — на заглушённом двигателе. Видно, как ходят поршни, работают клапаны, совмещаются метки ГРМ.")
	_header(v, "Снятые детали")
	removed_list = ItemList.new()
	removed_list.custom_minimum_size = Vector2(370, 220)
	v.add_child(removed_list)


func start_cranking() -> void:
	sim.electrical.key = 2
	key_buttons[2].button_pressed = true


func stop_cranking() -> void:
	if sim.electrical.key == 2:
		sim.electrical.key = 1
	key_buttons[2].button_pressed = false


# --- Обновление показаний -------------------------------------------------

func refresh(dt: float, real_factor: float, running_ok: String) -> void:
	_msg_time -= dt
	if _msg_time <= 0.0:
		message_label.text = running_ok
	var r := sim.rpm_display
	tacho.set_value(r)
	g_coolant.set_value(sim.thermal.t_coolant - 273.15)
	g_oil.set_value(sim.thermal.oil_pressure / 1e5)
	g_oil.warn_on = sim.electrical.key >= 1 and sim.thermal.oil_pressure < 0.45e5
	g_volt.set_value(sim.electrical.voltage)
	g_volt.warn_on = sim.electrical.charge_lamp
	g_vacuum.set_value(maxf(sim.manifold_vacuum_kpa(), 0.0))
	g_speed.set_value(absf(sim.drivetrain.vehicle_speed) * 3.6)
	for k in 2:
		key_buttons[k].button_pressed = sim.electrical.key == k
	var t := ""
	t += "[b]Момент[/b] %5.1f Н·м   [b]Мощность[/b] %4.1f кВт (%3.0f л.с.)\n" % [sim.torque_avg, sim.power_avg / 1000.0, sim.power_avg / 735.5]
	t += "Расход топлива %.2f л/ч · удельный %s г/кВт·ч\n" % [sim.fuel_consumption_lph(), ("%.0f" % sim.bsfc()) if sim.bsfc() > 0.0 else "—"]
	if r > 100.0:
		t += "Воздух %.1f г/с · наполнение ηv %.2f · λ %.2f (AFR %.1f)\n" % [sim.air_mass_rate * 1000.0, sim.volumetric_efficiency, sim.lambda_avg, sim.lambda_avg * EngineSpecs.AFR_STOICH]
	else:
		t += "Воздух — · двигатель стоит\n"
	t += "Опережение %.1f° (нач. %.1f + центр. %.1f + вак. %.1f) · искра %.0f мДж\n" % [sim.ignition.advance_deg, sim.ignition.initial_advance_deg, sim.ignition.centrifugal_deg, sim.ignition.vacuum_deg, sim.ignition.spark_energy_mj]
	t += "Дроссели %.0f° / %.0f° · поплавковая камера %.0f %% · пленка %.2f г\n" % [sim.carb.primary_angle_deg, sim.carb.secondary_angle_deg, sim.carb.bowl_level * 100.0, sim.im_film * 1000.0]
	t += "Масло %.0f °C (%s) · выхлоп %.0f °C · термостат %.0f %%\n" % [sim.thermal.t_oil - 273.15, "редукционный открыт" if sim.thermal.oil_relief_open else "%.0f сСт" % sim.thermal.oil_viscosity(), sim.exhaust_temp - 273.15, sim.thermal.thermostat_open * 100.0]
	t += "Генератор %.0f А · АКБ %s%.0f А · заряд %.0f %% · стартер %.0f А\n" % [sim.electrical.alternator_current, "разряд " if sim.electrical.battery_current > 0 else "заряд ", absf(sim.electrical.battery_current), sim.electrical.soc * 100.0, sim.electrical.starter_current]
	var status := ""
	for c in sim.cylinders:
		var mark := "[color=#6f6]●[/color]"
		if c.last_misfire:
			mark = "[color=#f55]✕[/color]"
		elif c.last_knock > 0.02:
			mark = "[color=#fc3]![/color]"
		status += "%s%d " % [mark, c.index + 1]
	t += "Цилиндры: %s  (● вспышка, ✕ пропуск, ! детонация)\n" % status
	var factor_txt := "реальное время" if real_factor > 0.98 else "замедление ×%.2f" % real_factor
	t += "[color=#8aa]Время модели: %s[/color]" % factor_txt
	info.text = t
	var lg := ""
	if sim.bearing_damage > 0.01:
		lg += "[color=#f84]Износ вкладышей: %.0f %%[/color]\n" % (sim.bearing_damage * 100.0)
	if sim.head_gasket_damage > 0.01:
		lg += "[color=#f84]Прокладка ГБЦ: повреждена на %.0f %%[/color]\n" % (sim.head_gasket_damage * 100.0)
	var pd := 0.0
	for c in sim.cylinders:
		pd = maxf(pd, c.piston_damage)
	if pd > 0.01:
		lg += "[color=#f84]Прогар поршней от детонации: до %.0f %%[/color]\n" % (pd * 100.0)
	if sim.valve_float > 0.0:
		lg += "[color=#f84]Зависание клапанов — пружины не успевают![/color]\n"
	if sim.thermal.boiling:
		lg += "[color=#f44]Антифриз закипел![/color]\n"
	for s in sim.damage_log:
		lg += "[color=#f44]%s[/color]\n" % s
	log_label.text = lg


func refresh_graphs() -> void:
	if not graph_p.is_visible_in_tree():
		return
	var pts := PackedVector2Array()
	var pv := PackedVector2Array()
	for k in sim.view_pressure.size():
		var p := sim.view_pressure[k]
		if p <= 0.0:
			continue
		pts.append(Vector2(k * 720.0 / sim.view_pressure.size(), p / 1e5))
		pv.append(Vector2(sim.view_volume[k] * 1e6, log(p / 1e5) / log(10.0)))
	if pv.size() > 0:
		pv.append(pv[0])
	graph_p.clear_series()
	graph_p.add_series(pts, Color(1.0, 0.55, 0.2), 2.0)
	var peak := 10.0
	for p2 in pts:
		peak = maxf(peak, p2.y)
	graph_p.y_max = ceilf(peak / 10.0) * 10.0
	graph_p.queue_redraw()
	graph_pv.clear_series()
	graph_pv.add_series(pv, Color(0.4, 0.8, 1.0), 2.0)
	graph_pv.queue_redraw()
	var li := PackedVector2Array()
	var le := PackedVector2Array()
	for k in 361:
		var a := k * 2.0
		li.append(Vector2(a, sim.valve_lift(deg_to_rad(a), true) * 1000.0))
		le.append(Vector2(a, sim.valve_lift(deg_to_rad(a), false) * 1000.0))
	graph_lift.clear_series()
	graph_lift.add_series(le, Color(1.0, 0.4, 0.3), 2.0, "выпуск")
	graph_lift.add_series(li, Color(0.3, 0.7, 1.0), 2.0, "впуск")
	var spark := 360.0 - sim.ignition.advance_deg
	graph_lift.markers = [{"x": spark, "color": Color(1, 1, 0.4, 0.8), "label": "искра"}]
	graph_lift.queue_redraw()
	var tt := "[b]Цилиндр  λ     ост.газы  Pmax, бар  IMEP, бар[/b]\n"
	for c in sim.cylinders:
		tt += "   %d       %.2f   %.2f        %4.1f        %5.2f%s\n" % [c.index + 1, c.trapped_lambda, c.residual, c.peak_pressure / 1e5, c.imep / 1e5, "  пропуск" if c.last_misfire else ""]
	cyl_table.text = tt


func show_part(p: EnginePart, blockers: Array, missing: Array, can_remove: bool, can_install: bool) -> void:
	if p == null:
		part_title.text = "Выберите деталь щелчком мыши"
		part_body.text = ""
		btn_remove.disabled = true
		btn_install.disabled = true
		return
	part_title.text = p.title
	var t := "[color=#9ab]%s[/color]\n%s\n" % [p.group, p.description]
	if p.specs != "":
		t += "\n[color=#fc8]%s[/color]\n" % p.specs.replace("\n", "\n")
	t += "\n[b]Состояние:[/b] %s\n" % ("снята" if p.removed else ("стоит в снятом узле" if p.is_detached() else "установлена"))
	if not blockers.is_empty():
		var names := []
		for b in blockers:
			names.append(b.title)
		t += "[color=#f86]Сначала %s: %s[/color]\n" % ["поставьте на место" if p.removed else "снимите", ", ".join(names)]
	if p.removed and not missing.is_empty():
		var names2 := []
		for b in missing:
			names2.append(b.title)
		t += "[color=#f86]Не хватает деталей узла: %s[/color]\n" % ", ".join(names2)
	if not p.critical:
		t += "[color=#8c8]Без этой детали двигатель может работать.[/color]\n"
	part_body.text = t
	btn_remove.disabled = not can_remove
	btn_install.disabled = not can_install


func refresh_removed(model_ref: EngineModel) -> void:
	removed_list.clear()
	for p in model_ref.part_order:
		if p.removed:
			removed_list.add_item(p.title)
