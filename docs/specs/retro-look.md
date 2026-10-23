# Retro Look — 90s anime cel, gameplay only

Status: specced and built 2026-10-21, not yet played.

The user brought a frame from a 90s anime film (a chase across a blue-grey deck, a girl in an
ochre jacket) and wanted that look in gameplay, not in the cutscenes, tested in trial. They felt
the cel look was already close. What the frame has that CEL does not: **coloured** lines (a darker
shade of each fill, not black), thin lines, flat two-tone fills, a muted warm palette with no pure
white or black, cool shadow paint, and a soft video transfer (blur, colour bleed, grain).

## Decisions (grilled 2026-10-21, every recommendation taken)

| # | Question | Decision |
|---|----------|----------|
| 1 | Where it lives | A third look on the LOOK switch: CEL / PIXEL / RETRO. Its own node in trial; cutscenes never load it |
| 2 | Line colour | Each surface's own fill, darkened (to 0.4 of its brightness) and nudged toward red-brown |
| 3 | Line width | 2.5 px, constant, hard (CEL is 4 px) |
| 4 | Fills | Two flat tones only: painted shading, cel scatter and specular/fresnel off in RETRO |
| 5 | Palette | A screen grade: saturation ~0.8, blacks lift to warm brown, whites cap at cream ~0.92, slight warm shift |
| 6 | Shadow tone | Blended ~30% toward a cool violet (0.55, 0.5, 0.7) |
| 7 | Video pass | Subtle ~1 px blur, sideways chroma bleed, fine moving grain, light vignette. No gate weave, no scanlines. Built by extending CinemaPost; gameplay gets its own instance |
| 8 | Rim light | pilot9's rim light off in RETRO |
| 9 | Environment | A copy of the scene's Environment with the Linear tonemap; sky, fog, ambient unchanged |
| 10 | Switching | LOOK row CEL / PIXEL / RETRO, `I` cycles all three, **RETRO is the default** |

## How it works

### The switch

`scripts/rendering/retro_look.gd` (`RetroLook`, group `retro_look`) extends `PixelLook`: the same
walk, record and exact restore, the same swap-on-arrival for nodes added while it is on. Only the
twin and the environment differ. Settings turns the old look off before the new one on, so only one
of the two nodes holds materials at a time. `I` lives on PixelLook only and cycles CEL -> PIXEL ->
RETRO.

### The twin

Every cel-base slot gets a duplicate of its material (same shader, so the two-tone light is the
real cel light) with:

- `flat_fill = true`: the cel shader skips painted shading and scatter for this material (per
  material, so the PAINTED SHADING / CEL SCATTER rows do not fight it; they show CEL ONLY in RETRO).
- `specular.a` and `fresnel.a` = 0.
- `shadow_tint` = (0.55, 0.5, 0.7, 0.3): the shadow tone is mixed toward this colour by its alpha.
  Default alpha is 0, so CEL and the cutscenes are untouched.
- `next_pass` = a duplicate of the outline material with `ink_from_fill = true`, `ink_width = 2.5`
  and the fill's `color`, `base_texture`, `uv_scale`, `uv_offset`. The hull samples the same
  texture at the same UV, so a textured fill gets a matching line, texel by texel. Ink = fill
  darkened in sRGB to `ink_value` (0.4) and mixed `ink_warmth` (0.35) toward a red-brown of the
  same brightness. A slot whose cel material had no outline gets none.

### The grade and the video pass

- The Environment copy: tonemap Linear, `adjustment_color_correction` ramp from warm brown
  (0.09, 0.065, 0.055) to cream (0.94, 0.91, 0.84). Exports on the node.
- The WorldEnvironment's `compositor` is set to `resources/retro_post.tres` (a Compositor holding a
  CinemaPost) while RETRO is on, and put back after. Its grade does saturation 0.8 and a slight
  warm split; grain, vignette, plus two new CinemaPost knobs:
  - `soften` (px): a small tent blur on every tap.
  - `bleed` (px) and `bleed_amount`: chroma taken from a wide horizontal average, luma kept sharp.
  Both default 0, so every cutscene's CinemaPost renders exactly as before. They ride in the
  composite pass's spare push-constant floats (still 128 bytes).
- The UI is not touched (the compositor is 3D only).

## Built (2026-10-21)

As above, with three probe-driven departures (tests/_probe_retro_shot.gd, trial at 2560x1440):

- **Line width units.** The hull's `outline_width` is the push; the visible line is half of it, so CEL
  actually draws 2 px. "Thinner than CEL" was a wrong premise. `ink_width` is the VISIBLE width in px
  at 1080p, scaled with the viewport height: 2.5 (3.3 px at 1440p), which is the frame's line as a share
  of its height.
- `ink_value` 0.4 -> 0.25: at 0.4 the line on light fills was within ~10 levels of the fill.
- `soften` 1.0 -> 0.6: 1 px of tent blur ate most of a 2 px line.

Watch: grey clouds read tan under the warm grade; trial's sky is a bright teal next to the frame's
muted backdrop. Both are grade/environment exports if the user wants them changed.

## Not in scope

Cutscenes; a painted backdrop sky (option C of question 9, held until the user has seen this);
distance-faded lines; gate weave and scanlines.
