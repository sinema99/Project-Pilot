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
  probe shots. **The hat hides his ears** (user, 2026-10-22) - see "Ears".

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

`hat_offset` (metres, Head-bone space) and `hat_tilt` (degrees back) on pilot9's "Hat" export
group.

## Built (2026-10-22)

Departures from the grill, found in the probe shots (`tests/_probe_hat_shot.gd`,
`tests/_probe_hat_head.gd`):

- **Sized to his head, not a real head.** His head is ~0.25 m across, so a real 0.36 m hat
  perched on top. The hat is scaled to fit him instead: ~0.5 m brim front to back, crown
  0.155 m. Same cattleman proportions.
- ~~His two ear fins come out through the hat~~ - superseded the same day, see "Ears".
- Felt and band are two MeshInstance3Ds with a material_override each, not two surfaces:
  `apply_stylized.gd` re-derives surface materials under his skeleton but leaves overrides alone.
- Fit: `hat_offset` (0, 0.11, 0.035), `hat_tilt` 6 deg.

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
