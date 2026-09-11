extends "res://tests/test_case.gd"

# Covers the 2026-09-11 blockout boxes - the editable geometry that stands beside the generated
# jump grid ruler. See docs/specs/blockout-boxes.md.
#
# The boxes are edited in the Godot editor, which nothing headless can drive: no test here
# clicks a handle or drags a gizmo. What it fences is everything the editor is allowed to
# ASSUME - that a box's collider is the box you can see, that its origin is its base, that a
# scale never survives on the node, and that none of the geometry it generates can reach the
# .tscn. Every one of those is silent when it breaks: the editor keeps working and the boxes
# keep looking right while measuring, colliding or saving something else.
#
# Geometry is read off the generated children rather than off `size`, for the same reason
# tests/test_pilot9_jump_grid_platform.gd reads the ruler's collision shapes: asserting that
# `size` equals `size` would pass forever.

const BOX_SCRIPT := preload("res://scripts/blockout_box.gd")
const BLOCKOUT_SCRIPT := preload("res://scripts/blockout.gd")

const PLUGIN_CFG := "res://addons/blockout/plugin.cfg"
const PLUGIN_SCRIPT := "res://addons/blockout/blockout_plugin.gd"
const GIZMO_SCRIPT := "res://addons/blockout/blockout_gizmo.gd"

## Half a millimetre. Everything below is metres of level geometry.
const TOL := 0.0005


# Boxes build themselves in _ready(), so a box outside the tree is an empty node - the same
# constraint the ruler's test works under. Freed at the end of each test rather than left for
# the runner: a --script run never reclaims the mesh and shape RIDs.
func _spawn(size: Vector3):
	# Untyped throughout this file: `size`, `snap` and `_bake_scale()` live on the script, and a
	# variable typed Node3D would not compile against any of them.
	var box = BOX_SCRIPT.new()
	box.size = size
	var loop := Engine.get_main_loop() as SceneTree
	loop.root.add_child(box)
	return box


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


func _children_of_type(node: Node, type: String) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		if child.is_class(type):
			out.append(child)
	return out


# The thing you look at and the thing you land on are one box. Let these drift and a gap built
# against the ruler measures one distance on screen and another under pilot9's feet.
func test_mesh_and_collider_are_the_same_box() -> void:
	var box = _spawn(Vector3(4.0, 1.5, 6.0))
	var mesh := box.get_node_or_null("Mesh") as MeshInstance3D
	var shape := box.get_node_or_null("Shape") as CollisionShape3D
	check(mesh != null and shape != null, "a box builds a Mesh and a Shape")
	if mesh == null or shape == null:
		return
	var drawn: Vector3 = (mesh.mesh as BoxMesh).size
	var solid: Vector3 = (shape.shape as BoxShape3D).size
	check(drawn.is_equal_approx(Vector3(4.0, 1.5, 6.0)), "the mesh is the size it was given")
	check(solid.is_equal_approx(drawn), "the collider is the same box as the mesh")
	_drop(box)


# The origin is the centre of the BASE, matching pilot9's origin at his soles and the jump
# grid's at its walking surface. Get it backwards and every box in every map sits half a box
# into the floor - which reads as a placement mistake rather than as a convention mistake, once
# per box, forever.
func test_the_origin_is_the_base() -> void:
	var box = _spawn(Vector3(2.0, 3.0, 2.0))
	var shape := box.get_node_or_null("Shape") as CollisionShape3D
	check(shape != null, "a box builds a Shape")
	if shape == null:
		return
	var half: float = (shape.shape as BoxShape3D).size.y * 0.5
	approx(shape.position.y - half, 0.0, TOL, "the box's underside sits on the node's origin")
	approx(shape.position.y + half, 3.0, TOL, "the box's top sits one height above it")
	approx(shape.position.x, 0.0, TOL, "the box is centred on x")
	approx(shape.position.z, 0.0, TOL, "the box is centred on z")
	_drop(box)


# The scale gizmo is allowed; a leftover scale is not. shaders/metre_grid.gdshader draws
# world-space metres off the model matrix, so a node left at scale 2 keeps drawing 1 m squares
# on a box that is no longer the size it says - the instrument stops measuring and says nothing.
func test_scale_folds_into_size() -> void:
	var box = _spawn(Vector3(4.0, 1.0, 4.0))
	box.scale = Vector3(2.0, 3.0, 1.0)
	box._bake_scale()
	check(box.scale.is_equal_approx(Vector3.ONE), "the node goes back to scale 1")
	check(box.size.is_equal_approx(Vector3(8.0, 3.0, 4.0)), "the scale ends up in the size")
	var mesh := box.get_node_or_null("Mesh") as MeshInstance3D
	check(mesh != null and (mesh.mesh as BoxMesh).size.is_equal_approx(Vector3(8.0, 3.0, 4.0)),
		"and the mesh was rebuilt to it")
	_drop(box)


# A baked scale lands on the box's own increments, so dragging the scale gizmo by eye still
# produces a number you can write in a spec.
func test_a_baked_scale_snaps() -> void:
	var box = _spawn(Vector3(4.0, 1.0, 4.0))
	box.snap = 0.5
	box.scale = Vector3(1.07, 1.0, 1.0)
	box._bake_scale()
	approx(box.size.x, 4.5, TOL, "4.28 m of dragged width rounds to the half metre")
	box.snap = 0.0
	box.scale = Vector3(1.07, 1.0, 1.0)
	box._bake_scale()
	approx(box.size.x, 4.815, TOL, "with snapping off it lands wherever it was dragged")
	_drop(box)


# Nothing thinner than a hand: a zero-thickness box has no collider worth standing on and no
# face left to grab a handle by.
func test_a_box_cannot_be_flattened_away() -> void:
	var box = _spawn(Vector3(4.0, 1.0, 4.0))
	box.size = Vector3(0.0, -3.0, 4.0)
	check(box.size.x >= BOX_SCRIPT.MIN_SIZE and box.size.y >= BOX_SCRIPT.MIN_SIZE,
		"a zero or negative size is held at the minimum")
	_drop(box)


# The same rule the ruler follows: what reaches scenes/trial.tscn is four properties per box and
# no geometry at all. An owner on any of this and every box starts saving a mesh and a collider
# into the scene file, which then goes stale the first time a size changes.
func test_nothing_generated_carries_an_owner() -> void:
	var box = _spawn(Vector3(4.0, 1.0, 4.0))
	check(box.get_child_count() > 0, "a box generates children")
	for child in box.get_children():
		check(child.owner == null, "%s is generated, not serialised" % child.name)
	_drop(box)


# Duplicating is the main thing this exists for - lay out one landing pad, then Ctrl+D it down
# the lane. A duplicate carries copies of the generated children across, so the rebuild has to
# clear them or every copy quietly owns two meshes and two colliders.
func test_a_duplicate_is_one_box() -> void:
	var box = _spawn(Vector3(3.0, 2.0, 5.0))
	var copy = box.duplicate()
	var loop := Engine.get_main_loop() as SceneTree
	loop.root.add_child(copy)
	check(copy.size.is_equal_approx(Vector3(3.0, 2.0, 5.0)), "the copy is the same size")
	eq(_children_of_type(copy, "MeshInstance3D").size(), 1, "the copy has one mesh")
	eq(_children_of_type(copy, "CollisionShape3D").size(), 1, "the copy has one collider")
	var mesh := copy.get_node_or_null("Mesh") as MeshInstance3D
	check(mesh != null and (mesh.mesh as BoxMesh).size.is_equal_approx(Vector3(3.0, 2.0, 5.0)),
		"and it was rebuilt rather than inherited")
	_drop(copy)
	_drop(box)


# The caption over a box is the only place its size is written down in the viewport, so it is
# read back here the way the ruler's lane labels are.
func test_the_label_reads_the_size() -> void:
	var box = _spawn(Vector3(4.0, 1.0, 6.5))
	eq(box.size_text(), "4 x 1 x 6.5", "whole metres lose their decimals, others keep them")
	var label := box.get_node_or_null("SizeLabel") as Label3D
	check(label != null and label.text == box.size_text(), "the billboard carries that text")
	box.show_size_label = false
	check(box.get_node_or_null("SizeLabel") == null, "and it can be turned off")
	_drop(box)


# The one thing the editor has no key for. Everything else about a box - duplicate, move,
# resize, delete - is the editor's own.
func test_add_box_makes_a_box() -> void:
	var root = BLOCKOUT_SCRIPT.new()
	var loop := Engine.get_main_loop() as SceneTree
	loop.root.add_child(root)
	var box = root.add_box()
	check(box != null, "add_box returns the box it made")
	if box != null:
		eq(box.get_parent(), root, "parented to the Blockout node")
		check(box.size.is_equal_approx(root.new_box_size), "at the size new boxes start at")
		approx(box.snap, root.new_box_snap, TOL, "carrying the snap new boxes start at")
	_drop(root)


# Nothing else in the suite compiles the addon. A parse error in it is invisible until the day
# somebody opens the editor and silently has no handles - and the boxes still work, so there is
# nothing to notice.
func test_the_editor_plugin_loads() -> void:
	check(load(PLUGIN_SCRIPT) != null, "the plugin script compiles")
	check(load(GIZMO_SCRIPT) != null, "the gizmo script compiles")
	var cfg := ConfigFile.new()
	eq(cfg.load(PLUGIN_CFG), OK, "plugin.cfg parses")
	eq(String(cfg.get_value("plugin", "script", "")), "blockout_plugin.gd",
		"and points at the plugin script")


# An addon that is present and not enabled is an addon that does nothing, which looks exactly
# like an addon that is broken.
func test_the_editor_plugin_is_enabled() -> void:
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", [])
	check(PLUGIN_CFG in enabled, "project.godot enables res://addons/blockout")
