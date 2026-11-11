extends SceneTree

# Throwaway probe, WINDOWED: opens the boss arena, stands pilot 18 m in front of the Knight (frozen)
# and steps each of the Knight's moves (docs/specs/knight-moveset.md) by hand, saving a close, a
# side and a player-eye shot at the key moments.
#   godot --path . --script tests/_probe_knight_moves.gd -- <out_dir> [move]   (move: hover/laser/missiles/smash)

const DT := 1.0 / 60.0
## [move, [times...]] - seconds into the move each shot is taken at.
const PLAN := [
	[&"hover", [0.0, 1.2]],
	[&"wake", [0.5, 1.0]],
	[&"laser", [0.4, 0.88, 1.1, 1.3, 1.6, 2.2]],
	[&"missiles", [0.75, 1.15, 1.6, 2.4, 3.2]],
	[&"smash", [0.6, 1.0, 1.45, 1.75, 2.6, 3.7]],
]

var _frames := 0
var _out := ""
var _only := ""
var _plan_i := 0
var _time_i := 0
var _t := 0.0
var _wait := 0
var _view := 0
var _cam: Camera3D
var _brain: KnightBrain
var _pilot: Node3D
## Knight -> pilot at the start (flat): the cameras keep to it even when he lands on pilot.
var _axis := Vector3.BACK


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_only = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 800)
	change_scene_to_file("res://Boss_Arena.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 60:
		return false
	if _frames == 60:
		var arena := current_scene.get_node(^"BossArena") as BossArena
		_brain = arena.brain
		_brain.set_physics_process(false)
		_brain.body.set_physics_process(false)
		_brain.debug_keys = false
		_pilot = arena.pilot
		_pilot.process_mode = Node.PROCESS_MODE_DISABLED
		var k := _brain.body
		_pilot.global_position = Vector3(k.global_position.x, _brain.floor_y, k.global_position.z) + k.global_basis.z * 18.0
		_pilot.look_at(k.global_position, Vector3.UP, true)
		_axis = k.global_basis.z
		_cam = Camera3D.new()
		_cam.fov = 50.0
		current_scene.add_child(_cam)
		_cam.current = true
		_start()
		return false
	if _plan_i >= PLAN.size():
		return true
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_save()
		return false
	var times: Array = PLAN[_plan_i][1]
	var target: float = times[_time_i]
	while _t < target - 0.0001:
		_step()
	_place_cam()
	_wait = 4
	return false


func _start() -> void:
	while _plan_i < PLAN.size() and _only != "" and String(PLAN[_plan_i][0]) != _only:
		_plan_i += 1
	if _plan_i >= PLAN.size():
		return
	_brain.reset()
	_t = 0.0
	_time_i = 0
	_view = 0
	var move: StringName = PLAN[_plan_i][0]
	match move:
		&"hover":
			_brain.start_move(KnightBrain.LASER)
			_brain._clear_attacks()
			_brain._enter(KnightBrain.State.FLOAT)
			_brain.frozen = true
		&"wake":
			_brain._enter(KnightBrain.State.WAKE)
		_:
			_brain.frozen = true
			_brain.start_move(move)


func _step() -> void:
	_brain.tick(DT)
	_brain.body.tick_coat(DT)
	for m in _brain.missiles:
		if is_instance_valid(m):
			m.set_physics_process(false)
			m.step(DT)
	_t += DT


func _place_cam() -> void:
	var k := _brain.body.global_position
	var p := _pilot.global_position
	var a := _axis
	var s := a.cross(Vector3.UP).normalized()
	var mid := (k + p) * 0.5
	match _view:
		0: _cam.look_at_from_position(k + a * 7.0 + s * 3.0 + Vector3.UP * 2.6, k + Vector3.UP * 2.4)
		1: _cam.look_at_from_position(mid + s * 20.0 + Vector3.UP * 5.0, mid + Vector3.UP * 3.0)
		2: _cam.look_at_from_position(p - a * 5.0 + s * 1.2 + Vector3.UP * 2.4, k + Vector3.UP * 3.0)


func _save() -> void:
	var move: String = PLAN[_plan_i][0]
	var times: Array = PLAN[_plan_i][1]
	var name := "%s_%02d_%s.png" % [move, int(round(float(times[_time_i]) * 10.0)), ["close", "side", "pilot"][_view]]
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name))
	print("saved ", name, " state ", _brain.state, " alt ", snappedf(_brain.alt, 0.01), " hits ", _brain.hits)
	_view += 1
	if _view < 3:
		_place_cam()
		_wait = 4
		return
	_view = 0
	_time_i += 1
	if _time_i >= times.size():
		_plan_i += 1
		if _only != "":
			_plan_i = PLAN.size()
		_start()
