# Inventory (2026-11-12)

A DayZ-style grid inventory on Tab: portrait | your grid | vicinity. Grilled 2026-11-12. No real
loot exists yet; four placeholder items lie near the trial spawn to drive it.

Status: built 2026-11-12.

## Decisions

1. **Own screen on Tab.** A non-pausing `UI` screen, `&"inventory"` in `ui_manager.gd`'s registry
   (`pauses: false`, `dim: false`, `hologram: false`). The pause shell's INVENTORY tab is deleted
   (`tab_inventory.tscn` gone; `tab_empty.gd` stays for nothing else - deleted too).
2. **World keeps running.** pilot9 is held `frozen` while it is open (`set_inventory_hold()`): no
   move, no look, no verbs, he idles where he stands. Cursor visible. Enemies, weather, physics
   carry on.
3. **Tetris grid.** Every item is W x H cells; R rotates the held item 90 deg; stackables show a
   count.
4. **One fixed 10 x 6 container** (`ItemGrid`). It is a container object so worn gear can add
   grids later; today there is one.
5. **Vicinity = `WorldItem`s within 2.5 m** of pilot9 with a clear ray from chest height (1.2 m)
   to the item. Refreshed every 0.2 s while open.
6. **Vicinity box is an auto-packed grid**, 10 cells wide, nearest first, packed top to bottom
   (rotated if that is the only way it fits the width), scrolls with the wheel. No rearranging.
   Grid -> vicinity = drop (spawns a `WorldItem` at his feet); vicinity -> grid = pick up.
7. **Mouse only for now.** LMB click takes, LMB click places (no hold-drag). R rotates the held
   item. RMB quick-moves (ground -> first free spot in the grid, grid -> ground). Tab / Esc
   close; anything held goes back where it came from. Gamepad is a follow-up.
8. **Portrait = a studio copy.** Its own World3D in a SubViewport: dark backdrop plate, key + rim
   light, and a pose mirror of pilot9 - a Skeleton3D copying his final pose every frame, carrying
   copies of every mesh under `character` (body, coat, hat, staff) sharing his meshes, skins and
   materials (the afterimage technique). He is frozen, so it plays his idle. Drag with LMB over
   it to turn him.
9. **PS1, flat on screen.** The whole screen is drawn into a low-res canvas (one texel = an
   integer number of pixels, 3 at 1080p: `lines` 360) sampled nearest: Barlow Condensed with
   antialiasing OFF, 1-texel cyan edges on dark plates, plates ordered-dithered (Bayer 4x4) for
   transparency, 15-bit colour. The portrait renders at the same texel resolution. The world
   behind dims 50%.
   - Deviation from the grill: the portrait gets low-res + dither + 15-bit but NOT vertex snap or
     affine textures - it wears his live materials (whatever LOOK is on) rather than a
     PS1-specific shader, so it matches what you see in the world.
10. **Test content.** `resources/items/` holds four `ItemDef`s: Ration 1x1 (stack 5), Battery 1x2,
    Medkit 2x2, Rifle crate 2x4 (each tinted). `scenes/trial.tscn` has a `TestLoot` node (marked
    TEST CONTENT) with one `WorldItem` of each (ration x3) a few metres in front of the spawn.
    The grid starts empty.
11. **Session only.** The `Inventory` autoload holds the grid; it survives scene changes and is
    gone on quit. No disk save.
12. **Only on his feet.** `pilot9.can_open_inventory()`: the controlled, visible pilot whose
    camera is current, on the floor, not sliding / dashing / mantling / vaulting / wall-running /
    wall-climbing / grinding / switching rails / tredging. Refused = Tab does nothing. Esc while
    open closes it (never opens the pause menu).
13. **Info strip** under the middle box: name, size, count of whatever is hovered or held. A key
    hint row along the bottom of the screen.
14. **Unfold** like the interaction panel: each box opens from a line over 0.1 s, staggered 0.03 s
    left to right; folds over 0.08 s. The camera does not move.
15. **F pickup.** A `WorldItem` within 2 m and within 60 deg of the camera's flat forward bids
    `TAKE` into the InteractionPrompt (closest wins, like doors). F puts it in the first spot it
    fits (upright, then rotated; stacks merge first). No room = the word reads `FULL` and F does
    nothing. The prompt panel hides while any UI screen is open.

## Files

- `scripts/inventory/item_def.gd` - `ItemDef` resource.
- `scripts/inventory/item_stack.gd` - `ItemStack`: def, count, cell, rotated.
- `scripts/inventory/item_grid.gd` - `ItemGrid`: placement, find-free, merge, pure.
- `scripts/inventory/inventory.gd` - `Inventory` autoload: the player grid, `try_add`, `drop`,
  the vicinity query and `pack_vicinity` (pure).
- `scripts/inventory/world_item.gd` - `WorldItem`: placeholder box, group `world_item`, F bid.
- `scripts/ui/inventory_screen.gd` + `scenes/ui/inventory_screen.tscn` - the screen, its input,
  layout and drawing; `scripts/ui/inventory_canvas.gd` draws the texels;
  `scripts/ui/inventory_portrait.gd` the studio + pose mirror;
  `shaders/ui/inventory_ps1.gdshader` the dither / 15-bit composite.
- `scripts/ui/ui_manager.gd` - `inventory` screen, `dim` / `hologram` registry flags,
  `hides_world_prompts()`.
- `scripts/ui/interaction_prompt.gd` - hides while a screen is open.
- `scripts/pilot9.gd` - `can_open_inventory()`, `set_inventory_hold()`.
- `project.godot` - `inventory` action (Tab), `Inventory` autoload.
- `tests/test_inventory.gd`, `tests/_probe_inventory_shot.gd`.

## Tunables

`InventoryScreen`: `lines` (canvas height at 1080p-equivalent), `unfold_time`, `fold_time`,
`stagger`, `dim`, `cell`. `Inventory`: `VICINITY_RADIUS`, `VICINITY_EYE`, `PICKUP_REACH`,
`PICKUP_CONE_DEG`.

## Known gaps

- No gamepad.
- Dropped items do not fall or roll: placed on the floor found by one ray down.
- The portrait copies his materials, so shader effects that read world state (snow cover,
  storm fog uniforms) may look slightly different in the studio.
- Global look keys (I, U, ...) handled by other scripts' `_input` still fire while it is open.

## Polish pass (2026-11-13)

Grilled 13 questions, built, probe-shot (`tests/_probe_inventory_polish.gd`), not yet played. Gamepad,
audio, pockets and a 3D inspect preview are out of scope.

- **Drag + click.** A press on an item picks it up (as before); if the cursor then moves more than
  `DRAG_TEXELS` (2) with the button down it is a drag and the release places it, an invalid release puts it
  back where it came from. A plain click still carries it until the next click.
- **Shift + LMB** = instant transfer: grid -> ground (grid <-> stash in STASH mode), ground -> grid, worn ->
  grid. **Ctrl + LMB** = half a stack (rounded up) onto the cursor; an unplaced half pours back into the
  stack it came from.
- **RMB = popup** (replaces the old RMB quick-move): TAKE (ground) / DROP (grid) / MOVE (stash) / CARRY
  (crate) / TAKE OFF (worn), SPLIT on stacks of 2+, INSPECT always. Unfolds like the boxes; click outside
  or Esc closes it (Esc again closes the screen). INSPECT shows a card: name, category, size, count,
  weight, description.
- **ItemDef** gained `category` (medical / food / ammo / gear / junk), `description`, `weight`.
- **Category look:** a 4x4 corner glyph in the category colour on every item; the info strip shows the
  category.
- **Q** drops the item under the cursor (or the held one) at his feet; **T** or the SORT button repacks the
  pack (and the stash aboard) - merge partial stacks, category order, biggest first - and groups the
  vicinity; **Ctrl+Z** undoes it while nothing else has changed the grids.
- **Feedback:** the held item snaps to the cells it would land in with a cyan outline (green = merge, red =
  no fit); its origin spot dims; a lift shadow; a 0.06 s flash on a placement; a 0.2 s shake on an invalid
  drop; a 1-texel cyan edge on the hovered item. Hint row switches between idle and held key sets.
- **Sound hooks:** `InventoryScreen.sound(kind)` fires `pick`, `place`, `rotate`, `invalid`, `drop`,
  `sort`. Nothing is connected - the project has no audio.
- **Equipment strip: already built, left as is.** `docs/specs/equipment-slots.md` shipped real
  head / body / legs / 2 weapon slots after this spec; the polish pass did NOT replace them with
  toggle-mirroring slots (the grill assumed they did not exist).
- Tests: `tests/test_inventory.gd` (29 tests). Tunables: `DRAG_TEXELS`, `FLASH_TIME`, `SHAKE_TIME`,
  `MENU_UNFOLD`, `MENU_ROW`, `CATEGORY_COLORS`.
