# hub2 industrial texturing pass

2026-11-13. Grilled with the user (11 questions), then built the same day. Built, probe-shot, tests
green; not yet played. Builds on [hub2.md](hub2.md) (the map scene).

Ask: make the hub2 map look like an industrial place: darker edges and corners, edge wear, vents on
some walls, random decals.

## Decisions

- **Technique:** a procedural world-space shader plus a baked edge/corner field. No UVs, no textures
  on the surfaces. Same pixel grid as the Jetpack look (16 texels per metre).
- **Palette:** cold, desaturated steel and concrete (albedo is a touch warm so the scene's blue
  ambient lands on grey, not saturated blue). Hazard yellow and orange only in small decal accents,
  rust only at the bottoms and creases, dark grime in the corners.
- **Edge wear:** dark grime in concave corners and creases (stepped, rust creeping out of the low
  ones); convex edges get a dark band with ragged chips of dull bare metal and a few bigger bites;
  corners (two lines near at once) darker still.
- **Surfaces by orientation:** walls = 6 x 3 m panels, seams with a lit lip, rivets, faint 1.5 m plate
  lines, steel/concrete zones 30 x 15 m, grime streaks hanging below each horizontal seam. Floors =
  diamond tread in 3 m plates, lighter walkway wear. Ceilings/undersides = dark ribbed steel.
  Everything near the bottom of the structure (`ground_y` up 14 m) is dirtier and rustier.
- **Vents and decals:** auto-scattered from the mesh with a fixed seed, drawn in code (no imported art):
  vents (square, small, wide, tall, round fan), hazard stripes, warning triangles, chevrons, data
  plates, pipes, stencil labels (20 strings, 3x5 font at 2x), grime streaks (hang under vents), rust
  blobs, floor scuffs, amber/red lamp clusters and status strips (the glow layer lights those).
  Alpha is cut out (0 or 1), so they sit in the same flat pixel style.
- **Visual only:** decals have no collision and the wear changes no geometry; the map keeps the
  glb's own trimesh collision, so wall-run / climb / mantle behave as before.
- **Bake:** offline, `tools/bake_hub2_wear.gd` -> `assets/hub2_wear/` (re-run after a hub2.glb
  re-export; `Hub2Wear` warns and leaves a mesh plain if its bake no longer matches). Decal placement
  is fixed, so "that vent on the second wall" can be found again.
- **Emissive:** a few small amber and red lamps / status strips, baked into the glow layer, no real lights.
- **No toggle.** hub2 just wears it. To revert: take `Hub2Wear` out of `scenes/hub2.tscn` (and put
  `ApplyCelGround` back if the old cel-ground look is wanted; that node was removed because its
  material_override would paint over the wear).

## How it works

- `scripts/hub2_wear_bake.gd` (`Hub2WearBake`): welds the map's meshes, classifies every edge
  (smooth under 25 deg, else convex / concave), floods "regions" of smooth faces, and cuts the map's
  separate pieces against each other to find seams where one goes into another (the glb is boxes
  poking into a big shell, so there are no shared edges there). Each triangle is un-indexed, cut to
  <= 12 m (3 m near a seam) only where a line is near it (kilometre-wide faces stay whole), and gets
  `CUSTOM0` = signed distance in metres from each vertex to its 4 nearest lines (a distance to a line
  is linear across a face, so the GPU interpolates it exactly), `CUSTOM1` = what each line is
  (0 none, 1 convex, 2 concave, 3 seam). A region's lines go to every triangle of the region, so a
  quad split in two never shows its diagonal. Distances are in world metres (the scene scales Map by
  0.75, `WORLD_SCALE`).
- `scripts/hub2_decal_atlas.gd` (`Hub2DecalAtlas`): the decal sheet, 512 px, colour + glow images.
- `Hub2WearBake.scatter()`: places decals on faces by area, kept clear of every line (corners tested
  against the line distances), nothing in front of them (ray test), no overlaps. Density fades to 12 %
  on faces far from anywhere he can stand. 14 000 cap; ~11 300 placed.
- `shaders/hub2_wear.gdshader` (surface), `shaders/hub2_decal.gdshader` (decals, clip-space depth bias
  so they don't z-fight far away).
- `scripts/hub2_wear.gd` (`Hub2Wear`, a node in `scenes/hub2.tscn`): swaps each glb mesh for its bake,
  puts the ShaderMaterial on as `material_override` (AirframeLook leaves it alone, so it shows under
  every look), adds the decals as one `WearDecals` MeshInstance3D.

## Numbers

`Cylinder_005` 6072 -> ~638 000 verts (3.9 MB file), `Cube` 240 -> 360. Bake takes ~20-35 s headless.

## Tests / probes

`tests/test_hub2_wear.gd` (bake data on a box, a seam between two boxes, scene wiring, collision
untouched, decals visual-only, sheet deterministic with glow). `tests/test_hub2.gd` updated (no cel
ground node; the spawn tests now follow the spawn empty, which the user moved after the first build).
Probe: `tests/_probe_hub2_wear_shot.gd` (windowed shots at world positions).

## Tuning knobs

`wear` (0 clean .. 1.5) and the palette uniforms on the surface material; `DENSITY_*` / `CAP` in
the bake tool; `grime_height`. Rust was cut back once after the first probe shot (a vertical rust
stripe in every wall corner read as too much).

## Pass 2 (2026-11-13)

Decal placement is now rule-based plus hand-placed key spots (see the worklog 2026-11-13). Knobs moved from
`DENSITY_*` / `CAP` to `GRID_U`, `REACH_*`, `MAX_*` and `KEY_SPOTS` in `scripts/hub2_wear_bake.gd`.
