@tool
class_name Blockout
extends Node3D

# The node your map blockout hangs off: a plain Node3D whose children are BlockoutBoxes.
# See docs/specs/blockout-boxes.md.
#
# It lives DIRECTLY in scenes/trial.tscn rather than being instanced from a scene of its own.
# An instanced scene's children cannot be edited from the parent, and editing a box without
# being able to see the jump grid ruler beside it defeats the entire point of building against
# a ruler.
#
# It sits at the world origin and is left there, so a box's inspector `position` reads as world
# metres and can be compared straight against a lane's caption on the platform.
#
# Nothing here is required to USE the boxes - duplicate, move and resize are all the editor's
# own. This is only the one thing the editor has no key for: making the first one.

const BOX_SCRIPT := preload("res://scripts/blockout_box.gd")

## How far in front of the editor camera a new box lands when nothing is under the cursor.
const DROP_DISTANCE := 8.0
## How far the drop ray looks for a surface to stand the box on.
const DROP_RAY := 500.0


@export_tool_button("Add box") var add_action: Callable = add_box

## What a new box starts as. A 4 x 1 x 6 slab is a landing pad you can immediately jump at;
## a 1 m cube would only ever be resized.
@export var new_box_size := Vector3(4.0, 1.0, 6.0)
@export var new_box_snap := 0.5


## Adds one box, standing on whatever the editor camera is pointed at, and selects it. Returns
## it, so tests and other tools can add boxes without an editor in the room.
func add_box() -> Node3D:
	# Untyped on purpose: naming the global class BlockoutBox here would make this script fail
	# to parse on the one run where the editor has not rescanned yet - the run somebody makes
	# straight after pulling this.
	var box = BOX_SCRIPT.new()
	box.name = "Box"
	box.snap = new_box_snap
	box.size = new_box_size
	# `true` for readable names: Box, Box2, Box3 rather than @StaticBody3D@41.
	add_child(box, true)
	# Without an owner the box is not part of the edited scene and is gone the moment the
	# scene is reloaded. The boxes are the one thing here that IS saved.
	var root := get_tree().edited_scene_root if get_tree() else null
	if root:
		box.owner = root
	box.position = _drop_point()
	_select(box)
	return box


# Where to put a new box: on the first surface under the editor camera's forward ray, and eight
# metres out in front if there is nothing there. Dropping it at the origin instead means every
# single box starts with a trip back across the map, and the ruler is parked ninety metres from
# world zero.
#
# Editor-only, through Engine.get_singleton() rather than a direct EditorInterface reference:
# that class does not exist in an exported build, and naming it would make this script fail to
# compile in the game.
func _drop_point() -> Vector3:
	var cam := _editor_camera()
	if cam == null:
		return Vector3.ZERO
	var from := cam.global_position
	var forward := -cam.global_basis.z
	var point := from + forward * DROP_DISTANCE

	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var query := PhysicsRayQueryParameters3D.create(from, from + forward * DROP_RAY)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			point = hit["position"]

	# Snapped in this node's own space, which is the space the inspector shows.
	var local := to_local(point)
	if new_box_snap > 0.0:
		local = local.snappedf(new_box_snap)
	return local


func _editor_camera() -> Camera3D:
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		return null
	var ei := Engine.get_singleton("EditorInterface")
	var viewport := ei.call("get_editor_viewport_3d", 0) as SubViewport
	return viewport.get_camera_3d() if viewport else null


func _select(node: Node) -> void:
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		return
	var selection = Engine.get_singleton("EditorInterface").call("get_selection")
	if selection:
		selection.call("clear")
		selection.call("add_node", node)
