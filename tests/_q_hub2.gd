extends SceneTree
var _phys: Node3D
var _f := 0
func _initialize() -> void:
	_phys = Node3D.new()
	var glb: Node3D = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	glb.scale = Vector3.ONE * 0.6
	_phys.add_child(glb)
	root.add_child(_phys)
func r(a: Vector3, b: Vector3) -> String:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.hit_back_faces = true
	var h := _phys.get_world_3d().direct_space_state.intersect_ray(q)
	if h.is_empty(): return "none"
	return "%s n%s d%.2f" % [h["position"], (h["normal"] as Vector3).snapped(Vector3.ONE*0.01), a.distance_to(h["position"])]
func _physics_process(_d: float) -> bool:
	_f += 1
	if _f < 3: return false
	var Q: Array = OS.get_cmdline_user_args()
	for s: String in Q:
		var v := s.split(",")
		var a := Vector3(float(v[0]), float(v[1]), float(v[2]))
		var b := Vector3(float(v[3]), float(v[4]), float(v[5]))
		print(s, " -> ", r(a, b))
	return true
