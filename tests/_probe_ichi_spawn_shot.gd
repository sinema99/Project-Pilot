extends SceneTree

# Throwaway probe, WINDOWED: boots Ichi.tscn, prints the ground under the pilot's spawn and saves
# a screenshot of the opening frame. Run:
#   godot --path . --script tests/_probe_ichi_spawn_shot.gd

var _frames := 0

func _initialize() -> void:
	change_scene_to_file("res://Ichi.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 900
	if _frames == 5:
		var pilot: Node3D = current_scene.find_child("Pilot9", true, false)
		var space := pilot.get_world_3d().direct_space_state
		var p := pilot.global_position
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 60.0)
		q.exclude = [pilot.get_rid()]
		var hit := space.intersect_ray(q)
		var ship: Node3D = current_scene.find_child("Sinestro2", true, false)
		print("NOSE ", ship.global_basis.z, " SHIP ", ship.global_position, " CHAR YAW ", pilot.get_node("character").rotation.y, " PIVOT YAW ", pilot.get_node("CameraPivot").rotation.y)
		print("SPAWN ", p, " GROUND ", hit.get("position"), " ", hit.get("collider"))
	if _frames == 150:
		root.get_texture().get_image().save_png("C:/Users/panac/AppData/Local/Temp/claude/C--Users-panac-Documents-Project-Pilot/5b1f01d1-265a-45f0-9a92-26c5edf40d3a/scratchpad/ichi_spawn.png")
		return true
	return false
