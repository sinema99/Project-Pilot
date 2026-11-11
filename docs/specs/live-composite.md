# COMPOSITE look (the cutscene composite in live play)

2026-11-04. Grilled with the user. The question was whether the cutscene composite can run in
gameplay at all. It can: `DepthComposite` and `CinemaPost` are per-frame passes on whatever camera is
active. Measured on `trial`, RTX 3060, 1440p, 8x MSAA: `DepthComposite` +0.27 ms, `CinemaPost` +0.47 ms
(RETRO already pays the second one). The old reason for leaving gameplay out (shots-composite.md,
"the only per-frame cost in play") stopped being true when RETRO shipped its video pass.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | The switch | COMPOSITE replaces the other looks. RETRO stays the default and does not change |
| 2 | LOOK row | **RETRO / COMPOSITE**, I flips them. CEL and PIXEL leave the row and the key; saves on them load as RETRO. Their code stays: RetroLook extends PixelLook and RETRO uses CEL's environment |
| 3 | Finish | `resources/composite_post.tres`: the cutscene grade, vignette, grain and fringing, plus RETRO's soften and chroma bleed. Probe it on RETRO's flat fills and tone down if too strong |
| 4 | Maps | Settings are exports on `RetroLook`, overridable per map. Tune `trial`; probe `starter_map`, `boss_arena`, `internals`. `internals` has no sun or sky, so no light and no wrap. Ichi has no RetroLook, so it is out and I does nothing there |
| 5 | Dark band | Brightness 0.6 (cutscenes 0.28), full dark to 6 m, gone by 60 m. Bright things escape it |
| 6 | Light | The map's real sun, placed every frame, faded out when off screen or behind the camera. Near geometry blocks it for free (it only touches far pixels). Energy 0.3, wrap 0.25 |
| 7 | Other rows | PIXEL FILTER, COLOUR DEPTH, PAINTED SHADING and CEL SCATTER leave the menu, with their QA keys (O, [, ], \\). Saved values load as their defaults so Ichi and the cutscenes stay as they are. ANIMATION stays |

## Build

- `RetroLook` owns COMPOSITE: `apply_composite(on)` swaps the WorldEnvironment's compositor between the
  video pass and `[DepthComposite, composite_post]`. Both compositors are built once, so flipping does
  not recompile shaders. COMPOSITE only exists while RETRO is on; turning RETRO off drops it first.
- `RetroLook.sun_view()` turns the sun direction into a screen UV and a 0-1 strength. It replaces
  `DepthComposite.screen_uv` here because that one mirrors points behind the camera.
- `RetroLook` runs at a late `process_priority`, so the glow reads the camera after it has moved.
- `DepthComposite.dark_keep_chroma` is new (0 by default, so the shots do not change): a colourful pixel
  escapes the dark band. `dark_keep` alone cannot do decision 5, because the game's glows are ordinary
  colours. A hostile bolt is about 0.23 luminance and white armour about 1, so any luminance threshold
  that frees the bolt also frees the armour.
- `Settings.HIDDEN_KEYS` resets the four removed rows on load. The rows stay in `DEFS` because the code
  that reads them stays.

## Built

Built 2026-11-04, tuned from probe shots. Not yet played. Departures and numbers:

- **`composite_keep` is 2.5, not the first 1.5.** At 1.5 the white mech skipped the band entirely. Glows
  are held by `composite_keep_chroma` 0.75 instead: the cyan rail stays bright in the band.
- **`internals` overrides four values** on its RetroLook node: band 0.8, near-neutral tint and lift, and
  its own fog colour for the haze. The defaults turned the map navy and took the pilot's colour. That
  needed two new exports, `composite_dark_tint` and `composite_dark_lift`.
- **`boss_arena` needed nothing.** Haze and glow read well over the baked backdrop.
- **`starter_map` needed nothing.** It is a white blockout and RETRO clips it to pure white at spawn;
  COMPOSITE's haze reads better there. The spawn camera sits against a wall.
- **The pause menu needs no handling.** The hologram panel looks the same in both looks (probe shots of
  each), so the planned fallback of dropping the band while it is open was not built.
- **`flat_fill` is on every RETRO twin** (`RetroLook._flat`), so PAINTED SHADING and CEL SCATTER really did
  nothing there.

Measured in motion on `trial` (run + full-stick camera sweep across the sun, 1440p, 8x MSAA): 4.9-5.5 ms
GPU per frame, and the glow never moved more than 0.042 energy in a frame. A first run showed a 0.14
step; that was the probe's own screenshots stalling the game, and it went away with them off.

Not checked: frame-to-frame edge flicker on outlines and other depth-free effects. Moving stills look
clean, but that is a call for playing it. The firing range's bolts were not on screen in any probe, so
the chroma escape is only proven on the rail.
