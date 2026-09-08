extends "res://tests/test_case.gd"

# EXIA, the pilotable mech. See docs/specs/exia-pilot.md.
#
# Covers what has no viewport in it: the imported clip set, and the animation state machine as a
# pure function. How 7 m/s feels, and whether the ramp under MECH_walk_start reads as weight, is
# a play session.

const MechScene := preload("res://scenes/mech.tscn")
const Mech := preload("res://scripts/mech.gd")
const Player := preload("res://scripts/player.gd")

# MECH_turning_L and MECH_turning_R are in the export but mech.gd never plays either: the
# 2026-09-02 re-export animated both, and both are a foot shuffle on the spot rather than a turn
# - the legs and toes move, no yaw reaches the skeleton, and neither covers any ground. They are
# still asserted here: the import is what is being pinned, and a clip silently going missing from
# a re-export is the failure this test exists to catch.
const EXPECTED_CLIPS := ["MECH_idle", "MECH_launch", "MECH_power_off", "MECH_standing",
	"MECH_turning_L", "MECH_turning_R", "MECH_walk", "MECH_walk_start"]

func _anim_player() -> AnimationPlayer:
	var glb: PackedScene = load("res://assets/Mech_V1.glb")
	var root := glb.instantiate()
	return root.find_child("AnimationPlayer", true, false) as AnimationPlayer

# --- the import ------------------------------------------------------------

# The Blender export carries Setsuna's fourteen actions as well, retargeted onto the mech's
# skeleton. mech_import.gd drops them; the mech has eight clips and no others.
func test_import_keeps_only_the_mech_clips() -> void:
	var ap := _anim_player()
	check(ap != null, "the imported GLB should have an AnimationPlayer")
	var names := Array(ap.get_animation_list())
	names.sort()
	eq(names, EXPECTED_CLIPS, "Mech_V1.glb should import with exactly the eight MECH_ clips")

# MECH_idle is a power-down, not a resting loop: it must end and stay ended, because the parked
# mech's crouch is that clip's held last frame. Looping it would stand the mech back up once a
# second.
func test_the_one_shots_do_not_loop() -> void:
	var ap := _anim_player()
	for one_shot in ["MECH_idle", "MECH_launch", "MECH_walk_start"]:
		eq(ap.get_animation(one_shot).loop_mode, Animation.LOOP_NONE,
			"%s plays once and holds its last frame" % one_shot)

func test_the_walk_and_the_standing_pose_loop() -> void:
	var ap := _anim_player()
	eq(ap.get_animation("MECH_walk").loop_mode, Animation.LOOP_LINEAR,
		"MECH_walk must loop - it plays for as long as the player is moving")
	# A single held pose, so looping and holding look identical. It loops so that
	# current_animation keeps naming it, which is what clip_for reads.
	eq(ap.get_animation("MECH_standing").loop_mode, Animation.LOOP_LINEAR,
		"MECH_standing must loop so the state machine can see it is the current clip")

# --- the state machine -----------------------------------------------------

# clip_for(piloted, moving, was_moving_last_frame, current)

func test_a_pilot_standing_still_gets_the_standing_pose() -> void:
	eq(Mech.clip_for(true, false, false, ""), "MECH_standing",
		"aboard and not moving: stand up straight")
	eq(Mech.clip_for(true, false, false, "MECH_standing"), "",
		"already standing: leave the playhead alone rather than restarting it")

func test_first_frame_of_movement_starts_the_walk() -> void:
	eq(Mech.clip_for(true, true, false, "MECH_standing"), "MECH_walk_start",
		"a movement key from a standstill spools the walk up")

func test_the_start_clip_is_allowed_to_finish() -> void:
	eq(Mech.clip_for(true, true, true, "MECH_walk_start"), "",
		"still moving mid-start: the queue hands over to MECH_walk on its own")

func test_walk_holds_while_moving() -> void:
	eq(Mech.clip_for(true, true, true, "MECH_walk"), "",
		"MECH_walk must not be re-issued every frame or it never advances")

func test_walk_is_recovered_if_the_chain_is_broken() -> void:
	eq(Mech.clip_for(true, true, true, ""), "MECH_walk",
		"moving with nothing playing means the queue was interrupted: pick the loop back up")

# Releasing the keys part-way through the spool-up stops the mech now, rather than making the
# player wait out an animation.
func test_releasing_the_keys_cuts_the_start_short() -> void:
	eq(Mech.clip_for(true, false, true, "MECH_walk_start"), "MECH_standing",
		"letting go mid-start returns to the standing pose immediately")
	eq(Mech.clip_for(true, false, true, "MECH_walk"), "MECH_standing",
		"letting go while walking returns to the standing pose")

# --- the standing start ----------------------------------------------------

# facing_for(yaw)

# The mech turns towards atan2(direction.x, direction.z) and then travels along facing_for() of
# the yaw it reached. If the two conventions ever disagree the mech travels across its own nose,
# which is the slide these two functions exist to prevent - so assert the round trip.
func test_the_nose_matches_the_heading_the_mech_turns_towards() -> void:
	for heading in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0),
			Vector3(0.6, 0, -0.8), Vector3(-0.28, 0, -0.96)]:
		var nose := Mech.facing_for(atan2(heading.x, heading.z))
		approx(nose.x, heading.x, 0.0001, "the nose should point along %v" % heading)
		approx(nose.z, heading.z, 0.0001, "the nose should point along %v" % heading)

func test_the_nose_stays_on_the_ground_plane() -> void:
	for yaw in [0.0, 0.7, -2.4, 3.1]:
		var nose := Mech.facing_for(yaw)
		approx(nose.y, 0.0, 0.0001, "the mech is driven horizontally; gravity owns y")
		approx(nose.length(), 1.0, 0.0001, "the nose is a unit vector, so it scales SPEED cleanly")

# ramp_rate(walk_start_length)

# The point of deriving the ramp from the clip: the mech is at SPEED on the frame MECH_walk_start
# ends, so MECH_walk is only ever entered at the one speed its stride was authored for. Any
# other rate would leave the walk loop playing at a speed it does not match, either from the
# handover onwards or for the stretch before the ramp caught up.
func test_the_ramp_finishes_exactly_when_the_start_clip_does() -> void:
	var length: float = _anim_player().get_animation("MECH_walk_start").length
	approx(Mech.ramp_rate(length) * length, Mech.SPEED, 0.0001,
		"the standing start must hand over to MECH_walk at full speed, not before or after")

# The clip is a second long today, which is the number the header comments quote.
func test_the_current_start_clip_gives_a_one_second_ramp() -> void:
	approx(_anim_player().get_animation("MECH_walk_start").length, 1.0, 0.0001,
		"MECH_walk_start is one second, so the ramp is 7 m/s/s")

# A re-export of a different length retunes the ramp rather than desyncing it.
func test_a_reexported_start_clip_retunes_the_ramp() -> void:
	approx(Mech.ramp_rate(2.0) * 2.0, Mech.SPEED, 0.0001,
		"a longer standing start should ramp more gently, not overshoot")
	approx(Mech.ramp_rate(0.5) * 0.5, Mech.SPEED, 0.0001,
		"a shorter one should ramp harder")

# Division by the clip length, so a missing or broken clip must not stall the mech outright.
func test_a_missing_start_clip_still_lets_the_mech_move() -> void:
	check(Mech.ramp_rate(0.0) > 0.0, "no start clip means set off at once, not never")

# The ramp is standing in for ground the clip does not cover. If MECH_walk_start ever travelled,
# root motion would be moving the mech as well and the two would fight.
func test_the_standing_start_covers_no_ground_itself() -> void:
	var ap := _anim_player()
	var clip: Animation = ap.get_animation("MECH_walk_start").duplicate()
	eq(Mech.split_travel(clip, Mech.root_bone_names(_skeleton()), _anchor(ap)), null,
		"MECH_walk_start is authored on the spot, so the ramp is the only thing moving the mech")

# --- the launch and the power-down -----------------------------------------

# Climbing in plays MECH_launch with MECH_standing queued behind it, so a mech standing still
# must be left alone until the boot-up ends - otherwise the state machine would cut it off on
# the very next physics frame.
func test_a_standing_launch_is_left_to_play_out() -> void:
	eq(Mech.clip_for(true, false, false, "MECH_launch"), "",
		"the launch runs to its end and hands over to the queued MECH_standing")

# The other half of the same rule as the walk start: a key press wins over an animation in
# progress. _play_chain clears the queue, so the launch's queued standing pose cannot fire
# after the walk.
func test_moving_off_interrupts_the_launch() -> void:
	eq(Mech.clip_for(true, true, false, "MECH_launch"), "MECH_walk_start",
		"driving off mid-launch starts walking rather than waiting the boot-up out")

# The whole point of the held last frame: once MECH_idle has run, current_animation is "" and
# the skeleton is still crouched. Re-issuing MECH_idle here would replay the power-down on a
# loop forever, which is exactly what a looping idle used to do.
func test_a_parked_mech_holds_its_crouch() -> void:
	eq(Mech.clip_for(false, false, false, ""), "",
		"nothing playing and nobody aboard: the crouch is held, so play nothing")
	eq(Mech.clip_for(false, false, false, "MECH_idle"), "",
		"the power-down is already running: let it reach the crouch")

func test_a_parked_mech_left_mid_clip_powers_down() -> void:
	eq(Mech.clip_for(false, false, true, "MECH_walk"), "MECH_idle",
		"parked with a movement clip still playing means the chain broke: power down")

# --- the scene -------------------------------------------------------------

# mech.gd reaches for all of these with @onready, where a rename fails at runtime and only in
# the scene that instances it.
func test_exia_scene_has_the_nodes_the_script_expects() -> void:
	var exia := MechScene.instantiate()
	eq(exia.name, &"EXIA", "the mech's root node is EXIA")
	for path in ["Model/AnimationPlayer", "CameraPivot/CameraPitch/SpringArm3D/Camera3D",
			"HandoverCamera", "InteractionArea", "ExitPoint", "UI/PromptLabel"]:
		check(exia.get_node_or_null(path) != null, "EXIA should have a node at '%s'" % path)

# The soles sit on the body's origin, so a CharacterBody3D placed at ground level stands on it.
# Up to the 2026-09-01 export the armature origin was 6.609566 m up and Model's offset cancelled
# that; the 2026-09-02 export moved the origin down to the feet, so the offset is ~0 and the
# model stands on the origin outright.
func test_the_model_stands_on_the_body_origin() -> void:
	var exia := MechScene.instantiate()
	var model := exia.get_node("Model") as Node3D
	approx(model.position.y, 0.00112, 0.0005,
		"the export puts the soles on the armature origin, so Model barely lifts it")

# The 2026-09-02 export is yawed a quarter turn, and the yaw is one number: a +90 degree Y
# rotation on the `metarig_001` armature node. The bone rests and the clips are all still built
# around a +Z nose - that is why the raw travel tracks still read +Z - so nothing is baked wrong;
# the whole rig is simply turned on its way out of Blender. The user is fixing it at the source,
# and until that export lands `Model` carries a -90 degree counter-rotation so the machine faces
# the way mech.gd's facing_for() walks it.
#
# So this asserts the *composition*, not the scene's basis on its own: the rig's resting nose,
# turned by the armature node and then by Model, has to come out on +Z. That makes it a real
# guard in both directions. A fixed export leaves the armature unrotated, the stale -90 in Model
# then swings the nose onto -X, and this fails - which is the prompt to drop the compensation and
# put Model back to an identity basis.
const REST_NOSE := Vector3.BACK  # +Z: what the bone rests are built around, both before and after

# The rotation the GLB's armature node applies on top of the rest pose.
func _armature_rotation() -> Basis:
	var glb: PackedScene = load("res://assets/Mech_V1.glb")
	var root: Node3D = glb.instantiate()
	var skeleton: Node3D = root.find_children("*", "Skeleton3D", true, false)[0]
	return (skeleton.get_parent() as Node3D).transform.basis.orthonormalized()

func test_the_model_faces_the_way_the_mech_walks() -> void:
	var exia := MechScene.instantiate()
	var model := exia.get_node("Model") as Node3D
	var nose := model.transform.basis * _armature_rotation() * REST_NOSE
	approx(nose.x, 0.0, 0.0001,
		"the mech's nose must end up on +Z, which is the way facing_for() walks it")
	approx(nose.z, 1.0, 0.0001,
		"the mech's nose must end up on +Z, which is the way facing_for() walks it")
	approx(model.transform.basis.get_scale().y, 1.0, 0.0001,
		"the counter-rotation must not scale the model")

# The counter-rotation is temporary, so pin what it is compensating for as well: the day this
# fails, the export has been fixed and Model's basis is the thing to change.
func test_the_export_is_still_yawed() -> void:
	approx(rad_to_deg(_armature_rotation().get_euler().y), 90.0, 0.01,
		"the export yaws the armature node 90 degrees; if that is gone, un-rotate Model")

# The collider is the machine, not a box around the pose: a hull short enough to stand a walking
# mech's shoulders through a bridge is the bug this pins. Measured off the skinned mesh at
# MECH_standing, which is 8.39 m tall and 7.62 m across the arms.
func test_the_hull_matches_the_machine() -> void:
	var exia := MechScene.instantiate()
	var body := exia.get_node("CollisionShape3D") as CollisionShape3D
	var box := body.shape as BoxShape3D
	approx(box.size.y, 8.55, 0.5, "the hull should be as tall as the standing mech")
	approx(body.position.y, box.size.y / 2.0, 0.0005,
		"the box is centred on its own half-height so its base sits on the soles")
	check(box.size.x > box.size.z, "EXIA is wider across the shoulders than it is deep")

func test_setsuna_can_be_a_pilot() -> void:
	var player: GDScript = load("res://scripts/player.gd")
	var methods: PackedStringArray = []
	var exit_args := -1
	var embark_args := -1
	for m in player.get_script_method_list():
		methods.append(String(m.name))
		if String(m.name) == "exit_vehicle":
			exit_args = (m.args as Array).size()
		if String(m.name) == "begin_embark":
			embark_args = (m.args as Array).size()
	check(methods.has("enter_vehicle"),
		"mech.gd only offers the prompt to bodies with enter_vehicle()")
	check(methods.has("exit_vehicle"), "F while piloting hands Setsuna back")
	# The handshake is duck-typed through has_method(), so a changed signature is a runtime
	# failure in the one frame nobody tests by hand.
	eq(exit_args, 2, "exit_vehicle takes where she lands and which way the vehicle points her")
	check(methods.has("begin_embark"), "F starts the climb before it hands her over")
	eq(embark_args, 2, "begin_embark takes the mount mark: where she stands and which way she faces")
	check(methods.has("embark_length"),
		"the mech waits out the climb, so it has to be able to ask how long it is")
	check(methods.has("ride"),
		"the mech carries her by spine.003 through the canopy close before hiding her")

# --- a climbless pilot: the mech-mount fallback ---------------------------------
#
# pilot9 (docs/specs/pilot9-mech-mount.md) is a pilot with enter_vehicle()/exit_vehicle() and
# none of the climb methods. _board() must gate the canopy beat on the PILOT having ride(),
# not on the mech having spine.003 + MECH_launch: the beat exists so the pilot is *seen*
# riding the closing cockpit, and there is nobody to see once a climbless pilot has been
# hidden on the spot. Without the guard, the piloting branch calls pilot.ride() every frame
# for the ~2 s of MECH_launch and the first pilot9 to press F takes the machine down with him.
#
# The riding half of the rule - a pilot WITH ride() still gets the beat - is in
# tests/test_pilot9_mech.gd, which needs an in-tree mech (and mutates the shared imported
# clips doing it, so it is kept out of this file's travel tests).

# The minimum a body needs to be offered the prompt and taken aboard on the spot.
class _ClimblessPilot extends Node3D:
	var boarded := false
	func enter_vehicle(_vehicle: Node3D) -> void:
		boarded = true
		visible = false
	func exit_vehicle(_pos: Vector3, _yaw: float) -> void:
		pass

# No tree, and no _ready(): the climbless branch of _board() never reaches _cockpit_world(),
# so the only rig reference it touches is anim_player, wired here by hand. Keeping _ready()
# out means _split_travel_out_of_the_clips() does not run and the shared Mech_V1 clips the
# travel tests below read are left intact.
func test_a_climbless_pilot_boards_on_the_spot_with_no_canopy_beat() -> void:
	var exia := MechScene.instantiate()
	exia.anim_player = exia.get_node("Model/AnimationPlayer")
	var pilot := _ClimblessPilot.new()
	exia.add_child(pilot)
	exia.pilot = pilot
	exia._board()
	approx(exia.seal_left, 0.0, 0.0001,
		"a pilot with no ride() has nothing to show riding the canopy, so seal_left stays 0")
	check(pilot.boarded,
		"enter_vehicle() is called inside _board(), so he is hidden on the frame F is pressed")
	check(not pilot.visible, "the climbless pilot is gone the instant he boards")
	exia.free()

# --- the camera handover ---------------------------------------------------

# See docs/specs/mech-camera-handover.md. The pan itself is a play session; what is asserted
# here is the geometry it starts from and the curve it runs on.

# yaw_behind(mech_yaw)

# The camera looks along its pivot's -Z and the mech walks along its own +Z, so "behind the
# mech" is the one place these two conventions have to be reconciled. A sin/cos swap or a
# dropped half-turn here puts the camera on EXIA's flank, or in its chest looking back at the
# pilot, which is the bug this whole entry angle exists to fix - so assert the round trip the
# same way the nose is asserted against the heading.
func test_entering_puts_the_camera_at_the_mechs_back() -> void:
	for mech_yaw in [0.0, 0.7, -2.4, 3.1, PI, -PI / 2.0]:
		# What the camera is looking at: its pivot's -Z, at the yaw yaw_behind picked.
		var look := -Mech.facing_for(Mech.yaw_behind(mech_yaw))
		var nose := Mech.facing_for(mech_yaw)
		approx(look.x, nose.x, 0.0001, "the camera should look along the mech's nose")
		approx(look.z, nose.z, 0.0001, "the camera should look along the mech's nose")

# camera_yaw is carried across piloting sessions and only ever added to by mouse motion, so an
# unwrapped result would walk it a full turn further from zero on every entry.
func test_the_entry_yaw_stays_wrapped() -> void:
	for mech_yaw in [0.0, 3.1, -3.1, PI, -PI]:
		var yaw := Mech.yaw_behind(mech_yaw)
		check(yaw >= -PI and yaw <= PI,
			"yaw_behind(%f) should stay inside one turn, got %f" % [mech_yaw, yaw])

# handover_ease(elapsed, duration)

func test_the_pan_starts_where_the_pilot_was_and_ends_on_the_mech() -> void:
	approx(Mech.handover_ease(0.0, Mech.HANDOVER_TIME), 0.0, 0.0001,
		"the first frame of the pan is the pilot's own view, unchanged")
	approx(Mech.handover_ease(Mech.HANDOVER_TIME, Mech.HANDOVER_TIME), 1.0, 0.0001,
		"the last frame is the mech camera exactly, or the handover ends on a jump")

# The window is counted down in _process, so a long frame can overshoot it.
func test_an_overshooting_frame_does_not_fly_past_the_mech_camera() -> void:
	approx(Mech.handover_ease(Mech.HANDOVER_TIME * 3.0, Mech.HANDOVER_TIME), 1.0, 0.0001,
		"a frame that overshoots the window still lands on the destination, not past it")

# Flat at both ends: the camera leaves and arrives with no velocity, which is what stops the
# join being visible at exactly the two moments the player is looking for it.
func test_the_pan_eases_in_and_out() -> void:
	approx(Mech.handover_ease(Mech.HANDOVER_TIME * 0.5, Mech.HANDOVER_TIME), 0.5, 0.0001,
		"the ease is symmetric, so it is half way across at the half way point")
	var step := Mech.HANDOVER_TIME * 0.02
	check(Mech.handover_ease(step, Mech.HANDOVER_TIME) < step / Mech.HANDOVER_TIME,
		"the pan sets off slower than a linear one - it has to start from a standstill")
	var near_end := Mech.HANDOVER_TIME - step
	check(Mech.handover_ease(near_end, Mech.HANDOVER_TIME) > near_end / Mech.HANDOVER_TIME,
		"and settles into the destination rather than arriving at speed")

func test_the_pan_only_ever_moves_forwards() -> void:
	var previous := -1.0
	for i in 21:
		var t: float = Mech.handover_ease(Mech.HANDOVER_TIME * i / 20.0, Mech.HANDOVER_TIME)
		check(t >= previous, "the ease must not go backwards - the camera would swing about")
		previous = t

# It divides by the window, and a zero-length handover is a cut rather than a stall.
func test_a_zero_length_handover_is_just_the_cut() -> void:
	approx(Mech.handover_ease(0.0, 0.0), 1.0, 0.0001,
		"no window means hand straight over to the mech camera")

# --- the handover camera ---------------------------------------------------

# The pan is flown by writing world transforms onto this camera every frame. Left parented to
# the mech's transform, EXIA walking forward under MECH_launch's root motion would drag the
# camera along with it and fight the interpolation.
func test_the_handover_camera_is_flown_in_world_space() -> void:
	var exia := MechScene.instantiate()
	var handover := exia.get_node("HandoverCamera") as Camera3D
	check(handover != null, "the mech carries its own camera for the pan")
	check(handover.top_level, "HandoverCamera must be top_level or the mech drags it")

# It only owns the viewport for the length of a pan. Saved current, it would take the picture
# the moment the mech is loaded, before anyone has climbed in.
func test_the_handover_camera_is_not_current_when_parked() -> void:
	var exia := MechScene.instantiate()
	var handover := exia.get_node("HandoverCamera") as Camera3D
	check(not handover.current, "HandoverCamera is claimed by _begin_handover, not by the scene")
	var mech_camera := exia.get_node("CameraPivot/CameraPitch/SpringArm3D/Camera3D") as Camera3D
	check(not mech_camera.current, "the mech camera is claimed when the pan lands")

# --- the ejection ----------------------------------------------------------

# ExitPoint used to be 3.5 m off EXIA's right flank, which is why the exit was a cut: a pan from
# the mech camera to hers would have swept through the machine. Out of the back it is, and the
# two cameras end up on one axis with nothing between them.

func test_the_pilot_is_put_out_of_the_back_of_the_mech() -> void:
	var exia: Node3D = MechScene.instantiate()
	var marker := exia.get_node("ExitPoint") as Marker3D
	for yaw in [0.0, 1.2, -2.6, PI]:
		# Where she lands relative to the mech, once the marker has been turned with it.
		var offset: Vector3 = Basis(Vector3.UP, yaw) * marker.position
		# She lands behind it, so the way back to the mech is the way the mech is facing.
		var to_mech := (-offset).normalized()
		var nose := Mech.facing_for(yaw)
		approx(to_mech.x, nose.x, 0.0001, "the exit point turns with the mech and stays behind it")
		approx(to_mech.z, nose.z, 0.0001, "the exit point turns with the mech and stays behind it")

# A few feet: outside EXIA's own collider so she is not spawned inside the machine, and close
# enough that she is still standing in the interaction box with the prompt armed.
func test_the_ejection_clears_the_hull_without_throwing_her_across_the_map() -> void:
	var exia: Node3D = MechScene.instantiate()
	var marker := exia.get_node("ExitPoint") as Marker3D
	var body := exia.get_node("CollisionShape3D") as CollisionShape3D
	var half_depth: float = (body.shape as BoxShape3D).size.z / 2.0
	approx(marker.position.x, 0.0, 0.0001, "directly behind the mech, not off to one side")
	check(marker.position.z < -half_depth,
		"she must land outside EXIA's body collider, not inside it")
	check(absf(marker.position.z) < 4.0, "a few feet out of the back, not across the car park")
	approx(marker.position.y, 0.0, 0.0001,
		"the mech's origin is at its soles, and she is put down on the same ground")

# The rule is written down in both rigs because both place a camera behind a body, and the exit
# lands facing the wrong way if they ever drift apart.
func test_both_rigs_put_the_camera_behind_the_same_way() -> void:
	for yaw in [0.0, 0.7, -2.4, 3.1]:
		approx(Player.yaw_behind(yaw), Mech.yaw_behind(yaw), 0.0001,
			"player.gd and mech.gd must agree on where 'behind' is")

# --- the climb -------------------------------------------------------------

# F starts a 2 s climb and the boot-up waits for it. See docs/specs/exia-pilot.md.
#
# The clip is authored travel, all of it - her body does not move for the whole climb, the bones
# do - so the mount mark is the whole of the wiring, and it is what is asserted here. Whether her
# hands land on the hull is a play session.

# Measured out of the two GLBs, which are exported from the same Blender file: she stands at the
# origin there and EXIA's body origin at (0, 0, 4.213517) yawed +90 degrees, so undoing that yaw
# puts her at mech-local (4.213517, 0, 0) facing -X. See the spec's Embarking section.
const MOUNT_DISTANCE := 4.213517

func _setsuna_anim_player() -> AnimationPlayer:
	var glb: PackedScene = load("res://assets/setsuna.glb")
	return glb.instantiate().find_child("AnimationPlayer", true, false) as AnimationPlayer

# The clip is dropped at import unless it is named in setsuna_import.gd's allow-list, and a
# dropped clip is silent: embark_length() goes to 0.0 and F boards her on the spot again.
func test_setsuna_imports_with_the_climb() -> void:
	var ap := _setsuna_anim_player()
	check(ap.has_animation(Player.ANIM_EMBARK),
		"'embark' has to be in KEEP in scripts/setsuna_import.gd or the climb never plays")

# The wait is the clip's own length, so a re-timed export moves the boot-up with it rather than
# leaving the mech booting up while she is still half way up the ladder.
func test_the_climb_is_two_seconds() -> void:
	approx(_setsuna_anim_player().get_animation(Player.ANIM_EMBARK).length, 2.0, 0.0001,
		"the climb is 2.0 s, which is what the mech counts down before MECH_launch")

# Held, not looped: the last frame is her sitting in the cockpit. A loop would drop her back down
# the machine and climb it again while the mech boots up. The name carries no .loop suffix so the
# import already gets this right; player.gd states it again in _ready the way it does for every
# other one-shot, and this pins the import end of it.
func test_the_climb_is_a_one_shot() -> void:
	eq(_setsuna_anim_player().get_animation(Player.ANIM_EMBARK).loop_mode, Animation.LOOP_NONE,
		"the climb ends on her sitting in the cockpit and holds that frame")

# She is cut onto the mark from wherever in the interaction box she pressed F, so the clip has to
# open on the pose she is already standing in. It does: embark's first spine frame is bit
# identical to IDLE's, position and rotation both, which is why nothing has to be blended.
func test_the_climb_starts_from_her_standing_pose() -> void:
	var ap := _setsuna_anim_player()
	var embark: Animation = ap.get_animation(Player.ANIM_EMBARK)
	var idle: Animation = ap.get_animation("SET IDLE")
	var embark_track := Mech.bone_track(embark, Mech.HIP_BONE)
	var idle_track := Mech.bone_track(idle, Mech.HIP_BONE)
	check(embark_track >= 0 and idle_track >= 0, "both clips key the hip")
	var start: Vector3 = embark.position_track_interpolate(embark_track, 0.0)
	var standing: Vector3 = idle.position_track_interpolate(idle_track, 0.0)
	approx(start.distance_to(standing), 0.0, 0.001,
		"the climb has to open on the pose she is cut into it from")

# And it ends 6.2 m up: the clip carries the whole climb, which is why the mount mark has to be
# exact and why the mech waits for it rather than launching underneath her.
func test_the_climb_ends_in_the_cockpit() -> void:
	var ap := _setsuna_anim_player()
	var embark: Animation = ap.get_animation(Player.ANIM_EMBARK)
	var track := Mech.bone_track(embark, Mech.HIP_BONE)
	var start: Vector3 = embark.position_track_interpolate(track, 0.0)
	var end: Vector3 = embark.position_track_interpolate(track, embark.length)
	# Bone units, on an armature scaled 0.9343115: 5.54 of them is the 5.17 m up the machine
	# that lands her in a cockpit 6.2 m off the ground.
	check(end.y - start.y > 5.0, "she climbs the machine, so the clip has to gain real height")
	check(end.z - start.z > 4.0, "and crosses the ground between the mount mark and the cockpit")

# The mark itself: off EXIA's flank, square to the nose, facing the machine. A metre out and she
# climbs into thin air beside it.
func test_the_mount_mark_sits_off_the_mechs_flank() -> void:
	var exia: Node3D = MechScene.instantiate()
	var mark := exia.get_node("EmbarkPoint") as Marker3D
	approx(mark.position.z, 0.0, 0.0001,
		"she starts square to the nose, not in front of or behind the machine")
	approx(mark.position.x, MOUNT_DISTANCE, 0.0001,
		"the distance is measured out of the export, not dialled in")
	approx(mark.position.y, 0.0, 0.0001,
		"the mech's origin is at its soles and she starts on the same ground")

func test_the_pilot_starts_the_climb_facing_the_machine() -> void:
	var exia: Node3D = MechScene.instantiate()
	var mark := exia.get_node("EmbarkPoint") as Marker3D
	# Her nose is her +Z, the same convention the mech walks on.
	var nose: Vector3 = Mech.facing_for(mark.rotation.y)
	var to_mech: Vector3 = (-mark.position).normalized()
	approx(nose.x, to_mech.x, 0.0001, "she has to be looking at the mech she is about to climb")
	approx(nose.z, to_mech.z, 0.0001, "she has to be looking at the mech she is about to climb")

# Far enough out to be standing beside the machine rather than inside it, close enough that she
# is still in the interaction box that armed the prompt in the first place.
func test_the_mount_mark_is_clear_of_the_hull_and_inside_the_box() -> void:
	var exia: Node3D = MechScene.instantiate()
	var mark := exia.get_node("EmbarkPoint") as Marker3D
	var hull := (exia.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var box := ((exia.get_node("InteractionArea/CollisionShape3D") as CollisionShape3D).shape
		as BoxShape3D)
	check(mark.position.x > hull.size.x / 2.0, "she must not start inside EXIA's own collider")
	check(mark.position.x < box.size.x / 2.0,
		"and must start somewhere she could have pressed F from")

# The mark is authored geometry, but it is not where she is actually put down: root motion moves
# the machine out from under it. Her climb was authored against EXIA crouched at the end of its
# power-down, and in the export that crouch stands 2.17 m along the nose, because MECH_idle walks
# the mech forward as it powers down. mech.gd takes exactly that travel out of the skeleton and
# gives it to the body instead, so on screen the crouch is 2.17 m *behind* where the climb expects
# to find it - and mounting straight off the mark put her on the front of the chest with the open
# canopy behind her. _mount_position subtracts the displacement the held pose is carrying; this is
# what that displacement is worth for a parked mech, which is the only state she can climb into.
func test_the_mount_is_pulled_back_by_the_power_downs_travel() -> void:
	var ap := _anim_player()
	var idle: Animation = ap.get_animation("MECH_idle").duplicate()
	var curve := Mech.split_travel(idle, Mech.root_bone_names(_skeleton()), _anchor(ap))
	check(curve != null, "the power-down travels, which is the whole reason for the pull-back")
	var held: Vector3 = curve.position_track_interpolate(0, curve.length) * ARMATURE_SCALE
	approx(held.z, 2.170, 0.005,
		"the held crouch stands 2.17 m along the nose of where the export drew it")
	approx(held.x, 0.0, 0.0005,
		"the power-down walks straight ahead, so the pull-back is along the nose and nowhere else")

# --- the canopy close ----------------------------------------------------------
#
# She is not hidden the instant the climb ends. MECH_launch slides the cockpit bone (spine.003)
# shut over its own length, and for that beat she is held on embark's last frame and carried by
# the bone. seat_follow is the rigid attach; the two bone facts below are what keep the carry
# out of root motion's way. Whether she visually holds the seated pose is a play session.

# now == board: the cockpit has not moved yet, so she sits exactly where the climb left her.
func test_she_does_not_move_on_the_first_seal_frame() -> void:
	var board := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 6, 1))
	var pilot := Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0, 4))
	check(Mech.seat_follow(board, board, pilot).is_equal_approx(pilot),
		"with the bone still at its board transform she stays put")

# A pure translation of the bone - the canopy rising and sliding back - moves her one for one.
func test_she_tracks_a_cockpit_translation() -> void:
	var board := Transform3D(Basis(), Vector3(3, 6, 1))
	var pilot := Transform3D(Basis(), Vector3(3, 6, 1))
	var shifted := Transform3D(Basis(), Vector3(3, 8.2, 2.7))
	var got := Mech.seat_follow(shifted, board, pilot)
	check(got.origin.is_equal_approx(Vector3(3, 8.2, 2.7)),
		"she follows the cockpit's translation exactly")

# A rotation of the bone carries her round it with her offset from it preserved.
func test_she_is_carried_rigidly_through_a_cockpit_rotation() -> void:
	var board := Transform3D(Basis(), Vector3.ZERO)
	var pilot := Transform3D(Basis(), Vector3(0, 0, 1))  # 1 m in front of the bone
	var turned := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)
	var got := Mech.seat_follow(turned, board, pilot)
	check(got.origin.is_equal_approx(Vector3(1, 0, 0)),
		"a quarter turn of the cockpit swings her a quarter circle, 1 m out throughout")

# The bone has to exist, or the carry silently reverts to hiding her the frame the launch starts.
func test_the_mech_rig_has_a_cockpit_bone() -> void:
	var skeleton := _skeleton()
	var idx := skeleton.find_bone(Mech.COCKPIT_BONE)
	check(idx != -1, "spine.003 is the canopy MECH_launch slides shut; she rides it")
	check(skeleton.get_bone_parent(idx) != -1,
		"spine.003 hangs off the spine, so the split never subtracts it and its world "
		+ "transform carries the mech's forward travel for free")

# ... and it must not be one of the bones the root-motion split translates, or the carry and
# root motion would both be moving her.
func test_the_cockpit_bone_is_not_a_travel_root() -> void:
	check(not Array(Mech.root_bone_names(_skeleton())).has(Mech.COCKPIT_BONE),
		"spine.003 stays out of split_travel, so seat_follow is the only thing moving her")

# --- the way out -----------------------------------------------------------
#
# F in the cockpit is the entry backwards and it animates nothing new: MECH_idle opens the same
# canopy MECH_launch shut, she rides it out on the offset the launch recorded, and `embark`
# played from its last frame to its first walks her down. What can be asserted is that the
# power-down really is the launch's canopy the other way round, and that the offset survives the
# mech having walked somewhere else since. Whether a reversed climb reads as a climb is a play
# session, and the first thing to look at.

# The position of the canopy bone at `at` seconds into `clip`.
func _canopy_at(clip_name: String, at: float) -> Vector3:
	var clip: Animation = _anim_player().get_animation(clip_name)
	var track := Mech.bone_track(clip, Mech.COCKPIT_BONE)
	check(track >= 0, "%s has to key spine.003 or there is no canopy in it" % clip_name)
	return clip.position_track_interpolate(track, at)

# The whole descent rests on this: EXIA opens its own cockpit on the way out with no clip written
# for it, because the power-down is the boot-up's canopy reversed. Shut standing, open crouched,
# and each clip's two ends are the other's swapped.
func test_the_power_down_opens_the_canopy_the_launch_shuts() -> void:
	var idle_open := _canopy_at("MECH_idle", _anim_player().get_animation("MECH_idle").length)
	var idle_shut := _canopy_at("MECH_idle", 0.0)
	var launch := _anim_player().get_animation("MECH_launch")
	approx(_canopy_at("MECH_launch", 0.0).distance_to(idle_open), 0.0, 0.001,
		"the boot-up starts where the power-down leaves the canopy: open")
	approx(_canopy_at("MECH_launch", launch.length).distance_to(idle_shut), 0.0, 0.001,
		"and ends where the power-down starts it: shut")
	check(idle_shut.distance_to(idle_open) > 1.0,
		"the canopy actually travels, or there is nothing for her to ride out on")

# The bone only ever slides, so the ride out is a pure translation: she is carried out of the
# cockpit rather than tipped out of it. A rotation track with more than one key would turn her
# through seat_follow's rigid attach.
func test_the_canopy_slides_rather_than_swings() -> void:
	var idle: Animation = _anim_player().get_animation("MECH_idle")
	for track in idle.get_track_count():
		if idle.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		if String(idle.track_get_path(track).get_concatenated_subnames()) != Mech.COCKPIT_BONE:
			continue
		eq(idle.track_get_key_count(track), 1,
			"spine.003 holds one rotation through the power-down, so she rides straight out")

# The window she rides out over is the power-down's own length, the way the climb's is `embark`'s
# - so a re-timed export moves the descent with it rather than starting her down a canopy that is
# still opening.
func test_the_ride_out_lasts_the_power_down() -> void:
	approx(_anim_player().get_animation("MECH_idle").length, 1.0, 0.0001,
		"MECH_idle is 1.0 s, which is what unseal_left counts down")

# The exit reuses the boards the entry recorded rather than measuring the seat again, and this is
# what makes that legal: the offset lives in the cockpit bone's own frame, so the same pair still
# puts her in the same place after the mech has walked half the map. Same bone pose, mech moved
# and turned - she comes out in the same spot relative to the machine.
func test_the_seated_offset_survives_the_mech_walking_off() -> void:
	# The cockpit bone's pose, in the mech's own space, and her root in it: the pair _board()
	# recorded on the frame MECH_launch started.
	var bone := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 6.2, 0.5))
	var seat := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.3, 6.0, 1.1))
	var boarded := Transform3D(Basis(Vector3.UP, 1.1), Vector3(12, 0, -30))
	var later := Transform3D(Basis(Vector3.UP, -2.2), Vector3(-140, 0, 85))
	var got := Mech.seat_follow(later * bone, boarded * bone, boarded * seat)
	check(got.is_equal_approx(later * seat),
		"the seat is the same place on the machine wherever the machine has got to")

func test_setsuna_answers_to_the_way_out() -> void:
	var player: GDScript = load("res://scripts/player.gd")
	var methods: PackedStringArray = []
	var disembark_args := -1
	for m in player.get_script_method_list():
		methods.append(String(m.name))
		if String(m.name) == "begin_disembark":
			disembark_args = (m.args as Array).size()
	check(methods.has("begin_unseal"),
		"the power-down puts her back on screen in the cockpit before she climbs down")
	check(methods.has("begin_disembark"), "and then she walks the climb backwards")
	# Duck-typed through has_method() like the rest of the handshake, so the signature is pinned
	# here or it fails in the one frame nobody tests by hand.
	eq(disembark_args, 2,
		"begin_disembark takes the same mount mark begin_embark does - she lands where she left")

# --- root motion -----------------------------------------------------------

# The clips walk the mech forward and the body used to stay put, so MECH_standing yanked it
# back 2.22 m the instant the boot-up ended. mech.gd splits that travel out of the skeleton at
# load and replays it on the CharacterBody3D instead.
#
# The split rewrites the imported clips, which are shared by every instance of the GLB, so
# these tests work on duplicates and leave the project's own copies alone.
#
# Both numbers below are in bone units, not metres: the export scales the armature node to size
# the mech, so the ground covered is the travel times ARMATURE_SCALE. See travel_scale_for.
const TRAVEL_TO_STANDING := 2.219457   # where MECH_launch's last frame sits, measured from the GLB
const TRAVEL_THROUGH_IDLE := 1.256675  # ... and how much of it MECH_idle put there
const ARMATURE_SCALE := 1.7267632      # the scale the 2026-09-01 export puts on metarig_001

func _skeleton() -> Skeleton3D:
	var glb: PackedScene = load("res://assets/Mech_V1.glb")
	return glb.instantiate().find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D

func _anchor(ap: AnimationPlayer) -> Vector3:
	var standing := ap.get_animation("MECH_standing")
	return standing.track_get_key_value(Mech.bone_track(standing, Mech.HIP_BONE), 0)

# The whole armature translates: the hip, the upper torso, both hands and both feet are all
# unparented in this rig and all six carry the same drift.
func test_the_export_translates_every_unparented_bone() -> void:
	var roots := Mech.root_bone_names(_skeleton())
	var names := Array(roots)
	names.sort()
	eq(names, ["hand.L.001", "hand.R.001", "spine", "spine.002", "toe.L.002", "toe.R.002"],
		"the travel is shared by every bone with no parent, so all of them get it subtracted")

# The bug, stated as an assertion: before the split, MECH_launch's last frame stands 2.22 m
# ahead of the pose MECH_standing holds, and that gap is the snap.
func test_the_launch_ends_ahead_of_the_standing_pose() -> void:
	var ap := _anim_player()
	var launch := ap.get_animation("MECH_launch")
	var hip := Mech.bone_track(launch, Mech.HIP_BONE)
	var last: Vector3 = launch.track_get_key_value(hip, launch.track_get_key_count(hip) - 1)
	approx(last.z - _anchor(ap).z, TRAVEL_TO_STANDING, 0.0005,
		"the imported MECH_launch ends 2.22 m in front of MECH_standing")

# ... and after it, every root bone's last frame is the standing pose exactly, so there is
# nothing left for the handover to snap.
func test_the_split_lands_the_launch_on_the_standing_pose() -> void:
	var ap := _anim_player()
	var standing := ap.get_animation("MECH_standing")
	var launch: Animation = ap.get_animation("MECH_launch").duplicate()
	var roots := Mech.root_bone_names(_skeleton())
	check(Mech.split_travel(launch, roots, _anchor(ap)) != null, "MECH_launch travels")
	for bone in roots:
		var track := Mech.bone_track(launch, bone)
		var last: Vector3 = launch.track_get_key_value(track, launch.track_get_key_count(track) - 1)
		var rest: Vector3 = standing.track_get_key_value(Mech.bone_track(standing, bone), 0)
		approx(last.x, rest.x, 0.0005, "%s should end on its standing pose" % bone)
		approx(last.z, rest.z, 0.0005, "%s should end on its standing pose" % bone)

# Only the horizontal drift comes out. The hip drops 1.10 m through MECH_launch and that is the
# crouch itself - handing it to a body standing on the ground would flatten the boot-up.
func test_the_split_leaves_the_crouch_in_the_skeleton() -> void:
	var ap := _anim_player()
	var launch: Animation = ap.get_animation("MECH_launch").duplicate()
	var hip := Mech.bone_track(launch, Mech.HIP_BONE)
	var before: Vector3 = launch.track_get_key_value(hip, 0)
	Mech.split_travel(launch, Mech.root_bone_names(_skeleton()), _anchor(ap))
	var after: Vector3 = launch.track_get_key_value(hip, 0)
	approx(after.y, before.y, 0.0001, "the hip's vertical travel is the crouch, not root motion")

# The curve is what the body is driven by, so it has to cover the ground the clip covered -
# measured from the standing pose, not from the clip's own first frame. MECH_launch opens
# 1.26 m along, where MECH_idle left the mech.
func test_the_travel_curve_carries_the_whole_chain() -> void:
	var ap := _anim_player()
	var anchor := _anchor(ap)
	var roots := Mech.root_bone_names(_skeleton())
	var idle: Animation = ap.get_animation("MECH_idle").duplicate()
	var idle_curve := Mech.split_travel(idle, roots, anchor)
	approx(idle_curve.position_track_interpolate(0, 0.0).z, 0.0, 0.0005,
		"the power-down starts from the resting pose")
	approx(idle_curve.position_track_interpolate(0, idle.length).z, TRAVEL_THROUGH_IDLE, 0.0005,
		"the power-down walks the mech 1.26 m forward")
	var launch: Animation = ap.get_animation("MECH_launch").duplicate()
	var launch_curve := Mech.split_travel(launch, roots, anchor)
	approx(launch_curve.position_track_interpolate(0, 0.0).z, TRAVEL_THROUGH_IDLE, 0.0005,
		"the boot-up picks up where the power-down left off, 1.26 m along")
	approx(launch_curve.position_track_interpolate(0, launch.length).z, TRAVEL_TO_STANDING, 0.0005,
		"the boot-up ends 2.22 m along, which is what the body has to have covered")

# The walk is an in-place cycle driven by SPEED, and the standing pose is a single held frame.
# Neither travels, so neither is touched - a curve for them would fight the velocity that
# already moves the mech.
func test_the_walk_and_the_standing_pose_are_left_alone() -> void:
	var ap := _anim_player()
	var roots := Mech.root_bone_names(_skeleton())
	var anchor := _anchor(ap)
	for clip_name in ["MECH_walk", "MECH_standing"]:
		var clip: Animation = ap.get_animation(clip_name).duplicate()
		eq(Mech.split_travel(clip, roots, anchor), null,
			"%s stays put, so there is no travel to hand to the body" % clip_name)

# Bones with a parent are keyed in their parent's space, so the armature's translation never
# reached them and subtracting it would bend the mech.
#
# Which parented bone to look at is not fixed: the import drops position tracks that never
# change, so the 2026-09-01 launch keys upper_arm.L where the export before it keyed thigh.L.
# Any one of them proves the rule, so the test picks whichever the export happens to carry.
func test_the_split_does_not_touch_parented_bones() -> void:
	var ap := _anim_player()
	var launch: Animation = ap.get_animation("MECH_launch").duplicate()
	var skeleton := _skeleton()
	var parented := ""
	for track in launch.get_track_count():
		if launch.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var bone := String(launch.track_get_path(track).get_concatenated_subnames())
		if skeleton.get_bone_parent(skeleton.find_bone(bone)) != -1:
			parented = bone
			break
	check(parented != "", "MECH_launch should key at least one bone with a parent")
	var index := Mech.bone_track(launch, parented)
	var before: Vector3 = launch.track_get_key_value(index, 0)
	Mech.split_travel(launch, Mech.root_bone_names(skeleton), _anchor(ap))
	eq(launch.track_get_key_value(index, 0), before,
		"%s is parented and must be left as it is" % parented)

# The scale the 2026-09-01 export grew the mech with. Before it, the armature node was unscaled
# and a bone unit was a metre; the split curve was handed to the body raw and it happened to be
# right. It is not any more - the body would cover 2.22 m of the 3.83 m the feet do, and the mech
# would moonwalk through every boot-up - so the ratio is measured rather than assumed.
func _skeleton_local_transform() -> Transform3D:
	var glb: PackedScene = load("res://assets/Mech_V1.glb")
	var root: Node3D = glb.instantiate()
	var skeleton: Node3D = root.find_children("*", "Skeleton3D", true, false)[0]
	# Composed by hand rather than read off global_transform: the tests run outside the tree.
	var xf := Transform3D.IDENTITY
	var node := skeleton
	while node != null and node != root:
		xf = node.transform * xf
		node = node.get_parent() as Node3D
	return xf

func test_the_export_scales_the_armature() -> void:
	approx(_skeleton_local_transform().basis.get_scale().y, ARMATURE_SCALE, 0.0005,
		"the mech is sized by a scale on metarig_001, so bone units are not metres")

func test_the_travel_is_converted_out_of_bone_units() -> void:
	var scale := Mech.travel_scale_for(Transform3D.IDENTITY, _skeleton_local_transform())
	approx(scale, ARMATURE_SCALE, 0.0005,
		"the body is unscaled, so the whole ratio is the armature's own scale")
	approx(TRAVEL_TO_STANDING * scale, 3.832, 0.005,
		"the boot-up has to walk the body the 3.83 m the animation walks the feet")

# Scaling the mech as a whole - body and model together - is not a bone/metre mismatch, so it
# must leave the conversion alone. Only the scale *between* the two counts.
func test_scaling_the_whole_mech_leaves_the_travel_alone() -> void:
	var doubled := Transform3D(Basis().scaled(Vector3(2, 2, 2)), Vector3.ZERO)
	approx(Mech.travel_scale_for(doubled, doubled * _skeleton_local_transform()),
		ARMATURE_SCALE, 0.0005,
		"a mech scaled up as a unit still converts bone units the same way")

# The mech is turned by rotation.y and _apply_root_motion multiplies the step by that basis, so
# a heading must not leak into the conversion as a scale.
func test_turning_the_mech_does_not_change_the_conversion() -> void:
	var turned := Transform3D(Basis(Vector3.UP, 1.2), Vector3(3, 0, -7))
	approx(Mech.travel_scale_for(turned, turned * _skeleton_local_transform()),
		ARMATURE_SCALE, 0.0005, "yaw and position are not scale")
