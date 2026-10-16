extends "res://tests/test_case.gd"

# Covers the run arm swing: pilot9's eight run cycles are RC's own with the shoulder, upper-arm
# and lower-arm swing scaled to RUN_ARM_SWING around each joint's average. See
# docs/specs/pilot9-run-arm-swing.md.
#
# What the user asked to keep is what is asserted hardest: the legs (every other track) are the
# addon's key for key, and each arm's apex lands on the same key it did before - the arms stay
# in time with the legs. Checked against scenes/pilot9.tscn, so a builder that forgot to run is
# caught, not just the helper.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")
const ARM_SWING := preload("res://scripts/arm_swing.gd")
const ANGLE_TOL := 0.0005   # radians

func _library() -> AnimationLibrary:
	var root := (load(PILOT_TSCN) as PackedScene).instantiate()
	var ap := root.get_node("AnimationPlayer") as AnimationPlayer
	var lib := ap.get_animation_library(&"")
	root.free()
	return lib

func _bone(anim: Animation, t: int) -> String:
	return str(anim.track_get_path(t)).get_slice(":", 1)

func _is_scaled(anim: Animation, t: int) -> bool:
	return anim.track_get_type(t) == Animation.TYPE_ROTATION_3D \
		and BUILDER.RUN_ARM_BONES.has(_bone(anim, t)) and anim.track_get_key_count(t) >= 2

func test_every_run_clip_is_a_pilot9_copy() -> void:
	var lib := _library()
	eq(BUILDER.RUN_CLIPS.size(), 8, "RC ships eight run cycles and all eight are scaled")
	for name in BUILDER.RUN_CLIPS:
		check(lib.has_animation(name), "library has %s" % name)
		var anim := lib.get_animation(name)
		check(anim.resource_path != BUILDER.RUN_CLIPS[name],
			"%s is the builder's copy, not the addon file" % name)

func test_walk_and_sprint_are_untouched() -> void:
	var lib := _library()
	for name in [&"walk_forward", &"sprint_forward"]:
		if not lib.has_animation(name):
			continue
		check(lib.get_animation(name).resource_path.begins_with("res://addons/real-controller/"),
			"%s is still RC's own clip" % name)

func test_only_the_arms_change_and_timing_holds() -> void:
	var lib := _library()
	for name in BUILDER.RUN_CLIPS:
		var src := load(BUILDER.RUN_CLIPS[name]) as Animation
		var got := lib.get_animation(name)
		eq(got.get_track_count(), src.get_track_count(), "%s track count" % name)
		approx(got.length, src.length, 0.00001, "%s length" % name)
		eq(got.loop_mode, src.loop_mode, "%s loop mode" % name)
		var scaled := 0
		for t in src.get_track_count():
			eq(got.track_get_path(t), src.track_get_path(t), "%s track %d path" % [name, t])
			eq(got.track_get_key_count(t), src.track_get_key_count(t), "%s track %d keys" % [name, t])
			var arm := _is_scaled(src, t)
			if arm:
				scaled += 1
			for k in src.track_get_key_count(t):
				approx(got.track_get_key_time(t, k), src.track_get_key_time(t, k), 0.00001,
					"%s %s key %d time" % [name, _bone(src, t), k])
				if not arm:
					check(got.track_get_key_value(t, k) == src.track_get_key_value(t, k),
						"%s %s key %d unchanged" % [name, _bone(src, t), k])
		eq(scaled, BUILDER.RUN_ARM_BONES.size(), "%s scales all six arm joints" % name)

func test_swing_is_scaled_and_apex_stays_on_its_frame() -> void:
	var lib := _library()
	for name in BUILDER.RUN_CLIPS:
		var src := load(BUILDER.RUN_CLIPS[name]) as Animation
		var got := lib.get_animation(name)
		for t in src.get_track_count():
			if not _is_scaled(src, t):
				continue
			var mid := ARM_SWING.track_mean(src, t)
			var apex_src := -1
			var apex_got := -1
			var best_src := -1.0
			var best_got := -1.0
			for k in src.track_get_key_count(t):
				var a_src := mid.angle_to(src.track_get_key_value(t, k))
				var a_got := mid.angle_to(got.track_get_key_value(t, k))
				approx(a_got, a_src * BUILDER.RUN_ARM_SWING, ANGLE_TOL,
					"%s %s key %d swing" % [name, _bone(src, t), k])
				if a_src > best_src:
					best_src = a_src
					apex_src = k
				if a_got > best_got:
					best_got = a_got
					apex_got = k
			# Two keys can tie for the peak to within float noise (run_backward_right's elbow
			# holds it across two frames), so the scaled apex only has to be a source apex.
			var a_at := mid.angle_to(src.track_get_key_value(t, apex_got))
			check(a_at >= best_src - ANGLE_TOL, "%s %s apex key %d is a source apex (was %d)"
				% [name, _bone(src, t), apex_got, apex_src])
