# hub2 PS1 mood pass

2026-11-13. Grilled with the user (7 questions), built the same day, probe-shot. Not yet played.
Builds on [hub2-industrial.md](hub2-industrial.md).

Ask: hub2 looked plain; get closer to a PS1 look.

## Decisions

- **Flavour:** moody Silent Hill / Resident Evil PS1, not colourful platformer, not hardware jank.
  The shader already had vertex snap, affine mapping and stepped shading; the gap was scene mood.
- **Order:** light, colour and fog before props. hub2 first, then promote to the shared AIRFRAME look.
- **Palette:** cold blue-grey base, warm sodium-orange accents, faint teal haze.
- **Light pools:** static, stepped, sodium (78 %), red (12 %), cold cyan (10 %).
- **Fog:** close, coloured, banded: starts 20 m, full at 95 m, 6 flat bands.
- **Sky:** stepped dusk gradient (orange horizon, teal, deep blue) and a few single-pixel stars.
- **Surface colour:** some steel wall zones painted teal or oxide red (zone = 30 x 15 m).
- **Character:** takes the environment's ambient and fog colour only; no per-pool sampling.

## Deviation from the grilled plan

Pools were meant to be baked into mesh vertex colours. hub2's big walls and floors are a few huge
quads, so vertex colour cannot hold a pool. Pools are instead evaluated per pixel in the surface and
decal shaders from a hashed world grid (`shaders/hub2_ps1.gdshaderinc`): one lamp may sit in each
14 m cell, so they are still static and deterministic and need no authoring or bake. Lamps float at
random points (they light whatever surface is near, there is no lamp prop). A hand-placed lamp list
would be the next step if pools should line up with fixtures.

## How it works

- `shaders/hub2_ps1.gdshaderinc`: `ps1_fog()` (banded), `ps1_pools()` (stepped, facing-weighted),
  uniforms for all tunables. Included by `hub2_wear.gdshader` and `hub2_decal.gdshader`, both
  `fog_disabled`; fog and pools are added as EMISSION so they agree on both.
- `resources/hub2_environment.tres`: cold ambient (0.5, 0.58, 0.8), same fog range and colour as the
  shader's, sky = `shaders/hub2_sky.gdshader`.
- `AirframeLook.environment_override` (new export): hub2 wears its own environment instead of the shared
  trial one. `sun_color` / `sun_energy` set on the node in `scenes/hub2.tscn` (warm, 1.5).

## Knobs

`pool_cell`, `pool_radius`, `pool_chance`, `pool_steps`, `pool_strength`, tints, `fog_*` in the
include; `paint_teal` / `paint_oxide` in `hub2_wear.gdshader`; sky colours and `bands` in the sky shader.

## Next

Promote to the shared AIRFRAME look once played and liked (trial keeps the old environment until then).
