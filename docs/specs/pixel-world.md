# Pixel World — crisp low-res render

Status: built 2026-10-03.

Replaces the old PIXEL FILTER (`shaders/pixelate.gdshader` + `scripts/rendering/pixelate.gd`). The old
filter was a screen-space post pass: it shrank the finished full-res frame by reading one pixel at
the centre of each grid cell. Its finest preset was 640x360, and it started at 160x90 when toggled on
with `O`. Because it point-sampled, 1-px outlines and thin edges either landed on the sampled pixel
or vanished, so the image shimmered as the camera moved. The user wanted **both** smaller pixels and
cleaner pixels.

## Decisions (grilled 2026-10-03)

| # | Question | Decision |
|---|----------|----------|
| 1 | What does "crisp" mean | Both: finer grid **and** clean, stable pixels |
| 2 | How the pixels are made | Real low-res 3D render, upscaled with nearest at an exact whole-number block size. Not a smarter post filter |
| 3 | What is pixelated | Everything 3D (level, characters, mech, outlines, rim light, VFX, afterimages, the hologram beam / ring / dim). **Sharp:** all 2D UI **and the hologram menu panel** |
| 4 | Pixel size | Fixed block size, not fixed internal resolution. **OFF / 2X / 3X / 4X**, default **3X** (853x480 at 2560x1440); **2X since 2026-10-12** (user picked it from play) |
| 5 | Outlines | Always **1 block** while pixelated (crease ink too). Built in, no setting. OFF = today's widths |
| 6 | AA and render scale | Pixelated forces MSAA off and ignores RENDER SCALE (and fullscreen RESOLUTION's 3D scale). Both rows show `PIXEL FILTER ON` dimmed while overridden |
| 7 | Colour banding | Becomes a real setting |
| 8 | Colour setting | **COLOUR DEPTH**: FULL / 32 / 16 / 8 levels per channel, default FULL. World only. Works with the pixel filter OFF too. `\` cycles it. No dither for now |
| 9 | Scope | `trial.tscn`, as a drop-in node. Shared-world SubViewport with a camera that copies the active camera every frame; nothing in the scene moves. Old PixelFilter removed from `test_platform.tscn` |
| 10 | Saved setting | New key `pixel_size`. The old `pixel_filter` entry is dropped, so everyone boots into 3X |

Known limitation, accepted: with a perspective camera, edges **crawl** slightly while the camera
moves. Each block is a real rendered pixel, so there is no per-frame flicker, but nothing can snap a
moving perspective camera to the grid.

## How it works

`scripts/rendering/pixel_world.gd` (`PixelWorld`, a CanvasLayer at layer -100, in group
`pixel_world`) builds everything in code:

- **WorldView**: a SubViewport sharing the main `World3D`, sized `ceil(render size / block)`, MSAA
  off, scale 1. Its camera copies the root's current camera every frame (interpolated transform,
  FOV, h/v offset, near/far, environment, attributes), so pilot's camera sway, dash FOV kick, the
  mech handover and the hologram camera all carry over for free. Its cull mask leaves out the
  sharp layer.
- **The root viewport stops drawing 3D** (`disable_3d`) while pixelated. Its cameras still exist and
  stay current, so every `get_viewport().get_camera_3d()` in the project keeps working.
- **Display**: a full-screen ColorRect whose shader reads the WorldView texture with `texelFetch` at
  `floor(physical pixel / block)`. Every block is exactly `block` x `block` physical pixels whatever
  the canvas stretch does, and COLOUR DEPTH bands it in the same pass.
- **SharpView**: a second, full-resolution, transparent SubViewport with the same camera, whose cull
  mask shows **only** render layer 20 (`PixelWorld.SHARP_LAYER`). The hologram panel lives on that
  layer, so it is drawn sharp over the pixel world. It only renders while something asks for it
  (`set_sharp_needed`, which the hologram calls on open / close).
- **ColourOnly**: with pixels OFF and COLOUR DEPTH on, a screen-texture pass on the same -100 layer
  bands the normal 3D render. Layer -100 is below every UI layer, so UI colours are never banded.
- Global shader uniform **`pixel_block`** (1.0 when OFF, the block size when on). `outline.gdshader`
  and `crease.gdshader` draw 1-block lines when it is above 1; `rim_light.gdshader` divides its pixel
  width by it so the rim keeps its screen size.

Leaving the tree (scene change to the main menu) restores `disable_3d = false` and `pixel_block =
1.0`.

### Settings

- `pixel_size` (PIXEL FILTER): `[0, 2, 3, 4]`, default index 2 (index 1 = 2X since 2026-10-12). Shown OFF / 2X / 3X / 4X.
- `colour_depth` (COLOUR DEPTH): `[0, 32, 16, 8]`, default 0. Shown FULL / 32 / 16 / 8.
- Both reach the node through the `pixel_world` group, tolerating null (the main menu has none).
- QA keys: `O` toggles OFF and the last block size, `[` `]` step the block size, `\` steps COLOUR
  DEPTH. All write through Settings.
- MSAA and RENDER SCALE rows are disabled and read `PIXEL FILTER ON` while pixel size is not OFF.

## Removed

`shaders/pixelate.gdshader`, `scripts/rendering/pixelate.gd`, the PixelFilter nodes in `trial.tscn`
and `test_platform.tscn`, the `pixel_filter` setting key and its 160x90..640x360 presets.

## Built

2026-10-03, as specced, with these notes:

- **Outline at 1 block is `width 2.0`**, not 1.0: the hull shader divides by VIEWPORT_SIZE in
  NDC, which spans 2 units, so today's `outline_width 4.0` is really 2 px. Crease ink goes to
  1 block too; the rim light divides its width by `pixel_block` so it keeps its screen size.
- **Render size comes from `visible_rect x final_transform`.** On the root window in 4.6,
  `get_texture().get_size()` applied the stretch scale twice (3122x1756 for a 2448x1377 target),
  which made the first build render too wide a view.
- **COLOUR DEPTH N gives exactly N levels** (the old shader gave N + 1).
- **QA keys:** `[` coarser / `]` finer, same direction as the old filter.
- **RENDER SCALE and ANTI-ALIASING rows** use `set_row_disabled`, so they also drop out of W/S
  focus while overridden. `test_menu_refresh.gd` focused RENDER SCALE as its "fifth row" and was
  moved to SHADOW QUALITY.
- `Settings._load()` now skips keys a save does not have, instead of logging an error per new key.

Verified: `tests/test_pixel_world.gd` (18 tests). `tests/_probe_pixel_shot.gd` windowed at a
2448x1377 target: every sampled block at 2X / 3X / 4X is uniform (0 of ~41k off), framing and FOV
match OFF, 8 / 16 levels come out exact. `tests/_probe_hologram.gd` with the filter on: the panel
text and scanlines are sharp over a pixelated world, pilot has 1-block outlines.

Not checkable headless: edge crawl in motion, and whether 3X is the right default by feel.

## 2026-10-12: pixel off by default, menus always sharp

User: "no more pixel menu. no more pixel shader at all, toggle it off and set it off by default."
PIXEL FILTER (`pixel_size`) now defaults to OFF (was 2X); LOOK stays CEL by default. ScreenPixel
no longer draws over menus in any look (`MENU_BLOCK` removed; `drawn_block` returns 0 while a menu
shows). The PIXEL FILTER row and the I key still exist as opt-in toggles.
