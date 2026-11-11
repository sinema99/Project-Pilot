# Knight boss - moveset

Status: specced and built 2026-11-09 (grill of 10, every recommendation taken). Not yet played.

The Knight (docs/specs/knight-boss.md) gets moving: he floats (he never walks), wakes when pilot
comes near, and fights with three moves - a laser, a missile volley and a smash. Each move has its
own body animation. This pass is the moveset only: no health on either side.

## Decisions

1. **Scope: moveset only, hits are feedback.** Every hit calls pilot9's `take_hit()` (white/red
   flash, sparks, shake, red vignette). No pilot HP, no boss HP, no death or phases - the fight loop
   gets its own grill once the moves feel right.
2. **Animation: key poses in code.** Each move is a timed list of key poses (windup, strike, hold,
   recovery), each a bone-rotation table like the drawing pose, blended on eased curves. His root
   motion (flying, diving, rising) is code too. No Blender.
3. **Floating.**
   - Bob 0.15 m on a 2.5 s cycle; legs hang loose, the robe sways a little.
   - Holds ~18 m from pilot: backs off if pilot closes, follows if pilot runs.
   - Slowly circles to one side (~4 m/s), switching direction every few seconds.
   - Cruises 2-4 m up (sabaton tips over the floor), rising and sinking a little.
   - Always turns to face pilot; leans into his drift (forward advancing, back retreating, banked
     on a strafe).
   - Leash: stays within 60 m of `BossAnchor`.
4. **Choosing.** 2.5-4 s of floating between attacks. Distance weights the pick: under ~10 m the
   smash is likely, 10-30 m the laser, past 30 m the missiles. Never the same move three times in a
   row.
5. **Start.** Dormant in the drawing pose until pilot is within 40 m, then a ~1.5 s wake (head up,
   out of the pose, rises a metre, arms spread), then the AI. He never goes back to sleep.
6. **Laser** (not reflectable).
   - Windup 0.9 s: right claw draws back to the chest, then thrusts out; a thin red aim line from
     the claw tracks pilot.
   - Lock 0.3 s: the line stops tracking, flashes white, thickens.
   - Fire 0.6 s: a thick beam (0.8 m) along the locked line, out to 80 m, stopped by walls; hits at
     most once. The recoil shoves him ~2 m back, robe whipping back.
   - Recovery 0.8 s: arm drops, shoulders sag.
7. **Missiles** (reflectable).
   - Windup 0.8 s: rises ~3 m, both arms sweep overhead, back arches.
   - Launch 0.6 s: 6 missiles, one per 0.1 s, fanned up and out from his back/shoulders; his arms
     snap a little higher on each.
   - Each climbs ~10 m, curves over, then homes on pilot at 16 m/s, turning at most ~100 deg/s:
     a dash or hard cut makes them overshoot; the stagger makes them arrive as a ripple.
   - Recovery 1.0 s: sinks back to cruise, arms down.
   - A missile dies on pilot, the floor or a wall (small burst), or after 7 s.
   - Reflect contract (`reflectable`, `shooter`, `reflect()`): a normal reflect knocks it away, a
     perfect one sends it back to hit the Knight (flash + sparks, feedback only).
8. **Smash.**
   - If pilot is over 25 m away he first flies at pilot (~1 s).
   - Rise 0.7 s: up to ~8 m over pilot, both claws gathered overhead, curling forward.
   - Mark 0.6 s: a 6 m red ring on the floor under pilot follows him, then locks and flashes white.
   - Dive 0.45 s: slams down onto the locked spot, claws first, robe streaming up.
   - Impact: within 2.5 m of the centre is hit at once; then a shockwave ring expands to 6 m over
     0.3 s and hits pilot only if he is on the ground when it passes (a jump clears it). Floor
     burst (dust/snow), crack decal, big camera shake even on a miss.
   - Stuck 1.5 s: claws in the floor, hunched - the biggest opening. Then heaves back to cruise.
9. **Debug keys, arena only.** F7 laser, F8 missiles, F9 smash (fire now, waking him if dormant;
   no distance rules, but the smash still flies in first when far). F10 freezes/unfreezes the AI
   (he keeps hovering, never picks). F11 resets him to dormant on the anchor. The F6 idle-clip
   toggle is retired.
10. **Look.** Hostile red (the range bolt's) with white-hot cores: laser white core + red glow,
    missiles red shards with dark smoke, smash ring red flashing white at lock, pale dust/snow
    burst. One telegraph rule: red tracks you, a white flash means locked. MOVEMENT EFFECTS hides
    only the cosmetic extras (dust, smoke, sparks), never telegraphs, beams or missiles.

## Build

- `KnightBody` (scripts/boss/knight_body.gd) gains a pose layer: a pose table is turned into local
  bone rotations once (`solve_pose`), and the body shows a blend of two solved poses
  (`show_blend(a, b, t)`). The F6 idle swap and its clip are removed. He gets `take_hit()` (white
  flash overlay + red sparks) and a `homing_height` so a perfect reflect steers onto his chest.
- `KnightPoses` (scripts/boss/knight_poses.gd): every key pose as a table, same format as the
  drawing pose.
- `KnightBrain` (scripts/boss/knight_brain.gd), a child of the Knight built by the arena: states
  DORMANT, WAKE, FLOAT, LASER, MISSILES, SMASH; each attack a list of timed phases. Drives his root
  transform (position, facing, lean, bob) and his pose. Pure helpers (`pick_move`, `beam_hits`,
  `smash_hits`, `wave_hits`, `turn_toward`) are static so the suite can test them without physics.
- `KnightLaser`, `KnightMissile`, `KnightSmash` (scripts/boss/): the attack visuals and hits.
- `BossArena` hands the brain pilot, the anchor and the floor height.

## Checks

`tests/test_knight_moveset.gd` (headless; the brain is stepped by hand): dormant until 40 m, wake
then float, float range/leash/height/facing, the pick weights and the no-three-in-a-row rule, each
move's phase timings, the laser's lock and once-only hit, missiles' count, turn cap, lifetime and
reflect contract, the smash's mark lock, inner hit and jump-clears-the-wave rule, debug keys, F6
gone. Look and timing judged from probe shots (`tests/_probe_knight_moves.gd`, windowed).

## Built (2026-11-09)

As specced; numbers are exports on `KnightBrain` (Waking / Floating / Choosing / Laser / Missiles /
Smash groups), `KnightMissile` and `KnightLaser`. Notes and departures:

- **Pose authoring rule:** a hanging arm (BACK +-80 first) swings forward about RIGHT, not UP.
  KnightPoses' header says so.
- **Smash stuck height** is measured once at setup (claw tips in the stuck pose, 0.15 m into the
  floor). The dive/stuck poses pitch him 60-70 deg forward with arms straight down so his knees stay
  clear of the floor; there is no extra root lean in the dive.
- **Smash phases** add a 0.8 s heave after the 1.5 s stuck (spec: "then heaves back to cruise").
- **Missile hits** go through pilot's hurtbox (layer 2) like the range bolt; a reflected missile hits
  the Knight by distance to his chest (`homing_height`), so he needs no hitbox yet.
- **Beam length** is a ray against the world (1) and the stop-only wall (10), pilot excluded.
- **Smoke and bursts** are low-poly balls (quads read as square chips in the cel look).
- **Smash shake** uses the new `PilotHitFeedback.shake()`, scaled by distance, felt within 35 m.
