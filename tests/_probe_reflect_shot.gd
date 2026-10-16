extends SceneTree

# Throwaway probe, WINDOWED: draws the staff, spins it, saves screenshots from behind and from the
# side, then throws a ball at him and logs the reflect. Run:
#   godot --path . --script tests/_probe_reflect_shot.gd -- <out_dir>

var _pilot: Node
var _frames := 0
var _out := ""
var _started := -1
var _side := false
var _ball: Node = null

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 600
	if _frames == 30:
		_pilot.toggle_drawn()
		_pilot.spring_arm.spring_length = 3.5
	if _frames == 60:
		_start(false)
	if _frames == 200:
		_start(true)
	if _started > 0:
		var since := _frames - _started
		if since == 12:
			_dump()
		if since in [4, 10, 16, 22, 28, 34]:
			_shot("reflect_%s_%02d.png" % ["side" if _side else "back", since])
		if since > 60:
			_started = -1
	if _frames == 260:
		_pilot.reflect_spin.reflected.connect(_on_reflected)
		_arm_trial(0.05)
	if _frames == 600:
		_arm_trial(0.4)
	if _ball != null and is_instance_valid(_ball) and _press_at_dist > 0.0 and not _ball.reflected:
		var d: float = _ball.global_position.distance_to(_pilot.reflect_spin.spin_centre())
		if d <= _press_at_dist:
			_press_at_dist = -1.0
			print("press at dist ", d, " phase ", _pilot.reflect_spin.phase)
			print("  started: ", _pilot.reflect_spin.try_start())
	if _ball != null and is_instance_valid(_ball) and _frames > 9999:
		print("  f", _frames, " phase ", _pilot.reflect_spin.phase, " el ", _pilot.reflect_spin.elapsed, " d ", _ball.global_position.distance_to(_pilot.reflect_spin.spin_centre()), " mon ", _pilot.reflect_spin.zone.monitoring)
	if _frames == 900:
		return true
	return false

var _press_at_dist := -1.0

func _arm_trial(lead: float) -> void:
	_pilot.camera_pivot.rotation.y = PI
	var em = current_scene.get_node("ReflectTestEmitter")
	_ball = em.fire()
	_press_at_dist = _pilot.reflect_spin.zone_radius + em.ball_speed * lead
	print("trial lead ", lead, " ball ", _ball)

func _on_reflected(proj: Node, perfect: bool, point: Vector3) -> void:
	var em = current_scene.get_node("ReflectTestEmitter")
	var to_em: Vector3 = ((em.global_position + Vector3.UP) - point).normalized()
	var aim: Vector3 = -_pilot.camera_3d.global_basis.z
	print("REFLECTED perfect=", perfect, " dot(to shooter)=", proj.velocity.normalized().dot(to_em), " dot(aim)=", proj.velocity.normalized().dot(aim), " elapsed=", _pilot.reflect_spin.elapsed)

func _start(side: bool) -> void:
	_side = side
	_pilot.camera_pivot.rotation.y = PI * 0.5 if side else 0.0
	_pilot.camera_pivot.rotation.x = -0.1
	_pilot.character.rotation.y = 0.0
	var spin = _pilot.reflect_spin
	print("start ok: ", spin.try_start(), " ready: ", spin.ready_to_spin())
	_started = _frames

func _dump() -> void:
	var sp = _pilot.reflect_spin
	var sk: Skeleton3D = sp._skeleton
	var c: Vector3 = sp.spin_centre()
	for n in ["RightUpperArm","RightLowerArm","RightHand","LeftUpperArm","LeftLowerArm","LeftHand","UpperChest"]:
		var i := sk.find_bone(n)
		var g: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
		print("  ", n, " ", g, " rel-centre ", g - c, " rest(skel) ", sk.get_bone_global_rest(i).origin)
	print("  centre ", c, " skel scale ", sk.global_transform.basis.get_scale(), " facing ", _pilot.character.global_basis.z)

func _shot(name_: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name_))
	print("saved ", name_, " angle=", _pilot.reflect_spin.angle, " infl=", _pilot.reflect_spin.pose_modifier.influence)

func _find_pilot(n: Node) -> Node:
	if n == null:
		return null
	if n.get_script() != null and n.get_script().resource_path == "res://scripts/pilot9.gd":
		return n
	for c in n.get_children():
		var f := _find_pilot(c)
		if f != null:
			return f
	return null
