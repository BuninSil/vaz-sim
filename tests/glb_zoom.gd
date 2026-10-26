extends SceneTree

# Увеличенная боковая проекция участка (см модели) для поиска зазоров панелей.
const REGIONS := [["hood_front", 160.0, 200.0, -10.0, 70.0, true], ["hood_rear", 90.0, 130.0, -10.0, 70.0, true], ["hood_front_side", 160.0, 200.0, 10.0, 45.0, false]]
const PX := 10.0

func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://models/lada_2106.glb"), st)
	var scene := doc.generate_scene(st)
	for r in REGIONS:
		var y0: float = r[1]; var y1: float = r[2]; var z0: float = r[3]; var z1: float = r[4]
		var img := Image.create(int((y1 - y0) * PX), int((z1 - z0) * PX), false, Image.FORMAT_RGB8)
		img.fill(Color(1, 1, 1))
		for n in scene.find_children("Object_*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var arr := mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				var a := v[idx[t]]; var b := v[idx[t+1]]; var c := v[idx[t+2]]
				var top: bool = r.size() > 5 and r[5]
				if top:
					if (b - a).cross(c - a).normalized().z * signf(1.0) < 0.3 and absf((b - a).cross(c - a).normalized().z) < 0.3:
						continue
					if (a.z + b.z + c.z) / 3.0 < 15.0:
						continue
					a = Vector3(a.x, a.y, a.x); b = Vector3(b.x, b.y, b.x); c = Vector3(c.x, c.y, c.x)
				elif (a.x + b.x + c.x) / 3.0 < 50.0:
					continue
				var col := Color(0.7, 0.55, 0.2) if (t / 3) % 2 == 0 else Color(0.55, 0.42, 0.15)
				_tri(img, Vector2(a.y - y0, z1 - a.z), Vector2(b.y - y0, z1 - b.z), Vector2(c.y - y0, z1 - c.z), col)
		for g in range(int(y0), int(y1) + 1):
			if g % 5 == 0:
				for y in img.get_height():
					if y % 3 == 0: img.set_pixel(clampi(int((g - y0) * PX), 0, img.get_width() - 1), y, Color(0, 0, 1) if g % 10 == 0 else Color(0.4, 0.4, 1))
		for g in range(int(z0), int(z1) + 1):
			if g % 5 == 0:
				for x in img.get_width():
					if x % 3 == 0: img.set_pixel(x, clampi(int((z1 - g) * PX), 0, img.get_height() - 1), Color(1, 0, 0) if g % 10 == 0 else Color(1, 0.5, 0.5))
		img.save_png("res://screenshots/_zoom_%s.png" % r[0])
	quit()

func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	a *= PX; b *= PX; c *= PX
	var mn := a.min(b).min(c).floor()
	var mx := a.max(b).max(c).ceil()
	for y in range(maxi(int(mn.y), 0), mini(int(mx.y), img.get_height() - 1) + 1):
		for x in range(maxi(int(mn.x), 0), mini(int(mx.x), img.get_width() - 1) + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := (b - a).cross(p - a); var d2 := (c - b).cross(p - b); var d3 := (a - c).cross(p - c)
			if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0):
				img.set_pixel(x, y, col)
