extends "res://tests/test_case.gd"

# docs/specs/cutscene-cockpit.md. Timing, a static camera, framing, the seated pose landing on the
# seat's targets, and everything inside the screen sphere. How it looks is judged by eye
# (tests/_probe_cockpit_shot.gd).

const SCENE := "res://scenes/cockpit.tscn"
const ASPECT := 16.0 / 9.0


func _shot() -> Node3D:
	var s: Node3D = (load(SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func _at(s: Node3D, t: float) -> void:
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	ap.pause()
	ap.seek(t, true)


func _ndc(cam: Camera3D, p: Vector3) -> Vector2:
	var local := cam.global_transform.affine_inverse() * p
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	return Vector2(local.x / -local.z / (tan_v * ASPECT), local.y / -local.z / tan_v)


func _skel(s: Node3D) -> Skeleton3D:
	return s.get_node("Seat/Pilot/Armature/GeneralSkeleton")


func _seat(s: Node3D) -> CockpitSeat:
	return s.get_node("Seat")


# World position of a bone with the solved seated pose.
func _bone(s: Node3D, pose: Dictionary, name: StringName) -> Vector3:
	var skel := _skel(s)
	return skel.global_transform * SeatedPose.bone_position(skel, pose, name)


func _reentry(s: Node3D) -> CockpitReentry:
	return s.get_node("Reentry")


func _pose(s: Node3D) -> Dictionary:
	var mod: SeatedPose = _skel(s).get_node("SeatedPose")
	return mod.solve(_skel(s), _seat(s))


func test_root_is_named_cockpit() -> void:
	var s := _shot()
	eq(s.name, "Cockpit", "root node")
	s.free()


func test_shot_is_eight_seconds_and_autoplays() -> void:
	var s := _shot()
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	approx(ap.get_animation(&"shot").length, 8.0, 0.001, "8 s shot")
	eq(ap.current_animation, "shot", "plays on load")
	check(not ap.get_animation(&"shot").loop_mode, "plays once")
	s.free()


func test_finished_fires_at_the_end() -> void:
	var s := _shot()
	var fired := [false]
	s.connect(&"finished", func() -> void: fired[0] = true)
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	ap.seek(7.99, true)
	ap.advance(0.05)
	check(fired[0], "finished emitted")
	s.free()


# The camera only trembles: a tenth of the seat's shake, never more than a centimetre or so.
func test_camera_only_trembles() -> void:
	var s := _shot()
	var cam: Camera3D = s.get_node("Camera3D")
	var re := _reentry(s)
	re.apply(0.0)
	var start := cam.global_transform
	var t := 0.0
	while t < 5.0:
		re.apply(t)
		var moved := cam.global_position.distance_to(start.origin)
		check(moved < 0.012, "camera within 12 mm at %.2f s (%.4f)" % [t, moved])
		var turned := rad_to_deg(cam.global_basis.z.angle_to(start.basis.z))
		check(turned < 0.6, "camera within 0.6 deg at %.2f s (%.2f)" % [t, turned])
		t += 0.05
	s.free()


# The sketch's direction: high, from his front-left, looking down.
func test_camera_is_high_front_left_looking_down() -> void:
	var s := _shot()
	var cam: Camera3D = s.get_node("Camera3D")
	var seat := _seat(s)
	var rel := seat.global_transform.affine_inverse() * cam.global_position
	check(rel.x > 0.5, "on his left (%.2f)" % rel.x)
	check(rel.z > 0.5, "in front of him (%.2f)" % rel.z)
	check(rel.y > 1.5, "above him (%.2f)" % rel.y)
	var pitch := rad_to_deg(asin(-cam.global_basis.z.normalized().y))
	check(pitch < -25.0 and pitch > -45.0, "looking down about 35 deg (%.1f)" % pitch)
	s.free()


# Whole seat in frame (the sketch's distance), and his head too.
func test_seat_and_head_in_frame() -> void:
	var s := _shot()
	var cam: Camera3D = s.get_node("Camera3D")
	for part in _seat(s).get_children():
		if part is MeshInstance3D:
			var aabb: AABB = (part as MeshInstance3D).get_aabb()
			for i in 8:
				var p := _ndc(cam, (part as MeshInstance3D).global_transform * aabb.get_endpoint(i))
				check(absf(p.x) < 1.0 and absf(p.y) < 1.0, "%s in frame (%.2f, %.2f)" % [part.name, p.x, p.y])
	var head := _ndc(cam, _bone(s, _pose(s), &"Head"))
	check(absf(head.x) < 0.8 and absf(head.y) < 0.8, "head well inside the frame")
	s.free()


func test_hips_on_the_seat() -> void:
	var s := _shot()
	var seat := _seat(s)
	var hips := _bone(s, _pose(s), &"Hips")
	check(hips.distance_to(seat.global_transform * seat.hip_target) < 0.01, "hips at the hip point")
	s.free()


func test_wrists_on_the_grips_and_feet_on_the_footrest() -> void:
	var s := _shot()
	var seat := _seat(s)
	var pose := _pose(s)
	var x := seat.global_transform
	var pairs := {
		&"LeftHand": seat.left_wrist_target, &"RightHand": seat.right_wrist_target,
		&"LeftFoot": seat.left_foot_target, &"RightFoot": seat.right_foot_target,
	}
	for bone: StringName in pairs:
		var d := _bone(s, pose, bone).distance_to(x * pairs[bone])
		check(d < 0.02, "%s on its target (%.3f m off)" % [bone, d])
	s.free()


# Knees bend up and forward, elbows out and down: not inverted limbs.
func test_knees_forward_elbows_down() -> void:
	var s := _shot()
	var pose := _pose(s)
	var inv := _seat(s).global_transform.affine_inverse()
	for side: String in ["Left", "Right"]:
		var hip := inv * _bone(s, pose, StringName(side + "UpperLeg"))
		var knee := inv * _bone(s, pose, StringName(side + "LowerLeg"))
		var shoulder := inv * _bone(s, pose, StringName(side + "UpperArm"))
		var elbow := inv * _bone(s, pose, StringName(side + "LowerArm"))
		check(knee.z > hip.z + 0.3, "%s knee ahead of the hip" % side)
		check(elbow.y < shoulder.y - 0.2, "%s elbow below the shoulder" % side)
	s.free()


# Face level: the head's up axis within a few degrees of the seat's up.
func test_head_level() -> void:
	var s := _shot()
	var skel := _skel(s)
	var pose := _pose(s)
	var neck := _bone(s, pose, &"Neck")
	var head := _bone(s, pose, &"Head")
	var tilt := rad_to_deg((head - neck).angle_to(_seat(s).global_basis.y))
	check(tilt < 8.0, "head upright (%.1f deg)" % tilt)
	check(skel != null, "skeleton")
	s.free()


func test_everything_inside_the_sphere() -> void:
	var s := _shot()
	var sphere: WireSphere = s.get_node("ScreenSphere")
	var r := sphere.radius
	var c := sphere.global_position
	var cam: Camera3D = s.get_node("Camera3D")
	check(cam.global_position.distance_to(c) < r - 0.5, "camera inside")
	for part in _seat(s).get_children():
		if part is MeshInstance3D:
			var aabb: AABB = (part as MeshInstance3D).get_aabb()
			for i in 8:
				var p := (part as MeshInstance3D).global_transform * aabb.get_endpoint(i)
				check(p.distance_to(c) < r - 1.0, "%s inside" % part.name)
	var pose := _pose(s)
	for b in [&"mixamorig_HeadTop_End", &"LeftFoot", &"RightFoot", &"LeftHand", &"RightHand"]:
		check(_bone(s, pose, b).distance_to(c) < r - 1.0, "%s inside" % b)
	s.free()


func test_no_staff() -> void:
	var s := _shot()
	eq(s.find_children("*", "ItemHolder", true, false).size(), 0, "no item holder")
	for n in s.find_children("*", "", true, false):
		check(not String(n.name).to_lower().contains("staff"), "no staff node (%s)" % n.name)
	s.free()


func test_welded_normals_close_box_corners() -> void:
	var verts := PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var normals := PackedVector3Array([Vector3.RIGHT, Vector3.UP, Vector3.BACK])
	var w := CockpitSeat.welded_normals(verts, normals)
	for n in w:
		check(n.is_equal_approx(Vector3.ONE.normalized()), "corner normal on the diagonal")


# Glass screen: the wireframe's lines stay, dimmed to dark seams over the re-entry fire.
func test_screen_is_a_dim_wireframe() -> void:
	var s := _shot()
	var sphere: WireSphere = s.get_node("ScreenSphere")
	var m := sphere.mesh as ArrayMesh
	eq(m.get_surface_count(), 1, "one surface")
	eq(m.surface_get_primitive_type(0), Mesh.PRIMITIVE_LINES, "lines, no faces")
	eq(sphere.segments, 32, "32 segments")
	eq(sphere.rings, 16, "16 rings")
	var line := (m.surface_get_material(0) as StandardMaterial3D).albedo_color
	check(line.get_luminance() < 0.15, "dark seams")
	s.free()


# Re-entry fire on the screen: just outside the wire, from a hot point off screen lower left (ahead of
# the seat) to its antipode off screen upper right, so the flow runs up and right along the seat.
func test_fire_flows_left_to_right_round_the_sphere() -> void:
	var s := _shot()
	var fire: ReentryFire = s.get_node("ScreenFire")
	var sphere: WireSphere = s.get_node("ScreenSphere")
	check(fire.global_position.is_equal_approx(sphere.global_position), "same centre as the wire")
	check(fire.radius > sphere.radius, "fire behind the wire lines")
	var cam: Camera3D = s.get_node("Camera3D")
	var src := fire.global_transform * (fire.source_direction.normalized() * fire.radius)
	var sink := fire.global_transform * (-fire.source_direction.normalized() * fire.radius)
	var right := cam.global_basis.x
	var src_local := cam.global_transform.affine_inverse() * src
	var sink_local := cam.global_transform.affine_inverse() * sink
	check(src_local.x < 0.0 and src_local.y < 0.0, "source lower left")
	check(sink_local.x > 0.0 and sink_local.y > 0.0, "sink upper right")
	check((sink - src).dot(right) > 0.0, "flow runs left to right")
	check((sink - src).dot(cam.global_basis.y) > 0.0, "flow runs up")
	var seat_fwd := _seat(s).global_basis.z
	check(fire.source_direction.normalized().dot(seat_fwd) > 0.8, "hot point ahead of the seat")
	s.free()


# ------------------------------------------------------------- re-entry read: wake, dropouts, push

# The fire's middle is in front of him, off screen left: no white core in the bottom of the shot.
func test_hot_core_in_front_of_him_off_screen() -> void:
	var s := _shot()
	var fire: ReentryFire = s.get_node("ScreenFire")
	var cam: Camera3D = s.get_node("Camera3D")
	var n := _ndc(cam, fire.global_transform * (fire.source_direction.normalized() * fire.radius))
	check(n.x < -1.0 or absf(n.y) > 1.0, "core off screen (%.2f, %.2f)" % [n.x, n.y])
	s.free()


# The wake opens through the shot and closes as the ship answers the push; the blue rim goes with it.
func test_fire_swallows_the_wake_on_the_push() -> void:
	var s := _shot()
	var re := _reentry(s)
	var fire: ReentryFire = s.get_node("ScreenFire")
	var rim: DirectionalLight3D = s.get_node("WakeRim")
	eq(fire.rim_light, rim, "rim wired to the fire")
	check(rim.light_color.b > rim.light_color.r * 1.5, "rim is cool blue")
	check(rim.global_basis.z.dot(_seat(s).global_basis.z) < -0.5, "rim comes from behind him (the wake)")
	re.apply(6.8)
	approx(fire.swallow, 0.0, 1e-6, "wake open until the ship answers")
	approx(float(fire.get_param(&"swallow")), 0.0, 1e-6, "on the screen too")
	check(rim.visible and rim.light_energy > 0.5, "rim lit")
	re.apply(7.12)
	check(fire.swallow > 0.3 and fire.swallow < 0.7, "closing over about half a second (%.2f)" % fire.swallow)
	re.apply(7.5)
	approx(fire.swallow, 1.0, 1e-6, "closed")
	approx(float(fire.get_param(&"swallow")), 1.0, 1e-6, "screen closed")
	check(not rim.visible, "rim gone with the wake")
	s.free()


# Each jolt knocks out 3-6 panels in frame for 2-4 frames; the push throws a burst of 8. Clean between.
func test_jolts_drop_panels_in_frame() -> void:
	var s := _shot()
	var re := _reentry(s)
	var fire: ReentryFire = s.get_node("ScreenFire")
	var sphere: WireSphere = s.get_node("ScreenSphere")
	eq(ReentryFire.GRID_SEGMENTS, sphere.segments, "panels are the wire grid's columns")
	eq(ReentryFire.GRID_RINGS, sphere.rings, "and its rows")
	eq(re.drop_events.size(), 4, "three jolts and the push")
	for i in re.drop_events.size():
		var e: Dictionary = re.drop_events[i]
		var count: int = e.drops.size()
		if i < 3:
			check(count >= 3 and count <= 6, "jolt %d: 3-6 panels (%d)" % [i, count])
		else:
			approx(e.time, 6.67, 1e-3, "burst on the push")
			eq(count, 8, "8 on the push")
		for d: Vector4 in e.drops:
			check(d.z >= 0.0 and d.z <= 2.0, "black, no signal or shifted")
			check(d.w >= 2.0 / 60.0 - 1e-4 and d.w <= 5.0 / 60.0 + 1e-4, "a few frames")
	re.apply(1.0)
	eq(int(fire.get_param(&"drop_count")), 0, "clean before the first jolt")
	re.apply(1.21)
	check(int(fire.get_param(&"drop_count")) >= 3, "panels out on the jolt")
	approx(float(fire.get_param(&"drop_age")), 0.01, 1e-3, "aged from the jolt")
	re.apply(1.5)
	var age := float(fire.get_param(&"drop_age"))
	for d: Vector4 in re.drop_events[0].drops:
		check(age >= d.w, "every panel back by 0.3 s")
	s.free()


# The push lean: winds up before the key, drives with the sticks, pressed back when the ship answers.
func test_push_lean_winds_up_drives_and_presses_back() -> void:
	var s := _shot()
	var b := _reentry(s).beats
	approx(b.lean(6.3), 0.0, 1e-6, "still in the pause")
	check(b.lean(6.5) > deg_to_rad(5.0), "winding up before the push (%.1f)" % rad_to_deg(b.lean(6.5)))
	approx(b.lean(6.67), deg_to_rad(18.0), 1e-4, "18 deg at the key")
	check(b.head_look(6.67).x > deg_to_rad(7.0), "head tucked")
	approx(b.stick_angle(6.92), deg_to_rad(20.0), 1e-4, "sticks forward in 0.25 s")
	check(b.lean(6.87) > deg_to_rad(21.0), "drives to 22 deg (%.1f)" % rad_to_deg(b.lean(6.87)))
	approx(b.lean(7.5), deg_to_rad(12.0), 1e-4, "pressed back to 12 deg")
	approx(b.lean(7.99), deg_to_rad(12.0), 1e-4, "held to the end")
	approx(b.left_wrist(6.5).distance_to(b.wrist_rest), 0.0, 1e-6, "hand already back on the stick")
	s.free()


# The fill light shines from the hot point and flickers with the fire; ambient is warm.
func test_fire_lights_the_cockpit() -> void:
	var s := _shot()
	var fire: ReentryFire = s.get_node("ScreenFire")
	var fill: Light3D = s.get_node("FireFill")
	eq(fire.fill_light, fill, "fill wired to the fire")
	fire._ready()
	var toward_center := -fill.global_basis.z
	var from_src := (fire.global_position - fire.global_transform * fire.source_direction.normalized()).normalized()
	check(toward_center.dot(from_src) > 0.99, "fill comes from the hot point")
	fire._process(0.37)
	approx(fill.light_energy, fire.fill_energy * ReentryFire.flicker_at(0.37, fire.flicker_amount), 1e-4, "fill flickers with the fire")
	check(fill.light_color.r > fill.light_color.b * 2.0, "fill is warm")
	var env: Environment = (s.get_node("WorldEnvironment") as WorldEnvironment).environment
	var amb := env.ambient_light_color
	check(amb.r > amb.g and amb.g > amb.b, "orange ambient")
	s.free()


# ---------------------------------------------------------------- atmosphere pass

# Three jolts, read off the shot's method keys: medium, small, big, the big one last.
func test_jolts_come_from_the_shot_track() -> void:
	var s := _shot()
	var j := _reentry(s).shake.jolts
	eq(j.size(), 3, "three jolts")
	var times := [1.2, 2.9, 4.1]
	for i in 3:
		approx(j[i].time, times[i], 0.001, "jolt %d time" % i)
	check(j[1].strength < j[0].strength and j[0].strength < j[2].strength, "medium, small, big")
	s.free()


# Between jolts the seat only buzzes (millimetres); on a jolt it kicks by centimetres and settles.
func test_seat_buzzes_and_jolts() -> void:
	var s := _shot()
	var sh := _reentry(s).shake
	var quiet := 0.0
	var t := 0.0
	while t < 1.15:
		quiet = maxf(quiet, (sh.seat_offset(t) * CockpitShake.PIVOT).distance_to(CockpitShake.PIVOT))
		t += 0.01
	check(quiet > 0.001 and quiet < 0.012, "buzz is millimetres (%.4f m)" % quiet)
	var big := 0.0
	t = 4.1
	while t < 4.3:
		big = maxf(big, (sh.seat_offset(t) * CockpitShake.PIVOT).distance_to(CockpitShake.PIVOT))
		t += 0.005
	check(big > 0.035 and big < 0.07, "big jolt kicks about 5 cm (%.3f m)" % big)
	var after := (sh.seat_offset(4.5) * CockpitShake.PIVOT).distance_to(CockpitShake.PIVOT)
	check(after < 0.012, "settled by 0.4 s after (%.4f m)" % after)
	s.free()


# Deterministic: the same time gives the same frame, so R replays it exactly.
func test_shake_is_deterministic() -> void:
	var s := _shot()
	var sh := _reentry(s).shake
	for t in [0.3, 1.25, 4.13]:
		check(sh.seat_offset(t).is_equal_approx(sh.seat_offset(t)), "seat at %.2f" % t)
		check(sh.body_sway(t) == sh.body_sway(t), "body at %.2f" % t)
	s.free()


# The seat (and him with it) moves; his hands stay on the grips and his feet on the footrest while
# his spine is thrown.
func test_hands_and_feet_stay_pinned_mid_jolt() -> void:
	var s := _shot()
	var re := _reentry(s)
	re.apply(4.14)
	var mod: SeatedPose = _skel(s).get_node("SeatedPose")
	check(mod.body_sway.length() > deg_to_rad(2.0), "spine thrown (%.1f deg)" % rad_to_deg(mod.body_sway.length()))
	var seat := _seat(s)
	var pose := _pose(s)
	var x := seat.global_transform
	var pairs := {
		&"LeftHand": seat.left_wrist_target, &"RightHand": seat.right_wrist_target,
		&"LeftFoot": seat.left_foot_target, &"RightFoot": seat.right_foot_target,
	}
	for bone: StringName in pairs:
		var d := _bone(s, pose, bone).distance_to(x * pairs[bone])
		check(d < 0.02, "%s pinned mid-jolt (%.3f m off)" % [bone, d])
	s.free()


# On a jolt his head is thrown opposite the kick, further than the seat moved, then swings back.
func test_head_thrown_opposite_the_kick() -> void:
	var s := _shot()
	var re := _reentry(s)
	var j: Dictionary = re.shake.jolts[2]
	var side := Vector3(j.dir.x, 0.0, j.dir.z).normalized()
	re.apply(j.time - 0.01)
	var head0 := _seat(s).global_transform.affine_inverse() * _bone(s, _pose(s), &"Head")
	var peak := 0.0
	var back := 0.0
	var t: float = j.time
	while t < j.time + 0.6:
		re.apply(t)
		var head := _seat(s).global_transform.affine_inverse() * _bone(s, _pose(s), &"Head")
		var along := (head - head0).dot(side)
		peak = minf(peak, along)
		back = maxf(back, along)
		t += 0.01
	check(peak < -0.02, "head thrown opposite the kick (%.3f m)" % peak)
	check(back > 0.0, "and overshoots back (%.3f m)" % back)
	s.free()


# The panels ride the seat but trail it: on a jolt they lag a few centimetres, then catch up.
func test_panels_trail_the_seat() -> void:
	var s := _shot()
	var sh := _reentry(s).shake
	var lag := 0.0
	var t := 4.1
	while t < 4.6:
		var seat_p := sh.seat_offset(t) * Vector3(0, 1.0, 0.5)
		var panel_p := sh.panel_offset(t) * Vector3(0, 1.0, 0.5)
		lag = maxf(lag, seat_p.distance_to(panel_p))
		t += 0.005
	check(lag > 0.005 and lag < 0.06, "panels lag a few cm (%.3f m)" % lag)
	var settled := (sh.seat_offset(4.9) * Vector3.ZERO).distance_to(sh.panel_offset(4.9) * Vector3.ZERO)
	check(settled < 0.01, "caught up (%.4f m)" % settled)
	s.free()


# Four panels, all in frame and in front of him, none covering his face from the camera.
func test_panels_in_frame_clear_of_his_face() -> void:
	var s := _shot()
	var cam: Camera3D = s.get_node("Camera3D")
	var holo: CockpitHolo = s.get_node("Holo")
	eq(holo.panels.size(), 4, "four panels")
	var head := _bone(s, _pose(s), &"Head")
	var head_ndc := _ndc(cam, head)
	var head_dist := cam.global_position.distance_to(head)
	for p in holo.panels:
		var half := p.panel_size * 0.5
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for corner in [Vector3(-half.x, -half.y, 0), Vector3(half.x, -half.y, 0), Vector3(-half.x, half.y, 0), Vector3(half.x, half.y, 0)]:
			var n := _ndc(cam, p.global_transform * corner)
			check(absf(n.x) < 1.0 and absf(n.y) < 1.0, "%s corner in frame (%.2f, %.2f)" % [p.name, n.x, n.y])
			lo = lo.min(n)
			hi = hi.max(n)
		var local := _seat(s).global_transform.affine_inverse() * p.global_position
		check(local.z > 0.3, "%s in front of him" % p.name)
		var covers := head_ndc.x > lo.x and head_ndc.x < hi.x and head_ndc.y > lo.y and head_ndc.y < hi.y \
				and cam.global_position.distance_to(p.global_position) < head_dist
		check(not covers, "%s clear of his face" % p.name)
	s.free()


# Every panel faces his head; the readouts count down; red only on the jolts.
func test_panels_read_the_descent() -> void:
	var s := _shot()
	var holo: CockpitHolo = s.get_node("Holo")
	var head := _bone(s, _pose(s), &"Head")
	for p in holo.panels:
		var to_head := (head - p.global_position).normalized()
		var d := p.global_basis.z.normalized().dot(to_head)
		check(d > 0.97, "%s faces his head (%.3f)" % [p.name, d])
	check(HoloDisplay.altitude_at(4.0) < HoloDisplay.altitude_at(0.0), "altitude counts down")
	check(HoloDisplay.speed_at(4.0) < HoloDisplay.speed_at(0.0), "speed bleeds off")
	var sh := _reentry(s).shake
	approx(sh.flash(1.0), 0.0, 1e-6, "no red before the first jolt")
	check(sh.flash(1.21) > 0.9, "red on the jolt")
	check(sh.flash(2.2) < 0.15, "faded back to green")
	eq(sh.glitch(1.22), 1.0, "panels tear on the jolt")
	eq(sh.glitch(1.4), 0.0, "and only for a frame or two")
	check(HoloDisplay.heat_at(1.21, sh.flash(1.21)) > HoloDisplay.heat_at(1.19, sh.flash(1.19)) + 0.2, "heat spikes")
	s.free()


# Each jolt flares the fire and pumps the fill; the alarm lamp lights; the big one throws sparks.
func test_jolts_flare_fire_lamps_and_sparks() -> void:
	var s := _shot()
	var re := _reentry(s)
	var fire: ReentryFire = s.get_node("ScreenFire")
	re.apply(1.0)
	approx(fire.flare, 0.0, 1e-6, "no flare before")
	re.apply(1.25)
	check(fire.flare > 0.4, "flare on the jolt (%.2f)" % fire.flare)
	var lamp := (_seat(s).get_node("LegButtonL2") as MeshInstance3D).material_override as StandardMaterial3D
	check(lamp != null and lamp.albedo_color.r > 0.6, "alarm lamp lit")
	re.apply(2.4)
	check(lamp.albedo_color.r < 0.4, "alarm lamp dark between jolts")
	check(re.sparks != null and not re.sparks.emitting, "no sparks yet")
	re.jolt(0.6)
	check(not re.sparks.emitting, "not on a medium jolt")
	re.jolt(1.0)
	check(re.sparks.emitting, "sparks on the big jolt")
	s.free()


# The drifting fire light moves over the shot.
func test_fire_light_drifts() -> void:
	var s := _shot()
	var re := _reentry(s)
	var light: OmniLight3D = s.get_node("FireDrift")
	re.apply(0.0)
	var a := light.global_position
	re.apply(2.5)
	check(light.global_position.distance_to(a) > 0.2, "drifts")
	check(light.light_color.r > light.light_color.b * 2.0, "warm")
	s.free()


# --------------------------------------------------------------- ending: warning swipe and push

# The ending's two keys come off the shot track: the warning with the big jolt, the push after it.
func test_ending_keys_come_from_the_shot_track() -> void:
	var s := _shot()
	var b := _reentry(s).beats
	approx(b.warning_time, 4.1, 1e-4, "warning on the big jolt")
	approx(b.push_time, 6.67, 1e-4, "push key")
	approx(_reentry(s).shake.surge_time, 6.87, 1e-4, "ship answers 0.2 s after the push")
	s.free()


# Hidden until the big jolt, pops open from a line, then flicked away and gone before the push.
func test_warning_pops_up_and_is_flicked_away() -> void:
	var s := _shot()
	var re := _reentry(s)
	var holo: CockpitHolo = s.get_node("Holo")
	var w := holo.warning
	check(w != null and not holo.panels.has(w), "a warning panel, apart from the four")
	re.apply(4.0)
	check(not w.visible, "hidden before the big jolt")
	re.apply(4.12)
	check(w.visible and w.open_amount < 0.5, "opening from a line (%.2f)" % w.open_amount)
	re.apply(4.3)
	check(w.visible and is_equal_approx(w.open_amount, 1.0) and is_equal_approx(w.fade, 1.0), "fully open")
	var rest := w.position
	re.apply(5.1)
	check(w.visible and is_equal_approx(w.fade, 1.0) and w.position.is_equal_approx(rest), "untouched while he stares")
	re.apply(5.45)
	check(w.visible and w.fade < 0.9, "fading on the flick (%.2f)" % w.fade)
	check((w.position - rest).x > 0.1, "thrown out to his left")
	re.apply(5.9)
	check(not w.visible, "gone")
	s.free()


# The warning sits where the user drew it: above Horizon, in front of his chest, facing him, in frame.
func test_warning_sits_above_the_horizon_panel() -> void:
	var s := _shot()
	var re := _reentry(s)
	var cam: Camera3D = s.get_node("Camera3D")
	var holo: CockpitHolo = s.get_node("Holo")
	re.apply(4.3)
	var w := holo.warning
	var horizon: HoloPanel = holo.get_node("Horizon")
	var nw := _ndc(cam, w.global_position)
	var nh := _ndc(cam, horizon.global_position)
	check(nw.y > nh.y + 0.15, "above Horizon on screen (%.2f vs %.2f)" % [nw.y, nh.y])
	check(absf(nw.x) < 0.5 and absf(nw.y) < 0.6, "in frame (%.2f, %.2f)" % [nw.x, nw.y])
	var head := _bone(s, _pose(s), &"Head")
	check(w.global_basis.z.normalized().dot((head - w.global_position).normalized()) > 0.97, "faces his head")
	s.free()


# His left wrist leaves the grip (into the guard), sweeps outward to his left past the panel, and is back
# on the grip before the push; his right hand never leaves its grip.
func test_left_hand_swipes_then_returns() -> void:
	var s := _shot()
	var re := _reentry(s)
	var seat := _seat(s)
	var mod: SeatedPose = _skel(s).get_node("SeatedPose")
	var wrist := func(t: float, bone: StringName) -> Vector3:
		re.apply(t)
		return seat.global_transform.affine_inverse() * _bone(s, mod.solve(_skel(s), seat), bone)
	var rest: Vector3 = wrist.call(4.1, &"LeftHand")
	var pause: Vector3 = wrist.call(5.05, &"LeftHand")
	check(pause.distance_to(re.beats.guard_point) < 0.02, "holding the guard while he stares (%.3f m)" % pause.distance_to(re.beats.guard_point))
	var start: Vector3 = wrist.call(5.33, &"LeftHand")
	var end: Vector3 = wrist.call(5.6, &"LeftHand")
	check(start.y > rest.y + 0.2, "lifted to the panel (%.2f m)" % (start.y - rest.y))
	check(end.x > start.x + 0.25, "flicked outward to his left (%.2f m)" % (end.x - start.x))
	var back: Vector3 = wrist.call(6.35, &"LeftHand")
	check(back.distance_to(rest) < 0.02, "back on the grip (%.3f m)" % back.distance_to(rest))
	var r0: Vector3 = wrist.call(4.1, &"RightHand")
	var r1: Vector3 = wrist.call(5.5, &"RightHand")
	check(r0.distance_to(r1) < 0.03, "right hand stays on its grip")
	s.free()


# The flinch: with the head snap and the "!" his left forearm snaps up in front of his left chest/shoulder,
# between him and the warning, elbow below the wrist, and holds until the swipe leaves from it.
func test_left_arm_guards_when_the_warning_pops() -> void:
	var s := _shot()
	var re := _reentry(s)
	var b := re.beats
	var seat := _seat(s)
	var mod: SeatedPose = _skel(s).get_node("SeatedPose")
	var at := func(t: float, bone: StringName) -> Vector3:
		re.apply(t)
		return seat.global_transform.affine_inverse() * _bone(s, mod.solve(_skel(s), seat), bone)
	approx(b.guard(4.17), 0.0, 1e-6, "on the stick before the head snap")
	check(b.guard(4.24) > 0.8, "snapped up in about 0.1 s (%.2f)" % b.guard(4.24))
	check(b.guard(4.28) > 1.0, "with a little overshoot")
	approx(b.guard(4.6), 1.0, 1e-6, "settled")
	check(b.startle_visible(4.24), "with the \"!\"")
	var hand: Vector3 = at.call(4.8, &"LeftHand")
	var elbow: Vector3 = at.call(4.8, &"LeftLowerArm")
	var shoulder: Vector3 = at.call(4.8, &"LeftUpperArm")
	var head: Vector3 = at.call(4.8, &"Head")
	check(hand.distance_to(b.guard_point) < 0.02, "wrist on the guard point")
	check(hand.y > shoulder.y - 0.1 and hand.y < head.y, "at chest/shoulder height, below the face (%.2f)" % hand.y)
	check(hand.z > shoulder.z + 0.2, "out in front of him")
	check(elbow.y < hand.y - 0.1, "forearm up, elbow below the wrist")
	check(hand.z < CockpitHolo.WARNING.pos.z, "between him and the warning")
	var r0: Vector3 = at.call(4.1, &"RightHand")
	var r1: Vector3 = at.call(4.8, &"RightHand")
	check(r0.distance_to(r1) < 0.03, "right hand stays on its grip")
	s.free()


# He looks at the warning while it is up and front again by the push.
func test_he_glances_at_the_warning() -> void:
	var s := _shot()
	var b := _reentry(s).beats
	approx(b.glance(4.05), 0.0, 1e-6, "eyes front before")
	check(b.glance(4.5) > 0.99, "looking at it")
	check(b.head_look(4.5).y > deg_to_rad(15.0), "turned to his left, toward it")
	check(b.glance(5.05) > 0.99, "still looking through the pause")
	approx(b.glance(6.67), 0.0, 1e-6, "front again by the push")
	s.free()


# Both sticks tilt forward about 20 deg with the wrists riding them, he leans, and the ship answers:
# faster, hotter fire, more buzz, speed climbing.
func test_push_tilts_the_sticks_and_the_ship_answers() -> void:
	var s := _shot()
	var re := _reentry(s)
	var seat := _seat(s)
	var fire: ReentryFire = s.get_node("ScreenFire")
	var grip: Node3D = seat.get_node("GripHeadL")
	re.apply(6.57)
	var before := grip.position
	approx(fire.speed_scale, 1.0, 1e-6, "flow unchanged before")
	re.apply(7.47)
	check(grip.position.z > before.z + 0.02, "stick head forward (%.3f m)" % (grip.position.z - before.z))
	approx(re.beats.stick_angle(7.47), deg_to_rad(20.0), 1e-4, "20 deg")
	var wrist := seat.global_transform.affine_inverse() * _bone(s, _pose(s), &"LeftHand")
	var target := re.pose.left_wrist_shift * seat.left_wrist_target
	check(wrist.distance_to(target) < 0.02, "wrist rides the stick")
	check(target.z > seat.left_wrist_target.z + 0.02, "and the stick carried it forward")
	check(re.pose.body_sway.x > deg_to_rad(4.0), "leans into it")
	approx(fire.speed_scale, 1.5, 1e-4, "fire flows 1.5x")
	check(fire.flare > 0.4, "and stays hotter")
	check(re.shake.surge(6.82) == 0.0 and re.shake.surge(7.47) == 1.0, "answer 0.2 s after the push")
	check(HoloDisplay.speed_at(7.87, 6.87) > HoloDisplay.speed_at(6.87, 6.87), "speed climbs")
	s.free()


# The cartoon "!": pops in with his head snap, overshoots, hard-cuts out well before the swipe; sits
# just above his head on his right, away from the warning, square to the camera, in frame.
func test_startle_mark_pops_by_his_head() -> void:
	var s := _shot()
	var re := _reentry(s)
	var b := re.beats
	var cam: Camera3D = s.get_node("Camera3D")
	var mark := re.startle
	check(mark != null and mark.text == "!", "a \"!\" by his head")
	re.apply(4.15)
	check(not mark.visible, "hidden before the head snap")
	re.apply(4.2)
	check(mark.visible, "up with the head snap")
	check(b.startle_scale(4.23) > 1.25, "overshoots (%.2f)" % b.startle_scale(4.23))
	approx(b.startle_scale(4.4), 1.0, 1e-6, "settles")
	re.apply(4.7)
	check(mark.visible, "still up")
	re.apply(4.75)
	check(not mark.visible, "hard cut after 0.55 s")
	check(not b.startle_visible(5.1), "gone before the hand leaves the stick")
	re.apply(4.4)
	var seat := _seat(s)
	var head := seat.global_transform.affine_inverse() * _bone(s, _pose(s), &"Head")
	var at := seat.global_transform.affine_inverse() * mark.global_position
	check(at.x < head.x - 0.1, "on his right, away from the warning (%.2f)" % (at.x - head.x))
	check(at.y > head.y + 0.15, "above his head (%.2f)" % (at.y - head.y))
	check(absf(mark.global_basis.z.normalized().dot(cam.global_basis.z)) > 0.97, "square to the camera")
	var n := _ndc(cam, mark.global_position)
	check(absf(n.x) < 0.9 and absf(n.y) < 0.9, "in frame (%.2f, %.2f)" % [n.x, n.y])
	s.free()
