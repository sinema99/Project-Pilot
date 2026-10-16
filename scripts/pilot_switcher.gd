extends Node
## Hands control between the pilots in a scene: 1 plays the first in `pilots`, 2 the second, and
## so on up to 9. The first is the one played on load. Each pilot is a pilot9 with set_controlled().
## See docs/specs/pilot-switch.md.

@export var pilots: Array[NodePath] = []

## Index into `pilots` of the one being played.
var active: int = 0


func _ready() -> void:
	# Every other pilot's _ready() has run by now - the switcher sits after them in the scene.
	select(0, true)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index := key.physical_keycode - KEY_1
	if index >= 0 and index < mini(pilots.size(), 9):
		select(index)
		get_viewport().set_input_as_handled()


## Plays pilot `index` and parks the rest where they stand. Refused while the current one is
## inside a vehicle (pilot9.enter_vehicle() switches his physics off), so nobody is stranded aboard.
func select(index: int, force: bool = false) -> void:
	if index == active and not force:
		return
	var current := _pilot(active)
	if not force and current != null and not current.is_physics_processing():
		return
	if _pilot(index) == null:
		return
	active = index
	for i in pilots.size():
		var pilot := _pilot(i)
		if pilot != null and i != index:
			pilot.set_controlled(false)
	# Last, so its camera is the one left current.
	_pilot(index).set_controlled(true)


func active_pilot() -> Node:
	return _pilot(active)


func _pilot(index: int) -> Node:
	if index < 0 or index >= pilots.size():
		return null
	var node := get_node_or_null(pilots[index])
	return node if node != null and node.has_method(&"set_controlled") else null
