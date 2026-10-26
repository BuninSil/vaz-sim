extends SceneTree

# Обход машины камерой для поиска визуальных дефектов.
var f := 0
var main: Node
var cam: Camera3D
const VIEWS := [
	["70_audit_front", Vector3(0, 420, 60), Vector3(0, 0, 0), 40.0],
	["71_audit_front34", Vector3(-260, 330, 90), Vector3(0, 0, 0), 40.0],
	["72_audit_side", Vector3(-480, 0, 40), Vector3(0, 0, 0), 45.0],
	["73_audit_rear34", Vector3(260, -340, 90), Vector3(0, -20, 0), 40.0],
	["74_audit_rear", Vector3(0, -430, 50), Vector3(0, 0, 0), 40.0],
	["75_audit_top", Vector3(10, 0, 560), Vector3(0, 0, 0), 50.0],
	["76_audit_wheel_f", Vector3(-160, 190, -10), Vector3(-75, 142, -21), 40.0],
	["77_audit_wheel_r", Vector3(-160, -40, -10), Vector3(-75, -96, -23), 40.0],
	["78_audit_low", Vector3(-300, 150, -38), Vector3(0, 0, -20), 50.0],
	["79_audit_engine_bay", Vector3(-40, 260, 130), Vector3(0, 150, 0), 50.0],
]

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _pt(cm: Vector3) -> Vector3:
	var bm: CarBodyModel = main.car.body_model
	return bm.global_transform * (bm._model_xf * cm)

func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		main.set_drive_mode(true)
		main.hud.tabs.visible = false
		main.hud.info_panel.visible = false
		main.hud.gauge_row.visible = false
		main.hud.help_label.visible = false
	if f == 60:
		cam = Camera3D.new()
		cam.far = 800.0
		root.add_child(cam)
		cam.current = true
	if f >= 60:
		var i := (f - 60) / 25
		if i >= VIEWS.size():
			return true
		var v: Array = VIEWS[i]
		if i == 9 and (f - 60) % 25 == 0:
			main.hud.request_opening.emit("hood")
		cam.fov = v[3]
		cam.global_position = _pt(v[1])
		cam.look_at(_pt(v[2]), Vector3.UP)
		if (f - 60) % 25 == 24:
			root.get_texture().get_image().save_png("res://screenshots/%s.png" % v[0])
	return false
