# Speeder1 pass 2 (2026-11-12)

Fine-tuning pass on the hover speeder ([speeder1.md](speeder1.md)). Grilled 8 questions, all agreed
(the last four on the recommendation). Built 2026-11-12.

## Decisions

1. **Nothing moves while he gets on or off.**
   - The bike is dead still: speed, velocity and the parked bob are held. The hover spring keeps its
     height. His own capsule is off from the moment RIDE is pressed, so he cannot nudge it.
   - He always boards from, and is put down at, the same spot: the ground beside the saddle on his
     left, `mount_spot` (1.35, 0, -0.60) in the body frame.
   - Right, then behind, only if the left is blocked.
   - Pressing RIDE from anywhere first walks him to the spot over 0.25 s (skipped when he is already
     within 0.25 m of it), then the leg swing runs.
2. **Size 1.5x** (`size_scale`).
   - What scales: the model, the hull's collision box, the interaction sphere, the ground rays,
     the camera distance and height, the prompt anchor, and the bob and dip.
   - Top speed scales with it, so the sense of speed is kept:
     - 37.5 m/s, 2.5 s to get there
     - brake 45, reverse 9, coast drag 4.5
     - turn rates unchanged
   - Hover height stays 0.45 (the hull underside is about 0.55 over the ground).
   - The rider points (seat, grips, pegs, mount spot) are in metres AT size 1.5. Retune them if
     `size_scale` changes.
   - The size is "fitted to the pilot" by the probe sheets: seat at (0, 0.86, -0.60), hips about
     1.3 m over the ground.
3. **Speed-dependent motorcycle riding.**
   - Upright at a crawl (hip 10° + spine 20°), the full sport tuck at speed (hip 20° + spine 46°,
     plus up to 8° more at top speed). Blended by a smoothstep from 15% to 70% of top speed, eased at
     4/s. He sits upright while getting on or off.
   - The bike banks up to 35° (was 25°). He leans a further 10° into a full turn (was 5°).
   - The inside knee drops out up to 0.12 m in a full turn at speed.
4. **Leg swing.**
   - Mount: 0.55 s after the walk. The far foot arcs 1.0 m over the saddle, the near foot 0.15 m, the
     hips rise 0.25 m at the midpoint. The pose layer blends in over the first 40% of the swing.
   - Dismount: the same swing backwards over 0.5 s. He is put down on the spot at the end
     (`end_ride`), not at the start. The spot is fixed when the hold completes.
   - The F-hold rule is unchanged (0.6 s, at a crawl, on the ground).
5. **Thruster fire, PS1 style** (`scripts/speeder_fire.gd`, built in code under `Tilt`).
   - Per nozzle: three nested hexagonal flame cones (flat colours, additive so the overlap goes hot).
     They are redrawn at 12 fps: a new length jitter and a half-turn twist every step, no smooth
     wobble.
   - Plus 24 hard-edged cube sparks per nozzle that step yellow -> orange -> red -> dark red (a
     constant gradient) and shrink away. They are left in the world, so the bike draws a spark line
     behind it at speed.
   - A small orange light behind the engines.
   - Two nozzles at (±0.255, 0.315, -1.23) at size 1: the `engines` surface of the model.
   - The whole thing is gated by MOVEMENT EFFECTS.
6. **Thruster behaviour** (`SpeederFire.levels()`, a pure function):

   | State | Level |
   |---|---|
   | nobody on | dark |
   | rider on, parked | 0.14 flicker |
   | coasting | 0.14 to 0.45, growing with speed |
   | throttle | 0.6 to 1.0, growing with speed |
   | brake / reverse | 0.05 |
   | turning | the outside nozzle x1.5, the inside x0.4 (D flares the left nozzle) |

   Flame length = 1.5 m x size x level at most. Level eases at 14/s up, 8/s down.

## Files

- `scripts/speeder.gd`: size, boarding (`mount`, `dismount`, `step_boarding`, `boarding_progress`,
  `transition_active`, `exit_spot(ignore)`), rider placement with the walk and swing, tuck easing,
  fire driving.
- `scripts/speeder_ride_pose.gd`: `tuck_share` blends the upright and tucked hip / spine angles.
- `scripts/speeder_fire.gd`: new.
- `tests/test_speeder.gd`: 25 tests. The old numbers moved (37.5 / 45 / 9 / 35°) and eight new
  ones cover size, stillness, the fixed spot, the walk, the reversed swing, the tuck and the fire.
- `tests/_probe_speeder_ride.gd`: new states `swing0 / swing3 / swing5 / swing7` (frozen mid-swing)
  and a throttle input; the camera sits further back for the bigger bike.

## Tunables

`speeder.gd`: Size, Rider (`tuck_from_share`, `tuck_full_share`, `knee_out`), Boarding
(`mount_spot`, `mount_walk_time`, `mount_swing_time`, `dismount_swing_time`, `swing_hip_lift`,
`swing_leg_arc`). `speeder_fire.gd`: the consts at the top (`STEP`, `MAX_LENGTH`, `GIRTH`, `LAYERS`,
spark palette, count, size).

## Known gaps

- The swing is checked in probe sheets and by progress / position tests, not played.
- A dismount that falls back to the right or behind (left blocked) pops to that spot at the end of
  the swing, since the swing always plays out on the pilot's mount side.
- The fire light and sparks have not been looked at under every LOOK (RETRO / COMPOSITE / AIRFRAME).
- Gamepad is still not read.

## Pass 3 (2026-11-12): 2.0x

Grilled 4 questions. `size_scale` 1.5 -> 2.0.

- Rider points were first left alone ("fitted to him"); played, he sat sunk inside the hull. REVERSED:
  they now scale x4/3 with the bike (seat (0,1.15,-0.80), grips (+-0.60,1.16,0.07), pegs
  (+-0.60,0.51,-0.44), mount spot (1.8,0,-0.80), swing lift 0.33, leg arc 1.33, coat plane 0.4).
  Probe-shot: he sits on top, hands on the grips, feet down to the pegs.
- Speed scales with size: 50 m/s, acceleration 20 (2.5 s), brake 60, reverse 12 (accel 12), coast
  drag 6. Turn rates unchanged. Hover height stays 0.45.
- Map unchanged. Collision stays honest (box 6 m long, interaction sphere 5.2 m); snags are reported,
  not hidden by a smaller hitbox.
- Tests updated to the new numbers; probe camera pulled back for the bigger bike.
- Parked / crawl posture leans further forward: upright hip 10 -> 15 deg, spine 20 -> 34 deg
  (full tuck still 20 / 46, so the test's upright < tucked still holds).
- Parked arms keep a bend: `seat_forward_upright` 0.18 m scoots him forward on the saddle at tuck 0,
  easing to nothing by the full tuck (hips closer to the grips so the two-bone arm is no longer
  fully stretched).
- 2026-11-12 seat/bars fit from the mesh itself (vertices of the `seat` and handlebar prongs, size 2.0):
  saddle pan z -0.2..-1.4, surface y ~0.95; bar ends at x +-0.5, z -0.12, y 1.10. Seat is now
  (0, 1.12, -0.85), grips (+-0.50, 1.10, -0.12). The parked scoot-forward (`seat_forward_upright`)
  is 0: it perched him on the cowl, off the seat; the arm bend now comes from the grips being closer.
