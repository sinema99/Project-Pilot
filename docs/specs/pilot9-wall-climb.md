# Spec: pilot9's wall climb

> **Status:** agreed 2026-10-13 (grilled); built 2026-10-13, not yet played. See *Built* at the end.
> **Scene:** `scenes/pilot9.tscn`, played in `scenes/trial.tscn`. No test course (the user's call).
> **Clip:** Mixamo *Climbing Up Wall* - `~/Downloads/Climbing Up Wall.fbx` (2026-10-13 12:27),
> copied to `assets/pilot9_wall_climb.fbx`.
> **Follows:** `docs/specs/pilot9-wall-run.md` (the gates, the pull, the wall-jump it borrows) and
> `docs/specs/pilot9-vault.md` (the FBX-without-Blender route).

## Problem statement

Running straight at a wall does nothing - he hits it. The wall-run only works airborne, and
dead-on it borrows the camera to pick a direction. The user wants the drawing:

```
            WALL
 wall run \ climb / wall run
           \  ^  /
              |
            Pilot
```

Straight at the wall, or within 10-15 degrees of it: climb up it. Anything steeper: the wall-run
that already exists.

## The clip

Measured before any decision: one clip, `mixamo_com`, **2.0 s, In Place, looping** - the Hips
bob ~0.3 m and come back to their start. Hand over hand; on pilot9's retargeted skeleton each
hand plants once per loop (left at 31 %, right at 91 %). 43 tracks, including finger bones the
blockout rig does not have. The climber **leans back** off the face: hands reach 0.55 m in
front of his origin, toes only 0.30 m.

So the clip decides nothing about height or speed - the controller does.

## Decisions (the grilling, in order)

1. **The head-on cone is the climb's.** Within `wall_climb_angle` (15 deg) of dead-on it climbs.
   The camera-redirected head-on wall-run keeps 15-30 deg and is the fallback inside 15 whenever
   the climb refuses. The sideways run is unchanged past that.
2. **Ground and air.** Running into a wall climbs it from the floor; jumping into one climbs it
   from wherever he catches it. Both need `wall_run_min_speed` (4 m/s) of horizontal speed - a
   walk into a wall does nothing. No ground-start wall-run (a separate change if ever).
3. **A Titanfall burst, not a stamina climb.** Automatic, no steering, a fixed rise, a lip hands
   off to the mantle, otherwise he runs out of grip and comes off. The loop plays at a rate tied
   to his climb speed.
4. **4.0 m per climb.** Ground climb reaches lips to **5.9 m** (4 + the mantle's 1.9 band), a
   metre past a single jump; caught at the top of a jump, ~**8.9 m** - the 8.6 m block on
   TrainingV becomes reachable.
5. **No budget.** Climb, jump off, climb the wall behind - Mario wall-jumping. Two facing walls
   are a chimney with no ceiling. This deliberately breaks the old "13.3 m is out of reach"
   ceiling the wall-run's chain decay protected.
6. **The same face waits 1 s** (`wall_climb_same_wall_cooldown`), counted from the end of a climb,
   so the targeting does not re-grab the wall he is leaving. Any other wall is open at once. A
   single tall wall is therefore a slow elevator (climb, peel, wait, climb) - the user's call.
7. **The climb jump is Mario's.** Straight out along the normal at `wall_jump_kick` (8.5 m/s),
   a **full** `jump_velocity` every time, outside the wall-run's decaying chain (neither reads
   nor advances it), an instant 180 to face away, and the wall-jump's push protection after.
   The double jump is untouched.
8. **Exits:** jump, a lip (the mantle), the wall ending above him, dash, or the clock. Crouch
   and the stick do nothing. The clock is a **0.8 s rise + 0.25 s stall** (speed eases to zero,
   the clip slows to a freeze), then a **1 m/s peel** off the face and a 0.15 s coyote in which
   jump is still the climb jump.
9. **Entry:** travel within 15 deg of dead-on, >= 4 m/s, face within 15 deg of vertical.
   Falling catches count (the fall is cancelled), a rising jump is replaced, and arrival speed
   changes nothing - a 4 m/s jog and a 14 m/s sprint both climb exactly 4.0 m. A lip the mantle
   can already take in the air is the mantle's.
10. **Look:** the loop at 2.5x (one loop = the 0.8 s rise), easing to a freeze in the stall. A
    measured mesh fit so hands meet the face. Staff hold off; body lean and arm swing off;
    camera unchanged. Hand taps on each plant, wall scuffs up the face, the wall-jump kick on
    the climb jump - all under MOVEMENT EFFECTS.
11. **Inside corner:** a wall-run that meets a too-tall wall dead ahead hands into a climb up it.
    A lip there is still the mantle's (row 2 of the wall-run spec's table).
12. **Other verbs:** a WALL-CLIMB row in Abilities (`can_wall_climb`). Dash ends a climb (no
    coyote, cooldown starts). Reflect and equip/holster are ignored. No rail catch mid-climb.
    Pilot9 only.
13. **No test course.** Suite tests and a headless probe build their own walls in code.

## Numbers

| Export | Default | Meaning |
|---|---|---|
| `can_wall_climb` | true | the ability |
| `wall_climb_angle` | 15 deg | the cone off dead-on |
| `wall_climb_height` | 4.0 m | rise + stall, always |
| `wall_climb_rise_time` | 0.8 s | flat out |
| `wall_climb_stall_time` | 0.25 s | eases to zero; part of the height |
| `wall_climb_peel_speed` | 1.0 m/s | off the face at the end |
| `wall_climb_same_wall_cooldown` | 1.0 s | that face only |
| `wall_climb_anim_speed` | 2.5 | clip rate over the rise |

The climb speed is derived, not set: `wall_climb_speed_for(h, rise, stall) = h / (rise + stall/2)`
= **4.32 m/s**, so rise + the linear stall come to exactly `wall_climb_height`.

Baked by `scripts/pilot9_build_scene.gd::_ensure_wall_climb_motion()`: `wall_climb_grab_phases`
(the two plants), `wall_climb_lean` (8.6 deg), `wall_climb_hand_reach` (0.219 m),
`wall_climb_duration` (2.0 s).

## Shape of the code

- `_handle_wall_climb(delta)` - in `_physics_process()` **after** `_handle_mantle_trigger()` and
  **before** `_handle_wall_run()`. Entry (dead-on ray, `_probe_wall_ahead()`), sustain (a ray
  along -normal from chest height, `_wall_follows()` for seams), the jump press (buffered), the
  clock (peel), the cooldown tick, and the inside-corner handoff while a run is live.
- `_wall_climb_gates()` - pure. `_can_start_wall_climb()` - the live wrapper (verbs, toggle,
  cooldown, the mantle's claim in the air).
- `_apply_wall_climb_velocity()` - in the movement if/elif: up at the climb speed x
  `wall_climb_speed_fraction_at()`, held to the face by the wall-run's pull, nothing along it.
- `_take_wall_climb_jump()` - spent in `_handle_gravity_and_jump()` from the buffer or the climb
  coyote (ahead of the wall coyote).
- `_handle_mantle_trigger()` aims into the climbed face at the run-top reach while climbing.
- Animation: `wall_climb` state (clip through `WallClimbScale`), 0.1 s in from Locomotion,
  crouch, slide, jump_land, jump, fall, wall_run; out to jump / Locomotion / fall.
  `pilot9_animation.gd::_drive_wall_climb()` writes `wall_climb_clip_rate()`.

## Tests

- `tests/test_pilot9_wall_climb.gd` (suite, 20 tests): the ability row, defaults, the state and
  its driver path, hands blocked (staff/equip/reflect), the height integral, the stall, every
  gate, **the angle split** (0-89 deg: climb up to 15, a run past it), the order in
  `_physics_process()`, the cooldown, and live climbs on collider walls - height + peel, the
  climb jump, a chimney, the cooldown, the inside corner, a mantle-able lip, the wall ending,
  `can_wall_climb` off.
- `tests/_probe_wall_climb.gd` (real frames, `--fixed-fps 60`, exits 1 on fail): ground climb
  4.04 m, sprint entry the same, 5.5 m block climbed and mantled, 6.5 m climb-and-peel, 1.5 m
  wall mantled, 30 deg no climb, the chimney, hands on the face.

## Built

Built 2026-10-13, the same day. Departures and findings:

- **The clip leans back, so the mesh does too.** A slide toward the face alone put the reaching
  hands 0.17 m into the wall (hands reach 0.55 m, toes 0.30 m). The bake fits a line through the
  furthest hand and the furthest toe: the mesh is tipped back **8.6 deg** about his feet, then
  slid in 0.09 m. Probed: wrists **0.075-0.16 m** off the face through the whole climb, which
  with the palm puts fingertips on it. Tilt and slide are **snapped** at entry - eased, the hands
  went through the wall for the first 0.3 s.
- **The taps are on the plants, not the peaks.** A hand tops out, then comes forward onto the
  face ~0.07 s later; the tap waits for the forward reach.
- **The peel holds for the climb coyote.** Air control is speed, not momentum: with the stick
  still held at the wall, the 1 m/s push was overwritten the very next frame. The push now holds
  for the 0.15 s coyote, then the stick has him again.
- **Fingers.** The FBX has finger tracks the BoneMap leaves unmapped; `_ensure_fbx_clips()` used
  to refuse any `mixamorig_*` track. It now drops unmapped ones and refuses only a Mixamo-named
  Hips (the real "retarget did not run" signal). `docs/reimport.md` updated.
- **The mantle now centres the mesh on entry** (`character.position = 0` beside its tilt snap):
  out of a climb the slide in eased out over the mantle's first frames and put the wrists
  0.09 m off the lip. `tests/_probe_mantle_hands.gd` is back to 0.000 on every case.
- **The staff is not moved to his back.** A drawn staff stays in his hand on a climb (only the
  hold pose is off, as in the air) - the spec said "stays on his back", which is only true when
  it is holstered.
- **Changes the mantle and vault probes see (by design):** running at a wall now climbs it from
  0.8 m out (ray reach from his centre), so `_probe_mantle_exit.gd`'s scripted jump at 0.6 m
  arrives after a climb-and-mantle has already stood him on top (he then jumps there).
  `_probe_mantle_hands.gd`'s "double d1.5 h5.0" no longer mantles: the scripted double-jump
  press lands mid-climb and is the climb jump. `_probe_vault.gd` still passes (vaults press at
  >= 0.5 m from the face, outside the climb's reach).
- **`_probe_routes.gd` fails 2 of 30** ("step up to t0_step", "climb chain 3") - the same two
  with `can_wall_climb` off, so not this change.
- **The test press.** `Input.action_press("jump")` inside the suite's single frame leaves `jump`
  just-pressed for every later test file (it took four wall-run tests down). The suite test
  checks the press path in source instead; the probe presses for real.

Played: not yet.
