extends "res://tests/test_case.gd"

# Covers pilot9's vault: the qualify predicate, the bake off the Mixamo FBX, the retarget that
# makes the FBX route work without Blender, the `vault` state and its wiring, and the path the
# controller bends onto each wall. See docs/specs/pilot9-vault.md.
#
# Real vaults - running at a wall, pressing jump, going over - need frames, and this runner is
# synchronous. They live in tests/_probe_vault.gd instead (every lane height at walk / run /
# sprint, the four controls, both buffers and the crouch exit), which exits non-zero on a fail:
#   godot --headless --fixed-fps 60 --path . --script tests/_probe_vault.gd

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")
const ANIMATION := preload("res://scripts/pilot9_animation.gd")
const HOLDER := preload("res://scripts/items/item_holder.gd")

var _pilot: Node = null

# One shared in-tree instance, for the reason tests/test_pilot9_climb.gd gives.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.is_vaulting = false
	_pilot.can_vault = true
	_pilot.frozen = false
	return _pilot

# A thin, square, waist-high wall at a comfortable distance with flat floor past it - every
# measurement passes, so each test below can move exactly one of them.
func _ok(p: Node, overrides := {}) -> bool:
	var m := {"reach": 1.5, "height": 1.1, "angle": 0.0, "depth": 0.4, "top_slope": 0.0,
		"landing_rise": 0.0}
	m.merge(overrides, true)
	return p._qualifies_as_vault(m["reach"], m["height"], m["angle"], m["depth"],
		m["top_slope"], m["landing_rise"])

# --- what qualifies ------------------------------------------------------------

func test_the_baseline_wall_qualifies() -> void:
	var p := _scene()
	check(_ok(p), "a 1.1 m, 0.4 m-deep, square wall 1.5 m ahead should vault")

func test_the_height_band_edges() -> void:
	var p := _scene()
	check(not _ok(p, {"height": 0.49}), "0.49 m is under the band - a step, not a vault")
	check(_ok(p, {"height": 0.5}), "0.5 m is the band's floor and should vault")
	check(_ok(p, {"height": 1.3}), "1.3 m is the band's ceiling and should vault")
	check(not _ok(p, {"height": 1.31}), "1.31 m is over the band - the jump's")

func test_the_approach_angle_edge() -> void:
	var p := _scene()
	check(_ok(p, {"angle": 44.0}), "44 degrees off square should vault")
	check(not _ok(p, {"angle": 46.0}), "46 degrees off square should not")

func test_the_depth_edge() -> void:
	var p := _scene()
	check(_ok(p, {"depth": 1.5}), "a 1.5 m-deep top is at the limit and should qualify")
	check(not _ok(p, {"depth": 1.75}), "a 1.75 m-deep top is a platform, not a wall")
	check(not _ok(p, {"depth": INF}), "a top every depth ray still hit is too deep")

func test_the_landing_edges() -> void:
	var p := _scene()
	check(_ok(p, {"landing_rise": -3.0}), "a 3.0 m drop past the wall is within vault_max_drop")
	check(not _ok(p, {"landing_rise": -3.1}), "a 3.1 m drop is a pit, not a landing")
	check(_ok(p, {"landing_rise": 0.3}), "a landing 0.3 m above his start is allowed")
	check(not _ok(p, {"landing_rise": 0.4}), "a landing 0.4 m above his start is not")
	check(not _ok(p, {"landing_rise": -INF}), "no floor at all past the wall is not a landing")

func test_the_reach_and_slope_edges() -> void:
	var p := _scene()
	check(not _ok(p, {"reach": 0.45}), "a face 0.45 m ahead is inside vault_reach_min")
	check(_ok(p, {"reach": 3.0}), "a face 3.0 m ahead is at vault_reach_max")
	check(not _ok(p, {"reach": 3.5}), "a face 3.5 m ahead is a jump")
	check(not _ok(p, {"top_slope": 31.0}), "a top 31 degrees off level is not one to plant on")

func test_can_vault_off_refuses_the_press() -> void:
	var p := _scene()
	p.can_vault = false
	check(not p._try_start_vault(), "can_vault off should leave every press to the jump")
	p.can_vault = true

# --- the clip -----------------------------------------------------------------

func test_the_vault_clip_came_across_from_the_fbx() -> void:
	var p := _scene()
	var ap := p.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(BUILDER.VAULT_CLIP):
		fail("no 'vault' clip in pilot9's library - _ensure_fbx_clips() did not lift it")
		return
	var a := ap.get_animation(BUILDER.VAULT_CLIP)
	approx(a.length, 1.2, 0.1, "the Mixamo vault runs 1.2 s")
	eq(a.loop_mode, Animation.LOOP_NONE, "the vault is a one-shot")

func test_the_retarget_ran() -> void:
	# The one untested link in "no Blender": a BoneMap filed under the wrong key is ignored, and
	# the clip arrives naming mixamorig_* bones that bind to nothing.
	var p := _scene()
	var ap := p.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skel := p.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	if ap == null or skel == null or not ap.has_animation(BUILDER.VAULT_CLIP):
		fail("the vault clip or the skeleton is missing")
		return
	var a := ap.get_animation(BUILDER.VAULT_CLIP)
	for t in a.get_track_count():
		var path := str(a.track_get_path(t))
		check(path.begins_with("%GeneralSkeleton:"),
			"vault track '%s' does not address %%GeneralSkeleton" % path)
		check(not path.contains("mixamorig"), "vault track '%s' was never retargeted" % path)
		check(skel.find_bone(path.get_slice(":", 1)) != -1,
			"vault track '%s' names a bone pilot9 does not have" % path)

func test_the_fbx_import_carries_the_bone_map() -> void:
	var f := FileAccess.open("res://assets/pilot9_vault.fbx.import", FileAccess.READ)
	if f == null:
		fail("assets/pilot9_vault.fbx.import is missing")
		return
	var text := f.get_as_text()
	check(text.contains("\"PATH:Skeleton3D\""),
		"the BoneMap has to sit under the FBX's own skeleton path, PATH:Skeleton3D")
	check(text.contains("\"bone_map/Hips\":&\"mixamorig_Hips\""), "the BoneMap is not pilot9.glb's")

func test_the_clip_is_locked_in_place() -> void:
	var p := _scene()
	var ap := p.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var a := ap.get_animation(BUILDER.VAULT_CLIP) if ap else null
	if a == null:
		fail("no vault clip")
		return
	var t := a.find_track(NodePath(BUILDER.SLIDE_MOTION_TRACK), Animation.TYPE_POSITION_3D)
	if t == -1:
		fail("the vault clip has no Hips position track")
		return
	var first: Vector3 = a.track_get_key_value(t, 0)
	var worst := 0.0
	for k in a.track_get_key_count(t):
		var v: Vector3 = a.track_get_key_value(t, k)
		worst = maxf(worst, maxf(absf(v.x - first.x), absf(v.z - first.z)))
	approx(worst, 0.0, 0.0001, "the vault's Hips X/Z should be locked - the body carries the travel")

# --- the bake -----------------------------------------------------------------

func test_the_bake_landed() -> void:
	var p := _scene()
	for prop in BUILDER.VAULT_BAKED:
		check(prop in p, "pilot9.gd declares no '%s'" % prop)
	check(p.vault_motion_y != null and p.vault_motion_z != null, "the vault curves did not bake")
	check(p.vault_duration > 0.0 and p.vault_clip_speed > 0.0, "no duration / clip speed baked")
	approx(p.vault_clip_speed, 4.4, 0.4, "the clip travels ~4.4 m/s as authored")
	approx(p.vault_top_height, 1.1, 0.1, "the authored top reads ~1.1 m on pilot9")

func test_the_moments_are_in_order() -> void:
	var p := _scene()
	check(p.vault_takeoff_time < p.vault_plant_time, "takeoff should come before the plant")
	check(p.vault_plant_time < p.vault_release_time, "the plant should come before the release")
	check(p.vault_release_time < p.vault_touchdown_time, "the release should come before touchdown")
	check(p.vault_release_time >= 0.55 and p.vault_release_time <= 0.70,
		"the hands should release at ~55-70%% of the clip, got %.2f" % p.vault_release_time)

# --- the path -----------------------------------------------------------------

func test_the_path_starts_where_he_stands() -> void:
	var p := _scene()
	var at := p._vault_path(0.0, 0.3, -1.0) as Vector2
	approx(at.length(), 0.0, 0.01, "u = 0 is where he pressed, whatever the wall")

func test_the_hands_meet_the_wall_whatever_it_is() -> void:
	# From the plant to the release the whole authored path is shifted by exactly (dh, dz) -
	# which is what puts the hands on THIS top instead of the authored one.
	var p := _scene()
	for dh in [-0.58, 0.0, 0.22]:
		for dz in [-1.8, 0.0, 0.5]:
			for u in [p.vault_plant_time + 0.001, p.vault_release_time]:
				var bent := p._vault_path(u, dh, dz) as Vector2
				var authored := p._vault_path(u, 0.0, 0.0) as Vector2
				approx(bent.x - authored.x, dh, 0.001, "hands off the top at u=%.3f dh=%.2f" % [u, dh])
				approx(bent.y - authored.y, dz, 0.001, "hands off the edge at u=%.3f dz=%.2f" % [u, dz])

func test_the_feet_come_down_at_his_start_height() -> void:
	var p := _scene()
	for dh in [-0.58, 0.22]:
		var down := p._vault_path(p.vault_touchdown_time, dh, 0.0) as Vector2
		approx(down.x, 0.0, 0.01, "touchdown should be on his start floor whatever the wall (dh %.2f)" % dh)

# --- the state ----------------------------------------------------------------

func _sm(p: Node) -> AnimationNodeStateMachine:
	return (p.get_node("AnimationTree") as AnimationTree).tree_root as AnimationNodeStateMachine

func _has_transition(sm: AnimationNodeStateMachine, from: String, to: String) -> bool:
	for i in sm.get_transition_count():
		if str(sm.get_transition_from(i)) == from and str(sm.get_transition_to(i)) == to:
			return true
	return false

func test_the_vault_state_exists_and_is_wired() -> void:
	var p := _scene()
	var sm := _sm(p)
	check(sm.has_node(BUILDER.VAULT_STATE), "no `vault` state in the tree")
	for from in ["Locomotion", "slide"]:
		check(_has_transition(sm, from, "vault"), "no `%s -> vault` - that press would not show" % from)
	for to in ["Locomotion", "fall", "jump", "slide"]:
		check(_has_transition(sm, "vault", to), "no `vault -> %s`" % to)

func test_the_seek_and_scale_meet_the_builder() -> void:
	# Two halves in two files, and set() on a path that does not exist is silent.
	var p := _scene()
	eq(p.VAULT_SEEK_PARAM, "parameters/vault/%s/seek_request" % BUILDER.VAULT_SEEK_NODE,
		"pilot9.gd's seek path drifted from the builder's node name")
	eq(ANIMATION.VAULT_SCALE, "parameters/vault/%s/scale" % BUILDER.VAULT_SCALE_NODE,
		"pilot9_animation.gd's scale path drifted from the builder's node name")
	var at := p.get_node("AnimationTree") as AnimationTree
	check(at.get(p.VAULT_SEEK_PARAM) != null, "the tree has no %s parameter" % p.VAULT_SEEK_PARAM)
	check(at.get(ANIMATION.VAULT_SCALE) != null, "the tree has no %s parameter" % ANIMATION.VAULT_SCALE)

# --- what it refuses and lets go of -------------------------------------------

func test_the_staff_lets_go_in_a_vault() -> void:
	check(not HOLDER.arm_override_for(&"vault"), "the drawn arm should let go in `vault`")
	eq(HOLDER.arm_target_for(&"vault", 7.5, 2.5, 5.0), 0.0, "arm target in `vault` should be 0")

func test_no_dash_mid_vault() -> void:
	var p := _scene()
	p.is_vaulting = true
	check(not p._can_dash(), "a dash out of a vault should be refused, as out of a mantle")
	p.is_vaulting = false
