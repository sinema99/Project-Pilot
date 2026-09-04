extends "res://tests/test_case.gd"

# Covers docs/specs/setsuna-screens.md.
#
# Two halves. The band/fill rules are pure static functions, so they are asserted
# directly with no scene. The quad placement is asserted by instantiating
# player.tscn and composing each quad's transform onto its bone's global rest --
# hand-placed transforms are the one thing in this change that can be wrong
# without anything erroring.

const Screens := preload("res://scripts/rendering/setsuna_screens.gd")
const SHADER_PATH := "res://shaders/screen.gdshader"

# name, bone, expected quad centre in mesh space, expected quad size.
# The centres are the placement as authored in player.tscn, confirmed on the screen by the user
# 2026-09-01 -- these lights are where they want them. They sit ~10cm above and ~2cm proud of
# the spec's measured-geometry table because the armature carries a 0.9343115 object scale, so
# the inverse-bind rest the table was measured against and the node-chain rest Godot builds bone
# rests from disagree. The table is the record of the panel geometry; these numbers are the
# record of the placement, and what this test is actually for is catching a re-export moving it.
const PLACEMENTS := [
	["ScreenHealth",  "spine.002", Vector3(0.025500, 1.493140, -0.303504),  Vector2(0.0510, 0.1165)],
	["ScreenStamina", "spine.002", Vector3(-0.035268, 1.492507, -0.303937), Vector2(0.0255, 0.1165)],
	["ScreenDash",    "spine.002", Vector3(0.0, 1.374516, -0.304665),       Vector2(0.1020, 0.0388)],
	["ScreenThighR",  "thigh.R",   Vector3(-0.139464, 0.818351, -0.058226), Vector2(0.0303, 0.2441)],
	["ScreenThighL",  "thigh.L",   Vector3(0.139526, 0.816704, -0.057846),  Vector2(0.0303, 0.2441)],
]

# --- the band table -------------------------------------------------------

# The speeds the controller can actually produce. It assigns velocity directly
# rather than accelerating, so nothing in between ever occurs -- but the
# thresholds are asserted separately below in case that changes.
#
# 3.0 is no longer one of them: CROUCH_SPEED is SPRINT_SPEED now, so the crouch
# reads red like the sprint and BAND_CROUCH is a band nothing reaches. The row
# stays because the band function is still asked about that speed range, and
# because the green comes back the moment the crouch gets a pace of its own.
func test_speed_band_at_each_real_speed() -> void:
	eq(Screens.speed_band(0.0), Screens.BAND_IDLE, "standing still is the idle band")
	eq(Screens.speed_band(3.0), Screens.BAND_CROUCH, "a creeping pace is the crouch band")
	eq(Screens.speed_band(6.0), Screens.BAND_RUN, "SPEED is the run band")
	eq(Screens.speed_band(9.0), Screens.BAND_SPRINT, "SPRINT_SPEED is the sprint band")
	eq(Screens.speed_band(18.0), Screens.BAND_SPRINT, "DASH_SPEED lands on sprint, not off the end")

func test_speed_band_thresholds() -> void:
	eq(Screens.speed_band(1.49), Screens.BAND_IDLE, "just under the crouch threshold is idle")
	eq(Screens.speed_band(1.51), Screens.BAND_CROUCH, "just over it is crouch")
	eq(Screens.speed_band(4.49), Screens.BAND_CROUCH, "just under the run threshold is crouch")
	eq(Screens.speed_band(4.51), Screens.BAND_RUN, "just over it is run")
	eq(Screens.speed_band(7.49), Screens.BAND_RUN, "just under the sprint threshold is run")
	eq(Screens.speed_band(7.51), Screens.BAND_SPRINT, "just over it is sprint")

func test_speed_band_colours_are_distinct() -> void:
	var seen := [Screens.BAND_IDLE, Screens.BAND_CROUCH, Screens.BAND_RUN, Screens.BAND_SPRINT]
	for i in seen.size():
		for k in range(i + 1, seen.size()):
			check(seen[i] != seen[k], "band %d and %d must not share a colour" % [i, k])

# --- fills ----------------------------------------------------------------

# The dash screen is a ready light, not a gauge: it deliberately shows no
# progress through the 3.0s lockout.
func test_dash_fill_is_binary() -> void:
	eq(Screens.dash_fill(0.0), 1.0, "no cooldown left means lit")
	eq(Screens.dash_fill(-1.0), 1.0, "an overshot cooldown still means lit")
	eq(Screens.dash_fill(0.01), 0.0, "any cooldown at all means dim")
	eq(Screens.dash_fill(3.0), 0.0, "a full cooldown means dim")

func test_meter_fill_clamps() -> void:
	eq(Screens.meter_fill(0.5), 0.5, "an in-range meter passes through")
	eq(Screens.meter_fill(0.0), 0.0, "empty is empty")
	eq(Screens.meter_fill(1.0), 1.0, "full is full")
	eq(Screens.meter_fill(-0.5), 0.0, "a negative meter clamps to empty")
	eq(Screens.meter_fill(2.0), 1.0, "an over-full meter clamps to full")

# --- shader ---------------------------------------------------------------

func test_shader_exposes_its_uniforms() -> void:
	var names := shader_uniform_names(SHADER_PATH)
	check(not names.is_empty(), "screen.gdshader failed to compile")
	for want in ["fill_color", "fill", "track_level"]:
		check(names.has(want), "screen.gdshader must expose '%s'" % want)

# The track is what stops an empty gauge reading as no screen at all, so its
# level is a spec decision rather than a taste knob.
func test_track_level_default() -> void:
	approx(declared_default_float(SHADER_PATH, "track_level"), 0.12, 0.0001,
		"track_level ships at 0.12")

# --- movement change ------------------------------------------------------

func test_dash_cooldown_is_three_seconds() -> void:
	var consts: Dictionary = load("res://scripts/player.gd").get_script_constant_map()
	approx(consts["DASH_COOLDOWN"], 3.0, 0.0001, "DASH_COOLDOWN is 3.0s per the spec")

# --- placement ------------------------------------------------------------

# Each quad's transform is hand-typed into player.tscn. A wrong one puts a screen
# somewhere plausible-looking with nothing to say it moved, which is exactly the
# failure a re-export would introduce. Composed rather than read off the live
# node: BoneAttachment3D only updates once it is in a tree and has processed a
# frame, and the runner calls tests synchronously.
func test_quads_sit_on_their_panels() -> void:
	var root: Node = load("res://scenes/player.tscn").instantiate()
	var skel := root.get_node_or_null("PlayerModel/metarig/Skeleton3D") as Skeleton3D
	if skel == null:
		fail("player.tscn has no PlayerModel/metarig/Skeleton3D")
		root.free()
		return

	for entry in PLACEMENTS:
		var node_name: String = entry[0]
		var attach := root.get_node_or_null(node_name) as BoneAttachment3D
		if attach == null:
			fail("player.tscn is missing the '%s' bone attachment" % node_name)
			continue
		eq(attach.bone_name, entry[1], "%s hangs off the right bone" % node_name)
		check(attach.use_external_skeleton,
			"%s must use an external skeleton, so it stays out of the imported subtree" % node_name)

		var quad := attach.get_node_or_null("Quad") as MeshInstance3D
		if quad == null:
			fail("'%s' has no Quad child" % node_name)
			continue

		var bone := skel.find_bone(entry[1])
		var placed := _bone_global_rest(skel, bone) * quad.transform
		var expected: Vector3 = entry[2]
		check(placed.origin.distance_to(expected) < 0.0005,
			"%s lands at %s, expected %s" % [node_name, str(placed.origin), str(expected)])

		var mesh := quad.mesh as QuadMesh
		if mesh == null:
			fail("'%s/Quad' is not a QuadMesh" % node_name)
			continue
		check(mesh.size.is_equal_approx(entry[3]),
			"%s is %s, expected %s" % [node_name, str(mesh.size), str(entry[3])])

	root.free()

# The rest pose of a bone in skeleton space, walked up by hand so it needs no
# tree and no processed frame.
func _bone_global_rest(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := skel.get_bone_rest(idx)
	var parent := skel.get_bone_parent(idx)
	while parent >= 0:
		t = skel.get_bone_rest(parent) * t
		parent = skel.get_bone_parent(parent)
	return t
