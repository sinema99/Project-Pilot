extends SceneTree

# Throwaway probe, WINDOWED: boots hub2.tscn, lets the pilot settle, saves the game camera view.
#   godot --path . --script tests/_probe_hub2_play.gd -- <out_dir>
var _f := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/hub2.tscn")
func _process(_d: float) -> bool:
	_f += 1
	if _f == 150:
		var p := OS.get_cmdline_user_args()[0] + "/hub2_play.png"
		print("saved ", root.get_texture().get_image().save_png(p))
		var pl := current_scene.get_node("Pilot9") as Node3D
		print("PILOT ", pl.global_position, " floor ", pl.is_on_floor())
	return _f > 155
