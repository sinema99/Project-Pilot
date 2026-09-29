# pilot9 rim light

2026-09-25. Reference: a Marvel Rivals character render (Star-Lord) the user shared, where a thin
white edge light runs along one side of the character's silhouette, just inside the ink line.

## What it is

A hard-edged white rim on **one side** of pilot9's silhouette, **inside the black ink line**. Cel,
not soft: a sliver of paint rather than a glow.

## Scope

- **pilot9 only.** Not the map, not Setsuna, not the mech.
- **Its own shader**, `shaders/cel/rim_light.gdshader`, with its own material
  `resources/pilot_rim_light.tres`. The cel base shader is untouched.
- **Toggleable**: `rim_light_enabled` on pilot9 (Inspector, "Rim Light" group). Off removes it
  completely.

## How

- Applied as `material_overlay` on every MeshInstance3D under pilot9's `character`. An overlay
  draws the mesh a second time on top of all its surfaces, so it does not collide with the
  per-surface cel materials `apply_stylized.gd` stamps on.
- The side is a **screen-space direction** (`rim_direction`, default upper-left), not the sun.
  It stays on the same side of the screen however the camera orbits, which is what the reference
  does, and it keeps working in shadow.
- **Silhouette only, never interior.** Screen-space depth test: step `rim_width` pixels toward
  the light and read the depth buffer. More than `depth_threshold` metres behind pilot means
  background, so this pixel is on the lit edge of his outline.
- **Thickness follows the mesh** (2026-09-25, after the fourth look: "have it arc nicely"). The
  surface normal's screen direction says which way the edge faces; the rim is `rim_width` thick
  where it faces the light, thinning (`rim_taper`) to `rim_width_min` where it is side-on. So it
  swells and runs out in crescents instead of an even stroke. On flat faces the normal is one
  value per face, so a box gets one thickness per face rather than a curve along it.
- **Under the ink.** The ink's inverted hull lays some black over pilot's own edge pixels, and
  this pass draws after it. Any pixel already ink-coloured (the `outline_color` global, within
  `ink_tolerance`) in the screen texture is left black.
- Unshaded, alpha-blended (transparent pass), no depth write. Hidden with the mesh during the dash.

## Revisions, all 2026-09-25

1. Fresnel rim - lit interior overlaps (arm across the chest). Replaced by the depth test.
2. Depth test, inside the silhouette - "needs to go behind the black outline".
3. Inverted hull pushed past the ink - put the white *outside* pilot's edge. Wrong: the user
   wants it inside. What "behind" meant is the ink staying on top where the two meet.
4. Depth test inside the silhouette + ink pixels spared.
5. Thickness varies with the edge's facing, for crescents (current).

## Tunables (on the material)

| uniform | default | meaning |
|---|---|---|
| `rim_color` | white, alpha 1 | colour; alpha is overall strength |
| `rim_direction` | (-1, 0.35) | screen-space side the light comes from (x right, y up) |
| `rim_width` | 5 px | thickest point, where the edge faces the light |
| `rim_width_min` | 0 px | thickness where the edge is side-on; 0 runs out to nothing |
| `rim_taper` | 1.5 | falloff; higher = thin for longer, sharper crescent |
| `depth_threshold` | 0.6 m | how far behind pilot counts as background; must beat arm-over-chest depth |
| `ink_tolerance` | 0.04 | how near the ink colour a pixel must be to stay black |

## Known limits

- A wall or object closer behind pilot than `depth_threshold` hides the rim along that stretch.
  Lower the threshold and body overlaps start lighting.
- Pilot's own near-black paint, where it falls on the rim, is also spared (reads as ink).
- Needs the Forward+ renderer's depth and screen textures (the project default).
- Look and feel can only be judged in play; the tests cover wiring and toggling.
