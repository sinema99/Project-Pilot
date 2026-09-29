extends "res://tests/test_case.gd"

# Covers the 2026-09-20 bounce pad - a blockout box that launches anything landing on it
# through the same arc a floor jump gives. See docs/specs/bounce-pad.md.
#
# A --script run never steps the physics server, so Area3D.body_entered never fires. Same shape
# as tests/test_door_button.gd: the two things that could be silently wrong - accepts() and
# bounce() - are plain, directly-callable functions rather than logic buried in a signal
# handler, and this file calls them directly.

const PAD_SCRIPT := preload("res://scripts/bounce_pad.gd")

const TOL := 0.0005


func _spawn_pad(sz := Vector3(2.0, 2.0, 2.0)) -> Node:
	var pad = PAD_SCRIPT.new()
	pad.name = "BouncePad"
	pad.size = sz
	var loop := Engine.get_main_loop() as SceneTree
	loop.root.add_child(pad, true)
	return pad


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


# A stand-in for pilot9 that carries only the two properties bounce() duck-types on, so this
# file never has to instantiate the real controller to test the launch.
class _BounceableStub extends CharacterBody3D:
	var jump_velocity := 8.5
	var is_jumping := false


# --- the launch -------------------------------------------------------------

# THE point of the feature: the pad does not invent a bounce height, it reads the body's own
# jump_velocity. Regress this into a hardcoded constant and a pilot9 retuned to jump higher
# stops matching the pad - a mismatch nothing here would otherwise catch.
func test_bounce_sets_velocity_to_the_bodys_own_jump_velocity() -> void:
	var pad := _spawn_pad()
	var body := _BounceableStub.new()
	body.velocity = Vector3(3.0, -9.0, 1.0)

	pad.bounce(body)

	approx(body.velocity.y, body.jump_velocity, TOL,
		"the launch is exactly the body's own jump_velocity")
	approx(body.velocity.x, 3.0, TOL, "horizontal velocity is left untouched")
	approx(body.velocity.z, 1.0, TOL, "on both axes")
	check(body.is_jumping, "is_jumping is set, so the launch reads to the AnimationTree like a jump")

	_drop(pad)
	body.free()


func test_bounce_ignores_a_body_with_no_jump_velocity() -> void:
	var pad := _spawn_pad()
	var scenery := StaticBody3D.new()

	# The assertion is that this line does not take the run down.
	pad.bounce(scenery)
	check(true, "a body with no jump_velocity to duck-type on is survivable")

	_drop(pad)
	scenery.free()


# --- who it accepts -----------------------------------------------------------

# project.godot has no [layer_names], so every StaticBody3D on the map - including the pad's
# own collider - shares layer 1 with its trigger volume. The group filter is what stops a pad
# reacting to scenery.
func test_accepts_only_player_group_bodies() -> void:
	var pad := _spawn_pad()

	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	var scenery := StaticBody3D.new()

	check(pad.accepts(player), "a body in the player group is bounced")
	check(not pad.accepts(scenery), "a passing static body is not")
	check(not pad.accepts(null), "and neither is nothing at all")

	player.free()
	scenery.free()
	_drop(pad)


# --- what reaches the .tscn -----------------------------------------------

# The same assertion test_door_button.gd makes about InteractButton's Reach, for the same
# reason: without an owner none of this serialises into the .tscn, so a duplicated pad rebuilds
# its own trigger rather than carrying a stale one along.
func test_the_landing_trigger_has_no_owner() -> void:
	var pad := _spawn_pad()
	var area := pad.get_node_or_null("Landing")
	check(area != null, "the pad generates its landing trigger")
	if area != null:
		eq(area.owner, null, "the landing trigger has no owner and cannot reach the .tscn")
		check(area is Area3D, "and it is an Area3D")
	_drop(pad)


# The trigger has to actually cover the top face it is meant to catch a landing on, or a pad
# resized in the editor quietly stops noticing anything standing on it.
func test_the_landing_trigger_spans_the_pads_footprint() -> void:
	var pad := _spawn_pad(Vector3(4.0, 1.5, 6.0))
	var area := pad.get_node_or_null("Landing")
	check(area != null, "the pad generates its landing trigger")
	if area == null:
		_drop(pad)
		return
	var shape := area.get_node_or_null("Shape") as CollisionShape3D
	check(shape != null, "the landing trigger has a collision shape")
	if shape == null:
		_drop(pad)
		return
	var box := shape.shape as BoxShape3D
	approx(box.size.x, pad.size.x, TOL, "the trigger is as wide as the pad")
	approx(box.size.z, pad.size.z, TOL, "and as deep")
	check(box.size.y < pad.size.y, "and thin - it straddles the top face rather than filling the box")
	_drop(pad)


# --- colour -----------------------------------------------------------------

# Bounce claims its own slot in the blockout palette (lime) rather than reusing warm, cyan or
# teal, each of which already means something else. A fresh pad should not have to be repainted
# by hand to read as what it is.
func test_a_fresh_pad_defaults_to_the_bounce_colour() -> void:
	var pad := _spawn_pad()
	check(pad.tint.is_equal_approx(PAD_SCRIPT.COLOUR_BOUNCE),
		"a freshly constructed pad defaults to the bounce colour, not BlockoutBox's teal")
	_drop(pad)
