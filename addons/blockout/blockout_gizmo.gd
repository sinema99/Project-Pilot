@tool
extends EditorNode3DGizmoPlugin

# Five drag handles on a selected BlockoutBox - one per side and one on the top.
# See docs/specs/blockout-boxes.md.
#
# FIVE and not six. A box's origin is the centre of its base, so a bottom handle would sit
# exactly on the move gizmo's origin and be a coin toss to click; the base is where you put it,
# and moving the base is what the move gizmo is for.
#
# A handle moves ONE face and leaves the opposite one planted, which is why each drag writes
# `size` AND `position`: geometry lined up against something on one side has to stay lined up.
# Growing about the centre is the wrong default for level building.
#
# Nothing here writes `scale`. shaders/metre_grid.gdshader draws world-space metres off the
# model matrix, and a scaled node's lines stop being metres - see the header of
# scripts/blockout_box.gd.

const BOX_SCRIPT := preload("res://scripts/blockout_box.gd")

## Handle ids are indices into these. The axis is the direction the face faces, in the box's
## own local space, which is what makes the maths below identical for all four sides.
const AXES: Array[Vector3] = [
	Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3.UP]
const HANDLE_NAMES: Array[String] = ["Width +X", "Width -X", "Depth +Z", "Depth -Z", "Height"]
const TOP := 4

## Teal, the same family as the box tint, so the wireframe reads as part of the blockout rather
## than as another engine gizmo.
const COLOUR_LINES := Color(0.35, 0.85, 0.80)

## Two lines are parallel enough to give up on when the camera is looking almost straight down
## the axis being dragged - at which point a ray tells you nothing about where the face went.
const PARALLEL_EPSILON := 0.0001

# Captured when a drag begins (Godot asks for the handle's value at that moment) so that a
# cancelled drag and an undo both have both halves of the edit to put back. A handle moves a
# face, and moving a face is two properties.
var _start_size := Vector3.ZERO
var _start_position := Vector3.ZERO


func _init() -> void:
	create_material("lines", COLOUR_LINES)
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "BlockoutBox"


# Identified by its script and not by `is BlockoutBox`. Same node either way, but this cannot
# be broken by the global class cache being stale, which it is exactly once - the first time
# somebody opens the project after pulling this.
func _has_gizmo(node: Node3D) -> bool:
	return node != null and node.get_script() == BOX_SCRIPT


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	if node == null:
		return
	var size: Vector3 = node.size
	gizmo.add_lines(_wireframe(size), get_material("lines", gizmo), false)
	var handles := PackedVector3Array()
	var ids := PackedInt32Array()
	for id in AXES.size():
		handles.append(_handle_position(size, id))
		ids.append(id)
	gizmo.add_handles(handles, get_material("handles", gizmo), ids)


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return HANDLE_NAMES[handle_id] if handle_id < HANDLE_NAMES.size() else ""


# Called by the editor when a drag STARTS, to keep something to restore. The extent it returns
# is also what shows in the viewport's readout, so it is deliberately the number a person is
# thinking about: how far that face stands from the middle of the box.
func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var node := gizmo.get_node_3d()
	if node == null:
		return 0.0
	_start_size = node.size
	_start_position = node.position
	return _extent(node.size, handle_id)


func _set_handle(
		gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool,
		camera: Camera3D, screen_point: Vector2) -> void:
	var node := gizmo.get_node_3d()
	if node == null:
		return
	var axis: Vector3 = AXES[handle_id]
	# The line the handle slides along: up the middle of the box for a side handle, up the
	# node's own vertical for the top one.
	var base := Vector3(0.0, node.size.y * 0.5, 0.0)
	if handle_id == TOP:
		base = Vector3.ZERO
	var extent := _ray_along_axis(node, camera, screen_point, base, axis)
	if is_inf(extent):
		return

	var size: Vector3 = node.size
	var index := _axis_index(axis)
	var before: float = size[index]
	# A side handle keeps the far face where it is, so the new width is the untouched half plus
	# wherever the dragged face now sits. The top handle IS the height - the base is anchored.
	size[index] = extent if handle_id == TOP else before * 0.5 + extent
	size[index] = maxf(size[index], BOX_SCRIPT.MIN_SIZE)
	# Snapping the SIZE rather than the dragged face, so the box comes out on whole increments
	# no matter where it started. Ctrl to drag free, the same modifier the editor's own snap
	# uses.
	if not Input.is_key_pressed(KEY_CTRL):
		size = node.snapped_size(size)

	node.size = size
	if handle_id != TOP:
		# Half the growth, along the face that moved: the opposite face ends up back where it
		# started. `basis` is a pure rotation here - nothing ever scales one of these nodes.
		node.position += node.transform.basis * (axis * (size[index] - before) * 0.5)


func _commit_handle(
		gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool,
		_restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	if node == null:
		return
	if cancel:
		node.size = _start_size
		node.position = _start_position
		return
	# Both properties in one action, or an undo puts the size back and leaves the box shifted
	# half a metre off whatever it was lined up against. `false`: the drag already applied the
	# new values, so the action only has to be able to reverse them.
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Resize blockout box")
	undo_redo.add_do_property(node, "size", node.size)
	undo_redo.add_do_property(node, "position", node.position)
	undo_redo.add_undo_property(node, "size", _start_size)
	undo_redo.add_undo_property(node, "position", _start_position)
	undo_redo.commit_action(false)


# --- geometry -------------------------------------------------------------

## How far the face with this id stands from the box's local origin.
func _extent(size: Vector3, handle_id: int) -> float:
	if handle_id == TOP:
		return size.y
	return size[_axis_index(AXES[handle_id])] * 0.5


func _handle_position(size: Vector3, handle_id: int) -> Vector3:
	if handle_id == TOP:
		return Vector3(0.0, size.y, 0.0)
	# Face centres, at half height - the box runs from y = 0 up.
	return AXES[handle_id] * _extent(size, handle_id) + Vector3(0.0, size.y * 0.5, 0.0)


func _axis_index(axis: Vector3) -> int:
	if absf(axis.x) > 0.5:
		return 0
	return 1 if absf(axis.y) > 0.5 else 2


# The twelve edges of the box, in the box's local space: x and z centred, y from the floor up.
func _wireframe(size: Vector3) -> PackedVector3Array:
	var x := size.x * 0.5
	var z := size.z * 0.5
	var y := size.y
	var corners: Array[Vector3] = [
		Vector3(-x, 0.0, -z), Vector3(x, 0.0, -z), Vector3(x, 0.0, z), Vector3(-x, 0.0, z),
		Vector3(-x, y, -z), Vector3(x, y, -z), Vector3(x, y, z), Vector3(-x, y, z)]
	var edges := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	var lines := PackedVector3Array()
	for i in edges:
		lines.append(corners[i])
	return lines


# Where the mouse ray passes the line `base + t * axis`, in the node's local space, returned as
# t. The classic closest-point-between-two-lines: the drag is one-dimensional, so the ray only
# has to answer for one number.
#
# INF when the camera is looking down the axis and the two lines are near parallel, where the
# answer would swing wildly for a pixel of mouse movement. Refusing to move is the right
# failure: the handle stops responding until you orbit, rather than throwing the face at the
# horizon.
func _ray_along_axis(
		node: Node3D, camera: Camera3D, screen_point: Vector2,
		base: Vector3, axis: Vector3) -> float:
	var to_local := node.global_transform.affine_inverse()
	var ray_origin := to_local * camera.project_ray_origin(screen_point)
	var ray_dir := (to_local.basis * camera.project_ray_normal(screen_point)).normalized()

	var w := base - ray_origin
	var b := axis.dot(ray_dir)
	var denom := 1.0 - b * b
	if absf(denom) < PARALLEL_EPSILON:
		return INF
	return (b * ray_dir.dot(w) - axis.dot(w)) / denom
