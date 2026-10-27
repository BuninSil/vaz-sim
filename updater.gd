extends Node

# Обновления без переустановки. Раз за запуск смотрит манифест на GitHub:
#  - новый патч к этому же APK — тихо качает его в user://patch.pck, применится
#    при следующем запуске (boot.gd подключает его раньше остальных скриптов);
#  - новый APK (поменялся движок или тяжёлые модели) — предлагает скачать его.
#    Он подписан тем же ключом и ставится поверх, настройки и прогресс остаются.

var manifest_url := "https://github.com/BuninSil/vaz-sim/releases/download/android/version.json"
const DOWNLOAD := "user://patch_dl.pck"

var apk_build := 0
var build := 0

var _http: HTTPRequest
var _remote := {}
var _layer: CanvasLayer


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	add_child(_http)
	# Даём игре спокойно загрузиться, потом идём в сеть.
	await get_tree().create_timer(4.0).timeout
	_http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	if _http.request(manifest_url) != OK:
		queue_free()


func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	_remote = data
	var remote_apk := int(_remote.get("apk", 0))
	var remote_build := int(_remote.get("build", 0))
	if remote_apk > apk_build:
		_banner("Вышла новая версия приложения (сборка %d). Ставится поверх старой, ничего удалять не надо." % remote_build, "Скачать", func() -> void:
			OS.shell_open(str(_remote.get("apk_url", "")))
		)
	elif remote_apk == apk_build and remote_build > build and str(_remote.get("patch_url", "")) != "":
		_http.download_file = DOWNLOAD
		_http.request_completed.connect(_on_patch, CONNECT_ONE_SHOT)
		if _http.request(str(_remote["patch_url"])) != OK:
			_http.download_file = ""


func _on_patch(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_http.download_file = ""
	var want := str(_remote.get("patch_sha256", ""))
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or (want != "" and FileAccess.get_sha256(DOWNLOAD) != want):
		DirAccess.remove_absolute(DOWNLOAD)
		return
	DirAccess.rename_absolute(DOWNLOAD, "user://patch.pck")
	var f := FileAccess.open("user://patch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"build": int(_remote["build"]), "apk": apk_build}))
	f.close()
	var notes := str(_remote.get("notes", ""))
	_banner("Скачано обновление (сборка %d)%s. Перезапусти игру, чтобы применить." % [int(_remote["build"]), (": " + notes) if notes != "" else ""], "", Callable())


# Плашка сверху экрана поверх интерфейса игры.
func _banner(text: String, action: String, cb: Callable) -> void:
	if _layer != null:
		_layer.queue_free()
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 70
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.13, 0.95)
	sb.border_color = Color(1.0, 0.7, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(520, 0)
	label.add_theme_font_size_override("font_size", 22)
	row.add_child(label)
	if action != "":
		var b := Button.new()
		b.text = action
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(cb)
		row.add_child(b)
	var close := Button.new()
	close.text = "✕"
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(func() -> void: _layer.queue_free())
	row.add_child(close)
	# Центруем по ширине после раскладки.
	panel.resized.connect(func() -> void: panel.position.x = (panel.get_viewport_rect().size.x - panel.size.x) * 0.5)
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
	)
