extends SceneTree

# Maintains scenes/pilot9.tscn. Run headless:
#
#   godot --headless --path . --script scripts/pilot9_build_scene.gd            # swap the rig
#   godot --headless --path . --script scripts/pilot9_build_scene.gd -- --fresh # rebuild from RC
#
# Two modes, because this script runs after EVERY pilot9.glb re-export and the scene it
# writes is also the scene the editor is used to tune.
#
# SWAP (default) - loads the existing scenes/pilot9.tscn and replaces only the
#   character/Armature subtree with the freshly imported rig. The AnimationPlayer library,
#   the AnimationTree state machine and its blend spaces, the camera rig and the capsule
#   are left as they were, so Mixamo clips added to the library and states added to the
#   tree survive a Blender re-export. This is the mode you want for a weight or mesh tweak.
#
# FRESH (--fresh) - rebuilds from RC's character.tscn, as the first build did. Use it to
#   re-base on a new Real Controller version, or to start over after a bad edit. It
#   DISCARDS every editor change to pilot9.tscn, including added clips and states.
#
# What this script OWNS in both modes, and therefore overwrites on every run: the GLB_CLIPS
# and FBX_CLIPS entries in the library, the whole `crouch` state with its transitions (and the
# `slide`, `climb`, `wall_run`, `rail`, `vault`, `dash` and `wall_climb` states with theirs), RC's two
# `-> jump_land` transitions (see _ensure_slide_state), AnimationTree.deterministic, and the
# rig camera's `current` flag. Editing any of them in
# the editor is wasted work - change it here.
#
# Why the rig is baked in rather than instanced: RC's 30 clips address the skeleton as
# %GeneralSkeleton (a scene-unique name), which only resolves if the skeleton node is
# OWNED by pilot9.tscn. The mesh/skin/materials are inlined for the same reason - an
# ExtResource into res://.godot/imported/pilot9.glb-<hash>.scn breaks when the hash
# changes on reimport.
#
# See docs/specs/pilot9-real-controller.md and docs/reimport.md.

const CHAR_TSCN := "res://addons/real-controller/character.tscn"
const PILOT_GLB := "res://assets/pilot9.glb"
const OUT := "res://scenes/pilot9.tscn"

const PILOT_HEIGHT := 1.9552          # measured mesh Y span of the retargeted rig
const CAPSULE_RADIUS := 0.34033203    # RC's radius; the blockout torso is no wider

const HEIGHT_TOLERANCE := 0.02        # metres of drift before the capsule is worth revisiting

# Clips authored in Blender and exported inside pilot9.glb. Real Controller's own 28
# arrive as .res files already referenced by the AnimationLibrary; these ride in on the
# GLB instead, so nothing references them and the builder has to lift them across on
# every re-export. Doing it here rather than in the editor is what makes them survive a
# --fresh (see the mode table in the header).
#
# Key   - the name Godot gives the clip after import. nodes/use_name_suffixes rewrites
#         the Blender action "P.crouchwalk" as "P_crouchwalk"; check the Import dock's
#         Advanced panel before adding a row, that is the part that varies.
# "as"  - the name it takes in pilot9's library, which is what the AnimationTree asks for.
# "loop"- the importer defaults every clip to LOOP_NONE regardless of content, so a cycle
#         has to say so here or it plays once and freezes.
const GLB_CLIPS := {
	"P_crouchwalk": {"as": &"crouch_walk", "loop": Animation.LOOP_LINEAR},
	# P_sitting (the climb-into-the-cockpit clip for the mech handover, not wired yet) is
	# absent from the 2026-09-21 export - flagged to the user, not silently re-added. If it
	# comes back in a later export, restore this entry:
	# "P_sitting": {"as": &"sit_down", "loop": Animation.LOOP_NONE},
	# A one-shot verb with its own run-in and run-out, not a cycle. Exported WITHOUT Mixamo's
	# In Place, and left that way on purpose - _ensure_slide_motion() below takes its 7.8 m
	# of root motion apart into a curve the controller drives the body with, and only then
	# locks the clip in place. See docs/specs/pilot9-slide.md.
	"P_slide": {"as": &"slide", "loop": Animation.LOOP_NONE},
	# The mantle. Exported WITHOUT In Place, like the slide, and taken apart the same way -
	# _ensure_climb_motion() below bakes its Hips travel into a pair of curves and then
	# locks the clip's Y *and* Z. See docs/specs/pilot9-climb.md.
	"P_climbing": {"as": &"climb_up", "loop": Animation.LOOP_NONE},
	# The wall-run cycle. The 2026-09-19 export had this key holding the skeleton's rest pose
	# (a Blender authoring miss - see the wall-run spec's "The animation" section for the
	# forced-sprint-clip workaround that shipped instead), which is why this entry once
	# refused to be wired. The 2026-09-21 re-export separated the rest pose into its own
	# `TPOSE` action (imported but deliberately not in this dict - Blender-authoring use
	# only) and re-keyed this one for real: 16 keys over 0.5s on the leg bones. Wired into
	# the `wall_run` state by _ensure_wall_run_state() below.
	# Retired 2026-09-26: the wall-run plays the ground sprint cycle instead (see the wall-run
	# spec's "Sprint cycle on the wall"). Still in the GLB; restore this entry to lift it again:
	# "P_wall-runR": {"as": &"wall_run_r", "loop": Animation.LOOP_LINEAR},
	# The rail grind's two gears, same 2026-09-21 export. Both in place - checked at wiring
	# (2026-09-24): P_rail-grind's Hips bob 1 cm in Y and nothing else, P_rail-sprint's hold one
	# key - so, like the wall-run's, there is nothing to bake or lock. Blended in the `rail`
	# state by _ensure_rail_state() below. See docs/specs/pilot9-rail-grind.md.
	"P_rail-grind": {"as": &"rail_grind", "loop": Animation.LOOP_LINEAR},
	"P_rail-sprint": {"as": &"rail_sprint", "loop": Animation.LOOP_LINEAR},
}

# Clips that arrive as loose FBX files rather than as Blender actions inside pilot9.glb - the
# no-Blender route for a Mixamo download (docs/reimport.md, "Adding a clip from a loose FBX").
# Each FBX's .import carries the same BoneMap as assets/pilot9.glb.import, keyed on the FBX's
# OWN skeleton path, so the importer retargets it onto the humanoid profile exactly as it does
# the GLB's actions. _ensure_fbx_clips() lifts them into the library beside GLB_CLIPS.
#
# Key    - the FBX's res:// path.
# "clip" - the clip name inside it. Every Mixamo download calls its one clip `mixamo_com`.
# "as"/"loop" - as in GLB_CLIPS.
const FBX_CLIPS := {
	# The vault: Mixamo "Jumping" (really a hand-plant vault), NOT In Place. Its 5.4 m of Hips
	# travel is baked into curves by _ensure_vault_motion() below and then locked, like the
	# slide's and the mantle's. See docs/specs/pilot9-vault.md.
	"res://assets/pilot9_vault.fbx": {"clip": "mixamo_com", "as": &"vault",
		"loop": Animation.LOOP_NONE},
	# The wall climb: Mixamo "Climbing Up Wall", In Place - a 2.0 s hand-over-hand loop whose
	# Hips bob ~0.3 m and come back. Nothing to bake out of the travel; _ensure_wall_climb_motion()
	# only measures the grabs and the hands' reach. See docs/specs/pilot9-wall-climb.md.
	"res://assets/pilot9_wall_climb.fbx": {"clip": "mixamo_com", "as": &"wall_climb",
		"loop": Animation.LOOP_LINEAR},
}

const CROUCH_STATE := &"crouch"
const CROUCH_CLIP := &"crouch_walk"
## AnimationTree parameter scripts/pilot9_animation.gd writes each frame. Kept next to
## the builder that creates the node, because renaming either half silently stops the
## crouch cycle advancing - set() on a path that does not exist is not an error.
const CROUCH_SCALE_NODE := "CrouchScale"

const SLIDE_STATE := &"slide"
const SLIDE_CLIP := &"slide"
## AnimationTree parameter scripts/pilot9_animation.gd writes each frame to freeze the clip
## on the hold pose. Same const-next-to-the-builder discipline as CROUCH_SCALE_NODE, and the
## same failure if the two halves drift apart: set() on a path that does not exist is not an
## error, so the clip would simply run past the hold and play itself out.
const SLIDE_SCALE_NODE := "SlideScale"
## The TimeSeek in the same blend tree, which is how the clip is dragged back onto the
## controller's clock when the `slide` state starts late. See _ensure_slide_state().
const SLIDE_SEEK_NODE := "SlideSeek"
const CLIMB_CLIP := &"climb_up"

const WALL_RUN_STATE := &"wall_run"
## The ground sprint's own forward cycle since 2026-09-26 - P_wall-runR is retired. The lean off
## the wall is pilot9.gd's (_align_model_to_slope()), not the clip's.
const WALL_RUN_CLIP := &"sprint_forward"

const WALL_CLIMB_STATE := &"wall_climb"
const WALL_CLIMB_CLIP := &"wall_climb"
## The `wall_climb` state's TimeScale. scripts/pilot9_animation.gd writes it every frame - the
## clip's rate follows his climb speed and freezes in the stall. Same const-next-to-the-builder
## discipline as CROUCH_SCALE_NODE: a stale path and the clip loops at authored speed.
const WALL_CLIMB_SCALE_NODE := "WallClimbScale"
## Samples across the wall-climb loop when finding the grabs.
const WALL_CLIMB_SAMPLES := 120
## Metres short of its furthest reach a hand still counts as on the face - see
## _ensure_wall_climb_motion().
const WALL_CLIMB_PLANT_SLOP := 0.03
const WALL_CLIMB_BAKED := ["wall_climb_grab_phases", "wall_climb_hand_reach", "wall_climb_lean",
	"wall_climb_duration"]

const RAIL_STATE := &"rail"
const RAIL_GRIND_CLIP := &"rail_grind"
const RAIL_SPRINT_CLIP := &"rail_sprint"
## The Blend2 between the two gears. scripts/pilot9_animation.gd eases its blend_amount toward
## is_rail_sprinting - same const-next-to-the-builder discipline as CROUCH_SCALE_NODE, and the
## same silent failure if the two halves drift: he would grind in the grind clip at both gears.
const RAIL_GEAR_NODE := "RailGear"

## The track the slide's travel lives on. The retargeter rewrites every GLB clip's paths to
## %GeneralSkeleton:<ProfileBone>, so this is the same address RC's own clips use - and
## `Hips` is the humanoid profile's root, which is where Mixamo puts locomotion.
const SLIDE_MOTION_TRACK := "%GeneralSkeleton:Hips"

## Points in the baked `slide_motion` curve. The clip is 40 keys over 1.55 s; this samples
## it at roughly 40 Hz, which is finer than the source and cheap either way - the curve is
## sampled twice per frame at runtime and the cost is in the count, not the fidelity.
const SLIDE_CURVE_SAMPLES := 64

## The rate P.slide's frame numbers are quoted in, which is NOT the rate the GLB was sampled
## at. The exporter baked 40 keys over 1.550 s - `Animation.step` reads 0.0333, i.e. 30 Hz -
## but the action on Blender's timeline is 93 frames long, so a frame number read off that
## timeline is worth 1/60 s. Both describe the same clip; this is the only number that
## converts between them, and it is here so the frame count below can be typed as the user
## sees it rather than pre-divided into seconds.
const SLIDE_SOURCE_FPS := 60.0

## Frames of P.slide kept. The action runs 93; frames 76-93 are the tail of the run-out,
## where he is already upright and simply running, and cutting them hands control back
## ~0.3 s earlier. That is the whole reason the exit reads as responsive rather than as a
## clip the player is waiting out.
##
## _ensure_slide_motion() then measures duration, distance and the curve off the shortened
## clip, so all three describe what actually plays and cannot disagree with it.
const SLIDE_KEEP_FRAMES := 75

## The frame the slide parks on, quoted on the same Blender timeline SLIDE_KEEP_FRAMES is -
## so 30/60 s = 0.500 s into the trimmed clip. Picked by eye in Blender: it is the first
## frame where he is fully down on the floor with the pose settled, which is the only kind
## of frame a hold can sit on for an unbounded length of time without reading as a freeze.
##
## The whole held phase happens AT this frame. Everything before it is the clip's run-in
## played straight, everything after it is the run-out played straight, and the hold is the
## seam between them - see docs/specs/pilot9-slide-hold.md.
##
## It must land inside the trimmed clip. A cut that ever comes down below it would leave a
## hold on a frame that no longer exists, which _ensure_slide_motion() refuses rather than
## clamps: the two numbers describe different intentions and silently reconciling them
## would produce a slide that holds on the run-out.
const SLIDE_HOLD_FRAME := 30

## Exported properties on scripts/pilot9.gd that this script, not the inspector, owns.
## Object.set() on a name a script does not declare is silently dropped, so every write is
## read back - a rename on the pilot9.gd side would otherwise leave the slide with a null
## curve and no complaint from anyone.
const SLIDE_BAKED := ["slide_motion", "slide_duration", "slide_distance", "slide_hold_time"]

const CLIMB_STATE := &"climb"

## Points in each baked climb curve. climb_up is 32 keys over 1.15 s; 64 samples is finer
## than the source and costs nothing - the curves are sampled once per frame at runtime.
const CLIMB_CURVE_SAMPLES := 64

## Metres of Hips rise below which climb_up is assumed to have come back exported In Place.
## The mantle is driven entirely by that travel and there is nothing to fall back on, so
## the build fails rather than shipping a climb that plays and goes nowhere.
const CLIMB_MIN_RISE := 1.0

## How much faster than authored the mantle plays. Baked onto the controller AND used to
## compress the `climb` state's clip (via its custom timeline) here, so the one number drives
## both clocks - see _ensure_climb_state() and docs/specs/pilot9-climb.md's "Two clocks".
const CLIMB_SPEED := 2.25

## The bones the entry and exit snaps are measured between. Profile-bone names, because the
## retargeter has rewritten every GLB clip onto Godot's humanoid profile.
const CLIMB_HAND_BONES := ["LeftHand", "RightHand"]
## Toes rather than feet: the foot bone is the ankle, and what has to land on the platform
## is the sole. The rest pose says how far the toes sit above his origin when he is standing
## on the floor, and that difference is the correction - see _ensure_climb_motion().
const CLIMB_FOOT_BONES := ["LeftToes", "RightToes"]

## The window, in fractions of the clip, over which the body path hands over from "hands held
## on the lip" to the authored stand-up after the pull ends. Short, because the hands leave
## the lip at the end of the pull; non-zero, because a hard switch is a kink in his velocity.
## See _climb_path().
const CLIMB_GRIP_RELEASE_BLEND := 0.1

## Same discipline as SLIDE_BAKED, and more of it to get wrong.
const CLIMB_BAKED := ["climb_motion_y", "climb_motion_z", "climb_duration", "climb_speed",
	"climb_rise", "climb_reach", "climb_inset", "climb_hand_offset", "climb_foot_offset"]

const VAULT_STATE := &"vault"
const VAULT_CLIP := &"vault"
## The `vault` state's TimeSeek and TimeScale. scripts/pilot9_animation.gd seeks the clip onto
## pilot9.gd's own vault clock every frame and holds the scale at 0, so the clip never runs on
## a clock of its own - the time scale and the run-up warp change per vault, and a clip playing
## at any fixed rate would part from the body. Same const-next-to-the-builder discipline as
## SLIDE_SEEK_NODE, and the same silent failure if the halves drift: he would vault frozen on
## frame 0.
const VAULT_SEEK_NODE := "VaultSeek"
const VAULT_SCALE_NODE := "VaultScale"

const DASH_STATE := &"dash"
## The ground sprint's forward cycle, forced for the whole dash so the afterimages have a pose to
## freeze - see docs/specs/pilot9-dash.md, "The afterimages". Same clip as the wall-run.
const DASH_CLIP := &"sprint_forward"
## pilot9.gd writes both - the scale every frame (via pilot9_animation.gd) and the seek on launch.
## Same const-next-to-the-builder discipline as CROUCH_SCALE_NODE.
const DASH_SEEK_NODE := "DashSeek"
const DASH_SCALE_NODE := "DashScale"
## Samples across the vault clip. Finer than the climb's 64 because the hand plant is short
## (~0.1-0.2 s of a 1.2 s clip) and its two ends are found by sample.
const VAULT_CURVE_SAMPLES := 96
## Metres forward the Hips must travel for the vault to count as NOT In Place - the whole move
## is this travel, as with the mantle's CLIMB_MIN_RISE.
const VAULT_MIN_TRAVEL := 3.0
## A hand slower than this (m/s, in the clip's own world) is planted. The two wrists hold
## within ~1 m/s of still on the top and move at 2-5 m/s either side of it.
const VAULT_PLANT_SPEED := 1.5
## A planted wrist is lifted again once it passes this. Above VAULT_PLANT_SPEED on purpose: the
## left wrist shuffles at ~2.2 m/s mid-plant without leaving the top, and lifts at ~2.7.
const VAULT_LIFT_SPEED := 2.5
## Metres of wrist above the surface the hand is flat on - the palm under the wrist bone.
## Subtracted from the planted wrists to give the top the clip was authored over, and added
## back at runtime so the wrists sit this far over the detected top.
const VAULT_PALM := 0.05
## A toe within this of its rest height (metres) is on the floor - the takeoff and the
## touchdown are measured against it.
const VAULT_GROUND_EPS := 0.05
## Metres past the planted hands a toe still counts as over the top when measuring the foot
## clearance - about the depth of the thin walls the clip was authored over.
const VAULT_OVER_TOP_DEPTH := 0.5
const VAULT_BAKED := ["vault_motion_y", "vault_motion_z", "vault_duration", "vault_travel",
	"vault_clip_speed", "vault_takeoff_time", "vault_plant_time", "vault_release_time",
	"vault_touchdown_time", "vault_top_height", "vault_plant_reach", "vault_post_travel",
	"vault_foot_clearance", "vault_palm", "vault_hand_spread"]

## RC's run cycles, re-baked into pilot9's library with a smaller arm swing - see
## _ensure_run_arm_swing() and docs/specs/pilot9-run-arm-swing.md. Library name -> the addon file
## it is always rebuilt from, so a second build never scales an already-scaled copy.
const RUN_CLIPS := {
	&"run_forward": "res://addons/real-controller/animations/run_forward.res",
	&"run_forward_left": "res://addons/real-controller/animations/run_forward_left.res",
	&"run_forward_right": "res://addons/real-controller/animations/run_forward_right.res",
	&"run_left": "res://addons/real-controller/animations/run_left.res",
	&"run_right": "res://addons/real-controller/animations/run_right.res",
	&"run_backward": "res://addons/real-controller/animations/run_backward.res",
	&"run_backward_left": "res://addons/real-controller/animations/run_backward_left.res",
	&"run_backward_right": "res://addons/real-controller/animations/run_backward_right.res",
}
## Fraction of the run's arm swing kept (user, 2026-10-06: "a little less"; 1.0 = RC's own).
const RUN_ARM_SWING := 0.7
const ARM_SWING := preload("res://scripts/arm_swing.gd")
## The joints that swing less. Hands and fingers keep their full motion on purpose.
const RUN_ARM_BONES := ["LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm",
	"LeftLowerArm", "RightLowerArm"]

## The blizzard tredge: a pilot9-only clip baked from RC's walk (legs only - see
## scripts/tredge_bake.gd) and the `tredge` state that plays it over `idle`. See
## docs/specs/pilot9-tredge.md.
const TREDGE_SOURCE := "res://addons/real-controller/animations/walk_forward.res"
const TREDGE_CLIP := &"tredge"
const TREDGE_STATE := &"tredge"
const TREDGE_BLEND_NODE := "TredgeMove"
const TREDGE_SCALE_NODE := "TredgeScale"
const TREDGE_BAKE := preload("res://scripts/tredge_bake.gd")

## RC's camera rig, unchanged by either mode. Only the `current` flag is asserted on it -
## see _ensure_camera_current().
const CAMERA_PATH := "CameraPivot/SpringArm3D/Camera3D"
const CAMERA_PIVOT_PATH := "CameraPivot"


## MainLoop's _initialize(), not Object's _init() - the constructor runs before autoloads
## are registered, so any script this loads that touches Settings (pilot9.gd's base_fov)
## fails to compile with "Identifier not found: Settings" the moment load(OUT) reloads it.
## tests/run_tests.gd sidesteps the same trap by hanging off _process() instead.
func _initialize() -> void:
	var fresh := _has_flag("--fresh")
	if not fresh and not ResourceLoader.exists(OUT):
		print("no ", OUT, " yet - building fresh")
		fresh = true

	var root: Node = _build_fresh() if fresh else _swap_rig()
	if root == null:
		quit(1)
		return

	# Both run in either mode and are idempotent: a swap has to refresh the clip a
	# re-export just changed, and a fresh build has to add what RC never had.
	if not _ensure_glb_clips(root):
		quit(1)
		return
	if not _ensure_fbx_clips(root):
		quit(1)
		return
	if not _ensure_run_arm_swing(root):
		quit(1)
		return
	if not _ensure_crouch_state(root):
		quit(1)
		return
	# Order matters: the bake reads the slide clip's root motion and then destroys it, so it
	# has to run after _ensure_glb_clips() has put a fresh copy in the library and before
	# anything else looks at that clip.
	if not _ensure_slide_motion(root):
		quit(1)
		return
	if not _ensure_slide_state(root):
		quit(1)
		return
	# Same ordering argument as the slide's: the bake reads climb_up's root motion and then
	# destroys it, so it runs after _ensure_glb_clips() has put a fresh copy in the library.
	if not _ensure_climb_motion(root):
		quit(1)
		return
	if not _ensure_climb_state(root):
		quit(1)
		return
	if not _ensure_wall_run_state(root):
		quit(1)
		return
	if not _ensure_rail_state(root):
		quit(1)
		return
	# Same ordering argument again: the bake reads the vault's root motion and then locks it.
	if not _ensure_vault_motion(root):
		quit(1)
		return
	if not _ensure_vault_state(root):
		quit(1)
		return
	if not _ensure_dash_state(root):
		quit(1)
		return
	if not _ensure_wall_climb_motion(root):
		quit(1)
		return
	if not _ensure_wall_climb_state(root):
		quit(1)
		return
	if not _ensure_tredge(root):
		quit(1)
		return
	if not _ensure_deterministic_blending(root):
		quit(1)
		return
	if not _ensure_camera_current(root):
		quit(1)
		return
	if not _ensure_camera_interpolation(root):
		quit(1)
		return

	_report_height(root)

	if not _save(root):
		quit(1)
		return

	print("wrote ", OUT, "  (", "fresh" if fresh else "rig swap", ")")
	quit(0)


# -- modes ----------------------------------------------------------------------------

# Replace character/Armature in the existing scene, leave everything else alone.
func _swap_rig() -> Node:
	var root := (load(OUT) as PackedScene).instantiate()

	var character := root.get_node_or_null("character")
	if character == null:
		push_error("%s has no 'character' node - run with --fresh to rebuild" % OUT)
		return null

	var old_arm := character.get_node_or_null("Armature")
	if old_arm:
		character.remove_child(old_arm)
		# free(), not queue_free(): nothing pumps the tree in a --script run, so a queued
		# node is never actually freed and its skeleton keeps the %GeneralSkeleton claim -
		# the new one then silently fails to register under that name.
		old_arm.free()

	var arm := _import_armature()
	if arm == null:
		return null
	character.add_child(arm)

	# instantiate() owns the scene's own nodes, but re-assert it so the swapped-in
	# armature and everything under it is packed rather than silently dropped.
	_reown(root, root)
	return root


# Rebuild from Real Controller's character.tscn with the pilot9 rig swapped in.
func _build_fresh() -> Node:
	var root := (load(CHAR_TSCN) as PackedScene).instantiate()

	var old_rig := root.get_node("character")
	var rig_basis: Basis = (old_rig as Node3D).transform.basis  # 180 deg about Y; kept
	root.remove_child(old_rig)
	old_rig.free()   # RC's rig also owns a %GeneralSkeleton - see the note in _swap_rig()

	var new_rig := Node3D.new()
	new_rig.name = "character"
	new_rig.transform = Transform3D(rig_basis, Vector3.ZERO)
	root.add_child(new_rig)
	new_rig.owner = root

	var arm := _import_armature()
	if arm == null:
		return null
	new_rig.add_child(arm)
	arm.owner = root
	_reown(arm, root)

	var ap := root.get_node("AnimationPlayer") as AnimationPlayer
	ap.root_node = ap.get_path_to(new_rig)
	var at := root.get_node("AnimationTree") as AnimationTree
	at.root_node = at.get_path_to(new_rig)

	root.set_script(load("res://scripts/pilot9.gd"))
	(root.get_node("Animation") as Node).set_script(load("res://scripts/pilot9_animation.gd"))

	var col := root.get_node("CollisionShape3D") as CollisionShape3D
	var cap := (col.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	cap.height = PILOT_HEIGHT
	cap.radius = CAPSULE_RADIUS
	col.shape = cap
	col.transform.origin.y = PILOT_HEIGHT / 2.0

	return root


# -- rig ------------------------------------------------------------------------------

func _import_armature() -> Node3D:
	var pilot := (load(PILOT_GLB) as PackedScene).instantiate()
	var arm := pilot.get_node_or_null("Armature") as Node3D
	if arm == null:
		push_error("%s has no 'Armature' node" % PILOT_GLB)
		pilot.free()
		return null

	var skel := arm.get_node_or_null("GeneralSkeleton") as Skeleton3D
	if skel == null:
		push_error("no 'GeneralSkeleton' under Armature - the retarget did not run. " +
			"Check that assets/pilot9.glb.import still carries its BoneMap under the key " +
			"'PATH:Armature/Skeleton3D' (see docs/reimport.md).")
		pilot.free()
		return null

	skel.unique_name_in_owner = true   # re-asserted as text after save (see _save)
	for mi in skel.find_children("*", "MeshInstance3D", true, false):
		_inline_resources(mi)

	pilot.remove_child(arm)
	pilot.free()
	return arm


# Break the tie to res://.godot/imported/pilot9.glb-<hash>.scn::* so ResourceSaver
# writes the mesh + skin + materials inline (survives a pilot9.glb reimport).
func _inline_resources(mi: MeshInstance3D) -> void:
	if mi.mesh:
		var m: Mesh = mi.mesh.duplicate(true)
		m.resource_path = ""
		mi.mesh = m
	if mi.skin:
		var s: Skin = mi.skin.duplicate(true)
		s.resource_path = ""
		mi.skin = s
	for i in mi.get_surface_override_material_count():
		var mat := mi.get_surface_override_material(i)
		if mat:
			var md: Material = mat.duplicate(true)
			md.resource_path = ""
			mi.set_surface_override_material(i, md)


func _reown(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_reown(c, owner)


# -- clips authored in Blender --------------------------------------------------------

# Copies every GLB_CLIPS entry out of the freshly imported pilot9.glb into pilot9's own
# AnimationLibrary, replacing any previous copy. Returns false if a named clip is missing.
func _ensure_glb_clips(root: Node) -> bool:
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		push_error("%s has no AnimationPlayer to hold the Blender clips" % OUT)
		return false
	var lib := ap.get_animation_library(&"")
	if lib == null:
		push_error("%s's AnimationPlayer has no default (unnamed) animation library" % OUT)
		return false

	var pilot := (load(PILOT_GLB) as PackedScene).instantiate()
	var src := pilot.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if src == null:
		push_error("%s imported without an AnimationPlayer - is animation/import off in " % PILOT_GLB +
			"assets/pilot9.glb.import, or does the export carry no actions?")
		pilot.free()
		return false

	var ok := true
	for glb_name in GLB_CLIPS:
		var spec: Dictionary = GLB_CLIPS[glb_name]
		var to: StringName = spec["as"]
		if not src.has_animation(glb_name) and spec.get("optional", false):
			print("  clip %s not in the export yet (optional) - skipped" % glb_name)
			continue
		if not src.has_animation(glb_name):
			push_error(("%s carries no clip named '%s'. It has %s. Rename the action in " +
				"Blender or update GLB_CLIPS in this script.")
				% [PILOT_GLB, glb_name, str(src.get_animation_list())])
			ok = false
			continue

		# duplicate(): the imported Animation belongs to res://.godot/imported/pilot9.glb-
		# <hash>.scn, and that hash changes on the next reimport - the same reason the mesh
		# and skin are inlined. Its track paths need no rewriting: the retargeter has
		# already rewritten them to %GeneralSkeleton:<ProfileBone>, which is exactly what
		# RC's own clips address, so they resolve against pilot9.tscn unchanged.
		var anim := (src.get_animation(glb_name) as Animation).duplicate(true) as Animation
		anim.resource_path = ""
		anim.resource_name = to
		anim.loop_mode = spec["loop"]

		if lib.has_animation(to):
			lib.remove_animation(to)
		lib.add_animation(to, anim)
		print("  clip %s -> \"%s\"  %.3fs, %d tracks, loop_mode %d"
			% [glb_name, to, anim.length, anim.get_track_count(), anim.loop_mode])

	pilot.free()
	return ok


# The FBX_CLIPS half of _ensure_glb_clips(): same copy-and-replace into pilot9's library, from
# a loose FBX instead of the GLB. The one thing the GLB route got for free is checked here
# rather than trusted - that the retarget actually ran. A BoneMap filed under the wrong
# subresource key is silently ignored, and the clip then arrives addressing `mixamorig_*` bones
# pilot9's skeleton does not have: it plays, binds nothing, and he vaults in his idle pose.
func _ensure_fbx_clips(root: Node) -> bool:
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var lib := ap.get_animation_library(&"") if ap != null else null
	if lib == null:
		push_error("%s has no AnimationPlayer default library to hold the FBX clips" % OUT)
		return false

	for fbx_path in FBX_CLIPS:
		var spec: Dictionary = FBX_CLIPS[fbx_path]
		var packed := load(fbx_path) as PackedScene
		if packed == null:
			push_error("%s did not import - is it in assets/ with its .import beside it?" % fbx_path)
			return false
		var scene := packed.instantiate()
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		var src: AnimationPlayer = players[0] if not players.is_empty() else null
		if src == null or not src.has_animation(spec["clip"]):
			push_error("%s carries no clip '%s' (has %s)" % [fbx_path, spec["clip"],
				str(src.get_animation_list()) if src != null else "no AnimationPlayer"])
			scene.free()
			return false

		var anim := (src.get_animation(spec["clip"]) as Animation).duplicate(true) as Animation
		scene.free()
		anim.resource_path = ""
		anim.resource_name = spec["as"]
		anim.loop_mode = spec["loop"]
		# A clip downloaded with fingers carries tracks for bones the BoneMap leaves unmapped (the
		# blockout rig has no fingers), and those keep their Mixamo names. Dropped - they bind
		# nothing. The retarget itself is judged on the Hips: a Mixamo-named Hips track means
		# the BoneMap never ran.
		for t in range(anim.get_track_count() - 1, -1, -1):
			var bone := str(anim.track_get_path(t)).get_slice(":", 1)
			if bone == "mixamorig_Hips" or bone == "mixamorig:Hips":
				push_error(("%s's Hips track still names a Mixamo bone - the retarget did not run. " +
					"Its .import needs assets/pilot9.glb.import's BoneMap under the FBX's own " +
					"skeleton path (\"PATH:Skeleton3D\" for a Mixamo FBX) - see docs/reimport.md.")
					% fbx_path)
				return false
			if bone.begins_with("mixamorig"):
				anim.remove_track(t)
		for t in anim.get_track_count():
			var path := str(anim.track_get_path(t))
			var bone := path.get_slice(":", 1)
			# The importer names the skeleton `GeneralSkeleton` and marks it unique, so the tracks
			# normally come out as %GeneralSkeleton:<Bone> already. Rewritten if not, onto the one
			# address every other clip in the library uses.
			if not path.begins_with("%GeneralSkeleton:"):
				anim.track_set_path(t, NodePath("%GeneralSkeleton:" + bone))

		if lib.has_animation(spec["as"]):
			lib.remove_animation(spec["as"])
		lib.add_animation(spec["as"], anim)
		print("  fbx clip %s:%s -> \"%s\"  %.3fs, %d tracks, loop_mode %d"
			% [fbx_path.get_file(), spec["clip"], spec["as"], anim.length,
			anim.get_track_count(), anim.loop_mode])
	return true


# Replaces each RUN_CLIPS entry in pilot9's library with a copy of the addon clip whose arm
# swing is scaled to RUN_ARM_SWING. The addon .res is the source every time and is never
# written - other scenes use RC's clips as shipped. The copy is inlined into pilot9.tscn and
# keeps the library name, so the RunBlend blend space needs no change.
func _ensure_run_arm_swing(root: Node) -> bool:
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var lib := ap.get_animation_library(&"") if ap != null else null
	if lib == null:
		push_error("%s has no AnimationPlayer default library to hold the run clips" % OUT)
		return false

	for to in RUN_CLIPS:
		var src := load(RUN_CLIPS[to]) as Animation
		if src == null:
			push_error("no run clip at %s - has the Real Controller addon moved?" % RUN_CLIPS[to])
			return false
		var anim := src.duplicate(true) as Animation
		anim.resource_path = ""
		anim.resource_name = to
		var touched := ARM_SWING.scale_swing(anim, RUN_ARM_BONES, RUN_ARM_SWING)
		if touched == 0:
			push_error("%s has no rotation tracks on %s - the bone names changed?"
				% [RUN_CLIPS[to], str(RUN_ARM_BONES)])
			return false
		if lib.has_animation(to):
			lib.remove_animation(to)
		lib.add_animation(to, anim)
		print("  run clip \"%s\"  arm swing x%.2f on %d tracks" % [to, RUN_ARM_SWING, touched])
	return true


# -- crouch ---------------------------------------------------------------------------

# Adds (or replaces) the `crouch` state and its transitions on the locomotion state
# machine. The state is a two-node blend tree - the clip through an AnimationNodeTimeScale
# - because pilot9 has a crouch WALK and no crouch IDLE. Standing still, the scale is
# eased to 0 by scripts/pilot9_animation.gd and he holds the pose he stopped on; marching
# on the spot is what that avoids. A Mixamo "Crouch Idle" would let this become a proper
# blend instead, and the TimeScale can go the day it exists.
func _ensure_crouch_state(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		push_error("%s has no AnimationTree" % OUT)
		return false
	var sm := at.tree_root as AnimationNodeStateMachine
	if sm == null:
		push_error("%s's AnimationTree root is not an AnimationNodeStateMachine" % OUT)
		return false

	var clip := AnimationNodeAnimation.new()
	clip.animation = CROUCH_CLIP

	var scale := AnimationNodeTimeScale.new()

	var bt := AnimationNodeBlendTree.new()
	bt.add_node("Clip", clip, Vector2(-160, 40))
	bt.add_node(CROUCH_SCALE_NODE, scale, Vector2(140, 40))
	bt.set_node_position("output", Vector2(440, 40))
	bt.connect_node(CROUCH_SCALE_NODE, 0, "Clip")
	bt.connect_node("output", 0, CROUCH_SCALE_NODE)

	# remove_node() takes the state's transitions with it, so a re-run cannot leave a
	# stale pair behind pointing at the node it just replaced.
	if sm.has_node(CROUCH_STATE):
		sm.remove_node(CROUCH_STATE)
	sm.add_node(CROUCH_STATE, bt, Vector2(630, 620))

	# Priority orders the exits that can be live in the same frame. Pressing jump clears
	# is_crouching AND launches him on one frame (see scripts/pilot9.gd), so `-> jump` and
	# `-> Locomotion` both qualify; jump has to win or the leap plays as a stand-up.
	_set_transition(sm, "Locomotion", CROUCH_STATE, 0.2, "is_crouching", 1)
	_set_transition(sm, CROUCH_STATE, "jump", 0.1, "velocity.y > 0", 0)
	_set_transition(sm, CROUCH_STATE, "fall", 0.3, "not is_on_floor() and velocity.y <= 0", 1)
	_set_transition(sm, CROUCH_STATE, "Locomotion", 0.2, "not is_crouching", 2)
	# Landing already crouched: jump_land's only other exit needs velocity, so without
	# this one a standing-still landing strands him out of the crouch he never left.
	_set_transition(sm, "jump_land", CROUCH_STATE, 0.2, "is_crouching", 0)

	print("  state \"%s\" -> %s (TimeScale), %d states, %d transitions"
		% [CROUCH_STATE, CROUCH_CLIP, sm.get_node_list().size(), sm.get_transition_count()])
	return true


# -- slide ----------------------------------------------------------------------------

# Splits the slide clip into the two things it actually is, and this is the whole trick of
# the feature.
#
# `P.slide` was exported without Mixamo's In Place, so its Hips track walks +7.8 m forward
# over 1.55 s. That motion cannot be left in the clip:
#
#   * only the mesh would move. The CharacterBody3D would sit still and the collision
#     capsule would be 7.8 m behind him for the length of the slide; and
#   * a root-motion track cannot be cross-faded. Every transition in this state machine is
#     an xfade, and blending a Hips at +7.68 m against a run clip's ~0 drags the mesh
#     backwards through the whole exit fade. AnimationTree.root_motion_track solves both -
#     and strips the named track from EVERY clip in the tree, taking the bob and sway out
#     of all 29 of RC's. Not worth it for one clip.
#
# The clip is also cut short first - see _trim_slide() - so everything below is measured
# against the shortened run-out rather than the authored one.
#
# So: the travel is baked out as a normalised distance-over-time Curve onto the controller,
# where scripts/pilot9.gd::_apply_slide_velocity() differentiates it to drive the body, and
# only then is the clip's Z locked to its first key. What is left in the library is an
# ordinary in-place clip that cross-fades like all the others - with its X and Y untouched,
# so the hip drop that sells the slide and the lateral sway both survive.
#
# The point of doing it this way rather than picking a speed and a friction constant: the
# clip has planted feet during its run-in (~8 m/s) and its run-out (~5 m/s), and those are
# the only two windows where a mismatch shows as skate. Driving the body from the animator's
# own numbers makes both exact by construction and re-derives them on every re-export.
func _ensure_slide_motion(root: Node) -> bool:
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(SLIDE_CLIP):
		push_error("no '%s' clip in the library - _ensure_glb_clips() did not run" % SLIDE_CLIP)
		return false
	var anim := ap.get_animation(SLIDE_CLIP)
	_trim_slide(anim)

	var track := anim.find_track(NodePath(SLIDE_MOTION_TRACK), Animation.TYPE_POSITION_3D)
	if track == -1:
		push_error(("'%s' has no position track on '%s'. Either the retarget did not run " +
			"(paths would still read Armature/Skeleton3D) or the action no longer animates " +
			"the hips at all.") % [SLIDE_CLIP, SLIDE_MOTION_TRACK])
		return false

	var length := anim.length
	var z0: float = anim.position_track_interpolate(track, 0.0).z
	var total: float = anim.position_track_interpolate(track, length).z - z0
	if total < 0.5:
		push_error(("'%s' carries only %.3f m of forward travel. It was exported In Place, " +
			"or backwards - the slide is driven entirely by this number and there is nothing " +
			"sensible to fall back on.") % [SLIDE_CLIP, total])
		return false

	# Linear tangents on every point: Curve interpolates as a bezier by default, and a
	# curve that overshoots between samples is a body that lurches between them.
	var curve := Curve.new()
	for i in SLIDE_CURVE_SAMPLES + 1:
		var u := float(i) / float(SLIDE_CURVE_SAMPLES)
		var travelled: float = anim.position_track_interpolate(track, u * length).z - z0
		var idx := curve.add_point(Vector2(u, clampf(travelled / total, 0.0, 1.0)))
		curve.set_point_left_mode(idx, Curve.TANGENT_LINEAR)
		curve.set_point_right_mode(idx, Curve.TANGENT_LINEAR)

	# The hold point, converted out of Blender frames into the clip's own seconds. Refused
	# rather than clamped if the trim has moved in past it - see SLIDE_HOLD_FRAME. Zero
	# would be a legal value on the pilot9.gd side (it reads as "no hold") and that is
	# exactly the silent downgrade worth avoiding: the slide would still work, and would
	# simply stop doing the thing this frame number exists for.
	var hold := float(SLIDE_HOLD_FRAME) / SLIDE_SOURCE_FPS
	if hold <= 0.0 or hold >= length:
		push_error(("the slide's hold frame (%d, i.e. %.3fs) is not inside the trimmed clip, " +
			"which runs %.3fs. Lower SLIDE_HOLD_FRAME or raise SLIDE_KEEP_FRAMES - a hold " +
			"on a frame that is not there cannot be built.") % [SLIDE_HOLD_FRAME, hold, length])
		return false

	root.set("slide_motion", curve)
	root.set("slide_duration", length)
	root.set("slide_distance", total)
	root.set("slide_hold_time", hold)
	for prop in SLIDE_BAKED:
		if root.get(prop) == null:
			push_error(("scripts/pilot9.gd declares no '%s'. Object.set() drops an unknown " +
				"property silently, so the slide would ship with no motion at all and " +
				"nothing in the log.") % prop)
			return false

	# Lock the pose in place. Z only - X carries the hip sway (it returns to where it
	# started) and Y is the drop to the floor and back, which is the read.
	for k in anim.track_get_key_count(track):
		var v: Vector3 = anim.track_get_key_value(track, k)
		v.z = z0
		anim.track_set_key_value(track, k, v)

	print("  clip \"%s\" locked in place; %.3f m over %.3fs baked to slide_motion (%d points), hold at frame %d (%.3fs)"
		% [SLIDE_CLIP, total, length, curve.point_count, SLIDE_HOLD_FRAME, hold])
	return true


# Cuts the clip's run-out short. Runs before anything else reads the clip, which is what
# keeps the bake honest: shorten it and the curve, the duration and the distance are all
# re-measured against the new end in the same pass.
#
# Moving `Animation.length` alone is NOT enough, and the way it fails is quiet. Godot's
# interpolation ignores keys past the length rather than clamping to the length: with the
# GLB sampled at 30 Hz, the last key inside a 1.25 s cut sits at 1.20 s, and every sample
# from there to the end returns that key. The clip would hold a frozen pose for its last
# 0.05 s - and the baked curve, read through the same interpolation, would flatten with it
# and stop the body dead. Measured: 6.262 m instead of 6.462 m, with the difference all in
# the final two frames.
#
# So the boundary pose is sampled first, at full precision, then the keys past the cut are
# dropped and that pose is re-keyed exactly on it. What comes out is a clip that animates
# all the way to its new end, which is the whole point of cutting there.
#
# Guarded rather than assumed. A re-export shorter than the cut would otherwise have its
# length silently pushed OUT to 1.25 s - Animation.length is settable in both directions -
# and the added time would be exactly the frozen tail this function exists to avoid.
func _trim_slide(anim: Animation) -> void:
	var trim := float(SLIDE_KEEP_FRAMES) / SLIDE_SOURCE_FPS
	if trim <= 0.0 or trim >= anim.length:
		print("  clip \"%s\" is %.3fs, at or under the %d-frame cut - left alone"
			% [SLIDE_CLIP, anim.length, SLIDE_KEEP_FRAMES])
		return
	var authored := anim.length

	for i in anim.get_track_count():
		var ty := anim.track_get_type(i)
		# Sampled BEFORE anything is removed and before the length moves - both change what
		# the interpolators return, which is the trap this whole function is working around.
		var at_cut: Variant = null
		match ty:
			Animation.TYPE_POSITION_3D: at_cut = anim.position_track_interpolate(i, trim)
			Animation.TYPE_ROTATION_3D: at_cut = anim.rotation_track_interpolate(i, trim)
			Animation.TYPE_SCALE_3D:    at_cut = anim.scale_track_interpolate(i, trim)
			_:
				# The GLB carries only the three 3D types. Anything else is a new kind of
				# track nobody has thought about here, and a silent skip is how it would
				# end up half-trimmed.
				push_warning(("'%s' track %d is type %d, which _trim_slide() does not know " +
					"how to re-key. Its keys past the cut are dropped without a boundary " +
					"key.") % [SLIDE_CLIP, i, ty])

		var k := anim.track_get_key_count(i) - 1
		while k >= 0:
			if anim.track_get_key_time(i, k) > trim:
				anim.track_remove_key(i, k)
			k -= 1

		if at_cut != null:
			var last := anim.track_get_key_count(i) - 1
			if last >= 0 and is_equal_approx(anim.track_get_key_time(i, last), trim):
				anim.track_set_key_value(i, last, at_cut)   # a key already landed on it
			else:
				anim.track_insert_key(i, trim, at_cut)

	anim.length = trim
	print("  clip \"%s\" trimmed %.3fs -> %.3fs (first %d of %d frames)"
		% [SLIDE_CLIP, authored, trim, SLIDE_KEEP_FRAMES,
			int(round(authored * SLIDE_SOURCE_FPS))])


# The `slide` state: the clip through a TimeScale, exited by the controller clearing
# is_sliding.
#
# This used to be a bare AnimationNodeAnimation, and the comment here used to say a
# TimeScale must never go near it. The reasoning behind that still holds and is worth
# keeping: the state machine plays the clip on its own clock while pilot9.gd::_slide_time
# runs in _physics_process, and the only reason those two agree is that they run at the same
# rate. Scale the clip by anything the controller does not also scale its clock by, and the
# animation drifts away from the distance curve driving the body, silently.
#
# Neither thing written to this scale breaks that rule; both use it.
#
#   * The hold writes 0.0, and the controller freezes _slide_time on exactly those frames
#     (see _apply_slide_velocity). Both clocks stop together and start again together, so the
#     offset between them at the end of the hold is the offset they had going in.
#   * The running value is pilot9.gd's `slide_time_scale` - 2.0 by default since
#     2026-09-11 - and the controller advances _slide_time by delta * that same export. One
#     number, read by both halves. See docs/specs/pilot9-slide-rate.md.
#
# What is still forbidden is a rate ONE side does not know about, and any rate that varies -
# a lerped ease like the crouch's would drift by the integral of the ease every single time.
#
# Running at one rate is only half of staying in step, though: the two clocks also have to
# START together, and the state machine's does not - it starts whenever the machine gets
# round to entering the state, which is late by a frame at best and by a whole blocked fade
# at worst. Hence the TimeSeek beside the TimeScale, which pilot9_animation.gd uses to drag
# the clip onto pilot9.gd's `_slide_time` the frame the state opens. Seek what the state
# machine got wrong; never scale it.
func _ensure_slide_state(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		push_error("%s has no AnimationTree" % OUT)
		return false
	var sm := at.tree_root as AnimationNodeStateMachine
	if sm == null:
		push_error("%s's AnimationTree root is not an AnimationNodeStateMachine" % OUT)
		return false

	var clip := AnimationNodeAnimation.new()
	clip.animation = SLIDE_CLIP

	var scale := AnimationNodeTimeScale.new()

	var bt := AnimationNodeBlendTree.new()
	bt.add_node("Clip", clip, Vector2(-160, 40))
	bt.add_node(SLIDE_SEEK_NODE, AnimationNodeTimeSeek.new(), Vector2(0, 40))
	bt.add_node(SLIDE_SCALE_NODE, scale, Vector2(180, 40))
	bt.set_node_position("output", Vector2(440, 40))
	# Clip -> SlideSeek -> SlideScale -> output. The seek sits INSIDE the scale on purpose:
	# a seek request is a position, not a delta, so it reaches the clip unscaled and lands on
	# the clip second it names whatever the scale is doing - including a scale of 0, which is
	# what the hold pins it with.
	bt.connect_node(SLIDE_SEEK_NODE, 0, "Clip")
	bt.connect_node(SLIDE_SCALE_NODE, 0, SLIDE_SEEK_NODE)
	bt.connect_node("output", 0, SLIDE_SCALE_NODE)

	if sm.has_node(SLIDE_STATE):
		sm.remove_node(SLIDE_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(SLIDE_STATE, bt, Vector2(630, 800))

	# Entering outranks the crouch and the jump at 0. is_crouching is cleared on the frame a
	# slide starts, so `Locomotion -> crouch` cannot actually be live at the same time - the
	# priority is there to say which one wins if that ever stops being true.
	_set_transition(sm, "Locomotion", SLIDE_STATE, 0.15, "is_sliding", 0)
	# Coming down from a jump the tree is in `fall`, and on the landing frame it is `fall` or
	# `jump_land` depending on timing. A buffered slide (docs/specs/pilot9-jump-slide.md)
	# flips is_sliding on that frame, so both airborne states need an is_sliding exit or the
	# entry routes fall -> jump_land -> Locomotion -> slide over three stacked fades. Priority
	# 0 puts each ahead of its plain-landing sibling (fall -> jump_land and
	# jump_land -> Locomotion are the default priority 1). No `jump -> slide`: is_sliding
	# cannot be true while velocity.y > 0 - the buffer refuses to arm while rising.
	_set_transition(sm, "fall", SLIDE_STATE, 0.1, "is_sliding", 0)
	_set_transition(sm, "jump_land", SLIDE_STATE, 0.1, "is_sliding", 0)
	# Same priority argument as the crouch's, for the same reason: cancelling into a jump
	# clears is_sliding on the frame it launches, so `-> jump` and `-> Locomotion` are both
	# eligible and the leap has to win or it plays as a stand-up.
	_set_transition(sm, SLIDE_STATE, "jump", 0.1, "velocity.y > 0", 0)
	_set_transition(sm, SLIDE_STATE, "fall", 0.2, "not is_on_floor() and velocity.y <= 0", 1)
	# The stand-up, and the only ordinary way out. There is deliberately NO `slide -> crouch`
	# transition: a slide never hands off into a crouch (that was the 2026-09-07 rule and it
	# cost the player every metre per second the slide earned - see
	# docs/specs/pilot9-slide-stand.md, which reverses docs/specs/pilot9-slide-crouch.md).
	# is_crouching cannot be true while is_sliding is, so such a transition would be dead
	# wiring; tests/test_pilot9_slide_stand.gd asserts its absence rather than trusting that.
	_set_transition(sm, SLIDE_STATE, "Locomotion", 0.2, "not is_sliding", 2)

	# RC's two landing transitions, re-stated here with a guard on top - the builder owns
	# them now, so this is the place to change them.
	#
	# A fade in progress blocks every transition in the machine for its whole length,
	# `jump_land -> slide` included. That is what broke the buffered slide: the tree reads
	# is_on_floor() the moment move_and_slide() lands him, which is up to a frame BEFORE
	# _handle_crouch_and_slide() spends the buffered press, so it would open a 0.2 s fade
	# into `jump_land` and the slide could not start until that fade had run out. The clip
	# was then a fifth of a second behind the controller's clock, and the hold froze it on
	# whatever frame it had reached - 10 or 15 rather than SLIDE_HOLD_FRAME.
	#
	# So the landing yields: with a press already waiting for the ground, `fall` and `jump`
	# hold for the one frame it takes the controller to start the slide, and the machine
	# takes `-> slide` instead. Only that frame is affected - slide_pending() is false on
	# every ordinary landing, and false again the instant the press is spent or dropped.
	#
	# The seek in the blend tree above still stands behind this: it covers the frames the
	# tree needs to reach the state at all, and any other way it can arrive late.
	_set_transition(sm, "fall", "jump_land", 0.2, "is_on_floor() and not slide_pending()", 1)
	_set_transition(sm, "jump", "jump_land", 0.2, "is_on_floor() and not slide_pending()", 1)

	print("  state \"%s\" -> %s (TimeScale + TimeSeek), %d states, %d transitions"
		% [SLIDE_STATE, SLIDE_CLIP, sm.get_node_list().size(), sm.get_transition_count()])
	return true


func _set_transition(sm: AnimationNodeStateMachine, from: StringName, to: StringName,
		xfade: float, expression: String, priority: int) -> void:
	if sm.has_transition(from, to):
		sm.remove_transition(from, to)
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	t.advance_expression = expression
	t.priority = priority
	sm.add_transition(from, to, t)


# -- climb ----------------------------------------------------------------------------

# The slide's trick on two axes, plus the two contact points the slide never needed.
#
# `P.climbing` was exported without In Place, so its Hips walk up and forward over 1.15 s.
# That travel cannot stay in the clip for the two reasons _ensure_slide_motion() lays out -
# only the mesh would move, and a root-motion track cannot be cross-faded. So it is baked
# out to a pair of normalised curves on the controller and the clip's Hips Y and Z are then
# locked to their first key. X is kept: it is the lateral sway on the pull-up.
#
# Two things here are NOT in the slide, and both come from the same fact: a mantle touches
# the world twice, at the catch and at the landing, and a slide never leaves the floor.
#
# 1. **motion_scale.** The retargeter divides every position track by
#    Skeleton3D.motion_scale (1.0608 on this rig) and AnimationMixer multiplies it back on
#    playback. Metres therefore need the multiply, or every distance is 6% short. Measured:
#    the Hips track reads 1.782 m of rise and the mesh actually rises 1.890 m.
#
# 2. **The clip's own travel is NOT what the body should travel.** FK'd at frame 1 his hand
#    contact sits 1.583 m above his origin; FK'd at the last frame his soles sit 0.247 m
#    above it. So a catch that puts his hands ON the lip and a landing that puts his soles
#    ON the top are 1.336 m apart - not the 1.890 m the Hips walk. Driving the authored
#    rise would leave him finishing about a third of a metre in the air above the platform,
#    with his hands floating over the lip through the middle of the pull.
#
#    So the distances are derived from the two poses that touch geometry, and the authored
#    travel is kept only for the SHAPE of the stand-up and for climb_inset, which is how far
#    in from the edge he lands.
#
# 3. **Between the two contacts the hands are the anchor, not the Hips.** Through the pull the
#    body is placed so his hands stay on the lip - see _climb_path(). The authored Hips walk
#    let them sag a quarter of a metre off the edge on this rig.
#
# What is written onto scripts/pilot9.gd: the two curves, the clip length, the rise and the
# reach in metres, the inset, and the two contact offsets the snaps subtract from the lip.
func _ensure_climb_motion(root: Node) -> bool:
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(CLIMB_CLIP):
		push_error("no '%s' clip in the library - _ensure_glb_clips() did not run" % CLIMB_CLIP)
		return false
	var skel := root.get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		push_error("no character/Armature/GeneralSkeleton - the climb's contact points are " +
			"measured by forward kinematics off that skeleton and cannot be guessed")
		return false

	var anim := ap.get_animation(CLIMB_CLIP)
	var track := anim.find_track(NodePath(SLIDE_MOTION_TRACK), Animation.TYPE_POSITION_3D)
	if track == -1:
		push_error(("'%s' has no position track on '%s'. Either the retarget did not run " +
			"(paths would still read Armature/Skeleton3D) or the action no longer animates " +
			"the hips at all.") % [CLIMB_CLIP, SLIDE_MOTION_TRACK])
		return false

	var length := anim.length
	var scale := skel.motion_scale
	var p0: Vector3 = anim.position_track_interpolate(track, 0.0)
	var p1: Vector3 = anim.position_track_interpolate(track, length)
	var rise := (p1.y - p0.y) * scale
	var reach := (p1.z - p0.z) * scale
	if rise < CLIMB_MIN_RISE:
		push_error(("'%s' carries only %.3f m of rise. It was exported In Place, or upside " +
			"down - the mantle's whole arc is this track and there is nothing sensible to " +
			"fall back on.") % [CLIMB_CLIP, rise])
		return false

	# The authored Hips travel per sample, in metres, read BEFORE the lock below destroys it.
	# Only the stand-up half of the path uses it - see _climb_path().
	var hips := PackedVector2Array()
	for i in CLIMB_CURVE_SAMPLES + 1:
		var d := (anim.position_track_interpolate(track,
			float(i) / float(CLIMB_CURVE_SAMPLES) * length) - p0) * scale
		hips.append(Vector2(d.y, d.z))

	# Both axes, unlike the slide's Z-only lock. What is left animates in place and
	# cross-fades like every other clip in the tree.
	for k in anim.track_get_key_count(track):
		var v: Vector3 = anim.track_get_key_value(track, k)
		v.y = p0.y
		v.z = p0.z
		anim.track_set_key_value(track, k, v)

	# Measured on the LOCKED clip, which is what actually plays, and in his own frame - the
	# retarget bakes the Armature to identity, so a bone's global pose here is already
	# metres relative to the body origin.
	if not _has_bones(skel, CLIMB_HAND_BONES) or not _has_bones(skel, CLIMB_FOOT_BONES):
		push_error(("could not find %s / %s on the retargeted rig - the entry and exit " +
			"snaps are measured between them.") % [str(CLIMB_HAND_BONES), str(CLIMB_FOOT_BONES)])
		return false
	var release := _climb_pull_end(skel, anim, length)
	if release == -1:
		return false
	var toes_rest := _contact_point(skel, null, 0.0, CLIMB_FOOT_BONES)
	_settle_climb_stand_up(skel, anim, track, length, release, p0.y, toes_rest.y)

	var hand := _contact_point(skel, anim, 0.0, CLIMB_HAND_BONES)
	var toes_end := _contact_point(skel, anim, length, CLIMB_FOOT_BONES)
	# The toe bone sits a little above the sole even when he is standing on the floor, and
	# the rest pose is where that offset is read from. Subtracting it turns "where the toes
	# are" into "where the ground under them is", which is what the exit snap wants.
	var foot := Vector3(toes_end.x, toes_end.y - toes_rest.y, toes_end.z)

	var target := Vector2(hand.y - foot.y, hand.z - foot.z + reach)
	var path := _climb_path(skel, anim, length, hips, target, release)
	if path.is_empty():
		return false
	var curve_y := _climb_curve(path, 0, target.x)
	var curve_z := _climb_curve(path, 1, target.y)

	root.set("climb_motion_y", curve_y)
	root.set("climb_motion_z", curve_z)
	root.set("climb_duration", length)
	root.set("climb_speed", CLIMB_SPEED)
	root.set("climb_rise", hand.y - foot.y)
	root.set("climb_reach", hand.z - foot.z + reach)
	root.set("climb_inset", reach)
	root.set("climb_hand_offset", hand)
	root.set("climb_foot_offset", foot)
	for prop in CLIMB_BAKED:
		if root.get(prop) == null:
			push_error(("scripts/pilot9.gd declares no '%s'. Object.set() drops an unknown " +
				"property silently, so the mantle would ship with no path at all and " +
				"nothing in the log.") % prop)
			return false

	print(("  clip \"%s\" locked in place (Y and Z); %.3f m up / %.3f m in authored over " +
		"%.3fs, driven %.3f m up / %.3f m forward, landing %.3f m in")
		% [CLIMB_CLIP, rise, reach, length, hand.y - foot.y, hand.z - foot.z + reach, reach])
	print("    hands at %v on frame 1, soles at %v on the last - the snaps' two anchors"
		% [hand, foot])
	return true


# The body's path over the mantle, in metres (x = up, y = forward), one entry per sample.
# Two halves, because the clip does two different things:
#
# 1. **The pull - hands held on the lip.** From the catch to the end of the pull (the sample
#    where his hands sit lowest against his own origin) the body is placed so the hand
#    contact stays exactly where frame 1 put it: offset = hand(0) - hand(u). The authored
#    Hips travel is NOT used here, and that is the fix of 2026-09-26. Mixamo's travel was
#    authored for Mixamo's arms; on pilot9's retargeted rig it let his hands sag ~0.23 m
#    below the lip and ~0.23 m out from the wall through the middle of the pull. Anchoring
#    the body to the hands is correct on any rig by construction.
# 2. **The stand-up - the authored arc.** After the pull the hands leave the lip, so the
#    authored Hips travel takes over, bent by a smoothstep so it still lands on `target` (the
#    exit snap's soles-on-the-top endpoint). The handover is blended over
#    CLIMB_GRIP_RELEASE_BLEND so his velocity does not kink where the halves meet.
#
# `release` is the sample the pull ends on - see _climb_pull_end().
func _climb_path(skel: Skeleton3D, anim: Animation, length: float,
		hips: PackedVector2Array, target: Vector2, release: int) -> PackedVector2Array:
	var n := CLIMB_CURVE_SAMPLES
	var grip := PackedVector2Array()
	for i in n + 1:
		var h := _contact_point(skel, anim, float(i) / float(n) * length, CLIMB_HAND_BONES)
		grip.append(Vector2(h.y, h.z))
	var anchored := PackedVector2Array()
	for i in n + 1:
		anchored.append(grip[0] - grip[i])

	var ur := float(release) / float(n)
	var at_release := anchored[release]
	var authored_rest := hips[n] - hips[release]
	var correction := target - at_release - authored_rest
	var path := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / float(n)
		if i <= release:
			path.append(anchored[i])
			continue
		var stand := at_release + (hips[i] - hips[release]) 			+ correction * smoothstep(0.0, 1.0, (u - ur) / (1.0 - ur))
		var w := smoothstep(0.0, 1.0, (u - ur) / CLIMB_GRIP_RELEASE_BLEND)
		path.append(anchored[i].lerp(stand, w))
	path[n] = target   # exact, so the curve's last point is 1.0 on both axes
	print("    pull ends at %.0f%% of the clip, hands held on the lip until then" % (ur * 100.0))
	return path


# The sample, of CLIMB_CURVE_SAMPLES, where the pull ends: his hands at their lowest against
# his own origin. Everything before it is the pull (_climb_path() holds the hands on the lip),
# everything after it the stand-up (_settle_climb_stand_up() lowers the pose onto the origin).
#
# Returns -1 (after push_error) when the clip has no recognisable pull.
func _climb_pull_end(skel: Skeleton3D, anim: Animation, length: float) -> int:
	var n := CLIMB_CURVE_SAMPLES
	var release := -1
	var lowest := INF
	for i in range(int(n * 0.1), int(n * 0.9) + 1):
		var y := _contact_point(skel, anim, float(i) / float(n) * length, CLIMB_HAND_BONES).y
		if y < lowest:
			lowest = y
			release = i
	if release <= int(n * 0.1) or release >= int(n * 0.9):
		push_error(("climb_up's hands never finish a pull (lowest at sample %d of %d) - " +
			"the clip is not a pull-up any more, and anchoring the body to its hands would " +
			"drag him anywhere.") % [release, n])
		return -1
	return release


# Lowers the locked Hips over the stand-up so the clip's last frame stands on his own origin,
# the way every Locomotion pose does. The fix for the exit pop of 2026-09-26.
#
# Locking Hips Y at its frame-1 height (the hang) left the end pose with his soles ~0.26 m
# above his origin, so the exit snap - soles on the top - parked the origin, and the capsule
# with it, 0.26 m inside the platform. On the next frame the physics pushed him out in one
# step (origin and camera +0.23 m in a frame) and the 0.2 s fade to Locomotion floated the
# mesh 0.2 m over the top before settling it. Settled here, the origin ends ON the top: the
# snap is exact, the capsule comes back clear of the floor, and the fade blends two poses
# that already stand in the same place.
#
# Only after `release`, so the pull - and the hands held on the lip through it - is untouched.
# Eased with a smoothstep over the whole stand-up, so the settle has no velocity on the last
# frame. The mesh's world path does not change: _climb_path() measures this modified clip, so
# the body is carried up by exactly what the pose is lowered by. Only the origin (the capsule
# and the camera) moves differently, and it now finishes where the feet are.
func _settle_climb_stand_up(skel: Skeleton3D, anim: Animation, track: int, length: float,
		release: int, hips_y: float, toes_rest_y: float) -> void:
	var soles := _contact_point(skel, anim, length, CLIMB_FOOT_BONES).y - toes_rest_y
	# Key values are pre-motion_scale - see the note on _ensure_climb_motion().
	var drop := soles / skel.motion_scale
	var ur := float(release) / float(CLIMB_CURVE_SAMPLES)
	for k in anim.track_get_key_count(track):
		var u := anim.track_get_key_time(track, k) / length
		if u <= ur:
			continue
		var v: Vector3 = anim.track_get_key_value(track, k)
		v.y = hips_y - drop * smoothstep(0.0, 1.0, (u - ur) / (1.0 - ur))
		anim.track_set_key_value(track, k, v)
	print("    stand-up settled %.3f m so the last frame stands on his origin" % soles)


# One axis of _climb_path() as a normalised curve: time fraction in, distance fraction out.
# Linear tangents on every point, like the slide's - a curve that overshoots between samples
# is a body that lurches between them.
#
# Deliberately NOT clamped to 0..1. The Y curve rises past 1.0 near the top (the pull over
# the lip before he settles back onto it) and the Z curve dips below 0 at the start (the
# swing back before the pull); both are the arc the spec asks for, and Curve's default 0..1
# value range would quietly flatten them.
func _climb_curve(path: PackedVector2Array, axis: int, total: float) -> Curve:
	var curve := Curve.new()
	curve.min_value = -1.0
	curve.max_value = 2.0
	var n := path.size() - 1
	for i in n + 1:
		var idx := curve.add_point(Vector2(float(i) / float(n), path[i][axis] / total))
		curve.set_point_left_mode(idx, Curve.TANGENT_LINEAR)
		curve.set_point_right_mode(idx, Curve.TANGENT_LINEAR)
	return curve


# The midpoint of `bones` at time `t`, in the skeleton's own frame. `anim` null means the
# rest pose. Every name is checked by _has_bones() before this is called.
#
# Forward kinematics by hand rather than through an AnimationPlayer: this script never puts
# the scene in a tree, and a mixer that is not being processed applies nothing. Position
# tracks are multiplied by motion_scale because that is what AnimationMixer does on playback
# - see the note on _ensure_climb_motion().
func _contact_point(skel: Skeleton3D, anim: Animation, t: float, bones: Array) -> Vector3:
	var count := skel.get_bone_count()
	var local: Array[Transform3D] = []
	local.resize(count)
	for i in count:
		local[i] = skel.get_bone_rest(i)
	if anim != null:
		for tr in anim.get_track_count():
			var b := skel.find_bone(str(anim.track_get_path(tr)).get_slice(":", 1))
			if b == -1:
				continue
			var x := local[b]
			match anim.track_get_type(tr):
				Animation.TYPE_POSITION_3D:
					x.origin = anim.position_track_interpolate(tr, t) * skel.motion_scale
				Animation.TYPE_ROTATION_3D:
					x.basis = Basis(anim.rotation_track_interpolate(tr, t)).scaled(x.basis.get_scale())
				Animation.TYPE_SCALE_3D:
					x.basis = x.basis.orthonormalized().scaled(anim.scale_track_interpolate(tr, t))
			local[b] = x

	var world: Array[Transform3D] = []
	world.resize(count)
	for i in count:
		var parent := skel.get_bone_parent(i)
		world[i] = local[i] if parent == -1 else world[parent] * local[i]

	var sum := Vector3.ZERO
	for bone_name in bones:
		sum += world[skel.find_bone(bone_name)].origin
	return sum / float(bones.size())


func _has_bones(skel: Skeleton3D, bones: Array) -> bool:
	for bone_name in bones:
		if skel.find_bone(bone_name) == -1:
			return false
	return true


# The `climb` state: one clip, entered and left on `is_climbing`.
#
# A plain AnimationNodeAnimation for the slide's reason - the state machine plays the clip on
# its own clock while pilot9.gd::_climb_time runs in _physics_process. What holds them
# together is that both run at CLIMB_SPEED off real time: the clip is compressed by its own
# custom timeline here, and _apply_climb_motion() advances _climb_time by delta * climb_speed.
# A TimeScale NODE would be the wrong tool - it would compress only the clip, and the path
# would know nothing about it. The custom timeline keeps the state a plain AnimationNodeAnimation.
#
# Note there is deliberately no trim of the tail, the way the slide cuts its run-out at
# frame 75. The mantle's tail is the stand-up and it is worth keeping; the "hands back a
# beat early" is done by the exit cross-fade eating it, not by dropping keys.
func _ensure_climb_state(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		push_error("%s has no AnimationTree" % OUT)
		return false
	var sm := at.tree_root as AnimationNodeStateMachine
	if sm == null:
		push_error("%s's AnimationTree root is not an AnimationNodeStateMachine" % OUT)
		return false

	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(CLIMB_CLIP):
		push_error("no '%s' clip to time the `climb` state against" % CLIMB_CLIP)
		return false

	var clip := AnimationNodeAnimation.new()
	clip.animation = CLIMB_CLIP
	# Compress the authored clip to 1 / CLIMB_SPEED of its length. stretch_time_scale remaps
	# the whole clip onto the shorter timeline, so it plays CLIMB_SPEED times faster while
	# staying a plain AnimationNodeAnimation. _apply_climb_motion() scales _climb_time by the
	# same CLIMB_SPEED, which is the whole reason the clip and the path still finish together.
	clip.use_custom_timeline = true
	clip.timeline_length = ap.get_animation(CLIMB_CLIP).length / CLIMB_SPEED
	clip.stretch_time_scale = true

	if sm.has_node(CLIMB_STATE):
		sm.remove_node(CLIMB_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(CLIMB_STATE, clip, Vector2(630, 980))

	# Entered from both airborne states. The mantle starts automatically while his feet are
	# off the floor, so depending on where in the arc it triggers the tree is in `jump`
	# (still rising) or `fall` (past apex). A fingertip catch is usually at or past apex,
	# which makes `fall` the common path, but a mantle that starts off a still-rising jump
	# needs the `jump` edge too.
	#
	# The 0.08 s cut is near-hard on purpose: the entry snap has already teleported him to
	# the lip and turned him to the wall, and a longer fade blends the previous airborne pose
	# across that teleport, which reads as a lurch.
	_set_transition(sm, "fall", CLIMB_STATE, 0.08, "is_climbing", 0)
	_set_transition(sm, "jump", CLIMB_STATE, 0.08, "is_climbing", 0)
	# One exit. No `climb -> fall` (collision is off, he cannot leave the floor mid-mantle)
	# and no `climb -> jump` (not cancellable - a buffered jump fires from Locomotion after
	# the state has already been left). The ~0.2 s fade eats the last of the stand-up so he
	# finishes it under player control rather than watching it.
	_set_transition(sm, CLIMB_STATE, "Locomotion", 0.2, "not is_climbing", 0)

	print("  state \"%s\" -> %s at %.2fx (timeline %.3fs), %d states, %d transitions"
		% [CLIMB_STATE, CLIMB_CLIP, CLIMB_SPEED, clip.timeline_length,
		sm.get_node_list().size(), sm.get_transition_count()])
	return true


# The `wall_run` state: one looping clip, entered and left on `is_wall_running`.
#
# A plain AnimationNodeAnimation, no custom timeline - unlike the slide and the climb, nothing
# in pilot9.gd paces its own clock against this clip's. _apply_wall_run_velocity() drives
# position from _wall_run_time directly, and the clip's own two Hips tracks hold a single key
# each (in place, not root motion - Blender exported it that way, unlike P.slide/P.climbing),
# so there is nothing here to bake or lock. It just loops at authored speed for as long as
# is_wall_running is true.
#
# The 30 degree lean off the wall is a separate channel - see _align_model_to_slope() in
# pilot9.gd, which drives character.rotation directly and does not go through this state at
# all. This state is only the leg cycle: the ground sprint's, since 2026-09-26.
func _ensure_wall_run_state(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		push_error("%s has no AnimationTree" % OUT)
		return false
	var sm := at.tree_root as AnimationNodeStateMachine
	if sm == null:
		push_error("%s's AnimationTree root is not an AnimationNodeStateMachine" % OUT)
		return false

	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(WALL_RUN_CLIP):
		push_error("no '%s' clip to wire the `wall_run` state to" % WALL_RUN_CLIP)
		return false

	var clip := AnimationNodeAnimation.new()
	clip.animation = WALL_RUN_CLIP

	if sm.has_node(WALL_RUN_STATE):
		sm.remove_node(WALL_RUN_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(WALL_RUN_STATE, clip, Vector2(630, 1100))

	# Entered from both airborne states, same reasoning as the climb's: a wall-run can start
	# off a still-rising jump (`jump`) or past the apex (`fall`), and gate 1 in
	# _wall_run_gates() ("Airborne. Never off the floor.") means Locomotion never needs the
	# transition at all.
	_set_transition(sm, "jump", WALL_RUN_STATE, 0.1, "is_wall_running", 0)
	_set_transition(sm, "fall", WALL_RUN_STATE, 0.1, "is_wall_running", 0)
	# Same priority argument as the slide's and the crouch's: the wall-jump sets velocity.y
	# positive and is_wall_running false in the same call (_take_wall_jump(), then
	# _end_wall_run()), so both exits are eligible on that frame and the leap has to win or it
	# plays as a plain fall.
	#
	# `not is_wall_running` on the leap too, not just the fall: attaching on a still-rising jump
	# keeps velocity.y positive for the rest of the rise (see _apply_wall_run_velocity()), and a
	# bare `velocity.y > 0` would bounce him wall_run -> jump -> wall_run every frame of it - the
	# run that starts, stops, then starts again.
	_set_transition(sm, WALL_RUN_STATE, "jump", 0.1, "velocity.y > 0 and not is_wall_running", 0)
	_set_transition(sm, WALL_RUN_STATE, "fall", 0.2, "not is_wall_running", 1)
	# The mantle out of a run goes straight to `climb`, same near-hard cut as the airborne
	# entries. Without it the tree went wall_run -> fall -> climb, and the wall-run's lean
	# blending out through `fall` played over the mantle's first frames as a tilt. Priority 0
	# beats the `fall` exit, which is also eligible on that frame.
	_set_transition(sm, WALL_RUN_STATE, CLIMB_STATE, 0.08, "is_climbing", 0)

	print("  state \"%s\" -> %s, %d states, %d transitions"
		% [WALL_RUN_STATE, WALL_RUN_CLIP, sm.get_node_list().size(), sm.get_transition_count()])
	return true


# The `rail` state: the two gear clips through a Blend2, entered and left on `is_rail_grinding`.
#
# A blend rather than two states because the gear flips while he rides, and a state change
# restarts a cycle where a blend keeps both running in step - scripts/pilot9_animation.gd eases
# RailGear's amount toward is_rail_sprinting over ~0.15 s. Neither clip carries root motion
# (see GLB_CLIPS), so nothing here is baked or locked; the controller places him on the curve.
func _ensure_rail_state(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		push_error("%s has no AnimationTree" % OUT)
		return false
	var sm := at.tree_root as AnimationNodeStateMachine
	if sm == null:
		push_error("%s's AnimationTree root is not an AnimationNodeStateMachine" % OUT)
		return false

	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	for clip_name in [RAIL_GRIND_CLIP, RAIL_SPRINT_CLIP]:
		if ap == null or not ap.has_animation(clip_name):
			push_error("no '%s' clip to wire the `rail` state to" % clip_name)
			return false

	var bt := AnimationNodeBlendTree.new()
	var grind := AnimationNodeAnimation.new()
	grind.animation = RAIL_GRIND_CLIP
	var sprint := AnimationNodeAnimation.new()
	sprint.animation = RAIL_SPRINT_CLIP
	var gear := AnimationNodeBlend2.new()
	bt.add_node(&"Grind", grind, Vector2(0, 0))
	bt.add_node(&"Sprint", sprint, Vector2(0, 160))
	bt.add_node(RAIL_GEAR_NODE, gear, Vector2(240, 60))
	bt.connect_node(RAIL_GEAR_NODE, 0, &"Grind")
	bt.connect_node(RAIL_GEAR_NODE, 1, &"Sprint")
	bt.connect_node(&"output", 0, RAIL_GEAR_NODE)

	if sm.has_node(RAIL_STATE):
		sm.remove_node(RAIL_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(RAIL_STATE, bt, Vector2(850, 1100))

	# Air only, so the airborne states are the real entries. Locomotion too, for a catch on the
	# first frame off a ledge before Locomotion -> fall has fired.
	for from in [&"jump", &"fall", &"Locomotion"]:
		_set_transition(sm, from, RAIL_STATE, 0.1, "is_rail_grinding", 0)
	# The wall-run's exits and the wall-run's reasoning: the jump off sets velocity.y positive
	# and is_rail_grinding false in one call, so the leap takes priority 0 over the fall, and the
	# leap names `not is_rail_grinding` too so a rail sloping up (positive velocity.y while
	# riding) cannot bounce him rail -> jump -> rail.
	_set_transition(sm, RAIL_STATE, "jump", 0.1, "velocity.y > 0 and not is_rail_grinding", 0)
	_set_transition(sm, RAIL_STATE, "fall", 0.2, "not is_rail_grinding", 1)

	print("  state \"%s\" -> %s / %s, %d states, %d transitions"
		% [RAIL_STATE, RAIL_GRIND_CLIP, RAIL_SPRINT_CLIP, sm.get_node_list().size(),
		sm.get_transition_count()])
	return true


# -- vault ----------------------------------------------------------------------------

# The mantle's bake, pointed at a clip that goes OVER rather than up. See
# docs/specs/pilot9-vault.md, "Motion".
#
# Mixamo's "Jumping" was downloaded without In Place: its Hips run 5.4 m forward and arc 0.8 m
# up and back down over 1.2 s. As with the slide and the mantle that travel is taken out of the
# clip and baked into curves the controller drives the body along, and the clip is locked.
#
# The clip is cut into five moments, all measured here off the clip itself (FK'd on pilot9's
# own skeleton, so every number is in his metres):
#
#   takeoff   - the last sample before the plant with a toe still on the floor
#   plant     - the first sample both wrists are still (under VAULT_PLANT_SPEED)
#   release   - the first sample after it either wrist moves again
#   touchdown - the first sample after the release a toe is back on the floor
#
# and the body path is built in three pieces:
#
# 1. **Clip start -> plant: the authored Hips travel.** The controller warps it at runtime so
#    the hands land on the detected top edge - see pilot9.gd::_vault_offset().
# 2. **Plant -> release: hands pinned.** The body is placed so the wrists' midpoint stays where
#    the plant put it, the mantle's _climb_path() method. Mixamo's hands slide ~0.2 m forward
#    while "planted"; anchored, they do not.
# 3. **Release -> end: the authored travel again**, continued from wherever the pin left him.
#
# Y is locked differently from the mantle's. Up to the release the lock holds Hips Y at its
# first key, so the whole arc is the body's. From the release to the touchdown the lock eases
# off, and from the touchdown on the clip's own Hips Y plays untouched - the run-out is an
# ordinary in-place run, feet on his origin, which is what lets the controller hand him to
# physics on the release and land him with move_and_slide().
func _ensure_vault_motion(root: Node) -> bool:
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(VAULT_CLIP):
		push_error("no '%s' clip in the library - _ensure_fbx_clips() did not run" % VAULT_CLIP)
		return false
	var skel := root.get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		push_error("no character/Armature/GeneralSkeleton to measure the vault against")
		return false
	var hands := ["LeftHand", "RightHand"]
	if not _has_bones(skel, hands) or not _has_bones(skel, CLIMB_FOOT_BONES):
		push_error("the retargeted rig is missing %s / %s - the vault is measured between them"
			% [str(hands), str(CLIMB_FOOT_BONES)])
		return false

	var anim := ap.get_animation(VAULT_CLIP)
	var track := anim.find_track(NodePath(SLIDE_MOTION_TRACK), Animation.TYPE_POSITION_3D)
	if track == -1:
		push_error("'%s' has no position track on '%s'" % [VAULT_CLIP, SLIDE_MOTION_TRACK])
		return false

	var n := VAULT_CURVE_SAMPLES
	var length := anim.length
	var dt := length / float(n)
	var scale := skel.motion_scale
	var p0: Vector3 = anim.position_track_interpolate(track, 0.0)

	# Everything as authored, BEFORE the lock: Mixamo's world, origin fixed, Hips carrying him.
	var hips := PackedVector3Array()
	var lh := PackedVector3Array()
	var rh := PackedVector3Array()
	var low_toe := PackedFloat32Array()
	for i in n + 1:
		var t := float(i) * dt
		hips.append((anim.position_track_interpolate(track, t) - p0) * scale)
		lh.append(_contact_point(skel, anim, t, ["LeftHand"]))
		rh.append(_contact_point(skel, anim, t, ["RightHand"]))
		low_toe.append(minf(_contact_point(skel, anim, t, ["LeftToes"]).y,
			_contact_point(skel, anim, t, ["RightToes"]).y))
	if hips[n].z < VAULT_MIN_TRAVEL:
		push_error(("'%s' travels only %.2f m forward. It was downloaded In Place - the vault " +
			"is driven entirely by that travel. Re-download it from Mixamo with In Place OFF.")
			% [VAULT_CLIP, hips[n].z])
		return false
	var toes_rest := _contact_point(skel, null, 0.0, CLIMB_FOOT_BONES).y

	# The four moments. The hands do NOT plant together on this rig: the left lands first
	# (~46%), the right ~0.07 s later, and the left lifts while the right is still down (~62%).
	# So each wrist gets its own window, and the plant is the first hand down and the release
	# the last hand up. Measured 2026-09-27; see the vault spec's "Built" notes.
	var lwin := _vault_plant_window(lh, dt)
	var rwin := _vault_plant_window(rh, dt)
	if lwin.x == -1 or rwin.x == -1:
		push_error(("'%s' has a wrist that never plants (left %v, right %v) - it is not a " +
			"hand-plant vault") % [VAULT_CLIP, lwin, rwin])
		return false
	var plant := mini(lwin.x, rwin.x)
	var release := maxi(lwin.y, rwin.y) + 1
	var takeoff := 0
	for i in plant:
		if low_toe[i] <= toes_rest + VAULT_GROUND_EPS:
			takeoff = i
	var touchdown := -1
	for i in range(release + 1, n + 1):
		if low_toe[i] <= toes_rest + VAULT_GROUND_EPS:
			touchdown = i
			break
	if touchdown == -1:
		push_error("'%s' never puts a foot back down after the hands release" % VAULT_CLIP)
		return false
	var ur := float(release) / float(n)
	var utd := float(touchdown) / float(n)

	# The lock. X and Z to the first key throughout; Y to the first key up to the release, then
	# eased back onto the authored Hips Y by the touchdown - see the note above.
	for k in anim.track_get_key_count(track):
		var v: Vector3 = anim.track_get_key_value(track, k)
		var w := _vault_y_lock(anim.track_get_key_time(track, k) / length, ur, utd)
		v = Vector3(p0.x, lerpf(v.y, p0.y, w), p0.z)
		anim.track_set_key_value(track, k, v)

	# The body path, and each wrist against it on the LOCKED clip, which is what plays.
	var body := PackedVector2Array()   # x = up, y = forward, metres from the start origin
	var lgrip := PackedVector2Array()
	var rgrip := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / float(n)
		body.append(Vector2(hips[i].y * _vault_y_lock(u, ur, utd), hips[i].z))
		var l := _contact_point(skel, anim, float(i) * dt, ["LeftHand"])
		var r := _contact_point(skel, anim, float(i) * dt, ["RightHand"])
		lgrip.append(Vector2(l.y, l.z))
		rgrip.append(Vector2(r.y, r.z))
	# Through the plant, each step moves the body by whatever keeps the planted wrists still:
	# minus their own step against the body, weighted toward the slower one. One wrist down,
	# that wrist is pinned outright; both down, the slower one wins, which is the one bearing
	# weight - and the weights cross over smoothly as the left lifts off.
	var path := PackedVector2Array()
	for i in n + 1:
		if i <= plant:
			path.append(body[i])
		elif i <= release:
			var wl := _vault_pin_weight(lh, lwin, i, dt)
			var wr := _vault_pin_weight(rh, rwin, i, dt)
			var step := -((lgrip[i] - lgrip[i - 1]) * wl + (rgrip[i] - rgrip[i - 1]) * wr) \
				/ maxf(wl + wr, 0.000001)
			path.append(path[i - 1] + step)
		else:
			var off := path[release] - body[release]
			var u := float(i) / float(n)
			path.append(Vector2(body[i].x + off.x * (1.0 - smoothstep(ur, utd, u)),
				body[i].y + off.y))

	# Where each wrist sits on the path the moment it goes down, and the point between the two -
	# the controller puts THAT on the detected top. The top is under the lower wrist.
	var lplant := path[lwin.x] + lgrip[lwin.x]
	var rplant := path[rwin.x] + rgrip[rwin.x]
	var top := minf(lplant.x, rplant.x) - VAULT_PALM
	var reach := (lplant.y + rplant.y) * 0.5
	var travel := path[n].y

	# Lowest toe over the top, anywhere between the takeoff and the touchdown. The legs swing
	# over BEFORE the hands go down on this clip (the toes are already ~0.8 m past the hands at
	# the plant), so the window is the whole flight, not the plant.
	var clearance := INF
	for i in range(takeoff, touchdown + 1):
		for toe in CLIMB_FOOT_BONES:
			var p := _contact_point(skel, anim, float(i) * dt, [toe])
			var z := path[i].y + p.z
			if absf(z - reach) <= VAULT_OVER_TOP_DEPTH * 0.5:
				clearance = minf(clearance, path[i].x + p.y - top)
	if clearance == INF:
		push_error("no toe of '%s' ever passes over the planted hands - not a vault" % VAULT_CLIP)
		return false

	var curve_y := _climb_curve(path, 0, top)
	var curve_z := _climb_curve(path, 1, travel)
	root.set("vault_motion_y", curve_y)
	root.set("vault_motion_z", curve_z)
	root.set("vault_duration", length)
	root.set("vault_travel", travel)
	root.set("vault_clip_speed", travel / length)
	root.set("vault_takeoff_time", float(takeoff) / float(n))
	root.set("vault_plant_time", float(plant) / float(n))
	root.set("vault_release_time", ur)
	root.set("vault_touchdown_time", utd)
	root.set("vault_top_height", top)
	root.set("vault_plant_reach", reach)
	root.set("vault_post_travel", path[touchdown].y - reach)
	root.set("vault_hand_spread", absf(rplant.y - lplant.y))
	root.set("vault_foot_clearance", clearance)
	root.set("vault_palm", VAULT_PALM)
	for prop in VAULT_BAKED:
		if root.get(prop) == null:
			push_error("scripts/pilot9.gd declares no '%s' - Object.set() dropped it silently" % prop)
			return false

	print(("  clip \"%s\" locked (X, Z; Y until the touchdown); %.3fs, %.2f m forward " +
		"(%.2f m/s), authored top %.3f m, hands %.3f m ahead at the plant")
		% [VAULT_CLIP, length, travel, travel / length, top, reach])
	print(("    takeoff %.0f%%  plant %.0f%%  release %.0f%%  touchdown %.0f%%  " +
		"hands to touchdown %.2f m  foot clearance %.3f m  body at release %v")
		% [100.0 * takeoff / n, 100.0 * plant / n, 100.0 * ur, 100.0 * utd, path[touchdown].y - reach,
		clearance, path[release]])
	print(("    left wrist down %.0f-%.0f%% at %v, right %.0f-%.0f%% at %v (up, forward) - " +
		"%.2f m apart along the travel")
		% [100.0 * lwin.x / n, 100.0 * lwin.y / n, lplant, 100.0 * rwin.x / n,
		100.0 * rwin.y / n, rplant, rplant.y - lplant.y])
	return true


# The samples one wrist is down for, as (first, last); (-1, -1) if it never is. Down means under
# VAULT_PLANT_SPEED to start, and staying down until it passes VAULT_LIFT_SPEED - the left wrist
# shuffles at ~2 m/s mid-plant without leaving the top, and a single threshold split its window.
func _vault_plant_window(points: PackedVector3Array, dt: float) -> Vector2i:
	var n := points.size() - 1
	for i in range(int(n * 0.2), int(n * 0.85)):
		if _vault_hand_speed(points, i, dt) < VAULT_PLANT_SPEED:
			var last := i
			while last + 1 < n and _vault_hand_speed(points, last + 1, dt) < VAULT_LIFT_SPEED:
				last += 1
			return Vector2i(i, last)
	return Vector2i(-1, -1)


# How hard a wrist holds the body at sample `i`: nothing outside its window, and inside it the
# slower the wrist the more it counts.
static func _vault_pin_weight(points: PackedVector3Array, window: Vector2i, i: int,
		dt: float) -> float:
	if i < window.x or i > window.y:
		return 0.0
	var s := _vault_hand_speed(points, i, dt) + 0.25
	return 1.0 / (s * s)


# How much of the Hips' authored Y the lock takes away at `u`: all of it up to the release, none
# of it from the touchdown on, eased between. The body path carries exactly what the lock takes.
static func _vault_y_lock(u: float, release: float, touchdown: float) -> float:
	if u <= release:
		return 1.0
	return 1.0 - smoothstep(release, touchdown, u)


# A wrist's speed at sample `i`, central difference, in m/s.
static func _vault_hand_speed(points: PackedVector3Array, i: int, dt: float) -> float:
	var a := maxi(i - 1, 0)
	var b := mini(i + 1, points.size() - 1)
	return (points[b] - points[a]).length() / (float(b - a) * dt)


# The `vault` state: the clip through a TimeSeek and a TimeScale held at 0. The controller owns
# the clock - pilot9_animation.gd seeks the clip onto pilot9.gd::vault_clip_time() every frame -
# because the vault's rate changes per vault (entry speed) and its run-up is warped per vault
# (distance to the wall), so no fixed timeline could stay under the body.
func _ensure_vault_state(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	var sm := at.tree_root as AnimationNodeStateMachine if at != null else null
	if sm == null:
		push_error("%s has no AnimationTree state machine" % OUT)
		return false
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(VAULT_CLIP):
		push_error("no '%s' clip to wire the `vault` state to" % VAULT_CLIP)
		return false

	var clip := AnimationNodeAnimation.new()
	clip.animation = VAULT_CLIP
	var scale := AnimationNodeTimeScale.new()
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("Clip", clip, Vector2(-160, 40))
	bt.add_node(VAULT_SEEK_NODE, AnimationNodeTimeSeek.new(), Vector2(0, 40))
	bt.add_node(VAULT_SCALE_NODE, scale, Vector2(180, 40))
	bt.set_node_position("output", Vector2(440, 40))
	# Same order as the slide's: the seek inside the scale, so a seek lands on the clip second it
	# names even with the scale at 0.
	bt.connect_node(VAULT_SEEK_NODE, 0, "Clip")
	bt.connect_node(VAULT_SCALE_NODE, 0, VAULT_SEEK_NODE)
	bt.connect_node("output", 0, VAULT_SCALE_NODE)

	if sm.has_node(VAULT_STATE):
		sm.remove_node(VAULT_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(VAULT_STATE, bt, Vector2(850, 980))

	# In from every state a grounded `jump` press can find the tree in - the landing ones too,
	# since a press on the frame he lands can beat the tree's own landing fade. 0.1 s: the clip
	# opens mid-stride and he is arriving from a run, so a short fade reads as continuous where
	# the mantle's hard cut would pop (docs/specs/pilot9-vault.md, "Entry").
	for from in [&"Locomotion", CROUCH_STATE, SLIDE_STATE, &"jump_land", &"fall", &"jump"]:
		_set_transition(sm, from, VAULT_STATE, 0.1, "is_vaulting", 0)
	# Out: the jump cancel (velocity.y > 0 in the same call that clears is_vaulting, so it has to
	# outrank the landing), the buffered slide, touchdown, and a vault off an edge.
	_set_transition(sm, VAULT_STATE, "jump", 0.1, "velocity.y > 0 and not is_vaulting", 0)
	_set_transition(sm, VAULT_STATE, SLIDE_STATE, 0.1, "is_sliding", 0)
	_set_transition(sm, VAULT_STATE, "Locomotion", 0.15, "not is_vaulting and is_on_floor()", 1)
	_set_transition(sm, VAULT_STATE, "fall", 0.2, "not is_vaulting and not is_on_floor()", 2)

	print("  state \"%s\" -> %s (TimeSeek + TimeScale 0, driven by the controller), %d states, %d transitions"
		% [VAULT_STATE, VAULT_CLIP, sm.get_node_list().size(), sm.get_transition_count()])
	return true


# The `dash` state: the sprint cycle through a TimeSeek and a TimeScale. No transition IN -
# pilot9.gd::_cut_to_dash_clip() hard-cuts with playback.start() from whatever state he is in, the
# mantle's pattern, so the first afterimage (dropped the same tick) is already the sprint pose.
# Out: ~0.1 s blends, all gated on `not is_dashing` so nothing leaves early.
func _ensure_dash_state(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	var sm := at.tree_root as AnimationNodeStateMachine if at != null else null
	if sm == null:
		push_error("%s has no AnimationTree state machine" % OUT)
		return false
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(DASH_CLIP):
		push_error("no '%s' clip to wire the `dash` state to" % DASH_CLIP)
		return false

	var clip := AnimationNodeAnimation.new()
	clip.animation = DASH_CLIP
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("Clip", clip, Vector2(-160, 40))
	bt.add_node(DASH_SEEK_NODE, AnimationNodeTimeSeek.new(), Vector2(0, 40))
	bt.add_node(DASH_SCALE_NODE, AnimationNodeTimeScale.new(), Vector2(180, 40))
	bt.set_node_position("output", Vector2(440, 40))
	# Seek inside the scale, as the slide's and the vault's are.
	bt.connect_node(DASH_SEEK_NODE, 0, "Clip")
	bt.connect_node(DASH_SCALE_NODE, 0, DASH_SEEK_NODE)
	bt.connect_node("output", 0, DASH_SCALE_NODE)

	if sm.has_node(DASH_STATE):
		sm.remove_node(DASH_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(DASH_STATE, bt, Vector2(1070, 980))

	# The tilted dash's exit rise (velocity.y > 0) has to outrank the plain fall.
	_set_transition(sm, DASH_STATE, "jump", 0.1,
		"not is_dashing and velocity.y > 0 and not is_on_floor()", 0)
	_set_transition(sm, DASH_STATE, "Locomotion", 0.1, "not is_dashing and is_on_floor()", 1)
	_set_transition(sm, DASH_STATE, "fall", 0.1, "not is_dashing and not is_on_floor()", 2)

	print("  state \"%s\" -> %s (TimeSeek + TimeScale, hard-cut in by the controller), %d states, %d transitions"
		% [DASH_STATE, DASH_CLIP, sm.get_node_list().size(), sm.get_transition_count()])
	return true


# -- wall climb -----------------------------------------------------------------------

# The wall climb's one bake, and it bakes no travel: the clip is In Place and the controller
# drives the body at a constant speed (see docs/specs/pilot9-wall-climb.md). What it measures
# instead, on pilot9's own skeleton:
#
# - The plants: the moments each hand reaches the face after topping out, as fractions of the
#   loop - one tap each. A hand peaks, then comes forward onto the wall; the plant is the first
#   sample after the peak within PLANT_SLOP of that hand's furthest reach.
# - The lean: the clip's climber leans back off his face - the hands reach ~0.54 m in front of
#   his origin, the toes only ~0.30 m. No slide puts both on a vertical wall, so the mesh is
#   tipped back by the angle of the line through the furthest hand and the furthest toe, degrees.
# - The reach: where that line meets his feet once tipped - the plane his hands and toes touch,
#   metres in front of his origin. pilot9.gd slides the mesh in by the gap between it and the
#   capsule's hold distance.
func _ensure_wall_climb_motion(root: Node) -> bool:
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(WALL_CLIMB_CLIP):
		push_error("no '%s' clip in the library - _ensure_fbx_clips() did not run" % WALL_CLIMB_CLIP)
		return false
	var skel := root.get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		push_error("no character/Armature/GeneralSkeleton to measure the wall climb against")
		return false
	var hands := ["LeftHand", "RightHand"]
	if not _has_bones(skel, hands) or not _has_bones(skel, CLIMB_FOOT_BONES):
		push_error("the retargeted rig is missing %s / %s - the wall climb is measured on them"
			% [str(hands), str(CLIMB_FOOT_BONES)])
		return false

	var anim := ap.get_animation(WALL_CLIMB_CLIP)
	var n := WALL_CLIMB_SAMPLES
	var phases := PackedFloat32Array()
	var hand_far := Vector3(0, 0, -INF)
	for hand in hands:
		var pts := PackedVector3Array()
		var far_z := -INF
		for i in n:
			var pt := _contact_point(skel, anim, anim.length * float(i) / float(n), [hand])
			pts.append(pt)
			far_z = maxf(far_z, pt.z)
			if pt.z > hand_far.z:
				hand_far = pt
		for i in n:
			var y := pts[i].y
			if not (y > pts[(i - 1 + n) % n].y and y >= pts[(i + 1) % n].y):
				continue
			# A peak - walk forward to where this hand meets the face.
			for k in n:
				var j := (i + k) % n
				if pts[j].z >= far_z - WALL_CLIMB_PLANT_SLOP:
					phases.append(float(j) / float(n))
					break
	if phases.is_empty():
		push_error("'%s' has no hand that tops out - not a climb" % WALL_CLIMB_CLIP)
		return false
	phases.sort()

	var toe_far := Vector3(0, 0, -INF)
	for i in n:
		for toe in CLIMB_FOOT_BONES:
			var pt := _contact_point(skel, anim, anim.length * float(i) / float(n), [toe])
			if pt.z > toe_far.z:
				toe_far = pt
	var lean := atan2(hand_far.z - toe_far.z, hand_far.y - toe_far.y)
	# Tipped back by `lean` about his feet, a point (y, z) lands at z cos - y sin: the same for
	# both contacts by construction, and that is the plane.
	var reach := toe_far.z * cos(lean) - toe_far.y * sin(lean)

	root.set("wall_climb_grab_phases", phases)
	root.set("wall_climb_hand_reach", reach)
	root.set("wall_climb_lean", rad_to_deg(lean))
	root.set("wall_climb_duration", anim.length)
	print(("  wall climb: %d plants at %s of the loop; hands reach %.3f m at %.2f m up, toes " +
		"%.3f m at %.2f m - tipped back %.1f deg, contact plane %.3f m in front of his origin")
		% [phases.size(), str(phases), hand_far.z, hand_far.y, toe_far.z, toe_far.y,
		rad_to_deg(lean), reach])
	return true


# The `wall_climb` state: the loop through a TimeScale pilot9_animation.gd drives. In from every
# state a climb can start in - on the ground (Locomotion, the crouch and the slide, both of which
# the climb ends), in the air, and off a wall-run that ran into an inside corner. 0.1 s, the
# vault's fade: he arrives from a run, and a hard cut would pop.
func _ensure_wall_climb_state(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	var sm := at.tree_root as AnimationNodeStateMachine if at != null else null
	if sm == null:
		push_error("%s has no AnimationTree state machine" % OUT)
		return false
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(WALL_CLIMB_CLIP):
		push_error("no '%s' clip to wire the `wall_climb` state to" % WALL_CLIMB_CLIP)
		return false

	var clip := AnimationNodeAnimation.new()
	clip.animation = WALL_CLIMB_CLIP
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("Clip", clip, Vector2(-160, 40))
	bt.add_node(WALL_CLIMB_SCALE_NODE, AnimationNodeTimeScale.new(), Vector2(60, 40))
	bt.set_node_position("output", Vector2(300, 40))
	bt.connect_node(WALL_CLIMB_SCALE_NODE, 0, "Clip")
	bt.connect_node("output", 0, WALL_CLIMB_SCALE_NODE)

	if sm.has_node(WALL_CLIMB_STATE):
		sm.remove_node(WALL_CLIMB_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(WALL_CLIMB_STATE, bt, Vector2(1070, 1100))

	for from in [&"Locomotion", CROUCH_STATE, SLIDE_STATE, &"jump_land", &"fall", &"jump",
			WALL_RUN_STATE]:
		_set_transition(sm, from, WALL_CLIMB_STATE, 0.1, "is_wall_climbing", 0)
	# Out: the climb jump (velocity.y > 0 in the same call that clears is_wall_climbing, so it
	# outranks the fall), the peel and the wall ending (fall). The mantle and the dash hard-cut
	# out on their own (playback.start), so neither needs a transition.
	_set_transition(sm, WALL_CLIMB_STATE, "jump", 0.1,
		"velocity.y > 0 and not is_wall_climbing", 0)
	_set_transition(sm, WALL_CLIMB_STATE, "Locomotion", 0.15,
		"not is_wall_climbing and is_on_floor()", 1)
	_set_transition(sm, WALL_CLIMB_STATE, "fall", 0.2,
		"not is_wall_climbing and not is_on_floor()", 2)

	print("  state \"%s\" -> %s (TimeScale, driven by the controller), %d states, %d transitions"
		% [WALL_CLIMB_STATE, WALL_CLIMB_CLIP, sm.get_node_list().size(), sm.get_transition_count()])
	return true


# -- blending -------------------------------------------------------------------------

# Real Controller ships its AnimationTree with `deterministic` OFF; Godot's own default is
# on. Off, a bone track whose total blend weight falls to zero keeps whatever value it last
# held instead of returning to the bone's rest - and a bone is only ever at zero weight if
# no playing clip animates it.
#
# That is fine while every clip animates the same bones, which is true of RC's own 27. It
# stopped being true the day crouch_walk arrived out of pilot9.glb: it rotates UpperChest
# (~22 degrees of hunch) and no RC clip touches that bone. So standing up blended the crouch
# out of every bone the walk shares and left UpperChest sitting at its crouched angle, for
# good - pilot9 walked away from every crouch tilted forward until the scene reloaded.
# (crouch_walk also carries a LeftFoot scale track nothing else has; it is ~1.0, so it never
# showed.)
#
# Turning the flag back on costs one thing: while crouched, the two wrists - animated by
# every RC clip, by neither GLB clip - sit at rest rather than freezing on whatever pose
# idle left them in. tests/test_pilot9_crouch.gd guards the flag against the next re-export.
# -- tredge ---------------------------------------------------------------------------

# Bakes the `tredge` clip from RC's walk_forward (the addon file every time, never written - walk
# itself is untouched) and adds the `tredge` state: idle and the clip in a Blend2, the clip
# through a TimeScale. pilot9_animation.gd drives both off his speed. The hunch, the arms and the
# gust stumble are not in the clip - they are scripts/tredge_pose.gd, at runtime.
func _ensure_tredge(root: Node) -> bool:
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var lib := ap.get_animation_library(&"") if ap != null else null
	var skel := root.get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	var sm := at.tree_root as AnimationNodeStateMachine if at != null else null
	if lib == null or skel == null or sm == null:
		push_error("%s is missing its library, skeleton or state machine for the tredge" % OUT)
		return false
	if not ap.has_animation(&"idle"):
		push_error("no 'idle' clip for the tredge's braced idle")
		return false

	var src := load(TREDGE_SOURCE) as Animation
	if src == null:
		push_error("no walk clip at %s - has the Real Controller addon moved?" % TREDGE_SOURCE)
		return false
	var anim := src.duplicate(true) as Animation
	anim.resource_path = ""
	anim.resource_name = TREDGE_CLIP
	var touched := TREDGE_BAKE.bake(anim, skel)
	if touched == 0:
		push_error("the tredge bake found no leg tracks on %s - the bone names changed?" % TREDGE_SOURCE)
		return false
	if lib.has_animation(TREDGE_CLIP):
		lib.remove_animation(TREDGE_CLIP)
	lib.add_animation(TREDGE_CLIP, anim)

	var idle := AnimationNodeAnimation.new()
	idle.animation = &"idle"
	var clip := AnimationNodeAnimation.new()
	clip.animation = TREDGE_CLIP
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("Idle", idle, Vector2(-160, -60))
	bt.add_node("Clip", clip, Vector2(-160, 120))
	bt.add_node(TREDGE_SCALE_NODE, AnimationNodeTimeScale.new(), Vector2(60, 120))
	bt.add_node(TREDGE_BLEND_NODE, AnimationNodeBlend2.new(), Vector2(260, 40))
	bt.set_node_position("output", Vector2(480, 40))
	bt.connect_node(TREDGE_SCALE_NODE, 0, "Clip")
	bt.connect_node(TREDGE_BLEND_NODE, 0, "Idle")
	bt.connect_node(TREDGE_BLEND_NODE, 1, TREDGE_SCALE_NODE)
	bt.connect_node("output", 0, TREDGE_BLEND_NODE)

	if sm.has_node(TREDGE_STATE):
		sm.remove_node(TREDGE_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(TREDGE_STATE, bt, Vector2(330, 620))

	# The 0.5 s blend each way is the spec's. Leaving the floor outranks the exit: walking off an
	# edge while still exposed falls, and the landing comes back through jump_land.
	_set_transition(sm, "Locomotion", TREDGE_STATE, 0.5, "is_tredging", 0)
	_set_transition(sm, TREDGE_STATE, "fall", 0.3, "not is_on_floor() and velocity.y <= 0", 0)
	_set_transition(sm, TREDGE_STATE, "Locomotion", 0.5, "not is_tredging", 1)
	_set_transition(sm, "jump_land", TREDGE_STATE, 0.3, "is_tredging", 0)

	print("  clip \"%s\" baked from walk_forward on %d tracks; state \"%s\" (idle / clip Blend2), %d states, %d transitions"
		% [TREDGE_CLIP, touched, TREDGE_STATE, sm.get_node_list().size(), sm.get_transition_count()])
	return true


func _ensure_deterministic_blending(root: Node) -> bool:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		push_error("%s has no AnimationTree to configure" % OUT)
		return false
	at.deterministic = true
	print("  AnimationTree.deterministic = true (bones no clip animates return to rest)")
	return true


# -- camera ---------------------------------------------------------------------------

# RC ships its rig camera with `current` unset, and nothing here was setting it either.
# Today that is invisible: Godot promotes the first Camera3D to enter a viewport when no
# other is active, so the trial has always rendered. It stops being invisible the moment a
# scene instancing pilot9 carries a camera of its own - then which one wins is decided by
# tree order, and the loser is a black screen or a view from the wrong place.
#
# So the flag is set here rather than left to the engine's fallback: it makes the rig's
# camera the intended one on the record, and it survives a --fresh, which an editor tick
# would not. tests/test_pilot9_retarget.gd asserts it.
func _ensure_camera_current(root: Node) -> bool:
	var cam := root.get_node_or_null(CAMERA_PATH) as Camera3D
	if cam == null:
		push_error("%s has no camera at %s" % [OUT, CAMERA_PATH])
		return false
	cam.current = true
	print("  ", CAMERA_PATH, ".current = true")
	return true


# Physics interpolation is on project-wide, and the camera rig is the one branch that must opt
# out of it: interpolated, mouse look is quantised to the physics tick and lands a frame late.
# pilot9.gd::_process() instead places the pivot from his *interpolated* transform each drawn
# frame, which it can only do if the pivot is detached from him - hence top_level.
#
# Asserted here for the same reason `current` is: RC's character.tscn ships neither flag, so a
# --fresh build would silently hand the rig back with the camera welded to his stepped 60 Hz
# position and judder on every turn - the exact bug this was added to fix.
func _ensure_camera_interpolation(root: Node) -> bool:
	var pivot := root.get_node_or_null(CAMERA_PIVOT_PATH) as Node3D
	if pivot == null:
		push_error("%s has no camera pivot at %s" % [OUT, CAMERA_PIVOT_PATH])
		return false
	pivot.top_level = true
	pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	print("  ", CAMERA_PIVOT_PATH, ".top_level = true, physics_interpolation_mode = OFF")
	return true


# -- height ---------------------------------------------------------------------------

# Report, never rewrite: a swap must not clobber a capsule the user tuned by hand.
func _report_height(root: Node) -> void:
	var arm := root.get_node_or_null("character/Armature")
	if arm == null:
		return
	var boxes: Array[AABB] = []
	_collect_aabb(arm, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return
	var merged: AABB = boxes[0]
	for i in range(1, boxes.size()):
		merged = merged.merge(boxes[i])
	var mesh_h := merged.size.y

	var cap_h := 0.0
	var col := root.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col and col.shape is CapsuleShape3D:
		cap_h = (col.shape as CapsuleShape3D).height

	print("mesh height %.4f m | capsule %.4f m | PILOT_HEIGHT %.4f m" % [mesh_h, cap_h, PILOT_HEIGHT])
	if absf(mesh_h - cap_h) > HEIGHT_TOLERANCE:
		print("  NOTE: his silhouette moved. Set PILOT_HEIGHT to %.4f and re-run with --fresh," % mesh_h)
		print("        or resize CollisionShape3D in the editor - the swap will not touch it.")


# The retarget bakes the Armature to identity, so a plain local-transform walk is metres.
func _collect_aabb(n: Node, xf: Transform3D, out: Array[AABB]) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(t * (n as MeshInstance3D).get_aabb())
	for c in n.get_children():
		_collect_aabb(c, t, out)


# -- save -----------------------------------------------------------------------------

func _save(root: Node) -> bool:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("pack failed")
		return false
	if ResourceSaver.save(packed, OUT) != OK:
		push_error("save failed")
		return false

	# ResourceSaver drops unique_name_in_owner on the baked skeleton; re-add it as text.
	# Without it RC's clips address %GeneralSkeleton and resolve to nothing - the state
	# machine transitions happily while pilot9 stands in T-pose.
	var f := FileAccess.open(OUT, FileAccess.READ)
	var src := f.get_as_text()
	f.close()
	var anchor := "[node name=\"GeneralSkeleton\" type=\"Skeleton3D\" parent=\"character/Armature\""
	var at := src.find(anchor)
	if at == -1:
		push_error("could not find the GeneralSkeleton node line in the saved scene")
		return false
	var line_end := src.find("\n", at)
	if not src.substr(line_end, 64).contains("unique_name_in_owner"):
		src = src.substr(0, line_end + 1) + "unique_name_in_owner = true\n" + src.substr(line_end + 1)
		var w := FileAccess.open(OUT, FileAccess.WRITE)
		w.store_string(src)
		w.close()
	return true


func _has_flag(f: String) -> bool:
	return OS.get_cmdline_args().has(f) or OS.get_cmdline_user_args().has(f)
