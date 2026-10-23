extends SceneTree

# Throwaway probe, headless: lists pilot9's bones and meshes, to find what his ear fins are.
#   godot --headless --path . --script tests/_probe_hat_ears.gd

var _pilot: Node
var _frames := 0

func _initialize() -> void:
	_pilot = (load("res://scenes/pilot9.tscn") as PackedScene).instantiate()
	root.add_child(_pilot)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var skel := _pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var names := []
	for b in skel.get_bone_count():
		names.append(skel.get_bone_name(b))
	print("bones: ", names)
	for c in skel.get_children():
		if c is MeshInstance3D:
			var m := c as MeshInstance3D
			print(m.name, " surfaces=", m.mesh.get_surface_count() if m.mesh else 0, " aabb=", m.get_aabb())
	return true
