# Spec: pilot9's camera and walls

> **Status:** built 2026-09-10. **Unplayed** - the feel is unjudged.
> **Scene:** `scenes/pilot9.tscn`. **Touches:** `scripts/pilot9.gd` only.
> No rebuild, no bake, no animation change. The SpringArm3D is configured from
> `_ready()` rather than the scene file, so a rebuild of pilot9.tscn cannot lose it.

## Problem statement

pilot9's camera already refuses to go through walls, and it does it badly. The
SpringArm3D under `CameraPivot` carries **no shape and no exclusions** - just
`spring_length = 3.5` - so all it has ever done is fire a single hairline ray from
his head to the lens and drop the camera onto whatever that one ray hit. Three
separate glitches fall out of that:

1. **Corner poke.** A ray is infinitely thin and the camera is not. Anything the ray
   passes beside - a pillar's edge, a doorframe, the lip of a platform - is geometry
   the near plane still slices into. You see through the world for a frame or two.
2. **The pop.** The arm's clamp is instantaneous in both directions. Walk past a
   column and the camera slams from 3.5 m to 0.6 m and back out to 3.5 m in single
   frames. Nothing in the shot is travelling; it is teleporting.
3. **The flicker.** At a grazing angle the ray hits and misses on alternating frames,
   so the camera oscillates between the two lengths at 60 Hz. This is the one that
   reads as "broken" rather than "abrupt".

## The rule

**The camera flies inside a sphere. When that sphere gets near a wall, the arm
shortens - quickly - and when the wall clears, it lengthens back slowly.**

Three parts, and each one kills one of the three glitches above:

| Part | Value | Kills |
|---|---|---|
| The arm sweeps a `SphereShape3D` instead of a ray | `camera_clearance` = 0.3 m | corner poke |
| A **fatter** probe sphere of our own trips first and drives a damped length | `+ camera_probe_lead` = 0.35 m | the pop |
| Retract fast, return slow | 16.0 / s in, 3.0 / s out | the flicker |

## Why two spheres

The SpringArm3D's own clamp cannot be smoothed - the node writes the child's
position itself, every frame, at exactly `min(spring_length, hit)`. Damping the
number we hand it does nothing if the arm's own cast is what is doing the clamping.

So the two spheres have two different jobs:

- **The probe (0.65 m radius, ours, cast in `_camera_obstruction_length()`)** is
  fatter, so it trips **earlier** - `camera_probe_lead` of travel before the wall is
  anywhere near the clearance sphere. That lead is the room the damping needs. It is
  what turns a snap into a zoom.
- **The arm's shape (0.3 m radius, the engine's)** never normally fires at all,
  because the probe has already pulled the length in. It only fires when the damping
  is behind - a wall arriving faster than 16 / s can answer for. That is a backstop,
  not the mechanism, and the day it fires is a day the alternative was a clipped lens.

Which is also why `camera_min_distance` (0.8 m) is a floor on **our** number and not
a guarantee about the camera. The arm may still take it under 0.8 in a corner. That
is the safety net working, not a bug.

## Why asymmetric speeds

`_camera_length_step()` picks `camera_retract_speed` when the desired length is
shorter than the current one and `camera_return_speed` when it is longer. The 5:1
split between them is the whole anti-flicker property:

- Toward the wall the camera must win the race, so it moves at 16 / s - about three
  frames to close most of the gap.
- Away from it there is nothing to be right about quickly, so it takes 3 / s -
  roughly a third of a second, slow enough to read as a camera decision.
- An intermittent hit at a grazing edge therefore settles **in**, not in the middle:
  each hit pulls hard, each gap drifts out gently, and the drift never gets far
  enough to matter before the next hit. The 60 Hz oscillation has nowhere to live.

Both rates are a rate times a frame, clamped into `[0, 1]` before they reach
`lerpf()` - the same guard `_handle_camera_fov()` documents, and for the same reason:
a long frame would otherwise overshoot the target instead of arriving at it.

## Excluding himself

`spring_arm.add_excluded_object(get_rid())`, and the same RID on the probe's
`exclude`. This is not housekeeping - it is load-bearing the moment the arm gains a
shape.

`CameraPivot` sits at y = 1.5 and his capsule spans 0 to 1.955, so **the arm starts
inside pilot9's own collider**. A ray survived that only because Godot's ray queries
do not hit from inside by default. A sphere cast does: without the exclusion the
probe would report a hit at zero travel on every single frame and weld the camera to
the back of his head.

## What walls must never do

**Make pilot9 disappear.** The mesh's visibility used to key off `spring_length`,
which was fine while nothing but the mode switch ever wrote it. Now that walls write
it, the old rule would blink his body out whenever a wall squeezed the camera under
30% of `camera_distance` - a new glitch traded for an old one.

So the two lengths are now separate values:

- `_camera_mode_length` - what the FIRST_PERSON / THIRD_PERSON transition wants,
  walls not consulted. **This is what the mesh's visibility reads.**
- `spring_arm.spring_length` - that length after the walls have had their say.

First person short-circuits the probe entirely: a mode length of 0 has nothing to
collide with.

## The dials

| Export | Ships at | What moving it does |
|---|---|---|
| `camera_clearance` | 0.3 m | The backstop sphere's radius. Bigger = the lens keeps more air, at the cost of retracting in more places. |
| `camera_probe_lead` | 0.35 m | How early the zoom starts. This is the pop dial: 0 hands the job back to the arm and the snap returns. |
| `camera_retract_speed` | 16.0 / s | How hard it pulls in. Too low and the backstop starts firing; too high and it is a snap again. |
| `camera_return_speed` | 3.0 / s | How lazily it comes back out. Raise it and the flicker starts to reappear. |
| `camera_min_distance` | 0.8 m | How close the damped length may get before it stops. The arm can still go under it. |

## What is not in this

- **The mech.** `scenes/mech.tscn` already sweeps a sphere with a 0.2 margin and
  excludes itself, so it never had glitches 1 or 3. Its pop is untouched here.
- **Camera-relative movement.** `_movement_basis()` reads `camera_pivot.rotation.y`,
  which the arm's length does not touch. A retraction cannot change where W goes.
- **Whipping the camera round obstacles.** No lateral avoidance, no yaw nudging. The
  arm shortens along its own axis and nothing else.

## Test

`tests/test_pilot9_camera_collision.gd`. The damping curve is a static function and
is asserted directly; the wiring - shape, radius, exclusion, the two lengths kept
apart - is asserted on a rig in the tree. The cast itself is left to play: headless
physics has no walls to hit.
