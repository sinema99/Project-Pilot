extends SceneTree
# Throwaway headless walk probe: from spawn, walk north off D through the shaft's opening and fall into A.
#   godot --headless --path . --script tests/_probe_hub2_drop.gd
var _f := 0
var _min_y := 1e9
func _initialize() -> void:
	change_scene_to_file("res://scenes/hub2.tscn")
func _process(_d: float) -> bool:
	_f += 1
	if current_scene == null or _f < 30:
		return false
	var pl := current_scene.get_node("Pilot9") as Node3D
	if _f == 30:
		print("START ", pl.global_position)
		pl.global_position = Vector3(4.0, 0.3, -172.0)
		Input.action_press("forward")
	_min_y = minf(_min_y, pl.global_position.y)
	if _f % 20 == 0:
		print("t=%d pos=%s floor=%s" % [_f, pl.global_position, (pl as CharacterBody3D).is_on_floor()])
	if _f > 3000 or pl.global_position.y < -272.0 and (pl as CharacterBody3D).is_on_floor():
		print("END ", pl.global_position, " min_y ", _min_y, " dead? ", pl.global_position.y < -300.0)
		return true
	return false
