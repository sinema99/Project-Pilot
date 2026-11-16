# pilot9 trench coat: leg drape + dirty hem

Grilled 2026-11-16 (8 questions, every recommendation taken except the lining). Follows
docs/specs/pilot9-trench-coat.md and docs/specs/pilot9-coat-wear.md.

## What the user asked for

- The bottom of the coat clips with his feet running, sprinting, crouching and kneeling - worst in
  the kneel, where it goes "crazy" through the leg.
- The bottom of the coat dirty, to match the grunge on his legs.

## Decisions

| # | Question | Answer |
|---|----------|--------|
| 1 | Shorten the coat? | **No.** Mid-calf stays (hem 0.30 m). Fixed with motion. |
| 2 | Kneel | **Drape over** his legs: front panels over the raised left thigh, back panels over the kneeling right shin, the hem resting on the floor. Settles over the kneel's own 0.25 s. |
| 3 | Crouch jog | **The same drape, live**: panels ride his pumping thighs. The fixed 9 deg crouch pool goes. |
| 4 | Scope | **One rule everywhere**: no panel ever passes inside either leg - thigh, shin or boot - in any state (a kicking heel lifts the back hem over itself). Coat tick cost held at today's ~0.2 ms. |
| 5 | Which looks get dirt | **AIRFRAME only** (where his leg grime lives). |
| 6 | How high | **A ~20 cm band**: heaviest at the hem edge, gone by ~0.50 m (rest height). His legs' grime colour, clumps and 3 steps. |
| 7 | Existing hem wear | **Drop the light rubbed hem edge, keep the dark leather band** under the dirt. |
| 8 | Lining | **Stays clean.** |

## How it is built

- `trench_coat.gd`: the old leg clearance (sample points, chain wedges, outward-only swing, 40 deg
  cap, off in crouch/slide) and the crouch pool are replaced by **leg capsules**: per leg a thigh,
  a shin and a boot capsule with an elliptical cross-section (thin to his side, deep front/back),
  built from the posed bones every tick. Each coat segment (both halves of all 8 chains) is turned
  about its pivot until it is clear of every capsule by `leg_margin`. The way out is the nearest
  side of the leg unless that is the inside of the coat, then it is outward-and-up (so the cloth
  goes OVER a leg, never under it). The floor and wall planes still win after it, and the spring
  loses its velocity into the leg. A second pass after the neighbour/hinge blend catches any
  segment the blend moved back into a leg.
- `ps1_surface.gdshader`: `coat_wear` loses its light hem edge; a new `coat_dirt` uniform puts the
  leg grime's dirt (same colour, clumps, 3 steps) on a band from the hem to ~0.50 m. Only the
  leather surface gets it (`JetpackLook._wear_coat`), in AIRFRAME and Jetpack.

## Checked by

- Probe shots (`tests/_probe_coat_shot.gd`): kneel, crouch jog, run, sprint, back + side.
- `tests/test_pilot9_trench_coat.gd`: no chain point inside a leg in the kneel / sprint; tick cost.

## Reverted 2026-11-16 (the drape half)

User played it: "the new rule makes the trench coat skirt freak out even more. lets go back to what
we had". `trench_coat.gd` and its test are back to the pre-drape code (LEG_SAMPLES / CHAIN_WEDGE leg
clearance, off in crouch/slide, 9 deg crouch pool); probe tilts match the pre-drape shots. The
dirty hem (shader + JetpackLook) is KEPT. Don't rebuild the capsule drape unasked.
