# Spec: pilot9's camera sway and landing dip

> **Status:** specced and built 2026-09-26. **Played 2026-09-28 - feels good.** Every
> number below is still a dial.
> **Scene:** `scenes/pilot9.tscn`. **Touches:** `scripts/pilot9.gd`, `scripts/settings.gd`,
> `scripts/ui/tabs/tab_settings.gd`.

## The ask

"Some minor sway when sprinting, a small jerk when landing from a jump ... nothing over the top
jarring, just something to give the camera a little immersion." Agreed in a grilling session
the same day; every decision below is one the player made, with the reason it was offered.

## Scope

**In:** a sprint sway, a lighter run sway, and a landing dip.

**Out:** walk, crouch-walk, slide, idle breathing, wall-run footfalls, rail rumble, dash
impact, double-jump kick, mantle. The wall-run, rail and dash already have their own camera
handling (roll, swing, lag), and stacking sway on those is how this becomes over the top.

## The sway

**Translation first, a hint of roll, no pitch or yaw.** Rotating a third-person camera swings
the whole framing around him - a degree at 3.5 m moves him ~6 cm on screen - which is the
jarring version. Translating it bobs the world behind a steady character, like an operator
jogging alongside.

- **Where it lives:** `Camera3D.h_offset` / `v_offset`. They shift the view without touching
  the transform, so nothing that reads the camera's transform (the wall probe, the mech
  handover, the dash streak's projection) sees the sway. Nothing in pilot9 used them before.
- **Shape:** a figure-eight. Vertical at twice the lateral rate - one dip per footfall, one
  side-to-side per stride. Smooth sines, no `abs(sin)` cusp: the cusp reads as a knock on
  every step, which is the jarring version again.
- **Roll:** in phase with the lateral sway, ADDED to the wall-run roll. The wall-run roll's ease
  now runs on its own field (`_camera_wall_roll`) and `rotation.z` is written as that plus the
  sway, so the ease never starts from a value the sway has dirtied.

| Dial | Default | At |
|---|---|---|
| `camera_sway_vertical` | 0.0075 m | sprint, 3.5 m arm |
| `camera_sway_lateral` | 0.005 m | sprint, 3.5 m arm |
| `camera_sway_roll` | 0.2 deg | sprint |
| `camera_sway_run_fraction` | 0.4 | run, as a fraction of sprint |

### The rhythm

**Its own clock, not the feet.** Locomotion is the `SprintBlend` blend-space mixing run and
sprint clips of different lengths, so there is no one playhead to read a footfall off, and a
marker scheme would need redoing on every `PILOT9.glb` export. A 1-2 cm bob a few steps out of
phase with his feet is very hard to see.

The stride rate is measured off the clips (2026-09-26): `run_forward` 0.600 s,
`sprint_forward` 0.533 s, each one full stride of two footfalls. These are consts, not reads -
the tree plays them at their authored rate. The rate eases between the two with speed.

The clock runs through the air, so the phase does not jump on landing; only the amplitude
fades.

### When it is on

**On the floor, running or sprinting, sized by his actual horizontal speed** - not the stick,
so pushing into a wall at a standstill gets nothing.

- The weight is piecewise-linear in horizontal speed: 0 at `walk_speed` (2.5), the run
  fraction at `speed` (5.0), 1.0 at `sprint_speed` (7.5), clamped. A run gathering pace grows
  into the sway rather than switching it on.
- **Faded to zero** - over `camera_sway_fade_time` (0.2 s), never cut - while walking,
  crouched, sliding, airborne, wall-running, on or switching a rail, climbing, dashing, or
  frozen. EXIA stops pilot9's physics outright; leaving it resets the sway and dip to zero.

## The landing dip

**Pure vertical, down then back, scaled by how hard he hit.**

- **Size:** piecewise-linear in downward speed at impact, three anchors:
  - nothing below `landing_dip_min_speed` (5 m/s) - step-offs and small hops cost nothing;
  - `landing_dip_full_jump` (0.15 m) at a full jump's landing speed - `jump_velocity *
    sqrt(jump_fall_multiplier)`, derived, 10 m/s today;
  - `landing_dip_max` (0.3 m) at `max_fall_speed` (28 m/s), clamped above.
- **Shape:** a critically damped spring. The landing adds a downward kick to the spring's
  velocity; it bottoms out `landing_dip_time` (0.1 s) later, is three-quarters back by
  0.3 s and gone by 0.5 s, with no rebound above rest. The kick is sized so the bottom is exactly the depth
  above.
- **Back-to-back landings add**, they do not restart. A second touchdown mid-recovery adds its
  kick to whatever the spring is doing, so there is no curve to pop back to the start of.
- It runs independently of the sway; the two add.

### What counts as a landing

| Touchdown | Dip? |
|---|---|
| Plain jump / fall onto floor | Yes |
| Landing into a land-slide | Yes |
| Rail jump landing on the floor | Yes |
| Wall-run dropping to the floor | Yes (scaled - a short drop costs nothing) |
| Catching a rail mid-air | No - not a floor, and the rail has its own camera |
| Finishing a ledge mantle | No |
| Touching a bounce pad | No |
| Exiting EXIA / respawn / teleport | No |

How the code gets there:

- **The impact speed** is his downward speed taken just before `move_and_slide()`, which is
  what zeroes it on contact. Only the ordinary movement branch records one; a rail ride, a
  switch, the mantle and `frozen` record zero. A mantle also ends with velocity zeroed, so the
  step onto the ledge measures nothing.
- **Touchdown** is `is_on_floor()` going false to true across `move_and_slide()`.
- **The kick lands one physics frame late, and only if he is not rising by then.** The bounce
  pad launches from its Area3D's `body_entered`, which Godot fires after the frame's
  `move_and_slide()` - so a hard fall can touch the pad's top on the same step. Checking at
  the top of the next frame sees the pad's `velocity.y` and drops the dip. 16 ms of delay on an
  80 ms dip is not visible. A jump pressed on landing is spent in the next frame's jump code,
  AFTER this check, so a bunny-hop still gets its dip - it was a landing.
- **EXIA exit** zeroes the pending kick, the spring and the floor memory.

## Zoom

**Every amplitude - sway and dip - is scaled by the live `spring_length` over
`camera_distance` (3.5 m).** Translation shrinks on screen with distance: 1.5 cm at 3.5 m is
about 0.3% of screen height, half that at 8 m, over double at 1.5 m. Scaling by the arm keeps
it the same size at every zoom, and because it reads the live arm, a wall squeezing the camera
in also shrinks the motion rather than letting it loom. First person (arm length 0) gets none,
for free.

The roll is an angle, so it is not scaled.

## The setting

**CONTROLS > CAMERA MOTION, ON / OFF, default ON.** A toggle, not a slider - the player's
call. It covers the sway and the dip only. The sprint FOV widen, the wall-run roll and the dash
lag predate it and have their own switches.

OFF is completely still: the offsets and the sway roll go to zero at once and landings are not
recorded. Read live off `Settings.camera_motion` every frame, per the settings spec's "anything
added here later must read live" rule.

## Not tested headlessly

- **The feel.** Played 2026-09-28 - feels good; every dial above stays tunable.
- **Phase against the feet.** The clock is free-running by design.
- **The one-frame delay** reads fine on paper and has not been watched.
- The weight curve, the dip curve, the spring (bottom time, depth, no rebound, adding kicks),
  the zoom scale, the bounce-pad cancel, the OFF switch and the EXIA reset are asserted in
  `tests/test_pilot9_camera_sway.gd`.

## Retune after first play (2026-09-26)

- **Sway halved.** "A little too much": vertical 0.015 → 0.0075 m, lateral 0.010 → 0.005 m,
  roll 0.4 → 0.2 deg. The run fraction is unchanged, so the run sway halved with it.
- **Dip deepened.** Reported as "not working". A headless drop showed it firing correctly, but
  it bottomed out at about 5 cm with the camera 3.5 m back, which cannot be seen. Full jump
  0.04 → 0.15 m, cap 0.08 → 0.3 m, time to bottom 0.08 → 0.1 s so the deeper travel does not
  snap. The dial ranges went up to 0.6 m to leave room.
