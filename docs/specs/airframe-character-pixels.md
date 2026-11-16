# AIRFRAME character pixels

2026-11-13. Grilled with the user (5 questions, all recommendations taken). Reference: a PS1 pilot
with a faceted brown coat, chunky ~4 px blocks, hard jagged edges.

## Decisions

1. **Block size and flat shading**, not just chunkier pixels. Characters are lit flat per face.
2. **4X** for characters, with the world staying at its 2X (PIXEL FILTER). Row `CHARACTER PIXELS`
   (OFF / 3X / 4X / 6X), key `pixel_char_size`, default 4X. Pilot and mech share the value.
3. **Everything alive or driven**: pilots, EXIA, speeder, range farmer, knight. Hard split by object,
   not a distance fade (the 2026-10-04 distance bands were rejected, see pixel-world.md).
4. **Flat shading is a shader**: per-face normal from screen-space derivatives. No decimated meshes.
   The coat was already faceted; high-poly parts only read as facets where the mesh is coarse.
5. **Edges**: characters are one texel per 4X block, hard and jagged, no supersampling. Occlusion
   follows the WORLD's depth at the world's block size. Ground shadows stay in the world pass.

## Built

- `PixelWorld`: a third SubViewport, CharView (transparent, `CHAR_LAYER` 18, camera mirrors the
  game camera with the environment's background cleared). `apply_settings(..., char_block)`.
- Compositing: ps1_surface and mech_weathered paint a close (< 50 m) character a flat marker
  (emission magenta, albedo 0) in the 2X world pass. `shaders/pixel_world.gdshader` shows CharView's
  colour in a 4X block where CharView covers it AND the world pass has marker in it. World blocks
  average without marker texels; a block that is all marker borrows a neighbour. Past 50 m there is
  no marker, so a far character stays in the 2X world. The pass is told apart by viewport width
  (global `pixel_char_view_w`).
- `AirframeLook`: `is_character` (under a CharacterBody3D or meta `airframe_character`, set on the
  range dummy and the knight) puts every such mesh on layer 18 as well as 1, and every Light3D too
  (a light must share a layer with the camera, or CharView gets no sun). Global
  `airframe_char_flat` = 1 while AIRFRAME is on.
- `Settings.effective_char_size`: the grid runs only under AIRFRAME in a map with an AirframeLook
  with the world filter on. The row greys: AIRFRAME ONLY / NEEDS PIXEL FILTER.
- Tests `tests/test_airframe_character_pixels.gd`; probe `tests/_probe_airframe_character_pixels.gd`
  (shots in `screenshots/airframe_char/`).

## Watch

- Marker leaks: the marker arrives as (1, ~0.1, 1), so detection is r,b > 0.8, g < 0.3.
- Non-ps1 character parts (glows, transparent) draw at 2X in the world.
- A third viewport adds a shadow pass and the characters' draw calls; not profiled.
- Not played, uncommitted.
