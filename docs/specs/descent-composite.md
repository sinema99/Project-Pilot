# Descent composite look

2026-10-18. Grilled with the user from a frame of the descent shot ("it looks flat") held against a
reference online: a cel-shaded desert shot shown as "Raw Render" and "Final Composite". The user wants
our shots to look like the composite. **Descent shot (`scenes/cutscene_descent.tscn`) first**; the
other shots later.

What the composite adds over the raw render, read off the reference: a strong value hierarchy (near
almost black, far almost white, steps between), light wrap (the bright background bleeds over the
dark edges in front of it), haze that lifts and flattens the distance toward the light colour, soft
light shafts, and one grade that tints even the darks. Ours reads flat because nothing is the
brightest thing in the frame: snow, sky and mountains share one pale lavender, the ruin frame is a
hard flat #0a0d12, and the grade never reaches the darks.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Key light | **The pale gap in the storm, centre-right behind the mountains** (where the trail comes in) is the light everything organises around. Near-white HDR there so it blooms; left-dark (storm wall) / right-bright diagonal |
| 2 | Where it lives | **A post pass on top**: a new CompositorEffect reading the depth buffer, before **CinemaPost** (now also on descent for grade, grain, vignette, edge CA). The world only gets light where the gap is |
| 3 | Near snow | **Dark band at ~25-30%**: near snow (to about the first trees) is dark slate with its texture faintly visible; the tree and wreck line is the lit band; city, mountains and the gap fade up into bright haze. Three planes: dark / lit / glowing |
| 4 | Shafts | **World-space shaft cards** (like the reference's raw render, and like our snow curtain): 4-6 slanted soft additive quads falling from the cloud-break rim onto the city/mountain band, slow breathing opacity, bumped by lightning. No screen-space radial blur |
| 5 | Colour | **Cool shot, one warm note**: the break and shafts pale cream (~#FFF4E6), the only warm thing; darks slate blue-violet (~#1C2030 on the ruin, lighter slate on the snow) from the existing lavender; haze stays lavender, lifting to cream near the gap; teal storm wall and cyan lightning unchanged |
| 6 | Lightning | **A flash lifts the dark band** toward cool blue-white (~28% -> ~60%) on the existing pulse curve; the ruin keeps its rim and stays dark; break and shafts stay steady |
| 7 | Scope | **General `DepthComposite`** next to `cinema_post.gd`, every value an export; only descent carries one for now. Shaft cards are descent-only. Lives on the shot's WorldEnvironment, so Intro_Movie gets it too |

## Build

- `scripts/rendering/depth_composite.gd` (`DepthComposite`, `@tool` CompositorEffect, post-transparent,
  HDR before the tonemap so the environment glow blooms the break). Reads colour + depth; distance from
  the inverse projection.
  - **Wrap source**: the far pixels (past `wrap_far`) at quarter resolution, premultiplied by how far
    they are, blurred (separable, a few passes).
  - **Composite**, per pixel, from its distance `d` (log scale) and its screen distance to `light_uv`:
    - *Dark band*: below `lit_start` the colour is multiplied down to `near_value` and tinted
      `dark_tint`, with `dark_lift` added so pure blacks become slate. `flash` lerps `near_value` to
      `flash_near_value` and the tint toward `flash_tint`.
    - *Haze*: past `haze_start` the colour mixes toward the haze colour (lavender, toward cream inside
      the light lobe), scaled by `haze_amount` and the wide light lobe, so the storm deck far from the
      gap keeps its weight.
    - *Break*: far pixels inside the light lobe get `light_color * light_energy` added (HDR).
    - *Light wrap*: near pixels get the blurred far colour added at `wrap_strength`.
- The shot's WorldEnvironment carries a `Compositor`: `[DepthComposite, CinemaPost]`.
- `scripts/cutscene/descent_shafts.gd` (`DescentShafts`): shaft cards from a table on `DescentShot`
  (`SHAFTS`: top sketch x, foot sketch x, foot distance, widths, strength, phase), unshaded additive
  shader, soft edges, fade toward the foot, slow breathing from shot time, a lightning bump.
- `DescentShot.apply(t)` pushes `flash` into the composite and the shafts. `light_px` (sketch px) on
  `DescentShot` places the light; it is mapped to screen UV the same way every sketch pixel is.

## Built

Built 2026-10-18. Departures and numbers:

- **Near band ramps over 15-400 m**, not a step at ~150-350 m: at 1.7 m eye height the visible snow is 7 m
  to the horizon, so a step put one flat colour over the whole field. The ramp gives a dark-to-light
  gradient up to the lit tree and wreck line.
- **Light 0.55 HDR at radius 0.16** (first pass 1.2 / 0.22 blew the whole gap into a white disc), squashed
  1.6x along the horizon. Haze 0.5, 25% left outside the wide lobe so the storm wall keeps its weight.
- **The flash lifts only beyond 12 m** (`flash_start`), so the ruin around the camera stays dark (row 6).
- **Shafts at energy 0.5**; they read around the light and fade out over the city.
- The snowflakes have no depth, so they take the treatment of what is behind them (darker over the near
  band). Left as is.

## Tamed

2026-10-19, user: "washed out". The engine glow was not the cause (glow off looked the same); it was the
composite's light lobe and haze. Light 0.55 -> **0.38**, radius 0.16 -> **0.12**, haze 0.5 -> **0.35**, set on
the descent scene's DepthComposite (the script defaults are unchanged, other shots inherit them). Shafts,
dark band and lightning untouched. The gap is a hot core now and the ridges and towers by it read.
