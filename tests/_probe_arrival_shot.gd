extends SceneTree

# Throwaway probe, WINDOWED: opens the arrival shot and saves the frame at a few shot times, to hold
# up against the reference (docs/specs/cutscene-arrival-ref.png). Run:
#   godot --path . --script tests/_probe_arrival_shot.gd -- <out_dir> [beacons] [noclouds]
# `beacons` holds every beacon lit, to find them; `noclouds` hides the clouds to see the land.

const SHOTS := [
	{name = "arrival_0.0.png", t = 0.0},
	{name = "arrival_5.0.png", t = 5.0},
	{name = "arrival_11.0.png", t = 11.0},
]

var _frames := 0
var _out := ""
var _view := 0
var _wait := 0
var _beacons := false
var _noclouds := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_beacons = args.has("beacons")
	_noclouds = args.has("noclouds")
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	change_scene_to_file("res://scenes/cutscene_arrival.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 20:
		return false
	var shot: Dictionary = SHOTS[_view]
	var s := current_scene as ArrivalShot
	s.animation_player.pause()
	s.set_process(false)
	if _beacons:
		s.beacon_on = s.beacon_period
	if _noclouds:
		s.clouds.visible = false
	s.apply(shot.t)
	_wait += 1
	if _wait < 10:
		return false
	_wait = 0
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(shot.name))
	print("saved ", shot.name)
	_view += 1
	return _view >= SHOTS.size()
