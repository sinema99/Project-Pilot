extends "res://tests/test_case.gd"

# Covers scripts/map_import.gd - the contract every map .glb is given at import time so a
# blockout does not have to be normal-perfect in Blender:
#   - trimesh collision on every mesh, solid from BOTH sides (backface_collision),
#   - every surface material drawn from both sides (cull_mode CULL_DISABLED).
#
# Asserted against the imported artifact rather than the script. map_import.gd extends
# EditorScenePostImport, which does not exist outside the editor, so it cannot be called
# here - and the interesting failure is not "the code is wrong" anyway. It is a STALE
# .godot/imported/ cache: the script can be perfectly right while the .scn actually loaded
# by the game was baked before the change, which looks like nothing happened. Loading the
# GLB is the only check that sees that.
#
# What this cannot see: whether a face is solid in a running physics space. The runner has
# no physics step behind it (see tests/test_pilot9_camera_collision.gd), so walking into a
# flipped wall is the player's check, in scenes/trial.tscn.

const MAPS: Array[String] = [
	"res://assets/mission1.glb",
	"res://assets/TrainingV.glb",
	"res://assets/test_platform.glb",
]

var _instances: Array[Node] = []

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super()

# Instantiated, not read as a PackedScene state: the collision StaticBody3D is built by the
# import script and hangs off the mesh, and only a real instance shows it.
func _map(path: String) -> Node:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	return n

func _meshes(node: Node, out: Array[MeshInstance3D]) -> Array[MeshInstance3D]:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_meshes(child, out)
	return out

func _shapes(node: Node, out: Array[CollisionShape3D]) -> Array[CollisionShape3D]:
	if node is CollisionShape3D:
		out.append(node as CollisionShape3D)
	for child in node.get_children():
		_shapes(child, out)
	return out

# --- collision -------------------------------------------------------------

func test_every_map_mesh_carries_trimesh_collision() -> void:
	for path in MAPS:
		var root := _map(path)
		check(root != null, "%s did not load" % path)
		if root == null:
			continue
		var meshes := _meshes(root, [] as Array[MeshInstance3D])
		check(meshes.size() > 0, "%s imported with no MeshInstance3D at all" % path)
		for mi in meshes:
			var shapes := _shapes(mi, [] as Array[CollisionShape3D])
			check(shapes.size() > 0, "%s: mesh %s has no collision" % [path, mi.name])
			for cs in shapes:
				var concave := cs.shape as ConcavePolygonShape3D
				check(concave != null,
					"%s: %s is not a ConcavePolygonShape3D" % [path, mi.name])
				if concave != null:
					check(concave.get_faces().size() > 0,
						"%s: %s has an empty collision shape" % [path, mi.name])

# The feature. Off - Godot's default - a triangle only stops a body arriving at its front,
# so a wall whose normal points the wrong way in Blender is walked straight through while
# still looking solid from the other side.
func test_map_collision_is_solid_from_both_sides() -> void:
	for path in MAPS:
		var root := _map(path)
		if root == null:
			continue
		var shapes := _shapes(root, [] as Array[CollisionShape3D])
		check(shapes.size() > 0, "%s has no collision shapes to check" % path)
		for cs in shapes:
			var concave := cs.shape as ConcavePolygonShape3D
			if concave == null:
				continue
			check(concave.backface_collision,
				"%s: %s collides on one side only" % [path, cs.get_parent().name])

# --- rendering -------------------------------------------------------------

# The other half of the same promise: a flipped face stays visible. Culling only - the
# normal still decides how the face is LIT, which no import setting can fix.
func test_map_surfaces_are_drawn_from_both_sides() -> void:
	for path in MAPS:
		var root := _map(path)
		if root == null:
			continue
		for mi in _meshes(root, [] as Array[MeshInstance3D]):
			var mesh := mi.mesh
			if mesh == null:
				continue
			for surface in mesh.get_surface_count():
				var mat := mi.get_surface_override_material(surface) as BaseMaterial3D
				check(mat != null,
					"%s: %s surface %d has no override material from the import" % [path, mi.name, surface])
				if mat != null:
					eq(mat.cull_mode, BaseMaterial3D.CULL_DISABLED,
						"%s: %s surface %d still culls backfaces" % [path, mi.name, surface])

# --- wiring ----------------------------------------------------------------

# A map added without this line imports with no collision and no double-siding, and nothing
# else in the suite notices, because every assertion above walks maps this list names.
func test_every_map_runs_the_import_script() -> void:
	for path in MAPS:
		var import_path := path + ".import"
		var f := FileAccess.open(import_path, FileAccess.READ)
		check(f != null, "%s is missing" % import_path)
		if f == null:
			continue
		var text := f.get_as_text()
		check(text.contains('import_script/path="res://scripts/map_import.gd"'),
			"%s does not run map_import.gd" % import_path)
