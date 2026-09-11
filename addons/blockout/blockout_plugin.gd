@tool
extends EditorPlugin

# Registers the face handles drawn on a selected BlockoutBox.
# See docs/specs/blockout-boxes.md.
#
# SUGAR, and deliberately nothing else. Every capability the blockout has - select, duplicate,
# move, resize, delete - works with this plugin switched off, through the editor's own gizmos
# and the inspector. What it adds is precision: a handle on a face beats typing a Vector3 when
# what you are actually doing is looking at a gap.
#
# So if it ever misbehaves, turning it off in Project Settings > Plugins costs you handles and
# nothing else. scripts/blockout_box.gd has no idea this exists.

const Gizmo := preload("res://addons/blockout/blockout_gizmo.gd")

var _gizmo: EditorNode3DGizmoPlugin = null


func _enter_tree() -> void:
	_gizmo = Gizmo.new()
	add_node_3d_gizmo_plugin(_gizmo)


func _exit_tree() -> void:
	if _gizmo:
		remove_node_3d_gizmo_plugin(_gizmo)
		_gizmo = null
