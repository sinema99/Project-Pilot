# pilot9 poncho

2026-10-22. Grilled (8 decisions). The user sent a screenshot with a rough red outline over his
torso: from the neck, out over the shoulder caps, down to about the bottom of the vest, narrowing
toward the hem. Same front and back, no design. "Focus on the mechanics": stiff, minor movement
that follows his actions. Mid-grill: "I don't want the front and back to be a single plate. Give
it some topology ... like a thick piece of wool."

## Decisions

1. **Built in code.** No Blender export. A procedural shell fitted to his body in bind space
   (the vest skins the same way), so the rest-pose-is-not-bind-pose gotcha from the scarf tail
   cannot bite.
2. **Locked to the chest; the arms slide out underneath.** No arm collision and no arm following.
   Accepted: a high arm (reflect spin, equip arm-out, mantle reach) can sink into the shoulder
   edge. Keep the edge short. No fix unless play shows it.
3. **Thick wool, not a plate.** It has real topology and deforms, but it is heavy, slow and damped.
4. **A coarse lattice pulled back to a tailored rest shape.** 16 columns around and 5 rows (24 x 6 since the "Refine" below) (collar
   + 4). The collar row is pinned to UpperChest. Every other point is sprung toward its spot on
   the rest shell in UpperChest's frame. That rest pull is the stiffness. Sideways and vertical
   smoothing of the offsets keeps it from kinking. A smooth thick mesh is drawn through the
   lattice, never the lattice itself.
5. **Inertia + capped wind.** Inertia comes from each point's target acceleration (low-passed,
   clamped). It lags on start, stop, turn, jump and landing (one heavy bounce), and floats a
   little in a fall. Wind is airflow from his speed, capped at `poncho_wind_max_lift` (18°) of hem
   lift at `poncho_wind_full_speed` (20 m/s) and above. Only half of the wind acts vertically
  (`VERTICAL_WIND`): a long fall already floats the hem through inertia, and the full wind on top
  lifted it 16 cm.
6. **Gameplay pilot9 + dash afterimages.** It's on trial's `Pilot9` only (`poncho_enabled`). The
   second pilot, Ichi and the cutscenes don't get it yet. The ghosts freeze the poncho's shape at
   the frame they drop.
7. **Tents over the vest pack.** The back has the same cut as the front but rests on a pack
   collider, falling from the pack to the hem.
8. **PONCHO row in settings**, on by default.

## Shape (bind space, metres; +Z front, +X his left, y up from the floor)

This is the first cut. The yoke, the ridge and the closer fit are in "Refine" below; the constants in
scripts/pilot9_poncho.gd are the truth.

Measured with `tests/_probe_poncho_fit.gd` (CPU skinning through the bind poses): the torso is
near-box, x ±0.23, z ±0.20 (front pouches and back pack), vest bottom y 1.09, shoulder tops
1.55, shoulder joint spheres x ±0.31 at y 1.42–1.54, scarf around the neck x ±0.135,
z -0.12..0.16, y 1.45–1.64.

- Column `c` points along θ = c·22.5°, θ 0 = front.
- **Collar** (row 0): y 1.59, a ring just outside the scarf. The scarf sits in the neck hole.
- **Ridge** (row 1): y 1.59, out over the shoulder caps, wide enough to clear the joint spheres.
  Both started at 1.565 / 1.55. The first probe shots showed his shoulder tops (the arm meshes
  reach y 1.59 in bind) poking through beside the collar, so they were raised.
- **Hem** (row 4): front/back y 1.07 (just below the vest). It rises toward the sides
  (smoothstep on |sin θ|) to y 1.44 over the shoulder joint, which leaves the sides open for the
  arms. From the front it reads wide at the shoulders and narrower toward the hem, like the
  outline.
- Rows 2–3 are spaced evenly between the ridge and the hem.
- Front and back use the same hem curve. The back's hem radius is larger only because the pack is
  bigger.

## Mechanics

Per lattice point: offset `d` from its target and offset velocity `dv`.
`d'' = -k·(d - wind) - c·dv - a_target`, with `k = (2π·poncho_stiffness)²` scaled per row and
`c = 2·poncho_damping·√k`. Integrated in substeps of at most 1/120 s, then:

- **Smoothing** (`poncho_bend`): each free point's offset eases toward the mean of its ring and
  column neighbours.
- **Length**: a segment can't stretch past 106% of its rest length.
- **Colliders**: rounded boxes in bone frames, from bind space (torso on UpperChest, pack on
  Chest, hips on Hips, thighs on the upper legs, shoulder joint spheres on the upper arms, which
  only rotate in place). They act on rows 2–4. A point stays half a thickness plus 5 mm out.
- **Target acceleration**: each point's target velocity is finite-differenced every frame,
  low-passed (0.04 s) and clamped to `poncho_max_accel`. A landing at 10 m/s is a short heavy
  bounce, not a metre-long whip.
- **Teleport**: a target that jumps over 2 m in one frame zeroes the offsets.
- **Pinned rows**: the collar is exact. The ridge is 4x stiffer than the drape.

Drawn as one ArrayMesh surface, rebuilt each frame (double-buffered, so the cel material's
surface override survives): 64 around × 17 rows, outer and inner shells `poncho_thickness`
(0.022 m) apart, with rolled edges at the hem and collar. Normals are smooth, so the inverted-hull
ink works.

## Colour and looks

The surface material is a StandardMaterial3D named `scarf` that carries the scarf slot's own
colour, read off his mesh at setup. `ApplyCelPilot9` derives it exactly like the scarf (same
slot + colour key, so it is the same material instance). CEL / PIXEL / RETRO swaps, the rim light
and painted shading all get it with no extra code.

## Tunables (pilot9 Inspector, "Poncho" group)

| export | default | meaning |
|---|---|---|
| `poncho_enabled` | false (true on trial's Pilot9) | build the poncho at all |
| `poncho_stiffness` | 2.2 Hz | natural frequency of the rest pull at the hem; higher = stiffer |
| `poncho_damping` | 0.55 | damping ratio; 1 = no bounce, lower = more bounce |
| `poncho_bend` | 0.3 | offset smoothing per substep; higher = moves as one thick piece |
| `poncho_max_accel` | 20 m/s² | cap on felt acceleration; caps every lag and bounce |
| `poncho_wind_full_speed` | 20 m/s | speed at which wind lift is full |
| `poncho_wind_max_lift` | 18° | hem lift at full wind |
| `poncho_thickness` | 0.008 m | wool thickness (was 0.022 before the refine) |

## Files

- `scripts/pilot9_poncho.gd` (`Pilot9Poncho`, a MeshInstance3D under his skeleton)
- `scripts/pilot9.gd`: "Poncho" export group, `_setup_poncho()`
- `scripts/pilot9_afterimage.gd`: ghosts take `frozen_mesh()` when a source has one
- `scripts/settings.gd`, `scripts/ui/tabs/tab_settings.gd`: PONCHO row
- `scenes/trial.tscn`: `poncho_enabled = true` on Pilot9
- `tests/test_pilot9_poncho.gd`, `tests/_probe_poncho_fit.gd`, `tests/_probe_poncho_shot.gd`

## Measured (tests/_probe_poncho_motion.gd, bare lattice, defaults)

| case | hem peak |
|---|---|
| run start 0 -> 7.5 m/s | 4.5 cm, settles to the wind's 4.3 cm |
| stop 7.5 -> 0 | 4.5 cm |
| landing at 10 m/s | 5.0 cm, one bounce |
| steady 20 m/s / 40 m/s | 11.3 cm both (the cap) |
| dash 7.5 -> 40 m/s | 12.5 cm |
| run bob 3 cm at 2.5 Hz | 5.2 cm |

## Refine: slimmer, rounded shoulders (2026-10-22)

User, after looking at it: "a good start but it needs work... way slimmer, way too thick, and the
part around the shoulders needs more subdivision." Grilled 3 decisions:

1. **Slimmer = both.** The cloth goes from 22 mm to 8 mm (`poncho_thickness`), and the shape hugs him.
   The drape now sits about 1.5 cm off the chest and back instead of 3.5-7 cm, and the
   ridge rolls round the shoulder cap instead of overhanging it.
2. **Shoulders: the shape, then the render.** The old shoulder was a flat shelf with a hard fold. The
   collar and ridge were both a flat ring at y 1.59, fitted against his T-posed arms. Now the
   lattice is 24 columns x 6 rows: collar, a new **yoke** row over the top of the shoulder, the
   **ridge** round the outside of the cap, then the same 3 drape rows. That gives 96 x 21 drawn.
3. **Arm push.** Upper-arm capsules lift the shoulder edge over a raised arm instead of letting the
   deltoid through. It is still locked to the chest, with no arm following.

Unchanged: length, colour, motion tunables, PONCHO row, ghosts, trial only.

### Built

- Shoulder fitted with his arms **down**: new `tests/_probe_poncho_shoulder.gd` measures the
  arm meshes in UpperChest's bind frame in trial's idle and run. The cap tops out at y 1.59 near
  x 0.24, falls to 1.54 at x 0.28 and 1.48 at x 0.30. The arm's outer face is at x 0.29-0.31. So
  the yoke is at (0.245, 1.607) at the side and the ridge at (0.297, 1.54). The bind pose is a
  T-pose, which is what had held the old ridge out as a shelf.
- Every row below the collar now collides (yoke and ridge too). The colliders carry a fifth field:
  "fits the rest". The two new upper-arm capsules (bind centre x �0.41, y 1.50, half x 0.14,
  radius 0.08) are `false`. They lie along the T-posed arm, so the rest shell is not fitted out of
  them and they only act live.
- Wind and lever are now measured from `RIDGE_ROW` (2), and act on the drape only, as before.
  `ROW_STIFFNESS` is [0, 5, 4, 1.8, 1.25, 1]. `BULGE` went from 12 to 8 mm.
- Pokes: new `tests/_probe_poncho_poke.gd` bins his torso and the cloth's inner face by angle and
  height, in idle, run and sprint. The first cut let the vest back's top edge (y 1.46, z -0.19)
  through by 16 mm, so `RIDGE_BACK` went from 0.16 to 0.198 and `YOKE_BACK` to 0.16. The vest's
  chest corners came through by 1-5 mm, so the UpperChest collider's half z went from 0.17 to 0.18.
  Idle is now clean. What the probe still flags are knees lifting under the hem in the run, and a
  collar-band binning artifact over the shoulder top (radial bins can't see under the yoke).
- Motion (`tests/_probe_poncho_motion.gd`) is barely changed: run start/stop 4.6 cm, landing
  4.2 cm, steady 20/40 m/s 11.7 cm, dash 12.9 cm, run bob 5.3 cm.
- Shots (`tests/_probe_poncho_shot.gd`): idle front and back are clean, the shoulders round, and
  the sprint lift looks as it did. The vest is visible from low behind in a run, through the open
  side, as it was before.
- Tests: `test_it_hugs_him` and `test_a_raised_arm_lifts_the_shoulder_edge` are new. The
  rest-clearance test now covers every row below the collar and skips the live-only capsules.

## Status

Built 2026-10-22. Refined the same day (above). Not yet played.
