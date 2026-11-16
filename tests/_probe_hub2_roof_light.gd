extends SceneTree

# Throwaway probe, WINDOWED: hub2 roof-door light + edge snow review shots (docs/specs/hub2-roof-door.md
# rev 1). Camera held still 40 frames per shot.
#   godot --path . --script tests/_probe_hub2_roof_light.gd -- <out_dir> [only_index]
var _f := 0
var _i := 0
var _cam: Camera3D
var _out := ""
var _only := -1
const SHOTS := [
	["spawn_fwd", Vector3(0, 30.8, 84), Vector3(0, 32.0, 40)],
	["near_lip", Vector3(0, 30.8, 10), Vector3(0, 36.0, -40)],
	["lip_down", Vector3(3, 31.5, -12), Vector3(-2, 22.0, -30)],
	["bridge_up", Vector3(0, 23.5, -40), Vector3(4, 58.0, -60)],
	["e_cross", Vector3(-8, 53.5, -35), Vector3(0, 30.0, -70)],
	["shaft_side", Vector3(10, 30.8, -15), Vector3(-12, 20.0, -55)],
	["lip_close", Vector3(15.5, 24.0, -16), Vector3(11.5, 21.8, -22)],
	["walkway_eye", Vector3(14.5, 23.5, -5), Vector3(12.0, 22.0, -30)],
]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	if a.size() > 1:
		_only = int(a[1])
		_i = _only
	change_scene_to_file("res://scenes/hub2.tscn")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 120:
		var inv := root.get_node_or_null("/root/Inventory")
		if inv != null and "persist" in inv:
			inv.persist = false
		var pl := current_scene.get_node("Pilot9") as Node3D
		pl.process_mode = Node.PROCESS_MODE_DISABLED
		pl.visible = false
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		_cam.fov = 70
	if _f > 120 and _i < SHOTS.size():
		var k := _f - 121
		var s: Array = SHOTS[_i]
		var ui := root.get_node_or_null("UI")
		if ui != null:
			while not (ui.stack as Array).is_empty():
				ui.close()
		paused = false
		if k == 0:
			_cam.global_position = s[1]
			_cam.look_at(s[2])
		if k == 40:
			root.get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, s[0]])
			print("PERF %s fps %d" % [s[0], Engine.get_frames_per_second()])
			_i += 1
			_f = 120
			if _only >= 0:
				return true
	return _i >= SHOTS.size()
