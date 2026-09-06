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
}

const CROUCH_STATE := &"crouch"
const CROUCH_CLIP := &"crouch_walk"
## AnimationTree parameter scripts/pilot9_animation.gd writes each frame. Kept next to
## the builder that creates the node, because renaming either half silently stops the
## crouch cycle advancing - set() on a path that does not exist is not an error.
const CROUCH_SCALE_NODE := "CrouchScale"

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
