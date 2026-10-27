extends Node

# Загрузчик: до главной сцены подключает скачанное обновление (user://patch.pck),
# потом запускает проверку новых версий и саму игру. Сам загрузчик обновлением
# не меняется — он уже загружен из APK, поэтому держим его маленьким.

const PATCH := "user://patch.pck"
const PATCH_INFO := "user://patch.json"


func _ready() -> void:
	var base := read_version("res://version.json")
	var build := int(base.get("build", 0))
	var apk := int(base.get("apk", 0))
	var info := read_version(PATCH_INFO)
	if FileAccess.file_exists(PATCH) and int(info.get("apk", -1)) == apk and int(info.get("build", 0)) > build:
		if ProjectSettings.load_resource_pack(PATCH, true):
			build = int(info["build"])
		else:
			_drop_patch()
	elif FileAccess.file_exists(PATCH):
		# Патч к другому APK (или старее установленного) — не нужен.
		_drop_patch()
	# Обновления раздаются только для телефона: на компе игру запускают из редактора.
	if OS.has_feature("android"):
		var updater: Node = load("res://updater.gd").new()
		updater.name = "Updater"
		updater.set("apk_build", apk)
		updater.set("build", build)
		get_tree().root.add_child.call_deferred(updater)
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")


static func read_version(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text) if text != "" else null
	return data if data is Dictionary else {}


func _drop_patch() -> void:
	DirAccess.remove_absolute(PATCH)
	DirAccess.remove_absolute(PATCH_INFO)
