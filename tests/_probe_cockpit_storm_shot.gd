extends SceneTree

# Throwaway probe, WINDOWED: opens the cockpit storm shot and saves screenshots at fixed shot times,
# to hold up against the user's editor screenshots (docs/specs/cutscene-cockpit-storm.md). Then two
# close debug views to check the right fist lands on the route panel's buttons and the left fist on
# the strip. Run:
#   godot --path . --script tests/_probe_cockpit_storm_shot.gd -- <out_dir>

const SHOTS := [
	{name = "soft.png", t = 0.5},
	{name = "panel_pop.png", t = 1.2},
	{name = "tap1.png", t = 1.9},
	{name = "tap2.png", t = 2.4},
	{name = "confirm.png", t = 2.5},
	{name = "strip_press.png", t = 4.15},
	{name = "ramp.png", t = 5.5},
	{name = "full.png", t = 7.2},
	{name = "lightning.png", t = 7.52},
	{name = "end.png", t = 9.9},
	{name = "close_tap1.png", t = 1.9, eye = Vector3(-0.1, 1.45, 1.1), at = Vector3(-0.45, 1.3, 0.4)},
	{name = "close_tap2.png", t = 2.4, eye = Vector3(-0.1, 1.45, 1.1), at = Vector3(-0.45, 1.3, 0.4)},
	{name = "close_strip.png", t = 4.15, eye = Vector3(1.1, 0.95, 0.35), at = Vector3(0.45, 0.75, 0.38)},
]

var _frames := 0
var _out := ""
var _view := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/cockpit_storm.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 20:
		return false
	var shot: Dictionary = SHOTS[_view]
	var cam: Camera3D = current_scene.get_node("Camera3D")
	var storm: CockpitStormDriver = current_scene.get_node("Storm")
	var ap: AnimationPlayer = current_scene.get_node("AnimationPlayer")
	if _wait == 0:
		ap.pause()
		storm.set_process(false)
		if not current_scene.has_meta(&"cam_rest"):
			current_scene.set_meta(&"cam_rest", cam.global_transform)
	storm.apply(shot.t)
	if shot.has("eye"):
		cam.global_position = shot.eye
		cam.look_at(shot.at)
	else:
		cam.global_transform = current_scene.get_meta(&"cam_rest")
	_wait += 1
	if _wait < 5:
		return false
	_wait = 0
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(shot.name))
	print("saved ", shot.name)
	_view += 1
	return _view >= SHOTS.size()
