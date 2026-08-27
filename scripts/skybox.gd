extends Node3D

func _ready() -> void:
	var mesh_instance := _find_mesh_instance(self)
	if mesh_instance:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat: Material = mesh_instance.get_surface_override_material(0)
		if mat == null:
			mat = mesh_instance.mesh.surface_get_material(0)
		if mat:
			mat = mat.duplicate()
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				bm.cull_mode = BaseMaterial3D.CULL_DISABLED
				bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh_instance.set_surface_override_material(0, mat)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null
