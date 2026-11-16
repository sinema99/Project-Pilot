# Crate carry (2026-11-13)

The pilot picks up crates and carries them in his hands. A crate can only live in a mech's stash
(3 x 3 cells), never in his own grid. Grilled 2026-11-13.

Status: built 2026-11-13, tests green, pose NOT probe-shot, not played.

## Decisions

1. **Pick-up.** F on a world crate (panel `[F] CARRY`) puts it in his hands. Needs plain ground
   locomotion (`can_begin_carry()`), empty hands, in reach and facing it.
2. **Movement lock.** `is_carrying` on pilot9: walk speed only; sprint, jump, dash, vault, mantle,
   wall-run, wall climb, slide, crouch and rail refused (same sites the tredge locks). Staff and
   revolver holstered on pick-up; equip, weapon keys and reflect refused. Inventory (Tab) still opens.
3. **Letting go.** F with nothing else on the panel sets it down 0.9 m ahead on the floor. It drops
   by itself when airborne 0.35 s, when the pilot stops being the controlled one (pilot switch) and
   on `take_hit`. A drop over the void lands back where the crate first stood (`home`).
4. **Visual.** A 0.6 m box (ground crate 0.9 m) child of the skeleton, both arms IK'd round it by
   `carry_pose.gd` (a SkeletonModifier3D after the tredge pose). No clip.
5. **Item.** `resources/items/crate.tres`: 3 x 3, `mech_only`, empty. `ItemDef.mech_only` makes
   `Inventory.can_take/take` refuse it. `rifle_crate.tres` is unchanged.
6. **Stash screen.** LMB or RMB on a crate in the stash, opened from the ground with empty hands,
   puts it in his hands and closes the screen. Full hands or opened from aboard: nothing. Crates
   never ride the cursor, so they cannot be rearranged inside the grid.
7. **EXIA panel.** Carrying: one row `LOAD CRATE` (no PILOT / STASH, cannot board), or `STASH FULL`
   when no 3 x 3 gap. F starts a 0.4 s load (box shrinks), then the stash takes it. No room at the
   end = he keeps it.
8. **World crates.** Static `Node3D` props (`world_crate.gd`), no physics. Depositing consumes the prop.
9. **No other effect** in the stash: no weight, no visible cargo.
10. **Test content.** `Crate1..3` in trial.tscn near EXIA (-6, 0, -12). Stash seed unchanged.

## Deviations / gaps

- Scene change: the crate is simply gone with the scene (nothing carries across).
- The arm pose and box placement (`carry_pose.gd` exports: `box_ahead`, `box_up`, `hand_half`,
  poles) are first guesses, never probe-shot. Palms are not rotated.
- Pilot switch keys: dropping happens on the next physics tick of the pilot left behind.

## Files

`scripts/pilot9_carry.gd`, `scripts/carry_pose.gd`, `scripts/inventory/world_crate.gd`,
`resources/items/crate.tres`; edits in `pilot9.gd`, `mech.gd`, `inventory.gd`, `item_def.gd`,
`ui/inventory_screen.gd`, `scenes/trial.tscn`; `tests/test_crate_carry.gd`.
