## pilot9's controller. A copy of addons/real-controller/character.gd
## (fdemir/real-controller, MIT) with four changes, each marked at its site:
##
## 1. Every `Input.mouse_mode` write is removed. Cursor state is owned by
##    scripts/ui/ui_manager.gd project-wide, and RC grabbing the mouse on _ready /
##    on click / on _exit_tree fought it. The ESC and left-click handlers in
##    _unhandled_input existed only to toggle capture, so they go with it; the
##    mouse-look maths they wrapped stays.
## 2. Controller pitch is subtracted, not added, in _handle_controller_camera -
##    stock disagreed in sign with its own mouse path and inverted the right stick.
## 3. Character rotation is gated on movement input in _handle_character_rotation,
##    so the camera can orbit to pilot9's front while he stands still.
## 4. He turns to face where he is travelling rather than welding to camera-back, so
##    there is no strafing and no backing up - `face_travel_direction`, in
##    _handle_character_rotation. See docs/specs/pilot9-turn-to-face.md.
##
## Nothing else is ported - see docs/specs/pilot9-real-controller.md ("Stock Real
## Controller feel").
##
## Added on top of RC, which has no crouch at all: the `crouch` toggle (C / controller B)
## and `crouch_speed`. The AnimationTree reads `is_crouching` directly through
## advance_expression, so it is a plain property and not a setter - see
## scripts/pilot9_build_scene.gd::_ensure_crouch_state().
##
## Also changed from stock RC: `sprint` is a toggle, not a hold - see _update_sprint_toggle().
## Letting go of sprint mid-jump should not drop him out of a run, and a jump buffered into a
## slide needs the sprint intent to outlive the button.
##
## Also added: the double jump. `air_jumps` extra jumps while airborne, spent by the same
## `jump` action - see _handle_gravity_and_jump(). The tree has no second-jump clip and no
## fall -> jump transition, so the `air_jumped` signal is what restarts the existing jump
## clip from frame 0; scripts/pilot9_animation.gd is its only listener.
##
## Also added: the slide. Same `crouch` key, claimed instead of the toggle when he is
## sprinting - see _handle_crouch_and_slide() and docs/specs/pilot9-slide.md. Its motion
## is not a speed constant; it is the clip's own forward-distance curve, baked onto
## `slide_motion` by the builder and differentiated here.
##
## Also added: the ledge mantle. Automatic - airborne with a ledge in probe range starts it,
## no button - see _handle_gravity_and_jump() and docs/specs/pilot9-climb.md. Unlike every
## other move here it is POSITION driven: the body is written straight onto a path sampled
## off `climb_motion_y` / `climb_motion_z` with collision off, and move_and_slide() is not
## called for its duration.
##
## Also added: the slope tilt. On the floor the `character` mesh's up axis eases toward the
## floor normal so a ramp reads as ground he is standing on - see _align_model_to_slope() and
## docs/specs/pilot9-slope-align.md. The collision capsule never tilts; this is the same trade
## player.gd makes for Setsuna, generalised from her pitch to a pitch and a roll.
##
## Requires a CameraPivot (Node3D) and Camera3D as children, and a character mesh as a child node.
extends CharacterBody3D

## Emitted when a second jump is taken with his feet already off the floor - an air jump. The AnimationTree is already
## in `jump` or `fall` when it happens, and neither re-enters `jump` on its own, so the
## clip is restarted from the listener rather than by a transition condition.
signal air_jumped

enum CameraMode {
	FIRST_PERSON,
	THIRD_PERSON
}

## Node References
## -----------------------------------------------------------------------------
## These nodes must exist in the scene tree for the controller to work properly.

@onready var camera_pivot: Node3D = %CameraPivot
@onready var camera_3d: Camera3D = %Camera3D
@onready var spring_arm: SpringArm3D = camera_pivot.get_node("SpringArm3D")
@onready var character: Node3D = $character
## Toggled off for the mantle's duration - see _start_climb(). RC never needed a
## reference to its own shape; the climb does, because a body on a scripted path over
## an edge has to stop colliding with the edge.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
## Held only so the mech handshake can switch the locomotion tree off while EXIA drives and
## start it again at `Locomotion` on the way out - see enter_vehicle() / exit_vehicle().
## pilot9 is otherwise driven entirely from the sibling `Animation` node
## (scripts/pilot9_animation.gd), which keeps writing blend positions into an inactive tree:
## harmless, because it sets parameters and never calls travel(). See
## docs/specs/pilot9-mech-mount.md.
@onready var anim_tree: AnimationTree = $AnimationTree

## Movement Settings
## -----------------------------------------------------------------------------
## Configure the character's movement speed and jump behavior.
##
## RESET 2026-09-10. Every feel layer below is parked at its own off value - the jump cut,
## the apex hang, the fall multiplier, coyote time, the jump buffer and all four momentum
## dials. Nothing was deleted: the code paths are live and still tested, they just stop
## changing the answer. The reason is that four passes stacked their assists on top of each
## other without a neutral baseline in between, and the result read as lag rather than as
## polish - *"our control over pilot needs to be increased"*. They come back one at a time,
## played between each. See docs/specs/pilot9-movement-reset.md.
##
## `speed`, `walk_speed`, `sprint_speed` and `crouch_speed` are NOT part of that reset and
## never were: they have sat at their authored values since the port and no pass has moved
## them.

@export_group("Movement")
## The three ground speeds are a DESIGN GRID, not taste. Against the 1.2 s airtime that
## `jump_height` and `jump_time_to_apex` produce, 2.5 / 5.0 / 7.5 clear gaps of exactly
## 3 / 6 / 9 m, so a gap in the map can be built to a whole number and read back as one.
## Move any of them and the grid moves with it - `jump_air_time` is what to multiply by.
@export_range(0.1, 20.0, 0.1, "or_greater") var speed: float = 5.0
## Speed when walking. Should be lower than normal speed.
@export_range(0.1, 10.0, 0.1, "or_greater") var walk_speed: float = 2.5
## Speed multiplier when sprinting. Should be higher than normal speed.
##
## 7.5, not 8.0, and the 0.5 is bought deliberately: at the 1.2 s airtime below it is what
## turns a running sprint jump into a gap of exactly 9 m. See `jump_air_time`.
@export_range(0.1, 30.0, 0.1, "or_greater") var sprint_speed: float = 7.5
## The jump, specified the way it reads on screen: how high, and how long to the top. The
## velocity and the gravity are DERIVED from these two - see `jump_velocity` and
## `jump_gravity` below - which is the whole reason the jump stopped being floaty. Tuning a
## velocity against a gravity nobody chose (stock Godot 9.8, real Earth) is two dials
## fighting over one arc; these two are independent, and time is the one that was wrong.
## Both are now ROUND ON PURPOSE - 2.0 m and 0.6 s - because a jump you cannot measure is a
## jump you cannot build a map to. See docs/specs/pilot9-jump-grid.md.
##
## 3.0 m exactly, and a double jump peaks at 6.0 m. Height is the ONE dial that moves
## without disturbing the gap grid: airtime is `jump_time_to_apex` and the fall multiplier,
## neither of which has a height in it, so 3 / 6 / 9 m of horizontal reach survives this
## untouched. What it does move is everything he CLIMBS - see the note on `climb_band_min`,
## because the lips a single jump can now mantle went up with it.
## See docs/specs/pilot9-jump-feel.md.
@export_range(0.2, 5.0, 0.05) var jump_height: float = 3.0
## Seconds from the floor to the top of the jump. The floatiness dial, and the first thing to
## turn when the jump is retuned. 0.60 s is the 0.61 s pre-reset arc rounded - a 10 ms move,
## below what anyone feels - and rounding it is what makes the airtime exactly 1.2 s and the
## gap grid whole. 0.38 was the 2026-09-10 jump-feel pass, parked with the rest of it.
##
## Turning this dial moves every gap in the map: see `jump_air_time`.
@export_range(0.05, 1.5, 0.01) var jump_time_to_apex: float = 0.60
## How much harder he falls than he rises, as a multiple of `jump_gravity`. 1.0 is symmetric
## real physics and reads as swimming - a rise is commitment, a slow fall is nothing. Every
## platformer worth the name runs somewhere in 1.5 - 2.5, and 1.9 is where this sat before
## the reset. Currently 1.0: symmetric, floaty, and deliberately so - it is the baseline the
## asymmetry has to earn its way back from.
@export_range(1.0, 4.0, 0.05) var jump_fall_multiplier: float = 1.0
## Variable jump height. Releasing `jump` while still rising clamps his upward speed to this
## fraction of `jump_velocity`, so a tap is a hop and a hold is the full arc. 1.0 turns it
## off and every jump is the same jump again - which is where the reset parks it, and which
## is the honest trade: it costs the player authority over the arc, and it stops a tap from
## being clipped into a stub. 0.4 was the pre-reset value and is the single dial most
## answerable for *"the jump feels like youre not even getting off the ground"*, because a
## real tap at 60 Hz was cut within a few frames of a 0.38 s rise. When it comes back it
## comes back higher.
@export_range(0.0, 1.0, 0.05) var jump_cut: float = 1.0
## The apex hang. Within this many m/s of the top of the arc - up or down - gravity is scaled
## by `jump_apex_scale`. Celeste's half-gravity trick, and it makes the jump feel SNAPPIER
## rather than floatier: the airtime it adds is spent at the one part of the arc the player
## is actually aiming from. 0.0 turns it off, which is where the reset parks it - 1.5 was the
## pre-reset band. Of every layer switched off here this is the one most likely to come back
## first: it buys snappiness rather than spending it.
@export_range(0.0, 6.0, 0.1) var jump_apex_speed: float = 0.0
## What gravity is multiplied by inside the apex band. 1.0 also turns the hang off.
@export_range(0.1, 1.0, 0.05) var jump_apex_scale: float = 1.0
## Terminal velocity, m/s. He stops accelerating downward here. NOT part of the 2026-09-10
## reset - it is a bound, not an assist, and without one a long drop integrates without limit.
## Under the restored symmetric gravity (9.9 m/s^2 at the current height and apex time) it is
## 39 m into a drop, which nothing in the map reaches, so short hops never meet it and the
## long drops stay readable.
@export_range(1.0, 100.0, 0.5) var max_fall_speed: float = 28.0
## Coyote time: seconds after walking off a ledge that a `jump` press still counts as a floor
## jump. Not garnish - forgiveness is what keeps a fast jump from reading as a punishing one,
## and Celeste ships 0.1 s of it without being a floaty game. Spends no air jump. 0.0 is
## frame-exact edge launches and is where the reset parks it; 0.1 was the pre-reset value.
## Note this one only earns its keep against a SHORT airtime, so it belongs back in the file
## on the same pass that shortens the jump again, not before.
@export_range(0.0, 0.5, 0.01) var coyote_time: float = 0.0
## Jump buffer: seconds before landing that a `jump` press is remembered for and spent on the
## touchdown frame. The other half of the forgiveness, the same argument and the same reset:
## 0.0 here, 0.1 before. Only ever armed when there is no air jump left to spend - see
## _handle_gravity_and_jump().
@export_range(0.0, 0.5, 0.01) var jump_buffer_time: float = 0.0
## Extra jumps available while airborne, on top of the one off the floor. 1 is a double
## jump; 0 is stock Real Controller. Each costs the full `jump_velocity`, replacing the
## fall rather than adding to it, so a second jump taken late reads the same as one taken
## early. Refilled on every grounded frame - see _handle_gravity_and_jump().
@export_range(0, 5, 1) var air_jumps: int = 1
@export var can_walk: bool = true
## Momentum. How fast speed above a sprint bleeds back down to one, in m/s^2, while his feet
## are on the floor. Stock Real Controller has no such thing - it assigns the horizontal
## velocity outright every frame, which deletes whatever a slide down a slope earned on the
## frame the slide ends. Below a sprint nothing here applies and the stock assignment runs
## untouched, dead stop included. See docs/specs/pilot9-slope-momentum.md.
##
## 0.0 by the 2026-09-10 reset (12.0 before it), and 0.0 IS the honest off switch for this
## one: the drive rate is only ever paid while pushing into speed he is already carrying
## above a sprint, and nothing grants him that any more now the slide's boost and slope gain
## are off too. The two BRAKES below are the ones with no zero - read their note.
@export_range(0.0, 60.0, 0.5) var momentum_decay: float = 0.0
## The same in the air, where 0.0 - nothing takes speed off him at all - is the shipping
## value: a jump out of a fast slide is the whole point of gaining the speed. This is the
## DRIVE rate only, paid while the stick is still pushing into his own travel; a released
## stick pays `air_momentum_brake` below.
@export_range(0.0, 60.0, 0.5) var air_momentum_decay: float = 0.0
## The airborne brake, in m/s^2, and the answer to a pilot9 who drifts. `air_momentum_decay`
## is what CARRYING speed through a jump costs - zero, deliberately. This is what it costs
## the moment he stops asking for it in the air: stick released, pushed across his travel, or
## against it. Without it a walk off a lip flew him sideways forever, so there was no way to
## drop down a shaft in a straight line (2026-09-09: *"i need pilot to be able to fall down
## long pipes in a straight line"*). At 40 m/s^2 a released sprint is gone in 0.2 s and 0.8 m,
## which reads as letting go rather than as a wall. 0.0 restores the old flying fall and is
## NOT an off switch - see the note on `momentum_brake` below, which applies to both.
##
## 200.0 by the 2026-09-10 reset (40.0 before it): a released sprint is gone in 0.04 s, which
## is the stock dead stop to within a frame or two. No drift at all, deliberately.
@export_range(0.0, 200.0, 1.0) var air_momentum_brake: float = 200.0
## The brake, in m/s^2, and the answer to a controller that feels like ice. `momentum_decay`
## above is what he pays for CARRYING speed - stick forward, going where he is already going.
## This is what he pays the moment he stops asking for it: stick released, stick pushed across
## or against his travel, or crouched. Deliberately several times the drive rate, because
## momentum is meant to reward driving into it and never to read as a loss of control - stock
## Real Controller stops dead on a released stick, and the closer this is to that, the more
## the momentum reads as a deliberate verb rather than as skating.
##
## **There is no zero here, and 0.0 is a trap.** A released stick puts `carried` above
## `target`, which enters the momentum branch of _apply_movement() whatever this is set to;
## at 0.0 _decayed_speed() then subtracts nothing and he coasts at full speed forever, on the
## ground as well as in the air. That is not stock behaviour - stock assigns the velocity
## outright and stops him dead, which is an INSTANT brake, not an absent one. So the
## reset-to-neutral value is the top of the range, not the bottom: 200.0 clears a sprint in
## 0.04 s. 60.0 was the pre-reset value, and anything in that region is the feature switched
## ON. See docs/specs/pilot9-movement-reset.md.
@export_range(0.0, 200.0, 1.0) var momentum_brake: float = 200.0
## Speed while crouched. Slower than walk_speed - the crouch clip's own cadence is what
## this is matched against, so changing one without the other makes him skate or moonwalk.
@export_range(0.1, 10.0, 0.1, "or_greater") var crouch_speed: float = 1.6
## How much of the grade the MESH lies along, heading-wise: 1.0 puts his nose down the hill
## going down and up it going up, 0.0 leaves him bolt upright as he was before 2026-09-11.
## Only the `character` child tilts - the collision capsule stays vertical, which is the whole
## trade (see docs/specs/pilot9-slope-align.md). Pairs with `slope_align_roll` below; the two
## together at 1.0 are "parallel with the slope" exactly.
@export_range(0.0, 1.0, 0.05) var slope_align_pitch: float = 1.0
## The same across his heading: 1.0 tips him downhill when the ground falls away to one side,
## which is the half of "parallel" that a pitch alone cannot reach - crossing a ramp sideways.
## 0.0 is Setsuna's shipped behaviour (`player.gd::_slope_pitch()` is pitch-only), and is the
## dial to reach for first if the hillside lean reads as skiing rather than as footing.
@export_range(0.0, 1.0, 0.05) var slope_align_roll: float = 1.0
## How fast that tilt chases a change in grade, in radians per second of blend weight. Kept
## equal to `rotation_speed` so cresting a ramp sweeps the same way a turn does rather than
## snapping. This is also the rate he levels out on leaving the ground.
@export_range(0.0, 40.0, 0.5) var slope_align_speed: float = 10.0

## Slide Settings
## -----------------------------------------------------------------------------
## The slide is `crouch` pressed at a sprint. Unlike every other move here it has no speed
## of its own: `slide_motion` IS the animation's forward travel, baked out of the clip by
## scripts/pilot9_build_scene.gd, and _apply_slide_velocity() differentiates it. That is
## what keeps his feet with the floor through the run-in and the run-out, which are the
## only two windows of the clip where a mismatch would show. See docs/specs/pilot9-slide.md.
##
## It is also HELD rather than played straight through. At `slide_hold_time` the clip and
## the curve both stop on the settled floor pose and he carries on at the speed he reached,
## for as long as the player wants: `crouch` again plays out the run-out, which stands him
## back up without giving the speed back, and `jump` leaves immediately. That is what makes a
## long slope one slide instead of a queue of 1.25 s ones. See docs/specs/pilot9-slide-hold.md
## and docs/specs/pilot9-slide-stand.md - every exit from a slide ends STANDING, never
## crouched.
##
## And it is no longer FLAT. Gravity accelerates a slide down a grade and friction bleeds
## that gain back off, so a slope is fuel rather than scenery; steep ground starts a slide by
## itself; and what a slide reached leaves with him instead of being deleted by the next
## _apply_movement(). All four dials below the baked block, plus `momentum_decay` in the
## Movement group, belong to that. See docs/specs/pilot9-slope-momentum.md.
##
## And it is no longer SLOWER THAN A SPRINT. The clip alone is about 5.2 m/s against a
## sprint's 8.0, which made the one move meant to gain ground a move that lost it, so
## `slide_entry_boost` and `slide_boost_time` put a floor under the curve: a slide opens
## above the speed he entered at and eases back down to it over two seconds. The clip, the
## hold speed and the bonus are all untouched - the floor only ever raises what they ask
## for. See docs/specs/pilot9-slide-boost.md.

@export_group("Slide")
@export var can_slide: bool = true
## The one dial worth turning. Multiplies distance without touching duration, so 1.5 is a
## longer slide *and* a faster one over the same 1.25 s. 1.0 is the clip as the builder
## trimmed it - see _trim_slide() in scripts/pilot9_build_scene.gd.
##
## The builder never writes this, so a value tuned in the inspector survives a rig swap -
## unlike the three baked properties below, which it overwrites on every sync.
@export_range(0.1, 3.0, 0.05) var slide_scale: float = 1.0
## How fast the slide plays - BOTH clocks, which is the only way this is allowed to exist.
## 2.0 is the clip at double rate: the run-in reaches the hold pose in 0.25 s instead of
## 0.50, the whole clip runs 0.625 s instead of 1.25, and every speed the curve produces
## doubles with it. The distance does not move - that is `slide_scale`, and the two compose.
##
## The clip and the distance curve are two separate clocks (see slide_duration below) and
## they agree only while they run at the SAME rate. This is that rate: scripts/
## pilot9_animation.gd writes it onto the `slide` state's TimeScale and _apply_slide_velocity
## advances _slide_time by delta * this. Anything that scales one without the other - or any
## rate that VARIES, like the crouch's eased scale - drifts the pose away from the travel
## with nothing in the log. See docs/specs/pilot9-slide-rate.md.
##
## Wall-clock tuning is deliberately NOT scaled by it: slide_boost_time, slide_cooldown,
## slide_friction and slide_slope_accel all still integrate against real time. 1.0 is the
## slide exactly as it shipped before 2026-09-11.
@export_range(0.1, 4.0, 0.05) var slide_time_scale: float = 2.0
## Kept short deliberately: without it, sprint held and `crouch` tapped re-enters the slide
## on the frame it leaves and he never stands up.
@export_range(0.0, 2.0, 0.05) var slide_cooldown: float = 0.4
## A `crouch` press made while airborne is remembered until he lands and spent the instant
## he does, so a jump into a slide only needs the press somewhere in the air - not on the
## single frame of touchdown. There is no timed window and no rise/fall gate: press `crouch`
## any time before landing. The remembered press becomes a slide only if the slide's normal
## conditions still hold on the landing frame (sprint on, stick pushed, off cooldown);
## otherwise it evaporates without toggling the crouch. `false` turns this off and an air
## press falls straight back to the crouch toggle. See docs/specs/pilot9-jump-slide.md.
@export var can_buffer_slide: bool = true
## The held slide. `false` plays the clip straight through the way it did before the hold
## existed, which is the whole of the old behaviour and is worth being able to get back to
## without a rebuild. Nothing else changes: the entry, the steering and the run-out are the
## same code either way. See docs/specs/pilot9-slide-hold.md.
@export var can_hold_slide: bool = true

## BAKED - written by scripts/pilot9_build_scene.gd::_ensure_slide_motion() from the clip
## itself. Distance travelled as a fraction of the total (Y) against time as a fraction of
## the clip (X), both 0..1. Editing these by hand is wasted work; the next sync rewrites them.
@export var slide_motion: Curve
## BAKED - the slide clip's length in SECONDS OF CLIP, not of wall clock. The state machine
## plays the clip on its own clock and this one runs in _physics_process; they agree only
## because both run at `slide_time_scale`, which is the one thing the TimeScale on the
## `slide` state is allowed to be.
@export var slide_duration: float = 0.0
## BAKED - metres the clip's Hips travel forward, the scale `slide_motion` is normalised by.
@export var slide_distance: float = 0.0
## BAKED - seconds into the clip the hold pose sits, from SLIDE_HOLD_FRAME in the builder.
## The clip's own frame 30, where he is fully down on the floor. 0.0 means no hold was baked
## (an old pilot9.tscn, or a build that refused the frame), and the slide falls back to
## playing straight through - the same thing `can_hold_slide` off does.
@export var slide_hold_time: float = 0.0

## The burst. A slide out of a sprint used to be SLOWER than the sprint - the clip travels
## slide_distance in slide_duration and that is about 5.2 m/s against a sprint's 8.0 - so the
## one move meant to get him somewhere faster cost him a third of his speed. These two put a
## FLOOR under the clip: it opens above the speed he entered at and eases back down to it.
## Neither touches the curve, the hold speed or the bonus. See docs/specs/pilot9-slide-boost.md.
##
## Multiplier on the entry speed for the floor at t = 0. At a sprint entry, 1.35 is a slide
## opening at 10.8 m/s. 1.0 is no burst at all and is where the 2026-09-10 reset parks it.
##
## Note 1.0 does NOT remove the floor, only the burst: _slide_speed_floor_at() still holds
## the slide at the speed he entered at, so a slide out of a sprint carries 7.5 m/s rather
## than falling to the clip's own ~5.2. That is the one layer in this file with no off
## switch, and it is left standing on purpose - it is also the only thing stopping the slide
## from being a brake, and the 2026-09-10 session explicitly ranked control over the clip's
## own foot placement. See docs/specs/pilot9-movement-reset.md.
@export_range(1.0, 3.0, 0.05) var slide_entry_boost: float = 1.0
## Seconds the floor takes to ease from the boost back down to the entry speed, linearly.
## Wall clock from _start_slide(), not clip time: a hold freezes the clip and the whole
## meaning of this number is that a player still down there afterwards is off the burst.
## 0.0 also turns the burst off - the floor goes flat at the entry speed immediately - and is
## the reset value; 2.0 was the pre-reset one.
@export_range(0.0, 10.0, 0.1) var slide_boost_time: float = 0.0

## Slope Settings
## -----------------------------------------------------------------------------
## The gravity term the slide never had. None of these touch the clip's own speed: they move
## `_slide_bonus`, a single scalar added on top of it, so a slide on flat ground is still the
## slide the curve describes. See docs/specs/pilot9-slope-momentum.md.

## Multiplier on the physical gravity-along-the-grade term. 1.0 is real physics - about
## 4.2 m/s^2 of horizontal gain on a 30 degree face - and 0.0 is the old flat slide, which
## is the honest off switch for this whole feature and is where the 2026-09-10 reset parks
## it. 1.0 before. With this at 0.0 the two dials under it are inert: `_slide_bonus` never
## leaves zero, so there is nothing for the friction to bleed or the ceiling to cap.
@export_range(0.0, 3.0, 0.05) var slide_slope_accel: float = 0.0
## How fast slope-gained speed bleeds off, in m/s^2. Applied to `_slide_bonus` ONLY, never
## to the clip's speed, which is what leaves the flat-ground hold the constant unending one
## docs/specs/pilot9-slide-hold.md called for: on the flat there is nothing else to decay.
@export_range(0.0, 20.0, 0.1) var slide_friction: float = 2.0
## Ceiling on a slide's total horizontal speed, clip plus bonus. About 2.7x a sprint.
@export_range(1.0, 60.0, 0.5) var slide_max_speed: float = 20.0
## Steep ground slides him whether he asked for it or not - no press, no sprint needed, and
## he cannot stand up until it flattens. `jump` still leaves.
##
## `false` by the 2026-09-10 reset. It is the clearest case in the file of the controller
## deciding a verb on the player's behalf, which is the whole of what that session was
## about, so it goes off first and has to argue its way back.
@export var can_auto_slide: bool = false
## The grade he can no longer keep his feet on, in degrees. The band this opens is bounded
## above by the body's own `floor_max_angle` (45 by default): steeper than that is not a
## floor at all and he simply falls off it.
@export_range(5.0, 60.0, 1.0) var slide_auto_angle: float = 35.0

## Climb Settings
## -----------------------------------------------------------------------------
## The ledge mantle: automatic when airborne with a ledge in probe range - no button. Two
## raycasts (fired every airborne frame) find the lip, the body is snapped so the clip's
## frame-1 hands meet it, and the whole 1.15 s is then driven by position off the baked
## curves with collision disabled. Not cancellable. See docs/specs/pilot9-climb.md.
##
## Every probe number below is a tunable starting value, not a measurement. The two that
## have to agree with each other are `climb_probe_height` and `climb_band_min`: the forward
## ray has to pass UNDER the lip it is looking for, so the ray height must stay below the
## shallowest ledge the band accepts, or the ray sails over the top of every wall in range.

@export_group("Climb")
@export var can_climb: bool = true
## Height above his feet the forward (wall) ray is cast from. Must be under
## `climb_band_min` - see the note above.
@export_range(0.1, 2.0, 0.05) var climb_probe_height: float = 0.85
## How far past himself the forward ray reaches. Grab range, measured from his centre, so
## it is spending most of itself on the capsule radius (0.34 m).
@export_range(0.1, 2.0, 0.05) var climb_probe_reach: float = 0.6
## The mantle band, in metres of lip height above his feet at the moment he presses `jump`.
## THIS is the whole filter - there is no climbable layer and no tag, so any static
## collider with an up-facing top in the band offers a mantle. Wide enough that the press
## does not have to be frame-perfect.
##
## What this band actually reaches is `peak + climb_band_max`, because the probe fires every
## airborne frame and he passes through every height on the way up and down - not just the
## apex. At the 2026-09-11 grid that is **4.9 m off a single jump and 7.9 m off a double**.
## The 3.0 m height moved the first of those a full metre: TrainingV's 4.2 m block used to
## need a double jump and is now a single-jump mantle. The 8.6 and 13.3 m blocks are out of
## reach either way and always were.
@export_range(0.2, 3.0, 0.05) var climb_band_min: float = 0.9
@export_range(0.2, 3.0, 0.05) var climb_band_max: float = 1.9
## How far off level the lip may be and still be a floor to land on, in degrees.
@export_range(0.0, 60.0, 1.0) var climb_max_lip_slope: float = 30.0
## Clearance demanded above the spot he would land on. He arrives standing, and planting
## him inside a ceiling is an uglier failure than refusing the mantle.
@export_range(0.5, 3.0, 0.1) var climb_headroom: float = 2.0

## BAKED - written by scripts/pilot9_build_scene.gd::_ensure_climb_motion() off climb_up
## itself. The clip's Hips travel as two normalised curves, time fraction in (0..1),
## distance fraction out. Y overshoots 1.0 near the top - that is the pull over the lip
## before he settles onto it, and clamping it flattens the one thing the arc is for. Z
## goes briefly NEGATIVE at the start - the swing back before the pull.
@export var climb_motion_y: Curve
@export var climb_motion_z: Curve
## BAKED - climb_up's raw (authored) length in seconds. The state machine plays the clip on
## its own clock and _climb_time runs in _physics_process; they agree because BOTH are scaled
## by `climb_speed` off real time - see that dial and docs/specs/pilot9-climb.md.
@export var climb_duration: float = 0.0
## BAKED - how much faster than authored the whole mantle plays (2.25 = two and a quarter
## times). Was 1.5 from the climb pass on 2026-09-07; raised 2026-09-11 because the pull-up
## still read as a pause in the run. At 2.25 the 1.15 s clip plays in 0.51 s.
## Applied to both clocks: the clip through the `climb` state's custom timeline (built by
## _ensure_climb_state) and the path through _apply_climb_motion advancing _climb_time by
## delta * climb_speed. Baked rather than a live dial because a value the tree was not built
## against parts the two clocks with nothing in the log.
@export var climb_speed: float = 2.25
## BAKED - metres the body rises over the mantle: the height of the frame-1 hands above the
## ground his feet stand on at the end of the clip. NOT the clip's own Hips travel, which
## is 1.89 m and describes a ledge this pose does not actually reach - see the long note on
## _ensure_climb_motion() in the builder.
@export var climb_rise: float = 0.0
## BAKED - metres the body travels forward over the mantle, front of the wall to standing.
@export var climb_reach: float = 0.0
## BAKED - metres in from the lip his feet land, taken from the clip's own forward Hips
## travel. This is the level-design contract: geometry with a top narrower than this has
## nothing to stand on.
@export var climb_inset: float = 0.0
## BAKED - where climb_up's frame-1 hand contact sits relative to his feet, in his own
## frame. The entry snap places him by subtracting this from the detected lip, which is
## what makes the hands meet the edge every time. Measured off the clip, never guessed.
@export var climb_hand_offset: Vector3 = Vector3.ZERO
## BAKED - where his ground contact sits relative to his feet on the clip's last frame,
## same frame and same job at the other end: the exit snap subtracts it from the landing
## point so his soles finish on the platform rather than through it.
@export var climb_foot_offset: Vector3 = Vector3.ZERO

## Camera Settings
## -----------------------------------------------------------------------------
## Adjust camera sensitivity and rotation limits.

@export_group("Camera")
## Mouse sensitivity for camera rotation. Higher values = faster rotation.
@export_range(0.0, 1.0, 0.001) var mouse_sensitivity: float = 0.005
## Enable controller support for camera look.
@export var controller_support: bool = true
## Controller stick sensitivity for camera rotation.
@export_range(0.1, 10.0, 0.1) var controller_sensitivity: float = 2.0
## Maximum vertical camera tilt angle in radians (prevents over-rotation).
@export_range(0.0, 1.57, 0.01) var tilt_limit: float = deg_to_rad(75)
## Speed at which the character mesh rotates to face movement direction. With
## face_travel_direction on this is the pivot dial: it is what a hard 180 costs, and the
## window during which he is still facing the old heading while already moving on the new
## one. Roughly a quarter second at 10.0.
@export_range(0.1, 50.0, 0.1) var rotation_speed: float = 10.0
## Turn the body toward wherever it is travelling instead of welding it to camera-back.
##
## This is the whole strafe seam. `true` (shipping): he always runs forward relative to
## himself, so a forward-only clip - the crouch walk, and whatever follows it - is correct
## in every direction, at the cost of RC's strafing and backing up. `false`: exactly stock
## Real Controller, camera-relative, directional clips and all.
##
## scripts/pilot9_animation.gd branches on this too, and nothing else does. An aim mode or
## a hold-to-strafe modifier is this flag and nothing more.
@export var face_travel_direction: bool = true
## Camera mode: FIRST_PERSON or THIRD_PERSON.
@export var camera_mode: CameraMode = CameraMode.THIRD_PERSON:
	set(value):
		camera_mode = value
		if is_node_ready():
			_update_camera_mode()
## Camera distance (SpringArm length) for third-person mode.
@export_range(0.0, 10.0, 0.1) var camera_distance: float = 3.5
## Speed at which the camera transitions between modes.
@export_range(1.0, 20.0, 0.1) var camera_transition_speed: float = 8.0
## Allow switching between camera modes with V key.
@export var allow_camera_mode_switch: bool = false
## Degrees added to the camera's FOV while he is sprinting. Rides on top of whatever the
## Camera3D's own `fov` is set to rather than replacing it - see `base_fov`. 0.0 is the off
## switch, and the whole feature costs one lerp a frame when it is off.
@export_range(0.0, 40.0, 0.5) var sprint_fov_boost: float = 10.0
## Speed at which the FOV eases between the base and the sprint boost. Deliberately the same
## dial and the same shipping value as camera_transition_speed above, so the lens and the
## spring arm move at a rate the player reads as one camera rather than two.
@export_range(1.0, 20.0, 0.1) var fov_transition_speed: float = 8.0
## The radius of the sphere the SpringArm3D itself sweeps - the hard backstop, and the least
## air the lens is ever allowed. A bare arm carries no shape at all and casts a hairline ray
## instead, which is what let the near plane slice through pillar edges and doorframes.
## See docs/specs/pilot9-camera-collision.md.
@export_range(0.05, 1.0, 0.01) var camera_clearance: float = 0.3
## Added to `camera_clearance` to get the radius of OUR probe, the fatter sphere in
## _camera_obstruction_length(). Fatter means it trips earlier, and that head start is the
## room the damping needs. This is the pop dial: at 0.0 the probe and the backstop agree,
## the arm's own instant clamp does all the work again, and the snap comes back.
@export_range(0.0, 1.0, 0.01) var camera_probe_lead: float = 0.35
## How fast the arm shortens when something is in the way. Toward a wall the camera has to
## win the race, so this is deliberately several times `camera_return_speed`.
@export_range(1.0, 40.0, 0.5) var camera_retract_speed: float = 16.0
## How fast it lengthens again once the way is clear. Slow on purpose: nothing needs to be
## right quickly in this direction, and the gap between the two rates is what stops a
## grazing hit-miss-hit from oscillating the shot at 60 Hz.
@export_range(0.5, 20.0, 0.1) var camera_return_speed: float = 3.0
## The floor on the damped length. Note this is a floor on OUR number, not a promise about
## the camera: the arm's own backstop may still take it under this in a corner, which is the
## safety net doing its job.
@export_range(0.0, 5.0, 0.1) var camera_min_distance: float = 0.8

## Seconds of clip the hold's speed is averaged over - see _slide_speed_at(). Long enough to
## span several of `slide_motion`'s 64 segments and short enough to still be local to the
## hold frame; the curve is smooth through there, so nothing in between is delicate.
const SLIDE_SPEED_WINDOW := 0.05

## A held slide this slow has run out of hill. Reached only by sliding UP one - the bonus
## goes negative there and eats the clip's speed - and the slide ends itself, standing, rather
## than leaving him creeping up a grade on his back. It is the one exit that does not play the
## run-out: not a dial, because there is no run-out worth playing at 1.5 m/s whatever the rest
## of the slide is tuned to, and the curve would only accelerate him forward again.
const SLIDE_STALL_SPEED := 1.5

## How far below his feet move_and_slide() may reach for the floor. Godot's default is 0.1 m,
## which one frame of a fast slide out-runs on any real grade - he leaves the surface at the
## crest and finishes the ramp in hops, each of which ends the slide. 0.5 m covers a frame at
## 20 m/s on a 45 degree face, and is the same value and the same reason as player.gd's.
const FLOOR_SNAP_LENGTH := 0.5

## Metres per second below which two speeds are the same speed. Only ever used to keep the
## momentum branch of _apply_movement() off a velocity that is already at its target.
const SPEED_EPSILON := 0.001

## A grade shallower than this reads as flat and gets no tilt on that axis. Collision meshes
## throw sub-degree normal changes across nominally flat floor, and without this he twitches
## standing still. About 3 degrees, the same value and the same reason as player.gd's
## MODEL_SLOPE_PITCH_DEADZONE. See _slope_align_angles().
const SLOPE_ALIGN_DEADZONE := deg_to_rad(3.0)

## Metres per second at or under which he counts as stopped, for the one thing that reads it:
## the sprint toggle clearing itself on a standstill. See _update_sprint_stop().
##
## Not SPEED_EPSILON (0.001), which a standable slope's residual velocity clears without him
## going anywhere - he would creep downhill at 0.05 m/s with the sprint quietly still on and
## no way to see why. 0.1 is far under a crouch's 1.6 and above that residue.
const SPRINT_STOP_SPEED := 0.1

## The camera pitch exit_vehicle() lands on - level, and the same value and intent as
## player.gd's EXIT_PITCH. He is put down at EXIA's ExitPoint looking at the machine he just
## climbed out of, and a fixed pitch keeps that framing the same however the mech's own
## camera was left. See docs/specs/pilot9-mech-mount.md and docs/specs/mech-camera-handover.md.
const EXIT_PITCH := 0.0

## How far past the wall face the down ray is cast, so it lands on the platform rather than
## on the edge itself - a ray aimed exactly at an edge is a coin toss.
const CLIMB_LIP_PROBE_INSET := 0.4
## Slack on both ends of the down ray, and the foot of the headroom ray, so a lip sitting
## exactly on a band boundary is still found and the headroom ray does not start inside the
## platform it is standing on.
const CLIMB_PROBE_MARGIN := 0.15

var input_dir: Vector2 = Vector2.ZERO
var input_strength: float = 0.0
var direction: Vector3 = Vector3.ZERO
## Sprint is a toggle, not a hold: `sprint` pressed flips this, `walk` pressed clears it, and
## so does coming to a complete stop. Flipped in _update_sprint_toggle() before anything reads
## it. `is_sprinting` below is this AND actually moving AND not crouched; this is the raw
## intent, and it survives a jump.
var sprint_toggled: bool = false
## Whether a stop is still owed a clear - set by any moving frame, spent by the frame he
## arrives at rest. The stop is an EDGE, and this is the whole of what makes it one: without
## it, standing still would be a state that ate a `sprint` press the frame after it was made.
## See _update_sprint_stop(), and docs/specs/pilot9-sprint-stop.md.
var _sprint_stop_armed: bool = false
var is_sprinting: bool = false
var is_walking: bool = false
var is_jumping: bool = false

## The speed he leaves the floor at, DERIVED from `jump_height` and `jump_time_to_apex`
## rather than dialled in. Read-only, and still called `jump_velocity` because the three
## sites that assign it to `velocity.y` - the floor jump, the air jump and the mantle exit -
## do not care where the number came from.
var jump_velocity: float:
	get: return 2.0 * jump_height / jump_time_to_apex
## Gravity while RISING, m/s^2, derived from the same two. Falling is this times
## `jump_fall_multiplier`, and both are scaled by the apex hang - see _gravity_scale().
##
## This is pilot9's own gravity and NOT the project's. get_gravity() is still what the slide
## reads in _apply_slide_bonus(), and `slide_slope_accel: 1.0` is documented against the 9.8
## it returns, so raising the project default to get a better jump would have made every
## slide 2.6x steeper and re-weighted EXIA on the way past. The cost of keeping it local is
## that pilot9 no longer honours Area3D gravity overrides; none exist in the project.
var jump_gravity: float:
	get: return 2.0 * jump_height / (jump_time_to_apex * jump_time_to_apex)

## Seconds from leaving the floor to touching it again at the SAME height, derived. This is
## the level designer's number: a gap is `jump_air_time * horizontal speed` wide, so at the
## shipping 1.2 s the three ground speeds clear 3 / 6 / 9 m and a gap in the map can be
## built to a whole metre. jump_distance() below does the multiply.
##
## The rise is `jump_time_to_apex`; the fall is that over the square root of
## `jump_fall_multiplier`, which is why a heavier fall SHORTENS every jump in the map
## rather than leaving the geometry alone. At the shipping 1.0 the two halves are equal.
##
## Two things it does NOT model, both because they are currently off and neither can be
## expressed in closed form: the apex hang (`jump_apex_speed` 0.0) lengthens the arc, and
## `jump_cut` (1.0) shortens a tapped one. Turn either on and this becomes the full-hold
## lower bound rather than the measurement - which is the trade the grid is paying for.
var jump_air_time: float:
	get: return jump_air_time_for(jump_time_to_apex, jump_fall_multiplier)

## Air jumps not yet spent this flight. Refilled to `air_jumps` on every grounded frame:
## leave the floor and the count is what it was on the last frame he touched it. `coyote_time`
## is leniency on the FLOOR jump only and never refills this - a coyote jump is the floor
## jump he was a frame late for, not a free extra one.
var _air_jumps_left: int = 0
## Seconds of coyote time left. Refilled to `coyote_time` on every grounded frame, ticked
## down while airborne, and zeroed by every jump taken. That last one is load-bearing:
## without it the grace outlives the floor jump that used it, and a second press 80 ms later
## takes a free jump that never touches `_air_jumps_left`.
var _coyote_left: float = 0.0
## Seconds a buffered `jump` press has left before it lapses. Armed only when a press is made
## airborne with no air jump to spend, and consumed on the first grounded frame. Unlike
## `_slide_buffered` this one DOES lapse - a jump remembered from the top of a long fall is
## not a jump the player is still asking for. See docs/specs/pilot9-jump-feel.md.
var _jump_buffered: float = 0.0
## Toggled by the `crouch` action, never held. Read every frame by the AnimationTree's
## advance expressions and by _apply_movement.
var is_crouching: bool = false
## True for the length of the slide clip. Read by the AnimationTree's advance expressions
## exactly like is_crouching, so the same warning applies: an expression naming a property
## that does not exist never fires and never complains.
var is_sliding: bool = false

## True for the held part of a slide - parked on the clip's hold pose, going at a constant
## speed, waiting for the player. Read by scripts/pilot9_animation.gd, which writes the
## `slide` state's TimeScale straight off it: is_slide_holding is the clip's freeze and the
## curve's freeze at once, and the two staying together is the only reason a TimeScale is
## allowed near this state at all (see _ensure_slide_state in the builder).
##
## Always false while is_sliding is false. Nothing outside _enter_slide_hold(), _end_slide()
## and the `crouch` branch of _handle_crouch_and_slide() may write it.
var is_slide_holding: bool = false

## Seconds into the slide clip - CLIP seconds, running at `slide_time_scale` x real time.
## Advanced in _apply_slide_velocity(), at the point the distance for this frame is consumed,
## so the window sampled off `slide_motion` is always the frame the motion is applied to.
## Frozen at `slide_hold_time` for the length of a hold.
var _slide_time: float = 0.0
## The speed the hold runs at, measured off the curve at the moment the hold begins and then
## held flat. Flat is still the right word: it is the CLIP's contribution to his speed, and
## the clip does not know about slopes. Everything the terrain adds rides in `_slide_bonus`
## beside it and is added at the point the velocity is written.
var _slide_hold_speed: float = 0.0
## Metres per second the SLOPE has given him, over and above whatever the clip is doing.
## Gravity along the grade adds to it, `slide_friction` bleeds it back toward zero, and it is
## reset with every slide. Sliding uphill drives it negative, which is how a slide up a hill
## slows down and eventually stalls out. The one number to watch when this is being tuned.
var _slide_bonus: float = 0.0
## Seconds since _start_slide(), the clock `slide_boost_time` is measured on. Deliberately
## NOT _slide_time: that one freezes for the length of a hold, and a burst that pauses with
## it would hand a player who holds the slide down an unending 10.8 m/s.
var _slide_elapsed: float = 0.0
## The speed the burst is measured against - his horizontal speed on the entry frame, held
## down to `sprint_speed` so a fast entry cannot compound into a faster floor. Zero for the
## automatic slide off steep ground, which starts from a standstill and is meant to.
var _slide_reference_speed: float = 0.0
## The heading the slide is travelling on, and the ONE thing his body and his mesh share
## while one is running: _steer_slide() turns it, _apply_slide_velocity() drives the body
## along it, and _handle_character_rotation() writes the mesh straight onto it. Nothing
## else may point him anywhere - two sources for a facing is what skate is made of.
var _slide_direction: Vector3 = Vector3.ZERO
var _slide_cooldown_left: float = 0.0
## A `crouch` press made in the air and not yet spent. Armed by _handle_crouch_and_slide()
## when a press would start a slide but for his feet being off the floor, and consumed on
## the first grounded frame - or dropped there, if the slide cannot start on it. Unlike the
## old timed buffer it does not lapse in the air: press `crouch` any time before landing and
## the slide is waiting for the floor. See docs/specs/pilot9-jump-slide.md.
var _slide_buffered: bool = false

## True for the length of the mantle. Read by the AnimationTree's advance expressions
## exactly like is_sliding, so the same warning applies: an expression naming a property
## that does not exist never fires and never complains. Only ever set by _start_climb(),
## which cannot run unless his feet were already off the floor.
var is_climbing: bool = false

## Seconds into climb_up. Advanced in _apply_climb_motion(), which is also the only thing
## that ends the mantle on time.
var _climb_time: float = 0.0
## The heading the mantle runs on: straight at the wall, taken from the forward ray's hit
## normal at the entry snap and never turned afterwards. The slide's _slide_direction
## discipline applies - while is_climbing this is the only thing pointing him anywhere.
var _climb_facing: Vector3 = Vector3.ZERO
## Where the entry snap put him, and the origin every sampled offset is added to.
var _climb_start_position: Vector3 = Vector3.ZERO
## Where he is hard-snapped on the exit frame: feet on the lip, climb_inset in along
## _climb_facing. Computed at entry from the same detected lip, so a frame of curve drift
## cannot leave him half in the floor.
var _climb_end_position: Vector3 = Vector3.ZERO
## The metres the curves are scaled by for THIS mantle, measured off the detected lip
## rather than taken from the bake. They come out equal to climb_rise / climb_reach while
## the entry snap is lip-relative; deriving them anyway is what keeps his feet on the
## platform if that ever stops being true.
var _climb_detected_rise: float = 0.0
var _climb_detected_reach: float = 0.0
## A `jump` pressed during the mantle. The mantle is not cancellable, so the press is held
## and spent on the first frame after the exit snap - the same courtesy the land-and-slide
## buffer gives. Dropped, not spent, if `frozen` ends the mantle.
var _climb_jump_buffered: bool = false

# Freeze the character. It may be useful when you want to pause the character.
var frozen: bool = false

## Where CameraPivot sits on him, matching its transform in scenes/pilot9.tscn (and the value
## scripts/pilot9_build_scene.gd writes there). The pivot is top_level now, so this is the whole
## of what _process() needs to place it each drawn frame.
const CAMERA_PIVOT_OFFSET := Vector3(0.0, 1.5, 0.0)

var target_camera_distance: float = 3.5
var is_transitioning_camera: bool = false
## The length the camera MODE wants, with the walls not consulted - what spring_length used
## to be back when nothing but _update_camera_mode() ever wrote it. It is kept separately
## now because walls write the real spring_length, and the character mesh's visibility reads
## THIS one: keying visibility off the wall-aware length would blink his body out every time
## a wall squeezed the camera in, which is a new glitch traded for an old one.
var _camera_mode_length: float = 3.5
## The probe cast every frame by _camera_obstruction_length(), built once in
## _setup_camera_collision() rather than per frame - it is the same query with a new origin.
var _camera_probe: PhysicsShapeQueryParameters3D = null
## The FOV with no sprint boost on it, read off the rig's camera at _ready() rather than
## declared here. _handle_camera_fov() writes camera_3d.fov every frame, so a constant in
## this file would silently clobber whatever the Camera3D is tuned to in the editor and give
## no sign it had. Capturing it means the boost rides on top of the tuned value instead.
var base_fov: float = 75.0

## `jump_air_time` and jump_distance() below, taking their inputs as arguments instead of
## reading them off `self`. They are the bodies of both, and both delegate here, so there is
## still exactly one copy of each formula.
##
## They are STATIC for the editor's sake. scripts/jump_grid.gd generates its ruler from a
## throwaway pilot9 in the editor viewport, and the editor will not instantiate a non-@tool
## script: what it hands back is a PLACEHOLDER instance, which carries the exported
## properties and nothing else. A method call on one fails outright - which is precisely how
## the platform came to generate nothing in the editor while working in game. A static is
## called on the script rather than on an instance, so it runs in both, and the grid can
## derive its gaps from `jump_time_to_apex` and `jump_fall_multiplier`, which ARE exports.
static func jump_air_time_for(time_to_apex: float, fall_multiplier: float) -> float:
	return time_to_apex * (1.0 + 1.0 / sqrt(fall_multiplier))


static func jump_distance_for(
		horizontal_speed: float, time_to_apex: float, fall_multiplier: float) -> float:
	return horizontal_speed * jump_air_time_for(time_to_apex, fall_multiplier)


## How wide a flat-to-flat gap he clears at `horizontal_speed`, in metres. Defaults to a
## run. Air control is not modelled - this is the distance for a jump taken at speed and
## held straight, which is the one a gap should be measured against.
func jump_distance(horizontal_speed: float = speed) -> float:
	return jump_distance_for(horizontal_speed, jump_time_to_apex, jump_fall_multiplier)


func _ready() -> void:
	# Set here rather than on the scene so it cannot be lost to a rebuild of pilot9.tscn, and
	# so the reason for it sits next to the number. See FLOOR_SNAP_LENGTH.
	floor_snap_length = FLOOR_SNAP_LENGTH
	base_fov = camera_3d.fov
	# Must come after the line above, or Settings.fov is overwritten by the
	# authored 75 on every spawn - the settings row would work in the menu and
	# do nothing in the world. See docs/specs/settings.md, One Ordering Trap.
	base_fov = Settings.fov
	target_camera_distance = 0.0 if camera_mode == CameraMode.FIRST_PERSON else camera_distance
	_camera_mode_length = target_camera_distance
	spring_arm.spring_length = target_camera_distance
	_setup_camera_collision()
	if character:
		character.visible = camera_mode == CameraMode.THIRD_PERSON

func _physics_process(delta: float) -> void:
	# First, and above every early return below, for the reason in its own docstring: the
	# frames a mantle or a freeze bails out on are exactly the frames the FOV has to be
	# easing back on.
	_handle_camera_fov(delta)
	_update_sprint_toggle()
	# Freezing mid-mantle ends it rather than pausing it, for the reason the slide ends
	# itself: nothing advances _climb_time while frozen, and he would be left hanging in
	# the air with his collision shape switched off. Landing him on top is the safe stop.
	if frozen and is_climbing:
		_end_climb(false)
	_handle_crouch_and_slide(delta)
	_handle_gravity_and_jump(delta)
	_handle_camera_transition(delta)
	_handle_controller_camera(delta)

	# Three ways through, and the tail below runs on all of them - which is why these are an
	# if/elif chain and no longer two early returns. See _align_model_to_slope().
	#
	# A mantle owns his position outright. move_and_slide() is deliberately NOT called
	# these frames - his collision shape is off and he is being written along a path over
	# an edge, so a velocity step would only fight the curve.
	if is_climbing:
		_apply_climb_motion(delta)
	elif frozen:
		handle_frozen_movement()
		move_and_slide()
	else:
		_handle_movement_input()
		# Before the rotation, and outside its THIRD_PERSON gate: the heading is what steers
		# the body, so it has to turn even in a camera mode where nothing is drawing the mesh.
		if is_sliding:
			_steer_slide(delta)
		if camera_mode == CameraMode.THIRD_PERSON:
			_handle_character_rotation(delta)
		# A slide owns his velocity outright: the curve says how fast, the steered heading
		# says where, and the stick reaches it only through that heading.
		if is_sliding:
			_apply_slide_velocity(delta)
		else:
			_apply_movement(delta)
		move_and_slide()

	# Last, and after move_and_slide() on the branches that call it: get_floor_normal() is
	# that call's output, so a tilt taken any earlier is lying about last frame's grade.
	_align_model_to_slope(delta)

func handle_frozen_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	input_dir = Vector2.ZERO
	is_sprinting = false
	is_walking = false

## Sprint toggles rather than being held: `sprint` (Shift / right trigger) flips it, `walk`
## (Alt) clears it, and a complete stop clears it. A toggle means letting go of the button
## mid-jump does not silently drop him out of a run - the intent carries through the air, so a
## jump buffered into a slide still reads the sprint it started with, and the player is not
## punished for an accidental release. Called before _handle_crouch_and_slide() so the slide
## checks see this frame's value.
##
## Frozen the press is ignored: handle_frozen_movement() forces the effective is_sprinting
## false anyway, and the toggle should come back untouched after a pause. The freeze also
## DISARMS the stop, and has to - the freeze zeroes both `velocity` and `input_dir`, so the
## first unfrozen frame is indistinguishable from a standstill and would otherwise spend the
## clear on a pause. A pause is not a stop.
##
## The stop is checked ABOVE the press so that a press landing on the same frame wins. That is
## the standing-still-then-pressing case, and it is the only reason the two are this way round.
func _update_sprint_toggle() -> void:
	if frozen:
		_sprint_stop_armed = false
		return
	_update_sprint_stop(is_on_floor())
	if Input.is_action_just_pressed("sprint"):
		sprint_toggled = not sprint_toggled
	elif Input.is_action_just_pressed("walk"):
		sprint_toggled = false

## Clears the sprint intent on the frame he arrives at rest. See
## docs/specs/pilot9-sprint-stop.md.
##
## A complete stop is on the floor, at rest, and not asking to move. All three matter:
##
## - **On the floor**, because a pilot9 in the air has not stopped, he is between things. An
##   airborne clear would fight the very thing the toggle exists for - `air_momentum_brake`
##   walks a stickless fall down to a straight vertical drop, and that is a fall, not a halt.
## - **At rest**, at SPRINT_STOP_SPEED rather than exactly zero.
## - **Stick centred**, because the stick is the player's request. Pinned head-on against a
##   wall at 0 m/s with the stick buried he is still ASKING to run - the wall stopped him, he
##   did not stop - so the sprint survives and is there again the moment he turns away.
##
## An edge, not a state: `_sprint_stop_armed` is set by every frame that is not a stop and
## spent by the first that is. Tested as a state this would eat a `sprint` press made while
## standing still, which is the commonest way a player starts a run.
##
## `on_floor` is passed rather than read so a test can drive this without a tree, where
## is_on_floor() is false and unfakeable. _update_sprint_toggle() is its only caller.
##
## `velocity` and `input_dir` are both LAST frame's here - this runs at the top of
## _physics_process(), before _handle_movement_input(). That is right rather than merely
## tolerable: the stop worth reacting to is the one move_and_slide() actually produced, not
## one predicted from a stick that has not been applied yet.
func _update_sprint_stop(on_floor: bool) -> void:
	if not (on_floor and input_dir == Vector2.ZERO and _horizontal_speed() <= SPRINT_STOP_SPEED):
		_sprint_stop_armed = true
		return
	if _sprint_stop_armed:
		_sprint_stop_armed = false
		sprint_toggled = false

## The `crouch` press, and the one place it is spent. Pressed at a sprint it starts a slide;
## pressed during a held one it leaves the hold; pressed at any other time it toggles the
## crouch. Never two of those - a single decision point is what keeps a slide from also
## leaving him crouched when it ends. See docs/specs/pilot9-slide-stand.md.
##
## Read here rather than in _input so it lands on the same frame as every other movement
## input; the AnimationTree samples is_crouching and is_sliding after this.
func _handle_crouch_and_slide(delta: float) -> void:
	_slide_cooldown_left = maxf(_slide_cooldown_left - delta, 0.0)

	if frozen:
		# Freezing mid-slide has to end it, not pause it: nothing advances _slide_time
		# while frozen, so the clip would play on against a clock that stopped. A queued
		# air press goes with it - a stale slide firing on the frame he unfreezes is not
		# what was asked for.
		_end_slide()
		_slide_buffered = false
		return

	# The mantle holds the whole body for its length, and `crouch` means nothing during
	# one. Returning here rather than earlier keeps the cooldown ticking, so a slide
	# cancelled into a mantle still waits out its full delay after he stands up.
	if is_climbing:
		return

	if is_sliding:
		if not is_on_floor():
			_end_slide()          # off a ledge mid-slide; `fall` takes it from here
		elif is_slide_holding:
			# The one press the slide does not swallow, and it RESUMES the clip rather than
			# ending it: the run-out (frames 30-75) is his stand-up, so it is played, and the
			# slide ends standing on the `_slide_time >= slide_duration` branch below once it
			# finishes. Nothing sets is_crouching - a slide never hands off into a crouch,
			# because crouch_speed is 1.6 m/s and that deletes everything the slide earned.
			# See docs/specs/pilot9-slide-stand.md.
			#
			# `jump` is not read here. It ends the slide in _handle_gravity_and_jump(), which
			# runs after this, so a jump out of a hold - or out of the run-out - cuts to the
			# leap. It is the one exit that skips the stand-up.
			#
			# Both stand-up exits are refused on ground too steep to stand on. Allowing
			# either there would only end a slide the auto-slide restarts on the next frame,
			# which is a clip playing its entry over and over rather than a stand-up. `jump`
			# still works - it is the one exit never taken away.
			if _on_auto_slide_slope():
				# Steered up a face he cannot stand on and run out of speed doing it. He
				# does not stop there - he slips back down, which is the same thing the
				# automatic slide says about this ground. Ending instead would only restart
				# a slide one frame later, and holding him would trap him: with both
				# standing exits refused, `jump` would be his only way off the face.
				#
				# The bonus goes with the heading. It is deeply negative by the time this
				# fires (that is what stopped him), and carrying it into a downhill run
				# would spend the first second of the descent paying it off.
				if _horizontal_speed() < SLIDE_STALL_SPEED:
					_slide_direction = _downhill(get_floor_normal())
					_slide_bonus = 0.0
			else:
				if Input.is_action_just_pressed("crouch"):
					# Resume, not end. The clock picks up from `slide_hold_time` and the
					# run-out plays him back up to standing at the clip's own ~5 m/s plus
					# whatever the grade earned, which is the whole point of leaving this
					# way rather than cutting.
					is_slide_holding = false
				elif _horizontal_speed() < SLIDE_STALL_SPEED:
					# Out of hill. See SLIDE_STALL_SPEED - only reachable going up one, and
					# the one stand-up that does NOT play the run-out: the run-out is driven
					# off the curve and would accelerate him back to ~5 m/s, which is the
					# one thing running out of hill must not do.
					_end_slide()
		elif _slide_time >= slide_duration:
			# The clip has played through, run-out and all - either because the hold was
			# left by the `crouch` press above, or because there was no hold to leave
			# (can_hold_slide false, or a rig that baked no slide_hold_time). He is standing
			# at the end of the run-out; `slide -> Locomotion` takes it from here.
			_end_slide()
		return                    # otherwise the slide holds the crouch key for its length

	# Steep ground takes his feet out from under him, with no press and no sprint. Ahead of
	# both the buffered press and the fresh one, because it is not a decision the player is
	# making: whatever `crouch` was going to mean this frame, he is sliding.
	#
	# The cooldown is deliberately not consulted. It exists to stop a player re-entering a
	# slide on the frame one ends; refusing this one would leave him standing for 0.4 s on a
	# face he is supposed to be unable to stand on.
	if _should_auto_slide():
		_slide_buffered = false
		_start_slide(_downhill(get_floor_normal()), true)
		return

	# A `crouch` press made in the air (see _should_buffer_slide) waits here for the ground.
	# Spent BEFORE the just-pressed check below, so one press is never read twice - and a
	# landing where the slide cannot start (sprint toggled off, stick centred, still on
	# cooldown) just drops the press rather than falling through to a crouch.
	if _slide_buffered and is_on_floor():
		_slide_buffered = false
		var buffered := _travel_direction(Input.get_vector("left", "right", "forward", "backward"))
		if _can_start_slide(buffered):
			_start_slide(buffered)
		return

	if not Input.is_action_just_pressed("crouch"):
		return

	# Fresh rather than last frame's `direction`: _handle_movement_input has not run yet
	# this frame, and this is the last look at the stick before _can_start_slide() decides -
	# a frame of lag in it is a frame of lag on the whole slide.
	var heading := _travel_direction(Input.get_vector("left", "right", "forward", "backward"))
	if _can_start_slide(heading):
		_start_slide(heading)
	elif _should_buffer_slide():
		# Sprinting into a slide, feet not yet on the floor - the one thing _can_start_slide()
		# failed on. Remember the press and spend it the instant he lands.
		_slide_buffered = true
	else:
		is_crouching = not is_crouching

## Sprinting, moving, on the ground, and NOT already crouched. The clip opens at 8 m/s with
## his feet planted, so anything slower than a sprint would start it with a lurch.
##
## `not is_crouching` outlives the crouch hand-off it was written for
## (docs/specs/pilot9-slide-crouch.md, reversed by pilot9-slide-stand.md) because it is
## independently right: out of a 1.6 m/s crouch the clip's 8 m/s opening is a lurch, and
## crouched the press means stand up - it falls through to the toggle at the bottom of
## _handle_crouch_and_slide().
func _can_start_slide(heading: Vector3) -> bool:
	return can_slide \
		and slide_motion != null \
		and slide_duration > 0.0 \
		and _slide_cooldown_left <= 0.0 \
		and is_on_floor() \
		and not is_crouching \
		and heading != Vector3.ZERO \
		and sprint_toggled \
		and not Input.is_action_pressed("walk")

## The airborne half of _can_start_slide(): every slide condition except the one a jump makes
## briefly false - his feet on the floor. A `crouch` press that meets these is a slide the
## player is asking for while still in the air, so it is remembered rather than spent as a
## crouch toggle, and stays remembered until he lands. No rise/fall gate and no timer: press
## `crouch` any time before touchdown. Sprint being a toggle is what makes this safe - the
## press means "slide" because the sprint it needs cannot have been let go by accident. See
## docs/specs/pilot9-jump-slide.md.
func _should_buffer_slide() -> bool:
	return can_slide \
		and can_buffer_slide \
		and slide_motion != null \
		and slide_duration > 0.0 \
		and _slide_cooldown_left <= 0.0 \
		and not is_on_floor() \
		and not is_crouching \
		and sprint_toggled \
		and not Input.is_action_pressed("walk") \
		and Input.get_vector("left", "right", "forward", "backward") != Vector2.ZERO


## `heading` is normally an intention - the stick's, or his facing - and is taken as a
## suggestion. `forced` makes it the heading outright, and exists for the automatic slide,
## whose whole meaning is that he is going down the fall line rather than wherever he was
## pointed when the ground gave way.
func _start_slide(heading: Vector3, forced: bool = false) -> void:
	is_sliding = true
	is_slide_holding = false
	_slide_time = 0.0
	_slide_hold_speed = 0.0
	# The burst is measured off the speed he arrives with, read here because this runs
	# before _apply_movement() and `velocity` is still last frame's - which for a sprinting
	# entry is a sprint, and for the automatic slide off steep ground is nearly nothing.
	# See docs/specs/pilot9-slide-boost.md.
	_slide_elapsed = 0.0
	_slide_reference_speed = minf(_horizontal_speed(), sprint_speed)
	# Nothing carries between slides. Cleared here as well as in _end_slide() so a slide
	# started on top of one that ended some other way still opens on the clip's own speed.
	_slide_bonus = 0.0
	# Where he is visibly pointing, not where the stick is pushing. Entering mid-turn the two
	# differ, and since the mesh is about to be welded to this heading, taking the stick's
	# would snap his body round on the entry frame. The stick is only the fallback for first
	# person, where nothing has been driving character.rotation.
	if forced:
		_slide_direction = heading
	else:
		_slide_direction = _facing() if camera_mode == CameraMode.THIRD_PERSON else heading
	# A slide is not a crouch: clear it on entry, and nothing on the slide path ever sets it
	# again. Every exit - the run-out, the stall, a jump, a ledge, a freeze - leaves him
	# standing. See docs/specs/pilot9-slide-stand.md.
	is_crouching = false

## Turns the slide. The player steers one exactly as he steers a run - same stick, same
## rotation_speed, same lerp - which is the whole of the change: a slide that cannot be
## aimed is a 1.25 s commitment the player makes blind, and every miss reads as the controls
## having been taken away rather than as a bad call.
##
## Deliberately a lerp on the HEADING rather than on the mesh. _handle_character_rotation()
## then writes the mesh onto the result instead of chasing it with a second lerp: one lerp
## end to end, so a slide turns at the speed a run turns at and not at half of it, and the
## body can never be pointing somewhere the mesh is not.
##
## Stick released, the heading holds - a slide with no input carries straight on, which is
## also what keeps the run-out from swinging when the player lets go early.
func _steer_slide(delta: float) -> void:
	if input_dir == Vector2.ZERO or direction == Vector3.ZERO:
		return
	var turned := lerp_angle(
		atan2(_slide_direction.x, _slide_direction.z),
		atan2(direction.x, direction.z),
		rotation_speed * delta)
	_slide_direction = Vector3(sin(turned), 0.0, cos(turned))

## The world direction the mesh is facing. The inverse of the rotation target computed in
## _handle_character_rotation(), and correct for the same reason: the 180 degree basis that
## turns pilot9 the right way round lives on the `character` node's own transform, so its
## rotation.y and a travel direction are already in the same frame.
func _facing() -> Vector3:
	return Vector3(sin(character.rotation.y), 0.0, cos(character.rotation.y))

## Also the cooldown's only writer - a slide cancelled by a jump has to wait out the same
## delay as one that ran to the end, or landing straight back into another is free.
func _end_slide() -> void:
	if not is_sliding:
		return
	is_sliding = false
	# Cleared here and not only where the hold is left, because the two other ways out of a
	# hold - a jump, and sliding off a ledge - both come through this function and neither
	# passes through the `crouch` branch. A stale true would leave the next slide's clip
	# frozen on frame 0 for as long as the entry lasts.
	is_slide_holding = false
	_slide_time = 0.0
	_slide_hold_speed = 0.0
	# The burst goes with the slide. The speed it reached does not - it is in `velocity`,
	# and _apply_movement() decays it from there like any other over-sprint.
	_slide_elapsed = 0.0
	_slide_reference_speed = 0.0
	# The bonus goes; the SPEED does not. `velocity` is left exactly as the last slide frame
	# wrote it, and _apply_movement() now decays it instead of assigning over it - that is
	# the whole of "the slope's speed leaves with him". See _apply_movement().
	_slide_bonus = 0.0
	_slide_cooldown_left = slide_cooldown

## The hold begins. Called from _apply_slide_velocity() on the frame _slide_time reaches
## `slide_hold_time`, which is also the frame that clamps it there.
##
## The speed is measured rather than declared: whatever the clip was doing over the window
## just before the hold frame is what he carries on at, so the transition into the hold is
## continuous by construction and there is no number here to tune against the animation.
func _enter_slide_hold() -> void:
	is_slide_holding = true
	_slide_hold_speed = _slide_speed_at(slide_hold_time)

## -- what the AnimationTree reads ---------------------------------------------
##
## Two accessors rather than two exported flags, for the same reason is_sliding is a plain
## var and `_slide_time` is not: these are the state machine's view of the slide, and the
## state machine is allowed to know only what it needs to stay in step with the controller.
## Both are read from scripts/pilot9_animation.gd and from advance expressions in
## scenes/pilot9.tscn; nothing writes through them.

## The slide clip's clock, in CLIP seconds. pilot9_animation.gd seeks the `slide` state onto
## this whenever the state starts late, which is the only thing keeping the frozen hold pose
## on the frame it was baked for - see _drive_slide() there and
## docs/specs/pilot9-jump-slide.md.
func slide_clip_time() -> float:
	return _slide_time

## True while an air `crouch` press is waiting for the ground. The `fall -> jump_land` and
## `jump -> jump_land` transitions yield to it: a landing that is about to become a slide
## must not start a 0.2 s fade into the landing clip first, because a fade in progress blocks
## every other transition for its whole length - `jump_land -> slide` included. See
## _ensure_slide_state() in scripts/pilot9_build_scene.gd.
func slide_pending() -> bool:
	return _slide_buffered

## The clip's own forward speed at `t` seconds in, in m/s, taken as the average across the
## SLIDE_SPEED_WINDOW ending there.
##
## A window rather than a two-sample derivative on purpose. `slide_motion` is 64 linear
## segments, so a derivative taken across less than one segment reads that segment's slope
## alone and steps as the sample point crosses a knot; 50 ms spans several and comes out
## smooth. A fixed window also makes the answer frame-rate independent, which matters here -
## unlike _apply_slide_velocity's per-frame difference, this one number is then held for an
## unbounded time and any error in it never washes out.
func _slide_speed_at(t: float) -> float:
	if slide_motion == null or slide_duration <= 0.0:
		return 0.0
	var window := minf(SLIDE_SPEED_WINDOW, t)
	if window <= 0.0:
		return 0.0
	var travelled := slide_motion.sample(t / slide_duration) \
		- slide_motion.sample((t - window) / slide_duration)
	# `window` is clip seconds and the answer is metres per REAL second, so the rate the clip
	# is being played at belongs in it - the hold carries this number for an unbounded time
	# and a speed measured in the wrong clock never washes out.
	return travelled * slide_distance * slide_scale * slide_time_scale / window

## The burst, in m/s, for this frame of this slide.
func _slide_speed_floor() -> float:
	return _slide_speed_floor_at(_slide_reference_speed, slide_entry_boost,
		slide_boost_time, _slide_elapsed)

## The floor's shape: `reference * boost` at entry, easing linearly to `reference` over
## `boost_time` and flat there forever after.
##
## Linear rather than eased on purpose. The player is meant to be able to feel where in the
## burst they are and to spend it deliberately; an exponential tail has no moment where it
## is over, and "still sliding after two seconds" then means nothing.
##
## A reference of zero returns zero rather than a boost of nothing, which is the automatic
## slide off steep ground: it starts from a standstill and gravity is the only thing
## entitled to speed it up. A slide may PRESERVE momentum and front-load it. It may not
## invent it.
static func _slide_speed_floor_at(reference: float, boost: float, boost_time: float,
		elapsed: float) -> float:
	if reference <= 0.0:
		return 0.0
	if boost_time <= 0.0:
		return reference
	var opened := reference * maxf(boost, 1.0)
	return lerpf(opened, reference, clampf(elapsed / boost_time, 0.0, 1.0))

## -- slopes -------------------------------------------------------------------
##
## The gravity term. Every piece of arithmetic here is a static function taking a floor
## normal, for one reason worth stating up front: is_on_floor() cannot be made true without a
## physics world, so a headless test can never reach this code through _physics_process. Pure
## functions are the only way any of it gets tested. See docs/specs/pilot9-slope-momentum.md
## and tests/test_pilot9_slope_momentum.gd.

## The downhill direction of a floor, flattened, unit length - and ZERO for level ground.
##
## It is the horizontal part of the normal, unchanged. A floor's normal leans DOWNHILL as it
## tilts (a plane descending toward +Z has normal (0, cos, sin)), which is the same fact
## player.gd::_slope_pitch() is built on and the one thing in this file worth checking by
## hand if a sign ever looks wrong.
static func _downhill(floor_normal: Vector3) -> Vector3:
	var flat := Vector3(floor_normal.x, 0.0, floor_normal.z)
	return Vector3.ZERO if flat.length() <= 0.0001 else flat.normalized()

## Horizontal acceleration, m/s^2, that gravity applies to something sliding along `heading`
## on a floor of this normal. Positive downhill, negative up, zero across.
##
## `gravity * sin` is the acceleration along the surface; the second `cos` (which is the
## normal's own y) projects it back onto the horizontal plane, because the slide's speed - and
## everything else in this controller - is bookkept as a horizontal quantity and left to
## move_and_slide() to lay along the floor.
##
## The dot product is what makes the stick matter: a slide steered across the fall line takes
## a fraction of the gain, and one steered up it pays.
static func _slope_accel(heading: Vector3, floor_normal: Vector3, gravity: float,
		scale: float) -> float:
	if heading.length() <= 0.0001 or floor_normal.length() <= 0.0001:
		return 0.0
	var n := floor_normal.normalized()
	var downhill := _downhill(n)
	if downhill == Vector3.ZERO:
		return 0.0
	var sin_t := Vector3(n.x, 0.0, n.z).length()
	return gravity * sin_t * n.y * heading.normalized().dot(downhill) * scale

## One frame of the bonus: gravity in, friction out.
##
## Friction is applied toward zero from whichever side the bonus is on and clamped AT zero
## rather than allowed through it, so a slide standing still on flat ground stays at the
## clip's speed instead of being dragged backwards by its own friction term.
static func _stepped_bonus(bonus: float, accel: float, friction: float, delta: float) -> float:
	var next := bonus + accel * delta
	var bleed := absf(friction) * delta
	if next > 0.0:
		return maxf(next - bleed, 0.0)
	if next < 0.0:
		return minf(next + bleed, 0.0)
	return 0.0

## The clip's speed plus the terrain's, held between a standstill and the ceiling. Negative
## is clamped rather than allowed to reverse him: a slide that has run out of speed going
## uphill stalls out (see SLIDE_STALL_SPEED), it does not start sliding back down facing
## forwards.
static func _capped_slide_speed(base: float, bonus: float, max_speed: float) -> float:
	return clampf(base + bonus, 0.0, max_speed)

## Ground he cannot keep his feet on. False for a zero normal, which is what get_floor_normal()
## returns when he is not on a floor at all.
static func _is_auto_slide_slope(floor_normal: Vector3, angle_deg: float) -> bool:
	if floor_normal.length() <= 0.0001:
		return false
	return floor_normal.normalized().y < cos(deg_to_rad(angle_deg))

## Momentum's one line: over-speed falls toward the target at `decay` m/s^2 and stops there,
## never through it. At or under the target the speed is returned untouched - the caller's
## stock path owns that case.
static func _decayed_speed(current: float, target: float, decay: float, delta: float) -> float:
	if current <= target:
		return current
	return maxf(current - absf(decay) * delta, target)

## How hard momentum is bled this frame, from how much the stick agrees with where he is
## already travelling. `agreement` is that dot product: 1 driving straight into his own
## momentum, 0 across it, -1 against it - and -1 is also what "no stick at all" and "crouched"
## are passed as, because both mean he has stopped asking for the speed.
##
## Only the agreeing half is interpolated. Everything from sideways round to fully against
## brakes at the same full rate rather than on a curve through it: the player pushing across
## his own travel is asking to stop going that way, and a graded answer to that is exactly
## the vagueness that reads as ice.
static func _momentum_rate(agreement: float, drive: float, brake: float) -> float:
	return lerpf(brake, drive, clampf(agreement, 0.0, 1.0))

## Whether the floor he is standing on right now is one of those. Not static - the two
## questions it folds together (is he on a floor, and is that floor steep) are both live
## state, and every caller wants them together.
func _on_auto_slide_slope() -> bool:
	return can_auto_slide and is_on_floor() \
		and _is_auto_slide_slope(get_floor_normal(), slide_auto_angle)

## The pitch and roll, in radians, that lay the MESH along the grade it is standing on -
## `(rotation.x, rotation.z)` for the `character` node, whose `rotation.y` is already the
## heading `yaw`. Zero on flat ground, inside the deadzone, and for the zero normal
## get_floor_normal() hands back with nothing underfoot.
##
## Rotate the normal back through the heading and it is expressed in his own frame, where
## Godot's default Euler YXZ order (`R = Ry * Rx * Rz`) puts local +Y at
##
##     n_body = (-sin(roll), cos(roll) * cos(pitch), cos(roll) * sin(pitch))
##
## which inverts exactly, with no small-angle fudge: at weight 1.0 the basis these two build
## maps +Y onto the floor normal. That YXZ order is also why this can be written onto
## rotation.x and rotation.z without touching the heading - the yaw is applied outermost, so
## _handle_character_rotation(), the slide's welded facing and the mantle's snap all keep
## meaning exactly what they meant.
##
## Signs, which are the only part of this worth checking by hand - a flip leans him INTO the
## hill, which reads as a broken clip rather than as a wrong sign:
##   - A floor's normal leans downhill (see _downhill), so heading down a grade puts n_body.z
##     positive, and positive rotation.x is nose-down. Same convention as player.gd.
##   - `character`'s local +X points to his LEFT (the 180 degree basis on the node - see
##     pilot9_animation.gd::_travel_blend), so ground falling away to his left gives a
##     negative roll, which tips his head to the left. Downhill, as it should be.
##
## Static and fully parameterised for the reason every other slope function here is: without a
## physics world there is no floor to stand him on, so this is the only form the arithmetic
## can be tested in. See docs/specs/pilot9-slope-align.md.
##
## `deadzone` is a parameter with the shipping value as its default for one reason: it is the
## only part of this that is NOT exact, so the round-trip test turns it off to assert the
## alignment itself, and a separate test pins the default. Nothing in the game passes it.
static func _slope_align_angles(yaw: float, floor_normal: Vector3, pitch_weight: float,
		roll_weight: float, deadzone: float = SLOPE_ALIGN_DEADZONE) -> Vector2:
	if floor_normal.length() <= 0.0001:
		return Vector2.ZERO
	var body := floor_normal.normalized().rotated(Vector3.UP, -yaw)
	var pitch := atan2(body.z, body.y)
	var roll := asin(clampf(-body.x, -1.0, 1.0))
	if absf(pitch) < deadzone:
		pitch = 0.0
	if absf(roll) < deadzone:
		roll = 0.0
	return Vector2(pitch * pitch_weight, roll * roll_weight)

## Tips the mesh along the grade so a ramp reads as ground he is standing on rather than one
## he is skating across. Only the `character` child moves - the capsule that does the
## colliding stays vertical - and it eases toward the target rather than snapping, so cresting
## a ramp sweeps like a turn.
##
## Levelled out the moment he is airborne or mantling, on the same ease: an airborne body has
## no grade to lie along, get_floor_normal() is stale once is_on_floor() goes false, and a
## mantle is a scripted path over an edge that already owns his pose.
func _align_model_to_slope(delta: float) -> void:
	var target := Vector2.ZERO
	if is_on_floor() and not is_climbing:
		target = _slope_align_angles(character.rotation.y, get_floor_normal(),
			slope_align_pitch, slope_align_roll)
	var step := slope_align_speed * delta
	character.rotation.x = lerp_angle(character.rotation.x, target.x, step)
	character.rotation.z = lerp_angle(character.rotation.z, target.y, step)

## The automatic slide's entry test. The slide's own preconditions (it is enabled, the clip
## was baked) still apply - without a curve there is nothing to drive him with - but the
## player-facing ones do NOT: no sprint, no stick, no cooldown, and a crouch is overridden
## rather than respected. He is not choosing this.
func _should_auto_slide() -> bool:
	return can_slide \
		and slide_motion != null \
		and slide_duration > 0.0 \
		and not is_sliding \
		and not is_climbing \
		and _on_auto_slide_slope()

## His horizontal speed, which is the only part of `velocity` momentum and the stall are
## about. The vertical is gravity's and move_and_slide()'s business.
func _horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

## What `jump_gravity` is multiplied by for one frame, given his vertical speed.
##
## Two rules in one number. Rising is 1.0 and falling is `fall_mult`, because the descent is
## where float is actually felt - a rise reads as commitment, a slow fall reads as swimming,
## and asymmetric gravity is what nearly every platformer does about it. Then either one is
## relaxed by `apex_scale` within `apex_speed` of the top, which sounds like it would add
## float and does the opposite: the airtime it buys back is spent at the one part of the arc
## the player is aiming from.
##
## Static and fully parameterised for the reason `_slope_accel()` is - the whole rule is then
## reachable from a `--script` run with no tree and no Input. `apex_scale: 1.0` or
## `apex_speed: 0.0` switches the hang off and leaves plain asymmetric gravity.
static func _gravity_scale(vy: float, fall_mult: float, apex_speed: float,
		apex_scale: float) -> float:
	var scale := 1.0 if vy > 0.0 else fall_mult
	if absf(vy) < apex_speed:
		scale *= apex_scale
	return scale

## The jump cut, and the reason a tap is a hop: rising with `jump` let go clamps his upward
## speed to `cut_speed`. Everything below that, and everything on the way down, is left alone.
##
## A **state** test on the button rather than an edge, deliberately. `is_action_just_released()`
## would be lost whenever a press and its release land inside one physics frame - a real tap at
## 60 Hz - and would make the answer depend on whether this ran before or after the press
## handling. Asking "is it held" every airborne frame cannot be defeated by either.
static func _cut_rise(vy: float, held: bool, cut_speed: float) -> float:
	if held or vy <= cut_speed:
		return vy
	return cut_speed

## Handles gravity application, the jump, the air jump and the mantle trigger.
##
## The mantle is automatic: every airborne frame the ledge probe runs, and a qualifying lip
## in range starts it with no input. Checked BEFORE the jump-press handling so a `jump`
## pressed on the frame a mantle begins is buffered for the exit (by the is_climbing branch
## next frame) rather than spent as an air jump.
##
## Gravity here is pilot9's own `jump_gravity`, NOT get_gravity(). See that property for why.
func _handle_gravity_and_jump(delta: float) -> void:
	if is_climbing:
		# Not cancellable - collision is off and he is on a scripted path over an edge, so
		# there is no safe point to release him. The press is held for the exit instead.
		if not frozen and Input.is_action_just_pressed("jump"):
			_climb_jump_buffered = true
		return

	# A freeze is not a moment the player is still mid-jump through, so both graces are
	# dropped on the way past - the same argument `_slide_buffered` gets in
	# _handle_crouch_and_slide(). A stale press firing on the frame he unfreezes is not
	# something anyone asked for. Everything below leans on this: it is the only reason the
	# buffered-jump branch does not need its own `frozen` test.
	if frozen:
		_coyote_left = 0.0
		_jump_buffered = 0.0

	if not is_on_floor():
		var scale := _gravity_scale(velocity.y, jump_fall_multiplier, jump_apex_speed,
			jump_apex_scale)
		velocity.y = maxf(velocity.y - jump_gravity * scale * delta, -max_fall_speed)
		# `frozen` counts as held: nothing should be cut during a pause, and the velocity is
		# about to be zeroed by handle_frozen_movement() anyway.
		velocity.y = _cut_rise(velocity.y, frozen or Input.is_action_pressed("jump"),
			jump_velocity * jump_cut)
		is_jumping = velocity.y > 0
		_coyote_left = maxf(_coyote_left - delta, 0.0)
		_jump_buffered = maxf(_jump_buffered - delta, 0.0)
	else:
		is_jumping = false
		_air_jumps_left = air_jumps
		_coyote_left = coyote_time

	# Spent here, ahead of everything else. The exit snap teleported him onto the ledge
	# without a move_and_slide(), so is_on_floor() is still false on this frame and the
	# press would otherwise fall through to the air-jump branch and be charged for.
	if _climb_jump_buffered:
		_climb_jump_buffered = false
		if not frozen:
			velocity.y = jump_velocity
			is_jumping = true
			return

	# The mantle is automatic - no press. Probe every airborne frame and let a qualifying
	# ledge start it. Ahead of the jump handling so a `jump` on the entry frame is buffered
	# for the exit by the is_climbing branch above next frame, not spent as an air jump. The
	# entry snap has already placed him, faced him and zeroed his velocity.
	if not frozen and not is_on_floor() and _try_start_climb():
		# The mantle has its own buffer (`_climb_jump_buffered`) and it is the only one that
		# should survive into the exit. Two graces racing to spend the same press is one too
		# many, and a coyote window left running would outlive the floor he left long ago.
		_coyote_left = 0.0
		_jump_buffered = 0.0
		return

	# A press made just before touchdown, spent on the frame he arrives. Ahead of the fresh
	# press so a player who both buffered and pressed on the landing frame gets one jump
	# rather than two reads of the same intent. Needs no `frozen` test - the block at the top
	# already cleared it.
	if is_on_floor() and _jump_buffered > 0.0:
		_jump_buffered = 0.0
		_take_floor_jump()
		return

	if frozen or not Input.is_action_just_pressed("jump"):
		return

	if is_on_floor() or _coyote_left > 0.0:
		# Coyote time rides in this branch rather than one of its own, which is the whole
		# claim it makes: a press inside the window is the FLOOR jump he was a frame late
		# for, not an extra one, so it costs no air jump and reads identically.
		_take_floor_jump()
	elif _air_jumps_left > 0:
		# The double jump. velocity.y is assigned, not added: rising, a second jump that
		# stacked would send him twice as high off a mistimed double-tap, and falling fast
		# an added one would barely register. Replacing it makes the second jump the same
		# jump wherever in the arc it is taken.
		#
		# `_coyote_left` is not cleared here because it cannot be anything but zero: the
		# branch above claims every frame where it is not.
		_air_jumps_left -= 1
		velocity.y = jump_velocity
		is_jumping = true
		air_jumped.emit()
	else:
		# Out of jumps and off the floor, so the press is remembered rather than dropped.
		# Only ever reached with no air jump left - the air jump is always the more immediate
		# answer to a press and always wins the read.
		_jump_buffered = jump_buffer_time

## The floor jump, shared by the press, the coyote press and the buffered press. All three
## are the same jump and differ only in what convinced us to take it.
func _take_floor_jump() -> void:
	# Jumping stands him up rather than being swallowed by the crouch. There is no
	# crouch-jump clip, and a dead jump key reads as broken input.
	is_crouching = false
	# Same argument for the slide, and it is the only way out of one early. Without
	# it the slide is a 1.25 second cutscene the player cannot leave.
	_end_slide()
	velocity.y = jump_velocity
	is_jumping = true
	# Load-bearing. Without it the grace outlives the jump that just used it and a second
	# press inside the window takes a free jump that never touches `_air_jumps_left`.
	_coyote_left = 0.0

## Processes movement input and calculates movement direction relative to camera.
func _handle_movement_input() -> void:
	input_dir = Input.get_vector("left", "right", "forward", "backward")
	input_strength = minf(input_dir.length(), 1.0)
	direction = _travel_direction(input_dir)

## The world direction a stick/WASD vector means, given where the camera is pointing.
## Lifted out of _handle_movement_input so the slide can ask the same question on the frame
## it starts, before that function has run - see _handle_crouch_and_slide().
func _travel_direction(dir: Vector2) -> Vector3:
	var camera_basis := Transform3D(Basis(Vector3.UP, camera_pivot.rotation.y), Vector3.ZERO).basis
	return (camera_basis * Vector3(dir.x, 0, dir.y)).normalized()

## Rotates the character mesh smoothly toward the direction it should face.
##
## Deviation 3 from stock RC: the lerp is gated on movement input. Stock welds the
## body to camera-back every frame, so orbiting just dragged pilot9 around with
## the camera and his face was unreachable. Standing still he now holds his world
## facing and the camera orbits freely around him.
##
## Deviation 4: what he turns toward. Stock aims at camera-back, which is what makes
## strafing and backing up read against the camera - and what left the one forward-only
## crouch clip playing over sideways motion. Aiming at the travel direction instead means
## he is always walking forward relative to himself, so that clip is correct everywhere.
##
## atan2(direction.x, direction.z) is a generalisation of the stock target rather than a
## replacement for it: `direction` is already camera-relative out of _handle_movement_input,
## so for straight-forward input the two expressions evaluate to the same angle. Measured at
## three camera yaws before this was written, and tests/test_pilot9_turn_to_face.gd holds it.
## That equality is also why the 180 degree basis baked into the `character` node needs no
## correction here.
##
## Deviation 5, the slide: the mesh is welded to `_slide_direction`, not lerped toward it.
## _steer_slide() has already done the smoothing on that heading this frame, at this same
## rotation_speed; lerping again here would only halve the turn rate and open a gap between
## where he points and where he travels. It also ignores the input gate - the heading holds
## itself when the stick is centred, so there is nothing to fall back to.
func _handle_character_rotation(delta: float) -> void:
	if camera_mode == CameraMode.FIRST_PERSON:
		return
	var target: float
	if is_climbing:
		# Welded, like the slide's - and for a stronger reason: the entry snap placed his
		# hands on the lip along this heading, so anything that turned him would slide the
		# grab off the edge it was measured against.
		character.rotation.y = atan2(_climb_facing.x, _climb_facing.z)
		return
	elif is_sliding:
		character.rotation.y = atan2(_slide_direction.x, _slide_direction.z)
		return
	elif input_dir == Vector2.ZERO:
		return
	else:
		target = atan2(direction.x, direction.z) if face_travel_direction \
			else camera_pivot.rotation.y + PI
	character.rotation.y = lerp_angle(character.rotation.y, target, rotation_speed * delta)

## Handles controller stick input for camera rotation.
func _handle_controller_camera(delta: float) -> void:
	if not controller_support or frozen:
		return
	if not InputMap.has_action("look_left") or not InputMap.has_action("look_right") or not InputMap.has_action("look_up") or not InputMap.has_action("look_down"):
		return
	var look_dir = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_dir != Vector2.ZERO:
		var sensitivity := controller_sensitivity * Settings.controller_sensitivity
		camera_pivot.rotation.y -= look_dir.x * sensitivity * delta
		camera_pivot.rotation.x -= look_dir.y * sensitivity * delta
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, -tilt_limit, tilt_limit)

## Gives the SpringArm3D a shape to sweep and takes pilot9 himself out of both casts, then
## builds the probe query once. See docs/specs/pilot9-camera-collision.md.
##
## Done here rather than on the scene for the reason floor_snap_length is: scenes/pilot9.tscn
## is a built artifact - scripts/pilot9_build_scene.gd writes it - so anything set in the
## editor is one rebuild away from being gone, silently, with the camera back on a bare ray.
##
## The exclusion is load-bearing, not housekeeping. CameraPivot sits at y = 1.5 and his own
## capsule spans 0 to 1.955, so the arm STARTS inside his collider. A ray survived that only
## because Godot's ray queries do not hit from inside by default; a sphere cast does, and
## without this the probe would report a hit at zero travel every frame and weld the camera
## to the back of his head.
func _setup_camera_collision() -> void:
	var backstop := spring_arm.shape as SphereShape3D
	if backstop == null:
		backstop = SphereShape3D.new()
		spring_arm.shape = backstop
	backstop.radius = camera_clearance
	spring_arm.add_excluded_object(get_rid())

	var probe := SphereShape3D.new()
	probe.radius = camera_clearance + camera_probe_lead
	_camera_probe = PhysicsShapeQueryParameters3D.new()
	_camera_probe.shape = probe
	_camera_probe.exclude = [get_rid()]
	_camera_probe.collision_mask = spring_arm.collision_mask

## The length the world allows, this frame, with no damping on it yet.
##
## The probe is FATTER than the arm's own backstop by camera_probe_lead, which is the whole
## point of casting it ourselves: it trips while the wall is still that much further out, and
## the head start is what _camera_length_step() spends turning a snap into a zoom. A probe
## the same size as the backstop would only ever agree with the arm, always too late to damp.
##
## cast_motion() hands back the safe fraction of the motion; a probe already overlapping
## something returns 0, which the floor below catches. First person has a zero-length arm and
## nothing to collide with, so it never casts at all.
func _camera_obstruction_length(mode_length: float) -> float:
	if mode_length <= 0.0 or _camera_probe == null or not is_inside_tree():
		return mode_length
	var world := get_world_3d()
	if world == null:
		return mode_length
	var space := world.direct_space_state
	if space == null:
		return mode_length
	_camera_probe.transform = Transform3D(Basis(), spring_arm.global_position)
	# A SpringArm3D pushes its children along its own +Z, so that is where the wall will be.
	_camera_probe.motion = spring_arm.global_transform.basis.z.normalized() * mode_length
	var fractions := space.cast_motion(_camera_probe)
	if fractions.size() < 1:
		return mode_length
	var allowed: float = float(fractions[0]) * mode_length
	# minf() so a mode length already under the floor - mid-transition to first person - is
	# not dragged back out by it.
	return maxf(allowed, minf(camera_min_distance, mode_length))

## One frame of the damped arm length: fast toward a wall, slow away from one.
##
## The asymmetry is the anti-flicker property and is worth more than the smoothing itself. A
## grazing edge that hits and misses on alternating frames settles IN rather than oscillating,
## because every hit pulls at retract_speed and every gap only drifts back at return_speed.
##
## Static and pure so the curve can be asserted without a rig, a tree or a wall - see
## tests/test_pilot9_camera_collision.gd. The weight is clamped for the reason
## _handle_camera_fov() clamps its own: a rate times a long frame would otherwise hand lerpf
## a weight above 1 and shoot past the target instead of arriving at it.
static func _camera_length_step(current: float, desired: float, delta: float, retract_speed: float, return_speed: float) -> float:
	var rate := retract_speed if desired < current else return_speed
	return lerpf(current, desired, clampf(rate * delta, 0.0, 1.0))

## Handles smooth camera transition between modes, and the walls.
##
## Two lengths, deliberately: the mode transition owns _camera_mode_length and the walls own
## spring_length. See docs/specs/pilot9-camera-collision.md for why the mesh reads the first.
func _handle_camera_transition(delta: float) -> void:
	_camera_mode_length = lerpf(_camera_mode_length, target_camera_distance,
		clampf(camera_transition_speed * delta, 0.0, 1.0))
	var desired := _camera_obstruction_length(_camera_mode_length)
	spring_arm.spring_length = _camera_length_step(spring_arm.spring_length, desired, delta,
		camera_retract_speed, camera_return_speed)

	if character and camera_distance > 0.0:
		var transition_progress := _camera_mode_length / camera_distance
		var visibility_threshold := 0.3
		character.visible = transition_progress > visibility_threshold
	elif character:
		character.visible = camera_mode == CameraMode.THIRD_PERSON

## Widens the camera while he is sprinting and eases it back for everything else.
## See docs/specs/pilot9-sprint-fov.md.
##
## The gate is _apply_movement()'s sprint test with the on-floor requirement dropped, which
## is the one thing here worth reading twice. `is_sprinting` is not used directly because it
## needs is_on_floor(): reading it would shut the view down the instant a sprinting pilot9
## left the ground and pop it open again on touchdown - a dip on every jump taken at speed,
## which is when the wide shot is most wanted. Carrying it through the air is the same call
## _update_sprint_toggle() already made for the sprint itself.
##
## A slide is not a sprint here, so the view sags shut for its length and opens again if it
## hands back to a run. That is the literal ask - sprinting only - and it is the line most
## likely to want revisiting after a play; dropping `and not is_sliding` is the whole change.
##
## Runs first in the physics step, so the state it reads is one frame old. That is the trade
## for also running on the frames a mantle or a freeze returns early from, which are the
## frames the FOV most needs to be travelling. 16 ms of lag on a ~500 ms ease is not visible.
func _handle_camera_fov(delta: float) -> void:
	var sprinting_view := sprint_toggled 		and input_dir != Vector2.ZERO 		and not Input.is_action_pressed("walk") 		and not is_crouching 		and not is_sliding 		and not is_climbing 		and not frozen
	var target_fov := base_fov + (sprint_fov_boost if sprinting_view else 0.0)
	# Clamped because the weight is a rate times a frame: a long frame - a hitch, a load, a
	# breakpoint - would otherwise hand lerpf a weight above 1 and shoot the FOV past the
	# target instead of arriving at it.
	camera_3d.fov = lerpf(camera_3d.fov, target_fov, clampf(fov_transition_speed * delta, 0.0, 1.0))

## Updates camera mode (sets target for smooth transition).
func _update_camera_mode() -> void:
	if camera_mode == CameraMode.FIRST_PERSON:
		target_camera_distance = 0.0
	else:
		target_camera_distance = camera_distance

## Applies horizontal movement velocity based on input and sprint/walk state.
##
## Deviation 6, momentum: stock Real Controller ASSIGNS the horizontal velocity from the stick
## every frame, and an assignment cannot carry speed - whatever a slide down a slope earned is
## deleted on the frame the slide ends, in mid-air included. So the assignment is kept for
## everything at or under ordinary locomotion speed and replaced by a decay above it. See
## docs/specs/pilot9-slope-momentum.md.
##
## The threshold is `sprint_speed` on both sides of it, and for two different reasons:
##
## - On the floor it is the line between locomotion and momentum. At or under a sprint every
##   feel decision stock made still stands, the dead stop on a released stick included.
## - In the air it is a floor on what he may be reassigned DOWN to, and only while a stick is
##   asking for it. `is_sprinting` needs is_on_floor(), so an airborne `current_speed` is the
##   plain walk-around `speed`, and the stock assignment therefore dropped a sprint jump from
##   8 m/s to 5 the moment he left the ground. It never sped him up in the air; it should not
##   slow him down either. With no stick there is nothing to hold up, the target is 0, and he
##   brakes down to a straight vertical fall - see `air_momentum_brake`.
##
## The RATE that decay runs at is what keeps this from reading as ice - see _momentum_rate().
## Speed he is still driving into costs the drive rate; speed he has stopped asking for costs
## the brake, which is several times as much. Letting go of the stick is a request to stop,
## and the controller has to answer it whether or not his feet are down: on the floor that is
## `momentum_decay` / `momentum_brake`, in the air `air_momentum_decay` / `air_momentum_brake`.
func _apply_movement(delta: float) -> void:
	var is_moving = input_dir != Vector2.ZERO and is_on_floor()
	# Crouch outranks both gaits: it owns the whole locomotion state, so leaving either
	# flag set would keep pilot9_animation.gd feeding the walk/run blends underneath it.
	is_sprinting = sprint_toggled and is_moving and not Input.is_action_pressed("walk") and not is_crouching
	is_walking = Input.is_action_pressed("walk") and is_moving and not sprint_toggled and can_walk and not is_crouching
	
	var current_speed: float
	if is_crouching:
		current_speed = crouch_speed
	elif is_sprinting:
		current_speed = sprint_speed
	elif is_walking and can_walk:
		current_speed = walk_speed
	else:
		current_speed = speed
	
	var demanded := current_speed * input_strength if direction else 0.0
	var carried := _horizontal_speed()
	# The speed the stick asks for, raised to a sprint where momentum is in play - over a
	# sprint on foot, and by however much of one he is already carrying in the air.
	var target := demanded
	if not is_on_floor():
		# The airborne floor is a floor under a REQUEST, so it needs a stick behind it. With
		# none the target is the 0 the stock assignment would have written, and the brake
		# below is what walks him down to it instead of snapping - which is what lets him
		# fall straight rather than carrying a lip's worth of run out into the drop.
		if direction:
			target = maxf(demanded, minf(carried, sprint_speed))
	elif carried > sprint_speed:
		target = maxf(demanded, sprint_speed)

	# Two conditions rather than one. `carried > target` is the decay itself; `target >
	# demanded` is the frame where they are already equal and the only thing the branch has
	# to do is keep the stock assignment from writing a smaller number - the airborne sprint
	# above, exactly at the boundary.
	if carried > target + SPEED_EPSILON or target > demanded + SPEED_EPSILON:
		var travel := Vector3(velocity.x, 0.0, velocity.z) / carried
		# How much of the speed he is still asking for. No stick and a crouch are both -1:
		# neither is a request to keep going. See _momentum_rate().
		var agreement := -1.0
		if direction and not is_crouching:
			agreement = direction.dot(travel)
		var drive := momentum_decay if is_on_floor() else air_momentum_decay
		var brake := momentum_brake if is_on_floor() else air_momentum_brake
		var kept := _decayed_speed(carried, target, _momentum_rate(agreement, drive, brake),
			delta)
		# Steered by the stick where there is one, and by his own heading where there is not,
		# so a released stick coasts to a halt along its own line instead of snapping to one.
		var heading := direction if direction else travel
		velocity.x = heading.x * kept
		velocity.z = heading.z * kept
		return

	if direction:
		velocity.x = direction.x * current_speed * input_strength
		velocity.z = direction.z * current_speed * input_strength
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

## Drives the slide from the clip's own forward-travel curve instead of a speed constant.
##
## `slide_motion` is distance-so-far against time, both normalised 0..1. The speed for this
## frame is the distance across the frame's window divided by the frame - i.e. the curve
## differentiated, sampled exactly where the motion is about to be applied. Feet and floor
## therefore agree wherever the clip has planted feet, which is the run-in at ~8 m/s and the
## run-out at ~5, without either number appearing anywhere in this file.
##
## is_sprinting and is_walking are deliberately left holding whatever _apply_movement last
## set: nothing reads them while the `slide` state owns the tree, and leaving them alone is
## what lets a slide that ends with sprint still toggled on hand straight back to a sprint
## rather than fading up from a run.
##
## Also the only writer of _slide_time, and therefore the only place the hold can begin. It
## has to be here rather than in _handle_crouch_and_slide(): that runs first in the frame
## and would enter the hold one frame after the crossing, having already let the curve carry
## him past the pose the hold is supposed to sit on.
func _apply_slide_velocity(delta: float) -> void:
	if delta <= 0.0 or slide_motion == null or slide_duration <= 0.0:
		return

	_slide_elapsed += delta
	_advance_slide_bonus(delta)

	# The floor under the clip. Raises the clip's speed to meet it and nothing more: where
	# the curve is already faster the curve drives, the bonus still rides on top, and a
	# negative bonus still eats straight through it - which is what keeps SLIDE_STALL_SPEED
	# reachable on a slide steered uphill. See docs/specs/pilot9-slide-boost.md.
	var floor_speed := _slide_speed_floor()

	# Held: the clip's speed is flat and the clock does not move, so everything that changes
	# during a hold changes in `_slide_bonus` and in the floor's own decay. velocity.y is
	# left to gravity, and move_and_slide() lays this horizontal velocity along whatever
	# floor he is on.
	if is_slide_holding:
		var held := _capped_slide_speed(
			maxf(_slide_hold_speed, floor_speed), _slide_bonus, slide_max_speed)
		velocity.x = _slide_direction.x * held
		velocity.z = _slide_direction.z * held
		return

	# The clock runs to the end of the clip, or to the hold if this frame is still short of
	# one. `entering` is what makes the crossing one-way: past the hold frame, and after the
	# run-out has resumed from it, _slide_time is no longer < slide_hold_time and the clip
	# plays out to its end the way it always did.
	var entering := can_hold_slide and slide_hold_time > 0.0 and _slide_time < slide_hold_time
	var limit := slide_hold_time if entering else slide_duration

	# The frame's worth of CLIP, which is not the frame: `slide_time_scale` is the rate the
	# state machine is playing the clip at, and reading the curve anywhere else would show a
	# pose that is not the pose travelling. One multiply, in the one place the clock moves.
	var clip_delta := delta * slide_time_scale
	var from := _slide_time / slide_duration
	var until := minf(_slide_time + clip_delta, limit)
	var travelled := (slide_motion.sample(until / slide_duration) - slide_motion.sample(from)) \
		* slide_distance * slide_scale
	# Back into wall seconds for the split below - `consumed` is clip time, and the part of
	# the frame the hold gets is whatever real time the curve did not use.
	var consumed := (until - _slide_time) / slide_time_scale
	_slide_time = until

	# The frame that crosses into the hold is split rather than rounded either way: the curve
	# is read up to the hold frame and the rest of the frame is already travelling at the
	# hold speed. Giving the whole frame to the curve would travel metres the run-out then
	# covers again; giving it to the clock would divide a part-frame's distance by a whole
	# delta and drop his speed for one frame, which is a hitch on the frame the hold is
	# meant to be seamless. Splitting it is exact in both.
	if entering and _slide_time >= slide_hold_time:
		_enter_slide_hold()
		travelled += _slide_hold_speed * (delta - consumed)

	var speed_now := _capped_slide_speed(
		maxf(travelled / delta, floor_speed), _slide_bonus, slide_max_speed)
	velocity.x = _slide_direction.x * speed_now
	velocity.z = _slide_direction.z * speed_now

## One frame of `_slide_bonus`, off the floor he is actually standing on.
##
## Airborne frames add nothing - a slide that has left the floor is over anyway, ended by
## _handle_crouch_and_slide() on this same frame - and that is also why every headless test
## of the slide sees a bonus of exactly zero and measures the clip alone.
##
## get_floor_normal() is one frame old, being the result of the last move_and_slide(). At
## 60 Hz on geometry that does not move, that is a normal read 16 ms before the velocity it
## shapes is applied; nothing here is delicate enough to care.
func _advance_slide_bonus(delta: float) -> void:
	if not is_on_floor():
		return
	var accel := _slope_accel(_slide_direction, get_floor_normal(), get_gravity().length(),
		slide_slope_accel)
	_slide_bonus = _stepped_bonus(_slide_bonus, accel, slide_friction, delta)

## -- the ledge mantle ---------------------------------------------------------
##
## Detection, entry snap, path playback, exit. See docs/specs/pilot9-climb.md. Three things
## are worth knowing before reading them:
##
## 1. The rays are fired every airborne frame - the mantle is automatic, so there is no
##    press to hang the probe off. Three raycasts a frame while off the floor; cheap, and
##    the guard in _handle_gravity_and_jump() keeps it from running on grounded frames.
## 2. The geometry is measured off the CLIP, not off the ledge. climb_hand_offset and
##    climb_foot_offset are where his hands and his soles sit relative to his own origin on
##    the first and last frames; both snaps subtract them from the detected lip, so the two
##    moments that actually touch the world are exact by construction.
## 3. Nothing here calls move_and_slide(). global_position is written directly with the
##    collision shape switched off, which is the only way a body gets over an edge it is
##    standing against.

## Is this hit a ledge? In the band, and flat enough to stand on. Pure maths, deliberately
## kept out of the raycasting so it can be tested without a physics world - it is the ONLY
## filter the mantle has (no climbable layer, no tag), which makes it worth testing.
##
## `height` is metres of lip above his feet; `normal` is the surface normal at the hit.
func _qualifies_as_ledge(height: float, normal: Vector3) -> bool:
	if height < climb_band_min or height > climb_band_max:
		return false
	return normal.normalized().dot(Vector3.UP) > cos(deg_to_rad(climb_max_lip_slope))

## Turns three raycast results into a mantle, or into nothing. Split out of _probe_ledge()
## for the reason the predicate above is: this is the whole decision, and the rays are the
## only part of it that needs a world.
##
## `forward` must have hit a wall, `down` must have hit a lip that qualifies, and
## `headroom` must have hit NOTHING - anything over the spot he would land on refuses the
## mantle, because he arrives standing and planting him inside a ceiling is an ugly failure.
##
## The lip handed back is the wall face at the top surface's height, not the down ray's own
## hit point: that ray is cast deliberately inside the platform (see CLIMB_LIP_PROBE_INSET)
## and his hands belong on the edge, not 0.4 m in from it.
func _evaluate_ledge(feet_y: float, forward: Dictionary, down: Dictionary,
		headroom: Dictionary) -> Dictionary:
	if forward.is_empty() or down.is_empty() or not headroom.is_empty():
		return {}
	var lip_y: float = (down["position"] as Vector3).y
	if not _qualifies_as_ledge(lip_y - feet_y, down["normal"]):
		return {}
	var face: Vector3 = forward["position"]
	return {
		"lip": Vector3(face.x, lip_y, face.z),
		"wall_normal": forward["normal"],
	}

## Fires the three rays and hands them to _evaluate_ledge(). Returns {} when there is no
## mantle here, which is every airborne frame away from a wall.
func _probe_ledge() -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var feet := global_position
	# Third person: the mesh yaw, which _handle_character_rotation() has been turning toward
	# travel every airborne frame - grab the wall he is flying at. First person: nothing
	# drives the mesh (that function early-returns), so character.rotation.y is stale and the
	# probe would fire at a fixed world heading. Aim it where the camera looks instead, the
	# way every other first-person heading in this controller is taken.
	var facing := _facing() if camera_mode == CameraMode.THIRD_PERSON \
		else -Vector3(sin(camera_pivot.rotation.y), 0.0, cos(camera_pivot.rotation.y))
	var self_rid := get_rid()

	# 1. The wall. Cast below the shallowest lip the band accepts - see climb_probe_height -
	#    so it meets the face rather than sailing over the top of it.
	var eye := feet + Vector3.UP * climb_probe_height
	var forward_q := PhysicsRayQueryParameters3D.create(eye, eye + facing * climb_probe_reach)
	forward_q.exclude = [self_rid]
	var forward := space.intersect_ray(forward_q)
	if forward.is_empty():
		return {}

	# 2. The lip, found from above and a little inside the platform. The ray spans the band
	#    and no more, so a hit is nearly always qualified already and _qualifies_as_ledge()
	#    is confirming rather than filtering.
	var inside: Vector3 = (forward["position"] as Vector3) + facing * CLIMB_LIP_PROBE_INSET
	var top := Vector3(inside.x, feet.y + climb_band_max + CLIMB_PROBE_MARGIN, inside.z)
	var span := (climb_band_max - climb_band_min) + 2.0 * CLIMB_PROBE_MARGIN
	var down_q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * span)
	down_q.exclude = [self_rid]
	var down := space.intersect_ray(down_q)
	if down.is_empty():
		return {}

	# 3. Headroom over the spot he would end up standing on.
	var face_pos: Vector3 = forward["position"]
	var landing := Vector3(face_pos.x, (down["position"] as Vector3).y, face_pos.z) \
		+ facing * climb_inset
	var head_q := PhysicsRayQueryParameters3D.create(
		landing + Vector3.UP * CLIMB_PROBE_MARGIN, landing + Vector3.UP * climb_headroom)
	head_q.exclude = [self_rid]
	var headroom := space.intersect_ray(head_q)

	return _evaluate_ledge(feet.y, forward, down, headroom)

## Airborne, with a ledge in range. Called every airborne frame now that the mantle is
## automatic; returns false for every other case so the frame falls through to the normal
## jump handling - see _handle_gravity_and_jump().
func _try_start_climb() -> bool:
	if not can_climb or is_climbing or is_on_floor():
		return false
	if climb_motion_y == null or climb_motion_z == null or climb_duration <= 0.0 or climb_speed <= 0.0:
		return false
	var ledge := _probe_ledge()
	if ledge.is_empty():
		return false
	_start_climb(ledge["lip"], ledge["wall_normal"])
	return true

## The entry snap. Instant, never blended: a one or two frame blend here reads as a slide
## toward the wall, and the whole point of snapping is that the hands meet the edge every
## time rather than nearly every time.
func _start_climb(lip: Vector3, wall_normal: Vector3) -> void:
	is_climbing = true
	_climb_time = 0.0
	_climb_jump_buffered = false
	# The mantle ends him standing, and it cannot be entered out of a slide anyway. Clearing
	# both is what stops the exit handing back into a pose he is visibly not in. The buffered
	# air-crouch goes too, for the reason `frozen` drops it: a stale slide firing on the frame
	# the mantle hands back is not what was asked for.
	is_crouching = false
	_slide_buffered = false
	_end_slide()

	# Face the wall: the heading opposite its normal, flattened to the ground plane. A normal
	# with no horizontal part is not a wall to face, so hold the heading he arrived on.
	var into_wall := Vector3(-wall_normal.x, 0.0, -wall_normal.z)
	_climb_facing = into_wall.normalized() if into_wall.length() > 0.001 else _facing()
	character.rotation.y = atan2(_climb_facing.x, _climb_facing.z)

	# His own frame, so the two baked offsets can be applied exactly as they were measured.
	# Built from the yaw rather than read off the node, so this is correct before anything
	# has re-evaluated the mesh transform.
	var body := Basis(Vector3.UP, character.rotation.y)
	_climb_start_position = lip - body * climb_hand_offset
	_climb_end_position = lip + _climb_facing * climb_inset - body * climb_foot_offset
	global_position = _climb_start_position
	# A snap onto the lip, not travel toward it. Without this the interpolator would draw him -
	# and the camera, which reads his interpolated transform - sliding in from wherever he
	# jumped. The per-frame writes in _handle_climb() below are real motion and do interpolate.
	reset_physics_interpolation()

	# Measured off the detected lip rather than lifted out of the bake - see the note on
	# _climb_detected_rise. The forward half is projected onto the heading because the
	# curves drive two axes; the few centimetres of lateral between his hands on the lip and
	# his feet on the top are left for the exit snap to absorb.
	var span := _climb_end_position - _climb_start_position
	_climb_detected_rise = span.y
	_climb_detected_reach = _climb_facing.dot(span)

	# Deferred because this runs inside physics processing, where the shape is in use.
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO

## Writes the body along the baked path. Position driven, not velocity driven - a mantle is
## not physics, and every frame of it is a place rather than a speed.
func _apply_climb_motion(delta: float) -> void:
	if climb_motion_y == null or climb_motion_z == null or climb_duration <= 0.0 or climb_speed <= 0.0:
		_end_climb(true)
		return
	# delta * climb_speed, not delta: the `climb` state's custom timeline compresses the clip
	# by the same climb_speed, so the two clocks stay locked while the whole mantle plays fast.
	_climb_time += delta * climb_speed
	if _climb_time >= climb_duration:
		_end_climb(true)
		return
	var u := _climb_time / climb_duration
	var offset := Vector3.UP * (climb_motion_y.sample(u) * _climb_detected_rise) \
		+ _climb_facing * (climb_motion_z.sample(u) * _climb_detected_reach)
	global_position = _climb_start_position + offset
	velocity = Vector3.ZERO

## Ends the mantle, on time or on `frozen`. Both endings do the same three things - hard
## snap to the endpoint, put the collision shape back, stop him dead - because the state
## being left is the same either way: a body with no collision shape somewhere over an edge.
##
## `completed` is false only when `frozen` cut it short, and then the buffered jump goes
## with it: a stale mantle-jump firing on the frame he unfreezes is not what was asked for.
func _end_climb(completed: bool) -> void:
	if not is_climbing:
		return
	is_climbing = false
	_climb_time = 0.0
	global_position = _climb_end_position
	# The hard snap the docstring above describes - not interpolated across, same as the entry.
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if not completed:
		_climb_jump_buffered = false

## Handles mouse input for camera rotation with tilt limits.
## Places the camera rig every drawn frame. Physics interpolation is on project-wide (see
## project.godot), which means his body steps at the physics tick and is drawn at an
## interpolated position in between - and a camera parented to it would have to be one of two
## wrong things. Interpolated, mouse look gets quantised to the tick and lands a frame late,
## which is precisely the authority over the view the movement work has been defending.
## Not interpolated, it inherits his raw 60 Hz stepped position and judders on every turn.
##
## So CameraPivot is top_level with physics_interpolation_mode OFF, and its two halves run off
## different clocks on purpose: position from his *interpolated* transform so the view travels
## smoothly, rotation left exactly as _unhandled_input below set it so it does not lag. This is
## the split the engine documents for this case.
##
## Only the position is written here. His pivot yaw and pitch are already world-absolute - the
## body is never rotated, only the mesh child is - so nothing has to be recomputed for
## top_level, and _unhandled_input stays the only thing that aims him.
##
## Note this runs while `frozen`, unlike almost everything else in this file. A frozen pilot9
## still has to be drawn at the right place, and the mantle and the mech handover both move him
## while the input handler is shut off.
func _process(_delta: float) -> void:
	camera_pivot.global_position = get_global_transform_interpolated() * CAMERA_PIVOT_OFFSET


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return

	if event is InputEventMouseMotion:
		# Settings.mouse_sensitivity is a 0.25x-2.00x scalar on top of this
		# authored value, not a replacement for it - the number itself is a
		# deliberate feel decision. See docs/specs/settings.md, Controls.
		var sensitivity := mouse_sensitivity * Settings.mouse_sensitivity
		camera_pivot.rotation.x -= event.relative.y * sensitivity
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, -tilt_limit, tilt_limit)
		camera_pivot.rotation.y += -event.relative.x * sensitivity

func _input(event: InputEvent) -> void:
	if InputMap.has_action("camera_mode_switch") and event.is_action_pressed("camera_mode_switch") and allow_camera_mode_switch:
		camera_mode = CameraMode.THIRD_PERSON if camera_mode == CameraMode.FIRST_PERSON else CameraMode.FIRST_PERSON
		_update_camera_mode()

## -- the mech handshake -----------------------------------------------------
##
## The two methods that make pilot9 a pilot of EXIA (scripts/mech.gd), and only these two of
## the six-method pilot contract. The other four are the climb - `embark_length`,
## `begin_embark`, `ride`, `begin_unseal`/`begin_disembark` - and he does not have it: `SET
## embark` is 2 s of authored travel from one exact spot, and an animation that only works
## from one approach makes the mech a thing you line yourself up with. So boarding is a cut
## and exiting is a cut, and mech.gd's own `has_method`-guarded fallback path does the rest.
##
## Duck-typed from mech.gd's side - it names no pilot class - so a rename here degrades to a
## fallback rather than erroring. tests/test_pilot9_mech.gd pins the pair from both ends for
## that reason. See docs/specs/pilot9-mech-mount.md.

## Boarding EXIA: he disappears on the frame F is pressed and the machine is drivable at
## once. The first four writes are player.gd::_hand_over_controls() exactly; on top of them
## the locomotion tree is switched off and he is hidden. `_vehicle` is unused - he rides
## nothing and is carried by nothing.
func enter_vehicle(_vehicle: Node3D) -> void:
	# F can land mid-slide, mid-crouch or mid-mantle - the interaction box is 9 m tall. End
	# them before the collision shape goes away under him rather than freezing them to resume.
	_end_verbs_for_boarding()
	velocity = Vector3.ZERO
	collision_shape.disabled = true
	# _end_verbs_for_boarding() may have run _end_climb(), which queues a DEFERRED re-enable
	# of the shape (a mantle normally ends mid-physics, where the shape is in use). Re-issue
	# the disable through the same deferred queue so it lands last; the direct write above is
	# what a same-frame caller and the tests see.
	collision_shape.set_deferred("disabled", true)
	set_physics_process(false)
	set_process_unhandled_input(false)
	anim_tree.active = false
	visible = false

## Ends every live verb on the way aboard. Each is stopped the way a freeze already stops it,
## not frozen to resume later: `is_slide_holding` is unbounded by design, so resuming a hold
## after a drive across the map is worse than losing it.
func _end_verbs_for_boarding() -> void:
	if is_climbing:
		# The same "land him on top" stop a freeze mid-mantle takes - he is on a scripted path
		# over an edge with his shape off, and that has to be closed out cleanly.
		_end_climb(false)
	if is_sliding:
		_end_slide()          # also clears is_slide_holding and arms the cooldown
	# A queued air-slide press would fire the instant he is handed back on the ground - the
	# same "slide he started somewhere else" the held slide is guarded against.
	_slide_buffered = false
	is_crouching = false
	sprint_toggled = false
	is_sprinting = false
	is_walking = false
	_slide_cooldown_left = 0.0

## Leaving EXIA, landing him in idle. The mirror of enter_vehicle(). `exit_position` is
## EXIA's ExitPoint - 3.6 m out of the back - and `facing_yaw` is the machine's own nose;
## ExitPoint is behind it, so facing the nose is facing the mech.
##
## His rig is shaped unlike Setsuna's and the same intents write different nodes (spec's
## table). The body's yaw is never touched - nothing ever rode him - so the mesh child
## carries the facing, and camera_pivot's yaw IS the world yaw with nothing to subtract.
func exit_vehicle(exit_position: Vector3, facing_yaw: float) -> void:
	global_position = exit_position
	# He is placed at the exit point, not walked there.
	reset_physics_interpolation()
	# The mesh, not the body. character.rotation.y = atan2(h.x, h.z) faces heading h, and
	# atan2(sin yaw, cos yaw) is yaw itself, so the mech's `rotation.y` crosses over with no
	# correction - see _handle_character_rotation and docs/specs/pilot9-turn-to-face.md.
	character.rotation.y = facing_yaw
	# And level. He is placed rather than walked, so a slope tilt carried in from wherever he
	# boarded would be a lean against ground that is no longer under him - see
	# _align_model_to_slope(), which eases it back on from zero if EXIA parked on a grade.
	character.rotation.x = 0.0
	character.rotation.z = 0.0
	# Half a turn round from his facing: behind him, looking at the machine he climbed out of.
	# mech-camera-handover.md's rule, and the fix for the handback dropping him staring at his
	# own back. Written straight onto the pivot because the body is unrotated.
	camera_pivot.rotation.y = facing_yaw + PI
	camera_pivot.rotation.x = EXIT_PITCH
	velocity = Vector3.ZERO
	visible = true
	collision_shape.disabled = false
	anim_tree.active = true
	set_physics_process(true)
	set_process_unhandled_input(true)
	# The 0.6 s pan into this shot comes free: mech.gd::_exit_mech() reads the viewport camera
	# after exit_vehicle() has made his current, and flies the view into it.
	camera_3d.current = true
	# Started outright at `Locomotion`, not left to the advance expressions to walk back:
	# board him mid-jump and the tree is parked in `jump` or `fall`, and he would step out of
	# a powered-down mech into a fall. `Locomotion` is what start() has to be given - pilot9's
	# tree has no `idle` state; idle is a corner of the Locomotion blend tree.
	var playback: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]
	if playback != null:
		playback.start(&"Locomotion")