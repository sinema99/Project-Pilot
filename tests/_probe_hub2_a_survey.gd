extends SceneTree
# Throwaway headless survey of real room A (floor -273): floor grid, ceiling, shaft mouth.
var _f := 0
var _phys: Node3D
func _initialize() -> void:
	_phys = Node3D.new()
	var glb: Node3D = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	glb.scale = Vector3.ONE * 0.6
	_phys.add_child(glb)
	root.add_child(_phys)
func _process(_d: float) -> bool:
	_f += 1
	if _f < 4: return false
	var ss := _phys.get_world_3d().direct_space_state
	var line := ""
	for z in range(90, -230, -6):
		var r := ss.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 45, z), Vector3(0, -300, z)))
		line += "%d:%s " % [z, "none" if r.is_empty() else "%.1f(n%.1f)" % [(r["position"] as Vector3).y, (r["normal"] as Vector3).y]]
	print("D centre line floor: ", line)
	return true
