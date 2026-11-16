extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn, walks the pilot up to EXIA, shoots the PILOT / STASH
# panel (both highlights), opens the stash from the ground and shoots it. See
# docs/specs/mech-stash.md. Run:
#   godot --path . --script tests/_probe_mech_stash_shot.gd -- <out_dir>

var _frames := 0
var _out := ""
var _step := 0
var _mech: Node3D
var _prompt: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1920, 1080)
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 90:
		return false
	var ui := root.get_node(^"UI")
	var inv := root.get_node(^"Inventory")
	match _step:
		0:
			_mech = get_first_node_in_group(&"mech") as Node3D
			var pilot: Node3D = inv.player()
			print("mech ", _mech, " pilot ", pilot)
			if _mech == null or pilot == null:
				return true
			# Beside it, facing it, inside the interaction area.
			var spot := _mech.global_position + _mech.global_basis.z * 3.0 + _mech.global_basis.x * 2.0
			pilot.global_position = spot + Vector3.UP * 0.5
			_step = 1
			_frames = 60
		1:
			if _frames < 100:
				return false
			_prompt = get_first_node_in_group(&"interaction_prompt")
			print("in range ", _mech.player_in_range, " prompt ", _prompt,
				" options ", _prompt.shown_options() if _prompt else null)
			_shot("panel_pilot")
			if _prompt:
				_prompt.scroll_selection(1)
			_step = 2
			_frames = 90
		2:
			if _frames < 100:
				return false
			print("selected ", _prompt.selected_option() if _prompt else "")
			_shot("panel_stash")
			print("open_stash ", inv.open_stash(_mech))
			_step = 3
			_frames = 80
		3:
			if _frames < 100:
				return false
			var screen: Control = ui._instances.get(&"inventory")
			print("stash mode ", screen.is_stash_mode() if screen else null, " stash items ", inv.stash.items.size())
			if screen:
				var por: Node = screen._portrait
				print("mirror xf ", por._mirror.transform, " cam ", por._camera.position)
				for c: MeshInstance3D in por._copies:
					if c.visible and c.mesh:
						print("  ", c.name, " skinned ", not c.skeleton.is_empty(), " aabb ", (por._mirror.transform * c.transform) * c.mesh.get_aabb())
			_shot("stash_open")
			ui.back()
			_step = 4
			_frames = 80
		4:
			if _frames < 90:
				return false
			_shot("closed")
			return true
	return false


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/mech_stash_%s.png" % [_out, name]
	print("saved ", path, " ", img.save_png(path))
