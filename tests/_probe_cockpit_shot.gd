extends SceneTree

# Throwaway probe, WINDOWED: opens the cockpit shot and saves screenshots, to hold up against the
# user's line sketch and the green hologram reference (docs/specs/cutscene-cockpit.md). The shot
# frames are taken at fixed shot times (buzz, first jolt, the big jolt with its sparks); then a side
# and a front debug view to judge the pose. Run:
#   godot --path . --script tests/_probe_cockpit_shot.gd -- <out_dir>

const SHOTS := [
	{name = "cockpit.png", t = 0.6},
	{name = "cockpit_jolt1.png", t = 1.24},
	{name = "cockpit_big.png", t = 4.16},
	{name = "startle_pop.png", t = 4.22},
	{name = "startle_hold.png", t = 4.5},
	{name = "end_warning.png", t = 4.8},
	{name = "end_reach.png", t = 5.32},
	{name = "end_flick.png", t = 5.42},
	{name = "end_follow.png", t = 5.65},
	{name = "end_back.png", t = 6.0},
	{name = "end_push.png", t = 7.57},
	{name = "drop_jolt1.png", t = 1.22},
	{name = "guard_snap.png", t = 4.24},
	{name = "guard_hold.png", t = 4.8},
	{name = "guard_side.png", t = 4.8, eye = Vector3(2.6, 0.8, 0.0)},
	{name = "guard_front.png", t = 4.8, eye = Vector3(0.0, 0.9, 2.6)},
	{name = "guard_reach.png", t = 5.25},
	{name = "drop_push.png", t = 6.69},
	{name = "lean_windup.png", t = 6.66},
	{name = "lean_drive.png", t = 6.92},
	{name = "swallow_half.png", t = 7.1},
	{name = "swallow_full.png", t = 7.9},
	{name = "end_side_lean.png", t = 6.92, eye = Vector3(2.6, 0.8, 0.0)},
	{name = "end_front_flick.png", t = 5.42, eye = Vector3(0.3, 1.3, 2.4)},
	{name = "side.png", t = 0.6, eye = Vector3(2.6, 0.8, 0.0)},
	{name = "front.png", t = 0.6, eye = Vector3(0.0, 0.9, 2.6)},
]

var _frames := 0
var _out := ""
var _view := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/cockpit.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 20:
		return false
	var shot: Dictionary = SHOTS[_view]
	var cam: Camera3D = current_scene.get_node("Camera3D")
	var re: CockpitReentry = current_scene.get_node("Reentry")
	var ap: AnimationPlayer = current_scene.get_node("AnimationPlayer")
	if _wait == 0:
		ap.pause()
		re.set_process(false)
		if shot.name == "cockpit_big.png":
			re.jolt(1.0)
	# The sparks need real frames to fly; hold the pose at t and let them go.
	re.apply(shot.t)
	if shot.has("eye"):
		cam.global_position = shot.eye
		cam.look_at(Vector3(0.0, 0.7, 0.1))
	_wait += 1
	if _wait < 5:
		return false
	_wait = 0
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(shot.name))
	print("saved ", shot.name)
	_view += 1
	return _view >= SHOTS.size()
