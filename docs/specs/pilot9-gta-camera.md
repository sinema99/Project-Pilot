# Spec: pilot9's GTA-style third-person camera

> **Status:** grilled, specced and built 2026-10-12. Not yet played.
> **Touches:** `scripts/pilot9.gd` (`tilt_limit` replaced by `tilt_up_limit` / `tilt_down_limit`),
> `tests/test_pilot9_camera_gta.gd` (new), `test_pilot9_camera_shoulder.gd`, `test_pilot9_camera_zoom.gd`.
> No scene change.

## The ask

"A better 3rd person camera ... identical to GTA or Red Dead." Resolved to GTA V's on-foot camera:
tight, snappy, close over the right shoulder.

## Decisions

| | |
|---|---|
| Base feel | GTA V. RDR2's auto-drift was offered and **declined** - no auto-recenter at all |
| Framing | `camera_distance` 3.5 -> **2.5 m**; `camera_shoulder_offset` 0.4 -> **0.8 m**, right shoulder. The X swap and the wall-run's auto side are unchanged |
| Orbit height | `camera_pivot_raise` **+0.4 m**, added in `_camera_zoom_lift()` and faded out into first person, so the camera orbits his head. Net pivot ~1.65 m at the 2.5 m arm |
| Pitch | `tilt_limit` (75, both ways) -> `tilt_up_limit` **45** / `tilt_down_limit` **60** degrees |
| Mouse | Raw, 1:1. Untouched apart from the new pitch clamp |
| Stick | The action deadzone (0.2, already in `project.godot`) stays. Response curve: deflection ^ `look_stick_curve` (1.6). Ramp: a full push (>= 0.9) starts at `look_stick_ramp_start` (0.5) of full speed and reaches 1.0 over `look_stick_ramp_time` (0.3 s); it resets the moment the stick drops below 0.9, and fades in with deflection (0.6-0.95) so gentle pushes are never slowed |
| Collision | Unchanged: fast push-in (`camera_retract_speed` 16), slow ease-out (`camera_return_speed` 3.0, about a 0.33 s time constant), shoulder clearance collapses the offset in tight spaces. See "Not changed" |
| State framing | Sprint or dash: **+0.3 m** back (`camera_sprint_pullback`). Crouch or slide: pivot **-0.4 m** (`camera_crouch_drop`). Both eased over `camera_state_ease_time` (0.3 s), never cut - a critically damped spring from rest, stepped per drawn frame (2026-10-13: the old exponential ease started at full speed and read as a snap coming out of a slide) |
| Kept as is | Sprint FOV, dash FOV kick, sway, landing dip, CAMERA MOTION toggle, wheel zoom (1.5-8 m), the dash's camera lag |

## Not changed, on purpose

- **Body-hide threshold.** The mesh hides off `_camera_mode_length / camera_distance`, never off the
  wall-squeezed arm, so a wall can't blink him out. With the 2.5 m reference the line is 0.75 m;
  `camera_zoom_min` (1.5) still clears it, and a test asserts that.
- **Collision rates.** The slow ease-out already matched what was asked for; nothing was added.
- Pilot9 only. The mech and its handover camera are out of scope.

## Not tested headlessly

How it frames and feels. Asserted: the defaults, the pitch clamp both ways, the curve's shape and
endpoints, the ramp's build and reset, the sprint/dash pull-back and release, the crouch/slide drop,
first person getting neither raise nor drop. The zoom test's expected lift now includes the raise.

## Tuning knobs, if it plays wrong

Too far/near: `camera_distance`. Off-center: `camera_shoulder_offset`. Looks at his chest instead of
his head: `camera_pivot_raise`. Stick feels twitchy: `look_stick_curve`, `look_stick_ramp_*`.
