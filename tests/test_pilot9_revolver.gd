extends "res://tests/test_case.gd"

# docs/specs/pilot9-revolver.md. The revolver item and model, the weapon slots (1 / 2 / R and the
# swap), the per-item hold rules, the uniform grow, and the staff-only reflect and tredge torch.
# How it looks in his hand is judged in play (tests/_probe_revolver_shot.gd for screenshots).

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const STAFF := "res://resources/items/staff.tres"
const REVOLVER := "res://resources/items/revolver.tres"
const HOLDER := preload("res://scripts/items/item_holder.gd")
const ANIM := preload("res://scripts/items/equip_anim.gd")
const TREDGE := preload("res://scripts/pilot9_tredge.gd")
const DT := 1.0 / 60.0

var _pilot: Node = null

# One shared in-tree pilot9: staff the current item, holstered, nothing playing, every flag clear.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.is_climbing = false
	_pilot.is_vaulting = false
	_pilot.is_wall_running = false
	_pilot.is_wall_climbing = false
	_pilot.frozen = false
	_pilot.tredge.mode = TREDGE.Mode.FORCED_OFF
	_pilot.end_tredge()
	_pilot.reflect_spin.cancel()
	# These tests are about the staff-and-revolver layout; the default loadout is rifle-and-revolver.
	var slots: Array[HeldItem] = [load(STAFF), load(REVOLVER)]
	_pilot.weapon_slots = slots
	_pilot.set_item(load(STAFF))
	if _pilot.is_item_drawn():
		_pilot.toggle_drawn()
	return _pilot

# Runs the equip animation to the end, swap chains included.
func _settle(pilot: Node) -> void:
	for i in 200:
		if not pilot.equip_anim.is_playing():
			return
		pilot.equip_anim._process(DT)

func _has_event(action: StringName, pred: Callable) -> bool:
	for ev in InputMap.action_get_events(action):
		if pred.call(ev):
			return true
	return false

# --- the item ---------------------------------------------------------------------------------

func test_revolver_item_is_set_up() -> void:
	var item: HeldItem = load(REVOLVER)
	check(item != null and item.scene != null, "revolver.tres points at a scene")
	if item == null:
		return
	eq(item.grow, HeldItem.Grow.UNIFORM, "it grows as a whole, not stretched")
	check(not item.can_reflect, "the revolver cannot reflect")
	check(item.hold_at_any_speed, "low ready at every pace")
	check(item.hold_off_states.has(&"slide"), "no low ready in a slide")
	eq(item.hold_rotations.size(), 4, "the trailing pose sets the four right-arm bones")
	eq(item.idle_rotations.size(), 4, "the wide idle pose sets the four right-arm bones")
	check((load(STAFF) as HeldItem).idle_rotations.is_empty(), "the staff has no idle pose")
	check((load(STAFF) as HeldItem).can_reflect, "the staff can reflect")
	eq((load(STAFF) as HeldItem).grow, HeldItem.Grow.LENGTH, "the staff still stretches out of the grip")

func test_model_is_06_m_long_grip_on_origin_barrel_down_minus_z() -> void:
	var item: HeldItem = load(REVOLVER)
	var gun := item.scene.instantiate() as Node3D
	(Engine.get_main_loop() as SceneTree).root.add_child(gun)
	var box := AABB()
	var first := true
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := gun.global_transform.affine_inverse() * mi.global_transform
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			box = AABB(xf * v, Vector3.ZERO) if first else box.expand(xf * v)
			first = false
	approx(box.size.z, 0.6, 0.001, "muzzle to grip back is 0.6 m, down its Z")
	check(box.size.x < 0.15, "it is gun-thin across (%.3f m)" % box.size.x)
	var muzzle: Marker3D = gun.get_node("Muzzle")
	check(muzzle.position.z < -0.4, "the muzzle is well down -Z (%s)" % muzzle.position)
	approx(muzzle.position.z, box.position.z, 0.002, "the muzzle sits at the barrel's end")
	check(box.has_point(Vector3.ZERO), "the grip (origin) is inside the gun")
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var mat := (node as MeshInstance3D).material_override as ShaderMaterial
		check(mat != null and mat.next_pass != null, "%s wears the cel material with ink" % node.name)
	gun.free()

# --- the bindings -----------------------------------------------------------------------------

func test_weapon_actions_are_bound() -> void:
	for a in [&"weapon_1", &"weapon_2"]:
		check(InputMap.has_action(a), "project.godot has `%s`" % a)
	check(_has_event(&"weapon_1", func(ev): return ev is InputEventKey and ev.physical_keycode == KEY_1),
		"weapon_1 on 1")
	check(_has_event(&"weapon_1", func(ev): return ev is InputEventJoypadButton \
		and ev.button_index == JOY_BUTTON_DPAD_RIGHT), "weapon_1 on d-pad right")
	check(_has_event(&"weapon_2", func(ev): return ev is InputEventKey and ev.physical_keycode == KEY_2),
		"weapon_2 on 2")
	check(_has_event(&"weapon_2", func(ev): return ev is InputEventJoypadButton \
		and ev.button_index == JOY_BUTTON_DPAD_LEFT), "weapon_2 on d-pad left")

func test_slots_are_staff_then_revolver() -> void:
	var pilot := _scene()
	eq(pilot.weapon_slots.size(), 2, "two weapon slots")
	eq(pilot.weapon_slots[0], load(STAFF), "slot 1 is the staff")
	eq(pilot.weapon_slots[1], load(REVOLVER), "slot 2 is the revolver")
	eq(pilot.STAFF_SLOT, 0, "the staff slot is the first")

# --- the slots --------------------------------------------------------------------------------

func test_2_draws_the_revolver_and_2_again_puts_it_away() -> void:
	var pilot := _scene()
	check(pilot.press_weapon(1), "2 starts")
	eq(pilot.current_slot(), 1, "the revolver is the item")
	check(pilot.equip_anim.is_playing(), "it materializes rather than snapping")
	_settle(pilot)
	check(pilot.is_item_drawn(), "the revolver is out")
	check(pilot.press_weapon(1), "2 again starts")
	_settle(pilot)
	check(not pilot.is_item_drawn(), "2 again puts it away")
	eq(pilot.current_slot(), 1, "it stays the last item")

func test_other_number_swaps_through_a_holster() -> void:
	var pilot := _scene()
	pilot.press_weapon(0)
	_settle(pilot)
	check(pilot.is_item_drawn() and pilot.current_slot() == 0, "the staff is out")
	check(pilot.press_weapon(1), "2 with the staff out starts a swap")
	check(pilot.is_swapping(), "a swap is queued")
	eq(pilot.current_slot(), 0, "the staff goes first")
	eq(pilot.equip_anim.direction, -1, "the staff is dematerializing")
	for i in int(ceil(pilot.equip_anim.total_time() / DT)) + 1:
		pilot.equip_anim._process(DT)
	eq(pilot.current_slot(), 1, "then the revolver is the item")
	eq(pilot.equip_anim.direction, 1, "and it is materializing")
	check(not pilot.is_swapping(), "the queue is spent")
	_settle(pilot)
	check(pilot.is_item_drawn() and pilot.current_slot() == 1, "the revolver ends up out")

func test_presses_mid_animation_are_ignored() -> void:
	var pilot := _scene()
	pilot.press_weapon(1)
	check(not pilot.press_weapon(0), "1 mid-draw is ignored")
	check(not pilot.press_equip(), "R mid-draw is ignored")
	_settle(pilot)
	eq(pilot.current_slot(), 1, "the revolver draw finished undisturbed")

func test_r_holsters_whatever_is_out_and_redraws_the_last() -> void:
	var pilot := _scene()
	pilot.press_weapon(1)
	_settle(pilot)
	check(pilot.press_equip(), "R with the revolver out starts")
	_settle(pilot)
	check(not pilot.is_item_drawn(), "R put the revolver away")
	check(pilot.press_equip(), "R with nothing out starts")
	_settle(pilot)
	check(pilot.is_item_drawn() and pilot.current_slot() == 1, "R brings back the revolver, the last one")

func test_holstered_other_number_draws_without_a_swap() -> void:
	var pilot := _scene()
	check(pilot.press_weapon(1), "2 with nothing out starts")
	check(not pilot.is_swapping(), "nothing to swap out")
	eq(pilot.equip_anim.direction, 1, "straight to the draw")

func test_swap_refused_in_a_mantle() -> void:
	var pilot := _scene()
	pilot.press_weapon(0)
	_settle(pilot)
	pilot.is_climbing = true
	check(not pilot.press_weapon(1), "no swap in a mantle")
	eq(pilot.current_slot(), 0, "the staff stays")
	pilot.is_climbing = false

func test_blocked_mid_swap_leaves_the_new_one_holstered() -> void:
	var pilot := _scene()
	pilot.press_weapon(0)
	_settle(pilot)
	pilot.press_weapon(1)
	pilot.equip_anim._process(DT)
	pilot.is_vaulting = true
	pilot.equip_anim._process(DT)
	eq(pilot.current_slot(), 1, "the swap still lands on the revolver")
	check(not pilot.is_item_drawn() and not pilot.equip_anim.is_playing(),
		"but holstered - the vault refuses the draw; R brings it out")
	pilot.is_vaulting = false

func test_draw_slot_snap() -> void:
	var pilot := _scene()
	pilot.draw_slot(1, true)
	check(pilot.is_item_drawn() and pilot.current_slot() == 1, "snapped to the revolver, drawn")
	check(not pilot.equip_anim.is_playing(), "no animation")
	pilot.draw_slot(0, true)
	check(pilot.is_item_drawn() and pilot.current_slot() == 0, "snapped back to the staff, drawn")

func test_toggle_drawn_mid_swap_does_not_chain() -> void:
	var pilot := _scene()
	pilot.press_weapon(0)
	_settle(pilot)
	pilot.press_weapon(1)
	pilot.toggle_drawn()
	check(not pilot.is_swapping(), "a snap drops the queued draw")
	check(not pilot.equip_anim.is_playing(), "nothing left playing")

# --- the hold ---------------------------------------------------------------------------------

func test_revolver_holds_at_any_pace_but_not_in_a_slide_or_the_air() -> void:
	var revolver: HeldItem = load(REVOLVER)
	var staff: HeldItem = load(STAFF)
	check(HOLDER.item_holds_in(revolver, &"Locomotion"), "low ready on the ground")
	check(HOLDER.item_holds_in(revolver, &"crouch"), "and crouched")
	check(not HOLDER.item_holds_in(revolver, &"slide"), "not in a slide")
	check(not HOLDER.item_holds_in(revolver, &"jump"), "not in a jump")
	check(not HOLDER.item_holds_in(revolver, &"wall_run"), "not on a wall-run")
	check(HOLDER.item_holds_in(staff, &"slide"), "the staff keeps its slide hold")

func test_revolver_arm_is_full_standing_still() -> void:
	var revolver: HeldItem = load(REVOLVER)
	var staff: HeldItem = load(STAFF)
	eq(HOLDER.item_target_for(revolver, &"Locomotion", 0.0, 2.5, 5.0), 1.0, "revolver standing: low ready")
	eq(HOLDER.item_target_for(staff, &"Locomotion", 0.0, 2.5, 5.0), 0.0, "staff standing: natural arm")
	eq(HOLDER.item_target_for(staff, &"Locomotion", 5.0, 2.5, 5.0), 1.0, "staff running: held back")
	eq(HOLDER.item_target_for(revolver, &"slide", 5.0, 2.5, 5.0), 0.0, "revolver sliding: off")

func test_idle_pose_blends_into_the_trailing_pose_by_pace() -> void:
	var pilot := _scene()
	pilot.draw_slot(1, true)
	var holder: Node = pilot.item_holder
	var skel: Skeleton3D = holder._skeleton
	var idle := HOLDER.pose_from_rotations(holder.held_item.idle_rotations, skel)
	var run := HOLDER.pose_from_rotations(holder.held_item.hold_rotations, skel)
	# The hand: since the IK aim pass the two poses share the arm and differ at the wrist.
	var arm := skel.find_bone("RightHand")
	var at_rest := HOLDER.blend_poses(idle, run, 0.0)
	var at_run := HOLDER.blend_poses(idle, run, 1.0)
	var half := HOLDER.blend_poses(idle, run, 0.5)
	check((at_rest[arm] as Quaternion).is_equal_approx(idle[arm]), "pace 0: the wide pose")
	check((at_run[arm] as Quaternion).is_equal_approx(run[arm]), "pace 1: the trailing pose")
	var a: float = (idle[arm] as Quaternion).angle_to(run[arm])
	check(a > 0.3, "the two poses are really different (%.2f rad)" % a)
	approx((half[arm] as Quaternion).angle_to(idle[arm]), a * 0.5, 0.01, "half pace: half way between")
	check(holder.current_pose().size() == 4, "the live pose covers the four right-arm bones")
	# The staff has no idle pose: its hold is the same at every pace.
	pilot.draw_slot(0, true)
	var staff: HeldItem = load(STAFF)
	eq(holder.current_pose().size(), HOLDER.pose_from_rotations(staff.hold_rotations, skel).size(), "staff pose unchanged")

# --- the grow ---------------------------------------------------------------------------------

func test_glow_fades_over_the_last_of_the_sweep() -> void:
	approx(ANIM.glow_fade(0.0, 0.3), 1.0, 0.0001, "full glow as it starts")
	approx(ANIM.glow_fade(0.7, 0.3), 1.0, 0.0001, "still full at 70%")
	approx(ANIM.glow_fade(0.85, 0.3), 0.5, 0.0001, "half way through the fade")
	approx(ANIM.glow_fade(1.0, 0.3), 0.0, 0.0001, "gone when formed")

func test_revolver_grows_uniformly_with_a_glow() -> void:
	var pilot := _scene()
	pilot.press_weapon(1)
	var anim: Node = pilot.equip_anim
	check(anim.is_uniform(), "the revolver is a uniform grow")
	# Into the sweep.
	for i in int(ceil((anim.out_time + anim.sweep_time * 0.5) / DT)):
		anim._process(DT)
	var item: Node3D = pilot.item_holder.item_instance
	var sc := item.transform.basis.get_scale()
	check(sc.x > 0.05 and sc.x < 0.999, "part-grown mid-sweep (%s)" % sc)
	approx(sc.x, sc.y, 0.001, "even on every axis")
	approx(sc.y, sc.z, 0.001, "even on every axis")
	var shells: Array = anim._shells
	check(not shells.is_empty(), "glow copies were built")
	var lit := false
	for sh in shells:
		lit = lit or (sh as MeshInstance3D).visible
	check(lit, "the glow is on while it forms")
	check(not anim._edges[0].visible, "no staff end bands on the revolver")
	_settle(pilot)
	for sh in shells:
		check(not (sh as MeshInstance3D).visible, "the glow is off once formed")
	check(item.transform.is_equal_approx(pilot.item_holder.held_item.hand_offset), "full size at hand_offset")

# --- staff-only things ------------------------------------------------------------------------

func test_reflect_does_nothing_with_the_revolver_out() -> void:
	var pilot := _scene()
	pilot.draw_slot(1, true)
	check(not pilot.reflect_spin.try_start(), "left mouse with the revolver out: no spin")
	pilot.draw_slot(0, true)
	check(pilot.reflect_spin.try_start(), "with the staff out it spins")
	pilot.reflect_spin.cancel()

func test_tredge_swaps_the_revolver_for_the_staff() -> void:
	var pilot := _scene()
	pilot.press_weapon(1)
	_settle(pilot)
	pilot.tredge.mode = TREDGE.Mode.FORCED_ON
	pilot.tredge._first = false
	for i in 20:
		pilot.tredge.tick(DT)
	check(pilot.is_tredging, "tredging")
	check(not pilot.tredge.lantern_allowed(), "no torch arm while the revolver is in his hand")
	_settle(pilot)
	eq(pilot.current_slot(), 0, "the staff replaced the revolver")
	check(pilot.is_item_drawn(), "drawn, as his torch")
	pilot.tredge.mode = TREDGE.Mode.FORCED_OFF
	for i in 20:
		pilot.tredge.tick(DT)

func test_tredge_snap_open_swaps_straight_to_the_staff() -> void:
	var pilot := _scene()
	pilot.draw_slot(1, true)
	pilot.tredge._first = true
	pilot.tredge.mode = TREDGE.Mode.FORCED_ON
	pilot.tredge.tick(DT)
	check(pilot.is_item_drawn() and pilot.current_slot() == 0, "the staff is snapped into his hand")
	check(not pilot.equip_anim.is_playing(), "no animation")
	pilot.tredge.mode = TREDGE.Mode.FORCED_OFF
	for i in 20:
		pilot.tredge.tick(DT)
