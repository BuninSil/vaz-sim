extends SceneTree

# Сечения кузова: внутренний контур боковин, крыши и стёкол (см модели).
func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://models/lada_2106.glb"), st)
	var scene := doc.generate_scene(st)
	var pts := []   # [x, y, z, имя]
	for n in scene.find_children("Object_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.name in ["Object_29","Object_30","Object_31","Object_32","Object_33","Object_34","Object_35","Object_36"]:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var c := (v[idx[t]] + v[idx[t+1]] + v[idx[t+2]]) / 3.0
			pts.append([c.x, c.y, c.z, String(mi.name)])
	# Поперечное сечение y=30: наименьший |x| боковины по высоте.
	for ys in [30.0, -50.0]:
		var line := "сечение y=%d: " % ys
		for zb in range(-30, 80, 10):
			var mx := 0.0
			for p in pts:
				if absf(p[1] - ys) < 3.0 and p[2] >= zb and p[2] < zb + 10 and p[0] > 0.0:
					mx = maxf(mx, p[0])
			line += "z%d:%.0f " % [zb, mx]
		print(line)
	# Продольное сечение x≈0: верх (крыша, стёкла) и низ.
	var line2 := "x=0 верх/низ: "
	for yb in range(-200, 200, 15):
		var top := -99.0
		var bot := 999.0
		var names := {}
		for p in pts:
			if absf(p[0]) < 8.0 and p[1] >= yb and p[1] < yb + 15:
				top = maxf(top, p[2])
				bot = minf(bot, p[2])
				names[p[3]] = true
		line2 += "\ny%d: %.0f..%.0f %s" % [yb, bot, top, names.keys()]
	print(line2)
	quit()
