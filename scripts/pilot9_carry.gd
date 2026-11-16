## The crate in his hands: what he carries, the pose, and when it comes down. Built at runtime by
## pilot9.gd::_setup_carry(), like the tredge. pilot9 owns `is_carrying` and the lockouts; this
## sets it. See docs/specs/pilot9-crate-carry.md.
extends Node

const _CarryPose := preload("res://scripts/carry_pose.gd")
const _WorldCrate := preload("res://scripts/inventory/world_crate.gd")
const INTERACT_ACTION := &"interact"

## The visible carried box's edge, metres (the ground crate is 0.9 so it never blocks the view).
const CARRY_EDGE := 0.6
## Seconds of blending the arms in and out.
const BLEND_TIME := 0.25
## Airborne this long and the crate comes out of his hands.
const FALL_DROP_TIME := 0.35
## Seconds the loading animation takes.
const LOAD_TIME := 0.4
## A set-down lands this far in front of him, metres.
const SET_DOWN_AHEAD := 0.9

## What he is carrying (an ItemDef with mech_only), null = empty hands.
var def: ItemDef = null
var pose: SkeletonModifier3D = null
var box: MeshInstance3D = null

var _pilot: Node3D = null
var _skeleton: Skeleton3D = null
var _home := Vector3.ZERO
var _air_time := 0.0
var _loading := 0.0
var _load_grid: ItemGrid = null


func setup(pilot: Node3D, skeleton: Skeleton3D) -> void:
	_pilot = pilot
	_skeleton = skeleton
	if skeleton == null:
		push_error("pilot9_carry: no skeleton - no carry pose")
		return
	pose = _CarryPose.new()
	pose.name = &"CarryPose"
	box = _WorldCrate.build_box(CARRY_EDGE, Color(0.55, 0.42, 0.26))
	box.name = &"CarriedCrate"
	box.visible = false
	skeleton.add_child(box)
	skeleton.add_child(pose)
	pose.box = box
	_refresh_unit()


func _refresh_unit() -> void:
	if _skeleton == null or pose == null or not _skeleton.is_inside_tree():
		return
	var s := _skeleton.global_basis.get_scale().x
	pose.unit = 1.0 / maxf(s, 0.0001)
	box.scale = Vector3.ONE * pose.unit


func is_carrying() -> bool:
	return def != null


## A crate into his hands. `home` is where it stood (a set-down over the void goes back there).
## False, with nothing changed, if his hands are full or he cannot carry right now.
func pick_up(item: ItemDef, home: Vector3) -> bool:
	if def != null or item == null or _pilot == null or not _pilot.can_begin_carry():
		return false
	def = item
	_home = home
	_air_time = 0.0
	_holster()
	_pilot.begin_carry()
	_refresh_unit()
	var mat := box.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = item.color
	return true


## The staff / revolver away, any draw or spin ended on the spot.
func _holster() -> void:
	if _pilot.get("reflect_spin") != null:
		_pilot.reflect_spin.cancel()
	var anim: Node = _pilot.get("equip_anim")
	if anim != null and anim.is_playing():
		anim.finish_now()
	var holder: Node = _pilot.get("item_holder")
	if holder != null and holder.is_drawn:
		holder.set_drawn(false)


## Hands empty and the crate handed on (the mech's stash takes it). Returns what he held.
func release() -> ItemDef:
	var out := def
	def = null
	if _pilot != null:
		_pilot.end_carry()
	return out


## Loads the crate into `grid` over LOAD_TIME: the box shrinks toward the mech, then the grid
## takes it and his hands are empty. Ignored while already loading or with empty hands. If the
## grid has no room when the time is up the crate stays in his hands.
func start_load(grid: ItemGrid, _toward: Vector3) -> bool:
	if def == null or _loading > 0.0:
		return false
	_load_grid = grid
	_loading = LOAD_TIME
	return true


func is_loading() -> bool:
	return _loading > 0.0


## Sets the crate down in front of him as a world crate. True if there was one to set down.
func set_down() -> bool:
	if def == null or _pilot == null or not _pilot.is_inside_tree():
		return false
	var item := release()
	var crate: Node3D = _WorldCrate.new()
	crate.def = item
	var host: Node = _pilot.get_tree().current_scene if _pilot.get_tree().current_scene != null \
		else _pilot.get_parent()
	host.add_child(crate)
	var forward := Vector3.FORWARD
	if _pilot.get("character") is Node3D:
		var yaw: float = (_pilot.get("character") as Node3D).rotation.y
		forward = Vector3(sin(yaw), 0.0, cos(yaw))
	var at: Vector3 = _pilot.global_position + forward * SET_DOWN_AHEAD
	var floor_at := _floor_under(at)
	# No floor under the spot (he is over a drop): back where the crate started.
	crate.global_position = floor_at if floor_at.is_finite() else _home
	crate.home = _home
	return true


## The floor one ray below `at`, or Vector3.INF when there is none.
func _floor_under(at: Vector3) -> Vector3:
	var space := _pilot.get_world_3d().direct_space_state if _pilot.get_world_3d() != null else null
	if space == null:
		return at
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0)
	if _pilot is CollisionObject3D:
		q.exclude = [(_pilot as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else Vector3.INF


func _unhandled_input(event: InputEvent) -> void:
	if def == null or _loading > 0.0 or not event.is_action_pressed(INTERACT_ACTION):
		return
	if _pilot == null or not _pilot.get("controlled") or _pilot.get("frozen"):
		return
	# Anything else the panel is offering (a mech's LOAD CRATE, a door) owns the press.
	var prompt := get_tree().get_first_node_in_group(&"interaction_prompt")
	if prompt != null and prompt.current_source != null:
		return
	if set_down():
		get_viewport().set_input_as_handled()


## A hostile hit, a fall, a pilot switch: the crate leaves his hands where he stands.
func drop_now() -> void:
	set_down()


## One physics tick, from the top of pilot9._physics_process().
func tick(delta: float) -> void:
	if _pilot == null or pose == null:
		return
	if def != null:
		if not _pilot.get("controlled"):
			drop_now()
		elif _pilot.is_on_floor():
			_air_time = 0.0
		else:
			_air_time += delta
			if _air_time >= FALL_DROP_TIME:
				drop_now()
	if _loading > 0.0:
		_tick_load(delta)
	var target := 1.0 if def != null else 0.0
	pose.weight = move_toward(pose.weight, target, delta / BLEND_TIME)
	box.visible = pose.weight > 0.0


func _tick_load(delta: float) -> void:
	if def == null:
		_loading = 0.0
		return
	_loading = maxf(_loading - delta, 0.0)
	var k := 1.0 - _loading / LOAD_TIME
	box.scale = Vector3.ONE * pose.unit * lerpf(1.0, 0.35, k)
	if _loading > 0.0:
		return
	if _load_grid != null and _load_grid.add(def, 1) > 0:
		release()
	_load_grid = null
	box.scale = Vector3.ONE * pose.unit
