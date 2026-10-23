extends "res://tests/test_case.gd"

# docs/specs/pilot9-held-item.md. Wiring, sockets, the no-item case and the per-move list. Where
# the staff sits and how the arm looks are judged in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const STAFF := "res://resources/items/staff.tres"
const HOLDER := preload("res://scripts/items/item_holder.gd")
const MODIFIER := preload("res://scripts/items/arm_pose_modifier.gd")
const APPLY_STYLIZED := preload("res://scripts/rendering/apply_stylized.gd")

# One shared in-tree instance, for the reason tests/test_pilot9_dash.gd gives.
var _pilot: Node = null

# The pilot with the staff back on and holstered, whatever the last test left.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.set_item(load(STAFF))
	if _pilot.is_item_drawn():
		_pilot.toggle_drawn()
	return _pilot

func _has_event(action: StringName, pred: Callable) -> bool:
	for ev in InputMap.action_get_events(action):
		if pred.call(ev):
			return true
	return false

func test_equip_is_bound_to_r_and_dpad_right() -> void:
	check(InputMap.has_action(&"equip"), "project.godot has no `equip` action")
	if not InputMap.has_action(&"equip"):
		return
	check(_has_event(&"equip", func(ev): return ev is InputEventKey and ev.physical_keycode == KEY_R),
		"`equip` should be on R")
	check(_has_event(&"equip", func(ev): return ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_DPAD_RIGHT),
		"`equip` should be on d-pad right")

func test_starting_item_is_the_staff() -> void:
	var ps := load(PILOT_TSCN) as PackedScene
	var fresh := ps.instantiate()
	eq(fresh.starting_item, load(STAFF), "pilot9 should start with the staff")
	fresh.free()

func test_spawns_holstered_and_hidden() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.item_holder
	check(h.item_instance != null, "the staff should be instanced at spawn")
	check(not pilot.is_item_drawn(), "he should spawn holstered")
	if h.item_instance:
		eq(h.item_instance.get_parent(), h.hand_socket, "a holstered staff waits in the hand socket")
		check(not h.item_instance.visible, "a holstered staff is hidden - no back sling")

func test_sockets_are_on_the_spec_bones() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.item_holder
	eq(h.hand_socket.bone_name, "RightHand", "hand socket bone")
	check(h.hand_socket.bone_idx >= 0, "RightHand should resolve on pilot9's skeleton")

func test_toggle_shows_and_hides_it() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.item_holder
	var staff: HeldItem = load(STAFF)
	pilot.toggle_drawn()
	check(pilot.is_item_drawn(), "one toggle should draw it")
	eq(h.item_instance.get_parent(), h.hand_socket, "a drawn staff sits in the hand socket")
	eq(h.item_instance.transform, staff.hand_offset, "drawn, it takes the item's hand_offset")
	check(h.item_instance.visible, "drawn, it shows")
	pilot.toggle_drawn()
	check(not pilot.is_item_drawn(), "a second toggle should holster it")
	eq(h.item_instance.get_parent(), h.hand_socket, "holstered, it stays in the hand socket")
	check(not h.item_instance.visible, "holstered, it is hidden")

func test_no_item_is_a_valid_state() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.item_holder
	pilot.set_item(null)
	eq(h.item_instance, null, "no item, no instance")
	pilot.toggle_drawn()
	check(not pilot.is_item_drawn(), "toggling with no item does nothing")
	eq(h.arm_target(), 0.0, "no item, no arm override")
	pilot.set_item(load(STAFF))
	check(h.item_instance != null, "an item set after none should appear")
	check(not pilot.is_item_drawn() and not h.item_instance.visible, "...holstered, hidden")

func test_swap_keeps_it_drawn_and_frees_the_old_one() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.item_holder
	pilot.toggle_drawn()
	var old: Node = h.item_instance
	var other := (load(STAFF) as HeldItem).duplicate() as HeldItem
	pilot.set_item(other)
	check(old.is_queued_for_deletion(), "the old staff's instance should be freed")
	eq(h.held_item, other, "the new item is the held one")
	check(pilot.is_item_drawn(), "a swap while drawn stays drawn")
	eq(h.item_instance.get_parent(), h.hand_socket, "the new staff lands in the hand")

func test_per_move_list() -> void:
	for s in [&"Locomotion", &"jump_land", &"crouch", &"slide"]:
		check(HOLDER.arm_override_for(s), "arm override should be ON in `%s`" % s)
	for s in [&"jump", &"fall", &"climb", &"wall_run", &"rail"]:
		check(not HOLDER.arm_override_for(s), "arm override should be OFF in `%s`" % s)
	check(not HOLDER.arm_override_for(&"some_future_move"), "an unlisted state defaults to OFF")

func test_every_listed_state_exists_in_the_tree() -> void:
	# A renamed state would silently fall to the unlisted default - off.
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var sm := (pilot.anim_tree as AnimationTree).tree_root as AnimationNodeStateMachine
	for s in HOLDER.ARM_OVERRIDE_STATES:
		check(sm.has_node(s), "per-move list names `%s`, which is not a state in pilot9's tree" % s)

func test_staff_carries_its_own_hold() -> void:
	# No clip: the hold is in the resource. Every arm bone it names must resolve on the rig, or
	# that bone silently drops out of the hold.
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var staff: HeldItem = load(STAFF)
	var skel := pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	eq(staff.hold_rotations.size(), HOLDER.ARM_BONES.size(), "the staff should hold every arm bone")
	eq(HOLDER.pose_from_rotations(staff.hold_rotations, skel).size(), HOLDER.ARM_BONES.size(),
		"every bone in the staff's hold should resolve on pilot9's skeleton")
	pilot.toggle_drawn()
	pilot.item_holder._refresh_pose()
	check(not pilot.item_holder.arm_modifier.pose.is_empty(), "drawn, the modifier should have the hold")

func test_pose_from_rotations_takes_arm_bones_only() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var skel := pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var pose := HOLDER.pose_from_rotations(
		{&"RightLowerArm": Vector3(0, 90, 0), &"LeftUpperLeg": Vector3(0, 90, 0), &"NoSuchBone": Vector3.ZERO}, skel)
	eq(pose.size(), 1, "only the right-arm bone should be taken")
	var q: Quaternion = pose.get(skel.find_bone("RightLowerArm"), Quaternion.IDENTITY)
	approx(q.angle_to(Quaternion(Vector3.UP, PI / 2.0)), 0.0, 0.001, "degrees should become the rotation")

func test_run_factor() -> void:
	# Idle and walk keep the natural arm; run and sprint hold the staff back.
	approx(HOLDER.run_factor(0.0, 2.5, 5.0), 0.0, 0.001, "idle")
	approx(HOLDER.run_factor(2.5, 2.5, 5.0), 0.0, 0.001, "walking pace")
	approx(HOLDER.run_factor(3.75, 2.5, 5.0), 0.5, 0.001, "halfway from walk to run")
	approx(HOLDER.run_factor(5.0, 2.5, 5.0), 1.0, 0.001, "running pace")
	approx(HOLDER.run_factor(7.5, 2.5, 5.0), 1.0, 0.001, "sprinting")

func test_arm_target_follows_his_speed() -> void:
	eq(HOLDER.arm_target_for(&"Locomotion", 0.0, 2.5, 5.0), 0.0, "idle: natural arm")
	eq(HOLDER.arm_target_for(&"Locomotion", 2.5, 2.5, 5.0), 0.0, "walking: natural arm")
	eq(HOLDER.arm_target_for(&"Locomotion", 5.0, 2.5, 5.0), 1.0, "running: staff held back")
	eq(HOLDER.arm_target_for(&"Locomotion", 7.5, 2.5, 5.0), 1.0, "sprinting: staff held back")
	eq(HOLDER.arm_target_for(&"jump", 0.0, 2.5, 5.0), 0.0, "a standing jump keeps the natural arm")
	eq(HOLDER.arm_target_for(&"jump", 7.5, 2.5, 5.0), 0.0, "a running jump opens both arms too")
	eq(HOLDER.arm_target_for(&"fall", 7.5, 2.5, 5.0), 0.0, "so does falling at speed")
	eq(HOLDER.arm_target_for(&"wall_run", 7.5, 2.5, 5.0), 0.0, "off-list moves stay off at any speed")

func test_holder_reads_pilot9s_speeds() -> void:
	# The gate reads walk_speed / speed / velocity off pilot9 by name - pin them.
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	eq(pilot.item_holder._body, pilot, "the holder should be given pilot9 as its body")
	for prop in ["walk_speed", "speed", "velocity"]:
		check(prop in pilot, "pilot9 should have `%s`" % prop)

func test_modifier_eases() -> void:
	var m := MODIFIER.new()
	m.target = 1.0
	m.step(0.075)
	approx(m.influence, 0.5, 0.001, "half the 0.15 s blend should be halfway in")
	m.step(1.0)
	approx(m.influence, 1.0, 0.001, "and it should stop at 1")
	m.free()

func test_rim_light_skips_the_staff() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.rim_light_enabled = true
	var meshes: Array[MeshInstance3D] = []
	APPLY_STYLIZED.collect_meshes(pilot.item_holder.item_instance, meshes)
	check(meshes.size() > 0, "the staff should have a mesh")
	for mi in meshes:
		eq(mi.material_overlay, null, "the rim light is pilot-only; the staff must not carry it")
