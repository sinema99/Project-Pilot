extends SceneTree

# Throwaway probe, WINDOWED: boots Ichi.tscn, waits for the Storm's roof-map bake, then checks it
# against straight-down physics rays on a grid over the map (the highest collision hit should match
# the baked height), saves the map as a greyscale png and a shot of the game camera. See
# docs/specs/ichi-snowstorm.md, "Snow shelter". Run:
#   godot --path . --script tests/_probe_storm_shelter.gd -- <out_dir>

var _frames := 0
var _out := ""
var _done := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://Ichi.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 600
	var storm: Storm = current_scene.find_child("Storm", true, false)
	if storm == null or storm.roof_image == null:
		return _frames > 600
	if _frames < 120 or _done:
		return false
	_done = true
	var img := storm.roof_image
	print("roof map ", img.get_size(), " format ", img.get_format(), " rect ", storm.roof_rect,
		" y ", storm.roof_y_min, " + ", storm.roof_y_span)
	var space := storm.get_world_3d().direct_space_state
	var top := storm.roof_y_min + storm.roof_y_span + 5.0
	var worst := 0.0
	var n := 0
	var bad := 0
	for i in 40:
		for j in 40:
			var p := storm.roof_rect.position + storm.roof_rect.size * Vector2((i + 0.5) / 40.0, (j + 0.5) / 40.0)
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.y), Vector3(p.x, storm.roof_y_min - 5.0, p.y))
			var hit := space.intersect_ray(q)
			var baked := storm.roof_height(p)
			if hit.is_empty():
				if baked != -INF:
					bad += 1
				continue
			n += 1
			var err := absf(baked - (hit.position as Vector3).y)
			worst = maxf(worst, err)
			if err > 1.0:
				bad += 1
	print("compared ", n, " hits, worst error ", worst, " m, ", bad, " off by > 1 m")
	var cam := current_scene.get_viewport().get_camera_3d()
	if cam != null:
		var cp := cam.global_position
		print("camera ", cp, " roof over it ", storm.roof_height(Vector2(cp.x, cp.z)),
			" sheltered ", storm.is_sheltered(cp))
	var grey := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_L8)
	for y in range(0, img.get_height(), 1):
		for x in range(0, img.get_width(), 1):
			var c := img.get_pixel(x, y)
			grey.set_pixel(x, y, Color.BLACK if c.a < 0.5 else Color.from_hsv(0, 0, (roundf(c.r * 255.0) + c.g) / 255.0))
	grey.resize(1024, 1024)
	grey.save_png(_out + "/roof_map.png")
	root.get_texture().get_image().save_png(_out + "/shelter_shot.png")
	print("saved to ", _out)
	_teleport_inside(storm)
	return false

# Second shot: the pilot stood under the big roof (map pixel 0.43, 0.56), floor found by a ray.
func _teleport_inside(storm: Storm) -> void:
	var p := storm.roof_rect.position + storm.roof_rect.size * Vector2(0.43, 0.56)
	var roof := storm.roof_height(p)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, roof - 1.0, p.y), Vector3(p.x, roof - 200.0, p.y))
	var hit := storm.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("no floor under the roof at ", p)
		return
	var floor_pos: Vector3 = hit.position
	print("inside: roof ", roof, " floor ", floor_pos.y, " pilot sheltered ", storm.is_sheltered(floor_pos + Vector3.UP))
	var pilot: Node3D = current_scene.find_child("Pilot9", true, false)
	pilot.global_position = floor_pos + Vector3.UP * 0.2
	for i in 90:
		await process_frame
	root.get_texture().get_image().save_png(_out + "/shelter_inside.png")
	print("saved inside shot")
	quit()
