# Cinema look (intro space shot first)

2026-10-16. Grilled with the user from an editor screenshot of the intro planet: "make the space
look better... make EVERYTHING look better. colors are flat... some post processing... lens flare,
noise... gradients". Built on **shot 1 (`scenes/cutscene_intro_space.tscn`) only**. If it looks good,
the same stack goes onto the other cutscene shots (cockpit, cockpit storm, descent, flyover) later.
Gameplay scenes are out of scope.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Scope | **This shot first**, built so the other shots can take the same stack later |
| 2 | Flare source | **The ship's bright points** (engine glows, the glint, the re-entry flare) and hero stars. The sun stays behind the camera; the planet's lighting is untouched |
| 3 | Flare look | **Anamorphic**: a long thin cool-blue horizontal streak through each bright point plus faint oval ghosts. A screen-space pass, so any bright pixel in a later shot streaks too |
| 4 | Backdrop | **Full treatment, held back**: gradient wash (navy to teal, a touch of violet), stronger nebula, a diagonal Milky Way band with dark dust lanes, stars in several colours and sizes, a few hero stars that pick up the streak. Everything stays darker than the planet's night side |
| 5 | Planet | **Cel bands kept, gradients inside them**: ocean deeper navy at the limb, lighter teal facing the sun; snow (and the sky city) cooler toward the shadow side; blue atmosphere haze thickening toward the limb; a thin warm orange band on the terminator. In its own include, around the finished sky city code |
| 6 | Post stack | **Colour grade** (teal shadows, warm highlights, a little more contrast and saturation), **subtle moving grain**, **soft vignette**, **chromatic aberration at the edges only**, **bloom retune** (lower threshold so snow and limb glow). **No** lens dirt, **no** scanlines |
| 7 | Star motion | **Subtle twinkle on the bright stars only** (2-4 s cycle, about +-30%). Small stars and the nebula stay still. Driven by shot time, so seeking shows the same frame |
| 8 | Title card | **Grain only** on the title and coordinates (no fringe, no vignette). Title text becomes **EARTH 2329** |

## Build

- `scripts/rendering/cinema_post.gd` (`CinemaPost`, `@tool` CompositorEffect, post-transparent, HDR
  before the tonemap so the glow also blooms the streak). Compute passes: copy, bright extract at
  quarter resolution, horizontal streak blur (growing stride, ping-pong), composite (chromatic
  aberration, streak + ghosts, grade, vignette, grain). Every knob is an export.
- The shot's `WorldEnvironment` carries a `Compositor` with one `CinemaPost`. Lives in the shot's
  scene, so `Intro_Movie`'s SubViewports render it too.
- `shaders/space/planet_grade.gdshaderinc`: the in-band gradients, used by `planet_snow` and
  `planet_clouds`.
- `shaders/space/space_sky.gdshader`: gradient, band, coloured / hero stars, twinkle
  (`twinkle_time` uniform, set from the shot time by `intro_space.gd`).
- `intro_title_card.gd`: grain in the wipe shader; `title_text` = "EARTH 2329".

## Built

Built 2026-10-16. Departures and numbers:

- **Streak threshold 1.6**: above the trail cores (1.5) so the long trails do not smear across the frame,
  below the heat flare (2.2), glints (4) and lightning crawlers (3). Hero stars are 3.2 so they streak at the
  bottom of their twinkle too. Streak intensity 1.2, decay 0.82, 4 passes (stride 1/4/16/64).
- **Chromatic aberration 0.0012 from 0.6 out.** The first pass (0.004 from 0.45) split every star into
  an RGB triplet.
- **The band** passes through the only sky the camera sees (a strip on the right, view x 0.39-0.52):
  normal (-0.854, 0.215, -0.474), from the top right corner down behind the limb. Band stars kept sparse
  (0.09 chance); denser read as noise.
- **Glow threshold 0.75** (was 1.0). The old "only HDR glows" test now asserts the lowered range.
- **Sky radiance at its smallest** (`radiance_size` 32, reflections disabled): the planet has no specular, and the twinkle
  would otherwise re-render the radiance every frame.
- **The title card carries its own grain** (wipe shader, 0.18), because the compositor runs on the 3D image only.

## Streaks off (2026-10-16)

User, from a pan frame of the starfield: "get rid of the weird horizontal streaks". `streak_intensity` 1.2 -> 0
and `ghost_intensity` 0.25 -> 0 (the ghosts are copies of the streak buffer, so they went too). The passes still
run; set the intensities back to bring it back. Grade, grain, vignette and edge CA are unchanged.
