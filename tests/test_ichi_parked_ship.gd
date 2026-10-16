extends "res://tests/test_case.gd"

# Sinestro2 parked in Ichi - see docs/specs/ichi-parked-ship.md. Headless can fence the held
# pose, the scene wiring and the snow-shelter boxes. How it looks and where it sits on the
# ground is checked by eye.

const SHIP := "res://scenes/sinestro2_parked.tscn"
const SCENE := "res://scenes/operation_ichi.tscn"

# The last key of `clip`'s track for `bone` on `armature`, of the given track type.
func _last_key(player: AnimationPlayer, clip: String, armature: String, bone: String, type: int) -> Variant:
	var anim := player.get_animation(clip)
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		if path.get_name(0) == armature and String(path.get_concatenated_subnames()) == bone \
				and anim.track_get_type(t) == type:
			return anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
	return null

func test_each_clip_holds_its_last_frame_on_its_own_armature() -> void:
	var ship: ParkedShip = (load(SHIP) as PackedScene).instantiate()
	check(ship.pose() > 0, "pose() wrote nothing")
	var player := ship.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var cases := [
		["cockpit_open", "Armature_001", "Bone"],
		["landingear", "Armature_002", "Bone"],
		["Action", "Armature_003", "Bone"],
	]
	for c in cases:
		var skel := ship.model.get_node("%s/Skeleton3D" % c[1]) as Skeleton3D
		var bone := skel.find_bone(c[2])
		var rot: Variant = _last_key(player, c[0], c[1], c[2], Animation.TYPE_ROTATION_3D)
		if rot != null:
			check(skel.get_bone_pose_rotation(bone).is_equal_approx(rot),
				"%s: %s is not on its last frame (a later clip's rest tracks overwrote it?)" % [c[0], c[1]])
	# The nose cone's slide is the one translation: it must survive the two clips posed after it.
	var cockpit := ship.model.get_node("Armature_001/Skeleton3D") as Skeleton3D
	approx(cockpit.get_bone_pose_position(cockpit.find_bone("Bone")).z, 1.0557, 0.01,
		"the cockpit is not open")
	ship.free()

func test_the_ship_is_solid_and_shelters_snow() -> void:
	var ship: Node = (load(SHIP) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(ship)  # roof_parts reads global transforms
	check(ship is StaticBody3D, "the ship root should be a StaticBody3D")
	var boxes := Storm.roof_boxes(ship)
	check(boxes.size() >= 6, "expected the hull boxes in the storm_roof group, got %d" % boxes.size())
	eq(Storm.roof_parts(ship).size(), boxes.size(), "every roof box becomes a bake part")
	ship.free()

func test_ichi_turns_the_pilot_and_parks_the_ship() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	var pilot: Node3D = scene.get_node("Pilot9")
	check(pilot.basis.is_equal_approx(Basis()), "turn his children, not the root - pilot9.gd treats character yaw as world yaw")
	var yaw := (pilot.get_node("character") as Node3D).rotation.y
	approx(absf(angle_difference((pilot.get_node("CameraPivot") as Node3D).rotation.y, yaw + PI)), 0.0, 0.01,
		"the camera should sit behind him, looking the way he faces")
	var ship := scene.get_node_or_null("Sinestro2")
	check(ship is ParkedShip, "Ichi has no Sinestro2")
	if ship is ParkedShip:
		# The opening shot: he stands off the ship's front-left quarter, looking at it.
		var to_ship := (ship as Node3D).position - pilot.position
		to_ship.y = 0.0
		check(Vector3(sin(yaw), 0.0, cos(yaw)).dot(to_ship.normalized()) > 0.9, "he should spawn facing the ship")
		check(to_ship.length() > 7.0 and to_ship.length() < 13.0, "he should spawn a few strides off the ship")
	var applier := scene.get_node("ApplyCelPilot9")
	check((applier.get("targets") as Array).has(NodePath("../Sinestro2")), "the ship gets the pilot's cel look")
	scene.free()
