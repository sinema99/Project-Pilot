# Equipment slots (2026-11-13)

Grilled and built 2026-11-13. Not yet played.

## Decisions

- The hat (2x2) and trench coat (3x3) are real inventory items. The staff (1x4) and revolver (2x2) are weapon items.
- Five slots on the inventory screen, inside the portrait box: HEAD, BODY, LEGS down the left edge (LEGS has no item yet), weapon 1 and 2 down the right edge. Hidden in STASH mode.
- Fresh game: hat and coat worn, staff on 1, revolver on 2, all weapons holstered.
- LMB picks up / drops. A wrong-kind slot refuses; a full slot swaps (the old item comes up on the cursor); RMB on a worn item sends it to the first free grid spot. Closing with a slot item held puts it back (slot, else grid, else ground).
- H and T are gone. 1 / 2 draw the weapon in that slot (unchanged animation); an empty slot does nothing; R is unchanged; Shift+1 / Shift+2 still switch pilots.
- A weapon that leaves its slot while drawn is holstered instantly. A weapon slotted in is never drawn for you. A weapon in the grid cannot be drawn. Either weapon fits either slot.
- One loadout for both pilots (both listen to `Inventory.equipment_changed`).
- The slots and the grid are saved together in `user://loadout.json` (not under --headless).
- Icons are rendered once from the real models (hat meshes, staff / revolver scenes, a blockout coat) by `scripts/inventory/item_icons.gd`; the colour block shows until the render lands.

## Files

- `scripts/inventory/inventory.gd` - `equipment`, `equip` / `unequip` / `slot_accepts`, save / load, `icon_for`.
- `scripts/inventory/item_icons.gd` - the icon renderer.
- `scripts/inventory/item_def.gd` - `slot`, `held_item`.
- `resources/items/{cowboy_hat,trench_coat,staff_weapon,revolver_weapon}.tres`.
- `scripts/ui/inventory_screen.gd` - slot layout, drawing, drag / drop.
- `scripts/pilot9.gd` - `_apply_equipment`, `staff_slot()`; `scripts/pilot9_tredge.gd` finds the staff by `staff_slot()`.
- `tests/test_equipment_slots.gd`.

## Known gaps

- The tredge torch needs the staff in a weapon slot.
- The legs slot takes nothing yet (no item has `slot = &"legs"`).
