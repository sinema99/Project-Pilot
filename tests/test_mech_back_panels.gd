extends "res://tests/test_case.gd"

# EXIA's two white back panels. See docs/specs/exia-back-panels.md. Clearance against every clip is
# tests/_probe_mech_panels.gd (slow); the look is tests/_probe_mech_panels_shot.gd.

const MechScene := preload("res://scenes/mech.tscn")
const Panels := preload("res://scripts/mech_back_panels.gd")

var _instances: Array[Node] = []

func _mech_in_tree() -> Node3D:
	var mech: Node3D = MechScene.instantiate()
	_instances.append(mech)
	(Engine.get_main_loop() as SceneTree).root.add_child(mech)
	mech.set_physics_process(false)
	mech.set_process(false)
	return mech

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()

func _attachments(mech: Node3D) -> Array:
	var out := []
	for side: float in [-1.0, 1.0]:
		var n := mech.find_child(Panels.attachment_name(side), true, false)
		if n != null:
			out.append(n)
	return out

func _pose(mech: Node3D, clip: String, t: float) -> void:
	var ap: AnimationPlayer = mech.anim_player
	ap.play(clip)
	ap.seek(t, true)
	ap.pause()
	mech._skeleton.force_update_all_bone_transforms()

func _shoulder(mech: Node3D, attach: BoneAttachment3D) -> Transform3D:
	var skel: Skeleton3D = mech._skeleton
	return mech._panel_skeleton_in_body * skel.get_bone_global_pose(skel.find_bone(attach.bone_name))

# The slab in the body frame, from the scene graph (bone * slab), not from the module's maths.
# Remembers the box's live (cargo-driven) length for _top_front / _bottom_front.
var _len := 7.5

func _slab_in_body(mech: Node3D, attach: BoneAttachment3D) -> Transform3D:
	var full := _shoulder(mech, attach) * (attach.get_child(0) as Node3D).transform
	_len = Panels.length() * full.basis.get_scale().y
	return full.orthonormalized()

func _top_front(xf: Transform3D) -> Vector3:
	return xf * Vector3(0.0, _len * 0.5, Panels.THICKNESS * 0.5)

func _bottom_front(xf: Transform3D) -> Vector3:
	return xf * Vector3(0.0, -_len * 0.5, Panels.THICKNESS * 0.5)

func test_each_box_rides_its_own_shoulder_bone() -> void:
	var mech := _mech_in_tree()
	var attaches := _attachments(mech)
	eq(attaches.size(), 2, "one attachment per shoulder")
	var by_name := {}
	for attach: BoneAttachment3D in attaches:
		check(attach.get_parent() is Skeleton3D, "%s sits on the skeleton" % attach.name)
		check(mech.get_node("Model").is_ancestor_of(attach), "under Model, so ApplyCelMech dresses them")
		eq(attach.get_child_count(), 1, "%s holds one box" % attach.name)
		by_name[String(attach.name)] = attach.bone_name
	eq(by_name.get(Panels.attachment_name(-1.0)), "shoulder.R", "the -X box hangs from the -X shoulder")
	eq(by_name.get(Panels.attachment_name(1.0)), "shoulder.L", "the +X box hangs from the +X shoulder")
	_pose(mech, "MECH_standing", 0.0)
	var skel: Skeleton3D = mech._skeleton
	for side: float in [-1.0, 1.0]:
		var p: Vector3 = mech._panel_skeleton_in_body * skel.get_bone_global_pose(skel.find_bone(Panels.BONES[side])).origin
		check(signf(p.x) == side, "%s is on the side %+.0f box's side (x %.2f)" % [Panels.BONES[side], side, p.x])

func test_the_slabs_are_thick_white_boxes_that_cast_shadows() -> void:
	for attach: BoneAttachment3D in _attachments(_mech_in_tree()):
		var mi := attach.get_child(0) as MeshInstance3D
		check(mi != null and mi.mesh is BoxMesh, "%s holds a box" % attach.name)
		if mi == null:
			continue
		var size: Vector3 = (mi.mesh as BoxMesh).size
		check(is_equal_approx(size.x, 1.0) and is_equal_approx(size.z, 1.0), "1.0 m wide, 1.0 m thick")
		eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s casts shadows" % mi.name)

func test_at_standing_the_slabs_land_where_the_spec_puts_them() -> void:
	var mech := _mech_in_tree()
	_pose(mech, "MECH_standing", 0.0)
	for attach: BoneAttachment3D in _attachments(mech):
		var got := _slab_in_body(mech, attach)
		var n := String(attach.name)
		var top := _top_front(got)
		var bottom := _bottom_front(got)
		check(absf(top.y - 8.0) < 0.01, "%s top level with the pauldrons (y %.3f)" % [n, top.y])
		check(absf(top.z - (-1.20)) < 0.01, "%s top almost touching the body (z %.3f)" % [n, top.z])
		var drop := _len * cos(deg_to_rad(10.0))
		var out := _len * sin(deg_to_rad(10.0))
		check(absf(bottom.y - (8.0 - drop)) < 0.01, "%s bottom swung up (y %.3f)" % [n, bottom.y])
		check(absf(bottom.z - (top.z - out)) < 0.01, "%s bottom 10 deg out (bottom z %.3f, top z %.3f)" % [n, bottom.z, top.z])

# The tilt of a slab's front face against the body frame's up: positive = bottom out.
static func _tilt(xf: Transform3D) -> float:
	var up := xf.basis.y.normalized()
	return rad_to_deg(atan2(up.z, up.y))

# THE RULE (rev 6): through every state the top front edge stays put in its own shoulder's frame,
# and both boxes hold one angle. Driven through mech.gd's own update, read back from the scene graph.
func test_rev6_the_hinge_never_leaves_its_shoulder_and_both_share_the_angle() -> void:
	var mech := _mech_in_tree()
	var ap: AnimationPlayer = mech.anim_player
	_pose(mech, "MECH_standing", 0.0)
	var rest := {}
	for attach: BoneAttachment3D in _attachments(mech):
		var side := -1.0 if String(attach.name).ends_with("L") else 1.0
		rest[String(attach.name)] = _shoulder(mech, attach).affine_inverse() * Panels.hinge_standing(side)
	# [clip, fraction, driving, running, sway]
	var cases := [
		["MECH_standing", 0.0, true, false, 0.0], ["MECH_idle", 0.3, false, false, 0.0],
		["MECH_idle", 0.7, false, false, 0.0], ["MECH_idle", 1.0, false, false, 0.0],
		["MECH_launch", 0.1, false, false, 0.0], ["MECH_launch", 0.25, false, false, 0.0],
		["MECH_launch", 0.6, false, false, 0.0], ["MECH_run", 0.4, true, true, 4.0],
		["MECH_sprint", 0.7, true, true, -3.0], ["MECH_stand_idle", 0.5, true, false, 2.0],
	]
	for c: Array in cases:
		if not ap.has_animation(c[0]):
			continue
		_pose(mech, c[0], ap.get_animation(c[0]).length * float(c[1]))
		mech._panels_driving = c[2]
		mech.loco = mech.Loco.RUN if c[3] else mech.Loco.STAND
		mech._panel_sway = Vector2(c[4], 0.0)
		for i in 30:
			mech._update_back_panels(1.0 / 30.0)
		var tilts := []
		for attach: BoneAttachment3D in _attachments(mech):
			var slab := _slab_in_body(mech, attach)
			var drift := (_shoulder(mech, attach).affine_inverse() * _top_front(slab)).distance_to(rest[String(attach.name)])
			check(drift < 0.001, "%s @%.2f: %s hinge stays on its shoulder (drift %.4f)" % [c[0], c[1], attach.name, drift])
			tilts.append(_tilt(slab))
		check(absf(tilts[0] - tilts[1]) < 0.01, "%s @%.2f: one angle (L %.2f, R %.2f)" % [c[0], c[1], tilts[0], tilts[1]])

func test_rev6_the_angle_rules() -> void:
	eq(Panels.angle(0.0, 0.0, 0.0, 0.0, Panels.NO_FLOOR), 10.0, "standing 10")
	eq(Panels.angle(1.0, 0.0, 0.0, 0.0, Panels.NO_FLOOR), 25.0, "running 25")
	eq(Panels.angle(0.0, 0.0, 4.0, 0.0, Panels.NO_FLOOR), 14.0, "sway adds to the pose")
	eq(Panels.angle(0.0, 1.0, 4.0, 50.0, Panels.NO_FLOOR), 50.0, "fully parked: the kickstand, sway faded out")
	eq(Panels.angle(0.0, 0.0, -3.0, 0.0, 30.0), 30.0, "the clearance is a floor sway can't swing in past")
	eq(Panels.angle(1.0, 0.0, 5.0, 0.0, 20.0), 30.0, "above the floor the pose wins")

func test_rev6_the_kickstand_puts_the_bottom_on_the_ground() -> void:
	for h: float in [3.0, 4.96, 6.5]:
		var slab := Panels.hung(Vector3(0.0, h, -1.0), Panels.kickstand_deg(h))
		var lowest := INF
		for sx: float in [-0.5, 0.5]:
			for sz: float in [-0.5, 0.5]:
				lowest = minf(lowest, (slab * Vector3(sx * Panels.WIDTH, -Panels.length() * 0.5, sz * Panels.THICKNESS)).y)
		check(absf(lowest) < 0.001, "hinge %.2f m up: bottom on the ground (lowest %.4f)" % [h, lowest])
	eq(Panels.kickstand_deg(9.0), 0.0, "a hinge above the box's length hangs straight")

func test_rev6_parked_the_lower_box_rests_on_the_floor_and_none_goes_below() -> void:
	var mech := _mech_in_tree()
	_pose(mech, "MECH_idle", mech.anim_player.get_animation("MECH_idle").length)
	mech._panels_driving = false
	for i in 30:
		mech._update_back_panels(1.0 / 30.0)
	var lows := []
	for attach: BoneAttachment3D in _attachments(mech):
		lows.append(_bottom_front(_slab_in_body(mech, attach)).y)
	var low := minf(lows[0], lows[1])
	check(low > -0.01, "no box below the floor (%.3f, %.3f)" % [lows[0], lows[1]])
	# 2026-11-13: the kickstand is the FULL-length angle whatever the cargo length, so a short box
	# splays out the same way instead of hanging straight down.
	var lowest := INF
	for attach: BoneAttachment3D in _attachments(mech):
		var sh: Transform3D = mech._panel_skeleton_in_body * mech._skeleton.get_bone_global_pose(mech._skeleton.find_bone(attach.bone_name))
		lowest = minf(lowest, Panels.hinge(sh, attach.get_meta("hinge_offset")).y)
	var want := Panels.kickstand_deg(lowest)
	check(want > 20.0, "the full-length kickstand splays the box (%.1f deg)" % want)
	for attach: BoneAttachment3D in _attachments(mech):
		var t := _tilt(_slab_in_body(mech, attach))
		check(absf(t - want) < 0.5, "parked at the kickstand %.1f deg whatever the length (%.1f)" % [want, t])

func test_rev4_kneel_follows_the_power_down_and_boot_up() -> void:
	eq(Panels.kneel_target("MECH_idle", 0.0, 1.0, true), 0.0, "power-down starts upright")
	eq(Panels.kneel_target("MECH_idle", 1.0, 1.0, true), 1.0, "power-down ends knelt")
	eq(Panels.kneel_target("MECH_launch", 0.0, 1.0, false), 1.0, "boot-up starts knelt")
	eq(Panels.kneel_target("MECH_launch", 1.0, 1.0, false), 0.0, "boot-up ends upright")
	eq(Panels.kneel_target("", 0.0, 0.0, true), 1.0, "parked hold stays knelt")
	eq(Panels.kneel_target("", 0.0, 0.0, false), 0.0, "an ended one-shot while driving is not the kneel")
	eq(Panels.kneel_target("MECH_run", 0.3, 1.0, false), 0.0, "running is not the kneel")

func test_rev4_run_swing_times() -> void:
	var lin := 0.0
	for i in 25:
		lin = Panels.step_run(lin, true, 0.01)
	check(is_equal_approx(lin, 1.0), "out to the run tilt in 0.25 s (%.3f)" % lin)
	for i in 20:
		lin = Panels.step_run(lin, false, 0.01)
	check(absf(lin - 0.5) < 0.001, "halfway back after 0.2 of 0.4 s (%.3f)" % lin)

func test_the_mech_still_boots_powered_down() -> void:
	var mech := _mech_in_tree()
	eq(mech.anim_player.current_animation, "MECH_idle", "reading the standing chest does not leave it standing")

func test_rev6_the_clearance_floor_only_through_power_down_and_boot_up() -> void:
	eq(Panels.clearance_for("MECH_run", 0.5), Panels.NO_FLOOR, "no floor outside the two parked clips")
	for clip in ["MECH_idle", "MECH_launch"]:
		check(Panels.CLEARANCE.has(clip), "%s has a baked table" % clip)
	for clip in Panels.CLEARANCE:
		var table: Array = Panels.CLEARANCE[clip]
		eq(table.size(), 41, "%s table has 41 samples" % clip)
		for v in table:
			check(float(v) >= 0.0 and float(v) < 90.0, "%s floor %.2f is an angle" % [clip, v])
	var script := Panels as GDScript
	check(not script.get_script_constant_map().has("PUSH"), "nothing slides a box any more")

# --- Rev 5: the heavy swing ---

func _run_sway(state: Vector2, drive: float, seconds: float) -> Vector2:
	for i in int(round(seconds * 60.0)):
		state = Panels.step_sway(state, drive, 1.0 / 60.0)
	return state

func test_rev5_steady_acceleration_settles_at_the_static_lag() -> void:
	var st := _run_sway(Vector2.ZERO, 10.0, 6.0)
	check(absf(st.x - 3.0) < 0.05, "10 m/s^2 settles 3 deg out (%.3f)" % st.x)

func test_rev5_a_start_overshoots_once_then_settles() -> void:
	var st := Vector2.ZERO
	var peak := 0.0
	var trough := INF
	var t := 0.0
	# 0.6 s of 10 m/s^2 speeding up, then cruising.
	while t < 5.0:
		st = Panels.step_sway(st, 10.0 if t < 0.6 else 0.0, 1.0 / 60.0)
		t += 1.0 / 60.0
		peak = maxf(peak, st.x)
		if t > 0.6:
			trough = minf(trough, st.x)
	check(peak > 2.0 and peak <= Panels.SWAY_OUT_CAP_DEG * Panels.SWAY_HARD_CLAMP, "lags out on the start (%.2f)" % peak)
	check(trough < -0.2, "swings back past rest once (%.2f)" % trough)
	check(absf(st.x) < 0.1 and absf(st.y) < 0.5, "settled by 5 s (%.3f, %.3f)" % [st.x, st.y])

func test_rev5_a_hard_stop_thunks_against_the_back_cushion() -> void:
	var st := Vector2.ZERO
	var lowest := 0.0
	for i in 60:
		st = Panels.step_sway(st, -Panels.SWAY_ACCEL_CLAMP, 1.0 / 60.0)
		lowest = minf(lowest, st.x)
	check(lowest < -Panels.SWAY_IN_CAP_DEG, "carries past the soft cap (%.2f)" % lowest)
	check(lowest >= -Panels.SWAY_IN_CAP_DEG * Panels.SWAY_HARD_CLAMP, "never past the hard clamp (%.2f)" % lowest)
	st = _run_sway(st, 0.0, 0.5)
	check(st.x > -Panels.SWAY_IN_CAP_DEG, "comes off the back once the stop is over (%.2f)" % st.x)

func test_rev5_kicks_are_inward_and_the_landing_is_biggest() -> void:
	check(Panels.footfall_kick(true) < 0.0, "a footfall thumps inward")
	check(absf(Panels.footfall_kick(false)) < absf(Panels.footfall_kick(true)), "the run thumps less than the sprint")
	check(absf(Panels.land_kick(3.0, 3.0)) > absf(Panels.SWAY_TAKEOFF_KICK), "a jump's landing beats its take-off")
	check(absf(Panels.SWAY_TAKEOFF_KICK) > absf(Panels.footfall_kick(true)), "take-off beats a footfall")
	var st := _run_sway(Vector2(0.0, Panels.footfall_kick(true)), 0.0, 3.0)
	check(absf(st.x) < 0.05, "a thump dies out (%.3f)" % st.x)

func test_rev5_turns_only_swing_out_and_spikes_are_clamped() -> void:
	eq(Panels.sway_drive(0.0, 10.0), Panels.sway_drive(0.0, -10.0), "left and right turns swing the same way")
	check(Panels.sway_drive(0.0, 10.0) > 0.0, "out")
	var a := Panels.smooth_accel(0.0, -540.0, 1.0 / 60.0)
	check(a >= -Panels.SWAY_ACCEL_CLAMP, "the instant stop's one-tick spike is clamped (%.2f)" % a)

# --- Cargo length (2026-11-13): the panels shrink with the stash fill, in 4 steps -------------------

func test_cargo_empty_is_a_one_metre_cube_never_zero() -> void:
	eq(Panels.length_for_fill(0.0), 1.0, "empty = 1 m")
	check(Panels.length_for_fill(0.0) == Panels.THICKNESS and Panels.WIDTH == Panels.THICKNESS, "a cube")

func test_cargo_steps() -> void:
	var a := Panels.length_for_fill(0.01)
	var b := Panels.length_for_fill(0.5)
	var c := Panels.length_for_fill(0.9)
	check(a > 1.0 and a < b and b < c, "each step is longer (%.2f %.2f %.2f)" % [a, b, c])
	eq(c, Panels.length(), "over two thirds is the full length")
	eq(Panels.length_for_fill(0.33), a, "up to a third is step one")
	eq(Panels.length_for_fill(0.66), b, "up to two thirds is step two")
	eq(Panels.length_for_fill(1.0), Panels.length(), "full")

func test_cargo_fill_counts_occupied_cells() -> void:
	var g := ItemGrid.new(10, 12)
	eq(Panels.fill_fraction(g), 0.0, "empty grid")
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("/root/Inventory")
	if inv != null:
		var full := Inventory_seed()
		check(Panels.fill_fraction(full) > 0.0, "the seeded stash is not empty")

func Inventory_seed() -> ItemGrid:
	var g := ItemGrid.new(10, 12)
	Engine.get_main_loop().root.get_node("/root/Inventory").seed_stash(g)
	return g

func test_cargo_hinge_stays_put_while_it_shrinks() -> void:
	var hinge := Vector3(1.75, 8.0, -1.2)
	for len in [1.0, 3.2, 7.5]:
		var t := Panels.hung(hinge, 10.0, len)
		var top_front := t * Vector3(0.0, Panels.length() * 0.5, Panels.THICKNESS * 0.5)
		check(top_front.distance_to(hinge) < 0.001, "hinge fixed at len %.1f (%s)" % [len, top_front])
