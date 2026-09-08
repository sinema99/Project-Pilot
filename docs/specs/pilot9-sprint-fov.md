# Spec: pilot9's sprint FOV

> **Status:** built 2026-09-07. **Unplayed** - the feel is unjudged.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Touches:** `scripts/pilot9.gd` only. No rebuild, no bake, no animation change.

## Problem statement

pilot9 has three gaits - walk at 2.5 m/s, run at 5, sprint at 8 - and the camera reports
none of them. It sits at a fixed 3.5 m behind him with a fixed 75 degree FOV, so a sprint
looks like a run with the legs moving faster. The speed is in the numbers and in the clip
but not in the shot.

## The rule

**Sprinting adds 10 degrees to the camera's FOV. Everything else is the base FOV.**

- Enter the sprint gait and the view eases open to `base_fov + sprint_fov_boost`.
- Leave it - any way, any state - and it eases back to `base_fov`.
- The travel is a lerp at `fov_transition_speed`, not a snap. About half a second either way
  at the shipping 8.0, which is the same dial `camera_transition_speed` uses for the spring
  arm and reads the same in play.

## Where the base FOV comes from

**Read off the Camera3D at `_ready()`, not written here.** `base_fov` is whatever the rig's
camera is set to - 75 today, because `scenes/pilot9.tscn` leaves `fov` at Godot's default and
never writes it.

This matters more than it looks. The boost is applied by writing `camera_3d.fov` every frame,
so the camera's own inspector value would otherwise be clobbered the first frame the game
ran, silently, with no way to tell that the dial had stopped working. Capturing it once at
`_ready()` means tuning the camera in the editor still lands, and the boost rides on top of
whatever it is set to.

## What counts as sprinting, for the camera

The gate is `_apply_movement()`'s own sprint test with **the on-floor requirement dropped**,
plus the states that own the body outright:

```
sprint_toggled and stick pushed and not `walk` and not crouching
                and not sliding and not climbing and not frozen
```

`is_sprinting` itself is deliberately *not* what is read, and the difference is one term:
`is_sprinting` requires `is_on_floor()`. Reading it directly would drop the FOV the instant a
sprinting pilot9 left the ground and pop it back on touchdown - a dip and a lurch on every
jump taken at speed, which is exactly when the wide view is most wanted.

Carrying it through the air is the same call `_update_sprint_toggle()` already made for the
sprint itself: the run is not over because his feet are off the ground, and the toggle exists
so an accidental release mid-jump does not say otherwise. The camera follows the intent, not
the floor contact.

## The states that drop it

| State | FOV | Why |
|---|---|---|
| Walk (`walk` held) | base | It is the slowest gait. |
| Crouch / crouch-walk | base | Crouch outranks both gaits in `_apply_movement()` too. |
| Slide | base | See below. |
| Mantle (`is_climbing`) | base | The climb owns his position; the camera should be still for it. |
| `frozen` | base | Nothing is moving. |
| Stick released, sprint still toggled | base | `is_sprinting` needs the stick and so does this. |

**The slide is the one to watch in play.** It is entered at 8 m/s from a sprint and it hands
back to a sprint when it ends, so with the boost gated off for its duration the view sags
open-closed-open across roughly a second - visible, and arguably wrong for the fastest move
in the game. It is gated off anyway because the ask was *sprinting*, and this is a decision
better made with a controller in hand than in advance. Dropping `and not is_sliding` from the
gate is the entire change if the sag reads badly.

## Where it runs in the physics step

**First**, before `_handle_crouch_and_slide()` and before every early return in
`_physics_process()`.

That placement is the point. A mantle returns early and a freeze returns early, and those are
precisely the frames on which the FOV must still be easing back rather than stuck wide
wherever the sprint left it. Running first is the only spot that gets all three.

The cost is that the state it reads - `input_dir`, `is_crouching`, `is_sliding` - is one
physics frame old, since `_handle_movement_input()` has not run yet this step. That is 16 ms
of lag on a value that takes about 500 ms to travel, i.e. invisible, and it is the trade
taken knowingly. A test asserts the call sits above the early returns for this reason.

## The dials

| Export | Ships at | What it is |
|---|---|---|
| `sprint_fov_boost` | `10.0` | Degrees added at a sprint. `0.0` switches the feature off. |
| `fov_transition_speed` | `8.0` | Lerp rate, per second. Matches `camera_transition_speed`. |

Both live in the existing `Camera` export group beside the spring-arm dials.

## Decisions

| | Taken | Over |
|---|---|---|
| The boost | A flat +10 on the sprint flag | Scaling FOV with actual `velocity.length()`, which reports every bump, ledge and slide as a camera move and needs a deadband and a smoothing pass to stop breathing. The gaits are discrete; the camera can be too. |
| The base | Captured off the camera at `_ready()` | A `75.0` constant, which would silently overwrite the camera's own inspector value. |
| Airborne | Keeps the boost | Reading `is_sprinting` straight, which dips on every sprint jump. |
| Slide | Drops the boost | Keeping it. Literal reading of the ask; flagged above as the thing the play will judge. |
| Easing | `lerpf` at a rate, clamped | A snap (jarring), or a tween (a second object owning the same property as the frame loop). |

## Risks

1. **The slide sag.** Called out above. The one this play judges.
2. **A second writer of `camera_3d.fov`.** There is none today, but `scripts/mech.gd` lerps
   `fov` on its own handover camera, and a future handover that panned *through* pilot9's rig
   camera would fight this loop frame by frame. Nothing catches that but a play.
3. **A camera swapped into the rig with a different FOV.** `base_fov` is captured once at
   `_ready()`, so replacing the Camera3D at runtime would leave the old base behind. Not a
   thing that happens today.

## What this does not do

- **No FOV on anything but the sprint gait.** Not the slide, not the double jump, not the
  mantle.
- **No speed-proportional FOV.** See the decision table.
- **No change to the spring arm.** Distance is untouched; this is the lens only.
- **Nothing for Setsuna.** `scripts/player.gd` and the mech's camera are not touched.

## Test coverage

`tests/test_pilot9_sprint_fov.gd`:

- the base is read off the camera rather than declared, and the rig starts un-boosted
- a sprint converges on `base_fov + sprint_fov_boost`, and releasing it converges back
- the boost is the exported degrees, and `0.0` is a working off switch
- an airborne sprint keeps the wide view (the `is_on_floor()` seam)
- walk, crouch, slide, climb, freeze and a released stick each drop it
- the travel is eased, not snapped, and a long frame lands exactly on target rather than
  overshooting past it
- the call sits above every early return in `_physics_process()`
