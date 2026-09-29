@tool
class_name BouncePad
extends "res://scripts/blockout_box.gd"

# A blockout box that launches anything landing on it through the SAME arc a floor jump
# already gives it - no button, no charge-up, just contact. See docs/specs/bounce-pad.md.
#
# PATH EXTENDS, not `extends BlockoutBox`, for the reason interact_button.gd and
# sliding_door.gd both carry it: blockout-boxes.md declares the global class names and never
# references them across files, because Godot's global class cache is stale exactly once, on
# the first run after somebody pulls, and a cross-file name reference turns that run into a
# parse error rather than a rescan.
#
# `@tool` is per-script and not inherited - without it here _ready() never runs in the editor
# and the box never builds its mesh or collider, so `Engine.is_editor_hint()` guards the parts
# that must not run outside a real game.

const PLAYER_GROUP := &"player"

## Lime, claiming a slot the blockout palette had not used yet - warm is what you clear, cyan
## is what you grab, grey is the instrument, teal is a blockout box. Bounce is a new verb and
## gets a new colour rather than borrowing one of those and lying about what it does.
const COLOUR_BOUNCE := Color(0.42, 0.86, 0.24)

## The Area3D this generates, named the same way InteractButton names its reach volume - see
## BlockoutBox.GENERATED, which this must never collide with.
const AREA_NAME := "Landing"

## How thin the landing trigger sits above the pad's own top face. Thin on purpose: it is what
## makes "walked onto the pad from the side" and "landed on it from above" both read as a
## landing, while staying too shallow for anything to rest inside it and re-trigger without
## actually leaving and touching down again.
const LANDING_DEPTH := 0.3

## The squash-and-stretch pop, seconds. Cosmetic only - the launch itself is instant, on the
## physics frame contact is made.
const BOUNCE_ANIM_TIME := 0.32
## How far the mesh squashes/stretches off 1.0 scale at the peak of the wobble.
const BOUNCE_SQUASH_AMOUNT := 0.35


var _area: Area3D = null
var _bounce_elapsed: float = BOUNCE_ANIM_TIME


## Overrides BlockoutBox's default teal before the base class ever reads it. `tint` is not
## redeclared here - it stays the one BlockoutBox already exports - so a pad still shows up as
## an ordinary tint field in the inspector and still repaints correctly if somebody sets it
## back. This only changes what a freshly placed pad starts as.
func _init() -> void:
	tint = COLOUR_BOUNCE


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_build_area()
	set_physics_process(true)


# --- who bounces ------------------------------------------------------------

## True for a body this pad will launch. Group membership, exactly like InteractButton.accepts
## - project.godot has no [layer_names], so every StaticBody3D on the map (including this pad's
## own collider) shares layer 1 with the Area3D, and the group is what keeps the pad from
## reacting to scenery.
##
## A plain function rather than logic buried in the signal handler, so a --script test run -
## which never steps the physics server and never fires body_entered - can still reach it. Same
## shape as tests/test_door_button.gd's accepts().
func accepts(body: Node) -> bool:
	return body != null and body.is_in_group(PLAYER_GROUP)


## The launch itself, callable directly so a headless test can drive it without a physics
## world. Sets `velocity.y` to the body's own `jump_velocity` - not a constant this file
## invents - so a retune of pilot9's jump height or time-to-apex moves the bounce with it, and
## the arc is provably the same one `_take_floor_jump()` leaves the floor at.
##
## Duck-typed on the two properties rather than a class check: anything that stands on the
## world with a `velocity` and reports its own `jump_velocity` gets the same bounce pilot9
## does, with no dependency on pilot9.gd.
func bounce(body: Node) -> void:
	if not ("velocity" in body) or not ("jump_velocity" in body):
		return
	var v: Vector3 = body.velocity
	v.y = body.jump_velocity
	body.velocity = v
	if "is_jumping" in body:
		body.is_jumping = true
	_bounce_elapsed = 0.0


func _on_body_entered(body: Node3D) -> void:
	if accepts(body):
		bounce(body)


# --- the wobble ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _bounce_elapsed >= BOUNCE_ANIM_TIME:
		return
	_bounce_elapsed = minf(_bounce_elapsed + delta, BOUNCE_ANIM_TIME)
	_apply_wobble(_bounce_elapsed / BOUNCE_ANIM_TIME)


## `t` runs 0 (the instant of contact) to 1 (settled). A squash first - the pad compresses flat
## and spreads wide, the way any springy surface does under a sudden load - then a decaying
## cosine carries it through an overshoot and back to rest, rather than snapping straight back
## and reading as a single hard click.
func _apply_wobble(t: float) -> void:
	var mesh := get_node_or_null(^"Mesh") as MeshInstance3D
	if mesh == null:
		return
	if t >= 1.0:
		mesh.scale = Vector3.ONE
		return
	var decay := exp(-t * 6.0)
	var wobble := -cos(t * TAU * 2.2) * decay
	mesh.scale = Vector3(
		1.0 - wobble * BOUNCE_SQUASH_AMOUNT * 0.5,
		1.0 + wobble * BOUNCE_SQUASH_AMOUNT,
		1.0 - wobble * BOUNCE_SQUASH_AMOUNT * 0.5)


# --- the trigger volume -------------------------------------------------------

## A thin Area3D sitting right on top of the pad's own solid box, added WITHOUT an `owner` -
## exactly like InteractButton's Reach and the jump grid's own geometry. What the .tscn stores
## is the box's own four properties and no volume at all; a duplicated pad rebuilds its own.
func _build_area() -> void:
	_area = Area3D.new()
	_area.name = AREA_NAME
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, LANDING_DEPTH, size.z)
	shape.shape = box
	# Straddling the top face rather than sitting flush above it, so a landing that only just
	# reaches the surface still overlaps on the frame it happens.
	shape.position = Vector3(0.0, size.y - LANDING_DEPTH * 0.5, 0.0)
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
