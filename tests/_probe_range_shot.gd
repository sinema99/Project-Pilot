extends SceneTree

# Throwaway probe, WINDOWED: puts pilot on the firing range, checks it wakes, lets it fire, reflects
# a bolt perfectly, and saves screenshots. Run:
#   godot --path . --script tests/_probe_range_shot.gd -- <out_dir>

var _pilot: Node
var _range: Node
var _frames := 0
var _out := ""
var _bolt: Node = null
var _pressed := false
var _fired_at := -1

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find(current_scene, "res://scripts/pilot9.gd") if current_scene != null else null
		return _frames > 600
	_range = current_scene.get_node("FiringRange")
	if _frames == 20:
		print("dummy before: ", _range.dummy.state)
		_pilot.global_position = _range.global_position + Vector3(6, 0.7, 12)
		_pilot.toggle_drawn()
		_pilot.camera_pivot.rotation.y = 0.0
		_pilot.spring_arm.spring_length = 4.0
	if _frames == 60:
		print("dummy after step-on: ", _range.dummy.state, " on slab ", _range.pilot_on_slab)
		_shot("range_wake.png")
	if _frames == 150 or (_frames > 150 and _range.dummy.state == 2 and _fired_at < 0):
		print("dummy state ", _range.dummy.state, " pos ", _range.dummy.global_position - _range.global_position)
		if _range.dummy.state != 2:
			return false
		_fired_at = _frames
		_range.dummy.force_fire()
		_pilot.reflect_spin.reflected.connect(func(p, perfect, pt): print("REFLECTED perfect=", perfect))
	if _frames > 150 and _bolt == null:
		for b in get_nodes_in_group("range_bolt"):
			_bolt = b
	if _bolt != null and is_instance_valid(_bolt) and not _pressed and not _bolt.reflected:
		var d: float = _bolt.global_position.distance_to(_pilot.reflect_spin.spin_centre())
		if d < 1.1 + 28.0 * 0.06:
			_pressed = true
			print("press ", _pilot.reflect_spin.try_start())
	if _frames > 150 and _bolt != null and not is_instance_valid(_bolt):
		pass
	if _fired_at > 0 and (_frames - _fired_at) in [10, 25, 40, 55, 70, 85]:
		_shot("range_%d.png" % _frames)
	if _frames == 600:
		print("stats: dealt ", _range.stats.damage_dealt, " hits ", _range.stats.hits_on_dummy, " taken ", _range.stats.hits_taken, " reflects ", _range.stats.reflects_perfect, "/", _range.stats.reflects_normal)
		_pilot.global_position = _range.global_position + Vector3(0, 0.7, 70)
	if _frames == 640:
		print("after leaving: ", _range.dummy.state, " bolts ", get_nodes_in_group("range_bolt").size())
		return true
	return false

func _shot(name_: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name_))
	print("saved ", name_)

func _find(n: Node, path: String) -> Node:
	if n.get_script() != null and n.get_script().resource_path == path:
		return n
	for c in n.get_children():
		var f := _find(c, path)
		if f != null:
			return f
	return null
