# Cargo container (2026-11-13)

Decoration for hub2: a 20 ft shipping container in ten colours, built in code. Grilled 2026-11-13
(8 questions). Status: built, tests green, probe-shot in hub2 under AIRFRAME; not yet played.

## Decisions

1. **Built in code** (`scripts/cargo_container.gd`, `CargoContainer`, `@tool`, extends StaticBody3D). One
   ArrayMesh with vertex colours, flat normals, no textures/UVs. `scenes/cargo_container.tscn` is the reusable scene.
2. **Size:** real 20 ft, 6.058 x 2.591 x 2.438 m (L x H x W), one length. Origin bottom centre, doors at +X.
3. **Solid and static.** Doors are cosmetic (two doors, bands, dark centre gap, locking rods, handles); the -X end is a plain ribbed panel.
4. **Look:** clean pixel look, no wear, not touched by the hub2 wear pass. Under AIRFRAME the vertex-colour material is cut into 16 texel/m pixels.
5. **Palette:** `palette` dropdown, ten presets: ORANGE_RED, BLUE, PALE_YELLOW, TEAL, BLACK, PINK, BROWN, ORANGE, GREY, CYAN.
   Rib light / valley dark / casting shades derive from the base colour. Changing it rebuilds live in the editor.
6. **Collision:** one box round the shell; ribs, castings and rods are visual only.
7. **In hub2:** `CargoContainers` node east of the map (x = 440, map ends at x ~ 402 at 0.6 scale), one container per colour in a row
   (z 61.75..102.25, 4.5 m apart), on a deletable `StagingSlab` (30 x 1 x 56 m, top at y = 0). The user hand-places them from there.

## Gotchas

- **PINK is deliberately not magenta.** `shaders/pixel_world.gdshader::is_marker` keys min(r,b) > 0.5 and g < 0.75 * min(r,b) as the
  character marker; a magenta container pixel got keyed out to black (black rails). Pink is (0.92, 0.58, 0.64). Keep any new colour clear of that test.
- Vertex colours go in as linear (`srgb_to_linear`), matching StandardMaterial3D and the PS1 surface shader.
- `.tscn` comments start with `;`, not `#` - a `#` line swallowed the nodes after it.

## Files

`scripts/cargo_container.gd`, `scenes/cargo_container.tscn`, `scenes/hub2.tscn` (CargoContainers), `tests/test_cargo_container.gd`.
