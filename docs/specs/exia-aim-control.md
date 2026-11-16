# Spec: EXIA aim-forward control - strafe, tank turn, Alt free-look

> **Status:** grilled + specced 2026-11-12; built 2026-11-12.
> **Scene:** `scenes/mech.tscn` (EXIA in `trial.tscn`).
> **Touches:** `scripts/mech.gd` (driving, camera, free-look), `scripts/mech_gait.gd` (a `StepGait`
> for the strafe and the back walk, the foot `x` and `leg_yaw` spec fields, diagonal bakes),
> `scripts/mech_moves.gd` (`build_all` adds the new clips). Tests: `tests/test_mech_aim.gd` (new),
> `tests/test_mech_moves.gd` (next_loco rows), `tests/test_mech_gait.gd`.
> **Supersedes:** the control model of `docs/specs/exia-movement.md` ("the mech travels along its own
> nose", camera-relative heading, face-the-travel-direction). Its clips, speeds, jump, stop and exit
> rules stand except where this says otherwise.

## The ask

"A and D strafe, not run left or right. The camera more like the pilot's now: the mouse isn't a
free-look, it's locked to forward facing. Alt as a free-look. If the player does a 180, the camera
has free control to do the 180, but the mech takes time to catch up, like a tank."

## Decisions (from the grill)

| # | Decision |
|---|---|
| 1 | **The body chases the camera.** EXIA's yaw always heads for the camera's yaw (the camera sits behind the nose) at a hard capped rate. No 180 detection: a fast swing simply outruns the cap. **W follows the nose**, not the camera - mid-turn it walks wherever the nose points. |
| 2 | **Always, standing too.** Moving the mouse with no key held turns the mech. |
| 3 | **Heavy caps:** 120 deg/s standing, 100 deg/s at the run (9 m/s), 60 deg/s at a sprint (14 m/s), blended by speed (0 -> 9 standing -> run, 9 -> 14 run -> sprint). Exports. |
| 4 | **Speeds off the nose:** A/D strafe **6 m/s**, S backs up **5 m/s**, S+A / S+D **5.5**. Sprint only with W in the mix (W+A / W+D sprint, angled). Sprint pressed while only strafing / backing: speed stays, the toggle stays on for when W comes back. |
| 5 | **Real side-step gait**, built in code: lead leg steps out, trail leg closes, legs never cross, hips square, planted feet hold. Plus a **backward walk** gait for S. |
| 6 | **Diagonals = the nearest clip with the hips yawed 45 deg** toward travel and the chest counter-rotated onto the nose. W+A / W+D: run or sprint; S+A / S+D: the back walk. |
| 7 | **Alt free-look:** while held the mech stops chasing (WASD still drive off the nose), the mouse orbits freely. On release the camera eases back behind the nose over **0.25 s** (yaw to the nose, pitch to where it was at the press); the mech never moves for it. |
| 8 | **Air:** committed. Launch velocity locked - no steering, no air strafe. The nose still chases the camera at **20%** of the cap. |
| 9 | **Standing: 30 deg dead cone.** Standing still the camera may drift 30 deg either side before the body moves; past it the step-turn plays (capped at 120 deg/s) until within 8 deg. Moving: no cone, it chases continuously. |
| 10 | **Stops:** the stop settle clips only after a forward run (incl. W+A / W+D). Strafe / back release brakes in ~0.3 s (20 m/s^2) and eases into the standing idle. |
| 11 | **Replace, don't toggle.** `aim_lock` export (default true) keeps the old control reachable from the editor; no menu row. |

Unchanged: the bank into turns, the exit rule (floor, <= run speed), F boarding + the handover pan,
the camera framing and pitch limits, the footfall dip / shake / dust, the jump numbers.

## Control (`mech.gd`, `aim_lock` true)

**Aim yaw** = the yaw that puts the camera directly behind the nose: `camera_yaw - PI` (the inverse of
`yaw_behind`). `aim_off` = |wrap(aim - rotation.y)|; 0 while free-look is held or returning.

**Keys -> a move in the mech's own frame** (nose +Z, left +X): `m = normalize(-x, 0, -y)` of the key
vector (A = x -1, W = y -1). World direction = the nose's basis x m, re-read every frame, so the velocity
turns with the nose and nothing slides.

| Keys | Gait | Clip | Target speed |
|---|---|---|---|
| W | forward | `MECH_run` / `MECH_sprint` (by speed, as before) | 9 / 14 with the sprint toggle |
| W+A, W+D | forward | `MECH_run_diag_L/_R`, `MECH_sprint_diag_L/_R` | 9 / 14 |
| A, D | side | `MECH_strafe_L` / `_R` | 6 |
| S | back | `MECH_back` | 5 |
| S+A, S+D | back | `MECH_back_diag_L/_R` | 5.5 |

**Speed:** the speed along the new direction is the current velocity projected onto it (floored at 0),
so A -> D ramps from zero and W -> W+A keeps cos 45 of it. Then: forward uses the old
`speed_target` (run ramp 15 m/s^2, sprint ramp, sprint brake); side / back ramp at 15 m/s^2 up and
brake at 20 m/s^2 down (a sprint dropping into a strafe).

**Turning per state:**

| State | Yaw |
|---|---|
| STAND | none (inside the cone) |
| TURN | step-turn toward aim at the standing cap (120 deg/s), pivoting on the planted foot as before |
| RUN, LAND | capped chase at `aim_turn_rate(speed)` |
| AIR | capped chase at 20% of `aim_turn_rate(speed)`; velocity untouched |
| CROUCH, STOP | none |

**State table changes** (`next_loco`, aim mode; classic rows unchanged):

| From | Goes to | When |
|---|---|---|
| STAND | RUN | a key held (any heading - W goes along the nose) |
| STAND | TURN | no key, `aim_off` > 30 deg |
| TURN | RUN | a key held |
| TURN | STAND | `aim_off` < 8 deg |
| RUN | STOP | keys let go at <= 9.1 and > 4.5 m/s **and the playing gait is forward** |
| RUN | STAND | otherwise on let-go (STAND brakes at 20 m/s^2 instead of stopping dead) |

**Free-look** (`free_look` action, Alt): pressed -> pitch remembered, chase off. Mouse orbits
`camera_yaw` / `camera_pitch` freely. Released -> 0.25 s smoothstep from where the view is to
`yaw_behind(rotation.y)` and the press pitch; mouse ignored during the return, chase off until it
lands. Re-pressed mid-return: the return is dropped, free-look again.

## The new clips (`mech_gait.gd`)

Two new pose-spec fields, both 0 / standing in `standing_spec`:

- `feet[side].x` - the ball's x in mech space (absolute; standing = the rig's +-1.76).
- `leg_yaw` (deg) - the whole lower body yawed about the vertical through the spine bone: ball
  positions, foot / toe / plate bones and the knee poles. A diagonal sets `leg_yaw = yaw += th`,
  `counter -= th`, so the hips and legs point along travel and spine.001 up is exactly back on the nose.

**`StepGait`** - a planted foot slides through the mech opposite the travel direction `dir` at exactly
`speed`; the swing is a hermite back to the landing spot with a lift arc. u = 0 is the left plant,
0.5 the right (the run's convention, so gait -> gait crossfades keep the phase).

| | Strafe (L / R) | Back walk | Back diag |
|---|---|---|---|
| dir | +X / -X | -Z | -Z (then leg_yaw -+45) |
| speed / cycle / contact | 6 / 0.8 / 0.42 s | 5 / 1.1 / 0.6 | 5.5 / 1.1 / 0.6 |
| stance width | +0.25 m out per foot | standing | standing |
| lift | 0.5 m | 0.4 | 0.4 |
| hips | 0.2 m down, 0.08 bob, roll 3 deg into travel | 0.25 down, 0.06 bob, lean +3 | same |
| plate | flat | lands tip-down -8, lifts tip-up +10 | same |
| arms | out 6, swing 4 | swing 8, elbow +10 | same |

Strafe numbers keep the balls >= ~1.6 m apart at the close (the trail foot lands inside where the
lead just left) and inside the leg's reach. Diagonals: the run / sprint `Gait` and the back `StepGait`
baked with `leg_yaw` +-45 (W+A / S+D = +45 run, -45 back; see the table's travel angles).

## Tests

- `test_mech_aim.gd`: aim_turn_rate at 0 / 9 / 14 and blended; capped chase; move_local and the
  gait / clip / speed table; free-look release returns to behind the nose in 0.25 s and pitch to the
  press; mouse ignored mid-return; a driven mech standing turns only past 30 deg; a strafe's velocity is
  sideways off the nose; the AIR velocity is untouched by the mouse.
- `test_mech_gait.gd`: every new clip loops at its length; planted balls slide at the gait speed along
  the right axis; no ball under the floor; legs in reach; strafe balls never closer than 1.4 m;
  a diagonal's chest (spine.001) faces the nose while its planted ball slides along the 45 deg line.
- `test_mech_moves.gd`: the aim-mode next_loco rows.

## Built (2026-11-12)

- **Deviation:** the diagonals' hip yaw is baked into clips (`MECH_run_diag_L/R`,
  `MECH_sprint_diag_L/R`, `MECH_back_diag_L/R`) via the `leg_yaw` field, not a runtime twist of the
  Model with a chest counter-rotation: a SkeletonModifier chest twist would leave the back panels
  (which read the shoulder bones' poses) a diagonal's 45 deg off the chest. Switching straight <->
  diagonal is a 0.15 s same-phase gait crossfade.
- 18 built clips now (9 new). Strafe balls stay >= 1.4 m apart (test), every key in reach.
- `drive_aim_step(keys, free_look, jump, sprint, walk, delta, on_floor)` is the testable frame;
  `_drive_classic` is the old control untouched (`tests/_probe_mech_drive.gd` sets `aim_lock = false`).
- Real physics (`tests/_probe_mech_aim_drive.gd`): standing 180 in 1.43 s, pivot drift 5 mm; strafe
  6.00 m/s with the nose unmoved; let go -> 0 in 0.33 s, STAND (no settle); back 5.00, S+A 5.50; while
  running and chasing a quarter-turn flick, velocity . nose = 1.0000; a mid-air camera swing leaves the
  velocity exactly as launched.
- Not checked headlessly: how the side-step and back walk look at speed.
