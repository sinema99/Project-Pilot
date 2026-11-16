extends SceneTree

# Bakes where EXIA's wear goes (docs/specs/mech-weathering.md, "Placement pass") into
# assets/mech_wear/<mesh>.res, one subdivided copy of each Mech_V1.glb part with the edge, seam, drop
# and corner fields in CUSTOM2 (see scripts/mech_wear_bake.gd). MechPaint swaps them in.
#
# Re-run after every Mech_V1.glb re-export (MechPaint warns and falls back to the plain paint when a
# part no longer matches its bake). Headless is fine, it takes a minute or two:
#   godot --headless --path . --script tools/bake_mech_wear.gd

const OUT := "res://assets/mech_wear"
const Bake := preload("res://scripts/mech_wear_bake.gd")

func _initialize() -> void:
	var scn: Node = (load("res://scenes/mech.tscn") as PackedScene).instantiate()
	var parts := {}
	for mi: MeshInstance3D in scn.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			parts[str(mi.name)] = mi.mesh
	var t0 := Time.get_ticks_msec()
	var baked: Dictionary = Bake.bake_parts(parts)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for part_name: String in baked:
		var mesh: ArrayMesh = baked[part_name]
		var path := "%s/%s.res" % [OUT, part_name]
		var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
		print("%s: %d -> %d verts, %s" % [part_name, int(mesh.get_meta(&"source_vertex_count")),
			mesh.surface_get_array_len(0), error_string(err)])
	print("baked %d parts in %.1f s" % [baked.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	scn.free()
	quit()
