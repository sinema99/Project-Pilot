extends SceneTree

# Probe: boots the trial scene headless, wakes the firing-range dummy, aims the camera at it and fires
# both guns, then reports what the dummy's take_hit heard. godot --headless --path . --script
# tests/_probe_gunplay_hit.gd. Sets Inventory.persist = false first (windowed probes write the real save).

var _frame := 0
var _pilot: Node = null
var _dummy: Node = null
var _hits: Array = []
var _stage := 0

func _initialize() -> void:
	var inv := root.get_node_or_null("/root/Inventory")
	if inv != null:
		inv.persist = false
	var ps := load("res://scenes/trial.tscn") as PackedScene
	root.add_child(ps.instantiate())

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	if _stage == 0:
		var pilots := get_nodes_in_group(&"reflect_target")
		var dummies := get_nodes_in_group(&"range_dummy")
		if pilots.is_empty() or dummies.is_empty():
			print("PROBE FAIL: no pilot or dummy (%d / %d)" % [pilots.size(), dummies.size()])
			quit(1)
			return true
		_pilot = pilots[0]
		_dummy = dummies[0]
		_pilot.global_position = _dummy.global_position + Vector3(0, 0.2, 9)
		var range_node := _dummy.get_parent()
		if range_node != null and range_node.has_method(&"enter"):
			range_node.enter(_pilot)
		_dummy.hit.connect(func(a, k, p): _hits.append([a, k]))
		_pilot.set_item(load("res://resources/items/revolver.tres"))
		_pilot.toggle_drawn()
		_stage = 1
		return false
	if _stage == 1 and _frame > 40:
		# Dead on, and the same frame as the shot: the dummy circles.
		_pilot.camera_3d.look_at(_dummy.global_position + Vector3(0, 1.0, 0))
		var fired: bool = _pilot.gunplay.try_fire()
		print("revolver fired: ", fired, "  rounds left: ", _pilot.gunplay.rounds_left())
		_stage = 2
		return false
	if _stage == 2 and _frame > 60:
		print("hits heard: ", _hits)
		# Aim at the sky: a miss reports nothing.
		_pilot.gunplay.tick(0.4)
		_pilot.camera_3d.look_at(_pilot.camera_3d.global_position + Vector3.UP * 5.0, Vector3.RIGHT)
		_pilot.gunplay.try_fire()
		_stage = 3
		return false
	if _stage == 3 and _frame > 80:
		print("hits after a sky shot: ", _hits.size(), " (should still be the same)")
		var ok: bool = _hits.size() == 1 and _hits[0][0] == 25.0 and _hits[0][1] == &"bullet"
		print("PROBE ", "PASS" if ok else "FAIL")
		quit(0 if ok else 1)
		return true
	return false
