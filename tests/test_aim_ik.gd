extends "res://tests/test_case.gd"

# docs/specs/pilot9-gun-aim.md. The right-click aim is PLACED, not posed: the gun is pinned to his
# BODY (rifle butt in the right shoulder pocket, revolver pushed out in front of the chest - never
# placed from the head), his upper body bends with the aim, and two_bone() reaches each hand to its
# grip. The hard rule here: no part of either gun enters his helmet at level, up or down. How it
# LOOKS is judged from tests/_probe_gun_aim.gd shots.

const AIM_IK := preload("res://scripts/items/aim_ik.gd")
const MODIFIER := preload("res://scripts/items/arm_pose_modifier.gd")
const RIFLE := "res://resources/items/rifle.tres"
const REVOLVER := "res://resources/items/revolver.tres"
const PILOT_TSCN := "res://scenes/pilot9.tscn"
## The helmet as a sphere around the Head bone (bone-local centre, radius), measured off the head
## mesh by tests/_probe_aim_measure.gd; a little generous.
const HEAD_CENTER := Vector3(0.0, 0.13, -0.016)
const HEAD_RADIUS := 0.195
const UP := Vector3.UP
## In skeleton space +X is his left and +Z his forward.
const LEFT := Vector3.RIGHT


func test_the_gun_points_at_the_aim_point_with_its_anchor_on_the_body() -> void:
	var anchor := Vector3(-0.2, 1.45, 0.1)
	var pin := Vector3(0, 0.07, 0.36)
	var f: Transform3D = AIM_IK.item_frame(anchor, Vector3(-0.2, 1.45, 30), UP, pin)
	approx((-f.basis.z).dot(Vector3(0, 0, 1)), 1.0, 1e-5, "level aim: -Z is straight ahead")
	approx(f.basis.y.dot(UP), 1.0, 1e-5, "upright")
	approx((f * pin).distance_to(anchor), 0.0, 1e-5, "the pinned point sits on the anchor")
	var down: Transform3D = AIM_IK.item_frame(anchor, Vector3(-0.2, 0.0, 10), UP, pin)
	check((-down.basis.z).y < -0.1, "a lower aim point tips the barrel down")
	approx((down * pin).distance_to(anchor), 0.0, 1e-5, "and the butt stays in the shoulder")


func test_the_anchor_comes_from_the_shoulders_never_the_head() -> void:
	var r := Vector3(-0.24, 1.45, 0.07)
	var l := Vector3(0.20, 1.46, 0.14)
	var aim := Vector3(0, 1.45, 40)
	var a: Vector3 = AIM_IK.anchor_point(r, l, false, Vector3(0.03, -0.02, 0.07), aim, UP, LEFT)
	check(a.x < r.x and a.y < r.y and a.z > r.z, "rifle: right of, below and ahead of the right shoulder joint")
	var c: Vector3 = AIM_IK.anchor_point(r, l, true, Vector3(0, 0.1, 0.6), aim, UP, LEFT)
	approx(c.x, (r.x + l.x) * 0.5, 0.01, "revolver: on his centre line")
	check(c.z > 0.6, "pushed out in front of the chest")


func test_two_bone_reaches_a_point_with_the_elbow_down() -> void:
	var skel := _arm()
	var target := Vector3(0.3, -0.2, 0.2)
	AIM_IK.two_bone(skel, 0, 1, 2, target, Vector3.DOWN)
	var reached: Vector3 = skel.get_bone_global_pose(2).origin
	approx(reached.distance_to(target), 0.0, 1e-3, "the hand lands on the target")
	var elbow: Vector3 = skel.get_bone_global_pose(1).origin
	check(elbow.y < reached.y + 0.01 or elbow.y < 0.0, "the elbow bends toward the pole (down)")
	skel.free()


func test_two_bone_clamps_an_unreachable_target() -> void:
	var skel := _arm()
	AIM_IK.two_bone(skel, 0, 1, 2, Vector3(5, 0, 0), Vector3.DOWN)
	var reached: Vector3 = skel.get_bone_global_pose(2).origin
	check(reached.length() <= 0.6 + 1e-3, "a far target is clamped to arm length")
	check(reached.x > 0.55, "and the arm points at it")
	skel.free()


func test_bend_adds_up_along_the_chain() -> void:
	var skel := _arm()
	AIM_IK.bend(skel, [0, 1], Vector3.RIGHT, [deg_to_rad(10.0), deg_to_rad(20.0)])
	var y: Vector3 = skel.get_bone_global_pose(1).basis.y
	approx(rad_to_deg(y.angle_to(Vector3.UP)), 30.0, 0.01, "the child carries both angles")
	skel.free()


func test_both_guns_aim_by_placement() -> void:
	var rifle := load(RIFLE) as HeldItem
	check(rifle.aim_ik and not rifle.aim_center, "the rifle is pinned at the right shoulder")
	approx(rifle.aim_anchor_item.z, 0.36, 0.03, "by the butt of its stock")
	check(rifle.aim_twist_deg.has(&"Spine"), "bladed torso kept")
	check(rifle.aim_left_hand.origin.z < -0.4, "left hand forward under the fore-end")
	var revolver := load(REVOLVER) as HeldItem
	check(revolver.aim_ik and revolver.aim_center, "the revolver is pushed out from his centre line")
	check(revolver.aim_twist_deg.is_empty(), "shoulders square")
	check(revolver.aim_left_hand.origin.length() < 0.15, "left hand on the grip: two hands on the gun")
	check(rifle.aim_bend > 0.9 and revolver.aim_bend > 0.9, "the upper body takes the up / down pitch")


func test_no_part_of_either_gun_enters_the_helmet_at_any_pitch() -> void:
	for path in [RIFLE, REVOLVER]:
		var item := load(path) as HeldItem
		for pitch in [0.0, 40.0, -40.0, 60.0, -60.0]:
			var r := _aimed(item, pitch)
			check(r.clearance > 0.01, "%s at %d deg: gun clear of the helmet, got %.3f m" % [
				path.get_file(), int(pitch), r.clearance])
			check(r.right_err < 0.005, "%s at %d deg: right hand on the grip (%.3f m off)" % [
				path.get_file(), int(pitch), r.right_err])
			check(r.left_err < 0.005, "%s at %d deg: left hand on the gun (%.3f m off)" % [
				path.get_file(), int(pitch), r.left_err])


func test_the_arrangement_is_the_same_at_every_pitch() -> void:
	# The torso bends, so the gun keeps its place against the head and chest.
	for path in [RIFLE, REVOLVER]:
		var item := load(path) as HeldItem
		var level: Dictionary = _aimed(item, 0.0)
		for pitch in [40.0, -40.0]:
			var r: Dictionary = _aimed(item, pitch)
			check(absf(r.clearance - level.clearance) < 0.06,
				"%s: helmet gap at %d deg (%.3f) stays near the level one (%.3f)" % [
					path.get_file(), int(pitch), r.clearance, level.clearance])
			approx(rad_to_deg(r.torso_pitch), pitch, 6.0, "%s: upper body bent with the aim" % path.get_file())


## A bare three-bone arm hanging down -Y, 0.3 m per bone.
func _arm() -> Skeleton3D:
	var skel := Skeleton3D.new()
	skel.add_bone("U")
	skel.add_bone("L")
	skel.add_bone("H")
	skel.set_bone_parent(1, 0)
	skel.set_bone_parent(2, 1)
	skel.set_bone_rest(0, Transform3D.IDENTITY)
	skel.set_bone_rest(1, Transform3D(Basis(), Vector3(0, -0.3, 0)))
	skel.set_bone_rest(2, Transform3D(Basis(), Vector3(0, -0.3, 0)))
	skel.reset_bone_poses()
	# In the tree: outside it a skeleton hands back stale global poses after a bone is set.
	(Engine.get_main_loop() as SceneTree).root.add_child(skel)
	return skel


## The real pilot9 skeleton at rest, aimed with `item` at `pitch_deg` the way ArmPoseModifier does
## it (twist, bend, reach). Returns the gap from gun to helmet, both wrist misses, the torso pitch.
func _aimed(item: HeldItem, pitch_deg: float) -> Dictionary:
	var pilot := (load(PILOT_TSCN) as PackedScene).instantiate()
	var skel := pilot.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	# The skeleton alone goes in the tree (outside it global poses go stale after a bone is set);
	# the pilot itself never readies.
	skel.get_parent().remove_child(skel)
	(Engine.get_main_loop() as SceneTree).root.add_child(skel)
	skel.reset_bone_poses()
	var chest := skel.find_bone(&"UpperChest")
	var chest_up_before: Vector3 = skel.get_bone_global_pose(chest).basis.y
	var p := deg_to_rad(pitch_deg)
	var aim_pt: Vector3 = skel.get_bone_global_pose(chest).origin + Vector3(0, sin(p), cos(p)) * 40.0
	var yaws := {}
	for bone_name in item.aim_twist_deg:
		yaws[skel.find_bone(bone_name)] = deg_to_rad(item.aim_twist_deg[bone_name])
	MODIFIER.apply_twist(skel, yaws)
	MODIFIER.apply_bend(skel, item, aim_pt, UP, LEFT, 1.0)
	var gun: Transform3D = AIM_IK.apply(skel, {"item": item, "weight": 1.0, "aim_pt": aim_pt,
		"up": UP, "left": LEFT})
	var head: Transform3D = skel.get_bone_global_pose(skel.find_bone(&"Head"))
	var center := head * HEAD_CENTER
	var model := item.scene.instantiate() as Node3D
	(Engine.get_main_loop() as SceneTree).root.add_child(model)
	var clearance := INF
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf: Transform3D = gun * (model.global_transform.affine_inverse() * mi.global_transform)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var n_idx: int = idx.size() if idx != null else verts.size()
			for i in range(0, n_idx - 2, 3):
				var a: Vector3 = xf * verts[idx[i] if idx != null else i]
				var b: Vector3 = xf * verts[idx[i + 1] if idx != null else i + 1]
				var c: Vector3 = xf * verts[idx[i + 2] if idx != null else i + 2]
				for q: Vector3 in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (a + c) * 0.5, (a + b + c) / 3.0]:
					clearance = minf(clearance, q.distance_to(center) - HEAD_RADIUS)
	model.queue_free()
	var rh: Vector3 = skel.get_bone_global_pose(skel.find_bone(&"RightHand")).origin
	var lh: Vector3 = skel.get_bone_global_pose(skel.find_bone(&"LeftHand")).origin
	var chest_up: Vector3 = skel.get_bone_global_pose(chest).basis.y
	# Positive = leaning back (aiming up): the chest's up axis tips toward -Z.
	var torso_pitch := atan2(-chest_up.z, chest_up.y) - atan2(-chest_up_before.z, chest_up_before.y)
	var out := {
		"clearance": clearance,
		"right_err": rh.distance_to((gun * item.hand_offset.affine_inverse()).origin),
		"left_err": lh.distance_to((gun * item.aim_left_hand).origin),
		"torso_pitch": torso_pitch,
	}
	skel.free()
	pilot.free()
	return out
