# Spec: pilot9's DayZ-style third-person camera

> **Status:** grilled and specced 2026-11-10; **built** 2026-11-10 (see "Built" at the end). Not yet played.
> Replaces the framing in `pilot9-gta-camera.md`; that spec's stick curve/ramp and collision stay.
> **Touches (when built):** `scripts/pilot9.gd`, `project.godot` (input map), `scripts/settings.gd`,
> `scripts/ui/tabs/tab_settings.gd`, camera tests (`test_pilot9_camera_gta.gd`, `_shoulder`, `_zoom`,
> `_sway`, dash FOV / dash lag tests), `docs/specs/settings.md`.

## The ask

"Fix the camera. I want a DayZ style camera." Resolved to: DayZ's camera, **not** DayZ's controls.
Framing is matched to a DayZ screenshot the user supplied (walking through grass beside a wooden
house): he stands just left of centre, head at screen centre, shot from just above and behind his head
looking down, horizon in the top quarter, shins on the bottom edge, feet out of frame.

## Decisions

| | |
|---|---|
| Control model | **Unchanged.** He still turns to face travel (`face_travel_direction` stays `true`), movement stays camera-relative. Full DayZ body-lock (option A) was offered and **declined** |
| Framing | Measured off the screenshot (assumes ~60 deg vertical FOV, ~1.8 m man): eye ~1.6 m behind him horizontally, ~0.4 m above the top of his head. Exports: `camera_distance` 2.5 -> **~1.7 m**, `camera_shoulder_offset` 0.8 -> **0.25 m**, pivot to **~0.4 m over the head** (via `camera_pivot_raise` / `CAMERA_PIVOT_OFFSET`, whichever lands the eye there). Tune by eye against the screenshot |
| Neutral pitch | New export `camera_neutral_pitch` = **-15 deg**. With the mouse level, the screenshot frame IS the view: head at screen centre, horizon in the top quarter |
| Pitch limits | Stay **world-referenced**: `tilt_up_limit` 45 / `tilt_down_limit` 60 measured from the horizon, unchanged. From neutral that is 60 up / 45 down |
| Free-look | **Hold Alt or R3** (joypad button 8, currently unbound). His travel heading freezes at the press; the camera orbits freely (all the way round) without steering the run. On release the camera eases back behind the frozen heading over ~**0.25 s**, then movement is camera-relative again. New input action `free_look` |
| Walk key | `walk` moves from **Alt to Caps Lock** (physical 4194329, unbound today). Note: the mech's walk (`mech.gd:1301`) reads the same action and moves with it |
| Weight | **Light horizontal trail.** A critically damped spring on the pivot's XZ position, ~**0.1 s**, no overshoot. Y stays welded so jumps, landings and ledges stay crisp. Mouse/stick look stays raw and direct |
| Effects | **Zeroed, code kept:** `sprint_fov_boost` 0, `dash_fov_boost` 0, sway (`camera_sway_*`) 0, landing dip 0, `camera_sprint_pullback` 0, `camera_crouch_drop` 0, `wall_run_camera_roll` 0, dash camera lag off (the trail replaces it). Any one comes back by restoring its number |
| Kept | Rail camera swing (functional: steers the view along curves), wheel zoom 1.5-8 m, collision (retract 16 / return 3.0 / shoulder clearance), X shoulder swap and the wall-run's auto side (now swinging +/-0.25 m), stick curve + ramp |
| Scope | Every scene pilot9 plays in: trial, starter map, Internals, Ichi (tredge included), Boss Arena, Jetpack. No scene overrides the camera exports, so defaults carry. The EXIA mech camera / handover and all cutscene cameras are untouched |

## Open item to settle at build time

- **The CAMERA MOTION menu row.** Agreed in the grill: remove it, since the pilot effects it toggled are
  now zero. Found while speccing: `Settings.camera_motion` also gates the **mech's shake**
  (`mech.gd:771, 1045, 1057, 1116`), the **range hit shake** (`pilot_hit_feedback.gd:103`), the
  **reflect spin** kick (`reflect_spin.gd:565`, plus pilot9's reflect FOV at `pilot9.gd:3555`) and the
  **hologram** (`pilot9_hologram.gd:347`). Removing the row strips player control over those too.
  Recommendation: **keep the row** (it still means something), or remove it and hard-wire those to
  "on". Ask before building.
- The reflect FOV kick wasn't on the effects list. It is a camera effect; zero it with the rest unless
  the user says otherwise.

## Build notes

- `_camera_zoom_tilt()` already writes `camera_3d.rotation.x` from zoom framing. The neutral pitch must
  add to that (or to the pivot pitch) without making the pitch clamp read the offset - limits are
  world-referenced, so clamp the **total** camera pitch, not the mouse pitch.
- The free-look heading freeze is a basis swap in the move-input path: while held, build the move basis
  from the frozen yaw instead of `camera_pivot`'s. The rail swing and the wall-run yaw clamp should
  not fight a held free-look - free-look wins while Alt is down.
- The trail must not move the spring arm's origin in a way that feeds back into its collision cast
  (same trap `_camera_zoom_lift()` documents): trail the pivot, cast from the trailed pivot.
- Body-hide threshold: still keyed off `_camera_mode_length / camera_distance`. Re-check that
  `camera_zoom_min` (1.5) stays clear of the hide line at the new 1.7 m reference - a test asserts it.

## Not tested headlessly

How it frames and feels. Assert: the new defaults, neutral pitch with level mouse, world-referenced
clamp both ways, free-look freezing the move basis and easing back, the trail's settle time and welded
Y, the zeroed effects, the Alt/Caps Lock/R3 bindings.

## Tuning knobs, if it plays wrong

Not like the screenshot: `camera_distance`, `camera_pivot_raise`, `camera_neutral_pitch`. Too centred
or too far left: `camera_shoulder_offset`. Floaty: the trail time. Snap-back too slow/fast: the
free-look return time.

## Built (2026-11-10)

All in `scripts/pilot9.gd` unless noted. Not played yet.

- **Framing:** `camera_distance` 1.7, `camera_shoulder_offset` 0.25, `camera_pivot_raise` 0.4 -> **0.6**
  (pivot ~1.81 m at the 1.7 m zoom, about the top of his head), new `camera_neutral_pitch` -15. At
  neutral the eye is ~2.25 m up and ~1.64 m back. The neutral pitch lives in the **orbit** (pivot
  pitch), not the lens: `_ready()` and `exit_vehicle()` put the pivot there (`EXIT_PITCH` const
  removed; the exit lands on neutral now). Orbit, not lens tilt, is what puts the eye above and
  behind his head looking down.
- **Pitch clamp:** `_clamp_look_pitch()` / static `_clamp_world_pitch()` clamp orbit + zoom lens
  tilt (`_lens_pitch`) to 45 up / 60 down from the horizon, on mouse, stick, and every frame after
  the zoom framing writes the lens (so zooming at the limit cannot carry it past).
- **Free-look:** new action `free_look` (Alt, joypad button 8 / R3). `_handle_free_look()` runs at
  the top of `_physics_process`. Press freezes yaw + pitch; `_move_yaw()` returns the frozen yaw
  while held or returning, and every gameplay read of the camera yaw goes through it (move basis,
  first-person facing, head-on wall-run tangent, rail catch, `face_travel_direction = false`
  fallback). Release eases yaw + pitch back over `free_look_return_time` (0.25 s, smoothstep);
  look input is ignored during that ease. Rail swing and the wall-run yaw limit skip while
  free-look is active. Re-press mid-return keeps the original frozen heading. A frozen
  (uncontrolled) pilot drops free-look.
  - *Choice made at build:* the return restores the **pitch** from the press too, not just yaw
    (DayZ does). One line in `_step_free_look()` if it should keep the free-look pitch.
- **Walk** moved to Caps Lock (physical 4194329) in `project.godot`; the mech's walk follows.
- **Trail:** `_trail_pivot()` in `_process()`: critically damped spring (the existing
  `_camera_state_spring`) on pivot X/Z, `camera_trail_time` 0.1 s, Y welded. Snaps on the first
  frame, after an exit, after the (now off) dash lag, and on any jump > `camera_trail_snap_distance`
  (4 m - teleports, respawns). The spring arm is a child of the trailed pivot, so the collision cast
  starts from the trailed origin.
- **Effects zeroed, code kept:** `sprint_fov_boost`, `dash_fov_boost`, `camera_sway_vertical /
  lateral / roll`, `landing_dip_full_jump`, `landing_dip_max`, `camera_sprint_pullback`,
  `camera_crouch_drop`, `wall_run_camera_roll` all 0; new `camera_dash_lag` bool (false) gates the
  dash lag; new `reflect_fov_scale` (0) scales `kick_fov()`.
- **CAMERA MOTION row: kept** (the spec's recommendation, pending the user's call) - it still
  gates the mech shake, range hit shake, reflect spin kick and the hologram.
- **Tests:** new `tests/test_pilot9_camera_dayz.gd` (defaults + eye placement, neutral start, world
  clamp both ways, free-look freeze + return, trail settle/no overshoot/welded Y/teleport snap,
  zeroed effects, bindings). The sway, sprint FOV and dash FOV tests now set the old numbers on
  their rig so the kept code is still exercised; GTA/shoulder/mech tests updated to the new values.
