@tool
class_name SlidingDoor
extends "res://scripts/blockout_box.gd"

# A blockout box that slides straight up out of the way when something calls activate().
# See docs/specs/button-door.md.
#
# PATH EXTENDS, not `extends BlockoutBox`. docs/specs/blockout-boxes.md declares the global
# class names and never references them across files: Godot's global class cache is stale
# exactly once, on the first run after somebody pulls, and a name reference makes that run a
# parse error rather than a rescan. A path inherits the whole box without touching the cache.
#
# `@tool` is NOT inherited - it is per-script. Without it here the editor would not run
# _ready() on this node, the box would never build its mesh or collider, and a door would be an
# empty spot in the viewport. The cost is that _ready() also runs in-editor, which is what the
# Engine.is_editor_hint() guard below is for.
#
# It is still a StaticBody3D, so it teleports rather than sweeps: a player standing on top is
# not carried up, and one wedged against a moving face is intersected rather than pushed. Both
# are inert for a door that retracts UPWARD, away from the path the player is standing in.
# Neither is inert for a door that comes back DOWN - which is why auto_close_after defaults to
# never. See the spec's StaticBody3D section before changing it.

enum State { CLOSED, OPENING, OPEN, CLOSING }


## Metres to rise. **Zero means the door's own height**, which is what makes this pasteable:
## a box's origin is the centre of its base and it spans y 0..size.y, so rising by exactly
## size.y puts its base where its top was and the gap is fully clear at any size. Drag the face
## handles until the door plugs the hole and the travel has already followed.
##
## Set it only for a door that should stop part-way - a gap to slide under, say.
@export var open_distance := 0.0

## Metres per second, NOT a duration. With travel derived from size.y a fixed duration would
## make a 6 m door rise twice as fast as a 3 m one; a fixed rate means every door in the game
## rises at the same speed and takes as long as it is tall. pilot9 has a slide, and "can I get
## under that" is only a learnable skill if the rate is a constant.
@export var open_speed := 3.0

## Seconds to hold open before closing on its own. **Zero means never**, and that is the only
## value the physics above is safe at - a descending door travels down the exact path the
## player is standing in without sweeping or pushing.
@export var auto_close_after := 0.0


## Where the door is in its travel. Read by tests; nothing outside advance() writes it.
var state: int = State.CLOSED

## The y the door was authored at, captured in _ready(). Open is derived from it, so a door
## placed at y=12 opens to 12 + travel() and no coordinate is ever typed.
var closed_y := 0.0

var _open_hold := 0.0


func _ready() -> void:
	# The box builds its own geometry in here. Everything below depends on `size` being real.
	super()
	closed_y = position.y
	if Engine.is_editor_hint():
		return
	# Integrated in the physics step rather than by a Tween: a Tween runs on the idle frame, so
	# the collider and the physics step drift by up to a frame, and pilot9 already reads
	# is_on_floor() and get_floor_normal() one frame late in several places.
	set_physics_process(true)


# --- the contract ---------------------------------------------------------

## Metres this door rises. `open_distance` when set, its own height otherwise.
func travel() -> float:
	return open_distance if open_distance > 0.0 else size.y


## The y the door rests at when fully open.
func open_y() -> float:
	return closed_y + travel()


## Open it. Duck-typed: this is the method InteractButton looks for, and it names no button.
## Idempotent - a second call on an open or opening door does nothing, which is what makes the
## one-shot latch a latch.
func activate() -> void:
	if state == State.OPEN or state == State.OPENING:
		return
	state = State.OPENING


## Close it again. Nothing in the shipped mechanic calls this - `auto_close_after` does, and it
## defaults to off. Here because a door that can close is a door that can be interrupted
## mid-travel, and that is the case worth having written correctly from the start.
func close() -> void:
	if state == State.CLOSED or state == State.CLOSING:
		return
	state = State.CLOSING


## One step of travel. Called from _physics_process, and directly by tests - a --script run
## never steps the physics server, so anything asserted about motion has to be reachable
## without one.
##
## Both branches CLAMP rather than integrate freely: a hitch on a loading frame hands this a
## delta of half a second, and a door that overshoots is a door through the ceiling.
func advance(delta: float) -> void:
	match state:
		State.OPENING:
			position.y = minf(position.y + open_speed * delta, open_y())
			if position.y >= open_y():
				state = State.OPEN
				_open_hold = auto_close_after
		State.OPEN:
			if auto_close_after > 0.0:
				_open_hold -= delta
				if _open_hold <= 0.0:
					state = State.CLOSING
		State.CLOSING:
			position.y = maxf(position.y - open_speed * delta, closed_y)
			if position.y <= closed_y:
				state = State.CLOSED


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	advance(delta)
