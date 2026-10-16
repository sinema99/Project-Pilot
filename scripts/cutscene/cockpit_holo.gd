@tool
class_name CockpitHolo
extends Node3D

# The arc of hologram panels round the front of the cockpit seat, in seat space (+Z his facing, +X
# his left). Every panel faces his head, as his ship's own displays would; from the shot most read
# edge-on or mirrored, and that is meant. CockpitReentry trails this whole rig behind the seat on a
# soft spring and feeds it the shot state.
# See docs/specs/cutscene-cockpit.md, "Atmosphere pass".

## Where the panels look: his head, seat space.
@export var head_point := Vector3(0.0, 1.15, -0.15):
	set(value):
		head_point = value
		_rebuild()

## name, kind, size (m), position (seat space), bend (deg).
const PANELS := [
	{name = "Horizon", kind = HoloDisplay.Kind.HORIZON, size = Vector2(0.36, 0.24),
			pos = Vector3(0.44, 1.0, 0.44), bend = 0.0},
	{name = "Heat", kind = HoloDisplay.Kind.HEAT, size = Vector2(0.2, 0.2),
			pos = Vector3(0.1, 1.3, 0.56), bend = 0.0},
	{name = "Radar", kind = HoloDisplay.Kind.RADAR, size = Vector2(0.22, 0.22),
			pos = Vector3(-0.38, 1.12, 0.5), bend = 0.0},
	{name = "Log", kind = HoloDisplay.Kind.LOG, size = Vector2(0.6, 0.12),
			pos = Vector3(0.0, 0.92, 0.6), bend = 50.0},
]

## The big jolt's WARNING, from the user's drawing: in front of his left chest, just above Horizon.
## Hidden until CockpitReentry pops it; not one of `panels`.
const WARNING := {name = "Warning", kind = HoloDisplay.Kind.WARNING, size = Vector2(0.3, 0.2),
		pos = Vector3(0.3, 1.22, 0.37), bend = 0.0}

## The storm shot's route prompt (docs/specs/cutscene-cockpit-storm.md): above Radar on his right,
## from the user's drawing. Only built with `with_route`; hidden until CockpitStormDriver pops it.
const ROUTE := {name = "Route", kind = HoloDisplay.Kind.ROUTE, size = Vector2(0.2, 0.2),
		pos = Vector3(-0.44, 1.32, 0.38), bend = 0.0}

## Builds the ROUTE panel too (the storm shot).
@export var with_route := false:
	set(value):
		with_route = value
		_rebuild()

var panels: Array[HoloPanel] = []
var warning: HoloPanel
var route: HoloPanel


func _ready() -> void:
	_rebuild()


## The shot state, to every panel.
func set_state(t: float, flash: float, glitch: float, roll: float, pitch: float) -> void:
	for p in panels:
		p.set_state(t, flash, glitch, roll, pitch)
	if warning != null and warning.visible:
		warning.set_state(t, flash, glitch, roll, pitch)
	if route != null and route.visible:
		route.set_state(t, flash, glitch, roll, pitch)


## The shot time the ship answers the push, to every readout.
func set_surge(time: float) -> void:
	for p in panels:
		p.set_surge(time)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta(&"generated"):
			remove_child(c)
			c.queue_free()
	panels.clear()
	for spec: Dictionary in PANELS:
		panels.append(_panel(spec))
	warning = _panel(WARNING)
	warning.visible = false
	route = null
	if with_route:
		route = _panel(ROUTE)
		route.visible = false


func _panel(spec: Dictionary) -> HoloPanel:
	var p := HoloPanel.new()
	p.name = spec.name
	p.set_meta(&"generated", true)
	var pos: Vector3 = spec.pos
	var facing := (head_point - pos).normalized()
	p.transform = Transform3D(Basis.looking_at(facing, Vector3.UP, true), pos)
	p.kind = spec.kind
	p.panel_size = spec.size
	p.bend_degrees = spec.bend
	add_child(p)
	return p
