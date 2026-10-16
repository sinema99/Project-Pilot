# Spec: pilot9's body lean - turn roll and speed pitch

> **Status:** grilled and specced 2026-10-05. Built 2026-10-06 - see "Built" at the end. Not yet played.
> **Scene:** `scenes/pilot9.tscn`. **Touches:** `scripts/pilot9.gd` only. No rebuild, no bake,
> no animation change, no new setting row.

## The ask

"Some tilt into pilot when he's moving around. Nothing crazy but some slight tilt when he turns
left and right and stuff. It'll give him a little more weight and look better."

## The rule

**On the ground, walking, running or sprinting, the mesh rolls into turns and pitches with
changes of speed - forward when he speeds up, back when he slows down - on top of the slope
tilt.** Movement itself is untouched; only the `character` mesh leans, never the capsule.

- **Roll** follows sideways acceleration: horizontal speed x the mesh's yaw rate. A turn on the
  spot leans nothing; a sprint carve leans hard.
- **Pitch** follows the gap between his real speed and a lagging "felt" speed. It decays on its
  own as the felt speed catches up, so it is a lean *into a change*, never a held pose.
- **No overshoot, no spring.** Considered (option C at the grill) and left out: easy to overdo,
  and the ask was "nothing crazy". Can be added later as one dial if it plays floaty.

## Where it applies

| State | Lean |
|---|---|
| Walk / run / sprint on the floor | **Yes** |
| Crouch-walk | No |
| Slide | No - its own steering and clip; a roll fights the low pose |
| Dash | No - the afterimages are its read |
| Air (jump, fall, double jump) | No - levels out as today; a bank is the feet gripping, and there are none |
| Wall-run, rail, rail switch, mantle, vault | No - each keeps its own tilt, unchanged |
| Frozen | No |
| First person | No - nothing is drawing the mesh's lean |

The gate is one predicate, `_body_lean_active()`: `is_on_floor()` and third person and none of
`is_crouching`, `is_sliding`, `is_dashing`, `is_climbing`, `is_vaulting`, `is_wall_running`,
`is_rail_grinding`, `is_rail_switching`, `frozen`. Outside it the lean target is zero and the
existing ease brings him level.

## Why it is shaped like this: movement is instant

Ground movement is snappy on purpose (the 2026-09-10 control-over-fidelity call):
`_apply_movement()` sets `velocity = direction * current_speed` in one frame, and releasing the
stick zeroes it in one frame. Velocity also snaps straight to the stick's direction. Two
consequences decided the design:

1. **The turn rate comes from the mesh, not the velocity.** `velocity` has no turn rate - it
   jumps. The mesh yaw is the one thing that turns smoothly (`lerp_angle` at `rotation_speed`
   in `_handle_character_rotation()`), so the roll reads the frame-to-frame change in
   `character.rotation.y`.
2. **The acceleration is a one-frame spike.** 0 -> 5 m/s in a frame. Feeding that to pitch would
   twitch for one frame. Hence the felt speed, which turns the spike into a decaying gap.

## Roll

```
yaw_rate   = wrapf(character.rotation.y - _lean_last_yaw, -PI, PI) / delta     # rad/s, + = turning left
lateral    = horizontal_speed * yaw_rate                                        # m/s^2
roll       = -clamp(lateral / body_lean_roll_full_accel, -1, 1) * deg_to_rad(body_lean_roll_max)
```

- **Full roll, 8 deg, at 23.5 m/s^2** - a sprint (7.5 m/s) carving at about 180 deg/s of facing.
  A run (5 m/s) gets a proportional share, a walk barely shows.
- **Sign.** The mesh faces local +Z, so his left is +X and a positive yaw step turns him left.
  Leaning *into* a left turn puts his head toward +X, which is **negative** `rotation.z` -
  the same convention `_slope_align_angles()` and `_rail_lean_roll()` already document. Hence
  the minus. A flipped sign leans him *out* of turns, which reads as being flung; the test
  pins it.
- **A stick flick** spikes the yaw rate (the lerp is fastest at its start) and saturates the
  roll at the cap for a few frames, then lets it go as the facing converges. That is the
  intended read of a planted pivot. A 180 deg reversal at sprint does the same.
- **Horizontal speed is the post-`move_and_slide()` velocity**, which `_align_model_to_slope()`
  already runs after. Running into a wall reads as stopped, so it does not lean.

## Pitch

```
_felt_speed += (speed - _felt_speed) * (1 - exp(-delta / body_lean_felt_lag))  # every frame, every state
gap         = speed - _felt_speed                                                # + speeding up
pitch       = +deg_to_rad(pitch_forward_max) * gain(gap / pitch_full_gap)  if gap > 0
              -deg_to_rad(pitch_back_max)    * gain(-gap / pitch_full_gap) if gap < 0
```

- **Positive `rotation.x` tips his head forward** (toward local +Z), the same sign the slope
  tilt uses for a downhill grade.
- **Full forward pitch, 6 deg, from a standing start into a sprint** (gap 7.5 m/s =
  `body_lean_pitch_full_gap`). 0 -> run is a 5 m/s step and peaks at about 4 deg.
- **Full back pitch, 4 deg, on a dead stop from a sprint.** Smaller than forward on purpose -
  a big rear lean reads as tripping.
- **The felt speed tracks in every state, air included,** even though the lean only shows on
  the ground. Otherwise a landing would compare his ground speed against a felt speed frozen
  at takeoff and kick for no reason. Landing into a run at the speed he had in the air leans
  nothing; landing into a stop rocks him back, which is right.
- **Frame-rate independent** - `exp()`, not a lerp at a rate.

### The caps are the visible peak, not the target

The pitch target is then eased by the existing `slope_align_speed` lerp, so a step in speed
passes through two lags: the felt speed (tau = 0.25 s) and the ease (tau ~ 1 / 10 s). Their
combined step response only peaks at **about 54%** of the target. Left alone, "6 deg" would show
as about 3 deg.

So the pitch target is divided by that peak fraction, computed from the two time constants:

```
t1 = body_lean_felt_lag,  t2 = 1 / slope_align_speed
t_peak = ln(t1 / t2) * t1 * t2 / (t1 - t2)
f      = t1 / (t1 - t2) * (exp(-t_peak / t1) - exp(-t_peak / t2))      # f = 1/e when t1 == t2
```

`gain(x) = clamp(x, 0, 1) / f`. A full step then **peaks** at the cap on the mesh. Retuning
either lag keeps the caps honest. `_body_lean_peak_fraction(t1, t2)` is a pure static
function and is tested on its own.

Roll needs none of this: a sustained carve holds its target long enough for the ease to reach
it, and a flick saturates at the cap anyway.

## How it fits into the existing tilt

Inside `_align_model_to_slope()`, and nowhere else. On the floor branch the target becomes:

```
target = _slope_align_angles(...) + _body_lean_target(delta)      # pitch in .x, roll in .y
```

and the existing `lerp_angle` at `slope_align_speed` eases `character.rotation` toward it,
exactly as today. That is the whole integration - **the slope tilt's ownership of
`character.rotation.x/z` is not restructured**, so:

- the three places that snap him level (mantle start, wall-run attach, vehicle exit) still
  work unchanged, and the lean simply eases back on from level after them;
- the other branches (wall-run, rail, air) never see the lean.

`_body_lean_target(delta)` runs **every frame, whatever the state**, because the yaw and felt
speed trackers have to stay current. It returns zero outside `_body_lean_active()`.

### Trackers reseeded where he is placed

A teleport or a welded snap moves the yaw (or speed) in one frame, which the trackers would read
as a violent turn. At the places that already snap his tilt level - and at respawn - set
`_lean_last_yaw = character.rotation.y` and `_felt_speed = _horizontal_speed()`. The cap would
bound the damage anyway (an eased 8 deg blip at most); reseeding removes it.

## The dials

All in a new **Body Lean** export group, next to the slope tilt exports.

| Export | Starts at | What it is |
|---|---|---|
| `body_lean_roll_max` | `8.0` | Degrees of roll at full. `0` turns the roll off. |
| `body_lean_roll_full_accel` | `23.5` | m/s^2 of sideways acceleration that earns the full roll. Lower = leans harder at a walk. |
| `body_lean_pitch_forward_max` | `6.0` | Degrees forward at the peak of a full speed-up. `0` turns it off. |
| `body_lean_pitch_back_max` | `4.0` | Degrees back at the peak of a full stop. `0` turns it off. |
| `body_lean_pitch_full_gap` | `7.5` | m/s of speed change that earns the full pitch (= `sprint_speed`). |
| `body_lean_felt_lag` | `0.25` | Seconds the felt speed lags behind - how long a pitch lingers. |

No settings row - it is body animation, like the slope tilt and the rail lean, not a comfort
issue like the camera motion.

## Decisions

| | Taken | Over |
|---|---|---|
| Scope of motion | Roll into turns + pitch on speed change | Roll only (looks like a lean clip, not weight); + overshoot spring (easy to overdo). |
| States | Ground walk / run / sprint only | + air (a bank with no feet planted reads wrong); + slide and crouch. |
| Roll source | Speed x mesh yaw rate | Yaw rate alone (a standing 180 would lean hard); stick vs facing (leans into walls). |
| Pitch source | Felt-speed lag | Event kicks (misses cases); hold-while-sprinting (a pose, not weight). |
| Sizes | 8 deg roll, 6 deg forward, 4 deg back, as visible peaks | Larger - "nothing crazy". |
| Toggle | None | Its own row; folding into CAMERA MOTION (which is the camera, not the body). |
| Integration | Added to the slope tilt's target, through its ease | A separately-owned lean layer, which would mean rewriting three level-snaps. |

## Risks to watch on the play

1. **Pitch reads as nodding on stop-start tapping.** Each tap is a full step. If it bobs,
   lengthen `body_lean_felt_lag` (gentler, longer) or drop `body_lean_pitch_back_max`.
2. **Sprint clip already leans forward.** The forward pitch only shows during the speed-up, so
   it should not stack into a held over-lean - but the first second of a sprint will be the
   most forward he ever looks.
3. **Roll on a stick flick saturates.** Every hard flick hits the full 8 deg for a beat. If
   flicks look jerky, raise `body_lean_roll_full_accel` (it only affects how easily the cap is
   reached).
4. **The staff on his back and the slide-hand / held-item arm overrides** are skeleton-side and
   ride the mesh rotation for free; nothing to do, but worth a glance.
5. **The outline.** A few degrees of roll should not show seams, but the cel outline is the
   first thing to look at if the silhouette looks wrong mid-carve.

## What this does not do

- **No change to movement:** speed, acceleration, turn rate and collision are all untouched.
- **No camera roll.** The camera does not lean with him.
- **No change to the wall-run, rail, slope or mantle tilts.**
- **No new animation clips, no Blender pass.**
- **Nothing for Setsuna or the mech.**

## Test coverage

`tests/test_pilot9_body_lean.gd`:

- **Peak fraction:** `_body_lean_peak_fraction(0.25, 0.1)` is about 0.54; equal time constants
  give 1/e; and simulating a full step through felt lag + the 60 Hz ease peaks within 10% of the
  cap for both forward and back.
- **Roll sign:** on the rig, a sprinting left turn gives negative `rotation.z` (head left) and a
  right turn positive.
- **Roll scale:** a turn on the spot (speed 0) gives no roll; the same yaw rate at a walk
  gives less than at a sprint; a sustained carve at 180 deg/s at sprint settles at about 8 deg.
- **Pitch:** standing -> sprint tips forward then returns to level within about a second;
  sprint -> stop tips back and returns; a held sprint at constant speed holds no pitch.
- **Gate:** crouch-walk, slide, dash, air, wall-run and rail give no lean term.
- **Felt speed tracks in the air:** a jump and a landing at the same horizontal speed gives no
  pitch kick.
- **Off switches:** each `_max = 0` zeroes its part alone.
- **Reseed:** a yaw snap at a reseed site gives no roll spike.
- `tests/test_pilot9_slope_align.gd` and `tests/test_pilot9_mech.gd` pass **unedited** - the
  regression check for the shared ease.

## Built (2026-10-06)

As specced, with these departures:

- **`on_floor` is a parameter** on `_body_lean_active()` and `_body_lean_target()`;
  `_align_model_to_slope()` passes `is_on_floor()`. A headless test cannot make the floor true,
  so this is the seam the tests drive.
- **Reseed sites are the three level-snaps that exist:** mantle start, vault start and vehicle
  exit (the spec named a wall-run attach snap, but the wall-run does not snap level, and the
  lean is gated off during a run anyway), plus `_ready()`. **pilot9 has no respawn function**,
  so there is nothing to reseed there. Any yaw snap inside a gated state is absorbed because
  the trackers update every frame.
- **The felt-speed test runs two seconds, not one.** After one second of tau = 0.25 s, the gap
  is still 0.14 m/s, which is about 0.2 deg of pitch. That is invisible, but it is over the 0.1 deg
  tolerance.

`tests/test_pilot9_body_lean.gd` has 17 tests and they all pass. `test_pilot9_slope_align.gd` and
`test_pilot9_mech.gd` pass unedited. The only other suite failure is the existing
`habitat: no generated child has an owner`.
