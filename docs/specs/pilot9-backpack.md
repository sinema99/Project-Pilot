# pilot9 backpack (2026-11-14)

Grilled 2026-11-14 from the user's reference image (an olive canvas rucksack: drawstring top
under a rounded flap with a leather trim and one strap + buckle, three front pockets with leather
tabs and metal buckles, side pockets, a top grab loop).

## Decisions

1. **Slot.** A new BACK slot in the equipment row above the grid: HEAD, BODY, LEGS, BACK, gap,
   1, 2. Slots go 28 -> 24 texels wide so the row of six still fits the grid box.
2. **Container.** The pack carries its own **6 x 4** grid (`ItemDef.container_size`). The grid
   lives on the item (`ItemStack.contents`, `WorldItem.contents`), so the contents travel with it:
   dropped, carried in a grid, put in a stash.
3. **No nesting.** A pack's grid never takes a pack (`ItemGrid.no_containers`).
4. **The pack as an item:** 4 x 4, gear, icon rendered from its own model.
5. **Middle column:** slot row -> your 10 x 6 grid -> BACKPACK 6 x 4 box (drawn only while a pack
   is worn; its space is kept so nothing jumps when you put one on). The INFO strip is gone.
6. **Hover tooltip** replaces INFO: PS1 panel, name / category + size (+ count) / description,
   shown at once below-right of the cursor and flipped at the canvas edges; hidden while dragging,
   while the RMB popup or the Inspect card is open. An empty slot shows "BACK - EMPTY".
7. **Ground packs.** (Revised 2026-11-14, see "Pack windows".) The vicinity shows a ground
   pack as just its 4x4 item - no header row, no grid under it. Its contents are reached with OPEN.
8. **STASH mode.** The worn pack's grid shows under your grid there too. RMB from the stash goes
   to your grid first, then the pack.
9. **Taking things** (F, shift-click, TAKE) fills your grid first, then the worn pack.
10. **Fresh game:** hat, coat, pack (empty), staff, revolver. An existing save is left alone; a
    pack lies on the ground in trial's TestLoot.
11. **Save:** the contents of any pack in the grid or the slots go into `user://loadout.json`.
    Ground items are not saved (unchanged).
12. **Look:** a code-built faceted mesh (`scripts/items/backpack_mesh.gd`), flat colours, olive
    canvas `(0.42, 0.40, 0.22)`, darker seams, brown leather `(0.30, 0.17, 0.09)`, dull grey
    buckles. Roughly 0.50 x 0.40 x 0.22 m. Shoulder straps over his shoulders.
13. **Fit + motion:** fitted to his bare back (coat hidden while fitting). In play the coat and
    the pack can both be worn and simply clip. Rigid on the chest bone; the straps ride the
    shoulder bones. Both pilots wear it (shared loadout).

## Pack windows (grilled 2026-11-14)

1. **Menu.** A pack on the ground: TAKE, EQUIP, OPEN, INSPECT. A pack in his grid: DROP, EQUIP,
   OPEN, INSPECT (STASH mode: MOVE, OPEN, INSPECT - no EQUIP there).
2. **EQUIP** wears it, contents and all. Already wearing one = swap: the old pack lands on the
   ground exactly where the new one lay (from a grid: the spot it left, else any free spot, else
   his feet). Never greyed out. Its window closes.
3. **OPEN** shows a small titled panel ("BACKPACK 6x4") with the pack's grid, on top of the
   screen, anchored beside the pack's item (right of it, else left), kept on the canvas. Always
   opens there - no remembered position.
4. **Draggable** by its title bar, clamped to the canvas.
5. **Fully interactive:** LMB / SHIFT / CTRL / RMB / R as any grid; changes write straight into
   that pack. SHIFT on an item in a window goes to his grid, then the worn pack. SHIFT on an item
   in his grid or worn pack goes into the FRONT window only (no spill; refused if it does not fit).
6. **Several at once.** Clicking / dragging one raises it; opening an already-open pack raises it;
   a new window stepped (8, 8) off any window already at its spot.
7. **Closing:** the X closes that one, Esc the front one (after a popup / Inspect card), Tab all.
   A window also closes when its pack leaves - out of the vicinity, taken, equipped, dropped out of
   his grid. A pack being dragged on the cursor keeps its window.
8. A window hides what is under it: slots, vicinity items, the sort button and the drop-to-ground
   area do not take clicks through it.

## Files

- `scripts/inventory/item_def.gd` - `container_size`, `is_container()`.
- `scripts/inventory/item_stack.gd` - `contents`.
- `scripts/inventory/item_grid.gd` - `no_containers`, `accepts()`, contents kept through sort /
  snapshot / restore.
- `scripts/inventory/world_item.gd` - `contents`.
- `scripts/inventory/inventory.gd` - `SLOT_BACK`, `pack_grid()`, take / drop / save with contents.
- `scripts/ui/inventory_screen.gd` - BACK slot, PACK box, tooltip, pack windows + EQUIP / OPEN.
- `scripts/items/backpack_mesh.gd`, `scripts/items/backpack_holder.gd`; `scripts/pilot9.gd` wires it.
- `resources/items/backpack.tres`.
- `tests/test_backpack.gd`.
