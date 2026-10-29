extends "res://tests/test_case.gd"

# The Internals greybox (map 1) - see docs/specs/internals-map.md. Headless fences the wiring the
# grilling decided: base kit only, the double jump pickup, three rest pads, the one-way doors,
# kill volumes and checkpoint respawns. Whether the route is walkable is tests/_probe_internals_route.gd;
# whether it is fun is played.

const SCENE := "res://scenes/internals.tscn"
const WRAPPER := "res://Internals.tscn"

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
	check(scene.pilot != null and scene.pilot.scene_file_path == "res://scenes/pilot9.tscn", "Pilot9 should be a pilot9 instance")
	check(scene.map != null and scene.map.find_child("spawn", true, false) is Marker3D, "Map needs its spawn marker")
	check(scene.get_node_or_null("EXIA") == null, "no mech on map 1: pilot hasn't found it yet")
	check(scene.get_node_or_null("MissionHud") is MissionHud, "the HUD (clock + debug keys) is missing")
	check(scene.map.get_node_or_null("Shell") is CSGCombiner3D, "the walls are one CSG shell")
	check(load(WRAPPER) is PackedScene, "Internals.tscn wrapper is missing")

func test_pilot_starts_with_the_base_kit_only() -> void:
	var pilot := _load().pilot
	eq(int(pilot.get("air_jumps")), 0, "the double jump is found in the Capacitor Vault, not owned")
	for flag in ["can_dash", "can_wall_run", "can_wall_climb", "can_rail_grind"]:
		check(not bool(pilot.get(flag)), "%s should be off on map 1" % flag)
	for flag in ["can_climb", "can_vault", "can_slide"]:
		check(bool(pilot.get(flag)), "%s is base kit and stays on" % flag)

func test_the_pickup_grants_the_double_jump() -> void:
	var scene := _load()
	var pickup := scene.map.find_child("DoubleJump", true, false) as AbilityPickup
	check(pickup != null, "no double jump pickup")
	pickup._on_body_entered(scene.pilot)
	eq(int(scene.pilot.get("air_jumps")), 1, "touching the pickup should set air_jumps 1")
	check(not pickup.visible, "the pickup should be spent")

func test_rest_pads_become_the_respawn() -> void:
	var scene := _load()
	var pads := scene.map.find_children("Rest*", "Area3D", true, false)
	eq(pads.size(), 3, "three rest pads")
	var pad := pads[1] as RestPad
	pad._on_body_entered(scene.pilot)
	check(scene.checkpoint == pad, "touching a pad should save it")
	scene.pilot.global_position = Vector3(0, -100, 0)
	scene.respawn()
	check(scene.pilot.global_position.distance_to(pad.global_position) < 0.5, "respawn should land on the saved pad")

func test_pits_kill_and_doors_are_one_way() -> void:
	var scene := _load()
	check(scene.map.find_children("*", "KillVolume", true, false).size() >= 6, "every pit floor needs a kill volume")
	var gates := scene.map.find_children("Gate_*", "StaticBody3D", true, false)
	eq(gates.size(), 3, "shutter, shortcut door and riser door")
	var g := gates[0] as OneWayGate
	g.open()
	check(not g.visible and g.collision_layer == 0, "an opened gate stops blocking")
