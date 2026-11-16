# pilot9 weapon mounts - holstered weapons on his body

Grilled 2026-11-16, built the same day. Code: `scripts/items/weapon_mounts.gd`, wired in
`scripts/pilot9.gd::_setup_weapon_mounts()`; placement data on `HeldItem` (`slot_*`).

## Decisions

- Keep the materialize draw / holster. Drawing: the body copy vanishes while the weapon forms in the
  hand; holstering reverses it. One weapon, never two.
- The body copy runs the same sweep and cyan glow, mirrored, overlapping the hand's - so the weapon
  seems to travel (`hand_amount()` is the hand copy's amount; the body copy is `1 - amount`).
- Rifle: upright on the left side of the backpack, muzzle up, ~5 deg outward cant, top of the gun
  outward. With no backpack: diagonal across his back (`slot_bare_*`).
- Revolver: outside the right thigh, no holster geometry, on the `RightUpperLeg` bone so it swings
  with the leg; muzzle down, top forward.
- Swap (1 / 2 with another out): unchanged - the drawn weapon dissolves back to its slot, then the
  other forms (pilot9.gd's existing `_pending_slot` chain).
- A body copy shows only for weapons in the loadout (`weapon_slots`, from the Inventory).
- It follows his body: under the skeleton, so hidden whenever the pilot model is (mech, speeder,
  cutscenes); shown in the hologram and portrait.
- The staff is unchanged: hidden when holstered, no body slot.

## Tuning

Per-weapon on the `.tres`: `slot_bone`, `slot_origin` (skeleton space: +Y up, his left +X, his back
-Z; origin is the grip), `slot_muzzle_dir`, `slot_top_dir`, and the `slot_bare_*` set.
The rifle is the real 1.5 m, so its muzzle rises ~0.5 m over his head with it upright.

## Built / verified

Tests: `tests/test_weapon_mounts.gd`. Probe shots: `tests/_probe_mounts_shot.gd`. Not yet played.
