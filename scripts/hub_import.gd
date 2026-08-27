@tool
extends EditorScenePostImport

# Runs when assets/HUB_blockout.glb is (re)imported.
#  - Adds trimesh (concave) static collision for every MeshInstance3D, so the
#    blockout is solid: floor, walls and ramps all stop the player.
#  - Forces every surface material double-sided (no backface culling) so polys
#    are visible from both sides.
func _post_import(scene: Node) -> Node:
	_process(scene)
	return scene

func _process(node: Node) -> void:
	if node is MeshInstance3D:
		node.create_trimesh_collision()
		_make_double_sided(node)
	for child in node.get_children():
		_process(child)

func _make_double_sided(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for surface in mesh.get_surface_count():
		var mat: Material = mi.get_surface_override_material(surface)
		if mat == null:
			mat = mesh.surface_get_material(surface)
		if mat == null:
			# No material from Blender: give it a neutral greybox tone instead
			# of the default pure white, which blows out under any lighting.
			mat = StandardMaterial3D.new()
			(mat as StandardMaterial3D).albedo_color = Color(0.45, 0.45, 0.45)
		else:
			mat = mat.duplicate()
		if mat is BaseMaterial3D:
			(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.set_surface_override_material(surface, mat)
