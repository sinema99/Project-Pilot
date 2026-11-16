extends SceneTree

# Ray survey of hub2's map shell (docs/specs/hub2-final-pass.md): every walkable floor layer per 1 m
# cell, its headroom, and whether open sky is above it. Writes PNG plan images per height band
# (1 px = 1 m, x right, z down) plus a raw layer dump for later queries.
#   godot --headless --path . --script tools/survey_hub2_map.gd -- <out_dir>

const WORLD_SCALE := 0.6
const X0 := -210
const X1 := 210
const Z0 := -470
const Z1 := 150
const TOP := 200.0
const BOTTOM := -320.0
const BANDS := [["A", -320.0, -150.0], ["mid", -150.0, 45.0], ["high", 45.0, 140.0], ["roof", 140.0, 200.0]]

var _phys: Node3D
var _ss: PhysicsDirectSpaceState3D
var _frames := 0
var _out := ""


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	_phys = Node3D.new()
	var glb: Node3D = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	glb.scale = Vector3.ONE * WORLD_SCALE
	_phys.add_child(glb)
	root.add_child(_phys)


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.hit_back_faces = true
	return _ss.intersect_ray(q)


func _physics_process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_ss = _phys.get_world_3d().direct_space_state
	var w := X1 - X0
	var h := Z1 - Z0
	var imgs := {}
	for b: Array in BANDS:
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		img.fill(Color(0.08, 0.08, 0.09))
		imgs[b[0]] = img
	var dump := PackedStringArray()
	for z in range(Z0, Z1):
		for x in range(X0, X1):
			var y := TOP
			var guard := 0
			while y > BOTTOM and guard < 24:
				guard += 1
				var r := _ray(Vector3(x + 0.5, y, z + 0.5), Vector3(x + 0.5, BOTTOM, z + 0.5))
				if r.is_empty():
					break
				var p: Vector3 = r["position"]
				var n: Vector3 = r["normal"]
				if n.y > 0.7:
					# walkable surface: headroom up
					var up := _ray(p + Vector3.UP * 0.05, p + Vector3.UP * 400.0)
					var head := 400.0
					var sky := up.is_empty()
					if not sky:
						head = (up["position"] as Vector3).y - p.y
					if head > 1.0:
						dump.append("%d %d %.2f %.2f %d" % [x, z, p.y, head, 1 if sky else 0])
						for b: Array in BANDS:
							if p.y >= b[1] and p.y < b[2]:
								var t := clampf((p.y - b[1]) / (b[2] - b[1]), 0.0, 1.0)
								var c := Color.from_hsv(0.66 - 0.66 * t, 0.65, 0.35 + 0.6 * clampf(head / 60.0, 0.0, 1.0))
								if sky:
									c = Color(0.9, 0.9, 0.9).lerp(c, 0.4)
								(imgs[b[0]] as Image).set_pixel(x - X0, z - Z0, c)
				y = p.y - 0.3
	for k: String in imgs:
		var img: Image = imgs[k]
		for z in range(Z0, Z1):
			for x in range(X0, X1):
				if x % 50 == 0 or z % 50 == 0:
					var c := img.get_pixel(x - X0, z - Z0)
					img.set_pixel(x - X0, z - Z0, c.lerp(Color(1, 0.2, 0.2), 0.6 if (x == 0 or z == 0) else 0.35))
				elif x % 10 == 0 or z % 10 == 0:
					var c2 := img.get_pixel(x - X0, z - Z0)
					img.set_pixel(x - X0, z - Z0, c2.lerp(Color(0.5, 0.5, 0.5), 0.15))
		img.save_png("%s/plan_%s.png" % [_out, k])
	var f := FileAccess.open(_out + "/layers.txt", FileAccess.WRITE)
	f.store_string("\n".join(dump))
	f.close()
	print("survey: %d floor samples" % dump.size())
	return true
