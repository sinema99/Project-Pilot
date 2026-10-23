# Composite look on every shot

2026-10-19. Grilled with the user as the follow-up to [descent-composite.md](descent-composite.md),
whose closing note was "descent first; the other shots later". This is "later": the same
`DepthComposite` + `CinemaPost` look on the four other cutscene shots, each set up for what it is.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Scope | **The four other cutscene shots**: intro space, cockpit, cockpit storm, flyover. Descent is done. Ichi (gameplay) is out: the dark near band would sit on pilot9, and it would be the only per-frame cost in play |
| 2 | Kit | **CinemaPost on all; DepthComposite on all, its parts switched per shot.** Shaft cards only where light can fall through a break: flyover only |
| 3 | Intro space | Key = **the sunlit limb** (halo arc), near-white HDR, fading in as the opening pan lands. The **ship darkens** while it is close (bright behind, dark in front), back to normal as it shrinks. Planet wraps over the ship. **No haze** (vacuum) |
| 4 | Cockpit | Key = **where the fire enters the frame**, cream-orange HDR, the lobe **grows on the push** as the fire swallows the wake. **Dark band off**, slate lift/tint only (he is the subject). **Light wrap is the main event**: the fire over pilot9's silhouette. **Jolts dim** the light and wrap (a dropout, not a lift). No haze |
| 5 | Cockpit storm | Key = **the vanishing point**, cream, **swallowed 3-7 s** as the storm closes in (the beat of the shot). Dark band off; slate tint heading toward descent's slate-violet as the storm arrives (matches the cut). Wrap strong in the calm, near gone in the storm. **Lightning 7.5 / 9.0 s lifts** wrap and lift toward cool blue-white. No haze |
| 6 | Flyover | Key = **a cloud-deck break ahead on the horizon**, descent's cream; **3-4 shaft cards** from it onto the far city. Planes: **ship dark** (hull rim + nozzle glow stay on top) / hero tower + near city lit / far city into lavender haze warming to cream toward the break. Wrap far city + break over the hull. **Lightning 1.2 s lifts** the dark band (the ship) |
| 7 | Grade | **One shared CinemaPost resource** (`resources/cinema_post.tres`) on all five shots, on its script defaults (both existing shots used the defaults). Per-shot colour comes from each DepthComposite, never the grade |

## Build

- `resources/cinema_post.tres`: the shared CinemaPost, `resource_local_to_scene` so each shot (and each
  Intro_Movie SubViewport) gets its own GPU state while the file stays the one place to tune.
  Descent and intro space switch to it.
- `DepthComposite.screen_uv(camera, point)`: a world point to the light's screen UV. Each shot that moves
  its camera places its light from a world point every frame, so the light stays on its thing.
- Each shot's WorldEnvironment carries `Compositor [DepthComposite, CinemaPost]`; the shot's driver pushes
  the per-frame values (light position, energy, radius, wrap, flash) from its own shot clock, so seeking
  shows the same frame.
- Flyover shafts reuse the descent card mesh and shader (`DescentShafts.card_mesh` from world points).

## Built

Built 2026-10-19, probe-tuned per shot. Departures and numbers:

- **Intro space: the light is toward the sun, just off the left edge.** The planet's day side faces off
  screen left all shot (the Sun is up, left and behind the camera). First built on the right-hand
  (night-side) limb because it was the only limb in frame; 2026-10-19 the user saw the contradiction
  (lit left, glow on the dark right) and it moved. `sun_uv()` runs the Sun's screen direction from the
  centre out to `sun_edge_margin` (0.05) past the edge, about uv (-0.03, 0.10), so it washes onto the lit
  side. Near-white 0.6 HDR, radius 0.12 stretched tall (0.6), fading in over shot 0-2.5 s. Ship band
  150-900 m at 35%; planet + stars are the background from 2-2.8 km.
- **Cockpit:** light at the fire source (`ReentryFire.source_direction` on the sphere) clamped 0.04 past the
  frame edge, which lands it lower left; cream-orange 0.8, radius 0.25 growing 2.2x with the swallow; wrap
  1.2 (the background is the sphere past 2.6-3.3 m; pilot9 sits about 1.5 m off the camera); jolts drop
  light and wrap by 60% on `CockpitShake.flash`. Near band 92% with a faint slate tint and lift.
- **Cockpit storm:** light on the vanishing point (the antipode of `StormBeats.ahead`), which sits just
  right of his head. 0.5 / r 0.2 calm, 0.06 / r 0.12 full storm; wrap 0.5 to 0.06; tint and near value lerp
  to descent's slate-violet / 80%; lightning pushes `flash` (near band to 100%, cool tint) and +0.6 wrap.
- **Flyover: there is no horizon in frame.** The camera looks 35 degrees down; the frame's top edge
  meets the ground about 2.5 km out. The break sits 8 degrees below level on the camera's look heading,
  just above the top centre, and bleeds in. Shafts are 4 cards with feet 1.3-1.75 km out and tops 800 m
  up, leaning 500 m back toward the break.
  - The streets are painted in the sky shader (no depth), so they read as infinitely far and the haze and
    light washed the frame: new **`sky_distance`** (1200 m here) gives sky pixels a distance.
  - The nozzle glows are transparent quads over the dark hull and went grey: new **`dark_keep`** (0.8
    luminance here) lets bright pixels escape the near band.
  - The ship at 62% with a light slate tint keeps a trace of its red; haze 0.35, light 0.45.
- **`DepthComposite.screen_uv` is a pinhole projection**, not `Camera3D.unproject_position`: unproject gave
  distance-dependent nonsense for the flyover's far break point (10 km, past the 8 km far plane).
- **Glow added to both cockpit environments** (tonemap linear, HDR threshold 1, descent's levels) so the key
  light blooms; the seat's red alarm lamps now bloom too.
- Shared CinemaPost verified: every instance of every shot gets its own copy (two intro instances included).
- `DescentShafts` gained `build_cards` / `card_mesh` (world-point cards); the descent table goes through it.

## Tamed

2026-10-19, user: cockpit storm "hard to see, so bloomy". The composite's hotspot and wrap, not the
engine glow. Calm light 0.5 -> **0.3**, radius 0.2 -> **0.15**, wrap 0.5 -> **0.25** (`CockpitStormDriver`
calm exports + the scene's starting values). Storm-end values and the lightning lift unchanged. Intro
space, cockpit and flyover untouched.
