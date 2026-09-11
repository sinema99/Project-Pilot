extends "res://tests/test_case.gd"

# Covers the 2026-09-11 button and door - a pressable blockout box wired to a box that slides
# up. See docs/specs/button-door.md.
#
# A --script run never steps the physics server, so Area3D.body_entered never fires and no
# amount of setup here will make it. That shaped the scripts rather than being worked around:
# the two things that could be silently wrong are reachable as plain functions - accepts() and
# advance() - and this file calls them directly.
#
# What it fences is everything that breaks QUIETLY. A door that opens 80% looks fine in the
# editor. A pasted button that opens the original door across the map works perfectly, on the
# wrong door. Neither shows up as an error; both show up as a confusing playtest.

const BUTTON_SCRIPT := preload("res://scripts/interact_button.gd")
const DOOR_SCRIPT := preload("res://scripts/sliding_door.gd")
const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")

## Half a millimetre. Everything below is metres of level geometry.
const TOL := 0.0005


# One wrapper holding a Button and a Door, the shape button-door.md specifies. Built children
# first so both are siblings before the wrapper enters the tree - the button resolves ^"../Door"
# in its _ready(), and a door added afterwards would be too late.
func _spawn_pair(door_size := Vector3(2.0, 3.0, 0.5), door_y := 0.0) -> Node3D:
	var wrapper := Node3D.new()
	wrapper.name = "DoorButton"
	var door = DOOR_SCRIPT.new()
	door.name = "Door"
	door.size = door_size
	door.position.y = door_y
	var button = BUTTON_SCRIPT.new()
	button.name = "Button"
	button.size = Vector3(1.0, 1.0, 1.0)
	wrapper.add_child(door)
	wrapper.add_child(button)
	var loop := Engine.get_main_loop() as SceneTree
	# `true` for readable names: a second wrapper becomes DoorButton2, exactly as Ctrl+D would.
	loop.root.add_child(wrapper, true)
	return wrapper


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


# --- the paste ------------------------------------------------------------

# THE point of the feature. Godot uniquifies names among siblings only, so two wrappers can
# each hold a child called `Door` and a duplicated button resolves to its own. Break this and
# every pasted door still opens - the original one, somewhere else in the map, which is a bug
# you find by playing rather than by testing.
func test_the_default_target_is_a_sibling_named_door() -> void:
	var button = BUTTON_SCRIPT.new()
	eq(button.target, NodePath("../Door"), "a fresh button points at a sibling named Door")
	button.free()


func test_a_pasted_pair_drives_its_own_door() -> void:
	var first := _spawn_pair()
	var second := _spawn_pair()
	check(first.name != second.name, "the two wrappers are distinct nodes in the tree")

	first.get_node("Button").press()

	eq(first.get_node("Door").state, DOOR_SCRIPT.State.OPENING,
		"pressing the first button opens the first door")
	eq(second.get_node("Door").state, DOOR_SCRIPT.State.CLOSED,
		"the pasted pair's door is untouched - its button is not wired across")

	_drop(first)
	_drop(second)


# --- the travel -----------------------------------------------------------

# Travel is the door's own height so that resizing it to plug a gap resizes the travel too. An
# explicit default would be two numbers to keep in sync per door, and the failure - a door that
# opens most of the way - looks completely correct in the editor and blocks the player.
func test_travel_defaults_to_the_doors_own_height() -> void:
	var pair := _spawn_pair(Vector3(2.0, 4.5, 0.5))
	var door = pair.get_node("Door")
	approx(door.travel(), 4.5, TOL, "travel is the door's own height by default")
	door.open_distance = 1.2
	approx(door.travel(), 1.2, TOL, "a nonzero open_distance overrides the derived height")
	_drop(pair)


# The closed position is wherever the door was authored, never assumed to be zero - place a
# door at 12 m and it opens to 12 + travel.
func test_closed_is_captured_from_the_authored_transform() -> void:
	var pair := _spawn_pair(Vector3(2.0, 3.0, 0.5), 12.0)
	var door = pair.get_node("Door")
	approx(door.closed_y, 12.0, TOL, "closed is the y the door was placed at")
	approx(door.open_y(), 15.0, TOL, "open is that plus the travel")
	_drop(pair)


func test_the_rise_is_three_metres_per_second() -> void:
	# Six metres tall so a second of travel cannot reach the top and clamp.
	var pair := _spawn_pair(Vector3(2.0, 6.0, 0.5))
	var door = pair.get_node("Door")
	door.activate()
	for _i in 10:
		door.advance(0.1)
	approx(door.position.y, 3.0, TOL, "one second at the default speed is three metres")
	eq(door.state, DOOR_SCRIPT.State.OPENING, "a six metre door is still opening after one second")
	_drop(pair)


# A hitch on a loading frame hands advance() half a second, and a door that integrates freely
# is a door through the ceiling.
func test_the_door_stops_exactly_at_open() -> void:
	var pair := _spawn_pair(Vector3(2.0, 3.0, 0.5))
	var door = pair.get_node("Door")
	door.activate()
	door.advance(100.0)
	approx(door.position.y, door.open_y(), TOL, "an absurd delta lands the door exactly at open")
	eq(door.state, DOOR_SCRIPT.State.OPEN, "and leaves it in OPEN")
	door.advance(100.0)
	approx(door.position.y, door.open_y(), TOL, "and it stays there with auto_close_after at 0")
	_drop(pair)


# --- the latch ------------------------------------------------------------

func test_the_latch_is_one_shot() -> void:
	var pair := _spawn_pair()
	var button = pair.get_node("Button")
	var door = pair.get_node("Door")

	button.press()
	check(button.spent, "a pressed button reports itself spent")
	door.advance(100.0)
	eq(door.state, DOOR_SCRIPT.State.OPEN, "the door opened")

	# Nudge it off its mark so a second activate() would be visible as motion.
	door.position.y = door.open_y() - 1.0
	button.press()
	eq(door.state, DOOR_SCRIPT.State.OPEN,
		"a second press does not re-open a door that is already open")

	_drop(pair)


func test_a_pressed_button_goes_dark() -> void:
	var pair := _spawn_pair()
	var button = pair.get_node("Button")
	var mesh := button.get_node_or_null("Mesh") as MeshInstance3D
	check(mesh != null, "the button built a Mesh")
	if mesh == null:
		_drop(pair)
		return
	var mat := mesh.material_override as ShaderMaterial
	check(mat != null, "the mesh carries the metre grid ShaderMaterial")
	button.press()
	if mat != null:
		var painted: Color = mat.get_shader_parameter("base_color")
		check(painted.is_equal_approx(button.pressed_tint),
			"pressing paints base_color rather than rebuilding the box")
	# The collider survived, which is the whole reason it is painted rather than re-tinted.
	check(button.get_node_or_null("Shape") != null, "the button's collider is not rebuilt")
	_drop(pair)


# --- the wiring -----------------------------------------------------------

# The button names nothing about doors. Break this and it stops driving the lift or bridge it
# was supposed to make possible - which nothing in the project would notice today.
func test_activate_is_duck_typed() -> void:
	var wrapper := Node3D.new()
	var stub := _ActivateStub.new()
	stub.name = "Door"
	var button = BUTTON_SCRIPT.new()
	button.name = "Button"
	wrapper.add_child(stub)
	wrapper.add_child(button)
	var loop := Engine.get_main_loop() as SceneTree
	loop.root.add_child(wrapper, true)

	button.press()
	eq(stub.calls, 1, "anything with an activate() is driven, door or not")

	_drop(wrapper)


func test_a_target_without_activate_is_inert_not_an_error() -> void:
	var wrapper := Node3D.new()
	var bare := Node3D.new()
	bare.name = "Door"
	var button = BUTTON_SCRIPT.new()
	button.name = "Button"
	wrapper.add_child(bare)
	wrapper.add_child(button)
	var loop := Engine.get_main_loop() as SceneTree
	loop.root.add_child(wrapper, true)

	# The assertion is that this line does not take the run down.
	button.press()
	check(true, "pressing a button whose target has no activate() is survivable")

	_drop(wrapper)


# project.godot has no [layer_names], so everything is on layer 1 and the reach volume reports
# every StaticBody3D it overlaps - including the blockout box the button is mounted on. The
# group filter is what stops the button tracking scenery.
func test_accepts_only_player_group_bodies() -> void:
	var pair := _spawn_pair()
	var button = pair.get_node("Button")

	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	var scenery := StaticBody3D.new()

	check(button.accepts(player), "a body in the player group arms the button")
	check(not button.accepts(scenery), "a passing static body does not")
	check(not button.accepts(null), "and neither does nothing at all")

	player.free()
	scenery.free()
	_drop(pair)


# --- what reaches the .tscn -----------------------------------------------

# The same assertion test_blockout.gd makes about the boxes' geometry, for the same reason:
# without an owner, none of this can be serialised into a scene file, so a duplicate rebuilds
# its own and stale volumes cannot accumulate.
func test_nothing_generated_carries_an_owner() -> void:
	var pair := _spawn_pair()
	var button = pair.get_node("Button")
	var area := button.get_node_or_null("Reach")
	check(area != null, "the button generates its reach volume")
	if area != null:
		eq(area.owner, null, "the reach volume has no owner and cannot reach the .tscn")
		check(area is Area3D, "and it is an Area3D")

	var prompt = PROMPT_SCRIPT.acquire(button)
	check(prompt != null, "the first button to ask for a prompt builds one")
	if prompt != null:
		eq(prompt.owner, null, "the auto-created prompt has no owner either")
		check(prompt.is_in_group(PROMPT_SCRIPT.GROUP),
			"and it joins the group, so the next button finds it instead of building a second")
		var again = PROMPT_SCRIPT.acquire(button)
		check(again == prompt, "a second acquire returns the same prompt")
		_drop(prompt)

	_drop(pair)


# The reach is the box inflated by `reach` on every axis, so resizing the button resizes what
# you have to walk into. It is invisible in the editor, which makes it exactly the kind of
# number that can drift without anybody seeing.
func test_the_reach_is_the_box_plus_slack() -> void:
	var pair := _spawn_pair()
	var button = pair.get_node("Button")
	var area := button.get_node_or_null("Reach")
	check(area != null, "the button generates its reach volume")
	if area == null:
		_drop(pair)
		return
	var shape := area.get_node_or_null("Shape") as CollisionShape3D
	check(shape != null, "the reach volume has a collision shape")
	if shape == null:
		_drop(pair)
		return
	var solid := (shape.shape as BoxShape3D).size
	var expected: Vector3 = button.size + Vector3.ONE * (button.reach * 2.0)
	check(solid.is_equal_approx(expected), "the reach is the button's box plus slack all round")
	approx(shape.position.y, button.size.y * 0.5, TOL,
		"and it is centred on the box, whose origin is its base")
	_drop(pair)


# --- input ----------------------------------------------------------------

# The pad binding is the one worth pinning. mech.gd's F is a raw keycode with no joypad event
# at all, so EXIA cannot be boarded on a controller - a door mechanic built to be pasted
# everywhere must not inherit that.
func test_the_interact_action_is_bound_for_key_and_pad() -> void:
	check(InputMap.has_action(&"interact"), "project.godot declares an `interact` action")
	if not InputMap.has_action(&"interact"):
		return
	var keys := 0
	var pads := 0
	for ev in InputMap.action_get_events(&"interact"):
		if ev is InputEventKey:
			keys += 1
		elif ev is InputEventJoypadButton:
			pads += 1
	check(keys >= 1, "interact has at least one key bound")
	check(pads >= 1, "interact has a gamepad button bound")
	eq(PROMPT_SCRIPT.key_label_for(&"interact"), "F",
		"the keycap reads its letter off the InputMap rather than a hardcoded string")


func test_an_unbound_action_does_not_fake_a_keycap() -> void:
	eq(PROMPT_SCRIPT.key_label_for(&"no_such_action_exists"), PROMPT_SCRIPT.NO_KEY,
		"an action with no binding shows the missing-key mark, not a plausible letter")


# A bare node with the one method the button looks for, and a count of how often it was called.
class _ActivateStub extends Node3D:
	var calls := 0

	func activate() -> void:
		calls += 1
