# pilot9 reflect / parry (staff spin, pass 1)

2026-09-29. Grilled with the user the same day. Not yet built.

Long-term purpose: enemies will shoot projectiles at pilot, and he spins his staff in front of him to
reflect them. There are no enemies yet, so this pass builds the spin, the reflect zone, and a debug
emitter to play against. Real enemies, damage, and audio are out of scope.

## Decisions

- **Trigger:** new `reflect` input action, left mouse button or gamepad right trigger. Each press
  starts a fixed spin of `spin_duration` (0.6 s). It cannot be cancelled.
- **Recovery:** `recovery_duration` (0.4 s) after the spin ends before the next spin can start.
  Nothing else is locked during recovery.
- **Movement:** fully free during the spin (walk, run, sprint, jump, double-jump, dash). The spin is
  an upper-body overlay only.
- **Allowed states:** idle, walk, run, sprint, jump, fall, double-jump, dash. Blocked (press does
  nothing) in mantle, vault, ledge climb, wall-run, and rail grind. Slide/crouch are allowed if they
  do not fight the arm override; if they do, block them and note it under "Built".
- **Staff must be drawn.** A press while the staff is holstered (or no item is held) does nothing.
  The player draws with `R` (`equip`) first. No auto-draw.
- **Animation is procedural,** built on the existing arm-override `SkeletonModifier3D` from the held
  item system. No Blender clip and no `PILOT9.glb` change. Both arms extend forward, the staff
  spins in a vertical circle in front of his chest, with a short ease-in and ease-out. The grip stays
  fixed at the staff's center (no hands sliding). The circle's plane faces the camera direction, like
  the reference image.
- **Spin disc** (replaced the tip trail 2026-10-06, see "The spin disc" below): a flat 2D circle
  the size of the staff, locked to it, so the spin reads as a disc. White, low opacity. Gated by
  the MOVEMENT EFFECTS toggle.

## Reflect zone

- An `Area3D` on the staff/holder, in front of the chest, monitoring only while the spin is active.
- It affects any body or area in the `reflectable` group. It calls `reflect(direction)` on it and
  emits a `reflected(projectile, perfect)` signal.
- **Perfect reflect:** the hit lands within `perfect_window` (0.15 s) of the spin's start. The
  projectile is sent back at its shooter (`projectile.shooter`).
- **Normal reflect:** any later hit during the spin. The direction is random inside a cone of
  `random_cone_deg` (60 degrees) around the camera's forward aim.
- A projectile reflects once per spin. Reflecting flips it out of the `reflectable` group's "hostile"
  state so it does not hit him again.

## Feedback

- **Normal:** small white spark burst at the contact point.
- **Perfect:** a bigger burst, a brief FOV kick using the existing dash-FOV system, and a hit-stop of
  `hit_stop` (0.05 s).
- Sound: stub hooks only, the project has no audio.
- All of it gated by the MOVEMENT EFFECTS toggle where it is visual (the hit-stop and FOV kick are
  gated by CAMERA MOTION).

## Test rig

- `ReflectTestEmitter`: a debug node that fires test balls at pilot on a timer or on a debug key.
- The test ball is in the `reflectable` group, has a `shooter` reference (the emitter), a velocity, a
  `reflect(direction)` method, and despawns after a lifetime or on impact.
- Enemies later only need to put their bullets in the group and set `shooter`.

## Tunables (exports)

`spin_duration` 0.6 s, `recovery_duration` 0.4 s, `perfect_window` 0.15 s, `random_cone_deg` 60,
`hit_stop` 0.05 s, spark sizes, trail width and opacity, zone size, staff spin axis and ease times.

## Tests

- Press with the staff holstered: no spin starts.
- Press in each blocked state: no spin starts. Press in each allowed state: spin starts.
- A second press during the spin or recovery does nothing. After recovery it starts again.
- A projectile entering the zone in the first `perfect_window` returns to `shooter`.
- A projectile entering later reflects inside the cone around the camera aim.
- One reflect per projectile per spin.
- No reflect outside the spin (zone is off).

## Out of scope

Real enemies, damage, homing or aim-assist, audio, wall-run and rail-grind spins, auto-draw.

## Built

2026-09-30. Full suite green (858 tests). Files: `scripts/items/reflect_spin.gd` (the spin, the zone,
the trail, the rules), `scripts/reflect/reflect_projectile.gd`, `scripts/reflect/reflect_test_emitter.gd`,
`tests/test_pilot9_reflect.gd`, `tests/_probe_reflect_shot.gd` (windowed screenshot + timed-reflect
probe). Edited: `pilot9.gd` (`_setup_reflect`, `kick_fov`, input, holster cancels), `pilot9_vfx.gd`
(`reflect_burst`), `project.godot` (`reflect` action, physics layer 8 `reflectable`), `trial.tscn`
(the emitter at z = 10).

Departures from the spec above:

- **Gamepad is the right shoulder, not the right trigger.** The right trigger is already `sprint`.
- **The spin circle faces the way he faces, not the camera.** He turns toward his movement, so it
  matches the camera whenever he runs toward it and differs when he strafes.
- **Both arms are straight,** hands meeting a reach in front of the chest and 0.25 m below shoulder
  height (`hand_drop`). Solved at setup from the rig's rest pose, so a PILOT9.glb re-export cannot
  leave stale numbers. The elbow has no bend.
- **Blend in and out is one weight.** The arms and the staff share the pose modifier's influence
  (`pose_blend`, 0.1 s), so the staff slides from his hand to the spin and back with the arms.
  There is no separate settle timer.
- **The spin is four turns** (two until 2026-10-06) across the 0.6 s (`spin_turns`), with 0.08 s / 0.1 s speed ramps.
- **The hit-stop is `Engine.time_scale` 0.05** for `hit_stop` real seconds, and it is switched by
  CAMERA MOTION along with the FOV kick (8 degrees, 0.4 s). Sparks and the disc follow MOVEMENT
  EFFECTS.
- **Slide and crouch are allowed.** They looked fine in the probe; only mantle, vault, wall-run and
  rail grind (including a rail switch) block the press.

Gotchas kept for later:

- A Godot 4 bone pose is the whole local rotation, not an offset from rest. The held-item hold
  values are absolute too. Anything set through `set_bone_pose_rotation` has to start from
  `get_bone_rest()`.
- Editing project files with Python on Windows rewrites them as CRLF; the repo is LF.
  `test_settings.gd` reads `project.godot` and fails on CRLF.

Test rig: F7 fires one ball at him from the post at z = 10, F8 toggles auto-fire every 2.5 s
(off by default). Balls turn yellow on a normal reflect and green on a perfect one.

Not yet played: how the spin looks at speed, whether 0.6 s / 0.4 s / 0.15 s feel right, the trail's
opacity, and the hit-stop and FOV kick.

## The spin disc (2026-10-06)

Grilled and built 2026-10-06. The tip trail smeared into spirals whenever he moved, and the staff
looked slow. Decisions:

- **2x faster:** `spin_turns` 2 -> 4, in the same 0.6 s. Duration, ease times, recovery and the
  perfect window are unchanged.
- **The trail is gone** (`_draw_trail`, its `ImmediateMesh`, and the `trail_*` exports).
- **The real staff stays visible** and keeps spinning; the disc sits on top of it to hide the strobe
  (at peak it turns ~45 degrees a frame).
- **Look: a blur disc.** A faint fill, a brighter rim where the tips run, and a smear wedge trailing
  each tip, which sweeps with the staff. `shaders/cel/vfx/spin_disc.gdshader`: unshaded, additive,
  white, on a `QuadMesh` (`SpinDisc`, a top-level child of `ReflectSpin`).
- **Locked exactly to the staff:** every rendered frame the quad takes the staff's own transform
  (centre, plane, angle), scaled to `tip_distance`. No smoothing, so they can never drift apart; it
  bobs with his run, and the one-armed sprint spin needs nothing extra.
- **Fades with spin speed:** opacity = `spin_speed_fraction()`, the angle curve's slope as a
  fraction of peak: up over the 0.08 s ease-in, full through the middle, down over the 0.1 s
  ease-out.
- Tunables: `disc_alpha` 0.35, `disc_rim` 0.6, `smear_length` 120 degrees (Feedback group).
  The fill (0.06) and rim width are shader uniforms.

Checked with `tests/_probe_reflect_shot.gd`: face-on from behind it is a circle exactly the staff's
size with the wedges behind each tip; side-on it is a thin ellipse on the staff. The first pass had
the fill at 0.15 and squared wedges, which read as an even bubble; the fill went to 0.06 and the
wedge falloff to ^1.5.

Not yet played: whether 4 turns reads well, the disc's opacity, and the wedge length.

**2026-10-12:** the spin is always one-armed now, standing included. The two-armed pose held the
staff at his hip, and the user wanted it raised like the sprint one. `solve_reach()` and the
two-arm pose are still built but no longer chosen. The staff's `hand_offset` grip also moved from
(0, 0.08, 0.03) to (0, 0.01, 0) in RightHand's frame, which is the end of the forearm. The
decimate pilot has no hands, and the staff was floating where the fist used to be.
