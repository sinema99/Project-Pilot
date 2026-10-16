## The blizzard tredge's switch and clock: is he out in the storm, how far the pose has blended,
## the gust, and the staff. Built at runtime by pilot9.gd::_setup_tredge(), like the item holder.
## pilot9 owns `is_tredging` and the lockouts; this sets it. See docs/specs/pilot9-tredge.md.
extends Node

const _TredgePose := preload("res://scripts/tredge_pose.gd")
const _StaffLight := preload("res://scripts/staff_light.gd")

enum Mode { AUTO, FORCED_ON, FORCED_OFF }

## Where "out in the snow" is asked, above his origin: about his chest.
const CHEST_HEIGHT := 1.3
## The cycle's length in seconds (walk_forward's). Two steps per cycle, for the lantern's bob.
const CYCLE := 0.8
## The gust spring: stiffness, damping and the kick a gust's onset gives it.
const SPRING_K := 60.0
const SPRING_C := 5.0
const SPRING_KICK := 3.0
## The gust peak rising through this counts as a gust hitting him.
const GUST_ONSET := 0.5

## AUTO follows the roof map; F6 cycles the others (and tests set them).
var mode: Mode = Mode.AUTO
## Debounced "out in the snow". The tredge itself is pilot9.is_tredging, which also waits for
## plain locomotion.
var exposed := false
## 0..1 gust peak this tick (0 with no storm), and the speed factor it gives.
var gust := 0.0
var pose: SkeletonModifier3D = null
## The torch: the glowing ball over the staff and its light. Faded with the torch arm.
var staff_light: Node3D = null

var _pilot: Node = null
var _storm: Node = null
var _disagree_for := 0.0
var _first := true
var _stagger_v := 0.0
var _last_gust := 0.0
var _grip_dirty := false


func setup(pilot: Node, skeleton: Skeleton3D) -> void:
	_pilot = pilot
	staff_light = _StaffLight.new()
	staff_light.name = &"StaffLight"
	add_child(staff_light)
	if skeleton == null:
		push_error("pilot9_tredge: no skeleton - no tredge pose")
		return
	pose = _TredgePose.new()
	pose.name = &"TredgePose"
	skeleton.add_child(pose)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F6:
		mode = ((mode + 1) % 3) as Mode
		print("tredge: ", ["AUTO", "FORCED ON", "FORCED OFF"][mode])


## The storm in this scene, or null.
func storm() -> Node:
	if _storm == null or not is_instance_valid(_storm) or not _storm.is_inside_tree():
		_storm = null
		if _pilot != null and _pilot.is_inside_tree():
			_storm = _pilot.get_tree().get_first_node_in_group(&"storm")
	return _storm


## Out in the snow this tick, before the debounce.
func raw_exposed() -> bool:
	match mode:
		Mode.FORCED_ON:
			return true
		Mode.FORCED_OFF:
			return false
	var s := storm()
	if s == null:
		return false
	return not s.is_sheltered(_pilot.global_position + Vector3.UP * CHEST_HEIGHT)


## `exposed` after this tick, given the raw reading: it flips only once the raw reading has
## disagreed with it for `debounce` seconds. Static so tests can drive it.
static func debounced(current: bool, raw: bool, disagree_for: float, delta: float,
		debounce: float) -> Array:
	if raw == current:
		return [current, 0.0]
	disagree_for += delta
	if disagree_for >= debounce:
		return [raw, 0.0]
	return [current, disagree_for]


## One physics tick, from the top of pilot9._physics_process().
func tick(delta: float) -> void:
	if _pilot == null:
		return
	var raw := raw_exposed()
	var snap := false
	if _first:
		_first = false
		exposed = raw
		snap = raw
	else:
		var got := debounced(exposed, raw, _disagree_for, delta, _pilot.tredge_debounce)
		exposed = got[0]
		_disagree_for = got[1]

	var was: bool = _pilot.is_tredging
	if exposed and not was and _pilot.can_begin_tredge():
		_pilot.begin_tredge()
		_take_out_staff(snap)
	elif not exposed and was:
		_pilot.end_tredge()

	var s := storm()
	gust = s.gust_peak() if s != null and _pilot.is_tredging else 0.0
	_drive_pose(delta, snap)
	_place_staff()
	_drive_light()


## The staff into his hand: a snap when the scene opens out in the storm, otherwise the draw.
func _take_out_staff(snap: bool) -> void:
	var holder: Node = _pilot.item_holder
	if holder == null or holder.item_instance == null or holder.is_drawn:
		return
	var equip: Node = _pilot.equip_anim
	if snap or equip == null or not equip.ready_to_play():
		_pilot.toggle_drawn()
	elif not equip.is_playing():
		equip.toggle()


## Whether the torch arm may be up: drawn, and no draw or spin moving the arm.
func lantern_allowed() -> bool:
	var holder: Node = _pilot.item_holder
	if holder == null or holder.item_instance == null or not holder.is_drawn:
		return false
	if _pilot.equip_anim != null and _pilot.equip_anim.is_playing():
		return false
	if _pilot.reflect_spin != null and _pilot.reflect_spin.is_spinning():
		return false
	return true


func _drive_pose(delta: float, snap: bool) -> void:
	if pose == null:
		return
	var on: bool = _pilot.is_tredging
	var step: float = delta / maxf(_pilot.tredge_blend_time, 0.001)
	var w_target := 1.0 if on else 0.0
	var l_target := 1.0 if on and lantern_allowed() else 0.0
	if snap:
		pose.weight = w_target
		pose.lantern = l_target
	else:
		pose.weight = move_toward(pose.weight, w_target, step)
		# Never ahead of the body: the arm comes up as part of the hunch.
		pose.lantern = minf(move_toward(pose.lantern, l_target, step), pose.weight)

	# The stumble: a spring following the gust, kicked at each gust's onset so it lurches.
	if _last_gust < GUST_ONSET and gust >= GUST_ONSET:
		_stagger_v += SPRING_KICK
	_last_gust = gust
	_stagger_v += (SPRING_K * (gust - pose.stagger) - SPRING_C * _stagger_v) * delta
	pose.stagger += _stagger_v * delta
	var s := storm()
	if s != null and _pilot.character != null:
		var wind := Vector3(s.wind_direction.x, 0.0, s.wind_direction.y)
		var right: Vector3 = -_pilot.character.global_basis.x
		pose.stagger_side = 1.0 if wind.dot(right) >= 0.0 else -1.0

	var speed: float = Vector2(_pilot.velocity.x, _pilot.velocity.z).length()
	pose.bob_amount = clampf(speed / maxf(_pilot.tredge_speed, 0.01), 0.0, 1.0)
	pose.bob_phase = fmod(pose.bob_phase + delta * _pilot.tredge_clip_rate() / CYCLE * TAU * 2.0, TAU)

	var holder: Node = _pilot.item_holder
	if holder != null and holder.held_item != null:
		pose.staff_axis = (holder.held_item.hand_offset.basis * Vector3.UP).normalized()


## The torch grip: the staff slid up through his fist while the lantern arm is up.
func _place_staff() -> void:
	var holder: Node = _pilot.item_holder
	if holder == null or holder.item_instance == null or holder.held_item == null:
		return
	if not holder.is_drawn or not lantern_allowed():
		_grip_dirty = false
		return
	var amount: float = pose.lantern if pose != null else 0.0
	if amount <= 0.0 and not _grip_dirty:
		return
	var xf: Transform3D = holder.held_item.hand_offset
	xf.origin += xf.basis * Vector3.UP * _pilot.tredge_grip_slide * amount
	holder.item_instance.transform = xf
	_grip_dirty = amount > 0.0


## The torch's ball rides the staff's top end and fades with the torch arm, so it is only there
## while he tredges with the arm up.
func _drive_light() -> void:
	if staff_light == null:
		return
	var holder: Node = _pilot.item_holder
	var staff: Node3D = null
	if holder != null and holder.item_instance != null and holder.is_drawn and lantern_allowed():
		staff = holder.item_instance
	if staff != staff_light.staff and staff != null:
		staff_light.staff_half_length = staff_top(staff)
	staff_light.staff = staff
	staff_light.fade = pose.lantern if pose != null and staff != null else 0.0
	staff_light.stagger = pose.stagger if pose != null else 0.0


## How far up its own +Y the staff's top end is: the top of its meshes' bounds.
static func staff_top(staff: Node3D) -> float:
	var top := 0.0
	for m in staff.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = staff.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb() 				if staff.is_inside_tree() else mi.transform * mi.get_aabb()
		top = maxf(top, box.end.y)
	return top if top > 0.0 else 0.8
