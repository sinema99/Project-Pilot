extends Node

# The intro shots back to back, to judge how they flow together. See docs/specs/intro-movie.md.
#
# Every shot is built once at startup, each parked in its own SubViewport (its own world), then
# shown for a few frames in turn under a black cover, so its _ready and its first draws in the
# window are paid before anything is on screen. Showing a shot moves it out into the movie; leaving
# moves it back. R restarts, Esc quits, Right / Left skip.

## Emitted when a shot goes live, with its index into SHOTS.
signal shot_changed(index: int)

enum Cut { HARD, FADE }

const SHOTS: Array[String] = [
	"res://scenes/cutscene_intro_space.tscn",
	"res://scenes/cockpit.tscn",
	"res://scenes/cutscene_descent.tscn",
	"res://scenes/cutscene_flyover.tscn",
]

@export var autoplay := true
## Which shot the movie opens on, 1-4.
@export_range(1, 4) var start_shot := 1
@export var cut := Cut.HARD
## Seconds to black and back from black at a FADE cut.
@export var fade_time := 0.3
## Frames each shot is shown under the black cover at startup before the movie starts.
@export var warm_frames := 4

var shots: Array[Node] = []
var shot_index := -1
## The live shot's storms, re-applied when it went live. Empty means storm fog is off.
var live_storms: Array[Storm] = []

var _viewports: Array[SubViewport] = []
var _cameras: Array[Camera3D] = []
var _cover: ColorRect
var _fade: Tween
var _started := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_cover = ColorRect.new()
	_cover.color = Color.BLACK
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_cover)
	build()
	get_viewport().size_changed.connect(_fit_viewports)
	if autoplay:
		for i in shots.size():
			_show(i)
			for f in warm_frames:
				await get_tree().process_frame
		begin()


## Instantiates every shot, paused at its first frame, into its own SubViewport that never draws.
func build() -> void:
	for path in SHOTS:
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var shot: Node = (load(path) as PackedScene).instantiate()
		vp.add_child(shot)
		# Autoplay put it at its first frame; hold it there. (Without a current animation the
		# shots' _process reads of the playhead are errors.)
		(shot.get_node("AnimationPlayer") as AnimationPlayer).pause()
		_viewports.append(vp)
		shots.append(shot)
		_cameras.append(vp.get_camera_3d())
		shot.process_mode = Node.PROCESS_MODE_DISABLED
	_fit_viewports()


## Ends the warm-up: the start shot plays.
func begin() -> void:
	for i in shots.size():
		shots[i].connect(&"finished", _on_shot_finished.bind(i))
	_started = true
	go_to(clampi(start_shot, 1, shots.size()) - 1)


## Cuts straight to shot `index` from its first frame.
func go_to(index: int) -> void:
	if _fade:
		_fade.kill()
		_fade = null
	_cover.color.a = 0.0
	_show(index)


## Replays the movie from shot 1.
func restart() -> void:
	go_to(0)


func _show(index: int) -> void:
	if shot_index >= 0:
		_park(shot_index)
	shot_index = index
	var shot := shots[index]
	shot.reparent(self, false)
	shot.process_mode = Node.PROCESS_MODE_INHERIT
	# The movie owns R / Esc; the shot's own handler would restart only itself.
	shot.set_process_input(false)
	if _cameras[index]:
		_cameras[index].make_current()
	_apply_storms(shot)
	shot.call(&"restart")
	if _started:
		shot_changed.emit(index)


func _park(index: int) -> void:
	var shot := shots[index]
	shot.process_mode = Node.PROCESS_MODE_DISABLED
	shot.reparent(_viewports[index], false)


# Storm's fog lives in shared shader globals: whichever storm wrote last wins, and leaving the tree
# switches it off. Re-apply the live shot's storm, or keep the fog off when it has none.
func _apply_storms(shot: Node) -> void:
	live_storms.clear()
	for n in shot.find_children("*", "", true, false):
		if n is Storm:
			(n as Storm).apply()
			live_storms.append(n)
	if live_storms.is_empty():
		RenderingServer.global_shader_parameter_set(&"storm_fog", 0.0)


func _on_shot_finished(index: int) -> void:
	if index != shot_index or index + 1 >= shots.size():
		return
	if cut == Cut.HARD or fade_time <= 0.0:
		_show(index + 1)
		return
	_fade = create_tween()
	_fade.tween_property(_cover, "color:a", 1.0, fade_time)
	_fade.tween_callback(_show.bind(index + 1))
	_fade.tween_property(_cover, "color:a", 0.0, fade_time)


# The parked shots lay out (the title card) at the window's canvas size.
func _fit_viewports() -> void:
	var size := Vector2i(get_viewport().get_visible_rect().size)
	for vp in _viewports:
		vp.size = size


# _input, not _unhandled_input: the UI autoload reads Esc in its own _input to open the pause
# menu. The current scene sits after the autoloads, so it sees the key first and consumes it.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			get_tree().quit()
		KEY_R when _started:
			get_viewport().set_input_as_handled()
			restart()
		KEY_RIGHT when _started:
			get_viewport().set_input_as_handled()
			if shot_index + 1 < shots.size():
				go_to(shot_index + 1)
		KEY_LEFT when _started:
			get_viewport().set_input_as_handled()
			go_to(maxi(shot_index - 1, 0))
