# Retro Look, pass 3 — CEL's palette, RETRO's drawing

Status: grilled, specced and built 2026-10-22.

The user sent a CEL screenshot of trial (bright blue sky, grey clouds, dark grey floor, teal and
orange blocks): "I like the color palette of this, but I like the outlines and look of retro."
RETRO keeps how it draws and takes CEL's colours. CEL, PIXEL and every cutscene are unchanged.

## Decisions (grilled 2026-10-22, every recommendation taken)

| # | Question | Decision |
|---|----------|----------|
| 1 | What reverts | Every colour piece of passes 1-2 goes; the drawing stays. Contact shadows stay but neutral grey; floor panel lines stay as a darker shade of CEL's floor |
| 2 | Environment | Exactly CEL's: Filmic, full ambient, CEL fog, no grade ramp, no haze. Video pass saturation 1.0 (soften / bleed / grain / vignette kept). Pass 2's white clipping was a Linear-tonemap problem, so it does not come back |
| 3 | Cel shade bias | Kept at -0.25 (value, not hue); ease to -0.15 if the pilot reads too dark |
| 4 | Background shadow | CEL's 0.45 (pass 2's 0.62 would lift trial's floor, which sits in shadow tone). Soft gradient + brush grain kept |
| 5 | Clouds | Painted shapes kept, in CEL's grey (0.64) with a darker neutral underside (0.5) |
| 6 | Line colour | Same width / value / from-the-fill; `ink_warmth` 0.35 -> 0.1 |
| 7 | Old values | Replaced, no second switch. They are recorded in retro-look-pass-2.md; the shader knobs stay |

## What changed

- `RetroLook.pixel_environment` is now a copy of CEL's environment with only the sky material
  swapped for `painted_sky` (which sets `clouds_paint` 1 and `clouds_shade_color` only). Removed:
  Linear tonemap, `ambient_scale`, black/white points, haze, sky/cloud colour exports.
- `shadow_tint` export removed (twins no longer set it; the shader default is neutral).
- `bg_tint` white, `bg_shadow_tone` 0.45, `floor_color` export removed (no deck),
  `floor_line` = black at alpha 0.3 (a darker shade of whatever the floor is), `contact_tint` grey 0.6,
  `cloud_shade` grey 0.5, `ink_warmth` 0.1.
- `resources/retro_post.tres` saturation 0.9 -> 1.0.

## Built (2026-10-22)

Probe shots of trial (tests/_probe_retro_shot.gd, RETRO first) match the screenshot's palette: blue
sky, grey clouds, dark grey floor with faint 4 m panels, teal/orange/red blocks as in CEL; pilots
inked with a visible shadow side at -0.25, so no tuning was needed. tests/test_retro_look.gd
updated to the pass 3 expectations. Not yet played.
