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
