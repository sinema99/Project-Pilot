@tool
extends EditorScenePostImport

# Runs when a map .glb is (re)imported - assets/test_platform.glb,
# assets/TrainingV.glb and assets/mission1.glb all point their import_script here.
#  - Adds trimesh (concave) static collision for every MeshInstance3D, so the
#    map is solid: floor, walls and ramps all stop the player.
#  - Makes that collision solid from *both* sides (backface_collision), so a
#    face whose normal points the wrong way still stops the player.
#  - Forces every surface material double-sided (no backface culling) so polys
#    are visible from both sides.
#
# The last two exist so a blockout does not have to be normal-perfect in
# Blender. A flipped face is invisible and non-solid by default in Godot: you
# walk through a wall that looks solid from the other side, and the wall itself
# vanishes when you get behind it. Both of those are fixed here, at import, for
# every map - not per-mesh in the scene, which would have to be redone on every
# re-export. Normals still decide *shading* (see _make_double_sided).
func _post_import(scene: Node) -> Node:
	_process(scene)
	return scene

func _process(node: Node) -> void:
	if node is MeshInstance3D:
		node.create_trimesh_collision()
		_make_solid_both_sides(node)
		_make_double_sided(node)
	for child in node.get_children():
		_process(child)


# create_trimesh_collision() leaves a StaticBody3D child holding a
# ConcavePolygonShape3D, and that shape only collides on the front of each
# triangle by default - a body approaching a face from behind passes straight
# through it. Turning backface_collision on makes every triangle solid from
# both sides, which is what a blockout wants: winding order in Blender stops
# being something the level has to get right before it can be walked on.
static func _make_solid_both_sides(mi: MeshInstance3D) -> void:
	for body in mi.get_children():
		if not (body is StaticBody3D):
			continue
		for node in body.get_children():
			if not (node is CollisionShape3D):
				continue
			var shape: Shape3D = (node as CollisionShape3D).shape
			if shape is ConcavePolygonShape3D:
				(shape as ConcavePolygonShape3D).backface_collision = true

# Culling only. A flipped face is *lit* by its normal no matter what we do
# here, so a wrong-way normal still reads as a dark or blown-out patch under
# the cel ramp, and the inverted-hull outline still extrudes the wrong way on
# it. Both sides being visible and solid is the floor, not a licence to ignore
# normals entirely when a surface looks wrong.
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
