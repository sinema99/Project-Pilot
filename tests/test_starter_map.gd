extends "res://tests/test_case.gd"

# The starter map mission - see docs/specs/starter-map.md. Headless fences the wiring, the
# spawn-empty snap (and its no-empty fallback), the kill-height respawn and the import contract.
# Whether the greybox reads at pilot scale is checked by playing it.

const SCENE := "res://scenes/starter_map.tscn"
const WRAPPER := "res://Starter_Map.tscn"

var _scene: MissionMap

func end() -> void:
	if is_instance_valid(_scene):
		_scene.free()
	_scene = null
	super()

# In the tree: respawn() works in global space.
func _load() -> MissionMap:
	_scene = (load(SCENE) as PackedScene).instantiate() as MissionMap
	(Engine.get_main_loop() as SceneTree).root.add_child(_scene)
	return _scene

func _yaw(scene: MissionMap) -> float:
	return (scene.pilot.get_node("character") as Node3D).rotation.y

func _add_spawn(scene: MissionMap, origin: Vector3, facing_yaw: float) -> void:
	var empty := Node3D.new()
	empty.name = "spawn"
	scene.map.add_child(empty)
	# Godot forward is -Z: an empty "facing" yaw y has its -Z along (sin y, 0, cos y).
	empty.global_transform = Transform3D(Basis(Vector3.UP, facing_yaw + PI), origin)

func test_the_scene_is_wired() -> void:
	var scene := _load()
	check(scene.map != null and scene.map.scene_file_path == "res://assets/starter_map.glb",
		"Map should be the starter_map.glb instance")
	check(scene.pilot != null and scene.pilot.scene_file_path == "res://scenes/pilot9.tscn",
		"Pilot9 should be a pilot9 instance")
	check(scene.get_node_or_null("Storm") == null, "a fresh mission: no Ichi blizzard")
	check(scene.get_node_or_null("EXIA") == null, "pilot9 only, no mech")
	eq((scene.get_node("ApplyCelGround").get("targets") as Array), [NodePath("../Map")],
		"the whole map gets the cel ground look")
	check(scene.get_node_or_null("RetroLook") != null and scene.get_node_or_null("PixelLook") != null,
		"trial's look rigs come along")
	check(load(WRAPPER) is PackedScene, "Starter_Map.tscn wrapper is missing")

func test_every_map_mesh_is_solid() -> void:
	var scene := _load()
	var meshes := scene.map.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() > 0, "the map imported no meshes")
	for mi in meshes:
		var solid := false
		for c in mi.get_children():
			solid = solid or c is StaticBody3D
		check(solid, "%s has no collision - is map_import.gd its import script?" % mi.name)

func test_the_pilot_reference_cube_is_not_imported() -> void:
	var scene := _load()
	check(scene.map.find_child("pilot_ref*", true, false) == null,
		"pilot_ref should be named pilot_ref-noimp in Blender so the importer skips it")

func test_no_spawn_empty_starts_at_the_origin_facing_plus_z() -> void:
	var scene := _load()
	if scene.map.find_child(scene.spawn_name, true, false) != null:
		scene.map.find_child(scene.spawn_name, true, false).name = "not_spawn"
	scene.respawn()
	approx(scene.pilot.global_position.distance_to(Vector3.UP * scene.spawn_lift), 0.0, 0.001,
		"no spawn empty: he should start on the origin")
	approx(absf(angle_difference(_yaw(scene), 0.0)), 0.0, 0.01, "no spawn empty: he should face +Z")

func test_he_snaps_to_the_spawn_empty() -> void:
	var scene := _load()
	_add_spawn(scene, Vector3(12, 3, -40), 1.1)
	scene.respawn()
	approx(scene.pilot.global_position.distance_to(Vector3(12, 3 + scene.spawn_lift, -40)), 0.0, 0.001,
		"he should stand on the spawn empty")
	check(scene.pilot.basis.is_equal_approx(Basis()), "turn his children, not the root")
	approx(absf(angle_difference(_yaw(scene), 1.1)), 0.0, 0.01, "he should face the empty's forward")
	approx(absf(angle_difference((scene.pilot.get_node("CameraPivot") as Node3D).rotation.y, 1.1 + PI)), 0.0, 0.01,
		"the camera should sit behind him")

func test_falling_below_the_kill_height_respawns_him() -> void:
	var scene := _load()
	_add_spawn(scene, Vector3(4, 0, 9), 0.0)
	scene.pilot.global_position = Vector3(50, scene.kill_height + 1.0, 50)
	scene._physics_process(1.0 / 60.0)
	approx(scene.pilot.global_position.y, scene.kill_height + 1.0, 0.001, "above the kill height: left alone")
	scene.pilot.global_position = Vector3(50, scene.kill_height - 1.0, 50)
	scene.pilot.velocity = Vector3(0, -40, 10)
	scene._physics_process(1.0 / 60.0)
	approx(scene.pilot.global_position.distance_to(Vector3(4, scene.spawn_lift, 9)), 0.0, 0.001,
		"below the kill height: back on the spawn")
	eq(scene.pilot.velocity, Vector3.ZERO, "respawn should stop him")
