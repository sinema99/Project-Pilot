# Spec: pilot9's rail grind

> **Status:** specified 2026-09-24 (grilling session), **built 2026-09-24, not played.** Every
> number is a starting guess exposed as an `@export_range`. See *Built* at the bottom for where
> the build left the letter of this spec.
> **Scene:** `scenes/pilot9.tscn`, plus a new pasteable `Rail` node. Tested in `scenes/trial.tscn`.
> **Character:** `assets/pilot9.glb` - `P_rail-grind` and `P_rail-sprint` (2026-09-21 export,
> imported but not yet in `GLB_CLIPS`). See *The animation*.
> **Reference:** a skateboarder grinding down a rail (the user's words), Jet Set Radio / Sonic
> Adventure for the auto-catch - bent wherever that meets the metre grid, and the grid wins.
> **Touches:** `docs/specs/pilot9-jump-grid.md` (the grind's two gears are measured against it),
> `docs/specs/pilot9-wall-run.md` (lockout, crouch-to-let-go, the same-frame priority),
> `docs/specs/pilot9-dash.md` (dashing off a rail), `docs/game-overview.md` (map #4, "cables on
> the machine").

## Problem statement

`docs/game-overview.md` caps the game at four movement techs. Double jump, air dash and
wall-run are built; rail grind is the last, and the only one with **a level-authoring piece** -
walls already exist in every map, rails do not. It replaced the grapple for exactly that reason:
a rail goes only where the level designer puts it.

Map #4's boss is "climb the giant, cables on the machine", so rails must also work when they are
**parented to something that moves**.

## The rule

**Falling onto a rail catches him. He rides it at one of two fixed speeds - grinding at 7.5 m/s,
or running at 10 m/s while sprint is toggled on - in the direction he arrived, until he jumps, dashes,
crouches or runs off the end.** The rail counts as ground.

## The rail

A new `Rail` node, `scripts/rail.gd` - `@tool`, `extends Path3D`, `class_name Rail`. You draw its
`Curve3D` in the Godot editor with Bézier handles, then paste it into a map the way
`bounce_pad.gd` and the button/door are pasted. Rails are placed in Godot on top of the imported
Blender greybox, not in Blender (GLB carries no curves; rebuilding a centreline from a tube mesh
was rejected as fragile).

- **The tube is generated** from the curve: a ring of `rail_sides` verts swept along
  `curve.get_baked_points()` at `rail_radius`, rebuilt in the editor on `curve_changed`. What he
  rides and what you see come from the same curve, so they cannot disagree.
- **No collision.** The tube is visual only. Walking or rising through it clips for a moment
  and can never snag him, give a stray `is_on_floor()`, or become a wall-run surface.
- **Found by group.** `_ready()` adds the rail to the `rails` group. pilot9 checks that group
  directly - a map has a handful of rails, and `get_closest_offset()` per rail is cheap.
- **Colour:** the blockout palette's cyan, "what you grab" - a rail is caught, so it borrows the
  grab colour rather than claiming a new one. Cel material and outline as the blockout boxes
  have. `extends Path3D`, so it cannot inherit `blockout_box.gd`; it copies the material setup.
- **Closed curves loop.** If `curve.closed` (Godot 4.4+) the ride wraps the offset and has no
  end.
- **Local space, always.** The grind stores a **curve offset**, never a world position, and
  converts through the rail's *current* `global_transform` every frame. A rail parented to a
  moving body carries him with it at no extra cost, and a static rail pays nothing for it.

| Export (on `Rail`) | Default | |
|---|---|---|
| `rail_radius` | **0.08 m** | Thicker for map #4's cables |
| `rail_sides` | 8 | Tube ring resolution |

## Attach

Every airborne frame, when `can_rail_grind`, for each rail in the group:

1. **Near.** His feet (the capsule's bottom) are within `rail_catch_radius` (**1.0 m**; was 0.5 m until 2026-09-24, widened from play) of the
   centreline's closest point.
2. **Above.** His feet are above the centreline in the rail's up at that point (for an upright
   rail, world up). Rising up through a rail from underneath does not catch.
3. **Not locked out.** It is not the rail he left less than `rail_relatch_lockout` (**0.3 s**)
   ago. Any other rail may catch him at once, so rail-to-rail chains are immediate.

Air only. Walking or sprinting into a knee-high rail does nothing. There is no grind button.

**The snap** eases his feet onto the top of the tube (centreline + `rail_radius`) over
`rail_snap_time` (**0.08 s**) rather than teleporting.

**Priority:** a rail catch beats a wall-run attach and a mantle on the same frame - the rail was
placed on purpose. `_handle_rail_grind()` runs ahead of `_handle_mantle_trigger()`.

## Direction

On attach he goes along whichever direction of the rail tangent is closer to his horizontal
velocity. With (almost) no horizontal velocity - a vertical drop onto it - his facing decides.
**Then it is locked:** no braking, no reversing, no standing still on a rail. The stick does not
steer the ride. It only aims the jump-off and the dash.

## The two gears

| Gear | Input | Speed | Clip | Jump-off clears |
|---|---|---|---|---|
| Grind | none (default) | **7.5 m/s** | `P_rail-grind` | **9 m** - the sprint rung |
| Rail sprint | sprint toggle on | **10 m/s** | `P_rail-sprint` | **12 m** - a new rung, rail-only |

- Entry speed is brought to the gear over `rail_speed_ease_time` (**0.25 s**), up or down,
  like the wall-run's floor. Switching gears eases the same way.
- **Slopes do not change the speed.** No gravity along the rail - a true-skate model would give
  every rail an arbitrary exit distance, and the grid wins that conflict here as it did on the
  wall-run.
- 12 m is `rail_sprint_speed * jump_air_time` = 10 × 1.2. It is the only gap in the game past
  9 m on a single jump, so **a 10-12 m gap means "rail sprint off this"** to the player.

## The rail counts as ground

Attaching does what a landing does:

- refills `_air_jumps_left` (the double jump),
- refreshes the dash air charge,
- zeroes `_wall_jumps_taken`.

The wall-run refused this because walls are everywhere and refilling on them turns corridors into
elevators. Rails are only where you put them, so the elevator is authored.

**Build rule, and the cost of this call: the highest he can reach off a rail is the rail's height
+ 6 m** (jump + double jump). Keep that in mind next to anything he is not meant to reach.

## Leaving

Every exit starts the same-rail lockout.

| Exit | Result |
|---|---|
| **Jump** | An ordinary jump - 3 m, 1.2 s - at gear speed, so 9 or 12 m. Stick neutral: straight along the tangent. Stick pushed: the heading bends up to `rail_jump_max_bend` (**45°**) toward it, **speed unchanged**, so distance stays on the grid; only where it lands moves. The double jump is available after, because the rail refilled it |
| **Dash** | A normal dash along the tangent, or bent by the stick with the same 45° cap. Spends the charge the rail refilled |
| **Crouch** | Let go. He drops with his current along-rail velocity and no jump, like crouch-to-let-go on the wall-run. The press is used up - it does not also start a slide on landing |
| **End of rail** | He carries on along the end tangent at gear speed, **including its slope** - an end that tilts up kicks him up a little. Gravity from there |
| **Mech boarding** | Ends the grind cleanly, as it does the wall-run |

**Rail coyote.** A jump pressed within `rail_coyote_time` (**0.15 s**) of running off the end
still gets the full rail jump, with gear speed and the 45° bend. Jumping at the lip is the
skilled play; pressing a bit late is not punished. Its own export because the global
`coyote_time` ships at **0.0** - the Q7 answer's "normal coyote window" would have been none at
all, so this copies `wall_jump_coyote_time`'s 0.15 instead.

## Body

He yaws to the ride direction and **stays upright** - world up, whatever the rail's slope. No
pitch (the slope-align's up-axis tilt does not run on a rail). The one exception, added
2026-09-24 from play: a **roll into bends** - up to `rail_lean_max` (20°, raised from 10° after play) toward the inside of
the curve, in proportion to how tight it is (full at `rail_lean_full_turn`, 6° of heading per
metre, radius ~9.5 m), read off the ride tangent 0.75 m either side of him and eased on at
`slope_align_speed`. A straight rail, or one that only changes slope, leans nothing. His feet sit at
centreline + `rail_radius`. Any sideways skate stance is in the clip itself.

## The animation

Both clips go into `GLB_CLIPS` in `scripts/pilot9_build_scene.gd`:

```gdscript
"P_rail-grind":  {"as": &"rail_grind",  "loop": Animation.LOOP_LINEAR},
"P_rail-sprint": {"as": &"rail_sprint", "loop": Animation.LOOP_LINEAR},
```

A `rail` state in the AnimationTree (a new `_ensure_rail_state()` beside
`_ensure_wall_run_state()`) blends the two on `is_rail_sprinting`, with a short crossfade
(~0.15 s). Entered off `is_rail_grinding`. The jump-off plays the ordinary jump clip off
`is_jumping`. Nothing new.

**Check at reimport:** whether either clip carries root motion. Both are assumed in-place loops.
If one was exported without In Place, strip it the way the slide motion is handled, or flag it.

## The camera

Rail only, third person only. When the look input has been idle for `rail_camera_idle_delay`
(**0.3 s**), the camera **yaw** eases toward the ride direction at up to `rail_camera_swing_rate`
(**90°/s**). Any look input cancels it at once and restarts the idle timer. Pitch is never
touched. First person does nothing - the view already is his facing. No other state gets this.

## The UI

`can_rail_grind := true`, beside `can_wall_run`. `tab_abilities.gd`: `RAIL GRIND` moves out of
`TECH` ("Found in map 4.") into `BASE_KIT` as a toggle row - "Ride any rail you land on." - the
same move the wall-run made on 2026-09-19. The map-4 unlock gates it once map 4 exists.

## The numbers

| Export (on pilot9) | Default | |
|---|---|---|
| `can_rail_grind` | true | |
| `rail_grind_speed` | **7.5 m/s** | = `sprint_speed`; grid 9 m |
| `rail_sprint_speed` | **10.0 m/s** | Grid 12 m |
| `rail_speed_ease_time` | 0.25 s | Entry and gear change |
| `rail_catch_radius` | 1.0 m | Feet to centreline |
| `rail_snap_time` | 0.08 s | |
| `rail_relatch_lockout` | 0.3 s | Same rail only |
| `rail_jump_max_bend` | 45° | Jump and dash |
| `rail_coyote_time` | 0.15 s | Off the end |
| `rail_camera_idle_delay` | 0.3 s | |
| `rail_camera_swing_rate` | 90°/s | Yaw only |

## Shape of the code

State, beside the wall-run's:

```gdscript
var is_rail_grinding: bool
var is_rail_sprinting: bool       # the gear; drives the clip blend
var _rail: Node                   # the Rail ridden (a Path3D; untyped per the class-cache rule)
var _rail_offset: float           # along the curve, local - never a world position
var _rail_dir: int                # +1 / -1 along the curve, locked at attach
var _rail_speed: float            # eases to the gear
var _rail_snap_left: float
var _rail_last: Node              # for the same-rail lockout
var _rail_lockout_left: float
var _rail_coyote_left: float
var _rail_coyote_tangent: Vector3 # the end tangent the coyote jump launches along
var _rail_camera_idle: float
```

| Function | |
|---|---|
| `_handle_rail_grind(delta)` | **New.** Catch test while airborne; while riding: advance `_rail_offset`, wrap or end, place him, face him. After `_handle_dash()`, before `_handle_mantle_trigger()` |
| `_rail_catch_gates(feet, closest, up, dist, radius, locked)` | **New, static, pure.** The three attach gates |
| `_rail_ride_dir(tangent, h_velocity, facing, look)` | **New, static, pure.** +1 / -1 |
| `_rail_jump_heading(tangent, stick, max_bend)` | **New, static, pure.** The bent launch direction - shared by the jump and the dash |
| `rail_jump_distance(speed)` | **New, static, pure.** `speed * jump_air_time` - the 9 / 12 m |
| `_start_rail_grind(rail, offset)` | Refill (ground rules), latch direction, start the snap |
| `_end_rail_grind(reason)` | Lockout, coyote on `END`, clears state |
| `_handle_gravity_and_jump()` | Suspended while grinding, as for the wall-run; the rail jump and rail coyote take the press ahead of the air jump |
| `_handle_crouch_and_slide()` | While grinding, crouch ends the grind and the press is consumed |
| `_handle_dash()` | Launched from a rail: tangent heading bent by the stick, ends the grind |
| `_handle_controller_camera()` | The idle swing-behind |

Riding sets the velocity from the curve: the next local point converted to world through
`_rail.global_transform`, minus where he is, over `delta`. `move_and_slide()` then carries him -
and the rail's own motion along with it, for a moving rail.

## Tests

`tests/test_pilot9_rail_grind.gd`, headless.

- **The grid.** `rail_jump_distance(rail_grind_speed) == 9.0`, `rail_jump_distance(rail_sprint_speed) == 12.0`.
- **The gates**, pure: in range and above catches; **below the centreline refuses** (rising
  through); out of range refuses; the lockout refuses the same rail and lets a different rail
  catch.
- **The direction.** Velocity along +tangent gives +1, along -tangent gives -1; zero velocity
  falls back to facing.
- **The bend.** Neutral stick is the tangent; a stick 90° off the tangent is capped at 45°; the
  heading is unit length, so speed and grid distance are unchanged.
- **The refill.** Starting a grind refills the air jump, the dash charge and the wall-jump count.
- **Local space.** A rail whose parent is moved between two frames carries the rider's world
  position by the same amount (the moving-rail guarantee, checked with no physics world by
  sampling through `global_transform`).
- **Closed loop.** An offset past the end of a closed curve wraps; on an open curve it ends.
- **`can_rail_grind = false`** refuses every catch.

The snap, the camera swing, the clip blend and the feel of both gears need a running frame and
are checked in play.

## Test geometry

**On the jump grid** (`scripts/jump_grid.gd`), built in code so rebuilds and tests can measure it:

- **A flat rail with a landing pad exactly 9 m past its end** - the grind gear's jump-off.
- **A flat rail with a pad at 12 m** - the sprint gear's.
- **A parallel pair, ~3 m apart** - the 45° hop across.

**Hand-placed in `scenes/trial.tscn`**, to test the paste-and-draw workflow itself:

- a long **S-curve down-rail**,
- a rail whose **end tilts up** (the lip kick),
- a **closed loop**.

No moving test rail this pass - the local-space test covers it.

## Deferred

- **Effects.** Grind sparks at the feet; the dash's speed-line bundle on rail sprint. After play.
- **A moving rail in `trial.tscn`**, on a sliding platform. Map #4 will need one anyway.
- **Rail ↔ wall-run handoffs** on the course (rail end into a wall, wall-jump onto a rail) - both
  should work from the rules above with nothing new; not given test geometry yet.

## Rejected

- **Rails authored in Blender** (tube mesh or empties chain). GLB has no curves; rebuilding a
  centreline is fragile, and a rail baked into the static map cannot ride a moving boss.
- **A grind button** (Tony Hawk). Routes are authored; a rail that is there is meant to be ridden.
- **Ground entry.** A knee-high rail would grab a player who meant to run past.
- **Entry speed + gravity** (true skate). Arbitrary exit distances; breaks the grid.
- **Braking / reversing.** A third state with no clip, and "back" is ambiguous on a curve.
- **Full 360° jump aim.** Backwards off a rail at 10 m/s is a route nobody authored.
- **A solid tube.** A 16 cm curved trimesh floor is where `CharacterBody3D` jitters.
- **Refill nothing / dash only.** Makes chains stingy, or a split rule to explain.
- **Pitching with the rail.** He looks like he's falling over at steep angles.
- **A hard-locked camera.** Takes control away; see the control-over-fidelity stance.

## Built (2026-09-24)

Everything above is in, as written, except where this list says otherwise. Headless:
`tests/test_pilot9_rail_grind.gd` (all of *Tests*, plus the tab row, the tree state and the
ruler's gaps); a scripted physics run also confirmed catch, snap, the ease to 7.5 m/s, a rail
moved mid-ride carrying him, and the run-off along the end tangent. **Nothing has been played.**

**Where the build differs, and why:**

- **The tube's material is the blockout boxes' *actual* one** - `metre_grid.gdshader`, unshaded,
  cyan, no outline. The spec said "cel material and outline as the blockout boxes have", but the
  boxes carry neither; the rail matches the boxes rather than the description of them.
- **On a rail, the gear IS the sprint toggle** (2026-09-24, replacing "held, toggle frozen").
  Caught sprinting he rail-sprints, caught otherwise he grinds; a sprint press on the rail shifts
  gear and he leaves in whichever gait he rode in. Held sprint meant a toggled sprinter who had let
  go of the key caught the rail in grind.
- **A rail launch is not braked by a released stick** (`_rail_launch_carry`, until he lands).
  Without it `air_momentum_brake` (200 m/s^2) stops a stickless flight dead in 0.04 s, so
  "carries on along the end tangent" and the neutral-stick 9 / 12 m jump would not have
  happened - and nobody holds the stick on a ride it does not steer. Set by the end, the jump,
  the rail coyote and crouch; cleared by landing, a dash, a wall-run or a mantle. Pushing the
  stick hands him back to ordinary air control.
- **Ordinary air control still applies after the launch.** The 45 degree cap governs the launch
  heading; a stick held further off turns him the rest of the way in the air, as it does off any
  jump. If that reads as the cap not working, the fix is push protection like the wall-jump's.
- **The catch is swept, not sampled** (fixed 2026-09-24, after play: "sometimes pilot just falls
  through the rail"). The gates used to test only where his feet were each frame. At 60 Hz a fall
  moves 0.17 m a frame at 10 m/s and 0.47 m at `max_fall_speed`, and the half-ball above the
  centreline is only 0.5 m deep on top and shallower off to the side (0.22 m at 0.45 m out). So a
  frame could step from above the zone to below the centreline with no frame inside it. Now the
  gates run along the path his feet took since last frame, every `RAIL_SWEEP_STEP` (0.05 m).
  The rail met earliest on that path wins, and his feet go back to that point before the snap.
  The sweep is dropped after any frame the catch did not run (ground, dash, climb, a ride, a
  switch), and for gaps over `RAIL_SWEEP_MAX` (2 m, a teleport).
- **Side approaches** (fixed 2026-09-24, after play: still falling through, "from the side").
  A probe firing arcs square across a rail found two things. (1) Every pass with his feet level
  with the centreline or below it missed, and the tube has no collision, so he went through it.
  The *Above* gate is now *not under*: below the centreline only the 90 degree cone straight
  underneath is refused (feet further below than to the side). Rising up through a rail from
  underneath still doesn't catch; a side pass now catches down to ~0.35 m under the centreline.
  (2) *Direction* compared his whole horizontal velocity, so dead side-on the sign of a near-zero
  dot product decided it: always +1 along the curve, i.e. whichever way it was drawn. Now it is
  momentum **along the rail** (over `RAIL_DIR_MIN_SPEED`, 0.5 m/s), else his facing, else the
  camera, each only if it leans more than 10 degrees off square (`RAIL_DIR_MIN_ALIGN`).
- **A catch at an open tip that would ride straight off it is refused** (`RAIL_END_MARGIN`,
  0.1 m) - otherwise brushing a rail's end on the way past is a free refill. Unless the direction
  was a tiebreak (under 0.5 m/s along the rail): a side-on catch at a tip rides back along it.
- **Jump and run-off use the ride's current speed**, which is the gear once the 0.25 s ease has
  finished. A gear change just before the lip launches mid-ease rather than popping.
- **The sprint FOV follows the rail gear** while grinding, since the toggle it normally reads is
  frozen.
- **`Locomotion -> rail`** is wired as well as `jump`/`fall`, for a catch on the first frame off a
  ledge.
- **The parallel pair is 3 m as specified, but a full-bend hop overshoots it.** At the grind gear
  a 45 degree launch travels ~6.4 m sideways by the time he is back at rail height, and at 3 m he
  is still near his apex over the second rail. Steering brings it back; tune the spacing in play.
- **Offsets are curve metres.** Do not scale a `Rail` node - a scaled rail would ride at the
  wrong speed. Draw the curve at the size you want.

**Where it lives:** `scripts/rail.gd`; `_handle_rail_grind()` and the section after
`_mirror_model_for_wall_run()` in `scripts/pilot9.gd`; `_ensure_rail_state()` in the builder;
`_drive_rail()` in `scripts/pilot9_animation.gd`; the `Rails` row in `scripts/jump_grid.gd`;
`RailTest` in `scenes/trial.tscn` (S-curve at x 8, lip kick at x 16, loop at x 27, all on
TrainingV's floor).

## Rail to rail (amendment, 2026-09-24)

> **Status:** specified and built 2026-09-24, not played. Asked for as "jump off of one rail and
> then land on the next". Two calls, both the recommended option: an **aimed rail switch**, and
> the 45° cap **held until the apex**.

**What a headless probe found before this.** Forward chains already worked: a rail 9 m on at
the same height, a lower rail, and running off the end onto a rail below all caught. **Sideways
never did**, for two reasons:

1. **The 45° cap was one frame long.** Ordinary air control ran on the launch frame itself, so
   a stick held sideways turned him fully sideways at once - `(7.5, 9.7, 0.0)`, no forward speed
   left - and he flew 9 m out across the air past any parallel rail.
2. **The catch was a 0.5 m half-ball.** From the side you had to arrive within half a metre of a
   line at exactly the right height. Forward, the whole length of the rail is the target.

### The rail switch

**Jump off a rail with the stick pushed toward another rail within reach, and he hops onto it.**
It is a scripted flight, not a ballistic guess, so it lands every time - including on a rail
that is moving.

- **The trigger.** A rail jump (not the rail coyote) with the stick at least
  `rail_switch_min_angle` (**30°**) off the ride tangent. Less than that - or no rail that way -
  is the ordinary rail jump, unchanged.
- **The target.** From the point **A** he would have reached by riding straight on for
  `rail_switch_time`, every other rail's closest point **T** to A. A rail qualifies when:
  - T is on the side the stick points, at least `RAIL_SWITCH_MIN_SIDE` (**0.5 m**) off his line
    (so the rail he is on, or one in line with it, is never a switch);
  - T is within `rail_switch_reach` (**6 m**) of A, flat;
  - T is at most `rail_switch_max_rise` (**2 m**) above his feet and `rail_switch_max_drop`
    (**4 m**) below;
  - landing there does not ride straight off an open tip (the catch's `RAIL_END_MARGIN` rule).

  Of those, the nearest to A. The rail he is on never qualifies.
- **The flight.** `rail_switch_time` (**0.4 s**) from his feet to the tube top at T, asked
  through the target rail's transform every frame (a moving rail is hit where it is now).
  Straight across, flat, plus an arc bump of `rail_switch_arc_height` (**1.0 m**) + half the
  height difference at the middle. He faces his ride direction the whole way.
- **Committed.** Nothing interrupts the flight: jump, dash and crouch presses are ignored and
  nothing else catches, grabs a wall or mantles. A freeze, mech boarding, or the target rail
  leaving the tree drops him into ordinary air with the flight's current velocity.
- **Landing** is an ordinary catch on the target - refills, lockout rules, direction - except
  that he **keeps the gear and speed he left with** instead of easing up from his sideways
  velocity. Direction is whichever way along the new rail his old ride direction points.
- **Animation.** The ordinary jump then fall, off `is_jumping` and `velocity.y`. Nothing new.

Why scripted: the gravity curve has an apex scale and a fall multiplier, air control fights any
sideways stick, and a target rail may move. A computed launch would have to predict all three.

### The 45° cap holds until the apex

`_take_rail_jump()` records the launch tangent. Until he stops rising, after ordinary air
control has run, his flat velocity is turned back to within `rail_jump_max_bend` of that
tangent - speed kept. At the apex (velocity.y ≤ 0) the stick has it all back. Cleared by
landing, a catch, a dash, a wall-run and a mantle, like `_rail_launch_carry`. Also applies to
the rail coyote jump.

This is push protection like the wall-jump's, simpler: a heading clamp, not a split component.

### Numbers

| Export (on pilot9) | Default | |
|---|---|---|
| `can_rail_switch` | true | Off: every rail jump is the ordinary one |
| `rail_switch_min_angle` | **30°** | Stick off the tangent to aim a switch |
| `rail_switch_reach` | **6 m** | Flat, from the ride-on point |
| `rail_switch_time` | **0.4 s** | The hop |
| `rail_switch_arc_height` | **1.0 m** | Bump at mid-flight |
| `rail_switch_max_rise` | 2 m | |
| `rail_switch_max_drop` | 4 m | |

### Tests

`tests/test_pilot9_rail_grind.gd`, pure where possible:

- the stick test: under 30° is not a switch, over it gives the side;
- the target gates: the wrong side, too near the line, out of reach, too high, too low;
- the arc starts at the start, ends at the end, and peaks at the bump;
- the cap: a 90° stick after a rail jump is held at 45° while rising and free after the apex.

Plus a scripted physics run (not in the suite): a parallel pair 3 m apart, switched across with
the stick held.

### Test geometry

The jump grid's parallel pair (3 m, `RAIL HOP`) is now the switch's station. No change.

### Built (rail to rail, 2026-09-24)

As written above. A scripted physics run (a throwaway probe, not in the suite) confirmed: the
switch lands right and left at 3 m, 1.5 m up at 5 m, and 3 m down, each 0.4 s after the press
and at 7.5 m/s. A 9 m-away rail (out of reach) falls back to the ordinary jump, which now flies
at exactly 45° (`(5.3, _, -5.3)`) until the apex. A stick aimed away from the only rail does not
switch. Forward chains (9 m on, lower, run-off onto a rail below) were already catching and still
do. **Nothing has been played.**

- **The gear on landing follows the sprint toggle**, as it does everywhere on a rail; only the
  *speed* is carried. The two are the same thing unless sprint changes mid-hop.
- **The landing teleports him onto the tube** on the last frame (at most one frame's travel),
  so the snap is skipped.

**Where it lives:** the `-- the rail switch --` section after `_apply_rail_velocity()` in
`scripts/pilot9.gd`, `_hold_rail_jump_cap()` beside `_apply_movement()`, and the "Rail Switch"
export group.

### Amendment: the ordinary rail jump drops the rail's momentum (2026-09-24, from play)

The user loves the switch but not the ordinary rail jump carrying the gear speed off the rail.
`_take_rail_jump()` now zeroes horizontal velocity: the jump goes straight up at the ordinary
3 m / 1.2 s, and the stick's ordinary air control is the only thing that moves him. That covers the
jump pressed on the rail and the rail-coyote jump after running off the end. There is no launch
carry and no 45° cap. **Only the switch keeps rail momentum.** Running off the end without jumping,
the crouch let-go and the dash off a rail are unchanged.

This makes the 9 / 12 m "rail jump" figures above stale: the jump grid's `rail_gap` /
`rail_sprint_gap` rulers (`rail_jump_distance()`) no longer describe any jump. `_rail_jump_cap` /
`_hold_rail_jump_cap()` are now never armed. Both are left in place until the user decides.

## Gears doubled (2026-09-24)

User call: "double the speed of rail grinding. both speeds." `rail_grind_speed` 7.5 → **15.0**,
`rail_sprint_speed` 10.0 → **20.0** m/s (export ranges widened to 60). The grid rungs follow:
a rail-switch or ruler jump now clears **18 / 24 m**, and the jump grid's rail stations rebuild
as `Rail_18m` / `Rail_24m`. The grind gear is no longer `sprint_speed`, so the "grind jump =
sprint rung" tie above is gone. The tables above keep the old numbers as history.

## Rail jump keeps its speed until the ground (amendment, 2026-09-24, from play)

User call: "when pilot jumps off a rail, i dont want him to lose any speed until he hits the
ground, then ease the speed out, and back to normal speed." This reverses the "drops the rail's
momentum" amendment above.

- **The jump.** `_take_rail_jump(launch)` launches at the ride's flat velocity plus the ordinary
  `jump_velocity` up. The stick bends the launch up to `rail_jump_max_bend` (45°), and the cap
  holds through the rise as in "Rail to rail". The rail-coyote jump launches along the end
  tangent at the speed he ran off at.
- **In the air, no speed is lost.** While `_rail_launch_carry` is set his flat speed is fixed at
  whatever the rail gave him. The stick steers the heading (inside the cap while rising, freely
  after the apex) but cannot brake it, and a released stick carries straight on. This holds for
  every exit that sets the carry: the jump, the rail coyote, running off the end and the crouch
  let-go. Before, a pushed stick on the end and crouch exits handed him to ordinary air control.
- **On landing, the speed eases out.** The first floor frame starts `rail_land_ease_time`
  (**0.5 s**): his flat speed goes from the landing speed to what the stick asks for now (run,
  sprint, walk, or 0 with the stick released) on a smoothstep. The stick steers throughout. The
  ease ends early if he leaves the ground (a jump, a ledge) or a slide, dash or rail takes his
  velocity. If he lands slower than the target, there is no ease and ordinary movement runs.
- **The jump grid's 18 / 24 m rail rulers describe a real jump again** (gear speed x 1.2 s,
  landing at take-off height).

### Amendment: speed, not momentum (2026-09-25, from play)

User call: "i like how he keeps his speed, but dont keep the momentum, i want the player to be able
to turn and move freely, while keeping the speed of the rail sprint / rail grind." The carry is now
a speed the stick spends, not a heading he is stuck on.

- **No 45° cap.** The jump leaves along the stick if it is pushed, along the rail if not, at full
  ride speed. `_rail_jump_cap` / `_hold_rail_jump_cap()` are deleted. `rail_jump_max_bend` stays:
  the rail switch still uses it.
- **In the air the stick drives him at the ride's speed (`_rail_launch_speed`) in any direction**,
  scaled by stick strength, from the first frame to landing. He can turn fully back.
- **A released stick keeps no momentum.** It falls through to the ordinary air brake, as in any
  other jump. Pushing again restores the full ride speed at once, because the speed is stored and
  is not read back from his velocity. This applies to every carry exit, including running off the
  end, so a hands-off run-off now drops short, which is the trade-off the 2026-09-24 carry was
  added to avoid.
- The landing ease is unchanged. It eases from whatever speed he lands with.
