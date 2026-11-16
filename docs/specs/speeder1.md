# Speeder1 (2026-11-12)

A drivable hover speeder bike in trial. The user modelled it in Blender (`speeder1.glb`): two objects,
the bike and a stack of cargo boxes on its back. The boxes are a separate object so they can show
and hide with the bike's stash. pilot9 rides it in a sport tuck that is built in code, because there
is no riding animation. Grilled 2026-11-12.

Status: built 2026-11-12.

## Decisions

1. **Drivable**, not a parked prop. Arcade hover only: no jumps, boost or combat.
2. **A/D steer the bike, the mouse looks freely.** W is throttle; S brakes, then reverses. The
   camera trails behind and eases back after 1.5 s without mouse input.
3. **25 m/s top speed**, reached in 2.5 s. S brakes at 30 m/s². Reverse is capped at 6 m/s. No
   boost. All of these are exports.
4. **Ground and edges.**
   - It hovers with its body origin 0.45 m above the ground (hull underside about 0.52 m). Five
     ground rays feed a spring. It tilts to match ramps, smoothed.
   - It flies off ledges and keeps its speed. Gravity in the air is ×1.5. No steering or throttle
     while airborne. It lands with a dip.
   - It can't climb anything taller than about 0.5 m (the collision box starts 5 cm above the
     origin).
   - It slides along walls and loses the speed going into them. No crashes or damage.
   - Below y −40 it respawns at its parking spot. A rider comes with it (stays on).
5. **On and off: same as EXIA.**
   - On foot, the panel offers RIDE over STASH; the wheel picks and F confirms.
   - RIDE lerps pilot onto the seat over 0.3 s while the pose layer blends in. No climb animation.
   - STASH opens the inventory screen in STASH mode without getting on.
   - Aboard, Tab opens the stash. Holding F for 0.6 s dismounts. The hold bar only fills while the
     bike is on the ground and below 2 m/s; above that it sits empty until the bike slows.
   - Drive input is cut while F is held.
   - He is put down on the bike's left side, facing along the nose. If the left is blocked, the
     right side, then behind; if nothing is clear, the left anyway.
6. **Stash: 8 × 6**, its own grid. It lives on the `Inventory` autoload, keyed by the speeder's
   `stash_key`, so it lasts the session like EXIA's (survives scene changes, gone on quit).
   - It starts with a battery and a ration (TEST CONTENT in `speeder.gd`).
   - The **Boxes** mesh shows exactly while the stash holds at least one item. It updates live
     off `ItemGrid.changed`, including while the screen is open.
7. **Sport tuck.**
   - Chest low behind the windscreen, back angled forward, knees forward against the front hull,
     feet tucked beside the hull under the seat's front.
   - Hands on the two stubs either side of the screen; these are the grips.
   - In-engine bone rotations plus two-bone IK, no clip.
8. **In motion.**
   - The bike banks up to 25° into turns, scaled by speed (full at 60% of top speed) and steer.
   - It pitches 3° nose-up under throttle and 4° nose-down braking, with a 2 cm bob when parked.
   - Rider:
     - his upper body hangs 5° further into turns
     - 6° more spine pitch at top speed (about 5 cm lower)
     - his head turns toward the camera, up to 60° each side
     - his hips follow the landing dip at 35%
   - The staff is holstered on mount (a spin or draw mid-way is finished or cancelled).
   - The trench coat stays on. It feels the bike's velocity, and a plane at 0.2 m (body frame)
     keeps it draped over the hull instead of hanging to the ground.
9. **Camera.**
   - 4.5 m behind, centred, aimed at a point 1.4 m above the bike's origin. Orbits freely.
   - It recentres behind the bike after 1.5 s without mouse input.
   - FOV widens by up to 10° and the camera falls back up to an extra 1 m at top speed.
   - 0.4 s smooth-eased handover from the walking camera to the bike camera and back.
10. **Placement.** `Speeder1` in trial at (−4, 0.45, 4), nose toward +Z.
    - Both pilots can ride it; pilot switching is already refused while one is in a vehicle.
    - It's reusable (`scenes/speeder.tscn`).
    - It's dressed by `ApplyCelMech` like EXIA and the Vanguard.

## Deviations from the grill

- **Placement:** the grill agreed on about (6, 0, −8). The rail test's S-curve runs right through
  that spot, so the bike moved to (−4, 0.45, 4), still a few metres from spawn.
- **Recentre speed:** the recentre only runs above 2 m/s (`recenter_min_speed`). Parked, the view
  stays where you put it, which is how GTA bikes behave.
- **Footpegs:** the bike has no footpeg geometry. The feet rest against the hull sides under the
  front of the seat (the hull pinches in there), with the knees forward against the hull. A sport
  tuck with feet back near the engines put the pegs 0.3 m from the hips, and the knees folded out
  sideways about 0.6 m.
- **Grips:** the stubs sit at hip height right in front of the seat. A deep tuck would leave the
  arms folded. The tuck is about 49° (15° pelvis + 34° spine) with elbows bent back and slightly
  out.

## Files

- `assets/speeder1.glb`: the export. The boxes are found by their `boxes` material, so object
  renames don't matter.
- `scenes/speeder.tscn` + `scripts/speeder.gd`:
  - body, drive, hover, panel bids, mount / dismount, stash, boxes
  - `Tilt` (top_level visual root), rider placement, camera, handover
- `scripts/speeder_ride_pose.gd`: the tuck. It's the last SkeletonModifier3D on his skeleton:
  rest reset, pelvis / spine / neck / head, arm and leg IK via `tredge_pose.solve_arm`.
- `scripts/pilot9.gd`: `begin_ride()` / `end_ride()`, `riding`, `ride_pose`, and `_ride_hold`
  folded into `frozen`.
- `scripts/inventory/inventory.gd`: `vehicle_stashes`, `vehicle_stash()`, `stash_of()`.
- `scripts/ui/inventory_screen.gd`: `stash_grid()` / `stash_title()`. The stash box and the
  portrait title come from the vehicle.
- `scenes/trial.tscn`: the `Speeder1` instance and the `ApplyCelMech` target.
- `tests/test_speeder.gd` (17 tests).
- Probes:
  - `tests/_probe_speeder_drive.gd` (headless, real physics)
  - `tests/_probe_speeder_ride.gd` (windowed pose sheets)
  - `tests/_probe_speeder_mesh.gd` (the bare mesh)

## Tunables

- `speeder.gd` exports:
  - Drive, Hover and Look groups
  - Rider: `seat_point`, `grip_left/right`, `peg_left/right` in the body frame (+Z nose, +X his
    left), lean, tuck, head turn, dip share, `mount_time`, `coat_plane_height`
  - Exit, Camera
- `speeder_ride_pose.gd` exports: `hip_pitch_degrees`, `spine_pitch_degrees`, `look_up_share`,
  shoulder roll, wrist / toe angles, `elbow_pole`, `knee_pole`.

## Re-exporting speeder1.glb

Copy over `assets/speeder1.glb` and reimport. Then check:

- **Boxes:** still a separate object wearing the `boxes` material.
- **Orientation:** the nose is still the file's −X. The Model is turned +90° about Y.
- **Seat, grips and pegs:** if the seat or grips moved, re-measure them:
  1. Read the vertex bounds per material.
  2. Re-shoot `tests/_probe_speeder_ride.gd`.

## Known gaps

- Keyboard only (W/A/S/D read as keys, like EXIA). No gamepad.
- No sound and no engine VFX.
- The coat can clip the rear side pods a little when parked.
- The cargo boxes are a single mesh: on with any loot, off when empty, not one box per item.
