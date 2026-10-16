extends "res://tests/test_case.gd"

# docs/specs/pilot9-tredge.md. The baked clip (walk untouched, knees higher, stride shorter, the
# planted foot where it was), the state, the switch and its debounce, the lockouts, the staff
# and the pose layer's reach. How it looks is judged in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const STAFF := "res://resources/items/staff.tres"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")
const TREDGE := preload("res://scripts/pilot9_tredge.gd")
const ANIM := preload("res://scripts/pilot9_animation.gd")
const STORM := preload("res://scripts/rendering/storm.gd")
const DT := 1.0 / 60.0

var _pilot: Node = null

# One shared in-tree pilot9, not tredging, staff holstered.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.tredge.mode = TREDGE.Mode.FORCED_OFF
	_pilot.tredge.exposed = false
	_pilot.tredge._first = false
	_pilot.tredge._disagree_for = 0.0
	_pilot.end_tredge()
	_pilot.tredge.pose.weight = 0.0
	_pilot.tredge.pose.lantern = 0.0
	_pilot.is_dashing = false
	_pilot.is_crouching = false
	_pilot.sprint_toggled = false
	_pilot.equip_anim.finish_now()
	if _pilot.item_holder.held_item == null:
		_pilot.set_item(load(STAFF))
	if _pilot.is_item_drawn():
		_pilot.toggle_drawn()
	return _pilot

func _tick(pilot: Node, seconds: float) -> void:
	for i in int(ceil(seconds / DT)):
		pilot.tredge.tick(DT)

func _library() -> AnimationLibrary:
	var root := (load(PILOT_TSCN) as PackedScene).instantiate()
	var lib := (root.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library(&"")
	root.free()
	return lib

# Poses `skel` at `t` of `anim`, every rotation and position track.
func _pose(skel: Skeleton3D, anim: Animation, t: float) -> void:
	for i in anim.get_track_count():
		var b := skel.find_bone(str(anim.track_get_path(i)).get_slice(":", 1))
		if b < 0:
			continue
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				skel.set_bone_pose_rotation(b, anim.rotation_track_interpolate(i, t))
			Animation.TYPE_POSITION_3D:
				skel.set_bone_pose_position(b, anim.position_track_interpolate(i, t))

# [peak height, lowest height, fore-aft travel] of a foot over the cycle.
func _foot_path(skel: Skeleton3D, anim: Animation, side: String) -> Vector3:
	var f := skel.find_bone(side + "Foot")
	var hi := -INF
	var lo := INF
	var zmin := INF
	var zmax := -INF
	for i in 48:
		_pose(skel, anim, anim.length * i / 48.0)
		var p := skel.get_bone_global_pose(f).origin
		hi = maxf(hi, p.y)
		lo = minf(lo, p.y)
		zmin = minf(zmin, p.z)
		zmax = maxf(zmax, p.z)
	return Vector3(hi, lo, zmax - zmin)

# --- the clip ---------------------------------------------------------------------------------

func test_clip_is_a_pilot9_copy_and_walk_is_untouched() -> void:
	var lib := _library()
	check(lib.has_animation(BUILDER.TREDGE_CLIP), "pilot9 has a tredge clip")
	check(not lib.get_animation(BUILDER.TREDGE_CLIP).resource_path.begins_with("res://addons/"),
		"the tredge clip is pilot9's own, not an addon file")
	check(lib.get_animation(&"walk_forward").resource_path == BUILDER.TREDGE_SOURCE,
		"walk_forward is still RC's own clip")
	var walk := load(BUILDER.TREDGE_SOURCE) as Animation
	var tr := lib.get_animation(BUILDER.TREDGE_CLIP)
	approx(tr.length, walk.length, 0.00001, "same cycle length as the walk")
	eq(tr.loop_mode, walk.loop_mode, "loops like the walk")

func test_knees_lift_stride_shortens_stance_holds() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var skel := pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var walk := load(BUILDER.TREDGE_SOURCE) as Animation
	var tr := _library().get_animation(BUILDER.TREDGE_CLIP)
	for side in ["Left", "Right"]:
		var w := _foot_path(skel, walk, side)
		var t := _foot_path(skel, tr, side)
		var lift := t.x - w.x
		check(lift > 0.06 and lift < 0.13, "%s foot peaks 6-13 cm higher (got %.3f)" % [side, lift])
		check(t.z < w.z * 0.95, "%s stride is shorter (%.3f vs %.3f)" % [side, t.z, w.z])
		check(absf(t.y - w.y) < 0.02, "%s planted foot stays on the ground (%.3f vs %.3f)" % [side, t.y, w.y])
	_pose(skel, walk, 0.0)

func test_state_and_paths_meet() -> void:
	var root := (load(PILOT_TSCN) as PackedScene).instantiate()
	var sm := (root.get_node("AnimationTree") as AnimationTree).tree_root as AnimationNodeStateMachine
	check(sm.has_node(BUILDER.TREDGE_STATE), "the state machine has a tredge state")
	check(sm.has_transition("Locomotion", BUILDER.TREDGE_STATE), "Locomotion -> tredge")
	check(sm.has_transition(BUILDER.TREDGE_STATE, "Locomotion"), "tredge -> Locomotion")
	check(sm.has_transition(BUILDER.TREDGE_STATE, "fall"), "tredge -> fall")
	check(sm.has_transition("jump_land", BUILDER.TREDGE_STATE), "jump_land -> tredge")
	for i in sm.get_transition_count():
		if sm.get_transition_from(i) == &"Locomotion" and sm.get_transition_to(i) == BUILDER.TREDGE_STATE:
			approx(sm.get_transition(i).xfade_time, 0.5, 0.0001, "0.5 s blend in")
	var bt := sm.get_node(BUILDER.TREDGE_STATE) as AnimationNodeBlendTree
	check(bt.has_node(BUILDER.TREDGE_BLEND_NODE) and bt.has_node(BUILDER.TREDGE_SCALE_NODE),
		"the blend tree has the nodes pilot9_animation.gd drives")
	check(ANIM.TREDGE_BLEND.contains(BUILDER.TREDGE_BLEND_NODE), "blend path names the built node")
	check(ANIM.TREDGE_SCALE.contains(BUILDER.TREDGE_SCALE_NODE), "scale path names the built node")
	root.free()

# --- the switch -------------------------------------------------------------------------------

func test_debounce_waits_a_quarter_second() -> void:
	var cur := false
	var since := 0.0
	for i in 14:   # 0.233 s
		var got: Array = TREDGE.debounced(cur, true, since, DT, 0.25)
		cur = got[0]
		since = got[1]
	check(not cur, "not yet exposed before 0.25 s")
	for i in 2:
		var got: Array = TREDGE.debounced(cur, true, since, DT, 0.25)
		cur = got[0]
		since = got[1]
	check(cur, "exposed after 0.25 s")
	var flick: Array = TREDGE.debounced(cur, false, 0.0, DT, 0.25)
	check(flick[0], "one sheltered frame does not flip it back")
	var back: Array = TREDGE.debounced(true, true, flick[1], DT, 0.25)
	approx(back[1], 0.0, 0.00001, "agreeing again resets the count")

func test_no_storm_means_no_tredge() -> void:
	var pilot := _scene()
	pilot.tredge.mode = TREDGE.Mode.AUTO
	check(pilot.tredge.storm() == null, "the test tree has no storm")
	check(not pilot.tredge.raw_exposed(), "no storm reads as sheltered")

func test_forced_on_tredges_and_draws_the_staff() -> void:
	var pilot := _scene()
	pilot.tredge.mode = TREDGE.Mode.FORCED_ON
	_tick(pilot, 0.2)
	check(not pilot.is_tredging, "still debouncing at 0.2 s")
	_tick(pilot, 0.1)
	check(pilot.is_tredging, "tredging after the debounce")
	check(pilot.equip_anim.is_playing(), "stepping out holstered plays the draw")
	check(is_zero_approx(pilot.tredge.pose.lantern), "the torch arm waits for the draw")
	_tick(pilot, pilot.equip_anim.total_time() + 0.05)
	pilot.equip_anim._process(pilot.equip_anim.total_time() + 0.05)
	check(pilot.is_item_drawn(), "the staff ends up in his hand")
	_tick(pilot, 0.6)
	approx(pilot.tredge.pose.weight, 1.0, 0.0001, "the pose blends fully in")
	approx(pilot.tredge.pose.lantern, 1.0, 0.0001, "the torch arm comes up once drawn")
	var xf: Transform3D = pilot.item_holder.item_instance.transform
	var held: Transform3D = pilot.item_holder.held_item.hand_offset
	var slid := xf.origin - held.origin
	approx(slid.length(), absf(pilot.tredge_grip_slide), 0.001,
		"the staff slides through his fist for the torch grip")
	var axis := held.basis * Vector3.UP
	check(slid.dot(axis) < 0.0, "it slides down, so he holds it high on the shaft")
	var light: Node3D = pilot.tredge.staff_light
	approx(light.fade, 1.0, 0.0001, "the staff light is up with the torch arm")
	check(light.staff == pilot.item_holder.item_instance, "the light rides the staff in his hand")
	approx(light.staff_half_length, 0.8, 0.001, "its top end is the 1.6 m staff's +Y end")

	pilot.tredge.mode = TREDGE.Mode.FORCED_OFF
	_tick(pilot, 0.3)
	check(not pilot.is_tredging, "inside again after the debounce")
	check(pilot.is_item_drawn(), "the staff stays in his hand inside")
	_tick(pilot, 0.6)
	approx(pilot.tredge.pose.weight, 0.0, 0.0001, "the pose blends out")
	approx(pilot.tredge.staff_light.fade, 0.0, 0.0001, "the light goes out with the torch arm")
	check(pilot.item_holder.item_instance.transform.is_equal_approx(held),
		"the grip is back to the ordinary hold")

func test_scene_opening_outside_snaps_the_staff_and_pose() -> void:
	var pilot := _scene()
	pilot.tredge._first = true
	pilot.tredge.mode = TREDGE.Mode.FORCED_ON
	pilot.tredge.tick(DT)
	check(pilot.is_tredging, "tredging from the first tick")
	check(pilot.is_item_drawn() and not pilot.equip_anim.is_playing(), "the staff is snapped into his hand")
	approx(pilot.tredge.pose.weight, 1.0, 0.0001, "no blend-in on the first tick")
	approx(pilot.tredge.pose.lantern, 1.0, 0.0001, "the torch is up from the first tick")

func test_waits_for_plain_locomotion() -> void:
	var pilot := _scene()
	pilot.is_dashing = true
	pilot.tredge.mode = TREDGE.Mode.FORCED_ON
	_tick(pilot, 0.3)
	check(not pilot.is_tredging, "a dash finishes before the tredge starts")
	pilot.is_dashing = false
	pilot.tredge.tick(DT)
	check(pilot.is_tredging, "and it starts the tick after")

# --- the lockouts -----------------------------------------------------------------------------

func test_speed_sprint_and_crouch_are_locked() -> void:
	var pilot := _scene()
	pilot.is_crouching = true
	pilot.sprint_toggled = true
	pilot.tredge.mode = TREDGE.Mode.FORCED_ON
	_tick(pilot, 0.3)
	check(not pilot.is_crouching, "the crouch is cleared on the way in")
	pilot._update_sprint_toggle()
	check(not pilot.sprint_toggled, "the sprint toggle is cleared")
	pilot.tredge.gust = 0.0
	approx(pilot._requested_speed(), pilot.tredge_speed, 0.0001, "one gait: tredge speed")
	check(not pilot.is_sprinting and not pilot.is_walking, "neither sprinting nor walking")
	pilot.tredge.gust = 1.0
	approx(pilot._requested_speed(), pilot.tredge_speed * (1.0 - pilot.tredge_gust_slow), 0.0001,
		"a gust's peak dips him to 60%")
	pilot.sprint_toggled = true
	pilot._update_sprint_toggle()
	check(not pilot.sprint_toggled, "the toggle cannot be turned back on")

func test_clip_rate_follows_speed() -> void:
	var pilot := _scene()
	pilot.velocity = Vector3(pilot.tredge_speed, 0.0, 0.0)
	approx(pilot.tredge_clip_rate(), 0.7, 0.0001, "0.7x at tredge speed")
	pilot.velocity = Vector3(0.0, 0.0, pilot.tredge_speed * 0.6)
	approx(pilot.tredge_clip_rate(), 0.42, 0.0001, "slower with the gust dip")
	pilot.velocity = Vector3.ZERO

# --- the gust ---------------------------------------------------------------------------------

func test_gust_peak_is_the_shader_curve() -> void:
	# storm_gust_peak() from storm_gust.gdshaderinc, evaluated by hand.
	for t in [0.0, 1.7, 4.2, 9.9, 33.3]:
		var w1 := TAU / 8.0
		var g := 0.6 * sin(w1 * t) + 0.4 * sin(w1 * 0.61 * t + 1.3)
		approx(STORM.gust_peak_at(t, 8.0), smoothstep(0.15, 0.75, g), 0.00001, "gust at %s s" % t)

# --- the pose ---------------------------------------------------------------------------------

func test_pose_puts_the_hands_where_asked() -> void:
	var pilot := _scene()
	var skel := pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var pose: SkeletonModifier3D = pilot.tredge.pose
	_pose(skel, load(BUILDER.TREDGE_SOURCE) as Animation, 0.2)
	pose.weight = 1.0
	pose.lantern = 1.0
	pose.stagger = 0.0
	pose.bob_amount = 0.0
	pose.staff_axis = (pilot.item_holder.held_item.hand_offset.basis * Vector3.UP).normalized()
	pose._process_modification_with_delta(0.0)
	var rs := skel.get_bone_global_pose(skel.find_bone(&"RightUpperArm")).origin
	var rh := skel.get_bone_global_pose(skel.find_bone(&"RightHand"))
	approx(rh.origin.distance_to(rs + pose.lantern_offset), 0.0, 0.02, "the lantern wrist is on its target")
	var staff: Vector3 = (rh.basis * pose.staff_axis).normalized()
	check(staff.dot(pose.lantern_direction()) > 0.999, "the staff stands along the lantern direction")
	check(staff.y > 0.9 and staff.z > 0.0 and staff.x > 0.0,
		"up, tipped forward, top in so the bottom end points out to his right")
	var re := skel.get_bone_global_pose(skel.find_bone(&"RightLowerArm")).origin
	check(re.y < rh.origin.y, "the right elbow hangs below the wrist")
	check(re.x < rs.x + 0.05, "the right elbow is not tucked across his body")
	var head := skel.get_bone_global_pose(skel.find_bone(&"Head")).origin
	var lh := skel.get_bone_global_pose(skel.find_bone(&"LeftHand")).origin
	approx(lh.distance_to(head + pose.shield_offset), 0.0, 0.03, "the shield wrist is in front of his face")
	var le := skel.get_bone_global_pose(skel.find_bone(&"LeftLowerArm")).origin
	check(le.x > lh.x, "the left elbow is out to his left of the wrist - the forearm crosses his face")
	pose.weight = 0.0
	pose.lantern = 0.0

func test_staff_light_floats_over_the_staff_top() -> void:
	var pilot := _scene()
	pilot.tredge.mode = TREDGE.Mode.FORCED_ON
	_tick(pilot, 0.3)
	pilot.equip_anim.finish_now()
	if not pilot.is_item_drawn():
		pilot.toggle_drawn()
	_tick(pilot, 0.6)
	var light: Node3D = pilot.tredge.staff_light
	light.float_amount = 0.0
	light._process(DT)
	check(light.visible, "the ball shows while he tredges")
	var staff: Node3D = pilot.item_holder.item_instance
	staff.global_transform = staff.global_transform.rotated_local(Vector3.FORWARD, 0.4)
	light.place()
	var axis := staff.global_basis.y.normalized()
	var tip := staff.global_transform * (Vector3.UP * 0.8)
	approx(light.global_position.distance_to(tip + axis * light.gap), 0.0, 0.001,
		"the ball floats gap metres past the top end, in line with a tilted staff")
	approx(light.light.omni_range, 6.0, 0.0001, "the light reaches 6 m")
	check(light.light.shadow_enabled, "the light casts shadows")
	check(light.light.light_energy > light.energy * 0.9 and light.light.light_energy < light.energy * 1.1,
		"energy within the flicker")
	pilot.tredge.mode = TREDGE.Mode.FORCED_OFF
	_tick(pilot, 0.9)
	light._process(DT)
	check(not light.visible, "the ball is gone inside")

func test_staff_light_strength_flickers_and_dips() -> void:
	var light: Node3D = TREDGE._StaffLight.new()
	light.fade = 1.0
	var lo := 10.0
	var hi := 0.0
	for i in 600:
		light._time = i * 0.05
		var s: float = light.strength()
		lo = minf(lo, s)
		hi = maxf(hi, s)
	check(lo >= 1.0 - light.flicker - 0.0001 and hi <= 1.0 + light.flicker + 0.0001,
		"the flicker stays within +-5%")
	check(hi - lo > light.flicker, "and it does move")
	light._time = 0.0
	var calm: float = light.strength()
	light.stagger = 1.0
	approx(light.strength(), calm * (1.0 - light.gust_dip), 0.0001, "a full stumble dips it")
	light.fade = 0.0
	approx(light.strength(), 0.0, 0.0001, "faded out is dark")
	light.free()
