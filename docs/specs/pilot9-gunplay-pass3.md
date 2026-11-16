# pilot9 gunplay pass 3 - shooting effects (2026-11-15)

Grilled, then built. Both guns share `scripts/items/gun_fx.gd`; the revolver is the "heavy" profile
(`not GunDef.ejects_casings`). Always on, no toggle. Pixel sprites (procedural textures, nearest, unshaded,
alpha-cut) for flash / smoke / impact bursts; chunky cubes for casings, embers and sparks. Capped at 60 live sprites.

- **Muzzle flash**: 5 frames x 0.018 s. Two crossed forward-jet quads (3 shape variants, random roll) cooling
  white > yellow > orange > red > dark, plus a 2-frame starburst, plus 5 colour-ramped ember cubes flung forward.
  Revolver 1.6x bigger and one frame longer.
- **Light**: OmniLight 5.5 m, no shadows, colour stepped warm-white / orange / dull red over ~0.08 s, +-25% brightness
  per shot, revolver 1.5x.
- **Smoke**: each shot adds 1 heat; heat drains at 1/1.5 per s (revolver 1/3). Heat >= 2.4 lights the barrel (3 quick
  rifle shots), it keeps smoking until heat < 1.2 (~2 s after stopping). Wisps are 4-frame dithered sprites that
  wobble upward and tint warm to cool. Below the threshold each shot only puffs once (revolver twice).
- **Tracer**: head 900 m/s (was 260), 3 m long; a 3-band trail steps yellow > orange > red and vanishes in 0.15 s after the
  head lands. Revolver 1.5x thicker.
- **Casings**: rifle only, now eject to the shooter's right (item local +X). Revolver still keeps its brass.
- **Impacts**: 3-frame burst, 2 surface-tinted dust puffs (red on enemies), 7 sparks that bounce once, hole unchanged.

Tests: `tests/test_gun_fx.gd`. Feel is judged in play; tuning knobs are the consts at the top of gun_fx.gd.
