@tool
class_name InteractButton
extends "res://scripts/blockout_box.gd"

# A blockout box you walk up to and press, which calls activate() on whatever `target` points
# at. See docs/specs/button-door.md.
#
# Path extends and @tool for the same two reasons sliding_door.gd carries them - see the header
# there.
#
# The whole design is in one property: `target` defaults to `^"../Door"`. Godot uniquifies node
# names among SIBLINGS only, so two wrappers can each hold a child called `Door`, and a
# duplicated wrapper's button resolves to its own door with nothing to re-wire. Name the boxes
# `button1`/`door1` instead and the first pair works while every paste silently opens the
# original door somewhere else in the map. Identity goes on the wrapper, never the children.
#
# It names nothing about doors. `activate()` is duck-typed exactly as mech.gd duck-types
# `enter_vehicle` on a pilot, so this button drives a lift, a bridge or a light written later
# with no edit to this file.

const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")

const PLAYER_GROUP := &"player"
const INTERACT_ACTION := &"interact"

## The Area3D this generates. Must not collide with BlockoutBox.GENERATED - a name in that list
## would be destroyed on every _rebuild().
const AREA_NAME := "Reach"

## One word, uppercase. The key lives in the prompt's keycap, so it is not in the string - the
## same shape as mech.gd's "PILOT" / "EXIT". See docs/specs/ui-shell.md on chrome vs prose.
const PROMPT_TEXT := "OPEN"

## BlockoutBox.COLOUR_BLOCKOUT at roughly 45% value. Same hue, so a spent button reads as THIS
## OBJECT, SPENT rather than as a different kind of object - every other slot in the blockout
## palette is taken (warm is what you clear, cyan is what you grab, grey is the instrument).
## 45% is also what ui-shell.md already uses to mean locked or inactive.
const COLOUR_PRESSED := Color(0.11, 0.28, 0.26)


## What to press. Relative, and pointing at a sibling named `Door` by default, which is the
## entire copy-and-paste mechanism - see the header.
@export var target: NodePath = ^"../Door"

## Metres of slack around the button's own box. The reach volume is the box inflated by this on
## every axis, so resizing the button resizes its reach.
@export var reach := 1.5

@export var prompt_text := PROMPT_TEXT

@export var pressed_tint := COLOUR_PRESSED


## True once pressed. One-shot: the button goes dark, stops prompting and stops listening. A
## prompt offering an action that does nothing is worse than no prompt.
var spent := false

var _target_node: Node = null
var _prompt: Node = null
var _bodies: Array[Node3D] = []


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_resolve_target()
	_build_area()
	# A button with nothing to press is inert rather than noisy: _resolve_target() has already
	# said why, once.
	var live := _target_node != null
	set_physics_process(live)
	set_process_unhandled_input(live)


# --- who is in range ------------------------------------------------------

## True for a body this button will respond to.
##
## Group membership, not a duck-type. mech.gd tests has_method("enter_vehicle") because it is
## about to CALL that method - the test and the contract are the same object. This button calls
## nothing on the player, so duck-typing would mean inventing a marker method purely to look
## for it. `player` is the group ui-shell.md established and tab_abilities.gd already uses.
##
## It is load-bearing, not cosmetic: project.godot has no [layer_names], so everything is on
## layer 1 and the Area3D reports every StaticBody3D it overlaps - including the blockout box
## this button is mounted on.
##
## A plain function rather than a line inside the signal handler so a headless test can reach
## it: a --script run never steps physics, so body_entered never fires.
func accepts(body: Node) -> bool:
	return body != null and body.is_in_group(PLAYER_GROUP)


## Metres to the closest player body in range, or -1.0 when none is.
func nearest_distance() -> float:
	var best := -1.0
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		var d := global_position.distance_to(body.global_position)
		if best < 0.0 or d < best:
			best = d
	return best


func _on_body_entered(body: Node3D) -> void:
	if accepts(body) and not _bodies.has(body):
		_bodies.append(body)


func _on_body_exited(body: Node3D) -> void:
	_bodies.erase(body)


# --- the prompt and the press ---------------------------------------------

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or spent:
		return
	var d := nearest_distance()
	if d < 0.0:
		return
	# Acquired lazily rather than in _ready(): the first button to need one builds it, so a
	# door pasted into a scene that has never heard of InteractionPrompt still draws a prompt.
	if _prompt == null:
		_prompt = PROMPT_SCRIPT.acquire(self)
	if _prompt != null:
		_prompt.offer(self, d, INTERACT_ACTION, prompt_text)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or spent:
		return
	if not event.is_action_pressed(INTERACT_ACTION):
		return
	# Exactly one button responds however many are in range: the prompt arbitrates by distance
	# and this is the button it settled on.
	if _prompt == null or _prompt.current_source != self:
		return
	press()
	# `interact` includes F, which mech.gd also reads. Consuming it is what stops one press
	# opening a door AND boarding EXIA. mech.gd consumes too; whichever runs first wins, and
	# _unhandled_input order is reverse scene-tree order - so this guarantees ONE action, not a
	# predictable one. See the spec's Known Gaps.
	get_viewport().set_input_as_handled()


## Fires the button: latch it, darken it, and call the target. Public so a test can press a
## button without a viewport or an input event.
func press() -> void:
	if spent:
		return
	spent = true
	_set_base_color(pressed_tint)
	if _prompt != null and _prompt.current_source == self:
		_prompt.clear_now()
	# Guarded again rather than trusting _resolve_target(): press() is public, and a target
	# that lost its script between then and now should be ignored, not a crash mid-playtest.
	if _target_node != null and _target_node.has_method(&"activate"):
		_target_node.activate()


# --- what it is made of ---------------------------------------------------

func _resolve_target() -> void:
	if target.is_empty():
		push_warning("%s: no target set - button is inert." % name)
		return
	var node := get_node_or_null(target)
	if node == null:
		push_warning("%s: target '%s' does not resolve - button is inert." % [name, target])
		return
	if not node.has_method(&"activate"):
		push_warning("%s: target '%s' has no activate() - button is inert." % [name, node.name])
		return
	_target_node = node


# The box inflated by `reach`, added WITHOUT an owner - exactly like the box's own mesh and
# collider and the ruler's geometry. What the .tscn stores is four box properties and no
# volume, a duplicate builds its own, and stale volumes cannot accumulate.
#
# The cost is that it is invisible in the editor. Debug > Visible Collision Shapes shows it in
# a running game; a gizmo would mean growing addons/blockout, which its own spec calls sugar.
func _build_area() -> void:
	var area := Area3D.new()
	area.name = AREA_NAME
	var shape := CollisionShape3D.new()
	# Named, or add_child() invents @CollisionShape3D@41 and nothing can find it again - not the
	# test, and not you in the remote scene tree.
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size + Vector3.ONE * (reach * 2.0)
	shape.shape = box
	# Half a height up, for the same reason the box's own collider is: the origin is the base.
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


# Straight onto the material that is already there, never by writing `tint`. `tint`'s setter
# calls _rebuild(), which remove_child + queue_frees the Mesh, Shape and SizeLabel and builds
# three fresh ones - and destroying a collider from inside a signal that fired during physics
# flushing is how you get "Can't change this state while flushing queries". `tint` keeps
# meaning "what this box is"; this is a paint job on top.
func _set_base_color(colour: Color) -> void:
	var mesh := get_node_or_null(^"Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("base_color", colour)
