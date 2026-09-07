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
# entries in the library, the whole `crouch` state with its transitions,
# AnimationTree.deterministic, and the rig camera's `current` flag. Editing any of them in
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
	# Imported and available, deliberately NOT wired into the state machine: this is the
	# climb-into-the-cockpit clip for the mech handover, which does not exist yet.
	"P_sitting": {"as": &"sit_down", "loop": Animation.LOOP_NONE},
	# A one-shot verb with its own run-in and run-out, not a cycle. Exported WITHOUT Mixamo's
	# In Place, and left that way on purpose - _ensure_slide_motion() below takes its 7.8 m
	# of root motion apart into a curve the controller drives the body with, and only then
	# locks the clip in place. See docs/specs/pilot9-slide.md.
	"P_slide": {"as": &"slide", "loop": Animation.LOOP_NONE},
	# The mantle. Exported WITHOUT In Place, like the slide, and taken apart the same way -
	# _ensure_climb_motion() below bakes its Hips travel into a pair of curves and then
	# locks the clip's Y *and* Z. See docs/specs/pilot9-climb.md.
	"P_climbing": {"as": &"climb_up", "loop": Animation.LOOP_NONE},
}

const CROUCH_STATE := &"crouch"
const CROUCH_CLIP := &"crouch_walk"
## AnimationTree parameter scripts/pilot9_animation.gd writes each frame. Kept next to
## the builder that creates the node, because renaming either half silently stops the
## crouch cycle advancing - set() on a path that does not exist is not an error.
const CROUCH_SCALE_NODE := "CrouchScale"

const SLIDE_STATE := &"slide"
const SLIDE_CLIP := &"slide"
const CLIMB_CLIP := &"climb_up"

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

## Exported properties on scripts/pilot9.gd that this script, not the inspector, owns.
## Object.set() on a name a script does not declare is silently dropped, so every write is
## read back - a rename on the pilot9.gd side would otherwise leave the slide with a null
## curve and no complaint from anyone.
const SLIDE_BAKED := ["slide_motion", "slide_duration", "slide_distance"]

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
const CLIMB_SPEED := 1.5

## The bones the entry and exit snaps are measured between. Profile-bone names, because the
## retargeter has rewritten every GLB clip onto Godot's humanoid profile.
const CLIMB_HAND_BONES := ["LeftHand", "RightHand"]
## Toes rather than feet: the foot bone is the ankle, and what has to land on the platform
## is the sole. The rest pose says how far the toes sit above his origin when he is standing
## on the floor, and that difference is the correction - see _ensure_climb_motion().
const CLIMB_FOOT_BONES := ["LeftToes", "RightToes"]

## Same discipline as SLIDE_BAKED, and more of it to get wrong.
const CLIMB_BAKED := ["climb_motion_y", "climb_motion_z", "climb_duration", "climb_speed",
	"climb_rise", "climb_reach", "climb_inset", "climb_hand_offset", "climb_foot_offset"]

## RC's camera rig, unchanged by either mode. Only the `current` flag is asserted on it -
## see _ensure_camera_current().
const CAMERA_PATH := "CameraPivot/SpringArm3D/Camera3D"


func _init() -> void:
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
	if not _ensure_deterministic_blending(root):
		quit(1)
		return
	if not _ensure_camera_current(root):
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

	root.set("slide_motion", curve)
	root.set("slide_duration", length)
	root.set("slide_distance", total)
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

	print("  clip \"%s\" locked in place; %.3f m over %.3fs baked to slide_motion (%d points)"
		% [SLIDE_CLIP, total, length, curve.point_count])
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


# The `slide` state: one clip, no TimeScale, exited by the controller clearing is_sliding.
#
# A plain AnimationNodeAnimation rather than the crouch's blend tree, and deliberately so -
# the state machine plays the clip on its own clock while pilot9.gd::_slide_time runs in
# _physics_process, and the only reason those two agree is that both are real time. A
# TimeScale anywhere in here would desync the animation from the distance curve driving the
# body, silently.
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

	if sm.has_node(SLIDE_STATE):
		sm.remove_node(SLIDE_STATE)   # takes its transitions with it - see _ensure_crouch_state
	sm.add_node(SLIDE_STATE, clip, Vector2(630, 800))

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
	_set_transition(sm, SLIDE_STATE, "Locomotion", 0.2, "not is_sliding", 2)

	print("  state \"%s\" -> %s, %d states, %d transitions"
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
#    travel is kept only for its SHAPE (the normalised curves) and for climb_inset, which is
#    how far in from the edge he lands. That is the same discipline the slide uses - drive
#    the body from the animator's own numbers - applied to the frames that actually matter.
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

	var curve_y := _normalised_curve(anim, track, length, Vector3.UP, p0)
	var curve_z := _normalised_curve(anim, track, length, Vector3.BACK, p0)

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
	var hand := _contact_point(skel, anim, 0.0, CLIMB_HAND_BONES)
	var toes_end := _contact_point(skel, anim, length, CLIMB_FOOT_BONES)
	var toes_rest := _contact_point(skel, null, 0.0, CLIMB_FOOT_BONES)
	# The toe bone sits a little above the sole even when he is standing on the floor, and
	# the rest pose is where that offset is read from. Subtracting it turns "where the toes
	# are" into "where the ground under them is", which is what the exit snap wants.
	var foot := Vector3(toes_end.x, toes_end.y - toes_rest.y, toes_end.z)

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


# One axis of the Hips track as a normalised curve: time fraction in, distance fraction out.
# Linear tangents on every point, like the slide's - a curve that overshoots between samples
# is a body that lurches between them.
#
# Deliberately NOT clamped to 0..1. The Y curve rises past 1.0 near the top (the pull over
# the lip before he settles back onto it) and the Z curve dips below 0 at the start (the
# swing back before the pull); both are the arc the spec asks for, and Curve's default 0..1
# value range would quietly flatten them.
func _normalised_curve(anim: Animation, track: int, length: float, axis: Vector3,
		origin: Vector3) -> Curve:
	var total := (anim.position_track_interpolate(track, length) - origin).dot(axis)
	var curve := Curve.new()
	curve.min_value = -1.0
	curve.max_value = 2.0
	for i in CLIMB_CURVE_SAMPLES + 1:
		var u := float(i) / float(CLIMB_CURVE_SAMPLES)
		var travelled := (anim.position_track_interpolate(track, u * length) - origin).dot(axis)
		var idx := curve.add_point(Vector2(u, travelled / total))
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
