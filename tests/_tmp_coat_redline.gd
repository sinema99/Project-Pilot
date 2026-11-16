extends SceneTree
# Throwaway: sets the coat probe's back camera (view 0) and reads the red line (user drawing,
# aligned scale 1.0079 +4,+6 onto the 640x900 crop) at each coat row: red x on screen -> model x
# on the plane z = row's side depth. Prints per row: screen y, red xs, model xs.
const RED := ""
var _f := 0
var _pilot: Node
var _cam: Camera3D
func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")
func _find(n: Node, out: Array) -> void:
	if n.has_method(&"toggle_coat"): out.append(n)
	for c in n.get_children(): _find(c, out)
func _process(_d: float) -> bool:
	_f += 1
	if _f < 120: return false
	if _pilot == null:
		var all := []; _find(current_scene, all); _pilot = all[0]
		_pilot.frozen = true
		_cam = Camera3D.new(); _cam.fov = 40.0; current_scene.add_child(_cam); _cam.current = true
		var p: Vector3 = _pilot.global_position
		var f: Vector3 = _pilot._facing().rotated(Vector3.UP, PI)
		_cam.global_position = p + f * 5.6 + Vector3.UP * 1.4
		_cam.look_at(p + Vector3.UP * 1.0, Vector3.UP)
		return false
	var skel: Skeleton3D = _pilot.coat.skeleton
	var red := Image.load_from_file(OS.get_cmdline_user_args()[0])
	var vs := Vector2(root.get_texture().get_image().get_size())
	var k := vs.y / root.get_visible_rect().size.y
	var off := Vector2((vs.x - 640) / 2, maxf((vs.y - 900) / 2, 0))
	print("viewport ", vs)
	var M = load("res://scripts/items/trench_coat_mesh.gd")
	var rows := {"top": [M.ROW_TOP_Y[2], M.ROW_TOP[2]], "arm": [M.ROW_ARM_Y, M.ROW_ARM[2]], "chest": [M.ROW_CHEST_Y, M.ROW_CHEST[2]], "waist": [M.ROW_WAIST_Y, M.ROW_WAIST[2]], "hip": [M.ROW_HIP_Y, M.ROW_HIP[2]], "knee": [M.ROW_KNEE_Y, M.ROW_KNEE[2]], "hem": [M.ROW_HEM_Y, M.ROW_HEM[2]]}
	for hy in [1.712, 1.69, 1.66, 1.62, 1.58, 1.55, 1.50, 1.45, 1.40, 1.34, 1.28, 1.22, 1.16, 1.12, 1.06, 1.00, 0.95, 0.88, 0.80, 0.72, 0.64, 0.55, 0.45, 0.38, 0.30]:
		var g := skel.global_transform
		var sp := _cam.unproject_position(g * Vector3(0, hy, 0)) * k - off
		var ry := int(round((sp.y - 6) / 1.0079))
		var xs := []
		for x in red.get_width():
			var c := red.get_pixel(x, ry)
			if c.r > 0.7 and c.g < 0.3 and c.b < 0.3: xs.append(x)
		# Model x of each red run on the z = 0 plane at that height.
		var mx := []
		var last := -10
		for x in xs:
			if x - last > 3:
				var sx: float = x * 1.0079 + 4 + off.x
				var pos = Plane(g.basis * Vector3(0, 0, 1), g * Vector3.ZERO).intersects_ray(_cam.project_ray_origin(Vector2(sx, sp.y + off.y) / k), _cam.project_ray_normal(Vector2(sx, sp.y + off.y) / k))
				mx.append("%.3f" % (g.affine_inverse() * pos).x)
			last = x
		print("y %.2f  screen %d  model x: %s" % [hy, int(sp.y), " ".join(mx)])
	return true
