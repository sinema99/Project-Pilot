extends "res://tests/test_case.gd"

# The hub2 map scene: pilot9 only, AIRFRAME look, spawn on the platform block at the end of the
# corridor beside the big cylinder. Whether it plays well is checked by running it (F6).

const SCENE := "res://scenes/hub2.tscn"

var _scene: MissionMap

func end() -> void:
	if is_instance_valid(_scene):
		_scene.free()
	_scene = null
	super()

func _load() -> MissionMap:
	_scene = (load(SCENE) as PackedScene).instantiate() as MissionMap
	(Engine.get_main_loop() as SceneTree).root.add_child(_scene)
	return _scene

func test_the_scene_is_wired() -> void:
	var scene := _load()
	check(scene.map != null and scene.map.scene_file_path == "res://assets/hub2.glb", "Map should be the hub2.glb instance")
	check(scene.pilot != null and scene.pilot.scene_file_path == "res://scenes/pilot9.tscn", "Pilot9 instance")
	for gone in ["EXIA", "Speeder1", "SpeederCourse", "Pilot9Decimate", "PilotSwitcher"]:
		check(scene.get_node_or_null(gone) == null, "%s should not be in hub2" % gone)
	check(scene.get_node_or_null("AirframeLook") != null, "AIRFRAME look rig should come along")
	check(scene.get_node_or_null("RetroLook") != null and scene.get_node_or_null("PixelWorld") != null, "look rigs")
	check(scene.get_node_or_null("ApplyCelGround") == null, "the cel ground look would paint over the industrial wear")
	eq(scene.get_node("Hub2Wear").get("map"), scene.map, "Hub2Wear dresses the map")

func test_every_map_mesh_is_solid() -> void:
	var scene := _load()
	var meshes := scene.map.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() > 0, "the map imported no meshes")
	for mi in meshes:
		if mi.name == Hub2Wear.DECAL_NODE:
			continue   # decals are visual only
		var solid := false
		for c in mi.get_children():
			solid = solid or c is StaticBody3D
		check(solid, "%s has no collision" % mi.name)

func test_he_spawns_on_the_platform_facing_the_spawn_empty() -> void:
	var scene := _load()
	scene.respawn()
	var spawn := scene.map.get_node("spawn") as Node3D
	approx(scene.pilot.global_position.distance_to(spawn.global_position + Vector3.UP * scene.spawn_lift), 0.0, 0.001, "on the spawn")
	# He faces the spawn empty's -Z (the spawn was moved into the room after the first build, so
	# this follows the node rather than a hard-coded -X).
	var fwd := -spawn.global_basis.z
	var yaw := (scene.pilot.get_node("character") as Node3D).rotation.y
	approx(absf(angle_difference(yaw, atan2(fwd.x, fwd.z))), 0.0, 0.01, "facing the spawn's forward")
	# The spawn rests on a surface: the first one below it (a room has a ceiling above).
	var top := -INF
	for mi in scene.map.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name == Hub2Wear.DECAL_NODE:
			continue
		var inv := m.global_transform.affine_inverse()
		var r := m.mesh.generate_triangle_mesh().intersect_ray(inv * (spawn.global_position + Vector3.UP * 1.0),
			(inv.basis * Vector3.DOWN).normalized())
		if not r.is_empty():
			top = maxf(top, (m.global_transform * (r["position"] as Vector3)).y)
	approx(spawn.global_position.y, top, 0.3, "spawn should rest on the platform surface")

func test_falling_below_the_kill_height_respawns_him() -> void:
	var scene := _load()
	var spawn := scene.map.get_node("spawn") as Node3D
	scene.pilot.global_position = Vector3(50, scene.kill_height - 1.0, 50)
	scene._physics_process(1.0 / 60.0)
	approx(scene.pilot.global_position.distance_to(spawn.global_position + Vector3.UP * scene.spawn_lift), 0.0, 0.001, "back on the spawn")

# Roof door rev 1 (docs/specs/hub2-roof-door.md): the daylight is slices through one soft light field
# (no stepped vertex-colour cards), and every slice reaches past the gap so no card edge sits in the light.
func test_roof_beams_are_soft_slices() -> void:
	var scene := _load()
	var door := scene.get_node("RoofDoor") as Hub2RoofDoor
	var beams := door.get_node("Beams") as MeshInstance3D
	var mat := beams.material_override as ShaderMaterial
	check(mat != null and mat.shader == Hub2RoofDoor.BEAM_SHADER, "beams use the soft beam shader")
	var gz := door.gap_half_length()
	var zs := {}
	for v in beams.mesh.get_faces():
		zs[snappedf(v.z, 0.01)] = true
	var z_lo := INF
	var z_hi := -INF
	for z: float in zs.keys():
		z_lo = minf(z_lo, z)
		z_hi = maxf(z_hi, z)
	check(z_lo <= -gz - Hub2RoofDoor.BEAM_FEATHER.y * 0.5 and z_hi >= gz + Hub2RoofDoor.BEAM_FEATHER.y * 0.5, "slices reach past the soft ends of the gap")
	check(zs.size() >= 12, "enough cross-sections to read as a volume (%d z values)" % zs.size())

# Crane control room (docs/specs/hub2-control-room.md).
func test_the_runway_no_longer_runs_through_the_control_room() -> void:
	var src := (load("res://scenes/hub2_dressing_src.tscn") as PackedScene).instantiate()
	var crane := src.find_child("BridgeCrane1", true, false) as Hub2Crane
	check(crane != null, "crane 1 should still be in room B")
	if crane != null:
		var east_rail := crane.position.x + crane.span * 0.5
		check(east_rail < -72.4 - 0.5, "crane 1's east runway (x %.1f) must sit outside the box's west wall (x -72.4)" % east_rail)
	src.free()

func test_the_windows_are_glass_and_still_solid() -> void:
	var scene := _load()
	var room := scene.get_node("ControlRoom") as Hub2ControlRoom
	check(room.glass != null and room.pane_tris >= 6, "the panes should have become a glass mesh (%d tris)" % room.pane_tris)
	var rows := {}
	var box := room.glass.mesh.get_aabb()
	check(box.size.z > 30.0 and box.position.x > -72.5 and box.end.x < -69.8 and box.size.y > 6.5, "glass covers the whole slanted wall (%s)" % str(box))
	# No pane triangle is left in any visual mesh of the map (decals included).
	var left := 0
	for node in scene.map.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var tris := mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var idx = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			for i in range(0, (idx as PackedInt32Array).size(), 3):
				if Hub2ControlRoom.pane_row(mi.global_transform * tris[idx[i]], mi.global_transform * tris[idx[i + 1]], mi.global_transform * tris[idx[i + 2]]) >= 0:
					left += 1
		else:
			for i in range(0, tris.size(), 3):
				var a: Vector3 = mi.global_transform * tris[i]
				var b: Vector3 = mi.global_transform * tris[i + 1]
				var c: Vector3 = mi.global_transform * tris[i + 2]
				if a != b and Hub2ControlRoom.pane_row(a, b, c) >= 0:
					left += 1
		rows[mi.name] = true
	eq(left, 0, "window triangles left in the map's meshes")
	# Collision keeps the quads: a solid wall still stands where the glass is.
	var solid := 0
	for body in scene.map.find_children("*", "StaticBody3D", true, false):
		for child in body.get_children():
			var cs := child as CollisionShape3D
			if cs != null and cs.shape is ConcavePolygonShape3D:
				var f := (cs.shape as ConcavePolygonShape3D).get_faces()
				for i in range(0, f.size(), 3):
					if Hub2ControlRoom.pane_row(cs.global_transform * f[i], cs.global_transform * f[i + 1], cs.global_transform * f[i + 2]) >= 0:
						solid += 1
	check(solid >= 6, "the pane quads must still be in the map's collision (%d)" % solid)

func test_the_control_room_door_slides_on_interact() -> void:
	var scene := _load()
	var room := scene.get_node("ControlRoom") as Hub2ControlRoom
	var door := room.door
	check(door != null and door.type == Hub2Door.Type.SLIDE, "a SLIDE door in the bulkhead")
	check(not door.is_open, "starts shut")
	var leaf := door.get_child(0) as Node3D
	for c in door.get_children():
		if c is AnimatableBody3D:
			leaf = c
	var shut_x := leaf.position.x
	door.toggle()
	check(door.is_open, "F opens it")
	for i in 60:
		door._physics_process(1.0 / 60.0)
	check(leaf.position.x - shut_x > 1.9, "the leaf has slid into the wall (%.2f)" % (leaf.position.x - shut_x))
	door.toggle()
	for i in 60:
		door._physics_process(1.0 / 60.0)
	approx(leaf.position.x, shut_x, 0.05, "and slides shut again")

func test_the_room_is_furnished_and_lit() -> void:
	var scene := _load()
	var room := scene.get_node("ControlRoom") as Hub2ControlRoom
	check(room.furniture != null and room.furniture.mesh.get_surface_count() > 3, "furniture with screen / lamp surfaces")
	check(room.screen_count >= 14, "powered screens (%d)" % room.screen_count)
	check(room.furniture_body.get_child_count() > 8, "furniture collides")

func test_the_window_cut_is_redone_when_the_wall_comes_back() -> void:
	var scene := _load()
	var room := scene.get_node("ControlRoom") as Hub2ControlRoom
	check(not room.ensure_cut(), "nothing to redo after a normal load")
	# Put the baked, uncut wall back, as a late swap would.
	var mi := scene.map.find_child("Cylinder_005", true, false) as MeshInstance3D
	mi.mesh = load("res://assets/hub2_wear/Cylinder_005.res")
	check(room.ensure_cut(), "pane triangles back, so it cuts again")
	check(not room.ensure_cut(), "and then they stay gone")
	check(room.glass != null and room.pane_tris > 0, "with one glass mesh")
