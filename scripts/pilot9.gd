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
## Also added: the rail grind. Falling onto a `Rail` (scripts/rail.gd) catches him and he rides
## it at one of two fixed gears until he jumps, dashes, crouches or runs off the end - see
## _handle_rail_grind() and docs/specs/pilot9-rail-grind.md. Like the mantle it is written
## against a path, but VELOCITY driven: every frame asks the rail where its next point is now,
## so a rail parented to something moving carries him with it.
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
## Driven directly during a wall-run, tree switched off - see _start_wall_run(). Sibling of
## anim_tree, same pattern the mech mount above uses to take the tree out of the loop.
@onready var anim_player: AnimationPlayer = $AnimationPlayer

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
## Speed while crouched. Matches `speed` (the run) since 2026-09-28 - the crouch is a gait,
## not a handicap. It was 1.6, matched to the crouch clip's cadence; the clip still plays at
## that authored rate, so at 5.0 his feet skate under him until the cycle is sped up to match.
@export_range(0.1, 10.0, 0.1, "or_greater") var crouch_speed: float = 5.0
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

## Body Lean Settings
## -----------------------------------------------------------------------------
## On the ground at a walk, run or sprint the mesh rolls into turns and pitches with changes
## of speed, on top of the slope tilt and through its ease. Movement is untouched - only
## `character` leans. See docs/specs/pilot9-body-lean.md and _body_lean_target().

@export_group("Body Lean")
## Degrees of roll into a turn at full. 0 turns the roll off.
@export_range(0.0, 30.0, 0.5) var body_lean_roll_max: float = 8.0
## m/s^2 of sideways acceleration (horizontal speed x mesh yaw rate) that earns the full roll.
## 23.5 is a sprint carving at about 180 degrees a second. Lower leans harder at a walk.
@export_range(0.1, 100.0, 0.5, "or_greater") var body_lean_roll_full_accel: float = 23.5
## Degrees forward at the VISIBLE peak of a full speed-up. 0 turns it off.
@export_range(0.0, 30.0, 0.5) var body_lean_pitch_forward_max: float = 6.0
## Degrees back at the visible peak of a full stop. Smaller than forward on purpose - a big
## rear lean reads as tripping. 0 turns it off.
@export_range(0.0, 30.0, 0.5) var body_lean_pitch_back_max: float = 4.0
## m/s of speed change that earns the full pitch (= sprint_speed).
@export_range(0.1, 30.0, 0.1, "or_greater") var body_lean_pitch_full_gap: float = 7.5
## Seconds the "felt" speed lags behind the real one - how long a pitch lingers.
@export_range(0.01, 2.0, 0.01) var body_lean_felt_lag: float = 0.25

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

## Vault Settings
## -----------------------------------------------------------------------------
## Over a waist-high obstacle at speed: a GROUNDED `jump` press with a qualifying top ahead
## vaults instead of jumping. Anything that does not qualify is the ordinary jump, unchanged.
## Hands planted on the top, clip locked, body driven along baked curves - collision off up to
## the hand release, move_and_slide() from there. See docs/specs/pilot9-vault.md.
##
## Every number below is a tunable starting value. The probes fire only on the press frame.

@export_group("Vault")
@export var can_vault: bool = true
## The near face, in metres ahead of his feet (the capsule's front, not his centre). Under the
## minimum the run-up has nothing to squash into and reads as a lurch; past the maximum it is
## a jump.
@export_range(0.0, 5.0, 0.05) var vault_reach_min: float = 0.5
@export_range(0.0, 6.0, 0.05) var vault_reach_max: float = 3.0
## The top, in metres above his feet. Under the band it is a step; over it the jump (and the
## mantle it carries into) takes it.
@export_range(0.1, 2.0, 0.05) var vault_band_min: float = 0.5
@export_range(0.1, 2.5, 0.05) var vault_band_max: float = 1.3
## Degrees off square he may approach at. He always goes over square - facing snaps across.
@export_range(0.0, 89.0, 1.0) var vault_max_angle: float = 45.0
## Deepest top, near face to far edge. Deeper is a platform you jump onto, not a wall you go over.
@export_range(0.1, 5.0, 0.05) var vault_max_depth: float = 1.5
## How far off level the top may be, in degrees - same as the mantle's lip.
@export_range(0.0, 60.0, 1.0) var vault_max_top_slope: float = 30.0
## How far below his start the landing floor may be. Past the drop is a pit, not a landing.
@export_range(0.0, 20.0, 0.1) var vault_max_drop: float = 3.0

## BAKED - written by scripts/pilot9_build_scene.gd::_ensure_vault_motion() off the vault clip
## (assets/pilot9_vault.fbx). The body path as two curves, clip fraction in: Y in units of
## `vault_top_height`, Z in units of `vault_travel`. The hands are pinned between the plant and
## the release; _vault_offset() warps the rest onto the detected wall at runtime.
@export var vault_motion_y: Curve
@export var vault_motion_z: Curve
## BAKED - the clip's authored length in seconds, and the metres forward the path covers over it.
@export var vault_duration: float = 0.0
@export var vault_travel: float = 0.0
## BAKED - vault_travel / vault_duration: the speed the clip was authored at. The time scale of a
## vault is entry speed over this.
@export var vault_clip_speed: float = 0.0
## BAKED - clip fractions: last toe off the floor, both wrists down, a wrist up again, a toe back
## down. The release is where collision comes back on and a jump press starts to count.
@export var vault_takeoff_time: float = 0.0
@export var vault_plant_time: float = 0.0
@export var vault_release_time: float = 0.0
@export var vault_touchdown_time: float = 0.0
## BAKED - the top the clip was authored over (planted wrists less a palm), metres above his feet.
@export var vault_top_height: float = 0.0
## BAKED - metres from his start origin to the planted hands, horizontally.
@export var vault_plant_reach: float = 0.0
## BAKED - metres from the planted hands to where he touches down. The landing ray looks there.
@export var vault_post_travel: float = 0.0
## BAKED - metres between the two wrists along the travel. They plant one after the other, the
## right ahead of the left, so a top has to be about this deep to take both.
@export var vault_hand_spread: float = 0.0
## BAKED - lowest toe over the top while the hands are down, metres above the top.
@export var vault_foot_clearance: float = 0.0
## BAKED - metres of wrist above the surface the hand is flat on.
@export var vault_palm: float = 0.0

## Dash Settings
## -----------------------------------------------------------------------------
## He vanishes, travels flat for `dash_time` at `dash_speed`, and reappears - no clip, no
## state machine entry, no TimeScale. See docs/specs/pilot9-dash.md.
##
## All three exported rather than const, unlike Setsuna's in player.gd: his whole kit is
## tuned in the inspector while playing, and a feature whose numbers are explicitly guesses
## is not going to be the exception.

@export_group("Dash")
@export var can_dash: bool = true
## Started from Setsuna's DASH_SPEED (18.0), bumped snappier after the play session, then
## doubled again on 2026-09-18 alongside the dash_time halving below - distance (dash_speed *
## dash_time) is unchanged, only how fast it happens. See docs/specs/pilot9-dash.md.
@export_range(1.0, 80.0, 0.5, "or_greater") var dash_speed: float = 40.0
## The user's call, 2026-09-17, halved 2026-09-18 for a snappier feel. Setsuna's is 0.3 s.
@export_range(0.05, 3.0, 0.05) var dash_time: float = 0.25
## Measured from the PRESS, not from the end of the dash, so the constant means what it
## says. Chosen against his 1.2 s airtime - see docs/specs/pilot9-dash.md, Availability.
@export_range(0.0, 10.0, 0.1) var dash_cooldown: float = 1.5

## Wall-Run Settings
## -----------------------------------------------------------------------------
## Airborne, moving along a near-vertical face, he sticks to it and runs - height held flat,
## then drooping, for about two seconds. Automatic, like the mantle: no button, and the six
## gates in _wall_run_gates() are the whole feature. See docs/specs/pilot9-wall-run.md.
##
## Every number below is a starting guess exposed as an @export_range, the same promise every
## other verb here makes - found in a play session, not chosen in this file.

@export_group("Wall Run")
## Every gate in the file defaults true except can_auto_slide, and there is no save system to
## gate against yet.
@export var can_wall_run: bool = true
## The floor every wall-run is brought up to - sprint speed, so the grid is 15 m whatever he
## caught the wall at. A faster entry is held, not added to. See wall_run_distance().
@export_range(0.0, 20.0, 0.1) var wall_run_speed: float = 7.5
## How long a slow catch takes to reach wall_run_speed. The wall lifting a jog to a sprint is
## the Titanfall feeling - see "Attach and detach" in the spec.
@export_range(0.0, 2.0, 0.01) var wall_run_speed_ramp: float = 0.25
## Chosen, not derived - it is what makes the grid whole metres: wall_run_speed 7.5 m/s for
## 2.0 s crosses 15 m. See wall_run_distance() and docs/specs/pilot9-jump-grid.md.
@export_range(0.1, 10.0, 0.05) var wall_run_flat_time: float = 2.0
## The tail after the flat portion, over which he droops rather than being dropped by a clock
## the player cannot see. Total attachment is wall_run_flat_time + wall_run_droop_time.
@export_range(0.0, 5.0, 0.05) var wall_run_droop_time: float = 0.8
## Fraction of jump_gravity the droop falls at. At 0.35 over 0.8 s that is ~1.9 m of drop -
## visible without being a fall.
@export_range(0.0, 2.0, 0.01) var wall_run_droop_gravity: float = 0.35
## Under run speed (5.0) with margin over a drift - a wall-run is a run.
@export_range(0.0, 20.0, 0.1) var wall_run_min_speed: float = 4.0
## How far off vertical a face may be and still count, degrees.
@export_range(0.0, 60.0, 1.0) var wall_run_wall_angle: float = 15.0
## Travel vs. the face, at the moment of attach. Wider than the detach angle on purpose - see
## "Attach and detach" in the spec.
@export_range(0.0, 90.0, 1.0) var wall_run_attach_angle: float = 60.0
## How close to dead-on he may hit a wall and still catch a run off it - the remainder of the
## 90 degrees wall_run_attach_angle does not already cover. Dead-on travel has no in-plane
## component to take a tangent from, so this path redirects him along the camera's look
## direction instead of his travel - see "Camera-redirected head-on attach" in the spec.
@export_range(0.0, 90.0, 1.0) var wall_run_head_on_angle: float = 30.0
## The steer-in cone for the top-of-wall mantle off a run (_try_mantle_off_wall_run()). It no
## longer lets go of the wall - see "Committed to the wall" in the spec. Deliberately a
## different number from wall_run_attach_angle - do not collapse them.
@export_range(0.0, 90.0, 1.0) var wall_run_detach_angle: float = 45.0
## Sideways ray length. His capsule is 0.68 m wide.
@export_range(0.1, 3.0, 0.05) var wall_run_probe_reach: float = 0.8
## How fast the run pulls him to the hold distance off the face - the gap divided by this is
## his speed toward it. Perpendicular to the run, so the grid never sees it.
@export_range(0.01, 1.0, 0.01) var wall_run_pull_time: float = 0.1
## How far the face may turn under him, frame to frame, and still be the wall he is running.
## Seams, angled panels and gentle curves carry him along; a sharper turn is the wall ending.
@export_range(0.0, 90.0, 1.0) var wall_run_follow_angle: float = 20.0
## Along the wall normal. 8.5 m/s crosses a 6 m corridor by the jump's apex, so the next wall
## is caught still rising - see "The wall-jump" in the spec.
@export_range(0.0, 20.0, 0.1) var wall_jump_kick: float = 8.5
## Each chained wall-jump's HEIGHT is this times the last's: 3, 1.5, 0.75 m... reset on the
## ground. The series sums to jump_height / (1 - decay) - the +6 m ceiling maps are authored
## against. 1.0 makes every corridor an elevator. See "The bound" and wall_jump_chain_ceiling().
@export_range(0.0, 1.0, 0.01) var wall_jump_chain_decay: float = 0.5
## How long pulling the stick back toward the wall just left takes to win over the kick -
## the deliberate 180. See "Air control after a wall-jump" in the spec.
@export_range(0.0, 2.0, 0.01) var wall_jump_steer_back_ramp: float = 0.4
## After any detach but a wall-jump, dash or mantle, jump is still a wall-jump for this long,
## and does not spend the double jump. See "Wall coyote" in the spec.
@export_range(0.0, 1.0, 0.01) var wall_jump_coyote_time: float = 0.15
## Camera roll toward the wall, degrees, eased at camera_transition_speed. See "The camera"
## in the spec.
@export_range(0.0, 45.0, 0.5) var wall_run_camera_roll: float = 12.0
## The mesh's lean off the wall, degrees: feet toward the face, head out into open air, eased
## at slope_align_speed. See "Sprint cycle on the wall" in the spec.
@export_range(0.0, 60.0, 0.5) var wall_run_lean: float = 30.0
## How far the mesh slides toward the face during a run, metres, eased at slope_align_speed.
## The capsule holds its radius off the wall and the lean pivots at his feet, so without this
## his feet hang ~0.4 m out and he reads as floating. Visual only - the capsule does not move.
@export_range(0.0, 0.5, 0.01) var wall_run_hug: float = 0.25
## The wall-side arm's pose during a run - the RIGHT arm's, the left is mirrored from it. Bone
## name -> Euler degrees, parent-relative, same format as HeldItem.hold_rotations; starts as a
## copy of the staff's running hold, minus the staff. See "The wall hand" in the spec.
@export var wall_hand_rotations: Dictionary[StringName, Vector3] = {
	&"RightShoulder": Vector3(-90, 90, 0),
	&"RightUpperArm": Vector3(63.2, 157.5, -6.7),
	&"RightLowerArm": Vector3(27.7, 90, 0),
	&"RightHand": Vector3(0, -81, 16.7),
}

## Wall-Climb Settings
## -----------------------------------------------------------------------------
## Running dead-on into a wall, he goes up it: a fixed 4 m burst, then a stall and a peel off
## unless a lip, a jump or the wall's top takes him first. Automatic, on the ground or in the
## air - the head-on cone the camera-redirected wall-run used to own. Jump kicks him straight
## back off it, Mario style, so two facing walls are a chimney. See
## docs/specs/pilot9-wall-climb.md.

@export_group("Wall Climb")
@export var can_wall_climb: bool = true
## Travel within this of dead-on into the face climbs it, degrees. Past it (up to
## wall_run_head_on_angle) the camera-redirected wall-run takes the wall instead.
@export_range(0.0, 90.0, 1.0) var wall_climb_angle: float = 15.0
## Metres of height one climb gains, rise and stall together. Arrival speed never changes it -
## a walk-pace catch and an EXIA sprint both climb exactly this. See wall_climb_speed().
@export_range(0.0, 20.0, 0.1) var wall_climb_height: float = 4.0
## The flat-out part of the climb, seconds.
@export_range(0.05, 5.0, 0.05) var wall_climb_rise_time: float = 0.8
## The stall after it: his climb speed eases to zero over this, seconds, and the clip slows with
## it. Part of wall_climb_height, not added to it.
@export_range(0.0, 2.0, 0.01) var wall_climb_stall_time: float = 0.25
## The push off the face when the stall runs out, m/s along the normal.
@export_range(0.0, 10.0, 0.1) var wall_climb_peel_speed: float = 1.0
## Seconds after a climb ends before that same face can be climbed again. Any other wall at once.
@export_range(0.0, 5.0, 0.05) var wall_climb_same_wall_cooldown: float = 1.0
## The clip's rate over the rise - one 2 s loop (two pulls) in the 0.8 s rise at 2.5. Scaled
## down with his speed through the stall, to a freeze.
@export_range(0.0, 10.0, 0.05) var wall_climb_anim_speed: float = 2.5
## BAKED - written by scripts/pilot9_build_scene.gd::_ensure_wall_climb_motion(). The fractions
## of the loop where a hand tops out and takes a hold - one hand tap each.
@export var wall_climb_grab_phases: PackedFloat32Array = PackedFloat32Array()
## BAKED - same bake. The clip's climber leans back off his face (hands far out, toes close in),
## so the mesh is tipped back this many degrees about his feet for the climb - which puts his
## hands and his toes on one vertical plane.
@export var wall_climb_lean: float = 0.0
## BAKED - same bake. That plane, metres in front of his origin once tipped. The mesh slides in
## toward the face by however far short of the wall it is (_wall_climb_hug()).
@export var wall_climb_hand_reach: float = 0.0
## BAKED - same bake. The loop's authored length, seconds - the tap clock runs against it.
@export var wall_climb_duration: float = 0.0

## Rail Grind Settings
## -----------------------------------------------------------------------------
## Falling onto a rail catches him; he rides it at one of two fixed gears in the direction he
## arrived, until he jumps, dashes, crouches or runs off the end. No button, no braking, no
## reversing, and the rail counts as ground for the refills. See docs/specs/pilot9-rail-grind.md.
##
## Every number is a starting guess, found in a play session rather than chosen in this file.

@export_group("Rail Grind")
@export var can_rail_grind: bool = true
## The default gear. 2 x sprint_speed (doubled 2026-09-24); 15 x 1.2 s = 18 m off a rail.
@export_range(0.0, 60.0, 0.1) var rail_grind_speed: float = 15.0
## Sprint held. 20 x 1.2 s = 24 m, a rung only a rail reaches - see rail_jump_distance().
@export_range(0.0, 60.0, 0.1) var rail_sprint_speed: float = 20.0
## How long entry speed, and a gear change, take to reach the gear. Linear, up or down.
@export_range(0.0, 2.0, 0.01) var rail_speed_ease_time: float = 0.25
## Feet to centreline, metres, for a catch.
@export_range(0.05, 2.0, 0.05) var rail_catch_radius: float = 1.0
## The ease of his feet onto the top of the tube after a catch, instead of a teleport.
@export_range(0.0, 0.5, 0.01) var rail_snap_time: float = 0.08
## Seconds before the rail he just left may catch him again. Any OTHER rail catches at once.
@export_range(0.0, 2.0, 0.01) var rail_relatch_lockout: float = 0.3
## Degrees the stick may bend a jump or a dash off the ride tangent. Speed never changes.
@export_range(0.0, 90.0, 1.0) var rail_jump_max_bend: float = 45.0
## A jump pressed this long after running off the end is still the full rail jump. Its own
## dial because the global coyote_time ships at 0.0.
@export_range(0.0, 1.0, 0.01) var rail_coyote_time: float = 0.15
## After a rail launch lands, seconds his speed takes to ease (smoothstep) from the landing speed
## down to what the stick asks for. He loses none of it in the air. 0 snaps.
@export_range(0.0, 2.0, 0.05) var rail_land_ease_time: float = 0.5
## Look input idle this long before the camera starts swinging behind the ride.
@export_range(0.0, 3.0, 0.05) var rail_camera_idle_delay: float = 0.3
## The swing's top speed, yaw only, degrees per second.
@export_range(0.0, 720.0, 5.0) var rail_camera_swing_rate: float = 90.0
## Degrees he leans into a bend on a rail, at full. Straight rail, none. 0 turns it off.
@export_range(0.0, 30.0, 0.5) var rail_lean_max: float = 20.0
## How tight a bend earns the full lean: degrees of heading change per metre of rail. Gentler
## bends lean in proportion. 6 deg/m is a radius of about 9.5 m.
@export_range(0.5, 45.0, 0.5) var rail_lean_full_turn: float = 6.0

@export_group("Rail Switch")
## A rail jump with the stick pushed toward another rail within reach hops onto it - a scripted
## flight that lands every time. Off: every rail jump is the ordinary one. See "Rail to rail" in
## docs/specs/pilot9-rail-grind.md.
@export var can_rail_switch: bool = true
## Degrees the stick must sit off the ride tangent to aim a switch. Less is the ordinary jump.
@export_range(0.0, 90.0, 1.0) var rail_switch_min_angle: float = 30.0
## Flat metres from the ride-on point (where riding straight on would put him) to the target.
@export_range(0.5, 20.0, 0.1) var rail_switch_reach: float = 6.0
## The hop's length in seconds.
@export_range(0.1, 1.5, 0.01) var rail_switch_time: float = 0.4
## The bump at mid-flight, over the straight line (plus half any height difference).
@export_range(0.0, 4.0, 0.05) var rail_switch_arc_height: float = 1.0
## How far above / below his feet a target may be.
@export_range(0.0, 6.0, 0.1) var rail_switch_max_rise: float = 2.0
@export_range(0.0, 12.0, 0.1) var rail_switch_max_drop: float = 4.0

## The afterimages
## -----------------------------------------------------------------------------
## The Sandevistan trail: frozen flat-colour copies of him, dropped by distance, held for the
## dash and cleared tail to head after it. Replaced the manga speed lines on 2026-09-28 (commit
## c36e25e is the last build with them). Drawn by scripts/pilot9_afterimage.gd. See
## docs/specs/pilot9-dash.md, "The afterimages".

@export_group("Afterimage")
## Playback rate of the forced sprint cycle during the dash. 2.5x runs about one full stride in
## the 0.25 s window, so every ghost has different legs; at 1.0 they all look alike.
@export_range(0.5, 6.0, 0.1) var dash_anim_speed: float = 2.5
## Clip second the sprint cycle starts from on every dash, so the trail's leg pattern is the same
## each time and can be tuned.
@export_range(0.0, 2.0, 0.01) var dash_anim_phase: float = 0.0
## Metres between ghosts. 1.6 on a 10 m dash is six ghosts: 0, 1.6 ... 8.0 m.
@export_range(0.3, 5.0, 0.05) var afterimage_spacing: float = 1.6
@export_range(1, 16) var afterimage_max_count: int = 6
## The newest ghost's colour - the one at his heels.
@export var afterimage_head_color: Color = Color(0.30, 0.90, 1.00)
## The colour afterimage_max_count - 1 ghosts back.
@export var afterimage_tail_color: Color = Color(0.35, 1.00, 0.45)
## The ink is the fill times this: the same hue, darker.
@export_range(0.0, 1.0, 0.01) var afterimage_line_darken: float = 0.45
## How see-through a ghost is, fill and ink alike: 1.0 solid, 0.5 half.
@export_range(0.05, 1.0, 0.01) var afterimage_opacity: float = 0.2
## Seconds from the dash's end until the last (newest) ghost is gone.
@export_range(0.05, 2.0, 0.01) var afterimage_clear_time: float = 1.0
## Seconds one ghost's dissolve takes. The gap between ghosts starting is what is left over.
@export_range(0.01, 1.0, 0.01) var afterimage_fade_time: float = 0.3

@export_group("Rim Light")
## The one-sided white edge light, after the Marvel Rivals renders. pilot9 only - it rides on
## his meshes as a material_overlay, so the map and the cel base shader never see it. Tune the
## look on the material itself. See docs/specs/pilot9-rim-light.md.
@export var rim_light_enabled: bool = false:
	set(value):
		rim_light_enabled = value
		if is_node_ready():
			_apply_rim_light()
@export var rim_light_material: Material = preload("res://resources/pilot_rim_light.tres"):
	set(value):
		rim_light_material = value
		if is_node_ready():
			_apply_rim_light()
## Set by PixelLook while LOOK is PIXEL: the rim is a cel graphic and stays off there whatever
## rim_light_enabled says. See docs/specs/pixel-look.md.
var rim_light_suppressed := false:
	set(value):
		if rim_light_suppressed == value:
			return
		rim_light_suppressed = value
		if is_node_ready() and rim_light_enabled:
			_apply_rim_light()

@export_group("Poncho")
## The wool poncho in the scarf's red: a stiff shell over his shoulders and torso that lags, settles
## and lifts a little with what he does. Built in code by scripts/pilot9_poncho.gd. Off by default;
## trial's Pilot9 turns it on (not the second pilot, Ichi or the cutscenes). The PONCHO settings row
## hides it live. See docs/specs/pilot9-poncho.md.
@export var poncho_enabled: bool = false
## Natural frequency of the pull back to its tailored shape, at the hem. Higher is stiffer.
@export_range(0.5, 6.0, 0.05) var poncho_stiffness: float = 2.2
## Damping ratio of that pull: 1.0 never overshoots, lower bounces more.
@export_range(0.05, 1.5, 0.01) var poncho_damping: float = 0.55
## How hard neighbouring points are pulled into line each substep - the "thick" in thick wool.
@export_range(0.0, 0.9, 0.01) var poncho_bend: float = 0.3
## Most acceleration the cloth ever feels, m/s^2. Caps every lag and bounce.
@export_range(1.0, 100.0, 0.5) var poncho_max_accel: float = 20.0
## Most sudden velocity change it feels, m/s: the rest of a landing or dash launch is not felt.
@export_range(0.0, 10.0, 0.05) var poncho_max_jolt: float = 1.0
## Speed at which the wind's lift is full, m/s. Faster adds nothing.
@export_range(1.0, 60.0, 0.5) var poncho_wind_full_speed: float = 20.0
## Hem lift at full wind, degrees.
@export_range(0.0, 60.0, 0.5) var poncho_wind_max_lift: float = 18.0
## Wool thickness, metres.
@export_range(0.002, 0.08, 0.001) var poncho_thickness: float = 0.008

@export_group("Body")
## A different body on the same rig: a GLB exported from the same Blender armature (same bone
## names). Its skinned meshes replace the ones in pilot9.tscn at _ready(); every animation, verb
## and effect is untouched. Empty keeps the scene's own meshes. See docs/specs/pilot-switch.md.
@export var body_glb: PackedScene = null

@export_group("Held Item")
## What he spawns carrying, holstered on his back. Empty is the no-item case: `equip` does
## nothing. A pickup later calls set_item(). See docs/specs/pilot9-held-item.md.
@export var starting_item: HeldItem = preload("res://resources/items/staff.tres")

@export_group("Tredge")
## The blizzard walk: out in a Storm's snow he can only tredge. See docs/specs/pilot9-tredge.md
## and scripts/pilot9_tredge.gd.
## Flat tredge speed, m/s (walk is walk_speed).
@export_range(0.1, 5.0, 0.05) var tredge_speed: float = 1.5
## How much of tredge_speed a gust's peak takes away: 0.4 leaves 60%.
@export_range(0.0, 0.9, 0.01) var tredge_gust_slow: float = 0.4
## rotation_speed is multiplied by this while tredging.
@export_range(0.05, 1.0, 0.05) var tredge_turn_scale: float = 0.5
## The tredge cycle's rate at tredge_speed; it follows his actual speed from there.
@export_range(0.1, 2.0, 0.05) var tredge_clip_rate_at_speed: float = 0.7
## Seconds the pose takes each way (the state machine's crossfade is built at 0.5 s).
@export_range(0.0, 2.0, 0.05) var tredge_blend_time: float = 0.5
## Seconds he has to be covered or exposed before the switch flips.
@export_range(0.0, 2.0, 0.05) var tredge_debounce: float = 0.25
## How fast his speed eases toward the tredge's, m/s^2 - into a gust's dip, out of it, and down
## from a run carried out of the building. The tredge keeps no momentum.
@export_range(0.5, 30.0, 0.5) var tredge_speed_rate: float = 6.0
## How far the staff slides along its +Y through his fist for the torch grip, metres. Negative
## slides it down, so he holds it higher: -0.4 puts his fist 3/4 of the way up the 1.6 m staff.
@export_range(-0.8, 0.8, 0.01) var tredge_grip_slide: float = -0.4

## Movement effects
## -----------------------------------------------------------------------------
## Grind sparks and their light, the ground-jump dust, the double-jump air burst and the
## landing dust - classic particles, all built in scripts/pilot9_vfx.gd and read from here at
## the moment of use. MOVEMENT EFFECTS in the settings screen switches the lot off. Every
## number is a starting dial. See docs/specs/pilot9-movement-vfx.md.

@export_group("Movement Effects")
@export var vfx_spark_color: Color = Color(1.0, 0.6, 0.18)
## Sparks per second at the rail-sprint gear. Fixed when the pilot is built.
@export_range(1.0, 400.0, 1.0) var vfx_spark_rate: float = 90.0
## The grind gear's density, as a fraction of the sprint gear's.
@export_range(0.0, 1.0, 0.05) var vfx_spark_grind_density: float = 0.55
## Metres per second a spark leaves at, at the rail-sprint gear.
@export_range(0.0, 20.0, 0.1) var vfx_spark_speed: float = 7.0
## The grind gear's spray speed, as a fraction of the sprint gear's - a shorter shower.
@export_range(0.0, 1.0, 0.05) var vfx_spark_grind_speed: float = 0.7
## Seconds a spark lives. Fixed when the pilot is built for the stream; bursts read it live.
@export_range(0.05, 2.0, 0.01) var vfx_spark_lifetime: float = 0.35
## Sparks thrown by catching a rail, and by a rail switch landing.
@export_range(0, 200) var vfx_spark_catch_count: int = 45
@export_range(0, 200) var vfx_spark_switch_count: int = 18
## The flicker at his feet while grinding. 0 energy turns it off.
@export_range(0.0, 8.0, 0.05) var vfx_spark_light_energy: float = 1.6
@export_range(0.1, 6.0, 0.05) var vfx_spark_light_range: float = 1.8
## Dust - the ground jump and the landing share it.
@export var vfx_dust_color: Color = Color(0.64, 0.58, 0.5, 0.75)
## Metres per second a puff spreads at. Damped, so it slows to a stop.
@export_range(0.0, 10.0, 0.1) var vfx_dust_speed: float = 2.5
@export_range(0.05, 2.0, 0.01) var vfx_dust_lifetime: float = 0.3
@export_range(1, 64) var vfx_jump_dust_count: int = 10
## Puffs each side of him at a full jump's landing; fewer below it.
@export_range(1, 32) var vfx_land_side_count: int = 4
## The ring's puffs at max_fall_speed; it only exists above a full jump's landing.
@export_range(0, 64) var vfx_land_ring_count: int = 18
## Metres per second the dust trails back when he lands into a slide.
@export_range(0.0, 20.0, 0.1) var vfx_land_slide_skew: float = 4.0
## The double jump's air - ring and wind streaks.
@export var vfx_air_color: Color = Color(0.85, 0.93, 1.0, 0.8)
## Metres across the ring grows to.
@export_range(0.2, 6.0, 0.05) var vfx_air_ring_size: float = 1.8
@export_range(0.05, 2.0, 0.01) var vfx_air_lifetime: float = 0.4
@export_range(0, 32) var vfx_air_streaks: int = 7
## Pass 2 - the speed lasers. Horizontal m/s they come on above and go off below (the gap stops
## them flickering right at sprint_speed), and the speed they are heaviest at. Off during a dash.
@export_range(0.0, 40.0, 0.1) var vfx_laser_on_speed: float = 8.5
@export_range(0.0, 40.0, 0.1) var vfx_laser_off_speed: float = 8.0
@export_range(0.0, 60.0, 0.5) var vfx_laser_full_speed: float = 20.0
## Seconds they take to ease in (the rate climbs) on crossing the on-speed.
@export_range(0.0, 1.0, 0.01) var vfx_laser_fade_in: float = 0.15
@export var vfx_laser_color: Color = Color(1.0, 1.0, 1.0, 0.25)
## Bolts fired a second at the on-speed and at full speed.
@export_range(0.0, 120.0, 0.5) var vfx_laser_rate_min: float = 6.0
@export_range(0.0, 120.0, 0.5) var vfx_laser_rate_max: float = 25.0
## A bolt's full length in metres at the on-speed and at full speed (each bolt varies a bit).
@export_range(0.1, 10.0, 0.05) var vfx_laser_length_min: float = 1.5
@export_range(0.1, 10.0, 0.05) var vfx_laser_length_max: float = 4.0
## A bolt's width at its middle, metres; it is pointed at both ends.
@export_range(0.005, 0.5, 0.005) var vfx_laser_width: float = 0.05
## Seconds a bolt lives, and the m/s it flies back through the world at.
@export_range(0.05, 2.0, 0.01) var vfx_laser_lifetime: float = 0.25
@export_range(0.0, 80.0, 0.5) var vfx_laser_speed: float = 16.0
## Degrees the cone flares outward from straight back, at the on-speed and at full speed.
@export_range(0.0, 60.0, 0.5) var vfx_laser_flare_min: float = 15.0
@export_range(0.0, 60.0, 0.5) var vfx_laser_flare_max: float = 20.0
## The ring the bolts fire from: its radius, how far behind his back, and how high off his feet.
@export_range(0.0, 2.0, 0.01) var vfx_laser_ring_radius: float = 0.35
@export_range(0.0, 2.0, 0.01) var vfx_laser_behind: float = 0.35
@export_range(0.0, 2.5, 0.01) var vfx_laser_chest_height: float = 1.2
## Metres no bolt ever comes to the camera - a bolt aimed closer is re-rolled.
@export_range(0.0, 3.0, 0.05) var vfx_laser_camera_clear: float = 0.6
## The on-speed's opacity, as a fraction of full.
@export_range(0.0, 1.0, 0.05) var vfx_laser_min_opacity: float = 0.5
## Slide sparks - the grind stream's twin. Stops below this horizontal m/s.
@export_range(0.0, 20.0, 0.1) var vfx_slide_spark_min_speed: float = 3.0
## Sparks thrown the moment a slide starts.
@export_range(0, 200) var vfx_slide_entry_count: int = 20
## The slide's foot light, as a fraction of the grind light.
@export_range(0.0, 2.0, 0.05) var vfx_slide_light_scale: float = 0.6
## Wall-run dust per second. Fixed when the pilot is built.
@export_range(1.0, 200.0, 1.0) var vfx_wall_dust_rate: float = 30.0
## Puffs in a wall-jump's ring (the push-out puff is half this; a wall attach, half again).
@export_range(1, 64) var vfx_wall_kick_count: int = 12
## Puffs under each hand on a mantle or vault plant, and how long they last.
@export_range(1, 32) var vfx_hand_tap_count: int = 4
@export_range(0.05, 1.0, 0.01) var vfx_hand_tap_lifetime: float = 0.25
## Puffs in the kick when he breaks into a sprint, and in a hard-turn skid.
@export_range(1, 64) var vfx_sprint_kick_count: int = 6
@export_range(1, 64) var vfx_skid_count: int = 10
## A hard turn: travel swinging more than this many degrees inside the window, at
## vfx_skid_min_speed_fraction of sprint_speed or more both then and now.
@export_range(10.0, 180.0, 1.0) var vfx_skid_angle: float = 100.0
@export_range(0.05, 1.0, 0.01) var vfx_skid_window: float = 0.2
@export_range(0.0, 2.0, 0.05) var vfx_skid_min_speed_fraction: float = 0.8
## At most one sprint kick or skid per this many seconds.
@export_range(0.0, 3.0, 0.05) var vfx_kick_cooldown: float = 0.5

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
## Furthest the camera may look UP, radians. GTA V's own limit; a steeper one swings the lens
## round to the sky and loses him. See docs/specs/pilot9-gta-camera.md.
@export_range(0.0, 1.57, 0.01) var tilt_up_limit: float = deg_to_rad(45)
## Furthest the camera may look DOWN, radians. Deeper than up because a platformer looks at
## its feet more than at the sky.
@export_range(0.0, 1.57, 0.01) var tilt_down_limit: float = deg_to_rad(60)
## The stick's response curve exponent: the stick's deflection (past the action's own 0.2
## deadzone) is raised to this, so small pushes turn slowly and a full push turns fast. 1.0 is
## linear. Mouse look is never curved.
@export_range(1.0, 3.0, 0.1) var look_stick_curve: float = 1.6
## Seconds a held full-deflection stick takes to reach full turn speed. 0.0 turns the ramp off.
@export_range(0.0, 1.0, 0.05) var look_stick_ramp_time: float = 0.3
## The fraction of full turn speed a full push starts at before the ramp lifts it.
@export_range(0.1, 1.0, 0.05) var look_stick_ramp_start: float = 0.5
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
@export_range(0.0, 10.0, 0.1) var camera_distance: float = 2.5
## Closest the scroll wheel can pull the camera in, metres. Kept above 30% of
## camera_distance (0.75 m), the line under which his body hides for first person.
## See docs/specs/pilot9-camera-zoom.md.
@export_range(0.5, 10.0, 0.1) var camera_zoom_min: float = 1.5
## Furthest the scroll wheel can push the camera out, metres.
@export_range(1.0, 20.0, 0.1) var camera_zoom_max: float = 8.0
## Metres per wheel notch.
@export_range(0.05, 2.0, 0.05) var camera_zoom_step: float = 0.5
## Where he sits on screen at full zoom-out, as a fraction of the screen from the top (0.5 is
## dead centre). The camera tilts up as it pulls back to hold him there instead of letting him
## drift to the middle. Full zoom-in is left exactly as it frames on its own - the tilt blends
## from that toward this. See "Framing" in docs/specs/pilot9-camera-zoom.md.
@export_range(0.5, 0.9, 0.01) var camera_zoom_out_screen_height: float = 0.68
## Metres the camera rises at full zoom-out, blended from camera_zoom_in_lift at full zoom-in.
## See "Framing" in docs/specs/pilot9-camera-zoom.md.
@export_range(0.0, 2.0, 0.05) var camera_zoom_out_lift: float = 0.1
## Metres the camera rises at full zoom-in - negative, so it drops and he sits nearer the middle
## of the screen up close. Fades to nothing on the way into first person.
## See "Framing" in docs/specs/pilot9-camera-zoom.md.
@export_range(-0.5, 0.5, 0.05) var camera_zoom_in_lift: float = -0.3
## Speed at which the camera transitions between modes.
@export_range(1.0, 20.0, 0.1) var camera_transition_speed: float = 8.0
## Allow switching between camera modes with V key.
@export var allow_camera_mode_switch: bool = false
## Degrees added to the camera's FOV while he is sprinting. Rides on top of the player's own
## FOV setting rather than replacing it - see `base_fov`. 0.0 is the off switch, and the whole
## feature costs one lerp a frame when it is off.
@export_range(0.0, 40.0, 0.5) var sprint_fov_boost: float = 10.0
## Speed at which the FOV eases between the base and the sprint boost. Deliberately the same
## dial and the same shipping value as camera_transition_speed above, so the lens and the
## spring arm move at a rate the player reads as one camera rather than two.
@export_range(1.0, 20.0, 0.1) var fov_transition_speed: float = 8.0
## Degrees the dash kicks the lens open, on top of whatever the sprint boost is doing. Ground
## and air alike. 0.0 is the off switch. See docs/specs/pilot9-dash-fov.md.
@export_range(0.0, 30.0, 0.5) var dash_fov_boost: float = 10.0
## Seconds from the launch to the full kick. Short on purpose: the dash itself is only
## `dash_time` long, and a slower open would still be opening when he reappears.
@export_range(0.0, 0.5, 0.01) var dash_fov_rise_time: float = 0.12
## Seconds from the dash's end back to no kick. The long half, and where the smoothness lives -
## it runs well past the dash, which is the "faster than you are" read.
@export_range(0.0, 2.0, 0.05) var dash_fov_release_time: float = 0.6
## The lens the kick will not push past. Limits the kick only - never the sprint boost or the
## player's own FOV setting. Only engages near the top of the FOV row.
@export_range(60.0, 170.0, 1.0) var dash_fov_ceiling: float = 115.0
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
## How long the dash's camera lag holds at its launch position before it starts gliding
## toward him, in real seconds. See _camera_dash_lag_position() and docs/specs/pilot9-dash.md,
## Camera. 0.0 is the original behaviour - the glide starts the instant he vanishes.
@export_range(0.0, 0.5, 0.01) var camera_dash_lag_delay: float = 0.05
## How long the glide itself takes once the delay above has elapsed, in real seconds -
## independent of `dash_time` now, on purpose, so the catch-up can be tuned slower than the
## dash without also retuning the dash. Together with `camera_dash_lag_delay` this can run
## past `dash_time`, in which case the shot is still visibly gliding onto him for a beat after
## he has already reappeared - see _camera_dash_lag_position().
@export_range(0.05, 1.5, 0.01) var camera_dash_lag_time: float = 0.3
## How far the third-person camera sits to one side of him, metres, at full zoom-out from first
## person. See docs/specs/pilot9-camera-shoulder.md.
@export_range(0.0, 2.0, 0.05) var camera_shoulder_offset: float = 0.8
## Metres the pivot is raised above the old chest-height anchor, so the camera orbits his head
## the way GTA's does. Fades out into first person with the zoom lift. See
## docs/specs/pilot9-gta-camera.md.
@export_range(0.0, 1.0, 0.05) var camera_pivot_raise: float = 0.4
## Metres the camera pulls back while he sprints or dashes.
@export_range(0.0, 1.0, 0.05) var camera_sprint_pullback: float = 0.3
## Metres the pivot drops while he crouches or slides.
@export_range(0.0, 1.0, 0.05) var camera_crouch_drop: float = 0.4
## Seconds for either of those to ease fully in or out - never cut.
@export_range(0.05, 1.0, 0.01) var camera_state_ease_time: float = 0.3
## Seconds for the camera to slide across on a swap, and on the wall-run's own side change.
@export_range(0.05, 1.0, 0.01) var camera_shoulder_swap_time: float = 0.25
## The run/sprint sway and the landing dip. See docs/specs/pilot9-camera-sway.md. Every
## metre here is at the 3.5 m arm - the motion is scaled by the live arm length over
## `camera_distance` so it reads the same size at every zoom. CAMERA MOTION in the settings
## screen switches the whole group off.
##
## Vertical bob at a full sprint, metres - one dip per footfall.
@export_range(0.0, 0.1, 0.001) var camera_sway_vertical: float = 0.0075
## Side-to-side at a full sprint, metres - one swing per stride, half the bob's rate.
@export_range(0.0, 0.1, 0.001) var camera_sway_lateral: float = 0.005
## Roll at a full sprint, degrees, in phase with the lateral swing. Added to the wall-run roll.
@export_range(0.0, 5.0, 0.05) var camera_sway_roll: float = 0.2
## The sway at a run (`speed`), as a fraction of the sprint's.
@export_range(0.0, 1.0, 0.05) var camera_sway_run_fraction: float = 0.4
## Seconds for the sway to fade fully in or out - never cut.
@export_range(0.01, 1.0, 0.01) var camera_sway_fade_time: float = 0.2
## Downward speed at impact under which a landing gets no dip at all, m/s.
@export_range(0.0, 20.0, 0.5) var landing_dip_min_speed: float = 5.0
## Dip depth at a full jump's landing speed, metres.
@export_range(0.0, 0.6, 0.005) var landing_dip_full_jump: float = 0.15
## Dip depth at `max_fall_speed` and above, metres.
@export_range(0.0, 0.6, 0.005) var landing_dip_max: float = 0.3
## Seconds from touchdown to the bottom of the dip. Sets the spring's stiffness; the settle
## back is critically damped, so it never rebounds above rest.
@export_range(0.02, 0.5, 0.01) var landing_dip_time: float = 0.1

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

## get_real_velocity() below this fraction of dash_speed, measured AFTER move_and_slide(),
## means something stopped him rather than him having simply not reached full speed yet -
## see _check_dash_blocked(). One velocity comparison catches walls, corners, slope
## shoulders and ceilings without any normal math.
const DASH_BLOCKED_SPEED_FRACTION := 0.5

## Height above his feet the two sideways wall-run rays fire from - see _probe_wall(). Roughly
## his torso, so it meets a wall the way a running body actually would.
const WALL_RUN_PROBE_HEIGHT := 1.0
## The second sustain ray, near his feet. Keeps a run alive where the torso ray finds a gap - a
## window, or the top of a short wall he has risen past. See _probe_wall_side().
const WALL_RUN_LOW_PROBE_HEIGHT := 0.3
## Skin between his capsule and the face while running - see _wall_run_hold_distance().
const WALL_RUN_HOLD_MARGIN := 0.05
## Gate 5's tolerance: travel·normal over this is "moving away from the face". Near zero on
## purpose - travel exactly along the face must still attach. See _wall_run_gates().
const WALL_RUN_AWAY_EPSILON := 0.001
## Metres from the wrist bone to the fingertips' contact - taken off the wall climb's hug so the
## palms, not the wrists, meet the face.
const WALL_CLIMB_PALM := 0.08
## Two faces are the same wall for the let-go lockout when their normals agree to within ~8
## degrees and their planes are within this many metres. See _same_wall().
const WALL_SAME_FACE_DOT := 0.99
const WALL_SAME_PLANE_DISTANCE := 0.25

## The group every Rail puts itself in - scripts/rail.gd's GROUP, restated rather than read so
## this file never names that class.
const RAIL_GROUP := &"rails"
## Horizontal m/s under which a catch is "a vertical drop onto it" and his facing picks the
## ride direction instead of his travel.
const RAIL_DIR_MIN_SPEED := 0.5
## How far off square across the rail his facing or the camera must point to pick the ride's
## direction when his momentum along it doesn't - the cosine of 80 degrees. Squarer than that
## is the same coin toss the momentum was.
const RAIL_DIR_MIN_ALIGN := 0.17
## Metres from an open end inside which a catch that would ride straight off that end is
## refused. Without it, brushing the tip of a rail on the way past is a free refill.
const RAIL_END_MARGIN := 0.1
## The catch is swept, not sampled - see _rail_sweep_points(). Metres between the points tested
## along the path his feet took since last frame: well inside the catch zone's depth anywhere
## but its very rim, so no fall speed can step over it.
const RAIL_SWEEP_STEP := 0.05
## Metres of path beyond which last frame's feet are not where he came from but a teleport
## (a respawn, a scripted placement), and only where he is now is tested. max_fall_speed at
## 60 Hz is under half a metre a frame.
const RAIL_SWEEP_MAX := 2.0
## Metres either side of him the curve lean reads the ride tangent at. Wide enough that the
## baked curve's point spacing does not flicker it, short enough that he leans as the bend comes.
const RAIL_LEAN_SAMPLE := 0.75
## Metres a switch target must sit off his straight-on line, to the stick's side - so the rail
## he is on, or one running on in line with it, is never a switch.
const RAIL_SWITCH_MIN_SIDE := 0.5
## How much of his vertical speed turns the lasers' cone - a steep fall aims them up only
## partly, so they still read as speed rather than a column.
const LASER_VERTICAL := 0.5
## Metres ahead of his origin along his travel the slide sparks come off - the leading foot.
const SLIDE_SPARK_LEAD := 0.4
## Metres either side of the lip/top point the two hand taps land.
const HAND_TAP_HALF_SPREAD := 0.2

## Why a grind ended. Every exit starts the same-rail lockout; only END opens the rail coyote.
enum RailExit { JUMP, DASH, CROUCH, END, BOARD, LOST }

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

## True for the length of a vault. Read by the AnimationTree's advance expressions - the same
## "a misspelt name never fires and never complains" warning as is_climbing. Only ever set by
## _start_vault(), which cannot run unless a grounded `jump` press found a qualifying top.
var is_vaulting: bool = false
## Clip fraction, 0..1. Advanced in _apply_vault_motion() at _vault_rate; also the clip's clock -
## pilot9_animation.gd seeks the `vault` state onto vault_clip_time() every frame.
var _vault_u: float = 0.0
## Clip fraction per second: (entry speed / vault_clip_speed) / vault_duration.
var _vault_rate: float = 0.0
## Straight across the obstacle (-face normal, flat), fixed at the press. The whole vault runs
## along it and the mesh is welded to it.
var _vault_dir: Vector3 = Vector3.ZERO
## Where he stood on the press frame. Every path sample is an offset from here.
var _vault_start: Vector3 = Vector3.ZERO
## Entry speed along _vault_dir, floored at `speed`. Also the exit speed.
var _vault_speed: float = 0.0
## This vault's corrections to the authored path - see _vault_offset().
var _vault_dh: float = 0.0
var _vault_dz: float = 0.0
## Past the hand release: collision is back on and the path runs through move_and_slide().
var _vault_released: bool = false
## _vault_u at the previous physics tick - the clip is seeked between the two, see _seek_vault_clip().
var _vault_u_prev: float = 0.0
## A `jump` pressed before the release, spent on the release frame.
var _vault_jump_buffered: bool = false
## A `crouch` pressed during the vault, spent on the exit: a slide if _can_start_slide() agrees
## on the landing, the ordinary air buffer if the vault ends in a fall.
var _vault_slide_buffered: bool = false
## The landing floor above his start (negative below), from the press's landing ray. The release
## never places him under it.
var _vault_land_rise: float = 0.0

## True for the length of a wall-run. Read by _apply_wall_run_velocity(), by
## _align_model_to_slope() for the mesh roll, and by _handle_camera_transition() for the
## camera roll. See docs/specs/pilot9-wall-run.md.
var is_wall_running: bool = false
## The face's normal at attach, stored rather than re-probed every frame so the roll and the
## camera stay put even on a frame the probe happens to graze a seam.
var _wall_normal: Vector3 = Vector3.ZERO
## Seconds into the current wall-run, flat portion and droop together. Compared against
## wall_run_flat_time and wall_run_flat_time + wall_run_droop_time.
var _wall_run_time: float = 0.0
## The tangent to the wall his travel was projected onto at attach - _apply_wall_run_velocity()
## drives him along this and nothing steers it once the run has started. Same discipline
## _slide_direction and _climb_facing already follow: one source for a facing at a time.
var _wall_run_direction: Vector3 = Vector3.ZERO
## The ALONG-WALL part of his speed at attach - the part into the face is dropped, or chains
## would snowball. _wall_run_speed_at() ramps it up to wall_run_speed; above that it is held.
var _wall_run_speed: float = 0.0
## A point on the face at attach. With _wall_normal it is the plane _same_wall() compares a
## later attach against - see _wall_lockout_normal.
var _wall_point: Vector3 = Vector3.ZERO
## False while he is still finishing the jump he attached on - velocity.y then falls under
## jump_gravity. True once it reaches zero (or at once, if he caught the wall falling), and
## from then the flat hold and the droop own velocity.y. See "Rise, then flat, then droop".
var _wall_run_leveled: bool = false
## Which side the wall is on for the current run, set once in _start_wall_run() - see
## wall_run_on_right().
var _wall_run_right: bool = true
## Wall-jumps already taken this flight - the `n` in wall_jump_height_for(). Zeroed on every
## grounded frame beside _air_jumps_left. See "The bound" in the spec.
var _wall_jumps_taken: int = 0
## Seconds left of the wall-jump's push protection - the away-from-wall part of his velocity
## is held at wall_jump_kick unless the stick pulls back against it. 0 = none. Ends on
## attach, landing, a dash, or after jump_air_time. See _apply_movement().
var _wall_jump_push_time: float = 0.0
## Seconds the stick has been pulling back toward the wall just left, during push protection.
## Its ratio to wall_jump_steer_back_ramp is the stick's authority over the away component.
var _wall_jump_steer_back: float = 0.0
## Seconds of wall coyote left: a jump inside it is a wall-jump off _wall_jump_normal, and
## costs no double jump. Opened by every detach except a wall-jump, a dash or a mantle.
var _wall_coyote_left: float = 0.0
## The face a let-go (timer, wall end) left him beside. Gate 5 cannot refuse
## that face - his travel is still along it, not away - so without this a
## timed-out run re-grabs the same wall on the very next frame. Cleared by a wall-jump (so the
## 180 onto the same wall still attaches), by attaching any other face, and by the ground.
## Not in the spec's gates; added in the 2026-09-23 build - see "Built" in the spec.
var _wall_lockout_normal: Vector3 = Vector3.ZERO
var _wall_lockout_point: Vector3 = Vector3.ZERO
## Seconds the lockout above has left. INF = until the ground or a wall-jump clears it.
var _wall_lockout_left: float = 0.0
## Why a run let go - decides the lockout. See _wall_lockout_time_for().
enum WallLetGo { TIMER, WALL_ENDED }
## His centre's distance from the face, measured by the sustain probe each run frame (and at
## attach). _apply_wall_run_velocity() pulls it toward _wall_run_hold_distance().
var _wall_run_gap: float = 0.0
## A `jump` pressed mid-run. Spent by _handle_gravity_and_jump() on the same frame, one call
## later - the same handoff _climb_jump_buffered uses, and for the same reason:
## _handle_wall_run() runs ahead of gravity and cannot apply the jump itself without gravity
## then running straight over it this same frame.
var _wall_jump_buffered: bool = false
## The wall normal the buffered jump kicks off, captured at the press because is_wall_running
## (and _wall_normal with it) is already cleared by the time the buffer is spent.
var _wall_jump_normal: Vector3 = Vector3.ZERO

## The wall climb - see docs/specs/pilot9-wall-climb.md.
var is_wall_climbing: bool = false
var _wall_climb_time: float = 0.0
## The face he is on, refreshed every frame from the sustain ray like the wall-run's.
var _wall_climb_normal: Vector3 = Vector3.ZERO
var _wall_climb_point: Vector3 = Vector3.ZERO
var _wall_climb_gap: float = 0.0
## The face just left and how long until it can be climbed again. Any other face is open.
var _wall_climb_lock_normal: Vector3 = Vector3.ZERO
var _wall_climb_lock_point: Vector3 = Vector3.ZERO
var _wall_climb_lock_left: float = 0.0
## Set by the press in _handle_wall_climb(), spent in _handle_gravity_and_jump() - the
## _wall_jump_buffered split, for the same reason.
var _wall_climb_jump_buffered: bool = false
## The face a climb jump kicks off - the buffered one, or the coyote one after a peel.
var _wall_climb_jump_normal: Vector3 = Vector3.ZERO
var _wall_climb_coyote_left: float = 0.0
## The loop position, in loop fractions, where the last hand tap was checked - see
## _emit_wall_climb_taps().
var _wall_climb_phase: float = 0.0

## True for the length of a grind. Read by the AnimationTree's advance expressions, so the same
## warning as is_sliding applies. See docs/specs/pilot9-rail-grind.md.
var is_rail_grinding: bool = false
## The gear - sprint held. Drives the grind/sprint clip blend in scripts/pilot9_animation.gd.
var is_rail_sprinting: bool = false
## The Rail ridden. Untyped on purpose: pilot9 duck-types rail.gd rather than naming its class.
var _rail = null
## Where he is along the curve, curve-local metres - never a world position, which is the whole
## of what lets a moving rail carry him. See rail.gd's header.
var _rail_offset: float = 0.0
## +1 / -1 along the curve, latched at attach and never changed. See _rail_ride_dir().
var _rail_dir: int = 1
## Speed along the rail this frame, and the linear ease it is on: from `_rail_speed_from` to
## `_rail_speed_to` over rail_speed_ease_time, restarted by the catch and by a gear change.
var _rail_speed: float = 0.0
var _rail_speed_from: float = 0.0
var _rail_speed_to: float = 0.0
var _rail_ease_time: float = 0.0
## Seconds of the entry snap left, and where his feet were relative to the tube top at the
## catch - that offset shrinks to nothing across the snap. Relative, so a moving rail still
## lands him on the tube rather than on where the tube was.
var _rail_snap_left: float = 0.0
var _rail_snap_offset: Vector3 = Vector3.ZERO
## The rail he last left, and how long before it may catch him again.
var _rail_last = null
var _rail_lockout_left: float = 0.0
## Where his feet were at last frame's catch test, and whether that test ran - the start of this
## frame's sweep. Any frame the catch does not run (ground, dash, climb, a ride) breaks the chain.
var _rail_sweep_from: Vector3 = Vector3.ZERO
var _rail_sweep_valid: bool = false
## The rail coyote: seconds left, and the launch the late jump takes - the end tangent (ride
## direction applied) and the speed he ran off at.
var _rail_coyote_left: float = 0.0
var _rail_coyote_tangent: Vector3 = Vector3.ZERO
var _rail_coyote_speed: float = 0.0
## Seconds since the last look input, mouse or stick - the camera swing-behind's clock.
var _rail_camera_idle: float = 0.0
## Set by every rail exit that launches him (the end, the jump, the rail coyote, crouch) through
## _start_rail_launch_carry(): until he lands, the stick drives him at the ride's speed in any
## direction it points. It is a speed, not momentum - a released stick brakes like any other
## jump. See _apply_stick_movement() and "Rail jump keeps its speed until the ground" in the spec.
var _rail_launch_carry: bool = false
## The flat speed the carry drives at - the ride's, taken as he left the rail.
var _rail_launch_speed: float = 0.0
## The landing ease that follows a carry: seconds in, and the flat speed he landed with. Off
## (elapsed < 0) until a carry lands. See _apply_rail_land_ease().
var _rail_land_ease_elapsed: float = -1.0
var _rail_land_ease_from: float = 0.0

## The rail switch - a committed, scripted hop onto another rail. See _start_rail_switch().
var is_rail_switching: bool = false
var _switch_rail = null           # the target; untyped, see `_rail`
var _switch_offset: float = 0.0   # where on it he lands, curve metres
var _switch_dir: int = 1          # the ride direction he lands with
var _switch_start: Vector3 = Vector3.ZERO
var _switch_elapsed: float = 0.0
var _switch_speed: float = 0.0    # the ride speed he left with, and lands with
var _switch_facing: Vector3 = Vector3.ZERO

## True for the length of a dash. Read only by pilot9.gd itself - the AnimationTree is not
## consulted at all while this is true, which is the whole feature. See
## docs/specs/pilot9-dash.md.
var is_dashing: bool = false
## Seconds left in the current dash, counting down from `dash_time`.
var _dash_time_left: float = 0.0
## Seconds left before another dash may be LAUNCHED, counting down from `dash_cooldown` from
## the frame of the press - not from the end of the dash.
var _dash_cooldown_left: float = 0.0
## Steerable for the whole window - see _steer_dash(). Set at launch, then overwritten every
## physics frame from live input while a stick is held, holding whatever it last was when the
## stick is centred. World-space, already normalised, y always 0.
var _dash_direction: Vector3 = Vector3.ZERO
## One dash's worth of air availability. Spent only by a dash LAUNCHED while airborne (see
## _dash_air_charge_after_launch()) and refreshed the instant he touches a floor (see
## _dash_air_charge_refreshed()), whatever the cooldown is doing - the charge is robust
## against a cooldown that gets tuned down during QA, not redundant with it.
var _dash_air_charge: bool = true
## The dash's afterimage trail - built in _ready(), see _setup_afterimage().
var _afterimage: Pilot9Afterimage = null

# Freeze the character. It may be useful when you want to pause the character.
var frozen: bool = false

## Body lean trackers, updated every frame whatever the state - see _body_lean_target().
## Last frame's mesh yaw, for the turn rate the roll reads.
var _lean_last_yaw: float = 0.0
## His horizontal speed as he "feels" it: lags the real one by body_lean_felt_lag, and the
## gap between them is the pitch.
var _felt_speed: float = 0.0

## Where CameraPivot sits on him, matching its transform in scenes/pilot9.tscn (and the value
## scripts/pilot9_build_scene.gd writes there). The pivot is top_level now, so this is the whole
## of what _process() needs to place it each drawn frame.
const CAMERA_PIVOT_OFFSET := Vector3(0.0, 1.5, 0.0)
## Height of the point on him the zoom framing keeps on screen - his middle, roughly where the
## standing capsule's centre sits in scenes/pilot9.tscn. See _camera_zoom_tilt().
const CAMERA_FRAME_HEIGHT := 1.0

## Stride lengths of the two clips the sway keeps time with, seconds, measured 2026-09-26.
## Each is one full stride - two footfalls. Consts, not reads: the tree plays them at their
## authored rate, and a re-export that changes them only drifts the free-running sway clock.
const SWAY_RUN_STRIDE := 0.600
const SWAY_SPRINT_STRIDE := 0.533

var target_camera_distance: float = 2.5
## The wall-run roll's own ease, radians. camera_3d.rotation.z is this plus the sway's roll,
## so the ease never starts from a value the sway has moved.
var _camera_wall_roll: float = 0.0
## Which shoulder the player chose: +1 right, -1 left. The wall-run overrides it while it runs
## and never writes it, so the camera returns here afterwards.
var _shoulder_side: float = 1.0
## The arm origin's eased sideways position, metres, signed (+ = camera's right).
var _shoulder_pos: float = 0.0
## How far the world lets the offset go on its current side, damped like the arm length.
var _shoulder_limit: float = 0.8
var _shoulder_probe: PhysicsShapeQueryParameters3D = null
## The sway's stride clock, radians of lateral phase. Runs through the air.
var _sway_phase: float = 0.0
## The sway's eased 0..1 weight.
var _sway_weight: float = 0.0
## The landing dip's spring: displacement (metres, negative is down) and its velocity.
var _dip_offset: float = 0.0
var _dip_velocity: float = 0.0
## Downward speed taken just before this frame's move_and_slide(), which zeroes it on contact.
## Zero on every branch that is not ordinary movement - see "What counts as a landing".
var _landing_speed_in: float = 0.0
## is_on_floor() as of the end of the previous physics frame.
var _dip_was_on_floor: bool = true
## A touchdown's impact speed, held one frame so a bounce pad can cancel it. 0.0 is none.
var _dip_pending_speed: float = 0.0
## The movement effects' node - see _setup_vfx(). Null only before _ready().
var _vfx: Pilot9Vfx = null
## A landing's dust strength (0..1), picked up by _resolve_landing_dip() and spent at the END
## of the same frame by _emit_landing_dust(), once a slide started on landing is visible.
var _land_dust_pending: float = 0.0
## The speed lasers' latch (on above vfx_laser_on_speed, off below vfx_laser_off_speed) and
## their 0..1 ease-in, which restarts from 0 every time they come on.
var _laser_on: bool = false
var _laser_ease: float = 0.0
## Seconds since he spawned, for the hard-turn window's timestamps.
var _vfx_clock: float = 0.0
## Counts down after a sprint kick or a skid; nothing kicks again until it reaches 0.
var _kick_cooldown_left: float = 0.0
## Last frame's is_sprinting (a slide counting as sprinting), for the sprint kick's rising edge.
## Kept through the air, so landing already sprinting is not a start.
var _was_sprint_moving: bool = false
## [time, flat travel direction] of the recent floor frames he was fast on - see _hard_turn_from().
var _turn_history: Array = []
## Where his feet meet the wall, refreshed every wall-run frame. The wall-jump kick uses the
## last one, so a coyote wall jump still puffs on the wall rather than in the air.
var _wall_kick_point: Vector3 = Vector3.ZERO
## The vault's detected top point, for the hand taps on its plant frame.
var _vault_hand_top: Vector3 = Vector3.ZERO
## The third-person length the scroll wheel has picked. Separate from camera_distance because
## that one is the body-hide reference - see docs/specs/pilot9-camera-zoom.md.
var _zoom_distance: float = 2.5
## The sprint pull-back and crouch drop's eased current values, metres, both >= 0.
var _camera_state_back: float = 0.0
var _camera_state_drop: float = 0.0
## Their spring velocities, m/s - see _camera_state_spring().
var _camera_state_back_vel: float = 0.0
var _camera_state_drop_vel: float = 0.0
## 0..1: how long a full-deflection look stick has been held, over look_stick_ramp_time.
var _look_ramp_t: float = 0.0
var is_transitioning_camera: bool = false
## The length the camera MODE wants, with the walls not consulted - what spring_length used
## to be back when nothing but _update_camera_mode() ever wrote it. It is kept separately
## now because walls write the real spring_length, and the character mesh's visibility reads
## THIS one: keying visibility off the wall-aware length would blink his body out every time
## a wall squeezed the camera in, which is a new glitch traded for an old one.
var _camera_mode_length: float = 2.5
## The probe cast every frame by _camera_obstruction_length(), built once in
## _setup_camera_collision() rather than per frame - it is the same query with a new origin.
var _camera_probe: PhysicsShapeQueryParameters3D = null
## True from the moment a dash launches until `camera_dash_lag_delay + camera_dash_lag_time` has
## elapsed in real time - see _camera_dash_lag_position(). While true, _process() blends
## CameraPivot's position from where the rig was at launch toward the live weld target instead
## of setting it outright, which is what lets him visibly outrun the camera and the shot glide
## back onto him rather than snap. False the rest of the time, which is the existing hard weld
## with nothing about it changed.
var _camera_dash_lag_active: bool = false
## Where CameraPivot was the instant the dash launched - since it was hard-welded up to that
## frame, this IS his launch position (plus CAMERA_PIVOT_OFFSET). The lerp's fixed end;
## _camera_dash_lag_position() never needs to know where the dash will actually take him.
var _camera_dash_lag_start: Vector3 = Vector3.ZERO
## Real seconds since the dash launched, ticked in _process() rather than the physics step -
## deliberately independent of `_dash_time_left`, which _check_dash_blocked() can zero out
## early. A dash cut short by a wall still owes the camera the rest of its original
## `camera_dash_lag_delay + camera_dash_lag_time` budget to glide the last of the way in;
## borrowing the dash's own countdown would truncate that into a snap the instant the wall
## stops him.
var _camera_dash_lag_elapsed: float = 0.0
## The FOV with no sprint boost on it: the player's own setting, read live every frame the
## boost is computed. A computed property rather than a field captured in _ready(), because a
## field is only ever as fresh as the last spawn - the settings row wrote to disk, survived a
## relaunch, and did nothing to a pilot who already existed. Nothing to push, nothing to
## order, nothing to go stale. See docs/specs/settings.md, FOV Applies Live.
##
## The Camera3D's authored fov is no longer consulted. It never carried a decision: no camera
## in pilot9.tscn or mech.tscn sets `fov` at all, so the 75 this used to capture was Godot's
## default rather than anything tuned.
var base_fov: float:
	get: return Settings.fov
## The sprint FOV's eased value, held apart from the camera so the dash kick can sit on top of
## it. The sprint lerp used to step `camera_3d.fov` in place; with a kick added it would read
## the kicked lens back as its start and pull the kick down at its own rate. The camera is
## now written, never read back. Seeded off the camera in _ready().
var _sprint_fov: float = 75.0
## The dash kick's envelope, 0..1 of `dash_fov_boost`. See _dash_fov_kick_at().
var _dash_fov_kick: float = 0.0
## Where the kick was when the current phase (rising or releasing) began, and how long that
## phase has run. A blocked dash releases from wherever it got to; a re-dash mid-release
## rises from wherever the release has got to.
var _dash_fov_from: float = 0.0
var _dash_fov_elapsed: float = 0.0
## is_dashing as of the last FOV step - a change starts a new phase.
var _dash_fov_was_dashing: bool = false

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

## Static twin of the two below, for the same reason jump_distance_for() is static: the jump
## grid platform reads pilot9's exports through an editor placeholder, which carries properties
## but not methods, so a call on `self` is not available to it.
static func dash_distance_for(a_dash_speed: float, a_dash_time: float) -> float:
	return a_dash_speed * a_dash_time


static func wall_run_distance_for(horizontal_speed: float, flat_time: float) -> float:
	return horizontal_speed * flat_time


## A jump off a rail at `speed`: the ordinary jump's airtime at that speed. Static twin of
## rail_jump_distance() for the jump grid's editor placeholder - see jump_distance_for().
static func rail_jump_distance_for(launch_speed: float, time_to_apex: float,
		fall_multiplier: float) -> float:
	return jump_distance_for(launch_speed, time_to_apex, fall_multiplier)


## How far a rail jump clears at `speed`, metres - 18 off the grind gear, 24 off the sprint gear.
func rail_jump_distance(rail_speed: float) -> float:
	return rail_jump_distance_for(rail_speed, jump_time_to_apex, jump_fall_multiplier)


## How far a dash covers, metres. Flat and locked for the whole window, so unlike
## jump_distance() there is no arc to integrate - it is exactly speed times time. Started at
## 9.0 m, the same number as the sprint jump, then moved off that lip on the play-session
## retune; see docs/specs/pilot9-dash.md, "The 9.0 m collision".
func dash_distance() -> float:
	return dash_distance_for(dash_speed, dash_time)

## How far a wall-run crosses, metres. One number: every run is brought up to wall_run_speed
## and held there for the flat portion, and the droop is not part of the grid - see "The grid"
## in the spec.
func wall_run_distance() -> float:
	return wall_run_distance_for(wall_run_speed, wall_run_flat_time)


## The nth chained wall-jump's height (n = wall-jumps already taken this flight): `height`
## scaled by `decay` per link. Static and pure - see tests/test_pilot9_wall_run.gd.
static func wall_jump_height_for(n: int, height: float, decay: float) -> float:
	return height * pow(decay, n)


## The most a whole chain can climb: the geometric series of wall_jump_height_for(), summed.
## 3 / (1 - 0.5) = 6 m - the ceiling maps are authored against. INF at decay 1.0, which is
## exactly what the test that protects the maps should fail on.
static func wall_jump_chain_ceiling(height: float, decay: float) -> float:
	if decay >= 1.0:
		return INF
	return height / (1.0 - decay)


func _ready() -> void:
	# Set here rather than on the scene so it cannot be lost to a rebuild of pilot9.tscn, and
	# so the reason for it sits next to the number. See FLOOR_SNAP_LENGTH.
	floor_snap_length = FLOOR_SNAP_LENGTH
	# First: everything below that walks his meshes (afterimage pool, rim light, hologram
	# masks) has to see the body he will actually wear.
	_swap_body_meshes()
	# Right after the body: the afterimage pool, the rim light and ApplyCelPilot9 all walk his
	# meshes and should find the poncho among them.
	_setup_poncho()
	_zoom_distance = clampf(camera_distance, camera_zoom_min, camera_zoom_max)
	target_camera_distance = 0.0 if camera_mode == CameraMode.FIRST_PERSON else _zoom_distance
	_camera_mode_length = target_camera_distance
	spring_arm.spring_length = target_camera_distance
	_setup_camera_collision()
	_setup_afterimage()
	_setup_vfx()
	_sprint_fov = camera_3d.fov
	_setup_item_holder()
	# Before the rim light and hologram, which walk his meshes.
	_setup_hat()
	_setup_wall_hand()
	_setup_slide_hand()
	_apply_rim_light()
	_setup_hologram()
	# Last of the skeleton modifiers: the tredge pose has the final word on both arms.
	_setup_tredge()
	_setup_anime_hold()
	if character:
		character.visible = camera_mode == CameraMode.THIRD_PERSON
		# The scene's starting yaw is not a turn.
		_reseed_body_lean()

## Replaces the skeleton's meshes with `body_glb`'s. The GLB's skins bind by bone name, and its
## skeleton is the same armature, so each mesh is lifted out and re-pointed at ours.
func _swap_body_meshes() -> void:
	if body_glb == null:
		return
	var skel := get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		push_error("pilot9: no skeleton to put body_glb on")
		return
	var source := body_glb.instantiate()
	var incoming := source.find_children("*", "MeshInstance3D", true, false)
	if incoming.is_empty():
		push_error("pilot9: body_glb has no meshes - keeping the scene's body")
		source.free()
		return
	for child in skel.get_children():
		if child is MeshInstance3D:
			skel.remove_child(child)
			child.queue_free()
	for node in incoming:
		var mi := node as MeshInstance3D
		mi.get_parent().remove_child(mi)
		mi.owner = null
		skel.add_child(mi)
		mi.skeleton = NodePath("..")
	source.free()

## -- pilot switching -----------------------------------------------------------
##
## More than one pilot9 can stand in a scene; scripts/pilot_switcher.gd hands control between
## them. An uncontrolled pilot is `frozen` (stands, falls, reads no input), owns no camera, and
## leaves the groups that mean "the one being played". See docs/specs/pilot-switch.md.

var controlled: bool = true

func set_controlled(on: bool) -> void:
	controlled = on
	frozen = not on
	# The firing range's dummies shoot the first reflect_target; the pause menu opens on the
	# first hologram_host. Both should be the pilot being played.
	if on:
		add_to_group(&"reflect_target")
	elif is_in_group(&"reflect_target"):
		remove_from_group(&"reflect_target")
	if hologram != null:
		if on:
			hologram.add_to_group(&"hologram_host")
		elif hologram.is_in_group(&"hologram_host"):
			hologram.remove_from_group(&"hologram_host")
	if on:
		camera_3d.current = true

func _physics_process(delta: float) -> void:
	# First, and above every early return below, for the reason in its own docstring: the
	# frames a mantle or a freeze bails out on are exactly the frames the FOV has to be
	# easing back on.
	_handle_camera_fov(delta)
	# Last frame's touchdown, now that the bounce pad has had its chance to launch him - see
	# "What counts as a landing" in docs/specs/pilot9-camera-sway.md.
	_resolve_landing_dip()
	if tredge != null:
		tredge.tick(delta)
	_update_sprint_toggle()
	# Freezing mid-mantle ends it rather than pausing it, for the reason the slide ends
	# itself: nothing advances _climb_time while frozen, and he would be left hanging in
	# the air with his collision shape switched off. Landing him on top is the safe stop.
	if frozen and is_climbing:
		_end_climb(false)
	# Same reason for the vault: nothing advances it while frozen, and before the hand release
	# his collision is off.
	if frozen and is_vaulting:
		_abort_vault()
	_handle_crouch_and_slide(delta)
	# Ahead of _handle_gravity_and_jump(): a dash launched this frame has to be is_dashing
	# true before that function runs, since it is the thing that refuses to run at all while
	# he is dashing (gravity suspended, jump not readable - see docs/specs/pilot9-dash.md).
	_handle_dash(delta)
	# Ahead of the mantle and the wall-run: a rail catch beats both on the same frame - the rail
	# was placed on purpose. After the dash, which refuses a catch while it runs and ends a grind
	# it launches out of. See docs/specs/pilot9-rail-grind.md, "Attach".
	_handle_rail_grind(delta)
	# Ahead of _handle_wall_run(): a ledge he can reach beats a wall-run attach, and a mantle
	# started here leaves nothing for the wall-run to grab. After the dash, which refuses it.
	# See "Mantle vs wall-run" in docs/specs/pilot9-wall-run.md.
	_handle_mantle_trigger()
	# After the mantle (a reachable lip is its, never a climb's) and ahead of the wall-run (dead-on
	# into a face is a climb before it is a camera-redirected run). Ahead of gravity for the
	# wall-run's reason: it suspends gravity and takes the jump press. See
	# docs/specs/pilot9-wall-climb.md.
	_handle_wall_climb(delta)
	# Same reason the dash sits here: a wall-run started this frame has to be is_wall_running
	# true before _handle_gravity_and_jump() runs, since that is the function it suspends
	# gravity against and the function it consumes the jump press through. See
	# docs/specs/pilot9-wall-run.md, "Shape of the code".
	_handle_wall_run(delta)
	_handle_gravity_and_jump(delta)
	_handle_camera_transition(delta)
	_handle_controller_camera(delta)
	_handle_rail_camera(delta)

	# Three ways through, and the tail below runs on all of them - which is why these are an
	# if/elif chain and no longer two early returns. See _align_model_to_slope().
	#
	# A mantle owns his position outright. move_and_slide() is deliberately NOT called
	# these frames - his collision shape is off and he is being written along a path over
	# an edge, so a velocity step would only fight the curve.
	_landing_speed_in = 0.0
	if is_climbing:
		_apply_climb_motion(delta)
	elif is_vaulting:
		# Position-driven up to the hand release and move_and_slide() after it - both inside.
		# No stick and no turning: he goes straight over, like the mantle.
		_apply_vault_motion(delta)
	elif frozen:
		handle_frozen_movement()
		move_and_slide()
	else:
		_handle_movement_input()
		# Before the rotation, and outside its THIRD_PERSON gate: the heading is what steers
		# the body, so it has to turn even in a camera mode where nothing is drawing the mesh.
		if is_sliding:
			_steer_slide(delta)
		elif is_dashing:
			_steer_dash()
		if camera_mode == CameraMode.THIRD_PERSON:
			_handle_character_rotation(delta)
		# A dash owns his velocity outright, same as a slide - see _apply_dash_velocity().
		# Unlike the mantle it still calls move_and_slide() below: the blocked-dash cut
		# reads its result.
		if is_dashing:
			_apply_dash_velocity()
		elif is_wall_running:
			_apply_wall_run_velocity(delta)
		elif is_wall_climbing:
			_apply_wall_climb_velocity(delta)
		elif is_rail_grinding:
			_apply_rail_velocity(delta)
		elif is_rail_switching:
			_apply_rail_switch_velocity(delta)
		elif is_sliding:
			_apply_slide_velocity(delta)
		else:
			_apply_movement(delta)
		# Read before move_and_slide(), which zeroes it on the frame he lands. A rail ride or
		# switch is not a fall - the rail catch is out of the dip's scope.
		if not is_rail_grinding and not is_rail_switching:
			_landing_speed_in = maxf(-velocity.y, 0.0)
		# The afterimages place ghosts along this tick's segment, so they need both ends of it.
		var dash_tick_from := global_position
		move_and_slide()
		if is_dashing:
			# After move_and_slide(), not before: this is the one place the dash asks what
			# actually happened this frame rather than what it demanded.
			_check_dash_blocked()
			if _afterimage != null:
				_afterimage.advance(character, dash_tick_from, global_position)

	# Last, and after move_and_slide() on the branches that call it: get_floor_normal() is
	# that call's output, so a tilt taken any earlier is lying about last frame's grade.
	_align_model_to_slope(delta)
	_emit_landing_dust()
	_update_grind_vfx()
	_update_movement_vfx(delta)
	_track_landing()

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
	# Locked off out in the blizzard - see docs/specs/pilot9-tredge.md.
	if is_tredging:
		sprint_toggled = false
		return
	_update_sprint_stop(is_on_floor())
	# The rail shares this toggle - it IS the rail's gear (see _handle_rail_grind()) - so a
	# sprint caught onto a rail rides it as a rail sprint, a press on the rail shifts gear, and
	# he leaves the rail in whichever gait he was riding in.
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

	# No crouch or slide out in the blizzard; begin_tredge() already cleared the crouch.
	if is_tredging:
		return

	# The dash already ended any slide and cleared the crouch on its own way in - see
	# _start_dash(). `crouch` means nothing for the rest of the window, the same "0.5 s of
	# zero control" the jump is refused under.
	if is_dashing:
		return

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

	# Crouch does nothing on the wall. This return is what consumes that press here: it never
	# reaches the slide buffer or the crouch toggle below. See "Committed to the wall" in
	# docs/specs/pilot9-wall-run.md.
	if is_wall_running or is_wall_climbing:
		return

	if is_sliding:
		if not is_on_floor():
			_end_slide()          # off a ledge mid-slide; `fall` takes it from here
		elif is_slide_holding:
			# The one press the slide does not swallow, and it RESUMES the clip rather than
			# ending it: the run-out (frames 30-75) is his stand-up, so it is played, and the
			# slide ends standing on the `_slide_time >= slide_duration` branch below once it
			# finishes. Nothing sets is_crouching - a slide never hands off into a crouch,
			# because crouch_speed (the run's 5.0 m/s) still deletes everything the slide earned.
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

	# The vault holds the body, but a `crouch` in it is remembered: spent on the exit as a slide
	# (see _end_vault()), so a vault at a sprint can land straight into one. Below the slide's
	# block because a slide cannot be running under a vault - _start_vault() ended it.
	if is_vaulting:
		if Input.is_action_just_pressed("crouch"):
			_vault_slide_buffered = true
		return

	# Crouch is the rail's let-go. Consumed here - it never reaches the slide buffer or the crouch
	# toggle below, so it does not also start a slide on landing. Below the slide block only
	# because a grind and a slide never overlap (_start_rail_grind() ends the slide). The lockout
	# _end_rail_grind() starts is what stops _handle_rail_grind(), which runs after this,
	# re-catching the same rail.
	if is_rail_grinding:
		if Input.is_action_just_pressed("crouch"):
			velocity = _rail_ride_velocity()
			_start_rail_launch_carry()
			_end_rail_grind(RailExit.CROUCH)
		return
	# The switch is committed - crouch mid-hop is ignored, and not saved for the landing.
	if is_rail_switching:
		return

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
	_rail_land_ease_elapsed = -1.0    # the slide owns his speed now; no rail ease after it
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
	# The entry shower, held to the stream's own cutoff: an auto-slide that starts from nearly
	# nothing should not burst sparks the stream then refuses.
	if _effects_on() and _horizontal_speed() >= vfx_slide_spark_min_speed:
		_vfx.slide_start(global_position + _slide_direction * SLIDE_SPARK_LEAD, -_slide_direction)

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
		gain_scale: float) -> float:
	if heading.length() <= 0.0001 or floor_normal.length() <= 0.0001:
		return 0.0
	var n := floor_normal.normalized()
	var downhill := _downhill(n)
	if downhill == Vector3.ZERO:
		return 0.0
	var sin_t := Vector3(n.x, 0.0, n.z).length()
	return gravity * sin_t * n.y * heading.normalized().dot(downhill) * gain_scale

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
##
## The body lean rides the floor branch's target and nothing else, so the level-snaps and the
## other branches never see it. It is computed above the branches because its trackers have to
## run every frame - see _body_lean_target().
func _align_model_to_slope(delta: float) -> void:
	var target := Vector2.ZERO
	var on_floor := is_on_floor()
	var lean := _body_lean_target(delta, on_floor)
	if on_floor and not is_climbing and not is_vaulting and not is_wall_climbing:
		target = _slope_align_angles(character.rotation.y, get_floor_normal(),
			slope_align_pitch, slope_align_roll) + lean
	elif is_wall_climbing:
		# Tipped back off the face by the clip's own lean - negative X is head back, away from a
		# face he is turned into. See wall_climb_lean.
		target = Vector2(-deg_to_rad(wall_climb_lean), 0.0)
	elif is_wall_running:
		# The ground sprint cycle plays on the wall (2026-09-26), so the lean off the face is
		# this roll's job: head away from the wall, the Titanfall pose.
		target = _wall_run_roll_angles(character.rotation.y, _wall_normal, wall_run_lean)
	elif is_rail_grinding:
		# No pitch on a rail, whatever its slope - only the roll into its bends.
		target = Vector2(0.0, _rail_lean_target())
	var step := slope_align_speed * delta
	character.rotation.x = lerp_angle(character.rotation.x, target.x, step)
	character.rotation.z = lerp_angle(character.rotation.z, target.y, step)
	# Slide the mesh in toward the face while running (see wall_run_hug); back to centre
	# otherwise, on the same ease.
	var offset := Vector3.ZERO
	if is_wall_running:
		offset = global_basis.inverse() * (-_wall_normal * wall_run_hug)
	elif is_wall_climbing:
		# Slid in until the tipped clip's hands and toes meet the face.
		offset = global_basis.inverse() * (-_wall_climb_normal * _wall_climb_hug())
	character.position = character.position.lerp(offset, minf(step, 1.0))

## Whether the body lean shows this frame: on the floor at a walk, run or sprint, third person.
## Everything else keeps its own tilt (or none) - see "Where it applies" in
## docs/specs/pilot9-body-lean.md. `on_floor` is a parameter so a headless test can reach it.
func _body_lean_active(on_floor: bool) -> bool:
	return on_floor \
		and camera_mode == CameraMode.THIRD_PERSON \
		and not is_crouching \
		and not is_sliding \
		and not is_dashing \
		and not is_climbing \
		and not is_vaulting \
		and not is_wall_running \
		and not is_wall_climbing \
		and not is_rail_grinding \
		and not is_rail_switching \
		and not frozen

## The lean added to the slope tilt's target: pitch in .x, roll in .y, radians.
##
## Called every frame whatever the state, because both trackers have to stay current - a felt
## speed frozen at takeoff would kick on every landing, and a yaw that last moved three states
## ago would read as a violent turn. Returns zero outside _body_lean_active().
##
## Roll is horizontal speed x the MESH's yaw rate: velocity snaps to the stick in one frame and
## has no turn rate, the mesh's lerp does. Leaning into a left turn (positive yaw step) puts his
## head toward local +X, which is negative rotation.z - same convention as the slope roll.
##
## Pitch is the gap between his speed and the lagging felt speed, so it is a lean into a CHANGE
## that decays by itself. The caps are visible peaks: the target is divided by the peak the felt
## lag and the slope ease reach together on a step - see _body_lean_peak_fraction().
func _body_lean_target(delta: float, on_floor: bool) -> Vector2:
	var flat_speed := _horizontal_speed()
	var yaw := character.rotation.y
	var yaw_step := wrapf(yaw - _lean_last_yaw, -PI, PI)
	_lean_last_yaw = yaw
	if delta <= 0.0:
		return Vector2.ZERO
	_felt_speed += (flat_speed - _felt_speed) * (1.0 - exp(-delta / maxf(body_lean_felt_lag, 0.0001)))
	if not _body_lean_active(on_floor):
		return Vector2.ZERO

	var lateral := flat_speed * yaw_step / delta
	var roll := -clampf(lateral / body_lean_roll_full_accel, -1.0, 1.0) \
		* deg_to_rad(body_lean_roll_max)

	var f := _body_lean_peak_fraction(body_lean_felt_lag, 1.0 / maxf(slope_align_speed, 0.0001))
	var gap := flat_speed - _felt_speed
	var pitch := 0.0
	if gap > 0.0:
		pitch = deg_to_rad(body_lean_pitch_forward_max) \
			* clampf(gap / body_lean_pitch_full_gap, 0.0, 1.0) / f
	elif gap < 0.0:
		pitch = -deg_to_rad(body_lean_pitch_back_max) \
			* clampf(-gap / body_lean_pitch_full_gap, 0.0, 1.0) / f
	return Vector2(pitch, roll)

## The peak of a unit step passed through two first-order lags of time constants t1 and t2 -
## the felt speed and the slope ease. About 0.54 at the shipping 0.25 s and 0.1 s, 1/e when the
## two are equal. The pitch target is divided by this so its cap is what shows on the mesh.
static func _body_lean_peak_fraction(t1: float, t2: float) -> float:
	if t1 <= 0.0 or t2 <= 0.0:
		return 1.0
	if absf(t1 - t2) < 0.000001:
		return exp(-1.0)
	var t_peak := log(t1 / t2) * t1 * t2 / (t1 - t2)
	return t1 / (t1 - t2) * (exp(-t_peak / t1) - exp(-t_peak / t2))

## Restarts the lean trackers from where he is now. Called where he is placed rather than
## walked - a yaw snap would otherwise read as a turn, a speed snap as a kick.
func _reseed_body_lean() -> void:
	_lean_last_yaw = character.rotation.y
	_felt_speed = _horizontal_speed()

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
		and not is_vaulting \
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
	var gravity_mult := 1.0 if vy > 0.0 else fall_mult
	if absf(vy) < apex_speed:
		gravity_mult *= apex_scale
	return gravity_mult

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

## Handles gravity application, the jump and the air jump.
##
## The mantle is started by _handle_mantle_trigger(), which runs ahead of this - so a `jump`
## pressed on the frame a mantle begins lands in the is_climbing branch below and is
## buffered for the exit rather than spent as an air jump.
##
## Gravity here is pilot9's own `jump_gravity`, NOT get_gravity(). See that property for why.
func _handle_gravity_and_jump(delta: float) -> void:
	# Gravity is suspended for the dash's whole window and `jump` is not readable during it
	# at all - the user's call, and the sharpest cost in the design. See
	# docs/specs/pilot9-dash.md, Jump. Both graces are frozen rather than ticked, exactly the
	# way a climb freezes them below: they resume wherever the dash found them.
	if is_dashing:
		return

	if is_climbing:
		# Not cancellable - collision is off and he is on a scripted path over an edge, so
		# there is no safe point to release him. The press is held for the exit instead.
		if not frozen and Input.is_action_just_pressed("jump"):
			_climb_jump_buffered = true
		return

	if is_vaulting:
		# Locked until the hands release, like the mantle, and the press waits for the release
		# frame. After it he is already a physics body again, so the press is the floor jump now.
		if not frozen and Input.is_action_just_pressed("jump"):
			if _vault_released:
				_vault_jump()
			else:
				_vault_jump_buffered = true
		return

	if is_wall_climbing:
		# Gravity and the jump press are _handle_wall_climb()'s, as they are the wall-run's.
		return

	if is_wall_running:
		# Gravity and the jump press are both owned by _handle_wall_run() while this is true -
		# it runs ahead of this function and already read the press, buffering it into
		# _wall_jump_buffered rather than leaving it for the read below. The mantle out of a
		# run is _handle_mantle_trigger()'s, which has already run this frame.
		return

	if is_rail_grinding:
		# Gravity is the rail's while he rides it - _apply_rail_velocity() places him on the
		# curve every frame. The jump is taken here outright: nothing after this in the frame
		# writes velocity.y, and _apply_movement() only sees him once he is off.
		if not frozen and Input.is_action_just_pressed("jump"):
			# A stick aimed at another rail makes the jump a switch onto it; otherwise (or with
			# no rail that way) it is the ordinary rail jump. See "Rail to rail" in the spec.
			if not _try_rail_switch():
				var launch := _rail_ride_velocity()   # read before the end drops the rail
				_end_rail_grind(RailExit.JUMP)
				_take_rail_jump(launch)
		return

	if is_rail_switching:
		# The switch's flight owns his whole velocity - _apply_rail_switch_velocity() - and
		# ignores the jump press: the hop is committed.
		return

	# A freeze is not a moment the player is still mid-jump through, so both graces are
	# dropped on the way past - the same argument `_slide_buffered` gets in
	# _handle_crouch_and_slide(). A stale press firing on the frame he unfreezes is not
	# something anyone asked for. Everything below leans on this: it is the only reason the
	# buffered-jump branch does not need its own `frozen` test.
	if frozen:
		_coyote_left = 0.0
		_jump_buffered = 0.0
		_wall_coyote_left = 0.0
		_rail_coyote_left = 0.0
		_wall_climb_coyote_left = 0.0
		_wall_climb_jump_buffered = false

	if not is_on_floor():
		var gravity_mult := _gravity_scale(velocity.y, jump_fall_multiplier, jump_apex_speed,
			jump_apex_scale)
		velocity.y = maxf(velocity.y - jump_gravity * gravity_mult * delta, -max_fall_speed)
		# `frozen` counts as held: nothing should be cut during a pause, and the velocity is
		# about to be zeroed by handle_frozen_movement() anyway.
		velocity.y = _cut_rise(velocity.y, frozen or Input.is_action_pressed("jump"),
			jump_velocity * jump_cut)
		is_jumping = velocity.y > 0
		_coyote_left = maxf(_coyote_left - delta, 0.0)
		_jump_buffered = maxf(_jump_buffered - delta, 0.0)
		_wall_coyote_left = maxf(_wall_coyote_left - delta, 0.0)
		_wall_climb_coyote_left = maxf(_wall_climb_coyote_left - delta, 0.0)
		_wall_jump_push_time = maxf(_wall_jump_push_time - delta, 0.0)
		_tick_wall_lockout(delta)
		_rail_coyote_left = maxf(_rail_coyote_left - delta, 0.0)
	else:
		is_jumping = false
		_air_jumps_left = air_jumps
		_coyote_left = coyote_time
		# The wall-run's whole per-flight state goes back to full here, beside the double
		# jump's - the chain decay, the push, the coyote and the same-wall lockout.
		_wall_jumps_taken = 0
		_wall_jump_push_time = 0.0
		_wall_coyote_left = 0.0
		_wall_lockout_normal = Vector3.ZERO
		_wall_lockout_left = 0.0
		_rail_coyote_left = 0.0
		_wall_climb_coyote_left = 0.0
		# A rail launch touching down: the speed it kept through the air starts easing out.
		if _rail_launch_carry:
			_rail_land_ease_elapsed = 0.0
			_rail_land_ease_from = _horizontal_speed()
		_rail_launch_carry = false

	# Spent here, one call after _handle_wall_run() read the press: that function runs ahead
	# of gravity and cannot apply the jump itself without gravity then running straight over
	# it this same frame. See _wall_jump_buffered's own note.
	if _wall_jump_buffered:
		_wall_jump_buffered = false
		_take_wall_jump()
		return

	# The climb jump, buffered by _handle_wall_climb() for the same reason.
	if _wall_climb_jump_buffered:
		_wall_climb_jump_buffered = false
		_take_wall_climb_jump()
		return

	# Spent here, ahead of everything else. The exit snap teleported him onto the ledge
	# without a move_and_slide(), so is_on_floor() is still false on this frame and the
	# press would otherwise fall through to the air-jump branch and be charged for.
	if _climb_jump_buffered:
		_climb_jump_buffered = false
		if not frozen:
			velocity.y = jump_velocity
			is_jumping = true
			return

	# A press made just before touchdown, spent on the frame he arrives. Ahead of the fresh
	# press so a player who both buffered and pressed on the landing frame gets one jump
	# rather than two reads of the same intent. Needs no `frozen` test - the block at the top
	# already cleared it.
	if is_on_floor() and _jump_buffered > 0.0:
		_jump_buffered = 0.0
		_take_floor_jump()
		return

	# No jump of any kind out in the blizzard (docs/specs/pilot9-tredge.md). begin_tredge()
	# cleared the buffer, so nothing above this can fire either.
	if is_tredging:
		return
	if frozen or not Input.is_action_just_pressed("jump"):
		return

	if is_on_floor() or _coyote_left > 0.0:
		# A thin, waist-high top ahead turns the grounded press into a vault. Only on the floor
		# itself - a coyote press is already off the edge - and checked first, because anything
		# that does not qualify falls through to the jump unchanged. See
		# docs/specs/pilot9-vault.md.
		if is_on_floor() and _try_start_vault():
			return
		# Coyote time rides in this branch rather than one of its own, which is the whole
		# claim it makes: a press inside the window is the FLOOR jump he was a frame late
		# for, not an extra one, so it costs no air jump and reads identically.
		_take_floor_jump()
	elif _rail_coyote_left > 0.0:
		# Rail coyote - the press a beat late off the end of a rail. The full rail jump, along
		# the end tangent at the speed he ran off at, spending nothing: a late press is not
		# punished. Ahead of the double jump for the wall coyote's reason.
		_take_rail_jump(_rail_coyote_tangent * _rail_coyote_speed)
	elif _wall_climb_coyote_left > 0.0:
		# Climb coyote - a press a beat after the peel is still the climb jump, for the wall
		# coyote's reason below.
		_take_wall_climb_jump()
	elif _wall_coyote_left > 0.0:
		# Wall coyote - the press a beat late off the end of a wall. Ahead of the double jump
		# on purpose: at chain speed this is the commonest input there is, and letting it
		# fall through would silently spend the double jump on a jump straight up. It counts
		# in the chain decay and costs no air jump. See "Wall coyote" in the spec.
		_take_wall_jump()
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
		if _effects_on():
			_vfx.double_jump(global_position)
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
	# Only off the floor itself: a coyote jump is already past the edge, and dust in mid-air
	# reads as a bug. Asked before the jump, while is_on_floor() still describes the takeoff.
	if is_on_floor() and _effects_on():
		_vfx.ground_jump(global_position)
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
	if is_dashing:
		# Welded to _dash_direction every frame, not just at launch - _steer_dash() has
		# already moved it this frame if the stick asked for a new heading. An instant yaw
		# snap is normally exactly what `rotation_speed` exists to prevent. It was free while he
		# was invisible for the window; he is visible now and it is kept anyway, for control.
		# See docs/specs/pilot9-dash.md, Direction and "The afterimages".
		character.rotation.y = atan2(_dash_direction.x, _dash_direction.z)
		return
	if is_climbing:
		# Welded, like the slide's - and for a stronger reason: the entry snap placed his
		# hands on the lip along this heading, so anything that turned him would slide the
		# grab off the edge it was measured against.
		character.rotation.y = atan2(_climb_facing.x, _climb_facing.z)
		return
	elif is_sliding:
		character.rotation.y = atan2(_slide_direction.x, _slide_direction.z)
		return
	elif is_wall_climbing:
		# Welded into the face - the stick does nothing on a climb.
		character.rotation.y = atan2(-_wall_climb_normal.x, -_wall_climb_normal.z)
		return
	elif is_wall_running:
		# Welded parallel to the wall for the whole run (2026-09-24): the stick is
		# camera-relative, so a camera nudge used to swing him off the face. _wall_run_direction
		# is fixed at attach and is exactly the heading the velocity runs along. Also covers
		# reaching for the top - turning into the face there would twist the run pose.
		character.rotation.y = atan2(_wall_run_direction.x, _wall_run_direction.z)
		return
	elif is_rail_grinding:
		# Welded to the ride, yaw only - he stays upright whatever the rail's slope, and the
		# stick does not steer a ride. The tangent turns with the curve, so this is the lerp's
		# job done by the rail itself.
		var ride := _rail_ride_tangent()
		if Vector2(ride.x, ride.z).length() > 0.0001:
			character.rotation.y = atan2(ride.x, ride.z)
		return
	elif is_rail_switching:
		# Facing the ride he left, the whole hop - it is a step sideways, not a turn.
		character.rotation.y = atan2(_switch_facing.x, _switch_facing.z)
		return
	elif input_dir == Vector2.ZERO:
		return
	else:
		target = atan2(direction.x, direction.z) if face_travel_direction \
			else camera_pivot.rotation.y + PI
	var turn := rotation_speed * (tredge_turn_scale if is_tredging else 1.0)
	character.rotation.y = lerp_angle(character.rotation.y, target, turn * delta)

## Handles controller stick input for camera rotation.
func _handle_controller_camera(delta: float) -> void:
	if not controller_support or frozen:
		return
	if not InputMap.has_action("look_left") or not InputMap.has_action("look_right") or not InputMap.has_action("look_up") or not InputMap.has_action("look_down"):
		return
	var raw := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if raw == Vector2.ZERO:
		_look_ramp_t = 0.0
		return
	_rail_camera_idle = 0.0
	_look_ramp_t = _look_ramp_step(_look_ramp_t, raw.length(), delta, look_stick_ramp_time)
	var look_dir := _look_stick_shape(raw, look_stick_curve) \
		* _look_ramp_factor(_look_ramp_t, raw.length(), look_stick_ramp_start)
	var sensitivity := controller_sensitivity * Settings.controller_sensitivity
	camera_pivot.rotation.y -= look_dir.x * sensitivity * delta
	camera_pivot.rotation.x = _clamp_pitch(camera_pivot.rotation.x - look_dir.y * sensitivity * delta,
		tilt_up_limit, tilt_down_limit)

## The stick's response curve: the direction kept, the deflection raised to `exponent`. Static and
## pure. Zero stays zero; a full push stays a full push.
static func _look_stick_shape(v: Vector2, exponent: float) -> Vector2:
	var m := v.length()
	if m <= 0.0001:
		return Vector2.ZERO
	return v / m * pow(minf(m, 1.0), exponent)

## One frame of the ramp clock: climbs only while the stick is near full deflection (0.9), and
## drops to nothing the moment it is not, so a flick never inherits a half-built ramp.
static func _look_ramp_step(t: float, magnitude: float, delta: float, ramp_time: float) -> float:
	if ramp_time <= 0.0:
		return 1.0
	if magnitude < 0.9:
		return 0.0
	return minf(t + delta / ramp_time, 1.0)

## The turn-speed multiplier the ramp gives: `start` fresh into a full push, 1.0 once ramped. It
## fades in with the deflection (0.6 to 0.95), so a gentle push is never slowed by it.
static func _look_ramp_factor(t: float, magnitude: float, start: float) -> float:
	var weight := smoothstep(0.6, 0.95, magnitude)
	return lerpf(1.0, lerpf(start, 1.0, t), weight)

## Pitch limits, radians: positive is looking up. Static and pure.
static func _clamp_pitch(pitch: float, up_limit: float, down_limit: float) -> float:
	return clampf(pitch, -down_limit, up_limit)

## The rail's swing-behind: once look input has been idle for rail_camera_idle_delay, the
## camera YAW eases toward the ride direction at up to rail_camera_swing_rate. Any look input -
## this stick, or the mouse in _unhandled_input() - zeroes the idle clock and cancels it at once.
## Pitch is never touched; first person does nothing, the view already being his facing. Rail
## only - no other state gets this. See docs/specs/pilot9-rail-grind.md, "The camera".
func _handle_rail_camera(delta: float) -> void:
	_rail_camera_idle += delta
	if not is_rail_grinding or frozen or camera_mode != CameraMode.THIRD_PERSON:
		return
	if _rail_camera_idle < rail_camera_idle_delay:
		return
	var ride := _rail_ride_tangent()
	if Vector2(ride.x, ride.z).length() <= 0.0001:
		return
	camera_pivot.rotation.y = rotate_toward(camera_pivot.rotation.y,
		_camera_yaw_facing(ride), deg_to_rad(rail_camera_swing_rate) * delta)

## The pivot yaw that looks along `dir` - the inverse of the camera forward
## _camera_wall_run_tangent() reads, -(sin yaw, 0, cos yaw). Static and pure.
static func _camera_yaw_facing(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)

## The wall-run camera limit: the view may not swing past parallel with the wall, so the camera
## never orbits round to the wall side of him. Camera forward is -(sin yaw, 0, cos yaw) and the
## camera sits BEHIND it, so a view pointing away from the wall (forward.dot(wall_normal) > 0)
## puts the camera on the wall side. A yaw past that is pulled back to whichever of the two
## parallel directions is nearer. Static and pure.
static func _clamp_yaw_off_wall(yaw: float, wall_normal: Vector3) -> float:
	var n := Vector3(wall_normal.x, 0.0, wall_normal.z)
	if n.length() <= 0.0001:
		return yaw
	n = n.normalized()
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if forward.dot(n) <= 0.0:
		return yaw
	var along := Vector3(-n.z, 0.0, n.x)
	return _camera_yaw_facing(along if forward.dot(along) >= 0.0 else -along)

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

	var side_probe := SphereShape3D.new()
	side_probe.radius = camera_clearance
	_shoulder_probe = PhysicsShapeQueryParameters3D.new()
	_shoulder_probe.shape = side_probe
	_shoulder_probe.exclude = [get_rid()]
	_shoulder_probe.collision_mask = spring_arm.collision_mask
	_shoulder_limit = camera_shoulder_offset

## The shoulder the camera wants, +1 right / -1 left: the player's choice, except while
## wall-running, when it is away from the wall. Wall on the right puts the camera on the left.
func _shoulder_target_side() -> float:
	if is_wall_running:
		return -1.0 if _wall_run_right else 1.0
	return _shoulder_side

## Static and pure so the tests can check the swap and the clamp without a rig. Moves `pos`
## toward `target` on an exponential ease that is within 2% of it after `swap_time`.
static func _shoulder_ease(pos: float, target: float, delta: float, swap_time: float) -> float:
	if swap_time <= 0.0:
		return target
	return lerpf(pos, target, clampf(4.0 * delta / swap_time, 0.0, 1.0))

## The sideways clearance, metres, in direction `side` from the pivot, up to the full offset.
## A sphere the arm's own backstop size, so the lens never starts inside a wall beside him.
func _shoulder_clearance(side: float) -> float:
	var full := camera_shoulder_offset
	if full <= 0.0 or _shoulder_probe == null or not is_inside_tree():
		return full
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return full
	_shoulder_probe.transform = Transform3D(Basis(), camera_pivot.global_position)
	_shoulder_probe.motion = camera_pivot.global_transform.basis.x.normalized() * side * full
	var fractions := world.direct_space_state.cast_motion(_shoulder_probe)
	if fractions.size() < 1:
		return full
	return float(fractions[0]) * full

## One frame of the shoulder: ease toward the wanted side, clamp by the world, write the arm's
## local x. Third person only - first person's zero-length arm scales it to nothing.
func _handle_camera_shoulder(delta: float) -> void:
	var side := _shoulder_target_side()
	var want := side * camera_shoulder_offset
	_shoulder_pos = _shoulder_ease(_shoulder_pos, want, delta, camera_shoulder_swap_time)
	var mode_scale := 0.0
	if camera_distance > 0.0:
		mode_scale = clampf(_camera_mode_length / camera_distance, 0.0, 1.0)
	var lead := signf(_shoulder_pos) if absf(_shoulder_pos) > 0.001 else side
	var clear := _shoulder_clearance(lead) if mode_scale > 0.0 else camera_shoulder_offset
	_shoulder_limit = _camera_length_step(_shoulder_limit, clear, delta,
		camera_retract_speed, camera_return_speed)
	var applied := signf(_shoulder_pos) * minf(absf(_shoulder_pos), _shoulder_limit)
	spring_arm.position.x = applied * mode_scale

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

## The camera's position partway through the dash's catch-up: eased from wherever the rig was
## AT LAUNCH toward wherever he is RIGHT NOW, weighted by how far past `delay` real time has
## gotten, out of `duration`. Before `delay` has elapsed the weight is pinned at 0.0 - the rig
## holds exactly at `start` while the target keeps moving, which is the "waits, then catches
## up" read. Both ends of the glide itself are still exact - elapsed <= delay reproduces the
## launch position bit for bit, elapsed >= delay + duration lands exactly on `target` - which is
## what lets _process() hand back to the plain hard weld once the window closes, with nothing
## left to snap into place.
##
## The "falls behind, glides back on" shape is not hand-tuned into the easing - it falls out of
## blending toward a target that is ITSELF moving. `target` advances roughly linearly through
## the dash (he is travelling at a constant `dash_speed`), so blending a *fixed* start toward a
## *moving* target with weight smoothstep(t) opens a gap that grows while the weight is still
## small, peaks near the middle of the window, and closes again as the weight approaches 1.
## `delay` widens that gap further before the glide even starts; `duration` is no longer pinned
## to `dash_time`, so the window this now closes on is `delay + duration`, not the dash's own
## length - see camera_dash_lag_delay and camera_dash_lag_time.
##
## Static and pure so the curve is assertable with no tree, no camera and no dash actually run
## - see tests/test_pilot9_dash.gd.
static func _camera_dash_lag_position(start: Vector3, target: Vector3, elapsed: float,
		delay: float, duration: float) -> Vector3:
	if duration <= 0.0:
		return target
	var t := clampf((elapsed - delay) / duration, 0.0, 1.0)
	return start.lerp(target, smoothstep(0.0, 1.0, t))

## The GTA framing's two state shifts: the pull-back while sprinting or dashing and the pivot
## drop while crouching or sliding, each eased on camera_state_ease_time. See
## docs/specs/pilot9-gta-camera.md.
##
## Runs from _process(), not the physics step: the pivot is placed every drawn frame, and a
## lift that only moved at the 60 Hz tick climbed in visible stairs on a faster display.
func _handle_camera_state(delta: float) -> void:
	var back_target := camera_sprint_pullback if (is_sprinting or is_dashing) else 0.0
	var drop_target := camera_crouch_drop if (is_crouching or is_sliding) else 0.0
	var back := _camera_state_spring(_camera_state_back, _camera_state_back_vel, back_target,
		delta, camera_state_ease_time)
	_camera_state_back = back.x
	_camera_state_back_vel = back.y
	var drop := _camera_state_spring(_camera_state_drop, _camera_state_drop_vel, drop_target,
		delta, camera_state_ease_time)
	_camera_state_drop = drop.x
	_camera_state_drop_vel = drop.y

## One step of a critically damped spring toward `target`, settled within 2% after
## `ease_time`. Returns (value, velocity). Replaces the exponential ease these shifts used to
## share with the shoulder, which is fastest on its first frame - so the instant a slide ended
## the pivot was already rising at full speed, and the camera read as snapping up. A spring
## from rest starts at zero speed instead. Static so the tests can check it without a rig.
static func _camera_state_spring(x: float, v: float, target: float, delta: float,
		ease_time: float) -> Vector2:
	if ease_time <= 0.0:
		return Vector2(target, 0.0)
	# (1 + wt) e^(-wt) = 0.02 at wt ~= 5.83.
	var step := _dip_spring_step(x - target, v, 5.83 / ease_time, delta)
	return Vector2(step.x + target, step.y)

## Handles smooth camera transition between modes, and the walls.
##
## Two lengths, deliberately: the mode transition owns _camera_mode_length and the walls own
## spring_length. See docs/specs/pilot9-camera-collision.md for why the mesh reads the first.
func _handle_camera_transition(delta: float) -> void:
	var back := _camera_state_back if target_camera_distance > 0.0 else 0.0
	_camera_mode_length = lerpf(_camera_mode_length, target_camera_distance + back,
		clampf(camera_transition_speed * delta, 0.0, 1.0))
	var desired := _camera_obstruction_length(_camera_mode_length)
	# The shoulder first: the obstruction cast above already ran from last frame's origin, which
	# is one frame stale and well inside the probe's lead.
	_handle_camera_shoulder(delta)
	spring_arm.spring_length = _camera_length_step(spring_arm.spring_length, desired, delta,
		camera_retract_speed, camera_return_speed)

	if character and camera_distance > 0.0:
		var transition_progress := _camera_mode_length / camera_distance
		var visibility_threshold := 0.3
		character.visible = transition_progress > visibility_threshold
	elif character:
		character.visible = camera_mode == CameraMode.THIRD_PERSON

	# The wall-run's camera roll - tilts the WORLD, which is what covers for the animation
	# dodge: a rolled camera reframes a rolled character as "the world went sideways" rather
	# than "the model is lying down." Same sign rule as the mesh's own roll, reused off
	# camera_pivot's yaw instead of the mesh's. See "The camera" in the spec.
	var camera_roll_target := 0.0
	if is_wall_running:
		# Already past parallel at attach: ease back to the limit instead of snapping.
		camera_pivot.rotation.y = rotate_toward(camera_pivot.rotation.y,
			_clamp_yaw_off_wall(camera_pivot.rotation.y, _wall_normal),
			deg_to_rad(360.0) * delta)
		camera_roll_target = _wall_run_roll_angles(
			camera_pivot.rotation.y, _wall_normal, wall_run_camera_roll).y
	_camera_wall_roll = lerp_angle(_camera_wall_roll, camera_roll_target,
		clampf(camera_transition_speed * delta, 0.0, 1.0))
	camera_3d.rotation.z = _camera_wall_roll + _handle_camera_motion(delta)

	# Zoom framing. Read off the live arm length, which is already eased and already knows
	# about walls, so the tilt needs no smoothing of its own.
	camera_3d.rotation.x = _camera_zoom_tilt(spring_arm.spring_length, camera_zoom_min,
		camera_zoom_max, camera_zoom_out_screen_height,
		CAMERA_PIVOT_OFFSET.y + _camera_zoom_lift() - CAMERA_FRAME_HEIGHT, deg_to_rad(base_fov))

## How far the pivot rises for the current zoom: camera_zoom_in_lift at camera_zoom_min,
## camera_zoom_out_lift at camera_zoom_max, linear between. Below zoom_min - only ever the ease
## into first person, at length 0 - the in-lift fades out so the first-person eye is not lowered.
## Keyed off the mode length, not spring_length, so a wall squeezing the arm does not move the
## pivot - which would move the arm's own origin and feed back into the cast.
func _camera_zoom_lift() -> float:
	if camera_zoom_max <= camera_zoom_min or camera_zoom_min <= 0.0:
		return 0.0
	# The GTA raise and the crouch drop fade out into first person with the zoom lift.
	var fade := clampf(_camera_mode_length / camera_zoom_min, 0.0, 1.0)
	var extra := (camera_pivot_raise - _camera_state_drop) * fade
	if _camera_mode_length < camera_zoom_min:
		return camera_zoom_in_lift * maxf(_camera_mode_length, 0.0) / camera_zoom_min + extra
	return lerpf(camera_zoom_in_lift, camera_zoom_out_lift, clampf(
		(_camera_mode_length - camera_zoom_min) / (camera_zoom_max - camera_zoom_min), 0.0, 1.0)) + extra

## The upward pitch, radians, that puts a point `drop` metres under the pivot at the screen
## height the zoom asks for. At `zoom_min` that is wherever the rig's geometry already puts
## him, so full zoom-in is untouched; by `zoom_max` it is `screen_height`, blended linearly in
## screen space between. The camera's own geometry puts him atan(drop / length) under the
## view's centre; only the shortfall is added. Never negative, so a wall squeezing the arm
## shorter than zoom_min - or first person, at length 0 - gets no tilt rather than a
## downward one. Static so the tests can check the maths without a rig. `fov` is vertical,
## Camera3D's default KEEP_HEIGHT.
static func _camera_zoom_tilt(length: float, zoom_min: float, zoom_max: float,
		screen_height: float, drop: float, fov: float) -> float:
	if length <= 0.0 or zoom_min <= 0.0 or zoom_max <= zoom_min:
		return 0.0
	var half := tan(fov * 0.5)
	var near_frac := (drop / zoom_min) / half
	var far_frac := (screen_height - 0.5) * 2.0
	var t := clampf((length - zoom_min) / (zoom_max - zoom_min), 0.0, 1.0)
	var want := atan(lerpf(near_frac, far_frac, t) * half)
	return maxf(0.0, want - atan(drop / length))

## Widens the camera while he is sprinting and eases it back for everything else, then lays
## the dash kick on top. See docs/specs/pilot9-sprint-fov.md and pilot9-dash-fov.md.
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
	# On a rail the stick does not drive him, so the gear alone is the sprint.
	if is_rail_grinding or is_rail_switching:
		sprinting_view = sprint_toggled and not frozen
	var target_fov := base_fov + (sprint_fov_boost if sprinting_view else 0.0)
	# Clamped because the weight is a rate times a frame: a long frame - a hitch, a load, a
	# breakpoint - would otherwise hand lerpf a weight above 1 and shoot the FOV past the
	# target instead of arriving at it.
	_sprint_fov = lerpf(_sprint_fov, target_fov, clampf(fov_transition_speed * delta, 0.0, 1.0))
	_step_dash_fov_kick(delta)
	_reflect_fov_deg = move_toward(_reflect_fov_deg, 0.0, _reflect_fov_rate * delta) 		if Settings.camera_motion else 0.0
	camera_3d.fov = _dash_fov_lens(_sprint_fov,
		_dash_fov_kick * dash_fov_boost + _reflect_fov_deg, dash_fov_ceiling)

## Advances the dash kick's envelope one physics step. See docs/specs/pilot9-dash-fov.md.
## Reads `is_dashing` one frame late for the same reason the sprint gate does - it runs first
## in the step - which is 16 ms on a 120 ms rise.
##
## CAMERA MOTION off holds the kick at zero with its clock stopped, and keeps the dashing flag
## in step, so switching the row back on mid-dash rises from zero rather than popping in.
func _step_dash_fov_kick(delta: float) -> void:
	if not Settings.camera_motion:
		_dash_fov_kick = 0.0
		_dash_fov_from = 0.0
		_dash_fov_elapsed = 0.0
		_dash_fov_was_dashing = is_dashing
		return
	if is_dashing != _dash_fov_was_dashing:
		_dash_fov_was_dashing = is_dashing
		_dash_fov_from = _dash_fov_kick
		_dash_fov_elapsed = 0.0
	_dash_fov_elapsed += delta
	_dash_fov_kick = _dash_fov_kick_at(is_dashing, _dash_fov_elapsed, _dash_fov_from,
		dash_fov_rise_time, dash_fov_release_time)

## The kick's envelope, 0..1. Dashing, it eases from `from` up to 1 over `rise_time`;
## released, it eases from `from` down to 0 over `release_time`. smoothstep both ways rather
## than a lerp at a rate, which is steepest at its start - that would put the sharpest pull of
## the close on the frame he reappears. `from` is where the phase began: a blocked dash
## releases from however far the rise got, and a re-dash rises from however far the release
## got, so neither ever jumps. Static and pure - tests/test_pilot9_dash_fov.gd.
static func _dash_fov_kick_at(dashing: bool, elapsed: float, from: float, rise_time: float,
		release_time: float) -> float:
	if dashing:
		if rise_time <= 0.0:
			return 1.0
		return lerpf(from, 1.0, smoothstep(0.0, 1.0, elapsed / rise_time))
	if release_time <= 0.0:
		return 0.0
	return from * (1.0 - smoothstep(0.0, 1.0, elapsed / release_time))

## The lens: the sprint's eased FOV plus the kick in degrees, with the kick - and only the
## kick - clamped so it never pushes past `ceiling`. A sprint FOV already above the ceiling is
## left where it is, not pulled down; it just gets no kick.
static func _dash_fov_lens(sprint_fov: float, kick_degrees: float, ceiling: float) -> float:
	return sprint_fov + clampf(kick_degrees, 0.0, maxf(ceiling - sprint_fov, 0.0))

## Updates camera mode (sets target for smooth transition).
## -- camera sway and landing dip ---------------------------------------------
##
## A figure-eight on the camera's h/v offsets while he runs or sprints, a hint of roll with it,
## and a spring dip when he lands hard. See docs/specs/pilot9-camera-sway.md. The pure halves
## are static so tests/test_pilot9_camera_sway.gd can check the curves without a rig.

## Writes the sway and the dip onto h_offset / v_offset and returns the sway's roll, radians,
## for _handle_camera_transition() to add to the wall-run roll. Called from there, after the
## arm has moved, so the zoom scale reads this frame's length.
func _handle_camera_motion(delta: float) -> float:
	if not Settings.camera_motion:
		_reset_camera_motion()
		return 0.0
	var h_speed := _horizontal_speed()
	var target := 0.0
	if _sway_allowed():
		target = _camera_sway_weight(h_speed, walk_speed, speed, sprint_speed,
			camera_sway_run_fraction)
	_sway_weight = move_toward(_sway_weight, target, delta / camera_sway_fade_time)
	# The clock runs whatever the weight, air included, so the phase never jumps on landing.
	_sway_phase = fmod(_sway_phase + TAU * delta / _sway_stride(h_speed, speed, sprint_speed),
		TAU)
	var spring := _dip_spring_step(_dip_offset, _dip_velocity, _dip_omega(landing_dip_time),
		delta)
	_dip_offset = spring.x
	_dip_velocity = spring.y
	var motion_scale := _camera_motion_scale(spring_arm.spring_length, camera_distance)
	var lateral := sin(_sway_phase)
	# cos(2x): lowest at either end of the lateral swing - the foot planting on that side -
	# and highest crossing the middle.
	var hit_shake: Vector2 = hit_feedback.shake_offset if hit_feedback != null else Vector2.ZERO
	camera_3d.h_offset = camera_sway_lateral * _sway_weight * lateral * motion_scale + hit_shake.x
	camera_3d.v_offset = (camera_sway_vertical * _sway_weight * cos(2.0 * _sway_phase)
		+ _dip_offset) * motion_scale + hit_shake.y
	return deg_to_rad(camera_sway_roll) * _sway_weight * lateral

## Every state the sway fades out in, as one test. Walking needs no term of its own - the
## weight is zero at walk_speed.
func _sway_allowed() -> bool:
	return is_on_floor() and not frozen and not is_crouching and not is_sliding 		and not is_climbing and not is_dashing and not is_wall_running 		and not is_rail_grinding and not is_rail_switching and not is_vaulting

## Everything back to still, offsets included. The OFF switch and leaving EXIA.
func _reset_camera_motion() -> void:
	_sway_weight = 0.0
	_dip_offset = 0.0
	_dip_velocity = 0.0
	_dip_pending_speed = 0.0
	_dip_was_on_floor = true
	if camera_3d:
		camera_3d.h_offset = 0.0
		camera_3d.v_offset = 0.0

## After move_and_slide(): a false-to-true on the floor with a recorded impact speed holds
## that speed for _resolve_landing_dip() to spend next frame. A mantle counts as on the floor
## throughout, so neither grabbing the ledge nor stepping onto it is ever a touchdown.
func _track_landing() -> void:
	if is_climbing:
		_dip_was_on_floor = true
		return
	var on_floor := is_on_floor()
	if on_floor and not _dip_was_on_floor and _landing_speed_in > 0.0:
		_dip_pending_speed = _landing_speed_in
	_dip_was_on_floor = on_floor

## Top of the frame after a touchdown. A bounce pad launches him from its Area3D's
## body_entered, which fires AFTER the touchdown frame's move_and_slide() and sets is_jumping -
## nothing else can have set it by here, since this frame's jump code has not run yet. So a
## pad cancels the dip and a jump pressed on landing does not.
func _resolve_landing_dip() -> void:
	var fall := _dip_pending_speed
	_dip_pending_speed = 0.0
	# The dust rides the same hand-off, and so the same bounce-pad cancel, but not the camera's
	# switch. Held to the end of the frame - see _emit_landing_dust().
	if fall > 0.0 and not is_jumping:
		_land_dust_pending = _landing_dust_strength(fall, landing_dip_min_speed,
			jump_velocity * sqrt(jump_fall_multiplier), max_fall_speed)
		_anime_accent(&"land", _land_dust_pending, func() -> bool:
			return _anime_state() == &"jump_land")
	if fall <= 0.0 or is_jumping or not Settings.camera_motion:
		return
	var depth := _landing_dip_depth(fall, landing_dip_min_speed,
		jump_velocity * sqrt(jump_fall_multiplier), landing_dip_full_jump,
		max_fall_speed, landing_dip_max)
	if depth > 0.0:
		# Added, not set - a second landing mid-recovery stacks on the first.
		_dip_velocity -= _dip_kick(depth, _dip_omega(landing_dip_time))

## 0 at `walk`, `run_fraction` at `run`, 1 at `sprint`, linear between, clamped.
static func _camera_sway_weight(h_speed: float, walk: float, run: float, sprint: float,
		run_fraction: float) -> float:
	if h_speed <= walk:
		return 0.0
	if h_speed < run:
		return run_fraction * (h_speed - walk) / maxf(run - walk, 0.001)
	return lerpf(run_fraction, 1.0, clampf((h_speed - run) / maxf(sprint - run, 0.001), 0.0, 1.0))

## Seconds per stride, eased from the run clip's to the sprint clip's with speed.
static func _sway_stride(h_speed: float, run: float, sprint: float) -> float:
	return lerpf(SWAY_RUN_STRIDE, SWAY_SPRINT_STRIDE,
		clampf((h_speed - run) / maxf(sprint - run, 0.001), 0.0, 1.0))

## The arm length over the authored 3.5 m: same on-screen size at every zoom, smaller when a
## wall squeezes the camera in, and nothing in first person.
static func _camera_motion_scale(length: float, reference: float) -> float:
	if reference <= 0.0:
		return 0.0
	return maxf(length, 0.0) / reference

## Dip depth, metres, for a downward impact speed. Three anchors, linear between: nothing at
## `min_speed`, `jump_dip` at a full jump's landing speed, `max_dip` at `max_speed` and above.
static func _landing_dip_depth(fall_speed: float, min_speed: float, jump_speed: float,
		jump_dip: float, max_speed: float, max_dip: float) -> float:
	if fall_speed <= min_speed:
		return 0.0
	if fall_speed <= jump_speed:
		return jump_dip * (fall_speed - min_speed) / maxf(jump_speed - min_speed, 0.001)
	return lerpf(jump_dip, max_dip,
		clampf((fall_speed - jump_speed) / maxf(max_speed - jump_speed, 0.001), 0.0, 1.0))

## A critically damped spring kicked from rest reaches its extreme 1/omega seconds later.
static func _dip_omega(time_to_bottom: float) -> float:
	return 1.0 / maxf(time_to_bottom, 0.001)

## The kick, m/s, that bottoms the spring out at exactly `depth`: the impulse response
## v0 * t * e^(-omega t) peaks at v0 / (omega e).
static func _dip_kick(depth: float, omega: float) -> float:
	return depth * omega * exp(1.0)

## One exact step of the critically damped spring - closed form rather than integrated, so
## the dip's shape does not depend on the frame rate. Returns (offset, velocity).
static func _dip_spring_step(x: float, v: float, omega: float, dt: float) -> Vector2:
	var decay := exp(-omega * dt)
	var c := v + omega * x
	return Vector2((x + c * dt) * decay, (v - omega * c * dt) * decay)

func _update_camera_mode() -> void:
	if camera_mode == CameraMode.FIRST_PERSON:
		target_camera_distance = 0.0
	else:
		target_camera_distance = _zoom_distance

## One wheel notch: positive `notches` zooms in. Scaled by the event's factor so a trackpad's
## fractional scroll moves a fraction of a step. See docs/specs/pilot9-camera-zoom.md.
func _zoom_camera(notches: float) -> void:
	_zoom_distance = clampf(_zoom_distance - notches * camera_zoom_step,
		camera_zoom_min, camera_zoom_max)
	_update_camera_mode()

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
## Which gait this frame's input asks for, and the flat speed that goes with it. Sets
## is_sprinting/is_walking as a side effect.
func _requested_speed() -> float:
	var is_moving = input_dir != Vector2.ZERO and is_on_floor()
	# The tredge outranks everything: one gait, slowed by the gust.
	if is_tredging:
		is_sprinting = false
		is_walking = false
		return tredge_speed * (1.0 - tredge_gust_slow * (tredge.gust if tredge != null else 0.0))
	# Crouch outranks both gaits: it owns the whole locomotion state, so leaving either
	# flag set would keep pilot9_animation.gd feeding the walk/run blends underneath it.
	is_sprinting = sprint_toggled and is_moving and not Input.is_action_pressed("walk") and not is_crouching
	is_walking = Input.is_action_pressed("walk") and is_moving and not sprint_toggled and can_walk and not is_crouching

	if is_crouching:
		return crouch_speed
	elif is_sprinting:
		return sprint_speed
	elif is_walking and can_walk:
		return walk_speed
	return speed

func _apply_movement(delta: float) -> void:
	if _wall_climb_coyote_left > 0.0 and not is_on_floor():
		# The peel off a climb: the push away from the face holds for the climb coyote, or the
		# air control (speed, not momentum) would turn it straight back into the wall on the
		# next frame with the stick still held. See "Built" in docs/specs/pilot9-wall-climb.md.
		return
	if _wall_jump_push_time > 0.0 and not is_on_floor():
		_apply_movement_under_wall_jump_push(delta)
	else:
		_wall_jump_push_time = 0.0
		_apply_stick_movement(delta)

## The wall-jump's flight: "the push survives unless you pull against it." His velocity is
## split against the normal he left. The along-wall part goes through the ordinary air step
## with full authority; the away part is taken out first - otherwise the step reads the
## kick as carried speed and folds it into his along-wall heading - and put back afterward
## at wall_jump_kick, unless the stick points back toward the wall. Only then does the stick
## take it over, from nothing to all of it across wall_jump_steer_back_ramp. See "Air control
## after a wall-jump" in the spec.
func _apply_movement_under_wall_jump_push(delta: float) -> void:
	var n := Vector3(_wall_jump_normal.x, 0.0, _wall_jump_normal.z).normalized()
	var away := velocity.x * n.x + velocity.z * n.z
	velocity.x -= n.x * away
	velocity.z -= n.z * away
	_apply_stick_movement(delta)
	var stick_away := velocity.x * n.x + velocity.z * n.z
	if direction and direction.dot(n) < 0.0:
		_wall_jump_steer_back += delta
	else:
		_wall_jump_steer_back = 0.0
	var authority := _wall_jump_steer_authority(_wall_jump_steer_back, wall_jump_steer_back_ramp)
	var held := lerpf(wall_jump_kick, stick_away, authority)
	velocity.x += n.x * (held - stick_away)
	velocity.z += n.z * (held - stick_away)

## How much of the away-from-wall component the stick owns after `pulled` seconds of pulling
## back toward the wall, 0..1. Static and pure - see tests/test_pilot9_wall_run.gd.
static func _wall_jump_steer_authority(pulled: float, ramp: float) -> float:
	if pulled <= 0.0:
		return 0.0
	if ramp <= 0.0:
		return 1.0
	return clampf(pulled / ramp, 0.0, 1.0)

func _apply_stick_movement(delta: float) -> void:
	var current_speed := _requested_speed()
	# Off a rail, the stick drives him at the ride's speed, wherever it points, until he lands -
	# free to turn, no heading kept. A released stick falls through to the ordinary air brake
	# below, and pushing again brings the full ride speed straight back. The landing then eases
	# it out - _apply_rail_land_ease(). See "Rail jump keeps its speed until the ground".
	if _rail_launch_carry and not is_on_floor() and direction:
		var held := direction * _rail_launch_speed * input_strength
		velocity.x = held.x
		velocity.z = held.z
		return
	if _apply_rail_land_ease(delta, current_speed):
		return
	var demanded := current_speed * input_strength if direction else 0.0
	var carried := _horizontal_speed()
	# The tredge keeps no momentum: momentum_decay is 0, so the gust's dip (and a run carried out
	# of the building) would never come off him. Eased at tredge_speed_rate instead.
	if is_tredging and is_on_floor():
		var eased := move_toward(carried, demanded, tredge_speed_rate * delta)
		var line := direction if direction \
			else (Vector3(velocity.x, 0.0, velocity.z) / carried if carried > 0.0001 else Vector3.ZERO)
		velocity.x = line.x * eased
		velocity.z = line.z * eased
		return
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

## The landing ease after a rail launch: on the floor, his flat speed goes from what he landed
## with to what the stick asks for now over rail_land_ease_time, on a smoothstep, steered by the
## stick (his own line with it released). True when it wrote velocity this frame. Ends itself in
## the air, when it runs out, or when he landed no faster than the target.
func _apply_rail_land_ease(delta: float, current_speed: float) -> bool:
	if _rail_land_ease_elapsed < 0.0:
		return false
	var target := current_speed * input_strength if direction else 0.0
	if not is_on_floor() or _rail_land_ease_from <= target + SPEED_EPSILON:
		_rail_land_ease_elapsed = -1.0
		return false
	_rail_land_ease_elapsed += delta
	var kept := _rail_land_speed_at(_rail_land_ease_from, target, rail_land_ease_time,
		_rail_land_ease_elapsed)
	if _rail_land_ease_elapsed >= rail_land_ease_time:
		_rail_land_ease_elapsed = -1.0
	var travel := Vector3(velocity.x, 0.0, velocity.z)
	var heading := direction if direction else 		(travel.normalized() if travel.length() > 0.0001 else Vector3.ZERO)
	velocity.x = heading.x * kept
	velocity.z = heading.z * kept
	return true

## The landing ease's speed `t` seconds in: smoothstep from `from` to `to` over `ease_time`,
## flat at `to` after. Static and pure.
static func _rail_land_speed_at(from: float, to: float, ease_time: float, t: float) -> float:
	if ease_time <= 0.0:
		return to
	return lerpf(from, to, smoothstep(0.0, 1.0, clampf(t / ease_time, 0.0, 1.0)))

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
##
## `facing` is the direction the wall ray is aimed along - his facing, ordinarily, or one of
## the two wall-run directions (see _try_mantle_off_wall_run()). `reach` overrides
## climb_probe_reach for the run-top ray, which has to span however far out a run holds him.
func _probe_ledge(facing: Vector3, reach: float = -1.0) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var feet := global_position
	var self_rid := get_rid()

	# 1. The wall. Cast below the shallowest lip the band accepts - see climb_probe_height -
	#    so it meets the face rather than sailing over the top of it.
	var eye := feet + Vector3.UP * climb_probe_height
	var forward_q := PhysicsRayQueryParameters3D.create(eye,
		eye + facing * (climb_probe_reach if reach < 0.0 else reach))
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

## Every airborne frame, ahead of _handle_wall_run(): the one place a mantle is started.
## Two regimes, because the question differs - see "Mantle vs wall-run" in
## docs/specs/pilot9-wall-run.md:
## - Not running: automatic, as it always was. A ledge in range along his facing takes him,
##   and it takes him BEFORE a wall-run attach is considered - into a reachable ledge is a
##   mantle, never a one-frame run that gets ripped off the wall.
## - Running: never by proximity. Only a ledge dead ahead along the run (an inside corner,
##   which is head-on to that wall) or the top of this wall when he steers into it.
func _handle_mantle_trigger() -> void:
	# A rail is ground he is riding, not a flight past a ledge - and it caught him first.
	if frozen or is_climbing or is_vaulting or is_dashing or is_rail_grinding \
			or is_rail_switching or is_on_floor() or is_tredging:
		return
	if is_wall_running:
		_try_mantle_off_wall_run()
	elif is_wall_climbing:
		# Into the face he is climbing, at the run-top reach - the capsule holds him off it.
		_try_start_climb_along(-_wall_climb_normal, maxf(climb_probe_reach, wall_run_probe_reach))
	else:
		_try_start_climb()

## Airborne, with a ledge in range along his facing. Returns false for every other case.
func _try_start_climb() -> bool:
	# Third person: the mesh yaw, which _handle_character_rotation() has been turning toward
	# travel every airborne frame - grab the wall he is flying at. First person: nothing
	# drives the mesh (that function early-returns), so character.rotation.y is stale and the
	# probe would fire at a fixed world heading. Aim it where the camera looks instead, the
	# way every other first-person heading in this controller is taken.
	var facing := _facing() if camera_mode == CameraMode.THIRD_PERSON \
		else -Vector3(sin(camera_pivot.rotation.y), 0.0, cos(camera_pivot.rotation.y))
	return _try_start_climb_along(facing)

## The mantle out of a wall-run - rows 2, 3 and 6 of the spec's table. The ahead ray follows
## the RUN, not his mesh: the mesh turns toward the stick, and a stick nudged into the wall
## would swing a mesh-aimed ray onto the very face he is running along.
func _try_mantle_off_wall_run() -> bool:
	if _try_start_climb_along(_wall_run_direction):
		return true
	var stick := _wall_run_stick()
	if not _steers_into_wall(stick, _wall_normal, wall_run_detach_angle):
		return false
	# A run holds him wherever he attached, up to wall_run_probe_reach out from the face -
	# the mantle's own 0.6 m reach made this hit on close attaches and miss on far ones.
	return _try_start_climb_along(-_wall_normal, maxf(climb_probe_reach, wall_run_probe_reach))

## True when the stick points into the wall - within wall_run_detach_angle of -wall_normal.
## Static and pure - see tests/test_pilot9_wall_run.gd.
static func _steers_into_wall(stick: Vector3, wall_normal: Vector3, detach_angle_deg: float) -> bool:
	var s := Vector3(stick.x, 0.0, stick.z)
	if s.length() <= 0.0001 or wall_normal.length() <= 0.0001:
		return false
	var theta := rad_to_deg(acos(clampf(s.normalized().dot(wall_normal.normalized()), -1.0, 1.0)))
	return theta - 90.0 > detach_angle_deg

## The shared tail: gates, one probe along `facing`, and the entry snap on a hit.
func _try_start_climb_along(facing: Vector3, reach: float = -1.0) -> bool:
	if not can_climb or is_climbing or is_on_floor():
		return false
	if climb_motion_y == null or climb_motion_z == null or climb_duration <= 0.0 or climb_speed <= 0.0:
		return false
	if facing.length() <= 0.0001:
		return false
	var ledge := _probe_ledge(facing.normalized(), reach)
	if ledge.is_empty():
		return false
	_start_climb(ledge["lip"], ledge["wall_normal"])
	return true

## The entry snap. Instant, never blended: a one or two frame blend here reads as a slide
## toward the wall, and the whole point of snapping is that the hands meet the edge every
## time rather than nearly every time.
func _start_climb(lip: Vector3, wall_normal: Vector3) -> void:
	is_climbing = true
	_anime_accent(&"mantle_grab", 1.0, func() -> bool: return is_climbing)
	_climb_time = 0.0
	_climb_jump_buffered = false
	# The mantle ends him standing, and it cannot be entered out of a slide anyway. Clearing
	# both is what stops the exit handing back into a pose he is visibly not in. The buffered
	# air-crouch goes too, for the reason `frozen` drops it: a stale slide firing on the frame
	# the mantle hands back is not what was asked for.
	is_crouching = false
	_slide_buffered = false
	_end_slide()
	# The wall-run handoff - see "The mantle handoff" in the spec. Position-driven from here,
	# same as every other mantle entry; nothing about a wall-run's own state survives it -
	# the wall coyote and the wall-jump's push included.
	_end_wall_run()
	# The lip off a wall climb - the same handoff.
	_end_wall_climb()
	_wall_climb_coyote_left = 0.0
	# Hard cut to `climb`, on every entry. The snap below has already put his frame-1 hands on
	# the lip, and that is only true of climb_up's frame 1 - any other pose, or any blend into
	# it, has his hands somewhere else. Left to the state machine the cut came 2+ frames late
	# (a fade in progress blocks every transition, and from Locomotion - a mantle on the first
	# airborne frame - there is no edge at all), then faded for 0.08 s more: measured
	# 2026-09-26, hands 0.5-1.1 m under the lip for the first ~7 frames, and the clip trailing
	# the path by as much afterwards, which floated them ~0.37 m OVER it mid-pull. Off a run
	# it also kills P_wall-runR's hip lean, which on a left wall pointed away from the wall.
	# advance(0) applies the cut this frame rather than on the tree's next tick.
	if anim_tree and anim_tree.active:
		var playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
		if playback:
			playback.start(&"climb")
			anim_tree.advance(0.0)
	_wall_coyote_left = 0.0
	_wall_jump_push_time = 0.0
	_rail_coyote_left = 0.0
	_rail_launch_carry = false
	_rail_land_ease_elapsed = -1.0
	# The mantle has its own buffer (`_climb_jump_buffered`) and it is the only one that
	# should survive into the exit. Two graces racing to spend the same press is one too
	# many, and a coyote window left running would outlive the floor he left long ago.
	_coyote_left = 0.0
	_jump_buffered = 0.0

	# Face the wall: the heading opposite its normal, flattened to the ground plane. A normal
	# with no horizontal part is not a wall to face, so hold the heading he arrived on.
	var into_wall := Vector3(-wall_normal.x, 0.0, -wall_normal.z)
	_climb_facing = into_wall.normalized() if into_wall.length() > 0.001 else _facing()
	# The entry snap is the plant - his hands meet the lip on this frame.
	_emit_hand_taps(lip, _climb_facing)
	character.rotation.y = atan2(_climb_facing.x, _climb_facing.z)
	# Level, snapped with the yaw. Left to their eases, the wall-run's camera roll (and any
	# leftover mesh pitch/roll) unwound over the mantle's first frames and read as a tilt.
	character.rotation.x = 0.0
	character.rotation.z = 0.0
	# Centred too: a wall climb's slide in toward the face eased out over the first frames and
	# carried the hands 0.09 m off the lip with it (tests/_probe_mantle_hands.gd, "from=wall_climb").
	character.position = Vector3.ZERO
	_reseed_body_lean()
	if camera_3d:
		camera_3d.rotation.z = 0.0
	_camera_wall_roll = 0.0

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

## -- the vault ----------------------------------------------------------------
##
## A grounded `jump` press with a thin, waist-high top ahead. See docs/specs/pilot9-vault.md.
## Detection runs once, on the press; the vault is then the mantle's machinery run sideways:
## a baked path, the clip seeked onto it, collision off while he is over the top. Unlike the
## mantle it hands back to physics halfway - from the hand release he is moved by
## move_and_slide(), so the landing is an ordinary landing.

## Metres above his feet the face ray is cast from. Under vault_band_min, for the reason the
## mantle's ray sits under its band: a ray above the top sails over it.
const VAULT_FACE_RAY_HEIGHT := 0.3
## Metres past the face the top ray looks down.
const VAULT_TOP_RAY_INSET := 0.15
## Spacing of the depth rays, in metres.
const VAULT_DEPTH_STEP := 0.25
## A depth ray that lands further than this from the top's height has left the top.
const VAULT_TOP_TOLERANCE := 0.3
## Metres of give on the height band's edges. His feet ride the floor at the physics safe margin
## (~1 mm up), so a 0.5 m wall measures 0.499 from them and fell off the 0.5 m edge.
const VAULT_EDGE_SLOP := 0.005
## The landing floor may be at most this far ABOVE his start.
const VAULT_MAX_LANDING_RISE := 0.3
## The body's height over the top at the apex - he goes over tucked, not standing. The apex
## clearance test is a capsule this tall.
const VAULT_APEX_HEIGHT := 1.0
## Metres under the path the post-release chase aims by the touchdown - see _apply_vault_motion().
const VAULT_TOUCHDOWN_SINK := 0.05
## The `vault` state's TimeSeek, built by scripts/pilot9_build_scene.gd::_ensure_vault_state() as
## VAULT_SEEK_NODE. Written every drawn frame by _seek_vault_clip() - a stale name here and he
## vaults frozen on frame 0, with nothing in the log.
const VAULT_SEEK_PARAM := "parameters/vault/VaultSeek/seek_request"
## The `dash` state and its two nodes, built by scripts/pilot9_build_scene.gd::_ensure_dash_state().
## Same silent-rename hazard as CROUCH_SCALE: set() on a missing path is not an error, and the
## cycle would run at authored speed from wherever it happened to be.
const DASH_STATE := &"dash"
const DASH_SCALE_PARAM := "parameters/dash/DashScale/scale"
const DASH_SEEK_PARAM := "parameters/dash/DashSeek/seek_request"

## Pure: does a probed obstacle qualify? Every argument is a measurement the probes took, in
## metres and degrees; the dials are read off this node. Kept free of raycasts so every edge of
## every check can be tested without a physics world (tests/test_pilot9_vault.gd).
##
## `reach` - near face ahead of his feet (capsule front). `height` - top above his feet.
## `angle` - approach off square. `depth` - near face to far edge, INF when the top ran past
## every depth ray. `top_slope` - degrees off level. `landing_rise` - landing floor above his
## start (negative is a drop), -INF when there is no floor at all.
func _qualifies_as_vault(reach: float, height: float, angle: float, depth: float,
		top_slope: float, landing_rise: float) -> bool:
	return reach >= vault_reach_min and reach <= vault_reach_max \
		and height >= vault_band_min - VAULT_EDGE_SLOP \
		and height <= vault_band_max + VAULT_EDGE_SLOP \
		and angle <= vault_max_angle \
		and depth <= vault_max_depth \
		and top_slope <= vault_max_top_slope \
		and landing_rise >= -vault_max_drop and landing_rise <= VAULT_MAX_LANDING_RISE

## The body path at clip fraction `u`, as (up, forward) metres from where he pressed - the baked
## curves bent onto this obstacle by `dh` (top above the authored top) and `dz` (hands further
## than authored). Three pieces, matching the bake's (see _ensure_vault_motion() in the builder):
##
## - **Up to the plant:** forward is SCALED so the hands arrive exactly `dz` further on - the
##   run-up squashes or stretches to fit the gap. Up blends `dh` in from the takeoff, so the
##   foot still on the floor does not sink into it.
## - **Plant to release:** the authored pinned path, shifted whole - the hands stay put.
## - **After the release:** forward keeps its shift, and `dh` eases back out by the touchdown,
##   so his feet come down at his start height whatever the wall was.
func _vault_path(u: float, dh: float, dz: float) -> Vector2:
	var up := vault_motion_y.sample(u) * vault_top_height
	var fwd := vault_motion_z.sample(u) * vault_travel
	if u <= vault_plant_time:
		var at_plant := vault_motion_z.sample(vault_plant_time) * vault_travel
		fwd = fwd * (at_plant + dz) / at_plant if at_plant > 0.01 \
			else fwd + dz * u / maxf(vault_plant_time, 0.001)
		up += dh * smoothstep(vault_takeoff_time, vault_plant_time, u)
	else:
		fwd += dz
		if u <= vault_release_time:
			up += dh
		else:
			up += dh * (1.0 - smoothstep(vault_release_time, vault_touchdown_time, u))
	return Vector2(up, fwd)

## Where _vault_path() puts him, in the world, for the vault running now.
func _vault_point(u: float) -> Vector3:
	var p := _vault_path(u, _vault_dh, _vault_dz)
	return _vault_start + Vector3.UP * p.x + _vault_dir * p.y

func _capsule_radius() -> float:
	var cap := collision_shape.shape as CapsuleShape3D if collision_shape else null
	return cap.radius if cap else 0.34

## Fires the rays and returns what they measured - {} when a ray found nothing to measure (no
## face, no top). The decision itself is _qualifies_as_vault()'s; this only measures.
func _probe_vault(facing: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return {}
	var feet := global_position
	var radius := _capsule_radius()
	var ex := [get_rid()]

	# 1. The near face, along his facing, from under the band.
	var eye := feet + Vector3.UP * VAULT_FACE_RAY_HEIGHT
	var face := _vault_ray(space, eye, eye + facing * (vault_reach_max + radius), ex)
	if face.is_empty() or not (face["collider"] is StaticBody3D):
		return {}
	var normal: Vector3 = face["normal"]
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length() < 0.5:
		return {}   # not a wall - a slope or a lip seen from below
	var dir := -flat.normalized()
	var face_pos: Vector3 = face["position"]

	# 2. The top, just past the face.
	var ceiling := feet.y + vault_band_max + VAULT_TOP_TOLERANCE
	var top_at := face_pos + dir * VAULT_TOP_RAY_INSET
	var top := _vault_ray(space, Vector3(top_at.x, ceiling, top_at.z),
		Vector3(top_at.x, feet.y + 0.05, top_at.z), ex)
	if top.is_empty():
		return {}
	var top_y: float = (top["position"] as Vector3).y

	# 3. The depth. Down rays stepped across the top until one leaves it; then one ray back
	#    toward the face at just under the top finds the far edge to the centimetre.
	var depth := INF
	var steps := int(ceil((vault_max_depth + VAULT_DEPTH_STEP - VAULT_TOP_RAY_INSET) / VAULT_DEPTH_STEP))
	for k in range(1, steps + 1):
		var along := VAULT_TOP_RAY_INSET + VAULT_DEPTH_STEP * k
		var at := face_pos + dir * along
		var hit := _vault_ray(space, Vector3(at.x, ceiling, at.z),
			Vector3(at.x, top_y - VAULT_TOP_TOLERANCE, at.z), ex)
		if not hit.is_empty():
			if (hit["position"] as Vector3).y > top_y + VAULT_TOP_TOLERANCE:
				return {}   # something taller stands on the top
			continue
		var low := Vector3(at.x, top_y - 0.05, at.z)
		var back := _vault_ray(space, low, low - dir * VAULT_DEPTH_STEP, ex)
		depth = along - VAULT_DEPTH_STEP * 0.5 if back.is_empty() \
			else ((back["position"] as Vector3) - face_pos).dot(dir)
		break

	# 4. The landing, where the clip puts his feet down. Only asked when the top is thin enough
	#    to have a far side - a deep top has no landing to find.
	var rise := -INF
	var anchor := _vault_anchor_inset(depth)
	if depth != INF:
		var land := face_pos + dir * (anchor + vault_post_travel)
		var hit := _vault_ray(space, Vector3(land.x, feet.y + VAULT_MAX_LANDING_RISE + 0.5, land.z),
			Vector3(land.x, feet.y - vault_max_drop - 0.1, land.z), ex)
		if not hit.is_empty():
			rise = (hit["position"] as Vector3).y - feet.y

	var along_face := (face_pos - feet).dot(dir)
	return {
		"reach": eye.distance_to(face_pos) - radius,
		"height": top_y - feet.y,
		"angle": rad_to_deg(acos(clampf(dir.dot(facing), -1.0, 1.0))),
		"depth": depth,
		"top_slope": rad_to_deg(acos(clampf((top["normal"] as Vector3).dot(Vector3.UP), -1.0, 1.0))),
		"landing_rise": rise,
		"dir": dir,
		# Metres along `dir` from his feet to where the hands go down.
		"anchor": along_face + anchor,
		"top_point": face_pos + dir * anchor + Vector3.UP * (top_y - face_pos.y),
	}

## How far past the near face the point between his hands goes down: the middle of the top,
## but never so far in that the rear (left) hand hangs off the near edge, and never past the
## point where the front (right) one would.
func _vault_anchor_inset(depth: float) -> float:
	var half := vault_hand_spread * 0.5
	var inset := half + 0.05
	if depth != INF:
		inset = minf(inset, maxf(depth * 0.5, VAULT_TOP_RAY_INSET))
	return inset

func _vault_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = exclude
	return space.intersect_ray(q)

## A shape overlap test against the static world at `feet` (his origin). A capsule of his own
## radius and `height`.
func _vault_clear(feet: Vector3, height: float) -> bool:
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = _capsule_radius()
	cap.height = maxf(height, cap.radius * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * cap.height * 0.5)
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	return space.intersect_shape(q, 1).is_empty()

## The press. Returns true when it became a vault; false leaves the press to the jump.
func _try_start_vault() -> bool:
	if not can_vault or is_vaulting or not is_on_floor() or frozen:
		return false
	if vault_motion_y == null or vault_motion_z == null or vault_duration <= 0.0 \
			or vault_clip_speed <= 0.0 or vault_travel <= 0.0:
		return false
	var facing := _facing() if camera_mode == CameraMode.THIRD_PERSON \
		else -Vector3(sin(camera_pivot.rotation.y), 0.0, cos(camera_pivot.rotation.y))
	var m := _probe_vault(facing)
	if m.is_empty() or not _qualifies_as_vault(m["reach"], m["height"], m["angle"], m["depth"],
			m["top_slope"], m["landing_rise"]):
		return false

	var dh: float = m["height"] - vault_top_height
	var dz: float = m["anchor"] - vault_plant_reach
	var dir: Vector3 = m["dir"]
	var start := global_position
	# 5. Clearance, checked last because it needs the path: the tucked body over the top, and
	#    the whole capsule where the release hands him back to physics - lifted onto the landing
	#    floor if a low wall's release sits under it, which is where _apply_vault_motion() will
	#    put him too.
	var top_point: Vector3 = m["top_point"]
	var apex := top_point + Vector3.UP * clampf(vault_foot_clearance, 0.05, 0.5)
	var rel := _vault_path(vault_release_time, dh, dz)
	var release := start + Vector3.UP * maxf(rel.x, m["landing_rise"] + 0.05) + dir * rel.y
	var cap := collision_shape.shape as CapsuleShape3D if collision_shape else null
	if not _vault_clear(apex, VAULT_APEX_HEIGHT) \
			or not _vault_clear(release, cap.height if cap else 1.9):
		return false

	var along := velocity.dot(dir)
	_vault_hand_top = top_point
	_start_vault(start, dir, maxf(along, speed), dh, dz, m["landing_rise"])
	return true

func _start_vault(start: Vector3, dir: Vector3, entry_speed: float, dh: float, dz: float,
		land_rise: float) -> void:
	is_vaulting = true
	_anime_accent(&"vault_plant", 1.0, func() -> bool: return is_vaulting)
	_vault_u = 0.0
	_vault_released = false
	_vault_jump_buffered = false
	_vault_slide_buffered = false
	_vault_start = start
	_vault_dir = dir
	_vault_speed = entry_speed
	_vault_dh = dh
	_vault_dz = dz
	_vault_land_rise = land_rise
	_vault_rate = (entry_speed / vault_clip_speed) / vault_duration
	# A vault out of a slide or a crouch leaves him standing, as the jump it replaces would.
	is_crouching = false
	_end_slide()
	_slide_buffered = false
	# The grounded graces are spent - the vault is the floor jump's replacement. The double jump
	# is NOT touched: a jump cancelled out of the vault is the floor jump, and the air jump is
	# still there after it.
	_coyote_left = 0.0
	_jump_buffered = 0.0
	_vault_u_prev = 0.0
	# Straight across, whatever the approach - into the turn-to-face model the way the mantle
	# writes the wall normal.
	character.rotation.y = atan2(dir.x, dir.z)
	character.rotation.x = 0.0
	character.rotation.z = 0.0
	_reseed_body_lean()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

## One physics frame of the vault.
func _apply_vault_motion(delta: float) -> void:
	var was := _vault_point(_vault_u)
	_vault_u_prev = _vault_u
	_vault_u = minf(_vault_u + delta * _vault_rate, 1.0)
	if _vault_u_prev < vault_plant_time and _vault_u >= vault_plant_time:
		_emit_hand_taps(_vault_hand_top, _vault_dir)

	if not _vault_released:
		if _vault_u < vault_release_time:
			global_position = _vault_point(_vault_u)
			velocity = (global_position - was) / maxf(delta, 0.0001)
			return
		# The release frame. Placed on the path, but never under the floor he is about to land
		# on - a low wall's release sits a few centimetres below it - and collision comes back.
		_vault_released = true
		var at := _vault_point(_vault_u)
		at.y = maxf(at.y, _vault_start.y + _vault_land_rise + 0.02)
		velocity = (at - global_position) / maxf(delta, 0.0001)
		global_position = at
		if collision_shape:
			collision_shape.set_deferred("disabled", false)
		# Floor snap off until he lands. No move_and_slide() has run since the press, so the body
		# still thinks it is standing where he started, and the first one after the release
		# snapped him FLOOR_SNAP_LENGTH straight down onto the floor - a half-metre drop in one
		# frame, measured 2026-09-27. _vault_let_go() puts it back.
		floor_snap_length = 0.0
		if _vault_jump_buffered:
			_vault_jump()
		return

	# After the release: chase the path through move_and_slide(), so a floor (or anything else)
	# stops him the way it would stop any body.
	var target := _vault_point(minf(_vault_u, vault_touchdown_time))
	# Aimed a few centimetres under the path as it comes down, so the touchdown is a contact
	# move_and_slide() reports rather than a body arriving exactly at the floor and hovering on it.
	target.y -= VAULT_TOUCHDOWN_SINK * smoothstep(vault_release_time, vault_touchdown_time, _vault_u)
	velocity = (target - global_position) / maxf(delta, 0.0001)
	if _vault_u >= vault_touchdown_time:
		# Past the clip's touchdown with no floor under him: a vault off an edge. Gravity's.
		velocity.y = minf(velocity.y, 0.0)
	_landing_speed_in = maxf(-velocity.y, 0.0)
	move_and_slide()
	if is_on_floor():
		_end_vault(true)
	elif _vault_u >= vault_touchdown_time:
		_end_vault(false)

## `landed` - on the floor (hand to Locomotion) or not (off an edge, hand to fall). Either way
## he leaves at the entry speed along the vault, and a buffered crouch is spent here.
func _end_vault(landed: bool) -> void:
	if not is_vaulting:
		return
	_vault_let_go()
	velocity = Vector3(_vault_dir.x * _vault_speed, 0.0 if landed else minf(velocity.y, 0.0),
		_vault_dir.z * _vault_speed)
	if _vault_slide_buffered:
		_vault_slide_buffered = false
		if landed:
			var heading := _travel_direction(Input.get_vector("left", "right", "forward", "backward"))
			if _can_start_slide(heading):
				_start_slide(heading)
		else:
			_slide_buffered = true   # the air buffer - spent on the landing like any other

## The jump out of a vault: the floor jump, taken from wherever the vault has him, at the entry
## speed along it. Spends nothing else - the double jump is still in hand.
func _vault_jump() -> void:
	_vault_let_go()
	_vault_slide_buffered = false
	velocity = _vault_dir * _vault_speed + Vector3.UP * jump_velocity
	is_jumping = true
	_coyote_left = 0.0

## Ends a vault that did not finish - a freeze, or boarding the mech. Before the release he has
## no collision and is somewhere over the top, so he is put where the release would have put him
## (proved clear on the press); after it he is simply let go.
func _abort_vault() -> void:
	if not is_vaulting:
		return
	if not _vault_released:
		var at := _vault_point(vault_release_time)
		at.y = maxf(at.y, _vault_start.y + _vault_land_rise + 0.02)
		global_position = at
		reset_physics_interpolation()
	_vault_let_go()
	_vault_slide_buffered = false
	velocity = Vector3.ZERO

## What every way out of a vault shares: the flag, the jump buffer, the collision shape and the
## floor snap the release switched off.
func _vault_let_go() -> void:
	is_vaulting = false
	_vault_jump_buffered = false
	floor_snap_length = FLOOR_SNAP_LENGTH
	if collision_shape:
		collision_shape.set_deferred("disabled", false)

## The clip's clock, in clip seconds - the controller's, not the tree's. See _seek_vault_clip().
func vault_clip_time() -> float:
	return _vault_u * vault_duration

## Seeks the `vault` state onto the controller's clock every drawn frame, so the pose and the
## path cannot part. pilot9_animation.gd holds the state's TimeScale at 0: the clip never
## advances on its own.
##
## From _process(), not the physics tick, and at the INTERPOLATED clip time. What is drawn is his
## physics-interpolated position - up to a tick behind the last one - and a pose seeked from the
## tick itself was that tick ahead of it: 0.12 m of hand sliding along the top at a sprint. This
## node's _process() also runs before the AnimationTree's own processing (a parent before its
## children), so the seek lands on this frame's pose rather than the next one's.
func _seek_vault_clip() -> void:
	if not is_vaulting or anim_tree == null:
		return
	var u := _vault_u
	if is_physics_interpolated_and_enabled():
		u = lerpf(_vault_u_prev, _vault_u, Engine.get_physics_interpolation_fraction())
	anim_tree.set(VAULT_SEEK_PARAM, u * vault_duration)

## -- the dash -----------------------------------------------------------------
##
## He flies at `dash_speed` for `dash_time`, fully visible since 2026-09-28: the tree is hard-cut
## onto the sprint cycle (the `dash` state) and a trail of afterimages drops behind him - see
## docs/specs/pilot9-dash.md, "The afterimages". It used to be a vanish with an ink streak, and
## no clip or state at all; that history is in the spec. Two limiters gate it (a cooldown measured from
## the press, and one air charge that only ever subtracts), and it wins outright over the
## crouch and the slide but is refused outright by the mantle and by `frozen`.

const _ApplyStylized := preload("res://scripts/rendering/apply_stylized.gd")

## The press, the cooldown clock, the air-charge refresh, and the running dash's own timer.
## Split from _apply_dash_velocity()/_check_dash_blocked() because those need to run either
## side of move_and_slide() in _physics_process(), and this does not.
func _handle_dash(delta: float) -> void:
	_dash_air_charge = _dash_air_charge_refreshed(_dash_air_charge, is_on_floor())
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)

	if frozen:
		# The same class as a freeze mid-slide or mid-mantle: not a moment the player is
		# still asking to be dashing through.
		if is_dashing:
			_end_dash()
		return

	if is_dashing:
		_dash_time_left -= delta
		if _dash_time_left <= 0.0:
			_end_dash()
		return

	# Mantle and frozen both refuse a fresh dash outright rather than queuing one - see
	# _dash_availability(). Climbing is not cancellable and a dash out of the middle of it
	# would fling a collider-less pilot9 through geometry.
	if is_tredging or not Input.is_action_just_pressed("dash") or not _can_dash():
		return

	# Fresh input, not `direction`: this runs ahead of _handle_movement_input() in
	# _physics_process(), the same reason the slide's press reads a fresh vector too.
	var heading := _travel_direction(Input.get_vector("left", "right", "forward", "backward"))
	if is_rail_grinding:
		# Off a rail the dash launches along the ride, bent toward the stick by at most
		# rail_jump_max_bend - the jump's own rule. Spends the air charge the rail refilled.
		heading = _rail_jump_heading(_rail_ride_tangent(), heading, rail_jump_max_bend)
		_end_rail_grind(RailExit.DASH)
	if heading == Vector3.ZERO:
		heading = _facing()          # the same fallback player.gd's DASH uses
	_start_dash(heading)

func _can_dash() -> bool:
	# The rail switch is committed - see _tick_rail_switch(). The vault is refused for the
	# mantle's reason: a scripted path over an edge, collision off for the first half of it.
	if is_rail_switching or is_vaulting:
		return false
	return _dash_availability(can_dash, _dash_cooldown_left, _dash_air_charge, is_on_floor(),
		is_climbing, frozen)

## Both limiters and all four blocked states, as one pure function: `can_dash` off, mid-climb,
## frozen, or still on cooldown with no air charge left to spend instead. Static so it can be
## asserted with no tree - see tests/test_pilot9_dash.gd.
static func _dash_availability(can_dash_: bool, cooldown_left: float, air_charge: bool,
		on_floor: bool, climbing: bool, frozen_: bool) -> bool:
	if not can_dash_ or climbing or frozen_ or cooldown_left > 0.0:
		return false
	return on_floor or air_charge

## Refreshed the instant he touches a floor - landing, or finishing a mantle onto a ledge -
## whatever the charge already was. Pure, and the reason it is pure is the same reason
## _slope_accel() is: is_on_floor() cannot be made true without a physics world.
static func _dash_air_charge_refreshed(air_charge: bool, on_floor: bool) -> bool:
	return true if on_floor else air_charge

## Spent by a dash LAUNCHED while airborne, and only then - a ground dash that carries him off
## a ledge (which it will; gravity is suspended and the line is flat) leaves the charge
## intact, because he started it on the floor.
static func _dash_air_charge_after_launch(air_charge: bool, launched_on_floor: bool) -> bool:
	return air_charge if launched_on_floor else false

## The entry snap - instant, like the mantle's: the heading, the velocity and the clip (a hard
## cut onto the sprint cycle) all switch on this tick.
func _start_dash(heading: Vector3) -> void:
	_dash_air_charge = _dash_air_charge_after_launch(_dash_air_charge, is_on_floor())
	is_dashing = true
	_dash_time_left = dash_time
	_dash_cooldown_left = dash_cooldown
	_dash_direction = _dash_aim(heading)
	# Dash wins over the crouch and the slide - free here because his collider never resizes
	# (see docs/specs/pilot9-dash.md, Interactions) and because the flat dash_speed replaces
	# whatever speed the slide was carrying rather than stacking onto it.
	is_crouching = false
	_end_slide()
	_slide_buffered = false
	# Neither grace should survive a dash - see _handle_gravity_and_jump()'s own note on why
	# both are frozen rather than ticked while this is true.
	_coyote_left = 0.0
	_jump_buffered = 0.0
	# A dash ends the wall-jump's push protection and closes the wall coyote - it is its own
	# answer to "where next", not a wall-jump. See "The dash" in docs/specs/pilot9-wall-run.md.
	_wall_jump_push_time = 0.0
	_wall_coyote_left = 0.0
	# A dash ends a climb (the cooldown starts) and closes its coyote - the wall-run's rule.
	_end_wall_climb()
	_wall_climb_coyote_left = 0.0
	# Same for the rail's: a dash is its own answer to "where next".
	_rail_coyote_left = 0.0
	_rail_launch_carry = false
	_rail_land_ease_elapsed = -1.0
	# The opening snap - same weld _handle_character_rotation() re-applies every later frame
	# once _steer_dash() has had a chance to move _dash_direction, instant both times because
	# nobody sees it happen.
	character.rotation.y = atan2(_dash_direction.x, _dash_direction.z)
	velocity = _dash_direction * dash_speed
	# He stays visible now (2026-09-28): the tree is cut onto the sprint cycle and the first
	# afterimage drops where he stands. See docs/specs/pilot9-dash.md, "The afterimages".
	_cut_to_dash_clip()
	if _afterimage != null:
		_afterimage.begin(character, _effects_on())
	# Let the shot fall behind for the window and glide back on afterward instead of staying
	# welded to him - see _process() and docs/specs/pilot9-dash.md, Camera. The pivot's current
	# position IS this frame's weld target already (nothing else has touched it), so capturing
	# it here as the lerp's start is a no-op position-wise - the lag begins from exactly where
	# the hard weld left off, with no jump.
	_camera_dash_lag_active = true
	_camera_dash_lag_start = camera_pivot.global_position
	_camera_dash_lag_elapsed = 0.0

## The exit - on the timer, or cut short by _check_dash_blocked(). The moment he reappears via
## the timer or the block, whatever he is ACTUALLY carrying is clamped DOWN to `sprint_speed` if
## it is over that - same heading, same pattern as the slide entry's `_slide_reference_speed`
## clamp. Downward only and off the real velocity rather than `dash_speed` outright, so a dash
## cut short by _check_dash_blocked() (already near zero) is not shoved back up to sprint speed
## into whatever just stopped him. He reappears already at sprint speed, not visibly carrying
## dash speed for even a frame; a separate 2026-09-18 attempt at a slower
## _apply_dash_exit_ease() blend was tried and reverted the same day for exactly that reason.
## Sprint is the one exception to any of this - he always
## comes out of a dash toggled into a sprint, on the ground or airborne. Airborne, is_sprinting
## itself stays false until is_on_floor() (see _requested_speed()); sprint_toggled surviving the
## fall is what makes him sprint the instant he lands rather than needing the player to re-press
## sprint into a stopped dash's momentum. _end_verbs_for_boarding() calls this and then
## overwrites sprint_toggled to false right after, so boarding EXIA mid-dash is unaffected.
## No cooldown refund either way - see docs/specs/pilot9-dash.md, "Blocked mid-dash".
func _end_dash() -> void:
	if not is_dashing:
		return
	is_dashing = false
	_dash_time_left = 0.0
	if _afterimage != null:
		_afterimage.end()
	sprint_toggled = true
	# Downward clamp only, off whatever he is ACTUALLY carrying (get_real_velocity()'s
	# heading, not _dash_direction) - a dash cut short by _check_dash_blocked() is already
	# near zero and this must not shove him back up to sprint_speed into the wall that just
	# stopped him.
	var carried := _horizontal_speed()
	if carried > sprint_speed:
		var heading := Vector3(velocity.x, 0.0, velocity.z) / carried
		velocity.x = heading.x * sprint_speed
		velocity.z = heading.z * sprint_speed

## Steers the dash - retuned 2026-09-18, reversing the original locked-heading design after the
## user tried it and changed their mind. Unlike _steer_slide(), this is not a lerp. That was
## free while he was invisible for the window; since 2026-09-28 he is visible and a hard turn
## is a visible yaw snap, kept on purpose - control beats clip fidelity on pilot9 - and on the
## spec's risk list. The heading can snap as many times as the stick asks for. Stick
## centred, `direction` is Vector3.ZERO and the heading holds - the same "no input, no change"
## rule _steer_slide() follows, and the same fallback _start_dash() uses at launch. Read only
## while is_dashing (see the caller in _physics_process()), so this never touches
## _dash_direction outside the window it is allowed to move.
func _steer_dash() -> void:
	var heading := direction
	if heading == Vector3.ZERO:
		heading = Vector3(_dash_direction.x, 0.0, _dash_direction.z)
		if heading.length() < 0.0001:
			return
	_dash_direction = _dash_aim(heading)

## Flattens a heading onto the ground plane - the dash is horizontal only, whatever the camera's
## pitch. Unit length out, so `dash_speed` is the true speed.
func _dash_aim(heading: Vector3) -> Vector3:
	return Vector3(heading.x, 0.0, heading.z).normalized()

## Bypasses _apply_movement() while the dash runs, exactly as _apply_slide_velocity() does for
## the slide - steered by _steer_dash() every frame, gravity suspended.
func _apply_dash_velocity() -> void:
	velocity = _dash_direction * dash_speed

## The one collision check, run AFTER move_and_slide() so get_real_velocity() reflects what
## actually happened this frame rather than what was demanded. A small fraction of dash_speed
## means a wall, a corner, a slope shoulder or a ceiling stopped him; without this the naive
## implementation pins an invisible pilot9 motionless for up to half a second, reappearing
## exactly where he already was. See docs/specs/pilot9-dash.md, "Blocked mid-dash".
func _check_dash_blocked() -> void:
	var moved := get_real_velocity()
	if Vector2(moved.x, moved.z).length() < dash_speed * DASH_BLOCKED_SPEED_FRACTION:
		_end_dash()

## Puts the rim light on (or takes it off) every mesh under `character`. An overlay rather than
## a next_pass so it stays clear of the per-surface cel materials apply_stylized stamps on.
func _apply_rim_light() -> void:
	if character == null:
		return
	var overlay: Material = rim_light_material if rim_light_enabled and not rim_light_suppressed else null
	var meshes: Array[MeshInstance3D] = []
	_ApplyStylized.collect_meshes(character, meshes)
	for mi in meshes:
		# The held item rides under his skeleton but the rim stays pilot-only.
		if item_holder != null and item_holder.owns(mi):
			continue
		mi.material_overlay = overlay

## -- the wall-run ---------------------------------------------------------------
##
## Airborne, moving along a near-vertical face, he sticks to it and runs - flat, then
## drooping. Automatic, like the mantle: no button, and _wall_run_gates() is the whole
## feature. See docs/specs/pilot9-wall-run.md.

## The direction two sideways probe rays fire along, and the direction a fresh attach's
## tangent is measured against - his current horizontal travel, or his facing if he has none.
func _wall_run_travel_direction() -> Vector3:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	return horizontal.normalized() if horizontal.length() > 0.0001 else _facing()

## Two rays, left and right of `travel_dir`, `wall_run_probe_reach` long - the pattern
## _probe_ledge() uses for its own forward ray. Returns the first hit, or {} if neither ray
## found anything: every airborne frame away from a wall.
func _probe_wall(travel_dir: Vector3) -> Dictionary:
	if travel_dir.length() <= 0.0001:
		return {}
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var origin := global_position + Vector3.UP * WALL_RUN_PROBE_HEIGHT
	var self_rid := get_rid()
	var t := travel_dir.normalized()
	for side in [t.rotated(Vector3.UP, -PI / 2.0), t.rotated(Vector3.UP, PI / 2.0)]:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + side * wall_run_probe_reach)
		query.exclude = [self_rid]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit
	return {}

## Single forward ray along travel_dir, wall_run_probe_reach long - the head-on companion to
## _probe_wall()'s sideways pair. Dead-on into a wall the sideways rays skim the face and find
## nothing; this is what actually sees it. Only used to catch the case _probe_wall() cannot -
## not to sustain an attached run.
func _probe_wall_ahead(travel_dir: Vector3) -> Dictionary:
	if travel_dir.length() <= 0.0001:
		return {}
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var origin := global_position + Vector3.UP * WALL_RUN_PROBE_HEIGHT
	var t := travel_dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + t * wall_run_probe_reach)
	query.exclude = [get_rid()]
	return space.intersect_ray(query)

## The sustain ray: one ray straight at the face he is running on (along -_wall_normal, kept
## current by _follow_wall()), `height` above his feet, wall_run_probe_reach long. Toward the
## wall side only - the far side is nothing to do with this run. The hit carries its `origin`
## so the gap can be measured from it. {} when it finds nothing.
func _probe_wall_side(height: float) -> Dictionary:
	var into := -Vector3(_wall_normal.x, 0.0, _wall_normal.z)
	if into.length() <= 0.0001:
		return {}
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var origin := global_position + Vector3.UP * height
	var query := PhysicsRayQueryParameters3D.create(origin,
		origin + into.normalized() * wall_run_probe_reach)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		hit["origin"] = origin
	return hit

## True when a face with `new_normal` is still the wall he is running on - within `max_deg` of
## `current`. Static and pure - see tests/test_pilot9_wall_run.gd.
static func _wall_follows(current: Vector3, new_normal: Vector3, max_deg: float) -> bool:
	if current.length() <= 0.0001 or new_normal.length() <= 0.0001:
		return false
	var d := clampf(current.normalized().dot(new_normal.normalized()), -1.0, 1.0)
	return rad_to_deg(acos(d)) <= max_deg + 0.0001

## Re-takes the face from this frame's sustain hit: the normal, the plane point, the run's
## tangent (re-projected, speed kept) and the gap the pull closes. The side never changes
## mid-run; the lean follows the refreshed normal.
func _follow_wall(normal: Vector3, point: Vector3, origin: Vector3) -> void:
	_wall_normal = normal.normalized()
	_wall_point = point
	var tangent := _wall_run_direction - _wall_normal * _wall_run_direction.dot(_wall_normal)
	tangent.y = 0.0
	if tangent.length() > 0.0001:
		_wall_run_direction = tangent.normalized()
	_wall_run_gap = (origin - point).dot(_wall_normal)

## How far off the face the run holds his centre: the capsule's radius plus a hair of skin.
## Read from the shape so a re-sized capsule does not grind into walls.
func _wall_run_hold_distance() -> float:
	var r := 0.34
	var cs: CollisionShape3D = collision_shape if collision_shape \
		else get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape is CapsuleShape3D:
		r = (cs.shape as CapsuleShape3D).radius
	return r + WALL_RUN_HOLD_MARGIN

## His speed toward the face this frame (negative = away): the gap past the hold distance,
## closed over `pull_time`. Static and pure.
static func _wall_run_pull_speed(gap: float, hold: float, pull_time: float) -> float:
	if pull_time <= 0.0:
		return 0.0
	return (gap - hold) / pull_time

## The raw stick in the RUN's frame rather than the camera's: stick-forward is
## _wall_run_direction, stick-right is the run's right. Read by the
## steer-in, so the camera is free for the length of a run. See "Staying on the wall" (2).
func _wall_run_stick() -> Vector3:
	return _run_frame_stick(Input.get_vector("left", "right", "forward", "backward"),
		_wall_run_direction)

## `raw` is Input.get_vector()'s (x right, y back). Static and pure.
static func _run_frame_stick(raw: Vector2, run_dir: Vector3) -> Vector3:
	var fwd := Vector3(run_dir.x, 0.0, run_dir.z)
	if raw.length() <= 0.0001 or fwd.length() <= 0.0001:
		return Vector3.ZERO
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	return (fwd * -raw.y + right * raw.x).normalized()

## The head-on counterpart to _wall_run_gates(): gates 1, 2, 3 and 6, but the angle test looks
## for travel near dead-on (theta close to 180) rather than along the face (theta close to 90).
## No gate 5 - he cannot be moving away from a wall he is running dead into. Static and pure
## for the same reason - see tests/test_pilot9_wall_run.gd.
static func _wall_run_head_on_gates(on_floor: bool, horizontal_speed: float, wall_normal: Vector3,
		travel_dir: Vector3, is_dashing_: bool, min_speed: float,
		wall_angle_deg: float, head_on_angle_deg: float) -> bool:
	if on_floor or is_dashing_:
		return false
	if horizontal_speed < min_speed:
		return false
	if wall_normal.length() <= 0.0001 or travel_dir.length() <= 0.0001:
		return false
	var n := wall_normal.normalized()
	if absf(n.y) > sin(deg_to_rad(wall_angle_deg)):
		return false
	var theta := rad_to_deg(acos(clampf(travel_dir.normalized().dot(n), -1.0, 1.0)))
	return theta >= 180.0 - head_on_angle_deg

## The missing tangent for a head-on attach: his own travel projects to zero on the wall plane,
## so the camera's horizontal look direction supplies it instead - the same projection
## _start_wall_run() does for travel_dir, sourced from the camera rather than from velocity.
## Looking right along the wall starts the run to the right, and looking left starts it left.
## Returns Vector3.ZERO if the camera is also looking dead into the wall - no redirect to give.
func _camera_wall_run_tangent(wall_normal: Vector3) -> Vector3:
	var forward := -Vector3(sin(camera_pivot.rotation.y), 0.0, cos(camera_pivot.rotation.y))
	var n := wall_normal.normalized()
	var tangent := forward - n * forward.dot(n)
	return tangent.normalized() if tangent.length() > 0.0001 else Vector3.ZERO

## The six gates, as one pure function: airborne (`on_floor` false), a run and not a drift
## (`min_speed`), the face near-vertical (`wall_angle_deg`), travel along the face rather than
## into it (`attach_angle_deg`), not moving away from the face, and not mid-dash. Static so
## every one of them, including the head-on case that must be refused, is assertable with no
## tree - see tests/test_pilot9_wall_run.gd. "Hitting a wall head-on is a wall-hit" falls
## straight out of the same formula the attach angle already is: head-on puts `theta` near
## 180, which is nowhere near the 90 a face he is running ALONG puts it at.
##
## Gate 5 is the re-grab fix. Straight off a wall-jump his travel is ~41 degrees off the
## normal he just left, which gate 4 alone accepts - and he would be welded straight back on.
## It is not a lockout: turning back toward the same wall is moving toward it, and attaches.
static func _wall_run_gates(on_floor: bool, horizontal_speed: float, wall_normal: Vector3,
		travel_dir: Vector3, is_dashing_: bool, min_speed: float,
		wall_angle_deg: float, attach_angle_deg: float) -> bool:
	if on_floor or is_dashing_:
		return false
	if horizontal_speed < min_speed:
		return false
	if wall_normal.length() <= 0.0001 or travel_dir.length() <= 0.0001:
		return false
	var n := wall_normal.normalized()
	if absf(n.y) > sin(deg_to_rad(wall_angle_deg)):
		return false
	var t := travel_dir.normalized()
	# Gate 5. A hair of tolerance so travel exactly along the face is not refused on noise.
	if t.dot(n) > WALL_RUN_AWAY_EPSILON:
		return false
	var theta := rad_to_deg(acos(clampf(t.dot(n), -1.0, 1.0)))
	return absf(theta - 90.0) <= attach_angle_deg

## True when a face (`normal`, through `point`) is the same plane as the one stored in
## `lock_normal` / `lock_point` - facing the same way and within a hand's width of it. The
## plane rather than the hit point, because the probe lands somewhere different along the
## wall every frame. A zero `lock_normal` means no lockout. Static and pure.
static func _same_wall(lock_normal: Vector3, lock_point: Vector3, normal: Vector3,
		point: Vector3) -> bool:
	if lock_normal.length() <= 0.0001 or normal.length() <= 0.0001:
		return false
	var a := lock_normal.normalized()
	if a.dot(normal.normalized()) < WALL_SAME_FACE_DOT:
		return false
	return absf((point - lock_point).dot(a)) <= WALL_SAME_PLANE_DISTANCE

## The instance wrapper around _wall_run_gates(): static and pure where possible, reading
## live state (is_on_floor(), _horizontal_speed(), is_dashing, the same-wall lockout) only
## where a pure function cannot.
func _can_start_wall_run(hit: Dictionary, travel_dir: Vector3) -> bool:
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if _same_wall(_wall_lockout_normal, _wall_lockout_point, normal,
			hit.get("position", Vector3.ZERO)):
		return false
	return _wall_run_gates(is_on_floor(), _horizontal_speed(), normal, travel_dir, is_dashing,
		wall_run_min_speed, wall_run_wall_angle, wall_run_attach_angle)

## Entry, timer and exit - the dash's own split, and for the same reason: this runs ahead of
## _handle_gravity_and_jump() (see _physics_process()) and owns the jump press and the detach
## checks, while _apply_wall_run_velocity() owns the velocity itself from the if/elif tail.
func _handle_wall_run(delta: float) -> void:
	if is_wall_running:
		_wall_run_time += delta
		if frozen:
			# The same class as a freeze mid-slide or mid-mantle: not a moment the player is
			# still asking to be wall-running through.
			_end_wall_run()
			return
		if Input.is_action_just_pressed("jump"):
			# Buffered rather than taken outright - see _wall_jump_buffered's own note on why.
			_wall_jump_normal = _wall_normal
			_wall_jump_buffered = true
			_end_wall_run()
			return
		# No crouch or stick let-go: jump, the wall ending and the run's own clock are the only
		# ways off. See "Committed to the wall" in docs/specs/pilot9-wall-run.md.
		if _wall_run_time >= wall_run_flat_time + wall_run_droop_time:
			_let_go_of_wall(WallLetGo.TIMER)
			return
		var wall_hit := _probe_wall_side(WALL_RUN_PROBE_HEIGHT)
		if wall_hit.is_empty():
			wall_hit = _probe_wall_side(WALL_RUN_LOW_PROBE_HEIGHT)
			if wall_hit.is_empty():
				# The wall ended. Detach keeping every bit of velocity - the free launch off
				# the end of a wall the spec calls out by name.
				_let_go_of_wall(WallLetGo.WALL_ENDED)
				return
			# Only the low ray still sees the face. Rising, he has come up past the top of
			# the wall: the rise ends here and the run carries on along the top. Level, it is
			# a gap at chest height - a window - and he runs on past it.
			if not _wall_run_leveled:
				velocity.y = 0.0
				_wall_run_leveled = true
		var wall_face_normal: Vector3 = wall_hit.get("normal", Vector3.ZERO)
		if not _wall_follows(_wall_normal, wall_face_normal, wall_run_follow_angle):
			# The face turned more sharply than a seam or a curve - a different wall.
			_let_go_of_wall(WallLetGo.WALL_ENDED)
			return
		_follow_wall(wall_face_normal, wall_hit["position"], wall_hit["origin"])
		return

	if frozen or is_climbing or is_vaulting or is_dashing or is_rail_grinding \
			or is_rail_switching or is_wall_climbing or is_on_floor() or not can_wall_run \
			or is_tredging:
		return
	var travel := _wall_run_travel_direction()
	var hit := _probe_wall(travel)
	if _can_start_wall_run(hit, travel):
		# No top-of-wall refusal here: running ALONG a wall he is not facing it, so the mantle
		# would not take the lip either and the refusal was a dead zone. Steering in takes the
		# top off the run. See "Staying on the wall" (1) in the spec.
		_start_wall_run(hit["normal"], travel, hit["position"])
		return
	# Camera-redirected head-on attach: running dead-on into a wall projects to nothing on the
	# wall plane, so there is no travel-direction tangent to run along, and _probe_wall()'s
	# sideways rays skim the face rather than hitting it. A forward ray catches the wall the
	# side rays cannot see, and the camera's look direction - not his travel - supplies the
	# missing tangent. See "Camera-redirected head-on attach" in the spec.
	var ahead := _probe_wall_ahead(travel)
	if ahead.is_empty():
		return
	var normal: Vector3 = ahead.get("normal", Vector3.ZERO)
	if _same_wall(_wall_lockout_normal, _wall_lockout_point, normal, ahead["position"]):
		return
	if not _wall_run_head_on_gates(is_on_floor(), _horizontal_speed(), normal, travel,
			is_dashing, wall_run_min_speed, wall_run_wall_angle, wall_run_head_on_angle):
		return
	if _wall_top_in_mantle_reach(normal):
		return
	var camera_tangent := _camera_wall_run_tangent(normal)
	if camera_tangent.length() <= 0.0001:
		return
	_start_wall_run(normal, camera_tangent, ahead["position"])

## The top of the wall is mantle territory for a HEAD-ON attach (2026-09-24): if a mantle
## could take this wall's lip from where he is, that attach is refused, so the two never share
## a frame. A sideways attach no longer asks - see "Staying on the wall" (1). It is the mantle's own probe aimed into the face, at the run-top reach
## _try_mantle_off_wall_run() uses, so "reachable" means exactly what the mantle means by it.
## See "No wall-run at the top of a wall" in docs/specs/pilot9-wall-run.md.
func _wall_top_in_mantle_reach(wall_normal: Vector3) -> bool:
	if not can_climb or wall_normal.length() <= 0.0001:
		return false
	var into := -Vector3(wall_normal.x, 0.0, wall_normal.z).normalized()
	return not _probe_ledge(into, maxf(climb_probe_reach, wall_run_probe_reach)).is_empty()

## The entry snap - instant, like the mantle's and the dash's. Stores the face, and keeps
## only the ALONG-WALL part of his speed: the part into the face is dropped, or arriving off a
## wall-jump at 7.5 along + 8.5 in would start the next run at 11.3 m/s and chains would
## snowball. A rising velocity.y is left alone - he finishes the jump he was on. See "Attach
## and detach" and "Rise, then flat, then droop" in the spec.
func _start_wall_run(normal: Vector3, travel_dir: Vector3, point: Vector3 = Vector3.ZERO) -> void:
	is_wall_running = true
	_wall_run_time = 0.0
	_wall_normal = normal.normalized()
	_wall_point = point
	_wall_run_gap = (global_position + Vector3.UP * WALL_RUN_PROBE_HEIGHT - point) \
		.dot(_wall_normal) if point != Vector3.ZERO else _wall_run_hold_distance()
	var tangent := travel_dir - _wall_normal * travel_dir.dot(_wall_normal)
	_wall_run_direction = tangent.normalized() if tangent.length() > 0.0001 \
		else travel_dir.normalized()
	_wall_run_speed = _along_wall_speed(Vector3(velocity.x, 0.0, velocity.z), _wall_run_direction)
	_wall_run_right = _wall_on_right_of(_wall_normal, _wall_run_direction)
	# Falling, the fall is caught; rising, he finishes the arc under jump gravity.
	_wall_run_leveled = velocity.y <= 0.0
	if _wall_run_leveled:
		velocity.y = 0.0
	# Attaching ends the last wall-jump's push and closes any wall coyote, and a new face
	# frees the one he let go of - he cannot be attaching to the locked one, it was refused.
	_wall_jump_push_time = 0.0
	_wall_jump_steer_back = 0.0
	_wall_coyote_left = 0.0
	_wall_lockout_normal = Vector3.ZERO
	_wall_lockout_left = 0.0
	_rail_coyote_left = 0.0
	_rail_launch_carry = false
	_rail_land_ease_elapsed = -1.0
	is_crouching = false
	_end_slide()
	# In the tree only - the wall-run tests start runs on a pilot that has no position.
	if is_inside_tree():
		_wall_kick_point = _wall_foot_contact()
		if _effects_on():
			_vfx.wall_attach(_wall_kick_point, _wall_normal)
	# The AnimationTree's own `wall_run` state picks up `is_wall_running` on the next frame
	# (see _ensure_wall_run_state() in scripts/pilot9_build_scene.gd) - nothing to drive here.
	# It is the sprint cycle, which has no side, so neither wall mirrors anything.

## How much of `horizontal_velocity` runs along `direction` (a unit tangent in the wall
## plane), never negative. The part into or out of the face is what it throws away. Static
## and pure - see tests/test_pilot9_wall_run.gd.
static func _along_wall_speed(horizontal_velocity: Vector3, dir: Vector3) -> float:
	return maxf(horizontal_velocity.dot(dir), 0.0)

## The run's speed `t` seconds in: an `entry` under `target` ramps up to it linearly across
## `ramp`; one at or over it is held. The wall lifts a jog to a sprint and never adds to a
## sprint. Static and pure - see tests/test_pilot9_wall_run.gd.
static func _wall_run_speed_at(entry: float, target: float, ramp: float, t: float) -> float:
	if entry >= target:
		return entry
	if ramp <= 0.0:
		return target
	return lerpf(entry, target, clampf(t / ramp, 0.0, 1.0))

## Bypasses _apply_movement() while the run holds, exactly as _apply_dash_velocity() does for
## the dash. Horizontal: along _wall_run_direction at _wall_run_speed_at(). Vertical, three
## phases on one clock: the rise (the jump he attached on, under jump_gravity through
## _gravity_scale(), exactly as any jump), then held flat at 0 until wall_run_flat_time, then
## drooping at `wall_run_droop_gravity` of jump_gravity. A rise still going when the flat clock
## runs out keeps its own gravity - it is already coming down faster than the droop would.
## See "Rise, then flat, then droop" in the spec.
func _apply_wall_run_velocity(delta: float) -> void:
	var s := _wall_run_speed_at(_wall_run_speed, wall_run_speed, wall_run_speed_ramp,
		_wall_run_time)
	# Held to the face: the gap past the hold distance, closed along -normal. Perpendicular to
	# the run, so the 15 m grid never sees it. See "Staying on the wall" (4).
	var pull := _wall_run_pull_speed(_wall_run_gap, _wall_run_hold_distance(), wall_run_pull_time)
	var n := Vector3(_wall_normal.x, 0.0, _wall_normal.z).normalized()
	velocity.x = _wall_run_direction.x * s - n.x * pull
	velocity.z = _wall_run_direction.z * s - n.z * pull
	if not _wall_run_leveled:
		var gravity_mult := _gravity_scale(velocity.y, jump_fall_multiplier, jump_apex_speed,
			jump_apex_scale)
		velocity.y = maxf(velocity.y - jump_gravity * gravity_mult * delta, -max_fall_speed)
		if velocity.y <= 0.0 and _wall_run_time <= wall_run_flat_time:
			velocity.y = 0.0
			_wall_run_leveled = true
		return
	if _wall_run_time <= wall_run_flat_time:
		velocity.y = 0.0
	else:
		var droop_elapsed := _wall_run_time - wall_run_flat_time
		velocity.y = maxf(-jump_gravity * wall_run_droop_gravity * droop_elapsed, -max_fall_speed)

## The launch speed of the nth chained wall-jump. Height is v*v / 2g, so scaling the height by
## decay^n scales the speed by sqrt(decay^n). Static and pure.
static func wall_jump_velocity_for(n: int, a_jump_velocity: float, decay: float) -> float:
	return a_jump_velocity * sqrt(pow(decay, n))

## The three components, and a fixed launch rather than an aimed one (the user's call):
## vertical is the chain-scaled jump (3 m on the first, see "The bound"), along-wall is
## whatever the run was carrying, and away-from-wall is exactly wall_jump_kick along the
## stored normal - whatever he had into or out of the face is replaced, not added to. Then the
## push protection starts, so the stick cannot erase the kick the next frame. Called from
## _handle_gravity_and_jump(): the buffered press off a live run, or a press in the wall coyote.
func _take_wall_jump() -> void:
	var n := Vector3(_wall_jump_normal.x, 0.0, _wall_jump_normal.z).normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var along := horizontal - n * horizontal.dot(n)
	velocity.x = along.x + n.x * wall_jump_kick
	velocity.z = along.z + n.z * wall_jump_kick
	velocity.y = wall_jump_velocity_for(_wall_jumps_taken, jump_velocity, wall_jump_chain_decay)
	_wall_jumps_taken += 1
	_wall_jump_push_time = jump_air_time
	_wall_jump_steer_back = 0.0
	_wall_coyote_left = 0.0
	# The 180 back onto the wall he just left is a chained hop like any other - see
	# _wall_lockout_normal.
	_wall_lockout_normal = Vector3.ZERO
	_wall_lockout_left = 0.0
	is_jumping = true
	_anime_accent(&"wall_kick")
	# On the wall where his feet last were - a coyote jump is already off it.
	if _effects_on() and _wall_kick_point != Vector3.ZERO:
		_vfx.wall_jump(_wall_kick_point, n)

## The let-go detaches - the timer and the wall ending. Each opens the
## wall coyote off this face; how long it locks the face out depends on `cause` - see
## _wall_lockout_time_for(). Velocity is left alone: they all "fall/launch normally".
func _let_go_of_wall(cause: WallLetGo) -> void:
	if not is_wall_running:
		return
	_wall_jump_normal = _wall_normal
	_wall_coyote_left = wall_jump_coyote_time
	_wall_lockout_left = _wall_lockout_time_for(cause)
	_wall_lockout_normal = _wall_normal if _wall_lockout_left > 0.0 else Vector3.ZERO
	_wall_lockout_point = _wall_point
	_end_wall_run()

## Lockout by cause (see "Staying on the wall" (3)): the timer is until the ground (INF) -
## otherwise the timer means nothing; a wall that ended locks nothing, so the same plane past a
## doorway is a new run. Static and pure.
static func _wall_lockout_time_for(cause: WallLetGo) -> float:
	if cause == WallLetGo.TIMER:
		return INF
	return 0.0

## Counts a timed lockout down, and frees the face when it runs out. INF never counts.
func _tick_wall_lockout(delta: float) -> void:
	if _wall_lockout_left <= 0.0 or is_inf(_wall_lockout_left):
		return
	_wall_lockout_left = maxf(_wall_lockout_left - delta, 0.0)
	if _wall_lockout_left <= 0.0:
		_wall_lockout_normal = Vector3.ZERO

## Clears the run. Never touches velocity: every ending in the spec either wants it untouched
## (the timer, the stick, the wall running out - all "falls/launches normally") or has already
## written what it wants before calling this (the wall-jump's kick, the mantle handoff).
func _end_wall_run() -> void:
	if not is_wall_running:
		return
	is_wall_running = false
	_wall_run_time = 0.0

## The mesh's lean off the wall plane, and the camera roll - the same
## formula, read against two different yaws (the mesh's, the camera pivot's). Not a measured
## alignment like _slope_align_angles(): a FIXED tilt, `roll_deg`, signed toward whichever
## side the wall is actually on.
##
## Rotating `wall_normal` into the given frame the way _slope_align_angles() rotates a floor
## normal, `body.x` is the normal's component along that frame's own left axis. The normal
## points away from the wall into open space, so `body.x > 0` - the normal leaning toward the
## left - puts the wall itself on the right, and the roll should tip that way: negative
## rotation.z, the same sign _slope_align_angles() gives "tips left" for the opposite lean.
static func _wall_run_roll_angles(yaw: float, wall_normal: Vector3, roll_deg: float) -> Vector2:
	if wall_normal.length() <= 0.0001:
		return Vector2.ZERO
	var body := wall_normal.normalized().rotated(Vector3.UP, -yaw)
	if is_equal_approx(body.x, 0.0):
		return Vector2.ZERO
	return Vector2(0.0, -signf(body.x) * deg_to_rad(roll_deg))

## Which side the wall is on, latched at attach.
func wall_run_on_right() -> bool:
	return _wall_run_right

## True when a wall with `wall_normal` is on the right of someone travelling along
## `travel_dir`. Read against the run's tangent rather than the mesh's yaw, because the mesh is
## still turning toward that tangent for the first frames of the run and a near-head-on attach
## could read either side. The normal points away from the wall, so it leaning to his LEFT
## (the mesh's local +X, the same body.x _wall_run_roll_angles() reads) puts the wall on his
## right. Static and pure - see tests/test_pilot9_wall_run.gd.
static func _wall_on_right_of(wall_normal: Vector3, travel_dir: Vector3) -> bool:
	return wall_normal.x * travel_dir.z - wall_normal.z * travel_dir.x > 0.0

## -- the wall climb -----------------------------------------------------------------
##
## Running dead-on into a wall, he goes straight up it: a fixed wall_climb_height, then a stall
## and a peel off, unless a lip (the mantle), a jump (the climb jump) or the wall's top ends it
## first. On the ground or in the air. Velocity-driven like the wall-run, so move_and_slide()
## keeps him honest against the geometry. See docs/specs/pilot9-wall-climb.md.

## The entry gates, as one pure function: a run and not a drift (`min_speed`), the face
## near-vertical (`wall_angle_deg`), travel within `climb_angle_deg` of dead-on into it, and
## not mid-dash. No floor gate - a climb starts on the ground or in the air alike. Static so
## every gate is assertable with no tree - see tests/test_pilot9_wall_climb.gd.
static func _wall_climb_gates(horizontal_speed: float, wall_normal: Vector3, travel_dir: Vector3,
		is_dashing_: bool, min_speed: float, wall_angle_deg: float,
		climb_angle_deg: float) -> bool:
	if is_dashing_ or horizontal_speed < min_speed:
		return false
	if wall_normal.length() <= 0.0001 or travel_dir.length() <= 0.0001:
		return false
	var n := wall_normal.normalized()
	if absf(n.y) > sin(deg_to_rad(wall_angle_deg)):
		return false
	var flat := Vector3(travel_dir.x, 0.0, travel_dir.z)
	if flat.length() <= 0.0001:
		return false
	var theta := rad_to_deg(acos(clampf(flat.normalized().dot(n), -1.0, 1.0)))
	return theta >= 180.0 - climb_angle_deg - 0.0001

## The flat-out climb speed that makes rise + stall come to exactly `height`: the rise is
## speed x rise_time, the linear stall half of speed x stall_time. Static and pure.
static func wall_climb_speed_for(height: float, rise_time: float, stall_time: float) -> float:
	var t := rise_time + stall_time * 0.5
	return height / t if t > 0.0 else 0.0

func wall_climb_speed() -> float:
	return wall_climb_speed_for(wall_climb_height, wall_climb_rise_time, wall_climb_stall_time)

## How much of the flat-out climb speed he has `t` seconds in: all of it through the rise, then
## linearly to nothing across the stall. Static and pure.
static func wall_climb_speed_fraction_at(t: float, rise_time: float, stall_time: float) -> float:
	if t <= rise_time:
		return 1.0
	if stall_time <= 0.0:
		return 0.0
	return clampf(1.0 - (t - rise_time) / stall_time, 0.0, 1.0)

## The clip's rate this frame - pilot9_animation.gd writes it onto the `wall_climb` TimeScale.
func wall_climb_clip_rate() -> float:
	if not is_wall_climbing:
		return wall_climb_anim_speed
	return wall_climb_anim_speed * wall_climb_speed_fraction_at(_wall_climb_time,
		wall_climb_rise_time, wall_climb_stall_time)

## How far the mesh slides in toward the face during a climb, metres: the gap between where the
## capsule holds him and the tipped clip's contact plane, less a palm. Negative pulls the mesh
## back if the hands would reach through the wall. Read from the bake, so a new clip re-fits.
func _wall_climb_hug() -> float:
	if wall_climb_hand_reach <= 0.0:
		return 0.0
	return clampf(_wall_run_hold_distance() - wall_climb_hand_reach - WALL_CLIMB_PALM, -0.3, 0.5)

## The same-wall cooldown, pure: true while `lock_left` is still running and the face (`normal`
## through `point`) is the locked one. Any other face is open the moment the climb ends.
static func _wall_climb_locked(lock_normal: Vector3, lock_point: Vector3, lock_left: float,
		normal: Vector3, point: Vector3) -> bool:
	return lock_left > 0.0 and _same_wall(lock_normal, lock_point, normal, point)

## The instance wrapper: the pure gates plus everything that needs live state - the verbs that
## own him outright, the toggle, the cooldown, and the mantle's claim on a reachable lip.
func _can_start_wall_climb(hit: Dictionary, travel_dir: Vector3) -> bool:
	if hit.is_empty() or not can_wall_climb:
		return false
	if frozen or is_climbing or is_vaulting or is_dashing or is_rail_grinding \
			or is_rail_switching or is_wall_climbing:
		return false
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var point: Vector3 = hit.get("position", Vector3.ZERO)
	if _wall_climb_locked(_wall_climb_lock_normal, _wall_climb_lock_point, _wall_climb_lock_left,
			normal, point):
		return false
	if not _wall_climb_gates(_horizontal_speed(), normal, travel_dir, is_dashing,
			wall_run_min_speed, wall_run_wall_angle, wall_climb_angle):
		return false
	# A lip the mantle can already take is the mantle's - it ran first this frame in the air, and
	# on the ground it takes the lip on his first airborne frame anyway. Only refused airborne:
	# on the ground the mantle cannot fire, and the climb is what lifts him to it.
	if not is_on_floor() and _wall_top_in_mantle_reach(normal):
		return false
	return true

## Entry, sustain and exit - the wall-run's split. Runs ahead of _handle_wall_run() (a head-on
## catch is a climb before it is ever a camera-redirected run) and ahead of
## _handle_gravity_and_jump(), whose gravity it suspends and whose jump press it takes.
func _handle_wall_climb(delta: float) -> void:
	if _wall_climb_lock_left > 0.0:
		_wall_climb_lock_left = maxf(_wall_climb_lock_left - delta, 0.0)
		if _wall_climb_lock_left <= 0.0:
			_wall_climb_lock_normal = Vector3.ZERO

	if is_wall_climbing:
		_wall_climb_time += delta
		if frozen:
			_end_wall_climb()
			return
		if Input.is_action_just_pressed("jump"):
			# Buffered, not taken: gravity runs after this and would eat the launch this frame.
			_wall_climb_jump_normal = _wall_climb_normal
			_wall_climb_jump_buffered = true
			_end_wall_climb()
			return
		if _wall_climb_time >= wall_climb_rise_time + wall_climb_stall_time:
			_peel_off_wall()
			return
		var hit := _probe_wall_climb_face()
		if hit.is_empty():
			# The face ran out above his chest - the top of a wall the mantle would not take, or
			# a gap. He keeps the climb speed he had and finishes it as a jump would.
			_end_wall_climb()
			return
		var normal: Vector3 = hit.get("normal", Vector3.ZERO)
		if not _wall_follows(_wall_climb_normal, normal, wall_run_follow_angle):
			_end_wall_climb()
			return
		_wall_climb_normal = normal.normalized()
		_wall_climb_point = hit["position"]
		_wall_climb_gap = (hit["origin"] - _wall_climb_point).dot(_wall_climb_normal)
		_emit_wall_climb_taps(delta)
		return

	if is_wall_running:
		# The inside corner: a run that meets a wall dead ahead along it climbs that wall. A lip
		# there is the mantle's (row 2 of the wall-run spec's table) and it ran first this frame.
		var ahead_run := _probe_wall_ahead(_wall_run_direction)
		if not ahead_run.is_empty() and _can_start_wall_climb(ahead_run, _wall_run_direction):
			_start_wall_climb(ahead_run["normal"], ahead_run["position"])
		return

	var travel := _wall_run_travel_direction()
	if is_tredging or Vector3(velocity.x, 0.0, velocity.z).length() <= 0.0001:
		return
	var ahead := _probe_wall_ahead(travel)
	if _can_start_wall_climb(ahead, travel):
		_start_wall_climb(ahead["normal"], ahead["position"])

## The sustain ray: straight at the face along -normal, from chest height, the wall-run's reach.
func _probe_wall_climb_face() -> Dictionary:
	var into := -Vector3(_wall_climb_normal.x, 0.0, _wall_climb_normal.z)
	if into.length() <= 0.0001:
		return {}
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var origin := global_position + Vector3.UP * WALL_RUN_PROBE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(origin,
		origin + into.normalized() * wall_run_probe_reach)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		hit["origin"] = origin
	return hit

## The entry snap: face the wall, drop every horizontal bit of speed, take the climb speed
## upward. A fall is caught outright, a rising jump replaced - he climbs exactly
## wall_climb_height whatever he arrived with.
func _start_wall_climb(normal: Vector3, point: Vector3) -> void:
	# The inside-corner handoff ends a run; nothing about the run survives into the climb.
	_end_wall_run()
	is_wall_climbing = true
	_wall_climb_time = 0.0
	_wall_climb_phase = 0.0
	_wall_climb_normal = Vector3(normal.x, 0.0, normal.z).normalized()
	_wall_climb_point = point
	_wall_climb_gap = (global_position + Vector3.UP * WALL_RUN_PROBE_HEIGHT - point) \
		.dot(_wall_climb_normal)
	_wall_climb_jump_buffered = false
	_wall_climb_coyote_left = 0.0
	velocity = Vector3.UP * wall_climb_speed()
	# Every per-flight grace that would fire out of the middle of a climb goes - the wall-run
	# entry's list. The double jump and the wall-jump chain are left alone (the spec's call).
	_wall_jump_push_time = 0.0
	_wall_jump_steer_back = 0.0
	_wall_coyote_left = 0.0
	_coyote_left = 0.0
	_jump_buffered = 0.0
	_rail_coyote_left = 0.0
	_rail_launch_carry = false
	_rail_land_ease_elapsed = -1.0
	is_crouching = false
	_slide_buffered = false
	_end_slide()
	var into := -_wall_climb_normal
	character.rotation.y = atan2(into.x, into.z)
	# The tilt and the slide in, snapped rather than eased: _align_model_to_slope() would take
	# ~0.3 s to get there, and the reaching hands pass through the face for all of it.
	character.rotation.x = -deg_to_rad(wall_climb_lean)
	character.rotation.z = 0.0
	if is_inside_tree():
		character.position = global_basis.inverse() * (-_wall_climb_normal * _wall_climb_hug())
	if is_inside_tree():
		_wall_kick_point = global_position - _wall_climb_normal * _wall_climb_gap
		if _effects_on():
			_vfx.wall_attach(_wall_kick_point, _wall_climb_normal)

## Clears the climb and starts the same-wall cooldown on the face he was on. Never touches
## velocity: the jump has already written its own, the peel writes its push, and the wall
## ending keeps the climb speed he had.
func _end_wall_climb() -> void:
	if not is_wall_climbing:
		return
	is_wall_climbing = false
	_wall_climb_time = 0.0
	_wall_climb_lock_normal = _wall_climb_normal
	_wall_climb_lock_point = _wall_climb_point
	_wall_climb_lock_left = wall_climb_same_wall_cooldown

## The clock ran out: a small push off the face, the fall, and a beat in which jump is still
## the climb jump.
func _peel_off_wall() -> void:
	var n := _wall_climb_normal
	velocity = Vector3(n.x * wall_climb_peel_speed, 0.0, n.z * wall_climb_peel_speed)
	_wall_climb_jump_normal = n
	_wall_climb_coyote_left = wall_jump_coyote_time
	_end_wall_climb()

## Bypasses _apply_movement() while he climbs, as the wall-run's does. Up at the climb speed
## (eased out through the stall), held to the face by the wall-run's pull, nothing along it.
func _apply_wall_climb_velocity(_delta: float) -> void:
	var pull := _wall_run_pull_speed(_wall_climb_gap, _wall_run_hold_distance(),
		wall_run_pull_time)
	var n := _wall_climb_normal
	velocity.x = -n.x * pull
	velocity.z = -n.z * pull
	velocity.y = wall_climb_speed() * wall_climb_speed_fraction_at(_wall_climb_time,
		wall_climb_rise_time, wall_climb_stall_time)

## The climb jump: straight back off the face at wall_jump_kick and a full jump up, every time -
## outside the wall-run's decaying chain. He turns to face away, and the wall-jump's push
## protection carries the kick across a chimney. Called from _handle_gravity_and_jump().
func _take_wall_climb_jump() -> void:
	var n := Vector3(_wall_climb_jump_normal.x, 0.0, _wall_climb_jump_normal.z).normalized()
	velocity = Vector3(n.x * wall_jump_kick, jump_velocity, n.z * wall_jump_kick)
	# The push protection reads the wall-jump's normal.
	_wall_jump_normal = n
	_wall_jump_push_time = jump_air_time
	_wall_jump_steer_back = 0.0
	_wall_climb_coyote_left = 0.0
	is_jumping = true
	character.rotation.y = atan2(n.x, n.z)
	_anime_accent(&"wall_kick")
	if _effects_on() and _wall_kick_point != Vector3.ZERO:
		_vfx.wall_jump(_wall_kick_point, n)

## One tap at the hand that just took a hold, on the face. The loop's clock is advanced here at
## the clip's own rate, so a grab phase crossed this frame is a grab the mesh is making now.
func _emit_wall_climb_taps(delta: float) -> void:
	if wall_climb_duration <= 0.0 or wall_climb_grab_phases.is_empty():
		return
	var from := _wall_climb_phase
	_wall_climb_phase += delta * wall_climb_clip_rate() / wall_climb_duration
	if not _effects_on():
		return
	for p in wall_climb_grab_phases:
		# Crossed this frame, on this loop or the wrap into the next.
		var crossed := (p > fposmod(from, 1.0) and p <= fposmod(from, 1.0) + (_wall_climb_phase - from)) \
			or (p + 1.0 > fposmod(from, 1.0) and p + 1.0 <= fposmod(from, 1.0) + (_wall_climb_phase - from))
		if crossed:
			_vfx.hand_taps([_wall_climb_hand_on_face()])

## The higher of his two hands - the one topping out - pushed onto the face.
func _wall_climb_hand_on_face() -> Vector3:
	var skel := get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	var hand := global_position + Vector3.UP * 2.0
	if skel != null:
		var best := -INF
		for bone in [&"LeftHand", &"RightHand"]:
			var idx := skel.find_bone(bone)
			if idx < 0:
				continue
			var p := skel.global_transform * skel.get_bone_global_pose(idx).origin
			if p.y > best:
				best = p.y
				hand = p
	var n := _wall_climb_normal
	return hand - n * (hand - _wall_climb_point).dot(n)

## -- the rail grind ---------------------------------------------------------------
##
## Falling onto a rail catches him; he rides it at a fixed gear until he jumps, dashes,
## crouches or runs off the end. See docs/specs/pilot9-rail-grind.md. Three rules shape
## everything below:
##
## 1. Air only, and automatic - three gates in _rail_catch_gates() are the whole attach.
## 2. The ride stores an OFFSET along the curve and asks the rail for a world point every
##    frame, through its current transform (scripts/rail.gd). A moving rail carries him.
## 3. The rail is ground for the refills and nothing else - he is never is_on_floor() on one.

## The three attach gates, pure: his feet within `radius` of the centreline's closest point,
## not UNDER it along the rail's `up` (rising through from underneath does not catch), and not
## the rail he left inside the lockout. `dist` is passed rather than recomputed so the caller's
## one distance is the one tested. Static - see tests/test_pilot9_rail_grind.gd.
##
## "Under" is the 90 degree cone straight below the centreline: feet more below it than off to
## its side. Anything else below the centreline is a side approach and catches - without that,
## coming at a rail from the side with his feet level with it or lower missed, and with no
## collision on the tube he passed straight through it (2026-09-24, from play).
static func _rail_catch_gates(feet: Vector3, closest: Vector3, up: Vector3, dist: float,
		radius: float, locked: bool) -> bool:
	if locked or dist > radius:
		return false
	var rel := feet - closest
	var height := rel.dot(up)
	if height > 0.0:
		return true
	return (rel - up * height).length() > -height

## The points his feet passed through since last frame's catch test: `from` to `to` in steps of
## at most RAIL_SWEEP_STEP, `from` itself left out (last frame tested it) and `to` last. Without
## it the gates see one point a frame, and a fall faster than the catch zone is deep steps from
## above it to below the centreline with no frame inside - he drops through the rail. Just `to`
## when there is no last frame to sweep from (`valid` false) or the gap is a teleport
## (RAIL_SWEEP_MAX). Static and pure.
static func _rail_sweep_points(from: Vector3, to: Vector3, valid: bool) -> PackedVector3Array:
	var length := from.distance_to(to)
	if not valid or length > RAIL_SWEEP_MAX or length <= RAIL_SWEEP_STEP:
		return PackedVector3Array([to])
	var steps := ceili(length / RAIL_SWEEP_STEP)
	var points := PackedVector3Array()
	for i in range(1, steps + 1):
		points.append(from.lerp(to, float(i) / float(steps)))
	return points

## +1 to ride toward increasing offset, -1 toward decreasing: whichever way along `tangent`
## his horizontal momentum already carries him. Measured ALONG the rail, not overall - coming
## at it side-on he may be fast but carrying almost nothing either way, and then the sign of
## that almost-nothing is a coin toss. Under RAIL_DIR_MIN_SPEED along it, `facing` decides,
## then `look` (the camera) if he faces square across it too. A dead tie rides forward.
## Static and pure.
static func _rail_ride_dir(tangent: Vector3, h_velocity: Vector3, facing: Vector3,
		look: Vector3 = Vector3.ZERO) -> int:
	var t := Vector3(tangent.x, 0.0, tangent.z)
	if t.length() <= 0.0001:
		t = tangent  # a vertical rail: nothing flat to compare, use it as it is
	t = t.normalized()
	var along := Vector3(h_velocity.x, 0.0, h_velocity.z).dot(t)
	if absf(along) > RAIL_DIR_MIN_SPEED:
		return -1 if along < 0.0 else 1
	for v: Vector3 in [facing, look]:
		var flat := Vector3(v.x, 0.0, v.z)
		if flat.length() <= 0.0001:
			continue
		var d := flat.normalized().dot(t)
		if absf(d) > RAIL_DIR_MIN_ALIGN:
			return -1 if d < 0.0 else 1
	return -1 if along < 0.0 else 1

## The launch heading off a rail, shared by the jump and the dash: the ride `tangent`,
## flattened, bent toward the `stick` by at most `max_bend_deg`. Neutral stick is the tangent.
## Always unit length and horizontal, so the speed - and the grid distance - never changes;
## only where he lands moves. Static and pure.
static func _rail_jump_heading(tangent: Vector3, stick: Vector3, max_bend_deg: float) -> Vector3:
	var t := Vector3(tangent.x, 0.0, tangent.z)
	if t.length() <= 0.0001:
		t = Vector3(stick.x, 0.0, stick.z)
		return t.normalized() if t.length() > 0.0001 else Vector3.ZERO
	t = t.normalized()
	var s := Vector3(stick.x, 0.0, stick.z)
	if s.length() <= 0.0001:
		return t
	var bend := t.signed_angle_to(s.normalized(), Vector3.UP)
	var limit := deg_to_rad(max_bend_deg)
	return t.rotated(Vector3.UP, clampf(bend, -limit, limit)).normalized()

## The ride speed `t` seconds into an ease from `from` to `to` over `ease_time`: linear, up
## or down, flat at `to` after. Static and pure - the wall-run's _wall_run_speed_at() without
## its hold-a-faster-entry rule, because a rail's gears are fixed both ways.
static func _rail_speed_at(from: float, to: float, ease_time: float, t: float) -> float:
	if ease_time <= 0.0:
		return to
	return lerpf(from, to, clampf(t / ease_time, 0.0, 1.0))

## `offset` moved by `step` along a curve of `length`: wrapped on a `closed` one, left
## unclamped on an open one so the caller can see it ran off. Static and pure.
static func _rail_offset_advanced(offset: float, step: float, length: float,
		closed: bool) -> float:
	var next := offset + step
	if closed and length > 0.0:
		return fposmod(next, length)
	return next

## True when `offset` has run off an open curve. A closed one never ends. Static and pure.
static func _rail_offset_ended(offset: float, length: float, closed: bool) -> bool:
	return not closed and (offset < 0.0 or offset > length)

## The mesh roll into a rail's bend, radians for `character.rotation.z`: the heading change from
## `behind` to `ahead` (ride tangents `span` metres apart, flattened), as degrees per metre, over
## `full_turn_deg` - clamped to 1 - times `max_deg`. A left bend is a positive signed angle about
## UP and leans his head left, which is negative rotation.z (see _slope_align_angles()). Static
## and pure - see tests/test_pilot9_rail_grind.gd.
static func _rail_lean_roll(behind: Vector3, ahead: Vector3, span: float, max_deg: float,
		full_turn_deg: float) -> float:
	var b := Vector3(behind.x, 0.0, behind.z)
	var a := Vector3(ahead.x, 0.0, ahead.z)
	if b.length() <= 0.0001 or a.length() <= 0.0001 or span <= 0.0 or full_turn_deg <= 0.0:
		return 0.0
	var rate := rad_to_deg(b.normalized().signed_angle_to(a.normalized(), Vector3.UP)) / span
	return -clampf(rate / full_turn_deg, -1.0, 1.0) * deg_to_rad(max_deg)

## This frame's lean, read off the ride tangent RAIL_LEAN_SAMPLE either side of him.
func _rail_lean_target() -> float:
	if not is_rail_grinding or not is_instance_valid(_rail):
		return 0.0
	var length: float = _rail.ride_length()
	var d := RAIL_LEAN_SAMPLE * float(_rail_dir)
	var back := _rail_offset - d
	var fore := _rail_offset + d
	if _rail.is_loop() and length > 0.0:
		back = fposmod(back, length)
		fore = fposmod(fore, length)
	var dir := float(_rail_dir)
	return _rail_lean_roll(_rail.tangent_at(back) * dir, _rail.tangent_at(fore) * dir,
		RAIL_LEAN_SAMPLE * 2.0, rail_lean_max, rail_lean_full_turn)

## The gear's speed for `sprinting`.
func _rail_gear_speed(sprinting: bool) -> float:
	return rail_sprint_speed if sprinting else rail_grind_speed

## The world direction he is riding, including the rail's slope. Zero off a rail.
func _rail_ride_tangent() -> Vector3:
	if not is_rail_grinding or not is_instance_valid(_rail):
		return Vector3.ZERO
	return _rail.tangent_at(_rail_offset) * float(_rail_dir)

## His along-rail velocity, slope and all - what crouch lets go with.
func _rail_ride_velocity() -> Vector3:
	return _rail_ride_tangent() * _rail_speed

## Every airborne frame: the catch test, or - riding - the gear, the ease, the advance along
## the curve, and the end. Placement and velocity are _apply_rail_velocity()'s, in the movement
## tail; the jump is _handle_gravity_and_jump()'s, the dash _handle_dash()'s and crouch
## _handle_crouch_and_slide()'s, each reading the press where that verb already reads it.
func _handle_rail_grind(delta: float) -> void:
	_rail_lockout_left = maxf(_rail_lockout_left - delta, 0.0)

	if is_rail_grinding:
		# Only a frame that runs the catch at the bottom re-arms the sweep; every other way out
		# of this function breaks it, so a catch never sweeps across a ride, a dash or a landing.
		_rail_sweep_valid = false
		# A freeze is not a moment he is still riding through, and a rail freed out from under
		# him (a map unloading a boss) cannot be asked for a point. Either lets go in place.
		if frozen or not is_instance_valid(_rail) or not _rail.is_inside_tree():
			_end_rail_grind(RailExit.LOST)
			return
		var sprinting := sprint_toggled
		if sprinting != is_rail_sprinting:
			is_rail_sprinting = sprinting
			_rail_speed_from = _rail_speed
			_rail_speed_to = _rail_gear_speed(sprinting)
			_rail_ease_time = 0.0
		_rail_ease_time += delta
		_rail_speed = _rail_speed_at(_rail_speed_from, _rail_speed_to, rail_speed_ease_time,
			_rail_ease_time)
		_rail_snap_left = maxf(_rail_snap_left - delta, 0.0)

		var length: float = _rail.ride_length()
		var closed: bool = _rail.is_loop()
		var next := _rail_offset_advanced(_rail_offset, float(_rail_dir) * _rail_speed * delta,
			length, closed)
		if _rail_offset_ended(next, length, closed):
			# Off the end: carry on along the end tangent at ride speed, slope included - an end
			# that tilts up kicks him up a little. Gravity from here. The jump a beat late still
			# gets the full rail launch - see the rail coyote in _handle_gravity_and_jump().
			var end_tangent: Vector3 = _rail.tangent_at(clampf(next, 0.0, length)) \
				* float(_rail_dir)
			velocity = end_tangent * _rail_speed
			_rail_coyote_tangent = end_tangent
			_rail_coyote_speed = _rail_speed
			_start_rail_launch_carry()
			_end_rail_grind(RailExit.END)
			return
		_rail_offset = next
		return

	# The switch is committed: nothing else catches him mid-hop, and it lands itself.
	if is_rail_switching:
		_rail_sweep_valid = false
		_tick_rail_switch(delta)
		return
	if not can_rail_grind or frozen or is_climbing or is_vaulting or is_dashing or is_on_floor() \
			or is_wall_climbing or is_tredging:
		_rail_sweep_valid = false
		return
	if not _try_catch_rail():
		_rail_sweep_from = global_position
		_rail_sweep_valid = true

## The catch: every point of this frame's sweep (_rail_sweep_points()) against every rail in the
## group. The rail passed earliest along the path wins - he meets it first - and among rails
## first met at the same point, the nearest. A catch found back along the path puts his feet
## there before the snap, so the snap never pulls him up from under the tube. Returns whether
## he caught one.
func _try_catch_rail() -> bool:
	var path := _rail_sweep_points(_rail_sweep_from, global_position, _rail_sweep_valid)
	var h_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var look := -Vector3(sin(camera_pivot.rotation.y), 0.0, cos(camera_pivot.rotation.y))
	var facing := _facing() if camera_mode == CameraMode.THIRD_PERSON else look
	var best = null
	var best_offset := 0.0
	var best_dir := 1
	var best_dist := INF
	var best_step := path.size()
	# Untyped on purpose - the rails are duck-typed, see `_rail`.
	var rails: Array = get_tree().get_nodes_in_group(RAIL_GROUP)
	for rail in rails:
		if not rail.has_method("closest_offset") or not rail.is_inside_tree():
			continue
		var length: float = rail.ride_length()
		if length <= 0.0:
			continue
		var locked: bool = rail == _rail_last and _rail_lockout_left > 0.0
		# Past best_step another rail was already met sooner; this one cannot win from there.
		for step in mini(best_step + 1, path.size()):
			var feet := path[step]
			var offset: float = rail.closest_offset(feet)
			var closest: Vector3 = rail.point_at(offset)
			var dist := feet.distance_to(closest)
			if not _rail_catch_gates(feet, closest, rail.up(), dist, rail_catch_radius, locked):
				continue
			var tangent: Vector3 = rail.tangent_at(offset)
			var dir := _rail_ride_dir(tangent, h_velocity, facing, look)
			# Not added by the spec: a catch at the very tip of an open rail that would ride
			# straight off it is refused, or brushing the end of one on the way past is a free
			# refill. Unless his momentum along the rail is what points off it, the tip is a
			# side approach whose direction was a tiebreak - that one rides back along the rail.
			var at_tip := func(d: int) -> bool:
				return not rail.is_loop() and ((d > 0 and offset >= length - RAIL_END_MARGIN)
					or (d < 0 and offset <= RAIL_END_MARGIN))
			if at_tip.call(dir):
				if absf(h_velocity.dot(tangent)) > RAIL_DIR_MIN_SPEED or at_tip.call(-dir):
					continue
				dir = -dir
			if step < best_step or dist < best_dist:
				best = rail
				best_offset = offset
				best_dir = dir
				best_dist = dist
				best_step = step
			break
	if best == null:
		return false
	global_position = path[best_step]
	_start_rail_grind(best, best_offset, best_dir)
	return true

## The catch lands. Does what a landing does - refills the double jump, the dash's air charge
## and the wall-jump chain - latches the direction, and starts the ease and the snap. Every
## other verb's per-flight leftovers go, the way the ground clears them. `switched` is a rail
## switch landing, which throws the smaller spark burst instead of the catch's.
func _start_rail_grind(rail, offset: float, dir: int, switched: bool = false) -> void:
	is_rail_grinding = true
	_rail = rail
	_rail_offset = offset
	_rail_dir = -1 if dir < 0 else 1
	var tangent: Vector3 = rail.tangent_at(offset)
	# Entry speed is the along-rail part of what he arrived with, eased to the gear from there.
	# The gear is the ground sprint toggle: caught sprinting, he rail-sprints; otherwise he grinds.
	is_rail_sprinting = sprint_toggled
	_rail_speed = absf(Vector3(velocity.x, 0.0, velocity.z).dot(tangent))
	_rail_speed_from = _rail_speed
	_rail_speed_to = _rail_gear_speed(is_rail_sprinting)
	_rail_ease_time = 0.0
	_rail_snap_left = rail_snap_time
	_rail_snap_offset = global_position - rail.top_at(offset)
	# The rail counts as ground.
	_air_jumps_left = air_jumps
	_dash_air_charge = true
	_wall_jumps_taken = 0
	_wall_jump_push_time = 0.0
	_wall_jump_steer_back = 0.0
	_wall_coyote_left = 0.0
	_wall_lockout_normal = Vector3.ZERO
	_coyote_left = 0.0
	_jump_buffered = 0.0
	_rail_coyote_left = 0.0
	_rail_launch_carry = false
	_rail_land_ease_elapsed = -1.0
	is_jumping = false
	is_crouching = false
	_slide_buffered = false
	_end_slide()
	_end_wall_run()
	velocity = Vector3.ZERO
	# A switch is a hop between rails, not a landing; it gets the soft hold.
	_anime_accent(&"rail_land", 0.0 if switched else 1.0, func() -> bool: return is_rail_grinding)
	if _effects_on():
		_vfx.rail_contact(global_position, -tangent * float(_rail_dir), not switched)

## Ends the ride. Every exit starts the same-rail lockout; the caller has already written
## whatever velocity the exit leaves with (the jump's, the end tangent's, crouch's along-rail
## drop) or wants it untouched. The rail coyote is opened here only for END.
func _end_rail_grind(reason: RailExit) -> void:
	if not is_rail_grinding:
		return
	is_rail_grinding = false
	is_rail_sprinting = false
	_rail_last = _rail
	_rail_lockout_left = rail_relatch_lockout
	_rail_coyote_left = rail_coyote_time if reason == RailExit.END else 0.0
	_rail_snap_left = 0.0
	_rail = null

## An ordinary jump off a rail - 3 m, 1.2 s - that keeps the ride's speed: `launch` is the
## ride velocity (or the end tangent's, for the rail coyote). He leaves along the stick if it is
## pushed, along the rail if not, at the ride's full speed. The carry lets the stick drive that
## speed anywhere until he lands, and the landing eases it out - see "Rail jump keeps its speed
## until the ground" in the spec. The double jump is still his: the rail refilled it.
func _take_rail_jump(launch: Vector3) -> void:
	var flat := Vector3(launch.x, 0.0, launch.z)
	var heading := direction if direction else flat.normalized()
	var along := heading * launch.length()
	velocity.x = along.x
	velocity.z = along.z
	velocity.y = jump_velocity
	is_jumping = true
	_rail_coyote_left = 0.0
	_start_rail_launch_carry()
	_rail_launch_speed = launch.length()

## Arms the rail carry at his current flat speed - the ride's, since every caller has just
## handed him the ride velocity. See _rail_launch_carry.
func _start_rail_launch_carry() -> void:
	_rail_launch_carry = true
	_rail_launch_speed = _horizontal_speed()

## Places him on the curve for this frame: the tube top at the (already advanced) offset,
## through the rail's current transform, plus whatever is left of the entry snap - as a
## velocity, so move_and_slide() carries him there and a moving rail's own motion rides along.
func _apply_rail_velocity(delta: float) -> void:
	if delta <= 0.0 or not is_instance_valid(_rail):
		return
	var target: Vector3 = _rail.top_at(_rail_offset)
	if _rail_snap_left > 0.0 and rail_snap_time > 0.0:
		target += _rail_snap_offset * (_rail_snap_left / rail_snap_time)
	velocity = (target - global_position) / delta

## -- the rail switch ---------------------------------------------------------------
##
## A rail jump with the stick aimed at another rail hops onto it. Scripted, not ballistic: the
## gravity curve's apex scale, air control and a target that may be moving would all have to be
## predicted by a computed launch. Instead the flight asks the target rail where its landing
## point is NOW, every frame, and is there at rail_switch_time. See "Rail to rail" in
## docs/specs/pilot9-rail-grind.md.

## Which side the stick aims a switch: +1 right of the ride, -1 left, 0 not a switch (neutral,
## or less than `min_angle_deg` off the tangent). Static and pure.
static func _rail_switch_side(tangent: Vector3, stick: Vector3, min_angle_deg: float) -> int:
	var t := Vector3(tangent.x, 0.0, tangent.z)
	var s := Vector3(stick.x, 0.0, stick.z)
	if t.length() <= 0.0001 or s.length() <= 0.0001:
		return 0
	var right := t.normalized().cross(Vector3.UP)
	var side := s.normalized().dot(right)
	if absf(side) < sin(deg_to_rad(min_angle_deg)) - 0.0001:
		return 0
	return 1 if side > 0.0 else -1

## Whether `target` (a rail's point nearest `ahead`) is a switch target from `feet`: to `side`
## of the ride line by at least RAIL_SWITCH_MIN_SIDE, within `reach` of `ahead` flat, and no more
## than `max_rise` above or `max_drop` below his feet. Static and pure.
static func _rail_switch_target_ok(feet: Vector3, ahead: Vector3, target: Vector3,
		tangent: Vector3, side: int, reach: float, max_rise: float, max_drop: float) -> bool:
	var right := Vector3(tangent.x, 0.0, tangent.z).normalized().cross(Vector3.UP)
	var off := Vector3(target.x - ahead.x, 0.0, target.z - ahead.z)
	if off.dot(right) * float(side) < RAIL_SWITCH_MIN_SIDE:
		return false
	if off.length() > reach:
		return false
	var dy := target.y - feet.y
	return dy <= max_rise and dy >= -max_drop

## The hop at `u` (0..1): straight from `from` to `to`, plus a bump peaking at mid-flight of
## `arc_height` plus half the height difference, so it clears the higher end. Static and pure.
static func _rail_switch_arc(from: Vector3, to: Vector3, u: float, arc_height: float) -> Vector3:
	var bump := arc_height + absf(to.y - from.y) * 0.5
	return from.lerp(to, u) + Vector3.UP * (4.0 * bump * u * (1.0 - u))

## The switch, if the stick aims one: finds the nearest qualifying rail and starts the hop.
## Called in place of the ordinary rail jump; false leaves that jump to be taken.
func _try_rail_switch() -> bool:
	if not can_rail_switch or not is_rail_grinding or not is_instance_valid(_rail):
		return false
	var tangent := _rail_ride_tangent()
	var stick := _travel_direction(Input.get_vector("left", "right", "forward", "backward"))
	var side := _rail_switch_side(tangent, stick, rail_switch_min_angle)
	if side == 0:
		return false
	var feet := global_position
	var flat := Vector3(tangent.x, 0.0, tangent.z).normalized()
	var ahead := feet + flat * _rail_speed * rail_switch_time
	var best = null
	var best_offset := 0.0
	var best_dir := 1
	var best_dist := INF
	# Untyped on purpose - the rails are duck-typed, see `_rail`.
	for rail in get_tree().get_nodes_in_group(RAIL_GROUP):
		if rail == _rail or not rail.has_method("closest_offset") or not rail.is_inside_tree():
			continue
		var length: float = rail.ride_length()
		if length <= 0.0:
			continue
		var offset: float = rail.closest_offset(ahead)
		var target: Vector3 = rail.top_at(offset)
		if not _rail_switch_target_ok(feet, ahead, target, tangent, side, rail_switch_reach,
				rail_switch_max_rise, rail_switch_max_drop):
			continue
		var dir := _rail_ride_dir(rail.tangent_at(offset), flat, flat)
		# The catch's own rule: never land on a tip he would ride straight off.
		if not rail.is_loop() and ((dir > 0 and offset >= length - RAIL_END_MARGIN)
				or (dir < 0 and offset <= RAIL_END_MARGIN)):
			continue
		var dist := Vector3(target.x - ahead.x, 0.0, target.z - ahead.z).length()
		if dist < best_dist:
			best = rail
			best_offset = offset
			best_dir = dir
			best_dist = dist
	if best == null:
		return false
	_switch_speed = _rail_speed
	_switch_facing = flat
	_end_rail_grind(RailExit.JUMP)
	is_rail_switching = true
	_switch_rail = best
	_switch_offset = best_offset
	_switch_dir = best_dir
	_switch_start = feet
	_switch_elapsed = 0.0
	is_jumping = true
	return true

## Every switching frame, ahead of the catch: lands him when the hop is done, or drops him into
## ordinary air if the flight cannot go on. Landing is an ordinary catch on the target, then the
## speed he left with put back - he does not ease up again from a sideways arrival.
func _tick_rail_switch(delta: float) -> void:
	if frozen or not is_instance_valid(_switch_rail) or not _switch_rail.is_inside_tree():
		_end_rail_switch()
		return
	_switch_elapsed += delta
	if _switch_elapsed < rail_switch_time:
		return
	var rail = _switch_rail
	_end_rail_switch()
	global_position = rail.top_at(_switch_offset)
	_start_rail_grind(rail, _switch_offset, _switch_dir, true)
	_rail_snap_left = 0.0
	# The gear is whatever the sprint toggle says now (_start_rail_grind() read it); the speed is the one
	# he left with, eased to that gear from there.
	_rail_speed = _switch_speed
	_rail_speed_from = _switch_speed

## Leaves the flight with whatever velocity it last had - the landing overwrites it, and every
## other way out (freeze, boarding, the target gone) drops him into ordinary air.
func _end_rail_switch() -> void:
	is_rail_switching = false
	_switch_rail = null

## The flight as a velocity, like _apply_rail_velocity(): the arc's next point, with its end
## asked of the target rail through its current transform, minus where he is, over `delta`.
func _apply_rail_switch_velocity(delta: float) -> void:
	if delta <= 0.0 or not is_instance_valid(_switch_rail):
		return
	var end: Vector3 = _switch_rail.top_at(_switch_offset)
	# _tick_rail_switch() has already counted this frame into _switch_elapsed.
	var u := clampf(_switch_elapsed / rail_switch_time, 0.0, 1.0)
	var next := _rail_switch_arc(_switch_start, end, u, rail_switch_arc_height)
	velocity = (next - global_position) / delta
	is_jumping = velocity.y > 0.0

## -- the movement effects -------------------------------------------------------
##
## Classic particles, not ink - see docs/specs/pilot9-movement-vfx.md. What they look like is
## scripts/pilot9_vfx.gd's; this section only says when.

## Built in code so a rebuild of pilot9.tscn cannot lose it.
func _setup_vfx() -> void:
	_vfx = Pilot9Vfx.new()
	_vfx.name = "MovementVfx"
	_vfx.pilot = self
	add_child(_vfx)

## MOVEMENT EFFECTS, and the node to draw them with. Every spawn asks this at the moment.
func _effects_on() -> bool:
	return _vfx != null and Settings.movement_effects

## End of the frame a landing was resolved on - after _handle_crouch_and_slide(), so a slide
## the landing started (buffered or auto) is already is_sliding and the dust can trail it.
func _emit_landing_dust() -> void:
	var strength := _land_dust_pending
	_land_dust_pending = 0.0
	if strength <= 0.0 or not _effects_on() or is_rail_grinding:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var skew := Vector3.ZERO
	if is_sliding and flat.length() > 0.01:
		skew = -flat.normalized() * vfx_land_slide_skew
	_vfx.land(global_position, strength, _facing(), skew)

## Every physics frame: the stream and its light follow the ride, and stop with it.
func _update_grind_vfx() -> void:
	if _vfx == null:
		return
	var active := is_rail_grinding and Settings.movement_effects
	var backward := -_rail_ride_tangent()
	_vfx.grind(active, global_position, backward,
		_rail_gear_weight(_rail_speed, rail_grind_speed, rail_sprint_speed))

## The landing dip's speed curve, normalised: 0 up to `min_speed`, 0.5 at a full jump's landing
## speed, 1 at `max_speed`, clamped. The dip's own anchors, so the dust and the camera agree.
static func _landing_dust_strength(fall_speed: float, min_speed: float, jump_speed: float,
		max_speed: float) -> float:
	return _landing_dip_depth(fall_speed, min_speed, jump_speed, 0.5, max_speed, 1.0)

## 0 at the grind gear's speed, 1 at the sprint gear's, clamped - a ramp through the gear ease.
static func _rail_gear_weight(rail_speed: float, grind: float, sprint: float) -> float:
	if sprint <= grind:
		return 1.0
	return clampf((rail_speed - grind) / (sprint - grind), 0.0, 1.0)

## Every physics frame, after the grind: pass 2's streams (lasers, slide sparks, wall dust) and
## the sprint kick and skid. See "Pass 2" in docs/specs/pilot9-movement-vfx.md.
func _update_movement_vfx(delta: float) -> void:
	if _vfx == null:
		return
	var on := Settings.movement_effects
	_vfx_clock += delta
	_kick_cooldown_left = maxf(_kick_cooldown_left - delta, 0.0)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var flat_speed := flat.length()
	var fwd := flat / flat_speed if flat_speed > 0.01 else _facing()

	# The lasers. The latch runs whatever the switch says, so turning effects back on mid-run
	# picks up the right state; the dash only stops new bolts.
	_laser_on = _laser_latch(_laser_on, flat_speed, vfx_laser_on_speed, vfx_laser_off_speed)
	var firing := on and _laser_on and not is_dashing
	_laser_ease = minf(_laser_ease + delta / maxf(vfx_laser_fade_in, 0.001), 1.0) \
		if firing else 0.0
	var aim := flat + Vector3.UP * velocity.y * LASER_VERTICAL
	_vfx.lasers(firing, global_position + Vector3.UP * vfx_laser_chest_height,
		-aim.normalized() if aim.length() > 0.01 else -fwd,
		_speed_ramp(flat_speed, vfx_laser_on_speed, vfx_laser_full_speed), _laser_ease, velocity,
		camera_3d.global_position if camera_3d != null else Vector3.INF, delta)

	# The slide sparks, off the leading foot.
	var sparking := on and is_sliding and flat_speed >= vfx_slide_spark_min_speed
	_vfx.slide(sparking, global_position + fwd * SLIDE_SPARK_LEAD, -fwd,
		_speed_ramp(flat_speed, vfx_slide_spark_min_speed, slide_max_speed))

	# The wall trail - the run's, or the scuffs off his feet up a climb.
	if is_wall_running:
		_wall_kick_point = _wall_foot_contact()
		_vfx.wall_run(on, _wall_kick_point, _wall_normal,
			_wall_dust_fade(_wall_run_time, wall_run_flat_time, wall_run_droop_time))
	elif is_wall_climbing:
		_wall_kick_point = global_position - _wall_climb_normal * _wall_climb_gap
		_vfx.wall_run(on, _wall_kick_point, _wall_climb_normal,
			wall_climb_speed_fraction_at(_wall_climb_time, wall_climb_rise_time,
				wall_climb_stall_time))
	else:
		_vfx.wall_run(false, _wall_kick_point, _wall_normal, 0.0)

	_update_sprint_kicks(on, flat_speed, fwd)

## The sprint kick and the hard-turn skid - floor only, one cooldown between them.
func _update_sprint_kicks(on: bool, run_speed: float, fwd: Vector3) -> void:
	# A freeze forces is_sprinting off; reading that as a stop would kick on every unpause.
	if frozen:
		return
	var sprint_moving := is_sprinting or is_sliding
	var grounded := is_on_floor() and not is_sliding and not is_rail_grinding
	var started := _sprint_started(grounded, sprint_moving, _was_sprint_moving)
	_was_sprint_moving = sprint_moving

	if not grounded:
		_turn_history.clear()
		return
	var fast := run_speed >= sprint_speed * vfx_skid_min_speed_fraction
	var was_dir := Vector3.ZERO
	if fast:
		was_dir = _hard_turn_from(_turn_history, fwd, _vfx_clock, vfx_skid_window, vfx_skid_angle)
		_turn_history.append([_vfx_clock, fwd])
	# Pruned after the check, so a sample exactly one window old still counts.
	while not _turn_history.is_empty() and _vfx_clock - _turn_history[0][0] > vfx_skid_window:
		_turn_history.pop_front()

	if not on or _kick_cooldown_left > 0.0:
		return
	if was_dir != Vector3.ZERO:
		_vfx.skid(global_position, was_dir)
		_kick_cooldown_left = vfx_kick_cooldown
		_turn_history.clear()
	elif started:
		_vfx.sprint_kick(global_position, -fwd)
		_kick_cooldown_left = vfx_kick_cooldown

## Where his feet meet the wall: his origin pushed onto the face along its normal.
func _wall_foot_contact() -> Vector3:
	var n := _wall_normal
	if _wall_point == Vector3.ZERO:
		return global_position - n * _wall_run_hold_distance()
	return global_position - n * (global_position - _wall_point).dot(n)

## One tap under each hand, either side of `center` across `facing`.
func _emit_hand_taps(center: Vector3, facing: Vector3) -> void:
	if not _effects_on():
		return
	var right := facing.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.001 else Vector3.RIGHT
	_vfx.hand_taps([center + right * HAND_TAP_HALF_SPREAD, center - right * HAND_TAP_HALF_SPREAD])

## Every stream off at once - for moments with no physics frames to do it (boarding).
func _stop_movement_vfx() -> void:
	if _vfx == null:
		return
	_vfx.grind(false, global_position, Vector3.ZERO, 0.0)
	_vfx.lasers(false, global_position, Vector3.ZERO, 0.0, 0.0, Vector3.ZERO, Vector3.INF, 0.0)
	_vfx.slide(false, global_position, Vector3.ZERO, 0.0)
	_vfx.wall_run(false, global_position, Vector3.ZERO, 0.0)
	_laser_on = false
	_laser_ease = 0.0

## A sprint start: sprinting now, not last frame, on the floor. `was` is kept through the air,
## so a landing already sprinting is not one. Static and pure.
static func _sprint_started(grounded: bool, sprint_moving: bool, was: bool) -> bool:
	return grounded and sprint_moving and not was

## The lasers' latch: on above `on_speed`, and once on, held down to `off_speed`. Static and pure.
static func _laser_latch(was_on: bool, current_speed: float, on_speed: float, off_speed: float) -> bool:
	if was_on:
		return current_speed >= off_speed
	return current_speed > on_speed

## 0 at `from`, 1 at `full`, clamped - the lasers' and the slide sparks' strength. Static and pure.
static func _speed_ramp(current_speed: float, from: float, full: float) -> float:
	if full <= from:
		return 1.0
	return clampf((current_speed - from) / (full - from), 0.0, 1.0)

## 1 through the run, falling to 0 across the droop. Static and pure.
static func _wall_dust_fade(t: float, flat_time: float, droop_time: float) -> float:
	if t <= flat_time:
		return 1.0
	if droop_time <= 0.0:
		return 0.0
	return clampf(1.0 - (t - flat_time) / droop_time, 0.0, 1.0)

## The first recent fast direction `now_dir` has swung more than `angle_deg` from inside the
## window, or ZERO. `history` is [time, flat unit direction] pairs, oldest first. Static and pure.
static func _hard_turn_from(history: Array, now_dir: Vector3, now: float, window: float,
		angle_deg: float) -> Vector3:
	var limit := cos(deg_to_rad(angle_deg))
	for sample: Array in history:
		if now - float(sample[0]) > window:
			continue
		var d: Vector3 = sample[1]
		if d.dot(now_dir) < limit:
			return d
	return Vector3.ZERO

## -- the afterimages -------------------------------------------------------------
##
## What they look like is scripts/pilot9_afterimage.gd's; this only says when. See
## docs/specs/pilot9-dash.md, "The afterimages".

## Built in code for the same reason as the movement VFX: a rebuild of pilot9.tscn cannot lose it.
func _setup_afterimage() -> void:
	_afterimage = Pilot9Afterimage.new()
	_afterimage.name = "Afterimages"
	_afterimage.pilot = self
	add_child(_afterimage)

## The hard cut into the `dash` state, from whatever he was doing, onto the same stride every
## time - the mantle's pattern (playback.start + advance(0)), so the pose is the sprint cycle on
## THIS tick and the launch ghost _start_dash() drops next is already it.
func _cut_to_dash_clip() -> void:
	if anim_tree == null or not anim_tree.active:
		return
	var playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
	if playback == null:
		return
	playback.start(DASH_STATE)
	anim_tree.set(DASH_SCALE_PARAM, dash_anim_speed)
	anim_tree.set(DASH_SEEK_PARAM, dash_anim_phase)
	anim_tree.advance(0.0)

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
##
## The hard weld above is the shipping behaviour everywhere except the dash. _start_dash() sets
## _camera_dash_lag_active and captures _camera_dash_lag_start; this function does the rest.
## While the flag is up, position comes from _camera_dash_lag_position() instead of the weld
## target directly, tied to `camera_dash_lag_delay` and `camera_dash_lag_time` rather than to
## `dash_time` or to any distance or speed - which is what guarantees the rig is back on him
## within that window instead of trailing indefinitely behind a pilot9 who kept moving after it
## ended. The flag drops the instant that window closes, handing position back to the exact weld
## above with nothing left over to drift: at elapsed >= delay + duration the two are
## mathematically identical anyway, so the switch itself is invisible. See
## docs/specs/pilot9-dash.md, Camera.
func _process(delta: float) -> void:
	_seek_vault_clip()
	_handle_camera_state(delta)
	var target := get_global_transform_interpolated() 		* (CAMERA_PIVOT_OFFSET + Vector3(0.0, _camera_zoom_lift(), 0.0))
	if _camera_dash_lag_active:
		_camera_dash_lag_elapsed += delta
		camera_pivot.global_position = _camera_dash_lag_position(
			_camera_dash_lag_start, target, _camera_dash_lag_elapsed,
			camera_dash_lag_delay, camera_dash_lag_time)
		if _camera_dash_lag_elapsed >= camera_dash_lag_delay + camera_dash_lag_time:
			_camera_dash_lag_active = false
	else:
		camera_pivot.global_position = target


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return

	if event is InputEventMouseMotion:
		# Look input - cancels the rail's swing-behind. See _handle_rail_camera().
		_rail_camera_idle = 0.0
		# Settings.mouse_sensitivity is a 0.25x-2.00x scalar on top of this
		# authored value, not a replacement for it - the number itself is a
		# deliberate feel decision. See docs/specs/settings.md, Controls.
		var sensitivity := mouse_sensitivity * Settings.mouse_sensitivity
		camera_pivot.rotation.x = _clamp_pitch(camera_pivot.rotation.x - event.relative.y * sensitivity,
			tilt_up_limit, tilt_down_limit)
		camera_pivot.rotation.y += -event.relative.x * sensitivity
		if is_wall_running:
			camera_pivot.rotation.y = _clamp_yaw_off_wall(camera_pivot.rotation.y, _wall_normal)
	elif event is InputEventMouseButton and event.pressed 			and camera_mode == CameraMode.THIRD_PERSON:
		# Wheel zoom. factor is 0 on some devices that do not report it; treat that as a notch.
		var notches: float = event.factor if event.factor > 0.0 else 1.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(notches)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(-notches)

func _input(event: InputEvent) -> void:
	if InputMap.has_action("camera_mode_switch") and event.is_action_pressed("camera_mode_switch") and allow_camera_mode_switch:
		camera_mode = CameraMode.THIRD_PERSON if camera_mode == CameraMode.FIRST_PERSON else CameraMode.FIRST_PERSON
		_update_camera_mode()
	# Third person only, and not while wall-running: that run picks its own side.
	if not frozen and not is_wall_running and camera_mode == CameraMode.THIRD_PERSON \
			and InputMap.has_action("shoulder_swap") and event.is_action_pressed("shoulder_swap"):
		swap_shoulder()
	# The draw / holster animation; it ignores the press itself in a mantle, vault or wall-run.
	# Out in the blizzard the staff is his torch: neither the holster nor the spin.
	if not frozen and not is_tredging and InputMap.has_action("equip") \
			and event.is_action_pressed("equip"):
		press_equip()
	if not frozen and not is_tredging and reflect_spin != null and InputMap.has_action("reflect") 			and event.is_action_pressed("reflect"):
		reflect_spin.try_start()
	# Cosmetic: works in the blizzard too. `frozen` keeps it to the pilot being played.
	if not frozen and InputMap.has_action("hat") and event.is_action_pressed("hat"):
		toggle_hat()

## Flips the chosen shoulder. The eased slide in _handle_camera_shoulder() does the rest.
func swap_shoulder() -> void:
	_shoulder_side = -_shoulder_side

## -- the held item ----------------------------------------------------------
##
## The staff, and whatever replaces it. Everything lives in scripts/items/item_holder.gd; these
## are the doors in. See docs/specs/pilot9-held-item.md.

const _ItemHolder := preload("res://scripts/items/item_holder.gd")

## Built in _ready(). Null only before then.
var item_holder: Node = null

func _setup_item_holder() -> void:
	item_holder = _ItemHolder.new()
	item_holder.name = &"ItemHolder"
	add_child(item_holder)
	item_holder.setup(get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D,
		anim_player, anim_tree, self)
	item_holder.set_item(starting_item)
	_setup_reflect()
	_setup_equip_anim()

## Swaps what he carries, keeping it drawn or holstered as it was. null takes it away.
func set_item(item: HeldItem) -> void:
	if equip_anim != null:
		equip_anim.finish_now()
	item_holder.set_item(item)
	_apply_rim_light()

## Draw or holster as a snap, this frame. Does nothing with no item. Scripts and tests use this;
## the R key plays the animation through press_equip().
func toggle_drawn() -> void:
	if equip_anim != null:
		equip_anim.finish_now()
	# A spin needs the staff in his hands: holstering ends it on the spot.
	if reflect_spin != null:
		reflect_spin.cancel()
	item_holder.toggle_drawn()

## The R key: the draw or holster animation. Returns whether one started. See
## scripts/items/equip_anim.gd and docs/specs/pilot9-equip-holster.md.
func press_equip() -> bool:
	if equip_anim == null or not equip_anim.ready_to_play():
		var was := is_item_drawn()
		toggle_drawn()
		return was != is_item_drawn()
	return equip_anim.toggle()

const _EquipAnim := preload("res://scripts/items/equip_anim.gd")

## Built in _ready(), after the reflect. Null only before then.
var equip_anim: Node = null

func _setup_equip_anim() -> void:
	equip_anim = _EquipAnim.new()
	equip_anim.name = &"EquipAnim"
	add_child(equip_anim)
	equip_anim.setup(self, item_holder,
		get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D, reflect_spin)

func is_item_drawn() -> bool:
	return item_holder != null and item_holder.is_drawn

## -- the cowboy hat ------------------------------------------------------------------
##
## On and off with H, no animation. Everything lives in scripts/items/hat_holder.gd. See
## docs/specs/pilot9-cowboy-hat.md.

const _HatHolder := preload("res://scripts/items/hat_holder.gd")

@export_group("Hat")
## Where the hat sits, in Head-bone space (metres).
@export var hat_offset: Vector3 = Vector3(0.0, 0.11, 0.035):
	set(value):
		hat_offset = value
		if hat_holder != null:
			hat_holder.place(hat_offset, hat_tilt)
## How far it is tipped back off his brow, degrees.
@export var hat_tilt: float = 6.0:
	set(value):
		hat_tilt = value
		if hat_holder != null:
			hat_holder.place(hat_offset, hat_tilt)
@export_group("")

## Built in _ready(). Null only before then.
var hat_holder: Node = null

func _setup_hat() -> void:
	hat_holder = _HatHolder.new()
	hat_holder.name = &"HatHolder"
	add_child(hat_holder)
	hat_holder.setup(get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D,
		hat_offset, hat_tilt)

## The H key. Off at boot, never saved.
func toggle_hat() -> void:
	if hat_holder != null:
		hat_holder.toggle()

func is_hat_on() -> bool:
	return hat_holder != null and hat_holder.is_on

## -- reflect ---------------------------------------------------------------------
##
## The staff spin that turns projectiles back. See scripts/items/reflect_spin.gd and
## docs/specs/pilot9-reflect.md.

const _ReflectSpin := preload("res://scripts/items/reflect_spin.gd")

var reflect_spin: Node = null
## Emitted when a hostile hit lands. The firing range's HUD counts these.
signal hit_taken(amount: float, kind: StringName, point: Vector3)
const _HitFeedback := preload("res://scripts/range/pilot_hit_feedback.gd")
var hit_feedback: Node = null
## Extra lens degrees from a perfect reflect, easing to zero. See kick_fov().
var _reflect_fov_deg: float = 0.0
var _reflect_fov_rate: float = 0.0

func _setup_reflect() -> void:
	add_to_group(&"reflect_target")
	reflect_spin = _ReflectSpin.new()
	reflect_spin.name = &"ReflectSpin"
	add_child(reflect_spin)
	reflect_spin.setup(self, item_holder,
		get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D, _vfx)
	hit_feedback = _HitFeedback.new()
	hit_feedback.name = &"HitFeedback"
	add_child(hit_feedback)
	hit_feedback.setup(self)

## Something hostile landed on him (the firing range's bolts). Feedback only: he cannot be hurt, so
## `amount` is carried for whatever listens, and nothing here changes his movement.
func take_hit(amount: float, kind: StringName, point: Vector3) -> void:
	if hit_feedback != null:
		hit_feedback.hit(point)
	hit_taken.emit(amount, kind, point)

## A tinted spark burst for hit effects. MOVEMENT EFFECTS gates it.
func spark_burst(point: Vector3, dir: Vector3, count: int, burst_speed: float, tint: Color) -> void:
	if _effects_on():
		_vfx.impact_burst(point, dir, count, burst_speed, tint)

## Adds `degrees` to the lens and eases it back to nothing over `seconds`. Larger kicks win.
func kick_fov(degrees: float, seconds: float) -> void:
	if degrees <= _reflect_fov_deg:
		return
	_reflect_fov_deg = degrees
	_reflect_fov_rate = degrees / maxf(seconds, 0.01)

## -- the hologram pause menu ----------------------------------------------------
##
## The rig the UI autoload finds through the `hologram_host` group. See scripts/pilot9_hologram.gd
## and docs/specs/pilot9-hologram-pause.md.

const _Hologram := preload("res://scripts/pilot9_hologram.gd")

var hologram: Node3D = null

func _setup_hologram() -> void:
	hologram = _Hologram.new()
	hologram.name = &"Hologram"
	add_child(hologram)
	hologram.setup(self, camera_3d,
		get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D, character)

## -- the wall hand ---------------------------------------------------------
##
## The empty hand trailing along the wall during a run. See scripts/wall_hand.gd and "The wall
## hand" in docs/specs/pilot9-wall-run.md.

const _WallHand := preload("res://scripts/wall_hand.gd")

## Built in _ready(), after the item holder so its modifiers run after the item's.
var wall_hand: Node = null

func _setup_wall_hand() -> void:
	wall_hand = _WallHand.new()
	wall_hand.name = &"WallHand"
	add_child(wall_hand)
	wall_hand.setup(get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D, self)

## -- the slide hand --------------------------------------------------------
##
## The right arm bent out to his side with the hand trailing at the floor during a slide. See
## scripts/slide_hand.gd.

const _SlideHand := preload("res://scripts/slide_hand.gd")

## Where the right hand reaches during a slide, in skeleton space: the rig faces +Z with his
## right on -X, and y 0 is the floor under his feet. Behind his shoulder and just off the ground.
@export var slide_hand_target: Vector3 = Vector3(-0.35, 0.06, -0.6)
## Which way the right elbow points, skeleton space - straight back behind him (rig faces +Z),
## tucked in toward his body and a little up.
@export var slide_elbow_pole: Vector3 = Vector3(0.45, 0.25, -1.0)

## Built in _ready(), after the item holder and wall hand so it runs last on the right arm.
var slide_hand: SkeletonModifier3D = null

func _setup_slide_hand() -> void:
	var skel := get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		return
	slide_hand = _SlideHand.new()
	slide_hand.name = &"SlideHand"
	slide_hand.body = self
	skel.add_child(slide_hand)

## -- the poncho -----------------------------------------------------------------
##
## scripts/pilot9_poncho.gd is the whole of it; this only builds it. See docs/specs/pilot9-poncho.md.

## Built in _ready() when poncho_enabled. Null otherwise.
var poncho: Pilot9Poncho = null

func _setup_poncho() -> void:
	if not poncho_enabled:
		return
	var skel := get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		return
	poncho = Pilot9Poncho.new()
	poncho.pilot = self
	skel.add_child(poncho)
	poncho.setup(skel)

## -- the tredge ------------------------------------------------------------------
##
## Out in a Storm's snow he can only tredge. scripts/pilot9_tredge.gd decides when and draws the
## pose; this side is the flag the lockouts read. See docs/specs/pilot9-tredge.md.

const _Tredge := preload("res://scripts/pilot9_tredge.gd")

## True while he is tredging: sprint, jump, crouch, slide, dash, wall-run, wall climb, mantle,
## vault, rail, reflect and equip are all refused. The AnimationTree's `tredge` state reads it.
var is_tredging: bool = false
## Built in _ready(). Null only before then.
var tredge: Node = null

func _setup_tredge() -> void:
	tredge = _Tredge.new()
	tredge.name = &"Tredge"
	add_child(tredge)
	tredge.setup(self, get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D)

## Whether the tredge may start now: only out of plain locomotion, never mid-move.
func can_begin_tredge() -> bool:
	return not (is_dashing or is_wall_running or is_wall_climbing or is_climbing or is_vaulting
		or is_sliding or is_rail_grinding or is_rail_switching)

func begin_tredge() -> void:
	is_tredging = true
	is_crouching = false
	# sprint_toggled is cleared by _update_sprint_toggle(), which runs right after this.
	_jump_buffered = 0.0

func end_tredge() -> void:
	is_tredging = false

## The tredge cycle's playback rate: tredge_clip_rate_at_speed at tredge_speed, following his
## actual speed so the feet stay planted through a gust's dip.
func tredge_clip_rate() -> float:
	var h := Vector2(velocity.x, velocity.z).length()
	return tredge_clip_rate_at_speed * h / maxf(tredge_speed, 0.01)

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
	if is_dashing:
		_end_dash()
	# The trail would otherwise hang in the world, hidden with him, and flash back in at
	# wherever he exits. Cut it outright, dashing or still clearing.
	if _afterimage != null:
		_afterimage.clear()
	if is_climbing:
		# The same "land him on top" stop a freeze mid-mantle takes - he is on a scripted path
		# over an edge with his shape off, and that has to be closed out cleanly.
		_end_climb(false)
	_abort_vault()
	if is_sliding:
		_end_slide()          # also clears is_slide_holding and arms the cooldown
	# Restores anim_tree.active before enter_vehicle() sets it false again for the ride -
	# without this, boarding mid-wall-run would leave the tree switched off (and the
	# AnimationPlayer parked on sprint_forward) under whatever he next steps out into.
	_end_wall_run()
	_end_wall_climb()
	_wall_climb_jump_buffered = false
	_wall_climb_coyote_left = 0.0
	# Ends cleanly, as the wall-run does. The graces go with it - a rail coyote or carry firing
	# the moment he steps back out would be a launch from somewhere he no longer is.
	_end_rail_grind(RailExit.BOARD)
	_end_rail_switch()
	# The stream and its light are only switched off by a physics frame, and there are none
	# aboard - left on, they would spray at wherever he steps back out for a frame.
	_land_dust_pending = 0.0
	_stop_movement_vfx()
	_rail_coyote_left = 0.0
	_rail_launch_carry = false
	_rail_land_ease_elapsed = -1.0
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
	_reseed_body_lean()
	# Half a turn round from his facing: behind him, looking at the machine he climbed out of.
	# mech-camera-handover.md's rule, and the fix for the handback dropping him staring at his
	# own back. Written straight onto the pivot because the body is unrotated.
	camera_pivot.rotation.y = facing_yaw + PI
	camera_pivot.rotation.x = EXIT_PITCH
	velocity = Vector3.ZERO
	# Not a landing, and nothing from before boarding should still be swaying.
	_reset_camera_motion()
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

## -- anime animation ------------------------------------------------------------
##
## ANIME: drawn cycles on Locomotion (8 drawings a cycle, on his real foot plants) and held impact
## accents; everything else, and his rotation and position always, smooth. The accents fire from
## the moments themselves - see the anime_hold.accent() calls. See docs/specs/anime-animation.md.

var anime_hold: AnimeHold = null

func _setup_anime_hold() -> void:
	var skel := get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		return
	anime_hold = AnimeHold.new()
	add_child(anime_hold)
	anime_hold.setup(skel)
	anime_hold.cycle_state = _anime_in_locomotion
	anime_hold.velocity = func() -> Vector3: return velocity
	if reflect_spin != null and reflect_spin.has_signal(&"reflected"):
		reflect_spin.reflected.connect(func(_p: Node, perfect: bool, _pt: Vector3) -> void:
			if perfect:
				_anime_accent(&"perfect_reflect"))

func _anime_in_locomotion() -> bool:
	return is_on_floor() and _anime_state() == &"Locomotion"

func _anime_state() -> StringName:
	if anim_tree == null:
		return &""
	var playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
	return playback.get_current_node() if playback else &""

## `still_on`: asked when the hold would start; false drops it (see AnimeHold.accent()).
func _anime_accent(accent_name: StringName, strength: float = 1.0,
		still_on: Callable = Callable()) -> void:
	if anime_hold != null:
		anime_hold.accent(accent_name, strength, -1.0, still_on)
