# pilot9 cowboy hat

Grilled 2026-10-22. A cowboy hat pilot9 puts on and takes off with one key. Cosmetic only.

## What it is

- A classic **cattleman**: tall crown with a centre crease and two front pinches, crown sloping a
  little lower at the front; a wide brim that curls up at the sides and dips slightly front and
  back. Modelled in code (`scripts/items/cowboy_hat_mesh.gd`), no Blender step.
- **Dark brown felt, near-black brown band** (darkened 2026-10-22). Both are cel materials copied from
  `resources/pilot_cel_character.tres`, so the hat gets ink, cel bands, the LOOK switch and painted
  shading like the rest of him.
- **Real size** was the plan (0.36 m brim) - see Built: it is sized to his head instead. Sits snug
  at the brow, tipped back a few degrees so his face reads from the shoulder camera. Fitted from
  probe shots. ~~The hat hides his ears~~ - reversed 2026-10-23: his ears come out through the hat, see "Ears through the hat".

## How it works

- **H** toggles it (`hat` input action, keyboard only). No animation: it appears or disappears
  that frame.
- **Off at boot**, never saved.
- Hung on the `Head` bone through a `BoneAttachment3D` built at runtime by
  `scripts/items/hat_holder.gd` (pilot9.gd::_setup_hat()), the same pattern as the staff's hand
  socket - a rebuild of pilot9.tscn cannot lose it. It follows every clip: nod, lean, slide,
  wall-run, mantle.
- **Both gameplay pilots** have one, each toggled on its own. H only reaches the pilot being played
  (`frozen` gates it). Cutscene pilots never show it - nobody can press H there.
- Works everywhere in gameplay, Tredge and the firing range included.

## The rest of him

- **Dash afterimages** wear it when he does. Nothing extra: the ghost pool copies every visible
  mesh under `character`, the hat included.
- **Rim light** lands on it - it is part of his silhouette, unlike the staff.
- **Pause menu**: H does nothing (the tree is paused, so pilot9 sees no input); the hat stays as it
  was. The visor ring that might have cut the brim is already off (`ring_enabled = false`), so
  the menu is untouched.

## Tunables

`hat_offset` (metres, Head-bone space), `hat_tilt` (degrees back; negative rakes forward) and
`hat_scale` (even scale on the whole hat, added 2026-10-23) on pilot9's "Hat" export group.

## Built (2026-10-22)

Departures from the grill, found in the probe shots (`tests/_probe_hat_shot.gd`,
`tests/_probe_hat_head.gd`):

- **Sized to his head, not a real head.** His head is ~0.25 m across, so a real 0.36 m hat
  perched on top. The hat is scaled to fit him instead: ~0.5 m brim front to back, crown
  0.155 m. Same cattleman proportions.
- ~~His two ear fins come out through the hat~~ - superseded the same day, see "Ears".
- Felt and band are two MeshInstance3Ds with a material_override each, not two surfaces:
  `apply_stylized.gd` re-derives surface materials under his skeleton but leaves overrides alone.
- Fit: `hat_offset` (0, 0.11, 0.035), `hat_tilt` 6 deg - superseded 2026-10-23, see "Pulled low".

Tests: `tests/test_pilot9_cowboy_hat.gd`.

## Ears and crown (2026-10-22, user feedback)

User: "make the top of the hat not so wide. also make the hat hide pilot's ears."

- Crown top half-widths 0.108/0.104 -> 0.09/0.088 m: a clear taper from the band to the top.
- **Ears.** Neither pilot's ears have a bone - they are part of the head mesh (pilot9's two grey
  fins; the decimate pilot's blue antennae, a material surface of their own). So while the hat is
  on, each head mesh is swapped for a "hatted" copy built at setup (`hat_holder.gd::cut_above()`):
  - only Head-weighted triangles (> 0.5) are touched;
  - the **skull** - the connected piece with the most triangles under the band, across all
    surfaces - is cut at 0.02 m above the brim's underside (hat space); the top it loses is under
    the crown;
  - every **other** head piece that reaches within 0.05 m of that line goes whole, so no stub
    shows under the brim (the decimate pilot's antennae are two pieces; the lower one stops just
    under the band). The visor line sits lower and is untouched.
  - Surfaces are never removed (a surface cut to nothing keeps one degenerate triangle) so his
    material overrides still line up. Moving the hat (`hat_offset` / `hat_tilt`) recuts.
  - The dash ghosts copy `mi.mesh` at drop time, so they wear the cut head too.
- Probe-checked on both pilots (`tests/_probe_hat_shot.gd -- <dir> <pilot_index>`,
  `tests/_probe_hat_cut.gd [-- decimate]`).

## Pulled low (2026-10-23, user feedback)

User: "i want the hat to sit down more on pilots head... IF pilot had eyes, i would want the hat to
kind of cover his eyes" (reference: a hat pulled low with the brim raked down over the brow).
Grilled the same day:

| # | Question | Decision |
|---|---|---|
| 1 | Dead-on at head height, how much of the visor seam (his "eyes") does the brim hide? | **Brim edge at the seam - the line just peeks out under it.** The pause-menu visor glow still shows. |
| 2 | Tilt or drop? | **Mostly tip forward, little drop**, so the back brim lifts like the reference. |
| 3 | Side cant? | **None.** Straight; the shoulder camera swaps sides. |
| 4 | Brim shape? | **Unchanged** - only offset and tilt. |
| 5 | Which pilots? | **Both**, same defaults. |

Built: `hat_offset` (0, 0.112, 0.05), `hat_tilt` 1 deg (was 0.11 / 0.035 / 6 deg).

- **Departure from Q2's "~10 deg forward":** the probe shots showed -10 deg buried the seam
  completely (option b) and a sliver of forehead showed between the band and the front brim. The
  seam line lands at the brim edge with a 5 deg change (6 -> 1). The front brim's own dip
  carries the rake.
- **Hat 1.5 cm forward** (z 0.035 -> 0.05) so the crown front covers his brow - without it the
  forward rake opened that forehead sliver.
- Fitted from `tests/_probe_hat_shot.gd`, which now takes an optional `y z tilt` after the pilot
  index to try a fit without editing pilot9.gd. Decimate pilot checked too: no antenna stubs, no
  gaps (that mesh has no visor seam).

## Raked (2026-10-23, user feedback)

User, over a screenshot from behind with the brim's slope drawn steeper: "tilt even more forward
... sit down more on his head, so make it wider or whatever if you need to". Grilled:

| # | Question | Decision |
|---|---|---|
| 1 | Where does the front brim edge sit, dead-on at head height? | **Around the visor seam**, as before. |
| 2 | How steep a rake? | **~15 deg forward** - the slope of the user's arrow. |
| 3 | What grows so it can sink lower? | **The whole hat, evenly, ~10-15%** - same cattleman proportions. |
| 4 | From behind? | **No skull above the back brim** - the crown swallows the top of his head. |

First build: `hat_offset` (0, 0.17, 0.0), `hat_tilt` -15 deg, `hat_scale` 1.12. In play the user
saw it perched on top of his head ("what the fuck is this"): Q1, Q2 and Q4 cannot all hold. His
visor seam is low on a short head, and a 15 deg rake over a ~0.56 m brim puts the back of the brim
~0.14 m above the front, so with the front at the seam the crown sits on the skull, not over it.
The probe's back shot showed it and was misread as "crown covers his head".

**Resolved (user picked B from probe shots): sink it, let the brim cover the seam, rake 6 deg.**

| # | Decision (revised) |
|---|---|
| 1 | Front brim **covers the visor seam** - his face is under the brim dead-on. |
| 2 | **6 deg forward** (15 deg sunk this low buries the face and opens a gap under the crown front). |
| 3 | Whole hat scaled **1.15**. |
| 4 | Sits **down on his head** from behind; the back brim just above the seam. |

Built: `hat_offset` (0, 0.10, 0.03), `hat_tilt` -6 deg, `hat_scale` 1.15 (new export), on both
pilots. Fitted from `tests/_probe_hat_shot.gd` (now takes `y z tilt scale`).
- **Head cut fixes the rake exposed** (`hat_holder.gd::cut_above()`):
  - The skull is now the head piece that crosses the band and **reaches lowest**, not the one with
    the most triangles under the band. Raked forward, more of each 1280-triangle ear fin sat under
    the band than of the ~230-triangle skull, so a fin was taken for the skull and the real skull
    went whole - his head vanished.
  - Only pieces **off to one side** of the head (ear fins, antennae) go whole near the band; a
    piece that wraps round it (the visor seam ring) is cut like the skull, so a deep fit can never
    delete the seam.
  - The cut stays a flat plane at the band: a crown-only cut was tried and left his brow poking
    up through the brim in front of the crown.
- Cut counts at the final fit (`tests/_probe_hat_cut.gd`): pilot9 2880 -> 244 (both fins plus
  the skull top under the crown), seam 40 -> 40; decimate pilot skull kept, antennae gone. Probe shots on both
  pilots: no stubs, no gaps. `tests/_probe_hat_pieces.gd` lists every head piece for a fit.

Tests: `test_raked_fit_scales_and_tips_it_forward`, `test_raked_cut_keeps_the_skull`.

## Ears through the hat (2026-10-23, user feedback)

User: "put the ears back, i like how they go through the hat. the hat should not hide the ears
anymore." Reverses "Ears" above. `hat_holder.gd::cut_above()` now never touches a head piece that
sits off to one side of the head (its hat-space x range doesn't cross 0) - pilot9's two fins, the
decimate pilot's antennae. Only pieces that wrap round the head (skull, visor seam) are cut at the
band, so the skull top still can't poke through the crown. `PIECE_REACH` and the skull pick are
gone. Cut at the final fit: pilot9 2880 -> 2804 (skull top only), seam 40 -> 40. Probe shots on
both pilots: fins stand out through the crown; antennae show under the brim.

Tests: `test_ears_come_through_the_hat`.

## Forward (2026-10-23)

User: the hat sat too far back on his head. The side probe agreed: the crown was centred behind
the middle of his skull. `hat_offset` z 0.03 -> 0.07 centres the crown over the skull; 0.10 put
it in front of his face. Height, tilt and scale unchanged.

## Reshaped (2026-10-26, user feedback)

User: "the top of the hat is too wide. it sits on pilots head weirdly." Grilled:

| # | Question | Decision |
|---|---|---|
| 1 | Which part is too wide? | **The crown top** - the brim is fine. It looked like a top hat, and the front had "a weird thing". |
| 2 | The two front pinches (the weird thing)? | **Keep them, much softer** - shallow and broad, shaping the front without denting it. |
| 3 | Crown profile? | **Rounded cattleman** - the wall bows out a little and rolls into the top through a rounded shoulder, no hard top corner. Centre crease stays. |
| 4 | Crown height? | **0.155 -> ~0.14 m** (unscaled). |
| 5 | How does it sit wrong? | **Not centred on his skull** - |
| 6 | Which way? | **Too far forward.** |

Built (`scripts/items/cowboy_hat_mesh.gd`):

- Pinches 0.045 deep / 0.32 wide -> **0.022 / 0.55**, angle 0.65 -> 0.7.
- New `CROWN_BOW` 0.008 m (wall bulge at mid height, `sin(pi k)`) and `SHOULDER` 0.03 m: the wall
  stops SHOULDER below the crown height and a quarter-circle `_shoulder()` rolls it in; the flat top
  starts SHOULDER inside `CROWN_TOP`, so the top is visibly narrower than the wall. The crown is
  one smooth group, so the shoulder shades round. The old 0.92/0.97 edge hack is gone.
- `CROWN_HEIGHT` 0.14.
- Fit: `hat_offset` z **0.07 -> 0.04**. Measured, not eyeballed: `tests/_probe_hat_centre.gd`
  prints the skull's front/back extent per height in Head-bone space (ears left out) - its middle
  is z ~0.04 from the band up, so 0.07 had the crown ~3 cm forward. The idle sway turns his head
  between probe runs, so the side shot alone can't judge a centimetre. Height, tilt -6 and scale
  1.15 unchanged; the probe shots show no skull through the new top, ears still out, brim still
  over the seam.
