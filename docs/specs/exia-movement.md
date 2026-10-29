# Spec: EXIA movement pass - run, sprint, jump, turn, stop, in and out

> **Status:** grilled + specced 2026-10-27; built 2026-10-27.
> **Scene:** `scenes/mech.tscn` (instanced as `EXIA` in `trial.tscn`; `test_platform.tscn` still
> has one for Setsuna). EXIA stays out of `starter_map` this pass.
> **Touches:** `scripts/mech.gd`; `scripts/mech_sprint.gd` becomes `scripts/mech_gait.gd` (one
> gait builder, two gaits); new `scripts/mech_moves.gd` (every non-cycle clip); `scripts/mech_vfx.gd`
> (dust scale). Tests: `tests/test_mech_sprint.gd` becomes `tests/test_mech_gait.gd`, new
> `tests/test_mech_moves.gd`, `tests/test_mech.gd` updated. Probe: `tests/_probe_mech_sprint.gd`
> becomes `tests/_probe_mech_moves.gd`. `assets/Mech_V1.glb` is NOT touched.
> **Supersedes:** the gait, ramp, brake and camera sections of `docs/specs/exia-sprint.md`. Its rig
> measurements still hold.

## The ask

"Rework how the mech moves. Run and sprint animation improved, the mech at a good working state by
the end of this pass: moveable, run and sprint look good, pilot can get in and out, a jump, stuff
like that."

**Done means:** get in, run, sprint, jump, turn, stop, get out - no sliding feet, no frozen idle,
no getting stuck.

## Decisions (from the grill)

| # | Decision |
|---|---|
| 1 | **Two speeds: run and sprint.** The old 7 m/s walk becomes the run. No third tier. |
| 2 | **Rebuild both as one family**, the 2026-10-13 sprint as the starting point. |
| 3 | **Titanfall titan for both.** Run = upright heavy jog, shorter steps, ~1.2 s cycle, little lean, arms mostly hanging with a small swing. Sprint = the same body committed: longer stride, lower hips, 8 deg lean, bigger arm swing, footfall camera jolt. |
| 4 | **Run 9 m/s, sprint 14 m/s.** Sprint control unchanged (`sprint` toggles, a stop or `walk` clears it). |
| 5 | **Heavy leg jump.** Space. 0.25 s crouch, ~3 m apex, forward speed kept, ~20% air steering, heavy landing (knee bend, camera slam, dust). Walking off a ledge uses the same fall and landing. |
| 6 | **Boarding stays the F cut.** New rules: exit only on the floor and at or below run speed; F while sprinting brakes first, then lets you out; pilot9 put behind the mech, or to a side if that is blocked. |
| 7 | **In:** idle sway while piloted, step-turn on the spot, a 1-2 step stop settle with a dip, a lean-in start. **Out:** strafing/backpedal (turn-to-face stays), slopes, `starter_map`, a boarding animation, a dash. |
| 8 | **Every animation built in code**, like the sprint. `MECH_walk` and `MECH_walk_start` are retired (still imported, never played). `MECH_idle` / `MECH_launch` stay for power-down / boot-up. |
| 9 | **Camera:** run gets ~40% of the sprint's footfall dip + bounce, no shake, no FOV. Sprint unchanged. Jump: a drop during the crouch, a small FOV rise on push-off, the biggest dip of the set + a 0.2 s shake on landing, scaled by fall height. All behind CAMERA MOTION (the FOV parts are not, same as the sprint FOV). |

## The rig (measured 2026-10-27, mech space: nose +Z, left +X, metres)

| | |
|---|---|
| Hip (thigh heads' midpoint) above the floor, standing | **4.44** |
| Feet (ball) | x = +-1.76, z = +0.33 ahead of the hips |
| Thigh / shin | 2.02 / 2.11 (reach 4.13) |
| Stilt (ankle to ball) standing lean | L 10.3 deg, R 15.3 deg (the rig is not symmetric) |
| Standing elbow bend | ~37 deg |

**Knee plane.** The leg solve used to bend every knee in the plane holding the nose (+Z). The
standing pose's knees sit out over the feet, not in that plane, so a solved "standing" pose did not
reproduce `MECH_standing`. The solve now takes each leg's pole from the standing pose itself (the
knee's offset from the hip-ankle line). Feed it the standing targets and you get the standing pose
back, which is what lets the idle, the stop and the landing end exactly on it. This also moves the
sprint's knees out over the feet a little.

## Architecture

```
mech_gait.gd   sampler (locals_at / mech_pose / pose_at), the context, `pose_from(ctx, spec)` - the
               generic solver: hips + spine + arms + two solved legs from one pose spec - and the
               gait: a `Gait` of numbers, `run()` / `sprint()`, `gait_spec(ctx, g, u)`, and
               `bake(skeleton, standing, length, loop, spec_fn)` which keys any spec function into a clip.
mech_moves.gd  every non-cycle clip as a spec function of time: stand idle, stop (L / R lead), turn
               step, jump crouch, air, land. `build_all(skeleton, standing)` -> {name: Animation}.
mech.gd        a locomotion state (`loco`) with a pure transition function, the body physics per state,
               which clip each state plays, camera and exit rules.
```

**A pose spec** is a Dictionary, every field relative to `MECH_standing` unless it says otherwise:
`hip_h` (absolute height above the floor), `sway` (x), `hip_dz`, `lean` / `yaw` / `roll` (deg about
the hips), `counter` (chest yaw, deg), `shoulder_drop` (deg), `arms.L/R = {pitch, elbow, adduct,
curl}` (deg, deltas), `feet.L/R = {z, h, plate, stilt}` (ball z relative to the standing hip z, ball
height above the floor, plate pitch deg, absolute stilt lean deg). `standing_spec(ctx)` is the
standing pose; everything starts from a copy of it.

All built clips are keyed at 30 fps, on the spot (the body supplies the speed), with a rotation
track for every bone, the spine's position track, and the standing value for every other track
`MECH_standing` keys.

## The clips

| Clip | Length | Loop | What it is |
|---|---|---|---|
| `MECH_run` | 1.2 s | yes | the 9 m/s jog. u = 0 is the left plant, u = 0.5 the right. |
| `MECH_sprint` | 1.0 s | yes | the 14 m/s run, same phase convention. |
| `MECH_stand_idle` | 4.0 s | yes | breathing sway. Frame 0 IS the standing pose. |
| `MECH_turn_step` | 1.0 s | yes | stepping on the spot: R swings in the first half (L planted), L in the second. |
| `MECH_stop_L` / `MECH_stop_R` | 1.0 s | no | the stop settle with the named foot leading (planted ahead). Ends on the standing pose. |
| `MECH_jump_crouch` | 0.25 s | no | the load: hips down 1.0 m, lean in, arms back. |
| `MECH_jump_air` | 1.2 s | yes | airborne: legs tucked one forward one back, arms out for balance, a slow drift. |
| `MECH_land` | 0.6 s | no | impact: hips drop 1.1 m by 0.12 s, recover by 0.6. Ends on the standing pose. |

### Run and sprint (one `Gait`, two sets of numbers)

The sprint's 2026-10-13 numbers are kept. The run is the same gait at 9 m/s:

| | Run | Sprint |
|---|---|---|
| Speed / cycle | 9 m/s / 1.2 s (5.4 m steps) | 14 / 1.0 (7 m) |
| Contact per foot | 0.42 s (3.78 m floor path) | 0.35 s (4.9 m) |
| Hip low / high | 4.12 / 4.28 | 3.90 / 4.10 |
| Lean (+ bob) | 4 deg (+0.6) | 8 (+1) |
| Hip yaw / roll / sway | 4 / 3 deg / 0.12 m | 6 / 4 / 0.15 |
| Ball lands ahead of hip | 1.6 m | 1.85 |
| Swing lift | 0.6 m | 0.8 |
| Arm forward / back | 18 / -14 deg | 30 / -25 |
| Elbow (absolute) fwd / back | 55 / 48 deg | 95 / 80 |
| Jolt shoulder / elbow | 1.5 / 2.5 deg | 2.5 / 4 |

Every planted foot moves back through the mech at exactly the gait's speed; each clip plays at
`speed / gait_speed` (run floored at 0.4, sprint at the run's share) so it stays planted through the
ramps and brakes.

### Stand idle

4 s loop, all `(1 - cos 2 pi u) / 2` or `sin` shapes so u = 0 is standing: hips down 4 cm and 3 cm
side to side, lean +0.6 deg, chest yaw 1 deg, arms 2 deg out of phase. Feet planted.

### Turn step

1.0 s loop on the spot: each foot lifts 0.55 m with the plate tipped and comes back down where it
was; hips dip 6 cm at each plant and shift 0.1 m over the planted foot.

### Stop (authored for 9 m/s)

The body brakes linearly over `STOP_TIME` 0.4 s: `d(t) = 9 (t - t^2 / 0.8)`, D = 1.8 m. The lead
foot is planted at `stand_z + D - d(t)` - it is locked to the floor while the body slides past it.
The trail foot starts lifted behind (z = stand - 1.2, h 0.5), swings through and plants at 0.3 s on
the same locked path. Hips: from the run's mean height and lean, bracing back to -4 deg by 0.3 s,
then the settle - down 0.35 m below standing with +3 deg by 0.5 s - and up to standing by 1.0 s.
Arms swing forward on the brake and settle. Which foot leads is read off the run's phase when the
keys are let go: u in [-0.25, 0.25) is the left (it has just planted, it is ahead).

### Jump crouch / air / land

Crouch: feet planted at standing, hips ease down 1.0 m and back 0.25 m, lean 12 deg, arms back 25 deg,
shoulders drop. Air: hips at standing height with the left ball 0.8 m ahead / 1.0 m up and the right
0.6 m behind / 1.4 m up, plates tipped down, arms out 15 deg and opposed 20 / -10, +-3% drift. Land:
feet planted at standing, hips 0.1 m down at contact -> 1.1 m down at 0.12 s (ease out) -> held to
0.2 s -> standing by 0.6 s (ease in-out), lean 14 deg at the bottom, arms down 10 deg + elbows 15,
shoulder jolt.

## Movement (`mech.gd`)

`SPEED` = **9.0** (the run). `SPRINT_SPEED` 14.0 as before.

### The locomotion state

`loco` is one of `STAND, TURN, RUN, STOP, CROUCH, AIR, LAND`, advanced once per physics frame by the
pure `next_loco(loco, in)` while a pilot is driving. Parked / boarding / climbing keep their old
paths untouched.

| From | Goes to | When |
|---|---|---|
| any grounded | CROUCH | Space on the floor (or within the 0.12 s coyote after leaving it), not in the first 0.2 s of LAND |
| STAND, TURN, RUN, STOP | AIR | off the floor for more than `COYOTE` 0.12 s |
| STAND | TURN | a key held and the heading is more than `TURN_STEP_ANGLE` 30 deg off the nose |
| STAND | RUN | a key held, heading within 30 deg |
| TURN | RUN | heading within `TURN_DONE_ANGLE` 8 deg |
| TURN | STAND | keys let go |
| RUN | STOP | keys let go, speed at or below run speed + 0.1, and above `STOP_MIN_SPEED` 4.5 |
| RUN | STAND | keys let go below 4.5 m/s |
| STOP | RUN | a key held |
| STOP | STAND | the stop clip has ended |
| CROUCH | AIR | after `CROUCH_TIME` 0.25 s - the launch: `velocity.y = JUMP_VELOCITY` |
| AIR | LAND | on the floor (and not still rising) |
| LAND | RUN / STAND | the land clip has ended, by whether a key is held |

### The body per state

- **STAND:** velocity to zero at once (as before - a mech that coasts walks off ledges).
- **TURN:** no forward speed. The body yaws toward the heading at `TURN_STEP_RATE` 200 deg/s,
  **pivoting about the planted foot** (left in the first half of the clip, right in the second): the
  origin is rotated round that ball's world position, so the planted foot stays put and the swing
  foot carries the turn. A 180 deg about-face is about 0.9 s - two steps.
- **RUN:** as before (speed ramps along the nose, the heading turns at `turn_rate`) with the run
  ramp `RUN_RAMP_TIME` 0.6 s (15 m/s^2) replacing the walk start, the sprint ramp 0.5 s on top. Sprint
  released while moving eases back to 9 in 0.25 s as before. Keys let go above run speed: brake at
  `(14 - 9) / 0.2` m/s^2 down to run speed, still RUN, then STOP.
- **STOP:** speed follows the stop clip's own curve, `v0 (1 - t / 0.4)` along the travel direction,
  so the locked foot holds. From below 9 m/s v0 is the actual speed (the foot slips by the
  difference, at most 1.8 m x 50%).
- **CROUCH:** horizontal speed kept (x 0.85 when standing still it is zero anyway); no turning.
- **AIR:** gravity x `MECH_GRAVITY_SCALE` 1.6 (15.7 m/s^2) - heavy, ~1.25 s in the air for a full
  jump. `JUMP_VELOCITY` = sqrt(2 x 15.7 x 3.0) = 9.7 m/s for the 3 m apex. Horizontal speed is kept;
  a held key turns the nose at 20% of the ground turn rate and the velocity follows the nose. No key:
  nothing changes. The highest point is tracked for the landing.
- **LAND:** fall = highest point - landing height. Landing from >= 2 m multiplies horizontal speed by
  0.6. Below 1.5 m the clip plays at 1.8x (a light landing); with a key held at 1.5x. Two dust rings,
  one per foot.

The gravity scale applies to the piloted mech whenever it is off the floor (a parked mech is never
off the floor).

### Clip per state and the blends

| State | Clip | Blend in |
|---|---|---|
| STAND | `MECH_stand_idle` (left alone while `MECH_launch` plays; `MECH_standing` after a launch fades into it over 0.3 s) | 0.2 (0.1 from a stop / land, which end on standing) |
| TURN | `MECH_turn_step` | 0.2 |
| RUN | `MECH_run` below `SPRINT_GAIT_SPEED` 9.1, `MECH_sprint` above | 0.2 from a standstill (entered at u = 0.75, the left foot reaching for its plant - the lean-in); run <-> sprint 0.15 at the **same phase** (both clips put the left plant at u = 0) |
| STOP | `MECH_stop_L` / `_R` | 0.15 |
| CROUCH | `MECH_jump_crouch` | 0.1 |
| AIR | `MECH_jump_air` | 0.08 from the crouch (the push-off), 0.25 from walking off a ledge |
| LAND | `MECH_land` | 0.05 |

`hold_built_bones` (was `hold_sprint_bones`) gives every imported clip a held standing track for
any bone the built clips key and it does not (the `toe.L.001` fix, kept).

## Getting in and out

Boarding unchanged. F while driving now calls `_request_exit()`:

- On the floor, at or below run speed + 0.1, not CROUCH / AIR: exit now.
- Otherwise: the sprint toggle is cleared and the exit is **pending**; the prompt reads `EXIT...`
  (sic: `PROMPT_EXIT_PENDING`). Keys still drive (so a sprint brakes down to the run). The moment the
  conditions hold, the exit runs. F again cancels it.
- **Where pilot9 goes:** `exit_spot()` tries ExitPoint (3.6 m behind), then the same distance to the
  left, the right, and the front. A spot is good when a 0.45 x 1.9 m capsule at it hits nothing but the
  mech, and a ray from 2 m above it finds floor within 5 m (it lands on that floor). He faces the
  mech. If none is good, ExitPoint as before.
- Setsuna's climb-down path is unchanged; the speed rule applies to it too.

## Camera

| | Run | Sprint | Jump |
|---|---|---|---|
| Footfall dip | 0.1 m (40%) | 0.25 m | crouch: eases down 0.4 m over the crouch |
| Bounce | 40% share of the run's hip | 35% share | - |
| Shake | none | 0.6 deg, 0.12 s | landing: 1.2 deg, 0.2 s, scaled with the fall |
| FOV | - | +10 | +5 kick on push-off, eased out |
| Landing dip | | | 0.6 m x clamp(fall / 3, 0.5, 2) |

Footfall dust on both gaits (MOVEMENT EFFECTS): the run's at 0.6 scale.

## Tests

- `test_mech_gait.gd`: both gaits loop at their length; planted balls move back at the gait's speed
  (5%); feet below the floor never; every key within the leg's reach; arm swing phasing; run / sprint
  phase convention; `pose_from(standing_spec)` reproduces `MECH_standing` (every bone within 2 cm).
- `test_mech_moves.gd`: every built clip present, looping right, the right length; stand idle frame 0,
  stop end and land end equal standing; stop lead foot locked to the floor (moves back at `d'(t)`);
  turn step feet return to standing; the crouch is lower than standing, the land bottom lower still;
  `next_loco` - every row of the transition table; jump velocity reaches 3 m under the scaled gravity;
  exit gating + pending; exit spot fallback order with a blocker.
- `test_mech.gd`: clip_for walk rows replaced, the ramp-from-walk-start tests removed.

## Probe

`tests/_probe_mech_moves.gd` (windowed): a contact sheet per clip, side view on a 1 m grid, to
`screenshots/mech-moves/<clip>.png`.

## Built (2026-10-27)

- Joins measured: the idle's frame 0, both stops' last frame and the landing's last frame are within
  0.07 mm of `MECH_standing`. All nine clips build in ~50 ms at boot.
- Real-physics drive (`tests/_probe_mech_drive.gd`, headless, simulated keys): S from a standstill
  steps round 180 deg in 0.87 s with the pivot foot drifting **8 mm**; the run reaches 9.00 m/s, the
  sprint 14.00; letting go of a sprint runs RUN -> STOP -> STAND to 0; the jump peaks at **3.08 m**
  and lands; F at rest exits at ExitPoint; F at a sprint goes pending and lets the pilot out on the
  frame it is braked to 9.0; with a box on ExitPoint the pilot comes out 3.6 m off the right side,
  facing the mech.
- Probe sheets looked at: `screenshots/mech-moves/`. The air pose's arms were straight out in front
  (zombie) on the first pass; now down and out for balance (pitch 6 / -14, elbow -10, out 22).
- Suite: 1339 tests, only the known `test_ichi_parked_ship` failures.
- `test_pilot9_mech`'s round trip now checks ExitPoint on the ground plane: the exit drops the pilot
  onto the floor under the spot, and the suite's tree can hold another test's floor.
- Not checked headlessly: how any of it looks and feels at speed in `trial.tscn`.
