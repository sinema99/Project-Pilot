# pilot9 staff materialize (equip / holster rework)

2026-10-22. Grilled with the user the same day. Replaces the draw and holster from
`docs/specs/pilot9-equip-holster.md` (reach behind, swing, spin and blur disc).

The staff no longer lives on his back. When holstered it is gone. `R` makes him put his right arm
out a little, and the staff forms in his hand out of thin air. Holstering is the same thing
reversed. It should be cheap and simple, and it must not look like the staff just pops into his hand.

## The motion (draw, 0.5 s)

| Beat | Time | What happens |
|---|---|---|
| Arm out | 0.15 s | the right arm lifts out to the side and slightly forward (about 35 deg off his body, a little forward), forearm loosely forward, palm down |
| Sweep | 0.20 s | the staff forms in his hand, already at its normal in-hand angle. It grows out from the grip to both ends, with a thin **cyan** HDR edge line on each leading end. The wrist does a small flick as it starts. No flash |
| Arm back | 0.15 s | the arm carries the staff into whatever the drawn arm does at his pace (running hold at run/sprint, natural arm at idle/walk) |

**Holster:** the same timeline backwards. The arm goes out, both ends collapse back into the hand
along the cyan edges, and the arm drops back to its natural swing.

## Rules (unchanged from the old draw)

- **Holstered = gone.** No back sling, no back socket, no `back_offset`.
- **Blocked** in mantle, vault, wall-run and wall-climb. The press is ignored, not queued.
- **R mid-animation** is ignored. **Reflect mid-animation** is ignored (the staff only counts as
  drawn once the draw ends, and stops counting on the holster press).
- **A blocked move starting mid-animation** finishes it at once: a draw snaps to fully formed and
  drawn, a holster vanishes.
- **Tredge** (blizzard) keeps the staff out as his torch, no holster.
- An item swap mid-animation finishes it first. Holstering mid-reflect cancels the reflect.
- `pilot9.toggle_drawn()` stays an instant snap (show/hide). Tests and probes use it.
- Both pilots (PilotSwitcher) get it automatically: same script.

## How it is built

- `scripts/items/equip_anim.gd` is rewritten: no back, no turn, no disc. Its own `ArmPoseModifier`
  (last in the chain) holds an **arm-out pose** computed once at setup from the rig's rest pose and
  three angles (out, forward, elbow bend), so it survives a PILOT9.glb re-export. The wrist flick is
  an extra hand rotation weighted by a bump at the start of the sweep.
- Arm back: the modifier's pose blends from the arm-out pose to `hold_rotations` while its weight
  goes from 1 to the drawn arm's weight, then hands over to the item holder's arm at that weight,
  as the old settle did.
- The staff stays in the hand socket the whole time (`item_holder.gd`). Holstered just hides it.
- The sweep: the staff instance is scaled along its own length axis about the grip, 0 -> 1, and two
  thin cyan bands (unshaded, HDR, `shaders/cel/vfx/materialize_edge.gdshader`) ride its two ends.
  The staff is a plain cylinder, so a length scale reads exactly like a reveal sweep, and it needs no
  change to the shared cel material. If the staff ever gets a detailed mesh, swap this for a cutoff
  in its shader.

## Tunables (exports on `EquipAnim`)

`out_time` 0.15, `sweep_time` 0.20, `back_time` 0.15, `arm_out_angle` 35, `arm_forward_angle` 20,
`elbow_bend` 25, `flick_angle` 25, `edge_color` cyan, `edge_energy`.
