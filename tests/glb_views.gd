extends SceneTree

# Растровые виды модели в её сантиметрах (сбоку и сверху) с сеткой — для разметки дверей.
const PX := 3.0

func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://models/lada_2106.glb"), st)
	var scene := doc.generate_scene(st)
	var side := Image.create(int(420 * PX), int(160 * PX), false, Image.FORMAT_RGB8)
	var top := Image.create(int(420 * PX), int(190 * PX), false, Image.FORMAT_RGB8)
	side.fill(Color(1, 1, 1))
	top.fill(Color(1, 1, 1))
	var colors := {}
	var k := 0
	for n in scene.find_children("Object_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var col := Color.from_hsv(fmod(k * 0.137, 1.0), 0.7, 0.75)
		colors[mi.name] = col
		k += 1
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				var a := v[idx[t]]
				var b := v[idx[t + 1]]
				var c := v[idx[t + 2]]
				var nrm := (b - a).cross(c - a).normalized()
				var shade := col.darkened(0.5 * (1.0 - absf(nrm.x)))
				if (a.x + b.x + c.x) > 0.0 and absf(nrm.x) > 0.2:
					_tri(side, Vector2(a.y + 210, 120 - a.z), Vector2(b.y + 210, 120 - b.z), Vector2(c.y + 210, 120 - c.z), shade)
				if absf(nrm.z) > 0.3 and (a.z + b.z + c.z) > 0.0:
					_tri(top, Vector2(a.y + 210, a.x + 95), Vector2(b.y + 210, b.x + 95), Vector2(c.y + 210, c.x + 95), col.darkened(0.5 * (1.0 - absf(nrm.z))))
	for img in [side, top]:
		for gx in range(-210, 211, 10):
			var x := int((gx + 210) * PX)
			for y in img.get_height():
				if y % (2 if gx % 50 == 0 else 6) == 0:
					img.set_pixel(clampi(x, 0, img.get_width() - 1), y, Color(0, 0, 0) if gx % 50 == 0 else Color(0.5, 0.5, 0.5))
		for gy in range(0, int(img.get_height() / PX), 10):
			var y := int(gy * PX)
			for x in img.get_width():
				if x % (2 if gy % 50 == 0 else 6) == 0:
					img.set_pixel(x, y, Color(0, 0, 0) if gy % 50 == 0 else Color(0.5, 0.5, 0.5))
	side.save_png("res://screenshots/_glb_side.png")
	top.save_png("res://screenshots/_glb_top.png")
	for nm in colors:
		print(nm, " ", colors[nm].to_html(false))
	quit()

func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	a *= PX; b *= PX; c *= PX
	var mn := a.min(b).min(c).floor()
	var mx := a.max(b).max(c).ceil()
	for y in range(maxi(int(mn.y), 0), mini(int(mx.y), img.get_height() - 1) + 1):
		for x in range(maxi(int(mn.x), 0), mini(int(mx.x), img.get_width() - 1) + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := (b - a).cross(p - a)
			var d2 := (c - b).cross(p - b)
			var d3 := (a - c).cross(p - c)
			if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0):
				img.set_pixel(x, y, col)
