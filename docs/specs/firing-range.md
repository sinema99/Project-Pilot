# Firing range

2026-10-07. Grilled with the user, then built the same day. The place combat gets tested: hit
results, new attacks, the reflect.

## Decisions

- **The laser** is a travelling bolt (an elongated streak, 28 m/s), not a hitscan beam, so it meets
  the existing reflect contract (`reflectable` group, `shooter`, `reflect()`). A charge-up flash on
  the box (0.45 s) comes before every shot.
- **Pilot is hit: feedback only.** Mesh flash (white 0.07 s, then red fading), spark burst at the
  contact point, small camera shake, red edge vignette. No health, knockback or stun; his movement
  is never touched. The flash and vignette always play; sparks follow MOVEMENT EFFECTS, the shake
  follows CAMERA MOTION.
- **The dummy cannot die.** One generic hook, `take_hit(amount, kind, point)`, is how anything hurts
  it; reflected bolts use it now, future attacks call the same method. A perfect reflect deals 50
  and shows `PERFECT 50`; a normal reflect deals 20. Reaction: white flash, white sparks, a short
  wobble of the mesh (never of its path), a floating damage number.
- **Movement:** it faces pilot and circles him (strafe perpendicular to the line between them,
  4 m/s), holding 14 m (backs off if he closes in, creeps in if he retreats; 1.5 m dead band). It
  reverses on a random 1.5-3 s timer and at the slab edge, and stays on the slab.
- **Firing:** every 2-3 s (random), only with a clear line to him (a blocked shot retries in 0.3 s).
- **The slab:** 50 x 50 m, flat, a 0.5 m rim (gapped at the entrance), floor markings, an 8 m wide
  85 m causeway running out of the +Z edge. Dormant until pilot steps on (power-on flash, 1 s
  before the first shot); dormant again when he leaves, with every bolt in flight cleared. The HUD
  totals persist across leaving.
- **Range tools:** a corner HUD while he is on the slab (damage dealt, hits on the dummy, hits
  taken, reflects perfect/normal, DPS over 3 s). F9 resets the stats, F10 fires one bolt now, F11
  freezes or unfreezes the dummy.
- The old `ReflectTestEmitter` (F7/F8) is untouched.

## Built

Files: `scripts/range/firing_range.gd` (`FiringRange`: the generated slab, trigger, HUD, hotkeys),
`range_dummy.gd` (the box, an `AnimatableBody3D`), `range_bolt.gd`, `range_stats.gd`,
`pilot_hit_feedback.gd`; `scenes/firing_range.tscn`; `tests/test_firing_range.gd`;
`tests/_probe_range_shot.gd` (windowed: steps on, waits for it to wake, reflects a bolt perfectly,
shoots frames to `screenshots/firing-range/`).
Edited: `pilot9.gd` (`take_hit`, `hit_taken`, `spark_burst`, `hit_feedback`, camera shake added to
the sway offsets), `pilot9_vfx.gd` (`impact_burst`, a tinted `reflect_burst`), `trial.tscn` (the
range at world (0, 0, -150), slab z -175..-125, causeway from -125 to -40), `project.godot`
(physics layer 9 `range_dummy`).

Departures from what was grilled:

- **A perfect reflect homes.** The first build sent the returned bolt straight at where the dummy
  was; it strafes 4 m/s, so it missed every time (the probe showed 0 damage). A perfect-reflected
  bolt now steers onto the shooter's chest (`PERFECT_HOMING` 6 / s). A normal reflect is unchanged:
  a random throw in the 60 degree cone, so it mostly misses by design.
- The dummy's `sync_to_physics` is off: with it on the node's transform did not update until a
  physics tick, so reading `global_position` was a frame stale. Pilot is not carried by it.
- The slab sits 150 m from the spawn, with a causeway. Drag `FiringRange` in `trial.tscn` closer if
  the run is a bother.

Tunables are exports on the dummy (range, strafe speed, reversal time, fire interval, charge time,
wake delay, bolt speed, damage), and consts on the bolt and the feedback node.

## Checked

`tests/test_firing_range.gd`: stats and the DPS window, range velocity and bounds, dormant start,
wake and sleep (bolts cleared), the wake delay, frozen holds still, facing and staying in bounds,
hits reported and counted, the bolt's reflect contract, the bolt hurting only the right target, the
homing, the feedback curves, the HUD text. Full suite: only four failures, all pre-existing and
unrelated (habitat owner check, two menu-refresh, one pixel-look). The windowed probe confirmed it
wakes on step-on, fires, the reflect lands (one perfect, 50 damage, HUD updated), and it sleeps and
clears bolts when pilot leaves.

Not yet played: how the timing feels (28 m/s, 0.45 s charge), the strafe pattern, the flash and
vignette strengths, the shake size, the homing strength.
