# Spec: EXIA's sprint - Titanfall titan run (grounded since 2026-10-12)

> **2026-10-27: superseded** by `docs/specs/exia-movement.md`, which rebuilt the sprint and a new
> 9 m/s run as one gait family. `scripts/mech_sprint.gd` is now `scripts/mech_gait.gd`, the tests are
> `tests/test_mech_gait.gd`, the probe `tests/_probe_mech_moves.gd`. The rig measurements and the
> history below still hold; the movement, brake, walk and camera numbers do not.

> **Status:** grilled and specced 2026-10-06; built 2026-10-06. **Gait redone 2026-10-12** as a grounded
> titan run - see "Redo 2026-10-12" at the end, which overrides the gait sections. Not yet played.
> **Scene:** `scenes/mech.tscn` (instanced as `EXIA` in `test_platform.tscn` / `trial.tscn`).
> **Touches:** `scripts/mech.gd`, new `scripts/mech_sprint.gd` (the clip, built in code), new
> `tests/test_mech_sprint.gd`, new `tests/_probe_mech_sprint.gd`. `assets/Mech_V1.glb` is NOT
> touched. No new setting row.

## The ask

"How well could you animate the mech, like a run cycle." Then, through the grill: a sprint on
top of the walk, as a toggle, that runs "like Titanfall mechs... almost like bounding jumps",
at 20 m/s, with the arms swinging - "replicate a Titanfall titan run animation".

## Decisions (from the grill)

| # | Decision |
|---|---|
| 1 | A **sprint tier on top of the walk**, toggled on the `sprint` action (Shift / right trigger). |
| 2 | **20 m/s.** |
| 3 | **10 m bounds** - 2 steps/s, **1.0 s cycle**, about half of each step airborne. |
| 4 | **The bounce is in the clip only** - the body stays on the floor. The camera gets a damped share of the hip bounce plus a dip and shake on every footfall. |
| 5 | **Full opposing arm swing**, Titanfall titan sprint: heavy forward lean, deep knee bend at each plant, steady head. |
| 6 | **Built from memory** (no reference frames available). The user corrects it pose by pose from probe screenshots. |
| 7 | **7 -> 20 m/s in 0.5 s**, the walk crossfading into the sprint over that bound. Sprint from a standstill allowed (walk start, then the ramp). |
| 8 | **0.25 s brake** on release (~2.5 m slide), crossfading to standing. Sprint off while moving eases back to 7 m/s in the same 0.25 s. No skid clip. |
| 9 | **Turn rate ~4 while sprinting** (~12 m circle) and **up to ~12 deg bank** - a model tilt, not part of the clip. |
| 10 | **Sprint FOV widen**, **footfall dust** (behind MOVEMENT EFFECTS), and the camera bounce/dip/shake **off with CAMERA MOTION**. |

Out of scope: sound, ground cracks/decals, a skid-stop clip, the turning clips, gamepad stick
movement for the mech (it reads raw WASD today and keeps doing so).

## The rig, measured 2026-10-06

From `MECH_standing`, skeleton global poses, in metres (the 1.7267632 armature scale is already
in these numbers). Model space: nose +Z, left +X.

| Joint | Height | Note |
|---|---|---|
| `thigh.L` head (hip) | 4.50 m | x = +/-1.17 |
| `shin.L` head (knee) | 3.25 m | knee sits 1.5 m ahead of the hip line |
| `foot.L` head (ankle) | 1.73 m | |
| `toe.L` head | 0.72 m | the "foot" bone is near-vertical: EXIA stands up on its toes |
| `toe.L.001` head | 0.07 m | the sole contact point |

Thigh 2.01 m, shin 2.11 m, foot 1.03 m, toe 0.67 m. Hip-to-sole chain ~5.8 m.

**Weighted (visible) bones:** `spine`, `spine.001`, `spine.003`, `thigh/shin/foot/toe.001 .L/.R`,
`upper_arm/forearm/hand .L/.R`. `shoulder.*` and `toe.L/.R` are unweighted parents.
**Unparented, unweighted** (Rigify IK leftovers that the clips key anyway): `hand.L.001`,
`hand.R.001`, `spine.002`, `toe.L.002`, `toe.R.002`. The sprint clip holds these at their
`MECH_standing` values so it owns the whole skeleton.

**The +90 deg armature yaw and the 1.7268 scale** sit on the `metarig_001` node (see
`mech-v1-reimport-workflow` memory and `Model`'s counter-rotation). The clip is authored in model
space and converted per bone, so both are absorbed and a re-export that fixes the yaw needs no
change here.

## The gait

### Timing

One cycle = 1.0 s = two bounds. Left contact at t = 0.00, right contact at t = 0.50; the right
leg is the left leg shifted half a cycle and mirrored in X.

| t (L side) | Pose | Hip height | Planted foot |
|---|---|---|---|
| 0.000 | **Contact** - L toe lands 2.5 m ahead of the hip, knee nearly straight | 4.30 m, falling | L |
| 0.125 | **Down** - lowest point, L knee deepest, R thigh passing under | **4.00 m** | L |
| 0.250 | **Toe-off** - L toe 2.5 m behind the hip, leg extended | 4.30 m, rising | L |
| 0.375 | **Up** - apex, both feet clear, R knee driving high, L heel kicked up behind | **4.60 m** | none |
| 0.500 | R contact - mirror of 0.000 | | R |

Ground contact 0.25 s per foot, flight 0.25 s per bound.

**The bob is stylised, not physical.** At real gravity 0.25 s of flight lifts the hips 8 cm; the
grill asked for a visible bound, so the hip travels **0.6 m** (4.00 - 4.60). It is a curve on the
`spine` position track, smooth (Catmull-Rom through the four heights above).

### No foot slide (the one hard constraint)

The clip runs in place; the body supplies the 20 m/s. So **while a foot is planted, its
`toe.*.001` must move backward in model space at exactly 20 m/s** - 5.0 m over the 0.25 s
contact, from +2.5 m to -2.5 m relative to the hip. That is what makes the mech look planted
rather than skating.

Keying the legs by hand cannot hit that. **The legs are solved, not keyed:**

- Per key, the build places an **ankle target** - on the floor path above during contact, on an
  authored swing arc during flight (peak sole height ~1.6 m, heel kicked up behind at toe-off,
  knee driving forward to a high thigh at the apex).
- `thigh` + `shin` are a two-bone analytic solve from the hip to that ankle, knee hinged about
  the model's lateral (X) axis, bending forward like the rest pose.
- `foot` and `toe` angles are authored per pose (flat-ish on contact, rolling onto the toe tip
  through toe-off, curled back in the swing) and the ankle target is offset so the **toe tip**,
  not the ankle, is what sits on the floor path.
- At contact and toe-off the leg is near full reach (hip 4.30 m, toe 2.5 m out against a ~5.8 m
  chain). If the solve ever asks for more than the chain, the hip drops to fit, never the foot.

### Pelvis and spine

- **Forward lean 15 deg** at the `spine` bone, +/-3 deg pitch with the bob (deeper at down).
- **Hip yaw +/-8 deg** toward the reaching leg (L hip forward at L contact).
- **Hip roll +/-5 deg**, the free side dropping through the down pose.
- **`spine.001` counter-twists** the hips: +/-12 deg yaw opposite the hip yaw, so the shoulders
  rock against the pelvis on every plant. This and the arm swing are where the "titan" read lives.
- **`spine.003` (the cockpit/head) cancels half** the lean and twist below it - the steady-head
  read, and it keeps the canopy from nodding at 2 Hz. (It is the bone `seat_follow` rides, but
  only during the launch; the sprint never runs while she is riding it.)

### Arms

Full opposing swing, peaking at contact: at L contact the **R arm is forward, L arm back**.

| | Forward peak | Back peak |
|---|---|---|
| `upper_arm` pitch (about lateral) | +45 deg | -35 deg |
| `forearm` bend | 100 deg (fist near chest height) | 60 deg |
| `upper_arm` adduction | 10 deg inward (fist crosses toward the centreline) | 0 |

- Swing follows the hip yaw's phase but **lags it by 2 frames** (~0.067 s) - the cheapest overlap
  there is, and the arms are where missing overlap shows most.
- The forearm bend overshoots 5 deg at each peak and settles over 3 frames.
- `hand` holds its standing rotation plus 10 deg of extra curl at the forward peak.

**All numbers in this section are starting values** - they are the from-memory guess decision 6
accepts, and are what the user's pose-by-pose notes will move. They are consts at the top of
`mech_sprint.gd`, grouped by bone, named for the pose they set.

## The clip: built in code

`scripts/mech_sprint.gd`, `class_name MechSprint`:

```gdscript
static func build(skeleton: Skeleton3D, standing: Animation) -> Animation
```

- Called from `mech.gd::_ready()`. The result is added to the AnimationPlayer's default library
  as **`MECH_sprint`**, `LOOP_LINEAR`, length 1.0, **31 keys** per track (30 fps, last = first).
- **Base pose is `MECH_standing`, not the bone rest** - the rig's rest is not guaranteed to equal
  its bind pose (the scarf lesson), and standing is what every other clip chains from.
- Rotations are authored as angles about model-space axes, then converted to bone-local:
  `local = parent_global^-1 * R_model * global_standing`, walking down each chain. Position is
  keyed on `spine` only, and **only its Y moves** - X/Z stay at the standing anchor, so even if the
  clip were ever added to the root-motion list it would split out zero travel.
- Built every boot instead of baked to a `.res`: ~20 tracks x 31 keys is trivial, a re-export of
  `Mech_V1.glb` cannot strand a stale bake, and the tests call `build()` directly.
- `MECH_sprint` is **not** added to `_split_travel_out_of_the_clips()`'s list.

## Movement (`mech.gd`)

### The toggle

`sprint_toggled: bool`, same rules as pilot9's `_update_sprint_toggle()`:

- `sprint` just pressed -> flip. `walk` just pressed -> clear.
- **Cleared on a complete stop**: on the floor, horizontal speed < 0.1 m/s, no WASD held. Edge-
  triggered like pilot9's `_sprint_stop_armed`, so a press made while standing still is kept.
- Only read while piloted and driving (not during climb, descent, launch or handover). Cleared
  when the pilot gets out.
- The mech's own input is raw WASD; the toggle uses the `sprint` / `walk` input actions.

### Speeds

```
SPRINT_SPEED      = 20.0   # m/s
SPRINT_RAMP_TIME  = 0.5    # 7 -> 20
SPRINT_BRAKE_TIME = 0.25   # 20 -> 0 on release, and 20 -> 7 on sprint off
```

The existing loop already ramps a speed magnitude along the nose (`move_toward(speed, SPEED,
acceleration * delta)`); it gains a target and a rate:

| State | Target | Rate |
|---|---|---|
| Moving, not sprinting, speed <= 7 | `SPEED` 7 | as today (walk-start ramp) |
| Moving, sprinting | 20 | (20 - 7) / 0.5 = 26 m/s^2 - but only once the walk start has finished, so a standing sprint is walk start (0 -> 7, 1.0 s) then the ramp |
| Moving, not sprinting, speed > 7 | 7 | (20 - 7) / 0.25 = 52 m/s^2 |
| No input, speed > 7 | 0 | 20 / 0.25 = 80 m/s^2 |
| No input, speed <= 7 | 0 | instant, as today |

The instant walk stop stays (the "a mech that coasts walks off ledges" rule); only speed above
the walk brakes.

### Turning

`ROTATE_SPEED_SPRINT = 4.0`, used instead of `ROTATE_SPEED` (10) while speed > 7. Blended by
speed between 7 and 20 so the turn rate does not step on the frame the sprint starts. Velocity
still follows the nose exactly (unchanged - that is what stops the mech sliding).

### Banking

A roll on the **`Model` node about the mech's forward axis, pivoting at the feet**, on top of its
authored transform (which carries the -90 deg yaw compensation - the bank composes with it, never
replaces it: `Model.transform = Transform3D(Basis(Vector3.FORWARD_OF_MECH, roll)) * _model_rest`).

```
yaw_rate = wrapf(rotation.y - _last_yaw, -PI, PI) / delta
lateral  = horizontal_speed * yaw_rate
target   = -clamp(lateral / BANK_FULL_ACCEL, -1, 1) * deg_to_rad(BANK_MAX_DEG)
roll     = lerp toward target, BANK_EASE per second
```

- `BANK_MAX_DEG = 12`, `BANK_FULL_ACCEL = 33` (20 m/s on a 12 m circle), `BANK_EASE = 8`.
- Leans **into** the turn. Sign pinned by a test, same convention pilot9's body lean documents.
- Applies at any speed (a walk turn reads near zero by the formula); zero target when not
  driving or not on the floor.
- The collider never tilts.

## Animation (`mech.gd`)

`clip_for()` gains the sprint:

- Speed > 7 and moving -> `MECH_sprint`.
- Sprint started from the walk loop: crossfade **0.5 s** (the ramp), **phase-matched** - the
  sprint starts at the time whose planted foot matches the walk's next contact. The walk's
  left-contact time is measured from `MECH_walk` once at boot (lowest `toe.L.001`), not
  hard-coded, so a re-export retunes it.
- Sprint -> walk (toggle off): 0.25 s crossfade, phase-matched the same way.
- Sprint -> stop: 0.25 s crossfade into `MECH_standing`.
- `_play_chain()` gains a blend argument; the existing walk/standing/launch/idle calls keep
  blend 0 (today's behaviour - `playback_default_blend_time` is 0.0).

**Accepted:** the feet slide during the 0.5 s and 0.25 s crossfades. Both clips are blending and
the speed is between their authored speeds; the no-slide test runs at steady 20 m/s only.

## Camera (`mech.gd`)

All three are offsets added after `_aim_camera()` and **all zero when `Settings.camera_motion`
is off**.

1. **Bounce share** - `CameraPivot.position.y = _pivot_rest_y + BOUNCE_SHARE * (hip_y -
   hip_y_cycle_mean)`, `BOUNCE_SHARE = 0.35` (0.6 m of hip -> ~0.2 m of camera), smoothed over
   ~0.05 s. Only while `MECH_sprint` is the playing clip; eases back to rest otherwise.
2. **Footfall dip** - a critically damped spring kicked down by `FOOTFALL_DIP = 0.25` m at each
   contact (the `MECH_sprint` playhead crossing 0.0 or 0.5), settling in ~0.15 s. Same spring
   shape as pilot9's `_dip_spring_step()`.
3. **Footfall shake** - `FOOTFALL_SHAKE_DEG = 0.6` of random pitch + roll on `CameraPitch`,
   decaying to zero over 0.12 s from each contact.

Contacts come from **playhead phase crossings** in `_physics_process`, not method tracks - the
clip stays pure pose data and the tests can drive it without a tree. A crossing is only a
footfall while `MECH_sprint` has full blend weight (not mid-crossfade).

### FOV

`camera.fov = Settings.fov + _sprint_fov_boost`, the boost easing to `SPRINT_FOV_BOOST = 10`
deg while speed > 7 and back to 0 otherwise, at pilot9's `fov_transition_speed` (8 / s). Not
gated by CAMERA MOTION (pilot9's sprint FOV is not either). The handover pan keeps reading
`camera.fov` live, so a pan that starts mid-sprint flies from the widened FOV.

## Footfall dust

At each contact (same crossing as the dip), a dust ring at the planted `toe.*.001`'s world
position, on the floor. Built with Pilot9Vfx's `_dust_burst()` scaled to the mech: puff size
**1.8 m** (4x pilot9's 0.45), ~10 puffs, life 0.8 s, radial speed ~6 m/s.

- `_dust_burst()` reads nothing off `pilot` (its colour/scale come from arguments), but its
  `_particles()` helper must be checked during the build. If it reads pilot exports, lift the two
  helpers to static functions on `Pilot9Vfx` and call them from both - do not copy them.
- The mech gets a small `MechVfx` node built in code by `mech.gd::_ready()` (the same
  rebuild-proof pattern as Pilot9Vfx).
- **Off when `Settings.movement_effects` is off.**

## Tests - `tests/test_mech_sprint.gd`

The clip (calls `MechSprint.build()` on the real imported skeleton):

- Exists as `MECH_sprint`, loops, length 1.0, 31 keys; key 30 == key 0 on every track (seamless).
- **No slide:** at 30 samples across each contact window, the planted `toe.*.001`'s model-space Z
  velocity is -20 m/s +/- 5%, and its height stays under 0.1 m.
- **Flight:** at t = 0.375 and 0.875, both toe tips are above 0.3 m.
- **Mirror:** the R leg at t + 0.5 equals the L leg at t mirrored in X (within 0.5 deg).
- **Bob:** `spine` height min 4.00 +/- 0.05 at t = 0.125, max 4.60 +/- 0.05 at t = 0.375; X/Z never
  leave the standing anchor.
- **Arms oppose:** at t = 0, R hand ahead of the hip, L hand behind; reversed at t = 0.5.
- The IK-leftover bones hold their standing values.

Movement and the rest (drive `mech.gd` the way `test_mech.gd` does):

- Toggle flips on `sprint`, clears on `walk`, clears on a complete stop, survives a press made
  while standing, clears on exit.
- Walk -> 20 m/s in 0.5 s (+/- one physics frame); release -> 0 within 0.25 s; sprint off -> 7
  within 0.25 s; below 7 the stop is still instant.
- Turn rate 4 at 20 m/s, 10 at 7 m/s.
- Bank leans into a left turn (sign), caps at 12 deg, composes with the Model's -90 deg yaw (the
  nose still lands on +Z - `test_the_model_faces_the_way_the_mech_walks` stays green).
- Camera offsets are zero with CAMERA MOTION off; no dust with MOVEMENT EFFECTS off.
- FOV target is `Settings.fov + 10` while sprinting.
- `clip_for` picks `MECH_sprint` above 7 m/s and the existing chains unchanged below it.
- The existing `tests/test_mech.gd` and `tests/test_pilot9_mech.gd` stay green.

## Probe - `tests/_probe_mech_sprint.gd`

Run windowed (the headless dummy renderer draws nothing). Poses `MECH_sprint` at **contact
(0.000), down (0.125), toe-off (0.250), up (0.375)** and saves each from the **side** and from
**three-quarters front** - 8 PNGs to `screenshots/mech-sprint/`, named `<pose>-<view>.png`, with a
floor grid line every 1 m so stride and toe height can be read off the image. This is decision
6's correction loop: the user reads the 8 frames and says things like "contact: arm higher".

## Order

1. `mech_sprint.gd` + the clip tests (green before anything plays it).
2. Probe screenshots - look at them before wiring, fix anything obviously wrong.
3. Toggle, speeds, turning, `clip_for` + crossfades.
4. Banking.
5. Camera bounce / dip / shake, FOV.
6. Footfall dust.
7. Full suite, worklog, memory.

## Redo 2026-10-12: a grounded titan run

> Supersedes decisions 3, 5 and 6 and "The gait" above where they disagree. Built the same day.

"The legs still look wonky and the arms are not in sync... think like Titanfall titan running or
Pacific Rim." Measured off the 10-06 clip before the grill:

- **In the air ~70% of the time.** Each foot was down 0.15 s of the 1.0 s cycle (the build's
  shortened stride shrank the contact window), so neither foot touched for most of it.
- **No push-off.** A planted foot left only 1.0 m behind the hip; the legs paddled in front.
- **Paw-back.** The swing foot's farthest point came 0.15 s before landing.
- **Arms on a sine against legs that are not.** Peaks drifted after the plants, 3.7 m of hand
  travel up to canopy height.

Reference (no published Titanfall titan run breakdown exists): ILM's Pacific Rim interviews and
animator critiques of mech runs - linger in the low contact pose and move fast through passing; a
heavy body bobs less, steady head; the chassis counter-shifts late toward the mass; arms cross the
body on diagonals; Pacific Rim cheated the Jaegers faster than physics so they would not lumber.

| # | Decision |
|---|---|
| R1 | **Grounded, not bounding.** |
| R2 | **0.8 s cycle, 2.5 steps/s, each foot down 0.28 s** (a 5.6 m floor path, from 2.1 m ahead of the hip to 3.5 m behind). 20 m/s kept. The leg cannot reach a 40%-of-1.0 s, 8 m path at a heavy hip height. |
| R3 | **Arms:** +30 / -25 deg, elbows 80-95 deg, forward fist across toward the centreline, back fist out past the hip; each arm's forward peak at the opposite foot's plant, held through the low pose (tanh-flattened), fast through the middle; a 2.5 deg shoulder drop and 4 deg forearm sag at every plant, settled by ~0.15 s. |
| R4 | **Body:** bob 0.25 m (low 0.07 s after the plant, high in the flight); hips sway 0.15 m over the planted foot, roll 4 deg; lean 20 deg (+2 at the low); hips yaw 6 deg, chest counters 8 deg 0.05 s late; canopy cancels 70%. |
| R5 | **Legs:** lands on the sole plate's back edge tip-up 12 deg, slaps flat by 20% of the stance, pivots onto the plate tip for the push-off (35 deg heel up); the stilt (foot + toe) leans from the reaching leg's line through loaded to in line with the driving leg; the swing lifts slowly and whips through passing (time warp), heel peaks ~1.0 m; no visible paw-back. |
| R6 | **Rate = speed / 20** (floor 7/20) while `MECH_sprint` plays, so the ramp and brake no longer skate. |

### Built

`scripts/mech_sprint.gd` rewritten around the measured foot: `foot` + `toe` are one near-vertical
**stilt** (ankle to ball, ~1.67 m) and `toe.*.001` is a flat **sole plate** (~0.86 m forward of the
ball, its tip where the `toe.*.002` leftover sits). `leg_state()` returns the ball target, plate
pitch and stilt lean; the floor contact (ball while tip-up, plate tip once flat) moves back at
exactly 20 m/s. `mech.gd`: `sprint_rate()` sets `speed_scale` in `_drive_animation` (1.0 for every
other clip); footfalls read the playhead against `MechSprint.LENGTH`.

Departures: "arrives already moving back at about 20 m/s" and "farthest point is the landing"
cannot both hold in the mech's frame; the farthest point won - the foot comes down with a near-zero
paw-back (`SWING_END_SLOPE` -2) and stops dead, a stomp. The fist's measured forward peak is ~0.07 s
after the plant (lean, bob and the chest's lag on top of the arm curve), inside the hold; the test
allows 0.1 s.

Probe (`tests/_probe_mech_sprint.gd`, windowed): plant / low / midstance / toeoff / flight x side /
front, plus `cycle-side.png`, 12 side frames across the cycle. The old empty `contact-side` frame
was the first draw before the window came up; the probe now warms up 10 frames.

## Retune 2026-10-13: slower, upright, feet that come back

> Supersedes R2, R4's lean and bob, decision 2 (speed) and the crossfade times above. Built the same
> day. Not yet played.

"The mech is leaning too far forwards... the speed also needs to be slowed down, currently the mechs
feet slide... make sure the feet go back to normal after moving."

| # | Decision |
|---|---|
| T1 | **14 m/s** (was 20). The cycle is rebuilt for it, so a planted foot moves back at exactly 14 m/s. The clip still plays at speed / 14 below that (floor 7 / 14 = 0.5). |
| T2 | **Lean 8 deg** (was 20) at `spine`, +1 deg at the low point (was 2). The canopy still cancels 70%. |
| T3 | **1.0 s cycle, 2 steps/s, 7 m stride, each foot down 0.35 s**: a 4.9 m floor path, from 1.85 m ahead of the hip to 3.05 m behind (the old 2.1 : 3.5 split, scaled). |
| T4 | **Walk <-> run crossfade 0.15 s** (was 0.5 s in, 0.25 s out), still phase-matched. The 0.5 s speed ramp and 0.25 s brake are unchanged; the run clip's speed-matched rate keeps the feet planted through them. |
| T5 | Bank: full 12 deg at 14 m/s on a ~12 m circle (`BANK_FULL_ACCEL` 33 -> 16.33). Bob 0.25 -> 0.2 m (`HIP_HIGH` 4.15 -> 4.10). Turn rate, camera dip/shake, FOV and dust unchanged. |
| T6 | **Feet reset.** No exported clip keys `toe.L.001` (the left sole plate; the right one is keyed), so after a run it kept the run's last angle under every later clip. `mech.gd::hold_sprint_bones()` gives every clip a one-key track holding MECH_standing's value for each bone the run keys and the clip does not. No Blender change. |

### Built

`mech_sprint.gd` consts only (`LENGTH`, `SPRINT_SPEED`, `CONTACT_TIME`, `HIP_HIGH`, `LEAN_DEG`,
`LEAN_BOB_DEG`, `STRIDE_FRONT`); every leg key is still inside reach. `mech.gd`: `SPRINT_SPEED` 14,
`SPRINT_BLEND_TIME` 0.15 used by `blend_for()`, `BANK_FULL_ACCEL` 16.33, `hold_sprint_bones()` called
from `_add_sprint_clip()`. Tests retuned to the new numbers, plus `test_the_lean_is_eight_degrees`,
`test_every_clip_keys_every_bone_the_run_moves` and
`test_the_left_sole_plate_is_back_to_standing_after_a_run`. The probe poses moved to the new timing
(plant 0, low 0.07, midstance 0.175, toe-off 0.34, flight 0.425).
