extends SceneTree

# Bakes hub2's industrial wear (docs/specs/hub2-industrial.md) into assets/hub2_wear/:
#   <mesh name>.res   each hub2.glb mesh, cut into flat faces with the edge / corner / seam distances
#   decals.res        every vent, stripe, plate, label, streak (Map space)
#   decals_color.res / decals_glow.res   the decal sheet (ImageTexture)
# Hub2Wear swaps them in at load. Re-run after every hub2.glb re-export (it warns and leaves the
# plain map when a mesh no longer matches its bake):
#   godot --headless --path . --script tools/bake_hub2_wear.gd

const OUT := "res://assets/hub2_wear"

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var scn: Node = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	var bake := Hub2WearBake.new()
	for mi: MeshInstance3D in scn.find_children("*", "MeshInstance3D", true, false):
		bake.add_mesh(str(mi.name), mi.mesh, _relative(mi, scn))
	var baked: Dictionary = bake.bake()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for mesh_name: String in baked:
		var err := ResourceSaver.save(baked[mesh_name], "%s/%s.res" % [OUT, mesh_name], ResourceSaver.FLAG_COMPRESS)
		print("saved %s: %s" % [mesh_name, error_string(err)])
	var atlas := Hub2DecalAtlas.build()
	var placed: Dictionary = bake.scatter(atlas)
	print("decals saved: ", error_string(ResourceSaver.save(placed["mesh"], OUT + "/decals.res", ResourceSaver.FLAG_COMPRESS)))
	print("sheet: ", error_string(ResourceSaver.save(ImageTexture.create_from_image(atlas["color"]), OUT + "/decals_color.res")),
		" ", error_string(ResourceSaver.save(ImageTexture.create_from_image(atlas["glow"]), OUT + "/decals_glow.res")))
	# A copy for looking at.
	(atlas["color"] as Image).save_png("C:/Users/panac/AppData/Local/Temp/claude/eb02f964d13f4351/8a9a6e43-d06b-4e30-8660-74bdb54a69c3/scratchpad/hub2_sheet.png")
	print("baked in %.1f s" % [(Time.get_ticks_msec() - t0) / 1000.0])
	scn.free()
	quit()


## `node`'s transform relative to `root`.
static func _relative(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
