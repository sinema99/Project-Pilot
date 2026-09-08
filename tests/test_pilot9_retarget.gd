extends "res://tests/test_case.gd"

# Covers the pilot9 retarget: scenes/pilot9.tscn is RC's rig scene with the baked
# HumanM skeleton swapped for assets/pilot9.glb run through Godot's humanoid
# retargeting profile (the BoneMap in assets/pilot9.glb.import).
#
# The silent failure this targets: a clip whose tracks resolve to nothing plays
# without error - no crash, no dialog - and pilot9 just stands in his rest pose
# while the state machine transitions happily around him. So the load-bearing
# assertion is that every track path in every shipped clip lands on a real bone.
#
# See docs/specs/pilot9-real-controller.md (Verification) and docs/reimport.md (pilot9).

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const TRIAL_TSCN := "res://scenes/trial.tscn"
const GLB_IMPORT := "res://assets/pilot9.glb.import"

# Bones the BoneMap deliberately leaves unmapped: pilot9 is a 25-bone Mixamo
# blockout with no fingers, eyes, jaw or Root, and RC's rig carries a few private
# helper bones (B-*) of its own. Tracks addressing these are expected orphans, not
# a broken retarget.
const KNOWN_ABSENT := [
	"Root", "Jaw", "LeftEye", "RightEye",
	"B-spineProxy", "B-handProp.L", "B-handProp.R", "B-root",
]

# The 22 profile slots the BoneMap fills (spec's BoneMap table).
const MAPPED_PROFILE_BONES := [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]

var _instances: Array[Node] = []

# Instantiating a scene in the RefCounted test context leaks its render resources
# at exit (no SceneTree to free it). Track every instance and drop it when the
# test method returns; run_tests.gd calls end() after each.
func _scene() -> Node:
	return _instantiate(PILOT_TSCN)

func _instantiate(path: String) -> Node:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	return n

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super()

func _skeleton(root: Node) -> Skeleton3D:
	for n in root.find_children("*", "Skeleton3D", true, false):
		return n
	return null

func _is_finger(bone: String) -> bool:
	for part in ["Thumb", "Index", "Middle", "Ring", "Little", "Finger"]:
		if bone.contains(part):
			return true
	return false

func _expected_absent(bone: String) -> bool:
	return bone in KNOWN_ABSENT or bone.begins_with("B-") or _is_finger(bone)

# --- the retarget landed --------------------------------------------------

func test_scene_loads() -> void:
	check(_scene() != null, "scenes/pilot9.tscn failed to load/instantiate")

func test_skeleton_is_named_GeneralSkeleton() -> void:
	var root := _scene()
	if root == null:
		fail("scene did not load"); return
	var skel := _skeleton(root)
	check(skel != null, "no Skeleton3D in scenes/pilot9.tscn")
	if skel:
		eq(skel.name, &"GeneralSkeleton",
			"RC's clip tracks address %GeneralSkeleton - the retargeter must rename the node")
		check(skel.unique_name_in_owner,
			"GeneralSkeleton must be unique_name_in_owner or %GeneralSkeleton track paths cannot resolve")

func test_skeleton_resolves_through_the_unique_name() -> void:
	var root := _scene()
	if root == null:
		fail("scene did not load"); return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	check(ap != null, "no AnimationPlayer node")
	if ap == null:
		return
	var base := ap.get_node_or_null(ap.root_node)
	check(base != null, "AnimationPlayer.root_node points at nothing: %s" % ap.root_node)
	var via_unique := root.get_node_or_null("%GeneralSkeleton")
	check(via_unique is Skeleton3D,
		"%GeneralSkeleton does not resolve to a Skeleton3D from the scene root")

func test_every_mapped_profile_bone_is_present() -> void:
	var root := _scene()
	if root == null:
		fail("scene did not load"); return
	var skel := _skeleton(root)
	if skel == null:
		fail("no skeleton"); return
	var missing: PackedStringArray = []
	for b in MAPPED_PROFILE_BONES:
		if skel.find_bone(b) == -1:
			missing.append(b)
	check(missing.is_empty(),
		"BoneMap claims these profile bones but the retargeted skeleton has none: %s" % str(missing))

func test_motion_scale_was_normalised() -> void:
	var root := _scene()
	if root == null:
		fail("scene did not load"); return
	var skel := _skeleton(root)
	if skel == null:
		fail("no skeleton"); return
	# Stock pilot9 imported at motion_scale 1.0; the rest-fixer sets it to ~Hips
	# height (~1.06). Anything still at exactly 1.0 means the fixer never ran.
	check(skel.motion_scale > 1.02,
		"motion_scale is %f - the rest fixer did not normalise it (retarget silently skipped?)" % skel.motion_scale)

# --- the clips bind ------------------------------------------------------

func test_all_shipped_clips_bind_every_track_to_a_real_bone() -> void:
	var root := _scene()
	if root == null:
		fail("scene did not load"); return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		fail("no AnimationPlayer"); return
	var skel := root.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	if skel == null:
		fail("%GeneralSkeleton unresolved - cannot check tracks"); return

	var clips := ap.get_animation_list()
	check(clips.size() >= 20,
		"expected RC's full clip set (~28), got %d - the AnimationLibrary is truncated" % clips.size())

	var broken: PackedStringArray = []
	for clip_name in clips:
		var anim := ap.get_animation(clip_name)
		for t in anim.get_track_count():
			var path := str(anim.track_get_path(t))
			var bone := path.get_slice(":", 1)
			if bone == "" or _expected_absent(bone):
				continue
			if skel.find_bone(bone) == -1:
				broken.append("%s -> %s" % [clip_name, bone])
	check(broken.is_empty(),
		"%d track(s) address bones that do not exist on the retargeted rig:\n      %s"
		% [broken.size(), "\n      ".join(broken)])

func test_no_shipped_clip_is_zero_length() -> void:
	var root := _scene()
	if root == null:
		fail("scene did not load"); return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		fail("no AnimationPlayer"); return
	var zero: PackedStringArray = []
	for clip_name in ap.get_animation_list():
		if ap.get_animation(clip_name).length <= 0.0:
			zero.append(clip_name)
	check(zero.is_empty(), "zero-length clips (a real failure mode per docs/reimport.md): %s" % str(zero))

# --- the import file still carries the BoneMap ---------------------------

func test_import_file_declares_the_bone_map() -> void:
	var f := FileAccess.open(GLB_IMPORT, FileAccess.READ)
	check(f != null, "assets/pilot9.glb.import missing")
	if f == null:
		return
	var src := f.get_as_text()
	check(src.contains("retarget/bone_map"),
		"assets/pilot9.glb.import has no retarget/bone_map - a plain reimport would drop the retarget")
	check(src.contains("SkeletonProfileHumanoid"),
		"BoneMap has no humanoid profile")
	check(src.contains("\"bone_map/Hips\":&\"mixamorig_Hips\""),
		"BoneMap does not map Hips -> mixamorig_Hips (underscore, not colon - that is the Godot 4.6 imported name)")

# --- trial.tscn: the drivable scene (spec step 6 + the headless-boot check) ---

func test_trial_scene_wires_pilot9() -> void:
	var root := _instantiate(TRIAL_TSCN)
	check(root != null, "scenes/trial.tscn failed to instantiate")
	if root == null:
		return
	var pilot := root.get_node_or_null("Pilot9")
	check(pilot is CharacterBody3D, "trial.tscn has no Pilot9 CharacterBody3D")
	if pilot:
		var scr := pilot.get_script() as Script
		check(scr != null and scr.resource_path == "res://scripts/pilot9.gd",
			"Pilot9 is not driven by scripts/pilot9.gd")
		check(pilot.get_node_or_null("%GeneralSkeleton") is Skeleton3D,
			"%GeneralSkeleton does not resolve inside the trial-instanced pilot9")

# EXIA (scenes/mech.tscn, added for the mech mount - docs/specs/pilot9-mech-mount.md) brings
# two cameras of its own, so a raw Camera3D count is no longer the check. What has to hold is
# that exactly one camera is `current`, it is RC's rig camera under Pilot9/CameraPivot, and
# EXIA's two are both dormant until someone climbs in. Strictly stronger than the old count -
# that never checked a *wrong* camera was not the one taking the picture.
func test_trial_has_exactly_one_current_camera_and_it_is_the_rc_rig_camera() -> void:
	var root := _instantiate(TRIAL_TSCN)
	if root == null:
		fail("trial.tscn did not load"); return
	var cams := root.find_children("*", "Camera3D", true, false)
	var current: Array = []
	for c in cams:
		if (c as Camera3D).current:
			current.append(c)
	eq(current.size(), 1,
		"trial.tscn must have exactly one current camera; got %d" % current.size())
	if current.size() == 1:
		var cam := current[0] as Camera3D
		check(str(root.get_path_to(cam)).begins_with("Pilot9/CameraPivot"),
			"the current camera should be RC's CameraPivot camera, got %s" % root.get_path_to(cam))
	for c in cams:
		if str(root.get_path_to(c)).begins_with("EXIA"):
			check(not (c as Camera3D).current,
				"EXIA's %s must not be current in a parked trial" % root.get_path_to(c))

func test_trial_still_carries_the_cel_pass_on_pilot9() -> void:
	# Cel look started OFF for the first look (spec), then flipped ON once the retarget
	# checked out on 2026-09-05. The node and its cel_character material must still be
	# wired at pilot9 - a dropped target is how the outline silently stops applying.
	var root := _instantiate(TRIAL_TSCN)
	if root == null:
		fail("trial.tscn did not load"); return
	var applier := root.get_node_or_null("ApplyCelPilot9")
	check(applier != null, "trial.tscn lost ApplyCelPilot9")
	if applier:
		check(applier.apply_on_ready, "cel pass on pilot9 should be live now (flipped on after the retarget checked out)")
		check(applier.material != null, "ApplyCelPilot9 has no material")
		check(applier.targets.size() == 1 and str(applier.targets[0]) == "../Pilot9",
			"ApplyCelPilot9 no longer targets Pilot9")
