# Ichi snowstorm

Status: built 2026-10-12; turned into a blizzard 2026-10-14 (see Blizzard), not yet played.

Ambience for `scenes/operation_ichi.tscn` (and so `Ichi.tscn`) only: the player trudges through a
snowstorm toward the building. Visuals only: no sound, no movement change, no trudge animation
(the user will make that later).

## Decisions (grilled 2026-10-12)

| # | Question | Decision |
|---|----------|----------|
| 1 | Visibility | Fixed fog, about 100 m (98% fog at 100 m). Not a fog that thins near the building |
| 2 | Light | Overcast: sun 0.7 -> 0.25 energy, cool grey-white, softer shadows; ambient blue-grey and dimmer |
| 3 | Fog colour | Two-tone, distance-driven, Valheim-style: deep blue near, blending to purple at the wall. Sky horizon matches the far colour |
| 4 | Snow | Hard near-horizontal wind (about 15 degrees down) from the side, streaked flakes, two layers (fine + near/large), gusts every 6-10 s |
| 5 | Gameplay | None. Movement is untouched |
| 6 | Sky | Own flat gradient (dim blue top to purple horizon), no sun disc or clouds. `cel_sky.tres` is untouched |

Defaults not asked: no settings toggle (always on in this scene); every value is an export on the
`Storm` node.

## How it works

- `scripts/rendering/storm.gd` (`Storm`): builds the fog quad and both snow meshes in code.
- `shaders/storm/storm_fog.gdshader`: a full-screen quad (`POSITION = vec4(VERTEX.xy, 1, 1)`)
  that reads the depth texture, reconstructs view distance and blends `near_color` -> `far_color`
  with `1 - exp(-3.9 t^2)`. Sky pixels (depth 0) are discarded so the sky shows through.
  Godot's own fog is off in this scene's Environment (it has one colour).
- `shaders/storm/storm_snow.gdshader`: every flake is a quad positioned from TIME in the vertex
  shader, wrapped into a camera-centred box, stretched along its velocity. Gusts live in the
  displacement integral, so streak length follows the wind. Fades at the box edge, close to the
  camera, and with the fog.
- Both read the rendering camera, so they work under PixelWorld's copied camera.
- Known look: facing along the wind, the streaks fan out from the screen centre (a hyperspace
  read). Shorter `streak_time` softens it.
- `operation_ichi.tscn`: ProceduralSkyMaterial sky, Sun `sky_mode` light-only, ambient, no
  built-in fog.

## Blizzard (grilled + built 2026-10-14, not yet played)

"Normal snowfall" -> a blizzard. Replaces the storm above; the table above is the original
storm, the values here are the live defaults.

| # | Question | Decision |
|---|----------|----------|
| 1 | Visibility | 98% fog at 40 m (was 100 m) |
| 2 | Fog colour | Still two-tone, but pale: blue-grey near `(0.52, 0.58, 0.68)`, lavender-white far `(0.80, 0.77, 0.86)` (was `(0.20, 0.30, 0.52)` / `(0.46, 0.38, 0.62)`). Sky horizon + ground colours match far |
| 3 | Wind | 28 m/s mean (was 18), gusts +-60% (was 50%), 10 degrees down: `fall_ratio` 0.18 (was 0.27) |
| 4 | Snow | Fine: 20,000 in a 50 m box (was 12,000 in 80 m). Near: 2,400 (was 1,200) |
| 5 | Gust whiteout | Visibility closes from 40 m to `gust_visibility` 25 m at a gust's peak, on the snow's own gust curve |
| 6 | Ground drift | New `Drift` layer: 3,000 faint low streaks hugging the surface |
| 7 | Light | Light touch: sun 0.25 -> 0.18, ambient `(0.30, 0.35, 0.50)` -> `(0.45, 0.48, 0.58)`, sky top `(0.18, 0.24, 0.42)` -> `(0.55, 0.60, 0.70)` |
| 8 | Gameplay | None, still visuals only |
| 9 | Lens effects | None (the near flakes do that job in-world) |
| 10 | Old storm | Replaced, no toggle; the old values are the "was" numbers in this table |

- `shaders/storm/storm_gust.gdshaderinc`: the gust curve, its integral, and `storm_visibility()`.
  Both the fog and the snow include it, so the whiteout and the gust speed-up are one event, and
  the snow fades against the same moving wall as the fog.
- Drift is `storm_snow.gdshader` with `drift = true`: wraps in XZ only, no fall, sits
  `0.04 + h^2 * drift_height` (0.5 m) over the roof map's height at the flake (ground, rooftops,
  the ship's `storm_roof` boxes), snakes sideways along the wind, and is cut into wandering ribbons
  across the wind. Streak time 0.08 s (falling snow 0.04 s), width 0.12, opacity 0.3, at
  `drift_calm` 40% of that between gusts and 100% at a peak. Under a roof the top surface is the
  roof, so there is no drift indoors. No map (headless, or off the map) = no drift.
- Ink fog (2026-10-14, after the first look: "barely be able to see the building from the
  ship"): the building's faces were already 98% fog at ~147 m; the black ink was what showed,
  because the hull outline drawn over sky pixels is out of the fog quad's reach and the crease
  ink draws after it. The fog now lives in `storm_*` shader globals (project.godot, read through
  `shaders/storm/storm_fog.gdshaderinc`), and `outline.gdshader` / `crease.gdshader` fog their
  own ink with the same curve and gust wall. Ink keeps `ink_floor` (0.1) of its darkness, so far
  silhouettes linger as faint ghosts. `storm_fog` is 0 outside the storm (`Storm._exit_tree`
  resets it), so other scenes' ink is unchanged.
- Sky `sky_curve` 0.12 -> 0.5: the sky stays the fog's far colour well above the horizon, so a
  fogged building no longer reads as a pale cut-out against a greyer sky.
- Cost (`tests/_probe_ichi_fps.gd`, windowed, outside): snow 0.01 ms -> about 0.57 ms GPU;
  whole frame 4.16 -> 4.70 ms.

## Snow shelter (grilled + built 2026-10-13, not yet played)

The snow fell inside the building: the flakes are a camera-centred box with no idea of the world.

| # | Question | Decision |
|---|----------|----------|
| 1 | Mechanism | A roof map (not hand-placed indoor boxes, not a camera trigger that kills the whole storm) |
| 2 | Direction | Straight down, not along the wind: indoors means no snow, no lee-side bare strips outside |
| 3 | Fog indoors | Untouched; only the snow changes |

- At load `Storm` renders the static level from straight above, once, into a `shelter_resolution`
  (2048) square HDR SubViewport with its own World3D, through `shaders/storm/storm_roof_bake.gdshader`
  (writes world height split over R/G, A = geometry). The map covers the level's XZ bounds: OP_1 is
  858 m, so about 0.42 m per pixel. It is read back to an Image and the viewport freed.
- "Static level" = every MeshInstance3D with a StaticBody3D child, i.e. what `map_import.gd`'s
  trimesh collision marks (`Storm.level_meshes`). The pilot, VFX, fog and snow are never baked.
- `storm_snow.gdshader` decodes the height over each flake's centre; a flake more than
  `shelter_margin` (0.3 m) below it collapses to a point. Hard cut, no fade. Flakes on an open
  rooftop or in a courtyard still fall. Off the map: snow.
- Any overhang shelters, including open-sided ones (accepted).
- `Storm.roof_height(xz)` / `is_sheltered(point)` do the same decode on the CPU.
- Headless the bake is skipped (dummy renderer), so the shelter is off in tests.
- Checked windowed by `tests/_probe_storm_shelter.gd`: 981 straight-down physics rays against the
  baked map, worst error 1.8 m on a single edge pixel, the rest under 1 m; a shot from under the
  big roof shows no snow inside and the storm still blowing past the open end.

## Known gaps

- PIXEL look swaps in PixelLook's own environment; the storm fog and snow still draw on top, but
  its lighting is not overcast. Only CEL is tuned.

## Tests

`tests/test_ichi_snowstorm.gd` (shaders compile, the mesh contract, the scene's setup, the roof
map decode and sheltered test on a hand-made map, the bake's mesh list is OP_1 only).
`tests/_probe_storm_shot.gd` saves the game camera's view windowed.
