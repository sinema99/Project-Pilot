# AIRFRAME pixel filter

2026-11-12. Grilled with the user (7 questions). The user wants the pixel filter back because they
think it adds to the PS1 look. PixelWorld (docs/specs/pixel-world.md) never left `trial.tscn`. Its
row left the menu on 2026-11-04 (docs/specs/live-composite.md), and its key has loaded OFF ever
since. This brings it back for AIRFRAME only.

This revises the 2026-11-10 call to keep PixelWorld out of the Airframe look
(docs/specs/jetpack-look.md), which kept the geometry at full resolution. The user has made that
change knowingly. Jetpack keeps the full-resolution reference.

## Decisions

1. **AIRFRAME only.** RETRO and COMPOSITE stay sharp. A map with no AirframeLook shows RETRO for
   AIRFRAME, so it stays sharp too.
2. **Jetpack.tscn untouched.** It stays the full-resolution reference to judge the filter against.
3. **2X by default**, which is 960x540 at 1080p. Coarser blocks wash out AIRFRAME's 16 texels per
   metre past a few metres.
4. **The PIXEL FILTER row comes back** (OFF / 2X / 3X / 4X / 6X) on its own key,
   `pixel_airframe_size`. Under RETRO and COMPOSITE it is greyed out and reads AIRFRAME ONLY. The
   old `pixel_size` key stays hidden and OFF, so no save can pixelate RETRO. A save from before
   this change boots at 2X.
5. **CRT stripes and fringe stay at screen resolution**, drawn over the blocks like a CRT image.
   The stripes are AIRFRAME's `Ps1Filter` CanvasLayer at -1, which is above PixelWorld at -100.
6. **No colour banding.** COLOUR DEPTH stays hidden.
7. **The interaction panel is pixelated with the world.** If its text stops reading, it moves to
   PixelWorld's sharp layer (20). The 2D HUD, the inventory and the hologram are sharp already.

Not grilled, and kept as the defaults: one texel per block (no supersampling, so edges are
PS1-hard), and no new hotkey (5 to 9 are taken).

## Built

- `scripts/settings.gd`: new DEFS row `pixel_airframe_size` `[0, 2, 3, 4, 6]` with default 2X,
  placed under LOOK. `effective_pixel_size(..., airframe_size, has_airframe)` returns AIRFRAME's
  size only when the look is AIRFRAME and the map has an AirframeLook. `_apply` pushes the new key
  through the same PixelWorld path, finding the AirframeLook through the `airframe_look` group.
- `scripts/rendering/pixel_world.gd`: on `_ready` it reads the new key and the group. AirframeLook
  joins the group in `_enter_tree`, so the lookup always finds it.
- `scripts/ui/tabs/tab_settings.gd`: the row's AIRFRAME ONLY greying. MSAA and RENDER SCALE grey out
  (PIXEL FILTER ON) whenever AIRFRAME's size is above OFF. The main menu has no AirframeLook, so it
  assumes trial's.
- Tests: `tests/test_airframe_pixel_filter.gd`.
- Probe: `tests/_probe_airframe_pixels.gd`. It shoots trial at OFF, 2X and 3X.

## Watch

- **Moire on the far ground (FIXED 2026-11-12: AIRFRAME now supersamples 2x2, user said the rings were unwanted).** At 2X and 3X, the 16 texels per metre floor pattern aliases against
  the block grid into wood-grain rings past about 10 m. Real PS1 had no mip-mapping, so some of
  this is authentic, but the rings are the loudest artefact in the probe shots. Fixes if the user
  dislikes them: supersample 2 for AIRFRAME (`Settings.pixel_supersample`), which averages them
  out, or fade the clump contrast with distance.
- The blockout dimension labels (`0.5x6x6`) are unreadable at 2X.
- Edge crawl in motion, already accepted in pixel-world.md.
