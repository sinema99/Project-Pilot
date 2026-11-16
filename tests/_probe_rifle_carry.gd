extends SceneTree

# Throwaway probe, WINDOWED: rifle carry pose variants on one contact sheet (front 3/4 + top view
# per variant). Each variant adds euler degrees to bones of hold_rotations + idle_rotations, live.
#   godot --path . --script tests/_probe_rifle_carry.gd -- <out_png>
# Inventory.persist is turned off in _process (autoloads are not in the tree in _initialize).

const VARIANTS := [
	{},
	{&"RightUpperArm": Vector3(0, 12, 0)},
	{&"RightUpperArm": Vector3(0, 12, 0), &"LeftUpperArm": Vector3(25, 0, 0)},
	{&"RightUpperArm": Vector3(0, 12, 0), &"LeftUpperArm": Vector3(-25, 0, 0)},
	{&"RightUpperArm": Vector3(0, 12, 0), &"LeftUpperArm": Vector3(0, 25, 0)},
	{&"RightUpperArm": Vector3(0, 12, 0), &"LeftUpperArm": Vector3(0, -25, 0)},
	{&"RightUpperArm": Vector3(0, 12, 0), &"LeftLowerArm": Vector3(25, 0, 0)},
	{&"RightUpperArm": Vector3(0, 12, 0), &"LeftLowerArm": Vector3(-25, 0, 0)},
	{&"RightUpperArm": Vector3(0, 12, 0), &"LeftLowerArm": Vector3(0, 25, 0)},
	{&"RightUpperArm": Vector3(0, 12, 0), &"LeftLowerArm": Vector3(0, -25, 0)},
]
const CELL := 560

var _pilot: Node
var _frames := 0
var _out := ""
var _persist_off := false
var _cam: Camera3D
var _base_hold := {}
var _base_idle := {}
var _v := -1
var _step := 0
var _sheet: Image


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("carry.png")
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if not _persist_off:
		var inv := root.get_node_or_null("/root/Inventory")
		if inv != null:
			inv.persist = false
			_persist_off = true
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	if _frames == 40:
		var dummy: Node = get_nodes_in_group(&"range_dummy")[0]
		_pilot.global_position = dummy.global_position + Vector3(2.0, 0.3, 9.0)
		_pilot.draw_slot(0, true)
		_cam = Camera3D.new()
		_cam.fov = 30.0
		current_scene.add_child(_cam)
	if _frames < 220:
		return false
	var item: HeldItem = _pilot.item_holder.held_item
	if _v < 0:
		_base_hold = item.hold_rotations.duplicate()
		_base_idle = item.idle_rotations.duplicate()
		_sheet = Image.create(CELL * VARIANTS.size(), CELL * 2, false, Image.FORMAT_RGB8)
		_v = 0
		_apply(item)
	_step += 1
	var body: Node3D = _pilot.character
	var c := body.global_position + Vector3(0, 1.25, 0)
	var fwd := body.global_basis.z
	var right := -body.global_basis.x
	if _step >= 8 and _step <= 15:
		_cam.global_position = c + fwd * 1.7 + right * 0.9 + Vector3(0, 0.2, 0)
		_cam.look_at(c)
		_cam.make_current()
	if _step == 15:
		_grab(0)
	elif _step > 15 and _step < 22:
		_cam.global_position = c + Vector3(0, 2.4, 0)
		_cam.look_at(c, fwd)
	elif _step == 22:
		_grab(1)
		_v += 1
		_step = 0
		if _v >= VARIANTS.size():
			item.hold_rotations = _base_hold
			item.idle_rotations = _base_idle
			_sheet.save_png(_out)
			quit()
			return true
		_apply(item)
	return false


func _apply(item: HeldItem) -> void:
	var h: Dictionary[StringName, Vector3] = {}
	var i: Dictionary[StringName, Vector3] = {}
	for k in _base_hold:
		h[k] = _base_hold[k]
	for k in _base_idle:
		i[k] = _base_idle[k]
	var add: Dictionary = VARIANTS[_v]
	for k in add:
		h[k] = h.get(k, Vector3.ZERO) + add[k]
		i[k] = i.get(k, Vector3.ZERO) + add[k]
	item.hold_rotations = h
	item.idle_rotations = i


func _grab(row: int) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var s := img.get_height()
	var x0 := (img.get_width() - s) / 2
	var sq := img.get_region(Rect2i(x0, 0, s, s))
	sq.resize(CELL, CELL)
	sq.convert(Image.FORMAT_RGB8)
	_sheet.blit_rect(sq, Rect2i(0, 0, CELL, CELL), Vector2i(_v * CELL, row * CELL))


func _find_pilot(n: Node) -> Node:
	if n.has_method(&"press_weapon") and not n.frozen:
		return n
	for c in n.get_children():
		var r := _find_pilot(c)
		if r != null:
			return r
	return null
