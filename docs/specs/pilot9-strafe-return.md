# pilot9 — strafe locomotion returns (backpedal)

2026-11-11. Grilled with the user, then built the same day.

## Why

Since turn-to-face (docs/specs/pilot9-turn-to-face.md, 2026-09-07) pilot9 always turns to face
where he travels, so S runs him toward the camera and only `run_forward` ever plays in steady
state. The user wants stock Real Controller back: S backpedals, A/D strafe, and the camera's
forward is his forward. That also gives the DayZ free-look (Alt / R3,
docs/specs/pilot9-dayz-camera.md) a job: while held, his body and movement stay where they were,
and the camera swings round him.

## Decisions (from the grill)

| # | Question | Answer |
|---|---|---|
| 1 | Walk / run facing | Camera-forward, all 8 directional clips (stock RC) |
| 2 | Sprint | Stock RC: camera-forward, `sprint_left`/`right` on A/D; any backward component drops him to the run gait and `run_backward*` until S is released (sprint toggle itself stays on) |
| 3 | Crouch walk | Faces travel (one forward-only clip, no crouch idle) |
| 4 | Jump / fall / land | Camera-forward (air strafes) |
| 5 | Body lean | Direction-aware: the speed-change lean is aimed along travel and split onto his body - front/back part is pitch, side part is roll - plus the existing turn roll |
| 6 | Switch? | Replaces face-travel. `face_travel_direction` stays as an export, default `false`; `true` gives the old behaviour everywhere. No menu row |

Not a decision, forced by the clips: slide, dash, vault, mantle, wall-run, wall-climb, rail ride
and rail switch keep their own facing (all forward-only clips; most were already welded). The
tredge also keeps facing travel (forced wade, one clip). When any of these ends he turns back to
camera-forward at `rotation_speed` (10, about a quarter second for a 180).

## Design

### Facing - `pilot9.gd`

- `face_travel_direction` default `true` -> `false`. Its meaning changes from "the control model"
  to "face travel in every state" (the old behaviour, kept for comparison).
- New `_faces_travel() -> bool`: `face_travel_direction or is_crouching or is_tredging`.
- `_handle_character_rotation`: the final lerp target is `atan2(direction)` when
  `_faces_travel()`, otherwise `_move_yaw() + PI` (stock camera-back, already there). Free-look
  is automatic: `_move_yaw()` is frozen while it is held.
- Vault gets an explicit branch before the input gate: lerp toward `_vault_dir`. Before this it
  fell through to face-travel, which happened to point the same way; under strafe it would turn
  him to the camera mid-vault.
- `_requested_speed`: `is_sprinting` also needs `_faces_travel() or input_dir.y <= 0` - a sprint
  with any backward component is a run, speed and clip both (otherwise `run_backward` would play
  at sprint speed and skate). `sprint_toggled` is untouched, so letting go of S sprints again.

### Animation - `pilot9_animation.gd`

- `_travel_blend()` always uses the body-frame formula (travel projected onto his yaw). In
  strafe steady state the body sits at camera-back, so this equals stock RC's input-space feed;
  while he is still turning back from a slide/dash/crouch it is more honest than input space (no
  moonwalk on the turn-back).
- The SpeedBlend gate reads `player._faces_travel()` instead of the flag. With the speed gate
  above it is redundant but keeps the clip and the speed agreeing if either changes.

### Body lean - `pilot9.gd::_body_lean_target`

- `gap = speed - felt_speed` stays scalar (so a constant-speed carve still pitches nothing).
- New tracker `_lean_travel_dir`: last horizontal travel direction, updated while speed > 0.1 m/s,
  so a stop still knows which way it was stopping from. Reseeded with the rest.
- Lean vector = `gap * _lean_travel_dir`. Pitch = its component along his forward (forward cap if
  positive, back cap if negative, same `pitch_full_gap` and peak fraction). Side roll = its
  component along his left, `roll_max` cap over the same full gap and peak fraction, toward the
  side of the change. Roll = clamp(turn roll + side roll, +-roll_max / f).
- Running forward this is exactly the old maths, so every existing tunable and test holds.

## Tests

- `tests/test_pilot9_turn_to_face.gd`: rewritten as the facing-rule test - default is strafe,
  walk/run/air weld to camera-back, crouch and tredge face travel, vault faces `_vault_dir`, the
  flag restores face-travel everywhere, body-frame blend equals input space at steady state, and
  a backward sprint is a run.
- `tests/test_pilot9_body_lean.gd`: + backpedal start pitches back, backpedal stop pitches
  forward, strafe start rolls toward the strafe, carve still holds no pitch.
- `tests/test_pilot9_camera_dayz.gd`: the "control model unchanged" check now asserts strafe.
- `tests/test_pilot9_slide.gd` already sets the flag explicitly.

## Not in scope

Crouch strafe clips (needs a Mixamo export), the CAMERA MOTION row question, anime cycles.
