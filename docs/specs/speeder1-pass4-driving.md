# Speeder1 pass 4: Sparrow driving (2026-11-12)

Driving pass on the hover speeder ([speeder1.md](speeder1.md), [speeder1-pass2.md](speeder1-pass2.md)):
make it handle like Destiny 2's Sparrow. Grilled 8 questions, all agreed (every one on the
recommendation). Built 2026-11-12.

## Decisions

1. **Steering = A/D yaw plus momentum and automatic slide.**
   - World velocity is kept. `speed` stays "signed speed along the nose"; new `lateral` is the sideways
     part (+ = toward the rider's left, the body's +X).
   - Each tick the nose turns, then the sideways part is bled off at the grip rate and most of it is
     turned back into forward speed (`grip_conserve` 0.7, a slide keeps its speed).
   - Grip rate: `grip_high` 7/s (about 0.5 s to recover) normally, `grip_low` 3/s sliding. A slide
     starts above 60% of cruise speed with a hard turn (`slide_from_share` 0.6 -> `slide_full_share`
     0.85, times |steer|), eased at 6/s so grip never snaps.
   - No handbrake. S still brakes then reverses (reversing keeps the old flipped steer).
2. **Boost = hold Shift (the `sprint` action) on a meter.**
   - 80 m/s (`boost_speed`), 60 m/s^2 up to it, meter 3 s (`boost_time`) refilling over 6 s
     (`boost_refill_time`) after a 0.4 s idle (`boost_refill_delay`).
   - An emptied meter can only restart at 25% (`boost_restart`).
   - Releasing it eases the speed back to cruise over 2 s (`boost_decay` = 15 m/s^2).
   - Works in the air too (thrust along the nose).
   - Shown on a small bar bottom-centre (`scripts/speeder_hud.gd`) while he rides.
3. **Air = jump + momentum + a little yaw.**
   - Space on the ground: a 1.5 m hop (`jump_height`; v = sqrt(2 g h) with g = 9.8 x 1.5), no double jump.
   - Off a ramp or ledge the velocity is kept; in the air the nose yaws at 0.8 rad/s on A/D but the
     velocity does not follow it.
   - The nose pitches to follow the arc (clamped 34 deg) and levels out over the last 3.5 m to the ground.
   - Landing dip unchanged.
4. **Collisions.**
   - Glancing hit (the speed into the wall is under 50% of the speed, the Godot slide keeps the rest):
     scrapes along it, `scrape_drag` 0.8/s.
   - Head-on (into >= 7 m/s and share > 0.5): bounce `bounce_restitution` 0.3 of the speed into the wall
     back off it, the nose swings toward the wall's tangent (`_yaw_kick`), camera kick.
   - Floors, ramps and slopes steeper than 0.5 normal-y are never walls.
5. **Camera.**
   - The recentre heads for behind the TRAVEL direction (blended in from 3 to 9 m/s of ground speed,
     never reversing), not the nose, so a drift reads. Free-look and the 1.5 s recentre delay unchanged.
   - Boost pulls the camera back 1.2 m x size (`boost_pull`), adds 18 deg FOV (`boost_fov`) and a
     shake (`boost_shake`) that fades with the boost; a head-on hit adds a decaying kick.
6. **Boost effects**: the thrusters flare to 1.25 (`levels(..., boost)`), and `SpeederFire` gets a
   `Streaks` emitter: thin additive cyan-white bolts streaming back past the rider while boosting.
   Gated by MOVEMENT EFFECTS like the flames. (The pilot's own speed lasers are tied to his exports and
   his own physics, which is off while riding, so these are the bike's own.)
7. **Test course** `scripts/speeder_course.gd`, a code-built node `SpeederCourse` in trial at
   (150, 0, 0): its own slab (top at y = 0, 240 x 400), a second bike `Speeder2` at its start
   (stash key `speeder_course`), then: two ramps side by side (10 deg x 10 m, 15 deg x 20 m), a hill
   (6 deg up and down, 40 m each), a slalom of three staggered walls, a scrape corridor ending in a
   head-on wall. Boxes are `BlockoutBox`es (teal metre grid).
8. **Numbers**: cruise stays 50 m/s (2.5 s to it), brake 60, reverse 12, turn rates 1.9 / 1.1.

## Files

- `scripts/speeder.gd`: the drive (`step_speed(.., boosting)`, `slide_target`, `grip_rate`,
  `_step_boost`, jump, `_handle_hits`, air pitch, camera, effects).
- `scripts/speeder_fire.gd`: `levels(.., boost)`, `drive(.., boost)`, `Streaks`.
- `scripts/speeder_hud.gd`: new, the boost bar.
- `scripts/speeder_course.gd`: new, the test course.
- `scenes/trial.tscn`: `SpeederCourse`, `Speeder2` cel applier target.
- `tests/test_speeder.gd`: new tests. `tests/_probe_speeder_drive.gd`: slide, boost, jump and wall probes.

## Known gaps

- Not played. Every number is a first guess tuned by probes (slide angle, boost feel, jump arc).
- No banked turns on the course (boxes cannot make a cross-camber that is not a hump).
- Gamepad still not read (boost is the `sprint` action so a pad's trigger works, steering does not).
- The pilot's real speed lasers are not reused (see 6).
