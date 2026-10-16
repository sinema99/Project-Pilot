# Pixel Look — CEL / PIXEL art-direction test

Status: built 2026-10-06, not yet played.

The user brought three references (a hazy yellow flower field, "Nightliner" by Lowtrippy, an old
man in a cap) and asked whether the game would look good like that, as a separate shader they can
toggle against today's cel + black ink look.

What the references share is not the pixels (the game is already pixelated at 3X by
PixelWorld, see [pixel-world.md](pixel-world.md)). It is: no ink outlines, smooth soft lighting,
busy surface detail inside every surface, and atmosphere. So the switch swaps the shading, not a
post filter.

## Decisions (grilled 2026-10-06)

| # | Question | Decision |
|---|----------|----------|
| 1 | What flips | A **LOOK** switch, CEL / PIXEL. PIXEL swaps the material shading as well; outlines and crease ink off |
| 2 | Lighting | Smooth diffuse falloff, coloured (ambient) shadows, no specular. Plus an optional **DITHER** |
| 3 | Surface detail | Procedural grain in the shader: multi-scale value + warm/cool hue noise. World triplanar on level geometry, UV on characters. Strength is a global |
| 4 | Atmosphere | Swaps too: dense sky-tinted haze, softer slightly desaturated grade. CEL gets today's environment back. Values are exports |
| 5 | Pixel size | Shared with PIXEL FILTER in both looks. PIXEL forces 3X when the filter is OFF. **6X** added to PIXEL FILTER |
| 6 | Not-cel things | Jump grid / blockout metre lines unchanged (fog still reaches them). pilot9's rim light off in PIXEL |
| 7 | Controls | `I` toggles LOOK live (was `P` until 2026-10-06). Settings rows **LOOK** (CEL / PIXEL) and **DITHER** (OFF / ON, dimmed in CEL). Saved; defaults CEL, dither ON |
| 8 | Dither | 4x4 Bayer laid out in pixel blocks, 16 levels per channel, or COLOUR DEPTH's levels if that is set. No palette remap |

## How it works

### The shader

`shaders/pixel_look/pixel-look.gdshader` + `shaders/pixel_look/grain.gdshaderinc`. Its own files;
the cel shader is not touched, so CEL is exactly today's look.

- Uniforms it shares by name with the cel base: `color`, `base_texture`, `uv_scale`, `uv_offset`,
  and the `paint_seed` instance uniform (apply_stylized stamps it). `grain_anchor` (UV / World)
  takes the cel material's `paint_anchor`.
- `light()`: wrapped Lambert (`look_wrap`), multiplied by attenuation so cast shadows still fall.
  Unlit sides are the Environment's ambient times albedo, which is what makes shadows coloured.
  No specular, no fresnel.
- Grain is applied to ALBEDO before lighting: three octaves of value noise, each stepped into a
  few flat levels so it clumps rather than blurs, lighter leaning warm and darker leaning cool.
  Each octave fades out as its cell gets smaller than about two rendered pixels (from `fwidth`
  of the anchor coordinate), so distant grain fades to the base colour instead of sparkling.

Globals in project.godot: `look_grain_strength`, `look_grain_value`, `look_grain_hue`,
`look_grain_world_size` (largest octave, metres), `look_grain_uv_size`, `look_wrap`.

### The switch

`scripts/rendering/pixel_look.gd` (`PixelLook`, a Node in group `pixel_look`) in trial.tscn.

- **To PIXEL:** walks every GeometryInstance3D in the scene. Any slot whose material runs the cel
  base shader (`material_override`, a MeshInstance3D's surface override, or the mesh's own surface
  material) gets a pixel twin in its place, with the slot's colour, texture, tiling and anchor.
  Twins are cached per source material, so shared materials share a twin. No next_pass, which
  drops the outline and crease ink. Every replacement is recorded so CEL can put it back exactly,
  including slots that had no override before. Nodes added while PIXEL is on (a respawn, a
  generated map) are swapped as they enter.
- **Environment:** the scene's WorldEnvironment gets a duplicate of its Environment with the
  PIXEL haze and grade; the original goes back on CEL.
- **Rim light:** pilot9 gets `rim_light_suppressed`, so his rim overlay stays off in PIXEL
  whatever `rim_light_enabled` says.
- `I` toggles the LOOK setting. Everything goes through Settings, so the menu row and the key
  agree.

### Pixel size and dither

Both reach PixelWorld through Settings:

- `Settings.effective_pixel_size(pixel_size, look)`: the PIXEL FILTER value, or 3 when it is
  OFF and LOOK is PIXEL.
- `Settings.dither_levels(look, dither, colour_depth)`: 0 unless LOOK is PIXEL and DITHER is ON;
  then COLOUR DEPTH's levels, or 16 when that is FULL.
- `pixel_world.gdshader` dithers with a 4x4 Bayer threshold indexed by the texel (block), so every
  block stays one solid colour.

PIXEL FILTER is now OFF / 2X / 3X / 4X / 6X. `[` `]` step through that list.

### Settings rows

- `look` (LOOK): `["cel", "pixel"]`, default CEL. Graphics section, after PIXEL FILTER.
- `dither` (DITHER): `["off", "on"]`, default ON. Dimmed with `CEL LOOK` while LOOK is CEL.
- PAINTED SHADING dims with `PIXEL LOOK` while LOOK is PIXEL: the grain replaces it.

## Not in scope

Particles, afterimages, speed lasers, the hologram, the light shafts, water and glow materials
are left as they are. No palette remap. test_platform.tscn does not get the switch.

## Tunables

Fog and grade are exports on the PixelLook node: `fog_density`, `fog_color`,
`fog_aerial_perspective`, `fog_sky_affect`, `saturation`, `contrast`. Grain and wrap are the
`look_*` shader globals.

## Built

2026-10-06, as specced, with these notes:

- **Swap root is PixelLook's parent** (the Trial root), not `current_scene`, so tests can run it on
  a small tree. Anything added anywhere while PIXEL is on is still caught through `node_added`.
- **Twins match the cel shader's lighting convention**: `light()` multiplies by ALBEDO like
  `base-cel-shader.gdshaderinc` does, so a slot's brightness stays comparable between looks.
- **Rim light**: `rim_light_suppressed` only re-applies overlays when the rim is enabled, so the
  hologram's stencil overlay is not disturbed in the default (rim off) setup.
- **MSAA / RENDER SCALE** rows also read `PIXEL FILTER ON` when the PIXEL look is forcing 3X.
- Starting values: haze density 0.008, `look_wrap` 0.5, grain value 0.22, hue 0.06, world size
  0.6 m, UV size 0.05.

Probe: `tests/_probe_look_shot.gd -- <out_dir>` (windowed) saves CEL / PIXEL 3X dither / PIXEL 3X
plain / PIXEL 6X / PIXEL with the filter forced / CEL again. In those shots the ink is gone, the
haze and grade show, and the floor grain and block dither are visible. CEL afterwards matches
CEL before.

Seen in the probe shots, to judge on the play: the white mech reads as a very bright, low-detail
shape (smooth light on pure white with no ink), and at 16 levels the dither is a visible fine
checker across the sky. Levers: `look_wrap` lower for more form, haze density, DITHER off or
COLOUR DEPTH 32.

## Softening pass (2026-10-06)

The user: "looks good, a little jarring and rough on the eyes". Read as temporal shimmer, not the
look itself: every block was a single point sample, so edges and grain specks near block size
snapped whole blocks on and off as the camera moved, and the 16-level Bayer was a hard checker.

- **2x supersample (PIXEL only).** WorldView renders at twice the block resolution and
  `pixel_world.gdshader` box-averages the 2x2 texels into each block (`supersample` uniform,
  `PixelWorld.apply_settings` 4th arg, `Settings.pixel_supersample(look)`). Edges get in-between
  blocks instead of popping. CEL stays at 1 so its ink lines stay solid black. Cost: 4x the
  pixels of the low-res render (1280x720 at 3X on 1080p), still well under native.
- **Dither 16 -> 32 levels** (`DITHER_DEFAULT_LEVELS`): half the step, so the checker is faint.
- **Grain fades earlier**: an octave is gone once its cells are under 4 rendered pixels (2 blocks),
  full at 8 (was 2 / 4 rendered pixels with no supersample).

Probe shots (`pixel_3x_old` vs `pixel_3x_dither`) show the sky checker gone and smoother edges.
Further levers if it is still rough: DITHER OFF, `look_grain_value` down, `PIXEL_LOOK_SUPERSAMPLE`
3 (softer, costlier), or a bigger block (6X) which flickers less per screen area.

## Whole screen (added 2026-10-06)

The user asked for the PIXEL look to reach "everything, like all the ui, menus". Built same day.

- `scripts/rendering/screen_pixel.gd`, autoload **ScreenPixel** (before Settings in
  project.godot): a CanvasLayer at layer 128, above the UI (100), with one full-screen ColorRect on
  `shaders/screen_pixel.gdshader`. It reads the finished frame (`hint_screen_texture`) and redraws
  it in blocks: HUD, prompts, pause and settings menus, the main menu (no PixelWorld there) and
  the hologram panel (which PixelWorld otherwise keeps sharp).
- On only in PIXEL; CEL keeps the sharp UI. Settings pushes it from the same LOOK / PIXEL FILTER /
  DITHER / COLOUR DEPTH branch that drives PixelWorld, with the same block
  (`effective_pixel_size`, so filter OFF is 3X here too) and the same dither levels.
- Same block grid as PixelWorld and the same quantize, now shared in
  `shaders/pixel_quantize.gdshaderinc`. The world under it is already one quantized colour per
  block, so averaging and re-quantizing it is a no-op; only full-res things change.
- Each block is the box average of its window pixels (not a nearest pick), so thin text strokes
  shade a block part-way and stay readable.
- Mouse filter IGNORE, so no menu click is eaten. The OS cursor is not affected.
- Probe: `tests/_probe_screen_pixel.gd` (main menu, off / 3X dither / 3X plain / 6X dither).
- **Menus force 2X** (2026-10-06; tried 6X and 3X, user picked 2X): while `UI.is_menu_showing()` (a screen on the stack, the main
  menu, or the hologram still closing) ScreenPixel draws at `MENU_BLOCK` 2 whatever PIXEL FILTER
  says, world included. CEL menus stay sharp.

## Reference pass (grilled 2026-10-06)

The user: "I don't love the dithering, and it doesn't reflect our reference photos." Side by side
with the flower-field reference: ours had a screen-fixed Bayer checker over everything (sky
included), a grain too faint and fine to survive the blocks, cool grey haze, and 3X blocks. The
reference has **no ordered dither**; its texture is all on the surfaces - hard-edged clumps of
2-3 hues a few blocks wide - under a warm golden-olive haze, at chunkier blocks.

| # | Question | Decision |
|---|----------|----------|
| 1 | The Bayer dither | **Removed.** The DITHER row and the Bayer path in `pixel_quantize.gdshaderinc` go; neither the world nor ScreenPixel dithers. Old saves' `dither` key is ignored |
| 2 | Surface texture | **Stepped palette clumps** replace the grain: each surface splits into hard-edged patches of three tones from its own colour - a darker cooler shade, the base, a lighter warmer tint. World space on level geometry, about 2-4 blocks wide at play distance. One global strength |
| 3 | Characters | **Clumps too** |
| 4 | Character clumps | **UV-anchored** (stuck to the body), about **half** the world clump size, same strength |
| 5 | Light | Smooth wrapped light cut into **4 soft steps**, clumps on top. Still no ink, no specular |
| 6 | Atmosphere | **Warm golden-olive** haze and grade in PIXEL on every map, a slight warm lift in the shadows; density about as before |
| 7 | Block size | **PIXEL defaults to 4X**, kept apart from CEL's (3X). The PIXEL FILTER row edits the active look's size; PIXEL has no OFF |
| 8 | Colour | **24 levels per channel** banding in PIXEL by default, no dither; COLOUR DEPTH overrides |

Unchanged: 2x supersample, menus at 2X, grid lines, rim light off in PIXEL, CEL itself.

### Built (2026-10-06)

- **Dither gone.** `pixel_quantize()` is plain rounding (`col, color_steps`); `dither_steps` is out of
  pixel_world / screen_pixel shaders, PixelWorld (`apply_settings(block, colour_steps, supersample)`),
  ScreenPixel (`apply_settings(block, colour_steps)`) and Settings (`dither` row, `dither_levels`,
  `DITHER_DEFAULT_LEVELS`). Old saves' `dither` key is dropped by `sanitise()`.
- **Clumps.** `shaders/pixel_look/clumps.gdshaderinc` replaces `grain.gdshaderinc`. A field of
  lightly domain-warped value noise plus a ragged detail octave, cut at 0.36 / 0.64 into shade /
  base / tint. **Two layers**: the near one at `look_clump_world_size` (0.09 m) and one 4x bigger
  that takes over once the near clumps shrink under ~2 blocks, so the texture carries into the
  middle distance instead of ending in a ring round the camera (the first probe did exactly
  that); the far layer fades to flat into the haze. World triplanar picks the **dominant plane**
  instead of blending, so bevels do not grow extra tones. Shade = darker x cool; tint = toward a
  warm cream `CLUMP_WARM` x warm, which also gives white (the mech) a visible third tone.
  Globals `look_clump_strength` 1, `_value` 0.14, `_hue` 0.08, `_world_size` 0.09, `_uv_size`
  0.035. Material uniform `grain_anchor` renamed `clump_anchor`.
- **Light steps.** `light()` cuts `wrapped * ATTENUATION` into `look_light_steps` (4) levels with
  `look_light_softness` (0.15) smoothstep edges, so cast shadow edges band the same way.
- **Haze.** PixelLook exports: fog `(0.70, 0.64, 0.45)`, aerial perspective 0 (the map's blue sky
  no longer cools it), sky affect 0.85 (sky goes golden), saturation 0.9, and
  `adjustment_color_correction` = a 1D ramp from `shadow_lift (0.07, 0.05, 0.015)` to
  `highlight (1.0, 0.97, 0.88)`.
- **Block size.** New hidden key `pixel_look_size` [2, 3, 4, 6] default 4. `Settings.pixel_filter_key(look)`
  picks which key the PIXEL FILTER row and the `[` `]` QA keys edit; `O` does nothing in PIXEL.
  `effective_pixel_size(pixel_size, pixel_look_size, look)`. tab_settings skips the key's own row
  (`ROWLESS_KEYS`) and binds the PIXEL FILTER row through `_bound_key()`.
- **Banding.** `Settings.colour_levels(look, colour_depth)`: COLOUR DEPTH, else 24 in PIXEL, else 0.
  Same value to the world and the screen pass.

Probe (`tests/_probe_look_shot.gd`, shots now `pixel_4x` / `pixel_4x_full` / `pixel_3x` / `pixel_6x`):
warm haze, no pattern on the sky, clumps from feet to haze, mech shaded in three tones. The 24
levels show as faint wide rings on the floor where the fog gradient crosses a step - expected,
the lever is COLOUR DEPTH or `PIXEL_LOOK_LEVELS`. Not yet played.

## 2026-10-12: pixel off by default, menus always sharp

User: "no more pixel menu. no more pixel shader at all, toggle it off and set it off by default."
PIXEL FILTER (`pixel_size`) now defaults to OFF (was 2X); LOOK stays CEL by default. ScreenPixel
no longer draws over menus in any look (`MENU_BLOCK` removed; `drawn_block` returns 0 while a menu
shows). The PIXEL FILTER row and the I key still exist as opt-in toggles.
